class_name PlayerCamera
extends Camera3D
## First-person eye camera (default) or third-person over-the-shoulder camera,
## with mouse look, collision, head bob, landing dip and trauma-based shake.
## Top-level so it never inherits the player's rotation.

var target: Node3D
var yaw := 0.0
var pitch := -0.25
var distance := 4.4
var min_distance := 1.8
var max_distance := 9.0
var shoulder := 0.55
var pivot_height := 1.55
var first_person := true
var eye_height := 1.62
## Walking speed (m/s) and grounded state, set by the Player each frame for head bob.
var move_speed := 0.0
var grounded := true

var _pivot := Vector3.ZERO
var _current_distance := 4.4
var _trauma := 0.0
var _shake_t := 0.0
var _noise := FastNoiseLite.new()
var _bob_phase := 0.0
var _bob := 0.0
var _dip := 0.0
var _dip_v := 0.0
var _eye := Vector3.ZERO
var _look_pending := Vector2.ZERO


func _ready() -> void:
	top_level = true
	fov = float(Settings.get_value("graphics", "fov"))
	near = 0.05
	# The overworld horizon mesh spans kilometres, not the near chunk radius.
	far = 4600.0
	_noise.frequency = 3.5
	# Soft fill from the viewer's side so characters never collapse into
	# glyph-less silhouettes against bright ground.
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.82, 0.62)
	fill.light_energy = 0.85
	fill.omni_range = 9.0
	fill.omni_attenuation = 1.6
	fill.light_specular = 0.1
	fill.shadow_enabled = false
	fill.light_volumetric_fog_energy = 0.0
	# Above and behind the eye: lights what you look at without blowing out
	# the first-person hands half a metre away.
	fill.position = Vector3(0.0, 0.9, 1.6)
	add_child(fill)
	Events.screen_shake.connect(add_trauma)
	first_person = bool(Settings.get_value("gameplay", "first_person"))
	Settings.changed.connect(func(section: String, key: String) -> void:
		if section == "graphics" and key == "fov":
			fov = float(Settings.get_value("graphics", "fov")))


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount * float(Settings.get_value("gameplay", "camera_shake")) * Settings.motion_scale(), 0.0, 1.0)
	# Controller rumble follows hits and shakes (Settings > Controls).
	var rumble := float(Settings.get_value("input", "pad_vibration"))
	if rumble > 0.0:
		var k := clampf(amount, 0.0, 1.0) * rumble
		for pad in Input.get_connected_joypads():
			Input.start_joy_vibration(pad, clampf(k * 0.8, 0.0, 1.0), clampf(k, 0.0, 1.0), 0.12 + k * 0.25)


## Mouse look. With smoothing on, the movement is eased in over a few frames.
func look(delta_mouse: Vector2) -> void:
	if bool(Settings.get_value("input", "mouse_smoothing")):
		_look_pending += delta_mouse
		return
	_turn(delta_mouse, float(Settings.get_value("gameplay", "mouse_sensitivity")), bool(Settings.get_value("gameplay", "invert_y")))


func _turn(delta_px: Vector2, sensitivity: float, invert: bool) -> void:
	var sens := 0.0025 * sensitivity
	var inv := -1.0 if invert else 1.0
	yaw -= delta_px.x * sens
	pitch = clampf(pitch - delta_px.y * sens * inv, -1.5 if first_person else -1.35, 1.5 if first_person else 1.1)


## Smoothed mouse and the right stick, once per frame before placing the camera.
func _frame_look(delta: float) -> void:
	if _look_pending != Vector2.ZERO:
		var step := _look_pending * (1.0 - exp(-delta * 28.0))
		if _look_pending.length() < 0.05:
			step = _look_pending
		_look_pending -= step
		_turn(step, float(Settings.get_value("gameplay", "mouse_sensitivity")), bool(Settings.get_value("gameplay", "invert_y")))
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_look_pending = Vector2.ZERO
		return
	var stick := Vector2.ZERO
	for pad in Input.get_connected_joypads():
		stick += Vector2(Input.get_joy_axis(pad, JOY_AXIS_RIGHT_X), Input.get_joy_axis(pad, JOY_AXIS_RIGHT_Y))
	var dz := clampf(float(Settings.get_value("input", "pad_deadzone")), 0.05, 0.6)
	var mag := minf(stick.length(), 1.0)
	if mag <= dz:
		return
	# Radial dead zone with a squared response: fine aim near the centre.
	var k := pow((mag - dz) / (1.0 - dz), 2.0)
	var rate := stick.normalized() * k * 2.6 * float(Settings.get_value("input", "pad_look_sensitivity")) * delta
	# Expressed in mouse pixels at sensitivity 1 so _turn's clamps apply.
	_turn(rate / 0.0025, 1.0, bool(Settings.get_value("input", "pad_invert_y")))


## Landing: the view dips with the impact and springs back.
func land(impact: float) -> void:
	_dip_v -= clampf(impact * 0.045, 0.0, 0.9)


func zoom(step: float) -> void:
	distance = clampf(distance * (1.0 + step), min_distance, max_distance)


func follow(world: VoxelWorld, focus: Vector3, delta: float) -> void:
	_frame_look(delta)
	if first_person:
		_follow_first_person(world, focus, delta)
		return
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


func _follow_first_person(world: VoxelWorld, focus: Vector3, delta: float) -> void:
	# Head bob: a gentle figure-eight tied to stride, fading when still or airborne.
	var walking := clampf(move_speed / 4.6, 0.0, 1.6) if grounded else 0.0
	_bob_phase += delta * (5.2 + move_speed * 0.55) * (1.0 if walking > 0.05 else 0.0)
	_bob = lerpf(_bob, walking, 1.0 - exp(-delta * 8.0))
	# Landing dip: a damped spring.
	# Semi-implicit spring in small steps: stable even on very long frames.
	var left := minf(delta, 0.25)
	while left > 0.0:
		var h := minf(left, 1.0 / 120.0)
		_dip_v += (-_dip * 90.0 - _dip_v * 14.0) * h
		_dip += _dip_v * h
		left -= h
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var bob_k := _bob * float(Settings.get_value("gameplay", "head_bob")) * (0.0 if Settings.motion_scale() < 1.0 else 1.0)
	var bob := Vector3(cos(_bob_phase) * 0.035, absf(sin(_bob_phase)) * 0.05 - 0.025, 0.0) * bob_k
	var target := focus + Vector3(0, eye_height + _dip * Settings.motion_scale(), 0) + Basis(Vector3.UP, yaw) * Vector3(0, 0, -0.06)
	# Smooth vertical steps (stairs, terrain) without lagging horizontally.
	if _eye == Vector3.ZERO or _eye.distance_to(target) > 3.0:
		_eye = target
	# Climbing never lets the eye trail more than a few centimetres below where
	# it belongs (it would look into the slope ahead); stepping down eases.
	_eye = Vector3(target.x, lerpf(_eye.y, target.y, 1.0 - exp(-delta * 22.0)), target.z)
	_eye.y = maxf(_eye.y, target.y - 0.05)
	var eye := _eye + basis * bob
	if world != null:
		eye = _clear_of_ground(world, eye, focus + Vector3(0, 1.0, 0))
	global_transform = Transform3D(basis, eye)
	rotate_object_local(Vector3.FORWARD, sin(_bob_phase) * 0.006 * bob_k)
	_trauma = maxf(0.0, _trauma - delta * 1.4)
	_shake_t += delta
	if _trauma > 0.0:
		var s := _trauma * _trauma
		rotate_object_local(Vector3.RIGHT, _noise.get_noise_2d(_shake_t * 40.0, 0.0) * 0.045 * s)
		rotate_object_local(Vector3.UP, _noise.get_noise_2d(0.0, _shake_t * 40.0) * 0.045 * s)


## Never let the eye (and the near plane around it) sit inside rock or a wall:
## slide it back towards the body's axis (then down to the chest) until a
## sphere around it is clear. The rendered Surface Nets mesh can bulge a
## little past the field's 0.5 level, so the test uses a lower threshold and
## a radius larger than the near plane's corner distance (~0.13 m at 100 deg).
const EYE_CLEAR := 0.26
const EYE_FIELD := 0.4
static var _eye_probes: Array[Vector3] = []


func _clear_of_ground(world: VoxelWorld, eye: Vector3, chest: Vector3) -> Vector3:
	if _eye_probes.is_empty():
		_eye_probes.append(Vector3.ZERO)
		for x in [-1, 0, 1]:
			for y in [-1, 0, 1]:
				for z in [-1, 0, 1]:
					if x != 0 or y != 0 or z != 0:
						_eye_probes.append(Vector3(x, y, z).normalized() * EYE_CLEAR)
	if _eye_open(world, eye):
		return eye
	# Back along a path that is known to be clear: the body axis at eye height, then the chest.
	var axis := Vector3(chest.x, eye.y, chest.z)
	var path: Array[Vector3] = [eye]
	for i in range(1, 9):
		path.append(eye.lerp(axis, i / 8.0))
	for i in range(1, 9):
		path.append(axis.lerp(chest, i / 8.0))
	for p: Vector3 in path:
		if _eye_open(world, p):
			return p
	return chest


func _eye_open(world: VoxelWorld, p: Vector3) -> bool:
	for o: Vector3 in _eye_probes:
		var q := p + o
		if world.field(q) >= EYE_FIELD or world.is_box_solid(Vector3i(q.floor())):
			return false
	return true


func aim_ray() -> Array:
	return [global_position, -global_basis.z]
