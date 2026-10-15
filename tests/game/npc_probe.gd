extends SceneTree
## Diagnostic (not part of CI): boots a solo game, lets the Emberfall villagers
## live through an afternoon and an evening and prints what each one did.
##   godot --headless --path . -s res://tests/game/npc_probe.gd -- --data-dir=<dir>

var _t := 0.0
var _step := 0
var _samples := {}   # net_id -> Array of [t, pos, on_floor, hit_wall, yaw]
var _sample_t := 0.0


func _initialize() -> void:
	change_scene_to_file.call_deferred("res://main.tscn")


func _process(delta: float) -> bool:
	_t += delta
	var game: Node = root.get_node("Game")
	match _step:
		0:
			if _t > 0.5:
				game.call("start_solo", 7, true)
				_step = 1
				_t = 0.0
		1:
			if int(game.get("state")) == 5:
				_step = 2
				_t = 0.0
				root.get_node("GameWorld").get("sky").set("time_of_day", 14.0)
				Engine.time_scale = 1.0
		2, 3:
			_sample_t += delta
			if _sample_t > 0.25:
				_sample_t = 0.0
				_sample()
			if _t > 75.0:
				_report("afternoon" if _step == 2 else "evening")
				_samples.clear()
				_t = 0.0
				if _step == 2:
					root.get_node("GameWorld").get("sky").set("time_of_day", 21.4)
					_step = 3
				else:
					Engine.time_scale = 1.0
					quit(0)
					return true
	return false


var _nan_reported := false


func _find_nan(n: Node) -> Node:
	if n is Node3D and not (n as Node3D).global_transform.origin.is_finite():
		return n
	for c in n.get_children():
		var r := _find_nan(c)
		if r != null:
			return r
	return null


func _sample() -> void:
	var w: Node = root.get_node("GameWorld")
	if not _nan_reported:
		var bad := _find_nan(w)
		if bad != null:
			_nan_reported = true
			print("NAN at t=%.1f node %s parent chain %s" % [_t, bad.get_path(), str(bad.get_parent().get_path())])
	for n in w.call("all_entities"):
		if n.get("kind") == "npc":
			if not _samples.has(n.net_id):
				_samples[n.net_id] = []
			_samples[n.net_id].append([_t, n.global_position, n.body.on_floor, n.body.hit_wall, n.yaw])


func _report(label: String) -> void:
	var w: Node = root.get_node("GameWorld")
	var vw: Node = w.call("world_for", 0)
	print("== %s (hour %.1f) player at %s" % [label, w.get("sky").get("time_of_day"), w.get("local_player").global_position])
	for id: int in _samples:
		var n: Node3D = w.call("entity", id)
		if n == null:
			print("npc %d vanished" % id)
			continue
		var s: Array = _samples[id]
		var travelled := 0.0
		var jumps := 0
		var off_floor := 0
		var walls := 0
		var yaw_change := 0.0
		for i in range(1, s.size()):
			var d: float = (s[i][1] as Vector3).distance_to(s[i - 1][1])
			travelled += d
			if d > 2.0:
				jumps += 1
			if not s[i][2]:
				off_floor += 1
			if s[i][3]:
				walls += 1
			yaw_change += absf(angle_difference(s[i - 1][4], s[i][4]))
		var p: Vector3 = n.global_position
		var g: float = vw.ground_below(p.x, p.y + 2.0, p.z, 6.0)
		print("%-20s %-10s act %d door %s pos %s ground %.2f walked %.1f jumps %d off_floor %d/%d walls %d rec %d replans %d overlap %s" % [
			n.display_name, n.role, n.act, str(not (n.home_door as Dictionary).is_empty()), str(p.snapped(Vector3.ONE * 0.1)), g, travelled, jumps,
			off_floor, s.size(), walls, n.recoveries, n.replans_total, str(n.body._overlaps(vw, p))])
	var lay: Variant = null
	for n in w.call("all_entities"):
		if n.get("kind") == "npc" and n.get("layout") != null:
			lay = n.get("layout")
			break
	if lay != null:
		print("doors: ", lay.doors.size())
		for d in lay.doors:
			print("   ", d["pos"], " out ", d["out"], " w ", d["width"], " hall ", d["hall"])
		var d0: Dictionary = lay.doors[0]
		var c := Vector3i((d0["pos"] as Vector3).floor())
		var o: Vector3 = d0["out"]
		for y in range(c.y - 2, c.y + 4):
			var row := "y %d: " % y
			for k in range(-3, 4):
				var p := c + Vector3i(roundi(o.x * k), y - c.y, roundi(o.z * k))
				row += "%3d/%.2f " % [vw.get_block(p), vw.voxel_field(p)]
			print(row)
		for k in range(-3, 4):
			var q: Vector3 = (d0["pos"] as Vector3) + o * (k * 0.5)
			print("  along %.1f stand %s ground %.3f" % [k * 0.5, str(load("res://entities/npc/npc_nav.gd").stand_height(vw, 0, q.x, q.z, q.y)), vw.ground_below(q.x, q.y + 1.5, q.z, 4.0)])
