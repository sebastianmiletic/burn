class_name LairDecor
extends Entity
## Set dressing for creature lairs, spawned through the location `spawns`
## list as {"type": "decor", "decor": <name>, "pos", "yaw", "size"} so it
## replicates like any entity (the visuals are built from the spawn data on
## every machine): spider webs and webbed cocoons, glowing egg sacs, a
## witch's bubbling cauldron, bone totems, bone piles, the ribcage of some
## vast sea creature, braziers. Never targeted, never ticks.

var decor := ""
var _root: Node3D


func _ready() -> void:
	team = Team.NEUTRAL
	hit_radius = 0.0
	hit_height = 0.0
	body.collides = false
	body.fly = true


func take_damage(_amount: float, _source_id := 0, _damage_kind := "hit") -> float:
	return 0.0


func on_spawned(data: Dictionary) -> void:
	decor = String(data.get("decor", "bones"))
	display_name = decor
	yaw = float(data.get("yaw", 0.0))
	rotation.y = yaw
	var size := float(data.get("size", 1.0))
	var seed_value := int(data.get("seed", net_id))
	_root = Node3D.new()
	add_child(_root)
	match decor:
		"web":
			_web(size, float(data.get("tilt", 0.0)), seed_value)
		"cocoon":
			_cocoon(size, seed_value)
		"eggs":
			_eggs(size, seed_value)
		"cauldron":
			_cauldron(size)
		"totem":
			_totem(size, seed_value)
		"ribs":
			_ribs(size, seed_value)
		"brazier":
			_brazier(size, Color(data.get("color", Color(1.0, 0.55, 0.2))))
		_:
			_bones(size, seed_value)


func server_tick(_delta: float) -> void:
	pass


static func silk() -> ShaderMaterial:
	return CreatureSkin.smooth(Color(0.88, 0.88, 0.84), Color(0.8, 0.8, 0.76), {"roughness": 0.4, "rim": 0.8, "specular_amount": 0.6, "ascii_id": AsciiMaterialId.CLOTH})


## Radial orb web: spokes and a spiral, a few strands broken.
func _web(r: float, tilt: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var holder := Node3D.new()
	holder.rotation = Vector3(tilt, 0, 0)
	_root.add_child(holder)
	var mat := silk()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = ModelKit.cylinder(0.012, 0.012, 1.0, 4)
	var segs: Array = []
	var spokes := 12
	for i in spokes:
		var a := TAU * float(i) / spokes + rng.randf_range(-0.08, 0.08)
		segs.append([Vector3.ZERO, Vector3(cos(a), sin(a), 0) * r * rng.randf_range(0.85, 1.0)])
	var turns := 9
	for t in turns:
		var rad := r * (0.15 + 0.85 * float(t) / turns)
		for i in spokes:
			if rng.randf() < 0.08:
				continue
			var a0 := TAU * float(i) / spokes
			var a1 := TAU * float(i + 1) / spokes
			segs.append([Vector3(cos(a0), sin(a0), 0) * rad, Vector3(cos(a1), sin(a1), 0) * rad * 1.02])
	mm.instance_count = segs.size()
	for i in segs.size():
		var a: Vector3 = segs[i][0]
		var b: Vector3 = segs[i][1]
		var y := b - a
		var len := y.length()
		var yn := y / maxf(len, 0.001)
		var x := yn.cross(Vector3.BACK).normalized()
		var z := x.cross(yn)
		mm.set_instance_transform(i, Transform3D(Basis(x, yn * len, z), (a + b) * 0.5))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)


func _cocoon(s: float, seed_value: int) -> void:
	var mat := silk()
	var body_mesh := OrganicMesh.blob("decor_cocoon_%d" % (seed_value % 3), Vector3(0.35, 0.95, 0.32) * s, 0.25, seed_value % 3 + 2, 12)
	ModelKit.part(_root, body_mesh, mat, Vector3(0, 1.6 * s, 0), Vector3(0, 0, 8))
	ModelKit.part(_root, ModelKit.cylinder(0.015, 0.015, 3.0 * s, 4), mat, Vector3(0, 4.0 * s, 0))
	# A skeletal hand poking out.
	ModelKit.part(_root, OrganicMesh.bezier("decor_finger", Vector3.ZERO, Vector3(0.05, -0.1, 0), Vector3(0.08, -0.22, 0.02), 0.02, 0.008, 5, 4), CreatureSkin.keratin(Color(0.82, 0.78, 0.66)), Vector3(0.25 * s, 1.1 * s, -0.1 * s))


func _eggs(s: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mat := CreatureSkin.membrane(Color(0.85, 0.8, 0.66), {"glow_mode": 1, "glow_color": Color(0.75, 0.45, 1.0), "glow_amount": 0.4,
		"glow_energy": 2.5, "glow_pulse": 1.0, "backlight": 1.6})
	for i in 9:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 1.2) * s
		var sz := rng.randf_range(0.25, 0.45) * s
		ModelKit.part(_root, OrganicMesh.blob("decor_egg_%d" % (i % 4), Vector3(0.8, 1.0, 0.8), 0.15, 60 + i % 4, 10), mat, Vector3(cos(a) * r, sz * 0.8, sin(a) * r), Vector3.ZERO, Vector3.ONE * sz)
	_light(Color(0.7, 0.45, 1.0), 1.2, 6.0 * s, Vector3(0, 0.8 * s, 0))


func _cauldron(s: float) -> void:
	var iron := CreatureSkin.rock(Color(0.12, 0.12, 0.12), {"roughness": 0.45, "pattern_scale": 6.0, "specular_amount": 0.6})
	ModelKit.part(_root, OrganicMesh.profile("decor_cauldron", Vector3(0, 0.15, 0), Vector3(0, 1.15, 0),
		[[0.0, 0.25, 0.25], [0.12, 0.62, 0.62], [0.55, 0.78, 0.78], [0.9, 0.62, 0.62], [1.0, 0.66, 0.66]], 18, 10, Vector3.BACK), iron, Vector3.ZERO, Vector3.ZERO, Vector3.ONE * s)
	ModelKit.part(_root, ModelKit.cylinder(0.6, 0.6, 0.05, 18), ModelKit.glow(Color(0.45, 1.0, 0.3), 4.0, 0.5), Vector3(0, 1.05 * s, 0), Vector3.ZERO, Vector3.ONE * s)
	for i in 3:
		var a := TAU * float(i) / 3.0
		ModelKit.part(_root, ModelKit.cylinder(0.05, 0.07, 0.35, 6), iron, Vector3(cos(a) * 0.45, 0.1, sin(a) * 0.45) * s)
	var bubbles := CreatureFx.emitter(_root, "hex", 30, Vector3(0.45, 0.05, 0.45) * s)
	bubbles.position = Vector3(0, 1.1 * s, 0)
	bubbles.emitting = true
	var fire := ModelKit.embers(_root, 30, Vector3(0.4, 0.05, 0.4) * s, 0.8, 0.3, 1.5)
	fire.position = Vector3(0, 0.1, 0)
	fire.emitting = true
	_light(Color(0.5, 1.0, 0.4), 2.0, 9.0 * s, Vector3(0, 1.6 * s, 0))


func _totem(s: float, seed_value: int) -> void:
	var wood := CreatureSkin.hide(Color(0.26, 0.2, 0.14), Color(0.2, 0.15, 0.1), {"pattern_scale": 6.0})
	var bone := CreatureSkin.keratin(Color(0.82, 0.78, 0.66))
	ModelKit.part(_root, OrganicMesh.bezier("decor_totem_pole_%d" % (seed_value % 2), Vector3.ZERO, Vector3(0.1, 1.3, 0.05), Vector3(0.0, 2.8, 0.0), 0.12, 0.07, 8, 7), wood, Vector3.ZERO, Vector3.ZERO, Vector3.ONE * s)
	ModelKit.part(_root, OrganicMesh.blob("decor_skull", Vector3(0.16, 0.17, 0.19), 0.06, 31, 12), bone, Vector3(0, 2.9 * s, 0), Vector3.ZERO, Vector3.ONE * s)
	for side: float in [-1.0, 1.0]:
		ModelKit.part(_root, ModelKit.sphere(0.035, 6), ModelKit.glow(Color(0.5, 1.0, 0.4), 6.0, 0.4), Vector3(side * 0.06, 2.92, -0.15) * s)
		ModelKit.part(_root, OrganicMesh.bezier("decor_horn_%d" % int(side), Vector3.ZERO, Vector3(side * 0.2, 0.15, 0.05), Vector3(side * 0.3, 0.35, 0.15), 0.04, 0.006, 6, 5), bone, Vector3(side * 0.12, 3.0, 0) * s)
	for i in 4:
		var y := 1.6 + i * 0.25
		ModelKit.part(_root, ModelKit.cylinder(0.01, 0.01, 0.4, 4), ModelKit.cloth(Color(0.3, 0.2, 0.15)), Vector3(0.14, y - 0.2, 0) * s)
		ModelKit.part(_root, ModelKit.sphere(0.04, 6), bone, Vector3(0.14, y - 0.42, 0) * s)


func _ribs(s: float, seed_value: int) -> void:
	# The ribcage of something vast, half buried: arching ribs and a spine.
	var bone := CreatureSkin.keratin(Color(0.78, 0.75, 0.66), {"pattern": CreatureSkin.Pattern.ROCK, "pattern_scale": 1.5, "roughness": 0.85})
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in 7:
		var z := (float(i) - 3.0) * 1.6 * s
		var h := (5.0 - absf(float(i) - 2.0) * 0.6) * s
		for side: float in [-1.0, 1.0]:
			if rng.randf() < 0.15:
				continue
			var key := "decor_rib_%d_%d" % [i, int(side)]
			var rib := OrganicMesh.bezier(key, Vector3.ZERO, Vector3(side * 2.6, h * 0.7, 0) * 1.0, Vector3(side * 1.2, h, 0.3), 0.28, 0.09, 10, 7)
			ModelKit.part(_root, rib, bone, Vector3(side * 0.5 * s, -0.4, z), Vector3(0, 0, 0), Vector3.ONE)
	ModelKit.part(_root, OrganicMesh.profile("decor_spine", Vector3(0, 0, -6.0 * s), Vector3(0, 0, 6.0 * s), [[0.0, 0.2, 0.2], [0.5, 0.45, 0.4], [1.0, 0.15, 0.15]], 10, 12), bone, Vector3(0, 0.0, 0))
	ModelKit.part(_root, OrganicMesh.blob("decor_skull_big", Vector3(1.6, 1.1, 2.4) * s, 0.15, 99, 14), bone, Vector3(0.5, 0.2, -8.0 * s), Vector3(10, 20, -15))


func _bones(s: float, seed_value: int) -> void:
	var bone := CreatureSkin.keratin(Color(0.8, 0.76, 0.64))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in 7:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.7) * s
		ModelKit.part(_root, ModelKit.capsule(0.05, rng.randf_range(0.4, 0.7), 6), bone, Vector3(cos(a) * r, 0.06, sin(a) * r), Vector3(90, rng.randf() * 360, rng.randf_range(-20, 20)), Vector3.ONE * s)
	ModelKit.part(_root, OrganicMesh.blob("decor_skull", Vector3(0.16, 0.17, 0.19), 0.06, 31, 12), bone, Vector3(0.2, 0.15, 0.1) * s, Vector3(0, rng.randf() * 360, 20), Vector3.ONE * s)


func _brazier(s: float, color: Color) -> void:
	var iron := CreatureSkin.rock(Color(0.15, 0.13, 0.12), {"roughness": 0.5, "pattern_scale": 5.0})
	ModelKit.part(_root, ModelKit.cylinder(0.08, 0.12, 1.1, 8), iron, Vector3(0, 0.55, 0) * s)
	ModelKit.part(_root, OrganicMesh.profile("decor_bowl", Vector3(0, 1.05, 0), Vector3(0, 1.45, 0), [[0.0, 0.15, 0.15], [0.4, 0.42, 0.42], [1.0, 0.5, 0.5]], 14, 6, Vector3.BACK), iron, Vector3.ZERO, Vector3.ZERO, Vector3.ONE * s)
	var fire := ModelKit.embers(_root, 40, Vector3(0.25, 0.1, 0.25) * s, 0.9, 0.35 * s, 1.8)
	fire.position = Vector3(0, 1.45 * s, 0)
	fire.emitting = true
	_light(color, 2.5, 10.0 * s, Vector3(0, 1.9 * s, 0))


func _light(color: Color, energy: float, radius: float, pos: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = radius
	l.shadow_enabled = false
	l.light_volumetric_fog_energy = 1.5
	l.position = pos
	_root.add_child(l)
