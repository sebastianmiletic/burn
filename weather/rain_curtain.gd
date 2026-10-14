class_name RainCurtain
extends GPUParticles3D
## Rain streaks that follow the active camera. Streaks are opaque, tagged
## STREAK, and aligned to their velocity, so the ASCII pass draws them as
## slanted strokes. (The full weather state machine arrives in Milestone 2;
## this emitter is driven directly by `intensity` and `wind`.)

@export var intensity := 1.0:
	set(value):
		intensity = clampf(value, 0.0, 1.0)
		amount_ratio = intensity
@export var wind := Vector3(2.5, 0.0, 0.8)
@export var fall_speed := 15.0
@export var box_size := Vector3(36.0, 2.0, 36.0)
@export var height_above_camera := 11.0

var _pm := ParticleProcessMaterial.new()


func _ready() -> void:
	amount = 3200
	lifetime = 1.3
	preprocess = 1.3
	local_coords = false
	fixed_fps = 0
	visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_pm.emission_box_extents = box_size * 0.5
	_pm.gravity = Vector3.ZERO
	_pm.particle_flag_align_y = true
	_pm.scale_min = 0.7
	_pm.scale_max = 1.2
	_update_velocity()
	process_material = _pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = MaterialLibrary.rain()
	draw_pass_1 = quad
	amount_ratio = intensity


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	# Lead the camera slightly so streaks fill the view while it moves.
	var forward := -camera.global_basis.z
	forward.y = 0.0
	global_position = camera.global_position + forward.normalized() * 6.0 + Vector3.UP * height_above_camera
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
