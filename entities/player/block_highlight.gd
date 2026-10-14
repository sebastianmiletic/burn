class_name BlockHighlight
extends Node3D
## Outline around the targeted block (FX layer, glows over the glyphs) and a
## crack overlay that grows while mining (opaque, so cracks become glyphs).

const CRACK_SHADER := preload("res://world/materials/block_crack.gdshader")

var _outline: MeshInstance3D
var _crack: MeshInstance3D
var _crack_mat := ShaderMaterial.new()


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
	visible = false


func show_target(hit: Dictionary, show: bool) -> void:
	visible = show and not hit.is_empty()
	if visible:
		global_position = Vector3(hit["pos"]) + Vector3(0.5, 0.5, 0.5)
		global_rotation = Vector3.ZERO


func set_crack(progress: float) -> void:
	_crack.visible = progress > 0.02
	_crack_mat.set_shader_parameter(&"progress", clampf(progress, 0.0, 1.0))


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
