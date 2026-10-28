extends TestCase
## Revision 5 Dark Ocean: far from every coast the open sea turns into the Dark Ocean
## (deeper, its own name, map mark and shader mood); revision 4 worlds never get it.
## Its wildlife (anglers, eels, and the roaming kraken and leviathan, which are
## ordinary mobs on the boss models) spawns only there, notices, attacks, roams,
## leashes and dies like any beast, and never touches the boss machinery.

const OceanTests := preload("res://tests/unit/test_ocean_worlds.gd")
const CreatureSim := preload("res://tests/unit/test_creature_sim.gd")
const WANDERERS := ["abyssal_kraken", "deep_leviathan", "anglerfish", "abyssal_eel"]


## [dark cells, mean dark depth, mean grey depth, a dark point, a non-dark sea point]
static func _survey(g: WorldGen) -> Array:
	var dark := 0
	var dark_depth := 0.0
	var grey := 0
	var grey_depth := 0.0
	var dark_at := Vector2.INF
	var sea_at := Vector2.INF
	for z in range(8, g.size, 24):
		for x in range(8, g.size, 24):
			var sk := g.ocean_kind_at(x, z)
			if sk == WorldGen.Sea.DARK:
				dark += 1
				dark_depth += WorldGen.SEA_LEVEL - g.smooth_height(x, z)
				if not dark_at.is_finite() and g.dark_ocean_amount(x, z) >= 1.0:
					dark_at = Vector2(x, z)
			elif sk in [WorldGen.Sea.GREY, WorldGen.Sea.SHELF]:
				grey += 1
				grey_depth += WorldGen.SEA_LEVEL - g.smooth_height(x, z)
				if not sea_at.is_finite() and g.dark_ocean_amount(x, z) == 0.0:
					sea_at = Vector2(x, z)
	return [dark, dark_depth / maxf(1.0, dark), grey_depth / maxf(1.0, grey), dark_at, sea_at]


func test_dark_ocean_only_in_new_worlds() -> void:
	var g := OceanTests.gen(WorldGen.LATEST_REVISION, 4321)
	var s := _survey(g)
	print("      dark ocean: %d cells (24 m grid), mean depth %.0f m vs grey sea %.0f m" % [s[0], s[1], s[2]])
	check(int(s[0]) > 200, "the Dark Ocean covers a real area (%d samples)" % s[0])
	check(float(s[1]) > float(s[2]) + 12.0, "the Dark Ocean is much deeper than the grey sea (%.0f vs %.0f m)" % [s[1], s[2]])
	check((s[3] as Vector2).is_finite(), "a point deep in the Dark Ocean exists")
	var p: Vector2 = s[3]
	check_eq(g.region_name(p.x, p.y), "The Dark Ocean", "the HUD names it")
	check_eq(g.ocean_kind_at(p.x, p.y), g.sea_at(p.x, p.y), "ocean_kind_at agrees with sea_at")
	check_eq(g.ocean_kind_at(1024, 1024), WorldGen.Sea.NONE, "land has no ocean kind")
	check_near(g.dark_ocean_amount(p.x, p.y), 1.0, 0.001, "full darkness deep in it")
	check_eq(g.dark_ocean_amount(1024, 1024), 0.0, "no darkness on land")
	# Kept clear of the outer isles and Atlantis.
	for key: String in AdventureTerrain.ISLES:
		var c: Vector2 = AdventureTerrain.ISLES[key][0]
		check(g.ocean_kind_at(c.x, c.y) != WorldGen.Sea.DARK, "%s is not in the Dark Ocean" % key)
	check(g.ocean_kind_at(AdventureTerrain.ATLANTIS.x, AdventureTerrain.ATLANTIS.y) != WorldGen.Sea.DARK, "Atlantis keeps its trench")
	# Older worlds: no Dark Ocean anywhere, no darkness.
	var old := OceanTests.gen(4, 4321)
	check_eq(int(_survey(old)[0]), 0, "revision 4 worlds have no Dark Ocean")
	check_eq(old.dark_ocean_amount(p.x, p.y), 0.0, "revision 4: no darkness")
	check(WorldGen.SEA_NAMES.size() == WorldGen.Sea.size() and WorldGen.SEA_COLORS.size() == WorldGen.Sea.size()
			and WorldGen.SEA_SHAPE.size() == WorldGen.Sea.size(), "every ocean kind has a name, colour and shape")


func test_dark_ocean_seabed_and_mood() -> void:
	var g := OceanTests.gen(WorldGen.LATEST_REVISION, 4321)
	var p: Vector2 = _survey(g)[3]
	if not p.is_finite():
		return
	# Dark mud / basalt / obsidian floor.
	var h := g.surface_height(int(p.x), int(p.y))
	var data: PackedByteArray = g.generate(Vector3i(int(p.x) >> 4, floori(h / 16.0), int(p.y) >> 4))[0]
	check(data.find(Blocks.BASALT) >= 0 or data.find(Blocks.MUD) >= 0 or data.find(Blocks.OBSIDIAN) >= 0, "the Dark Ocean floor is black rock and mud")
	# The shader mood eases in and out and is published as a global.
	OceanMood.reset(0.0)
	for i in 40:
		OceanMood.update(g, Vector3(p.x, 5.0, p.y), 0, 0.25)
	check(OceanMood.dark > 0.99, "dark_ocean_amount reaches 1 out there (%.2f)" % OceanMood.dark)
	check_eq(OceanMood.kind, WorldGen.Sea.DARK, "the mood knows the ocean kind")
	# (The headless dummy renderer keeps no globals; a real one reads back the value.)
	var sent: Variant = RenderingServer.global_shader_parameter_get(OceanMood.PARAM)
	check(sent == null or absf(float(sent) - 1.0) < 0.01, "shader global set (%s)" % str(sent))
	check(ProjectSettings.has_setting("shader_globals/dark_ocean_amount"), "dark_ocean_amount is a registered shader global")
	OceanMood.update(g, Vector3(1024, 30, 1024), 0, 0.5)
	check(OceanMood.dark < 1.0 and OceanMood.dark > 0.5, "it fades out slowly on leaving (%.2f)" % OceanMood.dark)
	OceanMood.update(g, Vector3(p.x, 5.0, p.y), 1, 0.25)
	check_eq(OceanMood.kind, WorldGen.Sea.NONE, "other dimensions have no ocean kind")
	OceanMood.reset(0.0)
	# The map tells it apart from the other seas.
	var sym := MapIcons.biome_symbol(MapIcons.DARK_OCEAN)
	check(sym[0] != MapIcons.biome_symbol(WorldGen.Biome.OCEAN)[0], "the Dark Ocean has its own map mark")


func test_dark_spawn_table() -> void:
	var g := OceanTests.gen(WorldGen.LATEST_REVISION, 4321)
	var s := _survey(g)
	var dark: Vector2 = s[3]
	var sea: Vector2 = s[4]
	check(WildSpawner.is_dark_ocean(g, Vector3(dark.x, 0, dark.y)), "spawner sees the Dark Ocean")
	check(WildSpawner.water_table(g, Vector3(dark.x, 0, dark.y)) == WildSpawner.DARK_WATER, "dark table out there")
	check(WildSpawner.water_table(g, Vector3(sea.x, 0, sea.y)) == WildSpawner.WATER, "ordinary table on the grey sea")
	check(WildSpawner.water_table(OceanTests.gen(4, 4321), Vector3(dark.x, 0, dark.y)) == WildSpawner.WATER, "revision 4: ordinary table")
	var dark_kinds: Array = []
	for row: Array in WildSpawner.DARK_WATER:
		dark_kinds.append(row[0])
		check(WildSpawner.swim_depth(row[0]) >= 2, "%s spawns in water" % row[0])
	for kind: String in WildSpawner.DARK_ONLY:
		check(kind in dark_kinds, "%s is in the Dark Ocean table" % kind)
		for row: Array in WildSpawner.WATER:
			check(row[0] != kind, "%s not in the ordinary sea table" % kind)
		for table: Dictionary in [WildSpawner.SURFACE_DAY, WildSpawner.SURFACE_NIGHT]:
			for b in table:
				for row: Array in table[b]:
					check(row[0] != kind, "%s not on land" % kind)
	for kind: String in WildSpawner.GIANTS:
		check(WildSpawner.swim_depth(kind) >= 10, "%s needs deep water" % kind)
		var weight := 0.0
		for row: Array in WildSpawner.DARK_WATER:
			if row[0] == kind:
				weight = row[1]
		check(weight > 0.0 and weight <= 0.1, "%s is rare (weight %.2f)" % [kind, weight])
	check(WildSpawner.GIANT_CAP == 1, "one giant at a time near a swimmer")


func test_wanderers_are_mobs_not_bosses() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root.get_node_or_null("Events") == null or tree.root.get_node_or_null("Audio") == null:
		print("      (dark ocean mob sim skipped: autoloads are not running)")
		return
	for kind: String in WANDERERS:
		check(not kind in EntityFactory.BOSS_KINDS, "%s is not a boss kind" % kind)
		check(Damage.RESIST.has(kind), "%s has a damage row" % kind)
		check(not QuestDB.boss_available({"boss_kind": kind}), "%s can't stand in for a boss quest" % kind)
		var sim: RefCounted = CreatureSim.SimWorld.new()
		var arena := Node3D.new()
		tree.root.add_child(arena)
		var player := _player(arena, Vector3(0, 0, 8))
		sim.players.append(player)
		var e: Node3D = EntityFactory.create(kind)
		check(e != null and e is Beast and not e is Boss, "%s is an ordinary beast" % kind)
		if e == null:
			arena.queue_free()
			continue
		e.sim_world = sim
		e.net_id = 61
		arena.add_child(e)
		e.global_position = Vector3.ZERO
		e.spawn_point = Vector3.ZERO
		e.body.gravity = 0.0
		check(e.model != null, "%s has a model" % kind)
		if kind == "abyssal_kraken":
			check(e.model is KrakenModel and (e.model as KrakenModel).roaming and (e.model as KrakenModel).k < 0.5, "the kraken wanderer is a small roaming kraken model")
		if kind == "deep_leviathan":
			check(e.model is LeviathanModel and (e.model as LeviathanModel).k < 1.0, "the leviathan wanderer is a smaller leviathan model")
		var dt := 1.0 / 30.0
		# Roams when nobody is near.
		player.global_position = Vector3(0, 0, 400)
		var wandered := 0.0
		while sim.now < 30.0:
			sim.now += dt
			e.server_tick(dt)
			wandered = maxf(wandered, Vector2(e.global_position.x, e.global_position.z).length())
		check(wandered > 2.0, "%s roams (%.1f m from home)" % [kind, wandered])
		# Hunts a swimmer.
		e.global_position = Vector3.ZERO
		player.global_position = Vector3(0, 0, 8)
		var noticed := false
		var t_end: float = sim.now + 25.0
		while sim.now < t_end:
			sim.now += dt
			e.server_tick(dt)
			e._process(dt)
			if e._target != null:
				noticed = true
		check(noticed, "%s noticed the swimmer" % kind)
		check(sim.hits.size() > 0, "%s attacked (%d hits)" % [kind, sim.hits.size()])
		check(not sim.started and sim.resets == 0, "%s never starts a boss fight" % kind)
		check(e.get("phase") == null and not e.has_method("boss_bar"), "%s has no boss bar" % kind)
		# Leashes, dies, despawns.
		player.global_position = Vector3(0, 0, 120)
		e.global_position = Vector3(0, 0, 45)
		for i in 60:
			e.server_tick(dt)
		check_eq(e.state, 7, "%s returns home when pulled away" % kind)
		e.take_damage(e.max_health * 10.0, 7, "hit")
		check(e.dead, "%s died" % kind)
		for i in 150:
			e.server_tick(dt)
		check(sim.despawned, "%s despawned after dying" % kind)
		check(not sim.finished, "%s's death is no boss kill" % kind)
		arena.queue_free()


func _player(arena: Node3D, pos: Vector3) -> Node3D:
	var entity_script: GDScript = load("res://entities/entity.gd")
	var player: Node3D = entity_script.new()
	player.team = 0
	player.net_id = 7
	player.max_health = 1e9
	player.health = 1e9
	player.hit_radius = 0.4
	player.hit_height = 1.8
	arena.add_child(player)
	player.global_position = pos
	return player
