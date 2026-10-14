class_name HeldItems
extends RefCounted
## Meshes for things held in a hand. Every item is built pointing along +Y
## from the grip (handle at the origin); the hand's Grip joint turns +Y forward.
## Scale `s` follows the holder's size.


static func build(item_id: String, s := 1.0, torch_shadows := false) -> Node3D:
	var root := Node3D.new()
	root.name = "Held_" + item_id
	var wood := ModelKit.mat(Color(0.36, 0.24, 0.14), AsciiMaterialId.SOLID, 0.85, 0.3)
	var dark_wood := ModelKit.mat(Color(0.2, 0.13, 0.08), AsciiMaterialId.SOLID, 0.85, 0.3)
	match item_id:
		"pickaxe_stone", "pickaxe_iron", "pickaxe_obsidian":
			var head_color := {"pickaxe_stone": Color(0.5, 0.49, 0.47), "pickaxe_iron": Color(0.75, 0.74, 0.72), "pickaxe_obsidian": Color(0.18, 0.1, 0.24)}[item_id] as Color
			var head := ModelKit.metal(head_color) if item_id != "pickaxe_stone" else ModelKit.mat(head_color, AsciiMaterialId.SOLID, 0.9, 0.35)
			ModelKit.part(root, ModelKit.cylinder(0.022, 0.026, 0.78, 6), wood, Vector3(0, 0.3 * s, 0), Vector3.ZERO, Vector3.ONE * s)
			ModelKit.part(root, ModelKit.box(Vector3(0.07, 0.08, 0.07)), head, Vector3(0, 0.68 * s, 0), Vector3.ZERO, Vector3.ONE * s)
			for side: float in [-1.0, 1.0]:
				ModelKit.part(root, ModelKit.box(Vector3(0.26, 0.06, 0.05)), head, Vector3(side * 0.15 * s, 0.66 * s, 0), Vector3(0, 0, side * -14), Vector3.ONE * s)
				ModelKit.part(root, ModelKit.cone(0.03, 0.1, 4), head, Vector3(side * 0.3 * s, 0.61 * s, 0), Vector3(0, 0, side * 110), Vector3.ONE * s)
			if item_id == "pickaxe_obsidian":
				ModelKit.part(root, ModelKit.box(Vector3(0.5, 0.012, 0.012)), ModelKit.glow(Color(0.7, 0.3, 1.0), 3.0), Vector3(0, 0.63 * s, -0.03 * s), Vector3.ZERO, Vector3.ONE * s)
		"sword_rusty", "sword_iron", "sword_ember", "sword_dragonbone", "warden_blade":
			var big := item_id == "sword_dragonbone" or item_id == "warden_blade"
			var blade_len := 1.25 if big else 0.85
			var width := 0.11 if big else 0.075
			var blade_c := {"sword_rusty": Color(0.55, 0.4, 0.3), "sword_iron": Color(0.82, 0.82, 0.84), "sword_ember": Color(0.55, 0.5, 0.48),
					"sword_dragonbone": Color(0.9, 0.86, 0.72), "warden_blade": Color(0.4, 0.42, 0.38)}[item_id] as Color
			var blade := ModelKit.metal(blade_c) if item_id != "sword_dragonbone" else ModelKit.mat(blade_c, AsciiMaterialId.SOLID, 0.6, 0.35)
			ModelKit.part(root, ModelKit.cylinder(0.025, 0.025, 0.2, 6), dark_wood, Vector3(0, 0.0, 0), Vector3.ZERO, Vector3.ONE * s)
			ModelKit.part(root, ModelKit.box(Vector3(0.06, 0.06, 0.06)), ModelKit.metal(Color(0.6, 0.5, 0.3)), Vector3(0, -0.12 * s, 0), Vector3.ZERO, Vector3.ONE * s)
			ModelKit.part(root, ModelKit.box(Vector3(width * 3.2, 0.045, 0.06)), ModelKit.metal(Color(0.55, 0.45, 0.28)), Vector3(0, 0.12 * s, 0), Vector3.ZERO, Vector3.ONE * s)
			ModelKit.part(root, ModelKit.slab(PackedVector2Array([Vector2(-width * 0.5, 0), Vector2(width * 0.5, 0), Vector2(width * 0.42, blade_len * 0.85), Vector2(0, blade_len), Vector2(-width * 0.42, blade_len * 0.85)]), 0.022),
					blade, Vector3(0, 0.14 * s, 0), Vector3.ZERO, Vector3.ONE * s)
			if item_id == "sword_ember":
				ModelKit.part(root, ModelKit.box(Vector3(0.016, blade_len * 0.8, 0.026)), ModelKit.glow(Color(1.0, 0.45, 0.12), 6.0, 0.3), Vector3(0, (0.14 + blade_len * 0.42) * s, 0), Vector3.ZERO, Vector3.ONE * s)
				var e := ModelKit.embers(root, 10, Vector3(0.03, blade_len * 0.4, 0.03) * s, 0.8, 0.06 * s, 0.8)
				e.position = Vector3(0, (0.14 + blade_len * 0.45) * s, 0)
				e.emitting = true
			elif item_id == "sword_dragonbone":
				for i in 4:
					ModelKit.part(root, ModelKit.cone(0.035, 0.16, 4), blade, Vector3(width * 0.55 * s, (0.35 + i * 0.22) * s, 0), Vector3(0, 0, -70), Vector3.ONE * s)
				ModelKit.part(root, ModelKit.box(Vector3(0.016, blade_len * 0.75, 0.026)), ModelKit.glow(Color(1.0, 0.35, 0.1), 4.0, 0.5), Vector3(0, (0.14 + blade_len * 0.4) * s, 0), Vector3.ZERO, Vector3.ONE * s)
			elif item_id == "warden_blade":
				ModelKit.part(root, ModelKit.box(Vector3(0.014, blade_len * 0.7, 0.026)), ModelKit.glow(Color(0.5, 1.0, 0.6), 3.0, 0.4), Vector3(0, (0.14 + blade_len * 0.4) * s, 0), Vector3.ZERO, Vector3.ONE * s)
		"torch":
			ModelKit.part(root, ModelKit.cylinder(0.03, 0.022, 0.5, 6), wood, Vector3(0, 0.15 * s, 0), Vector3.ZERO, Vector3.ONE * s)
			ModelKit.part(root, ModelKit.cylinder(0.045, 0.035, 0.08, 6), ModelKit.mat(Color(0.25, 0.18, 0.12), AsciiMaterialId.CLOTH), Vector3(0, 0.42 * s, 0), Vector3.ZERO, Vector3.ONE * s)
			_flame(root, Vector3(0, 0.5 * s, 0), s, torch_shadows, 1.5, 9.0)
		"lantern":
			var iron := ModelKit.metal(Color(0.25, 0.24, 0.24))
			ModelKit.part(root, ModelKit.cylinder(0.01, 0.01, 0.2, 4), iron, Vector3(0, 0.1 * s, 0), Vector3.ZERO, Vector3.ONE * s)
			ModelKit.part(root, ModelKit.box(Vector3(0.16, 0.03, 0.16)), iron, Vector3(0, 0.0, 0), Vector3.ZERO, Vector3.ONE * s)
			ModelKit.part(root, ModelKit.box(Vector3(0.11, 0.15, 0.11)), ModelKit.glow(Color(1.0, 0.72, 0.38), 5.0, 0.15), Vector3(0, -0.1 * s, 0), Vector3.ZERO, Vector3.ONE * s)
			ModelKit.part(root, ModelKit.box(Vector3(0.16, 0.03, 0.16)), iron, Vector3(0, -0.19 * s, 0), Vector3.ZERO, Vector3.ONE * s)
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.72, 0.4)
			light.light_energy = 1.6
			light.omni_range = 10.0
			light.shadow_enabled = torch_shadows
			light.light_volumetric_fog_energy = 1.0
			light.position = Vector3(0, -0.1 * s, 0)
			root.add_child(light)
		"potion_health", "potion_greater":
			var c := ItemDB.color(item_id)
			ModelKit.part(root, ModelKit.sphere(0.07, 8), ModelKit.mat(c, AsciiMaterialId.SOLID, 0.15, 0.05, 0.6), Vector3(0, 0.07 * s, 0), Vector3.ZERO, Vector3.ONE * s)
			ModelKit.part(root, ModelKit.cylinder(0.025, 0.025, 0.07, 6), ModelKit.mat(Color(0.7, 0.75, 0.75), AsciiMaterialId.SOLID, 0.2), Vector3(0, 0.16 * s, 0), Vector3.ZERO, Vector3.ONE * s)
			ModelKit.part(root, ModelKit.cylinder(0.02, 0.02, 0.03, 6), wood, Vector3(0, 0.21 * s, 0), Vector3.ZERO, Vector3.ONE * s)
		"bread":
			ModelKit.part(root, ModelKit.box(Vector3(0.16, 0.1, 0.1)), ModelKit.mat(ItemDB.color(item_id)), Vector3(0, 0.06 * s, 0), Vector3.ZERO, Vector3.ONE * s)
		"club":
			ModelKit.part(root, ModelKit.cylinder(0.12, 0.05, 1.1, 7), dark_wood, Vector3(0, 0.45 * s, 0), Vector3.ZERO, Vector3.ONE * s)
			for i in 3:
				ModelKit.part(root, ModelKit.cone(0.04, 0.12, 4), ModelKit.mat(Color(0.4, 0.4, 0.4)), Vector3(0.1 * s, (0.7 + i * 0.12) * s, 0), Vector3(0, 0, -90), Vector3.ONE * s)
		"giant_club":
			var stone := ModelKit.mat(Color(0.5, 0.52, 0.56), AsciiMaterialId.SOLID, 0.9, 0.35)
			ModelKit.part(root, ModelKit.cylinder(0.05, 0.05, 1.3, 7), dark_wood, Vector3(0, 0.55 * s, 0), Vector3.ZERO, Vector3.ONE * s)
			ModelKit.part(root, ModelKit.box(Vector3(0.55, 0.32, 0.36)), stone, Vector3(0, 1.25 * s, 0), Vector3.ZERO, Vector3.ONE * s)
			ModelKit.part(root, ModelKit.box(Vector3(0.6, 0.06, 0.4)), ModelKit.glow(Color(0.5, 0.85, 1.0), 2.5, 0.3), Vector3(0, 1.25 * s, 0), Vector3.ZERO, Vector3.ONE * s)
		"scythe":
			var shaft := ModelKit.mat(Color(0.12, 0.1, 0.12), AsciiMaterialId.SOLID, 0.5)
			ModelKit.part(root, ModelKit.cylinder(0.03, 0.03, 2.0, 6), shaft, Vector3(0, 0.6 * s, 0), Vector3.ZERO, Vector3.ONE * s)
			var blade := PackedVector2Array([Vector2(0, 0), Vector2(0.15, 0.08), Vector2(0.7, 0.05), Vector2(1.15, -0.25), Vector2(0.6, -0.08), Vector2(0.1, -0.1)])
			ModelKit.part(root, ModelKit.slab(blade, 0.03), ModelKit.metal(Color(0.3, 0.3, 0.34)), Vector3(0, 1.55 * s, 0), Vector3.ZERO, Vector3.ONE * s)
			ModelKit.part(root, ModelKit.box(Vector3(1.0, 0.02, 0.04)), ModelKit.glow(Color(0.45, 0.75, 1.0), 4.0, 0.4), Vector3(0.55 * s, 1.56 * s, 0), Vector3(0, 0, -6), Vector3.ONE * s)
		"bow":
			var limb := ModelKit.mat(Color(0.32, 0.22, 0.14))
			for side: float in [-1.0, 1.0]:
				ModelKit.part(root, ModelKit.cylinder(0.015, 0.025, 0.5, 5), limb, Vector3(0, side * 0.22 * s + 0.1 * s, 0.05 * s), Vector3(side * 20, 0, 0), Vector3.ONE * s)
			ModelKit.part(root, ModelKit.cylinder(0.004, 0.004, 0.9, 3), ModelKit.mat(Color(0.8, 0.8, 0.75)), Vector3(0, 0.1 * s, 0.13 * s), Vector3.ZERO, Vector3.ONE * s)
		_:
			if ItemDB.exists(item_id):
				var info := ItemDB.info(item_id)
				var c := ItemDB.color(item_id)
				if info.get("category", "") == "key" or info.get("category", "") == "material":
					ModelKit.part(root, ModelKit.box(Vector3(0.12, 0.12, 0.12)), ModelKit.glow(c, 2.5, 0.3) if info.get("category") == "key" else ModelKit.mat(c), Vector3(0, 0.08 * s, 0), Vector3(30, 30, 0), Vector3.ONE * s)
				else:
					var block_c := c
					if info.has("place_block"):
						block_c = Blocks.color(int(info["place_block"]))
					ModelKit.part(root, ModelKit.box(Vector3(0.24, 0.24, 0.24)), ModelKit.mat(block_c, AsciiMaterialId.SOLID, 0.85, 0.3), Vector3(0, 0.1 * s, 0), Vector3(15, 25, 0), Vector3.ONE * s)
			else:
				root.free()
				return null
	return root


static func _flame(parent: Node3D, pos: Vector3, s: float, shadows: bool, energy: float, radius: float) -> void:
	var core := ModelKit.part(parent, ModelKit.sphere(0.045, 6), ModelKit.glow(Color(1.0, 0.7, 0.3), 6.0, 0.3), pos, Vector3.ZERO, Vector3.ONE * s)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flame := GPUParticles3D.new()
	flame.amount = 24
	flame.lifetime = 0.45
	flame.local_coords = false
	flame.position = pos
	flame.visibility_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 3, 2))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.035 * s
	pm.direction = Vector3.UP
	pm.spread = 10.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3(0, 1.4, 0)
	var c := Curve.new()
	c.add_point(Vector2(0, 0.6))
	c.add_point(Vector2(0.3, 1.0))
	c.add_point(Vector2(1, 0.1))
	var ct := CurveTexture.new()
	ct.curve = c
	pm.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	flame.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.22) * s
	quad.material = MaterialLibrary.fx(Color(1.0, 0.82, 0.45), Color(1.0, 0.3, 0.05), 6.0)
	flame.draw_pass_1 = quad
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(flame)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.28)
	light.light_energy = energy
	light.omni_range = radius
	light.omni_attenuation = 1.3
	light.shadow_enabled = shadows
	light.light_volumetric_fog_energy = 1.5
	light.position = pos + Vector3(0, 0.1, 0)
	parent.add_child(light)
	var flicker := _Flicker.new()
	flicker.light = light
	flicker.base = energy
	parent.add_child(flicker)


class _Flicker:
	extends Node
	var light: OmniLight3D
	var base := 1.5
	var _t := randf() * 10.0

	func _process(delta: float) -> void:
		_t += delta
		if light != null:
			light.light_energy = base * (1.0 + sin(_t * 17.0) * 0.08 + sin(_t * 7.3) * 0.1 + sin(_t * 31.0) * 0.05)
