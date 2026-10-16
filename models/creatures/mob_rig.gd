class_name MobRig
extends RefCounted
## Skinned bodies for the ordinary creatures: one smooth mesh per creature,
## bound to a small skeleton, so a wolf's leg grows out of its shoulder, a
## shade's sleeve out of its robe, with no seams between parts.
##
##   var r := MobRig.new(2)                       # two material slots
##   var hips := r.bone("hips", -1, Vector3(0, 0.8, 0.4))
##   var chest := r.bone("chest", hips, Vector3(0, 0.85, -0.4))
##   r.tube(path, radii, [hips, hips, chest, ...])   # weights blend along the path
##   r.limb([p0, p1, p2], [thigh, shin], profile)    # rounded limb through joints
##   r.rigid(mesh, xform, head)                      # teeth, horns, ears...
##   var data := r.build("wolf")                     # cached by key
##   (MobModel.rig_instance turns `data` into a Skeleton3D + skinned mesh)
##
## Every bone's rest rotation is identity and its rest position is given in
## model space ("rig space"), so poses are plain rotations (see MobModel).
## Vertices carry their rest position in CUSTOM0.xyz (creature_skin `use_rest`)
## and param() in CUSTOM0.w (the fur mask),
## so fur, scales and stone patterns stay glued to the body while it moves,
## and UV in metres (u around, v along) for patterns that need a direction.

const FORMAT_FLAGS := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT

static var _cache := {}

var names := PackedStringArray()
var parents := PackedInt32Array()
var rest := PackedVector3Array()
var _slots: Array = []
var _slot := 0
var _param := 0.0
## Rings of the last tube (for tufts()).
var _last := {}


func _init(slot_count := 1) -> void:
	for i in slot_count:
		_slots.append({"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(),
			"c": PackedFloat32Array(), "b": PackedInt32Array(), "w": PackedFloat32Array(), "i": PackedInt32Array()})


static func has(key: String) -> bool:
	return _cache.has(key)


static func cached(key: String) -> Dictionary:
	return _cache.get(key, {})


func bone(bone_name: String, parent: int, pos: Vector3) -> int:
	names.append(bone_name)
	parents.append(parent)
	rest.append(pos)
	return names.size() - 1


## Per-vertex parameter for following geometry, stored in CUSTOM0.w: the fur
## mask (0 full coat .. 1 bare: faces, pads, horns) for fur_shell.gdshader.
func param(v: float) -> MobRig:
	_param = v
	return self


## Following geometry goes into material slot `i` (one surface per slot).
func slot(i: int) -> MobRig:
	_slot = i
	return self


func vertex_count() -> int:
	var n := 0
	for s: Dictionary in _slots:
		n += (s["v"] as PackedVector3Array).size()
	return n


# --- Tubes -------------------------------------------------------------------------------

## A smooth tube along `path` with per-point radii (x = sideways, y = the
## frame's up, which starts at `up_hint` and is carried along the path).
## `point_bones[i]` is the bone of point i: an int, or a Dictionary
## {bone: weight} for points shared by several bones. Weights are blended
## along the path over `blend` metres so joints bend smoothly instead of
## creasing. Ends are closed with rounded poles.
func tube(path: PackedVector3Array, radii: PackedVector2Array, point_bones: Array, blend := 0.1, sides := 12, up_hint := Vector3.UP, caps := true) -> void:
	var n := path.size()
	var along := PackedFloat32Array()
	along.resize(n)
	for i in range(1, n):
		along[i] = along[i - 1] + path[i].distance_to(path[i - 1])
	# Bone weights per ring, smoothed along the path.
	var raw: Array = []
	for pb: Variant in point_bones:
		raw.append(pb if pb is Dictionary else {int(pb): 1.0})
	var ring_w: Array = []
	for i in n:
		var acc := {}
		var total := 0.0
		for j in n:
			var d := absf(along[j] - along[i])
			if d > blend and j != i:
				continue
			var k := 1.0 - d / maxf(blend, 0.0001) if j != i else 1.0
			k = maxf(k, 0.0)
			for b: int in (raw[j] as Dictionary):
				acc[b] = float(acc.get(b, 0.0)) + float(raw[j][b]) * k
				total += float(raw[j][b]) * k
		ring_w.append(_top4(acc))
	# Frames (parallel transport).
	var tangents := PackedVector3Array()
	tangents.resize(n)
	for i in n:
		var t := path[mini(n - 1, i + 1)] - path[maxi(0, i - 1)]
		tangents[i] = t.normalized() if t.length_squared() > 1e-10 else Vector3.FORWARD
	var ups := PackedVector3Array()
	ups.resize(n)
	var u := up_hint - tangents[0] * up_hint.dot(tangents[0])
	if u.length_squared() < 1e-6:
		u = Vector3.BACK - tangents[0] * Vector3.BACK.dot(tangents[0])
	u = u.normalized()
	for i in n:
		u = u - tangents[i] * u.dot(tangents[i])
		if u.length_squared() < 1e-8:
			u = ups[i - 1] if i > 0 else Vector3.UP
		u = u.normalized()
		ups[i] = u
	var s: Dictionary = _slots[_slot]
	var ring := sides + 1
	var sides_v := PackedVector3Array()
	for i in n:
		sides_v.append(ups[i].cross(tangents[i]).normalized())
	_last = {"path": path, "side": sides_v, "up": ups, "tan": tangents, "radii": radii, "w": ring_w}
	var pos := PackedVector3Array()
	var uvs := PackedVector2Array()
	pos.resize(n * ring)
	uvs.resize(n * ring)
	for i in n:
		var side := ups[i].cross(tangents[i]).normalized()
		var r := radii[i]
		var circ := PI * (r.x + r.y)
		for j in ring:
			# Start (and so put the texture seam) underneath.
			var a := TAU * float(j) / sides - PI * 0.5
			pos[i * ring + j] = path[i] + side * cos(a) * r.x + ups[i] * sin(a) * r.y
			uvs[i * ring + j] = Vector2(float(j) / sides * circ, along[i])
	var normals := PackedVector3Array()
	normals.resize(pos.size())
	for i in n:
		for j in ring:
			var jj := j % sides
			var du := pos[i * ring + (jj + 1) % sides] - pos[i * ring + (jj - 1 + sides) % sides]
			var dv := pos[mini(n - 1, i + 1) * ring + jj] - pos[maxi(0, i - 1) * ring + jj]
			var nn := du.cross(dv)
			if nn.length_squared() < 1e-14:
				nn = pos[i * ring + j] - path[i]
			nn = nn.normalized()
			if nn.dot(pos[i * ring + j] - path[i]) < 0.0:
				nn = -nn
			normals[i * ring + j] = nn
	var ws: Array = []
	for i in n:
		for j in ring:
			ws.append(ring_w[i])
	var idx := PackedInt32Array()
	for i in n - 1:
		for j in sides:
			var a := i * ring + j
			var b := i * ring + j + 1
			var c := (i + 1) * ring + j + 1
			var d := (i + 1) * ring + j
			_tri_out(idx, pos, normals, a, b, c)
			_tri_out(idx, pos, normals, a, c, d)
	if caps:
		for end in 2:
			var i := 0 if end == 0 else n - 1
			var r := radii[i]
			if r.x <= 0.0001 and r.y <= 0.0001:
				continue
			var dir := -tangents[0] if end == 0 else tangents[n - 1]
			var pole := pos.size()
			pos.append(path[i] + dir * minf(r.x, r.y) * 0.45)
			normals.append(dir)
			uvs.append(Vector2(0, along[i]))
			ws.append(ring_w[i])
			for j in sides:
				_tri_out(idx, pos, normals, i * ring + j, i * ring + j + 1, pole)
	_append(s, pos, normals, uvs, ws, idx)


## A rounded limb through `joints` (rest positions). Segment i (joints[i] ->
## joints[i + 1]) belongs to `seg_bones[i]`; the path is a Catmull-Rom curve
## through the joints sampled into `rings` rings. `prof` rows are
## [t (0..1 along the whole limb), rx, ry, offset_up, offset_side] (offsets
## shape muscles: a calf bulging backwards, a forearm forwards). `root` adds a
## parent bone to the first stretch ({bone: weight}) so the limb stays fused
## to the body.
func limb(joints: PackedVector3Array, seg_bones: Array, prof: Array, rings := 12, sides := 10, up_hint := Vector3.BACK, blend := 0.08, root := {}, root_len := 0.0, caps := true) -> void:
	var segs := joints.size() - 1
	var seg_len := PackedFloat32Array()
	var total := 0.0
	for i in segs:
		var l := joints[i].distance_to(joints[i + 1])
		seg_len.append(l)
		total += l
	var path := PackedVector3Array()
	var radii := PackedVector2Array()
	var pbs: Array = []
	for r in rings + 1:
		var t := float(r) / rings
		var d := t * total
		var si := 0
		while si < segs - 1 and d > seg_len[si]:
			d -= seg_len[si]
			si += 1
		var f := clampf(d / maxf(seg_len[si], 0.0001), 0.0, 1.0)
		var p0 := joints[maxi(0, si - 1)]
		var p1 := joints[si]
		var p2 := joints[si + 1]
		var p3 := joints[mini(segs, si + 2)]
		if si == 0:
			p0 = p1 - (p2 - p1)
		if si == segs - 1:
			p3 = p2 + (p2 - p1)
		path.append(_catmull(p0, p1, p2, p3, f))
		var row := OrganicMesh._sample(prof, t)
		radii.append(Vector2(maxf(0.0, row[0]), maxf(0.0, row[1])))
		var bw := {int(seg_bones[si]): 1.0}
		if not root.is_empty() and t * total < root_len:
			var k := 1.0 - (t * total) / root_len
			for rb: int in root:
				bw[rb] = float(root[rb]) * k
		pbs.append(bw)
	# Offsets in the limb's own frame.
	for r in rings + 1:
		var row := OrganicMesh._sample(prof, float(r) / rings)
		if row[2] == 0.0 and row[3] == 0.0:
			continue
		var tan := path[mini(rings, r + 1)] - path[maxi(0, r - 1)]
		tan = tan.normalized()
		var up := up_hint - tan * up_hint.dot(tan)
		up = up.normalized() if up.length_squared() > 1e-6 else Vector3.UP
		var side := up.cross(tan).normalized()
		path[r] += up * float(row[2]) + side * float(row[3])
	tube(path, radii, pbs, blend, sides, up_hint, caps)


## Tufts of fur, quills, spines or scutes standing out of the last tube():
## `count` copies of `mesh` (built along +Y from its base, flat face +Z,
## unit length) between path fractions t0..t1 and angles a0..a1 (degrees
## round the tube: 0 top, 90 the frame's side (+X for most bodies), 180
## bottom). Each is `length` long (x0.7..1.2), leans back along the path by
## `lean` (0 straight out, 1 flat), and is skinned like the surface under it.
## `grid` (rows along, columns around) places them in tidy rows instead
## (scutes, plates) with a little jitter.
func tufts(mesh: Mesh, count: int, t0: float, t1: float, a0: float, a1: float, length: float, lean := 0.7, seed_value := 1, width := 1.0, backwards := true, grid := Vector2i.ZERO) -> void:
	if _last.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var path: PackedVector3Array = _last["path"]
	var n := path.size()
	if grid.x > 0:
		count = grid.x * grid.y
	for c in count:
		var t := rng.randf_range(t0, t1)
		var a := deg_to_rad(rng.randf_range(a0, a1))
		if grid.x > 0:
			var gi := c / grid.y
			var gj := c % grid.y
			t = lerpf(t0, t1, (float(gi) + 0.5) / grid.x) + rng.randf_range(-0.1, 0.1) / grid.x
			a = deg_to_rad(lerpf(a0, a1, float(gj) / maxf(1.0, grid.y - 1)) + rng.randf_range(-3.0, 3.0))
		var fi := clampf(t, 0.0, 1.0) * (n - 1)
		var i := clampi(int(fi), 0, n - 2)
		var f := fi - i
		var ctr := path[i].lerp(path[i + 1], f)
		var sd: Vector3 = (_last["side"][i] as Vector3).lerp(_last["side"][i + 1], f).normalized()
		var up: Vector3 = (_last["up"][i] as Vector3).lerp(_last["up"][i + 1], f).normalized()
		var tan: Vector3 = (_last["tan"][i] as Vector3).lerp(_last["tan"][i + 1], f).normalized()
		var r: Vector2 = (_last["radii"][i] as Vector2).lerp(_last["radii"][i + 1], f)
		var p := ctr + sd * sin(a) * r.x + up * cos(a) * r.y
		var nor := (sd * sin(a) / maxf(r.x, 0.001) + up * cos(a) / maxf(r.y, 0.001)).normalized()
		var l := length * rng.randf_range(0.7, 1.2)
		var along := -tan if backwards else tan
		var dir := nor.lerp(along, lean).normalized()
		var z := nor - dir * nor.dot(dir)
		z = z.normalized() if z.length_squared() > 1e-6 else along
		var x := dir.cross(z).normalized()
		var b := Basis(x * l * width, dir * l, z * l)
		b = b * Basis(Vector3.UP, rng.randf_range(-0.25, 0.25))
		var xf := Transform3D(b, p - nor * l * 0.08)
		var w: Array = _last["w"][i if f < 0.5 else i + 1]
		_rigid_w(mesh, xf, w)


## A rigid mesh following `bone` (optionally blended with `bone2`).
func rigid(mesh: Mesh, xf: Transform3D, b: int, bone2 := -1, w2 := 0.0) -> void:
	var w := {b: 1.0 - w2}
	if bone2 >= 0 and w2 > 0.0:
		w[bone2] = w2
	_rigid_w(mesh, xf, _top4(w))


## A rigid mesh with explicit weights ([PackedInt32Array bones, PackedFloat32Array weights]).
func _rigid_w(mesh: Mesh, xf: Transform3D, weights: Array) -> void:
	var nb := xf.basis.inverse().transposed()
	var flip := xf.basis.determinant() < 0.0
	var s: Dictionary = _slots[_slot]
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n := PackedVector3Array()
		if arr[Mesh.ARRAY_NORMAL] != null:
			n = arr[Mesh.ARRAY_NORMAL]
		var uv: Variant = arr[Mesh.ARRAY_TEX_UV]
		var pos := PackedVector3Array()
		var nor := PackedVector3Array()
		var uvs := PackedVector2Array()
		var ws: Array = []
		for i in v.size():
			pos.append(xf * v[i])
			nor.append((nb * n[i]).normalized() if n.size() > i else Vector3.UP)
			uvs.append((uv as PackedVector2Array)[i] if uv != null and (uv as PackedVector2Array).size() > i else Vector2.ZERO)
			ws.append(weights)
		var ind: Variant = arr[Mesh.ARRAY_INDEX]
		var idx := PackedInt32Array()
		if ind == null or (ind as PackedInt32Array).is_empty():
			for i in v.size():
				idx.append(i)
		else:
			idx = ind
		if flip:
			for i in range(0, idx.size(), 3):
				var t := idx[i + 1]
				idx[i + 1] = idx[i + 2]
				idx[i + 2] = t
		_append(s, pos, nor, uvs, ws, idx)


## A unit tuft card along +Y (flat face +Z) for tufts(): `curl` bends the tip
## outwards, `w` is the base half width (relative to the length).
static func tuft_mesh(key: String, w := 0.16, curl := 0.15, segs := 4) -> ArrayMesh:
	var path := PackedVector3Array()
	var radii := PackedVector2Array()
	for i in segs + 1:
		var t := float(i) / segs
		path.append(Vector3(0, t, curl * t * t))
		var r := w * (1.0 - t * 0.92)
		radii.append(Vector2(r, r * 0.3))
	return OrganicMesh.sweep("tuft_" + key, path, radii, 4, Vector3.BACK)


## Bake into a cached mesh + skin. Returns {mesh, skin, rest, parents, names, slots}
## where slots[i] is the surface index of material slot i (-1 if empty).
func build(key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]
	var mesh := ArrayMesh.new()
	var slot_surf: Array[int] = []
	for s: Dictionary in _slots:
		if (s["v"] as PackedVector3Array).is_empty():
			slot_surf.append(-1)
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s["v"]
		arrays[Mesh.ARRAY_NORMAL] = s["n"]
		arrays[Mesh.ARRAY_TEX_UV] = s["uv"]
		arrays[Mesh.ARRAY_CUSTOM0] = s["c"]
		arrays[Mesh.ARRAY_BONES] = s["b"]
		arrays[Mesh.ARRAY_WEIGHTS] = s["w"]
		arrays[Mesh.ARRAY_INDEX] = s["i"]
		slot_surf.append(mesh.get_surface_count())
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, FORMAT_FLAGS)
	var skin := Skin.new()
	for i in names.size():
		skin.add_bind(i, Transform3D(Basis.IDENTITY, -rest[i]))
	var data := {"mesh": mesh, "skin": skin, "rest": rest, "parents": parents, "names": names, "slots": slot_surf}
	_cache[key] = data
	return data


# --- Helpers -------------------------------------------------------------------------------

## Path through `pts` sampled as a Catmull-Rom curve into `count` points.
static func spline(pts: PackedVector3Array, count: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var segs := pts.size() - 1
	var lens := PackedFloat32Array()
	var total := 0.0
	for i in segs:
		lens.append(pts[i].distance_to(pts[i + 1]))
		total += lens[i]
	for r in count:
		var d := float(r) / (count - 1) * total
		var si := 0
		while si < segs - 1 and d > lens[si]:
			d -= lens[si]
			si += 1
		var f := clampf(d / maxf(lens[si], 0.0001), 0.0, 1.0)
		var p1 := pts[si]
		var p2 := pts[si + 1]
		var p0 := pts[si - 1] if si > 0 else p1 - (p2 - p1)
		var p3 := pts[si + 2] if si + 2 <= segs else p2 + (p2 - p1)
		out.append(_catmull(p0, p1, p2, p3, f))
	return out


## A smooth tube path through control points with radii and bones per point:
## returns [path, radii, bones] resampled to `count` points (Catmull-Rom,
## radii eased between the control points, bones switching half way).
static func resample(pts: PackedVector3Array, radii: PackedVector2Array, bones: Array, count: int) -> Array:
	var path := spline(pts, count)
	var segs := pts.size() - 1
	var lens := PackedFloat32Array()
	var total := 0.0
	for i in segs:
		lens.append(pts[i].distance_to(pts[i + 1]))
		total += lens[i]
	var out_r := PackedVector2Array()
	var out_b: Array = []
	for r in count:
		var d := float(r) / (count - 1) * total
		var si := 0
		while si < segs - 1 and d > lens[si]:
			d -= lens[si]
			si += 1
		var f := clampf(d / maxf(lens[si], 0.0001), 0.0, 1.0)
		var e := f * f * (3.0 - 2.0 * f)
		out_r.append(radii[si].lerp(radii[si + 1], e))
		out_b.append(bones[si] if f < 0.5 else bones[si + 1])
	return [path, out_r, out_b]


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


static func _top4(acc: Dictionary) -> Array:
	var items: Array = []
	for b: int in acc:
		if float(acc[b]) > 0.0001:
			items.append([b, float(acc[b])])
	items.sort_custom(func(x: Array, y: Array) -> bool: return x[1] > y[1])
	var bs := PackedInt32Array([0, 0, 0, 0])
	var ws := PackedFloat32Array([0, 0, 0, 0])
	var sum := 0.0
	for i in mini(4, items.size()):
		sum += float(items[i][1])
	for i in mini(4, items.size()):
		bs[i] = int(items[i][0])
		ws[i] = float(items[i][1]) / maxf(sum, 0.0001)
	if items.is_empty():
		ws[0] = 1.0
	return [bs, ws]


func _append(s: Dictionary, pos: PackedVector3Array, nor: PackedVector3Array, uvs: PackedVector2Array, ws: Array, idx: PackedInt32Array) -> void:
	var v: PackedVector3Array = s["v"]
	var n: PackedVector3Array = s["n"]
	var uv: PackedVector2Array = s["uv"]
	var c: PackedFloat32Array = s["c"]
	var b: PackedInt32Array = s["b"]
	var w: PackedFloat32Array = s["w"]
	var ii: PackedInt32Array = s["i"]
	var base := v.size()
	v.append_array(pos)
	n.append_array(nor)
	uv.append_array(uvs)
	for i in pos.size():
		c.append_array([pos[i].x, pos[i].y, pos[i].z, _param])
		var bw: Array = ws[i]
		b.append_array(bw[0])
		w.append_array(bw[1])
	for i in idx.size():
		ii.append(idx[i] + base)
	s["v"] = v
	s["n"] = n
	s["uv"] = uv
	s["c"] = c
	s["b"] = b
	s["w"] = w
	s["i"] = ii


static func _tri_out(idx: PackedInt32Array, verts: PackedVector3Array, normals: PackedVector3Array, a: int, b: int, c: int) -> void:
	var face := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	var nsum := normals[a] + normals[b] + normals[c]
	if face.dot(nsum) > 0.0:
		idx.append_array([a, c, b])
	else:
		idx.append_array([a, b, c])
