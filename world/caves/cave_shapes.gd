class_name CaveShapes
extends RefCounted
## Template meshes for CaveDecor, roughly unit sized (instances scale them).
## Local +Y is the surface normal (out of the rock) unless stated otherwise.

const B := CaveMeshes.Builder


static func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


## Hanging dripstone, root at y = +0.25 inside the rock, tip at y = -1.
## variant 0 slender, 1 thick and lumpy, 2 a cluster of three.
static func stalactite(variant: int) -> ArrayMesh:
	var b := B.new()
	var rng := _rng(101 + variant)
	var specs: Array = [[Vector3.ZERO, 1.0, 0.13 if variant == 0 else 0.25]]
	if variant == 2:
		specs = [[Vector3.ZERO, 1.0, 0.16], [Vector3(0.17, 0.02, 0.05), 0.62, 0.1], [Vector3(-0.07, 0.03, -0.16), 0.42, 0.08]]
	for k in specs.size():
		var off: Vector3 = specs[k][0]
		var length: float = specs[k][1]
		var r0: float = specs[k][2]
		var bend := Vector2(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.08, 0.08))
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		var cols := PackedColorArray()
		var rings := 13
		var phase := rng.randf() * TAU
		for i in rings:
			var t := float(i) / (rings - 1)
			var y := 0.25 - t * (length + 0.25)
			var r := r0 * pow(1.0 - t, 1.25) + 0.006
			r *= 1.0 + 0.09 * sin(t * 26.0 + phase) * (1.0 - t)
			if t < 0.2:
				r *= 1.0 + (0.2 - t) * 3.2  # flares into the ceiling
			if i == rings - 1:
				r = 0.0
			pts.append(off + Vector3(bend.x * t * t, y, bend.y * t * t))
			radii.append(r)
			cols.append(Color(t, 0.0, rng.randf(), lerpf(0.55, 1.0, minf(1.0, t * 3.0))))
		CaveMeshes.tube(b, pts, radii, cols, 9 if variant == 0 else 11, 0.22 if variant == 1 else 0.12, 5.0, float(variant * 3 + k))
		# A drop of water clinging to the tip.
		CaveMeshes.blob(b, pts[pts.size() - 1] + Vector3(0, -0.03, 0), Vector3(0.02, 0.028, 0.02), 1, 0.0, 1.0, 0.0, Color(1.0, 1.0, 0.5, 1.0))
	return b.commit()


## Floor dripstone, base at y = -0.25, top at y = 1. variant 0 slender, 1 squat stacked "fried eggs".
static func stalagmite(variant: int) -> ArrayMesh:
	var b := B.new()
	var rng := _rng(211 + variant)
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var cols := PackedColorArray()
	var rings := 14
	var r0 := 0.2 if variant == 0 else 0.42
	var phase := rng.randf() * TAU
	var lean := Vector2(rng.randf_range(-0.06, 0.06), rng.randf_range(-0.06, 0.06))
	for i in rings:
		var t := float(i) / (rings - 1)
		var y := -0.25 + t * 1.25
		var shape := pow(maxf(0.0, 1.0 - pow(t, 2.4)), 0.55)
		var r := r0 * shape
		if variant == 1:
			# Stacked splash cups ("fried eggs").
			r *= 1.0 + 0.22 * pow(maxf(0.0, sin(t * 17.0 + phase)), 3.0)
		else:
			r *= 1.0 + 0.06 * sin(t * 30.0 + phase) + 0.05 * sin(t * 71.0 + phase * 2.0)
		if t < 0.15:
			r *= 1.0 + (0.15 - t) * 3.5
		pts.append(Vector3(lean.x * t * t, y, lean.y * t * t))
		radii.append(r if i < rings - 1 else 0.0)
		cols.append(Color(t, 0.0, rng.randf(), lerpf(0.5, 1.0, minf(1.0, t * 2.5))))
	CaveMeshes.tube(b, pts, radii, cols, 14, 0.24, 6.0, 40.0 + variant)
	return b.commit()


## A curtain of icicles hanging from an ice crust (ceiling; tips at y ≈ -1).
static func icicles() -> ArrayMesh:
	var b := B.new()
	var rng := _rng(307)
	for i in 13:
		var x := lerpf(-0.5, 0.5, (i + rng.randf_range(-0.3, 0.3)) / 12.0)
		var z := rng.randf_range(-0.16, 0.16)
		var length := rng.randf_range(0.15, 1.0) * (1.0 - absf(x) * 0.7)
		var r0 := rng.randf_range(0.02, 0.055) * (0.6 + length * 0.5)
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		var cols := PackedColorArray()
		for k in 8:
			var t := float(k) / 7.0
			pts.append(Vector3(x + sin(t * 3.0 + i) * 0.01, 0.3 - t * (length + 0.3), z))
			radii.append(0.0 if k == 7 else r0 * pow(1.0 - t, 1.5) * (1.0 + 0.1 * sin(t * 30.0 + i)))
			cols.append(Color(t, 1.0, rng.randf(), 1.0))
		CaveMeshes.tube(b, pts, radii, cols, 5, 0.05, 6.0, float(i))
	return b.commit()


## Botryoidal metal nodules: a cluster of bumpy hemispheres half sunk in the rock.
static func nodules(variant: int) -> ArrayMesh:
	var b := B.new()
	var rng := _rng(401 + variant)
	var count := 7 if variant == 0 else 10
	CaveMeshes.blob(b, Vector3(0, 0.0, 0), Vector3(0.15, 0.07, 0.13), 1, 0.35, 6.0, 9.0, Color(0, 1, 0.5, 0.75))
	for i in count:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 0.3) * (0.4 if i == 0 else 1.0)
		var r := rng.randf_range(0.035, 0.11) * (1.5 if i == 0 else 1.0)
		var c := Vector3(cos(a) * d, r * rng.randf_range(-0.1, 0.25), sin(a) * d)
		CaveMeshes.blob(b, c, Vector3(r, r * rng.randf_range(0.7, 1.0), r), 1, 0.22, 14.0 / r * 0.12, float(i + variant * 20), Color(0.6, 1, rng.randf(), 1.0), -INF, 0.4)
		# Grape-like secondary bubbles.
		for k in 2:
			var sa := rng.randf() * TAU
			var sr := r * rng.randf_range(0.3, 0.5)
			var sc := c + Vector3(cos(sa), rng.randf_range(0.2, 0.8), sin(sa)).normalized() * r * 0.9
			CaveMeshes.blob(b, sc, Vector3.ONE * sr, 0, 0.15, 10.0, float(i * 3 + k), Color(0.8, 1, rng.randf(), 1.0))
	return b.commit()


## Coal: dark glossy lenses along a seam.
static func lens(variant: int) -> ArrayMesh:
	var b := B.new()
	var rng := _rng(503 + variant)
	var x := -0.45
	var count := 4 if variant == 0 else 5
	for i in count:
		var lx := rng.randf_range(0.14, 0.3)
		x += lx * 0.9
		var c := Vector3(x, rng.randf_range(-0.01, 0.025), sin(x * 4.0 + variant) * 0.08 + rng.randf_range(-0.04, 0.04))
		CaveMeshes.blob(b, c, Vector3(lx, rng.randf_range(0.035, 0.07), rng.randf_range(0.07, 0.13)), 1, 0.3, 5.0, float(i + 50 * variant), Color(0.5, 1, rng.randf(), 0.9))
		x += lx * 0.6
	for i in 5:
		var c := Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.2, 0.2))
		CaveMeshes.blob(b, c, Vector3.ONE * rng.randf_range(0.02, 0.05), 0, 0.3, 8.0, float(i + 9), Color(0.5, 1, rng.randf(), 1.0))
	return b.commit()


## Small crystal druse: prisms radiating from a rocky matrix.
static func crystals_small(variant: int) -> ArrayMesh:
	var b := B.new()
	var rng := _rng(601 + variant)
	CaveMeshes.blob(b, Vector3(0, -0.02, 0), Vector3(0.2, 0.06, 0.17), 1, 0.4, 7.0, 21.0 + variant, Color(0, 0, 0.5, 0.7))
	var count := 8 if variant == 0 else 12
	for i in count:
		var a := rng.randf() * TAU
		var spread := rng.randf_range(0.05, 0.75)
		var dir := Vector3(cos(a) * spread, 1.0, sin(a) * spread)
		var base := Vector3(cos(a) * rng.randf_range(0.0, 0.12), -0.03, sin(a) * rng.randf_range(0.0, 0.12))
		var length := rng.randf_range(0.09, 0.34) * (1.25 if i == 0 else 1.0)
		var radius := length * rng.randf_range(0.12, 0.2)
		CaveMeshes.prism(b, base, dir, length, radius, 6, radius * rng.randf_range(1.2, 2.2), rng)
	return b.commit()


## Large crystal cluster (sanctuaries, frost and ember caves), about 1 m tall.
static func crystals_large(variant: int) -> ArrayMesh:
	var b := B.new()
	var rng := _rng(701 + variant)
	CaveMeshes.blob(b, Vector3(0, -0.05, 0), Vector3(0.45, 0.14, 0.4), 2, 0.35, 3.0, 31.0 + variant, Color(0, 0, 0.5, 0.65))
	var count := 6 if variant == 0 else 9
	for i in count:
		var a := TAU * float(i) / count + rng.randf_range(-0.3, 0.3)
		var spread := 0.0 if i == 0 else rng.randf_range(0.25, 0.9)
		var dir := Vector3(cos(a) * spread, 1.0, sin(a) * spread)
		var base := Vector3(cos(a), 0, sin(a)) * (0.0 if i == 0 else rng.randf_range(0.08, 0.25)) + Vector3(0, -0.08, 0)
		var length := 1.0 if i == 0 else rng.randf_range(0.3, 0.78)
		var radius := 0.12 if i == 0 else length * rng.randf_range(0.13, 0.2)
		CaveMeshes.prism(b, base, dir, length, radius, 6, radius * rng.randf_range(1.4, 2.4), rng)
	return b.commit()


## Amethyst geode: a broken, lumpy rind cupping a lining of purple points.
static func geode() -> ArrayMesh:
	var b := B.new()
	var rng := _rng(809)
	# Rind: a low irregular lip around the cavity, broken on one side.
	for i in 9:
		var a := TAU * float(i) / 9.0 + rng.randf_range(-0.2, 0.2)
		if i == 4:
			continue
		var r := rng.randf_range(0.05, 0.08)
		CaveMeshes.blob(b, Vector3(cos(a) * 0.3, -0.01, sin(a) * 0.3), Vector3(r * 1.6, r * 0.7, r), 0, 0.35, 4.0, float(i), Color(0.0, 0, 0.5, 0.8), -INF, 0.0, false, 3)
	# Lining: dense crystal points filling the bowl and spilling over the lip.
	for i in 46:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * 0.3
		var base := Vector3(cos(a) * d, -0.05 + d * 0.12, sin(a) * d)
		var inward := Vector3(-cos(a), 0, -sin(a)) * d * 1.6
		var length := rng.randf_range(0.05, 0.16) * (1.3 - d)
		CaveMeshes.prism(b, base, Vector3.UP + inward + Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25)), length, length * 0.3, 5, length * 0.45, rng, Color(0.1, 1, 0, 0.5), Color(1, 1, 0, 1))
	return b.commit()


## Obsidian: sharp, conchoidally fractured glass blades.
static func shards(variant: int) -> ArrayMesh:
	var b := B.new()
	var rng := _rng(907 + variant)
	for i in (6 if variant == 0 else 8):
		var a := rng.randf() * TAU
		var tilt := rng.randf_range(0.1, 0.65)
		var dir := Vector3(cos(a) * tilt, 1.0, sin(a) * tilt).normalized()
		var base := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.25) + Vector3(0, -0.06, 0)
		var length := rng.randf_range(0.18, 0.6)
		var w := rng.randf_range(0.05, 0.12)
		var th := w * rng.randf_range(0.25, 0.5)
		var side := dir.cross(Vector3(cos(a + 1.3), 0, sin(a + 1.3))).normalized()
		var thick := dir.cross(side).normalized()
		var mid := base + dir * length * rng.randf_range(0.45, 0.65)
		var tip := base + dir * length + side * rng.randf_range(-0.04, 0.04)
		var c0 := Color(0.0, 1, 0, 0.6)
		var c1 := Color(1.0, 1, 0, 1)
		var corners := [base + side * w, base + thick * th, base - side * w * 0.8, base - thick * th]
		var mids := [mid + side * w * 0.9, mid + thick * th * 0.8, mid - side * w * 0.7, mid - thick * th * 0.8]
		for k in 4:
			var k1 := (k + 1) % 4
			var out: Vector3 = ((corners[k] as Vector3) + (corners[k1] as Vector3)) * 0.5 - base
			b.flat_tri(corners[k], corners[k1], mids[k1], out, c0, c0, c1)
			b.flat_tri(corners[k], mids[k1], mids[k], out, c0, c1, c1)
			b.flat_tri(mids[k], mids[k1], tip, out + dir * 0.3, c1, c1, c1)
	return b.commit()


## Basalt: a cluster of weathered hexagonal columns with jointed shafts and rounded tops.
static func basalt() -> ArrayMesh:
	var b := B.new()
	var rng := _rng(1009)
	var cells: Array[Vector2] = [Vector2.ZERO]
	for ring in 2:
		for k in 6 * (ring + 1):
			var a := TAU * float(k) / (6 * (ring + 1))
			cells.append(Vector2(cos(a), sin(a)) * 0.29 * (ring + 1) + Vector2(rng.randf_range(-0.03, 0.03), rng.randf_range(-0.03, 0.03)))
	for i in cells.size():
		var c := cells[i]
		if i > 0 and rng.randf() < 0.25:
			continue
		var h := rng.randf_range(0.35, 1.0) * (1.0 - c.length() * 0.8) + 0.1
		var r := rng.randf_range(0.13, 0.16)
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		var cols := PackedColorArray()
		var rings := maxi(3, int(h / 0.12))
		var tilt := Vector3(rng.randf_range(-0.03, 0.03), 0, rng.randf_range(-0.03, 0.03))
		for k in rings + 1:
			var t := float(k) / rings
			var y := -0.25 + t * (h + 0.25)
			# Columnar joints: a slight waist every few tens of centimetres.
			var joint := 1.0 - 0.06 * pow(absf(sin(y * 9.0 + i)), 8.0)
			pts.append(Vector3(c.x, y, c.y) + tilt * y)
			radii.append(r * joint)
			cols.append(Color(t, 0, rng.randf(), lerpf(0.55, 1.0, t)))
		# Rounded, weathered top.
		pts.append(Vector3(c.x, h + 0.04, c.y) + tilt * h)
		radii.append(r * 0.75)
		cols.append(Color(1, 0, 0.5, 1))
		pts.append(Vector3(c.x, h + 0.06, c.y) + tilt * h)
		radii.append(0.0)
		cols.append(Color(1, 0, 0.5, 1))
		_hex_tube(b, pts, radii, cols, rng.randf() * TAU)
	return b.commit()


## A tube with a rounded-hexagon section (basalt columns).
static func _hex_tube(b: CaveMeshes.Builder, pts: PackedVector3Array, radii: PackedFloat32Array, cols: PackedColorArray, rot: float) -> void:
	var sides := 6
	var rings: Array = []
	for i in pts.size():
		var ring := PackedInt32Array()
		if radii[i] <= 0.0005:
			ring.append(b.vert(pts[i], cols[i]))
		else:
			for s in sides:
				var a := TAU * float(s) / sides + rot
				# Hexagon radius at this angle, corners softened.
				var seg := fposmod(a - rot, TAU / 6.0) - TAU / 12.0
				var hex := cos(TAU / 12.0) / cos(seg)
				var rr := radii[i] * (1.0 + CaveMeshes.n3(pts[i] * 7.0 + Vector3(cos(a), 0, sin(a)), 3.0) * 0.06)
				var _h := hex
				ring.append(b.vert(pts[i] + Vector3(cos(a), 0, sin(a)) * rr, cols[i]))
		rings.append(ring)
	for i in pts.size() - 1:
		var r0: PackedInt32Array = rings[i]
		var r1: PackedInt32Array = rings[i + 1]
		for s in sides:
			var s1 := (s + 1) % sides
			var a := TAU * (float(s) + 0.5) / sides + rot
			var out := Vector3(cos(a), 0.3 if i >= pts.size() - 3 else 0.0, sin(a))
			if r1.size() == 1:
				b.tri(r0[s], r0[s1], r1[0], Vector3.UP + out * 0.2)
			else:
				var c00 := b.v[r0[s]]
				var c01 := b.v[r0[s1]]
				var c11 := b.v[r1[s1]]
				var c10 := b.v[r1[s]]
				b.flat_tri(c00, c01, c11, out, b.c[r0[s]], b.c[r0[s1]], b.c[r1[s1]])
				b.flat_tri(c00, c11, c10, out, b.c[r0[s]], b.c[r1[s1]], b.c[r1[s]])


## Glowing cracks in a crust of cooled lava (floor decal-like mesh, y ≈ 0).
static func ember_cracks() -> ArrayMesh:
	var b := B.new()
	var rng := _rng(1103)
	for branch in 5:
		var p := Vector3(rng.randf_range(-0.3, 0.3), 0.012, rng.randf_range(-0.3, 0.3))
		var a := rng.randf() * TAU
		var w := rng.randf_range(0.1, 0.18)
		for s in 7:
			a += rng.randf_range(-0.7, 0.7)
			var q := p + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.08, 0.2)
			q.y = 0.012
			var side := Vector3(-sin(a), 0, cos(a)) * w * 0.5
			# Centre line hot (r = 1), jagged edges cooler (r = 0).
			var j0 := Vector3(-sin(a), 0, cos(a)) * w * rng.randf_range(-0.25, 0.25)
			var ic0 := b.vert(p + j0, Color(1.0, 1.0, rng.randf(), 1))
			var ic1 := b.vert(q + j0, Color(1.0, 1.0, rng.randf(), 1))
			var i0 := b.vert(p - side * rng.randf_range(0.7, 1.2), Color(0.0, 1.0, rng.randf(), 1))
			var i1 := b.vert(p + side * rng.randf_range(0.7, 1.2), Color(0.0, 1.0, rng.randf(), 1))
			var i2 := b.vert(q + side * rng.randf_range(0.6, 1.0), Color(0.0, 1.0, rng.randf(), 1))
			var i3 := b.vert(q - side * rng.randf_range(0.6, 1.0), Color(0.0, 1.0, rng.randf(), 1))
			b.quad(i0, ic0, ic1, i3, Vector3.UP)
			b.quad(ic0, i1, i2, ic1, Vector3.UP)
			p = q
			w *= 0.82
	# Crusted rims of cooled rock beside the cracks.
	for i in 6:
		var c := Vector3(rng.randf_range(-0.45, 0.45), -0.02, rng.randf_range(-0.45, 0.45))
		CaveMeshes.blob(b, c, Vector3(rng.randf_range(0.08, 0.2), 0.04, rng.randf_range(0.08, 0.2)), 1, 0.4, 7.0, float(i), Color(0, 0, rng.randf(), 0.8))
	return b.commit()


## Rubble: angular rocks fallen from the roof.
static func rubble(variant: int) -> ArrayMesh:
	var b := B.new()
	var rng := _rng(1201 + variant)
	for i in (6 if variant == 0 else 9):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 0.55)
		var r := rng.randf_range(0.07, 0.3) * (1.4 if i == 0 else 1.0)
		var c := Vector3(cos(a) * d, r * 0.35, sin(a) * d)
		CaveMeshes.blob(b, c, Vector3(r, r * rng.randf_range(0.5, 0.85), r * rng.randf_range(0.7, 1.1)), 1, 0.18, 2.5, float(i + variant * 13), Color(0.5, 0, rng.randf(), 1.0), 0.0, 0.5, false, 7)
	return b.commit()


## Geyser sinter: terraced rimstone pools stepping down from a small basin.
static func sinter(variant: int) -> ArrayMesh:
	var b := B.new()
	var rng := _rng(1301 + variant)
	var lobes := [rng.randf() * TAU, rng.randf() * TAU]
	var rad := func(a: float) -> float: return 0.85 * (1.0 + 0.16 * sin(a * 3.0 + lobes[0]) + 0.1 * sin(a * 5.0 + lobes[1]))
	var hgt := func(f: float, a: float) -> float:
		# Terraces: flat pools behind raised lips.
		var steps := 4.0
		var k := floorf(f * steps)
		var frac := f * steps - k
		var lip := smoothstep(0.75, 0.92, frac) * (1.0 - smoothstep(0.92, 1.0, frac))
		return 0.16 - k * 0.055 + lip * 0.022 - (0.05 if f > 0.97 else 0.0) + 0.006 * sin(a * 9.0)
	CaveMeshes.disc(b, 9, 24, rad, hgt, Color(0, 0, 0.5, 1.0), 0.08)
	# Mark the central basin as wet (g channel) for the hot-pool shader.
	for i in b.v.size():
		var d := Vector2(b.v[i].x, b.v[i].z).length()
		if d < 0.2:
			b.c[i].g = 1.0
	return b.commit()


# --- Fungi ---------------------------------------------------------------------------------------
# Colour r: 0 stem, 0.5 gills / underside, 1 cap top. g: glow mask.

static func _cap(b: CaveMeshes.Builder, top: Vector3, radius: float, height: float, droop: float, seed_value: float, gills := true, sides := 14) -> void:
	# Cap as a lathe: apex down to a curled rim, then the gill underside back to the stem.
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var cols := PackedColorArray()
	var rings := 7 if sides > 10 else 4
	for i in rings:
		var t := float(i) / (rings - 1)
		var r := radius * sin(t * PI * 0.5)
		var y := top.y + height * (1.0 - t * t) - droop * t * t * t
		pts.append(Vector3(top.x, y, top.z))
		radii.append(r)
		cols.append(Color(1.0, smoothstep(0.62, 1.0, t), 0.5, 1.0))
	# Underside from the rim back in towards the stem.
	pts.append(Vector3(top.x, top.y - droop - height * 0.05, top.z))
	radii.append(radius * 0.93)
	cols.append(Color(0.5, 0.45, 0.5, 0.75))
	pts.append(Vector3(top.x, top.y - height * 0.05, top.z))
	radii.append(radius * 0.25)
	cols.append(Color(0.5, 0.1, 0.5, 0.45))
	_lathe(b, pts, radii, cols, sides, 0.08, seed_value)
	if gills and radius > 0.2:
		for g in 36:
			var a := TAU * float(g) / 36.0
			var d := Vector3(cos(a), 0, sin(a))
			var y0 := top.y - height * 0.04
			var p0 := Vector3(top.x, y0, top.z) + d * radius * 0.27
			var p1 := Vector3(top.x, top.y - droop * 0.9, top.z) + d * radius * 0.9
			var side := Vector3(-d.z, 0, d.x) * 0.004
			var drop := Vector3(0, -height * 0.18, 0)
			var gc := Color(0.5, 1.0, 0.5, 0.6)
			for s: Vector3 in [side, -side]:
				var i0 := b.vert(p0 + s, gc)
				var i1 := b.vert(p1 + s, gc)
				var i2 := b.vert(p1 + s + drop * 0.4, gc)
				var i3 := b.vert(p0 + s + drop, gc)
				b.quad(i0, i1, i2, i3, s)


## Surface of revolution around the vertical axis through pts[i].
static func _lathe(b: CaveMeshes.Builder, pts: PackedVector3Array, radii: PackedFloat32Array, cols: PackedColorArray, sides: int, jitter: float, seed_value: float) -> void:
	var rings: Array = []
	var rmax := 0.0
	for r in radii:
		rmax = maxf(rmax, r)
	for i in pts.size():
		var ring := PackedInt32Array()
		if radii[i] < 0.0005:
			ring.append(b.vert(pts[i], cols[i], Vector2(0.5, 0.5)))
		else:
			for s in sides:
				var a := TAU * float(s) / sides
				var d := Vector3(cos(a), 0, sin(a))
				var r := radii[i] * (1.0 + CaveMeshes.n3(pts[i] * 3.0 + d * 2.0, seed_value) * jitter)
				var f := radii[i] / maxf(0.0001, rmax)
				ring.append(b.vert(pts[i] + d * r, cols[i], Vector2(0.5 + d.x * f * 0.5, 0.5 + d.z * f * 0.5)))
		rings.append(ring)
	for i in pts.size() - 1:
		var r0: PackedInt32Array = rings[i]
		var r1: PackedInt32Array = rings[i + 1]
		# Outward: away from the axis, and up for the cap's top part / down underneath.
		var up_part := pts[i + 1].y <= pts[i].y
		for s in sides:
			var s1 := (s + 1) % sides
			var a := TAU * (float(s) + 0.5) / sides
			var out := Vector3(cos(a), 0.6 if up_part else -1.2, sin(a))
			if r0.size() == 1:
				b.tri(r0[0], r1[s], r1[s1], out)
			elif r1.size() == 1:
				b.tri(r0[s], r0[s1], r1[0], out)
			else:
				b.quad(r0[s], r0[s1], r1[s1], r1[s], out)


static func _stem(b: CaveMeshes.Builder, base: Vector3, top: Vector3, r0: float, r1: float, seed_value: float, bulb := 1.6, sides := 7) -> void:
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var cols := PackedColorArray()
	var bow := Vector3(top.x - base.x, 0, top.z - base.z) * 0.5
	var rings := 6 if sides > 5 else 4
	for i in rings:
		var t := float(i) / (rings - 1)
		pts.append(base.lerp(top, t) - bow * sin(t * PI) * 0.6 + Vector3(0, -0.02 if i == 0 else 0.0, 0))
		var r := lerpf(r0, r1, t)
		if t < 0.25:
			r *= 1.0 + (0.25 - t) * 4.0 * (bulb - 1.0)
		radii.append(r)
		cols.append(Color(0.0, 0.15 * t, 0.5, lerpf(0.6, 1.0, t)))
	CaveMeshes.tube(b, pts, radii, cols, sides, 0.08, 18.0, seed_value, false, false)


## Tall slender glow-caps in a tuft. variant 0 tall/bell caps, 1 shorter conical caps.
static func glowcaps(variant: int) -> ArrayMesh:
	var b := B.new()
	var rng := _rng(1401 + variant)
	for i in (6 if variant == 0 else 8):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 0.22)
		var base := Vector3(cos(a) * d, 0, sin(a) * d)
		var h := rng.randf_range(0.12, 0.42) * (1.0 if variant == 0 else 0.6)
		var top := base + Vector3(cos(a) * h * 0.25, h, sin(a) * h * 0.25)
		_stem(b, base, top, rng.randf_range(0.012, 0.02), 0.008, float(i), 1.3, 5)
		var cr := rng.randf_range(0.03, 0.07) * (1.0 if variant == 0 else 0.8)
		_cap(b, top, cr, cr * (1.2 if variant == 0 else 1.6), cr * 0.35, float(i) + 7.0, false, 8)
	return b.commit()


## Luminous puffballs.
static func puffballs() -> ArrayMesh:
	var b := B.new()
	var rng := _rng(1501)
	for i in 8:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 0.3)
		var r := rng.randf_range(0.025, 0.085)
		var c := Vector3(cos(a) * d, r * 0.8, sin(a) * d)
		CaveMeshes.blob(b, c, Vector3(r, r * 0.85, r), 1, 0.12, 9.0, float(i), Color(1.0, 0.85, rng.randf(), 1.0), -INF, 0.5)
		_stem(b, c - Vector3(0, r * 0.9, 0), c - Vector3(0, r * 0.4, 0), r * 0.35, r * 0.25, float(i) + 3.0, 1.0, 5)
	return b.commit()


## Bracket fungi stacked on a wall. Local +Y out of the wall, +Z world up.
static func shelf(variant: int) -> ArrayMesh:
	var b := B.new()
	var rng := _rng(1601 + variant)
	var z := -0.25
	for i in (4 if variant == 0 else 3):
		var r := rng.randf_range(0.11, 0.24) * (1.25 if variant == 1 else 1.0)
		var cx := rng.randf_range(-0.12, 0.12)
		var rings := 4
		var segs := 9
		var top_rows: Array = []
		var bot_rows: Array = []
		var wave := rng.randf() * TAU
		for ring in rings + 1:
			var f := float(ring) / rings
			var trow := PackedInt32Array()
			var brow := PackedInt32Array()
			for s in segs:
				var a := PI * float(s) / (segs - 1)
				var rr := r * f * (1.0 + 0.1 * sin(a * 7.0 + wave) * f)
				var x := cx + cos(a) * rr
				var y := sin(a) * rr - 0.02
				var th := lerpf(0.05, 0.01, f)
				var droop := -f * f * r * 0.25
				trow.append(b.vert(Vector3(x, y, z + th * 0.5 + droop), Color(1.0, 0.25 + f * 0.6, 0.5, 1.0), Vector2(a / PI, f)))
				brow.append(b.vert(Vector3(x, y, z - th * 0.5 + droop), Color(0.5, 1.0, 0.5, 0.7), Vector2(a / PI, f)))
			top_rows.append(trow)
			bot_rows.append(brow)
		for ring in rings:
			var t0: PackedInt32Array = top_rows[ring]
			var t1: PackedInt32Array = top_rows[ring + 1]
			var b0: PackedInt32Array = bot_rows[ring]
			var b1: PackedInt32Array = bot_rows[ring + 1]
			for s in segs - 1:
				b.quad(t0[s], t0[s + 1], t1[s + 1], t1[s], Vector3(0, 0, 1))
				b.quad(b0[s], b0[s + 1], b1[s + 1], b1[s], Vector3(0, 0, -1))
		var lt: PackedInt32Array = top_rows[rings]
		var lb: PackedInt32Array = bot_rows[rings]
		for s in segs - 1:
			var a := PI * (float(s) + 0.5) / (segs - 1)
			b.quad(lt[s], lt[s + 1], lb[s + 1], lb[s], Vector3(cos(a), sin(a), 0))
		z += rng.randf_range(0.1, 0.18)
	return b.commit()


## A giant cave mushroom about 1 m tall (instances scale it 2-5x): bulbous stem with a
## ring, broad cap with glowing gills underneath.
static func giant_mushroom(variant: int) -> ArrayMesh:
	var b := B.new()
	var rng := _rng(1701 + variant)
	var top := Vector3(rng.randf_range(-0.1, 0.1), 0.95, rng.randf_range(-0.1, 0.1))
	_stem(b, Vector3.ZERO, top, 0.075, 0.055, 2.0 + variant, 2.0)
	# Annulus skirt under the cap.
	var ring_y := top.y * 0.78
	var rp := PackedVector3Array([Vector3(top.x * 0.8, ring_y + 0.02, top.z * 0.8), Vector3(top.x * 0.8, ring_y - 0.04, top.z * 0.8)])
	_lathe(b, rp, PackedFloat32Array([0.06, 0.11]), PackedColorArray([Color(0, 0.3, 0.5, 0.8), Color(0.5, 0.6, 0.5, 0.7)]), 12, 0.15, 5.0)
	var radius := 0.5 if variant == 0 else 0.68
	_cap(b, top, radius, radius * (0.42 if variant == 0 else 0.3), radius * 0.16, 9.0 + variant, true)
	return b.commit()


# --- Silk, roots, moss, water ---------------------------------------------------------------------

## Orb web in the local XY plane (normal +Z), radius about 0.5, centre at the origin.
## Colour a: thread opacity; r: 0 structural .. 1 sticky spiral.
static func web_orb(variant: int) -> ArrayMesh:
	var b := B.new()
	var rng := _rng(1801 + variant)
	var spokes := 11 + variant * 3
	var frame: Array[Vector3] = []
	for i in spokes:
		var a := TAU * float(i) / spokes + rng.randf_range(-0.12, 0.12)
		var r := rng.randf_range(0.42, 0.55)
		var p := Vector3(cos(a) * r, sin(a) * r, 0)
		p.z = 0.04 * (1.0 - r * 2.0) * sin(a * 2.0)
		frame.append(p)
	var hub := Vector3(rng.randf_range(-0.03, 0.03), rng.randf_range(0.0, 0.04), 0)
	var solid := Color(0, 0, 0.5, 0.8)
	var sticky := Color(1, 0, 0.5, 0.55)
	for i in spokes:
		CaveMeshes.thread(b, hub, frame[i], 0.006, solid, Vector3.BACK)
		CaveMeshes.sag_thread(b, frame[i], frame[(i + 1) % spokes], 0.01, 0.006, solid, 2, Vector3.BACK)
	# Anchor lines out to the rock.
	for i in 4:
		var f := frame[(i * spokes) / 4]
		CaveMeshes.thread(b, f, f * 1.9 + Vector3(0, 0, rng.randf_range(-0.05, 0.05)), 0.006, solid)
	# The capture spiral: segments between neighbouring spokes, slightly sagging.
	var turns := 13
	var steps := turns * spokes
	var prev := Vector3.INF
	for k in steps:
		var t := float(k) / steps
		var i := k % spokes
		var rr := lerpf(0.13, 0.9, t)
		var p := hub.lerp(frame[i], rr)
		if prev != Vector3.INF and rng.randf() > 0.06:
			CaveMeshes.thread(b, prev, p, 0.0035, sticky, Vector3.BACK)
		elif prev != Vector3.INF and rng.randf() < 0.5:
			# A broken strand dangling down.
			CaveMeshes.thread(b, prev, prev + Vector3(rng.randf_range(-0.03, 0.03), -rng.randf_range(0.05, 0.14), 0), 0.0035, sticky, Vector3.BACK)
		prev = p
	# The whole web billows gently in one direction.
	for i in b.v.size():
		var p := b.v[i]
		b.v[i] = p + Vector3(0, -0.035 * (1.0 - minf(1.0, p.length() * 2.0)), 0.05 * (1.0 - minf(1.0, p.length() * 2.0)))
	return b.commit()


## Tangled sheet web hanging from a ceiling (y = 0 at the rock, down to about -0.8).
static func web_drape() -> ArrayMesh:
	var b := B.new()
	var rng := _rng(1901)
	var anchors: Array[Vector3] = []
	for i in 9:
		anchors.append(Vector3(lerpf(-0.6, 0.6, i / 8.0) + rng.randf_range(-0.05, 0.05), 0.02, rng.randf_range(-0.15, 0.15)))
	var low: Array[Vector3] = []
	for i in 7:
		low.append(Vector3(lerpf(-0.45, 0.45, i / 6.0) + rng.randf_range(-0.06, 0.06), -rng.randf_range(0.35, 0.85), rng.randf_range(-0.1, 0.1)))
	var col := Color(0, 0, 0.5, 0.6)
	for i in 34:
		var a := anchors[rng.randi() % anchors.size()] if rng.randf() < 0.5 else low[rng.randi() % low.size()]
		var e := low[rng.randi() % low.size()]
		CaveMeshes.sag_thread(b, a, e, rng.randf_range(0.0, 0.06), 0.004, col, 3)
	for i in low.size():
		# Dust-laden strands trailing down.
		CaveMeshes.sag_thread(b, low[i], low[i] + Vector3(0, -rng.randf_range(0.1, 0.4), 0), 0.0, 0.004, Color(1, 0, 0.5, 0.45), 2)
	return b.commit()


## Hanging roots (ceiling, y = 0 at the rock), 0.6-2 m long.
static func roots(variant: int) -> ArrayMesh:
	var b := B.new()
	var rng := _rng(2001 + variant)
	CaveMeshes.blob(b, Vector3(0, 0.02, 0), Vector3(0.3, 0.06, 0.25), 1, 0.4, 6.0, 4.0 + variant, Color(0, 0, 0.5, 0.7))
	for i in (8 if variant == 0 else 12):
		var a := rng.randf() * TAU
		var start := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.25)
		var length := rng.randf_range(0.5, 1.9) * (0.7 if variant == 1 else 1.0)
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		var cols := PackedColorArray()
		var wob := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.08
		var r0 := rng.randf_range(0.012, 0.035)
		for k in 9:
			var t := float(k) / 8.0
			var p := start + Vector3(0, -t * length, 0) + wob * sin(t * 5.0 + i) * t + Vector3(sin(t * 11.0 + i) * 0.02, 0, cos(t * 9.0 + i) * 0.02) * t
			pts.append(p)
			radii.append(0.0 if k == 8 else r0 * (1.0 - t * 0.85))
			cols.append(Color(t, 0, rng.randf(), lerpf(0.6, 1.0, t)))
		CaveMeshes.tube(b, pts, radii, cols, 5, 0.15, 10.0, float(i))
		if length > 1.0:
			# A side rootlet.
			var m := pts[4]
			var sp := PackedVector3Array([m, m + Vector3(0.12, -0.15, 0.05), m + Vector3(0.18, -0.45, 0.02)])
			CaveMeshes.tube(b, sp, PackedFloat32Array([r0 * 0.4, r0 * 0.25, 0.0]), PackedColorArray([Color(0.5, 0, 0.5, 0.8), Color(0.8, 0, 0.5, 0.9), Color(1, 0, 0.5, 1)]), 4, 0.0)
	return b.commit()


## Moss carpet (floor or wall), radius about 0.7, lumpy, with cushions.
static func moss(variant: int) -> ArrayMesh:
	var b := B.new()
	var rng := _rng(2101 + variant)
	var ph := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	var rad := func(a: float) -> float: return 0.7 * (1.0 + 0.25 * sin(a * 3.0 + ph[0]) + 0.15 * sin(a * 5.0 + ph[1]) + 0.08 * sin(a * 9.0 + ph[2]))
	var hgt := func(f: float, a: float) -> float: return 0.05 * (1.0 - f * f) * (0.7 + 0.3 * sin(a * 6.0 + f * 9.0)) - (0.025 if f > 0.99 else 0.0)
	CaveMeshes.disc(b, 5, 22, rad, hgt, Color(0, 0, 0.5, 1.0), 0.04)
	for i in 6:
		var a := rng.randf() * TAU
		var d: float = rad.call(a) * rng.randf_range(0.1, 0.6)
		var r := rng.randf_range(0.06, 0.16)
		CaveMeshes.blob(b, Vector3(cos(a) * d, 0.02, sin(a) * d), Vector3(r, r * 0.45, r), 0, 0.3, 12.0, float(i), Color(0.3, 0, rng.randf(), 1.0))
	return b.commit()


## Still puddle (radius about 1). Colour r: 0 centre .. 1 shore.
static func puddle(variant: int) -> ArrayMesh:
	var b := B.new()
	var rng := _rng(2201 + variant)
	var ph := [rng.randf() * TAU, rng.randf() * TAU]
	var rad := func(a: float) -> float: return 1.0 * (1.0 + 0.22 * sin(a * 2.0 + ph[0]) + 0.12 * sin(a * 5.0 + ph[1]))
	var hgt := func(_f: float, _a: float) -> float: return 0.0
	CaveMeshes.disc(b, 3, 24, rad, hgt, Color(0, 0, 0.5, 1.0))
	return b.commit()


## Ore crust: an irregular stain of vein mineral hugging the rock (colour g = 0, the shader's
## "matrix" colour) studded with nuggets / kidneys of the ore itself (g = 1).
static func crust(variant: int) -> ArrayMesh:
	var b := B.new()
	var rng := _rng(2301 + variant)
	var ph := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	var stretch := 1.6 if variant == 1 else 1.1
	var rad := func(a: float) -> float: return 0.42 * (1.0 + 0.3 * sin(a * 2.0 + ph[0]) + 0.18 * sin(a * 5.0 + ph[1]) + 0.1 * sin(a * 11.0 + ph[2])) * lerpf(1.0, stretch, absf(cos(a)))
	var hgt := func(f: float, a: float) -> float: return 0.028 * (1.0 - f * f) + 0.012 * sin(a * 13.0 + f * 17.0) * (1.0 - f) - (0.02 if f > 0.99 else 0.0)
	CaveMeshes.disc(b, 4, 20, rad, hgt, Color(0.3, 0.0, 0.5, 0.85), 0.04)
	# Botryoidal bumps in the crust itself.
	for i in 7:
		var a := rng.randf() * TAU
		var d: float = rad.call(a) * rng.randf_range(0.0, 0.7)
		var r := rng.randf_range(0.03, 0.08)
		CaveMeshes.blob(b, Vector3(cos(a) * d, 0.0, sin(a) * d), Vector3(r, r * 0.55, r), 0, 0.2, 9.0, float(i + 40), Color(0.6, 0.0, rng.randf(), 1.0))
	# Nuggets of the ore.
	for i in (6 if variant == 0 else 9):
		var a := rng.randf() * TAU
		var d: float = rad.call(a) * sqrt(rng.randf()) * 0.75
		var r := rng.randf_range(0.015, 0.055) * (1.6 if i == 0 else 1.0)
		CaveMeshes.blob(b, Vector3(cos(a) * d, 0.01, sin(a) * d), Vector3(r, r * rng.randf_range(0.5, 0.9), r * rng.randf_range(0.7, 1.2)), 1, 0.35, 5.0, float(i + 60 + variant * 20), Color(0.8, 1.0, rng.randf(), 1.0), -INF, 0.0, true)
	return b.commit()
