class_name DialogBox
extends Control
## NPC conversation at the bottom of the screen. Lines type out one at a
## time (Space / click / E to advance); options appear on the last line and
## are chosen with 1–4 or the mouse. Choosing emits Events.dialog_choice;
## a conversation without options ends with the choice "leave".

const CHARS_PER_SECOND := 60.0

var _npc: Node
var _lines := PackedStringArray()
var _options: Array = []
var _line := 0
var _shown := 0.0
var _frame: TermFrame
var _text: Label
var _opts_box: VBoxContainer
var _hint: Label
var is_open := false


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_frame = TermFrame.new()
	_frame.anchor_left = 0.5
	_frame.anchor_right = 0.5
	_frame.anchor_top = 1.0
	_frame.anchor_bottom = 1.0
	_frame.offset_left = -420
	_frame.offset_right = 420
	_frame.offset_top = -360
	_frame.offset_bottom = -110
	_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	_frame.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_advance())
	add_child(_frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_frame.add_child(box)
	_text = UiTheme.label("", 16, UiTheme.TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(780, 60)
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_text)
	_opts_box = VBoxContainer.new()
	_opts_box.add_theme_constant_override("separation", 0)
	box.add_child(_opts_box)
	_hint = UiTheme.label("", 11, UiTheme.TEXT_FAINT, HORIZONTAL_ALIGNMENT_RIGHT)
	box.add_child(_hint)
	UiContext.on("dialog_open", open_dialog)
	UiContext.on("dialog_close", close)


func open_dialog(npc: Node, title: String, lines: PackedStringArray, options: Array) -> void:
	_npc = npc
	_lines = lines if not lines.is_empty() else PackedStringArray(["…"])
	_options = options
	_line = 0
	_shown = 0.0
	_frame.title = title.to_upper()
	_clear_options()
	visible = true
	if not is_open:
		is_open = true
		UiContext.set_ui_open(true)
		UiContext.sound("ui_open")


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	UiContext.set_ui_open(false)


func _clear_options() -> void:
	for c in _opts_box.get_children():
		c.queue_free()


func _process(delta: float) -> void:
	if not is_open:
		return
	var full := _lines[_line]
	if _shown < full.length():
		var before := int(_shown)
		_shown = minf(_shown + delta * CHARS_PER_SECOND, full.length())
		if int(_shown) / 6 != before / 6:
			UiContext.sound("ui_hover")
	_text.text = full.substr(0, int(_shown))
	var last := _line == _lines.size() - 1
	var done := _shown >= full.length()
	if last and done and _opts_box.get_child_count() == 0 and not _options.is_empty():
		_show_options()
	_hint.text = "" if not done else ("" if (last and not _options.is_empty()) else ("space · continue" if not last else "space · farewell"))


func _show_options() -> void:
	var first: Button = null
	for i in _options.size():
		var o: Dictionary = _options[i]
		var id: String = str(o.get("id", ""))
		var b := UiTheme.button("%d.  %s" % [i + 1, o.get("text", "")], func() -> void: _choose(id))
		_opts_box.add_child(b)
		if first == null:
			first = b
	if first != null:
		first.grab_focus()


func _advance() -> void:
	var full := _lines[_line]
	if _shown < full.length():
		_shown = full.length()
		return
	if _line < _lines.size() - 1:
		_line += 1
		_shown = 0.0
		return
	if _options.is_empty():
		_choose("leave")


func _choose(id: String) -> void:
	UiContext.sound("ui_click")
	var npc := _npc
	close()
	UiContext.emit_event("dialog_choice", [npc, id])


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		_choose("leave")
		get_viewport().set_input_as_handled()
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_SPACE or k.keycode == KEY_E or k.keycode == KEY_ENTER:
		if _opts_box.get_child_count() == 0:
			_advance()
			get_viewport().set_input_as_handled()
	elif k.keycode >= KEY_1 and k.keycode <= KEY_4:
		var i := int(k.keycode - KEY_1)
		if i < _options.size() and _opts_box.get_child_count() > 0:
			_choose(str(_options[i].get("id", "")))
			get_viewport().set_input_as_handled()
