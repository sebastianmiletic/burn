class_name EnvironmentDetails
extends Node3D
## Small, bounded scenery sets. No per-voxel nodes, no collision on decorative
## plants. Geyser damage is resolved by the host, never by visual particles.
var _timer := 0.0
var _root: Node3D
var _key := ""
var _steam: Array[GPUParticles3D] = []
var _warned := ""

func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0:
		return
	_timer = 0.5
	var w := GameWorld.instance
	if w == null or w.local_player == null:
		return
	var now := Net.server_time()
	if Net.is_server():
		for p in w.players_in(0):
			var gen := w.gen_for(0)
			if gen.revision < 2 or p.dead or p.global_position.y >= -8:
				continue
			var r := CaveBiomes.region(p.global_position, gen.world_seed)
			if int(r["kind"]) != CaveBiomes.Kind.GEYSER or fmod(now + int(r["seed"]) % 8, 10.0) < 7.0:
				continue
			for vent in _vents(r):
				var d := p.global_position - vent
				if Vector2(d.x, d.z).length() < 2.2 and d.y > -1 and d.y < 10:
					w.damage(p, 4.0, 0, "steam")
	var pos := w.local_player.global_position
	var gen := w.gen_for(w.local_dimension)
	var cave := w.local_dimension == 0 and gen.revision >= 2 and pos.y < -8
	var r := CaveBiomes.region(pos, gen.world_seed)
	var key := "%d:%s:%s" % [w.local_dimension, str(r["key"]) if cave else str(Vector2i(pos.x / 48, pos.z / 48)), str(cave)]
	if key != _key:
		_key = key
		_rebuild(w, pos, cave, r)
	if cave:
		var kind := CaveBiomes.kind_at(pos, gen.world_seed)
		var label := "%s:%d" % [str(r["key"]), kind]
		if label != _warned:
			_warned = label
			Events.notify.emit(CaveBiomes.NAMES[kind] + (": no creatures, finite riches." if kind == CaveBiomes.Kind.CRYSTAL_REFUGE else (": steam surges every ten seconds. Keep clear of the vents." if kind == CaveBiomes.Kind.GEYSER else "")), "info")
			w.quests.on_event("cave", str(kind))
	var phase := fmod(now + int(r["seed"]) % 8, 10.0)
	for emitter in _steam:
		emitter.amount_ratio = 1.0 if phase >= 7 else 0.08

static func _vents(r: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for off: Vector3 in [Vector3(0, -19, 0), Vector3(16, -17.5, 5), Vector3(-12, -17.5, -13)]:
		out.append((r["center"] as Vector3) + off)
	return out

func _rebuild(w: GameWorld, pos: Vector3, cave: bool, r: Dictionary) -> void:
	if _root != null:
		_root.queue_free()
	_steam.clear()
	_root = Node3D.new()
	add_child(_root)
	if DisplayServer.get_name() == "headless":
		return
	if cave:
		var kind := int(r["kind"])
		# Luminous fungi and crystals light their surroundings with a few soft,
		# shadowless pools of the biome's colour (a small per-quality budget).
		var glow: Color = CaveBiomes.PALETTES.get(kind, CaveBiomes.PALETTES[CaveBiomes.Kind.KARST])["glow"]
		var lights_left: int = [0, 2, 4, 6][int(Settings.get_value("graphics", "quality"))]
		if kind == CaveBiomes.Kind.GEYSER:
			for vent in _vents(r):
				_add_mesh(ModelKit.cylinder(1.1, 1.8, 1.2, 16), vent, ModelKit.mat(Color(0.23, 0.22, 0.2)))
				_make_steam(vent)
				if lights_left > 0:
					lights_left -= 1
					_add_glow_light(vent + Vector3.UP * 1.4, glow, 0.6, 7.0)
		else:
			var rng := RandomNumberGenerator.new()
			rng.seed = int(r["seed"])
			var luminous := kind in [CaveBiomes.Kind.FUNGAL, CaveBiomes.Kind.FROST, CaveBiomes.Kind.CRYSTAL_REFUGE]
			for i in 36:
				var angle := rng.randf() * TAU
				var radius := rng.randf_range(3, 34)
				var p: Vector3 = r["center"] + Vector3(cos(angle) * radius, -20 * sqrt(1.0 - pow(radius / 48, 2)), sin(angle) * radius)
				var height := rng.randf_range(0.6, 2.6)
				if kind == CaveBiomes.Kind.FUNGAL:
					_add_mesh(ModelKit.cylinder(0.08, 0.16, height, 8), p + Vector3.UP * height * 0.5, ModelKit.mat(Color(0.45, 0.5, 0.33)))
					var cap := _add_mesh(ModelKit.sphere(0.7, 12), p + Vector3.UP * height, ModelKit.glow(Color(0.18, 0.65, 0.5), 0.75))
					cap.scale.y = 0.35
				else:
					var col := Color(0.4, 0.65, 0.85) if kind == CaveBiomes.Kind.FROST else (Color(0.55, 0.28, 0.7) if kind == CaveBiomes.Kind.CRYSTAL_REFUGE else Color(0.55, 0.51, 0.4))
					# Every third crystal glows faintly from within; the rest are
					# glossy and catch that light.
					var m: Material = ModelKit.glow(glow * 0.6, 0.7) if luminous and i % 3 == 0 else ModelKit.mat(col, AsciiMaterialId.SOLID, 0.3 if luminous else 0.8)
					_add_mesh(ModelKit.cone(0.35, height, 7), p + Vector3.UP * height * 0.5, m)
				if luminous and i % 6 == 0 and lights_left > 0:
					lights_left -= 1
					_add_glow_light(p + Vector3.UP * (height + 0.6), glow, 0.7, 9.0)
	elif w.local_dimension == 0 and pos.y < WorldGen.SEA_LEVEL + 15:
		_ocean(w.gen_for(0), pos)

func _add_glow_light(at: Vector3, color: Color, energy: float, light_range: float) -> void:
	var l := OmniLight3D.new()
	l.position = at
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = 1.8
	l.light_specular = 0.25
	l.shadow_enabled = false
	l.light_volumetric_fog_energy = 0.6
	l.distance_fade_enabled = true
	l.distance_fade_begin = 70.0
	l.distance_fade_length = 20.0
	_root.add_child(l)

func _add_mesh(mesh: Mesh, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.visibility_range_end = 105
	_root.add_child(mi)
	return mi

func _make_steam(at: Vector3) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = [24, 40, 64, 80][int(Settings.get_value("graphics", "quality"))]
	particles.lifetime = 2.0
	particles.position = at
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 12
	pm.initial_velocity_min = 5
	pm.initial_velocity_max = 9
	pm.gravity = Vector3(0, 1, 0)
	pm.scale_min = 0.2
	pm.scale_max = 0.8
	pm.color = Color(0.74, 0.8, 0.78, 0.5)
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.6))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	particles.process_material = pm
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://world/materials/steam.gdshader")
	mesh.material = mat
	particles.draw_pass_1 = mesh
	particles.visibility_aabb = AABB(Vector3(-4, -2, -4), Vector3(8, 25, 8))
	_root.add_child(particles)
	_steam.append(particles)

func _ocean(gen: WorldGen, pos: Vector3) -> void:
	var cell := Vector2i(pos.x / 48, pos.z / 48)
	var transforms: Array[Transform3D] = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := cell + Vector2i(dx, dz)
			var rng := RandomNumberGenerator.new()
			rng.seed = WorldGen._hash3(key.x, 0, key.y, gen.world_seed)
			for i in 20:
				var x := key.x * 48 + rng.randf_range(0, 48)
				var z := key.y * 48 + rng.randf_range(0, 48)
				var ground := gen.ground_level(x, z)
				if ground > WorldGen.SEA_LEVEL - 3 or not gen.in_bounds(int(x), int(z)):
					continue
				var height := minf(rng.randf_range(2, 7), WorldGen.SEA_LEVEL - ground - 1)
				transforms.append(Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(1, height, 1)), Vector3(x, ground, z)))
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var plant := QuadMesh.new()
	plant.size = Vector2(0.9, 1)
	plant.center_offset.y = 0.5
	mm.mesh = plant
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://world/materials/kelp.gdshader")
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(mi)
