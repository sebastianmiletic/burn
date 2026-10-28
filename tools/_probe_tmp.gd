extends SceneTree
func _init() -> void:
	var t := Time.get_ticks_msec()
	var g := WorldGen.new(WorldGen.Dimension.OVERWORLD, 1234, 5)
	g.prepare()
	print("prepare ms ", Time.get_ticks_msec() - t)
	for id in [&"mount_pyrrhos", &"fire_village", &"atlantis", &"atlantis_throne", &"scumport", &"scumport_cove", &"stormbreak", &"hollow_crowns", &"kraken_graveyard", &"brimstone_pit"]:
		var found := false
		for l in g.locations:
			if l.id == id:
				found = true
				var t0 := Time.get_ticks_msec()
				var n := Architecture.build(l, g)
				var verts := 0
				for c in n.get_children():
					verts += (c as MeshInstance3D).mesh.get_faces().size() / 3 if (c as MeshInstance3D).mesh.get_surface_count() > 0 else 0
				print("LOC ", id, " ", l.center, " r=", l.radius, " props=", l.props.size(), " spawns=", l.spawns.size(), " tris=", verts, " build ms ", Time.get_ticks_msec() - t0, " meta ", l.get_meta(&"map_kind", ""))
				n.free()
		if not found:
			print("LOC ", id, " MISSING")
	var V := AdventureTerrain.V
	for d: float in [0.0, 20.0, 45.0, 70.0, 100.0, 125.0, 140.0, 200.0, 300.0, 450.0]:
		var p := V + AdventureTerrain.NOTCH.rotated(PI) * d
		var q := V + AdventureTerrain.NOTCH * d
		print("V d=%d back h=%.1f  notch h=%.1f" % [d, g.smooth_height(p.x, p.y), g.smooth_height(q.x, q.y)])
	print("lake ", g.lake_level(V.x + 20, V.y), " ground at isle ", g.surface_height(int(V.x), int(V.y)))
	for k in AdventureTerrain.ISLES:
		var c: Vector2 = AdventureTerrain.ISLES[k][0]
		print("ISLE ", k, " h=", g.smooth_height(c.x, c.y), " biome ", g.biome_at(int(c.x), int(c.y)))
	var A := AdventureTerrain.ATLANTIS
	print("ATL h=", g.smooth_height(A.x, A.y), " surface ", g.surface_height(int(A.x), int(A.y)))
	t = Time.get_ticks_msec()
	for k in [Vector3i(78, 9, 163), Vector3i(248, -6, 190), Vector3i(165, 0, 209)]:
		g.generate(k)
	print("chunks ms ", Time.get_ticks_msec() - t)
	var img := MapImage.build(g)
	img.resize(900, 900)
	img.save_png("/private/tmp/claude-501/-Users-sebastianmiletic/373f6b73-3314-40bc-8f4e-2b0633e229fe/scratchpad/map5.png")
	quit()
