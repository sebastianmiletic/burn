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
		menu.call("_show_runs")
		await _wait(0.4)
		await _shot("menu_runs")
		menu.call("_show_credits")
		await _wait(0.4)
		await _shot("menu_credits")
		menu.queue_free()

	if _wants("browser"):
		var b := ServerBrowser.new()
		b.offline_preview = true
		add_child(b)
		var proto := ServerBrowser.protocol()
		b.show_entries([
			{"name": "Cinderheart's fire", "description": "Hunting the Mountain King, all welcome", "mode": "Campaign", "players": 3, "max_players": 8, "ping": 34.0, "protocol": proto, "version": "0.5.1", "password": false, "ip": "1.2.3.4", "port": 47211, "verified": true, "source": "online"},
			{"name": "The Ashen Vigil", "description": "", "mode": "Campaign", "players": 8, "max_players": 8, "ping": 92.0, "protocol": proto, "version": "0.5.1", "password": false, "ip": "1.2.3.5", "port": 47211, "verified": true, "source": "online"},
			{"name": "Kindlers only", "description": "friends of the forge", "mode": "Campaign", "players": 1, "max_players": 4, "ping": 151.0, "protocol": proto, "version": "0.5.1", "password": true, "ip": "1.2.3.6", "port": 47212, "verified": false, "source": "online"},
			{"name": "Basement fire", "description": "", "mode": "Campaign", "players": 2, "max_players": 6, "ping": 3.0, "protocol": proto, "version": "", "password": false, "ip": "192.168.1.20", "port": 47211, "verified": true, "source": "lan"},
			{"name": "Old embers", "description": "", "mode": "Campaign", "players": 2, "max_players": 8, "ping": -2.0, "protocol": proto - 1, "version": "0.5.0", "password": false, "ip": "1.2.3.7", "port": 47211, "verified": null, "source": "online"},
		], "5 public servers online.")
		await _wait(1.2)
		await _shot("browser")
		b.call("_show_host")
		await _wait(0.5)
		await _shot("browser_host")
		b.queue_free()
		await _frames(2)

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
		Net.leave()  # fake guest IDs below must never enter a live ENet party
		var join := LobbyScreen.create(LobbyScreen.Mode.JOIN)
		add_child(join)
		await _frames(2)
		join.call("_type_rune", 3)
		join.call("_type_rune", 11)
		join.call("_type_rune", 0)
		await _wait(0.6)
		await _shot("lobby_join")
		# Joined-guest fixtures for both read-only party-rule summaries.
		Net.players = {1: {"name": "Ash", "color": Color(0.95, 0.6, 0.25), "ready": true},
			2: {"name": "Ember", "color": Color(0.4, 0.7, 0.8), "ready": true}}
		Net.lobby_options["shrine_respawn"] = false
		join.call("_refresh")
		await _wait(0.4)
		await _shot("lobby_guest_revives")
		Net.lobby_options["shrine_respawn"] = true
		join.call("_refresh")
		await _wait(0.4)
		await _shot("lobby_guest_shrines")
		join.queue_free()
		Net.leave()

	if _wants("icons"):
		var sheet := IconSheet.new()
		sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(sheet)
		await _wait(0.4)
		await _shot("icons")
		sheet.queue_free()

	if _wants("loading"):
		var l := LoadingScreen.new()
		add_child(l)
		l.set_progress(0.12, "Shaping the land")
		await _wait(4.0)
		printerr("[gallery] loading fps %d" % Engine.get_frames_per_second())
		await _shot("loading")
		l.set_progress(0.62, "Raising the land")
		await _wait(7.6)
		printerr("[gallery] loading fps %d" % Engine.get_frames_per_second())
		await _shot("loading_roar")
		await _wait(3.2)
		await _shot("loading_bite")
		l.set_progress(1.0, "")
		l.queue_free()
		await _wait(0.4)
		await _shot("loading_outro")
		await _wait(1.2)

	var need_world := false
	for n in ["hud", "chat", "inventory", "shop", "dialog", "journal", "map", "pause", "death", "victory"]:
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
		# What the crosshair rests on replaces the location block (look_info).
		hud.status.call("_on_look", "Iron Ore Vein", "Ore · needs a stone pickaxe or better", "Smelts into iron ingots at a furnace.")
		await _wait(0.8)
		await _shot("hud_look")
		hud.status.call("_on_look", "", "", "")
	if _wants("chat"):
		ev.emit_signal("chat_message", "Brandmark", "/me raises a torch toward the pass", "party")
		ev.emit_signal("chat_message", "Kindlewright", "meet at the shrine, bring coal", "whisper")
		ev.emit_signal("chat_message", "", "The Mountain King has been defeated.", "system")
		ev.emit_signal("chat_message", "Soothand", "gg! that [b]was[/b] close", "party")
		await _wait(0.6)
		await _shot("hud_chat")
		hud.chat.open("/w Kindlewright on my way")
		await _wait(0.6)
		await _shot("hud_chat_typing")
		hud.chat.close()
		await _frames(2)
	var screens := [
		["inventory", func() -> void: hud.inventory_screen.open()],
		["shop", func() -> void: ev.emit_signal("shop_open", "blacksmith")],
		["dialog", func() -> void: ev.emit_signal("dialog_open", null, "Hale the Blacksmith",
				PackedStringArray(["Iron? Aye, I can work iron. Bring me five ore and three coal and you'll have a pickaxe that bites gold."]),
				[{"text": "Show me what you can forge.", "id": "shop"}, {"text": "Any work for a wanderer?", "id": "quest"}, {"text": "Farewell.", "id": "leave"}])],
		["journal", func() -> void: hud.quest_log.open()],
		["journal_path", func() -> void:
			hud.quest_log.open()
			hud.quest_log.call("_set_tab", QuestLogScreen.Tab.PATH)],
		["map", func() -> void: hud.map_screen.open()],
		["pause", func() -> void: hud.pause_menu.open()],
		["death", func() -> void: ev.emit_signal("player_died", "Burned by the Mountain King's hearthfire")],
		["downed", func() -> void:
			_world.get("local_player").set("downed", true)
			_world.get("local_player").set("bleed_left", 63.0)
			ev.emit_signal("player_died", "Felled by the Warden")],
		["victory", func() -> void: ev.emit_signal("campaign_won")],
	]
	for s: Array in screens:
		if not _wants(s[0]):
			continue
		(s[1] as Callable).call()
		await _wait(3.4 if s[0] in ["death", "downed", "victory", "dialog"] else 0.6)
		await _shot(s[0])
		hud.inventory_screen.close()
		hud.shop_screen.close()
		hud.quest_log.close()
		hud.map_screen.close()
		hud.pause_menu.close()
		hud.dialog.close()
		hud.death_screen.hide_death()
		_world.get("local_player").set("downed", false)
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


## Every map symbol (MapIcons.glyphs()) at a large and two map sizes, the
## boss badges, and the player marker pins, on dark and map-like grounds.
class IconSheet:
	extends Control

	const BOSSES := [&"skull", &"serpent", &"kraken", &"whirlpool", &"dragon", &"spider", &"crown", &"flame",
		&"hound", &"witch", &"crystal", &"void_eye"]

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.075, 0.07))
		draw_rect(Rect2(0, size.y * 0.62, size.x, size.y * 0.38), Color(0.5, 0.48, 0.32))
		var all := MapIcons.glyphs()
		var cols := 14
		var step := Vector2((size.x - 60.0) / cols, 92.0)
		for i in all.size():
			var g: StringName = all[i]
			var at := Vector2(50 + (i % cols) * step.x, 46 + (i / cols) * step.y)
			var col := MapIcons.STONE
			match g:
				&"village": col = MapIcons.VILLAGE
				&"shrine": col = MapIcons.SHRINE
				&"portal": col = MapIcons.PORTAL
				&"quest": col = MapIcons.QUEST
				&"wreck", &"sunken", &"well", &"fishing", &"anchor", &"b_waves": col = MapIcons.SEA
			MapIcons.draw_glyph(self, g, at, 24.0, col, Color(0, 0, 0, 0.85))
			MapIcons.draw_glyph(self, g, at + Vector2(-step.x * 0.28, 38), 8.0, col, Color(0, 0, 0, 0.85))
			MapIcons.draw_glyph(self, g, at + Vector2(step.x * 0.12, 38), 11.0, col, Color(0, 0, 0, 0.85))
			draw_string(UiTheme.MONO, at + Vector2(-step.x * 0.45, 58), String(g), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UiTheme.TEXT_DIM)
		var y := size.y * 0.62 + 50.0
		for i in BOSSES.size():
			var x := 60.0 + i * 100.0
			MapIcons.draw_badge(self, BOSSES[i], Vector2(x, y), 26.0, false)
			MapIcons.draw_badge(self, BOSSES[i], Vector2(x - 20, y + 62), 13.0, false)
			MapIcons.draw_badge(self, BOSSES[i], Vector2(x + 18, y + 62), 8.5, i % 3 == 0)
		for i in MapIcons.MARKER_ICONS.size():
			var x := 60.0 + i * 90.0
			var c: Color = MapIcons.MARKER_COLOURS[i % MapIcons.MARKER_COLOURS.size()]
			MapIcons.draw_marker(self, MapIcons.MARKER_ICONS[i], c, Vector2(x, y + 150), 13.0)
			MapIcons.draw_marker(self, MapIcons.MARKER_ICONS[i], c, Vector2(x + 34, y + 150), 6.0)
