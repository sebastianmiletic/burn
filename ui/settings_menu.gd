class_name SettingsMenu
extends Control
## Options overlay used from the main menu and the pause menu. Every control
## reads and writes `Settings`; changes apply immediately and persist.
## A centred framed panel: Cinzel tabs, striped option rows, and a footer
## that explains whichever option is hovered or focused.

signal closed

## Loaded at runtime: the Keybinds class refers to the Settings autoload, and a
## static dependency would stop this screen compiling where autoloads don't exist.
var _keybinds: Script = load("res://core/keybinds.gd")

const FPS_CAPS := [0, 30, 60, 90, 120, 144, 165, 240]
const RENDER_SCALES := [-1.0, 0.5, 0.62, 0.75, 0.85, 1.0]
const SECTIONS := ["graphics", "display", "audio", "controls", "gameplay"]

var _tabs: TabContainer
var _panel: MenuPanel
var _hint: Label
var _rebinding := ""
var _rebind_button: Button
var _binding_buttons := {}
var _row_index := 0


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UiTheme.scrim(0.55))

	_panel = MenuPanel.new("SETTINGS")
	_panel.subtitle = "changes apply at once and are remembered"
	_panel.padding = Vector2(30, 24)
	add_child(_panel)
	resized.connect(_layout)
	_layout()

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	_panel.add_child(outer)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.tab_alignment = TabBar.ALIGNMENT_CENTER
	_tabs.add_theme_font_override("font", UiTheme.title_font_spaced(700, 2))
	_tabs.add_theme_font_size_override("font_size", 15)
	_tabs.tab_changed.connect(func(_i: int) -> void:
		UiContext.sound("ui_click")
		_set_hint(""))
	outer.add_child(_tabs)

	_build_all()

	var rule := Control.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.draw.connect(func() -> void: rule.draw_line(Vector2(0, 0), Vector2(rule.size.x, 0), Color(UiTheme.BORDER, 0.6), 1.0))
	outer.add_child(rule)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	_hint = UiTheme.label("", UiTheme.SIZE_SMALL, UiTheme.TEXT_DIM)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hint.custom_minimum_size = Vector2(300, 34)
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(_hint)
	var reset := MenuOption.new("RESET TAB", _reset_tab, 14)
	reset.custom_minimum_size = Vector2(170, 38)
	bottom.add_child(reset)
	var done := MenuOption.new("DONE", close, 16)
	done.custom_minimum_size = Vector2(150, 38)
	bottom.add_child(done)
	outer.add_child(bottom)
	_set_hint("")
	UiContext.sound("ui_open")
	done.grab_focus.call_deferred()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)


## Centred, as large as fits comfortably.
func _layout() -> void:
	if _panel == null:
		return
	var s := size if size.x > 0.0 else Vector2(1600, 900)
	var w := minf(940.0, s.x - 60.0)
	var h := minf(700.0, s.y - 60.0)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -w * 0.5
	_panel.offset_right = w * 0.5
	_panel.offset_top = -h * 0.5
	_panel.offset_bottom = h * 0.5


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
	elif event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_TAB \
			and (event as InputEventKey).ctrl_pressed:
		var step := -1 if (event as InputEventKey).shift_pressed else 1
		_tabs.current_tab = posmod(_tabs.current_tab + step, _tabs.get_tab_count())
		get_viewport().set_input_as_handled()


func _finish_rebind() -> void:
	_rebinding = ""
	_rebind_button = null
	for action: String in _binding_buttons:
		(_binding_buttons[action] as Button).text = str(_keybinds.call("label_for", action))


func _reset_tab() -> void:
	var section: String = SECTIONS[_tabs.current_tab]
	UiContext.call_on(UiContext.autoload("Settings"), "reset_section", [section])
	var idx := _tabs.current_tab
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	_build_all()
	_tabs.current_tab = idx
	_set_hint("Restored the defaults of this tab.")


func _build_all() -> void:
	_build_graphics()
	_build_display()
	_build_audio()
	_build_controls()
	_build_gameplay()
	_build_chat()


func _set_hint(text: String) -> void:
	if _hint == null:
		return
	_hint.text = text if text != "" else "Esc closes  ·  Ctrl+Tab switches tabs  ·  hover an option to read about it"
	_hint.add_theme_color_override("font_color", UiTheme.TEXT if text != "" else UiTheme.TEXT_FAINT)


# --- Tab builders --------------------------------------------------------------------

func _page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 0)
	scroll.add_child(box)
	_tabs.add_child(scroll)
	_row_index = 0
	return box


func _build_graphics() -> void:
	var p := _page("Graphics")
	_heading(p, "Rendering")
	_option(p, "graphics", "quality", "Quality preset", UiContext.settings_const("QUALITY_NAMES"),
			"Low and Medium skip global illumination and reflections. High and Ultra add them.")
	var scale_names: Array = ["Follow preset", "50%", "62%", "75%", "85%", "100%"]
	_option_values(p, "graphics", "render_scale", "3D resolution", scale_names, RENDER_SCALES,
			"Resolution the 3D scene renders at before it is upscaled (MetalFX / FSR) to the full window. The UI is always native.")
	_check(p, "graphics", "adaptive_resolution", "Adaptive resolution", "With Follow preset selected, adjusts 3D resolution toward 60 FPS. Does not guarantee a minimum frame rate.")
	_check(p, "graphics", "altitude_blur", "Mountain distance blur", "Softens distant scenery as altitude increases. Turn off for a clearer view; snow remains.")
	_slider(p, "graphics", "fov", "Field of view", 55, 100, 1, "%d°", 1.0, "How wide the camera sees.")
	_heading(p, "Image")
	_slider(p, "graphics", "brightness", "Brightness", 0.5, 1.5, 0.01, "%d%%", 100.0, "Overall brightness of the image.")
	_slider(p, "graphics", "bloom", "Glow", 0.0, 2.0, 0.05, "%d%%", 100.0, "Bloom around fire, magic, lava and the sun.")
	_slider(p, "graphics", "fog", "Fog", 0.0, 2.0, 0.05, "%d%%", 100.0, "Distance haze and volumetric fog.")
	_slider(p, "graphics", "vignette", "Vignette", 0.0, 1.0, 0.01, "%d%%", 100.0, "Darkens the corners of the screen.")
	_slider(p, "graphics", "grain", "Film grain", 0.0, 0.2, 0.005, "%d%%", 500.0, "A little noise over the image.")


func _build_display() -> void:
	var p := _page("Display")
	_heading(p, "Window")
	_option(p, "display", "window_mode", "Window", UiContext.settings_const("WINDOW_MODE_NAMES"),
			"Fill screen covers the whole display without a separate fullscreen space.")
	_check(p, "display", "vsync", "Vertical sync", "Prevents tearing. Turn off for the lowest input latency.")
	var cap_names: Array = []
	for c: int in FPS_CAPS:
		cap_names.append("Unlimited" if c == 0 else "%d fps" % c)
	_option_values(p, "display", "fps_cap", "Frame cap", cap_names, FPS_CAPS, "Limits the frame rate to save power and heat.")


func _build_audio() -> void:
	var p := _page("Audio")
	_heading(p, "Volume")
	_slider(p, "audio", "master", "Master", 0.0, 1.0, 0.01, "%d%%", 100.0, "Everything you hear.")
	_slider(p, "audio", "music", "Music", 0.0, 1.0, 0.01, "%d%%", 100.0, "The score.")
	_slider(p, "audio", "sfx", "Effects", 0.0, 1.0, 0.01, "%d%%", 100.0, "Combat, footsteps, spells and the interface.")
	_slider(p, "audio", "ambient", "Ambience", 0.0, 1.0, 0.01, "%d%%", 100.0, "Wind, rain, fire and the sounds of places.")


func _build_controls() -> void:
	var p := _page("Controls")
	_heading(p, "Mouse")
	_slider(p, "gameplay", "mouse_sensitivity", "Sensitivity", 0.2, 3.0, 0.05, "%d%%", 100.0, "How far the camera turns per mouse movement.")
	_check(p, "gameplay", "invert_y", "Invert vertical look", "Moving the mouse up looks down.")
	_heading(p, "Keys")
	_binding_buttons.clear()
	var actions: Dictionary = _keybinds.get("ACTIONS")
	var labels: Dictionary = _keybinds.get("LABELS")
	for action: String in actions:
		var row := _row(p, str(labels.get(action, action)), "Click, then press a key or mouse button. Esc cancels.")
		var b := UiTheme.button(str(_keybinds.call("label_for", action)))
		b.custom_minimum_size = Vector2(220, 0)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_color_override("font_color", UiTheme.ACCENT)
		b.add_theme_stylebox_override("normal", _key_box(false))
		b.add_theme_stylebox_override("hover", _key_box(true))
		b.add_theme_stylebox_override("focus", _key_box(true))
		b.pressed.connect(func() -> void:
			_finish_rebind()
			_rebinding = action
			_rebind_button = b
			b.text = "press a key…")
		_hook_hint(b, "Click, then press a key or mouse button. Esc cancels.")
		row.add_child(b)
		_binding_buttons[action] = b


func _key_box(hot: bool) -> StyleBoxFlat:
	var s := UiTheme.flat(Color(1.0, 0.62, 0.22, 0.12 if hot else 0.04), 4)
	s.border_color = UiTheme.ACCENT_DIM if hot else Color(UiTheme.BORDER, 0.7)
	s.set_border_width_all(1)
	s.content_margin_left = 10
	s.content_margin_right = 10
	return s


func _build_gameplay() -> void:
	var p := _page("Gameplay")
	_heading(p, "You")
	var row := _row(p, "Name", "The name others see in a warband, and on your save.")
	var edit := LineEdit.new()
	edit.text = str(UiContext.setting("gameplay", "player_name"))
	edit.max_length = 20
	edit.custom_minimum_size = Vector2(300, 0)
	edit.text_changed.connect(func(t: String) -> void:
		if t.strip_edges() != "":
			UiContext.set_setting("gameplay", "player_name", t.strip_edges()))
	_hook_hint(edit, "The name others see in a warband, and on your save.")
	row.add_child(edit)
	_heading(p, "Comfort")
	_slider(p, "gameplay", "camera_shake", "Camera shake", 0.0, 1.5, 0.05, "%d%%", 100.0, "How hard big hits and explosions shake the view.")


# --- Row helpers --------------------------------------------------------------------

func _heading(parent: Control, text: String) -> void:
	parent.add_child(UiTheme.spacer(10))
	var l := UiTheme.title(text.to_upper(), 13, UiTheme.ACCENT_DIM, 700)
	l.add_theme_font_override("font", UiTheme.title_font_spaced(700, 3))
	parent.add_child(l)
	parent.add_child(UiTheme.spacer(4))
	_row_index = 0


## One option row: a label on the left, its control added on the right by the
## caller. Rows alternate a faint stripe; the row lights while its control has focus.
func _row(parent: Control, text: String, hint := "") -> HBoxContainer:
	var panel := PanelContainer.new()
	var base := UiTheme.flat(Color(1, 1, 1, 0.025 if _row_index % 2 == 0 else 0.0), 0)
	base.content_margin_left = 12
	base.content_margin_right = 12
	base.content_margin_top = 3
	base.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", base)
	_row_index += 1
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var l := UiTheme.label(text, UiTheme.SIZE_BODY, UiTheme.TEXT)
	l.custom_minimum_size = Vector2(250, 32)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if hint != "":
		l.tooltip_text = hint
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		l.mouse_entered.connect(_set_hint.bind(hint))
	row.add_child(l)
	var lit := base.duplicate() as StyleBoxFlat
	lit.bg_color = UiTheme.BG_HOVER
	lit.border_color = UiTheme.ACCENT_DIM
	lit.border_width_left = 2
	row.child_entered_tree.connect(func(c: Node) -> void:
		if c is Control and c != l:
			(c as Control).focus_entered.connect(func() -> void:
				panel.add_theme_stylebox_override("panel", lit)
				if hint != "":
					_set_hint(hint))
			(c as Control).focus_exited.connect(func() -> void: panel.add_theme_stylebox_override("panel", base)))
	parent.add_child(panel)
	return row


func _hook_hint(c: Control, hint: String) -> void:
	if hint != "":
		c.mouse_entered.connect(_set_hint.bind(hint))


func _option(parent: Control, section: String, key: String, text: String, names: Array, hint := "") -> void:
	var values: Array = []
	for i in names.size():
		values.append(i)
	_option_values(parent, section, key, text, names, values, hint)


func _option_values(parent: Control, section: String, key: String, text: String, names: Array, values: Array, hint := "") -> void:
	var row := _row(parent, text, hint)
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(300, 0)
	opt.add_theme_color_override("font_color", UiTheme.ACCENT)
	opt.add_theme_stylebox_override("normal", _key_box(false))
	opt.add_theme_stylebox_override("hover", _key_box(true))
	opt.add_theme_stylebox_override("focus", _key_box(true))
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
	_hook_hint(opt, hint)
	row.add_child(opt)


func _slider(parent: Control, section: String, key: String, text: String, lo: float, hi: float, step: float, fmt: String,
		display_scale := 1.0, hint := "") -> void:
	var row := _row(parent, text, hint)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(UiContext.setting(section, key))
	s.custom_minimum_size = Vector2(300, 24)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value_l := UiTheme.label(fmt % roundi(s.value * display_scale), UiTheme.SIZE_BODY, UiTheme.ACCENT)
	value_l.custom_minimum_size = Vector2(64, 0)
	value_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(v: float) -> void:
		value_l.text = fmt % roundi(v * display_scale)
		UiContext.set_setting(section, key, v))
	_hook_hint(s, hint)
	row.add_child(s)
	row.add_child(value_l)


func _check(parent: Control, section: String, key: String, text: String, hint := "") -> void:
	var row := _row(parent, text, hint)
	var c := CheckBox.new()
	c.button_pressed = bool(UiContext.setting(section, key))
	c.text = "on" if c.button_pressed else "off"
	c.custom_minimum_size = Vector2(90, 0)
	c.toggled.connect(func(on: bool) -> void:
		c.text = "on" if on else "off"
		UiContext.sound("ui_click")
		UiContext.set_setting(section, key, on))
	_hook_hint(c, hint)
	row.add_child(c)


## Chat options, appended to the Gameplay page (its own page if that is missing).
func _build_chat() -> void:
	var scroll := _tabs.get_node_or_null("Gameplay")
	var p: VBoxContainer = scroll.get_child(0) if scroll != null and scroll.get_child_count() > 0 else _page("Chat")
	_heading(p, "Chat")
	_check(p, "chat", "enabled", "Show chat", "Off hides the chat panel and stops T, Enter and / from opening it.")
	_slider(p, "chat", "text_size", "Text size", 11, 24, 1, "%d px", 1.0, "Size of chat text.")
	_slider(p, "chat", "opacity", "Opacity", 0.2, 1.0, 0.05, "%d%%", 100.0, "How strongly chat text shows over the world.")
	_slider(p, "chat", "fade_time", "Fade after", 3.0, 60.0, 1.0, "%d s", 1.0, "Seconds before a message fades. Open the chat (T) to see them all again.")
	_check(p, "chat", "show_system", "System messages", "Joins, leaves, deaths, defeated bosses and completed quests in the chat.")
	_check(p, "chat", "profanity_filter", "Filter profanity", "Masks common swear words in other players' messages.")
