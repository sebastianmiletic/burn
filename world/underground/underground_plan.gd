class_name UndergroundPlan
extends RefCounted
## World revision 5: the underground beyond the regional chambers. Planned once in
## WorldGen.prepare (after the natural cave network, before the carver index is built):
##
##   * great caverns: vast lumpy halls spanning several regions, lined with the rock of
##     their cave biome (moss, dripstone, ochre, verdigris, violet, sandstone),
##   * fissures: tall, narrow slots pinching shut far overhead,
##   * shafts: vertical pits between cave levels; a few break the surface and let
##     daylight fall into the dark (`gen.get_meta(&"cave_openings")`),
##   * old lava tubes: long round basalt galleries, the deepest with a lava runnel,
##   * layered sandstone caves: stacked shelves stepping up the walls,
##   * flooded grottos: low-roofed lakes joined to their region's chamber,
##   * the Everbloom cavern (UndergroundSites.everbloom) and the city of Hearthold
##     (UndergroundSites.hearthold), unique per world, reached by hidden passages.
##
## Everything is a CaveNetwork carver; F_SCHEME names the cave biome whose rock lines it
## (shell_block). Zones ([AABB, Kind, name]) let decor, the palette and the HUD know
## the planned volumes. Deterministic per seed; read-only after prepare.

const GRAND_CAVERNS := 9
const FISSURES := 28
const SHAFTS := 22
const OPEN_SHAFTS := 7
const TUBES := 8
const GROTTOS := 10
const MAX_GRADE := 0.34
## Ore blocks a scheme keeps where the generic rock had them (veins stay minable).
const KEEP := {13: true, 14: true, 15: true, 16: true, 51: true, 52: true, 53: true, 54: true, 55: true, 56: true, 57: true, 58: true}


static func plan(gen: WorldGen) -> void:
	var ctx := Ctx.new(gen)
	# The unique sites first: they claim their cells before anything else is placed.
	UndergroundSites.plan(ctx)
	_grand_caverns(ctx)
	_layered(ctx)
	_fissures(ctx)
	_shafts(ctx)
	_tubes(ctx)
	_grottos(ctx)
	var openings: Array = ctx.openings
	for e: Array in gen.caves.entrances:
		if String(e[2]) == "sinkhole":
			openings.append([e[0] + Vector3(0, 1, 0), e[0] - Vector3(0, 15, 0), 9.0])
	gen.set_meta(&"cave_openings", openings)


## Planning state shared by the passes.
class Ctx:
	var gen: WorldGen
	var net: CaveNetwork
	var rng := RandomNumberGenerator.new()
	var detail: FastNoiseLite
	var ridge: FastNoiseLite
	## Horizontal discs ([Vector2 centre, radius]) already taken by large features.
	var taken: Array = []
	## [top, bottom, radius] where daylight reaches the caves.
	var openings: Array = []

	func _init(g: WorldGen) -> void:
		gen = g
		net = g.caves
		rng.seed = g.world_seed * 48271 + 505
		detail = g.make_detail_noise()
		ridge = g.make_ridge_noise()

	func ground(x: float, z: float) -> float:
		return gen.column_f(int(x), int(z), detail, ridge).x + 1.0

	## Lowest ground over a disc (centre + two rings of samples).
	func min_ground(c: Vector2, r: float) -> float:
		var lo := ground(c.x, c.y)
		for ring: float in [r * 0.5, r]:
			for k in 8:
				var p := c + Vector2.from_angle(TAU * k / 8.0 + ring * 0.01) * ring
				lo = minf(lo, ground(p.x, p.y))
		return lo

	func is_free(c: Vector2, r: float) -> bool:
		for t: Array in taken:
			if c.distance_to(t[0]) < r + float(t[1]):
				return false
		return true

	func inside(c: Vector2, margin: float) -> bool:
		return c.x > margin and c.y > margin and c.x < gen.size - margin and c.y < gen.size - margin

	## Clear of every planned location (surface or not) by `margin` metres.
	func clear_of_sites(c: Vector2, margin: float) -> bool:
		for loc in gen.locations:
			if Vector2(loc.center.x, loc.center.z).distance_to(c) < margin + loc.radius:
				return false
		return true

	## The regional chamber kinds a volume may not open into (pools would spill).
	func near_pools(c: Vector3, reach: float) -> bool:
		for dz in [-reach, 0.0, reach]:
			for dx in [-reach, 0.0, reach]:
				for dy in [-reach * 0.3, 0.0, reach * 0.3]:
					var k := int(CaveBiomes.region(c + Vector3(dx, dy, dz), gen.world_seed, gen.revision)["kind"])
					if k == CaveBiomes.Kind.FLOODED or k == CaveBiomes.Kind.MAGMA or k == CaveBiomes.Kind.GEYSER:
						return true
		return false

	func zone(lo: Vector3, hi: Vector3, kind: int, zone_name: String) -> void:
		CaveBiomes.zones.append([AABB(lo, hi - lo), kind, zone_name])


# --- Shells -------------------------------------------------------------------------------

## WorldGen._carver_shell for carvers with a scheme: the cave biome's rock, keeping ore veins.
static func shell_block(net: CaveNetwork, cid: int, scheme: int, b: int, x: int, y: int, z: int, seed_value: int) -> int:
	if KEEP.has(b):
		return b
	var floor_y := minf(net.field(cid, CaveNetwork.F_AY), net.field(cid, CaveNetwork.F_BY))
	match int(net.field(cid, CaveNetwork.F_TYPE)):
		CaveNetwork.Type.BLOB:
			floor_y = net.field(cid, CaveNetwork.F_AY) - net.field(cid, CaveNetwork.F_BY) * 0.45
		CaveNetwork.Type.WORM:
			floor_y -= net.field(cid, CaveNetwork.F_R0) * 0.3
		CaveNetwork.Type.ROOM:
			floor_y = net.field(cid, CaveNetwork.F_AY)
	var h := WorldGen._hash3(x >> 3, y >> 2, z >> 3, seed_value + 907)
	return CaveBiomes.scheme_block(scheme, Vector3i(x, y, z), float(y) < floor_y + 0.6, h)


# --- Passages --------------------------------------------------------------------------------

## A winding natural passage from `start` to `target`, never steeper than MAX_GRADE: when the
## drop is too great it spirals around the target. Stays under the ground after the first
## segments. Returns the number of segments added.
static func tunnel(ctx: Ctx, start: Vector3, target: Vector3, r_min: float, r_max: float, scheme := 0, lump := 0.8) -> int:
	var rng := ctx.rng
	var cur := start
	var dir := Vector2(target.x - start.x, target.z - start.z)
	dir = dir.normalized() if dir.length() > 0.1 else Vector2.RIGHT
	var r := rng.randf_range(r_min, r_max)
	var spin := 1.0 if rng.randf() < 0.5 else -1.0
	const STEP := 10.0
	var n := 0
	for seg in 120:
		var to_t := Vector2(target.x - cur.x, target.z - cur.z)
		var dist := to_t.length()
		var drop := cur.y - target.y
		var next := Vector3.ZERO
		if dist < STEP * 1.3 and absf(drop) < STEP * MAX_GRADE * 1.3:
			next = target
		else:
			var want := to_t / maxf(dist, 0.001)
			if absf(drop) > (dist - STEP) * MAX_GRADE:
				want = (want.orthogonal() * spin * 0.85 + want * (0.15 if dist > 40.0 else -0.4)).normalized()
			dir = (dir * 0.5 + want * 0.5 + Vector2(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25))).normalized()
			var dy := -clampf(drop, -STEP * MAX_GRADE, STEP * MAX_GRADE)
			next = cur + Vector3(dir.x * STEP, dy, dir.y * STEP)
			next.x = clampf(next.x, 48.0, ctx.gen.size - 48.0)
			next.z = clampf(next.z, 48.0, ctx.gen.size - 48.0)
			if seg > 1:
				# Keep a roof of rock overhead (no accidental second mouth).
				next.y = minf(next.y, ctx.ground(next.x, next.z) - r - 4.0)
		var r2 := clampf(r + rng.randf_range(-0.5, 0.5), r_min, r_max)
		var id := ctx.net.add_worm(cur, next, r, r2, lump)
		if scheme > 0:
			ctx.net.set_scheme(id, scheme)
		n += 1
		r = r2
		cur = next
		if next == target:
			break
	return n


## A hillside mouth near `near` (searched on a ring of radii) whose passage winds down to
## `target`. `hidden`: a narrow cleft. Returns the surface point, or Vector3.INF.
static func hillside_entrance(ctx: Ctx, near: Vector2, r_lo: float, r_hi: float, target: Vector3, hidden: bool) -> Vector3:
	var gen := ctx.gen
	var radius := 1.9 if hidden else 3.0
	for attempt in 64:
		var a := ctx.rng.randf() * TAU
		var p := near + Vector2.from_angle(a) * ctx.rng.randf_range(r_lo, r_hi)
		if not ctx.inside(p, 120.0) or gen.is_protected(p.x, p.y) or gen.lake_level(p.x, p.y).x > -INF:
			continue
		if gen.biome_at(int(p.x), int(p.y)) == WorldGen.Biome.OCEAN:
			continue
		var g := ctx.ground(p.x, p.y)
		if g < WorldGen.SEA_LEVEL + 6.0:
			continue
		var grad := Vector2(ctx.ground(p.x + 4, p.y) - ctx.ground(p.x - 4, p.y), ctx.ground(p.x, p.y + 4) - ctx.ground(p.x, p.y - 4)) / 8.0
		var slope := grad.length()
		if slope < 0.3 or slope > 1.4:
			continue
		var into := grad / slope
		var e := Vector3(p.x, g, p.y)
		var b := e + Vector3(into.x, 0, into.y) * 12.0 + Vector3(0, radius * 0.55 - 2.4, 0)
		if ctx.ground(b.x, b.z) - b.y < radius + 2.5:
			continue
		var a0 := e - Vector3(into.x, 0, into.y) * 2.5 + Vector3(0, radius * 0.55 - 0.5, 0)
		ctx.net.add_worm(a0, b, radius + (0.2 if hidden else 0.6), radius, 0.9)
		tunnel(ctx, b, target, radius, radius + (1.0 if hidden else 1.4))
		return e
	return Vector3.INF


# --- Great caverns ---------------------------------------------------------------------------

static func _grand_caverns(ctx: Ctx) -> void:
	var gen := ctx.gen
	var n := gen.size / int(CaveBiomes.CELL.x)
	var cells: Array[Vector2i] = []
	for kz in range(2, n - 2):
		for kx in range(2, n - 2):
			cells.append(Vector2i(kx, kz))
	_shuffle(cells, ctx.rng)
	var made := 0
	for cell in cells:
		if made >= GRAND_CAVERNS:
			break
		var level := -1 if ctx.rng.randf() < 0.6 else -2
		var c := Vector3((cell.x + 0.5) * CaveBiomes.CELL.x, (level + 0.5) * CaveBiomes.CELL.y, (cell.y + 0.5) * CaveBiomes.CELL.z)
		var region := CaveBiomes.region(c, gen.world_seed, gen.revision)
		var kind := int(region["kind"])
		if not kind in [CaveBiomes.Kind.LUSH, CaveBiomes.Kind.DRIPSTONE, CaveBiomes.Kind.OCHRE, CaveBiomes.Kind.VERDIGRIS,
				CaveBiomes.Kind.VIOLET, CaveBiomes.Kind.SANDSTONE, CaveBiomes.Kind.KARST, CaveBiomes.Kind.FUNGAL]:
			continue
		var rx := ctx.rng.randf_range(66.0, 92.0)
		var rz := rx * ctx.rng.randf_range(0.7, 1.15)
		var ry := ctx.rng.randf_range(28.0, 36.0)
		var c2 := Vector2(c.x, c.z)
		if not ctx.is_free(c2, maxf(rx, rz) + 30.0) or not ctx.clear_of_sites(c2, maxf(rx, rz) * 0.5):
			continue
		var floor_y := clampf(c.y - ry * 0.2, -100.0, -30.0)
		var cy := floor_y + ry * 0.6
		var top := cy + ry
		if ctx.min_ground(c2, maxf(rx, rz)) < top + 14.0:
			continue
		if ctx.near_pools(Vector3(c.x, cy, c.z), maxf(rx, rz) * 0.75):
			continue
		var centre := Vector3(c.x, cy, c.z)
		var id := ctx.net.add_blob(centre, Vector3(rx, ry, rz), 2.2)
		ctx.net.set_scheme(id, kind)
		# Side halls and a high gallery give the hall an irregular outline.
		for k in 4:
			var a := ctx.rng.randf() * TAU
			var off := Vector3(cos(a) * rx * 0.62, ctx.rng.randf_range(-2.0, 8.0), sin(a) * rz * 0.62)
			var side := ctx.net.add_blob(centre + off, Vector3(rx * 0.42, ry * 0.55, rz * 0.42), 1.8)
			ctx.net.set_scheme(side, kind)
		# Doorways into the region's own chamber and to the next region.
		tunnel(ctx, Vector3(c.x + rx * 0.7, floor_y + 3.0, c.z), Vector3(c.x + CaveBiomes.CELL.x * 0.85, (region["center"] as Vector3).y - 6.0, c.z), 3.0, 4.2, kind)
		ctx.taken.append([c2, maxf(rx, rz)])
		var title: String = "Great " + String(CaveBiomes.NAMES[kind]).trim_prefix("The ")
		if kind == CaveBiomes.Kind.KARST:
			title = "The Great Hollow"
		ctx.zone(centre - Vector3(rx, ry * 0.7, rz) * 1.08, centre + Vector3(rx, ry, rz) * 1.08, kind, title)
		made += 1


# --- Layered sandstone caves -------------------------------------------------------------------

static func _layered(ctx: Ctx) -> void:
	var gen := ctx.gen
	var n := gen.size / int(CaveBiomes.CELL.x)
	for kz in range(1, n - 1):
		for kx in range(1, n - 1):
			var c := Vector3((kx + 0.5) * CaveBiomes.CELL.x, -32.0, (kz + 0.5) * CaveBiomes.CELL.z)
			var region := CaveBiomes.region(c, gen.world_seed, gen.revision)
			if int(region["kind"]) != CaveBiomes.Kind.SANDSTONE or not ctx.is_free(Vector2(c.x, c.z), 40.0):
				continue
			var r := CaveBiomes.radii_of(region)
			var base := c.y - r.y * 0.55
			var yaw := ctx.rng.randf() * PI
			var half := Vector2(r.x * 0.85, r.z * 0.85)
			# Shelves stepping up and back: each bed overhangs the one below.
			for step in 4:
				var f := float(step)
				var id := ctx.net.add_room(Vector3(c.x, base + f * 3.2, c.z), half.x + f * 2.6, half.y + f * 2.6, 3.4, yaw + f * 0.08)
				ctx.net.set_scheme(id, CaveBiomes.Kind.SANDSTONE)


# --- Fissures ----------------------------------------------------------------------------------

static func _fissures(ctx: Ctx) -> void:
	var gen := ctx.gen
	var made := 0
	for attempt in FISSURES * 6:
		if made >= FISSURES:
			break
		var a := Vector2(ctx.rng.randf_range(150.0, gen.size - 150.0), ctx.rng.randf_range(150.0, gen.size - 150.0))
		var dir := Vector2.from_angle(ctx.rng.randf() * TAU)
		var length := ctx.rng.randf_range(60.0, 150.0)
		var b := a + dir * length
		var height := ctx.rng.randf_range(16.0, 38.0)
		var floor_a := ctx.rng.randf_range(-92.0, -24.0)
		var floor_b := floor_a + ctx.rng.randf_range(-length * 0.15, length * 0.15)
		var top := maxf(floor_a, floor_b) + height
		var ok := true
		for k in 5:
			var p := a.lerp(b, k / 4.0)
			if ctx.ground(p.x, p.y) < top + 10.0 or not ctx.is_free(p, 6.0):
				ok = false
				break
		if not ok or floor_b < -104.0 or ctx.near_pools(Vector3((a.x + b.x) * 0.5, floor_a, (a.y + b.y) * 0.5), length * 0.5):
			continue
		var kind := int(CaveBiomes.region(Vector3((a.x + b.x) * 0.5, floor_a + 4.0, (a.y + b.y) * 0.5), gen.world_seed, gen.revision)["kind"])
		var id := ctx.net.add_slot(Vector3(a.x, floor_a, a.y), Vector3(b.x, floor_b, b.y), ctx.rng.randf_range(2.4, 4.2), height, 1.1)
		if kind >= CaveBiomes.Kind.LUSH:
			ctx.net.set_scheme(id, kind)
		made += 1


# --- Shafts ----------------------------------------------------------------------------------

static func _shafts(ctx: Ctx) -> void:
	var gen := ctx.gen
	var made := 0
	var open := 0
	for attempt in SHAFTS * 8:
		if made >= SHAFTS:
			break
		var p := Vector2(ctx.rng.randf_range(160.0, gen.size - 160.0), ctx.rng.randf_range(160.0, gen.size - 160.0))
		var r := ctx.rng.randf_range(3.2, 6.5)
		var g := ctx.ground(p.x, p.y)
		var bottom := ctx.rng.randf_range(-96.0, -50.0)
		var to_surface := open < OPEN_SHAFTS and ctx.rng.randf() < 0.45
		if not ctx.is_free(p, r + 4.0) or ctx.near_pools(Vector3(p.x, bottom, p.y), 20.0):
			continue
		var top := ctx.rng.randf_range(-30.0, -12.0)
		if to_surface:
			# A daylight shaft: open sky over a deep pit, on level, unclaimed land.
			if g < WorldGen.SEA_LEVEL + 8.0 or gen.is_protected(p.x, p.y) or gen.lake_level(p.x, p.y).x > -INF or not ctx.clear_of_sites(p, 40.0):
				continue
			var rim := true
			for k in 6:
				var q := p + Vector2.from_angle(TAU * k / 6.0) * (r + 6.0)
				if absf(ctx.ground(q.x, q.y) - g) > 4.0 or gen.is_protected(q.x, q.y):
					rim = false
					break
			if not rim:
				continue
			top = g + 3.0
		elif g < top + r + 14.0:
			continue
		var wob := Vector3(ctx.rng.randf_range(-3, 3), 0, ctx.rng.randf_range(-3, 3))
		var mid := Vector3(p.x, (bottom + top) * 0.5, p.y) + wob
		ctx.net.add_worm(Vector3(p.x, bottom, p.y), mid, r + 1.0, r, 1.2)
		ctx.net.add_worm(mid, Vector3(p.x, top, p.y), r, r * (0.8 if to_surface else 1.0), 1.2)
		# A chamber at the foot so the shaft lands somewhere.
		ctx.net.add_blob(Vector3(p.x, bottom + 3.0, p.y), Vector3(r + 6.0, 5.0, r + 6.0), 1.2)
		tunnel(ctx, Vector3(p.x, bottom + 1.0, p.y), Vector3(p.x + ctx.rng.randf_range(-60, 60), bottom + ctx.rng.randf_range(-6, 10), p.y + ctx.rng.randf_range(-60, 60)), 2.6, 3.6)
		if to_surface:
			ctx.openings.append([Vector3(p.x, g, p.y), Vector3(p.x, bottom, p.y), r])
			open += 1
		ctx.taken.append([p, r + 2.0])
		made += 1


# --- Lava tubes ------------------------------------------------------------------------------

static func _tubes(ctx: Ctx) -> void:
	var gen := ctx.gen
	var made := 0
	for attempt in TUBES * 10:
		if made >= TUBES:
			break
		var start := Vector3(ctx.rng.randf_range(250.0, gen.size - 250.0), ctx.rng.randf_range(-100.0, -40.0), ctx.rng.randf_range(250.0, gen.size - 250.0))
		var heading := Vector2.from_angle(ctx.rng.randf() * TAU)
		var segs := ctx.rng.randi_range(14, 26)
		var pts: Array[Vector3] = [start]
		var ok := true
		var cur := start
		for s in segs:
			heading = heading.rotated(ctx.rng.randf_range(-0.28, 0.28))
			cur = cur + Vector3(heading.x * 13.0, ctx.rng.randf_range(-1.6, 0.6), heading.y * 13.0)
			cur.y = clampf(cur.y, -102.0, -30.0)
			if not ctx.inside(Vector2(cur.x, cur.z), 120.0) or ctx.ground(cur.x, cur.z) < cur.y + 20.0:
				ok = false
				break
			pts.append(cur)
		if not ok or ctx.near_pools(start, 30.0) or ctx.near_pools(cur, 30.0):
			continue
		var lava := start.y < -78.0 and ctx.rng.randf() < 0.6
		var r := ctx.rng.randf_range(4.0, 5.5)
		var lo := start
		var hi := start
		for i in pts.size() - 1:
			var r2 := clampf(r + ctx.rng.randf_range(-0.6, 0.6), 3.6, 6.2)
			var a := pts[i]
			var b := pts[i + 1]
			var level := minf(a.y, b.y) - r * 0.5 + 0.5 if lava else CaveNetwork.NO_WATER
			var id := ctx.net.add_worm(a, b, r, r2, 0.35, level, Blocks.LAVA)
			ctx.net.set_scheme(id, CaveBiomes.Kind.TUBE)
			lo = lo.min(b)
			hi = hi.max(b)
			r = r2
		var pad := Vector3(8, 7, 8)
		ctx.zone(lo - pad, hi + pad, CaveBiomes.Kind.TUBE, "Old Lava Tubes")
		# Skylights: the roof has fallen in at one end into the cave above.
		tunnel(ctx, pts[0], pts[0] + Vector3(ctx.rng.randf_range(-50, 50), 14.0, ctx.rng.randf_range(-50, 50)), 2.6, 3.4)
		made += 1


# --- Flooded grottos ---------------------------------------------------------------------------

static func _grottos(ctx: Ctx) -> void:
	var gen := ctx.gen
	var made := 0
	for attempt in GROTTOS * 8:
		if made >= GROTTOS:
			break
		var p := Vector2(ctx.rng.randf_range(200.0, gen.size - 200.0), ctx.rng.randf_range(200.0, gen.size - 200.0))
		var rx := ctx.rng.randf_range(16.0, 28.0)
		var ry := ctx.rng.randf_range(7.0, 11.0)
		var cy := ctx.rng.randf_range(-62.0, -22.0)
		if not ctx.is_free(p, rx + 8.0) or ctx.ground(p.x, p.y) < cy + ry + 14.0 or ctx.near_pools(Vector3(p.x, cy, p.y), rx + 30.0):
			continue
		var level := cy - ry * 0.35
		var id := ctx.net.add_blob(Vector3(p.x, cy, p.y), Vector3(rx, ry, rx * ctx.rng.randf_range(0.7, 1.2)), 1.3, level, Blocks.WATER)
		var kind := CaveBiomes.Kind.DRIPSTONE if ctx.rng.randf() < 0.5 else CaveBiomes.Kind.VERDIGRIS
		ctx.net.set_scheme(id, kind)
		# A dry ledge passage leading in, just above the water.
		var region := CaveBiomes.region(Vector3(p.x, cy, p.y), gen.world_seed, gen.revision)
		var rc: Vector3 = region["center"]
		var edge := Vector3(p.x, level + 2.4, p.y) + (Vector3(rc.x - p.x, 0, rc.z - p.y).normalized() * rx * 0.8)
		tunnel(ctx, edge, Vector3(rc.x, rc.y - CaveBiomes.radii_of(region).y * 0.3, rc.z), 2.6, 3.4)
		ctx.taken.append([p, rx])
		made += 1


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t
