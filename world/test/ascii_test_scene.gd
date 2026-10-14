extends Node3D
## Milestone 1 renderer test: a rain-soaked ruined courtyard at night.
## Lit stone (solid glyphs), flagstones (ground), grass (foliage strokes),
## puddles (liquid), rain (streaks), torches and an orbiting fireball (FX
## layer + glow over the glyphs), and a rotating relic with an emissive core.

const CAPTURE := preload("res://tests/gpu/capture_driver.gd")

var camera: OrbitCamera
var rain: RainCurtain
var environment: Environment


func _ready() -> void:
	_build_environment()
	_build_lights()
	_build_ground()
	_build_ruins()
	_build_props()

	camera = OrbitCamera.new()
	camera.fov = 62.0
	camera.near = 0.05
	camera.far = 400.0
	camera.compositor = Ascii.make_compositor()
	camera.attributes = _camera_attributes()
	add_child(camera)

	rain = RainCurtain.new()
	add_child(rain)

	var overlay := AsciiDebugOverlay.new()
	overlay.rain_toggled.connect(func(on: bool) -> void: rain.emitting = on; rain.visible = on)
	overlay.orbit_toggled.connect(func(on: bool) -> void: camera.auto_orbit = on)
	add_child(overlay)
	add_child(PerfOverlay.new())

	_apply_disable_flags()
	if CAPTURE.requested():
		add_child(CAPTURE.new())


## Profiling aid: --disable=sdfgi,ssil,ssr,ssao,fog,glow,grass,rain,ascii,shadows,fx
func _apply_disable_flags() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--disable="):
			continue
		for feature in arg.trim_prefix("--disable=").split(","):
			match feature:
				"sdfgi": environment.sdfgi_enabled = false
				"ssil": environment.ssil_enabled = false
				"ssr": environment.ssr_enabled = false
				"ssao": environment.ssao_enabled = false
				"fog": environment.volumetric_fog_enabled = false
				"glow": environment.glow_enabled = false
				"ascii": Ascii.set_enabled(false)
				"sky": environment.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
				"skybg":
					environment.background_mode = Environment.BG_COLOR
					environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
					environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
				"materials":
					for node in find_children("*", "MeshInstance3D", true, false):
						(node as MeshInstance3D).material_override = StandardMaterial3D.new()
				"rain":
					rain.emitting = false
					rain.visible = false
				"grass", "shadows", "fx":
					for node in find_children("*", "", true, false):
						if feature == "grass" and node is GrassPatch:
							node.visible = false
						elif feature == "shadows" and node is Light3D:
							(node as Light3D).shadow_enabled = false
						elif feature == "fx" and node is GPUParticles3D and not node is RainCurtain:
							node.visible = false


func _process(_delta: float) -> void:
	if rain != null and camera != null:
		Ascii.effect.wind_slant = rain.screen_slant(camera)


func _build_environment() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://world/sky/night_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	# Incremental: radiance is refreshed over several frames. REALTIME redraws
	# the whole radiance cubemap every frame and cost ~40 ms here.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.6
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.0

	environment.ssao_enabled = true
	environment.ssao_radius = 1.2
	environment.ssao_intensity = 2.5
	environment.ssil_enabled = true
	environment.ssr_enabled = true
	environment.ssr_max_steps = 48
	environment.ssr_fade_in = 0.1

	environment.sdfgi_enabled = true
	environment.sdfgi_use_occlusion = true
	environment.sdfgi_cascades = 4
	environment.sdfgi_min_cell_size = 0.2
	environment.sdfgi_energy = 0.9

	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.035
	environment.volumetric_fog_albedo = Color(0.75, 0.78, 0.85)
	environment.volumetric_fog_emission = Color(0.004, 0.005, 0.008)
	environment.volumetric_fog_anisotropy = 0.45
	environment.volumetric_fog_length = 70.0
	environment.volumetric_fog_ambient_inject = 0.3

	environment.glow_enabled = true
	environment.glow_intensity = 0.9
	environment.glow_strength = 1.1
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for i in 7:
		environment.set_glow_level(i, i >= 1 and i <= 5)

	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)


func _camera_attributes() -> CameraAttributesPractical:
	var attr := CameraAttributesPractical.new()
	attr.auto_exposure_enabled = true
	attr.auto_exposure_scale = 0.45
	attr.auto_exposure_speed = 0.8
	attr.auto_exposure_min_sensitivity = 100.0
	attr.auto_exposure_max_sensitivity = 400.0
	return attr


func _build_lights() -> void:
	var moon := DirectionalLight3D.new()
	moon.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(-140.0), 0.0)
	moon.light_color = Color(0.58, 0.66, 0.92)
	moon.light_energy = 0.32
	moon.shadow_enabled = true
	moon.shadow_blur = 1.5
	moon.directional_shadow_max_distance = 80.0
	moon.light_volumetric_fog_energy = 0.6
	add_child(moon)


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 160)
	ground.mesh = plane
	ground.material_override = MaterialLibrary.ground()
	add_child(ground)

	# Puddles in the flagstone hollows.
	for p: Vector3 in [Vector3(3.2, 0, 4.5), Vector3(-4.6, 0, 1.5), Vector3(1.0, 0, -5.0), Vector3(-2.0, 0, 6.5)]:
		var puddle := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 1.0 + fmod(p.x * 7.13, 0.8)
		disc.bottom_radius = disc.top_radius
		disc.height = 0.01
		disc.radial_segments = 24
		puddle.mesh = disc
		puddle.position = p + Vector3(0, 0.006, 0)
		puddle.scale = Vector3(1.4, 1.0, 0.8)
		puddle.rotation.y = p.z
		puddle.material_override = MaterialLibrary.puddle()
		puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(puddle)

	var grass := GrassPatch.new()
	grass.area = Rect2(-26, -26, 52, 52)
	grass.count = 60000
	grass.holes = [Vector3(0, 0, 9.5), Vector3(0, -13, 4.0)]
	add_child(grass)


func _build_ruins() -> void:
	# A ring of pillars around the relic; some have fallen.
	for i in 8:
		var a := TAU * float(i) / 8.0 + 0.2
		var broken := i in [2, 5, 6]
		var pillar := RuinsKit.pillar(5.5, 0.42, broken, 100 + i)
		pillar.position = Vector3(cos(a) * 7.5, 0, sin(a) * 7.5)
		add_child(pillar)

	var arch := RuinsKit.arch(5.0, 6.2, 1.2, 4)
	arch.position = Vector3(0, 0.9, -11.5)
	add_child(arch)
	var steps := RuinsKit.steps(3, 7.0, 0.8, 0.3)
	steps.position = Vector3(0, 0, -9.0)
	steps.rotation.y = PI
	add_child(steps)
	var landing := RuinsKit.steps(1, 7.0, 3.0, 0.9)
	landing.position = Vector3(0, 0, -10.0)
	add_child(landing)

	for spec: Array in [[Vector3(-9.5, 0, -11.5), 0.0, 8.0], [Vector3(9.5, 0, -11.5), 0.0, 8.0],
			[Vector3(-14, 0, -4), PI * 0.5, 14.0], [Vector3(14, 0, -2), PI * 0.5, 10.0]]:
		var wall := RuinsKit.wall(spec[2], 3.4, 0.9, int(spec[0].x * 13.0))
		wall.position = spec[0]
		wall.rotation.y = spec[1]
		add_child(wall)

	for spec: Array in [[Vector3(-5, 0, 3), 1.8], [Vector3(6.5, 0, -3.5), 1.5], [Vector3(-11, 0, -9), 2.5], [Vector3(10, 0, 6), 2.0]]:
		var rubble := RuinsKit.rubble(14, spec[1], int(spec[0].z * 7.0 + 50.0))
		rubble.position = spec[0]
		add_child(rubble)

	# Distant silhouettes so the horizon is not empty.
	for i in 14:
		var a := TAU * float(i) / 14.0
		var tower := RuinsKit.pillar(randf_range(8.0, 16.0), randf_range(0.8, 1.6), i % 3 == 0, 300 + i)
		tower.position = Vector3(cos(a) * randf_range(32.0, 45.0), 0, sin(a) * randf_range(32.0, 45.0))
		add_child(tower)


func _build_props() -> void:
	add_child(Relic.new())

	for x: float in [-2.9, 2.9]:
		var torch := Torch.new()
		torch.position = Vector3(x, 3.3, -10.9)
		add_child(torch)
	var standing := Torch.new()
	standing.position = Vector3(5.2, 1.4, 5.0)
	standing.light_energy = 2.2
	add_child(standing)
	var post := MeshInstance3D.new()
	var pole := CylinderMesh.new()
	pole.top_radius = 0.06
	pole.bottom_radius = 0.09
	pole.height = 1.0
	post.mesh = pole
	post.position = Vector3(5.2, 0.5, 5.0)
	post.material_override = MaterialLibrary.stone(&"iron")
	add_child(post)

	add_child(FireballOrbiter.new())
