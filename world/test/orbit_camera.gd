class_name OrbitCamera
extends Camera3D
## Orbit camera for the renderer test scene: drag to orbit, wheel to zoom,
## WASD to move the focus point, optional slow cinematic auto-orbit.

@export var target := Vector3(0, 2, 0)
@export var distance := 13.0
@export var yaw := 0.6
@export var pitch := -0.28
@export var auto_orbit := true
@export var auto_speed := 0.06

var _yaw := 0.0
var _pitch := 0.0
var _distance := 0.0
var _target := Vector3.ZERO
var _dragging := false


func _ready() -> void:
	_yaw = yaw
	_pitch = pitch
	_distance = distance
	_target = target
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(3.0, distance * 0.9)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(60.0, distance * 1.1)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * 0.005
		pitch = clampf(pitch - mm.relative.y * 0.004, -1.35, 0.25)


func _process(delta: float) -> void:
	if auto_orbit and not _dragging:
		yaw += auto_speed * delta
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		move.z += 1.0
	if Input.is_key_pressed(KEY_A):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		move.x += 1.0
	if move != Vector3.ZERO:
		target += Basis(Vector3.UP, yaw) * move.normalized() * 8.0 * delta
	# Critically-damped style smoothing, frame-rate independent.
	var k := 1.0 - exp(-delta * 10.0)
	_yaw = lerp_angle(_yaw, yaw, k)
	_pitch = lerpf(_pitch, pitch, k)
	_distance = lerpf(_distance, distance, k)
	_target = _target.lerp(target, k)
	_apply()


func _apply() -> void:
	var b := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)
	global_position = _target + b * Vector3(0, 0, _distance)
	look_at(_target, Vector3.UP)
