class_name HumanoidModel
extends CreatureModel
## Articulated humanoid built from primitives: players, villagers, skeletons,
## ghouls, trolls, the Warden, the Mountain King and Hades all use it with
## different styles.
##
## style keys (all optional):
##   skin, cloth, cloth2, boots, hair: Color
##   height (m), bulk (width multiplier), arm_length, hunch (radians forward)
##   hood, cloak, robe, apron, hat, helmet, beard, tusks, horns, gaunt, tattered, skeleton: bool
##   eyes: Color (glowing eyes) ; crown: Color (glowing crown) ; crown_fire: bool
##   torch_shadows: bool (held torch casts shadows)

var style := {}

var _s := 1.0  # height scale
var _b := 1.0  # bulk
var pivot: Node3D
var hips: Node3D
var spine: Node3D
var chest: Node3D
var neck: Node3D
var head: Node3D
var sh_l: Node3D
var sh_r: Node3D
var el_l: Node3D
var el_r: Node3D
var hand_l: Node3D
var hand_r: Node3D
var th_l: Node3D
var th_r: Node3D
var kn_l: Node3D
var kn_r: Node3D
var ank_l: Node3D
var ank_r: Node3D
var cloak: Array[Node3D] = []
var grip_r: Node3D
var grip_l: Node3D

var _held_id := ""
var _held: Node3D
var _offhand: Node3D
var _trail_v: MeshInstance3D
var _trail_h: MeshInstance3D
var _phase := 0.0
var _walk := 0.0
var _run := 0.0
var _air := 0.0
var _hips_y := 0.98
var _cloak_swing := 0.0
var _prev_speed := 0.0


func _init(style_dict := {}) -> void:
	style = style_dict


func st(key: String, default: Variant) -> Variant:
	return style.get(key, default)


func _ember_extents() -> Vector3:
	return Vector3(0.3, 0.8, 0.25) * _s * Vector3(_b, 1.0, _b)


# --- Construction ----------------------------------------------------------------

func _build() -> void:
	_s = float(st("height", 1.8)) / 1.8
	_b = float(st("bulk", 1.0))
	var s := _s
	var b := _b
	var skeleton: bool = st("skeleton", false)
	var bone := ModelKit.mat(Color(0.82, 0.79, 0.7), AsciiMaterialId.SOLID, 0.7, 0.3)
	var skin_c: Color = st("skin", Color(0.78, 0.6, 0.48))
	var skin := bone if skeleton else ModelKit.mat(skin_c, AsciiMaterialId.SOLID, 0.75, 0.15)
	var cloth := ModelKit.cloth(st("cloth", Color(0.2, 0.17, 0.15)))
	var cloth2 := ModelKit.cloth(st("cloth2", Color(0.5, 0.22, 0.12)))
	var boots := ModelKit.mat(st("boots", Color(0.16, 0.11, 0.08)), AsciiMaterialId.SOLID, 0.8, 0.2)
	var arm_len := float(st("arm_length", 1.0))
	var gaunt: bool = st("gaunt", false)
	var limb := 0.75 if gaunt else 1.0

	pivot = ModelKit.joint(self, "Pivot", Vector3(0, _hips_y * s, 0))
	hips = ModelKit.joint(pivot, "Hips")
	spine = ModelKit.joint(hips, "Spine")
	chest = ModelKit.joint(spine, "Chest", Vector3(0, 0.3 * s, 0))
	neck = ModelKit.joint(chest, "Neck", Vector3(0, 0.36 * s, 0.01 * s))
	head = ModelKit.joint(neck, "Head", Vector3(0, 0.07 * s, 0))

	# Torso
	if skeleton:
		ModelKit.part(hips, ModelKit.box(Vector3(0.3 * b, 0.12, 0.16) * s), bone, Vector3(0, 0.02 * s, 0))
		ModelKit.part(spine, ModelKit.cylinder(0.035, 0.04, 0.34, 6), bone, Vector3(0, 0.17 * s, 0.03 * s), Vector3.ZERO, Vector3.ONE * s)
		for i in 4:
			var w := (0.4 - i * 0.04) * b
			ModelKit.part(chest, ModelKit.box(Vector3(w, 0.045, 0.22 - i * 0.02) * s), bone, Vector3(0, (0.04 + i * 0.075) * s, 0))
		ModelKit.part(chest, ModelKit.box(Vector3(0.5 * b, 0.07, 0.14) * s), bone, Vector3(0, 0.33 * s, 0))
		if st("cloth", null) != null:
			# Rags hanging from the shoulders.
			ModelKit.part(chest, ModelKit.box(Vector3(0.44 * b, 0.42, 0.2) * s), cloth, Vector3(0, 0.12 * s, 0.03 * s), Vector3(4, 0, 0))
	else:
		ModelKit.part(hips, ModelKit.box(Vector3(0.36 * b, 0.2, 0.22 * b) * s), cloth, Vector3(0, 0.04 * s, 0))
		ModelKit.part(spine, ModelKit.box(Vector3(0.34 * b * limb, 0.26, 0.2 * b) * s), cloth, Vector3(0, 0.16 * s, 0))
		ModelKit.part(chest, ModelKit.box(Vector3(0.46 * b * (0.85 if gaunt else 1.0), 0.36, 0.26 * b) * s), cloth, Vector3(0, 0.17 * s, 0))
		ModelKit.part(spine, ModelKit.box(Vector3(0.38 * b, 0.06, 0.24 * b) * s), cloth2, Vector3(0, 0.03 * s, 0))
		ModelKit.part(chest, ModelKit.box(Vector3(0.2 * b, 0.1, 0.26 * b) * s), cloth2, Vector3(0, 0.33 * s, 0))
	if st("apron", false):
		var leather := ModelKit.mat(Color(0.35, 0.22, 0.12), AsciiMaterialId.CLOTH, 0.9, 0.25)
		ModelKit.part(chest, ModelKit.box(Vector3(0.36 * b, 0.62, 0.03) * s), leather, Vector3(0, -0.08 * s, -0.15 * s * b))
	if st("robe", false):
		ModelKit.part(hips, ModelKit.cylinder(0.24 * b, 0.42 * b, 0.9, 10), cloth, Vector3(0, -0.42 * s, 0), Vector3.ZERO, Vector3.ONE * s)
		ModelKit.part(chest, ModelKit.box(Vector3(0.5 * b, 0.42, 0.3 * b) * s), cloth, Vector3(0, 0.12 * s, 0))

	# Head
	var head_mat := bone if skeleton else skin
	ModelKit.part(head, ModelKit.box(Vector3(0.24, 0.27, 0.25) * s), head_mat, Vector3(0, 0.15 * s, 0))
	if skeleton:
		ModelKit.part(head, ModelKit.box(Vector3(0.18, 0.08, 0.18) * s), bone, Vector3(0, 0.0, -0.02 * s))
	else:
		ModelKit.part(head, ModelKit.box(Vector3(0.05, 0.07, 0.06) * s), head_mat, Vector3(0, 0.13 * s, -0.14 * s))
		if st("hair", null) != null and not st("hood", false) and not st("helmet", false):
			ModelKit.part(head, ModelKit.box(Vector3(0.26, 0.12, 0.27) * s), ModelKit.cloth(st("hair", Color.BLACK)), Vector3(0, 0.27 * s, 0.01 * s))
	var eyes: Variant = st("eyes", null)
	if eyes != null:
		for ex: float in [-0.055, 0.055]:
			ModelKit.part(head, ModelKit.box(Vector3(0.05, 0.035, 0.03) * s), ModelKit.glow(eyes, 6.0), Vector3(ex * s, 0.17 * s, -0.125 * s))
	elif not skeleton:
		var dark := ModelKit.mat(Color(0.08, 0.06, 0.05))
		for ex: float in [-0.055, 0.055]:
			ModelKit.part(head, ModelKit.box(Vector3(0.04, 0.03, 0.02) * s), dark, Vector3(ex * s, 0.18 * s, -0.126 * s))
	if st("beard", false):
		var beard := ModelKit.cloth(st("hair", Color(0.75, 0.72, 0.68)))
		ModelKit.part(head, ModelKit.box(Vector3(0.22, 0.22, 0.08) * s), beard, Vector3(0, 0.0, -0.12 * s))
		ModelKit.part(head, ModelKit.box(Vector3(0.12, 0.14, 0.06) * s), beard, Vector3(0, -0.14 * s, -0.12 * s))
	if st("tusks", false):
		var tusk := ModelKit.mat(Color(0.88, 0.84, 0.72))
		for ex: float in [-0.08, 0.08]:
			ModelKit.part(head, ModelKit.cone(0.025, 0.12, 5), tusk, Vector3(ex * s, 0.06 * s, -0.14 * s), Vector3(-30, 0, 0), Vector3.ONE * s)
	if st("horns", false):
		var horn := ModelKit.mat(Color(0.22, 0.18, 0.16), AsciiMaterialId.SOLID, 0.5)
		for side: float in [-1.0, 1.0]:
			ModelKit.part(head, ModelKit.cone(0.05, 0.26, 6), horn, Vector3(side * 0.12 * s, 0.3 * s, 0.02 * s), Vector3(-15, 0, -side * 35), Vector3.ONE * s)
	if st("hood", false):
		var hood := cloth
		ModelKit.part(head, ModelKit.box(Vector3(0.32, 0.34, 0.3) * s), hood, Vector3(0, 0.17 * s, 0.03 * s))
		ModelKit.part(head, ModelKit.box(Vector3(0.24, 0.12, 0.2) * s), hood, Vector3(0, 0.35 * s, 0.08 * s), Vector3(-25, 0, 0))
		ModelKit.part(head, ModelKit.box(Vector3(0.34, 0.06, 0.08) * s), hood, Vector3(0, 0.33 * s, -0.12 * s))
		ModelKit.part(chest, ModelKit.box(Vector3(0.52 * b, 0.14, 0.32 * b) * s), hood, Vector3(0, 0.38 * s, 0.01 * s))
	if st("helmet", false):
		var steel := ModelKit.metal(st("helmet_color", Color(0.42, 0.42, 0.44)))
		ModelKit.part(head, ModelKit.box(Vector3(0.3, 0.2, 0.3) * s), steel, Vector3(0, 0.24 * s, 0))
		ModelKit.part(head, ModelKit.box(Vector3(0.04, 0.14, 0.26) * s), steel, Vector3(0, 0.39 * s, 0))
		ModelKit.part(head, ModelKit.box(Vector3(0.3, 0.05, 0.05) * s), steel, Vector3(0, 0.15 * s, -0.15 * s))
	if st("hat", false):
		var felt := ModelKit.cloth(st("cloth2", Color(0.3, 0.2, 0.1)))
		ModelKit.part(head, ModelKit.cylinder(0.26, 0.26, 0.03, 12), felt, Vector3(0, 0.3 * s, 0), Vector3.ZERO, Vector3.ONE * s)
		ModelKit.part(head, ModelKit.cylinder(0.11, 0.15, 0.2, 10), felt, Vector3(0, 0.4 * s, 0), Vector3.ZERO, Vector3.ONE * s)
	var crown: Variant = st("crown", null)
	if crown != null:
		var cm := ModelKit.glow(crown, 4.0, 0.4)
		for i in 7:
			var a := TAU * i / 7.0
			ModelKit.part(head, ModelKit.cone(0.045, 0.16, 4), cm, Vector3(cos(a) * 0.15 * s, 0.36 * s, sin(a) * 0.15 * s), Vector3.ZERO, Vector3.ONE * s)
		ModelKit.part(head, ModelKit.cylinder(0.17, 0.17, 0.05, 12), cm, Vector3(0, 0.29 * s, 0), Vector3.ZERO, Vector3.ONE * s)
		if st("crown_fire", false):
			var flames := ModelKit.embers(head, 30, Vector3(0.15, 0.05, 0.15) * s, 0.7, 0.18 * s, 1.6)
			flames.position = Vector3(0, 0.42 * s, 0)
			flames.emitting = true

	# Arms
	var sleeve := bone if skeleton else cloth
	var forearm := bone if skeleton else skin
	var ar := (0.045 if skeleton else 0.07) * limb
	for side: float in [-1.0, 1.0]:
		var sh := ModelKit.joint(chest, "Shoulder", Vector3(side * 0.28 * b * s, 0.29 * s, 0))
		ModelKit.part(sh, ModelKit.capsule(ar * b * s * 1.1, 0.34 * s * arm_len), sleeve, Vector3(0, -0.15 * s * arm_len, 0))
		if not skeleton:
			ModelKit.part(sh, ModelKit.box(Vector3(0.17 * b, 0.1, 0.2 * b) * s), cloth2, Vector3(side * 0.02 * s, 0.03 * s, 0))
		var el := ModelKit.joint(sh, "Elbow", Vector3(0, -0.3 * s * arm_len, 0))
		ModelKit.part(el, ModelKit.capsule(ar * b * s, 0.3 * s * arm_len), forearm, Vector3(0, -0.13 * s * arm_len, 0))
		var hand := ModelKit.joint(el, "Hand", Vector3(0, -0.27 * s * arm_len, 0))
		ModelKit.part(hand, ModelKit.box(Vector3(0.08 * b, 0.1, 0.07) * s), forearm, Vector3(0, -0.04 * s, 0))
		var grip := ModelKit.joint(hand, "Grip", Vector3(0, -0.05 * s, 0))
		grip.rotation_degrees = Vector3(-90, 0, 0)
		if side < 0.0:
			sh_l = sh
			el_l = el
			hand_l = hand
			grip_l = grip
		else:
			sh_r = sh
			el_r = el
			hand_r = hand
			grip_r = grip

	# Legs
	var trousers := bone if skeleton else ModelKit.cloth(st("trousers", (st("cloth", Color(0.2, 0.17, 0.15)) as Color).darkened(0.25)))
	var shin_mat := bone if skeleton else boots
	var lr := (0.05 if skeleton else 0.085) * limb
	for side: float in [-1.0, 1.0]:
		var th := ModelKit.joint(hips, "Thigh", Vector3(side * 0.11 * b * s, -0.03 * s, 0))
		ModelKit.part(th, ModelKit.capsule(lr * b * s, 0.46 * s), trousers, Vector3(0, -0.22 * s, 0))
		var kn := ModelKit.joint(th, "Knee", Vector3(0, -0.45 * s, 0))
		ModelKit.part(kn, ModelKit.capsule(lr * 0.9 * b * s, 0.45 * s), shin_mat, Vector3(0, -0.21 * s, 0))
		var ank := ModelKit.joint(kn, "Ankle", Vector3(0, -0.45 * s, 0))
		ModelKit.part(ank, ModelKit.box(Vector3(0.11 * b, 0.07, 0.24) * s), shin_mat, Vector3(0, -0.015 * s, -0.05 * s))
		if side < 0.0:
			th_l = th
			kn_l = kn
			ank_l = ank
		else:
			th_r = th
			kn_r = kn
			ank_r = ank

	# Cloak: a short chain of plates hinged at the shoulders.
	if st("cloak", false):
		var cloak_mat := ModelKit.cloth(st("cloak_color", st("cloth", Color(0.2, 0.17, 0.15))))
		var parent := ModelKit.joint(chest, "Cloak", Vector3(0, 0.34 * s, 0.15 * s * b))
		var seg_len := 0.36 * s * (1.25 if st("robe", false) else 1.0)
		var segments := 4 if st("tattered", false) else 3
		for i in segments:
			var j := ModelKit.joint(parent, "CloakSeg%d" % i, Vector3(0, 0, 0))
			var w := (0.56 + i * 0.07) * b * s
			ModelKit.part(j, ModelKit.box(Vector3(w, seg_len, 0.035 * s)), cloak_mat, Vector3(0, -seg_len * 0.5, 0))
			cloak.append(j)
			parent = j
			var next := ModelKit.joint(j, "CloakJoint%d" % i, Vector3(0, -seg_len, 0))
			parent = next

	# Weapon trails (FX layer).
	_trail_v = ModelKit.part(chest, ModelKit.arc(0.45 * s, 1.45 * s, 170.0, 20), ModelKit.trail_material(Color(1.0, 0.7, 0.4)), Vector3(0.25 * s * b, 0.3 * s, 0), Vector3(0, 90, -80))
	_trail_v.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_v.visible = false
	_trail_h = ModelKit.part(chest, ModelKit.arc(0.5 * s, 1.5 * s, 200.0, 20), ModelKit.trail_material(Color(1.0, 0.7, 0.4)), Vector3(0, 0.2 * s, 0), Vector3(-90, 160, 0))
	_trail_h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_h.visible = false

	var start_item: String = st("held", "")
	if start_item != "":
		_build_held(start_item)


# --- Items ------------------------------------------------------------------------

func set_held(item_id: String) -> void:
	if item_id == _held_id:
		return
	if not _built:
		style["held"] = item_id
		return
	_build_held(item_id)
	refresh_parts()


func _build_held(item_id: String) -> void:
	_held_id = item_id
	if _held != null:
		_held.queue_free()
		_held = null
	if item_id == "":
		return
	_held = HeldItems.build(item_id, _s, bool(st("torch_shadows", false)))
	if _held != null:
		grip_r.add_child(_held)
		var t: Color = ItemDB.color(item_id) if ItemDB.exists(item_id) else Color(1.0, 0.7, 0.4)
		if item_id.begins_with("sword_ember") or item_id.begins_with("sword_dragonbone"):
			t = Color(1.0, 0.55, 0.2)
		(_trail_v.material_override as ShaderMaterial).set_shader_parameter(&"color", Vector3(t.r, t.g, t.b).lerp(Vector3(1.0, 0.75, 0.45), 0.5))
		(_trail_h.material_override as ShaderMaterial).set_shader_parameter(&"color", Vector3(t.r, t.g, t.b).lerp(Vector3(1.0, 0.75, 0.45), 0.5))


func held_item() -> String:
	return _held_id


func set_offhand_light(on: bool) -> void:
	if not _built:
		return
	if on and _offhand == null:
		_offhand = HeldItems.build("torch", _s, bool(st("torch_shadows", false)))
		grip_l.add_child(_offhand)
		refresh_parts()
	elif not on and _offhand != null:
		_offhand.queue_free()
		_offhand = null
		refresh_parts()


# --- Animation --------------------------------------------------------------------

func _animate(delta: float) -> void:
	var s := _s
	var v := move_speed / s
	_walk = damp(_walk, clampf(v / 2.2, 0.0, 1.0), 8.0, delta)
	_run = damp(_run, clampf((v - 3.0) / 2.5, 0.0, 1.0), 6.0, delta)
	_air = damp(_air, 0.0 if grounded else 1.0, 10.0, delta)
	var cycle := 1.75 * (1.0 + _run * 0.25)
	_phase += delta * TAU * v / cycle
	var amp := 0.5 * _walk + 0.32 * _run
	var sp := sin(_phase)
	var cp := cos(_phase)
	var breathe := sin(_time * 1.7) * (1.0 - _walk)
	var hunch := float(st("hunch", 0.0))

	var t := {
		"spine": Vector3(-0.05 * _walk - 0.24 * _run + hunch, sp * 0.07 * _walk, 0),
		"chest": Vector3(breathe * 0.025 + hunch * 0.3, -sp * 0.14 * _walk, 0),
		"neck": Vector3(-(hunch * 1.1) + 0.12 * _run, 0, 0),
		"head": Vector3(-0.05 * _run, sin(_time * 0.4) * 0.12 * (1.0 - _walk), 0),
		"th_l": Vector3(sp * amp, 0, 0.03),
		"th_r": Vector3(-sp * amp, 0, -0.03),
		"kn_l": Vector3(-maxf(0.0, cp) * amp * 1.7 - 0.06, 0, 0),
		"kn_r": Vector3(-maxf(0.0, -cp) * amp * 1.7 - 0.06, 0, 0),
		"ank_l": Vector3(-sp * amp * 0.3, 0, 0),
		"ank_r": Vector3(sp * amp * 0.3, 0, 0),
		"sh_l": Vector3(-sp * amp * 0.85 + breathe * 0.02, 0, -0.1 - 0.05 * _run),
		"sh_r": Vector3(sp * amp * 0.85 - breathe * 0.02, 0, 0.1 + 0.05 * _run),
		"el_l": Vector3(0.22 + 0.9 * _run + maxf(0.0, -sp) * 0.25 * _walk, 0, 0),
		"el_r": Vector3(0.22 + 0.9 * _run + maxf(0.0, sp) * 0.25 * _walk, 0, 0),
		"pivot": Vector3.ZERO,
	}
	var hips_y := -absf(cp) * 0.04 * s * (_walk + _run) - 0.03 * s * _run + breathe * 0.004 * s
	# Holding a tool or weapon: carry it a little raised.
	if _held_id != "" and _action == "":
		t["sh_r"].x += 0.25
		t["el_r"].x += 0.45
	if _air > 0.01:
		var a := _air
		t["th_l"] = t["th_l"].lerp(Vector3(0.75, 0, 0.05), a)
		t["th_r"] = t["th_r"].lerp(Vector3(-0.25, 0, -0.05), a)
		t["kn_l"] = t["kn_l"].lerp(Vector3(-1.1, 0, 0), a)
		t["kn_r"] = t["kn_r"].lerp(Vector3(-0.5, 0, 0), a)
		t["sh_l"] = t["sh_l"].lerp(Vector3(0.6, 0, -0.5), a)
		t["sh_r"] = t["sh_r"].lerp(Vector3(0.6, 0, 0.5), a)

	var pivot_pos := Vector3(0, _hips_y * s + hips_y, 0)
	var w := action_weight()
	var p := action_progress()
	_trail_v.visible = false
	_trail_h.visible = false
	if _dead:
		# Collapse onto the back and stay there.
		var f := clampf(_dead_t / 0.9, 0.0, 1.0)
		f = f * f * (3.0 - 2.0 * f)
		t["pivot"] = Vector3(1.5 * f, 0, 0.15 * f)
		pivot_pos.y = lerpf(_hips_y * s, 0.16 * s, f)
		t["kn_l"] = Vector3(-0.5 * f, 0, 0)
		t["kn_r"] = Vector3(-0.2 * f, 0, 0)
		t["sh_l"] = Vector3(0.3, 0, -1.2 * f)
		t["sh_r"] = Vector3(0.2, 0, 1.0 * f)
		t["head"] = Vector3(0.4 * f, 0.5 * f, 0)
	elif p >= 0.0:
		_action_pose(_action, p, w, t)
		if _action == "dodge":
			var f := p * p * (3.0 - 2.0 * p)
			pivot_pos.y -= sin(PI * p) * 0.48 * s
			pivot_pos.z -= 0.0
			t["pivot"] = Vector3(-TAU * f, 0, 0)
		elif _action == "jump":
			pivot_pos.y -= keys(p, [[0.0, 0.0], [0.25, 0.12 * s], [0.5, -0.02 * s], [1.0, 0.0]])

	var rate := 24.0
	pivot.position = damp_v(pivot.position, pivot_pos, rate, delta)
	if _action == "dodge" and not _dead:
		pivot.rotation = t["pivot"]  # a roll must not be smoothed through 360 degrees
	else:
		pose(pivot, t["pivot"], 14.0, delta)
	pose(spine, t["spine"], rate, delta)
	pose(chest, t["chest"], rate, delta)
	pose(neck, t["neck"], rate, delta)
	pose(head, t["head"], rate, delta)
	pose(th_l, t["th_l"], rate, delta)
	pose(th_r, t["th_r"], rate, delta)
	pose(kn_l, t["kn_l"], rate, delta)
	pose(kn_r, t["kn_r"], rate, delta)
	pose(ank_l, t["ank_l"], rate, delta)
	pose(ank_r, t["ank_r"], rate, delta)
	pose(sh_l, t["sh_l"], rate, delta)
	pose(sh_r, t["sh_r"], rate, delta)
	pose(el_l, t["el_l"], rate, delta)
	pose(el_r, t["el_r"], rate, delta)

	# Cloak trails behind motion, flutters while running, settles when still.
	if not cloak.is_empty():
		var accel := (move_speed - _prev_speed) / maxf(delta, 0.001)
		_prev_speed = move_speed
		_cloak_swing = damp(_cloak_swing, clampf(move_speed * 0.12 - accel * 0.01, -0.2, 0.9), 4.0, delta)
		for i in cloak.size():
			var flutter := sin(_time * (3.0 + _run * 4.0) - i * 0.9) * (0.03 + 0.08 * _run)
			var target := Vector3(0.06 + _cloak_swing * (0.35 + i * 0.25) + flutter - (0.06 if i > 0 else 0.0) + _air * 0.4, 0, 0)
			if _dead:
				target = Vector3(-0.4, 0, 0)
			pose(cloak[i], target, 10.0 - i * 2.0, delta)


func _action_pose(action: String, p: float, w: float, t: Dictionary) -> void:
	match action:
		"attack":
			_blend(t, "sh_r", Vector3(keys(p, [[0, 0.4], [0.3, 2.75], [0.52, -0.35], [1, 0.3]]), 0, keys(p, [[0, 0.1], [0.3, 0.45], [0.55, -0.25], [1, 0.1]])), w)
			_blend(t, "el_r", Vector3(keys(p, [[0, 0.5], [0.3, 1.25], [0.5, 0.15], [1, 0.4]]), 0, 0), w)
			_blend(t, "chest", Vector3(keys(p, [[0.3, 0.1], [0.55, -0.18]]), keys(p, [[0, 0.0], [0.3, 0.5], [0.55, -0.55], [1, 0]]), 0), w)
			_blend(t, "spine", Vector3(keys(p, [[0.3, 0.05], [0.55, -0.22], [1, 0]]), 0, 0), w)
			_blend(t, "th_l", Vector3(keys(p, [[0.3, 0.0], [0.5, 0.45], [1, 0.1]]), 0, 0), w)
			_blend(t, "sh_l", Vector3(0.5, 0, -0.5), w)
			_show_trail(_trail_v, p, 0.3, 0.55)
		"attack2", "sweep":
			_blend(t, "sh_r", Vector3(1.45, keys(p, [[0, 0.0], [0.3, -1.3], [0.6, 1.4], [1, 0.2]]), 0.3), w)
			_blend(t, "el_r", Vector3(0.2, 0, 0), w)
			_blend(t, "chest", Vector3(0, keys(p, [[0, 0], [0.3, 0.85], [0.6, -1.0], [1, 0]]), 0), w)
			_blend(t, "spine", Vector3(-0.12, keys(p, [[0.3, 0.3], [0.6, -0.4]]), 0), w)
			if action == "sweep":
				_blend(t, "sh_l", Vector3(1.45, keys(p, [[0, 0.0], [0.3, -1.3], [0.6, 1.4], [1, 0.2]]) + 0.4, -0.3), w)
			_show_trail(_trail_h, p, 0.3, 0.6)
		"mine":
			_blend(t, "sh_r", Vector3(keys(p, [[0, 0.7], [0.45, 2.85], [0.62, 0.15], [1, 0.7]]), 0, 0.1), w)
			_blend(t, "el_r", Vector3(keys(p, [[0, 0.6], [0.45, 1.35], [0.62, 0.15], [1, 0.6]]), 0, 0), w)
			_blend(t, "sh_l", Vector3(keys(p, [[0, 0.6], [0.45, 2.3], [0.62, 0.3], [1, 0.6]]), 0, 0.35), w)
			_blend(t, "el_l", Vector3(keys(p, [[0, 0.8], [0.45, 1.2], [0.62, 0.6], [1, 0.8]]), 0, 0), w)
			_blend(t, "spine", Vector3(keys(p, [[0.45, 0.08], [0.62, -0.32], [1, -0.05]]), 0, 0), w)
		"cast", "throw":
			_blend(t, "sh_r", Vector3(keys(p, [[0, 0.2], [0.35, 2.3], [0.55, 1.35], [1, 0.3]]), 0, 0.15), w)
			_blend(t, "el_r", Vector3(keys(p, [[0.35, 1.7], [0.55, 0.05]]), 0, 0), w)
			_blend(t, "sh_l", Vector3(keys(p, [[0.35, 0.9], [0.55, 0.3]]), 0, -0.5), w)
			_blend(t, "chest", Vector3(0, keys(p, [[0, 0], [0.35, 0.45], [0.55, -0.35], [1, 0]]), 0), w)
			_blend(t, "th_l", Vector3(keys(p, [[0.35, 0.0], [0.55, 0.35], [1, 0.0]]), 0, 0), w)
		"shoot":
			_blend(t, "sh_l", Vector3(1.55, -0.2, -0.1), w)
			_blend(t, "el_l", Vector3(0.05, 0, 0), w)
			_blend(t, "sh_r", Vector3(1.5, keys(p, [[0, 0.0], [0.6, 0.5], [0.7, 0.1]]), 0.2), w)
			_blend(t, "el_r", Vector3(keys(p, [[0, 0.3], [0.6, 2.0], [0.7, 0.4]]), 0, 0), w)
			_blend(t, "chest", Vector3(0, 0.6, 0), w)
		"dodge":
			_blend(t, "th_l", Vector3(1.6, 0, 0), w)
			_blend(t, "th_r", Vector3(1.4, 0, 0), w)
			_blend(t, "kn_l", Vector3(-2.2, 0, 0), w)
			_blend(t, "kn_r", Vector3(-2.0, 0, 0), w)
			_blend(t, "sh_l", Vector3(1.1, 0, -0.2), w)
			_blend(t, "sh_r", Vector3(1.1, 0, 0.2), w)
			_blend(t, "el_l", Vector3(1.6, 0, 0), w)
			_blend(t, "el_r", Vector3(1.6, 0, 0), w)
			_blend(t, "spine", Vector3(-0.6, 0, 0), w)
			_blend(t, "neck", Vector3(-0.5, 0, 0), w)
		"hit":
			var f := sin(PI * p)
			t["spine"] += Vector3(0.32, 0, 0.08) * f
			t["head"] += Vector3(0.35, 0.2, 0) * f
			t["sh_l"] += Vector3(-0.4, 0, -0.4) * f
			t["sh_r"] += Vector3(-0.4, 0, 0.4) * f
		"interact":
			_blend(t, "sh_r", Vector3(keys(p, [[0, 0.2], [0.45, 1.35], [1, 0.2]]), 0, 0), w)
			_blend(t, "el_r", Vector3(0.25, 0, 0), w)
			_blend(t, "spine", Vector3(-0.15, 0, 0), w)
		"drink":
			_blend(t, "sh_r", Vector3(keys(p, [[0, 0.3], [0.35, 2.0], [0.75, 2.1], [1, 0.3]]), 0, 0.3), w)
			_blend(t, "el_r", Vector3(keys(p, [[0, 0.3], [0.35, 2.3], [0.75, 2.4], [1, 0.3]]), 0, 0), w)
			_blend(t, "head", Vector3(keys(p, [[0.3, 0.0], [0.5, 0.45], [0.8, 0.4], [1, 0]]), 0, 0), w)
		"jump":
			var crouch := keys(p, [[0, 0.0], [0.25, 1.0], [0.5, 0.0], [1, 0]])
			t["th_l"] += Vector3(0.6, 0, 0) * crouch
			t["th_r"] += Vector3(0.6, 0, 0) * crouch
			t["kn_l"] += Vector3(-1.1, 0, 0) * crouch
			t["kn_r"] += Vector3(-1.1, 0, 0) * crouch
			t["sh_l"] += Vector3(keys(p, [[0.25, -0.5], [0.5, 1.2], [1, 0.3]]), 0, 0) * w
			t["sh_r"] += Vector3(keys(p, [[0.25, -0.5], [0.5, 1.2], [1, 0.3]]), 0, 0) * w
		"slam", "spikes":
			var arm := keys(p, [[0, 0.3], [0.45, 3.0], [0.6, -0.1], [1, 0.3]])
			_blend(t, "sh_l", Vector3(arm, 0, -0.35), w)
			_blend(t, "sh_r", Vector3(arm, 0, 0.35), w)
			_blend(t, "el_l", Vector3(keys(p, [[0.45, 0.9], [0.6, 0.1]]), 0, 0), w)
			_blend(t, "el_r", Vector3(keys(p, [[0.45, 0.9], [0.6, 0.1]]), 0, 0), w)
			_blend(t, "spine", Vector3(keys(p, [[0, 0], [0.45, 0.25], [0.62, -0.5], [1, 0]]), 0, 0), w)
			var crouch := keys(p, [[0.5, 0.0], [0.65, 1.0], [1, 0]])
			t["th_l"] += Vector3(0.5, 0, 0) * crouch
			t["th_r"] += Vector3(0.5, 0, 0) * crouch
			t["kn_l"] += Vector3(-0.9, 0, 0) * crouch
			t["kn_r"] += Vector3(-0.9, 0, 0) * crouch
		"roar", "summon", "howl":
			var up := 2.6 if action == "summon" else 0.6
			_blend(t, "sh_l", Vector3(up, 0, -1.2), w)
			_blend(t, "sh_r", Vector3(up, 0, 1.2), w)
			_blend(t, "el_l", Vector3(0.4, 0, 0), w)
			_blend(t, "el_r", Vector3(0.4, 0, 0), w)
			_blend(t, "chest", Vector3(0.35, 0, 0), w)
			_blend(t, "head", Vector3(0.45 + sin(_time * 30.0) * 0.03, 0, 0), w)
		"lunge":
			_blend(t, "spine", Vector3(-0.65, 0, 0), w)
			_blend(t, "sh_l", Vector3(keys(p, [[0, 0.5], [0.4, 1.9], [1, 0.8]]), 0, -0.2), w)
			_blend(t, "sh_r", Vector3(keys(p, [[0, 0.5], [0.4, 1.9], [1, 0.8]]), 0, 0.2), w)
			_blend(t, "el_l", Vector3(0.1, 0, 0), w)
			_blend(t, "el_r", Vector3(0.1, 0, 0), w)
			_blend(t, "th_l", Vector3(0.7, 0, 0), w)
			_blend(t, "kn_r", Vector3(-0.8, 0, 0), w)
		"teleport":
			_blend(t, "spine", Vector3(-0.4, 0, 0), w)
			_blend(t, "sh_l", Vector3(2.2, 0, -0.8), w)
			_blend(t, "sh_r", Vector3(2.2, 0, 0.8), w)


func _blend(t: Dictionary, key: String, target: Vector3, w: float) -> void:
	t[key] = (t[key] as Vector3).lerp(target, w)


func _show_trail(trail: MeshInstance3D, p: float, from: float, to: float) -> void:
	if _held_id == "" or p < from or p > to + 0.25:
		return
	trail.visible = true
	var m := trail.material_override as ShaderMaterial
	m.set_shader_parameter(&"head", clampf((p - from) / (to - from), 0.0, 1.0))
	m.set_shader_parameter(&"alpha", 1.0 - clampf((p - to) / 0.25, 0.0, 1.0))
