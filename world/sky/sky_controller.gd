class_name SkyController
extends Node3D
## Day/night cycle, sun and moon, the environment (tonemap, GI, fog, glow,
## exposure) and how they change with the weather, underground and in the
## underworld. One in-game day lasts DAY_MINUTES real minutes; the server owns
## the clock.
##
## Works standalone too (main menu backdrop): with no GameWorld parent it just
## runs the clock and reads `weather` if one is assigned.
##
## The sky shader (world_sky.gdshader) and Atmosphere (its CPU twin) share
## one physical model, so the sun's colour, the ambient light, the fog and the
## clouds' lighting all come from the same atmosphere.

const DAY_MINUTES := 24.0
## In-game days per lunar cycle.
const MOON_CYCLE_DAYS := 8.0
## Overall light level. The original look used 1.05; the game is meant to be a
## touch dimmer.
const SUN_ENERGY := 0.95
const SKY_SHADER := preload("res://world/sky/world_sky.gdshader")

static var _noise_tex: NoiseTexture2D

var time_of_day := 8.5   ## hours 0..24
var day := 1
var environment := Environment.new()
var camera_attributes := CameraAttributesPractical.new()
var sun := DirectionalLight3D.new()
var moon := DirectionalLight3D.new()
## Assign when used outside GameWorld; inside GameWorld the world's Weather is used.
var weather: Weather
## Freeze the clock (menus, captures).
var paused := false

var _sky_mat := ShaderMaterial.new()
var _hell_glow := DirectionalLight3D.new()
var _dimension := 0
var _underground := 0.0   # smoothed 0..1
# Smoothed underground palette (CaveBiomes.palette_at), linear HDR.
var _cave_fog := Vector3(0.016, 0.0145, 0.013)
var _cave_bounce := Vector3(0.11, 0.095, 0.08)
var _cave_haze := Vector3(0.7, 0.62, 0.52)
var _cave_target: Dictionary = CaveBiomes.PALETTES[CaveBiomes.Kind.KARST]
var _cave_timer := 0.0
var _haze := {}
var _sync_timer := 0.0
var _atmos_timer := 0.0
var _flash := 0.0
var _flash_dir := Vector3(0, 0.3, 1)
# Atmosphere results (refreshed a few times per second).
var _sun_trans := Vector3.ONE
var _zenith := Vector3(0.2, 0.3, 0.45)
var _horizon := Vector3(0.5, 0.55, 0.6)
var _horizon_sun := Vector3(0.6, 0.55, 0.5)
var _sun_dir := Vector3.UP
var _moon_dir := Vector3.DOWN
var _moon_phase := 1.0
var _fog_mult := 1.0
var _quality := 1
var _raw := false
var _shadows := true
var _dof := false


static func cloud_noise() -> NoiseTexture2D:
	if _noise_tex == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_PERLIN
		n.frequency = 0.0085
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 5
		n.fractal_gain = 0.52
		n.seed = 1337
		_noise_tex = NoiseTexture2D.new()
		_noise_tex.width = 512
		_noise_tex.height = 512
		_noise_tex.seamless = true
		_noise_tex.seamless_blend_skirt = 0.15
		_noise_tex.generate_mipmaps = true
		_noise_tex.noise = n
	return _noise_tex


func _ready() -> void:
	_sky_mat.shader = SKY_SHADER
	_sky_mat.set_shader_parameter(&"cloud_noise", cloud_noise())
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
	environment.volumetric_fog_albedo = Color(0.85, 0.85, 0.85)
	environment.volumetric_fog_anisotropy = 0.72
	environment.volumetric_fog_length = 64.0
	environment.volumetric_fog_ambient_inject = 0.15
	environment.volumetric_fog_sky_affect = 0.0
	environment.glow_hdr_threshold = 1.0
	environment.glow_bloom = 0.03
	environment.glow_strength = 1.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for i in 7:
		environment.set_glow_level(i, i >= 1 and i <= 5)
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_density = 0.002
	environment.fog_sky_affect = 0.15
	environment.fog_aerial_perspective = 0.55
	environment.fog_sun_scatter = 0.12
	_apply_settings()
	Settings.changed.connect(func(section: String, _key: String) -> void:
		if section == "graphics":
			_apply_settings())
	var we := WorldEnvironment.new()
	we.environment = environment
	we.camera_attributes = camera_attributes
	add_child(we)

	sun.shadow_enabled = true
	sun.shadow_blur = 1.0
	sun.light_angular_distance = 0.5
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	moon.shadow_enabled = true
	moon.light_color = Color(0.62, 0.7, 0.95)
	moon.light_angular_distance = 0.5
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)
	# Underworld: the lava seas light everything from below.
	_hell_glow.light_color = Color(1.0, 0.36, 0.1)
	_hell_glow.shadow_enabled = false
	_hell_glow.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	_hell_glow.visible = false
	_hell_glow.look_at_from_position(Vector3.ZERO, Vector3(0.3, 1.0, 0.2), Vector3.FORWARD)
	add_child(_hell_glow)
	GraphicsQuality.apply_directional(sun, true)
	GraphicsQuality.apply_directional(moon, false)
	_update_lights(0.0, true)


func _apply_settings() -> void:
	_quality = int(Settings.get_value("graphics", "quality"))
	_fog_mult = float(Settings.get_value("graphics", "fog"))
	GraphicsQuality.apply_environment(environment)
	_shadows = GraphicsQuality.shadows_enabled()
	_dof = bool(Settings.get_value("graphics", "depth_of_field"))
	if GraphicsQuality.forward_plus():
		RenderingServer.camera_attributes_set_dof_blur_quality(
				[RenderingServer.DOF_BLUR_QUALITY_VERY_LOW, RenderingServer.DOF_BLUR_QUALITY_LOW,
				RenderingServer.DOF_BLUR_QUALITY_MEDIUM, RenderingServer.DOF_BLUR_QUALITY_HIGH][clampi(_quality, 0, 3)], _quality >= 2)
	if sun.is_inside_tree():
		GraphicsQuality.apply_directional(sun, true)
		GraphicsQuality.apply_directional(moon, false)
	(environment.sky as Sky).radiance_size = Sky.RADIANCE_SIZE_256 if _quality >= Settings.Quality.HIGH else Sky.RADIANCE_SIZE_128
	# Filmic AgX tonemapping; eye adaptation is scripted (see _update_lights)
	# so caves, nights and storms adapt by a believable, bounded amount.
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.25
	environment.tonemap_agx_white = 8.0
	environment.tonemap_agx_contrast = 1.45
	_raw = true
	camera_attributes.auto_exposure_enabled = false
	# The brightness slider (default 85 %) grades the final image.
	var bright := float(Settings.get_value("graphics", "brightness"))
	environment.adjustment_enabled = absf(bright - 0.85) > 0.005
	environment.adjustment_brightness = bright / 0.85


func set_dimension(dim: int) -> void:
	_dimension = dim
	_atmos_timer = 0.0


func sync_time(t: float, d: int) -> void:
	if absf(t - time_of_day) > 0.05:
		time_of_day = t
	day = d


## 0 in full daylight .. 1 in the dead of night / underground / underworld.
func darkness() -> float:
	if _dimension == 1:
		return 1.0
	return clampf(maxf(1.0 - _day_factor(), _underground), 0.0, 1.0)


## Lightning inside the clouds (Weather calls this; dir from the camera).
func flash_sky(dir: Vector3, strength := 1.0) -> void:
	_flash = maxf(_flash, strength)
	_flash_dir = dir.normalized()


func sun_direction() -> Vector3:
	return _sun_dir


func _day_factor() -> float:
	var sun_h := sin((time_of_day - 6.0) / 24.0 * TAU)
	return smoothstep(-0.12, 0.25, sun_h)


func _world() -> GameWorld:
	return get_parent() as GameWorld


func _weather() -> Weather:
	var w := _world()
	if w != null and w.weather != null:
		return w.weather
	return weather if is_instance_valid(weather) else null


func _process(delta: float) -> void:
	if not paused:
		time_of_day += delta * 24.0 / (DAY_MINUTES * 60.0)
	if time_of_day >= 24.0:
		time_of_day -= 24.0
		day += 1
	var w := _world()
	if w != null and Net.is_server() and w.replicator != null and w.weather != null:
		_sync_timer -= delta
		if _sync_timer <= 0.0:
			_sync_timer = 5.0
			w.replicator.broadcast_clock(time_of_day, day, w.weather.state_name())

	# Under rock the sun and sky are gone well before the player is deep: the
	# sun's shadows only reach ~100 m, so any sky light left on would light
	# distant cave walls as if they were outdoors (the old white-out).
	var under_target := 0.0
	if w != null and w.tracker != null and w.tracker.underground:
		under_target = clampf((w.tracker.depth - 3.0) / 9.0, 0.45, 1.0)
	# Eyes adapt faster going in than coming back out into daylight.
	var rate := 1.6 if under_target > _underground else 1.1
	_underground = lerpf(_underground, under_target, 1.0 - exp(-delta * rate))
	_update_cave_palette(w, delta)
	_flash = maxf(0.0, _flash - delta * 5.0)
	_update_lights(delta, false)


func _update_lights(delta: float, force: bool) -> void:
	var angle := (time_of_day - 6.0) / 24.0 * TAU   # sunrise at 6, sunset at 18
	_sun_dir = Vector3(cos(angle) * 0.85, sin(angle), 0.35).normalized()
	# The moon lags the sun by its phase angle: new moon rises with the sun,
	# full moon rises at sunset.
	var cycle := fposmod((float(day) + time_of_day / 24.0) / MOON_CYCLE_DAYS, 1.0)
	var ma := angle + PI + (cycle - 0.5) * TAU
	_moon_dir = Vector3(cos(ma) * 0.85, sin(ma), 0.22).normalized()
	_moon_phase = 0.5 * (1.0 - _sun_dir.dot(_moon_dir))
	sun.look_at_from_position(Vector3.ZERO, -_sun_dir, Vector3.UP if absf(_sun_dir.y) < 0.99 else Vector3.FORWARD)
	moon.look_at_from_position(Vector3.ZERO, -_moon_dir, Vector3.UP if absf(_moon_dir.y) < 0.99 else Vector3.FORWARD)

	var wx := _weather()
	var overcast := wx.overcast() if wx != null else 0.0
	var rain := wx.rain_amount_visual() if wx != null else 0.0
	var storm := wx.storm_amount() if wx != null else 0.0
	var fog := wx.fog_amount() if wx != null else 0.0
	var wet := wx.wetness() if wx != null else 0.0
	var dust := wx.dust_amount() if wx != null else 0.0
	var heat := wx.heat_amount() if wx != null else 0.0
	var ember := wx.ember_amount() if wx != null else 0.0
	var aurora := wx.aurora_amount() if wx != null else 0.0
	var meteors := wx.meteor_amount() if wx != null else 0.0
	var snowing := wx.snow_amount() if wx != null else 0.0
	var cover := wx.snow_cover() if wx != null else 0.0

	_atmos_timer -= delta
	if _atmos_timer <= 0.0 or force:
		_atmos_timer = 0.2
		_sun_trans = Atmosphere.sun_transmittance(_sun_dir)
		_zenith = Atmosphere.sky_radiance(Vector3.UP, _sun_dir, 8)
		var away := Vector3(-_sun_dir.x, 0.0, -_sun_dir.z).normalized()
		_horizon = Atmosphere.sky_radiance((away + Vector3(0, 0.08, 0)).normalized(), _sun_dir, 8)
		var toward := Vector3(_sun_dir.x, 0.0, _sun_dir.z).normalized()
		_horizon_sun = Atmosphere.sky_radiance((toward + Vector3(0, 0.08, 0)).normalized(), _sun_dir, 8)
		_set_cave_darkness()

	var hell := _dimension == 1
	var surface_light := 1.0 - _underground
	var dayf := _day_factor()
	var nightf := 1.0 - smoothstep(-0.18, 0.02, _sun_dir.y)

	# --- Sun: colour and strength straight from the atmosphere's transmittance.
	var t_lum := _sun_trans.dot(Vector3(0.2126, 0.7152, 0.0722))
	var t_max := maxf(maxf(_sun_trans.x, _sun_trans.y), maxf(_sun_trans.z, 1e-4))
	var sun_col := Color(_sun_trans.x / t_max, _sun_trans.y / t_max, _sun_trans.z / t_max)
	var cloud_block := overcast * 0.78 + storm * 0.15 + ember * 0.3
	var sun_e := SUN_ENERGY * clampf(t_lum / 0.78, 0.0, 1.0) * (1.0 - cloud_block) * smoothstep(-0.03, 0.06, _sun_dir.y)
	if wx != null and wx.ember_amount() > 0.0:
		sun_col = sun_col.lerp(Color(1.0, 0.45, 0.2), wx.ember_amount() * 0.6)
	sun.light_color = sun_col
	sun.light_energy = sun_e * surface_light * surface_light
	# Overcast skies soften shadows into a broad penumbra.
	sun.light_angular_distance = lerpf(0.5, 3.5, overcast)
	sun.shadow_enabled = sun.light_energy > 0.02 and not has_meta("no_shadow") and _shadows
	sun.visible = not hell
	var moon_e := 0.1 * smoothstep(0.0, 0.25, _moon_dir.y) * nightf * (0.25 + 0.75 * _moon_phase) * (1.0 - overcast * 0.8)
	moon.light_energy = moon_e * surface_light * surface_light
	moon.shadow_enabled = moon.light_energy > 0.02 and not has_meta("no_shadow") and sun.light_energy < 0.02 and _shadows
	moon.visible = not hell

	# --- Sky shader.
	var sky_dim := 1.0 - overcast * 0.45 - storm * 0.3
	var sun_light := _sun_trans * 1.0
	var zenith := _zenith * (1.0 - nightf) + Vector3(0.006, 0.008, 0.014) * nightf * (0.4 + 0.6 * _moon_phase)
	# Under a lid of cloud the ambient goes grey.
	var grey := zenith.dot(Vector3(0.3, 0.5, 0.2))
	var amb := zenith.lerp(Vector3(grey, grey, grey) * 1.25, overcast * 0.8) * (1.0 - storm * 0.45)
	_sky_mat.set_shader_parameter(&"sun_dir", _sun_dir)
	_sky_mat.set_shader_parameter(&"moon_dir", _moon_dir)
	_sky_mat.set_shader_parameter(&"moon_phase", _moon_phase)
	_sky_mat.set_shader_parameter(&"night", nightf)
	_sky_mat.set_shader_parameter(&"cloud_cover", clampf(0.32 + overcast * 0.68, 0.0, 1.0))
	_sky_mat.set_shader_parameter(&"cloud_dark", clampf(storm * 0.9 + rain * 0.35, 0.0, 1.0))
	_sky_mat.set_shader_parameter(&"cirrus", clampf(0.45 + overcast * 0.4 - storm * 0.5, 0.0, 1.0))
	_sky_mat.set_shader_parameter(&"haze", clampf(fog * 0.85 + rain * 0.45 + dust * 0.6 + heat * 0.25, 0.0, 1.0))
	_sky_mat.set_shader_parameter(&"aurora", aurora)
	_sky_mat.set_shader_parameter(&"meteors", meteors)
	_sky_mat.set_shader_parameter(&"heat", heat)
	_sky_mat.set_shader_parameter(&"embers", ember)
	_sky_mat.set_shader_parameter(&"sun_light", sun_light)
	_sky_mat.set_shader_parameter(&"sky_ambient", amb)
	_sky_mat.set_shader_parameter(&"sky_energy", sky_dim)
	_sky_mat.set_shader_parameter(&"underworld", 1.0 if hell else 0.0)
	_sky_mat.set_shader_parameter(&"flash", _flash)
	_sky_mat.set_shader_parameter(&"flash_dir", _flash_dir)
	var rainbow := clampf(wet * 1.5 - rain * 3.0 - overcast * 0.8, 0.0, 1.0) * smoothstep(0.02, 0.12, _sun_dir.y) * (1.0 - smoothstep(0.55, 0.75, _sun_dir.y))
	_sky_mat.set_shader_parameter(&"rainbow", rainbow)
	var wind := wx.wind_vector() if wx != null else Vector2(0.9, 0.44) * 0.3
	_sky_mat.set_shader_parameter(&"wind", wind * 0.012 + wind.normalized() * 0.003)

	# Underground the radiance cubemap (ambient, reflections, SDFGI's sky
	# light) is occluded by the rock: gem veins and wet rock stop mirroring a
	# bright blue sky, which read as white patches in the distance.
	var u := _underground
	_sky_mat.set_shader_parameter(&"occlusion", u)
	_sky_mat.set_shader_parameter(&"occluded_color", _cave_bounce * 0.35)

	# --- Environment.
	if hell:
		_hell_environment()
		return
	_hell_glow.visible = false
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Below ground the ambient is the cave's own tinted bounce, not the sky.
	environment.ambient_light_sky_contribution = lerpf(0.85, 0.0, u)
	var floor_col := Vector3(0.012, 0.015, 0.024)
	var amb_col := (amb * 0.8 + floor_col).lerp(_cave_bounce, u)
	environment.ambient_light_color = Color(amb_col.x, amb_col.y, amb_col.z)
	# Snow on the ground bounces light back up: brighter, cooler shadows.
	environment.ambient_light_energy = lerpf(0.45 * (1.0 - storm * 0.2) * (1.0 + cover * 0.3), 2.3, u)
	environment.background_energy_multiplier = 1.0
	# Fog takes the colour of the horizon away from the sun; aerial perspective
	# then pulls it towards the actual sky behind each object.
	var hz := (_horizon * 0.85 + _horizon_sun.limit_length(1.2) * 0.15) * (1.0 - nightf) + Vector3(0.008, 0.01, 0.016) * nightf
	var hz_grey := hz.dot(Vector3(0.3, 0.5, 0.2))
	hz = hz.lerp(Vector3(hz_grey, hz_grey, hz_grey * 1.05), overcast * 0.7 + fog * 0.3) * sky_dim
	# Falling snow: the air fills with a cool, bright grey-blue (light scattered
	# by the flakes), not the warm haze of a clear day.
	if snowing > 0.0:
		var sl := hz.dot(Vector3(0.3, 0.5, 0.2))
		hz = hz.lerp(Vector3(0.9, 0.94, 1.0) * sl, snowing * 0.6)
	if dust > 0.0:
		hz = hz.lerp(Vector3(0.42, 0.3, 0.2) * maxf(dayf, 0.08), dust * 0.6)
	if ember > 0.0:
		# Crater smoke: a brown-red murk, glowing faintly at night.
		hz = hz.lerp(Vector3(0.22, 0.08, 0.035) * maxf(dayf, 0.25), ember * 0.65)
	if heat > 0.0:
		var hl := hz.dot(Vector3(0.3, 0.5, 0.2))
		hz = hz.lerp(Vector3(hl * 1.12, hl * 1.0, hl * 0.84), heat * 0.4)
	# Underground, distance falls off into the cave's dark tinted murk. It also
	# covers the sky (fog_sky_affect) so the void past the streamed rock never
	# shows daylight.
	hz = hz.lerp(_cave_fog, u)
	environment.fog_light_color = Color(hz.x, hz.y, hz.z)
	environment.fog_light_energy = 1.0
	environment.fog_sun_scatter = 0.18 * (1.0 - overcast) * dayf * surface_light
	var morning := _mist_amount()
	var mist := morning + wet * (1.0 - rain) * 0.5
	var surface_density := (0.0013 + fog * 0.028 + rain * 0.006 + snowing * 0.009 + storm * 0.004 + dust * 0.012 + mist * 0.003 + ember * 0.004 + heat * 0.0008) * _fog_mult
	# High in the mountains a little cold haze hangs between the ranges (kept
	# light so the view across the peaks stays the reward for the climb).
	var alt := 0.0
	var gw := GameWorld.instance
	if gw != null and gw.weather != null:
		alt = gw.weather.altitude
	surface_density += alt * 0.0016 * _fog_mult
	var cave_density := 0.012 * (0.6 + 0.4 * _fog_mult)
	environment.fog_density = lerpf(surface_density, cave_density, u)
	# Depth of field: the far distance softens (an option), more so from the
	# mountain tops (the altitude blur option). Never underground.
	var alt_blur := alt > 0.03 and bool(Settings.get_value("graphics", "altitude_blur"))
	camera_attributes.dof_blur_far_enabled = (alt_blur or _dof) and u < 0.5
	if camera_attributes.dof_blur_far_enabled:
		var a := alt if alt_blur else 0.0
		camera_attributes.dof_blur_far_distance = lerpf(700.0, 260.0, a) if not _dof else lerpf(160.0, 120.0, a)
		camera_attributes.dof_blur_far_transition = lerpf(400.0, 200.0, a) if not _dof else 220.0
		camera_attributes.dof_blur_amount = (0.02 + a * 0.05) if not _dof else 0.045 + a * 0.03
	environment.fog_aerial_perspective = 0.6 * (1.0 - fog * 0.5) * (1.0 - u)
	environment.fog_sky_affect = lerpf(0.12 + fog * 0.6 + rain * 0.2, 1.0, u)
	# Ground mist that pools in the valleys at dawn and after rain.
	environment.fog_height = float(WorldGen.SEA_LEVEL) + 5.0
	environment.fog_height_density = (mist * 0.025 + fog * 0.02) * _fog_mult * surface_light
	# Volumetric fog: shafts of light at dawn/dusk and in heavy weather; in
	# caves a thin tinted haze that gives torches and glowing crystals a halo.
	var golden := clampf(1.0 - absf(_sun_dir.y) / 0.3, 0.0, 1.0) * smoothstep(-0.05, 0.03, _sun_dir.y)
	var forest := 0.0
	if _world() != null and _world().local_player != null:
		var g := _world().gen_for(0)
		if g != null:
			var p := _world().local_player.global_position
			var b := g.biome_at(int(p.x), int(p.z))
			forest = 1.0 if b == WorldGen.Biome.FOREST else (0.6 if b == WorldGen.Biome.MARSH else 0.0)
	# Weather visibility is the distance fog's job; volumetric fog adds local
	# depth (shafts, halos). Too dense, its far slice paints a pale wall over
	# everything beyond its range (the horizon included).
	var vol := 0.0015 + golden * 0.008 * (1.0 - overcast) + forest * 0.005 * dayf + morning * 0.004 + fog * 0.011 + rain * 0.004 + dust * 0.01 + ember * 0.006
	environment.volumetric_fog_density = lerpf(vol, 0.0045, u) * _fog_mult
	var vol_albedo := (Vector3(0.88, 0.88, 0.9) if dust < 0.3 else Vector3(0.85, 0.7, 0.55)) * (1.0 - overcast * 0.35 - storm * 0.35)
	if ember > 0.0:
		vol_albedo = vol_albedo.lerp(Vector3(0.6, 0.32, 0.2), ember)
	vol_albedo = vol_albedo.lerp(_cave_haze, u)
	environment.volumetric_fog_albedo = Color(vol_albedo.x, vol_albedo.y, vol_albedo.z)
	environment.volumetric_fog_emission = Color(0, 0, 0)
	environment.volumetric_fog_anisotropy = lerpf(lerpf(0.75, 0.3, overcast), 0.45, u)
	environment.volumetric_fog_ambient_inject = lerpf(0.06 + overcast * 0.15, 0.12, u)
	# Bounce light from the sky probe (SDFGI) is irrelevant under rock; torch
	# bounce still comes through SDFGI's own light injection.
	environment.volumetric_fog_gi_inject = lerpf(1.0, 0.6, u)
	# Eyes open up underground; only genuinely hot things (lava, torches, the
	# brightest crystals) should bloom, not every lit wall.
	environment.glow_hdr_threshold = lerpf(1.0, 1.35, u)
	# Horizon haze for DistantLand (its own aerial perspective).
	# The horizon of the sky as the sky shader actually draws it (atmosphere,
	# pulled towards the cloud murk by haze, dimmed by the cloud deck), so far
	# ranges fade into the real sky colour - in a storm a dark grey, never a
	# pale silhouette.
	var haze_k := clampf(fog * 0.85 + rain * 0.45 + dust * 0.6 + heat * 0.25, 0.0, 1.0)
	var murk_k := clampf(haze_k * 0.8 + haze_k * 0.35, 0.0, 1.0)
	var night_hz := Vector3(0.008, 0.01, 0.016)
	var sky_hz := _horizon * (1.0 - nightf) + night_hz * nightf
	var sky_hz_sun := _horizon_sun.limit_length(1.5) * (1.0 - nightf) + night_hz * nightf
	var murk_a := amb * 1.1 * (1.0 - overcast * 0.4)
	sky_hz = sky_hz.lerp(murk_a.lerp(Vector3.ONE * sky_hz.dot(Vector3(0.3, 0.5, 0.2)), 0.4), murk_k)
	sky_hz_sun = sky_hz_sun.lerp(murk_a.lerp(Vector3.ONE * sky_hz_sun.dot(Vector3(0.3, 0.5, 0.2)), 0.4), murk_k)
	# Low cloud near the horizon (the deck the sky shader fades into haze).
	# Cloud bases as world_sky.gdshader lights them: sky ambient, darkened by
	# thickness (cloud_dark) - a storm deck is a fifth as bright as fair cloud.
	var deck := clampf(overcast * 0.9 + storm * 0.1, 0.0, 0.95)
	var cloud_dark := clampf(storm * 0.9 + rain * 0.35, 0.0, 1.0)
	var base_col := amb * 0.75 * (1.0 - cloud_dark * 0.65) * (1.0 - cloud_dark * 0.5) * (1.0 - overcast * 0.5)
	sky_hz = sky_hz.lerp(base_col, deck) * sky_dim
	sky_hz_sun = sky_hz_sun.lerp(base_col, deck) * sky_dim
	if ember > 0.0:
		sky_hz = sky_hz.lerp(Vector3(0.22, 0.08, 0.035) * maxf(dayf, 0.25), ember * 0.7)
		sky_hz_sun = sky_hz_sun.lerp(Vector3(0.3, 0.1, 0.04) * maxf(dayf, 0.25), ember * 0.7)
	_haze = {
		"fog_col": hz,
		"sky_hz": sky_hz,
		"sky_hz_sun": sky_hz_sun,
		"fog_aerial": environment.fog_aerial_perspective,
		"fog_sky_affect": environment.fog_sky_affect,
		"fog_dens": environment.fog_density,
		# Far haze: clear-day air thins it; weather thickens it as much as the near fog.
		"far_dens": 0.00014 + maxf(environment.fog_density - 0.0013 * _fog_mult, 0.0) * 0.9,
		"sun_scatter": environment.fog_sun_scatter,
		"sun_dir_w": _sun_dir,
		"sun_col": Vector3(sun.light_color.r, sun.light_color.g, sun.light_color.b) * sun.light_energy,
		"fog_h": environment.fog_height,
		"fog_h_dens": environment.fog_height_density,
	}
	if "--cave-debug=nosdfgi" in OS.get_cmdline_user_args():
		environment.sdfgi_energy = 0.0
	if _raw:
		# Eyes adapt a little to the dark (and to gloomy storms), never fully.
		var gloom := clampf(nightf * 0.8 + storm * 0.3 + overcast * 0.15, 0.0, 1.0) * surface_light
		environment.tonemap_exposure = 1.1 * lerpf(1.0, 1.6, gloom) * lerpf(1.0, 1.38, u)


## Aerial-perspective inputs for the horizon (DistantLand's shader uniforms).
func haze_params() -> Dictionary:
	return _haze


## Smoothly follows the underground palette of where the player stands.
func _update_cave_palette(w: GameWorld, delta: float) -> void:
	_cave_timer -= delta
	if _cave_timer <= 0.0 and w != null and w.local_player != null:
		_cave_timer = 0.5
		var pos := w.local_player.global_position
		var g := w.gen_for(_dimension)
		if g != null:
			var loc := w.location_at(pos, _dimension)
			_cave_target = CaveBiomes.palette_at(pos, g.world_seed, _dimension, g.revision, String(loc.id) if loc != null else "")
	var k := 1.0 - exp(-delta * 0.8)
	var f: Color = _cave_target["fog"]
	var b: Color = _cave_target["bounce"]
	var h: Color = _cave_target["haze"]
	_cave_fog = _cave_fog.lerp(Vector3(f.r, f.g, f.b), k)
	_cave_bounce = _cave_bounce.lerp(Vector3(b.r, b.g, b.b), k)
	_cave_haze = _cave_haze.lerp(Vector3(h.r, h.g, h.b), k)


## Terrain materials hide sky (ambient) light where the mesher found no open
## sky. Out in daylight that is total, so cave mouths stay dark; underground
## the ambient is the cave's own bounce colour, so it is let back in as fill
## (and SDFGI's torch bounce with it).
func _set_cave_darkness() -> void:
	var w := _world()
	if w == null:
		return
	var value := lerpf(1.0, 0.3, _underground)
	if "--cave-debug=cd1" in OS.get_cmdline_user_args():
		value = 1.0
	for d: int in w.worlds:
		var vw: Object = w.worlds[d]
		if vw == null:
			continue
		for prop: String in ["opaque_material", "terrain_material"]:
			var mat := vw.get(prop) as ShaderMaterial
			if mat != null:
				mat.set_shader_parameter(&"cave_darkness", value)


func _mist_amount() -> float:
	# Dawn mist: thickest just before sunrise, burned off by mid-morning.
	var t := time_of_day
	return clampf(1.0 - absf(t - 6.3) / 2.2, 0.0, 1.0) * 0.8


func _hell_environment() -> void:
	# Under the underworld's rock ceilings the lava-sea glow and the ember sky
	# fade; what is left is a close, smoky red dark.
	var u := _underground
	var open := 1.0 - u
	sun.visible = true
	sun.light_color = Color(1.0, 0.45, 0.22)
	sun.light_energy = 0.32 * open * open
	sun.light_angular_distance = 2.5
	sun.look_at_from_position(Vector3.ZERO, Vector3(-0.3, -1.0, 0.45), Vector3.FORWARD)
	sun.shadow_enabled = not has_meta("no_shadow") and sun.light_energy > 0.02 and _shadows
	moon.visible = false
	_hell_glow.visible = true
	_hell_glow.light_energy = 0.28 * lerpf(1.0, 0.25, u)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Charcoal smoke and warm stone bounce, not a red filter. Lava and
	# braziers carry the saturated accents so arena materials stay readable.
	environment.ambient_light_color = Color(0.32, 0.25, 0.21).lerp(Color(_cave_bounce.x, _cave_bounce.y, _cave_bounce.z), u)
	environment.ambient_light_energy = lerpf(0.5, 0.45, u)
	environment.fog_light_color = Color(0.13, 0.10, 0.085).lerp(Color(_cave_fog.x, _cave_fog.y, _cave_fog.z), u)
	environment.fog_light_energy = 1.0
	environment.fog_sun_scatter = 0.0
	environment.fog_density = lerpf(0.006, 0.018, u) * _fog_mult
	environment.fog_aerial_perspective = 0.3 * open
	environment.fog_sky_affect = lerpf(0.5, 1.0, u)
	environment.fog_height = 20.0
	environment.fog_height_density = 0.03 * _fog_mult * open
	environment.volumetric_fog_albedo = Color(0.48, 0.43, 0.39)
	environment.volumetric_fog_emission = Color(0.008, 0.003, 0.001) * open
	environment.volumetric_fog_emission_energy = 1.0
	environment.volumetric_fog_anisotropy = 0.4
	environment.volumetric_fog_ambient_inject = lerpf(0.06, 0.25, u)
	environment.volumetric_fog_gi_inject = 1.0
	environment.volumetric_fog_density = lerpf(0.005, 0.009, u) * _fog_mult
	environment.glow_hdr_threshold = lerpf(1.0, 1.25, u)
	if _raw:
		environment.tonemap_exposure = 1.35 * lerpf(1.0, 1.2, u)
