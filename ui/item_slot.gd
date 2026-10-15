class_name ItemSlot
extends Control
## One inventory slot: a bevelled, rarity-tinted frame with the item's 3D
## icon (its glyph until the icon has rendered), stack count, key hint,
## socketed-gem pip and an optional "ghost" item for empty equipment slots.
## Supports drag & drop between slots; `accept` can veto a drop.

signal clicked(index: int, button: int)
signal hovered(index: int)
signal unhovered(index: int)
signal dropped_on(from_index: int, to_index: int)

@export var index := 0
@export var key_hint := ""
@export var selected := false:
	set(v):
		selected = v
		queue_redraw()
@export var draggable := false
@export var glyph_size := 30
## Faint item drawn when empty (equipment slots show what belongs there).
var ghost := ""
## Optional label drawn under the ghost ("HEAD").
var caption := ""
## Callable(from_index: int, to_index: int) -> bool. Null = accept all.
var accept: Callable
var dim := false:
	set(v):
		dim = v
		queue_redraw()

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
var _icon_version := -1


func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(60, 60)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_filter = Control.MOUSE_FILTER_STOP if draggable else Control.MOUSE_FILTER_IGNORE
	mouse_entered.connect(func() -> void:
		_hover = true
		hovered.emit(index)
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		unhovered.emit(index)
		queue_redraw())


func pulse() -> void:
	_pulse = 1.0


func _process(delta: float) -> void:
	if _pulse > 0.0:
		_pulse = maxf(0.0, _pulse - delta * 3.0)
		queue_redraw()
	# Redraw once the icon arrives.
	if _icon_version != ItemIcons.version:
		_icon_version = ItemIcons.version
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
		clicked.emit(index, mb.button_index)


func _get_drag_data(_at: Vector2) -> Variant:
	if not draggable or item.is_empty():
		return null
	var preview := _DragPreview.new()
	preview.id = String(item["id"])
	preview.count = int(item.get("count", 1))
	preview.size = size
	set_drag_preview(preview)
	return {"slot_index": index, "id": item["id"]}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if not draggable or not (data is Dictionary and (data as Dictionary).has("slot_index")):
		return false
	if accept.is_valid():
		return bool(accept.call(int(data["slot_index"]), index))
	return true


func _drop_data(_at: Vector2, data: Variant) -> void:
	dropped_on.emit(int(data["slot_index"]), index)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var id := String(item.get("id", ""))
	ItemStyle.draw_slot(self, r, ItemDB.rarity(id) if id != "" else -1, selected, _hover, marked, dim)
	if _pulse > 0.0:
		draw_rect(r.grow(-1), Color(1, 0.65, 0.25, _pulse * 0.22))
	var pad := size.x * 0.1
	var ir := Rect2(Vector2(pad, pad), size - Vector2(pad, pad) * 2.0)
	if id == "":
		if ghost != "":
			ItemStyle.draw_item(self, ir.grow(-size.x * 0.04), ghost, 0.12)
		if caption != "":
			var f := UiTheme.MONO
			var w := f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			draw_string(f, Vector2((size.x - w) * 0.5, size.y - 6), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, ItemStyle.TEXT_FAINT)
	else:
		ItemStyle.draw_item(self, ir, id, 0.55 if dim else 1.0)
		var count := int(item.get("count", 1))
		if count > 1:
			var t := str(count)
			var fs := 13 if size.x >= 56 else 11
			var ts := UiTheme.MONO_BOLD.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			ItemStyle.outlined(self, UiTheme.MONO_BOLD, Vector2(size.x - ts.x - 5, size.y - 5), t, fs, ItemStyle.TEXT)
		if item.has("gem"):
			var gc := ItemDB.color(String(item["gem"]))
			var gp := Vector2(size.x - 9, 9)
			ItemStyle.diamond(self, gp, 5.0, Color(0, 0, 0, 0.7))
			ItemStyle.diamond(self, gp, 3.8, gc)
			draw_circle(gp + Vector2(-1, -1), 1.0, Color(1, 1, 1, 0.8))
	if key_hint != "":
		ItemStyle.outlined(self, UiTheme.MONO_BOLD, Vector2(5, 13), key_hint, 10, ItemStyle.GOLD if selected else ItemStyle.TEXT_DIM)


class _DragPreview:
	extends Control
	var id := ""
	var count := 1

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		modulate.a = 0.9

	func _draw() -> void:
		var r := Rect2(-size * 0.5, size)
		draw_texture_rect(ItemStyle.radial(), r.grow(10), false, Color(1.0, 0.6, 0.25, 0.25))
		ItemStyle.draw_item(self, r.grow(-size.x * 0.08), id)
		if count > 1:
			ItemStyle.outlined(self, UiTheme.MONO_BOLD, r.end - Vector2(22, 4), str(count), 13, ItemStyle.TEXT)
