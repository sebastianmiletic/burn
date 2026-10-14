extends Node
## Autoload "Ascii": owns the ASCII compositor effect, builds the glyph atlas
## at the current cell size, and keeps both in step with Settings.

signal atlas_changed(texture: ImageTexture, cell: Vector2i)

const CELL_PRESETS: Array[Vector2i] = [Vector2i(6, 10), Vector2i(8, 14), Vector2i(12, 20)]

var effect := AsciiEffect.new()
var atlas_texture: ImageTexture
var atlas_cell := Vector2i.ZERO

var _atlas := GlyphAtlas.new()
var _requested_cell := Vector2i.ZERO


func _ready() -> void:
	add_child(_atlas)
	_atlas.built.connect(_on_atlas_built)
	Settings.changed.connect(_on_setting)
	_apply_settings()
	rebuild_atlas()


func _process(_delta: float) -> void:
	# The screen scale changes when the window moves between displays.
	if output_cell_size() != _requested_cell:
		rebuild_atlas()


## A compositor that runs the ASCII analysis. AsciiView puts it on its camera.
func make_compositor() -> Compositor:
	var compositor := Compositor.new()
	var effects: Array[CompositorEffect] = [effect]
	compositor.compositor_effects = effects
	return compositor


func screen_scale() -> float:
	if DisplayServer.get_name() == "headless":
		return 1.0
	return maxf(1.0, DisplayServer.screen_get_scale(DisplayServer.window_get_current_screen()))


## Glyph cell size in physical screen pixels. Presets are in logical pixels.
func output_cell_size() -> Vector2i:
	var preset := CELL_PRESETS[clampi(int(Settings.get_value("graphics", "cell_preset")), 0, 2)]
	return Vector2i((Vector2(preset) * screen_scale()).round())


func style() -> int:
	return int(Settings.get_value("graphics", "style"))


func rebuild_atlas() -> void:
	_requested_cell = output_cell_size()
	_atlas.build(_requested_cell, true)


func _on_atlas_built(image: Image, cell: Vector2i, table: PackedInt32Array) -> void:
	atlas_texture = ImageTexture.create_from_image(image)
	atlas_cell = cell
	effect.set_glyph_table(table)
	atlas_changed.emit(atlas_texture, cell)


func _on_setting(section: String, key: String) -> void:
	if section != "graphics":
		return
	if key == "cell_preset":
		rebuild_atlas()
	_apply_settings()


func _apply_settings() -> void:
	effect.classic_ramp = style() == Settings.Style.CLASSIC
	effect.draw_edges = bool(Settings.get_value("graphics", "edges"))
	effect.flicker = 0.6 if Settings.get_value("graphics", "flicker") else 0.0
	effect.enabled = style() != Settings.Style.OFF
