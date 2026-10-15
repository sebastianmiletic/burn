class_name Inventory
extends RefCounted
## A player's items: 3 hotbar slots (indices 0..2) followed by the bag, plus
## four armour slots (head, chest, legs, feet) addressed as EQUIP_BASE + n so
## the UI can treat every slot alike.
## Each slot is {} (empty) or {"id": String, "count": int}; gear may also carry
## {"gem": String} (a socketed gem).
##
## Client-local like the rest of the character: crafting, equipment, sockets
## and potion buffs never touch the network. The Player asks this object for
## its attack stats and for the incoming-damage multiplier.

signal changed

const HOTBAR := 3
const BAG := 30
const EQUIP_BASE := 100
const EQUIP_SLOTS := ["head", "chest", "legs", "feet"]

## Armour formula: damage taken = 50 / (50 + defence). A full infernal set
## (62) takes 45 %, copper (8) 86 %.
const ARMOR_K := 50.0
const BUFFS := {"ironskin": {"defense": 30.0}, "might": {"damage_mult": 0.25}}

var slots: Array[Dictionary] = []
var equipment := {"head": {}, "chest": {}, "legs": {}, "feet": {}}
var selected := 0
var gold := 0
## buff name -> end time (seconds, Time.get_ticks_msec based). Not saved.
var buffs := {}


func _init() -> void:
	slots.resize(HOTBAR + BAG)
	for i in slots.size():
		slots[i] = {}


func size() -> int:
	return slots.size()


static func is_equip_index(i: int) -> bool:
	return i >= EQUIP_BASE and i < EQUIP_BASE + EQUIP_SLOTS.size()


static func equip_index(slot_name: String) -> int:
	return EQUIP_BASE + EQUIP_SLOTS.find(slot_name)


func get_slot(i: int) -> Dictionary:
	if is_equip_index(i):
		return equipment[EQUIP_SLOTS[i - EQUIP_BASE]]
	return slots[i] if i >= 0 and i < slots.size() else {}


func _set_slot(i: int, d: Dictionary) -> void:
	if is_equip_index(i):
		equipment[EQUIP_SLOTS[i - EQUIP_BASE]] = d
	elif i >= 0 and i < slots.size():
		slots[i] = d


func selected_item() -> String:
	return slots[selected].get("id", "")


func select(i: int) -> void:
	selected = clampi(i, 0, HOTBAR - 1)
	changed.emit()


## Adds items, filling existing stacks first (hotbar, then bag). Returns the
## number that did not fit.
func add(id: String, count := 1) -> int:
	if not ItemDB.exists(id) or count <= 0:
		return count
	var max_stack := ItemDB.max_stack(id)
	for i in slots.size():
		if count <= 0:
			break
		if slots[i].get("id", "") == id and slots[i]["count"] < max_stack:
			var take := mini(max_stack - int(slots[i]["count"]), count)
			slots[i]["count"] += take
			count -= take
	for i in slots.size():
		if count <= 0:
			break
		if slots[i].is_empty():
			var take := mini(max_stack, count)
			slots[i] = {"id": id, "count": take}
			count -= take
	changed.emit()
	return count


## True if `count` of `id` would fit right now.
func room_for(id: String, count := 1) -> bool:
	var max_stack := ItemDB.max_stack(id)
	var space := 0
	for s in slots:
		if s.is_empty():
			space += max_stack
		elif s.get("id", "") == id:
			space += max_stack - int(s["count"])
		if space >= count:
			return true
	return space >= count


func count_of(id: String) -> int:
	var n := 0
	for s in slots:
		if s.get("id", "") == id:
			n += int(s["count"])
	return n


func has(id: String, count := 1) -> bool:
	return count_of(id) >= count


## Removes up to `count`, last slots first so hotbar items are kept. Returns removed.
func remove(id: String, count := 1) -> int:
	var removed := 0
	for i in range(slots.size() - 1, -1, -1):
		if removed >= count:
			break
		if slots[i].get("id", "") == id:
			var take := mini(int(slots[i]["count"]), count - removed)
			slots[i]["count"] -= take
			removed += take
			if slots[i]["count"] <= 0:
				slots[i] = {}
	if removed > 0:
		changed.emit()
	return removed


func remove_from_slot(i: int, count := 1) -> void:
	var s := get_slot(i)
	if s.is_empty():
		return
	s["count"] = int(s["count"]) - count
	if int(s["count"]) <= 0:
		_set_slot(i, {})
	changed.emit()


## Can the item in `item` go into slot `i`? Armour slots take only matching armour.
func accepts(i: int, item: Dictionary) -> bool:
	if item.is_empty():
		return true
	if is_equip_index(i):
		return ItemDB.equip_slot(String(item.get("id", ""))) == EQUIP_SLOTS[i - EQUIP_BASE]
	return i >= 0 and i < slots.size()


## Moves / swaps / merges two slots (bag, hotbar or armour). Returns false if
## the move is not allowed (e.g. a sword into the helmet slot).
func swap(a: int, b: int) -> bool:
	if a == b:
		return false
	var sa := get_slot(a)
	var sb := get_slot(b)
	# Merge equal stacks.
	if not sa.is_empty() and not sb.is_empty() and sa["id"] == sb["id"] and not sa.has("gem") and not sb.has("gem"):
		var max_stack := ItemDB.max_stack(sa["id"])
		var moved := mini(int(sa["count"]), max_stack - int(sb["count"]))
		if moved > 0:
			sb["count"] += moved
			sa["count"] -= moved
			_set_slot(a, {} if sa["count"] <= 0 else sa)
			changed.emit()
			return true
	if not accepts(b, sa) or not accepts(a, sb):
		return false
	_set_slot(a, sb)
	_set_slot(b, sa)
	changed.emit()
	return true


## Puts the armour in bag/hotbar slot `i` on (swapping out what was worn).
func equip_from(i: int) -> bool:
	var s := get_slot(i)
	var slot_name := ItemDB.equip_slot(String(s.get("id", "")))
	if slot_name == "" or is_equip_index(i):
		return false
	return swap(i, equip_index(slot_name))


## Takes off the armour in `slot_name` into the first free bag slot.
func unequip(slot_name: String) -> bool:
	var ei := equip_index(slot_name)
	if get_slot(ei).is_empty():
		return false
	for j in range(HOTBAR, slots.size()):
		if slots[j].is_empty():
			return swap(ei, j)
	for j in HOTBAR:
		if slots[j].is_empty():
			return swap(ei, j)
	return false


## Merges stacks and orders the bag (not the hotbar): gear first, best first,
## then consumables, materials, blocks.
func sort_bag() -> void:
	const ORDER := ["weapon", "tool", "armor", "light", "consumable", "station", "gem", "material", "block", "key"]
	var items: Array[Dictionary] = []
	for i in range(HOTBAR, slots.size()):
		if not slots[i].is_empty():
			items.append(slots[i])
		slots[i] = {}
	# Merge partial stacks.
	var merged: Array[Dictionary] = []
	for it in items:
		var placed := false
		if not it.has("gem"):
			for m in merged:
				if m["id"] == it["id"] and not m.has("gem") and int(m["count"]) < ItemDB.max_stack(m["id"]):
					var take := mini(ItemDB.max_stack(m["id"]) - int(m["count"]), int(it["count"]))
					m["count"] = int(m["count"]) + take
					it["count"] = int(it["count"]) - take
					if int(it["count"]) <= 0:
						placed = true
						break
		if not placed:
			merged.append(it)
	merged.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca := ORDER.find(ItemDB.category(a["id"]))
		var cb := ORDER.find(ItemDB.category(b["id"]))
		if ca != cb:
			return ca < cb
		var ra := ItemDB.rarity(a["id"])
		var rb := ItemDB.rarity(b["id"])
		if ra != rb:
			return ra > rb
		return ItemDB.display_name(a["id"]) < ItemDB.display_name(b["id"]))
	for k in merged.size():
		slots[HOTBAR + k] = merged[k]
	changed.emit()


## Sets the gem in slot `gem_index` into the gear in `target_index` (one socket
## per item; a gem already there is destroyed).
func socket(gem_index: int, target_index: int) -> bool:
	var g := get_slot(gem_index)
	var t := get_slot(target_index)
	if g.is_empty() or t.is_empty() or not ItemDB.can_socket(String(g["id"]), String(t["id"])):
		return false
	t["gem"] = String(g["id"])
	_set_slot(target_index, t)
	remove_from_slot(gem_index, 1)
	changed.emit()
	return true


# --- Fuel and crafting ---------------------------------------------------------------------

## Furnace fuel units available, not counting items the recipe itself consumes
## (`reserved` = recipe inputs per craft, multiplied by `times`).
func fuel_units(reserved := {}, times := 1) -> int:
	var units := 0
	for id: String in ItemDB.FUEL:
		var n := count_of(id) - int(reserved.get(id, 0)) * times
		if n > 0:
			units += n * ItemDB.fuel_value(id)
	return units


## Burns at least `units` of fuel, cheapest items first. Returns false if short.
func consume_fuel(units: int, reserved := {}) -> bool:
	if units <= 0:
		return true
	if fuel_units(reserved) < units:
		return false
	var order: Array = ItemDB.FUEL.keys()
	order.sort_custom(func(x: String, y: String) -> bool: return ItemDB.fuel_value(x) < ItemDB.fuel_value(y))
	# Prefer exact-ish burns: cheap fuel first, coal last.
	for id: String in order:
		var v := ItemDB.fuel_value(id)
		while units > 0 and count_of(id) - int(reserved.get(id, 0)) > 0:
			remove(id, 1)
			units -= v
	return units <= 0


## Performs a craft. `nearby_station_kinds` = station kinds within reach
## (Player gathers them). Returns {ok: bool, reason: String, item: String, count: int}.
func craft(recipe_id: String, nearby_station_kinds: Array = [], times := 1) -> Dictionary:
	var r := ItemDB.recipe(recipe_id)
	if r.is_empty():
		return {"ok": false, "reason": "Unknown recipe."}
	if not ItemDB.station_available(recipe_id, nearby_station_kinds):
		return {"ok": false, "reason": "You need a %s nearby." % ItemDB.station_name(ItemDB.recipe_station(recipe_id))}
	var miss := ItemDB.missing_for(recipe_id, self, times)
	if not miss.is_empty():
		if miss.has("fuel"):
			return {"ok": false, "reason": "The furnace needs fuel: coal, charcoal or wood."}
		return {"ok": false, "reason": "You lack the materials."}
	var result := ItemDB.recipe_result(recipe_id)
	var count := int(r.get("count", 1)) * times
	if not room_for(result, count):
		# Consuming the inputs may free a slot; check by simulation.
		var probe := Inventory.new()
		probe.from_dict(to_dict())
		for item: String in r.get("inputs", {}):
			probe.remove(item, int(r["inputs"][item]) * times)
		if not probe.room_for(result, count):
			return {"ok": false, "reason": "No room in your pack."}
	var inputs: Dictionary = r.get("inputs", {})
	consume_fuel(int(r.get("fuel", 0)) * times, _scaled(inputs, times))
	for item: String in inputs:
		remove(item, int(inputs[item]) * times)
	gold -= int(r.get("gold", 0)) * times
	add(result, count)
	changed.emit()
	return {"ok": true, "reason": "", "item": result, "count": count}


static func _scaled(d: Dictionary, times: int) -> Dictionary:
	var out := {}
	for k: String in d:
		out[k] = int(d[k]) * times
	return out


## How many times the recipe could be crafted with what is carried (capped).
func craftable_times(recipe_id: String, cap := 99) -> int:
	var n := 0
	while n < cap and ItemDB.missing_for(recipe_id, self, n + 1).is_empty():
		n += 1
	return n


# --- Combat stats ------------------------------------------------------------------------

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func buff_active(buff_name: String) -> bool:
	return float(buffs.get(buff_name, 0.0)) > _now()


func buff_remaining(buff_name: String) -> float:
	return maxf(0.0, float(buffs.get(buff_name, 0.0)) - _now())


func _buff_sum(stat: String) -> float:
	var v := 0.0
	for b: String in buffs:
		if buff_active(b):
			v += float(BUFFS.get(b, {}).get(stat, 0.0))
	return v


## Total armour defence: worn pieces, their gems and active buffs.
func defense() -> float:
	var d := 0.0
	for s: String in EQUIP_SLOTS:
		var e: Dictionary = equipment[s]
		if e.is_empty():
			continue
		d += float(ItemDB.info(e["id"]).get("defense", 0.0))
		d += float(ItemDB.socket_bonus(String(e.get("gem", "")), "armor").get("defense", 0.0))
	return d + _buff_sum("defense")


func fire_resist() -> float:
	var r := 0.0
	for s: String in EQUIP_SLOTS:
		var e: Dictionary = equipment[s]
		if e.is_empty():
			continue
		r += float(ItemDB.info(e["id"]).get("fire_resist", 0.0))
		r += float(ItemDB.socket_bonus(String(e.get("gem", "")), "armor").get("fire_resist", 0.0))
	return clampf(r, 0.0, 0.75)


## Multiplier for damage the wearer takes. Player.receive_damage multiplies
## `amount` by this. Falls and the void ignore armour; fire also uses fire resist.
func damage_taken_multiplier(kind := "hit") -> float:
	if kind in ["void", "fall"]:
		return 1.0
	var m := ARMOR_K / (ARMOR_K + defense())
	if kind in ["fire", "burn", "lava", "burn_hit"]:
		m = lerpf(1.0, m, 0.5) * (1.0 - fire_resist())
	return m


## Fraction of damage blocked, for the UI (0..1).
func damage_reduction() -> float:
	return 1.0 - ARMOR_K / (ARMOR_K + defense())


## Stats of the selected hotbar item including its gem and active buffs:
## {damage, speed, reach, burn, crit, heavy}. Bare hands: 3 damage.
func attack_stats() -> Dictionary:
	var s: Dictionary = slots[selected]
	return item_attack_stats(s)


func item_attack_stats(s: Dictionary) -> Dictionary:
	var inf := ItemDB.info(String(s.get("id", "")))
	var dmg := float(inf.get("damage", 3.0))
	var out := {"damage": dmg, "speed": float(inf.get("speed", 1.0)), "reach": float(inf.get("reach", 2.2)),
		"burn": float(inf.get("burn", 0.0)), "crit": 0.1 + float(inf.get("crit", 0.0)), "heavy": bool(inf.get("heavy", false))}
	var gem := ItemDB.socket_bonus(String(s.get("gem", "")), String(inf.get("category", "")))
	out["burn"] = float(out["burn"]) + float(gem.get("burn", 0.0))
	out["crit"] = float(out["crit"]) + float(gem.get("crit", 0.0))
	var mult := 1.0 + float(gem.get("damage_mult", 0.0)) + _buff_sum("damage_mult")
	out["damage"] = dmg * mult
	return out


## Applies a consumable's effect bookkeeping (buffs). Returns the health to
## restore. The caller removes the item and plays the drink animation.
func apply_consumable(id: String) -> float:
	var inf := ItemDB.info(id)
	if inf.has("buff"):
		buffs[String(inf["buff"])] = _now() + float(inf.get("buff_time", 60.0))
		changed.emit()
	return float(inf.get("heal", 0.0))


## Best healing item carried (potions before food), or "".
func best_heal_item() -> String:
	for id: String in ItemDB.heal_items_by_strength():
		if has(id):
			return id
	return ""


## Best selected-item stat among hotbar items is not used: only the selected item counts.
func selected_info() -> Dictionary:
	return ItemDB.info(selected_item())


func to_dict() -> Dictionary:
	return {"slots": slots.duplicate(true), "selected": selected, "gold": gold, "equipment": equipment.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	var saved: Array = d.get("slots", [])
	for i in slots.size():
		var s: Variant = saved[i] if i < saved.size() else {}
		slots[i] = _valid(s)
	# Old saves with fewer bag slots simply leave the new ones empty.
	var eq: Dictionary = d.get("equipment", {})
	for s: String in EQUIP_SLOTS:
		var e := _valid(eq.get(s, {}))
		equipment[s] = e if e.is_empty() or ItemDB.equip_slot(String(e["id"])) == s else {}
	selected = clampi(int(d.get("selected", 0)), 0, HOTBAR - 1)
	gold = int(d.get("gold", 0))
	changed.emit()


## Drops unknown ids from old saves instead of crashing on them.
static func _valid(s: Variant) -> Dictionary:
	if not s is Dictionary or (s as Dictionary).is_empty():
		return {}
	var d: Dictionary = s
	if not ItemDB.exists(String(d.get("id", ""))) or int(d.get("count", 0)) <= 0:
		return {}
	return d.duplicate()
