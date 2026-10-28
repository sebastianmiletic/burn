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
##
## Revision 3 (new worlds): a 4.6 km map. The campaign island keeps its places and
## gains two continents joined by land bridges, the Eastreach (Elderwood redwoods,
## the Highmere Alps with glacial lakes, the Pale Tundra, the Kaldfjord coast and
## the Red Mesas) and the Sunderlands (Brimstone Badlands around a caldera volcano,
## more mesas and redwoods). Mountains are sculpted massifs (peaks, ridgelines,
## couloirs, scree, snowcaps); ravines, cave mouths, sinkholes, flooded and magma
## chambers, underground rivers and full abandoned mines join the cave network
## (world/caves/cave_network.gd).

enum Dimension { OVERWORLD, HELL, RYFT }
enum Biome { OCEAN, PLAINS, FOREST, PEAKS, MARSH, WASTES, ASPHODEL, LAKE_OF_FIRE, TARTARUS, RYFT,
		REDWOOD, CANYON, ALPINE, TUNDRA, VOLCANIC, FJORD }

const BIOME_NAMES := ["The Grey Sea", "The Ashen Plains", "Emberwood", "Frost Peaks", "Blackmarsh",
		"Cinder Wastes", "Asphodel Fields", "Lake of Fire", "Tartarus", "Ryft Island",
		"The Elderwood", "The Red Mesas", "Highmere Alps", "The Pale Tundra", "Brimstone Badlands", "Kaldfjord Coast"]
## Map and horizon colours per biome (MapImage, DistantLand).
const BIOME_COLORS := [Color(0.08, 0.12, 0.16), Color(0.5, 0.45, 0.28), Color(0.42, 0.36, 0.18), Color(0.6, 0.62, 0.66),
		Color(0.24, 0.27, 0.18), Color(0.36, 0.3, 0.28), Color(0.35, 0.28, 0.26), Color(0.85, 0.3, 0.06),
		Color(0.22, 0.18, 0.18), Color(0.4, 0.35, 0.55),
		Color(0.2, 0.3, 0.16), Color(0.66, 0.36, 0.22), Color(0.4, 0.5, 0.36), Color(0.56, 0.58, 0.55),
		Color(0.21, 0.17, 0.16), Color(0.3, 0.4, 0.34)]

const FOREST_NAMES := ["Emberwood", "Northern Pinewoods", "Crimson Grove", "Oldgrowth Ironwood"]
const FOREST_COLORS := [Color(0.42, 0.36, 0.18), Color(0.22, 0.36, 0.31), Color(0.51, 0.25, 0.19), Color(0.25, 0.32, 0.16)]

## New worlds use the latest revision; saves keep the revision they were made with.
## Revision 4 adds the ocean biomes, sea structures and the ocean bosses' lairs (new worlds only).
## Revision 5 adds the surface lands and landforms of world/biomes/surface_biomes.gd (and more).
const LATEST_REVISION := 5
const SEA_LEVEL := 12
const LAVA_LEVEL := 0  ## hell
const COARSE := 4      ## metres per coarse map cell
const BLEND := 32      ## revision 3: metres per biome-blend cell
const VEIN_SHIFT := 3  ## revision 5: ore veins live in 8 m cells (one vein at most per cell)
const VEIN_CHANCE := 0.6  ## revision 5: chance an 8 m rock cell holds a vein
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
	Biome.REDWOOD: Vector3(30.0, 9.0, 0.0),
	Biome.CANYON: Vector3(34.0, 2.0, 0.0),
	Biome.ALPINE: Vector3(50.0, 7.0, 0.0),
	Biome.TUNDRA: Vector3(22.0, 3.5, 0.0),
	Biome.VOLCANIC: Vector3(26.0, 4.5, 0.0),
	Biome.FJORD: Vector3(44.0, 7.0, 0.0),
}
## Revision 3 mountains: shape before the sculpted massifs are added.
const PEAKS_SHAPE_V3 := Vector3(56.0, 7.0, 0.0)

## Revision 3 continents, joined to the campaign island by land bridges: (x, z, radius).
const CONTINENTS := [
	# The eastern land bridge beyond Thornwick.
	Vector3(1900, 1075, 125), Vector3(2040, 1095, 135), Vector3(2180, 1085, 150),
	# The Eastreach.
	Vector3(2450, 1050, 330), Vector3(2640, 760, 380), Vector3(3020, 600, 470), Vector3(3480, 560, 430),
	Vector3(3900, 560, 360), Vector3(4020, 900, 300), Vector3(3680, 1100, 470), Vector3(3150, 1150, 480),
	Vector3(2700, 1500, 380), Vector3(3250, 1750, 430), Vector3(3780, 1680, 380), Vector3(3980, 1420, 290),
	Vector3(3520, 2120, 380), Vector3(3000, 2200, 330),
	# The southern land bridge below the Dragon's Keep.
	Vector3(1010, 1990, 125), Vector3(1050, 2140, 140),
	# The Sunderlands.
	Vector3(1150, 2480, 360), Vector3(1700, 2600, 380), Vector3(2200, 2760, 340), Vector3(700, 2800, 340),
	Vector3(1250, 3000, 450), Vector3(1850, 3150, 420), Vector3(800, 3350, 360), Vector3(1400, 3550, 400),
	Vector3(2050, 3580, 330), Vector3(950, 3820, 300), Vector3(1600, 3900, 280),
]
## Revision 3 massifs: (x, z, height, radius). Each sculpts a peak with ridgelines and couloirs.
const PEAKS := [
	# Frost Peaks (campaign island).
	Vector4(1024, 250, 170, 330), Vector4(770, 390, 145, 300), Vector4(1290, 330, 160, 320),
	Vector4(900, 170, 135, 260), Vector4(1170, 165, 145, 270), Vector4(610, 300, 115, 240), Vector4(1430, 450, 120, 250),
	# Highmere Alps.
	Vector4(2780, 470, 280, 420), Vector4(3080, 380, 330, 460), Vector4(3400, 470, 300, 430), Vector4(3150, 770, 230, 360),
	Vector4(2650, 720, 200, 330), Vector4(3660, 340, 245, 360), Vector4(3560, 760, 200, 320), Vector4(2900, 230, 210, 300),
	# Kaldfjord highlands.
	Vector4(3990, 1080, 150, 300), Vector4(3930, 1460, 135, 280), Vector4(3800, 1260, 120, 260),
]
## The Brimstone caldera volcano: x, z, height, radius; caldera radius and depth.
const VOLCANO := Vector4(1250, 2620, 225, 560)
const CALDERA := Vector2(82, 78)
## Revision 4: where the ocean bosses' lairs are searched for (the trench, the maelstrom).
const KRAKEN_SITE := Vector2(3350, 2640)
const MAELSTROM_SITE := Vector2(1420, 4280)
## Kaldfjord inlets: polylines from the open sea inland (x, z, half width).
const FJORDS := [
	[Vector3(4460, 1030, 60), Vector3(4230, 1070, 52), Vector3(4060, 1010, 44), Vector3(3880, 1060, 34), Vector3(3760, 1010, 22)],
	[Vector3(4420, 1360, 62), Vector3(4200, 1390, 50), Vector3(4010, 1330, 42), Vector3(3850, 1400, 30)],
	[Vector3(4300, 1690, 55), Vector3(4110, 1640, 44), Vector3(3960, 1700, 30), Vector3(3840, 1650, 20)],
]
## Revision 4 ocean biomes (sea columns only; biome_at() still says OCEAN): HUD names,
## map tints, and [depth below the surface, sea-bed relief] blended between the seeds.
enum Sea { NONE, GREY, SHELF, REEF, SEAGRASS, KELP, FROZEN, VENTS, ABYSS, MAELSTROM }
const SEA_NAMES := ["", "The Grey Sea", "The Pale Shelf", "The Shimmering Shallows", "The Drowned Meadows",
		"The Kelpwood Deep", "The Rime Sea", "The Boiling Shoals", "The Abyssal Trench", "The Maelstrom"]
const SEA_COLORS := [Color(0, 0, 0), Color(0.08, 0.12, 0.16), Color(0.2, 0.32, 0.34), Color(0.16, 0.52, 0.54), Color(0.12, 0.3, 0.26),
		Color(0.1, 0.22, 0.2), Color(0.42, 0.5, 0.56), Color(0.18, 0.13, 0.12), Color(0.02, 0.04, 0.08), Color(0.06, 0.1, 0.16)]
const SEA_SHAPE := [Vector2(26, 3), Vector2(26, 3), Vector2(12, 2), Vector2(5.2, 1.4), Vector2(6.5, 1.0), Vector2(17, 3.5),
		Vector2(20, 3), Vector2(21, 4), Vector2(30, 3), Vector2(30, 2)]
const SEA_SEEDS := [
	[Vector2(250, 3000), Sea.REEF], [Vector2(300, 3750), Sea.REEF], [Vector2(1100, 4380), Sea.REEF], [Vector2(1950, 4250), Sea.REEF], [Vector2(130, 2450), Sea.REEF],
	[Vector2(2150, 1550), Sea.SEAGRASS], [Vector2(2250, 1950), Sea.SEAGRASS], [Vector2(2450, 3200), Sea.SEAGRASS], [Vector2(2550, 3750), Sea.SEAGRASS],
	[Vector2(2250, 2450), Sea.KELP], [Vector2(60, 1100), Sea.KELP], [Vector2(100, 600), Sea.KELP], [Vector2(1500, 100), Sea.KELP], [Vector2(2050, 300), Sea.KELP], [Vector2(4350, 2350), Sea.KELP],
	[Vector2(4470, 300), Sea.FROZEN], [Vector2(4500, 900), Sea.FROZEN], [Vector2(4520, 1550), Sea.FROZEN], [Vector2(3800, 90), Sea.FROZEN], [Vector2(3000, 80), Sea.FROZEN], [Vector2(4480, 2000), Sea.FROZEN],
	[Vector2(650, 2180), Sea.VENTS], [Vector2(1750, 2230), Sea.VENTS],
	[Vector2(3400, 3300), Sea.GREY], [Vector2(4200, 3500), Sea.GREY], [Vector2(3000, 4300), Sea.GREY], [Vector2(4300, 4350), Sea.GREY],
	[Vector2(2200, 1200), Sea.GREY], [Vector2(600, 4400), Sea.GREY], [Vector2(60, 1900), Sea.GREY], [Vector2(700, 60), Sea.GREY],
]
## The Abyssal Trench: polyline (x, z, half width) through the south-eastern deep.
const TRENCH := [Vector3(2850, 2800, 55), Vector3(3350, 2700, 80), Vector3(3800, 2850, 85), Vector3(4150, 3250, 85), Vector3(4450, 3900, 70)]

## Ravines: how strongly each biome is cut by them (0 never).
const RAVINE_ALLOWANCE := [0.0, 0.45, 0.7, 0.3, 0.0, 0.55, 0.0, 0.0, 0.0, 0.0, 1.0, 0.85, 0.35, 0.35, 0.5, 0.25]

var dimension := Dimension.OVERWORLD
var world_seed := 1
var revision := 2  ## Saves made before this update retain revision 1 terrain.
var size := 2048  ## world extent in blocks (x and z)
var locations: Array[Location] = []
## Revision 3: natural cave mouths, sinkholes, rivers and mine workings.
var caves: CaveNetwork
## Revision 3 lakes: [Vector2 centre, radius, level, surface block (WATER, ICE or LAVA)].
var lakes: Array = []

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

# Revision 3 maps (COARSE cells): mountain weight, ravine allowance (0..255), protected (1).
var _mtn := PackedFloat32Array()
var _rav := PackedByteArray()
var _protect := PackedByteArray()
var _hmap := PackedFloat32Array()
var _hmap_mutex := Mutex.new()
# Revision 3 blend grid (BLEND cells), freed after prepare().
var _bn := 0
var _b_shape := PackedVector3Array()
var _b_w := PackedColorArray()
var _b_s := PackedFloat32Array()
var _b_near := PackedInt32Array()
var _b_warp := PackedVector2Array()
# Revision 4 sea: blended [depth, relief] and the nearest sea seed per blend cell; sea biome per COARSE cell.
var _b_sea := PackedVector2Array()
var _b_sea_near := PackedInt32Array()
var _ocean := PackedByteArray()
## Revision 5: surface lands (SurfaceBiomes) and their 4 m map (land | weight << 3).
var land: SurfaceBiomes
var _land := PackedByteArray()
## While locations are planned the ravines are not cut yet (they avoid the planned sites).
var _planning := false
var _seed_pos := PackedVector2Array()
var _seed_biome := PackedByteArray()
var _roads: Array[PackedVector2Array] = []
var _bp_index := {}  # Vector2i chunk column -> Array[Blueprint]
# Shared noise (FastNoiseLite sampling is read-only and safe across threads).
var _n_detail: FastNoiseLite
var _n_ridge: FastNoiseLite
var _n_couloir: FastNoiseLite
var _n_ravine: FastNoiseLite
var _n_ravmask: FastNoiseLite
# Column cache for revision 3 chunk generation.
var _col_cache := {}
var _col_ring := PackedInt64Array()
var _col_next := 0
var _col_mutex := Mutex.new()
const COLUMN_CACHE := 2048


func _init(dim: Dimension, seed_value: int, world_revision := LATEST_REVISION) -> void:
	dimension = dim
	world_seed = seed_value
	revision = world_revision
	if dim == Dimension.OVERWORLD:
		size = 4608 if revision >= 3 else (3072 if revision >= 2 else 2048)
	else:
		size = 640
	_coarse_n = size / COARSE
	if _v3():
		_n_detail = make_detail_noise()
		_n_ridge = make_ridge_noise()
		_n_couloir = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.036, 1, 41)
		_n_ravine = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0029, 2, 43)
		_n_ravmask = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0021, 1, 44)
		_col_ring.resize(COLUMN_CACHE)
		_col_ring.fill(-1)
		if revision >= 5:
			land = SurfaceBiomes.new(seed_value)


## Revision 3 overworld.
func _v3() -> bool:
	return revision >= 3 and dimension == Dimension.OVERWORLD


func center() -> Vector2:
	# Keep the campaign coordinates; new lands extend east/south.
	return Vector2(1024, 1024) if dimension == Dimension.OVERWORLD else Vector2(size * 0.5, size * 0.5)


# --- Preparation --------------------------------------------------------------

func prepare(progress: Callable = Callable(), timing := false) -> void:
	var t := Time.get_ticks_msec()
	_setup_biome_seeds()
	if dimension == Dimension.OVERWORLD and land == null:
		SurfaceBiomes.unregister()
	_report(progress, 0.05, "Shaping the land")
	if _v3():
		_build_maps_v3()
		_report(progress, 0.3, "Filling the lakes")
		_plan_lakes()
	else:
		_build_coarse_maps()
	var t_coarse := Time.get_ticks_msec() - t
	_report(progress, 0.45, "Raising the ruins")
	_planning = true
	var planner := LocationPlanner.new(self)
	locations = planner.plan()
	_planning = false
	for loc in locations:
		_blueprints.append_array(loc.blueprints)
	var t_plan := Time.get_ticks_msec() - t - t_coarse
	_roads = LocationPlanner.roads(self)
	var t_caves := 0
	if _v3():
		_report(progress, 0.65, "Hollowing the caves")
		var t0 := Time.get_ticks_msec()
		_protect_sites()
		caves = CaveNetwork.plan_natural(self)
		if land != null:
			land.plan_caves(self, caves)
		for loc in locations:
			if loc.has_meta(&"carvers"):
				caves.merge(loc.get_meta(&"carvers") as CaveNetwork)
		CaveBiomes.revision = revision
		CaveBiomes.zones = []
		CaveBiomes.special_cells = {}
		if revision >= 5:
			UndergroundPlan.plan(self)  # varied caves, the Everbloom cavern, Hearthold (world/underground)
		caves.build_index()
		var boxes: Array[AABB] = []
		for loc in locations:
			if loc.has_meta(&"mine"):
				var ext := Vector3(loc.radius, loc.half_height + 2.0, loc.radius)
				boxes.append(AABB(loc.center - ext, ext * 2.0))
		CaveBiomes.mine_boxes = boxes
		t_caves = Time.get_ticks_msec() - t0
	_report(progress, 0.75, "Laying the old roads")
	var t1 := Time.get_ticks_msec()
	_rasterise_pads()
	_index_blueprints()
	_b_shape = PackedVector3Array()
	_b_w = PackedColorArray()
	_b_s = PackedFloat32Array()
	_b_near = PackedInt32Array()
	_b_warp = PackedVector2Array()
	_report(progress, 1.0, "Done")
	if timing or "--load-timing" in OS.get_cmdline_user_args():
		print("[load]   dim %d: coarse %d ms, plan %d ms, caves %d ms, pads/roads %d ms" % [dimension, t_coarse, t_plan, t_caves, Time.get_ticks_msec() - t1])


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
		if revision >= 3:
			# The new lands (appended so the campaign island's seeds are unchanged).
			for s: Array in [
					[Vector2(2330, 1080), Biome.REDWOOD], [Vector2(2600, 1330), Biome.REDWOOD], [Vector2(2560, 860), Biome.REDWOOD],
					[Vector2(2860, 520), Biome.ALPINE], [Vector2(3220, 470), Biome.ALPINE], [Vector2(3560, 560), Biome.ALPINE], [Vector2(3000, 820), Biome.ALPINE],
					[Vector2(3900, 470), Biome.TUNDRA], [Vector2(4000, 760), Biome.TUNDRA], [Vector2(3700, 270), Biome.TUNDRA],
					[Vector2(3980, 1150), Biome.FJORD], [Vector2(3900, 1520), Biome.FJORD],
					[Vector2(3150, 1200), Biome.PLAINS], [Vector2(3550, 1250), Biome.FOREST], [Vector2(2850, 1250), Biome.FOREST],
					[Vector2(3250, 1850), Biome.CANYON], [Vector2(3680, 2000), Biome.CANYON], [Vector2(3000, 2230), Biome.CANYON], [Vector2(2800, 1650), Biome.CANYON],
					[Vector2(1150, 2560), Biome.VOLCANIC], [Vector2(1560, 2640), Biome.VOLCANIC], [Vector2(1300, 2900), Biome.VOLCANIC],
					[Vector2(760, 2900), Biome.REDWOOD], [Vector2(1000, 3350), Biome.REDWOOD],
					[Vector2(1900, 3150), Biome.CANYON], [Vector2(2180, 2820), Biome.CANYON], [Vector2(1650, 3550), Biome.CANYON],
					[Vector2(1350, 3700), Biome.PLAINS], [Vector2(900, 3800), Biome.FOREST], [Vector2(2050, 3600), Biome.PLAINS]]:
				_biome_seeds.append([j.call(s[0]), s[1]])
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


# --- Revision 3 maps -----------------------------------------------------------

func _build_maps_v3() -> void:
	_bn = size / BLEND
	_b_shape.resize(_bn * _bn)
	_b_w.resize(_bn * _bn)
	_b_s.resize(_bn * _bn)
	_b_near.resize(_bn * _bn * 2)
	_b_warp.resize(_bn * _bn)
	if revision >= 4:
		_b_sea.resize(_bn * _bn)
		_b_sea_near.resize(_bn * _bn)
		_ocean.resize(_coarse_n * _coarse_n)
	_seed_pos.clear()
	_seed_biome.clear()
	for sd: Array in _biome_seeds:
		_seed_pos.append(sd[0])
		_seed_biome.append(sd[1])
	var tb := Time.get_ticks_msec()
	var task := WorkerThreadPool.add_group_task(_blend_rows, _bn, -1, true, "biome blend")
	WorkerThreadPool.wait_for_group_task_completion(task)
	if "--load-timing" in OS.get_cmdline_user_args():
		print("[load]   blend grid %d ms (%d cpus)" % [Time.get_ticks_msec() - tb, OS.get_processor_count()])
	var n := _coarse_n
	_base.resize(n * n)
	_amp.resize(n * n)
	_ridge.resize(n * n)
	_biome.resize(n * n)
	_mtn.resize(n * n)
	_rav.resize(n * n)
	_protect.resize(n * n)
	if land != null:
		_land.resize(n * n)
	task = WorkerThreadPool.add_group_task(_rows_v3, n, -1, true, "terrain maps")
	WorkerThreadPool.wait_for_group_task_completion(task)


static func _smin(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


static func _smax(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(a, b, h) + k * h * (1.0 - h)


## One row of the 16 m blend grid: biome shape weights (inverse distance), feature weights
## (mountains, mesas, volcano, fjords), the land / sea signed distance and the two nearest seeds.
func _blend_rows(row: int) -> void:
	var warp := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0025, 3, 11)
	var warp2 := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0025, 3, 12)
	var macro := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.004, 2, 13)
	var shore := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.006, 3, 14)
	var c := center()
	for col in _bn:
		var p := Vector2(col * BLEND + BLEND * 0.5, row * BLEND + BLEND * 0.5)
		var wo := Vector2(warp.get_noise_2dv(p), warp2.get_noise_2dv(p)) * 130.0
		var wp := p + wo
		var total := 0.0
		var shape := Vector3.ZERO
		var w := Color(0, 0, 0, 0)
		var b1 := 1e20
		var b2 := 1e20
		var i1 := 0
		var i2 := 0
		for si in _biome_seeds.size():
			var s: Array = _biome_seeds[si]
			var d := wp.distance_squared_to(s[0])
			var wt := 1.0 / (d * d + 1.0)
			total += wt
			var biome: int = s[1]
			shape += (PEAKS_SHAPE_V3 if biome == Biome.PEAKS else BIOME_SHAPE[biome]) * wt
			match biome:
				Biome.PEAKS, Biome.ALPINE:
					w.r += wt
				Biome.FJORD:
					w.r += wt * 0.75
					w.a += wt
				Biome.CANYON:
					w.g += wt
				Biome.VOLCANIC:
					w.b += wt
			if d < b1:
				b2 = b1
				i2 = i1
				b1 = d
				i1 = si
			elif d < b2:
				b2 = d
				i2 = si
		shape /= total
		shape.x += macro.get_noise_2dv(p) * 4.0
		w = Color(w.r / total, w.g / total, w.b / total, w.a / total)
		# Land: the campaign island (as in revision 2) joined to the new continents.
		var r := p.distance_to(c)
		var coast := warp.get_noise_2dv(p * 2.0) * 160.0 + sin((p - c).angle() * 5.0 + 0.7) * 65.0
		var s_land := r + coast - 925.0
		var s_new := 1e9
		for blob: Vector3 in CONTINENTS:
			s_new = _smin(s_new, p.distance_to(Vector2(blob.x, blob.y)) - blob.z, 140.0)
		s_new += shore.get_noise_2dv(p) * 95.0 + warp2.get_noise_2dv(p * 2.3) * 40.0
		var i := col + row * _bn
		_b_shape[i] = shape
		_b_w[i] = w
		_b_s[i] = _smin(s_land, s_new, 60.0) if s_new < 400.0 else s_land
		_b_warp[i] = wo
		_b_near[i * 2] = i1
		_b_near[i * 2 + 1] = i2
		if revision >= 4:
			var sw := 0.0
			var sea := Vector2.ZERO
			var sb := 1e20
			var si := 0
			for k in SEA_SEEDS.size():
				var sd: Array = SEA_SEEDS[k]
				var d2 := wp.distance_squared_to(sd[0])
				var wt := 1.0 / (d2 * d2 + 1.0)
				sw += wt
				sea += (SEA_SHAPE[int(sd[1])] as Vector2) * wt
				if d2 < sb:
					sb = d2
					si = k
			_b_sea[i] = sea / sw
			_b_sea_near[i] = si


## One row of the 4 m terrain maps: the blend grid interpolated, the nearest biome resolved at
## full resolution, then the sculpted features (massifs, mesas, the volcano, fjords, the coast).
func _rows_v3(row: int) -> void:
	var mwarp := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0032, 2, 51)
	var mwarp2 := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0032, 2, 52)
	var mridge := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0034, 3, 53)
	var mridge2 := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0095, 2, 54)
	var canyon := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0036, 2, 55)
	var basin := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0017, 1, 56)
	var cwarp := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.006, 2, 57)
	var n := _coarse_n
	var bn := _bn
	var near := _b_near
	var seed_pos := _seed_pos
	var seed_biome := _seed_biome
	var fz := clampf((float(row) + 0.5) * COARSE / BLEND - 0.5, 0.0, bn - 1.001)
	var iz := int(fz)
	var tz := fz - iz
	for col in n:
		var p := Vector2(col * COARSE + COARSE * 0.5, row * COARSE + COARSE * 0.5)
		var fx := clampf((float(col) + 0.5) * COARSE / BLEND - 0.5, 0.0, bn - 1.001)
		var ix := int(fx)
		var tx := fx - ix
		var i00 := ix + iz * bn
		var i10 := i00 + 1
		var i01 := i00 + bn
		var i11 := i01 + 1
		var shape := (_b_shape[i00] * (1.0 - tx) + _b_shape[i10] * tx) * (1.0 - tz) + (_b_shape[i01] * (1.0 - tx) + _b_shape[i11] * tx) * tz
		var wc := (_b_w[i00] * (1.0 - tx) + _b_w[i10] * tx) * (1.0 - tz) + (_b_w[i01] * (1.0 - tx) + _b_w[i11] * tx) * tz
		var s := lerpf(lerpf(_b_s[i00], _b_s[i10], tx), lerpf(_b_s[i01], _b_s[i11], tx), tz)
		# Nearest seed among the corners' two nearest (exact, warped Voronoi boundaries).
		var wp := p + (_b_warp[i00] * (1.0 - tx) + _b_warp[i10] * tx) * (1.0 - tz) + (_b_warp[i01] * (1.0 - tx) + _b_warp[i11] * tx) * tz
		var s0 := near[i00 * 2]
		var best := wp.distance_squared_to(seed_pos[s0])
		var biome := seed_biome[s0]
		for si in [near[i00 * 2 + 1], near[i10 * 2], near[i10 * 2 + 1], near[i01 * 2], near[i01 * 2 + 1], near[i11 * 2], near[i11 * 2 + 1]]:
			if si == s0:
				continue
			var sd := wp.distance_squared_to(seed_pos[si])
			if sd < best:
				best = sd
				biome = seed_biome[si]
		var base := shape.x
		# Mountains: sculpted massifs.
		if wc.r > 0.01:
			base += wc.r * _massif(p, mwarp, mwarp2, mridge, mridge2)
		# Mesas and canyons.
		if wc.g > 0.02:
			base = lerpf(base, _mesa(p, canyon, basin, cwarp), smoothstep(0.02, 0.6, wc.g))
		# The caldera volcano.
		if wc.b > 0.004:
			base += _volcano(p) * smoothstep(0.0, 0.5, wc.b)
		var land_code := 0
		if land != null:
			# Revision 5: the surface lands and landforms (world/biomes/surface_biomes.gd).
			var lc := land.cell(p, base, shape.y, shape.z, biome)
			base = lc.x
			shape = Vector3(shape.x, lc.y, lc.z)
			biome = int(lc.w) & 255
			land_code = int(lc.w) >> 8
		# Coast: gentle beaches, but sheer cliffs along the fjords.
		var soft := lerpf(65.0, 22.0, clampf(wc.a * 1.6, 0.0, 1.0))
		var t := smoothstep(-soft, soft, s)
		# Inlets cut the land; out at sea they just merge with the open water.
		var fj := _fjord_mask(p) * (1.0 - smoothstep(0.35, 0.95, t))
		var ocean: Vector3 = BIOME_SHAPE[Biome.OCEAN]
		var sea_kind := 0
		if revision >= 4:
			# Revision 4: the sea bed of the nearest ocean biome, shelving away from the coast,
			# the trench and the maelstrom's bowl cut into it.
			var sea := (_b_sea[i00] * (1.0 - tx) + _b_sea[i10] * tx) * (1.0 - tz) + (_b_sea[i01] * (1.0 - tx) + _b_sea[i11] * tx) * tz
			# The coastline itself stays where revision 3 drew it: the new sea bed only takes
			# over beyond the shore slope (t ~ 1), shelving in over the first ~100 m.
			var tr := _trench(p)
			var md := p.distance_to(MAELSTROM_SITE)
			var depth := sea.x + tr * 72.0 + 14.0 * (1.0 - smoothstep(60.0, 260.0, md))
			var take := smoothstep(0.85, 1.0, t) * smoothstep(30.0, 130.0, s)
			ocean = Vector3(lerpf(ocean.x, SEA_LEVEL - depth, take), lerpf(ocean.y, sea.y, take), 0.0)
			var best_sea := 1e20
			for ci in [i00, i10, i01, i11]:
				var sd: Array = SEA_SEEDS[_b_sea_near[ci]]
				var d2 := wp.distance_squared_to(sd[0])
				if d2 < best_sea:
					best_sea = d2
					sea_kind = int(sd[1])
			if tr > 0.3:
				sea_kind = Sea.ABYSS
			elif md < 240.0:
				sea_kind = Sea.MAELSTROM
			elif sea_kind == Sea.GREY and s < 200.0:
				sea_kind = Sea.SHELF
		base = lerpf(base, ocean.x, t)
		var amp := lerpf(shape.y, ocean.y, t)
		var ridge := lerpf(shape.z, ocean.z, t)
		if fj > 0.0:
			base = lerpf(base, -24.0, fj)
			amp = lerpf(amp, 2.0, fj)
		if t > 0.5 or fj > 0.6:
			biome = Biome.OCEAN
		# The Cinder Crater above the Gates of Hades (as in revision 2).
		var cd := p.distance_to(Vector2(_crater.x, _crater.y))
		base -= 22.0 * (1.0 - smoothstep(0.0, _crater.z, cd))
		base += 7.0 * exp(-pow((cd - _crater.z) / 14.0, 2.0))
		ridge *= smoothstep(_crater.z * 0.6, _crater.z * 1.6, cd)
		var adv_flags := 0
		if revision >= 5:
			# Revision 5: Mount Pyrrhos' caldera, the outer isles, the Atlantis bowl.
			var sc := AdventureTerrain.shape_column(p, base, amp, biome)
			base = sc[0]
			amp = sc[1]
			biome = sc[2]
			adv_flags = sc[3]
		var i := col + row * n
		_base[i] = base
		_amp[i] = amp
		_ridge[i] = ridge
		_biome[i] = biome
		if revision >= 4:
			_ocean[i] = sea_kind if biome == Biome.OCEAN else 0
		if land != null:
			_land[i] = land_code if biome != Biome.OCEAN else 0
		_mtn[i] = wc.r * (1.0 - t) * (1.0 - fj)
		var allow: float = RAVINE_ALLOWANCE[biome] * (1.0 - t) * (1.0 - fj) * smoothstep(SEA_LEVEL + 10.0, SEA_LEVEL + 28.0, base)
		allow *= 1.0 - smoothstep(0.3, 0.8, wc.r) * 0.6
		_rav[i] = clampi(int(allow * 255.0), 0, 255) if adv_flags & 1 == 0 else 0


## Peak envelope with ridgelines and erosion (metres above the biome base).
func _massif(p: Vector2, mwarp: FastNoiseLite, mwarp2: FastNoiseLite, mridge: FastNoiseLite, mridge2: FastNoiseLite) -> float:
	var near := false
	for pk: Vector4 in PEAKS:
		if absf(p.x - pk.x) < pk.w + 110.0 and absf(p.y - pk.y) < pk.w + 110.0:
			near = true
			break
	if not near:
		return 0.0
	var wp := p + Vector2(mwarp.get_noise_2dv(p), mwarp2.get_noise_2dv(p)) * 105.0
	var env := 0.0
	for pk: Vector4 in PEAKS:
		var dx := absf(wp.x - pk.x)
		var dz := absf(wp.y - pk.y)
		if dx > pk.w or dz > pk.w:
			continue
		var x := sqrt(dx * dx + dz * dz) / pk.w
		if x >= 1.0:
			continue
		env = _smax(env, pk.z * pow(1.0 - x, 1.75), 22.0)
	if env <= 0.0:
		return 0.0
	# Ridgelines radiate where the ridged noise crests; the ground between them falls into
	# valleys and cirques. A finer ridged octave carves spurs and buttresses.
	var r := 1.0 - absf(mridge.get_noise_2dv(wp))
	var r2 := 1.0 - absf(mridge2.get_noise_2dv(wp))
	return env * (0.58 + 0.42 * r * r) + env * 0.09 * (r2 * r2 - 0.45)


## Plateaus cut by winding canyons, with buttes and a soft bench in the walls.
func _mesa(p: Vector2, canyon: FastNoiseLite, basin: FastNoiseLite, cwarp: FastNoiseLite) -> float:
	var wp := p + Vector2(cwarp.get_noise_2dv(p), cwarp.get_noise_2d(p.y + 500.0, p.x)) * 45.0
	var an := absf(canyon.get_noise_2dv(wp))
	var s := smoothstep(0.035, 0.2, an)
	s = s + 0.075 * sin(s * TAU)
	var low := smoothstep(0.1, 0.42, basin.get_noise_2dv(p)) * (1.0 - smoothstep(0.42, 0.55, an))
	var top := lerpf(80.0, 44.0, low)
	return lerpf(32.0, top, s)


## The caldera volcano above the biome base.
func _volcano(p: Vector2) -> float:
	if revision >= 5:
		return AdventureTerrain.volcano(p)
	var d := p.distance_to(Vector2(VOLCANO.x, VOLCANO.y))
	if d >= VOLCANO.w:
		return 0.0
	var x := d / VOLCANO.w
	var cone := VOLCANO.z * pow(1.0 - x, 1.55)
	# Lava channels scored down the flanks.
	cone *= 1.0 - 0.06 * (0.5 + 0.5 * sin(atan2(p.y - VOLCANO.y, p.x - VOLCANO.x) * 13.0 + d * 0.012)) * smoothstep(0.15, 0.4, x)
	var rim := VOLCANO.z * pow(1.0 - CALDERA.x / VOLCANO.w, 1.55)
	var bowl := rim - CALDERA.y * (1.0 - pow(minf(d / CALDERA.x, 1.0), 2.2))
	var inside := 1.0 - smoothstep(CALDERA.x * 0.9, CALDERA.x * 1.12, d)
	return lerpf(minf(cone, rim + 4.0), bowl, inside)


## 0..1: inside a fjord inlet.
func _fjord_mask(p: Vector2) -> float:
	if p.x < 3650.0 or p.y < 850.0 or p.y > 1850.0:
		return 0.0
	var best := 0.0
	for line: Array in FJORDS:
		for k in line.size() - 1:
			var a: Vector3 = line[k]
			var b: Vector3 = line[k + 1]
			var ab := Vector2(b.x - a.x, b.y - a.y)
			var t := clampf((p - Vector2(a.x, a.y)).dot(ab) / ab.length_squared(), 0.0, 1.0)
			var q := Vector2(a.x, a.y) + ab * t
			var hw := lerpf(a.z, b.z, t)
			var d := p.distance_to(q)
			best = maxf(best, 1.0 - smoothstep(hw, hw + 38.0, d))
	return best


## 0..1: inside the Abyssal Trench (steep walls, revision 4).
func _trench(p: Vector2) -> float:
	if p.x < 2700.0 or p.y < 2600.0:
		return 0.0
	var best := 0.0
	for k in TRENCH.size() - 1:
		var a: Vector3 = TRENCH[k]
		var b: Vector3 = TRENCH[k + 1]
		var ab := Vector2(b.x - a.x, b.y - a.y)
		var t := clampf((p - Vector2(a.x, a.y)).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var hw := lerpf(a.z, b.z, t)
		var d := p.distance_to(Vector2(a.x, a.y) + ab * t)
		best = maxf(best, 1.0 - smoothstep(hw * 0.5, hw, d))
	return best


## Revision 4: the ocean biome of a sea column (Sea.NONE on land and in older worlds).
func sea_at(x: float, z: float) -> int:
	if _ocean.is_empty():
		return Sea.NONE
	var ix := clampi(int(x / COARSE), 0, _coarse_n - 1)
	var iz := clampi(int(z / COARSE), 0, _coarse_n - 1)
	return _ocean[ix + iz * _coarse_n]


## What the HUD calls a place in the wilds: the forest stand, the ocean biome or the biome.
func region_name(x: float, z: float) -> String:
	if land != null:
		var ln := land.region_name(Vector2(x, z))
		if ln != "":
			return ln
	var biome := biome_at(int(x), int(z))
	if biome == Biome.FOREST:
		return FOREST_NAMES[forest_region(int(x), int(z))]
	var sk := sea_at(x, z)
	if biome == Biome.OCEAN and sk != Sea.NONE:
		return SEA_NAMES[sk]
	return BIOME_NAMES[biome]


## Sea-bed relief per ocean biome on top of the blended floor (revision 4): reef heads,
## sand ripples, kelp-forest boulders, vent chimneys.
func _seabed(x: int, z: int, h: float, sk: int) -> float:
	match sk:
		Sea.REEF:
			var m := _vnoise(x, z, 7.0, world_seed + 81)
			if m > 0.58 and h < SEA_LEVEL - 1.6:
				h = minf(h + (m - 0.58) / 0.42 * 4.5, SEA_LEVEL - 1.6)
		Sea.SHELF, Sea.SEAGRASS, Sea.GREY:
			h += sin(x * 0.6 + z * 0.21 + _vnoise(x, z, 17.0, world_seed + 83) * 7.0) * 0.22
		Sea.KELP, Sea.FROZEN, Sea.MAELSTROM:
			h += maxf(0.0, _vnoise(x, z, 5.0, world_seed + 85) - 0.55) * 7.0
		Sea.VENTS:
			var cx := floori(x / 22.0)
			var cz := floori(z / 22.0)
			var hs := _hash3(cx, 7, cz, world_seed + 89)
			if hs & 3 != 0:
				var vx := cx * 22.0 + 5.0 + float(hs >> 4 & 15) * 0.8
				var vz := cz * 22.0 + 5.0 + float(hs >> 8 & 15) * 0.8
				var d := Vector2(x - vx, z - vz).length()
				if d < 4.5:
					h += 6.5 * pow(1.0 - d / 4.5, 1.6)
	return h


## Sea-floor surface (low byte) and subsoil (high byte) per ocean biome (revision 4).
func _sea_floor(x: int, z: int, h: int, n: float) -> int:
	match sea_at(x, z):
		Sea.REEF:
			return (Blocks.CORAL_ROCK | (Blocks.LIMESTONE << 8)) if n < 0.55 else (Blocks.SAND | (Blocks.SAND << 8))
		Sea.SEAGRASS:
			return (Blocks.SILT | (Blocks.SILT << 8)) if n < 0.78 else (Blocks.SAND | (Blocks.SAND << 8))
		Sea.SHELF:
			return (Blocks.SAND | (Blocks.SANDSTONE << 8)) if n < 0.8 else (Blocks.GRAVEL | (Blocks.SAND << 8))
		Sea.KELP, Sea.MAELSTROM:
			return (Blocks.GRAVEL | (Blocks.STONE << 8)) if n < 0.55 else (Blocks.STONE | (Blocks.STONE << 8))
		Sea.FROZEN:
			return (Blocks.GRAVEL | (Blocks.SILT << 8)) if n < 0.5 else ((Blocks.SILT if n < 0.8 else Blocks.STONE) | (Blocks.STONE << 8))
		Sea.VENTS:
			if _vnoise(x, z, 4.0, world_seed + 91) > 0.82:
				return Blocks.MAGMA_ROCK | (Blocks.BASALT << 8)
			return (Blocks.BASALT if n < 0.6 else Blocks.SCORIA) | (Blocks.BASALT << 8)
		Sea.ABYSS:
			return (Blocks.SILT if n < 0.7 else Blocks.MUD) | (Blocks.SLATE << 8)
	return (Blocks.SILT if n < 0.35 else Blocks.SAND) | (Blocks.SANDSTONE << 8)


## Ice floe density 0..0.5 over a Rime Sea column (0 = open water), revision 4.
func _floe(x: int, z: int, h: int) -> float:
	if h > SEA_LEVEL - 2 or sea_at(x, z) != Sea.FROZEN:
		return 0.0
	var f := _vnoise(x, z, 13.0, world_seed + 87) * 0.75 + _vnoise(x, z, 41.0, world_seed + 88) * 0.25
	return clampf((f - 0.5) * 4.0, 0.0, 0.5)


## Glacial lakes in the Alps, frozen ponds on the tundra, a lava lake in the caldera and a few
## forest tarns. Each lake sits in a bowl whose rim stays above the water.
func _plan_lakes() -> void:
	lakes.clear()
	var vc := Vector2(VOLCANO.x, VOLCANO.y)
	if revision >= 5:
		lakes.append_array(AdventureTerrain.lakes(self))
	else:
		lakes.append([vc, CALDERA.x * 0.8, smooth_height(vc.x, vc.y) + CALDERA.y * 0.45, Blocks.LAVA])
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 31 + 7
	var want := {Biome.ALPINE: [5, 52.0, 95.0, 220], Biome.TUNDRA: [7, 20.0, 40.0, 150], Biome.REDWOOD: [2, 28.0, 45.0, 260], Biome.FJORD: [2, 30.0, 50.0, 260]}
	for biome: int in want:
		var spec: Array = want[biome]
		var found := 0
		for attempt in 400:
			if found >= int(spec[0]):
				break
			var p := Vector2(rng.randf_range(2100, size - 300), rng.randf_range(150, size - 300))
			if biome_at(int(p.x), int(p.y)) != biome:
				continue
			var radius := rng.randf_range(spec[1], spec[2])
			var ok := true
			for l: Array in lakes:
				if (l[0] as Vector2).distance_to(p) < float(l[1]) + radius + float(spec[3]):
					ok = false
					break
			if not ok:
				continue
			# Valley floors only: the centre must be low compared with its surroundings.
			var hc := smooth_height(p.x, p.y)
			var ring_min := 1e9
			var ring_max := -1e9
			for k in 24:
				var a := TAU * k / 24.0
				var q := p + Vector2(cos(a), sin(a)) * radius * 1.3
				if biome_at(int(q.x), int(q.y)) == Biome.OCEAN:
					ring_min = -1e9
					break
				var hq := smooth_height(q.x, q.y)
				ring_min = minf(ring_min, hq)
				ring_max = maxf(ring_max, hq)
			if ring_min < SEA_LEVEL + 8 or ring_max - ring_min > radius * 1.5 or hc > ring_min + 8.0:
				continue
			var level := ring_min - 1.8
			lakes.append([p, radius, level, Blocks.ICE if biome == Biome.TUNDRA else Blocks.WATER])
			found += 1
	if land != null:
		land.plan(self)  # revision 5: the oasis spring, desert arches
	# Sculpt every bowl: the floor dips below the level, the rim rises above it.
	for l: Array in lakes:
		var c: Vector2 = l[0]
		var radius: float = l[1]
		var level: float = l[2]
		var depth := 3.0 + radius * 0.09
		var outer := radius * 1.55
		var x0 := maxi(int((c.x - outer) / COARSE), 0)
		var x1 := mini(int((c.x + outer) / COARSE), _coarse_n - 1)
		var z0 := maxi(int((c.y - outer) / COARSE), 0)
		var z1 := mini(int((c.y + outer) / COARSE), _coarse_n - 1)
		for iz in range(z0, z1 + 1):
			for ix in range(x0, x1 + 1):
				var i := ix + iz * _coarse_n
				var q := Vector2(ix * COARSE + COARSE * 0.5, iz * COARSE + COARSE * 0.5)
				var d := q.distance_to(c) / radius
				if d > 1.55:
					continue
				if l[3] == Blocks.LAVA:
					_amp[i] *= smoothstep(0.7, 1.4, d)
					_rav[i] = 0
					_protect[i] = 1
					continue
				if d < 1.0:
					_base[i] = minf(_base[i], level - 0.6 - depth * (1.0 - d * d))
				else:
					_base[i] = maxf(_base[i], level + 1.4 * (1.0 - smoothstep(1.0, 1.55, d)) + 0.6)
				_amp[i] *= smoothstep(0.85, 1.55, d)
				_ridge[i] = 0.0
				_mtn[i] *= smoothstep(1.0, 1.55, d)
				_rav[i] = 0
				_protect[i] = 1


## Keeps ravines, cave mouths and sinkholes away from every planned site and road.
func _protect_sites() -> void:
	for loc in locations:
		if loc.dimension != 0:
			continue
		var r := maxf(loc.radius, loc.pad_radius + loc.pad_falloff * 1.8) + 18.0
		_protect_disc(Vector2(loc.center.x, loc.center.z), r, 45.0)
	for road in _roads:
		for k in road.size() - 1:
			var a := road[k]
			var b := road[k + 1]
			var steps := maxi(1, int(a.distance_to(b) / 10.0))
			for s in steps + 1:
				_protect_disc(a.lerp(b, float(s) / steps), 12.0, 30.0)


func _protect_disc(c: Vector2, r: float, feather: float) -> void:
	var outer := r + feather
	var x0 := maxi(int((c.x - outer) / COARSE), 0)
	var x1 := mini(int((c.x + outer) / COARSE), _coarse_n - 1)
	var z0 := maxi(int((c.y - outer) / COARSE), 0)
	var z1 := mini(int((c.y + outer) / COARSE), _coarse_n - 1)
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var d := Vector2(ix * COARSE + COARSE * 0.5, iz * COARSE + COARSE * 0.5).distance_to(c)
			if d > outer:
				continue
			var i := ix + iz * _coarse_n
			if d < r:
				_protect[i] = 1
			_rav[i] = mini(_rav[i], int(255.0 * smoothstep(r, outer, d)))


## True near a planned site, road or lake (revision 3).
func is_protected(x: float, z: float) -> bool:
	if _protect.is_empty():
		return false
	var ix := clampi(int(x / COARSE), 0, _coarse_n - 1)
	var iz := clampi(int(z / COARSE), 0, _coarse_n - 1)
	return _protect[ix + iz * _coarse_n] == 1


## Mountain weight 0..1 at a point (revision 3).
func mountain_weight(x: float, z: float) -> float:
	return 0.0 if _mtn.is_empty() else _coarse_sample(_mtn, x, z)


## Natural ground heights on the 4 m grid (map, horizon), computed once in parallel.
func height_map() -> PackedFloat32Array:
	_hmap_mutex.lock()
	if _hmap.is_empty():
		_hmap.resize(_coarse_n * _coarse_n)
		var task := WorkerThreadPool.add_group_task(_hmap_rows, _coarse_n, -1, true, "height map")
		WorkerThreadPool.wait_for_group_task_completion(task)
	_hmap_mutex.unlock()
	return _hmap


func _hmap_rows(row: int) -> void:
	var detail := make_detail_noise()
	var ridge := make_ridge_noise()
	if not _v3():
		for col in _coarse_n:
			_hmap[col + row * _coarse_n] = column_f(col * COARSE + 2, row * COARSE + 2, detail, ridge).x
		return
	# Revision 3: the macro surface plus its detail and the pads (fine couloirs and ravines are
	# narrower than a map texel anyway).
	var n := _coarse_n
	for col in n:
		var i := col + row * n
		var x := col * COARSE + 2
		var z := row * COARSE + 2
		var h := _base[i] + detail.get_noise_2d(x, z) * _amp[i]
		if _ridge[i] > 0.5:
			var r := 1.0 - absf(ridge.get_noise_2d(x, z))
			h += r * r * _ridge[i]
		var pad: Variant = _pads.get(x + z * size)
		if pad != null:
			h = lerpf(h, (pad as Vector3).x, (pad as Vector3).y)
		_hmap[i] = h


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


func _coarse_sample8(arr: PackedByteArray, x: float, z: float) -> float:
	var fx := clampf(x / COARSE - 0.5, 0.0, _coarse_n - 1.001)
	var fz := clampf(z / COARSE - 0.5, 0.0, _coarse_n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := ix + iz * _coarse_n
	var a := lerpf(arr[i], arr[i + 1], tx)
	var b := lerpf(arr[i + _coarse_n], arr[i + _coarse_n + 1], tx)
	return lerpf(a, b, tz) / 255.0


func biome_at(x: int, z: int) -> int:
	var ix := clampi(x / COARSE, 0, _coarse_n - 1)
	var iz := clampi(z / COARSE, 0, _coarse_n - 1)
	return _biome[ix + iz * _coarse_n]


## Revision 5: land code of the 4 m cell at a column (SurfaceBiomes: land | weight << 3), 0 outside.
func land_code(x: int, z: int) -> int:
	if _land.is_empty():
		return 0
	var ix := clampi(x / COARSE, 0, _coarse_n - 1)
	var iz := clampi(z / COARSE, 0, _coarse_n - 1)
	return _land[ix + iz * _coarse_n]


## Biome byte for the terrain mesher: biome_at(), or SurfaceBiomes.LAND_CODE + land for the
## (dithered) columns of a revision 5 land.
func surface_biome_at(x: int, z: int) -> int:
	var b := biome_at(x, z)
	return land.mesher_biome(self, x, z, b) if land != null else b


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
	if _v3():
		var m := _coarse_sample(_mtn, x, z)
		if m > 0.02:
			h += _couloirs(x, z, m)
		if not _planning:
			var allow := _coarse_sample8(_rav, x, z)
			if allow > 0.01:
				h -= _ravine(x, z, h, allow)
		if not _ocean.is_empty():
			var sk := sea_at(x, z)
			if sk != Sea.NONE:
				h = _seabed(x, z, h, sk)
	return h


## Couloirs and ribs radiating down each massif: gullies that converge towards the summit,
## strongest on the steep middle flanks, faded where two peaks meet (no seams on cols).
func _couloirs(x: int, z: int, m: float) -> float:
	var best := 0.0
	var second := 0.0
	var bp := Vector4.ZERO
	for pk: Vector4 in PEAKS:
		var dx := float(x) - pk.x
		var dz := float(z) - pk.y
		if absf(dx) > pk.w or absf(dz) > pk.w:
			continue
		var d := sqrt(dx * dx + dz * dz) / pk.w
		if d >= 1.0:
			continue
		var f := pk.z * pow(1.0 - d, 1.75)
		if f > best:
			second = best
			best = f
			bp = pk
		elif f > second:
			second = f
	if best <= 0.0:
		return 0.0
	var dx := float(x) - bp.x
	var dz := float(z) - bp.y
	var dist := sqrt(dx * dx + dz * dz)
	var u := dist / bp.w
	var ang := atan2(dz, dx)
	# Around the peak at a fixed circumference: continuous, gullies converge on the summit.
	var c := _n_couloir.get_noise_3d(cos(ang) * 95.0, sin(ang) * 95.0, dist * 0.05)
	# Smooth U-shaped troughs along the zero lines of the noise, rounded ribs between them
	# (no knife edges: the smooth mesher would alias them into teeth).
	var gully := 1.0 - smoothstep(0.0, 0.42, absf(c))
	var rib := smoothstep(0.42, 0.9, absf(c))
	var flank := smoothstep(0.05, 0.25, u) * (1.0 - smoothstep(0.62, 0.9, u))
	var margin := smoothstep(0.0, 0.25, (best - second) / maxf(best, 1.0))
	var w := m * flank * margin * clampf(bp.z / 200.0, 0.4, 1.3)
	return (rib * 2.5 - gully * 7.0) * w


## Ravine depth at a column: narrow winding cracks 25-40 m deep with flat floors.
func _ravine(x: int, z: int, h: float, allow: float) -> float:
	var n := _n_ravine.get_noise_2d(x, z)
	var an := absf(n)
	if an > 0.045:
		return 0.0
	var seg := smoothstep(0.04, 0.3, _n_ravmask.get_noise_2d(x, z))
	if seg <= 0.0:
		return 0.0
	var q := an / 0.045
	var depth := (24.0 + 16.0 * seg) * allow * seg
	var carve := depth * (1.0 - smoothstep(0.28, 1.0, q))
	return clampf(carve, 0.0, maxf(0.0, h - (SEA_LEVEL + 4.0)))


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


## Forest subregions preserve the persisted base-biome IDs and ecology tables.
func forest_region(x: int, z: int) -> int:
	if revision < 2:
		return 0
	if revision >= 3:
		# Organic stands instead of 256 m squares: warp the cells with smooth value noise.
		var wx := x + int((_vnoise(x, z, 97.0, world_seed + 61) - 0.5) * 190.0)
		var wz := z + int((_vnoise(x, z, 97.0, world_seed + 62) - 0.5) * 190.0)
		return _hash3(wx >> 8, 0, wz >> 8, world_seed + 771) % FOREST_NAMES.size()
	return _hash3(x >> 8, 0, z >> 8, world_seed + 771) % FOREST_NAMES.size()


## Climate at a point for the weather (revision 3): x = snowfall 0..1 (cold biomes and above
## their snowline, never over the badlands or mesas), y = dust 0..1, z = high-altitude haze 0..1.
func climate_at(pos: Vector3) -> Vector3:
	var biome := biome_at(int(pos.x), int(pos.z))
	var snow := 0.0
	var dust := 0.0
	match biome:
		Biome.PEAKS:
			snow = 1.0
		Biome.TUNDRA:
			snow = 0.7
		Biome.ALPINE:
			snow = smoothstep(110.0, 160.0, pos.y)
		Biome.FJORD:
			snow = smoothstep(95.0, 140.0, pos.y)
		Biome.WASTES:
			dust = 1.0
		Biome.CANYON:
			dust = 0.12
		Biome.VOLCANIC:
			dust = 0.3
	var haze := clampf((pos.y - 170.0) / 180.0, 0.0, 1.0) if not biome in [Biome.VOLCANIC, Biome.CANYON] else 0.0
	if land != null:
		return land.climate(pos, Vector3(snow, dust, haze))
	return Vector3(snow, dust, haze)


## Ground colour seen from afar (horizon mesh): follows the surface rules, so snow lies only
## above the snowline on slopes that hold it, faces show rock, scree is grey. slope = rise/run.
func horizon_color(x: int, z: int, h: float, slope: float) -> Color:
	if land != null:
		var lc := land.horizon(self, x, z, int(h), slope)
		if lc.a > 0.0:
			return lc
	var biome := biome_at(x, z)
	var top := _surface_v3(x, z, int(h), biome, 0, slope) & 255 if revision >= 3 else -1
	match top:
		FACE:
			match biome:
				Biome.CANYON:
					return Color(0.6, 0.32, 0.2)
				Biome.VOLCANIC:
					return Color(0.18, 0.16, 0.16)
			return Color(0.44, 0.42, 0.41)
		Blocks.SNOW:
			return Color(0.86, 0.88, 0.92)
		Blocks.STONE, Blocks.GRANITE, Blocks.ALPINE_ROCK:
			return Color(0.42, 0.41, 0.4) if top == Blocks.STONE else Color(0.5, 0.49, 0.5)
		Blocks.GRAVEL, Blocks.SCREE:
			return Color(0.5, 0.49, 0.47)
		Blocks.RED_ROCK, Blocks.UMBER_ROCK:
			return Color(0.62, 0.34, 0.22)
		Blocks.RED_SAND:
			return Color(0.74, 0.47, 0.3)
		Blocks.BASALT, Blocks.SCORIA, Blocks.OBSIDIAN:
			return Color(0.2, 0.18, 0.18)
		Blocks.ASH:
			return Color(0.3, 0.28, 0.27)
		Blocks.DRY_GRASS, Blocks.PERMAFROST:
			return Color(0.5, 0.46, 0.34)
		Blocks.SAND:
			return Color(0.72, 0.64, 0.45)
		Blocks.MUD:
			return Color(0.24, 0.22, 0.16)
	if biome == Biome.FOREST:
		return FOREST_COLORS[forest_region(x, z)] * 0.8
	return Color(BIOME_COLORS[biome]) * 0.85


## Water (or ice / lava) surface level of a lake at a column, -INF when there is none.
func lake_level(x: float, z: float) -> Vector2:
	for l: Array in lakes:
		var c: Vector2 = l[0]
		var r: float = l[1]
		if absf(x - c.x) < r and absf(z - c.y) < r and Vector2(x, z).distance_to(c) < r:
			return Vector2(l[2], l[3])
	return Vector2(-INF, 0)


# --- Underground naming (revision 2+) -------------------------------------------

## Whether a point is underground: below the natural surface and not in open air.
func is_underground(pos: Vector3) -> bool:
	if dimension != Dimension.OVERWORLD:
		return false
	if revision >= 5 and AdventureTerrain.sheltered(pos):
		return true
	return pos.y < ground_level(pos.x, pos.z) - 5.0


## The name of the cave system at a point, or "" when it is not underground. Mines and other
## underground locations are named by their Location; this names the natural caves (so the HUD
## never reports the village above a cave).
func cave_name_at(pos: Vector3) -> String:
	if not is_underground(pos):
		return ""
	if revision < 2 or pos.y >= -8.0:
		var depth := ground_level(pos.x, pos.z) - pos.y
		return "Shallow Caves" if depth < 25.0 else "Caverns"
	if revision >= 5:
		var zone := CaveBiomes.zone_at(pos)
		if not zone.is_empty():
			return String(zone[2])
	var kind := CaveBiomes.kind_at(pos, world_seed, revision)
	if kind != CaveBiomes.Kind.KARST:
		return CaveBiomes.NAMES[kind]
	if pos.y < -90.0:
		return "The Abyss"
	if pos.y < -40.0:
		return "The Deep"
	return CaveBiomes.NAMES[kind]


## Cave biome at a point (CaveBiomes.Kind), or -1 above ground.
func cave_biome_at(x: int, y: int, z: int) -> int:
	var p := Vector3(x, y, z)
	if not is_underground(p) or y >= -8:
		return -1
	return CaveBiomes.kind_at(p, world_seed, revision)


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
	if revision >= 3:
		_add_road_v3(points, width, BANK, detail, ridge)
		return
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var steps := int(a.distance_to(b))
		for s in steps + 1:
			var p := a.lerp(b, float(s) / maxf(1.0, steps))
			# Villages own their streets: a road stops at the village edge.
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


## Revision 3 roads: a cross-section of cells per half metre of road instead of a full square
## per metre (the same surface, a tenth of the work), with the height smoothed along the route.
func _add_road_v3(points: PackedVector2Array, width: float, bank: float, detail: FastNoiseLite, ridge: FastNoiseLite) -> void:
	var villages: Array[Location] = []
	for loc: Location in locations:
		if loc.kind == Location.Kind.VILLAGE:
			villages.append(loc)
	# Sample the route every 2 m, then smooth the heights over ~16 m.
	var pts := PackedVector2Array()
	var dirs := PackedVector2Array()
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var steps := maxi(1, int(a.distance_to(b) / 2.0))
		var dir := (b - a).normalized()
		for s in steps:
			pts.append(a.lerp(b, float(s) / steps))
			dirs.append(dir)
	if pts.is_empty():
		return
	var heights := PackedFloat32Array()
	heights.resize(pts.size())
	for i in pts.size():
		heights[i] = raw_height(int(pts[i].x), int(pts[i].y), detail, ridge)
	var smooth := PackedFloat32Array()
	smooth.resize(pts.size())
	for i in pts.size():
		var sum := 0.0
		var cnt := 0
		for k in range(maxi(0, i - 4), mini(pts.size(), i + 5)):
			sum += heights[k]
			cnt += 1
		smooth[i] = maxf(sum / cnt + 0.15, SEA_LEVEL + 1.0)
	var reach := width + bank
	for i in pts.size():
		var p := pts[i]
		var in_village := false
		for loc in villages:
			if p.distance_to(Vector2(loc.center.x, loc.center.z)) < loc.radius + reach:
				in_village = true
				break
		if in_village:
			continue
		var side := dirs[i].orthogonal()
		var road_h := smooth[i]
		for s in range(-int(reach * 1.4), int(reach * 1.4) + 1):
			for along: float in [0.0, 1.0]:
				var q := p + side * (s * 0.7) + dirs[i] * along
				var x := int(q.x)
				var z := int(q.y)
				if not in_bounds(x, z):
					continue
				var d := absf(s * 0.7)
				var key := x + z * size
				var existing: Variant = _pads.get(key)
				if d <= width:
					if existing == null or (existing as Vector3).y < 0.999 or (existing as Vector3).z > 0.0:
						_pads[key] = Vector3(road_h, 1.0, 1.0)
				else:
					var w := 1.0 - smoothstep(width, reach, d)
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
	var roads := _roads if not _roads.is_empty() else LocationPlanner.roads(self)
	for road: PackedVector2Array in roads:
		add_road(road, 2.0)


## Blueprints per chunk column, so chunk generation only checks the few that can touch it.
func _index_blueprints() -> void:
	_bp_index.clear()
	for bp in _blueprints:
		for cz in range(floori(bp.origin.z / 16.0), floori((bp.origin.z + bp.size.z - 1) / 16.0) + 1):
			for cx in range(floori(bp.origin.x / 16.0), floori((bp.origin.x + bp.size.x - 1) / 16.0) + 1):
				var k := Vector2i(cx, cz)
				if not _bp_index.has(k):
					_bp_index[k] = []
				(_bp_index[k] as Array).append(bp)


func _blueprints_for(key: Vector3i) -> Array:
	if _bp_index.is_empty() and not _blueprints.is_empty():
		var all: Array = []
		for bp in _blueprints:
			if bp.intersects_chunk(key):
				all.append(bp)
		return all
	var out: Array = []
	for bp: Blueprint in _bp_index.get(Vector2i(key.x, key.z), []):
		if bp.intersects_chunk(key):
			out.append(bp)
	return out


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
	if revision >= 3:
		return _generate_overworld_v3(key)
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

	var touches_structure := not _blueprints_for(key).is_empty()

	var top := maxi(max_h, SEA_LEVEL) + 16  # trees reach above the ground
	if o.y > top and not touches_structure:
		return [data, PackedByteArray()]

	var caves := o.y < max_h - 3
	var chamber := CaveBiomes.region(Vector3(o) + Vector3(8, 8, 8), world_seed, revision)
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
	return _ore_kind(y, t)


## Revision 5 ore: each 8 m cell may hold one small vein, a short ragged capsule
## (2-6 blocks long, ~1 block thick) of a single ore picked by the cell's depth.
## Only the voxel's own cell is tested (a vein reaching past its cell is clipped).
func _vein_ore(x: int, y: int, z: int) -> int:
	var cx := x >> VEIN_SHIFT
	var cy := y >> VEIN_SHIFT
	var cz := z >> VEIN_SHIFT
	var s := world_seed * 31
	# Every cell parameter comes from bit fields of three hashes (this runs per rock voxel).
	var h1 := _hash3(cx, cy, cz, s + 401)
	if float(h1 & 255) >= VEIN_CHANCE * 256.0:
		return Blocks.AIR
	var cell := float(1 << VEIN_SHIFT)
	var a := Vector3(cx * cell + 2.5 + float((h1 >> 8) & 127) / 127.0 * 3.0,
			cy * cell + 2.5 + float((h1 >> 15) & 127) / 127.0 * 3.0,
			cz * cell + 2.5 + float((h1 >> 22) & 127) / 127.0 * 3.0)
	var p := Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5)
	if p.distance_squared_to(a) > 20.0:  # beyond the longest vein's reach (3 + 1.3 m)
		return Blocks.AIR
	var h2 := _hash3(cx, cy, cz, s + 402)
	var dir := Vector3(float(h2 & 127) / 127.0 - 0.5, (float((h2 >> 7) & 127) / 127.0 - 0.5) * 0.6,
			float((h2 >> 14) & 127) / 127.0 - 0.5)
	if dir.length_squared() < 0.0001:
		dir = Vector3.RIGHT
	dir = dir.normalized()
	var b := a + dir * (1.0 + float((h2 >> 21) & 31) / 31.0 * 2.0)
	a -= dir * (0.5 + float((h2 >> 26) & 31) / 31.0)
	var h3 := _hash3(cx, cy, cz, s + 403)
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var r := 0.75 + float(h3 & 255) / 255.0 * 0.55
	if p.distance_squared_to(a + ab * t) > r * r:
		return Blocks.AIR
	# Ragged edges: a few blocks of the capsule stay plain rock.
	if _hash01(x, y, z, s + 411) < 0.2:
		return Blocks.AIR
	return _ore_kind(cy * (1 << VEIN_SHIFT) + 4, float((h3 >> 8) & 0xffff) / 65535.0)


## Which ore a deposit at depth y holds (t: 0..1 roll).
static func _ore_kind(y: int, t: float) -> int:
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


# --- Revision 3 chunk generation ---------------------------------------------------------------

## Rock groups for the deep strata of a column.
enum Rock { PLAIN, MOUNTAIN, WASTES, MARSH, OCEAN, MESA, VOLCANIC, TUNDRA, REDWOOD, DUNE }


## Per chunk column (cached): heights, surface/subsurface blocks, rock group, biome, slope,
## road flag and the lake surface. Arrays of 256 in x + z*16 order.
func _columns_v3(cx: int, cz: int) -> Array:
	var key := (cx + 32768) * 65536 + (cz + 32768)
	_col_mutex.lock()
	var hit: Variant = _col_cache.get(key)
	_col_mutex.unlock()
	if hit != null:
		return hit
	var o := Vector2i(cx * 16, cz * 16)
	# Heights with a two-column border for (smoothed) slopes.
	var hb := PackedFloat32Array()
	hb.resize(20 * 20)
	var roads := PackedByteArray()
	roads.resize(256)
	for z in 20:
		for x in 20:
			var wx := o.x + x - 2
			var wz := o.y + z - 2
			var c := column_f(wx, wz, _n_detail, _n_ridge) if in_bounds(wx, wz) else Vector2(-20, 0)
			hb[x + z * 20] = c.x
			if x > 1 and z > 1 and x < 18 and z < 18:
				roads[(x - 2) + (z - 2) * 16] = int(c.y)
	var hf := PackedFloat32Array()
	hf.resize(256)
	var hi := PackedInt32Array()
	hi.resize(256)
	var top := PackedByteArray()
	top.resize(256)
	var sub := PackedByteArray()
	sub.resize(256)
	var rock := PackedByteArray()
	rock.resize(256)
	var biomes := PackedByteArray()
	biomes.resize(256)
	var slope := PackedFloat32Array()
	slope.resize(256)
	var water := PackedFloat32Array()
	water.resize(256)
	var wblock := PackedByteArray()
	wblock.resize(256)
	var max_h := -100000
	var min_h := 100000
	var max_w := -100000.0
	for z in 16:
		for x in 16:
			var i := x + z * 16
			var bi := (x + 2) + (z + 2) * 20
			var h := hb[bi]
			hf[i] = h
			var hh := int(floorf(h + 0.5))
			hi[i] = hh
			max_h = maxi(max_h, hh)
			min_h = mini(min_h, hh)
			var wx := o.x + x
			var wz := o.y + z
			# Slope over 4 m: steady enough that materials don't flicker column to column.
			var s := Vector2(hb[bi + 2] - hb[bi - 2], hb[bi + 40] - hb[bi - 40]).length() * 0.25
			slope[i] = s
			var biome := biome_at(wx, wz)
			biomes[i] = biome
			var surf := _surface_v3(wx, wz, hh, biome, roads[i], s)
			rock[i] = _rock_group(biome)
			if land != null and _land[clampi(wx / COARSE, 0, _coarse_n - 1) + clampi(wz / COARSE, 0, _coarse_n - 1) * _coarse_n] != 0:
				surf = land.surface(self, wx, wz, hh, roads[i], s, surf)
				rock[i] = land.rock_group(land.pick(self, wx, wz), rock[i])
			top[i] = surf & 255
			sub[i] = surf >> 8
			var lv := lake_level(wx, wz)
			water[i] = lv.x if lv.x > -INF else -100000.0
			wblock[i] = int(lv.y)
			max_w = maxf(max_w, water[i])
	var result := [hf, hi, top, sub, rock, biomes, slope, roads, water, wblock, max_h, min_h, max_w]
	if not _ocean.is_empty():
		# Revision 4: ice floes on the Rime Sea.
		var floe := PackedFloat32Array()
		floe.resize(256)
		for i in 256:
			if biomes[i] == Biome.OCEAN:
				floe[i] = _floe(o.x + (i & 15), o.y + (i >> 4), hi[i])
		result.append(floe)
	_col_mutex.lock()
	var slot := _col_next % COLUMN_CACHE
	var old := _col_ring[slot]
	if old >= 0:
		_col_cache.erase(old)
	_col_ring[slot] = key
	_col_next += 1
	_col_cache[key] = result
	_col_mutex.unlock()
	return result


static func _rock_group(biome: int) -> int:
	match biome:
		Biome.PEAKS, Biome.ALPINE, Biome.FJORD:
			return Rock.MOUNTAIN
		Biome.WASTES:
			return Rock.WASTES
		Biome.MARSH:
			return Rock.MARSH
		Biome.OCEAN:
			return Rock.OCEAN
		Biome.CANYON:
			return Rock.MESA
		Biome.VOLCANIC:
			return Rock.VOLCANIC
		Biome.TUNDRA:
			return Rock.TUNDRA
		Biome.REDWOOD:
			return Rock.REDWOOD
	return Rock.PLAIN


## Marks a steep column whose surface shows the bedrock of that height (rock faces read as one
## continuous rock, not as stacked bands of soil, subsoil and rock).
const FACE := 255


## Surface block (low byte) and the block for the next three metres (high byte) of a column.
func _surface_v3(x: int, z: int, h: int, biome: int, road: int, s: float) -> int:
	if road == 1:
		return (Blocks.GRAVEL if _vnoise(x, z, 5.0, 7) > 0.22 else Blocks.DIRT) | (Blocks.DIRT << 8)
	var beach := h <= SEA_LEVEL + 1 and h >= SEA_LEVEL - 3
	var n := _vnoise(x, z, 9.0, 9)
	var steep := s > 1.05
	if s > 0.95 + (_vnoise(x, z, 6.0, 41) - 0.5) * 0.3 and biome != Biome.MARSH and not beach:
		return FACE | (FACE << 8)
	if biome == Biome.OCEAN and revision >= 4 and h < SEA_LEVEL - 2:
		return _sea_floor(x, z, h, n)
	match biome:
		Biome.PLAINS:
			if beach:
				return Blocks.SAND | (Blocks.SAND << 8)
			if steep:
				return Blocks.STONE | (Blocks.STONE << 8)
			return (Blocks.DRY_GRASS if n < 0.3 else Blocks.GRASS) | (Blocks.DIRT << 8)
		Biome.FOREST:
			if beach:
				return Blocks.SAND | (Blocks.SAND << 8)
			if steep:
				return Blocks.STONE | (Blocks.DIRT << 8)
			return Blocks.GRASS | (Blocks.DIRT << 8)
		Biome.REDWOOD:
			if beach:
				return Blocks.GRAVEL | (Blocks.SAND << 8)
			if steep:
				return (Blocks.STONE if n < 0.6 else Blocks.GRANITE) | (Blocks.DIRT << 8)
			# Fern-covered duff with mossy grass in the clearings.
			return (Blocks.DIRT if _vnoise(x, z, 6.0, 31) < 0.55 else Blocks.GRASS) | (Blocks.DIRT << 8)
		Biome.PEAKS, Biome.ALPINE, Biome.FJORD:
			var snowline := 92.0 if biome == Biome.PEAKS else (150.0 if biome == Biome.ALPINE else 128.0)
			snowline += (_vnoise(x, z, 23.0, 33) - 0.5) * 26.0
			if beach:
				return Blocks.GRAVEL | (Blocks.GRAVEL << 8)
			if s > 1.25:
				return Blocks.ALPINE_ROCK | (Blocks.ALPINE_ROCK << 8)
			if h > snowline and s < 0.6:
				return Blocks.SNOW | ((Blocks.SNOW if h > snowline + 12 else Blocks.STONE) << 8)
			if h > snowline:
				# Too steep to hold a snowfield: wind-scoured rock (the weather still dusts it).
				return (Blocks.ALPINE_ROCK if n < 0.65 else Blocks.SCREE) | (Blocks.ALPINE_ROCK << 8)
			if s > 0.6 and h > snowline - 80.0:
				# Scree fans and rock steps below the faces.
				return (Blocks.SCREE if n < 0.6 else Blocks.ALPINE_ROCK) | (Blocks.ALPINE_ROCK << 8)
			if h > snowline - 18.0:
				# Fell-field: bare rock and scree between patches of alpine turf.
				return (Blocks.ALPINE_ROCK if n < 0.4 else (Blocks.SCREE if n < 0.6 else Blocks.GRASS)) | (Blocks.ALPINE_ROCK << 8)
			if s > 0.55:
				return (Blocks.ALPINE_ROCK if n < 0.5 else Blocks.SCREE) | (Blocks.ALPINE_ROCK << 8)
			return Blocks.GRASS | (Blocks.DIRT << 8)
		Biome.CANYON:
			if steep:
				return Blocks.RED_ROCK | (Blocks.RED_ROCK << 8)
			if beach:
				return Blocks.RED_SAND | (Blocks.RED_SAND << 8)
			var m := _vnoise(x, z, 14.0, 35)
			if m > 0.78:
				return Blocks.DRY_GRASS | (Blocks.RED_SAND << 8)
			return (Blocks.RED_SAND if m > 0.18 else Blocks.UMBER_ROCK) | (Blocks.RED_SAND << 8)
		Biome.TUNDRA:
			if beach:
				return Blocks.GRAVEL | (Blocks.GRAVEL << 8)
			var m := _vnoise(x, z, 17.0, 36)
			if m > 0.64 or h > 70:
				return Blocks.SNOW | (Blocks.PERMAFROST << 8)
			if m < 0.18 or steep:
				return Blocks.GRAVEL | (Blocks.PERMAFROST << 8)
			return (Blocks.PERMAFROST if n < 0.32 else Blocks.DRY_GRASS) | (Blocks.PERMAFROST << 8)
		Biome.VOLCANIC:
			if steep:
				return Blocks.BASALT | (Blocks.BASALT << 8)
			if beach:
				return Blocks.ASH | (Blocks.BASALT << 8)
			var m := _vnoise(x, z, 12.0, 37)
			if m > 0.72:
				return Blocks.SCORIA | (Blocks.SCORIA << 8)
			if m < 0.12:
				return Blocks.OBSIDIAN | (Blocks.BASALT << 8)
			return (Blocks.ASH if n < 0.62 else Blocks.BASALT) | (Blocks.ASH << 8)
		Biome.MARSH:
			if h <= SEA_LEVEL:
				return Blocks.MUD | (Blocks.MUD << 8)
			return Blocks.GRASS | (Blocks.MUD << 8)
		Biome.WASTES:
			if beach:
				return Blocks.SAND | (Blocks.SAND << 8)
			var r := _vnoise(x, z, 13.0, 3)
			return (Blocks.SAND if r < 0.2 else (Blocks.BASALT if r > 0.8 else Blocks.ASH)) | (Blocks.ASH << 8)
	return Blocks.SAND | (Blocks.SANDSTONE << 8)


## Deep rock (and ore) at a voxel: depth >= 4 below the column top.
func _rock_v3(x: int, y: int, z: int, depth: int, group: int, st: int, o1: int, o2: int) -> int:
	if y <= Y_MIN + 2:
		if y <= Y_MIN + 1 + (_hash3(x, 0, z, 5) & 1):
			return Blocks.BEDROCK
	if revision >= 5:
		# Revision 5: small scattered veins instead of large lenses.
		var vein := _vein_ore(x, y, z)
		if vein != Blocks.AIR:
			return vein
	# Ore veins: thin sheets inside irregular lenses, and rounder pockets.
	var sheet := revision < 5 and absi(o1 - 128) < 12 and o2 > 155
	if sheet or (revision < 5 and o2 > 220):
		var ore := _ore_kind(y, _hash01(x >> 3, y >> 3, z >> 3, 79))
		if ore != Blocks.AIR:
			return ore
	var band := posmod(floori((float(y) + float(st) * 0.09) / 7.0), 4)
	var pocket := st > 178
	if y < -95:
		return Blocks.BASALT if band < 2 or pocket else Blocks.DEEPSLATE
	if y < -40:
		if pocket:
			return Blocks.AMETHYST if st > 236 and y < -45 else Blocks.SLATE
		return Blocks.SLATE if band == 3 else Blocks.DEEPSLATE
	match group:
		Rock.MOUNTAIN:
			# Mostly grey gneiss-like stone with darker beds and the odd granite or marble body.
			if pocket:
				return Blocks.MARBLE if st > 205 else Blocks.GRANITE
			return Blocks.SLATE if band == 1 and st < 110 else Blocks.ALPINE_ROCK
		Rock.WASTES:
			if depth < 14:
				return Blocks.SANDSTONE if band < 2 else Blocks.BASALT
			return Blocks.BASALT if pocket else Blocks.STONE
		Rock.MARSH:
			if depth < 9:
				return Blocks.CLAY if band != 1 else Blocks.MUD
			return Blocks.SLATE if pocket else Blocks.STONE
		Rock.OCEAN:
			return Blocks.SANDSTONE if depth < 10 else (Blocks.LIMESTONE if pocket else Blocks.STONE)
		Rock.MESA:
			if y > 6:
				# The banded walls of the mesas: thin horizontal beds of red, umber, cream and clay.
				var bed := posmod(floori((float(y) + float(st) * 0.025) / 2.7), 9)
				return [Blocks.RED_ROCK, Blocks.RED_ROCK, Blocks.UMBER_ROCK, Blocks.SANDSTONE, Blocks.RED_ROCK,
						Blocks.CLAY, Blocks.RED_ROCK, Blocks.UMBER_ROCK, Blocks.SANDSTONE][bed]
			return Blocks.SANDSTONE if band < 2 else Blocks.STONE
		Rock.VOLCANIC:
			if depth < 26:
				return Blocks.SCORIA if band == 1 else (Blocks.OBSIDIAN if pocket and st > 210 else Blocks.BASALT)
			return Blocks.BASALT if band < 2 else Blocks.STONE
		Rock.TUNDRA:
			if depth < 8:
				return Blocks.PERMAFROST if band != 2 else Blocks.GRAVEL
			return Blocks.SLATE if band < 2 else Blocks.STONE
		Rock.REDWOOD:
			if pocket:
				return Blocks.GRANITE
			return Blocks.LIMESTONE if band == 2 else Blocks.STONE
		Rock.DUNE:
			return SurfaceBiomes.dune_rock(y, st, band, pocket)
	if pocket:
		return Blocks.GRANITE if band < 2 else Blocks.LIMESTONE
	return Blocks.LIMESTONE if band == 2 else Blocks.STONE


func _generate_overworld_v3(key: Vector3i) -> Array:
	var data := Chunk.empty()
	var dens := Chunk.empty()
	var o := key * Chunk.SIZE
	if o.y > Y_MAX or o.y + Chunk.SIZE <= Y_MIN:
		return [data, PackedByteArray()]
	var cols := _columns_v3(key.x, key.z)
	var hf: PackedFloat32Array = cols[0]
	var heights: PackedInt32Array = cols[1]
	var tops: PackedByteArray = cols[2]
	var subs: PackedByteArray = cols[3]
	var rocks: PackedByteArray = cols[4]
	var biomes: PackedByteArray = cols[5]
	var water: PackedFloat32Array = cols[8]
	var wblock: PackedByteArray = cols[9]
	var max_h: int = cols[10]
	var min_h: int = cols[11]
	var max_w: float = cols[12]
	var floe: PackedFloat32Array = cols[13] if cols.size() > 13 else PackedFloat32Array()

	var bps := _blueprints_for(key)
	var carvers := caves.chunk_carvers(key) if caves != null else PackedInt32Array()
	var top := maxi(maxi(max_h, SEA_LEVEL), int(max_w) + 1) + 24  # trees reach above the ground
	if o.y > top and bps.is_empty() and carvers.is_empty():
		return [data, PackedByteArray()]

	var underground := o.y < max_h - 2
	var chamber := CaveBiomes.region(Vector3(o) + Vector3(8, 8, 8), world_seed, revision)
	var kind := int(chamber["kind"])
	var cc: Vector3 = chamber["center"]
	var cr := CaveBiomes.radii_of(chamber)
	var has_chamber := o.y < -8 and absf(o.x + 8 - cc.x) < cr.x * 1.25 + 8 and absf(o.y + 8 - cc.y) < cr.y * 1.25 + 8 and absf(o.z + 8 - cc.z) < cr.z * 1.25 + 8
	var pool := CaveBiomes.pool_level(chamber)
	var pool_block := Blocks.LAVA if kind == CaveBiomes.Kind.MAGMA else Blocks.WATER
	var t1 := PackedByteArray()
	var t2 := PackedByteArray()
	var cav := PackedByteArray()
	var strata := PackedByteArray()
	var o1 := PackedByteArray()
	var o2 := PackedByteArray()
	if underground or not carvers.is_empty():
		t1 = _noise_block(o, 0.024, 1, 31)
	if underground:
		t2 = _noise_block(o, 0.024, 1, 32)
		strata = _noise_block(o, 0.035, 2, 34)
		o1 = _noise_block(o, 0.07, 1, 35)
		o2 = _noise_block(o, 0.045, 2, 36)
		if o.y < -12:
			cav = _noise_block(o, 0.012, 2, 33)
	var arches: Array = land.arches_in(o) if land != null else []
	var carve := PackedFloat32Array()
	var owner := PackedInt32Array()
	if not carvers.is_empty():
		carve.resize(Chunk.VOLUME)
		carve.fill(INF)
		owner.resize(Chunk.VOLUME)
		owner.fill(-1)
		caves.carve_chunk(o, carvers, t1, carve, owner)

	for y in Chunk.SIZE:
		var wy := o.y + y
		var fy := float(wy)
		for z in Chunk.SIZE:
			for x in Chunk.SIZE:
				var ci := x + z * Chunk.SIZE
				var h := heights[ci]
				var d := 0.5 + (hf[ci] + 0.5 - fy) * 0.5
				var arch_d := -1.0
				if not arches.is_empty():
					arch_d = land.arch_density(arches, o.x + x, wy, o.z + z)
					d = maxf(d, arch_d)
				var ni := x + y * Chunk.SIZE + z * Chunk.AREA
				var di := x + z * Chunk.SIZE + y * Chunk.AREA
				# Flood guards: no noise tunnel breaches a lake or a flooded/magma chamber.
				var guard := false
				var cid := -1
				var csd := INF
				if not carve.is_empty():
					csd = carve[di]
					cid = owner[di]
					if cid >= 0 and csd < 4.0 and fy <= caves.field(cid, CaveNetwork.F_WATER) + 1.0:
						guard = true
				var chamber_distance := 100.0
				if has_chamber and wy > Y_MIN + 4 and wy < h - 8:
					var q := (Vector3(o.x + x, wy, o.z + z) - cc) / cr
					chamber_distance = q.length() + (float(t1[ni]) - 127.5) * 0.0007 if not t1.is_empty() else q.length()
					if pool > -INF and chamber_distance < 1.45 and fy <= pool + 1.0:
						guard = true
				if underground and not guard and wy < h - 2 and wy > Y_MIN + 3:
					# Noise bytes map [-1, 1] to [0, 255]; 127.5 is zero.
					var depth_factor := clampf(float(h - wy) / 40.0, 0.0, 1.0)
					var tw := 9.0 + 6.0 * depth_factor
					var m := maxf(absf(t1[ni] - 127.5), absf(t2[ni] - 127.5)) - tw
					# Tunnels pinch shut just below the surface instead of ending in a flat roof.
					var dc := 0.5 + m / 24.0 + maxf(0.0, float(wy - h + 7)) * 0.12
					if wy < -12 and not cav.is_empty():
						dc = minf(dc, 0.5 + ((198.0 - depth_factor * 19.0) - float(cav[ni])) / 30.0)
					d = minf(d, dc)
				var in_chamber := false
				if chamber_distance < 2.0:
					# A chamber with a flat floor (walkable) and lumpy walls.
					var q := (Vector3(o.x + x, wy, o.z + z) - cc) / cr
					var dch := maxf((chamber_distance - 1.0) * 10.0, (-0.62 - q.y) * cr.y * 0.5)
					if 0.5 + dch < d:
						d = 0.5 + dch
						in_chamber = true
				if csd < INF:
					d = minf(d, 0.5 + csd * 0.5)
				var solid := d >= 0.5
				var b := Blocks.AIR
				if solid:
					var depth := h - wy
					if depth <= 0 and tops[ci] != FACE:
						b = tops[ci]
					elif depth < 4 and subs[ci] != FACE:
						b = subs[ci]
					else:
						b = _rock_v3(o.x + x, wy, o.z + z, depth, rocks[ci], int(strata[ni]) if not strata.is_empty() else 128,
								int(o1[ni]) if not o1.is_empty() else 128, int(o2[ni]) if not o2.is_empty() else 128)
					if arch_d >= 0.5 and wy > h:
						b = SurfaceBiomes.arch_block(wy)
					if b != Blocks.BEDROCK:
						if chamber_distance < 1.13:
							b = CaveBiomes.wall_material(o + Vector3i(x, y, z), kind, world_seed, q_floor(chamber_distance, wy, cc, cr))
						elif cid >= 0 and csd < CaveNetwork.SHELL:
							b = _carver_shell(cid, csd, b, o.x + x, wy, o.z + z, int(o2[ni]) if not o2.is_empty() else 128)
				elif wy <= h or csd < 0.0:
					# Carved by a cave: chamber pools, flooded passages, the magma deep.
					b = Blocks.AIR
					if cid >= 0 and csd < 0.0 and fy <= caves.field(cid, CaveNetwork.F_WATER):
						b = int(caves.field(cid, CaveNetwork.F_FILL))
					elif pool > -INF and chamber_distance < 1.45 and fy <= pool:
						b = pool_block
					elif wy < -112:
						b = Blocks.LAVA
					elif wy > h and wy <= SEA_LEVEL:
						b = Blocks.WATER
				elif wy <= SEA_LEVEL:
					b = Blocks.WATER
					if wy == SEA_LEVEL and not floe.is_empty() and floe[ci] > 0.0:
						b = Blocks.ICE
						d = 0.5 + floe[ci]
				elif fy <= water[ci]:
					b = wblock[ci]
					if b == Blocks.ICE and fy < water[ci] - 1.0:
						b = Blocks.WATER
				if b != Blocks.AIR:
					data[di] = b
				dens[di] = _dbyte(d, solid or b == Blocks.ICE)

	if o.y <= max_h + 24 and o.y + Chunk.SIZE > min_h - 1:
		_place_trees_v3(data, dens, o, cols)
	_stamp_blueprint_list(data, dens, key, bps)
	return [data, dens]


## 0 wall, 1 floor of a chamber (for floor materials).
static func q_floor(chamber_distance: float, wy: int, cc: Vector3, cr: Vector3) -> int:
	return 1 if float(wy) < cc.y - cr.y * 0.5 else 0


## Material next to a carved feature: ore seams in mine stopes, gravel mine floors.
func _carver_shell(cid: int, csd: float, b: int, x: int, y: int, z: int, o2: int) -> int:
	var scheme := int(caves.field(cid, CaveNetwork.F_SCHEME))
	if scheme > 0:
		return UndergroundPlan.shell_block(caves, cid, scheme, b, x, y, z, world_seed)
	var floor_block := int(caves.field(cid, CaveNetwork.F_FLOOR))
	if floor_block > 0 and csd < 1.3:
		var t := int(caves.field(cid, CaveNetwork.F_TYPE))
		if t == CaveNetwork.Type.DRIFT or t == CaveNetwork.Type.ROOM:
			var floor_y := caves.field(cid, CaveNetwork.F_AY)
			if t == CaveNetwork.Type.DRIFT:
				floor_y = minf(floor_y, caves.field(cid, CaveNetwork.F_BY))
			if float(y) < floor_y + 0.2:
				return floor_block
	var ore := int(caves.field(cid, CaveNetwork.F_ORE))
	if ore > 0 and csd < 1.9:
		var chance := caves.field(cid, CaveNetwork.F_ORE_CHANCE)
		if float(o2) / 255.0 > 1.0 - chance * 0.9 or _hash01(x >> 1, y >> 1, z >> 1, 91) < chance * 0.35:
			return ore
	return b


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
		Blocks.REDWOOD_TRUNK:
			# Old-growth giants: the tallest trees Flora grows.
			kind = 2
			height = 16.5 + float(hsh & 7) * 0.5
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
			# Never in water: the sea (marsh pools included) floods every column at or below SEA_LEVEL.
			if ground <= SEA_LEVEL:
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
				Biome.FOREST:
					var region := forest_region(rx, rz)
					trunk = [Blocks.OAK_TRUNK, Blocks.PINE_TRUNK, Blocks.CRIMSON_TRUNK, Blocks.OAK_TRUNK][region]
					trunk_h = [4, 6, 4, 6][region]
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


## Revision 3 trees: per-biome species and density, none on cliffs, above the treeline,
## in lakes or across roads.
func _place_trees_v3(data: PackedByteArray, dens: PackedByteArray, o: Vector3i, cols: Array) -> void:
	var heights: PackedInt32Array = cols[1]
	var tops: PackedByteArray = cols[2]
	var biomes: PackedByteArray = cols[5]
	var slopes: PackedFloat32Array = cols[6]
	var roads: PackedByteArray = cols[7]
	var water: PackedFloat32Array = cols[8]
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
			var ci := (rx - o.x) + (rz - o.z) * 16
			var biome := biomes[ci]
			var ground := heights[ci]
			var slope := slopes[ci]
			var chance := 0.0
			var trunk := Blocks.OAK_TRUNK
			var trunk_h := 4
			var roll := float((hsh >> 4) & 0xff) / 255.0
			match biome:
				Biome.FOREST:
					var region := forest_region(rx, rz)
					chance = [0.62, 0.52, 0.42, 0.72][region]
					trunk = [Blocks.OAK_TRUNK, Blocks.PINE_TRUNK, Blocks.CRIMSON_TRUNK, Blocks.OAK_TRUNK][region]
					trunk_h = [4, 6, 4, 6][region]
					if hsh % (7 if region == 3 else 19) == 0:
						trunk = Blocks.IRONWOOD_TRUNK
				Biome.PLAINS:
					chance = 0.05
					trunk = Blocks.OAK_TRUNK if (hsh >> 15) & 1 == 0 else Blocks.CRIMSON_TRUNK
				Biome.PEAKS:
					chance = 0.32 if ground < 84 else 0.0
					trunk = Blocks.PINE_TRUNK
					trunk_h = 5
				Biome.MARSH:
					chance = 0.16
					trunk = Blocks.CRIMSON_TRUNK if (hsh >> 14) & 1 == 0 else Blocks.DEAD_TRUNK
				Biome.WASTES:
					chance = 0.015
					trunk = Blocks.EMBERWOOD_TRUNK if hsh % 3 == 0 else Blocks.DEAD_TRUNK
					trunk_h = 3
				Biome.REDWOOD:
					chance = 0.4
					trunk = Blocks.REDWOOD_TRUNK
					trunk_h = 7
					if roll < 0.08:
						trunk = Blocks.OAK_TRUNK
						trunk_h = 4
					elif hsh % 23 == 0:
						trunk = Blocks.IRONWOOD_TRUNK
						trunk_h = 6
				Biome.ALPINE:
					chance = 0.36 if ground < 118 else (0.12 if ground < 132 else 0.0)
					trunk = Blocks.PINE_TRUNK
					trunk_h = 5
				Biome.FJORD:
					chance = 0.3 if ground < 104 else 0.0
					trunk = Blocks.PINE_TRUNK
					trunk_h = 5
				Biome.TUNDRA:
					chance = 0.035
					trunk = Blocks.PINE_TRUNK if (hsh >> 13) & 3 != 0 else Blocks.DEAD_TRUNK
					trunk_h = 3
				Biome.CANYON:
					chance = 0.018
					trunk = Blocks.EMBERWOOD_TRUNK if hsh % 5 == 0 else Blocks.DEAD_TRUNK
					trunk_h = 3
				Biome.VOLCANIC:
					chance = 0.022
					trunk = Blocks.EMBERWOOD_TRUNK if hsh % 4 == 0 else Blocks.DEAD_TRUNK
					trunk_h = 3
				Biome.RYFT:
					chance = 0.18
					trunk = Blocks.RYFTWOOD_TRUNK
			if land != null and _land[clampi(rx / COARSE, 0, _coarse_n - 1) + clampi(rz / COARSE, 0, _coarse_n - 1) * _coarse_n] != 0:
				var tv := land.tree(self, rx, rz, chance, trunk, trunk_h, hsh)
				chance = tv.x
				trunk = int(tv.y)
				trunk_h = int(tv.z)
			if roll >= chance or slope > 0.85 or roads[ci] == 1:
				continue
			if _pads.has(rx + rz * size):
				continue
			if ground + 8 < o.y or ground + 1 >= o.y + Chunk.SIZE:
				continue
			# Never in water: the sea (marsh pools included) floods every column at or below
			# SEA_LEVEL, lakes up to their level, and neither may reach the root cell.
			if ground <= SEA_LEVEL or water[ci] > float(ground) - 0.5:
				continue
			if tops[ci] == Blocks.SNOW and biome != Biome.TUNDRA:
				continue
			if _flooded_near(rx, ground + 1, rz):
				continue
			var root := Vector3i(rx, ground + 1, rz)
			var lx := rx - o.x
			var lz := rz - o.z
			# The ground under the root must still be there (not a cave mouth or a ravine lip).
			var gy := ground - o.y
			if gy >= 0 and gy < Chunk.SIZE and data[lx + lz * Chunk.SIZE + gy * Chunk.AREA] == Blocks.AIR:
				continue
			for i in trunk_h:
				var ly := root.y + i - o.y
				if ly < 0 or ly >= Chunk.SIZE:
					continue
				var di := lx + lz * Chunk.SIZE + ly * Chunk.AREA
				if data[di] == Blocks.AIR or data[di] == Blocks.WATER:
					data[di] = trunk
					dens[di] = mini(dens[di], 127)


## True when a cave carver floods (or carves away) the ground at a tree root: decided from the
## column alone, so every chunk a trunk spans agrees (no floating trunk halves).
func _flooded_near(x: int, root_y: int, z: int) -> bool:
	if caves == null:
		return false
	var p := Vector3(x + 0.5, root_y - 0.5, z + 0.5)
	for i in caves.chunk_carvers(Vector3i(x >> 4, floori(p.y / 16.0), z >> 4)):
		var d := caves._sdf(i, p, 0.0)
		if d < 2.5 and caves.field(i, CaveNetwork.F_WATER) >= float(root_y) - 1.5:
			return true
	return false


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
	_stamp_blueprint_list(data, dens, key, _blueprints_for(key))


func _stamp_blueprint_list(data: PackedByteArray, dens: PackedByteArray, key: Vector3i, bps: Array) -> void:
	var o := key * Chunk.SIZE
	var smooth := Blocks.family_table()
	for bp: Blueprint in bps:
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
	var touches := not _blueprints_for(key).is_empty()
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
