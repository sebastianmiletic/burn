class_name EnvironmentDetails
extends Node3D
## Small, bounded scenery sets. No per-voxel nodes, no collision on decorative
## plants. Geyser damage is resolved by the host, never by visual particles.
var _timer := 0.0
var _root: Node3D
var _key := ""
var _steam: Array[GPUParticles3D] = []
var _warned := ""
var _mines: MineDressing

func _ready() -> void:
	_mines = MineDressing.new()
	_mines.name = "MineDressing"
	add_child(_mines)

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
			var cave_name: String = CaveBiomes.NAMES[kind] if kind < CaveBiomes.NAMES.size() else "Caverns"
			Events.notify.emit(cave_name + (": no creatures, finite riches." if kind == CaveBiomes.Kind.CRYSTAL_REFUGE else (": steam surges every ten seconds. Keep clear of the vents." if kind == CaveBiomes.Kind.GEYSER else "")), "info")
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
		# Dripstone, fungi, crystals and webs are per-chunk CaveDecor; only set pieces live here.
		if int(r["kind"]) == CaveBiomes.Kind.GEYSER:
			for vent in _vents(r):
				_add_mesh(_vent_mesh(), vent + Vector3(0, -0.35, 0), CaveDecor.material(CaveDecor.T.R_SINTER))
				_make_steam(vent + Vector3(0, 0.6, 0))
				_vent_glow(vent + Vector3(0, 0.9, 0))
	# Kelp and the other sea plants are per-chunk SeaFlora now (world/flora/sea_flora.gd).

static var _vent: ArrayMesh

## A geyser vent: a sinter cone with terraced rimstone flanks and a hot pool in its crater.
static func _vent_mesh() -> ArrayMesh:
	if _vent != null:
		return _vent
	var b := CaveMeshes.Builder.new()
	var rad := func(a: float) -> float: return 3.2 * (1.0 + 0.12 * sin(a * 3.0 + 0.7) + 0.07 * sin(a * 7.0))
	var hgt := func(f: float, a: float) -> float:
		if f < 0.14:
			return 1.05  # pool surface
		if f < 0.2:
			return 1.05 + (f - 0.14) * 4.0  # crater lip
		var slope := 1.29 - (f - 0.2) * 1.55
		var steps := 6.0
		var k := (f - 0.2) / 0.8 * steps
		var frac := k - floorf(k)
		return slope + smoothstep(0.7, 0.95, frac) * 0.06 + 0.02 * sin(a * 11.0 + f * 20.0) - (0.25 if f > 0.98 else 0.0)
	CaveMeshes.disc(b, 22, 40, rad, hgt, Color(0, 0, 0.5, 1.0), 1.8)
	for i in b.v.size():
		var d := Vector2(b.v[i].x, b.v[i].z).length()
		b.c[i].r = clampf(1.0 - d / 3.2, 0.0, 1.0)
		if d < 0.45:
			b.c[i].g = 1.0
	_vent = b.commit()
	return _vent

func _vent_glow(at: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(0.45, 0.95, 0.85)
	l.light_energy = 0.8
	l.omni_range = 7.0
	l.shadow_enabled = false
	l.position = at
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
	particles.amount = [24, 40, 64, 80][clampi(Settings.gfx("effects"), 0, 3)]
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
