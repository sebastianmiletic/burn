class_name MapScreen
extends UiModal
## Full world map, drawn as an atlas sheet: relief and biome tints where you
## have been, the bare grey outline of the land where you have not (MapFog),
## region and sea names, place symbols (MapIcons), a lettered grid for
## calling out squares in co-op, a compass rose and a scale bar.
##
## Wheel or +/- zooms (smoothly, about the cursor), drag or WASD / arrows
## pans, Space recentres on you, click an objective in the side panel to fly
## to it. Right-click (or double-click) the map to place a marker; click one
## of your markers to rename, re-icon, recolour, share or delete it.

const SHADER := preload("res://ui/shaders/world_map.gdshader")
const SIDEBAR_W := 250.0
## The atlas grid: GRID x GRID squares over the whole world, A.. by 1..
const GRID := 12

var _view: Control
var _map: ColorRect
var _overlay: MapOverlay
var _mat := ShaderMaterial.new()
var _layers: MapLayers
var _zoom := 1.0
var _zoom_goal := 1.0
var _zoom_anchor := Vector2(-1, -1)   # view position kept fixed while zooming
var _center := Vector2(0.5, 0.5)      # map uv at the view centre
var _center_goal := Vector2(-1, -1)   # glide target (keyboard / focus_on)
var _velocity := Vector2.ZERO          # uv / s after a drag is released
var _dragging := false
var _drag_moved := 0.0
var _dim := 0
var _time := 0.0
var _title: Label
var _sub: Label
var _objectives: VBoxContainer
var _marker_list: VBoxContainer
var _marker_rev := -1
var _legend: Control
var _editor: MarkerEditor
var _pending_focus := Vector3.INF
var _pending_zoom := 0.0


func _init() -> void:
	panel_size = Vector2(1400, 860)
	panel_title = "MAP"
	scrim_alpha = 0.7


func _build() -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	_title = UiTheme.title("", 22, UiTheme.ACCENT_HOT, 700)
	head.add_child(_title)
	_sub = UiTheme.label("", UiTheme.SIZE_SMALL, UiTheme.TEXT_DIM)
	_sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_sub)
	content.add_child(head)
	content.add_child(UiTheme.spacer(4))

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)

	_view = Control.new()
	_view.clip_contents = true
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.gui_input.connect(_on_view_input)
	body.add_child(_view)
	_map = ColorRect.new()
	_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat.shader = SHADER
	_mat.set_shader_parameter(&"contour_strength", 0.14)
	_map.material = _mat
	_view.add_child(_map)
	_overlay = MapOverlay.new()
	_overlay.screen = self
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.add_child(_overlay)
	_editor = MarkerEditor.new()
	_editor.screen = self
	_editor.visible = false
	_view.add_child(_editor)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(SIDEBAR_W, 0)
	side.add_theme_constant_override("separation", 6)
	body.add_child(side)
	side.add_child(_heading("OBJECTIVES"))
	_objectives = VBoxContainer.new()
	_objectives.add_theme_constant_override("separation", 2)
	side.add_child(_objectives)
	side.add_child(UiTheme.spacer(6))
	side.add_child(_heading("MARKERS"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(SIDEBAR_W, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_marker_list = VBoxContainer.new()
	_marker_list.add_theme_constant_override("separation", 2)
	_marker_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_marker_list)
	side.add_child(scroll)
	side.add_child(UiTheme.spacer(6))
	side.add_child(_heading("LEGEND"))
	_legend = Legend.new()
	side.add_child(_legend)
	var hints := UiTheme.label("wheel / + −   zoom\ndrag / WASD   pan\nspace   centre on you\nright-click   place marker\nM / esc   close", 11, UiTheme.TEXT_FAINT)
	side.add_child(hints)


func _heading(text: String) -> Control:
	var l := UiTheme.title(text, 12, UiTheme.ACCENT_DIM, 700)
	l.add_theme_font_override("font", UiTheme.title_font_spaced(700, 3))
	return l


func _on_open() -> void:
	fit_panel(panel_size, Vector2(40, 36))
	var world := UiContext.world()
	var player := UiContext.player()
	_dim = int(player.get("dimension")) if player != null and player.get("dimension") != null else 0
	_layers = MapLayers.of(world, _dim)
	_mat.set_shader_parameter(&"has_map", _layers != null)
	if _layers != null:
		_layers.apply(_mat)
	var fog := MapFog.of(world)
	_mat.set_shader_parameter(&"has_fog", fog != null)
	if fog != null:
		if player != null:
			fog.reveal(_dim, (player as Node3D).global_position)
		_mat.set_shader_parameter(&"fog_tex", fog.texture(_dim))
	_title.text = ["THE ASHEN ISLE", "THE UNDERWORLD", "THE RYFT"][clampi(_dim, 0, 2)] if _dim <= 2 else "UNCHARTED WATERS"
	_velocity = Vector2.ZERO
	_center_goal = Vector2(-1, -1)
	_zoom_anchor = Vector2(-1, -1)
	_editor.visible = false
	if _pending_focus.is_finite():
		_center = _uv(_pending_focus)
		_zoom = _pending_zoom
		_pending_focus = Vector3.INF
	else:
		_zoom = 3.0
		_recentre(true)
	_zoom_goal = _zoom
	_rebuild_objectives()
	_marker_rev = -1


## Opens the map centred on a world position (quest log "show on map").
func focus_on(world_pos: Vector3, zoom := 4.0) -> void:
	_pending_focus = world_pos
	_pending_zoom = zoom
	if is_open:
		_center_goal = _uv(world_pos)
		_zoom_goal = zoom
		_pending_focus = Vector3.INF
	else:
		open()


func _uv(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z) / world_size()


func _recentre(instant := false) -> void:
	var player := UiContext.player()
	if player != null:
		var uv := _uv((player as Node3D).global_position)
		if instant:
			_center = uv
		else:
			_center_goal = uv


func world_size() -> float:
	return _layers.world_size if _layers != null else 2048.0


func _side() -> float:
	return minf(_view.size.x, _view.size.y) * _zoom


## Map uv -> position inside the view.
func uv_to_view(uv: Vector2) -> Vector2:
	return _view.size * 0.5 + (uv - _center) * _side()


func world_to_view(p: Vector3) -> Vector2:
	return uv_to_view(_uv(p))


func view_to_uv(at: Vector2) -> Vector2:
	return _center + (at - _view.size * 0.5) / maxf(_side(), 1.0)


## The world point under a view position (on the ground).
func view_to_world(at: Vector2) -> Vector3:
	var uv := view_to_uv(at) * world_size()
	var h: Variant = UiContext.call_on(UiContext.world(), "surface_height_at", [uv.x, uv.y], 0.0)
	return Vector3(uv.x, float(h) if h != null else 0.0, uv.y)


## The atlas square of a world position, e.g. "E7".
func grid_ref(p: Vector3) -> String:
	var cell := world_size() / GRID
	var gx := clampi(int(p.x / cell), 0, GRID - 1)
	var gz := clampi(int(p.z / cell), 0, GRID - 1)
	return "%s%d" % [char(65 + gx), gz + 1]


func _max_zoom() -> float:
	return maxf(2.0, world_size() / maxf(minf(_view.size.x, _view.size.y), 1.0) * 1.6)


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit


func _process(delta: float) -> void:
	if not is_open:
		return
	_time += delta
	# Smooth zoom about an anchor point, gliding, keyboard panning, inertia.
	var k := 1.0 - exp(-delta * 12.0)
	if absf(_zoom - _zoom_goal) > 0.0005 * _zoom:
		var anchor := _zoom_anchor if _zoom_anchor.x >= 0.0 else _view.size * 0.5
		var uv_at := view_to_uv(anchor)
		_zoom = exp(lerpf(log(_zoom), log(_zoom_goal), k))
		_center = uv_at - (anchor - _view.size * 0.5) / maxf(_side(), 1.0)
	else:
		_zoom = _zoom_goal
		_zoom_anchor = Vector2(-1, -1)
	var pan := Vector2.ZERO
	if not _typing():
		pan = Vector2(
			float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
			float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
	if pan != Vector2.ZERO:
		_center += pan.normalized() * 600.0 * delta / maxf(_side(), 1.0)
		_center_goal = Vector2(-1, -1)
		_velocity = Vector2.ZERO
	elif _center_goal.x >= 0.0:
		_center = _center.lerp(_center_goal, 1.0 - exp(-delta * 7.0))
		if _center.distance_to(_center_goal) * _side() < 0.5:
			_center = _center_goal
			_center_goal = Vector2(-1, -1)
	elif not _dragging and _velocity.length() > 0.0:
		_center += _velocity * delta
		_velocity *= exp(-delta * 5.0)
		if _velocity.length() * _side() < 2.0:
			_velocity = Vector2.ZERO
	_center = _center.clamp(Vector2(-0.1, -0.1), Vector2(1.1, 1.1))
	var side := maxf(_side(), 1.0)
	_mat.set_shader_parameter(&"view_size", _view.size)
	_mat.set_shader_parameter(&"uv_per_px", 1.0 / side)
	_mat.set_shader_parameter(&"view_origin_uv", _center - _view.size * 0.5 / side)
	_mat.set_shader_parameter(&"time", _time)
	var marks := MapMarkers.of(UiContext.world())
	if marks != null and marks.revision != _marker_rev:
		_marker_rev = marks.revision
		_rebuild_markers(marks)
	if _editor.visible:
		_editor.follow(world_to_view(_editor.world_pos))
	var player := UiContext.player()
	if player != null:
		var me := (player as Node3D).global_position
		var text := "%s  ·  you are in %s" % [_region_at(me), grid_ref(me)]
		if _sub.text != text:
			_sub.text = text
	_overlay.queue_redraw()


func _region_at(p: Vector3) -> String:
	var w := UiContext.world()
	if w is GameWorld:
		var vw := (w as GameWorld).world_for(_dim)
		if vw != null and vw.gen != null:
			return vw.gen.region_name(p.x, p.z)
	return ""


func _zoom_by(factor: float, at := Vector2(-1, -1)) -> void:
	_zoom_goal = clampf(_zoom_goal * factor, 0.85, _max_zoom())
	_zoom_anchor = at
	_center_goal = Vector2(-1, -1)


func _on_view_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_by(1.25, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_by(1.0 / 1.25, mb.position)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed and mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
				_new_marker_at(mb.position)
				return
			if not mb.pressed and _dragging and _drag_moved < 5.0:
				_click(mb.position, mb.button_index == MOUSE_BUTTON_RIGHT)
			_dragging = mb.pressed
			if mb.pressed:
				_drag_moved = 0.0
				_velocity = Vector2.ZERO
				_center_goal = Vector2(-1, -1)
		return
	var pg := event as InputEventMagnifyGesture
	if pg != null:
		_zoom_by(pg.factor, pg.position)
		return
	var pan := event as InputEventPanGesture
	if pan != null:
		_center += pan.delta * 6.0 / maxf(_side(), 1.0)
		return
	var mm := event as InputEventMouseMotion
	if mm != null:
		_overlay.hover = mm.position
		if _dragging:
			var d := mm.relative / maxf(_side(), 1.0)
			_center -= d
			_drag_moved += mm.relative.length()
			_velocity = _velocity.lerp(-d / maxf(get_process_delta_time(), 0.001), 0.5)


## A click without a drag: edit the marker under it, or (right button) place one.
func _click(at: Vector2, right: bool) -> void:
	var hit := _overlay.marker_at(at)
	if not hit.is_empty() and hit.get("mine", false):
		_editor.edit(hit)
		UiContext.sound("ui_click")
		return
	if right:
		_new_marker_at(at)
	elif _editor.visible:
		_editor.visible = false


func _new_marker_at(at: Vector2) -> void:
	var marks := MapMarkers.of(UiContext.world())
	if marks == null:
		return
	if marks.own.size() >= MapMarkers.MAX:
		UiContext.sound("ui_error")
		return
	_editor.create(view_to_world(at), _dim)
	UiContext.sound("ui_click")


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if _editor.visible and event.is_action_pressed("ui_cancel"):
		_editor.visible = false
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and not _typing():
		match key.keycode:
			KEY_SPACE:
				_recentre()
				get_viewport().set_input_as_handled()
				return
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				_zoom_by(1.5)
				get_viewport().set_input_as_handled()
				return
			KEY_MINUS, KEY_KP_SUBTRACT:
				_zoom_by(1.0 / 1.5)
				get_viewport().set_input_as_handled()
				return
	if event.is_action_pressed("map") and not _typing():
		close()
		get_viewport().set_input_as_handled()
		return
	super(event)


# --- Side panel ------------------------------------------------------------------------

func _rebuild_objectives() -> void:
	for c in _objectives.get_children():
		c.queue_free()
	var world := UiContext.world()
	var markers := QuestMarkers.all(world)
	var active: Variant = UiContext.call_on(UiContext.quests(), "active", [], [])
	var count := 0
	if active is Array:
		for quest: Dictionary in active:
			var id := str(quest.get("id", ""))
			if not markers.has(id) or count >= 7:
				continue
			var m: Dictionary = markers[id]
			var b := _side_button(("◆  " if quest.get("tracked", false) else "◇  ") + str(quest.get("title", id)),
					MapIcons.QUEST if quest.get("tracked", false) else UiTheme.TEXT_DIM, m["pos"], int(m.get("dim", 0)))
			b.tooltip_text = str(m.get("text", ""))
			_objectives.add_child(b)
			count += 1
	for pt: Dictionary in QuestMarkers.points(world):
		if str(pt.get("quest_id", "")) != "" or count >= 7:
			continue
		_objectives.add_child(_side_button("✦  " + str(pt.get("text", "")), MapIcons.point_colour(pt), pt["pos"], int(pt.get("dim", 0))))
		count += 1
	if count == 0:
		_objectives.add_child(UiTheme.label("No marked objectives.", 12, UiTheme.TEXT_FAINT))


func _side_button(text: String, col: Color, pos: Vector3, mdim: int) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.custom_minimum_size = Vector2(SIDEBAR_W - 34, 0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", col)
	b.pressed.connect(func() -> void:
		if mdim == _dim:
			_center_goal = _uv(pos)
			_zoom_goal = maxf(_zoom_goal, 4.0)
			UiContext.sound("ui_click"))
	b.disabled = mdim != _dim
	return b


func _rebuild_markers(marks: MapMarkers) -> void:
	for c in _marker_list.get_children():
		c.queue_free()
	var shown := 0
	for d in [_dim]:
		for m: Dictionary in marks.visible(d):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			var sw := GlyphSwatch.new()
			sw.glyph = MapMarkers.icon(m)
			sw.colour = MapMarkers.colour(m)
			row.add_child(sw)
			var label := String(m.get("name", ""))
			if not m.get("mine", false):
				label += "  ·  " + String(m.get("owner", "party"))
			elif m.get("shared", false):
				label += "  ⇄"
			var b := _side_button(label, UiTheme.TEXT if m.get("mine", false) else UiTheme.TEXT_DIM, m["pos"], int(m["dim"]))
			b.tooltip_text = grid_ref(m["pos"])
			row.add_child(b)
			if m.get("mine", false):
				var id := String(m["id"])
				var del := Button.new()
				del.text = "✕"
				del.tooltip_text = "Delete marker"
				del.add_theme_font_size_override("font_size", 12)
				del.add_theme_color_override("font_color", UiTheme.TEXT_FAINT)
				del.pressed.connect(func() -> void:
					marks.remove(id)
					if _editor.visible and _editor.marker_id == id:
						_editor.visible = false
					UiContext.sound("ui_click"))
				row.add_child(del)
			_marker_list.add_child(row)
			shown += 1
	if shown == 0:
		_marker_list.add_child(UiTheme.label("Right-click the map to\nplace a marker.", 12, UiTheme.TEXT_FAINT))


## A small symbol swatch (marker lists, editor buttons).
class GlyphSwatch:
	extends Control

	var glyph: StringName = &"pin"
	var colour := Color.WHITE

	func _init() -> void:
		custom_minimum_size = Vector2(24, 24)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		MapIcons.draw_glyph(self, glyph, size * 0.5, minf(size.x, size.y) * 0.36, colour, Color(0, 0, 0, 0.85))


## The marker editor: name, symbol, colour, party sharing, save / delete.
class MarkerEditor:
	extends PanelContainer

	var screen: MapScreen
	var world_pos := Vector3.ZERO
	var dim := 0
	var marker_id := ""
	var _name: LineEdit
	var _icons: GridContainer
	var _colours: HBoxContainer
	var _share: CheckBox
	var _delete: Button
	var _title: Label
	var _icon: StringName = &"pin"
	var _colour := MapIcons.MARKER_COLOURS[0]

	func _init() -> void:
		add_theme_stylebox_override("panel", UiTheme.panel_box(Color(0.035, 0.028, 0.026, 0.97), UiTheme.ACCENT_DIM, 1))
		custom_minimum_size = Vector2(256, 0)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		add_child(box)
		_title = UiTheme.title("NEW MARKER", 12, UiTheme.ACCENT_HOT, 700)
		box.add_child(_title)
		_name = LineEdit.new()
		_name.placeholder_text = "Name (e.g. Home, Iron vein)"
		_name.max_length = MapMarkers.NAME_MAX
		_name.text_submitted.connect(func(_t: String) -> void: _save())
		box.add_child(_name)
		_icons = GridContainer.new()
		_icons.columns = 6
		box.add_child(_icons)
		for g: StringName in MapIcons.MARKER_ICONS:
			var b := Button.new()
			b.custom_minimum_size = Vector2(36, 32)
			b.toggle_mode = true
			b.tooltip_text = String(g).trim_prefix("b_").capitalize()
			var sw := GlyphSwatch.new()
			sw.glyph = g
			sw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			b.add_child(sw)
			b.pressed.connect(func() -> void:
				_icon = g
				_refresh())
			b.set_meta(&"glyph", g)
			_icons.add_child(b)
		_colours = HBoxContainer.new()
		_colours.add_theme_constant_override("separation", 4)
		box.add_child(_colours)
		for c: Color in MapIcons.MARKER_COLOURS:
			var b := Button.new()
			b.custom_minimum_size = Vector2(26, 22)
			b.toggle_mode = true
			b.add_theme_stylebox_override("normal", UiTheme.flat(c))
			b.add_theme_stylebox_override("hover", UiTheme.flat(c.lightened(0.2)))
			b.add_theme_stylebox_override("pressed", UiTheme.panel_box(c, Color.WHITE, 2))
			b.pressed.connect(func() -> void:
				_colour = c
				_refresh())
			b.set_meta(&"colour", c)
			_colours.add_child(b)
		_share = CheckBox.new()
		_share.text = "Share with the party"
		_share.add_theme_font_size_override("font_size", 12)
		box.add_child(_share)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		box.add_child(row)
		var save := UiTheme.button("Save", _save, 12)
		save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(save)
		_delete = UiTheme.button("Delete", _remove, 12)
		row.add_child(_delete)
		row.add_child(UiTheme.button("Cancel", func() -> void: visible = false, 12))

	func create(at: Vector3, in_dim: int) -> void:
		marker_id = ""
		world_pos = at
		dim = in_dim
		_title.text = "NEW MARKER  ·  " + screen.grid_ref(at)
		_name.text = ""
		_icon = &"pin"
		_colour = MapIcons.MARKER_COLOURS[0]
		_share.button_pressed = false
		_delete.visible = false
		_open()

	func edit(m: Dictionary) -> void:
		marker_id = String(m["id"])
		world_pos = m["pos"]
		dim = int(m["dim"])
		_title.text = "MARKER  ·  " + screen.grid_ref(world_pos)
		_name.text = String(m.get("name", ""))
		_icon = MapMarkers.icon(m)
		_colour = MapMarkers.colour(m)
		_share.button_pressed = m.get("shared", false)
		_delete.visible = true
		_open()

	func _open() -> void:
		_share.disabled = not Net.is_online()
		_share.tooltip_text = "" if Net.is_online() else "Shared markers reach the party in co-op games."
		visible = true
		reset_size()
		_refresh()
		follow(screen.world_to_view(world_pos))
		_name.grab_focus()

	## Keeps the panel beside its spot on the map, inside the view.
	func follow(at: Vector2) -> void:
		var view := screen._view.size
		var s := get_combined_minimum_size()
		var p := at + Vector2(22, -s.y * 0.5)
		if p.x + s.x > view.x - 8:
			p.x = at.x - 22 - s.x
		position = p.clamp(Vector2(8, 8), (view - s - Vector2(8, 8)).max(Vector2(8, 8)))

	func _refresh() -> void:
		for b: Button in _icons.get_children():
			b.set_pressed_no_signal(b.get_meta(&"glyph") == _icon)
			(b.get_child(0) as GlyphSwatch).colour = _colour
			b.get_child(0).queue_redraw()
		for b: Button in _colours.get_children():
			b.set_pressed_no_signal((b.get_meta(&"colour") as Color).is_equal_approx(_colour))

	func _save() -> void:
		var marks := MapMarkers.of(UiContext.world())
		if marks == null:
			return
		if marker_id == "":
			marks.add(world_pos, dim, _name.text, _icon, _colour, _share.button_pressed)
		else:
			marks.edit(marker_id, {"name": _name.text, "icon": _icon, "color": _colour, "shared": _share.button_pressed})
		UiContext.sound("ui_click")
		visible = false

	func _remove() -> void:
		var marks := MapMarkers.of(UiContext.world())
		if marks != null and marker_id != "":
			marks.remove(marker_id)
			UiContext.sound("ui_click")
		visible = false


## The symbol key, in two columns.
class Legend:
	extends Control

	const ROWS := [
		[&"quest", "Objective"], [&"skull", "Boss"], [&"dead", "Defeated"], [&"village", "Village"],
		[&"shrine", "Shrine"], [&"cave", "Cave"], [&"mine", "Mine"], [&"dungeon", "Dungeon"],
		[&"portal", "Portal"], [&"tower", "Tower"], [&"ruin", "Ruins"], [&"wreck", "Wreck"],
		[&"keep", "Stronghold"], [&"activity", "Activity"], [&"mate", "Companion"], [&"marker", "Your marker"],
	]

	func _init() -> void:
		custom_minimum_size = Vector2(SIDEBAR_W, ceilf(ROWS.size() / 2.0) * 22.0 + 4.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i in ROWS.size():
			var row: Array = ROWS[i]
			var at := Vector2(12 + (i % 2) * SIDEBAR_W * 0.5, 11 + (i / 2) * 22.0)
			match row[0]:
				&"quest":
					MapIcons.draw_glyph(self, &"quest", at, 7.5, MapIcons.QUEST, Color(0, 0, 0, 0.9))
				&"skull":
					MapIcons.draw_badge(self, &"skull", at, 9.0, false)
				&"dead":
					MapIcons.draw_badge(self, &"skull", at, 9.0, true)
				&"mate":
					Minimap._chevron(self, at, 0.0, 6.5, UiTheme.FROST, 1.0)
				&"activity":
					MapIcons.draw_point(self, {"kind": "activity", "icon": "treasure"}, at, 8.0, 0.0)
				&"marker":
					MapIcons.draw_marker(self, &"home", MapIcons.MARKER_COLOURS[0], at + Vector2(0, 9), 6.0)
				_:
					var col := MapIcons.STONE
					match row[0]:
						&"village": col = MapIcons.VILLAGE
						&"shrine": col = MapIcons.SHRINE
						&"portal": col = MapIcons.PORTAL
						&"wreck": col = MapIcons.SEA
						&"cave", &"mine": col = MapIcons.EARTH
					MapIcons.draw_glyph(self, row[0], at, 7.5, col, Color(0, 0, 0, 0.85))
			draw_string(UiTheme.MONO, at + Vector2(16, 4.5), row[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.TEXT_DIM)


## Draws the atlas furniture, region names, places, markers, objectives,
## companions and you above the map.
class MapOverlay:
	extends Control

	const LAND_INK := Color(0.96, 0.9, 0.76, 0.8)
	const SEA_INK := Color(0.72, 0.86, 0.92, 0.72)
	const FRAME := Color(0.78, 0.6, 0.36, 0.85)

	var screen: MapScreen
	var hover := Vector2(-999, -999)
	var _marker_hits: Array = []   # [Vector2 view position, marker]

	func _label(pos: Vector2, text: String, fs: int, col: Color, font: Font, outline := 5) -> void:
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var p := pos + Vector2(-ts.x * 0.5, 0)
		draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, Color(0, 0, 0, 0.75))
		draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	## The player marker under a view position ({} if none).
	func marker_at(at: Vector2) -> Dictionary:
		var best := {}
		var best_d := 16.0
		for e: Array in _marker_hits:
			var d := (e[0] as Vector2).distance_to(at)
			if d < best_d:
				best_d = d
				best = e[1]
		return best

	func _draw() -> void:
		if screen == null:
			return
		var world := UiContext.world()
		var fog := MapFog.of(world)
		var dim := screen._dim
		var title := UiTheme.title_font(700)
		var bounds := Rect2(Vector2.ZERO, size).grow(40)
		var zoom := screen._zoom
		var px_per_m := screen._side() / screen.world_size()
		var hovered := {}
		var hovered_pos := Vector2.ZERO
		var best_d := 22.0
		_grid(px_per_m)
		# Places you know, laid out before drawing so names never collide.
		var order: Array = []
		var locs: Variant = UiContext.call_on(world, "locations", [dim], [])
		if locs is Array:
			for loc: Object in locs:
				if loc == null:
					continue
				var pos := screen.world_to_view(loc.get("center"))
				if not bounds.has_point(pos) or not Minimap.place_known(world, fog, dim, loc):
					continue
				var place := MapIcons.place_of(world, loc)
				var rank := 2 if String(place["boss"]) != "" else (1 if place["major"] else 0)
				order.append([rank, pos, place])
		order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var labels: Array[Rect2] = []
		var place_labels: Array = []
		for e: Array in order:
			var place: Dictionary = e[2]
			var r := 13.0 if e[0] == 2 else (10.0 if e[0] == 1 else 8.0)
			if not (e[0] > 0 or zoom > 4.0):
				continue
			var fs := 13 if e[0] > 0 else 11
			var text := String(place["name"])
			var ts := title.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var pos: Vector2 = e[1]
			var rect := Rect2(pos + Vector2(-ts.x * 0.5 - 3, r + 3), Vector2(ts.x + 6, fs + 4))
			var clash := false
			for o in labels:
				if o.intersects(rect):
					clash = true
					break
			if not clash:
				labels.append(rect)
				var col := UiTheme.TEXT if place["state"] != MapIcons.State.DEFEATED else UiTheme.TEXT_DIM
				place_labels.append([pos + Vector2(0, r + 4 + fs), text, fs, col if e[0] > 0 else UiTheme.TEXT_DIM])
		# Region and sea names (explored ones only), under everything else.
		if screen._layers != null:
			var spaced := UiTheme.title_font_spaced(600, 4)
			for reg: Array in screen._layers.regions:
				var wp: Vector2 = reg[1]
				var span := sqrt(float(reg[2])) * px_per_m
				if span < 70.0:
					continue
				var pos := screen.uv_to_view(wp / screen.world_size())
				if not bounds.has_point(pos):
					continue
				if fog != null and fog.seen(dim, Vector3(wp.x, 0, wp.y)) < 0.5:
					continue
				var fs := int(clampf(span / 16.0, 11.0, 19.0))
				var text := String(reg[0]).to_upper()
				var ts := spaced.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
				var rect := Rect2(pos - Vector2(ts.x * 0.5 + 14, fs), Vector2(ts.x + 20, fs + 6))
				var clash := false
				for o in labels:
					if o.intersects(rect):
						clash = true
						break
				if clash:
					continue
				labels.append(rect)
				var sea: bool = reg[3]
				var col := SEA_INK if sea else LAND_INK
				_label(pos + Vector2(6, 0), text, fs, col, spaced, 4)
				var sym: Array = MapIcons.biome_symbol(int(reg[4]) if reg.size() > 4 else 0)
				MapIcons.draw_glyph(self, sym[0], pos + Vector2(-ts.x * 0.5 - 6, -fs * 0.36), fs * 0.48, (sym[1] as Color).lightened(0.35), Color(0, 0, 0, 0.7))
		# Place symbols, most important on top, then their names.
		order.reverse()
		for e: Array in order:
			var pos: Vector2 = e[1]
			var place: Dictionary = e[2]
			var r := 13.0 if e[0] == 2 else (10.0 if e[0] == 1 else 8.0)
			MapIcons.draw_place(self, place, pos, r)
			var d := pos.distance_to(hover)
			if d < best_d:
				best_d = d
				hovered = place
				hovered_pos = pos
		for pl: Array in place_labels:
			_label(pl[0], pl[1], pl[2], pl[3], title)
		# Player markers (yours and the party's).
		_marker_hits.clear()
		var marks := MapMarkers.of(world)
		if marks != null:
			var sel := screen._editor.marker_id if screen._editor.visible else ""
			for m: Dictionary in marks.visible(dim):
				var pos := screen.world_to_view(m["pos"])
				if not bounds.has_point(pos):
					continue
				var head := pos + Vector2(0, -12.0)
				_marker_hits.append([head, m])
				MapIcons.draw_marker(self, MapMarkers.icon(m), MapMarkers.colour(m), pos, 8.0, 1.0 if m.get("mine", false) else 0.8, m["id"] == sel)
				if zoom > 2.0:
					_label(pos + Vector2(0, 14), String(m["name"]), 11, MapMarkers.colour(m).lightened(0.3), UiTheme.MONO_BOLD, 4)
				if head.distance_to(hover) < best_d:
					best_d = head.distance_to(hover)
					var owner := "Your marker" if m.get("mine", false) else "%s's marker" % String(m.get("owner", "A companion"))
					hovered = {"name": String(m["name"]), "sub": "%s  ·  %s%s" % [owner, screen.grid_ref(m["pos"]),
						"  ·  click to edit" if m.get("mine", false) else ""]}
					hovered_pos = head
		# Quest objectives, hand-ins and activities; search areas underneath.
		var pts: Array = []
		for pt: Dictionary in QuestMarkers.points(world):
			if int(pt.get("dim", 0)) == dim:
				pts.append(pt)
		for pt: Dictionary in pts:
			if float(pt.get("radius", 0.0)) > 0.0:
				MapIcons.draw_area(self, pt, screen.world_to_view(pt["pos"]), float(pt["radius"]) * px_per_m)
		pts.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
			return (1 if x.get("tracked", true) else 0) * 10.0 + float(x.get("priority", 1.0)) < (1 if y.get("tracked", true) else 0) * 10.0 + float(y.get("priority", 1.0)))
		for pt: Dictionary in pts:
			var pos := screen.world_to_view(pt["pos"])
			var tracked: bool = pt.get("tracked", true)
			var inside := Rect2(Vector2.ZERO, size).grow(-14).has_point(pos)
			if not inside:
				if not tracked:
					continue
				pos = pos.clamp(Vector2(14, 14), size - Vector2(14, 14))
			var quest_kind := String(pt.get("kind", "")) in ["main", "side", "turn_in"]
			MapIcons.draw_point(self, pt, pos, (10.0 if tracked else 8.0) if quest_kind else 10.0, screen._time, not inside)
			if pos.distance_to(hover) < best_d:
				best_d = pos.distance_to(hover)
				var name := str(pt.get("text", ""))
				var sub := ""
				var qid := str(pt.get("quest_id", ""))
				if qid != "":
					sub = name
					name = _quest_title(qid)
				hovered = {"name": name, "sub": sub}
				hovered_pos = pos
		# Companions and you.
		var me := UiContext.player()
		var players: Variant = UiContext.call_on(world, "players_in", [dim], [])
		var net := UiContext.net()
		if players is Array:
			for p: Object in players:
				if p == null or p == me:
					continue
				var pos := screen.world_to_view((p as Node3D).global_position)
				var col := UiTheme.FROST
				var peer: Variant = p.get("peer_id")
				if net != null and peer != null:
					col = UiContext.call_on(net, "player_color", [int(peer)], col)
				var pyaw: Variant = p.get("yaw")
				if p.get("downed") == true or p.get("dead") == true:
					var pulse := 0.5 + 0.5 * sin(screen._time * 6.0)
					draw_circle(pos, 9.0, Color(0, 0, 0, 0.7), true, -1.0, true)
					draw_arc(pos, 9.0 + pulse * 4.0, 0, TAU, 24, Color(1, 0.3, 0.25, 0.8 - pulse * 0.5), 1.6, true)
					draw_line(pos + Vector2(0, -5.5), pos + Vector2(0, 5.5), Color(1, 0.35, 0.28), 2.6, true)
					draw_line(pos + Vector2(-5.5, 0), pos + Vector2(5.5, 0), Color(1, 0.35, 0.28), 2.6, true)
				else:
					Minimap._chevron(self, pos, -float(pyaw) if pyaw != null else 0.0, 8.0, col, 1.0)
				var pname := str(p.get("display_name")) if p.get("display_name") != null else ""
				var ns := UiTheme.MONO.get_string_size(pname, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
				_label(pos + Vector2(14 + ns.x * 0.5, 4), pname, 12, col, UiTheme.MONO)
		if me != null:
			var pos := screen.world_to_view((me as Node3D).global_position)
			var yaw := float(UiContext.call_on(world, "camera_yaw", [], me.get("yaw") if me.get("yaw") != null else 0.0))
			var pulse := fposmod(screen._time * 0.6, 1.0)
			draw_arc(pos, 10.0 + pulse * 14.0, 0, TAU, 32, Color(1, 0.85, 0.55, (1.0 - pulse) * 0.5), 1.5, true)
			Minimap._chevron(self, pos, -yaw, 10.0, Color(1, 0.86, 0.55), 1.0)
		_frame()
		_scale_bar(px_per_m)
		_compass_rose(Vector2(size.x - 64, 84), 40.0)
		if not hovered.is_empty():
			_tooltip(hovered_pos, hovered)

	func _quest_title(id: String) -> String:
		var active: Variant = UiContext.call_on(UiContext.quests(), "active", [], [])
		if active is Array:
			for q: Dictionary in active:
				if str(q.get("id", "")) == id:
					return str(q.get("title", id))
		return id

	func _tooltip(at: Vector2, place: Dictionary) -> void:
		var title := UiTheme.title_font(700)
		var name := String(place.get("name", ""))
		var sub := String(place.get("sub", ""))
		var w := maxf(title.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, UiTheme.MONO.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x) + 24.0
		var h := 46.0 if sub != "" else 30.0
		var r := Rect2(at + Vector2(18, -h - 8), Vector2(w, h))
		if r.end.x > size.x - 8:
			r.position.x = at.x - 18 - w
		if r.position.y < 8:
			r.position.y = at.y + 18
		draw_rect(r, Color(0.03, 0.025, 0.024, 0.94))
		draw_rect(r, UiTheme.ACCENT_DIM, false, 1.0)
		draw_string(title, r.position + Vector2(12, 21), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiTheme.ACCENT_HOT)
		if sub != "":
			draw_string(UiTheme.MONO, r.position + Vector2(12, 38), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.TEXT_DIM)

	## The lettered atlas grid (A.. across, 1.. down) with finer lines when close.
	func _grid(px_per_m: float) -> void:
		var ws := screen.world_size()
		var cell := ws / GRID
		var cell_px := cell * px_per_m
		var a := screen.uv_to_view(Vector2.ZERO)
		var b := screen.uv_to_view(Vector2.ONE)
		var top := maxf(a.y, 0.0)
		var bottom := minf(b.y, size.y)
		var left := maxf(a.x, 0.0)
		var right := minf(b.x, size.x)
		if cell_px > 360.0:
			var fine := cell / 4.0
			for i in GRID * 4 + 1:
				if i % 4 == 0:
					continue
				var x := a.x + i * fine * px_per_m
				if x > 0.0 and x < size.x:
					draw_line(Vector2(x, top), Vector2(x, bottom), Color(1, 0.92, 0.75, 0.04), 1.0)
				var y := a.y + i * fine * px_per_m
				if y > 0.0 and y < size.y:
					draw_line(Vector2(left, y), Vector2(right, y), Color(1, 0.92, 0.75, 0.04), 1.0)
		var line := Color(1, 0.9, 0.7, 0.11)
		for i in GRID + 1:
			var x := a.x + i * cell_px
			if x >= -1.0 and x <= size.x + 1.0:
				draw_line(Vector2(x, top), Vector2(x, bottom), line, 1.0)
			var y := a.y + i * cell_px
			if y >= -1.0 and y <= size.y + 1.0:
				draw_line(Vector2(left, y), Vector2(right, y), line, 1.0)
		# Square references along the top and left edges of the view.
		var font := UiTheme.title_font(700)
		draw_rect(Rect2(0, 0, size.x, 18), Color(0.03, 0.025, 0.024, 0.72))
		draw_rect(Rect2(0, 0, 20, size.y), Color(0.03, 0.025, 0.024, 0.72))
		for i in GRID:
			var x := a.x + (i + 0.5) * cell_px
			if x > 24.0 and x < size.x - 8.0:
				var t := char(65 + i)
				var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
				draw_string(font, Vector2(x - ts.x * 0.5, 13), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.ACCENT_DIM.lightened(0.3))
			var y := a.y + (i + 0.5) * cell_px
			if y > 24.0 and y < size.y - 8.0:
				var t := str(i + 1)
				var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
				draw_string(font, Vector2(10 - ts.x * 0.5, y + 4), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.ACCENT_DIM.lightened(0.3))

	## A double neat-line round the sheet with small corner diamonds.
	func _frame() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r.grow(-1.0), FRAME, false, 1.5)
		draw_rect(r.grow(-5.0), Color(FRAME, 0.4), false, 1.0)
		for c: Vector2 in [Vector2(5, 5), Vector2(size.x - 5, 5), Vector2(5, size.y - 5), Vector2(size.x - 5, size.y - 5)]:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0)]), FRAME)

	## A chequered scale bar in round metres.
	func _scale_bar(px_per_m: float) -> void:
		var metres := 2000.0
		for m in [10.0, 25.0, 50.0, 100.0, 200.0, 250.0, 500.0, 1000.0, 2000.0]:
			if m * px_per_m >= 140.0:
				metres = m
				break
		var px := metres * px_per_m
		var x0 := 34.0
		var y := size.y - 24.0
		draw_rect(Rect2(x0 - 12, y - 26, px + 46, 40), Color(0.03, 0.025, 0.024, 0.72))
		draw_rect(Rect2(x0 - 12, y - 26, px + 46, 40), Color(FRAME, 0.5), false, 1.0)
		for i in 4:
			var seg := Rect2(x0 + px * i / 4.0, y, px / 4.0, 5.0)
			draw_rect(seg, UiTheme.TEXT if i % 2 == 0 else Color(0.08, 0.07, 0.06))
		draw_rect(Rect2(x0, y, px, 5.0), UiTheme.TEXT, false, 1.0)
		var font := UiTheme.MONO
		var unit := func(m: float) -> String: return ("%d" % int(m)) if m < 1000.0 else str(snappedf(m / 1000.0, 0.1))
		draw_string(font, Vector2(x0 - 3, y - 6), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.TEXT_DIM)
		var mid: String = unit.call(metres * 0.5)
		draw_string(font, Vector2(x0 + px * 0.5 - font.get_string_size(mid, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x * 0.5, y - 6), mid, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.TEXT_DIM)
		var end: String = unit.call(metres) + (" m" if metres < 1000.0 else " km")
		draw_string(font, Vector2(x0 + px - 6, y - 6), end, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.TEXT)

	## An eight-point compass rose with a ring of ticks.
	func _compass_rose(c: Vector2, r: float) -> void:
		draw_circle(c, r + 6.0, Color(0.03, 0.025, 0.024, 0.6), true, -1.0, true)
		draw_arc(c, r * 0.72, 0.0, TAU, 48, Color(FRAME, 0.8), 1.0, true)
		draw_arc(c, r + 3.0, 0.0, TAU, 64, Color(FRAME, 0.6), 1.0, true)
		for i in 32:
			var a := TAU * i / 32.0
			var d := Vector2(sin(a), -cos(a))
			draw_line(c + d * (r - (3.0 if i % 4 == 0 else 1.5)), c + d * (r + 3.0), Color(FRAME, 0.7), 1.0, true)
		var light := Color(0.95, 0.88, 0.72)
		var dark := Color(0.38, 0.28, 0.18)
		for i in 8:
			var a := TAU * i / 8.0
			var long := i % 2 == 0
			var len := r * (0.98 if long else 0.6)
			var wid := r * (0.17 if long else 0.12)
			var d := Vector2(sin(a), -cos(a))
			var s := Vector2(d.y, -d.x)
			var tip := c + d * len
			var col_a := light if long else light.darkened(0.25)
			var col_b := dark if long else dark.darkened(0.2)
			if i == 0:
				col_a = Color(0.95, 0.4, 0.28)
				col_b = Color(0.55, 0.16, 0.1)
			draw_colored_polygon(PackedVector2Array([c, tip, c + s * wid]), col_a)
			draw_colored_polygon(PackedVector2Array([c, tip, c - s * wid]), col_b)
		draw_circle(c, 3.0, FRAME, true, -1.0, true)
		var font := UiTheme.title_font(700)
		for card: Array in [["N", 0.0], ["E", PI * 0.5], ["S", PI], ["W", PI * 1.5]]:
			var a: float = card[1]
			var pos := c + Vector2(sin(a), -cos(a)) * (r + 13.0)
			var fs := 14 if card[0] == "N" else 11
			var ts := font.get_string_size(card[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string_outline(font, pos + Vector2(-ts.x * 0.5, fs * 0.36), card[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
			draw_string(font, pos + Vector2(-ts.x * 0.5, fs * 0.36), card[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
					UiTheme.ACCENT_HOT if card[0] == "N" else UiTheme.TEXT_DIM)
