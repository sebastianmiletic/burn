class_name OgygiaRaft
extends Entity
## The raft Calypso helped you lash together, waiting at the water's edge.
## Boarding it sails you home (Ogygia.depart).

var _bob := 0.0


func _init() -> void:
	kind = "ogygia_raft"
	team = Team.NEUTRAL
	hit_radius = 1.4
	body.collides = false
	body.gravity = 0.0
	max_health = 9999.0
	health = max_health


func on_spawned(_data: Dictionary) -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.32, 0.2)
	wood.roughness = 0.85
	var rope := StandardMaterial3D.new()
	rope.albedo_color = Color(0.7, 0.62, 0.45)
	var sail_mat := StandardMaterial3D.new()
	sail_mat.albedo_color = Color(0.9, 0.86, 0.76)
	sail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 7:
		var log := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.16
		c.bottom_radius = 0.17
		c.height = 3.4 - absf(i - 3) * 0.12
		c.radial_segments = 8
		log.mesh = c
		log.material_override = wood
		log.rotation = Vector3(PI * 0.5, 0, 0)
		log.position = Vector3((i - 3) * 0.32, 0.0, 0)
		add_child(log)
	for zc: float in [-1.1, 0.0, 1.1]:
		var cross := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(2.4, 0.1, 0.16)
		cross.mesh = b
		cross.material_override = rope
		cross.position = Vector3(0, 0.17, zc)
		add_child(cross)
	var mast := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 0.05
	m.bottom_radius = 0.07
	m.height = 3.2
	mast.mesh = m
	mast.material_override = wood
	mast.position = Vector3(0, 1.7, -0.3)
	add_child(mast)
	var sail := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.9, 2.0)
	sail.mesh = q
	sail.material_override = sail_mat
	sail.position = Vector3(0, 2.1, -0.24)
	add_child(sail)


func _process(delta: float) -> void:
	_bob += delta
	rotation = Vector3(sin(_bob * 0.9) * 0.025, yaw, sin(_bob * 0.7 + 1.0) * 0.03)


func interact_prompt(p: Player) -> String:
	return "Sail home on the raft" if p != null and not p.dead else ""


func local_interact(_p: Player) -> void:
	var w := world()
	if w != null:
		Ogygia.depart(w)
