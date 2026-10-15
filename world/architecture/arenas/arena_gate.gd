class_name ArenaGate
extends Node3D
## A modelled arena gate (portcullis, carved slab, web curtain) that follows
## the arena_gate collision: GameWorld closes the opening with invisible
## STRUCTURE cells when a boss fight starts and clears them when it ends.
## Styles: "drop" (slides down from `travel` m above), "rise" (rises from
## below the floor), "web" (silk grows across the opening).

const SPEED := 0.7   # fraction per second

var spawn_index := -1
var style := "drop"
var travel := 6.0
var _closed_xf := Transform3D.IDENTITY
var _t := 0.0          # 0 open .. 1 closed
var _target := 0.0
var _mesh: MeshInstance3D


func setup(g: Dictionary, material: Material) -> void:
	spawn_index = int(g["index"])
	style = String(g["style"])
	travel = float(g["travel"])
	var kit: ArenaKit = g["kit"]
	_closed_xf = g["xf"]
	_mesh = MeshInstance3D.new()
	var mesh := ArrayMesh.new()
	if not kit.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, kit.arrays())
	_mesh.mesh = mesh
	_mesh.material_override = ArenaMaterials.web() if style == "web" else material
	_mesh.visibility_range_end = 200.0
	add_child(_mesh)
	_apply()


func set_closed(closed: bool, snap := false) -> void:
	var target := 1.0 if closed else 0.0
	if target != _target and not snap and GameWorld.instance != null:
		Audio.play("door", global_transform * _closed_xf.origin, 6.0, 0.5 if style != "web" else 1.4)
		if style != "web":
			Audio.play("stomp", global_transform * _closed_xf.origin, 0.0, 0.7)
	_target = target
	if snap:
		_t = _target
		_apply()


func _process(delta: float) -> void:
	if is_equal_approx(_t, _target):
		return
	# Portcullises fall fast and rise slowly; webs knit quickly.
	var rate := SPEED * (1.8 if _target > _t and style == "drop" else 1.0)
	_t = move_toward(_t, _target, rate * delta)
	_apply()


func _apply() -> void:
	var e := _t * _t * (3.0 - 2.0 * _t)
	match style:
		"web":
			_mesh.visible = e > 0.01
			var s := maxf(e, 0.01)
			_mesh.transform = _closed_xf * Transform3D(Basis.from_scale(Vector3(s, s, 1.0)), Vector3.ZERO)
		"rise":
			_mesh.visible = e > 0.01
			_mesh.transform = Transform3D(_closed_xf.basis, _closed_xf.origin - _closed_xf.basis.y.normalized() * travel * (1.0 - e))
		_:
			_mesh.transform = Transform3D(_closed_xf.basis, _closed_xf.origin + _closed_xf.basis.y.normalized() * travel * (1.0 - e))
