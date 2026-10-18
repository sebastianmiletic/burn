class_name ActivityHud
extends CanvasLayer
## First-person guidance for quests and activities:
##  * a compass strip at the top: heading ticks, N/E/S/W, every marker from
##    QuestLog.markers() at its bearing (the focused one bright, with its
##    label and distance underneath);
##  * the objective diamond: the focused marker projected into the view (or
##    pinned to the screen edge with an arrow when behind you);
##  * the dowsing needle while searching for treasure (cold .. burning);
##  * event banners (a star falls, raids, the Proving Ring's waves).
## Focus: the highest-priority marker (events > activities > the tracked main
## quest), nearest first.

const STRIP_W := 560.0
const STRIP_H := 30.0
const SPAN := deg_to_rad(150.0)   ## bearing range shown across the strip

var director: ActivityDirector

var _root: Control
var _compass: Control
var _marker: Control
var _heat: Control
var _banner_title: Label
var _banner_sub: Label
var _banner_t := 0.0
var _markers: Array = []
var _focus: Dictionary = {}
var _refresh := 0.0
var _yaw := 0.0
var _cam_pos := Vector3.ZERO
var _proj := Vector2.ZERO
var _proj_ok := false
var _proj_edge := false


func _ready() -> void:
	layer = 19
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.theme()
	add_child(_root)
	_compass = Control.new()
	_compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass.draw.connect(_draw_compass)
	_root.add_child(_compass)
	_marker = Control.new()
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_marker.draw.connect(_draw_marker)
	_root.add_child(_marker)
	_heat = Control.new()
	_heat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heat.draw.connect(_draw_heat)
	_root.add_child(_heat)
	var banner := VBoxContainer.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.anchor_left = 0.5
	banner.anchor_right = 0.5
	banner.offset_left = -420
	banner.offset_right = 420
	banner.offset_top = 96  # clear of the location banner below it
	banner.alignment = BoxContainer.ALIGNMENT_CENTER
	_banner_title = UiTheme.title("", 34, UiTheme.ACCENT_HOT, 700)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_title.add_theme_constant_override("outline_size", 8)
	_banner_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	banner.add_child(_banner_title)
	_banner_sub = UiTheme.label("", 15, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_banner_sub.add_theme_constant_override("outline_size", 6)
	_banner_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_banner_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner.add_child(_banner_sub)
	banner.modulate.a = 0.0
	banner.name = "Banner"
	_root.add_child(banner)
	if director != null:
		director.banner.connect(show_banner)


func show_banner(title: String, subtitle: String, color: Color) -> void:
	_banner_title.text = title
	_banner_title.add_theme_color_override("font_color", color)
	_banner_sub.text = subtitle
	_banner_t = 5.0


## The marker the HUD points at right now ({} = none).
func focus() -> Dictionary:
	return _focus


func _process(delta: float) -> void:
	var w := GameWorld.instance
	if w == null or w.local_player == null or w.local_player.camera == null:
		_root.visible = false
		return
	var hud: Variant = w.hud
	var screens := hud != null and (hud as Object).has_method("any_screen_open") and bool((hud as Object).call("any_screen_open"))
	_root.visible = not screens
	var cam: Camera3D = w.local_player.camera
	_cam_pos = cam.global_position
	var fwd := -cam.global_basis.z
	_yaw = atan2(fwd.x, -fwd.z)   # 0 = north (-z), clockwise
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.25
		_markers = []
		for m: Dictionary in w.quests.markers():
			if int(m.get("dim", 0)) == w.local_dimension:
				_markers.append(m)
		_focus = _pick_focus(_markers, w.local_player.global_position)
	# Layout: the strip sits under the boss bar while a boss fight is on.
	var vp := _root.size
	var top := 10.0
	if hud != null and "boss_bar" in hud:
		var bb: Control = (hud as Object).get("boss_bar")
		if bb != null and bb.visible and bb.modulate.a > 0.05 and w.active_boss() != null:
			top = bb.offset_bottom + 8.0
	_compass.visible = bool(UiContext.setting("hud", "compass", true))   # Settings > Gameplay
	_compass.position = Vector2((vp.x - STRIP_W) * 0.5, top)
	_compass.size = Vector2(STRIP_W, STRIP_H + 34.0)
	_compass.queue_redraw()
	# Objective diamond.
	_proj_ok = false
	if not _focus.is_empty() and vp.x > 320.0 and vp.y > 320.0:
		var pos: Vector3 = _focus["pos"] + Vector3(0, 1.6, 0)
		var behind := cam.is_position_behind(pos)
		var sp := w.view.unproject(pos) if w.view != null else cam.unproject_position(pos)
		var margin := 48.0
		var rect := Rect2(Vector2(margin, margin + 60.0), vp - Vector2(margin * 2.0, margin * 2.0 + 120.0))
		if behind or not rect.has_point(sp):
			# Pin to the edge in the marker's direction.
			var centre := vp * 0.5
			var dir := (sp - centre) if not behind else (centre - sp)
			if dir.length() < 1.0:
				dir = Vector2(0, 1)
			dir = dir.normalized()
			var k := INF
			if absf(dir.x) > 0.001:
				k = minf(k, (rect.size.x * 0.5) / absf(dir.x))
			if absf(dir.y) > 0.001:
				k = minf(k, (rect.size.y * 0.5) / absf(dir.y))
			sp = centre + dir * k
			_proj_edge = true
		else:
			_proj_edge = false
		_proj = sp
		_proj_ok = true
	_marker.queue_redraw()
	# Treasure dowsing needle.
	var heat := director.treasure.heat if director != null else -1.0
	_heat.visible = heat >= 0.0
	if _heat.visible:
		_heat.position = Vector2(vp.x * 0.5 - 130.0, vp.y * 0.5 + 70.0)
		_heat.size = Vector2(260, 40)
		_heat.queue_redraw()
	# Banner fade.
	var banner: Control = _root.get_node("Banner")
	if _banner_t > 0.0:
		_banner_t -= delta
		banner.modulate.a = clampf(minf(_banner_t, 5.0 - _banner_t) * 2.5, 0.0, 1.0)
	else:
		banner.modulate.a = 0.0


static func _pick_focus(list: Array, from: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_key := -INF
	for m: Dictionary in list:
		var pr := float(m.get("priority", 1))
		match String(m.get("kind", "")):
			"main", "turn_in":
				pr = 1.5
			"side":
				pr = 0.5
		var dist := from.distance_to(m["pos"])
		var key := pr * 10000.0 - dist
		if key > best_key:
			best_key = key
			best = m
	return best


func _bearing(p: Vector3) -> float:
	var to := p - _cam_pos
	var b := atan2(to.x, -to.z)
	return angle_difference(_yaw, b)


func _colour(m: Dictionary) -> Color:
	match String(m.get("kind", "")):
		"main":
			return UiTheme.ACCENT_HOT
		"turn_in":
			return Color(0.6, 1.0, 0.5)
		"side":
			return UiTheme.ACCENT_DIM
	match String(m.get("icon", "")):
		"raid":
			return UiTheme.DANGER
		"star":
			return Color(0.65, 0.78, 1.0)
		"treasure":
			return Color(1.0, 0.85, 0.4)
		"bounty":
			return Color(1.0, 0.55, 0.3)
		"ring":
			return Color(1.0, 0.65, 0.35)
		"hart", "charm":
			return Color(1.0, 0.88, 0.45)
	return UiTheme.FROST


func _glyph(m: Dictionary) -> String:
	match String(m.get("icon", "")):
		"treasure":
			return "✕"
		"bounty":
			return "†"
		"star":
			return "⊕"
		"raid":
			return "▲"
		"ring":
			return "◎"
		"hart":
			return "◇"
	if m.get("kind", "") == "turn_in":
		return "?"
	return "◆"


func _draw_compass() -> void:
	var font: Font = UiTheme.MONO_BOLD
	var w := STRIP_W
	var mid := w * 0.5
	# Backing: a dark band fading out at the ends.
	for i in 24:
		var x0 := w * float(i) / 24.0
		var a := 0.55 * (1.0 - pow(absf(float(i) + 0.5 - 12.0) / 12.0, 2.0))
		_compass.draw_rect(Rect2(x0, 0, w / 24.0 + 0.5, STRIP_H), Color(0.02, 0.015, 0.01, a))
	_compass.draw_line(Vector2(0, STRIP_H), Vector2(w, STRIP_H), Color(UiTheme.ACCENT_DIM, 0.5), 1.0)
	# Ticks every 15 degrees, letters on the cardinals.
	for step in 24:
		var b := deg_to_rad(step * 15.0)
		var rel := angle_difference(_yaw, b)
		if absf(rel) > SPAN * 0.5:
			continue
		var x := mid + rel / (SPAN * 0.5) * mid
		var fade := 1.0 - pow(absf(rel) / (SPAN * 0.5), 3.0)
		if step % 6 == 0:
			var letter: String = ["N", "E", "S", "W"][step / 6]
			var c := UiTheme.ACCENT_HOT if letter == "N" else UiTheme.TEXT
			_compass.draw_string(font, Vector2(x - 6, 21), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(c, fade))
		else:
			var h := 8.0 if step % 3 == 0 else 5.0
			_compass.draw_line(Vector2(x, STRIP_H - h), Vector2(x, STRIP_H - 1), Color(UiTheme.TEXT_DIM, fade * 0.9), 1.0)
	_compass.draw_line(Vector2(mid, 0), Vector2(mid, 6), UiTheme.ACCENT, 2.0)
	# Markers.
	for m: Dictionary in _markers:
		var rel := _bearing(m["pos"])
		var clamped := clampf(rel, -SPAN * 0.5, SPAN * 0.5)
		var x := mid + clamped / (SPAN * 0.5) * mid
		var focus := m == _focus
		var c := _colour(m)
		if not focus:
			c.a = 0.6
		var size := 17 if focus else 13
		var g := _glyph(m)
		if absf(rel) > SPAN * 0.5:
			g = "◀" if rel < 0.0 else "▶"
		_compass.draw_string(font, Vector2(x - size * 0.32, 22), g, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)
	if not _focus.is_empty():
		var dist := _cam_pos.distance_to(_focus["pos"])
		var text := "%s  ·  %s" % [String(_focus.get("label", "")), _distance_text(dist)]
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		_compass.draw_string(font, Vector2(mid - tw * 0.5 + 1, STRIP_H + 19), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0, 0, 0, 0.8))
		_compass.draw_string(font, Vector2(mid - tw * 0.5, STRIP_H + 18), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, _colour(_focus))


static func _distance_text(d: float) -> String:
	return "%d m" % int(d) if d < 1000.0 else "%.1f km" % (d / 1000.0)


func _draw_marker() -> void:
	if not _proj_ok or _focus.is_empty():
		return
	var c := _colour(_focus)
	var p := _proj
	var dist := _cam_pos.distance_to(_focus["pos"])
	if dist < 3.0 and not _proj_edge:
		return
	var r := 9.0
	var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
	_marker.draw_colored_polygon(pts, Color(c, 0.25))
	pts.append(pts[0])
	_marker.draw_polyline(pts, c, 2.0, true)
	_marker.draw_circle(p, 2.5, c)
	if _focus.has("radius") and not _proj_edge:
		_marker.draw_arc(p, 22.0, 0.0, TAU, 32, Color(c, 0.4), 1.0, true)
	var font: Font = UiTheme.MONO_BOLD
	var text := _distance_text(dist)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_marker.draw_string(font, p + Vector2(-tw * 0.5 + 1, r + 18), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0, 0, 0, 0.8))
	_marker.draw_string(font, p + Vector2(-tw * 0.5, r + 17), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, c)
	if _proj_edge:
		var dir := (p - _marker.size * 0.5).normalized()
		var tip := p + dir * 18.0
		var side := Vector2(-dir.y, dir.x)
		_marker.draw_colored_polygon(PackedVector2Array([tip, p + dir * 8.0 + side * 6.0, p + dir * 8.0 - side * 6.0]), c)


func _draw_heat() -> void:
	var h := director.treasure.heat if director != null else -1.0
	if h < 0.0:
		return
	var font: Font = UiTheme.MONO_BOLD
	var word := TreasureHunt.heat_word(h).to_upper()
	var col := Color(0.45, 0.7, 1.0).lerp(Color(1.0, 0.35, 0.1), h)
	var w := 260.0
	_heat.draw_rect(Rect2(0, 18, w, 8), Color(0, 0, 0, 0.55))
	_heat.draw_rect(Rect2(1, 19, (w - 2) * h, 6), col)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * (2.0 + h * 10.0))
	var text := "✕  " + word
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	_heat.draw_string(font, Vector2(w * 0.5 - tw * 0.5 + 1, 13), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0, 0.8))
	_heat.draw_string(font, Vector2(w * 0.5 - tw * 0.5, 12), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col.lerp(Color.WHITE, pulse * h * 0.5))
