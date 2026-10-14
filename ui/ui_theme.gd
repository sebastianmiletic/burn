class_name UiTheme
extends RefCounted
## Shared look for every screen: terminal panels, one amber accent,
## JetBrains Mono for text and Cinzel for titles. `UiTheme.theme()` is
## assigned to each screen's root Control and inherited by its children.

const MONO := preload("res://assets/fonts/JetBrainsMono-Regular.ttf")
const MONO_BOLD := preload("res://assets/fonts/JetBrainsMono-Bold.ttf")
const CINZEL := preload("res://assets/fonts/Cinzel.ttf")

const ACCENT := Color(1.0, 0.62, 0.22)
const ACCENT_HOT := Color(1.0, 0.82, 0.5)
const ACCENT_DIM := Color(0.62, 0.36, 0.14)
const TEXT := Color(0.88, 0.85, 0.8)
const TEXT_DIM := Color(0.55, 0.52, 0.49)
const TEXT_FAINT := Color(0.36, 0.34, 0.32)
const BORDER := Color(0.42, 0.33, 0.25)
const BG := Color(0.03, 0.025, 0.025, 0.92)
const BG_SOLID := Color(0.035, 0.028, 0.026)
const BG_HOVER := Color(1.0, 0.62, 0.22, 0.1)
const DANGER := Color(0.95, 0.28, 0.2)
const HEALTH := Color(0.86, 0.22, 0.16)
const GOOD := Color(0.55, 0.85, 0.45)
const FROST := Color(0.55, 0.85, 1.0)

const SIZE_SMALL := 12
const SIZE_BODY := 14
const SIZE_LARGE := 18

static var _theme: Theme
static var _title_fonts := {}


static func theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


## Cinzel at a given weight (400 regular .. 900 black).
static func title_font(weight := 700) -> Font:
	if not _title_fonts.has(weight):
		var f := FontVariation.new()
		f.base_font = CINZEL
		f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		_title_fonts[weight] = f
	return _title_fonts[weight]


static func panel_box(bg := BG, border := BORDER, width := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_content_margin_all(10)
	s.anti_aliasing = false
	return s


static func flat(color: Color, margin := 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_content_margin_all(margin)
	return s


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font = MONO
	t.default_font_size = SIZE_BODY

	t.set_color("font_color", "Label", TEXT)
	t.set_constant("line_spacing", "Label", 2)

	# Buttons: text-like, amber on hover with a faint fill.
	var normal := flat(Color(0, 0, 0, 0), 6)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	var hover := flat(BG_HOVER, 6)
	hover.content_margin_left = 14
	hover.content_margin_right = 14
	hover.border_color = ACCENT_DIM
	hover.border_width_left = 2
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(1.0, 0.62, 0.22, 0.2)
	var disabled := normal.duplicate() as StyleBoxFlat
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = ACCENT_DIM
	focus.border_width_left = 2
	for type in ["Button", "OptionButton", "CheckBox", "CheckButton", "MenuButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, focus)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, ACCENT_HOT)
		t.set_color("font_pressed_color", type, ACCENT_HOT)
		t.set_color("font_hover_pressed_color", type, ACCENT_HOT)
		t.set_color("font_focus_color", type, ACCENT)
		t.set_color("font_disabled_color", type, TEXT_FAINT)
	t.set_icon("checked", "CheckBox", _check_icon(true))
	t.set_icon("unchecked", "CheckBox", _check_icon(false))
	t.set_icon("arrow", "OptionButton", _arrow_icon())

	# Text entry
	var edit := flat(Color(0.0, 0.0, 0.0, 0.55), 6)
	edit.border_color = BORDER
	edit.set_border_width_all(1)
	var edit_focus := edit.duplicate() as StyleBoxFlat
	edit_focus.border_color = ACCENT
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", edit_focus)
	t.set_stylebox("read_only", "LineEdit", edit)
	t.set_color("font_color", "LineEdit", ACCENT_HOT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(1, 0.6, 0.2, 0.35))
	t.set_color("font_placeholder_color", "LineEdit", TEXT_FAINT)

	# Sliders: thin line, amber fill, small square grabber.
	var slider := flat(Color(0.25, 0.2, 0.17), 0)
	slider.content_margin_top = 1
	slider.content_margin_bottom = 1
	var fill := flat(ACCENT_DIM, 0)
	fill.content_margin_top = 1
	fill.content_margin_bottom = 1
	t.set_stylebox("slider", "HSlider", slider)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _square_icon(ACCENT, 10))
	t.set_icon("grabber_highlight", "HSlider", _square_icon(ACCENT_HOT, 12))
	t.set_icon("grabber_disabled", "HSlider", _square_icon(TEXT_FAINT, 10))

	# Scroll bars
	var sb := flat(Color(0.12, 0.1, 0.09), 0)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	var grab := flat(Color(0.4, 0.3, 0.22), 0)
	var grab_hi := flat(ACCENT_DIM, 0)
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, sb)
		t.set_stylebox("grabber", type, grab)
		t.set_stylebox("grabber_highlight", type, grab_hi)
		t.set_stylebox("grabber_pressed", type, grab_hi)

	# Popup menus (OptionButton drop-downs)
	var popup := panel_box(BG_SOLID, ACCENT_DIM)
	popup.set_content_margin_all(4)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", flat(BG_HOVER, 2))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", ACCENT_HOT)
	t.set_icon("radio_checked", "PopupMenu", _square_icon(ACCENT, 6))
	t.set_icon("radio_unchecked", "PopupMenu", _square_icon(Color(0, 0, 0, 0), 6))

	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "TooltipPanel", panel_box(BG_SOLID, ACCENT_DIM))
	t.set_color("font_color", "TooltipLabel", TEXT)

	# Tabs
	var tab_sel := flat(Color(1, 0.62, 0.22, 0.12), 8)
	tab_sel.border_color = ACCENT
	tab_sel.border_width_bottom = 2
	var tab_un := flat(Color(0, 0, 0, 0), 8)
	var tab_hover := flat(Color(1, 0.62, 0.22, 0.06), 8)
	t.set_stylebox("tab_selected", "TabBar", tab_sel)
	t.set_stylebox("tab_unselected", "TabBar", tab_un)
	t.set_stylebox("tab_hovered", "TabBar", tab_hover)
	t.set_stylebox("tab_focus", "TabBar", StyleBoxEmpty.new())
	t.set_color("font_selected_color", "TabBar", ACCENT_HOT)
	t.set_color("font_unselected_color", "TabBar", TEXT_DIM)
	t.set_color("font_hovered_color", "TabBar", TEXT)
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab_un)
	t.set_stylebox("tab_hovered", "TabContainer", tab_hover)
	t.set_stylebox("panel", "TabContainer", flat(Color(0, 0, 0, 0), 10))
	t.set_color("font_selected_color", "TabContainer", ACCENT_HOT)
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXT)

	var sep := StyleBoxLine.new()
	sep.color = BORDER
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 12)
	t.set_constant("separation", "VBoxContainer", 6)
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_stylebox("panel", "ItemList", flat(Color(0, 0, 0, 0.3), 4))
	return t


static func _square_icon(color: Color, size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


static func _check_icon(on: bool) -> ImageTexture:
	var n := 14
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in n:
		img.set_pixel(i, 0, BORDER)
		img.set_pixel(i, n - 1, BORDER)
		img.set_pixel(0, i, BORDER)
		img.set_pixel(n - 1, i, BORDER)
	if on:
		for y in range(3, n - 3):
			for x in range(3, n - 3):
				img.set_pixel(x, y, ACCENT)
	return ImageTexture.create_from_image(img)


static func _arrow_icon() -> ImageTexture:
	var img := Image.create(9, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 5:
		for x in range(y, 9 - y):
			img.set_pixel(x, y, ACCENT_DIM)
	return ImageTexture.create_from_image(img)


# --- Little factories used across screens ----------------------------------------

static func label(text: String, size := SIZE_BODY, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l


static func title(text: String, size := 32, color := ACCENT, weight := 700) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", title_font(weight))
	return l


static func button(text: String, on_pressed: Callable = Callable(), size := SIZE_BODY) -> TermButton:
	var b := TermButton.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	return b


static func spacer(h := 8.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func hsep() -> HSeparator:
	return HSeparator.new()


## Full-screen dark scrim behind modal screens.
static func scrim(alpha := 0.6) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.0, 0.0, 0.0, alpha)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r


## Physical pixels per logical UI pixel for `node`'s viewport.
static func pixel_scale(node: CanvasItem) -> float:
	if DisplayServer.get_name() == "headless":
		return 1.0
	var vis := node.get_viewport().get_visible_rect().size
	return float(DisplayServer.window_get_size().x) / maxf(1.0, vis.x)


static func format_int(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func format_time(seconds: float) -> String:
	var s := int(seconds)
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s / 60) % 60]
	return "%dm %02ds" % [s / 60, s % 60]


static func clock(hours: float) -> String:
	var h := int(floorf(hours)) % 24
	var m := int(fmod(hours, 1.0) * 60.0)
	return "%02d:%02d" % [h, m]
