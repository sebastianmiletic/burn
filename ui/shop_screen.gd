class_name ShopScreen
extends UiModal
## Blacksmith forge (recipes) and merchant (buy / sell), opened by
## Events.shop_open(kind).

var kind := "merchant"
var _tabs: TabContainer
var _gold: Label
var _status: Label


func _init() -> void:
	panel_size = Vector2(820, 540)
	panel_title = "TRADE"


func _build() -> void:
	var head := HBoxContainer.new()
	_status = UiTheme.label("", UiTheme.SIZE_BODY, UiTheme.TEXT_DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_status)
	_gold = UiTheme.label("", UiTheme.SIZE_LARGE, Color(1.0, 0.85, 0.4), HORIZONTAL_ALIGNMENT_RIGHT)
	head.add_child(_gold)
	content.add_child(head)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_tabs)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_child(UiTheme.button("Leave  [Esc]", close))
	content.add_child(foot)
	UiContext.on("shop_open", open_shop)
	UiContext.on("inventory_changed", func() -> void:
		if is_open:
			_rebuild(_tabs.current_tab))


func open_shop(shop_kind: String) -> void:
	kind = shop_kind
	frame.title = "THE FORGE" if kind == "blacksmith" else "MERCHANT"
	open()


func _on_open() -> void:
	_status.text = "Iron, ember and bone, shaped to your need." if kind == "blacksmith" else "Coin for comfort. Comfort for coin."
	_rebuild(0)


func _rebuild(tab := 0) -> void:
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	var inv := UiContext.inventory()
	_gold.text = "◎ %s" % UiTheme.format_int(int(inv.get("gold")) if inv != null else 0)
	if kind == "blacksmith":
		_build_forge(inv)
	else:
		_build_buy(inv)
		_build_sell(inv)
	_tabs.current_tab = clampi(tab, 0, _tabs.get_tab_count() - 1)


func _list(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	scroll.add_child(box)
	_tabs.add_child(scroll)
	return box


func _item_row(parent: Control, id: String, sub: String, action: String, enabled: bool, cb: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var g := UiTheme.label(ItemDB.glyph(id), 22, ItemDB.color(id), HORIZONTAL_ALIGNMENT_CENTER)
	g.add_theme_font_override("font", UiTheme.MONO_BOLD)
	g.custom_minimum_size = Vector2(36, 44)
	g.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(g)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(UiTheme.label(ItemDB.display_name(id), UiTheme.SIZE_BODY, UiTheme.TEXT))
	var s := RichTextLabel.new()
	s.bbcode_enabled = true
	s.fit_content = true
	s.scroll_active = false
	s.add_theme_font_size_override("normal_font_size", 12)
	s.add_theme_color_override("default_color", UiTheme.TEXT_DIM)
	s.text = sub
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(s)
	text.tooltip_text = InventoryScreen.item_stats(id)
	text.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(text)
	var b := UiTheme.button(action, cb)
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(110, 0)
	b.add_theme_color_override("font_color", UiTheme.ACCENT if enabled else UiTheme.TEXT_FAINT)
	row.add_child(b)
	parent.add_child(row)
	parent.add_child(UiTheme.hsep())


func _build_forge(inv: Object) -> void:
	var box := _list("Forge")
	var gold := int(inv.get("gold")) if inv != null else 0
	for rid: String in ItemDB.RECIPES:
		var r: Dictionary = ItemDB.RECIPES[rid]
		var parts := PackedStringArray()
		var ok := true
		for input: String in r.get("inputs", {}):
			var need := int(r["inputs"][input])
			var have := int(UiContext.call_on(inv, "count_of", [input], 0))
			var enough := have >= need
			ok = ok and enough
			parts.append("[color=#%s]%d %s (%d)[/color]" % [(UiTheme.TEXT if enough else UiTheme.DANGER).to_html(false), need, ItemDB.display_name(input), have])
		var cost := int(r.get("gold", 0))
		if cost > 0:
			ok = ok and gold >= cost
			parts.append("[color=#%s]%d gold[/color]" % [(Color(1, 0.85, 0.4) if gold >= cost else UiTheme.DANGER).to_html(false), cost])
		var count := int(r.get("count", 1))
		var label := "Forge" + (" ×%d" % count if count > 1 else "")
		_item_row(box, rid, "  ·  ".join(parts), label, ok, func() -> void: _craft(rid))


func _build_buy(inv: Object) -> void:
	var box := _list("Buy")
	var gold := int(inv.get("gold")) if inv != null else 0
	for id: String in ItemDB.SHOP:
		var price := int(ItemDB.SHOP[id])
		var desc := str(ItemDB.info(id).get("desc", ""))
		_item_row(box, id, "%s  ·  [color=#ffd966]%d gold[/color]" % [desc, price], "Buy", gold >= price, func() -> void: _buy(id))


func _build_sell(inv: Object) -> void:
	var box := _list("Sell")
	var any := false
	for i in range(0, 27):
		var item: Dictionary = UiContext.call_on(inv, "get_slot", [i], {})
		if item.is_empty():
			continue
		var id: String = item["id"]
		var value := int(ItemDB.info(id).get("value", 0))
		if value <= 0 or ItemDB.category(id) == "key":
			continue
		any = true
		var price := maxi(1, value / 2)
		_item_row(box, id, "×%d  ·  sells for [color=#ffd966]%d gold[/color] each" % [int(item.get("count", 1)), price], "Sell one", true, func() -> void: _sell(i))
	if not any:
		box.add_child(UiTheme.label("Nothing the merchant wants. Ore and crystal fetch the best prices.", UiTheme.SIZE_BODY, UiTheme.TEXT_DIM))


func _craft(rid: String) -> void:
	var ok: bool = UiContext.call_on(UiContext.player(), "craft", [rid], false)
	_feedback(ok, "Forged %s." % ItemDB.display_name(rid), "You lack the materials.")


func _buy(id: String) -> void:
	var ok: bool = UiContext.call_on(UiContext.player(), "buy", [id], false)
	_feedback(ok, "Bought %s." % ItemDB.display_name(id), "Not enough gold, or no room in your pack.")


func _sell(i: int) -> void:
	var ok: bool = UiContext.call_on(UiContext.player(), "sell_slot", [i], false)
	_feedback(ok, "Sold.", "The merchant shakes their head.")


func _feedback(ok: bool, good: String, bad: String) -> void:
	_status.text = good if ok else bad
	_status.add_theme_color_override("font_color", UiTheme.GOOD if ok else UiTheme.DANGER)
	UiContext.sound("coin" if ok else "ui_back")
	_rebuild(_tabs.current_tab)
