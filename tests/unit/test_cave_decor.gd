extends TestCase
## Cave decoration planning (worker side) and mine prop expansion.


## A strip of floor, wall and ceiling triangles deep underground.
func _terrain(code: int) -> Array:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var custom := PackedFloat32Array()
	var uv2 := PackedVector2Array()
	for z in 14:
		for x in 14:
			for face: Array in [[Vector3(x, 2, z), Vector3.UP], [Vector3(x, 12, z), Vector3.DOWN], [Vector3(1, 2 + x * 0.6, z), Vector3.RIGHT]]:
				var p: Vector3 = face[0]
				var n: Vector3 = face[1]
				var t := n.cross(Vector3.FORWARD if absf(n.z) < 0.9 else Vector3.RIGHT).normalized()
				var b := n.cross(t)
				for c: Vector3 in [p, p + t, p + b]:
					verts.append(c)
					norms.append(n)
					custom.append_array([code, code, code, 0.0])
					uv2.append(Vector2(0.04, 0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	return arrays


func test_plan_is_deterministic_and_bounded() -> void:
	var terrain := _terrain(Blocks.LIMESTONE)
	for kind in 8:
		var a := CaveDecor.plan_chunk(Vector3i(64, -48, 64), terrain, 0, 1234, PackedByteArray(), kind)
		var b := CaveDecor.plan_chunk(Vector3i(64, -48, 64), terrain, 0, 1234, PackedByteArray(), kind)
		check_eq(a, b, "plan deterministic for kind %d" % kind)
		check(not a.is_empty(), "kind %d decorates a cave" % kind)
		check((a.get("lights", []) as Array).size() <= 2, "at most two decor lights per chunk")
		for key: int in a.get("batches", {}):
			var bt: Array = a["batches"][key]
			check_eq((bt[0] as PackedFloat32Array).size(), int(bt[1]) * CaveDecor.FLOATS, "buffer matches instance count")
			check((key >> 6) < CaveDecor.M.COUNT and (key & 63) < CaveDecor.T.COUNT, "valid mesh and material")


func test_exposed_ore_grows_nodules_even_outdoors() -> void:
	var terrain := _terrain(Blocks.COPPER_ORE)
	var uv2: PackedVector2Array = terrain[Mesh.ARRAY_TEX_UV2]
	uv2.fill(Vector2(1.0, 0.0))
	terrain[Mesh.ARRAY_TEX_UV2] = uv2
	var plan := CaveDecor.plan_chunk(Vector3i(0, 32, 0), terrain, 0, 7)
	var crusts := 0
	for key: int in plan.get("batches", {}):
		if (key >> 6) in [CaveDecor.M.CRUST, CaveDecor.M.CRUST + 1]:
			crusts += int(plan["batches"][key][1])
	check(crusts > 50, "copper crusts on an exposed cliff (%d)" % crusts)
	var plain := CaveDecor.plan_chunk(Vector3i(0, 32, 0), _open_sky(_terrain(Blocks.GRASS)), 0, 7)
	check(plain.is_empty(), "open grassland stays bare")


func _open_sky(terrain: Array) -> Array:
	var uv2: PackedVector2Array = terrain[Mesh.ARRAY_TEX_UV2]
	uv2.fill(Vector2(1.0, 0.0))
	terrain[Mesh.ARRAY_TEX_UV2] = uv2
	return terrain


func test_mine_props_expand_to_instances() -> void:
	var c := Vector3(500, -20, 500)
	var props := [
		{"type": "timber_set", "at": c, "yaw": 0.3, "width": 3.6, "height": 3.4, "lagging": true},
		{"type": "rail", "a": c, "b": c + Vector3(0, 0, 9)},
		{"type": "cart", "at": c, "yaw": 0.0, "tipped": false, "ore": Blocks.IRON_ORE},
		{"type": "lantern", "at": c + Vector3(0, 3, 0), "lit": true},
		{"type": "lantern", "at": c + Vector3(0, 3, 6), "lit": false},
		{"type": "rubble", "at": c, "radius": 1.5},
		{"type": "entrance", "at": c, "yaw": 0.0, "width": 4.0, "height": 3.6},
		{"type": "headframe", "at": c, "yaw": 0.0},
	]
	var plan := MineDressing.plan(props, c)
	check((plan["batches"] as Dictionary).size() >= 8, "props become several batches")
	check_eq((plan["lanterns"] as Array).size(), 2, "lit lanterns (and the portal lamp) are light candidates")
	for key: String in plan["batches"]:
		var bt: Array = plan["batches"][key]
		check_eq((bt[0] as PackedFloat32Array).size(), int(bt[1]) * 16)
