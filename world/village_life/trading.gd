class_name Trading
extends RefCounted
## Prices, stock and the act of trading with one villager. Inventories are
## each player's own (as with every shop), so trades run on the trading
## player's machine against their CharacterLife: reputation in the village
## sets the prices and which wares are offered; each villager's shelf and
## appetite are counted per day and restock over the following days.
##
## A villager is described by `who`: {key, village, profession, name}.

## Price factor by reputation tier (0 Distrusted .. 4 Honoured).
const BUY_FACTOR := [1.3, 1.0, 0.95, 0.88, 0.8]     ## what you pay
const SELL_FACTOR := [0.7, 1.0, 1.05, 1.12, 1.2]    ## what you are paid
## Below this reputation the village will not deal with you at all.
const REFUSE_BELOW := -30


static func who_of(npc: Node) -> Dictionary:
	return {"key": "%s:%d" % [String(npc.get("village")), int(npc.get("npc_seed"))], "village": String(npc.get("village")),
		"profession": String(npc.get("profession")), "name": String(npc.get("display_name"))}


static func refuses(life: CharacterLife, who: Dictionary) -> bool:
	return life.rep(String(who["village"])) < REFUSE_BELOW


static func buy_price(base: int, rep_tier: int) -> int:
	return maxi(1, roundi(base * float(BUY_FACTOR[clampi(rep_tier, 0, 4)])))


static func sell_price(base: int, rep_tier: int) -> int:
	return maxi(1, roundi(base * float(SELL_FACTOR[clampi(rep_tier, 0, 4)])))


## What the villager sells: [{item, price, stock, locked (tier needed or 0)}].
static func sell_offers(life: CharacterLife, who: Dictionary, day: int) -> Array:
	var out: Array = []
	var t := life.tier(String(who["village"]))
	var trade: Dictionary = Professions.TRADES.get(String(who["profession"]), {})
	for e: Array in trade.get("sells", []):
		var item := String(e[0])
		if not ItemDB.exists(item):
			continue
		var need := int(e[3])
		out.append({"item": item, "price": buy_price(int(e[1]), t), "stock": life.remaining(String(who["key"]), "sold", item, int(e[2]), day),
			"full": int(e[2]), "locked": need if t < need else 0})
	return out


## What the villager buys: [{item, price, wants}].
static func buy_offers(life: CharacterLife, who: Dictionary, day: int) -> Array:
	var out: Array = []
	var t := life.tier(String(who["village"]))
	var trade: Dictionary = Professions.TRADES.get(String(who["profession"]), {})
	for e: Array in trade.get("buys", []):
		var item := String(e[0])
		if not ItemDB.exists(item):
			continue
		out.append({"item": item, "price": sell_price(int(e[1]), t), "wants": life.remaining(String(who["key"]), "bought", item, int(e[2]), day), "full": int(e[2])})
	return out


static func _find(list: Array, item: String) -> Dictionary:
	for o: Dictionary in list:
		if String(o["item"]) == item:
			return o
	return {}


## Buys `count` of `item` from the villager. Returns "" or why not.
static func buy(inv: Inventory, life: CharacterLife, who: Dictionary, item: String, count: int, day: int) -> String:
	if refuses(life, who):
		return "%s won't deal with you." % String(who["name"])
	var o := _find(sell_offers(life, who, day), item)
	if o.is_empty():
		return "Not for sale."
	if int(o["locked"]) > 0:
		return "Only for those the village calls %s." % CharacterLife.tier_name(int(o["locked"]))
	count = mini(count, int(o["stock"]))
	if count <= 0:
		return "Sold out until tomorrow."
	var cost := int(o["price"]) * count
	if inv.gold < cost:
		return "Not enough gold."
	if not inv.room_for(item, count):
		return "No room in your pack."
	inv.gold -= cost
	inv.add(item, count)
	life.take(String(who["key"]), "sold", item, count, day, int(o["full"]))
	life.trade_rep(String(who["village"]), cost, day)
	return ""


## Sells `count` of `item` to the villager. Returns "" or why not.
static func sell(inv: Inventory, life: CharacterLife, who: Dictionary, item: String, count: int, day: int) -> String:
	if refuses(life, who):
		return "%s won't deal with you." % String(who["name"])
	var o := _find(buy_offers(life, who, day), item)
	if o.is_empty():
		return "They don't want that."
	count = mini(mini(count, int(o["wants"])), inv.count_of(item))
	if count <= 0:
		return "They have all they need of that today." if inv.has(item) else "You have none."
	var paid := int(o["price"]) * count
	inv.remove(item, count)
	inv.gold += paid
	inv.changed.emit()
	life.take(String(who["key"]), "bought", item, count, day, int(o["full"]))
	life.trade_rep(String(who["village"]), paid, day)
	return ""
