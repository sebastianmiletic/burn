class_name WingKit
extends RefCounted
## Skinned membranes and custom-weighted surfaces for MobRig bodies:
##   * panel(): a double-sided membrane stretched between two "spars"
##     (finger bones, the body side, a leg) with a scalloped trailing edge and
##     a little camber - bat, imp and dragon-like wings, ears, fins
##   * grid(): a tube-like surface whose every vertex gets its own bone
##     weights from a Callable (robes hanging from a ring of skirt bones)
## A spar is an Array of points [position (rig space), {bone: weight}],
## listed from the wing root outwards.


## Position and weights `t` (0..1 by length) along a spar.
static func spar_at(spar: Array, t: float) -> Array:
	var lens := PackedFloat32Array()
	var total := 0.0
	for i in spar.size() - 1:
		var l := (spar[i][0] as Vector3).distance_to(spar[i + 1][0])
		lens.append(l)
		total += l
	var d := clampf(t, 0.0, 1.0) * total
	var i := 0
	while i < lens.size() - 1 and d > lens[i]:
		d -= lens[i]
		i += 1
	var f := clampf(d / maxf(lens[i], 0.0001), 0.0, 1.0)
	var p := (spar[i][0] as Vector3).lerp(spar[i + 1][0], f)
	return [p, mix_w(spar[i][1], spar[i + 1][1], f)]


static func mix_w(a: Dictionary, b: Dictionary, f: float) -> Dictionary:
	var out := {}
	for k: int in a:
		out[k] = float(out.get(k, 0.0)) + float(a[k]) * (1.0 - f)
	for k: int in b:
		out[k] = float(out.get(k, 0.0)) + float(b[k]) * f
	return out


## Membrane between spars `a` and `b` (rows along the spars, cols across).
## `scallop` (0..0.5) bows the free edge in towards the root; `camber` bulges
## the middle along `front` (the side whose normals face `front`).
static func panel(r: MobRig, a: Array, b: Array, rows: int, cols: int, thick: float, front: Vector3, scallop := 0.25, camber := 0.0) -> void:
	var pos := PackedVector3Array()
	var ws: Array = []
	var uvs := PackedVector2Array()
	var a_root: Vector3 = spar_at(a, 0.0)[0]
	var b_root: Vector3 = spar_at(b, 0.0)[0]
	var a_tip: Vector3 = spar_at(a, 1.0)[0]
	var b_tip: Vector3 = spar_at(b, 1.0)[0]
	var edge_len := a_tip.distance_to(b_tip)
	for i in rows + 1:
		var t := float(i) / rows
		var pa: Array = spar_at(a, t)
		var pb: Array = spar_at(b, t)
		for j in cols + 1:
			var u := float(j) / cols
			var p := (pa[0] as Vector3).lerp(pb[0], u)
			var root := a_root.lerp(b_root, u)
			var inward := (root - p)
			if inward.length_squared() > 1e-8:
				p += inward.normalized() * edge_len * scallop * sin(PI * u) * pow(t, 3.0)
			pos.append(p)
			ws.append(mix_w(pa[1], pb[1], u))
			uvs.append(Vector2(u, t))
	var ring := cols + 1
	var nor := PackedVector3Array()
	nor.resize(pos.size())
	for i in rows + 1:
		for j in ring:
			var du := pos[i * ring + mini(j + 1, cols)] - pos[i * ring + maxi(j - 1, 0)]
			var dv := pos[mini(i + 1, rows) * ring + j] - pos[maxi(i - 1, 0) * ring + j]
			var n := du.cross(dv)
			n = n.normalized() if n.length_squared() > 1e-12 else front
			if n.dot(front) < 0.0:
				n = -n
			nor[i * ring + j] = n
	if camber != 0.0:
		for i in rows + 1:
			for j in ring:
				var t := float(i) / rows
				var u := float(j) / cols
				pos[i * ring + j] += nor[i * ring + j] * camber * sin(PI * u) * sin(PI * minf(1.0, t * 1.3))
	_emit_two_sided(r, pos, nor, uvs, ws, rows, cols, thick)


## A surface of rows x (cols + 1) points given row by row (closed round if
## `closed`), each vertex weighted by `weight_fn.call(rest_pos, row, col)` ->
## {bone: weight}. Normals point away from `centre_fn.call(row)` (a Vector3
## inside the surface). One-sided.
static func grid(r: MobRig, pts: PackedVector3Array, rows: int, cols: int, weight_fn: Callable, centres: PackedVector3Array) -> void:
	var ring := cols + 1
	var ws: Array = []
	var uvs := PackedVector2Array()
	var along := 0.0
	for i in rows:
		if i > 0:
			along += pts[i * ring].distance_to(pts[(i - 1) * ring])
		for j in ring:
			ws.append(MobRig._top4(weight_fn.call(pts[i * ring + j], i, j)))
			uvs.append(Vector2(float(j) / cols, along))
	var nor := PackedVector3Array()
	nor.resize(pts.size())
	for i in rows:
		for j in ring:
			var jj := j % cols
			var du := pts[i * ring + (jj + 1) % cols] - pts[i * ring + (jj - 1 + cols) % cols]
			var dv := pts[mini(rows - 1, i + 1) * ring + jj] - pts[maxi(0, i - 1) * ring + jj]
			var n := du.cross(dv)
			n = n.normalized() if n.length_squared() > 1e-12 else Vector3.UP
			if n.dot(pts[i * ring + j] - centres[i]) < 0.0:
				n = -n
			nor[i * ring + j] = n
	var idx := PackedInt32Array()
	for i in rows - 1:
		for j in cols:
			var a := i * ring + j
			var b := i * ring + j + 1
			var c := (i + 1) * ring + j + 1
			var d := (i + 1) * ring + j
			MobRig._tri_out(idx, pts, nor, a, b, c)
			MobRig._tri_out(idx, pts, nor, a, c, d)
	r._append(r._slots[r._slot], pts, nor, uvs, ws, idx)


static func _emit_two_sided(r: MobRig, pos: PackedVector3Array, nor: PackedVector3Array, uvs: PackedVector2Array, wdicts: Array, rows: int, cols: int, thick: float) -> void:
	var ring := cols + 1
	var n := pos.size()
	var all_p := PackedVector3Array()
	var all_n := PackedVector3Array()
	var all_uv := PackedVector2Array()
	var ws: Array = []
	for side in 2:
		var sgn := 1.0 if side == 0 else -1.0
		for i in n:
			all_p.append(pos[i] + nor[i] * thick * 0.5 * sgn)
			all_n.append(nor[i] * sgn)
			all_uv.append(uvs[i])
			ws.append(MobRig._top4(wdicts[i]))
	var idx := PackedInt32Array()
	for side in 2:
		var o := side * n
		for i in rows:
			for j in cols:
				var a := o + i * ring + j
				var b := o + i * ring + j + 1
				var c := o + (i + 1) * ring + j + 1
				var d := o + (i + 1) * ring + j
				MobRig._tri_out(idx, all_p, all_n, a, b, c)
				MobRig._tri_out(idx, all_p, all_n, a, c, d)
	r._append(r._slots[r._slot], all_p, all_n, all_uv, ws, idx)
