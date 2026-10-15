class_name DistantLand
extends MeshInstance3D
## A coarse, non-colliding silhouette beyond the streamed terrain. Built once
## on the loading worker; underlay is slightly inset so detailed terrain wins.
const STEP := 8
var gen: WorldGen
var _mat: ShaderMaterial
var _coverage: ImageTexture
var _coverage_timer := 0.0

static func arrays_for(world_gen: WorldGen) -> Array:
	var n := world_gen.size / STEP + 1
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	vertices.resize(n * n)
	colors.resize(n * n)
	normals.resize(n * n)
	var detail := world_gen.make_detail_noise()
	var ridge := world_gen.make_ridge_noise()
	for z in n:
		for x in n:
			var wx := mini(x * STEP, world_gen.size - 1)
			var wz := mini(z * STEP, world_gen.size - 1)
			var h := world_gen.column_f(wx, wz, detail, ridge).x + 0.4
			vertices[x + z * n] = Vector3(wx, h, wz)
			var color: Color = MapImage.BIOME_COLORS.get(world_gen.biome_at(wx, wz), Color(0.4, 0.4, 0.35))
			if h > 85:
				color = color.lerp(Color(0.84, 0.87, 0.9), smoothstep(85, 180, h))
			colors[x + z * n] = color
	for z in n:
		for x in n:
			var dx := vertices[mini(x + 1, n - 1) + z * n] - vertices[maxi(0, x - 1) + z * n]
			var dz := vertices[x + mini(z + 1, n - 1) * n] - vertices[x + maxi(z - 1, 0) * n]
			normals[x + z * n] = dz.cross(dx).normalized()
			if x < n - 1 and z < n - 1:
				var i := x + z * n
				indices.append_array([i, i + 1, i + n, i + 1, i + n + 1, i + n])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = vertices
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_INDEX] = indices
	return out

func setup(world_gen: WorldGen, arrays: Array) -> void:
	gen = world_gen
	var terrain := ArrayMesh.new()
	terrain.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = terrain
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://world/materials/distant_land.gdshader")
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _process(delta: float) -> void:
	var w := GameWorld.instance
	if w == null or w.local_player == null:
		return
	visible = w.local_dimension == gen.dimension
	if not visible:
		return
	_coverage_timer -= delta
	if _coverage_timer <= 0.0:
		_coverage_timer = 0.25
		var image := w.world_for(gen.dimension).horizon_coverage()
		if _coverage == null:
			_coverage = ImageTexture.create_from_image(image)
			_mat.set_shader_parameter(&"coverage", _coverage)
			_mat.set_shader_parameter(&"world_size", float(image.get_width() * Chunk.SIZE))
		else:
			_coverage.update(image)
	var pos := w.local_player.global_position
	_mat.set_shader_parameter(&"focus", pos)
	# Closer coarse terrain bridges streaming gaps during fast traversal.
	_mat.set_shader_parameter(&"near_radius", maxf(32, w.world_for(0).view_radius * 16 - 48))
