class_name MenuOption
extends Button
## A title-screen option: centred, letter-spaced Cinzel. When hovered or
## focused it warms to amber, a soft ember glow swells behind it, diamond
## ornaments slide in from the sides and a few sparks rise. Mouse hover moves
## keyboard focus, so exactly one option is ever lit.

## Main caption (drawn by this control; Button.text stays empty).
@export var caption := "":
	set(v):
		caption = v
		queue_redraw()
## Optional small second line (e.g. the save "Continue" leads to).
@export var detail := ""
@export var font_size := 22
@export var danger := false

var _hl := 0.0          # animated highlight 0..1
var _press := 0.0       # click flash
var _time := 0.0
var _seed := 0.0

static var _glow_tex: GradientTexture2D


func _init(text_caption := "", on_pressed := Callable(), size_px := 22) -> void:
	caption = text_caption
	font_size = size_px
	if on_pressed.is_valid():
		pressed.connect(on_pressed)


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	flat = true
	text = ""
	_seed = randf() * 100.0
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(s, empty)
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(380, font_size * 2.3 + (14 if detail != "" else 0))
	mouse_entered.connect(func() -> void:
		if not disabled and not has_focus():
			grab_focus())
	focus_entered.connect(func() -> void:
		if not disabled:
			UiContext.sound("ui_hover"))
	button_down.connect(func() -> void: _press = 1.0)
	pressed.connect(func() -> void: UiContext.sound("ui_click"))


func _lit() -> bool:
	return not disabled and (has_focus() or is_hovered())


func _process(delta: float) -> void:
	_time += delta
	var target := 1.0 if _lit() else 0.0
	var before := _hl
	_hl = move_toward(_hl, target, delta * (5.0 if target > _hl else 3.5))
	_press = maxf(0.0, _press - delta * 3.0)
	if _hl > 0.0 or before != _hl or _press > 0.0:
		queue_redraw()


func _font() -> Font:
	return UiTheme.title_font_spaced(600 if not _lit() else 700, 4)


func _draw() -> void:
	var font := _font()
	var e := _hl * _hl * (3.0 - 2.0 * _hl)
	var cx := size.x * 0.5
	var line_h := font.get_height(font_size)
	var text_w := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var block_h := line_h + (16.0 if detail != "" else 0.0)
	var top := (size.y - block_h) * 0.5
	var base := top + font.get_ascent(font_size)
	var accent := UiTheme.DANGER if danger else UiTheme.ACCENT

	# Ember glow behind the caption.
	if e > 0.01:
		if _glow_tex == null:
			_glow_tex = _make_glow()
		var gw := text_w + 220.0
		var gh := size.y * 1.15
		draw_texture_rect(_glow_tex, Rect2(cx - gw * 0.5, (size.y - gh) * 0.5, gw, gh), false,
				Color(accent.r, accent.g * 0.85, accent.b, 0.30 * e + 0.15 * _press))
		# Under-stroke growing from the centre.
		var lw := (text_w * 0.5 + 10.0) * e
		var ly := base + 8.0
		draw_line(Vector2(cx - lw, ly), Vector2(cx + lw, ly), Color(accent, 0.55 * e), 1.0)
		# Diamonds and flourishes sliding in.
		# Ornaments stay inside the control (narrow buttons sit near panel edges).
		var off := minf(text_w * 0.5 + 26.0 + (1.0 - e) * 18.0, cx - 8.0)
		var tail := clampf(cx - off - 12.0, 0.0, 26.0) * e
		var dy := base - font.get_ascent(font_size) * 0.36
		for side in [-1.0, 1.0]:
			var p := Vector2(cx + side * off, dy)
			_diamond(p, 4.0, Color(UiTheme.ACCENT_HOT, e))
			if tail > 1.0:
				draw_line(p + Vector2(side * 9.0, 0), p + Vector2(side * (9.0 + tail), 0), Color(accent, 0.5 * e), 1.0)
		# A few sparks lifting off the glow.
		for i in 5:
			var h := fposmod(_seed * 13.7 + i * 7.31, 1.0)
			var life := fposmod(_time * (0.35 + h * 0.3) + h, 1.0)
			var sx := cx + (h - 0.5) * (text_w + 60.0) + sin(_time * 2.0 + i) * 4.0
			var sy := size.y * 0.75 - life * size.y * 0.9
			draw_rect(Rect2(sx, sy, 2.0, 2.0), Color(UiTheme.ACCENT_HOT, (1.0 - life) * 0.8 * e))

	var col := UiTheme.TEXT.lerp(UiTheme.ACCENT_HOT if not danger else UiTheme.DANGER, e)
	if disabled:
		col = UiTheme.TEXT_FAINT
	var tx := cx - text_w * 0.5
	if e > 0.01:
		var glow := Color(accent, 0.13 * e)
		for o: Vector2 in [Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(0, -1.5), Vector2(0, 1.5)]:
			draw_string(font, Vector2(tx, base) + o, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, glow)
	# A dark outline keeps the letters clean over busy glyphs behind.
	draw_string_outline(font, Vector2(tx, base + 1.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 7, Color(0.01, 0.006, 0.004, 0.8))
	draw_string(font, Vector2(tx, base), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
	if detail != "":
		# Not the mono face: over the world it would read as part of the glyph field.
		var df := UiTheme.title_font_spaced(600, 1)
		var ds := 14
		var dw := df.get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, ds).x
		var dp := Vector2(cx - dw * 0.5, base + 21.0)
		draw_string_outline(df, dp, detail, HORIZONTAL_ALIGNMENT_LEFT, -1, ds, 6, Color(0.01, 0.006, 0.004, 0.85))
		draw_string(df, dp, detail, HORIZONTAL_ALIGNMENT_LEFT, -1, ds, UiTheme.TEXT_DIM.lerp(UiTheme.ACCENT, e * 0.6))


func _diamond(p: Vector2, r: float, c: Color) -> void:
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), c)


static func _make_glow() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.35))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 256
	t.height = 64
	return t
