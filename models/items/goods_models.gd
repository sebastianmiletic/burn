class_name GoodsModels
extends RefCounted
## Everything that is not a tool, weapon or armour: ore chunks, ingots, gems,
## crystals, potions, food, block samples, crafting materials and relics.
## Sized like the real thing (a fist-sized ore chunk, a 12 cm ingot...),
## resting on y = 0.

const ORES := {
	# id: [host rock, ore colour, metal finish of the nuggets ("" = crystal), glow]
	"copper_ore": [Color(0.36, 0.33, 0.3), Color(0.9, 0.52, 0.32), "copper", 0.0],
	"tin_ore": [Color(0.42, 0.4, 0.38), Color(0.75, 0.76, 0.75), "tin", 0.0],
	"iron_ore": [Color(0.42, 0.33, 0.28), Color(0.62, 0.32, 0.2), "rust", 0.0],
	"silver_ore": [Color(0.22, 0.22, 0.25), Color(0.93, 0.94, 0.97), "silver", 0.0],
	"gold_ore": [Color(0.4, 0.36, 0.3), Color(1.0, 0.78, 0.32), "gold", 0.0],
	"mithril_ore": [Color(0.22, 0.24, 0.3), Color(0.6, 0.85, 1.0), "", 1.4],
	"adamantite_ore": [Color(0.16, 0.17, 0.16), Color(0.3, 0.9, 0.5), "", 1.2],
}

const STONES := {
	# id: [colour, accent, roughness]
	"stone": [Color(0.5, 0.49, 0.47), Color(0.36, 0.35, 0.34), 0.9],
	"cobble": [Color(0.46, 0.45, 0.43), Color(0.3, 0.3, 0.29), 0.92],
	"granite": [Color(0.66, 0.52, 0.48), Color(0.25, 0.22, 0.22), 0.75],
	"sandstone": [Color(0.82, 0.68, 0.48), Color(0.7, 0.52, 0.32), 0.95],
	"marble": [Color(0.84, 0.83, 0.8), Color(0.45, 0.46, 0.52), 0.35],
	"slate": [Color(0.3, 0.33, 0.38), Color(0.2, 0.22, 0.26), 0.7],
	"limestone": [Color(0.72, 0.69, 0.6), Color(0.55, 0.5, 0.4), 0.9],
	"basalt": [Color(0.26, 0.24, 0.24), Color(0.15, 0.14, 0.14), 0.85],
	"soul_sand": [Color(0.38, 0.29, 0.24), Color(0.25, 0.18, 0.15), 1.0],
	"dirt": [Color(0.42, 0.3, 0.19), Color(0.3, 0.2, 0.12), 1.0],
	"sand": [Color(0.84, 0.74, 0.52), Color(0.7, 0.6, 0.42), 1.0],
	"snow": [Color(0.93, 0.94, 0.97), Color(0.75, 0.8, 0.9), 0.7],
	"ash": [Color(0.42, 0.39, 0.38), Color(0.3, 0.28, 0.27), 1.0],
	"clay": [Color(0.72, 0.5, 0.4), Color(0.6, 0.4, 0.3), 0.8],
	"gravel": [Color(0.52, 0.5, 0.47), Color(0.35, 0.34, 0.32), 0.95],
}


static func _p(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	return ModelKit.part(parent, mesh, mat, pos, rot, scl)


## Builds `id` into `parent`. Returns false if this module does not know it.
static func build(parent: Node3D, id: String) -> bool:
	if ORES.has(id):
		ore(parent, id)
		return true
	if id.ends_with("_ingot"):
		ingot(parent, id.trim_suffix("_ingot"))
		return true
	if STONES.has(id):
		block(parent, id)
		return true
	match id:
		"coal", "charcoal":
			coal(parent, id == "charcoal")
		"hellstone":
			_p(parent, ItemMesh.rock(0.065, 77, 0.3, 2, Vector3(1.1, 0.8, 1.0)), ItemMats.molten(Color(0.16, 0.06, 0.05), Color(1.0, 0.25, 0.06), 6.0), Vector3(0, 0.05, 0))
		"obsidian":
			_p(parent, ItemMesh.rock(0.07, 13, 0.35, 1, Vector3(1.0, 0.9, 0.8)), ItemMats.gem(Color(0.14, 0.07, 0.2), 0.08, 0.3), Vector3(0, 0.055, 0))
		"ruby":
			gem(parent, Color(0.92, 0.08, 0.16), 8, Vector3.ONE)
		"sapphire":
			gem(parent, Color(0.12, 0.3, 1.0), 10, Vector3(1.2, 1.0, 0.85))
		"amethyst":
			gem(parent, Color(0.62, 0.3, 0.95), 6, Vector3(0.9, 1.15, 0.9))
		"ember_crystal":
			crystals(parent, Color(1.0, 0.45, 0.12), Color(0.2, 0.12, 0.1))
		"frost_shard":
			crystals(parent, Color(0.6, 0.9, 1.0), Color(0.75, 0.8, 0.85))
		"wood":
			log_piece(parent)
		"planks":
			planks(parent)
		"brick":
			bricks(parent)
		"thatch":
			thatch(parent)
		"bone":
			bone(parent)
		"stick":
			stick(parent)
		"glass_vial":
			vial(parent, Color(0, 0, 0, 0))
		"emberleaf":
			leaf(parent)
		"potion_health", "potion_greater", "potion_phoenix", "potion_ironskin", "potion_might":
			potion(parent, id)
		"bread":
			bread(parent)
		"apple":
			apple(parent)
		"raw_meat", "cooked_meat":
			drumstick(parent, id == "cooked_meat")
		"warden_sigil", "frost_crown", "dragonheart", "cerberus_fang", "crown_of_hades":
			relic(parent, id)
		_:
			return false
	return true


# --- Minerals -------------------------------------------------------------------------------

static func ore(parent: Node3D, id: String) -> void:
	var d: Array = ORES[id]
	var seed_ := id.hash() & 0xffff
	_p(parent, ItemMesh.rock(0.07, seed_, 0.26, 2, Vector3(1.15, 0.82, 1.0)), ItemMats.ore_rock(d[0], d[1]), Vector3(0, 0.055, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var metal: String = d[2]
	var count := 5 if metal != "" else 4
	for i in count:
		var a := rng.randf() * TAU
		var el := rng.randf_range(0.0, 1.2)
		var dir := Vector3(cos(a) * cos(el), sin(el), sin(a) * cos(el))
		var pos := Vector3(0, 0.055, 0) + dir * Vector3(0.075, 0.05, 0.065)
		if metal != "":
			_p(parent, ItemMesh.rock(rng.randf_range(0.012, 0.02), seed_ + i, 0.35, 1), ItemMats.metal(metal), pos)
		else:
			var c := ItemMesh.crystal(rng.randf_range(0.009, 0.014), rng.randf_range(0.04, 0.07))
			var mi := _p(parent, c, ItemMats.gem(d[1], 0.05, float(d[3])), pos - dir * 0.01)
			mi.basis = Basis(Quaternion(Vector3.UP, dir.normalized())) * Basis(Vector3.UP, rng.randf() * TAU)


static func coal(parent: Node3D, charcoal: bool) -> void:
	if charcoal:
		var m := ItemMats.make({"albedo": Color(0.055, 0.05, 0.048), "accent": Color(0.3, 0.12, 0.05), "roughness": 0.9, "finish": ItemMats.Finish.WOOD, "grain_dir": Vector3.UP})
		for i in 3:
			_p(parent, ItemMesh.bevel_box(Vector3(0.035, 0.12, 0.035), 0.006), m, Vector3(-0.04 + i * 0.04, 0.02 + (0.03 if i == 1 else 0.0), 0), Vector3(90, 10.0 * i - 10.0, 0))
		return
	var mat := ItemMats.make({"albedo": Color(0.07, 0.07, 0.075), "accent": Color(0.3, 0.3, 0.35), "roughness": 0.35, "finish": ItemMats.Finish.ORE, "specular_amount": 0.7})
	_p(parent, ItemMesh.rock(0.06, 5, 0.32, 1, Vector3(1.1, 0.85, 1.0)), mat, Vector3(0, 0.05, 0))
	_p(parent, ItemMesh.rock(0.03, 6, 0.3, 1), mat, Vector3(0.07, 0.025, 0.03))


static func gem(parent: Node3D, c: Color, facets: int, scl: Vector3) -> void:
	_p(parent, ItemMesh.gem_cut(0.045, facets), ItemMats.gem(c, 0.04, 0.9), Vector3(0, 0.04, 0), Vector3(-18, 0, 8), scl)


static func crystals(parent: Node3D, c: Color, base: Color) -> void:
	_p(parent, ItemMesh.rock(0.045, 21, 0.25, 1, Vector3(1.3, 0.5, 1.0)), ItemMats.stone(base, base.darkened(0.4)), Vector3(0, 0.02, 0))
	var mat := ItemMats.gem(c, 0.05, 2.2)
	var specs := [[Vector3(0, 0.02, 0), Vector3(0, 0, 0), 0.02, 0.13], [Vector3(0.03, 0.02, 0.01), Vector3(0, 0, -28), 0.014, 0.09],
		[Vector3(-0.03, 0.02, 0.015), Vector3(15, 0, 30), 0.015, 0.08], [Vector3(0.0, 0.02, -0.03), Vector3(-32, 0, 5), 0.012, 0.07]]
	for s: Array in specs:
		_p(parent, ItemMesh.crystal(s[2], s[3]), mat, s[0], s[1])


static func ingot(parent: Node3D, metal: String) -> void:
	var mat: Material = ItemMats.metal(metal)
	_p(parent, ItemMesh.ingot(0.13, 0.055, 0.032), mat)
	# Stamped maker's mark on the top.
	_p(parent, ItemMesh.bevel_box(Vector3(0.03, 0.003, 0.016), 0.001), mat, Vector3(0, 0.0325, 0))


static func block(parent: Node3D, id: String) -> void:
	var d: Array = STONES[id]
	var mat := ItemMats.stone(d[0], d[1], d[2])
	match id:
		"dirt", "sand", "snow", "ash", "soul_sand", "clay":
			# A heap, as loose material would sit.
			var prof := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.1, 0.0), Vector2(0.095, 0.02), Vector2(0.07, 0.055), Vector2(0.035, 0.078), Vector2(0.0, 0.085)])
			if id == "clay":
				_p(parent, ItemMesh.rock(0.06, 3, 0.12, 2, Vector3(1.3, 0.75, 1.0), true), mat, Vector3(0, 0.045, 0))
				return
			_p(parent, ItemMesh.lathe(prof, 18, true), mat)
			var rng := RandomNumberGenerator.new()
			rng.seed = id.hash()
			for i in 6:
				var a := rng.randf() * TAU
				var r := rng.randf_range(0.03, 0.08)
				_p(parent, ItemMesh.rock(rng.randf_range(0.008, 0.016), i, 0.3, 1), mat, Vector3(cos(a) * r, 0.085 - r * 0.85, sin(a) * r))
			if id == "soul_sand":
				_p(parent, ModelKit.sphere(0.01, 6), ItemMats.glow(Color(0.5, 0.8, 1.0), 2.0), Vector3(0.02, 0.08, 0.02))
		"gravel":
			var rng := RandomNumberGenerator.new()
			rng.seed = 99
			for i in 9:
				var a := rng.randf() * TAU
				var r := rng.randf_range(0.0, 0.07)
				_p(parent, ItemMesh.rock(rng.randf_range(0.018, 0.03), i + 40, 0.3, 1), ItemMats.stone(d[0].darkened(rng.randf() * 0.3), d[1]), Vector3(cos(a) * r, 0.02 + (0.07 - r) * 0.5, sin(a) * r))
		"cobble":
			var rng := RandomNumberGenerator.new()
			rng.seed = 5
			_p(parent, ItemMesh.bevel_box(Vector3(0.17, 0.17, 0.17), 0.01), ItemMats.stone(Color(0.3, 0.29, 0.28), Color(0.2, 0.2, 0.2)), Vector3(0, 0.085, 0))
			for x in 2:
				for y in 2:
					for z in 2:
						var c := Vector3((x - 0.5) * 0.09, 0.045 + y * 0.09, (z - 0.5) * 0.09)
						_p(parent, ItemMesh.rock(0.052, x * 4 + y * 2 + z + 60, 0.2, 1, Vector3(1.0, 0.85, 1.0)), ItemMats.stone(d[0].darkened(rng.randf() * 0.2), d[1]), c)
		_:
			_p(parent, ItemMesh.bevel_box(Vector3(0.18, 0.18, 0.18), 0.012), mat, Vector3(0, 0.09, 0))
			# Chipped corner for a quarried look.
			_p(parent, ItemMesh.rock(0.03, 7, 0.4, 1), mat, Vector3(0.085, 0.175, 0.085))


static func log_piece(parent: Node3D) -> void:
	var bark := ItemMats.bark(Color(0.32, 0.23, 0.15))
	var heart := ItemMats.wood(Color(0.78, 0.6, 0.38), Color(0.45, 0.3, 0.16))
	var prof := PackedVector2Array([Vector2(0.075, -0.11), Vector2(0.08, -0.05), Vector2(0.078, 0.05), Vector2(0.074, 0.11)])
	_p(parent, ItemMesh.lathe(prof, 14, true), bark, Vector3(0, 0.08, 0), Vector3(0, 0, 90))
	for side: float in [-1.0, 1.0]:
		_p(parent, ModelKit.cylinder(0.068, 0.068, 0.006, 16), heart, Vector3(side * 0.111, 0.08, 0), Vector3(0, 0, 90))


static func planks(parent: Node3D) -> void:
	var cols := [Color(0.68, 0.48, 0.28), Color(0.62, 0.43, 0.25), Color(0.72, 0.52, 0.31)]
	for i in 3:
		var m := ItemMats.wood(cols[i], Color(0.35, 0.22, 0.12))
		_p(parent, ItemMesh.bevel_box(Vector3(0.2, 0.022, 0.06), 0.004), m, Vector3(0.0, 0.011 + i * 0.023, -0.065 + i * 0.065 if i < 2 else 0.0), Vector3(0, 0 if i < 2 else 90, 0))
	# Nails.
	for i in 2:
		_p(parent, ModelKit.sphere(0.004, 5), ItemMats.metal("dark_iron"), Vector3(-0.08 + i * 0.16, 0.058, 0.0))


static func bricks(parent: Node3D) -> void:
	var m := ItemMats.stone(Color(0.62, 0.32, 0.24), Color(0.42, 0.2, 0.15), 0.9)
	var mortar := ItemMats.stone(Color(0.7, 0.68, 0.62), Color(0.5, 0.5, 0.48))
	_p(parent, ItemMesh.bevel_box(Vector3(0.11, 0.035, 0.05), 0.004), m, Vector3(-0.03, 0.0175, -0.03))
	_p(parent, ItemMesh.bevel_box(Vector3(0.11, 0.035, 0.05), 0.004), m, Vector3(0.03, 0.0175, 0.03))
	_p(parent, ItemMesh.bevel_box(Vector3(0.115, 0.006, 0.055), 0.002), mortar, Vector3(0.0, 0.037, 0.0), Vector3(0, 40, 0))
	_p(parent, ItemMesh.bevel_box(Vector3(0.11, 0.035, 0.05), 0.004), m, Vector3(0.0, 0.058, 0.0), Vector3(0, 40, 0))


static func thatch(parent: Node3D) -> void:
	var straw := ItemMats.make({"albedo": Color(0.78, 0.64, 0.34), "accent": Color(0.55, 0.42, 0.2), "roughness": 0.8, "finish": ItemMats.Finish.WOOD, "ascii_id": AsciiMaterialId.FOLIAGE})
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for i in 26:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.035
		_p(parent, ModelKit.cylinder(0.0028, 0.0028, 0.2 + rng.randf() * 0.03, 4), straw, Vector3(cos(a) * r, 0.04 + sin(a) * r, 0), Vector3(90, 0, rng.randf_range(-4, 4)))
	_p(parent, ItemMesh.lathe(PackedVector2Array([Vector2(0.038, -0.008), Vector2(0.04, 0.0), Vector2(0.038, 0.008)]), 12, true), ItemMats.cloth(Color(0.45, 0.33, 0.2)), Vector3(0, 0.04, 0), Vector3(90, 0, 0))


static func bone(parent: Node3D) -> void:
	var prof := PackedVector2Array([Vector2(0.0, -0.1), Vector2(0.022, -0.096), Vector2(0.026, -0.08), Vector2(0.014, -0.06), Vector2(0.011, 0.0),
		Vector2(0.014, 0.06), Vector2(0.026, 0.08), Vector2(0.022, 0.096), Vector2(0.0, 0.1)])
	_p(parent, ItemMesh.lathe(prof, 10, true, Vector2(1.0, 0.8)), ItemMats.bone(), Vector3(0, 0.025, 0), Vector3(0, 30, 90))
	for side: float in [-1.0, 1.0]:
		_p(parent, ModelKit.sphere(0.018, 8), ItemMats.bone(), Vector3(side * 0.085, 0.028, 0.012 * side), Vector3.ZERO)


static func stick(parent: Node3D) -> void:
	var path := PackedVector3Array([Vector3(0, -0.02, 0), Vector3(0.004, 0.08, 0), Vector3(-0.004, 0.18, 0.002), Vector3(0.002, 0.28, 0)])
	var m := ItemMats.wood(Color(0.55, 0.4, 0.24), Color(0.3, 0.2, 0.1))
	_p(parent, ItemMesh.tube(path, PackedFloat32Array([0.009, 0.009, 0.008, 0.007]), 7), m)
	_p(parent, ItemMesh.tube(PackedVector3Array([Vector3(0, 0.15, 0), Vector3(0.025, 0.19, 0)]), PackedFloat32Array([0.005, 0.002]), 5), m)


static func leaf(parent: Node3D) -> void:
	var m := ItemMats.make({"albedo": Color(0.72, 0.22, 0.1), "accent": Color(0.95, 0.6, 0.2), "roughness": 0.6, "finish": ItemMats.Finish.WOOD,
		"ascii_id": AsciiMaterialId.FOLIAGE, "emission_mode": ItemMats.Emit.VEINS, "emission_color": Color(1.0, 0.45, 0.1), "emission_energy": 0.8})
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(0.025, 0.03), Vector2(0.03, 0.07), Vector2(0.018, 0.11), Vector2(0, 0.13), Vector2(-0.018, 0.11), Vector2(-0.03, 0.07), Vector2(-0.025, 0.03)])
	for i in 3:
		_p(parent, ItemMesh.plate_even(pts, 0.002, 0.001), m, Vector3(0, 0.01 + i * 0.005, 0), Vector3(-75, -35.0 + i * 35.0, 0))
	_p(parent, ItemMesh.tube(PackedVector3Array([Vector3(0, 0.01, 0), Vector3(0, 0.0, 0.04)]), PackedFloat32Array([0.004, 0.003]), 5), ItemMats.wood(Color(0.4, 0.3, 0.15)))


# --- Potions and food --------------------------------------------------------------------------

static func vial(parent: Node3D, liquid: Color) -> void:
	var prof := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.018, 0.002), Vector2(0.02, 0.02), Vector2(0.02, 0.07), Vector2(0.012, 0.085), Vector2(0.011, 0.1), Vector2(0.014, 0.105), Vector2(0.0, 0.106)])
	_p(parent, ItemMesh.lathe(prof, 14, true), ItemMats.glass())
	if liquid.a > 0.0:
		_p(parent, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, 0.004), Vector2(0.018, 0.006), Vector2(0.018, 0.05), Vector2(0.0, 0.05)]), 14, true), ItemMats.liquid(liquid))
	_p(parent, ModelKit.cylinder(0.011, 0.009, 0.02, 8), ItemMats.wood(Color(0.62, 0.48, 0.32)), Vector3(0, 0.112, 0))


static func potion(parent: Node3D, id: String) -> void:
	var c := ItemDB.color(id)
	var glass := ItemMats.glass()
	var liquid := ItemMats.liquid(c)
	var cork := ItemMats.wood(Color(0.62, 0.48, 0.32), Color(0.4, 0.3, 0.2))
	var body: PackedVector2Array
	var neck_y := 0.11
	match id:
		"potion_greater":
			# Tall bottle with shoulders.
			body = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.034, 0.002), Vector2(0.037, 0.02), Vector2(0.037, 0.09), Vector2(0.03, 0.11),
				Vector2(0.014, 0.125), Vector2(0.012, 0.15), Vector2(0.016, 0.156), Vector2(0.0, 0.157)])
			neck_y = 0.16
		"potion_ironskin":
			body = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.045, 0.002), Vector2(0.046, 0.075), Vector2(0.03, 0.095),
				Vector2(0.013, 0.104), Vector2(0.012, 0.125), Vector2(0.016, 0.13), Vector2(0.0, 0.131)])
			neck_y = 0.135
		"potion_might":
			body = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.05, 0.002), Vector2(0.044, 0.03), Vector2(0.02, 0.09), Vector2(0.012, 0.105),
				Vector2(0.012, 0.125), Vector2(0.016, 0.13), Vector2(0.0, 0.131)])
			neck_y = 0.135
		_:
			# Round flask.
			var pts: Array[Vector2] = [Vector2(0.0, 0.0)]
			for i in 9:
				var a := -PI * 0.5 + PI * 0.85 * float(i) / 8.0
				pts.append(Vector2(cos(a) * 0.045 + 0.0001, 0.045 + sin(a) * 0.045))
			pts.append_array([Vector2(0.013, 0.1), Vector2(0.012, 0.12), Vector2(0.016, 0.126), Vector2(0.0, 0.127)])
			body = PackedVector2Array(pts)
			neck_y = 0.13
	var sides := 4 if id == "potion_ironskin" else 18
	var squash := Vector2(1.0, 1.0)
	# The glass is opaque in this renderer, so the filled part of the bottle
	# is drawn in the liquid's colour and only the shoulder and neck as glass.
	var fill_y := body[body.size() - 1].y * 0.6
	var low := PackedVector2Array()
	var high := PackedVector2Array()
	for k in body.size():
		var p := body[k]
		if p.y <= fill_y:
			low.append(p)
		else:
			if high.is_empty() and k > 0:
				var q := body[k - 1]
				var f := (fill_y - q.y) / maxf(p.y - q.y, 0.0001)
				var cut := Vector2(lerpf(q.x, p.x, f), fill_y)
				low.append(cut)
				high.append(cut)
			high.append(p)
	low.append(Vector2(0.0, fill_y))
	var rot := Vector3(0, 45 if sides == 4 else 0, 0)
	_p(parent, ItemMesh.lathe(low, sides, id != "potion_ironskin", squash), liquid, Vector3.ZERO, rot)
	if high.size() >= 2:
		var hp := PackedVector2Array([Vector2(0.0, fill_y)])
		hp.append_array(high)
		_p(parent, ItemMesh.lathe(hp, sides, id != "potion_ironskin", squash), glass, Vector3.ZERO, rot)
	# Meniscus ring where the liquid meets the glass.
	var mr := low[low.size() - 2].x
	_p(parent, ItemMesh.lathe(PackedVector2Array([Vector2(mr * 1.02, fill_y - 0.002), Vector2(mr * 1.025, fill_y), Vector2(mr * 1.02, fill_y + 0.002)]), maxi(sides, 12), true), ItemMats.glass(Color(1, 1, 1)), Vector3.ZERO, rot)
	_p(parent, ModelKit.cylinder(0.013, 0.011, 0.024, 10), cork, Vector3(0, neck_y, 0))
	# String around the neck and a paper label.
	_p(parent, ItemMesh.lathe(PackedVector2Array([Vector2(0.0135, neck_y - 0.03), Vector2(0.0155, neck_y - 0.027), Vector2(0.0135, neck_y - 0.024)]), 10, true), ItemMats.cloth(Color(0.75, 0.68, 0.5)))
	if id == "potion_phoenix":
		var gold := ItemMats.metal("gold")
		for i in 4:
			var a := TAU * float(i) / 4.0
			var path := PackedVector3Array()
			var rr := PackedFloat32Array()
			for k in 7:
				var t := -PI * 0.5 + PI * 0.85 * float(k) / 6.0
				path.append(Vector3(cos(a), 0, sin(a)) * (cos(t) * 0.0475 + 0.001) + Vector3(0, 0.045 + sin(t) * 0.0475, 0))
				rr.append(0.0022)
			_p(parent, ItemMesh.tube(path, rr, 4), gold)
		_p(parent, ItemMesh.gem_cut(0.012, 6), ItemMats.glow(Color(1.0, 0.6, 0.2), 4.0), Vector3(0, neck_y + 0.02, 0))
	elif id in ["potion_health", "potion_greater"]:
		var label := PackedVector2Array([Vector2(-0.02, -0.014), Vector2(0.02, -0.014), Vector2(0.02, 0.014), Vector2(-0.02, 0.014)])
		var r := 0.046 if id == "potion_health" else 0.038
		_p(parent, ItemMesh.plate_even(label, 0.0012, 0.0004), ItemMats.cloth(Color(0.86, 0.8, 0.64)), Vector3(0, 0.045 if id == "potion_health" else 0.055, r))


static func bread(parent: Node3D) -> void:
	var crust := ItemMats.food(Color(0.72, 0.45, 0.2), 0.55)
	var prof := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.05, 0.002), Vector2(0.058, 0.02), Vector2(0.052, 0.045), Vector2(0.035, 0.062), Vector2(0.0, 0.068)])
	_p(parent, ItemMesh.lathe(prof, 16, true, Vector2(1.7, 1.0)), crust)
	var cut := ItemMats.food(Color(0.93, 0.8, 0.55), 0.8)
	for i in 3:
		_p(parent, ItemMesh.bevel_box(Vector3(0.012, 0.006, 0.06), 0.002), cut, Vector3(-0.045 + i * 0.045, 0.064 - absf(i - 1) * 0.008, 0), Vector3(0, 30, 0))


static func apple(parent: Node3D) -> void:
	var skin := ItemMats.food(Color(0.75, 0.1, 0.08), 0.35)
	var prof := PackedVector2Array([Vector2(0.0, 0.006), Vector2(0.018, 0.0), Vector2(0.036, 0.012), Vector2(0.044, 0.035), Vector2(0.04, 0.06),
		Vector2(0.026, 0.074), Vector2(0.008, 0.07), Vector2(0.0, 0.064)])
	_p(parent, ItemMesh.lathe(prof, 18, true), skin)
	_p(parent, ItemMesh.tube(PackedVector3Array([Vector3(0, 0.064, 0), Vector3(0.004, 0.085, 0), Vector3(0.01, 0.095, 0)]), PackedFloat32Array([0.0025, 0.002, 0.0018]), 5), ItemMats.wood(Color(0.35, 0.25, 0.12)))
	var lf := PackedVector2Array([Vector2(0, 0), Vector2(0.012, 0.01), Vector2(0.02, 0.03), Vector2(0.0, 0.045), Vector2(-0.008, 0.02)])
	_p(parent, ItemMesh.plate_even(lf, 0.0015, 0.0006), ItemMats.make({"albedo": Color(0.25, 0.5, 0.15), "roughness": 0.6, "ascii_id": AsciiMaterialId.FOLIAGE}), Vector3(0.006, 0.088, 0), Vector3(-30, 40, -60))


static func drumstick(parent: Node3D, cooked: bool) -> void:
	var meat := ItemMats.food(Color(0.5, 0.26, 0.12) if cooked else Color(0.8, 0.32, 0.3), 0.45 if cooked else 0.4)
	var prof := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.028, 0.008), Vector2(0.042, 0.035), Vector2(0.04, 0.07), Vector2(0.022, 0.1), Vector2(0.012, 0.11), Vector2(0.0, 0.112)])
	_p(parent, ItemMesh.lathe(prof, 14, true, Vector2(1.0, 0.85)), meat, Vector3(0, 0.035, 0), Vector3(0, 0, -70))
	_p(parent, ModelKit.cylinder(0.008, 0.008, 0.05, 8), ItemMats.bone(), Vector3(0.12, 0.075, 0), Vector3(0, 0, -70))
	for side: float in [-1.0, 1.0]:
		_p(parent, ModelKit.sphere(0.011, 8), ItemMats.bone(), Vector3(0.143, 0.083, side * 0.008))


# --- Relics -----------------------------------------------------------------------------------

static func relic(parent: Node3D, id: String) -> void:
	match id:
		"warden_sigil":
			var stone := ItemMats.stone(Color(0.4, 0.42, 0.36), Color(0.25, 0.28, 0.22), 0.8)
			_p(parent, ModelKit.cylinder(0.07, 0.07, 0.02, 24), stone, Vector3(0, 0.07, 0), Vector3(90, 0, 0))
			_p(parent, ItemMesh.lathe(PackedVector2Array([Vector2(0.068, -0.013), Vector2(0.076, -0.01), Vector2(0.076, 0.01), Vector2(0.068, 0.013)]), 24, true), ItemMats.metal("bronze"), Vector3(0, 0.07, 0), Vector3(90, 0, 0))
			var rune := ItemMats.glow(Color(0.5, 1.0, 0.6), 4.0)
			_p(parent, ItemMesh.bevel_box(Vector3(0.008, 0.08, 0.004), 0.001), rune, Vector3(0, 0.07, 0.012))
			_p(parent, ItemMesh.bevel_box(Vector3(0.05, 0.008, 0.004), 0.001), rune, Vector3(0, 0.09, 0.012), Vector3(0, 0, 25))
			_p(parent, ItemMesh.bevel_box(Vector3(0.05, 0.008, 0.004), 0.001), rune, Vector3(0, 0.05, 0.012), Vector3(0, 0, -25))
		"frost_crown", "crown_of_hades":
			var hades := id == "crown_of_hades"
			var m := ItemMats.metal("dark_iron") if hades else ItemMats.metal("silver")
			_p(parent, ItemMesh.lathe(PackedVector2Array([Vector2(0.075, 0.0), Vector2(0.08, 0.004), Vector2(0.08, 0.03), Vector2(0.075, 0.034), Vector2(0.071, 0.03), Vector2(0.071, 0.004)]), 28, true), m)
			for i in 8:
				var a := TAU * float(i) / 8.0
				var tall := 0.07 if i % 2 == 0 else 0.045
				_p(parent, ModelKit.cone(0.014, tall, 4), m, Vector3(cos(a) * 0.076, 0.032 + tall * 0.5, sin(a) * 0.076))
				var tip := ItemMats.glow(Color(1.0, 0.4, 0.1), 5.0) if hades else ItemMats.gem(Color(0.6, 0.9, 1.0), 0.04, 2.0)
				if i % 2 == 0:
					_p(parent, ItemMesh.gem_cut(0.01, 6), tip, Vector3(cos(a) * 0.081, 0.017, sin(a) * 0.081), Vector3(0, -rad_to_deg(a) + 90.0, 90))
			if hades:
				_p(parent, ItemMesh.lathe(PackedVector2Array([Vector2(0.081, 0.006), Vector2(0.083, 0.012), Vector2(0.081, 0.018)]), 28, true), ItemMats.metal("gold"))
		"dragonheart":
			var prof := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.03, 0.02), Vector2(0.05, 0.05), Vector2(0.055, 0.08), Vector2(0.04, 0.105), Vector2(0.02, 0.112), Vector2(0.0, 0.1)])
			_p(parent, ItemMesh.lathe(prof, 16, true, Vector2(1.0, 0.75)), ItemMats.molten(Color(0.35, 0.05, 0.04), Color(1.0, 0.35, 0.08), 6.0))
			for i in 2:
				_p(parent, ItemMesh.tube(PackedVector3Array([Vector3(-0.01 + i * 0.02, 0.1, 0), Vector3(-0.015 + i * 0.03, 0.13, 0.005), Vector3(-0.02 + i * 0.04, 0.14, 0.0)]),
					PackedFloat32Array([0.01, 0.008, 0.006]), 6), ItemMats.food(Color(0.35, 0.06, 0.05), 0.4))
		"cerberus_fang":
			var path := PackedVector3Array([Vector3(0, 0.0, 0), Vector3(0.01, 0.06, 0), Vector3(0.03, 0.12, 0), Vector3(0.065, 0.16, 0), Vector3(0.1, 0.17, 0)])
			_p(parent, ItemMesh.tube(path, PackedFloat32Array([0.024, 0.02, 0.014, 0.007, 0.001]), 9), ItemMats.bone(Color(0.92, 0.88, 0.76)))
			_p(parent, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, -0.025), Vector2(0.026, -0.02), Vector2(0.028, 0.005), Vector2(0.024, 0.01)]), 10, true), ItemMats.food(Color(0.45, 0.12, 0.1), 0.5))
