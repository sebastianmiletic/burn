extends Node
## Autoload "Ascii": owns the ASCII compositor effect and its glyph atlas.
##
## Gameplay and UI code changes the look through this node (cell presets,
## toggles); the effect itself only holds plain values the render thread reads.

signal cell_size_changed(preset: int, physical: Vector2i)

enum CellPreset { FINE, DEFAULT, CHUNKY }

const CELL_PRESETS: Array[Vector2i] = [Vector2i(6, 10), Vector2i(8, 14), Vector2i(12, 20)]
const PRESET_NAMES: Array[String] = ["Fine 6x10", "Default 8x14", "Chunky 12x20"]

var effect := AsciiEffect.new()
var cell_preset := CellPreset.DEFAULT
## 3D render resolution relative to the window's physical pixels. On a 2x
## (Retina) screen, 0.5 renders at the logical resolution and upscales.
var render_scale := 1.0

var _atlas := GlyphAtlas.new()


func _ready() -> void:
	add_child(_atlas)
	_atlas.built.connect(_on_atlas_built)
	_fit_window_to_screen_scale()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--render-scale="):
			render_scale = float(arg.trim_prefix("--render-scale="))
	set_render_scale(render_scale)


## Godot sizes windows in physical pixels; on a 2x screen the project's
## 1600x900 would open at half the intended size. Scale it up once.
func _fit_window_to_screen_scale() -> void:
	var window := get_tree().root
	var scale := screen_scale()
	if scale <= 1.0 or window.mode != Window.MODE_WINDOWED or DisplayServer.get_name() == "headless":
		return
	var base := Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))
	if "--resolution" in OS.get_cmdline_args() or "--fullscreen" in OS.get_cmdline_args():
		return
	if window.size == base:
		var usable := DisplayServer.screen_get_usable_rect(window.current_screen).size
		window.size = Vector2i((Vector2(base) * scale).min(Vector2(usable) * 0.92))
		window.move_to_center()


func screen_scale() -> float:
	return maxf(1.0, DisplayServer.screen_get_scale(DisplayServer.window_get_current_screen()))


func set_render_scale(value: float) -> void:
	render_scale = clampf(value, 0.25, 1.0)
	get_tree().root.scaling_3d_scale = render_scale
	set_cell_preset(cell_preset)


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		effect.z_near = camera.near
		effect.z_far = camera.far


## A compositor that runs the ASCII pass. Assign it to a Camera3D or WorldEnvironment.
func make_compositor() -> Compositor:
	var compositor := Compositor.new()
	var effects: Array[CompositorEffect] = [effect]
	compositor.compositor_effects = effects
	return compositor


func set_cell_preset(preset: int) -> void:
	cell_preset = clampi(preset, 0, CELL_PRESETS.size() - 1) as CellPreset
	var cell := physical_cell_size()
	_atlas.build(cell, cell.x <= 10)


## Cell size in internal 3D pixels. Presets are in logical (1x) pixels, so a
## cell covers the same screen area on every display and render scale.
func physical_cell_size() -> Vector2i:
	var scale := screen_scale() * render_scale
	return Vector2i((Vector2(CELL_PRESETS[cell_preset]) * scale).round()).max(Vector2i(3, 5))


func set_enabled(on: bool) -> void:
	effect.enabled = on


func is_enabled() -> bool:
	return effect.enabled


func _on_atlas_built(image: Image, cell: Vector2i, table: PackedInt32Array) -> void:
	effect.set_atlas(image, cell, table)
	cell_size_changed.emit(cell_preset, cell)
