class_name CaveNetwork
extends RefCounted
## Explicit underground features stitched into the noise caves (world revision 3):
##   * natural cave mouths on hillsides and ravine walls that wind down into the
##     cave network and end in a regional chamber,
##   * sinkholes (collapsed dolines) with a talus throat into a descending passage,
##   * underground rivers between neighbouring flooded chambers,
##   * the carved workings of every abandoned mine (drifts, rooms, declines).
##
## Every feature is a list of signed-distance "carvers" (metres, negative inside).
## WorldGen evaluates them per chunk on worker threads with carve_chunk(), which only
## visits the voxels inside each carver's bounding box. Read-only after plan().

enum Type { WORM, DRIFT, ROOM, FUNNEL, BLOB, SLOT }

const STRIDE := 17
const F_TYPE := 0
const F_AX := 1
const F_AY := 2
const F_AZ := 3
const F_BX := 4
const F_BY := 5
const F_BZ := 6
const F_R0 := 7
const F_R1 := 8
const F_WATER := 9
const F_FILL := 10
const F_ORE := 11
const F_ORE_CHANCE := 12
const F_LUMP := 13
const F_FLOOR := 14
const F_EXTRA := 15
## Revision 5: a CaveBiomes.Kind whose rock lines the carver (0 = the ordinary shell).
const F_SCHEME := 16
const NO_WATER := -100000.0
## Voxels this far outside a carver still record it (ore shells, floors, flood guards).
const SHELL := 2.5

## Natural cave mouths and sinkholes: [Vector3 surface entrance, Vector3 direction in, String kind].
var entrances: Array = []
## Underground rivers: [Vector3 from, Vector3 to, float water level].
var rivers: Array = []

var _data := PackedFloat32Array()
var _boxes: Array[AABB] = []
var _index := {}   # Vector2i chunk column -> PackedInt32Array of carver ids


func count() -> int:
	return _boxes.size()


func field(i: int, f: int) -> float:
	return _data[i * STRIDE + f]


func box(i: int) -> AABB:
	return _boxes[i]


# --- Building ---------------------------------------------------------------------------------

func _add(values: Array, aabb: AABB) -> int:
	var row := PackedFloat32Array(values)
	row.resize(STRIDE)
	_data.append_array(row)
	_boxes.append(aabb)
	return _boxes.size() - 1


## A natural passage: a capsule from a (radius r0) to b (radius r1) with a flattened floor and
## lumpy walls. `water` fills the passage below that height with `fill` (WATER or LAVA).
func add_worm(a: Vector3, b: Vector3, r0: float, r1: float, lump := 0.9, water := NO_WATER, fill := Blocks.WATER) -> int:
	var r := maxf(r0, r1) + lump + (SHELL + 4.0 if water > NO_WATER else 1.0)
	var lo := a.min(b) - Vector3(r, r, r)
	var hi := a.max(b) + Vector3(r, r, r)
	return _add([Type.WORM, a.x, a.y, a.z, b.x, b.y, b.z, r0, r1, water, fill, 0, 0, lump, 0, 0], AABB(lo, hi - lo))


## A mine drift: flat floor along a -> b (floor heights), vertical walls `half_width` from the
## centreline, rounded roof `height` above the floor. Optional ore shell and floor material.
func add_drift(a: Vector3, b: Vector3, half_width: float, height: float, floor_block := 0, ore := 0, ore_chance := 0.0, water := NO_WATER) -> int:
	var r := half_width * 1.6 + SHELL
	var lo := Vector3(minf(a.x, b.x) - r, minf(a.y, b.y) - SHELL - 1.0, minf(a.z, b.z) - r)
	var hi := Vector3(maxf(a.x, b.x) + r, maxf(a.y, b.y) + height + SHELL, maxf(a.z, b.z) + r)
	return _add([Type.DRIFT, a.x, a.y, a.z, b.x, b.y, b.z, half_width, height, water, Blocks.WATER, ore, ore_chance, 0.0, floor_block, 0], AABB(lo, hi - lo))


## A rectangular room (rounded corners) with its floor centre at `floor_center`, half extents
## (x, z), height and yaw. Optional ore shell (stopes) and floor material.
func add_room(floor_center: Vector3, half_x: float, half_z: float, height: float, yaw := 0.0, floor_block := 0, ore := 0, ore_chance := 0.0, water := NO_WATER) -> int:
	var r := sqrt(half_x * half_x + half_z * half_z) + SHELL
	var lo := floor_center - Vector3(r, SHELL + 1.0, r)
	var hi := floor_center + Vector3(r, height + SHELL, r)
	return _add([Type.ROOM, floor_center.x, floor_center.y, floor_center.z, half_x, height, half_z, 1.2, 0, water, Blocks.WATER, ore, ore_chance, 0.6, floor_block, yaw], AABB(lo, hi - lo))


## A sinkhole funnel: opening of radius `top_r` at height `top_y` narrowing to `bottom_r` at
## `depth` below it.
func add_funnel(center_xz: Vector2, top_y: float, top_r: float, depth: float, bottom_r: float, lump := 1.2) -> int:
	var r := top_r + 14.0 + SHELL
	var lo := Vector3(center_xz.x - r, top_y - depth - SHELL - 1.0, center_xz.y - r)
	var hi := Vector3(center_xz.x + r, top_y + 10.0, center_xz.y + r)
	return _add([Type.FUNNEL, center_xz.x, top_y, center_xz.y, 0, 0, 0, top_r, depth, NO_WATER, 0, 0, 0, lump, 0, bottom_r], AABB(lo, hi - lo))


## An irregular ellipsoidal pocket.
func add_blob(center: Vector3, radii: Vector3, lump := 1.0, water := NO_WATER, fill := Blocks.WATER) -> int:
	var r := radii + Vector3.ONE * (lump + SHELL)
	return _add([Type.BLOB, center.x, center.y, center.z, radii.x, radii.y, radii.z, 0, 0, water, fill, 0, 0, lump, 0, 0], AABB(center - r, r * 2.0))


## A fissure (revision 5): a tall, narrow slot along a -> b (floor heights), `half_width` at
## its widest, pinching shut `height` above the floor; rough walls.
func add_slot(a: Vector3, b: Vector3, half_width: float, height: float, lump := 1.0) -> int:
	var r := half_width + lump + SHELL + 1.0
	var lo := Vector3(minf(a.x, b.x) - r, minf(a.y, b.y) - SHELL - 1.0, minf(a.z, b.z) - r)
	var hi := Vector3(maxf(a.x, b.x) + r, maxf(a.y, b.y) + height + SHELL, maxf(a.z, b.z) + r)
	return _add([Type.SLOT, a.x, a.y, a.z, b.x, b.y, b.z, half_width, height, NO_WATER, 0, 0, 0, lump, 0, 0], AABB(lo, hi - lo))


## Lines carver `i` with the rock of a cave biome (CaveBiomes.Kind, see UndergroundPlan.shell_block).
func set_scheme(i: int, kind: int) -> void:
	_data[i * STRIDE + F_SCHEME] = kind


## Adds every carver of another network (mine workings planned with their location).
func merge(other: CaveNetwork) -> void:
	_data.append_array(other._data)
	_boxes.append_array(other._boxes)
	entrances.append_array(other.entrances)


func build_index() -> void:
	_index.clear()
	for i in _boxes.size():
		var b := _boxes[i]
		for cz in range(floori(b.position.z / 16.0), floori(b.end.z / 16.0) + 1):
			for cx in range(floori(b.position.x / 16.0), floori(b.end.x / 16.0) + 1):
				var k := Vector2i(cx, cz)
				var list: PackedInt32Array = _index.get(k, PackedInt32Array())
				list.append(i)
				_index[k] = list


## Carvers whose bounds reach the chunk.
func chunk_carvers(key: Vector3i) -> PackedInt32Array:
	var list: PackedInt32Array = _index.get(Vector2i(key.x, key.z), PackedInt32Array())
	if list.is_empty():
		return list
	var out := PackedInt32Array()
	var y0 := float(key.y * 16)
	for i in list:
		var b := _boxes[i]
		if b.position.y <= y0 + 16.0 and b.end.y >= y0:
			out.append(i)
	return out


## Signed distance at one point (main thread helpers and tests).
func sdf_at(p: Vector3) -> float:
	var best := INF
	var key := Vector3i(floori(p.x / 16.0), floori(p.y / 16.0), floori(p.z / 16.0))
	for i in chunk_carvers(key):
		best = minf(best, _sdf(i, p, 0.0))
	return best


# --- Evaluation (worker threads) --------------------------------------------------------------

## Fills `sdf` (chunk voxel order x + z*16 + y*256, initialised to INF) with the minimum signed
## distance of the given carvers and `owner` with the carver id that owns each voxel (-1 none).
## `lump` is a native noise block (x + y*16 + z*256 order, 0..255) for rough walls.
func carve_chunk(o: Vector3i, ids: PackedInt32Array, lump: PackedByteArray, sdf: PackedFloat32Array, owner: PackedInt32Array) -> void:
	for i in ids:
		var b := _boxes[i]
		var x0 := maxi(floori(b.position.x) - o.x, 0)
		var y0 := maxi(floori(b.position.y) - o.y, 0)
		var z0 := maxi(floori(b.position.z) - o.z, 0)
		var x1 := mini(ceili(b.end.x) - o.x, 15)
		var y1 := mini(ceili(b.end.y) - o.y, 15)
		var z1 := mini(ceili(b.end.z) - o.z, 15)
		if x0 > x1 or y0 > y1 or z0 > z1:
			continue
		var base := i * STRIDE
		var type := int(_data[base + F_TYPE])
		var a := Vector3(_data[base + F_AX], _data[base + F_AY], _data[base + F_AZ])
		var bb := Vector3(_data[base + F_BX], _data[base + F_BY], _data[base + F_BZ])
		var r0 := _data[base + F_R0]
		var r1 := _data[base + F_R1]
		var lump_amp := _data[base + F_LUMP] / 127.5
		var extra := _data[base + F_EXTRA]
		match type:
			Type.WORM:
				var ab := bb - a
				var inv := 1.0 / maxf(ab.length_squared(), 0.0001)
				for y in range(y0, y1 + 1):
					var py := float(o.y + y) + 0.5
					for z in range(z0, z1 + 1):
						var pz := float(o.z + z) + 0.5
						for x in range(x0, x1 + 1):
							var p := Vector3(float(o.x + x) + 0.5, py, pz)
							var t := clampf((p - a).dot(ab) * inv, 0.0, 1.0)
							var q := p - (a + ab * t)
							var r := lerpf(r0, r1, t)
							var d := maxf(q.length() - r, -(q.y + r * 0.55))
							if not lump.is_empty():
								d += (float(lump[x + y * 16 + z * 256]) - 127.5) * lump_amp
							var vi := x + z * 16 + y * 256
							if d < sdf[vi]:
								sdf[vi] = d
								owner[vi] = i
			Type.DRIFT:
				var dir := Vector2(bb.x - a.x, bb.z - a.z)
				var length := maxf(dir.length(), 0.001)
				dir /= length
				var w := r0
				var hh := r1 * 0.5
				const RC := 0.9
				for y in range(y0, y1 + 1):
					var py := float(o.y + y) + 0.5
					for z in range(z0, z1 + 1):
						var rz := float(o.z + z) + 0.5 - a.z
						for x in range(x0, x1 + 1):
							var rx := float(o.x + x) + 0.5 - a.x
							var along := rx * dir.x + rz * dir.y
							var lat := absf(rx * dir.y - rz * dir.x)
							var t := clampf(along / length, 0.0, 1.0)
							var v := py - lerpf(a.y, bb.y, t)
							var qx := lat - (w - RC)
							var qy := absf(v - hh) - (hh - RC)
							var d := Vector2(maxf(qx, 0.0), maxf(qy, 0.0)).length() + minf(maxf(qx, qy), 0.0) - RC
							d = maxf(d, maxf(-along - w * 0.6, along - length - w * 0.6))
							var vi := x + z * 16 + y * 256
							if d < sdf[vi]:
								sdf[vi] = d
								owner[vi] = i
			Type.ROOM:
				var cs := cos(extra)
				var sn := sin(extra)
				var hx := bb.x
				var hz := bb.z
				var hh := bb.y * 0.5
				var rc := r0
				for y in range(y0, y1 + 1):
					var v := float(o.y + y) + 0.5 - a.y
					for z in range(z0, z1 + 1):
						var dz := float(o.z + z) + 0.5 - a.z
						for x in range(x0, x1 + 1):
							var dx := float(o.x + x) + 0.5 - a.x
							var lx := absf(dx * cs - dz * sn) - (hx - rc)
							var lz := absf(dx * sn + dz * cs) - (hz - rc)
							var ly := absf(v - hh) - (hh - rc)
							var q := Vector3(maxf(lx, 0.0), maxf(ly, 0.0), maxf(lz, 0.0))
							var d := q.length() + minf(maxf(lx, maxf(ly, lz)), 0.0) - rc
							if not lump.is_empty() and v > 0.8:
								d += (float(lump[x + y * 16 + z * 256]) - 127.5) * lump_amp
							var vi := x + z * 16 + y * 256
							if d < sdf[vi]:
								sdf[vi] = d
								owner[vi] = i
			Type.FUNNEL:
				var top_y := a.y
				var depth := r1
				var top_r := r0
				var bottom_r := extra
				var yb := top_y - depth
				for y in range(y0, y1 + 1):
					var py := float(o.y + y) + 0.5
					var f := (py - yb) / depth
					var rad := bottom_r + (top_r - bottom_r) * pow(clampf(f, 0.0, 1.0), 1.7)
					if f > 1.0:
						rad = top_r + (py - top_y) * 1.4
					for z in range(z0, z1 + 1):
						var dz := float(o.z + z) + 0.5 - a.z
						for x in range(x0, x1 + 1):
							var dx := float(o.x + x) + 0.5 - a.x
							var d := maxf(sqrt(dx * dx + dz * dz) - rad, yb - py)
							if not lump.is_empty():
								d += (float(lump[x + y * 16 + z * 256]) - 127.5) * lump_amp
							var vi := x + z * 16 + y * 256
							if d < sdf[vi]:
								sdf[vi] = d
								owner[vi] = i
			Type.BLOB:
				var radii := Vector3(bb.x, bb.y, bb.z)
				var mr := minf(radii.x, minf(radii.y, radii.z))
				for y in range(y0, y1 + 1):
					var py := float(o.y + y) + 0.5
					for z in range(z0, z1 + 1):
						var pz := float(o.z + z) + 0.5
						for x in range(x0, x1 + 1):
							var q := (Vector3(float(o.x + x) + 0.5, py, pz) - a) / radii
							var d := (q.length() - 1.0) * mr
							d = maxf(d, -(q.y + 0.6) * radii.y)
							if not lump.is_empty():
								d += (float(lump[x + y * 16 + z * 256]) - 127.5) * lump_amp
							var vi := x + z * 16 + y * 256
							if d < sdf[vi]:
								sdf[vi] = d
								owner[vi] = i
			Type.SLOT:
				var dir := Vector2(bb.x - a.x, bb.z - a.z)
				var length := maxf(dir.length(), 0.001)
				dir /= length
				for y in range(y0, y1 + 1):
					var py := float(o.y + y) + 0.5
					for z in range(z0, z1 + 1):
						var rz := float(o.z + z) + 0.5 - a.z
						for x in range(x0, x1 + 1):
							var rx := float(o.x + x) + 0.5 - a.x
							var d := _slot(rx, rz, py, dir, length, a.y, bb.y, r0, r1)
							if not lump.is_empty():
								d += (float(lump[x + y * 16 + z * 256]) - 127.5) * lump_amp
							var vi := x + z * 16 + y * 256
							if d < sdf[vi]:
								sdf[vi] = d
								owner[vi] = i


## Fissure distance (approximate): lens-shaped cross-section, flat floor, rounded ends.
static func _slot(rx: float, rz: float, py: float, dir: Vector2, length: float, ya: float, yb: float, hw: float, height: float) -> float:
	var along := rx * dir.x + rz * dir.y
	var lat := absf(rx * dir.y - rz * dir.x)
	var t := clampf(along / length, 0.0, 1.0)
	var v := py - lerpf(ya, yb, t)
	var f := (v - 0.35 * height) / (0.65 * height)
	var w := hw * sqrt(maxf(0.0, 1.0 - f * f)) * (0.55 + 0.45 * sin(t * PI))
	var d := maxf(lat - w, -v)
	return maxf(d, maxf(-along - hw, along - length - hw))


## Single-point signed distance (no wall noise).
func _sdf(i: int, p: Vector3, _noise: float) -> float:
	var base := i * STRIDE
	var a := Vector3(_data[base + F_AX], _data[base + F_AY], _data[base + F_AZ])
	var bb := Vector3(_data[base + F_BX], _data[base + F_BY], _data[base + F_BZ])
	var r0 := _data[base + F_R0]
	var r1 := _data[base + F_R1]
	match int(_data[base + F_TYPE]):
		Type.WORM:
			var ab := bb - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			var q := p - (a + ab * t)
			var r := lerpf(r0, r1, t)
			return maxf(q.length() - r, -(q.y + r * 0.55))
		Type.DRIFT:
			var dir := Vector2(bb.x - a.x, bb.z - a.z)
			var length := maxf(dir.length(), 0.001)
			dir /= length
			var rx := p.x - a.x
			var rz := p.z - a.z
			var along := rx * dir.x + rz * dir.y
			var lat := absf(rx * dir.y - rz * dir.x)
			var v := p.y - lerpf(a.y, bb.y, clampf(along / length, 0.0, 1.0))
			var qx := lat - (r0 - 0.9)
			var qy := absf(v - r1 * 0.5) - (r1 * 0.5 - 0.9)
			var d := Vector2(maxf(qx, 0.0), maxf(qy, 0.0)).length() + minf(maxf(qx, qy), 0.0) - 0.9
			return maxf(d, maxf(-along - r0 * 0.6, along - length - r0 * 0.6))
		Type.ROOM:
			var extra := _data[base + F_EXTRA]
			var dx := p.x - a.x
			var dz := p.z - a.z
			var lx := absf(dx * cos(extra) - dz * sin(extra)) - (bb.x - r0)
			var lz := absf(dx * sin(extra) + dz * cos(extra)) - (bb.z - r0)
			var ly := absf(p.y - a.y - bb.y * 0.5) - (bb.y * 0.5 - r0)
			return Vector3(maxf(lx, 0.0), maxf(ly, 0.0), maxf(lz, 0.0)).length() + minf(maxf(lx, maxf(ly, lz)), 0.0) - r0
		Type.FUNNEL:
			var yb := a.y - r1
			var f := (p.y - yb) / r1
			var rad := _data[base + F_EXTRA] + (r0 - _data[base + F_EXTRA]) * pow(clampf(f, 0.0, 1.0), 1.7)
			if f > 1.0:
				rad = r0 + (p.y - a.y) * 1.4
			return maxf(Vector2(p.x - a.x, p.z - a.z).length() - rad, yb - p.y)
		Type.BLOB:
			var radii := Vector3(bb.x, bb.y, bb.z)
			var q := (p - a) / radii
			return maxf((q.length() - 1.0) * minf(radii.x, minf(radii.y, radii.z)), -(q.y + 0.6) * radii.y)
		Type.SLOT:
			var dir := Vector2(bb.x - a.x, bb.z - a.z)
			var length := maxf(dir.length(), 0.001)
			return _slot(p.x - a.x, p.z - a.z, p.y, dir / length, length, a.y, bb.y, r0, r1)
	return INF


# --- Natural features (revision 3, planned once in WorldGen.prepare) ----------------------------

const MOUTH_CELL := 170
## Chance of a cave mouth per cell, by biome (WorldGen.Biome order).
const MOUTH_CHANCE := [0.0, 0.22, 0.42, 0.6, 0.0, 0.35, 0.0, 0.0, 0.0, 0.0, 0.55, 0.62, 0.55, 0.22, 0.45, 0.4]
const SINK_CELL := 290
const SINK_CHANCE := [0.0, 0.3, 0.35, 0.08, 0.0, 0.2, 0.0, 0.0, 0.0, 0.0, 0.4, 0.22, 0.12, 0.32, 0.22, 0.08]
## Steepest descent of a natural passage (rise over run).
const MAX_GRADE := 0.34


static func plan_natural(gen: WorldGen) -> CaveNetwork:
	var net := CaveNetwork.new()
	var detail := gen.make_detail_noise()
	var ridge := gen.make_ridge_noise()
	var rng := RandomNumberGenerator.new()
	# Cave mouths: on hillsides a passage breaks into the slope; on level ground a small pit.
	for cz in range(1, gen.size / MOUTH_CELL - 1):
		for cx in range(1, gen.size / MOUTH_CELL - 1):
			var h := WorldGen._hash3(cx, 7, cz, gen.world_seed + 5150)
			var p := Vector2(cx * MOUTH_CELL + 20 + (h & 127), cz * MOUTH_CELL + 20 + ((h >> 7) & 127))
			var biome := gen.biome_at(int(p.x), int(p.y))
			if float((h >> 14) & 1023) / 1023.0 >= float(MOUTH_CHANCE[biome]):
				continue
			rng.seed = h
			_mouth(net, gen, p, rng, detail, ridge)
	# Sinkholes: collapsed dolines with a talus throat into a descending passage.
	for cz in range(1, gen.size / SINK_CELL - 1):
		for cx in range(1, gen.size / SINK_CELL - 1):
			var h := WorldGen._hash3(cx, 11, cz, gen.world_seed + 5170)
			var p := Vector2(cx * SINK_CELL + 40 + (h & 127) + ((h >> 21) & 63), cz * SINK_CELL + 40 + ((h >> 7) & 127) + ((h >> 27) & 15))
			var biome := gen.biome_at(int(p.x), int(p.y))
			if float((h >> 14) & 127) / 127.0 >= float(SINK_CHANCE[biome]):
				continue
			rng.seed = h
			_sinkhole(net, gen, p, rng, detail, ridge)
	# Underground rivers between neighbouring flooded chambers.
	var n := gen.size / int(CaveBiomes.CELL.x)
	for kz in n:
		for kx in n:
			var c := (Vector3(kx, -1, kz) + Vector3(0.5, 0.5, 0.5)) * CaveBiomes.CELL
			var r := CaveBiomes.region(c, gen.world_seed, gen.revision)
			if int(r["kind"]) != CaveBiomes.Kind.FLOODED:
				continue
			for step: Vector3 in [Vector3(CaveBiomes.CELL.x, 0, 0), Vector3(0, 0, CaveBiomes.CELL.z)]:
				var other := CaveBiomes.region(c + step, gen.world_seed, gen.revision)
				if int(other["kind"]) == CaveBiomes.Kind.FLOODED and (c + step).x < gen.size and (c + step).z < gen.size:
					rng.seed = int(r["seed"]) + int(step.x)
					_river(net, r, other, rng)
	return net


static func _ground(gen: WorldGen, x: float, z: float, detail: FastNoiseLite, ridge: FastNoiseLite) -> float:
	return gen.column_f(int(x), int(z), detail, ridge).x + 1.0


static func _mouth(net: CaveNetwork, gen: WorldGen, p: Vector2, rng: RandomNumberGenerator, detail: FastNoiseLite, ridge: FastNoiseLite) -> void:
	if gen.is_protected(p.x, p.y) or gen.lake_level(p.x, p.y).x > -INF:
		return
	var g := _ground(gen, p.x, p.y, detail, ridge)
	if g < WorldGen.SEA_LEVEL + 5.0:
		return
	var grad := Vector2(_ground(gen, p.x + 4, p.y, detail, ridge) - _ground(gen, p.x - 4, p.y, detail, ridge),
			_ground(gen, p.x, p.y + 4, detail, ridge) - _ground(gen, p.x, p.y - 4, detail, ridge)) / 8.0
	var slope := grad.length()
	var radius := rng.randf_range(2.6, 3.6)
	if slope < 0.14:
		# Level ground: a rocky pit opening into a passage.
		var heading := Vector2.from_angle(rng.randf() * TAU)
		var depth := rng.randf_range(6.0, 8.0)
		net.add_funnel(p, g + 0.6, rng.randf_range(5.5, 7.5), depth, radius, 1.0)
		var start := Vector3(p.x, g + 0.6 - depth + radius * 0.55 + 0.3, p.y)
		if _passage(net, gen, start, heading, rng, 2.5, 3.6, detail, ridge):
			net.entrances.append([Vector3(p.x, g, p.y), Vector3(heading.x, -0.4, heading.y), "pit"])
		return
	if slope > 1.6:
		return  # sheer faces: no footing at the mouth
	var into := grad / slope
	var e := Vector3(p.x, g, p.y)
	var a := e - Vector3(into.x, 0, into.y) * 3.0 + Vector3(0, radius * 0.55 - 0.4, 0)
	var b := e + Vector3(into.x, 0, into.y) * 13.0 + Vector3(0, radius * 0.55 - 2.2, 0)
	# The first stretch must stay under rock (not punch out of a thin spur).
	var cover := _ground(gen, b.x, b.z, detail, ridge) - b.y
	if cover < radius + 1.5:
		return
	var first := net.count()
	net.add_worm(a, b, radius + 0.6, radius, 1.1)
	if _passage(net, gen, b, into, rng, 2.4, 3.6, detail, ridge):
		net.entrances.append([e, Vector3(into.x, -0.15, into.y), "mouth"])
	else:
		net._truncate(first)


## A winding natural passage from `start` down to the cave chamber of its region. Returns false
## (and adds nothing) when it would break out under a protected site.
static func _passage(net: CaveNetwork, gen: WorldGen, start: Vector3, heading: Vector2, rng: RandomNumberGenerator, r_min: float, r_max: float, detail: FastNoiseLite, ridge: FastNoiseLite) -> bool:
	var first := net.count()
	var region := CaveBiomes.region(Vector3(start.x, -32.0, start.z), gen.world_seed, gen.revision)
	var c: Vector3 = region["center"]
	var pool := CaveBiomes.pool_level(region)
	var away := Vector2(start.x - c.x, start.z - c.z)
	away = away.normalized() if away.length() > 1.0 else Vector2.RIGHT
	var target := Vector3(c.x + away.x * CaveBiomes.RADII.x * 0.5, c.y - CaveBiomes.RADII.y * 0.28, c.z + away.y * CaveBiomes.RADII.z * 0.5)
	if pool > -INF:
		target.y = pool + 2.8
	var cur := start
	var dir := heading.normalized()
	var r := rng.randf_range(r_min, r_max)
	var spin := 1.0 if rng.randf() < 0.5 else -1.0
	const STEP := 11.0
	for seg in 60:
		var to_t := Vector2(target.x - cur.x, target.z - cur.z)
		var dist := to_t.length()
		var drop := cur.y - target.y
		var next := Vector3.ZERO
		if dist < STEP * 1.3 and absf(drop) < STEP * MAX_GRADE * 1.3:
			next = target
		else:
			var want := to_t / maxf(dist, 0.001)
			if drop > (dist - STEP) * MAX_GRADE:
				# Too steep to head straight there: wind around it while descending.
				want = (want.orthogonal() * spin * 0.85 + want * (0.15 if dist > 40.0 else -0.4)).normalized()
			dir = (dir * 0.5 + want * 0.5 + Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3))).normalized()
			var dy := -clampf(drop, -STEP * 0.15, STEP * MAX_GRADE)
			next = cur + Vector3(dir.x * STEP, dy, dir.y * STEP)
		# Shallow stretches must not open under villages, roads or lakes.
		var surface := _ground(gen, next.x, next.z, detail, ridge)
		if next.y > surface - r - 3.0 and (gen.is_protected(next.x, next.z) or next.y > surface - 1.0):
			if seg < 3:
				net._truncate(first)
				return false
		if next.x < 40 or next.z < 40 or next.x > gen.size - 40 or next.z > gen.size - 40:
			net._truncate(first)
			return false
		var r2 := clampf(r + rng.randf_range(-0.6, 0.6), r_min, r_max)
		net.add_worm(cur, next, r, r2, 0.9)
		# Now and then a wider gallery along the way.
		if seg % 7 == 4 and rng.randf() < 0.6:
			net.add_blob(next + Vector3(0, 1.2, 0), Vector3(rng.randf_range(5, 8), rng.randf_range(3.2, 4.5), rng.randf_range(5, 8)), 1.2)
		r = r2
		cur = next
		if next == target:
			net.add_blob(target + Vector3(0, 0.8, 0), Vector3(r + 3.0, r + 1.0, r + 3.0), 1.0)
			return true
	return true


static func _sinkhole(net: CaveNetwork, gen: WorldGen, p: Vector2, rng: RandomNumberGenerator, detail: FastNoiseLite, ridge: FastNoiseLite) -> void:
	if gen.is_protected(p.x, p.y) or gen.lake_level(p.x, p.y).x > -INF:
		return
	var g := _ground(gen, p.x, p.y, detail, ridge)
	if g < WorldGen.SEA_LEVEL + 10.0:
		return
	# Level ground only: the rim must not dip on one side.
	for k in 8:
		var q := p + Vector2.from_angle(TAU * k / 8.0) * 16.0
		if absf(_ground(gen, q.x, q.y, detail, ridge) - g) > 5.0 or gen.is_protected(q.x, q.y):
			return
	var first := net.count()
	var top_r := rng.randf_range(10.0, 15.0)
	var depth := rng.randf_range(12.0, 16.0)
	var top_y := g + 0.8
	net.add_funnel(p, top_y, top_r, depth, 3.4, 1.4)
	var heading := Vector2.from_angle(rng.randf() * TAU)
	var start := Vector3(p.x, top_y - depth + 3.4 * 0.55 + 0.4, p.y)
	if _passage(net, gen, start, heading, rng, 2.6, 3.8, detail, ridge):
		net.entrances.append([Vector3(p.x, g, p.y), Vector3(0, -1, 0), "sinkhole"])
	else:
		net._truncate(first)


static func _river(net: CaveNetwork, a_region: Dictionary, b_region: Dictionary, rng: RandomNumberGenerator) -> void:
	var a: Vector3 = a_region["center"]
	var b: Vector3 = b_region["center"]
	var level := CaveBiomes.pool_level(a_region)
	var dir := (b - a).normalized()
	var side := Vector3(-dir.z, 0, dir.x)
	var p0 := a + dir * CaveBiomes.RADII.x * 0.55
	var p1 := b - dir * CaveBiomes.RADII.x * 0.55
	var pts: Array[Vector3] = [p0]
	var segs := 5
	for i in range(1, segs):
		var t := float(i) / segs
		pts.append(p0.lerp(p1, t) + side * rng.randf_range(-14.0, 14.0))
	pts.append(p1)
	var r := 3.4
	for i in pts.size() - 1:
		var s := pts[i]
		var e := pts[i + 1]
		s.y = level + 0.7
		e.y = level + 0.7
		var r2 := rng.randf_range(3.0, 4.2)
		net.add_worm(s, e, r, r2, 0.7, level, Blocks.WATER)
		r = r2
	net.rivers.append([p0, p1, level])


func _truncate(n: int) -> void:
	if n >= _boxes.size():
		return
	_boxes.resize(n)
	_data.resize(n * STRIDE)
