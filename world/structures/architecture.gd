class_name Architecture
extends Node3D
## Streams the modelled architecture of every location (Location.props) near
## the local player: buildings, villages, shrines, towers, ruins, mines,
## wrecks, portals. Geometry is built on WorkerThreadPool (ArchBuild) and
## handed to the main thread one mesh per frame, so streaming never hitches.
## Collision stays in the voxel field as invisible Blocks.STRUCTURE.
##
## Levels of detail per location: shell (walls, roofs, windows, paths) to
## ArchBuild.SHELL_RANGE, detail (props, rafters) to DETAIL_RANGE, interior
## (furniture) to INTERIOR_RANGE, and a cheap far silhouette from FAR_BEGIN to
## FAR_RANGE, built for every location of the dimension up front so places
## never pop in.
##
## Prop types: "building" (BuildingMesh), "green" (VillageGreen), "site"
## (SiteMesh), "builder" ({"builder": Callable(b: ArchBuild, prop)}, for other
## modules), and the legacy "box" / "gable" ({at, size, material, rotation}).

const NEAR_DISTANCE := 320.0
const FREE_DISTANCE := 400.0
const MAX_TASKS := 2

var _near := {}       # loc id -> Node3D
var _far := {}        # loc id -> MeshInstance3D
var _tasks := {}      # loc id -> {"task": int, "build": ArchBuild, "far_only": bool}
var _queue: Array = []  # [loc id, ArchBuild, stage] waiting for main-thread instancing
var _far_dim := -99
var _poll := 0.0
var _night := -1.0
var _night_lights: Array[Light3D] = []
## Optional overrides so the menu backdrop (no GameWorld) can use this node.
var gen_override: WorldGen
var focus_override := Callable()
var sky_override: SkyController


static func box(loc: Location, at: Vector3, extent: Vector3, material: String, rotation := Vector3.ZERO) -> void:
	loc.props.append({"type": "box", "at": at, "size": extent, "material": material, "rotation": rotation})


func _ready() -> void:
	ArchMaterials.main()
	# Profiling aid: measure a scene with and without the architecture.
	if "--no-architecture" in OS.get_cmdline_user_args():
		set_process(false)


func _exit_tree() -> void:
	for id: StringName in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(int(_tasks[id]["task"]))
	_tasks.clear()


func _process(delta: float) -> void:
	_drain_queue()
	_collect_tasks()
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.25
	var focus := Vector3.INF
	var gen: WorldGen = gen_override
	var dim := 0
	var locs: Array[Location] = []
	if focus_override.is_valid():
		focus = focus_override.call()
		if gen != null:
			locs = gen.locations
			dim = gen.dimension
		if sky_override != null:
			_set_night(sky_override.time_of_day, dim)
	else:
		var w := GameWorld.instance
		if w == null or w.local_player == null:
			return
		focus = w.local_player.global_position
		dim = w.local_dimension
		gen = w.gen_for(dim)
		locs = w.locations(dim)
		if w.sky != null:
			_set_night(w.sky.time_of_day, w.local_dimension)
	if gen == null:
		return
	if _far_dim != dim:
		_reset_dimension(dim)
		for loc in locs:
			if not loc.props.is_empty():
				_start(loc, gen, true)
	var wanted := {}
	for loc in locs:
		if loc.props.is_empty():
			continue
		var d := Vector2(loc.center.x - focus.x, loc.center.z - focus.z).length()
		if d < NEAR_DISTANCE:
			wanted[loc.id] = true
			if not _near.has(loc.id) and not _tasks.has(loc.id) and not _queued(loc.id) and _tasks.size() < MAX_TASKS:
				_start(loc, gen, false)
		elif d < FREE_DISTANCE and _near.has(loc.id):
			wanted[loc.id] = true
	for id: StringName in _near.keys():
		if not wanted.has(id):
			_free_near(id)


func _reset_dimension(dim: int) -> void:
	_far_dim = dim
	for id: StringName in _near.keys():
		_free_near(id)
	for id: StringName in _far.keys():
		(_far[id] as Node).queue_free()
	_far.clear()
	_queue.clear()


func _free_near(id: StringName) -> void:
	var node: Node3D = _near[id]
	for l in node.find_children("*", "Light3D", true, false):
		_night_lights.erase(l)
	node.queue_free()
	_near.erase(id)


func _queued(id: StringName) -> bool:
	for q: Array in _queue:
		if q[0] == id and not q[3]:
			return true
	return false


func _start(loc: Location, gen: WorldGen, far_only: bool) -> void:
	var key := StringName(String(loc.id) + ("#far" if far_only else ""))
	if _tasks.has(key):
		return
	var b := ArchBuild.new(gen, loc.center, hash(String(loc.id)))
	b.far_only = far_only
	var task := WorkerThreadPool.add_task(Architecture.fill.bind(b, loc), false, "architecture")
	_tasks[key] = {"task": task, "build": b, "loc": loc, "far_only": far_only}


## Builds every prop of `loc` into `b` (worker thread).
static func fill(b: ArchBuild, loc: Location) -> void:
	for prop: Dictionary in loc.props:
		match String(prop.get("type", "")):
			"building":
				if b.far_only:
					BuildingMesh.far_only(b, prop)
				else:
					BuildingMesh.build(b, prop)
			"green":
				if b.far_only:
					VillageGreen.far(b, prop)
				else:
					VillageGreen.build(b, prop)
			"site":
				SiteMesh.build(b, prop)
			"builder":
				var f: Callable = prop.get("builder", Callable())
				if f.is_valid():
					f.call(b, prop)
			"box", "gable":
				if not b.far_only:
					_legacy(b, prop)


static func _legacy(b: ArchBuild, prop: Dictionary) -> void:
	var layers := {"plaster": ArchMaterials.L.PLASTER, "timber": ArchMaterials.L.TIMBER, "roof": ArchMaterials.L.SHINGLE, "stone": ArchMaterials.L.RUBBLE}
	var m := b.shell
	m.mat(layers.get(prop.get("material", "stone"), ArchMaterials.L.RUBBLE), Color(0.9, 0.88, 0.85), 0.4)
	var s: Vector3 = prop["size"]
	var xf := Transform3D(Basis.from_euler(prop.get("rotation", Vector3.ZERO)), (prop["at"] as Vector3) - b.origin)
	m.push(xf)
	if prop["type"] == "gable":
		m.prism(Vector3(0, 0, -s.z * 0.5), Vector3.RIGHT, Vector3.UP, PackedVector2Array([Vector2(-s.x, 0), Vector2(s.x, 0), Vector2(0, s.y)]), s.z)
	else:
		m.box(Vector3.ZERO, s, 1 if s.y >= maxf(s.x, s.z) else (0 if s.x >= s.z else 2))
	m.pop()


func _collect_tasks() -> void:
	for key: StringName in _tasks.keys():
		var t: Dictionary = _tasks[key]
		if not WorkerThreadPool.is_task_completed(int(t["task"])):
			continue
		WorkerThreadPool.wait_for_task_completion(int(t["task"]))
		_tasks.erase(key)
		var loc: Location = t["loc"]
		_queue.append([loc.id, t["build"], 0, t["far_only"], loc])


## Instantiates one queued mesh per frame (uploads are the only main-thread cost).
func _drain_queue() -> void:
	if _queue.is_empty():
		return
	var q: Array = _queue[0]
	var id: StringName = q[0]
	var b: ArchBuild = q[1]
	var stage: int = q[2]
	var far_only: bool = q[3]
	var loc: Location = q[4]
	if far_only:
		_queue.pop_front()
		if b.far.is_empty() or _far.has(id):
			return
		var mi := _instance(b.far, ArchBuild.FAR_BEGIN, ArchBuild.FAR_RANGE, true)
		mi.position = b.origin
		mi.visibility_range_begin_margin = 25.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_far[id] = mi
		return
	if stage == 0:
		if _near.has(id):
			_queue.pop_front()
			return
		var node := Node3D.new()
		node.name = "Arch_" + String(id)
		node.position = b.origin
		add_child(node)
		_near[id] = node
	var node: Node3D = _near.get(id)
	if node == null:
		_queue.pop_front()
		return
	match stage:
		0:
			if not b.shell.is_empty():
				node.add_child(_instance(b.shell, 0.0, ArchBuild.SHELL_RANGE, true))
		1:
			if not b.detail.is_empty():
				node.add_child(_instance(b.detail, 0.0, ArchBuild.DETAIL_RANGE, true))
		2:
			if not b.interior.is_empty():
				var mi := _instance(b.interior, 0.0, ArchBuild.INTERIOR_RANGE, false)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				node.add_child(mi)
		3:
			_effects(node, b)
	q[2] = stage + 1
	if stage >= 3:
		_queue.pop_front()


func _instance(m: ArchMesh, begin: float, end: float, shadows: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m.to_mesh()
	mi.material_override = ArchMaterials.main()
	mi.visibility_range_begin = begin
	mi.visibility_range_end = end
	mi.visibility_range_end_margin = 30.0 if end < 1000.0 else 0.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Lights, fires and chimney smoke for a built location.
func _effects(node: Node3D, b: ArchBuild) -> void:
	for f: Dictionary in b.fires:
		ArchMaterials.fire(node, f["pos"], f["size"], f["range"], f["energy"])
	for s: Dictionary in b.smoke:
		ArchMaterials.smoke(node, s["pos"], s["strength"])
	for l: Dictionary in b.lights:
		var light := OmniLight3D.new()
		light.position = l["pos"]
		light.light_color = l["color"]
		light.omni_range = l["range"]
		light.light_energy = l["energy"]
		light.omni_attenuation = 1.4
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 70.0
		light.distance_fade_length = 20.0
		light.light_volumetric_fog_energy = 0.5
		light.set_meta("energy", l["energy"])
		node.add_child(light)
		if l["night"]:
			_night_lights.append(light)
			light.visible = _night > 0.05
			light.light_energy = float(l["energy"]) * maxf(_night, 0.0)


## Windows glow and lamps light up as the sun goes down.
func _set_night(t: float, dim: int) -> void:
	var sun_h := sin((t - 6.0) / 24.0 * TAU)
	var night := 1.0 - smoothstep(-0.12, 0.16, sun_h)
	if dim != 0:
		night = 0.6
	if absf(night - _night) < 0.01:
		return
	_night = night
	ArchMaterials.set_night(night)
	for l in _night_lights:
		if is_instance_valid(l):
			l.visible = night > 0.05
			l.light_energy = float(l.get_meta("energy", 1.0)) * night


## Synchronous build of one location (tests, tools). Returns a node at loc.center.
static func build(loc: Location, gen: WorldGen = null) -> Node3D:
	var b := ArchBuild.new(gen, loc.center, hash(String(loc.id)))
	fill(b, loc)
	var node := Node3D.new()
	node.position = loc.center
	for m in [b.shell, b.detail, b.interior]:
		if not (m as ArchMesh).is_empty():
			var mi := MeshInstance3D.new()
			mi.mesh = (m as ArchMesh).to_mesh()
			mi.material_override = ArchMaterials.main()
			node.add_child(mi)
	return node
