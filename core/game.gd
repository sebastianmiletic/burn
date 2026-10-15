extends Node
## Autoload "Game": the application state machine.
##   intro -> main menu -> (solo | lobby) -> loading -> playing -> menu
## Owns save slots, starts/joins sessions and builds the GameWorld.

enum State { BOOT, INTRO, MENU, LOBBY, LOADING, PLAYING }

const PARTY_SLOT := 9            ## the host's shared party world
const AUTOSAVE_SECONDS := 300.0
var CHARACTER_PATH := RuntimePaths.file("saves/party_character.burn")

var state := State.BOOT
var session := {}
var world: GameWorld

var _screen: Node
var _loading: Node
var _autosave := AUTOSAVE_SECONDS


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _arg("--mp-test", "") == "host":
		# Test harness: begin the campaign as soon as a second player is in the lobby.
		Net.lobby_changed.connect(func() -> void:
			if state != State.LOADING and state != State.PLAYING and Net.players.size() >= 2:
				state = State.LOADING
				start_campaign())
	Net.session_started.connect(_on_session_started)
	Net.join_failed.connect(_on_join_failed)
	Events.campaign_won.connect(_on_campaign_won)


## Called by the main scene.
func boot() -> void:
	var args := Array(OS.get_cmdline_user_args())
	if "--solo" in args or "--playtest" in args or args.any(func(a: String) -> bool: return a.begins_with("--capture-game")):
		start_solo(int(_arg("--slot", "8")), not "--continue" in args)
		return
	if "--host" in args or args.any(func(a: String) -> bool: return a.begins_with("--join")):
		return  # Net handles command-line parties; the lobby UI follows its signals
	if "--skip-intro" in args:
		show_menu()
	else:
		show_intro()


func _arg(prefix: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix + "="):
			return a.get_slice("=", 1)
	return fallback


func _process(delta: float) -> void:
	if state == State.PLAYING and world != null and Net.is_server():
		_autosave -= delta
		if _autosave <= 0.0:
			_autosave = AUTOSAVE_SECONDS
			save_game()


# --- Screens ----------------------------------------------------------------------

func _set_screen(node: Node) -> void:
	if _screen != null and is_instance_valid(_screen):
		_screen.queue_free()
	_screen = node
	if node != null:
		get_tree().root.add_child.call_deferred(node)


func _ui(path: String, args := []) -> Node:
	if not ResourceLoader.exists(path):
		push_error("Missing UI script " + path)
		return null
	var script: Script = load(path)
	return script.callv("new", args) as Node


func show_intro() -> void:
	state = State.INTRO
	var intro := _ui("res://ui/intro_screen.gd")
	if intro == null:
		show_menu()
		return
	intro.connect("finished", show_menu)
	_set_screen(intro)
	Audio.set_music("menu")


func show_menu() -> void:
	state = State.MENU
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	_set_screen(_ui("res://ui/main_menu.gd"))
	Audio.set_music("menu")


func open_lobby_host() -> void:
	state = State.LOBBY
	Net.host_party(String(Settings.get_value("gameplay", "player_name")))
	_set_screen(_ui("res://ui/lobby_screen.gd", [true]))


func open_lobby_join() -> void:
	state = State.LOBBY
	_set_screen(_ui("res://ui/lobby_screen.gd", [false]))


# --- Saves ------------------------------------------------------------------------

func has_save() -> bool:
	return SaveSystem.most_recent() >= 0


func save_slots() -> Array[Dictionary]:
	return SaveSystem.slots()


func continue_game() -> void:
	var slot := SaveSystem.most_recent()
	if slot >= 0:
		start_solo(slot, false)


func save_game() -> void:
	if world == null or world.local_player == null or not Net.is_server():
		return
	var slot := int(session.get("slot", 0))
	SaveSystem.write(slot, world.save_data())
	if Net.is_online():
		_save_character()
	Events.notify.emit("Game saved.", "info")


func _save_character() -> void:
	if world == null or world.local_player == null:
		return
	DirAccess.make_dir_recursive_absolute(SaveSystem.DIR)
	var f := FileAccess.open(CHARACTER_PATH, FileAccess.WRITE)
	if f != null:
		var d := world.local_player.to_dict()
		d.erase("pos")
		d.erase("dim")
		f.store_var({"player": d, "quests": world.quests.to_dict(), "discovered": world.discovered.keys()})


func _load_character() -> Dictionary:
	if not FileAccess.file_exists(CHARACTER_PATH):
		return {}
	var f := FileAccess.open(CHARACTER_PATH, FileAccess.READ)
	var v: Variant = f.get_var() if f != null else null
	return v if v is Dictionary else {}


# --- Sessions ------------------------------------------------------------------------

func start_solo(slot: int, new_game: bool) -> void:
	Net.leave()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var save := {} if new_game else SaveSystem.read(slot)
	if new_game:
		SaveSystem.delete(slot)
	var seed_value := int(save.get("seed", randi()))
	if _arg("--seed", "") != "":
		seed_value = int(_arg("--seed", "1"))
	_load_world({"seed": seed_value, "mode": "solo", "slot": slot, "save": save})


## Host pressed "Begin campaign" in the lobby.
func start_campaign() -> void:
	var save := SaveSystem.read(PARTY_SLOT)
	var seed_value := int(save.get("seed", randi()))
	# Clients loading with the host need the saved generation revision too,
	# not just late joiners. Otherwise an old host world and new client differ.
	var initial_state := {
		"edits": save.get("edits", {}), "bosses_defeated": save.get("bosses_defeated", []),
		"world_revision": save.get("world_revision", WorldGen.LATEST_REVISION if save.is_empty() else 1),
		"ryft_unlocked": save.get("ryft_unlocked", false),
		"time_of_day": save.get("time_of_day", 8.5), "day": save.get("day", 1),
	}
	Net.late_join_info = func() -> Dictionary:
		var live := join_state()
		return {"seed": seed_value, "join_state": live if not live.is_empty() else initial_state, "options": Net.lobby_options.duplicate()}
	Net.start_campaign({"seed": seed_value, "host_save": save.has("seed"), "join_state": initial_state})


func _on_session_started(info: Dictionary) -> void:
	# The same session can be announced twice (campaign start racing a late join).
	if (state == State.LOADING or state == State.PLAYING) and int(session.get("seed", -1)) == int(info.get("seed", -2)) and world != null:
		return
	var host := Net.is_server()
	var save := {}
	if host:
		save = SaveSystem.read(PARTY_SLOT)
	else:
		# Clients bring their own character; the world state comes from the host.
		var character := _load_character()
		save = {"player": character.get("player", {}), "quests": character.get("quests", {}),
			"discovered": character.get("discovered", [])}
		var js: Dictionary = info.get("join_state", {})
		save["edits"] = js.get("edits", {})
		save["bosses_defeated"] = js.get("bosses_defeated", [])
		save["world_revision"] = js.get("world_revision", 2)
		save["ryft_unlocked"] = js.get("ryft_unlocked", false)
		save["time_of_day"] = js.get("time_of_day", 8.5)
		save["day"] = js.get("day", 1)
	_load_world({"seed": int(info.get("seed", 1)), "mode": "host" if host else "client", "slot": PARTY_SLOT, "save": save})


## The host sends this to players who join a campaign already in progress.
func join_state() -> Dictionary:
	return world.join_state() if world != null and world.is_ready_for_join() else {}


func _load_world(info: Dictionary) -> void:
	state = State.LOADING
	session = info
	_set_screen(null)
	MenuBackdrop.release()  # the title-screen world goes before the real one is built
	if world != null and is_instance_valid(world):
		world.get_parent().remove_child(world)
		world.queue_free()
	_loading = _ui("res://ui/loading_screen.gd")
	if _loading != null:
		get_tree().root.add_child(_loading)
	Audio.set_music("silence")
	world = GameWorld.new()
	world.name = "GameWorld"  # identical path on every peer for RPCs
	get_tree().root.add_child(world)
	world.loading.connect(func(p: float, text: String) -> void:
		if _loading != null and is_instance_valid(_loading) and _loading.has_method("set_progress"):
			_loading.call("set_progress", p, text))
	await world.setup(info)
	if _loading != null and is_instance_valid(_loading):
		_loading.queue_free()
	_loading = null
	state = State.PLAYING
	_autosave = AUTOSAVE_SECONDS
	world.replicator.client_ready()
	if info.get("mode", "solo") != "client":
		save_game()
	_maybe_capture()


func quit_to_menu() -> void:
	session = {}
	if state == State.PLAYING:
		if Net.is_server():
			save_game()
		elif Net.is_online():
			_save_character()
	Net.leave()
	if world != null and is_instance_valid(world):
		world.queue_free()
	world = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	show_menu()


func _on_join_failed(reason: String) -> void:
	if state == State.PLAYING or state == State.LOADING:
		quit_to_menu()
	Events.notify.emit(reason, "warn")


func _on_campaign_won() -> void:
	save_game()


func _maybe_capture() -> void:
	var mp := _arg("--mp-test", "")
	if mp != "":
		var probe: Node = load("res://tests/net/mp_probe.gd").new()
		probe.set("role", mp)
		world.add_child(probe)
	if "--playtest" in OS.get_cmdline_user_args():
		world.add_child(load("res://tests/game/playtest.gd").new())
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture-game="):
			var script: Script = load("res://tests/gpu/game_capture.gd")
			var cap: Node = script.new()
			cap.set("out_dir", a.get_slice("=", 1))
			world.add_child(cap)
