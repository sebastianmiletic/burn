class_name QuadrupedModel
extends MobModel
## Four-legged animals: wolves (grey, dire, frost), hellhounds, bears, deer
## and stags, rabbits, mountain goats, boars and the reptilian bog lurker.
##
## Each is ONE smooth skinned body (MobRig) built from its family's anatomy
## (QuadrupedSpecies): a torso tube from the tail root to the skull with a
## deep chest, tucked loin and shoulder / haunch masses, legs that grow out of
## the body through shoulder blade and pelvis, a species head with hinged jaw,
## teeth, wet nose, glossy eyes and ears on their own bones, fur tufts on the
## silhouette (ruffs, manes, bristles, beards, the goat's skirt), hooves,
## padded clawed paws or webbed feet, antlers / horns / tusks / scutes.
## About 30 bones and 5-7 draw calls per animal; meshes are cached per kind
## and individuals vary by size and coat.
##
## Motion: feet planted by two-bone IK from a speed-blended gait (walk ->
## trot -> gallop with spine flex; hares bound, lurkers sprawl and swing their
## spine), head and tail follow-through, ear flicks, breathing; bite, lunge /
## pounce, rearing slam, roar / howl, flinch, and a collapse onto the side.
## Faces -Z. `grazing` lowers the head of prey animals while idle.

const S_BODY := 0
const S_DARK := 1
const S_HORN := 2
const S_IVORY := 3
const S_MOUTH := 4
const S_EYE := 5
const SLOTS := 6

const HIPS := 0
const SPINE := 1
const CHEST := 2
const NECK := 3
const NECK2 := 4
const HEAD := 5
const JAW := 6
const EAR_L := 7
const EAR_R := 8
const TAIL0 := 9

var species := "wolf"
var spec := {}
var fam := {}
var grazing := false
## Individual size (x the kind's base scale).
var k := 1.0

var _tail_bones: Array[int] = []
var _legs: Array = []   # {up, lo, foot, toe, front, side, rest_foot, rest_wrist, len}
var _gait := 0.0
var _speed := 0.0
var _trot := 0.0
var _gallop := 0.0
var _graze := 0.0
var _crouch := 0.0
var _lunge := 0.0
var _rear := 0.0
var _jaw := 0.0
var _head_p := 0.0
var _head_y := 0.0
var _alert := 0.0
var _death_pose := false
var _dead_gb: Array[Basis] = []
var _dead_gp := PackedVector3Array()
var _death_side := 1.0
var _ember_fx: GPUParticles3D
var _eye_glow := false


func _init(kind_name := "wolf", variant_seed := 0) -> void:
	species = kind_name if QuadrupedSpecies.KINDS.has(kind_name) else "wolf"
	spec = (QuadrupedSpecies.KINDS[species] as Dictionary).duplicate()
	fam = QuadrupedSpecies.FAMILIES[spec["family"]]
	var rng := RandomNumberGenerator.new()
	rng.seed = variant_seed
	k = float(spec.get("scale", 1.0)) * rng.randf_range(0.9, 1.1)
	# Coat variants within a kind.
	var coats: Dictionary = {
		"bear": [Color(0.3, 0.2, 0.13), Color(0.11, 0.09, 0.08), Color(0.45, 0.35, 0.24)],
		"wolf": [Color(0.36, 0.34, 0.31), Color(0.45, 0.36, 0.26), Color(0.25, 0.24, 0.23), Color(0.55, 0.52, 0.48)],
		"goat": [Color(0.85, 0.83, 0.78), Color(0.45, 0.38, 0.3), Color(0.25, 0.22, 0.2)],
		"rabbit": [Color(0.5, 0.42, 0.32), Color(0.55, 0.53, 0.5), Color(0.38, 0.3, 0.22)],
	}
	if coats.has(species):
		var list: Array = coats[species]
		spec["back"] = list[rng.randi() % list.size()]
		if species == "bear":
			spec["belly"] = (spec["back"] as Color).lightened(0.12)
	var tint := rng.randf_range(-0.06, 0.06)
	spec["back"] = (spec["back"] as Color).lightened(tint) if tint > 0.0 else (spec["back"] as Color).darkened(-tint)
	_eye_glow = float(spec.get("eye_e", 0.0)) > 0.0
	dissolve_delay = 1.6
	durations["howl"] = 1.8
	durations["lunge"] = 0.75
	durations["pounce"] = 0.85
	durations["slam"] = 1.2
	durations["roar"] = 1.3


func _body_len() -> float:
	var t: Array = fam["torso"]
	return absf(float(t[0][0]) - float(t[t.size() - 1][0])) * k


func _ember_extents() -> Vector3:
	return Vector3(0.3, 0.3, 0.6) * _body_len()


func _lod_size() -> float:
	return maxf(0.6, _body_len() * 1.2)


# --- Build -------------------------------------------------------------------------------

func _build() -> void:
	var data := _rig_data()
	rig_instance(data, _materials(), k, 1.2)
	body_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_tail_bones.clear()
	var names: PackedStringArray = data["names"]
	for i in names.size():
		if names[i].begins_with("tail"):
			_tail_bones.append(i)
	_legs.clear()
	for li in 4:
		var front := li < 2
		var side := -1.0 if li % 2 == 0 else 1.0
		var b0 := names.find("%s%s_up" % ["f" if front else "h", "l" if side < 0.0 else "r"])
		var leg := {"up": b0, "lo": b0 + 1, "foot": b0 + 2, "toe": b0 + 3, "front": front, "side": side}
		leg["rest_foot"] = Vector3(rest[b0 + 3].x, 0.0, rest[b0 + 3].z)
		leg["lift0"] = rest[b0 + 3].y
		leg["wrist_off"] = rest[b0 + 2] - rest[b0 + 3]
		leg["len"] = rest[b0].distance_to(rest[b0 + 1]) + rest[b0 + 1].distance_to(rest[b0 + 2]) + rest[b0 + 2].distance_to(rest[b0 + 3])
		_legs.append(leg)
	if spec.get("embers", false):
		var at := follow(CHEST, "Embers")
		_ember_fx = ModelKit.embers(at, 22, Vector3(0.12, 0.1, 0.25), 0.9, 0.06, 1.2)
		_ember_fx.position = Vector3(0, 0.15, 0.1)
		_ember_fx.emitting = true


func _materials() -> Array:
	var fur := bool(spec.get("fur", true))
	var back: Color = spec["back"]
	var extra := {"use_rest": true, "accent": spec["accent"], "accent_mode": 3, "accent_amount": 0.5, "accent_scale": 2.0,
		"bump_distance": 25.0}
	if spec.has("cracks"):
		extra.merge({"glow_mode": 2, "glow_color": spec["cracks"], "glow_energy": 2.6, "glow_amount": 0.0, "glow_pulse": 0.6, "glow_sparsity": 0.85}, true)
	var body: ShaderMaterial
	if fur:
		extra["pattern_scale"] = 22.0
		extra["bump"] = 1.1
		extra["rim"] = 0.55
		body = CreatureSkin.fur(back, spec["belly"], extra)
	else:
		extra["pattern_scale"] = 9.0
		extra["wet"] = 0.45
		extra["bump"] = 1.4
		extra["accent_mode"] = 2
		extra["accent_amount"] = 0.35
		extra["accent_scale"] = 3.0
		body = CreatureSkin.scales(back, spec["belly"], 9.0, extra)
	var dark := CreatureSkin.hide(Color(0.05, 0.045, 0.045), Color(0.08, 0.07, 0.07), {"use_rest": true, "pattern_scale": 60.0,
		"roughness": 0.3, "wet": 0.5, "specular_amount": 0.6, "bump": 0.4})
	var horn_col := Color(0.12, 0.1, 0.09)
	if species == "goat":
		horn_col = Color(0.2, 0.18, 0.16)
	var horn := CreatureSkin.keratin(horn_col, {"use_rest": true, "pattern_scale": 40.0, "roughness": 0.45, "bump": 0.6})
	var ivory_col := Color(0.86, 0.82, 0.7)
	if spec.get("antlers", false):
		ivory_col = Color(0.55, 0.45, 0.34)
	var ivory := CreatureSkin.keratin(ivory_col, {"use_rest": true, "pattern_scale": 30.0, "bump": 0.5,
		"roughness": 0.75 if spec.get("antlers", false) else 0.35})
	var mouth := CreatureSkin.mouth(Color(0.42, 0.12, 0.12))
	var eye: Material
	if _eye_glow:
		eye = CreatureSkin.eye(spec["eye"], float(spec["eye_e"]), 0.1)
	else:
		eye = CreatureSkin.smooth(spec["eye"], spec["eye"], {"roughness": 0.04, "specular_amount": 1.0, "rim": 0.0, "bump": 0.0})
	return [body, dark, horn, ivory, mouth, eye]


func _rig_data() -> Dictionary:
	var key := "quad_" + species
	if MobRig.has(key):
		return MobRig.cached(key)
	var r := MobRig.new(SLOTS)
	var bl: Array = fam["bones"]
	var bulk := float(spec.get("bulk", 1.0))
	r.bone("hips", -1, bl[0])
	r.bone("spine", HIPS, bl[1])
	r.bone("chest", SPINE, bl[2])
	r.bone("neck", CHEST, bl[3])
	r.bone("neck2", NECK, bl[4])
	r.bone("head", NECK2, bl[5])
	var hp: Vector3 = bl[5]
	var jaw_at: Vector3 = hp + _jaw_offset()
	r.bone("jaw", HEAD, jaw_at)
	var ear_at := _ear_offset()
	r.bone("ear_l", HEAD, hp + Vector3(-ear_at.x, ear_at.y, ear_at.z))
	r.bone("ear_r", HEAD, hp + ear_at)
	var tj: Array = fam["tail"]
	var tail_bones: Array[int] = []
	for i in tj.size() - 1:
		tail_bones.append(r.bone("tail%d" % i, HIPS if i == 0 else tail_bones[i - 1], tj[i]))
	var leg_joints := {}
	for li in 4:
		var front := li < 2
		var side := -1.0 if li % 2 == 0 else 1.0
		var j: Array = fam["front" if front else "hind"]
		var pts := PackedVector3Array()
		for p: Vector3 in j:
			pts.append(Vector3(p.x * side * bulk, p.y, p.z))
		var pre := "%s%s_" % ["f" if front else "h", "l" if side < 0.0 else "r"]
		var up := r.bone(pre + "up", CHEST if front else HIPS, pts[1])
		r.bone(pre + "lo", up, pts[2])
		r.bone(pre + "foot", up + 1, pts[3])
		r.bone(pre + "toe", up + 2, pts[4])
		leg_joints[li] = [pts, up]

	# --- Torso: one tube from the tail root through the neck to the skull.
	var rows: Array = fam["torso"]
	var path := PackedVector3Array()
	var radii := PackedVector2Array()
	var pbs: Array = []
	var centre_bones := [HIPS, SPINE, CHEST, NECK, NECK2, HEAD]
	for row: Array in rows:
		var p := Vector3(0, float(row[1]), float(row[0]))
		path.append(p)
		radii.append(Vector2(float(row[2]) * bulk, float(row[3]) * lerpf(1.0, bulk, 0.6)))
		var best := HIPS
		var best_d := INF
		for b: int in centre_bones:
			var d := p.distance_to(r.rest[b])
			if d < best_d:
				best_d = d
				best = b
		pbs.append(best)
	var rs := MobRig.resample(path, radii, pbs, rows.size() * 3)
	var fine: PackedVector3Array = rs[0]
	var fine_r: PackedVector2Array = rs[1]
	var fine_b: Array = rs[2]
	var len_total := absf(float(rows[0][0]) - float(rows[rows.size() - 1][0]))
	r.slot(S_BODY).tube(fine, fine_r, fine_b, len_total * 0.16, 18)
	_body_tufts(r)

	# --- Tail.
	var tpath := PackedVector3Array()
	var trad := PackedVector2Array()
	var tbw: Array = []
	var tr: Array = fam["tail_r"]
	var croc := bool(fam.get("sprawl", false))
	tpath.append((tj[0] as Vector3) + ((tj[0] as Vector3) - (tj[1] as Vector3)).normalized() * float(tr[0]) * 1.2)
	trad.append(Vector2(float(tr[0]), float(tr[0])) * 0.8)
	tbw.append({HIPS: 0.6, tail_bones[0]: 0.4})
	for i in tj.size():
		tpath.append(tj[i])
		var rr := float(tr[i])
		trad.append(Vector2(rr, rr * (0.8 if croc else 1.0)))
		tbw.append(tail_bones[mini(i, tail_bones.size() - 1)])
	var trs := MobRig.resample(tpath, trad, tbw, tpath.size() * 4)
	var tfine: PackedVector3Array = trs[0]
	var tfr: PackedVector2Array = trs[1]
	var tfb: Array = trs[2]
	r.tube(tfine, tfr, tfb, 0.06, 12 if not croc else 14)
	_tail_tufts(r)

	# --- Legs.
	for li in 4:
		var pts: PackedVector3Array = leg_joints[li][0]
		var up: int = leg_joints[li][1]
		var front := li < 2
		var prof: Array = fam["front_prof" if front else "hind_prof"]
		var scaled: Array = []
		for row: Array in prof:
			var rw := row.duplicate()
			rw[1] = float(rw[1]) * bulk
			rw[2] = float(rw[2]) * bulk
			scaled.append(rw)
		var root := CHEST if front else HIPS
		r.slot(S_BODY).limb(pts, [root, up, up + 1, up + 2], scaled, 22, 12, Vector3.BACK, 0.05 * float(fam["gait"]["cycle"]),
			{root: 1.0}, pts[0].distance_to(pts[1]) * 1.1)
		_leg_tufts(r, front)
		_foot(r, pts, up + 3, (scaled[scaled.size() - 1] as Array)[1], li % 2 == 0)

	# --- Head.
	_head(r, hp, jaw_at)
	return r.build(key)


func _jaw_offset() -> Vector3:
	match String(fam["head"]):
		"bear":
			return Vector3(0, -0.07, -0.02)
		"deer":
			return Vector3(0, -0.04, -0.02)
		"goat":
			return Vector3(0, -0.04, -0.01)
		"boar":
			return Vector3(0, -0.07, -0.02)
		"hare":
			return Vector3(0, -0.018, -0.02)
		"croc":
			return Vector3(0, -0.035, 0.02)
	return Vector3(0, -0.03, -0.02)


func _ear_offset() -> Vector3:
	match String(fam["head"]):
		"bear":
			return Vector3(0.11, 0.1, 0.02)
		"deer":
			return Vector3(0.045, 0.05, 0.03)
		"goat":
			return Vector3(0.045, 0.035, 0.02)
		"boar":
			return Vector3(0.08, 0.1, 0.02)
		"hare":
			return Vector3(0.018, 0.03, 0.01)
		"croc":
			return Vector3(0.08, 0.06, 0.02)
	return Vector3(0.04, 0.05, 0.0)


# --- Fur ------------------------------------------------------------------------------------

func _tuft_mesh() -> Mesh:
	return MobRig.tuft_mesh("quad", 0.2, 0.18)


func _body_tufts(r: MobRig) -> void:
	var fl := float(spec.get("fur_len", 1.0))
	if not spec.get("fur", true):
		# Osteoderms: tidy rows of keeled scutes along the back.
		var scute := OrganicMesh.blob("quad_scute", Vector3(0.45, 0.35, 0.5), 0.1, 3, 8)
		r.slot(S_BODY).tufts(scute, 0, 0.08, 0.95, -55.0, 55.0, 0.075, 0.92, 11, 1.0, true, Vector2i(16, 6))
		return
	var tm := _tuft_mesh()
	var base := 0.035 * fl
	match String(fam["head"]):
		"canine":
			# Shaggy back and flanks, a thick ruff round the neck and chest, a fringe under the belly.
			r.tufts(tm, 70, 0.05, 0.75, -110.0, 110.0, base, 0.82, 3)
			r.tufts(tm, 46, 0.72, 0.97, -180.0, 180.0, base * (2.0 if spec.get("ruff", false) else 1.4), 0.6, 5, 1.3)
			r.tufts(tm, 22, 0.4, 0.8, 150.0, 210.0, base * 1.1, 0.7, 7)
			if spec.get("horns", false):
				r.tufts(MobRig.tuft_mesh("quad_spike", 0.14, 0.05), 12, 0.6, 0.95, -25.0, 25.0, 0.07, 0.35, 9)
		"bear":
			r.tufts(tm, 90, 0.05, 0.9, -130.0, 130.0, base * 1.4, 0.85, 3, 1.2)
			r.tufts(tm, 30, 0.2, 0.75, 140.0, 220.0, base * 1.6, 0.6, 7, 1.2)
		"deer":
			r.tufts(tm, 26, 0.05, 0.72, -90.0, 90.0, base * 0.7, 0.92, 3)
			if spec.get("mane", false):
				r.tufts(tm, 34, 0.74, 0.97, 100.0, 260.0, base * 2.4, 0.55, 5, 1.2)
		"goat":
			# Long white coat: a skirt hanging from the flanks, a shaggy crest.
			r.tufts(tm, 60, 0.05, 0.85, -100.0, 100.0, base * 1.1, 0.85, 3, 1.2)
			r.tufts(tm, 44, 0.1, 0.8, 95.0, 265.0, base * 2.6, 0.25, 5, 1.1, false)
			r.tufts(tm, 20, 0.72, 0.98, -40.0, 40.0, base * 1.6, 0.7, 7)
		"boar":
			# Coarse bristles and a tall crest of them along the spine.
			r.tufts(MobRig.tuft_mesh("quad_bristle", 0.12, 0.08), 34, 0.2, 0.98, -12.0, 12.0, 0.085, 0.42, 9, 1.3, false)
			r.tufts(tm, 70, 0.05, 0.95, -150.0, 150.0, base * 0.9, 0.85, 3)
		"hare":
			r.tufts(tm, 40, 0.0, 1.0, -180.0, 180.0, 0.012, 0.85, 3, 1.3)


func _tail_tufts(r: MobRig) -> void:
	var tm := _tuft_mesh()
	match String(fam["head"]):
		"canine":
			# The brush: long fur all round, longest in the middle.
			r.tufts(tm, 40, 0.12, 0.85, -180.0, 180.0, 0.075 * float(spec.get("fur_len", 1.0)), 0.75, 13, 1.4)
			r.tufts(tm, 14, 0.8, 1.0, -180.0, 180.0, 0.05, 0.85, 15, 1.2)
		"deer":
			r.tufts(tm, 14, 0.3, 1.0, 120.0, 240.0, 0.05, 0.8, 13, 1.3)
		"boar":
			r.tufts(tm, 6, 0.85, 1.0, -180.0, 180.0, 0.04, 0.9, 13)
		"croc":
			# Twin crests of tail scutes merging into one.
			var crest := OrganicMesh.blob("quad_crest", Vector3(0.18, 0.5, 0.35), 0.1, 5, 6)
			r.tufts(crest, 0, 0.05, 0.98, -25.0, 25.0, 0.09, 0.15, 17, 1.0, false, Vector2i(18, 2))


func _leg_tufts(r: MobRig, front: bool) -> void:
	match String(fam["head"]):
		"canine":
			r.tufts(_tuft_mesh(), 10 if front else 14, 0.1, 0.5, 0.0, 360.0, 0.03 * float(spec.get("fur_len", 1.0)), 0.85, 19 + int(front))
		"bear":
			r.tufts(_tuft_mesh(), 16, 0.1, 0.8, 0.0, 360.0, 0.06, 0.85, 19 + int(front), 1.2)
		"goat":
			r.tufts(_tuft_mesh(), 12, 0.05, 0.5, 0.0, 360.0, 0.06, 0.5, 23 + int(front))


# --- Feet -----------------------------------------------------------------------------------

func _foot(r: MobRig, pts: PackedVector3Array, toe: int, foot_r: float, left: bool) -> void:
	var p := pts[pts.size() - 1]
	var s := 1.0 if left else -1.0
	match String(fam["foot"]):
		"paw":
			var u := foot_r / 0.023
			r.slot(S_BODY).rigid(OrganicMesh.blob("quad_paw", Vector3(0.03, 0.024, 0.036) * u, 0.08, 3, 10), Transform3D(Basis(), p + Vector3(0, -0.008, -0.012) * u), toe)
			for t in 4:
				var x := (float(t) - 1.5) * 0.0145 * u
				var z := (-0.04 + absf(float(t) - 1.5) * 0.006) * u
				r.slot(S_BODY).rigid(OrganicMesh.blob("quad_toe", Vector3(0.0105, 0.012, 0.014) * u, 0.05, 5, 8), Transform3D(Basis(), p + Vector3(x, -0.022 * u, z)), toe)
				r.slot(S_HORN).rigid(OrganicMesh.bezier("quad_claw", Vector3.ZERO, Vector3(0, 0.002, -0.012), Vector3(0, -0.01, -0.02), 0.0045, 0.0008, 4, 5), Transform3D(Basis().scaled(Vector3.ONE * u), p + Vector3(x, -0.022 * u, z - 0.011 * u)), toe)
			r.slot(S_DARK).rigid(OrganicMesh.blob("quad_pad", Vector3(0.022, 0.008, 0.02) * u, 0.1, 9, 8), Transform3D(Basis(), p + Vector3(0, -0.03 * u, -0.008 * u)), toe)
		"bear":
			r.slot(S_BODY).rigid(OrganicMesh.blob("quad_bpaw", Vector3(0.1, 0.055, 0.15), 0.1, 3, 12), Transform3D(Basis(), p + Vector3(0, -0.01, -0.06)), toe)
			for t in 5:
				var x := (float(t) - 2.0) * 0.038
				var z := -0.18 + absf(float(t) - 2.0) * 0.015
				r.slot(S_HORN).rigid(OrganicMesh.bezier("quad_bclaw", Vector3.ZERO, Vector3(0, 0.01, -0.04), Vector3(0, -0.04, -0.07), 0.012, 0.002, 5, 5), Transform3D(Basis(), p + Vector3(x, -0.01, z)), toe)
		"hoof":
			var u := foot_r / 0.016
			# Pastern down to a cloven hoof, dewclaws behind the fetlock.
			r.slot(S_BODY).rigid(OrganicMesh.profile("quad_pastern", Vector3(0, 0.012, 0.004), Vector3(0, -0.05, -0.016), [[0.0, 0.017, 0.02], [0.6, 0.015, 0.018], [1.0, 0.016, 0.02]], 10, 4, Vector3.BACK), Transform3D(Basis().scaled(Vector3.ONE * u), p), toe)
			for h: float in [-1.0, 1.0]:
				var hm := OrganicMesh.profile("quad_hoof", Vector3(0, 0.0, 0.0), Vector3(0, -0.034, -0.012), [[0.0, 0.009, 0.016], [0.5, 0.011, 0.021], [1.0, 0.012, 0.024]], 8, 5, Vector3.BACK)
				r.slot(S_HORN).rigid(hm, Transform3D(Basis().scaled(Vector3.ONE * u), p + Vector3(h * 0.009, -0.05, -0.02) * u), toe)
				r.slot(S_HORN).rigid(OrganicMesh.blob("quad_dew", Vector3(0.005, 0.008, 0.005), 0.1, 3, 6), Transform3D(Basis().scaled(Vector3.ONE * u), p + Vector3(h * 0.011, -0.005, 0.02) * u), toe)
		"hare":
			r.slot(S_BODY).rigid(OrganicMesh.blob("quad_hpaw", Vector3(0.016, 0.012, 0.03), 0.1, 3, 8), Transform3D(Basis(), p + Vector3(0, 0.0, -0.01)), toe)
		"webbed":
			r.slot(S_BODY).rigid(OrganicMesh.blob("quad_wpalm", Vector3(0.06, 0.025, 0.06), 0.1, 3, 10), Transform3D(Basis(), p + Vector3(0, -0.005, -0.02)), toe)
			for t in 4:
				var a := lerpf(-0.6, 0.6, float(t) / 3.0) * s
				var dir := Vector3(sin(a), 0, -cos(a))
				r.slot(S_BODY).rigid(OrganicMesh.bezier("quad_wtoe", Vector3.ZERO, Vector3(0, 0.005, -0.05), Vector3(0, -0.01, -0.1), 0.016, 0.008, 5, 6), Transform3D(Basis(Vector3.UP, -a), p + dir * 0.03 + Vector3(0, -0.008, 0)), toe)
				r.slot(S_HORN).rigid(OrganicMesh.bezier("quad_wclaw", Vector3.ZERO, Vector3(0, 0.0, -0.02), Vector3(0, -0.01, -0.035), 0.007, 0.001, 4, 5), Transform3D(Basis(Vector3.UP, -a), p + dir * 0.13 + Vector3(0, -0.015, 0)), toe)


# --- Heads ----------------------------------------------------------------------------------

## Rigid part on a head bone, given in head-local coordinates (origin `at`).
func _hp(r: MobRig, slot_i: int, mesh: Mesh, at: Vector3, local: Transform3D, b: int) -> void:
	r.slot(slot_i).rigid(mesh, Transform3D(local.basis, at + local.origin), b)


func _put(pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot).scaled_local(scl) if scl != Vector3.ONE else Basis.from_euler(rot), pos)


func _head(r: MobRig, hp: Vector3, jaw_at: Vector3) -> void:
	var kind := String(fam["head"])
	var jl := jaw_at - hp
	var g := {}
	match kind:
		"canine":
			g = {"skull_a": Vector3(0, 0.0, 0.05), "skull_b": Vector3(0, -0.024, -0.245),
				"skull": [[0.0, 0.036, 0.04, 0.0], [0.1, 0.058, 0.055, 0.012], [0.24, 0.068, 0.058, 0.016], [0.36, 0.058, 0.05, 0.012],
					[0.47, 0.044, 0.041, 0.0], [0.6, 0.034, 0.033, -0.007], [0.8, 0.027, 0.029, -0.007], [0.93, 0.021, 0.025, -0.005], [1.0, 0.011, 0.014, -0.004]],
				"jaw_b": Vector3(0, -0.006, -0.205), "jaw": [[0.0, 0.04, 0.024], [0.3, 0.034, 0.02], [0.7, 0.024, 0.015], [1.0, 0.013, 0.009]],
				"nose": [Vector3(0, -0.006, -0.238), Vector3(0.019, 0.015, 0.014)], "eye": [Vector3(0.037, 0.03, -0.098), 0.0115, 0.35],
				"ear": [0.085, 0.03, "point"], "fangs": [Vector3(0.017, -0.03, -0.19), 0.028], "brow": true}
		"bear":
			g = {"skull_a": Vector3(0, 0.02, 0.1), "skull_b": Vector3(0, -0.06, -0.37),
				"skull": [[0.0, 0.1, 0.1], [0.18, 0.15, 0.135, 0.02], [0.36, 0.14, 0.12, 0.02], [0.52, 0.1, 0.09, -0.005],
					[0.7, 0.078, 0.075, -0.02], [0.9, 0.062, 0.06, -0.025], [1.0, 0.035, 0.035, -0.025]],
				"jaw_b": Vector3(0, -0.02, -0.3), "jaw": [[0.0, 0.08, 0.05], [0.4, 0.065, 0.04], [0.8, 0.045, 0.03], [1.0, 0.03, 0.02]],
				"nose": [Vector3(0, -0.035, -0.365), Vector3(0.036, 0.026, 0.022)], "eye": [Vector3(0.07, 0.035, -0.17), 0.013, 0.3],
				"ear": [0.06, 0.05, "round"], "fangs": [Vector3(0.035, -0.085, -0.31), 0.035], "brow": true}
		"deer":
			g = {"skull_a": Vector3(0, 0.03, 0.05), "skull_b": Vector3(0, -0.085, -0.27),
				"skull": [[0.0, 0.042, 0.048], [0.15, 0.054, 0.055, 0.01], [0.3, 0.05, 0.05, 0.006], [0.45, 0.04, 0.042, -0.004],
					[0.7, 0.03, 0.035, -0.008], [0.9, 0.026, 0.03, -0.008], [1.0, 0.016, 0.02, -0.006]],
				"jaw_b": Vector3(0, -0.06, -0.21), "jaw": [[0.0, 0.035, 0.022], [0.5, 0.026, 0.017], [1.0, 0.016, 0.01]],
				"nose": [Vector3(0, -0.075, -0.266), Vector3(0.018, 0.014, 0.012)], "eye": [Vector3(0.043, 0.02, -0.06), 0.014, 0.75],
				"ear": [0.15, 0.048, "leaf"], "brow": false}
		"goat":
			g = {"skull_a": Vector3(0, 0.02, 0.04), "skull_b": Vector3(0, -0.09, -0.22),
				"skull": [[0.0, 0.04, 0.045], [0.18, 0.05, 0.055, 0.012], [0.35, 0.046, 0.05, 0.012], [0.55, 0.036, 0.04, 0.004],
					[0.8, 0.028, 0.032, -0.002], [1.0, 0.018, 0.022, -0.004]],
				"jaw_b": Vector3(0, -0.07, -0.17), "jaw": [[0.0, 0.032, 0.02], [0.6, 0.024, 0.015], [1.0, 0.015, 0.01]],
				"nose": [Vector3(0, -0.085, -0.215), Vector3(0.015, 0.012, 0.01)], "eye": [Vector3(0.042, 0.02, -0.045), 0.012, 0.8],
				"ear": [0.09, 0.03, "side"], "brow": false}
		"boar":
			g = {"skull_a": Vector3(0, 0.05, 0.08), "skull_b": Vector3(0, -0.07, -0.34),
				"skull": [[0.0, 0.11, 0.13], [0.2, 0.11, 0.12, 0.01], [0.42, 0.085, 0.09, 0.0], [0.65, 0.06, 0.065, -0.01],
					[0.9, 0.048, 0.05, -0.012], [1.0, 0.046, 0.046, -0.012]],
				"jaw_b": Vector3(0, -0.03, -0.27), "jaw": [[0.0, 0.08, 0.04], [0.5, 0.055, 0.03], [1.0, 0.035, 0.02]],
				"nose": [Vector3(0, -0.075, -0.345), Vector3(0.045, 0.04, 0.012)], "eye": [Vector3(0.068, 0.04, -0.1), 0.008, 0.5],
				"ear": [0.09, 0.045, "point"], "brow": true}
		"hare":
			g = {"skull_a": Vector3(0, 0.0, 0.03), "skull_b": Vector3(0, -0.02, -0.07),
				"skull": [[0.0, 0.026, 0.028], [0.35, 0.033, 0.032, 0.002], [0.7, 0.025, 0.026, -0.003], [1.0, 0.012, 0.013, -0.006]],
				"jaw_b": Vector3(0, 0.0, -0.045), "jaw": [[0.0, 0.016, 0.01], [1.0, 0.008, 0.006]],
				"nose": [Vector3(0, -0.016, -0.075), Vector3(0.007, 0.006, 0.005)], "eye": [Vector3(0.025, 0.012, -0.022), 0.0095, 0.85],
				"ear": [0.11, 0.022, "long"], "brow": false}
		"croc":
			g = {"skull_a": Vector3(0, 0.0, 0.1), "skull_b": Vector3(0, -0.02, -0.62),
				"skull": [[0.0, 0.14, 0.08], [0.15, 0.15, 0.075], [0.35, 0.1, 0.052, -0.012], [0.6, 0.074, 0.038, -0.017],
					[0.85, 0.064, 0.033, -0.017], [0.95, 0.07, 0.035, -0.016], [1.0, 0.04, 0.024, -0.016]],
				"jaw_b": Vector3(0, -0.004, -0.6), "jaw": [[0.0, 0.13, 0.04], [0.4, 0.088, 0.028], [0.8, 0.064, 0.023], [1.0, 0.05, 0.018]],
				"nose": [Vector3(0, 0.02, -0.6), Vector3(0.03, 0.012, 0.02)], "eye": [Vector3(0.07, 0.075, -0.06), 0.022, 0.4],
				"ear": [0.0, 0.0, "none"], "brow": true}
	var skull := OrganicMesh.profile("qh_skull_" + species, g["skull_a"], g["skull_b"], g["skull"], 16, 16)
	_hp(r, S_BODY, skull, hp, Transform3D(), HEAD)
	var jaw := OrganicMesh.profile("qh_jaw_" + species, Vector3(0, 0, 0.03), g["jaw_b"], g["jaw"], 12, 10)
	_hp(r, S_BODY, jaw, jaw_at, Transform3D(), JAW)
	# Mouth: dark lips along the jaw line, wet inside, tongue.
	var jb: Vector3 = g["jaw_b"]
	_hp(r, S_MOUTH, OrganicMesh.blob("qh_mouth_" + species, Vector3(absf(float(g["jaw"][0][1])) * 0.7, absf(float(g["jaw"][0][2])) * 0.5, jb.length() * 0.45), 0.05, 3, 10), jaw_at, _put(Vector3(0, 0.008, jb.z * 0.5)), JAW)
	var nose: Array = g["nose"]
	_hp(r, S_DARK, OrganicMesh.blob("qh_nose_" + species, nose[1], 0.12, 5, 10), hp, _put(nose[0]), HEAD)
	# Eyes: a glossy ball with a pupil, sunk under a brow, turned outwards.
	var ev: Array = g["eye"]
	for side: float in [-1.0, 1.0]:
		var ep: Vector3 = ev[0]
		ep.x *= side
		var er := float(ev[1])
		var out_dir := Vector3(side * float(ev[2]), 0.1, -1.0).normalized()
		_hp(r, S_EYE, ModelKit.sphere(er, 10), hp, _put(ep), HEAD)
		if not _eye_glow:
			var pb := Basis.looking_at(out_dir, Vector3.UP).scaled_local(Vector3(0.62 if kind != "goat" else 0.9, 0.62 if kind != "goat" else 0.35, 0.3))
			_hp(r, S_DARK, ModelKit.sphere(er * 0.98, 8), hp, Transform3D(pb, ep + out_dir * er * 0.42), HEAD)
		# Lids: a ring of skin round the eye.
		var lid := BossKit.torus("qh_lid_%d" % int(er * 1000.0), er * 0.95, er * 0.28, 12, 5)
		_hp(r, S_DARK if kind in ["deer", "hare", "goat"] else S_BODY, lid, hp, Transform3D(Basis.looking_at(out_dir, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5), ep + out_dir * er * 0.15), HEAD)
		if g.get("brow", false):
			_hp(r, S_BODY, OrganicMesh.blob("qh_brow_" + species, Vector3(er * 1.6, er * 0.7, er * 1.4), 0.15, 7, 8), hp, _put(ep + Vector3(-side * er * 0.2, er * 0.9, er * 0.4), Vector3(0.2, side * 0.3, 0)), HEAD)
	# Ears on their own bones.
	var ear: Array = g["ear"]
	if String(ear[2]) != "none":
		for side: float in [-1.0, 1.0]:
			var eb := EAR_L if side < 0.0 else EAR_R
			var ebase: Vector3 = r.rest[eb]
			var el := float(ear[0])
			var ew := float(ear[1])
			var em := _ear_mesh(String(ear[2]), el, ew)
			var rot := Vector3.ZERO
			match String(ear[2]):
				"point":
					rot = Vector3(-0.15, side * 0.25, -side * 0.28)
				"round":
					rot = Vector3(-0.1, side * 0.4, -side * 0.5)
				"leaf":
					rot = Vector3(0.15, side * 0.5, -side * 1.05)
				"side":
					rot = Vector3(0.2, side * 0.3, -side * 1.35)
				"long":
					rot = Vector3(0.45, side * 0.2, -side * 0.18)
			r.slot(S_BODY).rigid(em, Transform3D(Basis.from_euler(rot), ebase), eb)
			# Darker, furred inside of the ear.
			r.slot(S_DARK).rigid(_ear_mesh(String(ear[2]) + "_in", el * 0.82, ew * 0.7), Transform3D(Basis.from_euler(rot), ebase + Basis.from_euler(rot) * Vector3(0, el * 0.06, -ew * 0.12)), eb)
	# Teeth.
	if spec.get("teeth", false) and g.has("fangs"):
		var fg: Array = g["fangs"]
		var fl := float(fg[1])
		for side: float in [-1.0, 1.0]:
			var fp: Vector3 = fg[0]
			fp.x *= side
			var fang := OrganicMesh.bezier("qh_fang_%d" % int(fl * 1000.0), Vector3.ZERO, Vector3(0, -fl * 0.6, 0.0), Vector3(0, -fl, fl * 0.15), fl * 0.17, fl * 0.02, 5, 6)
			_hp(r, S_IVORY, fang, hp, _put(fp), HEAD)
			_hp(r, S_IVORY, fang, jaw_at, Transform3D(Basis(Vector3.RIGHT, PI) * Basis().scaled(Vector3.ONE * 0.8), Vector3(fp.x * 0.85, 0.012, fp.z + 0.012 - jl.z)), JAW)
			for t in 3:
				var tz := fp.z + 0.02 + t * fl * 0.5
				_hp(r, S_IVORY, OrganicMesh.bezier("qh_molar_%d" % int(fl * 1000.0), Vector3.ZERO, Vector3(0, -fl * 0.2, 0), Vector3(0, -fl * 0.35, 0), fl * 0.14, fl * 0.05, 3, 5), hp, _put(Vector3(fp.x * 1.05, fp.y + fl * 0.1, tz)), HEAD)
		for t in 4:
			var x := (float(t) - 1.5) * float(fg[1]) * 0.28
			_hp(r, S_IVORY, OrganicMesh.bezier("qh_incisor_%d" % int(fl * 1000.0), Vector3.ZERO, Vector3(0, -fl * 0.2, 0), Vector3(0, -fl * 0.38, 0), fl * 0.08, fl * 0.05, 3, 5), hp, _put(Vector3(x, (fg[0] as Vector3).y, (fg[0] as Vector3).z - fl * 0.3)), HEAD)
	match kind:
		"croc":
			# Rows of interlocking teeth along both jaws, eye bumps, nostril knob.
			for side: float in [-1.0, 1.0]:
				for t in 12:
					var f := float(t) / 11.0
					var tz := lerpf(-0.08, -0.58, f)
					var tl := 0.03 + 0.02 * sin(f * 9.0) * sin(f * 9.0)
					var hw: float = OrganicMesh._sample(g["skull"], (tz - 0.1) / -0.72)[0]
					_hp(r, S_IVORY, OrganicMesh.bezier("qh_ctooth", Vector3.ZERO, Vector3(0, -0.6, 0.05), Vector3(0, -1.0, 0.0), 0.22, 0.03, 4, 5), hp, _put(Vector3(side * hw * 0.92, -0.03, tz), Vector3.ZERO, Vector3.ONE * tl), HEAD)
			for side: float in [-1.0, 1.0]:
				_hp(r, S_BODY, OrganicMesh.blob("qh_eyebump", Vector3(0.045, 0.04, 0.05), 0.15, 7, 10), hp, _put(Vector3(side * 0.07, 0.045, -0.06)), HEAD)
			r.slot(S_BODY)
		"boar":
			if spec.get("tusks", false):
				for side: float in [-1.0, 1.0]:
					var tusk := OrganicMesh.bezier("qh_tusk_%d" % int(side), Vector3.ZERO, Vector3(side * 0.02, 0.05, -0.01), Vector3(side * 0.045, 0.085, 0.03), 0.014, 0.002, 7, 6)
					_hp(r, S_IVORY, tusk, jaw_at, _put(Vector3(side * 0.04, 0.0, -0.2 - jl.z * 0.0)), JAW)
	# Horns and antlers.
	if spec.get("goat_horns", false):
		for side: float in [-1.0, 1.0]:
			var horn := OrganicMesh.bezier("qh_ghorn_%d" % int(side), Vector3.ZERO, Vector3(side * 0.03, 0.12, 0.06), Vector3(side * 0.06, 0.08, 0.2), 0.022, 0.003, 12, 8)
			_hp(r, S_HORN, horn, hp, _put(Vector3(side * 0.025, 0.06, -0.04)), HEAD)
	if spec.get("horns", false):
		for side: float in [-1.0, 1.0]:
			var horn := OrganicMesh.bezier("qh_hhorn_%d" % int(side), Vector3.ZERO, Vector3(side * 0.05, 0.07, 0.04), Vector3(side * 0.07, 0.13, 0.13), 0.022, 0.003, 10, 7)
			_hp(r, S_HORN, horn, hp, _put(Vector3(side * 0.035, 0.05, -0.05)), HEAD)
	if spec.get("antlers", false):
		for side: float in [-1.0, 1.0]:
			var p1 := Vector3(side * 0.12, 0.2, 0.08)
			var p2 := Vector3(side * 0.24, 0.42, -0.02)
			var base := Vector3(side * 0.035, 0.055, -0.01)
			_hp(r, S_IVORY, OrganicMesh.bezier("qh_beam_%d" % int(side), Vector3.ZERO, p1, p2, 0.018, 0.007, 12, 7), hp, _put(base), HEAD)
			_hp(r, S_IVORY, OrganicMesh.blob("qh_burr", Vector3(0.022, 0.012, 0.022), 0.2, 3, 8), hp, _put(base + Vector3(0, 0.01, 0)), HEAD)
			for t in 4:
				var f := 0.2 + t * 0.22
				var q := Vector3.ZERO.lerp(p1, f).lerp(p1.lerp(p2, f), f)
				var tl := 0.12 - t * 0.012
				var tine := OrganicMesh.bezier("qh_tine_%d_%d" % [int(side), t], Vector3.ZERO, Vector3(side * 0.01, tl * 0.5, -tl * 0.3), Vector3(side * 0.02, tl, -tl * 0.2), 0.011, 0.003, 6, 5)
				_hp(r, S_IVORY, tine, hp, _put(base + q), HEAD)
			# The brow tine curving forward over the face.
			_hp(r, S_IVORY, OrganicMesh.bezier("qh_brow_tine_%d" % int(side), Vector3.ZERO, Vector3(side * 0.01, 0.03, -0.05), Vector3(side * 0.0, 0.06, -0.09), 0.01, 0.003, 6, 5), hp, _put(base + Vector3(side * 0.02, 0.03, 0.0)), HEAD)
	if spec.get("beard", false):
		var tm := _tuft_mesh()
		for i in 7:
			var a := float(i) / 6.0
			_hp(r, S_BODY, tm, jaw_at, Transform3D(Basis(Vector3.RIGHT, PI * 0.95 + a * 0.15).scaled(Vector3(0.05, 0.1 - a * 0.02, 0.05)), Vector3((a - 0.5) * 0.02, -0.01, -0.09 - a * 0.03)), JAW)
	# Cheek ruff and fur on the crown.
	if fam["head"] in ["canine", "bear"] and spec.get("fur", true):
		var tm := _tuft_mesh()
		var hs := 1.0 if kind == "canine" else 2.0
		for side: float in [-1.0, 1.0]:
			for i in 6:
				var a := float(i) / 5.0
				var pos := Vector3(side * (0.06 + a * 0.008) * hs, (-0.035 + a * 0.05) * hs, (-0.015 + a * 0.03) * hs)
				var dir := Vector3(side * 0.55, -0.25 + a * 0.3, 0.8).normalized()
				var b := Basis.looking_at(-dir, Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5)
				_hp(r, S_BODY, tm, hp, Transform3D(b.scaled(Vector3(1.4, 1, 1) * 0.045 * hs * float(spec.get("fur_len", 1.0))), pos), HEAD)


func _ear_mesh(shape: String, l: float, w: float) -> Mesh:
	var key := "qh_ear_%s_%d_%d" % [shape, int(l * 1000.0), int(w * 1000.0)]
	var prof: Array
	var cup := 0.25
	match shape.trim_suffix("_in"):
		"round":
			prof = [[0.0, w * 0.75, w * 0.25], [0.45, w, w * 0.25, w * 0.08], [0.85, w * 0.7, w * 0.2, w * 0.04], [1.0, 0.0, 0.0]]
		"leaf", "side":
			prof = [[0.0, w * 0.35, w * 0.25], [0.35, w * 0.95, w * 0.2, w * 0.15], [0.7, w * 0.75, w * 0.15, w * 0.12], [1.0, 0.0, 0.0, w * 0.05]]
		"long":
			prof = [[0.0, w * 0.4, w * 0.3], [0.3, w * 0.95, w * 0.22, w * 0.12], [0.8, w * 0.8, w * 0.16, w * 0.1], [1.0, w * 0.2, w * 0.1, w * 0.05]]
		_:
			prof = [[0.0, w, w * 0.3], [0.5, w * 0.62, w * 0.2, w * cup * 0.4], [1.0, 0.0, 0.0]]
	return OrganicMesh.profile(key, Vector3.ZERO, Vector3(0, l, 0), prof, 8, 6, Vector3.BACK)


# --- Animation ------------------------------------------------------------------------------

func _on_action(action_name: String) -> void:
	if action_name == "die":
		_death_side = 1.0 if randf() < 0.5 else -1.0


func _animate(delta: float) -> void:
	if skel == null:
		return
	var gait: Dictionary = fam["gait"]
	var sprawl := bool(fam.get("sprawl", false))
	var hop := bool(spec.get("hop", false))
	var prey := bool(spec.get("prey", false))
	var p := action_progress()
	var w := action_weight(0.1, 0.2)
	var act := _action if p >= 0.0 and not _dead else ""
	# Speeds in rig units (the skeleton is scaled by k).
	_speed = damp(_speed, move_speed / k, 6.0, delta)
	var run := float(gait["run"])
	var walk_w := clampf(_speed / (run * 0.12), 0.0, 1.0)
	_trot = damp(_trot, clampf((_speed - run * 0.22) / (run * 0.2), 0.0, 1.0), 4.0, delta)
	_gallop = damp(_gallop, clampf((_speed - run * 0.55) / (run * 0.25), 0.0, 1.0), 4.0, delta)
	var cycle := float(gait["cycle"]) * (1.0 + 0.55 * _trot + 1.1 * _gallop)
	_gait = fposmod(_gait + delta * _speed / maxf(cycle, 0.05), 1.0)
	_graze = damp(_graze, 1.0 if (grazing and _speed < 0.3 and act == "") else 0.0, 1.5, delta)
	# Prey look up and listen now and then.
	_alert = damp(_alert, 1.0 if (prey and sin(_time * 0.37) > 0.7) else 0.0, 2.0, delta)
	var g := _gait * TAU
	var breathe := sin(_time * (2.0 if not prey else 2.8))

	# --- Targets from gait and actions.
	var crouch := 0.0
	var lunge := 0.0
	var rear := 0.0
	var pitch := 0.0
	var roll := 0.0
	var head_pitch := -0.05 - _graze * 1.05 + _alert * 0.25 * (1.0 - _graze)
	var head_yaw := sin(_time * 0.43) * 0.25 * (1.0 - walk_w) + sin(_time * 1.7) * 0.05
	var jaw_t := 0.02
	if not prey and not sprawl:
		jaw_t += maxf(0.0, sin(g * 2.0)) * 0.18 * _gallop + 0.06 * _trot
	if _graze > 0.5:
		jaw_t = maxf(0.0, sin(_time * 7.0)) * 0.12
	var front_raise := 0.0
	var tail_lift := 0.0
	var ear_back := 0.0
	match act:
		"attack", "attack2", "bite":
			var wind := keys(p, [[0, 0], [0.3, 1.0], [0.45, 0.0], [1, 0]])
			var strike := keys(p, [[0, 0], [0.32, 0.0], [0.5, 1.0], [0.7, 0.8], [1, 0]])
			crouch = 0.08 * wind
			lunge = 0.16 * strike - 0.05 * wind
			head_pitch = lerpf(head_pitch, -0.35, strike) + 0.35 * wind
			jaw_t = keys(p, [[0, 0.05], [0.3, 0.85], [0.48, 0.9], [0.56, 0.0], [1, 0.05]])
			ear_back = w
		"lunge", "pounce":
			var coil := keys(p, [[0, 0], [0.3, 1.0], [0.42, 0.0], [1, 0]])
			var leap := keys(p, [[0, 0], [0.35, 0.0], [0.5, 1.0], [0.75, 0.6], [1, 0]])
			crouch = 0.14 * coil - 0.06 * leap
			lunge = 0.35 * leap
			pitch = 0.18 * leap - 0.12 * coil
			front_raise = leap
			jaw_t = lerpf(jaw_t, 0.9, leap)
			head_pitch += 0.2 * coil - 0.15 * leap
			ear_back = w
		"slam":
			var up := keys(p, [[0, 0], [0.42, 1.0], [0.55, 1.0], [0.65, 0.0], [1, 0]])
			var down := keys(p, [[0, 0], [0.58, 0.0], [0.66, 1.0], [0.85, 0.6], [1, 0]])
			rear = up
			crouch = 0.12 * down
			jaw_t = lerpf(jaw_t, 0.8, maxf(up, down))
			head_pitch += 0.3 * up - 0.3 * down
		"roar", "howl", "shoot", "throw", "cast", "drain", "summon":
			var howl := act == "howl"
			head_pitch = lerpf(head_pitch, 1.15 if howl else 0.15, w)
			jaw_t = lerpf(jaw_t, (0.55 if howl else 0.95) + sin(_time * 30.0) * 0.04, w)
			if species == "bear" and act == "roar":
				rear = 0.75 * w
			else:
				crouch = 0.05 * w
				lunge = 0.04 * w
			ear_back = w
		"hit":
			var s := sin(PI * clampf(p * 1.4, 0.0, 1.0))
			roll = 0.12 * s
			lunge = -0.06 * s
			head_pitch += 0.3 * s
			head_yaw += 0.4 * s
			ear_back = s
	_crouch = damp(_crouch, crouch, 12.0, delta)
	_lunge = damp(_lunge, lunge, 12.0, delta)
	_rear = damp(_rear, rear, 7.0, delta)
	_jaw = damp(_jaw, jaw_t, 18.0, delta)
	_head_p = damp(_head_p, head_pitch, 6.0, delta)
	_head_y = damp(_head_y, head_yaw, 4.0, delta)
	var L := _body_len() / k

	# --- Body.
	var bob := breathe * 0.004 * L
	bob -= absf(sin(g * 2.0)) * 0.025 * L * _trot * (1.0 - _gallop)
	bob += sin(g * 2.0) * 0.012 * L * walk_w * (1.0 - _trot)
	var gal_pitch := sin(g) * 0.14 * _gallop
	var spine_flex := sin(g) * 0.22 * _gallop
	var hips_rest: Vector3 = rest[HIPS]
	var hips_pos := hips_rest + Vector3(0, bob - _crouch * L, -_lunge * L)
	if hop:
		hips_pos.y += maxf(0.0, sin(g)) * 0.08 * walk_w
		gal_pitch += sin(g) * 0.3 * walk_w
	var sway := 0.0
	if sprawl:
		sway = sin(g) * 0.22 * walk_w
	var rear_ang := _rear * (0.95 if species == "bear" else 0.6)
	# Rearing pivots the body up round the hips.
	hips_pos.y += _rear * 0.08 * L
	var body_b := Basis.from_euler(Vector3(pitch + gal_pitch + rear_ang, sway * 0.5, roll + sin(g) * 0.03 * walk_w))
	place(HIPS, hips_pos, body_b)
	fk(SPINE, Vector3(-spine_flex * 0.5 + breathe * 0.01, sway * 0.4, 0))
	fk(CHEST, Vector3(-spine_flex * 0.5, sway * 0.4, 0))
	# Neck and head: the head stays steady while the body rocks.
	var hp := _head_p - (pitch + gal_pitch + rear_ang) * 0.7
	var n_pitch := hp * 0.45 + sin(g * 2.0) * 0.04 * _trot
	fk(NECK, Vector3(n_pitch, _head_y * 0.35 - sway * 0.6, 0))
	fk(NECK2, Vector3(hp * 0.3, _head_y * 0.35, 0))
	fk(HEAD, Vector3(hp * 0.25 - sin(g * 2.0) * 0.04 * _trot, _head_y * 0.3, sin(_time * 0.6) * 0.04))
	fk(JAW, Vector3(-_jaw * (0.55 if sprawl else 0.6), 0, 0))
	var twitch := maxf(0.0, sin(_time * 0.9 + 1.3) - 0.93) * 8.0
	var ear_b := ear_back * 0.6 + _speed * 0.03
	fk(EAR_L, Vector3(ear_b * 0.6 + twitch * 0.2, -ear_b * 0.3, ear_b * 0.4))
	fk(EAR_R, Vector3(ear_b * 0.6, ear_b * 0.3 + _alert * sin(_time * 2.0) * 0.4, -ear_b * 0.4))
	# Tail.
	var tail_n := _tail_bones.size()
	for i in tail_n:
		var f := float(i) / maxf(1.0, tail_n - 1)
		var wag := sin(_time * (1.6 + _speed * 0.8) - f * 1.6) * (0.12 + 0.1 * walk_w)
		var lift := 0.0
		match String(fam["head"]):
			"canine":
				lift = (0.1 - _gallop * 0.25) * (1.0 - f * 0.5) + _gallop * 0.05 - tail_lift
			"croc":
				lift = 0.05 - f * 0.08
				wag = -sway * 1.5 * (0.5 + f) + sin(_time * 1.1 - f * 2.0) * 0.08
			"deer":
				lift = -0.3 * _alert - 0.5 * _gallop
		fk(_tail_bones[i], Vector3(lift, wag, 0))

	# --- Legs.
	var walk_off := [0.25, 0.75, 0.0, 0.5]
	var trot_off := [0.0, 0.5, 0.5, 0.0]
	var gal_off := [0.45, 0.55, 0.0, 0.1]
	var duty := lerpf(lerpf(0.66, 0.46, _trot), 0.32, _gallop)
	if hop:
		walk_off = [0.5, 0.55, 0.0, 0.0]
		trot_off = walk_off
		gal_off = walk_off
		duty = 0.4
	for li in 4:
		var leg: Dictionary = _legs[li]
		var front: bool = leg["front"]
		var side: float = leg["side"]
		var up_b: int = leg["up"]
		fk(up_b)
		var off := lerp_angle(float(walk_off[li]) * TAU, float(trot_off[li]) * TAU, _trot)
		off = lerp_angle(off, float(gal_off[li]) * TAU, _gallop) / TAU
		var ph := fposmod(_gait + off, 1.0)
		var leg_len: float = leg["len"]
		var stride := minf(duty * cycle, leg_len * (0.9 + 0.5 * _gallop)) * walk_w
		var lift_h := float(gait["lift"]) * (1.0 + 1.5 * _gallop) * walk_w
		var foot: Vector3 = leg["rest_foot"]
		foot.z -= _lunge * L * 0.3
		var swing_t := 0.0
		if ph < duty:
			foot.z += stride * (-0.5 + ph / duty)
		else:
			var s := (ph - duty) / (1.0 - duty)
			swing_t = sin(PI * s)
			foot.z += stride * (0.5 - s * s * (3.0 - 2.0 * s))
			foot.y += swing_t * lift_h
		if sprawl:
			foot.x += side * swing_t * 0.05
		# Crouching spreads the feet a little; hips sink.
		foot.y += float(leg["lift0"]) * 0.0
		var flex := swing_t * (1.3 if front else 0.7) * clampf(walk_w * 1.5, 0.0, 1.0)
		var paw := foot + Vector3(0, float(leg["lift0"]), 0)
		if front and front_raise > 0.0:
			# Leaping: forelegs reach far ahead.
			paw = paw.lerp(Vector3(paw.x, rest[HIPS].y * 0.55, paw.z - L * 0.35), front_raise)
			flex = lerpf(flex, -0.2, front_raise)
		if not front and front_raise > 0.0:
			paw = paw.lerp(Vector3(paw.x, paw.y + 0.02, paw.z + L * 0.25), front_raise * 0.7)
		if front and _rear > 0.01:
			# Rearing: forepaws come up and paw the air, then hammer down.
			var lift_pos := gp[up_b] + Vector3(side * 0.05 * L, -leg_len * 0.45, -leg_len * 0.5)
			paw = paw.lerp(lift_pos + Vector3(0, sin(_time * 9.0 + side) * 0.03 * L, 0), clampf(_rear, 0.0, 1.0))
			flex = lerpf(flex, 1.2, clampf(_rear, 0.0, 1.0))
		var off_v: Vector3 = leg["wrist_off"]
		off_v = off_v.rotated(Vector3.RIGHT, -flex if front else flex * 0.8)
		if sprawl:
			off_v = off_v.rotated(Vector3.FORWARD, side * swing_t * 0.3)
		var wrist := paw + off_v
		var pole: Vector3
		if sprawl:
			pole = gb[HIPS] * Vector3(side * 1.0, 0.8, 0.0)
		elif front:
			pole = gb[HIPS] * Vector3(side * 0.15, 0.0, 1.0)
		else:
			pole = gb[HIPS] * Vector3(side * 0.15, 0.0, -1.0)
		var lo: int = leg["lo"]
		var fb: int = leg["foot"]
		var tb: int = leg["toe"]
		ik(up_b, lo, fb, wrist, pole)
		aim(fb, tb, paw - gp[fb], Vector3.BACK if front else Vector3.FORWARD, pole)
		gp[tb] = gp[fb] + gb[fb] * (rest[tb] - rest[fb])
		var toe_curl := swing_t * (0.9 if front else 0.4) * clampf(walk_w * 1.5, 0.0, 1.0)
		gb[tb] = Basis(Vector3.RIGHT, toe_curl if front else -toe_curl)

	if _dead:
		_pose_dead(delta)
	commit()


## Collapse onto one side: a blend from the pose at the moment of death.
func _pose_dead(_delta: float) -> void:
	if not _death_pose:
		_death_pose = true
		_dead_gb = gb.duplicate()
		_dead_gp = gp.duplicate()
	var f := clampf(_dead_t / 0.9, 0.0, 1.0)
	f = f * f * (3.0 - 2.0 * f)
	var sprawl := bool(fam.get("sprawl", false))
	# Lying pose.
	var c: Array = fam["torso"]
	var half_w := 0.0
	for row: Array in c:
		half_w = maxf(half_w, float(row[2]))
	var roll := _death_side * (PI * 0.47 if not sprawl else 0.25)
	var hb := Basis.from_euler(Vector3(0.0, 0.1 * _death_side, roll))
	var hy := half_w * 0.95 if not sprawl else (rest[HIPS].y * 0.45)
	place(HIPS, Vector3(0, hy, rest[HIPS].z), hb)
	fk(SPINE, Vector3(0, 0.05 * _death_side, 0))
	fk(CHEST, Vector3(0, 0.05 * _death_side, 0))
	fk(NECK, Vector3(-0.15, -0.25 * _death_side, 0))
	fk(NECK2, Vector3(-0.1, -0.2 * _death_side, 0))
	fk(HEAD, Vector3(-0.1, -0.15 * _death_side, 0.15 * _death_side))
	fk(JAW, Vector3(-0.25, 0, 0))
	fk(EAR_L, Vector3(0.6, 0, 0))
	fk(EAR_R, Vector3(0.6, 0, 0))
	for i in _tail_bones.size():
		fk(_tail_bones[i], Vector3(0.05, 0.12 * _death_side, 0))
	for leg: Dictionary in _legs:
		var front: bool = leg["front"]
		var bend := 0.35 if front else -0.35
		fk(int(leg["up"]), Vector3(bend * 0.6, 0, 0))
		fk(int(leg["lo"]), Vector3(-bend, 0, 0))
		fk(int(leg["foot"]), Vector3(bend * 0.8, 0, 0))
		fk(int(leg["toe"]), Vector3(0.3, 0, 0))
	for b in bone_count:
		gb[b] = _dead_gb[b].slerp(gb[b], f).orthonormalized()
		gp[b] = _dead_gp[b].lerp(gp[b], f)


func set_dead(dead: bool) -> void:
	super.set_dead(dead)
	if not dead:
		_death_pose = false
	if _ember_fx != null:
		_ember_fx.emitting = not dead
