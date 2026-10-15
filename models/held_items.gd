class_name HeldItems
extends RefCounted
## Meshes for things held in a hand, and for every item's icon. Every item is
## built pointing along +Y from the grip (handle at the origin); the hand's
## Grip joint turns +Y forward. Scale `s` follows the holder's size.
##
## Real models live in models/items/: GearModels (tools, weapons per tier),
## ArmorModels, GoodsModels (ores, ingots, gems, potions, food, blocks,
## relics) and StationModels (crafting stations, miniature for the item).
## Creature props (club, scythe, bow, warden_blade...) stay here.


static func build(item_id: String, s := 1.0, torch_shadows := false) -> Node3D:
	var root := Node3D.new()
	root.name = "Held_" + item_id
	var body := Node3D.new()
	body.name = "Body"
	body.scale = Vector3.ONE * s
	root.add_child(body)
	if not _build_into(body, item_id, torch_shadows):
		root.free()
		return null
	return root


## A model for showing an item on its own (ground drops, shelves): centred
## on its bounds, lying the way it would rest, at most `max_size` metres.
static func display(item_id: String, max_size := 0.42) -> Node3D:
	var model := build(item_id, 1.0, false)
	if model == null:
		return null
	var holder := Node3D.new()
	holder.name = "Display_" + item_id
	holder.add_child(model)
	if ItemIcons.pose(item_id) == "diagonal":
		model.rotation_degrees = Vector3(0, 0, -90)
	var box := _bounds(model)
	var biggest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var k := minf(1.0, max_size / maxf(biggest, 0.001))
	model.scale = Vector3.ONE * k
	model.position = -box.get_center() * k + Vector3(0, box.size.y * 0.5 * k, 0)
	return holder


static func _bounds(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [[model, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var n: Node = e[0]
		var xf: Transform3D = e[1]
		for c in n.get_children():
			if c is Node3D:
				stack.append([c, xf * (c as Node3D).transform])
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null:
			var b := xf * mi.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
	return box


static func _build_into(body: Node3D, item_id: String, torch_shadows: bool) -> bool:
	var inf := ItemDB.info(item_id)
	var cat := String(inf.get("category", ""))
	var kind := String(inf.get("kind", ""))
	var tier := String(inf.get("tier", ""))
	match item_id:
		"sword_rusty":
			GearModels.sword(body, "iron", ItemMats.metal("rust"))
			return true
		"sword_ember":
			GearModels.sword(body, "steel")
			_p(body, ItemMesh.blade(0.7, PackedFloat32Array([0.014, 0.014, 0.013, 0.012, 0.011, 0.009, 0.006, 0.0]), 0.0128, 0.0), ItemMats.glow(Color(1.0, 0.45, 0.12), 5.0), Vector3(0, 0.21, 0))
			var e := ModelKit.embers(body, 10, Vector3(0.03, 0.34, 0.03), 0.8, 0.05, 0.8)
			e.position = Vector3(0, 0.6, 0)
			e.emitting = true
			return true
		"sword_dragonbone":
			_dragonbone(body)
			return true
		"pickaxe_obsidian":
			GearModels.pickaxe(body, "steel", ItemMats.gem(Color(0.16, 0.08, 0.24), 0.1, 0.4))
			_p(body, ItemMesh.bevel_box(Vector3(0.44, 0.004, 0.003), 0.001), ItemMats.glow(Color(0.7, 0.3, 1.0), 3.0), Vector3(0, 0.735, 0.022))
			return true
		"torch":
			_torch(body, torch_shadows)
			return true
		"lantern":
			_lantern(body, torch_shadows)
			return true
	if (cat == "tool" or cat == "weapon") and ItemDB.KINDS.has(kind) and tier != "":
		GearModels.build(body, kind, tier)
		return true
	if cat == "armor":
		ArmorModels.build(body, kind, tier)
		return true
	if cat == "station":
		var st := StationModels.build(String(inf.get("place_station", "workbench")), false)
		st.scale = Vector3.ONE * 0.2
		body.add_child(st)
		return true
	if GoodsModels.build(body, item_id):
		return true
	if _creature_prop(body, item_id):
		return true
	if ItemDB.exists(item_id):
		# Anything without a bespoke model: a bevelled block in its colour.
		var c := ItemDB.color(item_id)
		if inf.has("place_block"):
			c = Blocks.color(int(inf["place_block"]))
		_p(body, ItemMesh.bevel_box(Vector3(0.18, 0.18, 0.18), 0.01), ItemMats.stone(c, c.darkened(0.3)), Vector3(0, 0.09, 0))
		return true
	return false


static func _p(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	return ModelKit.part(parent, mesh, mat, pos, rot, scl)


static func _dragonbone(body: Node3D) -> void:
	var bone := ItemMats.bone(Color(0.92, 0.87, 0.74))
	var length := 1.2
	var w := PackedFloat32Array()
	for i in 12:
		var f := float(i) / 11.0
		w.append(0.11 * (1.0 - f * 0.3) * (1.0 - pow(f, 6.0)) * (1.0 + 0.08 * sin(f * 30.0)))
	w[11] = 0.0
	_p(body, ItemMesh.blade(length, w, 0.03, 0.0), bone, Vector3(0, 0.22, 0))
	for i in 5:
		var y := 0.35 + i * 0.2
		_p(body, ModelKit.cone(0.03, 0.14, 5), bone, Vector3(0.06 - i * 0.003, y, 0), Vector3(0, 0, -70))
	_p(body, ItemMesh.bevel_box(Vector3(0.012, length * 0.7, 0.032), 0.002), ItemMats.glow(Color(1.0, 0.35, 0.1), 4.0), Vector3(0, 0.22 + length * 0.4, 0))
	GearModels.guard(body, 0.2, "adamantite", 0.28)
	GearModels.grip_wrap(body, -0.08, 0.18, 0.02, ItemMats.leather(Color(0.25, 0.08, 0.05)))
	_p(body, ModelKit.sphere(0.03, 8), bone, Vector3(0, -0.1, 0))


static func _torch(body: Node3D, shadows: bool) -> void:
	var wood := ItemMats.wood(Color(0.42, 0.28, 0.16), Color(0.2, 0.12, 0.06))
	_p(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.018, -0.06), Vector2(0.022, 0.0), Vector2(0.026, 0.28), Vector2(0.03, 0.4)]), 8, true), wood)
	var cloth := ItemMats.cloth(Color(0.3, 0.2, 0.13))
	_p(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.03, 0.36), Vector2(0.045, 0.39), Vector2(0.048, 0.44), Vector2(0.04, 0.47), Vector2(0.0, 0.48)]), 10, true), cloth)
	_p(body, ItemMesh.rock(0.035, 3, 0.3, 1, Vector3(1.0, 0.7, 1.0)), ItemMats.molten(Color(0.1, 0.05, 0.03), Color(1.0, 0.45, 0.1), 5.0), Vector3(0, 0.48, 0))
	_flame(body, Vector3(0, 0.5, 0), 1.0, shadows, 1.5, 9.0)


static func _lantern(body: Node3D, shadows: bool) -> void:
	var iron := ItemMats.metal("dark_iron")
	var brass := ItemMats.metal("brass")
	_p(body, ItemMesh.tube(PackedVector3Array([Vector3(-0.04, -0.02, 0), Vector3(0, 0.03, 0), Vector3(0.04, -0.02, 0)]), PackedFloat32Array([0.004, 0.004, 0.004]), 5), iron)
	_p(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, -0.06), Vector2(0.06, -0.06), Vector2(0.075, -0.075), Vector2(0.0, -0.075)]), 8, false), brass)
	_p(body, ModelKit.cone(0.07, 0.05, 8), brass, Vector3(0, -0.04, 0))
	_p(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.05, -0.23), Vector2(0.052, -0.08)]), 8, true), ItemMats.glass(Color(1.0, 0.85, 0.6)))
	for i in 4:
		var a := TAU * (float(i) + 0.5) / 4.0
		_p(body, ModelKit.cylinder(0.005, 0.005, 0.16, 4), iron, Vector3(cos(a) * 0.058, -0.155, sin(a) * 0.058))
	_p(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, -0.25), Vector2(0.07, -0.25), Vector2(0.07, -0.23), Vector2(0.0, -0.23)]), 8, false), brass)
	_p(body, ModelKit.sphere(0.022, 8), ItemMats.glow(Color(1.0, 0.72, 0.38), 6.0), Vector3(0, -0.15, 0), Vector3.ZERO, Vector3(0.8, 1.3, 0.8))
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.4)
	light.light_energy = 1.6
	light.omni_range = 10.0
	light.shadow_enabled = shadows
	light.light_volumetric_fog_energy = 1.0
	light.position = Vector3(0, -0.15, 0)
	body.add_child(light)


static func _creature_prop(body: Node3D, item_id: String) -> bool:
	var dark_wood := ModelKit.mat(Color(0.2, 0.13, 0.08), AsciiMaterialId.SOLID, 0.85, 0.3)
	match item_id:
		"club":
			_p(body, ModelKit.cylinder(0.12, 0.05, 1.1, 7), dark_wood, Vector3(0, 0.45, 0))
			for i in 3:
				_p(body, ModelKit.cone(0.04, 0.12, 4), ModelKit.mat(Color(0.4, 0.4, 0.4)), Vector3(0.1, 0.7 + i * 0.12, 0), Vector3(0, 0, -90))
		"giant_club":
			var stone := ModelKit.mat(Color(0.5, 0.52, 0.56), AsciiMaterialId.SOLID, 0.9, 0.35)
			_p(body, ModelKit.cylinder(0.05, 0.05, 1.3, 7), dark_wood, Vector3(0, 0.55, 0))
			_p(body, ModelKit.box(Vector3(0.55, 0.32, 0.36)), stone, Vector3(0, 1.25, 0))
			_p(body, ModelKit.box(Vector3(0.6, 0.06, 0.4)), ModelKit.glow(Color(0.5, 0.85, 1.0), 2.5, 0.3), Vector3(0, 1.25, 0))
		"scythe":
			var shaft := ModelKit.mat(Color(0.12, 0.1, 0.12), AsciiMaterialId.SOLID, 0.5)
			_p(body, ModelKit.cylinder(0.03, 0.03, 2.0, 6), shaft, Vector3(0, 0.6, 0))
			var blade := PackedVector2Array([Vector2(0, 0), Vector2(0.15, 0.08), Vector2(0.7, 0.05), Vector2(1.15, -0.25), Vector2(0.6, -0.08), Vector2(0.1, -0.1)])
			_p(body, ModelKit.slab(blade, 0.03), ModelKit.metal(Color(0.3, 0.3, 0.34)), Vector3(0, 1.55, 0))
			_p(body, ModelKit.box(Vector3(1.0, 0.02, 0.04)), ModelKit.glow(Color(0.45, 0.75, 1.0), 4.0, 0.4), Vector3(0.55, 1.56, 0), Vector3(0, 0, -6))
		"bow":
			var limb := ModelKit.mat(Color(0.32, 0.22, 0.14))
			for side: float in [-1.0, 1.0]:
				_p(body, ModelKit.cylinder(0.015, 0.025, 0.5, 5), limb, Vector3(0, side * 0.22 + 0.1, 0.05), Vector3(side * 20, 0, 0))
			_p(body, ModelKit.cylinder(0.004, 0.004, 0.9, 3), ModelKit.mat(Color(0.8, 0.8, 0.75)), Vector3(0, 0.1, 0.13))
		"warden_blade":
			var blade_len := 1.25
			var width := 0.11
			_p(body, ModelKit.cylinder(0.025, 0.025, 0.2, 6), dark_wood, Vector3.ZERO)
			_p(body, ModelKit.box(Vector3(0.06, 0.06, 0.06)), ModelKit.metal(Color(0.6, 0.5, 0.3)), Vector3(0, -0.12, 0))
			_p(body, ModelKit.box(Vector3(width * 3.2, 0.045, 0.06)), ModelKit.metal(Color(0.55, 0.45, 0.28)), Vector3(0, 0.12, 0))
			_p(body, ModelKit.slab(PackedVector2Array([Vector2(-width * 0.5, 0), Vector2(width * 0.5, 0), Vector2(width * 0.42, blade_len * 0.85), Vector2(0, blade_len), Vector2(-width * 0.42, blade_len * 0.85)]), 0.022),
					ModelKit.metal(Color(0.4, 0.42, 0.38)), Vector3(0, 0.14, 0))
			_p(body, ModelKit.box(Vector3(0.014, blade_len * 0.7, 0.026)), ModelKit.glow(Color(0.5, 1.0, 0.6), 3.0, 0.4), Vector3(0, 0.14 + blade_len * 0.4, 0))
		_:
			return false
	return true


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
