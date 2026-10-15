class_name CrawlerModel
extends MobModel
## Long-bodied creatures whose body follows the path of the head (the
## entity position), drawn as ONE smooth skinned mesh (MobRig):
##   "cave_crawler": a giant armoured centipede of the deep caves - a trunk of
##                   ridged segments under overlapping glossy tergite plates,
##                   a jointed leg pair on every segment rippling in a
##                   metachronal wave, a flat head capsule with long beaded
##                   antennae, ocelli and hooked venom forcipules.
##   "shark":        a grey reef shark - countershaded fusiform body with a
##                   conical snout, five gill slits, first and second dorsal,
##                   pectoral, pelvic and anal fins, a heterocercal tail, dark
##                   eyes and rows of serrated teeth in a hinged jaw.
## The spine is a follow-the-leader chain in world space (no sliding when
## turning) with a travelling swim / crawl wave on top. Faces -Z.

const S_BODY := 0
const S_LEG := 1
const S_DARK := 2
const S_EYE := 3
const S_TOOTH := 4

var species := "cave_crawler"
var k := 1.0
var _len := 5.0
var _base_len := 5.5
var _spine: Array[int] = []
var _legs: Array = []      # [bone, side, segment index]
var _b := {}
var _pts := PackedVector3Array()   # chain joints (world)
var _ready_chain := false
var _prev := Vector3.INF
var _vel := Vector3.ZERO
var _look := Vector3.FORWARD
var _phase := 0.0
var _step := 0.0
var _jaw := 0.0
var _lunge := 0.0
var _rear := 0.0
var _flinch := 0.0


func _init(kind_name := "cave_crawler", variant_seed := 0) -> void:
	species = kind_name
	var rng := RandomNumberGenerator.new()
	rng.seed = variant_seed
	k = rng.randf_range(0.9, 1.15)
	_base_len = 5.5 if species == "cave_crawler" else 3.2
	_len = _base_len * k
	dissolve_delay = 1.4


func _ember_extents() -> Vector3:
	return Vector3(0.5, 0.3, _len * 0.4)


func _lod_size() -> float:
	return _len * 0.6


# --- Build -------------------------------------------------------------------------------

func _build() -> void:
	var data := _shark_rig() if species == "shark" else _crawler_rig()
	rig_instance(data, _materials(), k, 2.2)
	var names: PackedStringArray = data["names"]
	_b.clear()
	_spine.clear()
	_legs.clear()
	for i in names.size():
		_b[names[i]] = i
		if names[i].begins_with("seg"):
			_spine.append(i)
	for i in names.size():
		if names[i].begins_with("leg"):
			var side := -1.0 if names[i].ends_with("l") else 1.0
			_legs.append([i, side, parents[i]])
	_pts.resize(_spine.size())


func _materials() -> Array:
	if species == "shark":
		var skin := CreatureSkin.smooth(Color(0.33, 0.37, 0.41), Color(0.9, 0.9, 0.88), {"use_rest": true, "belly_mix": 1.0, "wet": 0.75,
			"pattern": CreatureSkin.Pattern.HIDE, "pattern_scale": 9.0, "bump": 0.12, "roughness": 0.38, "rim": 0.25, "accent": Color(0.2, 0.23, 0.27),
			"accent_mode": 3, "accent_amount": 0.4, "accent_scale": 1.5})
		var fin := CreatureSkin.smooth(Color(0.27, 0.3, 0.34), Color(0.75, 0.76, 0.75), {"use_rest": true, "belly_mix": 0.8, "wet": 0.75,
			"pattern": CreatureSkin.Pattern.HIDE, "pattern_scale": 16.0, "bump": 0.3, "roughness": 0.35, "accent": Color(0.12, 0.13, 0.15),
			"accent_mode": 3, "accent_amount": 0.3, "accent_scale": 2.0})
		var dark := CreatureSkin.mouth(Color(0.22, 0.09, 0.1))
		var eye := CreatureSkin.smooth(Color(0.01, 0.01, 0.012), Color(0.01, 0.01, 0.012), {"roughness": 0.03, "specular_amount": 1.0, "rim": 0.0, "bump": 0.0})
		var tooth := CreatureSkin.keratin(Color(0.93, 0.91, 0.86), {"use_rest": true, "pattern_scale": 60.0})
		return [skin, fin, dark, eye, tooth]
	var shell := CreatureSkin.chitin(Color(0.28, 0.11, 0.07), {"use_rest": true, "pattern_scale": 5.0, "bump": 0.9, "roughness": 0.28,
		"accent": Color(0.08, 0.04, 0.03), "accent_mode": 3, "accent_amount": 0.6, "accent_scale": 1.6, "belly": Color(0.6, 0.38, 0.16),
		"belly_mix": 0.8, "bump_distance": 30.0})
	var leg := CreatureSkin.chitin(Color(0.48, 0.24, 0.08), {"use_rest": true, "pattern_scale": 14.0, "bump": 0.6, "roughness": 0.3,
		"belly": Color(0.75, 0.5, 0.2)})
	var dark := CreatureSkin.keratin(Color(0.06, 0.03, 0.025), {"use_rest": true, "roughness": 0.2, "specular_amount": 0.85, "pattern_scale": 50.0})
	var eye := CreatureSkin.eye(Color(0.5, 1.0, 0.7), 5.0, 0.3)
	return [shell, leg, dark, eye, dark]


static func _tube_rows(r: MobRig, rows: Array, count: int, blend: float, sides: int) -> void:
	var pts := PackedVector3Array()
	var rad := PackedVector2Array()
	var bw: Array = []
	for row: Array in rows:
		pts.append(row[0])
		rad.append(row[1])
		bw.append(row[2])
	var rs := MobRig.resample(pts, rad, bw, count)
	r.tube(rs[0], rs[1], rs[2], blend, sides)


func _crawler_rig() -> Dictionary:
	var key := "crawler_centipede"
	if MobRig.has(key):
		return MobRig.cached(key)
	var r := MobRig.new(5)
	var L := _base_len
	var n := 16
	var seg := L / float(n - 1)
	var H := 0.3
	var spine: Array[int] = []
	for i in n:
		spine.append(r.bone("seg%d" % i, -1, Vector3(0, H, i * seg)))
	var head := spine[0]
	var forc_l := r.bone("forc_l", head, Vector3(-0.13, H - 0.08, -0.12))
	var forc_r := r.bone("forc_r", head, Vector3(0.13, H - 0.08, -0.12))
	var ant_l := r.bone("ant_l", head, Vector3(-0.07, H + 0.06, -0.33))
	var ant_r := r.bone("ant_r", head, Vector3(0.07, H + 0.06, -0.33))
	var leg_bones: Array = []
	for i in range(1, n - 1):
		for side: float in [-1.0, 1.0]:
			var b := r.bone("leg%d%s" % [i, "l" if side < 0.0 else "r"], spine[i], Vector3(side * 0.24, H - 0.06, i * seg))
			leg_bones.append([b, side, i])
	# Trunk: ridged segments, broad in the middle, tapering to a forked tail.
	var rows: Array = []
	rows.append([Vector3(0, H, -0.18), Vector2(0.17, 0.1), head])
	for i in n:
		var t := float(i) / (n - 1)
		var w := (0.24 + 0.1 * sin(PI * clampf(t * 1.25, 0.0, 1.0))) * (1.0 - smoothstep(0.75, 1.0, t) * 0.55)
		var hh := w * 0.52
		var z := i * seg
		rows.append([Vector3(0, H, z - seg * 0.42), Vector2(w * 0.86, hh * 0.85), spine[maxi(0, i - 1)] if i > 0 else head])
		rows.append([Vector3(0, H + 0.01, z), Vector2(w, hh), spine[i]])
	rows.append([Vector3(0, H, L + seg * 0.35), Vector2(0.06, 0.05), spine[n - 1]])
	r.slot(S_BODY)
	_tube_rows(r, rows, 80, 0.08, 14)
	# Tergites: overlapping glossy plates on every segment, sternites below.
	for i in range(1, n):
		var t := float(i) / (n - 1)
		var w := (0.24 + 0.1 * sin(PI * clampf(t * 1.25, 0.0, 1.0))) * (1.0 - smoothstep(0.75, 1.0, t) * 0.55)
		var plate := BossKit.shell("crawler_tergite_%d" % int(w * 100.0), Vector3(w * 1.08, w * 0.56, seg * 0.62), -100.0, 100.0, 0.0, 78.0, 0.02, 10, 5)
		r.slot(S_BODY).rigid(plate, Transform3D(Basis(Vector3.RIGHT, -0.08), Vector3(0, H + 0.01, i * seg - seg * 0.05)), spine[i], spine[i - 1], 0.25)
	# Head capsule, ocelli, antennae, forcipules.
	r.slot(S_BODY).rigid(OrganicMesh.profile("crawler_head", Vector3(0, H, 0.05), Vector3(0, H - 0.02, -0.36), [[0.0, 0.17, 0.09], [0.3, 0.2, 0.1], [0.7, 0.17, 0.08], [1.0, 0.08, 0.04]], 14, 10), Transform3D(), head)
	for side: float in [-1.0, 1.0]:
		for e in 4:
			var ep := Vector3(side * (0.1 + (e % 2) * 0.025), H + 0.075, -0.24 + (e / 2) * 0.03)
			r.slot(S_EYE).rigid(ModelKit.sphere(0.017, 6), Transform3D(Basis(), ep), head)
		var ab := ant_l if side < 0.0 else ant_r
		var ap := r.rest[ab]
		var pts := PackedVector3Array()
		for a in 9:
			var f := float(a) / 8.0
			pts.append(ap + Vector3(side * 0.35 * f, 0.18 * sin(f * 2.2), -0.95 * f))
		var rad := PackedVector2Array()
		var bw: Array = []
		for a in pts.size():
			var rr := lerpf(0.028, 0.008, float(a) / (pts.size() - 1))
			rad.append(Vector2(rr, rr))
			bw.append(ab)
		var rs := MobRig.resample(pts, rad, bw, 24)
		r.slot(S_LEG).tube(rs[0], rs[1], rs[2], 0.05, 6)
		var fb := forc_l if side < 0.0 else forc_r
		var fp := r.rest[fb]
		r.slot(S_LEG).rigid(OrganicMesh.profile("crawler_forc_base_%d" % int(side), fp + Vector3(-side * 0.06, 0.02, 0.06), fp + Vector3(side * 0.04, -0.01, -0.12), [[0.0, 0.06, 0.05], [0.6, 0.06, 0.05], [1.0, 0.04, 0.035]], 8, 6), Transform3D(), fb)
		var hook := OrganicMesh.bezier("crawler_forc_%d" % int(side), Vector3.ZERO, Vector3(side * 0.02, 0.0, -0.18), Vector3(-side * 0.12, -0.02, -0.26), 0.038, 0.004, 9, 7)
		r.slot(S_DARK).rigid(hook, Transform3D(Basis(), fp + Vector3(side * 0.04, -0.01, -0.12)), fb)
		# Mandible stubs.
		r.slot(S_DARK).rigid(OrganicMesh.bezier("crawler_mand_%d" % int(side), Vector3.ZERO, Vector3(-side * 0.02, -0.01, -0.05), Vector3(-side * 0.05, -0.02, -0.06), 0.02, 0.004, 5, 5), Transform3D(Basis(), Vector3(side * 0.05, H - 0.05, -0.34)), head)
	# Legs: coxa out and up to a knee, tibia and tarsus down to a hooked claw.
	for lb: Array in leg_bones:
		var b: int = lb[0]
		var side: float = lb[1]
		var i: int = lb[2]
		var t := float(i) / (n - 1)
		var w := (0.24 + 0.1 * sin(PI * clampf(t * 1.25, 0.0, 1.0))) * (1.0 - smoothstep(0.75, 1.0, t) * 0.55)
		var hip := r.rest[b]
		var reach := 0.62 + w * 0.8
		var pts := PackedVector3Array([hip - Vector3(side * 0.08, 0, 0), hip + Vector3(side * reach * 0.45, 0.14, -0.02), hip + Vector3(side * reach * 0.85, -0.05, -0.05), Vector3(hip.x + side * reach, 0.0, hip.z - 0.02)])
		r.slot(S_LEG).limb(pts, [spine[i], b, b], [[0.0, 0.036, 0.036], [0.25, 0.03, 0.027], [0.45, 0.025, 0.023], [0.48, 0.028, 0.026], [0.85, 0.015, 0.015], [1.0, 0.008, 0.008]], 12, 6, Vector3.UP, 0.04, {spine[i]: 1.0}, 0.1)
		r.slot(S_DARK).rigid(OrganicMesh.bezier("crawler_claw", Vector3.ZERO, Vector3(0, -0.02, -0.01), Vector3(0, -0.035, -0.035), 0.008, 0.001, 4, 4), Transform3D(Basis(Vector3.UP, side * 0.3), pts[3] + Vector3(0, 0.025, 0)), b)
	# Forked tail appendages.
	for side: float in [-1.0, 1.0]:
		r.slot(S_LEG).rigid(OrganicMesh.bezier("crawler_tailfork_%d" % int(side), Vector3.ZERO, Vector3(side * 0.12, 0.02, 0.25), Vector3(side * 0.2, -0.05, 0.55), 0.035, 0.008, 8, 6), Transform3D(Basis(), Vector3(side * 0.05, H, L + seg * 0.1)), spine[n - 1])
	return r.build(key)


func _shark_rig() -> Dictionary:
	var key := "crawler_shark"
	if MobRig.has(key):
		return MobRig.cached(key)
	var r := MobRig.new(5)
	var L := _base_len
	var n := 10
	var seg := L / float(n - 1)
	var spine: Array[int] = []
	for i in n:
		spine.append(r.bone("seg%d" % i, -1, Vector3(0, 0, i * seg)))
	var jaw := r.bone("jaw", spine[0], Vector3(0, -0.14, -0.12))
	var pec_l := r.bone("pec_l", spine[1], Vector3(-0.22, -0.16, seg * 1.0))
	var pec_r := r.bone("pec_r", spine[1], Vector3(0.22, -0.16, seg * 1.0))
	# Fusiform body: conical snout, deepest at the first dorsal, slim caudal peduncle.
	var prof := [[-0.8, 0.006, 0.006, -0.012], [-0.74, 0.032, 0.025, -0.01], [-0.62, 0.075, 0.058, -0.006], [-0.45, 0.125, 0.105, 0.0], [-0.25, 0.18, 0.17, 0.01], [0.05, 0.235, 0.26, 0.02],
		[0.45, 0.265, 0.3, 0.03], [0.85, 0.245, 0.275, 0.03], [1.35, 0.19, 0.21, 0.02], [1.85, 0.12, 0.135, 0.01], [2.35, 0.072, 0.095, 0.0],
		[2.8, 0.048, 0.07, 0.0], [L, 0.034, 0.05, 0.0], [L + 0.12, 0.01, 0.01, 0.0]]
	var rows: Array = []
	for pr: Array in prof:
		var z := float(pr[0])
		var bi := clampi(int(round(maxf(z, 0.0) / seg)), 0, n - 1)
		var bw: Variant = spine[bi]
		var fz := maxf(z, 0.0) / seg
		var b0 := clampi(int(floor(fz)), 0, n - 1)
		var b1 := mini(b0 + 1, n - 1)
		var f := fz - b0
		if b0 != b1:
			bw = {spine[b0]: 1.0 - f, spine[b1]: f}
		rows.append([Vector3(0, float(pr[3]), z), Vector2(float(pr[1]), float(pr[2])), bw])
	r.slot(S_BODY)
	_tube_rows(r, rows, 60, seg * 0.6, 16)
	# Fins (flat, tapered membranes with thickness).
	var fin_m := func(fkey: String, pts: PackedVector2Array, th: float) -> ArrayMesh:
		return OrganicMesh.membrane("shark_" + fkey, pts, 0.0, th)
	var dorsal: ArrayMesh = fin_m.call("dorsal", PackedVector2Array([Vector2(0.32, 0.0), Vector2(0.12, 0.25), Vector2(-0.06, 0.52), Vector2(-0.16, 0.56), Vector2(-0.2, 0.48), Vector2(-0.24, 0.05), Vector2(-0.3, 0.0)]), 0.05)
	r.slot(S_LEG).rigid(dorsal, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 0.3, 0.95)), spine[3], spine[2], 0.4)
	var dorsal2: ArrayMesh = fin_m.call("dorsal2", PackedVector2Array([Vector2(0.08, 0.0), Vector2(0.0, 0.1), Vector2(-0.07, 0.12), Vector2(-0.1, 0.0)]), 0.025)
	r.slot(S_LEG).rigid(dorsal2, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 0.1, 2.25)), spine[7])
	var anal: ArrayMesh = fin_m.call("anal", PackedVector2Array([Vector2(0.08, 0.0), Vector2(0.0, -0.09), Vector2(-0.07, -0.11), Vector2(-0.1, 0.0)]), 0.025)
	r.slot(S_LEG).rigid(anal, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, -0.1, 2.35)), spine[7])
	for side: float in [-1.0, 1.0]:
		var pb := pec_l if side < 0.0 else pec_r
		var pec: ArrayMesh = fin_m.call("pec_%d" % int(side), PackedVector2Array([Vector2(0, 0.17), Vector2(side * 0.22, 0.08), Vector2(side * 0.78, -0.4), Vector2(side * 0.72, -0.5), Vector2(side * 0.36, -0.25), Vector2(0, -0.12)]), 0.035)
		r.slot(S_LEG).rigid(pec, Transform3D(Basis.from_euler(Vector3(-PI * 0.5 + 0.15, 0, side * -0.35)), r.rest[pb]), pb)
		var pelv: ArrayMesh = fin_m.call("pelv_%d" % int(side), PackedVector2Array([Vector2(0, 0.06), Vector2(side * 0.16, -0.08), Vector2(side * 0.12, -0.12), Vector2(0, -0.06)]), 0.025)
		r.slot(S_LEG).rigid(pelv, Transform3D(Basis.from_euler(Vector3(-PI * 0.5 + 0.3, 0, side * -0.5)), Vector3(side * 0.12, -0.2, 1.75)), spine[5], spine[6], 0.5)
		# Gill slits: five dark arcs behind the eye.
		for g in 5:
			var gz := -0.08 + g * 0.06
			r.slot(S_DARK).rigid(OrganicMesh.bezier("shark_gill", Vector3(0, 0.11, 0), Vector3(0.012, 0.0, -0.01), Vector3(0, -0.11, 0.0), 0.008, 0.006, 5, 4), Transform3D(Basis(), Vector3(side * (0.235 + g * 0.012), -0.02, gz)), spine[0])
		# Eye.
		r.slot(S_EYE).rigid(ModelKit.sphere(0.028, 8), Transform3D(Basis(), Vector3(side * 0.112, 0.035, -0.45)), spine[0])
		r.slot(S_BODY).rigid(OrganicMesh.blob("shark_brow", Vector3(0.035, 0.018, 0.06), 0.1, 3, 8), Transform3D(Basis(), Vector3(side * 0.105, 0.058, -0.44)), spine[0])
		# Nostrils.
		r.slot(S_DARK).rigid(OrganicMesh.blob("shark_nostril", Vector3(0.012, 0.004, 0.02), 0.1, 5, 6), Transform3D(Basis(), Vector3(side * 0.04, -0.035, -0.68)), spine[0])
	# Heterocercal tail: long upper lobe, shorter lower lobe.
	var caudal: ArrayMesh = fin_m.call("caudal", PackedVector2Array([Vector2(0.12, 0.0), Vector2(-0.18, 0.28), Vector2(-0.52, 0.72), Vector2(-0.62, 0.74), Vector2(-0.42, 0.36),
		Vector2(-0.3, 0.06), Vector2(-0.4, -0.22), Vector2(-0.44, -0.34), Vector2(-0.3, -0.3), Vector2(-0.05, -0.06)]), 0.04)
	r.slot(S_LEG).rigid(caudal, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 0.0, L - 0.05)), spine[n - 1])
	# Head underside: mouth crescent on the jaw bone with rows of teeth.
	var jp := r.rest[jaw]
	r.slot(S_DARK).rigid(OrganicMesh.blob("shark_mouth", Vector3(0.17, 0.045, 0.14), 0.05, 3, 10), Transform3D(Basis(), jp + Vector3(0, 0.03, -0.13)), spine[0])
	r.slot(S_BODY).rigid(OrganicMesh.profile("shark_jaw", jp + Vector3(0, 0, 0.1), jp + Vector3(0, 0.0, -0.3), [[0.0, 0.2, 0.06], [0.5, 0.17, 0.055], [1.0, 0.07, 0.03]], 12, 8), Transform3D(), jaw)
	for row in 2:
		for side: float in [-1.0, 1.0]:
			for t in 7:
				var a := float(t) / 6.0
				var tp := Vector3(side * lerpf(0.17, 0.02, a) * (1.0 - row * 0.12), 0.0, lerpf(-0.06, -0.31, a) + row * 0.03)
				var tl := 0.035 - row * 0.01
				var tooth := OrganicMesh.bezier("shark_tooth_%d" % row, Vector3.ZERO, Vector3(0, -tl * 0.6, 0), Vector3(0, -tl, 0.004), tl * 0.35, tl * 0.03, 3, 4, 0.5)
				r.slot(S_TOOTH).rigid(tooth, Transform3D(Basis(), jp + Vector3(tp.x, 0.05, tp.z - 0.02)), spine[0])
				r.slot(S_TOOTH).rigid(tooth, Transform3D(Basis(Vector3.RIGHT, PI), jp + Vector3(tp.x * 0.95, 0.035, tp.z + 0.01)), jaw)
	return r.build(key)


# --- Animation ---------------------------------------------------------------------------

func _animate(delta: float) -> void:
	if skel == null:
		return
	var shark := species == "shark"
	var gt := global_transform
	var base := gt.origin
	var fwd := -gt.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.FORWARD
	if not _prev.is_finite():
		_prev = base
	_vel = _vel.lerp((base - _prev) / maxf(delta, 0.001), 1.0 - exp(-8.0 * delta))
	_prev = base
	var speed := _vel.length()
	var look := _vel.normalized() if speed > 0.4 else fwd
	if not shark:
		look.y = clampf(look.y, -0.5, 0.5)
	_look = _look.slerp(look.normalized(), 1.0 - exp(-6.0 * delta)).normalized()
	if absf(_look.y) > 0.95 or not _look.is_finite():
		_look = fwd
	var p := action_progress()
	var w := action_weight()
	var act := _action if p >= 0.0 and not _dead else ""
	var lunge := 0.0
	var rear := 0.0
	var jaw_t := 0.06 + (sin(_time * 1.5) * 0.04 if shark else 0.0)
	var flinch := 0.0
	match act:
		"attack", "bite", "lunge", "attack2":
			var s := keys(p, [[0, 0], [0.35, -0.6], [0.55, 1.0], [1, 0]])
			lunge = s
			rear = maxf(0.0, -s)
			jaw_t = keys(p, [[0, 0.1], [0.4, 1.0], [0.58, 0.0], [1, 0.1]])
		"roar", "howl", "summon", "slam":
			rear = 1.2 * w
			jaw_t = lerpf(jaw_t, 1.0, w)
		"hit":
			flinch = sin(PI * clampf(p * 1.3, 0.0, 1.0))
	_lunge = damp(_lunge, lunge, 14.0, delta)
	_rear = damp(_rear, rear, 10.0, delta)
	_jaw = damp(_jaw, jaw_t, 18.0, delta)
	_flinch = damp(_flinch, flinch, 20.0, delta)
	var n := _spine.size()
	var seg := _len / float(n - 1)
	var head := base + Vector3.UP * (_rear * (0.55 if not shark else 0.25) * k) + fwd * _lunge * (0.6 if not shark else 0.5) * k
	if _dead:
		head = base + Vector3.UP * (0.0 if not shark else -0.1)
	# Follow-the-leader chain in world space.
	if not _ready_chain:
		_ready_chain = true
		for i in n:
			_pts[i] = head - fwd * seg * i
	_pts[0] = head
	var rest_y := base.y
	var kk := 1.0 - exp(-(8.0 if not shark else 2.0) * delta)
	var prev_dir := Vector3.ZERO
	for i in range(1, n):
		var pt := _pts[i]
		var want_y := rest_y
		# Rearing lifts only the front third.
		if i < n / 3 and _rear > 0.0 and not _dead:
			want_y += _rear * (0.55 if not shark else 0.2) * k * (1.0 - float(i) / (n / 3.0))
		pt.y = lerpf(pt.y, want_y, kk * (0.3 + 0.7 * float(i) / n))
		var d := pt - _pts[i - 1]
		if d.length_squared() < 1e-8:
			d = prev_dir if prev_dir != Vector3.ZERO else -fwd
		d = d.normalized()
		if prev_dir != Vector3.ZERO:
			d = d.lerp(prev_dir, 0.15 if not shark else 0.4).normalized()
		_pts[i] = _pts[i - 1] + d * seg
		prev_dir = d
	# Travelling wave (display only) and conversion to rig space.
	_phase += delta * (6.0 if not shark else 5.0) * clampf(0.3 + speed / 3.0, 0.15, 2.5)
	var amp := (0.1 if not shark else 0.3) * k
	if _dead:
		amp *= maxf(0.0, 1.0 - _dead_t)
	var inv := gt.affine_inverse()
	var disp := PackedVector3Array()
	disp.resize(n)
	for i in n:
		var t := float(i) / (n - 1)
		var a := _pts[maxi(0, i - 1)]
		var b := _pts[mini(n - 1, i + 1)]
		var dir := (b - a)
		dir.y = 0.0
		dir = dir.normalized() if dir.length_squared() > 1e-8 else -fwd
		var side := dir.cross(Vector3.UP)
		var wave := sin(_phase - t * (2.5 if not shark else 0.9) * TAU) * amp * (0.15 + 0.85 * t)
		if shark:
			wave *= (0.1 + 0.9 * t * t)
		wave += _flinch * 0.15 * k * (1.0 - t)
		disp[i] = inv * (_pts[i] + side * wave) / k
	for i in n:
		var a := disp[maxi(0, i - 1)]
		var b := disp[mini(n - 1, i + 1)]
		var z := (b - a)
		if i == 0:
			var lk := (gt.basis.inverse() * -_look)
			z = z.normalized().lerp(lk.normalized(), 0.5) if z.length_squared() > 1e-8 else lk
		z = z.normalized() if z.length_squared() > 1e-8 else Vector3.BACK
		var y := Vector3.UP - z * Vector3.UP.dot(z)
		y = y.normalized() if y.length_squared() > 1e-6 else Vector3.UP
		var x := y.cross(z).normalized()
		var bb := Basis(x, y, z)
		if _dead and not shark:
			bb = bb * Basis(Vector3.BACK, clampf(_dead_t / 1.2, 0.0, 1.0) * PI * 0.9 * (1.0 if i % 2 == 0 else 1.02))
		elif _dead and shark:
			bb = bb * Basis(Vector3.BACK, clampf(_dead_t / 1.5, 0.0, 1.0) * PI * 0.6)
		place(_spine[i], disp[i], bb)
	if shark:
		fk(_b["jaw"], Vector3(_jaw * 0.55, 0, 0))
		var flap := sin(_time * 1.3) * 0.08
		fk(_b["pec_l"], Vector3(0, 0, flap - 0.05))
		fk(_b["pec_r"], Vector3(0, 0, -flap + 0.05))
	else:
		_pose_crawler(speed, delta)
	commit()


func _pose_crawler(speed: float, delta: float) -> void:
	var open := _jaw
	fk(_b["forc_l"], Vector3(0, -open * 0.7, 0))
	fk(_b["forc_r"], Vector3(0, open * 0.7, 0))
	fk(_b["ant_l"], Vector3(sin(_time * 3.0) * 0.2 - _rear * 0.3, sin(_time * 2.3) * 0.25, 0))
	fk(_b["ant_r"], Vector3(sin(_time * 3.0 + 1.0) * 0.2 - _rear * 0.3, sin(_time * 2.3 + 1.7) * 0.25, 0))
	_step += delta * (3.0 + speed * 4.0) * (0.0 if _dead else 1.0)
	var amp := 0.18 + clampf(speed * 0.18, 0.0, 0.42)
	for l: Array in _legs:
		var b: int = l[0]
		var side: float = l[1]
		var seg_b: int = l[2]
		var i := _spine.find(seg_b)
		if _dead:
			var curl := clampf(_dead_t / 1.0, 0.0, 1.0)
			fk(b, Vector3(0, 0, side * 0.9 * curl + sin(_time * 14.0 + i) * 0.1 * maxf(0.0, 1.0 - _dead_t)))
			continue
		var ph := _step - float(i) * 0.75 + (PI if side > 0.0 else 0.0)
		var swing := sin(ph) * amp
		var lift := maxf(0.0, cos(ph)) * 0.35 * clampf(0.3 + speed, 0.0, 1.0)
		# Front legs lift off the ground while rearing.
		if i < 4 and _rear > 0.0:
			lift += _rear * 0.4 * (1.0 - i / 4.0)
		fk(b, Vector3(0, -side * swing, side * lift))
