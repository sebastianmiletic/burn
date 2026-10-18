extends TestCase
## Modelled villages and sites: no voxel cubes, walkable doors, valid spawns,
## geometry for every structure.

static var _gen: WorldGen

## Boss arenas still built from blueprints by their own owner.
const BOSS_LOCATIONS := [&"silent_crypt", &"crypt_depths", &"mountain_hall", &"dragons_keep", &"gates_of_hades",
	&"tartarus", &"throne_of_hades", &"drowned_spire", &"weeping_hollow", &"broodmother_lair", &"hagsfen",
	&"kraken_graveyard", &"maw_of_the_sea"]


func _world() -> WorldGen:
	if _gen == null:
		_gen = WorldGen.new(WorldGen.Dimension.OVERWORLD, 1234)
		_gen.prepare()
	return _gen


func test_non_boss_blueprints_write_no_cubes() -> void:
	var g := _world()
	var bad := {}
	for loc in g.locations:
		if loc.id in BOSS_LOCATIONS:
			continue
		for bp in loc.blueprints:
			for v in bp.data:
				if v != Blueprint.KEEP and v != Blueprint.CARVE and (Blocks.family(v) == Blocks.Family.CUBE or Blocks.family(v) == Blocks.Family.SMALL):
					bad[loc.id] = Blocks.name_of(v)
	check(bad.is_empty(), "cube-family blocks in %s" % str(bad))


func test_village_spawns_stand_in_open_cells() -> void:
	var g := _world()
	for id: StringName in [&"emberfall", &"ashford", &"thornwick", &"frosthold", &"mirewatch", &"cinderreach"]:
		var loc := _loc(g, id)
		check(loc != null, "%s planned" % id)
		if loc == null:
			continue
		var roles := {}
		for s: Dictionary in loc.spawns:
			var p: Vector3 = s["pos"]
			if s["type"] in ["npc", "chest", "station"]:
				var cell := _stamped(loc, Vector3i(p.floor()))
				check(cell == Blueprint.KEEP or cell == Blueprint.CARVE, "%s %s spawn at %s is free (got %d)" % [id, s["type"], str(p), cell])
			roles[s.get("role", s.get("station", s["type"]))] = true
		for want in ["elder" if id == &"emberfall" else "chief", "blacksmith", "merchant", "villager", "anvil", "furnace", "workbench", "chest"]:
			check(roles.has(want), "%s has a %s" % [id, want])


func test_enterable_doors_are_carved() -> void:
	var g := _world()
	var loc := _loc(g, &"emberfall")
	var doors := 0
	for p: Dictionary in loc.props:
		if p.get("type", "") != "building" or not p["enterable"] or p["kind"] == "smithy":
			continue
		var floor_y := loc.ground_y + int(p.get("raise", 0.0))
		for i in range(int(p["door"]), int(p["door"]) + int(p["door_w"])):
			for y in [1, 2]:
				var c := VillagePlan.cell_world(p, i, int(p["d"]) - 1, floor_y + y)
				check_eq(_stamped(loc, c), Blueprint.CARVE, "%s doorway open at %s" % [p["role"], str(c)])
				doors += 1
		# The room behind the door is open and floored.
		var inside := VillagePlan.cell_world(p, int(p["door"]), int(p["d"]) - 2, floor_y + 1)
		check_eq(_stamped(loc, inside), Blueprint.CARVE, "%s room open" % p["role"])
		check_eq(_stamped(loc, inside - Vector3i(0, 1, 0)), Blocks.STRUCTURE, "%s floor solid" % p["role"])
	check(doors >= 6, "several enterable buildings (%d door cells)" % doors)


func test_every_structure_builds_geometry() -> void:
	var g := _world()
	var n := 0
	for loc in g.locations:
		if loc.props.is_empty() or loc.id in BOSS_LOCATIONS:
			continue
		var b := ArchBuild.new(g, loc.center, 1)
		Architecture.fill(b, loc)
		check(b.shell.vertex_count() > 300, "%s has modelled geometry" % loc.id)
		check_eq(b.shell.verts.size(), b.shell.uv2s.size(), "%s attributes line up" % loc.id)
		check(b.shell.indices.size() % 3 == 0, "%s triangles" % loc.id)
		var far := ArchBuild.new(g, loc.center, 1)
		far.far_only = true
		Architecture.fill(far, loc)
		n += 1
	check(n >= 20, "villages and sites modelled (%d)" % n)


func test_village_ground_is_clear_of_grass() -> void:
	var g := _world()
	var loc := _loc(g, &"emberfall")
	check(ArchClearings.is_clear(0, g.world_seed, int(loc.center.x) + 3, int(loc.center.z) + 3), "the green is paved")
	check(not ArchClearings.is_clear(0, g.world_seed, int(loc.center.x) + 120, int(loc.center.z) + 3), "open country keeps its grass")


func test_planner_stream_unchanged_by_villages() -> void:
	# Watchtowers sit where the old block villages left the random stream.
	var g := _world()
	var t := _loc(g, &"tower_0")
	check(t != null and Vector2(t.center.x, t.center.z).distance_to(Vector2(1024, 1024)) > 250.0, "tower placed on its ring")


func _loc(g: WorldGen, id: StringName) -> Location:
	for l in g.locations:
		if l.id == id:
			return l
	return null


## The block the location's blueprints stamp at a world cell (KEEP if none).
func _stamped(loc: Location, c: Vector3i) -> int:
	var out := Blueprint.KEEP
	for bp in loc.blueprints:
		var l := c - bp.origin
		var v := bp.get_local(l.x, l.y, l.z)
		if v != Blueprint.KEEP:
			out = v
	return out
