class_name MenuStage
extends Control
## Everything behind the title-screen UI: the live world (MenuBackdrop, drawn
## by its WorldView far below), a veil that keeps text readable over it, and
## the ember field shown until the world has streamed in (and for good where
## there is no backdrop, e.g. headless or --no-menu-world).
## Also shows the cinematic location card for the current shot.

## 0..1: how much the centre band darkens on top of the base veil (panels).
var focus_dim := 0.0:
	set(v):
		focus_dim = v
		if _veil != null:
			_veil.shader_material.set_shader_parameter(&"band_extra", v)
## Show the location card in the corner.
var show_caption := true
## A control whose rect gets a soft dark pool behind it (the title).
var pool_target: Control

var _embers: EmberBackground
var _veil: GlyphCanvas
var _card: VBoxContainer
var _card_title: Label
var _card_sub: Label
var _card_text := ""
var _card_alpha := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(MenuBackdrop.USER_GROUP)
	MenuBackdrop.ensure()

	_veil = GlyphCanvas.new()
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_veil)
	_veil._init_shader(preload("res://ui/menu/menu_veil.gdshader"))
	_veil.color = Color(0, 0, 0, 0)
	_embers = EmberBackground.new()
	add_child(_embers)
	move_child(_embers, 0)

	_card = VBoxContainer.new()
	_card.add_theme_constant_override("separation", 0)
	_card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_card.offset_left = 44
	_card.offset_right = 600
	_card.offset_top = -112
	_card.offset_bottom = -52
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_title = UiTheme.title("", 17, UiTheme.ACCENT, 700)
	_card_title.add_theme_font_override("font", UiTheme.title_font_spaced(700, 3))
	_card.add_child(_card_title)
	_card_title.add_theme_color_override("font_outline_color", Color(0.01, 0.006, 0.004, 0.85))
	_card_title.add_theme_constant_override("outline_size", 6)
	_card_sub = UiTheme.title("", 13, UiTheme.TEXT_DIM, 500)
	_card_sub.add_theme_font_override("font", UiTheme.title_font_spaced(500, 1))
	_card_sub.add_theme_color_override("font_outline_color", Color(0.01, 0.006, 0.004, 0.85))
	_card_sub.add_theme_constant_override("outline_size", 5)
	_card.add_child(_card_sub)
	_card.modulate.a = 0.0
	add_child(_card)
	_update(0.0)


func _process(delta: float) -> void:
	_update(delta)


func _update(delta: float) -> void:
	var b := MenuBackdrop.instance()
	var reveal := b.reveal if b != null else 0.0
	_embers.modulate.a = 1.0 - smoothstep(0.0, 1.0, reveal)
	_embers.visible = _embers.modulate.a > 0.004
	_veil.shader_material.set_shader_parameter(&"strength", lerpf(0.35, 1.0, reveal))
	if pool_target != null and is_instance_valid(pool_target) and pool_target.is_visible_in_tree() and size.x > 0.0:
		var r := pool_target.get_global_rect()
		var c := (r.get_center() - global_position) / size
		var h := r.size / size * 0.62
		_veil.shader_material.set_shader_parameter(&"title_rect", Vector4(c.x, c.y, h.x, h.y))
	else:
		_veil.shader_material.set_shader_parameter(&"title_rect", Vector4(0.5, -1.0, 0.01, 0.01))
	# Location card: follows the shot's own fade, swaps text while dark.
	var target := 0.0
	# Narrow windows: the centred UI needs the room, the card would overlap it.
	if b != null and show_caption and b.caption != "" and size.x >= 1180.0:
		target = clampf(b.visibility * 1.3 - 0.3, 0.0, 1.0) * reveal
		var text := b.caption.to_upper()
		if text != _card_text and _card_alpha < 0.05:
			_card_text = text
			_card_title.text = "◆  " + text
			_card_sub.text = "     " + b.caption_sub + "  ·  " + UiTheme.clock(b.time_of_day())
		if text != _card_text:
			target = 0.0
		elif _card_alpha > 0.5:
			_card_sub.text = "     " + b.caption_sub + "  ·  " + UiTheme.clock(b.time_of_day())
	_card_alpha = move_toward(_card_alpha, target, delta * 1.5)
	_card.modulate.a = _card_alpha * 0.85
