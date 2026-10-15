class_name ItemMesh
extends RefCounted
## Procedural meshes for items: lathe (revolved profiles), lofts (blades,
## hafts, horns), bevelled tapered extrusions (axe heads, guards, plates),
## rocks, cut gems, crystals and ingots. All cached by their parameters.
## Front faces follow Godot's convention (clockwise seen from outside); every
## triangle is oriented against an outward hint so winding never matters to
## the callers.

static var _cache := {}


static func _cached(key: String, make: Callable) -> ArrayMesh:
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]


## Collects triangles, orients them outward and commits (flat or smooth).
class Builder:
	var st := SurfaceTool.new()
	var smooth := true

	func _init(smooth_normals := true) -> void:
		smooth = smooth_normals
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(0 if smooth else 0xFFFFFFFF)

	## Adds a triangle whose front face looks along `out` (outward direction).
	func tri(a: Vector3, b: Vector3, c: Vector3, out: Vector3) -> void:
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-14:
			return
		if n.dot(out) > 0.0:
			var t := b
			b = c
			c = t
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)

	## Triangle oriented away from an interior point.
	func tri_from(a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> void:
		tri(a, b, c, (a + b + c) / 3.0 - inside)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3) -> void:
		tri(a, b, c, out)
		tri(a, c, d, out)

	func commit() -> ArrayMesh:
		st.generate_normals()
		return st.commit()


# --- Lathe -------------------------------------------------------------------------------

## Revolves `profile` (Vector2(radius, y), bottom to top) around Y.
## `squash` scales X and Z (elliptical sections); `sides` facets around.
static func lathe(profile: PackedVector2Array, sides := 16, smooth := true, squash := Vector2.ONE) -> ArrayMesh:
	var key := "lathe%s|%d|%s|%s" % [str(profile), sides, smooth, squash]
	return _cached(key, func() -> ArrayMesh:
		var b := Builder.new(smooth)
		var rings: Array = []
		for pt: Vector2 in profile:
			var ring := PackedVector3Array()
			for i in sides:
				var a := TAU * float(i) / sides
				ring.append(Vector3(cos(a) * pt.x * squash.x, pt.y, sin(a) * pt.x * squash.y))
			rings.append(ring)
		for j in profile.size() - 1:
			var r0: PackedVector3Array = rings[j]
			var r1: PackedVector3Array = rings[j + 1]
			# Outward normal of a profile segment in (r, y) is (dy, -dr): the
			# solid lies to the left of the direction of travel.
			var dy := profile[j + 1].y - profile[j].y
			var dr := profile[j + 1].x - profile[j].x
			for i in sides:
				var i2 := (i + 1) % sides
				var mid := (r0[i] + r0[i2] + r1[i] + r1[i2]) * 0.25
				var radial := Vector3(mid.x, 0, mid.z).normalized()
				var out := radial * dy + Vector3(0, -dr, 0)
				b.tri(r0[i], r0[i2], r1[i2], out)
				b.tri(r0[i], r1[i2], r1[i], out)
		# Caps where the profile does not close on the axis.
		if profile[0].x > 1e-4:
			var c := Vector3(0, profile[0].y, 0)
			var r: PackedVector3Array = rings[0]
			for i in sides:
				b.tri(c, r[(i + 1) % sides], r[i], Vector3.DOWN)
		if profile[profile.size() - 1].x > 1e-4:
			var c := Vector3(0, profile[profile.size() - 1].y, 0)
			var r: PackedVector3Array = rings[rings.size() - 1]
			for i in sides:
				b.tri(c, r[i], r[(i + 1) % sides], Vector3.UP)
		return b.commit())


# --- Loft ---------------------------------------------------------------------------------

## Joins consecutive closed rings (same point count). Rings with zero area at
## the ends become points (blade tips). `caps` closes open ends.
static func loft(rings: Array, smooth := false, caps := true) -> ArrayMesh:
	var key := "loft%s|%s|%s" % [str(rings).hash(), smooth, caps]
	return _cached(key, func() -> ArrayMesh:
		var b := Builder.new(smooth)
		var n: int = (rings[0] as PackedVector3Array).size()
		var centres: Array[Vector3] = []
		for r: PackedVector3Array in rings:
			var c := Vector3.ZERO
			for p in r:
				c += p
			centres.append(c / float(r.size()))
		for j in rings.size() - 1:
			var r0: PackedVector3Array = rings[j]
			var r1: PackedVector3Array = rings[j + 1]
			var axis_c := (centres[j] + centres[j + 1]) * 0.5
			for i in n:
				var i2 := (i + 1) % n
				var mid := (r0[i] + r0[i2] + r1[i] + r1[i2]) * 0.25
				b.tri(r0[i], r0[i2], r1[i2], mid - axis_c)
				b.tri(r0[i], r1[i2], r1[i], mid - axis_c)
		if caps:
			for end: int in [0, rings.size() - 1]:
				var r: PackedVector3Array = rings[end]
				var c: Vector3 = centres[end]
				var other: Vector3 = centres[1] if end == 0 else centres[rings.size() - 2]
				var out := (c - other).normalized()
				for i in n:
					b.tri(c, r[i], r[(i + 1) % n], out)
		return b.commit())


## A ring in the XZ plane at height y (radius x/z, n sides, rotated by `phase` turns).
static func ring(y: float, rx: float, rz: float, n: int, phase := 0.0, offset := Vector2.ZERO) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in n:
		var a := TAU * (float(i) / n + phase)
		out.append(Vector3(cos(a) * rx + offset.x, y, sin(a) * rz + offset.y))
	return out


## A blade cross-section at height y: width w (X), thickness t (Z), with a
## fuller groove when `fuller` > 0. 10 points, symmetric.
static func blade_section(y: float, w: float, t: float, fuller := 0.0, x_off := 0.0) -> PackedVector3Array:
	var hw := w * 0.5
	var ht := t * 0.5
	var g := ht * (1.0 - fuller * 0.55)
	var pts := [Vector2(-hw, 0), Vector2(-hw * 0.55, ht * 0.8), Vector2(-hw * 0.2, ht), Vector2(0, g), Vector2(hw * 0.2, ht),
		Vector2(hw * 0.55, ht * 0.8), Vector2(hw, 0), Vector2(hw * 0.55, -ht * 0.8), Vector2(0, -g), Vector2(-hw * 0.55, -ht * 0.8)]
	var out := PackedVector3Array()
	for p: Vector2 in pts:
		out.append(Vector3(p.x + x_off, y, p.y))
	return out


## Sword-like blade from y0 upward: `widths` sampled evenly along `length`
## (last width ~0 is the point), thickness `t` tapering to the tip.
static func blade(length: float, widths: PackedFloat32Array, t: float, fuller := 0.6, curve := 0.0) -> ArrayMesh:
	var rings: Array = []
	var n := widths.size()
	for i in n:
		var f := float(i) / float(n - 1)
		var y := f * length
		var w := widths[i]
		var th := t * lerpf(1.0, 0.35, f)
		var fu := fuller * clampf(1.0 - f * 1.25, 0.0, 1.0)
		rings.append(blade_section(y, maxf(w, 0.0005), maxf(th, 0.0005), fu, curve * f * f))
	return loft(rings, false, true)


# --- Extrusion with bevel and per-point thickness -------------------------------------------

## Extrudes the polygon `pts` (XY plane) along Z. `half_t[i]` is the half
## thickness at point i (thin = sharp edge). `bevel` chamfers the faces.
static func plate(pts: PackedVector2Array, half_t: PackedFloat32Array, bevel := 0.004, smooth := false) -> ArrayMesh:
	var key := "plate%s|%s|%.4f|%s" % [str(pts), str(half_t), bevel, smooth]
	return _cached(key, func() -> ArrayMesh:
		var n := pts.size()
		var area := 0.0
		for i in n:
			var a := pts[i]
			var c := pts[(i + 1) % n]
			area += a.x * c.y - c.x * a.y
		var ccw := area > 0.0
		var inset := PackedVector2Array()
		var centroid := Vector2.ZERO
		for p in pts:
			centroid += p
		centroid /= float(n)
		for i in n:
			var p0 := pts[(i - 1 + n) % n]
			var p1 := pts[i]
			var p2 := pts[(i + 1) % n]
			var e1 := (p1 - p0).normalized()
			var e2 := (p2 - p1).normalized()
			var n1 := Vector2(e1.y, -e1.x) if ccw else Vector2(-e1.y, e1.x)
			var n2 := Vector2(e2.y, -e2.x) if ccw else Vector2(-e2.y, e2.x)
			var m := (n1 + n2).normalized()
			var d := bevel / maxf(m.dot(n1), 0.35)
			var b := minf(bevel, half_t[i] * 0.8)
			d = d * (b / maxf(bevel, 1e-6))
			inset.append(p1 - m * d)
		var tris := Geometry2D.triangulate_polygon(pts)
		var bld := Builder.new(smooth)
		var front := PackedVector3Array()
		var back := PackedVector3Array()
		var side_f := PackedVector3Array()
		var side_b := PackedVector3Array()
		for i in n:
			var t := half_t[i]
			var b := minf(bevel, t * 0.8)
			front.append(Vector3(inset[i].x, inset[i].y, t))
			back.append(Vector3(inset[i].x, inset[i].y, -t))
			side_f.append(Vector3(pts[i].x, pts[i].y, t - b))
			side_b.append(Vector3(pts[i].x, pts[i].y, -(t - b)))
		for k in range(0, tris.size(), 3):
			bld.tri(front[tris[k]], front[tris[k + 1]], front[tris[k + 2]], Vector3.BACK)
			bld.tri(back[tris[k]], back[tris[k + 1]], back[tris[k + 2]], Vector3.FORWARD)
		for i in n:
			var i2 := (i + 1) % n
			var mid2 := (pts[i] + pts[i2]) * 0.5
			var e := pts[i2] - pts[i]
			var out2 := Vector2(e.y, -e.x) if ccw else Vector2(-e.y, e.x)
			var out := Vector3(out2.x, out2.y, 0)
			bld.quad(front[i], front[i2], side_f[i2], side_f[i], out + Vector3(0, 0, out.length() * 0.7))
			bld.quad(side_f[i], side_f[i2], side_b[i2], side_b[i], out)
			bld.quad(side_b[i], side_b[i2], back[i2], back[i], out - Vector3(0, 0, out.length() * 0.7))
			var _m := mid2
		return bld.commit())


## Uniform-thickness plate.
static func plate_even(pts: PackedVector2Array, half_t: float, bevel := 0.004) -> ArrayMesh:
	var ts := PackedFloat32Array()
	ts.resize(pts.size())
	ts.fill(half_t)
	return plate(pts, ts, bevel)


## Bevelled box (chamfered edges).
static func bevel_box(size: Vector3, bevel := 0.006) -> ArrayMesh:
	var key := "bbox%s|%.4f" % [size, bevel]
	return _cached(key, func() -> ArrayMesh:
		var h := size * 0.5
		var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.9)
		var rings: Array = []
		for yv: Array in [[-h.y, b], [-h.y + b, 0.0], [h.y - b, 0.0], [h.y, b]]:
			var y: float = yv[0]
			var ins: float = yv[1]
			var hx := h.x - ins
			var hz := h.z - ins
			var r := PackedVector3Array([
				Vector3(-hx + b, y, -hz), Vector3(hx - b, y, -hz), Vector3(hx, y, -hz + b), Vector3(hx, y, hz - b),
				Vector3(hx - b, y, hz), Vector3(-hx + b, y, hz), Vector3(-hx, y, hz - b), Vector3(-hx, y, -hz + b)])
			rings.append(r)
		return loft(rings, false, true))


# --- Natural shapes ---------------------------------------------------------------------------

static func _ico(subdiv: int) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts: Array[Vector3] = []
	for v: Vector3 in [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
			Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]:
		verts.append(v.normalized())
	var faces: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for s in subdiv:
		var mid := {}
		var nf: Array = []
		for f: Array in faces:
			var m: Array[int] = []
			for e in 3:
				var a: int = f[e]
				var c: int = f[(e + 1) % 3]
				var k := mini(a, c) * 100000 + maxi(a, c)
				if not mid.has(k):
					verts.append(((verts[a] + verts[c]) * 0.5).normalized())
					mid[k] = verts.size() - 1
				m.append(mid[k])
			nf.append([f[0], m[0], m[2]])
			nf.append([f[1], m[1], m[0]])
			nf.append([f[2], m[2], m[1]])
			nf.append([m[0], m[1], m[2]])
		faces = nf
	return [verts, faces]


## A lumpy rock / ore chunk of about `radius`, stretched by `scale`.
static func rock(radius: float, seed_: int, roughness := 0.28, subdiv := 2, scale := Vector3.ONE, smooth := false) -> ArrayMesh:
	var key := "rock%.3f|%d|%.2f|%d|%s|%s" % [radius, seed_, roughness, subdiv, scale, smooth]
	return _cached(key, func() -> ArrayMesh:
		var ico := _ico(subdiv)
		var verts: Array[Vector3] = ico[0]
		var faces: Array = ico[1]
		var noise := FastNoiseLite.new()
		noise.seed = seed_
		noise.frequency = 1.1
		noise.fractal_octaves = 3
		var disp: Array[Vector3] = []
		for v in verts:
			var d := 1.0 + noise.get_noise_3dv(v * 1.7) * roughness * 2.0
			# Flatten facets: quantise a little for a chipped look.
			disp.append(v * d * radius * scale)
		var b := Builder.new(smooth)
		for f: Array in faces:
			b.tri(disp[f[0]], disp[f[1]], disp[f[2]], (disp[f[0]] + disp[f[1]] + disp[f[2]]))
		return b.commit())


## Brilliant-cut gem: crown with a table above the girdle, pavilion below.
static func gem_cut(radius: float, facets := 8, crown := 0.45, pavilion := 0.85, table := 0.55) -> ArrayMesh:
	var key := "gem%.3f|%d|%.2f|%.2f|%.2f" % [radius, facets, crown, pavilion, table]
	return _cached(key, func() -> ArrayMesh:
		var b := Builder.new(false)
		var girdle_t := radius * 0.06
		var top := ring(radius * crown, radius * table, radius * table, facets, 0.5 / facets)
		var g1 := ring(girdle_t, radius, radius, facets * 2)
		var g0 := ring(-girdle_t, radius, radius, facets * 2)
		var apex := Vector3(0, -radius * pavilion, 0)
		var c := Vector3.ZERO
		# Table
		var tc := Vector3(0, radius * crown, 0)
		for i in facets:
			b.tri(tc, top[i], top[(i + 1) % facets], Vector3.UP)
		# Crown: star and kite facets between the table ring and the girdle.
		for i in facets:
			var t0 := top[i]
			var t1 := top[(i + 1) % facets]
			var ga := g1[(2 * i + 1) % (facets * 2)]
			var gb := g1[(2 * i + 2) % (facets * 2)]
			var gc := g1[(2 * i + 3) % (facets * 2)]
			b.tri_from(t0, t1, gb, c)
			b.tri_from(t0, ga, gb, c)
			b.tri_from(t1, gb, gc, c)
		# Girdle band
		for i in facets * 2:
			var i2 := (i + 1) % (facets * 2)
			b.quad(g1[i], g1[i2], g0[i2], g0[i], Vector3(g1[i].x + g1[i2].x, 0, g1[i].z + g1[i2].z))
		# Pavilion
		for i in facets * 2:
			b.tri_from(g0[i], g0[(i + 1) % (facets * 2)], apex, c)
		return b.commit())


## A hexagonal crystal: prism with a pointed termination.
static func crystal(radius: float, height: float, sides := 6) -> ArrayMesh:
	var key := "crys%.3f|%.3f|%d" % [radius, height, sides]
	return _cached(key, func() -> ArrayMesh:
		var rings: Array = [ring(0.0, radius * 0.85, radius * 0.85, sides), ring(height * 0.72, radius, radius, sides),
			ring(height, radius * 0.02, radius * 0.02, sides)]
		return loft(rings, false, true))


## A trapezoidal ingot with chamfered top edges.
static func ingot(length: float, width: float, height: float) -> ArrayMesh:
	var key := "ingot%.3f|%.3f|%.3f" % [length, width, height]
	return _cached(key, func() -> ArrayMesh:
		var rings: Array = []
		for yv: Array in [[0.0, 1.0, 1.0], [height * 0.8, 0.9, 0.84], [height, 0.83, 0.7]]:
			var y: float = yv[0]
			var hl: float = length * 0.5 * float(yv[1])
			var hw: float = width * 0.5 * float(yv[2])
			var c := minf(hl, hw) * 0.12
			rings.append(PackedVector3Array([Vector3(-hl + c, y, -hw), Vector3(hl - c, y, -hw), Vector3(hl, y, -hw + c), Vector3(hl, y, hw - c),
				Vector3(hl - c, y, hw), Vector3(-hl + c, y, hw), Vector3(-hl, y, hw - c), Vector3(-hl, y, -hw + c)]))
		return loft(rings, false, true))


## A tube following `path` points with radii `radii` (horns, cords, curved hafts).
static func tube(path: PackedVector3Array, radii: PackedFloat32Array, sides := 8, smooth := true) -> ArrayMesh:
	var key := "tube%s|%s|%d|%s" % [str(path), str(radii), sides, smooth]
	return _cached(key, func() -> ArrayMesh:
		var rings: Array = []
		var up := Vector3.FORWARD
		for i in path.size():
			var dir: Vector3
			if i == 0:
				dir = path[1] - path[0]
			elif i == path.size() - 1:
				dir = path[i] - path[i - 1]
			else:
				dir = path[i + 1] - path[i - 1]
			dir = dir.normalized()
			if absf(dir.dot(up)) > 0.95:
				up = Vector3.RIGHT
			var x := dir.cross(up).normalized()
			var z := x.cross(dir).normalized()
			var r := PackedVector3Array()
			for k in sides:
				var a := TAU * float(k) / sides
				r.append(path[i] + (x * cos(a) + z * sin(a)) * maxf(radii[i], 0.0004))
			rings.append(r)
		return loft(rings, smooth, true))
