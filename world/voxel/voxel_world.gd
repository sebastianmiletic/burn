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
const TERRAIN_SHADER := preload("res://world/materials/terrain.gdshader")
const FLORA_PATH := "res://world/flora/flora.gd"
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
var terrain_material := ShaderMaterial.new()
## Flora script (world/flora/flora.gd) when present: plans and builds grass and trees per chunk.
var flora: Script
var flora_quality := 1
var liquid_material := ShaderMaterial.new()

var _chunks := {}         # Vector3i -> PackedByteArray (empty = all air)
var _density := {}        # Vector3i -> PackedByteArray (empty = derived from the blocks)
var _solid_uniform := {}  # Vector3i -> true when the chunk is entirely opaque
var _edits := {}          # Vector3i -> Dictionary(local index -> block)
var _meshes := {}         # Vector3i -> MeshInstance3D
var _light_points := {}   # Vector3i -> Array [Vector3 pos, Color colour]
var _gen_pending := {}
var _mesh_pending := {}
var _mesh_version := {}
var _dirty := {}
var _column_top := {}
var _column_low := {}
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
	terrain_material.shader = TERRAIN_SHADER
	TerrainTextures.apply(terrain_material)
	TerrainTextures.apply(opaque_material)
	if ResourceLoader.exists(FLORA_PATH):
		flora = load(FLORA_PATH)
	flora_quality = GraphicsQuality.foliage()
	Settings.changed.connect(_on_settings_changed)
	if DisplayServer.get_name() != "headless":
		CaveDecor.warmup()  # cave decoration meshes (world/caves), built once on the loading screen
	var cores := maxi(2, OS.get_processor_count() - 1)
	_max_in_flight = cores
	# Separate budgets: meshing must never wait behind a long generation queue.
	_max_mesh = maxi(1, cores / 3)
	_max_gen = maxi(1, cores - _max_mesh)


## Graphics options apply to the chunks already built, not just new ones.
func _on_settings_changed(section: String, _key: String) -> void:
	if section != "graphics" or not is_inside_tree():
		return
	var q := GraphicsQuality.foliage()
	flora_quality = q
	if flora != null and dimension == 0:
		flora.call("requalify", get_tree(), q)
	for k: Vector3i in _meshes:
		var m: MeshInstance3D = _meshes[k]
		if m != null:
			m.cast_shadow = _shadow_setting(k)


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
			var hit := {"pos": p, "normal": normal, "block": b, "distance": t, "point": origin + dir * t, "surface_normal": Vector3(normal)}
			if Blocks.is_smooth(b):
				_refine_smooth_hit(hit, origin, dir, t)
			return hit
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


## The voxel grid finds which block; the smooth surface says where the ray
## really meets the ground (up to about half a block either side).
func _refine_smooth_hit(hit: Dictionary, origin: Vector3, dir: Vector3, t_hit: float) -> void:
	var t := maxf(0.0, t_hit - 0.9)
	var t_end := t_hit + 0.9
	var prev_t := t
	var prev_in := field(origin + dir * t) >= 0.5
	if prev_in:
		return  # started inside the ground: keep the grid answer
	t += 0.08
	while t <= t_end:
		if field(origin + dir * t) >= 0.5:
			# Bisect the crossing.
			var lo := prev_t
			var hi := t
			for i in 5:
				var mid := (lo + hi) * 0.5
				if field(origin + dir * mid) >= 0.5:
					hi = mid
				else:
					lo = mid
			var point := origin + dir * hi
			hit["point"] = point
			hit["distance"] = hi
			var n := field_normal(point)
			hit["surface_normal"] = n
			# Place blocks against the face the surface mostly looks along.
			var a := n.abs()
			if a.y >= a.x and a.y >= a.z:
				hit["normal"] = Vector3i(0, 1 if n.y > 0.0 else -1, 0)
			elif a.x >= a.z:
				hit["normal"] = Vector3i(1 if n.x > 0.0 else -1, 0, 0)
			else:
				hit["normal"] = Vector3i(0, 0, 1 if n.z > 0.0 else -1)
			return
		prev_t = t
		t += 0.08


## Outward surface normal of the smooth field at p.
func field_normal(p: Vector3) -> Vector3:
	const E := 0.35
	var g := Vector3(field(p + Vector3(E, 0, 0)) - field(p - Vector3(E, 0, 0)),
			field(p + Vector3(0, E, 0)) - field(p - Vector3(0, E, 0)),
			field(p + Vector3(0, 0, E)) - field(p - Vector3(0, 0, E)))
	return (-g).normalized() if g.length_squared() > 1e-8 else Vector3.UP


# --- Edits ----------------------------------------------------------------------

func set_block(p: Vector3i, block: int) -> void:
	set_voxels(PackedInt32Array([p.x, p.y, p.z, block, -1]))


## Batch edit. `changes` is flat: x, y, z, block, density (0..255, or -1 to derive
## it from the block). Each touched chunk is copied once and remeshed once.
## Edits are remembered as `block | (density + 1) << 8` (plain block ids from old
## saves still load: their density is derived).
func set_voxels(changes: PackedInt32Array) -> void:
	var touched := {}
	var copied := {}
	var events: Array = []
	var n := changes.size() / 5
	for c in n:
		var p := Vector3i(changes[c * 5], changes[c * 5 + 1], changes[c * 5 + 2])
		var block := changes[c * 5 + 3]
		var dens := changes[c * 5 + 4]
		var key := Chunk.key_of(p)
		var l := Chunk.local(p)
		var i := Chunk.index(l.x, l.y, l.z)
		if not _edits.has(key):
			_edits[key] = {}
		var data: Variant = _chunks.get(key)
		if data == null:
			# Not loaded here: remember it for when the chunk streams in.
			_edits[key][i] = block | ((dens + 1) << 8) if dens >= 0 else block
			continue
		if not copied.has(key):
			# Copy before writing: worker threads may still be reading the old buffers.
			var arr0: PackedByteArray = data
			_chunks[key] = Chunk.empty() if arr0.is_empty() else arr0.duplicate()
			var d0: PackedByteArray = _density.get(key, PackedByteArray())
			d0 = SmoothMesher.derive_density(arr0) if d0.is_empty() else d0.duplicate()
			_density[key] = d0 if not d0.is_empty() else Chunk.empty()
			copied[key] = true
			_solid_uniform.erase(key)
		var arr: PackedByteArray = _chunks[key]
		var dn: PackedByteArray = _density[key]
		var old := arr[i]
		arr[i] = block
		dn[i] = dens if dens >= 0 else _edit_density(block, dn[i])
		_edits[key][i] = block | ((dn[i] + 1) << 8)
		for dz in range(-1 if l.z == 0 else 0, 2 if l.z == 15 else 1):
			for dy in range(-1 if l.y == 0 else 0, 2 if l.y == 15 else 1):
				for dx in range(-1 if l.x == 0 else 0, 2 if l.x == 15 else 1):
					touched[key + Vector3i(dx, dy, dz)] = true
		if old != block:
			events.append([p, old, block])
	_fk = Vector3i(1 << 20, 0, 0)
	for k: Vector3i in touched:
		_mark_dirty(k)
	for e: Array in events:
		block_changed.emit(e[0], e[1], e[2])


func get_edits() -> Dictionary:
	return _edits.duplicate(true)


func apply_edits(edits: Dictionary) -> void:
	var batch := PackedInt32Array()
	for key: Vector3i in edits:
		var entries: Dictionary = edits[key]
		for i: int in entries:
			var y := i / Chunk.AREA
			var z := (i % Chunk.AREA) / Chunk.SIZE
			var x := i % Chunk.SIZE
			var v: int = entries[i]
			var p := key * Chunk.SIZE + Vector3i(x, y, z)
			batch.append_array([p.x, p.y, p.z, v & 255, (v >> 8) - 1 if v >= 256 else -1])
	set_voxels(batch)


# --- Sculpting ---------------------------------------------------------------------

## Server: carve a sphere out of the ground with the given tool for `seconds`
## of work. Each voxel loses density in proportion to how long the tool needs
## for its material (ItemDB.mine_time); voxels that fall below the surface
## become empty and are counted in the result. Built blocks, trees and
## anything too hard for the tool are untouched.
## Returns {"changes": PackedInt32Array (for set_voxels), "removed": {block: voxels}}.
func plan_dig(center: Vector3, radius: float, seconds: float, item_id: String) -> Dictionary:
	var changes := PackedInt32Array()
	var removed := {}
	var r := ceili(radius + 0.5)
	var c := Vector3i(center.floor())
	var cache := {}
	for dz in range(-r, r + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p := c + Vector3i(dx, dy, dz)
				var dist := (Vector3(p) + Vector3(0.5, 0.5, 0.5)).distance_to(center)
				if dist > radius:
					continue
				var b := get_block(p)
				if b < 0:
					continue
				var smooth := Blocks.is_smooth(b)
				var empty := b == Blocks.AIR or Blocks.is_liquid(b)
				if not smooth and not empty:
					continue
				var d := int(round(voxel_field(p) * 255.0))
				if d <= 0:
					continue
				var falloff := 1.0 - smoothstep(radius * 0.35, radius, dist)
				var work := 1.0
				if smooth:
					if not cache.has(b):
						cache[b] = ItemDB.mine_time(item_id, b)
					var t: float = cache[b]
					if t < 0.0:
						continue
					work = seconds / maxf(0.05, t)
				else:
					work = seconds * 2.0  # loosening the empty space around the surface
				var nd := d - int(work * falloff * 300.0)
				if nd >= d:
					continue
				if smooth and nd < 128:
					removed[b] = int(removed.get(b, 0)) + 1
					changes.append_array([p.x, p.y, p.z, Blocks.AIR, maxi(nd, 0)])
				else:
					changes.append_array([p.x, p.y, p.z, b, maxi(nd, 128 if smooth else 0)])
	return {"changes": changes, "removed": removed}


## Server: add ground of `block` in a sphere (building up / filling holes).
func plan_fill(center: Vector3, radius: float, block: int) -> PackedInt32Array:
	var changes := PackedInt32Array()
	var r := ceili(radius + 0.5)
	var c := Vector3i(center.floor())
	for dz in range(-r, r + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p := c + Vector3i(dx, dy, dz)
				var dist := (Vector3(p) + Vector3(0.5, 0.5, 0.5)).distance_to(center)
				if dist > radius:
					continue
				var b := get_block(p)
				if b < 0 or not (b == Blocks.AIR or Blocks.is_liquid(b) or Blocks.is_smooth(b)):
					continue
				var d := int(round(voxel_field(p) * 255.0))
				var add := int((1.0 - smoothstep(radius * 0.4, radius, dist)) * 260.0)
				var nd := mini(255, d + add)
				if nd <= d:
					continue
				if nd >= 128 and not Blocks.is_smooth(b):
					changes.append_array([p.x, p.y, p.z, block, nd])
				else:
					changes.append_array([p.x, p.y, p.z, b, nd])
	return changes


## Density byte an edit leaves behind: placed ground is fully solid, dug
## space fully empty, built blocks keep the ground's shape around them.
static func _edit_density(block: int, old: int) -> int:
	if Blocks.is_smooth(block):
		return 255
	if block == Blocks.AIR or Blocks.is_liquid(block):
		return 0
	return mini(old, 127)


# --- Smooth field -------------------------------------------------------------------
# The terrain surface is the 0.5 level set of a field sampled at voxel centres:
# smooth-family blocks are >= 0.5, everything else < 0.5. Crisp cubes are boxes.

var _fk := Vector3i(1 << 20, 0, 0)  # one-chunk cache for field lookups
var _fb := PackedByteArray()
var _fd := PackedByteArray()
var _fl := false  # cached chunk loaded


func _cache_chunk(key: Vector3i) -> void:
	_fk = key
	var data: Variant = _chunks.get(key)
	_fl = data != null
	_fb = data if data != null else PackedByteArray()
	_fd = _density.get(key, PackedByteArray())


## Field value at a voxel (0..1); unloaded space reads as solid.
func voxel_field(p: Vector3i) -> float:
	var key := Vector3i(p.x >> 4, p.y >> 4, p.z >> 4)
	if key != _fk:
		_cache_chunk(key)
	if not _fl:
		return 1.0
	if _fb.is_empty():
		return 0.0 if _fd.is_empty() else minf(_fd[(p.x & 15) + ((p.z & 15) << 4) + ((p.y & 15) << 8)] / 255.0, 0.498)
	var i := (p.x & 15) + ((p.z & 15) << 4) + ((p.y & 15) << 8)
	var b := _fb[i]
	var smooth := Blocks.is_smooth(b)
	var d := (255 if smooth else 0) if _fd.is_empty() else int(_fd[i])
	if smooth:
		return maxf(d, 128) / 255.0
	if d >= 128 and (Blocks.family(b) == Blocks.Family.CUBE or Blocks.family(b) == Blocks.Family.STRUCTURE):
		return 0.52  # built block sunk into the ground (see SmoothMesher)
	return minf(d, 127) / 255.0


## Trilinear field value at a world position (>= 0.5 means inside smooth ground).
func field(p: Vector3) -> float:
	var q := p - Vector3(0.5, 0.5, 0.5)
	var x0 := floori(q.x)
	var y0 := floori(q.y)
	var z0 := floori(q.z)
	var tx := q.x - x0
	var ty := q.y - y0
	var tz := q.z - z0
	var c000 := voxel_field(Vector3i(x0, y0, z0))
	var c100 := voxel_field(Vector3i(x0 + 1, y0, z0))
	var c010 := voxel_field(Vector3i(x0, y0 + 1, z0))
	var c110 := voxel_field(Vector3i(x0 + 1, y0 + 1, z0))
	var c001 := voxel_field(Vector3i(x0, y0, z0 + 1))
	var c101 := voxel_field(Vector3i(x0 + 1, y0, z0 + 1))
	var c011 := voxel_field(Vector3i(x0, y0 + 1, z0 + 1))
	var c111 := voxel_field(Vector3i(x0 + 1, y0 + 1, z0 + 1))
	var a := lerpf(lerpf(c000, c100, tx), lerpf(c010, c110, tx), ty)
	var b := lerpf(lerpf(c001, c101, tx), lerpf(c011, c111, tx), ty)
	return lerpf(a, b, tz)


## Height of the smooth ground under (x, z), searching down from y_from for
## at most `depth` metres. Returns -INF when there is none in range.
func ground_below(x: float, y_from: float, z: float, depth: float) -> float:
	# Along a vertical line the trilinear field is linear between sample layers:
	# evaluate it at each layer (y = k + 0.5) and solve for the crossing.
	var qx := x - 0.5
	var qz := z - 0.5
	var x0 := floori(qx)
	var z0 := floori(qz)
	var tx := qx - x0
	var tz := qz - z0
	var k := floori(y_from - 0.5)
	var below := _column_value(x0, z0, tx, tz, k)
	var above := _column_value(x0, z0, tx, tz, k + 1)
	var prev := lerpf(below, above, (y_from - 0.5) - k)
	var prev_y := y_from
	if prev >= 0.5:
		return INF  # buried: the caller is inside the ground
	var k_end := floori(y_from - depth - 0.5)
	while k >= k_end:
		var v := _column_value(x0, z0, tx, tz, k)
		var vy := float(k) + 0.5
		if v >= 0.5:
			var t := (v - 0.5) / maxf(v - prev, 1e-5)
			var h := vy + t * (prev_y - vy)
			return h if h <= y_from + 0.001 else -INF
		prev = v
		prev_y = vy
		k -= 1
	return -INF


func _column_value(x0: int, z0: int, tx: float, tz: float, k: int) -> float:
	var a := lerpf(voxel_field(Vector3i(x0, k, z0)), voxel_field(Vector3i(x0 + 1, k, z0)), tx)
	var b := lerpf(voxel_field(Vector3i(x0, k, z0 + 1)), voxel_field(Vector3i(x0 + 1, k, z0 + 1)), tx)
	return lerpf(a, b, tz)


## Crisp cube (or trunk) block at p: these collide as boxes.
func is_box_solid(p: Vector3i) -> bool:
	var b := get_block(p)
	return b > 0 and Blocks.is_solid(b) and not Blocks.is_smooth(b)


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
	# Cave decoration (thousands of instanced crystals, fungi, dripstone) is
	# only drawn when it can be seen: from inside the caves, or near a mouth.
	var under := dimension != 2 and focus.y < gen.ground_level(focus.x, focus.z) - 4.0
	if under != _focus_under:
		_focus_under = under
		_refresh_decor()
	if flora != null and visible and meshing_enabled:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			flora.call("update_distance_lod", get_tree(), cam.global_position)
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
	var low := 1000
	# Include the neighbour edge: steep mountain faces span many vertical
	# chunks, not just the two chunks below a column's highest sample.
	for sz in [-1, 4, 8, 12, 16]:
		for sx in [-1, 4, 8, 12, 16]:
			var x: int = cx * 16 + sx
			var z: int = cz * 16 + sz
			if gen.in_bounds(x, z):
				var height := gen.surface_height(x, z)
				top = maxi(top, height)
				low = mini(low, height)
	_column_low[k] = floori(float(low) / 16.0) - 1
	var sea := WorldGen.SEA_LEVEL if dimension == 0 else WorldGen.LAVA_LEVEL
	top = maxi(top, sea) + 12
	var cy := floori(top / 16.0)
	_column_top[k] = cy
	return cy


func _rebuild_wanted(fkey: Vector3i) -> void:
	_wanted_mesh.clear()
	_wanted_data.clear()
	# Nearby peaks are not a ceiling above the player. Use the exact column.
	var underground := dimension != 2 and focus.y < gen.ground_level(focus.x, focus.z) - 8.0
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
				var low := int(_column_low.get(Vector2i(cx, cz), top - 2))
				if dimension == 2:
					low = maxi(0, low - 4)  # Floating islands also expose their underside.
				for y in range(maxi(low, WorldGen.Y_MIN / 16), top + 1):
					ys[y] = true
			for y: int in ys:
				if y * 16 > WorldGen.Y_MAX + 32 or y * 16 < WorldGen.Y_MIN - 16:
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
	var densities := []
	densities.resize(27)
	for dz in range(-1, 2):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				densities[(dx + 1) + (dy + 1) * 3 + (dz + 1) * 9] = _density.get(k + Vector3i(dx, dy, dz), PackedByteArray())
	WorkerThreadPool.add_task(_task_mesh.bind(k, neighbours, densities, version), false, "chunk mesh")
	return 1


## Skylight heights for the mesher: the lowest column within 2 m. A vertex on
## a cliff face sits far below its own column's top but is open to the sky
## sideways; only rock overhead on every side (caves, overhangs) darkens it.
## The 2 m border outside the chunk comes from the generator's smooth base
## height (a cheap, thread-safe lookup), so the shading has no chunk seams.
func _sky_heights(surface: PackedInt32Array, o: Vector3i) -> PackedInt32Array:
	if dimension == 2:
		return surface
	const B := 2
	const W := Chunk.SIZE + 2 * B
	var wide := PackedInt32Array()
	wide.resize(W * W)
	for z in W:
		for x in W:
			var lx := x - B
			var lz := z - B
			if lx >= 0 and lz >= 0 and lx < Chunk.SIZE and lz < Chunk.SIZE:
				wide[x + z * W] = surface[lx + lz * Chunk.SIZE]
			else:
				wide[x + z * W] = int(gen.smooth_height(o.x + lx, o.z + lz))
	# Separable 5x5 minimum: rows, then columns.
	var rows := PackedInt32Array()
	rows.resize(W * W)
	for z in W:
		for x in range(B, W - B):
			var lo := wide[x - B + z * W]
			for d in range(1, 2 * B + 1):
				lo = mini(lo, wide[x - B + d + z * W])
			rows[x + z * W] = lo
	var out := PackedInt32Array()
	out.resize(Chunk.AREA)
	for z in Chunk.SIZE:
		for x in Chunk.SIZE:
			var lo := rows[x + B + z * W]
			for d in range(1, 2 * B + 1):
				lo = mini(lo, rows[x + B + (z + d) * W])
			out[x + z * Chunk.SIZE] = lo
	return out


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
	var r := gen.generate(k)
	_lock.lock()
	_gen_results.append([k, r[0], r[1]])
	_lock.unlock()


func _task_mesh(k: Vector3i, neighbours: Array, densities: Array, version: int) -> void:
	var detail := gen.make_detail_noise()
	var ridge := gen.make_ridge_noise()
	var surface := PackedInt32Array()
	surface.resize(Chunk.AREA)
	var biomes := PackedByteArray()
	biomes.resize(Chunk.AREA)
	var o := k * Chunk.SIZE
	for z in Chunk.SIZE:
		for x in Chunk.SIZE:
			var wx := o.x + x
			var wz := o.z + z
			surface[x + z * Chunk.SIZE] = int(gen.column(wx, wz, detail, ridge).x) if gen.in_bounds(wx, wz) else -64
			biomes[x + z * Chunk.SIZE] = gen.biome_at(wx, wz)
	var result := ChunkMesher.build(neighbours, surface, o.y)
	var smooth := SmoothMesher.build(neighbours, densities, _sky_heights(surface, o), biomes, o, dimension)
	if smooth.has("terrain"):
		result["terrain"] = smooth["terrain"]
	if flora != null:
		var fs: Dictionary = smooth.get("flora_surface", {})
		var trees: Array = smooth.get("trees", [])
		if not fs.is_empty() or not trees.is_empty():
			if fs.is_empty():
				fs = {"tris": PackedVector3Array(), "normals": PackedVector3Array(), "blocks": PackedByteArray(), "sky": PackedFloat32Array()}
			result["flora"] = flora.call("plan_chunk", o, fs, trees, dimension, gen.world_seed)
	# Emissive blocks become light sources.
	var center: PackedByteArray = neighbours[13]
	var lights: Array = []
	# Cave decorations (world/caves/cave_decor.gd): ore nodules, dripstone, fungi, webs; glowing ones add lights.
	if dimension < 2 and smooth.has("terrain"):
		var decor := CaveDecor.plan_chunk(o, smooth["terrain"], dimension, gen.world_seed, center)
		if not decor.is_empty():
			result["cave_decor"] = decor
			lights.append_array(decor["lights"])
	var light_cells := {}
	if not center.is_empty():
		for i in Chunk.VOLUME:
			var b := center[i]
			if b != 0 and Blocks.light(b) > 0.0 and b != Blocks.LAVA and b != Blocks.HELLSTONE:
				var y := i / Chunk.AREA
				var z := (i % Chunk.AREA) / Chunk.SIZE
				var x := i % Chunk.SIZE
				if Blocks.is_smooth(b):
					# A buried vein contributes emission to its surface material,
					# not thousands of point lights. Only exposed deposits qualify.
					if x > 0 and x < 15 and y > 0 and y < 15 and z > 0 and z < 15:
						if center[i - 1] != 0 and center[i + 1] != 0 and center[i - 16] != 0 and center[i + 16] != 0 and center[i - 256] != 0 and center[i + 256] != 0:
							continue
					var light_cell := (x >> 3) + (z >> 3) * 2 + (y >> 3) * 4
					if light_cells.has(light_cell):
						continue
					light_cells[light_cell] = true
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
		var dens: PackedByteArray = r[2]
		_gen_pending.erase(k)
		if _edits.has(k):
			var entries: Dictionary = _edits[k]
			if dens.is_empty():
				dens = SmoothMesher.derive_density(data)
			if dens.is_empty():
				dens = Chunk.empty()
			for i: int in entries:
				var v: int = entries[i]
				data[i] = v & 255
				dens[i] = (v >> 8) - 1 if v >= 256 else _edit_density(v & 255, dens[i])
		# Density only matters near a surface: drop it when it says nothing.
		if not dens.is_empty() and (dens.count(0) == Chunk.VOLUME or dens.count(255) == Chunk.VOLUME):
			dens = PackedByteArray()
		_density[k] = dens
		if k == _fk:
			_fk = Vector3i(1 << 20, 0, 0)
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


## Horizon coverage is based on completed meshes, not distance alone.
func horizon_coverage() -> Image:
	var size := ceili(float(gen.size) / Chunk.SIZE)
	var image := Image.create(size, size, false, Image.FORMAT_R8)
	var columns := {}
	for key: Vector3i in _wanted_mesh:
		var column := Vector2i(key.x, key.z)
		columns[column] = bool(columns.get(column, true)) and _meshes.has(key)
	for column: Vector2i in columns:
		if columns[column] and column.x >= 0 and column.y >= 0 and column.x < size and column.y < size:
			image.set_pixel(column.x, column.y, Color.WHITE)
	return image


func _set_mesh(k: Vector3i, result: Dictionary) -> void:
	var old: MeshInstance3D = _meshes.get(k)
	if old != null:
		old.queue_free()
	_light_points[k] = result.get("lights", [])
	if not result.has("opaque") and not result.has("liquid") and not result.has("terrain") and not result.has("flora"):
		_meshes[k] = null
		return
	var mesh := ArrayMesh.new()
	if result.has("terrain"):
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, result["terrain"], [], {}, SmoothMesher.format_flags())
		mesh.surface_set_material(mesh.get_surface_count() - 1, terrain_material)
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
	if result.has("flora") and flora != null:
		var node: Node3D = flora.call("build_chunk", result["flora"], flora_quality)
		if node != null:
			mi.add_child(node)
	if result.has("cave_decor"):
		var decor_node := CaveDecor.build_chunk(result["cave_decor"], flora_quality)
		if decor_node != null:
			decor_node.visible = _decor_visible(k)
			mi.add_child(decor_node)


var _focus_under := false


## Decor in a chunk buried well below the ground is invisible from the surface.
func _decor_visible(k: Vector3i) -> bool:
	if _focus_under:
		return true
	var c := Vector3(k * Chunk.SIZE) + Vector3(8, 16, 8)
	return c.y > gen.ground_level(c.x, c.z) - 6.0


func _refresh_decor() -> void:
	for k: Vector3i in _meshes:
		var m: MeshInstance3D = _meshes[k]
		if m == null:
			continue
		var decor := m.get_node_or_null(^"CaveDecor") as Node3D
		if decor != null:
			decor.visible = _decor_visible(k)


func _shadow_setting(k: Vector3i) -> int:
	var c := Vector3(k * Chunk.SIZE) + Vector3(8, 8, 8)
	var near := c.distance_to(focus) < GraphicsQuality.shadow_caster_distance() + 12.0
	return GeometryInstance3D.SHADOW_CASTING_SETTING_ON if near and GraphicsQuality.shadows_enabled() else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


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
			_density.erase(k)
			_solid_uniform.erase(k)
			_fk = Vector3i(1 << 20, 0, 0)


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
					var distance := focus.distance_squared_to(p[0])
					if distance < 32.0 * 32.0:
						found.append([distance, p])
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
