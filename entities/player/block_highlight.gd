class_name BlockHighlight
extends Node3D
## Outline around the targeted block (FX layer, glows over the glyphs) and a
## crack overlay that grows while mining (opaque, so cracks become glyphs).

const CRACK_SHADER := preload("res://world/materials/block_crack.gdshader")

var _outline: MeshInstance3D
var _crack: MeshInstance3D
var _crack_mat := ShaderMaterial.new()
## Smooth ground: a soft ring where the pick will strike and decal cracks.
var _ring: Decal
var _cracks: Decal
var _smooth := false


func _ready() -> void:
	top_level = true
	_outline = MeshInstance3D.new()
	_outline.mesh = _box_lines(1.02)
	_outline.material_override = MaterialLibrary.fx(Color(1.0, 0.85, 0.6), Color(1.0, 0.55, 0.2), 1.6, false)
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_outline)
	_crack = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 1.004
	_crack.mesh = box
	_crack_mat.shader = CRACK_SHADER
	_crack.material_override = _crack_mat
	_crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_crack)
	_ring = Decal.new()
	_ring.size = Vector3(1.3, 0.8, 1.3)
	_ring.texture_albedo = _ring_texture()
	_ring.texture_emission = _ring.texture_albedo
	_ring.emission_energy = 1.4
	_ring.modulate = Color(1.0, 0.72, 0.4, 0.55)
	_ring.albedo_mix = 0.35
	_ring.cull_mask = 1
	add_child(_ring)
	_cracks = Decal.new()
	_cracks.size = Vector3(1.4, 0.9, 1.4)
	_cracks.texture_albedo = _crack_texture()
	_cracks.modulate = Color(0.05, 0.04, 0.03, 1.0)
	add_child(_cracks)
	visible = false


func show_target(hit: Dictionary, show: bool) -> void:
	visible = show and not hit.is_empty()
	if not visible:
		return
	_smooth = true  # A surface contact, never a visible voxel-selection box.
	_outline.visible = false
	# No target marker on natural ground: the crosshair is enough, and a glowing
	# ring on every surface you look at with a tool out is distracting.
	_ring.visible = false
	if _smooth:
		# Decals project along their -Y: line Y up with the surface normal.
		var n: Vector3 = hit.get("surface_normal", Vector3.UP)
		var x := n.cross(Vector3.FORWARD if absf(n.y) > 0.9 else Vector3.UP).normalized()
		global_transform = Transform3D(Basis(x, n, x.cross(n)), hit["point"])
	else:
		global_position = Vector3(hit["pos"]) + Vector3(0.5, 0.5, 0.5)
		global_rotation = Vector3.ZERO


func set_crack(progress: float) -> void:
	progress = clampf(progress, 0.0, 1.0)
	_crack.visible = progress > 0.02 and not _smooth
	_crack_mat.set_shader_parameter(&"progress", progress)
	_cracks.visible = progress > 0.02 and _smooth
	_cracks.modulate.a = 0.35 + progress * 0.65
	_cracks.size = Vector3.ONE * (0.5 + progress * 0.9) + Vector3(0, 0.4, 0)


static func _ring_texture() -> ImageTexture:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var d := Vector2(x - 63.5, y - 63.5).length() / 63.5
			var a := clampf(1.0 - absf(d - 0.78) / 0.09, 0.0, 1.0)
			a = a * a + clampf(1.0 - d, 0.0, 1.0) * 0.12
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


static func _crack_texture() -> ImageTexture:
	# Fissures: edges of a jittered Voronoi diagram, fading towards the rim.
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var pts: Array[Vector2] = []
	for i in 22:
		pts.append(Vector2(rng.randf(), rng.randf()) * 128.0)
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var p := Vector2(x, y)
			var d1 := 1e9
			var d2 := 1e9
			for q in pts:
				var d := p.distance_squared_to(q)
				if d < d1:
					d2 = d1
					d1 = d
				elif d < d2:
					d2 = d
			var edge := sqrt(d2) - sqrt(d1)
			var rim := clampf(1.0 - p.distance_to(Vector2(64, 64)) / 64.0, 0.0, 1.0)
			var a := clampf(1.0 - edge / 1.6, 0.0, 1.0) * clampf(rim * 2.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


static func _box_lines(size: float) -> ArrayMesh:
	var h := size * 0.5
	var c := [Vector3(-h, -h, -h), Vector3(h, -h, -h), Vector3(h, h, -h), Vector3(-h, h, -h),
		Vector3(-h, -h, h), Vector3(h, -h, h), Vector3(h, h, h), Vector3(-h, h, h)]
	var edges := [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	for e: Array in edges:
		verts.append(c[e[0]])
		verts.append(c[e[1]])
		uvs.append(Vector2(0.5, 0.5))
		uvs.append(Vector2(0.5, 0.5))
		colors.append(Color(1, 1, 1, 0.7))
		colors.append(Color(1, 1, 1, 0.7))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh
