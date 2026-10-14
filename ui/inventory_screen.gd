class_name InventoryScreen
extends UiModal
## Held items (3) and the pack (24). Drag & drop or click two slots to swap,
## Shift+click moves between held and pack, right-click uses an item.

const COLUMNS := 6
const HELD := 3

var _slots: Array[ItemSlot] = []
var _marked := -1
var _detail_glyph: Label
var _detail_name: Label
var _detail_kind: Label
var _detail_desc: Label
var _detail_stats: Label
var _gold: Label
var _use_btn: Button
var _drop_btn: Button
var _focus := -1


func _init() -> void:
	panel_size = Vector2(820, 500)
	panel_title = "INVENTORY"


func _build() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	left.add_child(UiTheme.label("HELD  ·  keys 1 2 3", UiTheme.SIZE_SMALL, UiTheme.ACCENT_DIM))
	var held := HBoxContainer.new()
	held.add_theme_constant_override("separation", 6)
	left.add_child(held)
	for i in HELD:
		held.add_child(_make_slot(i, str(i + 1)))
	left.add_child(UiTheme.spacer(6))
	left.add_child(UiTheme.label("PACK", UiTheme.SIZE_SMALL, UiTheme.ACCENT_DIM))
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	left.add_child(grid)
	for i in range(HELD, HELD + 24):
		grid.add_child(_make_slot(i, ""))
	left.add_child(UiTheme.spacer(4))
	left.add_child(UiTheme.label("drag or click two slots to swap · shift-click to move · right-click to use", 11, UiTheme.TEXT_FAINT))

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(300, 0)
	right.add_theme_constant_override("separation", 6)
	row.add_child(right)
	_detail_glyph = UiTheme.label("", 44, UiTheme.ACCENT)
	_detail_glyph.add_theme_font_override("font", UiTheme.MONO_BOLD)
	right.add_child(_detail_glyph)
	_detail_name = UiTheme.title("", 22, UiTheme.ACCENT_HOT, 700)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD
	right.add_child(_detail_name)
	_detail_kind = UiTheme.label("", UiTheme.SIZE_SMALL, UiTheme.ACCENT_DIM)
	right.add_child(_detail_kind)
	_detail_desc = UiTheme.label("", UiTheme.SIZE_BODY, UiTheme.TEXT)
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	_detail_desc.custom_minimum_size.x = 300
	right.add_child(_detail_desc)
	_detail_stats = UiTheme.label("", UiTheme.SIZE_SMALL, UiTheme.TEXT_DIM)
	right.add_child(_detail_stats)
	var spring := Control.new()
	spring.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spring)
	var acts := HBoxContainer.new()
	_use_btn = UiTheme.button("Use", func() -> void: _use(_focus))
	_drop_btn = UiTheme.button("Drop", func() -> void: _drop(_focus))
	acts.add_child(_use_btn)
	acts.add_child(_drop_btn)
	right.add_child(acts)
	right.add_child(UiTheme.hsep())
	_gold = UiTheme.label("", UiTheme.SIZE_LARGE, Color(1.0, 0.85, 0.4))
	right.add_child(_gold)
	UiContext.on("inventory_changed", func() -> void:
		if is_open:
			_refresh())


func _make_slot(i: int, key: String) -> ItemSlot:
	var s := ItemSlot.new()
	s.index = i
	s.key_hint = key
	s.draggable = true
	s.custom_minimum_size = Vector2(58, 58)
	s.clicked.connect(_on_click)
	s.hovered.connect(_show_detail)
	s.dropped_on.connect(func(a: int, b: int) -> void: _swap(a, b))
	_slots.append(s)
	return s


func _on_open() -> void:
	_marked = -1
	_refresh()
	_show_detail(UiContext.inventory().get("selected") if UiContext.inventory() != null else 0)


func _refresh() -> void:
	var inv := UiContext.inventory()
	var sel := int(inv.get("selected")) if inv != null else -1
	for s in _slots:
		var item: Dictionary = UiContext.call_on(inv, "get_slot", [s.index], {})
		s.item = item.duplicate()
		s.selected = s.index == sel
		s.marked = s.index == _marked
	_gold.text = "◎  %s gold" % UiTheme.format_int(int(inv.get("gold")) if inv != null else 0)
	_show_detail(_focus if _focus >= 0 else 0)


func _on_click(i: int, button: int) -> void:
	var inv := UiContext.inventory()
	if inv == null:
		return
	if button == MOUSE_BUTTON_RIGHT:
		_use(i)
		return
	if Input.is_key_pressed(KEY_SHIFT):
		_quick_move(i)
		return
	if _marked < 0:
		var item: Dictionary = inv.call("get_slot", i)
		if not item.is_empty():
			_marked = i
			UiContext.sound("ui_click")
	elif _marked == i:
		_marked = -1
	else:
		_swap(_marked, i)
		_marked = -1
	_refresh()


func _swap(a: int, b: int) -> void:
	var inv := UiContext.inventory()
	if inv == null or a == b:
		return
	inv.call("swap", a, b)
	UiContext.sound("ui_click")
	_focus = b
	_refresh()


func _quick_move(i: int) -> void:
	var inv := UiContext.inventory()
	var target_range := range(HELD, HELD + 24) if i < HELD else range(0, HELD)
	for j: int in target_range:
		var item: Dictionary = inv.call("get_slot", j)
		if item.is_empty():
			_swap(i, j)
			return
	# No empty slot: swap with the first one of the other area.
	_swap(i, target_range[0])


func _use(i: int) -> void:
	if i < 0:
		return
	var p := UiContext.player()
	var inv := UiContext.inventory()
	var item: Dictionary = UiContext.call_on(inv, "get_slot", [i], {})
	if item.is_empty():
		return
	var cat := ItemDB.category(item["id"])
	if cat == "consumable":
		UiContext.call_on(p, "use_item_slot", [i])
	elif i >= HELD:
		# Tools, weapons, lights and blocks: "use" means take it in hand.
		_quick_move(i)
	_refresh()


func _drop(i: int) -> void:
	if i < 0:
		return
	UiContext.call_on(UiContext.player(), "drop_slot", [i])
	_refresh()


func _show_detail(i: int) -> void:
	_focus = i
	var inv := UiContext.inventory()
	var item: Dictionary = UiContext.call_on(inv, "get_slot", [i], {})
	if item.is_empty():
		_detail_glyph.text = ""
		_detail_name.text = "Empty slot" if i >= 0 else ""
		_detail_kind.text = ""
		_detail_desc.text = "Drag an item here, or click two slots to swap them."
		_detail_stats.text = ""
		_use_btn.disabled = true
		_drop_btn.disabled = true
		return
	var id: String = item["id"]
	var info := ItemDB.info(id)
	_detail_glyph.text = ItemDB.glyph(id)
	_detail_glyph.add_theme_color_override("font_color", ItemDB.color(id))
	_detail_name.text = ItemDB.display_name(id)
	_detail_kind.text = "%s%s" % [ItemDB.category(id).to_upper(), "  ×%d" % int(item.get("count", 1)) if int(item.get("count", 1)) > 1 else ""]
	_detail_desc.text = str(info.get("desc", ""))
	_detail_stats.text = item_stats(id)
	var cat := ItemDB.category(id)
	_use_btn.disabled = false
	_use_btn.text = "Use" if cat == "consumable" else ("Hold" if i >= HELD else "In hand")
	_use_btn.disabled = cat != "consumable" and i < HELD
	_drop_btn.disabled = cat == "key"


## A compact stats block for any item (also used by the shop).
static func item_stats(id: String) -> String:
	var info := ItemDB.info(id)
	var lines := PackedStringArray()
	if info.has("damage"):
		lines.append("damage      %d" % int(info["damage"]))
	if info.has("speed"):
		lines.append("speed       %.1f" % float(info["speed"]))
	if info.has("reach"):
		lines.append("reach       %.1f m" % float(info["reach"]))
	if info.has("burn"):
		lines.append("burn        %d / s" % int(info["burn"]))
	if info.has("mine_tier"):
		lines.append("mining tier %s" % ["wood", "stone", "iron", "obsidian"][clampi(int(info["mine_tier"]), 0, 3)])
	if info.has("mine_speed"):
		lines.append("mining      ×%.1f" % float(info["mine_speed"]))
	if info.has("heal"):
		lines.append("restores    %d hp" % int(info["heal"]))
	if info.has("place_block"):
		lines.append("placeable   right-click")
	if int(info.get("value", 0)) > 0:
		lines.append("worth       %d gold" % int(info["value"]))
	return "\n".join(lines)
