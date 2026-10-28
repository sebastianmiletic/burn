class_name WellEntity
extends Entity
## A village well you can draw from (E): the bucket rattles down on its rope,
## splashes, and is wound back up with whatever it brought from the bottom.
## Mostly water and junk, sometimes something useful, very rarely a gem, a
## ring or a sodden treasure map. Each player can draw from a given well once
## every COOLDOWN seconds (server-side, per well and player name).
##
## The rope and bucket are drawn here (the well's stonework is village
## architecture, VillageProps.well); positions are relative to the well centre.

const COOLDOWN := 240.0
const DOWN := 1.3
const BOTTOM := 0.5
const UP := 1.5
const ROPE_TOP := Vector3(0.1, 1.66, 0.0)
const BUCKET_REST := 0.62
const BUCKET_LOW := -0.62

## [weight, item, min, max]: about 80 % junk, 18 % useful, 2 % rare.
const TABLE := [
	[30.0, "well_water", 1, 1], [12.0, "pebbles", 2, 5], [9.0, "old_boot", 1, 1], [11.0, "rusty_coin", 1, 3],
	[5.0, "coal", 1, 3], [4.0, "iron_ore", 1, 2], [3.0, "copper_ore", 1, 3], [3.0, "potion_health", 1, 1], [3.0, "ancient_coin", 1, 1],
	[2.0, "glass_vial", 1, 2], [2.0, "torch", 2, 3],
	[0.6, "silver_ring", 1, 1], [0.5, "ruby", 1, 1], [0.5, "sapphire", 1, 1], [0.4, "amethyst", 1, 1], [0.4, "pearl", 1, 1], [0.5, "treasure_map", 1, 1],
]

var well_key := ""
var _used := {}            # server: player name -> time used
var _local_used := -1e9    # this client's own cooldown (for the prompt)
var _busy := 0.0
var _rope: MeshInstance3D
var _bucket: Node3D
var _t := -1.0


func _init() -> void:
	kind = "well"
	team = Team.NEUTRAL
	hit_radius = 1.3
	hit_height = 1.0
	body.collides = false
	body.gravity = 0.0


func on_spawned(data: Dictionary) -> void:
	well_key = String(data.get("key", ""))
	var m := ArchMesh.new()
	m.mat(ArchMaterials.L.BOARDS, VillageProps.OAK, 0.3)
	m.lathe(Vector3.ZERO, PackedVector2Array([Vector2(0.14, 0.0), Vector2(0.17, 0.3), Vector2(0.155, 0.3), Vector2(0.13, 0.03), Vector2(0.0, 0.03)]), 10, true, false)
	m.mat(ArchMaterials.L.IRON, Color(0.7, 0.7, 0.7), 0.0)
	m.lathe(Vector3(0, 0.03, 0), PackedVector2Array([Vector2(0.148, 0.0), Vector2(0.15, 0.03)]), 10, false, false)
	m.lathe(Vector3(0, 0.24, 0), PackedVector2Array([Vector2(0.168, 0.0), Vector2(0.17, 0.03)]), 10, false, false)
	m.cylinder(Vector3(-0.16, 0.3, 0), Vector3(0.0, 0.42, 0), 0.008, -1.0, 4)
	m.cylinder(Vector3(0.16, 0.3, 0), Vector3(0.0, 0.42, 0), 0.008, -1.0, 4)
	_bucket = Node3D.new()
	var bi := MeshInstance3D.new()
	bi.mesh = m.to_mesh(ArchMaterials.main())
	_bucket.add_child(bi)
	add_child(_bucket)
	var rope := ArchMesh.new()
	rope.mat(ArchMaterials.L.LINEN, Color(0.7, 0.6, 0.45), 0.1)
	rope.cylinder(Vector3.ZERO, Vector3(0, -1.0, 0), 0.012, -1.0, 5)
	_rope = MeshInstance3D.new()
	_rope.mesh = rope.to_mesh(ArchMaterials.main())
	_rope.position = ROPE_TOP
	add_child(_rope)
	_pose(BUCKET_REST)


func _pose(bucket_y: float) -> void:
	_bucket.position = Vector3(ROPE_TOP.x, bucket_y, 0.0)
	_rope.scale = Vector3(1, maxf(0.05, ROPE_TOP.y - bucket_y - 0.42), 1)


func interact_prompt(_p: Player) -> String:
	if _t >= 0.0:
		return ""
	var left := COOLDOWN - (Time.get_ticks_msec() / 1000.0 - _local_used)
	if left > 0.0:
		return "The bucket comes up empty for now (%ds)" % ceili(left)
	return "Lower the bucket"


func local_interact(_p: Player) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _local_used < COOLDOWN or _t >= 0.0:
		Events.notify.emit("Give the well a while to settle.", "info")
		return
	_local_used = now
	world().replicator.request_interact(net_id)


func server_interact(p: Player) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var who := p.display_name if p.display_name != "" else str(p.peer_id)
	if _busy > now or now - float(_used.get(who, -1e9)) < COOLDOWN:
		return
	_used[who] = now
	_busy = now + DOWN + BOTTOM + UP
	world().replicator.broadcast_entity_event(net_id, "draw", p.peer_id)
	var peer := p.peer_id
	get_tree().create_timer(DOWN + BOTTOM + UP).timeout.connect(func() -> void:
		if not is_instance_valid(self):
			return
		var find := roll(randf())
		var w := world()
		if w != null:
			w.replicator.give_item_to(peer, String(find[0]), randi_range(int(find[1]), int(find[2]))))


## Weighted pick for a roll in 0..1: [item, min count, max count].
static func roll(r: float) -> Array:
	var total := 0.0
	for e: Array in TABLE:
		total += float(e[0])
	var x := r * total
	for e: Array in TABLE:
		x -= float(e[0])
		if x <= 0.0:
			return [String(e[1]), int(e[2]), int(e[3])]
	return ["well_water", 1, 1]


func on_event(event: String, arg: Variant) -> void:
	if event != "draw":
		return
	_t = 0.0
	if world() != null and world().local_player != null and int(arg) == world().local_player.peer_id:
		_local_used = Time.get_ticks_msec() / 1000.0
	Audio.play("chest", global_position + Vector3(0, 1.7, 0), -10.0, 0.6)


func _process(delta: float) -> void:
	if _t < 0.0 or _bucket == null:
		return
	var prev := _t
	_t += delta
	var y := BUCKET_REST
	if _t < DOWN:
		var f := _t / DOWN
		y = lerpf(BUCKET_REST, BUCKET_LOW, f * f)
	elif _t < DOWN + BOTTOM:
		y = BUCKET_LOW + sin((_t - DOWN) * 18.0) * 0.02
		if prev < DOWN:
			Audio.play("splash", global_position + Vector3(0, -0.5, 0), -6.0, 1.2)
	elif _t < DOWN + BOTTOM + UP:
		var f := (_t - DOWN - BOTTOM) / UP
		y = lerpf(BUCKET_LOW, BUCKET_REST, 1.0 - (1.0 - f) * (1.0 - f))
		_bucket.rotation.y = sin(_t * 3.0) * 0.3
	else:
		_t = -1.0
		_bucket.rotation.y = 0.0
	_pose(y)
