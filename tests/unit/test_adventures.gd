extends TestCase
## World revision 5 adventures: Mount Pyrrhos (volcano, Kilnhollow, the
## Emberheart altar), Atlantis with the Kraken, the outer isles; and the sword
## in the stone's countdown rules.

static var _gens := {}


static func _world(revision := WorldGen.LATEST_REVISION) -> WorldGen:
	if not _gens.has(revision):
		var g := WorldGen.new(WorldGen.Dimension.OVERWORLD, 1234, revision)
		g.prepare()
		_gens[revision] = g
	return _gens[revision]


static func _find(g: WorldGen, id: StringName) -> Location:
	for loc in g.locations:
		if loc.id == id:
			return loc
	return null


func test_revision_5_plans_the_adventure_sites() -> void:
	var g := _world()
	for id: StringName in [&"mount_pyrrhos", &"fire_village", &"atlantis", &"atlantis_throne", &"scumport", &"stormbreak", &"hollow_crowns"]:
		check(_find(g, id) != null, "revision 5 plans %s" % id)
	for id: StringName in [&"mount_pyrrhos", &"fire_village", &"atlantis", &"atlantis_throne"]:
		check(_find(_world(4), id) == null, "revision 4 has no %s" % id)
	check(_find(_world(4), &"kraken_graveyard") != null, "revision 4 keeps the Kraken's Graveyard")
	check(_find(g, &"kraken_graveyard") == null, "revision 5 moves the Kraken out of the Graveyard")


func test_volcano_has_a_caldera_lava_lake_and_altar() -> void:
	var g := _world()
	var V := AdventureTerrain.V
	var rim := g.surface_height(int(V.x + AdventureTerrain.RC + 4.0), int(V.y))
	var foot := g.surface_height(int(V.x + AdventureTerrain.R - 20.0), int(V.y))
	var floor_y := g.surface_height(int(V.x - 70.0), int(V.y + 30.0))
	check(rim > foot + 120, "the cone rises well above its foot (rim %d, foot %d)" % [rim, foot])
	check(floor_y < rim - 30, "the caldera floor lies below the rim (floor %d, rim %d)" % [floor_y, rim])
	# The lava lake round the altar island.
	var lake := g.lake_level(V.x + AdventureTerrain.LAKE_R - 10.0, V.y)
	check(lake.x > -INF, "there is a lava lake inside the caldera")
	var volcano := _find(g, &"mount_pyrrhos")
	var village := _find(g, &"fire_village")
	if volcano == null or village == null:
		return
	var adv: Dictionary = volcano.get_meta(&"adv", {})
	check(adv.has("altar"), "the altar is recorded for the sword event")
	var folk: Array = village.get_meta(&"adv", {}).get("fire_folk", [])
	check(folk.size() >= 10, "Kilnhollow has fire folk (%d)" % folk.size())
	for f: Dictionary in folk:
		check(AdventureTerrain.in_caldera(f["pos"]), "fire folk live inside the caldera")
	check(EmberheartEvent.in_blast(adv.get("altar", Vector3.ZERO)), "the altar is inside the blast radius")


func test_kraken_lives_in_atlantis() -> void:
	var g := _world()
	var throne := _find(g, &"atlantis_throne")
	if throne == null:
		check(false, "Atlantis throne planned")
		return
	var bosses := throne.spawns_of("boss")
	check(bosses.size() == 1 and String(bosses[0]["kind"]) == "kraken", "the Kraken's boss spawn is in Atlantis")
	var a := AdventureTerrain.ATLANTIS
	var bed := g.surface_height(int(a.x), int(a.y))
	check(bed < WorldGen.SEA_LEVEL - 60, "Atlantis lies deep under the sea (bed %d)" % bed)


func test_sword_in_the_stone_countdown() -> void:
	var e := EmberheartEvent.new()
	var sword := ItemDB.info(String(EmberheartEvent.ITEM))
	check(float(sword.get("damage", 0.0)) > float(ItemDB.info("sword_gatebreaker")["damage"]), "the Emberheart outclasses Gatebreaker")
	check_eq(int(sword.get("value", -1)), 0, "the Emberheart cannot be sold for gold")
	check(not e.fire_folk_hostile(), "the fire folk are peaceful while the sword sits in the stone")
	check_eq(e.shake(), 0.0, "no shake before the sword is drawn")
	check(e.lava_spew_rate() > 0.0, "lava spits from the cracks")
	check(e.take(7), "the sword can be drawn")
	check(not e.take(8), "only once")
	check(e.fire_folk_hostile(), "drawing it turns the fire folk hostile")
	var s0 := e.shake()
	check(not e.tick(EmberheartEvent.COUNTDOWN * 0.5), "no eruption at half time")
	check(e.shake() > s0, "the shake grows as the countdown runs")
	var saved := e.to_dict()
	check(e.tick(EmberheartEvent.COUNTDOWN), "the volcano erupts when the countdown ends")
	check(not e.tick(1.0), "it erupts once")
	check(not e.holder_escapes(Vector3(AdventureTerrain.V.x, 100, AdventureTerrain.V.y)), "caught at the altar")
	check(e.holder_escapes(Vector3(AdventureTerrain.V.x + AdventureTerrain.R + 50.0, 20, AdventureTerrain.V.y)), "escaped past the foot")
	var r := EmberheartEvent.new()
	r.from_dict(saved)
	check_eq(r.state, EmberheartEvent.State.AWAKENED, "state survives a save")
	check_eq(r.holder, 7, "holder survives a save")
	check_near(r.remaining, EmberheartEvent.COUNTDOWN * 0.5, 0.01, "countdown survives a save")


func test_adventure_spawns_use_known_entity_kinds() -> void:
	var known: Array = EntityFactory.ENEMY_KINDS + EntityFactory.BEAST_KINDS + EntityFactory.BOSS_KINDS
	for id: StringName in [&"mount_pyrrhos", &"fire_village", &"atlantis", &"atlantis_throne", &"scumport", &"scumport_cove", &"stormbreak", &"hollow_crowns"]:
		var loc := _find(_world(), id)
		if loc == null:
			continue
		for type: String in ["enemy", "boss"]:
			for s in loc.spawns_of(type):
				check(String(s["kind"]) in known, "%s spawns a known %s kind (%s)" % [id, type, s["kind"]])
