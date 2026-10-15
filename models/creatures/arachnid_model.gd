class_name ArachnidModel
extends CreatureModel
## Eight-legged creatures: giant spiders, spiderlings, scorpions and the
## Broodmother. Smooth swept body parts (cephalothorax, abdomen, chelicerae
## with fangs, pedipalps), an eye cluster that glows, and legs solved with
## two-bone IK every frame from a tetrapod gait (alternating groups of four),
## so feet plant and lift instead of sliding. Scorpions add crushing chelae
## and a segmented tail arching over the back with a glowing sting.
## Faces -Z; `size` is the body length in metres.

var species := "spider"
var size := 1.6
var palette := {}

var body: Node3D
var abdomen: Node3D
var head: Node3D
var fangs: Array[Node3D] = []
var palps: Array[Node3D] = []
var claws: Array = []       # scorpion chelae [arm, pincer]
var tail: Array[Node3D] = []
var legs: Array = []                # [hip(Vector3 local), seg_a: Node3D, seg_b: Node3D, seg_c: Node3D, rest_foot: Vector3, group: int, la, lb, lc, side]
var eye_mats: Array[MeshInstance3D] = []
var sac_glow: Array[MeshInstance3D] = []

var _gait := 0.0
var _walk := 0.0
var _body_h := 0.0
## The Broodmother hangs from the cavern roof on a silk line.
var hanging := false
var _thread: MeshInstance3D


func _init(kind_name := "spider", variant_seed := 0) -> void:
	species = kind_name
	var rng := RandomNumberGenerator.new()
	rng.seed = variant_seed
	match species:
		"spiderling":
			size = 0.7
			palette = {"body": Color(0.55, 0.6, 0.45), "accent": Color(0.2, 0.25, 0.12), "belly": Color(0.75, 0.75, 0.6), "eye": Color(0.7, 1.0, 0.4)}
		"broodmother":
			size = 5.2
			palette = {"body": Color(0.13, 0.1, 0.12), "accent": Color(0.85, 0.82, 0.74), "belly": Color(0.32, 0.22, 0.3), "eye": Color(0.85, 0.35, 1.0), "glow": Color(0.75, 0.4, 1.0)}
		"scorpion":
			size = 2.4
			var sand := [Color(0.62, 0.42, 0.2), Color(0.45, 0.22, 0.12), Color(0.25, 0.2, 0.18)]
			var c: Color = sand[rng.randi() % sand.size()]
			palette = {"body": c, "accent": c.darkened(0.45), "belly": c.lightened(0.25), "eye": Color(1.0, 0.55, 0.15), "glow": Color(0.6, 1.0, 0.3)}
		_:
			size = rng.randf_range(1.5, 2.0)
			var furs := [Color(0.22, 0.17, 0.13), Color(0.12, 0.11, 0.1), Color(0.3, 0.25, 0.2)]
			var c: Color = furs[rng.randi() % furs.size()]
			palette = {"body": c, "accent": Color(0.55, 0.42, 0.25) if rng.randf() < 0.5 else Color(0.6, 0.12, 0.08), "belly": c.lightened(0.15), "eye": Color(1.0, 0.25, 0.15)}
	dissolve_delay = 1.6
	durations["summon"] = 1.6
	durations["roar"] = 1.6
	durations["shoot"] = 0.9
	durations["lunge"] = 0.7


func _ember_extents() -> Vector3:
	return Vector3(0.6, 0.35, 0.8) * size


func _lod_size() -> float:
	return size * 1.4


func _build() -> void:
	var s := size
	var scorp := species == "scorpion"
	var brood := species == "broodmother"
	var shell: ShaderMaterial
	var leg_mat: ShaderMaterial
	if scorp:
		shell = CreatureSkin.chitin(palette["body"], {"accent": palette["accent"], "accent_mode": 3, "accent_amount": 0.6, "accent_scale": 1.0 / s})
		leg_mat = CreatureSkin.chitin((palette["body"] as Color).lightened(0.05), {"pattern_scale": 6.0})
	elif brood:
		shell = CreatureSkin.chitin(palette["body"], {"accent": palette["accent"], "accent_mode": 2, "accent_amount": 0.8, "accent_scale": 0.9 / s * 3.0, "pattern_scale": 1.2})
		leg_mat = CreatureSkin.chitin(palette["body"], {"accent": palette["accent"], "accent_mode": 1, "accent_amount": 0.75, "accent_scale": 1.6, "pattern_scale": 2.0})
	else:
		shell = CreatureSkin.fur(palette["body"], palette["belly"], {"pattern_scale": 14.0, "accent": palette["accent"], "accent_mode": 3, "accent_amount": 0.55, "accent_scale": 1.4 / s})
		leg_mat = CreatureSkin.fur(palette["body"], palette["belly"], {"pattern_scale": 18.0, "accent": palette["accent"], "accent_mode": 1, "accent_amount": 0.7, "accent_scale": 2.2 / s})
	var fang_mat := CreatureSkin.keratin(Color(0.12, 0.1, 0.09), {"roughness": 0.3})
	_body_h = s * (0.42 if scorp else 0.55)
	body = ModelKit.joint(self, "Body", Vector3(0, _body_h, 0))

	# Cephalothorax.
	var ceph_len := s * (0.55 if scorp else 0.42)
	ModelKit.part(body, OrganicMesh.profile("ar_ceph_%s_%.2f" % [species, s], Vector3(0, 0, ceph_len * 0.45), Vector3(0, 0.02 * s, -ceph_len * 0.55),
		[[0.0, 0.05 * s, 0.04 * s], [0.15, 0.24 * s, 0.15 * s, 0.03 * s], [0.6, 0.23 * s, 0.17 * s, 0.05 * s], [0.9, 0.15 * s, 0.11 * s, 0.02 * s], [1.0, 0.04 * s, 0.04 * s]], 14, 12), shell)
	head = ModelKit.joint(body, "Head", Vector3(0, 0.04 * s, -ceph_len * 0.5))
	# Eyes: two big, six small, glowing.
	var eye := CreatureSkin.eye(palette["eye"], 7.0, 0.2)
	var eye_spots := [Vector3(-0.05, 0.12, -0.02), Vector3(0.05, 0.12, -0.02), Vector3(-0.11, 0.1, 0.02), Vector3(0.11, 0.1, 0.02),
			Vector3(-0.08, 0.15, 0.06), Vector3(0.08, 0.15, 0.06), Vector3(-0.14, 0.12, 0.08), Vector3(0.14, 0.12, 0.08)]
	for i in eye_spots.size():
		var r := (0.045 if i < 2 else 0.028) * s
		eye_mats.append(ModelKit.part(head, ModelKit.sphere(r, 8), eye, eye_spots[i] * s))
	# Chelicerae with curved fangs.
	for side: float in [-1.0, 1.0]:
		var ch := ModelKit.joint(head, "Chelicera", Vector3(side * 0.06 * s, 0.0, -0.02 * s))
		ModelKit.part(ch, OrganicMesh.profile("ar_chel_%s_%.2f" % [species, s], Vector3.ZERO, Vector3(0, -0.12 * s, -0.12 * s),
			[[0.0, 0.07 * s, 0.07 * s], [0.6, 0.06 * s, 0.06 * s], [1.0, 0.035 * s, 0.035 * s]], 8, 6), shell)
		var fm := OrganicMesh.bezier("ar_fang_%s_%.2f" % [species, s], Vector3.ZERO, Vector3(0, -0.08 * s, -0.02 * s), Vector3(side * -0.03 * s, -0.13 * s, 0.05 * s), 0.025 * s, 0.003 * s, 6, 5)
		ModelKit.part(ch, fm, fang_mat, Vector3(0, -0.12 * s, -0.12 * s))
		fangs.append(ch)
		if not scorp:
			var palp := ModelKit.joint(head, "Palp", Vector3(side * 0.12 * s, -0.02 * s, -0.02 * s))
			ModelKit.part(palp, OrganicMesh.bezier("ar_palp_%s_%.2f_%d" % [species, s, int(side)], Vector3.ZERO, Vector3(side * 0.06, 0.04, -0.12) * s, Vector3(side * 0.08, -0.1, -0.2) * s, 0.03 * s, 0.022 * s, 6, 6), leg_mat)
			palps.append(palp)

	# Abdomen (spiders) or segmented tail (scorpions).
	if scorp:
		_build_scorpion_parts(shell, leg_mat)
	else:
		abdomen = ModelKit.joint(body, "Abdomen", Vector3(0, 0.08 * s, ceph_len * 0.45))
		var ab := Vector3(0.36, 0.3, 0.5) * s * (1.25 if brood else 1.0)
		var ab_mat := shell
		if brood:
			ab_mat = CreatureSkin.chitin(palette["belly"], {"accent": palette["accent"], "accent_mode": 2, "accent_amount": 0.9, "accent_scale": 1.2,
				"glow_mode": 1, "glow_color": palette["glow"], "glow_amount": 0.25, "glow_energy": 3.0, "glow_pulse": 1.0, "pattern_scale": 1.0})
		ModelKit.part(abdomen, OrganicMesh.blob("ar_abd_%s_%.2f" % [species, s], ab, 0.06, 17, 18), ab_mat, Vector3(0, ab.y * 0.55, ab.z * 0.95))
		# Spinnerets.
		for side: float in [-1.0, 1.0]:
			ModelKit.part(abdomen, ModelKit.cone(0.04 * s, 0.12 * s, 6), leg_mat, Vector3(side * 0.04 * s, ab.y * 0.4, ab.z * 1.9), Vector3(-110, 0, 0))
		if brood:
			# Egg sacs clinging to her back, glowing faintly, and a crown of bone spikes.
			var sac := CreatureSkin.membrane(Color(0.85, 0.82, 0.7), {"glow_mode": 1, "glow_color": palette["glow"], "glow_amount": 0.5, "glow_energy": 2.5, "glow_pulse": 1.0, "backlight": 1.5})
			for i in 7:
				var a := TAU * float(i) / 7.0
				var p := Vector3(cos(a) * ab.x * 0.55, ab.y * 1.25 + sin(a * 2.0) * 0.05 * s, ab.z * 0.95 + sin(a) * ab.z * 0.45)
				sac_glow.append(ModelKit.part(abdomen, OrganicMesh.blob("ar_sac_%d" % (i % 3), Vector3(0.11, 0.09, 0.13) * s, 0.12, 30 + i, 10), sac, p))
			var bone := CreatureSkin.keratin(Color(0.85, 0.82, 0.72))
			for i in 6:
				var x := (float(i) - 2.5) * 0.06 * s
				var hsp := (0.22 - absf(float(i) - 2.5) * 0.04) * s
				ModelKit.part(body, OrganicMesh.bezier("ar_crown_%d" % i, Vector3.ZERO, Vector3(0, hsp * 0.7, hsp * 0.2), Vector3(x * 0.4, hsp, hsp * 0.6), 0.03 * s, 0.004 * s, 6, 5), bone, Vector3(x, 0.15 * s, -0.05 * s))

	_thread = ModelKit.part(body, ModelKit.cylinder(0.03 * s, 0.03 * s, 40.0, 4), LairDecor.silk(), Vector3(0, 20.0 + 0.3 * s, 0.2 * s))
	_thread.visible = false
	# Legs: hips around the cephalothorax, feet on a wide ellipse.
	var leg_count := 4
	var reach := s * (1.15 if not scorp else 0.85)
	for side: float in [-1.0, 1.0]:
		for i in leg_count:
			var f := float(i) / (leg_count - 1)  # 0 front .. 1 back
			var hip := Vector3(side * 0.16 * s, _body_h - 0.02 * s, lerpf(-0.14, 0.14, f) * s * (1.6 if scorp else 1.0))
			var ang := deg_to_rad(lerpf(-50.0, 60.0, f))
			var foot := Vector3(side * cos(ang) * reach * (0.85 + 0.15 * sin(f * PI)), 0.0, sin(ang) * reach * 0.95 + (0.25 * s if scorp else 0.0))
			var la := reach * 0.62
			var lb := reach * 0.68
			var lc := reach * 0.18
			var seg_a := Node3D.new()
			var seg_b := Node3D.new()
			var seg_c := Node3D.new()
			add_child(seg_a)
			add_child(seg_b)
			add_child(seg_c)
			var key := "ar_leg_%s_%.2f" % [species, s]
			ModelKit.part(seg_a, OrganicMesh.profile(key + "_a", Vector3.ZERO, Vector3(0, la, 0), [[0.0, 0.055 * s, 0.055 * s], [0.12, 0.07 * s, 0.07 * s], [0.85, 0.05 * s, 0.05 * s], [1.0, 0.04 * s, 0.04 * s]], 8, 6, Vector3.BACK), leg_mat)
			ModelKit.part(seg_b, OrganicMesh.profile(key + "_b", Vector3.ZERO, Vector3(0, lb, 0), [[0.0, 0.045 * s, 0.045 * s], [0.2, 0.05 * s, 0.05 * s], [1.0, 0.028 * s, 0.028 * s]], 8, 6, Vector3.BACK), leg_mat)
			ModelKit.part(seg_c, OrganicMesh.profile(key + "_c", Vector3.ZERO, Vector3(0, lc, 0), [[0.0, 0.028 * s, 0.028 * s], [1.0, 0.01 * s, 0.01 * s]], 6, 4, Vector3.BACK), fang_mat if brood else leg_mat)
			var group := (i + (0 if side < 0.0 else 1)) % 2
			legs.append([hip, seg_a, seg_b, seg_c, foot, group, la, lb, lc, side])


func _build_scorpion_parts(shell: ShaderMaterial, leg_mat: ShaderMaterial) -> void:
	var s := size
	# Mesosoma: a long segmented back.
	abdomen = ModelKit.joint(body, "Mesosoma", Vector3(0, 0.0, 0.18 * s))
	for i in 6:
		var w := (0.22 - absf(float(i) - 2.0) * 0.015) * s
		ModelKit.part(abdomen, OrganicMesh.blob("sc_plate_%d_%.2f" % [i, s], Vector3(w, w * 0.5, 0.08 * s), 0.04, 3 + i, 12), shell, Vector3(0, 0.02 * s, float(i) * 0.1 * s))
	# Tail: five segments arching over the back, then the sting.
	var parent: Node3D = ModelKit.joint(abdomen, "Tail", Vector3(0, 0.03 * s, 0.6 * s))
	for i in 5:
		var j := ModelKit.joint(parent, "T%d" % i, Vector3(0, 0, 0.0 if i == 0 else 0.15 * s))
		var r := (0.075 - i * 0.006) * s
		ModelKit.part(j, OrganicMesh.blob("sc_tail_%d_%.2f" % [i, s], Vector3(r, r * 0.9, 0.09 * s), 0.05, 40 + i, 10), shell, Vector3(0, 0, 0.075 * s))
		tail.append(j)
		parent = j
	var sting := ModelKit.joint(parent, "Sting", Vector3(0, 0, 0.16 * s))
	ModelKit.part(sting, OrganicMesh.blob("sc_bulb_%.2f" % s, Vector3(0.07, 0.06, 0.09) * s, 0.05, 9, 10), shell, Vector3(0, 0, 0.05 * s))
	ModelKit.part(sting, OrganicMesh.bezier("sc_sting_%.2f" % s, Vector3.ZERO, Vector3(0, -0.06, 0.08) * s, Vector3(0, -0.14, 0.02) * s, 0.03 * s, 0.003 * s, 6, 5), CreatureSkin.keratin(Color(0.1, 0.08, 0.06)), Vector3(0, 0, 0.12 * s))
	ModelKit.part(sting, ModelKit.sphere(0.03 * s, 6), ModelKit.glow(palette["glow"], 5.0, 0.6), Vector3(0, -0.06, 0.16) * s)
	tail.append(sting)
	# Chelae: arm + heavy pincer with a moving finger.
	for side: float in [-1.0, 1.0]:
		var arm := ModelKit.joint(head, "Arm", Vector3(side * 0.14 * s, -0.02 * s, 0.02 * s))
		ModelKit.part(arm, OrganicMesh.bezier("sc_arm_%.2f_%d" % [s, int(side)], Vector3.ZERO, Vector3(side * 0.2, 0.05, -0.1) * s, Vector3(side * 0.22, 0.0, -0.32) * s, 0.05 * s, 0.045 * s, 6, 7), leg_mat)
		var hand := ModelKit.joint(arm, "Pincer", Vector3(side * 0.22, 0.0, -0.32) * s)
		ModelKit.part(hand, OrganicMesh.blob("sc_hand_%.2f" % s, Vector3(0.09, 0.07, 0.15) * s, 0.06, 77, 12), shell, Vector3(0, 0, -0.08 * s))
		ModelKit.part(hand, OrganicMesh.bezier("sc_finger_a_%.2f_%d" % [s, int(side)], Vector3.ZERO, Vector3(side * -0.02, 0, -0.12) * s, Vector3(side * -0.05, 0, -0.22) * s, 0.035 * s, 0.006 * s, 6, 6), shell, Vector3(side * 0.04 * s, 0, -0.2 * s))
		var finger := ModelKit.joint(hand, "Finger", Vector3(side * -0.04 * s, 0, -0.2 * s))
		ModelKit.part(finger, OrganicMesh.bezier("sc_finger_b_%.2f_%d" % [s, int(side)], Vector3.ZERO, Vector3(side * 0.02, 0, -0.1) * s, Vector3(side * 0.05, 0, -0.18) * s, 0.03 * s, 0.005 * s, 6, 6), shell)
		claws.append([arm, hand, finger, side])


func _animate(delta: float) -> void:
	var s := size
	var p := action_progress()
	var w := action_weight(0.1, 0.2)
	_walk = damp(_walk, clampf(move_speed / (1.6 * s + 1.0), 0.0, 1.0), 6.0, delta)
	var cadence := 1.6 + 1.4 / maxf(0.5, s)
	_gait += delta * TAU * cadence * clampf(move_speed / (1.2 * s + 0.6), 0.0, 2.0)
	var breathe := sin(_time * 2.0)
	var body_pos := Vector3(0, _body_h + breathe * 0.01 * s - absf(sin(_gait * 2.0)) * 0.02 * s * _walk, 0)
	var body_rot := Vector3(0, 0, sin(_gait) * 0.03 * _walk)
	var fang_t := 0.1 + sin(_time * 3.0) * 0.08
	var front_raise := 0.0
	var abd_t := Vector3(sin(_time * 1.4) * 0.03, 0, 0)
	var tail_curl := 0.0
	var claw_open := 0.15 + sin(_time * 1.7) * 0.1
	var claw_reach := 0.0
	var sting_strike := 0.0
	var crouch := 0.0
	if _dead:
		var f := clampf(_dead_t / 0.8, 0.0, 1.0)
		body.position = damp_v(body.position, Vector3(0, 0.12 * s, 0), 6.0, delta)
		pose(body, Vector3(0, 0, 0.15 * f), 4.0, delta)
		_pose_legs(delta, true)
		return
	if p >= 0.0:
		match _action:
			"attack", "attack2", "bite":
				var strike := keys(p, [[0, 0], [0.35, -0.6], [0.55, 1.0], [1, 0]])
				body_pos.z -= strike * 0.25 * s
				body_rot.x += -strike * 0.15
				fang_t = lerpf(fang_t, keys(p, [[0, 0.2], [0.4, 1.1], [0.6, -0.2], [1, 0.1]]), w)
				claw_reach = strike
				claw_open = lerpf(claw_open, keys(p, [[0, 0.2], [0.4, 0.9], [0.6, 0.0], [1, 0.2]]), w)
				sting_strike = keys(p, [[0, 0], [0.4, -0.5], [0.6, 1.0], [1, 0]]) if species == "scorpion" and _action == "attack2" else 0.0
			"lunge", "pounce":
				crouch = keys(p, [[0, 0], [0.25, 1.0], [0.4, -0.6], [0.8, -0.2], [1, 0]])
				body_rot.x += -crouch * 0.25
				fang_t = lerpf(fang_t, 1.0, w)
				front_raise = maxf(0.0, -crouch) * 0.8
			"shoot", "throw", "cast":
				abd_t.x += keys(p, [[0, 0], [0.4, -0.7], [0.6, 0.3], [1, 0]]) * w
				body_rot.x += keys(p, [[0, 0], [0.4, 0.2], [0.6, -0.1], [1, 0]])
				sting_strike = keys(p, [[0, 0], [0.4, -0.4], [0.6, 1.0], [1, 0]]) if species == "scorpion" else 0.0
			"roar", "howl", "summon":
				front_raise = w
				body_rot.x += 0.35 * w
				fang_t = lerpf(fang_t, 1.0 + sin(_time * 30.0) * 0.1, w)
				abd_t.x += sin(_time * 12.0) * 0.08 * w
				claw_open = lerpf(claw_open, 1.0, w)
				tail_curl = 0.3 * w
			"slam", "spikes":
				var stab := keys(p, [[0, 0], [0.45, 1.0], [0.6, -0.4], [1, 0]])
				front_raise = maxf(0.0, stab)
				body_rot.x += stab * 0.3 - maxf(0.0, -stab) * 0.4
			"hit":
				body_rot += Vector3(0.2, 0, 0.1) * sin(PI * p)
				body_pos.y += 0.05 * s * sin(PI * p)
	body_pos.y -= crouch * 0.15 * s
	_thread.visible = hanging
	if hanging:
		# Dangling: legs drawn in, slowly turning on the line.
		body_rot = Vector3(0.2, sin(_time * 0.7) * 0.4, sin(_time * 1.1) * 0.08)
		front_raise = 0.6
	body.position = damp_v(body.position, body_pos, 12.0, delta)
	pose(body, body_rot, 10.0, delta)
	for i in fangs.size():
		var side := -1.0 if i == 0 else 1.0
		pose(fangs[i], Vector3(fang_t * 0.4, side * fang_t * 0.25, 0), 18.0, delta)
	for i in palps.size():
		pose(palps[i], Vector3(sin(_time * 4.0 + i * 2.0) * 0.25 - front_raise * 0.4, 0, 0), 10.0, delta)
	if abdomen != null and species != "scorpion":
		pose(abdomen, abd_t, 8.0, delta)
		for g in sac_glow:
			g.set_instance_shader_parameter(&"intensity", 1.0 + (1.5 if _action == "summon" else 0.0))
	if species == "scorpion":
		for i in tail.size():
			var curl := 0.55 + tail_curl * 0.2 - sting_strike * (0.25 if i < 3 else -0.15)
			pose(tail[i], Vector3(-curl + sin(_time * 1.6 + i * 0.6) * 0.04, sin(_time * 0.9 + i * 0.5) * 0.06, 0), 12.0, delta)
		for c: Array in claws:
			var arm: Node3D = c[0]
			var finger: Node3D = c[2]
			var side: float = c[3]
			pose(arm, Vector3(0.1 - claw_reach * 0.3, side * (-0.15 + claw_reach * 0.35), 0), 12.0, delta)
			pose(finger, Vector3(0, side * -claw_open * 0.5, 0), 18.0, delta)
	_pose_legs(delta, false, front_raise)


## Tetrapod gait with two-bone IK per leg.
func _pose_legs(delta: float, dead: bool, front_raise := 0.0) -> void:
	var s := size
	var bt := Transform3D(Basis.from_euler(body.rotation), body.position - Vector3(0, _body_h, 0))
	for leg: Array in legs:
		var hip: Vector3 = bt * (leg[0] as Vector3)
		var rest: Vector3 = leg[4]
		var group: int = leg[5]
		var la: float = leg[6]
		var lb: float = leg[7]
		var lc: float = leg[8]
		var side: float = leg[9]
		var foot := rest
		if dead:
			# Legs curl up beneath the body.
			foot = Vector3(side * 0.25 * s, 0.35 * s, rest.z * 0.3)
		else:
			var ph := _gait + (PI if group == 1 else 0.0)
			var stride := 0.28 * s * _walk
			foot.z += -cos(ph) * stride
			foot.y += maxf(0.0, sin(ph)) * 0.22 * s * _walk
			if rest.z < -0.3 * s and front_raise > 0.0:
				foot = foot.lerp(Vector3(rest.x * 0.6, _body_h + 0.5 * s, rest.z - 0.2 * s), front_raise)
		var tip := foot + Vector3(0, lc * 0.9, 0)
		var pole := Vector3(side, 1.6, 0).normalized()
		var knee := _ik_knee(hip, tip, la, lb, pole)
		_orient(leg[1], hip, knee)
		_orient(leg[2], knee, tip)
		_orient(leg[3], tip, foot)


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
