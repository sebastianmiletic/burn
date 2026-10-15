extends SceneTree
## Activities and villagers in the real game (headless):
##   godot --headless --path . -s res://tests/game/activity_test.gd -- --data-dir=<dir> [--only=npc,board,treasure,meteor,raid,ring]
## Boots a new solo game, then runs tests/game/activity_playtest.gd inside it
## (loaded after the autoloads exist). Prints PASS/FAIL lines; exit code 1 on failure.

var _t := 0.0
var _step := 0


func _initialize() -> void:
	change_scene_to_file.call_deferred("res://main.tscn")


func _process(delta: float) -> bool:
	_t += delta
	var game: Node = root.get_node_or_null("Game")
	if game == null:
		return false
	match _step:
		0:
			if _t > 0.5:
				game.call("start_solo", 6, true)
				_step = 1
				_t = 0.0
		1:
			if int(game.get("state")) == 5:
				var runner: Node = load("res://tests/game/activity_playtest.gd").new()
				root.get_node("GameWorld").add_child(runner)
				_step = 2
			elif _t > 120.0:
				print("FAIL  game did not load")
				quit(1)
	return false
