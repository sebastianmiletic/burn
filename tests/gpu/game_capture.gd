extends Node
## In-game capture tour (development aid):
##   godot --path . --fullscreen -- --capture-game=/abs/dir [--tour=a,b,c] [--seed=N]
##       [--time=H] [--weather=clear|overcast|rain|storm|fog|snow] [--style=N] [--quality=N] [--raw]
## Visits places at different times of day, saves screenshots and frame
## timings to report.txt, then quits. --time / --weather override every stop;
## --style / --quality / --scale change the graphics settings for this run only (not saved).
## "3d gpu" (GPU time of the 3D view) needs timestamp queries: on macOS run with
## --rendering-driver vulkan (Metal reports 0). --gpu-breakdown adds the cost of
## each feature (volumetric fog, sky, SSAO, glow, fog, sun shadow, water, weather, ASCII).

var out_dir := ""

const STOPS := {
	"spawn": [&"emberfall_shrine", 10.0, 0.0],
	"ryft": [&"ryft_landing", 12.0, -1.4, Vector3(0, 2, 8), -0.1],
	"geyser": [&"emberfall", 12.0, 0.0, Vector3.ZERO, -0.1],
	"sanctuary": [&"emberfall", 12.0, 0.0, Vector3.ZERO, -0.1],
	"mine": [&"old_ember_mine", 12.0, 0.0, Vector3(0, 2, 6), -0.2],
	"village": [&"emberfall", 10.0, 0.6],
	"dusk": [&"emberfall", 18.2, 2.4],
	"night": [&"emberfall", 23.0, 1.2],
	"forest": [&"thornwick", 9.0, 1.8],
	"peaks": [&"frosthold", 11.0, 3.0],
	"hall": [&"mountain_hall", 12.0, 0.0],
	"keep": [&"dragons_keep", 16.5, 0.5],
	"crypt": [&"silent_crypt", 21.0, 2.0],
	"gates": [&"gates_of_hades", 12.0, 0.0],
	"hell": [&"asphodel", 12.0, 0.0],
	"player": [&"emberfall", 11.0, 0.4, Vector3(-50, 2, 50), -0.3],
	"dragonfight": [&"dragons_keep", 15.0, 3.14, Vector3(0, 2, 12), -0.25],
	"kingfight": [&"mountain_hall", 12.0, 0.0, Vector3(0, 0, 8), -0.2],
	"vista": [&"emberfall", 15.5, 0.0, Vector3(0, 6, 46), -0.2],
	"road": [&"emberfall", 17.0, 2.2, Vector3(60, 2, -40), -0.1],
	"woods": [&"thornwick", 16.0, 1.0, Vector3(-40, 2, 30), -0.1],
	"dawn": [&"emberfall", 6.35, -1.45, Vector3(0, 6, 46), -0.05],
	"sunset": [&"emberfall", 17.75, 1.6, Vector3(0, 6, 46), -0.05],
	"storm": [&"emberfall", 14.0, 0.6, Vector3(0, 6, 46), -0.12],
	"rain": [&"thornwick", 11.0, 1.0, Vector3(-40, 2, 30), -0.15],
	"snow": [&"frosthold", 12.0, 3.0, Vector3(0, 2, 4), -0.15],
	"lake": [&"emberfall", 10.5, 0.0, Vector3.ZERO, -0.25],
	"lakedusk": [&"emberfall", 18.0, 0.0, Vector3.ZERO, -0.2],
	"underworld": [&"asphodel", 12.0, 1.0, Vector3(0, 2, 20), -0.1],
	"fogmorning": [&"thornwick", 7.5, -1.4, Vector3(-40, 2, 30), -0.08],
}

## Weather forced at a stop (unless --weather overrides it).
const STOP_WEATHER := {"storm": "storm", "rain": "rain", "snow": "snow", "fogmorning": "fog"}
## Stops that look for open water near their location and stand on its shore.
const WATER_STOPS := ["lake", "lakedusk"]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var w := GameWorld.instance
	var report := PackedStringArray()
	var tour := ["spawn", "village", "dusk", "night", "forest", "peaks", "keep", "crypt", "gates", "hell"]
	var force_time := -1.0
	var force_weather := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tour="):
			tour = Array(a.trim_prefix("--tour=").split(","))
		elif a.begins_with("--time="):
			force_time = float(a.trim_prefix("--time="))
		elif a.begins_with("--weather="):
			force_weather = a.trim_prefix("--weather=")
		elif a.begins_with("--style="):
			_set_graphics("style", int(a.trim_prefix("--style=")))
		elif a.begins_with("--quality="):
			_set_graphics("quality", int(a.trim_prefix("--quality=")))
		elif a.begins_with("--scale="):
			_set_graphics("render_scale", float(a.trim_prefix("--scale=")))
	report.append("quality %s, style %s, preset scale %.2f (actual/adaptive viewport recorded per stop)" % [Settings.QUALITY_NAMES[int(Settings.get_value("graphics", "quality"))],
			Settings.STYLE_NAMES[int(Settings.get_value("graphics", "style"))], Settings.render_scale()])
	if "--no-bosses" in OS.get_cmdline_user_args():
		for k in ["warden", "mountain_king", "dragon", "cerberus", "hades", "leviathan", "broodmother", "bog_hag"]:
			w.bosses_defeated[k] = true
	if "--no-spawns" in OS.get_cmdline_user_args():
		# Architecture captures: no creatures wandering into the frame.
		w.director.process_mode = Node.PROCESS_MODE_DISABLED
		w.spawner.process_mode = Node.PROCESS_MODE_DISABLED
	if "--no-hud" in OS.get_cmdline_user_args() and w.hud != null:
		w.hud.visible = false
	await _frames(60)
	for stop: String in tour:
		# "arena_<location id>": stand 18 m in front of that location's boss spawn.
		var arena := stop.begins_with("arena_")
		var spec: Array = [StringName(stop.trim_prefix("arena_")), 13.0, 0.0, Vector3(0, 2.5, 18), -0.12] if arena else STOPS.get(stop, [])
		# "cam:<location id>:ox:oy:oz:yaw:pitch[:time]": hover at an offset from the boss spawn
		# (or the location centre), e.g. close-ups of arena architecture.
		var cam := stop.begins_with("cam:")
		if cam:
			var cparts := stop.split(":")
			spec = [StringName(cparts[1]), float(cparts[7]) if cparts.size() > 7 else 13.0, float(cparts[5]),
					Vector3(float(cparts[2]), float(cparts[3]), float(cparts[4])), float(cparts[6])]
			stop = "cam_%s_%02d" % [cparts[1], tour.find(stop)]
		# "site_<location id>": 16 m south of a location, looking north.
		# "bld_<village>_<n>" / "in_<village>_<n>": the n-th building of a
		# village from outside its door, or from just inside it.
		var inside := stop.begins_with("in_")
		if stop.begins_with("site_"):
			spec = [StringName(stop.trim_prefix("site_")), 10.5, 0.0, Vector3(0, 2.5, 16), -0.1]
		elif stop.begins_with("bld_") or inside:
			var parts := stop.split("_")
			var vloc := w.location_by_id(StringName("_".join(parts.slice(1, parts.size() - 1))))
			var n := int(parts[parts.size() - 1])
			var k := 0
			if vloc != null:
				for prop: Dictionary in vloc.props:
					if prop.get("type", "") != "building":
						continue
					if k == n:
						var door: Vector3 = prop["door_out"]
						var front := Basis(Vector3.UP, int(prop["rot"]) * PI * 0.5) * Vector3.BACK
						var pos := door + front * 6.5 + Vector3(0, 1.0, 0)
						var look := -front
						var pitch := -0.08
						if inside:
							var d := float(prop["d"])
							pos = VillagePlan.to_world(prop, Vector3(-float(prop["w"]) * 0.5 + float(prop["door"]) + float(prop["door_w"]) * 0.5, 0.05, d * 0.5 - 1.5))
							look = -front
							pitch = -0.12
						spec = [vloc.id, 11.0, atan2(-look.x, -look.z), pos - vloc.center, pitch]
					k += 1
		if spec.is_empty():
			report.append("%s: unknown stop" % stop)
			continue
		var loc := w.location_by_id(spec[0])
		if loc == null:
			report.append("%s: location missing" % stop)
			continue
		if stop == "ryft" or loc.dimension == 2:
			w.ryft_unlocked = true  # Capture-only fixture, never normal gameplay.
		if loc.dimension != w.local_dimension:
			w.travel(loc.dimension)
		var target := loc.center
		for s in loc.spawns_of("shrine"):
			target = s["pos"]
		var p := w.local_player
		p.invulnerable_until = Time.get_ticks_msec() / 1000.0 + 3600.0   # teleports can look like falls
		var vw := w.world_for(loc.dimension)
		var offset: Vector3 = spec[3] if spec.size() > 3 else Vector3(0, 2, 4)
		if spec.size() > 3:
			target = loc.center
		if arena or cam:
			for s in loc.spawns_of("boss"):
				target = s["pos"]
		p.global_position = target + offset
		p.body.fly = cam
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--hold="):
				p.give_item(a.trim_prefix("--hold="), 1)
				for i in Inventory.HOTBAR:
					if p.inventory.get_slot(i).get("id", "") == a.trim_prefix("--hold="):
						p.inventory.selected = i
		if stop in ["geyser", "sanctuary"]:
			var wanted := CaveBiomes.Kind.GEYSER if stop == "geyser" else CaveBiomes.Kind.CRYSTAL_REFUGE
			var found := false
			for z in range(4, 12):
				for x in range(4, 12):
					var r := CaveBiomes.region(Vector3(x * 128 + 64, -32, z * 128 + 64), vw.gen.world_seed)
					if int(r["kind"]) == wanted:
						p.global_position = r["center"] + Vector3(0, -16, 8)
						found = true
						break
				if found:
					break
			p.offhand_light = true
		if stop in WATER_STOPS:
			var shore := _find_shore(w, loc)
			p.global_position = Vector3(shore.x, 0, shore.y)
			spec = spec.duplicate()
			spec[2] = shore.z
		vw.focus = p.global_position
		w.sky.time_of_day = spec[1] if force_time < 0.0 else force_time
		var weather: String = force_weather if force_weather != "" else STOP_WEATHER.get(stop, "clear")
		if w.weather.has_method("force"):
			w.weather.call("force", weather)
		p.camera.yaw = float(spec[2])
		p.camera.pitch = float(spec[4]) if spec.size() > 4 else -0.18
		var t0 := Time.get_ticks_msec()
		while (not vw.is_area_loaded(p.global_position) or vw.loading_progress() < 0.95) and Time.get_ticks_msec() - t0 < 20000:
			await get_tree().process_frame
		if not inside and (spec.size() > 3 or vw.is_solid(Vector3i(p.global_position.floor())) or not vw.is_solid(Vector3i((p.global_position - Vector3(0, 3, 0)).floor()))):
			var gp := p.global_position
			var g := vw.ground_below(gp.x, gp.y + 30.0, gp.z, 60.0)
			var y := g if absf(g) < 1e6 else float(vw.surface_y(int(gp.x), int(gp.z)) + 1)
			if loc.half_height > 0.0:
				y = loc.center.y
			p.global_position.y = y + 0.05
		if cam:
			p.global_position = target + offset
		p.body.velocity = Vector3.ZERO
		if stop.ends_with("fight"):
			var kind := "dragon" if stop == "dragonfight" else "mountain_king"
			var fwd := -p.camera.global_basis.z
			fwd.y = 0.0
			var boss := w.spawn_entity(kind, p.global_position + fwd.normalized() * 14.0 + Vector3(0, 0.5, 0), loc.dimension, {"home": String(loc.id)})
			if boss != null:
				boss.set("home_location", String(loc.id))
			p.invulnerable_until = Time.get_ticks_msec() / 1000.0 + 600.0
			await _frames(60)
			for i in 6:
				if boss != null and not boss.dead:
					w.request_attack([boss.net_id], 30.0, "hit")
				await get_tree().create_timer(1.0).timeout
			await _shot(stop + "_a")
			await get_tree().create_timer(2.5).timeout
		_unpause(w)
		await _frames(90)
		_unpause(w)
		# Falls and landings move the camera; frame the shot as specified.
		p.camera.yaw = float(spec[2])
		p.camera.pitch = float(spec[4]) if spec.size() > 4 else -0.18
		await _frames(20)
		var vp_rid := w.view.viewport.get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vp_rid, true)
		var stats := await _measure(1.5)
		var gpu := 0.0
		for i in 30:
			await get_tree().process_frame
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid) / 30.0
		report.append("output %s, 3D viewport %s, adaptive %s" % [str(DisplayServer.window_get_size()), str(w.view.viewport.size), str(Settings.get_value("graphics", "adaptive_resolution"))])
		report.append("%-8s %-28s load %5d ms  avg %.2f ms (%.0f fps) worst %.2f ms  3d gpu %.2f ms  process %.2f ms  draws %d  prims %d" % [stop, loc.name, Time.get_ticks_msec() - t0, stats.x, 1000.0 / stats.x, stats.y, gpu,
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
		for arg in OS.get_cmdline_user_args():
			if arg == "--third-person" and p.camera.first_person:
				p.camera.first_person = false
				p.call("_apply_view")
				await _frames(10)
			elif arg.begins_with("--press="):
				# Hold movement keys (e.g. move_forward,sprint) to catch locomotion mid-stride.
				for act in arg.trim_prefix("--press=").split(","):
					Input.action_press(act)
				await get_tree().create_timer(1.2).timeout
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--dig="):
				# Look down a little and dig N strikes into what the crosshair hits.
				p.camera.pitch = -0.55
				await _frames(5)
				for i in int(arg.trim_prefix("--dig=")):
					var hit: Dictionary = p.call("_block_target")
					if not hit.is_empty():
						p.call("_sculpt_strike", hit, int(hit["block"]))
					await get_tree().create_timer(0.45).timeout
				await _frames(30)
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--action="):
				# Freeze-frame an action mid-swing (first-person viewmodel checks).
				p.call("_start_action", arg.trim_prefix("--action="), 0.6)
				await get_tree().create_timer(0.2).timeout
		await _shot(stop)
		# --ui=map,journal: also shoot those HUD screens at every stop.
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--ui=") and w.hud != null:
				for screen_name in arg.trim_prefix("--ui=").split(","):
					var screen: Variant = w.hud.get({"map": "map_screen", "journal": "quest_log"}.get(screen_name, ""))
					if screen is UiModal:
						(screen as UiModal).open()
						await get_tree().create_timer(0.8).timeout
						await _shot(stop + "_" + screen_name)
						(screen as UiModal).close()
						await _frames(5)
		if "--arena-cost" in OS.get_cmdline_user_args():
			# GPU time with the modelled arenas hidden (needs --rendering-driver vulkan on macOS).
			var arenas := w.find_children("ArenaDirector", "", true, false)
			for a: Node3D in arenas:
				a.visible = false
			await _frames(20)
			var gpu_off := 0.0
			for i in 30:
				await get_tree().process_frame
				gpu_off += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid) / 30.0
			for a: Node3D in arenas:
				a.visible = true
			report.append("   arena gpu cost %.2f ms (%.2f with, %.2f without)" % [gpu - gpu_off, gpu, gpu_off])
		if "--gpu-breakdown" in OS.get_cmdline_user_args():
			await _gpu_breakdown(w, report, gpu if gpu > 0.0 else (await _measure(2.0)).x)
		if "--raw" in OS.get_cmdline_user_args():
			Ascii.effect.enabled = false
			await _frames(3)
			await _shot(stop + "_raw")
			Ascii.effect.enabled = true
		var meshes := p.model.find_children("*", "GeometryInstance3D", true, false)
		var first: Node3D = null
		var nvis := 0
		for m: Node3D in meshes:
			if m.is_visible_in_tree():
				nvis += 1
				if first == null:
					first = m
		for m: Node3D in meshes:
			if not m.is_visible_in_tree():
				var n: Node = m
				while n != null and n is Node3D and (n as Node3D).visible:
					n = n.get_parent()
				printerr("[game-capture] hidden mesh ", p.model.get_path_to(m), " hidden ancestor ", p.model.get_path_to(n) if n != null else "?", " dead ", p.dead, " model_dead ", p.model.get("_dead"))
				break
		printerr("[game-capture] visible meshes ", nvis, " entity root vis ", w.get_node("Entities").visible, " gw vis ", w.visible)
		printerr("[game-capture] model meshes ", meshes.size(), " first ", first.global_position if first else Vector3.ZERO, " in tree vis ", first.is_visible_in_tree() if first else false, " layers ", (first as VisualInstance3D).layers if first else 0, " cam mask ", w.view.camera.cull_mask, " cam pos ", w.view.camera.global_position)
		printerr("[game-capture] player at ", p.global_position, " cam ", p.camera.global_position, " fwd ", -p.camera.global_basis.z, " proc ", p.is_processing(), " state ", Game.state, " dead ", p.dead, " pm ", p.process_mode, " can ", p.can_process(), " model ", p.model, " vis ", p.visible, " model vis ", p.model.visible if p.model else false)
	if "--prof" in OS.get_cmdline_user_args():
		await _profile(w, report)
	for line in report:
		printerr("[game-capture] ", line)
	var f := FileAccess.open(out_dir.path_join("report.txt"), FileAccess.WRITE)
	f.store_string("\n".join(report) + "\n")
	f.close()
	get_tree().quit()


## GPU cost of the 3D view with one feature off at a time (needs a driver
## with timestamp queries, e.g. --rendering-driver vulkan on macOS).
func _gpu_breakdown(w: GameWorld, report: PackedStringArray, all_on: float) -> void:
	var env := w.sky.environment
	var vp := w.view.viewport.get_viewport_rid()
	var flat := Shader.new()
	flat.code = "shader_type spatial;\nvoid fragment() { ALBEDO = vec3(0.05, 0.1, 0.1); }\n"
	var liquid: ShaderMaterial = w.world_for(w.local_dimension).get("liquid_material")
	var liquid_shader := liquid.shader if liquid != null else null
	var toggles := {
		"volumetric fog": [func() -> void: env.volumetric_fog_enabled = false, func() -> void: env.volumetric_fog_enabled = true],
		"sky": [func() -> void: env.background_mode = Environment.BG_COLOR, func() -> void: env.background_mode = Environment.BG_SKY],
		"ssao": [func() -> void: env.ssao_enabled = false, func() -> void: GraphicsQuality.apply_environment(env)],
		"glow": [func() -> void: env.glow_enabled = false, func() -> void: env.glow_enabled = true],
		"fog": [func() -> void: env.fog_enabled = false, func() -> void: env.fog_enabled = true],
		"sun shadow": [func() -> void: w.sky.set_meta("no_shadow", true), func() -> void: w.sky.remove_meta("no_shadow")],
		"water shader": [func() -> void: if liquid != null: liquid.shader = flat, func() -> void: if liquid != null: liquid.shader = liquid_shader],
		"weather": [func() -> void: w.weather.visible = false, func() -> void: w.weather.visible = true],
		"ascii": [func() -> void: Ascii.effect.enabled = false, func() -> void: Ascii.effect.enabled = true],
	}
	var line := "   gpu %.2f ms;" % all_on
	for label: String in toggles:
		var pair: Array = toggles[label]
		(pair[0] as Callable).call()
		await _frames(25)
		var g := 0.0
		for i in 30:
			await get_tree().process_frame
			g += RenderingServer.viewport_get_measured_render_time_gpu(vp) / 30.0
		if g <= 0.0:
			# No GPU timestamps (Metal): use the frame time (run with --no-vsync).
			g = (await _measure(2.0)).x
		(pair[1] as Callable).call()
		line += "  -%s %.2f" % [label, all_on - g]
	report.append(line)
	await _frames(20)


## A pause menu opened by focus changes (other windows) would freeze the player.
func _unpause(w: GameWorld) -> void:
	var pm: Variant = w.hud.get("pause_menu") if w.hud != null else null
	if pm != null and bool(pm.get("is_open")):
		pm.call("close")
	get_tree().paused = false


## Changes a graphics setting for this run only (Settings.set_value would save it).
func _set_graphics(key: String, value: Variant) -> void:
	Settings._data["graphics"][key] = value
	Settings.changed.emit("graphics", key)


## A dry column next to open water near `loc`: Vector3(x, z, yaw facing the water).
func _find_shore(w: GameWorld, loc: Location) -> Vector3:
	var g := w.gen_for(loc.dimension)
	var c := Vector2(loc.center.x, loc.center.z)
	var best := Vector2(-1, -1)
	var best_d := INF
	for z in range(8, g.size - 8, 16):
		for x in range(8, g.size - 8, 16):
			var d := c.distance_squared_to(Vector2(x, z))
			if d < best_d and g.surface_height(x, z) < WorldGen.SEA_LEVEL - 2:
				# Wide enough to be a lake, not a puddle.
				if g.surface_height(x + 6, z) < WorldGen.SEA_LEVEL and g.surface_height(x - 6, z) < WorldGen.SEA_LEVEL \
						and g.surface_height(x, z + 6) < WorldGen.SEA_LEVEL and g.surface_height(x, z - 6) < WorldGen.SEA_LEVEL:
					best_d = d
					best = Vector2(x, z)
	if best.x < 0.0:
		return Vector3(c.x, c.y, 0.0)
	# Walk from the water towards the location until the ground is dry.
	var dir := (c - best).normalized()
	var p := best
	for k in 200:
		p += dir
		if g.surface_height(int(p.x), int(p.y)) >= WorldGen.SEA_LEVEL:
			break
	p += dir * 3.0
	# Face the water: forward = (-sin(yaw), 0, -cos(yaw)) = -dir.
	return Vector3(p.x, p.y, atan2(dir.x, dir.y))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _measure(seconds: float) -> Vector2:
	var total := 0.0
	var worst := 0.0
	var n := 0
	var last := Time.get_ticks_usec()
	while total < seconds * 1000.0:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := float(now - last) / 1000.0
		last = now
		total += ms
		worst = maxf(worst, ms)
		n += 1
	return Vector2(total / n, worst)


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + ".png"))


## Pauses one subsystem at a time and reports main-thread process time.
func _profile(w: GameWorld, report: PackedStringArray) -> void:
	var groups := {
		"all on": [],
		"hud": [w.hud],
		"entities": [w.get_node("Entities")],
		"voxels": w.worlds.values(),
		"sky+weather": [w.sky, w.weather],
		"tracker+director+spawner": [w.tracker, w.director, w.spawner],
		"view": [w.view],
		"replicator": [w.replicator],
		"Audio": [Audio],
		"Net": [Net],
		"Ascii": [Ascii],
		"local player": [w.local_player],
		"EVERYTHING": [w, Audio, Net, Ascii, Settings, Events],
	}
	for label: String in groups:
		var nodes: Array = groups[label]
		for n: Node in nodes:
			n.process_mode = Node.PROCESS_MODE_DISABLED
		await _frames(30)
		var total := 0.0
		for i in 120:
			await get_tree().process_frame
			total += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var phys := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		var objs := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		report.append("   physics %.2f ms, nodes %d, fps %.0f" % [phys, objs, Engine.get_frames_per_second()])
		report.append("profile %-26s process %.2f ms" % ["without " + label if not nodes.is_empty() else label, total / 120.0])
		for n: Node in nodes:
			n.process_mode = Node.PROCESS_MODE_INHERIT
