class_name IntroScreen
extends CanvasLayer
## Opening title: "BURN" smoulders, then burns into existence as glyphs,
## a subtitle fades in, then everything falls back to ash. Any key skips.

signal finished

const SUBTITLE := "every fire remembers the ash it came from"
const DURATION := 5.4

var _root: Control
var _bg: EmberBackground
var _title: BurningTitle
var _subtitle: Label
var _hint: Label
var _t := 0.0
var _done := false


func _ready() -> void:
	layer = 90
	add_to_group(MenuBackdrop.USER_GROUP)
	MenuBackdrop.ensure()  # the menu's live world streams in behind the intro
	_root = Control.new()
	_root.theme = UiTheme.theme()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(black)

	_bg = EmberBackground.new()
	_bg.intensity = 0.0
	_root.add_child(_bg)

	_title = BurningTitle.new()
	_title.progress = 0.0
	_title.letter_scale = 0.78
	_title.set_anchors_preset(Control.PRESET_CENTER)
	_title.custom_minimum_size = Vector2(980, 300)
	_title.size = _title.custom_minimum_size
	_title.position = -_title.size * 0.5 + Vector2(0, -40)
	_root.add_child(_title)

	_subtitle = UiTheme.title(SUBTITLE.to_upper(), 16, UiTheme.ACCENT, 500)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_subtitle.anchor_top = 0.5
	_subtitle.anchor_bottom = 0.5
	_subtitle.offset_left = -400
	_subtitle.offset_right = 400
	_subtitle.offset_top = 130
	_subtitle.offset_bottom = 160
	_subtitle.modulate.a = 0.0
	_root.add_child(_subtitle)

	_hint = UiTheme.label("press any key", UiTheme.SIZE_SMALL, UiTheme.TEXT_FAINT, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_left = -200
	_hint.offset_right = 200
	_hint.offset_top = -48
	_hint.offset_bottom = -28
	_hint.modulate.a = 0.0
	_root.add_child(_hint)
	UiContext.sound("ui_open")


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_title.progress = smoothstep(0.5, 3.1, _t)
	_title.flames = smoothstep(1.5, 3.0, _t)
	_bg.intensity = smoothstep(0.0, 2.5, _t) * 0.55 * (1.0 - smoothstep(4.6, 5.3, _t))
	_subtitle.modulate.a = smoothstep(2.7, 3.5, _t) * (1.0 - smoothstep(4.6, 5.2, _t))
	_hint.modulate.a = smoothstep(1.0, 2.0, _t) * 0.7 * (1.0 - smoothstep(4.4, 4.8, _t))
	_title.fade = 1.0 - smoothstep(4.7, 5.35, _t)
	if _t >= DURATION:
		_finish()


func _input(event: InputEvent) -> void:
	if _done or _t < 0.3:
		return
	if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	# The menu appears under a dark veil that lifts, instead of a hard cut.
	if is_inside_tree():
		var fader := _Fader.new()
		get_tree().root.add_child.call_deferred(fader)
	finished.emit()
	queue_free()


## A black layer over everything that fades out, then frees itself.
class _Fader extends CanvasLayer:
	var _rect: ColorRect
	var _t := 0.0

	func _ready() -> void:
		layer = 95
		_rect = ColorRect.new()
		_rect.color = Color(0.0, 0.0, 0.0, 1.0)
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_rect)

	func _process(delta: float) -> void:
		_t += delta
		_rect.color.a = 1.0 - smoothstep(0.05, 0.9, _t)
		if _t >= 0.9:
			queue_free()
