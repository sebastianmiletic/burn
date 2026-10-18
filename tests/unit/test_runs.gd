extends TestCase
## Unlimited runs (SaveSystem) next to the old numbered slot files.

var _dir_before := ""


func _use_temp_dir() -> void:
	_dir_before = SaveSystem.DIR
	SaveSystem.DIR = RuntimePaths.file("runs_test_%d" % randi())
	DirAccess.make_dir_recursive_absolute(SaveSystem.DIR)


func _restore() -> void:
	var d := DirAccess.open(SaveSystem.DIR)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(SaveSystem.DIR.path_join(f))
	DirAccess.remove_absolute(SaveSystem.DIR)
	SaveSystem.DIR = _dir_before


func _world(seed_value: int, name: String, t: float) -> Dictionary:
	return {"seed": seed_value, "player": {"name": name, "xp": 0}, "play_time": t, "location_name": "Ashfall", "edits": {}}


func test_paths_keep_old_slot_files() -> void:
	check_eq(SaveSystem.run_id(2), "slot_2")
	check(SaveSystem.path(2).ends_with("/slot_2.burn"), "old slots keep their file")
	check(SaveSystem.fog_path(2).ends_with("/map_fog_2.burn"), "old slots keep their map file")
	check(SaveSystem.path("ab12").ends_with("/run_ab12.burn"))
	check(SaveSystem.fog_path("ab12").ends_with("/map_fog_run_ab12.burn"))
	check(not SaveSystem.valid_id("../x"), "ids with path characters are refused")


func test_unlimited_runs_list_newest_first() -> void:
	_use_temp_dir()
	# An old-style save written the way earlier builds did (no .meta file).
	SaveSystem.write(1, _world(11, "Old", 30.0))
	DirAccess.remove_absolute(SaveSystem.meta_path(1))
	var ids := []
	for i in 5:
		var id := SaveSystem.new_id()
		SaveSystem.create_meta(id, "Run %d" % i, 100 + i, i % 3)
		SaveSystem.write(id, _world(100 + i, "W%d" % i, 10.0 * i))
		ids.append(id)
	var runs := SaveSystem.list_runs()
	check_eq(runs.size(), 6, "more than three runs")
	var legacy := SaveSystem.summary(1)
	check_eq(String(legacy["title"]), "Hearth II", "old slot gets a title")
	check_eq(int(legacy["seed"]), 11)
	check(FileAccess.file_exists(SaveSystem.meta_path(1)), "summary cached")
	check_eq(SaveSystem.read(1).get("seed"), 11, "old slot still loads")
	var s := SaveSystem.summary(ids[2])
	check_eq(String(s["title"]), "Run 2")
	check_eq(int(s["difficulty"]), 2)
	check(float(s["created_at"]) > 0.0)
	for i in runs.size() - 1:
		check(maxf(runs[i]["saved_at"], runs[i]["created_at"]) >= maxf(runs[i + 1]["saved_at"], runs[i + 1]["created_at"]), "sorted newest first")
	SaveSystem.rename(ids[0], "  Renamed  ")
	check_eq(String(SaveSystem.summary(ids[0])["title"]), "Renamed")
	SaveSystem.write(ids[0], _world(100, "W0", 99.0))
	check_eq(String(SaveSystem.summary(ids[0])["title"]), "Renamed", "a rename survives saving")
	check_eq(String(SaveSystem.read(ids[0])["run"]["title"]), "Renamed", "title travels in the save")
	var f := FileAccess.open(SaveSystem.fog_path(ids[1]), FileAccess.WRITE)
	f.store_var({})
	f.close()
	SaveSystem.delete(ids[1])
	check(not SaveSystem.exists(ids[1]) and not FileAccess.file_exists(SaveSystem.fog_path(ids[1])) \
			and not FileAccess.file_exists(SaveSystem.meta_path(ids[1])), "delete removes save, map and summary")
	check_eq(SaveSystem.list_runs().size(), 5)
	_restore()


func test_seed_text() -> void:
	var game: Script = load("res://core/game.gd")
	check_eq(game.call("seed_from_text", "1234"), 1234)
	check_eq(game.call("seed_from_text", "ash and ember"), game.call("seed_from_text", "ash and ember"), "phrases are stable")
	check(int(game.call("seed_from_text", "")) >= 0)
