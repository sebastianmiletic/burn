class_name StatBar
extends Control
## Segmented terminal-style bar: label on the left, cells of fill, a fading
## "trail" showing recent loss, and the numbers on the right.

@export var caption := "HP"
@export var fill_color := UiTheme.HEALTH
@export var trail_color := Color(1.0, 0.85, 0.6)
@export var show_numbers := true
@export var segment := 6.0
@export var bar_height := 10.0
@export var caption_width := 34.0
@export var numbers_width := 96.0
## Text drawn instead of numbers (e.g. the rank title).
@export var right_text := ""

var value := 1.0
var max_value := 1.0
var _shown := 1.0
var _trail := 1.0
var _trail_hold := 0.0
var _flash := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(260, 18)


func set_values(v: float, mx: float, instant := false) -> void:
	var before := value / maxf(max_value, 0.0001)
	value = v
	max_value = maxf(mx, 0.0001)
	var ratio := value / max_value
	if ratio < before - 0.001:
		_trail_hold = 0.5
		_flash = 1.0
	if instant:
		_shown = ratio
		_trail = ratio
	queue_redraw()


func _process(delta: float) -> void:
	var ratio := clampf(value / max_value, 0.0, 1.0)
	var moving := absf(_shown - ratio) > 0.0005 or absf(_trail - _shown) > 0.0005 or _flash > 0.0
	_shown = move_toward(_shown, ratio, delta * 2.5)
	if ratio > _trail:
		_trail = ratio
	_trail_hold -= delta
	if _trail_hold <= 0.0:
		_trail = move_toward(_trail, _shown, delta * 0.6)
	_flash = maxf(0.0, _flash - delta * 3.0)
	if moving:
		queue_redraw()


func _draw() -> void:
	var font := UiTheme.MONO
	var fs := 12
	var asc := font.get_ascent(fs)
	var y_text := (size.y + asc - font.get_descent(fs)) * 0.5
	draw_string(UiTheme.MONO_BOLD, Vector2(0, y_text), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fill_color.lerp(UiTheme.TEXT, 0.3))
	var bar_x := caption_width
	var bar_w := size.x - caption_width - (numbers_width if show_numbers or right_text != "" else 0.0)
	var bar := Rect2(bar_x, (size.y - bar_height) * 0.5, bar_w, bar_height)
	draw_rect(bar.grow(1.0), Color(0, 0, 0, 0.6))
	var cells := maxi(1, int(bar.size.x / segment))
	var cw := bar.size.x / cells
	for i in cells:
		var f0 := float(i) / cells
		var r := Rect2(bar.position.x + i * cw, bar.position.y, cw - 1.0, bar.size.y)
		var c := Color(fill_color.r * 0.18, fill_color.g * 0.18, fill_color.b * 0.18, 0.9)
		if f0 < _shown:
			var hot := 1.0 - float(i) / cells * 0.35
			c = fill_color * hot
			c.a = 1.0
			if f0 + 1.0 / cells > _shown:
				c = c.lerp(UiTheme.ACCENT_HOT, 0.35)
		elif f0 < _trail:
			c = trail_color * 0.8
		draw_rect(r, c)
	if _flash > 0.0:
		draw_rect(bar, Color(1, 0.9, 0.7, _flash * 0.35))
	var right := right_text
	if right == "" and show_numbers:
		right = "%d / %d" % [roundi(value), roundi(max_value)]
	if right != "":
		draw_string(font, Vector2(size.x - numbers_width + 8, y_text), right, HORIZONTAL_ALIGNMENT_LEFT, numbers_width - 8, fs, UiTheme.TEXT)
