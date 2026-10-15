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

	# Grass commons and well. No stamped plaza or village paths.
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
			_house(loc, bp, Vector3i(hp.x, fy, hp.y), 11, 9, 5, door, true)
			var door_w := _w(bp, Vector3(hp.x + door.x * 6, fy + 1, hp.y + door.y * 6))
			loc.add_spawn("npc", door_w, {"role": "elder" if is_start else "chief"})
			loc.add_spawn("chest", _w(bp, Vector3(hp.x - door.x * 3, fy + 1, hp.y - door.y * 3)), {"tier": 1})
		elif i == 1:
			_forge(bp, Vector3i(hp.x, fy, hp.y))
			loc.add_spawn("npc", _w(bp, Vector3(hp.x + door.x * 4, fy + 1, hp.y + door.y * 4)), {"role": "blacksmith"})
			# Crafting stations at the smithy (spawned by LocationDirector once stations exist).
			loc.add_spawn("station", _w(bp, Vector3(hp.x + 1, fy + 1, hp.y - 2)), {"station": "anvil", "yaw": 0.0})
			loc.add_spawn("station", _w(bp, Vector3(hp.x - 2, fy + 1, hp.y + 2)), {"station": "furnace", "yaw": PI})
			loc.add_spawn("station", _w(bp, Vector3(hp.x + 3, fy + 1, hp.y - 2)), {"station": "workbench", "yaw": 0.0})
		else:
			_house(loc, bp, Vector3i(hp.x, fy, hp.y), 7 + 2 * rng.randi_range(0, 1), 6 + rng.randi_range(0, 2), 4, door, false)
	for i in 4:
		var ang := rng.randf() * TAU
		loc.add_spawn("npc", _w(bp, Vector3(cx + cos(ang) * 10.0, fy + 1, cz + sin(ang) * 10.0)), {"role": "villager"})
	loc.add_spawn("npc", _w(bp, Vector3(cx + 4, fy + 1, cz - 3)), {"role": "merchant"})
	loc.add_spawn("guard_post", _w(bp, Vector3(cx, fy + 1, cz)), {})


static func _house(loc: Location, bp: Blueprint, c: Vector3i, w: int, d: int, wall_h: int, door: Vector2i, hall: bool) -> void:
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
	Architecture.house(loc, bp, c, w, d, wall_h)


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

## Moved to Battlegrounds (modelled arena, STRUCTURE collision).
static func crypt(surface: Location, depths: Location) -> void:
	Battlegrounds.crypt(surface, depths)


# --- Hall of the Mountain King ---------------------------------------------------

## Moved to Battlegrounds (modelled arena, STRUCTURE collision).
static func mountain_hall(loc: Location, exit_dir: Vector2i, exit_y: int, rng: RandomNumberGenerator) -> void:
	Battlegrounds.mountain_hall(loc, exit_dir, exit_y, rng)


# --- The Dragon's Keep ------------------------------------------------------------

## Moved to Battlegrounds (modelled arena, STRUCTURE collision).
static func castle(loc: Location, rng: RandomNumberGenerator) -> void:
	Battlegrounds.castle(loc, rng)


# --- Gates of Hades --------------------------------------------------------------

## Moved to Battlegrounds (modelled arena, STRUCTURE collision).
static func gates_of_hades(loc: Location, rng: RandomNumberGenerator) -> void:
	Battlegrounds.gates_of_hades(loc, rng)


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


## Moved to Battlegrounds (modelled arena, STRUCTURE collision).
static func tartarus(loc: Location, rng: RandomNumberGenerator) -> void:
	Battlegrounds.tartarus(loc, rng)


## Moved to Battlegrounds (modelled arena, STRUCTURE collision).
static func throne(loc: Location, rng: RandomNumberGenerator) -> void:
	Battlegrounds.throne(loc, rng)
