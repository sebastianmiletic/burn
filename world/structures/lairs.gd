class_name Lairs
extends RefCounted
## Blueprints for the creature lairs added with the Leviathan:
##   * The Drowned Spire - a ruined sea platform on a rocky islet in the Grey
##     Sea, reached by a broken stone causeway; the Leviathan circles it.
##     A drowned tower rises from the waves behind the arena.
##   * The Weeping Hollow - a sinkhole ringed by old stones in Emberwood; a
##     winding cave tunnel leads down to a vast webbed cavern where the
##     Broodmother nests.
##   * Hagsfen - a clearing deep in Blackmarsh: black pools, standing
##     stones, dead trees and a witch's hut on stilts.
## Built things are invisible STRUCTURE collision; their meshes come from the
## arena props ("type": "arena") built by world/architecture/arenas/lair_arenas.gd.
## Natural rock, mud, water and lava stay smooth terrain.
## Spawn types used: boss, enemy, chest, lore, shrine, arena_gate.

const SEA := WorldGen.SEA_LEVEL
const S := Blocks.STRUCTURE


static func _w(bp: Blueprint, local: Vector3) -> Vector3:
	return Vector3(bp.origin) + local + Vector3(0.5, 0.0, 0.5)


## Floor-top centre above local cell `lc` (see Battlegrounds for the convention).
static func _center(bp: Blueprint, lc: Vector3i) -> Vector3:
	return Vector3(bp.origin + lc) + Vector3(0.5, 1.0, 0.5)


static func _arena_prop(loc: Location) -> Dictionary:
	for p: Dictionary in loc.props:
		if String(p.get("type", "")) == "arena":
			return p
	return {}


# --- The Drowned Spire ----------------------------------------------------------------

## `out_dir`: horizontal direction from the coast out to sea.
static func drowned_spire(loc: Location, out_dir: Vector2, rng: RandomNumberGenerator) -> void:
	loc.ground_y = SEA + 2
	loc.radius = 40.0
	loc.pad_radius = 17.0
	loc.pad_falloff = 9.0
	var below := 24
	var half := 42
	var c := Vector3i(roundi(loc.center.x), loc.ground_y, roundi(loc.center.z))
	var bp := Blueprint.new(Vector3i(c.x - half, loc.ground_y - below, c.z - half), Vector3i(half * 2 + 1, below + 36, half * 2 + 1))
	loc.blueprints.append(bp)
	var lc := Vector3i(half, below, half)  # platform surface cell, local
	var fy := lc.y
	var away := Vector3(out_dir.x, 0, out_dir.y).normalized()
	var toward_coast := -away
	# Rugged islet: granite boulders around the pad, half in the sea.
	for i in 16:
		var a := TAU * float(i) / 16.0 + rng.randf_range(-0.15, 0.15)
		var r := rng.randf_range(17.0, 21.0)
		var p := lc + Vector3i(roundi(cos(a) * r), rng.randi_range(-5, -1), roundi(sin(a) * r))
		bp.sphere(p, rng.randf_range(2.5, 4.2), Blocks.GRANITE if i % 3 else Blocks.STONE)
	# Foundation rock and the platform (flagstones are modelled over STRUCTURE).
	for dz in range(-17, 18):
		for dx in range(-17, 18):
			var d := Vector2(dx, dz).length()
			if d > 16.6:
				continue
			bp.fill(Vector3i(lc.x + dx, fy - 3, lc.z + dz), Vector3i(lc.x + dx, fy - 1, lc.z + dz), Blocks.STONE)
			bp.set_local(lc.x + dx, fy, lc.z + dz, S)
			bp.fill(Vector3i(lc.x + dx, fy + 1, lc.z + dz), Vector3i(lc.x + dx, fy + 12, lc.z + dz), Blueprint.CARVE)
	# Broken balustrade around the rim (a gap faces the causeway).
	var rail := PackedByteArray()
	rail.resize(72)
	for i in 72:
		var a := TAU * float(i) / 72.0
		var dir := Vector3(cos(a), 0, sin(a))
		if dir.dot(toward_coast) > 0.94:
			continue
		if (i / 3) % 3 == 2 or rng.randf() < 0.15:
			continue
		rail[i] = 1
		bp.set_local(lc.x + roundi(cos(a) * 16.0), fy + 1, lc.z + roundi(sin(a) * 16.0), S)
	# A ring of columns, some standing, some broken or fallen.
	var columns: Array = []
	for i in 12:
		var a := TAU * float(i) / 12.0 + PI / 12.0
		var p := lc + Vector3i(roundi(cos(a) * 13.0), 1, roundi(sin(a) * 13.0))
		var kind := rng.randi() % 4
		var h := 0
		if kind == 0:
			# Fallen drums along the floor.
			var along := Vector2(-sin(a), cos(a))
			for s in 5:
				bp.set_local(p.x + roundi(along.x * s), fy + 1, p.z + roundi(along.y * s), S)
		else:
			h = rng.randi_range(3, 9) if kind != 3 else 1
			bp.cylinder(p, 0.9, h, S)
			if h >= 8:
				bp.cylinder(p + Vector3i(0, h, 0), 1.4, 1, S)
		columns.append([Vector3(p - lc) - Vector3(0, 1, 0), a, kind, h])
	# The drowned tower: rising from the sea behind the arena.
	var tc := lc + Vector3i(roundi(away.x * 32.0), 0, roundi(away.z * 32.0))
	bp.sphere(Vector3i(tc.x, 4, tc.z), 8.0, Blocks.GRANITE)
	bp.cylinder(Vector3i(tc.x, 2, tc.z), 5.5, fy + 26, S, true)
	for y: int in [fy + 4, fy + 12, fy + 20]:
		bp.cylinder(Vector3i(tc.x, y, tc.z), 4.6, 1, S)
	var breaks: Array = []
	for i in 4:
		var a := rng.randf() * TAU
		var bc := Vector3i(tc.x + roundi(cos(a) * 5.0), fy + 24 + rng.randi_range(0, 6), tc.z + roundi(sin(a) * 5.0))
		var br := rng.randf_range(2.5, 4.0)
		bp.sphere(bc, br, Blueprint.CARVE)
		breaks.append([Vector3(bc - lc) - Vector3(0, 1, 0), br])
	# Lamp posts (iron, modelled) on the diagonals.
	var lamps: Array = []
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI / 4.0
		var p := lc + Vector3i(roundi(cos(a) * 9.0), 1, roundi(sin(a) * 9.0))
		bp.set_local(p.x, p.y, p.z, S)
		lamps.append(Vector3(p - lc) - Vector3(0, 1, 0))
	var center := _center(bp, lc)
	var side := Vector3(toward_coast.z, 0, -toward_coast.x)
	loc.props.append({"type": "arena", "material": "arena", "arena": "drowned_spire", "center": center, "radius": 70.0, "seed": rng.randi(),
			"away": away, "rail": rail, "columns": columns, "tower": Vector3(tc - lc) - Vector3(0, 1, 0), "tower_h": float(fy + 26 + 2 - lc.y - 1),
			"tower_base": float(2 - lc.y - 1), "breaks": breaks, "lamps": lamps,
			"braziers": [side * 11.5 + away * 4.0, side * -11.5 + away * 4.0], "ribs": Vector3(-away.z, 0, away.x) * 20.5 + Vector3(0, -1.5, 0),
			"bones": Vector3(-away.z, 0, away.x) * -12.0 + away * 4.0})
	# Spawns.
	loc.add_spawn("boss", _w(bp, Vector3(lc) + Vector3(0, 1, 0)), {"kind": "leviathan"})
	var land := Vector3(lc) + toward_coast * 13.0 + Vector3(0, 1, 0)
	loc.add_spawn("lore", _w(bp, land + side * 2.5), {"text": "leviathan"})
	loc.add_spawn("chest", _w(bp, Vector3(lc) + away * 11.0 + Vector3(0, 1, 0)), {"tier": 3})
	for s: float in [-1.0, 1.0]:
		var p := Vector3(lc) + side * s * 9.0 + toward_coast * 5.0 + Vector3(0, 1, 0)
		loc.add_spawn("enemy", _w(bp, p), {"kind": "drowned"})
	# Sharks patrol the deep water off the islet.
	for i in 2:
		var a := atan2(away.z, away.x) + (1.3 if i == 0 else -1.3)
		loc.add_spawn("enemy", _w(bp, Vector3(lc) + Vector3(cos(a), 0, sin(a)) * 33.0 + Vector3(0, -6, 0)), {"kind": "shark"})
	loc.center = _w(bp, Vector3(lc) + Vector3(0, 1, 0))
	loc.half_height = 0.0


## A broken stone causeway from `from` (on the coast) to `to` (the platform rim).
static func causeway(loc: Location, from: Vector2, to: Vector2, rng: RandomNumberGenerator) -> void:
	var deck_y := SEA + 2
	var lo := Vector2(minf(from.x, to.x), minf(from.y, to.y)) - Vector2(6, 6)
	var hi := Vector2(maxf(from.x, to.x), maxf(from.y, to.y)) + Vector2(6, 6)
	var y0 := -14
	var bp := Blueprint.new(Vector3i(int(floor(lo.x)), y0, int(floor(lo.y))), Vector3i(int(hi.x - lo.x) + 1, deck_y + 12 - y0, int(hi.y - lo.y) + 1))
	loc.blueprints.append(bp)
	var length := from.distance_to(to)
	var dir := (to - from).normalized()
	var side := Vector2(-dir.y, dir.x)
	var gaps := [length * 0.38, length * 0.66]
	var steps := int(length / 0.4)
	var parapet: Array = []   # [d0, d1] stretches with a low wall
	for s in steps + 1:
		var t := float(s) / steps
		var d := t * length
		var p := from.lerp(to, t)
		var in_gap := false
		for g: float in gaps:
			if absf(d - g) < 1.1:
				in_gap = true
		for w in range(-3, 4):
			var q := p + side * (float(w) * 0.5)
			var lx := int(floor(q.x)) - bp.origin.x
			var lz := int(floor(q.y)) - bp.origin.z
			var ly := deck_y - y0
			if absf(float(w) * 0.5) <= 1.5:
				if not in_gap:
					bp.set_local(lx, ly, lz, S)
					bp.set_local(lx, ly - 1, lz, S)
				for up in range(1, 5):
					bp.set_local(lx, ly + up, lz, Blueprint.CARVE)
			elif not in_gap and fmod(d, 9.0) < 5.0 and d > 2.0 and d < length - 2.0:
				bp.set_local(lx, ly + 1, lz, S)
	# Piers down to the sea bed every 7 m.
	var piers := PackedFloat32Array()
	var dd := 7.0
	while dd < length - 3.0:
		if dd > 3.0:
			piers.append(dd)
			var p := from.lerp(to, dd / length)
			for w2 in range(-1, 2):
				var q := p + side * float(w2)
				var lx := int(floor(q.x)) - bp.origin.x
				var lz := int(floor(q.y)) - bp.origin.z
				for y in range(0, deck_y - y0 - 1):
					bp.set_local(lx, y, lz, S)
		dd += 7.0
	# A ruined gateway near the islet end.
	var g := from.lerp(to, 0.85)
	for sgn: float in [-1.0, 1.0]:
		var q := g + side * sgn * 2.5
		var lx := int(floor(q.x)) - bp.origin.x
		var lz := int(floor(q.y)) - bp.origin.z
		for y in range(deck_y - y0 - 1, deck_y - y0 + 7):
			bp.set_local(lx, y, lz, S)
	for w in range(-3, 4):
		if w == 2:
			continue
		var q := g + side * float(w) * 0.8
		bp.set_local(int(floor(q.x)) - bp.origin.x, deck_y - y0 + 7, int(floor(q.y)) - bp.origin.z, S)
	var prop := _arena_prop(loc)
	if not prop.is_empty():
		prop["causeway"] = {"from": Vector3(from.x, deck_y + 1, from.y), "to": Vector3(to.x, deck_y + 1, to.y), "gaps": gaps, "piers": piers, "gateway": 0.85}


# --- The Weeping Hollow (Broodmother) -----------------------------------------------

## surface: the sinkhole; lair: the cavern. `dir` = axis direction of the tunnel.
## cavern_floor: world y the cavern floor stands at.
static func weeping_hollow(surface: Location, lair: Location, dir: Vector2i, cavern_floor: int, rng: RandomNumberGenerator) -> void:
	surface.radius = 12.0
	surface.pad_radius = 9.0
	surface.pad_falloff = 6.0
	var s := Vector3i(roundi(surface.center.x), surface.ground_y, roundi(surface.center.z))
	var along := Vector3i(dir.x, 0, dir.y)
	var across := Vector3i(dir.y, 0, -dir.x)
	var tunnel_len := 78
	var cav_r := 27
	var reach := tunnel_len + cav_r + 6
	var lo := s + along * -10 + across * -34
	var hi := s + along * reach + across * 34
	var mn := Vector3i(mini(lo.x, hi.x), cavern_floor - 6, mini(lo.z, hi.z))
	var mx := Vector3i(maxi(lo.x, hi.x), s.y + 14, maxi(lo.z, hi.z))
	var bp := Blueprint.new(mn, mx - mn + Vector3i.ONE)
	surface.blueprints.append(bp)
	var ls := s - mn  # local sinkhole centre at ground level
	var fy := cavern_floor - mn.y
	# Ruined ring of standing stones around the sinkhole (STRUCTURE, modelled).
	var stones: Array = []
	for i in 9:
		var a := TAU * float(i) / 9.0
		var p := ls + Vector3i(roundi(cos(a) * 7.5), 1, roundi(sin(a) * 7.5))
		var h := rng.randi_range(1, 4)
		bp.fill(p, p + Vector3i(0, h, 0), S)
		stones.append([Vector3(p - ls) - Vector3(0, 1, 0), h + 1, a])
	# The tunnel: a winding natural cave sloping down to the cavern.
	var drop := ls.y - fy
	var wander := 0.0
	var tunnel: Array = []
	for i in tunnel_len + 4:
		var f := clampf(float(i) / tunnel_len, 0.0, 1.0)
		var y := ls.y - int(round(drop * f)) + 2
		wander = clampf(wander + rng.randf_range(-0.5, 0.5), -5.0, 5.0)
		var p := ls + along * i + across * roundi(wander * sin(f * PI))
		bp.sphere(Vector3i(p.x, y, p.z), rng.randf_range(2.6, 3.3), Blueprint.CARVE)
		if i % 11 == 5 and i > 8:
			tunnel.append(Vector3(p.x - ls.x, y - 2 - ls.y, p.z - ls.z))
	# The cavern.
	var cc := ls + along * (tunnel_len + cav_r - 4)
	cc.y = fy
	bp.ellipsoid(Vector3i(cc.x, fy + 9, cc.z), Vector3(cav_r, 13, cav_r), Blueprint.CARVE)
	for dz in range(-cav_r, cav_r + 1):
		for dx in range(-cav_r, cav_r + 1):
			if dx * dx + dz * dz > cav_r * cav_r:
				continue
			bp.fill(Vector3i(cc.x + dx, fy - 4, cc.z + dz), Vector3i(cc.x + dx, fy - 1, cc.z + dz), Blocks.STONE)
			if rng.randf() < 0.05:
				bp.set_local(cc.x + dx, fy - 1, cc.z + dz, Blocks.GRAVEL)
	# Pillars of rock from floor to roof, and stalactites.
	var pillars: Array = []
	for i in 6:
		var a := TAU * float(i) / 6.0 + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(13.0, 20.0)
		var p := Vector3i(cc.x + roundi(cos(a) * r), fy, cc.z + roundi(sin(a) * r))
		for y in 24:
			var t := absf(float(y) - 11.0) / 11.0
			bp.cylinder(p + Vector3i(0, y, 0), 1.3 + t * t * 2.2, 1, Blocks.STONE)
		pillars.append(Vector3(p - cc))
	for i in 14:
		var a := rng.randf() * TAU
		var r := rng.randf_range(4.0, 22.0)
		var p := Vector3i(cc.x + roundi(cos(a) * r), fy + 20, cc.z + roundi(sin(a) * r))
		var h := rng.randi_range(2, 6)
		for y in h:
			bp.cylinder(p - Vector3i(0, y, 0), 1.4 * (1.0 - float(y) / h), 1, Blocks.STONE)
	# Amethyst glinting in the walls.
	for i in 40:
		var a := rng.randf() * TAU
		var e := rng.randf_range(-0.6, 0.9)
		var p := Vector3i(cc.x + roundi(cos(a) * (cav_r + 0.5) * cos(e)), fy + 9 + roundi(sin(e) * 13.0), cc.z + roundi(sin(a) * (cav_r + 0.5) * cos(e)))
		bp.set_local(p.x, p.y, p.z, Blocks.AMETHYST)
	# A still black pool.
	var pool := Vector3i(cc.x + across.x * 14, fy - 1, cc.z + across.z * 14)
	bp.cylinder(pool - Vector3i(0, 1, 0), 3.5, 2, Blocks.WATER)
	# Spawns.
	var mouth := ls + along * (tunnel_len - 2)
	mouth.y = fy
	var lair_center := _center(bp, cc - Vector3i(0, 1, 0))
	lair.props.append({"type": "arena", "material": "arena", "arena": "broodmother", "center": lair_center, "radius": 70.0, "seed": rng.randi(),
			"along": Vector3(along), "across": Vector3(across), "cav_r": float(cav_r), "pillars": pillars, "pool": Vector3(pool - cc) + Vector3(0, 1, 0),
			"mouth": Vector3(mouth - cc), "tunnel": tunnel, "tunnel_origin": Vector3(ls - cc), "stones": stones, "gate": 0})
	lair.add_spawn("boss", _w(bp, Vector3(cc) + Vector3(0, 0, 0)), {"kind": "broodmother"})
	lair.add_spawn("arena_gate", _w(bp, Vector3(mouth)), {"along": along, "across": across, "width": 3, "height": 6})
	for i in 3:
		var p := ls + along * (20 + i * 20)
		var f := clampf(float(20 + i * 20) / tunnel_len, 0.0, 1.0)
		p.y = ls.y - int(round(drop * f)) + 0
		surface.add_spawn("enemy", _w(bp, Vector3(p)), {"kind": "giant_spider"})
	for i in 2:
		var a := TAU * float(i) / 2.0 + 1.0
		lair.add_spawn("enemy", _w(bp, Vector3(cc.x + cos(a) * 14.0, fy, cc.z + sin(a) * 14.0)), {"kind": "giant_spider"})
	lair.add_spawn("enemy", _w(bp, Vector3(ls + along * 40) + Vector3(0, -int(round(drop * 40.0 / tunnel_len)) + 3, 0)), {"kind": "bat_swarm"})
	lair.add_spawn("chest", _w(bp, Vector3(cc) + Vector3(along) * (cav_r - 5)), {"tier": 3})
	surface.add_spawn("lore", _w(bp, Vector3(ls) + Vector3(across) * 4.0 + Vector3(0, 1, 0)), {"text": "broodmother"})
	surface.center = _w(bp, Vector3(ls) + Vector3(0, 1, 0))
	lair.center = _w(bp, Vector3(cc) + Vector3(0, 1, 0))
	lair.radius = float(cav_r) + 4.0
	lair.half_height = 14.0
	lair.ground_y = cavern_floor


# --- Hagsfen (Bog Hag) -------------------------------------------------------------------

static func hagsfen(loc: Location, rng: RandomNumberGenerator) -> void:
	loc.radius = 26.0
	loc.pad_radius = 20.0
	loc.pad_falloff = 10.0
	var half := 28
	var below := 5
	var c := Vector3i(roundi(loc.center.x), loc.ground_y, roundi(loc.center.z))
	var bp := Blueprint.new(Vector3i(c.x - half, loc.ground_y - below, c.z - half), Vector3i(half * 2 + 1, below + 18, half * 2 + 1))
	loc.blueprints.append(bp)
	var lc := Vector3i(half, below, half)
	var fy := lc.y
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.12
	# Boggy clearing.
	for dz in range(-21, 22):
		for dx in range(-21, 22):
			if dx * dx + dz * dz > 21 * 21:
				continue
			var n := noise.get_noise_2d(dx, dz)
			bp.set_local(lc.x + dx, fy, lc.z + dz, Blocks.MUD if n < 0.25 else Blocks.GRASS)
			bp.set_local(lc.x + dx, fy - 1, lc.z + dz, Blocks.MUD)
			bp.fill(Vector3i(lc.x + dx, fy + 1, lc.z + dz), Vector3i(lc.x + dx, fy + 3, lc.z + dz), Blueprint.CARVE)
	# Black pools.
	var pools: Array[Vector3i] = []
	var pool_info: Array = []
	for i in 4:
		var a := TAU * float(i) / 4.0 + rng.randf_range(-0.3, 0.3) + 0.4
		var r := rng.randf_range(9.0, 14.0)
		var p := Vector3i(lc.x + roundi(cos(a) * r), fy, lc.z + roundi(sin(a) * r))
		var pr := rng.randf_range(2.4, 3.6)
		bp.cylinder(p - Vector3i(0, 1, 0), pr, 2, Blocks.WATER)
		pools.append(p)
		pool_info.append([Vector3(p - lc), pr])
	# The hut on stilts at the back of the clearing (collision only; modelled).
	var back := Vector3i(0, 0, -1)
	var hc := lc + back * 15
	var x0 := hc.x - 4
	var x1 := hc.x + 4
	var z0 := hc.z - 3
	var z1 := hc.z + 3
	var floor_y := fy + 3
	for corner: Vector2i in [Vector2i(x0, z0), Vector2i(x1, z0), Vector2i(x0, z1), Vector2i(x1, z1), Vector2i(hc.x, z0), Vector2i(hc.x, z1)]:
		bp.fill(Vector3i(corner.x, fy - 2, corner.y), Vector3i(corner.x, floor_y + 4, corner.y), S)
	bp.hollow(Vector3i(x0, floor_y, z0), Vector3i(x1, floor_y + 4, z1), S)
	bp.fill(Vector3i(x0 + 1, floor_y, z0 + 1), Vector3i(x1 - 1, floor_y, z1 - 1), S)
	bp.gable_roof(Vector3i(x0 - 1, floor_y + 5, z0 - 1), Vector3i(x1 + 1, floor_y + 5, z1 + 1), S)
	bp.fill(Vector3i(hc.x, floor_y + 1, z1), Vector3i(hc.x, floor_y + 2, z1), Blueprint.CARVE)
	# Porch and stairs down to the clearing.
	bp.fill(Vector3i(x0, floor_y, z1 + 1), Vector3i(x1, floor_y, z1 + 1), S)
	for i in 3:
		bp.fill(Vector3i(hc.x - 1, fy + 1 + i, z1 + 4 - i), Vector3i(hc.x + 1, fy + 1 + i, z1 + 4 - i), S)
	# Standing stones.
	var stones: Array = []
	for i in 9:
		var a := TAU * float(i) / 9.0
		var p := lc + Vector3i(roundi(cos(a) * 19.0), 1, roundi(sin(a) * 19.0))
		if Vector2(cos(a), sin(a)).dot(Vector2(0, 1)) > 0.93:
			continue
		var h := rng.randi_range(2, 5)
		bp.fill(p, p + Vector3i(0, h, 0), S)
		stones.append([Vector3(p - lc) - Vector3(0, 1, 0), h + 1, a, i % 3 == 0])
	# Dead trees around the edge.
	for i in 7:
		var a := rng.randf() * TAU
		var r := rng.randf_range(22.0, 26.0)
		var p := lc + Vector3i(roundi(cos(a) * r), 1, roundi(sin(a) * r))
		bp.fill(p, p + Vector3i(0, rng.randi_range(5, 9), 0), Blocks.DEAD_TRUNK)
	# Cauldron (collision) in front of the hut.
	var cauldron := hc + Vector3i(0, 1, 6)
	bp.set_local(cauldron.x, cauldron.y, cauldron.z, S)
	var center := _center(bp, lc)
	loc.props.append({"type": "arena", "material": "arena", "arena": "hagsfen", "center": center, "radius": 40.0, "seed": rng.randi(),
			"hut": Vector3(hc - lc), "hut_floor": float(floor_y - fy), "pools": pool_info, "stones": stones,
			"cauldron": Vector3(cauldron - lc) - Vector3(0, 1, 0)})
	# Spawns.
	loc.add_spawn("boss", _w(bp, Vector3(lc) + Vector3(0, 1, 0)), {"kind": "bog_hag"})
	for i in 2:
		var p: Vector3i = pools[i]
		loc.add_spawn("enemy", _w(bp, Vector3(p) + Vector3(0, 0.2, 0)), {"kind": "bog_lurker"})
	for i in 2:
		var p: Vector3i = pools[2 + i]
		loc.add_spawn("enemy", _w(bp, Vector3(p) + Vector3(2.5, 1, 2.5)), {"kind": "ghoul"})
	loc.add_spawn("chest", _w(bp, Vector3(hc) + Vector3(0, 4, -1)), {"tier": 2})
	loc.add_spawn("lore", _w(bp, Vector3(lc) + Vector3(2, 1, 19)), {"text": "bog_hag"})
	loc.center = _w(bp, Vector3(lc) + Vector3(0, 1, 0))
