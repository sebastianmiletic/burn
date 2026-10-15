extends TestCase
## Boss battlegrounds: every boss has a modelled arena prop, no boss location
## writes visible cube blocks, arena gates open onto air, and the arena
## builders produce geometry on any seed.

const BOSSES := ["warden", "mountain_king", "dragon", "leviathan", "broodmother", "bog_hag", "cerberus", "hades"]


func _locations(seed_value: int) -> Array[Location]:
	var out: Array[Location] = []
	for dim in [0, 1, 2]:
		var g := WorldGen.new(dim, seed_value if dim == 0 else (seed_value ^ 0x5eed if dim == 1 else seed_value ^ 0x7f17))
		g.prepare()
		out.append_array(g.locations)
	return out


func test_every_boss_has_a_modelled_arena() -> void:
	var locs := _locations(1234)
	var kinds := {}
	var arenas := {}
	for loc in locs:
		for s in loc.spawns_of("boss"):
			kinds[s["kind"]] = loc
		if not ArenaDirector.arena_props(loc).is_empty():
			arenas[loc.id] = true
	for k: String in BOSSES:
		check(kinds.has(k), "%s has a home" % k)
		if kinds.has(k):
			check(arenas.has((kinds[k] as Location).id), "%s's location carries an arena prop" % k)
	check(arenas.has(&"gates_of_hades"), "the Gates of Hades are modelled")
	for id: StringName in [&"ryft_isle_1", &"ryft_isle_2"]:
		check(arenas.has(id), "%s has a crystal arena for its Ryft boss" % id)


func test_boss_blueprints_write_no_cubes() -> void:
	var fam := Blocks.family_table()
	for loc in _locations(1234):
		if ArenaDirector.arena_props(loc).is_empty():
			continue
		var cubes := 0
		for bp in loc.blueprints:
			for v in bp.data:
				if v != Blueprint.KEEP and v != Blueprint.CARVE and (fam[v] == Blocks.Family.CUBE or fam[v] == Blocks.Family.SMALL):
					cubes += 1
		check_eq(cubes, 0, "%s blueprint writes no visible cube blocks" % loc.id)


func test_arena_gates_open_onto_air() -> void:
	for loc in _locations(1234):
		for g in loc.spawns_of("arena_gate"):
			var base := Vector3i((g["pos"] as Vector3).floor())
			var open := 0
			for bp in loc.blueprints:
				var l := base - bp.origin
				var v := bp.get_local(l.x, l.y, l.z)
				if v == Blueprint.CARVE:
					open += 1
				elif v == Blocks.STRUCTURE:
					open -= 100
			check(open >= 0, "%s gate opening is not walled in" % loc.id)


func test_arenas_build_geometry() -> void:
	for loc in _locations(77):
		for p: Dictionary in ArenaDirector.arena_props(loc):
			var b := ArenaBuild.new(p)
			ArenaBuilders.run(b)
			var tris := 0
			for m: Dictionary in b.meshes:
				tris += (m["arrays"][Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			check(tris > 10000, "%s arena has real geometry (%d tris)" % [p["arena"], tris])
			check(tris < 400000, "%s arena stays within budget (%d tris)" % [p["arena"], tris])
			check(not b.lights.is_empty(), "%s arena is lit" % p["arena"])
			check_eq(b.gates.size(), loc.spawns_of("arena_gate").size(), "%s draws every arena gate" % p["arena"])
