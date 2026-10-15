class_name CaveMeshes
extends RefCounted
## Procedural meshes for cave decorations (CaveDecor) and mine props (MineMeshes).
##
## Everything is grown from a few organic primitives: swept tubes with noisy
## radii (stalactites, stems, roots), displaced icospheres (nodules, rocks),
## faceted prisms (crystals), polar discs (puddles, moss, rimstone) and thin
## crossed ribbons (spider silk). Meshes are built once on the main thread.
##
## Vertex colour convention shared with the cave shaders:
##   r  0 base .. 1 tip (wet tips, crystal clarity, fungus part: 0 stem, 0.5 gills, 1 cap)
##   g  glow / special mask (crystal vs matrix, wet droplet, bioluminescence)
##   b  per-piece random
##   a  ambient occlusion (1 open .. 0 crevice)

static var _noise: FastNoiseLite


static func noise() -> FastNoiseLite:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = 1.0
		_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		_noise.fractal_octaves = 3
	return _noise


static func n3(p: Vector3, seed_offset: float) -> float:
	return noise().get_noise_3dv(p + Vector3(seed_offset * 17.13, seed_offset * 5.71, -seed_offset * 11.3))


## Indexed triangle builder with consistent outward winding and smooth normals.
class Builder:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var _flat_from := PackedInt32Array()  # vertex ranges that keep their own (flat) normals

	func vert(p: Vector3, col: Color, t := Vector2.ZERO) -> int:
		v.append(p)
		n.append(Vector3.ZERO)
		c.append(col)
		uv.append(t)
		return v.size() - 1

	## Triangle a, b, c; `outward` is any vector pointing out of the surface there.
	func tri(a: int, b: int, cc: int, outward: Vector3) -> void:
		var fn := (v[cc] - v[a]).cross(v[b] - v[a])
		if fn.dot(outward) < 0.0:
			var tmp := b
			b = cc
			cc = tmp
		idx.append(a)
		idx.append(b)
		idx.append(cc)

	func quad(a: int, b: int, cc: int, d: int, outward: Vector3) -> void:
		tri(a, b, cc, outward)
		tri(a, cc, d, outward)

	## Flat-shaded triangle with its own vertices (crystal facets).
	func flat_tri(a: Vector3, b: Vector3, cc: Vector3, outward: Vector3, ca: Color, cb: Color, ccol: Color) -> void:
		var fn := (cc - a).cross(b - a)
		if fn.dot(outward) < 0.0:
			var tp := b
			b = cc
			cc = tp
			var tc := cb
			cb = ccol
			ccol = tc
			fn = -fn
		fn = fn.normalized()
		var i := v.size()
		v.append(a)
		v.append(b)
		v.append(cc)
		for k in 3:
			n.append(fn)
			uv.append(Vector2.ZERO)
		c.append(ca)
		c.append(cb)
		c.append(ccol)
		idx.append(i)
		idx.append(i + 1)
		idx.append(i + 2)
		_flat_from.append(i)

	func commit() -> ArrayMesh:
		# Smooth normals for every vertex that is not part of a flat facet.
		var flat := PackedByteArray()
		flat.resize(v.size())
		for i in _flat_from:
			flat[i] = 1
			flat[i + 1] = 1
			flat[i + 2] = 1
		var acc := PackedVector3Array()
		acc.resize(v.size())
		for t in idx.size() / 3:
			var a := idx[t * 3]
			var b := idx[t * 3 + 1]
			var cc := idx[t * 3 + 2]
			var fn := (v[cc] - v[a]).cross(v[b] - v[a])
			acc[a] += fn
			acc[b] += fn
			acc[cc] += fn
		for i in v.size():
			if flat[i] == 0:
				var nn := acc[i]
				n[i] = nn.normalized() if nn.length_squared() > 1e-12 else Vector3.UP
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


# --- Primitives ------------------------------------------------------------------------

## Perpendicular frames along a polyline (parallel transport).
static func _frames(pts: PackedVector3Array) -> Array:
	var tangents: Array[Vector3] = []
	for i in pts.size():
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, pts.size() - 1)]
		tangents.append((b - a).normalized())
	var t0 := tangents[0]
	var nrm := Vector3.RIGHT if absf(t0.x) < 0.9 else Vector3.FORWARD
	nrm = (nrm - t0 * nrm.dot(t0)).normalized()
	var out := []
	for i in pts.size():
		var t := tangents[i]
		nrm = (nrm - t * nrm.dot(t)).normalized()
		out.append([nrm, t.cross(nrm).normalized(), t])
	return out


## Swept tube. radii[i] per point (0 closes to a point), colours per point.
## jitter: relative radial noise amplitude; nf: noise frequency (1/m); seed: noise offset.
static func tube(b: Builder, pts: PackedVector3Array, radii: PackedFloat32Array, cols: PackedColorArray, sides: int,
		jitter := 0.0, nf := 4.0, seed_value := 0.0, cap_start := false, cap_end := true) -> void:
	var frames := _frames(pts)
	var rings: Array = []
	var count := pts.size()
	for i in count:
		var f: Array = frames[i]
		var r := radii[i]
		var ring := PackedInt32Array()
		if r <= 0.0005:
			ring.append(b.vert(pts[i], cols[i], Vector2(0.5, float(i) / maxf(1, count - 1))))
		else:
			for s in sides:
				var a := TAU * float(s) / sides
				var dir: Vector3 = (f[0] as Vector3) * cos(a) + (f[1] as Vector3) * sin(a)
				var rr := r
				if jitter > 0.0:
					rr *= 1.0 + n3((pts[i] + dir * r) * nf, seed_value) * jitter
				ring.append(b.vert(pts[i] + dir * rr, cols[i], Vector2(float(s) / sides, float(i) / maxf(1, count - 1))))
		rings.append(ring)
	for i in count - 1:
		var r0: PackedInt32Array = rings[i]
		var r1: PackedInt32Array = rings[i + 1]
		var mid := (pts[i] + pts[i + 1]) * 0.5
		if r0.size() == 1 and r1.size() == 1:
			continue
		if r1.size() == 1:
			for s in sides:
				b.tri(r0[s], r0[(s + 1) % sides], r1[0], b.v[r0[s]] - pts[i])
		elif r0.size() == 1:
			for s in sides:
				b.tri(r1[s], r1[(s + 1) % sides], r0[0], b.v[r1[s]] - pts[i + 1])
		else:
			for s in sides:
				var s1 := (s + 1) % sides
				b.quad(r0[s], r0[s1], r1[s1], r1[s], (b.v[r0[s]] + b.v[r1[s1]]) * 0.5 - mid)
	if cap_end and (rings[count - 1] as PackedInt32Array).size() > 1:
		var last: PackedInt32Array = rings[count - 1]
		var tip := b.vert(pts[count - 1] + (frames[count - 1][2] as Vector3) * radii[count - 1] * 0.4, cols[count - 1], Vector2(0.5, 1.0))
		for s in sides:
			b.tri(last[s], last[(s + 1) % sides], tip, frames[count - 1][2])
	if cap_start and (rings[0] as PackedInt32Array).size() > 1:
		var first: PackedInt32Array = rings[0]
		var tip0 := b.vert(pts[0] - (frames[0][2] as Vector3) * radii[0] * 0.4, cols[0], Vector2(0.5, 0.0))
		for s in sides:
			b.tri(first[s], first[(s + 1) % sides], tip0, -(frames[0][2] as Vector3))


## Displaced icosphere (subdiv 0..2) scaled by radii, centred at c.
static func blob(b: Builder, c: Vector3, radii: Vector3, subdiv: int, amp: float, nf: float, seed_value: float, col: Color,
		flatten_below := -INF, ao_down := 0.0, faceted := false, cuts := 0) -> void:
	var sphere := _icosphere(subdiv)
	var pos: PackedVector3Array = sphere[0]
	var tris: PackedInt32Array = sphere[1]
	var wp := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	# Fracture planes: flat faces with sharp-ish edges, like broken stone.
	var planes: Array[Vector3] = []
	var offsets := PackedFloat32Array()
	for k in cuts:
		var h := seed_value * 7.31 + k * 2.17
		planes.append(Vector3(sin(h * 3.1), sin(h * 1.7 + 1.0), cos(h * 2.3)).normalized())
		offsets.append(0.5 + 0.3 * absf(sin(h * 5.3)))
	for p in pos:
		var d := p * (1.0 + n3(p * nf, seed_value) * amp)
		for k in cuts:
			var over := d.dot(planes[k]) - offsets[k]
			if over > 0.0:
				d -= planes[k] * over
		var w := c + Vector3(d.x * radii.x, d.y * radii.y, d.z * radii.z)
		if w.y < flatten_below:
			w.y = lerpf(w.y, flatten_below, 0.85)
		var cc := col
		cc.a = clampf(col.a - maxf(0.0, -p.y) * ao_down, 0.0, 1.0)
		wp.append(w)
		cols.append(cc)
		uvs.append(Vector2(atan2(p.z, p.x) / TAU + 0.5, p.y * 0.5 + 0.5))
	if faceted:
		# Fractured stone: every face keeps its own normal.
		for t in tris.size() / 3:
			var a := tris[t * 3]
			var bb := tris[t * 3 + 1]
			var cc := tris[t * 3 + 2]
			b.flat_tri(wp[a], wp[bb], wp[cc], (wp[a] + wp[bb] + wp[cc]) / 3.0 - c, cols[a], cols[bb], cols[cc])
		return
	var base := b.v.size()
	for k in wp.size():
		b.vert(wp[k], cols[k], uvs[k])
	for t in tris.size() / 3:
		var a := base + tris[t * 3]
		var bb := base + tris[t * 3 + 1]
		var cc := base + tris[t * 3 + 2]
		b.tri(a, bb, cc, (b.v[a] + b.v[bb] + b.v[cc]) / 3.0 - c)


static var _ico_cache := {}


static func _icosphere(subdiv: int) -> Array:
	if _ico_cache.has(subdiv):
		return _ico_cache[subdiv]
	var t := (1.0 + sqrt(5.0)) / 2.0
	var pts := PackedVector3Array([Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)])
	for i in pts.size():
		pts[i] = pts[i].normalized()
	var tris := PackedInt32Array([0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1])
	for s in subdiv:
		var mids := {}
		var nt := PackedInt32Array()
		for k in tris.size() / 3:
			var a := tris[k * 3]
			var b := tris[k * 3 + 1]
			var c := tris[k * 3 + 2]
			var ab := _mid(pts, mids, a, b)
			var bc := _mid(pts, mids, b, c)
			var ca := _mid(pts, mids, c, a)
			nt.append_array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca])
		tris = nt
	_ico_cache[subdiv] = [pts, tris]
	return _ico_cache[subdiv]


static func _mid(pts: PackedVector3Array, mids: Dictionary, a: int, b: int) -> int:
	var key := mini(a, b) * 100000 + maxi(a, b)
	if mids.has(key):
		return mids[key]
	pts.append(((pts[a] + pts[b]) * 0.5).normalized())
	mids[key] = pts.size() - 1
	return pts.size() - 1


## Faceted crystal: an irregular prism from `base` along `dir` with a pyramidal tip.
## col_base / col_tip: vertex colours (r clarity gradient, g = 1 crystal).
static func prism(b: Builder, base: Vector3, dir: Vector3, length: float, radius: float, sides: int, tip: float,
		rng: RandomNumberGenerator, col_base := Color(0, 1, 0, 0.6), col_tip := Color(1, 1, 0, 1)) -> void:
	dir = dir.normalized()
	var x := (Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).cross(dir).normalized()
	var z := dir.cross(x).normalized()
	var radii := PackedFloat32Array()
	var angles := PackedFloat32Array()
	for s in sides:
		radii.append(radius * rng.randf_range(0.78, 1.15))
		angles.append(TAU * (float(s) + rng.randf_range(-0.18, 0.18)) / sides)
	var shaft := maxf(length - tip, length * 0.3)
	var top_scale := rng.randf_range(0.85, 1.0)
	var apex := base + dir * length + (x * rng.randf_range(-0.2, 0.2) + z * rng.randf_range(-0.2, 0.2)) * radius
	var mid_col := col_base.lerp(col_tip, shaft / length)
	for s in sides:
		var s1 := (s + 1) % sides
		var d0 := x * cos(angles[s]) + z * sin(angles[s])
		var d1 := x * cos(angles[s1]) + z * sin(angles[s1])
		var b0 := base + d0 * radii[s]
		var b1 := base + d1 * radii[s1]
		var t0 := base + dir * shaft + d0 * radii[s] * top_scale
		var t1 := base + dir * shaft + d1 * radii[s1] * top_scale
		var out := (d0 + d1) * 0.5
		b.flat_tri(b0, b1, t1, out, col_base, col_base, mid_col)
		b.flat_tri(b0, t1, t0, out, col_base, mid_col, mid_col)
		b.flat_tri(t0, t1, apex, out + dir * 0.5, mid_col, mid_col, col_tip)


## Polar disc around the origin in XZ. radius_fn(angle) -> metres; height_fn(r01, angle) -> y.
## Colour r = radial position 0 centre .. 1 edge.
static func disc(b: Builder, rings: int, segs: int, radius_fn: Callable, height_fn: Callable, col: Color, skirt := 0.0) -> void:
	var centre := b.vert(Vector3(0, height_fn.call(0.0, 0.0), 0), Color(0.0, col.g, col.b, col.a), Vector2(0.5, 0.5))
	var prev := PackedInt32Array()
	for ring in range(1, rings + 1):
		var f := float(ring) / rings
		var cur := PackedInt32Array()
		for s in segs:
			var a := TAU * float(s) / segs
			var r: float = radius_fn.call(a) * f
			var p := Vector3(cos(a) * r, height_fn.call(f, a), sin(a) * r)
			cur.append(b.vert(p, Color(f, col.g, col.b, col.a), Vector2(0.5 + cos(a) * f * 0.5, 0.5 + sin(a) * f * 0.5)))
		for s in segs:
			var s1 := (s + 1) % segs
			if ring == 1:
				b.tri(centre, cur[s], cur[s1], Vector3.UP)
			else:
				b.quad(prev[s], cur[s], cur[s1], prev[s1], Vector3.UP)
		prev = cur
	if skirt > 0.0:
		# A short apron down into the ground so the edge never floats.
		var low := PackedInt32Array()
		for s in segs:
			var p := b.v[prev[s]]
			low.append(b.vert(Vector3(p.x * 0.97, p.y - skirt, p.z * 0.97), Color(1.0, col.g, col.b, col.a * 0.5), b.uv[prev[s]]))
		for s in segs:
			var s1 := (s + 1) % segs
			var out := Vector3(b.v[prev[s]].x, 0, b.v[prev[s]].z)
			b.quad(prev[s], prev[s1], low[s1], low[s], out)


## Two crossed thin ribbons along a -> b (silk threads, wires). alpha in colour a.
## plane_normal set: a single ribbon lying in that plane (orb webs, seen face on).
static func thread(b: Builder, a: Vector3, e: Vector3, width: float, col: Color, plane_normal := Vector3.ZERO) -> void:
	var d := e - a
	var len := d.length()
	if len < 0.001:
		return
	d /= len
	var side := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
	var up := d.cross(side).normalized()
	var widths: Array[Vector3] = [side * width * 0.5, up * width * 0.5]
	if plane_normal != Vector3.ZERO:
		widths = [d.cross(plane_normal).normalized() * width * 0.5]
	for w: Vector3 in widths:
		var i0 := b.vert(a - w, col, Vector2(0, 0))
		var i1 := b.vert(a + w, col, Vector2(1, 0))
		var i2 := b.vert(e + w, col, Vector2(1, 1))
		var i3 := b.vert(e - w, col, Vector2(0, 1))
		var nrm := w.cross(d)
		b.quad(i0, i1, i2, i3, nrm)


## Sagging thread between a and e (catenary-ish), `sag` metres down at the middle.
static func sag_thread(b: Builder, a: Vector3, e: Vector3, sag: float, width: float, col: Color, segs := 4, plane_normal := Vector3.ZERO) -> void:
	var prev := a
	for i in range(1, segs + 1):
		var t := float(i) / segs
		var p := a.lerp(e, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		thread(b, prev, p, width, col, plane_normal)
		prev = p
