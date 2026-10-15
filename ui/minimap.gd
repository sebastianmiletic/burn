class_name Minimap
extends Control
## Top-left circular minimap. The terrain is the shared map renderer
## (ui/shaders/map_common.gdshaderinc: hillshade, water, roads, buildings,
## fog of war) rotated so "up" is where you are looking. Discovered places
## and bosses show as vector symbols (MapIcons), the tracked objective as a
## gold marker that sticks to the rim when it is out of range.
## While on foot it also uncovers the fog of war (MapFog) around the player.

const SHADER := preload("res://ui/shaders/minimap.gdshader")
const RADIUS_METRES := 110.0
const FOG_SAVE_SECONDS := 12.0

var dimension := 0
var zoom := 1.0
var _zoom_target := 1.0

var _map_rect: ColorRect
var _overlay: Control
var _mat := ShaderMaterial.new()
var _layers: MapLayers
var _fog: MapFog
var _fog_save := FOG_SAVE_SECONDS
var _angle := 0.0
var _player_pos := Vector3.ZERO
var _places: Array = []    # [Vector2 unit offset, place Dictionary]
var _quests: Array = []    # [Vector2 unit offset, point Dictionary] (QuestMarkers.points)
var _enemies: Array = []   # [Vector2 unit offset, is_boss]
var _mates: Array = []     # [Vector2 unit offset, colour, yaw, downed]
var _time := 0.0
var _cave_poll := 0.0
var _cave_tex: ImageTexture
var _cave_center := Vector3.ZERO
var _cave := false
var _readout: Label


func _ready() -> void:
	custom_minimum_size = Vector2(196, 196)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat.shader = SHADER
	_map_rect = ColorRect.new()
	_map_rect.material = _mat
	_map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	tree_exiting.connect(func() -> void:
		if _fog != null:
			_fog.save_file())
	_layout()


func _layout() -> void:
	_map_rect.position = Vector2(10, 10)
	_map_rect.size = size - Vector2(20, 20)
	_overlay.position = Vector2.ZERO
	_overlay.size = size
	_readout.position = Vector2(0, size.y + 2)
	_readout.size = Vector2(size.x, 16)


## Smoothly change the visible range (1 = default; < 1 closer).
func set_zoom(z: float) -> void:
	_zoom_target = clampf(z, 0.35, 4.0)


func _radius() -> float:
	return minf(size.x, size.y) * 0.5 - 10.0


func _process(delta: float) -> void:
	_time += delta
	_mat.set_shader_parameter(&"time", _time)
	var world := UiContext.world()
	var player := UiContext.player()
	if world == null or player == null:
		_overlay.queue_redraw()
		return
	var dim_v: Variant = player.get("dimension")
	var dim := int(dim_v) if dim_v != null else 0
	if dim != dimension or _layers == null:
		dimension = dim
		_layers = MapLayers.of(world, dimension)
		_mat.set_shader_parameter(&"has_map", _layers != null)
		if _layers != null:
			_layers.apply(_mat)
	_player_pos = (player as Node3D).global_position
	var yaw_v: Variant = player.get("yaw")
	var yaw: float = UiContext.call_on(world, "camera_yaw", [], yaw_v if yaw_v != null else 0.0)
	_angle = lerp_angle(_angle, yaw, 1.0 - exp(-delta * 14.0))
	if _layers == null:
		_overlay.queue_redraw()
		return
	# Fog of war: uncover around the player, upload changes, save now and then.
	if _fog == null:
		_fog = MapFog.of(world)
	if _fog != null:
		_fog.reveal(dimension, _player_pos)
		_mat.set_shader_parameter(&"fog_tex", _fog.texture(dimension))
		_mat.set_shader_parameter(&"has_fog", true)
		_fog_save -= delta
		if _fog_save <= 0.0:
			_fog_save = FOG_SAVE_SECONDS
			_fog.save_file()
	var surface: Variant = UiContext.call_on(world, "surface_height_at", [_player_pos.x, _player_pos.z], null)
	var under := 0.0
	if surface != null:
		under = clampf((float(surface) - _player_pos.y - 6.0) / 12.0, 0.0, 1.0)
	_cave = under > 0.5 and world is GameWorld
	_zoom_target = 0.6 if _cave else 1.0
	zoom = lerpf(zoom, _zoom_target, 1.0 - exp(-delta * 4.0))
	_mat.set_shader_parameter(&"center_uv", _layers.uv(_player_pos))
	_mat.set_shader_parameter(&"span", RADIUS_METRES * 2.0 * zoom / _layers.world_size)
	_mat.set_shader_parameter(&"angle", _angle)
	_mat.set_shader_parameter(&"underground", under)
	_mat.set_shader_parameter(&"cave_mode", _cave)
	_cave_poll -= delta
	if _cave:
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
	_readout.text = "%s  ·  %d m  ·  Y %d" % ["CAVE" if _cave else "SURFACE", int(RADIUS_METRES * zoom), int(_player_pos.y)]
	_collect_markers(world, player)
	queue_redraw()
	_overlay.queue_redraw()


## World position -> offset in the unit circle (may be outside for clamping).
func _to_circle(p: Vector3) -> Vector2:
	var d := Vector2(p.x - _player_pos.x, p.z - _player_pos.z) / (RADIUS_METRES * zoom)
	return d.rotated(_angle)


func _collect_markers(world: Node, player: Object) -> void:
	_places.clear()
	_quests.clear()
	_enemies.clear()
	_mates.clear()
	# Quest objectives, hand-ins and activities (QuestLog.markers()); untracked
	# quests stay off the minimap (the world map shows them).
	for pt: Dictionary in QuestMarkers.points(world):
		if int(pt.get("dim", 0)) != dimension or not pt.get("tracked", true):
			continue
		_quests.append([_to_circle(pt["pos"]), pt])
	var discovered: Variant = world.get("discovered")
	var locs: Variant = UiContext.call_on(world, "locations", [dimension], [])
	if locs is Array:
		for loc: Object in locs:
			if loc == null:
				continue
			if discovered is Dictionary and not (discovered as Dictionary).has(loc.get("id")):
				continue
			var c := _to_circle(loc.get("center"))
			if c.length() > 1.25 and loc.get("major") != true and MapIcons.boss_of(loc) == "":
				continue
			_places.append([c, MapIcons.place_of(world, loc)])
	var enemies: Variant = UiContext.call_on(world, "entities_near", [_player_pos, RADIUS_METRES * zoom, dimension, 1], [])
	if enemies is Array:
		for e: Object in enemies:
			if e == null or e.get("dead") == true:
				continue
			if absf((e as Node3D).global_position.y - _player_pos.y) > 24.0:
				continue  # Do not show surface enemies as if they occupied a cave.
			var is_boss: bool = (e.has_method("is_boss") and e.call("is_boss")) or (e.has_meta("boss") and e.get_meta("boss") == true)
			_enemies.append([_to_circle((e as Node3D).global_position), is_boss])
	var players: Variant = UiContext.call_on(world, "players_in", [dimension], [])
	if players is Array:
		var net := UiContext.net()
		for p: Object in players:
			if p == null or p == player:
				continue
			var col := UiTheme.FROST
			var peer: Variant = p.get("peer_id")
			if net != null and peer != null:
				col = UiContext.call_on(net, "player_color", [int(peer)], col)
			var pyaw: Variant = p.get("yaw")
			var downed: bool = p.get("downed") == true or p.get("dead") == true
			_mates.append([_to_circle((p as Node3D).global_position), col, float(pyaw) if pyaw != null else 0.0, downed])


func _draw() -> void:
	var c := size * 0.5
	var r := _radius()
	# Bezel: soft shadow, dark ring, fine gold hairlines and ticks.
	draw_circle(c, r + 9.0, Color(0, 0, 0, 0.35), true, -1.0, true)
	draw_circle(c, r + 7.0, Color(0.035, 0.028, 0.026, 0.96), true, -1.0, true)
	draw_arc(c, r + 0.8, 0, TAU, 128, Color(0.78, 0.6, 0.36, 0.9), 1.4, true)
	draw_arc(c, r + 6.6, 0, TAU, 128, Color(0.5, 0.38, 0.24, 0.8), 1.0, true)
	for i in 72:
		var a := TAU * i / 72.0 + _angle
		var major := i % 18 == 0
		var mid := i % 6 == 0
		var dir := Vector2(sin(a), -cos(a))
		var l0 := r + 2.2
		var l1 := r + (5.6 if major else (4.2 if mid else 3.2))
		draw_line(c + dir * l0, c + dir * l1, Color(0.8, 0.62, 0.38, 0.85 if (major or mid) else 0.4), 1.0, true)


func _draw_overlay() -> void:
	var c := size * 0.5
	var r := _radius()
	var ci := _overlay
	# Places (bosses and major places stay on the rim when out of range).
	for entry: Array in _places:
		var off: Vector2 = entry[0]
		var place: Dictionary = entry[1]
		var important: bool = place.get("major", false) or String(place.get("boss", "")) != ""
		var at_rim := off.length() > 0.86
		if at_rim:
			if not important:
				continue
			off = off.normalized() * 0.86
		var big := String(place.get("boss", "")) != ""
		MapIcons.draw_place(ci, place, c + off * r, 8.5 if big else 6.5, at_rim)
	# Enemies.
	for e: Array in _enemies:
		var off: Vector2 = e[0]
		if off.length() > 0.95:
			continue
		var pos := c + off * r
		if e[1]:
			var pulse := 0.5 + 0.5 * sin(_time * 5.0)
			ci.draw_arc(pos, 6.0 + pulse * 2.0, 0, TAU, 20, Color(1, 0.25, 0.18, 0.6), 1.5, true)
			ci.draw_circle(pos, 3.6, Color(1, 0.3, 0.2), true, -1.0, true)
		else:
			ci.draw_circle(pos, 3.2, Color(0, 0, 0, 0.7), true, -1.0, true)
			ci.draw_circle(pos, 2.3, Color(0.95, 0.27, 0.2), true, -1.0, true)
	# Companions: chevrons in their colour; a pulsing cross when they are down.
	for m: Array in _mates:
		var off: Vector2 = m[0]
		var at_rim := off.length() > 0.9
		if at_rim:
			off = off.normalized() * 0.9
		var pos := c + off * r
		if m[3]:
			var pulse := 0.5 + 0.5 * sin(_time * 6.0)
			ci.draw_circle(pos, 7.0, Color(0, 0, 0, 0.7), true, -1.0, true)
			ci.draw_arc(pos, 7.0 + pulse * 3.0, 0, TAU, 20, Color(1, 0.3, 0.25, 0.8 - pulse * 0.5), 1.5, true)
			ci.draw_line(pos + Vector2(0, -4.5), pos + Vector2(0, 4.5), Color(1, 0.35, 0.28), 2.4, true)
			ci.draw_line(pos + Vector2(-4.5, 0), pos + Vector2(4.5, 0), Color(1, 0.35, 0.28), 2.4, true)
		else:
			_chevron(ci, pos, _angle - float(m[2]), 6.0, m[1], 0.6 if at_rim else 1.0)
	# Objectives and activities on top: they matter most. Search areas first.
	var m_per_unit := RADIUS_METRES * zoom
	for e: Array in _quests:
		var pt: Dictionary = e[1]
		var rad := float(pt.get("radius", 0.0))
		if rad > 0.0 and (e[0] as Vector2).length() < 1.2:
			MapIcons.draw_area(ci, pt, c + (e[0] as Vector2) * r, rad / m_per_unit * r)
	var order := _quests.duplicate()
	order.sort_custom(func(x: Array, y: Array) -> bool: return float(x[1].get("priority", 1.0)) < float(y[1].get("priority", 1.0)))
	for e: Array in order:
		var off: Vector2 = e[0]
		var at_rim := off.length() > 0.84
		if at_rim:
			off = off.normalized() * 0.84
		var quest_kind := String(e[1].get("kind", "")) in ["main", "side", "turn_in"]
		MapIcons.draw_point(ci, e[1], c + off * r, 7.5 if quest_kind else 7.0, _time, at_rim)
	# Cardinal letters ride the bezel.
	var font := UiTheme.title_font(700)
	for card: Array in [["N", 0.0], ["E", PI * 0.5], ["S", PI], ["W", PI * 1.5]]:
		var a: float = card[1] + _angle
		var pos := c + Vector2(sin(a), -cos(a)) * (r + 3.5)
		var north: bool = card[0] == "N"
		var fs := 13 if north else 10
		ci.draw_circle(pos, 8.5 if north else 7.0, Color(0.035, 0.028, 0.026), true, -1.0, true)
		if north:
			ci.draw_arc(pos, 8.5, 0, TAU, 24, Color(0.86, 0.3, 0.2), 1.2, true)
		var tsz := font.get_string_size(card[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		ci.draw_string(font, pos + Vector2(-tsz.x * 0.5, fs * 0.36), card[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(1, 0.82, 0.55) if north else UiTheme.TEXT_DIM)
	# View cone and the player's arrow (always pointing up: the map turns).
	var cone := PackedVector2Array([c])
	for i in 9:
		var a := lerpf(-0.42, 0.42, i / 8.0)
		cone.append(c + Vector2(sin(a), -cos(a)) * r * 0.62)
	var cols := PackedColorArray([Color(1, 0.78, 0.45, 0.16)])
	for i in 9:
		cols.append(Color(1, 0.78, 0.45, 0.0))
	ci.draw_polygon(cone, cols)
	_chevron(ci, c, 0.0, 8.5, Color(1, 0.86, 0.55), 1.0)


## A navigation chevron pointing along `angle` (0 = up), outlined.
static func _chevron(ci: CanvasItem, at: Vector2, angle: float, s: float, col: Color, alpha: float) -> void:
	var pts := PackedVector2Array([Vector2(0, -1.15), Vector2(0.8, 0.85), Vector2(0, 0.42), Vector2(-0.8, 0.85)])
	for i in pts.size():
		pts[i] = at + pts[i].rotated(angle) * s
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, Color(0, 0, 0, 0.85 * alpha), 3.0, true)
	var fill := col
	fill.a *= alpha
	ci.draw_colored_polygon(pts, fill)
	ci.draw_polyline(closed, fill, 1.0, true)
