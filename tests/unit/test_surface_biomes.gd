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
	check(g.land.safe_at(Vector3(o.x, 20, o.z)), "the oasis is a safe zone")
	check(SurfaceBiomes.is_peaceful(g, Vector3(o.x, 20, o.z)), "the oasis is peaceful")
	var m: Vector3 = g.land.centres[SurfaceBiomes.Land.MEADOW]
	check(SurfaceBiomes.is_peaceful(g, Vector3(m.x, 20, m.y)), "the meadow is peaceful")
	check(not g.land.safe_at(Vector3(1024, 20, 1024)), "Emberfall is no oasis")
	check_eq(g.land.keep_out(Vector3(o.x + 80, 20, o.z), Vector3(o.x, 20, o.z)).distance_to(Vector3(o.x, 20, o.z)) >= SurfaceBiomes.SAFE_RADIUS, true,
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


func test_spawn_rules() -> void:
	var g := gen(WorldGen.LATEST_REVISION, 4321)
	var o := g.land.oasis
	for night in [false, true]:
		check_eq(SurfaceBiomes.spawn_table(g, Vector3(o.x, 20, o.z), night), [], "no hostiles spawn in the oasis (night %s)" % night)
		check_eq(SurfaceBiomes.spawn_table(g, Vector3(o.x + 40, 20, o.z), night), [], "nor on its lush ring (night %s)" % night)
		var m: Vector3 = g.land.centres[SurfaceBiomes.Land.MEADOW]
		check_eq(SurfaceBiomes.spawn_table(g, Vector3(m.x, 20, m.y), night), [], "Moony Meadows is peaceful (night %s)" % night)
		var gy: Vector3 = g.land.centres[SurfaceBiomes.Land.GRAVEYARD]
		var kinds: Array = (SurfaceBiomes.spawn_table(g, Vector3(gy.x, 20, gy.y), night) as Array).map(func(t: Array) -> String: return t[0])
		check("shade" in kinds, "ghosts haunt the Dragons' Graveyard (night %s)" % night)
		var d: Vector3 = g.land.centres[SurfaceBiomes.Land.DESERT]
		var far := Vector2(d.x, d.y) + (Vector2(d.x, d.y) - Vector2(o.x, o.z)).normalized() * 150.0
		var dk: Array = (SurfaceBiomes.spawn_table(g, Vector3(far.x, 20, far.y), night) as Array).map(func(t: Array) -> String: return t[0])
		check("scorpion" in dk, "scorpions roam the open dunes (night %s)" % night)
	check(SurfaceBiomes.spawn_table(gen(4), Vector3(o.x, 20, o.z), true) == null, "revision 4 keeps the host tables")
	check(not SurfaceBiomes.is_peaceful(gen(4), Vector3(o.x, 20, o.z)), "revision 4 has no oasis")
	# Every kind in a land table is a real enemy.
	var gy2: Vector3 = g.land.centres[SurfaceBiomes.Land.GRAVEYARD]
	for t: Array in SurfaceBiomes.spawn_table(g, Vector3(gy2.x, 20, gy2.y), true):
		check(Enemy.STATS.has(t[0]), "%s is an enemy kind" % t[0])


func test_meadow_grass_is_tall() -> void:
	var g := gen(WorldGen.LATEST_REVISION, 4321)
	var m: Vector3 = g.land.centres[SurfaceBiomes.Land.MEADOW]
	var moon := 0
	for i in 40:
		var x := int(m.x) + (i % 8) * 9 - 36
		var z := int(m.y) + (i / 8) * 9 - 20
		var bi := g.surface_biome_at(x, z)
		if SurfaceBiomes.material_code(Blocks.GRASS, bi) == SurfaceBiomes.CODE_MOON_GRASS:
			moon += 1
	check(moon >= 36, "the meadow's heart is moon grass (%d/40)" % moon)
	check_eq(g.surface_biome_at(1024, 1024), g.biome_at(1024, 1024), "outside the lands the mesher biome is the biome")
	check_eq(gen(4).surface_biome_at(int(m.x), int(m.y)), gen(4).biome_at(int(m.x), int(m.y)), "revision 4 meshes as before")
	check(SurfaceBiomes.CODE_GRAVE_SOIL < 128 and SurfaceBiomes.CODE_DUNE_SAND >= 123, "land codes fit the 128-entry texture tables")
	var rules: Array = Flora.RULES[Flora.BLOCK_MOON_GRASS]
	check_eq(int(rules[0][0]), Flora.L.TALL_GRASS, "moon grass grows tall grass")
	check(float(rules[0][2]) * 0.8 >= 1.5, "the tall grass reaches head height")
	# The mesher hands Flora the moon-grass code for meadow grass.
	var x0 := int(m.x)
	var z0 := int(m.y)
	var h := g.surface_height(x0, z0)
	var k := Vector3i(x0 >> 4, h >> 4, z0 >> 4)
	var nb: Array = []
	var dn: Array = []
	for dz in range(-1, 2):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var r := g.generate(k + Vector3i(dx, dy, dz))
				nb.append(r[0])
				dn.append(r[1])
	var surface := PackedInt32Array()
	surface.resize(256)
	surface.fill(1000)
	var biomes := PackedByteArray()
	biomes.resize(256)
	for z in 16:
		for x in 16:
			biomes[x + z * 16] = g.surface_biome_at(k.x * 16 + x, k.z * 16 + z)
	var res := SmoothMesher.build(nb, dn, surface, biomes, k * 16, 0)
	var fb: PackedByteArray = res.get("flora_surface", {}).get("blocks", PackedByteArray())
	check(Flora.BLOCK_MOON_GRASS in fb, "meadow chunks give Flora moon grass (%d triangles)" % fb.size())


func test_graveyard_loot_and_oasis_rim() -> void:
	var g := gen(WorldGen.LATEST_REVISION, 4321)
	var gy: Vector3 = g.land.centres[SurfaceBiomes.Land.GRAVEYARD]
	var names: Array = SurfaceBiomes.land_loot(g, Vector3(gy.x, 20, gy.y)).map(func(t: Array) -> String: return t[0])
	for item in ["dragon_fang", "dragon_blood", "dragon_femur"]:
		check(item in names, "the graveyard's dead carry %s" % item)
		check(ItemDB.BASE.has(item), "%s is an item" % item)
	check(SurfaceBiomes.land_loot(g, Vector3(1024, 20, 1024)).is_empty(), "no dragon parts elsewhere")
	check(SurfaceBiomes.land_loot(gen(4), Vector3(gy.x, 20, gy.y)).is_empty(), "nor in revision 4 worlds")
	# A hostile chasing someone into the oasis waits on the rim on its own side.
	var o := g.land.oasis
	var stop: Vector3 = g.land.keep_out(Vector3(o.x + 90, 20, o.z), Vector3(o.x - 10, 20, o.z))
	check(stop.x > o.x and Vector2(stop.x - o.x, stop.z - o.z).length() >= SurfaceBiomes.SAFE_RADIUS, "stops on the near rim")
	var out: Vector3 = g.land.keep_out(Vector3(o.x, 20, o.z + 10), Vector3(o.x, 20, o.z))
	check(Vector2(out.x - o.x, out.z - o.z).length() > SurfaceBiomes.SAFE_RADIUS, "a hostile inside heads out")
