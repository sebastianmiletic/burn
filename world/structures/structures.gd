class_name Structures
extends RefCounted
## Blueprint builders for every kind of location. Coordinates inside a
## builder are local to its blueprint; `w()` converts back to world space for
## spawn points.



static func _bp(loc: Location, half: Vector3i, below: int, above: int) -> Blueprint:
	var c := Vector3i(loc.center.round())
	var bp := Blueprint.new(Vector3i(c.x - half.x, loc.ground_y - below, c.z - half.z),
			Vector3i(half.x * 2 + 1, below + above, half.z * 2 + 1))
	loc.blueprints.append(bp)
	return bp


static func _w(bp: Blueprint, local: Vector3) -> Vector3:
	return Vector3(bp.origin) + local + Vector3(0.5, 0.0, 0.5)


# --- Village -------------------------------------------------------------------

static func village(loc: Location, rng: RandomNumberGenerator, is_start: bool) -> void:
	loc.radius = 36.0
	loc.pad_radius = 27.0
	loc.pad_falloff = 12.0
	var bp := _bp(loc, Vector3i(32, 0, 32), 6, 22)
	var cx := 32
	var cz := 32
	var fy := 6  # local y of the ground surface

	# Plaza and well.
	for dz in range(-8, 9):
		for dx in range(-8, 9):
			var d := Vector2(dx, dz).length()
			if d <= 8.2:
				bp.set_local(cx + dx, fy, cz + dz, Blocks.COBBLE if d > 6.8 or (dx + dz) % 3 == 0 else Blocks.GRAVEL)
	bp.cylinder(Vector3i(cx, fy + 1, cz), 2.3, 2, Blocks.MOSSY_COBBLE, true)
	bp.cylinder(Vector3i(cx, fy - 4, cz), 1.3, 5, Blocks.WATER)
	for corner: Vector2i in [Vector2i(-2, -2), Vector2i(2, -2), Vector2i(-2, 2), Vector2i(2, 2)]:
		bp.fill(Vector3i(cx + corner.x, fy + 1, cz + corner.y), Vector3i(cx + corner.x, fy + 4, cz + corner.y), Blocks.LOG)
	bp.fill(Vector3i(cx - 2, fy + 5, cz - 2), Vector3i(cx + 2, fy + 5, cz + 2), Blocks.THATCH)
	for a in 4:
		var ang := TAU * a / 4.0 + PI / 4.0
		var p := Vector2i(Vector2(cos(ang), sin(ang)) * 7.5)
		bp.fill(Vector3i(cx + p.x, fy + 1, cz + p.y), Vector3i(cx + p.x, fy + 3, cz + p.y), Blocks.LOG)
		bp.set_local(cx + p.x, fy + 4, cz + p.y, Blocks.LANTERN)

	var count := 6 + rng.randi_range(0, 2)
	for i in count:
		var ang := TAU * float(i) / count + rng.randf_range(-0.15, 0.15)
		var dist := rng.randf_range(16.0, 22.0)
		var hp := Vector2i((Vector2(cos(ang), sin(ang)) * dist).round()) + Vector2i(cx, cz)
		var to_plaza := Vector2(cx - hp.x, cz - hp.y)
		var door := Vector2i(signi(int(to_plaza.x)), 0) if absf(to_plaza.x) > absf(to_plaza.y) else Vector2i(0, signi(int(to_plaza.y)))
		if i == 0:
			_house(bp, Vector3i(hp.x, fy, hp.y), 11, 9, 5, door, true)
			var door_w := _w(bp, Vector3(hp.x + door.x * 6, fy + 1, hp.y + door.y * 6))
			loc.add_spawn("npc", door_w, {"role": "elder" if is_start else "chief"})
			loc.add_spawn("chest", _w(bp, Vector3(hp.x - door.x * 3, fy + 1, hp.y - door.y * 3)), {"tier": 1})
		elif i == 1:
			_forge(bp, Vector3i(hp.x, fy, hp.y))
			loc.add_spawn("npc", _w(bp, Vector3(hp.x + door.x * 4, fy + 1, hp.y + door.y * 4)), {"role": "blacksmith"})
		else:
			_house(bp, Vector3i(hp.x, fy, hp.y), 7 + 2 * rng.randi_range(0, 1), 6 + rng.randi_range(0, 2), 4, door, false)
	for i in 4:
		var ang := rng.randf() * TAU
		loc.add_spawn("npc", _w(bp, Vector3(cx + cos(ang) * 10.0, fy + 1, cz + sin(ang) * 10.0)), {"role": "villager"})
	loc.add_spawn("npc", _w(bp, Vector3(cx + 4, fy + 1, cz - 3)), {"role": "merchant"})
	loc.add_spawn("guard_post", _w(bp, Vector3(cx, fy + 1, cz)), {})


static func _house(bp: Blueprint, c: Vector3i, w: int, d: int, wall_h: int, door: Vector2i, hall: bool) -> void:
	var x0 := c.x - w / 2
	var x1 := x0 + w - 1
	var z0 := c.z - d / 2
	var z1 := z0 + d - 1
	var y0 := c.y
	bp.fill(Vector3i(x0 - 1, y0, z0 - 1), Vector3i(x1 + 1, y0, z1 + 1), Blocks.COBBLE)
	bp.fill(Vector3i(x0, y0 + 1, z0), Vector3i(x1, y0 + wall_h, z1), Blocks.PLANKS)
	bp.fill(Vector3i(x0 + 1, y0 + 1, z0 + 1), Vector3i(x1 - 1, y0 + wall_h, z1 - 1), Blueprint.CARVE)
	bp.fill(Vector3i(x0 + 1, y0, z0 + 1), Vector3i(x1 - 1, y0, z1 - 1), Blocks.PLANKS)
	for corner: Vector2i in [Vector2i(x0, z0), Vector2i(x1, z0), Vector2i(x0, z1), Vector2i(x1, z1)]:
		bp.fill(Vector3i(corner.x, y0 + 1, corner.y), Vector3i(corner.x, y0 + wall_h, corner.y), Blocks.LOG)
	# Windows on the long walls.
	for x in range(x0 + 2, x1 - 1, 3):
		bp.set_local(x, y0 + 2, z0, Blueprint.CARVE)
		bp.set_local(x, y0 + 2, z1, Blueprint.CARVE)
	for z in range(z0 + 2, z1 - 1, 3):
		bp.set_local(x0, y0 + 2, z, Blueprint.CARVE)
		bp.set_local(x1, y0 + 2, z, Blueprint.CARVE)
	# Door facing the plaza.
	var dw := 1 if hall else 0
	if door.x != 0:
		var dx := x1 if door.x > 0 else x0
		bp.fill(Vector3i(dx, y0 + 1, c.z - dw), Vector3i(dx, y0 + 3 if hall else y0 + 2, c.z + dw), Blueprint.CARVE)
	else:
		var dz := z1 if door.y > 0 else z0
		bp.fill(Vector3i(c.x - dw, y0 + 1, dz), Vector3i(c.x + dw, y0 + 3 if hall else y0 + 2, dz), Blueprint.CARVE)
	bp.gable_roof(Vector3i(x0 - 1, y0 + wall_h + 1, z0 - 1), Vector3i(x1 + 1, y0 + wall_h + 1, z1 + 1), Blocks.THATCH)
	bp.set_local(c.x, y0 + wall_h, c.z, Blocks.LANTERN)


static func _forge(bp: Blueprint, c: Vector3i) -> void:
	bp.fill(Vector3i(c.x - 4, c.y, c.z - 3), Vector3i(c.x + 4, c.y, c.z + 3), Blocks.COBBLE)
	for corner: Vector2i in [Vector2i(-4, -3), Vector2i(4, -3), Vector2i(-4, 3), Vector2i(4, 3)]:
		bp.fill(Vector3i(c.x + corner.x, c.y + 1, c.z + corner.y), Vector3i(c.x + corner.x, c.y + 4, c.z + corner.y), Blocks.LOG)
	bp.fill(Vector3i(c.x - 5, c.y + 5, c.z - 4), Vector3i(c.x + 5, c.y + 5, c.z + 4), Blocks.THATCH)
	bp.fill(Vector3i(c.x - 3, c.y + 1, c.z - 2), Vector3i(c.x - 1, c.y + 1, c.z), Blocks.COBBLE)
	bp.set_local(c.x - 2, c.y + 1, c.z - 1, Blocks.LAVA)
	bp.fill(Vector3i(c.x - 3, c.y + 2, c.z - 2), Vector3i(c.x - 1, c.y + 3, c.z - 2), Blocks.COBBLE)
	bp.set_local(c.x + 2, c.y + 1, c.z, Blocks.IRON_BARS)
	bp.set_local(c.x + 2, c.y + 1, c.z + 2, Blocks.CHEST)


# --- Shrine, tower, ruins -------------------------------------------------------

static func shrine(loc: Location) -> void:
	loc.radius = 7.0
	loc.pad_radius = 5.0
	loc.pad_falloff = 5.0
	var bp := _bp(loc, Vector3i(4, 0, 4), 2, 8)
	var y := 2
	bp.fill(Vector3i(1, y, 1), Vector3i(7, y, 7), Blocks.COBBLE)
	bp.fill(Vector3i(2, y + 1, 2), Vector3i(6, y + 1, 6), Blocks.MOSSY_COBBLE)
	for corner: Vector2i in [Vector2i(1, 1), Vector2i(7, 1), Vector2i(1, 7), Vector2i(7, 7)]:
		bp.fill(Vector3i(corner.x, y + 1, corner.y), Vector3i(corner.x, y + 3, corner.y), Blocks.RUNESTONE)
	bp.set_local(4, y + 2, 4, Blocks.RUNESTONE)
	loc.add_spawn("shrine", _w(bp, Vector3(4, y + 3, 4)))


static func tower(loc: Location, rng: RandomNumberGenerator) -> void:
	loc.radius = 9.0
	loc.pad_radius = 6.0
	loc.pad_falloff = 5.0
	var bp := _bp(loc, Vector3i(6, 0, 6), 3, 22)
	var c := Vector3i(6, 3, 6)
	bp.cylinder(c, 4.0, 1, Blocks.COBBLE)
	bp.cylinder(c + Vector3i(0, 1, 0), 3.6, 15, Blocks.COBBLE, true)
	for y in [6, 11]:
		bp.cylinder(c + Vector3i(0, y, 0), 2.7, 1, Blocks.PLANKS)
	bp.cylinder(c + Vector3i(0, 16, 0), 4.2, 1, Blocks.COBBLE)
	for i in 12:
		if i % 2 == 0:
			var a := TAU * i / 12.0
			bp.set_local(c.x + roundi(cos(a) * 4.0), c.y + 17, c.z + roundi(sin(a) * 4.0), Blocks.COBBLE)
	bp.fill(Vector3i(c.x + 3, c.y + 1, c.z), Vector3i(c.x + 4, c.y + 2, c.z), Blueprint.CARVE)
	bp.set_local(c.x, c.y + 17, c.z, Blocks.LANTERN)
	# Ruined: knock a few chunks out of the wall.
	for i in 3:
		var a := rng.randf() * TAU
		var y := rng.randi_range(5, 14)
		bp.sphere(c + Vector3i(roundi(cos(a) * 3.6), y, roundi(sin(a) * 3.6)), 1.6, Blueprint.CARVE)
	loc.add_spawn("enemy", _w(bp, Vector3(c.x, c.y + 17, c.z + 2)), {"kind": "archer"})
	loc.add_spawn("enemy", _w(bp, Vector3(c.x + 6, c.y + 1, c.z)), {"kind": "skeleton"})
	loc.add_spawn("chest", _w(bp, Vector3(c.x - 1, c.y + 12, c.z)), {"tier": 1})


static func ruin(loc: Location, rng: RandomNumberGenerator) -> void:
	loc.radius = 14.0
	loc.pad_radius = 10.0
	loc.pad_falloff = 6.0
	var bp := _bp(loc, Vector3i(12, 0, 12), 3, 12)
	var y := 3
	for i in 6:
		var a := rng.randf() * TAU
		var r := rng.randf_range(3.0, 10.0)
		var p := Vector3i(12 + roundi(cos(a) * r), y + 1, 12 + roundi(sin(a) * r))
		var h := rng.randi_range(2, 7)
		var horizontal := rng.randf() < 0.5
		var length := rng.randi_range(3, 7)
		for j in length:
			var col_h := maxi(1, h - rng.randi_range(0, 3))
			var q := p + (Vector3i(j, 0, 0) if horizontal else Vector3i(0, 0, j))
			bp.fill(q, q + Vector3i(0, col_h - 1, 0), Blocks.MOSSY_COBBLE if rng.randf() < 0.5 else Blocks.COBBLE)
	for i in 3:
		var a := rng.randf() * TAU
		var p := Vector3i(12 + roundi(cos(a) * 6), y + 1, 12 + roundi(sin(a) * 6))
		bp.cylinder(p, 1.2, rng.randi_range(3, 8), Blocks.COBBLE)
	loc.add_spawn("enemy", _w(bp, Vector3(12, y + 1, 9)), {"kind": "skeleton"})
	loc.add_spawn("enemy", _w(bp, Vector3(15, y + 1, 14)), {"kind": "ghoul"})
	if rng.randf() < 0.6:
		loc.add_spawn("chest", _w(bp, Vector3(12, y + 1, 12)), {"tier": 1})


# --- The Silent Crypt -------------------------------------------------------------

static func crypt(surface: Location, depths: Location) -> void:
	surface.radius = 16.0
	surface.pad_radius = 12.0
	surface.pad_falloff = 7.0
	var bp := _bp(surface, Vector3i(14, 0, 64), 24, 12)
	var cx := 14
	var cz := 64
	var y := 24  # local ground level
	# Mausoleum
	bp.fill(Vector3i(cx - 6, y, cz - 6), Vector3i(cx + 6, y, cz + 6), Blocks.COBBLE)
	bp.hollow(Vector3i(cx - 5, y, cz - 5), Vector3i(cx + 5, y + 6, cz + 5), Blocks.MOSSY_COBBLE)
	bp.fill(Vector3i(cx - 6, y + 7, cz - 6), Vector3i(cx + 6, y + 7, cz + 6), Blocks.COBBLE)
	bp.fill(Vector3i(cx - 4, y + 8, cz - 4), Vector3i(cx + 4, y + 8, cz + 4), Blocks.COBBLE)
	bp.fill(Vector3i(cx - 1, y + 1, cz + 5), Vector3i(cx + 1, y + 3, cz + 5), Blueprint.CARVE)
	for px: int in [-4, 4]:
		bp.fill(Vector3i(cx + px, y + 1, cz + 7), Vector3i(cx + px, y + 6, cz + 7), Blocks.COBBLE)
	bp.set_local(cx, y + 6, cz + 6, Blocks.LANTERN)
	# Stairs going down to the north.
	for i in 19:
		var sy := y - i
		var sz := cz + 3 - i
		bp.fill(Vector3i(cx - 1, sy, sz), Vector3i(cx + 1, sy + 4, sz), Blueprint.CARVE)
		bp.fill(Vector3i(cx - 1, sy - 1, sz), Vector3i(cx + 1, sy - 1, sz), Blocks.COBBLE)
	# Crypt hall.
	var fy := y - 19
	var hz0 := cz - 40
	var hz1 := cz - 15
	bp.fill(Vector3i(cx - 13, fy - 1, hz0 - 1), Vector3i(cx + 13, fy + 8, hz1 + 1), Blocks.MOSSY_COBBLE)
	bp.fill(Vector3i(cx - 12, fy, hz0), Vector3i(cx + 12, fy + 7, hz1), Blueprint.CARVE)
	bp.fill(Vector3i(cx - 12, fy - 1, hz0), Vector3i(cx + 12, fy - 1, hz1), Blocks.COBBLE)
	for row: int in [-7, 7]:
		for z in range(hz0 + 3, hz1 - 2, 5):
			bp.fill(Vector3i(cx + row - 1, fy, z), Vector3i(cx + row + 1, fy, z + 2), Blocks.BONE)
			bp.set_local(cx + row, fy + 1, z + 1, Blocks.BONE)
	for z in range(hz0 + 2, hz1, 6):
		for x: int in [-12, 12]:
			bp.set_local(cx + x, fy + 4, z, Blocks.LANTERN)
	bp.fill(Vector3i(cx - 1, fy, hz1), Vector3i(cx + 1, fy + 4, hz1 + 2), Blueprint.CARVE)
	# Boss chamber.
	var bz0 := hz0 - 24
	var bz1 := hz0 - 3
	bp.fill(Vector3i(cx - 12, fy - 1, bz0 - 1), Vector3i(cx + 12, fy + 11, bz1 + 1), Blocks.MOSSY_COBBLE)
	bp.fill(Vector3i(cx - 11, fy, bz0), Vector3i(cx + 11, fy + 10, bz1), Blueprint.CARVE)
	bp.fill(Vector3i(cx - 1, fy, bz1), Vector3i(cx + 1, fy + 4, hz0), Blueprint.CARVE)
	for corner: Vector2i in [Vector2i(-8, 4), Vector2i(8, 4), Vector2i(-8, 18), Vector2i(8, 18)]:
		bp.cylinder(Vector3i(cx + corner.x, fy, bz0 + corner.y), 1.4, 10, Blocks.BONE)
	for z in range(bz0 + 2, bz1, 7):
		for x: int in [-11, 11]:
			bp.set_local(cx + x, fy + 5, z, Blocks.LANTERN)

	surface.add_spawn("enemy", _w(bp, Vector3(cx + 4, y + 1, cz + 9)), {"kind": "ghoul"})
	for i in 6:
		depths.add_spawn("enemy", _w(bp, Vector3(cx + (i % 2) * 8 - 4, fy, hz0 + 4 + i * 3)), {"kind": "skeleton" if i % 3 else "archer"})
	depths.add_spawn("boss", _w(bp, Vector3(cx, fy, (bz0 + bz1) / 2.0)), {"kind": "warden"})
	depths.add_spawn("chest", _w(bp, Vector3(cx, fy, bz0 + 2)), {"tier": 2})
	depths.center = _w(bp, Vector3(cx, fy + 1, (bz0 + hz1) / 2.0))
	depths.radius = 34.0
	depths.ground_y = int(depths.center.y)


# --- Hall of the Mountain King ---------------------------------------------------

static func mountain_hall(loc: Location, exit_dir: Vector2i, exit_y: int, rng: RandomNumberGenerator) -> void:
	var floor_y := int(loc.center.y) - 1
	var c := Vector3i(int(loc.center.x), floor_y, int(loc.center.z))
	# One blueprint covers the hall plus the tunnel in any direction.
	var reach := 100
	var bp := Blueprint.new(Vector3i(c.x - reach, mini(floor_y, exit_y) - 4, c.z - reach),
			Vector3i(reach * 2 + 1, absi(exit_y - floor_y) + 28, reach * 2 + 1))
	loc.blueprints.append(bp)
	var lc := c - bp.origin  # local hall centre at floor level
	var hx := 17
	var hz := 28
	var h := 18
	# The hall is oriented so its long axis runs along the exit direction.
	var along := Vector3i(exit_dir.x, 0, exit_dir.y)
	var across := Vector3i(exit_dir.y, 0, -exit_dir.x)
	for a in range(-hz, hz + 1):
		for b in range(-hx, hx + 1):
			var p := lc + along * a + across * b
			bp.set_local(p.x, p.y, p.z, Blocks.DEEPSLATE if (a + b) % 4 else Blocks.COBBLE)
			var roof := h - int(pow(absf(b) / hx, 2.0) * 5.0)
			for y in range(1, roof):
				bp.set_local(p.x, p.y + y, p.z, Blueprint.CARVE)
			# Frost crystals glinting in the walls.
			if absi(b) == hx and rng.randf() < 0.18:
				var wall := p + across * signi(b)
				bp.set_local(wall.x, wall.y + rng.randi_range(2, 10), wall.z, Blocks.CRYSTAL)
	for a in range(-hz + 4, hz - 3, 8):
		for b: int in [-9, 9]:
			var p := lc + along * a + across * b
			bp.cylinder(Vector3i(p.x, p.y + 1, p.z), 1.6, h - 3, Blocks.COBBLE)
			bp.set_local(p.x, p.y + 6, p.z, Blocks.CRYSTAL)
	# Throne at the far end.
	var t := lc - along * (hz - 3)
	for step in 3:
		for b in range(-5 + step, 6 - step):
			for d in range(0, 4 - step):
				var p := t + across * b - along * d
				bp.set_local(p.x, p.y + 1 + step, p.z, Blocks.GOLD_BLOCK)
	for y in range(4, 10):
		for b in range(-2, 3):
			var p := t - along * 3 + across * b
			bp.set_local(p.x, p.y + y, p.z, Blocks.RUNESTONE)
	# Tunnel out to the mountainside, sloping to meet the ground.
	var start := lc + along * hz
	var tunnel_len := 75
	for i in tunnel_len:
		var fy := int(lerpf(0.0, float(exit_y - floor_y), float(i) / tunnel_len))
		for b in range(-3, 4):
			var p := start + along * i + across * b
			bp.set_local(p.x, p.y + fy, p.z, Blocks.COBBLE)
			for y in range(1, 7):
				bp.set_local(p.x, p.y + fy + y, p.z, Blueprint.CARVE)
		if i % 9 == 0:
			var lp := start + along * i + across * 3
			bp.set_local(lp.x, lp.y + fy + 4, lp.z, Blocks.LANTERN)
	# Great doorway.
	for b in range(-5, 6):
		for y in range(0, 10):
			var p := start + across * b
			if absi(b) == 5 or y == 9:
				bp.set_local(p.x, p.y + y, p.z, Blocks.RUNESTONE)
			else:
				bp.set_local(p.x, p.y + y, p.z, Blueprint.CARVE)

	loc.add_spawn("boss", _w(bp, Vector3(lc) + Vector3(along) * -6.0 + Vector3(0, 1, 0)), {"kind": "mountain_king"})
	for i in 4:
		loc.add_spawn("enemy", _w(bp, Vector3(lc + along * (i * 10 - 10) + across * (6 if i % 2 else -6)) + Vector3(0, 1, 0)), {"kind": "troll"})
	for i in 3:
		loc.add_spawn("enemy", _w(bp, Vector3(start + along * (15 + i * 18)) + Vector3(0, 1 + (exit_y - floor_y) * (15.0 + i * 18.0) / tunnel_len, 0)), {"kind": "skeleton"})
	loc.add_spawn("chest", _w(bp, Vector3(t - along * 5) + Vector3(2, 1, 0)), {"tier": 3})
	loc.add_spawn("arena_gate", _w(bp, Vector3(start)), {"along": along, "across": across, "width": 4, "height": 8})
	loc.center = _w(bp, Vector3(lc) + Vector3(0, 1, 0))


# --- The Dragon's Keep ------------------------------------------------------------

static func castle(loc: Location, rng: RandomNumberGenerator) -> void:
	loc.radius = 52.0
	loc.pad_radius = 47.0
	loc.pad_falloff = 14.0
	var bp := _bp(loc, Vector3i(52, 0, 52), 4, 40)
	var c := Vector3i(52, 4, 52)  # local centre, ground level
	var half := 40
	var wall_h := 14
	# Courtyard paving.
	for dz in range(-half, half + 1):
		for dx in range(-half, half + 1):
			var r := rng.randf()
			bp.set_local(c.x + dx, c.y, c.z + dz, Blocks.COBBLE if r < 0.55 else (Blocks.ASH if r < 0.85 else Blocks.GRAVEL))
	# Curtain walls.
	for side in 4:
		var dir := [Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, 0, -1)][side] as Vector3i
		var normal := Vector3i(dir.z, 0, -dir.x)
		var from := c + dir * -half + normal * half
		var to := c + dir * half + normal * half
		bp.fill(Vector3i(mini(from.x, to.x), c.y + 1, mini(from.z, to.z)) - (Vector3i(1, 0, 1) - dir.abs()),
				Vector3i(maxi(from.x, to.x), c.y + wall_h, maxi(from.z, to.z)) + (Vector3i(1, 0, 1) - dir.abs()), Blocks.BRICK)
		bp.crenellate(from + Vector3i(0, wall_h, 0), to + Vector3i(0, wall_h, 0), Blocks.BRICK)
	# Corner towers.
	for corner: Vector2i in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		var tc := c + Vector3i(corner.x * half, 1, corner.y * half)
		bp.cylinder(tc, 5.5, wall_h + 7, Blocks.BRICK, true)
		bp.cylinder(tc + Vector3i(0, wall_h + 7, 0), 6.2, 1, Blocks.BRICK)
		for i in 16:
			if i % 2 == 0:
				var a := TAU * i / 16.0
				bp.set_local(tc.x + roundi(cos(a) * 6.0), tc.y + wall_h + 8, tc.z + roundi(sin(a) * 6.0), Blocks.BRICK)
		bp.set_local(tc.x, tc.y + wall_h + 8, tc.z, Blocks.LANTERN)
	# Gatehouse on the north wall (facing the crater road).
	var gz := c.z - half
	bp.fill(Vector3i(c.x - 4, c.y + 1, gz - 2), Vector3i(c.x + 4, c.y + 9, gz + 2), Blueprint.CARVE)
	for gx: int in [-8, 8]:
		bp.cylinder(Vector3i(c.x + gx, c.y + 1, gz), 3.6, wall_h + 5, Blocks.BRICK, true)
		bp.set_local(c.x + gx, c.y + wall_h + 6, gz, Blocks.LANTERN)
	bp.fill(Vector3i(c.x - 4, c.y + 10, gz - 2), Vector3i(c.x + 4, c.y + 10, gz - 2), Blocks.IRON_BARS)
	# The keep at the south end.
	var k0 := Vector3i(c.x - 12, c.y + 1, c.z + 16)
	var k1 := Vector3i(c.x + 12, c.y + 26, c.z + 36)
	bp.hollow(k0, k1, Blocks.BRICK)
	for fy: int in [9, 17]:
		bp.fill(Vector3i(k0.x + 1, c.y + fy, k0.z + 1), Vector3i(k1.x - 1, c.y + fy, k1.z - 1), Blocks.PLANKS)
		bp.fill(Vector3i(k0.x + 2, c.y + fy, k0.z + 2), Vector3i(k0.x + 4, c.y + fy, k0.z + 4), Blueprint.CARVE)
	bp.fill(Vector3i(k0.x, c.y + 26, k0.z), Vector3i(k1.x, c.y + 26, k1.z), Blocks.BRICK)
	bp.crenellate(Vector3i(k0.x, c.y + 26, k0.z), Vector3i(k1.x, c.y + 26, k0.z), Blocks.BRICK)
	bp.fill(Vector3i(c.x - 2, c.y + 1, k0.z), Vector3i(c.x + 2, c.y + 6, k0.z), Blueprint.CARVE)
	for x in range(k0.x + 3, k1.x - 2, 4):
		for y: int in [5, 13, 21]:
			bp.set_local(x, c.y + y, k0.z, Blueprint.CARVE)
	# Fire basins in the courtyard.
	for corner: Vector2i in [Vector2i(-24, -24), Vector2i(24, -24), Vector2i(-24, 8), Vector2i(24, 8)]:
		var bc := c + Vector3i(corner.x, 1, corner.y)
		bp.cylinder(bc, 1.8, 1, Blocks.BRICK)
		bp.set_local(bc.x, bc.y, bc.z, Blocks.LAVA)

	loc.add_spawn("boss", _w(bp, Vector3(c.x, c.y + 1, c.z - 6)), {"kind": "dragon"})
	for i in 6:
		var a := TAU * i / 6.0
		loc.add_spawn("enemy", _w(bp, Vector3(c.x + cos(a) * 30.0, c.y + 1, c.z + sin(a) * 30.0)), {"kind": "skeleton" if i % 2 else "archer"})
	loc.add_spawn("chest", _w(bp, Vector3(c.x, c.y + 18, c.z + 30)), {"tier": 3})
	loc.add_spawn("arena_gate", _w(bp, Vector3(c.x, c.y + 1, gz)), {"along": Vector3i(0, 0, 1), "across": Vector3i(1, 0, 0), "width": 4, "height": 9})


# --- Gates of Hades --------------------------------------------------------------

static func gates_of_hades(loc: Location, rng: RandomNumberGenerator) -> void:
	var c := Vector3i(loc.center.round())
	var bp := Blueprint.new(c - Vector3i(46, 24, 46), Vector3i(93, 48, 93))
	loc.blueprints.append(bp)
	var lc := Vector3i(46, 24, 46)
	bp.ellipsoid(lc, Vector3(44, 20, 44), Blueprint.CARVE)
	var floor_y := lc.y - 12
	for dz in range(-44, 45):
		for dx in range(-44, 45):
			if dx * dx + dz * dz > 44 * 44:
				continue
			bp.fill(Vector3i(lc.x + dx, floor_y - 6, lc.z + dz), Vector3i(lc.x + dx, floor_y, lc.z + dz), Blocks.BASALT)
			if rng.randf() < 0.08:
				bp.set_local(lc.x + dx, floor_y, lc.z + dz, Blocks.OBSIDIAN)
	# Lava pools.
	for i in 6:
		var a := rng.randf() * TAU
		var r := rng.randf_range(14.0, 34.0)
		var pc := Vector3i(lc.x + roundi(cos(a) * r), floor_y, lc.z + roundi(sin(a) * r))
		if pc.z < lc.z - 18:
			continue
		bp.cylinder(pc - Vector3i(0, 1, 0), rng.randf_range(2.5, 5.0), 2, Blocks.LAVA)
	# The Gate: an obsidian frame on the north side.
	var gz := lc.z - 30
	for side: int in [-1, 1]:
		bp.fill(Vector3i(lc.x + side * 9 - 1, floor_y + 1, gz - 1), Vector3i(lc.x + side * 9 + 1, floor_y + 22, gz + 1), Blocks.OBSIDIAN)
		for y in range(floor_y + 3, floor_y + 21, 4):
			bp.set_local(lc.x + side * 9, y, gz + 2, Blocks.RUNESTONE)
	bp.fill(Vector3i(lc.x - 11, floor_y + 20, gz - 1), Vector3i(lc.x + 11, floor_y + 23, gz + 1), Blocks.OBSIDIAN)
	bp.fill(Vector3i(lc.x - 4, floor_y + 24, gz), Vector3i(lc.x + 4, floor_y + 24, gz), Blocks.HELLSTONE)
	for i in 6:
		bp.fill(Vector3i(lc.x - 8 + i, floor_y + 1, gz + 2 + i), Vector3i(lc.x + 8 - i, floor_y + 1, gz + 2 + i), Blocks.OBSIDIAN)
	for z in range(gz + 10, lc.z + 20, 8):
		for x: int in [-6, 6]:
			bp.cylinder(Vector3i(lc.x + x, floor_y + 1, z), 1.2, 1, Blocks.BASALT)
			bp.set_local(lc.x + x, floor_y + 1, z, Blocks.LAVA)
	loc.add_spawn("portal", _w(bp, Vector3(lc.x, floor_y + 1, gz)), {"to": 1, "size": Vector2(14, 19)})
	loc.add_spawn("shrine", _w(bp, Vector3(lc.x, floor_y + 1, lc.z + 14)))
	for i in 5:
		var a := rng.randf() * TAU
		loc.add_spawn("enemy", _w(bp, Vector3(lc.x + cos(a) * 20.0, floor_y + 1, lc.z + sin(a) * 20.0)), {"kind": "imp"})
	loc.center = _w(bp, Vector3(lc.x, floor_y + 1, lc.z))


static func crater_marker(loc: Location, rng: RandomNumberGenerator) -> void:
	# Basalt spires around the crater floor hint at what lies beneath.
	var bp := _bp(loc, Vector3i(40, 0, 40), 2, 14)
	for i in 9:
		var a := TAU * i / 9.0 + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(12.0, 30.0)
		var p := Vector3i(40 + roundi(cos(a) * r), 3, 40 + roundi(sin(a) * r))
		bp.cylinder(p, rng.randf_range(0.8, 1.8), rng.randi_range(4, 11), Blocks.BASALT)
	bp.cylinder(Vector3i(40, 1, 40), 2.2, 2, Blocks.OBSIDIAN)
	bp.set_local(40, 3, 40, Blocks.RUNESTONE)
	loc.add_spawn("lore", _w(bp, Vector3(40, 4, 40)), {"text": "crater"})


# --- Hell -------------------------------------------------------------------------

static func hell_spawn(loc: Location) -> void:
	loc.pad_radius = 16.0
	loc.pad_falloff = 10.0
	var bp := _bp(loc, Vector3i(14, 0, 14), 3, 20)
	var c := Vector3i(14, 3, 14)
	bp.cylinder(c, 9.0, 1, Blocks.OBSIDIAN)
	bp.cylinder(c, 6.0, 1, Blocks.BASALT)
	for side: int in [-1, 1]:
		bp.fill(Vector3i(c.x + side * 5, c.y + 1, c.z - 8), Vector3i(c.x + side * 5, c.y + 12, c.z - 7), Blocks.OBSIDIAN)
	bp.fill(Vector3i(c.x - 5, c.y + 13, c.z - 8), Vector3i(c.x + 5, c.y + 13, c.z - 7), Blocks.OBSIDIAN)
	for i in 8:
		var a := TAU * i / 8.0
		var p := c + Vector3i(roundi(cos(a) * 8.0), 1, roundi(sin(a) * 8.0))
		bp.fill(p, p + Vector3i(0, 2, 0), Blocks.BONE)
		bp.set_local(p.x, p.y + 3, p.z, Blocks.LANTERN)
	loc.add_spawn("portal", _w(bp, Vector3(c.x, c.y + 1, c.z - 7)), {"to": 0, "size": Vector2(8, 12)})
	loc.add_spawn("shrine", _w(bp, Vector3(c.x, c.y + 1, c.z + 4)))


static func tartarus(loc: Location, rng: RandomNumberGenerator) -> void:
	loc.radius = 42.0
	loc.pad_radius = 40.0
	loc.pad_falloff = 12.0
	var bp := _bp(loc, Vector3i(44, 0, 44), 4, 24)
	var c := Vector3i(44, 4, 44)
	bp.cylinder(c, 27.0, 1, Blocks.OBSIDIAN)
	for r in range(28, 32):
		for i in 360:
			var a := deg_to_rad(i)
			var p := c + Vector3i(roundi(cos(a) * r), 0, roundi(sin(a) * r))
			var gap := fmod(float(i) + 22.5, 90.0) < 9.0
			if r >= 30:
				if not gap:
					bp.fill(p + Vector3i(0, 1, 0), p + Vector3i(0, 10, 0), Blocks.BASALT)
			bp.set_local(p.x, p.y, p.z, Blocks.BASALT)
	for i in 360:
		var a := deg_to_rad(i)
		var gap := fmod(float(i) + 22.5, 90.0) < 9.0
		for r in range(33, 38):
			var p := c + Vector3i(roundi(cos(a) * r), 0, roundi(sin(a) * r))
			bp.set_local(p.x, p.y, p.z, Blocks.BASALT if gap else Blocks.LAVA)
			bp.set_local(p.x, p.y - 1, p.z, Blocks.BASALT)
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		var tc := c + Vector3i(roundi(cos(a) * 30.0), 1, roundi(sin(a) * 30.0))
		bp.cylinder(tc, 3.5, 16, Blocks.BASALT, true)
		bp.set_local(tc.x, tc.y + 16, tc.z, Blocks.HELLSTONE)
	for i in 6:
		var a := rng.randf() * TAU
		var p := c + Vector3i(roundi(cos(a) * 18.0), 1, roundi(sin(a) * 18.0))
		bp.cylinder(p, 1.0, rng.randi_range(3, 7), Blocks.BONE)
	loc.add_spawn("boss", _w(bp, Vector3(c.x, c.y + 1, c.z)), {"kind": "cerberus"})
	for i in 4:
		var a := TAU * i / 4.0
		loc.add_spawn("enemy", _w(bp, Vector3(c.x + cos(a) * 40.0, c.y + 1, c.z + sin(a) * 40.0)), {"kind": "imp"})
	loc.add_spawn("chest", _w(bp, Vector3(c.x + 20, c.y + 1, c.z)), {"tier": 3})
	loc.add_spawn("shrine", _w(bp, Vector3(c.x, c.y + 1, c.z + 44)))


static func throne(loc: Location, rng: RandomNumberGenerator) -> void:
	loc.radius = 40.0
	loc.pad_radius = 38.0
	loc.pad_falloff = 12.0
	var bp := _bp(loc, Vector3i(40, 0, 40), 4, 34)
	var c := Vector3i(40, 4, 40)
	bp.fill(Vector3i(c.x - 20, c.y, c.z - 32), Vector3i(c.x + 20, c.y, c.z + 32), Blocks.OBSIDIAN)
	for z in range(c.z - 32, c.z + 33):
		for x: int in [-22, -21, 21, 22]:
			bp.set_local(c.x + x, c.y, z, Blocks.LAVA)
	for z in range(c.z - 26, c.z + 27, 9):
		for x: int in [-14, 14]:
			bp.cylinder(Vector3i(c.x + x, c.y + 1, z), 1.8, 18, Blocks.OBSIDIAN)
			bp.set_local(c.x + x, c.y + 8, z, Blocks.HELLSTONE)
			bp.set_local(c.x + x, c.y + 18, z, Blocks.HELLSTONE)
	# Throne dais at the far (south) end.
	for step in 4:
		bp.fill(Vector3i(c.x - 9 + step * 2, c.y + 1 + step, c.z + 22 + step), Vector3i(c.x + 9 - step * 2, c.y + 1 + step, c.z + 31), Blocks.OBSIDIAN)
	bp.fill(Vector3i(c.x - 2, c.y + 5, c.z + 29), Vector3i(c.x + 2, c.y + 5, c.z + 30), Blocks.GOLD_BLOCK)
	bp.fill(Vector3i(c.x - 3, c.y + 6, c.z + 31), Vector3i(c.x + 3, c.y + 16, c.z + 31), Blocks.HELLSTONE)
	bp.fill(Vector3i(c.x - 1, c.y + 17, c.z + 31), Vector3i(c.x + 1, c.y + 19, c.z + 31), Blocks.GOLD_BLOCK)
	for i in 10:
		var p := c + Vector3i(rng.randi_range(-18, 18), 1, rng.randi_range(-30, 18))
		bp.set_local(p.x, p.y, p.z, Blocks.BONE)
	loc.add_spawn("boss", _w(bp, Vector3(c.x, c.y + 1, c.z + 12)), {"kind": "hades"})
	loc.add_spawn("shrine", _w(bp, Vector3(c.x, c.y + 1, c.z - 40)))
	for i in 4:
		loc.add_spawn("enemy", _w(bp, Vector3(c.x + (i - 1.5) * 8.0, c.y + 1, c.z - 20)), {"kind": "shade"})
	loc.add_spawn("arena_gate", _w(bp, Vector3(c.x, c.y + 1, c.z - 33)), {"along": Vector3i(0, 0, 1), "across": Vector3i(1, 0, 0), "width": 6, "height": 8})
