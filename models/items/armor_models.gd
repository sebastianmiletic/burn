class_name ArmorModels
extends RefCounted
## Armour pieces as standalone objects (icons, held, displayed): helm,
## cuirass, greaves and sabatons per metal tier. Centred near the origin,
## front facing +Z.


static func _p(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	return ModelKit.part(parent, mesh, mat, pos, rot, scl)


static func build(parent: Node3D, piece: String, tier: String) -> void:
	match piece:
		"helmet":
			helmet(parent, tier)
		"chestplate":
			chestplate(parent, tier)
		"greaves":
			greaves(parent, tier)
		"boots":
			boots(parent, tier)


static func _rivets(parent: Node3D, y: float, r: float, squash: Vector2, n: int, mat: Material, from_deg := 0.0, to_deg := 360.0) -> void:
	for i in n:
		var a := deg_to_rad(lerpf(from_deg, to_deg, (float(i) + 0.5) / float(n)))
		_p(parent, ModelKit.sphere(0.0045, 6), mat, Vector3(cos(a) * r * squash.x, y, sin(a) * r * squash.y))


static func helmet(parent: Node3D, tier: String) -> void:
	var m := ItemMats.metal(tier)
	var trim := ItemMats.trim(tier)
	var squash := Vector2(0.9, 1.04)
	var prof := PackedVector2Array([Vector2(0.112, -0.06), Vector2(0.118, -0.03), Vector2(0.122, 0.02), Vector2(0.12, 0.07), Vector2(0.11, 0.115),
		Vector2(0.088, 0.155), Vector2(0.056, 0.182), Vector2(0.02, 0.195), Vector2(0.0, 0.197)])
	if tier in ["copper", "bronze"]:
		# Taller, conical "spangen" helm.
		prof = PackedVector2Array([Vector2(0.112, -0.06), Vector2(0.118, -0.02), Vector2(0.12, 0.03), Vector2(0.11, 0.09), Vector2(0.085, 0.15),
			Vector2(0.05, 0.2), Vector2(0.018, 0.235), Vector2(0.0, 0.245)])
	_p(parent, ItemMesh.lathe(prof, 20, true, squash), m)
	# Brow band with rivets.
	var band := PackedVector2Array([Vector2(0.121, -0.012), Vector2(0.126, -0.006), Vector2(0.127, 0.018), Vector2(0.123, 0.024)])
	_p(parent, ItemMesh.lathe(band, 20, true, squash), trim)
	_rivets(parent, 0.006, 0.128, squash, 12, trim)
	# Crest ridge front-to-back.
	var ridge := PackedVector3Array()
	var rr := PackedFloat32Array()
	for i in 9:
		var a := deg_to_rad(lerpf(-75.0, 75.0, float(i) / 8.0))
		ridge.append(Vector3(0, -0.005 + cos(a) * 0.2, sin(a) * 0.125 * 1.04))
		rr.append(0.007)
	if tier not in ["copper"]:
		_p(parent, ItemMesh.tube(ridge, rr, 6), trim)
	# Nasal guard and cheek plates.
	var nasal := PackedVector2Array([Vector2(-0.012, 0.02), Vector2(0.012, 0.02), Vector2(0.009, -0.075), Vector2(0.0, -0.085), Vector2(-0.009, -0.075)])
	_p(parent, ItemMesh.plate_even(nasal, 0.004, 0.0015), m, Vector3(0, -0.01, 0.128), Vector3(-8, 0, 0))
	for side: float in [-1.0, 1.0]:
		var cheek := PackedVector2Array([Vector2(-0.045, 0.0), Vector2(0.045, 0.0), Vector2(0.04, -0.07), Vector2(0.0, -0.11), Vector2(-0.035, -0.08)])
		_p(parent, ItemMesh.plate_even(cheek, 0.004, 0.0015), m, Vector3(side * 0.1, -0.06, 0.035), Vector3(6, side * 62.0, side * -4.0))
		_p(parent, ModelKit.sphere(0.006, 6), trim, Vector3(side * 0.104, -0.065, 0.06))
	match tier:
		"bronze":
			_plume(parent, Color(0.7, 0.1, 0.08))
		"steel":
			_plume(parent, Color(0.85, 0.82, 0.75))
		"mithril":
			for side: float in [-1.0, 1.0]:
				var wing := PackedVector2Array([Vector2(0, 0), Vector2(0.03, 0.02), Vector2(0.06, 0.08), Vector2(0.075, 0.15), Vector2(0.05, 0.12), Vector2(0.035, 0.1), Vector2(0.02, 0.05)])
				_p(parent, ItemMesh.plate_even(wing, 0.004, 0.0015), m, Vector3(side * 0.11, 0.06, -0.01), Vector3(0, side * 80.0 + 90.0, 0), Vector3(1, 1, 1))
			_p(parent, ItemMesh.gem_cut(0.014, 8, 0.4, 0.5), GearModels.gem_for(tier), Vector3(0, 0.03, 0.133), Vector3(90, 0, 0))
		"adamantite":
			for i in 5:
				var a := deg_to_rad(lerpf(-50.0, 50.0, float(i) / 4.0))
				_p(parent, ModelKit.cone(0.012, 0.06, 5), trim, Vector3(0, 0.185 + cos(a) * 0.01, sin(a) * 0.14), Vector3(rad_to_deg(a), 0, 0))
		"infernal":
			for side: float in [-1.0, 1.0]:
				var horn := PackedVector3Array([Vector3(side * 0.1, 0.1, 0.0), Vector3(side * 0.16, 0.14, 0.0), Vector3(side * 0.19, 0.21, -0.02), Vector3(side * 0.18, 0.28, -0.05)])
				_p(parent, ItemMesh.tube(horn, PackedFloat32Array([0.026, 0.019, 0.011, 0.002]), 8), ItemMats.metal("dark_iron"))
			_p(parent, ItemMesh.bevel_box(Vector3(0.11, 0.008, 0.01), 0.002), ItemMats.glow(Color(1.0, 0.4, 0.08), 6.0), Vector3(0, 0.04, 0.122))


static func _plume(parent: Node3D, c: Color) -> void:
	var path := PackedVector3Array([Vector3(0, 0.19, 0.06), Vector3(0, 0.235, 0.0), Vector3(0, 0.23, -0.08), Vector3(0, 0.17, -0.16), Vector3(0, 0.08, -0.2)])
	_p(parent, ItemMesh.tube(path, PackedFloat32Array([0.012, 0.022, 0.026, 0.02, 0.006]), 8), ItemMats.cloth(c), Vector3.ZERO, Vector3.ZERO, Vector3(0.7, 1, 1))


static func chestplate(parent: Node3D, tier: String) -> void:
	var m := ItemMats.metal(tier)
	var trim := ItemMats.trim(tier)
	var sq := Vector2(1.0, 0.64)
	var prof := PackedVector2Array([Vector2(0.135, -0.17), Vector2(0.142, -0.13), Vector2(0.15, -0.06), Vector2(0.166, 0.02), Vector2(0.178, 0.09),
		Vector2(0.172, 0.15), Vector2(0.14, 0.19), Vector2(0.09, 0.21), Vector2(0.06, 0.212)])
	_p(parent, ItemMesh.lathe(prof, 24, true, sq), m)
	# Gorget ring at the neck.
	_p(parent, ItemMesh.lathe(PackedVector2Array([Vector2(0.075, 0.2), Vector2(0.08, 0.215), Vector2(0.07, 0.235), Vector2(0.06, 0.24)]), 18, true, Vector2(1.0, 0.85)), trim)
	# Central ridge down the front, following the plate.
	var ridge := PackedVector3Array()
	var rr := PackedFloat32Array()
	for i in prof.size() - 2:
		var p := prof[i]
		ridge.append(Vector3(0, p.y, p.x * sq.y + 0.001))
		rr.append(0.006)
	_p(parent, ItemMesh.tube(ridge, rr, 6), m)
	# Fauld lames and a belt.
	for i in 3:
		var y := -0.18 - i * 0.026
		var r := 0.14 + i * 0.008
		_p(parent, ItemMesh.lathe(PackedVector2Array([Vector2(r - 0.004, y - 0.014), Vector2(r, y - 0.01), Vector2(r, y + 0.012), Vector2(r - 0.01, y + 0.016)]), 22, true, sq), m)
		_rivets(parent, y, r + 0.002, sq, 8, trim, 20.0, 160.0)
	_p(parent, ItemMesh.lathe(PackedVector2Array([Vector2(0.142, -0.15), Vector2(0.147, -0.145), Vector2(0.148, -0.12), Vector2(0.143, -0.115)]), 22, true, sq), ItemMats.leather(Color(0.25, 0.15, 0.09)))
	_p(parent, ItemMesh.bevel_box(Vector3(0.03, 0.03, 0.01), 0.003), trim, Vector3(0, -0.133, 0.096))
	# Pauldrons: layered domes on the shoulders.
	for side: float in [-1.0, 1.0]:
		var dome := PackedVector2Array([Vector2(0.075, -0.015), Vector2(0.074, 0.01), Vector2(0.062, 0.04), Vector2(0.038, 0.062), Vector2(0.0, 0.07)])
		var at := Vector3(side * 0.165, 0.15, 0.0)
		_p(parent, ItemMesh.lathe(dome, 16, true), m, at, Vector3(0, 0, side * -38.0))
		for k in 2:
			var lame := PackedVector2Array([Vector2(0.08 - k * 0.002, -0.012), Vector2(0.082 - k * 0.002, 0.0), Vector2(0.075 - k * 0.002, 0.012)])
			_p(parent, ItemMesh.lathe(lame, 16, true), trim if k == 0 else m, at + Vector3(side * (0.02 + k * 0.012), -0.035 - k * 0.022, 0), Vector3(0, 0, side * -38.0))
		if tier in ["adamantite", "infernal"]:
			_p(parent, ModelKit.cone(0.014, 0.07, 5), ItemMats.metal("dark_iron") if tier == "infernal" else trim, at + Vector3(side * 0.035, 0.05, 0), Vector3(0, 0, side * -38.0))
	var g := GearModels.gem_for(tier)
	if g != null:
		_p(parent, ItemMesh.gem_cut(0.02, 8, 0.4, 0.5), g, Vector3(0, 0.12, 0.178 * sq.y + 0.006), Vector3(90, 0, 0))
	if tier == "infernal":
		_p(parent, ItemMesh.bevel_box(Vector3(0.006, 0.18, 0.006), 0.001), ItemMats.glow(Color(1.0, 0.4, 0.1), 5.0), Vector3(0, 0.0, 0.166 * sq.y + 0.004))


static func greaves(parent: Node3D, tier: String) -> void:
	var m := ItemMats.metal(tier)
	var trim := ItemMats.trim(tier)
	# Waist with tassets.
	var sq := Vector2(1.0, 0.62)
	_p(parent, ItemMesh.lathe(PackedVector2Array([Vector2(0.13, 0.0), Vector2(0.142, 0.01), Vector2(0.142, 0.045), Vector2(0.13, 0.055)]), 22, true, sq), ItemMats.leather(Color(0.24, 0.14, 0.08)))
	_p(parent, ItemMesh.bevel_box(Vector3(0.028, 0.028, 0.01), 0.003), trim, Vector3(0, 0.028, 0.09))
	for side: float in [-1.0, 1.0]:
		var x := side * 0.072
		# Leg tube: thigh, knee, calf, ankle.
		var prof := PackedVector2Array([Vector2(0.05, -0.47), Vector2(0.044, -0.43), Vector2(0.052, -0.36), Vector2(0.058, -0.3), Vector2(0.05, -0.24),
			Vector2(0.054, -0.2), Vector2(0.066, -0.1), Vector2(0.072, -0.02), Vector2(0.068, 0.005)])
		_p(parent, ItemMesh.lathe(prof, 16, true, Vector2(1.0, 0.9)), m, Vector3(x, 0, 0))
		# Tasset plate over the thigh.
		var tas := PackedVector2Array([Vector2(-0.06, 0.0), Vector2(0.06, 0.0), Vector2(0.055, -0.1), Vector2(-0.055, -0.1)])
		_p(parent, ItemMesh.plate_even(tas, 0.004, 0.002), m, Vector3(x, 0.0, 0.07), Vector3(-10, side * 12.0, 0))
		_p(parent, ModelKit.sphere(0.005, 6), trim, Vector3(x, -0.02, 0.078))
		# Knee cop with a fan.
		var cop := PackedVector2Array([Vector2(0.05, -0.012), Vector2(0.044, 0.012), Vector2(0.026, 0.03), Vector2(0.0, 0.036)])
		_p(parent, ItemMesh.lathe(cop, 14, true), m, Vector3(x, -0.22, 0.045), Vector3(90, 0, 0))
		_p(parent, ModelKit.sphere(0.008, 6), trim, Vector3(x, -0.22, 0.085))
		var fan := PackedVector2Array([Vector2(0, 0.03), Vector2(0.04, 0.0), Vector2(0, -0.03)])
		_p(parent, ItemMesh.plate_even(fan, 0.003, 0.001), trim, Vector3(x + side * 0.045, -0.22, 0.03), Vector3(0, side * -60.0 + (180.0 if side < 0.0 else 0.0), 0))
		# Shin ridge.
		_p(parent, ItemMesh.tube(PackedVector3Array([Vector3(x, -0.27, 0.052), Vector3(x, -0.36, 0.054), Vector3(x, -0.44, 0.042)]), PackedFloat32Array([0.004, 0.005, 0.003]), 5), m)
		if tier == "infernal":
			_p(parent, ItemMesh.bevel_box(Vector3(0.004, 0.12, 0.004), 0.001), ItemMats.glow(Color(1.0, 0.42, 0.1), 5.0), Vector3(x, -0.35, 0.058))


static func boots(parent: Node3D, tier: String) -> void:
	var m := ItemMats.metal(tier)
	var trim := ItemMats.trim(tier)
	var leather := ItemMats.leather(Color(0.28, 0.17, 0.1))
	for side: float in [-1.0, 1.0]:
		var x := side * 0.062
		# Leather boot under the plates.
		_p(parent, ItemMesh.lathe(PackedVector2Array([Vector2(0.044, 0.0), Vector2(0.046, 0.08), Vector2(0.05, 0.15), Vector2(0.046, 0.16)]), 14, true, Vector2(1.0, 0.95)), leather, Vector3(x, 0.03, -0.01))
		# Plated cuff.
		_p(parent, ItemMesh.lathe(PackedVector2Array([Vector2(0.05, 0.07), Vector2(0.053, 0.08), Vector2(0.055, 0.15), Vector2(0.05, 0.16)]), 14, true, Vector2(1.0, 0.95)), m, Vector3(x, 0.03, -0.01))
		# Sabaton: overlapping lames from ankle to toe.
		var rings: Array = []
		for k in 7:
			var f := float(k) / 6.0
			var z := lerpf(-0.05, 0.13, f)
			var w := lerpf(0.05, 0.03, f * f)
			var h := lerpf(0.06, 0.018, f)
			var r := PackedVector3Array()
			for i in 10:
				var a := PI * float(i) / 9.0
				r.append(Vector3(x + cos(a) * w, 0.002 + sin(a) * h, z))
			rings.append(r)
		_p(parent, ItemMesh.loft(rings, true, true), m)
		for k in 4:
			var z := 0.0 + k * 0.03
			var f := (z + 0.05) / 0.18
			var w := lerpf(0.05, 0.03, f * f) + 0.003
			var h := lerpf(0.06, 0.018, f) + 0.003
			var arc := PackedVector3Array()
			var rr := PackedFloat32Array()
			for i in 7:
				var a := PI * float(i) / 6.0
				arc.append(Vector3(x + cos(a) * w, sin(a) * h, z))
				rr.append(0.0025)
			_p(parent, ItemMesh.tube(arc, rr, 4), trim if k == 0 else m)
		# Sole and heel.
		_p(parent, ItemMesh.bevel_box(Vector3(0.1, 0.012, 0.2), 0.004), leather, Vector3(x, 0.0, 0.035))
		_p(parent, ItemMesh.bevel_box(Vector3(0.08, 0.025, 0.05), 0.004), leather, Vector3(x, 0.006, -0.045))
		if tier in ["adamantite", "infernal"]:
			_p(parent, ModelKit.cone(0.01, 0.04, 5), trim, Vector3(x + side * 0.05, 0.14, -0.01), Vector3(0, 0, side * -90.0))
