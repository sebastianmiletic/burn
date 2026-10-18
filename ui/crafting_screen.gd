class_name CraftingScreen
extends UiModal
## The crafting book of a station (workbench, furnace, anvil, alchemy table,
## the village smithy, or "" = by hand). Left: recipes grouped by kind with
## have/need at a glance. Right: the selected result turning on a lit plinth,
## its stats compared with what you use now, the ingredients you have and
## miss, a quantity picker and the craft button. Timed work (smelting,
## forging, brewing) fills a progress bar; materials are taken as each item
## completes, so closing the screen never loses anything.
##
## Opened by Events.station_open(kind, station). Crafting goes through
## Player.craft(recipe_id) - client-local like the rest of the inventory.

const GROUP_NAMES := {"basics": "Basics", "stations": "Stations", "building": "Building", "smelting": "Smelting", "food": "Cooking",
	"tools": "Tools", "weapons": "Weapons", "armor": "Armour", "potions": "Potions"}
## Seconds per craft when a recipe sets no "time".
const DEFAULT_TIME := {"": 0.35, "workbench": 0.6, "anvil": 1.1, "furnace": 1.6, "alchemy": 1.5, "campfire": 1.8, "smithy": 1.0}
const WORK_SOUND := {"workbench": "pick_wood", "anvil": "hit_metal", "furnace": "fire", "alchemy": "potion", "campfire": "fire", "": "cloth"}

var kind := ""
var station: Node = null
var _kinds: Array = []
var _list: VBoxContainer
var _rows := {}
var _selected := ""
var _only_craftable := false
var _filter_btn: Button
var _preview: ItemPreview
var _name: Label
var _type: Label
var _stats: RichTextLabel
var _desc: Label
var _ingredients: VBoxContainer
var _qty := 1
var _qty_label: Label
var _craft_btn: Button
var _progress: CraftProgress
var _status: Label
var _panel: ItemStyle.OrnatePanel
var _chips: Label
var _tooltip: ItemTooltip
# Work queue: recipe being made, how many left, seconds per item, elapsed.
var _job := ""
var _job_left := 0
var _job_time := 1.0
var _job_t := 0.0
var _clang_t := 0.0


## Adds one CraftingScreen next to `sibling` (the inventory screen) if none exists.
static func ensure(sibling: Node) -> void:
	var tree := sibling.get_tree()
	if tree == null or tree.get_first_node_in_group(&"crafting_screen") != null:
		return
	var parent := sibling.get_parent()
	if parent == null:
		return
	var c := CraftingScreen.new()
	parent.add_child(c)
	parent.move_child(c, sibling.get_index() + 1)


func _init() -> void:
	panel_size = Vector2(1220, 720)
	panel_title = ""
	add_to_group(&"crafting_screen")


func _build() -> void:
	_panel = ItemStyle.dress(self, "CRAFTING")
	var head := HBoxContainer.new()
	content.add_child(head)
	_chips = UiTheme.label("", 12, ItemStyle.TEXT_DIM)
	_chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_chips)
	_filter_btn = ItemStyle.button("Show: all", func() -> void:
		_only_craftable = not _only_craftable
		_rebuild_list())
	head.add_child(_filter_btn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	# Recipe list.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(420, 0)
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	left.add_child(ItemStyle.header("RECIPES"))
	var lw := ItemStyle.well(4)
	lw.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(lw)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lw.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 0)
	scroll.add_child(_list)
	# Detail.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	right.add_child(top)
	var stage := ItemStyle.well(0)
	stage.accent = Color(1.0, 0.55, 0.2, 0.22)
	top.add_child(stage)
	_preview = ItemPreview.new()
	_preview.custom_minimum_size = Vector2(250, 250)
	stage.add_child(_preview)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	top.add_child(info)
	_name = UiTheme.label("", 26, ItemStyle.GOLD)
	_name.add_theme_font_override("font", ItemStyle.title_font(700))
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_name)
	_type = UiTheme.label("", 12, ItemStyle.TEXT_DIM)
	info.add_child(_type)
	info.add_child(UiTheme.spacer(4))
	_stats = RichTextLabel.new()
	_stats.bbcode_enabled = true
	_stats.fit_content = true
	_stats.scroll_active = false
	_stats.add_theme_font_size_override("normal_font_size", 13)
	_stats.add_theme_font_override("normal_font", UiTheme.MONO)
	_stats.add_theme_font_override("bold_font", UiTheme.MONO_BOLD)
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(_stats)
	_desc = UiTheme.label("", 12, Color(0.78, 0.72, 0.62))
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_desc)
	right.add_child(ItemStyle.header("REQUIRES"))
	var iw := ItemStyle.well(10)
	iw.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(iw)
	_ingredients = VBoxContainer.new()
	_ingredients.add_theme_constant_override("separation", 6)
	iw.add_child(_ingredients)
	# Quantity, craft button, progress.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	right.add_child(bar)
	bar.add_child(ItemStyle.button("−", func() -> void: _set_qty(_qty - 1)))
	_qty_label = UiTheme.label("1", 18, ItemStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_qty_label.add_theme_font_override("font", ItemStyle.title_font(700))
	_qty_label.custom_minimum_size = Vector2(44, 0)
	bar.add_child(_qty_label)
	bar.add_child(ItemStyle.button("+", func() -> void: _set_qty(_qty + 1)))
	bar.add_child(ItemStyle.button("Max", func() -> void: _set_qty(_max_qty())))
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spring)
	_craft_btn = ItemStyle.button("Craft", _on_craft, true)
	_craft_btn.custom_minimum_size = Vector2(220, 46)
	bar.add_child(_craft_btn)
	_progress = CraftProgress.new()
	_progress.custom_minimum_size = Vector2(0, 26)
	right.add_child(_progress)
	_status = UiTheme.label("", 13, ItemStyle.TEXT_DIM)
	right.add_child(_status)
	_tooltip = ItemTooltip.new()
	add_child(_tooltip)
	UiContext.on("station_open", open_station)
	# Until the HUD lists this screen itself, step aside for screens that take over.
	UiContext.on("dialog_open", func(_n: Node, _t: String, _l: PackedStringArray, _o: Array) -> void: _step_aside())
	UiContext.on("player_died", func(_c: String) -> void: _step_aside())
	UiContext.on("campaign_won", _step_aside)
	UiContext.on("inventory_changed", func() -> void:
		if is_open:
			_refresh_rows()
			_show_detail())


func _step_aside() -> void:
	if is_open:
		close()


## Opens the book for a station kind ("" = by hand, "smithy" = village smith).
func open_station(station_kind: String, station_node: Node = null) -> void:
	kind = station_kind
	station = station_node
	_close_others()
	if is_open:
		_on_open()
	else:
		open()


func _close_others() -> void:
	var p := get_parent()
	if p == null:
		return
	for c in p.get_children():
		if c != self and c is UiModal and (c as UiModal).is_open and (c is InventoryScreen or c is ShopScreen):
			(c as UiModal).close()


func _on_open() -> void:
	_cancel_job()
	_kinds = nearby_station_kinds()
	if kind != "" and not kind in _kinds:
		_kinds.append(kind)
	var title := ItemDB.station_name(kind).to_upper() if kind != "" else "CRAFTING"
	_panel.title = title
	var desc := String(ItemDB.STATIONS.get(kind, {}).get("desc", "Iron, ember and bone, shaped to your need."))
	var near := PackedStringArray()
	for k: String in _kinds:
		if k != "":
			near.append(ItemDB.station_name(k))
	_chips.text = desc + ("   ·   Within reach: " + ", ".join(near) if not near.is_empty() else "")
	_craft_btn.text = _verb()
	_selected = ""
	_qty = 1
	_status.text = ""
	ItemIcons.prewarm()
	_rebuild_list()


func _verb() -> String:
	return String(ItemDB.STATIONS.get(kind if kind != "smithy" else "anvil", {}).get("verb", "Craft"))


## Station kinds within 4 m of the local player (the station that opened the
## book always counts). Uses Player.nearby_station_kinds() when it exists.
func nearby_station_kinds() -> Array:
	var p := UiContext.player()
	var v: Variant = UiContext.call_on(p, "nearby_station_kinds", [], null)
	if v is Array:
		return (v as Array).duplicate()
	var out: Array = []
	var w := UiContext.world()
	if p is Node3D and w != null and w.has_method("entities_near"):
		var near: Variant = w.call("entities_near", (p as Node3D).global_position, 4.0, int(p.get("dimension")))
		if near is Array:
			for e: Variant in near:
				if not e is Node:
					continue
				var en := e as Node
				if str(en.get("kind")) == "station":
					out.append(str(en.get("station_kind")))
				elif str(en.get("kind")) == "npc" and str(en.get("role")) == "blacksmith":
					out.append("smithy")
	return out


func _recipes() -> Array:
	var list: Array = []
	var kinds := [kind]
	if kind == "smithy":
		kinds = ["anvil", "furnace"]
	for k: String in kinds:
		list.append_array(ItemDB.recipes_for_station(k))
	return list


func _rebuild_list() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows.clear()
	_filter_btn.text = "Show: can make" if _only_craftable else "Show: all"
	var inv := UiContext.inventory() as Inventory
	var last_group := ""
	var first_ok := ""
	var first := ""
	for rid: String in _recipes():
		var row := RecipeRow.new()
		row.recipe_id = rid
		row.inventory = inv
		row.station_ok = ItemDB.station_available(rid, _kinds)
		if _only_craftable and not row.craftable():
			row.free()
			continue
		var g := String(ItemDB.recipe(rid).get("group", ""))
		if g != last_group:
			last_group = g
			var h := ItemStyle.header(String(GROUP_NAMES.get(g, g.capitalize())).to_upper())
			h.custom_minimum_size = Vector2(0, 30)
			var m := MarginContainer.new()
			m.add_theme_constant_override("margin_left", 10)
			m.add_theme_constant_override("margin_right", 10)
			m.add_theme_constant_override("margin_top", 6)
			m.add_child(h)
			_list.add_child(m)
		row.pressed.connect(_select)
		_list.add_child(row)
		_rows[rid] = row
		if first == "":
			first = rid
		if first_ok == "" and row.craftable():
			first_ok = rid
	if _list.get_child_count() == 0:
		_list.add_child(UiTheme.label("  Nothing you can make here yet.", 13, ItemStyle.TEXT_DIM))
	_select(first_ok if first_ok != "" else first)


func _refresh_rows() -> void:
	for rid: String in _rows:
		(_rows[rid] as RecipeRow).queue_redraw()


func _select(rid: String) -> void:
	if rid != _selected:
		_qty = 1
	_selected = rid
	for r: String in _rows:
		(_rows[r] as RecipeRow).selected = r == rid
	_show_detail()


func _show_detail() -> void:
	for c in _ingredients.get_children():
		_ingredients.remove_child(c)
		c.queue_free()
	if _selected == "":
		_name.text = ""
		_type.text = ""
		_stats.text = ""
		_desc.text = ""
		_preview.show_item("")
		_craft_btn.disabled = true
		return
	var inv := UiContext.inventory() as Inventory
	var r := ItemDB.recipe(_selected)
	var result := ItemDB.recipe_result(_selected)
	var count := int(r.get("count", 1))
	_preview.show_item(result)
	_name.text = ItemDB.display_name(result) + ("  ×%d" % count if count > 1 else "")
	_name.add_theme_color_override("font_color", ItemDB.rarity_color(result))
	_type.text = "%s  ·  %s" % [ItemDB.RARITY_NAMES[ItemDB.rarity(result)], ItemDB.type_label(result)]
	var cmp := _compare_for(inv, result)
	_stats.text = "\n".join(ItemTooltip.stat_lines({"id": result, "count": 1}, cmp))
	if not cmp.is_empty():
		_stats.text += "\n[color=#%s]compared with your %s[/color]" % [ItemStyle.TEXT_FAINT.to_html(false), ItemDB.display_name(String(cmp["id"]))]
	_desc.text = String(ItemDB.info(result).get("desc", ""))
	var inputs: Dictionary = r.get("inputs", {})
	for item: String in inputs:
		_ingredients.add_child(_ingredient(item, int(inputs[item]) * _qty, inv.count_of(item) if inv != null else 0))
	var fuel := int(r.get("fuel", 0)) * _qty
	if fuel > 0:
		var units := inv.fuel_units(inputs, _qty) if inv != null else 0
		_ingredients.add_child(_ingredient("coal", fuel, units, "Fuel  (coal 4 · charcoal 4 · wood 2 · planks 1)"))
	var need_station := ItemDB.recipe_station(_selected)
	if not ItemDB.station_available(_selected, _kinds):
		var l := UiTheme.label("Needs a %s within reach." % ItemDB.station_name(need_station), 13, ItemStyle.BAD)
		_ingredients.add_child(l)
	var t := _time_for(_selected)
	if t > 0.4:
		_ingredients.add_child(UiTheme.label("Takes %.1f s each" % t, 11, ItemStyle.TEXT_FAINT))
	_qty_label.text = str(_qty)
	_update_button()


func _ingredient(item: String, need: int, have: int, label := "") -> Control:
	var row := IngredientRow.new()
	row.item = item
	row.need = need
	row.have = have
	row.label = label if label != "" else ItemDB.display_name(item)
	row.custom_minimum_size = Vector2(0, 40)
	row.hovered.connect(func(id: String, rr: Control) -> void:
		if label == "":
			_tooltip.show_item({"id": id, "count": have}, rr.get_global_rect()))
	row.unhovered.connect(func() -> void: _tooltip.hide_tip())
	return row


func _compare_for(inv: Inventory, result: String) -> Dictionary:
	if inv == null:
		return {}
	var cat := ItemDB.category(result)
	if cat == "armor":
		return inv.get_slot(Inventory.equip_index(ItemDB.equip_slot(result)))
	if cat == "weapon" or cat == "tool":
		# Compare with the same kind if carried, otherwise with what is in hand.
		var k := ItemDB.kind_of(result)
		var best := {}
		for i in inv.size():
			var s := inv.get_slot(i)
			if not s.is_empty() and ItemDB.kind_of(String(s["id"])) == k and ItemDB.category(String(s["id"])) == cat:
				if best.is_empty() or float(ItemDB.info(String(s["id"])).get("damage", 0.0)) > float(ItemDB.info(String(best["id"])).get("damage", 0.0)):
					best = s
		if not best.is_empty():
			return best
		var held := inv.get_slot(inv.selected)
		return held if ItemDB.is_gear(String(held.get("id", ""))) else {}
	return {}


func _max_qty() -> int:
	var inv := UiContext.inventory() as Inventory
	if inv == null or _selected == "":
		return 1
	return maxi(1, inv.craftable_times(_selected, 64))


func _set_qty(q: int) -> void:
	_qty = clampi(q, 1, 64)
	if ItemDB.is_gear(ItemDB.recipe_result(_selected)):
		_qty = mini(_qty, 8)
	_show_detail()


func _update_button() -> void:
	var inv := UiContext.inventory() as Inventory
	if _job != "":
		_craft_btn.text = "Stop"
		_craft_btn.disabled = false
		return
	_craft_btn.text = _verb() + ("  ×%d" % _qty if _qty > 1 else "")
	_craft_btn.disabled = inv == null or not ItemDB.station_available(_selected, _kinds) or not ItemDB.missing_for(_selected, inv, _qty).is_empty()


func _time_for(rid: String) -> float:
	var r := ItemDB.recipe(rid)
	if r.has("time"):
		return float(r["time"])
	return float(DEFAULT_TIME.get(ItemDB.recipe_station(rid), 0.5))


func _on_craft() -> void:
	if _job != "":
		_cancel_job()
		_say("Stopped.", false)
		return
	if _selected == "":
		return
	var inv := UiContext.inventory() as Inventory
	var miss := ItemDB.missing_for(_selected, inv, _qty) if inv != null else {"?": 1}
	if not miss.is_empty():
		var parts := PackedStringArray()
		for k: String in miss:
			parts.append("%d %s" % [miss[k], "fuel" if k == "fuel" else (ItemDB.display_name(k) if ItemDB.exists(k) else k)])
		_say("Missing " + ", ".join(parts) + ".", false)
		UiContext.sound("ui_back")
		return
	_job = _selected
	_job_left = _qty
	_job_time = _time_for(_selected)
	_job_t = 0.0
	_clang_t = 0.0
	_progress.active = true
	_progress.kind = kind
	_update_button()


func _cancel_job() -> void:
	_job = ""
	_job_left = 0
	_job_t = 0.0
	if _progress != null:
		_progress.active = false
		_progress.value = 0.0
	if _craft_btn != null and _selected != "":
		_update_button()


func _process(delta: float) -> void:
	if _job == "":
		return
	_job_t += delta
	_clang_t -= delta
	if _clang_t <= 0.0:
		_clang_t = 0.38 if kind == "anvil" or kind == "smithy" else 0.9
		UiContext.sound(String(WORK_SOUND.get(kind, "ui_click")))
	_progress.value = clampf(_job_t / maxf(_job_time, 0.01), 0.0, 1.0)
	_progress.label = "%s %s   %d left" % [_verb() + "ing" if not _verb().ends_with("e") else _verb().trim_suffix("e") + "ing", ItemDB.display_name(ItemDB.recipe_result(_job)), _job_left]
	if _job_t < _job_time:
		return
	_job_t = 0.0
	var rid := _job
	var ok: bool = UiContext.call_on(UiContext.player(), "craft", [rid], false)
	if not ok:
		_say("The work stopped: something is missing.", false)
		_cancel_job()
		return
	_job_left -= 1
	_progress.flash()
	UiContext.sound("pickup")
	var made := int(ItemDB.recipe(rid).get("count", 1))
	_say("%s %s%s." % ["Made", ItemDB.display_name(ItemDB.recipe_result(rid)), " ×%d" % made if made > 1 else ""], true)
	if _job_left <= 0:
		_cancel_job()
		UiContext.sound("levelup" if ItemDB.is_gear(ItemDB.recipe_result(rid)) else "coin")
	_refresh_rows()
	_show_detail()


func _say(text: String, good: bool) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", ItemStyle.GOOD if good else ItemStyle.BAD)


func close() -> void:
	_cancel_job()
	if _tooltip != null:
		_tooltip.hide_tip()
	super()


func _unhandled_input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("inventory"):
		close()
		get_viewport().set_input_as_handled()
		return
	super(event)


## Gallery hook: start crafting the first craftable recipe several times.
func debug_start() -> void:
	for rid: String in _rows:
		if (_rows[rid] as RecipeRow).craftable():
			_select(rid)
			break
	_set_qty(mini(5, _max_qty()))
	_on_craft()


## An ingredient with icon, name and have/need.
class IngredientRow:
	extends Control
	signal hovered(id: String, row: Control)
	signal unhovered
	var item := ""
	var need := 1
	var have := 0
	var label := ""
	var _v := -1

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mouse_filter = Control.MOUSE_FILTER_PASS
		mouse_entered.connect(func() -> void: hovered.emit(item, self))
		mouse_exited.connect(func() -> void: unhovered.emit())

	func _process(_d: float) -> void:
		if _v != ItemIcons.version:
			_v = ItemIcons.version
			queue_redraw()

	func _draw() -> void:
		var ok := have >= need
		var r := Rect2(Vector2(0, 2), Vector2(size.y - 4, size.y - 4))
		ItemStyle.draw_slot(self, r, ItemDB.rarity(item), false, false, false, not ok)
		ItemStyle.draw_item(self, r.grow(-3), item)
		draw_string(UiTheme.MONO, Vector2(r.end.x + 12, size.y * 0.5 + 5), label, HORIZONTAL_ALIGNMENT_LEFT, size.x - r.end.x - 120, 13, ItemStyle.TEXT if ok else ItemStyle.TEXT_DIM)
		var t := "%d / %d" % [have, need]
		var f := UiTheme.MONO_BOLD
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(f, Vector2(size.x - w - 30, size.y * 0.5 + 5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ItemStyle.GOOD if ok else ItemStyle.BAD)
		var c := Vector2(size.x - 12, size.y * 0.5)
		if ok:
			draw_polyline(PackedVector2Array([c + Vector2(-5, 0), c + Vector2(-1, 4), c + Vector2(6, -5)]), ItemStyle.GOOD, 2.0, true)
		else:
			draw_line(c + Vector2(-4, -4), c + Vector2(4, 4), ItemStyle.BAD, 2.0, true)
			draw_line(c + Vector2(-4, 4), c + Vector2(4, -4), ItemStyle.BAD, 2.0, true)


## Progress bar: molten fill with a flickering hot edge (furnace), steel
## sparks (anvil), or a calm amber fill.
class CraftProgress:
	extends Control
	var value := 0.0:
		set(v):
			value = v
			queue_redraw()
	var active := false:
		set(v):
			active = v
			queue_redraw()
	var kind := ""
	var label := ""
	var _flash := 0.0
	var _t := 0.0

	func flash() -> void:
		_flash = 1.0

	func _process(delta: float) -> void:
		_t += delta
		if _flash > 0.0:
			_flash = maxf(0.0, _flash - delta * 2.5)
		if active or _flash > 0.0:
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		ItemStyle.draw_well(self, r)
		if not active and _flash <= 0.0:
			draw_string(UiTheme.MONO, Vector2(10, size.y * 0.5 + 4), "Ready", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ItemStyle.TEXT_FAINT)
			return
		var fill := Rect2(r.position + Vector2(2, 2), Vector2((r.size.x - 4) * value, r.size.y - 4))
		var hot := Color(1.0, 0.62, 0.2)
		var cool := Color(0.55, 0.12, 0.04)
		if kind == "alchemy":
			hot = Color(0.6, 0.85, 1.0)
			cool = Color(0.2, 0.15, 0.5)
		elif kind == "anvil" or kind == "smithy":
			hot = Color(1.0, 0.85, 0.55)
			cool = Color(0.45, 0.2, 0.08)
		ItemStyle.hgradient(self, fill, cool, hot)
		# Rippling heat shimmer along the fill.
		for i in int(fill.size.x / 6.0):
			var x := fill.position.x + i * 6.0
			var a := 0.08 + 0.08 * sin(_t * 6.0 + i * 0.7)
			draw_line(Vector2(x, fill.position.y + 1), Vector2(x, fill.end.y - 1), Color(1, 1, 1, a), 1.0)
		if fill.size.x > 2.0:
			var edge := Vector2(fill.end.x, size.y * 0.5)
			draw_texture_rect(ItemStyle.radial(), Rect2(edge - Vector2(16, 16), Vector2(32, 32)), false, Color(hot.r, hot.g, hot.b, 0.8))
		if _flash > 0.0:
			draw_rect(r, Color(1.0, 0.85, 0.5, _flash * 0.35))
		ItemStyle.outlined(self, UiTheme.MONO_BOLD, Vector2(10, size.y * 0.5 + 5), label, 12, ItemStyle.TEXT)
