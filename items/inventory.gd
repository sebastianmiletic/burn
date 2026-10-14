class_name Inventory
extends RefCounted
## A player's items: 3 hotbar slots (indices 0..2) followed by the bag.
## Each slot is {} (empty) or {"id": String, "count": int}.

signal changed

const HOTBAR := 3
const BAG := 24

var slots: Array[Dictionary] = []
var selected := 0
var gold := 0


func _init() -> void:
	slots.resize(HOTBAR + BAG)
	for i in slots.size():
		slots[i] = {}


func size() -> int:
	return slots.size()


func get_slot(i: int) -> Dictionary:
	return slots[i] if i >= 0 and i < slots.size() else {}


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
	if slots[i].is_empty():
		return
	slots[i]["count"] -= count
	if slots[i]["count"] <= 0:
		slots[i] = {}
	changed.emit()


func swap(a: int, b: int) -> void:
	if a == b:
		return
	var sa := slots[a]
	var sb := slots[b]
	# Merge equal stacks.
	if not sa.is_empty() and not sb.is_empty() and sa["id"] == sb["id"]:
		var max_stack := ItemDB.max_stack(sa["id"])
		var moved := mini(int(sa["count"]), max_stack - int(sb["count"]))
		if moved > 0:
			sb["count"] += moved
			sa["count"] -= moved
			slots[a] = {} if sa["count"] <= 0 else sa
			changed.emit()
			return
	slots[a] = sb
	slots[b] = sa
	changed.emit()


## Best tool/weapon stat among hotbar items is not used: only the selected item counts.
func selected_info() -> Dictionary:
	return ItemDB.info(selected_item())


func to_dict() -> Dictionary:
	return {"slots": slots.duplicate(true), "selected": selected, "gold": gold}


func from_dict(d: Dictionary) -> void:
	var saved: Array = d.get("slots", [])
	for i in slots.size():
		slots[i] = saved[i] if i < saved.size() and saved[i] is Dictionary else {}
	selected = int(d.get("selected", 0))
	gold = int(d.get("gold", 0))
	changed.emit()
