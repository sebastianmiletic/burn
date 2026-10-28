extends TestCase
## World revision 5 underground: varied cave biomes and the Everbloom cavern; revision 4
## worlds still generate exactly as before.

const KEYS := [Vector3i(64, 1, 64), Vector3i(26, 0, 65), Vector3i(218, -1, 218), Vector3i(262, 0, 66), Vector3i(262, -1, 66),
		Vector3i(64, -3, 64), Vector3i(125, -1, 125), Vector3i(78, 1, 163), Vector3i(270, -1, 30), Vector3i(150, -1, 140),
		Vector3i(15, -1, 200), Vector3i(278, 0, 68), Vector3i(100, -3, 200), Vector3i(200, -4, 100), Vector3i(180, -2, 180)]
## Recorded from main (2688851) before the revision 5 underground was merged (seed 1234).
const GOLDEN_4 := "2869317766/1606318894,3421629514/3681642917,3891204306/270247331,3933628830/3678062242,2792600209/1675639835,549836671/1535358581,1253118892/2937777524,3843902944/2544374968,737007427/1795602131,3430463094/765275876,2202956221/1669863527,3197534486/2543116718,1476762337/736133098,819928885/905582339,1675639835/1675639835"


func test_revision_4_generates_as_before() -> void:
	var g := WorldGen.new(WorldGen.Dimension.OVERWORLD, 1234, 4)
	g.prepare()
	check(CaveBiomes.zones.is_empty(), "revision 4 plans no underground zones")
	var parts := PackedStringArray()
	for k: Vector3i in KEYS:
		var r := g.generate(k)
		parts.append("%d/%d" % [hash(r[0]), hash(r[1])])
	check_eq(",".join(parts), GOLDEN_4, "revision 4 chunks are unchanged")


func test_revision_5_cave_biomes_vary() -> void:
	var kinds := {}
	var shapes := {}
	var old_new_kinds := 0
	for kz in 16:
		for kx in 16:
			for ky in [-1, -2]:
				var p := (Vector3(kx, ky, kz) + Vector3(0.5, 0.5, 0.5)) * CaveBiomes.CELL
				var r := CaveBiomes.region(p, 777, 5)
				kinds[int(r["kind"])] = true
				shapes[CaveBiomes.radii_of(r)] = true
				if int(CaveBiomes.region(p, 777, 4)["kind"]) >= CaveBiomes.Kind.LUSH:
					old_new_kinds += 1
	check_eq(old_new_kinds, 0, "revision 4 never picks a revision 5 cave biome")
	for k in [CaveBiomes.Kind.LUSH, CaveBiomes.Kind.DRIPSTONE, CaveBiomes.Kind.OCHRE, CaveBiomes.Kind.VERDIGRIS, CaveBiomes.Kind.VIOLET]:
		check(kinds.has(k), "cave biome %s appears" % CaveBiomes.NAMES[k])
	check(shapes.size() >= 4, "chambers come in several shapes (%d)" % shapes.size())
	# Each new biome lines its walls with its own rock, not plain limestone.
	for k in [CaveBiomes.Kind.LUSH, CaveBiomes.Kind.OCHRE, CaveBiomes.Kind.VERDIGRIS, CaveBiomes.Kind.VIOLET, CaveBiomes.Kind.SANDSTONE]:
		var rocks := {}
		for i in 40:
			rocks[CaveBiomes.scheme_block(k, Vector3i(i, i, 0), i % 2 == 0, i * 7)] = true
		check(not rocks.has(Blocks.STONE), "%s is not grey stone" % CaveBiomes.NAMES[k])
		check(rocks.size() >= 2, "%s mixes rocks" % CaveBiomes.NAMES[k])


func test_everbloom_cavern_and_harvest() -> void:
	var g := WorldGen.new(WorldGen.Dimension.OVERWORLD, 1234, 5)
	g.prepare()
	var loc: Location = null
	for l in g.locations:
		if l.id == UndergroundSites.EVERBLOOM_ID:
			loc = l
	check(loc != null, "a revision 5 world has the Everbloom cavern")
	check(not CaveBiomes.zones.is_empty(), "revision 5 plans underground zones")
	if loc == null:
		return
	var trees := loc.spawns_of("entity")
	check_eq(trees.size(), 1, "one Everbloom tree")
	check_eq(String(trees[0].get("kind", "")), "ug_everbloom", "the tree's entity kind")
	var f := loc.center
	check_eq(g.cave_name_at(f + Vector3(0, 4, 0)), "The Everbloom Cavern", "the cavern is named")
	# Open air over a moss floor around the tree.
	var p := Vector3i(roundi(f.x) + 12, roundi(f.y) + 3, roundi(f.z))
	var fl := Vector3i(p.x, roundi(f.y) - 1, p.z)
	var chunk := g.generate(Chunk.key_of(p))[0] as PackedByteArray
	var local := p - Chunk.key_of(p) * Chunk.SIZE
	check_eq(int(chunk[Chunk.index(local.x, local.y, local.z)]), Blocks.AIR, "air inside the cavern")
	var chunk2 := g.generate(Chunk.key_of(fl))[0] as PackedByteArray
	var l2 := fl - Chunk.key_of(fl) * Chunk.SIZE
	check_eq(int(chunk2[Chunk.index(l2.x, l2.y, l2.z)]), Blocks.CAVE_MOSS, "moss floor")
	# The tree entity and its harvest.
	var tree := EntityFactory.create("ug_everbloom")
	check(tree is Everbloom, "factory makes the Everbloom")
	tree.free()
	var all := Everbloom.harvest_yield(100.0, 0.0, 0.0, 0.0)
	check_eq(all, {"everbloom_leaf": 3, "everbloom_fruit": 1, "everbloom_sap": 1}, "first harvest gives leaves, fruit and sap")
	var later := Everbloom.harvest_yield(130.0, 120.0, 100.0 + Everbloom.FRUIT_REGROW, 100.0 + Everbloom.SAP_REGROW)
	check_eq(later, {"everbloom_leaf": 3}, "fruit and sap regrow slowly")
	for item in ["everbloom_leaf", "everbloom_fruit", "everbloom_sap"]:
		check(ItemDB.exists(item), "item %s exists" % item)
