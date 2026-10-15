class_name ArachnidModel
extends MobModel
## Eight-legged creatures: giant spiders, spiderlings and giant scorpions
## (the Broodmother has her own model and borrows the IK helpers below).
##
## Each is ONE smooth skinned body (MobRig, ~45 bones, 4-5 draw calls):
##   spider    hairy cephalothorax with a raised eye mound of eight glossy
##             eyes, a narrow pedicel, a swollen banded abdomen with
##             spinnerets, bulbous chelicerae with curved fangs, hairy
##             pedipalps and eight jointed legs (femur up to a high knee,
##             patella / tibia down, metatarsus and tarsus with claws), all
##             bristling with setae and longer spines
##   scorpion  flat carapace with a median eye tubercle, seven ridged
##             mesosoma tergites, a five-segment metasoma arching over the
##             back to a bulbous telson and curved sting with a venom glow,
##             big chelae (pincers) with a hinged finger, eight legs
## Legs are planted by two-bone IK from an alternating-tetrapod gait. Bite /
## lunge (rearing strike), pinch and sting, threat display (roar), hit
## flinch, and a death where the legs curl in under the body.
## Faces -Z; `size` is the body length in metres.

const S_BODY := 0
const S_ABD := 1
const S_FANG := 2
const S_EYE := 3
const S_GLOW := 4
const S_LEG := 5

var species := "spider"
var size := 1.6
var palette := {}
## Hanging from a silk line (kept for compatibility; legs draw in).
var hanging := false

var _b := {}           # bone name -> index
var _legs: Array = []  # {up, lo, foot, toe, side, i, tip: Vector3, group}
var _tail: Array[int] = []
var _gait := 0.0
var _walk := 0.0
var _speed := 0.0
var _rear := 0.0
var _lunge := 0.0
var _fang := 0.0
var _crouch := 0.0
var _sting := 0.0
var _pinch := 0.0
var _claw_reach := 0.0
var _flinch := 0.0
var _curl := 0.0
var _h := 0.5


func _init(kind_name := "spider", variant_seed := 0) -> void:
	species = kind_name
	var rng := RandomNumberGenerator.new()
	rng.seed = variant_seed
	match species:
		"spiderling":
			size = 0.7
			palette = {"body": Color(0.5, 0.55, 0.4), "accent": Color(0.16, 0.2, 0.1), "belly": Color(0.7, 0.72, 0.58), "eye": Color(0.7, 1.0, 0.4)}
		"scorpion":
			size = 2.4
			var sand := [Color(0.55, 0.36, 0.17), Color(0.4, 0.2, 0.11), Color(0.2, 0.16, 0.14)]
			var c: Color = sand[rng.randi() % sand.size()]
			palette = {"body": c, "accent": c.darkened(0.5), "belly": c.lightened(0.25), "eye": Color(1.0, 0.55, 0.15), "glow": Color(0.6, 1.0, 0.3)}
		_:
			size = rng.randf_range(1.5, 2.0)
			var furs := [Color(0.2, 0.15, 0.11), Color(0.1, 0.09, 0.08), Color(0.27, 0.22, 0.17)]
			var c: Color = furs[rng.randi() % furs.size()]
			palette = {"body": c, "accent": Color(0.5, 0.38, 0.22) if rng.randf() < 0.5 else Color(0.55, 0.12, 0.07), "belly": c.lightened(0.12), "eye": Color(1.0, 0.25, 0.15)}
	dissolve_delay = 1.6
	durations["summon"] = 1.6
	durations["roar"] = 1.6
	durations["shoot"] = 0.9
	durations["lunge"] = 0.75
	durations["attack2"] = 0.8


func _ember_extents() -> Vector3:
	return Vector3(0.6, 0.35, 0.8) * size


func _lod_size() -> float:
	return size * 1.4


# --- Build -------------------------------------------------------------------------------

func _build() -> void:
	var scorp := species == "scorpion"
	var data := _scorpion_rig() if scorp else _spider_rig()
	rig_instance(data, _materials(), size, 1.4)
	var names: PackedStringArray = data["names"]
	_b.clear()
	for i in names.size():
		_b[names[i]] = i
	_h = rest[0].y
	_legs.clear()
	_tail.clear()
	for side: float in [-1.0, 1.0]:
		for i in 4:
			var pre := "l%d%s_" % [i, "l" if side < 0.0 else "r"]
			var up: int = _b[pre + "up"]
			var leg := {"up": up, "lo": up + 1, "foot": up + 2, "toe": up + 3, "side": side, "i": i,
				"tip": rest[up + 3], "off": rest[up + 2] - rest[up + 3],
				"group": (i + (0 if side < 0.0 else 1)) % 2}
			_legs.append(leg)
	for i in 6:
		if _b.has("tail%d" % i):
			_tail.append(_b["tail%d" % i])


func _materials() -> Array:
	var scorp := species == "scorpion"
	var body: ShaderMaterial
	var abd: ShaderMaterial
	if scorp:
		body = CreatureSkin.chitin(palette["body"], {"use_rest": true, "pattern_scale": 9.0, "bump": 0.6, "accent": palette["accent"],
			"accent_mode": 3, "accent_amount": 0.55, "accent_scale": 3.0, "roughness": 0.45, "belly": palette["belly"], "belly_mix": 0.7, "bump_distance": 25.0})
		abd = CreatureSkin.chitin((palette["body"] as Color).darkened(0.08), {"use_rest": true, "pattern_scale": 33.0, "bump": 0.5,
			"accent": palette["accent"], "accent_mode": 3, "accent_amount": 0.45, "accent_scale": 3.0, "roughness": 0.4, "belly": palette["belly"], "belly_mix": 0.7, "bump_distance": 25.0})
	else:
		body = CreatureSkin.fur(palette["body"], palette["belly"], {"use_rest": true, "pattern_scale": 42.0, "bump": 1.2,
			"accent": palette["accent"], "accent_mode": 3, "accent_amount": 0.45, "accent_scale": 4.0, "rim": 0.4, "bump_distance": 20.0,
			"ascii_id": AsciiMaterialId.SOLID})
		abd = CreatureSkin.fur(palette["body"], palette["belly"], {"use_rest": true, "pattern_scale": 40.0, "bump": 1.2,
			"accent": palette["accent"], "accent_mode": 1, "accent_amount": 0.75, "accent_scale": 7.0, "rim": 0.45, "bump_distance": 20.0,
			"ascii_id": AsciiMaterialId.SOLID})
	var fang := CreatureSkin.keratin(Color(0.06, 0.05, 0.05), {"use_rest": true, "roughness": 0.18, "specular_amount": 0.85, "pattern_scale": 60.0})
	var leg: ShaderMaterial
	if scorp:
		leg = CreatureSkin.chitin((palette["body"] as Color).lightened(0.06), {"use_rest": true, "pattern_scale": 14.0, "bump": 0.6,
			"roughness": 0.42, "belly": palette["belly"], "belly_mix": 0.5, "bump_distance": 25.0})
	else:
		# Banded legs: the bands run round the leg (UV v is the distance along it).
		leg = CreatureSkin.fur(palette["body"], palette["belly"], {"use_uv": true, "pattern_scale": 26.0, "bump": 1.3,
			"accent": palette["accent"], "accent_mode": 1, "accent_amount": 0.7, "accent_scale": 4.6, "rim": 0.45, "bump_distance": 20.0,
			"ascii_id": AsciiMaterialId.SOLID})
	var eye := CreatureSkin.eye((palette["eye"] as Color).darkened(0.35), 1.6, 0.1)
	var glow := CreatureSkin.eye(palette.get("glow", palette["eye"]), 5.0, 0.6)
	return [body, abd, fang, eye, glow, leg]


## A single hair / seta: a thin three-sided blade along +Y (flat face +Z), curling outwards.
static func _hair() -> ArrayMesh:
	var path := PackedVector3Array([Vector3.ZERO, Vector3(0, 0.5, 0.06), Vector3(0, 1.0, 0.2)])
	var radii := PackedVector2Array([Vector2(0.15, 0.05), Vector2(0.09, 0.03), Vector2(0.01, 0.005)])
	return OrganicMesh.sweep("arach_hair3", path, radii, 3, Vector3.BACK)


static func _p(pts: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p: Vector3 in pts:
		out.append(p)
	return out


static func _r(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in pts:
		out.append(p)
	return out


## A smooth tube through control points [pos, radius(Vector2), bone or {bone: w}] resampled to `count`.
static func _tube(r: MobRig, rows: Array, count: int, blend: float, sides: int) -> void:
	var pts := PackedVector3Array()
	var rad := PackedVector2Array()
	var bw: Array = []
	for row: Array in rows:
		pts.append(row[0])
		rad.append(row[1])
		bw.append(row[2])
	var rs := MobRig.resample(pts, rad, bw, count)
	r.tube(rs[0], rs[1], rs[2], blend, sides)


func _leg_bones(r: MobRig, body: int, legs_spec: Array) -> Array:
	# legs_spec rows: [hip, knee, ankle, tip] (right side); returns joint lists per leg.
	var out: Array = []
	for side: float in [-1.0, 1.0]:
		for i in 4:
			var j: Array = legs_spec[i]
			var m := Vector3(side, 1, 1)
			var pre := "l%d%s_" % [i, "l" if side < 0.0 else "r"]
			var up := r.bone(pre + "up", body, (j[0] as Vector3) * m)
			r.bone(pre + "lo", up, (j[1] as Vector3) * m)
			r.bone(pre + "foot", up + 1, (j[2] as Vector3) * m)
			r.bone(pre + "toe", up + 2, (j[3] as Vector3) * m)
			out.append([up, side, i, [(j[0] as Vector3) * m, (j[1] as Vector3) * m, (j[2] as Vector3) * m, (j[3] as Vector3) * m]])
	return out


func _spider_rig() -> Dictionary:
	var key := "arach_spider"
	if MobRig.has(key):
		return MobRig.cached(key)
	var r := MobRig.new(6)
	var H := 0.5
	var body := r.bone("body", -1, Vector3(0, H, -0.12))
	var abd := r.bone("abdomen", body, Vector3(0, H + 0.03, 0.12))
	var chel_l := r.bone("chel_l", body, Vector3(-0.055, H - 0.02, -0.33))
	var chel_r := r.bone("chel_r", body, Vector3(0.055, H - 0.02, -0.33))
	var fang_l := r.bone("fang_l", chel_l, Vector3(-0.06, H - 0.17, -0.39))
	var fang_r := r.bone("fang_r", chel_r, Vector3(0.06, H - 0.17, -0.39))
	var palps := {}
	for side: float in [-1.0, 1.0]:
		var s := "l" if side < 0.0 else "r"
		var p0 := r.bone("palp_" + s, body, Vector3(side * 0.085, H - 0.05, -0.3))
		var p1 := r.bone("palp2_" + s, p0, Vector3(side * 0.13, H + 0.02, -0.44))
		palps[side] = [p0, p1]
	# Legs: hips round the carapace, a high knee, feet on a wide ellipse.
	var spec: Array = []
	var angles := [36.0, 72.0, 108.0, 146.0]
	var reach := [1.35, 1.15, 1.0, 1.25]
	for i in 4:
		var hip := Vector3(0.135, H - 0.025, lerpf(-0.27, -0.01, float(i) / 3.0))
		var a := deg_to_rad(float(angles[i]))
		var d := Vector3(sin(a), 0, -cos(a))
		var R: float = reach[i]
		var knee := hip + d * R * 0.32 + Vector3(0, 0.3, 0)
		var ankle := hip + d * R * 0.76
		ankle.y = 0.21
		var tip := hip + d * R
		tip.y = 0.0
		spec.append([hip, knee, ankle, tip])
	var legs := _leg_bones(r, body, spec)

	# Cephalothorax: a broad, low carapace with a raised eye mound in front.
	r.slot(S_BODY)
	_tube(r, [[Vector3(0, H - 0.01, -0.375), Vector2(0.035, 0.03), body], [Vector3(0, H + 0.02, -0.34), Vector2(0.1, 0.075), body],
		[Vector3(0, H + 0.025, -0.26), Vector2(0.155, 0.1), body], [Vector3(0, H + 0.01, -0.13), Vector2(0.18, 0.105), body],
		[Vector3(0, H, 0.0), Vector2(0.155, 0.09), body], [Vector3(0, H + 0.01, 0.075), Vector2(0.07, 0.05), body],
		[Vector3(0, H + 0.025, 0.115), Vector2(0.035, 0.03), {body: 0.5, abd: 0.5}]], 18, 0.05, 18)
	r.tufts(_hair(), 64, 0.1, 0.92, -120.0, 120.0, 0.05, 0.84, 3, 1.3)
	# Abdomen: swollen, banded, hairy, with spinnerets.
	r.slot(S_ABD)
	_tube(r, [[Vector3(0, H + 0.03, 0.1), Vector2(0.035, 0.03), {body: 0.4, abd: 0.6}], [Vector3(0, H + 0.06, 0.17), Vector2(0.17, 0.15), abd],
		[Vector3(0, H + 0.09, 0.31), Vector2(0.255, 0.22), abd], [Vector3(0, H + 0.1, 0.46), Vector2(0.27, 0.23), abd],
		[Vector3(0, H + 0.08, 0.6), Vector2(0.21, 0.18), abd], [Vector3(0, H + 0.045, 0.7), Vector2(0.1, 0.09), abd],
		[Vector3(0, H + 0.02, 0.74), Vector2(0.025, 0.025), abd]], 20, 0.05, 20)
	r.tufts(_hair(), 120, 0.06, 0.96, -180.0, 180.0, 0.065, 0.8, 5, 1.4)
	for side: float in [-1.0, 1.0]:
		r.slot(S_FANG).rigid(OrganicMesh.bezier("spider_spinneret", Vector3.ZERO, Vector3(0, -0.01, 0.03), Vector3(0, -0.03, 0.05), 0.016, 0.006, 4, 6), Transform3D(Basis(), Vector3(side * 0.025, H + 0.0, 0.725)), abd)
	# Chelicerae: bulbous, hairy, with curved fangs folding inwards.
	for side: float in [-1.0, 1.0]:
		var ch := chel_l if side < 0.0 else chel_r
		var fg := fang_l if side < 0.0 else fang_r
		var a := r.rest[ch]
		var b := r.rest[fg]
		r.slot(S_BODY).rigid(OrganicMesh.profile("spider_chel_%d" % int(side), a + Vector3(0, 0.03, 0.03), b, [[0.0, 0.05, 0.055], [0.35, 0.062, 0.062], [0.8, 0.045, 0.045], [1.0, 0.03, 0.03]], 10, 8), Transform3D(), ch)
		var fang := OrganicMesh.bezier("spider_fang_%d" % int(side), Vector3.ZERO, Vector3(-side * 0.025, -0.05, -0.01), Vector3(-side * 0.06, -0.075, 0.035), 0.02, 0.002, 7, 6)
		r.slot(S_FANG).rigid(fang, Transform3D(Basis(), b), fg)
		# Bristles on the chelicerae.
		for t in 6:
			var f := float(t) / 5.0
			var pos := a.lerp(b, 0.2 + f * 0.6) + Vector3(side * 0.04, 0.0, -0.035)
			var dir := Vector3(side * 0.4, -0.3, -1.0).normalized()
			var bb := Basis.looking_at(-dir, Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5)
			r.slot(S_BODY).rigid(_hair(), Transform3D(bb.scaled(Vector3.ONE * 0.05), pos), ch)
	# Pedipalps: short hairy leg-like feelers.
	for side: float in [-1.0, 1.0]:
		var pb: Array = palps[side]
		var j := _p([r.rest[pb[0]], r.rest[pb[1]], r.rest[pb[1]] + Vector3(side * 0.02, -0.14, -0.08)])
		r.slot(S_LEG).limb(j, [pb[0], pb[1]], [[0.0, 0.032, 0.032], [0.45, 0.03, 0.03], [0.5, 0.034, 0.034], [0.9, 0.028, 0.028], [1.0, 0.022, 0.022]], 12, 8, Vector3.UP, 0.03)
		r.tufts(_hair(), 10, 0.1, 1.0, 0.0, 360.0, 0.035, 0.6, 31 + int(side))
	# Legs: jointed tubes with knee / ankle swellings, setae and spines.
	for lg: Array in legs:
		var up: int = lg[0]
		var j: Array = lg[3]
		var side: float = lg[1]
		var hip: Vector3 = j[0]
		var inside := hip - Vector3(side * 0.07, -0.01, 0.0)
		var pts := _p([inside, hip, j[1], j[2], j[3]])
		r.slot(S_LEG).limb(pts, [body, up, up + 1, up + 2], [[0.0, 0.046, 0.046], [0.04, 0.05, 0.05], [0.12, 0.045, 0.045], [0.3, 0.039, 0.039],
			[0.335, 0.044, 0.044], [0.37, 0.037, 0.037], [0.74, 0.028, 0.028], [0.775, 0.032, 0.032], [0.81, 0.024, 0.024], [0.96, 0.014, 0.014], [1.0, 0.01, 0.01]],
			18, 8, Vector3.UP, 0.04)
		r.tufts(_hair(), 34, 0.04, 0.97, 0.0, 360.0, 0.055, 0.72, 7 + up, 1.4, false)
		r.slot(S_FANG).tufts(MobRig.tuft_mesh("spider_spine", 0.09, 0.05, 2), 5, 0.2, 0.8, -60.0, 60.0, 0.085, 0.35, 11 + up, 1.0, false)
		# Tarsal claws.
		var tip: Vector3 = j[3]
		var d := (tip - (j[2] as Vector3)).normalized()
		r.slot(S_FANG).rigid(OrganicMesh.bezier("spider_claw", Vector3.ZERO, Vector3(0, 0.0, -0.02), Vector3(0, -0.012, -0.03), 0.006, 0.001, 4, 4), Transform3D(Basis.looking_at(d, Vector3.UP), tip), up + 3)
	# Eyes: two big forward eyes, three pairs round them, on a mound.
	r.slot(S_BODY).rigid(OrganicMesh.blob("spider_mound", Vector3(0.085, 0.045, 0.07), 0.08, 3, 10), Transform3D(Basis(), Vector3(0, H + 0.075, -0.29)), body)
	var eyes := [[Vector3(0.026, H + 0.095, -0.345), 0.027], [Vector3(0.07, H + 0.08, -0.32), 0.019], [Vector3(0.036, H + 0.115, -0.3), 0.017], [Vector3(0.085, H + 0.098, -0.275), 0.017]]
	for e: Array in eyes:
		for side: float in [-1.0, 1.0]:
			var ep: Vector3 = e[0]
			r.slot(S_EYE).rigid(ModelKit.sphere(float(e[1]), 7), Transform3D(Basis(), Vector3(ep.x * side, ep.y, ep.z)), body)
	return r.build(key)


func _scorpion_rig() -> Dictionary:
	var key := "arach_scorpion"
	if MobRig.has(key):
		return MobRig.cached(key)
	var r := MobRig.new(6)
	var H := 0.24
	var body := r.bone("body", -1, Vector3(0, H, -0.18))
	var meso := r.bone("meso", body, Vector3(0, H + 0.01, -0.02))
	var meso2 := r.bone("meso2", meso, Vector3(0, H + 0.02, 0.2))
	var tj := [Vector3(0, H + 0.04, 0.39), Vector3(0, H + 0.18, 0.5), Vector3(0, H + 0.34, 0.53), Vector3(0, H + 0.48, 0.47), Vector3(0, H + 0.57, 0.36), Vector3(0, H + 0.585, 0.24)]
	var tail: Array[int] = []
	for i in tj.size():
		tail.append(r.bone("tail%d" % i, meso2 if i == 0 else tail[i - 1], tj[i]))
	var arms := {}
	for side: float in [-1.0, 1.0]:
		var s := "l" if side < 0.0 else "r"
		var a0 := r.bone("arm_" + s, body, Vector3(side * 0.09, H - 0.01, -0.31))
		var a1 := r.bone("arm2_" + s, a0, Vector3(side * 0.22, H + 0.04, -0.39))
		var hand := r.bone("hand_" + s, a1, Vector3(side * 0.22, H + 0.03, -0.52))
		var finger := r.bone("finger_" + s, hand, Vector3(side * 0.18, H + 0.03, -0.68))
		arms[side] = [a0, a1, hand, finger]
	var spec: Array = []
	var angles := [55.0, 80.0, 104.0, 128.0]
	var reach := [0.36, 0.4, 0.45, 0.52]
	for i in 4:
		var hip := Vector3(0.1, H - 0.03, lerpf(-0.27, -0.04, float(i) / 3.0))
		var a := deg_to_rad(float(angles[i]))
		var d := Vector3(sin(a), 0, -cos(a))
		var R: float = reach[i]
		var knee := hip + d * R * 0.4 + Vector3(0, 0.1, 0)
		var ankle := hip + d * R * 0.8
		ankle.y = 0.07
		var tip := hip + d * R
		tip.y = 0.0
		spec.append([hip, knee, ankle, tip])
	var legs := _leg_bones(r, body, spec)

	# Prosoma: flat carapace.
	r.slot(S_BODY)
	_tube(r, [[Vector3(0, H - 0.01, -0.37), Vector2(0.05, 0.025), body], [Vector3(0, H, -0.34), Vector2(0.11, 0.05), body],
		[Vector3(0, H + 0.005, -0.24), Vector2(0.15, 0.068), body], [Vector3(0, H + 0.005, -0.1), Vector2(0.165, 0.074), body],
		[Vector3(0, H + 0.005, -0.03), Vector2(0.165, 0.074), {body: 0.6, meso: 0.4}]], 14, 0.04, 18)
	# Median eyes on a tubercle, lateral eyes at the front corners.
	r.rigid(OrganicMesh.blob("scorp_tubercle", Vector3(0.035, 0.022, 0.04), 0.05, 3, 8), Transform3D(Basis(), Vector3(0, H + 0.07, -0.25)), body)
	for side: float in [-1.0, 1.0]:
		r.slot(S_EYE).rigid(ModelKit.sphere(0.013, 8), Transform3D(Basis(), Vector3(side * 0.016, H + 0.088, -0.255)), body)
		for t in 3:
			r.slot(S_EYE).rigid(ModelKit.sphere(0.008, 6), Transform3D(Basis(), Vector3(side * (0.09 + t * 0.012), H + 0.045, -0.335 + t * 0.012)), body)
	# Mesosoma: seven tergites with ridged edges.
	r.slot(S_ABD)
	var rows: Array = []
	for j in 7:
		var z0 := -0.04 + j * 0.06
		var w := 0.17 + 0.03 * sin(PI * (float(j) + 0.5) / 7.0) - (0.04 if j == 6 else 0.0)
		var bone_j: Variant = meso if z0 < 0.1 else meso2
		if z0 >= 0.1 and z0 < 0.16:
			bone_j = {meso: 0.5, meso2: 0.5}
		rows.append([Vector3(0, H + 0.01, z0), Vector2(w * 0.95, 0.07), bone_j])
		rows.append([Vector3(0, H + 0.02, z0 + 0.035), Vector2(w, 0.085), bone_j])
	rows.append([Vector3(0, H + 0.03, 0.39), Vector2(0.075, 0.06), {meso2: 0.5, tail[0]: 0.5}])
	_tube(r, rows, 44, 0.03, 18)
	# Metasoma: five segments with constrictions, arching over the back.
	var trows: Array = []
	var tr := [0.065, 0.06, 0.057, 0.054, 0.052]
	for k in 5:
		var a: Vector3 = tj[k]
		var b: Vector3 = tj[k + 1]
		var rr: float = tr[k]
		trows.append([a, Vector2(rr * 0.78, rr * 0.72), tail[k]])
		trows.append([a.lerp(b, 0.3), Vector2(rr, rr * 0.92), tail[k]])
		trows.append([a.lerp(b, 0.75), Vector2(rr * 0.98, rr * 0.9), tail[k]])
	trows.append([tj[5], Vector2(0.04, 0.04), tail[5]])
	_tube(r, trows, 40, 0.02, 12)
	# Keels: a double ridge of small knobs along each segment's top.
	r.tufts(OrganicMesh.blob("scorp_knob", Vector3(0.35, 0.5, 0.35), 0.1, 5, 6), 0, 0.05, 0.92, -25.0, 25.0, 0.022, 0.6, 9, 1.0, true, Vector2i(15, 2))
	# Telson: bulb, curved aculeus and the venom glow at its tip.
	var tb := tail[5]
	var tp: Vector3 = tj[5]
	r.slot(S_ABD).rigid(OrganicMesh.profile("scorp_bulb", tp + Vector3(0, 0.0, 0.02), tp + Vector3(0, -0.04, -0.13), [[0.0, 0.045, 0.045], [0.4, 0.07, 0.075], [0.85, 0.045, 0.045], [1.0, 0.02, 0.02]], 12, 10), Transform3D(), tb)
	var sting := OrganicMesh.bezier("scorp_sting", Vector3.ZERO, Vector3(0, -0.02, -0.07), Vector3(0, -0.1, -0.1), 0.022, 0.002, 7, 6)
	r.slot(S_FANG).rigid(sting, Transform3D(Basis(), tp + Vector3(0, -0.04, -0.12)), tb)
	r.slot(S_GLOW).rigid(ModelKit.sphere(0.013, 6), Transform3D(Basis(), tp + Vector3(0, -0.13, -0.215)), tb)
	# Chelae: arm, heavy swollen hand with a fixed finger, hinged movable finger.
	for side: float in [-1.0, 1.0]:
		var ab: Array = arms[side]
		var a0: int = ab[0]
		var a1: int = ab[1]
		var hand: int = ab[2]
		var fin: int = ab[3]
		var j := _p([r.rest[a0] - Vector3(side * 0.04, 0, -0.03), r.rest[a0], r.rest[a1], r.rest[hand]])
		r.slot(S_BODY).limb(j, [body, a0, a1], [[0.0, 0.04, 0.035], [0.15, 0.045, 0.04], [0.5, 0.05, 0.045], [0.55, 0.055, 0.05], [0.95, 0.05, 0.045], [1.0, 0.045, 0.04]], 14, 10, Vector3.UP, 0.03)
		var hp := r.rest[hand]
		var fp := r.rest[fin]
		# The hand (manus): bulbous, with granules.
		r.slot(S_BODY).rigid(OrganicMesh.profile("scorp_manus_%d" % int(side), hp + Vector3(0, 0, 0.03), fp + Vector3(side * 0.01, 0, 0.01), [[0.0, 0.045, 0.04], [0.2, 0.08, 0.06], [0.5, 0.1, 0.07, 0.0, side * 0.012], [0.8, 0.085, 0.06], [1.0, 0.05, 0.04]], 14, 12), Transform3D(), hand)
		# Fixed finger (outer) and movable finger (inner) curving to meet at the tips.
		r.slot(S_BODY).rigid(OrganicMesh.bezier("scorp_fixed_%d" % int(side), Vector3.ZERO, Vector3(side * 0.012, 0.0, -0.09), Vector3(-side * 0.03, 0.0, -0.16), 0.033, 0.006, 9, 7, 0.8), Transform3D(Basis(), fp + Vector3(side * 0.035, 0.0, 0.0)), hand)
		r.slot(S_BODY).rigid(OrganicMesh.bezier("scorp_finger_%d" % int(side), Vector3.ZERO, Vector3(-side * 0.012, 0.0, -0.09), Vector3(side * 0.028, 0.0, -0.155), 0.03, 0.006, 9, 7, 0.8), Transform3D(Basis(), fp + Vector3(-side * 0.032, 0.0, 0.0)), fin)
		r.slot(S_FANG).rigid(OrganicMesh.bezier("scorp_tip_a_%d" % int(side), Vector3.ZERO, Vector3(-side * 0.012, 0.0, -0.02), Vector3(-side * 0.025, 0.0, -0.03), 0.011, 0.002, 4, 5), Transform3D(Basis(), fp + Vector3(side * 0.01, 0.0, -0.135)), hand)
		r.slot(S_FANG).rigid(OrganicMesh.bezier("scorp_tip_b_%d" % int(side), Vector3.ZERO, Vector3(side * 0.012, 0.0, -0.02), Vector3(side * 0.025, 0.0, -0.03), 0.01, 0.002, 4, 5), Transform3D(Basis(), fp + Vector3(-side * 0.008, 0.0, -0.13)), fin)
		# Chelicerae: small pincers at the front of the carapace.
		r.slot(S_FANG).rigid(OrganicMesh.bezier("scorp_chel_%d" % int(side), Vector3.ZERO, Vector3(0, -0.005, -0.03), Vector3(-side * 0.012, -0.012, -0.05), 0.014, 0.003, 5, 5), Transform3D(Basis(), Vector3(side * 0.025, H - 0.01, -0.36)), body)
	# Legs.
	for lg: Array in legs:
		var up: int = lg[0]
		var j: Array = lg[3]
		var side: float = lg[1]
		var hip: Vector3 = j[0]
		var pts := _p([hip - Vector3(side * 0.05, -0.01, 0.0), hip, j[1], j[2], j[3]])
		r.slot(S_LEG).limb(pts, [body, up, up + 1, up + 2], [[0.0, 0.03, 0.026], [0.08, 0.032, 0.028], [0.36, 0.026, 0.024], [0.4, 0.029, 0.027],
			[0.75, 0.02, 0.019], [0.79, 0.022, 0.021], [0.95, 0.012, 0.012], [1.0, 0.008, 0.008]], 16, 8, Vector3.UP, 0.025)
		var tip: Vector3 = j[3]
		var d := (tip - (j[2] as Vector3)).normalized()
		r.slot(S_FANG).rigid(OrganicMesh.bezier("spider_claw", Vector3.ZERO, Vector3(0, 0.0, -0.02), Vector3(0, -0.012, -0.03), 0.006, 0.001, 4, 4), Transform3D(Basis.looking_at(d, Vector3.UP), tip), up + 3)
	# Pectines under the belly (comb organs).
	for side: float in [-1.0, 1.0]:
		r.slot(S_BODY).rigid(OrganicMesh.bezier("scorp_pectine_%d" % int(side), Vector3.ZERO, Vector3(side * 0.04, -0.01, 0.01), Vector3(side * 0.08, -0.005, 0.03), 0.01, 0.006, 5, 5), Transform3D(Basis(), Vector3(side * 0.02, H - 0.06, -0.03)), meso)
	return r.build(key)


# --- Animation ---------------------------------------------------------------------------

func _animate(delta: float) -> void:
	if skel == null:
		return
	var scorp := species == "scorpion"
	var p := action_progress()
	var w := action_weight(0.1, 0.2)
	var act := _action if p >= 0.0 and not _dead else ""
	_speed = damp(_speed, move_speed / size, 8.0, delta)
	_walk = damp(_walk, clampf(_speed / 0.4, 0.0, 1.0), 6.0, delta)
	var cycle := 0.55 if not scorp else 0.42
	_gait = fposmod(_gait + delta * _speed / cycle, 1.0)
	var breathe := sin(_time * 2.0)
	var rear := 0.0
	var lunge := 0.0
	var fang := 0.12 + sin(_time * 3.1) * 0.06
	var crouch := 0.0
	var sting := 0.0
	var pinch := 0.15 + sin(_time * 1.7) * 0.12
	var claw_reach := 0.0
	var flinch := 0.0
	match act:
		"attack", "bite":
			var wind := keys(p, [[0, 0], [0.3, 1.0], [0.42, 0.0], [1, 0]])
			var strike := keys(p, [[0, 0], [0.34, 0.0], [0.5, 1.0], [0.72, 0.7], [1, 0]])
			rear = 0.55 * wind
			lunge = 0.22 * strike - 0.05 * wind
			fang = lerpf(fang, 1.1, wind) * (1.0 - strike) - 0.25 * strike
			claw_reach = strike
			pinch = keys(p, [[0, 0.2], [0.35, 1.0], [0.52, 0.0], [1, 0.2]])
			if scorp:
				sting = keys(p, [[0, 0], [0.45, -0.4], [0.62, 1.0], [0.8, 0.6], [1, 0]])
		"attack2", "shoot", "throw", "cast":
			sting = keys(p, [[0, 0], [0.35, -0.6], [0.55, 1.0], [0.75, 0.8], [1, 0]])
			rear = 0.2 * maxf(0.0, -sting) if not scorp else 0.0
			lunge = 0.08 * maxf(0.0, sting)
			pinch = lerpf(pinch, 0.8, w)
		"lunge", "pounce":
			var coil := keys(p, [[0, 0], [0.25, 1.0], [0.4, 0.0], [1, 0]])
			var leap := keys(p, [[0, 0], [0.32, 0.0], [0.5, 1.0], [0.8, 0.5], [1, 0]])
			crouch = coil
			rear = 0.75 * leap
			lunge = 0.4 * leap
			fang = lerpf(fang, 1.2, w)
			claw_reach = leap
			pinch = lerpf(pinch, 1.0, leap)
		"roar", "howl", "summon", "slam", "spikes":
			rear = (0.9 if not scorp else 0.35) * w
			fang = lerpf(fang, 1.2 + sin(_time * 30.0) * 0.12, w)
			pinch = lerpf(pinch, 1.0, w)
			claw_reach = -0.6 * w
			sting = 0.25 * w
		"hit":
			flinch = sin(PI * clampf(p * 1.3, 0.0, 1.0))
	if hanging:
		crouch = 0.5
	_rear = damp(_rear, rear, 10.0, delta)
	_lunge = damp(_lunge, lunge, 14.0, delta)
	_fang = damp(_fang, fang, 18.0, delta)
	_crouch = damp(_crouch, crouch, 12.0, delta)
	_sting = damp(_sting, sting, 14.0, delta)
	_pinch = damp(_pinch, pinch, 16.0, delta)
	_claw_reach = damp(_claw_reach, claw_reach, 12.0, delta)
	_flinch = damp(_flinch, flinch, 20.0, delta)
	_curl = damp(_curl, 1.0 if _dead else 0.0, 4.0, delta)

	# --- Body.
	var g := _gait * TAU
	var body_rest := rest[0]
	var bob := breathe * 0.006 - absf(sin(g * 2.0)) * 0.012 * _walk - _crouch * 0.15 * _h - _flinch * 0.04
	var pos := body_rest + Vector3(0, bob + _rear * 0.08, -_lunge)
	pos.y = lerpf(pos.y, _h * 0.32, _curl)
	var pitch := _rear * (0.55 if not scorp else 0.25) - _crouch * 0.12 + _flinch * 0.18
	var roll := sin(g) * 0.025 * _walk + _flinch * 0.1
	place(0, pos, Basis.from_euler(Vector3(pitch * (1.0 - _curl), 0, roll)))
	if scorp:
		_pose_scorpion(delta, breathe)
	else:
		_pose_spider(breathe)
	_pose_legs(scorp)
	commit()


func _pose_spider(breathe: float) -> void:
	var abd: int = _b["abdomen"]
	fk(abd, Vector3(-0.08 * _rear + breathe * 0.02 + sin(_time * 1.3) * 0.03 + 0.1 * _curl, sin(_time * 0.8) * 0.05 * (1.0 - _curl), 0))
	for side: float in [-1.0, 1.0]:
		var s := "l" if side < 0.0 else "r"
		var ch: int = _b["chel_" + s]
		fk(ch, Vector3(_fang * 0.35, 0, side * _fang * 0.12))
		fk(_b["fang_" + s], Vector3(-_fang * 0.6, side * _fang * 0.7, 0))
		var pa: int = _b["palp_" + s]
		var wiggle := sin(_time * 4.0 + side * 1.7) * 0.18
		fk(pa, Vector3(wiggle - _rear * 0.5 + _curl * 0.8, side * 0.1, 0))
		fk(_b["palp2_" + s], Vector3(-wiggle * 0.6 + _curl * 0.8, 0, 0))


func _pose_scorpion(_delta: float, breathe: float) -> void:
	fk(_b["meso"], Vector3(breathe * 0.01, sin(_time * 0.7) * 0.02, 0))
	fk(_b["meso2"], Vector3(0, sin(_time * 0.7 - 0.6) * 0.03, 0))
	# Tail: sways while idle, cocks back, then stabs forward over the head.
	var n := _tail.size()
	for i in n:
		var f := float(i) / maxf(1.0, n - 1)
		var curl := -_sting * (0.42 if i < 4 else 0.15) + maxf(0.0, -_sting) * 0.0
		var idle := sin(_time * 1.3 + f * 1.5) * 0.05
		if _curl > 0.0:
			curl = lerpf(curl, 0.55 - f * 0.2, _curl)
		fk(_tail[i], Vector3(curl + idle, sin(_time * 0.9 + f) * 0.07 * (1.0 - _curl), 0))
	for side: float in [-1.0, 1.0]:
		var s := "l" if side < 0.0 else "r"
		var reach := _claw_reach
		# Arms swing forward to grab, spread wide to threaten.
		fk(_b["arm_" + s], Vector3(0.1 * maxf(0.0, -reach), side * (0.25 * reach - 0.4 * maxf(0.0, -reach)) + side * sin(_time * 0.6) * 0.04, side * 0.15 * maxf(0.0, -reach)))
		fk(_b["arm2_" + s], Vector3(0, -side * (0.35 * reach) + side * 0.05, 0))
		fk(_b["hand_" + s], Vector3(0, side * 0.2 * reach, 0))
		fk(_b["finger_" + s], Vector3(0, side * _pinch * 0.45, 0))


func _pose_legs(scorp: bool) -> void:
	var stride_k := 0.28 if not scorp else 0.22
	var lift_h := (0.16 if not scorp else 0.07)
	var duty := 0.55
	var body_b := gb[0]
	for leg: Dictionary in _legs:
		var up: int = leg["up"]
		var lo: int = leg["lo"]
		var ft: int = leg["foot"]
		var toe: int = leg["toe"]
		var side: float = leg["side"]
		var i: int = leg["i"]
		fk(up)
		var tip: Vector3 = leg["tip"]
		var hip := gp[up]
		var ph := fposmod(_gait + (0.5 if int(leg["group"]) == 1 else 0.0) + float(i) * 0.04, 1.0)
		var stride := stride_k * _walk * (1.0 if i != 3 else 1.1)
		var lift := 0.0
		if ph < duty:
			tip.z += stride * (ph / duty - 0.5)
		else:
			var s := (ph - duty) / (1.0 - duty)
			tip.z += stride * (0.5 - s * s * (3.0 - 2.0 * s))
			lift = sin(PI * s) * lift_h * _walk
		tip.y += lift
		tip.z -= _lunge * (0.5 if i < 2 else 0.25)
		# Front legs rise when rearing (threat posture / strike).
		if i < 2 and _rear > 0.01 and not scorp:
			var raised := hip + Vector3(side * (0.35 - i * 0.1), 0.45 - i * 0.12, -0.55 + i * 0.15) + Vector3(0, sin(_time * 6.0 + i + side) * 0.04, 0)
			tip = tip.lerp(raised, clampf(_rear * (1.0 - i * 0.35), 0.0, 1.0))
		if _curl > 0.0:
			# Death: the legs fold in under the body, knees up.
			var folded := Vector3(hip.x * 0.6, gp[0].y * 0.5, hip.z * 0.8 + (0.04 if i > 1 else -0.04))
			tip = tip.lerp(folded, _curl)
		if hanging:
			tip = tip.lerp(Vector3(hip.x * 1.6, hip.y - 0.25, hip.z * 1.3), 0.6)
		var off: Vector3 = leg["off"]
		var ankle := tip + off * (1.0 - _curl * 0.5)
		var pole := body_b * Vector3(side * 0.35, 1.0, 0.0)
		ik(up, lo, ft, ankle, pole)
		aim(ft, toe, tip - gp[ft], Vector3.UP, pole)
		gp[toe] = gp[ft] + gb[ft] * (rest[toe] - rest[ft])
		gb[toe] = gb[ft]


# --- Shared IK helpers (also used by the Broodmother, the dragon and Cerberus) ----------------

static func _ik_knee(a: Vector3, b: Vector3, la: float, lb: float, pole: Vector3) -> Vector3:
	var d := b - a
	var dist := clampf(d.length(), absf(la - lb) + 0.001, la + lb - 0.001)
	var dir := d.normalized() if d.length_squared() > 1e-8 else Vector3.DOWN
	var cos_a := clampf((la * la + dist * dist - lb * lb) / (2.0 * la * dist), -1.0, 1.0)
	var perp := pole - dir * pole.dot(dir)
	if perp.length_squared() < 1e-6:
		perp = Vector3.UP
	perp = perp.normalized()
	return a + dir * cos_a * la + perp * sqrt(1.0 - cos_a * cos_a) * la


## Points a segment node's +Y from `from` to `to`.
static func _orient(seg: Node3D, from: Vector3, to: Vector3) -> void:
	var y := to - from
	if y.length_squared() < 1e-8:
		return
	y = y.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 1e-6:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	seg.transform = Transform3D(Basis(x, y, z), from)
