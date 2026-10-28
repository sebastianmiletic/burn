extends TestCase
## Revision 5 surface lands (world/biomes/surface_biomes.gd): revisions 2-4 generate exactly as
## before, new worlds get the dunes and their oasis, Moony Meadows, the Dragons' Graveyard,
## escarpments, valleys and arches, deterministically.

## Revision 4 chunks (seed 1234), recorded with main's generator before the lands were merged.
const GOLDEN_KEYS_4 := [Vector3i(64, 1, 64), Vector3i(26, 0, 65), Vector3i(218, -1, 218), Vector3i(262, 0, 66),
		Vector3i(64, -3, 64), Vector3i(125, -1, 125), Vector3i(78, 1, 163), Vector3i(100, 1, 90), Vector3i(37, 0, 105)]
const GOLDEN_4 := "2869317766/1606318894,3421629514/3681642917,3891204306/270247331,3933628830/3678062242,549836671/1535358581,1253118892/2937777524,3843902944/2544374968,464595002/561283273,2694786439/3473403460"


static func gen(revision: int, seed_value := 1234) -> WorldGen:
	return load("res://tests/unit/test_ocean_worlds.gd").gen(revision, seed_value)


func test_revision_4_generates_as_before() -> void:
	var sig: String = load("res://tests/unit/test_ocean_worlds.gd").signature(gen(4), GOLDEN_KEYS_4)
	if GOLDEN_4 == "":
		print("      golden 4: %s" % sig)
	check_eq(sig, GOLDEN_4, "revision 4 chunks are unchanged")
	check(gen(4).land == null, "revision 4 has no surface lands")


func test_new_worlds_have_the_lands() -> void:
	check(WorldGen.LATEST_REVISION >= 5, "new worlds are revision 5+")
	var g := gen(WorldGen.LATEST_REVISION, 4321)
	check(g.land != null, "revision 5 plans the lands")
	for k: int in [SurfaceBiomes.Land.DESERT, SurfaceBiomes.Land.MEADOW, SurfaceBiomes.Land.GRAVEYARD]:
		var c: Vector3 = g.land.centres[k]
		check_eq(g.region_name(c.x, c.y), SurfaceBiomes.LAND_NAMES[k], "%s is named on the HUD" % SurfaceBiomes.LAND_NAMES[k])
	var o := g.land.oasis
	check(g.lake_level(o.x, o.z).x > -INF, "the oasis has a spring pool")
	check(SurfaceBiomes.is_safe(Vector3(o.x, 20, o.z)), "the oasis is a safe zone")
	var m: Vector3 = g.land.centres[SurfaceBiomes.Land.MEADOW]
	check(SurfaceBiomes.is_peaceful(g, Vector3(m.x, 20, m.y)), "the meadow is peaceful")
	check(not SurfaceBiomes.is_safe(Vector3(1024, 20, 1024)), "Emberfall is no oasis")
	check_eq(SurfaceBiomes.keep_out(Vector3(o.x + 80, 20, o.z), Vector3(o.x, 20, o.z)).distance_to(Vector3(o.x, 20, o.z)) >= SurfaceBiomes.SAFE_RADIUS, true,
			"hostiles are turned back at the oasis rim")


func test_desert_surfaces_and_arches() -> void:
	var g := gen(WorldGen.LATEST_REVISION, 4321)
	var c: Vector3 = g.land.centres[SurfaceBiomes.Land.DESERT]
	var sand := 0
	var n := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 60:
		var x := int(c.x + rng.randf_range(-120, 120))
		var z := int(c.y + rng.randf_range(-120, 120))
		var h := g.surface_height(x, z)
		var data: PackedByteArray = g.generate(Vector3i(x >> 4, h >> 4, z >> 4))[0]
		var b := data[(x & 15) + (z & 15) * 16 + (h & 15) * 256] if not data.is_empty() else 0
		n += 1
		if b in [Blocks.SAND, Blocks.SANDSTONE, Blocks.GRAVEL, Blocks.CLAY, Blocks.LIMESTONE, Blocks.RED_ROCK, Blocks.UMBER_ROCK]:
			sand += 1
	check(sand > n * 0.8, "the dunes are sand and sandstone (%d/%d)" % [sand, n])
	check(g.land.arches.size() >= 2, "the desert has natural arches (%d)" % g.land.arches.size())
	if not g.land.arches.is_empty():
		var a: Array = g.land.arches[0]
		var top: Vector3 = (a[0] as Vector3) + Vector3(0, float(a[2]), 0)
		var key := Vector3i(floori(top.x / 16.0), floori(top.y / 16.0), floori(top.z / 16.0))
		var data: PackedByteArray = g.generate(key)[0]
		var p := Vector3i(top.floor()) - key * 16
		check(not data.is_empty() and data[p.x + p.z * 16 + p.y * 256] != Blocks.AIR, "an arch's crown is solid rock")


func test_lands_are_deterministic() -> void:
	var a := WorldGen.new(WorldGen.Dimension.OVERWORLD, 4321, WorldGen.LATEST_REVISION)
	a.prepare()
	var b := gen(WorldGen.LATEST_REVISION, 4321)
	var keys: Array = []
	for k: int in b.land.centres:
		var c: Vector3 = b.land.centres[k]
		keys.append(Vector3i(int(c.x) >> 4, b.surface_height(int(c.x), int(c.y)) >> 4, int(c.y) >> 4))
	check_eq(load("res://tests/unit/test_ocean_worlds.gd").signature(a, keys), load("res://tests/unit/test_ocean_worlds.gd").signature(b, keys), "same seed, same lands")
