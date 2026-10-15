extends TestCase

func test_material_table_is_complete() -> void:
	check_eq(Blocks.DATA.size(), Blocks.COUNT, "every persisted material has a definition")
	check_eq(Blocks.family(Blocks.STRUCTURE), Blocks.Family.STRUCTURE)
	for b in [Blocks.IRONWOOD_TRUNK, Blocks.EMBERWOOD_TRUNK, Blocks.RYFTWOOD_TRUNK]:
		check_eq(Blocks.family(b), Blocks.Family.TREE)
		check(ItemDB.ITEMS.has(Blocks.drop(b)), "rare wood has an inventory item")
	check(not Blocks.is_breakable(-1), "unloaded data is never mineable")

func test_rare_woods_require_upgraded_tools() -> void:
	check(not ItemDB.can_mine("axe_wood", Blocks.IRONWOOD_TRUNK))
	check(ItemDB.can_mine("axe_iron", Blocks.IRONWOOD_TRUNK))
	check(not ItemDB.can_mine("axe_iron", Blocks.EMBERWOOD_TRUNK))
	check(ItemDB.can_mine("axe_steel", Blocks.EMBERWOOD_TRUNK))
	check(not ItemDB.can_mine("axe_steel", Blocks.RYFTWOOD_TRUNK))
	check(ItemDB.can_mine("axe_mithril", Blocks.RYFTWOOD_TRUNK))

func test_cave_regions_and_refuges() -> void:
	var counts := {}
	for z in 32:
		for x in 32:
			var p := Vector3(x * 128 + 64, -32, z * 128 + 64)
			var r := CaveBiomes.region(p, 1234)
			var k := int(r["kind"])
			counts[k] = int(counts.get(k, 0)) + 1
			check_eq(CaveBiomes.region(p, 1234), r, "region deterministic")
			check_eq(CaveBiomes.kind_at(p, 1234), k)
			if k == CaveBiomes.Kind.CRYSTAL_REFUGE:
				check(CaveBiomes.sanctuary(p, 1234))
				check(not CaveBiomes.sanctuary(p + Vector3(63, 0, 0), 1234))
	check_eq(counts.size(), 5, "all five biomes occur")
	check(int(counts[CaveBiomes.Kind.CRYSTAL_REFUGE]) < 80, "sanctuaries are rare")

func test_ryft_islands_have_air_below_and_connected_paths() -> void:
	for island: Vector4 in WorldGen.RYFT_ISLANDS:
		var span := WorldGen.ryft_column(Vector2(island.x, island.y))
		check(span.x > 50 and span.y > 0 and span.y < span.x, "floating land has two surfaces")
	check(WorldGen.ryft_column(Vector2(20, 20)).x < 0, "empty sky beyond islands")
	for i in range(1, WorldGen.RYFT_ISLANDS.size()):
		var target: Vector4 = WorldGen.RYFT_ISLANDS[i]
		for step in 20:
			var p := Vector2(320, 320).lerp(Vector2(target.x, target.y), step / 19.0)
			check(WorldGen.ryft_column(p).x >= 0, "walkable path to every isle")

func test_network_rejects_malformed_state() -> void:
	check(not Replicator.valid_player_state([]))
	var state := [0, Vector3(1024, 24, 1024), 0.0, 0, 0.0, "sword_rusty", 100.0, 100.0, 0, "Test", false]
	check(Replicator.valid_player_state(state))
	state[1] = Vector3(NAN, 0, 0)
	check(not Replicator.valid_player_state(state))
	state[1] = Vector3.ZERO
	state[6] = INF
	check(not Replicator.valid_player_state(state))

func test_endgame_has_balanced_reward_and_followup() -> void:
	check_eq(QuestDB.main_quest("throne")["next"], "ryft")
	check(not QuestDB.main_quest("ryft").is_empty())
	check_eq(int(ItemDB.info("sword_gatebreaker")["value"]), 0, "unique reward cannot create gold")

func test_updater_versions() -> void:
	check(Updater.compare("v0.4.0", "0.3.9") > 0)
	check_eq(Updater.compare("0.4.0", "v0.4.0"), 0)
	check(Updater.compare("1.10.0", "1.9.0") > 0)
