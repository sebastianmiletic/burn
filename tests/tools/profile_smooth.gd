extends SceneTree
## Profiles SmoothMesher stages on a real surface chunk.
##   godot --headless --path . -s res://tests/tools/profile_smooth.gd

func _initialize() -> void:
	var g := WorldGen.new(WorldGen.Dimension.OVERWORLD, 1234)
	g.prepare()
	var c := Vector3i(64, 1, 64)
	var k := Vector3i(c.x, floori((g.surface_height(c.x * 16 + 8, c.z * 16 + 8) + 1) / 16.0), c.z)
	var blocks := []
	var dens := []
	blocks.resize(27)
	dens.resize(27)
	for dz in range(-1, 2):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var r := g.generate(k + Vector3i(dx, dy, dz))
				blocks[(dx + 1) + (dy + 1) * 3 + (dz + 1) * 9] = r[0]
				dens[(dx + 1) + (dy + 1) * 3 + (dz + 1) * 9] = r[1]
	var t := Time.get_ticks_usec()
	var pb := ChunkMesher.pad_blocks(blocks)
	print("pad blocks ", (Time.get_ticks_usec() - t) / 1000.0)
	t = Time.get_ticks_usec()
	var pd := SmoothMesher._pad_density(blocks, dens)
	print("pad density ", (Time.get_ticks_usec() - t) / 1000.0)
	var surface := PackedInt32Array()
	surface.resize(256)
	var biomes := PackedByteArray()
	biomes.resize(256)
	for i in 3:
		t = Time.get_ticks_usec()
		var res := SmoothMesher.build(blocks, dens, surface, biomes, k * 16, 0)
		print("build ", (Time.get_ticks_usec() - t) / 1000.0, " ms")
	t = Time.get_ticks_usec()
	ChunkMesher.build(blocks, surface, k.y * 16)
	print("cube build ", (Time.get_ticks_usec() - t) / 1000.0, " ms")
	quit()
