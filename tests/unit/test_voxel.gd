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


func _neighbours(g: WorldGen, k: Vector3i, cache: Dictionary) -> Array:
	var blocks := []
	var dens := []
	blocks.resize(27)
	dens.resize(27)
	for dz in range(-1, 2):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n := k + Vector3i(dx, dy, dz)
				if not cache.has(n):
					cache[n] = g.generate(n)
				var r: Array = cache[n]
				blocks[(dx + 1) + (dy + 1) * 3 + (dz + 1) * 9] = r[0]
				dens[(dx + 1) + (dy + 1) * 3 + (dz + 1) * 9] = r[1]
	return [blocks, dens]


func _smooth_mesh(g: WorldGen, k: Vector3i, cache: Dictionary) -> Dictionary:
	var nb := _neighbours(g, k, cache)
	var surface := PackedInt32Array()
	surface.resize(256)
	surface.fill(1000)
	var biomes := PackedByteArray()
	biomes.resize(256)
	return SmoothMesher.build(nb[0], nb[1], surface, biomes, k * 16, 0)


func test_smooth_terrain_mesh_and_seams() -> void:
	var g := _world()
	var c := Vector3i(64, 1, 64)
	var k := Vector3i(c.x, floori((g.surface_height(c.x * 16 + 8, c.z * 16 + 8) + 1) / 16.0), c.z)
	var cache := {}
	var t0 := Time.get_ticks_usec()
	var a := _smooth_mesh(g, k, cache)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	check(a.has("terrain"), "surface chunk has a smooth surface")
	if not a.has("terrain"):
		return
	var va: PackedVector3Array = a["terrain"][Mesh.ARRAY_VERTEX]
	print("      smooth mesh: %.2f ms, %d triangles" % [ms, va.size() / 3])
	check(va.size() % 3 == 0 and va.size() > 30, "valid triangles")
	var inside := true
	for v in va:
		if v.x < -1.0 or v.x > 17.0 or v.z < -1.0 or v.z > 17.0:
			inside = false
	check(inside, "vertices stay within the chunk's cells")
	# Seams: vertices on the shared border of two neighbouring chunks coincide.
	var b := _smooth_mesh(g, k + Vector3i(1, 0, 0), cache)
	if b.has("terrain"):
		var vb: PackedVector3Array = b["terrain"][Mesh.ARRAY_VERTEX]
		var border := {}
		for v in vb:
			if v.x < 0.5:
				border[Vector3i((v + Vector3(16, 0, 0)) * 1000.0)] = true
		var shared := 0
		var matched := 0
		for v in va:
			if v.x > 15.5 and v.x < 16.5:
				shared += 1
				if border.has(Vector3i(v * 1000.0)):
					matched += 1
		check(shared == 0 or matched * 10 >= shared * 9, "border vertices shared (%d/%d)" % [matched, shared])


func test_density_matches_blocks() -> void:
	var g := _world()
	var k := Vector3i(64, 1, 64)
	var r := g.generate(k)
	var blocks: PackedByteArray = r[0]
	var dens: PackedByteArray = r[1]
	if dens.is_empty():
		return
	var bad := 0
	for i in Chunk.VOLUME:
		var smooth := Blocks.is_smooth(blocks[i])
		if smooth and dens[i] < 128:
			bad += 1
	check_eq(bad, 0, "smooth solid voxels have density >= 128")


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
	# Villages are modelled now (no crisp cubes): set a few legacy cubes, as an old save could hold.
	var centre: PackedByteArray = neighbours[13]
	if centre.is_empty():
		centre = Chunk.empty()
	for i in 16:
		centre[i + 8 * Chunk.SIZE + 8 * Chunk.AREA] = Blocks.PLANKS
	neighbours[13] = centre
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


func test_revision3_world_is_larger_with_new_lands() -> void:
	var g := _world()
	check_eq(g.revision, WorldGen.LATEST_REVISION, "new worlds use the latest revision")
	check(g.size >= 4608, "the overworld is at least 1.5x wider")
	var land := 0
	var biomes := {}
	var n := g.size / WorldGen.COARSE
	for i in range(0, n * n, 7):
		if g._base[i] > WorldGen.SEA_LEVEL:
			land += 1
		biomes[int(g._biome[i])] = true
	check(land * 7 * 16 > 7000000, "land area at least doubled (%.1f km2)" % [land * 7 * 16 / 1e6])
	for b in [WorldGen.Biome.REDWOOD, WorldGen.Biome.CANYON, WorldGen.Biome.ALPINE, WorldGen.Biome.TUNDRA, WorldGen.Biome.VOLCANIC, WorldGen.Biome.FJORD]:
		check(biomes.has(b), "biome %s exists" % WorldGen.BIOME_NAMES[b])
	check_eq(WorldGen.BIOME_NAMES.size(), WorldGen.Biome.size(), "every biome is named")
	check_eq(WorldGen.BIOME_COLORS.size(), WorldGen.Biome.size(), "every biome has a map colour")


func test_new_villages_mines_and_caves_are_planned() -> void:
	var g := _world()
	var ids := {}
	for loc in g.locations:
		ids[loc.id] = loc
	for id in [&"emberfall", &"elderhollow", &"highmere", &"kaldvik", &"redmesa", &"brimhold", &"old_ember_mine", &"old_ember_mine_workings", &"redrock_delve"]:
		check(ids.has(id), "planned %s" % id)
	var mines := 0
	for loc in g.locations:
		if loc.kind == Location.Kind.MINE and loc.has_meta(&"mine"):
			mines += 1
			var props: Array = loc.get_meta(&"mine")["props"]
			check(props.size() > 40, "%s is dressed (%d props)" % [loc.name, props.size()])
			check(not loc.spawns_of("enemy").is_empty() and not loc.spawns_of("chest").is_empty(), "%s has monsters and loot" % loc.name)
			# The workings are carved: a drift floor point is open air.
			for p: Dictionary in props:
				if p["type"] == "rail":
					var at: Vector3 = (p["a"] as Vector3).lerp(p["b"], 0.5) + Vector3(0, 1.5, 0)
					var data := g.generate_chunk(Chunk.key_of(Vector3i(at.floor())))
					var l := Chunk.local(Vector3i(at.floor()))
					check_eq(data[Chunk.index(l.x, l.y, l.z)], Blocks.AIR, "%s drift is open" % loc.name)
					break
	check(mines >= 6, "full mines planned (%d)" % mines)
	var kinds := {}
	for e: Array in g.caves.entrances:
		kinds[e[2]] = true
	check(kinds.has("mouth") and kinds.has("sinkhole"), "cave mouths and sinkholes lead underground")
	check(g.caves.rivers.size() > 0, "underground rivers")
	check(g.lakes.size() > 3, "lakes")


func test_cave_naming_never_reports_the_surface() -> void:
	var g := _world()
	var p := Vector3(1024, -40, 1024)
	check(g.is_underground(p), "deep below Emberfall is underground")
	check(g.cave_name_at(p) != "", "named as a cave")
	check_eq(g.cave_name_at(Vector3(1024, g.ground_level(1024, 1024) + 2.0, 1024)), "", "no cave name in the open")


func test_generation_v3_timing() -> void:
	var g := _world()
	var t0 := Time.get_ticks_usec()
	var count := 0
	for x in range(150, 154):
		for z in range(60, 63):
			var h := g.surface_height(x * 16 + 8, z * 16 + 8)
			for y in [floori(h / 16.0), -2]:
				g.generate(Vector3i(x, y, z))
				count += 1
	print("      v3 generate: %.2f ms/chunk" % [(Time.get_ticks_usec() - t0) / 1000.0 / count])


## A pond in smooth ground: the water surface runs one cell into the ground all
## round (the shore skirt, flat and waveless), and the wave depth is 0 on the shore.
func test_water_surface_skirts_the_shore() -> void:
	var c := Chunk.empty()
	for z in 16:
		for x in 16:
			for y in 6:
				c[Chunk.index(x, y, z)] = Blocks.SAND
	for z in range(5, 11):
		for x in range(5, 11):
			for y in range(2, 6):
				c[Chunk.index(x, y, z)] = Blocks.WATER
	var neighbours := []
	neighbours.resize(27)
	for i in 27:
		neighbours[i] = PackedByteArray()
	neighbours[13] = c
	var surface := PackedInt32Array()
	surface.resize(256)
	surface.fill(5)
	var ground := PackedFloat32Array()
	ground.resize(17 * 17)
	ground.fill(6.0)
	for z in range(5, 12):
		for x in range(5, 12):
			ground[x + z * 17] = 2.0
	var result := ChunkMesher.build(neighbours, surface, 0, ground)
	check(result.has("liquid"), "pond has a water surface")
	var verts: PackedVector3Array = result["liquid"][Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = result["liquid"][Mesh.ARRAY_TEX_UV]
	var cells := {}
	var deep := 0
	for i in verts.size():
		var v := verts[i]
		check(absf(v.y - 5.0 - ChunkMesher.WATER_TOP) < 1e-4, "every surface vertex sits at the water level")
		var on_shore := v.x <= 5.0 or v.x >= 11.0 or v.z <= 5.0 or v.z >= 11.0
		if on_shore:
			check_eq(uvs[i].x, 0.0, "no waves on the shoreline")
		elif uvs[i].x > 3.0:
			deep += 1
		if i % 4 == 0:
			cells[Vector2i(floori(v.x + 0.5), floori(v.z + 0.5))] = true
	check(deep > 0, "open water carries its depth")
	check_eq(cells.size(), 8 * 8, "36 water cells plus a ring of 28 skirt cells")
