class_name GearModels
extends RefCounted
## Tools and weapons of every material tier, built along +Y from the grip
## (the hand holds the origin). Each tier has its own silhouette details:
## leaf-bladed copper and bronze, fullered iron and steel, elven mithril,
## broad spiked adamantite, flame-bladed infernal with molten veins.


static func _p(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	return ModelKit.part(parent, mesh, mat, pos, rot, scl)


## Head/blade material of a tier ("wood" and "stone" are not metals).
static func head_mat(tier: String) -> Material:
	match tier:
		"wood":
			return ItemMats.wood(Color(0.6, 0.43, 0.26), Color(0.3, 0.2, 0.1))
		"stone":
			return ItemMats.stone(Color(0.5, 0.49, 0.47), Color(0.32, 0.31, 0.3), 0.9)
	return ItemMats.metal(tier)


static func haft_mat(tier: String) -> Material:
	match tier:
		"mithril":
			return ItemMats.wood(Color(0.78, 0.7, 0.58), Color(0.45, 0.38, 0.3))
		"adamantite":
			return ItemMats.wood(Color(0.24, 0.16, 0.12), Color(0.12, 0.08, 0.05))
		"infernal":
			return ItemMats.metal("dark_iron")
		"steel":
			return ItemMats.wood(Color(0.36, 0.22, 0.13), Color(0.18, 0.1, 0.05))
	return ItemMats.wood(Color(0.52, 0.36, 0.21), Color(0.26, 0.16, 0.08))


static func grip_mat(tier: String) -> Material:
	match tier:
		"mithril":
			return ItemMats.leather(Color(0.2, 0.25, 0.38))
		"adamantite":
			return ItemMats.leather(Color(0.12, 0.2, 0.14))
		"infernal":
			return ItemMats.leather(Color(0.22, 0.06, 0.04))
		"steel":
			return ItemMats.leather(Color(0.18, 0.1, 0.07))
		"wood", "stone":
			return ItemMats.cloth(Color(0.55, 0.47, 0.34))
	return ItemMats.leather(Color(0.36, 0.2, 0.11))


static func gem_for(tier: String) -> Material:
	match tier:
		"mithril":
			return ItemMats.gem(Color(0.3, 0.55, 1.0), 0.05, 1.6)
		"adamantite":
			return ItemMats.gem(Color(0.2, 0.95, 0.45), 0.05, 1.4)
		"infernal":
			return ItemMats.glow(Color(1.0, 0.45, 0.1), 5.0)
		"steel":
			return ItemMats.gem(Color(0.85, 0.12, 0.15), 0.05, 0.8)
	return null


static func build(parent: Node3D, kind: String, tier: String) -> void:
	match kind:
		"pickaxe":
			pickaxe(parent, tier)
		"axe":
			axe(parent, tier)
		"sword":
			sword(parent, tier)
		"dagger":
			dagger(parent, tier)
		"spear":
			spear(parent, tier)
		"greataxe":
			greataxe(parent, tier)
		"warhammer":
			warhammer(parent, tier)
	if tier == "infernal":
		var e := ModelKit.embers(parent, 8, Vector3(0.04, 0.15, 0.04), 0.9, 0.05, 0.6)
		e.position = Vector3(0, 0.6, 0)
		e.emitting = true


# --- Shared parts -------------------------------------------------------------------------

static func haft(parent: Node3D, y0: float, y1: float, r0: float, r1: float, mat: Material) -> void:
	var prof := PackedVector2Array([Vector2(r0 * 0.75, y0), Vector2(r0, y0 + 0.008), Vector2(lerpf(r0, r1, 0.5) * 1.03, (y0 + y1) * 0.5),
		Vector2(r1, y1 - 0.008), Vector2(r1 * 0.8, y1)])
	_p(parent, ItemMesh.lathe(prof, 10, true, Vector2(1.0, 0.82)), mat)


## Leather / cord wrapping: a ribbed sleeve.
static func grip_wrap(parent: Node3D, y0: float, y1: float, r: float, mat: Material) -> void:
	var prof := PackedVector2Array()
	var n := int((y1 - y0) / 0.011)
	prof.append(Vector2(r * 0.9, y0))
	for i in n + 1:
		var y := y0 + (y1 - y0) * float(i) / float(maxi(n, 1))
		prof.append(Vector2(r * (1.07 if i % 2 == 0 else 1.0), y))
	prof.append(Vector2(r * 0.9, y1))
	_p(parent, ItemMesh.lathe(prof, 10, true), mat)


static func rivet(parent: Node3D, pos: Vector3, r: float, mat: Material) -> void:
	_p(parent, ModelKit.sphere(r, 6), mat, pos)


static func band(parent: Node3D, y: float, r: float, h: float, mat: Material) -> void:
	var prof := PackedVector2Array([Vector2(r * 0.96, y - h * 0.5), Vector2(r, y - h * 0.35), Vector2(r, y + h * 0.35), Vector2(r * 0.96, y + h * 0.5)])
	_p(parent, ItemMesh.lathe(prof, 12, true), mat)


static func pommel(parent: Node3D, y: float, tier: String) -> void:
	var trim := ItemMats.trim(tier)
	match tier:
		"wood", "stone":
			_p(parent, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, y - 0.02), Vector2(0.02, y - 0.016), Vector2(0.024, y), Vector2(0.018, y + 0.012), Vector2(0.0, y + 0.014)]), 10), haft_mat("wood"))
		"copper", "bronze":
			_p(parent, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, y - 0.03), Vector2(0.024, y - 0.026), Vector2(0.03, y - 0.012), Vector2(0.018, y + 0.004), Vector2(0.012, y + 0.016), Vector2(0.0, y + 0.018)]), 12), trim)
		"iron", "steel":
			# Wheel pommel.
			_p(parent, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, -0.012), Vector2(0.028, -0.01), Vector2(0.032, 0.0), Vector2(0.028, 0.01), Vector2(0.0, 0.012)]), 14, true),
				trim, Vector3(0, y - 0.01, 0), Vector3(90, 0, 0))
			_p(parent, ModelKit.cylinder(0.012, 0.012, 0.03, 8), trim, Vector3(0, y + 0.012, 0))
		_:
			_p(parent, ItemMesh.lathe(PackedVector2Array([Vector2(0.012, y + 0.016), Vector2(0.022, y + 0.004), Vector2(0.026, y - 0.012), Vector2(0.0, y - 0.03)]), 10), trim)
			var g := gem_for(tier)
			if g != null:
				_p(parent, ItemMesh.gem_cut(0.017, 8), g, Vector3(0, y - 0.036, 0), Vector3(180, 0, 0))


static func guard(parent: Node3D, y: float, tier: String, width: float) -> void:
	var trim := ItemMats.trim(tier) if tier not in ["wood", "stone"] else head_mat(tier)
	var hw := width * 0.5
	var pts: PackedVector2Array
	match tier:
		"steel", "mithril":
			# Quillons sweeping up toward the blade.
			pts = PackedVector2Array([Vector2(-hw, 0.03), Vector2(-hw * 0.9, 0.012), Vector2(-hw * 0.5, -0.004), Vector2(-0.02, -0.012), Vector2(0.02, -0.012),
				Vector2(hw * 0.5, -0.004), Vector2(hw * 0.9, 0.012), Vector2(hw, 0.03), Vector2(hw * 0.94, 0.036), Vector2(hw * 0.5, 0.012), Vector2(0.02, 0.01),
				Vector2(-0.02, 0.01), Vector2(-hw * 0.5, 0.012), Vector2(-hw * 0.94, 0.036)])
		"adamantite":
			pts = PackedVector2Array([Vector2(-hw, -0.03), Vector2(-hw * 0.6, -0.012), Vector2(-0.025, -0.02), Vector2(0.025, -0.02), Vector2(hw * 0.6, -0.012),
				Vector2(hw, -0.03), Vector2(hw * 0.9, 0.0), Vector2(hw, 0.04), Vector2(hw * 0.55, 0.014), Vector2(-hw * 0.55, 0.014), Vector2(-hw, 0.04), Vector2(-hw * 0.9, 0.0)])
		"infernal":
			pts = PackedVector2Array([Vector2(-hw, 0.05), Vector2(-hw * 0.8, 0.0), Vector2(-0.03, -0.022), Vector2(0.03, -0.022), Vector2(hw * 0.8, 0.0), Vector2(hw, 0.05),
				Vector2(hw * 0.82, 0.03), Vector2(hw * 0.5, 0.012), Vector2(0.03, 0.014), Vector2(-0.03, 0.014), Vector2(-hw * 0.5, 0.012), Vector2(-hw * 0.82, 0.03)])
		_:
			pts = PackedVector2Array([Vector2(-hw, -0.008), Vector2(hw, -0.008), Vector2(hw + 0.008, 0.0), Vector2(hw, 0.009), Vector2(-hw, 0.009), Vector2(-hw - 0.008, 0.0)])
	_p(parent, ItemMesh.plate_even(pts, 0.013, 0.004), trim, Vector3(0, y, 0))
	var g := gem_for(tier)
	if g != null:
		_p(parent, ItemMesh.gem_cut(0.014, 8, 0.4, 0.5), g, Vector3(0, y + 0.004, 0.012), Vector3(90, 0, 0))
		_p(parent, ItemMesh.gem_cut(0.014, 8, 0.4, 0.5), g, Vector3(0, y + 0.004, -0.012), Vector3(-90, 0, 0))


# --- Swords and daggers -----------------------------------------------------------------------

static func _blade_widths(tier: String, base: float, n := 10) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	for i in n:
		var f := float(i) / float(n - 1)
		var v: float
		match tier:
			"copper", "bronze":
				# Leaf blade: swells two thirds of the way up.
				v = base * (0.8 + 0.45 * sin(f * PI * 0.85)) * (1.0 - pow(f, 6.0))
			"adamantite":
				v = base * 1.35 * (1.0 - pow(f, 4.0) * 0.55) * (1.0 - pow(f, 9.0))
			"infernal":
				v = base * (1.05 + 0.18 * sin(f * 19.0)) * (1.0 - pow(f, 3.0) * 0.5) * (1.0 - pow(f, 8.0))
			"mithril":
				v = base * 0.9 * (1.0 - f * 0.35) * (1.0 - pow(f, 7.0))
			_:
				v = base * (1.0 - f * 0.22) * (1.0 - pow(f, 7.0))
		w.append(maxf(v, 0.0))
	w[n - 1] = 0.0
	return w


static func sword(parent: Node3D, tier: String, head: Material = null) -> void:
	var length := {"wood": 0.7, "copper": 0.6, "bronze": 0.66, "iron": 0.8, "steel": 0.85, "mithril": 0.92, "adamantite": 0.88, "infernal": 0.95}.get(tier, 0.8) as float
	var base := 0.052
	var thick := 0.022 if tier == "wood" else 0.012
	var fuller := 0.0 if tier in ["wood", "copper", "bronze", "infernal"] else 0.7
	var blade_y := 0.19
	var hm: Material = head if head != null else head_mat(tier)
	_p(parent, ItemMesh.blade(length, _blade_widths(tier, base, 12), thick, fuller), hm, Vector3(0, blade_y, 0))
	# Ricasso block and grip.
	_p(parent, ItemMesh.bevel_box(Vector3(0.04, 0.025, 0.016), 0.003), hm, Vector3(0, blade_y - 0.006, 0))
	guard(parent, 0.172, tier, 0.2 if tier not in ["copper", "bronze"] else 0.11)
	grip_wrap(parent, -0.005, 0.158, 0.016, grip_mat(tier))
	pommel(parent, -0.02, tier)
	if tier == "infernal":
		_p(parent, ItemMesh.blade(length * 0.8, _blade_widths("iron", 0.012, 8), 0.0135, 0.0), ItemMats.glow(Color(1.0, 0.42, 0.1), 4.0), Vector3(0, blade_y + 0.02, 0))
	elif tier == "mithril":
		_p(parent, ItemMesh.bevel_box(Vector3(0.004, length * 0.62, 0.0125), 0.001), ItemMats.glow(Color(0.5, 0.8, 1.0), 2.2), Vector3(0, blade_y + length * 0.36, 0))


static func dagger(parent: Node3D, tier: String) -> void:
	var length := 0.27 if tier != "adamantite" else 0.3
	var w := PackedFloat32Array([0.044, 0.046, 0.044, 0.04, 0.034, 0.026, 0.016, 0.0])
	if tier == "infernal":
		w = PackedFloat32Array([0.044, 0.05, 0.04, 0.046, 0.034, 0.03, 0.016, 0.0])
	_p(parent, ItemMesh.blade(length, w, 0.011, 0.5 if tier in ["steel", "mithril"] else 0.0), head_mat(tier), Vector3(0, 0.13, 0))
	guard(parent, 0.118, tier, 0.1)
	grip_wrap(parent, -0.0, 0.105, 0.014, grip_mat(tier))
	pommel(parent, -0.012, tier)


# --- Pickaxe and axes ----------------------------------------------------------------------

static func pickaxe(parent: Node3D, tier: String, head: Material = null) -> void:
	var hy := 0.72
	haft(parent, -0.12, hy + 0.05, 0.018, 0.016, haft_mat(tier))
	grip_wrap(parent, -0.09, 0.1, 0.0185, grip_mat(tier))
	var mat: Material = head if head != null else head_mat(tier)
	# Curved double pick: upper and lower arcs, thinning to points at both ends.
	var pts := PackedVector2Array()
	var ht := PackedFloat32Array()
	var n := 13
	var span := 0.33 if tier not in ["mithril", "adamantite"] else 0.36
	for i in n:
		var t := -1.0 + 2.0 * float(i) / float(n - 1)
		var yc := 0.03 * (1.0 - t * t) - 0.045 * t * t
		var hh := 0.03 * pow(1.0 - absf(t), 0.8) + 0.003
		pts.append(Vector2(t * span, yc + hh))
		ht.append(0.02 * pow(1.0 - absf(t), 0.6) + 0.004)
	for i in range(n - 1, -1, -1):
		var t := -1.0 + 2.0 * float(i) / float(n - 1)
		var yc := 0.03 * (1.0 - t * t) - 0.045 * t * t
		var hh := 0.03 * pow(1.0 - absf(t), 0.8) + 0.003
		if t > 0.7 and tier not in ["wood", "stone"]:
			hh = hh * 1.0 + 0.012 * (t - 0.7) / 0.3  # chisel end on the right
		pts.append(Vector2(t * span, yc - hh))
		ht.append(0.02 * pow(1.0 - absf(t), 0.6) + 0.004)
	_p(parent, ItemMesh.plate(pts, ht, 0.004), mat, Vector3(0, hy, 0))
	# Eye collar, wedge and langets.
	_p(parent, ItemMesh.bevel_box(Vector3(0.052, 0.07, 0.046), 0.006), mat, Vector3(0, hy + 0.01, 0))
	if tier in ["wood", "stone"]:
		_lashing(parent, hy, 0.03)
	else:
		var trim := ItemMats.trim(tier)
		for side: float in [-1.0, 1.0]:
			_p(parent, ItemMesh.bevel_box(Vector3(0.006, 0.12, 0.014), 0.002), trim, Vector3(side * 0.019, hy - 0.08, 0))
			rivet(parent, Vector3(side * 0.023, hy - 0.11, 0), 0.004, trim)
		rivet(parent, Vector3(0, hy + 0.045, 0), 0.007, trim)
	if tier == "mithril":
		_p(parent, ItemMesh.bevel_box(Vector3(span * 1.4, 0.003, 0.002), 0.0005), ItemMats.glow(Color(0.5, 0.8, 1.0), 2.5), Vector3(0, hy + 0.025, 0.022))


static func _lashing(parent: Node3D, y: float, r: float) -> void:
	var cord := ItemMats.cloth(Color(0.48, 0.38, 0.25))
	for i in 3:
		var a := deg_to_rad(35.0 + i * 55.0)
		var path := PackedVector3Array()
		var radii := PackedFloat32Array()
		for k in 9:
			var t := TAU * float(k) / 8.0
			path.append(Vector3(cos(t) * r, y - 0.03 + sin(t + a) * 0.025 + float(i) * 0.012, sin(t) * r * 0.9))
			radii.append(0.0035)
		_p(parent, ItemMesh.tube(path, radii, 5), cord)


static func axe(parent: Node3D, tier: String) -> void:
	var hy := 0.62
	var path := PackedVector3Array([Vector3(0, -0.12, 0), Vector3(0.006, 0.1, 0), Vector3(-0.004, 0.35, 0), Vector3(-0.01, 0.55, 0), Vector3(0, hy + 0.06, 0)])
	_p(parent, ItemMesh.tube(path, PackedFloat32Array([0.017, 0.019, 0.017, 0.016, 0.015]), 9), haft_mat(tier))
	grip_wrap(parent, -0.09, 0.08, 0.0195, grip_mat(tier))
	var pts := PackedVector2Array([Vector2(-0.05, 0.034), Vector2(-0.024, 0.042), Vector2(0.026, 0.042), Vector2(0.07, 0.055), Vector2(0.135, 0.095),
		Vector2(0.158, 0.06), Vector2(0.168, 0.0), Vector2(0.16, -0.06), Vector2(0.13, -0.11), Vector2(0.095, -0.085), Vector2(0.05, -0.045),
		Vector2(0.026, -0.036), Vector2(-0.024, -0.036), Vector2(-0.05, -0.03)])
	var ht := PackedFloat32Array([0.019, 0.02, 0.02, 0.012, 0.004, 0.0025, 0.0025, 0.0025, 0.004, 0.01, 0.016, 0.02, 0.02, 0.019])
	if tier == "stone":
		pts = PackedVector2Array([Vector2(-0.03, 0.03), Vector2(0.04, 0.05), Vector2(0.12, 0.06), Vector2(0.15, 0.0), Vector2(0.12, -0.06), Vector2(0.04, -0.045), Vector2(-0.03, -0.03)])
		ht = PackedFloat32Array([0.02, 0.018, 0.008, 0.004, 0.008, 0.018, 0.02])
	_p(parent, ItemMesh.plate(pts, ht, 0.004), head_mat(tier), Vector3(0, hy, 0))
	if tier == "stone":
		_lashing(parent, hy, 0.028)
	elif tier != "wood":
		rivet(parent, Vector3(0, hy + 0.046, 0), 0.006, ItemMats.trim(tier))
		_p(parent, ItemMesh.bevel_box(Vector3(0.05, 0.012, 0.042), 0.003), ItemMats.trim(tier), Vector3(0, hy - 0.045, 0))


static func greataxe(parent: Node3D, tier: String) -> void:
	var hy := 0.9
	haft(parent, -0.32, hy + 0.12, 0.021, 0.019, haft_mat(tier))
	grip_wrap(parent, -0.28, -0.05, 0.022, grip_mat(tier))
	grip_wrap(parent, 0.25, 0.42, 0.021, grip_mat(tier))
	var mat := head_mat(tier)
	for side: float in [-1.0, 1.0]:
		var pts := PackedVector2Array()
		var ht := PackedFloat32Array()
		# Crescent bit: from the eye out to a broad curved edge.
		var raw := [Vector2(0.03, 0.05), Vector2(0.09, 0.07), Vector2(0.16, 0.15), Vector2(0.2, 0.1), Vector2(0.22, 0.0), Vector2(0.2, -0.1),
			Vector2(0.16, -0.16), Vector2(0.09, -0.075), Vector2(0.03, -0.05)]
		var thick := [0.024, 0.016, 0.005, 0.003, 0.003, 0.003, 0.005, 0.016, 0.024]
		for i in raw.size():
			var p: Vector2 = raw[i]
			pts.append(Vector2(p.x * side, p.y))
			ht.append(thick[i])
		_p(parent, ItemMesh.plate(pts, ht, 0.004), mat, Vector3(0, hy, 0))
	_p(parent, ItemMesh.bevel_box(Vector3(0.07, 0.11, 0.052), 0.007), mat, Vector3(0, hy, 0))
	_p(parent, ModelKit.cone(0.018, 0.1, 6), mat, Vector3(0, hy + 0.1, 0))
	var trim := ItemMats.trim(tier) if tier not in ["wood", "stone"] else mat
	for y: float in [hy - 0.07, hy + 0.06]:
		band(parent, y, 0.026, 0.014, trim)
	for side: float in [-1.0, 1.0]:
		rivet(parent, Vector3(side * 0.036, hy, 0.02), 0.006, trim)
	var g := gem_for(tier)
	if g != null:
		_p(parent, ItemMesh.gem_cut(0.016, 8, 0.4, 0.5), g, Vector3(0, hy, 0.027), Vector3(90, 0, 0))


static func warhammer(parent: Node3D, tier: String) -> void:
	var hy := 0.82
	haft(parent, -0.24, hy + 0.1, 0.02, 0.019, haft_mat(tier))
	grip_wrap(parent, -0.2, 0.02, 0.021, grip_mat(tier))
	var mat := head_mat(tier)
	if tier == "stone":
		_p(parent, ItemMesh.rock(0.075, 31, 0.18, 2, Vector3(1.5, 0.95, 1.0)), mat, Vector3(0, hy, 0))
		_lashing(parent, hy - 0.02, 0.03)
		return
	_p(parent, ItemMesh.bevel_box(Vector3(0.1, 0.085, 0.08), 0.012), mat, Vector3(0.025, hy, 0))
	# Striking face with a waffle of small pyramids.
	_p(parent, ItemMesh.bevel_box(Vector3(0.02, 0.095, 0.09), 0.006), mat, Vector3(0.08, hy, 0))
	for i in 3:
		for j in 3:
			_p(parent, ModelKit.cone(0.012, 0.016, 4), mat, Vector3(0.096, hy - 0.028 + i * 0.028, -0.028 + j * 0.028), Vector3(0, 45, -90))
	# Back spike curving down, top spike.
	var spike := PackedVector3Array([Vector3(-0.025, hy, 0), Vector3(-0.07, hy - 0.004, 0), Vector3(-0.11, hy - 0.02, 0), Vector3(-0.14, hy - 0.05, 0)])
	_p(parent, ItemMesh.tube(spike, PackedFloat32Array([0.026, 0.02, 0.011, 0.001]), 6, false), mat)
	_p(parent, ModelKit.cone(0.014, 0.075, 6), mat, Vector3(0, hy + 0.08, 0))
	var trim := ItemMats.trim(tier)
	for side: float in [-1.0, 1.0]:
		_p(parent, ItemMesh.bevel_box(Vector3(0.006, 0.2, 0.014), 0.002), trim, Vector3(side * 0.021, hy - 0.13, 0))
	band(parent, hy - 0.052, 0.025, 0.012, trim)
	var g := gem_for(tier)
	if g != null:
		_p(parent, ItemMesh.gem_cut(0.016, 8, 0.4, 0.5), g, Vector3(0.025, hy, 0.041), Vector3(90, 0, 0))


static func spear(parent: Node3D, tier: String) -> void:
	var top := 1.02
	haft(parent, -0.72, top, 0.016, 0.015, haft_mat(tier))
	grip_wrap(parent, -0.08, 0.12, 0.017, grip_mat(tier))
	var mat := head_mat(tier)
	if tier == "stone":
		_p(parent, ItemMesh.rock(0.03, 7, 0.12, 1, Vector3(1.0, 3.2, 0.4)), mat, Vector3(0, top + 0.08, 0))
		_lashing(parent, top - 0.01, 0.018)
		return
	# Socket and leaf head.
	_p(parent, ItemMesh.lathe(PackedVector2Array([Vector2(0.019, top - 0.08), Vector2(0.018, top - 0.02), Vector2(0.014, top + 0.03), Vector2(0.009, top + 0.045)]), 10), mat)
	var w := PackedFloat32Array([0.012, 0.04, 0.056, 0.058, 0.05, 0.038, 0.024, 0.01, 0.0])
	if tier == "infernal" or tier == "adamantite":
		w = PackedFloat32Array([0.014, 0.05, 0.07, 0.05, 0.062, 0.04, 0.028, 0.012, 0.0])
	_p(parent, ItemMesh.blade(0.28, w, 0.016, 0.0), mat, Vector3(0, top + 0.04, 0))
	var trim := ItemMats.trim(tier)
	band(parent, top - 0.075, 0.021, 0.01, trim)
	# Butt spike (ferrule).
	_p(parent, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, -0.8), Vector2(0.012, -0.76), Vector2(0.017, -0.72), Vector2(0.017, -0.7)]), 8), trim)
	if tier in ["mithril", "infernal"]:
		var tassel := ItemMats.cloth(Color(0.2, 0.35, 0.8) if tier == "mithril" else Color(0.7, 0.12, 0.05))
		_p(parent, ModelKit.cone(0.022, 0.09, 8), tassel, Vector3(0, top - 0.13, 0), Vector3(180, 0, 0))
