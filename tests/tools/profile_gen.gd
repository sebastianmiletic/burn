extends SceneTree
## Profiles chunk generation stages:  godot --headless --path . -s res://tests/tools/profile_gen.gd


func _init() -> void:
	var g := WorldGen.new(WorldGen.Dimension.OVERWORLD, 1234)
	g.prepare()
	var detail := g.make_detail_noise()
	var ridge := g.make_ridge_noise()
	for label_key: Array in [["village surface", Vector3i(64, 1, 64)], ["forest surface", Vector3i(96, 1, 64)], ["underground", Vector3i(80, -3, 70)], ["air", Vector3i(80, 5, 70)]]:
		var k: Vector3i = label_key[1]
		var o := k * 16
		var t := Time.get_ticks_usec()
		for z in 16:
			for x in 16:
				g.column(o.x + x, o.z + z, detail, ridge)
		var cols := Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		var data := g.generate_chunk(k)
		var total := Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		g._place_trees(data, o, detail, ridge)
		var trees := Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		g._stamp_blueprints(data, k)
		var stamp := Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		for i in 4096:
			g._ground_block(1000 + (i & 15), -20, 1000 + (i >> 4), 30, 1, 0)
		var ground := Time.get_ticks_usec() - t
		print("%-16s total %5.1f ms | columns %4.1f | trees %4.1f | stamp %4.1f | 4096 ground_block %4.1f" % [label_key[0], total / 1000.0, cols / 1000.0, trees / 1000.0, stamp / 1000.0, ground / 1000.0])
	quit()
