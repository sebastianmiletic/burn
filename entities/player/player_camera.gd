class_name PlayerCamera
extends Camera3D
## Third-person over-the-shoulder camera with mouse look, voxel collision,
## smoothing and trauma-based shake. Top-level so it never inherits the
## player's rotation.

var target: Node3D
var yaw := 0.0
var pitch := -0.25
var distance := 4.4
var min_distance := 1.8
var max_distance := 9.0
var shoulder := 0.55
var pivot_height := 1.55

var _pivot := Vector3.ZERO
var _current_distance := 4.4
var _trauma := 0.0
var _shake_t := 0.0
var _noise := FastNoiseLite.new()


func _ready() -> void:
	top_level = true
	fov = float(Settings.get_value("graphics", "fov"))
	near = 0.08
	far = 600.0
	_noise.frequency = 3.5
	# Soft fill from the viewer's side so characters never collapse into
	# glyph-less silhouettes against bright ground.
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.82, 0.62)
	fill.light_energy = 0.55
	fill.omni_range = 9.0
	fill.omni_attenuation = 1.6
	fill.light_specular = 0.1
	fill.shadow_enabled = false
	fill.light_volumetric_fog_energy = 0.0
	add_child(fill)
	Events.screen_shake.connect(add_trauma)
	Settings.changed.connect(func(section: String, key: String) -> void:
		if section == "graphics" and key == "fov":
			fov = float(Settings.get_value("graphics", "fov")))


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount * float(Settings.get_value("gameplay", "camera_shake")), 0.0, 1.0)


func look(delta_mouse: Vector2) -> void:
	var sens := 0.0025 * float(Settings.get_value("gameplay", "mouse_sensitivity"))
	var inv := -1.0 if Settings.get_value("gameplay", "invert_y") else 1.0
	yaw -= delta_mouse.x * sens
	pitch = clampf(pitch - delta_mouse.y * sens * inv, -1.35, 1.1)


func zoom(step: float) -> void:
	distance = clampf(distance * (1.0 + step), min_distance, max_distance)


func follow(world: VoxelWorld, focus: Vector3, delta: float) -> void:
	var desired_pivot := focus + Vector3(0, pivot_height, 0)
	# Critically damped follow: frame-rate independent and jitter free.
	_pivot = _pivot.lerp(desired_pivot, 1.0 - exp(-delta * 18.0)) if _pivot != Vector3.ZERO else desired_pivot
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var side := basis.x * shoulder
	var back := basis.z
	var pivot := _pivot + side
	var want := distance
	if world != null:
		var hit := world.raycast(pivot, back, distance + 0.4)
		if not hit.is_empty():
			want = maxf(0.6, float(hit["distance"]) - 0.35)
	# Pull in fast, ease out slowly.
	var k := 1.0 - exp(-delta * (25.0 if want < _current_distance else 6.0))
	_current_distance = lerpf(_current_distance, want, k)
	global_transform = Transform3D(basis, pivot + back * _current_distance)

	_trauma = maxf(0.0, _trauma - delta * 1.4)
	_shake_t += delta
	if _trauma > 0.0:
		var s := _trauma * _trauma
		rotate_object_local(Vector3.RIGHT, _noise.get_noise_2d(_shake_t * 40.0, 0.0) * 0.06 * s)
		rotate_object_local(Vector3.UP, _noise.get_noise_2d(0.0, _shake_t * 40.0) * 0.06 * s)
		global_position += basis * Vector3(_noise.get_noise_2d(_shake_t * 30.0, 9.0), _noise.get_noise_2d(9.0, _shake_t * 30.0), 0.0) * 0.25 * s


func aim_ray() -> Array:
	return [global_position, -global_basis.z]
