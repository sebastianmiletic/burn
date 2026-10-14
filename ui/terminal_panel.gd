class_name TerminalPanel
extends Control
## A terminal-style panel: dark background, thin box-drawing frame
## (┌─┐│└┘) with an inset title, and monospace lines. Drawn as UI on top of
## the 3D view, so it is never turned into ASCII.
##
## A line is either a String, or an Array of [text, Color] segments.

const FONT := preload("res://assets/fonts/JetBrainsMono-Regular.ttf")
const ACCENT := Color(1.0, 0.62, 0.22)
const TEXT := Color(0.86, 0.84, 0.8)
const DIM := Color(0.5, 0.49, 0.47)
const BACKGROUND := Color(0.02, 0.02, 0.025, 0.86)

@export var title := ""
@export var font_size := 14
@export var min_columns := 0

var lines: Array = []:
	set(value):
		lines = value
		_resize()
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resize()


func char_size() -> Vector2:
	return Vector2(FONT.get_char_size("M".unicode_at(0), font_size).x, FONT.get_height(font_size))


func _columns() -> int:
	var cols := maxi(min_columns, title.length() + 4)
	for line: Variant in lines:
		cols = maxi(cols, _line_length(line))
	return cols + 2  # one space of padding each side


func _resize() -> void:
	var cs := char_size()
	custom_minimum_size = Vector2((_columns() + 2) * cs.x, (lines.size() + 2) * cs.y)
	size = custom_minimum_size


func _draw() -> void:
	var cs := char_size()
	var ascent := FONT.get_ascent(font_size)
	var cols := _columns()
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)

	var top := "┌─"
	if title != "":
		top += " " + title + " "
	top += "─".repeat(maxi(0, cols - (top.length() - 1)))
	top += "┐"
	_text(Vector2(0, ascent), top, DIM)
	if title != "":
		_text(Vector2(cs.x * 3, ascent), title, ACCENT)

	for i in lines.size():
		var y := ascent + cs.y * (i + 1)
		_text(Vector2(0, y), "│", DIM)
		_text(Vector2(cs.x * (cols + 1), y), "│", DIM)
		var x := cs.x * 2
		var line: Variant = lines[i]
		if line is String:
			_text(Vector2(x, y), line, TEXT)
		else:
			for seg: Array in line:
				var s: String = seg[0]
				_text(Vector2(x, y), s, seg[1])
				x += cs.x * s.length()

	var bottom := "└" + "─".repeat(cols) + "┘"
	_text(Vector2(0, ascent + cs.y * (lines.size() + 1)), bottom, DIM)


func _text(pos: Vector2, s: String, color: Color) -> void:
	draw_string(FONT, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


static func _line_length(line: Variant) -> int:
	if line is String:
		return (line as String).length()
	var n := 0
	for seg: Array in line:
		n += (seg[0] as String).length()
	return n
