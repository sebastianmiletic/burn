class_name GraphicsQuality
extends RefCounted
## Applies the Low / Medium / High / Ultra preset (Settings.graphics.quality)
## to an Environment and its lights. Fine detail disappears inside a glyph
## cell, so the presets mostly trade lighting richness (GI, fog, reflections)
## rather than texture resolution.


static func apply_environment(env: Environment) -> void:
	var q := int(Settings.get_value("graphics", "quality"))
	var fog_mult := float(Settings.get_value("graphics", "fog"))
	var bloom := float(Settings.get_value("graphics", "bloom"))

	env.ssao_enabled = q >= Settings.Quality.MEDIUM
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.0
	env.ssil_enabled = q >= Settings.Quality.ULTRA
	env.ssr_enabled = q >= Settings.Quality.HIGH
	env.ssr_max_steps = 32 if q < Settings.Quality.ULTRA else 64
	env.sdfgi_enabled = q >= Settings.Quality.HIGH
	env.sdfgi_cascades = 3 if q == Settings.Quality.HIGH else 5
	env.sdfgi_min_cell_size = 0.25
	env.sdfgi_use_occlusion = true
	env.volumetric_fog_enabled = q >= Settings.Quality.HIGH and fog_mult > 0.01
	env.glow_enabled = bloom > 0.01
	env.glow_intensity = 0.8 * bloom

	var vol_size: int = [64, 64, 96, 128][q]
	RenderingServer.environment_set_volumetric_fog_volume_size(vol_size, vol_size)
	RenderingServer.environment_set_volumetric_fog_filter_active(q >= Settings.Quality.HIGH)
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 4096, 8192][q], true)
	RenderingServer.environment_set_ssao_quality(
			[RenderingServer.ENV_SSAO_QUALITY_VERY_LOW, RenderingServer.ENV_SSAO_QUALITY_LOW,
			RenderingServer.ENV_SSAO_QUALITY_MEDIUM, RenderingServer.ENV_SSAO_QUALITY_HIGH][q],
			true, 0.5, 2, 50, 300)


## Sun/moon shadow setup for this quality.
static func apply_directional(light: DirectionalLight3D, sun: bool) -> void:
	var q := int(Settings.get_value("graphics", "quality"))
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q <= Settings.Quality.MEDIUM else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	light.directional_shadow_max_distance = ([40.0, 60.0, 100.0, 140.0][q]) * (1.0 if sun else 0.7)
	light.directional_shadow_blend_splits = q >= Settings.Quality.HIGH


## How far (m) chunk meshes still cast shadows.
static func shadow_caster_distance() -> float:
	return [32.0, 48.0, 80.0, 120.0][int(Settings.get_value("graphics", "quality"))]


## Shadow-casting budget for point lights at this quality.
static func point_shadows_allowed() -> int:
	return [0, 2, 4, 8][int(Settings.get_value("graphics", "quality"))]
