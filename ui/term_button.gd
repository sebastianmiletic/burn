class_name TermButton
extends Button
## Menu button: plain text that lights amber with a "▸" marker on hover or
## keyboard focus, and plays the UI sounds.

@export var marker := true


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	mouse_entered.connect(_on_hover)
	focus_entered.connect(_on_hover)
	pressed.connect(func() -> void: UiContext.sound("ui_click"))
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _on_hover() -> void:
	if not disabled:
		UiContext.sound("ui_hover")


func _draw() -> void:
	if not marker or disabled:
		return
	if is_hovered() or has_focus():
		var font := get_theme_font("font")
		var fs := get_theme_font_size("font_size")
		var y := (size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5
		draw_string(font, Vector2(2, y), "▸", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.ACCENT)
