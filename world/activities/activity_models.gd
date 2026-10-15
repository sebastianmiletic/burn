class_name ActivityModels
extends RefCounted
## Procedural models for the activities: buried chest, bounty board, meteorite,
## the Proving Ring (standing stones, braziers, war horn), footprints and the
## "X marks the spot" mound. Built from the item kit's meshes and materials
## (bevelled planks, lathed metal, displaced rock, molten veins) so they sit
## with the rest of the hand-made props; nothing is a voxel cube.

static func _p(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	return ModelKit.part(parent, mesh, mat, pos, rot, scl)


static func _wood(c := Color(0.45, 0.3, 0.17), grain := Vector3.RIGHT) -> Material:
	return ItemMats.wood(c, c.darkened(0.45), grain)


# --- Treasure chest ---------------------------------------------------------------------

## Iron-bound oak chest, 0.9 x 0.55 x 0.6 m, front facing +Z. Returns the lid pivot.
static func chest(root: Node3D, seed_value := 0) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var iron := ItemMats.metal("dark_iron")
	var brass := ItemMats.metal("brass")
	var w := 0.9
	var d := 0.58
	var h := 0.48
	# Body: horizontal planks on every side.
	for i in 4:
		var y := 0.06 + i * 0.115
		var c := Color(0.42, 0.27, 0.15).darkened(rng.randf_range(0.0, 0.18))
		for side: float in [-1.0, 1.0]:
			_p(root, ItemMesh.bevel_box(Vector3(w, 0.11, 0.035), 0.008), _wood(c), Vector3(0, y, side * (d * 0.5 - 0.0175)))
			_p(root, ItemMesh.bevel_box(Vector3(0.035, 0.11, d - 0.07), 0.008), _wood(c, Vector3.BACK), Vector3(side * (w * 0.5 - 0.0175), y, 0))
	_p(root, ItemMesh.bevel_box(Vector3(w - 0.04, 0.03, d - 0.04), 0.006), _wood(Color(0.3, 0.2, 0.11)), Vector3(0, 0.015, 0))
	# Iron corner straps and bands.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_p(root, ItemMesh.bevel_box(Vector3(0.06, h, 0.06), 0.006), iron, Vector3(sx * (w * 0.5 - 0.02), h * 0.5, sz * (d * 0.5 - 0.02)))
	for bx: float in [-0.28, 0.28]:
		_p(root, ItemMesh.bevel_box(Vector3(0.05, 0.012, d + 0.012), 0.003), iron, Vector3(bx, h - 0.01, 0))
		for side: float in [-1.0, 1.0]:
			_p(root, ItemMesh.bevel_box(Vector3(0.05, h, 0.012), 0.003), iron, Vector3(bx, h * 0.5, side * (d * 0.5 + 0.004)))
	# Lid: a barrel-vaulted top hinged at the back.
	var lid := Node3D.new()
	lid.name = "Lid"
	lid.position = Vector3(0, h, -d * 0.5)
	root.add_child(lid)
	for i in 7:
		var a := lerpf(-PI * 0.5, PI * 0.5, (float(i) + 0.5) / 7.0)
		var r := d * 0.5
		var p := Vector3(0, cos(a) * r * 0.55, d * 0.5 + sin(a) * r)
		var c := Color(0.44, 0.29, 0.16).darkened(rng.randf_range(0.0, 0.2))
		_p(lid, ItemMesh.bevel_box(Vector3(w - 0.01, 0.035, r * PI / 7.0 + 0.012), 0.006), _wood(c), p, Vector3(rad_to_deg(a) * 0.95, 0, 0))
	for bx: float in [-0.28, 0.28]:
		for i in 7:
			var a := lerpf(-PI * 0.5, PI * 0.5, (float(i) + 0.5) / 7.0)
			var r := d * 0.5 + 0.015
			_p(lid, ItemMesh.bevel_box(Vector3(0.052, 0.012, r * PI / 7.0 + 0.02), 0.003), iron, Vector3(bx, cos(a) * r * 0.55, d * 0.5 + sin(a) * r), Vector3(rad_to_deg(a) * 0.95, 0, 0))
	# Lock plate and hasp.
	_p(root, ItemMesh.bevel_box(Vector3(0.12, 0.14, 0.02), 0.006), brass, Vector3(0, h - 0.08, d * 0.5 + 0.012))
	_p(root, ModelKit.cylinder(0.012, 0.012, 0.025, 8), ItemMats.glow(Color(0.0, 0.0, 0.0), 0.0), Vector3(0, h - 0.09, d * 0.5 + 0.02), Vector3(90, 0, 0))
	_p(lid, ItemMesh.bevel_box(Vector3(0.06, 0.1, 0.015), 0.004), brass, Vector3(0, -0.02, d + 0.01))
	# Rivets.
	for sx: float in [-1.0, 1.0]:
		for y: float in [0.1, 0.25, 0.4]:
			_p(root, ModelKit.sphere(0.009, 6), brass, Vector3(sx * (w * 0.5 - 0.02), y, d * 0.5 + 0.012))
	return lid


## Gold, gems and an idol that glint inside an open chest.
static func hoard(root: Node3D) -> void:
	var gold := ItemMats.metal("gold")
	for i in 18:
		var a := float(i) * 2.399
		var r := 0.05 + 0.25 * sqrt(float(i) / 18.0)
		_p(root, ModelKit.cylinder(0.035, 0.035, 0.008, 10), gold, Vector3(cos(a) * r * 1.3, 0.38 + sin(float(i)) * 0.02, sin(a) * r * 0.7), Vector3(randf_range(-30, 30), 0, randf_range(-30, 30)))
	_p(root, ItemMesh.gem_cut(0.035, 8), ItemMats.gem(Color(0.9, 0.1, 0.18), 0.05, 0.6), Vector3(0.12, 0.42, 0.04))
	_p(root, ItemMesh.gem_cut(0.03, 10), ItemMats.gem(Color(0.15, 0.35, 1.0), 0.05, 0.6), Vector3(-0.16, 0.41, -0.05))


## Disturbed earth with two crossed stakes: X marks the spot.
static func dig_mark(root: Node3D, seed_value := 0) -> void:
	var earth := ItemMats.stone(Color(0.3, 0.22, 0.14), Color(0.18, 0.12, 0.07), 0.95, 4.0)
	for i in 5:
		var a := float(i) * 1.7 + seed_value
		_p(root, ItemMesh.rock(0.28, seed_value + i, 0.25, 2, Vector3(1.4, 0.3, 1.1)), earth, Vector3(cos(a) * 0.35, 0.02, sin(a) * 0.3))
	var stake := _wood(Color(0.5, 0.36, 0.2), Vector3.UP)
	for s: float in [-1.0, 1.0]:
		_p(root, ModelKit.cylinder(0.02, 0.028, 0.95, 6), stake, Vector3(0, 0.35, 0), Vector3(0, 45.0 * s, 32.0))
	var rope := ItemMats.cloth(Color(0.7, 0.6, 0.4))
	_p(root, ModelKit.cylinder(0.032, 0.032, 0.05, 8), rope, Vector3(0, 0.38, 0))
	_p(root, ItemMesh.plate_even(PackedVector2Array([Vector2(0, 0), Vector2(0.16, 0.0), Vector2(0.16, 0.1), Vector2(0, 0.1)]), 0.002), ItemMats.cloth(Color(0.75, 0.15, 0.1)), Vector3(0.0, 0.7, 0.0), Vector3(0, 30, 0))


# --- Bounty board -----------------------------------------------------------------------

## A roofed notice board on two posts with pinned contracts, ~2.4 m tall, facing +Z.
static func board(root: Node3D) -> Array:
	var post := ItemMats.bark(Color(0.32, 0.23, 0.15))
	var plank := Color(0.48, 0.33, 0.19)
	for sx: float in [-0.85, 0.85]:
		_p(root, ItemMesh.lathe(PackedVector2Array([Vector2(0.09, 0.0), Vector2(0.085, 1.2), Vector2(0.075, 2.25)]), 9, true), post, Vector3(sx, 0, 0))
		_p(root, ItemMesh.rock(0.16, int(sx * 10.0) + 4, 0.2, 2, Vector3(1.0, 0.45, 1.0)), ItemMats.stone(Color(0.42, 0.4, 0.37)), Vector3(sx, 0.03, 0))
	# Backing boards.
	for i in 5:
		var y := 0.95 + i * 0.2
		_p(root, ItemMesh.bevel_box(Vector3(1.6, 0.19, 0.04), 0.01), _wood(plank.darkened(0.06 * (i % 3))), Vector3(0, y, 0.0))
	_p(root, ItemMesh.bevel_box(Vector3(1.74, 0.08, 0.07), 0.01), _wood(plank.darkened(0.25)), Vector3(0, 0.88, 0.01))
	_p(root, ItemMesh.bevel_box(Vector3(1.74, 0.08, 0.07), 0.01), _wood(plank.darkened(0.25)), Vector3(0, 1.92, 0.01))
	# Little gable roof.
	for side: float in [-1.0, 1.0]:
		_p(root, ItemMesh.bevel_box(Vector3(2.1, 0.04, 0.5), 0.01), _wood(Color(0.33, 0.22, 0.13)), Vector3(0, 2.3, side * 0.2), Vector3(side * 32.0, 0, 0))
	_p(root, ModelKit.cylinder(0.035, 0.035, 2.15, 8), post, Vector3(0, 2.43, 0), Vector3(0, 0, 90))
	# Notices: parchment sheets with a red seal each; returned so the board can show
	# how many contracts are posted.
	var notes: Array = []
	var paper := ItemMats.cloth(Color(0.86, 0.79, 0.62))
	var seal := ItemMats.make({"albedo": Color(0.6, 0.08, 0.06), "roughness": 0.4})
	for i in 3:
		var n := Node3D.new()
		n.position = Vector3(-0.5 + i * 0.5, 1.42 + (0.06 if i == 1 else -0.03), 0.03)
		n.rotation_degrees = Vector3(0, 0, [-4.0, 3.0, -2.0][i])
		root.add_child(n)
		_p(n, ItemMesh.plate_even(PackedVector2Array([Vector2(-0.17, -0.24), Vector2(0.17, -0.24), Vector2(0.18, 0.22), Vector2(-0.16, 0.24)]), 0.002), paper, Vector3.ZERO, Vector3(0, 0, 0))
		_p(n, ModelKit.cylinder(0.03, 0.03, 0.008, 10), seal, Vector3(0, -0.15, 0.006), Vector3(90, 0, 0))
		_p(n, ModelKit.sphere(0.012, 6), ItemMats.metal("iron"), Vector3(0, 0.2, 0.008))
		notes.append(n)
	return notes


# --- Meteorite ----------------------------------------------------------------------------

## A fused lump of star-iron with glowing seams (~1.6 m across).
static func meteorite(root: Node3D, seed_value: int) -> MeshInstance3D:
	var core := _p(root, ItemMesh.rock(0.8, seed_value, 0.32, 3, Vector3(1.15, 0.85, 1.0)), ItemMats.molten(Color(0.12, 0.11, 0.13), Color(1.0, 0.42, 0.12), 7.0), Vector3(0, 0.55, 0))
	var star := ItemMats.make({"albedo": Color(0.35, 0.4, 0.55), "accent": Color(0.15, 0.17, 0.25), "metallic": 0.9, "roughness": 0.3,
		"finish": ItemMats.Finish.ORE, "emission_mode": ItemMats.Emit.SHIMMER, "emission_color": Color(0.5, 0.65, 1.0), "emission_energy": 1.6})
	for i in 6:
		var a := float(i) * 1.05 + seed_value
		_p(root, ItemMesh.crystal(0.07, 0.35 + 0.1 * (i % 3), 5), star, Vector3(cos(a) * 0.55, 0.65 + 0.2 * sin(a * 2.0), sin(a) * 0.5), Vector3(rad_to_deg(sin(a)) * 40.0, 0, rad_to_deg(cos(a)) * 40.0))
	return core


# --- Proving Ring -------------------------------------------------------------------------

static func standing_stone(root: Node3D, height: float, seed_value: int, pos: Vector3, yaw: float) -> void:
	var stone := MaterialLibrary.stone(&"dark")
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = yaw
	root.add_child(n)
	_p(n, ItemMesh.rock(0.5, seed_value, 0.18, 3, Vector3(0.75, height, 0.45)), stone, Vector3(0, height * 0.45, 0))
	# Carved ember rune near the top.
	_p(n, ItemMesh.bevel_box(Vector3(0.04, 0.32, 0.02), 0.004), ModelKit.glow(Color(1.0, 0.45, 0.15), 3.0), Vector3(0, height * 0.62, 0.22))
	_p(n, ItemMesh.bevel_box(Vector3(0.2, 0.04, 0.02), 0.004), ModelKit.glow(Color(1.0, 0.45, 0.15), 3.0), Vector3(0, height * 0.66, 0.22), Vector3(0, 0, 30))


## An iron brazier on three legs. Returns the bowl's top position (for fire).
static func brazier(root: Node3D, pos: Vector3) -> Vector3:
	var iron := ItemMats.metal("dark_iron")
	var n := Node3D.new()
	n.position = pos
	root.add_child(n)
	for i in 3:
		var a := TAU * float(i) / 3.0
		_p(n, ModelKit.cylinder(0.025, 0.03, 1.15, 6), iron, Vector3(cos(a) * 0.22, 0.55, sin(a) * 0.22), Vector3(rad_to_deg(sin(a)) * 12.0, 0, -rad_to_deg(cos(a)) * 12.0))
	_p(n, ItemMesh.lathe(PackedVector2Array([Vector2(0.06, 1.0), Vector2(0.3, 1.08), Vector2(0.38, 1.22), Vector2(0.34, 1.24), Vector2(0.27, 1.12), Vector2(0.0, 1.06)]), 14, true), iron)
	_p(n, ItemMesh.rock(0.2, 9, 0.3, 2, Vector3(1.3, 0.4, 1.3)), ItemMats.molten(Color(0.1, 0.08, 0.07), Color(1.0, 0.4, 0.1), 4.0), Vector3(0, 1.15, 0))
	return pos + Vector3(0, 1.25, 0)


## The war horn on its post, with a banner; faces +Z.
static func horn_post(root: Node3D) -> void:
	var wood := ItemMats.bark(Color(0.3, 0.21, 0.14))
	_p(root, ItemMesh.lathe(PackedVector2Array([Vector2(0.12, 0.0), Vector2(0.1, 1.6), Vector2(0.08, 2.6)]), 10, true), wood)
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 9:
		var t := float(i) / 8.0
		path.append(Vector3(-0.35 + t * 0.7, 1.45 + sin(t * PI) * 0.22, 0.14 + t * t * 0.1))
		radii.append(lerpf(0.02, 0.13, t * t))
	_p(root, ItemMesh.tube(path, radii, 10), ItemMats.bone(Color(0.9, 0.84, 0.7)))
	_p(root, ItemMesh.lathe(PackedVector2Array([Vector2(0.135, 0.0), Vector2(0.15, 0.02), Vector2(0.135, 0.04)]), 14, true), ItemMats.metal("brass"), path[8] + Vector3(-0.02, 0, 0), Vector3(0, 0, 90))
	_p(root, ModelKit.cylinder(0.015, 0.015, 1.2, 6), wood, Vector3(0, 2.45, 0), Vector3(0, 0, 90))
	var banner := ItemMats.cloth(Color(0.55, 0.12, 0.08))
	_p(root, ItemMesh.plate_even(PackedVector2Array([Vector2(-0.5, 0), Vector2(0.5, 0), Vector2(0.5, -1.0), Vector2(0.0, -1.25), Vector2(-0.5, -1.0)]), 0.004), banner, Vector3(0, 2.42, 0.02))
	_p(root, ItemMesh.gem_cut(0.08, 6), ItemMats.glow(Color(1.0, 0.6, 0.2), 2.5), Vector3(0, 1.95, 0.03), Vector3(90, 0, 0))


# --- Tracks -------------------------------------------------------------------------------

## One footprint mesh (pad + toes), flat, ~0.3 m long; front is -Z.
static func paw_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blobs := [[Vector2(0, 0.04), Vector2(0.075, 0.065)], [Vector2(-0.07, -0.07), Vector2(0.025, 0.035)], [Vector2(-0.025, -0.1), Vector2(0.025, 0.035)],
		[Vector2(0.025, -0.1), Vector2(0.025, 0.035)], [Vector2(0.07, -0.07), Vector2(0.025, 0.035)]]
	for b: Array in blobs:
		var c: Vector2 = b[0]
		var r: Vector2 = b[1]
		for i in 10:
			var a0 := TAU * float(i) / 10.0
			var a1 := TAU * float(i + 1) / 10.0
			var p0 := Vector3(c.x, 0, c.y)
			var p1 := Vector3(c.x + cos(a1) * r.x, 0, c.y + sin(a1) * r.y)
			var p2 := Vector3(c.x + cos(a0) * r.x, 0, c.y + sin(a0) * r.y)
			for tri: Array in [[p0, p1, p2], [p0, p2, p1]]:
				for v: Vector3 in tri:
					st.set_normal(Vector3.UP)
					st.add_vertex(v)
	return st.commit()
