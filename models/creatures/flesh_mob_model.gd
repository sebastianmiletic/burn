class_name FleshMobModel
extends MobHumanoid
## The fleshed humanoid monsters, each one smooth skinned body sculpted on the
## humanoid rig (MobHumanoid) plus merged gear:
##   troll    a hunched three-metre brute: slab traps and a pot belly, long
##            arms ending in huge nailed hands, thick legs and broad feet, a
##            small head with a heavy brow, a hooked bulb of a nose, big ears and
##            a tusked underbite; warty mottled hide, a hide loincloth, wrapped
##            forearms. Tribes: moss-grown with mushrooms and a tree-branch
##            club; grey with bone spikes, a spiked hide pauldron and a stone
##            maul; brown with great tusks, a necklace of teeth and skulls and an
##            iron-studded club.
##   ghoul    an emaciated corpse: ribs, spine, collarbones and hip bones
##            pressing through grey-green skin, knobbed joints, long clawed
##            fingers, a skull-tight face with sunken glowing eyes, bared teeth,
##            bat ears, tattered rags.
##   drowned  a bloated, waterlogged thrall: wrinkled wet pallor, a slack
##            jaw, glowing teal eyes, lank hair, kelp hanging from shoulders,
##            arms and belt, barnacle crusts, a rusted manacle and chain, rags.

const SKIN := 0
const NAIL := 1
const MOUTH := 2

var kind := "troll"
var tribe := 0
var skin_color := Color(0.4, 0.42, 0.32)
var cloth_color := Color(0.3, 0.22, 0.15)
var eye_color := Color(1.0, 0.75, 0.2)
var hair_color := Color(0.12, 0.12, 0.1)
var wild_hair := false
var _mob_fx: Array[GPUParticles3D] = []


func _init(kind_name := "troll", style_dict := {}, opts := {}) -> void:
	kind = kind_name
	tribe = int(opts.get("tribe", 0))
	wild_hair = bool(opts.get("wild_hair", false))
	skin_color = style_dict.get("skin", skin_color)
	cloth_color = style_dict.get("cloth", cloth_color)
	eye_color = style_dict.get("eyes", eye_color)
	hair_color = opts.get("hair", hair_color)
	var b := float(style_dict.get("bulk", 1.0))
	var arm := float(style_dict.get("arm_length", 1.0))
	var key := "flesh_%s_%d_%s_%.2f_%.2f_%s" % [kind, tribe, "h" if wild_hair else "", b, arm, "cloak" if style_dict.get("cloak", false) else ""]
	super(style_dict, key)
	if kind == "troll":
		dissolve_delay = 1.8
		durations["slam"] = 1.3


func _flesh_materials() -> Array:
	var belly := skin_color.lightened(0.12)
	var skin: ShaderMaterial
	match kind:
		"troll":
			skin = CreatureSkin.hide(skin_color, belly, {"use_rest": true, "pattern_scale": 4.5, "bump": 0.85, "bump_distance": 30.0,
				"roughness": 0.72, "rim": 0.22, "accent": skin_color.darkened(0.35), "accent_mode": 2, "accent_amount": 0.5, "accent_scale": 2.6,
				"specular_amount": 0.25})
		"ghoul":
			var grey := skin_color.lerp(Color(0.5, 0.5, 0.47), 0.3)
			skin = CreatureSkin.hide(grey.darkened(0.12), grey, {"use_rest": true, "pattern_scale": 6.0, "bump": 0.6, "bump_distance": 20.0,
				"roughness": 0.58, "rim": 0.3, "accent": skin_color.darkened(0.45), "accent_mode": 2, "accent_amount": 0.4, "accent_scale": 3.0,
				"specular_amount": 0.35})
		_:
			var pale := skin_color.lerp(Color(0.5, 0.54, 0.5), 0.25).darkened(0.2)
			skin = CreatureSkin.hide(pale, pale.lightened(0.08), {"use_rest": true, "pattern_scale": 5.5, "bump": 0.8, "bump_distance": 20.0,
				"roughness": 0.5, "wet": 0.35, "rim": 0.15, "accent": Color(0.2, 0.26, 0.24), "accent_mode": 2, "accent_amount": 0.5, "accent_scale": 3.0,
				"specular_amount": 0.35})
	var nail_col := Color(0.2, 0.17, 0.12)
	if kind == "troll":
		nail_col = Color(0.3, 0.26, 0.18)
	elif kind == "drowned":
		nail_col = Color(0.62, 0.6, 0.55)
	var nail := CreatureSkin.keratin(nail_col, {"use_rest": true, "pattern_scale": 40.0, "bump": 0.8})
	var mouth := CreatureSkin.mouth(Color(0.22, 0.06, 0.05) if kind != "drowned" else Color(0.12, 0.1, 0.1))
	return [skin, nail, mouth]


func _gear_materials() -> Dictionary:
	return {
		"eyes": BossKit.glow(eye_color, {"ghoul": 6.0, "troll": 5.0}.get(kind, 4.0), 0.15),
		"dark": ModelKit.mat(Color(0.015, 0.012, 0.01), AsciiMaterialId.SOLID, 0.95, 0.0, 0.0),
		"teeth": BossKit.bone({"skinned": true, "albedo": Color(0.86, 0.8, 0.62) if kind != "ghoul" else Color(0.7, 0.62, 0.42), "grime": 0.5}),
		"bone": BossKit.bone({"skinned": true, "albedo": Color(0.84, 0.8, 0.68), "grime": 0.5}),
		"leather": BossKit.leather({"skinned": true, "albedo": Color(0.42, 0.3, 0.2)}),
		"hide": BossKit.fur(Color(0.22, 0.16, 0.11), {"skinned": true, "albedo": Color(0.5, 0.38, 0.27)}),
		"cloth": BossKit.cloth(cloth_color, cloth_color.darkened(0.4), {"skinned": true, "tatter": 0.7, "grime": 0.75}),
		"rope": BossKit.wood(Color(0.35, 0.28, 0.18), {"skinned": true, "albedo": Color(0.65, 0.55, 0.38), "pattern_scale": 40.0}),
		"moss": BossKit.fur(Color(0.12, 0.2, 0.06), {"skinned": true, "albedo": Color(0.3, 0.42, 0.16), "pattern_scale": 30.0}),
		"cap": BossKit.skin(Color(0.45, 0.16, 0.06), {"skinned": true, "albedo": Color(0.75, 0.32, 0.14)}),
		"hair": BossKit.fur(hair_color.darkened(0.3), {"skinned": true, "albedo": hair_color, "pattern_scale": 30.0}),
		"kelp": BossKit.cloth(Color(0.16, 0.26, 0.1), Color(0.1, 0.16, 0.06), {"skinned": true, "tatter": 0.4, "grime": 0.3, "roughness": 0.3}),
		"shell": BossKit.bone({"skinned": true, "albedo": Color(0.7, 0.7, 0.66), "grime": 0.8, "pattern_scale": 30.0}),
		"metal": BossKit.metal({"skinned": true, "albedo": Color(0.45, 0.42, 0.4), "rust": 0.6, "wear": 0.5, "grime": 0.6}),
	}


func _after_mob() -> void:
	var k := _kit_key()
	if style.get("cloak", false) and _cloak_first >= 0:
		var c := cloth_color.darkened(0.2)
		skinned(BossKit.cloak(k + "_cloak", body, style, 13, 13, 0.01, 1.1, 0.0), BossKit.cloth(c, c.darkened(0.4), {"skinned": true, "tatter": 0.85, "grime": 0.85, "roughness": 0.4}))
	if kind == "drowned":
		# Water dripping off the body.
		var fx := fx_point(R.CHEST, Vector3(0, 1.2, 0))
		_mob_fx.append(BossKit.emitter(fx, "wisp", 6, Vector3(0.18, 0.3, 0.12), Color(0.5, 0.75, 0.8), 0.025, 0.8, -1.5))


func set_dead(is_dead: bool) -> void:
	super.set_dead(is_dead)
	for f in _mob_fx:
		if is_instance_valid(f):
			f.emitting = not is_dead


# --- Sculpt ----------------------------------------------------------------------------------

func _sculpt() -> void:
	var k := _kit_key()
	match kind:
		"troll":
			_troll(k)
		"ghoul":
			_ghoul(k)
		_:
			_drowned(k)


## Torso tube from rows [y, z, half width, half depth, bone].
func _torso(rows: Array, blend := 0.08) -> void:
	var path := PackedVector3Array()
	var radii := PackedVector2Array()
	var bones: Array = []
	for r: Array in rows:
		path.append(Vector3(0, float(r[0]), float(r[1])))
		radii.append(Vector2(float(r[2]), float(r[3])))
		bones.append(r[4])
	var rs := MobRig.resample(path, radii, bones, rows.size() * 3)
	flesh_slot(SKIN).tube(rs[0], rs[1], rs[2], blend, 18, Vector3.BACK)


func _arm_joints(side: float, clav_in: float) -> PackedVector3Array:
	var o := 0 if side < 0.0 else 5
	var sh := _rest[R.UARM_L + o]
	return PackedVector3Array([Vector3(side * clav_in, sh.y + 0.01, 0.02), sh, _rest[R.FARM_L + o], _rest[R.HAND_L + o], _rest[R.FING_L + o]])


func _leg_joints(side: float) -> PackedVector3Array:
	var o := 0 if side < 0.0 else 4
	var th := _rest[R.THIGH_L + o]
	return PackedVector3Array([Vector3(side * th.x * 0.4, 1.0, 0.0), th, _rest[R.SHIN_L + o], _rest[R.FOOT_L + o]])


func _arm_bones(side: float) -> Array:
	var o := 0 if side < 0.0 else 5
	return [R.CHEST, R.UARM_L + o, R.FARM_L + o, R.HAND_L + o]


func _leg_bones(side: float) -> Array:
	var o := 0 if side < 0.0 else 4
	return [R.HIPS, R.THIGH_L + o, R.SHIN_L + o]


## Fingers on the finger bone and a thumb on the hand: `fl` length, `fr` radius,
## `claw` nail length (0 = flat nails). Palms face inward in the rest pose.
func _sculpt_hand(k: String, side: float, fl: float, fr: float, claw: float) -> void:
	var o := 0 if side < 0.0 else 5
	var wr := _rest[R.HAND_L + o]
	var kn := _rest[R.FING_L + o]
	for f in 4:
		var z := lerpf(-fr * 2.2, fr * 2.2, f / 3.0)
		var l := fl * (1.0 if f in [1, 2] else 0.86)
		var base := kn + Vector3(0, fr * 1.2, z)
		var tip := Vector3(-side * l * 0.18, -l, -l * 0.08)
		flesh_slot(SKIN).rigid(OrganicMesh.bezier("%s_fing_%d" % [k, int(l * 1000.0)], Vector3.ZERO, tip * 0.5 + Vector3(-side * l * 0.04, 0, 0), tip, fr, fr * 0.78, 6, 8), Transform3D(Basis(), base), R.FING_L + o)
		var nail := OrganicMesh.bezier("%s_nail_%d_%d" % [k, int(claw * 1000.0), int(side)], Vector3.ZERO, Vector3(-side * claw * 0.2, -claw * 0.6, -claw * 0.1), Vector3(-side * claw * 0.55, -claw, -claw * 0.05), fr * 0.6, fr * 0.08, 5, 5) if claw > 0.0 \
			else OrganicMesh.blob(k + "_flatnail", Vector3(fr * 0.6, fr * 0.8, fr * 0.35), 0.05, 3, 6)
		flesh_slot(NAIL).rigid(nail, Transform3D(Basis(), base + tip * 0.97 + Vector3(side * fr * 0.15, 0, 0)), R.FING_L + o)
		# Knuckle.
		flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_knuckle", Vector3(fr, fr * 0.9, fr), 0.05, 5, 6), Transform3D(Basis(), base + Vector3(side * fr * 0.3, 0, 0)), R.FING_L + o)
	var th0 := wr + Vector3(-side * fr * 0.4, -fl * 0.35, -fr * 2.6)
	var th_tip := Vector3(-side * fl * 0.2, -fl * 0.55, -fl * 0.35)
	flesh_slot(SKIN).rigid(OrganicMesh.bezier("%s_thumb_%d" % [k, int(side)], Vector3.ZERO, th_tip * 0.5, th_tip, fr * 1.15, fr * 0.85, 6, 8), Transform3D(Basis(), th0), R.HAND_L + o)
	flesh_slot(NAIL).rigid(OrganicMesh.blob(k + "_tnail", Vector3(fr * 0.6, fr * 0.8, fr * 0.35), 0.05, 3, 6), Transform3D(Basis(), th0 + th_tip), R.HAND_L + o)


## A foot from the ankle forward with toes and nails; `w` half width, `l` length.
func _sculpt_foot(k: String, side: float, w: float, l: float, h: float, claw: float) -> void:
	var o := 0 if side < 0.0 else 4
	var an := _rest[R.FOOT_L + o]
	var to := _rest[R.TOE_L + o]
	flesh_slot(SKIN).rigid(OrganicMesh.profile(k + "_foot", Vector3(0, 0, l * 0.28), Vector3(0, -h * 0.25, -l * 0.62), [[0.0, w * 0.7, h * 0.8], [0.25, w * 0.85, h * 0.95, h * 0.1], [0.7, w, h * 0.6], [1.0, w * 0.9, h * 0.45]], 12, 10),
		Transform3D(Basis(), Vector3(an.x, an.y - h * 0.15, an.z)), R.FOOT_L + o)
	for t in 4:
		var x := lerpf(-w * 0.75, w * 0.75, t / 3.0) * side
		var tl := l * (0.2 if t > 0 else 0.26) * (1.0 - t * 0.08)
		var base := Vector3(to.x + x, h * 0.35, to.z + l * 0.1)
		flesh_slot(SKIN).rigid(OrganicMesh.bezier("%s_toe_%d" % [k, int(tl * 1000.0)], Vector3.ZERO, Vector3(0, h * 0.05, -tl * 0.5), Vector3(0, -h * 0.15, -tl), w * 0.26, w * 0.2, 4, 7), Transform3D(Basis(), base), R.TOE_L + o)
		var nail := OrganicMesh.bezier("%s_tclaw_%d" % [k, int(claw * 1000.0)], Vector3.ZERO, Vector3(0, -claw * 0.2, -claw * 0.6), Vector3(0, -claw * 0.7, -claw), w * 0.14, w * 0.02, 4, 5) if claw > 0.0 \
			else OrganicMesh.blob(k + "_tnail2", Vector3(w * 0.15, w * 0.08, w * 0.12), 0.05, 3, 6)
		flesh_slot(NAIL).rigid(nail, Transform3D(Basis(), base + Vector3(0, -h * 0.1, -tl * 0.95)), R.TOE_L + o)


## Pointed ear (a thick tapering leaf) on the head.
func _ear(k: String, side: float, at: Vector3, l: float, w: float, rot: Vector3) -> void:
	var prof := [[0.0, w, w * 0.3], [0.35, w * 0.95, w * 0.22, w * 0.1], [0.75, w * 0.5, w * 0.15, w * 0.08], [1.0, 0.0, 0.0]]
	var m := OrganicMesh.profile("%s_ear_%d_%d" % [k, int(l * 1000.0), int(w * 1000.0)], Vector3.ZERO, Vector3(0, l, 0), prof, 8, 6, Vector3.BACK)
	flesh_slot(SKIN).rigid(m, Transform3D(Basis.from_euler(rot), at), R.HEAD)


## Hanging strips (loincloth, rags, kelp): `n` strips round an ellipse at
## height y (radii rx, rz) between angles; each `l0..l1` long.
func _strips(k: String, role: String, b: int, n: int, y: float, rx: float, rz: float, a0: float, a1: float, l0: float, l1: float, w0: float, w1: float, seed_value: int, skip_sides := true) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in n:
		var a := lerpf(a0, a1, (float(i) + 0.5) / n) + rng.randf_range(-0.1, 0.1)
		if skip_sides and absf(absf(a) - PI * 0.5) < 0.3:
			continue
		var top := Vector3(sin(a) * rx, y, -cos(a) * rz)
		var out := Vector3(sin(a), 0, -cos(a))
		var l := rng.randf_range(l0, l1)
		var path := PackedVector3Array()
		var widths := PackedFloat32Array()
		for j in 7:
			var t := float(j) / 6.0
			path.append(top + Vector3(0, -l * t, 0) + out * (0.02 * t + 0.008 * sin(t * 4.0 + i)))
			widths.append(lerpf(w0, w1, t) * (1.0 + 0.25 * sin(i * 2.3 + t * 6.0)))
		gear(role, BossKit.ribbon("%s_%s_%d_%d" % [k, role, seed_value, i], path, widths, Vector3(cos(a), 0, sin(a)), 0.006), b)


# --- Troll -----------------------------------------------------------------------------------

func _troll(k: String) -> void:
	var sw := _rest[R.UARM_R].x
	var hw := _rest[R.THIGH_R].x
	var H := R.HIPS
	var S := R.SPINE
	var C := R.CHEST
	_torso([[0.82, 0.0, hw * 0.95, 0.12, H], [0.9, 0.0, hw * 1.55, 0.17, H], [0.99, -0.01, hw * 1.72, 0.2, H], [1.07, -0.04, sw * 0.9, 0.23, S],
		[1.15, -0.05, sw * 0.93, 0.24, S], [1.24, -0.03, sw * 0.96, 0.22, C], [1.32, 0.0, sw * 1.02, 0.2, C], [1.4, 0.03, sw * 1.02, 0.18, C],
		[1.47, 0.05, sw * 0.7, 0.16, C], [1.53, 0.03, 0.13, 0.12, R.NECK], [1.59, -0.01, 0.09, 0.09, R.NECK], [1.635, -0.03, 0.075, 0.075, R.HEAD]], 0.1)
	# Warts and lumps over the back and shoulders.
	flesh_slot(SKIN).tufts(OrganicMesh.blob(k + "_wart", Vector3(0.5, 0.35, 0.5), 0.2, 3, 6), 70, 0.15, 0.95, -170.0, 170.0, 0.045, 0.95, 5)
	for sx: float in [-1.0, 1.0]:
		# Slab trapezius, pectorals, lats.
		flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_trap", Vector3(0.15, 0.075, 0.11), 0.12, 7, 12), Transform3D(Basis(Vector3.FORWARD, sx * 0.4), Vector3(sx * sw * 0.45, 1.47, 0.06)), C, R.NECK, 0.25)
		flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_pec", Vector3(0.15, 0.06, 0.03), 0.08, 9, 12), Transform3D(Basis(Vector3.UP, sx * 0.3) * Basis(Vector3.FORWARD, sx * 0.15), Vector3(sx * sw * 0.4, 1.37, -0.13)), C)
		flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_lat", Vector3(0.1, 0.16, 0.09), 0.1, 11, 10), Transform3D(Basis(), Vector3(sx * sw * 0.72, 1.3, 0.08)), C)
		flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_glute", Vector3(0.13, 0.12, 0.1), 0.1, 13, 10), Transform3D(Basis(), Vector3(sx * hw * 0.85, 0.94, 0.1)), H)
	flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_belly", Vector3(0.22, 0.17, 0.1), 0.08, 15, 14), Transform3D(Basis(), Vector3(0, 1.11, -0.17)), S)
	# Limbs.
	var arm_prof := [[0.0, 0.1, 0.1], [0.16, 0.135, 0.13], [0.3, 0.11, 0.115], [0.42, 0.1, 0.108, -0.012], [0.54, 0.08, 0.085, 0.01],
		[0.63, 0.096, 0.096, -0.006], [0.8, 0.074, 0.068], [0.88, 0.066, 0.052], [1.0, 0.07, 0.036]]
	var leg_prof := [[0.0, 0.14, 0.15], [0.14, 0.165, 0.17], [0.3, 0.145, 0.15, -0.012], [0.5, 0.09, 0.1], [0.57, 0.082, 0.09],
		[0.67, 0.098, 0.11, 0.028], [0.84, 0.068, 0.07], [0.95, 0.06, 0.062], [1.0, 0.065, 0.065]]
	for sx: float in [-1.0, 1.0]:
		flesh_limb(SKIN, _arm_joints(sx, sw * 0.45), _arm_bones(sx), arm_prof, R.CHEST, 22, 14)
		flesh_limb(SKIN, _leg_joints(sx), _leg_bones(sx), leg_prof, R.HIPS, 20, 14)
		_sculpt_hand(k, sx, 0.12, 0.024, 0.0)
		_sculpt_foot(k, sx, 0.085, 0.3, 0.075, 0.0)
		var o := 0 if sx < 0.0 else 5
		# Elbow and knee knobs.
		flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_elbow", Vector3(0.055, 0.06, 0.05), 0.15, 17, 8), Transform3D(Basis(), _rest[R.FARM_L + o] + Vector3(0, 0.0, 0.05)), R.FARM_L + o)
		var lo := 0 if sx < 0.0 else 4
		flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_knee", Vector3(0.07, 0.07, 0.05), 0.15, 19, 8), Transform3D(Basis(), _rest[R.SHIN_L + lo] + Vector3(0, 0.02, -0.07)), R.SHIN_L + lo)
	_troll_head(k)
	_troll_gear(k)


func _troll_head(k: String) -> void:
	var h := R.HEAD
	var j := R.JAW
	# Everything is sculpted at human scale then enlarged round the neck top
	# and pushed forward: a big, low-slung head on the thick neck.
	var hs := 1.3
	var piv := Vector3(0, 1.6, 0.0)
	var T := Transform3D(Basis().scaled(Vector3.ONE * hs), piv - piv * hs + Vector3(0, -0.01, -0.035))
	flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_cranium", Vector3(0.082, 0.072, 0.092), 0.1, 21, 16), T * Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, 1.69, -0.01)), h)
	var brow := PackedVector3Array()
	var brow_r := PackedVector2Array()
	for i in 9:
		var a := lerpf(-1.2, 1.2, i / 8.0)
		brow.append(T * Vector3(sin(a) * 0.068, 1.705 + cos(a * 1.5) * 0.005, -0.078 - cos(a) * 0.026))
		brow_r.append(Vector2(0.021, 0.016) * hs * (1.0 - absf(a) * 0.25))
	flesh_slot(SKIN).tube(brow, brow_r, [h, h, h, h, h, h, h, h, h], 0.05, 10, Vector3.UP)
	for sx: float in [-1.0, 1.0]:
		flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_cheek", Vector3(0.03, 0.026, 0.03), 0.1, 23, 8), T * Transform3D(Basis(), Vector3(sx * 0.052, 1.664, -0.078)), h)
		gear("dark", OrganicMesh.blob(k + "_socket", Vector3(0.017, 0.012, 0.01), 0.05, 25, 8), h, T * Transform3D(Basis(), Vector3(sx * 0.033, 1.686, -0.1)))
		gear("eyes", ModelKit.sphere(0.0075, 8), h, T * Transform3D(Basis(), Vector3(sx * 0.033, 1.686, -0.106)))
		# Long ears drooping out to the sides.
		var ear_prof := [[0.0, 0.035, 0.012], [0.35, 0.04, 0.01, 0.006], [0.75, 0.022, 0.008, 0.004], [1.0, 0.0, 0.0]]
		var em := OrganicMesh.profile(k + "_tear", Vector3.ZERO, Vector3(0, 0.11, 0), ear_prof, 8, 6, Vector3.BACK)
		flesh_slot(SKIN).rigid(em, T * Transform3D(Basis.from_euler(Vector3(0.5, sx * 0.5, -sx * 1.35)), Vector3(sx * 0.074, 1.682, 0.0)), h)
	# Hooked nose with a warty bulb, a broad upper lip.
	flesh_slot(SKIN).rigid(OrganicMesh.bezier(k + "_nose", Vector3.ZERO, Vector3(0, -0.01, -0.035), Vector3(0, -0.04, -0.05), 0.017, 0.02, 6, 10), T * Transform3D(Basis(), Vector3(0, 1.685, -0.1)), h)
	flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_nosebulb", Vector3(0.025, 0.022, 0.022), 0.15, 27, 10), T * Transform3D(Basis(), Vector3(0, 1.645, -0.148)), h)
	flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_uplip", Vector3(0.05, 0.02, 0.04), 0.08, 29, 10), T * Transform3D(Basis(), Vector3(0, 1.627, -0.098)), h)
	# The jutting lower jaw, a lower lip and tusks (on the jaw bone).
	flesh_slot(SKIN).rigid(OrganicMesh.profile(k + "_jaw", Vector3(0, 1.64, 0.0), Vector3(0, 1.603, -0.13), [[0.0, 0.07, 0.035], [0.4, 0.068, 0.04, -0.004], [0.8, 0.062, 0.038, -0.006], [1.0, 0.05, 0.028, -0.005]], 14, 10), T, j)
	flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_lolip", Vector3(0.052, 0.015, 0.025), 0.08, 30, 10), T * Transform3D(Basis(), Vector3(0, 1.617, -0.122)), j)
	flesh_slot(MOUTH).rigid(OrganicMesh.blob(k + "_mouth", Vector3(0.048, 0.013, 0.05), 0.05, 31, 10), T * Transform3D(Basis(), Vector3(0, 1.618, -0.095)), j)
	var tl := 0.07 if tribe == 2 else 0.045
	for sx: float in [-1.0, 1.0]:
		var tusk := OrganicMesh.bezier("%s_tusk_%d_%d" % [k, int(sx), int(tl * 1000.0)], Vector3.ZERO, Vector3(sx * tl * 0.1, tl * 0.6, 0.0), Vector3(sx * tl * 0.35, tl, tl * 0.2), 0.009 * tl / 0.045, 0.002, 7, 7)
		gear("teeth", tusk, j, T * Transform3D(Basis(), Vector3(sx * 0.038, 1.618, -0.122)))
		for t in 2:
			gear("teeth", OrganicMesh.bezier(k + "_ltooth", Vector3.ZERO, Vector3(0, 0.006, 0), Vector3(0, 0.012, 0.0), 0.005, 0.003, 2, 5), j, T * Transform3D(Basis(), Vector3(sx * (0.01 + t * 0.011), 1.62, -0.128)))
	# Hair by tribe: a stringy moss-matted mane, a bare scarred scalp, a topknot.
	if tribe == 0:
		for i in 11:
			var a := lerpf(-1.6, 1.6, i / 10.0)
			var root := Vector3(sin(a) * 0.07, 1.73 - absf(a) * 0.01, cos(a) * 0.05)
			gear("moss", OrganicMesh.bezier("%s_mhair_%d" % [k, i % 3], Vector3.ZERO, Vector3(sin(a) * 0.03, -0.03, 0.04), Vector3(sin(a) * 0.045, -0.13 - 0.03 * (i % 3), 0.05), 0.012, 0.004, 6, 6), h, T * Transform3D(Basis(), root))
	elif tribe == 2:
		gear("hair", OrganicMesh.bezier(k + "_topknot", Vector3.ZERO, Vector3(0, 0.05, 0.02), Vector3(0, 0.06, 0.1), 0.02, 0.006, 8, 8), h, T * Transform3D(Basis(), Vector3(0, 1.75, 0.0)))
		gear("leather", BossKit.torus(k + "_knotband", 0.018, 0.005, 10, 4), h, T * Transform3D(Basis(), Vector3(0, 1.765, 0.005)))
		for sx: float in [-1.0, 1.0]:
			gear("metal", BossKit.torus(k + "_earring", 0.012, 0.003, 10, 4), h, T * Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(sx * 0.13, 1.64, 0.02)))


func _troll_gear(k: String) -> void:
	var hw := _rest[R.THIGH_R].x
	var sw := _rest[R.UARM_R].x
	# Belt of twisted rope and a hide loincloth front and back.
	gear("rope", BossKit.torus(k + "_belt", hw * 1.72, 0.022, 28, 6), R.HIPS, Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.75)), Vector3(0, 1.0, 0.0)))
	_strips(k, "hide", R.HIPS, 7, 0.99, hw * 1.65, 0.2, PI * 0.75, PI * 1.25, 0.32, 0.4, 0.07, 0.05, 3, false)
	_strips(k, "hide", R.HIPS, 7, 0.99, hw * 1.65, 0.18, -PI * 0.28, PI * 0.28, 0.26, 0.36, 0.07, 0.05, 5, false)
	# Wrapped forearms.
	for sx: float in [-1.0, 1.0]:
		var o := 0 if sx < 0.0 else 5
		var wr := _rest[R.HAND_L + o]
		var el := _rest[R.FARM_L + o]
		for i in 3:
			var p := el.lerp(wr, 0.62 + i * 0.1)
			gear("leather", BossKit.torus(k + "_wrap", 0.08 - i * 0.006, 0.014, 14, 5), R.FARM_L + o, Transform3D(Basis(Vector3.RIGHT, 0.15 * (i - 1)), p), Color(0.8, 0.7, 0.6))
	match tribe:
		0:
			# Moss and mushrooms growing on the shoulders and back.
			var rng := RandomNumberGenerator.new()
			rng.seed = 41
			for i in 9:
				var sx := -1.0 if i % 2 == 0 else 1.0
				var p := Vector3(sx * rng.randf_range(0.05, sw * 0.9), rng.randf_range(1.33, 1.5), rng.randf_range(0.04, 0.16))
				gear("moss", OrganicMesh.blob("%s_moss_%d" % [k, i % 4], Vector3(0.09, 0.035, 0.08), 0.45, 50 + i % 4, 10), R.CHEST, Transform3D(Basis(Vector3.RIGHT, 0.4), p))
			for sx: float in [-1.0, 1.0]:
				var o := 0 if sx < 0.0 else 5
				gear("moss", OrganicMesh.blob(k + "_moss_sh", Vector3(0.11, 0.04, 0.1), 0.45, 59, 10), R.UARM_L + o, Transform3D(Basis(), _rest[R.UARM_L + o] + Vector3(sx * 0.03, 0.1, 0.0)))
			for m in 4:
				var base := Vector3(0.1 + m * 0.04, 1.47 + (m % 2) * 0.03, 0.1 - m * 0.02)
				var sh := 0.03 + m * 0.008
				gear("bone", BossKit.lathe(k + "_stem", PackedVector2Array([Vector2(0.007, 0.0), Vector2(0.006, sh)]), 6), R.CHEST, Transform3D(Basis(Vector3.FORWARD, -0.3 + m * 0.15), base))
				var cap := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.024, 0.0), Vector2(0.026, 0.006), Vector2(0.018, 0.016), Vector2(0.0, 0.02)])
				gear("cap", BossKit.lathe(k + "_cap", cap, 10, 1.0, 1.0, true, true), R.CHEST, Transform3D(Basis(Vector3.FORWARD, -0.3 + m * 0.15).scaled(Vector3.ONE * (0.8 + m * 0.15)), base + Basis(Vector3.FORWARD, -0.3 + m * 0.15) * Vector3(0, sh, 0)))
		1:
			# Bone spikes driven along the spine, a spiked hide pauldron on the left.
			for i in 5:
				var y := 1.48 - i * 0.075
				var l := 0.11 - i * 0.012
				gear("bone", OrganicMesh.bezier("%s_bspike_%d" % [k, i], Vector3.ZERO, Vector3(0, l * 0.4, l * 0.5), Vector3(0, l * 0.5, l), 0.022, 0.003, 6, 6), R.CHEST if y > 1.2 else R.SPINE, Transform3D(Basis(), Vector3(0, y, 0.16 + (0.04 if y > 1.3 else 0.0))))
			var sh := _rest[R.UARM_L]
			var pad := BossKit.shell(k + "_pad", Vector3(0.15, 0.12, 0.16), -110, 110, 0, 85, 0.02, 14, 7)
			gear("hide", pad, R.UARM_L, Transform3D(Basis(Vector3.FORWARD, -0.35) * Basis(Vector3.UP, PI * 0.5), sh + Vector3(-0.03, 0.06, 0)))
			for i in 4:
				var a := lerpf(-0.9, 0.9, i / 3.0)
				gear("bone", OrganicMesh.bezier("%s_pspike_%d" % [k, i], Vector3.ZERO, Vector3(-0.02, 0.05, 0), Vector3(-0.05, 0.11 - absf(a) * 0.03, 0.0), 0.016, 0.002, 6, 5), R.UARM_L, Transform3D(Basis(), sh + Vector3(-0.08, 0.14 - absf(a) * 0.04, a * 0.1)))
			gear("leather", BossKit.torus(k + "_padstrap", 0.24, 0.012, 22, 4), R.CHEST, Transform3D(Basis(Vector3.FORWARD, -0.75), Vector3(0.0, 1.32, 0.0)))
		_:
			# A necklace of teeth and little skulls.
			for i in 13:
				var a := lerpf(-1.25, 1.25, i / 12.0)
				var p := Vector3(sin(a) * 0.19, 1.47 - cos(a * 0.8) * 0.12, -cos(a) * 0.16 + 0.02)
				if i % 4 == 2:
					gear("bone", OrganicMesh.blob(k + "_nskull", Vector3(0.025, 0.028, 0.026), 0.08, 61, 8), R.CHEST, Transform3D(Basis(), p))
				else:
					gear("teeth", OrganicMesh.bezier(k + "_ntooth", Vector3.ZERO, Vector3(0, -0.02, -0.005), Vector3(0, -0.04, 0.0), 0.007, 0.002, 4, 5), R.CHEST, Transform3D(Basis(), p))
			var cord := PackedVector3Array()
			var cord_r := PackedVector2Array()
			for i in 13:
				var a := lerpf(-1.4, 1.4, i / 12.0)
				cord.append(Vector3(sin(a) * 0.195, 1.485 - cos(a * 0.8) * 0.12 + (0.0 if absf(a) < 1.3 else 0.03), -cos(a) * 0.165 + 0.02))
				cord_r.append(Vector2(0.005, 0.005))
			gear("leather", OrganicMesh.sweep(k + "_cord", cord, cord_r, 4), R.CHEST)


## Weapons: a gnarled tree-branch club (iron-studded for the tusked tribe) or a stone maul.
func _build_held(item_id: String) -> void:
	if item_id != "club" and item_id != "giant_club":
		super._build_held(item_id)
		return
	_held_id = item_id
	if _held != null:
		_held.queue_free()
	_held = Node3D.new()
	_held.name = "Club"
	grip_r.add_child(_held)
	var wood := BossKit.wood(Color(0.2, 0.13, 0.08))
	var asm := BossKit.assembly()
	var key := "troll_%s_%d" % [item_id, tribe]
	if item_id == "giant_club":
		var rock := BossKit.rock(Color(0.32, 0.33, 0.33), {"pattern_scale": 10.0})
		var rope := BossKit.wood(Color(0.35, 0.28, 0.18), {"albedo": Color(0.65, 0.55, 0.38), "pattern_scale": 40.0})
		asm.add(BossKit.lathe(key + "_haft", PackedVector2Array([Vector2(0.03, -0.2), Vector2(0.034, 0.0), Vector2(0.036, 0.9), Vector2(0.04, 1.05)]), 9), wood, Transform3D.IDENTITY, Color(0.5, 0.38, 0.26))
		asm.add(OrganicMesh.blob(key + "_head", Vector3(0.17, 0.13, 0.14), 0.3, 77, 14), rock, Transform3D(Basis(Vector3.UP, 0.3), Vector3(0, 1.08, 0)), Color(0.6, 0.6, 0.58))
		for i in 3:
			asm.add(BossKit.torus(key + "_lash", 0.05, 0.012, 12, 5), rope, Transform3D(Basis(Vector3.FORWARD, 0.4 * (i - 1)), Vector3(0, 0.96 + i * 0.03, 0)), Color(1, 1, 1))
		asm.add(BossKit.torus(key + "_lash2", 0.14, 0.012, 18, 5), rope, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.08, 0)), Color(1, 1, 1))
		_held_len = 1.25
	else:
		asm.add(OrganicMesh.profile(key + "_branch", Vector3(0, -0.18, 0), Vector3(0.02, 1.0, 0.0), [[0.0, 0.035, 0.035], [0.25, 0.04, 0.04], [0.6, 0.065, 0.06, 0.005], [0.85, 0.095, 0.09, -0.01], [1.0, 0.07, 0.07]], 10, 12, Vector3.BACK), wood, Transform3D.IDENTITY, Color(0.5, 0.38, 0.26))
		var rng := RandomNumberGenerator.new()
		rng.seed = 9
		for i in 6:
			var y := rng.randf_range(0.3, 0.95)
			var a := rng.randf() * TAU
			var r := 0.04 + y * 0.05
			asm.add(OrganicMesh.blob(key + "_knot", Vector3(0.03, 0.04, 0.03), 0.3, 80 + i % 3, 8), wood, Transform3D(Basis(), Vector3(cos(a) * r, y, sin(a) * r)), Color(0.42, 0.32, 0.22))
		if tribe == 2:
			var iron := BossKit.metal({"albedo": Color(0.4, 0.38, 0.36), "rust": 0.5})
			for i in 9:
				var y := 0.62 + (i / 3) * 0.13
				var a := TAU * float(i % 3) / 3.0 + (i / 3) * 0.6
				var r := 0.05 + y * 0.045
				var d := Vector3(cos(a), 0, sin(a))
				asm.add(OrganicMesh.bezier(key + "_stud", Vector3.ZERO, d * 0.02, d * 0.045, 0.012, 0.002, 3, 5), iron, Transform3D(Basis(), d * r + Vector3(0, y, 0)), Color(1, 1, 1))
		_held_len = 1.1
	bake_into(_held, key, asm)


# --- Ghoul -----------------------------------------------------------------------------------

func _ghoul(k: String) -> void:
	var sw := _rest[R.UARM_R].x
	var hw := _rest[R.THIGH_R].x
	var H := R.HIPS
	var S := R.SPINE
	var C := R.CHEST
	# A starved torso: narrow ribcage, a waist sucked in under it, sharp hips.
	_torso([[0.84, 0.0, hw * 0.9, 0.075, H], [0.92, 0.0, hw * 1.35, 0.1, H], [1.0, 0.0, hw * 1.35, 0.095, H], [1.08, 0.01, sw * 0.52, 0.072, S],
		[1.16, 0.0, sw * 0.6, 0.08, S], [1.24, -0.005, sw * 0.74, 0.1, C], [1.33, 0.0, sw * 0.8, 0.105, C], [1.41, 0.01, sw * 0.8, 0.095, C],
		[1.47, 0.02, sw * 0.6, 0.08, C], [1.52, 0.015, 0.05, 0.05, R.NECK], [1.58, 0.0, 0.042, 0.045, R.NECK], [1.62, -0.01, 0.04, 0.04, R.HEAD]], 0.07)
	# Ribs, sternum, collarbones, spine and hip bones pressing through.
	for i in 7:
		var yb := 1.43 - i * 0.034
		var w := sw * (0.62 + sin(minf(1.0, i / 5.0) * PI * 0.5) * 0.17)
		for sx: float in [-1.0, 1.0]:
			var path := PackedVector3Array()
			var radii := PackedVector2Array()
			for j in 7:
				var a := lerpf(0.5, PI * 0.88, j / 6.0)
				var y := yb - sin(a * 0.5) * (0.05 + i * 0.006)
				var d := 0.095 + 0.008 * sin(i * 0.5)
				path.append(Vector3(sx * sin(a) * w * 1.02, y, cos(a) * d * 1.02))
				radii.append(Vector2(0.007, 0.007))
			flesh_slot(SKIN).tube(path, radii, [C, C, C, C, C, C, C], 0.05, 5, Vector3.UP)
	for i in 12:
		var y := 1.0 + i * 0.042
		flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_vbump", Vector3(0.014, 0.012, 0.012), 0.05, 33, 6), Transform3D(Basis(), Vector3(0, y, 0.075 + (0.025 if y > 1.2 else 0.0) - (0.005 if y < 1.1 else 0.0))), H if y < 1.05 else (S if y < 1.2 else C))
	for sx: float in [-1.0, 1.0]:
		var o := 0 if sx < 0.0 else 5
		flesh_slot(SKIN).rigid(OrganicMesh.bezier(k + "_clav_%d" % int(sx), Vector3.ZERO, Vector3(sx * 0.06, 0.012, 0.01), Vector3(sx * (sw - 0.03), 0.02, 0.06), 0.011, 0.009, 6, 6), Transform3D(Basis(), Vector3(sx * 0.02, 1.45, -0.075)), R.CLAV_L + o)
		flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_hipbone", Vector3(0.025, 0.02, 0.03), 0.1, 35, 8), Transform3D(Basis(), Vector3(sx * hw * 1.3, 1.0, -0.06)), H)
		flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_scap", Vector3(0.045, 0.06, 0.015), 0.1, 37, 8), Transform3D(Basis(Vector3.UP, sx * 0.4), Vector3(sx * sw * 0.55, 1.36, 0.075)), C)
	var arm_prof := [[0.0, 0.045, 0.05], [0.16, 0.05, 0.05], [0.3, 0.036, 0.038], [0.48, 0.03, 0.032], [0.54, 0.036, 0.038], [0.62, 0.03, 0.03],
		[0.8, 0.026, 0.024], [0.88, 0.024, 0.018], [1.0, 0.03, 0.014]]
	var leg_prof := [[0.0, 0.06, 0.065], [0.14, 0.065, 0.07], [0.32, 0.048, 0.052], [0.52, 0.036, 0.04], [0.57, 0.042, 0.045], [0.64, 0.034, 0.036, 0.008],
		[0.86, 0.026, 0.028], [1.0, 0.028, 0.03]]
	for sx: float in [-1.0, 1.0]:
		flesh_limb(SKIN, _arm_joints(sx, sw * 0.4), _arm_bones(sx), arm_prof, R.CHEST, 22, 10)
		flesh_limb(SKIN, _leg_joints(sx), _leg_bones(sx), leg_prof, R.HIPS, 20, 10)
		_sculpt_hand(k, sx, 0.11, 0.0085, 0.04)
		_sculpt_foot(k, sx, 0.04, 0.22, 0.04, 0.025)
		var o := 0 if sx < 0.0 else 5
		var lo := 0 if sx < 0.0 else 4
		flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_elbow", Vector3(0.022, 0.026, 0.022), 0.1, 39, 6), Transform3D(Basis(), _rest[R.FARM_L + o] + Vector3(0, 0.0, 0.02)), R.FARM_L + o)
		flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_knee", Vector3(0.03, 0.032, 0.025), 0.1, 41, 6), Transform3D(Basis(), _rest[R.SHIN_L + lo] + Vector3(0, 0.01, -0.035)), R.SHIN_L + lo)
	_corpse_head(k, true)
	_strips(k, "cloth", R.HIPS, 12, 0.985, hw * 1.4, 0.105, -PI, PI, 0.18, 0.42, 0.035, 0.015, 7)
	gear("rope", BossKit.torus(k + "_belt", hw * 1.38, 0.008, 20, 4), R.HIPS, Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.75)), Vector3(0, 0.99, 0.0)))
	if wild_hair:
		_lank_hair(k, 11, 0.32)


## Skull-tight head (ghoul) or swollen waterlogged face (drowned).
func _corpse_head(k: String, ghoul: bool) -> void:
	var h := R.HEAD
	var c := Vector3(0, 1.72, -0.005)
	flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_cranium", Vector3(0.074, 0.085, 0.095) * (1.0 if ghoul else 1.06), 0.05 if ghoul else 0.12, 43, 16), Transform3D(Basis(), c), h)
	# Face: brow, cheekbones (sharp on the ghoul, puffy on the drowned), nose.
	var brow := PackedVector3Array()
	var brow_r := PackedVector2Array()
	for i in 7:
		var a := lerpf(-1.0, 1.0, i / 6.0)
		brow.append(Vector3(sin(a) * 0.058, 1.71, -0.078 - cos(a) * 0.016))
		brow_r.append(Vector2(0.013, 0.011))
	flesh_slot(SKIN).tube(brow, brow_r, [h, h, h, h, h, h, h], 0.05, 8, Vector3.UP)
	for sx: float in [-1.0, 1.0]:
		var cheek := Vector3(0.016, 0.014, 0.02) if ghoul else Vector3(0.019, 0.016, 0.02)
		flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_cheek", cheek, 0.05, 45, 8), Transform3D(Basis(), Vector3(sx * 0.05, 1.672, -0.068)), h)
		# Sunken sockets with a cold glow deep inside.
		gear("dark", OrganicMesh.blob(k + "_socket", Vector3(0.019, 0.016, 0.012), 0.05, 47, 8), h, Transform3D(Basis(), Vector3(sx * 0.03, 1.693, -0.088)))
		gear("eyes", ModelKit.sphere(0.0065 if ghoul else 0.0062, 8), h, Transform3D(Basis(), Vector3(sx * 0.03, 1.693, -0.095)))
		if ghoul:
			_ear(k, sx, Vector3(sx * 0.07, 1.71, 0.0), 0.085, 0.03, Vector3(0.25, sx * 0.5, -sx * 1.15))
		else:
			flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_dear", Vector3(0.012, 0.03, 0.022), 0.15, 49, 8), Transform3D(Basis(), Vector3(sx * 0.074, 1.69, 0.0)), h)
	if ghoul:
		# Two slits for a nose, a lipless mouth of long teeth.
		for sx: float in [-1.0, 1.0]:
			gear("dark", OrganicMesh.blob(k + "_nslit", Vector3(0.006, 0.012, 0.005), 0.05, 51, 6), h, Transform3D(Basis(Vector3.FORWARD, sx * 0.3), Vector3(sx * 0.008, 1.668, -0.093)))
		flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_maxilla", Vector3(0.034, 0.02, 0.028), 0.05, 53, 10), Transform3D(Basis(), Vector3(0, 1.643, -0.066)), h)
		for i in 10:
			var a := lerpf(-1.1, 1.1, i / 9.0)
			var p := Vector3(sin(a) * 0.034, 1.627, -cos(a) * 0.05 - 0.03)
			gear("teeth", OrganicMesh.bezier(k + "_gtooth", Vector3.ZERO, Vector3(0, -0.008, 0), Vector3(0, -0.017, -0.002), 0.005, 0.0025, 3, 5), h, Transform3D(Basis(), p))
			gear("teeth", OrganicMesh.bezier(k + "_gtooth_l", Vector3.ZERO, Vector3(0, 0.007, 0), Vector3(0, 0.014, -0.002), 0.0045, 0.0025, 3, 5), R.JAW, Transform3D(Basis(), p + Vector3(0, -0.026, 0.004)))
		flesh_slot(SKIN).rigid(OrganicMesh.profile(k + "_jaw", Vector3(0, 1.65, 0.0), Vector3(0, 1.598, -0.08), [[0.0, 0.044, 0.02], [0.5, 0.036, 0.017], [1.0, 0.024, 0.013]], 12, 8), Transform3D.IDENTITY, R.JAW)
		flesh_slot(MOUTH).rigid(OrganicMesh.blob(k + "_mouth", Vector3(0.026, 0.01, 0.03), 0.05, 55, 8), Transform3D(Basis(), Vector3(0, 1.614, -0.055)), R.JAW)
	else:
		# A puffy nose, swollen lips, a slack jaw hanging open.
		flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_dnose", Vector3(0.016, 0.026, 0.02), 0.1, 57, 8), Transform3D(Basis(Vector3.RIGHT, -0.3), Vector3(0, 1.668, -0.095)), h)
		flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_duplip", Vector3(0.03, 0.009, 0.014), 0.1, 59, 8), Transform3D(Basis(), Vector3(0, 1.636, -0.088)), h)
		flesh_slot(SKIN).rigid(OrganicMesh.profile(k + "_djaw", Vector3(0, 1.65, 0.0), Vector3(0, 1.6, -0.088), [[0.0, 0.055, 0.03], [0.5, 0.05, 0.028], [1.0, 0.034, 0.02]], 12, 8), Transform3D.IDENTITY, R.JAW)
		flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_dlolip", Vector3(0.027, 0.009, 0.014), 0.1, 61, 8), Transform3D(Basis(), Vector3(0, 1.607, -0.088)), R.JAW)
		flesh_slot(MOUTH).rigid(OrganicMesh.blob(k + "_mouth", Vector3(0.032, 0.02, 0.04), 0.05, 63, 8), Transform3D(Basis(), Vector3(0, 1.62, -0.065)), R.JAW)
		flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_jowl", Vector3(0.042, 0.022, 0.038), 0.12, 65, 10), Transform3D(Basis(), Vector3(0, 1.6, -0.035)), R.JAW, R.NECK, 0.4)


## Lank strands of hair from the scalp.
func _lank_hair(k: String, n: int, l: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for i in n:
		var a := lerpf(-1.9, 1.9, (float(i) + 0.5) / n)
		var root := Vector3(sin(a) * 0.07, 1.775 - absf(a) * 0.02, cos(a) * 0.075 - 0.005)
		var ll := l * rng.randf_range(0.6, 1.0)
		var out := Vector3(sin(a), 0, cos(a))
		var path := PackedVector3Array()
		var widths := PackedFloat32Array()
		for j in 6:
			var t := float(j) / 5.0
			path.append(root + out * (0.02 * sqrt(t) + 0.012) + Vector3(0, -ll * t, 0.01 * t))
			widths.append(lerpf(0.016, 0.004, t))
		gear("hair", BossKit.ribbon("%s_hair_%d" % [k, i], path, widths, Vector3(cos(a), 0, -sin(a)), 0.006), R.HEAD)


# --- Drowned ---------------------------------------------------------------------------------

func _drowned(k: String) -> void:
	var sw := _rest[R.UARM_R].x
	var hw := _rest[R.THIGH_R].x
	var H := R.HIPS
	var S := R.SPINE
	var C := R.CHEST
	# Bloated with seawater: a swollen belly and puffy limbs.
	_torso([[0.84, 0.0, hw * 1.0, 0.09, H], [0.92, 0.0, hw * 1.6, 0.125, H], [1.0, -0.01, hw * 1.75, 0.14, H], [1.08, -0.025, sw * 0.86, 0.15, S],
		[1.16, -0.02, sw * 0.88, 0.145, S], [1.25, -0.01, sw * 0.86, 0.13, C], [1.34, 0.0, sw * 0.88, 0.122, C], [1.42, 0.01, sw * 0.88, 0.11, C],
		[1.48, 0.02, sw * 0.62, 0.095, C], [1.53, 0.015, 0.065, 0.06, R.NECK], [1.59, 0.0, 0.058, 0.056, R.NECK], [1.63, -0.01, 0.052, 0.052, R.HEAD]], 0.08)
	# Barnacles crusted over the back and shoulders (on the torso).
	var barn := BossKit.lathe(k + "_barnacle", PackedVector2Array([Vector2(0.016, 0.0), Vector2(0.013, 0.012), Vector2(0.007, 0.018), Vector2(0.004, 0.016)]), 7, 1.0, 1.0, true, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for i in 26:
		var th := rng.randf_range(-1.9, 1.9)
		var y := rng.randf_range(1.18, 1.46)
		var rx := sw * 0.87
		var rz := 0.12
		var nrm := Vector3(sin(th) / rx, 0.15, cos(th) / rz).normalized()
		var pos := Vector3(sin(th) * rx, y, cos(th) * rz) - nrm * 0.004
		var up := Vector3.UP if absf(nrm.y) < 0.9 else Vector3.BACK
		var bb := Basis.looking_at(-nrm, up) * Basis(Vector3.RIGHT, PI * 0.5)
		flesh_slot(NAIL).rigid(barn, Transform3D(bb.scaled(Vector3.ONE * rng.randf_range(0.7, 1.3)), pos), R.CHEST)
	var arm_prof := [[0.0, 0.055, 0.06], [0.16, 0.068, 0.066], [0.3, 0.058, 0.058], [0.48, 0.05, 0.052], [0.54, 0.048, 0.05], [0.64, 0.052, 0.052],
		[0.8, 0.042, 0.04], [0.88, 0.036, 0.03], [1.0, 0.04, 0.022]]
	var leg_prof := [[0.0, 0.085, 0.09], [0.14, 0.09, 0.095], [0.32, 0.075, 0.08], [0.52, 0.055, 0.06], [0.58, 0.054, 0.058], [0.66, 0.058, 0.062, 0.01],
		[0.86, 0.042, 0.044], [1.0, 0.04, 0.042]]
	for sx: float in [-1.0, 1.0]:
		flesh_limb(SKIN, _arm_joints(sx, sw * 0.42), _arm_bones(sx), arm_prof, R.CHEST, 20, 12)
		flesh_limb(SKIN, _leg_joints(sx), _leg_bones(sx), leg_prof, R.HIPS, 18, 12)
		_sculpt_hand(k, sx, 0.085, 0.011, 0.012)
		_sculpt_foot(k, sx, 0.048, 0.24, 0.05, 0.0)
	flesh_slot(SKIN).rigid(OrganicMesh.blob(k + "_belly", Vector3(0.14, 0.12, 0.06), 0.1, 67, 12), Transform3D(Basis(), Vector3(0, 1.12, -0.11)), S)
	_corpse_head(k, false)
	_lank_hair(k, 13, 0.36)
	# Rags of a sailor's shirt and breeches.
	_strips(k, "cloth", R.HIPS, 12, 0.985, hw * 1.7, 0.14, -PI, PI, 0.22, 0.4, 0.045, 0.02, 11)
	# Kelp hanging from the shoulders, belt and arms.
	_strips(k, "kelp", R.CHEST, 6, 1.47, sw * 0.8, 0.1, -PI, PI, 0.3, 0.55, 0.022, 0.008, 15)
	_strips(k, "kelp", R.HIPS, 5, 0.98, hw * 1.75, 0.15, -PI, PI, 0.3, 0.5, 0.024, 0.008, 17, false)
	for sx: float in [-1.0, 1.0]:
		var o := 0 if sx < 0.0 else 5
		var el := _rest[R.FARM_L + o]
		var path := PackedVector3Array([el + Vector3(sx * 0.05, 0.02, 0), el + Vector3(sx * 0.06, -0.12, 0.01), el + Vector3(sx * 0.055, -0.3, 0.0)])
		gear("kelp", BossKit.ribbon("%s_akelp_%d" % [k, int(sx)], path, PackedFloat32Array([0.018, 0.014, 0.005]), Vector3.BACK, 0.005), R.FARM_L + o)
	# A rusted manacle on the left wrist with a few links of broken chain.
	var wr := _rest[R.HAND_L] + Vector3(0, 0.03, 0)
	gear("metal", BossKit.torus(k + "_manacle", 0.042, 0.011, 14, 5), R.FARM_L, Transform3D(Basis(), wr))
	for i in 4:
		var b := Basis(Vector3.UP, PI * 0.5 * (i % 2)) * Basis(Vector3.FORWARD, PI * 0.5)
		gear("metal", BossKit.torus(k + "_link", 0.017, 0.0055, 10, 4), R.FARM_L, Transform3D(b.scaled(Vector3(1.0, 1.0, 1.0)), wr + Vector3(-0.01, -0.03 - i * 0.03, 0.0)))
