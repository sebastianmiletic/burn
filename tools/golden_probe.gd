extends SceneTree
## Prints chunk-hash signatures for older world revisions (the golden values in
## tests/unit/test_underground.gd). Usage:
##   godot --headless --path . -s tools/golden_probe.gd -- --data-dir=<dir under build/>

const KEYS := [Vector3i(64, 1, 64), Vector3i(26, 0, 65), Vector3i(218, -1, 218), Vector3i(262, 0, 66), Vector3i(262, -1, 66),
		Vector3i(64, -3, 64), Vector3i(125, -1, 125), Vector3i(78, 1, 163), Vector3i(270, -1, 30), Vector3i(150, -1, 140),
		Vector3i(15, -1, 200), Vector3i(278, 0, 68), Vector3i(100, -3, 200), Vector3i(200, -4, 100), Vector3i(180, -2, 180)]


func _init() -> void:
	for rev in [3, 4]:
		var g := WorldGen.new(WorldGen.Dimension.OVERWORLD, 1234, rev)
		g.prepare()
		var parts := PackedStringArray()
		for k: Vector3i in KEYS:
			var r := g.generate(k)
			parts.append("%d/%d" % [hash(r[0]), hash(r[1])])
		print("GOLDEN %d: %s" % [rev, ",".join(parts)])
	quit()
