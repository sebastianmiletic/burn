extends SceneTree
func _init() -> void:
	var g := WorldGen.new(WorldGen.Dimension.OVERWORLD, 1234, 4)
	g.prepare()
	var keys := [Vector3i(78, 8, 163), Vector3i(78, 12, 163), Vector3i(209, -5, 168), Vector3i(209, -3, 168), Vector3i(187, 0, 218), Vector3i(250, 0, 100), Vector3i(40, 0, 250), Vector3i(64, 1, 64)]
	var parts := PackedStringArray()
	for k: Vector3i in keys:
		var r := g.generate(k)
		parts.append("%d/%d" % [hash(r[0]), hash(r[1])])
	print("SIG ", ",".join(parts))
	var locs := PackedStringArray()
	for l in g.locations:
		locs.append("%s@%d,%d,%d" % [l.id, int(l.center.x), int(l.center.y), int(l.center.z)])
	print("LOCS ", hash(",".join(locs)), " ", g.locations.size())
	print("HMAP ", hash(g.height_map()))
	quit()
