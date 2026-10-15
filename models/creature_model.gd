class_name CreatureModel
extends Node3D
## Base for every animated model. Subclasses build their parts in `_build()`
## and pose them every frame in `_animate(delta)` from continuous phases, so
## motion never pops. One-shot actions are started with `play()`.
##
## Shared state: move_speed (m/s), grounded, current action and its
## progress, hit flash, burning, death dissolve. Models face -Z.

signal action_finished(action: String)

var move_speed := 0.0
var grounded := true
## Turn rate visual helper: models may lean into turns.
var turn_rate := 0.0

var _action := ""
var _action_t := 0.0
var _action_dur := 1.0
var _flash := 0.0
var _flash_color := Color.WHITE
var _burn := 0.0
var _burn_target := 0.0
var _dead := false
var _dead_t := 0.0
var _dissolve := 0.0
var _time := 0.0
var _geoms: Array[GeometryInstance3D] = []
var _glows: Array[GeometryInstance3D] = []
var _embers: GPUParticles3D
var _glow_intensity := 1.0
var _built := false
## Animation level of detail: far-away models pose themselves less often.
var lod_enabled := true
var _lod_step := 0.0
var _lod_acc := 0.0
var _lod_check := 0.0

## Seconds after death before the body crumbles into embers.
var dissolve_delay := 1.4
var dissolve_time := 1.6
## Default length of one-shot actions, per action name.
var durations := {
	"attack": 0.55, "attack2": 0.6, "mine": 0.5, "cast": 0.6, "dodge": 0.55, "hit": 0.35,
	"die": 1.2, "interact": 0.6, "drink": 0.9, "jump": 0.45, "slam": 1.1, "roar": 1.4,
	"bite": 0.7, "claw": 0.7, "tail": 1.0, "breath": 2.4, "gust": 1.2, "takeoff": 1.5,
	"land": 1.0, "dive": 1.2, "pounce": 1.0, "howl": 1.5, "summon": 1.3, "throw": 1.0,
	"sweep": 1.0, "teleport": 0.8, "shoot": 0.9, "lunge": 0.6, "spikes": 1.2, "drain": 1.0,
}
## Actions that loop until another action replaces them.
var looping := {"mine": true, "breath": false, "fly": true}


func _ready() -> void:
	if not _built:
		_built = true
		_build()
		_collect(self)
		_embers = ModelKit.embers(self, 24, _ember_extents(), 1.2, 0.09)


## Override: create the model's parts.
func _build() -> void:
	pass


## Override: pose the model.
func _animate(_delta: float) -> void:
	pass


## Size of the box embers rise from while burning / dissolving.
func _ember_extents() -> Vector3:
	return Vector3(0.3, 0.8, 0.3)


func play(action: String, duration := -1.0) -> void:
	if _dead and action != "die":
		return
	_action = action
	_action_t = 0.0
	_action_dur = duration if duration > 0.0 else float(durations.get(action, 0.6))
	_on_action(action)


func _on_action(_action_name: String) -> void:
	pass


func current_action() -> String:
	return _action


## 0..1 progress of the current action, or -1 when idle.
func action_progress() -> float:
	if _action == "":
		return -1.0
	return clampf(_action_t / _action_dur, 0.0, 1.0)


## Envelope that eases an action in and out (0 at the ends, 1 in the middle).
func action_weight(fade_in := 0.12, fade_out := 0.2) -> float:
	var t := action_progress()
	if t < 0.0:
		return 0.0
	return smoothstep(0.0, fade_in, t) * (1.0 - smoothstep(1.0 - fade_out, 1.0, t))


func flash(color := Color(1, 1, 1)) -> void:
	_flash = 1.0
	_flash_color = color


func set_burning(on: bool) -> void:
	_burn_target = 1.0 if on else 0.0


func set_dead(dead: bool) -> void:
	if dead == _dead:
		return
	_dead = dead
	_dead_t = 0.0
	if dead:
		_action = ""
		play("die")
	else:
		_dissolve = 0.0
		_set_param(&"dissolve", 0.0)
		visible = true


func is_dissolved() -> bool:
	return _dead and _dissolve >= 1.0


func set_glow_intensity(v: float) -> void:
	_glow_intensity = v
	for g in _glows:
		g.set_instance_shader_parameter(&"intensity", v)


func _process(frame_delta: float) -> void:
	if not _built:
		return
	var delta := frame_delta
	if lod_enabled:
		_lod_check -= frame_delta
		if _lod_check <= 0.0:
			_lod_check = 0.35 + randf() * 0.2
			_lod_step = _lod_interval()
		if _lod_step > 0.0 and _flash <= 0.0 and not _dead:
			_lod_acc += frame_delta
			if _lod_acc < _lod_step:
				return
			delta = _lod_acc
			_lod_acc = 0.0
	_time += delta
	if _action != "":
		_action_t += delta
		if _action_t >= _action_dur:
			var finished := _action
			if looping.get(_action, false):
				_action_t = fmod(_action_t, _action_dur)
			elif _action == "die":
				_action_t = _action_dur
			else:
				_action = ""
			action_finished.emit(finished)
	_animate(delta)

	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
		_set_param(&"hit_flash", _flash * 0.85)
		_set_param(&"flash_color", Vector3(_flash_color.r, _flash_color.g, _flash_color.b))
	var b := move_toward(_burn, _burn_target, delta * 2.0)
	if b != _burn:
		_burn = b
		_set_param(&"burn", _burn)
	if _dead:
		_dead_t += delta
		if _dead_t > dissolve_delay:
			_dissolve = clampf((_dead_t - dissolve_delay) / dissolve_time, 0.0, 1.0)
			_set_param(&"dissolve", _dissolve * 0.95 + 0.02)
			set_glow_intensity(1.0 - _dissolve)
			if _dissolve >= 1.0:
				for g in _geoms:
					g.visible = false
	if _embers != null:
		_embers.emitting = _burn > 0.05 or (_dead and _dead_t > dissolve_delay and _dissolve < 0.9)


## Seconds between animation updates for this model right now (0 = every frame).
func _lod_interval() -> float:
	if not is_visible_in_tree():
		return 0.5
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null:
		return 0.0
	var d := cam.global_position.distance_to(global_position) / maxf(0.5, _lod_size())
	if d > 70.0:
		return 0.25
	if d > 32.0:
		return 1.0 / 15.0
	if d > 16.0:
		return 1.0 / 30.0
	return 0.0


## Rough size of the model in metres (big creatures keep full-rate animation further away).
func _lod_size() -> float:
	return 1.8


func _set_param(param: StringName, value: Variant) -> void:
	for g in _geoms:
		g.set_instance_shader_parameter(param, value)


func _collect(node: Node) -> void:
	for c in node.get_children():
		if c is GeometryInstance3D and not c is GPUParticles3D:
			var gi := c as GeometryInstance3D
			var m := gi.material_override as ShaderMaterial
			if m != null and (m.shader == ModelKit.CREATURE or m.shader == CreatureSkin.SHADER):
				_geoms.append(gi)
			elif m != null and m.shader == ModelKit.GLOW:
				_glows.append(gi)
				gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_collect(c)


## Re-scan after adding parts at runtime (held items).
func refresh_parts() -> void:
	_geoms.clear()
	_glows.clear()
	_collect(self)


# --- Small maths helpers for subclasses ----------------------------------------------

static func damp(current: float, target: float, rate: float, delta: float) -> float:
	return lerpf(current, target, 1.0 - exp(-rate * delta))


static func damp_v(current: Vector3, target: Vector3, rate: float, delta: float) -> Vector3:
	return current.lerp(target, 1.0 - exp(-rate * delta))


## Smoothly drive a joint's rotation (radians) towards a target.
static func pose(node: Node3D, target: Vector3, rate: float, delta: float) -> void:
	node.rotation = node.rotation.lerp(target, 1.0 - exp(-rate * delta))


## Piecewise curve helper: value at t from [[t0, v0], [t1, v1], ...] with smooth easing.
static func keys(t: float, points: Array) -> float:
	if t <= points[0][0]:
		return points[0][1]
	for i in range(points.size() - 1):
		var a: Array = points[i]
		var b: Array = points[i + 1]
		if t <= b[0]:
			var f: float = (t - float(a[0])) / maxf(0.0001, float(b[0]) - float(a[0]))
			f = f * f * (3.0 - 2.0 * f)
			return lerpf(a[1], b[1], f)
	return points[points.size() - 1][1]
