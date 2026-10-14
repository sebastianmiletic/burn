class_name GlyphCanvas
extends ColorRect
## Base for UI effects drawn with the game's glyph atlas (burning title,
## ember background). Keeps the atlas, ramp, cell size and time uniforms in
## step with the Ascii autoload and the control's physical pixel size.

const RAMP := " .:-=+*o#%8@"

## Cell size in logical UI pixels when no atlas is available yet.
@export var fallback_cell := Vector2(8, 14)
## Multiplies the atlas cell (1 = same grid as the game view).
@export var cell_scale := 1.0

var shader_material := ShaderMaterial.new()
var _time := 0.0


func _init_shader(shader: Shader) -> void:
	shader_material.shader = shader
	material = shader_material
	color = Color.BLACK
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ramp := PackedInt32Array()
	var glyphs := GlyphSet.all_glyphs()
	for i in RAMP.length():
		ramp.append(maxi(0, glyphs.find(RAMP[i])))
	shader_material.set_shader_parameter(&"ramp", ramp)
	shader_material.set_shader_parameter(&"ramp_len", RAMP.length())
	var ascii := get_node_or_null("/root/Ascii")
	if ascii != null:
		ascii.connect("atlas_changed", _on_atlas)
		if ascii.get("atlas_texture") != null:
			_on_atlas(ascii.get("atlas_texture"), ascii.get("atlas_cell"))


func _on_atlas(texture: Texture2D, cell: Vector2i) -> void:
	if cell_scale != 1.0:
		return  # scaled grids use the procedural fallback cells
	shader_material.set_shader_parameter(&"atlas", texture)
	shader_material.set_shader_parameter(&"has_atlas", true)
	shader_material.set_shader_parameter(&"cell_px", Vector2(cell))


func _process(delta: float) -> void:
	_time += delta
	var s := UiTheme.pixel_scale(self)
	shader_material.set_shader_parameter(&"rect_px", size * s)
	shader_material.set_shader_parameter(&"time", _time)
	if not shader_material.get_shader_parameter(&"has_atlas"):
		shader_material.set_shader_parameter(&"cell_px", fallback_cell * cell_scale * s)
