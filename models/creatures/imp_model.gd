class_name ImpModel
extends CreatureModel
## Small winged devil of the underworld. Hovers on fast bat wings, throws fire.

var body: Node3D
var head: Node3D
var wing_l: Node3D
var wing_r: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var tail: Array[Node3D] = []
var hand_fire: Node3D


func _ember_extents() -> Vector3:
	return Vector3(0.3, 0.4, 0.3)


func _build() -> void:
	var red := ModelKit.mat(Color(0.68, 0.18, 0.1), AsciiMaterialId.SOLID, 0.6, 0.3, 0.45)
	var dark := ModelKit.mat(Color(0.3, 0.1, 0.08), AsciiMaterialId.SOLID, 0.5, 0.2)
	var membrane := ModelKit.mat(Color(0.3, 0.07, 0.05), AsciiMaterialId.CLOTH, 0.9, 0.35)
	body = ModelKit.joint(self, "Body", Vector3(0, 1.0, 0))
	ModelKit.part(body, ModelKit.box(Vector3(0.38, 0.42, 0.3)), red, Vector3(0, 0.05, 0))
	ModelKit.part(body, ModelKit.box(Vector3(0.3, 0.18, 0.26)), red, Vector3(0, -0.22, 0.02))
	head = ModelKit.joint(body, "Head", Vector3(0, 0.3, -0.04))
	ModelKit.part(head, ModelKit.box(Vector3(0.3, 0.26, 0.28)), red, Vector3(0, 0.12, 0))
	ModelKit.part(head, ModelKit.box(Vector3(0.16, 0.08, 0.1)), dark, Vector3(0, 0.03, -0.16))
	for side: float in [-1.0, 1.0]:
		ModelKit.part(head, ModelKit.cone(0.05, 0.24, 5), dark, Vector3(side * 0.11, 0.3, 0.02), Vector3(-25, 0, -side * 30))
		ModelKit.part(head, ModelKit.box(Vector3(0.06, 0.035, 0.03)), ModelKit.glow(Color(1.0, 0.85, 0.2), 7.0), Vector3(side * 0.07, 0.15, -0.14))
	for side: float in [-1.0, 1.0]:
		var arm := ModelKit.joint(body, "Arm", Vector3(side * 0.22, 0.18, 0))
		ModelKit.part(arm, ModelKit.capsule(0.045, 0.34), red, Vector3(0, -0.15, 0))
		ModelKit.part(arm, ModelKit.cone(0.04, 0.1, 4), dark, Vector3(0, -0.34, -0.02), Vector3(180, 0, 0))
		var leg := ModelKit.joint(body, "Leg", Vector3(side * 0.11, -0.3, 0))
		ModelKit.part(leg, ModelKit.capsule(0.055, 0.36), red, Vector3(0, -0.15, 0.04))
		ModelKit.part(leg, ModelKit.box(Vector3(0.08, 0.05, 0.14)), dark, Vector3(0, -0.33, -0.02))
		var wing := ModelKit.joint(body, "Wing", Vector3(side * 0.12, 0.2, 0.15))
		var pts := PackedVector2Array([Vector2(0, 0), Vector2(0.75, 0.25), Vector2(0.95, -0.05), Vector2(0.7, -0.15), Vector2(0.55, -0.4), Vector2(0.3, -0.25), Vector2(0.12, -0.35)])
		if side < 0.0:
			for i in pts.size():
				pts[i].x = -pts[i].x
		ModelKit.part(wing, ModelKit.slab(pts, 0.02), membrane, Vector3.ZERO, Vector3(0, side * -25, 0))
		ModelKit.part(wing, ModelKit.cylinder(0.015, 0.02, 0.8, 4), dark, Vector3(side * 0.38, 0.12, 0), Vector3(0, 0, side * -72))
		if side < 0.0:
			arm_l = arm
			leg_l = leg
			wing_l = wing
		else:
			arm_r = arm
			leg_r = leg
			wing_r = wing
	var parent := ModelKit.joint(body, "Tail", Vector3(0, -0.25, 0.14))
	for i in 4:
		var j := ModelKit.joint(parent, "T%d" % i, Vector3(0, 0, 0.0 if i == 0 else 0.16))
		ModelKit.part(j, ModelKit.capsule(0.035 - i * 0.005, 0.18), dark, Vector3(0, 0, 0.08), Vector3(90, 0, 0))
		tail.append(j)
		parent = j
	ModelKit.part(parent, ModelKit.cone(0.07, 0.12, 3), dark, Vector3(0, 0, 0.24), Vector3(90, 0, 0))
	hand_fire = ModelKit.part(arm_r, ModelKit.sphere(0.09, 6), ModelKit.glow(Color(1.0, 0.45, 0.1), 7.0, 0.5), Vector3(0, -0.38, -0.04))
	hand_fire.visible = false


func _animate(delta: float) -> void:
	var flap := sin(_time * 18.0)
	var bob := sin(_time * 3.0) * 0.08
	var p := action_progress()
	var w := action_weight()
	var lean := clampf(move_speed * 0.08, 0.0, 0.5)
	if _dead:
		var f := clampf(_dead_t / 0.8, 0.0, 1.0)
		body.position = body.position.lerp(Vector3(0, 0.25, 0), 1.0 - exp(-8.0 * delta))
		pose(body, Vector3(1.3 * f, 0, 0.5 * f), 8.0, delta)
		pose(wing_l, Vector3(0, -0.2, -0.9), 6.0, delta)
		pose(wing_r, Vector3(0, 0.2, 0.9), 6.0, delta)
		return
	body.position = damp_v(body.position, Vector3(0, 1.0 + bob, 0), 10.0, delta)
	pose(body, Vector3(-lean, 0, 0), 8.0, delta)
	pose(wing_l, Vector3(0, -0.3 - flap * 0.15, -flap * 0.75), 40.0, delta)
	pose(wing_r, Vector3(0, 0.3 + flap * 0.15, flap * 0.75), 40.0, delta)
	pose(leg_l, Vector3(0.3 + sin(_time * 3.0) * 0.1, 0, 0), 10.0, delta)
	pose(leg_r, Vector3(0.2 - sin(_time * 3.0) * 0.1, 0, 0), 10.0, delta)
	for i in tail.size():
		pose(tail[i], Vector3(-0.25 + sin(_time * 4.0 - i) * 0.2, sin(_time * 2.5 - i * 0.8) * 0.35, 0), 10.0, delta)
	var arm_r_t := Vector3(0.2, 0, 0.2)
	var arm_l_t := Vector3(0.2, 0, -0.2)
	var head_t := Vector3(sin(_time * 1.3) * 0.1, sin(_time * 0.7) * 0.3, 0)
	hand_fire.visible = false
	if p >= 0.0:
		match _action:
			"throw", "attack", "cast":
				arm_r_t = arm_r_t.lerp(Vector3(keys(p, [[0, 0.2], [0.45, 2.6], [0.6, 1.0], [1, 0.2]]), 0, 0.2), w)
				hand_fire.visible = p < 0.55
			"hit":
				head_t += Vector3(0.5, 0, 0) * sin(PI * p)
				pose(body, Vector3(0.4 * sin(PI * p), 0, 0), 20.0, delta)
	pose(arm_r, arm_r_t, 18.0, delta)
	pose(arm_l, arm_l_t, 18.0, delta)
	pose(head, head_t, 10.0, delta)
