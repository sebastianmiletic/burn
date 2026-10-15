class_name ArenaKit
extends RefCounted
## Thread-safe mesh accumulator for the boss arenas (pure data, no scene access).
##
## Geometry is written in the coordinates of the current transform (`push`/`pop`)
## with the current material state (`mat`). Every vertex carries:
##   UV     texture coordinates in metres * the layer's scale (V grows downwards on walls)
##   UV2    x = material code (see below), y = emission strength
##   COLOR  rgb = tint (or emission colour), a = baked ambient occlusion
## Material codes (arena.gdshader):
##   0..23   TerrainTextures layer, mapped with the mesh UVs
##   50..73  the same layer mapped triplanar in world space (rocks, cave walls, rubble)
##   IRON, CLOTH, GLOW, GOLD, LIQUID, BONE: procedural surfaces
## Triangles are oriented from the intended normals, so primitives never care
## about winding.

# TerrainTextures.L mirrors (the shared texture arrays).
const LUSH := 0
const DRY := 1
const DIRT := 2
const FOREST := 3
const ROCK := 4
const SAND := 5
const SNOW := 6
const TRAIL := 7
const MUD := 8
const ASH := 9
const DARK := 10
const MARBLE := 11
const SANDSTONE := 12
const CLAY := 13
const GRANITE := 14
const LIMESTONE := 15
const MOSSY := 16
const PLANKS := 17
const BARK := 18
const COBBLE := 19
const CASTLE := 20
const MOSSY_WALL := 21
const THATCH := 22
const CARVED := 23
const TRI := 50
const IRON := 100
const CLOTH := 101
const GLOW := 102
const GOLD := 103
const LIQUID := 104
const BONE := 105

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var uvs := PackedVector2Array()
var uv2s := PackedVector2Array()
var cols := PackedColorArray()
var idx := PackedInt32Array()

var xf := Transform3D.IDENTITY
var _nb := Basis.IDENTITY
var _stack: Array[Transform3D] = []

var layer := float(ROCK)
var tint := Color(1, 1, 1, 1)
var uv_scale := 0.5
var emit := 0.0
## World-space height of the floor the current piece stands on: vertices
## near it are darkened (contact shadow / grime). -INF disables.
var ao_floor := -INF
var ao_span := 1.6
var ao_min := 0.5
## Raw mode (silk, flows): UVs are written unscaled and UV2 = (layer, emit) is free data.
var raw := false

var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()


func _init(seed_value := 1) -> void:
	rng.seed = seed_value
	noise.seed = seed_value
	noise.frequency = 0.6
	noise.fractal_octaves = 3


# --- State ------------------------------------------------------------------------

func mat(code: int, color := Color(1, 1, 1), scale := 0.5, emission := 0.0) -> void:
	layer = float(code)
	tint = color
	uv_scale = scale
	emit = emission


## Random brightness variation of the current tint (per piece).
func vary(amount := 0.08) -> void:
	var f := 1.0 + rng.randf_range(-amount, amount)
	tint = Color(tint.r * f, tint.g * f, tint.b * f, tint.a)


func push(t: Transform3D) -> void:
	_stack.append(xf)
	xf = xf * t
	_nb = xf.basis.inverse().transposed()


func push_at(pos: Vector3, yaw := 0.0, scale := Vector3.ONE) -> void:
	push(Transform3D(Basis(Vector3.UP, yaw).scaled(scale), pos))


func pop() -> void:
	xf = _stack.pop_back()
	_nb = xf.basis.inverse().transposed()


func vertex_count() -> int:
	return verts.size()


# --- Raw triangles -------------------------------------------------------------------

func _v(p: Vector3, n: Vector3, uv: Vector2) -> int:
	var wp := xf * p
	verts.append(wp)
	norms.append((_nb * n).normalized())
	# Triplanar and bone surfaces ignore mesh UVs: UV.x carries their scale.
	if raw:
		uvs.append(uv)
	else:
		uvs.append(Vector2(uv_scale, 0.0) if (layer >= TRI and layer < IRON) or layer == BONE else uv * uv_scale)
	uv2s.append(Vector2(layer, emit))
	var ao := tint.a
	if ao_floor > -1e8:
		ao *= lerpf(ao_min, 1.0, clampf((wp.y - ao_floor) / ao_span, 0.0, 1.0))
	cols.append(Color(tint.r, tint.g, tint.b, ao))
	return verts.size() - 1


## Index triangle, flipped if needed so it faces along its vertex normals.
func _t(a: int, b: int, c: int) -> void:
	var face := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	if face.dot(norms[a] + norms[b] + norms[c]) > 0.0:
		idx.append(a)
		idx.append(c)
		idx.append(b)
	else:
		idx.append(a)
		idx.append(b)
		idx.append(c)


func tri(a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, n := Vector3.ZERO) -> void:
	if n == Vector3.ZERO:
		n = (b - a).cross(c - a).normalized()
	_t(_v(a, n, ua), _v(b, n, ub), _v(c, n, uc))


## Flat quad a-b-c-d (any winding); n = outward normal (computed if zero).
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, n := Vector3.ZERO) -> void:
	if n == Vector3.ZERO:
		n = (b - a).cross(c - a).normalized()
		if n == Vector3.ZERO:
			n = (c - a).cross(d - a).normalized()
	var i0 := _v(a, n, ua)
	var i1 := _v(b, n, ub)
	var i2 := _v(c, n, uc)
	var i3 := _v(d, n, ud)
	_t(i0, i1, i2)
	_t(i0, i2, i3)


## Planar UVs for a face with normal n: u along the horizontal tangent, v down.
static func face_uv(p: Vector3, n: Vector3) -> Vector2:
	if absf(n.y) > 0.7:
		return Vector2(p.x, p.z)
	var t := Vector3(-n.z, 0, n.x).normalized()
	return Vector2(p.dot(t), -p.y)


## Quad with automatic planar UVs.
func pquad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n := Vector3.ZERO) -> void:
	if n == Vector3.ZERO:
		n = (b - a).cross(c - a).normalized()
		if n == Vector3.ZERO:
			n = (c - a).cross(d - a).normalized()
	quad(a, b, c, d, face_uv(a, n), face_uv(b, n), face_uv(c, n), face_uv(d, n), n)


func ptri(a: Vector3, b: Vector3, c: Vector3, n := Vector3.ZERO) -> void:
	if n == Vector3.ZERO:
		n = (b - a).cross(c - a).normalized()
	tri(a, b, c, face_uv(a, n), face_uv(b, n), face_uv(c, n), n)


# --- Boxes -----------------------------------------------------------------------------

## Axis-aligned box (in current transform) with an optional chamfer on every edge.
## skip_bottom drops the underside (pieces resting on floors).
func box(center: Vector3, size: Vector3, bevel := 0.0, skip_bottom := true) -> void:
	var h := size * 0.5
	var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.9)
	if b <= 0.001:
		var c := center
		var x := h.x
		var y := h.y
		var z := h.z
		pquad(c + Vector3(-x, y, -z), c + Vector3(x, y, -z), c + Vector3(x, y, z), c + Vector3(-x, y, z), Vector3.UP)
		if not skip_bottom:
			pquad(c + Vector3(-x, -y, -z), c + Vector3(x, -y, -z), c + Vector3(x, -y, z), c + Vector3(-x, -y, z), Vector3.DOWN)
		pquad(c + Vector3(-x, -y, z), c + Vector3(x, -y, z), c + Vector3(x, y, z), c + Vector3(-x, y, z), Vector3.BACK)
		pquad(c + Vector3(-x, -y, -z), c + Vector3(x, -y, -z), c + Vector3(x, y, -z), c + Vector3(-x, y, -z), Vector3.FORWARD)
		pquad(c + Vector3(x, -y, -z), c + Vector3(x, -y, z), c + Vector3(x, y, z), c + Vector3(x, y, -z), Vector3.RIGHT)
		pquad(c + Vector3(-x, -y, -z), c + Vector3(-x, -y, z), c + Vector3(-x, y, z), c + Vector3(-x, y, -z), Vector3.LEFT)
		return
	# Chamfered box: 6 inset faces, 12 edge strips, 8 corner triangles.
	var ix := h.x - b
	var iy := h.y - b
	var iz := h.z - b
	var c := center
	# faces
	pquad(c + Vector3(-ix, h.y, -iz), c + Vector3(ix, h.y, -iz), c + Vector3(ix, h.y, iz), c + Vector3(-ix, h.y, iz), Vector3.UP)
	if not skip_bottom:
		pquad(c + Vector3(-ix, -h.y, -iz), c + Vector3(ix, -h.y, -iz), c + Vector3(ix, -h.y, iz), c + Vector3(-ix, -h.y, iz), Vector3.DOWN)
	pquad(c + Vector3(-ix, -iy, h.z), c + Vector3(ix, -iy, h.z), c + Vector3(ix, iy, h.z), c + Vector3(-ix, iy, h.z), Vector3.BACK)
	pquad(c + Vector3(-ix, -iy, -h.z), c + Vector3(ix, -iy, -h.z), c + Vector3(ix, iy, -h.z), c + Vector3(-ix, iy, -h.z), Vector3.FORWARD)
	pquad(c + Vector3(h.x, -iy, -iz), c + Vector3(h.x, -iy, iz), c + Vector3(h.x, iy, iz), c + Vector3(h.x, iy, -iz), Vector3.RIGHT)
	pquad(c + Vector3(-h.x, -iy, -iz), c + Vector3(-h.x, -iy, iz), c + Vector3(-h.x, iy, iz), c + Vector3(-h.x, iy, -iz), Vector3.LEFT)
	# edges around the top
	for sx: float in [-1.0, 1.0]:
		pquad(c + Vector3(sx * ix, h.y, -iz), c + Vector3(sx * ix, h.y, iz), c + Vector3(sx * h.x, iy, iz), c + Vector3(sx * h.x, iy, -iz), Vector3(sx, 1, 0).normalized())
		if not skip_bottom:
			pquad(c + Vector3(sx * ix, -h.y, -iz), c + Vector3(sx * ix, -h.y, iz), c + Vector3(sx * h.x, -iy, iz), c + Vector3(sx * h.x, -iy, -iz), Vector3(sx, -1, 0).normalized())
	for sz: float in [-1.0, 1.0]:
		pquad(c + Vector3(-ix, h.y, sz * iz), c + Vector3(ix, h.y, sz * iz), c + Vector3(ix, iy, sz * h.z), c + Vector3(-ix, iy, sz * h.z), Vector3(0, 1, sz).normalized())
		if not skip_bottom:
			pquad(c + Vector3(-ix, -h.y, sz * iz), c + Vector3(ix, -h.y, sz * iz), c + Vector3(ix, -iy, sz * h.z), c + Vector3(-ix, -iy, sz * h.z), Vector3(0, -1, sz).normalized())
	# vertical edges
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			pquad(c + Vector3(sx * h.x, -iy, sz * iz), c + Vector3(sx * ix, -iy, sz * h.z), c + Vector3(sx * ix, iy, sz * h.z), c + Vector3(sx * h.x, iy, sz * iz), Vector3(sx, 0, sz).normalized())
			ptri(c + Vector3(sx * ix, h.y, sz * iz), c + Vector3(sx * h.x, iy, sz * iz), c + Vector3(sx * ix, iy, sz * h.z), Vector3(sx, 1, sz).normalized())
			if not skip_bottom:
				ptri(c + Vector3(sx * ix, -h.y, sz * iz), c + Vector3(sx * h.x, -iy, sz * iz), c + Vector3(sx * ix, -iy, sz * h.z), Vector3(sx, -1, sz).normalized())


## A box between two points (beams, rails, struts): square section `w` x `t`.
func beam(a: Vector3, b: Vector3, w: float, t := -1.0, bevel := 0.02, up_hint := Vector3.UP) -> void:
	if t < 0.0:
		t = w
	var d := b - a
	var length := d.length()
	if length < 0.001:
		return
	var z := d / length
	var x := up_hint.cross(z)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT.cross(z)
	x = x.normalized()
	var y := z.cross(x).normalized()
	push(Transform3D(Basis(x, y, z), (a + b) * 0.5))
	box(Vector3.ZERO, Vector3(w, t, length), bevel, false)
	pop()


# --- Extrusions -----------------------------------------------------------------------

## Closed polygon in the local XY plane extruded from z = z0 to z1 (caps optional).
func extrude(poly: PackedVector2Array, z0: float, z1: float, caps := true, smooth := false) -> void:
	var n := poly.size()
	var centroid := Vector2.ZERO
	for p in poly:
		centroid += p
	centroid /= n
	var area := 0.0
	for i in n:
		area += poly[i].cross(poly[(i + 1) % n])
	var ccw := area > 0.0
	var run := 0.0
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var e := b - a
		var out := Vector2(e.y, -e.x).normalized() if ccw else Vector2(-e.y, e.x).normalized()
		var nrm := Vector3(out.x, out.y, 0)
		var l := e.length()
		if smooth:
			var pa := poly[(i - 1 + n) % n]
			var nb := poly[(i + 2) % n]
			var na := _edge_out(pa, a, ccw) + out
			var nb2 := _edge_out(b, nb, ccw) + out
			var i0 := _v(Vector3(a.x, a.y, z0), Vector3(na.x, na.y, 0).normalized(), Vector2(run, z0))
			var i1 := _v(Vector3(b.x, b.y, z0), Vector3(nb2.x, nb2.y, 0).normalized(), Vector2(run + l, z0))
			var i2 := _v(Vector3(b.x, b.y, z1), Vector3(nb2.x, nb2.y, 0).normalized(), Vector2(run + l, z1))
			var i3 := _v(Vector3(a.x, a.y, z1), Vector3(na.x, na.y, 0).normalized(), Vector2(run, z1))
			_t(i0, i1, i2)
			_t(i0, i2, i3)
		else:
			quad(Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z0), Vector3(b.x, b.y, z1), Vector3(a.x, a.y, z1),
					Vector2(run, -a.y if absf(out.y) < 0.7 else z0), Vector2(run + l, -b.y if absf(out.y) < 0.7 else z0),
					Vector2(run + l, -b.y if absf(out.y) < 0.7 else z1), Vector2(run, -a.y if absf(out.y) < 0.7 else z1), nrm)
		run += l
	if caps:
		var tris := Geometry2D.triangulate_polygon(poly)
		for i in range(0, tris.size(), 3):
			var a := poly[tris[i]]
			var b := poly[tris[i + 1]]
			var c := poly[tris[i + 2]]
			tri(Vector3(a.x, a.y, z1), Vector3(b.x, b.y, z1), Vector3(c.x, c.y, z1), Vector2(a.x, -a.y), Vector2(b.x, -b.y), Vector2(c.x, -c.y), Vector3.BACK)
			tri(Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z0), Vector3(c.x, c.y, z0), Vector2(-a.x, -a.y), Vector2(-b.x, -b.y), Vector2(-c.x, -c.y), Vector3.FORWARD)


static func _edge_out(a: Vector2, b: Vector2, ccw: bool) -> Vector2:
	var e := b - a
	return Vector2(e.y, -e.x).normalized() if ccw else Vector2(-e.y, e.x).normalized()


## A moulding: 2D profile (x = outwards, y = up; open polyline) swept along a
## straight run from a to b on the local XZ plane, profile normal facing `out`.
func moulding(a: Vector3, b: Vector3, out: Vector3, profile: PackedVector2Array) -> void:
	var along := (b - a)
	var length := along.length()
	if length < 0.001:
		return
	out = out.normalized()
	for i in profile.size() - 1:
		var p0 := profile[i]
		var p1 := profile[i + 1]
		var seg := p1 - p0
		var n2 := Vector2(seg.y, -seg.x).normalized()
		var nrm := (out * n2.x + Vector3.UP * n2.y).normalized()
		var q0 := a + out * p0.x + Vector3.UP * p0.y
		var q1 := b + out * p0.x + Vector3.UP * p0.y
		var q2 := b + out * p1.x + Vector3.UP * p1.y
		var q3 := a + out * p1.x + Vector3.UP * p1.y
		var v0 := -p0.y if absf(nrm.y) < 0.7 else p0.x
		var v1 := -p1.y if absf(nrm.y) < 0.7 else p1.x
		quad(q0, q1, q2, q3, Vector2(0, v0), Vector2(length, v0), Vector2(length, v1), Vector2(0, v1), nrm)


# --- Lathe / sweep ----------------------------------------------------------------

## Surface of revolution around the local Y axis. profile: Vector2(radius, y),
## bottom to top. Smooth around, creased where the profile turns sharply.
## a0..a1 limits the sweep (radians) for broken or half shapes.
func lathe(profile: PackedVector2Array, segments := 16, a0 := 0.0, a1 := TAU, jitter := 0.0) -> void:
	var full := is_equal_approx(a1 - a0, TAU)
	var cols_n := segments + 1
	var m := profile.size()
	# Closed loops drawn clockwise in (r, y) get their normals flipped so they face out.
	var area := 0.0
	for j in m:
		area += profile[j].cross(profile[(j + 1) % m])
	var flip := -1.0 if area < -1e-4 else 1.0
	# Per profile segment: own vertex rows so creases stay sharp.
	var vlen := 0.0
	for j in m - 1:
		var p0 := profile[j]
		var p1 := profile[j + 1]
		var seg := p1 - p0
		var sl := seg.length()
		if sl < 1e-5:
			continue
		var n2 := Vector2(seg.y, -seg.x).normalized() * flip  # outward for bottom-to-top profiles
		var rows := []
		for r in 2:
			var p := p0 if r == 0 else p1
			var row := PackedInt32Array()
			for i in cols_n:
				var t := float(i) / segments
				var ang := lerpf(a0, a1, t)
				var rad := p.x
				if jitter > 0.0 and rad > 0.01:
					var k := i % segments if full else i
					rad *= 1.0 + jitter * noise.get_noise_2d(float(k) * 3.1, p.y * 2.0)
				var dir := Vector3(cos(ang), 0, sin(ang))
				var pos := dir * rad + Vector3(0, p.y, 0)
				var nrm := (dir * n2.x + Vector3.UP * n2.y).normalized()
				var u := ang * maxf(0.25, (p0.x + p1.x) * 0.5)
				var uv := Vector2(u, -(vlen + (sl if r == 1 else 0.0))) if absf(n2.y) < 0.75 else Vector2(pos.x, pos.z)
				row.append(_v(pos, nrm, uv))
			rows.append(row)
		for i in segments:
			var r0: PackedInt32Array = rows[0]
			var r1: PackedInt32Array = rows[1]
			_t(r0[i], r0[i + 1], r1[i + 1])
			_t(r0[i], r1[i + 1], r1[i])
		vlen += sl
	if not full:
		# Close the cut faces with the (implicitly closed) profile polygon.
		var tris := Geometry2D.triangulate_polygon(profile)
		for ang: float in [a0, a1]:
			var dir := Vector3(cos(ang), 0, sin(ang))
			var nrm := Vector3(-sin(ang), 0, cos(ang)) * (-1.0 if ang == a0 else 1.0)
			for i in range(0, tris.size(), 3):
				var pa := profile[tris[i]]
				var pb := profile[tris[i + 1]]
				var pc := profile[tris[i + 2]]
				ptri(dir * pa.x + Vector3(0, pa.y, 0), dir * pb.x + Vector3(0, pb.y, 0), dir * pc.x + Vector3(0, pc.y, 0), nrm)


## Tube along a path. radii: one per path point (round section) with `sides`.
## closed_ends caps both ends with a point. ry_scale flattens the section.
func sweep(path: PackedVector3Array, radii: PackedFloat32Array, sides := 8, ry_scale := 1.0, up_hint := Vector3.UP, cap := true) -> void:
	var n := path.size()
	if n < 2:
		return
	var frames := _frames(path, up_hint)
	var rings := []
	var vlen := 0.0
	for i in n:
		if i > 0:
			vlen += path[i].distance_to(path[i - 1])
		var f: Basis = frames[i]
		var ring := PackedInt32Array()
		var r := radii[i]
		for s in sides + 1:
			var a := TAU * float(s) / sides
			var off := f.x * cos(a) * r + f.y * sin(a) * r * ry_scale
			var nrm := (f.x * cos(a) * ry_scale + f.y * sin(a)).normalized()
			ring.append(_v(path[i] + off, nrm, Vector2(a * maxf(r, 0.05) * 1.0, -vlen)))
		rings.append(ring)
	for i in n - 1:
		var r0: PackedInt32Array = rings[i]
		var r1: PackedInt32Array = rings[i + 1]
		for s in sides:
			_t(r0[s], r0[s + 1], r1[s + 1])
			_t(r0[s], r1[s + 1], r1[s])
	if cap:
		for e: int in [0, n - 1]:
			if radii[e] < 0.005:
				continue
			var f: Basis = frames[e]
			var dirn := -f.z if e == 0 else f.z
			var tip := _v(path[e] + dirn * radii[e] * 0.3, dirn, Vector2.ZERO)
			var ring: PackedInt32Array = rings[e]
			for s in sides:
				_t(tip, ring[s], ring[s + 1])


## Parallel-transported frames along a path: Basis(x, y, z = tangent).
static func _frames(path: PackedVector3Array, up_hint: Vector3) -> Array:
	var n := path.size()
	var out := []
	var up := up_hint
	for i in n:
		var a := path[maxi(0, i - 1)]
		var b := path[mini(n - 1, i + 1)]
		var t := (b - a).normalized()
		if t == Vector3.ZERO:
			t = Vector3.FORWARD
		var x := up.cross(t)
		if x.length_squared() < 1e-6:
			x = Vector3.RIGHT.cross(t)
			if x.length_squared() < 1e-6:
				x = Vector3.FORWARD.cross(t)
		x = x.normalized()
		var y := t.cross(x).normalized()
		up = y
		out.append(Basis(x, y, t))
	return out


## Quadratic bezier points.
static func bezier(p0: Vector3, p1: Vector3, p2: Vector3, steps: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in steps + 1:
		var t := float(i) / steps
		out.append(p0.lerp(p1, t).lerp(p1.lerp(p2, t), t))
	return out


## A hanging (catenary-like) curve between a and b sagging by `sag` metres.
static func sag_curve(a: Vector3, b: Vector3, sag: float, steps: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in steps + 1:
		var t := float(i) / steps
		out.append(a.lerp(b, t) + Vector3(0, -sag * 4.0 * t * (1.0 - t), 0))
	return out


# --- Organic --------------------------------------------------------------------------

## A lumpy rock / boulder: subdivided octahedron displaced by noise. Triplanar
## material recommended. flat_base cuts it off below y = -radii.y * flat_base.
func rock(center: Vector3, radii: Vector3, lumps := 0.25, detail := 3, seed_value := 0, flat_base := 0.6, sharp := 0.0) -> void:
	var base := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	var faces := [[0, 2, 4], [4, 2, 1], [1, 2, 5], [5, 2, 0], [4, 3, 0], [1, 3, 4], [5, 3, 1], [0, 3, 5]]
	var tris: Array = []
	for f: Array in faces:
		tris.append([base[f[0]], base[f[1]], base[f[2]]])
	for d in detail:
		var next: Array = []
		for t: Array in tris:
			var a: Vector3 = t[0]
			var b: Vector3 = t[1]
			var c: Vector3 = t[2]
			var ab := ((a + b) * 0.5).normalized()
			var bc := ((b + c) * 0.5).normalized()
			var ca := ((c + a) * 0.5).normalized()
			next.append([a, ab, ca])
			next.append([ab, b, bc])
			next.append([ca, bc, c])
			next.append([ab, bc, ca])
		tris = next
	var nz := FastNoiseLite.new()
	nz.seed = seed_value
	nz.frequency = 1.1
	nz.fractal_octaves = 3
	var cache := {}
	var disp := func(dir: Vector3) -> Vector3:
		var key := Vector3i((dir * 1000.0).round())
		if cache.has(key):
			return cache[key]
		var nv := nz.get_noise_3dv(dir * 1.6)
		if sharp > 0.0:
			nv = lerpf(nv, -absf(nv) * 2.0 + 0.5, sharp)
		var p := dir * radii * (1.0 + nv * lumps)
		if p.y < -radii.y * flat_base:
			p.y = -radii.y * flat_base + (p.y + radii.y * flat_base) * 0.15
		cache[key] = p
		return p
	# Smooth normals by averaging face normals per direction.
	var acc := {}
	var flat: Array = []
	for t: Array in tris:
		var pa: Vector3 = disp.call(t[0])
		var pb: Vector3 = disp.call(t[1])
		var pc: Vector3 = disp.call(t[2])
		var fn := (pb - pa).cross(pc - pa)
		if fn.dot(pa + pb + pc) < 0.0:
			fn = -fn
		for k in 3:
			var key := Vector3i(((t[k] as Vector3) * 1000.0).round())
			acc[key] = acc.get(key, Vector3.ZERO) + fn
		flat.append([pa, pb, pc, t[0], t[1], t[2]])
	for f: Array in flat:
		var ids := PackedInt32Array()
		for k in 3:
			var p: Vector3 = f[k]
			var key := Vector3i(((f[k + 3] as Vector3) * 1000.0).round())
			var nrm: Vector3 = (acc[key] as Vector3).normalized()
			ids.append(_v(center + p, nrm, Vector2(p.x + p.y, p.z - p.y)))
		_t(ids[0], ids[1], ids[2])


## Tapered spike / stalactite: a jittered cone along `dir`.
func spike(base_pos: Vector3, dir: Vector3, length: float, radius: float, sides := 7, seed_value := 0) -> void:
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	var steps := 5
	var bend := Vector3(sin(seed_value * 1.7), 0, cos(seed_value * 2.3)) * length * 0.06
	for i in steps + 1:
		var t := float(i) / steps
		path.append(base_pos + dir * length * t + bend * t * t)
		radii.append(radius * pow(1.0 - t, 1.25) + 0.01)
	sweep(path, radii, sides, 1.0, Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT, false)


# --- Architecture helpers -------------------------------------------------------

## Round column on a square plinth with mouldings. style: "plain", "fluted",
## "carved" (banded). broken > 0 snaps the shaft at that fraction with a jagged top.
func column(base: Vector3, height: float, radius: float, style := "plain", broken := 0.0, segments := 16) -> void:
	push_at(base)
	var r := radius
	var plinth := r * 1.45
	box(Vector3(0, r * 0.2, 0), Vector3(plinth * 2.0, r * 0.4, plinth * 2.0), r * 0.06)
	lathe(PackedVector2Array([Vector2(r * 1.3, r * 0.4), Vector2(r * 1.3, r * 0.52), Vector2(r * 1.18, r * 0.62),
			Vector2(r * 1.12, r * 0.7), Vector2(r * 1.05, r * 0.78)]), segments)
	var shaft_top := height - r * 1.1
	var top := shaft_top if broken <= 0.0 else lerpf(r * 1.2, shaft_top, broken)
	if style == "fluted":
		var flutes := 12
		var prof := PackedVector2Array()
		for i in flutes * 3:
			var a := TAU * float(i) / (flutes * 3)
			var dip := 0.0 if i % 3 == 0 else 0.06
			prof.append(Vector2(cos(a), sin(a)) * r * (1.0 - dip))
		push(Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0, r * 0.78, 0)))
		extrude(prof, 0.0, top - r * 0.78, false, true)
		pop()
	else:
		var prof := PackedVector2Array()
		var steps := 6
		for i in steps + 1:
			var t := float(i) / steps
			var y := lerpf(r * 0.78, top, t)
			var entasis := 1.0 - 0.06 * t * t
			prof.append(Vector2(r * entasis, y))
		lathe(prof, segments)
		if style == "carved":
			for k in 3:
				var y := lerpf(r * 1.5, top - r * 0.5, (k + 1) / 4.0)
				if y < top - 0.2:
					lathe(PackedVector2Array([Vector2(r * 0.98, y - 0.12), Vector2(r * 1.08, y - 0.08), Vector2(r * 1.08, y + 0.08), Vector2(r * 0.98, y + 0.12)]), segments)
	if broken > 0.0:
		_broken_top(top, r * 0.98, segments)
	else:
		lathe(PackedVector2Array([Vector2(r * 0.94, shaft_top), Vector2(r * 1.05, shaft_top + r * 0.1), Vector2(r * 1.05, shaft_top + r * 0.2),
				Vector2(r * 1.0, shaft_top + r * 0.3), Vector2(r * 1.35, shaft_top + r * 0.75)]), segments)
		box(Vector3(0, shaft_top + r * 0.92, 0), Vector3(r * 2.9, r * 0.35, r * 2.9), r * 0.05, false)
	pop()


## Jagged break across a shaft at height y.
func _broken_top(y: float, r: float, segments: int) -> void:
	var center := _v(Vector3(0, y + r * 0.1, 0), Vector3.UP, Vector2.ZERO)
	var ring := PackedInt32Array()
	var tops := PackedFloat32Array()
	for i in segments + 1:
		var a := TAU * float(i % segments) / segments
		var h := y + rng.randf_range(-0.35, 0.35) * r if i < segments else tops[0]
		tops.append(h)
	for i in segments + 1:
		var a := TAU * float(i % segments) / segments
		var p := Vector3(cos(a) * r, tops[i], sin(a) * r)
		ring.append(_v(p, (Vector3(cos(a), 1.5, sin(a))).normalized(), Vector2(p.x, p.z)))
	for i in segments:
		_t(center, ring[i], ring[i + 1])
	# jagged side strip down to the shaft
	for i in segments:
		var a0 := TAU * float(i) / segments
		var a1 := TAU * float(i + 1) / segments
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var lo := y - r * 0.4
		quad(d0 * r + Vector3(0, lo, 0), d1 * r + Vector3(0, lo, 0), d1 * r + Vector3(0, tops[i + 1], 0), d0 * r + Vector3(0, tops[i], 0),
				Vector2(a0 * r, -lo), Vector2(a1 * r, -lo), Vector2(a1 * r, -tops[i + 1]), Vector2(a0 * r, -tops[i]), ((d0 + d1) * 0.5).normalized())


## Semicircular (or pointed, pointed > 0) arch of voussoir stones in the local
## XY plane, centred on x = 0, springing at y = spring, thickness along z.
func arch(span: float, spring: float, ring_w: float, depth: float, stones := 11, pointed := 0.0, gap := 0.03) -> void:
	var r := span * 0.5
	for i in stones:
		var t0 := float(i) / stones
		var t1 := float(i + 1) / stones
		var poly := PackedVector2Array()
		var steps := 3
		for s in steps + 1:
			poly.append(_arch_pt(lerpf(t0, t1, float(s) / steps), r, spring, pointed) + _arch_dir(lerpf(t0, t1, float(s) / steps), pointed) * gap)
		for s in range(steps, -1, -1):
			var t := lerpf(t0, t1, float(s) / steps)
			poly.append(_arch_pt(t, r + ring_w, spring, pointed))
		# shrink along the ring for mortar gaps
		var c := Vector2.ZERO
		for p in poly:
			c += p
		c /= poly.size()
		for k in poly.size():
			poly[k] = c + (poly[k] - c) * (1.0 - gap * 0.8)
		vary(0.06)
		extrude(poly, -depth * 0.5, depth * 0.5)


static func _arch_pt(t: float, r: float, spring: float, pointed: float) -> Vector2:
	# t: 0 (left springing) .. 1 (right springing)
	var a := PI * (1.0 - t)
	if pointed <= 0.0:
		return Vector2(cos(a) * r, spring + sin(a) * r)
	# Two-centred pointed arch: centres offset by pointed * r.
	var off := pointed * r
	var rr := r + off
	var side := -1.0 if t < 0.5 else 1.0
	var local_t := t * 2.0 if t < 0.5 else (t - 0.5) * 2.0
	var max_a := acos(off / rr)
	var ang := lerpf(PI, max_a, local_t) if side < 0.0 else lerpf(PI - max_a, 0.0, local_t)
	var cx := off * (1.0 if side < 0.0 else -1.0)
	return Vector2(cx + cos(ang) * rr, spring + sin(ang) * rr)


static func _arch_dir(t: float, pointed: float) -> Vector2:
	var a := PI * (1.0 - t)
	return -Vector2(cos(a), sin(a))


## A chain of links from a to b (sagging), each link a small stadium torus.
func chain(a: Vector3, b: Vector3, link := 0.22, thick := 0.035, sag := 0.0) -> void:
	var length := a.distance_to(b)
	var count := maxi(2, int(length / (link * 0.78)))
	var pts := sag_curve(a, b, sag, count)
	for i in count:
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var mid := (p0 + p1) * 0.5
		var z := (p1 - p0).normalized()
		var x := Vector3.UP.cross(z)
		if x.length_squared() < 1e-6:
			x = Vector3.RIGHT
		x = x.normalized()
		var y := z.cross(x)
		if i % 2 == 1:
			var t := x
			x = y
			y = -t
		var path := PackedVector3Array()
		var rr := PackedFloat32Array()
		var seg := 10
		var hl := link * 0.5 - thick
		var hw := link * 0.28
		for s in seg + 1:
			var ang := TAU * float(s) / seg
			var px := cos(ang) * hw
			var pz := sin(ang) * hw
			pz += signf(pz) * maxf(0.0, hl - hw)
			path.append(mid + x * px + z * pz)
			rr.append(thick)
		sweep(path, rr, 5, 1.0, y, false)


## Grid of individually bevelled flagstones over a rectangle in the local XZ
## plane at height y (top surface). Irregular row heights and offsets; holes
## where skip(x, z) returns true.
func flagstones(x0: float, z0: float, x1: float, z1: float, y: float, size := 1.6, bevel := 0.05, depth := 0.35, broken := 0.0, skip := Callable()) -> void:
	var z := z0
	var row := 0
	while z < z1 - 0.05:
		var rh := minf(size * rng.randf_range(0.7, 1.15), z1 - z)
		if z1 - (z + rh) < size * 0.4:
			rh = z1 - z
		var x := x0 - (rng.randf() * size * 0.6 if row % 2 else 0.0)
		while x < x1 - 0.05:
			var w := size * rng.randf_range(0.8, 1.5)
			var xa := maxf(x, x0)
			var xb := minf(x + w, x1)
			if x1 - xb < size * 0.35:
				xb = x1
			if xb - xa > 0.1:
				var c := Vector3((xa + xb) * 0.5, y - depth * 0.5 + rng.randf_range(-0.02, 0.015), z + rh * 0.5)
				var ok := true
				if skip.is_valid():
					ok = not bool(skip.call(c.x, c.z))
				if ok and broken > 0.0 and rng.randf() < broken:
					ok = false
				if ok:
					vary(0.1)
					var gap := 0.025
					push(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.01, 0.01), 0, rng.randf_range(-0.01, 0.01))), c))
					box(Vector3.ZERO, Vector3(xb - xa - gap, depth, rh - gap), bevel)
					pop()
			x = xb
		z += rh
		row += 1


# --- Output -----------------------------------------------------------------------------

func is_empty() -> bool:
	return idx.is_empty()


func arrays() -> Array:
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = verts
	a[Mesh.ARRAY_NORMAL] = norms
	a[Mesh.ARRAY_TEX_UV] = uvs
	a[Mesh.ARRAY_TEX_UV2] = uv2s
	a[Mesh.ARRAY_COLOR] = cols
	a[Mesh.ARRAY_INDEX] = idx
	return a


## Splits the triangles into square cells of `cell` metres (by centroid) so
## the renderer can frustum-cull parts of a big arena. Returns {Vector2i: arrays}.
## (Packed arrays are values in GDScript: each bucket is built in locals.)
func split(cell: float) -> Dictionary:
	var tri_n := idx.size() / 3
	var keys := {}
	var tri_bucket := PackedInt32Array()
	tri_bucket.resize(tri_n)
	var key_list: Array[Vector2i] = []
	for t in tri_n:
		var cen := (verts[idx[t * 3]] + verts[idx[t * 3 + 1]] + verts[idx[t * 3 + 2]]) / 3.0
		var key := Vector2i(floori(cen.x / cell), floori(cen.z / cell))
		var bid: int = keys.get(key, -1)
		if bid < 0:
			bid = key_list.size()
			keys[key] = bid
			key_list.append(key)
		tri_bucket[t] = bid
	# Counting sort of triangles by bucket.
	var counts := PackedInt32Array()
	counts.resize(key_list.size() + 1)
	for t in tri_n:
		counts[tri_bucket[t] + 1] += 1
	for i in key_list.size():
		counts[i + 1] += counts[i]
	var order := PackedInt32Array()
	order.resize(tri_n)
	var fill := counts.duplicate()
	for t in tri_n:
		var bid := tri_bucket[t]
		order[fill[bid]] = t
		fill[bid] += 1
	var remap := PackedInt32Array()
	remap.resize(verts.size())
	var stamp := PackedInt32Array()
	stamp.resize(verts.size())
	stamp.fill(-1)
	var out := {}
	for bid in key_list.size():
		var v := PackedVector3Array()
		var nn := PackedVector3Array()
		var u := PackedVector2Array()
		var u2 := PackedVector2Array()
		var cc := PackedColorArray()
		var ii := PackedInt32Array()
		for o in range(counts[bid], counts[bid + 1]):
			var t := order[o]
			for k in 3:
				var vi := idx[t * 3 + k]
				if stamp[vi] != bid:
					stamp[vi] = bid
					remap[vi] = v.size()
					v.append(verts[vi])
					nn.append(norms[vi])
					u.append(uvs[vi])
					u2.append(uv2s[vi])
					cc.append(cols[vi])
				ii.append(remap[vi])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = nn
		arr[Mesh.ARRAY_TEX_UV] = u
		arr[Mesh.ARRAY_TEX_UV2] = u2
		arr[Mesh.ARRAY_COLOR] = cc
		arr[Mesh.ARRAY_INDEX] = ii
		out[key_list[bid]] = arr
	return out
