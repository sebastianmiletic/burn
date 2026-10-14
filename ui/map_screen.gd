class_name MapScreen
extends UiModal
## Full world map. Mouse wheel zooms, drag pans, Space recentres on you.

const SHADER := preload("res://ui/shaders/world_map.gdshader")

var _view: Control
var _map: TextureRect
var _overlay: Control
var _mat := ShaderMaterial.new()
var _tex: ImageTexture
var _zoom := 1.0
var _center := Vector2(0.5, 0.5)  # map uv at the view centre
var _dragging := false
var _metres_per_pixel := 4.0
var _dim := 0
var _title: Label


func _init() -> void:
	panel_size = Vector2(1000, 680)
	panel_title = "MAP"


func _build() -> void:
	_title = UiTheme.title("", 18, UiTheme.ACCENT_HOT, 700)
	content.add_child(_title)
	_view = Control.new()
	_view.clip_contents = true
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.gui_input.connect(_on_view_input)
	content.add_child(_view)
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.01, 0.008)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.add_child(bg)
	_map = TextureRect.new()
	_map.stretch_mode = TextureRect.STRETCH_SCALE
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_mat.shader = SHADER
	_map.material = _mat
	_view.add_child(_map)
	_overlay = MapOverlay.new()
	_overlay.screen = self
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.add_child(_overlay)
	var foot := HBoxContainer.new()
	foot.add_child(UiTheme.label("wheel · zoom    drag · pan    space · centre on you    esc · close", 11, UiTheme.TEXT_FAINT))
	content.add_child(foot)


func _on_open() -> void:
	var world := UiContext.world()
	var player := UiContext.player()
	_dim = int(player.get("dimension")) if player != null and player.get("dimension") != null else 0
	var img: Variant = UiContext.call_on(world, "map_image", [_dim], null)
	if img is Image:
		_tex = ImageTexture.create_from_image(img)
		_map.texture = _tex
	_metres_per_pixel = float(UiContext.call_on(world, "map_metres_per_pixel", [_dim], 4.0))
	_title.text = "THE ASHEN ISLE" if _dim == 0 else "THE UNDERWORLD"
	_zoom = 2.0
	_recentre()


func _recentre() -> void:
	var player := UiContext.player()
	if player != null and _tex != null:
		var p := (player as Node3D).global_position
		_center = Vector2(p.x, p.z) / (_tex.get_width() * _metres_per_pixel)


func world_size() -> float:
	return (_tex.get_width() * _metres_per_pixel) if _tex != null else 2048.0


## Map uv -> position inside the view, given zoom and centre.
func uv_to_view(uv: Vector2) -> Vector2:
	var side := minf(_view.size.x, _view.size.y) * _zoom
	return _view.size * 0.5 + (uv - _center) * side


func world_to_view(p: Vector3) -> Vector2:
	return uv_to_view(Vector2(p.x, p.z) / world_size())


func _process(_delta: float) -> void:
	if not is_open:
		return
	var side := minf(_view.size.x, _view.size.y) * _zoom
	_map.size = Vector2(side, side)
	_map.position = uv_to_view(Vector2.ZERO)
	_mat.set_shader_parameter(&"cells", side / 5.0)
	_overlay.queue_redraw()


func _on_view_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.15)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
	var mm := event as InputEventMouseMotion
	if mm != null and _dragging:
		var side := minf(_view.size.x, _view.size.y) * _zoom
		_center -= mm.relative / side


func _zoom_at(at: Vector2, factor: float) -> void:
	var side := minf(_view.size.x, _view.size.y) * _zoom
	var uv_at := _center + (at - _view.size * 0.5) / side
	_zoom = clampf(_zoom * factor, 0.8, 24.0)
	var new_side := minf(_view.size.x, _view.size.y) * _zoom
	_center = uv_at - (at - _view.size * 0.5) / new_side


func _unhandled_input(event: InputEvent) -> void:
	if is_open and event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_SPACE:
		_recentre()
		get_viewport().set_input_as_handled()
		return
	if is_open and event.is_action_pressed("map"):
		close()
		get_viewport().set_input_as_handled()
		return
	super(event)


## Draws location names and player markers above the map.
class MapOverlay:
	extends Control

	var screen: MapScreen

	func _draw() -> void:
		if screen == null:
			return
		var world := UiContext.world()
		var font := UiTheme.MONO
		var bold := UiTheme.MONO_BOLD
		var discovered: Variant = world.get("discovered") if world != null else null
		var locs: Variant = UiContext.call_on(world, "locations", [screen._dim], [])
		if locs is Array:
			for loc: Object in locs:
				if discovered is Dictionary and not (discovered as Dictionary).has(loc.get("id")):
					continue
				var pos := screen.world_to_view(loc.get("center"))
				if not Rect2(Vector2.ZERO, size).grow(40).has_point(pos):
					continue
				var major: bool = loc.get("major") == true
				var g := str(Minimap.KIND_GLYPHS.get(int(loc.get("kind")), "◆"))
				var col := UiTheme.ACCENT_HOT if major else UiTheme.ACCENT_DIM
				var gs := bold.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
				draw_string_outline(bold, pos + Vector2(-gs.x * 0.5, 6), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 3, Color(0, 0, 0, 0.8))
				draw_string(bold, pos + Vector2(-gs.x * 0.5, 6), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
				if major or screen._zoom > 3.0:
					var name := str(loc.get("name"))
					var fs := 13 if major else 11
					var ns := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
					var np := pos + Vector2(-ns.x * 0.5, 24)
					draw_string_outline(font, np, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.85))
					draw_string(font, np, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT if major else UiTheme.TEXT_DIM)
		var me := UiContext.player()
		var players: Variant = UiContext.call_on(world, "players_in", [screen._dim], [])
		if players is Array:
			for p: Object in players:
				if p == null or p == me:
					continue
				var pos := screen.world_to_view((p as Node3D).global_position)
				draw_circle(pos, 5.0, UiTheme.FROST)
				var pname := str(p.get("display_name")) if p.get("display_name") != null else ""
				draw_string(font, pos + Vector2(8, 4), pname, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.FROST)
		if me != null:
			var pos := screen.world_to_view((me as Node3D).global_position)
			var yaw: float = float(me.get("yaw")) if me.get("yaw") != null else 0.0
			var fwd := Vector2(-sin(yaw), -cos(yaw))
			var side := fwd.orthogonal()
			var arrow := PackedVector2Array([pos + fwd * 11.0, pos - fwd * 7.0 + side * 7.0, pos - fwd * 3.0, pos - fwd * 7.0 - side * 7.0])
			draw_colored_polygon(arrow, UiTheme.ACCENT_HOT)
			draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color(0, 0, 0), 1.5, true)
		# Scale bar.
		var metres := 250.0
		var px := screen.world_to_view(Vector3(metres, 0, 0)).x - screen.world_to_view(Vector3.ZERO).x
		var y := size.y - 18
		draw_line(Vector2(16, y), Vector2(16 + px, y), UiTheme.ACCENT, 2.0)
		draw_string(font, Vector2(16, y - 6), "%d m" % int(metres), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.TEXT_DIM)
