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


var _gfx_preset: OptionButton
var _gfx_page: VBoxContainer


func _build_graphics() -> void:
	_gfx_page = _page("Graphics")
	_fill_graphics(_gfx_page)


## Every graphics option. Preset-driven options show what is in effect; changing
## one makes the preset read "Custom". Hints name the performance cost.
func _fill_graphics(p: VBoxContainer) -> void:
	var levels4: Array = ["Low", "Medium", "High", "Ultra"]
	_heading(p, "Quality")
	var preset_hint := "Sets every option below at once. High targets 60 FPS on an Apple M4 class GPU; Ultra is for faster GPUs. Changing any single option makes this Custom."
	var row := _row(p, "Quality preset", preset_hint)
	_gfx_preset = OptionButton.new()
	_gfx_preset.custom_minimum_size = Vector2(300, 0)
	_gfx_preset.add_theme_color_override("font_color", UiTheme.ACCENT)
	_gfx_preset.add_theme_stylebox_override("normal", _key_box(false))
	_gfx_preset.add_theme_stylebox_override("hover", _key_box(true))
	_gfx_preset.add_theme_stylebox_override("focus", _key_box(true))
	for n: String in UiContext.settings_const("QUALITY_NAMES") + ["Custom"]:
		_gfx_preset.add_item(n)
	_gfx_preset.set_item_disabled(_gfx_preset.item_count - 1, true)
	_gfx_sync_preset()
	_gfx_preset.item_selected.connect(func(i: int) -> void:
		if i < 4:
			UiContext.call_on(UiContext.autoload("Settings"), "apply_quality_preset", [i])
			_gfx_rebuild.call_deferred())
	_hook_hint(_gfx_preset, preset_hint)
	row.add_child(_gfx_preset)

	_heading(p, "Resolution and anti-aliasing")
	_option_values(p, "graphics", "upscaler", "Upscaler", UiContext.settings_const("UPSCALER_NAMES"), [0, 1, 2, 3, 4, 5],
			"How the 3D image is scaled up to the window. Automatic: MetalFX spatial on Mac, FSR 1 elsewhere (cheap). Temporal upscalers (FSR 2, MetalFX temporal) look cleaner but cost 2-15 ms more per frame on this class of GPU.")
	var scale_names: Array = ["Follow preset", "50%", "62%", "75%", "85%", "100%"]
	_option_values(p, "graphics", "render_scale", "3D resolution", scale_names, RENDER_SCALES,
			"Resolution the 3D scene renders at before upscaling. GPU cost grows with the pixel count: 100% costs about twice 70%. The UI is always native.")
	_check(p, "graphics", "adaptive_resolution", "Adaptive resolution", "With 3D resolution on Follow preset, lowers the 3D resolution when the GPU cannot hold 60 FPS. No cost; does not help when the CPU is the limit.")
	_slider(p, "graphics", "sharpness", "Sharpness", 0.0, 1.0, 0.05, "%d%%", 100.0, "Sharpening applied by the FSR / MetalFX upscaler. Free; no effect at native resolution.")
	_gfx_option(p, "antialiasing", "Anti-aliasing", ["Off", "FXAA", "TAA", "MSAA 2x", "MSAA 4x"],
			"Smooths jagged edges. FXAA: almost free, slightly soft. TAA: about 1 ms, the steadiest grass and foliage, can ghost. MSAA: geometry edges only, 2-6 ms. Ignored when a temporal upscaler is on.")
	var hdr_ok := DisplayServer.get_name() != "headless" and DisplayServer.window_is_hdr_output_supported(0)
	_check(p, "graphics", "hdr", "HDR output", "Sends a high dynamic range image to an HDR display (brighter highlights). No GPU cost." + ("" if hdr_ok else " This display or renderer does not report HDR support, so it has no effect here."))

	_heading(p, "Lighting")
	_gfx_option(p, "shadows", "Shadows", ["Off", "Low", "Medium", "High", "Ultra"],
			"Sun and moon shadow resolution, softness and reach (40 m on Low to 150 m on Ultra). One of the biggest costs: High about 3-5 ms, Ultra about twice that.")
	_gfx_option(p, "gi", "Global illumination", ["Off", "SDFGI", "SDFGI high"],
			"Bounced light from the sun, sky and torches (SDFGI). Interiors and caves read naturally. About 3-6 ms; high uses more rays and cascades. Forward+ only.")
	_gfx_option(p, "ssao", "Ambient occlusion", ["Off", "Low", "Medium", "High"],
			"Contact darkening in creases, under rocks and eaves. 0.5-2.5 ms depending on level.")
	_gfx_option(p, "ssil", "Screen-space bounce light", ["Off", "On"],
			"Colour bleeding between nearby surfaces on top of global illumination. About 2-4 ms.")
	_gfx_option(p, "ssr", "Reflections", ["Off", "Low", "High"],
			"Screen-space reflections in water and wet stone. 1-3 ms. Off-screen objects fall back to the sky reflection.")
	_gfx_option(p, "volumetric_fog", "Volumetric fog", ["Off", "Low", "High"],
			"Light shafts through mist, halos around torches in caves, fog pooling in valleys. Low about 1-2 ms, High 3-4 ms. Distance and height fog stay on when off.")

	_heading(p, "World detail")
	var vd := int(UiContext.call_on(UiContext.autoload("Settings"), "gfx", ["view_distance"], 10))
	_gfx_slider(p, "view_distance", "View distance", 4, 16, vd, "%d m", 16.0,
			"Radius of fully detailed terrain around you; beyond it the distant-land horizon takes over. Large CPU and GPU cost: each step adds terrain to stream, mesh and draw.")
	_gfx_option(p, "foliage", "Foliage", levels4,
			"Density and draw distance of grass, flowers and bushes. One of the largest GPU costs in forests and meadows (2-10 ms).")
	_gfx_option(p, "mesh_detail", "Mesh detail", levels4,
			"Distance at which trees and models switch to simpler versions. Higher keeps full detail further away: 1-4 ms in forests.")
	_gfx_option(p, "texture_quality", "Texture filtering", levels4,
			"Texture sharpness at distance and at grazing angles (mip bias, anisotropic filtering 2x-16x). Under 1 ms; Low saves memory bandwidth on integrated GPUs.")
	_gfx_option(p, "effects", "Effects", levels4,
			"Particles in rain, snow, dust and embers, and how many nearby torch and fungus lights are lit. 0.5-3 ms in storms and caves.")

	_heading(p, "Camera")
	_slider(p, "graphics", "fov", "Field of view", 55, 100, 1, "%d°", 1.0, "How wide the camera sees. Wider shows more of the world at once: slightly more to draw.")
	_slider(p, "graphics", "motion_blur", "Motion blur", 0.0, 1.0, 0.05, "%d%%", 100.0, "Blurs the image while the camera turns. Off by default. About 0.5-1 ms when on.")
	_check(p, "graphics", "depth_of_field", "Depth of field", "Softens the far distance like a camera lens. About 1-2 ms.")
	_check(p, "graphics", "altitude_blur", "Mountain distance blur", "Softens distant scenery as altitude increases. About 1 ms when it applies. Turn off for a clearer view.")

	_heading(p, "Image")
	_slider(p, "graphics", "brightness", "Brightness", 0.5, 1.5, 0.01, "%d%%", 100.0, "Overall brightness of the image. Use Calibrate to set it for your display. Free.")
	var cal_hint := "Shows a test image to set brightness so dark caves stay dark but readable. Free."
	var crow := _row(p, "Brightness calibration", cal_hint)
	var cal := UiTheme.button("Calibrate…", _gfx_calibrate)
	cal.custom_minimum_size = Vector2(220, 0)
	_hook_hint(cal, cal_hint)
	crow.add_child(cal)
	_slider(p, "graphics", "bloom", "Glow", 0.0, 2.0, 0.05, "%d%%", 100.0, "Bloom around fire, magic, lava and the sun. About 0.5-1 ms when on (0% turns it off).")
	_slider(p, "graphics", "fog", "Fog", 0.0, 2.0, 0.05, "%d%%", 100.0, "Thickness of distance haze, height fog and volumetric fog. 0% also switches volumetric fog off and saves its cost.")
	_check(p, "graphics", "sun_shafts", "Sun shafts and lens flare", "Rays from the sun through gaps and a soft lens flare when looking towards it. About 0.5 ms while the sun is in view.")
	_slider(p, "graphics", "chromatic_aberration", "Chromatic aberration", 0.0, 1.0, 0.05, "%d%%", 100.0, "Colour fringes towards the screen edges, like a lens. About 0.3 ms when on.")
	_slider(p, "graphics", "vignette", "Vignette", 0.0, 1.0, 0.01, "%d%%", 100.0, "Darkens the corners of the screen. Free.")
	_slider(p, "graphics", "grain", "Film grain", 0.0, 0.2, 0.005, "%d%%", 500.0, "A little noise over the image. Free.")


func _gfx_rebuild() -> void:
	if _gfx_page == null or not is_instance_valid(_gfx_page):
		return
	for c in _gfx_page.get_children():
		_gfx_page.remove_child(c)
		c.queue_free()
	_row_index = 0
	_fill_graphics(_gfx_page)


## Shows the preset in effect, or Custom when options were overridden.
func _gfx_sync_preset() -> void:
	if _gfx_preset == null or not is_instance_valid(_gfx_preset):
		return
	var custom := bool(UiContext.call_on(UiContext.autoload("Settings"), "graphics_is_custom", [], false))
	_gfx_preset.select(_gfx_preset.item_count - 1 if custom else clampi(int(UiContext.setting("graphics", "quality", 2)), 0, 3))


## A preset-driven option: shows the level in effect, writes an override.
func _gfx_option(parent: Control, key: String, text: String, names: Array, hint: String) -> void:
	var row := _row(parent, text, hint)
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(300, 0)
	opt.add_theme_color_override("font_color", UiTheme.ACCENT)
	opt.add_theme_stylebox_override("normal", _key_box(false))
	opt.add_theme_stylebox_override("hover", _key_box(true))
	opt.add_theme_stylebox_override("focus", _key_box(true))
	for n: String in names:
		opt.add_item(n)
	opt.select(clampi(int(UiContext.call_on(UiContext.autoload("Settings"), "gfx", [key], 0)), 0, names.size() - 1))
	opt.item_selected.connect(func(i: int) -> void:
		UiContext.set_setting("graphics", key, i)
		_gfx_sync_preset())
	opt.tooltip_text = hint
	_hook_hint(opt, hint)
	row.add_child(opt)


## An integer preset-driven slider, applied when released (view distance restreams the world).
func _gfx_slider(parent: Control, key: String, text: String, lo: float, hi: float, value: float, fmt: String, display_scale: float, hint: String) -> void:
	var row := _row(parent, text, hint)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1
	s.value = value
	s.custom_minimum_size = Vector2(300, 24)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value_l := UiTheme.label(fmt % roundi(value * display_scale), UiTheme.SIZE_BODY, UiTheme.ACCENT)
	value_l.custom_minimum_size = Vector2(64, 0)
	value_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(v: float) -> void:
		value_l.text = fmt % roundi(v * display_scale)
		if not s.has_focus() or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			UiContext.set_setting("graphics", key, int(v))
			_gfx_sync_preset())
	s.drag_ended.connect(func(_changed: bool) -> void:
		UiContext.set_setting("graphics", key, int(s.value))
		_gfx_sync_preset())
	_hook_hint(s, hint)
	row.add_child(s)
	row.add_child(value_l)


## Brightness calibration: three marks on black at 2 %, 4 % and 8 % grey
## (scaled by the game's brightness). The faintest should be barely visible.
func _gfx_calibrate() -> void:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var marks := Control.new()
	marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marks.draw.connect(func() -> void:
		var b := float(UiContext.setting("graphics", "brightness", 0.85)) / 0.85
		var c := marks.size * Vector2(0.5, 0.42)
		for i in 3:
			var g: float = [0.02, 0.04, 0.08][i] * b
			var col := Color(g, g, g).linear_to_srgb()
			var at := c + Vector2((i - 1) * 220.0, 0.0)
			marks.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -70), at + Vector2(45, 40), at + Vector2(-45, 40)]), col))
	layer.add_child(marks)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	box.offset_top = -230
	box.offset_left = -330
	box.offset_right = 330
	box.add_theme_constant_override("separation", 12)
	var tip := UiTheme.label("Adjust until the left mark is barely visible and the right one is clearly visible.", UiTheme.SIZE_BODY, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(tip)
	var s := HSlider.new()
	s.min_value = 0.5
	s.max_value = 1.5
	s.step = 0.01
	s.value = float(UiContext.setting("graphics", "brightness", 0.85))
	s.custom_minimum_size = Vector2(600, 24)
	s.value_changed.connect(func(v: float) -> void:
		UiContext.set_setting("graphics", "brightness", v)
		marks.queue_redraw())
	box.add_child(s)
	var done := UiTheme.button("Done", func() -> void:
		layer.queue_free()
		_gfx_rebuild.call_deferred())
	box.add_child(done)
	layer.add_child(box)
	add_child(layer)
	s.grab_focus.call_deferred()


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
