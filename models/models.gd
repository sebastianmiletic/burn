class_name Models
extends RefCounted
## One place that knows what every creature looks like.
##   Models.create("skeleton") / Models.create_mob("wolf", net_id) / Models.player(index) / Models.villager("elder", seed)
## create_mob picks a per-individual variant (size, colouring, gear) from the
## seed, identically on every machine.

const PLAYER_COLOURS := [
	[Color(0.36, 0.3, 0.25), Color(0.62, 0.27, 0.12)],  # ash and ember
	[Color(0.26, 0.31, 0.37), Color(0.34, 0.5, 0.66)],  # river
	[Color(0.38, 0.34, 0.22), Color(0.66, 0.55, 0.24)], # gold
	[Color(0.34, 0.22, 0.31), Color(0.6, 0.3, 0.5)],    # plum
	[Color(0.24, 0.32, 0.24), Color(0.4, 0.6, 0.34)],   # moss
	[Color(0.4, 0.38, 0.37), Color(0.82, 0.8, 0.77)],   # bone
	[Color(0.42, 0.18, 0.13), Color(0.88, 0.44, 0.22)], # flame
	[Color(0.2, 0.2, 0.27), Color(0.55, 0.55, 0.74)],   # dusk
]


static func create(kind: String) -> CreatureModel:
	return create_mob(kind, 0)


## Model for any creature kind; `seed_value` (the entity's net id) picks a variant.
static func create_mob(kind: String, seed_value: int) -> CreatureModel:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) + seed_value * 7919
	match kind:
		"player":
			return player(0)
		"skeleton", "archer", "ghoul", "troll", "drowned", "warden", "mountain_king", "hades", "bog_hag":
			return _humanoid_mob(kind, rng)
		"imp":
			return ImpModel.new()
		"shade":
			return ShadeModel.new()
		"dragon":
			return DragonModel.new()
		"cerberus":
			return CerberusModel.new()
		"leviathan", "sea_serpent":
			return LeviathanModel.new(kind)
		"broodmother":
			return BroodmotherModel.new()
		"giant_spider", "spiderling", "scorpion":
			return ArachnidModel.new("spider" if kind == "giant_spider" else kind, seed_value)
		"wolf", "dire_wolf", "frost_wolf", "hellhound", "bear", "deer", "stag", "rabbit", "goat", "boar", "bog_lurker":
			return QuadrupedModel.new(kind, seed_value)
		"cave_bat":
			return FlyerModel.new("bat", seed_value)
		"bird_flock", "gull_flock", "crow_flock", "fish_school", "bat_swarm":
			return FlockModel.new(kind, seed_value)
		"rock_golem":
			return GolemModel.new(seed_value)
		"fire_elemental":
			return ElementalModel.new(seed_value)
		"cave_crawler", "shark":
			return CrawlerModel.new(kind, seed_value)
	if kind.begins_with("villager") or kind in ["elder", "chief", "blacksmith", "merchant"]:
		return villager(kind.trim_prefix("villager_"), kind.hash())
	return HumanoidModel.new({})


## Humanoid monsters: one HumanoidModel style per kind plus per-individual
## variation, and gear / growths attached by HumanoidDressing so each kind has
## its own silhouette.
static func _humanoid_mob(kind: String, rng: RandomNumberGenerator) -> CreatureModel:
	var style := {}
	var gear: Array = []
	var opts := {}
	match kind:
		"skeleton":
			var bones := [Color(0.82, 0.79, 0.7), Color(0.72, 0.66, 0.5), Color(0.5, 0.45, 0.38)]
			var eyes := [Color(1.0, 0.35, 0.1), Color(1.0, 0.15, 0.08), Color(0.4, 0.75, 1.0)]
			var rags := [Color(0.22, 0.16, 0.12), Color(0.3, 0.12, 0.1), Color(0.15, 0.17, 0.14)]
			style = {"skeleton": true, "bone": bones[rng.randi() % bones.size()], "eyes": eyes[rng.randi() % eyes.size()],
				"cloth": rags[rng.randi() % rags.size()], "held": "sword_rusty", "height": rng.randf_range(1.78, 1.95)}
			match rng.randi() % 3:
				0:
					style["helmet"] = true
					style["helmet_color"] = Color(0.36, 0.32, 0.28)
					gear = ["shield"]
				1:
					gear = ["pauldrons"]
				_:
					style["helmet"] = true
					style["helmet_color"] = Color(0.3, 0.27, 0.24)
					style["height"] = 2.05
					style["bulk"] = 1.15
					gear = ["breastplate", "pauldrons", "shield"]
			opts = {"rust": Color(0.42, 0.28, 0.18)}
		"archer":
			var hoods := [Color(0.16, 0.18, 0.14), Color(0.22, 0.17, 0.12), Color(0.17, 0.17, 0.19)]
			style = {"skeleton": true, "eyes": Color(1.0, 0.6, 0.15), "cloth": hoods[rng.randi() % hoods.size()],
				"hood": true, "cloak": rng.randf() < 0.5, "tattered": true, "held": "bow", "height": rng.randf_range(1.75, 1.9)}
			gear = ["quiver"]
		"ghoul":
			var skins := [Color(0.42, 0.45, 0.36), Color(0.45, 0.38, 0.44), Color(0.6, 0.6, 0.55), Color(0.35, 0.4, 0.42)]
			style = {"skin": skins[rng.randi() % skins.size()], "cloth": Color(0.16, 0.13, 0.11), "cloth2": Color(0.24, 0.2, 0.16),
				"gaunt": true, "hunch": rng.randf_range(-0.55, -0.35), "arm_length": rng.randf_range(1.25, 1.4),
				"eyes": Color(0.9, 1.0, 0.3) if rng.randf() < 0.6 else Color(1.0, 0.4, 0.2), "hair": Color(0.1, 0.1, 0.1),
				"height": rng.randf_range(1.6, 1.8)}
			gear = ["claws"]
			if rng.randf() < 0.5:
				gear.append("wild_hair")
				opts["hair"] = Color(0.2, 0.2, 0.18)
		"troll":
			var tribe := rng.randi() % 3
			var skins := [Color(0.36, 0.42, 0.3), Color(0.45, 0.45, 0.47), Color(0.4, 0.33, 0.28)]
			style = {"skin": skins[tribe], "cloth": Color(0.3, 0.22, 0.15), "cloth2": Color(0.22, 0.16, 0.1),
				"height": rng.randf_range(2.9, 3.6), "bulk": rng.randf_range(1.55, 1.85), "hunch": -0.3, "arm_length": 1.25,
				"tusks": true, "eyes": Color(1.0, 0.75, 0.2), "held": "club" if tribe != 1 else "giant_club"}
			var tribe_gear := [["moss"], ["back_spikes", "pauldrons"], ["tusks_big", "charms"]]
			gear = tribe_gear[tribe]
		"drowned":
			var skins := [Color(0.42, 0.52, 0.5), Color(0.35, 0.45, 0.48), Color(0.5, 0.55, 0.48)]
			style = {"skin": skins[rng.randi() % skins.size()], "cloth": Color(0.12, 0.16, 0.16), "cloth2": Color(0.2, 0.24, 0.2),
				"gaunt": true, "hunch": -0.25, "eyes": Color(0.35, 1.0, 0.9), "hair": Color(0.08, 0.12, 0.1),
				"tattered": true, "cloak": rng.randf() < 0.4, "cloak_color": Color(0.1, 0.14, 0.13),
				"held": "sword_rusty" if rng.randf() < 0.5 else "", "height": rng.randf_range(1.75, 1.95)}
			gear = ["seaweed", "barnacles", "claws"]
		"warden":
			style = {"skeleton": true, "height": 4.4, "bulk": 1.35, "eyes": Color(0.4, 1.0, 0.55),
				"helmet": true, "helmet_color": Color(0.28, 0.3, 0.26), "cloak": true, "tattered": true,
				"cloak_color": Color(0.14, 0.17, 0.13), "cloth": Color(0.14, 0.17, 0.13), "held": "warden_blade"}
			gear = ["pauldrons", "breastplate", "bone_crown"]
			opts = {"rust": Color(0.3, 0.32, 0.27)}
		"mountain_king":
			style = {"skin": Color(0.48, 0.55, 0.62), "cloth": Color(0.25, 0.3, 0.38), "cloth2": Color(0.62, 0.7, 0.78),
				"height": 6.2, "bulk": 1.9, "hunch": -0.25, "arm_length": 1.2, "tusks": true, "beard": true, "hair": Color(0.85, 0.9, 0.95),
				"eyes": Color(0.5, 0.85, 1.0), "crown": Color(0.55, 0.9, 1.0), "cloak": true, "cloak_color": Color(0.35, 0.4, 0.5),
				"held": "giant_club"}
			gear = ["icicles", "pauldrons"]
			opts = {"rust": Color(0.5, 0.58, 0.66)}
		"hades":
			style = {"skin": Color(0.32, 0.3, 0.36), "cloth": Color(0.07, 0.06, 0.09), "cloth2": Color(0.35, 0.1, 0.08),
				"height": 5.0, "bulk": 1.25, "robe": true, "cloak": true, "tattered": true, "cloak_color": Color(0.08, 0.06, 0.1),
				"eyes": Color(0.4, 0.75, 1.0), "crown": Color(0.45, 0.75, 1.0), "crown_fire": true, "beard": true,
				"hair": Color(0.15, 0.15, 0.2), "held": "scythe"}
			gear = ["charms"]
		"bog_hag":
			style = {"skin": Color(0.5, 0.56, 0.42), "cloth": Color(0.14, 0.17, 0.11), "cloth2": Color(0.3, 0.24, 0.14),
				"height": 2.0, "bulk": 0.95, "hunch": -0.5, "gaunt": true, "arm_length": 1.3, "robe": true, "hood": true,
				"cloak": true, "tattered": true, "cloak_color": Color(0.12, 0.14, 0.1), "eyes": Color(0.5, 1.0, 0.35), "held": ""}
			gear = ["hag_staff", "hump", "wild_hair", "charms", "claws"]
			opts = {"hair": Color(0.62, 0.64, 0.58), "glow": Color(0.5, 1.0, 0.4), "cloth": Color(0.14, 0.17, 0.11)}
	var model := HumanoidModel.new(style)
	return HumanoidDressing.dress(model, gear, opts)


static func player(colour_index: int, torch_shadows := true) -> HumanoidModel:
	return HumanoidModel.new(player_style(colour_index, torch_shadows))


static func player_style(colour_index: int, torch_shadows := true) -> Dictionary:
	var c: Array = PLAYER_COLOURS[posmod(colour_index, PLAYER_COLOURS.size())]
	return {"skin": Color(0.74, 0.58, 0.46), "cloth": c[0], "cloth2": c[1], "hood": true, "cloak": true,
		"cloak_color": (c[0] as Color).darkened(0.08), "boots": Color(0.14, 0.1, 0.07), "torch_shadows": torch_shadows}


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
