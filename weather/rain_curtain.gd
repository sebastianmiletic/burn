class_name RainCurtain
extends GPUParticles3D
## Rain that follows the active camera. Driven by `intensity` and `wind`.
##
## * ASCII styles: streaks are opaque, tagged STREAK and aligned to their
##   velocity, so the ASCII pass draws them as slanted strokes.
## * "ASCII off": soft, semi-transparent motion-blurred streaks.
## Drops collide with a GPUParticlesCollisionHeightField3D that follows the
## camera (rendered from the world's geometry), so rain stops at roofs and
## overhangs, and each impact spawns a splash (Medium quality and up).

@export var intensity := 1.0:
	set(value):
		intensity = clampf(value, 0.0, 1.0)
		amount_ratio = intensity
		if _splash != null:
			_splash.amount_ratio = intensity
@export var wind := Vector3(2.5, 0.0, 0.8)
@export var fall_speed := 15.0
@export var box_size := Vector3(40.0, 2.0, 40.0)
@export var height_above_camera := 13.0
## Light level of the drops (Weather sets it from the sky).
var brightness := 1.0:
	set(value):
		brightness = value
		_soft_mat.set_shader_parameter(&"brightness", value)
		_splash_mat.set_shader_parameter(&"brightness", value)

## Keep the roof heightfield running even when no rain falls (snow uses it).
var keep_collider := false

var _pm := ParticleProcessMaterial.new()
var _soft_mat := ShaderMaterial.new()
var _splash_mat := ShaderMaterial.new()
var _quad := QuadMesh.new()
var _splash: GPUParticles3D
var _collider: GPUParticlesCollisionHeightField3D
var _raw := false


func _ready() -> void:
	var q := int(Settings.get_value("graphics", "quality"))
	amount = [2600, 4800, 7000, 10000][q]
	lifetime = 1.5
	preprocess = 1.5
	local_coords = false
	fixed_fps = 0
	visibility_aabb = AABB(Vector3(-45, -45, -45), Vector3(90, 90, 90))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_pm.emission_box_extents = box_size * 0.5
	_pm.gravity = Vector3.ZERO
	_pm.particle_flag_align_y = true
	_pm.scale_min = 0.7
	_pm.scale_max = 1.2
	_pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_pm.collision_use_scale = false
	collision_base_size = 0.02
	_update_velocity()
	process_material = _pm
	_quad.size = Vector2(1.0, 1.0)
	draw_pass_1 = _quad
	_soft_mat.shader = preload("res://weather/rain_soft.gdshader")
	_splash_mat.shader = preload("res://world/sky/splash.gdshader")

	# The roof over the rain: a heightfield of everything below the emitter.
	_collider = GPUParticlesCollisionHeightField3D.new()
	_collider.size = Vector3(48.0, 48.0, 48.0)
	_collider.resolution = [GPUParticlesCollisionHeightField3D.RESOLUTION_256, GPUParticlesCollisionHeightField3D.RESOLUTION_256,
			GPUParticlesCollisionHeightField3D.RESOLUTION_512, GPUParticlesCollisionHeightField3D.RESOLUTION_512][q]
	_collider.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	_collider.follow_camera_enabled = true
	add_child(_collider)
	_collider.top_level = true

	if q >= Settings.Quality.MEDIUM:
		_splash = GPUParticles3D.new()
		_splash.amount = [0, 1400, 2400, 3600][q]
		_splash.lifetime = 0.35
		_splash.local_coords = false
		_splash.visibility_aabb = visibility_aabb
		_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var spm := ParticleProcessMaterial.new()
		spm.direction = Vector3.UP
		spm.spread = 55.0
		spm.initial_velocity_min = 0.8
		spm.initial_velocity_max = 2.2
		spm.gravity = Vector3(0, -9.8, 0)
		spm.scale_min = 0.6
		spm.scale_max = 1.3
		spm.particle_flag_align_y = true
		_splash.process_material = spm
		var sq := QuadMesh.new()
		sq.size = Vector2(1.0, 1.0)
		sq.material = _splash_mat
		_splash.draw_pass_1 = sq
		add_child(_splash)
		_splash.top_level = true
		sub_emitter = get_path_to(_splash)
		_pm.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_AT_COLLISION
		_pm.sub_emitter_amount_at_collision = 1
	_apply_style()
	Settings.changed.connect(func(section: String, key: String) -> void:
		if section == "graphics" and key == "style":
			_apply_style())
	amount_ratio = intensity


func _apply_style() -> void:
	_raw = int(Settings.get_value("graphics", "style")) == Settings.Style.OFF
	_quad.material = _soft_mat if _raw else MaterialLibrary.rain()


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	# Lead the camera slightly so streaks fill the view while it moves.
	var forward := -camera.global_basis.z
	forward.y = 0.0
	global_position = camera.global_position + forward.normalized() * 6.0 + Vector3.UP * height_above_camera
	_collider.global_position = camera.global_position + Vector3.UP * 8.0
	_collider.visible = visible or keep_collider
	_update_velocity()


## Screen-space lean of the rain for this camera (-1 left .. 1 right).
func screen_slant(camera: Camera3D) -> float:
	var v := _velocity()
	var right := camera.global_basis.x
	return clampf(v.dot(right) / maxf(absf(v.y), 0.001) * 2.0, -1.0, 1.0)


func _velocity() -> Vector3:
	return Vector3(wind.x, -fall_speed, wind.z)


func _update_velocity() -> void:
	var v := _velocity()
	_pm.direction = v.normalized()
	_pm.spread = 2.0
	_pm.initial_velocity_min = v.length() * 0.9
	_pm.initial_velocity_max = v.length() * 1.1
