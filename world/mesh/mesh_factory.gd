class_name MeshFactory
extends RefCounted
## Procedural meshes that the primitive mesh types don't cover.


## Torus knot tube (p, q) — the rotating relic in the test scene.
static func torus_knot(p: int, q: int, radius: float, tube: float, segments: int, sides: int) -> ArrayMesh:
	var centers := PackedVector3Array()
	for i in segments:
		var t := TAU * float(i) / float(segments)
		var r := radius * (2.0 + cos(q * t)) / 3.0
		centers.append(Vector3(r * cos(p * t), radius * -sin(q * t) / 3.0, r * sin(p * t)))

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in segments:
		var c := centers[i]
		var tangent := (centers[(i + 1) % segments] - centers[(i - 1 + segments) % segments]).normalized()
		var ref := Vector3.UP if absf(tangent.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		var bx := tangent.cross(ref).normalized()
		var by := tangent.cross(bx).normalized()
		for s in sides:
			var a := TAU * float(s) / float(sides)
			var n := bx * cos(a) + by * sin(a)
			verts.append(c + n * tube)
			normals.append(n)
			uvs.append(Vector2(float(s) / sides, float(i) / segments))
	for i in segments:
		var i2 := (i + 1) % segments
		for s in sides:
			var s2 := (s + 1) % sides
			var a := i * sides + s
			var b := i2 * sides + s
			var c := i2 * sides + s2
			var d := i * sides + s2
			indices.append_array([a, b, c, a, c, d])
	return _build(verts, normals, uvs, indices)


## A single tapered, slightly curved grass blade. UV.y = 0 at the root, 1 at the tip.
static func grass_blade(height: float, width: float, segments: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in segments + 1:
		var t := float(i) / segments
		var w := width * (1.0 - t * 0.92) * 0.5
		var lean := t * t * height * 0.18
		var y := t * height
		verts.append(Vector3(-w, y, lean))
		verts.append(Vector3(w, y, lean))
		var n := Vector3(0.0, -0.36 * t, 1.0).normalized()
		normals.append(n)
		normals.append(n)
		uvs.append(Vector2(0.0, t))
		uvs.append(Vector2(1.0, t))
	for i in segments:
		var a := i * 2
		indices.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	return _build(verts, normals, uvs, indices)


## Simple tapered rock: a jittered, flattened icosphere-like blob.
static func rock(radius: float, seed_value: int) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 1.4
	sphere.radial_segments = 10
	sphere.rings = 6
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var offsets := {}
	for i in verts.size():
		var key := verts[i].snappedf(0.001)
		if not offsets.has(key):
			offsets[key] = 0.75 + rng.randf() * 0.45
		verts[i] *= offsets[key]
	arrays[Mesh.ARRAY_VERTEX] = verts
	var st := SurfaceTool.new()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	st.create_from(mesh, 0)
	st.set_smooth_group(-1)
	st.generate_normals()
	return st.commit()


static func _build(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
