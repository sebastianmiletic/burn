class_name UiModal
extends Control
## Base for in-game screens that take the mouse: a dimmed backdrop, a framed
## panel in the centre, Esc to close, sounds, and telling gameplay to release
## the mouse while open.

signal closed

@export var panel_size := Vector2(760, 520)
@export var panel_title := ""
@export var scrim_alpha := 0.55
## Some screens (death, victory) must not be closed with Esc.
@export var escape_closes := true

var frame: TermFrame
var content: VBoxContainer
var is_open := false


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	add_child(UiTheme.scrim(scrim_alpha))
	frame = TermFrame.new()
	frame.title = panel_title
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -panel_size.x * 0.5
	frame.offset_right = panel_size.x * 0.5
	frame.offset_top = -panel_size.y * 0.5
	frame.offset_bottom = panel_size.y * 0.5
	add_child(frame)
	content = VBoxContainer.new()
	frame.add_child(content)
	_build()


## Subclasses add their widgets to `content` here.
func _build() -> void:
	pass


## Subclasses refresh their data here; called on every open.
func _on_open() -> void:
	pass


func open() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	_on_open()
	UiContext.set_ui_open(true)
	UiContext.sound("ui_open")


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	UiContext.sound("ui_close")
	UiContext.set_ui_open(false)
	closed.emit()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if escape_closes and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
