class_name ArenaInstance
extends Node3D
## The nodes of one built arena: mesh cells, flame billboards, pooled lights,
## embers and animated gates. Created incrementally by ArenaDirector (step()
## does a bounded amount of work per call) from an ArenaBuild.

const GATE_POLL := 0.15

var build: ArenaBuild
var location: Location
var dimension := 0
var lights: ArenaLights
var _mesh_i := 0
var _stage := 0
var _gates: Array[ArenaGate] = []
var _gate_poll := 0.0


func setup(b: ArenaBuild, loc: Location, dim: int) -> void:
	build = b
	location = loc
	dimension = dim
	position = b.center
	name = "Arena_" + b.kind


## Main thread: instantiate part of the arena. Returns true when complete.
func step() -> bool:
	match _stage:
		0:
			if _mesh_i < build.meshes.size():
				_add_mesh(build.meshes[_mesh_i])
				_mesh_i += 1
				return false
			_stage = 1
			return false
		1:
			_add_flames()
			_add_embers()
			_stage = 2
			return false
		2:
			lights = ArenaLights.new()
			lights.name = "Lights"
			add_child(lights)
			lights.setup(build.lights, build.center)
			_stage = 3
			return false
		3:
			for g: Dictionary in build.gates:
				var gate := ArenaGate.new()
				add_child(gate)
				gate.setup(g, ArenaMaterials.arena(build.params))
				_gates.append(gate)
			_stage = 4
			_poll_gates(true)
			return true
	return true


func _add_mesh(entry: Dictionary) -> void:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, entry["arrays"])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat_name := String(entry["material"])
	if mat_name == "main":
		mi.material_override = ArenaMaterials.arena(build.params)
	elif mat_name == "web":
		mi.material_override = ArenaMaterials.web()
	elif mat_name.begins_with("flow:"):
		mi.material_override = ArenaMaterials.flow(build.flow_params[mat_name.trim_prefix("flow:")])
	mi.visibility_range_end = float(entry["range"])
	mi.visibility_range_end_margin = 10.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(entry["shadow"]) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _add_flames() -> void:
	var by_kind := {}
	for f: Array in build.flames:
		var k := String(f[2])
		if not by_kind.has(k):
			by_kind[k] = []
		(by_kind[k] as Array).append(f)
	for k: String in by_kind:
		var list: Array = by_kind[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = ArenaMaterials.flame_quad()
		mm.instance_count = list.size()
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for i in list.size():
			var f: Array = list[i]
			var h := float(f[1])
			var p: Vector3 = (f[0] as Vector3) - build.center
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(h * 0.5, h, h * 0.5)), p))
			mm.set_instance_custom_data(i, Color(1, 1, 1, randf()))
			lo = lo.min(p - Vector3(h, h, h))
			hi = hi.max(p + Vector3(h, h * 2.0, h))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = ArenaMaterials.flame(k)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(lo, hi - lo)
		mmi.visibility_range_end = 220.0
		add_child(mmi)


func _add_embers() -> void:
	if int(Settings.get_value("graphics", "quality")) < Settings.Quality.MEDIUM:
		return
	for e: Array in build.embers:
		var host := Node3D.new()
		host.position = (e[0] as Vector3) - build.center
		add_child(host)
		var p := ModelKit.embers(host, int(e[2]), e[1], 1.6, 0.07, 1.6)
		p.emitting = true
		p.visibility_range_end = 60.0


func _process(delta: float) -> void:
	if _stage < 4 or _gates.is_empty():
		return
	_gate_poll -= delta
	if _gate_poll <= 0.0:
		_gate_poll = GATE_POLL
		_poll_gates(false)


## A gate is closed while its opening holds collision (GameWorld._set_arena_gates).
func _poll_gates(snap: bool) -> void:
	var w := GameWorld.instance
	if w == null or location == null:
		return
	var vw := w.world_for(dimension)
	if vw == null:
		return
	var spawns := location.spawns_of("arena_gate")
	for gate in _gates:
		if gate.spawn_index < 0 or gate.spawn_index >= spawns.size():
			continue
		var g: Dictionary = spawns[gate.spawn_index]
		var base := Vector3i((g["pos"] as Vector3).floor())
		var closed := false
		for h in [0, 1]:
			var b := vw.get_block(base + Vector3i(0, h, 0))
			if b == Blocks.STRUCTURE or b == Blocks.IRON_BARS:
				closed = true
		gate.set_closed(closed, snap)
