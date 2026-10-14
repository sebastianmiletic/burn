class_name DragonModel
extends CreatureModel
## Ashvane, the dragon of the Keep: a long spine with a five-joint neck,
## hinged jaw and glowing throat, an eight-joint tail that follows the body,
## four legs with a diagonal gait, and membrane wings that fold, spread and
## flap. About 16 m from snout to tail tip. Faces -Z.

var flying := false

var body: Node3D
var neck: Array[Node3D] = []
var head: Node3D
var jaw: Node3D
var mouth: Node3D
var tail: Array[Node3D] = []
var legs: Array = []  # [hip, knee, ankle, side, front]
var wing_l: Node3D
var wing_r: Node3D
var elbow_l: Node3D
var elbow_r: Node3D
var fire: FireStream
var throat: MeshInstance3D

var _gait := 0.0
var _walk := 0.0
var _fly := 0.0
var _flap := 0.0
var _body_y := 2.9


func _init() -> void:
	dissolve_delay = 2.0
	dissolve_time = 2.5
	durations["breath"] = 3.0
	durations["takeoff"] = 1.6
	durations["dive"] = 1.4


func _ember_extents() -> Vector3:
	return Vector3(2.2, 1.5, 5.0)


func mouth_node() -> Node3D:
	return mouth


func _build() -> void:
	var scale_c := Color(0.32, 0.11, 0.07)
	var scales := ModelKit.mat(scale_c, AsciiMaterialId.SOLID, 0.55, 0.35)
	var belly := ModelKit.mat(Color(0.62, 0.42, 0.24), AsciiMaterialId.SOLID, 0.7, 0.3)
	var horn := ModelKit.mat(Color(0.85, 0.78, 0.62), AsciiMaterialId.SOLID, 0.5, 0.2)
	var dark := ModelKit.mat(Color(0.13, 0.05, 0.04), AsciiMaterialId.SOLID, 0.5, 0.2)
	var membrane := ModelKit.mat(Color(0.4, 0.12, 0.07), AsciiMaterialId.CLOTH, 0.9, 0.4)

	body = ModelKit.joint(self, "Body", Vector3(0, _body_y, 0))
	ModelKit.part(body, ModelKit.capsule(1.25, 4.6, 10), scales, Vector3(0, 0, -0.3), Vector3(90, 0, 0))
	ModelKit.part(body, ModelKit.capsule(1.0, 2.8, 10), scales, Vector3(0, -0.1, 2.4), Vector3(90, 0, 0))
	ModelKit.part(body, ModelKit.box(Vector3(1.4, 0.4, 4.6)), belly, Vector3(0, -1.0, 0.2))
	for i in 9:
		var z := -2.2 + i * 0.75
		ModelKit.part(body, ModelKit.cone(0.22, 0.75 - absf(i - 3) * 0.06, 4), horn, Vector3(0, 1.15 - absf(z) * 0.05, z), Vector3(-20, 0, 0))

	# Neck and head
	var parent := ModelKit.joint(body, "NeckBase", Vector3(0, 0.6, -2.3))
	for i in 5:
		var j := ModelKit.joint(parent, "Neck%d" % i, Vector3(0, 0, 0.0 if i == 0 else -0.95))
		var r := 0.66 - i * 0.05
		ModelKit.part(j, ModelKit.capsule(r, 1.35, 8), scales, Vector3(0, 0, -0.45), Vector3(90, 0, 0))
		ModelKit.part(j, ModelKit.box(Vector3(r * 1.1, 0.25, 0.8)), belly, Vector3(0, -r * 0.85, -0.45))
		ModelKit.part(j, ModelKit.cone(0.14, 0.45, 4), horn, Vector3(0, r + 0.1, -0.4), Vector3(-25, 0, 0))
		neck.append(j)
		parent = j
	head = ModelKit.joint(parent, "Head", Vector3(0, 0, -0.95))
	ModelKit.part(head, ModelKit.box(Vector3(1.0, 0.8, 1.2)), scales, Vector3(0, 0.15, -0.4))
	ModelKit.part(head, ModelKit.box(Vector3(0.72, 0.42, 1.25)), scales, Vector3(0, 0.12, -1.45))
	ModelKit.part(head, ModelKit.box(Vector3(0.5, 0.12, 0.4)), dark, Vector3(0, 0.36, -1.85))
	for side: float in [-1.0, 1.0]:
		ModelKit.part(head, ModelKit.cone(0.13, 1.1, 5), horn, Vector3(side * 0.38, 0.6, 0.15), Vector3(-60, 0, -side * 20))
		ModelKit.part(head, ModelKit.cone(0.08, 0.6, 4), horn, Vector3(side * 0.5, 0.2, 0.1), Vector3(-80, 0, -side * 50))
		ModelKit.part(head, ModelKit.box(Vector3(0.16, 0.08, 0.1)), ModelKit.glow(Color(1.0, 0.6, 0.15), 8.0, 0.2), Vector3(side * 0.42, 0.4, -0.85))
		for k in 4:
			ModelKit.part(head, ModelKit.cone(0.04, 0.16, 3), horn, Vector3(side * 0.3, -0.12, -1.0 - k * 0.22), Vector3(180, 0, 0))
	jaw = ModelKit.joint(head, "Jaw", Vector3(0, -0.15, -0.2))
	ModelKit.part(jaw, ModelKit.box(Vector3(0.66, 0.2, 1.75)), scales, Vector3(0, -0.12, -0.9))
	for side: float in [-1.0, 1.0]:
		for k in 4:
			ModelKit.part(jaw, ModelKit.cone(0.035, 0.14, 3), horn, Vector3(side * 0.26, 0.02, -0.6 - k * 0.3), Vector3.ZERO)
	throat = ModelKit.part(head, ModelKit.sphere(0.32, 8), ModelKit.glow(Color(1.0, 0.45, 0.1), 6.0, 0.6), Vector3(0, -0.05, -0.55))
	mouth = ModelKit.joint(head, "Mouth", Vector3(0, -0.05, -2.0))
	fire = FireStream.new().setup(15.0, 13.0, 1.8)
	mouth.add_child(fire)

	# Tail
	parent = ModelKit.joint(body, "TailBase", Vector3(0, 0.0, 3.6))
	for i in 8:
		var j := ModelKit.joint(parent, "Tail%d" % i, Vector3(0, 0, 0.0 if i == 0 else 1.05))
		var r := maxf(0.14, 0.75 - i * 0.085)
		ModelKit.part(j, ModelKit.capsule(r, 1.4, 8), scales, Vector3(0, 0, 0.5), Vector3(90, 0, 0))
		ModelKit.part(j, ModelKit.cone(r * 0.35, r * 0.9 + 0.1, 4), horn, Vector3(0, r + 0.05, 0.5), Vector3(-20, 0, 0))
		tail.append(j)
		parent = j
	ModelKit.part(parent, ModelKit.slab(PackedVector2Array([Vector2(0, 0), Vector2(0.55, 0.5), Vector2(0, 1.4), Vector2(-0.55, 0.5)]), 0.08), horn, Vector3(0, 0, 1.0), Vector3(90, 0, 0))

	# Legs
	for spec: Array in [[-1.0, true], [1.0, true], [-1.0, false], [1.0, false]]:
		var side: float = spec[0]
		var front: bool = spec[1]
		var hip := ModelKit.joint(body, "Hip", Vector3(side * (1.15 if front else 1.0), -0.45, -1.4 if front else 2.6))
		ModelKit.part(hip, ModelKit.capsule(0.46, 1.6, 8), scales, Vector3(0, -0.6, 0))
		var knee := ModelKit.joint(hip, "Knee", Vector3(0, -1.25, 0))
		ModelKit.part(knee, ModelKit.capsule(0.32, 1.4, 8), scales, Vector3(0, -0.55, 0))
		var ankle := ModelKit.joint(knee, "Ankle", Vector3(0, -1.15, 0))
		ModelKit.part(ankle, ModelKit.box(Vector3(0.6, 0.25, 0.8)), scales, Vector3(0, -0.12, -0.2))
		for k in 3:
			ModelKit.part(ankle, ModelKit.cone(0.07, 0.35, 4), horn, Vector3((k - 1) * 0.2, -0.15, -0.68), Vector3(-90, 0, 0))
		legs.append([hip, knee, ankle, side, front])

	# Wings: inner membrane on the shoulder joint, outer on the elbow.
	for side: float in [-1.0, 1.0]:
		var wing := ModelKit.joint(body, "Wing", Vector3(side * 0.95, 1.0, -1.1))
		ModelKit.part(wing, ModelKit.capsule(0.2, 3.4, 6), scales, Vector3(side * 1.6, 0, 0), Vector3(0, 0, 90))
		var inner := PackedVector2Array([Vector2(0, 0.0), Vector2(3.2, 0.0), Vector2(3.0, 2.6), Vector2(1.4, 3.6), Vector2(0, 2.8)])
		var elbow := ModelKit.joint(wing, "Elbow", Vector3(side * 3.2, 0, 0))
		ModelKit.part(elbow, ModelKit.capsule(0.16, 3.8, 6), scales, Vector3(side * 1.8, 0, 0), Vector3(0, 0, 90))
		var outer := PackedVector2Array([Vector2(0, 0), Vector2(3.6, 0), Vector2(5.0, 1.0), Vector2(4.4, 3.6), Vector2(2.6, 4.4), Vector2(0.6, 3.3), Vector2(-0.1, 2.6)])
		for f in 3:
			var ang := deg_to_rad(20 + f * 28)
			var length := 4.6 - f * 0.6
			var tip := Vector3(cos(ang) * side, 0, sin(ang)) * length
			var spar := ModelKit.part(elbow, ModelKit.cylinder(0.04, 0.09, length, 4), dark, Vector3(side * 3.6, 0, 0) + tip * 0.5)
			spar.basis = Basis(Quaternion(Vector3.UP, tip.normalized()))
		if side < 0.0:
			for i in inner.size():
				inner[i].x = -inner[i].x
			for i in outer.size():
				outer[i].x = -outer[i].x
		ModelKit.part(wing, ModelKit.slab(inner, 0.06), membrane, Vector3.ZERO, Vector3(90, 0, 0))
		ModelKit.part(elbow, ModelKit.slab(outer, 0.06), membrane, Vector3.ZERO, Vector3(90, 0, 0))
		ModelKit.part(elbow, ModelKit.cone(0.12, 0.6, 4), horn, Vector3(side * 0.1, 0.25, 0), Vector3.ZERO)
		if side < 0.0:
			wing_l = wing
			elbow_l = elbow
		else:
			wing_r = wing
			elbow_r = elbow


func _animate(delta: float) -> void:
	var p := action_progress()
	var w := action_weight(0.1, 0.18)
	_walk = damp(_walk, clampf(move_speed / 4.0, 0.0, 1.0), 5.0, delta)
	_fly = damp(_fly, 1.0 if (flying or not grounded) else 0.0, 3.0, delta)
	_gait += delta * TAU * move_speed / 5.5
	var flap_speed := 1.4 + (1.0 if _action == "takeoff" or _action == "gust" else 0.0)
	_flap += delta * TAU * flap_speed * maxf(_fly, 0.3 if _action == "gust" else 0.0)
	var breathe := sin(_time * 1.2)

	if _dead:
		var f := clampf(_dead_t / 1.6, 0.0, 1.0)
		body.position = damp_v(body.position, Vector3(0, 1.1, 0), 3.0, delta)
		pose(body, Vector3(0.05, 0, 0.25 * f), 3.0, delta)
		for i in neck.size():
			pose(neck[i], Vector3(-0.25 if i == 0 else 0.05, 0.12, 0), 3.0, delta)
		pose(jaw, Vector3(0.35, 0, 0), 4.0, delta)
		pose(wing_l, Vector3(0, 0.1, 0.35), 2.0, delta)
		pose(wing_r, Vector3(0, -0.1, -0.35), 2.0, delta)
		pose(elbow_l, Vector3(0, 0.3, 0.1), 2.0, delta)
		pose(elbow_r, Vector3(0, -0.3, -0.1), 2.0, delta)
		for leg: Array in legs:
			pose(leg[0], Vector3(0, 0, -0.9 * float(leg[3])), 3.0, delta)
			pose(leg[1], Vector3(0.6, 0, 0), 3.0, delta)
		if fire.emitting:
			fire.set_on(false)
		throat.set_instance_shader_parameter(&"intensity", 0.0)
		return

	# --- Body ---------------------------------------------------------------
	var body_t := Vector3(-0.05 * _walk + breathe * 0.01, 0, 0)
	var body_pos := Vector3(0, _body_y + breathe * 0.04 - absf(cos(_gait)) * 0.08 * _walk, 0)
	body_t = body_t.lerp(Vector3(-0.12, 0, sin(_flap) * 0.04), _fly)
	body_pos.y += _fly * 0.6 + sin(_flap) * 0.25 * _fly

	# --- Neck: default S-curve, looking around ---------------------------------
	var neck_t: Array[Vector3] = []
	for i in neck.size():
		var base := 0.55 if i == 0 else (0.05 if i < 3 else -0.18)
		neck_t.append(Vector3(base + breathe * 0.02, sin(_time * 0.5 + i * 0.4) * 0.05, 0))
	var head_t := Vector3(-0.35, sin(_time * 0.37) * 0.12, 0)
	var jaw_t := Vector3(0.05 + maxf(0.0, sin(_time * 0.8)) * 0.04, 0, 0)
	var throat_glow := 0.25 + 0.15 * sin(_time * 2.0)

	# --- Wings -------------------------------------------------------------------
	var folded := [Vector3(0.0, 1.05, 0.55), Vector3(0.0, -2.5, 0.1)]
	var flap := sin(_flap)
	var spread := [Vector3(0.0, 0.15, 0.25 + flap * 0.85), Vector3(0.0, -0.2 - flap * 0.2, -0.15 + flap * 0.35)]
	var wing_mix := _fly

	# --- Actions -----------------------------------------------------------------
	if p >= 0.0:
		match _action:
			"bite":
				var lunge := keys(p, [[0, 0], [0.35, -0.4], [0.55, 0.55], [1, 0]])
				for i in neck_t.size():
					neck_t[i] += Vector3(-lunge * (0.35 if i == 0 else 0.15), 0, 0) * w
				head_t += Vector3(lunge * 0.4, 0, 0) * w
				jaw_t.x = lerpf(jaw_t.x, keys(p, [[0, 0.1], [0.4, 0.8], [0.55, 0.0], [1, 0.05]]), w)
				body_t.x += -0.08 * w
			"claw":
				body_t += Vector3(0.12, 0.25, 0.1) * w
			"tail":
				body_t.y += keys(p, [[0, 0], [0.3, -0.45], [0.6, 0.9], [1, 0]]) * w
			"breath":
				var on := p > 0.15 and p < 0.88
				if on != fire.emitting:
					fire.set_on(on)
				var sweep := keys(p, [[0, 0], [0.15, -0.55], [0.88, 0.55], [1, 0]])
				neck_t[0] += Vector3(-0.35, sweep * 0.5, 0) * w
				for i in range(1, neck_t.size()):
					neck_t[i] += Vector3(0.0, sweep * 0.12, 0) * w
				head_t += Vector3(0.25, 0, 0) * w
				jaw_t.x = lerpf(jaw_t.x, 0.75, w)
				throat_glow = lerpf(throat_glow, 2.2 + sin(_time * 25.0) * 0.3, w)
				body_t.x += -0.06 * w
			"roar":
				for i in neck_t.size():
					neck_t[i] += Vector3(0.18 if i < 2 else 0.0, 0, 0) * w
				head_t += Vector3(-0.35, 0, 0) * w
				jaw_t.x = lerpf(jaw_t.x, 0.85 + sin(_time * 40.0) * 0.03, w)
				wing_mix = maxf(wing_mix, 0.55 * w)
				throat_glow = lerpf(throat_glow, 1.2, w)
			"gust":
				wing_mix = maxf(wing_mix, w)
				body_t.x += 0.12 * w
			"takeoff":
				wing_mix = maxf(wing_mix, w)
				var crouch := keys(p, [[0, 0], [0.25, 1.0], [0.4, 0.0], [1, 0]])
				body_pos.y -= crouch * 0.7
			"land":
				var crouch := keys(p, [[0, 0.0], [0.4, 1.0], [1, 0]])
				body_pos.y -= crouch * 0.6
				wing_mix = maxf(wing_mix, 1.0 - p)
			"dive":
				body_t.x = lerpf(body_t.x, -0.7, w)
				spread = [Vector3(0.0, 0.9, 0.35), Vector3(0.0, -1.2, 0.0)]
				wing_mix = 1.0
				jaw_t.x = lerpf(jaw_t.x, 0.6, w)
			"hit":
				body_t += Vector3(0.1, 0, 0.08) * sin(PI * p)
				head_t += Vector3(-0.3, 0.3, 0) * sin(PI * p)
	elif fire.emitting:
		fire.set_on(false)

	body.position = damp_v(body.position, body_pos, 8.0, delta)
	pose(body, body_t, 6.0, delta)
	for i in neck.size():
		pose(neck[i], neck_t[i], 7.0, delta)
	pose(head, head_t, 8.0, delta)
	pose(jaw, jaw_t, 18.0, delta)
	throat.set_instance_shader_parameter(&"intensity", throat_glow)

	var wl: Vector3 = (folded[0] as Vector3).lerp(spread[0], wing_mix)
	var el: Vector3 = (folded[1] as Vector3).lerp(spread[1], wing_mix)
	pose(wing_r, Vector3(wl.x, -wl.y, wl.z), 9.0, delta)
	pose(wing_l, Vector3(wl.x, wl.y, -wl.z), 9.0, delta)
	pose(elbow_r, Vector3(el.x, -el.y, el.z), 9.0, delta)
	pose(elbow_l, Vector3(el.x, el.y, -el.z), 9.0, delta)

	# Tail: each joint follows the body's turning with a lag, plus a lazy sway.
	var sway_amp := 0.12 + 0.1 * _walk
	var whip := 0.0
	if _action == "tail":
		whip = keys(p, [[0, 0], [0.3, 0.5], [0.6, -1.0], [1, 0]]) * w
	for i in tail.size():
		var lag := float(i) * 0.55
		var y := sin(_time * 1.1 - lag) * sway_amp - turn_rate * 0.08 + whip * (0.15 + i * 0.05)
		pose(tail[i], Vector3((-0.08 if i < 2 else 0.04) + _fly * 0.04, y, 0), 6.0, delta)

	# Legs: diagonal gait on the ground, tucked in flight.
	for leg: Array in legs:
		var hip: Node3D = leg[0]
		var knee: Node3D = leg[1]
		var ankle: Node3D = leg[2]
		var side: float = leg[3]
		var front: bool = leg[4]
		var phase := _gait + (0.0 if (front == (side < 0.0)) else PI)
		var swing := sin(phase) * 0.55 * _walk
		var lift := maxf(0.0, cos(phase)) * 0.7 * _walk
		var hip_t := Vector3(swing, 0, 0)
		var knee_t := Vector3((-0.35 if front else 0.45) - lift * (1.0 if front else -1.0) * 0.6, 0, 0)
		var ankle_t := Vector3((0.3 if front else -0.4), 0, 0)
		if _fly > 0.01:
			hip_t = hip_t.lerp(Vector3(-0.9 if front else 0.9, 0, 0), _fly)
			knee_t = knee_t.lerp(Vector3(1.2 if front else -1.0, 0, 0), _fly)
		if _action == "claw" and front and side > 0.0:
			var raise := keys(p, [[0, 0], [0.35, 1.0], [0.55, -0.2], [1, 0]]) * w
			hip_t += Vector3(1.6, 0.4, 0) * raise
			knee_t += Vector3(-1.0, 0, 0) * raise
		pose(hip, hip_t, 10.0, delta)
		pose(knee, knee_t, 10.0, delta)
		pose(ankle, ankle_t, 10.0, delta)
