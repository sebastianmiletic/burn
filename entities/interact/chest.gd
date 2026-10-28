class_name Chest
extends Entity
## A loot chest in a mine, wreck, ruin or lair. Opening it (E) shows its
## contents in the shared container screen (BuildingWorld / ContainerScreen):
## the first opening rolls its loot by tier into the chest (saved with the
## world), after that it is an ordinary chest anyone can take from or store
## in. The lid swings open while someone is looking inside.

const SLOTS := 24
const LOOT := {
	1: [["potion_health", 0.7, 1, 2], ["torch", 0.8, 3, 6], ["coal", 0.6, 2, 5], ["iron_ore", 0.5, 1, 3], ["bread", 0.6, 1, 3]],
	2: [["potion_health", 0.9, 1, 3], ["potion_greater", 0.4, 1, 1], ["gold_ore", 0.6, 2, 4], ["ember_crystal", 0.4, 1, 2], ["iron_ore", 0.6, 2, 5], ["lantern", 0.4, 1, 2]],
	3: [["potion_greater", 0.9, 1, 2], ["gold_ore", 0.8, 3, 6], ["ember_crystal", 0.7, 2, 4], ["obsidian", 0.5, 2, 4], ["sword_ember", 0.25, 1, 1], ["pickaxe_iron", 0.35, 1, 1]],
}

var chest_key := ""
var tier := 1
var opened := false
var _lid: Node3D
var _lid_axis := Vector3.RIGHT
var _lid_open := -1.85


func _init() -> void:
	kind = "chest"
	team = Team.NEUTRAL
	hit_radius = 0.5
	hit_height = 0.9
	body.collides = false
	body.gravity = 0.0


func on_spawned(data: Dictionary) -> void:
	chest_key = String(data.get("key", ""))
	tier = int(data.get("tier", 1))
	opened = bool(data.get("opened", false))
	var model := PieceMesh.get_model("chest_iron" if tier >= 2 else "chest", "")
	var root := Node3D.new()
	root.position = Vector3(-0.5, 0.0, -0.5)
	add_child(root)
	var mi := MeshInstance3D.new()
	mi.mesh = model["mesh"]
	root.add_child(mi)
	for leaf: Dictionary in model["leaves"]:
		_lid = Node3D.new()
		_lid.position = leaf["pivot"]
		_lid_axis = leaf["axis"]
		_lid_open = float(leaf["open"])
		var lm := MeshInstance3D.new()
		lm.mesh = leaf["mesh"]
		_lid.add_child(lm)
		root.add_child(_lid)


func interact_prompt(_p: Player) -> String:
	return "Open chest" if not opened else "Look in the chest"


func local_interact(_p: Player) -> void:
	var b := world().building
	if b != null:
		b.request_open("c:" + chest_key, "Iron-bound Chest" if tier >= 2 else "Old Chest")


## Server: the chest's contents on first opening (gold goes to the opener).
## Chests already looted in saves from before containers stay empty.
func fill_loot(peer: int) -> Array:
	var slots: Array = []
	for k in SLOTS:
		slots.append({})  # one Dictionary per slot (fill() would share one)
	var w := world()
	if w.opened_chests.has(chest_key):
		return slots
	w.opened_chests[chest_key] = true
	opened = true
	var i := 0
	# Plus books (spells, potions, crafting), arrows and mana potions (ArcanaItems).
	for entry: Array in LOOT.get(tier, LOOT[1]) + ArcanaItems.CHEST_LOOT.get(tier, []):
		if i >= SLOTS:
			break
		if randf() < float(entry[1]):
			slots[i] = {"id": String(entry[0]), "count": randi_range(int(entry[2]), int(entry[3]))}
			i += 3 if i < 18 else 1
	w.replicator.give_gold_to(peer, randi_range(5, 15) * tier)
	w.replicator.broadcast_entity_event(net_id, "opened")
	return slots


func on_event(event: String, arg: Variant) -> void:
	if event == "opened":
		opened = true
	elif event == "lid" and _lid != null:
		var open := bool(arg)
		Audio.play("chest", global_position, -4.0, 1.0 if open else 0.85)
		var from := _lid.basis.get_rotation_quaternion()
		var to := Basis(_lid_axis, _lid_open if open else 0.0).get_rotation_quaternion()
		var tw := create_tween()
		tw.tween_method(func(t: float) -> void: _lid.basis = Basis(from.slerp(to, t)), 0.0, 1.0, 0.5).set_trans(Tween.TRANS_BACK if open else Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
