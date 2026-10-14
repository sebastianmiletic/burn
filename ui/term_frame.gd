class_name TermFrame
extends Container
## A panel framed with real box-drawing characters (┌─┐│└┘) and an optional
## title set into the top border. Children are laid out inside the frame like
## a MarginContainer (all children fill the content rect).

@export var title := "":
	set(v):
		title = v
		update_minimum_size()
		queue_redraw()
@export var padding := Vector2(18, 16)
@export var background := UiTheme.BG
@export var border_color := UiTheme.BORDER
@export var title_color := UiTheme.ACCENT
@export var font_size := 14
## Draws small amber accents at the corners.
@export var accent_corners := true


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		var r := content_rect()
		for c in get_children():
			if c is Control and (c as Control).visible and not (c as Control).top_level:
				fit_child_in_rect(c, r)


func content_rect() -> Rect2:
	var cs := _cell()
	var top := cs.y * 0.5 + padding.y
	return Rect2(Vector2(padding.x, top), size - Vector2(padding.x * 2.0, top + padding.y))


func _get_minimum_size() -> Vector2:
	var m := Vector2.ZERO
	for c in get_children():
		if c is Control and (c as Control).visible and not (c as Control).top_level:
			m = m.max((c as Control).get_combined_minimum_size())
	var cs := _cell()
	var w := maxf(m.x + padding.x * 2.0, (title.length() + 6) * cs.x)
	return Vector2(w, m.y + padding.y * 2.0 + cs.y * 0.5)


func _cell() -> Vector2:
	var f := UiTheme.MONO
	return Vector2(f.get_char_size("─".unicode_at(0), font_size).x, f.get_height(font_size))


func _draw() -> void:
	var f := UiTheme.MONO
	var cs := _cell()
	var asc := f.get_ascent(font_size)
	var half := cs.y * 0.5
	draw_rect(Rect2(Vector2(0, half), size - Vector2(0, half)), background)
	# Horizontal runs: repeat ─ and let the last one overlap the corner neatly.
	var cols := maxi(2, int(floorf(size.x / cs.x)))
	var step := size.x / cols
	var top_y := half - cs.y * 0.5 + asc
	var bot_y := size.y - cs.y + asc
	var title_from := 2
	var title_to := 2 + title.length() + 2 if title != "" else 0
	for i in range(1, cols - 1):
		var x := i * step
		if title != "" and i >= title_from and i < title_to:
			pass
		else:
			_glyph(f, Vector2(x, top_y), "─", border_color)
		_glyph(f, Vector2(x, bot_y), "─", border_color)
	# Vertical runs
	var rows := maxi(2, int(floorf((size.y - half) / cs.y)))
	var vstep := (size.y - half) / rows
	for j in range(1, rows):
		var y := half + j * vstep - cs.y * 0.5 + asc
		if y > bot_y - cs.y * 0.6:
			break
		_glyph(f, Vector2(0, y), "│", border_color)
		_glyph(f, Vector2(size.x - cs.x, y), "│", border_color)
	var cc := title_color if accent_corners else border_color
	_glyph(f, Vector2(0, top_y), "┌", cc)
	_glyph(f, Vector2(size.x - cs.x, top_y), "┐", cc)
	_glyph(f, Vector2(0, bot_y), "└", cc)
	_glyph(f, Vector2(size.x - cs.x, bot_y), "┘", cc)
	if title != "":
		var tx := title_from * step + cs.x * 0.5
		draw_string(UiTheme.MONO_BOLD, Vector2(tx, top_y), " " + title + " ", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, title_color)


func _glyph(f: Font, pos: Vector2, ch: String, color: Color) -> void:
	draw_string(f, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
