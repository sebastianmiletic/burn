extends SceneTree
## App flow test (headless): intro -> menu -> new solo game -> quit to menu
## -> continue. Run: godot --headless --path . -s res://tests/game/flow_test.gd

var _fails := 0
var _step := 0
var _t := 0.0


func _initialize() -> void:
	change_scene_to_file.call_deferred("res://main.tscn")


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1


func _process(delta: float) -> bool:
	_t += delta
	var game: Node = root.get_node("Game")
	match _step:
		0:
			if _t > 1.0:
				_check(int(game.get("state")) == 1, "boot shows the intro")
				# Skip the intro the way a key press does.
				var intro := _find_screen("IntroScreen")
				if intro != null:
					intro.emit_signal("finished")
				_step = 1
				_t = 0.0
		1:
			if _t > 0.5:
				_check(int(game.get("state")) == 2 and _find_screen("MainMenu") != null, "intro finishes into the main menu")
				game.call("start_solo", 5, true)
				_step = 2
				_t = 0.0
		2:
			if int(game.get("state")) == 5:
				_check(true, "new solo game loads and plays (%.1f s)" % _t)
				_check(root.get_node_or_null("GameWorld") != null, "GameWorld at /root/GameWorld")
				_step = 3
				_t = 0.0
			elif _t > 90.0:
				_check(false, "new solo game loads")
				return _done()
		3:
			if _t > 2.0:
				# Wake on Ogygia, then save by quitting: continue must bring us back there.
				var gw: Node = root.get_node("GameWorld")
				var rep: Node = gw.get("replicator")
				rep.set("force_drown_outcome", 1)
				rep.call("request_drown_outcome")
				_check(int(gw.get("local_dimension")) == 3, "rescued onto Ogygia before saving")
				game.call("quit_to_menu")
				_step = 4
				_t = 0.0
		4:
			if _t > 1.0:
				_check(int(game.get("state")) == 2, "quit returns to the menu")
				_check(bool(game.call("has_save")), "the game was saved on quit")
				game.call("continue_game")
				_step = 5
				_t = 0.0
		5:
			if int(game.get("state")) == 5:
				_check(true, "continue loads the saved game")
				_check(str(game.get("session").get("slot")) == "slot_5", "quitting saved into the run that was played (slot 5), got %s" % str(game.get("session").get("slot")))
				_step = 6
				_t = 0.0
			elif _t > 90.0:
				_check(false, "continue loads the saved game")
				return _done()
		6:
			if _t > 3.0:
				var gw: Node = root.get_node("GameWorld")
				var p: Node = gw.get("local_player")
				_check(int(p.get("dimension")) == 3 and int(gw.get("local_dimension")) == 3, "a game saved on Ogygia loads on Ogygia")
				var residents := 0
				for e: Node in gw.call("all_entities"):
					if String(e.get("kind")) in ["calypso", "ogygia_raft"]:
						residents += 1
				_check(residents == 2, "Calypso and the raft are there after loading")
				load("res://world/ogygia/ogygia.gd").call("depart", gw)
				_check(int(p.get("dimension")) == 0, "the raft leaves Ogygia after a reload")
				return _done()
			elif _t > 90.0:
				_check(false, "continue loads the saved game")
				return _done()
	return false


func _find_screen(cls: String) -> Node:
	for c in root.get_children():
		var s: Script = c.get_script()
		if s != null and s.get_global_name() == cls:
			return c
	return null


func _done() -> bool:
	print("FLOW %s — %d failures" % ["PASSED" if _fails == 0 else "FAILED", _fails])
	quit(1 if _fails > 0 else 0)
	return true
