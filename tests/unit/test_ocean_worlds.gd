extends TestCase
## Revision 4 oceans: older revisions generate exactly as before (golden chunk hashes),
## new worlds get ocean biomes with varied sea beds, and no tree ever stands in water.

## Chunks sampled for the golden hashes: land, coast, marsh, fjord, open sea and the deep.
const GOLDEN_KEYS := {
	2: [Vector3i(64, 1, 64), Vector3i(26, 0, 65), Vector3i(156, -1, 156), Vector3i(64, -1, 125), Vector3i(64, 0, 124),
			Vector3i(64, -3, 64), Vector3i(98, 0, 64), Vector3i(6, -1, 64)],
	3: [Vector3i(64, 1, 64), Vector3i(26, 0, 65), Vector3i(218, -1, 218), Vector3i(262, 0, 66), Vector3i(262, -1, 66),
			Vector3i(64, -3, 64), Vector3i(125, -1, 125), Vector3i(78, 1, 163), Vector3i(270, -1, 30), Vector3i(150, -1, 140),
			Vector3i(15, -1, 200), Vector3i(278, 0, 68)],
}
## Recorded from the generator before revision 4 existed (seed 1234).
const GOLDEN := {
	2: "1742671292/1606318894,1199454714/445216907,1477158163/3217204397,507926682/1540810611,283349804/1238695424,3190252623/1535358581,884592225/4225490440,1839358562/1984014490",
	3: "2869317766/1606318894,3421629514/3681642917,1169042361/1682809790,1883801151/1675639835,2792600209/1675639835,549836671/1535358581,289928623/443836410,3843902944/2544374968,3037024169/3964956076,514104974/1425637716,1462057989/4194905917,1883801151/1675639835",
}

static var _gens := {}


static func gen(revision: int, seed_value := 1234) -> WorldGen:
	var key := "%d:%d" % [revision, seed_value]
	if not _gens.has(key):
		var g := WorldGen.new(WorldGen.Dimension.OVERWORLD, seed_value, revision)
		g.prepare()
		_gens[key] = g
	return _gens[key]


static func signature(g: WorldGen, keys: Array) -> String:
	var parts := PackedStringArray()
	for k: Vector3i in keys:
		var r := g.generate(k)
		parts.append("%d/%d" % [hash(r[0]), hash(r[1])])
	return ",".join(parts)


func test_old_revisions_generate_as_before() -> void:
	for rev: int in [2, 3]:
		var sig := signature(gen(rev), GOLDEN_KEYS[rev])
		if GOLDEN[rev] == "":
			print("      golden %d: %s" % [rev, sig])
		check_eq(sig, GOLDEN[rev], "revision %d chunks are unchanged" % rev)


## Trunk bases in sampled chunks: [Vector3i root, block id, chunk data, chunk origin].
static func _tree_roots(g: WorldGen, rng: RandomNumberGenerator, samples: int) -> Array:
	var out: Array = []
	var fam := Blocks.family_table()
	var tried := 0
	while tried < samples:
		var x := rng.randi_range(64, g.size - 64)
		var z := rng.randi_range(64, g.size - 64)
		var h := g.surface_height(x, z)
		var biome := g.biome_at(x, z)
		var lake := g.lake_level(x, z).x > -INF
		# Shores, marshes and lake basins are where a tree could end up in water.
		if absi(h - WorldGen.SEA_LEVEL) > 9 and biome != WorldGen.Biome.MARSH and not lake:
			continue
		tried += 1
		for dy in 2:
			var key := Vector3i(x >> 4, floori(h / 16.0) + dy, z >> 4)
			var data: PackedByteArray = g.generate(key)[0]
			if data.is_empty():
				continue
			var o := key * 16
			for i in Chunk.VOLUME:
				var b := data[i]
				if b == 0 or fam[b] != Blocks.Family.TREE:
					continue
				var ly := i / Chunk.AREA
				if ly > 0 and data[i - Chunk.AREA] == b:
					continue
				var lz := (i % Chunk.AREA) / Chunk.SIZE
				var lx := i % Chunk.SIZE
				out.append([o + Vector3i(lx, ly, lz), b, data, o])
	return out


func test_no_tree_stands_in_water() -> void:
	var rng := RandomNumberGenerator.new()
	var checked := 0
	for spec: Array in [[2, 1234, 60], [3, 1234, 140], [3, 99, 60], [WorldGen.LATEST_REVISION, 4321, 140]]:
		var g := gen(spec[0], spec[1])
		rng.seed = int(spec[1]) * 3 + int(spec[0])
		var bad := 0
		var roots := _tree_roots(g, rng, spec[2])
		for r: Array in roots:
			var root: Vector3i = r[0]
			var data: PackedByteArray = r[2]
			var o: Vector3i = r[3]
			var wet := root.y <= WorldGen.SEA_LEVEL or g.lake_level(root.x, root.z).x >= float(root.y) - 0.5
			# The root cell's neighbours at the same height (inside this chunk) hold no water.
			var l := root - o
			for d: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, -1, 0)]:
				var q := l + d
				if q.x < 0 or q.y < 0 or q.z < 0 or q.x >= 16 or q.y >= 16 or q.z >= 16:
					continue
				var nb := data[q.x + q.z * 16 + q.y * 256]
				if nb == Blocks.WATER or nb == Blocks.ICE:
					wet = true
			if wet:
				bad += 1
				if bad < 4:
					print("      tree in water: rev %d seed %d at %s" % [spec[0], spec[1], str(root)])
		checked += roots.size()
		check_eq(bad, 0, "revision %d seed %d: no trunk base in or under water (%d trees)" % [spec[0], spec[1], roots.size()])
	check(checked > 100, "enough shoreline trees were sampled (%d)" % checked)
