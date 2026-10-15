class_name FlakeFall
extends GPUParticles3D
## Slow precipitation around the camera: snow in the Frost Peaks, wind-blown
## dust in the Cinder Wastes, ash in the underworld. Opaque STREAK flakes for
## the ASCII styles, soft transparent ones with ASCII off. Flakes stop at roofs
## (they collide with the RainCurtain's heightfield).

enum Kind { SNOW, DUST, ASH }

var intensity := 0.0:
	set(value):
		intensity = clampf(value, 0.0, 1.0)
		amount_ratio = maxf(intensity, 0.001)
## Horizontal wind (m/s) the flakes drift with.
var wind := Vector3.ZERO
var brightness := 1.0:
	set(value):
		brightness = value
		_hard.set_shader_parameter(&"brightness", value)
		_soft.set_shader_parameter(&"brightness", value * 0.9)

var kind := Kind.SNOW
var _pm := ParticleProcessMaterial.new()
var _hard := ShaderMaterial.new()
var _soft := ShaderMaterial.new()
var _quad := QuadMesh.new()
var _fall := 1.2
var _height := 9.0


func _init(k := Kind.SNOW) -> void:
	kind = k


func _ready() -> void:
	var q := int(Settings.get_value("graphics", "quality"))
	var tint := Color(0.92, 0.94, 0.98)
	var size := 0.07
	match kind:
		Kind.SNOW:
			amount = [1800, 3200, 4800, 7000][q]
			lifetime = 9.0
			_fall = 1.3
		Kind.DUST:
			amount = [1200, 2200, 3400, 5000][q]
			lifetime = 4.0
			_fall = 0.15
			_height = 3.0
			tint = Color(0.62, 0.48, 0.34)
			size = 0.03
		Kind.ASH:
			amount = [700, 1200, 1800, 2600][q]
			lifetime = 8.0
			_fall = 0.5
			tint = Color(0.32, 0.3, 0.29)
			size = 0.04
	preprocess = lifetime
	local_coords = false
	visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_pm.emission_box_extents = Vector3(28.0, 6.0 if kind != Kind.DUST else 3.0, 28.0)
	_pm.gravity = Vector3.ZERO
	_pm.spread = 25.0
	_pm.scale_min = 0.6
	_pm.scale_max = 1.4
	_pm.turbulence_enabled = true
	_pm.turbulence_noise_strength = 1.4 if kind == Kind.SNOW else 2.2
	_pm.turbulence_noise_scale = 4.0
	_pm.turbulence_noise_speed_random = 0.6
	_pm.turbulence_influence_min = 0.05
	_pm.turbulence_influence_max = 0.18
	_pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_pm.collision_use_scale = false
	collision_base_size = 0.02
	process_material = _pm
	for m: ShaderMaterial in [_hard, _soft]:
		m.set_shader_parameter(&"tint", Vector3(tint.r, tint.g, tint.b))
		m.set_shader_parameter(&"size", size)
	_hard.shader = preload("res://world/sky/flake.gdshader")
	_soft.shader = preload("res://world/sky/flake_soft.gdshader")
	_quad.size = Vector2(1.0, 1.0)
	draw_pass_1 = _quad
	_quad.material = _soft
	amount_ratio = maxf(intensity, 0.001)


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var forward := -camera.global_basis.z
	forward.y = 0.0
	# Upwind of the camera, so drifting flakes cross the view.
	var upwind := -wind * clampf(_height / maxf(_fall, 0.3), 0.0, 4.0) * 0.5
	upwind.y = 0.0
	global_position = camera.global_position + forward.normalized() * 6.0 + Vector3.UP * _height + upwind.limit_length(14.0)
	var v := Vector3(wind.x, -_fall, wind.z)
	_pm.direction = v.normalized()
	_pm.initial_velocity_min = v.length() * 0.7
	_pm.initial_velocity_max = v.length() * 1.2
