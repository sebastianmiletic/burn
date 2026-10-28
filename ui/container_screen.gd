class_name ContainerScreen
extends UiModal
## A chest, barrel or loot chest opened with E: its grid on the left, the
## player's hands and pack on the right (BuildingWorld holds the contents; the
## server owns them and pushes every change to everyone looking in).
##
## Drag & drop between and within the grids; Shift+click (or double-click)
## sends a stack across; right-click moves half a stack. Take all, Deposit
## all (the pack, never the three held slots) and Sort. E or Esc closes.

const COLUMNS := 6
const SLOT := 60.0
const BOX := 1000      ## container slot i is ItemSlot index BOX + i

var _box_grid: GridContainer
var _box_slots: Array[ItemSlot] = []
var _pack_slots: Array[ItemSlot] = []
var _title: Label
var _count: Label
var _tooltip: ItemTooltip
var _built_for := -1


func _init() -> void:
	panel_size = Vector2(1060, 640)
	panel_title = ""


func _ready() -> void:
	super._ready()
	add_to_group(&"container_screen")


func _build() -> void:
	ItemStyle.dress(self, "STORAGE")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	# Left: the container.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.custom_minimum_size = Vector2(COLUMNS * SLOT + (COLUMNS - 1) * 8 + 24, 0)
	row.add_child(left)
	var head := HBoxContainer.new()
	left.add_child(head)
	_title = UiTheme.label("", 18, ItemStyle.GOLD)
	_title.add_theme_font_override("font", ItemStyle.title_font(700))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_count = UiTheme.label("", 12, ItemStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	head.add_child(_count)
	var bw := ItemStyle.well(12)
	bw.accent = Color(1.0, 0.7, 0.3, 0.1)
	left.add_child(bw)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 4 * SLOT + 3 * 8 + 4)
	bw.add_child(scroll)
	_box_grid = GridContainer.new()
	_box_grid.columns = COLUMNS
	_box_grid.add_theme_constant_override("h_separation", 8)
	_box_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_box_grid)
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 8)
	acts.add_child(ItemStyle.button("Take all", _take_all, true))
	acts.add_child(ItemStyle.button("Deposit all", _deposit_all))
	acts.add_child(ItemStyle.button("Sort", _sort))
	left.add_child(acts)
	var hint := UiTheme.label("drag to move · shift-click to send across · right-click moves half · E or Esc closes", 11, ItemStyle.TEXT_FAINT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 380
	left.add_child(hint)
	# Right: hands and pack.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	right.add_child(ItemStyle.header("IN HAND"))
	var hw := ItemStyle.well(10)
	right.add_child(hw)
	var held := HBoxContainer.new()
	held.add_theme_constant_override("separation", 10)
	hw.add_child(held)
	for i in Inventory.HOTBAR:
		held.add_child(_make_slot(i, str(i + 1)))
	right.add_child(ItemStyle.header("PACK"))
	var pw := ItemStyle.well(10)
	right.add_child(pw)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	pw.add_child(grid)
	for i in range(Inventory.HOTBAR, Inventory.HOTBAR + Inventory.BAG):
		grid.add_child(_make_slot(i, ""))
	_tooltip = ItemTooltip.new()
	add_child(_tooltip)
	UiContext.on("inventory_changed", func() -> void:
		if is_open:
			_refresh())


func _make_slot(i: int, key: String) -> ItemSlot:
	var s := ItemSlot.new()
	s.index = i
	s.key_hint = key
	s.draggable = true
	s.custom_minimum_size = Vector2(SLOT, SLOT)
	s.clicked.connect(_on_click)
	s.hovered.connect(_on_hover)
	s.unhovered.connect(func(_i: int) -> void: _tooltip.hide_tip())
	s.dropped_on.connect(_on_drop)
	if i < BOX:
		_pack_slots.append(s)
	else:
		_box_slots.append(s)
	return s


func _building() -> BuildingWorld:
	var w := UiContext.world() as GameWorld
	return w.building if w != null else null


func _inv() -> Inventory:
	return UiContext.inventory() as Inventory


## Called by BuildingWorld when contents arrive for a newly opened container.
func open_container() -> void:
	var b := _building()
	if b == null:
		return
	if not b.container_changed.is_connected(_refresh):
		b.container_changed.connect(_refresh)
	open()


func _on_open() -> void:
	ItemIcons.prewarm()
	_tooltip.hide_tip()
	_refresh()


func close() -> void:
	if not is_open:
		return
	super.close()
	_tooltip.hide_tip()
	var b := _building()
	if b != null and b.open_key != "":
		b.close_container()


func _refresh() -> void:
	var b := _building()
	if b == null or b.open_key == "":
		if is_open:
			close()
		return
	var n := b.open_slots.size()
	if n != _built_for:
		_built_for = n
		for s in _box_slots:
			s.queue_free()
		_box_slots.clear()
		for i in n:
			_box_grid.add_child(_make_slot(BOX + i, ""))
	var used := 0
	for i in _box_slots.size():
		var item: Dictionary = b.open_slots[i] if i < n else {}
		_box_slots[i].item = item.duplicate()
		if not item.is_empty():
			used += 1
	_title.text = b.open_title.to_upper()
	_count.text = "%d / %d" % [used, n]
	var inv := _inv()
	for s in _pack_slots:
		s.item = inv.get_slot(s.index).duplicate() if inv != null else {}
		s.selected = inv != null and s.index == inv.selected


func _on_hover(i: int) -> void:
	var item := _item_at(i)
	if item.is_empty():
		_tooltip.hide_tip()
		return
	var slot: ItemSlot = _box_slots[i - BOX] if i >= BOX else _pack_slots[_pack_index(i)]
	_tooltip.show_item(item, slot.get_global_rect())


func _pack_index(i: int) -> int:
	for k in _pack_slots.size():
		if _pack_slots[k].index == i:
			return k
	return 0


func _item_at(i: int) -> Dictionary:
	var b := _building()
	if i >= BOX:
		return b.open_slots[i - BOX] if b != null and i - BOX < b.open_slots.size() else {}
	var inv := _inv()
	return inv.get_slot(i) if inv != null else {}


func _on_click(i: int, button: int) -> void:
	var b := _building()
	var inv := _inv()
	if b == null or inv == null or _item_at(i).is_empty():
		return
	var count := int(_item_at(i).get("count", 1))
	if button == MOUSE_BUTTON_RIGHT:
		var half := maxi(1, count / 2)
		if i >= BOX:
			b.take(i - BOX, half)
		else:
			b.put(i, -1, half)
		UiContext.sound("ui_click")
	elif Input.is_key_pressed(KEY_SHIFT):
		if i >= BOX:
			b.take(i - BOX)
		else:
			b.put(i)
		UiContext.sound("ui_click")


func _on_drop(from: int, to: int) -> void:
	var b := _building()
	var inv := _inv()
	if b == null or inv == null or from == to:
		return
	if from >= BOX and to >= BOX:
		b.move(from - BOX, to - BOX)
	elif from >= BOX:
		b.take(from - BOX, -1, to if inv.get_slot(to).is_empty() else -1)
	elif to >= BOX:
		b.put(from, to - BOX)
	else:
		inv.swap(from, to)
	UiContext.sound("ui_click")


func _take_all() -> void:
	var b := _building()
	if b != null:
		b.take_all()
		UiContext.sound("pickup")


func _deposit_all() -> void:
	var b := _building()
	if b != null:
		b.deposit_all()
		UiContext.sound("ui_click")


func _sort() -> void:
	var b := _building()
	if b != null:
		b.sort_container()
		UiContext.sound("ui_click")


func _unhandled_input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)
