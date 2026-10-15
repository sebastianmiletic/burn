class_name ItemDB
extends RefCounted
## Every item in the game. Items are plain ids (Strings) plus counts; this
## table holds their behaviour. Hand-written items live in BASE; the metal
## ladder (tools, weapons and armour for every material tier) is generated
## from TIERS x KINDS in _static_init, so every tier is consistent.
##
## category: "tool", "weapon", "armor", "consumable", "material", "block",
##           "light", "station", "key", "currency"
## glyph: the character the UI draws while the item's 3D icon is not ready.
## rarity: 0 common .. 5 mythic (frame colour in the UI).
##
## Progression (pickaxe "mine_tier" vs Blocks tier):
##   1 wood       stone, coal, copper, tin, sandstone, limestone, bone
##   2 stone/copper   iron, granite, marble, slate, basalt, deepslate
##   3 bronze/iron    silver, gold, ruby, sapphire, amethyst, frost crystal
##   4 steel          mithril, ember crystal
##   5 mithril        adamantite, obsidian
##   6 adamantite     hellstone
##   7 infernal       everything, fastest

const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"]
const RARITY_COLORS := [Color(0.72, 0.7, 0.66), Color(0.45, 0.8, 0.38), Color(0.36, 0.62, 1.0),
		Color(0.72, 0.45, 1.0), Color(1.0, 0.62, 0.2), Color(1.0, 0.3, 0.22)]

## Label for a pickaxe mine tier (what the cheapest pick with that tier is made of).
const MINE_TIER_LABELS := ["hand", "wood", "stone", "iron", "steel", "mithril", "adamantite", "infernal"]

## Equipment slots (Inventory.equipment keys), in paper-doll order.
const EQUIP_SLOTS := ["head", "chest", "legs", "feet"]

## Material tiers of the ladder, weakest first.
const TIER_ORDER := ["wood", "stone", "copper", "bronze", "iron", "steel", "mithril", "adamantite", "infernal"]
const METALS := ["copper", "bronze", "iron", "steel", "mithril", "adamantite", "infernal"]

## power: sword damage at this tier; everything else scales from it.
## armor: total defence of a full set. material: what the gear is made of.
const TIERS := {
	"wood": {"label": "Wooden", "power": 6.0, "mine_tier": 1, "mine_speed": 0.7, "armor": 0.0, "rarity": 0, "value": 2,
		"color": Color(0.55, 0.38, 0.22), "material": "planks", "station": "workbench"},
	"stone": {"label": "Stone", "power": 8.0, "mine_tier": 2, "mine_speed": 1.0, "armor": 0.0, "rarity": 0, "value": 4,
		"color": Color(0.55, 0.54, 0.52), "material": "stone", "station": "workbench"},
	"copper": {"label": "Copper", "power": 11.0, "mine_tier": 2, "mine_speed": 1.25, "armor": 8.0, "rarity": 0, "value": 10,
		"color": Color(0.85, 0.5, 0.32), "material": "copper_ingot", "station": "anvil"},
	"bronze": {"label": "Bronze", "power": 13.5, "mine_tier": 3, "mine_speed": 1.5, "armor": 13.0, "rarity": 1, "value": 18,
		"color": Color(0.78, 0.58, 0.3), "material": "bronze_ingot", "station": "anvil"},
	"iron": {"label": "Iron", "power": 16.0, "mine_tier": 3, "mine_speed": 1.8, "armor": 18.0, "rarity": 1, "value": 30,
		"color": Color(0.7, 0.7, 0.7), "material": "iron_ingot", "station": "anvil"},
	"steel": {"label": "Steel", "power": 21.0, "mine_tier": 4, "mine_speed": 2.3, "armor": 26.0, "rarity": 2, "value": 55,
		"color": Color(0.66, 0.72, 0.8), "material": "steel_ingot", "station": "anvil"},
	"mithril": {"label": "Mithril", "power": 27.0, "mine_tier": 5, "mine_speed": 3.0, "armor": 36.0, "rarity": 3, "value": 110,
		"color": Color(0.7, 0.86, 1.0), "material": "mithril_ingot", "station": "anvil"},
	"adamantite": {"label": "Adamantite", "power": 34.0, "mine_tier": 6, "mine_speed": 3.8, "armor": 48.0, "rarity": 4, "value": 200,
		"color": Color(0.35, 0.78, 0.48), "material": "adamantite_ingot", "station": "anvil"},
	"infernal": {"label": "Infernal", "power": 43.0, "mine_tier": 7, "mine_speed": 5.0, "armor": 62.0, "rarity": 5, "value": 360,
		"color": Color(1.0, 0.42, 0.16), "material": "infernal_ingot", "station": "anvil", "burn": 5.0, "fire_resist": 0.1},
}

## Tool / weapon kinds. dmg/speed/reach are multipliers of the tier's power.
## Damage per second is roughly equal across kinds; the feel differs.
const KINDS := {
	"pickaxe": {"category": "tool", "name": "%s Pick-Axe", "glyph": "T", "dmg": 0.45, "speed": 1.0, "reach": 2.4, "cost": 3, "sticks": 2,
		"desc": "Pick on one side, axe on the other: digs rock and ore and fells trees. Harder ores and rare woods need a better one."},
	"axe": {"category": "tool", "name": "%s Axe", "glyph": "P", "dmg": 0.8, "speed": 0.95, "reach": 2.5, "cost": 3, "sticks": 2,
		"desc": "Fells trees and splits timber quickly. A fair weapon in a pinch."},
	"sword": {"category": "weapon", "name": "%s Sword", "glyph": "/", "dmg": 1.0, "speed": 1.1, "reach": 2.8, "cost": 2, "sticks": 1,
		"desc": "Balanced and quick. The soldier's choice."},
	"dagger": {"category": "weapon", "name": "%s Dagger", "glyph": "-", "dmg": 0.62, "speed": 1.75, "reach": 2.1, "cost": 1, "sticks": 1,
		"desc": "Light and vicious. Strikes fast, crits often.", "crit": 0.08},
	"spear": {"category": "weapon", "name": "%s Spear", "glyph": "|", "dmg": 0.92, "speed": 0.95, "reach": 3.7, "cost": 2, "sticks": 3,
		"desc": "Long reach. Keep monsters at the point."},
	"greataxe": {"category": "weapon", "name": "%s Greataxe", "glyph": "P", "dmg": 1.7, "speed": 0.62, "reach": 3.1, "cost": 4, "sticks": 2,
		"heavy": true, "desc": "Slow, two-handed, and devastating."},
	"warhammer": {"category": "weapon", "name": "%s Warhammer", "glyph": "T", "dmg": 1.9, "speed": 0.56, "reach": 2.9, "cost": 5, "sticks": 2,
		"heavy": true, "desc": "Crushes bone and plate alike. Staggers what it hits."},
}

## Which kinds exist per tier.
const TIER_KINDS := {
	"wood": ["pickaxe", "axe", "sword"],
	"stone": ["pickaxe", "axe", "spear", "warhammer"],
}

const ARMOR_PIECES := {
	"helmet": {"slot": "head", "share": 0.2, "cost": 5, "name": "%s Helm", "glyph": "^"},
	"chestplate": {"slot": "chest", "share": 0.4, "cost": 8, "name": "%s Cuirass", "glyph": "M"},
	"greaves": {"slot": "legs", "share": 0.25, "cost": 7, "name": "%s Greaves", "glyph": "H"},
	"boots": {"slot": "feet", "share": 0.15, "cost": 4, "name": "%s Sabatons", "glyph": "L"},
}

## Gems and crystals that can be set into gear (drag the gem onto the item).
## Weapon bonus / armour bonus.
const SOCKETS := {
	"ruby": {"weapon": {"burn": 5.0}, "armor": {"defense": 4.0, "fire_resist": 0.1}, "text": "Ruby: +5 burn / +4 defence, 10% fire resist"},
	"sapphire": {"weapon": {"damage_mult": 0.15}, "armor": {"defense": 7.0}, "text": "Sapphire: +15% damage / +7 defence"},
	"amethyst": {"weapon": {"crit": 0.1}, "armor": {"defense": 5.0, "regen": 0.5}, "text": "Amethyst: +10% crit / +5 defence"},
	"ember_crystal": {"weapon": {"burn": 3.0, "damage_mult": 0.05}, "armor": {"fire_resist": 0.2}, "text": "Ember: +3 burn, +5% damage / 20% fire resist"},
	"frost_shard": {"weapon": {"damage_mult": 0.1}, "armor": {"defense": 4.0, "fire_resist": 0.15}, "text": "Frost: +10% damage / +4 defence, 15% fire resist"},
}

## Burn value of furnace fuel, in fuel units (one unit smelts one cheap ore).
const FUEL := {"coal": 4, "charcoal": 4, "wood": 2, "planks": 1, "stick": 1}

## Crafting stations: kind -> display info. "" = by hand.
const STATIONS := {
	"": {"name": "By Hand", "verb": "Craft", "desc": "Simple things you can make anywhere."},
	"workbench": {"name": "Workbench", "verb": "Craft", "desc": "Saw, chisel and mallet: wooden and stone tools, building parts, other stations."},
	"furnace": {"name": "Furnace", "verb": "Smelt", "desc": "Ore into ingots, sand into glass, clay into brick. Burns fuel."},
	"anvil": {"name": "Anvil", "verb": "Forge", "desc": "Hammer ingots into tools, weapons and armour."},
	"alchemy": {"name": "Alchemy Table", "verb": "Brew", "desc": "Potions and elixirs from herbs, gems and glass."},
}

const BASE := {
	"hiking_boots": {"name": "Ironspike Hiking Boots", "category": "armor", "kind": "boots", "slot": "feet", "glyph": "L", "color": Color(0.48, 0.36, 0.23), "stack": 1, "value": 35, "defense": 3.0, "rarity": 1, "desc": "Equip to climb steep mountain steps. Iron crampons improve footing; sheer cliffs still require another route."},
	"ironwood": {"name": "Ironwood", "category": "material", "glyph": "=", "color": Color(0.35, 0.3, 0.22), "stack": 99, "value": 4, "rarity": 2, "desc": "Dense old-growth timber. Requires an iron axe or better."},
	"emberwood": {"name": "Emberwood", "category": "material", "glyph": "=", "color": Color(0.7, 0.28, 0.12), "stack": 99, "value": 6, "rarity": 3, "desc": "Heat-hardened timber. Requires a steel axe or better."},
	"ryftwood": {"name": "Ryftwood", "category": "material", "glyph": "=", "color": Color(0.55, 0.4, 0.8), "stack": 99, "value": 9, "rarity": 4, "desc": "Timber from the floating isles. Requires a mithril axe or better."},
	"sword_gatebreaker": {"name": "Gatebreaker", "category": "weapon", "kind": "sword", "glyph": "/", "color": Color(0.8, 0.42, 0.22), "damage": 62.0, "speed": 0.85, "reach": 3.3, "burn": 8.0, "stack": 1, "value": 0, "rarity": 4, "tier": "infernal", "heavy": true, "desc": "Hades' one-time reward. Powerful, heavy and bound: merchants will not buy it."},
	# Legacy and unique gear ---------------------------------------------------
	"sword_rusty": {"name": "Rusty Sword", "category": "weapon", "kind": "sword", "glyph": "/", "color": Color(0.62, 0.45, 0.35),
		"damage": 9.0, "speed": 1.0, "reach": 2.6, "stack": 1, "value": 5, "rarity": 0, "tier": "stone",
		"desc": "Better than bare hands. Barely."},
	"sword_ember": {"name": "Emberbrand", "category": "weapon", "kind": "sword", "glyph": "/", "color": Color(1.0, 0.5, 0.2),
		"damage": 26.0, "speed": 1.15, "reach": 3.0, "stack": 1, "value": 220, "burn": 6.0, "rarity": 3, "tier": "steel",
		"desc": "Ember crystal set in steel. Sets foes alight."},
	"sword_dragonbone": {"name": "Dragonbone Greatsword", "category": "weapon", "kind": "sword", "glyph": "/", "color": Color(0.95, 0.9, 0.75),
		"damage": 40.0, "speed": 0.9, "reach": 3.4, "stack": 1, "value": 520, "burn": 10.0, "rarity": 4, "tier": "adamantite", "heavy": true,
		"desc": "Carved from Ashvane's spine. Heavy, cruel, glorious."},
	"pickaxe_obsidian": {"name": "Obsidian Pick-Axe", "category": "tool", "kind": "pickaxe", "glyph": "T", "color": Color(0.5, 0.3, 0.7),
		"mine_tier": 5, "mine_speed": 2.6, "damage": 9.0, "speed": 1.0, "reach": 2.4, "stack": 1, "value": 180, "rarity": 3, "tier": "mithril",
		"desc": "Black glass edge, gold binding. Cuts obsidian and adamantite."},
	# Consumables --------------------------------------------------------------
	"potion_health": {"name": "Health Potion", "category": "consumable", "glyph": "!", "color": Color(0.9, 0.2, 0.2),
		"heal": 45.0, "stack": 10, "value": 12, "rarity": 0, "desc": "Emberleaf tincture. Restores 45 health."},
	"potion_greater": {"name": "Greater Potion", "category": "consumable", "glyph": "!", "color": Color(1.0, 0.45, 0.3),
		"heal": 120.0, "stack": 10, "value": 40, "rarity": 1, "desc": "Ruby-red and warm. Restores 120 health."},
	"potion_phoenix": {"name": "Phoenix Elixir", "category": "consumable", "glyph": "!", "color": Color(1.0, 0.72, 0.25),
		"heal": 260.0, "stack": 10, "value": 110, "rarity": 3, "desc": "Liquid fire that mends flesh. Restores 260 health."},
	"potion_ironskin": {"name": "Ironskin Draught", "category": "consumable", "glyph": "!", "color": Color(0.45, 0.6, 0.95),
		"buff": "ironskin", "buff_time": 90.0, "stack": 10, "value": 45, "rarity": 2, "desc": "Your skin hardens like plate. +30 defence for 90 s."},
	"potion_might": {"name": "Draught of Might", "category": "consumable", "glyph": "!", "color": Color(0.7, 0.3, 0.9),
		"buff": "might", "buff_time": 90.0, "stack": 10, "value": 45, "rarity": 2, "desc": "Strength floods your arms. +25% damage for 90 s."},
	"bread": {"name": "Hearth Bread", "category": "consumable", "glyph": "o", "color": Color(0.8, 0.6, 0.35),
		"heal": 15.0, "stack": 20, "value": 3, "rarity": 0, "food": true, "desc": "Warm and filling. Restores 15 health."},
	"apple": {"name": "Red Apple", "category": "consumable", "glyph": "o", "color": Color(0.8, 0.15, 0.12),
		"heal": 8.0, "stack": 20, "value": 2, "rarity": 0, "food": true, "desc": "Crisp and sweet. Restores 8 health."},
	"raw_meat": {"name": "Raw Meat", "category": "consumable", "glyph": "o", "color": Color(0.75, 0.3, 0.3),
		"heal": 4.0, "stack": 20, "value": 2, "rarity": 0, "food": true, "desc": "Cook it at a furnace first."},
	"cooked_meat": {"name": "Roast Meat", "category": "consumable", "glyph": "o", "color": Color(0.6, 0.35, 0.18),
		"heal": 30.0, "stack": 20, "value": 6, "rarity": 0, "food": true, "desc": "Charred, juicy, glorious. Restores 30 health."},
	# Light --------------------------------------------------------------------
	"torch": {"name": "Torch", "category": "light", "glyph": "i", "color": Color(1.0, 0.7, 0.3),
		"place_block": 29, "stack": 64, "value": 1, "rarity": 0, "desc": "Hold to light your way. Right-click to place."},
	"lantern": {"name": "Lantern", "category": "light", "glyph": "%", "color": Color(1.0, 0.75, 0.4),
		"place_block": 40, "stack": 16, "value": 8, "rarity": 1, "desc": "A brighter, steadier light. Place it."},
	# Stations -----------------------------------------------------------------
	"workbench": {"name": "Workbench", "category": "station", "glyph": "n", "color": Color(0.62, 0.44, 0.26), "place_station": "workbench",
		"stack": 4, "value": 6, "rarity": 0, "desc": "Place it to craft wooden and stone tools, building parts and other stations."},
	"furnace": {"name": "Furnace", "category": "station", "glyph": "n", "color": Color(0.6, 0.5, 0.45), "place_station": "furnace",
		"stack": 4, "value": 12, "rarity": 0, "desc": "Place it to smelt ore into ingots. Feed it coal or wood."},
	"anvil": {"name": "Anvil", "category": "station", "glyph": "n", "color": Color(0.45, 0.45, 0.48), "place_station": "anvil",
		"stack": 4, "value": 30, "rarity": 1, "desc": "Place it to forge metal tools, weapons and armour."},
	"alchemy_table": {"name": "Alchemy Table", "category": "station", "glyph": "n", "color": Color(0.55, 0.4, 0.7), "place_station": "alchemy",
		"stack": 4, "value": 30, "rarity": 1, "desc": "Place it to brew potions and elixirs."},
	# Blocks -------------------------------------------------------------------
	"stone": {"name": "Stone", "category": "block", "glyph": "#", "color": Color(0.5, 0.49, 0.48), "place_block": 1, "stack": 99, "value": 0},
	"cobble": {"name": "Cobblestone", "category": "block", "glyph": "#", "color": Color(0.45, 0.44, 0.43), "place_block": 10, "stack": 99, "value": 0},
	"dirt": {"name": "Dirt", "category": "block", "glyph": "#", "color": Color(0.45, 0.32, 0.2), "place_block": 2, "stack": 99, "value": 0},
	"sand": {"name": "Sand", "category": "block", "glyph": "#", "color": Color(0.8, 0.7, 0.5), "place_block": 4, "stack": 99, "value": 0},
	"snow": {"name": "Snow", "category": "block", "glyph": "#", "color": Color(0.9, 0.9, 0.92), "place_block": 5, "stack": 99, "value": 0},
	"gravel": {"name": "Gravel", "category": "block", "glyph": "#", "color": Color(0.5, 0.48, 0.45), "place_block": 12, "stack": 99, "value": 0},
	"wood": {"name": "Wood", "category": "block", "glyph": "=", "color": Color(0.5, 0.35, 0.2), "place_block": 7, "stack": 99, "value": 1,
		"desc": "A length of trunk. Split it into planks by hand."},
	"planks": {"name": "Planks", "category": "block", "glyph": "=", "color": Color(0.65, 0.46, 0.27), "place_block": 9, "stack": 99, "value": 1},
	"brick": {"name": "Castle Brick", "category": "block", "glyph": "#", "color": Color(0.55, 0.32, 0.25), "place_block": 11, "stack": 99, "value": 1},
	"thatch": {"name": "Thatch", "category": "block", "glyph": "~", "color": Color(0.7, 0.58, 0.3), "place_block": 25, "stack": 99, "value": 0},
	"basalt": {"name": "Basalt", "category": "block", "glyph": "#", "color": Color(0.3, 0.27, 0.27), "place_block": 21, "stack": 99, "value": 0},
	"ash": {"name": "Ash", "category": "block", "glyph": ".", "color": Color(0.4, 0.37, 0.36), "place_block": 22, "stack": 99, "value": 0},
	"bone": {"name": "Bone", "category": "block", "glyph": "-", "color": Color(0.85, 0.82, 0.72), "place_block": 23, "stack": 99, "value": 2},
	"soul_sand": {"name": "Soul Sand", "category": "block", "glyph": "#", "color": Color(0.4, 0.3, 0.25), "place_block": 39, "stack": 99, "value": 0},
	"obsidian": {"name": "Obsidian", "category": "block", "glyph": "#", "color": Color(0.3, 0.15, 0.4), "place_block": 17, "stack": 99, "value": 8, "rarity": 2},
	"granite": {"name": "Granite", "category": "block", "glyph": "#", "color": Color(0.6, 0.48, 0.45), "place_block": 45, "stack": 99, "value": 1},
	"sandstone": {"name": "Sandstone", "category": "block", "glyph": "#", "color": Color(0.8, 0.66, 0.46), "place_block": 46, "stack": 99, "value": 0},
	"marble": {"name": "Marble", "category": "block", "glyph": "#", "color": Color(0.9, 0.89, 0.86), "place_block": 47, "stack": 99, "value": 2},
	"slate": {"name": "Slate", "category": "block", "glyph": "#", "color": Color(0.32, 0.35, 0.4), "place_block": 48, "stack": 99, "value": 1},
	"clay": {"name": "Clay", "category": "block", "glyph": "#", "color": Color(0.7, 0.5, 0.4), "place_block": 49, "stack": 99, "value": 1,
		"desc": "Fire it in a furnace to make brick."},
	"limestone": {"name": "Limestone", "category": "block", "glyph": "#", "color": Color(0.78, 0.75, 0.66), "place_block": 50, "stack": 99, "value": 1},
	# Raw materials ------------------------------------------------------------
	"stick": {"name": "Stick", "category": "material", "glyph": "/", "color": Color(0.55, 0.4, 0.24), "stack": 99, "value": 0,
		"desc": "Handles, hafts and torches."},
	"coal": {"name": "Coal", "category": "material", "glyph": "*", "color": Color(0.25, 0.25, 0.25), "stack": 99, "value": 2,
		"desc": "Fuel for the furnace (4 units). Turns iron into steel."},
	"charcoal": {"name": "Charcoal", "category": "material", "glyph": "*", "color": Color(0.2, 0.17, 0.15), "stack": 99, "value": 2,
		"desc": "Wood burned slowly into fuel (4 units)."},
	"copper_ore": {"name": "Copper Ore", "category": "material", "glyph": "*", "color": Color(0.75, 0.45, 0.3), "stack": 99, "value": 2,
		"desc": "Green-veined rock from near the surface. Smelt it."},
	"tin_ore": {"name": "Tin Ore", "category": "material", "glyph": "*", "color": Color(0.68, 0.68, 0.66), "stack": 99, "value": 2,
		"desc": "Alloy it with copper to make bronze."},
	"iron_ore": {"name": "Iron Ore", "category": "material", "glyph": "*", "color": Color(0.75, 0.55, 0.45), "stack": 99, "value": 5,
		"desc": "Rust-red rock. Smelt it into iron."},
	"silver_ore": {"name": "Silver Ore", "category": "material", "glyph": "*", "color": Color(0.82, 0.84, 0.88), "stack": 99, "value": 9, "rarity": 1,
		"desc": "Bright flecks in dark stone, below the iron."},
	"gold_ore": {"name": "Gold Ore", "category": "material", "glyph": "*", "color": Color(1.0, 0.82, 0.35), "stack": 99, "value": 15, "rarity": 1,
		"desc": "Merchants pay well for this."},
	"mithril_ore": {"name": "Mithril Ore", "category": "material", "glyph": "*", "color": Color(0.65, 0.85, 1.0), "stack": 99, "value": 30, "rarity": 2,
		"desc": "Pale blue, lighter than it looks. Needs a steel pick."},
	"adamantite_ore": {"name": "Adamantite Ore", "category": "material", "glyph": "*", "color": Color(0.35, 0.8, 0.5), "stack": 99, "value": 55, "rarity": 3,
		"desc": "From the deep near the lava. Only mithril bites it."},
	"ember_crystal": {"name": "Ember Crystal", "category": "material", "glyph": "*", "color": Color(1.0, 0.5, 0.2), "stack": 99, "value": 30, "rarity": 2,
		"desc": "Warm to the touch. Found deep below. Can be set into gear."},
	"frost_shard": {"name": "Frost Shard", "category": "material", "glyph": "*", "color": Color(0.6, 0.9, 1.0), "stack": 99, "value": 20, "rarity": 2,
		"desc": "Never melts. Can be set into gear."},
	"hellstone": {"name": "Hellstone", "category": "material", "glyph": "*", "color": Color(0.9, 0.2, 0.1), "stack": 99, "value": 60, "rarity": 3,
		"desc": "Mined in the underworld. Burns without fire."},
	"ruby": {"name": "Ruby", "category": "gem", "glyph": "◆", "color": Color(0.95, 0.15, 0.22), "stack": 99, "value": 40, "rarity": 2,
		"desc": "Deep red. Set it into a weapon for fire, or armour for warmth."},
	"sapphire": {"name": "Sapphire", "category": "gem", "glyph": "◆", "color": Color(0.2, 0.4, 1.0), "stack": 99, "value": 40, "rarity": 2,
		"desc": "Cold blue fire. Sharpens blades, hardens plate."},
	"amethyst": {"name": "Amethyst", "category": "gem", "glyph": "◆", "color": Color(0.7, 0.4, 1.0), "stack": 99, "value": 32, "rarity": 2,
		"desc": "Violet crystal. Finds the gaps in armour."},
	"emberleaf": {"name": "Emberleaf", "category": "material", "glyph": "\"", "color": Color(0.85, 0.35, 0.15), "stack": 99, "value": 2,
		"desc": "A red-veined herb that grows in the ash. The root of every healing draught."},
	"glass_vial": {"name": "Glass Vial", "category": "material", "glyph": "u", "color": Color(0.75, 0.88, 0.9), "stack": 99, "value": 2,
		"desc": "Blown from sand in a furnace. Holds potions."},
	# Ingots -------------------------------------------------------------------
	"copper_ingot": {"name": "Copper Ingot", "category": "material", "glyph": "=", "color": Color(0.85, 0.5, 0.32), "stack": 99, "value": 4, "rarity": 0, "tier": "copper"},
	"tin_ingot": {"name": "Tin Ingot", "category": "material", "glyph": "=", "color": Color(0.76, 0.77, 0.76), "stack": 99, "value": 4, "rarity": 0},
	"bronze_ingot": {"name": "Bronze Ingot", "category": "material", "glyph": "=", "color": Color(0.78, 0.58, 0.3), "stack": 99, "value": 7, "rarity": 0, "tier": "bronze"},
	"iron_ingot": {"name": "Iron Ingot", "category": "material", "glyph": "=", "color": Color(0.7, 0.7, 0.7), "stack": 99, "value": 10, "rarity": 1, "tier": "iron"},
	"steel_ingot": {"name": "Steel Ingot", "category": "material", "glyph": "=", "color": Color(0.66, 0.72, 0.8), "stack": 99, "value": 18, "rarity": 1, "tier": "steel"},
	"silver_ingot": {"name": "Silver Ingot", "category": "material", "glyph": "=", "color": Color(0.9, 0.92, 0.95), "stack": 99, "value": 20, "rarity": 1},
	"gold_ingot": {"name": "Gold Ingot", "category": "material", "glyph": "=", "color": Color(1.0, 0.8, 0.35), "stack": 99, "value": 34, "rarity": 2},
	"mithril_ingot": {"name": "Mithril Ingot", "category": "material", "glyph": "=", "color": Color(0.7, 0.86, 1.0), "stack": 99, "value": 70, "rarity": 2, "tier": "mithril"},
	"adamantite_ingot": {"name": "Adamantite Ingot", "category": "material", "glyph": "=", "color": Color(0.35, 0.78, 0.48), "stack": 99, "value": 120, "rarity": 3, "tier": "adamantite"},
	"infernal_ingot": {"name": "Infernal Ingot", "category": "material", "glyph": "=", "color": Color(1.0, 0.42, 0.16), "stack": 99, "value": 220, "rarity": 4, "tier": "infernal"},
	# Key items ----------------------------------------------------------------
	"warden_sigil": {"name": "Warden's Sigil", "category": "key", "glyph": "&", "color": Color(0.8, 0.85, 0.6), "stack": 1, "value": 0, "rarity": 4,
		"desc": "Taken from the Warden of the Silent Crypt. One of three seals."},
	"frost_crown": {"name": "Frost Crown", "category": "key", "glyph": "&", "color": Color(0.6, 0.9, 1.0), "stack": 1, "value": 0, "rarity": 4,
		"desc": "The Mountain King's crown. One of three seals."},
	"dragonheart": {"name": "Dragonheart", "category": "key", "glyph": "&", "color": Color(1.0, 0.35, 0.15), "stack": 1, "value": 0, "rarity": 4,
		"desc": "Still beating. One of three seals."},
	"cerberus_fang": {"name": "Cerberus Fang", "category": "key", "glyph": "&", "color": Color(0.9, 0.3, 0.2), "stack": 1, "value": 0, "rarity": 5,
		"desc": "Opens the way to the Throne of Hades."},
	"crown_of_hades": {"name": "Crown of Hades", "category": "key", "glyph": "&", "color": Color(1.0, 0.85, 0.4), "stack": 1, "value": 0, "rarity": 5,
		"desc": "The underworld bows to you."},
}

## Hand-written recipes. The recipe id is always the id of the item it makes
## (Player.craft gives `recipe_id`). Generated gear recipes are added in _static_init.
##   inputs: {item: count}, count: made per craft, station: "" | workbench | furnace | anvil | alchemy,
##   fuel: furnace fuel units per craft, time: seconds per craft (furnace / alchemy), gold: optional fee.
const BASE_RECIPES := {
	"hiking_boots": {"inputs": {"iron_ingot": 4, "wood": 2}, "station": "anvil", "group": "armor"},
	# By hand
	"planks": {"inputs": {"wood": 1}, "count": 4, "station": "", "group": "basics"},
	"ironwood_coal": {"result": "charcoal", "inputs": {"ironwood": 1}, "count": 4, "station": "furnace", "group": "smelting"},
	"emberwood_crystal": {"result": "ember_crystal", "inputs": {"emberwood": 4, "coal": 2}, "station": "furnace", "group": "smelting"},
	"ryftwood_amethyst": {"result": "amethyst", "inputs": {"ryftwood": 3, "silver_ingot": 1}, "station": "alchemy", "group": "basics"},
	"stick": {"inputs": {"planks": 1}, "count": 4, "station": "", "group": "basics"},
	"torch": {"inputs": {"stick": 1, "coal": 1}, "count": 4, "station": "", "group": "basics"},
	"workbench": {"inputs": {"wood": 2, "planks": 4}, "station": "", "group": "stations"},
	# Workbench
	"furnace": {"inputs": {"stone": 12, "coal": 2}, "station": "workbench", "group": "stations"},
	"anvil": {"inputs": {"copper_ingot": 4, "stone": 8}, "station": "workbench", "group": "stations"},
	"alchemy_table": {"inputs": {"planks": 6, "glass_vial": 3, "copper_ingot": 2}, "station": "workbench", "group": "stations"},
	"cobble": {"inputs": {"stone": 2}, "count": 2, "station": "workbench", "group": "building"},
	"thatch": {"inputs": {"stick": 3}, "count": 2, "station": "workbench", "group": "building"},
	# Furnace (smelting)
	"copper_ingot": {"inputs": {"copper_ore": 1}, "fuel": 1, "time": 1.6, "station": "furnace", "group": "smelting"},
	"tin_ingot": {"inputs": {"tin_ore": 1}, "fuel": 1, "time": 1.6, "station": "furnace", "group": "smelting"},
	"bronze_ingot": {"inputs": {"copper_ingot": 3, "tin_ingot": 1}, "count": 4, "fuel": 2, "time": 2.4, "station": "furnace", "group": "smelting"},
	"iron_ingot": {"inputs": {"iron_ore": 1}, "fuel": 2, "time": 2.2, "station": "furnace", "group": "smelting"},
	"steel_ingot": {"inputs": {"iron_ingot": 1, "coal": 2}, "fuel": 2, "time": 3.0, "station": "furnace", "group": "smelting"},
	"silver_ingot": {"inputs": {"silver_ore": 1}, "fuel": 2, "time": 2.2, "station": "furnace", "group": "smelting"},
	"gold_ingot": {"inputs": {"gold_ore": 1}, "fuel": 2, "time": 2.2, "station": "furnace", "group": "smelting"},
	"mithril_ingot": {"inputs": {"mithril_ore": 2}, "fuel": 3, "time": 3.6, "station": "furnace", "group": "smelting"},
	"adamantite_ingot": {"inputs": {"adamantite_ore": 2}, "fuel": 4, "time": 4.5, "station": "furnace", "group": "smelting"},
	"infernal_ingot": {"inputs": {"hellstone": 2, "adamantite_ingot": 1, "ember_crystal": 1}, "fuel": 4, "time": 5.5, "station": "furnace", "group": "smelting"},
	"glass_vial": {"inputs": {"sand": 2}, "fuel": 1, "time": 1.4, "station": "furnace", "group": "smelting"},
	"brick": {"inputs": {"clay": 1}, "count": 2, "fuel": 1, "time": 1.2, "station": "furnace", "group": "building"},
	"charcoal": {"inputs": {"wood": 2}, "time": 2.0, "station": "furnace", "group": "smelting"},
	"cooked_meat": {"inputs": {"raw_meat": 1}, "fuel": 1, "time": 2.0, "station": "furnace", "group": "food"},
	# Anvil (beyond the generated ladder)
	"lantern": {"inputs": {"iron_ingot": 1, "glass_vial": 1, "torch": 1}, "station": "anvil", "group": "basics"},
	"sword_ember": {"inputs": {"steel_ingot": 3, "ember_crystal": 4, "gold_ingot": 1}, "station": "anvil", "group": "weapons"},
	"pickaxe_obsidian": {"inputs": {"obsidian": 6, "gold_ingot": 3, "ember_crystal": 2, "stick": 2}, "station": "anvil", "group": "tools"},
	"sword_dragonbone": {"inputs": {"bone": 12, "hellstone": 4, "obsidian": 4, "adamantite_ingot": 2}, "station": "anvil", "group": "weapons"},
	# Alchemy
	"potion_health": {"inputs": {"glass_vial": 1, "emberleaf": 2}, "time": 1.5, "station": "alchemy", "group": "potions"},
	"potion_greater": {"inputs": {"glass_vial": 1, "emberleaf": 2, "ruby": 1}, "time": 2.0, "station": "alchemy", "group": "potions"},
	"potion_phoenix": {"inputs": {"glass_vial": 1, "emberleaf": 3, "ember_crystal": 1, "amethyst": 1}, "time": 3.0, "station": "alchemy", "group": "potions"},
	"potion_ironskin": {"inputs": {"glass_vial": 1, "emberleaf": 1, "sapphire": 1, "iron_ingot": 1}, "time": 2.5, "station": "alchemy", "group": "potions"},
	"potion_might": {"inputs": {"glass_vial": 1, "emberleaf": 1, "amethyst": 1, "bone": 2}, "time": 2.5, "station": "alchemy", "group": "potions"},
}

const RANK_TITLES := ["Ashen", "Kindled", "Smoulder", "Ember", "Flame", "Blaze", "Pyre", "Inferno", "Phoenix", "Eternal Flame"]
const RANK_XP := [0, 100, 260, 500, 850, 1350, 2000, 2900, 4100, 5800]

## Merchant stock: id -> price in gold
const SHOP := {"potion_health": 12, "potion_greater": 40, "bread": 3, "apple": 2, "emberleaf": 3, "glass_vial": 4,
		"torch": 1, "lantern": 10, "coal": 3, "stick": 1}

## Every item (BASE + generated). Same shape as BASE.
static var ITEMS := {}
## Every recipe (BASE_RECIPES + generated gear).
static var RECIPES := {}


static func _static_init() -> void:
	for id: String in BASE:
		ITEMS[id] = BASE[id]
	for tier: String in TIER_ORDER:
		var t: Dictionary = TIERS[tier]
		var kinds: Array = TIER_KINDS.get(tier, KINDS.keys())
		for k: String in kinds:
			_add_gear(k + "_" + tier, k, tier)
		if tier in METALS:
			for piece: String in ARMOR_PIECES:
				_add_armor(piece + "_" + tier, piece, tier)
	for rid: String in BASE_RECIPES:
		RECIPES[rid] = BASE_RECIPES[rid]


static func _add_gear(id: String, kind: String, tier: String) -> void:
	var t: Dictionary = TIERS[tier]
	var k: Dictionary = KINDS[kind]
	var power := float(t["power"])
	var item := {
		"name": String(k["name"]) % t["label"], "category": k["category"], "kind": kind, "tier": tier,
		"glyph": k["glyph"], "color": t["color"], "stack": 1, "rarity": t["rarity"],
		"damage": snappedf(power * float(k["dmg"]), 0.5), "speed": k["speed"], "reach": k["reach"],
		"value": int(t["value"]) * (int(k["cost"]) + 1), "desc": k["desc"],
	}
	if kind == "pickaxe":
		item["mine_tier"] = t["mine_tier"]
		item["mine_speed"] = t["mine_speed"]
	elif kind == "axe":
		item["chop_speed"] = float(t["mine_speed"]) * 1.4 + 0.4
		item["mine_tier"] = 0
		item["mine_speed"] = item["chop_speed"]
	if k.get("heavy", false):
		item["heavy"] = true
	if k.has("crit"):
		item["crit"] = k["crit"]
	if t.has("burn") and k["category"] == "weapon":
		item["burn"] = t["burn"]
	# Keep the original Iron Sword / pickaxes exactly as before where tests and saves expect them.
	if id == "sword_iron":
		item["damage"] = 16.0
	if id == "pickaxe_stone":
		item["damage"] = 4.0
	ITEMS[id] = item
	var inputs := {String(t["material"]): int(k["cost"])}
	if int(k["sticks"]) > 0:
		inputs["stick"] = int(k["sticks"])
	if tier == "mithril":
		inputs["silver_ingot"] = 1
	elif tier == "adamantite":
		inputs["gold_ingot"] = 1
	elif tier == "infernal":
		inputs["ember_crystal"] = 1
	RECIPES[id] = {"inputs": inputs, "station": t["station"], "group": "tools" if k["category"] == "tool" else "weapons", "generated": true}


static func _add_armor(id: String, piece: String, tier: String) -> void:
	var t: Dictionary = TIERS[tier]
	var a: Dictionary = ARMOR_PIECES[piece]
	var item := {
		"name": String(a["name"]) % t["label"], "category": "armor", "kind": piece, "tier": tier, "slot": a["slot"],
		"glyph": a["glyph"], "color": t["color"], "stack": 1, "rarity": t["rarity"],
		"defense": snappedf(float(t["armor"]) * float(a["share"]), 0.1),
		"value": int(t["value"]) * (int(a["cost"]) + 1),
		"desc": "Part of a %s set. Wear it in the %s slot." % [String(t["label"]).to_lower(), a["slot"]],
	}
	if t.has("fire_resist"):
		item["fire_resist"] = t["fire_resist"]
	ITEMS[id] = item
	var inputs := {String(t["material"]): int(a["cost"])}
	if tier == "mithril":
		inputs["silver_ingot"] = 1
	elif tier == "adamantite":
		inputs["gold_ingot"] = 1
	elif tier == "infernal":
		inputs["ember_crystal"] = 1
	RECIPES[id] = {"inputs": inputs, "station": "anvil", "group": "armor", "generated": true}


# --- Lookups -----------------------------------------------------------------------

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


static func rarity(id: String) -> int:
	return clampi(int(ITEMS.get(id, {}).get("rarity", 0)), 0, RARITY_COLORS.size() - 1)


static func rarity_color(id: String) -> Color:
	return RARITY_COLORS[rarity(id)]


static func tier_of(id: String) -> String:
	return String(ITEMS.get(id, {}).get("tier", ""))


static func kind_of(id: String) -> String:
	return String(ITEMS.get(id, {}).get("kind", ""))


static func is_gear(id: String) -> bool:
	var c := category(id)
	return c == "weapon" or c == "tool" or c == "armor"


static func equip_slot(id: String) -> String:
	return String(ITEMS.get(id, {}).get("slot", ""))


## Human-readable type line ("Two-handed weapon", "Pickaxe", "Ore"...).
static func type_label(id: String) -> String:
	var inf := info(id)
	match String(inf.get("category", "")):
		"weapon":
			return "Heavy weapon" if inf.get("heavy", false) else String(inf.get("kind", "weapon")).capitalize()
		"tool":
			return String(inf.get("kind", "tool")).capitalize()
		"armor":
			return "Armour · %s" % String(inf.get("slot", "")).capitalize()
		"consumable":
			return "Food" if inf.get("food", false) else "Potion"
		"material":
			if id.ends_with("_ingot"):
				return "Ingot"
			if id.ends_with("_ore") or id in ["hellstone", "coal"]:
				return "Ore"
			return "Material"
		"gem":
			return "Gem · socketable"
		"block":
			return "Building block"
		"light":
			return "Light source"
		"station":
			return "Crafting station"
		"key":
			return "Relic"
	return String(inf.get("category", "")).capitalize()


## Socket bonus of `gem` for an item of `item_category` ("weapon"/"tool" -> weapon, "armor").
static func socket_bonus(gem: String, item_category: String) -> Dictionary:
	if not SOCKETS.has(gem):
		return {}
	return SOCKETS[gem].get("armor" if item_category == "armor" else "weapon", {})


## "+5 burn, +5% damage" for a gem set into an item of `item_category`.
static func socket_text(gem: String, item_category: String) -> String:
	const LABELS := {"burn": "+%d burn", "damage_mult": "+%d%% damage", "crit": "+%d%% crit", "defense": "+%d defence",
		"fire_resist": "%d%% fire resist", "regen": "+%.1f regen"}
	var parts := PackedStringArray()
	var b := socket_bonus(gem, item_category)
	for k: String in b:
		var v := float(b[k])
		if k in ["damage_mult", "crit", "fire_resist"]:
			v *= 100.0
		parts.append(String(LABELS.get(k, k + " %s")) % v)
	return ", ".join(parts)


static func can_socket(gem: String, item_id: String) -> bool:
	return SOCKETS.has(gem) and is_gear(item_id)


# --- Mining ---------------------------------------------------------------------------

## Blocks an axe chops quickly.
static func is_wood_block(block: int) -> bool:
	return Blocks.is_trunk(block) or block in [Blocks.LOG, Blocks.PINE_LOG, Blocks.PLANKS, Blocks.CHEST, Blocks.THATCH]


## Seconds it takes `item_id` to break `block`, or -1.0 if it cannot.
## Pickaxes need mine_tier >= Blocks.tier(block); axes chop wood fast and
## only manage soft (tier 0) ground; anything else counts as bare hands.
static func mine_time(item_id: String, block: int) -> float:
	if not Blocks.is_breakable(block):
		return -1.0
	var h := Blocks.hardness(block)
	var need := Blocks.tier(block)
	var inf := info(item_id)
	var kind := String(inf.get("kind", ""))
	var speed := 0.35
	var tier := 0
	if kind == "pickaxe":
		# The pick-axe is a multitool: its axe bit chops as well as an axe.
		tier = int(inf.get("mine_tier", 1))
		speed = float(inf.get("mine_speed", 1.0))
		if is_wood_block(block):
			speed = speed * 1.4 + 0.4
	elif kind == "axe":
		tier = int(TIERS.get(String(inf.get("tier", "wood")), {}).get("mine_tier", 1)) if is_wood_block(block) else 0
		speed = float(inf.get("chop_speed", 1.0)) if is_wood_block(block) else float(inf.get("chop_speed", 1.0)) * 0.6
	elif inf.get("category", "") == "tool" and inf.has("mine_tier"):
		tier = int(inf["mine_tier"])
		speed = float(inf.get("mine_speed", 1.0))
	if need > tier:
		return -1.0
	return maxf(0.08, h / maxf(speed, 0.05))


static func can_mine(item_id: String, block: int) -> bool:
	return mine_time(item_id, block) >= 0.0


## Names of the ore blocks a pickaxe tier unlocks (for tooltips).
static func ores_for_tier(t: int) -> PackedStringArray:
	var out := PackedStringArray()
	for b: int in [Blocks.COAL_ORE, Blocks.COPPER_ORE, Blocks.TIN_ORE, Blocks.IRON_ORE, Blocks.SILVER_ORE, Blocks.GOLD_ORE,
			Blocks.RUBY_ORE, Blocks.SAPPHIRE_ORE, Blocks.AMETHYST, Blocks.CRYSTAL, Blocks.MITHRIL_ORE, Blocks.EMBER_ORE,
			Blocks.ADAMANTITE_ORE, Blocks.OBSIDIAN, Blocks.HELLSTONE]:
		if Blocks.tier(b) == t:
			out.append(Blocks.name_of(b).to_lower().replace(" ore", ""))
	return out


# --- Recipes ------------------------------------------------------------------------------

static func recipe(recipe_id: String) -> Dictionary:
	return RECIPES.get(recipe_id, {})


## The item a recipe makes (recipe ids are item ids; "result" overrides).
static func recipe_result(recipe_id: String) -> String:
	return String(RECIPES.get(recipe_id, {}).get("result", recipe_id))


static func recipe_station(recipe_id: String) -> String:
	return String(RECIPES.get(recipe_id, {}).get("station", ""))


## Recipe ids made at a station kind ("" = by hand), in ladder order.
static func recipes_for_station(kind: String) -> Array:
	var out: Array = []
	for rid: String in RECIPES:
		if String(RECIPES[rid].get("station", "")) == kind:
			out.append(rid)
	out.sort_custom(func(a: String, b: String) -> bool: return _recipe_sort_key(a) < _recipe_sort_key(b))
	return out


static func _recipe_sort_key(rid: String) -> String:
	const GROUPS := ["basics", "stations", "smelting", "food", "building", "tools", "weapons", "armor", "potions"]
	var r: Dictionary = RECIPES[rid]
	var g := GROUPS.find(String(r.get("group", "")))
	var tier := TIER_ORDER.find(tier_of(recipe_result(rid)))
	var kind_i := 0
	var k := kind_of(recipe_result(rid))
	if KINDS.has(k):
		kind_i = KINDS.keys().find(k)
	elif ARMOR_PIECES.has(k):
		kind_i = ARMOR_PIECES.keys().find(k)
	var order := maxi(tier, 0) if r.get("generated", false) else BASE_RECIPES.keys().find(rid)
	return "%02d|%03d|%02d|%s" % [maxi(g, 0), order, kind_i, rid]


## True when the station kinds within reach satisfy the recipe.
## "" recipes need nothing. The village smith ("smithy") counts as anvil + furnace + workbench.
static func station_available(recipe_id: String, nearby_station_kinds: Array) -> bool:
	var need := recipe_station(recipe_id)
	if need == "":
		return true
	if need in nearby_station_kinds:
		return true
	return "smithy" in nearby_station_kinds and need in ["anvil", "furnace", "workbench"]


## Missing inputs as {item: shortfall}; "fuel" for furnace fuel units, "gold" for a fee.
static func missing_for(recipe_id: String, inventory: Inventory, times := 1) -> Dictionary:
	var r := recipe(recipe_id)
	var miss := {}
	if r.is_empty():
		miss["?"] = 1
		return miss
	var inputs: Dictionary = r.get("inputs", {})
	for item: String in inputs:
		var need := int(inputs[item]) * times
		var have := inventory.count_of(item) if inventory != null else 0
		if have < need:
			miss[item] = need - have
	var fuel := int(r.get("fuel", 0)) * times
	if fuel > 0:
		# Fuel items that are also ingredients are not double-counted: reserve them first.
		var units := inventory.fuel_units(inputs, times) if inventory != null else 0
		if units < fuel:
			miss["fuel"] = fuel - units
	var gold := int(r.get("gold", 0)) * times
	if gold > 0 and (inventory == null or inventory.gold < gold):
		miss["gold"] = gold - (inventory.gold if inventory != null else 0)
	return miss


## Contract helper: can `recipe_id` be crafted now with this inventory next to these stations?
static func can_craft(recipe_id: String, inventory: Inventory, nearby_station_kinds: Array) -> bool:
	if not RECIPES.has(recipe_id) or inventory == null:
		return false
	return station_available(recipe_id, nearby_station_kinds) and missing_for(recipe_id, inventory).is_empty()


## Alias kept for the wording in docs/REALISM_CONTRACTS.md.
static func can_craft_at(recipe_id: String, inventory: Inventory, nearby_station_kinds: Array) -> bool:
	return can_craft(recipe_id, inventory, nearby_station_kinds)


static func station_name(kind: String) -> String:
	if kind == "smithy":
		return "The Smithy"
	return String(STATIONS.get(kind, {}).get("name", kind.capitalize()))


static func fuel_value(id: String) -> int:
	return int(FUEL.get(id, 0))


## Consumables that heal, strongest first (for the potion hotkey).
static func heal_items_by_strength() -> Array:
	var out: Array = []
	for id: String in ITEMS:
		if ITEMS[id].has("heal") and not ITEMS[id].get("food", false):
			out.append(id)
	for id: String in ITEMS:
		if ITEMS[id].has("heal") and ITEMS[id].get("food", false):
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool:
		var fa := 1 if ITEMS[a].get("food", false) else 0
		var fb := 1 if ITEMS[b].get("food", false) else 0
		if fa != fb:
			return fa < fb
		return float(ITEMS[a]["heal"]) > float(ITEMS[b]["heal"]))
	return out


# --- Ranks ------------------------------------------------------------------------------

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
