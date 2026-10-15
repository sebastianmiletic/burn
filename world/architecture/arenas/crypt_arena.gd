class_name CryptArena
extends RefCounted
## The Silent Crypt and its depths (Warden): a gothic mausoleum, the stair, a
## vaulted catacomb hall lined with bone niches and sarcophagi, candelabra and
## chains, a sealed iron gate, and the Warden's rib-vaulted tomb chamber.
## Centre-relative coordinates; mirrors Battlegrounds.crypt.

const K := preload("res://world/architecture/arenas/arena_kit.gd")
const P := preload("res://world/architecture/arenas/arena_pieces.gd")

const STONE := Color(0.62, 0.6, 0.56)
const CANDLE := Color(1.0, 0.68, 0.36)
const GHOST := Color(0.45, 1.0, 0.6)


static func hall_vault(x: float, fy: float) -> float:
	return fy + 7.0 + 3.0 * (1.0 - pow(x / 12.5, 2.0)) - 0.1


static func chamber_vault(x: float, fy: float) -> float:
	return fy + 10.0 + 4.0 * (1.0 - pow(x / 11.5, 2.0)) - 0.15


static func build(b: ArenaBuild) -> void:
	var pr := b.prop
	var c := b.center
	var fy := float(pr["fy"])
	b.params = {"moss": 0.45, "grime": 0.55, "grime_color": Color(0.28, 0.27, 0.22), "ambient": 0.3}
	var k := b.shell
	var d := b.detail
	for kit: K in [k, d]:
		kit.push(Transform3D(Basis.IDENTITY, c))
		kit.ao_floor = 0.0
	_mausoleum(b, k, d)
	_stair(b, k, d, fy)
	_hall(b, k, d, fy)
	_gate(b, k, fy)
	_chamber(b, k, d, fy)


# --- Surface -------------------------------------------------------------------------

static func _mausoleum(b: ArenaBuild, k: K, d: K) -> void:
	var wall := STONE * Color(0.95, 0.95, 0.9)
	k.mat(K.MOSSY_WALL, wall, 0.3)
	# platform with steps to the door
	k.box(Vector3(0, -0.2, 0.5), Vector3(15.0, 0.4, 16.0), 0.06)
	for i in 3:
		k.box(Vector3(0, -0.3 - i * 0.3, 8.6 + i * 0.5), Vector3(5.0, 0.3, 0.6), 0.04)
	# walls (door gap in the south wall) and corner buttresses
	k.mat(K.CASTLE, wall, 0.3)
	k.box(Vector3(-6.0, 4.0, 0), Vector3(1.0, 8.0, 13.0), 0.04)
	k.box(Vector3(6.0, 4.0, 0), Vector3(1.0, 8.0, 13.0), 0.04)
	k.box(Vector3(0, 4.0, -6.0), Vector3(11.0, 8.0, 1.0), 0.04)
	k.box(Vector3(-3.75, 4.0, 6.0), Vector3(4.5, 8.0, 1.0), 0.04)
	k.box(Vector3(3.75, 4.0, 6.0), Vector3(4.5, 8.0, 1.0), 0.04)
	k.box(Vector3(0, 6.1, 6.0), Vector3(3.0, 3.8, 1.0), 0.04)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			k.box(Vector3(sx * 6.8, 3.0, sz * 6.8), Vector3(1.2, 6.0, 1.2), 0.06)
			k.push(Transform3D(Basis(Vector3(sz, 0, -sx).normalized(), 0.6), Vector3(sx * 6.8, 6.4, sz * 6.8)))
			k.box(Vector3.ZERO, Vector3(1.0, 1.2, 1.0), 0.05)
			k.pop()
	# pointed portal with an open iron gate
	k.mat(K.CASTLE, wall * Color(1.1, 1.08, 1.05), 0.32)
	k.push(Transform3D(Basis.IDENTITY, Vector3(0, 0, 6.55)))
	k.arch(3.0, 2.6, 0.5, 0.4, 9, 0.35)
	k.pop()
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(s * 1.75, 1.3, 6.55), Vector3(0.5, 2.6, 0.4), 0.04)
	d.mat(K.IRON, Color(1, 1, 1), 1.0)
	d.push(Transform3D(Basis(Vector3.UP, 1.9), Vector3(-1.5, 0, 6.9)))
	for i in 5:
		d.box(Vector3(0.3 + i * 0.3, 1.6, 0), Vector3(0.05, 3.2, 0.05), 0.0, false)
	d.box(Vector3(0.9, 0.5, 0), Vector3(1.5, 0.08, 0.06), 0.0, false)
	d.box(Vector3(0.9, 2.8, 0), Vector3(1.5, 0.08, 0.06), 0.0, false)
	d.pop()
	# steep slate roof with a stone ridge and a finial cross
	k.mat(K.DARK, Color(0.45, 0.48, 0.52), 0.6)
	for s: float in [-1.0, 1.0]:
		k.push(Transform3D(Basis(Vector3(0, 0, 1), -s * 0.785), Vector3(s * 3.4, 11.4, 0)))
		k.box(Vector3.ZERO, Vector3(9.6, 0.3, 14.4), 0.04, false)
		k.pop()
	k.mat(K.CASTLE, wall, 0.3)
	for z: float in [-6.0, 6.0]:
		var gable := PackedVector2Array([Vector2(-6.5, 8.0), Vector2(6.5, 8.0), Vector2(0.0, 14.5)])
		k.push(Transform3D(Basis.IDENTITY, Vector3(0, 0, z)))
		k.extrude(gable, -0.5, 0.5)
		k.pop()
	k.box(Vector3(0, 14.7, 0), Vector3(0.6, 0.5, 14.6), 0.05)
	k.box(Vector3(0, 16.2, 6.3), Vector3(0.3, 2.6, 0.3), 0.03)
	k.box(Vector3(0, 16.8, 6.3), Vector3(1.4, 0.3, 0.3), 0.03)
	# a rose of the dead over the door
	k.push(Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 10.0, 6.55)))
	k.lathe(PackedVector2Array([Vector2(1.0, -0.2), Vector2(1.25, -0.2), Vector2(1.25, 0.15), Vector2(1.0, 0.15)]), 20)
	k.pop()
	k.mat(K.DARK, Color(0.03, 0.03, 0.03), 0.5)
	k.box(Vector3(0, 10.0, 6.5), Vector3(2.0, 2.0, 0.05), 0.0)
	# interior: floor around the stair head, a lantern
	k.mat(K.COBBLE, STONE * Color(0.8, 0.8, 0.78), 0.4)
	k.box(Vector3(-4.0, -0.15, 0), Vector3(3.0, 0.3, 11.0), 0.03)
	k.box(Vector3(4.0, -0.15, 0), Vector3(3.0, 0.3, 11.0), 0.03)
	k.box(Vector3(0, -0.15, 4.5), Vector3(5.0, 0.3, 2.0), 0.03)
	b.light(c_world(b, Vector3(0, 3.0, 3.5)), CANDLE, 1.5, 8.0, 0, 0.3, 0.5)
	b.flame(c_world(b, Vector3(-4.8, 1.0, 4.8)), 0.3, "candle")
	b.flame(c_world(b, Vector3(4.8, 1.0, 4.8)), 0.3, "candle")
	# graves around the mausoleum
	for i in 14:
		var a := k.rng.randf() * TAU
		var r := k.rng.randf_range(9.5, 15.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if p.z > 6.0 and absf(p.x) < 3.5:
			continue
		var yaw := k.rng.randf_range(-0.3, 0.3)
		d.mat(K.MOSSY_WALL if i % 2 else K.CASTLE, STONE * Color(0.9, 0.9, 0.85), 0.5)
		d.push(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, k.rng.randf_range(-0.25, 0.2)), p))
		var h := k.rng.randf_range(0.9, 1.6)
		d.box(Vector3(0, h * 0.5 - 0.2, 0), Vector3(0.8, h, 0.18), 0.04)
		if i % 3 == 0:
			d.push(Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, h - 0.2, 0)))
			d.lathe(PackedVector2Array([Vector2(0.4, -0.09), Vector2(0.4, 0.09), Vector2(0.0, 0.09)]), 10, PI, TAU)
			d.pop()
		d.pop()


static func c_world(b: ArenaBuild, p: Vector3) -> Vector3:
	return b.center + p


static func _stair(b: ArenaBuild, k: K, d: K, fy: float) -> void:
	k.ao_floor = -INF
	for i in 20:
		var z := 3.0 - i
		var y := -float(i)
		k.mat(K.CASTLE, STONE * Color(0.85, 0.85, 0.82), 0.35)
		# two half-steps per 1 m cell
		k.box(Vector3(0, y - 0.2, z + 0.25), Vector3(5.0, 0.4, 0.5), 0.04)
		k.box(Vector3(0, y - 0.7, z - 0.25), Vector3(5.0, 0.4, 0.5), 0.04)
		k.ao_floor = y
		if i >= 3:
			k.mat(K.MOSSY_WALL, STONE * Color(0.8, 0.8, 0.75), 0.3)
			for s: float in [-1.0, 1.0]:
				k.pquad(Vector3(s * 2.45, y - 1.0, z - 0.5), Vector3(s * 2.45, y - 1.0, z + 0.5), Vector3(s * 2.45, y + 5.0, z + 0.5), Vector3(s * 2.45, y + 5.0, z - 0.5), Vector3(-s, 0, 0))
			k.pquad(Vector3(-2.5, y + 4.95, z - 0.5), Vector3(2.5, y + 4.95, z - 0.5), Vector3(2.5, y + 4.95, z + 0.5), Vector3(-2.5, y + 4.95, z + 0.5), Vector3.DOWN)
		if i % 5 == 3:
			k.mat(K.CASTLE, STONE, 0.3)
			for s: float in [-1.0, 1.0]:
				k.box(Vector3(s * 2.25, y + 2.0, z), Vector3(0.5, 5.0, 0.7), 0.04)
			k.box(Vector3(0, y + 4.7, z), Vector3(5.0, 0.6, 0.7), 0.04)
			P.sconce(b, d, Vector3(-2.45, y + 2.4, z - 1.0), Vector3(1, 0, 0), c_world(b, Vector3(-2.45, y + 2.4, z - 1.0)), "fire", CANDLE, 1.4)
	k.ao_floor = 0.0


static func _hall(b: ArenaBuild, k: K, d: K, fy: float) -> void:
	var hz := b.prop["hall"] as Array
	var z0 := float(hz[0]) - 0.5
	var z1 := float(hz[1]) + 0.5
	var hx := 12.45
	# floor: worn flagstones with an aisle
	k.ao_floor = -INF
	k.mat(K.COBBLE, STONE * Color(0.78, 0.76, 0.72), 0.4)
	k.flagstones(-hx, z0, hx, z1, fy, 1.2, 0.04, 0.3, 0.04)
	k.ao_floor = fy
	# end walls (doorways to the stair and the gate passage)
	_end_wall(k, z1 - 0.05, -1.0, fy, hx, 2.5, 5.0, func(x: float) -> float: return hall_vault(x, fy))
	_end_wall(k, z0 + 0.05, 1.0, fy, hx, 2.5, 6.0, func(x: float) -> float: return hall_vault(x, fy))
	# side walls with bone niches (two tiers every 2 m)
	var niche_z := {}
	for n: Vector3 in b.prop["niches"]:
		niche_z[Vector2i(int(n.x), int(n.z))] = true
	var spring := hall_vault(hx, fy)
	for side: float in [-1.0, 1.0]:
		var x := side * hx
		var z := z0
		while z < z1 - 0.01:
			var zc := z + 0.5
			var is_niche := niche_z.has(Vector2i(int(side * 13), int(round(zc))))
			k.mat(K.MOSSY_WALL, STONE * Color(0.85, 0.85, 0.8), 0.3)
			if is_niche:
				# wall around two niche openings (y fy+1..fy+2 and fy+3..fy+4 open, 0.9 wide)
				for band: Array in [[fy, fy + 1.05], [fy + 1.95, fy + 3.05], [fy + 3.95, spring]]:
					k.pquad(Vector3(x, band[0], z), Vector3(x, band[0], z + 1.0), Vector3(x, band[1], z + 1.0), Vector3(x, band[1], z), Vector3(-side, 0, 0))
				for y0: float in [fy + 1.05, fy + 3.05]:
					_niche(k, d, Vector3(x, y0, zc), side)
			else:
				k.pquad(Vector3(x, fy, z), Vector3(x, fy, z + 1.0), Vector3(x, spring, z + 1.0), Vector3(x, spring, z), Vector3(-side, 0, 0))
			z += 1.0
		# plinth and the string course under the vault
		k.mat(K.CASTLE, STONE * Color(0.8, 0.8, 0.76), 0.3)
		k.moulding(Vector3(x, fy, z1), Vector3(x, fy, z0), Vector3(-side, 0, 0), PackedVector2Array([Vector2(0.35, 0.0), Vector2(0.35, 0.5), Vector2(0.0, 0.7)]))
		k.moulding(Vector3(x, fy, z1), Vector3(x, fy, z0), Vector3(-side, 0, 0), PackedVector2Array([Vector2(0.0, spring - fy - 0.5), Vector2(0.3, spring - fy - 0.3), Vector2(0.3, spring - fy)]))
	# barrel vault with transverse ribs
	_vault(k, -hx, hx, z0, z1, func(x: float) -> float: return hall_vault(x, fy), STONE * Color(0.78, 0.78, 0.74))
	var zr := z0 + 2.5
	while zr < z1 - 1.0:
		_rib(k, -hx, hx, zr, func(x: float) -> float: return hall_vault(x, fy))
		zr += 5.0
	# sarcophagi
	for s: Vector3 in b.prop["sarcophagi"]:
		_sarcophagus(k, d, Vector3(s.x, fy, s.z), int(s.z * 3.0 + s.x), false)
	# candelabra between them and chains from the vault
	for row: float in [-7.0, 7.0]:
		var z := z0 + 6.5
		while z < z1 - 3.0:
			_candelabrum(b, d, Vector3(row * 0.55, fy, z), 2.3)
			z += 10.0
	d.mat(K.IRON, Color(1, 1, 1), 1.0)
	for i in 6:
		var x := d.rng.randf_range(-9.0, 9.0)
		var z := d.rng.randf_range(z0 + 2.0, z1 - 2.0)
		var top := hall_vault(x, fy)
		d.chain(Vector3(x, top, z), Vector3(x + d.rng.randf_range(-0.3, 0.3), top - d.rng.randf_range(2.0, 4.0), z), 0.28, 0.035)


## Wall across the hall at z (facing `nz`) with a centred doorway of half-width w and height h.
static func _end_wall(k: K, z: float, nz: float, fy: float, hx: float, w: float, h: float, vault: Callable) -> void:
	k.mat(K.MOSSY_WALL, STONE * Color(0.85, 0.85, 0.8), 0.3)
	var poly := PackedVector2Array([Vector2(-hx, fy), Vector2(-w, fy), Vector2(-w, fy + h - 1.0)])
	for i in 7:
		var t := float(i) / 6.0
		poly.append(Vector2(lerpf(-w, w, t), fy + h - 1.0 + sin(t * PI) * 1.0))
	poly.append(Vector2(w, fy))
	poly.append(Vector2(hx, fy))
	for i in 17:
		var x := lerpf(hx, -hx, float(i) / 16.0)
		poly.append(Vector2(x, float(vault.call(x))))
	k.push(Transform3D(Basis.IDENTITY, Vector3(0, 0, z)))
	k.extrude(poly, -0.25 if nz > 0.0 else 0.0, 0.0 if nz > 0.0 else 0.25, true)
	k.pop()
	k.mat(K.CASTLE, STONE * Color(1.0, 0.98, 0.94), 0.32)
	k.push(Transform3D(Basis.IDENTITY, Vector3(0, 0, z + nz * 0.15)))
	k.arch(w * 2.0, fy + h - 1.0, 0.5, 0.35, 9)
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(s * (w + 0.25), fy + (h - 1.0) * 0.5, 0), Vector3(0.5, h - 1.0, 0.35), 0.04)
	k.pop()


static func _vault(k: K, x0: float, x1: float, z0: float, z1: float, vault: Callable, tint: Color) -> void:
	k.mat(K.CASTLE, tint, 0.3)
	var n := 22
	for i in n:
		var xa := lerpf(x0, x1, float(i) / n)
		var xb := lerpf(x0, x1, float(i + 1) / n)
		var ya := float(vault.call(xa))
		var yb := float(vault.call(xb))
		var na := Vector3((float(vault.call(xa + 0.05)) - float(vault.call(xa - 0.05))) / 0.1, -1.0, 0).normalized()
		var nb := Vector3((float(vault.call(xb + 0.05)) - float(vault.call(xb - 0.05))) / 0.1, -1.0, 0).normalized()
		var arc_a := xa
		var arc_b := xb
		var i0 := k._v(Vector3(xa, ya, z0), na, Vector2(arc_a, z0))
		var i1 := k._v(Vector3(xb, yb, z0), nb, Vector2(arc_b, z0))
		var i2 := k._v(Vector3(xb, yb, z1), nb, Vector2(arc_b, z1))
		var i3 := k._v(Vector3(xa, ya, z1), na, Vector2(arc_a, z1))
		k._t(i0, i1, i2)
		k._t(i0, i2, i3)


static func _rib(k: K, x0: float, x1: float, z: float, vault: Callable) -> void:
	k.mat(K.CASTLE, STONE * Color(0.95, 0.94, 0.9), 0.32)
	var n := 16
	var prev := Vector3(x0, float(vault.call(x0)) - 0.2, z)
	for i in range(1, n + 1):
		var x := lerpf(x0, x1, float(i) / n)
		var p := Vector3(x, float(vault.call(x)) - 0.2, z)
		k.beam(prev, p, 0.55, 0.45, 0.05, Vector3(0, 0, 1))
		prev = p


## A bone niche: dark recess with dressed reveals, a skull and long bones.
static func _niche(k: K, d: K, at: Vector3, side: float) -> void:
	var x := at.x
	k.mat(K.DARK, Color(0.06, 0.055, 0.05), 0.5)
	k.pquad(Vector3(x + side * 0.95, at.y, at.z - 0.45), Vector3(x + side * 0.95, at.y, at.z + 0.45), Vector3(x + side * 0.95, at.y + 0.9, at.z + 0.45), Vector3(x + side * 0.95, at.y + 0.9, at.z - 0.45), Vector3(-side, 0, 0))
	k.mat(K.CASTLE, STONE * Color(0.7, 0.68, 0.64), 0.4)
	k.pquad(Vector3(x, at.y, at.z - 0.45), Vector3(x + side, at.y, at.z - 0.45), Vector3(x + side, at.y, at.z + 0.45), Vector3(x, at.y, at.z + 0.45), Vector3.UP)
	k.pquad(Vector3(x, at.y + 0.9, at.z - 0.45), Vector3(x + side, at.y + 0.9, at.z - 0.45), Vector3(x + side, at.y + 0.9, at.z + 0.45), Vector3(x, at.y + 0.9, at.z + 0.45), Vector3.DOWN)
	for s: float in [-1.0, 1.0]:
		k.pquad(Vector3(x, at.y, at.z + s * 0.45), Vector3(x + side, at.y, at.z + s * 0.45), Vector3(x + side, at.y + 0.9, at.z + s * 0.45), Vector3(x, at.y + 0.9, at.z + s * 0.45), Vector3(0, 0, -s))
	# frame
	k.mat(K.CASTLE, STONE, 0.32)
	k.box(Vector3(x - side * 0.04, at.y - 0.06, at.z), Vector3(0.12, 0.12, 1.05), 0.02)
	d.mat(K.BONE, Color(0.86, 0.82, 0.72), 0.7)
	var h := int(absf(at.z * 7.0 + at.y * 3.0)) % 5
	if h != 0:
		d.rock(Vector3(x + side * 0.5, at.y + 0.17, at.z + (0.15 if h % 2 else -0.12)), Vector3(0.15, 0.17, 0.18), 0.08, 2, h)
		d.mat(K.DARK, Color(0.02, 0.02, 0.02), 0.5)
		for s: float in [-1.0, 1.0]:
			d.rock(Vector3(x + side * 0.37, at.y + 0.2, at.z + (0.15 if h % 2 else -0.12) + s * 0.06), Vector3(0.04, 0.045, 0.03), 0.0, 1, 3)
		d.mat(K.BONE, Color(0.86, 0.82, 0.72), 0.7)
	for j in 2 + h % 2:
		var zz := at.z + (float(j) - 0.5) * 0.18
		d.sweep(PackedVector3Array([Vector3(x + side * 0.2, at.y + 0.06 + j * 0.05, zz), Vector3(x + side * 0.85, at.y + 0.06 + j * 0.05, zz + 0.05)]), PackedFloat32Array([0.04, 0.035]), 5)


static func _sarcophagus(k: K, d: K, at: Vector3, seed_value: int, grand: bool) -> void:
	var s := 1.4 if grand else 1.0
	k.push(Transform3D(Basis.IDENTITY, at))
	k.mat(K.CASTLE, STONE * Color(0.85, 0.84, 0.8), 0.35)
	k.box(Vector3(0, 0.12, 0), Vector3(2.6 * s, 0.24, 3.0 * s), 0.05)
	k.mat(K.MARBLE, Color(0.62, 0.6, 0.56), 0.35)
	k.box(Vector3(0, 0.62, 0), Vector3(1.4 * s, 0.8, 2.5 * s), 0.05)
	k.mat(K.CASTLE, STONE * Color(0.92, 0.9, 0.85), 0.35)
	for side: float in [-1.0, 1.0]:
		for j in 3:
			k.box(Vector3(side * 0.72 * s, 0.62, (j - 1) * 0.75 * s), Vector3(0.06, 0.55, 0.4 * s), 0.02)
	var open := seed_value % 3 == 0 or grand
	if open:
		# lid slid aside, bones within
		k.mat(K.MARBLE, Color(0.6, 0.58, 0.54), 0.35)
		k.push(Transform3D(Basis(Vector3.UP, 0.35) * Basis(Vector3(0, 0, 1), 0.12), Vector3(0.65 * s, 1.08, 0.2 * s)))
		k.box(Vector3.ZERO, Vector3(1.6 * s, 0.18, 2.7 * s), 0.05, false)
		k.pop()
		k.mat(K.DARK, Color(0.03, 0.03, 0.03), 0.5)
		k.box(Vector3(0, 1.0, 0), Vector3(1.15 * s, 0.05, 2.25 * s), 0.0)
		d.mat(K.BONE, Color(0.85, 0.8, 0.7), 0.7)
		d.rock(at + Vector3(-0.15, 1.08, -0.85 * s), Vector3(0.16, 0.18, 0.19), 0.08, 2, seed_value)
	else:
		# carved effigy on the lid
		k.mat(K.MARBLE, Color(0.62, 0.6, 0.56), 0.35)
		k.box(Vector3(0, 1.1, 0), Vector3(1.55 * s, 0.2, 2.65 * s), 0.05)
		k.mat(K.TRI + K.MARBLE, Color(0.66, 0.64, 0.6), 0.6)
		k.rock(Vector3(0, 1.32, 0.1 * s), Vector3(0.38 * s, 0.17 * s, 0.85 * s), 0.08, 2, seed_value)
		k.rock(Vector3(0, 1.36, -0.95 * s), Vector3(0.17 * s, 0.17 * s, 0.19 * s), 0.05, 2, seed_value + 1)
		k.box(Vector3(0, 1.48, 0.3 * s), Vector3(0.08, 0.06, 1.3 * s), 0.01)
		k.box(Vector3(0, 1.5, -0.25 * s), Vector3(0.45 * s, 0.06, 0.08), 0.01)
	k.pop()


static func _candelabrum(b: ArenaBuild, d: K, at: Vector3, h: float) -> void:
	d.mat(K.IRON, Color(1, 1, 1), 1.0)
	d.push(Transform3D(Basis.IDENTITY, at))
	for i in 3:
		var a := TAU * i / 3.0
		d.sweep(PackedVector3Array([Vector3(cos(a) * 0.45, 0.0, sin(a) * 0.45), Vector3(cos(a) * 0.2, 0.25, sin(a) * 0.2), Vector3(0, 0.45, 0)]), PackedFloat32Array([0.03, 0.035, 0.04]), 5)
	d.sweep(PackedVector3Array([Vector3(0, 0.4, 0), Vector3(0, h, 0)]), PackedFloat32Array([0.04, 0.03]), 6)
	var arms := [Vector3(0, h + 0.1, 0)]
	for i in 4:
		var a := TAU * i / 4.0
		var tip := Vector3(cos(a) * 0.45, h - 0.05, sin(a) * 0.45)
		d.sweep(PackedVector3Array([Vector3(0, h - 0.3, 0), Vector3(cos(a) * 0.3, h - 0.32, sin(a) * 0.3), tip]), PackedFloat32Array([0.022, 0.022, 0.022]), 4)
		arms.append(tip)
	for tip: Vector3 in arms:
		d.mat(K.IRON, Color(1, 1, 1), 1.0)
		d.lathe(PackedVector2Array([Vector2(0.02, tip.y - 0.02), Vector2(0.08, tip.y + 0.02), Vector2(0.08, tip.y + 0.04)]), 6)
		d.mat(K.LIMESTONE, Color(0.95, 0.9, 0.76), 1.0)
		d.push(Transform3D(Basis.IDENTITY, Vector3(tip.x, 0, tip.z)))
		var ch := 0.18 + absf(sin(tip.x * 9.0 + tip.z * 5.0)) * 0.18
		d.lathe(PackedVector2Array([Vector2(0.045, tip.y + 0.03), Vector2(0.045, tip.y + 0.03 + ch), Vector2(0.0, tip.y + 0.05 + ch)]), 6)
		d.pop()
		b.flame(b.center + at + Vector3(tip.x, tip.y + 0.06 + ch, tip.z), 0.22, "candle")
	d.pop()
	b.light(b.center + at + Vector3(0, h + 0.5, 0), CANDLE, 2.2, 10.0, 0, 0.3, 0.6)


static func _gate(b: ArenaBuild, k: K, fy: float) -> void:
	var z := -45.0
	# passage walls and ceiling
	k.mat(K.MOSSY_WALL, STONE * Color(0.85, 0.85, 0.8), 0.3)
	for s: float in [-1.0, 1.0]:
		k.pquad(Vector3(s * 2.45, fy, -46.5), Vector3(s * 2.45, fy, -42.5), Vector3(s * 2.45, fy + 6.0, -42.5), Vector3(s * 2.45, fy + 6.0, -46.5), Vector3(-s, 0, 0))
	k.pquad(Vector3(-2.5, fy + 5.95, -46.5), Vector3(2.5, fy + 5.95, -46.5), Vector3(2.5, fy + 5.95, -42.5), Vector3(-2.5, fy + 5.95, -42.5), Vector3.DOWN)
	k.mat(K.COBBLE, STONE * Color(0.78, 0.76, 0.72), 0.4)
	k.ao_floor = -INF
	k.flagstones(-2.5, -46.5, 2.5, -42.5, fy, 1.0, 0.04, 0.3)
	k.ao_floor = fy
	k.mat(K.DARK, Color(0.03, 0.03, 0.03), 0.5)
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(s * 2.42, fy + 3.0, z), Vector3(0.08, 6.0, 0.3), 0.0)
	# a skull keystone over the gate
	k.mat(K.BONE, Color(0.8, 0.76, 0.66), 0.7)
	k.rock(Vector3(0, fy + 5.55, -42.35), Vector3(0.35, 0.4, 0.25), 0.1, 2, 5)
	# the gate: wrought iron with spear-point finials
	var g := K.new(45)
	g.mat(K.IRON, Color(1, 1, 1), 1.0)
	var w := 5.0
	var h := 6.1
	for i in 13:
		var x := -w * 0.5 + w * float(i) / 12.0
		g.box(Vector3(x, h * 0.5, 0), Vector3(0.07, h, 0.07), 0.01, false)
		g.spike(Vector3(x, h, 0), Vector3.UP, 0.3, 0.06, 4, i)
		g.spike(Vector3(x, 0.05, 0), Vector3.DOWN, 0.25, 0.05, 4, i)
	for y: float in [0.5, 2.2, 4.0, 5.6]:
		g.box(Vector3(0, y, 0), Vector3(w + 0.1, 0.1, 0.12), 0.02, false)
	for i in 6:
		var x := -w * 0.5 + w * (float(i) + 0.5) / 6.0
		g.push(Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(x, 3.1, 0)))
		g.lathe(PackedVector2Array([Vector2(0.28, -0.03), Vector2(0.33, -0.03), Vector2(0.33, 0.03), Vector2(0.28, 0.03)]), 12)
		g.pop()
	b.gate(int(b.prop.get("gate", 0)), g, Transform3D(Basis.IDENTITY, b.center + Vector3(0, fy, z)), "drop", 6.2)


static func _chamber(b: ArenaBuild, k: K, d: K, fy: float) -> void:
	var cz := b.prop["chamber"] as Array
	var z0 := float(cz[0]) - 0.5
	var z1 := float(cz[1]) + 0.5
	var hx := 11.45
	var vault := func(x: float) -> float: return chamber_vault(x, fy)
	k.ao_floor = -INF
	k.mat(K.MARBLE, Color(0.48, 0.47, 0.45), 0.35)
	k.flagstones(-hx, z0, hx, z1, fy, 1.5, 0.04, 0.3, 0.03)
	k.mat(K.MARBLE, Color(0.25, 0.24, 0.24), 0.35)
	k.flagstones(-2.0, z0 + 5.0, 2.0, z1, fy + 0.005, 1.0, 0.03, 0.3)
	k.ao_floor = fy
	_end_wall(k, z1 - 0.05, -1.0, fy, hx, 2.5, 6.0, vault)
	# far wall: solid with a carved relief of a knight
	k.mat(K.MOSSY_WALL, STONE * Color(0.85, 0.85, 0.8), 0.3)
	var poly := PackedVector2Array([Vector2(-hx, fy), Vector2(hx, fy)])
	for i in 17:
		var x := lerpf(hx, -hx, float(i) / 16.0)
		poly.append(Vector2(x, float(vault.call(x))))
	k.push(Transform3D(Basis.IDENTITY, Vector3(0, 0, z0 + 0.05)))
	k.extrude(poly, -0.25, 0.0, true)
	k.pop()
	P.statue(k, Vector3(0, fy + 2.0, z0 + 1.6), 0.0, 9.0, K.TRI + K.MARBLE, Color(0.55, 0.54, 0.5), false, false)
	for side: float in [-1.0, 1.0]:
		var x := side * hx
		k.mat(K.MOSSY_WALL, STONE * Color(0.85, 0.85, 0.8), 0.3)
		var spring := float(vault.call(hx))
		k.pquad(Vector3(x, fy, z0), Vector3(x, fy, z1), Vector3(x, spring, z1), Vector3(x, spring, z0), Vector3(-side, 0, 0))
		k.mat(K.CASTLE, STONE * Color(0.8, 0.8, 0.76), 0.3)
		k.moulding(Vector3(x, fy, z1), Vector3(x, fy, z0), Vector3(-side, 0, 0), PackedVector2Array([Vector2(0.4, 0.0), Vector2(0.4, 0.6), Vector2(0.0, 0.8)]))
		# blind lancet arcades on the walls
		var z := z0 + 2.0
		while z < z1 - 1.5:
			k.mat(K.CASTLE, STONE, 0.32)
			k.box(Vector3(x - side * 0.2, fy + 3.0, z), Vector3(0.4, 6.0, 0.5), 0.04)
			k.push(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(x - side * 0.2, 0, z + 1.5)))
			k.arch(2.6, fy + 6.0, 0.4, 0.4, 7, 0.4)
			k.pop()
			k.mat(K.DARK, Color(0.08, 0.075, 0.07), 0.5)
			k.pquad(Vector3(x - side * 0.02, fy + 0.8, z + 0.3), Vector3(x - side * 0.02, fy + 0.8, z + 2.7), Vector3(x - side * 0.02, fy + 6.2, z + 2.7), Vector3(x - side * 0.02, fy + 6.2, z + 0.3), Vector3(-side, 0, 0))
			z += 3.0
	_vault(k, -hx, hx, z0, z1, vault, STONE * Color(0.78, 0.78, 0.74))
	# piers with ribs springing across the bays
	var piers: Array = b.prop["piers"]
	for p: Vector3 in piers:
		_pier(k, Vector3(p.x, fy, p.z), float(vault.call(p.x)))
	for zz: float in [-54.0, -62.0, -70.0]:
		_rib(k, -hx, hx, zz, vault)
	k.mat(K.CASTLE, STONE * Color(0.95, 0.94, 0.9), 0.32)
	for i in 3:
		var za := -54.0 - i * 8.0
		var zb := za - 8.0 if i < 2 else z0
		for s: float in [-1.0, 1.0]:
			# diagonal ribs across each bay
			var a := Vector3(s * 6.0, float(vault.call(s * 6.0)) - 0.25, za)
			var e := Vector3(-s * 6.0, float(vault.call(-s * 6.0)) - 0.25, zb)
			var mid := Vector3(0, float(vault.call(0.0)) - 0.25, (za + zb) * 0.5)
			var path := K.bezier(a, mid + Vector3(0, 0.4, 0), e, 10)
			var prev := path[0]
			for j in range(1, path.size()):
				k.beam(prev, path[j], 0.4, 0.35, 0.04, Vector3(0, 1, 0))
				prev = path[j]
	# boss of the vault: hanging chandelier ring of candles
	_ring_chandelier(b, d, Vector3(0, fy + 8.0, -62.0), float(vault.call(0.0)))
	# the Warden's tomb on its dais
	k.mat(K.MARBLE, Color(0.4, 0.39, 0.37), 0.35)
	k.box(Vector3(0, fy + 0.5, -75.0), Vector3(9.0, 1.0, 5.0), 0.05)
	k.box(Vector3(0, fy + 1.5, -75.0), Vector3(5.0, 1.0, 3.0), 0.05)
	k.mat(K.GOLD, Color(1, 1, 1), 1.0)
	k.box(Vector3(0, fy + 1.0, -72.52), Vector3(9.0, 0.06, 0.06), 0.01)
	_sarcophagus(k, d, Vector3(0, fy + 2.0, -75.0), 3, true)
	for s: float in [-1.0, 1.0]:
		P.fire_basin(b, k, Vector3(s * 6.5, fy, -73.5), b.center + Vector3(s * 6.5, fy, -73.5), 0.85, "green", K.MARBLE, GHOST, 1)
		_candelabrum(b, d, Vector3(s * 3.4, fy + 1.0, -72.4), 1.6)
	# chains and cages from the vault
	d.mat(K.IRON, Color(1, 1, 1), 1.0)
	for i in 5:
		var x := d.rng.randf_range(-8.0, 8.0)
		var z := d.rng.randf_range(-74.0, -50.0)
		var top := float(vault.call(x))
		var low := top - d.rng.randf_range(3.0, 6.0)
		d.chain(Vector3(x, top, z), Vector3(x, low, z), 0.3, 0.04)
		if i % 2 == 0:
			_cage(d, Vector3(x, low, z))
	# bones scattered on the chamber floor
	for i in 6:
		var p := Vector3(d.rng.randf_range(-9.0, 9.0), fy, d.rng.randf_range(-70.0, -50.0))
		TartarusArena._bones(d, p, i + 20)


static func _pier(k: K, at: Vector3, top: float) -> void:
	k.push(Transform3D(Basis.IDENTITY, at))
	k.mat(K.CASTLE, STONE * Color(0.9, 0.9, 0.86), 0.32)
	k.box(Vector3(0, 0.4, 0), Vector3(3.1, 0.8, 3.1), 0.06)
	k.box(Vector3(0, top * 0.0 + (top - at.y) * 0.5, 0), Vector3(1.9, top - at.y, 1.9), 0.08)
	k.mat(K.MARBLE, STONE * Color(0.85, 0.85, 0.82), 0.3)
	for i in 4:
		var a := TAU * i / 4.0
		var p := Vector3(cos(a), 0, sin(a)) * 1.05
		k.push(Transform3D(Basis.IDENTITY, p))
		k.lathe(PackedVector2Array([Vector2(0.4, 0.8), Vector2(0.4, top - at.y - 1.6), Vector2(0.55, top - at.y - 1.3), Vector2(0.5, top - at.y - 1.0)]), 10)
		k.pop()
	k.mat(K.CASTLE, STONE, 0.32)
	k.box(Vector3(0, top - at.y - 1.0, 0), Vector3(3.0, 0.5, 3.0), 0.06)
	k.pop()


static func _ring_chandelier(b: ArenaBuild, d: K, at: Vector3, ceiling: float) -> void:
	d.mat(K.IRON, Color(1, 1, 1), 1.0)
	d.push(Transform3D(Basis.IDENTITY, at))
	d.lathe(PackedVector2Array([Vector2(1.6, -0.07), Vector2(1.72, 0.0), Vector2(1.6, 0.07), Vector2(1.48, 0.0)]), 24)
	for i in 3:
		var a := TAU * i / 3.0
		d.beam(Vector3(cos(a), 0, sin(a)) * 1.6, Vector3(0, ceiling - at.y - 2.0, 0), 0.04, 0.04, 0.0)
	d.chain(Vector3(0, ceiling - at.y - 2.0, 0), Vector3(0, ceiling - at.y, 0), 0.3, 0.04)
	d.mat(K.LIMESTONE, Color(0.95, 0.9, 0.76), 1.0)
	for i in 12:
		var a := TAU * i / 12.0
		var p := Vector3(cos(a), 0, sin(a)) * 1.6
		d.push(Transform3D(Basis.IDENTITY, p))
		d.lathe(PackedVector2Array([Vector2(0.05, 0.05), Vector2(0.05, 0.3), Vector2(0.0, 0.32)]), 6)
		d.pop()
		b.flame(b.center + at + p + Vector3(0, 0.34, 0), 0.24, "candle")
	d.pop()
	b.light(b.center + at + Vector3(0, -0.5, 0), CANDLE, 2.6, 15.0, 2, 0.2, 0.8)


static func _cage(d: K, at: Vector3) -> void:
	d.mat(K.IRON, Color(1, 1, 1), 1.0)
	d.push(Transform3D(Basis.IDENTITY, at - Vector3(0, 1.6, 0)))
	for i in 8:
		var a := TAU * i / 8.0
		var p := Vector3(cos(a), 0, sin(a)) * 0.55
		d.sweep(PackedVector3Array([p, p * 1.05 + Vector3(0, 0.8, 0), p * 0.3 + Vector3(0, 1.55, 0)]), PackedFloat32Array([0.025, 0.025, 0.025]), 4)
	d.lathe(PackedVector2Array([Vector2(0.55, -0.03), Vector2(0.58, 0.0), Vector2(0.55, 0.03), Vector2(0.52, 0.0)]), 12)
	d.mat(K.BONE, Color(0.84, 0.8, 0.7), 0.7)
	d.rock(Vector3(0.1, 0.18, 0.0), Vector3(0.15, 0.17, 0.18), 0.08, 2, 9)
	d.pop()
