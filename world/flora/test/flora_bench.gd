extends SceneTree
## Headless CPU benchmark of the flora pipeline:
##   godot --headless --path . -s res://world/flora/test/flora_bench.gd
## Prints warmup time, plan_chunk ms for a typical grassy chunk (with and without trees),
## instance counts per layer, and build_chunk ms.

const Terrain := preload("res://world/flora/test/flora_terrain.gd")

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var t0 := Time.get_ticks_usec()
	Flora.warmup()
	print("warmup: %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	for kind in 4:
		var line := "tree kind %d:" % kind
		for v in Flora.VARIANTS:
			var m0 := Flora.tree_mesh(kind, v, 0)
			var m1 := Flora.tree_mesh(kind, v, 1)
			var m2 := Flora.tree_mesh(kind, v, 2)
			line += " v%d tris %d/%d/%d" % [v, _tris(m0), _tris(m1), _tris(m2)]
		print(line)
	var terr := Terrain.new(5)
	var surf := terr.surface(2, 3, 0)
	print("surface triangles: %d" % (surf.tris.size() / 3))
	var trees := []
	for i in 6:
		trees.append([Vector3(2.5 + (i % 3) * 5.0, terr.height(32 + 2.5 + (i % 3) * 5.0, 48 + 3.0 + (i / 3) * 8.0), 3.0 + (i / 3) * 8.0), i % 2, 8.0 + i, 1000 + i])
	for label in ["meadow (no trees)", "forest edge (6 oaks)"]:
		var tr: Array = [] if label.begins_with("meadow") else trees
		var best := 1e9
		var plan := {}
		for rep in 5:
			var t := Time.get_ticks_usec()
			plan = Flora.plan_chunk(Vector3i(32, 0, 48), surf, tr, 0, 1234)
			best = minf(best, (Time.get_ticks_usec() - t) / 1000.0)
		var total := 0
		var parts := PackedStringArray()
		for g: Dictionary in plan.groups:
			total += int(g.count)
			parts.append("%s=%d" % [Flora.L.keys()[g.layer], g.count])
		print("%s: plan_chunk %.2f ms, %d instances (%s), %d tree groups" % [label, best, total, ", ".join(parts), plan.trees.size()])
		for q in 4:
			var tb := Time.get_ticks_usec()
			var node := Flora.build_chunk(plan, q)
			var ms := (Time.get_ticks_usec() - tb) / 1000.0
			print("   build_chunk q%d: %.3f ms, %d nodes" % [q, ms, node.get_child_count()])
			node.free()
	quit()
	return true


func _tris(m: ArrayMesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		n += m.surface_get_array_index_len(s) / 3
	return n
