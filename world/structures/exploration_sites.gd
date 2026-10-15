class_name ExplorationSites
extends RefCounted

static func mine(loc: Location) -> void:
	loc.radius = 34
	loc.half_height = 70
	loc.major = true
	var bp := Blueprint.new(Vector3i(loc.center) + Vector3i(-12, -62, -96), Vector3i(25, 74, 110))
	loc.blueprints.append(bp)
	# Walkable descending adit. The smooth floor slopes instead of exposing cubes.
	for step in range(90):
		var y := 62 - floori(step * 0.58)
		var z := 96 - step
		bp.fill(Vector3i(9, y, z), Vector3i(15, y + 5, z), Blueprint.CARVE)
		bp.fill(Vector3i(9, y - 2, z), Vector3i(15, y - 1, z), Blocks.LIMESTONE)
		if step % 9 == 0:
			var p := Vector3(bp.origin) + Vector3(12.5, y, z + 0.5)
			for side in [-2.7, 2.7]:
				Architecture.box(loc, p + Vector3(side, 2.4, 0), Vector3(0.35, 4.8, 0.35), "timber")
			Architecture.box(loc, p + Vector3(0, 4.7, 0), Vector3(6.0, 0.4, 0.4), "timber")
			bp.set_local(9, y + 2, z, Blocks.TORCH)
	bp.ellipsoid(Vector3i(12, 10, 13), Vector3(10, 7, 10), Blueprint.CARVE)
	bp.fill(Vector3i(5, 3, 6), Vector3i(19, 3, 20), Blocks.LIMESTONE)
	loc.add_spawn("chest", Vector3(bp.origin) + Vector3(12.5, 4.5, 13.5), {"tier": 2})
	loc.add_spawn("lore", loc.center + Vector3(5, 1, 1), {"text": "The old adit descends to the galleries. Bring an iron pick and torches. Steam vents give warning before they erupt; crystal sanctuaries shelter no creatures."})

## World revision 3: a full abandoned mine (world/caves/mine_layout.gd). `surface` is the
## timbered portal on a hillside, `depths` the workings (levels, stopes, the deep gallery).
static func full_mine(surface: Location, depths: Location, gen: WorldGen, heading: Vector2, rng: RandomNumberGenerator, spec: Dictionary) -> void:
	surface.radius = 16.0
	surface.half_height = 12.0
	surface.major = true
	depths.major = true
	MineLayout.build(surface, depths, gen, heading, rng, spec)


static func shipwreck(loc: Location) -> void:
	loc.radius = 20
	loc.half_height = 18
	var bp := Blueprint.new(Vector3i(loc.center) + Vector3i(-12, -2, -7), Vector3i(25, 14, 15))
	loc.blueprints.append(bp)
	# Curved ribs and broken deck, batched into a single timber draw call.
	for rib in range(-8, 9, 2):
		var width := 4.0 * sqrt(maxf(0, 1.0 - pow(rib / 10.0, 2)))
		for side in [-1.0, 1.0]:
			for segment in 4:
				var angle := (segment + 0.5) * PI / 8.0
				var p := loc.center + Vector3(rib, 3.0 - cos(angle) * 3.0, side * sin(angle) * width)
				Architecture.box(loc, p, Vector3(0.25, 1.4, 0.25), "timber", Vector3(side * (PI / 2.0 - angle), 0, 0))
	for plank in range(-3, 4):
		Architecture.box(loc, loc.center + Vector3(plank * 0.15, 1.0, plank * 0.7), Vector3(14.0 - absf(plank), 0.18, 0.62), "timber")
	Architecture.box(loc, loc.center + Vector3(1, 4, 0), Vector3(0.4, 8, 0.4), "timber", Vector3(0.0, 0.0, 0.28))
	bp.fill(Vector3i(6, 2, 4), Vector3i(18, 2, 10), Blocks.STRUCTURE)
	loc.add_spawn("chest", loc.center + Vector3(3, 1.2, 0), {"tier": 2})
	loc.add_spawn("lore", loc.center + Vector3(-3, 1.2, 0), {"text": "The tide took the crew, but not the cargo. These old sea lanes once reached the islands beyond the eastern reef."})

static func ryft(gen: WorldGen) -> Array[Location]:
	var out: Array[Location] = []
	for i in WorldGen.RYFT_ISLANDS.size():
		var island: Vector4 = WorldGen.RYFT_ISLANDS[i]
		var id := &"ryft_landing" if i == 0 else StringName("ryft_isle_%d" % i)
		var loc := Location.new(id, "Ryft Landing" if i == 0 else ["", "The Broken Observatory", "Crown of the Ryft", "Driftwood Refuge"][i], Location.Kind.RUIN, Vector3(island.x, island.z, island.y))
		loc.dimension = 2
		loc.radius = island.w
		loc.major = true
		loc.pad_radius = 8
		loc.pad_falloff = 8
		if i == 0:
			loc.add_spawn("portal", loc.center + Vector3(0, 1, -8), {"to": 0, "size": Vector2(4, 6)})
			loc.add_spawn("shrine", loc.center + Vector3(4, 1, 0))
		else:
			loc.add_spawn("chest", loc.center + Vector3(0, 1, 0), {"tier": 3})
			loc.add_spawn("enemy", loc.center + Vector3(10, 1, 3), {"kind": "rock_golem" if i == 2 else "shade"})
		for side in [-1, 1]:
			Architecture.box(loc, loc.center + Vector3(side * 5, 3, -8), Vector3(1.2, 7, 1.4), "stone", Vector3(0, 0, side * 0.12))
		out.append(loc)
	return out
