class_name ArchMesh
extends RefCounted
## Geometry accumulator for modelled architecture. Pure data, so it is filled
## on worker threads; the main thread only turns `arrays()` into an ArrayMesh.
##
## Every surface carries (see architecture.gdshader):
##   UV     texture coordinates in metres (the shader applies each layer's tile size;
##          it derives the tangent frame from screen-space derivatives)
##   UV2.x  texture layer (ArchMaterials.L) + snow cover * 0.9 in the fraction
##   UV2.y  wear: moss, damp streaks and colour drift (0..1); on glass: lit at night
##   COLOR  rgb tint, a = grime (1 clean .. 0 sooty / damp), graded from `dirt_y`
## Front faces are clockwise seen from outside (Godot's convention).

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var uv2s := PackedVector2Array()
var indices := PackedInt32Array()

## Current transform applied to everything emitted (push/pop).
var xf := Transform3D.IDENTITY
var _stack: Array[Transform3D] = []

## Surface attributes for the next primitives.
var layer := 0
var tint := Color(1, 1, 1)
var grime := 1.0
var wear := 0.0
var snow := 0.0
## Grime gradient: vertices at or below `dirt_y` (mesh space) get `dirt_amount`
## darker, fading out over `dirt_h` metres. dirt_h <= 0 disables it.
var dirt_y := 0.0
var dirt_h := 0.0
var dirt_amount := 0.45


func vertex_count() -> int:
	return verts.size()


func is_empty() -> bool:
	return indices.is_empty()


func push(t: Transform3D) -> void:
	_stack.append(xf)
	xf = xf * t


func pop() -> void:
	xf = _stack.pop_back()


## Sets the surface attributes in one call. Returns self for chaining.
func mat(layer_id: int, color := Color(1, 1, 1), wear_amount := 0.0, grime_amount := 1.0) -> ArchMesh:
	layer = layer_id
	tint = color
	wear = wear_amount
	grime = grime_amount
	return self


func _alpha(p: Vector3) -> float:
	var a := grime
	if dirt_h > 0.0:
		a *= lerpf(1.0 - dirt_amount, 1.0, clampf((p.y - dirt_y) / dirt_h, 0.0, 1.0))
	return a


## A planar quad. Corners in order around the quad; the facing is fixed from `n`
## (or from the corner order when n is zero). UVs per corner, in metres. The
## tangent frame is derived in the shader, so only positions, the normal and
## UVs are stored (this is the hot path: keep it lean).
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, n := Vector3.ZERO) -> void:
	var geo := (b - a).cross(c - a)
	if geo.length_squared() < 1e-12:
		geo = (c - a).cross(d - a)
		if geo.length_squared() < 1e-12:
			return
	if n == Vector3.ZERO:
		n = -geo.normalized()
	var base := verts.size()
	var pa := xf * a
	var pb := xf * b
	var pc := xf * c
	var pd := xf * d
	verts.append(pa)
	verts.append(pb)
	verts.append(pc)
	verts.append(pd)
	var wn := (xf.basis * n).normalized()
	normals.append(wn)
	normals.append(wn)
	normals.append(wn)
	normals.append(wn)
	if dirt_h > 0.0:
		colors.append(Color(tint.r, tint.g, tint.b, _alpha(pa)))
		colors.append(Color(tint.r, tint.g, tint.b, _alpha(pb)))
		colors.append(Color(tint.r, tint.g, tint.b, _alpha(pc)))
		colors.append(Color(tint.r, tint.g, tint.b, _alpha(pd)))
	else:
		var col := Color(tint.r, tint.g, tint.b, grime)
		colors.append(col)
		colors.append(col)
		colors.append(col)
		colors.append(col)
	uvs.append(ua)
	uvs.append(ub)
	uvs.append(uc)
	uvs.append(ud)
	var u2 := Vector2(float(layer) + clampf(snow, 0.0, 1.0) * 0.9, wear)
	uv2s.append(u2)
	uv2s.append(u2)
	uv2s.append(u2)
	uv2s.append(u2)
	indices.append(base)
	if geo.dot(n) > 0.0:
		indices.append(base + 2)
		indices.append(base + 1)
		indices.append(base)
		indices.append(base + 3)
		indices.append(base + 2)
	else:
		indices.append(base + 1)
		indices.append(base + 2)
		indices.append(base)
		indices.append(base + 2)
		indices.append(base + 3)


func tri(a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, n := Vector3.ZERO) -> void:
	var geo := (b - a).cross(c - a)
	if geo.length_squared() < 1e-12:
		return
	if n == Vector3.ZERO:
		n = -geo.normalized()
	var base := verts.size()
	var pa := xf * a
	var pb := xf * b
	var pc := xf * c
	verts.append(pa)
	verts.append(pb)
	verts.append(pc)
	var wn := (xf.basis * n).normalized()
	normals.append(wn)
	normals.append(wn)
	normals.append(wn)
	colors.append(Color(tint.r, tint.g, tint.b, _alpha(pa)))
	colors.append(Color(tint.r, tint.g, tint.b, _alpha(pb)))
	colors.append(Color(tint.r, tint.g, tint.b, _alpha(pc)))
	uvs.append(ua)
	uvs.append(ub)
	uvs.append(uc)
	var u2 := Vector2(float(layer) + clampf(snow, 0.0, 1.0) * 0.9, wear)
	uv2s.append(u2)
	uv2s.append(u2)
	uv2s.append(u2)
	indices.append(base)
	if geo.dot(n) > 0.0:
		indices.append(base + 2)
		indices.append(base + 1)
	else:
		indices.append(base + 1)
		indices.append(base + 2)


## Rectangle from origin `o` spanning `u * w` and `v * h` (u, v unit and
## orthogonal). Faces u x v... i.e. the normal is v.cross(u) flipped so that
## (u right, v up) faces the viewer. UV origin `uv0` in metres; texture v runs
## down, so `v` maps to -uv.y.
func rect(o: Vector3, u: Vector3, v: Vector3, w: float, h: float, uv0 := Vector2.ZERO) -> void:
	var n := u.cross(v).normalized()
	quad(o, o + u * w, o + u * w + v * h, o + v * h,
			uv0, uv0 + Vector2(w, 0), uv0 + Vector2(w, -h), uv0 + Vector2(0, -h), n)


## Axis-aligned box in the current frame, centred at `c`. `grain` picks the
## texture's v direction on faces that contain that axis (0 x, 1 y, 2 z):
## timber grain runs along a beam's length. UVs are world-scaled and offset by
## the box position so neighbouring pieces don't repeat the same texels.
func box(c: Vector3, size: Vector3, grain := 1, skip := 0) -> void:
	var h := size * 0.5
	# Planar UVs stay continuous across boxes in one frame; separate frames
	# (beams, props) get an offset so neighbours don't repeat the same texels.
	var ofs := Vector2(fposmod(xf.origin.x * 0.37 + xf.origin.z * 0.61, 7.0), fposmod(xf.origin.y * 0.53 + xf.origin.x * 0.29, 7.0))
	# +x, -x, +y, -y, +z, -z ; skip is a bitmask in that order.
	var axes := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	for f in 6:
		if skip & (1 << f):
			continue
		var n: Vector3 = axes[f]
		var ax := f / 2
		# The two in-plane axes.
		var a1 := (ax + 1) % 3
		var a2 := (ax + 2) % 3
		# v along the grain axis if it lies in this face, else along y / z.
		var va := a2
		var ua := a1
		if grain == a1:
			va = a1
			ua = a2
		elif grain == a2:
			va = a2
			ua = a1
		elif ax != 1:
			va = 1
			ua = a1 if a2 == 1 else a2
		var uvec := Vector3.ZERO
		uvec[ua] = 1.0
		var vvec := Vector3.ZERO
		vvec[va] = 1.0
		# Orient u so that (u, v) faces outwards.
		if uvec.cross(vvec).dot(n) < 0.0:
			uvec = -uvec
		var center := c + n * h[ax]
		var o := center - uvec * h[ua] - vvec * h[va]
		rect(o, uvec, vvec, size[ua], size[va], ofs + Vector2(o.dot(uvec), -o.dot(vvec)))


## A beam from `a` to `b` with a rectangular section (width across, depth
## along `up_hint` x dir). Grain runs along the beam. `chamfer` bevels the four
## long edges (cheap highlights that sell timber up close).
func beam(a: Vector3, b: Vector3, width: float, depth: float, up_hint := Vector3.UP, chamfer := 0.0) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 1e-4:
		return
	dir /= length
	var side := up_hint.cross(dir)
	if side.length_squared() < 1e-6:
		side = Vector3.RIGHT.cross(dir) if absf(dir.x) < 0.9 else Vector3.FORWARD.cross(dir)
	side = side.normalized()
	var up := dir.cross(side).normalized()
	var basis := Basis(side, up, dir)
	var mid := (a + b) * 0.5
	push(Transform3D(basis, mid))
	if chamfer <= 0.0:
		box(Vector3.ZERO, Vector3(width, depth, length), 2)
	else:
		_chamfer_prism(width, depth, length, minf(chamfer, minf(width, depth) * 0.3))
	pop()


## Octagonal-section prism along z (a beam with bevelled long edges).
func _chamfer_prism(w: float, d: float, length: float, c: float) -> void:
	var hw := w * 0.5
	var hd := d * 0.5
	var pts := [Vector2(hw - c, hd), Vector2(hw, hd - c), Vector2(hw, -hd + c), Vector2(hw - c, -hd),
			Vector2(-hw + c, -hd), Vector2(-hw, -hd + c), Vector2(-hw, hd - c), Vector2(-hw + c, hd)]
	var hz := length * 0.5
	var run := 0.0
	var seed_ofs := absf(xf.origin.x * 0.31 + xf.origin.z * 0.17 + xf.origin.y * 0.07)
	for i in 8:
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[(i + 1) % 8]
		var e := p0.distance_to(p1)
		var n2 := Vector2(p1.y - p0.y, p0.x - p1.x).normalized()
		if n2.dot((p0 + p1) * 0.5) < 0.0:
			n2 = -n2
		var n := Vector3(n2.x, n2.y, 0)
		var u0 := run + seed_ofs
		quad(Vector3(p0.x, p0.y, -hz), Vector3(p1.x, p1.y, -hz), Vector3(p1.x, p1.y, hz), Vector3(p0.x, p0.y, hz),
				Vector2(u0, 0), Vector2(u0 + e, 0), Vector2(u0 + e, -length), Vector2(u0, -length), n)
		run += e
	# End caps (end grain).
	for s: float in [-1.0, 1.0]:
		var n := Vector3(0, 0, s)
		for i in range(1, 7):
			var a2: Vector2 = pts[0]
			var b2: Vector2 = pts[i]
			var c2: Vector2 = pts[i + 1]
			tri(Vector3(a2.x, a2.y, hz * s), Vector3(b2.x, b2.y, hz * s), Vector3(c2.x, c2.y, hz * s), a2, b2, c2, n)


## Extruded polygon: `pts` in the plane spanned by `u` (x) and `v` (y) at
## origin `o`, extruded `depth` along u.cross(v) (the front face). Sides use
## the outline length as u.
func prism(o: Vector3, u: Vector3, v: Vector3, pts: PackedVector2Array, depth: float, back := true, sides := true) -> void:
	var n := u.cross(v).normalized()
	var tris := Geometry2D.triangulate_polygon(pts)
	if tris.is_empty():
		return
	var to3 := func(p: Vector2, z: float) -> Vector3: return o + u * p.x + v * p.y + n * z
	for i in range(0, tris.size(), 3):
		var a := pts[tris[i]]
		var b := pts[tris[i + 1]]
		var c := pts[tris[i + 2]]
		tri(to3.call(a, depth), to3.call(b, depth), to3.call(c, depth), Vector2(a.x, -a.y), Vector2(b.x, -b.y), Vector2(c.x, -c.y), n)
		if back:
			tri(to3.call(a, 0.0), to3.call(b, 0.0), to3.call(c, 0.0), Vector2(-a.x, -a.y), Vector2(-b.x, -b.y), Vector2(-c.x, -c.y), -n)
	if not sides:
		return
	var centroid := Vector2.ZERO
	for p in pts:
		centroid += p
	centroid /= pts.size()
	var run := 0.0
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var e := a.distance_to(b)
		var n2 := Vector2(b.y - a.y, a.x - b.x).normalized()
		if n2.dot((a + b) * 0.5 - centroid) < 0.0:
			n2 = -n2
		var sn := (u * n2.x + v * n2.y).normalized()
		quad(to3.call(a, 0.0), to3.call(b, 0.0), to3.call(b, depth), to3.call(a, depth),
				Vector2(run, 0), Vector2(run + e, 0), Vector2(run + e, -depth), Vector2(run, -depth), sn)
		run += e


## Surface of revolution around the local y axis at `c`: profile points are
## (radius, height). Caps close the ends where the radius is non-zero.
func lathe(c: Vector3, profile: PackedVector2Array, segments := 12, cap_bottom := true, cap_top := true, phase := 0.0) -> void:
	var circ := PackedVector2Array()
	for s in segments + 1:
		var a := TAU * float(s) / segments + phase
		circ.append(Vector2(cos(a), sin(a)))
	for i in profile.size() - 1:
		var p0 := profile[i]
		var p1 := profile[i + 1]
		var slope := Vector2(p1.x - p0.x, p1.y - p0.y)
		var seg_len := slope.length()
		if seg_len < 1e-5:
			continue
		var nr := Vector2(slope.y, -slope.x) / seg_len   # outward (radial, vertical)
		var vy0 := 0.0
		for j in i:
			vy0 += profile[j].distance_to(profile[j + 1])
		for s in segments:
			var c0 := circ[s]
			var c1 := circ[s + 1]
			var am := (c0 + c1).normalized()
			var n := Vector3(am.x * nr.x, nr.y, am.y * nr.x).normalized()
			var u0 := TAU * maxf(p0.x, p1.x) * float(s) / segments
			var u1 := TAU * maxf(p0.x, p1.x) * float(s + 1) / segments
			quad(c + Vector3(c0.x * p0.x, p0.y, c0.y * p0.x), c + Vector3(c1.x * p0.x, p0.y, c1.y * p0.x),
					c + Vector3(c1.x * p1.x, p1.y, c1.y * p1.x), c + Vector3(c0.x * p1.x, p1.y, c0.y * p1.x),
					Vector2(u0, -vy0), Vector2(u1, -vy0), Vector2(u1, -vy0 - seg_len), Vector2(u0, -vy0 - seg_len), n)
	if cap_bottom and profile[0].x > 0.001:
		_disc(c + Vector3(0, profile[0].y, 0), profile[0].x, segments, Vector3.DOWN, circ)
	var last := profile[profile.size() - 1]
	if cap_top and last.x > 0.001:
		_disc(c + Vector3(0, last.y, 0), last.x, segments, Vector3.UP, circ)


func _disc(c: Vector3, r: float, segments: int, n: Vector3, circ: PackedVector2Array) -> void:
	for s in segments:
		var a := circ[s]
		var b := circ[s + 1]
		tri(c, c + Vector3(a.x * r, 0, a.y * r), c + Vector3(b.x * r, 0, b.y * r), Vector2.ZERO, a * r, b * r, n)


## Cylinder between two points (posts, poles, rails).
func cylinder(a: Vector3, b: Vector3, r0: float, r1 := -1.0, segments := 8, caps := true) -> void:
	if r1 < 0.0:
		r1 = r0
	var dir := b - a
	var length := dir.length()
	if length < 1e-4:
		return
	var y := dir / length
	var x := y.cross(Vector3.FORWARD) if absf(y.z) < 0.9 else y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	push(Transform3D(Basis(x, y, z), a))
	lathe(Vector3.ZERO, PackedVector2Array([Vector2(r0, 0.0), Vector2(r1, length)]), segments, caps, caps)
	pop()


## Height-field patch: a grid over (u, v) with per-vertex offsets along n from
## `height(u, v)` (thatch lumps, rubble). Smooth normals from the grid.
func patch(o: Vector3, u: Vector3, v: Vector3, w: float, h: float, nu: int, nv: int, height: Callable, uv0 := Vector2.ZERO) -> void:
	var n := u.cross(v).normalized()
	var pts := PackedVector3Array()
	pts.resize((nu + 1) * (nv + 1))
	for j in nv + 1:
		for i in nu + 1:
			var fu := w * float(i) / nu
			var fv := h * float(j) / nv
			pts[i + j * (nu + 1)] = o + u * fu + v * fv + n * float(height.call(fu, fv))
	for j in nv:
		for i in nu:
			var i00 := i + j * (nu + 1)
			var i10 := i00 + 1
			var i01 := i00 + nu + 1
			var i11 := i01 + 1
			var fu0 := w * float(i) / nu
			var fu1 := w * float(i + 1) / nu
			var fv0 := h * float(j) / nv
			var fv1 := h * float(j + 1) / nv
			var fn := (pts[i10] - pts[i00]).cross(pts[i01] - pts[i00]).normalized()
			if fn.dot(n) < 0.0:
				fn = -fn
			quad(pts[i00], pts[i10], pts[i11], pts[i01],
					uv0 + Vector2(fu0, -fv0), uv0 + Vector2(fu1, -fv0), uv0 + Vector2(fu1, -fv1), uv0 + Vector2(fu0, -fv1), fn)


## Arrays for ArrayMesh.add_surface_from_arrays.
func arrays() -> Array:
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = verts
	a[Mesh.ARRAY_NORMAL] = normals
	a[Mesh.ARRAY_COLOR] = colors
	a[Mesh.ARRAY_TEX_UV] = uvs
	a[Mesh.ARRAY_TEX_UV2] = uv2s
	a[Mesh.ARRAY_INDEX] = indices
	return a


## Appends another accumulator (already in this mesh's space).
func append(other: ArchMesh) -> void:
	var base := verts.size()
	verts.append_array(other.verts)
	normals.append_array(other.normals)
	colors.append_array(other.colors)
	uvs.append_array(other.uvs)
	uv2s.append_array(other.uv2s)
	for i in other.indices:
		indices.append(i + base)


func aabb() -> AABB:
	if verts.is_empty():
		return AABB()
	var box_ := AABB(verts[0], Vector3.ZERO)
	for p in verts:
		box_ = box_.expand(p)
	return box_


func to_mesh(material: Material = null) -> ArrayMesh:
	var m := ArrayMesh.new()
	if indices.is_empty():
		return m
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays())
	if material != null:
		m.surface_set_material(0, material)
	return m


## An irregular, faceted stone (rubble, cairns, boulders): a perturbed
## low-poly ellipsoid, flat-shaded, sitting on y = 0 at `c`.
func rock(c: Vector3, size: Vector3, seed_value: int, rings := 4, segs := 7) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var pts: Array[PackedVector3Array] = []
	for j in rings + 1:
		var row := PackedVector3Array()
		var phi := PI * float(j) / rings
		for i in segs:
			var th := TAU * (float(i) + (0.5 if j % 2 == 1 else 0.0)) / segs
			var k := r.randf_range(0.78, 1.12) if j > 0 and j < rings else 1.0
			var p := Vector3(sin(phi) * cos(th) * k, -cos(phi), sin(phi) * sin(th) * k)
			p.y = (p.y + 1.0) * 0.5
			if j == 0:
				p.y = 0.0
			row.append(c + p * size)
		pts.append(row)
	for j in rings:
		for i in segs:
			var a := pts[j][i]
			var b := pts[j][(i + 1) % segs]
			var d := pts[j + 1][(i + 1) % segs]
			var e := pts[j + 1][i]
			var centre := c + Vector3(0, size.y * 0.5, 0)
			var n1 := (b - a).cross(d - a).normalized()
			if n1.dot((a + b + d) / 3.0 - centre) < 0.0:
				n1 = -n1
			tri(a, b, d, Vector2(a.x + a.z, -a.y), Vector2(b.x + b.z, -b.y), Vector2(d.x + d.z, -d.y), n1)
			var n2 := (d - a).cross(e - a).normalized()
			if n2.dot((a + d + e) / 3.0 - centre) < 0.0:
				n2 = -n2
			tri(a, d, e, Vector2(a.x + a.z, -a.y), Vector2(d.x + d.z, -d.y), Vector2(e.x + e.z, -e.y), n2)
