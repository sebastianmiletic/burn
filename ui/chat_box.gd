class_name ChatBox
extends Control
## Chat panel (left side of the HUD, also in the lobby). No background: text
## carries a soft outline and shadow so it reads over any scene. Lines fade
## after the chat settings' fade time and come back while typing; a faint
## backdrop shows only while typing. Mouse wheel / PageUp / PageDown scroll
## back while open. T or Enter opens it, "/" opens it in command mode.
## Messages and commands live in ChatHub (shared with other chat boxes).

signal typing_changed(active: bool)

const MAX_LINES := 100
const CHANNEL_COLORS := {"party": UiTheme.TEXT, "local": UiTheme.TEXT, "global": UiTheme.TEXT,
	"whisper": Color(0.86, 0.62, 1.0), "whisper_out": Color(0.72, 0.56, 0.9), "system": UiTheme.ACCENT, "info": UiTheme.TEXT_DIM}

## Lobby: the input line stays visible and lines never fade.
var always_open := false
## In game: typing frees the mouse and blocks gameplay input.
var captures_game_input := true

var _backdrop: Panel
var _scroll: ScrollContainer
var _log: VBoxContainer
var _edit: LineEdit
var _lines: Array = []  # [RichTextLabel, age seconds]
var _typing := false
var _hub: ChatHub
var _stick_bottom := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hub = ChatHub.instance()
	_backdrop = Panel.new()
	var sb := UiTheme.flat(Color(0.02, 0.015, 0.012, 0.42), 0)
	sb.set_corner_radius_all(4)
	_backdrop.add_theme_stylebox_override("panel", sb)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.offset_left = -8
	_backdrop.offset_right = 8
	_backdrop.offset_top = -6
	_backdrop.offset_bottom = 6
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.modulate.a = 0.0
	add_child(_backdrop)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.follow_focus = false
	col.add_child(_scroll)
	_log = VBoxContainer.new()
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.alignment = BoxContainer.ALIGNMENT_END
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_theme_constant_override("separation", 2)
	_scroll.add_child(_log)
	_scroll.get_v_scroll_bar().changed.connect(func() -> void:
		if _stick_bottom:
			_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value))

	_edit = LineEdit.new()
	_edit.placeholder_text = "say something…   /help for commands   (Enter sends, Esc cancels)"
	_edit.max_length = 200
	_edit.context_menu_enabled = false
	var es := UiTheme.flat(Color(0.03, 0.022, 0.02, 0.55), 6)
	es.border_color = Color(UiTheme.ACCENT_DIM, 0.6)
	es.border_width_bottom = 1
	_edit.add_theme_stylebox_override("normal", es)
	_edit.add_theme_stylebox_override("focus", es)
	if always_open:
		_edit.placeholder_text = "chat…   /help"
	_edit.visible = always_open
	_edit.text_submitted.connect(_submit)
	col.add_child(_edit)

	for e: Dictionary in _hub.history:
		_add_line(e, true)
	_hub.added.connect(func(e: Dictionary) -> void: _add_line(e, false))
	_hub.cleared.connect(func() -> void:
		for l: Array in _lines:
			(l[0] as Node).queue_free()
		_lines.clear())
	var settings := UiContext.autoload("Settings")
	if settings != null:
		settings.connect("changed", func(section: String, _k: String) -> void:
			if section == "chat":
				_restyle())


func is_typing() -> bool:
	return _typing


func is_enabled() -> bool:
	return bool(UiContext.setting("chat", "enabled", true))


## Start typing; `prefill` "/" opens command mode.
func open(prefill := "") -> void:
	if not is_enabled():
		return
	_typing = true
	_edit.visible = true
	_edit.text = prefill
	_edit.grab_focus()
	_edit.caret_column = prefill.length()
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	if captures_game_input:
		UiContext.set_ui_open(true)
	typing_changed.emit(true)


func close() -> void:
	if not _typing:
		return
	_typing = false
	_edit.visible = always_open
	_edit.release_focus()
	_stick_bottom = true
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for l: Array in _lines:   # what you just read stays a moment, then fades
		l[1] = minf(float(l[1]), _fade_time() - 3.0)
	typing_changed.emit(false)


func _submit(text: String) -> void:
	_edit.text = ""
	if not always_open:
		close()
	if text.strip_edges() != "":
		_hub.submit(text)
	if always_open:
		_edit.grab_focus.call_deferred()


func _input(event: InputEvent) -> void:
	if not _typing and not (always_open and _edit.has_focus()):
		return
	if event.is_action_pressed("ui_cancel"):
		if always_open:
			_edit.release_focus()
		else:
			close()
		get_viewport().set_input_as_handled()
		return
	var k := event as InputEventKey
	if k != null and k.pressed and (k.keycode == KEY_PAGEUP or k.keycode == KEY_PAGEDOWN):
		var step := _scroll.size.y * 0.7 * (-1.0 if k.keycode == KEY_PAGEUP else 1.0)
		_scroll_by(step)
		get_viewport().set_input_as_handled()
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and get_global_rect().has_point(mb.position) \
			and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		_scroll_by(48.0 * (-1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0))
		get_viewport().set_input_as_handled()


func _scroll_by(px: float) -> void:
	var bar := _scroll.get_v_scroll_bar()
	_scroll.scroll_vertical = int(clampf(_scroll.scroll_vertical + px, 0.0, bar.max_value))
	_stick_bottom = _scroll.scroll_vertical >= int(bar.max_value - bar.page) - 2


## Kept for older callers (gallery, tests): a line straight into this box's hub.
func add_message(from_name: String, text: String, channel: String) -> void:
	_hub.add(from_name, text, channel)


func _add_line(e: Dictionary, old: bool) -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.selection_enabled = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.text = format_entry(e, bool(UiContext.setting("chat", "profanity_filter", true)))
	_style(l)
	_log.add_child(l)
	_lines.append([l, _fade_time() + 2.0 if old else 0.0])
	while _lines.size() > MAX_LINES:
		(_lines.pop_front()[0] as Node).queue_free()


## BBCode for one chat entry. Every user-supplied part is escaped.
static func format_entry(e: Dictionary, filter := true) -> String:
	var channel := String(e.get("channel", "party"))
	var from := ChatHub.escape(String(e.get("from", "")))
	var raw := String(e.get("text", ""))
	if filter and channel != "system" and channel != "info":
		raw = ChatHub.filter_profanity(raw)
	var text := ChatHub.escape(raw)
	var col: Color = CHANNEL_COLORS.get(channel, UiTheme.TEXT)
	var c := col.to_html(false)
	var name_c := UiTheme.ACCENT.to_html(false)
	if channel == "system":
		return "[color=#%s]◆ %s[/color]" % [c, text]
	if channel == "info" or from == "":
		return "[color=#%s]%s[/color]" % [c, text]
	if channel == "whisper":
		return "[color=#%s][i]%s whispers:[/i] %s[/color]" % [c, from, text]
	if channel == "whisper_out":
		return "[color=#%s][i]to %s:[/i] %s[/color]" % [c, from, text]
	if raw.begins_with("/me "):
		return "[color=#%s][i]* %s %s[/i][/color]" % [UiTheme.ACCENT_HOT.to_html(false), from, text.substr(4)]
	return "[color=#%s]%s[/color]  [color=#%s]%s[/color]" % [name_c, from, c, text]


func _style(l: RichTextLabel) -> void:
	var size_px := int(UiContext.setting("chat", "text_size", 15))
	l.add_theme_font_override("normal_font", UiTheme.MONO)
	l.add_theme_font_override("italics_font", UiTheme.MONO)
	l.add_theme_font_size_override("normal_font_size", size_px)
	l.add_theme_font_size_override("italics_font_size", size_px)
	l.add_theme_constant_override("outline_size", maxi(3, size_px / 4))
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.78))
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", maxi(4, size_px / 3))


func _restyle() -> void:
	for l: Array in _lines:
		_style(l[0])
	if not is_enabled() and _typing:
		close()


func _fade_time() -> float:
	return float(UiContext.setting("chat", "fade_time", 10.0))


func _process(delta: float) -> void:
	visible = is_enabled()
	var showing := _typing or always_open
	_backdrop.modulate.a = move_toward(_backdrop.modulate.a, 1.0 if _typing else 0.0, delta * 6.0)
	var fade := _fade_time()
	var opacity := clampf(float(UiContext.setting("chat", "opacity", 1.0)), 0.1, 1.0)
	for l: Array in _lines:
		l[1] += delta
		var a := 1.0 if showing else clampf((fade - float(l[1])) / 1.5, 0.0, 1.0)
		var c := l[0] as Control
		c.modulate.a = a * opacity
		# Faded lines take no room, so the visible ones sit at the bottom.
		c.visible = a > 0.0 or showing
