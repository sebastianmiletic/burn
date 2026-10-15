class_name ItemStyle
extends RefCounted
## Look of the item screens (inventory, crafting, trade, tooltips, slots):
## dark-fantasy panels with layered bronze borders, filigree corners, a title
## cartouche, warm gradients and a faint grain. Kept separate from UiTheme so
## the menus can be restyled independently; colours echo UiTheme's amber.

const GOLD := Color(0.93, 0.74, 0.42)
const GOLD_DIM := Color(0.6, 0.44, 0.24)
const BRONZE := Color(0.46, 0.33, 0.2)
const INK := Color(0.045, 0.037, 0.033)
const PANEL_TOP := Color(0.1, 0.082, 0.07, 0.97)
const PANEL_BOTTOM := Color(0.045, 0.036, 0.031, 0.97)
const WELL := Color(0.03, 0.025, 0.022, 0.85)
const TEXT := Color(0.9, 0.86, 0.79)
const TEXT_DIM := Color(0.6, 0.56, 0.5)
const TEXT_FAINT := Color(0.4, 0.37, 0.33)
const GOOD := Color(0.5, 0.88, 0.45)
const BAD := Color(0.95, 0.35, 0.28)
const EMBER := Color(1.0, 0.55, 0.2)

static var _grain: Texture2D
static var _radial: Texture2D
static var _boxes := {}


static func title_font(weight := 700) -> Font:
	return UiTheme.title_font(weight)


## Fine film grain, tiled over panels.
static func grain() -> Texture2D:
	if _grain == null:
		var n := 128
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for y in n:
			for x in n:
				var v := rng.randf()
				img.set_pixel(x, y, Color(1, 0.9, 0.75, v * v * 0.5))
		_grain = ImageTexture.create_from_image(img)
	return _grain


## White radial falloff (alpha 1 at the centre, 0 at the edge).
static func radial() -> Texture2D:
	if _radial == null:
		var t := GradientTexture2D.new()
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		t.gradient = g
		t.width = 128
		t.height = 128
		_radial = t
	return _radial


static func vgradient(ci: CanvasItem, r: Rect2, top: Color, bottom: Color) -> void:
	ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))


static func hgradient(ci: CanvasItem, r: Rect2, left: Color, right: Color) -> void:
	ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([left, right, right, left]))


static func diamond(ci: CanvasItem, c: Vector2, r: float, col: Color, filled := true) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	if filled:
		ci.draw_colored_polygon(pts, col)
	else:
		pts.append(pts[0])
		ci.draw_polyline(pts, col, 1.0, true)


## A horizontal rule that fades out at both ends with a diamond in the middle.
static func rule(ci: CanvasItem, from: Vector2, width: float, col := GOLD_DIM, ornament := true) -> void:
	var mid := from + Vector2(width * 0.5, 0)
	var segs := 16
	for i in segs:
		var a := float(i) / segs
		var b := float(i + 1) / segs
		var alpha := sin(PI * (a + b) * 0.5)
		ci.draw_line(from + Vector2(width * a, 0), from + Vector2(width * b, 0), Color(col.r, col.g, col.b, col.a * alpha), 1.0)
	if ornament:
		diamond(ci, mid, 3.5, col)
		diamond(ci, mid + Vector2(-9, 0), 1.6, col)
		diamond(ci, mid + Vector2(9, 0), 1.6, col)


## The big framed panel behind a screen.
static func draw_panel(ci: CanvasItem, r: Rect2, title := "", subtitle := "") -> void:
	# Drop shadow.
	for i in 6:
		var g := float(6 - i) * 4.0
		ci.draw_rect(r.grow(g), Color(0, 0, 0, 0.06))
	vgradient(ci, r, PANEL_TOP, PANEL_BOTTOM)
	# Warm glow from the top centre and darker edges.
	ci.draw_texture_rect(radial(), Rect2(r.position + Vector2(r.size.x * 0.1, -r.size.y * 0.35), Vector2(r.size.x * 0.8, r.size.y * 0.9)), false, Color(1.0, 0.55, 0.2, 0.07))
	ci.draw_texture_rect(grain(), r, true, Color(1, 1, 1, 0.05))
	# Layered borders: dark outline, bronze band, fine gold inner line.
	ci.draw_rect(r, Color(0, 0, 0, 0.9), false, 2.0)
	ci.draw_rect(r.grow(-3), BRONZE, false, 2.0)
	ci.draw_rect(r.grow(-7), Color(GOLD.r, GOLD.g, GOLD.b, 0.35), false, 1.0)
	for corner in 4:
		_corner(ci, r, corner)
	if title != "":
		_cartouche(ci, r, title, subtitle)


static func _corner(ci: CanvasItem, r: Rect2, corner: int) -> void:
	var sx := 1.0 if corner % 2 == 0 else -1.0
	var sy := 1.0 if corner < 2 else -1.0
	var o := Vector2(r.position.x if sx > 0 else r.end.x, r.position.y if sy > 0 else r.end.y)
	var d := Vector2(sx, sy)
	var col := GOLD
	# L bracket.
	ci.draw_line(o + d * 3.0, o + Vector2(sx * 34.0, sy * 3.0), col, 2.0)
	ci.draw_line(o + d * 3.0, o + Vector2(sx * 3.0, sy * 34.0), col, 2.0)
	# Filigree: two arcs and a diamond.
	var c := o + d * 13.0
	ci.draw_arc(c, 7.0, 0.0, TAU, 16, Color(col.r, col.g, col.b, 0.55), 1.0, true)
	diamond(ci, c, 3.2, col)
	diamond(ci, o + Vector2(sx * 40.0, sy * 3.0), 2.2, col)
	diamond(ci, o + Vector2(sx * 3.0, sy * 40.0), 2.2, col)


static func _cartouche(ci: CanvasItem, r: Rect2, title: String, subtitle: String) -> void:
	var font := title_font(700)
	var fs := 24
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 6.0 * title.length()
	var w := maxf(tw + 80.0, 240.0)
	var h := 40.0
	var cx := r.position.x + r.size.x * 0.5
	var top := r.position.y - h * 0.5
	var pts := PackedVector2Array([Vector2(cx - w * 0.5, top + h * 0.5), Vector2(cx - w * 0.5 + 16, top), Vector2(cx + w * 0.5 - 16, top),
		Vector2(cx + w * 0.5, top + h * 0.5), Vector2(cx + w * 0.5 - 16, top + h), Vector2(cx - w * 0.5 + 16, top + h)])
	ci.draw_colored_polygon(pts, Color(0.16, 0.06, 0.04, 0.98))
	ci.draw_polygon(PackedVector2Array([pts[1], pts[2], Vector2(pts[2].x, top + h * 0.5), Vector2(pts[1].x, top + h * 0.5)]),
		PackedColorArray([Color(0.4, 0.14, 0.07, 0.6), Color(0.4, 0.14, 0.07, 0.6), Color(0.4, 0.14, 0.07, 0.0), Color(0.4, 0.14, 0.07, 0.0)]))
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, GOLD, 1.6, true)
	var inner := PackedVector2Array()
	for p in closed:
		inner.append(Vector2(cx, top + h * 0.5) + (p - Vector2(cx, top + h * 0.5)) * Vector2((w - 10.0) / w, 0.78))
	ci.draw_polyline(inner, Color(GOLD.r, GOLD.g, GOLD.b, 0.35), 1.0, true)
	diamond(ci, Vector2(cx - w * 0.5, top + h * 0.5), 5.0, GOLD)
	diamond(ci, Vector2(cx + w * 0.5, top + h * 0.5), 5.0, GOLD)
	spaced(ci, font, Vector2(cx, top + h * 0.5 + fs * 0.36), title, fs, Color(1.0, 0.86, 0.6), 6.0, true)
	if subtitle != "":
		var sf := UiTheme.MONO
		var sw := sf.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		ci.draw_string(sf, Vector2(cx - sw * 0.5, top + h + 18), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT_DIM)


## Letter-spaced text, centred on `pos.x` when `centred`.
static func spaced(ci: CanvasItem, font: Font, pos: Vector2, text: String, fs: int, col: Color, spacing := 3.0, centred := false, shadow := true) -> void:
	var total := 0.0
	for ch in text:
		total += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + spacing
	total -= spacing
	var x := pos.x - total * 0.5 if centred else pos.x
	for ch in text:
		if shadow:
			ci.draw_string(font, Vector2(x + 1, pos.y + 2), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.7))
		ci.draw_string(font, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + spacing


## Section header: small caps title with a fading rule.
static func draw_header(ci: CanvasItem, pos: Vector2, width: float, text: String, col := GOLD_DIM) -> void:
	var font := title_font(700)
	spaced(ci, font, pos + Vector2(0, 12), text, 13, Color(0.92, 0.76, 0.5), 2.5, false, true)
	var tw := 0.0
	for ch in text:
		tw += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 2.5
	var x0 := pos.x + tw + 10.0
	if x0 < pos.x + width:
		hgradient(ci, Rect2(Vector2(x0, pos.y + 7), Vector2(pos.x + width - x0, 1)), Color(col.r, col.g, col.b, 0.8), Color(col.r, col.g, col.b, 0.0))
		diamond(ci, Vector2(x0, pos.y + 7.5), 2.5, col)


## A recessed well (lists, detail areas).
static func draw_well(ci: CanvasItem, r: Rect2, accent := Color(0, 0, 0, 0)) -> void:
	ci.draw_rect(r, WELL)
	vgradient(ci, Rect2(r.position, Vector2(r.size.x, minf(18.0, r.size.y))), Color(0, 0, 0, 0.35), Color(0, 0, 0, 0))
	ci.draw_rect(r, Color(0.0, 0.0, 0.0, 0.8), false, 1.0)
	ci.draw_rect(r.grow(-1), Color(BRONZE.r, BRONZE.g, BRONZE.b, 0.45), false, 1.0)
	if accent.a > 0.0:
		ci.draw_texture_rect(radial(), Rect2(r.position + Vector2(0, r.size.y * 0.2), r.size * Vector2(1.0, 0.8)), false, accent)


## Item slot frame. rarity tints the glow and border; states add highlights.
static func draw_slot(ci: CanvasItem, r: Rect2, rarity := -1, selected := false, hover := false, marked := false, disabled := false) -> void:
	var rc: Color = ItemDB.RARITY_COLORS[clampi(rarity, 0, 5)] if rarity >= 0 else Color(0.5, 0.45, 0.4)
	var bg := Color(0.06, 0.05, 0.045, 0.94)
	if hover:
		bg = Color(0.09, 0.075, 0.062, 0.96)
	if selected:
		for i in 4:
			ci.draw_rect(r.grow(2.0 + i * 2.0), Color(1.0, 0.65, 0.25, 0.09 - i * 0.02), false, 2.0)
	ci.draw_rect(r, bg)
	vgradient(ci, Rect2(r.position, Vector2(r.size.x, r.size.y * 0.5)), Color(1, 1, 1, 0.035), Color(1, 1, 1, 0.0))
	if rarity >= 1:
		ci.draw_texture_rect(radial(), r.grow(-2), false, Color(rc.r, rc.g, rc.b, 0.22))
	elif rarity == 0:
		ci.draw_texture_rect(radial(), r.grow(-2), false, Color(1.0, 0.8, 0.6, 0.06))
	# Bevel: dark outer, light inner top-left.
	ci.draw_rect(r, Color(0, 0, 0, 0.85), false, 1.0)
	var border := Color(0.3, 0.24, 0.17)
	if rarity >= 1:
		border = rc.darkened(0.25)
	if hover:
		border = border.lightened(0.25)
	if marked:
		border = Color(1.0, 0.85, 0.5)
	if selected:
		border = GOLD
	ci.draw_rect(r.grow(-1), border, false, 1.0 if not selected else 2.0)
	ci.draw_line(r.position + Vector2(2, 2), Vector2(r.end.x - 2, r.position.y + 2), Color(1, 1, 1, 0.06), 1.0)
	if rarity >= 3 or selected:
		var cc := GOLD if selected else rc
		for corner in 4:
			var sx := 1.0 if corner % 2 == 0 else -1.0
			var sy := 1.0 if corner < 2 else -1.0
			var o := Vector2(r.position.x if sx > 0 else r.end.x, r.position.y if sy > 0 else r.end.y) + Vector2(sx, sy) * 1.0
			ci.draw_line(o, o + Vector2(sx * 8.0, 0), cc, 2.0)
			ci.draw_line(o, o + Vector2(0, sy * 8.0), cc, 2.0)
	if disabled:
		ci.draw_rect(r, Color(0, 0, 0, 0.45))


## Draws an item's icon (or its glyph while the icon renders) into `r`.
static func draw_item(ci: CanvasItem, r: Rect2, id: String, alpha := 1.0) -> void:
	var tex := ItemIcons.icon(id)
	if tex != null:
		ci.draw_texture_rect(tex, Rect2(r.position + Vector2(2, 3), r.size), false, Color(0, 0, 0, 0.45 * alpha))
		ci.draw_texture_rect(tex, r, false, Color(1, 1, 1, alpha))
		return
	var g := ItemDB.glyph(id)
	var col := ItemDB.color(id)
	col.a = alpha
	var font := UiTheme.MONO_BOLD
	var fs := int(r.size.y * 0.5)
	var gs := font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pos := r.position + Vector2((r.size.x - gs.x) * 0.5, (r.size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
	ci.draw_string(font, pos + Vector2(0, 1), g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.r, col.g, col.b, 0.25 * alpha))
	ci.draw_string(font, pos, g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Outlined text (counts on slots).
static func outlined(ci: CanvasItem, font: Font, pos: Vector2, text: String, fs: int, col: Color) -> void:
	ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## A premium button style (used for the main action buttons).
static func button(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", title_font(700))
	b.add_theme_font_size_override("font_size", 15 if primary else 13)
	b.add_theme_color_override("font_color", Color(1.0, 0.88, 0.62) if primary else TEXT)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.8))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.95, 0.8))
	b.add_theme_color_override("font_disabled_color", TEXT_FAINT)
	b.add_theme_color_override("font_focus_color", Color(1.0, 0.9, 0.7))
	for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, _button_box(st, primary))
	if cb.is_valid():
		b.pressed.connect(cb)
	b.pressed.connect(func() -> void: UiContext.sound("ui_click"))
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			UiContext.sound("ui_hover"))
	return b


static func _button_box(state: String, primary: bool) -> StyleBox:
	var key := "%s|%s" % [state, primary]
	if _boxes.has(key):
		return _boxes[key]
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(3)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 8 if primary else 5
	s.content_margin_bottom = 8 if primary else 5
	s.set_border_width_all(1)
	var base := Color(0.32, 0.1, 0.05) if primary else Color(0.12, 0.095, 0.08)
	match state:
		"normal":
			s.bg_color = base
			s.border_color = GOLD_DIM if primary else BRONZE
		"hover":
			s.bg_color = base.lightened(0.12)
			s.border_color = GOLD
			s.shadow_color = Color(1.0, 0.55, 0.2, 0.25)
			s.shadow_size = 6
		"pressed":
			s.bg_color = base.darkened(0.2)
			s.border_color = GOLD
		"disabled":
			s.bg_color = Color(0.07, 0.06, 0.055)
			s.border_color = Color(0.22, 0.19, 0.16)
		"focus":
			s.draw_center = false
			s.border_color = GOLD
	if primary and state != "disabled" and state != "focus":
		s.border_width_top = 1
		s.border_width_bottom = 2
	_boxes[key] = s
	return s


## Hides a UiModal's terminal frame and puts an ornate panel behind it.
static func dress(modal: UiModal, title: String, subtitle := "") -> OrnatePanel:
	modal.frame.self_modulate = Color(1, 1, 1, 0)
	modal.frame.padding = Vector2(26, 34)
	var p := OrnatePanel.new()
	p.title = title
	p.subtitle = subtitle
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(p)
	modal.move_child(p, modal.frame.get_index())
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.offset_left = modal.frame.offset_left
	p.offset_right = modal.frame.offset_right
	p.offset_top = modal.frame.offset_top
	p.offset_bottom = modal.frame.offset_bottom
	return p


## Ornate background panel control (see draw_panel).
class OrnatePanel:
	extends Control
	var title := "":
		set(v):
			title = v
			queue_redraw()
	var subtitle := "":
		set(v):
			subtitle = v
			queue_redraw()

	func _draw() -> void:
		ItemStyle.draw_panel(self, Rect2(Vector2.ZERO, size), title, subtitle)


static func header(text: String, width := 0.0) -> Header:
	var h := Header.new()
	h.text = text
	h.custom_minimum_size = Vector2(width, 22)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL if width <= 0.0 else Control.SIZE_FILL
	return h


## Section title with a fading rule.
class Header:
	extends Control
	var text := ""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		ItemStyle.draw_header(self, Vector2(0, 2), size.x, text)


static func well(margin := 10) -> Well:
	var w := Well.new()
	for side: String in ["left", "right", "top", "bottom"]:
		w.add_theme_constant_override("margin_" + side, margin)
	return w


## A recessed area that lays its children out with margins.
class Well:
	extends MarginContainer
	var accent := Color(0, 0, 0, 0)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _draw() -> void:
		ItemStyle.draw_well(self, Rect2(Vector2.ZERO, size), accent)
