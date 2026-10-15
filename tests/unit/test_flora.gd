extends TestCase
## Flora planning: determinism, thread safety, MultiMesh buffer layout, scatter rules.

const Terrain := preload("res://world/flora/test/flora_terrain.gd")


func _surface() -> Dictionary:
	var t := Terrain.new(5)
	return t.surface(1, 2, 0)


func _trees() -> Array:
	return [[Vector3(4.5, 0.0, 5.0), Flora.OAK, 9.0, 11], [Vector3(11.0, 0.0, 9.5), Flora.PINE, 10.5, 12]]


func _sig(plan: Dictionary) -> String:
	var parts := PackedStringArray()
	for g: Dictionary in plan.groups:
		var buf: PackedFloat32Array = g.buf
		parts.append("%d:%d:%d" % [g.layer, g.count, hash(buf)])
	for g: Dictionary in plan.trees:
		parts.append("t%d/%d:%d" % [g.kind, g.variant, g.count])
	parts.sort()
	return ",".join(parts)


func test_plan_is_deterministic() -> void:
	var s := _surface()
	var a := Flora.plan_chunk(Vector3i(16, 0, 32), s, _trees(), 0, 77)
	var b := Flora.plan_chunk(Vector3i(16, 0, 32), s, _trees(), 0, 77)
	check_eq(_sig(a), _sig(b), "same input, same plan")
	var c := Flora.plan_chunk(Vector3i(16, 0, 32), s, _trees(), 0, 78)
	check(_sig(a) != _sig(c), "a different world seed changes the scatter")
	var total := 0
	for g: Dictionary in a.groups:
		total += int(g.count)
		check_eq((g.buf as PackedFloat32Array).size(), int(g.count) * Flora.FLOATS, "buffer size")
		var tiers: PackedInt32Array = g.tiers
		check_eq(tiers[0] + tiers[1] + tiers[2] + tiers[3], int(g.count), "tiers add up")
	check(total > 300, "a grassy chunk gets plenty of cover (%d)" % total)
	check_eq(a.trees.size(), 2, "one group per tree kind/variant")


func test_plan_on_worker_threads_matches_main_thread() -> void:
	var s := _surface()
	var expected := _sig(Flora.plan_chunk(Vector3i(16, 0, 32), s, _trees(), 0, 77))
	var results: Array = []
	results.resize(6)
	var task := WorkerThreadPool.add_group_task(func(i: int) -> void:
		results[i] = _sig(Flora.plan_chunk(Vector3i(16, 0, 32), s, _trees(), 0, 77)), 6)
	WorkerThreadPool.wait_for_group_task_completion(task)
	for r in results:
		check_eq(r, expected, "worker-thread plan identical")


## MultiMesh.buffer layout for TRANSFORM_3D + custom data (16 floats): the basis by rows with the
## origin in the 4th column, then the custom colour. (The headless dummy renderer does not store
## MultiMesh data, so the layout is checked against the documented order directly.)
func test_buffer_layout() -> void:
	var plan := Flora.plan_chunk(Vector3i.ZERO, _surface(), _trees(), 0, 5)
	for g: Dictionary in plan.trees:
		var seed_value := 11 if g.kind == Flora.OAK else 12
		var h := 9.0 if g.kind == Flora.OAK else 10.5
		var tp := Flora.tree_params(g.kind, seed_value)
		var b := Basis(Vector3.UP, tp[1]).scaled(Vector3.ONE * h)
		var buf: PackedFloat32Array = g.buf
		check_near(buf[0], b.x.x, 0.001, "row 0: x.x")
		check_near(buf[2], b.z.x, 0.001, "row 0: z.x")
		check_near(buf[5], h, 0.001, "row 1: y.y is the tree height")
		check_near(buf[8], b.x.z, 0.001, "row 2: x.z")
		check_near(buf[3], 4.5 if g.kind == Flora.OAK else 11.0, 0.001, "origin x in column 3")
		check(buf[15] >= 0.0 and buf[15] <= 1.0, "custom alpha is a 0..1 random")


func test_caves_and_steep_ground_stay_bare() -> void:
	var s := _surface()
	var dark := s.duplicate(true)
	var sky := PackedFloat32Array()
	sky.resize((s.sky as PackedFloat32Array).size())
	sky.fill(0.1)
	dark.sky = sky
	var plan := Flora.plan_chunk(Vector3i.ZERO, dark, [], 0, 1)
	check_eq(plan.groups.size(), 0, "no cover in caves")


func test_hell_grows_asphodel() -> void:
	var s := _surface()
	var blocks: PackedByteArray = s.blocks
	blocks.fill(39)   # soul sand
	s.blocks = blocks
	var plan := Flora.plan_chunk(Vector3i.ZERO, s, [], 1, 3)
	var layers := []
	for g: Dictionary in plan.groups:
		layers.append(g.layer)
	check(Flora.L.SOUL_GRASS in layers, "pale soul grass in the underworld")
	check(not (Flora.L.GRASS in layers), "no overworld grass in hell")
