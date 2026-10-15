class_name SpeedStreaks
extends GPUParticles3D
## Faint air/dust streaks peeling off a sprinting or rolling character.
## Created lazily by HumanoidModel the first time it sprints or dodges.

const DUST := preload("res://models/fx/dust.gdshader")

var _pm := ParticleProcessMaterial.new()


func _init() -> void:
	amount = 18
	lifetime = 0.35
	local_coords = false
	emitting = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 4, 6))
	_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_pm.emission_box_extents = Vector3(0.25, 0.7, 0.2)
	_pm.direction = Vector3(0, 0, 1)
	_pm.spread = 8.0
	_pm.initial_velocity_min = 2.0
	_pm.initial_velocity_max = 4.0
	_pm.gravity = Vector3.ZERO
	_pm.damping_min = 2.0
	_pm.damping_max = 3.0
	_pm.particle_flag_align_y = true
	_pm.color = Color(0.75, 0.72, 0.66, 1.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.add_point(0.2, Color(1, 1, 1, 0.5))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	_pm.color_ramp = gt
	process_material = _pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.7)
	var m := ShaderMaterial.new()
	m.shader = DUST
	m.set_shader_parameter(&"streak", true)
	m.set_shader_parameter(&"density", 0.35)
	m.set_shader_parameter(&"soft_distance", 0.1)
	quad.material = m
	draw_pass_1 = quad


## velocity: world velocity of the character; strength 0..1.
func drive(velocity: Vector3, strength: float) -> void:
	var on := strength > 0.05
	if on != emitting:
		emitting = on
	if on:
		var v := velocity
		v.y = 0.0
		var dir := -v.normalized() if v.length() > 0.5 else Vector3.BACK
		_pm.direction = dir
		_pm.initial_velocity_min = v.length() * 0.25
		_pm.initial_velocity_max = v.length() * 0.5
		amount_ratio = clampf(strength, 0.1, 1.0)
