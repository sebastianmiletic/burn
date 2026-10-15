extends Node3D
## Visual and performance check for the bespoke boss models, seen the way a
## player sees them: from first-person eye height (1.6 m), at fighting range
## and close up, mid-attack, brooding before the fight, in each phase, and in a
## dark arena lit only by the boss's own lights.
##
##   godot --path . res://tests/gpu/boss_gallery.tscn -- --capture=/abs/dir [--only=warden,hades]
##       [--shots=front,close,action,dormant,phase3,dark,side] [--perf] [--style=4]
##
## --perf prints the CPU cost of animating each boss (µs per frame, averaged).

const BOSSES := ["warden", "mountain_king", "hades", "bog_hag", "ryft_sentinel", "void_sovereign"]
## Actions to freeze mid-way per boss.
const ACTIONS := {
	"warden": ["sweep", "slam", "summon"],
	"mountain_king": ["slam", "throw", "roar"],
	"hades": ["sweep", "cast", "summon"],
	"bog_hag": ["cast", "attack2", "summon"],
	"ryft_sentinel": ["cast", "slam", "summon"],
	"void_sovereign": ["sweep", "cast", "summon"],
}
const HEIGHTS := {"warden": 4.6, "mountain_king": 7.0, "hades": 5.4, "bog_hag": 2.3, "ryft_sentinel": 6.4, "void_sovereign": 7.6}
const SPACING := 60.0

var camera: Camera3D
var sun: DirectionalLight3D
var env: Environment
var _models := {}
var _capture_dir := ""
var _only := PackedStringArray()
var _shots := PackedStringArray(["front", "close", "action", "dormant", "phase3", "dark", "side"])
var _perf := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_capture_dir = arg.trim_prefix("--capture=")
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",")
		elif arg.begins_with("--shots="):
			_shots = arg.trim_prefix("--shots=").split(",")
		elif arg == "--perf":
			_perf = true
		elif arg.begins_with("--style="):
			Settings.set_value("graphics", "style", int(arg.trim_prefix("--style=")))
	_environment()
	_ground()
	for i in BOSSES.size():
		var kind: String = BOSSES[i]
		if not _only.is_empty() and not _only.has(kind):
			continue
		var m := Models.create(kind)
		if m == null:
			push_error("boss gallery: no model for %s" % kind)
			continue
		m.position = Vector3(i * SPACING, 0, 0)
		m.rotation_degrees.y = 0.0
		add_child(m)
		m.lod_enabled = false
		if m.has_method("set_boss_state"):
			m.call("set_boss_state", true, 1, false)
		_models[kind] = m
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = 800.0
	add_child(camera)
	var view := AsciiView.new()
	view.source_camera = camera
	add_child(view)
	camera.global_position = Vector3(0, 1.6, -12)
	camera.look_at(Vector3(0, 2.5, 0))
	if _models.is_empty():
		push_error("boss gallery: nothing to show")
		get_tree().quit(1)
		return
	if _capture_dir != "" or _perf:
		if _capture_dir != "":
			DirAccess.make_dir_recursive_absolute(_capture_dir)
		_run.call_deferred()


func _environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.3, 0.38)
	sky_mat.sky_horizon_color = Color(0.6, 0.58, 0.55)
	sky_mat.ground_bottom_color = Color(0.1, 0.09, 0.08)
	sky_mat.ground_horizon_color = Color(0.4, 0.37, 0.33)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.0
	env.ssao_enabled = true
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.004
	GraphicsQuality.apply_environment(env)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(-140.0), 0)
	sun.light_color = Color(1.0, 0.9, 0.78)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)


func _ground() -> void:
	var g := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(BOSSES.size() * SPACING + 200.0, 300)
	g.mesh = plane
	g.position = Vector3(BOSSES.size() * SPACING * 0.5 - SPACING * 0.5, 0, 0)
	g.material_override = MaterialLibrary.ground()
	add_child(g)


## Lighting presets: day (sun + sky) or a dark arena (dim ambient, no sun).
func _lighting(dark: bool) -> void:
	sun.visible = not dark
	env.ambient_light_energy = 0.12 if dark else 0.7
	env.background_energy_multiplier = 0.08 if dark else 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED if dark else Environment.REFLECTION_SOURCE_SKY


func _frame(kind: String, eye: Vector3, look: Vector3) -> void:
	var m: Node3D = _models[kind]
	camera.global_position = m.global_position + eye
	camera.look_at(m.global_position + look, Vector3.UP)


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		t += get_process_delta_time()
		await get_tree().process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(img.get_width() / 2, img.get_height() / 2)
	img.save_png(_capture_dir.path_join("%s.png" % name))
	printerr("[bosses] saved ", name)


func _run() -> void:
	await _wait(2.0)
	if _perf:
		await _measure()
		if _capture_dir == "":
			get_tree().quit()
			return
	for kind: String in _models:
		var m: CreatureModel = _models[kind]
		var h: float = HEIGHTS.get(kind, 4.0)
		var front := Vector3(0, 0, -1)   # models face -Z
		if _shots.has("front"):
			_lighting(false)
			_frame(kind, Vector3(2.0, 1.6, -maxf(9.0, h * 2.3)), Vector3(0, h * 0.55, 0))
			await _wait(0.4)
			await _save("%s_front" % kind)
		if _shots.has("close"):
			_frame(kind, Vector3(-1.2, 1.6, -maxf(3.0, h * 0.75)), Vector3(0, h * 0.72, 0))
			await _wait(0.3)
			await _save("%s_close" % kind)
		if _shots.has("side"):
			_frame(kind, Vector3(h * 1.6, h * 0.45, -h * 0.6), Vector3(0, h * 0.5, 0))
			await _wait(0.3)
			await _save("%s_side" % kind)
		if _shots.has("action"):
			_frame(kind, Vector3(3.0, 1.6, -maxf(9.0, h * 2.1)), Vector3(0, h * 0.55, 0))
			for act: String in ACTIONS.get(kind, []):
				m.play(act)
				var dur := float(m.durations.get(act, 1.0))
				await _wait(dur * 0.42)
				await _save("%s_act_%s" % [kind, act])
				await _wait(dur * 0.7)
		if _shots.has("dormant") and m.has_method("set_boss_state"):
			m.call("set_boss_state", false, 1, false)
			_frame(kind, Vector3(2.5, 1.6, -maxf(8.0, h * 1.9)), Vector3(0, h * 0.4, 0))
			await _wait(2.2)
			await _save("%s_dormant" % kind)
			m.call("set_boss_state", true, 1, false)
			await _wait(1.0)
		if _shots.has("phase3") and m.has_method("set_boss_state"):
			m.call("set_boss_state", true, 2, false)
			await _wait(0.2)
			m.call("set_boss_state", true, 3, false)
			_frame(kind, Vector3(-2.0, 1.6, -maxf(9.0, h * 2.2)), Vector3(0, h * 0.55, 0))
			m.play("roar")
			await _wait(1.6)
			await _save("%s_phase3" % kind)
		if _shots.has("dark"):
			_lighting(true)
			_frame(kind, Vector3(1.5, 1.6, -maxf(9.0, h * 2.2)), Vector3(0, h * 0.55, 0))
			await _wait(0.5)
			await _save("%s_dark" % kind)
			_lighting(false)
		var _u := front
	get_tree().quit()


## CPU cost of animating each boss model: drive _process directly.
func _measure() -> void:
	var cam_pos := camera.global_position
	for kind: String in _models:
		var m: CreatureModel = _models[kind]
		_frame(kind, Vector3(2.0, 1.6, -10.0), Vector3(0, 2.5, 0))
		m.move_speed = 2.0
		if m is HumanoidModel:
			(m as HumanoidModel).velocity = Vector3(0, 0, -2.0)
		await _wait(0.3)
		var frames := 240
		var t0 := Time.get_ticks_usec()
		for i in frames:
			if i % 60 == 0:
				m.play("sweep" if i % 120 == 0 else "slam")
			m._process(1.0 / 60.0)
		var us := float(Time.get_ticks_usec() - t0) / frames
		var tris := 0
		var draws := 0
		for mi: Node in m.find_children("*", "MeshInstance3D", true, false):
			var mesh := (mi as MeshInstance3D).mesh
			if mesh == null or not (mi as MeshInstance3D).visible:
				continue
			draws += mesh.get_surface_count()
			for s in mesh.get_surface_count():
				var arr := mesh.surface_get_arrays(s)
				var idx: Variant = arr[Mesh.ARRAY_INDEX]
				tris += (idx as PackedInt32Array).size() / 3 if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		printerr("[bosses] perf %-15s %6.0f us/frame animate  %d mesh draws  %d triangles" % [kind, us, draws, tris])
		m.move_speed = 0.0
		if m is HumanoidModel:
			(m as HumanoidModel).velocity = Vector3.ZERO
	camera.global_position = cam_pos
