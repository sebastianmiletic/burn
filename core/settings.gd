extends Node
## Autoload "Settings": every player-facing option, persisted to
## user://settings.cfg. Systems read values from here and listen to `changed`.

signal changed(section: String, key: String)

var PATH := RuntimePaths.file("settings.cfg")

enum Quality { LOW, MEDIUM, HIGH, ULTRA }
enum WindowMode { FILL_SCREEN, WINDOWED, FULLSCREEN, EXCLUSIVE }
enum Vsync { OFF, ON, ADAPTIVE, MAILBOX }

const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra"]
const WINDOW_MODE_NAMES := ["Fill screen", "Windowed", "Fullscreen", "Exclusive fullscreen"]
const VSYNC_NAMES := ["Off", "On", "Adaptive", "Mailbox (triple buffered)"]
const COLORBLIND_NAMES := ["Off", "Protanopia (red-weak)", "Deuteranopia (green-weak)", "Tritanopia (blue-weak)"]
const CROSSHAIR_NAMES := ["Cross", "Dot", "Circle", "Cross and dot", "Hidden"]
const CROSSHAIR_COLOR_NAMES := ["Ember", "White", "Green", "Cyan", "Magenta", "Yellow"]
const CROSSHAIR_COLORS := [Color(1, 0.9, 0.75), Color(1, 1, 1), Color(0.45, 1.0, 0.45), Color(0.4, 0.95, 1.0),
	Color(1.0, 0.45, 0.95), Color(1.0, 0.95, 0.3)]
## Actions that can be latched with one press instead of held (Accessibility).
const TOGGLE_ACTIONS := {"sprint": "toggle_sprint", "attack": "toggle_attack"}
## Changing these resizes or moves the window (the settings screen asks to keep them).
const WINDOW_KEYS := ["window_mode", "monitor", "resolution", "hdr"]

## Graphics options a quality preset decides. Stored as -1 ("follow the
## preset") unless the player overrides them; gfx() resolves either way. Values
## per preset, Low .. Ultra (see GraphicsQuality for what each level means).
const GFX_PRESETS := {
	"shadows": [1, 2, 3, 4],          # 0 off, 1 low .. 4 ultra
	"antialiasing": [1, 5, 2, 2],     # 0 off, 1 FXAA, 2 TAA, 3 MSAA 2x, 4 MSAA 4x, 5 SMAA (docs/ANTI_ALIASING.md)
	"ssao": [0, 1, 2, 3],             # 0 off, 1 low, 2 medium, 3 high
	"ssil": [0, 0, 0, 1],             # 0 off, 1 on
	"ssr": [0, 0, 1, 2],              # 0 off, 1 low, 2 high
	"gi": [0, 0, 1, 2],               # 0 off, 1 SDFGI, 2 SDFGI high
	"volumetric_fog": [0, 0, 1, 2],   # 0 off, 1 low, 2 high
	"view_distance": [6, 8, 10, 12],  # streamed terrain radius, chunks of 16 m
	"foliage": [0, 1, 2, 3],          # density and draw distance of grass, plants, trees
	"texture_quality": [0, 1, 2, 3],  # mip bias and anisotropic filtering
	"mesh_detail": [0, 1, 2, 3],      # level-of-detail distances
	"effects": [0, 1, 2, 3],          # particle counts (weather, ambient)
}
## Graphics-settings revision: 1 = the sharpness pass (render scale in native
## pixels, mountain blur off, stronger sharpening; docs/ANTI_ALIASING.md).
const AA_REV := 1
const UPSCALER_NAMES := ["Automatic", "Bilinear", "AMD FSR 1", "AMD FSR 2 (temporal)", "MetalFX spatial", "MetalFX temporal"]

const DEFAULTS := {
	"display": {
		"window_mode": WindowMode.FILL_SCREEN,
		"monitor": -1,         # -1: the screen the window is on
		"resolution": "",      # windowed size "WxH"; "": 80% of the screen
		"vsync": Vsync.ON,
		"fps_cap": 0,
		"ui_scale": 1.0,       # on top of the automatic HiDPI / screen-size scale
		"hdr": false,
	},
	"graphics": {
		"quality": Quality.HIGH,
		"adaptive_resolution": true,
		"altitude_blur": false,
		"render_scale": -1.0,  # -1: follow the quality preset; else a fraction of native (physical) pixels
		"brightness": 0.85,
		"fov": 80.0,
		"fog": 1.0,
		"bloom": 1.0,
		"vignette": 0.3,
		"grain": 0.0,
		"shadows": -1,
		"antialiasing": -1,
		"ssao": -1,
		"ssil": -1,
		"ssr": -1,
		"gi": -1,
		"volumetric_fog": -1,
		"view_distance": -1,
		"foliage": -1,
		"texture_quality": -1,
		"mesh_detail": -1,
		"effects": -1,
		"upscaler": 0,
		"sharpness": 0.8,
		"aa_rev": AA_REV,      # settings older than this get the sharper defaults once
		"motion_blur": 0.0,
		"depth_of_field": false,
		"chromatic_aberration": 0.0,
		"sun_shafts": true,
	},
	"audio": {
		"master": 0.8,
		"music": 0.6,
		"sfx": 0.9,
		"ambient": 0.8,
		"ui": 0.9,
		"mute_unfocused": false,
		"output_device": "Default",
	},
	"gameplay": {
		"mouse_sensitivity": 1.0,
		"invert_y": false,
		"camera_shake": 1.0,
		"player_name": "",
		"first_person": true,
		"auto_update": true,
		"head_bob": 1.0,
		"autosave_minutes": 5.0,   # 0: only when quitting
	},
	"input": {
		"mouse_smoothing": false,
		"pad_look_sensitivity": 1.0,
		"pad_deadzone": 0.2,
		"pad_vibration": 1.0,
		"pad_invert_y": false,
	},
	"hud": {
		"minimap": true,
		"compass": true,
		"quest_tracker": true,
		"damage_numbers": true,
		"crosshair": 0,
		"crosshair_color": 0,
	},
	"accessibility": {
		"colorblind": 0,
		"colorblind_strength": 1.0,
		"reduce_motion": false,
		"reduce_flashing": false,
		"high_contrast": false,
		"toggle_sprint": false,
		"toggle_attack": false,
	},
	"online": {
		"master_server_url": "",  # "" = ServerList.DEFAULT_MASTER_URL
		"server_name": "",
		"server_description": "",
		"max_players": 8,
	},
	"chat": {
		"enabled": true,
		"text_size": 15,
		"opacity": 1.0,
		"fade_time": 10.0,
		"show_system": true,
		"profanity_filter": true,
	},
	"controls": {},
}

var _data := {}
var _latched := {}
var _filter_layer: CanvasLayer
var _filter_mat: ShaderMaterial
var _unfocused := false


func _ready() -> void:
	_data = DEFAULTS.duplicate(true)
	var cfg := ConfigFile.new()
	var first_run := not FileAccess.file_exists(PATH)
	if first_run:
		_data["graphics"]["quality"] = _suggested_quality()
	if cfg.load(PATH) == OK:
		for section: String in cfg.get_sections():
			if not _data.has(section):
				continue
			for key: String in cfg.get_section_keys(section):
				# Options that no longer exist (the retired ASCII renderer's) are dropped.
				if section != "controls" and not (DEFAULTS[section] as Dictionary).has(key):
					continue
				_data[section][key] = cfg.get_value(section, key)
		# Older settings files: vsync was on/off; the UI volume followed effects.
		if _data["display"]["vsync"] is bool:
			_data["display"]["vsync"] = Vsync.ON if _data["display"]["vsync"] else Vsync.OFF
		if not cfg.has_section_key("audio", "ui"):
			_data["audio"]["ui"] = _data["audio"]["sfx"]
		# Before the sharpness pass every file stored the old blurry defaults
		# (mountain blur on, light sharpening): move those to the new ones once.
		if int(cfg.get_value("graphics", "aa_rev", 0)) < 1:
			_data["graphics"]["altitude_blur"] = false
			_data["graphics"]["sharpness"] = maxf(float(_data["graphics"]["sharpness"]), DEFAULTS["graphics"]["sharpness"])
		_data["graphics"]["aa_rev"] = AA_REV
	if String(_data["gameplay"]["player_name"]) == "":
		_data["gameplay"]["player_name"] = _default_name()
	Keybinds.apply(_data["controls"])
	_apply_deadzone()
	apply_display()
	_build_filter()


## First launch on a laptop's integrated graphics starts at Medium so the game
## runs smoothly; dedicated GPUs and Apple Silicon start at High.
func _suggested_quality() -> int:
	if DisplayServer.get_name() == "headless":
		return Quality.HIGH
	var vendor := RenderingServer.get_video_adapter_vendor().to_lower()
	var name := RenderingServer.get_video_adapter_name().to_lower()
	if vendor.contains("apple") or name.contains("apple"):
		return Quality.HIGH
	if RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
		return Quality.MEDIUM
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		return Quality.LOW  # compatibility fallback: keep it light
	return Quality.HIGH


func get_value(section: String, key: String) -> Variant:
	return _data.get(section, {}).get(key, DEFAULTS.get(section, {}).get(key))


func set_value(section: String, key: String, value: Variant) -> void:
	if get_value(section, key) == value:
		return
	_data[section][key] = value
	if section == "display":
		apply_display(key)
	_on_changed(section, key)
	changed.emit(section, key)
	save()


func save() -> void:
	DirAccess.make_dir_recursive_absolute(PATH.get_base_dir())
	var cfg := ConfigFile.new()
	for section: String in _data:
		for key: String in _data[section]:
			cfg.set_value(section, key, _data[section][key])
	cfg.save(PATH)


func store_controls(controls: Dictionary) -> void:
	_data["controls"] = controls.duplicate(true)
	changed.emit("controls", "")
	save()


func reset_section(section: String) -> void:
	_data[section] = DEFAULTS[section].duplicate(true)
	if section == "controls":
		Keybinds.reset()
	if section == "display":
		apply_display()
	for key: String in _data[section]:
		_on_changed(section, key)
		changed.emit(section, key)
	save()


## Restores single options (a settings tab mixes keys from several sections).
func reset_keys(pairs: Array) -> void:
	var display := false
	for pair: Array in pairs:
		var section: String = pair[0]
		var key: String = pair[1]
		if not (DEFAULTS.get(section, {}) as Dictionary).has(key):
			continue
		_data[section][key] = DEFAULTS[section][key]
		display = display or section == "display"
	if display:
		apply_display()
	for pair: Array in pairs:
		_on_changed(pair[0], pair[1])
		changed.emit(pair[0], pair[1])
	save()


func _on_changed(section: String, key: String) -> void:
	if section == "accessibility" and key.begins_with("colorblind"):
		_update_filter()
	elif section == "input" and key == "pad_deadzone":
		_apply_deadzone()
	elif section == "accessibility" and key.begins_with("toggle_"):
		_latched.clear()


# --- Hold or toggle -------------------------------------------------------------------

## Whether a held action is active: the key itself, or its latch when the
## player chose "toggle" for it (Accessibility). Latches drop whenever the
## mouse is freed (menus, death), so nothing keeps running behind a screen.
func action_held(action: String) -> bool:
	var key: String = TOGGLE_ACTIONS.get(action, "")
	if key == "" or not bool(get_value("accessibility", key)):
		return Input.is_action_pressed(action)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_latched.erase(action)
	return bool(_latched.get(action, false))


func _input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	for action: String in TOGGLE_ACTIONS:
		if bool(get_value("accessibility", TOGGLE_ACTIONS[action])) and InputMap.has_action(action) \
				and event.is_action_pressed(action):
			_latched[action] = not bool(_latched.get(action, false))


func _apply_deadzone() -> void:
	var dz := clampf(float(get_value("input", "pad_deadzone")), 0.05, 0.6)
	for action: String in Keybinds.ACTIONS:
		if InputMap.has_action(action):
			InputMap.action_set_deadzone(action, dz)


# --- Comfort scales read by gameplay ------------------------------------------------------

## Multiplier for screen flashes (lightning, big hits, damage pulses).
func flash_scale() -> float:
	return 0.25 if bool(get_value("accessibility", "reduce_flashing")) else 1.0


## Multiplier for camera motion that is not the player's own (bob, shake, dips).
func motion_scale() -> float:
	return 0.3 if bool(get_value("accessibility", "reduce_motion")) else 1.0


# --- Colour-vision filter ---------------------------------------------------------------

func _build_filter() -> void:
	_filter_layer = CanvasLayer.new()
	_filter_layer.layer = 128   # above the HUD and every menu
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_filter_mat = ShaderMaterial.new()
	_filter_mat.shader = load("res://ui/shaders/color_filter.gdshader")
	rect.material = _filter_mat
	_filter_layer.add_child(rect)
	add_child(_filter_layer)
	_update_filter()


func _update_filter() -> void:
	if _filter_layer == null:
		return
	var mode := clampi(int(get_value("accessibility", "colorblind")), 0, 3)
	_filter_layer.visible = mode > 0
	_filter_mat.set_shader_parameter(&"mode", mode)
	_filter_mat.set_shader_parameter(&"strength", clampf(float(get_value("accessibility", "colorblind_strength")), 0.0, 1.0))

## A preset-driven graphics option: the player's override, or the preset's value.
func gfx(key: String) -> int:
	var v := int(get_value("graphics", key))
	if v >= 0 or not GFX_PRESETS.has(key):
		return v
	return int(GFX_PRESETS[key][clampi(int(get_value("graphics", "quality")), 0, 3)])


## True when an individual option differs from what the current preset sets.
func graphics_is_custom() -> bool:
	var q := clampi(int(get_value("graphics", "quality")), 0, 3)
	for key: String in GFX_PRESETS:
		var v := int(get_value("graphics", key))
		if v >= 0 and v != int(GFX_PRESETS[key][q]):
			return true
	return float(get_value("graphics", "render_scale")) > 0.0


## Choosing a preset sets every preset-driven option back to that preset.
func apply_quality_preset(q: int) -> void:
	_data["graphics"]["quality"] = clampi(q, 0, 3)
	_data["graphics"]["render_scale"] = -1.0
	for key: String in GFX_PRESETS:
		_data["graphics"][key] = -1
	save()
	changed.emit("graphics", "quality")


## Fraction of the window's native (physical) resolution the 3D view renders
## at before adaptive resolution (1.0 = native, also on a HiDPI screen).
func render_scale(physical := Vector2i.ZERO) -> float:
	var forced: float = get_value("graphics", "render_scale")
	if forced > 0.0:
		return minf(forced, 1.0)
	if physical == Vector2i.ZERO:
		physical = DisplayServer.window_get_size() if DisplayServer.get_name() != "headless" else Vector2i(1920, 1080)
	return GraphicsQuality.preset_scale(int(get_value("graphics", "quality")), physical)


## Applies the display options. `key` limits the work to what changed (the
## window is only moved / resized when a window option changed, or at start).
func apply_display(key := "") -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window := get_tree().root
	var vsync := int(get_value("display", "vsync"))
	if "--no-vsync" in OS.get_cmdline_user_args():
		vsync = Vsync.OFF
	DisplayServer.window_set_vsync_mode([DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_ENABLED,
		DisplayServer.VSYNC_ADAPTIVE, DisplayServer.VSYNC_MAILBOX][clampi(vsync, 0, 3)])
	Engine.max_fps = int(get_value("display", "fps_cap"))
	window.content_scale_factor = ui_scale()
	if hdr_supported():
		window.hdr_output_requested = bool(get_value("display", "hdr"))
	if key != "" and not key in WINDOW_KEYS:
		return
	if "--resolution" in OS.get_cmdline_args() or "--fullscreen" in OS.get_cmdline_args():
		return  # explicit size from the command line (benchmarks, captures)
	var screen := window.current_screen
	var monitor := int(get_value("display", "monitor"))
	if monitor >= 0 and monitor < DisplayServer.get_screen_count() and monitor != screen:
		if window.mode != Window.MODE_WINDOWED:
			window.mode = Window.MODE_WINDOWED
		screen = monitor
		window.current_screen = monitor
	match int(get_value("display", "window_mode")):
		WindowMode.FILL_SCREEN:
			# A borderless window covering the screen (all of it but the OS menu
			# bar / taskbar), without switching to a separate fullscreen space.
			window.mode = Window.MODE_WINDOWED
			window.borderless = true
			var usable := DisplayServer.screen_get_usable_rect(screen)
			window.position = usable.position
			window.size = usable.size
		WindowMode.WINDOWED:
			window.mode = Window.MODE_WINDOWED
			window.borderless = false
			var usable := DisplayServer.screen_get_usable_rect(screen)
			var want := parse_resolution(String(get_value("display", "resolution")))
			if want.x <= 0 or want.x > usable.size.x or want.y > usable.size.y:
				want = Vector2i(Vector2(usable.size) * 0.8)
			window.size = want
			window.position = usable.position + (usable.size - window.size) / 2
		WindowMode.FULLSCREEN:
			window.borderless = false
			window.mode = Window.MODE_FULLSCREEN
		WindowMode.EXCLUSIVE:
			window.borderless = false
			window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN


## "1600x900" -> Vector2i(1600, 900); anything else -> (0, 0).
static func parse_resolution(text: String) -> Vector2i:
	var parts := text.to_lower().split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


## Window sizes offered for a screen: common sizes that fit inside it.
static func resolutions_for(screen: int) -> PackedStringArray:
	var out := PackedStringArray()
	if DisplayServer.get_name() == "headless":
		return out
	var usable := DisplayServer.screen_get_usable_rect(clampi(screen, 0, maxi(0, DisplayServer.get_screen_count() - 1))).size
	for r: Vector2i in [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1440, 900), Vector2i(1600, 900),
			Vector2i(1680, 1050), Vector2i(1920, 1080), Vector2i(1920, 1200), Vector2i(2560, 1440),
			Vector2i(2560, 1600), Vector2i(3200, 1800), Vector2i(3840, 2160)]:
		if r.x <= usable.x and r.y <= usable.y:
			out.append("%dx%d" % [r.x, r.y])
	return out


static func hdr_supported() -> bool:
	return DisplayServer.get_name() != "headless" and DisplayServer.has_feature(DisplayServer.FEATURE_HDR_OUTPUT) \
			and DisplayServer.window_is_hdr_output_supported()


## 2D content scale: HiDPI factor times a gentle boost on large screens, so
## the UI reads the same on a laptop and a 4K monitor.
func ui_scale() -> float:
	if DisplayServer.get_name() == "headless":
		return 1.0
	var screen := DisplayServer.window_get_current_screen()
	var dpi := maxf(1.0, DisplayServer.screen_get_scale(screen))
	var logical_h := float(DisplayServer.screen_get_size(screen).y) / dpi
	var user := clampf(float(get_value("display", "ui_scale")), 0.6, 1.6)
	return dpi * clampf(logical_h / 1000.0, 0.85, 1.6) * user


func _default_name() -> String:
	var first := ["Ash", "Cinder", "Ember", "Soot", "Flint", "Brand", "Pyre", "Char", "Wick", "Kindle"]
	var second := ["walker", "born", "heart", "hand", "seeker", "blade", "wright", "mark"]
	return first[randi() % first.size()] + second[randi() % second.size()]
