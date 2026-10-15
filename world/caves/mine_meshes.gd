class_name MineMeshes
extends RefCounted
## Template meshes for abandoned mine props (MineDressing). Wooden parts are
## unit-length members along +Y (instances scale them to size; the wood shader
## reads the instance scale so the grain stays in metres).

const B := CaveMeshes.Builder


static func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


## Hewn timber: chamfered square section (1 x 1 before scaling), y 0..1, adze facets.
## broken: the top end is snapped into splinters.
static func beam(broken := false) -> ArrayMesh:
	var b := B.new()
	var rng := _rng(3001 if broken else 3000)
	var section: Array[Vector2] = []
	var ch := 0.13
	for c: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]:
		section.append(Vector2(c.x * 0.5, c.y * (0.5 - ch)))
		section.append(Vector2(c.x * (0.5 - ch), c.y * 0.5))
	# Order the outline around the centre.
	section.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.angle() < q.angle())
	var rings := 9
	var rows: Array = []
	for i in rings:
		var t := float(i) / (rings - 1)
		var row := PackedInt32Array()
		for k in section.size():
			var s := section[k]
			var facet := CaveMeshes.n3(Vector3(s.x * 3.0, t * 6.0, s.y * 3.0), 3.0) * 0.025
			var y := t
			if broken and i == rings - 1:
				y = t - rng.randf_range(0.0, 0.35)
			var p := Vector3(s.x * (1.0 + facet), y, s.y * (1.0 + facet))
			row.append(b.vert(p, Color(0.0, 0.0, rng.randf(), 1.0), Vector2(float(k) / section.size(), t)))
		rows.append(row)
	var n := section.size()
	for i in rings - 1:
		var r0: PackedInt32Array = rows[i]
		var r1: PackedInt32Array = rows[i + 1]
		for k in n:
			var k1 := (k + 1) % n
			var mid := (section[k] + section[k1]) * 0.5
			b.quad(r0[k], r0[k1], r1[k1], r1[k], Vector3(mid.x, 0, mid.y))
	# End grain caps (g = 1).
	for end in [0, rings - 1]:
		var row: PackedInt32Array = rows[end]
		var cy := 0.0 if end == 0 else (1.0 - (0.18 if broken else 0.0))
		var centre := b.vert(Vector3(0, cy, 0), Color(0, 1, 0.5, 0.9))
		var out := Vector3.DOWN if end == 0 else Vector3.UP
		for k in n:
			var ci := b.vert(b.v[row[k]], Color(0, 1, 0.5, 0.9))
			var cj := b.vert(b.v[row[(k + 1) % n]], Color(0, 1, 0.5, 0.9))
			b.tri(centre, ci, cj, out)
	return b.commit()


## Round rod (rungs, handles, axles, rope): radius 0.5, y 0..1.
static func rod() -> ArrayMesh:
	var b := B.new()
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in 3:
		pts.append(Vector3(0, i * 0.5, 0))
		radii.append(0.5)
		cols.append(Color(0, 0, 0.5, 1))
	CaveMeshes.tube(b, pts, radii, cols, 8, 0.0, 1.0, 0.0, true, true)
	return b.commit()


## Steel rail with a flat-bottom I profile, 1 m long along +Z. Head top at y = 0.11.
static func rail() -> ArrayMesh:
	var b := B.new()
	var prof: Array[Vector2] = [Vector2(-0.055, 0.0), Vector2(0.055, 0.0), Vector2(0.055, 0.012), Vector2(0.012, 0.025),
		Vector2(0.009, 0.075), Vector2(0.03, 0.085), Vector2(0.032, 0.11), Vector2(-0.032, 0.11), Vector2(-0.03, 0.085),
		Vector2(-0.009, 0.075), Vector2(-0.012, 0.025), Vector2(-0.055, 0.012)]
	var n := prof.size()
	for k in n:
		var a := prof[k]
		var c := prof[(k + 1) % n]
		var nrm := Vector2(c.y - a.y, -(c.x - a.x))
		var top := 1.0 if (a.y > 0.1 and c.y > 0.1) else 0.0
		var col := Color(top, 0, 0.5, 1)
		var i0 := b.vert(Vector3(a.x, a.y, 0), col)
		var i1 := b.vert(Vector3(c.x, c.y, 0), col)
		var i2 := b.vert(Vector3(c.x, c.y, 1), col)
		var i3 := b.vert(Vector3(a.x, a.y, 1), col)
		b.quad(i0, i1, i2, i3, Vector3(nrm.x, nrm.y, 0) if nrm.dot(a + c) >= 0.0 else -Vector3(nrm.x, nrm.y, 0))
	return b.commit()


## A chamfered board as a closed box of 8 noisy corners (crate planks, signs).
static func _board(b: CaveMeshes.Builder, c: Vector3, half: Vector3, basis: Basis, col: Color, rng: RandomNumberGenerator) -> void:
	var corners: Array[Vector3] = []
	for k in 8:
		var s := Vector3(1 if k & 1 else -1, 1 if k & 2 else -1, 1 if k & 4 else -1)
		var p := Vector3(s.x * half.x, s.y * half.y, s.z * half.z) * rng.randf_range(0.97, 1.0)
		corners.append(c + basis * p)
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	for f: Array in faces:
		var a: Vector3 = corners[f[0]]
		var bb: Vector3 = corners[f[1]]
		var cc: Vector3 = corners[f[2]]
		var d: Vector3 = corners[f[3]]
		var out := (a + bb + cc + d) * 0.25 - c
		b.flat_tri(a, bb, cc, out, col, col, col)
		b.flat_tri(a, cc, d, out, col, col, col)


## Plank crate, 1 m cube on the floor (y 0..1).
static func crate() -> ArrayMesh:
	var b := B.new()
	var rng := _rng(3101)
	var wood := Color(0, 0, 0.5, 1)
	for face in 6:
		var axis := face / 2
		var sgn := 1.0 if face % 2 == 0 else -1.0
		for k in 4:
			var off := -0.36 + k * 0.24
			var c := Vector3(0, 0.5, 0)
			var half := Vector3.ZERO
			match axis:
				0:
					c += Vector3(sgn * 0.48, off, 0)
					half = Vector3(0.02, 0.105, 0.47)
				1:
					c += Vector3(off, 0.5 * sgn + (0.0 if sgn > 0 else 0.0) - 0.02 * sgn, 0)
					half = Vector3(0.105, 0.02, 0.47)
				_:
					c += Vector3(0, off, sgn * 0.48)
					half = Vector3(0.47, 0.105, 0.02)
			wood.b = rng.randf()
			_board(b, c, half, Basis(), wood, rng)
	# Corner battens.
	for x in [-1, 1]:
		for z in [-1, 1]:
			_board(b, Vector3(x * 0.49, 0.5, z * 0.49), Vector3(0.04, 0.5, 0.04), Basis(), Color(0.3, 0, rng.randf(), 1), rng)
	return b.commit()


## Barrel staves (wood) about 0.9 m tall, radius 0.3.
static func barrel() -> ArrayMesh:
	var b := B.new()
	var rng := _rng(3201)
	var staves := 14
	for s in staves:
		var a0 := TAU * float(s) / staves
		var a1 := TAU * float(s + 0.94) / staves
		var col := Color(0, 0, rng.randf(), 1)
		var rows: Array = []
		for i in 7:
			var t := float(i) / 6.0
			var r := 0.27 + 0.05 * sin(t * PI)
			var y := t * 0.9
			var row := PackedInt32Array()
			for a: float in [a0, a1]:
				row.append(b.vert(Vector3(cos(a) * r, y, sin(a) * r), col, Vector2(a, t)))
			rows.append(row)
		for i in 6:
			var r0: PackedInt32Array = rows[i]
			var r1: PackedInt32Array = rows[i + 1]
			var am := (a0 + a1) * 0.5
			b.quad(r0[0], r0[1], r1[1], r1[0], Vector3(cos(am), 0, sin(am)))
	# Lids.
	for y: float in [0.02, 0.86]:
		var c := b.vert(Vector3(0, y, 0), Color(0, 1, 0.5, 0.8))
		var ring := PackedInt32Array()
		for s in staves:
			var a := TAU * float(s) / staves
			ring.append(b.vert(Vector3(cos(a) * 0.27, y, sin(a) * 0.27), Color(0, 1, 0.5, 0.8)))
		for s in staves:
			b.tri(c, ring[s], ring[(s + 1) % staves], Vector3.UP if y > 0.5 else Vector3.DOWN)
	return b.commit()


## Iron hoops for the barrel.
static func barrel_hoops() -> ArrayMesh:
	var b := B.new()
	for y: float in [0.1, 0.3, 0.6, 0.8]:
		var t := y / 0.9
		var r := 0.27 + 0.05 * sin(t * PI) + 0.006
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		var cols := PackedColorArray()
		for i in 21:
			var a := TAU * float(i) / 20.0
			pts.append(Vector3(cos(a) * r, y, sin(a) * r))
			radii.append(0.012)
			cols.append(Color(0.4, 0, 0.5, 1))
		CaveMeshes.tube(b, pts, radii, cols, 4, 0.0, 1.0, 0.0, false, false)
	return b.commit()


## Riveted iron ore cart (about 1.4 x 1.1 x 0.95 m), wheels and axles. Floor at y = 0.
static func cart() -> ArrayMesh:
	var b := B.new()
	var rng := _rng(3301)
	var rows: Array = []
	var rounded := func(w: float, l: float, r: float, segs: int) -> Array[Vector2]:
		var out: Array[Vector2] = []
		for q in 4:
			var cx := (w * 0.5 - r) * (1 if q == 0 or q == 3 else -1)
			var cz := (l * 0.5 - r) * (1 if q < 2 else -1)
			for s in segs + 1:
				var a := PI * 0.5 * (q + float(s) / segs)
				out.append(Vector2(cx + cos(a) * r, cz + sin(a) * r))
		return out
	var levels := [[0.3, 0.72, 1.05], [0.55, 0.82, 1.2], [0.98, 0.94, 1.36]]
	var outline_count := 0
	for lv: Array in levels:
		var ol: Array[Vector2] = rounded.call(lv[1], lv[2], 0.1, 3)
		outline_count = ol.size()
		var row := PackedInt32Array()
		for p in ol:
			var rust := clampf(0.5 + CaveMeshes.n3(Vector3(p.x, lv[0], p.y) * 4.0, 2.0) * 0.8, 0.0, 1.0)
			row.append(b.vert(Vector3(p.x, lv[0], p.y), Color(rust, 0, 0.5, 1.0 if lv[0] > 0.5 else 0.7)))
		rows.append(row)
	for i in 2:
		var r0: PackedInt32Array = rows[i]
		var r1: PackedInt32Array = rows[i + 1]
		for k in outline_count:
			var k1 := (k + 1) % outline_count
			var mid := (b.v[r0[k]] + b.v[r1[k1]]) * 0.5
			b.quad(r0[k], r0[k1], r1[k1], r1[k], Vector3(mid.x, 0, mid.z))
	# Inner wall (thin sheet) and floor.
	var top_in: Array[Vector2] = rounded.call(0.88, 1.3, 0.08, 3)
	var bot_in: Array[Vector2] = rounded.call(0.66, 0.98, 0.08, 3)
	var ri := PackedInt32Array()
	var rb := PackedInt32Array()
	for k in top_in.size():
		ri.append(b.vert(Vector3(top_in[k].x, 0.97, top_in[k].y), Color(0.8, 0, 0.5, 0.6)))
		rb.append(b.vert(Vector3(bot_in[k].x, 0.36, bot_in[k].y), Color(0.9, 0, 0.5, 0.35)))
	for k in top_in.size():
		var k1 := (k + 1) % top_in.size()
		var mid := (b.v[ri[k]] + b.v[rb[k1]]) * 0.5
		b.quad(ri[k], ri[k1], rb[k1], rb[k], -Vector3(mid.x, 0, mid.z))
	var fc := b.vert(Vector3(0, 0.36, 0), Color(0.9, 0, 0.5, 0.3))
	for k in bot_in.size():
		b.tri(fc, rb[k], rb[(k + 1) % bot_in.size()], Vector3.UP)
	var bc := b.vert(Vector3(0, 0.3, 0), Color(0.6, 0, 0.5, 0.5))
	var r0b: PackedInt32Array = rows[0]
	for k in outline_count:
		b.tri(bc, r0b[k], r0b[(k + 1) % outline_count], Vector3.DOWN)
	# Rolled rim.
	var rim := PackedVector3Array()
	var rim_r := PackedFloat32Array()
	var rim_c := PackedColorArray()
	var top_out: Array[Vector2] = rounded.call(0.95, 1.37, 0.1, 3)
	for k in top_out.size() + 1:
		var p := top_out[k % top_out.size()]
		rim.append(Vector3(p.x, 0.985, p.y))
		rim_r.append(0.025)
		rim_c.append(Color(0.3, 0, 0.5, 1))
	CaveMeshes.tube(b, rim, rim_r, rim_c, 6, 0.0, 1.0, 0.0, false, false)
	# Strap bands with rivets.
	for z: float in [-0.35, 0.0, 0.35]:
		for side in [-1.0, 1.0]:
			var pts := PackedVector3Array([Vector3(side * 0.37, 0.32, z), Vector3(side * 0.42, 0.6, z), Vector3(side * 0.48, 0.96, z)])
			CaveMeshes.tube(b, pts, PackedFloat32Array([0.018, 0.018, 0.018]), PackedColorArray([Color(0.6, 0, 0.5, 1), Color(0.6, 0, 0.5, 1), Color(0.6, 0, 0.5, 1)]), 4, 0.0, 1.0, 0.0, false, false)
			for k in 4:
				var t := float(k) / 3.0
				var rp := Vector3(side * lerpf(0.385, 0.485, t), lerpf(0.34, 0.94, t), z)
				CaveMeshes.blob(b, rp + Vector3(side * 0.012, 0, 0), Vector3.ONE * 0.014, 0, 0.0, 1.0, 0.0, Color(0.2, 0, 0.5, 1))
	# Chassis beams, axles and flanged wheels.
	for x: float in [-0.25, 0.25]:
		CaveMeshes.tube(b, PackedVector3Array([Vector3(x, 0.26, -0.62), Vector3(x, 0.26, 0.62)]), PackedFloat32Array([0.04, 0.04]), PackedColorArray([Color(0.7, 0, 0.5, 0.8), Color(0.7, 0, 0.5, 0.8)]), 4, 0.0, 1.0, 0.0, true, true)
	for z: float in [-0.42, 0.42]:
		CaveMeshes.tube(b, PackedVector3Array([Vector3(-0.5, 0.17, z), Vector3(0.5, 0.17, z)]), PackedFloat32Array([0.025, 0.025]), PackedColorArray([Color(0.5, 0, 0.5, 0.8), Color(0.5, 0, 0.5, 0.8)]), 6, 0.0, 1.0, 0.0, true, true)
		for x: float in [-0.45, 0.45]:
			var s := signf(x)
			var wp := PackedVector3Array([Vector3(x - s * 0.04, 0.17, z), Vector3(x - s * 0.035, 0.17, z), Vector3(x + s * 0.0, 0.17, z), Vector3(x + s * 0.03, 0.17, z), Vector3(x + s * 0.035, 0.17, z)])
			var wr := PackedFloat32Array([0.19, 0.2, 0.165, 0.165, 0.05])
			var wc := PackedColorArray([Color(0.5, 0, 0.5, 0.8), Color(0.3, 0, 0.5, 0.9), Color(0.2, 0, 0.5, 1), Color(0.4, 0, 0.5, 1), Color(0.6, 0, 0.5, 1)])
			CaveMeshes.tube(b, wp, wr, wc, 16, 0.0, 1.0, 0.0, true, true)
	return b.commit()


## Ore heap that fills the cart tub (y 0.4 .. 1.05).
static func heap() -> ArrayMesh:
	var b := B.new()
	var rng := _rng(3401)
	for i in 16:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf())
		var r := rng.randf_range(0.08, 0.17)
		var c := Vector3(cos(a) * d * 0.33, 0.62 + (1.0 - d) * 0.3 + rng.randf_range(-0.03, 0.03), sin(a) * d * 0.52)
		CaveMeshes.blob(b, c, Vector3(r, r * 0.8, r), 1, 0.2, 2.0, float(i), Color(0.5, 1, rng.randf(), 1.0), -INF, 0.5, false, 5)
	return b.commit()


## Iron lantern cage: hook, cap, four bars, base. Hanging point at y = 0, body below.
static func lantern_frame() -> ArrayMesh:
	var b := B.new()
	var c := Color(0.4, 0, 0.5, 1)
	var pts := PackedVector3Array([Vector3(0, 0.0, 0), Vector3(0, -0.03, 0), Vector3(0, -0.08, 0), Vector3(0, -0.13, 0)])
	CaveMeshes.tube(b, pts, PackedFloat32Array([0.0, 0.025, 0.09, 0.1]), PackedColorArray([c, c, c, c]), 10, 0.0, 1.0, 0.0, false, true)
	for k in 4:
		var a := TAU * float(k) / 4.0 + PI / 4.0
		var d := Vector3(cos(a), 0, sin(a))
		CaveMeshes.tube(b, PackedVector3Array([d * 0.085 + Vector3(0, -0.13, 0), d * 0.095 + Vector3(0, -0.24, 0), d * 0.085 + Vector3(0, -0.36, 0)]),
			PackedFloat32Array([0.008, 0.008, 0.008]), PackedColorArray([c, c, c]), 4, 0.0, 1.0, 0.0, false, false)
	CaveMeshes.tube(b, PackedVector3Array([Vector3(0, -0.35, 0), Vector3(0, -0.39, 0), Vector3(0, -0.4, 0)]), PackedFloat32Array([0.1, 0.09, 0.0]), PackedColorArray([c, c, c]), 10, 0.0)
	# Handle loop and a short chain to the roof.
	var loop := PackedVector3Array()
	var lr := PackedFloat32Array()
	var lc := PackedColorArray()
	for i in 9:
		var a := PI * float(i) / 8.0
		loop.append(Vector3(cos(a) * 0.06, 0.0 + sin(a) * 0.05 - 0.02, 0))
		lr.append(0.006)
		lc.append(c)
	CaveMeshes.tube(b, loop, lr, lc, 4, 0.0, 1.0, 0.0, false, false)
	return b.commit()


static func lantern_glass() -> ArrayMesh:
	var b := B.new()
	var pts := PackedVector3Array([Vector3(0, -0.13, 0), Vector3(0, -0.2, 0), Vector3(0, -0.29, 0), Vector3(0, -0.35, 0)])
	CaveMeshes.tube(b, pts, PackedFloat32Array([0.06, 0.075, 0.075, 0.065]), PackedColorArray([Color(0, 1, 0.5, 1), Color(0.5, 1, 0.5, 1), Color(0.5, 1, 0.5, 1), Color(0, 1, 0.5, 1)]), 12, 0.0, 1.0, 0.0, true, true)
	return b.commit()


## Sheave wheel for the headframe, radius 0.9 in the XY plane.
static func sheave() -> ArrayMesh:
	var b := B.new()
	var c := Color(0.5, 0, 0.5, 1)
	var rim := PackedVector3Array()
	var rr := PackedFloat32Array()
	var rc := PackedColorArray()
	for i in 33:
		var a := TAU * float(i) / 32.0
		rim.append(Vector3(cos(a) * 0.9, sin(a) * 0.9, 0))
		rr.append(0.05)
		rc.append(c)
	CaveMeshes.tube(b, rim, rr, rc, 6, 0.0, 1.0, 0.0, false, false)
	for k in 8:
		var a := TAU * float(k) / 8.0
		CaveMeshes.tube(b, PackedVector3Array([Vector3.ZERO, Vector3(cos(a) * 0.88, sin(a) * 0.88, 0)]), PackedFloat32Array([0.025, 0.02]), PackedColorArray([c, c]), 5, 0.0, 1.0, 0.0, false, false)
	CaveMeshes.tube(b, PackedVector3Array([Vector3(0, 0, -0.12), Vector3(0, 0, 0.12)]), PackedFloat32Array([0.09, 0.09]), PackedColorArray([c, c]), 10, 0.0, 1.0, 0.0, true, true)
	return b.commit()


## Pickaxe head (iron), handle hole at the origin, spikes along ±X.
static func pick_head() -> ArrayMesh:
	var b := B.new()
	var c := Color(0.6, 0, 0.5, 1)
	for s in [-1.0, 1.0]:
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		var cols := PackedColorArray()
		for i in 6:
			var t := float(i) / 5.0
			pts.append(Vector3(s * t * 0.3, -t * t * 0.07, 0))
			radii.append(0.0 if i == 5 else 0.028 * (1.0 - t * 0.8))
			cols.append(c)
		CaveMeshes.tube(b, pts, radii, cols, 6, 0.0)
	CaveMeshes.blob(b, Vector3.ZERO, Vector3(0.04, 0.045, 0.035), 1, 0.0, 1.0, 0.0, c)
	return b.commit()


## Shovel blade (iron), socket at the origin, blade down along -Y.
static func shovel_blade() -> ArrayMesh:
	var b := B.new()
	var c := Color(0.7, 0, 0.5, 1)
	for side: float in [1.0, -1.0]:
		var rows: Array = []
		for i in 6:
			var t := float(i) / 5.0
			var row := PackedInt32Array()
			var w := lerpf(0.07, 0.13, sqrt(t)) * (1.0 - pow(t, 6.0) * 0.4)
			for k in 7:
				var u := float(k) / 6.0 * 2.0 - 1.0
				row.append(b.vert(Vector3(u * w, -t * 0.32, -u * u * 0.03 + side * 0.003), c))
			rows.append(row)
		for i in 5:
			var r0: PackedInt32Array = rows[i]
			var r1: PackedInt32Array = rows[i + 1]
			for k in 6:
				b.quad(r0[k], r0[k + 1], r1[k + 1], r1[k], Vector3(0, 0, side))
	return b.commit()


## Wooden bucket with an iron handle (y 0..0.35).
static func bucket() -> ArrayMesh:
	var b := B.new()
	var c := Color(0, 0, 0.5, 1)
	CaveMeshes.tube(b, PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0.34, 0)]), PackedFloat32Array([0.14, 0.17]), PackedColorArray([c, c]), 14, 0.03, 9.0, 1.0, true, false)
	return b.commit()


## Spoil heap: a broad mound of waste rock, radius 1 (y 0..0.45).
static func spoil() -> ArrayMesh:
	var b := B.new()
	var rng := _rng(3501)
	var ph := rng.randf() * TAU
	var rad := func(a: float) -> float: return 1.0 + 0.15 * sin(a * 3.0 + ph) + 0.08 * sin(a * 7.0)
	var hgt := func(f: float, a: float) -> float: return 0.45 * (1.0 - f * f) * (0.85 + 0.15 * sin(a * 5.0 + f * 7.0)) + CaveMeshes.n3(Vector3(cos(a) * f, 0, sin(a) * f) * 6.0, 4.0) * 0.04 - (0.06 if f > 0.99 else 0.0)
	CaveMeshes.disc(b, 8, 30, rad, hgt, Color(0.5, 0, 0.5, 1.0), 0.06)
	for i in 14:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * 0.95
		var r := rng.randf_range(0.04, 0.12)
		CaveMeshes.blob(b, Vector3(cos(a) * d, 0.45 * (1.0 - d * d) * 0.9, sin(a) * d), Vector3(r, r * 0.7, r), 1, 0.2, 3.0, float(i), Color(0.5, 0, rng.randf(), 1), -INF, 0.4, false, 5)
	return b.commit()
