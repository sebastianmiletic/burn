class_name ActivityItems
extends RefCounted
## Models for the items the activities hand out (ItemDB "model_script"), in the
## item kit's conventions: built along +Y from the grip, metres.

static func _p(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	return ModelKit.part(parent, mesh, mat, pos, rot, scl)


static func build(body: Node3D, id: String) -> bool:
	match id:
		"treasure_map":
			_map(body)
		"ancient_coin":
			_coin(body)
		"gilded_idol":
			_idol(body)
		"starmetal":
			_starmetal(body)
		"trophy_fang":
			var path := PackedVector3Array([Vector3(0, 0.0, 0), Vector3(0.008, 0.05, 0), Vector3(0.025, 0.1, 0), Vector3(0.05, 0.13, 0)])
			_p(body, ItemMesh.tube(path, PackedFloat32Array([0.018, 0.015, 0.009, 0.001]), 8), ItemMats.bone(Color(0.93, 0.89, 0.78)))
			_p(body, ModelKit.cylinder(0.022, 0.022, 0.012, 10), ItemMats.leather(Color(0.3, 0.18, 0.1)), Vector3(0, -0.004, 0))
		"trophy_pelt":
			var fur := ItemMats.make({"albedo": Color(0.45, 0.37, 0.3), "accent": Color(0.25, 0.2, 0.16), "roughness": 0.95, "finish": ItemMats.Finish.CLOTH,
				"ascii_id": AsciiMaterialId.CLOTH, "bump_amount": 2.0})
			_p(body, ItemMesh.plate(PackedVector2Array([Vector2(-0.12, 0), Vector2(-0.06, -0.04), Vector2(0.06, -0.04), Vector2(0.12, 0), Vector2(0.09, 0.14),
				Vector2(0.13, 0.22), Vector2(0.0, 0.26), Vector2(-0.13, 0.22), Vector2(-0.09, 0.14)]), PackedFloat32Array([0.012, 0.012, 0.012, 0.012, 0.016, 0.012, 0.012, 0.012, 0.016]), 0.006, true), fur)
			_p(body, ModelKit.cylinder(0.014, 0.014, 0.2, 6), ItemMats.cloth(Color(0.6, 0.5, 0.35)), Vector3(0, 0.12, 0.0), Vector3(0, 0, 90))
		"trophy_skull":
			_p(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.045, 0.01), Vector2(0.062, 0.05), Vector2(0.058, 0.09), Vector2(0.035, 0.115), Vector2(0.0, 0.12)]), 14, true, Vector2(0.9, 1.1)), ItemMats.bone())
			for s: float in [-1.0, 1.0]:
				_p(body, ModelKit.sphere(0.016, 8), ItemMats.glow(Color(1.0, 0.45, 0.15), 4.0), Vector3(s * 0.022, 0.06, 0.05))
			_p(body, ItemMesh.bevel_box(Vector3(0.06, 0.03, 0.05), 0.008), ItemMats.bone(Color(0.8, 0.76, 0.64)), Vector3(0, 0.012, 0.03))
		"pickaxe_starfall":
			GearModels.pickaxe(body, "mithril", _star_steel())
			_p(body, ItemMesh.bevel_box(Vector3(0.42, 0.004, 0.003), 0.001), ItemMats.glow(Color(0.55, 0.7, 1.0), 4.0), Vector3(0, 0.735, 0.022))
		"sword_starfall":
			GearModels.sword(body, "mithril", _star_steel())
			_p(body, ItemMesh.blade(0.68, PackedFloat32Array([0.006, 0.006, 0.005, 0.005, 0.004, 0.003, 0.002, 0.0]), 0.012, 0.0), ItemMats.glow(Color(0.55, 0.7, 1.0), 4.0), Vector3(0, 0.22, 0))
		"sword_champion":
			GearModels.sword(body, "adamantite", ItemMats.metal("gold"))
			_p(body, ItemMesh.gem_cut(0.022, 8), ItemMats.glow(Color(1.0, 0.55, 0.2), 5.0), Vector3(0, 0.12, 0.012), Vector3(90, 0, 0))
		"storm_horn":
			var path := PackedVector3Array()
			var radii := PackedFloat32Array()
			for i in 8:
				var t := float(i) / 7.0
				path.append(Vector3(sin(t * 2.2) * 0.05, t * 0.22, 0.0))
				radii.append(lerpf(0.008, 0.04, t * t))
			_p(body, ItemMesh.tube(path, radii, 10), ItemMats.bone(Color(0.82, 0.78, 0.7)))
			for k in 3:
				var t2 := 0.3 + k * 0.22
				_p(body, ModelKit.cylinder(radii[int(t2 * 7)] + 0.004, radii[int(t2 * 7)] + 0.004, 0.008, 12), ItemMats.metal("silver"), path[int(t2 * 7)])
			_p(body, ItemMesh.gem_cut(0.012, 6), ItemMats.glow(Color(0.6, 0.7, 1.0), 5.0), path[4] + Vector3(0, 0, 0.03), Vector3(90, 0, 0))
		"sunstone":
			_p(body, ItemMesh.gem_cut(0.045, 12, 0.5, 0.9), ItemMats.gem(Color(1.0, 0.75, 0.25), 0.05, 2.5), Vector3(0, 0.06, 0))
			_p(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.034, 0.012), Vector2(0.0, 0.016)]), 12, true), ItemMats.metal("gold"), Vector3(0, 0.0, 0))
		"fog_lantern":
			var lantern := HeldItems.build("lantern", 1.0)
			if lantern != null:
				for c in lantern.get_children():
					c.reparent(body, false)
				lantern.free()
			_p(body, ModelKit.sphere(0.045, 10), ItemMats.glass(Color(0.75, 0.85, 0.95)), Vector3(0, -0.15, 0), Vector3.ZERO, Vector3(1.0, 1.6, 1.0))
		"frost_totem":
			_p(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.025, 0.0), Vector2(0.03, 0.1), Vector2(0.022, 0.2), Vector2(0.0, 0.215)]), 8, true), ItemMats.wood(Color(0.42, 0.34, 0.26)))
			for i in 3:
				var a := float(i) * TAU / 3.0
				_p(body, ItemMesh.crystal(0.012, 0.07, 6), ItemMats.glow(Color(0.6, 0.9, 1.0), 3.0), Vector3(cos(a) * 0.026, 0.17, sin(a) * 0.026), Vector3(rad_to_deg(sin(a)) * 25.0, 0, rad_to_deg(cos(a)) * -25.0))
			_p(body, ModelKit.cylinder(0.033, 0.033, 0.012, 10), ItemMats.cloth(Color(0.2, 0.35, 0.6)), Vector3(0, 0.12, 0))
		_:
			return false
	return true


static func _star_steel() -> Material:
	return ItemMats.make({"albedo": Color(0.5, 0.56, 0.75), "accent": Color(0.15, 0.17, 0.3), "metallic": 0.95, "roughness": 0.16, "finish": ItemMats.Finish.METAL,
		"wear": 0.05, "emission_mode": ItemMats.Emit.SHIMMER, "emission_color": Color(0.55, 0.7, 1.0), "emission_energy": 1.4})


static func _map(body: Node3D) -> void:
	var paper := ItemMats.cloth(Color(0.84, 0.74, 0.52))
	# A rolled sheet with one end loosely unrolled, tied with red cord.
	_p(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.026, 0.0), Vector2(0.028, 0.01), Vector2(0.028, 0.21), Vector2(0.026, 0.22)]), 14, true), paper, Vector3(0, 0, 0))
	_p(body, ItemMesh.plate_even(PackedVector2Array([Vector2(0.0, 0.01), Vector2(0.13, 0.03), Vector2(0.14, 0.2), Vector2(0.0, 0.21)]), 0.0012), paper, Vector3(0.02, 0, 0.012), Vector3(0, -25, 0))
	var ink := ItemMats.make({"albedo": Color(0.45, 0.08, 0.05), "roughness": 0.8})
	_p(body, ItemMesh.bevel_box(Vector3(0.025, 0.004, 0.003), 0.001), ink, Vector3(0.085, 0.1, 0.045), Vector3(0, -25, 45))
	_p(body, ItemMesh.bevel_box(Vector3(0.025, 0.004, 0.003), 0.001), ink, Vector3(0.085, 0.1, 0.045), Vector3(0, -25, -45))
	_p(body, ModelKit.cylinder(0.03, 0.03, 0.012, 12), ItemMats.cloth(Color(0.65, 0.1, 0.08)), Vector3(0, 0.11, 0))


static func _coin(body: Node3D) -> void:
	var gold := ItemMats.metal("gold")
	_p(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.032, 0.003), Vector2(0.03, 0.006), Vector2(0.0, 0.006)]), 18, true), gold, Vector3(0, 0.03, 0), Vector3(90, 0, 0))
	_p(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.018, 0.0), Vector2(0.0, 0.0012)]), 12, true), ItemMats.metal("bronze"), Vector3(0, 0.03, 0.0065), Vector3(90, 0, 0))


static func _idol(body: Node3D) -> void:
	var gold := ItemMats.metal("gold")
	_p(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.035, 0.02), Vector2(0.03, 0.06), Vector2(0.036, 0.09), Vector2(0.02, 0.11),
		Vector2(0.03, 0.13), Vector2(0.028, 0.155), Vector2(0.0, 0.165)]), 12, true), gold)
	for s: float in [-1.0, 1.0]:
		_p(body, ModelKit.sphere(0.006, 6), ItemMats.glow(Color(1.0, 0.4, 0.1), 5.0), Vector3(s * 0.01, 0.14, 0.024))


static func _starmetal(body: Node3D) -> void:
	_p(body, ItemMesh.rock(0.055, 41, 0.3, 2, Vector3(1.1, 0.85, 0.9)), ItemMats.make({"albedo": Color(0.32, 0.36, 0.5), "accent": Color(0.1, 0.12, 0.2),
		"metallic": 0.9, "roughness": 0.28, "finish": ItemMats.Finish.ORE, "emission_mode": ItemMats.Emit.SHIMMER, "emission_color": Color(0.5, 0.65, 1.0), "emission_energy": 1.8}), Vector3(0, 0.05, 0))
	for i in 3:
		var a := float(i) * 2.1
		_p(body, ItemMesh.crystal(0.008, 0.035, 5), ItemMats.glow(Color(0.6, 0.75, 1.0), 4.0), Vector3(cos(a) * 0.035, 0.08, sin(a) * 0.03), Vector3(rad_to_deg(cos(a)) * 30.0, 0, rad_to_deg(sin(a)) * 30.0))
