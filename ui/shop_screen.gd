class_name ShopScreen
extends UiModal
## Trade, opened by Events.shop_open(kind). The merchant buys and sells; the
## blacksmith lets you use his forge: "blacksmith" opens the crafting book of
## the village smithy (anvil + furnace) instead. "trade:<net id>" trades with
## one villager by their profession (Professions.TRADES via Trading): their
## own wares, stock and appetite, priced by the village's opinion of you.

var kind := "merchant"
var _tabs: TabContainer
var _gold: Label
var _status: Label
var _tooltip: ItemTooltip
var _panel: ItemStyle.OrnatePanel
## Villager trade ("trade:<id>"): Trading.who_of(npc), else empty (merchant shop).
var _who := {}


func _init() -> void:
	panel_size = Vector2(900, 640)
	panel_title = ""


func _build() -> void:
	_panel = ItemStyle.dress(self, "MERCHANT")
	var head := HBoxContainer.new()
	_status = UiTheme.label("", UiTheme.SIZE_BODY, ItemStyle.TEXT_DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_status)
	_gold = UiTheme.label("", 22, Color(1.0, 0.84, 0.45), HORIZONTAL_ALIGNMENT_RIGHT)
	_gold.add_theme_font_override("font", ItemStyle.title_font(700))
	head.add_child(_gold)
	content.add_child(head)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_override("font", ItemStyle.title_font(700))
	_tabs.add_theme_font_size_override("font_size", 14)
	content.add_child(_tabs)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_child(ItemStyle.button("Leave  [Esc]", close))
	content.add_child(foot)
	_tooltip = ItemTooltip.new()
	add_child(_tooltip)
	UiContext.on("shop_open", open_shop)
	UiContext.on("inventory_changed", func() -> void:
		if is_open:
			_rebuild(_tabs.current_tab))
	_install_crafting.call_deferred()


func _install_crafting() -> void:
	CraftingScreen.ensure(self)
	PetNameDialog.ensure(self)


func open_shop(shop_kind: String) -> void:
	kind = shop_kind
	if kind == "blacksmith":
		# The smith's forge is a crafting station you may use.
		UiContext.emit_event("station_open", ["smithy", null])
		return
	_who = {}
	_panel.title = "MERCHANT"
	if kind.begins_with("trade:"):
		var npc := _villager(int(kind.trim_prefix("trade:")))
		if npc == null:
			return
		_who = Trading.who_of(npc)
		_panel.title = String(npc.call("role_title")).to_upper()
	open()


func _villager(id: int) -> Node:
	var p := UiContext.player() as Entity
	var w := p.world() if p != null else null
	return w.entity(id) as Node if w != null else null


func _life() -> CharacterLife:
	return CharacterLife.of(UiContext.player())


func _day() -> int:
	var p := UiContext.player() as Entity
	var w := p.world() if p != null else null
	return w.day() if w != null else 0


func _on_open() -> void:
	_status.text = "Coin for comfort. Comfort for coin." if _who.is_empty() else "%s — the village calls you %s." % [
		Professions.greeting(String(_who["profession"])), CharacterLife.tier_name(_life().tier(String(_who["village"])))]
	_status.add_theme_color_override("font_color", ItemStyle.TEXT_DIM)
	ItemIcons.prewarm()
	_rebuild(0)


func close() -> void:
	if _tooltip != null:
		_tooltip.hide_tip()
	super()


func _rebuild(tab := 0) -> void:
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	var inv := UiContext.inventory() as Inventory
	_gold.text = "%s  ◎" % UiTheme.format_int(inv.gold if inv != null else 0)
	if not _who.is_empty():
		_build_trade_buy(inv)
		_build_trade_sell(inv)
	else:
		_build_buy(inv)
		_build_sell(inv)
	_tabs.current_tab = clampi(tab, 0, _tabs.get_tab_count() - 1)


func _list(title: String) -> VBoxContainer:
	var well := ItemStyle.well(4)
	well.name = title
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	well.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 0)
	scroll.add_child(box)
	_tabs.add_child(well)
	return box


func _item_row(parent: Control, slot: Dictionary, sub: String, action: String, enabled: bool, cb: Callable) -> void:
	var row := TradeRow.new()
	row.slot = slot
	row.sub = sub
	row.custom_minimum_size = Vector2(0, 62)
	row.hovered.connect(func(r: Control) -> void: _tooltip.show_item(slot, r.get_global_rect()))
	row.unhovered.connect(func() -> void: _tooltip.hide_tip())
	var b := ItemStyle.button(action, cb, enabled)
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(120, 34)
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.anchor_top = 0.5
	b.anchor_bottom = 0.5
	b.offset_left = -136
	b.offset_right = -16
	b.offset_top = -17
	b.offset_bottom = 17
	row.add_child(b)
	parent.add_child(row)


func _build_buy(inv: Inventory) -> void:
	var box := _list("Buy")
	var gold := inv.gold if inv != null else 0
	for id: String in ItemDB.SHOP:
		var price := int(ItemDB.SHOP[id])
		_item_row(box, {"id": id, "count": 1}, "[color=#ffd36b]%d gold[/color]   [color=#%s]%s[/color]" % [price, ItemStyle.TEXT_DIM.to_html(false), _short(str(ItemDB.info(id).get("desc", "")))],
			"Buy", gold >= price, func() -> void: _buy(id))


func _build_sell(inv: Inventory) -> void:
	var box := _list("Sell")
	var any := false
	if inv != null:
		for i in inv.size():
			var item := inv.get_slot(i)
			if item.is_empty():
				continue
			var id := String(item["id"])
			var value := int(ItemDB.info(id).get("value", 0))
			if value <= 0 or ItemDB.category(id) == "key":
				continue
			any = true
			var price := maxi(1, value / 2)
			_item_row(box, item, "×%d   ·   [color=#ffd36b]%d gold[/color] each" % [int(item.get("count", 1)), price], "Sell one", true, func() -> void: _sell(i))
	if not any:
		box.add_child(UiTheme.label("  Nothing the merchant wants. Ore, ingots and gems fetch the best prices.", UiTheme.SIZE_BODY, ItemStyle.TEXT_DIM))


## A villager's own wares (Trading.sell_offers): stock per day, some locked by reputation.
func _build_trade_buy(inv: Inventory) -> void:
	var box := _list("Buy")
	var gold := inv.gold if inv != null else 0
	for o: Dictionary in Trading.sell_offers(_life(), _who, _day()):
		var id := String(o["item"])
		var price := int(o["price"])
		var locked := int(o["locked"])
		var sub := "[color=#ffd36b]%d gold[/color]   ·   %d left today" % [price, int(o["stock"])]
		if locked > 0:
			sub = "[color=#%s]Only for a %s of the village[/color]" % [ItemStyle.TEXT_DIM.to_html(false), CharacterLife.tier_name(locked)]
		_item_row(box, {"id": id, "count": 1}, sub, "Buy", locked == 0 and int(o["stock"]) > 0 and gold >= price,
			func() -> void: _trade(true, id))


## What the villager wants (Trading.buy_offers), shown when you carry some.
func _build_trade_sell(inv: Inventory) -> void:
	var box := _list("Sell")
	var any := false
	for o: Dictionary in Trading.buy_offers(_life(), _who, _day()):
		var id := String(o["item"])
		var have := inv.count_of(id) if inv != null else 0
		if have <= 0:
			continue
		any = true
		_item_row(box, {"id": id, "count": have}, "×%d   ·   [color=#ffd36b]%d gold[/color] each   ·   wants %d more today" % [have, int(o["price"]), int(o["wants"])],
			"Sell one", int(o["wants"]) > 0, func() -> void: _trade(false, id))
	if not any:
		box.add_child(UiTheme.label("  Nothing they want. They buy: " + ", ".join(Trading.buy_offers(_life(), _who, _day()).slice(0, 6).map(
			func(o: Dictionary) -> String: return ItemDB.display_name(String(o["item"])))), UiTheme.SIZE_BODY, ItemStyle.TEXT_DIM))


## Trades run on the trading player's own inventory (as with every shop).
func _trade(buying: bool, id: String) -> void:
	var inv := UiContext.inventory() as Inventory
	if inv == null:
		return
	var err := Trading.buy(inv, _life(), _who, id, 1, _day()) if buying else Trading.sell(inv, _life(), _who, id, 1, _day())
	if err == "" and buying:
		inv.changed.emit()
	_feedback(err == "", ("Bought %s." if buying else "Sold %s.") % ItemDB.display_name(id), err)


func _buy(id: String) -> void:
	var ok: bool = UiContext.call_on(UiContext.player(), "buy", [id], false)
	_feedback(ok, "Bought %s." % ItemDB.display_name(id), "Not enough gold, or no room in your pack.")


func _sell(i: int) -> void:
	var ok: bool = UiContext.call_on(UiContext.player(), "sell_slot", [i], false)
	_feedback(ok, "Sold.", "The merchant shakes their head.")


func _feedback(ok: bool, good: String, bad: String) -> void:
	_status.text = good if ok else bad
	_status.add_theme_color_override("font_color", ItemStyle.GOOD if ok else ItemStyle.BAD)
	UiContext.sound("coin" if ok else "ui_back")
	_rebuild(_tabs.current_tab)


static func _short(s: String, n := 62) -> String:
	return s if s.length() <= n else s.substr(0, n - 1).strip_edges() + "…"


## A merchant row: framed icon, name in rarity colour, a bbcode sub line.
class TradeRow:
	extends Control
	signal hovered(row: Control)
	signal unhovered
	var slot := {}
	var sub := ""
	var _hover := false
	var _v := -1
	var _rich: RichTextLabel

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mouse_filter = Control.MOUSE_FILTER_PASS
		_rich = RichTextLabel.new()
		_rich.bbcode_enabled = true
		_rich.scroll_active = false
		_rich.fit_content = true
		_rich.autowrap_mode = TextServer.AUTOWRAP_OFF
		_rich.clip_contents = true
		_rich.add_theme_font_size_override("normal_font_size", 12)
		_rich.add_theme_font_override("normal_font", UiTheme.MONO)
		_rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rich.position = Vector2(74, 34)
		_rich.text = sub
		add_child(_rich)
		mouse_entered.connect(func() -> void:
			_hover = true
			hovered.emit(self)
			queue_redraw())
		mouse_exited.connect(func() -> void:
			_hover = false
			unhovered.emit()
			queue_redraw())

	func _process(_d: float) -> void:
		if _v != ItemIcons.version:
			_v = ItemIcons.version
			queue_redraw()
		if _rich != null:
			_rich.size = Vector2(maxf(10.0, size.x - 74 - 150), 22)

	func _draw() -> void:
		var id := String(slot.get("id", ""))
		if _hover:
			ItemStyle.hgradient(self, Rect2(Vector2.ZERO, size), Color(1.0, 0.8, 0.6, 0.08), Color(1.0, 0.8, 0.6, 0.0))
		draw_line(Vector2(8, size.y - 0.5), Vector2(size.x - 8, size.y - 0.5), Color(ItemStyle.BRONZE.r, ItemStyle.BRONZE.g, ItemStyle.BRONZE.b, 0.25), 1.0)
		var r := Rect2(Vector2(10, 6), Vector2(size.y - 12, size.y - 12))
		ItemStyle.draw_slot(self, r, ItemDB.rarity(id), false, _hover)
		ItemStyle.draw_item(self, r.grow(-4), id)
		draw_string(ItemStyle.title_font(700), Vector2(74, 26), ItemDB.display_name(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ItemDB.rarity_color(id))
