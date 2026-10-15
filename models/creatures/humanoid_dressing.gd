class_name HumanoidDressing
extends RefCounted
## Extra gear and growths attached to a HumanoidModel's joints after it has
## built itself, so humanoid monsters read differently at a glance without
## touching the character code: shields, quivers, pauldrons, ragged claws,
## moss and mushrooms on trolls, icicles, seaweed and barnacles on the
## drowned, the bog witch's gnarled staff, hump, wild hair and charms.
##
##   HumanoidDressing.dress(model, ["shield", "pauldrons"], {"metal": Color(...)})
##
## Joints are looked up by the HumanoidModel's public names (chest, head,
## hand_l...) with a fallback to node names, and anything missing is skipped,
## so changes to the character rig degrade gracefully.

## Attach `items` once the model has built (or now, if it already has).
static func dress(model: CreatureModel, items: Array, opts := {}) -> CreatureModel:
	if items.is_empty():
		return model
	if model.is_node_ready():
		_apply(model, items, opts)
	else:
		model.ready.connect(func() -> void: _apply(model, items, opts), CONNECT_ONE_SHOT)
	return model


static func _joint(model: Node, prop: String, node_name: String) -> Node3D:
	var j: Variant = model.get(prop)
	if j is Node3D and is_instance_valid(j):
		return j
	var found := model.find_child(node_name, true, false)
	return found as Node3D


static func _apply(model: CreatureModel, items: Array, opts: Dictionary) -> void:
	var s := float(model.get("_s")) if model.get("_s") != null else 1.0
	var b := float(model.get("_b")) if model.get("_b") != null else 1.0
	var chest := _joint(model, "chest", "Chest")
	var head := _joint(model, "head", "Head")
	var hips := _joint(model, "hips", "Hips")
	var hand_l := _joint(model, "hand_l", "Hand")
	var hand_r := _joint(model, "hand_r", "Hand")
	var grip_r := _joint(model, "grip_r", "Grip")
	var sh_l := _joint(model, "sh_l", "Shoulder")
	var sh_r := _joint(model, "sh_r", "Shoulder")
	var metal := ModelKit.metal(opts.get("metal", Color(0.42, 0.36, 0.3)))
	var rust := CreatureSkin.rock(opts.get("rust", Color(0.4, 0.27, 0.18)), {"pattern_scale": 9.0, "roughness": 0.7, "bump": 0.8})
	var wood := CreatureSkin.hide(Color(0.28, 0.2, 0.13), Color(0.2, 0.14, 0.09), {"pattern_scale": 8.0, "roughness": 0.9})
	var bone := CreatureSkin.keratin(Color(0.8, 0.76, 0.64))
	for item: String in items:
		match item:
			"shield":
				if hand_l != null:
					var holder := ModelKit.joint(hand_l, "Shield", Vector3(-0.05 * s, -0.06 * s, 0))
					ModelKit.part(holder, OrganicMesh.blob("dress_shield", Vector3(0.05, 0.3, 0.26), 0.05, 4, 14), wood, Vector3.ZERO, Vector3(0, 0, 0), Vector3.ONE * s)
					ModelKit.part(holder, ModelKit.cylinder(0.33, 0.33, 0.03, 16), rust, Vector3(-0.02 * s, 0, 0), Vector3(0, 0, 90), Vector3(1.0, 1.0, 0.85) * s)
					ModelKit.part(holder, ModelKit.sphere(0.07, 8), metal, Vector3(-0.06 * s, 0, 0), Vector3.ZERO, Vector3.ONE * s)
			"quiver":
				if chest != null:
					var q := ModelKit.joint(chest, "Quiver", Vector3(0.1 * s, 0.12 * s, 0.17 * s * b))
					q.rotation_degrees = Vector3(-12, 0, 24)
					ModelKit.part(q, ModelKit.cylinder(0.07, 0.06, 0.62, 8), wood, Vector3.ZERO, Vector3.ZERO, Vector3.ONE * s)
					for i in 5:
						ModelKit.part(q, ModelKit.cylinder(0.008, 0.008, 0.3, 4), wood, Vector3((i - 2) * 0.022 * s, 0.4 * s, (i % 2) * 0.02 * s), Vector3.ZERO, Vector3.ONE * s)
						ModelKit.part(q, ModelKit.box(Vector3(0.03, 0.08, 0.005)), ModelKit.cloth(Color(0.75, 0.7, 0.62)), Vector3((i - 2) * 0.022 * s, 0.52 * s, (i % 2) * 0.02 * s), Vector3.ZERO, Vector3.ONE * s)
			"pauldrons":
				for sh: Node3D in [sh_l, sh_r]:
					if sh == null:
						continue
					var side := signf(sh.position.x) if sh.position.x != 0.0 else 1.0
					ModelKit.part(sh, OrganicMesh.blob("dress_pauldron", Vector3(0.14, 0.09, 0.15), 0.05, 6, 12), rust, Vector3(side * 0.03 * s, 0.05 * s, 0), Vector3(0, 0, side * -20), Vector3(b, 1, b) * s)
					ModelKit.part(sh, OrganicMesh.bezier("dress_pspike", Vector3.ZERO, Vector3(0.02, 0.06, 0), Vector3(0.05, 0.12, 0.0), 0.025, 0.003, 5, 5), bone, Vector3(side * 0.05 * s, 0.12 * s, 0), Vector3(0, 0, side * -25), Vector3.ONE * s)
			"breastplate":
				if chest != null:
					ModelKit.part(chest, OrganicMesh.blob("dress_breastplate", Vector3(0.22, 0.2, 0.06), 0.04, 8, 14), rust, Vector3(0, 0.18 * s, -0.11 * s * b), Vector3.ZERO, Vector3(b, 1, 1) * s)
			"claws":
				for hand: Node3D in [hand_l, hand_r]:
					if hand == null:
						continue
					for i in 4:
						var x := (float(i) - 1.5) * 0.022
						ModelKit.part(hand, OrganicMesh.bezier("dress_claw", Vector3.ZERO, Vector3(0, -0.06, -0.02), Vector3(0, -0.12, 0.03), 0.012, 0.002, 5, 4), CreatureSkin.keratin(Color(0.2, 0.18, 0.12)), Vector3(x * s, -0.08 * s, -0.02 * s), Vector3.ZERO, Vector3.ONE * s)
			"moss":
				var moss := CreatureSkin.fur(Color(0.2, 0.3, 0.12), Color(0.15, 0.2, 0.1), {"pattern_scale": 20.0})
				for j: Node3D in [chest, sh_l, sh_r, head]:
					if j == null:
						continue
					var n := 3 if j == chest else 1
					for i in n:
						var p := Vector3((float(i) - 1.0) * 0.12, 0.3 if j == chest else 0.05, 0.08 if j == chest else 0.0) * s
						ModelKit.part(j, OrganicMesh.blob("dress_moss_%d" % i, Vector3(0.12, 0.06, 0.1), 0.45, 21 + i, 10), moss, p, Vector3.ZERO, Vector3(b, 1, b) * s)
				if head != null:
					var cap := CreatureSkin.smooth(Color(0.6, 0.25, 0.12), Color(0.8, 0.7, 0.55))
					ModelKit.part(head, ModelKit.sphere(0.06, 8), cap, Vector3(0.1 * s, 0.32 * s, 0.03 * s), Vector3.ZERO, Vector3(1, 0.5, 1) * s)
					ModelKit.part(head, ModelKit.cylinder(0.015, 0.02, 0.06, 6), CreatureSkin.smooth(Color(0.85, 0.8, 0.7), Color(0.85, 0.8, 0.7)), Vector3(0.1 * s, 0.29 * s, 0.03 * s), Vector3.ZERO, Vector3.ONE * s)
			"back_spikes":
				if chest != null:
					for i in 4:
						var p := Vector3(0, (0.42 - i * 0.12) * s, 0.14 * s * b)
						ModelKit.part(chest, OrganicMesh.bezier("dress_bspike", Vector3.ZERO, Vector3(0, 0.05, 0.08), Vector3(0, 0.08, 0.2), 0.05, 0.005, 6, 5), bone, p, Vector3.ZERO, Vector3.ONE * s * (1.0 - i * 0.12))
			"icicles":
				var ice := CreatureSkin.smooth(Color(0.75, 0.88, 0.98), Color(0.6, 0.75, 0.9), {"roughness": 0.15, "specular_amount": 0.8, "rim": 0.6})
				for j: Node3D in [chest, sh_l, sh_r, head]:
					if j == null:
						continue
					for i in 3:
						var p := Vector3((float(i) - 1.0) * 0.08, 0.36 if j == chest else 0.08, 0.1 if j == chest else 0.0) * s
						ModelKit.part(j, ModelKit.cone(0.03, 0.18, 5), ice, p, Vector3(180 if j != head else 0, 0, (float(i) - 1.0) * 15.0), Vector3.ONE * s)
			"seaweed":
				var weed := CreatureSkin.membrane(Color(0.16, 0.3, 0.14), {"backlight": 0.5})
				for j: Node3D in [chest, sh_l, sh_r, hips]:
					if j == null:
						continue
					for i in 3:
						var len := 0.35 + 0.15 * float(i % 2)
						var pts := PackedVector2Array([Vector2(-0.03, 0), Vector2(0.03, 0), Vector2(0.05, -len * 0.5), Vector2(0.01, -len), Vector2(-0.04, -len * 0.6)])
						var x := (float(i) - 1.0) * 0.12
						ModelKit.part(j, OrganicMesh.membrane("dress_weed_%d" % i, pts, 0.02, 0.01), weed, Vector3(x, 0.33 if j == chest else 0.0, 0.11 if j == chest else 0.05) * s, Vector3(0, 0, (float(i) - 1.0) * 10.0), Vector3.ONE * s)
			"barnacles":
				var shell := CreatureSkin.rock(Color(0.62, 0.6, 0.55), {"pattern_scale": 14.0})
				for j: Node3D in [chest, head, sh_l, sh_r]:
					if j == null:
						continue
					for i in 3:
						var p := Vector3(sin(i * 2.1) * 0.12, (0.15 + 0.08 * i) if j == chest else (0.12 if j == head else 0.0), cos(i * 2.1) * 0.1) * s
						ModelKit.part(j, ModelKit.cylinder(0.012, 0.03, 0.03, 6), shell, p, Vector3(randf_range(-30, 30), 0, randf_range(-30, 30)), Vector3.ONE * s)
			"hag_staff":
				# Held upright in the right hand, rising past the shoulder.
				var holder: Node3D = hand_r
				if holder != null:
					var staff := OrganicMesh.bezier("dress_hag_staff", Vector3(0, -0.6, 0), Vector3(0.06, 0.5, 0.05), Vector3(0.0, 1.35, 0.0), 0.035, 0.022, 10, 6)
					holder = ModelKit.joint(holder, "Staff", Vector3(0, -0.05 * s, -0.07 * s))
					ModelKit.part(holder, staff, wood, Vector3.ZERO, Vector3.ZERO, Vector3.ONE * s)
					# A crooked crown of twigs holding a glowing bog-light.
					for i in 4:
						var a := TAU * float(i) / 4.0
						ModelKit.part(holder, OrganicMesh.bezier("dress_hag_twig_%d" % i, Vector3.ZERO, Vector3(cos(a) * 0.06, 0.1, sin(a) * 0.06), Vector3(cos(a) * 0.03, 0.22, sin(a) * 0.03), 0.012, 0.004, 5, 4), wood, Vector3(0, 1.32 * s, 0), Vector3.ZERO, Vector3.ONE * s)
					ModelKit.part(holder, ModelKit.sphere(0.07, 10), ModelKit.glow(opts.get("glow", Color(0.5, 1.0, 0.4)), 6.0, 0.6), Vector3(0, 1.45 * s, 0), Vector3.ZERO, Vector3.ONE * s)
					var light := OmniLight3D.new()
					light.light_color = opts.get("glow", Color(0.5, 1.0, 0.4))
					light.light_energy = 1.4
					light.omni_range = 7.0
					light.shadow_enabled = false
					light.position = Vector3(0, 1.45 * s, 0)
					holder.add_child(light)
			"hump":
				if chest != null:
					var robe := ModelKit.cloth(opts.get("cloth", Color(0.16, 0.18, 0.12)))
					ModelKit.part(chest, OrganicMesh.blob("dress_hump", Vector3(0.2, 0.18, 0.16), 0.2, 12, 12), robe, Vector3(0, 0.28 * s, 0.12 * s), Vector3.ZERO, Vector3(b, 1, b) * s)
			"wild_hair":
				if head != null:
					var hair := CreatureSkin.fur(opts.get("hair", Color(0.6, 0.62, 0.55)), Color(0.4, 0.4, 0.35), {"pattern_scale": 30.0})
					for i in 7:
						var a := lerpf(-1.3, 1.3, float(i) / 6.0)
						var tip := Vector3(sin(a) * 0.18, -0.45 - 0.1 * float(i % 3), 0.12 + cos(a) * 0.06)
						ModelKit.part(head, OrganicMesh.bezier("dress_hair_%d" % i, Vector3.ZERO, tip * 0.5 + Vector3(0, 0.08, 0.02), tip, 0.035, 0.006, 6, 5), hair, Vector3(sin(a) * 0.12, 0.3, 0.02) * s, Vector3.ZERO, Vector3.ONE * s)
			"charms":
				if chest != null:
					for i in 5:
						var x := (float(i) - 2.0) * 0.07
						ModelKit.part(chest, ModelKit.sphere(0.03, 6), bone, Vector3(x, 0.3 - absf(x) * 0.6, -0.15 * b) * s, Vector3.ZERO, Vector3(1, 1.3, 1) * s)
					ModelKit.part(chest, OrganicMesh.blob("dress_skull_charm", Vector3(0.05, 0.055, 0.05), 0.08, 31, 10), bone, Vector3(0, 0.17, -0.16 * b) * s, Vector3.ZERO, Vector3.ONE * s)
			"bone_crown":
				if head != null:
					for i in 6:
						var a := TAU * float(i) / 6.0
						ModelKit.part(head, OrganicMesh.bezier("dress_bcrown", Vector3.ZERO, Vector3(0, 0.08, 0.01), Vector3(0, 0.15, 0.04), 0.022, 0.003, 5, 4), bone, Vector3(cos(a) * 0.13, 0.33, sin(a) * 0.13) * s, Vector3(0, -rad_to_deg(a), 0), Vector3.ONE * s)
			"tusks_big":
				if head != null:
					for side: float in [-1.0, 1.0]:
						ModelKit.part(head, OrganicMesh.bezier("dress_tusk", Vector3.ZERO, Vector3(0.0, 0.06, -0.04), Vector3(0.02, 0.12, -0.02), 0.025, 0.004, 6, 5), bone, Vector3(side * 0.08, 0.05, -0.13) * s, Vector3(0, 0, side * -15), Vector3.ONE * s)
	model.refresh_parts()
