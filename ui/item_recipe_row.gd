class_name RecipeRow
extends Control
## One recipe in a list: icon in a rarity frame, the result's name, and its
## ingredients as small icons with have/need counts (green when covered, red
## when short). Craftable rows glow; selected rows get a gold bar.

signal pressed(recipe_id: String)
signal hovered(recipe_id: String, row: RecipeRow)
signal unhovered(recipe_id: String)

var recipe_id := ""
var inventory: Inventory
var station_ok := true
var selected := false:
	set(v):
		selected = v
		queue_redraw()
## Show a "CRAFT" pill on hover (inventory hand-crafting list).
var quick := false
var _hover := false
var _icon_version := -1


func _ready() -> void:
	custom_minimum_size = Vector2(0, 58)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void:
		_hover = true
		hovered.emit(recipe_id, self)
		UiContext.sound("ui_hover")
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		unhovered.emit(recipe_id)
		queue_redraw())


func craftable() -> bool:
	return inventory != null and station_ok and ItemDB.missing_for(recipe_id, inventory).is_empty()


func _process(_d: float) -> void:
	if _icon_version != ItemIcons.version:
		_icon_version = ItemIcons.version
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(recipe_id)
		accept_event()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var ok := craftable()
	var result := ItemDB.recipe_result(recipe_id)
	var rc := ItemDB.rarity_color(result)
	if selected:
		ItemStyle.hgradient(self, r, Color(1.0, 0.6, 0.25, 0.2), Color(1.0, 0.6, 0.25, 0.03))
		draw_rect(Rect2(0, 0, 3, size.y), ItemStyle.GOLD)
	elif _hover:
		ItemStyle.hgradient(self, r, Color(1.0, 0.8, 0.6, 0.08), Color(1.0, 0.8, 0.6, 0.0))
	draw_line(Vector2(8, size.y - 0.5), Vector2(size.x - 8, size.y - 0.5), Color(ItemStyle.BRONZE.r, ItemStyle.BRONZE.g, ItemStyle.BRONZE.b, 0.25), 1.0)
	var icon_r := Rect2(Vector2(8, 5), Vector2(size.y - 10, size.y - 10))
	ItemStyle.draw_slot(self, icon_r, ItemDB.rarity(result), false, _hover, false, not ok)
	ItemStyle.draw_item(self, icon_r.grow(-4), result, 1.0 if ok else 0.5)
	var count := int(ItemDB.recipe(recipe_id).get("count", 1))
	if count > 1:
		ItemStyle.outlined(self, UiTheme.MONO_BOLD, icon_r.end - Vector2(16, 3), "×%d" % count, 10, ItemStyle.TEXT)
	var x := icon_r.end.x + 10
	var name_col := rc if ok else rc.darkened(0.35)
	draw_string(ItemStyle.title_font(700), Vector2(x, 23), ItemDB.display_name(result), HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 60, 14, name_col)
	# Ingredients: tiny icons with have/need.
	var inputs: Dictionary = ItemDB.recipe(recipe_id).get("inputs", {})
	var ix := x
	var font := UiTheme.MONO_BOLD
	for item: String in inputs:
		var need := int(inputs[item])
		var have := inventory.count_of(item) if inventory != null else 0
		ItemStyle.draw_item(self, Rect2(Vector2(ix, 30), Vector2(20, 20)), item)
		var t := "%d/%d" % [mini(have, 999), need]
		var col := ItemStyle.GOOD if have >= need else ItemStyle.BAD
		draw_string(font, Vector2(ix + 22, 45), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
		ix += 24 + font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 8
		if ix > size.x - 40:
			break
	var fuel := int(ItemDB.recipe(recipe_id).get("fuel", 0))
	if fuel > 0 and ix < size.x - 50:
		var units := inventory.fuel_units(inputs) if inventory != null else 0
		draw_string(font, Vector2(ix, 45), "fuel %d" % fuel, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ItemStyle.GOOD if units >= fuel else ItemStyle.BAD)
	# State marker.
	if ok:
		var c := Vector2(size.x - 16, size.y * 0.5)
		draw_texture_rect(ItemStyle.radial(), Rect2(c - Vector2(12, 12), Vector2(24, 24)), false, Color(1.0, 0.6, 0.2, 0.5))
		ItemStyle.diamond(self, c, 4.5, ItemStyle.GOLD)
	elif not station_ok:
		draw_string(UiTheme.MONO, Vector2(size.x - 70, 23), "station", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ItemStyle.TEXT_FAINT)
	if quick and _hover and ok:
		var pill := Rect2(Vector2(size.x - 74, size.y * 0.5 - 11), Vector2(54, 22))
		draw_rect(pill, Color(0.32, 0.1, 0.05))
		draw_rect(pill, ItemStyle.GOLD, false, 1.0)
		draw_string(ItemStyle.title_font(700), pill.position + Vector2(7, 16), "CRAFT", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.88, 0.62))
