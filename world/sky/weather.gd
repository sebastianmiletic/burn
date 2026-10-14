class_name Weather
extends Node3D
## Server-driven weather: Clear -> Overcast -> Rain -> Storm -> Fog, with
## smooth 30-120 s transitions, synced to clients. Drives rain streaks, wet
## ground, fog, wind and lightning (screen flash + delayed thunder).
## The underworld has its own constant ash fall.

const STATES := ["clear", "overcast", "rain", "storm", "fog"]
# overcast, rain, storm, fog, wind per state
const LEVELS := {
	"clear": [0.0, 0.0, 0.0, 0.0, 0.2],
	"overcast": [0.6, 0.0, 0.0, 0.1, 0.4],
	"rain": [0.85, 0.6, 0.0, 0.2, 0.6],
	"storm": [1.0, 1.0, 1.0, 0.25, 1.0],
	"fog": [0.5, 0.0, 0.0, 1.0, 0.1],
}

var state := "clear"
var _current := [0.0, 0.0, 0.0, 0.0, 0.2]
var _blend_speed := 1.0 / 60.0
var _next_change := 240.0
var _lightning_timer := 8.0
var _rain: RainCurtain
var _ash: GPUParticles3D
var _dimension := 0
var _wet := 0.0


func _ready() -> void:
	_rain = RainCurtain.new()
	add_child(_rain)
	_rain.intensity = 0.0
	_ash = _make_ash()
	add_child(_ash)


func set_dimension(dim: int) -> void:
	_dimension = dim


func state_name() -> String:
	return state


func sync_state(s: String) -> void:
	if s != state and LEVELS.has(s):
		state = s
		_blend_speed = 1.0 / 40.0
		Events.weather_changed.emit(state)


func overcast() -> float:
	return _current[0] if _dimension == 0 else 0.0


func rain_amount() -> float:
	return _current[1] if _dimension == 0 else 0.0


func storm_amount() -> float:
	return _current[2] if _dimension == 0 else 0.0


func fog_amount() -> float:
	return _current[3] if _dimension == 0 else 0.0


func wind_amount() -> float:
	return _current[4]


func _process(delta: float) -> void:
	if Net.is_server():
		_next_change -= delta
		if _next_change <= 0.0:
			_pick_next()
	var target: Array = LEVELS[state]
	for i in 5:
		_current[i] = move_toward(_current[i], target[i], delta * _blend_speed)
	var w := get_parent() as GameWorld
	var underground := w != null and w.tracker != null and w.tracker.underground
	var raining := _dimension == 0 and not underground
	_rain.intensity = _current[1] if raining else 0.0
	_rain.visible = _rain.intensity > 0.01
	_rain.emitting = _rain.visible
	_rain.wind = Vector3(2.0 + _current[4] * 5.0, 0, 0.8 + _current[4] * 2.0)
	_ash.emitting = _dimension == 1
	_ash.visible = _dimension == 1
	if w != null and w.local_player != null:
		_ash.global_position = w.local_player.global_position + Vector3(0, 8, 0)
		if _rain.visible and w.local_player.camera != null:
			Ascii.effect.wind_slant = _rain.screen_slant(w.local_player.camera)
	# Ground gets wet in rain and dries slowly.
	_wet = move_toward(_wet, _current[1], delta * (0.02 if _current[1] > _wet else 0.006))
	if w != null:
		for d: int in w.worlds:
			var mat: ShaderMaterial = (w.worlds[d] as VoxelWorld).opaque_material
			mat.set_shader_parameter(&"wetness", _wet if d == 0 else 0.0)
			mat.set_shader_parameter(&"wind_strength", 0.4 + _current[4] * 1.2)
	if Net.is_server() and _current[2] > 0.5 and w != null:
		_lightning_timer -= delta
		if _lightning_timer <= 0.0:
			_lightning_timer = randf_range(5.0, 16.0)
			var players := w.players_in(0)
			if not players.is_empty():
				var p: Player = players[randi() % players.size()]
				var a := randf() * TAU
				w.replicator.broadcast_lightning(p.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(30.0, 120.0), 0)


func _pick_next() -> void:
	var order := {"clear": ["overcast", "overcast", "fog"], "overcast": ["rain", "clear", "fog"],
		"rain": ["storm", "overcast", "rain"], "storm": ["rain", "overcast"], "fog": ["clear", "overcast"]}
	var options: Array = order[state]
	state = options[randi() % options.size()]
	_blend_speed = 1.0 / randf_range(30.0, 120.0)
	_next_change = randf_range(180.0, 420.0)
	Events.weather_changed.emit(state)
	var w := get_parent() as GameWorld
	if w != null and w.replicator != null:
		w.replicator.broadcast_clock(w.sky.time_of_day, w.sky.day, state)


func strike_fx(pos: Vector3) -> void:
	var w := get_parent() as GameWorld
	if w == null or w.tracker.underground:
		return
	w.view.flash = 1.0
	Events.lightning.emit(pos)
	var dist := w.local_player.global_position.distance_to(pos)
	get_tree().create_timer(dist / 340.0).timeout.connect(func() -> void:
		Audio.play("thunder", Vector3.INF, clampf(-dist / 12.0, -14.0, 0.0)))
	# A brief bright light at the strike.
	var l := OmniLight3D.new()
	l.light_color = Color(0.8, 0.85, 1.0)
	l.light_energy = 12.0
	l.omni_range = 80.0
	w.add_child(l)
	l.global_position = pos + Vector3(0, 30, 0)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.35)
	tw.tween_callback(l.queue_free)


func _make_ash() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 900
	p.lifetime = 6.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30, 6, 30)
	pm.direction = Vector3(0.3, -1, 0.1)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0, -0.3, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.0
	pm.color_ramp = Torch._fade_gradient()
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	q.material = MaterialLibrary.fx(Color(1.0, 0.6, 0.3), Color(0.9, 0.25, 0.05), 3.0)
	p.draw_pass_1 = q
	p.emitting = false
	return p
