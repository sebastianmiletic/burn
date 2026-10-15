extends TestCase
## Activity rules that do not need a running game: treasure riddles and
## spots, chest loot within the economy, bounty contracts and elite scaling,
## Proving Ring escalation, the meteor crater's shape, weather charms, the
## new items (models, recipes), quest markers and saving activity progress.

static var _gen: WorldGen


func _world() -> WorldGen:
	if _gen == null:
		_gen = WorldGen.new(WorldGen.Dimension.OVERWORLD, 1234)
		_gen.prepare()
	return _gen


func test_treasure_riddles_lead_to_open_ground() -> void:
	var g := _world()
	var start := Vector3(1024, 20, 1048)
	var seen := {}
	for s in 25:
		var hunt := TreasureHunt.generate(g, g.locations, start, s * 977)
		check(not hunt.is_empty(), "seed %d makes a hunt" % s)
		if hunt.is_empty():
			continue
		var spot: Vector3 = hunt["spot"]
		check(TreasureHunt.spot_ok(g, g.locations, spot.x, spot.z), "the X is on dry open ground")
		check(g.surface_height(int(spot.x), int(spot.z)) >= WorldGen.SEA_LEVEL + 1, "not under water")
		var lm: Vector3 = hunt["landmark_pos"]
		var paces := Vector2(spot.x - lm.x, spot.z - lm.z).length()
		check(paces > 10.0 and paces < 80.0, "the X is near the landmark (%.0f m)" % paces)
		check(String(hunt["clue"]).contains(String(hunt["landmark_name"])), "the riddle names the landmark")
		check(int(hunt["tier"]) >= 1 and int(hunt["tier"]) <= 3, "tier in range")
		seen[hunt["landmark"]] = true
	check(seen.size() >= 5, "riddles send you to many places (%d)" % seen.size())


func test_riddle_bearing_matches_the_spot() -> void:
	var g := _world()
	var hunt := TreasureHunt.generate(g, g.locations, Vector3(1024, 20, 1048), 4242)
	var lm: Vector3 = hunt["landmark_pos"]
	var spot: Vector3 = hunt["spot"]
	var deg := fposmod(rad_to_deg(atan2(spot.x - lm.x, -(spot.z - lm.z))), 360.0)
	var word: String = TreasureHunt.DIRS[int(round(deg / 45.0)) % 8]
	check(String(hunt["clue"]).contains(" %s," % word), "clue says %s (%s)" % [word, hunt["clue"]])


func test_chest_loot_fits_the_economy() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for tier in [1, 2, 3]:
		var total := 0.0
		var maps := 0
		for i in 400:
			var l := TreasureHunt.roll_loot(tier, rng)
			var value := int(l["gold"])
			for item: String in l["items"]:
				check(ItemDB.exists(item), "loot item exists: " + item)
				value += int(ItemDB.info(item).get("value", 0)) * int(l["items"][item])
			total += value
			if l["items"].has("treasure_map"):
				maps += 1
		var avg := total / 400.0
		# A chest is worth a good evening, not a fortune: compare the iron sword (~90).
		check(avg > 60.0 * tier and avg < 260.0 * tier, "tier %d chest averages %.0f gold of value" % [tier, avg])
		check(maps > 80 and maps < 200, "tier %d chests chain into new maps often (%d/400)" % [tier, maps])


func test_bounty_contracts_and_elites() -> void:
	var g := _world()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var kinds := {}
	for i in 30:
		var c := Bounties.make_contract(g, g.locations, i + 1, rng)
		check(not c.is_empty(), "contract %d generated" % i)
		if c.is_empty():
			continue
		kinds[c["mob"]] = true
		check(EntityFactory.BEAST_KINDS.has(c["mob"]) or EntityFactory.ENEMY_KINDS.has(c["mob"]), "quarry kind exists: " + String(c["mob"]))
		check(ItemDB.exists(String(c["trophy"])), "trophy exists")
		check(int(c["gold"]) >= 70 and int(c["gold"]) <= 240, "reward %d gold" % int(c["gold"]))
		var den: Vector3 = c["den"]
		var area: Vector3 = c["area"]
		if c["type"] == "hunt":
			var gap := Vector2(den.x - area.x, den.z - area.z).length()
			check(gap > 20.0 and gap < 40.0, "a hunt's den is beyond its last-seen area (%.0f m)" % gap)
		else:
			check(den == area, "an elite's lair is marked exactly")
	check(kinds.size() >= 5, "varied quarry (%d kinds)" % kinds.size())
	var solo := Bounties.elite_scale(1, 1)
	var party := Bounties.elite_scale(1, 3)
	check(float(solo["health"]) >= 4.0, "elites are much tougher than their kin")
	check(float(party["health"]) > float(solo["health"]), "elites scale with the party")
	check(float(Bounties.elite_scale(3, 1)["damage"]) > float(solo["damage"]), "higher tiers bite harder")


func test_proving_ring_escalates() -> void:
	var prev := 0
	var counts := []
	for wave in range(1, 16):
		var n := 0
		var champs := 0
		for e: Array in ProvingGrounds.wave_plan(wave, 1):
			n += int(e[1])
			if e[2]:
				champs += 1
			check(EntityFactory.BEAST_KINDS.has(e[0]) or EntityFactory.ENEMY_KINDS.has(e[0]), "wave monster exists: " + String(e[0]))
		counts.append(n)
		if wave % 5 == 0:
			check(champs >= 1, "wave %d has a champion" % wave)
	check(counts[14] > counts[0], "late waves are bigger (%s)" % str(counts))
	var party := 0
	for e: Array in ProvingGrounds.wave_plan(3, 3):
		party += int(e[1])
	check(party > counts[2], "a party faces more monsters")
	for w: int in ProvingGrounds.MILESTONES:
		check(ItemDB.exists(ProvingGrounds.MILESTONES[w]), "milestone reward exists")
	prev = prev


func test_crater_buries_the_core_under_soft_ash() -> void:
	var site := Vector3(100.5, 30.0, 100.5)
	var ch := WorldEvents.crater_changes(site, 5)
	check(ch.size() % 5 == 0 and ch.size() > 500, "crater edits generated (%d)" % (ch.size() / 5))
	var ore := 0
	var air_bowl := 0
	var above_core_soft := true
	for i in range(0, ch.size(), 5):
		var p := Vector3(ch[i], ch[i + 1], ch[i + 2]) + Vector3(0.5, 0.5, 0.5)
		var b := ch[i + 3]
		if b in [Blocks.IRON_ORE, Blocks.SILVER_ORE, Blocks.GOLD_ORE, Blocks.MITHRIL_ORE, Blocks.CRYSTAL, Blocks.AMETHYST]:
			ore += 1
		if b == Blocks.AIR and p.y > site.y - 1.0 and Vector2(p.x - site.x, p.z - site.z).length() < 2.0:
			air_bowl += 1
		# Straight above the core, up to the bowl floor: diggable with any pick.
		if Vector2(p.x - site.x, p.z - site.z).length() < 0.8 and p.y > site.y - 2.0 and p.y < site.y - 1.3 and b != Blocks.AIR:
			above_core_soft = above_core_soft and Blocks.tier(b) <= 2
	check(ore >= 15, "star-ore in the crater (%d)" % ore)
	check(air_bowl >= 8, "a bowl is blasted out")
	check(above_core_soft, "the core is reachable with a stone pickaxe")


func test_weather_charms_are_usable_items() -> void:
	for id: String in ["storm_horn", "sunstone", "fog_lantern", "frost_totem"]:
		var inf := ItemDB.info(id)
		check(inf.get("category", "") == "consumable" and WeatherCraft.CHARMS.has(String(inf.get("buff", ""))), id + " is a usable charm")
		check(ItemDB.RECIPES.has(id), id + " can be crafted")
	var inv := Inventory.new()
	inv.add("storm_horn", 1)
	inv.apply_consumable("storm_horn")
	check(inv.buff_active("storm_call"), "using the horn starts its effect")
	check(inv.defense() == 0.0, "charms do not change armour")


func test_new_items_have_models_and_recipes() -> void:
	for id: String in ItemDB.ITEMS:
		var inf := ItemDB.info(id)
		if not inf.has("model_script"):
			continue
		var root := Node3D.new()
		check(ActivityItems.build(root, id), id + " has a bespoke model (not the cube fallback)")
		check(root.get_child_count() > 0, id + " model has parts")
		root.free()
	for rid: String in ["pickaxe_starfall", "sword_starfall"]:
		for input: String in ItemDB.recipe(rid)["inputs"]:
			check(ItemDB.exists(input), "%s input %s exists" % [rid, input])
	check(int(ItemDB.SHOP.get("treasure_map", 0)) > 0, "the trader sells maps")
	check(ItemDB.type_label("treasure_map") == "Treasure map", "maps are labelled")


func test_activity_progress_saves_with_the_character() -> void:
	var q := QuestLog.new()
	q.accept("kindling")
	q.activity["treasure"] = {"active": {"id": 3, "stage": "search", "spot": Vector3(1, 2, 3)}, "found": 4, "seq": 3}
	var copy := QuestLog.new()
	copy.from_dict(q.to_dict())
	check_eq(int(copy.activity["treasure"]["found"]), 4, "treasures found survive")
	check_eq(copy.activity["treasure"]["active"]["spot"], Vector3(1, 2, 3), "an unfinished hunt survives")
	var old := QuestLog.new()
	old.from_dict({"active": {"no_such_quest": {"progress": [0], "tracked": true}}, "completed": []})
	check(not old.is_active("no_such_quest"), "saves from other versions drop unknown quests safely")
	check(q.markers().is_empty() or GameWorld.instance != null, "markers need a world")
