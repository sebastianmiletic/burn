class_name CerberusModel
extends CreatureModel
## The three-headed hound of Tartarus: a heavy quadruped with a burning mane,
## three independently animated heads (the outer two breathe fire) and a
## whip of a tail. About 7 m long. Faces -Z.

var body: Node3D
var necks: Array[Node3D] = []
var heads: Array[Node3D] = []
var jaws: Array[Node3D] = []
var mouths: Array[Node3D] = []
var fires: Array[FireStream] = []
var legs: Array = []
var tail: Array[Node3D] = []

var _gait := 0.0
var _walk := 0.0
var _body_y := 2.3


func _init() -> void:
	dissolve_delay = 1.8
	dissolve_time = 2.2
	durations["breath"] = 2.6


func _ember_extents() -> Vector3:
	return Vector3(1.4, 1.2, 3.0)


func _build() -> void:
	var fur := ModelKit.mat(Color(0.26, 0.17, 0.15), AsciiMaterialId.SOLID, 0.85, 0.4, 0.45)
	var flesh := ModelKit.mat(Color(0.5, 0.16, 0.12), AsciiMaterialId.SOLID, 0.6, 0.3)
	var bone := ModelKit.mat(Color(0.82, 0.76, 0.62), AsciiMaterialId.SOLID, 0.5, 0.2)
	body = ModelKit.joint(self, "Body", Vector3(0, _body_y, 0))
	ModelKit.part(body, ModelKit.capsule(1.05, 2.8, 10), fur, Vector3(0, 0.1, -0.5), Vector3(90, 0, 0))
	ModelKit.part(body, ModelKit.capsule(0.82, 2.1, 10), fur, Vector3(0, -0.05, 1.4), Vector3(90, 0, 0))
	for i in 8:
		var z := -1.6 + i * 0.45
		ModelKit.part(body, ModelKit.cone(0.16, 0.6, 4), fur, Vector3(0, 1.05 - i * 0.04, z), Vector3(-30, 0, 0))
	for i in 5:
		ModelKit.part(body, ModelKit.box(Vector3(1.5 - i * 0.1, 0.08, 0.12)), bone, Vector3(0, 0.15, -0.9 + i * 0.35), Vector3(0, 0, 0))
	var mane := ModelKit.embers(body, 40, Vector3(1.0, 0.4, 0.6), 0.9, 0.35, 2.0)
	mane.position = Vector3(0, 1.0, -1.2)
	mane.emitting = true

	for k in 3:
		var x := (k - 1) * 0.85
		var nb := ModelKit.joint(body, "Neck%d" % k, Vector3(x, 0.45, -1.75))
		ModelKit.part(nb, ModelKit.capsule(0.48, 1.3, 8), fur, Vector3(0, 0, -0.45), Vector3(90, 0, 0))
		var hd := ModelKit.joint(nb, "Head%d" % k, Vector3(0, 0, -1.0))
		hd.scale = Vector3.ONE * 1.25
		ModelKit.part(hd, ModelKit.box(Vector3(0.72, 0.62, 0.78)), fur, Vector3(0, 0.1, -0.25))
		ModelKit.part(hd, ModelKit.box(Vector3(0.46, 0.34, 0.72)), fur, Vector3(0, 0.0, -0.9))
		ModelKit.part(hd, ModelKit.box(Vector3(0.2, 0.12, 0.12)), ModelKit.mat(Color(0.05, 0.03, 0.03)), Vector3(0, 0.13, -1.27))
		for side: float in [-1.0, 1.0]:
			ModelKit.part(hd, ModelKit.cone(0.13, 0.45, 4), fur, Vector3(side * 0.24, 0.55, -0.05), Vector3(-15, 0, -side * 18))
			ModelKit.part(hd, ModelKit.box(Vector3(0.12, 0.07, 0.06)), ModelKit.glow(Color(1.0, 0.2, 0.05), 8.0, 0.2), Vector3(side * 0.2, 0.24, -0.63))
		var jaw := ModelKit.joint(hd, "Jaw", Vector3(0, -0.15, -0.5))
		ModelKit.part(jaw, ModelKit.box(Vector3(0.42, 0.14, 0.8)), flesh, Vector3(0, -0.08, -0.38))
		for side: float in [-1.0, 1.0]:
			ModelKit.part(jaw, ModelKit.cone(0.04, 0.16, 3), bone, Vector3(side * 0.16, 0.05, -0.65), Vector3.ZERO)
			ModelKit.part(hd, ModelKit.cone(0.045, 0.2, 3), bone, Vector3(side * 0.16, -0.17, -1.1), Vector3(180, 0, 0))
		var mouth := ModelKit.joint(hd, "Mouth", Vector3(0, -0.1, -1.3))
		necks.append(nb)
		heads.append(hd)
		jaws.append(jaw)
		mouths.append(mouth)
		if k != 1:
			var f := FireStream.new().setup(11.0, 12.0, 1.3)
			mouth.add_child(f)
			fires.append(f)

	for spec: Array in [[-1.0, true], [1.0, true], [-1.0, false], [1.0, false]]:
		var side: float = spec[0]
		var front: bool = spec[1]
		var hip := ModelKit.joint(body, "Hip", Vector3(side * 0.72, -0.3, -1.0 if front else 1.75))
		ModelKit.part(hip, ModelKit.capsule(0.44, 1.3, 8), fur, Vector3(0, -0.5, 0))
		var knee := ModelKit.joint(hip, "Knee", Vector3(0, -1.05, 0))
		ModelKit.part(knee, ModelKit.capsule(0.3, 1.15, 8), fur, Vector3(0, -0.45, 0))
		var ankle := ModelKit.joint(knee, "Ankle", Vector3(0, -0.95, 0))
		ModelKit.part(ankle, ModelKit.box(Vector3(0.45, 0.2, 0.55)), fur, Vector3(0, -0.08, -0.12))
		for c in 3:
			ModelKit.part(ankle, ModelKit.cone(0.05, 0.22, 3), bone, Vector3((c - 1) * 0.14, -0.12, -0.42), Vector3(-90, 0, 0))
		legs.append([hip, knee, ankle, side, front])

	var parent := ModelKit.joint(body, "Tail", Vector3(0, 0.3, 2.5))
	for i in 5:
		var j := ModelKit.joint(parent, "T%d" % i, Vector3(0, 0, 0.0 if i == 0 else 0.6))
		ModelKit.part(j, ModelKit.capsule(0.2 - i * 0.03, 0.75, 6), fur, Vector3(0, 0, 0.3), Vector3(90, 0, 0))
		tail.append(j)
		parent = j
	var tip := ModelKit.embers(parent, 16, Vector3(0.1, 0.1, 0.1), 0.6, 0.3, 1.5)
	tip.position = Vector3(0, 0, 0.7)
	tip.emitting = true


func _animate(delta: float) -> void:
	var p := action_progress()
	var w := action_weight(0.1, 0.18)
	_walk = damp(_walk, clampf(move_speed / 5.0, 0.0, 1.0), 6.0, delta)
	_gait += delta * TAU * move_speed / (4.2 + _walk * 1.5)
	var breathe := sin(_time * 1.6)
	if _dead:
		body.position = damp_v(body.position, Vector3(0, 0.85, 0), 3.0, delta)
		pose(body, Vector3(0, 0, 0.35), 3.0, delta)
		for k in 3:
			pose(necks[k], Vector3(-0.4, (k - 1) * 0.3, 0), 3.0, delta)
			pose(jaws[k], Vector3(0.4, 0, 0), 4.0, delta)
		for f in fires:
			if f.emitting:
				f.set_on(false)
		for leg: Array in legs:
			pose(leg[0], Vector3(0, 0, -1.0 * float(leg[3])), 3.0, delta)
		return

	var body_pos := Vector3(0, _body_y + breathe * 0.03 - absf(sin(_gait)) * 0.12 * _walk, 0)
	var body_t := Vector3(-0.04 * _walk + sin(_gait * 2.0) * 0.03 * _walk, 0, 0)
	var neck_t: Array[Vector3] = []
	var head_t: Array[Vector3] = []
	var jaw_t: Array[float] = []
	for k in 3:
		var spread := -(k - 1) * 0.42
		neck_t.append(Vector3(0.22 + sin(_time * 0.9 + k * 2.0) * 0.06, spread + sin(_time * 0.6 + k) * 0.1, (k - 1) * -0.15))
		head_t.append(Vector3(-0.25, -spread * 0.4 + sin(_time * 0.8 + k * 1.3) * 0.15, 0))
		jaw_t.append(0.05 + maxf(0.0, sin(_time * 2.6 + k * 2.0)) * 0.15)
	var tail_wag := 0.25 + 0.2 * _walk

	if p >= 0.0:
		match _action:
			"bite", "attack":
				for k in 3:
					var offset := [0.15, 0.0, 0.3][k] as float
					var lp := clampf((p - offset) / 0.55, 0.0, 1.0)
					var lunge := keys(lp, [[0, 0], [0.4, -0.3], [0.6, 0.6], [1, 0]])
					neck_t[k] += Vector3(-lunge * 0.5, 0, 0) * w
					head_t[k] += Vector3(lunge * 0.3, 0, 0) * w
					jaw_t[k] = lerpf(jaw_t[k], keys(lp, [[0, 0.1], [0.45, 0.9], [0.6, 0.0], [1, 0.05]]), w)
				body_t.x -= 0.1 * w
			"pounce":
				var crouch := keys(p, [[0, 0], [0.3, 1.0], [0.45, -0.6], [0.8, -0.2], [1, 0]])
				body_pos.y -= crouch * 0.6
				body_t.x += keys(p, [[0, 0], [0.3, 0.12], [0.45, -0.35], [0.8, 0.1], [1, 0]]) * w
			"breath":
				var on := p > 0.15 and p < 0.85
				for f in fires:
					if on != f.emitting:
						f.set_on(on)
				for k: int in [0, 2]:
					var sweep := keys(p, [[0.15, -0.35], [0.85, 0.35]]) * (1.0 if k == 0 else -1.0)
					neck_t[k] += Vector3(-0.25, sweep - (k - 1) * 0.2, 0) * w
					head_t[k] += Vector3(0.3, 0, 0) * w
					jaw_t[k] = lerpf(jaw_t[k], 0.7, w)
			"howl", "roar", "summon":
				for k in 3:
					neck_t[k] += Vector3(0.5, (k - 1) * 0.25, 0) * w
					head_t[k] += Vector3(-0.6, 0, 0) * w
					jaw_t[k] = lerpf(jaw_t[k], 0.75 + sin(_time * 35.0 + k) * 0.05, w)
				body_t.x += 0.12 * w
			"hit":
				body_t += Vector3(0.1, 0, 0.12) * sin(PI * p)
				for k in 3:
					head_t[k] += Vector3(-0.4, 0.2, 0) * sin(PI * p)
	else:
		for f in fires:
			if f.emitting:
				f.set_on(false)

	body.position = damp_v(body.position, body_pos, 10.0, delta)
	pose(body, body_t, 8.0, delta)
	for k in 3:
		pose(necks[k], neck_t[k], 9.0, delta)
		pose(heads[k], head_t[k], 9.0, delta)
		pose(jaws[k], Vector3(jaw_t[k], 0, 0), 18.0, delta)
	for i in tail.size():
		pose(tail[i], Vector3(0.25 + i * 0.04, sin(_time * 4.0 - i * 0.6) * tail_wag - turn_rate * 0.1, 0), 8.0, delta)
	for leg: Array in legs:
		var front: bool = leg[4]
		var side: float = leg[3]
		var phase := _gait + (0.0 if (front == (side < 0.0)) else PI)
		var swing := sin(phase) * 0.7 * _walk
		var lift := maxf(0.0, cos(phase)) * _walk
		var hip_t := Vector3(swing, 0, 0)
		var knee_t := Vector3((-0.3 - lift * 0.7) if front else (0.45 + lift * 0.6), 0, 0)
		var ankle_t := Vector3(0.3 if front else -0.45, 0, 0)
		if _action == "pounce":
			var stretch := keys(p, [[0.3, 0.0], [0.45, 1.0], [0.8, 0.6], [1, 0]]) * w
			hip_t += Vector3(1.0 if front else -0.9, 0, 0) * stretch
		pose(leg[0], hip_t, 12.0, delta)
		pose(leg[1], knee_t, 12.0, delta)
		pose(leg[2], ankle_t, 12.0, delta)
