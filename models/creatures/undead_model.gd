class_name UndeadModel
extends MobHumanoid
## Risen skeletons and skeleton archers: an anatomical skeleton bone by bone -
## a skull with deep sockets, cheekbones, nasal cavity, teeth and a hinged
## mandible, a curved column of vertebrae, a ribcage of paired ribs round a
## sternum, clavicles and shoulder blades, a pelvis with iliac wings, long
## bones with knuckled joint ends (humerus, radius and ulna, femur, kneecap,
## tibia and fibula) and articulated hands and feet - lit by ember eyes.
## Gear by variant: rusted kettle helm, round shield, pauldrons, a dented
## breastplate and faulds for the old knight; a hood, mantle, quiver of
## fletched arrows and a recurve bow for the archer; tattered rags on all.

const ARCHER_GEAR := ["hood", "quiver", "rags"]

var gear_list: Array = []
var bone_color := Color(0.82, 0.79, 0.7)
var rag_color := Color(0.22, 0.16, 0.12)
var eye_color := Color(1.0, 0.35, 0.1)
var metal_color := Color(0.36, 0.32, 0.28)
var _eye_fx: GPUParticles3D


## `gear`: any of "helmet", "great_helm", "shield", "pauldrons", "breastplate", "rags", "hood", "quiver".
func _init(style_dict := {}, gear_items: Array = [], opts := {}) -> void:
	gear_list = gear_items
	bone_color = style_dict.get("bone", bone_color)
	rag_color = style_dict.get("cloth", rag_color)
	eye_color = style_dict.get("eyes", eye_color)
	metal_color = opts.get("metal", metal_color)
	var b := float(style_dict.get("bulk", 1.0))
	var key := "undead_%s_%.2f_%s" % ["_".join(PackedStringArray(gear_items)), b, "cloak" if style_dict.get("cloak", false) else ""]
	super(style_dict, key)


func _flesh_materials() -> Array:
	return []


func _gear_materials() -> Dictionary:
	return {
		"bone": BossKit.bone({"skinned": true, "albedo": bone_color, "grime": 0.45}),
		"dark": ModelKit.mat(Color(0.015, 0.012, 0.01), AsciiMaterialId.SOLID, 0.95, 0.0, 0.0),
		"eyes": BossKit.glow(eye_color, 7.0, 0.25),
		"metal": BossKit.metal({"skinned": true, "albedo": metal_color, "rust": 0.38, "wear": 0.55, "grime": 0.6, "roughness": 0.55}),
		"leather": BossKit.leather({"skinned": true, "albedo": Color(0.42, 0.32, 0.24)}),
		"wood": BossKit.wood(Color(0.2, 0.14, 0.09), {"skinned": true}),
		"wood_light": BossKit.wood(Color(0.4, 0.3, 0.2), {"skinned": true, "albedo": Color(0.75, 0.62, 0.45)}),
		"cloth": BossKit.cloth(rag_color, rag_color.darkened(0.35), {"skinned": true, "tatter": 0.7, "grime": 0.75}),
	}


func _after_mob() -> void:
	var rags := BossKit.cloth(rag_color, rag_color.darkened(0.35), {"skinned": true, "tatter": 0.85, "grime": 0.8})
	var k := _kit_key()
	if style.get("cloak", false) and _cloak_first >= 0:
		skinned(BossKit.cloak(k + "_cloak", body, style, 13, 13, 0.01, 1.15, 0.0), rags)
	# Ember wisps rising from the sockets.
	var fx := fx_point(R.HEAD, Vector3(0, 1.72, -0.07))
	_eye_fx = BossKit.emitter(fx, "mote", 5, Vector3(0.04, 0.01, 0.01), eye_color, 0.035, 0.8, 0.35)


func set_dead(is_dead: bool) -> void:
	super.set_dead(is_dead)
	if _eye_fx != null:
		_eye_fx.emitting = not is_dead


# --- Bones ---------------------------------------------------------------------------------

func _sculpt() -> void:
	var k := _kit_key()
	_skull(k)
	_spine(k)
	_neck(k)
	_ribcage(k)
	_pelvis(k)
	for side: float in [-1.0, 1.0]:
		_arm(k, side)
		_leg(k, side)
	if "helmet" in gear_list:
		_helmet(k, false)
	if "great_helm" in gear_list:
		_helmet(k, true)
	if "pauldrons" in gear_list:
		for side: float in [-1.0, 1.0]:
			var o := 0 if side < 0.0 else 5
			var asm := BossKit.assembly()
			pauldron(asm, BossKit.metal(), "sk", _rest[R.UARM_L + o] + Vector3(side * 0.0, -0.02, 0.0), side, 0.1, 1, Color(0.75, 0.72, 0.68))
			take(asm, "metal", R.UARM_L + o)
			# A leather strap across the chest holds them.
			gear("leather", BossKit.torus(k + "_pstrap", 0.075, 0.008, 12, 4), R.UARM_L + o, Transform3D(Basis(Vector3.FORWARD, side * 0.3), _rest[R.UARM_L + o] + Vector3(-side * 0.02, -0.06, 0)), Color(1, 1, 1))
	if "breastplate" in gear_list:
		_breastplate(k)
	if "shield" in gear_list:
		_shield(k)
	if "hood" in gear_list:
		_hood(k)
	if "quiver" in gear_list:
		_quiver(k)
	if "rags" in gear_list:
		_rags(k)


## A long bone along `from` -> `to` with knuckled ends.
func _long_bone(key: String, from: Vector3, to: Vector3, r: float, b: int, head_r := 1.6, tint := Color(1, 1, 1)) -> void:
	var l := from.distance_to(to)
	var prof := PackedVector2Array([Vector2(r * 0.6, -r * 0.6), Vector2(r * head_r, 0.0), Vector2(r * head_r * 0.95, l * 0.06),
		Vector2(r * 1.05, l * 0.16), Vector2(r * 0.9, l * 0.5), Vector2(r * 1.05, l * 0.84), Vector2(r * head_r * 0.95, l * 0.94),
		Vector2(r * head_r, l), Vector2(r * 0.6, l + r * 0.6)])
	gear("bone", BossKit.lathe("%s_lb_%d_%d" % [key, int(r * 1000.0), int(l * 1000.0)], prof, 9, 1.0, 0.85, true, true), b, span(from, to), tint)


func _skull(k: String) -> void:
	var h := R.HEAD
	var c := Vector3(0, 1.735, -0.005)
	# Cranium: a long ellipsoid, flatter at the sides.
	gear("bone", OrganicMesh.blob(k + "_cranium", Vector3(0.072, 0.082, 0.094), 0.04, 5, 18), h, Transform3D(Basis(), c))
	# Brow ridge over the sockets, cheekbones and zygomatic arches.
	var brow := PackedVector3Array()
	var brow_r := PackedVector2Array()
	for i in 9:
		var a := lerpf(-1.1, 1.1, i / 8.0)
		brow.append(Vector3(sin(a) * 0.066, 1.725 + cos(a * 2.0) * 0.004, -0.07 - cos(a) * 0.022))
		brow_r.append(Vector2(0.012, 0.009))
	gear("bone", OrganicMesh.sweep(k + "_brow", brow, brow_r, 6), h)
	for sx: float in [-1.0, 1.0]:
		gear("bone", OrganicMesh.blob(k + "_cheek", Vector3(0.02, 0.016, 0.022), 0.05, 7, 8), h, Transform3D(Basis(), Vector3(sx * 0.05, 1.676, -0.068)))
		gear("bone", OrganicMesh.bezier(k + "_zyg_%d" % int(sx), Vector3.ZERO, Vector3(sx * 0.012, 0.0, 0.03), Vector3(sx * 0.008, 0.004, 0.058), 0.007, 0.006, 5, 6), h, Transform3D(Basis(), Vector3(sx * 0.058, 1.676, -0.055)))
		# Sockets: dark hollows with an ember deep inside.
		gear("dark", OrganicMesh.blob(k + "_socket", Vector3(0.021, 0.019, 0.014), 0.08, 9, 10), h, Transform3D(Basis(), Vector3(sx * 0.031, 1.703, -0.082)))
		gear("eyes", ModelKit.sphere(0.0075, 8), h, Transform3D(Basis(), Vector3(sx * 0.031, 1.702, -0.088)))
		# Temples and the mastoid behind the jaw hinge.
		gear("bone", OrganicMesh.blob(k + "_mastoid", Vector3(0.012, 0.018, 0.012), 0.05, 11, 6), h, Transform3D(Basis(), Vector3(sx * 0.055, 1.66, 0.012)))
	# Upper jaw (maxilla) and the nasal cavity.
	gear("bone", OrganicMesh.blob(k + "_maxilla", Vector3(0.042, 0.03, 0.036), 0.04, 13, 12), h, Transform3D(Basis(), Vector3(0, 1.652, -0.064)))
	gear("dark", OrganicMesh.blob(k + "_nasal", Vector3(0.011, 0.017, 0.008), 0.05, 15, 8), h, Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(0, 1.677, -0.096)))
	_teeth(k, h, 1.637, -1.0)
	# Mandible on the jaw bone: a U of bone from hinge to chin and back.
	var jaw := PackedVector3Array()
	var jaw_r := PackedVector2Array()
	for i in 13:
		var t := float(i) / 12.0
		var a := lerpf(-PI * 0.5, PI * 0.5, t)
		var x := sin(a) * 0.048
		var z := -cos(a) * 0.075 + 0.0
		var y := 1.608 - cos(a) * 0.008
		if absf(a) > 1.25:
			# Rami rising to the hinge.
			var f := (absf(a) - 1.25) / (PI * 0.5 - 1.25)
			y = lerpf(1.608, 1.66, f)
			z = lerpf(z, -0.02, f)
		jaw.append(Vector3(x, y, z - 0.012))
		jaw_r.append(Vector2(0.007, 0.014))
	gear("bone", OrganicMesh.sweep(k + "_mandible", jaw, jaw_r, 6), R.JAW)
	_teeth(k, R.JAW, 1.621, 1.0)


func _teeth(k: String, b: int, y: float, dir: float) -> void:
	for i in 10:
		var a := lerpf(-1.15, 1.15, i / 9.0)
		var l := 0.013 if absf(a) < 0.6 else 0.011
		var p := Vector3(sin(a) * 0.036, y, -cos(a) * 0.05 - 0.034)
		gear("bone", OrganicMesh.bezier("%s_tooth_%d" % [k, int(dir)], Vector3.ZERO, Vector3(0, -dir * l * 0.5, 0), Vector3(0, -dir * l, 0), 0.0045, 0.0032, 2, 5), b,
			Transform3D(Basis(), p), Color(0.92, 0.88, 0.72))


func _spine(k: String) -> void:
	for i in 21:
		var t := float(i) / 20.0
		var y := lerpf(0.95, 1.49, t)
		# The S-curve: lumbar forward, thoracic back, neck forward.
		var z := 0.035 + sin(t * PI * 1.6 - 0.3) * 0.02
		var b := R.HIPS
		if y > 1.49:
			b = R.NECK
		elif y > 1.17:
			b = R.CHEST
		elif y > 1.03:
			b = R.SPINE
		var s := 1.0 if y < 1.48 else 0.7
		if y < 1.05:
			s = 1.2
		gear("bone", OrganicMesh.blob(k + "_vert", Vector3(0.019, 0.011, 0.017) * s, 0.08, 17, 7), b, Transform3D(Basis(), Vector3(0, y, z)))
		# Spinous process pointing back and down, transverse processes to the sides.
		gear("bone", OrganicMesh.bezier(k + "_spinous", Vector3.ZERO, Vector3(0, -0.004, 0.012), Vector3(0, -0.012, 0.022), 0.006, 0.003, 3, 5), b, Transform3D(Basis().scaled(Vector3.ONE * s), Vector3(0, y, z + 0.012)))
		if i % 2 == 0:
			for sx: float in [-1.0, 1.0]:
				gear("bone", OrganicMesh.bezier(k + "_transv_%d" % int(sx), Vector3.ZERO, Vector3(sx * 0.012, 0, 0.004), Vector3(sx * 0.022, -0.002, 0.008), 0.004, 0.003, 3, 4), b, Transform3D(Basis().scaled(Vector3.ONE * s), Vector3(0, y, z)))


func _neck(k: String) -> void:
	for i in 5:
		var y := 1.5 + i * 0.026
		gear("bone", OrganicMesh.blob(k + "_cerv", Vector3(0.014, 0.009, 0.013), 0.08, 18, 8), R.NECK, Transform3D(Basis(), Vector3(0, y, 0.022 - i * 0.004)))
		gear("bone", OrganicMesh.bezier(k + "_cspin", Vector3.ZERO, Vector3(0, -0.003, 0.008), Vector3(0, -0.008, 0.014), 0.004, 0.002, 3, 4), R.NECK, Transform3D(Basis(), Vector3(0, y, 0.03 - i * 0.004)))


func _ribcage(k: String) -> void:
	var c := R.CHEST
	for i in 10:
		var yb := 1.45 - i * 0.032
		var depth := 0.085 + sin(float(i) / 9.0 * PI) * 0.022
		var w := 0.075 + sin(minf(1.0, float(i) / 6.0) * PI * 0.5) * 0.06 - maxf(0.0, i - 7.0) * 0.012
		var reach := PI if i < 7 else lerpf(0.8, 0.55, float(i - 7) / 2.0) * PI
		for sx: float in [-1.0, 1.0]:
			var path := PackedVector3Array()
			var radii := PackedVector2Array()
			for j in 10:
				var a := reach * float(j) / 9.0
				var y := yb - sin(a * 0.5) * (0.055 + i * 0.006) - sin(a) * 0.012
				path.append(Vector3(sx * sin(a) * w, y, cos(a) * depth - 0.012))
				radii.append(Vector2(0.0045, 0.009) * (1.0 - 0.25 * float(j) / 9.0))
			gear("bone", OrganicMesh.sweep("%s_rib_%d_%d" % [k, i, int(sx)], path, radii, 5), c, Transform3D.IDENTITY, Color(0.95, 0.94, 0.92) if i < 7 else Color(0.88, 0.86, 0.82))
	# Sternum.
	gear("bone", OrganicMesh.blob(k + "_sternum", Vector3(0.016, 0.085, 0.008), 0.05, 19, 10), c, Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(0, 1.33, -0.098)))
	for sx: float in [-1.0, 1.0]:
		var o := 0 if sx < 0.0 else 5
		# Clavicle from the sternum to the shoulder, shoulder blade on the back.
		var sh := _rest[R.UARM_L + o]
		gear("bone", OrganicMesh.bezier(k + "_clav_%d" % int(sx), Vector3.ZERO, Vector3(sx * 0.07, 0.02, 0.02), sh - Vector3(sx * 0.02, 1.415, -0.08) + Vector3(0, 0, -0.0), 0.008, 0.007, 7, 6), R.CLAV_L + o, Transform3D(Basis(), Vector3(sx * 0.018, 1.415, -0.085)))
		gear("bone", OrganicMesh.blob(k + "_scapula", Vector3(0.05, 0.066, 0.009), 0.08, 21, 10), c, Transform3D(Basis(Vector3.UP, sx * 0.45) * Basis(Vector3.FORWARD, sx * 0.25), Vector3(sx * 0.1, 1.37, 0.07)))
		gear("bone", OrganicMesh.blob(k + "_acromion", Vector3(0.022, 0.012, 0.02), 0.08, 23, 8), R.UARM_L + o, Transform3D(Basis(), sh + Vector3(-sx * 0.01, 0.025, 0.01)))


func _pelvis(k: String) -> void:
	var h := R.HIPS
	var hw := _rest[R.THIGH_R].x
	for sx: float in [-1.0, 1.0]:
		# Iliac wings flaring up and out, the socket ring round the hip joint.
		var wing := BossKit.shell(k + "_ilium", Vector3(0.06, 0.055, 0.045), -65, 65, 20, 90, 0.007, 9, 6)
		gear("bone", wing, h, Transform3D(Basis(Vector3.UP, -sx * PI * 0.42) * Basis(Vector3.RIGHT, 0.25), Vector3(sx * hw * 0.35, 0.96, 0.02)))
		gear("bone", BossKit.torus(k + "_acetab", 0.022, 0.007, 10, 4), h, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(sx * hw * 0.82, 0.925, 0.0)))
		gear("bone", OrganicMesh.bezier(k + "_pubis_%d" % int(sx), Vector3.ZERO, Vector3(-sx * 0.03, -0.03, -0.03), Vector3(-sx * hw * 0.8, -0.04, -0.045), 0.011, 0.01, 6, 6), h, Transform3D(Basis(), Vector3(sx * hw * 0.82, 0.93, -0.005)))
		gear("bone", OrganicMesh.bezier(k + "_ischium_%d" % int(sx), Vector3.ZERO, Vector3(-sx * 0.01, -0.04, 0.02), Vector3(-sx * 0.025, -0.06, 0.0), 0.011, 0.009, 5, 6), h, Transform3D(Basis(), Vector3(sx * hw * 0.82, 0.925, 0.005)))
	gear("bone", OrganicMesh.blob(k + "_sacrum", Vector3(0.035, 0.05, 0.018), 0.06, 27, 10), h, Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, 0.955, 0.05)))


func _arm(k: String, sx: float) -> void:
	var o := 0 if sx < 0.0 else 5
	var sh := _rest[R.UARM_L + o]
	var el := _rest[R.FARM_L + o]
	var wr := _rest[R.HAND_L + o]
	var kn := _rest[R.FING_L + o]
	_long_bone(k + "_hum", sh + Vector3(-sx * 0.004, 0.0, 0), el + Vector3(0, 0.006, 0), 0.0105, R.UARM_L + o, 1.75)
	# Radius and ulna side by side, the olecranon behind the elbow.
	_long_bone(k + "_rad", el + Vector3(sx * 0.008, -0.012, -0.006), wr + Vector3(sx * 0.006, 0.0, -0.006), 0.0075, R.FARM_L + o, 1.5)
	_long_bone(k + "_uln", el + Vector3(-sx * 0.004, -0.006, 0.008), wr + Vector3(-sx * 0.004, 0.0, 0.008), 0.0068, R.FARM_L + o, 1.5)
	gear("bone", OrganicMesh.blob(k + "_olec", Vector3(0.011, 0.016, 0.011), 0.05, 29, 6), R.FARM_L + o, Transform3D(Basis(), el + Vector3(0, 0.0, 0.016)))
	# Hand: carpals, metacarpals to the knuckles, curled phalanges, thumb.
	gear("bone", OrganicMesh.blob(k + "_carpal", Vector3(0.016, 0.012, 0.02), 0.15, 31, 8), R.HAND_L + o, Transform3D(Basis(), wr + Vector3(0, -0.012, 0)))
	for f in 4:
		var z := lerpf(-0.022, 0.02, f / 3.0)
		var base := wr + Vector3(0, -0.02, z * 0.7)
		var knuck := kn + Vector3(0, 0.012, z)
		gear("bone", OrganicMesh.bezier(k + "_metac", Vector3.ZERO, (knuck - base) * 0.5, knuck - base, 0.0042, 0.004, 3, 5), R.HAND_L + o, Transform3D(Basis(), base))
		var fl := 0.026 if f in [1, 2] else 0.022
		gear("bone", OrganicMesh.bezier(k + "_phal_%d" % int(fl * 1000.0), Vector3.ZERO, Vector3(0, -fl * 0.55, -0.004), Vector3(0, -fl, -fl * 0.35), 0.0038, 0.0026, 5, 5), R.FING_L + o, Transform3D(Basis(), knuck))
	gear("bone", OrganicMesh.bezier(k + "_thumb_%d" % int(sx), Vector3.ZERO, Vector3(-sx * 0.004, -0.02, -0.014), Vector3(-sx * 0.004, -0.036, -0.026), 0.0045, 0.003, 5, 5), R.HAND_L + o, Transform3D(Basis(), wr + Vector3(0, -0.012, -0.018)))


func _leg(k: String, sx: float) -> void:
	var o := 0 if sx < 0.0 else 4
	var th := _rest[R.THIGH_L + o]
	var kn := _rest[R.SHIN_L + o]
	var an := _rest[R.FOOT_L + o]
	var to := _rest[R.TOE_L + o]
	# Femur: the neck angles in to the socket, the greater trochanter juts out.
	_long_bone(k + "_fem", th + Vector3(sx * 0.012, -0.03, 0.0), kn + Vector3(0, 0.012, 0), 0.0135, R.THIGH_L + o, 1.75)
	gear("bone", OrganicMesh.bezier(k + "_femneck_%d" % int(sx), Vector3.ZERO, Vector3(-sx * 0.015, 0.012, 0), Vector3(-sx * 0.026, 0.02, 0.0), 0.011, 0.01, 4, 6), R.THIGH_L + o, Transform3D(Basis(), th + Vector3(sx * 0.012, -0.03, 0)))
	gear("bone", ModelKit.sphere(0.017, 8), R.THIGH_L + o, Transform3D(Basis(), th + Vector3(-sx * 0.012, -0.01, 0)))
	gear("bone", OrganicMesh.blob(k + "_troch", Vector3(0.014, 0.022, 0.014), 0.1, 33, 6), R.THIGH_L + o, Transform3D(Basis(), th + Vector3(sx * 0.028, -0.035, 0.004)))
	gear("bone", OrganicMesh.blob(k + "_patella", Vector3(0.016, 0.02, 0.009), 0.05, 35, 8), R.SHIN_L + o, Transform3D(Basis(), kn + Vector3(0, 0.015, -0.03)))
	# Tibia and the thin fibula beside it.
	_long_bone(k + "_tib", kn + Vector3(0, -0.006, -0.004), an + Vector3(0, 0.02, 0), 0.0115, R.SHIN_L + o, 1.7)
	_long_bone(k + "_fib", kn + Vector3(sx * 0.02, -0.025, 0.01), an + Vector3(sx * 0.022, 0.012, 0.006), 0.0055, R.SHIN_L + o, 1.5)
	# Foot: heel and ankle bones, metatarsals, toes.
	gear("bone", OrganicMesh.blob(k + "_talus", Vector3(0.02, 0.018, 0.04), 0.12, 37, 8), R.FOOT_L + o, Transform3D(Basis(), an + Vector3(0, -0.032, 0.02)))
	for t in 5:
		var x := lerpf(-0.026, 0.026, t / 4.0) * sx
		var base := an + Vector3(x * 0.6, -0.04, -0.015)
		var tip := to + Vector3(x, 0.0, 0.0)
		gear("bone", OrganicMesh.bezier(k + "_metat", Vector3.ZERO, (tip - base) * 0.5 + Vector3(0, 0.006, 0), tip - base, 0.0055 if t != (0 if sx > 0.0 else 4) else 0.007, 0.0045, 3, 5), R.FOOT_L + o, Transform3D(Basis(), base))
		gear("bone", OrganicMesh.bezier(k + "_toe", Vector3.ZERO, Vector3(0, -0.004, -0.012), Vector3(0, -0.01, -0.022), 0.0045, 0.003, 3, 5), R.TOE_L + o, Transform3D(Basis(), tip))


# --- Gear ----------------------------------------------------------------------------------

func _helmet(k: String, great: bool) -> void:
	var h := R.HEAD
	if great:
		# A dented great helm with a breathing-holed visor and curled horns.
		var helm := PackedVector2Array([Vector2(0.1, 1.6), Vector2(0.104, 1.66), Vector2(0.107, 1.72), Vector2(0.104, 1.77), Vector2(0.09, 1.81), Vector2(0.055, 1.835), Vector2(0.0, 1.842)])
		gear("metal", BossKit.lathe(k + "_ghelm", helm, 20, 0.95, 1.08, false, true), h, Transform3D.IDENTITY, Color(0.85, 0.8, 0.75))
		gear("dark", OrganicMesh.blob(k + "_gslit", Vector3(0.075, 0.012, 0.03), 0.0, 2, 10), h, Transform3D(Basis(), Vector3(0, 1.704, -0.098)))
		for sx: float in [-1.0, 1.0]:
			gear("eyes", ModelKit.sphere(0.008, 6), h, Transform3D(Basis().scaled(Vector3(1.6, 0.6, 0.6)), Vector3(sx * 0.03, 1.704, -0.105)))
			gear("bone", OrganicMesh.bezier(k + "_ghorn_%d" % int(sx), Vector3.ZERO, Vector3(sx * 0.08, 0.02, 0.02), Vector3(sx * 0.1, 0.12, -0.04), 0.02, 0.003, 10, 7), h, Transform3D(Basis(), Vector3(sx * 0.095, 1.77, 0.0)), Color(0.7, 0.62, 0.5))
		var ridge := BossKit.wrap_rows([[1.8, 0.012, 0.11, 0.0], [1.7, 0.012, 0.115, 0.0], [1.62, 0.012, 0.11, 0.0]], -0.15, 0.15, 3)
		gear("metal", BossKit.plate(k + "_gridge", ridge, 0.012, Vector3(0, 1.7, 0.0)), h, Transform3D.IDENTITY, Color(0.6, 0.55, 0.5))
		return
	# A rusted kettle helm with a broad brim and a nasal bar.
	var cap := PackedVector2Array([Vector2(0.088, 1.735), Vector2(0.09, 1.77), Vector2(0.08, 1.81), Vector2(0.055, 1.835), Vector2(0.0, 1.842)])
	gear("metal", BossKit.lathe(k + "_kettle", cap, 18, 0.95, 1.08, false, true), h, Transform3D.IDENTITY, Color(0.85, 0.8, 0.75))
	var brim := PackedVector2Array([Vector2(0.085, 1.742), Vector2(0.13, 1.728), Vector2(0.142, 1.718), Vector2(0.14, 1.712)])
	gear("metal", BossKit.lathe(k + "_brim", brim, 22, 0.95, 1.08), h, Transform3D.IDENTITY, Color(0.7, 0.66, 0.6))
	gear("metal", BossKit.torus(k + "_hband", 0.091, 0.006, 18, 4), h, Transform3D(Basis().scaled(Vector3(0.95, 1.0, 1.08)), Vector3(0, 1.76, 0)), Color(0.6, 0.55, 0.5))
	gear("leather", OrganicMesh.bezier(k + "_chin_l", Vector3.ZERO, Vector3(0.0, -0.06, -0.02), Vector3(0.03, -0.11, -0.04), 0.006, 0.006, 6, 4), h, Transform3D(Basis(), Vector3(-0.075, 1.735, 0.0)))


## Hanging cloth strips round an ellipse (rags, mantle fringes).
func _strips(k: String, b: int, n: int, y: float, rx: float, rz: float, l0: float, l1: float, w0: float, w1: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in n:
		var a := lerpf(-PI, PI, (float(i) + 0.5) / n) + rng.randf_range(-0.1, 0.1)
		var top := Vector3(sin(a) * rx, y, -cos(a) * rz)
		var out := Vector3(sin(a), 0, -cos(a))
		var l := rng.randf_range(l0, l1)
		var path := PackedVector3Array()
		var widths := PackedFloat32Array()
		for j in 6:
			var t := float(j) / 5.0
			path.append(top + Vector3(0, -l * t, 0) + out * (0.015 * t))
			widths.append(lerpf(w0, w1, t))
		gear("cloth", BossKit.ribbon("%s_strip_%d_%d" % [k, seed_value, i], path, widths, Vector3(cos(a), 0, sin(a)), 0.005), b)


## A rope belt with tattered strips of cloth hanging from it.
func _rags(k: String) -> void:
	gear("leather", BossKit.torus(k + "_rope", 0.135, 0.011, 24, 5, 1.0), R.HIPS, Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.82)), Vector3(0, 0.985, 0.0)), Color(0.75, 0.65, 0.5))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(k)
	for i in 11:
		# Mostly front and back, a few over the hips.
		var a := lerpf(-PI, PI, (float(i) + 0.5) / 11.0) + rng.randf_range(-0.12, 0.12)
		if absf(absf(a) - PI * 0.5) < 0.35:
			continue
		var top := Vector3(sin(a) * 0.138, 0.975, -cos(a) * 0.115)
		var out := Vector3(sin(a), 0, -cos(a))
		var l := rng.randf_range(0.2, 0.42)
		var path := PackedVector3Array()
		var widths := PackedFloat32Array()
		for j in 6:
			var t := float(j) / 5.0
			path.append(top + Vector3(0, -l * t, 0) + out * (0.02 * t + 0.01 * sin(t * 3.0 + i)))
			widths.append(lerpf(0.042, 0.018, t) * (1.0 + 0.3 * sin(i * 1.7 + t * 5.0)))
		var across := Vector3(cos(a), 0, sin(a))
		gear("cloth", BossKit.ribbon("%s_rag_%d" % [k, i], path, widths, across, 0.006), R.HIPS)


func _breastplate(k: String) -> void:
	var c := R.CHEST
	var breast := BossKit.wrap_rows([[1.45, 0.13, 0.09, 0.0], [1.4, 0.16, 0.12, 0.012], [1.32, 0.17, 0.135, 0.025], [1.24, 0.16, 0.13, 0.03], [1.17, 0.145, 0.12, 0.02]], -1.65, 1.65, 17, Vector3(0, 0, 0.0))
	gear("metal", BossKit.plate(k + "_breast", breast, 0.012, Vector3(0, 1.3, 0.03)), c, Transform3D.IDENTITY, Color(0.8, 0.76, 0.7))
	# Broken straps over the shoulders.
	for sx: float in [-1.0, 1.0]:
		gear("leather", OrganicMesh.bezier(k + "_bstrap_%d" % int(sx), Vector3.ZERO, Vector3(0, 0.05, 0.06), Vector3(0, 0.0, 0.14), 0.012, 0.012, 6, 4), c, Transform3D(Basis(), Vector3(sx * 0.09, 1.44, -0.07)))
	# Faulds over the hips (a dented skirt of lames).
	for i in 2:
		var y0 := 1.0 - i * 0.045
		var prof := PackedVector2Array([Vector2(0.15 + i * 0.012, y0), Vector2(0.165 + i * 0.014, y0 - 0.045), Vector2(0.17 + i * 0.014, y0 - 0.06)])
		gear("metal", BossKit.lathe("%s_fauld_%d" % [k, i], prof, 20, 1.0, 0.82), R.HIPS, Transform3D(Basis(), Vector3(0, 0, -0.005)), Color(0.75, 0.7, 0.65) if i == 0 else Color(0.6, 0.56, 0.52))


func _shield(k: String) -> void:
	# A round shield of rotten planks with an iron rim and boss, strapped to the left forearm.
	var b := R.FARM_L
	var el := _rest[R.FARM_L]
	var wr := _rest[R.HAND_L]
	var c := el.lerp(wr, 0.55) + Vector3(-0.06, 0.0, -0.01)
	var bas := Basis(Vector3.FORWARD, PI * 0.5)
	var disc := PackedVector2Array([Vector2(0.0, 0.012), Vector2(0.22, 0.012), Vector2(0.23, 0.0), Vector2(0.22, -0.012), Vector2(0.0, -0.016)])
	gear("wood", BossKit.lathe(k + "_shield", disc, 24), b, Transform3D(bas, c), Color(0.42, 0.3, 0.2))
	gear("metal", BossKit.torus(k + "_srim", 0.228, 0.012, 28, 5), b, Transform3D(bas, c), Color(0.7, 0.65, 0.6))
	var boss := PackedVector2Array([Vector2(0.06, 0.0), Vector2(0.058, 0.02), Vector2(0.04, 0.045), Vector2(0.0, 0.055)])
	gear("metal", BossKit.lathe(k + "_sboss", boss, 14, 1.0, 1.0, false, true), b, Transform3D(bas, c + Vector3(-0.012, 0, 0)), Color(0.8, 0.75, 0.7))
	for i in 3:
		gear("metal", OrganicMesh.bezier(k + "_splank", Vector3.ZERO, Vector3(0, 0.2, 0), Vector3(0, 0.4, 0), 0.004, 0.004, 2, 4), b, Transform3D(Basis(), c + Vector3(-0.014, -0.2, (float(i) - 1.0) * 0.1)), Color(0.4, 0.38, 0.35))


func _hood(k: String) -> void:
	# A deep tattered hood round the skull, its mantle over the shoulders.
	var hood := BossKit.shell(k + "_hood", Vector3(0.118, 0.145, 0.13), -128, 128, 0, 132, 0.012, 18, 10)
	gear("cloth", hood, R.HEAD, Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(0, 1.7, 0.03)))
	# The peak of the hood falls down the back.
	gear("cloth", OrganicMesh.bezier(k + "_hoodtail", Vector3.ZERO, Vector3(0, -0.02, 0.06), Vector3(0, -0.12, 0.08), 0.05, 0.01, 6, 8, 0.4), R.HEAD, Transform3D(Basis(), Vector3(0, 1.8, 0.08)))
	# A ragged fringe of a mantle hanging from the shoulders.
	_strips(k, R.CHEST, 13, 1.34, 0.235, 0.15, 0.1, 0.24, 0.045, 0.02, 31)


func _quiver(k: String) -> void:
	# Slung across the back: leather quiver, fletched arrows.
	var c := R.CHEST
	var base := Vector3(0.07, 1.12, 0.12)
	var top := Vector3(-0.08, 1.52, 0.14)
	var q := PackedVector2Array([Vector2(0.04, 0.0), Vector2(0.048, 0.02), Vector2(0.05, 0.3), Vector2(0.054, 0.36), Vector2(0.05, 0.37)])
	var xf := span(base, top)
	gear("leather", BossKit.lathe(k + "_quiver", q, 12, 1.0, 1.0, true, false), c, xf, Color(0.65, 0.5, 0.36))
	gear("leather", BossKit.torus(k + "_qband", 0.052, 0.006, 12, 4), c, xf * Transform3D(Basis(), Vector3(0, 0.08, 0)), Color(0.4, 0.3, 0.2))
	gear("leather", BossKit.torus(k + "_qband", 0.052, 0.006, 12, 4), c, xf * Transform3D(Basis(), Vector3(0, 0.28, 0)), Color(0.4, 0.3, 0.2))
	for i in 6:
		var off := Vector3((float(i % 3) - 1.0) * 0.018, 0.0, (float(i / 3) - 0.5) * 0.02)
		var shaft := xf * Transform3D(Basis(Vector3.FORWARD, off.x * 1.5), Vector3(off.x, 0.2, off.z))
		gear("wood_light", BossKit.lathe(k + "_arrow", PackedVector2Array([Vector2(0.0035, 0.0), Vector2(0.0035, 0.27), Vector2(0.004, 0.28)]), 5), c, shaft, Color(0.8, 0.7, 0.55))
		for f in 3:
			var fb := Basis(Vector3.UP, TAU * f / 3.0)
			gear("cloth", OrganicMesh.membrane(k + "_fletch", PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.016, 0.01), Vector2(0.012, 0.055), Vector2(0.0, 0.06)]), 0.0, 0.002), c, shaft * Transform3D(fb, Vector3(0, 0.215, 0)), Color(0.9, 0.88, 0.82))


## Weapons: a modelled recurve bow for the archer, a notched, rust-eaten
## arming sword for the others; anything else as HeldItems builds it.
func _build_held(item_id: String) -> void:
	if item_id == "sword_rusty":
		_rusty_sword()
		return
	if item_id != "bow":
		super._build_held(item_id)
		return
	_held_id = item_id
	if _held != null:
		_held.queue_free()
		_held = null
	_held = Node3D.new()
	_held.name = "Bow"
	grip_l.add_child(_held)
	var k := _kit_key()
	var wood := BossKit.wood(Color(0.22, 0.15, 0.09))
	var leather := BossKit.leather({"albedo": Color(0.4, 0.3, 0.22)})
	var asm := BossKit.assembly()
	# Limbs bow away from the archer, the tips recurve towards them.
	for side: float in [-1.0, 1.0]:
		var limb := OrganicMesh.bezier("%s_bowlimb_%d" % [k, int(side)], Vector3.ZERO, Vector3(0, side * 0.2, -0.13), Vector3(0, side * 0.4, -0.1), 0.024, 0.012, 10, 6, 0.6)
		asm.add(limb, wood, Transform3D(Basis(), Vector3(0, 0.1 + side * 0.07, 0.0)), Color(0.45, 0.32, 0.2))
		asm.add(OrganicMesh.bezier("%s_bowtip_%d" % [k, int(side)], Vector3.ZERO, Vector3(0, side * 0.025, 0.03), Vector3(0, side * 0.035, 0.06), 0.011, 0.005, 4, 5), wood, Transform3D(Basis(), Vector3(0, 0.1 + side * 0.47, -0.1)), Color(0.25, 0.18, 0.12))
	asm.add(BossKit.lathe(k + "_bowgrip", PackedVector2Array([Vector2(0.019, -0.07), Vector2(0.021, 0.0), Vector2(0.019, 0.07)]), 8), leather, Transform3D(Basis(), Vector3(0, 0.1, 0)), Color(0.7, 0.55, 0.4))
	asm.add(BossKit.lathe(k + "_string", PackedVector2Array([Vector2(0.002, 0.0), Vector2(0.002, 1.01)]), 4), leather, Transform3D(Basis(), Vector3(0, -0.405, -0.04)), Color(0.85, 0.82, 0.75))
	bake_into(_held, "bow", asm)
	_held_len = 0.8

