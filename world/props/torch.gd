class_name Torch
extends Node3D
## Wall or standing torch: iron bowl, additive flame and sparks (emissive FX
## layer, never ASCII), and a flickering shadow-casting light that also lights
## the volumetric fog.

@export var light_color := Color(1.0, 0.56, 0.24)
@export var light_energy := 2.6
@export var light_range := 10.0
@export var cast_shadows := true
@export var flicker_strength := 0.35

var light: OmniLight3D

var _noise := FastNoiseLite.new()
var _t := 0.0
var _base_position := Vector3.ZERO


func _ready() -> void:
	_noise.seed = randi()
	_noise.frequency = 2.2
	_build_bowl()
	_build_flame()
	_build_sparks()
	light = OmniLight3D.new()
	light.position = Vector3(0.0, 0.35, 0.0)
	light.light_color = light_color
	light.light_energy = light_energy
	light.omni_range = light_range
	light.omni_attenuation = 1.4
	light.shadow_enabled = cast_shadows
	light.shadow_blur = 1.5
	light.light_volumetric_fog_energy = 2.0
	light.light_size = 0.12
	add_child(light)
	_base_position = light.position


func _process(delta: float) -> void:
	_t += delta
	var n := _noise.get_noise_1d(_t * 10.0)
	var n2 := _noise.get_noise_1d(_t * 3.0 + 50.0)
	light.light_energy = light_energy * (1.0 + n * flicker_strength + n2 * flicker_strength * 0.5)
	light.light_color = light_color.lerp(Color(1.0, 0.75, 0.4), clampf(n * 0.5 + 0.25, 0.0, 1.0))
	light.position = _base_position + Vector3(n2, absf(n), n) * 0.03


func _build_bowl() -> void:
	var bowl := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.16
	mesh.bottom_radius = 0.07
	mesh.height = 0.18
	mesh.radial_segments = 10
	bowl.mesh = mesh
	bowl.material_override = MaterialLibrary.stone(&"iron")
	add_child(bowl)
	var stem := MeshInstance3D.new()
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.035
	stem_mesh.bottom_radius = 0.045
	stem_mesh.height = 0.5
	stem_mesh.radial_segments = 6
	stem.mesh = stem_mesh
	stem.position = Vector3(0.0, -0.32, 0.0)
	stem.material_override = MaterialLibrary.stone(&"iron")
	add_child(stem)


func _build_flame() -> void:
	var flame := GPUParticles3D.new()
	flame.amount = 48
	flame.lifetime = 0.55
	flame.position = Vector3(0.0, 0.12, 0.0)
	flame.local_coords = false
	flame.visibility_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 3, 2))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.07
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0.0, 1.6, 0.0)
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	pm.scale_curve = _curve([Vector2(0.0, 0.6), Vector2(0.25, 1.0), Vector2(1.0, 0.1)])
	pm.color_ramp = _fade_gradient()
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 1.5
	flame.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.26, 0.34)
	quad.material = MaterialLibrary.fx(Color(1.0, 0.82, 0.45), Color(1.0, 0.28, 0.04), 7.0)
	flame.draw_pass_1 = quad
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flame)


func _build_sparks() -> void:
	var sparks := GPUParticles3D.new()
	sparks.amount = 14
	sparks.lifetime = 1.6
	sparks.position = Vector3(0.0, 0.2, 0.0)
	sparks.local_coords = false
	sparks.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 5, 4))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0.0, 0.25, 0.0)
	pm.damping_min = 0.4
	pm.damping_max = 0.8
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_noise_scale = 2.5
	pm.color_ramp = _fade_gradient()
	sparks.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.045, 0.045)
	quad.material = MaterialLibrary.fx(Color(1.0, 0.9, 0.6), Color(1.0, 0.4, 0.08), 14.0)
	sparks.draw_pass_1 = quad
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sparks)


static func _curve(points: Array[Vector2]) -> CurveTexture:
	var c := Curve.new()
	for p in points:
		c.add_point(p)
	var tex := CurveTexture.new()
	tex.curve = c
	return tex


static func _fade_gradient() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex
