class_name ChatBox
extends VBoxContainer
## Bottom-left chat. Messages fade after a while; press the chat key to type.

signal typing_changed(active: bool)

const FADE_AFTER := 9.0
const MAX_LINES := 8
const CHANNEL_COLORS := {"global": UiTheme.TEXT, "party": UiTheme.FROST, "local": UiTheme.TEXT_DIM, "system": UiTheme.ACCENT}

var _log: VBoxContainer
var _edit: LineEdit
var _lines: Array = []  # [Label, age]
var _typing := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(420, 0)
	alignment = BoxContainer.ALIGNMENT_END
	_log = VBoxContainer.new()
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_theme_constant_override("separation", 1)
	add_child(_log)
	_edit = LineEdit.new()
	_edit.placeholder_text = "say something…  (Enter to send, Esc to cancel)"
	_edit.max_length = 160
	_edit.visible = false
	_edit.text_submitted.connect(_submit)
	add_child(_edit)
	UiContext.on("chat_message", add_message)


func is_typing() -> bool:
	return _typing


func open() -> void:
	_typing = true
	_edit.visible = true
	_edit.text = ""
	_edit.grab_focus()
	for l: Array in _lines:
		l[1] = 0.0
	typing_changed.emit(true)


func close() -> void:
	_typing = false
	_edit.visible = false
	_edit.release_focus()
	typing_changed.emit(false)


func _submit(text: String) -> void:
	var t := text.strip_edges()
	close()
	if t == "":
		return
	var net := UiContext.net()
	var online: bool = UiContext.call_on(net, "is_online", [], false)
	if online:
		UiContext.call_on(net, "send_chat", [t])
	else:
		add_message(str(UiContext.setting("gameplay", "player_name")), t, "local")


func _input(event: InputEvent) -> void:
	if _typing and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func add_message(from_name: String, text: String, channel: String) -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.custom_minimum_size.x = 420
	l.add_theme_font_size_override("normal_font_size", 13)
	l.add_theme_font_override("normal_font", UiTheme.MONO)
	var col: Color = CHANNEL_COLORS.get(channel, UiTheme.TEXT)
	if channel == "system" or from_name == "":
		l.text = "[color=#%s]· %s[/color]" % [col.to_html(false), _escape(text)]
	else:
		l.text = "[color=#%s]%s[/color]  [color=#%s]%s[/color]" % [UiTheme.ACCENT.to_html(false), _escape(from_name), col.to_html(false), _escape(text)]
	_log.add_child(l)
	_lines.append([l, 0.0])
	while _lines.size() > MAX_LINES:
		(_lines.pop_front()[0] as Node).queue_free()


static func _escape(s: String) -> String:
	return s.replace("[", "[lb]")


func _process(delta: float) -> void:
	for l: Array in _lines:
		l[1] += delta
		var a := 1.0 if _typing else clampf((FADE_AFTER - float(l[1])) / 1.5, 0.0, 1.0)
		(l[0] as Control).modulate.a = a
