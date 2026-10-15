extends SceneTree
## GPU captures of villagers and activities in first person (development aid):
##   godot --path . --resolution 1600x900 -s res://tests/gpu/activity_capture.gd -- \
##       --out=/abs/dir --no-update --data-dir=<dir> [--shots=npc,smith,board,...] [--style=4] [--quality=2]
## Boots a new solo game and runs tests/gpu/activity_capture_run.gd inside it.

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
				root.get_node("GameWorld").add_child(load("res://tests/gpu/activity_capture_run.gd").new())
				_step = 2
			elif _t > 180.0:
				quit(1)
	return false
