class_name Weather
extends Node3D
## Server-driven weather: clear -> overcast -> rain -> storm, and fog, with
## convincing transitions (clouds build and the light dims first, the wind
## rises before the rain; afterwards the rain stops first, the ground stays
## wet, mist lingers, a rainbow may show). Synced to clients through
## Replicator.broadcast_clock (state name only).
##
## What the precipitation looks like depends on where the local player is:
## snow in the Frost Peaks and at altitude, wind-blown dust in the Cinder
## Wastes, rain elsewhere, nothing underground; the underworld has constant
## ash fall and embers.
##
## Drives the global shader uniforms (docs/REALISM_CONTRACTS.md):
## wind_dir, wind_strength (gusty), wetness, snow_cover, rain_amount.

const STATES := ["clear", "overcast", "rain", "storm", "fog"]
# overcast, precipitation, storm, fog, wind per state
const LEVELS := {
	"clear": [0.0, 0.0, 0.0, 0.0, 0.25],
	"overcast": [0.65, 0.0, 0.0, 0.08, 0.45],
	"rain": [0.88, 0.62, 0.0, 0.18, 0.6],
	"storm": [1.0, 1.0, 1.0, 0.22, 1.0],
	"fog": [0.45, 0.0, 0.0, 1.0, 0.08],
}
## Per channel transition speed multipliers (getting worse, getting better):
## clouds and wind lead the rain in; the rain leads the clouds out.
const RATE_UP := [1.7, 0.65, 0.6, 1.0, 2.0]
const RATE_DOWN := [0.7, 1.8, 1.8, 0.8, 0.8]
## Altitude (m) above which precipitation falls as snow anywhere.
const SNOW_LINE := 62.0

var state := "clear"
var _current := [0.0, 0.0, 0.0, 0.0, 0.25]
var _blend_speed := 1.0 / 60.0
var _next_change := 240.0
var _lightning_timer := 8.0
var _sheet_timer := 3.0
var _rain: RainCurtain
var _snow: FlakeFall
var _dust: FlakeFall
var _ash: FlakeFall
var _embers: GPUParticles3D
var _dimension := 0
var _wet := 0.0
var _snow_cover := 0.0
var _snow_mix := 0.0      # 0 rain .. 1 snow, smoothed
var _dust_mix := 0.0      # 0 .. 1 in the wastes, smoothed
var _forced_snow := false
var _time := 0.0
var _gust := FastNoiseLite.new()
var _wind_dir := Vector2(0.9, 0.44).normalized()
var _wind_strength := 0.3
var _underground := false


func _ready() -> void:
	_gust.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_gust.frequency = 0.08
	_gust.fractal_octaves = 3
	_gust.seed = 77
	_rain = RainCurtain.new()
	add_child(_rain)
	_rain.intensity = 0.0
	_snow = FlakeFall.new(FlakeFall.Kind.SNOW)
	add_child(_snow)
	_dust = FlakeFall.new(FlakeFall.Kind.DUST)
	add_child(_dust)
	_ash = FlakeFall.new(FlakeFall.Kind.ASH)
	add_child(_ash)
	_embers = _make_embers()
	add_child(_embers)
	for p: GPUParticles3D in [_rain, _snow, _dust, _ash, _embers]:
		p.emitting = false
		p.visible = false


func set_dimension(dim: int) -> void:
	_dimension = dim


func state_name() -> String:
	return state


func sync_state(s: String) -> void:
	if s != state and LEVELS.has(s):
		state = s
		_blend_speed = 1.0 / 40.0
		Events.weather_changed.emit(state)


## Development aid (captures): jump straight to a state. "snow" = rain that
## falls as snow wherever the player is.
func force(s: String) -> void:
	_forced_snow = s == "snow"
	if _forced_snow:
		s = "rain"
	if not LEVELS.has(s):
		return
	state = s
	var target: Array = LEVELS[s]
	for i in 5:
		_current[i] = target[i]
	_next_change = 1e9
	_snow_mix = 1.0 if _forced_snow else 0.0
	if s == "rain" or s == "storm":
		_wet = 0.8
		_snow_cover = 0.7 if _forced_snow else 0.0
	else:
		_wet = 0.0
		_snow_cover = 0.0
	Events.weather_changed.emit(state)


func overcast() -> float:
	return _current[0] if _dimension == 0 else 0.0


## Audible rain (0 when the precipitation is snow or dust, or underground).
func rain_amount() -> float:
	if _dimension != 0 or _underground:
		return 0.0
	return _current[1] * (1.0 - _snow_mix) * (1.0 - _dust_mix)


## Precipitation as the sky sees it (darkens clouds whatever falls from them).
func rain_amount_visual() -> float:
	return _current[1] if _dimension == 0 else 0.0


func snow_amount() -> float:
	if _dimension != 0 or _underground:
		return 0.0
	return _current[1] * _snow_mix * (1.0 - _dust_mix)


## Dust storm strength in the Cinder Wastes.
func dust_amount() -> float:
	if _dimension != 0:
		return 0.0
	return _dust_mix * clampf(_current[1] + (_current[4] - 0.4) * 0.8, 0.0, 1.0)


func storm_amount() -> float:
	return _current[2] if _dimension == 0 else 0.0


func fog_amount() -> float:
	if _dimension != 0:
		return 0.0
	# Mist lingers after rain.
	return clampf(_current[3] + _wet * (1.0 - _current[1]) * 0.25, 0.0, 1.0)


## Wind for the ambience: 0 calm .. 1 gale, gusty.
func wind_amount() -> float:
	return clampf(_wind_strength, 0.0, 1.0)


## Horizontal wind direction * strength (x, z).
func wind_vector() -> Vector2:
	return _wind_dir * _wind_strength


func wetness() -> float:
	return _wet


func snow_cover() -> float:
	return _snow_cover


func _world() -> GameWorld:
	return get_parent() as GameWorld


func _process(delta: float) -> void:
	_time += delta
	var w := _world()
	if Net.is_server():
		_next_change -= delta
		if _next_change <= 0.0:
			_pick_next()
	var target: Array = LEVELS[state]
	for i in 5:
		var rate: float = RATE_UP[i] if target[i] > _current[i] else RATE_DOWN[i]
		_current[i] = move_toward(_current[i], target[i], delta * _blend_speed * rate)

	# Where is the local player? (snow / dust / underground)
	_underground = w != null and w.tracker != null and w.tracker.underground
	var snow_target := 1.0 if _forced_snow else 0.0
	var dust_target := 0.0
	var player_pos := Vector3.ZERO
	var camera := get_viewport().get_camera_3d()
	if w != null and w.local_player != null:
		player_pos = w.local_player.global_position
	elif camera != null:
		player_pos = camera.global_position
	if w != null and _dimension == 0:
		var g := w.gen_for(0)
		if g != null:
			var b := g.biome_at(int(player_pos.x), int(player_pos.z))
			if b == WorldGen.Biome.PEAKS or player_pos.y > SNOW_LINE:
				snow_target = 1.0
			elif b == WorldGen.Biome.WASTES:
				dust_target = 1.0
	_snow_mix = move_toward(_snow_mix, snow_target, delta * 0.3)
	_dust_mix = move_toward(_dust_mix, dust_target, delta * 0.3)

	_update_wind(delta)

	var outside := _dimension == 0 and not _underground
	var precip: float = _current[1]
	var rain := precip * (1.0 - _snow_mix) * (1.0 - _dust_mix) if outside else 0.0
	var snow := precip * _snow_mix * (1.0 - _dust_mix) if outside else 0.0
	var dust := dust_amount() if outside else 0.0
	var wind3 := Vector3(_wind_dir.x, 0.0, _wind_dir.y) * _wind_strength
	var light := _light_level()

	_rain.intensity = rain
	_set_active(_rain, rain > 0.01)
	_rain.wind = wind3 * 6.0 + Vector3(0.8, 0, 0.3)
	_rain.brightness = light
	_snow.intensity = snow
	_set_active(_snow, snow > 0.01)
	_snow.wind = wind3 * 3.0
	_snow.brightness = light
	_dust.intensity = dust
	_set_active(_dust, dust > 0.02)
	_dust.wind = wind3 * 12.0 + Vector3(_wind_dir.x, 0, _wind_dir.y) * 2.0
	_dust.brightness = light
	_rain.keep_collider = _snow.visible or _dust.visible
	var hell := _dimension == 1
	_ash.intensity = 0.8 if hell else 0.0
	_set_active(_ash, hell)
	_ash.wind = wind3 * 2.0 + Vector3(0.4, 0, 0.2)
	_ash.brightness = 0.6
	_set_active(_embers, hell)
	if camera != null:
		_embers.global_position = camera.global_position + Vector3(0, 6, 0)
		if _rain.visible and Ascii.effect != null:
			Ascii.effect.wind_slant = _rain.screen_slant(camera)

	# Rain soaks the ground and it dries slowly (faster in sunshine); snow
	# settles in the cold and melts away elsewhere.
	if _dimension == 0:
		var sky: SkyController = w.sky if w != null else null
		var sun_up := sky != null and sky.darkness() < 0.3
		var wet_target := clampf(rain * 1.4, 0.0, 1.0)
		if wet_target > _wet:
			_wet = move_toward(_wet, wet_target, delta / 45.0)
		else:
			_wet = move_toward(_wet, wet_target, delta / (260.0 if sun_up and _current[0] < 0.5 else 600.0))
		if snow > 0.05:
			_snow_cover = move_toward(_snow_cover, clampf(snow * 1.2, 0.0, 1.0), delta / 90.0)
		else:
			_snow_cover = move_toward(_snow_cover, 0.0, delta / (500.0 if _snow_mix > 0.5 else 40.0))
	else:
		_wet = move_toward(_wet, 0.0, delta / 20.0)
		_snow_cover = move_toward(_snow_cover, 0.0, delta / 20.0)

	RenderingServer.global_shader_parameter_set(&"wind_dir", _wind_dir)
	RenderingServer.global_shader_parameter_set(&"wind_strength", _wind_strength)
	RenderingServer.global_shader_parameter_set(&"wetness", _wet if _dimension == 0 else 0.0)
	RenderingServer.global_shader_parameter_set(&"snow_cover", _snow_cover)
	RenderingServer.global_shader_parameter_set(&"rain_amount", rain)
	_legacy_materials(w)

	if Net.is_server() and _current[2] > 0.5 and w != null and w.replicator != null:
		_lightning_timer -= delta
		if _lightning_timer <= 0.0:
			_lightning_timer = randf_range(4.0, 14.0) / _current[2]
			var players := w.players_in(0)
			if not players.is_empty():
				var p: Player = players[randi() % players.size()]
				var a := randf() * TAU
				w.replicator.broadcast_lightning(p.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(35.0, 160.0), 0)
	# Sheet lightning: flickers inside distant clouds (local, unsynced).
	if outside and _current[2] > 0.3:
		_sheet_timer -= delta
		if _sheet_timer <= 0.0:
			_sheet_timer = randf_range(2.0, 7.0) / _current[2]
			var a := randf() * TAU
			_sky_flash(Vector3(cos(a), randf_range(0.15, 0.5), sin(a)), randf_range(0.25, 0.6))


func _update_wind(_delta: float) -> void:
	# Direction drifts slowly over minutes; strength gusts over seconds.
	var ang := 0.46 + sin(_time * 0.004) * 0.7 + sin(_time * 0.0137 + 1.3) * 0.25 + _gust.get_noise_1d(_time * 0.05 + 500.0) * 0.35
	_wind_dir = Vector2(cos(ang), sin(ang))
	var base: float = _current[4]
	var g := _gust.get_noise_1d(_time) * 0.5 + 0.5           # 0..1
	var burst := pow(maxf(_gust.get_noise_1d(_time * 0.6 + 100.0), 0.0), 2.0) * 1.4
	_wind_strength = clampf(base * (0.7 + 0.45 * g) + burst * base * 0.6, 0.0, 1.0)
	if _dimension == 1:
		_wind_strength = 0.2 + 0.1 * g


## 0..1 brightness of the ambient light (self-lighting for drops and flakes).
func _light_level() -> float:
	var w := _world()
	if w == null or w.sky == null:
		return 1.0
	return clampf(1.0 - w.sky.darkness(), 0.08, 1.0) * (1.0 - _current[2] * 0.4)


func _set_active(p: GPUParticles3D, on: bool) -> void:
	if p.visible != on:
		p.visible = on
		p.emitting = on


## The cube terrain's own material uniforms (pre-smooth-terrain); harmless when gone.
func _legacy_materials(w: GameWorld) -> void:
	if w == null:
		return
	for d: int in w.worlds:
		var vw: Object = w.worlds[d]
		if vw == null:
			continue
		var mat := vw.get("opaque_material") as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter(&"wetness", _wet if d == 0 else 0.0)
			mat.set_shader_parameter(&"wind_strength", 0.4 + _wind_strength * 1.2)


func _pick_next() -> void:
	var order := {"clear": ["overcast", "overcast", "fog", "clear"], "overcast": ["rain", "clear", "fog", "rain"],
		"rain": ["storm", "overcast", "rain"], "storm": ["rain", "overcast"], "fog": ["clear", "overcast"]}
	var options: Array = order[state]
	state = options[randi() % options.size()]
	_blend_speed = 1.0 / randf_range(40.0, 120.0)
	_next_change = randf_range(180.0, 420.0)
	Events.weather_changed.emit(state)
	var w := _world()
	if w != null and w.replicator != null:
		w.replicator.broadcast_clock(w.sky.time_of_day, w.sky.day, state)


## A lightning strike at `pos` (broadcast by the server to everyone).
func strike_fx(pos: Vector3) -> void:
	var w := _world()
	if w == null or w.local_player == null or (w.tracker != null and w.tracker.underground):
		return
	var ground := pos
	var h := w.surface_height_at(pos.x, pos.z)
	if h > 0.0:
		ground.y = h + 1.0
	var cam := w.local_player.global_position
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		cam = camera.global_position
	var dist := cam.distance_to(ground)
	LightningBolt.strike(w, ground, randf_range(110.0, 160.0), cam, randi())
	if w.view != null:
		w.view.flash = maxf(w.view.flash, clampf(1.2 - dist / 160.0, 0.25, 0.8))
	_sky_flash((ground + Vector3(0, 120, 0) - cam).normalized(), 1.0)
	Events.lightning.emit(pos)
	get_tree().create_timer(dist / 340.0).timeout.connect(func() -> void:
		Audio.play("thunder", Vector3.INF, clampf(-dist / 12.0, -14.0, 0.0)))


func _sky_flash(dir: Vector3, strength: float) -> void:
	var w := _world()
	if w != null and w.sky != null:
		w.sky.flash_sky(dir, strength)


func _make_embers() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 500
	p.lifetime = 6.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30, 8, 30)
	pm.direction = Vector3(0.2, 1, 0.1)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.0
	pm.gravity = Vector3(0, 0.15, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.color_ramp = Torch._fade_gradient()
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	q.material = MaterialLibrary.fx(Color(1.0, 0.6, 0.3), Color(0.9, 0.25, 0.05), 3.0)
	p.draw_pass_1 = q
	p.emitting = false
	return p
