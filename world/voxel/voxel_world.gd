class_name VoxelWorld
extends Node3D
## A streamed, editable voxel dimension.
##
## Chunk data is generated on worker threads (WorldGen) and meshed on worker
## threads (ChunkMesher) once all 26 neighbours exist; meshes are uploaded on
## the main thread within a small per-frame budget so streaming never hitches.
## Player edits are kept separately so unedited chunks can be dropped and
## regenerated, and so the edit list can be saved or sent to joining players.

signal block_changed(pos: Vector3i, old_block: int, new_block: int)
signal area_ready  ## first time the area around the focus is fully meshed

const OPAQUE_SHADER := preload("res://world/materials/voxel.gdshader")
const LIQUID_SHADER := preload("res://world/materials/voxel_liquid.gdshader")

var gen: WorldGen
var dimension := 0
## Chunks meshed within this horizontal radius (in chunks) of `focus`.
var view_radius := 9
var focus := Vector3.ZERO
## Server only: other players' positions; their surroundings get data (for
## physics and AI) but no meshes.
var data_focus: Array[Vector3] = []
var meshing_enabled := true
var max_point_lights := 12

var opaque_material := ShaderMaterial.new()
var liquid_material := ShaderMaterial.new()

var _chunks := {}         # Vector3i -> PackedByteArray (empty = all air)
var _solid_uniform := {}  # Vector3i -> true when the chunk is entirely opaque
var _edits := {}          # Vector3i -> Dictionary(local index -> block)
var _meshes := {}         # Vector3i -> MeshInstance3D
var _light_points := {}   # Vector3i -> Array [Vector3 pos, Color colour]
var _gen_pending := {}
var _mesh_pending := {}
var _mesh_version := {}
var _dirty := {}
var _column_top := {}
var _lock := Mutex.new()
var _gen_results: Array = []
var _mesh_results: Array = []
var _in_flight := 0
var _scan_timer := 0.0
var _last_focus_key := Vector3i(1 << 20, 0, 0)
var _wanted_mesh: Array[Vector3i] = []
var _wanted_data: Array[Vector3i] = []
var _mesh_todo: Array[Vector3i] = []
var _data_cursor := 0
var _area_ready_emitted := false
var _light_nodes: Array[OmniLight3D] = []
var _light_timer := 0.0
var _max_in_flight := 8
var _gen_in_flight := 0
var _mesh_in_flight := 0
var _max_gen := 6
var _max_mesh := 4


func setup(world_gen: WorldGen, dim: int) -> void:
	gen = world_gen
	dimension = dim
	opaque_material.shader = OPAQUE_SHADER
	liquid_material.shader = LIQUID_SHADER
	var cores := maxi(2, OS.get_processor_count() - 1)
	_max_in_flight = cores
	# Separate budgets: meshing must never wait behind a long generation queue.
	_max_mesh = maxi(1, cores / 3)
	_max_gen = maxi(1, cores - _max_mesh)


func _exit_tree() -> void:
	# Let in-flight tasks finish before the generator goes away.
	while _in_flight > 0 and _drain_once():
		OS.delay_msec(2)


func _drain_once() -> bool:
	_lock.lock()
	var n := _gen_results.size() + _mesh_results.size()
	_in_flight -= n
	_gen_results.clear()
	_mesh_results.clear()
	_lock.unlock()
	return true


# --- Queries ----------------------------------------------------------------------

func get_block(p: Vector3i) -> int:
	var key := Chunk.key_of(p)
	var data: Variant = _chunks.get(key)
	if data == null:
		return -1
	var arr: PackedByteArray = data
	if arr.is_empty():
		return Blocks.AIR
	var l := Chunk.local(p)
	return arr[Chunk.index(l.x, l.y, l.z)]


## Unloaded space counts as solid so nothing falls through the world.
func is_solid(p: Vector3i) -> bool:
	var b := get_block(p)
	return b < 0 or Blocks.is_solid(b)


func is_loaded(p: Vector3i) -> bool:
	return _chunks.has(Chunk.key_of(p))


func is_area_loaded(p: Vector3) -> bool:
	return _chunks.has(Chunk.key_of(Vector3i(p.floor())))


func surface_y(x: int, z: int) -> int:
	# Scan down through loaded data first; fall back to the generator.
	var top := gen.surface_height(x, z)
	for y in range(top + 24, top - 40, -1):
		var b := get_block(Vector3i(x, y, z))
		if b > 0 and Blocks.is_solid(b):
			return y
	return top


## Voxel ray march (Amanatides & Woo). Returns {} on miss.
func raycast(origin: Vector3, dir: Vector3, max_dist: float, include_liquid := false) -> Dictionary:
	dir = dir.normalized()
	var p := Vector3i(origin.floor())
	var step := Vector3i(signi(int(signf(dir.x))), signi(int(signf(dir.y))), signi(int(signf(dir.z))))
	var t_max := Vector3.ZERO
	var t_delta := Vector3.ZERO
	for a in 3:
		if absf(dir[a]) < 1e-6:
			t_max[a] = INF
			t_delta[a] = INF
		else:
			var next_boundary := float(p[a] + (1 if step[a] > 0 else 0))
			t_max[a] = (next_boundary - origin[a]) / dir[a]
			t_delta[a] = absf(1.0 / dir[a])
	var normal := Vector3i.ZERO
	var t := 0.0
	while t <= max_dist:
		var b := get_block(p)
		if b < 0:
			return {}
		if b != Blocks.AIR and (Blocks.is_solid(b) or Blocks.shape(b) == Blocks.Shape.SMALL or (include_liquid and Blocks.is_liquid(b))):
			return {"pos": p, "normal": normal, "block": b, "distance": t, "point": origin + dir * t}
		if t_max.x < t_max.y and t_max.x < t_max.z:
			p.x += step.x
			t = t_max.x
			t_max.x += t_delta.x
			normal = Vector3i(-step.x, 0, 0)
		elif t_max.y < t_max.z:
			p.y += step.y
			t = t_max.y
			t_max.y += t_delta.y
			normal = Vector3i(0, -step.y, 0)
		else:
			p.z += step.z
			t = t_max.z
			t_max.z += t_delta.z
			normal = Vector3i(0, 0, -step.z)
	return {}


# --- Edits ----------------------------------------------------------------------

func set_block(p: Vector3i, block: int) -> void:
	var key := Chunk.key_of(p)
	var l := Chunk.local(p)
	var i := Chunk.index(l.x, l.y, l.z)
	if not _edits.has(key):
		_edits[key] = {}
	_edits[key][i] = block
	var data: Variant = _chunks.get(key)
	if data == null:
		return
	var arr: PackedByteArray = data
	# Copy before writing: worker threads may still be reading the old buffer.
	arr = Chunk.empty() if arr.is_empty() else arr.duplicate()
	var old := arr[i]
	arr[i] = block
	_chunks[key] = arr
	_solid_uniform.erase(key)
	for dz in range(-1 if l.z == 0 else 0, 2 if l.z == 15 else 1):
		for dy in range(-1 if l.y == 0 else 0, 2 if l.y == 15 else 1):
			for dx in range(-1 if l.x == 0 else 0, 2 if l.x == 15 else 1):
				_mark_dirty(key + Vector3i(dx, dy, dz))
	block_changed.emit(p, old, block)


func get_edits() -> Dictionary:
	return _edits.duplicate(true)


func apply_edits(edits: Dictionary) -> void:
	for key: Vector3i in edits:
		var entries: Dictionary = edits[key]
		for i: int in entries:
			var y := i / Chunk.AREA
			var z := (i % Chunk.AREA) / Chunk.SIZE
			var x := i % Chunk.SIZE
			set_block(key * Chunk.SIZE + Vector3i(x, y, z), entries[i])


func _mark_dirty(key: Vector3i) -> void:
	if _meshes.has(key) or _mesh_pending.has(key):
		_dirty[key] = true
		_mesh_version[key] = int(_mesh_version.get(key, 0)) + 1


# --- Streaming --------------------------------------------------------------------

func _process(delta: float) -> void:
	if gen == null:
		return
	_consume_results()
	var fkey := Chunk.key_of(Vector3i(focus.floor()))
	_scan_timer -= delta
	if fkey != _last_focus_key or _scan_timer <= 0.0:
		_last_focus_key = fkey
		_scan_timer = 4.0
		_rebuild_wanted(fkey)
		_unload_far(fkey)
	_schedule()
	if meshing_enabled:
		_light_timer -= delta
		if _light_timer <= 0.0:
			_light_timer = 0.25
			_update_lights()


func _column_top_cy(cx: int, cz: int) -> int:
	var k := Vector2i(cx, cz)
	if _column_top.has(k):
		return _column_top[k]
	var top := -1000
	for s: Vector2i in [Vector2i(0, 0), Vector2i(15, 0), Vector2i(0, 15), Vector2i(15, 15), Vector2i(8, 8), Vector2i(4, 11), Vector2i(11, 4)]:
		var x := cx * 16 + s.x
		var z := cz * 16 + s.y
		if gen.in_bounds(x, z):
			top = maxi(top, gen.surface_height(x, z))
	var sea := WorldGen.SEA_LEVEL if dimension == 0 else WorldGen.LAVA_LEVEL
	top = maxi(top, sea) + 12
	var cy := floori(top / 16.0)
	_column_top[k] = cy
	return cy


func _rebuild_wanted(fkey: Vector3i) -> void:
	_wanted_mesh.clear()
	_wanted_data.clear()
	var surface_cy := _column_top_cy(fkey.x, fkey.z)
	var underground := focus.y < surface_cy * 16 - 40
	var radius := view_radius if not underground else mini(view_radius, 6)
	var seen := {}
	var candidates: Array = []
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var d2 := dx * dx + dz * dz
			if d2 > radius * radius:
				continue
			var cx := fkey.x + dx
			var cz := fkey.z + dz
			if not gen.in_bounds(cx * 16 + 8, cz * 16 + 8) and not gen.in_bounds(cx * 16, cz * 16) and not gen.in_bounds(cx * 16 + 15, cz * 16 + 15):
				continue
			var top := _column_top_cy(cx, cz)
			var ys := {}
			var down := 3 if underground else 2
			for y in range(fkey.y - down, fkey.y + 3):
				ys[y] = true
			if not underground or d2 <= 9:
				for y in range(top - 2, top + 1):
					ys[y] = true
			for y: int in ys:
				if y * 16 > 160 or y * 16 < -144:
					continue
				var k := Vector3i(cx, y, cz)
				candidates.append([d2 + absi(y - fkey.y) * 2, k])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	_data_cursor = 0
	_mesh_todo.clear()
	for c: Array in candidates:
		var k: Vector3i = c[1]
		_wanted_mesh.append(k)
		if not _meshes.has(k):
			_mesh_todo.append(k)
		for dz in range(-1, 2):
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var n := k + Vector3i(dx, dy, dz)
					if not seen.has(n):
						seen[n] = true
						_wanted_data.append(n)
	# Data around other players (server-side simulation).
	for p in data_focus:
		var pk := Chunk.key_of(Vector3i(p.floor()))
		for dz in range(-2, 3):
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var n := pk + Vector3i(dx, dy, dz)
					if not seen.has(n):
						seen[n] = true
						_wanted_data.append(n)


func _schedule() -> void:
	# Cursors walk the (distance-sorted) wanted lists a bounded amount per
	# frame, so streaming cost stays flat no matter how much is loaded.
	if meshing_enabled:
		# Edited chunks first: the player is looking at them.
		for k: Vector3i in _dirty.keys():
			if _mesh_in_flight >= _max_mesh:
				break
			_try_mesh(k)
		var mchecks := 0
		var i := 0
		while i < _mesh_todo.size() and _mesh_in_flight < _max_mesh and mchecks < 96:
			mchecks += 1
			var k := _mesh_todo[i]
			var state := _try_mesh(k)
			if state != 0:
				_mesh_todo.remove_at(i)  # dispatched or nothing to do
			else:
				i += 1
	var checks := 0
	while _data_cursor < _wanted_data.size() and _gen_in_flight < _max_gen and checks < 512:
		var k := _wanted_data[_data_cursor]
		_data_cursor += 1
		checks += 1
		if _chunks.has(k) or _gen_pending.has(k):
			continue
		_gen_pending[k] = true
		_in_flight += 1
		_gen_in_flight += 1
		WorkerThreadPool.add_task(_task_generate.bind(k), false, "chunk gen")


## 1 = dispatched or empty, 2 = already meshed, 0 = not ready yet.
func _try_mesh(k: Vector3i) -> int:
	if _mesh_pending.has(k):
		return 1
	if _meshes.has(k) and not _dirty.has(k):
		return 2
	if not _chunks.has(k):
		return 0
	var neighbours := _neighbour_data(k)
	if neighbours.is_empty():
		return 0
	_dirty.erase(k)
	if _skip_mesh(k):
		_set_mesh(k, {})
		return 1
	_mesh_pending[k] = true
	_in_flight += 1
	_mesh_in_flight += 1
	var version := int(_mesh_version.get(k, 0))
	WorkerThreadPool.add_task(_task_mesh.bind(k, neighbours, version), false, "chunk mesh")
	return 1


func _neighbour_data(k: Vector3i) -> Array:
	var out := []
	out.resize(27)
	for dz in range(-1, 2):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n := k + Vector3i(dx, dy, dz)
				var d: Variant = _chunks.get(n)
				if d == null:
					return []
				out[(dx + 1) + (dy + 1) * 3 + (dz + 1) * 9] = d
	return out


## Empty chunks, and solid chunks buried in solid chunks, have no faces.
func _skip_mesh(k: Vector3i) -> bool:
	var data: PackedByteArray = _chunks[k]
	if data.is_empty():
		return true
	if not _solid_uniform.has(k):
		return false
	for n: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		if not _solid_uniform.has(k + n):
			return false
	return true


func _task_generate(k: Vector3i) -> void:
	var data := gen.generate_chunk(k)
	_lock.lock()
	_gen_results.append([k, data])
	_lock.unlock()


func _task_mesh(k: Vector3i, neighbours: Array, version: int) -> void:
	var detail := gen.make_detail_noise()
	var ridge := gen.make_ridge_noise()
	var surface := PackedInt32Array()
	surface.resize(Chunk.AREA)
	var o := k * Chunk.SIZE
	for z in Chunk.SIZE:
		for x in Chunk.SIZE:
			var wx := o.x + x
			var wz := o.z + z
			surface[x + z * Chunk.SIZE] = int(gen.column(wx, wz, detail, ridge).x) if gen.in_bounds(wx, wz) else -64
	var result := ChunkMesher.build(neighbours, surface, o.y)
	# Emissive blocks become light sources.
	var center: PackedByteArray = neighbours[13]
	var lights: Array = []
	if not center.is_empty():
		for i in Chunk.VOLUME:
			var b := center[i]
			if b != 0 and Blocks.light(b) > 0.0 and b != Blocks.LAVA and b != Blocks.HELLSTONE:
				var y := i / Chunk.AREA
				var z := (i % Chunk.AREA) / Chunk.SIZE
				var x := i % Chunk.SIZE
				lights.append([Vector3(o) + Vector3(x + 0.5, y + 0.6, z + 0.5), Blocks.color(b), Blocks.light(b)])
	result["lights"] = lights
	_lock.lock()
	_mesh_results.append([k, version, result])
	_lock.unlock()


func _consume_results() -> void:
	_lock.lock()
	var gens := _gen_results
	_gen_results = []
	var meshes := _mesh_results
	_mesh_results = []
	_lock.unlock()

	for r: Array in gens:
		_in_flight -= 1
		_gen_in_flight -= 1
		var k: Vector3i = r[0]
		var data: PackedByteArray = r[1]
		_gen_pending.erase(k)
		if _edits.has(k):
			var entries: Dictionary = _edits[k]
			for i: int in entries:
				data[i] = entries[i]
		if Chunk.is_all(data, Blocks.AIR):
			data = PackedByteArray()
		elif Blocks.is_opaque(data[0]) and data.count(data[0]) == Chunk.VOLUME:
			_solid_uniform[k] = true
		_chunks[k] = data

	var budget_end := Time.get_ticks_usec() + 4000
	var deferred: Array = []
	for r: Array in meshes:
		if Time.get_ticks_usec() > budget_end:
			deferred.append(r)
			continue
		_in_flight -= 1
		_mesh_in_flight -= 1
		var k: Vector3i = r[0]
		_mesh_pending.erase(k)
		if int(_mesh_version.get(k, 0)) != int(r[1]):
			_dirty[k] = true  # edited while meshing: do it again
			continue
		_set_mesh(k, r[2])
	if not deferred.is_empty():
		_lock.lock()
		_mesh_results = deferred + _mesh_results
		_lock.unlock()
		# Deferred results are still counted as in flight.
		_in_flight += 0

	if not _area_ready_emitted and _near_area_meshed():
		_area_ready_emitted = true
		area_ready.emit()


func _near_area_meshed() -> bool:
	var fkey := Chunk.key_of(Vector3i(focus.floor()))
	var checked := 0
	for k in _wanted_mesh:
		if Vector2(k.x - fkey.x, k.z - fkey.z).length() > 3.0:
			continue
		checked += 1
		if not _meshes.has(k):
			return false
	return checked > 0


func debug_stats() -> String:
	return "chunks %d meshes %d in_flight %d gen_pending %d mesh_pending %d wanted %d/%d todo %d cursor %d progress %.2f" % [
		_chunks.size(), _meshes.size(), _in_flight, _gen_pending.size(), _mesh_pending.size(),
		_wanted_mesh.size(), _wanted_data.size(), _mesh_todo.size(), _data_cursor, loading_progress()]


func loading_progress() -> float:
	var fkey := Chunk.key_of(Vector3i(focus.floor()))
	var total := 0
	var done := 0
	for k in _wanted_mesh:
		if Vector2(k.x - fkey.x, k.z - fkey.z).length() > 3.0:
			continue
		total += 1
		if _meshes.has(k):
			done += 1
	return float(done) / maxf(1.0, total)


func _set_mesh(k: Vector3i, result: Dictionary) -> void:
	var old: MeshInstance3D = _meshes.get(k)
	if old != null:
		old.queue_free()
	_light_points[k] = result.get("lights", [])
	if not result.has("opaque") and not result.has("liquid"):
		_meshes[k] = null
		return
	var mesh := ArrayMesh.new()
	if result.has("opaque"):
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, result["opaque"])
		mesh.surface_set_material(mesh.get_surface_count() - 1, opaque_material)
	if result.has("liquid"):
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, result["liquid"])
		mesh.surface_set_material(mesh.get_surface_count() - 1, liquid_material)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(k * Chunk.SIZE)
	mi.cast_shadow = _shadow_setting(k)
	add_child(mi)
	_meshes[k] = mi


func _shadow_setting(k: Vector3i) -> int:
	var c := Vector3(k * Chunk.SIZE) + Vector3(8, 8, 8)
	var near := c.distance_to(focus) < GraphicsQuality.shadow_caster_distance() + 12.0
	return GeometryInstance3D.SHADOW_CASTING_SETTING_ON if near else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _unload_far(fkey: Vector3i) -> void:
	# Only nearby terrain casts shadows: halves the shadow-pass draw calls.
	for k: Vector3i in _meshes:
		var m: MeshInstance3D = _meshes[k]
		if m != null:
			m.cast_shadow = _shadow_setting(k)
	var r := view_radius + 2
	var mesh_keys := _meshes.keys()
	for k: Vector3i in mesh_keys:
		if absi(k.x - fkey.x) > r or absi(k.z - fkey.z) > r or absi(k.y - fkey.y) > 8:
			var mi: MeshInstance3D = _meshes[k]
			if mi != null:
				mi.queue_free()
			_meshes.erase(k)
			_light_points.erase(k)
	var dr := view_radius + 4
	var data_keys := _chunks.keys()
	for k: Vector3i in data_keys:
		if absi(k.x - fkey.x) <= dr and absi(k.z - fkey.z) <= dr and absi(k.y - fkey.y) <= 10:
			continue
		var near_other := false
		for p in data_focus:
			var pk := Chunk.key_of(Vector3i(p.floor()))
			if absi(k.x - pk.x) <= 3 and absi(k.z - pk.z) <= 3 and absi(k.y - pk.y) <= 3:
				near_other = true
				break
		if not near_other and not _mesh_pending.has(k):
			_chunks.erase(k)
			_solid_uniform.erase(k)


# --- Lights -------------------------------------------------------------------------

func _update_lights() -> void:
	var fkey := Chunk.key_of(Vector3i(focus.floor()))
	var found: Array = []
	for dz in range(-3, 4):
		for dy in range(-2, 3):
			for dx in range(-3, 4):
				var pts: Variant = _light_points.get(fkey + Vector3i(dx, dy, dz))
				if pts == null:
					continue
				for p: Array in pts:
					found.append([focus.distance_squared_to(p[0]), p])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	while _light_nodes.size() < max_point_lights:
		var l := OmniLight3D.new()
		l.omni_range = 9.0
		l.omni_attenuation = 1.6
		l.light_volumetric_fog_energy = 1.2
		l.visible = false
		add_child(l)
		_light_nodes.append(l)
	for i in _light_nodes.size():
		var l := _light_nodes[i]
		if i < found.size() and i < max_point_lights:
			var p: Array = found[i][1]
			l.visible = true
			l.position = p[0]
			l.light_color = p[1]
			l.light_energy = 0.55 * float(p[2])
			l.omni_range = 5.0 + float(p[2]) * 2.2
		else:
			l.visible = false
