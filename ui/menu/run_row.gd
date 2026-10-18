class_name RunRow
extends Button
## One run in the title screen's runs list: its title in Cinzel, then the
## rank, place and time played, then when it was last played. Focus (keyboard,
## controller or a click) selects it; pressing it again plays it.

signal chosen(run: Dictionary)
signal activated(run: Dictionary)

var run := {}
var selected := false:
	set(v):
		selected = v
		queue_redraw()

var _hl := 0.0


func _init(info: Dictionary = {}) -> void:
	run = info


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	flat = true
	text = ""
	custom_minimum_size = Vector2(0, 74)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(s, empty)
	focus_entered.connect(func() -> void:
		_focus_frame = Engine.get_process_frames()
		UiContext.sound("ui_hover")
		chosen.emit(run))
	pressed.connect(func() -> void:
		var fresh_click := _mouse_press and _click_fresh
		_mouse_press = false
		if selected and has_focus() and not fresh_click:
			UiContext.sound("ui_click")
			activated.emit(run)
		elif not has_focus():
			grab_focus())


var _focus_frame := -1
var _mouse_press := false
var _click_fresh := false


## A click that only just focused (selected) the row does not play it yet.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_mouse_press = true
		_click_fresh = Engine.get_process_frames() - _focus_frame <= 1


func _process(delta: float) -> void:
	var target := 1.0 if has_focus() else (0.5 if is_hovered() else 0.0)
	var before := _hl
	_hl = move_toward(_hl, target, delta * 6.0)
	if before != _hl:
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var e := _hl
	draw_rect(r, Color(1, 1, 1, 0.025))
	if selected or e > 0.0:
		draw_rect(r, Color(UiTheme.ACCENT, 0.05 + 0.07 * e + (0.04 if selected else 0.0)))
	if selected:
		draw_rect(Rect2(0, 0, 3, size.y), UiTheme.ACCENT)
	draw_line(Vector2(0, size.y - 0.5), Vector2(size.x, size.y - 0.5), Color(UiTheme.BORDER, 0.35), 1.0)
	var x := 18.0
	var title_font := UiTheme.title_font_spaced(700 if selected or e > 0.5 else 600, 1)
	var title_col := UiTheme.TEXT.lerp(UiTheme.ACCENT_HOT, maxf(e, 0.6 if selected else 0.0))
	var title := str(run.get("title", "Untitled run"))
	var w := size.x - x - 16.0
	draw_string(title_font, Vector2(x, 26), title, HORIZONTAL_ALIGNMENT_LEFT, w - 120.0, 18, title_col)
	var mono := UiTheme.MONO
	var when := RunRow.relative_date(float(run.get("saved_at", 0.0)))
	draw_string(mono, Vector2(x, 26), when, HORIZONTAL_ALIGNMENT_RIGHT, w, UiTheme.SIZE_SMALL, UiTheme.TEXT_DIM)
	draw_string(mono, Vector2(x, 47), RunRow.line_rank(run), HORIZONTAL_ALIGNMENT_LEFT, w, UiTheme.SIZE_SMALL,
			UiTheme.ACCENT.lerp(UiTheme.TEXT_DIM, 0.35))
	draw_string(mono, Vector2(x, 65), "%s played  ·  seed %d" % [UiTheme.format_time(float(run.get("play_time", 0.0))), int(run.get("seed", 0))],
			HORIZONTAL_ALIGNMENT_LEFT, w, UiTheme.SIZE_SMALL, UiTheme.TEXT_FAINT.lerp(UiTheme.TEXT_DIM, 0.6))


## "Ember  ·  Wanderer  ·  Ashfall Village"
static func line_rank(info: Dictionary) -> String:
	var rank := int(info.get("rank", 0))
	var bits := [str(ItemDB.RANK_TITLES[clampi(rank, 0, ItemDB.RANK_TITLES.size() - 1)])]
	var who := str(info.get("name", ""))
	if who != "":
		bits.append(who)
	var loc := str(info.get("location", ""))
	bits.append(loc if loc != "" else "Unknown lands")
	return "  ·  ".join(bits)


## "18 Oct 2026, 14:05" in local time ("unknown" for 0).
static func date_text(unix: float) -> String:
	if unix <= 0.0:
		return "unknown"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(int(unix) + bias)
	const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%d %s %d, %02d:%02d" % [d["day"], MONTHS[clampi(int(d["month"]) - 1, 0, 11)], d["year"], d["hour"], d["minute"]]


## "today 14:05", "yesterday 09:12", "3 days ago", else the date.
static func relative_date(unix: float) -> String:
	if unix <= 0.0:
		return ""
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var now := int(Time.get_unix_time_from_system()) + bias
	var t := int(unix) + bias
	var days := int(floor(now / 86400.0)) - int(floor(t / 86400.0))
	var d := Time.get_datetime_dict_from_unix_time(t)
	var hm := "%02d:%02d" % [d["hour"], d["minute"]]
	if days <= 0:
		return "today " + hm
	if days == 1:
		return "yesterday " + hm
	if days < 7:
		return "%d days ago" % days
	return date_text(unix).get_slice(",", 0)
