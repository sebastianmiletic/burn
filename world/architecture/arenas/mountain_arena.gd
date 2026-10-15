class_name MountainArena
extends RefCounted
## Hall of the Mountain King: a colossal dwarven hall carved into the mountain.
## Square carved pillars with bronze bands and rune glyphs, a ribbed vault, a
## rune-carved floor, a throne dais between two king statues, fire braziers and
## iron chandeliers against blue frost and ice, and a stepped tunnel closed by a
## carved stone door. Local frame: x across the hall, z along it (towards the
## exit), y up, floor at 0. Mirrors Battlegrounds.mountain_hall.

const K := preload("res://world/architecture/arenas/arena_kit.gd")
const P := preload("res://world/architecture/arenas/arena_pieces.gd")

const STONE := Color(0.5, 0.5, 0.54)
const SLATE := Color(0.42, 0.45, 0.5)
const RUNE := Color(0.35, 0.75, 1.0)
const FIRE := Color(1.0, 0.55, 0.24)


static func vault_y(x: float) -> float:
	return 16.2 - 4.4 * (x / 17.0) * (x / 17.0)


static func build(b: ArenaBuild) -> void:
	var pr := b.prop
	var along: Vector3 = pr["along"]
	var across: Vector3 = pr["across"]
	var hx := float(pr["hx"]) + 0.5
	var hz := float(pr["hz"]) + 0.5
	var ta := float(pr["throne_a"])
	var basis := Basis(across, Vector3.UP, along)
	var frame := Transform3D(basis, b.center)
	b.params = {"frost": 0.55, "grime": 0.35, "grime_color": Color(0.3, 0.3, 0.33), "ambient": 0.35, "frost_color": Color(0.8, 0.9, 1.0)}
	var k := b.shell
	var d := b.detail
	for kit: K in [k, d]:
		kit.push(frame)
		kit.ao_floor = 0.0
	var to_world := func(p: Vector3) -> Vector3:
		return frame * p
	# --- Floor: slate tiles, a rune band down the nave, the seal before the throne.
	k.ao_floor = -INF
	k.mat(K.DARK, SLATE, 0.4)
	var skip := func(x: float, z: float) -> bool:
		for pl: Vector2 in pr["pillars"]:
			if absf(x - pl.y) < 1.6 and absf(z - pl.x) < 1.6:
				return true
		return absf(x) < 2.6
	k.flagstones(-hx, -hz, hx, hz, 0.0, 2.0, 0.05, 0.4, 0.0, skip)
	k.mat(K.CARVED, Color(0.55, 0.55, 0.6), 0.5)
	k.flagstones(-2.6, -hz, 2.6, hz, 0.0, 1.3, 0.04, 0.4)
	k.ao_floor = 0.0
	k.mat(K.GLOW, RUNE, 1.0, 1.8)
	var z := -hz + 1.5
	var gi := 0
	while z < hz - 1.0:
		_glyph(k, Vector3(0, 0.012, z), 0.9, gi)
		z += 2.6
		gi += 1
	for x: float in [-2.75, 2.75]:
		k.beam(Vector3(x, 0.01, -hz + 0.5), Vector3(x, 0.01, hz - 0.5), 0.06, 0.02, 0.0)
	_rune_circle(k, Vector3(0, 0.012, -6.0), 6.5)
	b.light(to_world.call(Vector3(0, 1.0, -6.0)), RUNE, 1.6, 10.0, 0, 0.1, 0.5)
	# --- Walls and vault ----------------------------------------------------------
	_walls(b, k, d, hx, hz, frame)
	# --- Pillars -------------------------------------------------------------------
	for pl: Vector2 in pr["pillars"]:
		_pillar(k, d, Vector3(pl.y, 0, pl.x))
	# --- Dais, throne and kings ----------------------------------------------------
	_dais(b, k, ta, frame)
	# --- Braziers and chandeliers ---------------------------------------------------
	for za: float in [-16.0, 0.0, 16.0]:
		for x: float in [-5.0, 5.0]:
			P.fire_basin(b, k, Vector3(x, 0, za), to_world.call(Vector3(x, 0, za)), 1.0, "fire", K.CARVED, FIRE, 1 if za == 0.0 else 0)
	for za: float in [-10.0, 8.0, 24.0]:
		_chandelier(b, d, Vector3(0, 10.5, za), vault_y(0.0), frame)
	# --- Door and tunnel -------------------------------------------------------------
	_door(b, k, hz, frame)
	_tunnel(b, k, d, hz, pr["steps"], frame)


## A dwarven glyph: angular strokes inside a square, seeded.
static func _glyph(k: K, at: Vector3, s: float, seed_value: int) -> void:
	var pts := [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3.ZERO]
	var h := seed_value * 2654435761
	for i in 4:
		var a: Vector3 = pts[(h >> (i * 4)) % pts.size()]
		var e: Vector3 = pts[(h >> (i * 4 + 2)) % pts.size()]
		if a.distance_to(e) < 0.5:
			e = pts[(i + 3) % pts.size()]
		k.beam(at + a * s * 0.45, at + e * s * 0.45, 0.07, 0.02, 0.0)
	# frame
	for i in 4:
		var a: Vector3 = pts[i] * s * 0.55
		var e: Vector3 = pts[(i + 1) % 4] * s * 0.55
		k.beam(at + a, at + e, 0.05, 0.02, 0.0)


static func _rune_circle(k: K, at: Vector3, r: float) -> void:
	k.mat(K.GOLD, Color(1, 1, 1), 1.0)
	k.push(Transform3D(Basis.IDENTITY, at))
	for rr: float in [r, r - 0.9]:
		k.lathe(PackedVector2Array([Vector2(rr - 0.12, -0.01), Vector2(rr - 0.1, 0.02), Vector2(rr + 0.1, 0.02), Vector2(rr + 0.12, -0.01)]), 56)
	k.mat(K.GLOW, RUNE, 1.0, 2.0)
	var n := 16
	for i in n:
		var a := TAU * i / n
		var dir := Vector3(cos(a), 0, sin(a))
		var tan := Vector3(-dir.z, 0, dir.x)
		var c := dir * (r - 0.45)
		k.push(Transform3D(Basis(tan, Vector3.UP, dir), c))
		_glyph(k, Vector3.ZERO, 0.55, i + 11)
		k.pop()
	# spokes to an inner hexagon
	for i in 6:
		var a0 := TAU * i / 6.0
		var a1 := TAU * (i + 1) / 6.0
		k.beam(Vector3(cos(a0), 0, sin(a0)) * r * 0.45, Vector3(cos(a1), 0, sin(a1)) * r * 0.45, 0.08, 0.02, 0.0)
		k.beam(Vector3(cos(a0), 0, sin(a0)) * r * 0.45, Vector3(cos(a0), 0, sin(a0)) * (r - 0.95), 0.06, 0.02, 0.0)
	k.pop()


static func _walls(b: ArenaBuild, k: K, d: K, hx: float, hz: float, frame: Transform3D) -> void:
	var top := vault_y(hx) + 0.05
	# Side walls: pilasters every 4 m, recessed panels, a cornice under the vault.
	for side: float in [-1.0, 1.0]:
		var x := side * (hx - 0.05)
		k.mat(K.GRANITE, STONE, 0.3)
		k.pquad(Vector3(x, 0, -hz), Vector3(x, 0, hz), Vector3(x, top, hz), Vector3(x, top, -hz), Vector3(-side, 0, 0))
		k.mat(K.CARVED, STONE * Color(1.05, 1.05, 1.08), 0.35)
		var zz := -hz + 2.0
		while zz < hz - 1.0:
			k.box(Vector3(x - side * 0.35, top * 0.5, zz), Vector3(0.7, top, 1.4), 0.06)
			zz += 4.0
		k.moulding(Vector3(x, 0, hz), Vector3(x, 0, -hz), Vector3(-side, 0, 0), PackedVector2Array([Vector2(0.9, 0.0), Vector2(0.9, 0.6), Vector2(0.6, 0.8), Vector2(0.0, 1.0)]))
		k.moulding(Vector3(x, 0, hz), Vector3(x, 0, -hz), Vector3(-side, 0, 0), PackedVector2Array([Vector2(0.0, top - 1.4), Vector2(0.5, top - 1.1), Vector2(0.55, top - 0.6), Vector2(1.0, top - 0.2), Vector2(1.0, top)]))
		k.moulding(Vector3(x, 0, hz), Vector3(x, 0, -hz), Vector3(-side, 0, 0), PackedVector2Array([Vector2(0.0, 5.8), Vector2(0.25, 5.9), Vector2(0.25, 6.3), Vector2(0.0, 6.4)]))
		# icicles under the cornice, ice at the foot of the wall
		d.mat(K.TRI + K.SNOW, Color(0.75, 0.88, 1.0), 0.5, 0.25)
		var zi := -hz + 0.7
		while zi < hz - 0.5:
			if d.rng.randf() < 0.7:
				d.spike(Vector3(x - side * (0.6 + d.rng.randf() * 0.35), top - 0.25, zi), Vector3.DOWN, d.rng.randf_range(0.5, 1.8), d.rng.randf_range(0.06, 0.14), 5, int(zi * 10.0))
			zi += d.rng.randf_range(0.3, 0.9)
		for j in 7:
			var zc := d.rng.randf_range(-hz + 2.0, hz - 2.0)
			_ice_cluster(b, d, Vector3(x - side * 1.1, 0, zc), frame, j)
	# End walls: the throne end carries a great rune disc; the door end has the doorway.
	for endz: float in [-hz + 0.05, hz - 0.05]:
		var nz := -signf(endz)
		k.mat(K.GRANITE, STONE, 0.3)
		var poly := PackedVector2Array()
		for i in 17:
			var x := lerpf(-hx, hx, float(i) / 16.0)
			poly.append(Vector2(x, vault_y(x) + 0.05))
		poly.append(Vector2(hx, 0))
		poly.append(Vector2(-hx, 0))
		if endz < 0.0:
			k.push(Transform3D(Basis.IDENTITY, Vector3(0, 0, endz)))
			k.extrude(poly, -0.3, 0.0, true)
			k.pop()
		else:
			# leave the doorway open (x -4.5..4.5, y 0..8)
			var left := PackedVector2Array([Vector2(-hx, 0), Vector2(-4.5, 0), Vector2(-4.5, 8.0), Vector2(0, 8.0)])
			var right := PackedVector2Array([Vector2(0, 8.0), Vector2(4.5, 8.0), Vector2(4.5, 0), Vector2(hx, 0)])
			var upper := PackedVector2Array()
			for i in 17:
				var x := lerpf(-hx, hx, float(i) / 16.0)
				upper.append(Vector2(x, vault_y(x) + 0.05))
			var full := PackedVector2Array()
			full.append_array(left)
			full.append_array(right)
			for i in range(upper.size() - 1, -1, -1):
				full.append(upper[i])
			k.push(Transform3D(Basis.IDENTITY, Vector3(0, 0, endz)))
			k.extrude(full, 0.0, 0.3, true)
			k.pop()
	# The vault: a smooth barrel under the carved rock, with transverse and long ribs.
	k.mat(K.GRANITE, STONE * Color(0.9, 0.92, 0.98), 0.3)
	var nx := 24
	for i in nx:
		var x0 := lerpf(-hx, hx, float(i) / nx)
		var x1 := lerpf(-hx, hx, float(i + 1) / nx)
		var y0 := vault_y(x0)
		var y1 := vault_y(x1)
		var n0 := Vector3(-2.0 * 4.4 * x0 / (17.0 * 17.0), -1.0, 0).normalized()
		var n1 := Vector3(-2.0 * 4.4 * x1 / (17.0 * 17.0), -1.0, 0).normalized()
		var a := k._v(Vector3(x0, y0, -hz), n0, Vector2(x0, -hz))
		var bb := k._v(Vector3(x1, y1, -hz), n1, Vector2(x1, -hz))
		var cc := k._v(Vector3(x1, y1, hz), n1, Vector2(x1, hz))
		var dd := k._v(Vector3(x0, y0, hz), n0, Vector2(x0, hz))
		k._t(a, bb, cc)
		k._t(a, cc, dd)
	k.mat(K.CARVED, STONE * Color(1.05, 1.05, 1.1), 0.35)
	var zr := -hz + 4.0
	while zr < hz - 1.0:
		_rib(k, zr, hx)
		zr += 8.0
	for xr: float in [-9.0, 0.0, 9.0]:
		var y := vault_y(xr) - 0.35
		k.box(Vector3(xr, y, 0), Vector3(1.0, 0.7, hz * 2.0), 0.08, false)
	# frost icicles from the ribs
	d.mat(K.TRI + K.SNOW, Color(0.75, 0.88, 1.0), 0.5, 0.25)
	zr = -hz + 4.0
	while zr < hz - 1.0:
		for j in 9:
			var x := d.rng.randf_range(-hx + 1.0, hx - 1.0)
			d.spike(Vector3(x, vault_y(x) - 0.6, zr + d.rng.randf_range(-0.4, 0.4)), Vector3.DOWN, d.rng.randf_range(0.6, 2.4), d.rng.randf_range(0.08, 0.18), 5, j)
		zr += 8.0


## A transverse stone rib following the vault at z.
static func _rib(k: K, z: float, hx: float) -> void:
	var path := PackedVector3Array()
	var n := 20
	for i in n + 1:
		var x := lerpf(-hx, hx, float(i) / n)
		path.append(Vector3(x, vault_y(x) - 0.3, z))
	var prev := path[0]
	for i in range(1, path.size()):
		var p := path[i]
		k.beam(prev, p, 0.9, 0.7, 0.06, Vector3(0, 0, 1))
		prev = p


static func _pillar(k: K, d: K, at: Vector3) -> void:
	var top := vault_y(at.x) - 0.2
	k.push(Transform3D(Basis.IDENTITY, at))
	var sq := func(hw: float, ch: float) -> PackedVector2Array:
		return PackedVector2Array([Vector2(-hw + ch, -hw), Vector2(hw - ch, -hw), Vector2(hw, -hw + ch), Vector2(hw, hw - ch),
				Vector2(hw - ch, hw), Vector2(-hw + ch, hw), Vector2(-hw, hw - ch), Vector2(-hw, -hw + ch)])
	k.push(Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3.ZERO))
	k.mat(K.CARVED, STONE, 0.35)
	k.extrude(sq.call(2.0, 0.4), 0.0, 0.6)
	k.extrude(sq.call(1.8, 0.4), 0.6, 1.3)
	k.mat(K.GRANITE, STONE * Color(0.95, 0.95, 1.0), 0.3)
	k.extrude(sq.call(1.5, 0.35), 1.3, top - 2.0, false)
	# carved bands
	k.mat(K.CARVED, STONE * Color(1.08, 1.08, 1.1), 0.35)
	for y: float in [3.2, 7.0, 10.6]:
		if y < top - 3.0:
			k.extrude(sq.call(1.62, 0.38), y, y + 0.9)
	k.mat(K.GOLD, Color(1, 1, 1), 1.0)
	for y: float in [2.0, 5.2, 9.0]:
		if y < top - 3.0:
			k.extrude(sq.call(1.56, 0.36), y, y + 0.22)
	# capital: corbels stepping out into the vault
	k.mat(K.CARVED, STONE, 0.35)
	k.extrude(sq.call(1.75, 0.4), top - 2.0, top - 1.2)
	k.extrude(sq.call(2.1, 0.45), top - 1.2, top - 0.5)
	k.extrude(sq.call(2.5, 0.5), top - 0.5, top + 0.4)
	k.pop()
	# glowing rune strips on the four faces
	k.mat(K.GLOW, RUNE, 1.0, 2.0)
	for f in 4:
		var yaw := f * PI / 2.0
		k.push(Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO))
		k.push(Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0, 1.52)))
		for j in 3:
			_glyph(k, Vector3(0, 0, -(4.2 + j * 1.15)), 0.75, f * 5 + j + int(at.z))
		k.pop()
		k.pop()
	k.pop()


static func _dais(b: ArenaBuild, k: K, ta: float, frame: Transform3D) -> void:
	for step in 3:
		var hw := 5.5 - step
		var zf := ta - step + 0.5
		var zb := ta - 3.5
		k.mat(K.CARVED, STONE * Color(1.05, 1.05, 1.08), 0.4)
		k.box(Vector3(0, step + 0.5, (zf + zb) * 0.5), Vector3(hw * 2.0, 1.0, zf - zb), 0.05)
		k.mat(K.GOLD, Color(1, 1, 1), 1.0)
		k.box(Vector3(0, step + 1.0, zf), Vector3(hw * 2.0, 0.08, 0.1), 0.01)
	# throne hewn from the mountain
	k.push(Transform3D(Basis.IDENTITY, Vector3(0, 3.0, ta - 2.2)))
	k.mat(K.GRANITE, STONE * Color(0.9, 0.9, 0.95), 0.35)
	k.box(Vector3(0, 0.6, 0.4), Vector3(4.4, 1.2, 2.4), 0.1)
	k.box(Vector3(0, 3.6, -0.6), Vector3(5.0, 7.2, 1.2), 0.12)
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(s * 2.3, 1.4, 0.4), Vector3(0.8, 1.6, 2.6), 0.1)
	k.mat(K.GOLD, Color(1, 1, 1), 1.0)
	k.box(Vector3(0, 7.3, -0.6), Vector3(5.4, 0.3, 1.4), 0.04)
	for i in 5:
		var x := -2.0 + i * 1.0
		k.spike(Vector3(x, 7.4, -0.6), Vector3.UP, 1.0 + (0.8 if i == 2 else 0.0) - absf(x) * 0.15, 0.22, 4, i)
	k.mat(K.GLOW, RUNE, 1.0, 2.2)
	k.push(Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 4.2, 0.02)))
	_glyph(k, Vector3.ZERO, 2.0, 77)
	k.pop()
	k.pop()
	# great rune disc on the end wall behind
	var wall_z := ta - 3.45
	k.push(Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 11.0, wall_z)))
	k.mat(K.CARVED, STONE, 0.35)
	k.lathe(PackedVector2Array([Vector2(4.6, 0.0), Vector2(4.6, 0.3), Vector2(0.0, 0.3)]), 40)
	k.pop()
	k.push(Transform3D(Basis.IDENTITY, Vector3(0, 11.0, wall_z + 0.32)))
	k.push(Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3.ZERO))
	_rune_circle(k, Vector3.ZERO, 4.3)
	k.pop()
	k.pop()
	b.light(frame * Vector3(0, 9.0, wall_z + 3.0), RUNE, 2.6, 16.0, 0, 0.08, 1.0)
	# The kings.
	for s: float in [-1.0, 1.0]:
		P.statue(k, Vector3(s * 8.0, 0, ta - 1.0), 0.0, 13.0, K.TRI + K.GRANITE, STONE * Color(0.95, 0.95, 1.0), true, true)


static func _chandelier(b: ArenaBuild, d: K, at: Vector3, ceiling: float, frame: Transform3D) -> void:
	d.mat(K.IRON, Color(1, 1, 1), 1.0)
	d.push(Transform3D(Basis.IDENTITY, at))
	d.lathe(PackedVector2Array([Vector2(1.9, -0.08), Vector2(2.05, 0.0), Vector2(1.9, 0.08), Vector2(1.75, 0.0)]), 24)
	d.lathe(PackedVector2Array([Vector2(0.9, -0.06), Vector2(1.0, 0.0), Vector2(0.9, 0.06), Vector2(0.8, 0.0)]), 16)
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		d.beam(Vector3(cos(a), 0, sin(a)) * 1.9, Vector3(0, ceiling - at.y, 0), 0.04, 0.04, 0.0)
		d.beam(Vector3(cos(a), 0, sin(a)) * 0.9, Vector3(cos(a), 0, sin(a)) * 1.9, 0.05, 0.05, 0.0)
	d.mat(K.LIMESTONE, Color(0.95, 0.9, 0.78), 1.0)
	for i in 10:
		var a := TAU * i / 10.0
		var p := Vector3(cos(a), 0, sin(a)) * 1.9
		d.push(Transform3D(Basis.IDENTITY, p))
		d.lathe(PackedVector2Array([Vector2(0.06, 0.05), Vector2(0.06, 0.35), Vector2(0.0, 0.37)]), 6)
		d.pop()
		b.flame(frame * (at + p + Vector3(0, 0.38, 0)), 0.32, "candle")
	d.pop()
	b.light(frame * (at + Vector3(0, -0.4, 0)), Color(1.0, 0.7, 0.4), 2.2, 13.0, 0, 0.2, 0.8)


static func _ice_cluster(b: ArenaBuild, d: K, at: Vector3, frame: Transform3D, seed_value: int) -> void:
	d.mat(K.TRI + K.SNOW, Color(0.6, 0.82, 1.0), 0.5, 0.5)
	var n := 4 + seed_value % 4
	for i in n:
		var dir := Vector3(d.rng.randf_range(-0.6, 0.6), 1.0, d.rng.randf_range(-0.6, 0.6)).normalized()
		d.spike(at + Vector3(d.rng.randf_range(-0.6, 0.6), -0.1, d.rng.randf_range(-0.6, 0.6)), dir, d.rng.randf_range(0.8, 2.6), d.rng.randf_range(0.15, 0.32), 6, seed_value * 9 + i)


static func _door(b: ArenaBuild, k: K, hz: float, frame: Transform3D) -> void:
	var dz := hz + 1.0   # door cell centre (one row into the tunnel)
	# frame: massive jambs and a stepped lintel on the hall face
	k.mat(K.CARVED, STONE * Color(1.05, 1.05, 1.08), 0.35)
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(s * 5.6, 4.5, hz - 0.2), Vector3(2.2, 9.0, 0.9), 0.08)
		k.box(Vector3(s * 5.6, 9.4, hz - 0.3), Vector3(2.6, 0.8, 1.1), 0.08)
	k.box(Vector3(0, 9.6, hz - 0.3), Vector3(13.4, 2.2, 1.0), 0.1)
	k.box(Vector3(0, 11.2, hz - 0.3), Vector3(9.0, 1.0, 0.9), 0.1)
	k.mat(K.GLOW, RUNE, 1.0, 2.0)
	for i in 5:
		k.push(Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(-4.0 + i * 2.0, 9.6, hz - 0.82)))
		_glyph(k, Vector3.ZERO, 0.9, 50 + i)
		k.pop()
	# the slab door (gate), carved, in gate space
	var g := K.new(61)
	g.mat(K.GRANITE, STONE * Color(0.85, 0.85, 0.9), 0.35)
	g.box(Vector3(0, 4.15, 0), Vector3(9.1, 8.3, 0.9), 0.08, false)
	g.mat(K.CARVED, STONE, 0.35)
	for s: float in [-1.0, 1.0]:
		g.box(Vector3(0, 4.15, s * 0.5), Vector3(8.2, 7.4, 0.12), 0.04, false)
	g.mat(K.GOLD, Color(1, 1, 1), 1.0)
	for s: float in [-1.0, 1.0]:
		g.box(Vector3(0, 4.15, s * 0.58), Vector3(0.25, 7.4, 0.06), 0.02, false)
		g.box(Vector3(0, 4.15, s * 0.58), Vector3(8.2, 0.25, 0.06), 0.02, false)
	g.mat(K.GLOW, RUNE, 1.0, 2.2)
	for s: float in [-1.0, 1.0]:
		g.push(Transform3D(Basis(Vector3.RIGHT, PI / 2.0) * Basis(Vector3.FORWARD, 0.0), Vector3(0, 4.15, s * 0.62)))
		_rune_circle(g, Vector3.ZERO, 2.4)
		g.pop()
	b.gate(int(b.prop.get("gate", 0)), g, Transform3D(frame.basis, frame * Vector3(0, 0, dz)), "drop", 8.8)


static func _tunnel(b: ArenaBuild, k: K, d: K, hz: float, steps: PackedInt32Array, frame: Transform3D) -> void:
	var n := steps.size()
	for i in n:
		var z0 := hz - 1.0 + i
		var z1 := z0 + 1.0
		var y := float(steps[i])
		if i >= 1:
			k.ao_floor = -INF
			k.mat(K.DARK, SLATE, 0.4)
			k.box(Vector3(0, y - 0.15, (z0 + z1) * 0.5), Vector3(7.0, 0.3, 1.0), 0.04)
			if i + 1 < n and steps[i + 1] != steps[i]:
				var y2 := float(steps[i + 1])
				k.box(Vector3(0, minf(y, y2) + absf(y2 - y) * 0.5, z1), Vector3(7.0, absf(y2 - y), 0.08), 0.0)
			k.ao_floor = y
			# walls and ceiling
			k.mat(K.GRANITE, STONE * Color(0.9, 0.9, 0.95), 0.3)
			for s: float in [-1.0, 1.0]:
				k.pquad(Vector3(s * 3.45, y - 0.3, z0), Vector3(s * 3.45, y - 0.3, z1), Vector3(s * 3.45, y + 6.0, z1), Vector3(s * 3.45, y + 6.0, z0), Vector3(-s, 0, 0))
			k.pquad(Vector3(-3.5, y + 5.95, z0), Vector3(3.5, y + 5.95, z0), Vector3(3.5, y + 5.95, z1), Vector3(-3.5, y + 5.95, z1), Vector3.DOWN)
		if i % 9 == 4:
			# arch frame: pilasters and a chamfered lintel, with a hanging lantern
			k.mat(K.CARVED, STONE * Color(1.05, 1.05, 1.08), 0.35)
			for s: float in [-1.0, 1.0]:
				k.box(Vector3(s * 3.15, y + 2.8, z0 + 0.5), Vector3(0.6, 5.6, 0.9), 0.05)
			k.box(Vector3(0, y + 5.55, z0 + 0.5), Vector3(7.0, 0.8, 1.0), 0.06)
			for s: float in [-1.0, 1.0]:
				k.push(Transform3D(Basis(Vector3(0, 0, 1), s * 0.785), Vector3(s * 2.6, y + 5.0, z0 + 0.5)))
				k.box(Vector3.ZERO, Vector3(0.8, 0.8, 0.95), 0.04)
				k.pop()
			var lp := Vector3(0, y + 4.3, z0 + 0.5)
			d.mat(K.IRON, Color(1, 1, 1), 1.0)
			d.chain(lp + Vector3(0, 1.3, 0), lp + Vector3(0, 0.4, 0), 0.2, 0.03)
			d.push(Transform3D(Basis.IDENTITY, lp))
			d.lathe(PackedVector2Array([Vector2(0.05, -0.2), Vector2(0.25, -0.1), Vector2(0.25, 0.3), Vector2(0.12, 0.42), Vector2(0.03, 0.45)]), 6)
			d.pop()
			b.flame(frame * (lp + Vector3(0, -0.1, 0)), 0.32, "candle")
			b.light(frame * lp, Color(1.0, 0.65, 0.35), 1.8, 10.0, 0, 0.25, 0.6)
	# portal at the mountainside
	var ze := hz - 1.0 + n - 0.5
	var ye := float(steps[n - 1])
	k.mat(K.CARVED, STONE * Color(1.05, 1.05, 1.08), 0.35)
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(s * 4.2, ye + 3.5, ze), Vector3(1.6, 7.0, 1.4), 0.08)
	k.box(Vector3(0, ye + 7.6, ze), Vector3(10.0, 1.4, 1.6), 0.1)
	k.mat(K.GLOW, RUNE, 1.0, 2.0)
	for i in 3:
		k.push(Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(-2.0 + i * 2.0, ye + 7.6, ze + 0.82)))
		_glyph(k, Vector3.ZERO, 0.8, 90 + i)
		k.pop()
