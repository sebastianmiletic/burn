extends RefCounted
## Synthetic smooth terrain for flora tests: a noise heightfield cut into 16 m chunks, with the
## same `surface` dictionaries the smooth mesher hands to Flora.plan_chunk().

const CHUNK := 16

var noise := FastNoiseLite.new()
var size_chunks := 6
var region_fn: Callable   # (x, z) -> block id; defaults to grass


func _init(seed_value := 3) -> void:
	noise.seed = seed_value
	noise.frequency = 0.012
	noise.fractal_octaves = 4


func height(x: float, z: float) -> float:
	return noise.get_noise_2d(x, z) * 9.0 + noise.get_noise_2d(x * 3.1, z * 3.1) * 0.6


func block_at(x: float, z: float) -> int:
	if region_fn.is_valid():
		return region_fn.call(x, z)
	return 3


## Up-facing triangles of chunk (cx, cz) at 1 m resolution, chunk-local coordinates
## (origin = (cx*16, oy, cz*16)).
func surface(cx: int, cz: int, oy: int) -> Dictionary:
	var tris := PackedVector3Array()
	var normals := PackedVector3Array()
	var blocks := PackedByteArray()
	var sky := PackedFloat32Array()
	var ox := cx * CHUNK
	var oz := cz * CHUNK
	for z in CHUNK:
		for x in CHUNK:
			var p00 := Vector3(x, height(ox + x, oz + z) - oy, z)
			var p10 := Vector3(x + 1, height(ox + x + 1, oz + z) - oy, z)
			var p01 := Vector3(x, height(ox + x, oz + z + 1) - oy, z + 1)
			var p11 := Vector3(x + 1, height(ox + x + 1, oz + z + 1) - oy, z + 1)
			for t in [[p00, p11, p10], [p00, p01, p11]]:
				var a: Vector3 = t[0]
				var b: Vector3 = t[1]
				var c: Vector3 = t[2]
				var n := (c - a).cross(b - a).normalized()
				if n.y < 0.0:
					n = -n
				if n.y <= 0.5:
					continue
				tris.append(a)
				tris.append(b)
				tris.append(c)
				normals.append(n)
				var centre := (a + b + c) / 3.0
				blocks.append(block_at(ox + centre.x, oz + centre.z))
				sky.append(1.0)
	return {"tris": tris, "normals": normals, "blocks": blocks, "sky": sky}


## Ground mesh for one chunk (world coordinates relative to the chunk origin), vertex-coloured by block.
func ground_mesh(cx: int, cz: int, oy: int, colors: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ox := cx * CHUNK
	var oz := cz * CHUNK
	var res := 2
	for z in CHUNK * res:
		for x in CHUNK * res:
			var fx := float(x) / res
			var fz := float(z) / res
			var s := 1.0 / res
			var q := [Vector3(fx, 0, fz), Vector3(fx + s, 0, fz), Vector3(fx, 0, fz + s), Vector3(fx + s, 0, fz + s)]
			for i in 4:
				var v: Vector3 = q[i]
				v.y = height(ox + v.x, oz + v.z) - oy
				q[i] = v
			for idx in [0, 1, 3, 0, 3, 2]:
				var v: Vector3 = q[idx]
				var e := 0.1
				var nx := height(ox + v.x - e, oz + v.z) - height(ox + v.x + e, oz + v.z)
				var nz := height(ox + v.x, oz + v.z - e) - height(ox + v.x, oz + v.z + e)
				st.set_normal(Vector3(nx, 2.0 * e, nz).normalized())
				st.set_color(colors.get(block_at(ox + v.x, oz + v.z), Color(0.3, 0.3, 0.2)))
				st.add_vertex(v)
	return st.commit()
