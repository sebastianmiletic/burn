class_name SettingsMenu
extends Control
## Options overlay used from the main menu and the pause menu. Every control
## reads and writes `Settings`; changes apply immediately and persist.

signal closed

## Loaded at runtime: the Keybinds class refers to the Settings autoload, and a
## static dependency would stop this screen compiling where autoloads don't exist.
var _keybinds: Script = load("res://core/keybinds.gd")

const FPS_CAPS := [0, 30, 60, 90, 120, 144, 165, 240]
const RENDER_SCALES := [-1.0, 0.5, 0.62, 0.75, 0.85, 1.0]

var _tabs: TabContainer
var _rebinding := ""
var _rebind_button: Button
var _binding_buttons := {}


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UiTheme.scrim(0.72))

	var frame := TermFrame.new()
	frame.title = "SETTINGS"
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.custom_minimum_size = Vector2(860, 600)
	frame.size = frame.custom_minimum_size
	frame.position = -frame.size * 0.5
	frame.anchor_left = 0.5
	frame.anchor_top = 0.5
	frame.anchor_right = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -430
	frame.offset_right = 430
	frame.offset_top = -300
	frame.offset_bottom = 300
	add_child(frame)

	var outer := VBoxContainer.new()
	frame.add_child(outer)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.tab_changed.connect(func(_i: int) -> void: UiContext.sound("ui_click"))
	outer.add_child(_tabs)

	_build_graphics()
	_build_display()
	_build_audio()
	_build_controls()
	_build_gameplay()

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	var reset := UiTheme.button("Reset tab", _reset_tab)
	bottom.add_child(reset)
	var done := UiTheme.button("Done  [Esc]", close)
	bottom.add_child(done)
	outer.add_child(bottom)
	UiContext.sound("ui_open")
	done.grab_focus.call_deferred()


func close() -> void:
	UiContext.sound("ui_back")
	closed.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	if _rebinding != "":
		var code := 0
		if event is InputEventKey and event.pressed and not event.echo:
			var k := event as InputEventKey
			if k.keycode == KEY_ESCAPE:
				_finish_rebind()
				get_viewport().set_input_as_handled()
				return
			code = k.physical_keycode if k.physical_keycode != 0 else k.keycode
		elif event is InputEventMouseButton and event.pressed:
			var mb := event as InputEventMouseButton
			if mb.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				code = mb.button_index
		if code != 0:
			_keybinds.call("rebind", _rebinding, code)
			_finish_rebind()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _finish_rebind() -> void:
	_rebinding = ""
	_rebind_button = null
	for action: String in _binding_buttons:
		(_binding_buttons[action] as Button).text = str(_keybinds.call("label_for", action))


func _reset_tab() -> void:
	var section: String = ["graphics", "display", "audio", "controls", "gameplay"][_tabs.current_tab]
	UiContext.call_on(UiContext.autoload("Settings"), "reset_section", [section])
	var idx := _tabs.current_tab
	for c in _tabs.get_children():
		c.queue_free()
	await get_tree().process_frame
	_build_graphics()
	_build_display()
	_build_audio()
	_build_controls()
	_build_gameplay()
	_tabs.current_tab = idx


# --- Tab builders --------------------------------------------------------------------

func _page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	scroll.add_child(box)
	_tabs.add_child(scroll)
	return box


func _build_graphics() -> void:
	var p := _page("Graphics")
	_heading(p, "Rendering")
	_option(p, "graphics", "quality", "Quality preset", UiContext.settings_const("QUALITY_NAMES"),
			"Low and Medium skip global illumination and reflections. High and Ultra add them.")
	_option(p, "graphics", "style", "Render style", UiContext.settings_const("STYLE_NAMES"),
			"Ember is the warm sepia look. Full colour keeps the scene's own colours.")
	_option(p, "graphics", "cell_preset", "Glyph size", UiContext.settings_const("CELL_NAMES"), "Smaller glyphs show more detail.")
	var scale_names: Array = ["Follow preset", "50%", "62%", "75%", "85%", "100%"]
	_option_values(p, "graphics", "render_scale", "3D resolution", scale_names, RENDER_SCALES,
			"Resolution of the scene behind the glyphs. Glyphs are always drawn at full resolution.")
	_slider(p, "graphics", "fov", "Field of view", 55, 100, 1, "%d°")
	_heading(p, "Image")
	_slider(p, "graphics", "brightness", "Brightness", 0.5, 1.5, 0.01, "%d%%", 100.0)
	_slider(p, "graphics", "bloom", "Glow", 0.0, 2.0, 0.05, "%d%%", 100.0)
	_slider(p, "graphics", "fog", "Fog", 0.0, 2.0, 0.05, "%d%%", 100.0)
	_slider(p, "graphics", "bg_fill", "Cell background", 0.0, 0.6, 0.01, "%d%%", 100.0)
	_slider(p, "graphics", "vignette", "Vignette", 0.0, 1.0, 0.01, "%d%%", 100.0)
	_slider(p, "graphics", "grain", "Film grain", 0.0, 0.2, 0.005, "%d%%", 500.0)
	_check(p, "graphics", "edges", "Edge glyphs", "Outline silhouettes with | / - \\ strokes.")
	_check(p, "graphics", "flicker", "Glyph flicker", "Dark glyphs flicker like dying embers.")
	_check(p, "graphics", "shimmer", "Chromatic shimmer", "Very bright glyphs split into colour fringes.")


func _build_display() -> void:
	var p := _page("Display")
	_option(p, "display", "window_mode", "Window", UiContext.settings_const("WINDOW_MODE_NAMES"),
			"Fill screen covers the whole display without a separate fullscreen space.")
	_check(p, "display", "vsync", "Vertical sync", "Prevents tearing. Turn off for the lowest input latency.")
	var cap_names: Array = []
	for c: int in FPS_CAPS:
		cap_names.append("Unlimited" if c == 0 else "%d fps" % c)
	_option_values(p, "display", "fps_cap", "Frame cap", cap_names, FPS_CAPS)


func _build_audio() -> void:
	var p := _page("Audio")
	_slider(p, "audio", "master", "Master", 0.0, 1.0, 0.01, "%d%%", 100.0)
	_slider(p, "audio", "music", "Music", 0.0, 1.0, 0.01, "%d%%", 100.0)
	_slider(p, "audio", "sfx", "Effects", 0.0, 1.0, 0.01, "%d%%", 100.0)
	_slider(p, "audio", "ambient", "Ambience", 0.0, 1.0, 0.01, "%d%%", 100.0)


func _build_controls() -> void:
	var p := _page("Controls")
	_heading(p, "Mouse")
	_slider(p, "gameplay", "mouse_sensitivity", "Sensitivity", 0.2, 3.0, 0.05, "%d%%", 100.0)
	_check(p, "gameplay", "invert_y", "Invert vertical look")
	_heading(p, "Keys  ·  click a binding, then press a key or mouse button  ·  Esc cancels")
	_binding_buttons.clear()
	var actions: Dictionary = _keybinds.get("ACTIONS")
	var labels: Dictionary = _keybinds.get("LABELS")
	for action: String in actions:
		var row := _row(p, str(labels.get(action, action)))
		var b := UiTheme.button(str(_keybinds.call("label_for", action)))
		b.custom_minimum_size = Vector2(220, 0)
		b.add_theme_color_override("font_color", UiTheme.ACCENT)
		b.pressed.connect(func() -> void:
			_finish_rebind()
			_rebinding = action
			_rebind_button = b
			b.text = "press a key…")
		row.add_child(b)
		_binding_buttons[action] = b


func _build_gameplay() -> void:
	var p := _page("Gameplay")
	var row := _row(p, "Name")
	var edit := LineEdit.new()
	edit.text = str(UiContext.setting("gameplay", "player_name"))
	edit.max_length = 20
	edit.custom_minimum_size = Vector2(260, 0)
	edit.text_changed.connect(func(t: String) -> void:
		if t.strip_edges() != "":
			UiContext.set_setting("gameplay", "player_name", t.strip_edges()))
	row.add_child(edit)
	_slider(p, "gameplay", "camera_shake", "Camera shake", 0.0, 1.5, 0.05, "%d%%", 100.0)


# --- Row helpers --------------------------------------------------------------------

func _heading(parent: Control, text: String) -> void:
	parent.add_child(UiTheme.spacer(6))
	parent.add_child(UiTheme.label(text.to_upper(), UiTheme.SIZE_SMALL, UiTheme.ACCENT_DIM))


func _row(parent: Control, text: String, hint := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := UiTheme.label(text, UiTheme.SIZE_BODY, UiTheme.TEXT)
	l.custom_minimum_size = Vector2(240, 30)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if hint != "":
		l.tooltip_text = hint
		l.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(l)
	parent.add_child(row)
	return row


func _option(parent: Control, section: String, key: String, text: String, names: Array, hint := "") -> void:
	var values: Array = []
	for i in names.size():
		values.append(i)
	_option_values(parent, section, key, text, names, values, hint)


func _option_values(parent: Control, section: String, key: String, text: String, names: Array, values: Array, hint := "") -> void:
	var row := _row(parent, text, hint)
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(260, 0)
	opt.add_theme_color_override("font_color", UiTheme.ACCENT)
	var current: Variant = UiContext.setting(section, key)
	for i in names.size():
		opt.add_item(str(names[i]), i)
		if is_equal_approx(float(values[i]), float(current)):
			opt.select(i)
	opt.item_selected.connect(func(i: int) -> void:
		var v: Variant = values[i]
		if current is int:
			v = int(v)
		UiContext.set_setting(section, key, v))
	opt.tooltip_text = hint
	row.add_child(opt)


func _slider(parent: Control, section: String, key: String, text: String, lo: float, hi: float, step: float, fmt: String, display_scale := 1.0) -> void:
	var row := _row(parent, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(UiContext.setting(section, key))
	s.custom_minimum_size = Vector2(300, 24)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value_l := UiTheme.label(fmt % roundi(s.value * display_scale), UiTheme.SIZE_BODY, UiTheme.ACCENT)
	value_l.custom_minimum_size = Vector2(70, 0)
	value_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(v: float) -> void:
		value_l.text = fmt % roundi(v * display_scale)
		UiContext.set_setting(section, key, v))
	row.add_child(s)
	row.add_child(value_l)


func _check(parent: Control, section: String, key: String, text: String, hint := "") -> void:
	var row := _row(parent, text, hint)
	var c := CheckBox.new()
	c.button_pressed = bool(UiContext.setting(section, key))
	c.text = "on" if c.button_pressed else "off"
	c.toggled.connect(func(on: bool) -> void:
		c.text = "on" if on else "off"
		UiContext.sound("ui_click")
		UiContext.set_setting(section, key, on))
	row.add_child(c)
