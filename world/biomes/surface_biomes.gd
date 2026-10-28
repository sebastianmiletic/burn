class_name SurfaceBiomes
extends RefCounted
## World revision 5 (new worlds only): surface biomes and landforms on the campaign island.
##
## Lands are overlays on the revision 3 biome map ("host" biomes keep every table indexed by
## WorldGen.Biome valid; region_name() and the spawner ask here first):
##   * DESERT, "The Sunscar Dunes" (south-east): wind-shaped transverse/barchan dunes with
##     slip faces, banded sandstone mesas and buttes, natural arches (signed-distance solids
##     unioned into the density field), slot ravines and cave mouths in the mesa flanks.
##   * OASIS, inside the desert: a turquoise spring pool (a planned lake), a lush grass ring and
##     palms; a safe zone (no hostile spawns, hostiles will not enter it: keep_out()).
##   * MEADOW, "Moony Meadows" (north-east): gentle rolling ground under head-high silver grass
##     (BiomeFlora); peaceful; trapdoors to the Labyrinth (BiomeSites).
##   * GRAVEYARD, "The Dragons' Graveyard" (south-west): a bleak grey basin with rock spines and
##     cliffs, dragon skeletons, mist and ghosts (BiomeSites).
## Landforms everywhere in revision 5: winding escarpments (sheer cliffs of layered rock, one or
## two steps), broad U-shaped valleys, and extra cave mouths at cliff feet, mesa flanks and pits.
## Transitions: every land fades over a ~120 m band; surfaces are dithered per column with a
## patchy noise (so soil, terrain material and flora mix), heights blend continuously.
##
## WorldGen owns one instance (`gen.land`, revision >= 5) and calls it from a handful of hooks.
## Everything here is deterministic and thread-safe after construction (read-only noise).

enum Land { NONE, DESERT, MEADOW, GRAVEYARD, OASIS }
const LAND_NAMES := ["", "The Sunscar Dunes", "Moony Meadows", "The Dragons' Graveyard", "Sunscar Oasis"]
## Map tints per land.
const LAND_COLORS := [Color(0, 0, 0), Color(0.86, 0.71, 0.47), Color(0.56, 0.64, 0.6), Color(0.42, 0.41, 0.4), Color(0.32, 0.6, 0.38)]
## Host biome per land (spawn tables, trees fallback, horizon colours).
const HOST := [-1, WorldGen.Biome.WASTES, WorldGen.Biome.PLAINS, WorldGen.Biome.WASTES, WorldGen.Biome.WASTES]
## Land regions: x, z, radius (nominal; jittered a little per world seed).
const REGIONS := {
	Land.DESERT: Vector3(1600, 1440, 285),
	Land.MEADOW: Vector3(1640, 700, 215),
	Land.GRAVEYARD: Vector3(590, 1690, 180),
}
## Width of the transition band (m) around each land.
const BAND := 120.0
const OASIS_RADIUS := 95.0     ## lush ring fades out over this distance from the spring
const OASIS_POOL := 17.0       ## spring pool radius
const SAFE_RADIUS := 55.0      ## hostiles never enter this disc around the oasis
## Value WorldGen.surface_biome_at() returns for a land column: LAND_CODE + Land.
const LAND_CODE := 32
## Mesher material codes (SmoothMesher / TerrainTextures / Flora): biome variants of a block,
## in the 120..127 range Blocks reserves for them (the texture tables hold 128 codes).
const CODE_DUNE_SAND := 123
const CODE_OASIS_GRASS := 124
const CODE_MOON_GRASS := 125
const CODE_GRAVE_SOIL := 126
## Places the landforms keep away from (planned settlements, boss sites).
const KEEP_CLEAR := [Vector2(1024, 1024), Vector2(1215, 875), Vector2(1575, 1045), Vector2(1000, 575), Vector2(540, 905),
	Vector2(850, 1510), Vector2(410, 1110), Vector2(1024, 300), Vector2(1040, 1800), Vector2(1024, 1555),
	Vector2(2430, 1120), Vector2(3060, 960), Vector2(3860, 1180), Vector2(3930, 640), Vector2(3320, 1880),
	Vector2(1560, 2440), Vector2(800, 3080), Vector2(1930, 3140)]

## Safe discs (x, z, radius) of the last prepared revision-5 overworld (enemies, spawner).
static var safe_zones := PackedVector3Array()
## Peaceful lands of the last prepared overworld: [Vector3 region, kind].
static var peaceful_regions: Array = []

var seed_value := 1
var centres := {}            # Land -> Vector3 (x, z, r)
var oasis := Vector3.ZERO    # x, z, ground level
var arches: Array = []       # [Vector3 centre (on the ground), Vector3 axis, float R, float r, AABB]
var _keep := PackedVector2Array()

var _n_warp: FastNoiseLite
var _n_dune: FastNoiseLite
var _n_dune_a: FastNoiseLite
var _n_mesa: FastNoiseLite
var _n_roll: FastNoiseLite
var _n_spine: FastNoiseLite
var _n_ezone: FastNoiseLite
var _n_eline: FastNoiseLite
var _n_vzone: FastNoiseLite
var _n_valley: FastNoiseLite
var _n_pick: FastNoiseLite
var _n_arch: FastNoiseLite


func _init(world_seed: int) -> void:
	seed_value = world_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 92821 + 5
	for k: int in REGIONS:
		var r: Vector3 = REGIONS[k]
		centres[k] = Vector3(r.x + rng.randf_range(-25, 25), r.y + rng.randf_range(-25, 25), r.z)
	var dc: Vector3 = centres[Land.DESERT]
	# The spring sits in the northern half of the dunes, toward the forest.
	var a := rng.randf_range(-2.6, -1.2)
	oasis = Vector3(dc.x + cos(a) * 95.0, 0.0, dc.y + sin(a) * 95.0)
	_n_warp = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.006, 2, 601)
	_n_dune = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.004, 2, 602)
	_n_dune_a = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.008, 2, 603)
	_n_mesa = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0062, 2, 604)
	_n_roll = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0055, 2, 605)
	_n_spine = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.011, 3, 606)
	_n_spine.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_n_ezone = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0013, 2, 607)
	_n_eline = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0026, 2, 608)
	_n_vzone = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0011, 1, 609)
	_n_valley = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0019, 2, 610)
	_n_pick = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.09, 2, 611)
	_n_arch = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.18, 1, 612)
	_keep = PackedVector2Array(KEEP_CLEAR)


func _noise(type: int, freq: float, octaves: int, offset: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = type
	n.frequency = freq
	n.fractal_octaves = octaves
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	n.seed = seed_value + offset
	return n


# --- Regions ------------------------------------------------------------------------------

## (land, weight 0..1) at a point: smooth over the transition band, warped edges.
func land_weight(p: Vector2) -> Vector2:
	for k: int in centres:
		var c: Vector3 = centres[k]
		var dx := p.x - c.x
		var dz := p.y - c.y
		var reach := c.z + BAND
		if absf(dx) > reach or absf(dz) > reach:
			continue
		var d := sqrt(dx * dx + dz * dz) + _n_warp.get_noise_2dv(p * 0.5) * 70.0
		var w := 1.0 - smoothstep(c.z - BAND * 0.75, c.z + BAND * 0.25, d)
		if w <= 0.0:
			continue
		if k == Land.DESERT:
			var wo := oasis_weight(p)
			if wo > 0.5:
				return Vector2(Land.OASIS, wo)
		return Vector2(k, w)
	return Vector2.ZERO


## 0..1: the oasis' lush ring (1 at the spring).
func oasis_weight(p: Vector2) -> float:
	var d := p.distance_to(Vector2(oasis.x, oasis.z)) + _n_warp.get_noise_2dv(p * 2.0) * 14.0
	return 1.0 - smoothstep(OASIS_RADIUS * 0.45, OASIS_RADIUS, d)


func _keep_clear(p: Vector2) -> float:
	var f := 1.0
	for q in _keep:
		var d := p.distance_squared_to(q)
		if d < 260.0 * 260.0:
			f = minf(f, smoothstep(140.0, 260.0, sqrt(d)))
	return f


# --- 4 m terrain maps (WorldGen._rows_v3, before the coast) --------------------------------

## Reshapes one 4 m cell. Returns Vector4(base, detail amplitude, ridge amplitude,
## biome + 256 * land code) where land code = land | (weight * 31) << 3.
func cell(p: Vector2, base: float, amp: float, ridge: float, biome: int) -> Vector4:
	var lw := land_weight(p)
	var kind := int(lw.x)
	var w := lw.y
	var lf := Vector2(base, amp)
	if kind != Land.NONE:
		var shaped := _land_height(kind, p)
		base = lerpf(base, shaped.x, w)
		amp = lerpf(amp, shaped.y, w)
		ridge = lerpf(ridge, 0.0, w)
		if w > 0.5:
			biome = HOST[kind]
	# Landforms (not in the dunes or the meadow; strongest in the graveyard).
	var e_fac := _escarp_factor(biome)
	if kind == Land.DESERT or kind == Land.OASIS or kind == Land.MEADOW:
		e_fac *= 1.0 - w
	elif kind == Land.GRAVEYARD:
		e_fac = lerpf(e_fac, 1.3, w)
	var keep := _keep_clear(p)
	if e_fac > 0.0 and keep > 0.0:
		var ez := smoothstep(0.1, 0.32, _n_ezone.get_noise_2dv(p)) * e_fac * keep
		if ez > 0.01:
			var wp := p + Vector2(_n_warp.get_noise_2dv(p), _n_warp.get_noise_2d(p.y, p.x)) * 40.0
			var l := _n_eline.get_noise_2dv(wp)
			var hgt := 11.0 + 9.0 * (_n_dune_a.get_noise_2dv(p * 0.2) * 0.5 + 0.5)
			var lift := smoothstep(-0.011, 0.011, l) + 0.6 * smoothstep(0.055, 0.075, l)
			base += lift * hgt * ez * smoothstep(WorldGen.SEA_LEVEL + 3.0, WorldGen.SEA_LEVEL + 12.0, base)
	var v_fac := _valley_factor(biome) * (1.0 - (w if kind != Land.NONE else 0.0))
	if v_fac > 0.0 and keep > 0.0:
		var vz := smoothstep(0.05, 0.3, _n_vzone.get_noise_2dv(p)) * v_fac * keep
		if vz > 0.01:
			var wp := p + Vector2(_n_warp.get_noise_2d(p.x * 0.5, p.y * 0.5 + 300.0), _n_warp.get_noise_2d(p.y * 0.5, p.x * 0.5)) * 90.0
			var v := absf(_n_valley.get_noise_2dv(wp))
			var prof := 1.0 - smoothstep(0.012, 0.08, v)
			if prof > 0.0:
				var depth := 19.0 * vz * pow(prof, 0.75)
				base = maxf(base - depth, minf(base, WorldGen.SEA_LEVEL + 4.0))
	var code := 0
	if kind != Land.NONE:
		code = kind | (clampi(int(roundf(w * 31.0)), 0, 31) << 3)
	return Vector4(base, amp, ridge, float(biome + 256 * code))


func _escarp_factor(biome: int) -> float:
	match biome:
		WorldGen.Biome.FOREST, WorldGen.Biome.WASTES:
			return 1.0
		WorldGen.Biome.PLAINS, WorldGen.Biome.REDWOOD:
			return 0.85
		WorldGen.Biome.TUNDRA, WorldGen.Biome.FJORD:
			return 0.6
		WorldGen.Biome.CANYON, WorldGen.Biome.VOLCANIC, WorldGen.Biome.MARSH:
			return 0.35
	return 0.0


func _valley_factor(biome: int) -> float:
	match biome:
		WorldGen.Biome.FOREST, WorldGen.Biome.REDWOOD:
			return 1.0
		WorldGen.Biome.ALPINE, WorldGen.Biome.PLAINS:
			return 0.75
		WorldGen.Biome.PEAKS, WorldGen.Biome.FJORD, WorldGen.Biome.TUNDRA:
			return 0.55
		WorldGen.Biome.WASTES, WorldGen.Biome.CANYON:
			return 0.4
	return 0.0


## (height, detail amplitude) of a land's own terrain at p.
func _land_height(kind: int, p: Vector2) -> Vector2:
	match kind:
		Land.DESERT, Land.OASIS:
			var floor_h := 21.0 + _n_roll.get_noise_2dv(p * 0.4) * 3.5
			var od := p.distance_to(Vector2(oasis.x, oasis.z))
			var mesa := mesa_height(p) * smoothstep(70.0, 130.0, od)
			var cover := smoothstep(0.5, 6.0, mesa)
			var h := floor_h + dune_height(p) * (1.0 - cover) * smoothstep(25.0, 75.0, od) + mesa
			# The oasis lies in a shallow green hollow around its spring.
			var wo := oasis_weight(p)
			h = lerpf(h, 19.6, smoothstep(0.0, 0.85, wo))
			return Vector2(h, lerpf(0.9, 1.6, wo))
		Land.MEADOW:
			return Vector2(23.0 + _n_roll.get_noise_2dv(p) * 5.0 + _n_roll.get_noise_2dv(p * 2.7) * 1.6, 1.8)
		Land.GRAVEYARD:
			var spine := _n_spine.get_noise_2dv(p) * 0.5 + 0.5
			var h := 16.0 + _n_roll.get_noise_2dv(p * 1.3) * 4.0 + pow(smoothstep(0.55, 0.95, spine), 1.6) * 14.0
			return Vector2(h, 2.6)
	return Vector2(20.0, 4.0)


## Dunes: transverse ridges across the prevailing wind (from the west-south-west) with long
## windward backs and short slip faces at the angle of repose, breaking into crescents.
func dune_height(p: Vector2) -> float:
	var wind := Vector2(0.94, 0.34)
	var side := Vector2(-wind.y, wind.x)
	var u := p.dot(wind)
	var v := p.dot(side)
	var wv := _n_dune.get_noise_2dv(p)
	var phase := u / 64.0 + wv * 1.7 + _n_dune.get_noise_2d(v * 0.5, 913.0) * 0.9
	var f := phase - floorf(phase)
	var prof := f / 0.72 if f < 0.72 else (1.0 - f) / 0.28
	prof = prof * prof * (3.0 - 2.0 * prof)
	var a := 2.5 + 8.5 * (_n_dune_a.get_noise_2dv(p) * 0.5 + 0.5)
	var seg := 0.6 + 0.4 * sin(v / 41.0 + wv * 3.0)
	var draa := (_n_dune_a.get_noise_2dv(p * 0.25) * 0.5 + 0.5) * 6.0
	return prof * a * seg + draa


## Mesas and buttes: flat-topped sandstone tables in one or two tiers with sheer walls.
func mesa_height(p: Vector2) -> float:
	var wp := p + Vector2(_n_warp.get_noise_2dv(p * 1.5), _n_warp.get_noise_2d(p.y * 1.5, p.x * 1.5)) * 30.0
	var m := _n_mesa.get_noise_2dv(wp)
	var t1 := smoothstep(0.36, 0.41, m)
	if t1 <= 0.0:
		return 0.0
	var t2 := smoothstep(0.55, 0.59, m)
	return t1 * (21.0 + 7.0 * (_n_roll.get_noise_2dv(p * 0.7) * 0.5 + 0.5)) + t2 * 11.0


# --- Columns ------------------------------------------------------------------------------

## Land of a column for its surface: the land inside, the host outside, dithered across the
## transition band in noisy patches (soil, terrain material and flora all follow it).
func pick(gen: WorldGen, x: int, z: int) -> int:
	var code := gen.land_code(x, z)
	if code == 0:
		return Land.NONE
	var kind := code & 7
	var w := float(code >> 3) / 31.0
	if kind == Land.OASIS:
		# The lush ring fades into the dunes.
		var wo := oasis_weight(Vector2(x, z))
		return Land.OASIS if _dither(x, z, wo) else Land.DESERT
	if w >= 0.999:
		return kind
	return kind if _dither(x, z, w) else Land.NONE


func _dither(x: int, z: int, w: float) -> bool:
	var n := _n_pick.get_noise_2d(x, z) * 0.5 + 0.5
	n = n * 0.8 + float(WorldGen._hash3(x, 3, z, seed_value) & 255) / 255.0 * 0.2
	return n < w


## Surface (low byte) and subsurface (high byte) of a land column; `surf` is the host's.
func surface(gen: WorldGen, x: int, z: int, h: int, road: int, s: float, surf: int) -> int:
	if road == 1:
		return surf
	var kind := pick(gen, x, z)
	if kind == Land.NONE:
		return surf
	var n := WorldGen._vnoise(x, z, 7.0, 613)
	var face := s > 0.95 + (WorldGen._vnoise(x, z, 6.0, 41) - 0.5) * 0.3
	match kind:
		Land.DESERT:
			if face:
				return WorldGen.FACE | (WorldGen.FACE << 8)
			if s > 0.7:
				return (Blocks.SANDSTONE if n < 0.6 else Blocks.SAND) | (Blocks.SANDSTONE << 8)
			if h > 36 and n < 0.45:
				return Blocks.SANDSTONE | (Blocks.SANDSTONE << 8)  # wind-scoured mesa tops
			if n > 0.93:
				return Blocks.GRAVEL | (Blocks.SAND << 8)  # desert pavement
			return Blocks.SAND | (Blocks.SAND << 8)
		Land.OASIS:
			var od := Vector2(x, z).distance_to(Vector2(oasis.x, oasis.z))
			if od < OASIS_POOL + 4.0 + n * 3.0:
				return Blocks.SAND | (Blocks.SAND << 8)
			return Blocks.GRASS | (Blocks.DIRT << 8)
		Land.MEADOW:
			if face:
				return WorldGen.FACE | (WorldGen.FACE << 8)
			if s > 0.75:
				return Blocks.STONE | (Blocks.DIRT << 8)
			return Blocks.GRASS | (Blocks.DIRT << 8)
		Land.GRAVEYARD:
			if face:
				return WorldGen.FACE | (WorldGen.FACE << 8)
			if s > 0.6:
				return (Blocks.SLATE if n < 0.5 else Blocks.GRAVEL) | (Blocks.GRAVEL << 8)
			if n < 0.3:
				return Blocks.GRAVEL | (Blocks.DIRT << 8)
			if n < 0.42:
				return Blocks.ASH | (Blocks.DIRT << 8)
			return Blocks.DIRT | (Blocks.GRAVEL << 8)
	return surf


## Rock group of a land column (deep layers and cliff faces).
func rock_group(kind: int, group: int) -> int:
	match kind:
		Land.DESERT, Land.OASIS:
			return WorldGen.Rock.DUNE
		Land.GRAVEYARD:
			return WorldGen.Rock.MOUNTAIN
	return group


## Banded desert sandstone: cream, ochre, rose and pale limestone beds a couple of metres thick.
static func dune_rock(y: int, st: int, band: int, pocket: bool) -> int:
	if y < 2:
		return Blocks.STONE if band < 2 else Blocks.SANDSTONE
	var bed := posmod(floori((float(y) + float(st) * 0.03) / 2.4), 10)
	if pocket and bed == 4:
		return Blocks.CLAY
	return [Blocks.SANDSTONE, Blocks.SANDSTONE, Blocks.LIMESTONE, Blocks.SANDSTONE, Blocks.CLAY,
			Blocks.SANDSTONE, Blocks.RED_ROCK, Blocks.SANDSTONE, Blocks.SANDSTONE, Blocks.UMBER_ROCK][bed]


## Tree rule of a land column: Vector3(chance, trunk block, trunk height); host values pass through.
func tree(gen: WorldGen, x: int, z: int, chance: float, trunk: int, trunk_h: int, hsh: int) -> Vector3:
	var kind := pick(gen, x, z)
	match kind:
		Land.DESERT:
			return Vector3(0.004, Blocks.DEAD_TRUNK, 3)
		Land.OASIS:
			return Vector3(0.0, trunk, trunk_h)  # palms are drawn by BiomeFlora
		Land.MEADOW:
			return Vector3(0.008, Blocks.OAK_TRUNK if hsh % 3 != 0 else Blocks.CRIMSON_TRUNK, 4)
		Land.GRAVEYARD:
			return Vector3(0.03, Blocks.DEAD_TRUNK, 4)
	return Vector3(chance, trunk, trunk_h)


## Ground colour seen from afar (WorldGen.horizon_color); alpha 0 = not a land column.
func horizon(gen: WorldGen, x: int, z: int, h: int, slope: float) -> Color:
	if gen.land_code(x, z) == 0:
		return Color(0, 0, 0, 0)
	var kind := pick(gen, x, z)
	if kind == Land.NONE:
		return Color(0, 0, 0, 0)
	var top := surface(gen, x, z, h, 0, slope, Blocks.SAND) & 255
	match kind:
		Land.DESERT:
			if top == WorldGen.FACE:
				return Color(0.7, 0.52, 0.36) if posmod(h / 3, 3) != 1 else Color(0.78, 0.64, 0.46)
			if top == Blocks.SANDSTONE:
				return Color(0.76, 0.6, 0.42)
			return Color(0.86, 0.72, 0.5)
		Land.OASIS:
			return Color(0.78, 0.7, 0.5) if top == Blocks.SAND else Color(0.2, 0.36, 0.14)
		Land.MEADOW:
			return Color(0.36, 0.42, 0.34) if top == Blocks.GRASS else Color(0.44, 0.43, 0.42)
		Land.GRAVEYARD:
			return Color(0.3, 0.3, 0.3) if top == WorldGen.FACE else Color(0.38, 0.37, 0.35)
	return Color(0, 0, 0, 0)


## Mesher biome byte of a column: LAND_CODE + land for land columns.
func mesher_biome(gen: WorldGen, x: int, z: int, biome: int) -> int:
	var kind := pick(gen, x, z)
	return LAND_CODE + kind if kind != Land.NONE else biome


## Mesher material code for `block` on a land column (`bi` = mesher biome byte), or -1.
static func material_code(block: int, bi: int) -> int:
	match bi - LAND_CODE:
		Land.DESERT:
			if block == Blocks.SAND:
				return CODE_DUNE_SAND
		Land.OASIS:
			if block == Blocks.GRASS:
				return CODE_OASIS_GRASS
		Land.MEADOW:
			if block == Blocks.GRASS:
				return CODE_MOON_GRASS
		Land.GRAVEYARD:
			if block == Blocks.DIRT or block == Blocks.GRAVEL or block == Blocks.ASH:
				return CODE_GRAVE_SOIL
	return -1


static func block_of_code(code: int) -> int:
	match code:
		CODE_DUNE_SAND:
			return Blocks.SAND
		CODE_OASIS_GRASS, CODE_MOON_GRASS:
			return Blocks.GRASS
		CODE_GRAVE_SOIL:
			return Blocks.DIRT
	return code


# --- Queries --------------------------------------------------------------------------------

## HUD name of a land, or "" outside them (weight above one half).
func region_name(p: Vector2) -> String:
	var lw := land_weight(p)
	if lw.x == Land.NONE or lw.y < 0.5:
		return ""
	return LAND_NAMES[int(lw.x)]


## Climate adjustments: Vector3(snow, dust, haze) -> adjusted (heat shimmer on the dunes, mist
## lying in the graveyard).
func climate(p: Vector3, c: Vector3) -> Vector3:
	var lw := land_weight(Vector2(p.x, p.z))
	match int(lw.x):
		Land.DESERT:
			return Vector3(0.0, maxf(c.y, 0.55 * lw.y), c.z)
		Land.GRAVEYARD:
			return Vector3(c.x * 0.3, c.y * 0.3, maxf(c.z, 0.85 * lw.y))
		Land.OASIS:
			return Vector3(0.0, 0.1, c.z)
	return c


# --- Planning (prepare) ----------------------------------------------------------------------

## WorldGen._plan_lakes: the oasis spring (sculpted with the other bowls), the arches.
func plan(gen: WorldGen) -> void:
	var g := gen.smooth_height(oasis.x, oasis.z)
	oasis.y = g
	gen.lakes.append([Vector2(oasis.x, oasis.z), OASIS_POOL, g - 0.7, Blocks.WATER])
	_plan_arches(gen)
	_register()


func _register() -> void:
	safe_zones = PackedVector3Array([Vector3(oasis.x, oasis.z, SAFE_RADIUS)])
	var m: Vector3 = centres[Land.MEADOW]
	peaceful_regions = [[m, Land.MEADOW]]


## Clears the static registries (older worlds have no lands).
static func unregister() -> void:
	safe_zones = PackedVector3Array()
	peaceful_regions = []


func _plan_arches(gen: WorldGen) -> void:
	arches.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 3571 + 17
	var dc: Vector3 = centres[Land.DESERT]
	for attempt in 120:
		if arches.size() >= 5:
			break
		var p := Vector2(dc.x, dc.y) + Vector2.from_angle(rng.randf() * TAU) * dc.z * 0.8 * sqrt(rng.randf())
		if p.distance_to(Vector2(oasis.x, oasis.z)) < 110.0:
			continue
		var lw := land_weight(p)
		if lw.x != Land.DESERT or lw.y < 0.9 or mesa_height(p) > 0.5:
			continue
		var ok := true
		for a: Array in arches:
			if Vector2((a[0] as Vector3).x, (a[0] as Vector3).z).distance_to(p) < 70.0:
				ok = false
		if not ok:
			continue
		var big := rng.randf_range(7.5, 13.0)
		var tube := rng.randf_range(2.2, 3.1)
		var ang := rng.randf() * TAU
		var axis := Vector3(cos(ang), 0, sin(ang))
		# Both feet on the ground: the lower of the two sets the base.
		var fa := p + Vector2(axis.x, axis.z) * big
		var fb := p - Vector2(axis.x, axis.z) * big
		var g := minf(gen.smooth_height(fa.x, fa.y), gen.smooth_height(fb.x, fb.y))
		if g < WorldGen.SEA_LEVEL + 3.0:
			continue
		var c := Vector3(p.x, g - 1.0, p.y)
		var ext := Vector3(big + tube + 4.0, big + tube + 3.0, big + tube + 4.0)
		var box := AABB(c - Vector3(ext.x, 9.0, ext.z), Vector3(ext.x * 2.0, ext.y + 9.0, ext.z * 2.0))
		arches.append([c, axis, big, tube, box])


## Arches intersecting a chunk (WorldGen._generate_overworld_v3).
func arches_in(o: Vector3i) -> Array:
	if arches.is_empty():
		return []
	var cb := AABB(Vector3(o), Vector3(16, 16, 16))
	var out: Array = []
	for a: Array in arches:
		if (a[4] as AABB).intersects(cb):
			out.append(a)
	return out


## Density (WorldGen convention: >= 0.5 solid) of the arches at a voxel.
func arch_density(list: Array, x: int, y: int, z: int) -> float:
	var best := -1.0
	var p := Vector3(x + 0.5, y + 0.5, z + 0.5)
	for a: Array in list:
		var c: Vector3 = a[0]
		var axis: Vector3 = a[1]
		var big: float = a[2]
		var tube: float = a[3]
		var q := p - c
		var qa := q.dot(axis)
		var qn := q.dot(Vector3(-axis.z, 0, axis.x))
		var qy := q.y
		var sd := 0.0
		if qy >= 0.0:
			var ring := Vector2(qa, qy).length()
			var th := atan2(qy, absf(qa))  # 0 at the feet, pi/2 at the crown
			var rr := tube * (1.0 + 0.55 * (1.0 - sin(th)))
			sd = Vector2(ring - big, qn * 1.15).length() - rr
		else:
			# Feet: flaring buttresses down into the ground.
			var rr := tube * (1.55 + minf(-qy, 9.0) * 0.08)
			sd = Vector2(absf(qa) - big, qn * 1.15).length() - rr
		sd += _n_arch.get_noise_3dv(p) * 0.55
		best = maxf(best, 0.5 - sd * 0.5)
	return best


## Rock of an arch voxel above the ground.
static func arch_block(y: int) -> int:
	return dune_rock(y, 128, 0, false)


## Extra cave mouths: at the feet of escarpments, in the mesa flanks, pits in the graveyard.
func plan_caves(gen: WorldGen, net: CaveNetwork) -> void:
	var detail := gen.make_detail_noise()
	var ridge := gen.make_ridge_noise()
	var rng := RandomNumberGenerator.new()
	const CELL := 72
	var made := 0
	for cz in range(2, gen.size / CELL - 2):
		for cx in range(2, gen.size / CELL - 2):
			var h := WorldGen._hash3(cx, 13, cz, seed_value + 6150)
			var p := Vector2(cx * CELL + (h & 63), cz * CELL + ((h >> 6) & 63))
			if gen.biome_at(int(p.x), int(p.y)) == WorldGen.Biome.OCEAN or gen.is_protected(p.x, p.y):
				continue
			var lw := land_weight(p)
			var roll := float((h >> 12) & 1023) / 1023.0
			var chance := 0.0
			var g := gen.smooth_height(p.x, p.y)
			var slope := Vector2(gen.smooth_height(p.x + 6, p.y) - gen.smooth_height(p.x - 6, p.y),
					gen.smooth_height(p.x, p.y + 6) - gen.smooth_height(p.x, p.y - 6)).length() / 12.0
			if int(lw.x) == Land.GRAVEYARD and lw.y > 0.6:
				chance = 0.22 if slope < 0.14 else 0.35
			elif int(lw.x) == Land.DESERT and lw.y > 0.6:
				chance = 0.45 if slope > 0.35 and slope < 1.5 and mesa_height(p) < 3.0 else 0.0
			elif int(lw.x) == Land.NONE or lw.y < 0.3:
				var ez := smoothstep(0.1, 0.32, _n_ezone.get_noise_2dv(p)) * _escarp_factor(gen.biome_at(int(p.x), int(p.y)))
				if ez > 0.3 and slope > 0.3 and slope < 1.5:
					chance = 0.4
			if roll >= chance or g < WorldGen.SEA_LEVEL + 6.0:
				continue
			rng.seed = h
			var before := net.entrances.size()
			CaveNetwork._mouth(net, gen, p, rng, detail, ridge)
			if net.entrances.size() > before:
				made += 1
	if "--load-timing" in OS.get_cmdline_user_args():
		print("[load]   revision 5 cave mouths: %d" % made)


# --- Safe zones (server AI and spawning) ------------------------------------------------------

## True inside a safe disc of the last prepared revision-5 overworld (static registry).
static func is_safe(pos: Vector3) -> bool:
	for z in safe_zones:
		if Vector2(pos.x - z.x, pos.z - z.y).length_squared() < z.z * z.z:
			return true
	return false


## True inside a peaceful land of `gen` (no hostile wild spawns): the oasis' safe disc and lush
## ring, and Moony Meadows. Always false for worlds without lands (revision < 5).
static func is_peaceful(gen: Object, pos: Vector3) -> bool:
	var land: Variant = gen.get("land") if gen != null else null
	if land == null:
		return false
	var sb := land as SurfaceBiomes
	var p := Vector2(pos.x, pos.z)
	if p.distance_squared_to(Vector2(sb.oasis.x, sb.oasis.z)) < SAFE_RADIUS * SAFE_RADIUS:
		return true
	var lw := sb.land_weight(p)
	return (int(lw.x) == Land.MEADOW and lw.y > 0.4) or int(lw.x) == Land.OASIS


## True inside this world's oasis safe disc (instance form of is_safe(); no static state).
func safe_at(pos: Vector3) -> bool:
	return Vector2(pos.x - oasis.x, pos.z - oasis.z).length_squared() < SAFE_RADIUS * SAFE_RADIUS


## Where a hostile at `from` may head for `target`: never into this world's oasis (the point is
## pushed back to the rim); from inside it, straight out.
func keep_out(from: Vector3, target: Vector3) -> Vector3:
	for z in [Vector3(oasis.x, oasis.z, SAFE_RADIUS)]:
		var c := Vector2(z.x, z.y)
		var r: float = z.z + 1.5
		var f := Vector2(from.x, from.z)
		var t := Vector2(target.x, target.z)
		if f.distance_to(c) < r:
			var out := (f - c).normalized() if f.distance_to(c) > 0.1 else Vector2.RIGHT
			var e := c + out * (r + 4.0)
			return Vector3(e.x, from.y, e.y)
		if t.distance_to(c) < r:
			# Wait on the rim on the hostile's own side (never walk across the oasis).
			var dir := (f - c).normalized()
			var e := c + dir * r
			return Vector3(e.x, target.y, e.y)
	return target


## Extra loot for a hostile spawned at `pos` (WildSpawner): dragon fang, blood and femur in the
## Dragons' Graveyard; [] elsewhere and in older worlds.
static func land_loot(gen: Object, pos: Vector3) -> Array:
	var land: Variant = gen.get("land") if gen != null else null
	if land == null:
		return []
	var lw: Vector2 = (land as SurfaceBiomes).land_weight(Vector2(pos.x, pos.z))
	if int(lw.x) != Land.GRAVEYARD or lw.y < 0.5:
		return []
	return [["dragon_fang", 0.18, 1, 1], ["dragon_blood", 0.1, 1, 1], ["dragon_femur", 0.12, 1, 1]]


## Wild spawn table override for lands ([] = none), or null for the host table.
static func spawn_table(gen: Object, pos: Vector3, night: bool) -> Variant:
	var land: Variant = gen.get("land") if gen != null else null
	if land == null:
		return null
	if is_peaceful(gen, pos):
		return []
	var lw: Vector2 = (land as SurfaceBiomes).land_weight(Vector2(pos.x, pos.z))
	if lw.y < 0.5:
		return null
	match int(lw.x):
		Land.GRAVEYARD:
			# Ghosts: shades drift among the bones (by day too).
			return [["shade", 1.0, 1, 2], ["skeleton", 0.6, 1, 2]] if night else [["shade", 0.6, 1, 1], ["skeleton", 0.5, 1, 1]]
		Land.DESERT:
			return [["scorpion", 1.0, 1, 2], ["skeleton", 0.6, 1, 2], ["archer", 0.3, 1, 1]] if night else [["scorpion", 1.0, 1, 2], ["fire_elemental", 0.15, 1, 1]]
	return null
