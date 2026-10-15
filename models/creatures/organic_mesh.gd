class_name OrganicMesh
extends RefCounted
## Smooth organic meshes for creatures, built once and cached by key:
##   * sweep: an elliptical cross-section swept along a 3D path with
##     parallel-transported frames (bodies, necks, limbs, tails, horns, claws)
##   * profile: a sweep along a straight axis shaped by a radius profile
##   * bezier: a tapered tube along a quadratic curve (horns, teeth, legs)
##   * blob: a lumpy ellipsoid (rocks, egg sacs, abdomens)
##   * skinned_tube: a long tube weighted to a chain of bones (serpents)
## UVs are in metres (u around the body, v along it) so the creature skin
## shader can lay scales on skinned meshes without stretching.

static var _cache := {}


static func has(key: String) -> bool:
	return _cache.has(key)


## Sweep along `path` with per-point radii (x = sideways, y = "up" of the frame).
## `up_hint` picks the frame's initial up direction. Ends are closed with poles.
static func sweep(key: String, path: PackedVector3Array, radii: PackedVector2Array, sides := 12, up_hint := Vector3.UP) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var n := path.size()
	var tangents := PackedVector3Array()
	tangents.resize(n)
	for i in n:
		var a := path[maxi(0, i - 1)]
		var b := path[mini(n - 1, i + 1)]
		var t := b - a
		tangents[i] = t.normalized() if t.length_squared() > 1e-10 else Vector3.FORWARD
	var ups := PackedVector3Array()
	ups.resize(n)
	var u := up_hint - tangents[0] * up_hint.dot(tangents[0])
	if u.length_squared() < 1e-6:
		u = Vector3.RIGHT - tangents[0] * Vector3.RIGHT.dot(tangents[0])
	u = u.normalized()
	for i in n:
		u = u - tangents[i] * u.dot(tangents[i])
		if u.length_squared() < 1e-8:
			u = ups[i - 1] if i > 0 else Vector3.UP
		u = u.normalized()
		ups[i] = u
	var ring := sides + 1
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(n * ring)
	uvs.resize(n * ring)
	var along := 0.0
	for i in n:
		if i > 0:
			along += path[i].distance_to(path[i - 1])
		var side := ups[i].cross(tangents[i]).normalized()
		var r := radii[i]
		var circ := PI * (r.x + r.y)
		for j in ring:
			var a := TAU * float(j) / sides
			verts[i * ring + j] = path[i] + side * cos(a) * r.x + ups[i] * sin(a) * r.y
			uvs[i * ring + j] = Vector2(float(j) / sides * circ, along)
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in n:
		for j in ring:
			var jj := j % sides
			var jp := (jj + 1) % sides
			var jm := (jj - 1 + sides) % sides
			var du := verts[i * ring + jp] - verts[i * ring + jm]
			var dv := verts[mini(n - 1, i + 1) * ring + jj] - verts[maxi(0, i - 1) * ring + jj]
			var nn := du.cross(dv)
			if nn.length_squared() < 1e-12:
				nn = verts[i * ring + j] - path[i]
			nn = nn.normalized()
			if nn.dot(verts[i * ring + j] - path[i]) < 0.0:
				nn = -nn
			normals[i * ring + j] = nn
	var idx := PackedInt32Array()
	for i in n - 1:
		for j in sides:
			var a := i * ring + j
			var b := i * ring + j + 1
			var c := (i + 1) * ring + j + 1
			var d := (i + 1) * ring + j
			_tri_out(idx, verts, normals, a, b, c)
			_tri_out(idx, verts, normals, a, c, d)
	# Poles close the ends.
	for end in 2:
		var i := 0 if end == 0 else n - 1
		var r := radii[i]
		if r.x <= 0.0001 and r.y <= 0.0001:
			continue
		var dir := -tangents[0] if end == 0 else tangents[n - 1]
		var pole := verts.size()
		verts.append(path[i] + dir * minf(r.x, r.y) * 0.35)
		normals.append(dir)
		uvs.append(Vector2(0, along if end == 1 else 0.0))
		for j in sides:
			_tri_out(idx, verts, normals, i * ring + j, i * ring + j + 1, pole)
	var mesh := _commit(verts, normals, uvs, idx)
	_cache[key] = mesh
	return mesh


## Straight sweep from `from` to `to` shaped by `profile`: an Array of
## [t (0..1 along the axis), rx, ry, offset_up, offset_side]. Rings in between
## are interpolated smoothly; `rings` controls the resolution.
static func profile(key: String, from: Vector3, to: Vector3, prof: Array, sides := 12, rings := 14, up_hint := Vector3.UP) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var axis := to - from
	var t_dir := axis.normalized()
	var up := up_hint - t_dir * up_hint.dot(t_dir)
	if up.length_squared() < 1e-6:
		up = Vector3.BACK - t_dir * Vector3.BACK.dot(t_dir)
	up = up.normalized()
	var side := up.cross(t_dir).normalized()
	var path := PackedVector3Array()
	var radii := PackedVector2Array()
	for i in rings + 1:
		var t := float(i) / rings
		var s := _sample(prof, t)
		path.append(from + axis * t + up * s[2] + side * s[3])
		radii.append(Vector2(maxf(0.0, s[0]), maxf(0.0, s[1])))
	return sweep(key, path, radii, sides, up)


## Tapered tube along a quadratic Bezier p0 -> p2 bending towards p1.
static func bezier(key: String, p0: Vector3, p1: Vector3, p2: Vector3, r0: float, r1: float, segments := 8, sides := 8, flat := 1.0) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var path := PackedVector3Array()
	var radii := PackedVector2Array()
	for i in segments + 1:
		var t := float(i) / segments
		var a := p0.lerp(p1, t)
		var b := p1.lerp(p2, t)
		path.append(a.lerp(b, t))
		var r := lerpf(r0, r1, t)
		radii.append(Vector2(r, r * flat))
	return sweep(key, path, radii, sides)


## Lumpy ellipsoid. `lumps` 0..1 scales the noise displacement.
static func blob(key: String, size: Vector3, lumps := 0.15, seed_value := 1, segments := 14) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.6
	noise.fractal_octaves = 3
	var rings := maxi(6, segments / 2 + 2)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var dirs := PackedVector3Array()
	for i in rings + 1:
		var v := float(i) / rings
		var phi := PI * v
		for j in segments + 1:
			var th := TAU * float(j % segments) / segments
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var disp := 1.0 + noise.get_noise_3dv(d * 1.3) * lumps
			verts.append(Vector3(d.x * size.x, d.y * size.y, d.z * size.z) * disp)
			dirs.append(d)
			uvs.append(Vector2(float(j) / segments * PI * (size.x + size.z), v * PI * size.y))
	var ring := segments + 1
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in rings + 1:
		for j in ring:
			var jj := j % segments
			var du := verts[i * ring + (jj + 1) % segments] - verts[i * ring + (jj - 1 + segments) % segments]
			var dv := verts[mini(rings, i + 1) * ring + jj] - verts[maxi(0, i - 1) * ring + jj]
			var nn := du.cross(dv)
			if nn.length_squared() < 1e-12 or i == 0 or i == rings:
				nn = dirs[i * ring + j] / Vector3(size.x, size.y, size.z).max(Vector3(0.001, 0.001, 0.001))
			nn = nn.normalized()
			if nn.dot(dirs[i * ring + j]) < 0.0:
				nn = -nn
			normals[i * ring + j] = nn
	var idx := PackedInt32Array()
	for i in rings:
		for j in segments:
			var a := i * ring + j
			var b := i * ring + j + 1
			var c := (i + 1) * ring + j + 1
			var d := (i + 1) * ring + j
			_tri_out(idx, verts, normals, a, b, c)
			_tri_out(idx, verts, normals, a, c, d)
	var mesh := _commit(verts, normals, uvs, idx)
	_cache[key] = mesh
	return mesh


## A tube along +Z from z = 0 (head end) to z = length, weighted to `bones`
## evenly spaced bones (bone i rests at z = i * length / (bones - 1)).
## radius(t) comes from `prof` ([t, rx, ry, offset_up] rows, see profile()).
static func skinned_tube(key: String, length: float, bones: int, prof: Array, rings := 64, sides := 14) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var ring := sides + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var bone_idx := PackedInt32Array()
	var weights := PackedFloat32Array()
	var centres := PackedVector3Array()
	var seg := length / float(bones - 1)
	for i in rings + 1:
		var t := float(i) / rings
		var s := _sample(prof, t)
		var z := t * length
		var c := Vector3(0, s[2], z)
		centres.append(c)
		var circ: float = PI * (float(s[0]) + float(s[1]))
		var fb := z / seg
		var b0 := clampi(int(floor(fb)), 0, bones - 1)
		var b1 := mini(b0 + 1, bones - 1)
		var w1 := clampf(fb - b0, 0.0, 1.0)
		if b1 == b0:
			w1 = 0.0
		for j in ring:
			var a := TAU * float(j) / sides
			verts.append(c + Vector3(cos(a) * s[0], sin(a) * s[1], 0))
			uvs.append(Vector2(float(j) / sides * circ, z))
			bone_idx.append_array([b0, b1, 0, 0])
			weights.append_array([1.0 - w1, w1, 0.0, 0.0])
	normals.resize(verts.size())
	for i in rings + 1:
		for j in ring:
			var jj := j % sides
			var du := verts[i * ring + (jj + 1) % sides] - verts[i * ring + (jj - 1 + sides) % sides]
			var dv := verts[mini(rings, i + 1) * ring + jj] - verts[maxi(0, i - 1) * ring + jj]
			var nn := du.cross(dv).normalized()
			if nn.dot(verts[i * ring + j] - centres[i]) < 0.0:
				nn = -nn
			normals[i * ring + j] = nn
	var idx := PackedInt32Array()
	for i in rings:
		for j in sides:
			var a := i * ring + j
			var b := i * ring + j + 1
			var c := (i + 1) * ring + j + 1
			var d := (i + 1) * ring + j
			_tri_out(idx, verts, normals, a, b, c)
			_tri_out(idx, verts, normals, a, c, d)
	# Cap both ends.
	for end in 2:
		var i := 0 if end == 0 else rings
		var dir := Vector3(0, 0, -1) if end == 0 else Vector3(0, 0, 1)
		var pole := verts.size()
		var s := _sample(prof, 0.0 if end == 0 else 1.0)
		verts.append(centres[i] + dir * minf(s[0], s[1]) * 0.5)
		normals.append(dir)
		uvs.append(Vector2(0, centres[i].z))
		var b := 0 if end == 0 else bones - 1
		bone_idx.append_array([b, b, 0, 0])
		weights.append_array([1.0, 0.0, 0.0, 0.0])
		for j in sides:
			_tri_out(idx, verts, normals, i * ring + j, i * ring + j + 1, pole)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_BONES] = bone_idx
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_cache[key] = mesh
	return mesh


## Fin / wing membrane: a flat polygon (XY plane) with gently curved surface.
## `cup` bows the middle out along +Z. Double sided.
static func membrane(key: String, points: PackedVector2Array, cup := 0.0, thickness := 0.03) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var tris := Geometry2D.triangulate_polygon(points)
	var centroid := Vector2.ZERO
	var max_r := 0.001
	for p in points:
		centroid += p
	centroid /= maxf(1.0, points.size())
	for p in points:
		max_r = maxf(max_r, p.distance_to(centroid))
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for face in 2:
		var off := thickness * 0.5 * (1.0 if face == 0 else -1.0)
		var base := verts.size()
		for p in points:
			var d := p.distance_to(centroid) / max_r
			var z := cup * (1.0 - d * d) + off
			verts.append(Vector3(p.x, p.y, z))
			var g := (p - centroid) / max_r * cup * 2.0 / max_r
			var nn := Vector3(g.x, g.y, 1.0).normalized()
			normals.append(nn if face == 0 else -nn)
			uvs.append(p)
		for i in range(0, tris.size(), 3):
			_tri_out(idx, verts, normals, base + tris[i], base + tris[i + 1], base + tris[i + 2])
	var mesh := _commit(verts, normals, uvs, idx)
	_cache[key] = mesh
	return mesh


## Several meshes baked into one (one draw call): parts = [[mesh, Transform3D], ...].
## Mirrored transforms (negative determinant) keep their faces outward.
static func merge(key: String, parts: Array) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var a := _gather(parts, -1)
	var mesh := _commit(a[0], a[1], a[2], a[3])
	_cache[key] = mesh
	return mesh


## Rigid parts bound to bones of a skeleton, for skinned meshes:
## parts = [[mesh, rest Transform3D, bone index, (optional) second bone, (optional) weight of the second]].
## Returns the arrays of one surface (ARRAY_BONES / ARRAY_WEIGHTS filled).
static func skinned_parts(parts: Array) -> Array:
	var a := _gather(parts, 0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = a[0]
	arrays[Mesh.ARRAY_NORMAL] = a[1]
	arrays[Mesh.ARRAY_TEX_UV] = a[2]
	arrays[Mesh.ARRAY_INDEX] = a[3]
	arrays[Mesh.ARRAY_BONES] = a[4]
	arrays[Mesh.ARRAY_WEIGHTS] = a[5]
	return arrays


## A skinned mesh from surfaces given as arrays (see skinned_parts), cached by key.
static func skinned_mesh(key: String, surfaces: Array) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var mesh := ArrayMesh.new()
	for s: Array in surfaces:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, s)
	_cache[key] = mesh
	return mesh


## Surface arrays of a cached mesh (for combining a skinned tube with extra parts).
static func surface_arrays(mesh: Mesh, surface := 0) -> Array:
	return mesh.surface_get_arrays(surface)


static func _gather(parts: Array, skin: int) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for part: Array in parts:
		var m: Mesh = part[0]
		var xf: Transform3D = part[1]
		var nb := xf.basis.inverse().transposed()
		var flip := xf.basis.determinant() < 0.0
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var uv: Variant = arr[Mesh.ARRAY_TEX_UV]
			var base := verts.size()
			for i in v.size():
				verts.append(xf * v[i])
				normals.append((nb * n[i]).normalized() if n.size() > i else Vector3.UP)
				uvs.append((uv as PackedVector2Array)[i] if uv != null and (uv as PackedVector2Array).size() > i else Vector2.ZERO)
				if skin >= 0:
					var b0: int = part[2]
					var b1: int = part[3] if part.size() > 3 else b0
					var w1: float = part[4] if part.size() > 4 else 0.0
					bones.append_array([b0, b1, 0, 0])
					weights.append_array([1.0 - w1, w1, 0.0, 0.0])
			var ind: Variant = arr[Mesh.ARRAY_INDEX]
			var tri := PackedInt32Array()
			if ind == null or (ind as PackedInt32Array).is_empty():
				for i in v.size():
					tri.append(i)
			else:
				tri = ind
			for i in range(0, tri.size(), 3):
				if flip:
					idx.append_array([base + tri[i], base + tri[i + 2], base + tri[i + 1]])
				else:
					idx.append_array([base + tri[i], base + tri[i + 1], base + tri[i + 2]])
	return [verts, normals, uvs, idx, bones, weights]


# --- Helpers ---------------------------------------------------------------------

## Smoothly interpolated profile row at t: [rx, ry, offset_up, offset_side].
static func _sample(prof: Array, t: float) -> Array:
	var first: Array = prof[0]
	if t <= float(first[0]):
		return _row(first)
	for i in range(prof.size() - 1):
		var a: Array = prof[i]
		var b: Array = prof[i + 1]
		if t <= float(b[0]):
			var f := (t - float(a[0])) / maxf(0.0001, float(b[0]) - float(a[0]))
			f = f * f * (3.0 - 2.0 * f)
			var ra := _row(a)
			var rb := _row(b)
			return [lerpf(ra[0], rb[0], f), lerpf(ra[1], rb[1], f), lerpf(ra[2], rb[2], f), lerpf(ra[3], rb[3], f)]
	return _row(prof[prof.size() - 1])


static func _row(r: Array) -> Array:
	var rx := float(r[1])
	var ry := float(r[2]) if r.size() > 2 else rx
	var up := float(r[3]) if r.size() > 3 else 0.0
	var sd := float(r[4]) if r.size() > 4 else 0.0
	return [rx, ry, up, sd]


## Appends a triangle wound so its front face points along the vertex normals
## (Godot culls counter-clockwise-from-outside triangles as back faces).
static func _tri_out(idx: PackedInt32Array, verts: PackedVector3Array, normals: PackedVector3Array, a: int, b: int, c: int) -> void:
	var face := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	var nsum := normals[a] + normals[b] + normals[c]
	if face.dot(nsum) > 0.0:
		idx.append_array([a, c, b])
	else:
		idx.append_array([a, b, c])


static func _commit(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, idx: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
