extends Node
## UI gallery: shows every screen with fake data and (optionally) captures
## screenshots.
##   godot --path . --fullscreen res://tests/gpu/ui_gallery.tscn -- --capture=/abs/dir [--only=hud,inventory]
## Without --capture it cycles through the screens; press Space for the next.

const MockWorld := preload("res://tests/gpu/ui_mock_world.gd")

var _out := ""
var _only := PackedStringArray()
var _world: Node
var _current: Node
var _stage: Control


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_out = arg.trim_prefix("--capture=")
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",")
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _wants(name: String) -> bool:
	return _only.is_empty() or _only.has(name)


func _run() -> void:
	await _frames(10)
	if _wants("intro"):
		var intro := IntroScreen.new()
		add_child(intro)
		await _wait(1.6)
		await _shot("intro_burning")
		await _wait(1.9)
		await _shot("intro_full")
		if is_instance_valid(intro):
			intro.queue_free()

	if _wants("menu"):
		var menu := MainMenu.new()
		add_child(menu)
		await _wait(1.2)
		await _shot("menu")
		menu.call("_show_solo")
		await _wait(0.4)
		await _shot("menu_solo")
		menu.call("_show_multiplayer")
		await _wait(0.4)
		await _shot("menu_multiplayer")
		menu.queue_free()

	if _wants("settings"):
		var bg := EmberBackground.new()
		add_child(bg)
		var s := SettingsMenu.new()
		add_child(s)
		await _wait(0.5)
		await _shot("settings_graphics")
		s.get("_tabs").current_tab = 3
		await _wait(0.3)
		await _shot("settings_controls")
		s.queue_free()
		bg.queue_free()

	if _wants("lobby"):
		var host := LobbyScreen.create(LobbyScreen.Mode.HOST)
		add_child(host)
		var host_runes := PackedInt32Array([3, 11, 0, 14])
		for i in 4:
			var g: RuneGlyph = host.get("_code_row").get_child(i)
			g.rune = host_runes[i]
		await _wait(0.6)
		await _shot("lobby_host")
		host.queue_free()
		var join := LobbyScreen.create(LobbyScreen.Mode.JOIN)
		add_child(join)
		await _frames(2)
		join.call("_type_rune", 3)
		join.call("_type_rune", 11)
		join.call("_type_rune", 0)
		await _wait(0.6)
		await _shot("lobby_join")
		join.queue_free()

	if _wants("loading"):
		var l := LoadingScreen.new()
		add_child(l)
		l.set_progress(0.62, "Raising the ruins")
		await _wait(1.0)
		await _shot("loading")
		l.queue_free()

	var need_world := false
	for n in ["hud", "inventory", "shop", "dialog", "journal", "map", "pause", "death", "victory"]:
		need_world = need_world or _wants(n)
	if not need_world:
		get_tree().quit()
		return

	_world = MockWorld.new()
	add_child(_world)
	_world.call("setup")
	var backdrop := EmberBackground.new()
	backdrop.intensity = 0.7
	var layer := CanvasLayer.new()
	layer.layer = -5
	layer.add_child(backdrop)
	add_child(layer)
	var hud := Hud.new()
	add_child(hud)
	await _frames(5)
	var ev := get_node("/root/Events")
	ev.emit_signal("location_changed", "Hall of the Mountain King", "Frost Peaks · Hall", true)
	ev.emit_signal("player_health_changed", 64.0, 140.0)
	ev.emit_signal("xp_changed", 610, 3, 0.31)
	ev.emit_signal("inventory_changed")
	ev.emit_signal("hotbar_selected", 0)
	ev.emit_signal("ability_cooldown", "fireball", 3.2, 6.0)
	ev.emit_signal("ability_cooldown", "dodge", 0.6, 1.2)
	ev.emit_signal("boss_engaged", null, "The Mountain King")
	ev.emit_signal("boss_health_changed", null, 12450.0, 20000.0, 2)
	ev.emit_signal("quest_updated", "embers")
	ev.emit_signal("notify", "+3 Iron Ore", "loot")
	ev.emit_signal("notify", "Quest updated: Embers in the Ash", "quest")
	ev.emit_signal("notify", "Your pickaxe is too soft for gold.", "warn")
	ev.emit_signal("interact_prompt", "[E]  Talk to Hale the blacksmith")
	ev.emit_signal("mining_progress", 0.65)
	ev.emit_signal("chat_message", "Cinderheart", "found iron down the east shaft", "party")
	ev.emit_signal("chat_message", "", "Ashwalker joined the warband.", "system")
	var p: Vector3 = _world.get("local_player").global_position
	ev.emit_signal("damage_number", p + Vector3(0.5, 2.0, 0), 37, false, "hit")
	ev.emit_signal("damage_number", p + Vector3(-0.8, 2.3, 0), 112, true, "hit")
	ev.emit_signal("damage_number", p + Vector3(0.2, 1.6, 1.0), 9, false, "player")
	if _wants("hud"):
		await _wait(0.9)
		await _shot("hud_banner")
		await _wait(3.3)
		ev.emit_signal("damage_number", p + Vector3(0.5, 2.0, 0), 24, false, "hit")
		await _wait(0.3)
		await _shot("hud")
	var screens := [
		["inventory", func() -> void: hud.inventory_screen.open()],
		["shop", func() -> void: ev.emit_signal("shop_open", "blacksmith")],
		["dialog", func() -> void: ev.emit_signal("dialog_open", null, "Hale the Blacksmith",
				PackedStringArray(["Iron? Aye, I can work iron. Bring me five ore and three coal and you'll have a pickaxe that bites gold."]),
				[{"text": "Show me what you can forge.", "id": "shop"}, {"text": "Any work for a wanderer?", "id": "quest"}, {"text": "Farewell.", "id": "leave"}])],
		["journal", func() -> void: hud.quest_log.open()],
		["map", func() -> void: hud.map_screen.open()],
		["pause", func() -> void: hud.pause_menu.open()],
		["death", func() -> void: ev.emit_signal("player_died", "Burned by the Mountain King's hearthfire")],
		["victory", func() -> void: ev.emit_signal("campaign_won")],
	]
	for s: Array in screens:
		if not _wants(s[0]):
			continue
		(s[1] as Callable).call()
		await _wait(3.4 if s[0] in ["death", "victory", "dialog"] else 0.6)
		await _shot(s[0])
		hud.inventory_screen.close()
		hud.shop_screen.close()
		hud.quest_log.close()
		hud.map_screen.close()
		hud.pause_menu.close()
		hud.dialog.close()
		hud.death_screen.hide_death()
		hud.victory_screen.close()
		get_tree().paused = false
		await _frames(2)
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _shot(shot_name: String) -> void:
	if _out == "":
		await _wait(1.5)
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(shot_name + ".png"))
	printerr("[gallery] ", shot_name)
