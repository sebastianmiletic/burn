extends SceneTree
## Headless test runner:  godot --headless --path . -s res://tests/run_tests.gd
## Runs every tests/unit/test_*.gd (each extends TestCase). Exit code 1 on failure.
## `-- --only=voxel,swim` runs only the files whose names contain one of those words.


var _ran := false


## Runs on the first frame, after autoloads (Events, Audio, ...) exist.
func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_run()
	return false


func _run() -> void:
	var dir := DirAccess.open("res://tests/unit")
	var files := PackedStringArray()
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			var words := a.trim_prefix("--only=").split(",", false)
			var kept := PackedStringArray()
			for f in files:
				for word in words:
					if word in f:
						kept.append(f)
						break
			files = kept

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
