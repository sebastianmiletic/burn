extends Node
## Automated capture + benchmark for the renderer test scene.
##
##   godot --path . -- --capture=/abs/out/dir [--capture-seconds=3]
##
## For each cell preset: waits for the atlas, measures average / worst frame
## time, then saves screenshots of the ASCII view, the raw scene, the edge
## view and the material-mask view. Prints a summary and quits.

var _out := ""
var _seconds := 3.0
var _presets: Array[int] = [0, 1, 2]
var _shots := true


static func requested() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			return true
	return false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_out = arg.trim_prefix("--capture=")
		elif arg.begins_with("--capture-seconds="):
			_seconds = float(arg.trim_prefix("--capture-seconds="))
		elif arg.begins_with("--capture-presets="):
			_presets.clear()
			for p in arg.trim_prefix("--capture-presets=").split(","):
				_presets.append(int(p))
		elif arg == "--no-shots":
			_shots = false
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	var report := PackedStringArray()
	await _frames(30)
	var size := get_viewport().get_texture().get_size()
	report.append("window %dx%d, screen scale %.1f, render scale %.2f" % [size.x, size.y, DisplayServer.screen_get_scale(), Ascii.render_scale])
	for preset in _presets:
		Ascii.set_cell_preset(preset)
		await _wait_for_cell(Ascii.physical_cell_size())
		await _frames(20)
		var stats := await _measure(_seconds)
		var tag: String = ["fine", "default", "chunky"][preset]
		var vp := get_viewport().get_viewport_rid()
		var internal := Vector2(DisplayServer.window_get_size()) * Ascii.render_scale
		report.append("%-8s 3d %dx%d cell %s  avg %.2f ms (%.0f fps)  worst %.2f ms  gpu %.2f ms  cpu %.2f ms" % [tag, internal.x, internal.y, str(Ascii.physical_cell_size()), stats.x, 1000.0 / stats.x, stats.y,
				RenderingServer.viewport_get_measured_render_time_gpu(vp), RenderingServer.viewport_get_measured_render_time_cpu(vp)])
		if not _shots:
			continue
		await _shot("%s_ascii" % tag)
		if preset == Ascii.CellPreset.DEFAULT:
			Ascii.effect.debug_view = AsciiEffect.DebugView.EDGES
			await _shot("default_edges")
			Ascii.effect.debug_view = AsciiEffect.DebugView.MATERIALS
			await _shot("default_materials")
			Ascii.effect.debug_view = AsciiEffect.DebugView.NONE
			Ascii.set_enabled(false)
			await _shot("default_raw")
			Ascii.set_enabled(true)
	for line in report:
		print("[capture] ", line)
	var f := FileAccess.open(_out.path_join("report.txt"), FileAccess.WRITE)
	f.store_string("\n".join(report) + "\n")
	f.close()
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait_for_cell(cell: Vector2i) -> void:
	for i in 300:
		if Ascii.effect.current_cell_size() == cell:
			return
		await get_tree().process_frame
	push_error("capture: atlas for %s never arrived" % str(cell))


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
	await _frames(4)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(shot_name + ".png"))
