class_name SettingsMenu
extends Control
## Options overlay used from the main menu and the pause menu. Every control
## reads and writes `Settings`; changes apply immediately and persist.
## A centred framed panel: a search box, Cinzel tabs, striped option rows,
## and a footer that explains whichever option is hovered or focused.
## Window changes (mode, screen, size, HDR) ask to be kept within 15 s.

signal closed

## Loaded at runtime: the Keybinds class refers to the Settings autoload, and a
## static dependency would stop this screen compiling where autoloads don't exist.
var _keybinds: Script = load("res://core/keybinds.gd")

const FPS_CAPS := [0, 30, 60, 90, 120, 144, 165, 240]
const RENDER_SCALES := [-1.0, 0.5, 0.62, 0.75, 0.85, 1.0]
const SECTIONS := ["graphics", "display", "audio", "controls", "gameplay", "accessibility"]
const AUTOSAVE_MINUTES := [0.0, 2.0, 5.0, 10.0, 15.0, 30.0]
const CONFIRM_SECONDS := 15.0
## What "Reset tab" restores on tabs that mix sections.
const TAB_KEYS := {
	"controls": [["gameplay", "mouse_sensitivity"], ["gameplay", "invert_y"], ["input", "mouse_smoothing"],
		["input", "pad_look_sensitivity"], ["input", "pad_deadzone"], ["input", "pad_vibration"], ["input", "pad_invert_y"]],
	"gameplay": [["gameplay", "camera_shake"], ["gameplay", "head_bob"], ["gameplay", "autosave_minutes"],
		["hud", "minimap"], ["hud", "compass"], ["hud", "quest_tracker"], ["hud", "damage_numbers"],
		["hud", "crosshair"], ["hud", "crosshair_color"]],
}

var _tabs: TabContainer
var _panel: MenuPanel
var _hint: Label
var _search: LineEdit
var _rebinding := ""
var _rebind_slot := 0
var _rebind_pad := false
var _rebind_button: Button
var _rebind_timeout := 0.0
var _binding_buttons := {}      # action -> [primary, secondary, controller] buttons
var _row_index := 0
var _checks := {}               # "section/key" -> [CheckBox]
var _confirm: Control
var _confirm_left := 0.0
var _confirm_label: Label
var _confirm_revert := Callable()


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
	_search = LineEdit.new()
	_search.placeholder_text = "Search settings…"
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(320, 32)
	_search.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_search.text_changed.connect(_filter)
	_hook_hint(_search, "Type to show only the options whose name or description matches, across every tab.")
	outer.add_child(_search)
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
	var settings := UiContext.autoload("Settings")
	if settings != null:
		settings.connect(&"changed", _sync_checks)


## Centred, as large as fits comfortably.
func _layout() -> void:
	if _panel == null:
		return
	var s := size if size.x > 0.0 else Vector2(1600, 900)
	var w := minf(1000.0, s.x - 40.0)
	var h := minf(760.0, s.y - 40.0)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -w * 0.5
	_panel.offset_right = w * 0.5
	_panel.offset_top = -h * 0.5
	_panel.offset_bottom = h * 0.5


func close() -> void:
	if _confirm != null:
		_end_confirm(false)
	UiContext.sound("ui_back")
	closed.emit()
	queue_free()


func _process(delta: float) -> void:
	if _confirm != null:
		_confirm_left -= delta
		_confirm_label.text = "Reverting in %d s" % ceili(maxf(_confirm_left, 0.0))
		if _confirm_left <= 0.0:
			_end_confirm(false)
	if _rebinding != "" and _rebind_pad:
		_rebind_timeout -= delta
		if _rebind_timeout <= 0.0:
			_finish_rebind()


func _input(event: InputEvent) -> void:
	if _rebinding != "":
		_rebind_input(event)
		return
	if _confirm != null:
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			_end_confirm(false)
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _search.has_focus() and _search.text != "":
			_search.text = ""
			_filter("")
		else:
			close()
	elif event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_TAB \
			and (event as InputEventKey).ctrl_pressed:
		var step := -1 if (event as InputEventKey).shift_pressed else 1
		_tabs.current_tab = posmod(_tabs.current_tab + step, _tabs.get_tab_count())
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		var step := -1 if (event as InputEventJoypadButton).button_index == JOY_BUTTON_LEFT_SHOULDER else 1
		_tabs.current_tab = posmod(_tabs.current_tab + step, _tabs.get_tab_count())
		get_viewport().set_input_as_handled()


# --- Rebinding ----------------------------------------------------------------------------

func _start_rebind(action: String, slot: int, pad: bool, b: Button) -> void:
	_finish_rebind()
	_rebinding = action
	_rebind_slot = slot
	_rebind_pad = pad
	_rebind_button = b
	_rebind_timeout = 6.0
	b.text = "press a button…" if pad else "press a key…"
	_set_hint(("Press a controller button, trigger or stick direction. Waits 6 s; Esc cancels." if pad
			else "Press a key or mouse button. Esc cancels; Backspace or Delete clears this binding."))


func _rebind_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_ESCAPE:
			_finish_rebind()
			return
		if not _rebind_pad and k.keycode in [KEY_BACKSPACE, KEY_DELETE]:
			_bind(0)
			return
	var code := 0
	if _rebind_pad:
		if event is InputEventJoypadButton and event.pressed:
			code = int(_keybinds.call("event_code", event))
		elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.6:
			code = int(_keybinds.call("event_code", event))
	else:
		if event is InputEventKey and event.pressed and not event.echo:
			code = int(_keybinds.call("event_code", event))
		elif event is InputEventMouseButton and event.pressed:
			var mb := event as InputEventMouseButton
			if mb.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
				code = int(mb.button_index)
	if code != 0:
		_bind(code)


func _bind(code: int) -> void:
	var action := _rebinding
	var taken := str(_keybinds.call("set_binding", action, _rebind_slot, code, _rebind_pad))
	_finish_rebind()
	var labels: Dictionary = _keybinds.get("LABELS")
	if taken != "":
		_set_hint("%s was also bound to %s; the two swapped." % [_keybinds.call("code_name", code), labels.get(taken, taken)])
	elif code == 0:
		_set_hint("Cleared. %s keeps its other bindings." % labels.get(action, action))
	else:
		_set_hint("%s now uses %s." % [labels.get(action, action), _keybinds.call("code_name", code)])


func _finish_rebind() -> void:
	_rebinding = ""
	_rebind_button = null
	_refresh_bindings()


func _refresh_bindings() -> void:
	for action: String in _binding_buttons:
		var keys: Array = _keybinds.call("key_list", action)
		var pads: Array = _keybinds.call("pad_list", action)
		var bs: Array = _binding_buttons[action]
		for i in 2:
			(bs[i] as Button).text = str(_keybinds.call("code_name", int(keys[i]))) if i < keys.size() else "—"
		(bs[2] as Button).text = str(_keybinds.call("code_name", int(pads[0]))) if not pads.is_empty() else "—"


# --- Reset, search -------------------------------------------------------------------------

func _reset_tab() -> void:
	var section: String = SECTIONS[_tabs.current_tab]
	var settings := UiContext.autoload("Settings")
	if TAB_KEYS.has(section):
		UiContext.call_on(settings, "reset_keys", [TAB_KEYS[section]])
	if section != "gameplay":
		UiContext.call_on(settings, "reset_section", [section])
	var idx := _tabs.current_tab
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	_build_all()
	_tabs.current_tab = idx
	_filter(_search.text)
	_set_hint("Restored the defaults of this tab.")


func _build_all() -> void:
	_checks.clear()
	_build_graphics()
	_build_display()
	_build_audio()
	_build_controls()
	_build_gameplay()
	_build_accessibility()
	_build_chat()


## Hides rows (and empty headings) that do not match `text`, in every tab.
func _filter(text: String) -> void:
	var q := text.strip_edges().to_lower()
	var first_hit := -1
	for t in _tabs.get_tab_count():
		var box := (_tabs.get_tab_control(t) as ScrollContainer).get_child(0) as VBoxContainer
		var heading: Control = null
		var heading_hits := 0
		var hits := 0
		for c: Node in box.get_children():
			var ctl := c as Control
			if ctl.has_meta("heading"):
				if heading != null:
					heading.visible = heading_hits > 0
				heading = ctl
				heading_hits = 0
				continue
			var hay := str(ctl.get_meta("search", ""))
			var show := q == "" or hay.contains(q)
			ctl.visible = show
			if show and hay != "":
				heading_hits += 1
				hits += 1
		if heading != null:
			heading.visible = heading_hits > 0
		_tabs.set_tab_title(t, str(_tabs.get_tab_control(t).name) + ("" if q == "" else " (%d)" % hits))
		if hits > 0 and first_hit < 0:
			first_hit = t
	if q != "" and first_hit >= 0:
		var cur := (_tabs.get_tab_control(_tabs.current_tab) as ScrollContainer).get_child(0) as VBoxContainer
		var any := false
		for c: Node in cur.get_children():
			if (c as Control).visible and (c as Control).has_meta("search"):
				any = true
				break
		if not any:
			_tabs.current_tab = first_hit


func _set_hint(text: String) -> void:
	if _hint == null:
		return
	_hint.text = text if text != "" else "Esc closes  ·  Ctrl+Tab or LB / RB switch tabs  ·  hover or focus an option to read about it"
	_hint.add_theme_color_override("font_color", UiTheme.TEXT if text != "" else UiTheme.TEXT_FAINT)


# --- Display confirmation ------------------------------------------------------------------

## Applies a window option, then asks to keep it; no answer in 15 s reverts.
func _set_display(value: Variant, key: String) -> void:
	var before: Variant = UiContext.setting("display", key)
	if before == value:
		return
	if _confirm != null:
		_end_confirm(true)
	UiContext.set_setting("display", key, value)
	_confirm_revert = func() -> void: UiContext.set_setting("display", key, before)
	_show_confirm()


func _show_confirm() -> void:
	_confirm = Control.new()
	_confirm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm.add_child(UiTheme.scrim(0.6))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm.add_child(center)
	var p := MenuPanel.new("KEEP THESE DISPLAY SETTINGS?")
	p.title_size = 18
	center.add_child(p)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	p.add_child(box)
	var msg := UiTheme.label("If the picture is wrong, wait and the previous settings come back.", UiTheme.SIZE_BODY, UiTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	msg.custom_minimum_size.x = 440
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(msg)
	_confirm_label = UiTheme.label("", UiTheme.SIZE_LARGE, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_confirm_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var keep := MenuOption.new("KEEP", func() -> void: _end_confirm(true), 16)
	keep.custom_minimum_size = Vector2(170, 40)
	var revert := MenuOption.new("REVERT", func() -> void: _end_confirm(false), 16)
	revert.custom_minimum_size = Vector2(170, 40)
	row.add_child(keep)
	row.add_child(revert)
	box.add_child(row)
	_confirm_left = CONFIRM_SECONDS
	_confirm_label.text = "Reverting in %d s" % int(CONFIRM_SECONDS)
	add_child(_confirm)
	keep.grab_focus.call_deferred()


func _end_confirm(keep: bool) -> void:
	if _confirm == null:
		return
	var c := _confirm
	_confirm = null
	c.queue_free()
	if not keep and _confirm_revert.is_valid():
		_confirm_revert.call()
		_rebuild_keep_tab()
		_set_hint("Display settings reverted.")
	elif keep:
		_set_hint("Display settings kept.")
	_confirm_revert = Callable()


func _rebuild_keep_tab() -> void:
	var idx := _tabs.current_tab
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	_build_all()
	_tabs.current_tab = idx
	_filter(_search.text)


# --- Tab builders --------------------------------------------------------------------

func _page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
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
			"How the 3D image is scaled up to the window when 3D resolution is below 100%. Automatic: AMD FSR 1 with sharpening (well under 1 ms). MetalFX spatial has no sharpening and looks softer. Temporal upscalers (FSR 2, MetalFX temporal) also anti-alias but cost 2-15 ms more per frame on this class of GPU.")
	var scale_names: Array = ["Follow preset", "50%", "62%", "75%", "85%", "100%"]
	_option_values(p, "graphics", "render_scale", "3D resolution", scale_names, RENDER_SCALES,
			"Resolution the 3D scene renders at, as a share of your screen's native pixels (100% = native, also on Retina / HiDPI screens). Follow preset: High aims at about 2.2 million pixels (native on 1080p, ~64% on a MacBook), Ultra at about 4 million. GPU cost grows with the pixel count: 100% costs about twice 70%. The UI is always native.")
	_check(p, "graphics", "adaptive_resolution", "Adaptive resolution", "With 3D resolution on Follow preset, lowers the 3D resolution when the GPU cannot hold 60 FPS, never below 75% of the preset's on High (60% on Low). No cost; does not help when the CPU is the limit.")
	_slider(p, "graphics", "sharpness", "Sharpness", 0.0, 1.0, 0.05, "%d%%", 100.0, "Sharpening (AMD RCAS) after upscaling, and after TAA at native resolution with the Automatic upscaler. Free. MetalFX has no sharpening.")
	_gfx_option(p, "antialiasing", "Anti-aliasing", ["Off", "FXAA", "TAA", "MSAA 2x", "MSAA 4x", "SMAA"],
			"Smooths jagged edges. FXAA: almost free, soft. SMAA: about 0.5 ms, sharper than FXAA (Medium). TAA: about 1 ms, the steadiest grass and foliage, slightly soft (sharpened back), can ghost behind fast particles (High, Ultra). MSAA: geometry edges only, 2-6 ms. Ignored when a temporal upscaler is on.")

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
	_check(p, "graphics", "altitude_blur", "Mountain distance blur", "Softens distant scenery as altitude increases (a gentle depth-of-field look). Off by default for a clear view. About 1 ms when it applies.")

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
	var modes: Array = UiContext.settings_const("WINDOW_MODE_NAMES")
	_choice(p, "display", "window_mode", "Window mode", modes, range(modes.size()),
			"Fill screen: a borderless window over the whole display, quick to switch away from. Windowed: a normal window. Fullscreen: the display's own fullscreen space. Exclusive: fullscreen that takes over the display (lowest latency on Windows).",
			_set_display.bind("window_mode"))
	var screens: Array = ["The screen the game is on"]
	var screen_values: Array = [-1]
	if DisplayServer.get_name() != "headless":
		for i in DisplayServer.get_screen_count():
			var sz := DisplayServer.screen_get_size(i)
			screens.append("Screen %d  (%d × %d)" % [i + 1, sz.x, sz.y])
			screen_values.append(i)
	_choice(p, "display", "monitor", "Monitor", screens, screen_values,
			"Which display the game opens on. The window moves there at once.", _set_display.bind("monitor"))
	var res_names: Array = ["Automatic (80% of the screen)"]
	var res_values: Array = [""]
	var scr := int(UiContext.setting("display", "monitor", -1))
	var settings := UiContext.autoload("Settings")
	var sizes: Variant = settings.call("resolutions_for", scr if scr >= 0 else DisplayServer.window_get_current_screen()) if settings != null else PackedStringArray()
	for r: String in sizes:
		res_names.append(r.replace("x", " × "))
		res_values.append(r)
	var cur_res := str(UiContext.setting("display", "resolution", ""))
	if cur_res != "" and not cur_res in res_values:
		res_names.append(cur_res.replace("x", " × "))
		res_values.append(cur_res)
	_choice(p, "display", "resolution", "Window size", res_names, res_values,
			"Size of the window in Windowed mode, in pixels. The other modes always use the whole screen; lower the 3D resolution under Graphics instead.",
			_set_display.bind("resolution"))
	if settings != null and bool(settings.call("hdr_supported")):
		_check(p, "display", "hdr", "HDR output", "Sends a high-dynamic-range picture to an HDR display. Only offered where the display and system support it.",
				_set_display.bind("hdr"))
	_heading(p, "Frame pacing")
	_option(p, "display", "vsync", "Vertical sync", UiContext.settings_const("VSYNC_NAMES"),
			"On prevents tearing. Adaptive tears only when the frame rate drops below the refresh rate. Mailbox shows the newest frame without tearing at some extra power use. Off gives the lowest input latency.")
	_fps_cap(p)
	_heading(p, "Interface")
	_slider(p, "display", "ui_scale", "UI scale", 0.75, 1.5, 0.05, "%d%%", 100.0,
			"Size of menus, HUD and text, on top of the automatic adjustment for your screen's size and pixel density.")


func _fps_cap(p: Control) -> void:
	var hint := "Limits the frame rate to save power and heat. Custom lets you pick any limit from 20 to 500."
	var row := _row(p, "Frame cap", hint)
	var opt := _option_button(hint)
	var cur := int(UiContext.setting("display", "fps_cap", 0))
	for c: int in FPS_CAPS:
		opt.add_item("Unlimited" if c == 0 else "%d fps" % c)
	opt.add_item("Custom")
	var spin := SpinBox.new()
	spin.min_value = 20
	spin.max_value = 500
	spin.step = 1
	spin.suffix = "fps"
	spin.custom_minimum_size = Vector2(120, 0)
	spin.value = cur if cur > 0 else 75
	var preset := FPS_CAPS.find(cur)
	opt.select(preset if preset >= 0 else FPS_CAPS.size())
	spin.visible = preset < 0
	opt.custom_minimum_size.x = 300 - (130 if spin.visible else 0)
	opt.item_selected.connect(func(i: int) -> void:
		spin.visible = i >= FPS_CAPS.size()
		opt.custom_minimum_size.x = 300 - (130 if spin.visible else 0)
		UiContext.set_setting("display", "fps_cap", int(spin.value) if spin.visible else int(FPS_CAPS[i])))
	spin.value_changed.connect(func(v: float) -> void: UiContext.set_setting("display", "fps_cap", int(v)))
	_hook_hint(spin, hint)
	row.add_child(opt)
	row.add_child(spin)


func _build_audio() -> void:
	var p := _page("Audio")
	_heading(p, "Volume")
	_slider(p, "audio", "master", "Master", 0.0, 1.0, 0.01, "%d%%", 100.0, "Everything you hear.")
	_slider(p, "audio", "music", "Music", 0.0, 1.0, 0.01, "%d%%", 100.0, "The score.")
	_slider(p, "audio", "sfx", "Effects", 0.0, 1.0, 0.01, "%d%%", 100.0, "Combat, footsteps, spells, creatures and the world.")
	_slider(p, "audio", "ambient", "Ambience", 0.0, 1.0, 0.01, "%d%%", 100.0, "Wind, rain, fire and the sounds of places.")
	_slider(p, "audio", "ui", "Interface", 0.0, 1.0, 0.01, "%d%%", 100.0, "Menu clicks, page turns and other interface sounds.")
	_heading(p, "Output")
	var devices: Array = Array(AudioServer.get_output_device_list())
	if not "Default" in devices:
		devices.push_front("Default")
	var cur := str(UiContext.setting("audio", "output_device", "Default"))
	if not cur in devices:
		devices.append(cur)
	var names: Array = []
	for d: String in devices:
		names.append("System default" if d == "Default" else d)
	_choice(p, "audio", "output_device", "Output device", names, devices,
			"Where the sound plays. System default follows the device chosen in your operating system. A missing device falls back to the default.")
	_check(p, "audio", "mute_unfocused", "Mute when in background", "Silences the game while another window has focus.")
	var note := UiTheme.label("BURN has no spoken dialogue, so there are no voice or subtitle options.", UiTheme.SIZE_SMALL, UiTheme.TEXT_FAINT)
	note.set_meta("search", "voice dialogue subtitles")
	p.add_child(UiTheme.spacer(8))
	p.add_child(note)


func _build_controls() -> void:
	var p := _page("Controls")
	_heading(p, "Mouse")
	_slider(p, "gameplay", "mouse_sensitivity", "Sensitivity", 0.2, 3.0, 0.05, "%d%%", 100.0, "How far the camera turns per mouse movement.")
	_check(p, "gameplay", "invert_y", "Invert vertical look", "Moving the mouse up looks down.")
	_check(p, "input", "mouse_smoothing", "Mouse smoothing", "Eases camera turns over a few frames. Off gives the most direct, raw-feeling aim.")
	_heading(p, "Controller")
	_slider(p, "input", "pad_look_sensitivity", "Look sensitivity", 0.2, 3.0, 0.05, "%d%%", 100.0, "How fast the right stick turns the camera.")
	_slider(p, "input", "pad_deadzone", "Stick dead zone", 0.05, 0.5, 0.01, "%d%%", 100.0, "How far a stick must move before it counts. Raise it if the view or your character drifts.")
	_slider(p, "input", "pad_vibration", "Vibration", 0.0, 1.0, 0.05, "%d%%", 100.0, "Rumble when you are hit and when the ground shakes. 0% turns it off.")
	_check(p, "input", "pad_invert_y", "Invert stick look", "Pushing the right stick up looks down.")
	_heading(p, "Hold or toggle")
	_check(p, "accessibility", "toggle_sprint", "Sprint: press to toggle", "Press sprint once to keep running, again to stop, instead of holding it. Opening a menu stops it.")
	_check(p, "accessibility", "toggle_attack", "Attack / mine: press to toggle", "Press attack once to keep swinging or mining, again to stop, instead of holding it. Opening a menu stops it.")
	_heading(p, "Bindings")
	var head := _row(p, "Action")
	for t: String in ["Primary", "Secondary", "Controller"]:
		var l := UiTheme.label(t, UiTheme.SIZE_SMALL, UiTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		l.custom_minimum_size = Vector2(170, 0)
		head.add_child(l)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(34, 0)
	head.add_child(spacer)
	_binding_buttons.clear()
	var actions: Dictionary = _keybinds.get("ACTIONS")
	var labels: Dictionary = _keybinds.get("LABELS")
	var hint := "Click a binding, then press the new key, mouse button or controller input. A key already in use swaps with the other action. ↺ restores the defaults."
	for action: String in actions:
		var row := _row(p, str(labels.get(action, action)), hint)
		var bs: Array = []
		for i in 3:
			var b := UiTheme.button("")
			b.custom_minimum_size = Vector2(170, 0)
			b.alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.clip_text = true
			b.add_theme_color_override("font_color", UiTheme.ACCENT)
			b.add_theme_stylebox_override("normal", _key_box(false))
			b.add_theme_stylebox_override("hover", _key_box(true))
			b.add_theme_stylebox_override("focus", _key_box(true))
			var slot := i
			b.pressed.connect(func() -> void: _start_rebind(action, mini(slot, 1), slot == 2, b))
			_hook_hint(b, hint)
			row.add_child(b)
			bs.append(b)
		var r := UiTheme.button("↺")
		r.custom_minimum_size = Vector2(34, 0)
		r.tooltip_text = "Restore the default bindings of %s" % str(labels.get(action, action))
		r.pressed.connect(func() -> void:
			_keybinds.call("reset_action", action)
			_refresh_bindings()
			_set_hint("%s: defaults restored." % str(labels.get(action, action))))
		_hook_hint(r, "Restores this action's default keyboard, mouse and controller bindings.")
		row.add_child(r)
		_binding_buttons[action] = bs
	_refresh_bindings()


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
	var name_hint := "The name others see in a warband, and on your runs."
	var row := _row(p, "Name", name_hint)
	var edit := LineEdit.new()
	edit.text = str(UiContext.setting("gameplay", "player_name"))
	edit.max_length = 20
	edit.custom_minimum_size = Vector2(300, 0)
	edit.text_changed.connect(func(t: String) -> void:
		if t.strip_edges() != "":
			UiContext.set_setting("gameplay", "player_name", t.strip_edges()))
	_hook_hint(edit, name_hint)
	row.add_child(edit)
	_heading(p, "Camera")
	_slider(p, "gameplay", "camera_shake", "Camera shake", 0.0, 1.5, 0.05, "%d%%", 100.0, "How hard big hits and explosions shake the view.")
	_slider(p, "gameplay", "head_bob", "Head bob", 0.0, 1.0, 0.05, "%d%%", 100.0, "How much the first-person view sways while you walk and run.")
	_heading(p, "HUD")
	_check(p, "hud", "minimap", "Minimap", "The round map in the top-left corner. The world map (M) is always available.")
	_check(p, "hud", "compass", "Compass", "The heading strip with objective markers at the top of the screen.")
	_check(p, "hud", "quest_tracker", "Quest tracker", "Your active quests in the top-right corner. The quest log (J) is always available.")
	_check(p, "hud", "damage_numbers", "Damage numbers", "Numbers that float up when you hit, are hit or heal.")
	_option(p, "hud", "crosshair", "Crosshair", UiContext.settings_const("CROSSHAIR_NAMES"), "Shape of the reticle in the centre of the screen. The mining ring and prompts still show when hidden.")
	_option(p, "hud", "crosshair_color", "Crosshair colour", UiContext.settings_const("CROSSHAIR_COLOR_NAMES"), "Colour of the reticle.")
	_heading(p, "Saving")
	var names: Array = []
	for m: float in AUTOSAVE_MINUTES:
		names.append("Off (save on quit)" if m <= 0.0 else "Every %d minutes" % int(m))
	_choice(p, "gameplay", "autosave_minutes", "Autosave", names, AUTOSAVE_MINUTES,
			"How often your run is saved while you play (hosts save for the whole warband). The game always saves when you quit to the title.")


func _build_accessibility() -> void:
	var p := _page("Accessibility")
	_heading(p, "Colour")
	_option(p, "accessibility", "colorblind", "Colour-blind filter", UiContext.settings_const("COLORBLIND_NAMES"),
			"Shifts colours you may confuse into ones you can tell apart, over the whole screen (world, HUD and menus). Pick the type that matches your vision.")
	_slider(p, "accessibility", "colorblind_strength", "Filter strength", 0.0, 1.0, 0.05, "%d%%", 100.0, "How strongly the colour-blind filter corrects.")
	_check(p, "accessibility", "high_contrast", "High-contrast HUD", "Heavy dark outlines behind HUD text and a bolder crosshair, for reading over bright scenes.")
	_heading(p, "Motion and light")
	_check(p, "accessibility", "reduce_motion", "Reduce motion", "Removes head bob and cuts camera shake and landing dips to a fraction.")
	_check(p, "accessibility", "reduce_flashing", "Reduce flashing", "Dims lightning, white flashes from big hits and the red damage pulse to a quarter.")
	_heading(p, "Hold-to-press alternatives")
	_check(p, "accessibility", "toggle_sprint", "Sprint: press to toggle", "Press sprint once to keep running, again to stop, instead of holding it. Opening a menu stops it.")
	_check(p, "accessibility", "toggle_attack", "Attack / mine: press to toggle", "Press attack once to keep swinging or mining, again to stop, instead of holding it. Opening a menu stops it.")
	var note := UiTheme.label("Text and interface size: Display > UI scale.", UiTheme.SIZE_SMALL, UiTheme.TEXT_FAINT)
	note.set_meta("search", "text size font interface scale")
	p.add_child(UiTheme.spacer(8))
	p.add_child(note)


# --- Row helpers --------------------------------------------------------------------

func _heading(parent: Control, text: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.set_meta("heading", true)
	box.add_child(UiTheme.spacer(10))
	var l := UiTheme.title(text.to_upper(), 13, UiTheme.ACCENT_DIM, 700)
	l.add_theme_font_override("font", UiTheme.title_font_spaced(700, 3))
	box.add_child(l)
	box.add_child(UiTheme.spacer(4))
	parent.add_child(box)
	_row_index = 0


## One option row: a label on the left, its control added on the right by the
## caller. Rows alternate a faint stripe; the row lights while its control has focus.
func _row(parent: Control, text: String, hint := "") -> HBoxContainer:
	var panel := PanelContainer.new()
	panel.set_meta("search", (text + " " + hint).to_lower())
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
	l.custom_minimum_size = Vector2(220, 32)
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
	_choice(parent, section, key, text, names, values, hint)


func _option_button(hint: String) -> OptionButton:
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(300, 0)
	opt.clip_text = true
	opt.add_theme_color_override("font_color", UiTheme.ACCENT)
	opt.add_theme_stylebox_override("normal", _key_box(false))
	opt.add_theme_stylebox_override("hover", _key_box(true))
	opt.add_theme_stylebox_override("focus", _key_box(true))
	opt.tooltip_text = hint
	_hook_hint(opt, hint)
	return opt


## A drop-down of `names` storing `values`. `apply` (optional) is called with
## the new value instead of writing the setting directly (display confirmation).
func _choice(parent: Control, section: String, key: String, text: String, names: Array, values: Array, hint := "",
		apply := Callable()) -> void:
	var row := _row(parent, text, hint)
	var opt := _option_button(hint)
	var current: Variant = UiContext.setting(section, key)
	for i in names.size():
		opt.add_item(str(names[i]), i)
		var v: Variant = values[i]
		if (v is String and str(current) == v) or (not v is String and not current is String and is_equal_approx(float(v), float(current))):
			opt.select(i)
	opt.item_selected.connect(func(i: int) -> void:
		var v: Variant = values[i]
		if current is int:
			v = int(v)
		elif current is float:
			v = float(v)
		if apply.is_valid():
			apply.call(v)
		else:
			UiContext.set_setting(section, key, v))
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


func _check(parent: Control, section: String, key: String, text: String, hint := "", apply := Callable()) -> void:
	var row := _row(parent, text, hint)
	var c := CheckBox.new()
	c.button_pressed = bool(UiContext.setting(section, key))
	c.text = "on" if c.button_pressed else "off"
	c.custom_minimum_size = Vector2(90, 0)
	c.toggled.connect(func(on: bool) -> void:
		c.text = "on" if on else "off"
		UiContext.sound("ui_click")
		if apply.is_valid():
			apply.call(on)
		else:
			UiContext.set_setting(section, key, on))
	_hook_hint(c, hint)
	row.add_child(c)
	var id := section + "/" + key
	if not _checks.has(id):
		_checks[id] = []
	(_checks[id] as Array).append(c)


## The same option can appear on two tabs: keep every copy in step.
func _sync_checks(section: String, key: String) -> void:
	for c: CheckBox in _checks.get(section + "/" + key, []):
		if is_instance_valid(c):
			var on := bool(UiContext.setting(section, key))
			c.set_pressed_no_signal(on)
			c.text = "on" if on else "off"


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
