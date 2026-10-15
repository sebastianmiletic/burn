class_name CharGeo
extends RefCounted
## Accumulates skinned, smooth character geometry in the bind pose and turns it
## into ArrayMesh surface arrays.
##
## Every vertex carries:
##   COLOR   r = palette slot / 255, g = material type / 255, b = shade (x0.5), a = cavity (baked AO)
##   CUSTOM0 xyz = bind-pose position (stable 3D noise that does not swim when
##           limbs move), w = free parameter (cloak hem distance, eye mask...)
##   BONES / WEIGHTS: up to four influences.
## See character.gdshader for the slot and material-type tables.
##
## Winding: Godot front faces are clockwise seen from outside; all primitives
## here emit triangles that way and normals are computed from the faces.

# Palette slots (instance uniforms in character.gdshader).
const SKIN := 0
const HAIR := 1
const CLOTH := 2
const CLOTH2 := 3
const TROUSERS := 4
const LEATHER := 5
const METAL := 6
const CLOAK := 7
const FIXED := 8  ## constant colour chosen by the material type (bone, ivory, horn, eye, dark)

# Material types (lighting response, ASCII class, procedural detail).
const M_SKIN := 0
const M_CLOTH := 1
const M_LEATHER := 2
const M_METAL := 3
const M_HAIR := 4
const M_BONE := 5
const M_EYE := 6
const M_DARK := 7
const M_MAIL := 8
const M_LIPS := 9
const M_HORN := 10
const M_WOOL := 11
const M_IVORY := 12
const M_DECAY := 13

var pos := PackedVector3Array()
var uv := PackedVector2Array()
var col := PackedColorArray()
var cus := PackedFloat32Array()
var bon := PackedInt32Array()
var wgt := PackedFloat32Array()
var idx := PackedInt32Array()

var _mat := Color(0, 0, 0.5, 1)
var _b := PackedInt32Array([0, 0, 0, 0])
var _w := PackedFloat32Array([1, 0, 0, 0])
var _param := 0.0


func vertex_count() -> int:
	return pos.size()


func tri_count() -> int:
	return idx.size() / 3


## slot: palette slot, mtype: material type, shade: brightness multiplier (0..2), ao: 0 dark crease .. 1 open.
func mat(slot: int, mtype: int, shade := 1.0, ao := 1.0) -> void:
	_mat = Color(slot / 255.0, mtype / 255.0, clampf(shade * 0.5, 0.0, 1.0), clampf(ao, 0.0, 1.0))


func param(v: float) -> void:
	_param = v


func bone(b: int) -> void:
	_b[0] = b
	_b[1] = 0
	_b[2] = 0
	_b[3] = 0
	_w[0] = 1.0
	_w[1] = 0.0
	_w[2] = 0.0
	_w[3] = 0.0


## Blend between two bones: f = 0 all a, 1 all b.
func bone2(a: int, b: int, f: float) -> void:
	f = clampf(f, 0.0, 1.0)
	_b[0] = a
	_b[1] = b
	_b[2] = 0
	_b[3] = 0
	_w[0] = 1.0 - f
	_w[1] = f
	_w[2] = 0.0
	_w[3] = 0.0


## Up to four bones with weights (normalised here).
func bones(bs: Array, ws: Array) -> void:
	var total := 0.0
	for i in 4:
		_b[i] = int(bs[i]) if i < bs.size() else 0
		_w[i] = maxf(0.0, float(ws[i])) if i < ws.size() else 0.0
		total += _w[i]
	if total <= 0.0:
		_w[0] = 1.0
		total = 1.0
	for i in 4:
		_w[i] /= total


func add(p: Vector3, t := Vector2.ZERO) -> int:
	pos.append(p)
	uv.append(t)
	col.append(_mat)
	cus.append(p.x)
	cus.append(p.y)
	cus.append(p.z)
	cus.append(_param)
	for i in 4:
		bon.append(_b[i])
		wgt.append(_w[i])
	return pos.size() - 1


## Copy material, parameter and skin weights of vertex `src` onto `dst`.
func copy_attrs(dst: int, src: int) -> void:
	col[dst] = col[src]
	cus[dst * 4 + 3] = cus[src * 4 + 3]
	for i in 4:
		bon[dst * 4 + i] = bon[src * 4 + i]
		wgt[dst * 4 + i] = wgt[src * 4 + i]


func tri(a: int, b: int, c: int) -> void:
	idx.append(a)
	idx.append(b)
	idx.append(c)


## Quad a-b-c-d where a->b runs "around" and a->d runs "along" in the same
## sense as a ring loft (see header): emits (a, b, d) and (b, c, d).
func quad(a: int, b: int, c: int, d: int) -> void:
	tri(a, b, d)
	tri(b, c, d)


## Right-handed ring frame for a tube running along `t`: returns [bx, bz].
static func frame(t: Vector3, ref := Vector3.RIGHT) -> Array:
	var bx := ref - t * ref.dot(t)
	if bx.length_squared() < 1e-6:
		bx = Vector3.FORWARD - t * Vector3.FORWARD.dot(t)
	bx = bx.normalized()
	var bz := bx.cross(t).normalized()
	return [bx, bz]


static func _se(c: float, p: float) -> float:
	if p == 2.0:
		return c
	return signf(c) * pow(absf(c), 2.0 / p)


## A lofted tube through `pts` (bind-pose positions).
## rings: per point Vector4(rx, r_front, r_back, power) - r_front is the radius on the side
##        facing the model's front (-Z, or `front` if given), power 2 = ellipse, >2 boxier.
## ws: per point Vector3(bone_a, bone_b, blend) or null to keep the current bones.
## cap0 / cap1: round the start / end with this many extra rings (0 = open).
## Returns the index of the first ring vertex.
func tube(pts: PackedVector3Array, rings: Array, sides: int, ws: Array = [], cap0 := 2, cap1 := 2,
		ref := Vector3.RIGHT, front := Vector3.FORWARD, v0 := 0.0, v1 := 1.0, mats: Array = []) -> int:
	var n := pts.size()
	var first := pos.size()
	var ring_ids: Array[int] = []
	var frames: Array = []
	var tangents: Array[Vector3] = []
	for k in n:
		var t: Vector3
		if k == 0:
			t = pts[1] - pts[0]
		elif k == n - 1:
			t = pts[n - 1] - pts[n - 2]
		else:
			t = (pts[k + 1] - pts[k - 1])
		t = t.normalized()
		tangents.append(t)
		frames.append(frame(t, ref))
	# Optional rounded caps are extra rings beyond the ends, shrinking to a pole.
	var all_pts: Array[Vector3] = []
	var all_r: Array[Vector4] = []
	var all_f: Array = []
	var all_w: Array = []
	var all_v: Array[float] = []
	var all_m: Array = []
	var len_total := 0.0
	for k in range(1, n):
		len_total += pts[k].distance_to(pts[k - 1])
	var acc := 0.0
	for k in n:
		if k > 0:
			acc += pts[k].distance_to(pts[k - 1])
		all_pts.append(pts[k])
		all_r.append(rings[k])
		all_f.append(frames[k])
		all_w.append(ws[k] if k < ws.size() else null)
		all_v.append(lerpf(v0, v1, acc / maxf(len_total, 1e-5)))
		all_m.append(mats[k] if k < mats.size() else null)
	if cap0 > 0:
		var r0: Vector4 = rings[0]
		var depth := minf(r0.x, (r0.y + r0.z) * 0.5)
		for c in range(cap0, 0, -1):
			var a := float(c) / float(cap0 + 1) * PI * 0.5
			all_pts.push_front(pts[0] - tangents[0] * depth * sin(a))
			all_r.push_front(Vector4(r0.x * cos(a), r0.y * cos(a), r0.z * cos(a), r0.w))
			all_f.push_front(frames[0])
			all_w.push_front(ws[0] if ws.size() > 0 else null)
			all_v.push_front(v0)
			all_m.push_front(mats[0] if mats.size() > 0 else null)
	if cap1 > 0:
		var r1: Vector4 = rings[n - 1]
		var depth := minf(r1.x, (r1.y + r1.z) * 0.5)
		for c in range(1, cap1 + 1):
			var a := float(c) / float(cap1 + 1) * PI * 0.5
			all_pts.append(pts[n - 1] + tangents[n - 1] * depth * sin(a))
			all_r.append(Vector4(r1.x * cos(a), r1.y * cos(a), r1.z * cos(a), r1.w))
			all_f.append(frames[n - 1])
			all_w.append(ws[n - 1] if ws.size() > 0 else null)
			all_v.append(v1)
			all_m.append(mats[n - 1] if mats.size() > 0 else null)
	var saved_mat := _mat
	var saved_b := _b.duplicate()
	var saved_w := _w.duplicate()
	var connect: Array[bool] = []
	for k in all_pts.size():
		var wv: Variant = all_w[k]
		if wv != null:
			var w3: Vector3 = wv
			bone2(int(w3.x), int(w3.y), w3.z)
		var fr: Array = all_f[k]
		var bx: Vector3 = fr[0]
		var bz: Vector3 = fr[1]
		var r: Vector4 = all_r[k]
		var fz := bz.dot(front)
		var mv: Variant = all_m[k]
		var copies := 1
		if mv != null and k > 0 and mv != _mat:
			copies = 2  # hard material edge: finish the strip, then restart
		for copy in copies:
			if copy == copies - 1 and mv != null:
				_mat = mv
			ring_ids.append(pos.size())
			connect.append(k > 0 and copy == 0)
			for j in sides:
				var th := TAU * float(j) / float(sides)
				var c := _se(cos(th), r.w)
				var s := _se(sin(th), r.w)
				var rz := r.y if s * fz > 0.0 else r.z
				add(all_pts[k] + bx * c * r.x + bz * s * rz, Vector2(float(j) / sides, all_v[k]))
	_mat = saved_mat
	_b = saved_b
	_w = saved_w
	for k in range(1, ring_ids.size()):
		if not connect[k]:
			continue
		var a0 := ring_ids[k - 1]
		var a1 := ring_ids[k]
		for j in sides:
			var j1 := (j + 1) % sides
			quad(a0 + j, a0 + j1, a1 + j1, a1 + j)
	if cap0 > 0:
		var r0: Vector4 = rings[0]
		var depth := minf(r0.x, (r0.y + r0.z) * 0.5)
		var pole := add(pts[0] - tangents[0] * depth, Vector2(0.5, v0))
		var a0 := ring_ids[0]
		copy_attrs(pole, a0)
		pos[pole] = pts[0] - tangents[0] * depth
		for j in sides:
			tri(pole, a0 + (j + 1) % sides, a0 + j)
	if cap1 > 0:
		var r1: Vector4 = rings[n - 1]
		var depth := minf(r1.x, (r1.y + r1.z) * 0.5)
		var pole := add(pts[n - 1] + tangents[n - 1] * depth, Vector2(0.5, v1))
		var last := ring_ids[ring_ids.size() - 1]
		copy_attrs(pole, last)
		for j in sides:
			tri(pole, last + j, last + (j + 1) % sides)
	return first


## A (deformed) ellipsoid. basis columns are the local axes; `deform` (optional)
## maps (unit direction, local point) -> displaced local point.
func ellipsoid(center: Vector3, radii: Vector3, rings: int, sides: int, basis := Basis.IDENTITY,
		power := 2.0, deform := Callable(), uv_scale := 1.0) -> int:
	var first := pos.size()
	# Poles along local Y.
	var top := add(center + basis * _ell_point(Vector3.UP, radii, power, deform), Vector2(0.5, 0))
	var ring_start: Array[int] = []
	for i in range(1, rings):
		var phi := PI * float(i) / float(rings)
		ring_start.append(pos.size())
		for j in sides:
			var th := TAU * float(j) / float(sides)
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			add(center + basis * _ell_point(d, radii, power, deform), Vector2(float(j) / sides * uv_scale, float(i) / rings))
	var bottom := add(center + basis * _ell_point(Vector3.DOWN, radii, power, deform), Vector2(0.5, 1))
	# Winding: rings run downwards (along -Y), theta from +X towards +Z.
	var r0 := ring_start[0]
	for j in sides:
		tri(top, r0 + j, r0 + (j + 1) % sides)
	for k in range(ring_start.size() - 1):
		var a0 := ring_start[k]
		var a1 := ring_start[k + 1]
		for j in sides:
			var j1 := (j + 1) % sides
			# Going down: a ring at lower index is above; flip relative to tube().
			quad(a1 + j, a1 + j1, a0 + j1, a0 + j)
	var rl := ring_start[ring_start.size() - 1]
	for j in sides:
		tri(bottom, rl + (j + 1) % sides, rl + j)
	return first


static func _ell_point(d: Vector3, r: Vector3, power: float, deform: Callable) -> Vector3:
	var p := Vector3(_se(d.x, power) * r.x, _se(d.y, power) * r.y, _se(d.z, power) * r.z) if power != 2.0 else d * r
	if deform.is_valid():
		p = deform.call(d, p)
	return p


## Double-sided sheet from a grid of points (rows x cols, row-major), with a
## rim. `normal_hint` is the direction the "outer" face looks. `thickness` in m.
## per-vertex weights through `weight_fn(row, col) -> Array[bones, weights]` or current bones.
func sheet(grid: PackedVector3Array, rows: int, cols: int, thickness: float, outer_hint: Vector3,
		weight_fn := Callable(), param_fn := Callable(), inner_shade := 0.6) -> void:
	# Per-vertex offsets along a smooth grid normal.
	var normals := PackedVector3Array()
	normals.resize(rows * cols)
	for r in rows:
		for c in cols:
			var p := grid[r * cols + c]
			var du := grid[r * cols + mini(c + 1, cols - 1)] - grid[r * cols + maxi(c - 1, 0)]
			var dv := grid[mini(r + 1, rows - 1) * cols + c] - grid[maxi(r - 1, 0) * cols + c]
			var nn := du.cross(dv).normalized()
			if nn.dot(outer_hint) < 0.0:
				nn = -nn
			normals[r * cols + c] = nn
			var _unused := p
	var saved_mat := _mat
	var outer := pos.size()
	for side in 2:
		if side == 1:
			_mat = Color(saved_mat.r, saved_mat.g, saved_mat.b * inner_shade, saved_mat.a * 0.8)
		for r in rows:
			for c in cols:
				if weight_fn.is_valid():
					var bw: Array = weight_fn.call(r, c)
					bones(bw[0], bw[1])
				if param_fn.is_valid():
					_param = float(param_fn.call(r, c))
				var o := normals[r * cols + c] * thickness * (0.5 if side == 0 else -0.5)
				add(grid[r * cols + c] + o, Vector2(float(c) / (cols - 1), float(r) / (rows - 1)))
	_mat = saved_mat
	var inner := outer + rows * cols
	# Decide winding from the first cell so the outer face looks along outer_hint.
	var a := grid[0]
	var b := grid[1]
	var d := grid[cols]
	var flip := (b - a).cross(d - a).dot(normals[0]) > 0.0
	for r in rows - 1:
		for c in cols - 1:
			var i00 := r * cols + c
			var i01 := i00 + 1
			var i10 := i00 + cols
			var i11 := i10 + 1
			if flip:
				tri(outer + i00, outer + i10, outer + i01)
				tri(outer + i01, outer + i10, outer + i11)
				tri(inner + i00, inner + i01, inner + i10)
				tri(inner + i01, inner + i11, inner + i10)
			else:
				tri(outer + i00, outer + i01, outer + i10)
				tri(outer + i01, outer + i11, outer + i10)
				tri(inner + i00, inner + i10, inner + i01)
				tri(inner + i01, inner + i10, inner + i11)
	# Rim around the border joins the two faces.
	var border: Array[int] = []
	for c in cols:
		border.append(c)
	for r in range(1, rows):
		border.append(r * cols + cols - 1)
	for c in range(cols - 2, -1, -1):
		border.append((rows - 1) * cols + c)
	for r in range(rows - 2, 0, -1):
		border.append(r * cols)
	for k in border.size():
		var i0 := border[k]
		var i1 := border[(k + 1) % border.size()]
		if flip:
			tri(outer + i0, inner + i0, outer + i1)
			tri(outer + i1, inner + i0, inner + i1)
		else:
			tri(outer + i0, outer + i1, inner + i0)
			tri(outer + i1, inner + i1, inner + i0)


## Rigidly transform every vertex added since `from` (bind pose), e.g. to place a
## part built at the origin.
func transform_from(from: int, xf: Transform3D) -> void:
	for i in range(from, pos.size()):
		var p := xf * pos[i]
		pos[i] = p
		cus[i * 4] = p.x
		cus[i * 4 + 1] = p.y
		cus[i * 4 + 2] = p.z


## Append another builder (weights and materials preserved).
func merge(o: CharGeo) -> void:
	var base := pos.size()
	pos.append_array(o.pos)
	uv.append_array(o.uv)
	col.append_array(o.col)
	cus.append_array(o.cus)
	bon.append_array(o.bon)
	wgt.append_array(o.wgt)
	for i in o.idx:
		idx.append(base + i)


## Smooth normals from the faces (area weighted). Vertices that share a
## position within `weld` and the same material get the same normal, so loft
## seams and pole fans shade smoothly.
func compute_normals() -> PackedVector3Array:
	var n := PackedVector3Array()
	n.resize(pos.size())
	for t in range(0, idx.size(), 3):
		var a := idx[t]
		var b := idx[t + 1]
		var c := idx[t + 2]
		var fn := (pos[c] - pos[a]).cross(pos[b] - pos[a])
		n[a] += fn
		n[b] += fn
		n[c] += fn
	# Weld: vertices at the same spot (material seams, duplicated rings) share a normal.
	var groups := {}
	for i in pos.size():
		var key := (pos[i] * 20000.0).round()
		var g: Variant = groups.get(key)
		if g == null:
			groups[key] = i
		else:
			var first: int = g
			if n[i].dot(n[first]) > 0.0:
				n[first] += n[i]
				n[i] = Vector3(INF, 0, 0)
	for i in pos.size():
		if n[i].x == INF:
			n[i] = n[int(groups[(pos[i] * 20000.0).round()])]
	for i in n.size():
		var v := n[i]
		n[i] = v.normalized() if v.length_squared() > 1e-20 else Vector3.UP
	return n


## Remove triangles added since `from_tri` whose centroid fails `keep(centroid) -> bool`.
func clip_tris(from_tri: int, keep: Callable) -> void:
	var out := PackedInt32Array()
	for t in range(from_tri * 3, idx.size(), 3):
		var c := (pos[idx[t]] + pos[idx[t + 1]] + pos[idx[t + 2]]) / 3.0
		if keep.call(c):
			out.append(idx[t])
			out.append(idx[t + 1])
			out.append(idx[t + 2])
	idx.resize(from_tri * 3)
	idx.append_array(out)


## Reverse the winding of triangles added since `from_tri` (inner shells).
func flip_tris(from_tri: int) -> void:
	for t in range(from_tri * 3, idx.size(), 3):
		var tmp := idx[t + 1]
		idx[t + 1] = idx[t + 2]
		idx[t + 2] = tmp


## Re-skin vertices [from, to): fn(p: Vector3) -> [bones, weights] or null to keep.
func reweight(from: int, to: int, fn: Callable) -> void:
	for i in range(from, to):
		var r: Variant = fn.call(pos[i])
		if r == null:
			continue
		var bw: Array = r
		bones(bw[0], bw[1])
		for k in 4:
			bon[i * 4 + k] = _b[k]
			wgt[i * 4 + k] = _w[k]


## Multiply shade / set cavity of vertices [from, to): fn(p) -> Vector2(shade_mult, ao) or null.
func reshade(from: int, to: int, fn: Callable) -> void:
	for i in range(from, to):
		var r: Variant = fn.call(pos[i])
		if r == null:
			continue
		var v: Vector2 = r
		var c := col[i]
		col[i] = Color(c.r, c.g, clampf(c.b * v.x, 0.0, 1.0), clampf(v.y, 0.0, 1.0))


func to_arrays() -> Array:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = compute_normals()
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_CUSTOM0] = cus
	arr[Mesh.ARRAY_BONES] = bon
	arr[Mesh.ARRAY_WEIGHTS] = wgt
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


const FORMAT_FLAGS := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT


func aabb() -> AABB:
	if pos.is_empty():
		return AABB()
	var box := AABB(pos[0], Vector3.ZERO)
	for p in pos:
		box = box.expand(p)
	return box
