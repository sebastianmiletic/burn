class_name Relic
extends Node3D
## The rotating model for the renderer test: a stone torus knot around a
## glowing ember core, on a pedestal. Exercises solid glyphs, edge glyphs on
## a moving silhouette, and emissive pass-through.

@export var spin_speed := 0.35
@export var tilt_speed := 0.11

var _knot: MeshInstance3D
var _core: MeshInstance3D
var _t := 0.0


func _ready() -> void:
	var stone := MaterialLibrary.stone(&"ruin")
	_add_box(Vector3(1.6, 0.3, 1.6), Vector3(0, 0.15, 0), stone)
	_add_box(Vector3(1.1, 0.9, 1.1), Vector3(0, 0.75, 0), stone)
	_add_box(Vector3(1.4, 0.22, 1.4), Vector3(0, 1.31, 0), stone)

	_knot = MeshInstance3D.new()
	_knot.mesh = MeshFactory.torus_knot(2, 3, 1.15, 0.17, 220, 14)
	_knot.material_override = MaterialLibrary.stone(&"dark")
	_knot.position = Vector3(0, 2.75, 0)
	add_child(_knot)

	_core = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	_core.mesh = sphere
	_core.material_override = MaterialLibrary.emissive(Color(1.0, 0.42, 0.12), 5.0)
	_core.position = _knot.position
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)

	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.45, 0.15)
	glow.light_energy = 1.4
	glow.omni_range = 5.0
	glow.position = _knot.position
	glow.shadow_enabled = false
	glow.light_volumetric_fog_energy = 1.0
	add_child(glow)


func _process(delta: float) -> void:
	_t += delta
	_knot.rotation = Vector3(sin(_t * tilt_speed) * 0.6, _t * spin_speed, cos(_t * tilt_speed * 0.7) * 0.3)
	var pulse := 1.0 + sin(_t * 2.1) * 0.08
	_core.scale = Vector3.ONE * pulse


func _add_box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
