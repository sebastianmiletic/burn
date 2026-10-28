class_name FlyerModel
extends MobModel
## A single winged creature on one skinned body (MobRig):
##   "bat": a giant cave bat - shaggy body, big cupped ears, a leaf nose,
##          fangs and small burning eyes; leathery wings of membrane stretched
##          over the arm, four long finger bones and the legs, a tail
##          membrane between the hind feet; a thumb claw at each wrist
##   bird:  the same rig with feathered panels, a beak and a tail fan
## The wing beat folds the hand in on the upstroke and spreads it on the
## downstroke (the body lifts with each beat). `attack` / `bite` dives with
## the jaw open, `hit` flinches, death crumples the wings. Faces -Z.

const BODY := 0
const CHEST := 1
const HEAD := 2
const JAW := 3
const WING_L := 4   # shoulder, elbow, wrist, fingers 1..4
const WING_R := 11
const LEG_L := 18   # hip, knee, foot
const LEG_R := 21
const TAIL := 24    # 2 bones

const S_FUR := 0
const S_WING := 1
const S_HORN := 2
const S_EYE := 3
const S_DARK := 4

const TIPS := [Vector3(0.58, 0.045, -0.05), Vector3(0.6, 0.03, 0.08), Vector3(0.5, 0.02, 0.2), Vector3(0.33, 0.01, 0.25)]

var species := "bat"
var size := 1.0
## Birds at rest (a pet raven on the ground): wings folded, no beat.
var perched := false
var _perch := 0.0

var _flap := 0.0
var _dive := 0.0
var _flinch := 0.0
var _jaw_open := 0.0


func _init(kind_name := "bat", variant_seed := 0) -> void:
	species = kind_name
	var rng := RandomNumberGenerator.new()
	rng.seed = variant_seed
	size = rng.randf_range(0.85, 1.15) * (1.0 if species == "bat" else (0.8 if species == "phoenix" else 0.5))
	_flap = rng.randf() * TAU
	dissolve_delay = 0.8


func _ember_extents() -> Vector3:
	return Vector3(0.4, 0.2, 0.3) * size


func _lod_size() -> float:
	return 1.2


# --- Build -------------------------------------------------------------------------------

func _build() -> void:
	var bat := species == "bat"
	var mats: Array = []
	if bat:
		mats = [CreatureSkin.fur(Color(0.17, 0.13, 0.11), Color(0.28, 0.21, 0.17), {"use_rest": true, "pattern_scale": 90.0, "bump": 1.0, "rim": 0.55,
				"bump_distance": 10.0}),
			CreatureSkin.membrane(Color(0.17, 0.1, 0.09), {"use_rest": true, "backlight": 1.5, "pattern_scale": 8.0, "rim": 0.4, "bump": 0.2}),
			CreatureSkin.keratin(Color(0.85, 0.8, 0.7), {"use_rest": true}),
			CreatureSkin.eye(Color(1.0, 0.25, 0.1), 3.5, 0.1),
			CreatureSkin.hide(Color(0.12, 0.08, 0.08), Color(0.2, 0.12, 0.12), {"use_rest": true, "pattern_scale": 60.0, "roughness": 0.45, "wet": 0.3})]
	elif species == "phoenix":
		mats = [CreatureSkin.feathers(Color(0.85, 0.22, 0.05), Color(1.0, 0.7, 0.15), {"use_rest": true, "pattern_scale": 60.0}),
			CreatureSkin.feathers(Color(1.0, 0.55, 0.08), Color(1.0, 0.85, 0.3), {"use_rest": true, "pattern_scale": 30.0}),
			CreatureSkin.keratin(Color(0.95, 0.8, 0.35), {"use_rest": true}),
			CreatureSkin.eye(Color(1.0, 0.9, 0.4), 2.5, 0.0),
			CreatureSkin.hide(Color(0.4, 0.12, 0.05), Color(0.5, 0.2, 0.05), {"use_rest": true})]
	else:
		mats = [CreatureSkin.feathers(Color(0.15, 0.14, 0.14), Color(0.3, 0.28, 0.26), {"use_rest": true, "pattern_scale": 60.0}),
			CreatureSkin.feathers(Color(0.12, 0.11, 0.11), Color(0.2, 0.19, 0.18), {"use_rest": true, "pattern_scale": 30.0}),
			CreatureSkin.keratin(Color(0.3, 0.26, 0.16), {"use_rest": true}),
			CreatureSkin.eye(Color(1.0, 0.8, 0.3), 1.0, 0.0),
			CreatureSkin.hide(Color(0.1, 0.09, 0.08), Color(0.1, 0.09, 0.08), {"use_rest": true})]
	rig_instance(_rig_data(bat), mats, size, 1.4)


func _rig_data(bat: bool) -> Dictionary:
	var key := "mob_flyer_" + species
	if MobRig.has(key):
		return MobRig.cached(key)
	var r := MobRig.new(5)
	r.bone("body", -1, Vector3(0, 0, 0.02))
	r.bone("chest", BODY, Vector3(0, 0.005, -0.06))
	r.bone("head", CHEST, Vector3(0, 0.02, -0.13))
	r.bone("jaw", HEAD, Vector3(0, 0.0, -0.155))
	for s: float in [-1.0, 1.0]:
		var sd := "l" if s < 0.0 else "r"
		var sh := r.bone("w_sh_" + sd, CHEST, Vector3(s * 0.04, 0.02, -0.07))
		r.bone("w_el_" + sd, sh, Vector3(s * 0.16, 0.035, -0.03))
		r.bone("w_wr_" + sd, sh + 1, Vector3(s * 0.3, 0.03, -0.07))
		for f in 4:
			r.bone("w_f%d_" % f + sd, sh + 2, Vector3(s * 0.3, 0.03, -0.07))
	for s: float in [-1.0, 1.0]:
		var sd := "l" if s < 0.0 else "r"
		var hip := r.bone("hip_" + sd, BODY, Vector3(s * 0.035, -0.01, 0.08))
		r.bone("knee_" + sd, hip, Vector3(s * 0.06, -0.02, 0.13))
		r.bone("foot_" + sd, hip + 1, Vector3(s * 0.055, -0.03, 0.17))
	r.bone("tail0", BODY, Vector3(0, -0.005, 0.1))
	r.bone("tail1", TAIL, Vector3(0, -0.01, 0.17))

	# Body: a stout furry barrel, short neck.
	var rows := [[0.13, 0.025, 0.022, -0.005], [0.1, 0.045, 0.04, 0.0], [0.04, 0.058, 0.05, 0.0], [-0.03, 0.058, 0.05, 0.004],
		[-0.08, 0.046, 0.043, 0.01], [-0.115, 0.036, 0.036, 0.016]]
	var path := PackedVector3Array()
	var radii := PackedVector2Array()
	var pb: Array = []
	for row: Array in rows:
		var z := float(row[0])
		path.append(Vector3(0, float(row[3]), z))
		radii.append(Vector2(float(row[1]), float(row[2])))
		pb.append(BODY if z > 0.0 else (CHEST if z > -0.1 else HEAD))
	var rs := MobRig.resample(path, radii, pb, 16)
	r.slot(S_FUR).tube(rs[0], rs[1], rs[2], 0.04, 14, Vector3.UP)
	if bat:
		r.tufts(MobRig.tuft_mesh("bat", 0.22, 0.2), 70, 0.0, 1.0, -180.0, 180.0, 0.022, 0.8, 5, 1.2)
	# Head.
	var hp := r.rest[HEAD]
	if bat:
		r.slot(S_FUR).rigid(OrganicMesh.profile("bat_skull", Vector3(0, 0.005, 0.03), Vector3(0, -0.012, -0.05),
			[[0.0, 0.03, 0.03], [0.3, 0.037, 0.034, 0.004], [0.6, 0.03, 0.026], [0.85, 0.02, 0.018, -0.004], [1.0, 0.012, 0.011, -0.004]], 12, 10), Transform3D(Basis(), hp), HEAD)
		for s: float in [-1.0, 1.0]:
			# Huge cupped ears.
			var ear := OrganicMesh.profile("bat_ear", Vector3.ZERO, Vector3(0, 0.085, 0), [[0.0, 0.016, 0.01], [0.3, 0.03, 0.008, 0.012], [0.7, 0.024, 0.006, 0.01], [1.0, 0.0, 0.0, 0.004]], 8, 6, Vector3.BACK)
			r.slot(S_WING).rigid(ear, Transform3D(Basis.from_euler(Vector3(0.25, s * 0.5, -s * 0.45)), hp + Vector3(s * 0.022, 0.022, 0.005)), HEAD)
			r.slot(S_EYE).rigid(ModelKit.sphere(0.006, 6), Transform3D(Basis(), hp + Vector3(s * 0.017, 0.008, -0.03)), HEAD)
			r.slot(S_HORN).rigid(OrganicMesh.bezier("bat_fang", Vector3.ZERO, Vector3(0, -0.008, 0), Vector3(0, -0.015, 0.002), 0.0035, 0.0006, 3, 5), Transform3D(Basis(), hp + Vector3(s * 0.008, -0.02, -0.052)), HEAD)
		# Leaf nose and nostrils.
		r.slot(S_DARK).rigid(OrganicMesh.blob("bat_snout", Vector3(0.014, 0.011, 0.01), 0.1, 5, 8), Transform3D(Basis(), hp + Vector3(0, -0.006, -0.055)), HEAD)
		var leaf := OrganicMesh.membrane("bat_leaf", PackedVector2Array([Vector2(-0.009, 0), Vector2(0.009, 0), Vector2(0.004, 0.018), Vector2(0, 0.024), Vector2(-0.004, 0.018)]), 0.003, 0.003)
		r.slot(S_DARK).rigid(leaf, Transform3D(Basis(Vector3.RIGHT, -0.35), hp + Vector3(0, 0.002, -0.058)), HEAD)
		r.slot(S_DARK).rigid(OrganicMesh.profile("bat_jaw", Vector3(0, 0, 0.0), Vector3(0, -0.004, -0.04), [[0.0, 0.016, 0.008], [1.0, 0.008, 0.005]], 8, 5), Transform3D(Basis(), r.rest[JAW]), JAW)
		for s: float in [-1.0, 1.0]:
			r.slot(S_HORN).rigid(OrganicMesh.bezier("bat_lfang", Vector3.ZERO, Vector3(0, 0.006, 0), Vector3(0, 0.011, 0.0), 0.003, 0.0006, 3, 5), Transform3D(Basis(), r.rest[JAW] + Vector3(s * 0.007, 0.002, -0.034)), JAW)
	else:
		r.slot(S_FUR).rigid(OrganicMesh.blob("bird_head", Vector3(0.03, 0.03, 0.034), 0.05, 3, 10), Transform3D(Basis(), hp), HEAD)
		r.slot(S_HORN).rigid(OrganicMesh.bezier("bird_beak", Vector3.ZERO, Vector3(0, -0.004, -0.03), Vector3(0, -0.012, -0.055), 0.012, 0.001, 5, 6), Transform3D(Basis(), hp + Vector3(0, -0.004, -0.025)), HEAD)
		for s: float in [-1.0, 1.0]:
			r.slot(S_EYE).rigid(ModelKit.sphere(0.006, 6), Transform3D(Basis(), hp + Vector3(s * 0.022, 0.008, -0.012)), HEAD)
	# Wings.
	for s: float in [-1.0, 1.0]:
		var ws := WING_L if s < 0.0 else WING_R
		var sh := r.rest[ws]
		var el := r.rest[ws + 1]
		var wr := r.rest[ws + 2]
		var tips: Array = []
		for t: Vector3 in TIPS:
			tips.append(Vector3(t.x * s, t.y, t.z))
		r.slot(S_WING if bat else S_FUR).limb(PackedVector3Array([sh, el, wr]), [ws, ws + 1], [[0.0, 0.014, 0.014], [0.45, 0.009, 0.009], [0.55, 0.01, 0.01], [1.0, 0.008, 0.008]],
			12, 6, Vector3.UP, 0.02, {CHEST: 1.0}, 0.03)
		var spars: Array = []
		for f in 4:
			var tipf: Vector3 = tips[f]
			var mid := wr.lerp(tipf, 0.5) + Vector3(0, 0.012, 0)
			if bat:
				r.slot(S_WING).limb(PackedVector3Array([wr, mid, tipf]), [ws + 3 + f, ws + 3 + f], [[0.0, 0.006, 0.006], [0.5, 0.0045, 0.0045], [1.0, 0.002, 0.002]], 8, 5, Vector3.UP, 0.02)
			spars.append([[wr, {ws + 2: 1.0}], [mid, {ws + 3 + f: 1.0}], [tipf, {ws + 3 + f: 1.0}]])
		r.slot(S_HORN).rigid(OrganicMesh.bezier("bat_thumb", Vector3.ZERO, Vector3(s * 0.004, 0.006, -0.012), Vector3(0, 0.0, -0.022), 0.004, 0.0006, 4, 5), Transform3D(Basis(), wr + Vector3(0, 0.005, -0.004)), ws + 2)
		var lg := LEG_L if s < 0.0 else LEG_R
		var body := [[Vector3(s * 0.04, 0.0, -0.05), {CHEST: 1.0}], [Vector3(s * 0.045, -0.005, 0.06), {BODY: 1.0}], [r.rest[lg + 2], {lg + 2: 1.0}]]
		var arm := [[sh, {ws: 1.0}], [el, {ws + 1: 1.0}], [wr, {ws + 2: 1.0}]]
		var chord := [[sh, {ws: 1.0}], [wr, {ws + 2: 1.0}]]
		r.slot(S_WING)
		var sc := 0.22 if bat else 0.05
		WingKit.panel(r, arm, chord, 5, 2, 0.003, Vector3.UP, 0.0, 0.0)
		WingKit.panel(r, spars[0], spars[1], 7, 4, 0.003, Vector3.UP, sc, 0.01)
		WingKit.panel(r, spars[1], spars[2], 7, 4, 0.003, Vector3.UP, sc, 0.01)
		WingKit.panel(r, spars[2], spars[3], 7, 4, 0.003, Vector3.UP, sc, 0.01)
		WingKit.panel(r, spars[3], body, 7, 5, 0.003, Vector3.UP, sc * 0.8, 0.012)
		# Hind legs with hooked toes; tail membrane between them.
		r.slot(S_DARK).limb(PackedVector3Array([r.rest[lg], r.rest[lg + 1], r.rest[lg + 2]]), [lg, lg + 1], [[0.0, 0.011, 0.011], [0.5, 0.007, 0.007], [1.0, 0.006, 0.006]], 8, 6, Vector3.UP, 0.02, {BODY: 1.0}, 0.02)
		for c in 3:
			r.slot(S_HORN).rigid(OrganicMesh.bezier("bat_toe", Vector3.ZERO, Vector3(0, -0.004, 0.008), Vector3(0, -0.008, 0.004), 0.002, 0.0005, 3, 4), Transform3D(Basis(), r.rest[lg + 2] + Vector3((float(c) - 1.0) * 0.004, 0, 0.003)), lg + 2)
		if bat:
			var leg := [[r.rest[lg], {lg: 1.0}], [r.rest[lg + 1], {lg + 1: 1.0}], [r.rest[lg + 2], {lg + 2: 1.0}]]
			var tail := [[r.rest[TAIL], {TAIL: 1.0}], [Vector3(0, -0.01, 0.15), {TAIL + 1: 1.0}], [Vector3(0, -0.012, 0.21), {TAIL + 1: 1.0}]]
			r.slot(S_WING)
			WingKit.panel(r, leg, tail, 4, 3, 0.003, Vector3.UP, 0.15, 0.0)
	if not bat:
		var fan := OrganicMesh.membrane("bird_tail", PackedVector2Array([Vector2(-0.025, 0), Vector2(0.025, 0), Vector2(0.05, 0.11), Vector2(0, 0.1), Vector2(-0.05, 0.11)]), 0.0, 0.004)
		r.slot(S_WING).rigid(fan, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.0, 0.1)), TAIL)
	return r.build(key)


# --- Animation ------------------------------------------------------------------------------

func _animate(delta: float) -> void:
	if skel == null:
		return
	var bat := species == "bat"
	var p := action_progress()
	var w := action_weight()
	var act := _action if p >= 0.0 and not _dead else ""
	var t := _time
	var rate := (8.5 if bat else 6.0)
	var die := 0.0
	if _dead:
		die = clampf(_dead_t / 0.5, 0.0, 1.0)
		rate *= 1.0 - die
	_perch = damp(_perch, 1.0 if perched and not _dead else 0.0, 6.0, delta)
	rate *= 1.0 - _perch
	_flap += delta * TAU * rate
	var stroke := sin(_flap) * (1.0 - _perch)
	var down := -cos(_flap)
	var fold := lerpf(smoothstep(0.0, 1.0, maxf(0.0, -down)) * (0.9 if bat else 0.4), 1.0, _perch)
	var dive := 0.0
	var flinch := 0.0
	var jaw := 0.05
	match act:
		"attack", "bite", "lunge", "drain", "attack2":
			dive = keys(p, [[0, 0], [0.4, -0.5], [0.6, 1.0], [1, 0]])
			jaw = keys(p, [[0, 0.05], [0.35, 0.9], [0.6, 0.9], [0.7, 0.0], [1, 0.05]])
		"hit":
			flinch = sin(PI * clampf(p * 1.3, 0.0, 1.0))
			jaw = 0.5 * flinch
		"roar", "howl":
			jaw = 0.9 * w
	_dive = damp(_dive, dive * w, 14.0, delta)
	_flinch = damp(_flinch, flinch, 16.0, delta)
	_jaw_open = damp(_jaw_open, jaw, 18.0, delta)

	var lean := clampf(move_speed * 0.04, 0.0, 0.4)
	var body_b := Basis.from_euler(Vector3(-0.1 - lean - _dive * 0.5 + _flinch * 0.5 + die * 1.2, sin(t * 3.0) * 0.1, sin(t * 2.3) * 0.15 + die * 0.8))
	place(BODY, rest[BODY] + Vector3(0, -stroke * 0.035 - die * 0.05, -_dive * 0.08), body_b)
	fk(CHEST, Vector3(stroke * 0.05, 0, 0))
	fk(HEAD, Vector3(sin(t * 4.0) * 0.12 + _dive * 0.3, sin(t * 2.7) * 0.3, 0))
	fk(JAW, Vector3(_jaw_open * 0.8, 0, 0))
	for s: float in [-1.0, 1.0]:
		var ws := WING_L if s < 0.0 else WING_R
		var up_ang := 0.1 + stroke * 0.95
		var sweep := down * 0.2
		var f := fold
		if _dead:
			up_ang = lerpf(up_ang, -1.1, die)
			f = lerpf(f, 1.0, die)
		up_ang += _flinch * 0.7
		fk(ws, Vector3(0, -s * sweep, s * up_ang))
		fk(ws + 1, Vector3(0, -s * f * 0.9, -s * f * 0.5))
		fk(ws + 2, Vector3(0, -s * f * 1.0, -s * f * 0.3))
		for fi in 4:
			fk(ws + 3 + fi, Vector3(0, -s * f * (0.15 + fi * 0.32) + s * (1.0 - f) * (0.06 - fi * 0.04), 0))
	for s: float in [-1.0, 1.0]:
		var lg := LEG_L if s < 0.0 else LEG_R
		fk(lg, Vector3(0.2 + stroke * 0.1, 0, s * 0.1))
		fk(lg + 1, Vector3(-0.2, 0, 0))
		fk(lg + 2, Vector3(0.3, 0, 0))
	fk(TAIL, Vector3(0.1 + stroke * 0.1, 0, 0))
	fk(TAIL + 1, Vector3(0.15, 0, 0))
	commit()
