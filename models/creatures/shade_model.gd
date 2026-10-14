class_name ShadeModel
extends CreatureModel
## A drifting hooded ghost of the underworld: tattered robe, reaching
## sleeves, two cold eyes and a trail of pale wisps.

var body: Node3D
var hood: Node3D
var arm_l: Node3D
var arm_r: Node3D
var rags: Array[Node3D] = []
var _wisps: GPUParticles3D


func _ember_extents() -> Vector3:
	return Vector3(0.35, 0.8, 0.35)


func _build() -> void:
	var robe := ModelKit.mat(Color(0.2, 0.22, 0.27), AsciiMaterialId.CLOTH, 0.95, 0.3, 0.7)
	var robe2 := ModelKit.mat(Color(0.3, 0.33, 0.38), AsciiMaterialId.CLOTH, 0.95, 0.3, 0.7)
	body = ModelKit.joint(self, "Body", Vector3(0, 0.5, 0))
	ModelKit.part(body, ModelKit.cylinder(0.26, 0.5, 1.4, 9), robe, Vector3(0, 0.7, 0))
	ModelKit.part(body, ModelKit.box(Vector3(0.6, 0.3, 0.4)), robe2, Vector3(0, 1.35, 0))
	hood = ModelKit.joint(body, "Hood", Vector3(0, 1.5, 0))
	ModelKit.part(hood, ModelKit.box(Vector3(0.42, 0.46, 0.42)), robe, Vector3(0, 0.2, 0.02))
	ModelKit.part(hood, ModelKit.box(Vector3(0.28, 0.2, 0.3)), robe, Vector3(0, 0.45, 0.1), Vector3(-30, 0, 0))
	ModelKit.part(hood, ModelKit.box(Vector3(0.3, 0.3, 0.05)), ModelKit.mat(Color(0.01, 0.01, 0.02)), Vector3(0, 0.16, -0.2))
	for side: float in [-1.0, 1.0]:
		ModelKit.part(hood, ModelKit.box(Vector3(0.07, 0.035, 0.03)), ModelKit.glow(Color(0.45, 0.85, 1.0), 7.0, 0.3), Vector3(side * 0.07, 0.2, -0.23))
		var arm := ModelKit.joint(body, "Arm", Vector3(side * 0.32, 1.35, 0))
		ModelKit.part(arm, ModelKit.cylinder(0.07, 0.12, 0.7, 6), robe2, Vector3(0, -0.32, 0))
		ModelKit.part(arm, ModelKit.box(Vector3(0.05, 0.22, 0.05)), ModelKit.mat(Color(0.6, 0.62, 0.65)), Vector3(0, -0.72, 0))
		if side < 0.0:
			arm_l = arm
		else:
			arm_r = arm
	for i in 6:
		var a := TAU * i / 6.0
		var j := ModelKit.joint(body, "Rag%d" % i, Vector3(cos(a) * 0.42, 0.05, sin(a) * 0.42))
		ModelKit.part(j, ModelKit.box(Vector3(0.18, 0.55, 0.03)), robe, Vector3(0, -0.25, 0), Vector3(0, -rad_to_deg(a) + 90, 0))
		rags.append(j)
	_wisps = GPUParticles3D.new()
	_wisps.amount = 26
	_wisps.lifetime = 1.6
	_wisps.local_coords = false
	_wisps.visibility_aabb = AABB(Vector3(-3, -2, -3), Vector3(6, 6, 6))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.35, 0.1, 0.35)
	pm.direction = Vector3.UP
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0, 0.4, 0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	_wisps.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.18, 0.18)
	q.material = MaterialLibrary.fx(Color(0.7, 0.9, 1.0), Color(0.2, 0.4, 0.7), 3.0)
	_wisps.draw_pass_1 = q
	_wisps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wisps.position = Vector3(0, 0.4, 0)
	body.add_child(_wisps)


func _animate(delta: float) -> void:
	var p := action_progress()
	var w := action_weight()
	if _dead:
		_wisps.emitting = false
		pose(body, Vector3(0.0, _time * 2.0, 0), 4.0, delta)
		body.position = damp_v(body.position, Vector3(0, -0.6, 0), 2.0, delta)
		return
	var bob := sin(_time * 2.1) * 0.12
	body.position = damp_v(body.position, Vector3(0, 0.5 + bob, 0), 8.0, delta)
	pose(body, Vector3(-clampf(move_speed * 0.07, 0.0, 0.4), 0, sin(_time * 1.3) * 0.05), 6.0, delta)
	var reach := Vector3(0.35, 0, 0)
	if p >= 0.0 and (_action == "attack" or _action == "drain" or _action == "lunge"):
		reach = reach.lerp(Vector3(1.6, 0, 0), w)
	pose(arm_l, reach + Vector3(sin(_time * 2.0) * 0.1, 0, -0.15), 10.0, delta)
	pose(arm_r, reach + Vector3(-sin(_time * 2.0) * 0.1, 0, 0.15), 10.0, delta)
	pose(hood, Vector3(0.1 * sin(_time * 0.9), sin(_time * 0.5) * 0.25, 0), 6.0, delta)
	for i in rags.size():
		pose(rags[i], Vector3(sin(_time * 3.0 + i * 1.3) * 0.25 + move_speed * 0.08, 0, cos(_time * 2.4 + i) * 0.15), 8.0, delta)
	if p >= 0.0 and _action == "hit":
		pose(body, Vector3(0.5 * sin(PI * p), 0, 0), 20.0, delta)
