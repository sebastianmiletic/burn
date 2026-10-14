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

enum Dimension { OVERWORLD, HELL }
enum Biome { OCEAN, PLAINS, FOREST, PEAKS, MARSH, WASTES, ASPHODEL, LAKE_OF_FIRE, TARTARUS }

const BIOME_NAMES := ["The Grey Sea", "The Ashen Plains", "Emberwood", "Frost Peaks", "Blackmarsh",
		"Cinder Wastes", "Asphodel Fields", "Lake of Fire", "Tartarus"]

const SEA_LEVEL := 12
const LAVA_LEVEL := 0  ## hell
const COARSE := 4      ## metres per coarse map cell
const Y_MIN := -128
const Y_MAX := 127

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
}

var dimension := Dimension.OVERWORLD
var world_seed := 1
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


func _init(dim: Dimension, seed_value: int) -> void:
	dimension = dim
	world_seed = seed_value
	size = 2048 if dim == Dimension.OVERWORLD else 640
	_coarse_n = size / COARSE


func center() -> Vector2:
	return Vector2(size * 0.5, size * 0.5)


# --- Preparation --------------------------------------------------------------

func prepare(progress: Callable = Callable()) -> void:
	_setup_biome_seeds()
	_report(progress, 0.05, "Shaping the land")
	_build_coarse_maps()
	_report(progress, 0.45, "Raising the ruins")
	var planner := LocationPlanner.new(self)
	locations = planner.plan()
	for loc in locations:
		_blueprints.append_array(loc.blueprints)
	_report(progress, 0.75, "Laying the old roads")
	_rasterise_pads()
	_report(progress, 1.0, "Done")


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
			shape += BIOME_SHAPE[s[1]] * w
			if d < best:
				best = d
				best_biome = s[1]
		shape /= total
		shape.x += macro.get_noise_2dv(p) * 4.0
		if dimension == Dimension.OVERWORLD:
			# An island: the sea closes in past ~900 m from the centre.
			var r := p.distance_to(c)
			var t := smoothstep(860.0, 990.0, r + warp.get_noise_2dv(p * 2.0) * 60.0)
			shape = shape.lerp(BIOME_SHAPE[Biome.OCEAN], t)
			if t > 0.5:
				best_biome = Biome.OCEAN
			# The Cinder Crater above the Gates of Hades.
			var cd := p.distance_to(Vector2(_crater.x, _crater.y))
			shape.x -= 22.0 * (1.0 - smoothstep(0.0, _crater.z, cd))
			shape.x += 7.0 * exp(-pow((cd - _crater.z) / 14.0, 2.0))
			shape.z *= smoothstep(_crater.z * 0.6, _crater.z * 1.6, cd)
		else:
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


func biome_at(x: int, z: int) -> int:
	var ix := clampi(x / COARSE, 0, _coarse_n - 1)
	var iz := clampi(z / COARSE, 0, _coarse_n - 1)
	return _biome[ix + iz * _coarse_n]


## Smooth (detail-free) ground height, used for roads and site planning.
func smooth_height(x: float, z: float) -> float:
	return _coarse_sample(_base, x, z)


## Natural terrain height before structures and roads.
func raw_height(x: int, z: int, detail: FastNoiseLite, ridge: FastNoiseLite) -> float:
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
	var h := raw_height(x, z, detail, ridge)
	var road := 0.0
	var pad: Variant = _pads.get(x + z * size)
	if pad != null:
		var p: Vector3 = pad
		h = lerpf(h, p.x, p.y)
		road = p.z
	return Vector2(floorf(h), road)


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
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var steps := int(a.distance_to(b))
		for s in steps + 1:
			var p := a.lerp(b, float(s) / maxf(1.0, steps))
			var road_h := maxf(smooth_height(p.x, p.y) + 0.5, SEA_LEVEL + 1.0)
			for dz in range(-int(width) - 2, int(width) + 3):
				for dx in range(-int(width) - 2, int(width) + 3):
					var x := int(p.x) + dx
					var z := int(p.y) + dz
					if not in_bounds(x, z):
						continue
					var d := Vector2(dx, dz).length()
					var key := x + z * size
					var existing: Variant = _pads.get(key)
					if d <= width:
						if existing == null or (existing as Vector3).y < 0.999 or (existing as Vector3).z > 0.0:
							_pads[key] = Vector3(road_h, 1.0, 1.0)
					elif d <= width + 2.5 and existing == null:
						var natural := raw_height(x, z, detail, ridge)
						var w := 1.0 - (d - width) / 2.5
						_pads[key] = Vector3(lerpf(natural, road_h, w), 1.0, 0.0)


func _rasterise_pads() -> void:
	for loc in locations:
		if loc.pad_radius > 0.0:
			add_pad(Vector2(loc.center.x, loc.center.z), loc.pad_radius, loc.pad_falloff, loc.ground_y + 0.0)
	for road: PackedVector2Array in LocationPlanner.roads(self):
		add_road(road, 2.0)


# --- Chunk generation (worker threads) ----------------------------------------

func generate_chunk(key: Vector3i) -> PackedByteArray:
	if dimension == Dimension.HELL:
		return _generate_hell(key)
	return _generate_overworld(key)


static func _hash3(x: int, y: int, z: int, s: int) -> int:
	var h := (x * 374761393 + y * 668265263 + z * 2147483647 + s * 1274126177) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return h ^ (h >> 16)


static func _hash01(x: int, y: int, z: int, s: int) -> float:
	return float(_hash3(x, y, z, s) & 0xffff) / 65535.0


func _generate_overworld(key: Vector3i) -> PackedByteArray:
	var data := Chunk.empty()
	var o := key * Chunk.SIZE
	if o.y > Y_MAX or o.y + Chunk.SIZE <= Y_MIN:
		return data
	var detail := make_detail_noise()
	var ridge := make_ridge_noise()

	var heights := PackedInt32Array()
	heights.resize(Chunk.AREA)
	var roads := PackedByteArray()
	roads.resize(Chunk.AREA)
	var biomes := PackedByteArray()
	biomes.resize(Chunk.AREA)
	var max_h := -1000
	for z in Chunk.SIZE:
		for x in Chunk.SIZE:
			var wx := o.x + x
			var wz := o.z + z
			var col := column(wx, wz, detail, ridge) if in_bounds(wx, wz) else Vector2(-20, 0)
			var i := x + z * Chunk.SIZE
			heights[i] = int(col.x)
			roads[i] = int(col.y)
			biomes[i] = biome_at(wx, wz)
			max_h = maxi(max_h, int(col.x))

	var touches_structure := false
	for bp in _blueprints:
		if bp.intersects_chunk(key):
			touches_structure = true
			break

	var top := maxi(max_h, SEA_LEVEL) + 14  # trees reach above the ground
	if o.y > top and not touches_structure:
		return data

	var caves := o.y < max_h - 3
	var t1 := PackedByteArray()
	var t2 := PackedByteArray()
	var cav := PackedByteArray()
	if caves:
		t1 = _noise_block(o, 0.024, 1, 31)
		t2 = _noise_block(o, 0.024, 1, 32)
		if o.y < -12:
			cav = _noise_block(o, 0.012, 2, 33)

	for y in Chunk.SIZE:
		var wy := o.y + y
		for z in Chunk.SIZE:
			for x in Chunk.SIZE:
				var ci := x + z * Chunk.SIZE
				var h := heights[ci]
				var b := Blocks.AIR
				if wy <= h:
					b = _ground_block(o.x + x, wy, o.z + z, h, biomes[ci], roads[ci])
					if caves and wy < h - 3 and wy > Y_MIN + 3:
						# Noise bytes map [-1, 1] to [0, 255]; 127.5 is zero.
						var ni := x + y * Chunk.SIZE + z * Chunk.AREA
						var depth_factor := clampf(float(h - wy) / 40.0, 0.0, 1.0)
						var tw := 9.0 + 6.0 * depth_factor
						var carve := absf(t1[ni] - 127.5) < tw and absf(t2[ni] - 127.5) < tw
						if not carve and wy < -12 and not cav.is_empty():
							carve = cav[ni] > 198.0 - depth_factor * 19.0
						if carve:
							b = Blocks.LAVA if wy < -112 else Blocks.AIR
				elif wy <= SEA_LEVEL:
					b = Blocks.WATER
					if biomes[ci] == Biome.PEAKS and wy == SEA_LEVEL:
						b = Blocks.ICE
				if b != Blocks.AIR:
					data[x + z * Chunk.SIZE + y * Chunk.AREA] = b

	var min_h := 100000
	for hh in heights:
		min_h = mini(min_h, hh)
	if o.y <= max_h + 14 and o.y + Chunk.SIZE > min_h - 1:
		_place_trees(data, o, detail, ridge)
	_stamp_blueprints(data, key)
	return data


## Noise for one chunk via the native batch path: bytes indexed x + y*16 + z*256.
func _noise_block(o: Vector3i, freq: float, octaves: int, seed_offset: int) -> PackedByteArray:
	var n := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, freq, octaves, seed_offset)
	n.offset = Vector3(o)
	var images := n.get_image_3d(Chunk.SIZE, Chunk.SIZE, Chunk.SIZE, false, false)
	var out := PackedByteArray()
	for z in Chunk.SIZE:
		out.append_array((images[z] as Image).get_data())
	return out


func _ground_block(x: int, y: int, z: int, h: int, biome: int, road: int) -> int:
	if y <= Y_MIN + 1 + (_hash3(x, 0, z, 5) & 1):
		return Blocks.BEDROCK
	var depth := h - y
	if depth == 0:
		if road == 1:
			return Blocks.GRAVEL if _hash3(x, y, z, 7) & 3 != 0 else Blocks.DIRT
		if h <= SEA_LEVEL + 1 and h >= SEA_LEVEL - 2 and biome != Biome.MARSH:
			return Blocks.SAND
		match biome:
			Biome.PLAINS:
				return Blocks.DRY_GRASS if (_hash3(x >> 2, 0, z >> 2, 9) & 3) == 0 else Blocks.GRASS
			Biome.FOREST:
				return Blocks.GRASS
			Biome.PEAKS:
				if h > 64:
					return Blocks.SNOW
				return Blocks.STONE if h > 52 else Blocks.GRASS
			Biome.MARSH:
				return Blocks.MUD if h <= SEA_LEVEL else Blocks.GRASS
			Biome.WASTES:
				var r := _hash3(x >> 3, 0, z >> 3, 3) & 7
				return Blocks.SAND if r == 0 else (Blocks.BASALT if r == 1 else Blocks.ASH)
			_:
				return Blocks.SAND
	if depth < 4:
		match biome:
			Biome.WASTES:
				return Blocks.ASH if depth < 2 else Blocks.BASALT
			Biome.PEAKS:
				return Blocks.STONE if h > 52 else Blocks.DIRT
			Biome.OCEAN:
				return Blocks.SAND if depth < 3 else Blocks.GRAVEL
			Biome.MARSH:
				return Blocks.MUD
			_:
				return Blocks.DIRT
	# Ores, deeper is richer.
	var r := _hash01(x >> 1, y >> 1, z >> 1, 77)
	var s := _hash01(x, y, z, 78)
	if r < 0.035 and s < 0.7:
		if y < -100 and r < 0.02:
			return Blocks.OBSIDIAN
		if y < -60 and r < 0.008:
			return Blocks.EMBER_ORE
		if y < -25 and r < 0.014:
			return Blocks.GOLD_ORE
		if y < 18 and r < 0.024:
			return Blocks.IRON_ORE
		if y < 50:
			return Blocks.COAL_ORE
	if y < -40:
		return Blocks.DEEPSLATE
	if biome == Biome.WASTES and depth < 12:
		return Blocks.BASALT
	return Blocks.STONE


func _place_trees(data: PackedByteArray, o: Vector3i, detail: FastNoiseLite, ridge: FastNoiseLite) -> void:
	# Trees are rooted on a 5 m jittered grid; check roots within reach of this chunk.
	const GRID := 5
	const REACH := 4
	var gx0 := floori(float(o.x - REACH) / GRID)
	var gx1 := floori(float(o.x + Chunk.SIZE + REACH) / GRID)
	var gz0 := floori(float(o.z - REACH) / GRID)
	var gz1 := floori(float(o.z + Chunk.SIZE + REACH) / GRID)
	for gz in range(gz0, gz1 + 1):
		for gx in range(gx0, gx1 + 1):
			var hsh := _hash3(gx, 0, gz, 101)
			var rx := gx * GRID + (hsh & 3)
			var rz := gz * GRID + ((hsh >> 2) & 3)
			if not in_bounds(rx, rz):
				continue
			var biome := biome_at(rx, rz)
			var chance := 0.0
			match biome:
				Biome.FOREST: chance = 0.62
				Biome.PLAINS: chance = 0.05
				Biome.PEAKS: chance = 0.32
				Biome.MARSH: chance = 0.16
				Biome.WASTES: chance = 0.015
			if float((hsh >> 4) & 0xff) / 255.0 >= chance:
				continue
			var key := rx + rz * size
			if _pads.has(key):
				continue
			var col := column(rx, rz, detail, ridge)
			var ground := int(col.x)
			if ground + 14 < o.y or ground + 1 > o.y + Chunk.SIZE + 3:
				continue
			if ground <= SEA_LEVEL and biome != Biome.MARSH:
				continue
			if biome == Biome.PEAKS and ground > 70:
				continue
			_tree(data, o, Vector3i(rx, ground + 1, rz), biome, hsh)


func _tree(data: PackedByteArray, o: Vector3i, root: Vector3i, biome: int, hsh: int) -> void:
	var trunk_h := 5 + ((hsh >> 12) & 3)
	var log_block := Blocks.LOG
	var leaf := Blocks.LEAVES
	match biome:
		Biome.PEAKS:
			log_block = Blocks.PINE_LOG
			leaf = Blocks.PINE_LEAVES
			trunk_h += 3
		Biome.MARSH:
			leaf = Blocks.CRIMSON_LEAVES if (hsh >> 14) & 1 == 0 else Blocks.AIR
		Biome.WASTES:
			leaf = Blocks.AIR
		Biome.PLAINS:
			leaf = Blocks.LEAVES if (hsh >> 15) & 1 == 0 else Blocks.CRIMSON_LEAVES
	for i in trunk_h:
		_set_if(data, o, root + Vector3i(0, i, 0), log_block, true)
	if leaf == Blocks.AIR:
		# Dead tree: a couple of bare branches.
		_set_if(data, o, root + Vector3i(1, trunk_h - 2, 0), log_block, true)
		_set_if(data, o, root + Vector3i(-1, trunk_h - 1, 0), log_block, true)
		return
	var top := root + Vector3i(0, trunk_h, 0)
	if biome == Biome.PEAKS:
		for layer in 7:
			var r := 3 - layer / 2
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if absi(dx) + absi(dz) <= r + 1 and not (dx == 0 and dz == 0 and layer < 5):
						_set_if(data, o, top + Vector3i(dx, layer - 4, dz), leaf, false)
		_set_if(data, o, top + Vector3i(0, 3, 0), leaf, false)
		return
	# Broad autumn crown: a squashed, slightly ragged sphere.
	var r := 3.2 + float((hsh >> 18) & 3) * 0.4
	for dy in range(-3, 4):
		for dz in range(-4, 5):
			for dx in range(-4, 5):
				var d := Vector3(dx, dy * 1.35, dz).length()
				if d <= r and _hash01(root.x + dx, root.y + dy, root.z + dz, 55) > 0.12 * d / r:
					_set_if(data, o, top + Vector3i(dx, dy, dz), leaf, false)


static func _set_if(data: PackedByteArray, o: Vector3i, p: Vector3i, block: int, overwrite: bool) -> void:
	var lx := p.x - o.x
	var ly := p.y - o.y
	var lz := p.z - o.z
	if lx < 0 or ly < 0 or lz < 0 or lx >= Chunk.SIZE or ly >= Chunk.SIZE or lz >= Chunk.SIZE:
		return
	var i := lx + lz * Chunk.SIZE + ly * Chunk.AREA
	if overwrite or data[i] == Blocks.AIR or data[i] == Blocks.WATER:
		data[i] = block


func _stamp_blueprints(data: PackedByteArray, key: Vector3i) -> void:
	var o := key * Chunk.SIZE
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
					data[drow + x] = Blocks.AIR if v == Blueprint.CARVE else v


# --- Hell --------------------------------------------------------------------

func _generate_hell(key: Vector3i) -> PackedByteArray:
	var data := Chunk.empty()
	var o := key * Chunk.SIZE
	if o.y > 63 or o.y + Chunk.SIZE <= -64:
		return data
	var detail := make_detail_noise()
	var ridge := make_ridge_noise()
	var max_h := -1000
	var heights := PackedInt32Array()
	heights.resize(Chunk.AREA)
	var biomes := PackedByteArray()
	biomes.resize(Chunk.AREA)
	for z in Chunk.SIZE:
		for x in Chunk.SIZE:
			var wx := o.x + x
			var wz := o.z + z
			var col := column(wx, wz, detail, ridge) if in_bounds(wx, wz) else Vector2(-30, 0)
			heights[x + z * Chunk.SIZE] = int(col.x)
			biomes[x + z * Chunk.SIZE] = biome_at(wx, wz)
			max_h = maxi(max_h, int(col.x))
	var touches := false
	for bp in _blueprints:
		if bp.intersects_chunk(key):
			touches = true
			break
	if o.y > maxi(max_h, LAVA_LEVEL) + 10 and not touches:
		return data
	for y in Chunk.SIZE:
		var wy := o.y + y
		for z in Chunk.SIZE:
			for x in Chunk.SIZE:
				var ci := x + z * Chunk.SIZE
				var h := heights[ci]
				var b := Blocks.AIR
				if wy <= -62:
					b = Blocks.BEDROCK
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
				if b != Blocks.AIR:
					data[x + z * Chunk.SIZE + y * Chunk.AREA] = b
	# Bone spires and soul-lantern trees.
	_place_hell_features(data, o, detail, ridge)
	_stamp_blueprints(data, key)
	return data


func _place_hell_features(data: PackedByteArray, o: Vector3i, detail: FastNoiseLite, ridge: FastNoiseLite) -> void:
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
			for i in h:
				_set_if(data, o, Vector3i(rx, ground + 1 + i, rz), Blocks.BONE, true)
			if (hsh >> 12) & 1:
				_set_if(data, o, Vector3i(rx + 1, ground + h - 1, rz), Blocks.BONE, false)
				_set_if(data, o, Vector3i(rx - 1, ground + h - 2, rz), Blocks.BONE, false)
				_set_if(data, o, Vector3i(rx, ground + h + 1, rz), Blocks.HELLSTONE, false)
