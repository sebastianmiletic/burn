extends Node
## Main-menu capture (development aid):
##   godot --path . --fullscreen -- --skip-intro --capture-menu=/abs/dir [--menu-shot-seconds=7] [--menu-only=shots,styles,panels]
## Waits for the live backdrop, screenshots every camera shot, the menu in the
## ASCII-off style and each sub-panel, measures frame times, writes
## report.txt and quits. The render style is restored afterwards.

var out_dir := ""
var menu: Node

var _report := PackedStringArray()


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	# Stray clicks or keys while the capture owns the screen must not start a game.
	get_tree().root.gui_disable_input = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--menu-ui-scale="):   # e.g. 3.6: the layout a small window would get
			get_tree().root.content_scale_factor = float(a.get_slice("=", 1))
	get_tree().root.focus_exited.connect(func() -> void: printerr("[menu-capture] window lost focus"))
	_run.call_deferred()


func _wants(part: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--menu-only="):
			return part in a.trim_prefix("--menu-only=").split(",")
	return true


func _run() -> void:
	var style0 := int(Settings.get_value("graphics", "style"))
	Settings.set_value("graphics", "style", Settings.Style.EMBER)
	var t0 := Time.get_ticks_msec()
	await _frames(20)
	_report.append("window %s, ui scale %.2f, render scale %.2f, quality %d" % [
		DisplayServer.window_get_size(), get_tree().root.content_scale_factor, Settings.render_scale(),
		int(Settings.get_value("graphics", "quality"))])
	await _shot("menu_early")
	var b := MenuBackdrop.instance()
	while b != null and b.first_frame_ms < 0 and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
		b = MenuBackdrop.instance()
	if b == null:
		_report.append("no backdrop")
	else:
		_report.append("backdrop first shot after %d ms (from backdrop start), %d ms after capture start" % [b.first_frame_ms, Time.get_ticks_msec() - t0])
		var stats := await _measure(2.0)
		_report.append("during fade-in: avg %.2f ms worst %.2f ms" % [stats.x, stats.y])
		await _wait(1.5)
		if "--menu-prof" in OS.get_cmdline_user_args():
			await _wait(16.0)
			var st := await _measure(3.0)
			_report.append("steady (no streaming) %-18s avg %.2f ms (%.0f fps) worst %.2f ms draws %d prims %d" % [b.caption, st.x, 1000.0 / st.x, st.y,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
			b.process_mode = Node.PROCESS_MODE_DISABLED
			await _wait(1.0)
			st = await _measure(2.0)
			_report.append("steady, backdrop paused (render only): avg %.2f ms worst %.2f ms" % [st.x, st.y])
			b.process_mode = Node.PROCESS_MODE_INHERIT
			b.visible = false
			await _wait(0.5)
			st = await _measure(2.0)
			_report.append("world hidden (sky + ASCII pass only): avg %.2f ms worst %.2f ms" % [st.x, st.y])
			b.visible = true
		elif "--menu-tune" in OS.get_cmdline_user_args():
			await _tune(b)
		elif _wants("shots"):
			var seen := {}
			var guard := Time.get_ticks_msec()
			while seen.size() < 4 and Time.get_ticks_msec() - guard < 90000:
				var idx := b.shot_index
				if not seen.has(idx):
					seen[idx] = true
					await _wait(2.4)
					var st := await _measure(1.5)
					_report.append("shot %d %-22s avg %.2f ms (%.0f fps) worst %.2f ms process %.2f ms draws %d prims %d" % [idx, b.caption, st.x, 1000.0 / st.x, st.y,
						Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
						RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
						RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
					await _shot("shot_%d" % idx)
				await get_tree().process_frame
	if _wants("styles"):
		Settings.set_value("graphics", "style", Settings.Style.OFF)
		await _wait(0.6)
		await _shot("style_off")
		Settings.set_value("graphics", "style", Settings.Style.FULL_COLOUR)
		await _wait(0.6)
		await _shot("style_colour")
		Settings.set_value("graphics", "style", Settings.Style.EMBER)
		await _wait(0.4)
	if _wants("panels") and menu != null and is_instance_valid(menu):
		for p: Array in [["_show_solo", "panel_solo"], ["_show_multiplayer", "panel_multiplayer"], ["_show_credits", "panel_credits"]]:
			menu.call(p[0])
			await _wait(0.9)
			await _shot(p[1])
		if menu.has_method("_close_panel"):
			menu.call("_close_panel")
		menu.call("_show_settings")
		await _wait(0.9)
		await _shot("panel_settings")
		var s: Node = menu.get("_settings")
		if s != null:
			s.call("close")
		await _wait(0.8)
		await _shot("menu_back")
	if _wants("lobby"):
		for host in [false, true]:
			Game.call("open_lobby_host" if host else "open_lobby_join")
			await _wait(1.2)
			var lobby := _find_root_child("LobbyScreen")
			if lobby != null and not host:
				for r in [3, 11, 0]:
					lobby.call("_type_rune", r)
				await _wait(0.4)
			await _shot("lobby_host" if host else "lobby_join")
			if lobby != null:
				lobby.call("_leave")
			await _wait(0.8)
		await _shot("menu_after_lobby")
	if _wants("lifecycle"):
		await _lifecycle()
	Settings.set_value("graphics", "style", style0)
	for line in _report:
		printerr("[menu-capture] ", line)
	var f := FileAccess.open(out_dir.path_join("report.txt"), FileAccess.WRITE)
	f.store_string("\n".join(_report) + "\n")
	f.close()
	get_tree().quit()


## Every shot at its start and end, in Ember and with ASCII off (composition tuning).
func _tune(b: MenuBackdrop) -> void:
	for i in 4:
		b.debug_jump(i)
		var t0 := Time.get_ticks_msec()
		while not (b.is_playing() and b.shot_index == i) and Time.get_ticks_msec() - t0 < 30000:
			await get_tree().process_frame
		_report.append("tune shot %d %s loaded in %d ms" % [i, b.caption, Time.get_ticks_msec() - t0])
		for u in [0.08, 0.92]:
			b.debug_seek(u)
			await _wait(0.8)
			await _shot("tune_%d_%02d" % [i, int(u * 100)])
			Settings.set_value("graphics", "style", Settings.Style.OFF)
			await _wait(0.25)
			await _shot("tune_%d_%02d_raw" % [i, int(u * 100)])
			Settings.set_value("graphics", "style", Settings.Style.EMBER)
			await _wait(0.1)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


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
	return Vector2(total / maxi(1, n), worst)


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + ".png"))
	_last_us = 0  # encoding the PNG is not a hitch of the menu


func _find_root_child(cls: String) -> Node:
	for c in get_tree().root.get_children():
		var s: Script = c.get_script()
		if s != null and s.get_global_name() == cls:
			return c
	return null


var _last_us := 0


## Logs every long frame with what the backdrop was doing (hitch hunting).
func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_us > 0 and now - _last_us > 60000:
		var b := MenuBackdrop.instance()
		_report.append("hitch %.0f ms at %.1f s  shot %d  %s" % [(now - _last_us) / 1000.0, now / 1e6,
			b.shot_index if b != null else -1, b.debug_state() if b != null else ""])
	_last_us = now


## Menu -> game -> menu: the backdrop must be gone while the game runs (one
## world, one AsciiView) and come back afterwards. Uses throwaway slot 7.
func _lifecycle() -> void:
	var nodes0 := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	Game.call("start_solo", 7, true)
	var t0 := Time.get_ticks_msec()
	while int(Game.get("state")) != 5 and Time.get_ticks_msec() - t0 < 90000:
		await get_tree().process_frame
	await _wait(1.0)
	var worlds := get_tree().root.find_children("*", "VoxelWorld", true, false).size()
	var views := get_tree().root.find_children("*", "AsciiView", true, false).size()
	_report.append("in game: backdrop %s, VoxelWorlds %d (expect 2), AsciiViews %d (expect 1), root 3D disabled %s" % [
		"GONE" if MenuBackdrop.instance() == null and get_tree().root.get_node_or_null("MenuBackdrop") == null else "STILL THERE",
		worlds, views, get_tree().root.disable_3d])
	await _shot("lifecycle_game")
	Game.call("quit_to_menu")
	t0 = Time.get_ticks_msec()
	while (MenuBackdrop.instance() == null or MenuBackdrop.instance().first_frame_ms < 0) and Time.get_ticks_msec() - t0 < 40000:
		await get_tree().process_frame
	await _wait(3.0)
	worlds = get_tree().root.find_children("*", "VoxelWorld", true, false).size()
	views = get_tree().root.find_children("*", "AsciiView", true, false).size()
	_report.append("back in menu after %d ms: backdrops %d, VoxelWorlds %d (expect 2, both the backdrop's), AsciiViews %d, root 3D disabled %s, nodes %d -> %d" % [
		Time.get_ticks_msec() - t0, get_tree().root.find_children("MenuBackdrop", "", false, false).size(), worlds, views,
		get_tree().root.disable_3d, nodes0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	await _shot("lifecycle_menu")
	SaveSystem.delete(7)
