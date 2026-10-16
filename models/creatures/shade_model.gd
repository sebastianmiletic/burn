class_name ShadeModel
extends MobModel
## A shade of the underworld: a hooded wraith of grave-cloth drifting a hand
## above the ground. One skinned body (MobRig, ~30 bones):
##   * a deep cowl over a black void, with a skull half seen inside it and
##     two soft, cold eyes; a lower jaw that gapes when it feeds
##   * a long robe with vertical folds hanging from a ring of skirt bones,
##     going thin and translucent towards a ragged hem that tears into
##     tongues and fades into mist (shade_veil.gdshader), a shoulder mantle,
##     bell sleeves
##   * gaunt grey forearms and long-fingered skeletal hands with dark nails
## Motion: hovering bob, leaning into its drift, the skirt trailing and
## rippling, searching head, curling fingers; `drain` reaches out with both
## hands splayed and the jaw open, `attack` / `lunge` rakes, `hit` recoils,
## death rises, spreads its arms and melts into wisps. Faces -Z.

const ROOT := 0
const SPINE := 1
const CHEST := 2
const NECK := 3
const HEAD := 4
const JAW := 5
const ARM_L := 6   # up, lo, hand, fingers (+0..3)
const ARM_R := 10
const SKIRT := 14  # pairs (upper, lower) per strip
const STRIPS := 8

const S_VEIL := 0
const S_BONE := 1
const S_VOID := 2
const S_EYE := 3
const S_SKULL := 4

var _wisps_fx: GPUParticles3D
var _reach := 0.0
var _rake := 0.0
var _recoil := 0.0
var _jaw_open := 0.0
var _eye := 1.0
var _drift := Vector3.ZERO
var _prev := Vector3.INF
var _vel := Vector3.ZERO


func _init() -> void:
	dissolve_delay = 0.9
	dissolve_time = 1.4
	durations["drain"] = 1.0


func _ember_extents() -> Vector3:
	return Vector3(0.3, 0.8, 0.3)


func _lod_size() -> float:
	return 2.6


# --- Build -------------------------------------------------------------------------------

func _build() -> void:
	var veil := ShaderMaterial.new()
	veil.shader = preload("res://models/creatures/shade_veil.gdshader")
	veil.set_shader_parameter(&"albedo", Color(0.03, 0.033, 0.042))
	veil.set_shader_parameter(&"albedo2", Color(0.11, 0.125, 0.15))
	veil.set_shader_parameter(&"rim_energy", 0.4)
	var bone := CreatureSkin.smooth(Color(0.46, 0.48, 0.47), Color(0.3, 0.32, 0.33), {"use_rest": true, "pattern": CreatureSkin.Pattern.HIDE,
		"pattern_scale": 70.0, "bump": 0.5, "roughness": 0.7, "rim": 0.35, "specular_amount": 0.25, "bump_distance": 12.0})
	var void_mat := CreatureSkin.smooth(Color(0.005, 0.006, 0.01), Color(0.0, 0.0, 0.0), {"use_rest": true, "rim": 0.0,
		"roughness": 1.0, "specular_amount": 0.0, "bump": 0.0})
	var eye := ModelKit.glow(Color(0.55, 0.88, 1.0), 9.0, 0.15)
	var skull := CreatureSkin.keratin(Color(0.17, 0.165, 0.16), {"use_rest": true, "pattern_scale": 60.0, "roughness": 0.7, "rim": 0.0,
		"specular_amount": 0.15, "belly": Color(0.08, 0.08, 0.08), "belly_mix": 0.9})
	rig_instance(_rig_data(), [veil, bone, void_mat, eye, skull], 1.0, 1.0)
	# A shade throws no shadow.
	body_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var at := follow(ROOT, "Mist")
	_wisps_fx = BossKit.emitter(at, "smoke", 18, Vector3(0.3, 0.1, 0.3), Color(0.14, 0.2, 0.27), 0.7, 2.2, 0.18)
	_wisps_fx.position = Vector3(0, -0.72, 0.05)


func _rig_data() -> Dictionary:
	var key := "mob_shade"
	if MobRig.has(key):
		return MobRig.cached(key)
	var r := MobRig.new(5)
	r.bone("root", -1, Vector3(0, 1.0, 0))
	r.bone("spine", ROOT, Vector3(0, 1.3, 0.01))
	r.bone("chest", SPINE, Vector3(0, 1.55, 0.02))
	r.bone("neck", CHEST, Vector3(0, 1.74, 0.0))
	r.bone("head", NECK, Vector3(0, 1.86, -0.02))
	r.bone("jaw", HEAD, Vector3(0, 1.827, -0.058))
	for s: float in [-1.0, 1.0]:
		var sd := "l" if s < 0.0 else "r"
		var up := r.bone("arm_up_" + sd, CHEST, Vector3(s * 0.2, 1.6, 0.02))
		r.bone("arm_lo_" + sd, up, Vector3(s * 0.27, 1.3, 0.0))
		r.bone("hand_" + sd, up + 1, Vector3(s * 0.3, 1.04, -0.08))
		r.bone("fingers_" + sd, up + 2, Vector3(s * 0.31, 0.95, -0.11))
	for i in STRIPS:
		var d := _strip_dir(i)
		var a := r.bone("skirt_a%d" % i, ROOT, d * 0.24 + Vector3(0, 0.78, 0.05))
		r.bone("skirt_b%d" % i, a, d * 0.33 + Vector3(0, 0.42, 0.08))

	# --- Robe: a hanging grid of cloth with folds, from the neck to the hem.
	var rows_spec := [[1.79, 0.07, 0.07, 0.02], [1.7, 0.13, 0.11, 0.02], [1.62, 0.235, 0.14, 0.02], [1.5, 0.225, 0.15, 0.02],
		[1.35, 0.2, 0.145, 0.02], [1.2, 0.19, 0.14, 0.03], [1.05, 0.21, 0.165, 0.04], [0.9, 0.245, 0.2, 0.05], [0.75, 0.28, 0.235, 0.06],
		[0.6, 0.315, 0.265, 0.07], [0.45, 0.345, 0.29, 0.08], [0.3, 0.37, 0.31, 0.1], [0.15, 0.39, 0.33, 0.12], [0.02, 0.4, 0.34, 0.14]]
	var rows := 30
	var cols := 32
	var pts := PackedVector3Array()
	var centres := PackedVector3Array()
	for i in rows:
		var f := float(i) / (rows - 1) * (rows_spec.size() - 1)
		var i0 := clampi(int(f), 0, rows_spec.size() - 2)
		var e := f - i0
		e = e * e * (3.0 - 2.0 * e)
		var a: Array = rows_spec[i0]
		var b: Array = rows_spec[i0 + 1]
		var y := lerpf(a[0], b[0], e)
		var rx := lerpf(a[1], b[1], e)
		var rz := lerpf(a[2], b[2], e)
		var zo := lerpf(a[3], b[3], e)
		centres.append(Vector3(0, y, zo))
		var fold_amp := 0.03 + 0.1 * smoothstep(1.4, 0.1, y)
		for j in cols + 1:
			var th := TAU * float(j % cols) / cols
			var fold := sin(th * 7.0 + y * 1.5) * 0.6 + sin(th * 11.0 - y * 2.3) * 0.4
			var k := 1.0 + fold * fold_amp
			pts.append(Vector3(sin(th) * rx * k, y, zo - cos(th) * rz * k))
	r.slot(S_VEIL)
	WingKit.grid(r, pts, rows, cols, _robe_weights, centres)
	# Shoulder mantle over the robe.
	var mantle := BossKit.shell("shade_mantle", Vector3(0.265, 0.22, 0.19), 0.0, 360.0, 35.0, 100.0, 0.02, 20, 6)
	r.rigid(mantle, Transform3D(Basis(), Vector3(0, 1.6, 0.02)), CHEST)
	# Hood: a deep cowl open at the front, with a point hanging behind.
	var hood := BossKit.shell("shade_hood", Vector3(0.165, 0.2, 0.19), 42.0, 318.0, 0.0, 128.0, 0.022, 18, 10)
	r.rigid(hood, Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(0, 1.88, 0.0)), HEAD)
	r.rigid(OrganicMesh.bezier("shade_hood_tail", Vector3.ZERO, Vector3(0, -0.05, 0.12), Vector3(0, -0.2, 0.2), 0.07, 0.01, 6, 8, 0.5), Transform3D(Basis(), Vector3(0, 1.98, 0.12)), HEAD)
	# Sleeves: bell sleeves from the shoulders, open at the cuff.
	for s: float in [-1.0, 1.0]:
		var up := ARM_L if s < 0.0 else ARM_R
		var j := PackedVector3Array([Vector3(s * 0.12, 1.6, 0.02), r.rest[up], r.rest[up + 1], r.rest[up + 2] + Vector3(s * 0.01, 0.05, 0.02)])
		r.slot(S_VEIL).limb(j, [CHEST, up, up + 1], [[0.0, 0.065, 0.065], [0.3, 0.066, 0.064], [0.62, 0.06, 0.058], [0.85, 0.078, 0.072], [1.0, 0.11, 0.1]],
			20, 14, Vector3.BACK, 0.08, {CHEST: 1.0}, 0.12, false)
		_build_arm(r, s, up)

	# --- Inside the hood: the void, a skull half seen, two cold eyes.
	var hp := Vector3(0, 1.86, -0.02)
	r.slot(S_VOID).rigid(OrganicMesh.blob("shade_void", Vector3(0.135, 0.16, 0.1), 0.05, 3, 12), Transform3D(Basis(), hp + Vector3(0, 0.02, 0.06)), HEAD)
	hp += Vector3(0, 0.012, 0.012)
	var skull := OrganicMesh.profile("shade_skull", Vector3(0, 0.03, 0.05), Vector3(0, -0.035, -0.115),
		[[0.0, 0.05, 0.055], [0.25, 0.072, 0.08, 0.01], [0.5, 0.068, 0.07, 0.0], [0.72, 0.058, 0.05, -0.01], [0.88, 0.045, 0.036, -0.02], [1.0, 0.03, 0.025, -0.022]], 14, 12)
	r.slot(S_SKULL).rigid(skull, Transform3D(Basis().scaled(Vector3(0.8, 0.85, 0.9)), hp), HEAD)
	for s: float in [-1.0, 1.0]:
		# Cheekbones, sockets and the eyes deep inside them.
		r.slot(S_SKULL).rigid(OrganicMesh.blob("shade_cheek", Vector3(0.022, 0.016, 0.03), 0.1, 5, 8), Transform3D(Basis(), hp + Vector3(s * 0.045, -0.03, -0.075)), HEAD)
		r.slot(S_VOID).rigid(OrganicMesh.blob("shade_socket", Vector3(0.02, 0.018, 0.014), 0.05, 7, 10), Transform3D(Basis(), hp + Vector3(s * 0.025, -0.002, -0.094)), HEAD)
		r.slot(S_EYE).rigid(ModelKit.sphere(0.0095, 8), Transform3D(Basis().scaled(Vector3(1.2, 0.8, 1.0)), hp + Vector3(s * 0.025, -0.004, -0.106)), HEAD)
	r.slot(S_VOID).rigid(OrganicMesh.blob("shade_nose", Vector3(0.01, 0.014, 0.01), 0.05, 9, 6), Transform3D(Basis(), hp + Vector3(0, -0.03, -0.112)), HEAD)
	# Upper teeth and a hanging lower jaw.
	for t in 6:
		var x := (float(t) - 2.5) * 0.011
		r.slot(S_SKULL).rigid(OrganicMesh.bezier("shade_tooth", Vector3.ZERO, Vector3(0, -0.006, 0), Vector3(0, -0.013, 0.0), 0.0045, 0.003, 3, 5), Transform3D(Basis(), hp + Vector3(x, -0.052, -0.106 + absf(x) * 0.4)), HEAD)
	var jp := Vector3(0, 1.815, -0.07) + Vector3(0, 0.012, 0.012)
	r.slot(S_SKULL).rigid(OrganicMesh.profile("shade_mandible", Vector3(0, 0.0, 0.03), Vector3(0, -0.02, -0.05), [[0.0, 0.045, 0.012], [0.5, 0.04, 0.014], [1.0, 0.026, 0.012]], 10, 6), Transform3D(Basis(), jp), JAW)
	for t in 6:
		var x := (float(t) - 2.5) * 0.01
		r.slot(S_SKULL).rigid(OrganicMesh.bezier("shade_ltooth", Vector3.ZERO, Vector3(0, 0.005, 0), Vector3(0, 0.011, 0.0), 0.004, 0.0028, 3, 5), Transform3D(Basis(), jp + Vector3(x, -0.008, -0.045 + absf(x) * 0.4)), JAW)
	return r.build(key)


static func _strip_dir(i: int) -> Vector3:
	var th := TAU * float(i) / STRIPS
	return Vector3(sin(th), 0, -cos(th))


## Bone weights of a robe vertex: centre-line bones above the waist, the two
## nearest skirt strips below, a little of the arm at the shoulders.
func _robe_weights(p: Vector3, _row: int, _col: int) -> Dictionary:
	var w := {}
	var y := p.y
	if y > 0.98:
		var anchors := [[1.0, ROOT], [1.3, SPINE], [1.55, CHEST], [1.78, NECK]]
		var done := false
		for i in anchors.size() - 1:
			var a: Array = anchors[i]
			var b: Array = anchors[i + 1]
			if y <= float(b[0]):
				var f := clampf((y - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0)
				w[int(a[1])] = 1.0 - f
				w[int(b[1])] = float(w.get(int(b[1]), 0.0)) + f
				done = true
				break
		if not done:
			w[NECK] = 1.0
		# Shoulders ride a little on the arms.
		var ax := absf(p.x)
		var sh := smoothstep(0.12, 0.22, ax) * smoothstep(1.4, 1.55, y) * (1.0 - smoothstep(1.66, 1.74, y)) * 0.55
		if sh > 0.0:
			for k: int in w:
				w[k] = float(w[k]) * (1.0 - sh)
			w[ARM_L if p.x < 0.0 else ARM_R] = sh
		return w
	var th := fposmod(atan2(p.x, -p.z), TAU)
	var fi := th / TAU * STRIPS
	var i0 := int(floor(fi)) % STRIPS
	var i1 := (i0 + 1) % STRIPS
	var fa: float = fi - floor(fi)
	for pair: Array in [[i0, 1.0 - fa], [i1, fa]]:
		var sa := SKIRT + int(pair[0]) * 2
		var aw := float(pair[1])
		if aw <= 0.0:
			continue
		var chain := {}
		if y > 0.78:
			var f := (y - 0.78) / 0.2
			chain = {ROOT: f, sa: 1.0 - f}
		elif y > 0.42:
			var f := (y - 0.42) / 0.36
			chain = {sa: f, sa + 1: 1.0 - f}
		else:
			chain = {sa + 1: 1.0}
		for k: int in chain:
			w[k] = float(w.get(k, 0.0)) + float(chain[k]) * aw
	return w


func _build_arm(r: MobRig, s: float, up: int) -> void:
	var el := r.rest[up + 1]
	var wr := r.rest[up + 2]
	var kn := r.rest[up + 3]
	# Withered forearm inside the sleeve, bony wrist.
	r.slot(S_BONE).limb(PackedVector3Array([el, wr, kn]), [up + 1, up + 2], [[0.0, 0.03, 0.03], [0.55, 0.024, 0.022], [0.7, 0.02, 0.02], [0.8, 0.026, 0.014], [1.0, 0.03, 0.012]],
		12, 8, Vector3(-s, 0, 0), 0.03)
	var along := (kn - wr).normalized()
	var palm_n := Vector3(-s, 0, 0)
	palm_n = (palm_n - along * palm_n.dot(along)).normalized()
	var across := along.cross(palm_n).normalized()
	# Knuckles and four long fingers curling towards the palm, dark nails.
	var lens := [0.105, 0.125, 0.12, 0.095]
	for f in 4:
		var o := (float(f) - 1.5) * 0.017
		var base := kn + across * o
		var l: float = lens[f]
		var tip := base + along * l * 0.92 + palm_n * l * 0.3 + across * o * 0.3
		var mid := base + along * l * 0.62 - palm_n * l * 0.02
		var finger := OrganicMesh.bezier("shade_finger_%d" % f, Vector3.ZERO, mid - base, tip - base, 0.0085, 0.0045, 7, 6)
		r.slot(S_BONE).rigid(finger, Transform3D(Basis(), base), up + 3)
		for kk in 2:
			var kp := base.lerp(mid, 0.1 + kk * 0.75)
			r.slot(S_BONE).rigid(OrganicMesh.blob("shade_knuckle", Vector3(0.0095, 0.009, 0.0095), 0.1, 11, 6), Transform3D(Basis(), kp), up + 3)
		var nail_dir := (tip - mid).normalized()
		r.slot(S_VOID).rigid(OrganicMesh.bezier("shade_nail", Vector3.ZERO, nail_dir * 0.012, nail_dir * 0.024 + palm_n * 0.006, 0.0045, 0.0008, 4, 5), Transform3D(Basis(), tip - nail_dir * 0.004), up + 3)
	# Thumb from the side of the palm.
	var tb := wr.lerp(kn, 0.4) + across * -0.026 + palm_n * 0.01
	var thumb := OrganicMesh.bezier("shade_thumb_%d" % int(s), Vector3.ZERO, along * 0.04 + across * -0.012 + palm_n * 0.01, along * 0.075 + palm_n * 0.03, 0.009, 0.005, 6, 6)
	r.slot(S_BONE).rigid(thumb, Transform3D(Basis(), tb), up + 2)
	# Palm.
	var pb := Basis(across, along, palm_n)
	r.slot(S_BONE).rigid(OrganicMesh.blob("shade_palm", Vector3(0.033, 0.045, 0.011), 0.1, 13, 8), Transform3D(pb, wr.lerp(kn, 0.55)), up + 2, up + 3, 0.3)


# --- Animation ------------------------------------------------------------------------------

func _animate(delta: float) -> void:
	if skel == null:
		return
	var p := action_progress()
	var w := action_weight(0.12, 0.25)
	var act := _action if p >= 0.0 and not _dead else ""
	if not _prev.is_finite():
		_prev = global_position
	var v := (global_position - _prev) / maxf(delta, 0.001)
	_prev = global_position
	_vel = _vel.lerp(v, 1.0 - exp(-4.0 * delta))
	var local_v := global_transform.basis.inverse() * _vel
	local_v.y = 0.0
	var speed := maxf(move_speed, local_v.length())
	_drift = _drift.lerp(local_v.limit_length(4.0), 1.0 - exp(-3.0 * delta))
	var t := _time

	var reach := 0.0
	var rake := 0.0
	var recoil := 0.0
	var jaw := 0.08 + sin(t * 0.9) * 0.04
	var eye := 1.0 + 0.15 * sin(t * 2.3)
	match act:
		"drain":
			reach = w
			jaw = lerpf(jaw, 0.55 + sin(t * 23.0) * 0.06, w)
			eye = 1.0 + 1.6 * w
		"attack", "lunge", "attack2":
			rake = keys(p, [[0, 0], [0.35, -1.0], [0.6, 1.0], [1, 0]])
			reach = 0.35 * w
			jaw = lerpf(jaw, 0.4, w)
			eye = 1.0 + 0.8 * w
		"hit":
			recoil = sin(PI * clampf(p * 1.3, 0.0, 1.0))
			eye = 0.6
		"roar", "summon", "cast", "throw", "shoot":
			reach = 0.6 * w
			jaw = lerpf(jaw, 0.6, w)
			eye = 1.0 + w
	_reach = damp(_reach, reach, 7.0, delta)
	_rake = damp(_rake, rake, 12.0, delta)
	_recoil = damp(_recoil, recoil, 16.0, delta)
	_jaw_open = damp(_jaw_open, jaw, 10.0, delta)
	_eye = damp(_eye, eye, 8.0, delta)

	var die := 0.0
	if _dead:
		die = clampf(_dead_t / 1.2, 0.0, 1.0)
		die = die * die * (3.0 - 2.0 * die)
	# --- Core: hovers, leans into the drift, recoils.
	var bob := sin(t * 1.7) * 0.06 + sin(t * 0.63) * 0.03
	var lean := -clampf(_drift.z * -0.08, -0.15, 0.3) - 0.2 * _reach
	var root_pos := Vector3(_drift.x * -0.02, 1.0 + bob + die * 0.45, 0.18 * _recoil - 0.12 * _reach)
	var root_b := Basis.from_euler(Vector3(lean + 0.35 * _recoil - 0.25 * die, sin(t * 0.4) * 0.1 + _rake * 0.25, sin(t * 1.1) * 0.05 - _drift.x * 0.05))
	place(ROOT, root_pos, root_b)
	var breathe := sin(t * 1.3) * 0.03
	fk(SPINE, Vector3(breathe - 0.1 * _reach + 0.1 * die, _rake * 0.2, 0))
	fk(CHEST, Vector3(breathe * 0.5 - 0.12 * _reach + 0.15 * die, _rake * 0.25, 0))
	fk(NECK, Vector3(-0.1 * _reach + 0.2 * _recoil + 0.3 * die, sin(t * 0.47) * 0.25 * (1.0 - _reach), 0))
	fk(HEAD, Vector3(-0.15 * _reach + 0.3 * _recoil + 0.4 * die + sin(t * 0.8) * 0.05, sin(t * 0.47 + 0.6) * 0.15 * (1.0 - _reach), sin(t * 0.33) * 0.1))
	fk(JAW, Vector3(_jaw_open * 0.6 + die * 0.5, 0, 0))

	# --- Arms: hands drift and reach.
	for s: float in [-1.0, 1.0]:
		var up := ARM_L if s < 0.0 else ARM_R
		fk(up)
		var rest_hand := rest[up + 2]
		var idle := rest_hand + Vector3(s * 0.03 * sin(t * 0.9 + s), sin(t * 1.2 + s * 1.3) * 0.04, -0.04 + sin(t * 0.7 + s) * 0.03)
		var reach_pt := Vector3(s * 0.2, 1.42, -0.62)
		var tgt := idle.lerp(reach_pt, _reach)
		# Rake: the right hand sweeps from high and wide across the front.
		var rk := _rake * (1.0 if s > 0.0 else 0.35)
		if rk < 0.0:
			tgt = tgt.lerp(Vector3(s * 0.55, 1.75, -0.1), -rk)
		else:
			tgt = tgt.lerp(Vector3(-s * 0.15, 1.15, -0.6), rk)
		tgt += Vector3(s * 0.2, 0.25, 0.1) * _recoil
		tgt = tgt.lerp(Vector3(s * 0.75, 1.75, 0.0), die)
		var to_model := gb[ROOT] * (tgt - rest[ROOT]) + gp[ROOT]
		var pole := gb[ROOT] * Vector3(s * 1.0, -0.2, 0.7)
		ik(up, up + 1, up + 2, to_model, pole)
		var hand_dir := (gp[up + 2] - gp[up + 1]).normalized().lerp(gb[ROOT] * Vector3(0, 0.05, -1.0), _reach * 0.85)
		aim(up + 2, up + 3, hand_dir, Vector3(-s, 0, 0), gb[ROOT] * Vector3(-s, 0, 0))
		var curl := 0.35 + sin(t * 1.1 + s) * 0.15 - _reach * 0.75 + maxf(0.0, _rake * s) * 0.5 + die * 0.4
		fk(up + 3, Vector3(0, 0, -s * curl))

	# --- Skirt: trails behind the drift and ripples.
	var trail := clampf(-_drift.z * 0.12, -0.25, 0.45) + 0.15 * _reach + 0.3 * _recoil
	var side_trail := clampf(_drift.x * 0.1, -0.3, 0.3)
	for i in STRIPS:
		var d := _strip_dir(i)
		var tan := Vector3(-d.z, 0, d.x)
		var wave := sin(t * 2.1 + i * 1.7) * 0.1 + sin(t * 1.3 + i * 0.9) * 0.06 + die * 0.25
		var wave2 := sin(t * 2.6 + i * 1.1 + 1.0) * 0.14 + die * 0.3
		var b1 := Basis(Vector3.RIGHT, -trail * 0.6) * Basis(Vector3.FORWARD, side_trail * 0.6) * Basis(tan, -wave)
		var b2 := Basis(Vector3.RIGHT, -trail * 0.5) * Basis(Vector3.FORWARD, side_trail * 0.5) * Basis(tan, -wave2)
		fkb(SKIRT + i * 2, b1)
		fkb(SKIRT + i * 2 + 1, b2)
	commit()
	body_mi.set_instance_shader_parameter(&"intensity", _eye * (1.0 - _dissolve))
	if _wisps_fx != null:
		_wisps_fx.emitting = not _dead or _dead_t < dissolve_delay + 0.6
		_wisps_fx.amount_ratio = 1.0 if not _dead else 1.0
