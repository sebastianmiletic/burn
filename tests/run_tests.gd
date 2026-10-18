extends SceneTree
## Headless test runner:  godot --headless --path . -s res://tests/run_tests.gd
## Runs every tests/unit/test_*.gd (each extends TestCase). Exit code 1 on failure.
## `-- --only=voxel,flora` runs just the files whose names contain one of the words.


var _ran := false


## Runs on the first frame, after autoloads (Events, Audio, ...) exist.
func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_run()
	return false


func _run() -> void:
	var only := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.get_slice("=", 1).split(",", false)
	var dir := DirAccess.open("res://tests/unit")
	var files := PackedStringArray()
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			if not only.is_empty() and not Array(only).any(func(w: String) -> bool: return f.contains(w)):
				continue
			files.append(f)
	files.sort()

	var total := 0
	var failed := 0
	for f in files:
		var script: GDScript = load("res://tests/unit/" + f)
		if script == null or not script.can_instantiate():
			failed += 1
			print("FAIL  %s (does not compile)" % f)
			continue
		var case: TestCase = script.new()
		var n := case.run()
		total += n
		if case.failures.is_empty():
			print("PASS  %s (%d tests)" % [f, n])
		else:
			failed += case.failures.size()
			print("FAIL  %s" % f)
			for msg in case.failures:
				print("      ", msg)
	print("%d tests, %d failures" % [total, failed])
	quit(1 if failed > 0 else 0)
