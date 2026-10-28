class_name UndergroundSites
extends RefCounted
## The two unique underground places of a revision 5 world, planned by UndergroundPlan:
##
##   The Everbloom Cavern  a vast moss-carpeted hall with one enormous glowing tree
##                         (entity "ug_everbloom"), reached through a narrow hidden cleft
##                         in a hillside and from the cave network.
##   Hearthold             the city of the Stonekin around the Heartcrystal: carved stone
##                         houses on two levels, bridges, a market, a forge
##                         (UndergroundCity), behind a rune-marked cleft on the surface and
##                         a deep road from the caves.
##
## Both claim their region cell (CaveBiomes.special_cells), add a zone, a Location
## (Location.Kind.EVERBLOOM / UNDERCITY) and blueprints for floors and collision.

const EVERBLOOM_ID := &"everbloom_cavern"
const CITY_ID := &"hearthold"
const EVERBLOOM_FLOOR := -60.0
const EVERBLOOM_RADII := Vector3(60, 30, 60)
const CITY_FLOOR := -56.0
const CITY_RADII := Vector3(74, 34, 74)
## Hearthold (UndergroundCity). The Stonekin are ordinary villager NPCs until they get their own entity.
const ENABLE_CITY := true


static func plan(ctx: UndergroundPlan.Ctx) -> void:
	var gen := ctx.gen
	var n := gen.size / int(CaveBiomes.CELL.x)
	var cells: Array[Vector2i] = []
	for kz in range(3, n - 3):
		for kx in range(3, n - 3):
			cells.append(Vector2i(kx, kz))
	UndergroundPlan._shuffle(cells, ctx.rng)
	var home := gen.center()
	var city_cell := Vector2i(-1, -1)
	# Hearthold: within a long walk of Emberfall (found mid-game), under solid ground.
	for cell in cells:
		var c := _cell_centre(cell)
		var d := c.distance_to(home)
		if d < 420.0 or d > 1500.0:
			continue
		if ENABLE_CITY and _site_ok(ctx, c, CITY_RADII, CITY_FLOOR):
			city_cell = cell
			_hearthold(ctx, cell)
			break
	for cell in cells:
		var c := _cell_centre(cell)
		if c.distance_to(home) < 380.0 or (city_cell.x >= 0 and c.distance_to(_cell_centre(city_cell)) < 600.0):
			continue
		if _site_ok(ctx, c, EVERBLOOM_RADII, EVERBLOOM_FLOOR):
			_everbloom(ctx, cell)
			break


static func _cell_centre(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * CaveBiomes.CELL.x, (cell.y + 0.5) * CaveBiomes.CELL.z)


static func _site_ok(ctx: UndergroundPlan.Ctx, c: Vector2, radii: Vector3, floor_y: float) -> bool:
	if not ctx.inside(c, 360.0) or not ctx.is_free(c, radii.x + 40.0) or not ctx.clear_of_sites(c, radii.x + 20.0):
		return false
	var top := floor_y + radii.y * 1.6
	if ctx.min_ground(c, radii.x + 8.0) < top + 16.0:
		return false
	return not ctx.near_pools(Vector3(c.x, floor_y + radii.y * 0.6, c.y), radii.x)


## Claims a cell and carves the main hall: a lumpy dome with a flat floor at `floor_y`.
static func _hall(ctx: UndergroundPlan.Ctx, cell: Vector2i, floor_y: float, radii: Vector3, kind: int, zone_name: String) -> Vector3:
	var c2 := _cell_centre(cell)
	CaveBiomes.special_cells[Vector3i(cell.x, -1, cell.y)] = kind
	var centre := Vector3(c2.x, floor_y + radii.y * 0.6, c2.y)
	ctx.net.set_scheme(ctx.net.add_blob(centre, radii, 1.5), kind)
	ctx.taken.append([c2, radii.x + 10.0])
	ctx.zone(Vector3(c2.x - radii.x - 14.0, floor_y - 6.0, c2.y - radii.z - 14.0), Vector3(c2.x + radii.x + 14.0, centre.y + radii.y + 4.0, c2.y + radii.z + 14.0), kind, zone_name)
	return Vector3(c2.x, floor_y, c2.y)


## A connection from the hall's rim to the chamber of a neighbouring region.
static func _cave_road(ctx: UndergroundPlan.Ctx, cell: Vector2i, floor_c: Vector3, rim: float, angle: float) -> void:
	var gen := ctx.gen
	for k in 4:
		var a := angle + k * PI * 0.5
		var dir := Vector2.from_angle(a)
		var step := Vector2i(roundi(dir.x), roundi(dir.y))
		var nc := Vector3((cell.x + step.x + 0.5) * CaveBiomes.CELL.x, -32.0, (cell.y + step.y + 0.5) * CaveBiomes.CELL.z)
		var region := CaveBiomes.region(nc, gen.world_seed, gen.revision)
		var kind := int(region["kind"])
		if kind == CaveBiomes.Kind.FLOODED or kind == CaveBiomes.Kind.GEYSER or CaveBiomes.special_cells.has(region["key"]):
			continue
		var rc: Vector3 = region["center"]
		var start := floor_c + Vector3(dir.x * rim, 1.6, dir.y * rim)
		UndergroundPlan.tunnel(ctx, start, Vector3(rc.x, rc.y - CaveBiomes.radii_of(region).y * 0.35, rc.z), 2.8, 3.6)
		return


static func _blueprint_disc(centre: Vector3i, radius: int, layers: Array) -> Blueprint:
	## layers: block per y from the bottom (centre.y - layers.size()) up to centre.y - 1.
	var depth := layers.size()
	var bp := Blueprint.new(centre + Vector3i(-radius, -depth, -radius), Vector3i(radius * 2 + 1, depth, radius * 2 + 1))
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dz * dz > radius * radius:
				continue
			for i in depth:
				bp.set_local(dx + radius, i, dz + radius, int(layers[i]))
	return bp


# --- The Everbloom ---------------------------------------------------------------------------

static func _everbloom(ctx: UndergroundPlan.Ctx, cell: Vector2i) -> void:
	var gen := ctx.gen
	var rng := ctx.rng
	var f := _hall(ctx, cell, EVERBLOOM_FLOOR, EVERBLOOM_RADII, CaveBiomes.Kind.EVERBLOOM, "The Everbloom Cavern")
	var top := EVERBLOOM_FLOOR + EVERBLOOM_RADII.y * 1.6
	# Mossy alcoves around the hall.
	for k in 5:
		var a := TAU * k / 5.0 + rng.randf_range(-0.3, 0.3)
		var off := Vector3(cos(a), 0, sin(a)) * EVERBLOOM_RADII.x * 0.78
		ctx.net.set_scheme(ctx.net.add_blob(f + off + Vector3(0, 7.0, 0), Vector3(19, 11, 19), 1.4), CaveBiomes.Kind.EVERBLOOM)
	# The hidden cleft from the surface, and the old way in from the caves.
	var a0 := rng.randf() * TAU
	var rim := f + Vector3(cos(a0), 0, sin(a0)) * 50.0 + Vector3(0, 1.2, 0)
	var mouth := UndergroundPlan.hillside_entrance(ctx, Vector2(f.x, f.z), 150.0, 320.0, rim, true)
	_cave_road(ctx, cell, f, 48.0, a0 + PI)
	var loc := Location.new(EVERBLOOM_ID, "The Everbloom Cavern", Location.Kind.EVERBLOOM, f)
	loc.radius = 56.0
	loc.half_height = 34.0
	loc.major = true
	loc.dimension = 0
	var fc := Vector3i(roundi(f.x), roundi(f.y), roundi(f.z))
	# A level floor of moss over stone (the roots spread through it), and a still pool.
	var bp := _blueprint_disc(fc, 44, [Blocks.STONE, Blocks.STONE, Blocks.MUD, Blocks.CAVE_MOSS])
	var pond := Vector3(cos(a0 + 2.2), 0, sin(a0 + 2.2)) * 27.0
	for dz in range(-7, 8):
		for dx in range(-7, 8):
			var d := Vector2(dx, dz).length()
			if d > 6.5:
				continue
			var lx := 44 + roundi(pond.x) + dx
			var lz := 44 + roundi(pond.z) + dz
			if lx < 0 or lz < 0 or lx > 88 or lz > 88:
				continue
			for i in (3 if d < 4.5 else 2):
				bp.set_local(lx, 3 - i, lz, Blocks.WATER)
	loc.blueprints.append(bp)
	loc.add_spawn("entity", f, {"kind": "ug_everbloom", "data": {"floor": f.y, "top": top}})
	loc.set_meta(&"everbloom", {"tree": f, "floor": f.y, "top": top, "radius": EVERBLOOM_RADII.x, "mouth": mouth, "pond": f + pond})
	gen.locations.append(loc)
	gen._blueprints.append_array(loc.blueprints)
	if mouth != Vector3.INF:
		ctx.openings.append([mouth, mouth - Vector3(0, 8, 0), 1.5])


# --- Hearthold -------------------------------------------------------------------------------

static func _hearthold(ctx: UndergroundPlan.Ctx, cell: Vector2i) -> void:
	var gen := ctx.gen
	var rng := ctx.rng
	var f := _hall(ctx, cell, CITY_FLOOR, CITY_RADII, CaveBiomes.Kind.CITY, "Hearthold")
	# Level streets: three overlapping rounded rooms; their corners leave carved bays in the walls.
	for k in 3:
		ctx.net.set_scheme(ctx.net.add_room(f, 50.0, 50.0, 9.0, k * PI / 6.0), CaveBiomes.Kind.CITY)
	var layout := UndergroundCity.layout(gen.world_seed)
	var gates: Array = layout["gates"]
	# The rune-marked cleft from the surface ends at the first gate; the deep road at the second.
	var g0: Dictionary = gates[0]
	var g1: Dictionary = gates[1]
	var gate0 := f + (g0["pos"] as Vector3) * 1.12 + Vector3(0, 1.4, 0)
	var mouth := UndergroundPlan.hillside_entrance(ctx, Vector2(f.x, f.z), 220.0, 420.0, gate0, true)
	_cave_road(ctx, cell, f, 64.0, float(g1["angle"]))
	ctx.net.set_scheme(ctx.net.add_worm(f + (g0["pos"] as Vector3) * 0.92 + Vector3(0, 1.4, 0), gate0, 2.6, 2.4, 0.4), CaveBiomes.Kind.CITY)
	var loc := Location.new(CITY_ID, "Hearthold", Location.Kind.UNDERCITY, f)
	loc.radius = 66.0
	loc.half_height = 40.0
	loc.major = true
	loc.dimension = 0
	var fc := Vector3i(roundi(f.x), roundi(f.y), roundi(f.z))
	loc.blueprints.append(_blueprint_disc(fc, 64, [Blocks.STONE, Blocks.STONE, Blocks.GRANITE, Blocks.GRANITE]))
	loc.blueprints.append_array(UndergroundCity.blueprints(layout, fc))
	for i in (layout["npcs"] as Array).size():
		var npc: Dictionary = layout["npcs"][i]
		loc.add_spawn("entity", f + (npc["pos"] as Vector3) + Vector3(0, 0.05, 0), {"kind": "npc",
				"data": {"role": npc["role"], "village": String(CITY_ID), "seed": gen.world_seed * 31 + i * 7919, "yaw": float(npc.get("yaw", 0.0))}})
	loc.add_spawn("shrine", f + Vector3(0, 0.05, 13.5))
	loc.set_meta(&"city", {"layout": layout, "mouth": mouth, "floor": f.y})
	gen.locations.append(loc)
	gen._blueprints.append_array(loc.blueprints)
	if mouth != Vector3.INF:
		ctx.openings.append([mouth, mouth - Vector3(0, 8, 0), 1.5])
