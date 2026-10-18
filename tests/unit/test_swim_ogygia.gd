extends TestCase
## Swimming physics, the hidden breath timer and its drowning outcome, and
## Ogygia's terrain and rescue roll. (Arrival, departure and save/load on the
## island run in the full game: tests/game/playtest.gd.)


func _lake() -> VoxelWorld:
	# Stone floor at y = 0, water up to y = 7 (surface drawn at 7.88), air above.
	var vw := VoxelWorld.new()
	for cz in range(-2, 2):
		for cy in range(-2, 2):
			for cx in range(-2, 2):
				var k := Vector3i(cx, cy, cz)
				var blocks := Chunk.empty()
				var dens := Chunk.empty()
				for i in Chunk.VOLUME:
					var y := k.y * 16 + i / Chunk.AREA
					if y < 0:
						blocks[i] = Blocks.STONE
						dens[i] = 255
					elif y <= 7:
						blocks[i] = Blocks.WATER
				vw._chunks[k] = blocks
				vw._density[k] = dens
	return vw


func test_water_surface_and_buoyancy() -> void:
	var vw := _lake()
	check_near(Player.water_surface_at(vw, Vector3(0.5, 3.0, 0.5)), 7.88, 0.01, "surface over deep water")
	check_eq(Player.water_surface_at(vw, Vector3(0.5, 9.0, 0.5)), -INF, "no water above the lake")
	# A swimming body with the player's treading rule floats up from the bottom
	# and settles with its eyes above the surface; it never sinks or launches.
	var owner := Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(owner)
	owner.global_position = Vector3(0.5, 0.05, 0.5)
	var body := VoxelBody.new()
	body.half_extents = Vector3(0.32, 0.9, 0.32)
	body.swimming = true
	var top := -INF
	for f in 600:
		var surface := Player.water_surface_at(vw, owner.global_position)
		var tread := surface - Player.TREAD_DEPTH
		var target := Vector3(0, clampf((tread - owner.global_position.y) * 2.2, -1.4, 0.9), 0)
		body.velocity = body.velocity.lerp(target, 1.0 - exp(-3.2 / 60.0))
		body.step(owner, vw, 1.0 / 60.0)
		top = maxf(top, owner.global_position.y)
	var eye := owner.global_position.y + 1.62
	check(eye > 7.88 and eye < 8.3, "treading keeps the eyes just above water (eye %.2f)" % eye)
	check(top < 7.88 - 1.0, "buoyancy never throws the body out of the water (top %.2f)" % top)
	# Not swimming: the old water physics still sink slowly.
	body.swimming = false
	for f in 120:
		body.step(owner, vw, 1.0 / 60.0)
	check(owner.global_position.y < 7.88 - 1.42, "without swimming the body sinks")
	owner.queue_free()
	vw.free()


func test_breath_blackout_and_drowning() -> void:
	var p := Player.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(p)
	var causes: Array = []
	var on_died := func(c: String) -> void: causes.append(c)
	Events.player_died.connect(on_died)
	p.head_under = true
	var t := 0.0
	var first_dark := -1.0
	while t < 80.0 and not p.dead:
		p._breath_update(0.1)
		p.head_under = true
		t += 0.1
		if first_dark < 0.0 and p.suffocation > 0.05:
			first_dark = t
	check(first_dark > Player.BREATH_TIME - Player.BREATH_FADE - 1.0, "vision only starts closing near the end (%.1f s)" % first_dark)
	check(p.dead and t >= Player.BREATH_TIME, "the head under water blacks out and drowns (%.1f s)" % t)
	check(t < Player.BREATH_TIME + 8.0, "blackout follows soon after the air runs out (%.1f s)" % t)
	check(causes.size() == 1 and String(causes[0]).contains("Drowned"), "death cause names drowning")
	Events.player_died.disconnect(on_died)
	# Surfacing before the blackout recovers gradually.
	var q := Player.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(q)
	for i in 320:
		q.head_under = true
		q._breath_update(0.1)
	var dim := q.suffocation
	check(dim > 0.3 and not q.dead, "after 32 s under, the view is closing (%.2f)" % dim)
	q.head_under = false
	q._breath_update(0.5)
	check(q.suffocation > 0.0 and q.suffocation < dim, "surfacing lifts the dark gradually")
	for i in 40:
		q._breath_update(0.25)
	check(q.suffocation == 0.0 and q.air == q.breath_capacity(), "a few breaths and it is gone")
	p.queue_free()
	q.queue_free()


func test_rescue_roll_is_rare_and_forced_rng_is_deterministic() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var saved := 0
	for i in 10000:
		if Ogygia.rolls_rescue(rng):
			saved += 1
	check(saved > 700 and saved < 1100, "about %d %% of drownings wake on Ogygia (%d / 10000)" % [int(Ogygia.RESCUE_CHANCE * 100.0), saved])
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 7
	b.seed = 7
	for i in 50:
		check_eq(Ogygia.rolls_rescue(a), Ogygia.rolls_rescue(b))


func test_ogygia_island_terrain() -> void:
	var g := OgygiaGen.new(1234)
	check_eq(g.dimension, Ogygia.DIM)
	var beach := Ogygia.beach_spawn(g)
	check(beach.y > OgygiaGen.SEA + 0.5 and beach.y < OgygiaGen.SEA + 4.0, "the beach is just above the sea (%.1f)" % beach.y)
	var far := g.ground_level(OgygiaGen.CENTER.x + 400, OgygiaGen.CENTER.y)
	check(far < OgygiaGen.SEA - 10.0, "open sea all around (floor %.1f)" % far)
	check(g.ground_level(OgygiaGen.GROTTO.x, OgygiaGen.GROTTO.z - 10.0) > OgygiaGen.SEA + 14.0, "a hill rises behind the beach")
	# The grotto is open air above a dry floor, roofed by the hill.
	var k := Chunk.key_of(Vector3i(OgygiaGen.GROTTO))
	var r := g.generate(k)
	var blocks: PackedByteArray = r[0]
	var l := Chunk.local(Vector3i(OgygiaGen.GROTTO))
	check_eq(blocks[Chunk.index(l.x, l.y, l.z)], Blocks.AIR, "the grotto is hollow")
	var h := Ogygia.hearth(g)
	var hk := Chunk.key_of(Vector3i(h.floor()) - Vector3i(0, 1, 0))
	var hb: PackedByteArray = g.generate(hk)[0]
	var hl := Chunk.local(Vector3i(h.floor()) - Vector3i(0, 1, 0))
	check(Blocks.is_smooth(hb[Chunk.index(hl.x, hl.y, hl.z)]), "the hearth stands on solid floor")
	# The spring holds water above sea level.
	var sp := Vector3i(int(OgygiaGen.SPRING.x), int(g.ground_level(OgygiaGen.SPRING.x, OgygiaGen.SPRING.y) + 0.3), int(OgygiaGen.SPRING.y))
	var sb: PackedByteArray = g.generate(Chunk.key_of(sp))[0]
	var sl := Chunk.local(sp)
	check(sp.y > OgygiaGen.SEA and sb[Chunk.index(sl.x, sl.y, sl.z)] == Blocks.WATER, "a spring pool in the meadow (y %d)" % sp.y)
