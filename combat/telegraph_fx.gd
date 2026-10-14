class_name TelegraphFx
extends MeshInstance3D
## Visual for a telegraphed attack (see TelegraphShape for the geometry).
## Fills over `duration`, flashes as the attack lands, then fades away.

const SHADER := preload("res://combat/telegraph.gdshader")
const SHAPES := {"circle": 0, "cone": 1, "line": 2, "ring": 3}

var _mat := ShaderMaterial.new()


static func spawn(parent: Node3D, shape: String, pos: Vector3, dir: Vector3, size: Vector3, duration: float) -> TelegraphFx:
	var fx := TelegraphFx.new()
	parent.add_child(fx)
	fx._setup(shape, pos, dir, size, duration)
	return fx


func _setup(shape: String, pos: Vector3, dir: Vector3, size: Vector3, duration: float) -> void:
	var plane := PlaneMesh.new()
	match shape:
		"circle":
			plane.size = Vector2(size.x, size.x) * 2.0
		"ring":
			plane.size = Vector2(size.y, size.y) * 2.0
		"cone":
			plane.size = Vector2(size.x, size.x) * 2.0
		"line":
			plane.size = Vector2(size.y, size.x)
			plane.center_offset = Vector3(0, 0, -size.x * 0.5)
	plane.subdivide_width = 0
	plane.subdivide_depth = 0
	mesh = plane
	_mat.shader = SHADER
	_mat.set_shader_parameter(&"shape", SHAPES.get(shape, 0))
	_mat.set_shader_parameter(&"size", Vector2(size.x, size.y))
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	global_position = pos + Vector3(0, 0.08, 0)
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length_squared() > 1e-6:
		look_at(global_position + flat.normalized(), Vector3.UP)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter(&"fill", v), 0.0, 1.0, maxf(0.05, duration))
	tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter(&"flash", v), 1.0, 0.0, 0.3)
	tw.parallel().tween_method(func(v: float) -> void: _mat.set_shader_parameter(&"alpha", v), 1.0, 0.0, 0.35)
	tw.tween_callback(queue_free)
