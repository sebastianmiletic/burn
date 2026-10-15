class_name QuadrupedModel
extends CreatureModel
## Four-legged animals from one rig: wolves (grey, dire, frost), hellhounds,
## bears, deer and stags, rabbits, mountain goats, boars and the reptilian
## bog lurker. Smooth swept torsos with species proportions, articulated
## necks and heads with hinged jaws, ears, eyes, antlers / horns / tusks,
## fur or scale skins with countershading, and a speed-blended gait (walk ->
## trot -> gallop; rabbits hop, lurkers sprawl). Faces -Z.
##
## `grazing` lowers the head of prey animals while idle.

const SPECIES := {
	"wolf": {"len": 1.15, "h": 0.8, "chest": [0.2, 0.25], "waist": [0.14, 0.16], "hip": [0.16, 0.19], "neck": 0.34, "neck_r": 0.12,
		"head": 0.24, "skull": 0.11, "snout": 0.2, "snout_r": 0.055, "leg": 0.05, "tail": "bushy", "tail_len": 0.55, "ears": "pointed",
		"fur": true, "back": Color(0.36, 0.34, 0.31), "belly": Color(0.78, 0.74, 0.67), "accent": Color(0.13, 0.12, 0.11), "eye": Color(1.0, 0.78, 0.3), "eye_e": 2.5, "teeth": true},
	"dire_wolf": {"base": "wolf", "scale": 1.45, "back": Color(0.17, 0.15, 0.14), "belly": Color(0.4, 0.36, 0.32), "accent": Color(0.06, 0.05, 0.05), "eye": Color(1.0, 0.25, 0.1), "eye_e": 6.0, "ruff": true},
	"frost_wolf": {"base": "wolf", "scale": 1.2, "back": Color(0.8, 0.85, 0.9), "belly": Color(0.95, 0.96, 0.97), "accent": Color(0.45, 0.55, 0.66), "eye": Color(0.45, 0.85, 1.0), "eye_e": 6.0, "ruff": true},
	"hellhound": {"base": "wolf", "scale": 1.35, "back": Color(0.09, 0.06, 0.06), "belly": Color(0.2, 0.08, 0.06), "accent": Color(0.05, 0.03, 0.03), "eye": Color(1.0, 0.45, 0.1), "eye_e": 8.0,
		"ruff": true, "cracks": Color(1.0, 0.4, 0.08), "horns": true, "embers": true},
	"bear": {"len": 1.55, "h": 1.1, "chest": [0.42, 0.5], "waist": [0.4, 0.46], "hip": [0.4, 0.45], "neck": 0.26, "neck_r": 0.27, "hump": true,
		"head": 0.3, "skull": 0.2, "snout": 0.2, "snout_r": 0.09, "leg": 0.12, "tail": "stub", "tail_len": 0.12, "ears": "round", "plantigrade": true,
		"fur": true, "back": Color(0.3, 0.2, 0.13), "belly": Color(0.38, 0.27, 0.18), "accent": Color(0.2, 0.13, 0.08), "eye": Color(0.05, 0.03, 0.02), "eye_e": 0.0, "teeth": true},
	"deer": {"len": 1.05, "h": 0.98, "chest": [0.18, 0.25], "waist": [0.15, 0.19], "hip": [0.17, 0.21], "neck": 0.46, "neck_r": 0.105, "neck_up": 0.85,
		"head": 0.22, "skull": 0.09, "snout": 0.17, "snout_r": 0.045, "leg": 0.032, "tail": "flag", "tail_len": 0.14, "ears": "large", "hooves": true,
		"fur": true, "back": Color(0.55, 0.37, 0.22), "belly": Color(0.88, 0.82, 0.72), "accent": Color(0.92, 0.9, 0.85), "eye": Color(0.03, 0.03, 0.03), "eye_e": 0.0, "prey": true},
	"stag": {"base": "deer", "scale": 1.15, "antlers": true, "back": Color(0.48, 0.31, 0.18)},
	"rabbit": {"len": 0.3, "h": 0.2, "chest": [0.08, 0.09], "waist": [0.085, 0.09], "hip": [0.1, 0.11], "neck": 0.06, "neck_r": 0.06, "neck_up": 0.6,
		"head": 0.09, "skull": 0.055, "snout": 0.05, "snout_r": 0.035, "leg": 0.022, "tail": "puff", "tail_len": 0.05, "ears": "long", "hop": true,
		"fur": true, "back": Color(0.5, 0.42, 0.32), "belly": Color(0.85, 0.82, 0.76), "accent": Color(0.35, 0.28, 0.2), "eye": Color(0.02, 0.02, 0.02), "eye_e": 0.0, "prey": true},
	"goat": {"len": 0.9, "h": 0.75, "chest": [0.2, 0.25], "waist": [0.19, 0.22], "hip": [0.18, 0.21], "neck": 0.32, "neck_r": 0.09, "neck_up": 0.8,
		"head": 0.22, "skull": 0.09, "snout": 0.13, "snout_r": 0.05, "leg": 0.04, "tail": "flag", "tail_len": 0.1, "ears": "side", "hooves": true, "goat_horns": true, "beard": true,
		"fur": true, "back": Color(0.85, 0.83, 0.78), "belly": Color(0.92, 0.9, 0.86), "accent": Color(0.3, 0.27, 0.24), "eye": Color(0.7, 0.6, 0.2), "eye_e": 0.6, "prey": true},
	"boar": {"len": 1.05, "h": 0.78, "chest": [0.27, 0.33], "waist": [0.24, 0.28], "hip": [0.21, 0.25], "neck": 0.18, "neck_r": 0.2,
		"head": 0.3, "skull": 0.15, "snout": 0.24, "snout_r": 0.075, "leg": 0.045, "tail": "thin", "tail_len": 0.2, "ears": "pointed", "hooves": true, "tusks": true, "bristles": true,
		"fur": true, "back": Color(0.24, 0.2, 0.16), "belly": Color(0.36, 0.3, 0.24), "accent": Color(0.1, 0.08, 0.07), "eye": Color(0.05, 0.03, 0.02), "eye_e": 0.0, "prey": true},
	"bog_lurker": {"len": 2.0, "h": 0.42, "chest": [0.38, 0.2], "waist": [0.4, 0.21], "hip": [0.34, 0.19], "neck": 0.3, "neck_r": 0.22, "neck_up": 0.05,
		"head": 0.45, "skull": 0.17, "snout": 0.75, "snout_r": 0.08, "leg": 0.07, "tail": "croc", "tail_len": 2.0, "ears": "none", "sprawl": true, "teeth": true, "plates": true,
		"fur": false, "back": Color(0.2, 0.25, 0.14), "belly": Color(0.58, 0.55, 0.38), "accent": Color(0.08, 0.1, 0.06), "eye": Color(1.0, 0.82, 0.2), "eye_e": 3.0},
}

var species := "wolf"
var spec := {}
var grazing := false
var k := 1.0

var body: Node3D
var chest_j: Node3D
var neck_j: Node3D
var head: Node3D
var jaw: Node3D
var ears: Array[Node3D] = []
var tail: Array[Node3D] = []
var legs: Array = []  # [hip, knee, ankle, front: bool, side: float, phase_offset_index]
var eye_parts: Array[MeshInstance3D] = []

var _gait := 0.0
var _speed := 0.0
var _graze := 0.0
var _hip_h := 0.0


func _init(kind_name := "wolf", variant_seed := 0) -> void:
	species = kind_name
	var base: Dictionary = SPECIES.get(kind_name, SPECIES["wolf"])
	spec = base.duplicate()
	if base.has("base"):
		spec = (SPECIES[base["base"]] as Dictionary).duplicate()
		spec.merge(base, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = variant_seed
	k = float(spec.get("scale", 1.0)) * rng.randf_range(0.9, 1.1)
	# Colour variants within a kind.
	var tint := rng.randf_range(-0.06, 0.06)
	if species == "bear":
		var coats := [Color(0.3, 0.2, 0.13), Color(0.11, 0.09, 0.08), Color(0.45, 0.35, 0.24)]
		spec["back"] = coats[rng.randi() % coats.size()]
		spec["belly"] = (spec["back"] as Color).lightened(0.12)
	elif species == "wolf":
		var coats := [Color(0.36, 0.34, 0.31), Color(0.45, 0.36, 0.26), Color(0.25, 0.24, 0.23), Color(0.55, 0.52, 0.48)]
		spec["back"] = coats[rng.randi() % coats.size()]
	elif species == "goat":
		var coats := [Color(0.85, 0.83, 0.78), Color(0.45, 0.38, 0.3), Color(0.25, 0.22, 0.2)]
		spec["back"] = coats[rng.randi() % coats.size()]
	elif species == "rabbit":
		var coats := [Color(0.5, 0.42, 0.32), Color(0.55, 0.53, 0.5), Color(0.38, 0.3, 0.22)]
		spec["back"] = coats[rng.randi() % coats.size()]
	spec["back"] = (spec["back"] as Color).lightened(tint) if tint > 0.0 else (spec["back"] as Color).darkened(-tint)
	dissolve_delay = 1.5
	durations["howl"] = 1.8
	durations["lunge"] = 0.7
	durations["pounce"] = 0.8


func _ember_extents() -> Vector3:
	return Vector3(0.3, 0.3, 0.6) * float(spec["len"]) * k


func _lod_size() -> float:
	return maxf(0.6, float(spec["len"]) * k * 1.3)


func _build() -> void:
	var L := float(spec["len"]) * k
	var H := float(spec["h"]) * k
	var c0: Array = spec["chest"]
	var c1: Array = spec["waist"]
	var c2: Array = spec["hip"]
	var fur: bool = spec["fur"]
	var extra := {"accent": spec["accent"], "accent_mode": 3, "accent_amount": 0.55, "accent_scale": 2.0 / maxf(0.3, k)}
	if spec.has("cracks"):
		extra.merge({"glow_mode": 2, "glow_color": spec["cracks"], "glow_energy": 3.0, "glow_amount": 0.0, "glow_pulse": 0.6}, true)
	var skin: ShaderMaterial
	if fur:
		extra["pattern_scale"] = 7.0 / sqrt(k * float(spec["len"]))
		skin = CreatureSkin.fur(spec["back"], spec["belly"], extra)
	else:
		extra["pattern_scale"] = 7.0
		extra["wet"] = 0.5
		skin = CreatureSkin.scales(spec["back"], spec["belly"], 7.0, extra)
	var dark := CreatureSkin.hide((spec["back"] as Color).darkened(0.6), (spec["back"] as Color).darkened(0.5), {"pattern_scale": 14.0, "roughness": 0.5})
	var keratin := CreatureSkin.keratin(Color(0.86, 0.82, 0.7))
	var hoof := CreatureSkin.keratin(Color(0.12, 0.1, 0.08), {"roughness": 0.45})
	var mouth := CreatureSkin.mouth(Color(0.45, 0.15, 0.15))
	var sprawl := bool(spec.get("sprawl", false))
	_hip_h = H * (0.95 if not sprawl else 1.0)
	body = ModelKit.joint(self, "Body", Vector3(0, _hip_h, 0))

	# Torso: one smooth sweep from rump to shoulders.
	var key := "quad_torso_%s_%.2f" % [species, k]
	var torso := OrganicMesh.profile(key, Vector3(0, 0, L * 0.5), Vector3(0, 0.02 * L, -L * 0.5),
		[[0.0, float(c2[0]) * 0.35 * k, float(c2[1]) * 0.35 * k, -0.02 * k], [0.1, float(c2[0]) * k, float(c2[1]) * k, 0.0],
		[0.5, float(c1[0]) * k, float(c1[1]) * k, -0.02 * k], [0.82, float(c0[0]) * k, float(c0[1]) * k, -0.03 * k],
		[1.0, float(c0[0]) * 0.55 * k, float(c0[1]) * 0.55 * k, 0.02 * k]], 16, 16)
	ModelKit.part(body, torso, skin)
	if spec.get("hump", false):
		ModelKit.part(body, OrganicMesh.blob("quad_hump_%.2f" % k, Vector3(0.3, 0.2, 0.35) * k, 0.1, 5, 14), skin, Vector3(0, float(c0[1]) * k * 0.75, -L * 0.28))
	if spec.get("ruff", false):
		ModelKit.part(body, OrganicMesh.blob("quad_ruff_%s_%.2f" % [species, k], Vector3(float(c0[0]) * 1.2, float(c0[1]) * 1.15, 0.22) * k, 0.25, 9, 16), skin, Vector3(0, 0.03 * k, -L * 0.42))
	if spec.get("plates", false):
		for i in 9:
			var z := lerpf(-L * 0.42, L * 0.45, float(i) / 8.0)
			for side: float in [-1.0, 1.0]:
				ModelKit.part(body, OrganicMesh.blob("quad_plate", Vector3(0.05, 0.035, 0.07) * k, 0.1, 13, 8), dark, Vector3(side * 0.09 * k, float(c1[1]) * k * 0.95, z))
	if spec.get("bristles", false):
		for i in 7:
			var z := lerpf(-L * 0.45, L * 0.1, float(i) / 6.0)
			ModelKit.part(body, OrganicMesh.bezier("quad_bristle", Vector3.ZERO, Vector3(0, 0.07, 0.03) * k, Vector3(0, 0.1, 0.09) * k, 0.03 * k, 0.004 * k, 5, 4), dark, Vector3(0, float(c0[1]) * k * 0.92, z))
	if spec.get("embers", false):
		var em := ModelKit.embers(body, 26, Vector3(0.18, 0.12, 0.3) * k, 0.8, 0.18 * k, 1.4)
		em.position = Vector3(0, float(c0[1]) * k, -L * 0.3)
		em.emitting = true

	# Neck and head.
	var neck_len := float(spec["neck"]) * k
	var neck_up := float(spec.get("neck_up", 0.35))
	chest_j = ModelKit.joint(body, "Chest", Vector3(0, 0.04 * k, -L * 0.42))
	neck_j = ModelKit.joint(chest_j, "Neck", Vector3.ZERO)
	var nr := float(spec["neck_r"]) * k
	var neck_end := Vector3(0, neck_len * sin(neck_up), -neck_len * cos(neck_up))
	ModelKit.part(neck_j, OrganicMesh.profile("quad_neck_%s_%.2f" % [species, k], Vector3(0, -nr * 0.2, nr * 0.6), neck_end,
		[[0.0, nr * 1.25, nr * 1.4], [0.5, nr * 1.05, nr * 1.15], [1.0, nr * 0.85, nr * 0.95]], 12, 8), skin)
	head = ModelKit.joint(neck_j, "Head", neck_end)
	var hl := float(spec["head"]) * k
	var sr := float(spec["skull"]) * k
	var snl := float(spec["snout"]) * k
	var snr := float(spec["snout_r"]) * k
	ModelKit.part(head, OrganicMesh.profile("quad_skull_%s_%.2f" % [species, k], Vector3(0, 0.0, sr * 0.7), Vector3(0, -sr * 0.25, -hl - snl),
		[[0.0, sr * 0.8, sr * 0.85], [0.25, sr * 1.05, sr * 1.0, sr * 0.1], [0.55, sr * 0.75, sr * 0.7, 0.0], [0.85, snr * 1.15, snr * 1.1, -sr * 0.05], [1.0, snr * 0.65, snr * 0.6, -sr * 0.08]], 14, 14), skin)
	# Nose.
	ModelKit.part(head, ModelKit.sphere(snr * 0.55, 8), dark, Vector3(0, -sr * 0.2, -hl - snl + snr * 0.15), Vector3.ZERO, Vector3(1.2, 0.8, 0.8))
	# Lower jaw.
	jaw = ModelKit.joint(head, "Jaw", Vector3(0, -sr * 0.45, 0.0))
	ModelKit.part(jaw, OrganicMesh.profile("quad_jaw_%s_%.2f" % [species, k], Vector3(0, 0, sr * 0.3), Vector3(0, -sr * 0.05, -hl - snl * 0.92),
		[[0.0, sr * 0.6, sr * 0.35], [0.6, snr * 1.0, snr * 0.55], [1.0, snr * 0.6, snr * 0.35]], 10, 10), skin)
	ModelKit.part(head, OrganicMesh.blob("quad_mouth_%s_%.2f" % [species, k], Vector3(snr * 0.9, sr * 0.15, (hl + snl) * 0.4), 0.05, 3, 8), mouth, Vector3(0, -sr * 0.42, -(hl + snl) * 0.5))
	if spec.get("teeth", false):
		for side: float in [-1.0, 1.0]:
			ModelKit.part(head, OrganicMesh.bezier("quad_fang_%s" % species, Vector3.ZERO, Vector3(0, -0.6, -0.05) * snr, Vector3(0, -1.0, 0.15) * snr, snr * 0.22, snr * 0.03, 5, 5), keratin, Vector3(side * snr * 0.7, -sr * 0.35, -hl - snl * 0.75))
			if species == "bog_lurker":
				for i in 7:
					ModelKit.part(head, ModelKit.cone(snr * 0.12, snr * 0.5, 4), keratin, Vector3(side * snr * 0.95, -sr * 0.42, -hl * 0.4 - snl * float(i) / 7.0), Vector3(180, 0, 0))
	if spec.get("tusks", false):
		for side: float in [-1.0, 1.0]:
			ModelKit.part(jaw, OrganicMesh.bezier("quad_tusk", Vector3.ZERO, Vector3(side * 0.02, 0.06, -0.02) * k, Vector3(side * 0.05, 0.1, 0.03) * k, 0.02 * k, 0.003 * k, 6, 5), keratin, Vector3(side * snr * 0.9, 0.0, -hl - snl * 0.6))
	# Eyes: glowing for predators, glossy dark for prey.
	var eye_e := float(spec["eye_e"])
	var eye_mat: Material = CreatureSkin.eye(spec["eye"], eye_e, 0.1) if eye_e > 0.0 else CreatureSkin.smooth(Color(0.02, 0.02, 0.02), Color(0.02, 0.02, 0.02), {"roughness": 0.05, "specular_amount": 0.9, "rim": 0.0})
	var eye_r := sr * (0.2 if spec.get("prey", false) else 0.16)
	for side: float in [-1.0, 1.0]:
		var ex := sr * (0.72 if spec.get("prey", false) else 0.55)
		eye_parts.append(ModelKit.part(head, ModelKit.sphere(eye_r, 8), eye_mat, Vector3(side * ex, sr * 0.3, -hl * 0.48), Vector3.ZERO, Vector3(0.7, 0.9, 1.0)))
	# Ears.
	match String(spec["ears"]):
		"pointed", "large", "side", "round", "long":
			for side: float in [-1.0, 1.0]:
				var ear := ModelKit.joint(head, "Ear", Vector3(side * sr * 0.55, sr * 0.75, sr * 0.2))
				var e_len: float = sr * {"pointed": 0.9, "large": 1.5, "side": 1.0, "round": 0.45, "long": 3.0}[String(spec["ears"])]
				var e_w: float = sr * {"pointed": 0.45, "large": 0.55, "side": 0.35, "round": 0.45, "long": 0.5}[String(spec["ears"])]
				var pts := PackedVector2Array([Vector2(-e_w * 0.5, 0), Vector2(e_w * 0.5, 0), Vector2(e_w * 0.35, e_len * 0.7), Vector2(0, e_len), Vector2(-e_w * 0.4, e_len * 0.65)])
				if spec["ears"] == "round":
					pts = PackedVector2Array([Vector2(-e_w * 0.5, 0), Vector2(e_w * 0.5, 0), Vector2(e_w * 0.55, e_len * 0.6), Vector2(0, e_len), Vector2(-e_w * 0.55, e_len * 0.6)])
				ModelKit.part(ear, OrganicMesh.membrane("quad_ear_%s_%.2f" % [species, k], pts, e_w * 0.25, e_w * 0.12), skin, Vector3.ZERO, Vector3(0, side * 25, side * -15 if spec["ears"] != "side" else side * -70))
				ears.append(ear)
	if spec.get("antlers", false):
		var antler := CreatureSkin.keratin(Color(0.7, 0.62, 0.5), {"roughness": 0.7})
		for side: float in [-1.0, 1.0]:
			var a := ModelKit.joint(head, "Antler", Vector3(side * sr * 0.4, sr * 0.85, sr * 0.1))
			var beam_end := Vector3(side * 0.35, 0.55, 0.15) * k
			ModelKit.part(a, OrganicMesh.bezier("quad_beam_%d" % int(side), Vector3.ZERO, Vector3(side * 0.12, 0.3, 0.12) * k, beam_end, 0.03 * k, 0.012 * k, 8, 6), antler)
			for t in 4:
				var f := 0.25 + t * 0.22
				var base_p := Vector3(side * 0.12, 0.3, 0.12) * k * (2.0 * f * (1.0 - f)) * 2.0 + beam_end * f * f
				ModelKit.part(a, OrganicMesh.bezier("quad_tine_%d_%d" % [int(side), t], Vector3.ZERO, Vector3(side * 0.02, 0.1, -0.06) * k, Vector3(side * 0.03, 0.2 - t * 0.02, -0.05) * k, 0.015 * k, 0.004 * k, 5, 4), antler, base_p)
	if spec.get("goat_horns", false) or spec.get("horns", false):
		var horn_mat := CreatureSkin.keratin(Color(0.35, 0.3, 0.25) if spec.get("goat_horns", false) else Color(0.12, 0.08, 0.07), {"pattern_scale": 30.0})
		for side: float in [-1.0, 1.0]:
			var p0 := Vector3.ZERO
			var p1 := Vector3(side * 0.06, 0.16, 0.12) * k
			var p2 := Vector3(side * 0.12, 0.02, 0.24) * k
			if spec.get("horns", false):
				p1 = Vector3(side * 0.05, 0.12, 0.06) * k
				p2 = Vector3(side * 0.1, 0.18, 0.18) * k
			ModelKit.part(head, OrganicMesh.bezier("quad_horn_%s_%d" % [species, int(side)], p0, p1, p2, 0.035 * k, 0.006 * k, 8, 6), horn_mat, Vector3(side * sr * 0.45, sr * 0.85, sr * 0.05))
	if spec.get("beard", false):
		ModelKit.part(jaw, OrganicMesh.bezier("quad_beard", Vector3.ZERO, Vector3(0, -0.06, 0.01) * k, Vector3(0, -0.14, 0.03) * k, 0.03 * k, 0.006 * k, 5, 6), skin, Vector3(0, -snr * 0.4, -hl - snl * 0.35))

	# Tail.
	var tail_len := float(spec["tail_len"]) * k
	var parent: Node3D = ModelKit.joint(body, "Tail", Vector3(0, float(c2[1]) * k * 0.55, L * 0.48))
	match String(spec["tail"]):
		"bushy", "croc", "thin":
			var n := 4 if spec["tail"] != "croc" else 7
			for i in n:
				var j := ModelKit.joint(parent, "T%d" % i, Vector3(0, 0, 0.0 if i == 0 else tail_len / n))
				var r := (0.07 if spec["tail"] == "bushy" else (0.02 if spec["tail"] == "thin" else 0.2)) * k * (1.0 - float(i) / n * (0.5 if spec["tail"] == "bushy" else 0.85))
				if spec["tail"] == "bushy" and i == n - 1:
					r *= 0.6
				ModelKit.part(j, OrganicMesh.profile("quad_tail_%s_%.2f_%d" % [species, k, i], Vector3.ZERO, Vector3(0, 0, tail_len / n * 1.15),
					[[0.0, r, r * (0.7 if spec["tail"] == "croc" else 1.0)], [0.5, r * 1.08, r * (0.75 if spec["tail"] == "croc" else 1.08)], [1.0, r * 0.82, r * 0.8]], 10, 6), skin)
				if spec["tail"] == "croc" and i < n - 1:
					ModelKit.part(j, OrganicMesh.blob("quad_plate", Vector3(0.05, 0.035, 0.07) * k, 0.1, 13, 8), dark, Vector3(0, r * 0.75, tail_len / n * 0.5))
				tail.append(j)
				parent = j
		"stub", "flag", "puff":
			var j := ModelKit.joint(parent, "T0", Vector3.ZERO)
			var tail_mat: Material = skin if spec["tail"] == "stub" else CreatureSkin.fur(Color(0.95, 0.94, 0.9), Color(0.95, 0.94, 0.9), {"pattern_scale": 30.0})
			ModelKit.part(j, OrganicMesh.blob("quad_tailtip_%s_%.2f" % [species, k], Vector3(tail_len * 0.45, tail_len * 0.45, tail_len * 0.6), 0.15, 4, 8), tail_mat, Vector3(0, 0, tail_len * 0.4))
			tail.append(j)

	# Legs.
	var leg_r := float(spec["leg"]) * k
	for spec_leg: Array in [[true, -1.0], [true, 1.0], [false, -1.0], [false, 1.0]]:
		var front: bool = spec_leg[0]
		var side: float = spec_leg[1]
		var half_w := float(c0[0] if front else c2[0]) * k * (0.6 if not sprawl else 0.85)
		var hip := ModelKit.joint(body, "Hip", Vector3(side * half_w, -0.02 * k, -L * 0.36 if front else L * 0.36))
		var upper := _hip_h * (0.5 if not sprawl else 0.55)
		var lower := _hip_h * (0.42 if not sprawl else 0.45)
		var foot_l := _hip_h * (0.2 if not sprawl else 0.1)
		if spec.get("hop", false) and not front:
			upper *= 1.3
			lower *= 1.4
		var thick := leg_r * (1.0 if front else 1.2)
		if sprawl:
			hip.rotation.z = side * 1.1
		ModelKit.part(hip, OrganicMesh.profile("quad_upper_%s_%.2f_%d" % [species, k, int(front)], Vector3(0, thick * 0.5, 0), Vector3(0, -upper, 0),
			[[0.0, thick * 1.9, thick * 2.2], [0.35, thick * 1.6, thick * 1.8], [1.0, thick * 0.95, thick]], 10, 8, Vector3.BACK), skin)
		var knee := ModelKit.joint(hip, "Knee", Vector3(0, -upper, 0))
		ModelKit.part(knee, OrganicMesh.profile("quad_lower_%s_%.2f_%d" % [species, k, int(front)], Vector3.ZERO, Vector3(0, -lower, 0),
			[[0.0, thick * 0.95, thick], [0.6, thick * 0.75, thick * 0.8], [1.0, thick * 0.7, thick * 0.72]], 8, 6, Vector3.BACK), skin)
		var ankle := ModelKit.joint(knee, "Ankle", Vector3(0, -lower, 0))
		if spec.get("hooves", false):
			ModelKit.part(ankle, OrganicMesh.profile("quad_pastern_%s_%.2f" % [species, k], Vector3.ZERO, Vector3(0, -foot_l, -foot_l * 0.15), [[0.0, thick * 0.7, thick * 0.7], [1.0, thick * 0.6, thick * 0.65]], 8, 4, Vector3.BACK), skin)
			ModelKit.part(ankle, ModelKit.cylinder(thick * 0.55, thick * 0.85, thick * 1.6, 8), hoof, Vector3(0, -foot_l - thick * 0.4, -foot_l * 0.17))
		else:
			var paw := Vector3(thick * 1.1, thick * 0.55, thick * (2.4 if spec.get("plantigrade", false) else 1.7))
			if spec.get("hop", false) and not front:
				paw.z *= 2.4
			ModelKit.part(ankle, OrganicMesh.profile("quad_meta_%s_%.2f_%d" % [species, k, int(front)], Vector3.ZERO, Vector3(0, -foot_l, 0), [[0.0, thick * 0.7, thick * 0.72], [1.0, thick * 0.65, thick * 0.65]], 8, 4, Vector3.BACK), skin)
			ModelKit.part(ankle, OrganicMesh.blob("quad_paw_%s_%.2f_%d" % [species, k, int(front)], paw, 0.05, 8, 10), skin, Vector3(0, -foot_l - paw.y * 0.3, -paw.z * 0.35))
			if spec.get("teeth", false) or species == "bog_lurker":
				for c in 3:
					ModelKit.part(ankle, OrganicMesh.bezier("quad_claw_%.2f" % k, Vector3.ZERO, Vector3(0, -0.02, -0.04) * k, Vector3(0, -0.05, -0.06) * k, 0.012 * k, 0.002 * k, 4, 4), CreatureSkin.keratin(Color(0.15, 0.13, 0.1)), Vector3((c - 1) * thick * 0.7, -foot_l - paw.y * 0.2, -paw.z * 1.1))
		var offset_i := 0
		if front:
			offset_i = 0 if side < 0.0 else 2
		else:
			offset_i = 3 if side < 0.0 else 1
		legs.append([hip, knee, ankle, front, side, offset_i])


func _animate(delta: float) -> void:
	var L := float(spec["len"]) * k
	var p := action_progress()
	var w := action_weight(0.1, 0.2)
	var run_speed := 6.0 * sqrt(k * float(spec["len"]))
	_speed = damp(_speed, move_speed, 6.0, delta)
	var walk := clampf(_speed / (run_speed * 0.25), 0.0, 1.0)
	var run := clampf((_speed - run_speed * 0.35) / (run_speed * 0.5), 0.0, 1.0)
	var hop := bool(spec.get("hop", false))
	var stride := L * (0.9 + 0.9 * run)
	_gait += delta * _speed / maxf(0.1, stride)
	_graze = damp(_graze, 1.0 if (grazing and _speed < 0.3 and p < 0.0) else 0.0, 2.0, delta)
	var breathe := sin(_time * (2.2 if not spec.get("prey", false) else 3.0))
	var body_pos := Vector3(0, _hip_h + breathe * 0.006 * L, 0)
	var body_rot := Vector3(0, 0, 0)
	var neck_t := Vector3(-0.1 - _graze * 0.95 + breathe * 0.02, sin(_time * 0.4) * 0.15 * (1.0 - walk), 0)
	var head_t := Vector3(0.1 + _graze * 0.35, sin(_time * 0.7) * 0.1 * (1.0 - walk), 0)
	var jaw_t := 0.03 + (maxf(0.0, sin(_time * 6.0)) * 0.06 * run if not spec.get("prey", false) else 0.0)
	if _graze > 0.5:
		jaw_t = maxf(0.0, sin(_time * 7.0)) * 0.15
	var crouch := 0.0
	var front_lift := 0.0
	# Gallop bounce and pitch.
	var g := _gait * TAU
	body_pos.y += (sin(g * 2.0) * 0.02 * walk + sin(g) * 0.05 * run) * L
	body_rot.x += sin(g) * 0.08 * run
	if _dead:
		var f := clampf(_dead_t / 0.7, 0.0, 1.0)
		body.position = damp_v(body.position, Vector3(0, float(spec["chest"][0]) * k * 0.9, 0), 5.0, delta)
		pose(body, Vector3(0, 0, PI * 0.5 * f), 5.0, delta)
		pose(neck_j, Vector3(0.3, 0, 0), 4.0, delta)
		pose(jaw, Vector3(0.3, 0, 0), 4.0, delta)
		for leg: Array in legs:
			pose(leg[0], Vector3(0.3 if leg[3] else -0.3, 0, 0), 4.0, delta)
			pose(leg[1], Vector3(0.2, 0, 0), 4.0, delta)
		return
	if p >= 0.0:
		match _action:
			"attack", "attack2", "bite":
				var snap := keys(p, [[0, 0], [0.35, -0.5], [0.55, 1.0], [1, 0]])
				neck_t.x += -snap * 0.25
				head_t.x += snap * 0.25
				body_pos.z -= snap * 0.12 * L
				jaw_t = lerpf(jaw_t, keys(p, [[0, 0.05], [0.4, 0.75], [0.58, 0.0], [1, 0.05]]), w)
				crouch = keys(p, [[0, 0], [0.35, 0.4], [0.55, 0.0], [1, 0]])
			"lunge", "pounce":
				crouch = keys(p, [[0, 0], [0.3, 1.0], [0.45, -0.5], [0.9, -0.2], [1, 0]])
				body_rot.x += crouch * 0.12 - maxf(0.0, -crouch) * 0.2
				jaw_t = lerpf(jaw_t, 0.8, w)
				front_lift = maxf(0.0, -crouch)
			"slam":
				# Bears rear up and smash down with both forepaws.
				var rear := keys(p, [[0, 0], [0.45, 1.0], [0.62, -0.25], [1, 0]])
				body_rot.x += rear * 0.75
				body_pos.y += maxf(0.0, rear) * 0.35 * L
				front_lift = maxf(0.0, rear) * 1.5
				jaw_t = lerpf(jaw_t, 0.7, w)
				neck_t.x += rear * 0.3
			"roar", "howl":
				var up := 0.85 if _action == "howl" else 0.35
				neck_t.x = lerpf(neck_t.x, up, w)
				head_t.x = lerpf(head_t.x, up * 0.6 if _action == "howl" else -0.2, w)
				jaw_t = lerpf(jaw_t, 0.6 + sin(_time * 30.0) * 0.03, w)
				if _action == "roar" and species == "bear":
					body_rot.x += 0.5 * w
					front_lift = w * 1.2
			"hit":
				body_rot += Vector3(-0.08, 0, 0.12) * sin(PI * p)
				neck_t.x += 0.2 * sin(PI * p)
	body_pos.y -= crouch * 0.12 * L
	body.position = damp_v(body.position, body_pos, 12.0, delta)
	pose(body, body_rot, 9.0, delta)
	pose(neck_j, neck_t, 7.0, delta)
	pose(head, head_t, 8.0, delta)
	pose(jaw, Vector3(jaw_t, 0, 0), 16.0, delta)
	for i in ears.size():
		var side := -1.0 if i == 0 else 1.0
		var twitch := maxf(0.0, sin(_time * 0.9 + i * 2.7) - 0.92) * 6.0
		pose(ears[i], Vector3(-0.2 * run + twitch * 0.3, 0, side * twitch * 0.2), 12.0, delta)
	for i in tail.size():
		var wag := sin(_time * (1.5 + run * 4.0) - i * 0.6) * (0.15 if spec["tail"] != "croc" else 0.25)
		# Positive x droops the tail; it lifts a little when running.
		var lift := (0.55 if i == 0 else 0.12) - run * 0.3 if spec["tail"] == "bushy" else (0.4 if i == 0 else 0.0)
		if spec["tail"] == "croc":
			lift = 0.1 if i < 2 else 0.02
		elif spec["tail"] in ["flag", "puff"]:
			lift = -0.3
		pose(tail[i], Vector3(lift, wag, 0), 8.0, delta)
	# Legs: walk = lateral sequence, gallop = rotary, hop = bound.
	var walk_off := [0.0, 0.5, 0.25, 0.75]  # LF, RH... indexed by offset_i
	var run_off := [0.0, 0.62, 0.12, 0.5]
	var amp := (0.35 + 0.35 * run) * walk
	for leg: Array in legs:
		var hip: Node3D = leg[0]
		var knee: Node3D = leg[1]
		var ankle: Node3D = leg[2]
		var front: bool = leg[3]
		var oi: int = leg[5]
		var off := lerpf(float(walk_off[oi]), float(run_off[oi]), run)
		if hop:
			off = 0.0 if front else 0.45
		var ph := fposmod(_gait + off, 1.0)
		var duty := lerpf(0.62, 0.42, run)
		var swing: float
		var lift: float
		if ph < duty:
			swing = lerpf(1.0, -1.0, ph / duty)
			lift = 0.0
		else:
			var q := (ph - duty) / (1.0 - duty)
			swing = lerpf(-1.0, 1.0, q)
			lift = sin(PI * q)
		var hip_x := swing * amp
		var knee_x: float
		var ankle_x: float
		if front:
			knee_x = -lift * 1.1 * walk - 0.05
			ankle_x = lift * 0.6 * walk + 0.05
		else:
			knee_x = 0.35 + lift * 0.9 * walk
			ankle_x = -0.45 - lift * 0.3 * walk
			hip_x -= 0.25
		if spec.get("sprawl", false):
			knee_x = -0.9 + lift * 0.4
			ankle_x = 0.0
		if front and front_lift > 0.0:
			hip_x = lerpf(hip_x, 1.1, clampf(front_lift, 0.0, 1.0))
			knee_x = lerpf(knee_x, -1.2, clampf(front_lift, 0.0, 1.0))
		if crouch > 0.0:
			knee_x += crouch * (0.4 if not front else -0.4)
		pose(hip, Vector3(hip_x, 0, hip.rotation.z), 14.0, delta)
		pose(knee, Vector3(knee_x, 0, 0), 14.0, delta)
		pose(ankle, Vector3(ankle_x, 0, 0), 14.0, delta)
