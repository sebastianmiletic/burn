class_name FireStream
extends GPUParticles3D
## A cone of fire blown along the node's -Z axis (dragon and Cerberus
## breath, Hades' pillars). FX layer: additive, glows over the glyphs.

var _light: OmniLight3D


func setup(length := 14.0, spread_deg := 14.0, size := 1.4, hot := Color(1.0, 0.85, 0.5), cool := Color(1.0, 0.28, 0.04)) -> FireStream:
	amount = 220
	lifetime = 0.9
	local_coords = false
	emitting = false
	visibility_aabb = AABB(Vector3(-length, -length, -length * 1.5), Vector3(length * 2, length * 2, length * 3))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.direction = Vector3(0, 0, -1)
	pm.spread = spread_deg
	pm.initial_velocity_min = length * 1.0
	pm.initial_velocity_max = length * 1.35
	pm.gravity = Vector3(0, 2.0, 0)
	pm.damping_min = 1.0
	pm.damping_max = 3.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 2.0
	pm.turbulence_noise_scale = 3.0
	var c := Curve.new()
	c.add_point(Vector2(0, 0.25))
	c.add_point(Vector2(0.4, 1.0))
	c.add_point(Vector2(1, 1.6))
	var ct := CurveTexture.new()
	ct.curve = c
	pm.scale_curve = ct
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.6, Color(1, 1, 1, 0.6))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = MaterialLibrary.fx(hot, cool, 6.0)
	draw_pass_1 = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.5, 0.2)
	_light.omni_range = length
	_light.light_energy = 0.0
	_light.position = Vector3(0, 0, -length * 0.35)
	_light.light_volumetric_fog_energy = 3.0
	add_child(_light)
	return self


func set_on(on: bool) -> void:
	emitting = on
	var tw := create_tween()
	tw.tween_property(_light, "light_energy", 5.0 if on else 0.0, 0.25)
