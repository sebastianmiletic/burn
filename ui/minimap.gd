class_name Minimap
extends Control
## Top-left circular minimap. The terrain comes from GameWorld.map_image(dim)
## (1 px = 4 m overworld); live markers are drawn on top. The map turns with
## the view so "up" is always where you are looking; the N marker orbits the
## rim.

const SHADER := preload("res://ui/shaders/minimap.gdshader")
const RADIUS_METRES := 96.0
const KIND_GLYPHS := {
	0: "■", 1: "▲", 2: "▲", 3: "Ω", 4: "†", 5: "*", 6: "i", 7: "◆", 8: "Ω", 9: "▲", 10: "♛",
}

var dimension := 0
var metres_per_pixel := 4.0
var zoom := 1.0

var _map_rect: ColorRect
var _overlay: Control
var _mat := ShaderMaterial.new()
var _tex: ImageTexture
var _image_id := 0
var _poll := 0.0
var _angle := 0.0
var _player_pos := Vector3.ZERO
var _markers: Array = []   # [Vector2 screen offset (unit circle), glyph, colour, size]
var _time := 0.0
var _cave_poll := 0.0
var _cave_tex: ImageTexture
var _cave_center := Vector3.ZERO
var _readout: Label


func _ready() -> void:
	custom_minimum_size = Vector2(176, 176)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat.shader = SHADER
	_map_rect = ColorRect.new()
	_map_rect.material = _mat
	_map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_rect.position = Vector2(8, 8)
	add_child(_map_rect)
	# Markers must draw above the map, and a parent's _draw is under its children.
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_readout = UiTheme.label("", 10, UiTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_readout)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	_map_rect.position = Vector2(8, 8)
	_map_rect.size = size - Vector2(16, 16)
	_overlay.position = Vector2.ZERO
	_overlay.size = size
	_readout.position = Vector2(0, size.y + 3)
	_readout.size = Vector2(size.x, 18)


func _process(delta: float) -> void:
	_time += delta
	_mat.set_shader_parameter(&"time", _time)
	var world := UiContext.world()
	var player := UiContext.player()
	if world == null or player == null:
		_overlay.queue_redraw()
		return
	var dim_v: Variant = player.get("dimension")
	dimension = int(dim_v) if dim_v != null else 0
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.5
		_refresh_image(world)
	_player_pos = (player as Node3D).global_position
	var yaw: float = UiContext.call_on(world, "camera_yaw", [], player.get("yaw") if player.get("yaw") != null else 0.0)
	_angle = lerp_angle(_angle, yaw, 1.0 - exp(-delta * 12.0))
	var world_size := float(_tex.get_width()) * metres_per_pixel if _tex != null else 2048.0
	_mat.set_shader_parameter(&"center_uv", Vector2(_player_pos.x, _player_pos.z) / world_size)
	_mat.set_shader_parameter(&"span", RADIUS_METRES * 2.0 * zoom / world_size)
	_mat.set_shader_parameter(&"angle", _angle)
	_mat.set_shader_parameter(&"style", 0 if int(UiContext.setting("graphics", "style")) == 0 else 1)
	var surface: Variant = UiContext.call_on(world, "surface_height_at", [_player_pos.x, _player_pos.z], null)
	var under := 0.0
	if surface != null:
		under = clampf((float(surface) - _player_pos.y - 6.0) / 12.0, 0.0, 1.0)
	_mat.set_shader_parameter(&"underground", under)
	_cave_poll -= delta
	var cave_mode := under > 0.5 and world is GameWorld
	_mat.set_shader_parameter(&"cave_mode", cave_mode)
	if cave_mode:
		if _cave_poll <= 0:
			_cave_poll = 1.0
			_cave_center = _player_pos
			var image := MapImage.cave_slice((world as GameWorld).world_for(dimension), _cave_center)
			if _cave_tex == null:
				_cave_tex = ImageTexture.create_from_image(image)
			else:
				_cave_tex.update(image)
			_mat.set_shader_parameter(&"cave_tex", _cave_tex)
		_mat.set_shader_parameter(&"cave_offset", Vector2(_player_pos.x - _cave_center.x, _player_pos.z - _cave_center.z) / 192.0)
	_readout.text = "%s  %dm  |  Y %d" % ["CAVE" if cave_mode else "RANGE", int(RADIUS_METRES * zoom), int(_player_pos.y)]
	_collect_markers(world, player)
	queue_redraw()
	_overlay.queue_redraw()


func _refresh_image(world: Node) -> void:
	var img: Variant = UiContext.call_on(world, "map_image", [dimension], null)
	if not (img is Image):
		_mat.set_shader_parameter(&"has_map", false)
		return
	var image: Image = img
	var mpp: Variant = UiContext.call_on(world, "map_metres_per_pixel", [dimension], 4.0)
	metres_per_pixel = float(mpp)
	var id := image.get_instance_id() ^ image.get_width()
	if _tex == null or id != _image_id or _tex.get_width() != image.get_width():
		_tex = ImageTexture.create_from_image(image)
		_image_id = id
	# The world image is immutable: do not re-upload megabytes every half second.
	_mat.set_shader_parameter(&"map_tex", _tex)
	_mat.set_shader_parameter(&"has_map", true)


## World position -> offset inside the unit circle (may be outside for clamping).
func _to_circle(p: Vector3) -> Vector2:
	var d := Vector2(p.x - _player_pos.x, p.z - _player_pos.z) / (RADIUS_METRES * zoom)
	return d.rotated(_angle)


func _collect_markers(world: Node, player: Object) -> void:
	_markers.clear()
	if world is GameWorld:
		var gw := world as GameWorld
		# Quest objectives, hand-ins and activities (QuestLog.markers()).
		const ICONS := {"treasure": ["✕", Color(1.0, 0.85, 0.4)], "bounty": ["†", Color(1.0, 0.55, 0.3)], "star": ["⊕", Color(0.65, 0.78, 1.0)],
			"raid": ["▲", Color(0.95, 0.3, 0.25)], "ring": ["◎", Color(1.0, 0.65, 0.35)], "hart": ["◇", Color(1.0, 0.88, 0.45)]}
		for m: Dictionary in gw.quests.markers():
			if int(m.get("dim", 0)) != dimension:
				continue
			var icon: Array = ICONS.get(String(m.get("icon", "")), ["!" if m.get("kind", "") != "turn_in" else "?", UiTheme.FROST])
			_markers.append([_to_circle(m["pos"]), icon[0], icon[1], 16 if m.get("kind", "") != "activity" else 14, true])
	var discovered: Variant = world.get("discovered")
	var locs: Variant = UiContext.call_on(world, "locations", [dimension], [])
	if locs is Array:
		for loc: Object in locs:
			if loc == null:
				continue
			var id: Variant = loc.get("id")
			if discovered is Dictionary and not (discovered as Dictionary).has(id):
				continue
			var c := _to_circle(loc.get("center"))
			var kind := int(loc.get("kind"))
			var major: bool = loc.get("major") == true
			_markers.append([c, str(KIND_GLYPHS.get(kind, "◆")), UiTheme.ACCENT_HOT if major else UiTheme.ACCENT_DIM, 13 if major else 10, true])
	var enemies: Variant = UiContext.call_on(world, "entities_near", [_player_pos, RADIUS_METRES * zoom, dimension, 1], [])
	if enemies is Array:
		for e: Object in enemies:
			if e == null or e.get("dead") == true:
				continue
			if absf((e as Node3D).global_position.y - _player_pos.y) > 24.0:
				continue  # Do not show surface enemies as if they occupied a cave.
			var is_boss: bool = e.has_method("is_boss") and e.call("is_boss")
			_markers.append([_to_circle((e as Node3D).global_position), "◆" if is_boss else "•", UiTheme.DANGER, 14 if is_boss else 11, false])
	var players: Variant = UiContext.call_on(world, "players_in", [dimension], [])
	if players is Array:
		for p: Object in players:
			if p == null or p == player:
				continue
			_markers.append([_to_circle((p as Node3D).global_position), "▲", UiTheme.FROST, 12, true])


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 8.0
	# Rim: double ring with ticks.
	draw_circle(c, r + 6.0, Color(0, 0, 0, 0.75))
	draw_arc(c, r + 1.5, 0, TAU, 96, UiTheme.BORDER, 1.0, true)
	draw_arc(c, r + 5.5, 0, TAU, 96, UiTheme.ACCENT_DIM, 1.0, true)
	for i in 36:
		var a := TAU * i / 36.0 + _angle
		var len := 4.0 if i % 9 == 0 else 2.0
		var dir := Vector2(sin(a), -cos(a))
		draw_line(c + dir * (r + 1.5), c + dir * (r + 1.5 + len), UiTheme.ACCENT_DIM if i % 9 else UiTheme.ACCENT, 1.0)



func _draw_overlay() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 8.0
	var font := UiTheme.MONO_BOLD
	# Cardinal letters orbit the rim.
	for card: Array in [["N", 0.0, UiTheme.ACCENT_HOT], ["E", PI * 0.5, UiTheme.TEXT_DIM], ["S", PI, UiTheme.TEXT_DIM], ["W", PI * 1.5, UiTheme.TEXT_DIM]]:
		var a: float = card[1] + _angle
		var pos := c + Vector2(sin(a), -cos(a)) * (r + 0.5)
		var fs := 12 if card[0] == "N" else 10
		_overlay.draw_circle(pos, 8.0, Color(0.02, 0.015, 0.012))
		var tsz := font.get_string_size(card[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		_overlay.draw_string(font, pos + Vector2(-tsz.x * 0.5, fs * 0.36), card[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, card[2])
	# Markers (locations clamp to the rim so you can steer toward them).
	for m: Array in _markers:
		var off: Vector2 = m[0]
		var at_rim := false
		if off.length() > 0.92:
			if not m[4]:
				continue
			off = off.normalized() * 0.92
			at_rim = true
		var pos := c + off * r
		var fs: int = m[3]
		var g: String = m[1]
		var tsz := font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var col: Color = m[2]
		if at_rim:
			col.a = 0.6
		_overlay.draw_string_outline(font, pos + Vector2(-tsz.x * 0.5, fs * 0.35), g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.85 * col.a))
		_overlay.draw_string(font, pos + Vector2(-tsz.x * 0.5, fs * 0.35), g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	# The player: an arrow pointing up (the view direction).
	var tip := c + Vector2(0, -9)
	var arrow := PackedVector2Array([tip, c + Vector2(6, 7), c + Vector2(0, 3), c + Vector2(-6, 7)])
	_overlay.draw_colored_polygon(arrow, UiTheme.ACCENT_HOT)
	_overlay.draw_polyline(arrow + PackedVector2Array([tip]), Color(0, 0, 0, 0.8), 1.0, true)
	# View cone.
	var cone := PackedVector2Array([c, c + Vector2(-0.42, -1).normalized() * r * 0.55, c + Vector2(0.42, -1).normalized() * r * 0.55])
	_overlay.draw_colored_polygon(cone, Color(1, 0.7, 0.3, 0.07))
