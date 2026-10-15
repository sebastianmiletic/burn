extends Node3D
## Standalone flora test: smooth noise terrain in 16 m chunks, planned on worker threads with
## Flora.plan_chunk and built with Flora.build_chunk exactly as the chunk mesher does, a body
## walking through the grass (FoliageInteraction), wind, ambient life, a felled tree.
##
##   godot --path . res://world/flora/test/flora_test.tscn                    (interactive, 1-9 shots, F fell, W wind)
##   godot --path . --fullscreen res://world/flora/test/flora_test.tscn -- --capture=/abs/dir [--styles=0,4] [--quality=1] [--only=road,meadow]
##   godot --path . --fullscreen res://world/flora/test/flora_test.tscn -- --bench   (GPU timings)

const Terrain := preload("res://world/flora/test/flora_terrain.gd")
const CHUNKS := 9            # 144 m square overworld
const HELL_OFFSET := Vector3i(400, 0, 0)

const BLOCK_COLORS := {
	3: Color(0.26, 0.27, 0.1), 2: Color(0.3, 0.22, 0.14), 34: Color(0.45, 0.38, 0.2), 38: Color(0.16, 0.13, 0.09),
	5: Color(0.85, 0.87, 0.9), 4: Color(0.7, 0.62, 0.45), 22: Color(0.2, 0.18, 0.17), 1: Color(0.38, 0.37, 0.35),
	39: Color(0.24, 0.18, 0.15), 12: Color(0.42, 0.4, 0.38),
}

## name, camera position, look target, extra (time to wait / special)
var SHOTS := [
	["road", Vector3(-1, 0, 16), Vector3(-1, 0, 60), 1.6],
	["meadow", Vector3(30, 0, 98), Vector3(48, 0, 84), 1.7],
	["trample", Vector3(95, 0, 70), Vector3(100, 0, 78), 1.7],
	["flowers", Vector3(36, 0, 62), Vector3(44, 0, 72), 1.2],
	["forest", Vector3(70, 0, 52), Vector3(80, 0, 40), 1.7],
	["pines", Vector3(64, 0, 112), Vector3(70, 0, 132), 1.7],
	["deadwood", Vector3(110, 0, 18), Vector3(122, 0, 8), 1.7],
	["marsh", Vector3(14, 0, 28), Vector3(8, 0, 12), 1.4],
	["vista", Vector3(40, 0, 70), Vector3(90, 0, 40), 14.0],
	["fell", Vector3(56, 0, 34), Vector3(64, 0, 44), 1.05],
	["fell_burst", Vector3(56, 0, 34), Vector3(64, 0, 44), 0.75],
	["hell", Vector3(408, 0, 4), Vector3(416, 0, 16), 1.7],
]

var camera: Camera3D
var view: AsciiView
var terrain := Terrain.new(7)
var hell_terrain := Terrain.new(19)
var interaction: FoliageInteraction
var ambient: Node3D
var walker: Node3D
var sun: DirectionalLight3D
var env: Environment
var _capture_dir := ""
var _bench := false
var _styles := [0, 4]
var _only: PackedStringArray = []
var _walk_t := 0.0
var _walk_path: Curve3D
var _trees: Array = []     # [world root, kind, height, seed]
var _flora_nodes: Array[Node3D] = []
var _plan_ms: Array[float] = []
var _snow := false
var _wind := 0.45
var _restore: Array = []


func _ready() -> void:
	# Settings persist to user://; put the user's own values back when a scripted run ends.
	_restore = [Settings.get_value("graphics", "style"), Settings.get_value("graphics", "quality")]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_capture_dir = arg.trim_prefix("--capture=")
		elif arg.begins_with("--styles="):
			_styles = Array(arg.trim_prefix("--styles=").split(",")).map(func(s: String) -> int: return int(s))
		elif arg.begins_with("--quality="):
			Settings.set_value("graphics", "quality", int(arg.trim_prefix("--quality=")))
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",")
		elif arg == "--bench":
			_bench = true
		elif arg == "--snow":
			_snow = true
	RenderingServer.global_shader_parameter_set(&"wind_dir", Vector2(0.8, 0.6).normalized())
	RenderingServer.global_shader_parameter_set(&"wind_strength", 0.45)
	RenderingServer.global_shader_parameter_set(&"wetness", 0.0)
	RenderingServer.global_shader_parameter_set(&"snow_cover", 0.0)
	terrain.region_fn = _region
	hell_terrain.region_fn = func(x: float, z: float) -> int: return 39 if hell_terrain.noise.get_noise_2d(x * 3.0, z * 3.0) > 0.1 else 22
	_environment()
	var t0 := Time.get_ticks_msec()
	Flora.warmup()
	print("[flora_test] warmup %.0f ms (Flora.warmup_ms %.0f)" % [Time.get_ticks_msec() - t0, Flora.warmup_ms])
	_place_trees()
	_build_world()
	_make_walker()
	interaction = FoliageInteraction.new()
	add_child(interaction)
	interaction.track(walker, 0.75)
	ambient = AmbientLife.new()
	ambient.wind = _wind
	ambient.wetness = 0.0
	add_child(ambient)
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.near = 0.05
	camera.far = 600.0
	add_child(camera)
	view = AsciiView.new()
	view.source_camera = camera
	add_child(view)
	_set_shot(0)
	if _capture_dir != "":
		DirAccess.make_dir_recursive_absolute(_capture_dir)
		_capture.call_deferred()
	elif _bench:
		_run_bench.call_deferred()


# ------------------------------------------------------------------ world

func _region(x: float, z: float) -> int:
	var n := terrain.noise.get_noise_2d(x * 2.3 + 50.0, z * 2.3) * 6.0
	# Dirt road winding north through the middle.
	var road_x := 64.0 + sin(z * 0.045) * 6.0
	if absf(x - road_x) < 2.2 + n * 0.15:
		return 2
	if z > 112.0 + n:
		return 5 if terrain.height(x, z) > 2.0 + n * 0.3 else 1
	if x < 30.0 and z < 40.0:
		return 38   # marsh
	if x > 100.0 and z < 36.0:
		return 22   # burnt ash with dead trees
	if x > 92.0 and z > 48.0 and z < 100.0:
		return 34   # dry grass field
	if x > 74.0 and x < 84.0 and z > 100.0 and z < 112.0:
		return 1    # stone outcrop
	return 3


func _place_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var seed_n := 0
	# Autumn avenue: oaks and crimsons lining the road.
	for i in 22:
		var z := 14.0 + i * 4.6 + rng.randf_range(-1.0, 1.0)
		if z > 106.0:
			break
		for side in [-1.0, 1.0]:
			var x: float = 64.0 + sin(z * 0.045) * 6.0 + side * rng.randf_range(4.2, 6.5)
			var kind := Flora.OAK if rng.randf() < 0.72 else Flora.CRIMSON
			_trees.append([Vector3(x, terrain.height(x, z), z), kind, rng.randf_range(7.5, 11.5), seed_n])
			seed_n += 1
	# Small forest east of the road.
	for i in 30:
		var x := rng.randf_range(74.0, 92.0)
		var z := rng.randf_range(26.0, 56.0)
		_trees.append([Vector3(x, terrain.height(x, z), z), Flora.OAK if rng.randf() < 0.6 else Flora.CRIMSON, rng.randf_range(6.0, 12.0), seed_n])
		seed_n += 1
	# Pines in the snowy north.
	for i in 26:
		var x := rng.randf_range(40.0, 120.0)
		var z := rng.randf_range(118.0, 142.0)
		_trees.append([Vector3(x, terrain.height(x, z), z), Flora.PINE, rng.randf_range(8.0, 12.0), seed_n])
		seed_n += 1
	# Dead trees on the ash.
	for i in 9:
		var x := rng.randf_range(104.0, 140.0)
		var z := rng.randf_range(2.0, 34.0)
		_trees.append([Vector3(x, terrain.height(x, z), z), Flora.DEAD, rng.randf_range(5.0, 9.0), seed_n])
		seed_n += 1
	# Marsh: a few crimsons.
	for i in 4:
		var x := rng.randf_range(4.0, 26.0)
		var z := rng.randf_range(4.0, 36.0)
		_trees.append([Vector3(x, terrain.height(x, z), z), Flora.CRIMSON, rng.randf_range(6.0, 9.0), seed_n])
		seed_n += 1


func _ground_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"
global uniform float wetness;
varying vec3 v_wp;
void vertex() { v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float n = n_fbm2(v_wp.xz * 0.9);
	float m = n_fbm2(v_wp.xz * 0.12 + 7.0);
	vec3 c = COLOR.rgb * (0.75 + n * 0.5) * (0.85 + m * 0.3);
	ALBEDO = c * (1.0 - wetness * 0.4);
	ROUGHNESS = ascii_roughness(mix(0.92, 0.3, wetness), ASCII_GROUND);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func _build_world() -> void:
	var mat := _ground_material()
	var jobs: Array = []
	for cz in CHUNKS:
		for cx in CHUNKS:
			jobs.append([terrain, cx, cz, 0, Vector3i.ZERO])
	for cz in 2:
		for cx in 2:
			jobs.append([hell_terrain, cx, cz, 1, HELL_OFFSET])
	# Plan every chunk on the WorkerThreadPool, like the real mesher.
	var plans: Array = []
	plans.resize(jobs.size())
	var inputs: Array = []
	for j: Array in jobs:
		var terr: RefCounted = j[0]
		var cx: int = j[1]
		var cz: int = j[2]
		var origin := Vector3i(cx * 16, 0, cz * 16) + (j[4] as Vector3i)
		var surf: Dictionary = terr.surface(cx, cz, 0)
		var trees: Array = []
		if j[3] == 0:
			for t: Array in _trees:
				var p: Vector3 = t[0]
				if int(floor(p.x / 16.0)) == cx and int(floor(p.z / 16.0)) == cz:
					trees.append([p - Vector3(origin), t[1], t[2], t[3]])
		inputs.append([origin, surf, trees, j[3]])
	var t0 := Time.get_ticks_usec()
	var task := WorkerThreadPool.add_group_task(func(i: int) -> void:
		var inp: Array = inputs[i]
		var ts := Time.get_ticks_usec()
		plans[i] = Flora.plan_chunk(inp[0], inp[1], inp[2], inp[3], 1234)
		plans[i]["ms"] = (Time.get_ticks_usec() - ts) / 1000.0, jobs.size())
	WorkerThreadPool.wait_for_group_task_completion(task)
	var wall := (Time.get_ticks_usec() - t0) / 1000.0
	var build_total := 0.0
	var build_max := 0.0
	var inst_total := 0
	for i in jobs.size():
		var j: Array = jobs[i]
		var terr: RefCounted = j[0]
		var origin: Vector3i = inputs[i][0]
		var chunk := MeshInstance3D.new()
		chunk.mesh = terr.ground_mesh(j[1], j[2], 0, BLOCK_COLORS)
		chunk.material_override = mat
		chunk.position = Vector3(origin)
		add_child(chunk)
		var tb := Time.get_ticks_usec()
		var node := Flora.build_chunk(plans[i], int(Settings.get_value("graphics", "quality")))
		chunk.add_child(node)
		var ms := (Time.get_ticks_usec() - tb) / 1000.0
		build_total += ms
		build_max = maxf(build_max, ms)
		_flora_nodes.append(node)
		_plan_ms.append(plans[i].ms)
		for g: Dictionary in plans[i].groups:
			inst_total += int(g.count)
	_plan_ms.sort()
	print("[flora_test] %d chunks planned on worker threads in %.1f ms wall; plan_chunk median %.2f ms, max %.2f ms" % [
			jobs.size(), wall, _plan_ms[_plan_ms.size() / 2], _plan_ms[-1]])
	print("[flora_test] build_chunk avg %.3f ms, max %.3f ms; %d ground instances (%.0f per chunk)" % [
			build_total / jobs.size(), build_max, inst_total, float(inst_total) / jobs.size()])


func _make_walker() -> void:
	# The tracked node sits at the feet (as entity positions do); the capsule body is a child.
	walker = Node3D.new()
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.75
	body.mesh = cap
	body.position.y = 0.875
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.22, 0.3)
	body.material_override = m
	walker.add_child(body)
	add_child(walker)
	_walk_path = Curve3D.new()
	for p in [Vector3(90, 0, 66), Vector3(98, 0, 74), Vector3(104, 0, 80), Vector3(100, 0, 88), Vector3(92, 0, 80), Vector3(90, 0, 66)]:
		_walk_path.add_point(p)


func _process(delta: float) -> void:
	_walk_t += delta * 1.6
	var length := _walk_path.get_baked_length()
	var p := _walk_path.sample_baked(fmod(_walk_t, length))
	p.y = terrain.height(p.x, p.z)
	walker.global_position = p


func _environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.42, 0.6)
	sky_mat.sky_horizon_color = Color(0.85, 0.7, 0.55)
	sky_mat.ground_bottom_color = Color(0.12, 0.1, 0.08)
	sky_mat.ground_horizon_color = Color(0.6, 0.48, 0.36)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.65, 0.55)
	env.fog_density = 0.0012
	env.fog_aerial_perspective = 0.3
	env.fog_sky_affect = 0.5
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(0.9, 0.8, 0.7)
	GraphicsQuality.apply_environment(env)
	print("[flora_test] quality %d" % int(Settings.get_value("graphics", "quality")))
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-24.0), deg_to_rad(-150.0), 0)
	sun.light_color = Color(1.0, 0.82, 0.6)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	GraphicsQuality.apply_directional(sun, true)
	add_child(sun)


# ------------------------------------------------------------------ shots

func _set_shot(i: int) -> void:
	var s: Array = SHOTS[clampi(i, 0, SHOTS.size() - 1)]
	if s[0] == "fell_burst":
		return
	var t: RefCounted = hell_terrain if s[0] == "hell" else terrain
	var off := Vector3(HELL_OFFSET) if s[0] == "hell" else Vector3.ZERO
	var cp: Vector3 = s[1]
	var tp: Vector3 = s[2]
	if s[0] == "road":
		# Stand on the road, looking along it.
		cp.x = 64.0 + sin(cp.z * 0.045) * 6.0
		tp.x = 64.0 + sin(tp.z * 0.045) * 6.0
	cp.y = t.height(cp.x - off.x, cp.z - off.z) + (1.7 if s[0] != "vista" else 9.0)
	tp.y = t.height(tp.x - off.x, tp.z - off.z) + (1.2 if s[0] != "vista" else 2.0)
	if s[0] == "trample" or s[0] == "flowers":
		cp.y += 0.6
		tp.y -= 0.8
	camera.global_position = cp
	camera.look_at(tp, Vector3.UP)
	ambient.set(&"time_of_day", 20.3 if s[0] == "marsh" else 15.5)
	ambient.set(&"dimension", 1 if s[0] == "hell" else 0)
	if s[0] == "hell":
		ambient.set(&"ground_height", func(x: float, z: float) -> float: return hell_terrain.height(x - HELL_OFFSET.x, z - HELL_OFFSET.z))
	else:
		ambient.set(&"ground_height", terrain.height)
	if s[0] == "hell":
		env.fog_light_color = Color(0.5, 0.2, 0.15)
		sun.light_color = Color(1.0, 0.45, 0.3)
		sun.light_energy = 0.8
	else:
		env.fog_light_color = Color(0.75, 0.65, 0.55)
		sun.light_color = Color(1.0, 0.82, 0.6)
		sun.light_energy = 1.6
	if s[0] == "marsh":
		sun.light_energy = 0.35
		sun.light_color = Color(0.9, 0.5, 0.35)


func _fell_one() -> void:
	# A tree that is not part of the planned chunks (in the game the chopped tree's chunk is
	# re-meshed without it): 9 m in front of the camera, falling across the view.
	var fwd := -camera.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var root := camera.global_position + fwd * 9.0
	root.y = terrain.height(root.x, root.z)
	var dir := fwd.cross(Vector3.UP).normalized()
	Flora.fell(self, root, Flora.OAK, 9.5, 7, dir)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	if k.keycode >= KEY_1 and k.keycode <= KEY_9:
		_set_shot(k.keycode - KEY_1)
	elif k.keycode == KEY_0:
		_set_shot(9)
	elif k.keycode == KEY_F:
		_fell_one()
	elif k.keycode == KEY_W:
		_wind = fmod(_wind + 0.3, 1.2)
		RenderingServer.global_shader_parameter_set(&"wind_strength", _wind)
		ambient.set(&"wind", _wind)


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		t += get_process_delta_time()
		await get_tree().process_frame


func _capture() -> void:
	await _wait(1.5)
	for style: int in _styles:
		Settings.set_value("graphics", "style", style)
		for i in SHOTS.size():
			var s: Array = SHOTS[i]
			if not _only.is_empty() and not (s[0] in _only):
				continue
			_set_shot(i)
			if s[0] == "fell":
				_fell_one()
			if _snow:
				RenderingServer.global_shader_parameter_set(&"snow_cover", 0.8 if s[0] == "pines" else 0.0)
			await _wait(s[3])
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var path := _capture_dir.path_join("s%d_%02d_%s.png" % [style, i, s[0]])
			img.save_png(path)
			printerr("[flora_test] saved ", path)
	_quit()


# ------------------------------------------------------------------ bench

## Mean frame time (ms) with vsync off - the scene is GPU-bound, so differences between layer
## toggles are the GPU cost of the toggled layers. (Metal reports no GPU timestamps here.)
## Returns (mean frame ms, mean render-thread CPU ms).
func _gpu_ms(frames: int) -> Vector2:
	var vp := view.viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in 10:
		await get_tree().process_frame
	var cpu := 0.0
	var samples: Array[float] = []
	var last := Time.get_ticks_usec()
	for i in frames:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		samples.append((now - last) / 1000.0)
		last = now
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
	samples.sort()
	# Median: robust against hitches from other processes.
	return Vector2(samples[samples.size() / 2], cpu / frames)


func _set_layers(grass: bool, plants: bool, trees: bool) -> void:
	for n in _flora_nodes:
		for c in n.get_children():
			var mmi := c as MultiMeshInstance3D
			var mesh := mmi.multimesh.mesh
			var is_tree := mesh.get_surface_count() == 2 and mmi.multimesh.instance_count < 64 and _is_tree_mesh(mesh)
			if is_tree:
				mmi.visible = trees
			elif _is_grass_mesh(mesh):
				mmi.visible = grass
			else:
				mmi.visible = plants


func _is_tree_mesh(m: Mesh) -> bool:
	for kind in 4:
		for v in Flora.VARIANTS:
			for lod in 3:
				if Flora.tree_mesh(kind, v, lod) == m:
					return true
	return false


func _is_grass_mesh(m: Mesh) -> bool:
	var mat := m.surface_get_material(0) as ShaderMaterial
	return mat != null and mat.shader.resource_path.ends_with("flora_grass.gdshader")


func _run_bench() -> void:
	Settings.set_value("graphics", "style", 0)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await _wait(1.0)
	var report := PackedStringArray()
	report.append("quality %d, window %s, 3D viewport %s" % [int(Settings.get_value("graphics", "quality")), str(DisplayServer.window_get_size()), str(view.viewport.size)])
	for shot in ["meadow", "road", "vista", "forest"]:
		var idx := -1
		for i in SHOTS.size():
			if SHOTS[i][0] == shot:
				idx = i
		_set_shot(idx)
		_set_layers(true, true, true)
		var all := await _gpu_ms(90)
		_set_layers(false, true, true)
		var no_grass := await _gpu_ms(90)
		_set_layers(false, false, true)
		var no_plants := await _gpu_ms(90)
		_set_layers(false, false, false)
		var none := await _gpu_ms(90)
		_set_layers(true, true, true)
		report.append("%-7s frame %.2f ms | grass %.2f ms | plants/rocks/bushes %.2f ms | trees %.2f ms | rest %.2f ms (render-thread cpu %.2f ms)" % [
				shot, all.x, all.x - no_grass.x, no_grass.x - no_plants.x, no_plants.x - none.x, none.x, all.y])
	for line in report:
		print("[flora_bench] ", line)
	_quit()


func _quit() -> void:
	Settings.set_value("graphics", "style", _restore[0])
	Settings.set_value("graphics", "quality", _restore[1])
	get_tree().quit()
