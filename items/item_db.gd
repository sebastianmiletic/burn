class_name ItemDB
extends RefCounted
## Every item in the game. Items are plain ids (Strings) plus counts; this
## table holds their behaviour.
##
## category: "tool", "weapon", "consumable", "material", "block", "light", "key", "currency"
## glyph: the character the UI draws for the item icon.

const ITEMS := {
	# Tools and weapons ------------------------------------------------------
	"pickaxe_stone": {"name": "Stone Pickaxe", "category": "tool", "glyph": "T", "color": Color(0.6, 0.58, 0.55),
		"mine_tier": 1, "mine_speed": 1.0, "damage": 4.0, "stack": 1, "value": 5,
		"desc": "Chips through stone and coal. Too soft for gold."},
	"pickaxe_iron": {"name": "Iron Pickaxe", "category": "tool", "glyph": "T", "color": Color(0.78, 0.74, 0.7),
		"mine_tier": 2, "mine_speed": 1.6, "damage": 6.0, "stack": 1, "value": 40,
		"desc": "Forged in Emberfall. Breaks gold and ember crystal."},
	"pickaxe_obsidian": {"name": "Obsidian Pickaxe", "category": "tool", "glyph": "T", "color": Color(0.5, 0.3, 0.7),
		"mine_tier": 3, "mine_speed": 2.4, "damage": 8.0, "stack": 1, "value": 160,
		"desc": "Black glass edge. Cuts obsidian and hellstone."},
	"sword_rusty": {"name": "Rusty Sword", "category": "weapon", "glyph": "/", "color": Color(0.62, 0.45, 0.35),
		"damage": 9.0, "speed": 1.0, "reach": 2.6, "stack": 1, "value": 5,
		"desc": "Better than bare hands. Barely."},
	"sword_iron": {"name": "Iron Sword", "category": "weapon", "glyph": "/", "color": Color(0.82, 0.8, 0.78),
		"damage": 16.0, "speed": 1.1, "reach": 2.8, "stack": 1, "value": 60,
		"desc": "A soldier's blade, balanced and true."},
	"sword_ember": {"name": "Emberbrand", "category": "weapon", "glyph": "/", "color": Color(1.0, 0.5, 0.2),
		"damage": 26.0, "speed": 1.15, "reach": 3.0, "stack": 1, "value": 200, "burn": 6.0,
		"desc": "Ember crystal set in steel. Sets foes alight."},
	"sword_dragonbone": {"name": "Dragonbone Greatsword", "category": "weapon", "glyph": "/", "color": Color(0.95, 0.9, 0.75),
		"damage": 40.0, "speed": 0.9, "reach": 3.4, "stack": 1, "value": 500, "burn": 10.0,
		"desc": "Carved from Ashvane's spine. Heavy, cruel, glorious."},
	# Consumables ----------------------------------------------------------
	"potion_health": {"name": "Health Potion", "category": "consumable", "glyph": "!", "color": Color(0.9, 0.2, 0.2),
		"heal": 45.0, "stack": 10, "value": 12, "desc": "Restores 45 health."},
	"potion_greater": {"name": "Greater Potion", "category": "consumable", "glyph": "!", "color": Color(1.0, 0.45, 0.3),
		"heal": 120.0, "stack": 10, "value": 40, "desc": "Restores 120 health."},
	"bread": {"name": "Hearth Bread", "category": "consumable", "glyph": "o", "color": Color(0.8, 0.6, 0.35),
		"heal": 15.0, "stack": 20, "value": 3, "desc": "Warm and filling. Restores 15 health."},
	# Light ----------------------------------------------------------------
	"torch": {"name": "Torch", "category": "light", "glyph": "i", "color": Color(1.0, 0.7, 0.3),
		"place_block": 29, "stack": 64, "value": 1, "desc": "Hold to light your way. Right-click to place."},
	"lantern": {"name": "Lantern", "category": "light", "glyph": "%", "color": Color(1.0, 0.75, 0.4),
		"place_block": 40, "stack": 16, "value": 6, "desc": "A brighter, steadier light. Place it."},
	# Blocks ---------------------------------------------------------------
	"stone": {"name": "Stone", "category": "block", "glyph": "#", "color": Color(0.5, 0.49, 0.48), "place_block": 1, "stack": 99, "value": 0},
	"cobble": {"name": "Cobblestone", "category": "block", "glyph": "#", "color": Color(0.45, 0.44, 0.43), "place_block": 10, "stack": 99, "value": 0},
	"dirt": {"name": "Dirt", "category": "block", "glyph": "#", "color": Color(0.45, 0.32, 0.2), "place_block": 2, "stack": 99, "value": 0},
	"sand": {"name": "Sand", "category": "block", "glyph": "#", "color": Color(0.8, 0.7, 0.5), "place_block": 4, "stack": 99, "value": 0},
	"snow": {"name": "Snow", "category": "block", "glyph": "#", "color": Color(0.9, 0.9, 0.92), "place_block": 5, "stack": 99, "value": 0},
	"gravel": {"name": "Gravel", "category": "block", "glyph": "#", "color": Color(0.5, 0.48, 0.45), "place_block": 12, "stack": 99, "value": 0},
	"wood": {"name": "Wood", "category": "block", "glyph": "=", "color": Color(0.5, 0.35, 0.2), "place_block": 7, "stack": 99, "value": 1},
	"planks": {"name": "Planks", "category": "block", "glyph": "=", "color": Color(0.65, 0.46, 0.27), "place_block": 9, "stack": 99, "value": 1},
	"brick": {"name": "Castle Brick", "category": "block", "glyph": "#", "color": Color(0.42, 0.4, 0.4), "place_block": 11, "stack": 99, "value": 1},
	"thatch": {"name": "Thatch", "category": "block", "glyph": "~", "color": Color(0.7, 0.58, 0.3), "place_block": 25, "stack": 99, "value": 0},
	"basalt": {"name": "Basalt", "category": "block", "glyph": "#", "color": Color(0.3, 0.27, 0.27), "place_block": 21, "stack": 99, "value": 0},
	"ash": {"name": "Ash", "category": "block", "glyph": ".", "color": Color(0.4, 0.37, 0.36), "place_block": 22, "stack": 99, "value": 0},
	"bone": {"name": "Bone", "category": "block", "glyph": "-", "color": Color(0.85, 0.82, 0.72), "place_block": 23, "stack": 99, "value": 2},
	"soul_sand": {"name": "Soul Sand", "category": "block", "glyph": "#", "color": Color(0.4, 0.3, 0.25), "place_block": 39, "stack": 99, "value": 0},
	"obsidian": {"name": "Obsidian", "category": "block", "glyph": "#", "color": Color(0.3, 0.15, 0.4), "place_block": 17, "stack": 99, "value": 8},
	# Materials ------------------------------------------------------------
	"coal": {"name": "Coal", "category": "material", "glyph": "*", "color": Color(0.25, 0.25, 0.25), "stack": 99, "value": 2,
		"desc": "Fuel for the forge."},
	"iron_ore": {"name": "Iron Ore", "category": "material", "glyph": "*", "color": Color(0.75, 0.6, 0.5), "stack": 99, "value": 5,
		"desc": "Bring it to a blacksmith."},
	"gold_ore": {"name": "Gold Ore", "category": "material", "glyph": "*", "color": Color(1.0, 0.82, 0.35), "stack": 99, "value": 15,
		"desc": "Merchants pay well for this."},
	"ember_crystal": {"name": "Ember Crystal", "category": "material", "glyph": "*", "color": Color(1.0, 0.5, 0.2), "stack": 99, "value": 30,
		"desc": "Warm to the touch. Found deep below."},
	"frost_shard": {"name": "Frost Shard", "category": "material", "glyph": "*", "color": Color(0.6, 0.9, 1.0), "stack": 99, "value": 20,
		"desc": "Never melts."},
	"hellstone": {"name": "Hellstone", "category": "material", "glyph": "*", "color": Color(0.9, 0.2, 0.1), "stack": 99, "value": 60,
		"desc": "Mined in the underworld. Burns without fire."},
	# Key items ------------------------------------------------------------
	"warden_sigil": {"name": "Warden's Sigil", "category": "key", "glyph": "&", "color": Color(0.8, 0.85, 0.6), "stack": 1, "value": 0,
		"desc": "Taken from the Warden of the Silent Crypt. One of three seals."},
	"frost_crown": {"name": "Frost Crown", "category": "key", "glyph": "&", "color": Color(0.6, 0.9, 1.0), "stack": 1, "value": 0,
		"desc": "The Mountain King's crown. One of three seals."},
	"dragonheart": {"name": "Dragonheart", "category": "key", "glyph": "&", "color": Color(1.0, 0.35, 0.15), "stack": 1, "value": 0,
		"desc": "Still beating. One of three seals."},
	"cerberus_fang": {"name": "Cerberus Fang", "category": "key", "glyph": "&", "color": Color(0.9, 0.3, 0.2), "stack": 1, "value": 0,
		"desc": "Opens the way to the Throne of Hades."},
	"crown_of_hades": {"name": "Crown of Hades", "category": "key", "glyph": "&", "color": Color(1.0, 0.85, 0.4), "stack": 1, "value": 0,
		"desc": "The underworld bows to you."},
}

const RANK_TITLES := ["Ashen", "Kindled", "Smoulder", "Ember", "Flame", "Blaze", "Pyre", "Inferno", "Phoenix", "Eternal Flame"]
const RANK_XP := [0, 100, 260, 500, 850, 1350, 2000, 2900, 4100, 5800]

## Blacksmith recipes: result -> {inputs: {id: count}, gold}
const RECIPES := {
	"pickaxe_iron": {"inputs": {"iron_ore": 5, "coal": 3}, "gold": 10},
	"sword_iron": {"inputs": {"iron_ore": 6, "coal": 3}, "gold": 15},
	"sword_ember": {"inputs": {"ember_crystal": 4, "iron_ore": 4, "gold_ore": 2}, "gold": 40},
	"pickaxe_obsidian": {"inputs": {"obsidian": 6, "gold_ore": 3, "ember_crystal": 2}, "gold": 60},
	"sword_dragonbone": {"inputs": {"hellstone": 4, "bone": 12, "obsidian": 4}, "gold": 120},
	"lantern": {"inputs": {"iron_ore": 1, "coal": 1}, "gold": 2},
	"torch": {"inputs": {"wood": 1, "coal": 1}, "gold": 0, "count": 4},
}

## Merchant stock: id -> price in gold
const SHOP := {"potion_health": 12, "potion_greater": 40, "bread": 3, "torch": 1, "lantern": 8}


static func exists(id: String) -> bool:
	return ITEMS.has(id)


static func info(id: String) -> Dictionary:
	return ITEMS.get(id, {})


static func display_name(id: String) -> String:
	return ITEMS.get(id, {}).get("name", id)


static func category(id: String) -> String:
	return ITEMS.get(id, {}).get("category", "")


static func max_stack(id: String) -> int:
	return int(ITEMS.get(id, {}).get("stack", 1))


static func glyph(id: String) -> String:
	return ITEMS.get(id, {}).get("glyph", "?")


static func color(id: String) -> Color:
	return ITEMS.get(id, {}).get("color", Color.WHITE)


static func rank_for_xp(xp: int) -> int:
	var r := 0
	for i in RANK_XP.size():
		if xp >= RANK_XP[i]:
			r = i
	return r


static func rank_progress(xp: int) -> float:
	var r := rank_for_xp(xp)
	if r >= RANK_XP.size() - 1:
		return 1.0
	return float(xp - RANK_XP[r]) / float(RANK_XP[r + 1] - RANK_XP[r])
