class_name GraphicsQuality
extends RefCounted
## Applies the Low / Medium / High / Ultra preset (Settings.graphics.quality)
## to an Environment and its lights.
##
##   Low     fastest: no screen-space effects, no volumetrics, small shadows.
##   Medium  the default: half-res SSAO, soft 2-split sun shadows, height fog
##           and aerial perspective (no volumetrics). Budgeted to cost no more
##           than the old Medium.
##   High    + SDFGI (bounced light), half-res SSIL, SSR (reflections in water), filtered
##           volumetric fog (god rays at dawn/dusk, in forests, in storms),
##           4-split shadows.
##   Ultra   lavish: finer SSIL, 5 SDFGI cascades, finer volumetric fog, 8k shadows
##           to 160 m with a softer filter, longer SSR.



static func quality() -> int:
	return int(Settings.get_value("graphics", "quality"))


static func apply_environment(env: Environment) -> void:
	var q := quality()
	var fog_mult := float(Settings.get_value("graphics", "fog"))
	var bloom := float(Settings.get_value("graphics", "bloom"))

	env.ssao_enabled = q >= Settings.Quality.MEDIUM
	env.ssao_radius = [1.0, 1.0, 1.3, 1.5][q]
	env.ssao_intensity = [1.6, 1.6, 1.8, 2.0][q]
	env.ssao_power = 1.4
	env.ssao_detail = 0.5
	env.ssao_light_affect = 0.08
	env.ssao_ao_channel_affect = 0.4
	# Screen-space indirect light: colour bleeding and bounce between nearby
	# surfaces (torch-lit walls, sunlit ground under eaves) on top of SDFGI.
	env.ssil_enabled = q >= Settings.Quality.HIGH
	env.ssil_radius = 3.0 if q == Settings.Quality.HIGH else 4.0
	env.ssil_intensity = 0.8
	env.ssr_enabled = q >= Settings.Quality.HIGH
	env.ssr_max_steps = [16, 24, 40, 64][q]
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 2.5
	env.ssr_depth_tolerance = 0.25
	env.sdfgi_enabled = q >= Settings.Quality.HIGH
	env.sdfgi_cascades = 4 if q == Settings.Quality.HIGH else 5
	env.sdfgi_min_cell_size = 0.25
	env.sdfgi_use_occlusion = true
	env.sdfgi_read_sky_light = true
	env.sdfgi_bounce_feedback = 0.45
	env.sdfgi_energy = 0.9
	env.volumetric_fog_enabled = q >= Settings.Quality.HIGH and fog_mult > 0.01
	env.volumetric_fog_length = [48.0, 48.0, 80.0, 128.0][q]
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.9 if q <= Settings.Quality.MEDIUM else 0.85
	env.glow_enabled = bloom > 0.01
	env.glow_intensity = 0.8 * bloom

	var vol_size: int = [48, 48, 96, 128][q]
	var vol_depth: int = [32, 32, 96, 128][q]
	RenderingServer.environment_set_volumetric_fog_volume_size(vol_size, vol_depth)
	RenderingServer.environment_set_volumetric_fog_filter_active(q >= Settings.Quality.HIGH)
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 4096, 8192][q], true)
	RenderingServer.directional_soft_shadow_filter_set_quality([
			RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
			RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][q])
	RenderingServer.environment_set_ssao_quality(
			[RenderingServer.ENV_SSAO_QUALITY_VERY_LOW, RenderingServer.ENV_SSAO_QUALITY_LOW,
			RenderingServer.ENV_SSAO_QUALITY_MEDIUM, RenderingServer.ENV_SSAO_QUALITY_HIGH][q],
			q <= Settings.Quality.HIGH, 0.5, 2, 50, 300)
	RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_LOW if q == Settings.Quality.HIGH else RenderingServer.ENV_SSIL_QUALITY_MEDIUM, true, 0.5, 4, 50, 300)
	RenderingServer.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_32 if q == Settings.Quality.HIGH else RenderingServer.ENV_SDFGI_RAY_COUNT_64)
	RenderingServer.environment_set_sdfgi_frames_to_converge(RenderingServer.ENV_SDFGI_CONVERGE_IN_30_FRAMES)
	RenderingServer.environment_set_sdfgi_frames_to_update_light(RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_8_FRAMES if q == Settings.Quality.HIGH else RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_4_FRAMES)


## Sun/moon shadow setup for this quality.
static func apply_directional(light: DirectionalLight3D, sun: bool) -> void:
	var q := quality()
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q <= Settings.Quality.MEDIUM else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	light.directional_shadow_max_distance = ([40.0, 60.0, 100.0, 160.0][q]) * (1.0 if sun else 0.7)
	light.directional_shadow_blend_splits = q >= Settings.Quality.HIGH
	light.directional_shadow_fade_start = 0.85
	light.light_volumetric_fog_energy = [0.0, 1.0, 1.2, 1.4][q]


## How far (m) chunk meshes still cast shadows.
static func shadow_caster_distance() -> float:
	return [32.0, 48.0, 80.0, 120.0][quality()]


## Shadow-casting budget for point lights at this quality.
static func point_shadows_allowed() -> int:
	return [0, 2, 4, 8][quality()]
