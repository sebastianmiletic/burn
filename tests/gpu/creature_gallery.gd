extends Node3D
## Visual check for the creatures, mobs, wildlife and lair dressing, rendered
## through the ASCII view (companion to model_gallery.tscn, which shows the
## characters).
##
##   godot --path . --fullscreen res://tests/gpu/creature_gallery.tscn -- --capture=/abs/dir [--style=4] [--only=leviathan]
##
## Without --capture it is interactive: 1-9 / 0 / - jump between shots, space replays actions.

const SHOTS := [
	# name, camera position, look target, [[model, action], ...], seconds to wait
	["leviathan_rear", Vector3(26, 9, -8), Vector3(0, 7, -40), [["lev_a", "roar"]], 1.0],
	["leviathan_bite", Vector3(-22, 6, -14), Vector3(0, 4, -38), [["lev_a", "bite"]], 0.75],
	["leviathan_cruise", Vector3(180, 26, 10), Vector3(150, 0, -40), [], 0.3],
	["leviathan_slam", Vector3(330, 22, 18), Vector3(300, 4, -45), [["lev_c", "slam"]], 1.25],
	["sea", Vector3(150, 5, 92), Vector3(150, 1.5, 70), [["shark", "bite"], ["serpent", "roar"]], 0.6],
	["spiders", Vector3(450, 4.5, 5), Vector3(450, 1.5, -14), [["brood", "roar"], ["scorpion", "attack2"], ["spider", "lunge"]], 0.6],
	["canines", Vector3(600, 2.4, 4.5), Vector3(600, 0.9, -9), [["dire_wolf", "attack"], ["bear", "slam"], ["hellhound", "howl"]], 0.55],
	["prey", Vector3(750, 1.8, 4.5), Vector3(750, 0.7, -8), [], 0.3],
	["cave", Vector3(900, 3.0, 6.5), Vector3(900, 1.4, -8), [["golem", "slam"], ["elemental", "throw"], ["crawler", "bite"]], 0.6],
	["marsh", Vector3(1050, 2.6, 6), Vector3(1050, 0.8, -6), [["lurker", "lunge"]], 0.4],
	["humanoids", Vector3(1200, 2.6, 9.5), Vector3(1200, 1.4, -2), [["troll_a", "slam"], ["hag", "cast"], ["drowned", "attack"]], 0.5],
	["lair", Vector3(1350, 4.0, 12), Vector3(1350, 1.5, -6), [], 0.5],
	["flocks", Vector3(1500, 3.0, 9), Vector3(1500, 1.0, 0), [], 0.4],
	# The beast bosses (look targets "model.node" follow a part of the model).
	["dragon_idle", Vector3(1716, 6.5, -3), Vector3(1700, 4.5, -30), [], 0.6],
	["dragon_side", Vector3(1731, 5.0, -24), Vector3(1700, 4.0, -29), [], 0.3],
	["dragon_bite", Vector3(1712, 3.0, -6), "dragon.head", [["dragon", "bite"]], 0.7],
	["dragon_claw", Vector3(1716, 3.0, -8), Vector3(1700, 3.0, -30), [["dragon", "claw"]], 0.6],
	["dragon_tail", Vector3(1680, 5.0, -4), Vector3(1700, 3.0, -30), [["dragon", "tail"]], 0.8],
	["dragon_gust", Vector3(1712, 4.0, 2), Vector3(1700, 7.0, -30), [["dragon", "gust"]], 0.72],
	["dragon_roar", Vector3(1708, 3.0, -6), Vector3(1700, 7.0, -30), [["dragon", "roar"]], 0.9],
	["dragon_breath", Vector3(1734, 5.0, -18), Vector3(1700, 3.0, -22), [["dragon", "breath"]], 1.9],
	["dragon_breath_late", Vector3(1726, 3.0, -8), Vector3(1700, 3.0, -26), [["dragon", "breath"]], 2.6],
	["dragon_pov", Vector3(1694, 1.6, -13), "dragon.head", [], 0.3],
	["dragon_closeup", Vector3(1697, 1.6, -21), "dragon.head", [["dragon", "roar"]], 0.8],
	["dragon_fly", Vector3(1792, 2.0, -6), Vector3(1780, 14.0, -30), [], 0.4],
	["dragon_strafe", Vector3(1812, 4.0, -12), Vector3(1780, 6.0, -22), [["dragon_air", "breath"]], 1.0],
	["dragon_dive", Vector3(1795, 3.0, -2), Vector3(1780, 12.0, -30), [["dragon_air", "dive"]], 0.5],
	["cerberus_idle", Vector3(1893, 5.0, -10), Vector3(1880, 4.0, -30), [], 0.4],
	["cerberus_side", Vector3(1902, 4.0, -26), Vector3(1880, 3.5, -30), [], 0.3],
	["cerberus_bite", Vector3(1888, 2.6, -14), Vector3(1880, 4.0, -30), [["cerberus", "bite"]], 0.66],
	["cerberus_breath", Vector3(1904, 4.0, -18), Vector3(1878, 3.0, -24), [["cerberus", "breath"]], 1.7],
	["cerberus_howl", Vector3(1890, 3.0, -14), Vector3(1880, 6.0, -30), [["cerberus", "howl"]], 0.9],
	["cerberus_slam", Vector3(1892, 3.0, -12), Vector3(1880, 4.0, -30), [["cerberus", "slam"]], 0.65],
	["cerberus_pounce", Vector3(1897, 3.0, -16), Vector3(1880, 3.0, -30), [["cerberus", "pounce"]], 0.55],
	["cerberus_pov", Vector3(1876, 1.6, -16), "cerberus.heads", [], 0.3],
	["brood_idle", Vector3(2052, 5.0, -10), Vector3(2040, 2.0, -30), [], 0.4],
	["brood_attack", Vector3(2048, 2.5, -14), Vector3(2040, 3.0, -30), [["brood_b", "bite"]], 0.5],
	["brood_rear", Vector3(2050, 3.0, -12), Vector3(2040, 4.0, -30), [["brood_b", "roar"]], 0.8],
	["brood_pov", Vector3(2037, 1.6, -18), Vector3(2040, 3.0, -30), [], 0.3],
	["brood_stab", Vector3(2050, 3.0, -12), Vector3(2040, 3.0, -30), [["brood_b", "slam"]], 0.55],
	["brood_hang", Vector3(2108, 2.0, -8), Vector3(2100, 11.0, -30), [], 0.4],
]

## Close-ups: [model name, action to play or ""].
const PORTRAITS := [["brood", "roar"], ["spider", ""], ["scorpion", "attack2"], ["spiderling_0", ""], ["wolf", ""], ["dire_wolf", "attack"],
	["frost_wolf", ""], ["hellhound", "howl"], ["bear", "roar"], ["deer", ""], ["stag", ""], ["rabbit", ""], ["goat", ""], ["boar", ""],
	["bat", "attack"], ["crawler", "bite"], ["golem", "slam"], ["elemental", "throw"], ["lurker", "bite"], ["shark", "bite"],
	["serpent", "roar"], ["skeleton_0", ""], ["skeleton_2", ""], ["archer_0", ""], ["ghoul_0", ""], ["drowned", ""], ["hag", "cast"],
	["troll_a", ""], ["troll_b", ""], ["troll_c", ""]]

var camera: Camera3D
var _models := {}
var _capture_dir := ""
var _only := ""
var _shot := 0
var _t := 0.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_capture_dir = arg.trim_prefix("--capture=")
		elif arg.begins_with("--style="):
			Settings.set_value("graphics", "style", int(arg.trim_prefix("--style=")))
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=")
		elif arg.begins_with("--quality="):
			Settings.set_value("graphics", "quality", int(arg.trim_prefix("--quality=")))
	_environment()
	_ground()
	_place()
	camera = Camera3D.new()
	camera.fov = 60.0
	camera.near = 0.1
	camera.far = 900.0
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
	sky_mat.sky_top_color = Color(0.22, 0.25, 0.3)
	sky_mat.sky_horizon_color = Color(0.62, 0.55, 0.48)
	sky_mat.ground_bottom_color = Color(0.1, 0.08, 0.07)
	sky_mat.ground_horizon_color = Color(0.45, 0.38, 0.3)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.0
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.003
	GraphicsQuality.apply_environment(env)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(-35.0), 0)
	sun.light_color = Color(1.0, 0.85, 0.68)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	add_child(sun)


func _ground() -> void:
	var water := MeshInstance3D.new()
	var wp := PlaneMesh.new()
	wp.size = Vector2(500, 400)
	water.mesh = wp
	water.position = Vector3(140, 0, 0)
	water.material_override = CreatureSkin.smooth(Color(0.08, 0.16, 0.2), Color(0.08, 0.16, 0.2), {"roughness": 0.08,
		"specular_amount": 0.9, "rim": 0.0, "pattern": CreatureSkin.Pattern.HIDE, "pattern_scale": 0.6, "bump": 1.2, "ascii_id": AsciiMaterialId.LIQUID})
	add_child(water)
	var g := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1300, 400)
	g.mesh = plane
	g.position = Vector3(1040, 0, 0)
	g.material_override = MaterialLibrary.ground()
	add_child(g)
	var g2 := MeshInstance3D.new()
	var plane2 := PlaneMesh.new()
	plane2.size = Vector2(700, 400)
	g2.mesh = plane2
	g2.position = Vector3(1990, 0, 0)
	g2.material_override = MaterialLibrary.ground()
	add_child(g2)


func _add(model_name: String, model: CreatureModel, pos: Vector3, yaw_deg := 0.0, speed := 0.0) -> CreatureModel:
	model.position = pos
	model.rotation_degrees.y = yaw_deg
	model.lod_enabled = false
	add_child(model)
	model.move_speed = speed
	_models[model_name] = model
	return model


func _place() -> void:
	# The Leviathan: reared up, cruising in a circle, tail-slamming a platform.
	var lev_a := _add("lev_a", Models.create("leviathan"), Vector3(0, 0, -40), 200.0) as LeviathanModel
	lev_a.water_y = 0.0
	lev_a.surfaced = true
	lev_a.engaged = true
	var lev_b := _add("lev_b", Models.create("leviathan"), Vector3(150, 0, -40), 0.0) as LeviathanModel
	lev_b.water_y = 0.0
	var lev_c := _add("lev_c", Models.create("leviathan"), Vector3(300 + 23, 0, -40), 180.0) as LeviathanModel
	lev_c.water_y = 0.0
	lev_c.engaged = true
	lev_c.arena_center = Vector3(300, 0, -40)
	lev_c.platform_y = 1.0
	var platform := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 16.0
	cyl.bottom_radius = 17.0
	cyl.height = 2.0
	platform.mesh = cyl
	platform.material_override = MaterialLibrary.stone(&"ruin")
	platform.position = Vector3(300, 0.0, -40)
	add_child(platform)
	_add("shark", Models.create_mob("shark", 2), Vector3(146, 0.6, 70), 120.0, 4.0)
	var serpent := _add("serpent", Models.create("sea_serpent"), Vector3(156, 0, 64), 220.0) as LeviathanModel
	serpent.water_y = 0.0
	serpent.surfaced = true
	# Spiders.
	_add("brood", Models.create("broodmother"), Vector3(450, 0, -20), 200.0)
	_add("spider", Models.create_mob("giant_spider", 4), Vector3(443, 0, -11), 150.0, 0.0)
	_add("scorpion", Models.create_mob("scorpion", 1), Vector3(457, 0, -10), 220.0)
	for i in 3:
		_add("spiderling_%d" % i, Models.create_mob("spiderling", i), Vector3(446.5 + i * 1.4, 0, -6.5 - i * 0.6), 160.0 + i * 20.0, 3.0)
	# Canines and bears.
	var canines := ["wolf", "dire_wolf", "frost_wolf", "hellhound"]
	for i in canines.size():
		_add(canines[i], Models.create_mob(canines[i], i + 5), Vector3(596.5 + i * 2.6, 0, -8.0 - (i % 2) * 1.5), 150.0 + i * 15.0, 2.5 if i == 0 else 0.0)
	_add("bear", Models.create_mob("bear", 1), Vector3(601, 0, -15), 200.0)
	# Prey.
	var prey := [["deer", 0.0], ["stag", 1.5], ["rabbit", 0.0], ["goat", 1.0], ["boar", 0.0]]
	for i in prey.size():
		var m := _add(prey[i][0], Models.create_mob(prey[i][0], i + 3), Vector3(745.5 + i * 2.3, 0, -7.0 - (i % 2) * 1.5), 120.0 + i * 25.0, prey[i][1])
		if prey[i][0] == "deer":
			m.set("grazing", true)
	# Deep caves.
	_add("bat", Models.create_mob("cave_bat", 1), Vector3(897, 2.2, -5), 160.0, 3.0)
	_add("bat2", Models.create_mob("cave_bat", 2), Vector3(899, 3.0, -7), 200.0, 3.0)
	_add("crawler", Models.create_mob("cave_crawler", 1), Vector3(893, 0, -7), 120.0)
	_add("golem", Models.create_mob("rock_golem", 1), Vector3(901, 0, -10), 200.0)
	_add("elemental", Models.create_mob("fire_elemental", 1), Vector3(906, 0, -6), 220.0)
	# Marsh.
	_add("lurker", Models.create_mob("bog_lurker", 1), Vector3(1048, 0, -6), 150.0)
	_add("ghoul_m", Models.create_mob("ghoul", 3), Vector3(1052.5, 0, -7), 200.0, 1.5)
	# Humanoid monsters with their variants.
	var hum := [["skeleton", 0], ["skeleton", 1], ["skeleton", 2], ["archer", 0], ["ghoul", 0], ["ghoul", 1], ["drowned", 0], ["hag", 0]]
	for i in hum.size():
		var kind: String = hum[i][0]
		var m := Models.create_mob("bog_hag" if kind == "hag" else kind, int(hum[i][1]) + 11)
		_add(kind if kind in ["drowned", "hag"] else "%s_%d" % [kind, hum[i][1]], m, Vector3(1193.5 + i * 1.9, 0, -1.0), 180.0)
	for i in 3:
		_add("troll_%s" % ["a", "b", "c"][i], Models.create_mob("troll", i * 7 + 1), Vector3(1194 + i * 5.5, 0, -7.5), 185.0)
	# Lair dressing.
	var decor := [["web", Vector3(1344, 0, -8), 3.5], ["eggs", Vector3(1349, 0, -4), 1.0], ["cocoon", Vector3(1346, 0, -5), 1.0],
		["cauldron", Vector3(1353, 0, -3), 1.0], ["totem", Vector3(1357, 0, -6), 1.0], ["ribs", Vector3(1352, 0, -16), 1.0],
		["brazier", Vector3(1341, 0, -2), 1.0], ["bones", Vector3(1350, 0, 0), 1.0]]
	for i in decor.size():
		var d := LairDecor.new()
		add_child(d)
		d.position = decor[i][1]
		d.on_spawned({"decor": decor[i][0], "size": decor[i][2], "yaw": 0.3 * i, "seed": i, "tilt": 0.0})
	# Flocks.
	_add("birds", Models.create_mob("bird_flock", 1), Vector3(1497, 0, 0), 0.0)
	_add("crows", Models.create_mob("crow_flock", 2), Vector3(1503, 0, -3), 0.0)
	var gulls := _add("gulls", Models.create_mob("gull_flock", 3), Vector3(1500, 0, -6), 0.0) as FlockModel
	gulls.startled = true
	_add("bats", Models.create_mob("bat_swarm", 4), Vector3(1506, 3, -2), 0.0)
	# Beast bosses.
	var dragon := _add("dragon", Models.create("dragon"), Vector3(1700, 0, -30), 200.0) as DragonModel
	dragon.ground_y = 0.0
	var air := _add("dragon_air", Models.create("dragon"), Vector3(1780, 10, -30), 200.0) as DragonModel
	air.flying = true
	air.grounded = false
	air.ground_y = 0.0
	(_add("cerberus", Models.create("cerberus"), Vector3(1880, 0, -30), 200.0) as CerberusModel).ground_y = 0.0
	_add("brood_b", Models.create("broodmother"), Vector3(2040, 0, -30), 200.0)
	var hang := _add("brood_h", Models.create("broodmother"), Vector3(2100, 8, -30), 200.0) as BroodmotherModel
	hang.hanging = true
	hang.ceiling_y = 30.0
	hang.ground_y = 0.0


func _process(delta: float) -> void:
	_t += delta
	# The cruising Leviathans swim circles (the tail-slammer around its platform).
	for c: Array in [["lev_b", Vector3(150, 0, -40), 26.0], ["lev_c", Vector3(300, 0, -40), 23.0]]:
		var m: CreatureModel = _models.get(c[0])
		if m == null or (c[0] == "lev_c" and m.current_action() == "slam"):
			continue
		var r: float = c[2]
		var a := _t * 6.0 / r
		m.position = (c[1] as Vector3) + Vector3(cos(a) * r, 0, sin(a) * r)
		m.rotation.y = -a + PI
		m.move_speed = 6.0


func _set_shot(i: int) -> void:
	_shot = clampi(i, 0, SHOTS.size() - 1)
	var s: Array = SHOTS[_shot]
	camera.global_position = s[1]
	camera.look_at(_look_point(s[2]), Vector3.UP)


## A shot's look target: a point, or "model.node" (a part of a model, e.g. "dragon.head").
func _look_point(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	var parts := String(v).split(".")
	var m: Node = _models.get(parts[0])
	if m == null:
		return Vector3.ZERO
	var part: Variant = m.get(parts[1]) if parts.size() > 1 else m
	if part is Array and not (part as Array).is_empty():
		part = (part as Array)[(part as Array).size() / 2]
	if part is Node3D:
		return (part as Node3D).global_position
	return (m as Node3D).global_position


func _play_actions() -> void:
	for a: Array in SHOTS[_shot][3]:
		var m: CreatureModel = _models.get(a[0])
		if m != null:
			m.play(a[1])


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	if k.keycode >= KEY_1 and k.keycode <= KEY_9:
		_set_shot(k.keycode - KEY_1)
	elif k.keycode == KEY_0:
		_set_shot(9)
	elif k.keycode == KEY_MINUS:
		_set_shot(10)
	elif k.keycode == KEY_SPACE:
		_play_actions()


## --only takes a comma-separated list of shot name prefixes.
func _wanted(shot: String) -> bool:
	for prefix in _only.split(","):
		if prefix != "" and shot.begins_with(prefix):
			return true
	return false


func _capture() -> void:
	# Let the serpent chains settle and the cruising one swim a while.
	var t := 0.0
	while t < 4.0:
		t += get_process_delta_time()
		await get_tree().process_frame
	for i in SHOTS.size():
		if _only != "" and not _wanted(String(SHOTS[i][0])):
			continue
		_set_shot(i)
		_play_actions()
		var wait: float = SHOTS[i][4]
		t = 0.0
		while t < wait:
			t += get_process_delta_time()
			await get_tree().process_frame
		if not SHOTS[i][2] is Vector3:
			camera.look_at(_look_point(SHOTS[i][2]), Vector3.UP)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if _only != "":
			img.resize(img.get_width() / 2, img.get_height() / 2)
		img.save_png(_capture_dir.path_join("%02d_%s.png" % [i, SHOTS[i][0]]))
		printerr("[creatures] saved ", SHOTS[i][0])
	for i in PORTRAITS.size():
		var pname: String = PORTRAITS[i][0]
		if _only != "" and not ("portrait".begins_with(_only) or pname.begins_with(_only)):
			continue
		var m: CreatureModel = _models.get(pname)
		if m == null:
			continue
		var size := maxf(0.5, m._lod_size())
		if m is HumanoidModel:
			size = float((m as HumanoidModel).style.get("height", 1.8)) * 0.9
		var front := -m.global_transform.basis.z
		front.y = 0.0
		front = front.normalized()
		var right := front.cross(Vector3.UP)
		var focus := m.global_position + Vector3(0, size * 0.32, 0)
		camera.global_position = focus + (front * 1.7 + right * 1.1) * size + Vector3(0, size * 0.35, 0)
		camera.look_at(focus, Vector3.UP)
		if PORTRAITS[i][1] != "":
			m.play(PORTRAITS[i][1])
		t = 0.0
		while t < 0.45:
			t += get_process_delta_time()
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(img.get_width() / 2, img.get_height() / 2)
		img.save_png(_capture_dir.path_join("p%02d_%s.png" % [i, pname]))
		printerr("[creatures] portrait ", pname)
	get_tree().quit()
