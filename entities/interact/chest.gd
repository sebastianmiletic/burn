class_name Chest
extends Entity
## A loot chest. Opened once per world (saved); spills loot by tier.

const LOOT := {
	1: [["potion_health", 0.7, 1, 2], ["torch", 0.8, 3, 6], ["coal", 0.6, 2, 5], ["iron_ore", 0.5, 1, 3], ["bread", 0.6, 1, 3]],
	2: [["potion_health", 0.9, 1, 3], ["potion_greater", 0.4, 1, 1], ["gold_ore", 0.6, 2, 4], ["ember_crystal", 0.4, 1, 2], ["iron_ore", 0.6, 2, 5], ["lantern", 0.4, 1, 2]],
	3: [["potion_greater", 0.9, 1, 2], ["gold_ore", 0.8, 3, 6], ["ember_crystal", 0.7, 2, 4], ["obsidian", 0.5, 2, 4], ["sword_ember", 0.25, 1, 1], ["pickaxe_iron", 0.35, 1, 1]],
}

var chest_key := ""
var tier := 1
var opened := false
var _lid: Node3D


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
	var wood := MaterialLibrary.stone(&"iron")
	var planks := ShaderMaterial.new()
	planks.shader = MaterialLibrary.STONE
	planks.set_shader_parameter(&"color_light", Color(0.5, 0.34, 0.18))
	planks.set_shader_parameter(&"color_dark", Color(0.3, 0.2, 0.1))
	planks.set_shader_parameter(&"moss_amount", 0.0)
	planks.set_shader_parameter(&"ascii_id", AsciiMaterialId.SOLID)
	_box(Vector3(1.0, 0.55, 0.65), Vector3(0, 0.275, 0), planks, self)
	_box(Vector3(1.04, 0.08, 0.69), Vector3(0, 0.45, 0), wood, self)
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.55, -0.32)
	add_child(_lid)
	_box(Vector3(1.0, 0.25, 0.65), Vector3(0, 0.12, 0.32), planks, _lid)
	_box(Vector3(0.14, 0.18, 0.06), Vector3(0, 0.0, 0.66), MaterialLibrary.emissive(Color(1.0, 0.75, 0.3), 1.5), _lid)
	_set_open_visual(opened)


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


func _set_open_visual(open: bool) -> void:
	if _lid != null:
		_lid.rotation.x = -1.9 if open else 0.0


func interact_prompt(_p: Player) -> String:
	return "" if opened else "Open chest"


func local_interact(_p: Player) -> void:
	world().replicator.request_interact(net_id)


func server_interact(_p: Player) -> void:
	if opened:
		return
	opened = true
	world().opened_chests[chest_key] = true
	world().replicator.broadcast_entity_event(net_id, "opened")
	# Plus books (spells, potions, crafting), arrows and mana potions (ArcanaItems).
	for entry: Array in LOOT.get(tier, LOOT[1]) + ArcanaItems.CHEST_LOOT.get(tier, []):
		if randf() < float(entry[1]):
			world().drop_item(global_position + Vector3(0, 0.9, 0), entry[0], randi_range(int(entry[2]), int(entry[3])), dimension)
	world().replicator.give_gold_to(_p.peer_id, randi_range(5, 15) * tier)


func on_event(event: String, _arg: Variant) -> void:
	if event == "opened":
		opened = true
		Audio.play("chest", global_position)
		var tw := create_tween()
		tw.tween_property(_lid, "rotation:x", -1.9, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
