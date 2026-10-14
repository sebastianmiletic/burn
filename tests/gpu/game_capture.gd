extends Node
## In-game capture tour (development aid):
##   godot --path . --fullscreen -- --capture-game=/abs/dir [--tour=a,b,c] [--seed=N]
## Visits places at different times of day, saves screenshots and frame
## timings to report.txt, then quits.

var out_dir := ""

const STOPS := {
	"spawn": [&"emberfall_shrine", 10.0, 0.0],
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
}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var w := GameWorld.instance
	var report := PackedStringArray()
	var tour := ["spawn", "village", "dusk", "night", "forest", "peaks", "keep", "crypt", "gates", "hell"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tour="):
			tour = Array(a.trim_prefix("--tour=").split(","))
	await _frames(60)
	for stop: String in tour:
		var spec: Array = STOPS[stop]
		var loc := w.location_by_id(spec[0])
		if loc == null:
			report.append("%s: location missing" % stop)
			continue
		if loc.dimension != w.local_dimension:
			w.travel(loc.dimension)
		var target := loc.center
		for s in loc.spawns_of("shrine"):
			target = s["pos"]
		var p := w.local_player
		var vw := w.world_for(loc.dimension)
		var offset: Vector3 = spec[3] if spec.size() > 3 else Vector3(0, 2, 4)
		if spec.size() > 3:
			target = loc.center
		p.global_position = target + offset
		vw.focus = p.global_position
		w.sky.time_of_day = spec[1]
		p.camera.yaw = float(spec[2])
		p.camera.pitch = float(spec[4]) if spec.size() > 4 else -0.18
		var t0 := Time.get_ticks_msec()
		while (not vw.is_area_loaded(p.global_position) or vw.loading_progress() < 0.95) and Time.get_ticks_msec() - t0 < 20000:
			await get_tree().process_frame
		if spec.size() > 3 or vw.is_solid(Vector3i(p.global_position.floor())) or not vw.is_solid(Vector3i((p.global_position - Vector3(0, 3, 0)).floor())):
			var gp := p.global_position
			var g := vw.ground_below(gp.x, gp.y + 30.0, gp.z, 60.0)
			var y := g if absf(g) < 1e6 else float(vw.surface_y(int(gp.x), int(gp.z)) + 1)
			if loc.half_height > 0.0:
				y = loc.center.y
			p.global_position.y = y + 0.05
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
		await _frames(90)
		var stats := await _measure(1.5)
		report.append("%-8s %-28s load %5d ms  avg %.2f ms (%.0f fps) worst %.2f ms  process %.2f ms  draws %d  prims %d" % [stop, loc.name, Time.get_ticks_msec() - t0, stats.x, 1000.0 / stats.x, stats.y,
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
		await _shot(stop)
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
		printerr("[game-capture] player at ", p.global_position, " cam ", p.camera.global_position, " model ", p.model, " vis ", p.visible, " model vis ", p.model.visible if p.model else false)
	if "--prof" in OS.get_cmdline_user_args():
		await _profile(w, report)
	for line in report:
		printerr("[game-capture] ", line)
	var f := FileAccess.open(out_dir.path_join("report.txt"), FileAccess.WRITE)
	f.store_string("\n".join(report) + "\n")
	f.close()
	get_tree().quit()


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
