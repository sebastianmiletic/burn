extends TestCase
## Player building: pieces and their items, container slot logic (chests and
## barrels), village well loot, and revision-5 ore veins.


func test_every_piece_registers_an_item_and_recipe() -> void:
	var pairs := BuildPieces.all_pairs()
	check(pairs.size() > 20, "many piece/material pairs")
	for pair: Array in pairs:
		var id := BuildPieces.item_id(String(pair[0]), String(pair[1]))
		check(ItemDB.exists(id), "item for " + id)
		check_eq(BuildPieces.parse(id), pair, "parse round-trips " + id)
		check(BuildPieces.max_hp(String(pair[0]), String(pair[1])) > 0.0, "hp for " + id)


func test_every_piece_builds_a_mesh() -> void:
	for pair: Array in BuildPieces.all_pairs():
		var model := PieceMesh.get_model(String(pair[0]), String(pair[1]))
		var mesh: Mesh = model.get("mesh")
		check(mesh != null and mesh.get_surface_count() > 0, "mesh for %s %s" % [pair[0], pair[1]])
	for kind: String in ["door", "chest", "barrel"]:
		var mats: Array = BuildPieces.PIECES[kind].get("mats", [""])
		var leaves: Array = PieceMesh.get_model(kind, String(mats[0]))["leaves"]
		if kind != "barrel":
			check(not leaves.is_empty(), kind + " has a moving leaf (door / lid)")


func test_containers_have_slots() -> void:
	for kind: String in ["chest", "chest_iron", "barrel"]:
		check_eq(BuildPieces.use_of(kind), "container", kind + " is a container")
		check(BuildPieces.container_slots(kind) >= 18, kind + " has slots")


func test_container_add_merges_then_fills_and_returns_overflow() -> void:
	var slots: Array = [{}, {}, {}]
	check(BuildingWorld.container_add(slots, {"id": "coal", "count": 10}).is_empty(), "fits")
	check(BuildingWorld.container_add(slots, {"id": "coal", "count": 5}).is_empty(), "merges")
	check_eq(int(slots[0]["count"]), 15, "merged into the first stack")
	check(BuildingWorld.container_add(slots, {"id": "torch", "count": 2}, 2).is_empty(), "preferred slot")
	check_eq(String(slots[2]["id"]), "torch", "went into the preferred slot")
	check(BuildingWorld.container_add(slots, {"id": "ruby", "count": 1}).is_empty(), "last free slot")
	var rest := BuildingWorld.container_add(slots, {"id": "pearl", "count": 3})
	check_eq(int(rest.get("count", 0)), 3, "a full container hands the stack back")


func test_sort_merges_stacks() -> void:
	var slots: Array = [{"id": "coal", "count": 3}, {}, {"id": "torch", "count": 1}, {"id": "coal", "count": 4}]
	BuildingWorld.sort_slots(slots)
	var coal := 0
	var filled := 0
	for s: Dictionary in slots:
		if not s.is_empty():
			filled += 1
			if s["id"] == "coal":
				coal += int(s["count"])
	check_eq(coal, 7, "no coal lost")
	check_eq(filled, 2, "coal merged into one stack")
	check((slots[3] as Dictionary).is_empty(), "empties at the end")


func test_well_loot_exists_and_is_mostly_junk() -> void:
	for e: Array in WellEntity.TABLE:
		check(ItemDB.exists(String(e[1])), "well loot item " + String(e[1]))
	var rare := 0
	for i in 1000:
		var r := WellEntity.roll((i + 0.5) / 1000.0)
		check(int(r[1]) >= 1 and int(r[2]) >= int(r[1]), "count range")
		if String(r[0]) in ["silver_ring", "ruby", "sapphire", "amethyst", "pearl", "treasure_map"]:
			rare += 1
	check(rare > 0 and rare < 60, "rare well finds are rare (%d / 1000)" % rare)


func test_revision5_ores_are_small_veins() -> void:
	var g := WorldGen.new(WorldGen.Dimension.OVERWORLD, 1234, 5)
	var ore := {}
	for x in 48:
		for y in range(-40, -8):
			for z in 48:
				var b := g._vein_ore(x, y, z)
				if b != Blocks.AIR:
					ore[Vector3i(x, y, z)] = b
	check(ore.size() > 20, "veins exist (%d ore blocks)" % ore.size())
	# Flood-fill: every vein is small and holds one ore.
	var seen := {}
	var largest := 0
	for start: Vector3i in ore:
		if seen.has(start):
			continue
		var stack: Array[Vector3i] = [start]
		seen[start] = true
		var n := 0
		while not stack.is_empty():
			var c: Vector3i = stack.pop_back()
			n += 1
			for d: Vector3i in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
				var q := c + d
				if ore.has(q) and not seen.has(q) and ore[q] == ore[start]:
					seen[q] = true
					stack.append(q)
		largest = maxi(largest, n)
	check(largest <= 40, "veins stay small (largest %d blocks)" % largest)
	check_eq(g._vein_ore(5, -20, 7), WorldGen.new(WorldGen.Dimension.OVERWORLD, 1234, 5)._vein_ore(5, -20, 7), "deterministic")


func test_old_revisions_keep_ore_lenses() -> void:
	# Revision 4 still fills a lens (o2 > 220) with ore; revision 5 ignores the lens field.
	var g4 := WorldGen.new(WorldGen.Dimension.OVERWORLD, 1234, 4)
	var g5 := WorldGen.new(WorldGen.Dimension.OVERWORLD, 1234, 5)
	var lens4 := 0
	var lens5 := 0
	for x in 16:
		for z in 16:
			var y := -20
			if g4._rock_v3(x, y, z, 30, 0, 128, 0, 240) != g4._rock_v3(x, y, z, 30, 0, 128, 0, 0):
				lens4 += 1
			var plain := g5._rock_v3(x, y, z, 30, 0, 128, 0, 0)
			if g5._rock_v3(x, y, z, 30, 0, 128, 0, 240) != plain:
				lens5 += 1
	check_eq(lens4, 256, "revision 4 lenses are solid ore")
	check_eq(lens5, 0, "revision 5 has no lenses")
