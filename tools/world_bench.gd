extends SceneTree
## World generation benchmark (headless):
##   godot --headless --path . -s res://tools/world_bench.gd -- [--revision=N] [--chunks=N] [--seed=N]
## Prints prepare() phase timings, the overworld land area and the average chunk
## generation cost for surface, mountain and cave chunks.


func _init() -> void:
	var revision := WorldGen.LATEST_REVISION
	var chunks := 24
	var seed_value := 1234
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--revision="):
			revision = int(a.trim_prefix("--revision="))
		elif a.begins_with("--chunks="):
			chunks = int(a.trim_prefix("--chunks="))
		elif a.begins_with("--seed="):
			seed_value = int(a.trim_prefix("--seed="))
	var t := Time.get_ticks_msec()
	var gen := WorldGen.new(WorldGen.Dimension.OVERWORLD, seed_value, revision)
	gen.prepare(Callable(), true)
	print("[bench] revision %d size %d: prepare %d ms, %d locations" % [revision, gen.size, Time.get_ticks_msec() - t, gen.locations.size()])
	var land := 0
	var counts := {}
	var n := gen.size / WorldGen.COARSE
	for i in n * n:
		var b := int(gen._biome[i])
		counts[b] = int(counts.get(b, 0)) + 1
		if gen._base[i] > WorldGen.SEA_LEVEL:
			land += 1
	print("[bench] land %.2f km2" % [land * WorldGen.COARSE * WorldGen.COARSE / 1e6])
	for b: int in counts:
		print("[bench]   biome %-22s %.2f km2" % [WorldGen.BIOME_NAMES[b], counts[b] * WorldGen.COARSE * WorldGen.COARSE / 1e6])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var kinds := {"surface": [], "deep": []}
	for i in chunks:
		var x := rng.randi_range(300, gen.size - 300)
		var z := rng.randi_range(300, gen.size - 300)
		var h := gen.surface_height(x, z)
		kinds["surface"].append(Vector3i(x >> 4, floori(h / 16.0), z >> 4))
		kinds["deep"].append(Vector3i(x >> 4, -3 - (i % 4), z >> 4))
	for k: String in kinds:
		var t0 := Time.get_ticks_usec()
		for key: Vector3i in kinds[k]:
			gen.generate(key)
		print("[bench] generate %s: %.2f ms/chunk" % [k, (Time.get_ticks_usec() - t0) / 1000.0 / chunks])
	var t1 := Time.get_ticks_usec()
	var img := MapImage.build(gen)
	print("[bench] map image %dx%d: %d ms" % [img.get_width(), img.get_height(), (Time.get_ticks_usec() - t1) / 1000])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			img.save_png(a.trim_prefix("--map="))
	if gen.caves != null:
		var ekinds := {}
		for e: Array in gen.caves.entrances:
			ekinds[e[2]] = int(ekinds.get(e[2], 0)) + 1
		print("[bench] caves: %d carvers, entrances %s, rivers %d, lakes %d" % [gen.caves.count(), str(ekinds), gen.caves.rivers.size(), gen.lakes.size()])
	for loc in gen.locations:
		if loc.kind == Location.Kind.MINE or loc.kind == Location.Kind.VILLAGE:
			print("[bench]   %-24s %s %s" % [loc.name, str(Vector3i(loc.center)), WorldGen.BIOME_NAMES[gen.biome_at(int(loc.center.x), int(loc.center.z))]])
	quit()
