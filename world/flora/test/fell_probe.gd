extends SceneTree
## Headless probe of the felling FX timeline:
##   godot --headless --path . -s res://world/flora/test/fell_probe.gd

var _root: Node3D
var _t := 0.0
var _fx: Node3D


func _process(delta: float) -> bool:
	if _root == null:
		_root = Node3D.new()
		root.add_child(_root)
		Flora.fell(_root, Vector3(3, 1, 4), Flora.OAK, 9.0, 42, Vector3(1, 0, 0))
		_fx = _root.get_child(0)
		return false
	_t += delta
	if not is_instance_valid(_fx):
		print("t=%.2f fx freed" % _t)
		quit()
		return true
	var mesh: MeshInstance3D = _fx.get_child(0).get_child(0)
	var top := mesh.global_transform * Vector3(0, 1, 0)
	if int(_t * 10.0) % 3 == 0:
		print("t=%.2f top=%s visible=%s children=%d" % [_t, str(top.snapped(Vector3.ONE * 0.01)), mesh.visible, _fx.get_child_count()])
	return false
