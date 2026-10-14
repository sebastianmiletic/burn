class_name GrassPatch
extends MultiMeshInstance3D
## A field of instanced grass blades scattered over a rectangle, skipping
## circular holes (paving, puddles). Blades sway in the shader.

@export var area := Rect2(-20, -20, 40, 40)
@export var count := 30000
@export var seed_value := 7

var holes: Array[Vector3] = []  ## (x, z, radius)


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = MeshFactory.grass_blade(0.55, 0.06, 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var transforms: Array[Transform3D] = []
	var tries := 0
	while transforms.size() < count and tries < count * 4:
		tries += 1
		var x := rng.randf_range(area.position.x, area.end.x)
		var z := rng.randf_range(area.position.y, area.end.y)
		if _in_hole(x, z, rng.randf() * 0.8):
			continue
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		basis = basis.rotated(basis.x, rng.randf_range(-0.15, 0.15))
		var s := rng.randf_range(0.6, 1.5)
		basis = basis.scaled(Vector3(rng.randf_range(0.8, 1.3), s, 1.0))
		transforms.append(Transform3D(basis, Vector3(x, 0.0, z)))
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	multimesh = mm
	material_override = MaterialLibrary.grass()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _in_hole(x: float, z: float, feather: float) -> bool:
	for h in holes:
		if Vector2(x - h.x, z - h.y).length() < h.z + feather:
			return true
	return false
