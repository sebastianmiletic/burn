class_name FlyerModel
extends CreatureModel
## A single winged creature: the cave bat (leathery membrane wings stretched
## over finger bones, big ears, fangs) or a bird (feathered wings that fold).
## Flaps continuously; dives and bites with `attack`. Faces -Z.

var species := "bat"
var size := 1.0

var body: Node3D
var head: Node3D
var jaw: Node3D
var wings: Array = []  # [shoulder, wrist, side]
var _flap := 0.0


func _init(kind_name := "bat", variant_seed := 0) -> void:
	species = kind_name
	var rng := RandomNumberGenerator.new()
	rng.seed = variant_seed
	size = rng.randf_range(0.85, 1.15) * (1.0 if species == "bat" else 0.5)
	dissolve_delay = 0.8


func _ember_extents() -> Vector3:
	return Vector3(0.4, 0.2, 0.3) * size


func _lod_size() -> float:
	return 1.2


func _build() -> void:
	var s := size
	var bat := species == "bat"
	var skin: ShaderMaterial
	var wing_mat: ShaderMaterial
	if bat:
		skin = CreatureSkin.fur(Color(0.2, 0.15, 0.13), Color(0.32, 0.24, 0.2), {"pattern_scale": 40.0})
		wing_mat = CreatureSkin.membrane(Color(0.22, 0.12, 0.11), {"backlight": 1.4, "pattern_scale": 4.0})
	else:
		skin = CreatureSkin.feathers(Color(0.15, 0.14, 0.14), Color(0.3, 0.28, 0.26), {"pattern_scale": 30.0})
		wing_mat = CreatureSkin.feathers(Color(0.12, 0.11, 0.11), Color(0.2, 0.19, 0.18), {"pattern_scale": 24.0})
	var bone := CreatureSkin.keratin(Color(0.25, 0.18, 0.15))
	body = ModelKit.joint(self, "Body", Vector3(0, 0.0, 0))
	ModelKit.part(body, OrganicMesh.profile("fly_body_%s" % species, Vector3(0, 0, 0.22) * s, Vector3(0, 0.02, -0.16) * s,
		[[0.0, 0.03 * s, 0.03 * s], [0.3, 0.1 * s, 0.09 * s], [0.75, 0.09 * s, 0.085 * s], [1.0, 0.05 * s, 0.05 * s]], 10, 8), skin)
	head = ModelKit.joint(body, "Head", Vector3(0, 0.03, -0.17) * s)
	ModelKit.part(head, OrganicMesh.blob("fly_head_%s" % species, Vector3(0.07, 0.065, 0.08) * s, 0.05, 3, 10), skin)
	var eye := CreatureSkin.eye(Color(1.0, 0.3, 0.15) if bat else Color(1.0, 0.8, 0.3), 3.0 if bat else 1.0)
	for side: float in [-1.0, 1.0]:
		ModelKit.part(head, ModelKit.sphere(0.014 * s, 6), eye, Vector3(side * 0.035, 0.02, -0.06) * s)
	if bat:
		for side: float in [-1.0, 1.0]:
			var pts := PackedVector2Array([Vector2(-0.025, 0), Vector2(0.03, 0), Vector2(0.01, 0.11), Vector2(-0.015, 0.08)])
			for p in pts.size():
				pts[p] *= s
			ModelKit.part(head, OrganicMesh.membrane("fly_ear", pts, 0.01 * s, 0.006 * s), wing_mat, Vector3(side * 0.04, 0.05, 0.0) * s, Vector3(-10, side * 20, side * -20))
		ModelKit.part(head, OrganicMesh.blob("fly_snout", Vector3(0.035, 0.03, 0.04) * s, 0.1, 7, 8), skin, Vector3(0, -0.01, -0.07) * s)
		jaw = ModelKit.joint(head, "Jaw", Vector3(0, -0.03, -0.04) * s)
		for side: float in [-1.0, 1.0]:
			ModelKit.part(head, ModelKit.cone(0.006 * s, 0.03 * s, 4), CreatureSkin.keratin(), Vector3(side * 0.014, -0.035, -0.09) * s, Vector3(180, 0, 0))
	else:
		ModelKit.part(head, ModelKit.cone(0.015 * s, 0.07 * s, 6), CreatureSkin.keratin(Color(0.25, 0.22, 0.15)), Vector3(0, -0.005, -0.1) * s, Vector3(-90, 0, 0))
		ModelKit.part(body, OrganicMesh.membrane("fly_tail_bird", PackedVector2Array([Vector2(-0.05, 0), Vector2(0.05, 0), Vector2(0.07, 0.14), Vector2(-0.07, 0.14)]) , 0.0, 0.01), wing_mat, Vector3(0, 0.0, 0.2) * s, Vector3(90, 0, 0), Vector3.ONE * s)
	for side: float in [-1.0, 1.0]:
		var shoulder := ModelKit.joint(body, "Wing", Vector3(side * 0.06, 0.04, -0.06) * s)
		var wrist := ModelKit.joint(shoulder, "Wrist", Vector3(side * 0.22, 0, 0) * s)
		var inner: PackedVector2Array
		var outer: PackedVector2Array
		if bat:
			ModelKit.part(shoulder, OrganicMesh.bezier("fly_arm_%d" % int(side), Vector3.ZERO, Vector3(side * 0.11, 0.02, -0.02) * s, Vector3(side * 0.22, 0, 0) * s, 0.012 * s, 0.009 * s, 5, 5), bone)
			inner = PackedVector2Array([Vector2(0, 0.02), Vector2(0.22, 0.02), Vector2(0.22, -0.18), Vector2(0.1, -0.24), Vector2(0, -0.26)])
			outer = PackedVector2Array([Vector2(0, 0.02), Vector2(0.3, 0.04), Vector2(0.26, -0.1), Vector2(0.18, -0.2), Vector2(0.1, -0.15), Vector2(0.0, -0.2)])
			for f in 3:
				var tip := Vector3(side * (0.3 - f * 0.05), 0, 0.04 + f * 0.09) * s
				ModelKit.part(wrist, OrganicMesh.bezier("fly_finger_%d_%d" % [int(side), f], Vector3.ZERO, tip * 0.5 + Vector3(0, 0.01, 0) * s, tip, 0.007 * s, 0.003 * s, 4, 4), bone)
		else:
			inner = PackedVector2Array([Vector2(0, 0.04), Vector2(0.22, 0.03), Vector2(0.22, -0.1), Vector2(0, -0.12)])
			outer = PackedVector2Array([Vector2(0, 0.03), Vector2(0.18, 0.0), Vector2(0.3, -0.08), Vector2(0.2, -0.13), Vector2(0, -0.1)])
		if side < 0.0:
			for i in inner.size():
				inner[i].x = -inner[i].x
			for i in outer.size():
				outer[i].x = -outer[i].x
		for i in inner.size():
			inner[i] *= s
		for i in outer.size():
			outer[i] *= s
		ModelKit.part(shoulder, OrganicMesh.membrane("fly_in_%s_%d" % [species, int(side)], inner, 0.02 * s, 0.006 * s), wing_mat, Vector3.ZERO, Vector3(-90, 0, 0))
		ModelKit.part(wrist, OrganicMesh.membrane("fly_out_%s_%d" % [species, int(side)], outer, 0.02 * s, 0.006 * s), wing_mat, Vector3.ZERO, Vector3(-90, 0, 0))
		wings.append([shoulder, wrist, side])


func _animate(delta: float) -> void:
	var p := action_progress()
	var w := action_weight()
	var rate := 9.0 if species == "bat" else 6.0
	_flap += delta * TAU * rate
	var f := sin(_flap)
	var body_t := Vector3(-0.1 - clampf(move_speed * 0.04, 0.0, 0.4), sin(_time * 3.0) * 0.1, sin(_time * 2.3) * 0.15)
	var bob := Vector3(0, f * 0.04 * size, 0)
	if _dead:
		pose(body, Vector3(1.2, 0, 0.8), 6.0, delta)
		body.position = damp_v(body.position, Vector3(0, -0.05, 0), 6.0, delta)
		for wg: Array in wings:
			pose(wg[0], Vector3(0, 0, -float(wg[2]) * 0.6), 5.0, delta)
		return
	if p >= 0.0 and _action in ["attack", "bite", "lunge", "drain"]:
		body_t.x += keys(p, [[0, 0], [0.4, -0.5], [0.6, 0.6], [1, 0]]) * w
		if jaw != null:
			pose(jaw, Vector3(keys(p, [[0, 0], [0.4, 0.7], [0.6, 0], [1, 0]]), 0, 0), 20.0, delta)
	body.position = damp_v(body.position, bob, 20.0, delta)
	pose(body, body_t, 10.0, delta)
	pose(head, Vector3(sin(_time * 4.0) * 0.15, sin(_time * 2.7) * 0.3, 0), 10.0, delta)
	for wg: Array in wings:
		var side: float = wg[2]
		var sh: Node3D = wg[0]
		var wr: Node3D = wg[1]
		sh.rotation = Vector3(0, side * 0.1, side * f * 0.9)
		wr.rotation = Vector3(0, 0, side * (f * 0.5 - 0.15))
