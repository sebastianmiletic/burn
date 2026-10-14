class_name ItemSlot
extends Control
## One inventory slot: framed square, the item's glyph in its colour, a stack
## count, an optional key hint. Supports drag & drop between slots.

signal clicked(index: int, button: int)
signal hovered(index: int)
signal dropped_on(from_index: int, to_index: int)

@export var index := 0
@export var key_hint := ""
@export var selected := false:
	set(v):
		selected = v
		queue_redraw()
@export var draggable := false
@export var glyph_size := 30

var item := {}:
	set(v):
		item = v
		queue_redraw()
var marked := false:
	set(v):
		marked = v
		queue_redraw()
var _hover := false
var _pulse := 0.0


func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(60, 60)
	mouse_filter = Control.MOUSE_FILTER_STOP if draggable else Control.MOUSE_FILTER_IGNORE
	mouse_entered.connect(func() -> void:
		_hover = true
		hovered.emit(index)
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())


func pulse() -> void:
	_pulse = 1.0


func _process(delta: float) -> void:
	if _pulse > 0.0:
		_pulse = maxf(0.0, _pulse - delta * 3.0)
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
		clicked.emit(index, mb.button_index)


func _get_drag_data(_at: Vector2) -> Variant:
	if not draggable or item.is_empty():
		return null
	var preview := Label.new()
	preview.text = ItemDB.glyph(item["id"])
	preview.add_theme_font_override("font", UiTheme.MONO_BOLD)
	preview.add_theme_font_size_override("font_size", glyph_size)
	preview.add_theme_color_override("font_color", ItemDB.color(item["id"]))
	set_drag_preview(preview)
	return {"slot_index": index}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return draggable and data is Dictionary and (data as Dictionary).has("slot_index")


func _drop_data(_at: Vector2, data: Variant) -> void:
	dropped_on.emit(int(data["slot_index"]), index)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var border := UiTheme.BORDER
	var bg := Color(0.02, 0.016, 0.015, 0.85)
	if selected:
		border = UiTheme.ACCENT
		bg = Color(0.12, 0.06, 0.02, 0.9)
	elif marked:
		border = UiTheme.ACCENT_HOT
	elif _hover:
		border = UiTheme.ACCENT_DIM
	draw_rect(r, bg)
	if _pulse > 0.0:
		draw_rect(r, Color(1, 0.6, 0.2, _pulse * 0.25))
	draw_rect(r.grow(-0.5), border, false, 1.0)
	# Bracket corners give the slot its terminal look.
	var c := 7.0
	var cc := UiTheme.ACCENT if selected else border.lightened(0.15)
	for corner: Vector2 in [Vector2(0, 0), Vector2(size.x, 0), Vector2(0, size.y), Vector2(size.x, size.y)]:
		var sx := 1.0 if corner.x == 0 else -1.0
		var sy := 1.0 if corner.y == 0 else -1.0
		draw_line(corner, corner + Vector2(c * sx, 0), cc, 2.0)
		draw_line(corner, corner + Vector2(0, c * sy), cc, 2.0)
	if key_hint != "":
		draw_string(UiTheme.MONO, Vector2(5, 13), key_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UiTheme.TEXT_FAINT if not selected else UiTheme.ACCENT)
	if item.is_empty():
		return
	var id: String = item.get("id", "")
	var g := ItemDB.glyph(id)
	var col := ItemDB.color(id)
	var font := UiTheme.MONO_BOLD
	var gs := font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, glyph_size)
	var gpos := Vector2((size.x - gs.x) * 0.5, (size.y + font.get_ascent(glyph_size) - font.get_descent(glyph_size)) * 0.5)
	# Soft glow behind the glyph.
	draw_string(font, gpos + Vector2(0, 1), g, HORIZONTAL_ALIGNMENT_LEFT, -1, glyph_size, Color(col.r, col.g, col.b, 0.25))
	draw_string(font, gpos, g, HORIZONTAL_ALIGNMENT_LEFT, -1, glyph_size, col)
	var count := int(item.get("count", 1))
	if count > 1:
		var t := str(count)
		var ts := UiTheme.MONO.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		draw_string(UiTheme.MONO_BOLD, Vector2(size.x - ts.x - 5, size.y - 5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.TEXT)
