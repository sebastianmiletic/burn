extends Node3D
## Visual check for every creature model, rendered through the ASCII view.
##
##   godot --path . --fullscreen res://tests/gpu/model_gallery.tscn -- --capture=/abs/dir [--style=0]
##
## Without --capture it is an interactive gallery: 1-8 jump between shots,
## space replays the actions.

const SHOTS := [
	# name, camera position, look target
	["humanoids", Vector3(0, 2.4, 9.5), Vector3(0, 1.1, 0)],
	["third_person", Vector3(-12.0, 2.6, 3.8), Vector3(-12.0, 1.5, -1.0)],
	["monsters", Vector3(0, 3.2, -1.8), Vector3(0, 1.8, -9.0)],
	["giants", Vector3(0, 5.0, -11.5), Vector3(0, 3.6, -24.0)],
	["dragon", Vector3(-17.0, 7.0, -42.0), Vector3(0, 3.0, -55.0)],
	["dragon_fly", Vector3(-20.0, 4.0, -38.0), Vector3(0, 7.0, -55.0)],
	["cerberus", Vector3(-9.0, 4.0, -71.0), Vector3(0, 2.2, -80.0)],
	["telegraphs", Vector3(30.0, 18.0, 0.0), Vector3(30.0, 0.0, -12.0)],
	["villagers", Vector3(0, 1.7, 21.5), Vector3(0, 1.0, 14.0)],
	["poses_move", Vector3(64.75, 1.3, 8.5), Vector3(64.75, 0.9, 0.0)],
	["poses_action", Vector3(64.75, 1.3, -11.5), Vector3(64.75, 0.9, -20.0)],
	["closeup", Vector3(-2.2, 1.65, 2.6), Vector3(-6.0, 1.45, 0.0)],
	["faces", Vector3(-3.0, 1.62, 16.6), Vector3(-3.0, 1.55, 14.0)],
	["runner_back", Vector3(-12.0, 2.0, 3.0), Vector3(-12.0, 1.2, -0.5)],
]

## Animation pose rows: [name, x offset]. Side-on, so the models face -X.
const MOVE_POSES := ["idle", "walk", "run", "sprint", "jump_up", "fall", "land"]
const ACTION_POSES := ["attack", "attack2", "dodge", "cast", "mine", "hit", "die"]

var camera: Camera3D
var _models := {}
var _capture_dir := ""
var _shot := 0
var _only := PackedStringArray()


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_capture_dir = arg.trim_prefix("--capture=")
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",")
		elif arg.begins_with("--style="):
			Settings.set_value("graphics", "style", int(arg.trim_prefix("--style=")))
	_environment()
	_ground()
	_place_models()
	camera = Camera3D.new()
	camera.fov = 60.0
	camera.near = 0.1
	camera.far = 500.0
	add_child(camera)
	var view := AsciiView.new()
	view.source_camera = camera
	add_child(view)
	_set_shot(0)
	if _capture_dir != "":
		DirAccess.make_dir_recursive_absolute(_capture_dir)
		_capture.call_deferred()


func _environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.18, 0.15)
	sky_mat.sky_horizon_color = Color(0.7, 0.45, 0.3)
	sky_mat.ground_bottom_color = Color(0.1, 0.07, 0.05)
	sky_mat.ground_horizon_color = Color(0.5, 0.33, 0.22)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.0
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.004
	env.volumetric_fog_albedo = Color(0.9, 0.75, 0.6)
	GraphicsQuality.apply_environment(env)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-32.0), deg_to_rad(-40.0), 0)
	sun.light_color = Color(1.0, 0.78, 0.55)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)


func _ground() -> void:
	var g := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	g.mesh = plane
	g.material_override = MaterialLibrary.ground()
	add_child(g)


func _add(model_name: String, model: CreatureModel, pos: Vector3, yaw_deg := 0.0) -> CreatureModel:
	model.position = pos
	model.rotation_degrees.y = yaw_deg
	add_child(model)
	_models[model_name] = model
	return model


func _place_models() -> void:
	# Row of humanoids, facing the camera (+Z), so rotate 180.
	var row := ["player_sword", "player_torch", "skeleton", "archer", "ghoul", "elder", "blacksmith", "merchant"]
	for i in row.size():
		var x := (i - (row.size() - 1) * 0.5) * 2.0
		var m: CreatureModel
		match row[i]:
			"player_sword":
				m = Models.player(0)
			"player_torch":
				m = Models.player(1)
			"elder", "blacksmith", "merchant":
				m = Models.villager(row[i], i * 31)
			_:
				m = Models.create(row[i])
		_add(row[i], m, Vector3(x, 0, 0), 180.0)
	(_models["player_sword"] as HumanoidModel).set_held("sword_ember")
	(_models["player_torch"] as HumanoidModel).set_held("pickaxe_iron")
	(_models["player_torch"] as HumanoidModel).set_offhand_light(true)
	# Third-person view of a running player (camera behind, so the model faces -Z).
	var runner := _add("runner", Models.player(0), Vector3(-12, 0, 0), 0.0) as HumanoidModel
	runner.set_held("sword_iron")
	runner.move_speed = 5.5
	# Monsters
	_add("troll", Models.create("troll"), Vector3(-4.5, 0, -9.0), 180.0)
	_add("imp", Models.create("imp"), Vector3(-1.0, 1.5, -9.0), 200.0)
	_add("shade", Models.create("shade"), Vector3(1.5, 0, -9.0), 160.0)
	_add("warden", Models.create("warden"), Vector3(5.0, 0, -9.0), 200.0)
	# Giants
	_add("mountain_king", Models.create("mountain_king"), Vector3(-4.0, 0, -24.0), 160.0)
	_add("hades", Models.create("hades"), Vector3(4.5, 0, -24.0), 200.0)
	# Dragon and Cerberus
	_add("dragon", Models.create("dragon"), Vector3(0, 0, -55.0), 120.0)
	_add("cerberus", Models.create("cerberus"), Vector3(0, 0, -80.0), 130.0)
	# Villager variety (seeded, stable).
	var roles := ["villager", "blacksmith", "merchant", "guard", "elder", "chief", "villager", "villager"]
	for i in roles.size():
		var vm := HumanoidModel.new(CharStyles.villager(roles[i], 11 + i * 37))
		_add("v%d" % i, vm, Vector3((i - 3.5) * 1.9, 0, 14.0), 180.0)
	# Animation poses, side-on (facing -X).
	for i in MOVE_POSES.size():
		var pm := Models.player(i % 2) as HumanoidModel
		_add("pose_" + MOVE_POSES[i], pm, Vector3(59.0 + i * 1.9, 0, 0), 90.0)
		pm.set_held("sword_iron" if i % 2 == 0 else "")
	for i in ACTION_POSES.size():
		var am := Models.player(i % 3) as HumanoidModel
		_add("pose_" + ACTION_POSES[i], am, Vector3(59.0 + i * 1.9, 0, -20.0), 90.0)
		am.set_held("pickaxe_iron" if ACTION_POSES[i] == "mine" else ("" if ACTION_POSES[i] == "cast" else "sword_ember"))


func _set_shot(i: int) -> void:
	_shot = clampi(i, 0, SHOTS.size() - 1)
	var s: Array = SHOTS[_shot]
	camera.global_position = s[1]
	camera.look_at(s[2], Vector3.UP)
	var dragon := _models["dragon"] as DragonModel
	dragon.flying = s[0] == "dragon_fly"
	dragon.grounded = not dragon.flying
	if s[0] == "telegraphs":
		for c: Array in [["circle", Vector3(22, 0, -8), Vector3(5, 0, 0)], ["cone", Vector3(30, 0, -4), Vector3(9, 35, 0)],
				["line", Vector3(38, 0, -2), Vector3(14, 2.5, 0)], ["ring", Vector3(30, 0, -20), Vector3(3, 7, 0)]]:
			TelegraphFx.spawn(self, c[0], c[1], Vector3(0, 0, -1), c[2], 2.0)


func _play_actions() -> void:
	(_models["player_sword"] as CreatureModel).play("attack")
	(_models["player_torch"] as CreatureModel).play("mine")
	(_models["skeleton"] as CreatureModel).play("attack2")
	(_models["archer"] as CreatureModel).play("shoot")
	(_models["ghoul"] as CreatureModel).play("lunge")
	(_models["troll"] as CreatureModel).play("slam")
	(_models["imp"] as CreatureModel).play("throw")
	(_models["shade"] as CreatureModel).play("drain")
	(_models["warden"] as CreatureModel).play("sweep")
	(_models["mountain_king"] as CreatureModel).play("roar")
	(_models["hades"] as CreatureModel).play("summon")
	(_models["dragon"] as CreatureModel).play("breath")
	(_models["cerberus"] as CreatureModel).play("howl")


## Keep the pose models in their states; fire actions so they are mid-way at capture time.
func _drive_poses(t0: float, t1: float, total: float) -> void:
	var speeds := {"idle": 0.0, "walk": 1.5, "run": 4.6, "sprint": 7.4, "jump_up": 4.6, "fall": 4.6, "land": 0.0}
	for k: String in speeds:
		var m := _models["pose_" + k] as HumanoidModel
		var v: float = speeds[k]
		m.move_speed = v
		m.velocity = m.global_transform.basis * Vector3(0, 0, -v)
		m.sprinting = k == "sprint"
		m.grounded = not (k == "jump_up" or k == "fall")
		if k == "jump_up":
			m.velocity.y = 3.5
		elif k == "fall":
			m.velocity.y = -7.0
	var at := func(when_before_end: float) -> bool:
		var when := total - when_before_end
		return t0 < when and t1 >= when
	if at.call(0.11):
		(_models["pose_land"] as HumanoidModel).on_land(16.0)
	var acts := {"attack": [0.55, 0.4], "attack2": [0.6, 0.42], "dodge": [0.55, 0.45], "cast": [0.6, 0.47], "mine": [0.5, 0.58], "hit": [0.35, 0.4]}
	for k: String in acts:
		var d: float = acts[k][0]
		var p: float = acts[k][1]
		if at.call(d * p):
			(_models["pose_" + k] as HumanoidModel).play(k, d)
	if at.call(0.9) and SHOTS[_shot][0] == "poses_action":
		(_models["pose_die"] as HumanoidModel).set_dead(true)
	for k: String in acts:
		var m := _models["pose_" + k] as HumanoidModel
		m.move_speed = 0.0
		m.velocity = Vector3.ZERO if k != "dodge" else m.global_transform.basis * Vector3(0, 0, -6.0)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	if k.keycode >= KEY_1 and k.keycode <= KEY_8:
		_set_shot(k.keycode - KEY_1)
	elif k.keycode == KEY_SPACE:
		_play_actions()


func _capture() -> void:
	for i in 60:
		await get_tree().process_frame
	for i in SHOTS.size():
		_set_shot(i)
		if not _only.is_empty() and not _only.has(SHOTS[i][0]):
			continue
		if SHOTS[i][0] in ["humanoids", "monsters", "giants", "dragon", "cerberus"]:
			_play_actions()
		# Mid-action poses read best: wait ~45 % into the actions.
		var wait := 0.5 if SHOTS[i][0] != "dragon" else 1.2
		if SHOTS[i][0] == "telegraphs":
			wait = 1.2
		if SHOTS[i][0].begins_with("poses"):
			wait = 1.6
		var t := 0.0
		while t < wait:
			var dt := get_process_delta_time()
			_drive_poses(t, t + dt, wait)
			t += dt
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(_capture_dir.path_join("%02d_%s.png" % [i, SHOTS[i][0]]))
		printerr("[gallery] saved ", SHOTS[i][0])
	get_tree().quit()
