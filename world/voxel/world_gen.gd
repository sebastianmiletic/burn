class_name WorldGen
extends RefCounted
## Deterministic terrain generation for one dimension.
##
## prepare() runs once (on a loading screen): it builds coarse biome / height
## maps with native noise, plans every named location (villages, castles,
## the Hall of the Mountain King, the Gates of Hades...), builds their
## blueprints and rasterises roads and flattened building pads.
##
## generate_chunk() is thread-safe and called from worker threads.

enum Dimension { OVERWORLD, HELL, RYFT }
enum Biome { OCEAN, PLAINS, FOREST, PEAKS, MARSH, WASTES, ASPHODEL, LAKE_OF_FIRE, TARTARUS, RYFT }

const BIOME_NAMES := ["The Grey Sea", "The Ashen Plains", "Emberwood", "Frost Peaks", "Blackmarsh",
		"Cinder Wastes", "Asphodel Fields", "Lake of Fire", "Tartarus", "Ryft Island"]

const SEA_LEVEL := 12
const LAVA_LEVEL := 0  ## hell
const COARSE := 4      ## metres per coarse map cell
const Y_MIN := -128
const Y_MAX := 383

# base height, detail amplitude, ridge amplitude
const BIOME_SHAPE := {
	Biome.OCEAN: Vector3(-8.0, 3.0, 0.0),
	Biome.PLAINS: Vector3(20.0, 4.5, 0.0),
	Biome.FOREST: Vector3(24.0, 8.0, 0.0),
	Biome.PEAKS: Vector3(44.0, 10.0, 62.0),
	Biome.MARSH: Vector3(11.0, 2.2, 0.0),
	Biome.WASTES: Vector3(22.0, 5.0, 9.0),
	Biome.ASPHODEL: Vector3(10.0, 4.0, 0.0),
	Biome.LAKE_OF_FIRE: Vector3(-6.0, 3.0, 0.0),
	Biome.TARTARUS: Vector3(16.0, 6.0, 22.0),
	Biome.RYFT: Vector3(80.0, 5.0, 16.0),
}

var dimension := Dimension.OVERWORLD
var world_seed := 1
var revision := 2  ## Saves made before this update retain revision 1 terrain.
var size := 2048  ## world extent in blocks (x and z)
var locations: Array[Location] = []

var _coarse_n := 512
var _base := PackedFloat32Array()
var _amp := PackedFloat32Array()
var _ridge := PackedFloat32Array()
var _biome := PackedByteArray()
var _biome_seeds: Array = []  # [Vector2 position, biome]
## Column overrides: key (x + z * size) -> Vector3(target height, blend 0..1, road 0/1)
var _pads := {}
var _blueprints: Array[Blueprint] = []
var _crater := Vector3(1024, 1555, 70)  # x, z, radius (overworld)


func _init(dim: Dimension, seed_value: int, world_revision := 2) -> void:
	dimension = dim
	world_seed = seed_value
	revision = world_revision
	size = (3072 if revision >= 2 else 2048) if dim == Dimension.OVERWORLD else 640
	_coarse_n = size / COARSE


func center() -> Vector2:
	# Keep the campaign coordinates; new islands extend east/south.
	return Vector2(1024, 1024) if dimension == Dimension.OVERWORLD else Vector2(size * 0.5, size * 0.5)


# --- Preparation --------------------------------------------------------------

func prepare(progress: Callable = Callable()) -> void:
	var t := Time.get_ticks_msec()
	_setup_biome_seeds()
	_report(progress, 0.05, "Shaping the land")
	_build_coarse_maps()
	var t_coarse := Time.get_ticks_msec() - t
	_report(progress, 0.45, "Raising the ruins")
	var planner := LocationPlanner.new(self)
	locations = planner.plan()
	for loc in locations:
		_blueprints.append_array(loc.blueprints)
	var t_plan := Time.get_ticks_msec() - t - t_coarse
	_report(progress, 0.75, "Laying the old roads")
	_rasterise_pads()
	_report(progress, 1.0, "Done")
	if "--load-timing" in OS.get_cmdline_user_args():
		print("[load]   dim %d: coarse %d ms, plan %d ms, pads/roads %d ms" % [dimension, t_coarse, t_plan, Time.get_ticks_msec() - t - t_coarse - t_plan])


func _report(progress: Callable, value: float, text: String) -> void:
	if progress.is_valid():
		progress.call(value, text)


func _setup_biome_seeds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var j := func(p: Vector2) -> Vector2: return p + Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40))
	if dimension == Dimension.OVERWORLD:
		_biome_seeds = [
			[j.call(Vector2(1024, 1024)), Biome.PLAINS], [j.call(Vector2(1180, 860)), Biome.PLAINS], [j.call(Vector2(860, 1180)), Biome.PLAINS],
			[j.call(Vector2(1560, 1020)), Biome.FOREST], [j.call(Vector2(1440, 700)), Biome.FOREST], [j.call(Vector2(1480, 1360)), Biome.FOREST],
			[j.call(Vector2(1024, 330)), Biome.PEAKS], [j.call(Vector2(700, 420)), Biome.PEAKS], [j.call(Vector2(1340, 380)), Biome.PEAKS],
			[j.call(Vector2(420, 1050)), Biome.MARSH], [j.call(Vector2(520, 1380)), Biome.MARSH], [j.call(Vector2(480, 740)), Biome.MARSH],
			[j.call(Vector2(1024, 1700)), Biome.WASTES], [j.call(Vector2(1300, 1660)), Biome.WASTES], [j.call(Vector2(760, 1650)), Biome.WASTES],
		]
	elif dimension == Dimension.RYFT:
		_biome_seeds = [[Vector2(320, 320), Biome.RYFT]]
	else:
		_biome_seeds = [
			[Vector2(320, 320), Biome.ASPHODEL], [Vector2(200, 260), Biome.ASPHODEL],
			[Vector2(470, 240), Biome.LAKE_OF_FIRE], [Vector2(150, 470), Biome.LAKE_OF_FIRE], [Vector2(500, 520), Biome.LAKE_OF_FIRE],
			[Vector2(320, 120), Biome.TARTARUS], [Vector2(320, 520), Biome.TARTARUS],
		]


func _noise(type: int, freq: float, octaves: int, seed_offset: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = type
	n.frequency = freq
	n.fractal_octaves = octaves
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	n.seed = world_seed + seed_offset
	return n


func _build_coarse_maps() -> void:
	var n := _coarse_n
	_base.resize(n * n)
	_amp.resize(n * n)
	_ridge.resize(n * n)
	_biome.resize(n * n)
	var task := WorkerThreadPool.add_group_task(_coarse_rows, n, -1, true, "coarse maps")
	WorkerThreadPool.wait_for_group_task_completion(task)


func _coarse_rows(row: int) -> void:
	var warp := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0025, 3, 11)
	var warp2 := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0025, 3, 12)
	var macro := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.004, 2, 13)
	var n := _coarse_n
	var c := center()
	var seeds := _biome_seeds
	for col in n:
		var p := Vector2(col * COARSE + COARSE * 0.5, row * COARSE + COARSE * 0.5)
		var wp := p + Vector2(warp.get_noise_2dv(p), warp2.get_noise_2dv(p)) * (130.0 if dimension == Dimension.OVERWORLD else 60.0)
		var total := 0.0
		var shape := Vector3.ZERO
		var best := 1e20
		var best_biome := 0
		for s: Array in seeds:
			var d := wp.distance_squared_to(s[0])
			var w := 1.0 / (d * d + 1.0)
			total += w
			var biome_shape: Vector3 = BIOME_SHAPE[s[1]]
			if revision >= 2 and s[1] == Biome.PEAKS:
				biome_shape = Vector3(105.0, 22.0, 190.0)
			shape += biome_shape * w
			if d < best:
				best = d
				best_biome = s[1]
		shape /= total
		shape.x += macro.get_noise_2dv(p) * 4.0
		if dimension == Dimension.OVERWORLD:
			# An island: the sea closes in past ~900 m from the centre.
			var r := p.distance_to(c)
			var coast := warp.get_noise_2dv(p * 2.0) * (160.0 if revision >= 2 else 60.0)
			if revision >= 2:
				coast += sin((p - c).angle() * 5.0 + 0.7) * 65.0
			var t := smoothstep(860.0, 990.0, r + coast)
			shape = shape.lerp(BIOME_SHAPE[Biome.OCEAN], t)
			if t > 0.5:
				best_biome = Biome.OCEAN
			if revision >= 2:
				# Asymmetric outlying islands, reefs and channels.
				for island: Vector3 in [Vector3(2290, 1260, 230), Vector3(2180, 2230, 330), Vector3(1210, 2480, 210)]:
					var edge := p.distance_to(Vector2(island.x, island.y)) + warp2.get_noise_2dv(p * 3.0) * 95.0
					var land := 1.0 - smoothstep(island.z * 0.65, island.z, edge)
					shape = shape.lerp(Vector3(32, 12, 18), land)
					if land > 0.5:
						best_biome = Biome.FOREST
			# The Cinder Crater above the Gates of Hades.
			var cd := p.distance_to(Vector2(_crater.x, _crater.y))
			shape.x -= 22.0 * (1.0 - smoothstep(0.0, _crater.z, cd))
			shape.x += 7.0 * exp(-pow((cd - _crater.z) / 14.0, 2.0))
			shape.z *= smoothstep(_crater.z * 0.6, _crater.z * 1.6, cd)
		elif dimension == Dimension.HELL:
			var r := p.distance_to(c)
			shape = shape.lerp(BIOME_SHAPE[Biome.LAKE_OF_FIRE], smoothstep(250.0, 310.0, r))
		var i := col + row * n
		_base[i] = shape.x
		_amp[i] = shape.y
		_ridge[i] = shape.z
		_biome[i] = best_biome


# --- Column queries (thread-safe) ---------------------------------------------

func _coarse_sample(arr: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf(x / COARSE - 0.5, 0.0, _coarse_n - 1.001)
	var fz := clampf(z / COARSE - 0.5, 0.0, _coarse_n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := ix + iz * _coarse_n
	var a := lerpf(arr[i], arr[i + 1], tx)
	var b := lerpf(arr[i + _coarse_n], arr[i + _coarse_n + 1], tx)
	return lerpf(a, b, tz)


const FOREST_NAMES := ["Emberwood", "Northern Pinewoods", "Crimson Grove", "Oldgrowth Ironwood"]
const FOREST_COLORS := [Color(0.42, 0.36, 0.18), Color(0.22, 0.36, 0.31), Color(0.51, 0.25, 0.19), Color(0.25, 0.32, 0.16)]

## Forest subregions preserve the persisted base-biome IDs and ecology tables.
func forest_region(x: int, z: int) -> int:
	if revision < 2:
		return 0
	return _hash3(x >> 8, 0, z >> 8, world_seed + 771) % FOREST_NAMES.size()


func biome_at(x: int, z: int) -> int:
	var ix := clampi(x / COARSE, 0, _coarse_n - 1)
	var iz := clampi(z / COARSE, 0, _coarse_n - 1)
	return _biome[ix + iz * _coarse_n]


## Smooth (detail-free) ground height, used for roads and site planning.
func smooth_height(x: float, z: float) -> float:
	return _coarse_sample(_base, x, z)


## Natural terrain height before structures and roads.
func raw_height(x: int, z: int, detail: FastNoiseLite, ridge: FastNoiseLite) -> float:
	if dimension == Dimension.RYFT:
		return ryft_column(Vector2(x, z)).x + detail.get_noise_2d(x, z) * 1.5
	var h := _coarse_sample(_base, x, z)
	var amp := _coarse_sample(_amp, x, z)
	var rid := _coarse_sample(_ridge, x, z)
	h += detail.get_noise_2d(x, z) * amp
	if rid > 0.5:
		var r := 1.0 - absf(ridge.get_noise_2d(x, z))
		h += r * r * rid
	return h


## Final surface height (top solid block y) and whether the column is road.
func column(x: int, z: int, detail: FastNoiseLite, ridge: FastNoiseLite) -> Vector2:
	var c := column_f(x, z, detail, ridge)
	return Vector2(floorf(c.x + 0.5), c.y)


## Continuous terrain height (before rounding to a block) and road flag. The
## smooth ground surface lies at world height c.x + 1.0.
func column_f(x: int, z: int, detail: FastNoiseLite, ridge: FastNoiseLite) -> Vector2:
	var h := raw_height(x, z, detail, ridge)
	var road := 0.0
	var pad: Variant = _pads.get(x + z * size)
	if pad != null:
		var p: Vector3 = pad
		h = lerpf(h, p.x, p.y)
		road = p.z
	return Vector2(h, road)


func make_detail_noise() -> FastNoiseLite:
	return _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.012, 4, 21)


func make_ridge_noise() -> FastNoiseLite:
	var n := _noise(FastNoiseLite.TYPE_SIMPLEX, 0.0065, 4, 22)
	n.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	return n


## Convenience for the main thread (minimap, spawning).
var _main_detail: FastNoiseLite
var _main_ridge: FastNoiseLite


func surface_height(x: int, z: int) -> int:
	if _main_detail == null:
		_main_detail = make_detail_noise()
		_main_ridge = make_ridge_noise()
	return int(column(x, z, _main_detail, _main_ridge).x)


## Height of the smooth natural ground surface in world units (ignores caves and edits).
func ground_level(x: float, z: float) -> float:
	if _main_detail == null:
		_main_detail = make_detail_noise()
		_main_ridge = make_ridge_noise()
	var ix := floori(x)
	var iz := floori(z)
	var tx := x - ix
	var tz := z - iz
	var a := lerpf(column_f(ix, iz, _main_detail, _main_ridge).x, column_f(ix + 1, iz, _main_detail, _main_ridge).x, tx)
	var b := lerpf(column_f(ix, iz + 1, _main_detail, _main_ridge).x, column_f(ix + 1, iz + 1, _main_detail, _main_ridge).x, tx)
	return lerpf(a, b, tz) + 1.0


func in_bounds(x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < size and z < size


# --- Pads (flattened building sites) and roads ---------------------------------

func add_pad(center_xz: Vector2, radius: float, falloff: float, height: float) -> void:
	var r := int(radius + falloff)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x := int(center_xz.x) + dx
			var z := int(center_xz.y) + dz
			if not in_bounds(x, z):
				continue
			var d := Vector2(dx, dz).length()
			var w := 1.0 - smoothstep(radius, radius + falloff, d)
			if w <= 0.0:
				continue
			var key := x + z * size
			var old: Variant = _pads.get(key)
			if old == null or (old as Vector3).y < w:
				_pads[key] = Vector3(height, w, 0.0)


func add_road(points: PackedVector2Array, width: float) -> void:
	var detail := make_detail_noise()
	var ridge := make_ridge_noise()
	const BANK := 6.0  # metres over which the road blends back into the land
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var steps := int(a.distance_to(b))
		for s in steps + 1:
			var p := a.lerp(b, float(s) / maxf(1.0, steps))
			var in_village := false
			for loc: Location in locations:
				if loc.kind == Location.Kind.VILLAGE and p.distance_to(Vector2(loc.center.x, loc.center.z)) < loc.radius + width + BANK:
					in_village = true
					break
			if in_village:
				continue
			# The road follows the land, smoothed over ~10 m so it doesn't ripple.
			var natural := 0.0
			for o: Vector2 in [Vector2.ZERO, Vector2(5, 0), Vector2(-5, 0), Vector2(0, 5), Vector2(0, -5)]:
				natural += raw_height(int(p.x + o.x), int(p.y + o.y), detail, ridge)
			var road_h := maxf(natural / 5.0 + 0.15, SEA_LEVEL + 1.0)
			var r := int(width + BANK) + 1
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var x := int(p.x) + dx
					var z := int(p.y) + dz
					if not in_bounds(x, z):
						continue
					var d := Vector2(dx, dz).length()
					if d > width + BANK:
						continue
					var key := x + z * size
					var existing: Variant = _pads.get(key)
					if d <= width:
						if existing == null or (existing as Vector3).y < 0.999 or (existing as Vector3).z > 0.0:
							_pads[key] = Vector3(road_h, 1.0, 1.0)
					else:
						var w := 1.0 - smoothstep(width, width + BANK, d)
						if existing == null or ((existing as Vector3).z == 0.0 and (existing as Vector3).y < w):
							_pads[key] = Vector3(road_h, w, 0.0)


func _rasterise_pads() -> void:
	for loc in locations:
		if loc.pad_radius > 0.0:
			# Wide, gentle shoulders so building sites never leave cut walls in the smooth land.
			# (Islets out at sea keep their steep shores: the sea around them must stay deep.)
			var at_sea := biome_at(int(loc.center.x), int(loc.center.z)) == Biome.OCEAN
			var falloff := loc.pad_falloff if at_sea else maxf(loc.pad_falloff * 1.8, 10.0)
			add_pad(Vector2(loc.center.x, loc.center.z), loc.pad_radius, falloff, loc.ground_y + 0.0)
	for road: PackedVector2Array in LocationPlanner.roads(self):
		add_road(road, 2.0)


# --- Chunk generation (worker threads) ----------------------------------------

func generate_chunk(key: Vector3i) -> PackedByteArray:
	return generate(key)[0]


## Block ids and the matching density bytes for one chunk: [blocks, density].
## Density is the smooth terrain field sampled at voxel centres (>= 128 inside
## natural ground); an empty density array means "derive it from the blocks".
func generate(key: Vector3i) -> Array:
	if dimension == Dimension.HELL:
		return _generate_hell(key)
	if dimension == Dimension.RYFT:
		return _generate_ryft(key)
	return _generate_overworld(key)


static func _hash3(x: int, y: int, z: int, s: int) -> int:
	var h := (x * 374761393 + y * 668265263 + z * 2147483647 + s * 1274126177) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return h ^ (h >> 16)


static func _hash01(x: int, y: int, z: int, s: int) -> float:
	return float(_hash3(x, y, z, s) & 0xffff) / 65535.0


## Density byte for a field value d (0.5 = surface), consistent with solidity.
static func _dbyte(d: float, solid: bool) -> int:
	var q := clampi(int(d * 255.0), 0, 255)
	return maxi(q, 128) if solid else mini(q, 127)


func _generate_overworld(key: Vector3i) -> Array:
	var data := Chunk.empty()
	var dens := Chunk.empty()
	var o := key * Chunk.SIZE
	if o.y > Y_MAX or o.y + Chunk.SIZE <= Y_MIN:
		return [data, PackedByteArray()]
	var detail := make_detail_noise()
	var ridge := make_ridge_noise()

	var heights := PackedInt32Array()
	heights.resize(Chunk.AREA)
	var hf := PackedFloat32Array()
	hf.resize(Chunk.AREA)
	var roads := PackedByteArray()
	roads.resize(Chunk.AREA)
	var biomes := PackedByteArray()
	biomes.resize(Chunk.AREA)
	var max_h := -1000
	for z in Chunk.SIZE:
		for x in Chunk.SIZE:
			var wx := o.x + x
			var wz := o.z + z
			var col := column_f(wx, wz, detail, ridge) if in_bounds(wx, wz) else Vector2(-20, 0)
			var i := x + z * Chunk.SIZE
			hf[i] = col.x
			heights[i] = int(floorf(col.x + 0.5))
			roads[i] = int(col.y)
			biomes[i] = biome_at(wx, wz)
			max_h = maxi(max_h, heights[i])

	var touches_structure := false
	for bp in _blueprints:
		if bp.intersects_chunk(key):
			touches_structure = true
			break

	var top := maxi(max_h, SEA_LEVEL) + 16  # trees reach above the ground
	if o.y > top and not touches_structure:
		return [data, PackedByteArray()]

	var caves := o.y < max_h - 3
	var chamber := CaveBiomes.region(Vector3(o) + Vector3(8, 8, 8), world_seed)
	var advanced_caves := revision >= 2 and o.y < -8
	var t1 := PackedByteArray()
	var t2 := PackedByteArray()
	var cav := PackedByteArray()
	var strata := PackedByteArray()
	if caves:
		t1 = _noise_block(o, 0.024, 1, 31)
		t2 = _noise_block(o, 0.024, 1, 32)
		strata = _noise_block(o, 0.035, 2, 34)
		if o.y < -12:
			cav = _noise_block(o, 0.012, 2, 33)

	for y in Chunk.SIZE:
		var wy := o.y + y
		for z in Chunk.SIZE:
			for x in Chunk.SIZE:
				var ci := x + z * Chunk.SIZE
				var h := heights[ci]
				var d := 0.5 + (hf[ci] + 0.5 - float(wy)) * 0.5
				var ni := x + y * Chunk.SIZE + z * Chunk.AREA
				if caves and wy < h - 2 and wy > Y_MIN + 3:
					# Noise bytes map [-1, 1] to [0, 255]; 127.5 is zero.
					var depth_factor := clampf(float(h - wy) / 40.0, 0.0, 1.0)
					var tw := 9.0 + 6.0 * depth_factor
					var m := maxf(absf(t1[ni] - 127.5), absf(t2[ni] - 127.5)) - tw
					# Tunnels pinch shut just below the surface instead of ending in a flat roof.
					var dc := 0.5 + m / 24.0 + maxf(0.0, float(wy - h + 7)) * 0.12
					if wy < -12 and not cav.is_empty():
						dc = minf(dc, 0.5 + ((198.0 - depth_factor * 19.0) - float(cav[ni])) / 30.0)
					d = minf(d, dc)
				var chamber_distance := 100.0
				if advanced_caves and wy > Y_MIN + 4 and wy < h - 8:
					chamber_distance = CaveBiomes.distance_to_chamber(Vector3(o.x + x, wy, o.z + z), chamber)
					d = minf(d, 0.5 + (chamber_distance - 1.0) * 10.0)
				var solid := d >= 0.5
				var b := Blocks.AIR
				if solid:
					var st := 128 if strata.is_empty() else int(strata[ni])
					b = _ground_block(o.x + x, wy, o.z + z, h, biomes[ci], roads[ci], st)
					if chamber_distance < 1.13 and b != Blocks.BEDROCK:
						b = CaveBiomes.wall_material(o + Vector3i(x, y, z), int(chamber["kind"]), world_seed)
				elif wy <= h:
					b = Blocks.LAVA if wy < -112 else Blocks.AIR  # carved by a cave
				elif wy <= SEA_LEVEL:
					b = Blocks.WATER
					if biomes[ci] == Biome.PEAKS and wy == SEA_LEVEL:
						b = Blocks.ICE
				var di := x + z * Chunk.SIZE + y * Chunk.AREA
				if b != Blocks.AIR:
					data[di] = b
				dens[di] = _dbyte(d, solid or b == Blocks.ICE)

	var min_h := 100000
	for hh in heights:
		min_h = mini(min_h, hh)
	if o.y <= max_h + 16 and o.y + Chunk.SIZE > min_h - 1:
		_place_trees(data, dens, o, detail, ridge)
	_stamp_blueprints(data, dens, key)
	return [data, dens]


## Noise for one chunk via the native batch path: bytes indexed x + y*16 + z*256.
func _noise_block(o: Vector3i, freq: float, octaves: int, seed_offset: int) -> PackedByteArray:
	var n := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, freq, octaves, seed_offset)
	n.offset = Vector3(o)
	var images := n.get_image_3d(Chunk.SIZE, Chunk.SIZE, Chunk.SIZE, false, false)
	var out := PackedByteArray()
	for z in Chunk.SIZE:
		out.append_array((images[z] as Image).get_data())
	return out


func _ground_block(x: int, y: int, z: int, h: int, biome: int, road: int, strata := 128) -> int:
	if y <= Y_MIN + 1 + (_hash3(x, 0, z, 5) & 1):
		return Blocks.BEDROCK
	var depth := h - y
	if depth == 0:
		if road == 1:
			return Blocks.GRAVEL if _vnoise(x, z, 5.0, 7) > 0.22 else Blocks.DIRT
		if h <= SEA_LEVEL + 1 and h >= SEA_LEVEL - 2 and biome != Biome.MARSH:
			return Blocks.SAND
		match biome:
			Biome.PLAINS:
				return Blocks.DRY_GRASS if _vnoise(x, z, 9.0, 9) < 0.3 else Blocks.GRASS
			Biome.FOREST:
				return Blocks.GRASS
			Biome.PEAKS:
				if h > 64:
					return Blocks.SNOW
				if h > 52:
					return Blocks.GRANITE if _vnoise(x, z, 11.0, 8) < 0.3 else Blocks.STONE
				return Blocks.GRASS
			Biome.MARSH:
				return Blocks.MUD if h <= SEA_LEVEL else Blocks.GRASS
			Biome.WASTES:
				var r := _vnoise(x, z, 13.0, 3)
				return Blocks.SAND if r < 0.2 else (Blocks.BASALT if r > 0.8 else Blocks.ASH)
			_:
				return Blocks.SAND
	if depth < 4:
		match biome:
			Biome.WASTES:
				return Blocks.ASH if depth < 2 else Blocks.BASALT
			Biome.PEAKS:
				return Blocks.STONE if h > 52 else Blocks.DIRT
			Biome.OCEAN:
				return Blocks.SAND if depth < 3 else Blocks.SANDSTONE
			Biome.MARSH:
				return Blocks.MUD if depth < 2 else Blocks.CLAY
			_:
				if h <= SEA_LEVEL + 2 and depth < 3:
					return Blocks.SAND
				return Blocks.DIRT
	var ore := _ore(x, y, z)
	if ore != Blocks.AIR:
		return ore
	# Rock strata: wavy sedimentary bands plus pockets of other rock.
	var band := posmod(floori((float(y) + float(strata) * 0.09) / 7.0), 4)
	var pocket := strata > 178
	if y < -95:
		return Blocks.BASALT if band < 2 or pocket else Blocks.DEEPSLATE
	if y < -40:
		if pocket:
			return Blocks.AMETHYST if strata > 236 and y < -45 else Blocks.SLATE
		return Blocks.SLATE if band == 3 else Blocks.DEEPSLATE
	match biome:
		Biome.PEAKS:
			if pocket:
				return Blocks.MARBLE
			return Blocks.GRANITE if band == 0 else Blocks.STONE
		Biome.WASTES:
			if depth < 14:
				return Blocks.SANDSTONE if band < 2 else Blocks.BASALT
			return Blocks.BASALT if pocket else Blocks.STONE
		Biome.MARSH:
			if depth < 9:
				return Blocks.CLAY if band != 1 else Blocks.MUD
			return Blocks.SLATE if pocket else Blocks.STONE
		Biome.OCEAN:
			return Blocks.SANDSTONE if depth < 10 else (Blocks.LIMESTONE if pocket else Blocks.STONE)
	if pocket:
		return Blocks.GRANITE if band < 2 else Blocks.LIMESTONE
	return Blocks.LIMESTONE if band == 2 else Blocks.STONE


## Smooth value noise 0..1 from the integer hash (organic patches, thread-safe).
static func _vnoise(x: int, z: int, scale: float, s: int) -> float:
	var fx := x / scale
	var fz := z / scale
	var ix := floori(fx)
	var iz := floori(fz)
	var tx := fx - ix
	var tz := fz - iz
	tx = tx * tx * (3.0 - 2.0 * tx)
	tz = tz * tz * (3.0 - 2.0 * tz)
	var a := lerpf(_hash01(ix, 0, iz, s), _hash01(ix + 1, 0, iz, s), tx)
	var b := lerpf(_hash01(ix, 0, iz + 1, s), _hash01(ix + 1, 0, iz + 1, s), tx)
	return lerpf(a, b, tz)


## Ore veins: 2 m clusters, richer and rarer metals deeper down.
func _ore(x: int, y: int, z: int) -> int:
	var r := _hash01(x >> 1, y >> 1, z >> 1, 77)
	if r >= 0.05:
		return Blocks.AIR
	if _hash01(x, y, z, 78) >= 0.72:
		return Blocks.AIR
	var t := _hash01(x >> 1, y >> 1, z >> 1, 79)
	if y < -100 and t < 0.35:
		return Blocks.OBSIDIAN
	if y < -95 and t < 0.6:
		return Blocks.ADAMANTITE_ORE
	if y < -60 and t < 0.3:
		return Blocks.MITHRIL_ORE if t < 0.16 else Blocks.EMBER_ORE
	if y < -40 and t < 0.38:
		return Blocks.RUBY_ORE if t < 0.19 else Blocks.SAPPHIRE_ORE
	if y < -25 and t < 0.5:
		return Blocks.GOLD_ORE
	if y < -10 and t < 0.62:
		return Blocks.SILVER_ORE
	if y < 20 and t < 0.75:
		return Blocks.IRON_ORE
	if y < 40 and t < 0.86:
		return Blocks.COPPER_ORE if t < 0.81 else Blocks.TIN_ORE
	if y < 60:
		return Blocks.COAL_ORE
	return Blocks.AIR


# --- Trees -------------------------------------------------------------------
# Trees are a trunk column of a TREE-family block (collision, chopping); Flora
# draws the actual tree. The visual height and variant come from tree_info().

const TREE_GRID := 5


## [kind (Flora.Tree), visual height m, seed] for a trunk rooted at root.
static func tree_info(trunk_block: int, root: Vector3i) -> Array:
	var hsh := _hash3(root.x, root.y, root.z, 211)
	var kind := 0
	var height := 0.0
	match trunk_block:
		Blocks.PINE_TRUNK:
			kind = 2
			height = 9.0 + float(hsh & 7) * 0.7
		Blocks.DEAD_TRUNK:
			kind = 3
			height = 5.0 + float(hsh & 7) * 0.45
		Blocks.CRIMSON_TRUNK, Blocks.EMBERWOOD_TRUNK, Blocks.RYFTWOOD_TRUNK:
			kind = 1
			height = 7.0 + float(hsh & 7) * 0.5
		_:
			kind = 0
			height = 7.5 + float(hsh & 7) * 0.6
	return [kind, height, hsh]


func _place_trees(data: PackedByteArray, dens: PackedByteArray, o: Vector3i, detail: FastNoiseLite, ridge: FastNoiseLite) -> void:
	var gx0 := floori(float(o.x) / TREE_GRID)
	var gx1 := floori(float(o.x + Chunk.SIZE - 1) / TREE_GRID)
	var gz0 := floori(float(o.z) / TREE_GRID)
	var gz1 := floori(float(o.z + Chunk.SIZE - 1) / TREE_GRID)
	for gz in range(gz0, gz1 + 1):
		for gx in range(gx0, gx1 + 1):
			var hsh := _hash3(gx, 0, gz, 101)
			var rx := gx * TREE_GRID + (hsh & 3)
			var rz := gz * TREE_GRID + ((hsh >> 2) & 3)
			if rx < o.x or rz < o.z or rx >= o.x + Chunk.SIZE or rz >= o.z + Chunk.SIZE or not in_bounds(rx, rz):
				continue
			var biome := biome_at(rx, rz)
			var chance := 0.0
			match biome:
				Biome.FOREST: chance = [0.62, 0.52, 0.42, 0.72][forest_region(rx, rz)]
				Biome.PLAINS: chance = 0.05
				Biome.PEAKS: chance = 0.32
				Biome.MARSH: chance = 0.16
				Biome.WASTES: chance = 0.015
				Biome.RYFT: chance = 0.18
			if float((hsh >> 4) & 0xff) / 255.0 >= chance:
				continue
			if _pads.has(rx + rz * size):
				continue
			var ground := int(column(rx, rz, detail, ridge).x)
			if ground + 6 < o.y or ground + 1 >= o.y + Chunk.SIZE:
				continue
			if ground <= SEA_LEVEL and biome != Biome.MARSH:
				continue
			if biome == Biome.PEAKS and ground > 70:
				continue
			var trunk := Blocks.OAK_TRUNK
			var trunk_h := 4
			match biome:
				Biome.FOREST:
					var region := forest_region(rx, rz)
					trunk = [Blocks.OAK_TRUNK, Blocks.PINE_TRUNK, Blocks.CRIMSON_TRUNK, Blocks.OAK_TRUNK][region]
					trunk_h = [4, 6, 4, 6][region]
				Biome.PEAKS:
					trunk = Blocks.PINE_TRUNK
					trunk_h = 5
				Biome.MARSH:
					trunk = Blocks.CRIMSON_TRUNK if (hsh >> 14) & 1 == 0 else Blocks.DEAD_TRUNK
				Biome.WASTES:
					trunk = Blocks.DEAD_TRUNK
					trunk_h = 3
				Biome.PLAINS:
					trunk = Blocks.OAK_TRUNK if (hsh >> 15) & 1 == 0 else Blocks.CRIMSON_TRUNK
			if revision >= 2:
				if biome == Biome.RYFT:
					trunk = Blocks.RYFTWOOD_TRUNK
				elif biome == Biome.FOREST and hsh % (7 if forest_region(rx, rz) == 3 else 19) == 0:
					trunk = Blocks.IRONWOOD_TRUNK
				elif biome == Biome.WASTES and hsh % 3 == 0:
					trunk = Blocks.EMBERWOOD_TRUNK
			var root := Vector3i(rx, ground + 1, rz)
			# Only the root's own column matters: the whole trunk sits in this chunk column.
			var lx := rx - o.x
			var lz := rz - o.z
			for i in trunk_h:
				var ly := root.y + i - o.y
				if ly < 0 or ly >= Chunk.SIZE:
					continue
				var di := lx + lz * Chunk.SIZE + ly * Chunk.AREA
				if data[di] == Blocks.AIR or data[di] == Blocks.WATER:
					data[di] = trunk
					dens[di] = mini(dens[di], 127)


static func _set_if(data: PackedByteArray, o: Vector3i, p: Vector3i, block: int, overwrite: bool) -> void:
	var lx := p.x - o.x
	var ly := p.y - o.y
	var lz := p.z - o.z
	if lx < 0 or ly < 0 or lz < 0 or lx >= Chunk.SIZE or ly >= Chunk.SIZE or lz >= Chunk.SIZE:
		return
	var i := lx + lz * Chunk.SIZE + ly * Chunk.AREA
	if overwrite or data[i] == Blocks.AIR or data[i] == Blocks.WATER:
		data[i] = block


## x/z, surface height, radius. Narrow arched causeways connect the islands.
const RYFT_ISLANDS := [Vector4(320, 320, 80, 62), Vector4(442, 302, 106, 42), Vector4(266, 186, 128, 46), Vector4(176, 356, 96, 40)]

static func ryft_column(p: Vector2) -> Vector2:
	var result := Vector2(-120, -121)
	for island: Vector4 in RYFT_ISLANDS:
		var r := p.distance_to(Vector2(island.x, island.y)) / island.w
		if r < 1.0:
			var top := island.z - pow(r, 5.0) * 9.0
			if top > result.x:
				result = Vector2(top, island.z - 12.0 - sqrt(1.0 - r) * 46.0)
	for i in range(1, RYFT_ISLANDS.size()):
		var a := Vector2(320, 320)
		var b := Vector2(RYFT_ISLANDS[i].x, RYFT_ISLANDS[i].y)
		var t := clampf((p - a).dot(b - a) / a.distance_squared_to(b), 0.0, 1.0)
		if p.distance_to(a.lerp(b, t)) < 3.2:
			var h := lerpf(80, RYFT_ISLANDS[i].z, t) + sin(t * PI) * 6.0
			if h > result.x:
				result = Vector2(h, h - 4.5)
	return result

func _generate_ryft(key: Vector3i) -> Array:
	var data := Chunk.empty()
	var dens := Chunk.empty()
	var o := key * Chunk.SIZE
	if o.y < 0 or o.y > 160:
		return [data, dens]
	var detail := make_detail_noise()
	var ridge := make_ridge_noise()
	for z in 16:
		for x in 16:
			var span := ryft_column(Vector2(o.x + x, o.z + z))
			if span.x < 0:
				continue
			var h := column_f(o.x + x, o.z + z, detail, ridge).x
			for y in 16:
				var wy := o.y + y
				var d := 0.5 + minf(h + 0.5 - wy, wy - span.y) * 0.5
				var index := Chunk.index(x, y, z)
				dens[index] = _dbyte(d, d >= 0.5)
				if d >= 0.5:
					data[index] = Blocks.GRASS if wy > h - 2 else (Blocks.AMETHYST if _hash3(o.x + x, wy, o.z + z, world_seed) % 31 == 0 else Blocks.SLATE)
	_place_trees(data, dens, o, detail, ridge)
	_stamp_blueprints(data, dens, key)
	return [data, dens]

func _stamp_blueprints(data: PackedByteArray, dens: PackedByteArray, key: Vector3i) -> void:
	var o := key * Chunk.SIZE
	var smooth := Blocks.family_table()
	for bp in _blueprints:
		if not bp.intersects_chunk(key):
			continue
		var x0 := maxi(o.x, bp.origin.x)
		var x1 := mini(o.x + Chunk.SIZE, bp.origin.x + bp.size.x)
		var y0 := maxi(o.y, bp.origin.y)
		var y1 := mini(o.y + Chunk.SIZE, bp.origin.y + bp.size.y)
		var z0 := maxi(o.z, bp.origin.z)
		var z1 := mini(o.z + Chunk.SIZE, bp.origin.z + bp.size.z)
		var sx := bp.size.x
		var sxz := bp.size.x * bp.size.z
		for y in range(y0, y1):
			for z in range(z0, z1):
				var row := (z - bp.origin.z) * sx + (y - bp.origin.y) * sxz - bp.origin.x
				var drow := (z - o.z) * Chunk.SIZE + (y - o.y) * Chunk.AREA - o.x
				for x in range(x0, x1):
					var v := bp.data[row + x]
					if v == Blueprint.KEEP:
						continue
					var di := drow + x
					if v == Blueprint.CARVE:
						data[di] = Blocks.AIR
						dens[di] = 0
					else:
						data[di] = v
						# Built blocks keep the ground's density: below ground they read as
						# ground for the smooth surface, above it as air.
						if smooth[v] == Blocks.Family.SMOOTH:
							dens[di] = 230


# --- Hell --------------------------------------------------------------------

func _generate_hell(key: Vector3i) -> Array:
	var data := Chunk.empty()
	var dens := Chunk.empty()
	var o := key * Chunk.SIZE
	if o.y > 63 or o.y + Chunk.SIZE <= -64:
		return [data, PackedByteArray()]
	var detail := make_detail_noise()
	var ridge := make_ridge_noise()
	var max_h := -1000
	var heights := PackedInt32Array()
	heights.resize(Chunk.AREA)
	var hf := PackedFloat32Array()
	hf.resize(Chunk.AREA)
	var biomes := PackedByteArray()
	biomes.resize(Chunk.AREA)
	for z in Chunk.SIZE:
		for x in Chunk.SIZE:
			var wx := o.x + x
			var wz := o.z + z
			var col := column_f(wx, wz, detail, ridge) if in_bounds(wx, wz) else Vector2(-30, 0)
			var i := x + z * Chunk.SIZE
			hf[i] = col.x
			heights[i] = int(floorf(col.x + 0.5))
			biomes[i] = biome_at(wx, wz)
			max_h = maxi(max_h, heights[i])
	var touches := false
	for bp in _blueprints:
		if bp.intersects_chunk(key):
			touches = true
			break
	if o.y > maxi(max_h, LAVA_LEVEL) + 14 and not touches:
		return [data, PackedByteArray()]
	for y in Chunk.SIZE:
		var wy := o.y + y
		for z in Chunk.SIZE:
			for x in Chunk.SIZE:
				var ci := x + z * Chunk.SIZE
				var h := heights[ci]
				var d := 0.5 + (hf[ci] + 0.5 - float(wy)) * 0.5
				var b := Blocks.AIR
				if wy <= -62:
					b = Blocks.BEDROCK
					d = 1.0
				elif wy <= h:
					var depth := h - wy
					if depth == 0:
						match biomes[ci]:
							Biome.ASPHODEL: b = Blocks.ASH if _hash3(x + o.x, 0, z + o.z, 4) & 3 else Blocks.SOUL_SAND
							Biome.TARTARUS: b = Blocks.BASALT
							_: b = Blocks.BASALT if h > LAVA_LEVEL else Blocks.OBSIDIAN
					elif depth < 4:
						b = Blocks.ASH if biomes[ci] == Biome.ASPHODEL else Blocks.BASALT
					else:
						var r := _hash01((o.x + x) >> 1, wy >> 1, (o.z + z) >> 1, 91)
						b = Blocks.HELLSTONE if r < 0.012 else (Blocks.OBSIDIAN if r < 0.02 else Blocks.BASALT)
				elif wy <= LAVA_LEVEL:
					b = Blocks.LAVA
				var di := x + z * Chunk.SIZE + y * Chunk.AREA
				if b != Blocks.AIR:
					data[di] = b
				dens[di] = _dbyte(d, b != Blocks.AIR and b != Blocks.LAVA)
	# Bone spires.
	_place_hell_features(data, dens, o, detail, ridge)
	_stamp_blueprints(data, dens, key)
	return [data, dens]


func _place_hell_features(data: PackedByteArray, dens: PackedByteArray, o: Vector3i, detail: FastNoiseLite, ridge: FastNoiseLite) -> void:
	const GRID := 9
	for gz in range(floori(float(o.z - 3) / GRID), floori(float(o.z + 19) / GRID) + 1):
		for gx in range(floori(float(o.x - 3) / GRID), floori(float(o.x + 19) / GRID) + 1):
			var hsh := _hash3(gx, 1, gz, 303)
			if (hsh & 7) > 1:
				continue
			var rx := gx * GRID + ((hsh >> 3) & 7)
			var rz := gz * GRID + ((hsh >> 6) & 7)
			if not in_bounds(rx, rz) or _pads.has(rx + rz * size):
				continue
			var ground := int(column(rx, rz, detail, ridge).x)
			if ground <= LAVA_LEVEL:
				continue
			var h := 4 + ((hsh >> 9) & 7)
			# A tapering spire: a 3x3 base that narrows to a single column.
			for i in h:
				var r := 1 if i < h / 3 else 0
				for dz in range(-r, r + 1):
					for dx in range(-r, r + 1):
						if r == 1 and absi(dx) + absi(dz) == 2:
							continue
						_set_dens(data, dens, o, Vector3i(rx + dx, ground + 1 + i, rz + dz), Blocks.BONE, 200 - i * 6)
			if (hsh >> 12) & 1:
				_set_dens(data, dens, o, Vector3i(rx + 1, ground + h - 1, rz), Blocks.BONE, 170)
				_set_dens(data, dens, o, Vector3i(rx - 1, ground + h - 2, rz), Blocks.BONE, 170)
				_set_dens(data, dens, o, Vector3i(rx, ground + h, rz), Blocks.HELLSTONE, 200)


static func _set_dens(data: PackedByteArray, dens: PackedByteArray, o: Vector3i, p: Vector3i, block: int, density: int) -> void:
	var lx := p.x - o.x
	var ly := p.y - o.y
	var lz := p.z - o.z
	if lx < 0 or ly < 0 or lz < 0 or lx >= Chunk.SIZE or ly >= Chunk.SIZE or lz >= Chunk.SIZE:
		return
	var i := lx + lz * Chunk.SIZE + ly * Chunk.AREA
	if data[i] == Blocks.AIR or data[i] == Blocks.LAVA:
		data[i] = block
		dens[i] = clampi(density, 128, 255)
