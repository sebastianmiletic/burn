class_name BuriedCache
extends Entity
## A treasure chest buried under a map's X. Hidden in the ground until the
## hunter digs down to its lid (mining sculpts the terrain); then it glints and
## can be opened by its owner. The server rolls the loot.

var owner_peer := 0
var hunt_id := -1
var tier := 1
var opened := false
var exposed := false
var _lid: Node3D
var _hoard: Node3D
var _glint: GPUParticles3D
var _light: OmniLight3D
var _check := 0.0
var _opened_at := -1.0


func _init() -> void:
	kind = "act_cache"
	team = Team.NEUTRAL
	hit_radius = 0.5
	hit_height = 0.8
	body.collides = false
	body.gravity = 0.0


func on_spawned(data: Dictionary) -> void:
	owner_peer = int(data.get("owner", 0))
	hunt_id = int(data.get("hunt", -1))
	tier = int(data.get("tier", 1))
	var model := Node3D.new()
	model.name = "Chest"
	add_child(model)
	model.rotation.y = float(int(data.get("seed", 0)) % 628) / 100.0
	_lid = ActivityModels.chest(model, int(data.get("seed", 0)))
	_hoard = Node3D.new()
	_hoard.visible = false
	model.add_child(_hoard)
	ActivityModels.hoard(_hoard)
	_glint = ModelKit.embers(self, 14, Vector3(0.4, 0.1, 0.3), 1.4, 0.05, 0.6)
	_glint.position.y = 0.6
	_glint.emitting = false
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.8, 0.45)
	_light.light_energy = 0.0
	_light.omni_range = 4.0
	_light.position.y = 0.9
	add_child(_light)


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.3
	var was := exposed
	exposed = is_exposed()
	if exposed != was:
		_glint.emitting = exposed and not opened
		_light.light_energy = 1.2 if exposed and not opened else 0.0
		if exposed and not opened:
			Audio.play("gem", global_position + Vector3(0, 0.7, 0), -4.0)
	if is_server() and opened and _opened_at >= 0.0 and Time.get_ticks_msec() / 1000.0 - _opened_at > 45.0:
		_opened_at = -1.0
		world().despawn_entity(self)


## Dug out: open air just above the lid.
func is_exposed() -> bool:
	var vw := voxels()
	if vw == null or not vw.is_area_loaded(global_position):
		return false
	var top := global_position + Vector3(0, 0.95, 0)
	return vw.field(top) < 0.5 and vw.field(top + Vector3(0, 0.45, 0)) < 0.5


func interact_prompt(_p: Player) -> String:
	if opened or not exposed:
		return ""
	if owner_peer != multiplayer.get_unique_id():
		return "Someone's treasure chest"
	return "Open the treasure chest"


func local_interact(p: Player) -> void:
	if owner_peer != multiplayer.get_unique_id():
		Events.notify.emit("This chest belongs to whoever followed its map.", "info")
		return
	world().replicator.request_interact(net_id)
	if p.camera != null:
		p.camera.add_trauma(0.08)


func server_interact(p: Player) -> void:
	if opened or p.peer_id != owner_peer or not is_exposed():
		return
	opened = true
	_opened_at = Time.get_ticks_msec() / 1000.0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var loot := TreasureHunt.roll_loot(tier, rng)
	var w := world()
	w.replicator.give_gold_to(p.peer_id, int(loot["gold"]))
	w.replicator.give_xp_to(p.peer_id, int(loot["xp"]), "")
	for item: String in loot["items"]:
		w.replicator.give_item_to(p.peer_id, item, int(loot["items"][item]))
	w.replicator.broadcast_entity_event(net_id, "opened", int(loot["gold"]))


func on_event(event: String, arg: Variant) -> void:
	if event != "opened":
		return
	opened = true
	_glint.emitting = false
	_light.light_energy = 2.0
	_hoard.visible = true
	Audio.play("chest", global_position + Vector3(0, 0.6, 0))
	Audio.play("coin", global_position + Vector3(0, 0.6, 0), 0.0, 0.9)
	var tw := create_tween()
	tw.tween_property(_lid, "rotation:x", -1.85, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_light, "light_energy", 0.6, 2.0)
	ModelKit.burst(self, Vector3(0, 0.9, 0), 40, 0.35, 4.0, 0.08, Color(1.0, 0.95, 0.6), Color(1.0, 0.7, 0.2), 0.9)
	if world() != null:
		var acts := ActivityDirector.of(world())
		if acts != null:
			acts.treasure.on_cache_opened(self)
		if owner_peer == multiplayer.get_unique_id() and arg != null:
			Events.notify.emit("The chest held %d gold and more." % int(arg), "loot")
