class_name ImpModel
extends MobModel
## A small winged devil of the underworld: one skinned body (MobRig) of
## wiry, ember-veined red hide - a big-skulled head with heavy brows, swept
## pointed ears, curling black horns, a wide grin of needle teeth over a
## smouldering throat and slit amber eyes; a lean torso with pecs and a
## pot belly, clawed three-fingered hands, digitigrade legs with clawed feet,
## a whip tail ending in a barbed spade, and bat wings: membrane stretched
## over the arm and three long finger bones, skinned so they spread on the
## downstroke and fold on the upstroke.
## Motion: flapping hover (the body lifts with each downstroke), dangling
## legs, swishing tail; `throw` / `attack` / `cast` winds a fireball up over
## the shoulder and hurls it, `hit` jerks back, death folds the wings and
## drops it to the ground. Faces -Z.

const HIPS := 0
const SPINE := 1
const CHEST := 2
const NECK := 3
const HEAD := 4
const JAW := 5
const ARM_L := 6     # up, lo, hand, fingers
const ARM_R := 10
const LEG_L := 14    # thigh, shin, foot, toes
const LEG_R := 18
const TAIL := 22     # 5 bones
const TAIL_N := 5
const WING_L := 27   # shoulder, elbow, wrist, finger 1..3
const WING_R := 33

const S_SKIN := 0
const S_WING := 1
const S_HORN := 2
const S_EYE := 3
const S_MOUTH := 4
const S_EMBER := 5

var hand_fire: Node3D
var _fire_fx: GPUParticles3D
var _flap := 0.0
var _throw := 0.0
var _flinch := 0.0
var _jaw_open := 0.0
var _fall_y := 0.0
var _variant := 0


func _init(variant_seed := 0) -> void:
	_variant = variant_seed
	dissolve_delay = 1.2
	durations["throw"] = 0.9


func _ember_extents() -> Vector3:
	return Vector3(0.3, 0.4, 0.3)


func _lod_size() -> float:
	return 1.5


# --- Build -------------------------------------------------------------------------------

func _build() -> void:
	var skin := CreatureSkin.hide(Color(0.4, 0.075, 0.045), Color(0.62, 0.2, 0.09), {"use_rest": true, "pattern_scale": 16.0, "bump": 0.3,
		"roughness": 0.62, "rim": 0.4, "specular_amount": 0.3, "accent": Color(0.13, 0.025, 0.02), "accent_mode": 3, "accent_amount": 0.7,
		"accent_scale": 5.0, "bump_distance": 15.0})
	var wing := CreatureSkin.membrane(Color(0.2, 0.04, 0.03), {"use_rest": true, "pattern_scale": 7.0, "backlight": 1.3, "rim": 0.35})
	var horn := CreatureSkin.keratin(Color(0.07, 0.05, 0.045), {"use_rest": true, "pattern_scale": 60.0, "roughness": 0.3, "specular_amount": 0.7})
	var eye := ModelKit.glow(Color(1.0, 0.72, 0.15), 7.0, 0.1)
	var mouth := CreatureSkin.mouth(Color(0.3, 0.05, 0.03))
	var ember := ModelKit.glow(Color(1.0, 0.4, 0.08), 3.5, 0.5)
	rig_instance(_rig_data(), [skin, wing, horn, eye, mouth, ember], 1.0, 1.4)
	# Fireball held in the right hand while winding up a throw.
	hand_fire = follow(ARM_R + 3, "HandFire")
	var ball := ModelKit.part(hand_fire, ModelKit.sphere(0.075, 10), ModelKit.glow(Color(1.0, 0.55, 0.15), 7.0, 0.6), Vector3(0, -0.06, -0.02))
	ModelKit.part(ball, ModelKit.sphere(0.11, 10), MaterialLibrary.fx(Color(1.0, 0.6, 0.2), Color(1.0, 0.2, 0.03), 1.4))
	_fire_fx = ModelKit.embers(hand_fire, 16, Vector3(0.05, 0.05, 0.05), 0.5, 0.05, 1.0)
	_fire_fx.position = Vector3(0, -0.06, -0.02)
	hand_fire.visible = false


func _rig_data() -> Dictionary:
	var key := "mob_imp"
	if MobRig.has(key):
		return MobRig.cached(key)
	var r := MobRig.new(6)
	r.bone("hips", -1, Vector3(0, 0.93, 0.0))
	r.bone("spine", HIPS, Vector3(0, 1.05, 0.01))
	r.bone("chest", SPINE, Vector3(0, 1.18, 0.0))
	r.bone("neck", CHEST, Vector3(0, 1.29, -0.005))
	r.bone("head", NECK, Vector3(0, 1.36, -0.02))
	r.bone("jaw", HEAD, Vector3(0, 1.345, -0.05))
	for s: float in [-1.0, 1.0]:
		var sd := "l" if s < 0.0 else "r"
		var up := r.bone("arm_up_" + sd, CHEST, Vector3(s * 0.12, 1.245, 0.0))
		r.bone("arm_lo_" + sd, up, Vector3(s * 0.185, 1.08, 0.035))
		r.bone("hand_" + sd, up + 1, Vector3(s * 0.205, 0.94, -0.02))
		r.bone("fingers_" + sd, up + 2, Vector3(s * 0.212, 0.885, -0.035))
	for s: float in [-1.0, 1.0]:
		var sd := "l" if s < 0.0 else "r"
		var th := r.bone("thigh_" + sd, HIPS, Vector3(s * 0.07, 0.905, 0.0))
		r.bone("shin_" + sd, th, Vector3(s * 0.085, 0.75, -0.075))
		r.bone("foot_" + sd, th + 1, Vector3(s * 0.08, 0.6, 0.02))
		r.bone("toes_" + sd, th + 2, Vector3(s * 0.08, 0.555, -0.045))
	var tail_pts := [Vector3(0, 0.9, 0.06), Vector3(0, 0.84, 0.16), Vector3(0, 0.8, 0.27), Vector3(0, 0.8, 0.38), Vector3(0, 0.84, 0.47), Vector3(0, 0.9, 0.54)]
	for i in TAIL_N:
		r.bone("tail%d" % i, HIPS if i == 0 else TAIL + i - 1, tail_pts[i])
	for s: float in [-1.0, 1.0]:
		var sd := "l" if s < 0.0 else "r"
		var ws := r.bone("wing_sh_" + sd, CHEST, Vector3(s * 0.07, 1.23, 0.075))
		r.bone("wing_el_" + sd, ws, Vector3(s * 0.24, 1.36, 0.13))
		r.bone("wing_wr_" + sd, ws + 1, Vector3(s * 0.42, 1.31, 0.12))
		for f in 3:
			r.bone("wing_f%d_" % f + sd, ws + 2, Vector3(s * 0.42, 1.31, 0.12))

	# --- Torso: wiry, a little pot-bellied, broad at the shoulders.
	var st := [[0.855, 0.05, 0.045, 0.0], [0.89, 0.088, 0.07, 0.0], [0.95, 0.098, 0.074, 0.0], [1.02, 0.086, 0.074, -0.012],
		[1.09, 0.092, 0.072, -0.006], [1.16, 0.115, 0.078, 0.0], [1.22, 0.128, 0.074, 0.006], [1.265, 0.085, 0.06, 0.01],
		[1.3, 0.042, 0.042, 0.0], [1.345, 0.042, 0.048, -0.01]]
	var path := PackedVector3Array()
	var radii := PackedVector2Array()
	var bones: Array = []
	for row: Array in st:
		var y := float(row[0])
		path.append(Vector3(0, y, float(row[3])))
		radii.append(Vector2(float(row[1]), float(row[2])))
		bones.append(HIPS if y < 0.99 else (SPINE if y < 1.12 else (CHEST if y < 1.27 else (NECK if y < 1.33 else HEAD))))
	var rs := MobRig.resample(path, radii, bones, 26)
	r.slot(S_SKIN).tube(rs[0], rs[1], rs[2], 0.06, 16, Vector3.BACK)
	# Muscles: pecs, shoulder caps, shoulder blades, a ridge of spine knobs.
	for s: float in [-1.0, 1.0]:
		r.rigid(OrganicMesh.blob("imp_pec", Vector3(0.052, 0.036, 0.028), 0.06, 3, 10), Transform3D(Basis(Vector3.FORWARD, s * 0.25), Vector3(s * 0.048, 1.175, -0.06)), CHEST)
		r.rigid(OrganicMesh.blob("imp_delt", Vector3(0.045, 0.045, 0.045), 0.06, 5, 10), Transform3D(Basis(), Vector3(s * 0.118, 1.235, 0.0)), CHEST, ARM_L if s < 0.0 else ARM_R, 0.4)
		r.rigid(OrganicMesh.blob("imp_blade", Vector3(0.045, 0.06, 0.02), 0.08, 7, 8), Transform3D(Basis(Vector3.FORWARD, s * 0.3), Vector3(s * 0.06, 1.19, 0.062)), CHEST)
	for i in 6:
		var y := lerpf(0.95, 1.26, float(i) / 5.0)
		r.rigid(OrganicMesh.blob("imp_knob", Vector3(0.012, 0.012, 0.012), 0.1, 9, 6), Transform3D(Basis(), Vector3(0, y, 0.07 + sin(float(i)) * 0.004)), SPINE if y < 1.12 else CHEST)

	# --- Arms and hands.
	for s: float in [-1.0, 1.0]:
		var up := ARM_L if s < 0.0 else ARM_R
		var j := PackedVector3Array([Vector3(s * 0.07, 1.24, 0.0), r.rest[up], r.rest[up + 1], r.rest[up + 2], r.rest[up + 3]])
		r.slot(S_SKIN).limb(j, [CHEST, up, up + 1, up + 2], [[0.0, 0.04, 0.04], [0.16, 0.042, 0.04], [0.3, 0.031, 0.032], [0.42, 0.03, 0.034, -0.008],
			[0.56, 0.023, 0.024], [0.66, 0.027, 0.028, 0.004], [0.86, 0.017, 0.016], [1.0, 0.02, 0.01]], 22, 10, Vector3.BACK, 0.03, {CHEST: 1.0}, 0.06)
		var kn := r.rest[up + 3]
		var along := (kn - r.rest[up + 2]).normalized()
		var palm_n := Vector3(-s, 0, 0)
		palm_n = (palm_n - along * palm_n.dot(along)).normalized()
		var across := along.cross(palm_n).normalized()
		for f in 3:
			var o := (float(f) - 1.0) * 0.014
			var base := kn + across * o
			var l := 0.06 - absf(float(f) - 1.0) * 0.008
			var tip := base + along * l * 0.85 + palm_n * l * 0.35
			r.slot(S_SKIN).rigid(OrganicMesh.bezier("imp_finger_%d" % f, Vector3.ZERO, along * l * 0.55, tip - base, 0.0075, 0.005, 5, 6), Transform3D(Basis(), base), up + 3)
			var cd := (tip - base).normalized()
			r.slot(S_HORN).rigid(OrganicMesh.bezier("imp_claw", Vector3.ZERO, cd * 0.012, cd * 0.022 + palm_n * 0.008, 0.005, 0.0008, 4, 5), Transform3D(Basis(), tip - cd * 0.003), up + 3)
		var tb := r.rest[up + 2].lerp(kn, 0.5) - across * 0.02 + palm_n * 0.006
		r.slot(S_SKIN).rigid(OrganicMesh.bezier("imp_thumb_%d" % int(s), Vector3.ZERO, along * 0.025 - across * 0.008, along * 0.045 + palm_n * 0.018, 0.0075, 0.005, 5, 6), Transform3D(Basis(), tb), up + 2)

	# --- Legs: digitigrade, clawed three-toed feet, a spur at the heel.
	for s: float in [-1.0, 1.0]:
		var th := LEG_L if s < 0.0 else LEG_R
		var j := PackedVector3Array([Vector3(s * 0.04, 0.95, 0.0), r.rest[th], r.rest[th + 1], r.rest[th + 2], r.rest[th + 3]])
		r.slot(S_SKIN).limb(j, [HIPS, th, th + 1, th + 2], [[0.0, 0.05, 0.05], [0.18, 0.05, 0.055], [0.38, 0.034, 0.038], [0.48, 0.025, 0.028],
			[0.56, 0.026, 0.032, 0.008], [0.72, 0.016, 0.018], [0.82, 0.015, 0.016], [1.0, 0.018, 0.014]], 22, 10, Vector3.BACK, 0.03, {HIPS: 1.0}, 0.06)
		var toe := r.rest[th + 3]
		for f in 3:
			var a := (float(f) - 1.0) * 0.4
			var dir := Vector3(sin(a), -0.15, -cos(a)).normalized()
			r.slot(S_SKIN).rigid(OrganicMesh.bezier("imp_toe", Vector3.ZERO, dir * 0.025, dir * 0.045 + Vector3(0, -0.006, 0), 0.009, 0.006, 4, 6), Transform3D(Basis(), toe + Vector3(0, -0.005, 0)), th + 3)
			r.slot(S_HORN).rigid(OrganicMesh.bezier("imp_tclaw", Vector3.ZERO, dir * 0.012, dir * 0.02 + Vector3(0, -0.012, 0), 0.005, 0.0008, 4, 5), Transform3D(Basis(), toe + dir * 0.042), th + 3)
		r.slot(S_HORN).rigid(OrganicMesh.bezier("imp_spur", Vector3.ZERO, Vector3(0, -0.01, 0.015), Vector3(0, -0.005, 0.03), 0.006, 0.001, 4, 5), Transform3D(Basis(), r.rest[th + 2] + Vector3(0, -0.01, 0.01)), th + 2)

	# --- Tail: a whip with a barbed spade.
	var tp := PackedVector3Array()
	var trad := PackedVector2Array()
	var tb: Array = []
	for i in TAIL_N + 1:
		var p: Vector3 = tail_pts[i]
		tp.append(p)
		var rr := lerpf(0.026, 0.008, float(i) / TAIL_N)
		trad.append(Vector2(rr, rr))
		tb.append({HIPS: 1.0} if i == 0 else TAIL + mini(i - 1, TAIL_N - 1))
	var trs := MobRig.resample(tp, trad, tb, 24)
	r.slot(S_SKIN).tube(trs[0], trs[1], trs[2], 0.05, 8, Vector3.UP)
	var tip: Vector3 = tail_pts[TAIL_N]
	var spade := OrganicMesh.membrane("imp_spade", PackedVector2Array([Vector2(0, -0.01), Vector2(0.03, 0.02), Vector2(0.012, 0.03), Vector2(0, 0.065), Vector2(-0.012, 0.03), Vector2(-0.03, 0.02)]), 0.004, 0.012)
	r.slot(S_HORN).rigid(spade, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.RIGHT, -0.6), tip), TAIL + TAIL_N - 1)

	# --- Head.
	var hp := r.rest[HEAD]
	var skull := OrganicMesh.profile("imp_skull", Vector3(0, 0.025, 0.065), Vector3(0, -0.035, -0.088),
		[[0.0, 0.05, 0.055, 0.0], [0.22, 0.072, 0.075, 0.014], [0.45, 0.07, 0.068, 0.012], [0.65, 0.058, 0.05, -0.002], [0.82, 0.05, 0.04, -0.012], [1.0, 0.028, 0.024, -0.016]], 16, 14)
	r.slot(S_SKIN).rigid(skull, Transform3D(Basis(), hp), HEAD)
	# Heavy brow, cheekbones, a hooked nose, chin spike.
	r.rigid(OrganicMesh.profile("imp_brow", Vector3(-0.055, 0.0, 0.0), Vector3(0.055, 0.0, 0.0), [[0.0, 0.012, 0.012], [0.25, 0.02, 0.018, 0.006], [0.5, 0.016, 0.016, -0.004], [0.75, 0.02, 0.018, 0.006], [1.0, 0.012, 0.012]], 8, 10, Vector3.UP), Transform3D(Basis(), hp + Vector3(0, 0.03, -0.062)), HEAD)
	for s: float in [-1.0, 1.0]:
		r.rigid(OrganicMesh.blob("imp_cheek", Vector3(0.022, 0.018, 0.026), 0.08, 11, 8), Transform3D(Basis(), hp + Vector3(s * 0.045, -0.012, -0.05)), HEAD)
		# Slanted, glowing eyes in deep sockets.
		r.slot(S_EYE).rigid(ModelKit.sphere(0.012, 8), Transform3D(Basis(Vector3.FORWARD, -s * 0.45).scaled(Vector3(1.5, 0.75, 0.7)), hp + Vector3(s * 0.03, 0.013, -0.07)), HEAD)
		# Ears: long, pointed, swept back.
		var ear := OrganicMesh.profile("imp_ear", Vector3.ZERO, Vector3(0, 0.11, 0), [[0.0, 0.024, 0.008], [0.3, 0.02, 0.006, 0.006], [0.7, 0.01, 0.004, 0.004], [1.0, 0.0, 0.0]], 6, 6, Vector3.BACK)
		r.slot(S_SKIN).rigid(ear, Transform3D(Basis.from_euler(Vector3(1.2, s * 0.2, -s * 1.15)), hp + Vector3(s * 0.065, 0.005, 0.0)), HEAD)
		# Horns curling up and back.
		var horn := OrganicMesh.bezier("imp_horn_%d" % int(s), Vector3.ZERO, Vector3(s * 0.035, 0.07, 0.01), Vector3(s * 0.03, 0.12, 0.07), 0.018, 0.002, 9, 7)
		r.slot(S_HORN).rigid(horn, Transform3D(Basis(), hp + Vector3(s * 0.035, 0.055, -0.03)), HEAD)
	r.slot(S_SKIN).rigid(OrganicMesh.bezier("imp_nose", Vector3.ZERO, Vector3(0, -0.012, -0.012), Vector3(0, -0.022, -0.008), 0.011, 0.005, 4, 6), Transform3D(Basis(), hp + Vector3(0, 0.0, -0.088)), HEAD)
	# Grin: upper teeth, a smouldering throat, lower jaw with teeth and a chin spike.
	r.slot(S_EMBER).rigid(OrganicMesh.blob("imp_throat", Vector3(0.03, 0.012, 0.035), 0.05, 13, 8), Transform3D(Basis(), hp + Vector3(0, -0.04, -0.045)), HEAD)
	for t in 10:
		var f := float(t) / 9.0
		var a := lerpf(-1.1, 1.1, f)
		var tp2 := hp + Vector3(sin(a) * 0.04, -0.036, -0.085 + (1.0 - cos(a)) * 0.04)
		r.slot(S_HORN).rigid(OrganicMesh.bezier("imp_tooth", Vector3.ZERO, Vector3(0, -0.006, 0), Vector3(0, -0.011, 0.0), 0.0035, 0.0006, 3, 4), Transform3D(Basis(), tp2), HEAD)
	var jp := r.rest[JAW]
	r.slot(S_SKIN).rigid(OrganicMesh.profile("imp_jaw", Vector3(0, 0.0, 0.03), Vector3(0, -0.012, -0.05), [[0.0, 0.05, 0.02], [0.5, 0.045, 0.02], [0.85, 0.03, 0.016], [1.0, 0.016, 0.01]], 12, 8), Transform3D(Basis(), jp), JAW)
	r.slot(S_MOUTH).rigid(OrganicMesh.blob("imp_tongue", Vector3(0.022, 0.006, 0.03), 0.05, 17, 8), Transform3D(Basis(), jp + Vector3(0, 0.002, -0.02)), JAW)
	for t in 8:
		var f := float(t) / 7.0
		var a := lerpf(-1.0, 1.0, f)
		r.slot(S_HORN).rigid(OrganicMesh.bezier("imp_ltooth", Vector3.ZERO, Vector3(0, 0.005, 0), Vector3(0, 0.01, 0.0), 0.0032, 0.0006, 3, 4), Transform3D(Basis(), jp + Vector3(sin(a) * 0.036, 0.004, -0.045 + (1.0 - cos(a)) * 0.035)), JAW)
	r.slot(S_HORN).rigid(OrganicMesh.bezier("imp_chin", Vector3.ZERO, Vector3(0, -0.015, -0.006), Vector3(0, -0.03, 0.004), 0.008, 0.001, 4, 5), Transform3D(Basis(), jp + Vector3(0, -0.02, -0.05)), JAW)

	# --- Wings: arm and finger bones, membrane between them.
	for s: float in [-1.0, 1.0]:
		var ws := WING_L if s < 0.0 else WING_R
		var sh := r.rest[ws]
		var el := r.rest[ws + 1]
		var wr := r.rest[ws + 2]
		var tips := [Vector3(s * 0.8, 1.43, 0.1), Vector3(s * 0.76, 1.12, 0.17), Vector3(s * 0.56, 0.95, 0.21)]
		r.slot(S_SKIN).limb(PackedVector3Array([sh, el, wr]), [ws, ws + 1], [[0.0, 0.022, 0.022], [0.45, 0.016, 0.016], [0.55, 0.018, 0.018], [1.0, 0.014, 0.014]],
			14, 7, Vector3.BACK, 0.03, {CHEST: 1.0}, 0.04)
		for f in 3:
			var tipf: Vector3 = tips[f]
			r.slot(S_SKIN).limb(PackedVector3Array([wr, wr.lerp(tipf, 0.5) + Vector3(0, 0.015, 0), tipf]), [ws + 3 + f, ws + 3 + f], [[0.0, 0.011, 0.011], [0.5, 0.007, 0.007], [1.0, 0.003, 0.003]], 10, 6, Vector3.BACK, 0.02)
		r.slot(S_HORN).rigid(OrganicMesh.bezier("imp_wclaw", Vector3.ZERO, Vector3(s * 0.01, 0.02, -0.01), Vector3(s * 0.0, 0.04, -0.015), 0.006, 0.001, 4, 5), Transform3D(Basis(), wr + Vector3(0, 0.01, -0.005)), ws + 2)
		var spars: Array = []
		for f in 3:
			var tipf: Vector3 = tips[f]
			spars.append([[wr, {ws + 2: 1.0}], [wr.lerp(tipf, 0.5) + Vector3(0, 0.015, 0), {ws + 3 + f: 1.0}], [tipf, {ws + 3 + f: 1.0}]])
		var body := [[sh + Vector3(-s * 0.01, -0.02, 0.0), {CHEST: 1.0}], [Vector3(s * 0.075, 1.08, 0.065), {SPINE: 1.0}], [Vector3(s * 0.07, 0.94, 0.05), {HIPS: 1.0}]]
		var arm := [[sh, {ws: 1.0}], [el, {ws + 1: 1.0}], [wr, {ws + 2: 1.0}]]
		var chord := [[sh, {ws: 1.0}], [wr, {ws + 2: 1.0}]]
		r.slot(S_WING)
		WingKit.panel(r, spars[0], spars[1], 8, 5, 0.004, Vector3.BACK, 0.22, 0.012)
		WingKit.panel(r, spars[1], spars[2], 8, 5, 0.004, Vector3.BACK, 0.22, 0.012)
		WingKit.panel(r, spars[2], body, 8, 6, 0.004, Vector3.BACK, 0.18, 0.015)
		WingKit.panel(r, arm, chord, 6, 2, 0.004, Vector3.BACK, 0.0, 0.0)
	return r.build(key)


# --- Animation ------------------------------------------------------------------------------

func _animate(delta: float) -> void:
	if skel == null:
		return
	var p := action_progress()
	var w := action_weight(0.1, 0.2)
	var act := _action if p >= 0.0 and not _dead else ""
	var t := _time
	var rate := 3.6 + clampf(move_speed * 0.15, 0.0, 0.8)
	var die := 0.0
	if _dead:
		die = clampf(_dead_t / 0.7, 0.0, 1.0)
		rate *= 1.0 - die
	_flap += delta * TAU * rate
	var stroke := sin(_flap)          # +1 wings high, -1 low
	var down := -cos(_flap)           # > 0 while beating down
	var fold := smoothstep(0.0, 1.0, maxf(0.0, -down)) * 0.8

	var throw := 0.0
	var flinch := 0.0
	var jaw := 0.12 + maxf(0.0, sin(t * 1.7)) * 0.08
	var fire := false
	match act:
		"throw", "attack", "cast", "shoot", "attack2":
			throw = keys(p, [[0, 0], [0.45, -1.0], [0.58, 1.0], [0.8, 0.6], [1, 0]])
			jaw = lerpf(jaw, 0.6, w)
			fire = p < 0.56
		"hit":
			flinch = sin(PI * clampf(p * 1.3, 0.0, 1.0))
			jaw = lerpf(jaw, 0.5, flinch)
		"roar", "summon", "lunge":
			jaw = lerpf(jaw, 0.8, w)
	_throw = damp(_throw, throw, 14.0, delta)
	_flinch = damp(_flinch, flinch, 16.0, delta)
	_jaw_open = damp(_jaw_open, jaw, 14.0, delta)
	hand_fire.visible = fire
	if _fire_fx != null:
		_fire_fx.emitting = fire

	# --- Body: lifts on each downstroke, leans into flight.
	var lean := clampf(move_speed * 0.07, 0.0, 0.45)
	var y := 0.0 - stroke * 0.035 + sin(t * 1.3) * 0.03
	if _dead:
		_fall_y = minf(_fall_y + delta * (2.0 + _dead_t * 9.0), 0.78)
		y = -_fall_y
	var hips_b := Basis.from_euler(Vector3(-lean + _flinch * 0.4 + die * 1.35, _throw * 0.15, sin(t * 1.1) * 0.06 + die * 0.4))
	place(HIPS, rest[HIPS] + Vector3(0, y, _flinch * 0.12), hips_b)
	fk(SPINE, Vector3(stroke * 0.04 + _throw * -0.08, _throw * 0.2, 0))
	fk(CHEST, Vector3(stroke * 0.05 - _throw * 0.12 + _flinch * 0.2, _throw * 0.3, 0))
	fk(NECK, Vector3(lean * 0.5 - stroke * 0.05, sin(t * 0.7) * 0.3 * (1.0 - absf(_throw)), 0))
	fk(HEAD, Vector3(lean * 0.4 + _flinch * 0.5 - _throw * 0.1, sin(t * 0.7 + 0.5) * 0.2, sin(t * 0.9) * 0.1))
	fk(JAW, Vector3(_jaw_open * 0.7, 0, 0))

	# --- Wings.
	for s: float in [-1.0, 1.0]:
		var ws := WING_L if s < 0.0 else WING_R
		var up_ang := 0.15 + stroke * 0.85
		var sweep := down * 0.25 - lean * 0.2
		if _dead:
			up_ang = lerpf(up_ang, -0.9, die)
			sweep = lerpf(sweep, 0.9, die)
			fold = lerpf(fold, 1.0, die)
		up_ang += _flinch * 0.6
		fk(ws, Vector3(0, s * sweep, s * up_ang))
		fk(ws + 1, Vector3(0, -s * fold * 0.7, -s * (0.1 + fold * 0.9)))
		fk(ws + 2, Vector3(0, -s * fold * 0.9, -s * fold * 0.4))
		for f in 3:
			fk(ws + 3 + f, Vector3(0, -s * fold * (0.2 + f * 0.35) * 0.9, 0))

	# --- Arms: claws ready; the right hand winds a fireball up and hurls it.
	for s: float in [-1.0, 1.0]:
		var up := ARM_L if s < 0.0 else ARM_R
		fk(up)
		var tgt := Vector3(s * 0.2, 1.02, -0.1) + Vector3(0, sin(t * 2.0 + s) * 0.02, 0)
		if s > 0.0:
			if _throw < 0.0:
				tgt = tgt.lerp(Vector3(0.22, 1.42, 0.15), -_throw)
			else:
				tgt = tgt.lerp(Vector3(0.1, 1.25, -0.42), _throw)
		else:
			tgt = tgt.lerp(Vector3(-0.22, 1.18, -0.2), absf(_throw) * 0.6)
		tgt += Vector3(s * 0.12, 0.15, 0.05) * _flinch
		if _dead:
			tgt = tgt.lerp(Vector3(s * 0.3, 0.95, 0.05), die)
		var tm := gb[HIPS] * (tgt - rest[HIPS]) + gp[HIPS]
		ik(up, up + 1, up + 2, tm, gb[HIPS] * Vector3(s * 0.6, -0.2, 1.0))
		aim(up + 2, up + 3, (gp[up + 2] - gp[up + 1]).normalized(), Vector3(-s, 0, 0), gb[HIPS] * Vector3(-s, 0, 0))
		var curl := 0.5 + sin(t * 1.4 + s) * 0.15 - (0.6 if (s > 0.0 and absf(_throw) > 0.3) else 0.0)
		fk(up + 3, Vector3(0, 0, -s * curl))

	# --- Legs dangle and kick a little.
	for s: float in [-1.0, 1.0]:
		var th := LEG_L if s < 0.0 else LEG_R
		var kick := sin(t * 2.4 + s * 1.2) * 0.12 + stroke * 0.06
		fk(th, Vector3(0.35 + kick + lean * 0.6 - die * 0.6, 0, s * 0.08))
		fk(th + 1, Vector3(-0.55 - kick * 0.6, 0, 0))
		fk(th + 2, Vector3(0.5 + kick * 0.4, 0, 0))
		fk(th + 3, Vector3(0.35 + sin(t * 3.0 + s) * 0.15, 0, 0))

	# --- Tail: a lazy S that whips with the throw.
	for i in TAIL_N:
		var f := float(i) / (TAIL_N - 1)
		var sw := sin(t * 2.2 - f * 2.4) * (0.22 + f * 0.15) + _throw * 0.3 * f
		fk(TAIL + i, Vector3(-0.08 + sin(t * 1.6 - f * 2.0) * 0.12 - die * 0.15, sw, 0))
	commit()
