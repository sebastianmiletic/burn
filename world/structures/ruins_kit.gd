class_name RuinsKit
extends RefCounted
## Modular ruin pieces built from primitive meshes with the stone material.
## Every builder returns a Node3D whose origin sits on the ground.
## (Milestone 2 extends this kit with stairs, floors, gates and the crypt.)


static func pillar(height: float, radius: float, broken: bool, seed_value: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var root := Node3D.new()
	root.name = "Pillar"
	var stone := MaterialLibrary.stone(&"ruin")
	_box(root, Vector3(radius * 2.8, 0.35, radius * 2.8), Vector3(0, 0.175, 0), stone)
	_box(root, Vector3(radius * 2.4, 0.2, radius * 2.4), Vector3(0, 0.45, 0), stone)
	var shaft_h := height * (rng.randf_range(0.35, 0.7) if broken else 1.0)
	# Drums: a stack of short cylinders, each slightly offset like settled masonry.
	var drums := maxi(2, int(shaft_h / 0.9))
	var drum_h := shaft_h / drums
	for i in drums:
		var drum := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = radius * (0.96 if i == drums - 1 else 1.0)
		cyl.bottom_radius = radius
		cyl.height = drum_h - 0.02
		cyl.radial_segments = 14
		cyl.rings = 1
		drum.mesh = cyl
		drum.position = Vector3(rng.randf_range(-0.02, 0.02), 0.55 + drum_h * (i + 0.5), rng.randf_range(-0.02, 0.02))
		drum.rotation.y = rng.randf() * TAU
		drum.material_override = stone
		root.add_child(drum)
	if broken:
		# The fallen top lies at the foot of the pillar.
		var fallen := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = radius
		cyl.bottom_radius = radius
		cyl.height = height * 0.35
		cyl.radial_segments = 14
		fallen.mesh = cyl
		var a := rng.randf() * TAU
		fallen.position = Vector3(cos(a) * (height * 0.3), radius, sin(a) * (height * 0.3))
		fallen.rotation = Vector3(0.0, a, PI * 0.5)
		fallen.material_override = stone
		root.add_child(fallen)
	else:
		_box(root, Vector3(radius * 2.6, 0.3, radius * 2.6), Vector3(0, 0.55 + shaft_h + 0.15, 0), stone)
	return root


static func arch(width: float, height: float, depth: float, seed_value: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var root := Node3D.new()
	root.name = "Arch"
	var stone := MaterialLibrary.stone(&"ruin")
	var ring := 0.75
	var r := (width - ring * 2.0) * 0.5  # inner radius of the opening
	var spring := height - r - ring
	for side: float in [-1.0, 1.0]:
		_box(root, Vector3(ring, spring, depth), Vector3(side * (r + ring * 0.5), spring * 0.5, 0), stone)
	# Voussoirs around a semicircle, with a couple missing for the ruin look.
	var stones := 13
	var mid := r + ring * 0.5
	for i in stones:
		if i in [3, 4] and rng.randf() < 0.7:
			continue
		var a := PI * (float(i) + 0.5) / float(stones)
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(ring, mid * PI / float(stones) * 0.96, depth)
		mi.mesh = box
		mi.position = Vector3(cos(a) * mid, spring + sin(a) * mid, 0)
		mi.rotation.z = a
		mi.material_override = stone
		root.add_child(mi)
	return root


static func wall(length: float, height: float, thickness: float, seed_value: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var root := Node3D.new()
	root.name = "Wall"
	var stone := MaterialLibrary.stone(&"ruin")
	var block := 1.1
	var count := int(length / block)
	for i in count:
		var h := height * (0.35 + 0.65 * absf(sin(float(i) * 0.7 + rng.randf() * 1.5)))
		var courses := maxi(1, int(h / 0.55))
		for c in courses:
			var w := block * rng.randf_range(0.9, 1.0)
			var bh := h / courses
			_box(root, Vector3(w, bh - 0.03, thickness * rng.randf_range(0.9, 1.0)),
					Vector3(-length * 0.5 + (i + 0.5) * block + rng.randf_range(-0.03, 0.03), bh * (c + 0.5), rng.randf_range(-0.04, 0.04)), stone)
	return root


static func steps(count: int, width: float, tread: float, rise: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Steps"
	var stone := MaterialLibrary.stone(&"ruin")
	for i in count:
		var depth := tread * float(count - i)
		_box(root, Vector3(width, rise, depth), Vector3(0, rise * (i + 0.5), -depth * 0.5), stone)
	return root


static func rubble(count: int, radius: float, seed_value: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var root := Node3D.new()
	root.name = "Rubble"
	var stone := MaterialLibrary.stone(&"ruin")
	for i in count:
		var mi := MeshInstance3D.new()
		var size := rng.randf_range(0.12, 0.45)
		mi.mesh = MeshFactory.rock(size, seed_value * 31 + i)
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * radius
		mi.position = Vector3(cos(a) * d, size * 0.3, sin(a) * d)
		mi.rotation = Vector3(rng.randf() * 0.5, rng.randf() * TAU, rng.randf() * 0.5)
		mi.material_override = stone
		root.add_child(mi)
	return root


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi
