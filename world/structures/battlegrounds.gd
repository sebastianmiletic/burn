class_name Battlegrounds
extends RefCounted
## Boss battlegrounds: the blueprints (invisible STRUCTURE collision, carved
## space, spawns, arena gates) and the arena props that ArenaDirector turns
## into modelled geometry (world/architecture/arenas/*). Nothing here writes a
## visible cube block: architecture is STRUCTURE + meshes; natural ground stays
## smooth terrain.
##
## Convention for arena props: "center" is the top of the arena floor above
## the blueprint cell `c` (cell corner + (0.5, 1, 0.5)), so in centre-relative
## coordinates a blueprint cell (dx, dy, dz) relative to `c` spans
## x in [dx - 0.5, dx + 0.5], y in [dy - 1, dy], z in [dz - 0.5, dz + 0.5].

const S := Blocks.STRUCTURE
const CARVE := Blueprint.CARVE


static func _bp(loc: Location, half: Vector3i, below: int, above: int) -> Blueprint:
	var c := Vector3i(loc.center.round())
	var bp := Blueprint.new(Vector3i(c.x - half.x, loc.ground_y - below, c.z - half.z),
			Vector3i(half.x * 2 + 1, below + above, half.z * 2 + 1))
	loc.blueprints.append(bp)
	return bp


static func _w(bp: Blueprint, local: Vector3) -> Vector3:
	return Vector3(bp.origin) + local + Vector3(0.5, 0.0, 0.5)


## Arena centre (floor top above cell c) in world space.
static func _center(bp: Blueprint, c: Vector3i) -> Vector3:
	return Vector3(bp.origin + c) + Vector3(0.5, 1.0, 0.5)


## Fill relative to c (inclusive corners).
static func _box(bp: Blueprint, c: Vector3i, a: Vector3i, b: Vector3i, block := S) -> void:
	bp.fill(c + a, c + b, block)


static func _disc(bp: Blueprint, c: Vector3i, at: Vector3i, radius: float, y0: int, y1: int, block := S) -> void:
	var r := int(ceil(radius))
	for y in range(y0, y1 + 1):
		for z in range(-r, r + 1):
			for x in range(-r, r + 1):
				if x * x + z * z <= radius * radius:
					bp.set_local(c.x + at.x + x, c.y + y, c.z + at.z + z, block)


# --- The Dragon's Keep ------------------------------------------------------------------

## A ruined castle on the Cinder Wastes: square curtain walls with corner
## towers, a gatehouse with a portcullis (the arena gate) facing north, the
## shell of a great keep at the south end, scorched flagstones and the bones of
## an older dragon in the courtyard.
static func castle(loc: Location, rng: RandomNumberGenerator) -> void:
	loc.radius = 52.0
	loc.pad_radius = 47.0
	loc.pad_falloff = 14.0
	var bp := _bp(loc, Vector3i(52, 0, 52), 4, 40)
	var c := Vector3i(52, 4, 52)  # local centre, ground cell
	var half := 40
	var wall_h := 14
	# Courtyard: clear the air, one flat floor of collision under the flagstones.
	_box(bp, c, Vector3i(-half + 2, 1, -half + 2), Vector3i(half - 2, 30, half - 2), CARVE)
	_box(bp, c, Vector3i(-half - 1, 0, -half - 1), Vector3i(half + 1, 0, half + 1))
	# Breaches: stretches of curtain wall broken down to `top` (never to the ground).
	var breaches: Array = []
	for side in 4:
		if side == 0:
			continue  # the gatehouse wall stays whole
		if rng.randf() < 0.75:
			var from := rng.randi_range(-24, 10)
			breaches.append([side, from, from + rng.randi_range(7, 12), rng.randi_range(6, 9)])
	# Curtain walls: 3 m thick, wall-walk at +wall_h, merlons on the outer edge.
	for side in 4:
		for t in range(-half, half + 1):
			var top := wall_h
			for br: Array in breaches:
				if int(br[0]) == side and t >= int(br[1]) and t <= int(br[2]):
					top = int(br[3])
			for k in range(-1, 2):
				var cell := _side_cell(side, t, half + k)
				_box(bp, c, Vector3i(cell.x, 1, cell.y), Vector3i(cell.x, top, cell.y))
			if top == wall_h and t % 2 == 0 and absi(t) < half - 4:
				var m := _side_cell(side, t, half + 1)
				bp.set_local(c.x + m.x, c.y + wall_h + 1, c.z + m.y, S)
	# Inner buttresses every 10 m (KeepArena draws them on these cells).
	for side in 4:
		for t in range(-30, 31, 10):
			if side == 0 and absi(t) < 12:
				continue
			var near_breach := false
			for br: Array in breaches:
				if int(br[0]) == side and t >= int(br[1]) - 2 and t <= int(br[2]) + 2:
					near_breach = true
			if not near_breach:
				var cell := _side_cell(side, t, half - 2)
				_box(bp, c, Vector3i(cell.x, 1, cell.y), Vector3i(cell.x, 10, cell.y))
	# Corner towers (solid collision; two have lost their tops).
	var ruined := [rng.randi() % 4, (rng.randi() % 3 + 1)]
	ruined[1] = (int(ruined[0]) + int(ruined[1])) % 4
	var towers: Array = []
	var corners := [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]
	for i in 4:
		var corner: Vector2i = corners[i]
		var at := Vector3i(corner.x * half, 0, corner.y * half)
		var broken := i in ruined
		var top := wall_h + 7 if not broken else wall_h + rng.randi_range(4, 6)
		_disc(bp, c, at, 6.2, 1, 2)
		_disc(bp, c, at, 5.5, 3, top)
		towers.append([Vector3(at.x, 0, at.z), 5.5, float(top), broken])
	# Gatehouse on the north wall: flanking towers, a tall block that hides the
	# raised portcullis, and the passage (the arena gate).
	var gz := -half
	for gx: int in [-8, 8]:
		_disc(bp, c, Vector3i(gx, 0, gz), 3.6, 1, wall_h + 5)
	_box(bp, c, Vector3i(-6, 1, gz - 2), Vector3i(6, wall_h + 6, gz + 2))
	_box(bp, c, Vector3i(-4, 1, gz - 3), Vector3i(4, 9, gz + 3), CARVE)
	# The keep at the south end: a solid shell with an open ground-floor hall.
	var k0 := Vector3i(-12, 1, 16)
	var k1 := Vector3i(12, 26, 36)
	_box(bp, c, k0, k1)
	_box(bp, c, Vector3i(-10, 1, 18), Vector3i(10, 8, 34), CARVE)
	_box(bp, c, Vector3i(-2, 1, 16), Vector3i(2, 6, 17), CARVE)
	var collapse := rng.randi() % 2  # 0: east corner fallen, 1: west
	var cx := 12 if collapse == 0 else -12
	for y in range(14, 27):
		var r := float(y - 14) * 0.6 + 2.0
		for z in range(16, 37):
			for x in range(-12, 13):
				if Vector2(x - cx, (z - 16) * 0.8).length() < r:
					bp.set_local(c.x + x, c.y + y, c.z + z, CARVE)
	# Fire basins.
	var basins: Array = []
	for corner: Vector2i in [Vector2i(-24, -24), Vector2i(24, -24), Vector2i(-24, 8), Vector2i(24, 8)]:
		_disc(bp, c, Vector3i(corner.x, 0, corner.y), 1.6, 1, 1)
		basins.append(Vector3(corner.x, 0, corner.y))
	# The bones of an older dragon, half buried in ash (skull collision only).
	var bone_side := -1.0 if rng.randf() < 0.5 else 1.0
	var skull := Vector3(bone_side * 18.0, 0, -8.0 + rng.randf_range(-3, 3))
	_disc(bp, c, Vector3i(int(skull.x), 0, int(skull.z)), 1.6, 1, 2)
	var center := _center(bp, c)
	loc.props.append({"type": "arena", "material": "arena", "arena": "dragons_keep", "center": center, "radius": 60.0,
			"seed": rng.randi(), "half": half, "wall_h": wall_h, "breaches": breaches, "towers": towers,
			"keep": [Vector3(k0), Vector3(k1)], "collapse": collapse, "basins": basins,
			"skull": skull, "bone_side": bone_side, "gate": 0})
	loc.add_spawn("boss", _w(bp, Vector3(c.x, c.y + 1, c.z - 6)), {"kind": "dragon"})
	for i in 6:
		var a := TAU * i / 6.0
		loc.add_spawn("enemy", _w(bp, Vector3(c.x + cos(a) * 30.0, c.y + 1, c.z + sin(a) * 30.0)), {"kind": "skeleton" if i % 2 else "archer"})
	loc.add_spawn("chest", _w(bp, Vector3(c.x, c.y + 1, c.z + 31)), {"tier": 3})
	loc.add_spawn("arena_gate", _w(bp, Vector3(c.x, c.y + 1, c.z + gz)), {"along": Vector3i(0, 0, 1), "across": Vector3i(1, 0, 0), "width": 4, "height": 9})


## Cell (x, z) of the curtain wall on `side` (0 north, 1 east, 2 south, 3 west)
## at position t along it and distance d from the centre.
static func _side_cell(side: int, t: int, d: int) -> Vector2i:
	match side:
		0:
			return Vector2i(t, -d)
		1:
			return Vector2i(d, t)
		2:
			return Vector2i(-t, d)
	return Vector2i(-d, -t)


# --- The Silent Crypt (Warden) ------------------------------------------------------------

## A gothic mausoleum in the marsh; a broad stair descends to a vaulted
## catacomb hall (sarcophagi, bone niches, candelabra) and, past a sealed iron
## gate (the arena gate), the Warden's rib-vaulted tomb chamber.
## Relative to c (the mausoleum floor cell): hall z -42..-17 at y -19,
## gate at z -45, chamber z -77..-47.
static func crypt(surface: Location, depths: Location) -> void:
	surface.radius = 16.0
	surface.pad_radius = 12.0
	surface.pad_falloff = 7.0
	var bp := _bp(surface, Vector3i(16, 0, 84), 34, 16)
	var c := Vector3i(16, 34, 84)
	var fy := -19   # hall floor cell relative to c
	# Mausoleum: platform, walls, door, gabled roof.
	_box(bp, c, Vector3i(-7, 0, -7), Vector3i(7, 0, 8))
	_box(bp, c, Vector3i(-6, 1, -6), Vector3i(6, 8, 6))
	_box(bp, c, Vector3i(-5, 1, -5), Vector3i(5, 7, 5), CARVE)
	_box(bp, c, Vector3i(-1, 1, 6), Vector3i(1, 4, 6), CARVE)
	for i in 6:
		_box(bp, c, Vector3i(-6 + i, 9 + i, -6), Vector3i(6 - i, 9 + i, 6))
	# The stair down to the north.
	for i in 20:
		var z := 3 - i
		_box(bp, c, Vector3i(-2, -i + 1, z), Vector3i(2, -i + 5, z), CARVE)
		_box(bp, c, Vector3i(-2, -i, z), Vector3i(2, -i, z))
	# Catacomb hall with a vaulted ceiling and bone niches in the walls.
	var hz0 := -42
	var hz1 := -17
	for z in range(hz0, hz1 + 1):
		for x in range(-12, 13):
			var roof := 8 + int(3.0 * (1.0 - pow(x / 12.5, 2.0)))
			_box(bp, c, Vector3i(x, fy + 1, z), Vector3i(x, fy + roof, z), CARVE)
			bp.set_local(c.x + x, c.y + fy, c.z + z, S)
	var niches: Array = []
	for z in range(hz0 + 2, hz1 - 1, 2):
		for side: int in [-1, 1]:
			for tier: int in [2, 4]:
				bp.set_local(c.x + side * 13, c.y + fy + tier, c.z + z, CARVE)
				niches.append(Vector3(side * 13, fy + tier, z))
	var sarcophagi: Array = []
	for row: int in [-7, 7]:
		for z in range(hz0 + 4, hz1 - 2, 5):
			_box(bp, c, Vector3i(row - 1, fy + 1, z - 1), Vector3i(row + 1, fy + 1, z + 1))
			sarcophagi.append(Vector3(row, fy, z))
	# Passage with the sealed gate.
	_box(bp, c, Vector3i(-2, fy + 1, -46), Vector3i(2, fy + 6, hz0 - 1), CARVE)
	_box(bp, c, Vector3i(-2, fy, -46), Vector3i(2, fy, hz0 - 1))
	# The Warden's chamber: rib vault, clustered piers, the tomb dais.
	var bz0 := -77
	var bz1 := -47
	for z in range(bz0, bz1 + 1):
		for x in range(-11, 12):
			var roof := 11 + int(4.0 * (1.0 - pow(x / 11.5, 2.0)))
			_box(bp, c, Vector3i(x, fy + 1, z), Vector3i(x, fy + roof, z), CARVE)
			bp.set_local(c.x + x, c.y + fy, c.z + z, S)
	var piers: Array = []
	for z: int in [-54, -62, -70]:
		for x: int in [-6, 6]:
			_box(bp, c, Vector3i(x - 1, fy + 1, z - 1), Vector3i(x + 1, fy + 15, z + 1))
			piers.append(Vector3(x, fy, z))
	_box(bp, c, Vector3i(-4, fy + 1, -77), Vector3i(4, fy + 1, -73))
	_box(bp, c, Vector3i(-2, fy + 2, -76), Vector3i(2, fy + 2, -74))
	var center := _center(bp, c)
	depths.props.append({"type": "arena", "material": "arena", "arena": "crypt", "center": center, "radius": 85.0, "seed": 77,
			"fy": fy, "hall": [hz0, hz1], "chamber": [bz0, bz1], "niches": niches, "sarcophagi": sarcophagi, "piers": piers, "gate": 0})
	surface.add_spawn("enemy", _w(bp, Vector3(c.x + 5, c.y + 1, c.z + 11)), {"kind": "ghoul"})
	for i in 6:
		depths.add_spawn("enemy", _w(bp, Vector3(c.x + (i % 2) * 8 - 4, c.y + fy + 1, c.z + hz0 + 4 + i * 3)), {"kind": "skeleton" if i % 3 else "archer"})
	depths.add_spawn("boss", _w(bp, Vector3(c.x, c.y + fy + 1, c.z - 64)), {"kind": "warden"})
	depths.add_spawn("chest", _w(bp, Vector3(c.x + 3, c.y + fy + 1, c.z - 71)), {"tier": 2})
	depths.add_spawn("arena_gate", _w(bp, Vector3(c.x, c.y + fy + 1, c.z - 45)), {"along": Vector3i(0, 0, 1), "across": Vector3i(1, 0, 0), "width": 2, "height": 6})
	depths.center = _w(bp, Vector3(c.x, c.y + fy + 1, c.z - 47))
	depths.radius = 34.0
	depths.ground_y = int(depths.center.y)


# --- Hall of the Mountain King ---------------------------------------------------------

## A colossal dwarven hall carved into the mountain: square carved pillars, a
## vaulted roof with stone ribs, a rune-carved floor, a throne dais with two
## king statues, and a stepped tunnel out to the mountainside closed by a
## carved stone door (the arena gate).
static func mountain_hall(loc: Location, exit_dir: Vector2i, exit_y: int, rng: RandomNumberGenerator) -> void:
	var floor_y := int(loc.center.y) - 1
	var c := Vector3i(int(loc.center.x), floor_y, int(loc.center.z))
	var reach := 100
	var bp := Blueprint.new(Vector3i(c.x - reach, mini(floor_y, exit_y) - 4, c.z - reach),
			Vector3i(reach * 2 + 1, absi(exit_y - floor_y) + 28, reach * 2 + 1))
	loc.blueprints.append(bp)
	var lc := c - bp.origin  # local hall centre, floor cell
	var hx := 17
	var hz := 28
	var h := 18
	var along := Vector3i(exit_dir.x, 0, exit_dir.y)
	var across := Vector3i(exit_dir.y, 0, -exit_dir.x)
	var cell := func(a: int, b: int, y: int) -> Vector3i:
		return lc + along * a + across * b + Vector3i(0, y, 0)
	for a in range(-hz, hz + 1):
		for b in range(-hx, hx + 1):
			var p: Vector3i = cell.call(a, b, 0)
			bp.set_local(p.x, p.y, p.z, S)
			var roof := h - int(pow(absf(b) / hx, 2.0) * 5.0)
			for y in range(1, roof):
				bp.set_local(p.x, p.y + y, p.z, CARVE)
	# Square carved pillars (3 x 3) up into the vault.
	var pillars: Array = []
	for a in range(-hz + 4, hz - 3, 8):
		for b: int in [-9, 9]:
			for da in range(-1, 2):
				for db in range(-1, 2):
					var p: Vector3i = cell.call(a + da, b + db, 0)
					bp.fill(Vector3i(p.x, p.y + 1, p.z), Vector3i(p.x, p.y + h, p.z), S)
			pillars.append(Vector2(a, b))
	# Throne dais at the far end.
	var ta := -(hz - 3)
	for step in 3:
		for b in range(-5 + step, 6 - step):
			for dd in range(step, 4):
				var p: Vector3i = cell.call(ta - dd, b, 1 + step)
				bp.set_local(p.x, p.y, p.z, S)
	for y in range(4, 10):
		for b in range(-2, 3):
			var p: Vector3i = cell.call(ta - 3, b, y)
			bp.set_local(p.x, p.y, p.z, S)
	# King statues flanking the dais.
	for b: int in [-8, 8]:
		for da in range(-1, 2):
			for db in range(-1, 2):
				var p: Vector3i = cell.call(ta - 1 + da, b + db, 1)
				bp.fill(p, p + Vector3i(0, 4, 0), S)
	# Tunnel out to the mountainside, a staircase of 1 m steps.
	var start: Vector3i = cell.call(hz, 0, 0)
	var tunnel_len := 75
	var steps := PackedInt32Array()
	for i in tunnel_len:
		var fy := int(lerpf(0.0, float(exit_y - floor_y), float(i) / tunnel_len))
		steps.append(fy)
		for b in range(-3, 4):
			var p := start + along * i + across * b
			bp.set_local(p.x, p.y + fy, p.z, S)
			for y in range(1, 7):
				bp.set_local(p.x, p.y + fy + y, p.z, CARVE)
	# Braziers along the nave.
	for a: int in [-16, 0, 16]:
		for b: int in [-5, 5]:
			var p: Vector3i = cell.call(a, b, 1)
			bp.set_local(p.x, p.y, p.z, S)
	# Great doorway one step into the tunnel: 9 wide, 8 tall, framed in stone.
	var door := start + along
	for b in range(-6, 7):
		for y in range(1, 12):
			var p := door + across * b
			if absi(b) >= 5 or y >= 9:
				bp.set_local(p.x, p.y + y, p.z, S)
			else:
				bp.set_local(p.x, p.y + y, p.z, CARVE)
	var center := _center(bp, lc)
	loc.props.append({"type": "arena", "material": "arena", "arena": "mountain_hall", "center": center, "radius": 105.0, "seed": rng.randi(),
			"along": Vector3(along), "across": Vector3(across), "hx": hx, "hz": hz, "h": h, "pillars": pillars, "throne_a": ta,
			"steps": steps, "gate": 0})
	loc.add_spawn("boss", _w(bp, Vector3(lc) + Vector3(along) * -6.0 + Vector3(0, 1, 0)), {"kind": "mountain_king"})
	for i in 4:
		loc.add_spawn("enemy", _w(bp, Vector3(lc + along * (i * 10 - 10) + across * (5 if i % 2 else -5)) + Vector3(0, 1, 0)), {"kind": "troll"})
	for i in 3:
		var ti := 15 + i * 18
		loc.add_spawn("enemy", _w(bp, Vector3(start + along * ti) + Vector3(0, 1 + steps[ti], 0)), {"kind": "skeleton"})
	loc.add_spawn("chest", _w(bp, Vector3(lc + along * (ta + 3)) + Vector3(across) * 3.0 + Vector3(0, 1, 0)), {"tier": 3})
	loc.add_spawn("arena_gate", _w(bp, Vector3(door) + Vector3(0, 1, 0)), {"along": along, "across": across, "width": 4, "height": 8})
	loc.center = _w(bp, Vector3(lc) + Vector3(0, 1, 0))


# --- Ryft boss lairs --------------------------------------------------------------------

## Crystal arenas on the Ryft's floating isles: index 1 the Broken Observatory
## (Prism Sentinel), index 2 the Crown of the Ryft (Void Sovereign). A circular
## dais of ryft stone ringed by crystal pillars (collision) around the boss pad
## at loc.center + (0, 1.5, -6). Replaces the isle's placeholder box props.
static func ryft_lair(loc: Location, index: int) -> void:
	var keep: Array = []
	for p: Dictionary in loc.props:
		if String(p.get("type", "")) != "box":
			keep.append(p)
	loc.props = keep
	loc.pad_radius = 16.0
	loc.pad_falloff = 10.0
	var g := int(loc.center.y)
	var c0 := Vector3i(roundi(loc.center.x), g, roundi(loc.center.z) - 6)
	var bp := Blueprint.new(c0 - Vector3i(20, 6, 20), Vector3i(41, 30, 41))
	loc.blueprints.append(bp)
	var c := Vector3i(20, 6, 20)
	var r := 15.0
	for z in range(-20, 21):
		for x in range(-20, 21):
			var d := Vector2(x, z).length()
			if d <= r:
				bp.set_local(c.x + x, c.y, c.z + z, S)
				for y in range(1, 22):
					bp.set_local(c.x + x, c.y + y, c.z + z, CARVE)
	var pillars: Array = []
	var n := 8 if index == 1 else 10
	for i in n:
		var a := TAU * i / n + 0.2
		var at := Vector3i(roundi(cos(a) * 13.0), 0, roundi(sin(a) * 13.0))
		_disc(bp, c, at, 1.1, 1, 6)
		pillars.append(Vector3(at))
	loc.props.append({"type": "arena", "material": "arena", "arena": "ryft_lair", "center": _center(bp, c), "radius": 30.0,
			"seed": index * 911, "variant": index, "pillars": pillars, "r": r})


# --- Gates of Hades ---------------------------------------------------------------------

## A vast cavern beneath the Cinder Crater. At its north end stands the Gate:
## two carved pylons and a pointed arch framing the portal to the underworld,
## guarded by two colossal hooded statues, approached along an avenue of
## soul-fire braziers.
static func gates_of_hades(loc: Location, rng: RandomNumberGenerator) -> void:
	var c := Vector3i(loc.center.round())
	var bp := Blueprint.new(c - Vector3i(46, 24, 46), Vector3i(93, 48, 93))
	loc.blueprints.append(bp)
	var lc := Vector3i(46, 24, 46)
	bp.ellipsoid(lc, Vector3(44, 20, 44), CARVE)
	var floor_y := lc.y - 12
	for dz in range(-44, 45):
		for dx in range(-44, 45):
			if dx * dx + dz * dz > 44 * 44:
				continue
			bp.fill(Vector3i(lc.x + dx, floor_y - 6, lc.z + dz), Vector3i(lc.x + dx, floor_y, lc.z + dz), Blocks.BASALT)
			if rng.randf() < 0.08:
				bp.set_local(lc.x + dx, floor_y, lc.z + dz, Blocks.OBSIDIAN)
	var gz := lc.z - 30
	var fc := Vector3i(lc.x, floor_y, lc.z)   # floor cell under the cavern centre
	var gzr := gz - lc.z
	# Paved forecourt and avenue: flat collision under the flagstones.
	_box(bp, fc, Vector3i(-13, 0, gzr - 4), Vector3i(13, 0, gzr + 9))
	_box(bp, fc, Vector3i(-8, 0, gzr + 9), Vector3i(8, 0, 24))
	# Lava pools away from the avenue.
	var pools: Array = []
	for i in 7:
		var a := rng.randf() * TAU
		var r := rng.randf_range(16.0, 34.0)
		var pc := Vector3i(lc.x + roundi(cos(a) * r), floor_y, lc.z + roundi(sin(a) * r))
		if pc.z < lc.z - 18 or absi(pc.x - lc.x) < 14:
			continue
		var pr := rng.randf_range(2.5, 5.0)
		bp.cylinder(pc - Vector3i(0, 1, 0), pr, 2, Blocks.LAVA)
		pools.append([Vector3(pc - fc), pr])
	# The Gate: pylons and an arch around the 14 x 19 m portal.
	for side: int in [-1, 1]:
		_box(bp, fc, Vector3i(side * 8, 1, gzr - 2), Vector3i(side * 12, 27, gzr + 2))
	_box(bp, fc, Vector3i(-12, 21, gzr - 2), Vector3i(12, 27, gzr + 2))
	# Guardian statues (bases) and the brazier avenue.
	for side: int in [-1, 1]:
		_disc(bp, fc, Vector3i(side * 18, 0, gzr + 5), 2.6, 1, 9)
	var braziers: Array = []
	for z in range(gzr + 11, 22, 8):
		for side: int in [-1, 1]:
			_disc(bp, fc, Vector3i(side * 7, 0, z), 1.2, 1, 1)
			braziers.append(Vector3(side * 7, 0, z))
	var center := _center(bp, fc)
	loc.props.append({"type": "arena", "material": "arena", "arena": "gates_of_hades", "center": center, "radius": 46.0,
			"seed": rng.randi(), "gate_z": float(gzr), "braziers": braziers, "pools": pools})
	loc.add_spawn("portal", _w(bp, Vector3(lc.x, floor_y + 1, gz)), {"to": 1, "size": Vector2(14, 19)})
	loc.add_spawn("shrine", _w(bp, Vector3(lc.x, floor_y + 1, lc.z + 14)))
	for i in 5:
		var a := rng.randf() * TAU
		loc.add_spawn("enemy", _w(bp, Vector3(lc.x + cos(a) * 20.0, floor_y + 1, lc.z + sin(a) * 20.0)), {"kind": "imp"})
	loc.center = _w(bp, Vector3(lc.x, floor_y + 1, lc.z))


# --- Tartarus (Cerberus) -------------------------------------------------------------------

## A fortress pit of obsidian: a round arena inside a spiked wall with four
## chained gates (arena gates), bridges over a lava moat, and four bastions.
static func tartarus(loc: Location, rng: RandomNumberGenerator) -> void:
	loc.radius = 42.0
	loc.pad_radius = 41.0
	loc.pad_falloff = 12.0
	var bp := _bp(loc, Vector3i(46, 0, 46), 4, 28)
	var c := Vector3i(46, 4, 46)
	for z in range(-40, 41):
		for x in range(-40, 41):
			var r := Vector2(x, z).length()
			if r > 40.5:
				continue
			var in_gap := mini(absi(x), absi(z)) <= 2
			if r <= 33.0:
				bp.set_local(c.x + x, c.y, c.z + z, S)
				for y in range(1, 26):
					bp.set_local(c.x + x, c.y + y, c.z + z, CARVE)
			if r > 29.0 and r <= 32.5:
				# Wall; over the gaps only a lintel above the 7 m gate.
				for y in range(8 if in_gap else 1, 13):
					bp.set_local(c.x + x, c.y + y, c.z + z, S)
			if r > 27.6 and r <= 29.0 and not in_gap:
				bp.set_local(c.x + x, c.y + 1, c.z + z, S)  # spiked ledge
			if r > 33.0 and r <= 37.5:
				if in_gap:
					bp.set_local(c.x + x, c.y, c.z + z, S)  # bridge deck
				else:
					bp.set_local(c.x + x, c.y, c.z + z, Blocks.LAVA)
					bp.set_local(c.x + x, c.y - 1, c.z + z, Blocks.BASALT)
					bp.set_local(c.x + x, c.y - 2, c.z + z, Blocks.BASALT)
			if r > 37.5 and r <= 40.5:
				bp.set_local(c.x + x, c.y, c.z + z, S if in_gap else Blocks.BASALT)
	# Bastions on the diagonals.
	var bastions: Array = []
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		var at := Vector3i(roundi(cos(a) * 31.0), 0, roundi(sin(a) * 31.0))
		_disc(bp, c, at, 4.6, 1, 18)
		bastions.append(Vector3(at))
	var center := _center(bp, c)
	loc.props.append({"type": "arena", "material": "arena", "arena": "tartarus", "center": center, "radius": 46.0, "seed": rng.randi(),
			"bastions": bastions, "wall_r": [29.0, 32.5], "wall_h": 12.0, "moat": [33.0, 37.5], "gates": [0, 1, 2, 3]})
	loc.add_spawn("boss", _w(bp, Vector3(c.x, c.y + 1, c.z)), {"kind": "cerberus"})
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		loc.add_spawn("enemy", _w(bp, Vector3(c.x + cos(a) * 42.0, c.y + 1, c.z + sin(a) * 42.0)), {"kind": "imp"})
	loc.add_spawn("chest", _w(bp, Vector3(c.x + 20, c.y + 1, c.z + 6)), {"tier": 3})
	loc.add_spawn("shrine", _w(bp, Vector3(c.x, c.y + 1, c.z + 44)))
	# Four chained gates in the wall gaps.
	for d: Vector3i in [Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, 0, -1)]:
		loc.add_spawn("arena_gate", _w(bp, Vector3(c + d * 31 + Vector3i(0, 1, 0))), {"along": d, "across": Vector3i(absi(d.z), 0, absi(d.x)), "width": 2, "height": 7})


# --- Throne of Hades ----------------------------------------------------------------------

## The throne hall of the underworld: a walled nave of colossal columns between
## two lava channels, a stepped dais and the throne at the south end, the
## gate at the north end over the river of souls.
static func throne(loc: Location, rng: RandomNumberGenerator) -> void:
	loc.radius = 40.0
	loc.pad_radius = 44.0
	loc.pad_falloff = 12.0
	var bp := _bp(loc, Vector3i(46, 0, 54), 4, 36)
	var c := Vector3i(46, 4, 54)
	# Floor and clear air over the whole precinct.
	_box(bp, c, Vector3i(-27, 1, -50), Vector3i(27, 34, 34), CARVE)
	_box(bp, c, Vector3i(-28, 0, -50), Vector3i(28, 0, 35))
	# Lava channels along the nave.
	for z in range(-32, 33):
		for x: int in [-22, -21, 21, 22]:
			bp.set_local(c.x + x, c.y, c.z + z, Blocks.LAVA)
			bp.set_local(c.x + x, c.y - 1, c.z + z, Blocks.BASALT)
	# Walls: sides, back, and the gate wall with its opening.
	_box(bp, c, Vector3i(25, 1, -35), Vector3i(27, 24, 35))
	_box(bp, c, Vector3i(-27, 1, -35), Vector3i(-25, 24, 35))
	_box(bp, c, Vector3i(-27, 1, 33), Vector3i(27, 28, 35))
	_box(bp, c, Vector3i(-27, 1, -35), Vector3i(27, 20, -33))
	_box(bp, c, Vector3i(-6, 1, -36), Vector3i(6, 8, -32), CARVE)
	# Forecourt walls on either side of the river of souls.
	_box(bp, c, Vector3i(25, 1, -50), Vector3i(27, 8, -36))
	_box(bp, c, Vector3i(-27, 1, -50), Vector3i(-25, 8, -36))
	# Colossal columns.
	var columns: Array = []
	for z in range(-26, 27, 9):
		for x: int in [-14, 14]:
			_disc(bp, c, Vector3i(x, 0, z), 2.6, 1, 2)
			_disc(bp, c, Vector3i(x, 0, z), 1.9, 3, 22)
			columns.append(Vector3(x, 0, z))
	# Dais and throne.
	for step in 4:
		_box(bp, c, Vector3i(-9 + step * 2, 1 + step, 22 + step), Vector3i(9 - step * 2, 1 + step, 32))
	_box(bp, c, Vector3i(-2, 5, 29), Vector3i(2, 5, 31))
	_box(bp, c, Vector3i(-3, 5, 31), Vector3i(3, 17, 32))
	# The river of souls before the gate, with a bridge.
	for z in range(-42, -37):
		for x in range(-27, 28):
			if absi(x) <= 5:
				continue
			bp.set_local(c.x + x, c.y, c.z + z, CARVE)
			bp.set_local(c.x + x, c.y - 1, c.z + z, S)
	var center := _center(bp, c)
	loc.props.append({"type": "arena", "material": "arena", "arena": "throne_of_hades", "center": center, "radius": 54.0, "seed": rng.randi(),
			"columns": columns, "gate": 0})
	loc.add_spawn("boss", _w(bp, Vector3(c.x, c.y + 1, c.z + 12)), {"kind": "hades"})
	loc.add_spawn("shrine", _w(bp, Vector3(c.x, c.y + 1, c.z - 46)))
	for i in 4:
		loc.add_spawn("enemy", _w(bp, Vector3(c.x + (i - 1.5) * 8.0, c.y + 1, c.z - 20)), {"kind": "shade"})
	loc.add_spawn("arena_gate", _w(bp, Vector3(c.x, c.y + 1, c.z - 34)), {"along": Vector3i(0, 0, 1), "across": Vector3i(1, 0, 0), "width": 6, "height": 8})
