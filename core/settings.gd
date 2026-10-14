extends Node
## Autoload "Settings": every player-facing option, persisted to
## user://settings.cfg. Systems read values from here and listen to `changed`.

signal changed(section: String, key: String)

const PATH := "user://settings.cfg"

enum Quality { LOW, MEDIUM, HIGH, ULTRA }
enum Style { EMBER, FULL_COLOUR, CLASSIC, PHOSPHOR, OFF }
enum WindowMode { FILL_SCREEN, WINDOWED, FULLSCREEN }

const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra"]
const STYLE_NAMES := ["Ember", "Full colour", "Classic", "Phosphor", "ASCII off"]
const WINDOW_MODE_NAMES := ["Fill screen", "Windowed", "Fullscreen"]
const CELL_NAMES := ["Fine 6x10", "Default 8x14", "Chunky 12x20"]

const DEFAULTS := {
	"display": {
		"window_mode": WindowMode.FILL_SCREEN,
		"vsync": true,
		"fps_cap": 0,
	},
	"graphics": {
		"quality": Quality.MEDIUM,
		"render_scale": -1.0,  # -1: follow the quality preset
		"style": Style.EMBER,
		"cell_preset": 1,
		"brightness": 0.85,
		"fov": 70.0,
		"fog": 1.0,
		"bloom": 1.0,
		"vignette": 0.3,
		"grain": 0.04,
		"edges": true,
		"flicker": false,
		"shimmer": false,
		"bg_fill": 0.08,
	},
	"audio": {
		"master": 0.8,
		"music": 0.6,
		"sfx": 0.9,
		"ambient": 0.8,
	},
	"gameplay": {
		"mouse_sensitivity": 1.0,
		"invert_y": false,
		"camera_shake": 1.0,
		"player_name": "",
	},
	"controls": {},
}

var _data := {}


func _ready() -> void:
	_data = DEFAULTS.duplicate(true)
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for section: String in cfg.get_sections():
			if not _data.has(section):
				continue
			for key: String in cfg.get_section_keys(section):
				_data[section][key] = cfg.get_value(section, key)
	if String(_data["gameplay"]["player_name"]) == "":
		_data["gameplay"]["player_name"] = _default_name()
	Keybinds.apply(_data["controls"])
	apply_display()


func get_value(section: String, key: String) -> Variant:
	return _data.get(section, {}).get(key, DEFAULTS.get(section, {}).get(key))


func set_value(section: String, key: String, value: Variant) -> void:
	if get_value(section, key) == value:
		return
	_data[section][key] = value
	if section == "display":
		apply_display()
	changed.emit(section, key)
	save()


func save() -> void:
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
		changed.emit(section, key)
	save()


## Fraction of the logical window resolution the 3D view renders at.
func render_scale() -> float:
	var forced: float = get_value("graphics", "render_scale")
	if forced > 0.0:
		return forced
	return [0.5, 0.62, 0.75, 1.0][int(get_value("graphics", "quality"))]


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window := get_tree().root
	var vsync: bool = get_value("display", "vsync") and not "--no-vsync" in OS.get_cmdline_user_args()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(get_value("display", "fps_cap"))
	window.content_scale_factor = ui_scale()
	if "--resolution" in OS.get_cmdline_args() or "--fullscreen" in OS.get_cmdline_args():
		return  # explicit size from the command line (benchmarks, captures)
	var screen := window.current_screen
	match int(get_value("display", "window_mode")):
		WindowMode.FILL_SCREEN:
			# A borderless window covering the screen: no separate fullscreen space.
			window.mode = Window.MODE_WINDOWED
			window.borderless = true
			window.position = DisplayServer.screen_get_position(screen)
			window.size = DisplayServer.screen_get_size(screen)
		WindowMode.WINDOWED:
			window.mode = Window.MODE_WINDOWED
			window.borderless = false
			var usable := DisplayServer.screen_get_usable_rect(screen)
			window.size = Vector2i(Vector2(usable.size) * 0.8)
			window.position = usable.position + (usable.size - window.size) / 2
		WindowMode.FULLSCREEN:
			window.borderless = false
			window.mode = Window.MODE_FULLSCREEN


## 2D content scale: HiDPI factor times a gentle boost on large screens, so
## the UI reads the same on a laptop and a 4K monitor.
func ui_scale() -> float:
	if DisplayServer.get_name() == "headless":
		return 1.0
	var screen := DisplayServer.window_get_current_screen()
	var dpi := maxf(1.0, DisplayServer.screen_get_scale(screen))
	var logical_h := float(DisplayServer.screen_get_size(screen).y) / dpi
	return dpi * clampf(logical_h / 1000.0, 0.85, 1.6)


func _default_name() -> String:
	var first := ["Ash", "Cinder", "Ember", "Soot", "Flint", "Brand", "Pyre", "Char", "Wick", "Kindle"]
	var second := ["walker", "born", "heart", "hand", "seeker", "blade", "wright", "mark"]
	return first[randi() % first.size()] + second[randi() % second.size()]
