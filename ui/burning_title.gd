class_name BurningTitle
extends GlyphCanvas
## The "BURN" logo: Cinzel letters rendered into a mask, then burnt in as
## glyphs by burning_title.gdshader. `progress` drives the burn-in (0..1).

const SHADER := preload("res://ui/shaders/burning_title.gdshader")

@export var text := "BURN"
@export var progress := 1.0:
	set(v):
		progress = clampf(v, 0.0, 1.0)
		shader_material.set_shader_parameter(&"progress", progress)
@export var flames := 1.0:
	set(v):
		flames = v
		shader_material.set_shader_parameter(&"flames", v)
@export var fade := 1.0:
	set(v):
		fade = v
		shader_material.set_shader_parameter(&"fade", v)
## Letter height as a fraction of the control height.
@export var letter_scale := 0.62

var _mask_vp: SubViewport
var _label: Label


func _ready() -> void:
	_init_shader(SHADER)
	color = Color(0, 0, 0, 0)
	_mask_vp = SubViewport.new()
	_mask_vp.disable_3d = true
	_mask_vp.transparent_bg = false
	_mask_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mask_vp.add_child(bg)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", UiTheme.title_font(900))
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mask_vp.add_child(_label)
	add_child(_mask_vp)
	shader_material.set_shader_parameter(&"mask", _mask_vp.get_texture())
	shader_material.set_shader_parameter(&"progress", progress)
	shader_material.set_shader_parameter(&"flames", flames)
	shader_material.set_shader_parameter(&"fade", fade)
	resized.connect(_rebuild_mask)
	_rebuild_mask.call_deferred()


func _rebuild_mask() -> void:
	if size.x < 4.0 or size.y < 4.0:
		return
	# Mask resolution: enough for crisp sampling at the cell grid.
	var aspect := size.x / size.y
	var h := 512
	_mask_vp.size = Vector2i(int(h * aspect), h)
	_label.text = text
	_label.add_theme_font_size_override("font_size", int(h * letter_scale))
	# Wide letter spacing suits Cinzel capitals.
	var spaced := ""
	for i in text.length():
		spaced += text[i] + (" " if i < text.length() - 1 else "")
	_label.text = spaced
	_mask_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
