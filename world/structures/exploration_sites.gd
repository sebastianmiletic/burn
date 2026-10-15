class_name ExplorationSites
extends RefCounted
## Abandoned mines, shipwrecks and the Ryft's islands. Collision is carved /
## STRUCTURE in blueprints; everything visible is modelled by SiteMesh.

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
	bp.ellipsoid(Vector3i(12, 10, 13), Vector3(10, 7, 10), Blueprint.CARVE)
	bp.fill(Vector3i(5, 3, 6), Vector3i(19, 3, 20), Blocks.LIMESTONE)
	# Timber sets, rails, the portal, carts and lanterns (SiteMesh "mine").
	loc.props.append({"type": "site", "site": "mine", "material": "timber", "at": loc.center, "size": Vector3.ONE,
			"origin": Vector3(bp.origin), "steps": 90, "rate": 0.58, "cx": 12.5, "top_z": 96.0, "seed": hash(String(loc.id))})
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
	bp.fill(Vector3i(6, 2, 4), Vector3i(18, 2, 10), Blocks.STRUCTURE)
	loc.props.append({"type": "site", "site": "wreck", "material": "timber", "at": loc.center + Vector3(0.5, 0, 0.5), "size": Vector3.ONE,
			"yaw": 0.0, "seed": hash(String(loc.id))})
	loc.add_spawn("chest", loc.center + Vector3(3, 1.2, 0), {"tier": 2})
	loc.add_spawn("lore", loc.center + Vector3(-3, 1.2, 0), {"text": "The tide took the crew, but not the cargo. These old sea lanes once reached the islands beyond the eastern reef."})

static func ryft(gen: WorldGen) -> Array[Location]:
	var out: Array[Location] = []
	var variants := ["landing", "observatory", "crown", "refuge"]
	for i in WorldGen.RYFT_ISLANDS.size():
		var island: Vector4 = WorldGen.RYFT_ISLANDS[i]
		var id := &"ryft_landing" if i == 0 else StringName("ryft_isle_%d" % i)
		var loc := Location.new(id, "Ryft Landing" if i == 0 else ["", "The Broken Observatory", "Crown of the Ryft", "Driftwood Refuge"][i], Location.Kind.RUIN, Vector3(island.x, island.z, island.y))
		loc.dimension = 2
		loc.radius = island.w
		loc.major = true
		loc.pad_radius = 8
		loc.pad_falloff = 8
		var bp := Blueprint.new(Vector3i(loc.center.round()) + Vector3i(-10, -2, -10), Vector3i(21, 14, 21))
		loc.blueprints.append(bp)
		var g := int(loc.center.round().y) - int(bp.origin.y)
		var variant: String = variants[mini(i, variants.size() - 1)]
		loc.props.append({"type": "site", "site": "ryft", "variant": variant, "material": "stone", "at": loc.center, "size": Vector3.ONE, "seed": hash(String(id))})
		if i == 0:
			loc.add_spawn("portal", loc.center + Vector3(0, 1, -8), {"to": 0, "size": Vector2(4, 6)})
			loc.add_spawn("shrine", loc.center + Vector3(4, 1, 0))
			var gate_at := loc.center + Vector3(0, 0, -8)
			loc.props.append({"type": "site", "site": "gateway", "material": "stone", "at": gate_at, "size": Vector3.ONE,
					"portal": Vector2(4, 6), "seed": 11})
			for side: float in [-1.0, 1.0]:
				var cell := Vector3i(floori(gate_at.x + side * 2.55), 0, floori(gate_at.z)) - bp.origin
				bp.fill(Vector3i(cell.x, g + 1, cell.z), Vector3i(cell.x, g + 7, cell.z), Blocks.STRUCTURE)
		else:
			loc.add_spawn("chest", loc.center + Vector3(0, 1, 0), {"tier": 3})
			loc.add_spawn("enemy", loc.center + Vector3(10, 1, 3), {"kind": "rock_golem" if i == 2 else "shade"})
			# Ryft bosses (entities/bosses/ryft_sentinel_boss.gd, void_sovereign_boss.gd) on the
			# levelled pad of the observatory and crown isles; their lairs may move these.
			if i == 1 or i == 2:
				loc.add_spawn("boss", loc.center + Vector3(0, 1.5, -6), {"kind": "ryft_sentinel" if i == 1 else "void_sovereign"})
		if i == 1 or i == 2:
			Battlegrounds.ryft_lair(loc, i)  # crystal boss arenas (Prism Sentinel, Void Sovereign)
		out.append(loc)
	return out
