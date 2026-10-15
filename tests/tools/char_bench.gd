extends SceneTree
## Character smoke test + benchmark (headless):
##   godot --headless --path . -s res://tests/tools/char_bench.gd
## Builds every humanoid style, reports mesh build time / triangles, then drives
## 20 characters through walk/run/jump/attack/die and reports the CPU cost of a
## model update (GDScript animation + IK + cloth; skinning itself is on the GPU).


var _ran := false


func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		load("res://tests/tools/char_bench_impl.gd").new().run(self)
	return false
