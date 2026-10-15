class_name ItemDrop
extends Entity
## An item lying in the world: the item's own model that bounces out,
## settles, bobs, and is picked up by walking over it.

var item_id := ""
var count := 1
var _mesh: Node3D
var _age := 0.0
var _pickup_cooldown := 0.0


func _init() -> void:
	kind = "drop"
	team = Team.NEUTRAL
	hit_radius = 0.2
	hit_height = 0.4
	body.half_extents = Vector3(0.15, 0.15, 0.15)
	body.can_step = false


func on_spawned(data: Dictionary) -> void:
	item_id = String(data.get("item", ""))
	count = int(data.get("count", 1))
	body.velocity = data.get("vel", Vector3.ZERO)
	_mesh = HeldItems.display(item_id)
	if _mesh == null:
		var box := MeshInstance3D.new()
		box.mesh = BoxMesh.new()
		(box.mesh as BoxMesh).size = Vector3.ONE * 0.3
		box.material_override = MaterialLibrary.emissive(ItemDB.color(item_id), 1.6)
		_mesh = box
	var c := ItemDB.color(item_id)
	add_child(_mesh)
	if ItemDB.category(item_id) == "key":
		var l := OmniLight3D.new()
		l.light_color = c
		l.light_energy = 1.5
		l.omni_range = 5.0
		l.position.y = 0.5
		add_child(l)


func server_tick(delta: float) -> void:
	_age += delta
	body.step(self, voxels(), delta)
	if body.on_floor:
		body.velocity.x *= 0.8
		body.velocity.z *= 0.8
	if _age > 300.0:
		world().despawn_entity(self)


func _process(delta: float) -> void:
	if _mesh == null:
		return
	_age += 0.0 if is_server() else delta
	var t := Time.get_ticks_msec() / 1000.0
	_mesh.position.y = 0.3 + sin(t * 2.5 + net_id) * 0.08
	_mesh.rotation.y = t * 1.6
	var w := world()
	if w == null or w.local_player == null or w.local_player.dead or w.local_player.dimension != dimension:
		return
	_pickup_cooldown -= delta
	if _pickup_cooldown <= 0.0 and w.local_player.global_position.distance_to(global_position) < 1.7:
		_pickup_cooldown = 0.5
		w.replicator.request_pickup(net_id)
