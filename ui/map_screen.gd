class_name MapScreen
extends UiModal
## Full world map. Wheel or +/- zooms (smoothly, about the cursor), drag or
## WASD / arrows pans, Space recentres on you, click an objective in the
## side panel to fly to it. Unexplored land stays grey (MapFog).

const SHADER := preload("res://ui/shaders/world_map.gdshader")
const SIDEBAR_W := 250.0

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
var _legend: Control
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
	_mat.set_shader_parameter(&"contour_strength", 0.16)
	_map.material = _mat
	_view.add_child(_map)
	_overlay = MapOverlay.new()
	_overlay.screen = self
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.add_child(_overlay)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(SIDEBAR_W, 0)
	side.add_theme_constant_override("separation", 6)
	body.add_child(side)
	side.add_child(_heading("OBJECTIVES"))
	_objectives = VBoxContainer.new()
	_objectives.add_theme_constant_override("separation", 2)
	side.add_child(_objectives)
	side.add_child(UiTheme.spacer(10))
	side.add_child(_heading("LEGEND"))
	_legend = Legend.new()
	side.add_child(_legend)
	var spring := Control.new()
	spring.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spring)
	var hints := UiTheme.label("wheel / + −   zoom\ndrag / WASD   pan\nspace   centre on you\nM / esc   close", 11, UiTheme.TEXT_FAINT)
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
	_title.text = ["THE ASHEN ISLE", "THE UNDERWORLD", "THE RYFT"][clampi(_dim, 0, 2)]
	_velocity = Vector2.ZERO
	_center_goal = Vector2(-1, -1)
	_zoom_anchor = Vector2(-1, -1)
	if _pending_focus.is_finite():
		_center = _uv(_pending_focus)
		_zoom = _pending_zoom
		_pending_focus = Vector3.INF
	else:
		_zoom = 3.0
		_recentre(true)
	_zoom_goal = _zoom
	_rebuild_objectives()


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


func _max_zoom() -> float:
	return maxf(2.0, world_size() / maxf(minf(_view.size.x, _view.size.y), 1.0) * 1.6)


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
	var pan := Vector2(
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
	_overlay.queue_redraw()


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


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
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
	if event.is_action_pressed("map"):
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
			if not markers.has(id):
				continue
			var m: Dictionary = markers[id]
			var b := Button.new()
			b.text = ("◆  " if quest.get("tracked", false) else "◇  ") + str(quest.get("title", id))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			b.custom_minimum_size = Vector2(SIDEBAR_W, 0)
			b.add_theme_font_size_override("font_size", 13)
			b.add_theme_color_override("font_color", MapIcons.QUEST if quest.get("tracked", false) else UiTheme.TEXT_DIM)
			b.tooltip_text = str(m.get("text", ""))
			var pos: Vector3 = m["pos"]
			var mdim := int(m.get("dim", 0))
			b.pressed.connect(func() -> void:
				if mdim == _dim:
					_center_goal = _uv(pos)
					_zoom_goal = maxf(_zoom_goal, 4.0)
					UiContext.sound("ui_click"))
			b.disabled = mdim != _dim
			_objectives.add_child(b)
			count += 1
	for pt: Dictionary in QuestMarkers.points(world):
		if str(pt.get("quest_id", "")) != "" or count >= 9:
			continue
		var b := Button.new()
		b.text = "✦  " + str(pt.get("text", ""))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.custom_minimum_size = Vector2(SIDEBAR_W, 0)
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("font_color", MapIcons.point_colour(pt))
		var pos: Vector3 = pt["pos"]
		var mdim := int(pt.get("dim", 0))
		b.pressed.connect(func() -> void:
			if mdim == _dim:
				_center_goal = _uv(pos)
				_zoom_goal = maxf(_zoom_goal, 4.0)
				UiContext.sound("ui_click"))
		b.disabled = mdim != _dim
		_objectives.add_child(b)
		count += 1
	if count == 0:
		_objectives.add_child(UiTheme.label("No marked objectives.", 12, UiTheme.TEXT_FAINT))


## The symbol key.
class Legend:
	extends Control

	const ROWS := [
		[&"quest", "Objective"], [&"skull", "Boss"], [&"dead", "Boss defeated"], [&"village", "Village"],
		[&"shrine", "Shrine"], [&"cave", "Cave"], [&"mine", "Mine"], [&"portal", "Portal"],
		[&"tower", "Watchtower"], [&"ruin", "Ruins"], [&"keep", "Stronghold"], [&"activity", "Activity / event"],
		[&"mate", "Companion"],
	]

	func _init() -> void:
		custom_minimum_size = Vector2(SIDEBAR_W, ROWS.size() * 24.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var y := 12.0
		for row: Array in ROWS:
			var at := Vector2(14, y)
			match row[0]:
				&"quest":
					MapIcons.draw_glyph(self, &"quest", at, 8.0, MapIcons.QUEST, Color(0, 0, 0, 0.9))
				&"skull":
					MapIcons.draw_badge(self, &"skull", at, 9.5, false)
				&"dead":
					MapIcons.draw_badge(self, &"skull", at, 9.5, true)
				&"mate":
					Minimap._chevron(self, at, 0.0, 7.0, UiTheme.FROST, 1.0)
				&"activity":
					MapIcons.draw_point(self, {"kind": "activity", "icon": "treasure"}, at, 8.5, 0.0)
				_:
					var col := MapIcons.STONE
					match row[0]:
						&"village": col = MapIcons.VILLAGE
						&"shrine": col = MapIcons.SHRINE
						&"portal": col = MapIcons.PORTAL
					MapIcons.draw_glyph(self, row[0], at, 8.0, col, Color(0, 0, 0, 0.85))
			draw_string(UiTheme.MONO, Vector2(34, y + 4.5), row[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.TEXT_DIM)
			y += 24.0


## Draws places, objectives, companions and you above the map.
class MapOverlay:
	extends Control

	var screen: MapScreen
	var hover := Vector2(-999, -999)

	func _label(pos: Vector2, text: String, fs: int, col: Color, font: Font) -> void:
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var p := pos + Vector2(-ts.x * 0.5, 0)
		draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.8))
		draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	func _draw() -> void:
		if screen == null:
			return
		var world := UiContext.world()
		var font := UiTheme.MONO
		var title := UiTheme.title_font(700)
		var discovered: Variant = world.get("discovered") if world != null else null
		var bounds := Rect2(Vector2.ZERO, size).grow(40)
		var zoom := screen._zoom
		var hovered := {}
		var hovered_pos := Vector2.ZERO
		var best_d := 22.0
		var locs: Variant = UiContext.call_on(world, "locations", [screen._dim], [])
		var labels: Array[Rect2] = []
		if locs is Array:
			# Bosses and major places last, so they draw on top.
			var order: Array = []
			for loc: Object in locs:
				if loc == null:
					continue
				if discovered is Dictionary and not (discovered as Dictionary).has(loc.get("id")):
					continue
				var pos := screen.world_to_view(loc.get("center"))
				if not bounds.has_point(pos):
					continue
				var place := MapIcons.place_of(world, loc)
				var rank := 2 if String(place["boss"]) != "" else (1 if place["major"] else 0)
				order.append([rank, pos, place])
			order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
			var cands: Array = []
			for e: Array in order:
				var pos: Vector2 = e[1]
				var place: Dictionary = e[2]
				var boss := String(place["boss"]) != ""
				var r := 13.0 if boss else (10.0 if place["major"] else 8.0)
				MapIcons.draw_place(self, place, pos, r)
				var d := pos.distance_to(hover)
				if d < best_d:
					best_d = d
					hovered = place
					hovered_pos = pos
				if boss or place["major"] or zoom > 4.0:
					cands.append([e[0], pos, place, r])
			# Labels: most important first, skipping any that would collide.
			cands.reverse()
			for cd: Array in cands:
				var pos: Vector2 = cd[1]
				var place: Dictionary = cd[2]
				var r: float = cd[3]
				var big: bool = cd[0] > 0
				var fs := 13 if big else 11
				var text := String(place["name"])
				var ts := title.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
				var rect := Rect2(pos + Vector2(-ts.x * 0.5 - 3, r + 3), Vector2(ts.x + 6, fs + 4))
				var clash := false
				for o in labels:
					if o.intersects(rect):
						clash = true
						break
				if clash:
					continue
				labels.append(rect)
				var col := UiTheme.TEXT if place["state"] != MapIcons.State.DEFEATED else UiTheme.TEXT_DIM
				if not big:
					col = UiTheme.TEXT_DIM
				_label(pos + Vector2(0, r + 4 + fs), text, fs, col, title)
		# Quest objectives, hand-ins and activities; search areas underneath.
		var px_per_m := screen._side() / screen.world_size()
		var pts: Array = []
		for pt: Dictionary in QuestMarkers.points(world):
			if int(pt.get("dim", 0)) == screen._dim:
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
		var players: Variant = UiContext.call_on(world, "players_in", [screen._dim], [])
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
				var ns := font.get_string_size(pname, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
				_label(pos + Vector2(14 + ns.x * 0.5, 4), pname, 12, col, font)
		if me != null:
			var pos := screen.world_to_view((me as Node3D).global_position)
			var yaw := float(UiContext.call_on(world, "camera_yaw", [], me.get("yaw") if me.get("yaw") != null else 0.0))
			var pulse := fposmod(screen._time * 0.6, 1.0)
			draw_arc(pos, 10.0 + pulse * 14.0, 0, TAU, 32, Color(1, 0.85, 0.55, (1.0 - pulse) * 0.5), 1.5, true)
			Minimap._chevron(self, pos, -yaw, 10.0, Color(1, 0.86, 0.55), 1.0)
		if not hovered.is_empty():
			_tooltip(hovered_pos, hovered)
		_scale_bar()
		_compass()

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

	func _scale_bar() -> void:
		var px_per_m := screen._side() / screen.world_size()
		var metres := 1000.0
		for m in [10.0, 25.0, 50.0, 100.0, 250.0, 500.0, 1000.0]:
			if m * px_per_m >= 90.0:
				metres = m
				break
		var px := metres * px_per_m
		var y := size.y - 20.0
		var x0 := 18.0
		draw_rect(Rect2(x0 - 8, y - 22, px + 16, 32), Color(0, 0, 0, 0.45))
		draw_line(Vector2(x0, y), Vector2(x0 + px, y), UiTheme.ACCENT_HOT, 2.0)
		for x in [x0, x0 + px * 0.5, x0 + px]:
			draw_line(Vector2(x, y - 5), Vector2(x, y + 3), UiTheme.ACCENT_HOT, 1.5)
		var text := "%d m" % int(metres) if metres < 1000.0 else "1 km"
		draw_string(UiTheme.MONO, Vector2(x0, y - 9), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.TEXT)

	func _compass() -> void:
		var c := Vector2(size.x - 34, 36)
		draw_circle(c, 20, Color(0, 0, 0, 0.45), true, -1.0, true)
		draw_arc(c, 20, 0, TAU, 32, UiTheme.ACCENT_DIM, 1.0, true)
		var n := PackedVector2Array([c + Vector2(0, -15), c + Vector2(5, 0), c + Vector2(-5, 0)])
		var s := PackedVector2Array([c + Vector2(0, 15), c + Vector2(5, 0), c + Vector2(-5, 0)])
		draw_colored_polygon(n, Color(0.9, 0.3, 0.2))
		draw_colored_polygon(s, UiTheme.TEXT_DIM)
		draw_string(UiTheme.title_font(700), c + Vector2(-5, -22), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.ACCENT_HOT)
