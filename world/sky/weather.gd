class_name Weather
extends Node3D
## Server-driven weather that genuinely changes over time, in solo and online
## play alike: the host walks a weighted chain of weather states and events
## (fair weather, cloud, rain, thunderstorms with real lightning strikes, fog
## banks, blizzards, heatwaves, dust storms, ember storms off the Cinder
## Crater, and on clear nights the aurora or a meteor shower). Transitions are
## gradual and physically ordered: clouds build and the wind rises before the
## rain; afterwards the rain stops first, the ground stays wet, mist lingers,
## and a rainbow may show in the afternoon sun.
##
## Sync: the state name travels with Replicator.broadcast_clock (sent on every
## change and every few seconds), so joiners and clients follow the host.
## Gameplay can summon weather with `request(state, seconds)` (server
## authoritative; clients forward the request to the host).
##
## What falls from the sky depends on where the local player is: snow in the
## Frost Peaks, at altitude and in a blizzard; wind-blown dust in the Cinder
## Wastes and in a dust storm; rain elsewhere; nothing underground. The
## underworld has constant ash fall and embers.
##
## Drives the global shader uniforms (docs/REALISM_CONTRACTS.md):
## wind_dir, wind_strength (gusty), wetness, snow_cover, rain_amount.

## Every state. The first five are the everyday ones.
const STATES := ["clear", "overcast", "rain", "storm", "fog", "snow", "blizzard", "heatwave", "dust_storm",
		"ember_storm", "aurora", "meteor_shower"]
## Channels: overcast, precipitation, storm, fog, wind, snow (forces snow),
## dust (forces dust), heat, aurora, embers, meteors.
const CHANNELS := 11
const LEVELS := {
	"clear":         [0.0,  0.0,  0.0, 0.0,  0.25, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
	"overcast":      [0.65, 0.0,  0.0, 0.08, 0.45, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
	"rain":          [0.88, 0.62, 0.0, 0.18, 0.6,  0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
	"storm":         [1.0,  1.0,  1.0, 0.22, 1.0,  0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
	"fog":           [0.45, 0.0,  0.0, 1.0,  0.08, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
	"snow":          [0.85, 0.6,  0.0, 0.25, 0.45, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0],
	"blizzard":      [0.95, 0.95, 0.0, 0.7,  1.0,  1.0, 0.0, 0.0, 0.0, 0.0, 0.0],
	"heatwave":      [0.0,  0.0,  0.0, 0.0,  0.12, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0],
	"dust_storm":    [0.35, 0.35, 0.0, 0.45, 1.0,  0.0, 1.0, 0.5, 0.0, 0.0, 0.0],
	"ember_storm":   [0.75, 0.0,  0.0, 0.3,  0.6,  0.0, 0.0, 0.4, 0.0, 1.0, 0.0],
	"aurora":        [0.0,  0.0,  0.0, 0.0,  0.2,  0.0, 0.0, 0.0, 1.0, 0.0, 0.0],
	"meteor_shower": [0.0,  0.0,  0.0, 0.0,  0.2,  0.0, 0.0, 0.0, 0.0, 0.0, 1.0],
}
## Per channel transition speed multipliers (getting worse, getting better):
## clouds and wind lead the rain in; the rain leads the clouds out.
const RATE_UP := [1.7, 0.65, 0.6, 1.0, 2.0, 1.0, 1.0, 0.6, 0.5, 0.8, 0.8]
const RATE_DOWN := [0.7, 1.8, 1.8, 0.8, 0.8, 1.0, 1.0, 0.8, 0.8, 1.0, 1.2]
## Altitude (m) above which precipitation falls as snow anywhere.
const SNOW_LINE := 62.0
## Weighted successors [state, weight]; night-only and day-only states are
## filtered by the clock when picked.
const CHAIN := {
	"clear": [["overcast", 4], ["fog", 1], ["heatwave", 1.2], ["dust_storm", 0.6], ["aurora", 1.4], ["meteor_shower", 1.0], ["clear", 1]],
	"overcast": [["rain", 4], ["clear", 2], ["fog", 1], ["snow", 0.8], ["blizzard", 0.4], ["ember_storm", 0.7]],
	"snow": [["overcast", 2], ["blizzard", 0.6], ["clear", 1]],
	"rain": [["storm", 2.5], ["overcast", 2], ["clear", 1.5], ["rain", 1]],
	"storm": [["rain", 3], ["overcast", 1]],
	"fog": [["clear", 2], ["overcast", 1.5]],
	"blizzard": [["overcast", 2], ["fog", 1]],
	"heatwave": [["clear", 2], ["dust_storm", 1], ["overcast", 1]],
	"dust_storm": [["clear", 1.5], ["overcast", 1]],
	"ember_storm": [["overcast", 2], ["rain", 1]],
	"aurora": [["clear", 2], ["meteor_shower", 0.5], ["fog", 0.5]],
	"meteor_shower": [["clear", 2], ["aurora", 0.6]],
}
const NIGHT_ONLY := ["aurora", "meteor_shower"]
const DAY_ONLY := ["heatwave"]
## Seconds a state lasts (min, max) before the host picks the next one.
const DURATION := {
	"clear": [150.0, 330.0], "overcast": [120.0, 260.0], "rain": [120.0, 280.0], "storm": [90.0, 200.0],
	"fog": [90.0, 200.0], "snow": [120.0, 260.0], "blizzard": [90.0, 200.0], "heatwave": [150.0, 300.0], "dust_storm": [80.0, 160.0],
	"ember_storm": [90.0, 180.0], "aurora": [120.0, 260.0], "meteor_shower": [90.0, 180.0],
}
const ANNOUNCE := {
	"storm": "Thunder rolls in: a storm is breaking. Lightning seeks the high ground.",
	"snow": "Snow begins to fall.",
	"blizzard": "A blizzard sweeps down from the peaks.",
	"heatwave": "A heatwave settles over the island.",
	"dust_storm": "A dust storm rises out of the wastes.",
	"ember_storm": "The Cinder Crater stirs: embers rain from a burning sky.",
	"aurora": "The aurora is dancing tonight.",
	"meteor_shower": "Falling stars streak across the night.",
	"fog": "A fog bank rolls in.",
}
## Lightning that lands this close to a player hurts them (m).
const STRIKE_RADIUS := 3.5

var state := "clear"
var _current: Array = LEVELS["clear"].duplicate()
var _blend_speed := 1.0 / 60.0
var _next_change := 90.0
var _hold := 0.0           ## requested weather: no random change until it runs out
var _lightning_timer := 8.0
var _sheet_timer := 3.0
var _meteor_timer := 2.0
var _rain: RainCurtain
var _snow: FlakeFall
var _dust: FlakeFall
var _ash: FlakeFall
var _embers: GPUParticles3D
var _breath: GPUParticles3D
var _dimension := 0
var _wet := 0.0
var _snow_cover := 0.0
var _snow_mix := 0.0      # 0 rain .. 1 snow, smoothed
## 0 at the foothills .. 1 near the summits of the big mountains (smoothed).
var altitude := 0.0
var _dust_mix := 0.0      # 0 .. 1 in the wastes or a dust storm, smoothed
var _ember_near := 0.0    # 0 .. 1 how close to the Cinder Crater (smoothed)
var _forced_snow := false
var _time := 0.0
var _gust := FastNoiseLite.new()
var _wind_dir := Vector2(0.9, 0.44).normalized()
var _wind_strength := 0.3
var _underground := false


func _init() -> void:
	# A stable node path, so requests from clients reach the host's weather.
	name = "Weather"


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
	_breath = _make_breath()
	add_child(_breath)
	for p: GPUParticles3D in [_rain, _snow, _dust, _ash, _embers]:
		p.emitting = false
		p.visible = false
	_next_change = randf_range(60.0, 150.0)


func set_dimension(dim: int) -> void:
	_dimension = dim


func state_name() -> String:
	return state


## Client side of the sync: follow the host's state.
func sync_state(s: String) -> void:
	if s != state and LEVELS.has(s):
		_set_state(s, 1.0 / 40.0)


## Summon weather (items, abilities, quests). Server-authoritative: on a
## client the request is forwarded to the host, which applies it for everyone.
## `state` is one of STATES; the weather holds for `seconds` (10..900) before
## the natural cycle resumes. Returns false for an unknown state.
func request(new_state: String, seconds: float, source_peer := 0) -> bool:
	if not LEVELS.has(new_state):
		return false
	if not Net.is_server():
		_request_on_host.rpc_id(1, new_state, seconds)
		return true
	_hold = clampf(seconds, 10.0, 900.0)
	_next_change = _hold
	_set_state(new_state, 1.0 / 25.0)
	_broadcast()
	if source_peer != 0:
		print_verbose("[weather] %s summoned by peer %d for %.0f s" % [new_state, source_peer, _hold])
	return true


@rpc("any_peer", "reliable")
func _request_on_host(new_state: String, seconds: float) -> void:
	if Net.is_server():
		request(new_state, seconds, multiplayer.get_remote_sender_id())


## Seconds left on a summoned weather (0 when the natural cycle runs).
func hold_left() -> float:
	return _hold


## Development aid (captures): jump straight to a state. "snow" = rain that
## falls as snow wherever the player is.
func force(s: String) -> void:
	_forced_snow = false
	if not LEVELS.has(s):
		return
	state = s
	var target: Array = LEVELS[s]
	for i in CHANNELS:
		_current[i] = target[i]
	_next_change = 1e9
	_snow_mix = 1.0 if s == "snow" or s == "blizzard" else 0.0
	_dust_mix = 1.0 if s == "dust_storm" else 0.0
	if s in ["rain", "storm", "snow", "blizzard"]:
		_wet = 0.8
		_snow_cover = 0.7 if s == "snow" or s == "blizzard" else 0.0
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
	return _current[1] * (1.0 - _dust_mix * 0.7) if _dimension == 0 else 0.0


func snow_amount() -> float:
	if _dimension != 0 or _underground:
		return 0.0
	return _current[1] * _snow_mix * (1.0 - _dust_mix)


## Dust storm strength (the Cinder Wastes in any wind, everywhere in a dust storm).
func dust_amount() -> float:
	if _dimension != 0:
		return 0.0
	return _dust_mix * clampf(_current[1] + (_current[4] - 0.4) * 0.8 + _current[6] * 0.6, 0.0, 1.0)


func storm_amount() -> float:
	return _current[2] if _dimension == 0 else 0.0


func fog_amount() -> float:
	if _dimension != 0:
		return 0.0
	# Mist lingers after rain.
	return clampf(_current[3] + _wet * (1.0 - _current[1]) * 0.25, 0.0, 1.0)


## Heat haze 0..1 (heatwave, dust storm, ember storm).
func heat_amount() -> float:
	return _current[7] if _dimension == 0 else 0.0


## Aurora curtains 0..1 (only shows at night; SkyController fades it by darkness).
func aurora_amount() -> float:
	return _current[8] if _dimension == 0 else 0.0


## Ember storm 0..1, strongest near the Cinder Crater.
func ember_amount() -> float:
	if _dimension != 0:
		return 0.0
	return _current[9] * lerpf(0.45, 1.0, _ember_near)


## Meteor shower 0..1.
func meteor_amount() -> float:
	return _current[10] if _dimension == 0 else 0.0


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


## How far one can see outdoors, 0 (white-out) .. 1 (clear) — for AI and gameplay.
func visibility() -> float:
	if _dimension != 0 or _underground:
		return 1.0
	return clampf(1.0 - fog_amount() * 0.7 - snow_amount() * 0.35 - dust_amount() * 0.5 - rain_amount() * 0.15, 0.1, 1.0)


func _world() -> GameWorld:
	return get_parent() as GameWorld


func _process(delta: float) -> void:
	_time += delta
	var w := _world()
	if Net.is_server():
		_hold = maxf(0.0, _hold - delta)
		_next_change -= delta
		if _next_change <= 0.0:
			_pick_next()
	var target: Array = LEVELS[state]
	for i in CHANNELS:
		var rate: float = RATE_UP[i] if target[i] > _current[i] else RATE_DOWN[i]
		_current[i] = move_toward(_current[i], target[i], delta * _blend_speed * rate)

	# Where is the local player? (snow / dust / underground / crater)
	_underground = w != null and w.tracker != null and w.tracker.underground
	var snow_target := 1.0 if _forced_snow else 0.0
	var dust_target := 0.0
	var player_pos := Vector3.ZERO
	var camera := get_viewport().get_camera_3d()
	if w != null and w.local_player != null:
		player_pos = w.local_player.global_position
	elif camera != null:
		player_pos = camera.global_position
	var ember_target := 0.0
	if w != null and _dimension == 0:
		var g := w.gen_for(0)
		if g != null:
			var b := g.biome_at(int(player_pos.x), int(player_pos.z))
			if b == WorldGen.Biome.PEAKS or player_pos.y > SNOW_LINE:
				snow_target = 1.0
			elif b == WorldGen.Biome.WASTES:
				dust_target = 1.0
			var crater: Vector3 = g._crater
			ember_target = 1.0 - smoothstep(crater.z * 1.5, crater.z * 8.0, Vector2(player_pos.x, player_pos.z).distance_to(Vector2(crater.x, crater.y)))
	# High up, snow blows whatever the weather below is doing.
	var alt_target := clampf((player_pos.y - 95.0) / 120.0, 0.0, 1.0) if _dimension == 0 and not _underground else 0.0
	if w != null and _dimension == 0 and w.gen_for(0) != null and w.gen_for(0).revision >= 3:
		# Revision 3 climate (WorldGen.climate_at): snow in cold biomes / above their snowline,
		# dust over the badlands and mesas, haze only on the highest summits.
		var climate := w.gen_for(0).climate_at(player_pos)
		snow_target = climate.x
		dust_target = climate.y
		alt_target = climate.z if not _underground else 0.0
	if _forced_snow:
		snow_target = 1.0
	# A blizzard snows everywhere; a dust storm carries dust everywhere.
	snow_target = maxf(snow_target, _current[5])
	dust_target = maxf(dust_target, _current[6])
	altitude = move_toward(altitude, alt_target, delta * 0.25)
	if altitude > 0.05:
		snow_target = 1.0
	_snow_mix = move_toward(_snow_mix, snow_target, delta * 0.3)
	_dust_mix = move_toward(_dust_mix, dust_target, delta * 0.3)
	_ember_near = move_toward(_ember_near, ember_target, delta * 0.2)

	_update_wind(delta)

	var outside := _dimension == 0 and not _underground
	var precip: float = _current[1]
	var rain := precip * (1.0 - _snow_mix) * (1.0 - _dust_mix) if outside else 0.0
	var snow := precip * _snow_mix * (1.0 - _dust_mix) if outside else 0.0
	if outside:
		snow = maxf(snow, altitude * 0.85)
	var dust := dust_amount() if outside else 0.0
	var wind3 := Vector3(_wind_dir.x, 0.0, _wind_dir.y) * _wind_strength
	var light := _light_level()

	_rain.intensity = rain
	_set_active(_rain, rain > 0.01)
	_rain.wind = wind3 * 6.0 + Vector3(0.8, 0, 0.3)
	_rain.brightness = light
	_snow.intensity = snow
	_set_active(_snow, snow > 0.01)
	_snow.wind = wind3 * (3.0 + _current[5] * 4.0)
	_snow.brightness = light
	_dust.intensity = dust
	_set_active(_dust, dust > 0.02)
	_dust.wind = wind3 * 12.0 + Vector3(_wind_dir.x, 0, _wind_dir.y) * 2.0
	_dust.brightness = light
	_rain.keep_collider = _snow.visible or _dust.visible
	var hell := _dimension == 1
	var embers := ember_amount() if outside else 0.0
	_ash.intensity = 0.8 if hell else embers * 0.7
	_set_active(_ash, hell or embers > 0.03)
	_ash.wind = wind3 * 2.0 + Vector3(0.4, 0, 0.2)
	_ash.brightness = 0.6
	_embers.amount_ratio = 1.0 if hell else maxf(embers, 0.001)
	_set_active(_embers, hell or embers > 0.03)
	if camera != null:
		_embers.global_position = camera.global_position + Vector3(0, 6, 0)
	_update_breath(w, camera)

	# Rain soaks the ground and it dries slowly (faster in sunshine and in a
	# heatwave); snow settles in the cold and melts away elsewhere.
	if _dimension == 0:
		var sky: SkyController = w.sky if w != null else null
		var sun_up := sky != null and sky.darkness() < 0.3
		var wet_target := clampf(rain * 1.4, 0.0, 1.0)
		if wet_target > _wet:
			_wet = move_toward(_wet, wet_target, delta / 45.0)
		else:
			var dry := 260.0 if sun_up and _current[0] < 0.5 else 600.0
			_wet = move_toward(_wet, wet_target, delta / (dry * (1.0 - _current[7] * 0.7)))
		if snow > 0.05:
			_snow_cover = move_toward(_snow_cover, clampf(maxf(snow * 1.2, altitude * 1.4), 0.0, 1.0), delta / (90.0 if altitude < 0.2 and _current[5] < 0.5 else 20.0))
		else:
			_snow_cover = move_toward(_snow_cover, 0.0, delta / (500.0 if _snow_mix > 0.5 else 40.0 * (1.0 - _current[7] * 0.6)))
	else:
		_wet = move_toward(_wet, 0.0, delta / 20.0)
		_snow_cover = move_toward(_snow_cover, 0.0, delta / 20.0)

	RenderingServer.global_shader_parameter_set(&"wind_dir", _wind_dir)
	RenderingServer.global_shader_parameter_set(&"wind_strength", _wind_strength)
	CharCloth.set_wind(_wind_dir, _wind_strength)
	RenderingServer.global_shader_parameter_set(&"wetness", _wet if _dimension == 0 else 0.0)
	RenderingServer.global_shader_parameter_set(&"snow_cover", _snow_cover)
	RenderingServer.global_shader_parameter_set(&"rain_amount", rain)
	_legacy_materials(w)

	if Net.is_server() and _current[2] > 0.5 and w != null and w.replicator != null:
		_lightning_timer -= delta
		if _lightning_timer <= 0.0:
			_lightning_timer = randf_range(4.0, 14.0) / _current[2]
			_strike(w)
	# Sheet lightning: flickers inside distant clouds (local, unsynced).
	if outside and _current[2] > 0.3:
		_sheet_timer -= delta
		if _sheet_timer <= 0.0:
			_sheet_timer = randf_range(2.0, 7.0) / _current[2]
			var a := randf() * TAU
			_sky_flash(Vector3(cos(a), randf_range(0.15, 0.5), sin(a)), randf_range(0.25, 0.6))
	# Meteor shower: the sky draws the streaks; now and then a bright fireball
	# flashes the night (local, unsynced).
	if outside and meteor_amount() > 0.3:
		_meteor_timer -= delta
		if _meteor_timer <= 0.0:
			_meteor_timer = randf_range(5.0, 16.0)
			var a := randf() * TAU
			_sky_flash(Vector3(cos(a), randf_range(0.35, 0.8), sin(a)), randf_range(0.08, 0.18))


## The host's lightning: mostly around players at a distance, sometimes close
## (a strike within STRIKE_RADIUS hurts). It prefers high ground.
func _strike(w: GameWorld) -> void:
	var players := w.players_in(0)
	if players.is_empty():
		return
	var p: Player = players[randi() % players.size()]
	if w.tracker != null and p == w.local_player and w.tracker.underground:
		return
	var a := randf() * TAU
	var close := randf() < 0.12
	var pos := p.global_position + Vector3(cos(a), 0, sin(a)) * (randf_range(5.0, 22.0) if close else randf_range(35.0, 160.0))
	# Seek a nearby rise.
	var best := pos
	var best_h := w.surface_height_at(pos.x, pos.z)
	for i in 4:
		var q := pos + Vector3(randf_range(-12, 12), 0, randf_range(-12, 12))
		var h := w.surface_height_at(q.x, q.z)
		if h > best_h:
			best = q
			best_h = h
	if best_h > 0.0:
		best.y = best_h + 1.0
	w.replicator.broadcast_lightning(best, 0)
	for other: Player in players:
		if not other.dead and Vector2(other.global_position.x - best.x, other.global_position.z - best.z).length() < STRIKE_RADIUS \
				and absf(other.global_position.y - best.y) < 6.0:
			w.damage(other, 28.0, 0, "lightning")


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


## Host: choose what comes next from the weighted chain, respecting the clock.
func _pick_next() -> void:
	var w := _world()
	var hour := w.sky.time_of_day if w != null and w.sky != null else 12.0
	var night := hour < 5.0 or hour > 19.5
	var day := hour > 8.0 and hour < 17.0
	var options: Array = CHAIN.get(state, CHAIN["clear"])
	var total := 0.0
	var allowed: Array = []
	for o: Array in options:
		var s: String = o[0]
		if (s in NIGHT_ONLY and not night) or (s in DAY_ONLY and not day):
			continue
		allowed.append(o)
		total += float(o[1])
	var pick := "clear"
	var r := randf() * total
	for o: Array in allowed:
		r -= float(o[1])
		if r <= 0.0:
			pick = o[0]
			break
	var span: Array = DURATION.get(pick, [150.0, 300.0])
	_next_change = randf_range(span[0], span[1])
	_set_state(pick, 1.0 / randf_range(30.0, 90.0))
	_broadcast()


func _set_state(s: String, blend: float) -> void:
	if s == state:
		return
	state = s
	_blend_speed = blend
	if s != "rain":
		_forced_snow = false
	Events.weather_changed.emit(state)
	if ANNOUNCE.has(s) and _dimension == 0:
		Events.notify.emit(ANNOUNCE[s], "info")


func _broadcast() -> void:
	var w := _world()
	if w != null and w.replicator != null and w.sky != null:
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


## Breath vapour in the cold (snowy biomes, high ground, blizzards, cold nights
## in the north): a faint puff in front of the face every few seconds.
func _update_breath(w: GameWorld, camera: Camera3D) -> void:
	var cold := 0.0
	if _dimension == 0 and w != null and w.local_player != null and camera != null and not w.local_player.dead:
		cold = maxf(maxf(_snow_mix, altitude * 1.5), _current[5])
		if w.sky != null:
			cold = maxf(cold, _snow_mix * 0.5 + w.sky.darkness() * 0.3 * _snow_mix)
	var on := cold > 0.45
	if _breath.emitting != on:
		_breath.emitting = on
		_breath.visible = on or _breath.visible
	if not on:
		return
	var fwd := -camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var head := w.local_player.global_position + Vector3(0, 1.55, 0)
	_breath.global_position = head + fwd * 0.42
	var pm := _breath.process_material as ParticleProcessMaterial
	pm.direction = (fwd + Vector3(0, -0.15, 0)).normalized()
	_breath.amount_ratio = clampf(cold, 0.5, 1.0)


func _make_breath() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 10
	p.lifetime = 3.4
	p.explosiveness = 0.85
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.04
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 14.0
	pm.initial_velocity_min = 0.45
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3(0, 0.05, 0)
	pm.damping_min = 0.6
	pm.damping_max = 1.0
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.25))
	grow.add_point(Vector2(0.45, 1.0))
	grow.add_point(Vector2(1.0, 1.4))
	var ct := CurveTexture.new()
	ct.curve = grow
	pm.scale_curve = ct
	# Visible for the first ~1.3 s of each 3.4 s cycle: a puff, then a pause.
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.06, Color(1, 1, 1, 0.22))
	g.add_point(0.38, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.32, 0.32)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.92, 0.94, 0.97)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.4
	m.albedo_texture = _soft_dot()
	q.material = m
	p.draw_pass_1 = q
	p.emitting = false
	p.visible = false
	return p


static func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t


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
