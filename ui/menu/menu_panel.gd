class_name MenuPanel
extends Container
## The framed panel used by the title screens (save slots, warband, credits,
## settings, lobby): smoky dark glass, a hairline double border with amber
## corner brackets, and a Cinzel title over an ornamented divider. Children
## fill the content rect, like a MarginContainer.

@export var title := "":
	set(v):
		title = v
		update_minimum_size()
		queue_redraw()
@export var subtitle := "":
	set(v):
		subtitle = v
		update_minimum_size()
		queue_redraw()
@export var padding := Vector2(34, 26)
@export var title_size := 22
@export var background := Color(0.016, 0.012, 0.011, 0.94)


func _init(panel_title := "") -> void:
	title = panel_title


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		var r := content_rect()
		for c in get_children():
			if c is Control and (c as Control).visible and not (c as Control).top_level:
				fit_child_in_rect(c, r)


func _header_h() -> float:
	if title == "":
		return 0.0
	var h := UiTheme.title_font(700).get_height(title_size) + 22.0
	if subtitle != "":
		h += 20.0
	return h


func content_rect() -> Rect2:
	var top := padding.y + _header_h()
	return Rect2(Vector2(padding.x, top), size - Vector2(padding.x * 2.0, top + padding.y))


func _get_minimum_size() -> Vector2:
	var m := Vector2.ZERO
	for c in get_children():
		if c is Control and (c as Control).visible and not (c as Control).top_level:
			m = m.max((c as Control).get_combined_minimum_size())
	var tf := UiTheme.title_font_spaced(700, 4)
	var tw := tf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x + 120.0
	return Vector2(maxf(m.x + padding.x * 2.0, tw), m.y + padding.y * 2.0 + _header_h())


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, background)
	# Warm light pooling at the top edge.
	draw_rect(Rect2(0, 0, size.x, 2), Color(UiTheme.ACCENT, 0.08))
	var border := Color(UiTheme.BORDER, 0.75)
	draw_rect(r.grow(-0.5), border, false, 1.0)
	draw_rect(r.grow(-5.5), Color(UiTheme.BORDER, 0.28), false, 1.0)
	var c := UiTheme.ACCENT_DIM
	var L := 20.0
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var p := Vector2(corner.x * size.x, corner.y * size.y)
		var sx := 1.0 if corner.x == 0 else -1.0
		var sy := 1.0 if corner.y == 0 else -1.0
		draw_line(p + Vector2(sx * 1, sy * 1), p + Vector2(sx * L, sy * 1), c, 2.0)
		draw_line(p + Vector2(sx * 1, sy * 1), p + Vector2(sx * 1, sy * L), c, 2.0)
	if title == "":
		return
	var tf := UiTheme.title_font_spaced(700, 4)
	var tw := tf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
	var ty := padding.y + tf.get_ascent(title_size) - 4.0
	draw_string(tf, Vector2((size.x - tw) * 0.5 + 1.0, ty + 2.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Color(0, 0, 0, 0.6))
	draw_string(tf, Vector2((size.x - tw) * 0.5, ty), title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, UiTheme.ACCENT)
	var dy := ty + 14.0
	if subtitle != "":
		var sf := UiTheme.MONO
		var sw := sf.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_SMALL).x
		draw_string(sf, Vector2((size.x - sw) * 0.5, dy + 10.0), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_SMALL, UiTheme.TEXT_DIM)
		dy += 20.0
	MenuPanel.draw_divider(self, Vector2(size.x * 0.5, dy), minf(size.x * 0.32, 220.0))


## The ── ◆ ── ornament, centred on `at`, `half` pixels to each side.
static func draw_divider(ci: CanvasItem, at: Vector2, half: float, alpha := 1.0) -> void:
	var c := Color(UiTheme.ACCENT_DIM, 0.8 * alpha)
	ci.draw_line(at + Vector2(-half, 0), at + Vector2(-9, 0), c, 1.0)
	ci.draw_line(at + Vector2(9, 0), at + Vector2(half, 0), c, 1.0)
	var r := 4.0
	ci.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)]),
			Color(UiTheme.ACCENT, alpha))
	for s in [-1.0, 1.0]:
		var q := at + Vector2(s * (half + 5.0), 0)
		ci.draw_colored_polygon(PackedVector2Array([q + Vector2(0, -2), q + Vector2(2, 0), q + Vector2(0, 2), q + Vector2(-2, 0)]), c)
