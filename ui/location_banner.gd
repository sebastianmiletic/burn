class_name LocationBanner
extends Control
## Big centred announcement the first time you enter a place, and the rank-up
## flourish. Cinzel title between ornament rules, subtitle below.

const HOLD := 3.2

var _title := ""
var _subtitle := ""
var _age := 99.0
var _accent := UiTheme.ACCENT_HOT
var _queue: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiContext.on("location_changed", func(t: String, s: String, first: bool) -> void:
		if first:
			show_banner(t, s, UiTheme.ACCENT_HOT))
	UiContext.on("rank_up", func(rank: int, title: String) -> void:
		show_banner("RANK %d · %s" % [rank + 1, title.to_upper()], "the fire in you grows", Color(1.0, 0.92, 0.6)))
	UiContext.on("boss_defeated", func(_k: String, n: String) -> void:
		show_banner(n.to_upper(), "has fallen", UiTheme.ACCENT_HOT))


func show_banner(title: String, subtitle: String, accent: Color) -> void:
	if _age < HOLD + 1.2:
		_queue.append([title, subtitle, accent])
		return
	_title = title
	_subtitle = subtitle
	_accent = accent
	_age = 0.0
	UiContext.sound("quest")


func _process(delta: float) -> void:
	_age += delta
	if _age > HOLD + 1.2 and not _queue.is_empty():
		var n: Array = _queue.pop_front()
		show_banner(n[0], n[1], n[2])
	if _age < HOLD + 1.3:
		queue_redraw()


func _draw() -> void:
	if _age > HOLD + 1.2 or _title == "":
		return
	var a := clampf(_age / 0.6, 0.0, 1.0) * clampf((HOLD + 1.2 - _age) / 1.0, 0.0, 1.0)
	var font := UiTheme.title_font(800)
	var fs := 46
	var spread := 1.0 + (1.0 - clampf(_age / 1.4, 0.0, 1.0)) * 0.08
	var ts := font.get_string_size(_title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var cy := size.y * 0.27
	var cx := size.x * 0.5
	var col := Color(_accent, a)
	draw_string_outline(font, Vector2(cx - ts.x * 0.5 * spread, cy), _title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(0, 0, 0, 0.55 * a))
	draw_string(font, Vector2(cx - ts.x * 0.5 * spread, cy), _title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	var rule := ts.x * 0.5 + 40.0
	var reveal := clampf(_age / 1.0, 0.0, 1.0)
	var ry := cy + 18.0
	draw_line(Vector2(cx - rule * reveal, ry), Vector2(cx - 10, ry), Color(UiTheme.ACCENT_DIM, a), 1.0)
	draw_line(Vector2(cx + 10, ry), Vector2(cx + rule * reveal, ry), Color(UiTheme.ACCENT_DIM, a), 1.0)
	var d := PackedVector2Array([Vector2(cx, ry - 5), Vector2(cx + 5, ry), Vector2(cx, ry + 5), Vector2(cx - 5, ry)])
	draw_colored_polygon(d, col)
	if _subtitle != "":
		var sf := UiTheme.title_font(500)
		var ss := sf.get_string_size(_subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 17)
		draw_string(sf, Vector2(cx - ss.x * 0.5, ry + 30), _subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(UiTheme.TEXT, a * 0.9))
