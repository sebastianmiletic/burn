class_name EmberBackground
extends GlyphCanvas
## Animated ash-and-ember glyph field behind the menus.

const SHADER := preload("res://ui/shaders/ember_field.gdshader")

@export var intensity := 1.0:
	set(v):
		intensity = v
		shader_material.set_shader_parameter(&"intensity", v)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_init_shader(SHADER)
	shader_material.set_shader_parameter(&"intensity", intensity)
