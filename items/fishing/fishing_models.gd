class_name FishingModels
extends RefCounted
## Models for the village-life items (ItemDB "model_script"): fishing rods by
## tier, tackle and bait, every fish species, junk and treasure from the
## water, fish dishes and trade goods. Rods are built along +Y from the grip
## (HeldItems convention) and are ROD_LENGTH long; the line leaves the tip.

const ROD_LENGTH := {1: 1.55, 2: 1.75, 3: 1.7, 4: 1.85, 5: 1.95}


static func rod_length(item_id: String) -> float:
	return float(ROD_LENGTH.get(int(ItemDB.info(item_id).get("rod_tier", 1)), 1.6))


static func _p(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	return ModelKit.part(parent, mesh, mat, pos, rot, scl)


static func build(body: Node3D, id: String) -> bool:
	var inf := ItemDB.info(id)
	if inf.has("rod_tier"):
		rod(body, int(inf["rod_tier"]))
		return true
	if inf.has("fish"):
		fish(body, id, false)
		return true
	match id:
		"smoked_fish":
			fish(body, "fish_herring", true)
		"fish_steak":
			_steak(body)
		"fish_stew":
			_stew(body)
		"cheese":
			_cheese(body)
		"fishing_line":
			_spool(body)
		"river_reed":
			_reeds(body)
		"bait_worms":
			_bait_tin(body, false)
		"bait_glowgrub":
			_bait_tin(body, true)
		"bait_lure":
			_lure(body)
		"old_boot":
			_boot(body)
		"driftwood":
			_driftwood(body)
		"tangled_net":
			_net(body)
		"seaweed":
			_seaweed(body)
		"bottled_letter":
			_bottle(body)
		"sunken_coffer":
			_coffer(body)
		_:
			return false
	return true


# --- Rods -------------------------------------------------------------------------------------

## A rod of `tier`: grip, reel seat and reel, the tapering blank with line
## guides, and the line threaded to the tip.
static func rod(body: Node3D, tier: int) -> void:
	var length := float(ROD_LENGTH.get(tier, 1.6))
	var blank: Material
	var grip: Material = ItemMats.make({"albedo": Color(0.72, 0.55, 0.36), "accent": Color(0.45, 0.32, 0.2), "roughness": 0.9, "finish": ItemMats.Finish.STONE, "detail_scale": 9.0})
	var fitting: Material = ItemMats.metal("iron")
	var r0 := 0.013
	match tier:
		1:
			blank = ItemMats.wood(Color(0.62, 0.47, 0.28), Color(0.35, 0.24, 0.12))
			fitting = ItemMats.wood(Color(0.4, 0.28, 0.16))
		2:
			blank = ItemMats.make({"albedo": Color(0.78, 0.7, 0.42), "accent": Color(0.5, 0.42, 0.2), "roughness": 0.5, "finish": ItemMats.Finish.WOOD, "specular_amount": 0.6, "grain_dir": Vector3.UP})
			fitting = ItemMats.metal("copper")
		3:
			blank = ItemMats.wood(Color(0.45, 0.32, 0.2), Color(0.22, 0.14, 0.08))
			fitting = ItemMats.metal("iron")
			r0 = 0.015
		4:
			blank = ItemMats.metal("mithril")
			fitting = ItemMats.metal("silver")
			grip = ItemMats.leather(Color(0.18, 0.2, 0.3))
		_:
			blank = ItemMats.make({"albedo": Color(0.12, 0.42, 0.45), "accent": Color(0.05, 0.18, 0.2), "metallic": 0.5, "roughness": 0.25, "finish": ItemMats.Finish.GEM,
				"emission_mode": ItemMats.Emit.FRESNEL, "emission_color": Color(0.2, 0.9, 0.85), "emission_energy": 0.6})
			fitting = ItemMats.metal("mithril")
			grip = ItemMats.leather(Color(0.1, 0.22, 0.24))
	# Butt cap and grip.
	_p(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, -0.06), Vector2(0.017, -0.058), Vector2(0.019, -0.04), Vector2(0.0175, -0.03)]), 12), fitting)
	_p(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.0175, -0.03), Vector2(0.02, 0.02), Vector2(0.019, 0.12), Vector2(0.0165, 0.2), Vector2(0.015, 0.22)]), 12), grip)
	# Reel seat ring and the reel hanging under the rod.
	_p(body, ModelKit.cylinder(0.017, 0.017, 0.05, 12), fitting, Vector3(0, 0.25, 0))
	var reel_c := Vector3(0, 0.25, 0.055)
	_p(body, ModelKit.box(Vector3(0.012, 0.03, 0.04)), fitting, Vector3(0, 0.25, 0.028))
	_p(body, ModelKit.cylinder(0.04, 0.04, 0.03, 18), fitting, reel_c, Vector3(0, 0, 90))
	_p(body, ModelKit.cylinder(0.028, 0.028, 0.032, 14), ItemMats.cloth(Color(0.85, 0.83, 0.75)), reel_c, Vector3(0, 0, 90))
	_p(body, ModelKit.box(Vector3(0.006, 0.05, 0.008)), fitting, reel_c + Vector3(0.02, 0.02, 0.0), Vector3(0, 0, 0))
	_p(body, ModelKit.sphere(0.008, 8), ItemMats.wood(Color(0.3, 0.2, 0.12)), reel_c + Vector3(0.026, 0.045, 0.0))
	# The blank, tapering to the tip (reed rods show their joints).
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 9:
		var f := float(i) / 8.0
		pts.append(Vector3(0, 0.22 + (length - 0.22) * f, 0))
		radii.append(lerpf(r0, 0.0032, pow(f, 0.8)))
	_p(body, ItemMesh.tube(pts, radii, 8), blank)
	if tier == 2:
		for j in 4:
			var y := 0.45 + j * (length - 0.5) / 4.0
			var r := lerpf(r0, 0.0032, (y - 0.22) / (length - 0.22)) + 0.0025
			_p(body, ModelKit.cylinder(r, r, 0.014, 10), blank, Vector3(0, y, 0))
	# Line guides on little feet, the line running through them to the tip.
	var line := ItemMats.make({"albedo": Color(0.92, 0.92, 0.88), "roughness": 0.4, "finish": ItemMats.Finish.PLAIN})
	for j in 5:
		var y := 0.42 + j * (length - 0.48) / 4.6
		var gr := 0.012 - j * 0.0016
		_p(body, BossKit.torus("rod_guide_%d" % j, gr, 0.0015, 10, 4), fitting, Vector3(0, y, 0.018 + gr * 0.6), Vector3(90, 0, 0))
		_p(body, ModelKit.box(Vector3(0.003, 0.012, 0.016)), fitting, Vector3(0, y, 0.01))
	_p(body, ItemMesh.tube(PackedVector3Array([reel_c + Vector3(0, 0.03, -0.01), Vector3(0, length * 0.5, 0.02), Vector3(0, length, 0.006)]),
			PackedFloat32Array([0.0007, 0.0007, 0.0007]), 3, false), line)
	if tier >= 4:
		_p(body, ModelKit.sphere(0.006, 8), ItemMats.glow(Color(0.5, 0.9, 1.0) if tier == 4 else Color(0.3, 1.0, 0.85), 2.5), Vector3(0, length, 0.0))


# --- Fish ---------------------------------------------------------------------------------

const SHAPES := {
	# length, depth (top-bottom), width, tail spread, belly tint, stripes, eel?
	"fish_perch": [0.22, 0.38, 0.5, 0.6, Color(0.95, 0.85, 0.5), 6, false],
	"fish_carp": [0.3, 0.4, 0.55, 0.6, Color(0.95, 0.85, 0.6), 0, false],
	"fish_trout": [0.28, 0.3, 0.5, 0.55, Color(0.95, 0.75, 0.7), 0, false],
	"fish_catfish": [0.34, 0.28, 0.6, 0.5, Color(0.7, 0.68, 0.6), 0, false],
	"fish_pike": [0.5, 0.22, 0.45, 0.5, Color(0.9, 0.9, 0.7), 0, false],
	"fish_eel": [0.55, 0.1, 0.9, 0.2, Color(0.4, 0.38, 0.3), 0, true],
	"fish_herring": [0.2, 0.28, 0.4, 0.6, Color(0.95, 0.95, 0.98), 0, false],
	"fish_mackerel": [0.26, 0.26, 0.45, 0.65, Color(0.95, 0.95, 0.95), 8, false],
	"fish_cod": [0.42, 0.3, 0.55, 0.55, Color(0.9, 0.88, 0.8), 0, false],
	"fish_salmon": [0.5, 0.3, 0.45, 0.6, Color(0.95, 0.85, 0.85), 0, false],
	"fish_bass": [0.4, 0.4, 0.5, 0.6, Color(0.95, 0.95, 0.85), 0, false],
	"fish_tuna": [0.7, 0.34, 0.6, 0.85, Color(0.88, 0.9, 0.95), 0, false],
	"fish_frostfin": [0.45, 0.32, 0.4, 0.75, Color(0.95, 1.0, 1.0), 0, false],
	"fish_ember_eel": [0.6, 0.11, 0.9, 0.2, Color(1.0, 0.8, 0.3), 0, true],
	"fish_glowfin": [0.24, 0.34, 0.45, 0.6, Color(0.85, 1.0, 0.95), 0, false],
	"fish_swordfish": [0.95, 0.24, 0.55, 0.9, Color(0.85, 0.88, 0.92), 0, false],
	"fish_golden_koi": [0.38, 0.36, 0.55, 0.65, Color(1.0, 0.95, 0.75), 0, false],
	"fish_ghost_carp": [0.36, 0.4, 0.55, 0.6, Color(1.0, 1.0, 1.0), 0, false],
	"fish_abyssal_angler": [0.4, 0.55, 0.7, 0.45, Color(0.25, 0.28, 0.35), 0, false],
}


## A fish lying on its side along +X (head at +X), centred near the origin.
## `smoked` darkens it to a cured brown.
static func fish(body: Node3D, id: String, smoked: bool) -> void:
	var sh: Array = SHAPES.get(id, SHAPES["fish_perch"])
	var l := float(sh[0])
	var depth := float(sh[1])
	var width := float(sh[2])
	var eel := bool(sh[6])
	var col := ItemDB.color(id)
	var belly: Color = sh[4]
	if smoked:
		col = Color(0.5, 0.3, 0.14)
		belly = Color(0.7, 0.45, 0.2)
	var glow := id in ["fish_glowfin", "fish_ember_eel", "fish_ghost_carp"]
	var skin := ItemMats.make({"albedo": col, "accent": belly, "metallic": 0.35 if not smoked else 0.0, "roughness": 0.28 if not smoked else 0.7,
		"finish": ItemMats.Finish.GEM if not smoked else ItemMats.Finish.LEATHER, "bump_amount": 0.3, "sparkle_amount": 0.25 if not smoked else 0.0})
	if glow:
		skin = ItemMats.make({"albedo": col * 0.6, "accent": belly, "metallic": 0.2, "roughness": 0.3, "finish": ItemMats.Finish.GEM,
			"emission_mode": ItemMats.Emit.FRESNEL, "emission_color": col, "emission_energy": 1.6})
	var fin := ItemMats.make({"albedo": col.darkened(0.25), "roughness": 0.45, "finish": ItemMats.Finish.PLAIN, "specular_amount": 0.3})
	# Body: a lathe round the length axis, flattened side to side.
	var prof := PackedVector2Array()
	var n := 12
	for i in n + 1:
		var f := float(i) / n
		var r := l * depth * 0.5 * (pow(sin(PI * clampf(f * 0.95 + 0.03, 0.0, 1.0)), 0.75 if not eel else 0.3))
		if eel:
			r = l * depth * 0.5 * clampf(sin(PI * f) * 2.5, 0.0, 1.0)
		prof.append(Vector2(maxf(r, 0.0005) if i > 0 and i < n else 0.0, -l * 0.5 + l * f))
	var root := Node3D.new()
	body.add_child(root)
	root.rotation_degrees = Vector3(0, 0, -90)
	root.position = Vector3(0, l * depth * 0.5, 0)
	_p(root, ItemMesh.lathe(prof, 14, true, Vector2(1.0, width)), skin)
	# Belly stripe and bars (perch, mackerel).
	var stripes := int(sh[5])
	for s in stripes:
		var y := -l * 0.3 + float(s) / maxf(1.0, stripes - 1) * l * 0.55
		_p(root, ModelKit.box(Vector3(l * depth * 0.7, l * 0.022, l * depth * width * 1.04)), ItemMats.make({"albedo": col.darkened(0.55), "roughness": 0.4, "finish": ItemMats.Finish.PLAIN}),
				Vector3(0, y, 0))
	# Tail fin: a forked plate at the -Y (tail) end of the lathe.
	var spread := float(sh[3]) * l * 0.5
	var tail := PackedVector2Array([Vector2(0, 0), Vector2(-spread * 0.7, -spread * 0.9), Vector2(-spread * 0.2, -spread * 0.55), Vector2(0, -spread * 0.35),
		Vector2(spread * 0.2, -spread * 0.55), Vector2(spread * 0.7, -spread * 0.9)])
	if not eel:
		_p(root, ItemMesh.plate_even(tail, 0.002, 0.001), fin, Vector3(0, -l * 0.47, 0))
	# Dorsal and belly fins (the swordfish's sail, the eel's long ribbon).
	var dl := l * (0.35 if not eel else 0.8)
	var dorsal := PackedVector2Array([Vector2(-dl * 0.5, 0), Vector2(-dl * 0.25, l * depth * (0.3 if id != "fish_swordfish" else 0.7)), Vector2(dl * 0.4, l * depth * 0.12), Vector2(dl * 0.5, 0)])
	_p(root, ItemMesh.plate_even(dorsal, 0.0015, 0.0008), fin, Vector3(-l * depth * 0.42, -l * 0.02, 0), Vector3(0, 0, 90))
	var pelvic := PackedVector2Array([Vector2(-dl * 0.2, 0), Vector2(0.0, -l * depth * 0.2), Vector2(dl * 0.2, 0)])
	_p(root, ItemMesh.plate_even(pelvic, 0.0015, 0.0008), fin, Vector3(l * depth * 0.42, 0.0, 0), Vector3(0, 0, 90))
	# Eyes, gill line, and the bill / lantern / barbels of the special ones.
	var eye := ItemMats.make({"albedo": Color(0.02, 0.02, 0.02), "roughness": 0.05, "finish": ItemMats.Finish.GEM})
	for side: float in [-1.0, 1.0]:
		_p(root, ModelKit.sphere(l * 0.03, 8), eye, Vector3(-l * depth * 0.1, l * 0.38, side * l * depth * 0.5 * width * 0.55))
		_p(root, BossKit.torus("fish_gill_%d" % int(l * depth * 10000.0), l * depth * 0.32, l * 0.004, 12, 3), fin, Vector3(0, l * 0.3, side * 0.0), Vector3(0, 0, 0), Vector3(1.0, 1.0, width * 1.05))
	match id:
		"fish_swordfish":
			_p(root, ModelKit.cylinder(0.003, l * 0.025, l * 0.4, 8), skin, Vector3(0, l * 0.5 + l * 0.18, 0))
		"fish_abyssal_angler":
			_p(root, ItemMesh.tube(PackedVector3Array([Vector3(-l * 0.12, l * 0.4, 0), Vector3(-l * 0.32, l * 0.48, 0), Vector3(-l * 0.3, l * 0.62, 0)]), PackedFloat32Array([0.003, 0.002, 0.0015]), 5), fin)
			_p(root, ModelKit.sphere(l * 0.04, 10), ItemMats.glow(Color(0.5, 1.0, 0.9), 4.0), Vector3(-l * 0.3, l * 0.64, 0))
		"fish_catfish":
			for side: float in [-1.0, 1.0]:
				_p(root, ItemMesh.tube(PackedVector3Array([Vector3(-l * 0.02, l * 0.46, side * 0.01), Vector3(-l * 0.08, l * 0.55, side * 0.05), Vector3(-l * 0.16, l * 0.52, side * 0.08)]),
						PackedFloat32Array([0.002, 0.0015, 0.001]), 4), fin)


static func _steak(body: Node3D) -> void:
	var flesh := ItemMats.food(Color(0.92, 0.6, 0.42), 0.5)
	_p(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.07, 0.0), Vector2(0.075, 0.01), Vector2(0.07, 0.03), Vector2(0.0, 0.03)]), 18, true, Vector2(1.0, 0.7)), flesh)
	_p(body, ModelKit.cylinder(0.04, 0.04, 0.002, 16), ItemMats.food(Color(0.55, 0.3, 0.15), 0.6), Vector3(0, 0.031, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.7))
	for i in 3:
		_p(body, ModelKit.box(Vector3(0.11, 0.003, 0.006)), ItemMats.food(Color(0.35, 0.18, 0.08), 0.7), Vector3(0, 0.032, -0.02 + i * 0.02), Vector3(0, 35, 0))


static func _stew(body: Node3D) -> void:
	var bowl := ItemMats.wood(Color(0.5, 0.33, 0.18))
	_p(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.075, 0.035), Vector2(0.08, 0.06), Vector2(0.072, 0.06), Vector2(0.066, 0.038), Vector2(0.0, 0.02)]), 20), bowl)
	_p(body, ModelKit.cylinder(0.068, 0.068, 0.004, 18), ItemMats.food(Color(0.75, 0.5, 0.25), 0.25), Vector3(0, 0.05, 0))
	for i in 5:
		var a := float(i) * 1.3
		_p(body, ModelKit.sphere(0.012, 6), ItemMats.food(Color(0.95, 0.85, 0.7), 0.5), Vector3(cos(a) * 0.035, 0.053, sin(a) * 0.035))


static func _cheese(body: Node3D) -> void:
	var rind := ItemMats.food(Color(0.9, 0.7, 0.3), 0.55)
	_p(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.075, 0.0), Vector2(0.082, 0.02), Vector2(0.078, 0.045), Vector2(0.0, 0.05)]), 22), rind)
	_p(body, ModelKit.box(Vector3(0.06, 0.044, 0.002)), ItemMats.food(Color(0.98, 0.88, 0.55), 0.7), Vector3(0.03, 0.025, 0.0))


static func _spool(body: Node3D) -> void:
	_p(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.04, 0.008), Vector2(0.015, 0.008), Vector2(0.015, 0.062), Vector2(0.04, 0.062), Vector2(0.04, 0.07), Vector2(0.0, 0.07)]), 16), ItemMats.wood(Color(0.55, 0.38, 0.2)))
	_p(body, ModelKit.cylinder(0.033, 0.033, 0.052, 16), ItemMats.cloth(Color(0.88, 0.86, 0.78)), Vector3(0, 0.035, 0))


static func _reeds(body: Node3D) -> void:
	var cane := ItemMats.make({"albedo": Color(0.75, 0.7, 0.42), "accent": Color(0.45, 0.4, 0.2), "roughness": 0.5, "finish": ItemMats.Finish.WOOD, "grain_dir": Vector3.UP})
	for i in 5:
		var a := float(i) * TAU / 5.0
		_p(body, ModelKit.cylinder(0.008, 0.01, 0.5, 8), cane, Vector3(cos(a) * 0.014, 0.25, sin(a) * 0.014), Vector3(sin(a) * 3.0, 0, cos(a) * 3.0))
	_p(body, ModelKit.cylinder(0.03, 0.03, 0.02, 12), ItemMats.cloth(Color(0.6, 0.5, 0.35)), Vector3(0, 0.2, 0))


static func _bait_tin(body: Node3D, glow: bool) -> void:
	var tin := ItemMats.metal("tin") if not glow else ItemMats.glass(Color(0.6, 0.9, 0.6))
	_p(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.042, 0.004), Vector2(0.042, 0.045), Vector2(0.038, 0.047), Vector2(0.0, 0.03)]), 18), tin)
	_p(body, ModelKit.cylinder(0.038, 0.038, 0.01, 16), ItemMats.stone(Color(0.3, 0.22, 0.15)), Vector3(0, 0.038, 0))
	var worm := ItemMats.food(Color(0.75, 0.42, 0.42), 0.3) if not glow else ItemMats.glow(Color(0.5, 1.0, 0.4), 2.5)
	for i in 3:
		var a := float(i) * 2.1
		var c := Vector3(cos(a) * 0.015, 0.044, sin(a) * 0.015)
		_p(body, ItemMesh.tube(PackedVector3Array([c, c + Vector3(0.01, 0.015, 0.0), c + Vector3(0.018, 0.022, 0.012), c + Vector3(0.03, 0.012, 0.01)]), PackedFloat32Array([0.0035, 0.0035, 0.003, 0.002]), 6), worm)


static func _lure(body: Node3D) -> void:
	_p(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.008, 0.01), Vector2(0.01, 0.04), Vector2(0.006, 0.06), Vector2(0.0, 0.065)]), 10, true, Vector2(1.0, 0.6)), ItemMats.metal("copper"))
	for i in 4:
		var a := float(i) * 25.0 - 37.0
		_p(body, ItemMesh.plate_even(PackedVector2Array([Vector2(0, 0), Vector2(0.008, -0.02), Vector2(0.0, -0.05), Vector2(-0.008, -0.02)]), 0.001, 0.0005),
				ItemMats.cloth([Color(0.9, 0.3, 0.2), Color(1.0, 0.8, 0.2), Color(0.2, 0.5, 0.9), Color(0.95, 0.95, 0.9)][i]), Vector3(0, 0.005, 0), Vector3(0, a * 2.0, a))
	_p(body, BossKit.torus("lure_hook", 0.01, 0.0012, 10, 4), ItemMats.metal("steel"), Vector3(0, -0.01, 0), Vector3(90, 0, 0))


static func _boot(body: Node3D) -> void:
	var leather := ItemMats.leather(Color(0.22, 0.17, 0.12))
	_p(body, ItemMesh.bevel_box(Vector3(0.09, 0.025, 0.24), 0.01), leather, Vector3(0, 0.012, 0.03))
	_p(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.045, 0.0), Vector2(0.05, 0.08), Vector2(0.048, 0.2), Vector2(0.044, 0.2)]), 12, true, Vector2(1.0, 1.15)), leather, Vector3(0, 0.02, -0.04))
	_p(body, ModelKit.sphere(0.03, 8), ItemMats.make({"albedo": Color(0.2, 0.35, 0.15), "roughness": 0.8, "finish": ItemMats.Finish.CLOTH}), Vector3(0.02, 0.21, -0.05), Vector3.ZERO, Vector3(1.4, 0.6, 1.0))


static func _driftwood(body: Node3D) -> void:
	var wood := ItemMats.make({"albedo": Color(0.7, 0.66, 0.6), "accent": Color(0.45, 0.42, 0.38), "roughness": 0.9, "finish": ItemMats.Finish.BARK, "bump_amount": 1.5})
	_p(body, ItemMesh.tube(PackedVector3Array([Vector3(-0.2, 0.03, 0), Vector3(-0.05, 0.04, 0.02), Vector3(0.08, 0.03, -0.01), Vector3(0.2, 0.05, 0.02)]), PackedFloat32Array([0.025, 0.03, 0.026, 0.012]), 8), wood)
	_p(body, ItemMesh.tube(PackedVector3Array([Vector3(0.0, 0.04, 0.0), Vector3(0.04, 0.07, 0.05), Vector3(0.06, 0.08, 0.1)]), PackedFloat32Array([0.012, 0.009, 0.004]), 6), wood)


static func _net(body: Node3D) -> void:
	var cord := ItemMats.cloth(Color(0.55, 0.5, 0.38))
	_p(body, ItemMesh.rock(0.09, 7, 0.35, 2, Vector3(1.0, 0.55, 0.9)), ItemMats.make({"albedo": Color(0.45, 0.4, 0.3), "roughness": 0.95, "finish": ItemMats.Finish.CLOTH, "detail_scale": 18.0}), Vector3(0, 0.05, 0))
	for i in 4:
		var a := float(i) * 1.6
		_p(body, BossKit.torus("net_float", 0.02, 0.008, 10, 5), ItemMats.wood(Color(0.7, 0.5, 0.25)), Vector3(cos(a) * 0.08, 0.04 + i * 0.01, sin(a) * 0.07), Vector3(90, a * 40.0, 0))
	_p(body, ItemMesh.tube(PackedVector3Array([Vector3(-0.1, 0.02, 0.05), Vector3(0.0, 0.1, -0.02), Vector3(0.12, 0.03, 0.04)]), PackedFloat32Array([0.003, 0.003, 0.003]), 4), cord)


static func _seaweed(body: Node3D) -> void:
	var weed := ItemMats.make({"albedo": Color(0.18, 0.36, 0.16), "roughness": 0.3, "finish": ItemMats.Finish.PLAIN, "specular_amount": 0.7, "ascii_id": AsciiMaterialId.FOLIAGE})
	for i in 5:
		var a := float(i) * TAU / 5.0
		var blade := PackedVector2Array([Vector2(-0.01, 0), Vector2(0.012, 0), Vector2(0.018, 0.08), Vector2(0.0, 0.16), Vector2(-0.016, 0.08)])
		_p(body, ItemMesh.plate_even(blade, 0.0015, 0.0006), weed, Vector3(cos(a) * 0.01, 0, sin(a) * 0.01), Vector3(sin(a) * 40.0, rad_to_deg(a), cos(a) * 30.0))


static func _bottle(body: Node3D) -> void:
	_p(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.032, 0.0), Vector2(0.036, 0.01), Vector2(0.036, 0.1), Vector2(0.03, 0.12), Vector2(0.012, 0.135), Vector2(0.011, 0.17), Vector2(0.0, 0.17)]), 16), ItemMats.glass(Color(0.55, 0.8, 0.65)))
	_p(body, ModelKit.cylinder(0.0115, 0.01, 0.022, 10), ItemMats.wood(Color(0.55, 0.38, 0.22)), Vector3(0, 0.175, 0))
	_p(body, ModelKit.cylinder(0.018, 0.018, 0.08, 12), ItemMats.cloth(Color(0.88, 0.82, 0.65)), Vector3(0.0, 0.055, 0.0), Vector3(0, 0, 8))
	_p(body, ModelKit.cylinder(0.019, 0.019, 0.006, 12), ItemMats.cloth(Color(0.6, 0.1, 0.08)), Vector3(0.0, 0.06, 0.0))


static func _coffer(body: Node3D) -> void:
	var wood := ItemMats.wood(Color(0.32, 0.22, 0.14), Color(0.18, 0.12, 0.07))
	var iron := ItemMats.metal("dark_iron")
	_p(body, ItemMesh.bevel_box(Vector3(0.2, 0.1, 0.13), 0.006), wood, Vector3(0, 0.05, 0))
	var lid := ItemMesh.lathe(PackedVector2Array([Vector2(0.0, -0.1), Vector2(0.065, -0.1), Vector2(0.065, 0.1), Vector2(0.0, 0.1)]), 10, false, Vector2(1.0, 0.55))
	_p(body, lid, wood, Vector3(0, 0.1, 0), Vector3(0, 0, 90), Vector3(1.0, 1.0, 1.0))
	for x: float in [-0.07, 0.0, 0.07]:
		_p(body, ItemMesh.bevel_box(Vector3(0.016, 0.105, 0.136), 0.002), iron, Vector3(x, 0.052, 0))
	_p(body, ItemMesh.bevel_box(Vector3(0.03, 0.035, 0.012), 0.003), ItemMats.metal("bronze"), Vector3(0, 0.1, 0.068))
	var barn := ItemMats.stone(Color(0.75, 0.72, 0.62), Color(0.4, 0.38, 0.32))
	for i in 7:
		var a := float(i) * 0.9
		_p(body, ModelKit.cone(0.008, 0.008, 6), barn, Vector3(cos(a) * 0.09, 0.02 + float(i % 3) * 0.03, sin(a) * 0.06))
