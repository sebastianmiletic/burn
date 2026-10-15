class_name InventoryScreen
extends UiModal
## Character and pack. Left: the paper doll (live 3D character wearing the
## armour, four armour slots) and attributes. Middle: the three held slots
## and the 30-slot pack. Right: gold and crafting by hand.
##
## Mouse: drag & drop anywhere (gems dropped on gear are set into it), click
## two slots to swap, Shift+click to move between pack / hand / armour,
## right-click to use, wear or take in hand. Hover for the item card with a
## comparison against what you use now. C opens the crafting book.

const COLUMNS := 6
const HELD := Inventory.HOTBAR
const SLOT := 64.0

var _slots: Array[ItemSlot] = []
var _by_index := {}
var _marked := -1
var _focus := -1
var _tooltip: ItemTooltip
var _preview: ItemPreview
var _stats: RichTextLabel
var _gold: Label
var _hand_list: VBoxContainer
var _status: Label
var _use_btn: Button
var _drop_btn: Button
var _status_time := 0.0


func _init() -> void:
	panel_size = Vector2(1220, 720)
	panel_title = ""


func _build() -> void:
	ItemStyle.dress(self, "INVENTORY")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	row.add_child(_build_character())
	row.add_child(_build_pack())
	row.add_child(_build_side())
	_tooltip = ItemTooltip.new()
	add_child(_tooltip)
	UiContext.on("inventory_changed", func() -> void:
		if is_open:
			_refresh())
	_install_crafting.call_deferred()


func _install_crafting() -> void:
	CraftingScreen.ensure(self)


# --- Layout ------------------------------------------------------------------------------

func _build_character() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(340, 0)
	col.add_theme_constant_override("separation", 8)
	col.add_child(ItemStyle.header("CHARACTER"))
	var well := ItemStyle.well(10)
	well.accent = Color(1.0, 0.55, 0.2, 0.12)
	col.add_child(well)
	var doll := HBoxContainer.new()
	doll.add_theme_constant_override("separation", 6)
	well.add_child(doll)
	var eq := VBoxContainer.new()
	eq.add_theme_constant_override("separation", 10)
	eq.alignment = BoxContainer.ALIGNMENT_CENTER
	doll.add_child(eq)
	var ghosts := {"head": "helmet_iron", "chest": "chestplate_iron", "legs": "greaves_iron", "feet": "boots_iron"}
	for s: String in Inventory.EQUIP_SLOTS:
		var slot := _make_slot(Inventory.equip_index(s), "")
		slot.ghost = ghosts[s]
		slot.caption = s.to_upper()
		eq.add_child(slot)
	_preview = ItemPreview.new()
	_preview.mode = ItemPreview.Mode.CHARACTER
	_preview.custom_minimum_size = Vector2(230, 300)
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doll.add_child(_preview)
	col.add_child(ItemStyle.header("ATTRIBUTES"))
	var sw := ItemStyle.well(12)
	sw.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sw)
	_stats = RichTextLabel.new()
	_stats.bbcode_enabled = true
	_stats.fit_content = true
	_stats.scroll_active = false
	_stats.add_theme_font_size_override("normal_font_size", 13)
	_stats.add_theme_font_override("normal_font", UiTheme.MONO)
	_stats.add_theme_font_override("bold_font", UiTheme.MONO_BOLD)
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sw.add_child(_stats)
	return col


func _build_pack() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(COLUMNS * SLOT + (COLUMNS - 1) * 8 + 24, 0)
	col.add_child(ItemStyle.header("IN HAND  ·  1  2  3"))
	var hw := ItemStyle.well(12)
	col.add_child(hw)
	var held := HBoxContainer.new()
	held.add_theme_constant_override("separation", 12)
	held.alignment = BoxContainer.ALIGNMENT_CENTER
	hw.add_child(held)
	for i in HELD:
		var s := _make_slot(i, str(i + 1))
		s.custom_minimum_size = Vector2(76, 76)
		held.add_child(s)
	col.add_child(ItemStyle.header("PACK"))
	var pw := ItemStyle.well(12)
	col.add_child(pw)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	pw.add_child(grid)
	for i in range(HELD, HELD + Inventory.BAG):
		grid.add_child(_make_slot(i, ""))
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 8)
	_use_btn = ItemStyle.button("Use", func() -> void: _use(_focus))
	_drop_btn = ItemStyle.button("Drop", func() -> void: _drop(_focus))
	acts.add_child(_use_btn)
	acts.add_child(_drop_btn)
	acts.add_child(ItemStyle.button("Sort pack", _sort))
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acts.add_child(spring)
	col.add_child(acts)
	_status = UiTheme.label("", 12, ItemStyle.TEXT_DIM)
	col.add_child(_status)
	var hint := UiTheme.label("drag to move · drop a gem on gear to socket it · shift-click to send · right-click to use or wear", 11, ItemStyle.TEXT_FAINT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 420
	col.add_child(hint)
	return col


func _build_side() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gw := ItemStyle.well(10)
	gw.accent = Color(1.0, 0.8, 0.3, 0.15)
	col.add_child(gw)
	var gold_row := HBoxContainer.new()
	gw.add_child(gold_row)
	gold_row.add_child(UiTheme.label("PURSE", 12, ItemStyle.TEXT_DIM))
	_gold = UiTheme.label("", 22, Color(1.0, 0.84, 0.45), HORIZONTAL_ALIGNMENT_RIGHT)
	_gold.add_theme_font_override("font", ItemStyle.title_font(700))
	_gold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gold_row.add_child(_gold)
	col.add_child(ItemStyle.header("CRAFT BY HAND"))
	var lw := ItemStyle.well(4)
	lw.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(lw)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lw.add_child(scroll)
	_hand_list = VBoxContainer.new()
	_hand_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hand_list.add_theme_constant_override("separation", 0)
	scroll.add_child(_hand_list)
	var book := ItemStyle.button("Crafting book  [C]", _open_book, true)
	col.add_child(book)
	var hint := UiTheme.label("Workbench, furnace, anvil and alchemy recipes open when you use the station.", 11, ItemStyle.TEXT_FAINT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)
	return col


func _make_slot(i: int, key: String) -> ItemSlot:
	var s := ItemSlot.new()
	s.index = i
	s.key_hint = key
	s.draggable = true
	s.custom_minimum_size = Vector2(SLOT, SLOT)
	s.clicked.connect(_on_click)
	s.hovered.connect(_on_hover)
	s.unhovered.connect(func(_i: int) -> void: _tooltip.hide_tip())
	s.dropped_on.connect(func(a: int, b: int) -> void: _move(a, b))
	s.accept = _can_move
	_slots.append(s)
	_by_index[i] = s
	return s


# --- Refresh -------------------------------------------------------------------------------

func _on_open() -> void:
	_marked = -1
	_tooltip.hide_tip()
	ItemIcons.prewarm()
	_refresh()


func _inv() -> Inventory:
	return UiContext.inventory() as Inventory


func _refresh() -> void:
	var inv := _inv()
	var sel := inv.selected if inv != null else -1
	for s in _slots:
		var item: Dictionary = inv.get_slot(s.index) if inv != null else {}
		s.item = item.duplicate()
		s.selected = s.index == sel
		s.marked = s.index == _marked
	_gold.text = "%s  ◎" % UiTheme.format_int(inv.gold if inv != null else 0)
	if inv != null:
		_preview.show_character(inv.equipment, inv.selected_item())
	_refresh_stats(inv)
	_refresh_hand(inv)
	_refresh_actions()


func _refresh_stats(inv: Inventory) -> void:
	if inv == null:
		_stats.text = ""
		return
	var a := inv.attack_stats()
	var held := inv.selected_item()
	var lines := PackedStringArray()
	var dim := ItemStyle.TEXT_DIM.to_html(false)
	lines.append("[color=#%s]Attack      [/color][b]%.1f[/b]  [color=#%s]× %.2f/s · %.1f m[/color]" % [dim, float(a["damage"]), dim, float(a["speed"]), float(a["reach"])])
	lines.append("[color=#%s]Defence     [/color][b]%.0f[/b]  [color=#%s](blocks %d%%)[/color]" % [dim, inv.defense(), dim, int(round(inv.damage_reduction() * 100.0))])
	if inv.fire_resist() > 0.0:
		lines.append("[color=#%s]Fire resist [/color][b]%d%%[/b]" % [dim, int(inv.fire_resist() * 100.0)])
	var inf := ItemDB.info(held)
	if inf.has("mine_tier"):
		lines.append("[color=#%s]Mining      [/color][b]%s[/b]  [color=#%s]×%.1f[/color]" % [dim, ItemDB.MINE_TIER_LABELS[clampi(int(inf["mine_tier"]), 0, 7)], dim, float(inf.get("mine_speed", 1.0))])
	if float(a["burn"]) > 0.0:
		lines.append("[color=#%s]Burn        [/color][b]%d / s[/b]" % [dim, int(a["burn"])])
	for b: String in ["ironskin", "might"]:
		if inv.buff_active(b):
			lines.append("[color=#%s]✦ %s  %ds[/color]" % [Color(0.7, 0.6, 1.0).to_html(false), b.capitalize(), int(inv.buff_remaining(b))])
	_stats.text = "\n".join(lines)


func _refresh_hand(inv: Inventory) -> void:
	for c in _hand_list.get_children():
		_hand_list.remove_child(c)
		c.queue_free()
	for rid: String in ItemDB.recipes_for_station(""):
		var row := RecipeRow.new()
		row.recipe_id = rid
		row.inventory = inv
		row.quick = true
		row.pressed.connect(_craft_hand)
		row.hovered.connect(func(id: String, rr: RecipeRow) -> void:
			_tooltip.show_item({"id": ItemDB.recipe_result(id), "count": int(ItemDB.recipe(id).get("count", 1))}, rr.get_global_rect()))
		row.unhovered.connect(func(_id: String) -> void: _tooltip.hide_tip())
		_hand_list.add_child(row)


func _refresh_actions() -> void:
	var inv := _inv()
	var item: Dictionary = inv.get_slot(_focus) if inv != null and _focus >= 0 else {}
	_use_btn.disabled = item.is_empty()
	_drop_btn.disabled = item.is_empty() or ItemDB.category(String(item.get("id", ""))) == "key"
	if item.is_empty():
		_use_btn.text = "Use"
		return
	var id := String(item["id"])
	var cat := ItemDB.category(id)
	if Inventory.is_equip_index(_focus):
		_use_btn.text = "Take off"
	elif cat == "armor":
		_use_btn.text = "Wear"
	elif cat == "consumable":
		_use_btn.text = "Use"
	elif _focus >= HELD:
		_use_btn.text = "Hold"
	else:
		_use_btn.text = "In hand"
		_use_btn.disabled = true


func _process(delta: float) -> void:
	if _status_time > 0.0:
		_status_time -= delta
		if _status_time <= 0.0:
			_status.text = ""


func _say(text: String, good := true) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", ItemStyle.GOOD if good else ItemStyle.BAD)
	_status_time = 3.0


# --- Interaction -----------------------------------------------------------------------------

func _on_hover(i: int) -> void:
	var inv := _inv()
	if inv == null:
		return
	var item := inv.get_slot(i)
	if item.is_empty():
		_tooltip.hide_tip()
		return
	_tooltip.show_item(item, (_by_index[i] as Control).get_global_rect(), compare_for(inv, i))


## What to compare the item in slot `i` with: the worn piece for armour, the
## item in hand for weapons and tools.
static func compare_for(inv: Inventory, i: int) -> Dictionary:
	var item := inv.get_slot(i)
	var id := String(item.get("id", ""))
	var cat := ItemDB.category(id)
	if cat == "armor":
		var ei := Inventory.equip_index(ItemDB.equip_slot(id))
		return {} if ei == i else inv.get_slot(ei)
	if cat == "weapon" or cat == "tool":
		if i == inv.selected:
			return {}
		var held := inv.get_slot(inv.selected)
		return held if ItemDB.is_gear(String(held.get("id", ""))) else {}
	return {}


func _on_click(i: int, button: int) -> void:
	var inv := _inv()
	if inv == null:
		return
	_focus = i
	if button == MOUSE_BUTTON_RIGHT:
		_use(i)
		return
	if Input.is_key_pressed(KEY_SHIFT):
		_quick_move(i)
		return
	if _marked < 0:
		if not inv.get_slot(i).is_empty():
			_marked = i
			UiContext.sound("ui_click")
	elif _marked == i:
		_marked = -1
	else:
		_move(_marked, i)
		_marked = -1
	_refresh()


func _can_move(a: int, b: int) -> bool:
	var inv := _inv()
	if inv == null or a == b:
		return false
	var sa := inv.get_slot(a)
	var sb := inv.get_slot(b)
	if not sa.is_empty() and not sb.is_empty() and ItemDB.can_socket(String(sa["id"]), String(sb["id"])):
		return true
	return inv.accepts(b, sa) and inv.accepts(a, sb)


func _move(a: int, b: int) -> void:
	var inv := _inv()
	if inv == null or a == b:
		return
	var sa := inv.get_slot(a)
	var sb := inv.get_slot(b)
	if not sa.is_empty() and not sb.is_empty() and ItemDB.can_socket(String(sa["id"]), String(sb["id"])):
		var replaced := String(sb.get("gem", ""))
		if inv.socket(a, b):
			UiContext.sound("equip")
			_say("Set %s into %s.%s" % [ItemDB.display_name(sa["id"]), ItemDB.display_name(sb["id"]), (" The old %s shattered." % ItemDB.display_name(replaced)) if replaced != "" else ""])
	elif inv.swap(a, b):
		UiContext.sound("equip" if Inventory.is_equip_index(a) or Inventory.is_equip_index(b) else "ui_click")
	else:
		UiContext.sound("ui_back")
		_say("That doesn't go there.", false)
	_focus = b
	_refresh()


func _quick_move(i: int) -> void:
	var inv := _inv()
	var id := String(inv.get_slot(i).get("id", ""))
	if Inventory.is_equip_index(i):
		inv.unequip(Inventory.EQUIP_SLOTS[i - Inventory.EQUIP_BASE])
	elif ItemDB.category(id) == "armor":
		inv.equip_from(i)
		UiContext.sound("equip")
	else:
		var target_range := range(HELD, HELD + Inventory.BAG) if i < HELD else range(0, HELD)
		var done := false
		for j: int in target_range:
			if inv.get_slot(j).is_empty():
				inv.swap(i, j)
				done = true
				break
		if not done:
			inv.swap(i, target_range[0] if i >= HELD else HELD)
		UiContext.sound("ui_click")
	_refresh()


func _use(i: int) -> void:
	var inv := _inv()
	if i < 0 or inv == null:
		return
	var item := inv.get_slot(i)
	if item.is_empty():
		return
	var id := String(item["id"])
	var cat := ItemDB.category(id)
	if Inventory.is_equip_index(i):
		if not inv.unequip(Inventory.EQUIP_SLOTS[i - Inventory.EQUIP_BASE]):
			_say("No room in your pack.", false)
		UiContext.sound("equip")
	elif cat == "armor":
		inv.equip_from(i)
		UiContext.sound("equip")
		_say("You put on the %s." % ItemDB.display_name(id))
	elif cat == "consumable":
		var p := UiContext.player()
		if ItemDB.info(id).has("heal") or (p != null and p.has_method("use_consumable")):
			UiContext.call_on(p, "use_consumable" if p != null and p.has_method("use_consumable") else "use_item_slot", [i])
		else:
			# Buff draughts until the Player handles them itself.
			inv.apply_consumable(id)
			inv.remove_from_slot(i, 1)
			UiContext.sound("potion")
			_say("You drink the %s." % ItemDB.display_name(id))
	elif i >= HELD:
		# Tools, weapons, lights, blocks: take it in hand.
		inv.swap(i, inv.selected)
		UiContext.sound("equip")
	_refresh()


func _drop(i: int) -> void:
	if i < 0:
		return
	UiContext.call_on(UiContext.player(), "drop_slot", [i])
	_tooltip.hide_tip()
	_refresh()


func _sort() -> void:
	var inv := _inv()
	if inv != null:
		inv.sort_bag()
		_say("Pack sorted.")
	_refresh()


func _craft_hand(rid: String) -> void:
	var inv := _inv()
	if inv == null:
		return
	var miss := ItemDB.missing_for(rid, inv)
	if not miss.is_empty():
		UiContext.sound("ui_back")
		var parts := PackedStringArray()
		for k: String in miss:
			parts.append("%d %s" % [miss[k], ItemDB.display_name(k) if ItemDB.exists(k) else k])
		_say("Missing " + ", ".join(parts) + ".", false)
		return
	var ok: bool = UiContext.call_on(UiContext.player(), "craft", [rid], false)
	if ok:
		_say("Crafted %s." % ItemDB.display_name(ItemDB.recipe_result(rid)))
	else:
		_say("Could not craft that.", false)
	_refresh()


func _open_book() -> void:
	close()
	UiContext.emit_event("station_open", ["", null])


func _unhandled_input(event: InputEvent) -> void:
	if is_open and event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_C:
		_open_book()
		get_viewport().set_input_as_handled()
		return
	super(event)


## Gallery hook: show the tooltip for a slot as if hovered.
func debug_hover(i: int) -> void:
	_focus = i
	_refresh_actions()
	_on_hover(i)


## A compact plain-text stats block for any item (also used by tests and the shop).
static func item_stats(id: String) -> String:
	var info := ItemDB.info(id)
	var lines := PackedStringArray()
	if info.has("damage"):
		lines.append("damage      %.1f" % float(info["damage"]))
	if info.has("speed"):
		lines.append("speed       %.2f" % float(info["speed"]))
	if info.has("reach"):
		lines.append("reach       %.1f m" % float(info["reach"]))
	if info.has("burn"):
		lines.append("burn        %d / s" % int(info["burn"]))
	if info.has("mine_tier") and String(info.get("kind", "")) == "pickaxe":
		lines.append("mining tier %s" % ItemDB.MINE_TIER_LABELS[clampi(int(info["mine_tier"]), 0, 7)])
	if info.has("mine_speed"):
		lines.append("mining      ×%.1f" % float(info["mine_speed"]))
	if info.has("defense"):
		lines.append("defence     %.1f" % float(info["defense"]))
	if info.has("heal"):
		lines.append("restores    %d hp" % int(info["heal"]))
	if info.has("place_block") or info.has("place_station"):
		lines.append("placeable   right-click")
	if int(info.get("value", 0)) > 0:
		lines.append("worth       %d gold" % int(info["value"]))
	return "\n".join(lines)
