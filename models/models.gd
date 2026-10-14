class_name Models
extends RefCounted
## One place that knows what every creature looks like.
##   Models.create("skeleton") / Models.create("dragon") / Models.player(index) / Models.villager("elder", seed)

const PLAYER_COLOURS := [
	[Color(0.2, 0.17, 0.15), Color(0.55, 0.22, 0.1)],   # ash and ember
	[Color(0.14, 0.18, 0.22), Color(0.3, 0.45, 0.6)],   # river
	[Color(0.22, 0.2, 0.12), Color(0.6, 0.5, 0.2)],     # gold
	[Color(0.2, 0.12, 0.18), Color(0.55, 0.25, 0.45)],  # plum
	[Color(0.12, 0.18, 0.13), Color(0.35, 0.55, 0.3)],  # moss
	[Color(0.24, 0.22, 0.22), Color(0.8, 0.78, 0.75)],  # bone
	[Color(0.25, 0.1, 0.08), Color(0.85, 0.4, 0.2)],    # flame
	[Color(0.1, 0.1, 0.14), Color(0.5, 0.5, 0.7)],      # dusk
]


static func create(kind: String) -> CreatureModel:
	match kind:
		"player":
			return player(0)
		"skeleton":
			return HumanoidModel.new({"skeleton": true, "eyes": Color(1.0, 0.35, 0.1), "cloth": Color(0.22, 0.16, 0.12),
				"held": "sword_rusty", "helmet": true, "helmet_color": Color(0.36, 0.32, 0.28)})
		"archer":
			return HumanoidModel.new({"skeleton": true, "eyes": Color(1.0, 0.6, 0.15), "cloth": Color(0.16, 0.18, 0.14),
				"hood": true, "held": "bow"})
		"ghoul":
			return HumanoidModel.new({"skin": Color(0.42, 0.45, 0.36), "cloth": Color(0.16, 0.13, 0.11), "cloth2": Color(0.24, 0.2, 0.16),
				"gaunt": true, "hunch": -0.45, "arm_length": 1.3, "eyes": Color(0.9, 1.0, 0.3), "hair": Color(0.1, 0.1, 0.1)})
		"troll":
			return HumanoidModel.new({"skin": Color(0.36, 0.42, 0.36), "cloth": Color(0.3, 0.22, 0.15), "cloth2": Color(0.22, 0.16, 0.1),
				"height": 3.2, "bulk": 1.7, "hunch": -0.3, "arm_length": 1.25, "tusks": true, "eyes": Color(1.0, 0.75, 0.2),
				"held": "club"})
		"imp":
			return ImpModel.new()
		"shade":
			return ShadeModel.new()
		"warden":
			return HumanoidModel.new({"skeleton": true, "height": 4.4, "bulk": 1.35, "eyes": Color(0.4, 1.0, 0.55),
				"helmet": true, "helmet_color": Color(0.28, 0.3, 0.26), "cloak": true, "tattered": true,
				"cloak_color": Color(0.14, 0.17, 0.13), "cloth": Color(0.14, 0.17, 0.13), "held": "warden_blade"})
		"mountain_king":
			return HumanoidModel.new({"skin": Color(0.48, 0.55, 0.62), "cloth": Color(0.25, 0.3, 0.38), "cloth2": Color(0.62, 0.7, 0.78),
				"height": 6.2, "bulk": 1.9, "hunch": -0.25, "arm_length": 1.2, "tusks": true, "beard": true, "hair": Color(0.85, 0.9, 0.95),
				"eyes": Color(0.5, 0.85, 1.0), "crown": Color(0.55, 0.9, 1.0), "cloak": true, "cloak_color": Color(0.35, 0.4, 0.5),
				"held": "giant_club"})
		"hades":
			return HumanoidModel.new({"skin": Color(0.32, 0.3, 0.36), "cloth": Color(0.07, 0.06, 0.09), "cloth2": Color(0.35, 0.1, 0.08),
				"height": 5.0, "bulk": 1.25, "robe": true, "cloak": true, "tattered": true, "cloak_color": Color(0.08, 0.06, 0.1),
				"eyes": Color(0.4, 0.75, 1.0), "crown": Color(0.45, 0.75, 1.0), "crown_fire": true, "beard": true,
				"hair": Color(0.15, 0.15, 0.2), "held": "scythe"})
		"dragon":
			return DragonModel.new()
		"cerberus":
			return CerberusModel.new()
	if kind.begins_with("villager") or kind in ["elder", "chief", "blacksmith", "merchant"]:
		return villager(kind.trim_prefix("villager_"), kind.hash())
	return HumanoidModel.new({})


static func player(colour_index: int, torch_shadows := true) -> HumanoidModel:
	return HumanoidModel.new(player_style(colour_index, torch_shadows))


static func player_style(colour_index: int, torch_shadows := true) -> Dictionary:
	var c: Array = PLAYER_COLOURS[posmod(colour_index, PLAYER_COLOURS.size())]
	return {"skin": Color(0.74, 0.58, 0.46), "cloth": c[0], "cloth2": c[1], "hood": true, "cloak": true,
		"cloak_color": (c[0] as Color).darkened(0.15), "boots": Color(0.14, 0.1, 0.07), "torch_shadows": torch_shadows}


static func villager(role: String, seed_value: int) -> HumanoidModel:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var skins := [Color(0.82, 0.66, 0.52), Color(0.68, 0.5, 0.38), Color(0.5, 0.36, 0.26), Color(0.85, 0.72, 0.6)]
	var cloths := [Color(0.42, 0.32, 0.2), Color(0.3, 0.33, 0.25), Color(0.45, 0.2, 0.15), Color(0.25, 0.28, 0.35), Color(0.5, 0.45, 0.35)]
	var hairs := [Color(0.15, 0.1, 0.06), Color(0.4, 0.25, 0.12), Color(0.7, 0.6, 0.4), Color(0.1, 0.08, 0.08), Color(0.6, 0.6, 0.58)]
	var style := {
		"skin": skins[rng.randi() % skins.size()], "cloth": cloths[rng.randi() % cloths.size()],
		"cloth2": cloths[rng.randi() % cloths.size()].darkened(0.3), "hair": hairs[rng.randi() % hairs.size()],
		"height": rng.randf_range(1.62, 1.86), "bulk": rng.randf_range(0.92, 1.12),
	}
	match role:
		"elder", "chief":
			style.merge({"robe": true, "beard": true, "hair": Color(0.82, 0.8, 0.76), "cloth": Color(0.3, 0.22, 0.32),
				"cloth2": Color(0.6, 0.45, 0.2), "hunch": -0.15, "held": "lantern" if role == "elder" else ""}, true)
		"blacksmith":
			style.merge({"apron": true, "bulk": 1.25, "beard": rng.randf() < 0.6, "cloth": Color(0.3, 0.25, 0.2), "held": "pickaxe_iron"}, true)
		"merchant":
			style.merge({"hat": true, "cloth": Color(0.35, 0.18, 0.3), "cloth2": Color(0.7, 0.55, 0.25), "bulk": 1.15}, true)
		"guard":
			style.merge({"helmet": true, "cloth": Color(0.3, 0.3, 0.32), "cloth2": Color(0.55, 0.15, 0.1), "held": "sword_iron"}, true)
		_:
			style["hood"] = rng.randf() < 0.3
			style["beard"] = rng.randf() < 0.3
	return HumanoidModel.new(style)
