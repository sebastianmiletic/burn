class_name GraphicsQuality
extends RefCounted
## Applies the graphics options (Settings.gfx: a Low / Medium / High / Ultra
## preset, or the player's individual overrides) to an Environment, the sun
## and moon, and the shadow atlas. Everything here can be re-applied at any
## time: every property a level touches is set at every level, so switching
## presets at runtime leaves nothing behind.
##
##   shadows         0 off, 1 low (2k atlas, 2 splits, 40 m) .. 4 ultra (8k, 4 splits, 160 m)
##   ssao            0 off .. 3 high
##   ssil            0 off, 1 on (screen-space bounce light)
##   ssr             0 off, 1 low, 2 high (reflections in water and wet stone)
##   gi              0 off, 1 SDFGI (4 cascades), 2 SDFGI high (5 cascades, more rays)
##   volumetric_fog  0 off, 1 low (coarse froxels), 2 high
## Screen-space effects, SDFGI and volumetric fog exist only in Forward+;
## the compatibility renderer (OpenGL) keeps distance/height fog and shadows.

const SHADOW_ATLAS := [1024, 2048, 4096, 4096, 8192]
const SHADOW_DISTANCE := [0.0, 40.0, 60.0, 90.0, 150.0]
const SHADOW_CASTERS := [0.0, 32.0, 48.0, 72.0, 112.0]


static func quality() -> int:
	return int(Settings.get_value("graphics", "quality"))


static func level(key: String) -> int:
	return Settings.gfx(key)


static func forward_plus() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"


static func apply_environment(env: Environment) -> void:
	var fp := forward_plus()
	var fog_mult := float(Settings.get_value("graphics", "fog"))
	var bloom := float(Settings.get_value("graphics", "bloom"))
	var ao := level("ssao") if fp else 0
	var il := level("ssil") if fp else 0
	var sr := level("ssr") if fp else 0
	var gi := level("gi") if fp else 0
	var vf := level("volumetric_fog") if fp else 0
	var sh := level("shadows")

	env.ssao_enabled = ao > 0
	env.ssao_radius = [1.0, 1.0, 1.3, 1.5][ao]
	env.ssao_intensity = [1.6, 1.6, 1.8, 2.0][ao]
	env.ssao_power = 1.4
	env.ssao_detail = 0.5
	env.ssao_light_affect = 0.08
	env.ssao_ao_channel_affect = 0.4
	# Screen-space indirect light: colour bleeding and bounce between nearby
	# surfaces (torch-lit walls, sunlit ground under eaves) on top of SDFGI.
	env.ssil_enabled = il > 0
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.8
	env.ssr_enabled = sr > 0
	env.ssr_max_steps = [16, 32, 56][sr]
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 2.5
	env.ssr_depth_tolerance = 0.25
	env.sdfgi_enabled = gi > 0
	env.sdfgi_cascades = 5 if gi >= 2 else 4
	env.sdfgi_min_cell_size = 0.25
	env.sdfgi_use_occlusion = true
	env.sdfgi_read_sky_light = true
	env.sdfgi_bounce_feedback = 0.45
	env.sdfgi_energy = 0.9
	env.volumetric_fog_enabled = vf > 0 and fog_mult > 0.01
	env.volumetric_fog_length = [48.0, 64.0, 112.0][vf]
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.9 if vf <= 1 else 0.85
	env.glow_enabled = bloom > 0.01
	env.glow_intensity = 0.8 * bloom

	if not fp:
		RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS[sh], true)
		return
	# Half-resolution GI gather: most of SDFGI's per-pixel cost, hardly visible
	# under the upscaler. Full resolution on SDFGI high.
	RenderingServer.gi_set_use_half_resolution(gi < 2)
	RenderingServer.environment_set_volumetric_fog_volume_size([48, 64, 112][vf], [32, 48, 112][vf])
	RenderingServer.environment_set_volumetric_fog_filter_active(vf >= 1)
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS[sh], true)
	RenderingServer.directional_soft_shadow_filter_set_quality([
			RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
			RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
			RenderingServer.SHADOW_QUALITY_SOFT_HIGH][sh])
	RenderingServer.positional_soft_shadow_filter_set_quality([
			RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
			RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
			RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][sh])
	RenderingServer.environment_set_ssao_quality(
			[RenderingServer.ENV_SSAO_QUALITY_VERY_LOW, RenderingServer.ENV_SSAO_QUALITY_LOW,
			RenderingServer.ENV_SSAO_QUALITY_MEDIUM, RenderingServer.ENV_SSAO_QUALITY_HIGH][ao],
			ao <= 2, 0.5, 2, 50, 300)
	RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_MEDIUM, true, 0.5, 4, 50, 300)
	RenderingServer.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_64 if gi >= 2 else RenderingServer.ENV_SDFGI_RAY_COUNT_32)
	RenderingServer.environment_set_sdfgi_frames_to_converge(RenderingServer.ENV_SDFGI_CONVERGE_IN_30_FRAMES)
	RenderingServer.environment_set_sdfgi_frames_to_update_light(RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_4_FRAMES if gi >= 2 else RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_8_FRAMES)


## Sun/moon shadow setup for this quality.
static func apply_directional(light: DirectionalLight3D, sun: bool) -> void:
	var sh := level("shadows")
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if sh <= 2 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	light.directional_shadow_max_distance = maxf(SHADOW_DISTANCE[sh], 1.0) * (1.0 if sun else 0.7)
	light.directional_shadow_blend_splits = sh >= 3
	light.directional_shadow_fade_start = 0.85
	# Sharper first split for the same atlas: most of the detail is near.
	light.directional_shadow_split_1 = 0.08 if sh >= 3 else 0.15
	light.directional_shadow_split_2 = 0.22
	light.directional_shadow_split_3 = 0.5
	light.light_volumetric_fog_energy = [0.0, 1.0, 1.2, 1.4][level("volumetric_fog")] if forward_plus() else 0.0


## Whether the sun and moon cast shadows at all.
static func shadows_enabled() -> bool:
	return level("shadows") > 0


## How far (m) chunk meshes still cast shadows.
static func shadow_caster_distance() -> float:
	return SHADOW_CASTERS[level("shadows")]


## Shadow-casting budget for point lights at this quality.
static func point_shadows_allowed() -> int:
	return [0, 0, 2, 4, 8][level("shadows")]


## Flora quality (density / distance tier 0..3).
static func foliage() -> int:
	return clampi(level("foliage"), 0, 3)


## Streamed terrain radius in chunks.
static func view_radius() -> int:
	return clampi(level("view_distance"), 4, 16)
