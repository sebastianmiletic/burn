class_name ArcanaModels
extends RefCounted
## Models for ArcanaItems (ItemDB "model_script"): bows, arrows, staffs,
## books, brewed potions, brewing ingredients and the cauldron. Item-kit
## conventions: built along +Y from the grip, metres.

static func _p(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	return ModelKit.part(parent, mesh, mat, pos, rot, scl)


static func build(body: Node3D, id: String) -> bool:
	var inf := ItemDB.info(id)
	match String(inf.get("kind", "")):
		"bow":
			_bow(body, inf)
			return true
		"staff":
			_staff(body, id, inf)
			return true
		"arrow":
			_arrow(body, inf)
			return true
	if inf.has("book"):
		_book(body, inf)
		return true
	match id:
		"cauldron":
			cauldron(body, false)
			return true
		"brew_sludge":
			_p(body, ItemMesh.rock(0.07, 3, 0.4, 2, Vector3(1.2, 0.6, 1.0), true), ItemMats.food(Color(0.28, 0.26, 0.16), 0.3), Vector3(0, 0.04, 0))
			return true
		"dragon_fang":
			var path := PackedVector3Array([Vector3(0, 0, 0), Vector3(0.01, 0.07, 0), Vector3(0.03, 0.14, 0), Vector3(0.07, 0.19, 0)])
			_p(body, ItemMesh.tube(path, PackedFloat32Array([0.028, 0.022, 0.013, 0.001]), 9), ItemMats.bone(Color(0.96, 0.92, 0.8)))
			return true
		"dragon_femur":
			_p(body, ModelKit.cylinder(0.03, 0.03, 0.34, 9), ItemMats.bone(), Vector3(0, 0.17, 0))
			for y: float in [0.0, 0.34]:
				for s: float in [-1.0, 1.0]:
					_p(body, ModelKit.sphere(0.04, 9), ItemMats.bone(), Vector3(s * 0.025, y, 0))
			return true
		"everbloom_leaf":
			_p(body, ItemMesh.plate(PackedVector2Array([Vector2(0, 0), Vector2(0.05, 0.06), Vector2(0.04, 0.14), Vector2(0, 0.18), Vector2(-0.04, 0.14), Vector2(-0.05, 0.06)]),
				PackedFloat32Array([0.003, 0.003, 0.003, 0.003, 0.003, 0.003]), 0.002, true), ItemMats.glow(Color(0.4, 0.95, 0.5), 1.2))
			return true
		"everbloom_fruit":
			_p(body, ModelKit.sphere(0.055, 12), ItemMats.glow(Color(0.95, 0.55, 0.8), 1.5), Vector3(0, 0.06, 0))
			_p(body, ModelKit.cylinder(0.006, 0.006, 0.04, 5), ItemMats.wood(Color(0.3, 0.4, 0.2)), Vector3(0, 0.13, 0))
			return true
	if String(inf.get("category", "")) == "consumable" or id in ["dragon_blood", "everbloom_sap"]:
		_flask(body, Color(inf.get("color", Color.WHITE)), id == "everbloom_sap")
		return true
	return false


static func _bow(body: Node3D, inf: Dictionary) -> void:
	var c: Color = inf.get("color", Color(0.5, 0.35, 0.2))
	var long := String(inf.get("tier", "")) in ["steel", "adamantite"]
	var half := 0.62 if long else 0.5
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 13:
		var t := float(i) / 12.0 * 2.0 - 1.0   # -1..1 along the limbs
		pts.append(Vector3(0, t * half, -0.1 * (1.0 - t * t) - (0.03 * t * t * t * t if String(inf.get("tier", "")) == "adamantite" else 0.0)))
		radii.append(lerpf(0.022, 0.009, absf(t)))
	var wood := ItemMats.wood(c, c.darkened(0.45))
	_p(body, ItemMesh.tube(pts, radii, 8), wood)
	# Grip wrap and string.
	_p(body, ModelKit.cylinder(0.026, 0.026, 0.12, 8), ItemMats.leather(), Vector3(0, 0, -0.1))
	var string_len := half * 2.0 - 0.02
	_p(body, ModelKit.cylinder(0.0025, 0.0025, string_len, 4), ItemMats.cloth(Color(0.88, 0.85, 0.78)), Vector3(0, 0, 0.0))
	if inf.has("burn"):
		_p(body, ModelKit.cylinder(0.006, 0.006, 0.18, 5), ItemMats.glow(Color(1.0, 0.45, 0.15), 3.0), Vector3(0, half * 0.6, -0.04))
	if String(inf.get("tier", "")) == "adamantite":
		_p(body, ModelKit.sphere(0.02, 8), ItemMats.glow(Color(0.7, 0.55, 1.0), 4.0), Vector3(0, 0.08, -0.12))


static func _arrow(body: Node3D, inf: Dictionary) -> void:
	_p(body, ModelKit.cylinder(0.005, 0.005, 0.6, 5), ItemMats.wood(Color(0.55, 0.42, 0.28)), Vector3(0, 0.3, 0))
	var head := ItemMats.stone(Color(0.45, 0.44, 0.42)) if float(inf.get("arrow_damage", 0.0)) <= 0.0 else ItemMats.metal("iron")
	_p(body, ModelKit.cone(0.014, 0.05, 4), head, Vector3(0, 0.62, 0))
	for k in 3:
		var a := TAU * k / 3.0
		_p(body, ItemMesh.bevel_box(Vector3(0.002, 0.07, 0.018), 0.0005), ItemMats.cloth(Color(0.85, 0.8, 0.72)), Vector3(sin(a) * 0.01, 0.05, cos(a) * 0.01), Vector3(0, rad_to_deg(a), 0))
	if inf.has("arrow_burn"):
		_p(body, ModelKit.sphere(0.018, 6), ItemMats.glow(Color(1.0, 0.5, 0.15), 3.0), Vector3(0, 0.58, 0))


static func _staff(body: Node3D, id: String, inf: Dictionary) -> void:
	var c: Color = inf.get("color", Color(0.5, 0.36, 0.24))
	var path := PackedVector3Array([Vector3(0, -0.5, 0), Vector3(0.008, 0.0, 0.004), Vector3(-0.004, 0.5, 0), Vector3(0.0, 0.9, 0.0)])
	var wood := ItemMats.wood(Color(0.42, 0.3, 0.19) if id != "staff_void" else Color(0.3, 0.22, 0.4))
	_p(body, ItemMesh.tube(path, PackedFloat32Array([0.016, 0.019, 0.018, 0.022]), 8), wood)
	_p(body, ModelKit.cylinder(0.024, 0.024, 0.08, 8), ItemMats.leather(), Vector3(0, 0.05, 0))
	# The focus: claws holding a glowing stone.
	var focus: Color = c.lightened(0.2)
	for k in 3:
		var a := TAU * k / 3.0
		var claw := PackedVector3Array([Vector3(0, 0.9, 0), Vector3(sin(a) * 0.045, 0.96, cos(a) * 0.045), Vector3(sin(a) * 0.025, 1.04, cos(a) * 0.025)])
		_p(body, ItemMesh.tube(claw, PackedFloat32Array([0.008, 0.007, 0.003]), 5), wood)
	_p(body, ItemMesh.gem_cut(0.035, 8), ItemMats.gem(focus, 0.06, 4.0), Vector3(0, 0.98, 0))
	var light := OmniLight3D.new()
	light.light_color = focus
	light.light_energy = 0.6
	light.omni_range = 1.6
	light.position = Vector3(0, 0.98, 0)
	body.add_child(light)


static func _book(body: Node3D, inf: Dictionary) -> void:
	var c: Color = inf.get("color", Color(0.4, 0.3, 0.2))
	_p(body, ItemMesh.bevel_box(Vector3(0.16, 0.22, 0.012), 0.003), ItemMats.leather(c), Vector3(0, 0.11, 0.022))
	_p(body, ItemMesh.bevel_box(Vector3(0.16, 0.22, 0.012), 0.003), ItemMats.leather(c), Vector3(0, 0.11, -0.022))
	_p(body, ItemMesh.bevel_box(Vector3(0.15, 0.21, 0.034), 0.002), ItemMats.cloth(Color(0.86, 0.8, 0.66)), Vector3(0.004, 0.11, 0))
	_p(body, ItemMesh.bevel_box(Vector3(0.014, 0.22, 0.056), 0.003), ItemMats.leather(c.darkened(0.3)), Vector3(-0.08, 0.11, 0))
	_p(body, ModelKit.sphere(0.012, 8), ItemMats.glow(c.lightened(0.4), 2.5), Vector3(0.02, 0.13, 0.03))


static func _flask(body: Node3D, color: Color, jar: bool) -> void:
	var profile := PackedVector2Array([Vector2(0, 0), Vector2(0.04, 0.0), Vector2(0.05, 0.03), Vector2(0.045, 0.07), Vector2(0.015, 0.1), Vector2(0.014, 0.13), Vector2(0.0, 0.13)]) if not jar \
		else PackedVector2Array([Vector2(0, 0), Vector2(0.04, 0.0), Vector2(0.042, 0.08), Vector2(0.03, 0.09), Vector2(0.0, 0.09)])
	_p(body, ItemMesh.lathe(profile, 14), ItemMats.glass())
	_p(body, ModelKit.sphere(0.038, 10), ItemMats.liquid(color), Vector3(0, 0.035, 0), Vector3.ZERO, Vector3(1, 0.8, 1))
	_p(body, ModelKit.cylinder(0.016, 0.014, 0.025, 8), ItemMats.wood(Color(0.55, 0.42, 0.3)), Vector3(0, 0.135 if not jar else 0.095, 0))


## The cauldron (held icon and the placed station when `live`).
static func cauldron(root: Node3D, live: bool) -> void:
	var iron := ItemMats.metal("iron")
	var s := 1.0 if live else 0.3
	var profile := PackedVector2Array([Vector2(0, 0.12), Vector2(0.3, 0.14), Vector2(0.42, 0.3), Vector2(0.44, 0.48), Vector2(0.38, 0.62), Vector2(0.4, 0.66), Vector2(0.36, 0.66), Vector2(0.33, 0.6)])
	var scaled := PackedVector2Array()
	for p in profile:
		scaled.append(p * s)
	_p(root, ItemMesh.lathe(scaled, 20), iron)
	for k in 3:
		var a := TAU * k / 3.0
		_p(root, ModelKit.cylinder(0.03 * s, 0.04 * s, 0.22 * s, 6), iron, Vector3(sin(a) * 0.3 * s, 0.1 * s, cos(a) * 0.3 * s))
	if live:
		var brew := _p(root, ModelKit.cylinder(0.36, 0.36, 0.02, 18), ItemMats.liquid(Color(0.25, 0.5, 0.3)), Vector3(0, 0.56, 0))
		brew.name = "Brew"
		var embers := ModelKit.embers(root, 16, Vector3(0.25, 0.05, 0.25), 0.9, 0.05, 0.6)
		embers.position = Vector3(0, 0.04, 0)
		embers.emitting = true
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.55, 0.25)
		light.light_energy = 0.9
		light.omni_range = 3.5
		light.position = Vector3(0, 0.2, 0)
		light.name = "Fire"
		root.add_child(light)
