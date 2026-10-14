extends TestCase

static var _gen: WorldGen


func _world() -> WorldGen:
	if _gen == null:
		_gen = WorldGen.new(WorldGen.Dimension.OVERWORLD, 1234)
		var t := Time.get_ticks_msec()
		_gen.prepare()
		print("      prepare: %d ms, %d locations" % [Time.get_ticks_msec() - t, _gen.locations.size()])
	return _gen


func test_packed_arrays_share_on_assignment() -> void:
	# The mesher relies on this: assigning a packed array shares it.
	var a := PackedInt32Array([1])
	var b := a
	b.append(2)
	check_eq(a.size(), 2, "packed array assignment should share storage")


func test_generation_is_deterministic() -> void:
	var g := _world()
	var k := Vector3i(64, 1, 64)
	check_eq(g.generate_chunk(k), g.generate_chunk(k))


func test_start_village_exists_and_is_dry() -> void:
	var g := _world()
	var found := false
	for loc in g.locations:
		if loc.id == &"emberfall":
			found = true
			check(loc.center.y > WorldGen.SEA_LEVEL, "Emberfall above sea level")
			check(not loc.spawns_of("npc").is_empty(), "Emberfall has NPCs")
	check(found, "Emberfall planned")


func test_every_boss_has_a_spawn() -> void:
	var g := _world()
	var bosses := {}
	for loc in g.locations:
		for s in loc.spawns_of("boss"):
			bosses[s["kind"]] = true
	for kind in ["warden", "mountain_king", "dragon"]:
		check(bosses.has(kind), "boss %s placed" % kind)
	var hell := WorldGen.new(WorldGen.Dimension.HELL, 1234)
	hell.prepare()
	var hell_bosses := {}
	for loc in hell.locations:
		for s in loc.spawns_of("boss"):
			hell_bosses[s["kind"]] = true
	check(hell_bosses.has("cerberus") and hell_bosses.has("hades"), "hell bosses placed")


func test_gate_cavern_is_carved() -> void:
	var g := _world()
	for loc in g.locations:
		if loc.id == &"gates_of_hades":
			var p := Vector3i(loc.center.round()) + Vector3i(0, 4, 10)
			var data := g.generate_chunk(Chunk.key_of(p))
			var l := Chunk.local(p)
			check_eq(data[Chunk.index(l.x, l.y, l.z)], Blocks.AIR, "air inside the gate cavern")


func test_mesher_produces_faces_and_timing() -> void:
	var g := _world()
	var c := Vector3i(64, 1, 64)
	var k := Vector3i(c.x, floori(g.surface_height(c.x * 16 + 8, c.z * 16 + 8) / 16.0), c.z)
	var neighbours := []
	neighbours.resize(27)
	var t0 := Time.get_ticks_usec()
	for dz in range(-1, 2):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				neighbours[(dx + 1) + (dy + 1) * 3 + (dz + 1) * 9] = g.generate_chunk(k + Vector3i(dx, dy, dz))
	var gen_ms := (Time.get_ticks_usec() - t0) / 27000.0
	var surface := PackedInt32Array()
	surface.resize(256)
	surface.fill(1000)
	t0 = Time.get_ticks_usec()
	var result := ChunkMesher.build(neighbours, surface, k.y * 16)
	var mesh_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("      generate: %.2f ms/chunk, mesh: %.2f ms" % [gen_ms, mesh_ms])
	check(result.has("opaque"), "surface chunk has faces")
	var verts: PackedVector3Array = result["opaque"][Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = result["opaque"][Mesh.ARRAY_INDEX]
	check(verts.size() > 0 and idx.size() % 3 == 0, "valid triangles")
