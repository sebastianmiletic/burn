class_name SkyController
extends Node3D
## Day/night cycle, sun and moon, the environment (GI, fog, glow, tonemap)
## and how they change underground and in the underworld.
## One in-game day lasts DAY_MINUTES real minutes; the server owns the clock.

const DAY_MINUTES := 24.0

var time_of_day := 8.5   ## hours 0..24
var day := 1
var environment := Environment.new()
var sun := DirectionalLight3D.new()
var moon := DirectionalLight3D.new()

var _sky_mat := ShaderMaterial.new()
var _dimension := 0
var _underground := 0.0   # smoothed 0..1
var _sync_timer := 0.0


func _ready() -> void:
	_sky_mat.shader = preload("res://world/sky/world_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 0.95
	environment.volumetric_fog_density = 0.012
	environment.volumetric_fog_albedo = Color(0.8, 0.78, 0.75)
	environment.volumetric_fog_anisotropy = 0.5
	environment.volumetric_fog_length = 96.0
	environment.volumetric_fog_ambient_inject = 0.25
	environment.glow_hdr_threshold = 1.0
	environment.glow_bloom = 0.04
	environment.glow_strength = 1.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for i in 7:
		environment.set_glow_level(i, i >= 1 and i <= 5)
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_density = 0.004
	environment.fog_sky_affect = 0.25
	GraphicsQuality.apply_environment(environment)
	Settings.changed.connect(func(section: String, _key: String) -> void:
		if section == "graphics":
			GraphicsQuality.apply_environment(environment)
			GraphicsQuality.apply_directional(sun, true)
			GraphicsQuality.apply_directional(moon, false))
	var we := WorldEnvironment.new()
	we.environment = environment
	add_child(we)

	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 0.6
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	add_child(sun)
	moon.shadow_enabled = true
	moon.light_color = Color(0.55, 0.63, 0.9)
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	add_child(moon)
	GraphicsQuality.apply_directional(sun, true)
	GraphicsQuality.apply_directional(moon, false)


func set_dimension(dim: int) -> void:
	_dimension = dim


func sync_time(t: float, d: int) -> void:
	if absf(t - time_of_day) > 0.05:
		time_of_day = t
	day = d


## 0 in full daylight .. 1 in the dead of night / underground / underworld.
func darkness() -> float:
	if _dimension == 1:
		return 1.0
	return clampf(maxf(1.0 - _day_factor(), _underground), 0.0, 1.0)


func _day_factor() -> float:
	var sun_h := sin((time_of_day - 6.0) / 24.0 * TAU)
	return smoothstep(-0.12, 0.25, sun_h)


func _process(delta: float) -> void:
	time_of_day += delta * 24.0 / (DAY_MINUTES * 60.0)
	if time_of_day >= 24.0:
		time_of_day -= 24.0
		day += 1
	var w := get_parent() as GameWorld
	if Net.is_server() and w != null and w.replicator != null:
		_sync_timer -= delta
		if _sync_timer <= 0.0:
			_sync_timer = 5.0
			w.replicator.broadcast_clock(time_of_day, day, w.weather.state_name())

	var under_target := 0.0
	if w != null and w.tracker != null and w.tracker.underground:
		under_target = clampf((w.tracker.depth - 4.0) / 18.0, 0.0, 1.0)
	_underground = lerpf(_underground, under_target, 1.0 - exp(-delta * 1.5))

	var angle := (time_of_day - 6.0) / 24.0 * TAU   # sunrise at 6, sunset at 18
	var sun_dir := Vector3(cos(angle) * 0.85, sin(angle), 0.35).normalized()
	var moon_dir := -sun_dir + Vector3(0.0, 0.0, 0.2)
	sun.look_at_from_position(Vector3.ZERO, -sun_dir, Vector3.UP if absf(sun_dir.y) < 0.99 else Vector3.FORWARD)
	moon.look_at_from_position(Vector3.ZERO, -moon_dir.normalized(), Vector3.UP)
	var dayf := _day_factor()
	var dusk := clampf(1.0 - absf(sun_dir.y) / 0.35, 0.0, 1.0) * smoothstep(-0.15, 0.05, sun_dir.y)
	var weather_dim := 1.0
	var cover := 0.4
	var storm := 0.0
	if w != null and w.weather != null:
		weather_dim = 1.0 - w.weather.overcast() * 0.55
		cover = 0.35 + w.weather.overcast() * 0.6
		storm = w.weather.storm_amount()

	var surface_light := 1.0 - _underground
	var hell := _dimension == 1
	sun.visible = not hell
	moon.visible = not hell
	sun.light_energy = (1.05 * smoothstep(-0.05, 0.25, sun_dir.y)) * weather_dim * surface_light
	sun.light_color = Color(1.0, 0.62, 0.38).lerp(Color(1.0, 0.93, 0.84), smoothstep(0.05, 0.5, sun_dir.y))
	sun.shadow_enabled = sun.light_energy > 0.02 and not has_meta("no_shadow")
	moon.light_energy = 0.12 * smoothstep(0.0, 0.3, moon_dir.y) * (1.0 - dayf) * weather_dim * surface_light
	moon.shadow_enabled = moon.light_energy > 0.02 and not has_meta("no_shadow")

	_sky_mat.set_shader_parameter(&"day", dayf)
	_sky_mat.set_shader_parameter(&"dusk", dusk)
	_sky_mat.set_shader_parameter(&"cloud_cover", cover)
	_sky_mat.set_shader_parameter(&"storm", storm)
	_sky_mat.set_shader_parameter(&"underworld", 1.0 if hell else 0.0)
	_sky_mat.set_shader_parameter(&"sun_dir", sun_dir)
	_sky_mat.set_shader_parameter(&"moon_dir", moon_dir.normalized())

	if hell:
		environment.ambient_light_energy = 0.35
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color(0.5, 0.12, 0.05)
		environment.fog_light_color = Color(0.25, 0.04, 0.02)
		environment.fog_density = 0.012
		environment.volumetric_fog_albedo = Color(0.9, 0.4, 0.25)
		environment.volumetric_fog_emission = Color(0.04, 0.006, 0.0)
		environment.volumetric_fog_density = 0.02 * float(Settings.get_value("graphics", "fog"))
	else:
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		environment.ambient_light_energy = lerpf(0.18, 0.75, dayf) * weather_dim * lerpf(1.0, 0.05, _underground)
		var fog_day := Color(0.55, 0.52, 0.5).lerp(Color(0.7, 0.4, 0.22), dusk * 0.6)
		environment.fog_light_color = Color(0.015, 0.016, 0.022).lerp(fog_day, dayf) * lerpf(1.0, 0.05, _underground)
		var weather_fog := w.weather.fog_amount() if w != null and w.weather != null else 0.0
		environment.fog_density = (0.0011 + weather_fog * 0.03) * float(Settings.get_value("graphics", "fog")) * lerpf(1.0, 3.0, _underground)
		environment.volumetric_fog_albedo = Color(0.8, 0.78, 0.75)
		environment.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
		environment.volumetric_fog_density = (0.002 + weather_fog * 0.03) * float(Settings.get_value("graphics", "fog"))
	if w != null:
		for d: int in w.worlds:
			var mat: ShaderMaterial = (w.worlds[d] as VoxelWorld).opaque_material
			mat.set_shader_parameter(&"cave_darkness", 1.0)
