class_name GolemModel
extends CreatureModel
## Deep-cave rock golem: a hulking body of fitted boulders held together by
## glowing crystal veins (amethyst, ember or frost by variant), long arms
## ending in fists that drag near the ground, a small sunken head with one
## burning eye-slit, and short pillar legs. Lumbering gait; slams with both
## fists, punches, and roars by grinding its plates. Faces -Z.

var size := 2.6
var vein := Color(0.75, 0.4, 1.0)

var pelvis: Node3D
var torso: Node3D
var head: Node3D
var arms: Array = []   # [shoulder, elbow, side]
var legs: Array = []   # [hip, knee, side]
var _gait := 0.0
var _walk := 0.0


func _init(variant_seed := 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = variant_seed
	size = rng.randf_range(2.4, 3.0)
	var veins := [Color(0.75, 0.4, 1.0), Color(1.0, 0.45, 0.12), Color(0.45, 0.85, 1.0)]
	vein = veins[rng.randi() % veins.size()]
	dissolve_delay = 1.6
	durations["slam"] = 1.3


func _ember_extents() -> Vector3:
	return Vector3(0.6, 1.0, 0.5) * size * 0.5


func _lod_size() -> float:
	return size * 1.2


func _build() -> void:
	var s := size / 2.6
	var stone := CreatureSkin.rock(Color(0.36, 0.34, 0.33), {"glow_mode": 2, "glow_color": vein, "glow_amount": 0.18, "glow_energy": 3.5, "glow_pulse": 0.5, "pattern_scale": 1.4 / s})
	var dark := CreatureSkin.rock(Color(0.22, 0.21, 0.21), {"pattern_scale": 2.0 / s})
	var moss := CreatureSkin.fur(Color(0.22, 0.28, 0.14), Color(0.18, 0.22, 0.12), {"pattern_scale": 18.0})
	var crystal := ModelKit.glow(vein, 4.0, 0.4)
	pelvis = ModelKit.joint(self, "Pelvis", Vector3(0, 1.0 * s, 0))
	ModelKit.part(pelvis, OrganicMesh.blob("golem_pelvis", Vector3(0.5, 0.3, 0.38) * s, 0.25, 3, 12), stone)
	torso = ModelKit.joint(pelvis, "Torso", Vector3(0, 0.25 * s, 0))
	ModelKit.part(torso, OrganicMesh.blob("golem_chest", Vector3(0.85, 0.65, 0.6) * s, 0.22, 5, 16), stone, Vector3(0, 0.75 * s, -0.05 * s), Vector3(-12, 0, 0))
	ModelKit.part(torso, OrganicMesh.blob("golem_back", Vector3(0.7, 0.45, 0.45) * s, 0.3, 8, 12), dark, Vector3(0, 1.05 * s, 0.25 * s), Vector3(20, 0, 0))
	ModelKit.part(torso, OrganicMesh.blob("golem_belly", Vector3(0.55, 0.35, 0.42) * s, 0.25, 11, 12), dark, Vector3(0, 0.25 * s, -0.05 * s))
	ModelKit.part(torso, OrganicMesh.blob("golem_moss", Vector3(0.55, 0.12, 0.4) * s, 0.5, 13, 12), moss, Vector3(0.1 * s, 1.38 * s, 0.15 * s), Vector3(15, 0, 8))
	# Crystals bursting from the shoulders and back.
	for i in 6:
		var a := float(i) / 5.0
		var p := Vector3(lerpf(-0.6, 0.6, a) * s, (1.25 + sin(a * PI) * 0.25) * s, (0.3 + 0.1 * sin(i * 2.3)) * s)
		ModelKit.part(torso, ModelKit.cone(0.09 * s, (0.35 + 0.25 * sin(i * 1.7)) * s, 5), crystal, p, Vector3(25 + i * 7, i * 30, (a - 0.5) * 50))
	head = ModelKit.joint(torso, "Head", Vector3(0, 1.3 * s, -0.42 * s))
	ModelKit.part(head, OrganicMesh.blob("golem_head", Vector3(0.28, 0.24, 0.26) * s, 0.2, 17, 12), stone)
	ModelKit.part(head, ModelKit.box(Vector3(0.3, 0.05, 0.05) * s), ModelKit.glow(vein, 9.0, 0.3), Vector3(0, 0.02 * s, -0.24 * s))
	ModelKit.part(head, OrganicMesh.blob("golem_brow", Vector3(0.32, 0.08, 0.12) * s, 0.2, 19, 10), dark, Vector3(0, 0.12 * s, -0.2 * s))
	for side: float in [-1.0, 1.0]:
		var sh := ModelKit.joint(torso, "Shoulder", Vector3(side * 0.9 * s, 1.0 * s, 0))
		ModelKit.part(sh, OrganicMesh.blob("golem_pauldron", Vector3(0.42, 0.35, 0.4) * s, 0.3, 23, 12), dark, Vector3(side * 0.05 * s, 0.1 * s, 0))
		ModelKit.part(sh, OrganicMesh.blob("golem_upper", Vector3(0.26, 0.5, 0.26) * s, 0.25, 29, 10), stone, Vector3(0, -0.45 * s, 0))
		var el := ModelKit.joint(sh, "Elbow", Vector3(0, -0.9 * s, 0))
		ModelKit.part(el, OrganicMesh.blob("golem_fore", Vector3(0.28, 0.5, 0.28) * s, 0.25, 31, 10), stone, Vector3(0, -0.4 * s, 0))
		ModelKit.part(el, OrganicMesh.blob("golem_fist", Vector3(0.38, 0.32, 0.38) * s, 0.2, 37, 12), dark, Vector3(0, -0.95 * s, 0))
		ModelKit.part(el, ModelKit.cone(0.06 * s, 0.25 * s, 5), crystal, Vector3(side * 0.15 * s, -0.25 * s, 0.15 * s), Vector3(30, 0, side * -40))
		arms.append([sh, el, side])
		var hip := ModelKit.joint(pelvis, "Hip", Vector3(side * 0.35 * s, -0.1 * s, 0))
		ModelKit.part(hip, OrganicMesh.blob("golem_thigh", Vector3(0.26, 0.35, 0.28) * s, 0.2, 41, 10), stone, Vector3(0, -0.3 * s, 0))
		var kn := ModelKit.joint(hip, "Knee", Vector3(0, -0.55 * s, 0))
		ModelKit.part(kn, OrganicMesh.blob("golem_shin", Vector3(0.24, 0.3, 0.26) * s, 0.2, 43, 10), dark, Vector3(0, -0.2 * s, 0))
		ModelKit.part(kn, OrganicMesh.blob("golem_foot", Vector3(0.3, 0.14, 0.38) * s, 0.15, 47, 10), stone, Vector3(0, -0.4 * s, -0.08 * s))
		legs.append([hip, kn, side])
	var light := OmniLight3D.new()
	light.light_color = vein
	light.light_energy = 1.2
	light.omni_range = 6.0 * s
	light.shadow_enabled = false
	light.position = Vector3(0, 1.0 * s, -0.4 * s)
	torso.add_child(light)


func _animate(delta: float) -> void:
	var s := size / 2.6
	var p := action_progress()
	var w := action_weight(0.12, 0.2)
	_walk = damp(_walk, clampf(move_speed / 2.0, 0.0, 1.0), 5.0, delta)
	_gait += delta * TAU * move_speed / (2.2 * s)
	var sway := sin(_gait) * 0.08 * _walk
	var torso_t := Vector3(0.18 + sin(_time * 0.8) * 0.02, sway * 0.6, sway)
	var pelvis_y := 1.0 * s - absf(sin(_gait)) * 0.06 * s * _walk
	var arm_t := [Vector3(sin(_gait) * 0.35 * _walk + 0.1, 0, -0.15), Vector3(-sin(_gait) * 0.35 * _walk + 0.1, 0, 0.15)]
	var elbow_t := [Vector3(-0.35, 0, 0), Vector3(-0.35, 0, 0)]
	var head_t := Vector3(sin(_time * 0.5) * 0.05, sin(_time * 0.3) * 0.15, 0)
	if _dead:
		var f := clampf(_dead_t / 1.0, 0.0, 1.0)
		pelvis.position = damp_v(pelvis.position, Vector3(0, 0.5 * s, 0), 4.0, delta)
		pose(torso, Vector3(0.9 * f, 0, 0.2), 3.0, delta)
		for a: Array in arms:
			pose(a[0], Vector3(0.6, 0, float(a[2]) * 0.5), 3.0, delta)
		for l: Array in legs:
			pose(l[0], Vector3(1.2 * f, 0, 0), 3.0, delta)
			pose(l[1], Vector3(-1.4 * f, 0, 0), 3.0, delta)
		return
	if p >= 0.0:
		match _action:
			"slam", "spikes":
				var lift := keys(p, [[0, 0], [0.5, 1.0], [0.65, -0.4], [1, 0]])
				for i in 2:
					arm_t[i] = (arm_t[i] as Vector3).lerp(Vector3(2.6 * maxf(0.0, lift) - 0.6 * maxf(0.0, -lift), 0, (-0.2 if i == 0 else 0.2)), w)
					elbow_t[i] = (elbow_t[i] as Vector3).lerp(Vector3(-0.6 * maxf(0.0, lift), 0, 0), w)
				torso_t.x += -0.3 * maxf(0.0, lift) + 0.5 * maxf(0.0, -lift)
				pelvis_y -= maxf(0.0, -lift) * 0.2 * s
			"attack", "attack2":
				var i := 1 if _action == "attack" else 0
				var punch := keys(p, [[0, 0], [0.4, -0.6], [0.6, 1.2], [1, 0]])
				arm_t[i] = (arm_t[i] as Vector3).lerp(Vector3(1.4 * punch + 0.3, 0, 0), w)
				elbow_t[i] = (elbow_t[i] as Vector3).lerp(Vector3(-0.2 - maxf(0.0, -punch) * 1.2, 0, 0), w)
				torso_t.y += (0.35 if i == 1 else -0.35) * punch * w
			"roar":
				torso_t.x -= 0.3 * w
				head_t.x -= 0.4 * w
				arm_t[0] = (arm_t[0] as Vector3).lerp(Vector3(0.4, 0, -0.9), w)
				arm_t[1] = (arm_t[1] as Vector3).lerp(Vector3(0.4, 0, 0.9), w)
			"hit":
				torso_t.x -= 0.2 * sin(PI * p)
	pelvis.position = damp_v(pelvis.position, Vector3(0, pelvis_y, 0), 10.0, delta)
	pose(torso, torso_t, 7.0, delta)
	pose(head, head_t, 6.0, delta)
	for i in 2:
		pose(arms[i][0], arm_t[i], 9.0, delta)
		pose(arms[i][1], elbow_t[i], 9.0, delta)
	for l: Array in legs:
		var side: float = l[2]
		var ph := _gait + (0.0 if side < 0.0 else PI)
		var swing := sin(ph) * 0.4 * _walk
		var bend := maxf(0.0, cos(ph)) * 0.6 * _walk
		pose(l[0], Vector3(swing + bend * 0.4, 0, 0), 10.0, delta)
		pose(l[1], Vector3(-bend, 0, 0), 10.0, delta)
