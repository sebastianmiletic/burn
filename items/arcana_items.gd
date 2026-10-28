class_name ArcanaItems
extends RefCounted
## Items of the role/spell/brewing systems, merged into ItemDB by
## ItemDB._static_init (never overwriting an id another system defined, so the
## dragon and Everbloom ingredients below are placeholders only until the
## biome/cave branches bring the real ones).
##
## Bows ("kind": "bow"): hold attack to draw (draw seconds), release to loose
##   an arrow (uses arrows from the bag). "arrow_speed" m/s at full draw.
## Staffs ("kind": "staff"): attack fires an arcane bolt for "mana_cost" mana.
## "rank_req": the role rank the weapon asks for (Roles.rank_ok); below it the
##   weapon refuses to answer you.
## Books ("book": knowledge id): use (right click) to read; what they teach goes
##   into the Codex (K) for good.

const MODEL := "res://models/arcana_models.gd"

const ITEMS := {
	# --- Bows -------------------------------------------------------------------------
	"bow_hunting": {"name": "Hunting Bow", "category": "weapon", "kind": "bow", "glyph": ")", "color": Color(0.55, 0.38, 0.22),
		"damage": 11.0, "draw": 0.85, "arrow_speed": 40.0, "speed": 1.0, "reach": 2.2, "stack": 1, "value": 14, "rarity": 0, "tier": "wood",
		"rank_req": 0, "model_script": MODEL, "desc": "Ash and sinew. Hold to draw, release to loose. Needs arrows."},
	"bow_yew": {"name": "Yew Bow", "category": "weapon", "kind": "bow", "glyph": ")", "color": Color(0.42, 0.3, 0.18),
		"damage": 17.0, "draw": 0.95, "arrow_speed": 44.0, "speed": 1.0, "reach": 2.2, "stack": 1, "value": 60, "rarity": 1, "tier": "iron",
		"rank_req": 2, "model_script": MODEL, "desc": "Ironwood heart, silk string. Asks for an Archer of rank 2."},
	"bow_longbow": {"name": "Warden Longbow", "category": "weapon", "kind": "bow", "glyph": ")", "color": Color(0.36, 0.26, 0.16),
		"damage": 25.0, "draw": 1.15, "arrow_speed": 50.0, "speed": 1.0, "reach": 2.2, "stack": 1, "value": 160, "rarity": 2, "tier": "steel",
		"rank_req": 4, "model_script": MODEL, "desc": "Taller than you, steel-capped. Slow to draw, hits like a hammer. Archer rank 4."},
	"bow_emberwood": {"name": "Emberwood Bow", "category": "weapon", "kind": "bow", "glyph": ")", "color": Color(0.75, 0.3, 0.12),
		"damage": 34.0, "draw": 1.05, "arrow_speed": 52.0, "burn": 5.0, "speed": 1.0, "reach": 2.2, "stack": 1, "value": 320, "rarity": 3, "tier": "mithril",
		"rank_req": 6, "model_script": MODEL, "desc": "Its arrows leave the string smouldering. Archer rank 6."},
	"bow_ryftwood": {"name": "Ryftwood Recurve", "category": "weapon", "kind": "bow", "glyph": ")", "color": Color(0.55, 0.4, 0.8),
		"damage": 45.0, "draw": 1.0, "arrow_speed": 58.0, "speed": 1.0, "reach": 2.2, "stack": 1, "value": 560, "rarity": 4, "tier": "adamantite",
		"rank_req": 8, "model_script": MODEL, "desc": "Wood from the floating isles, strung with starlight. Archer rank 8."},
	# --- Arrows -----------------------------------------------------------------------
	"arrow": {"name": "Arrow", "category": "material", "kind": "arrow", "glyph": "↑", "color": Color(0.6, 0.5, 0.38), "stack": 99, "value": 1,
		"arrow_damage": 0.0, "model_script": MODEL, "desc": "Stick, stone head. Bows need them."},
	"arrow_iron": {"name": "Iron Arrow", "category": "material", "kind": "arrow", "glyph": "↑", "color": Color(0.7, 0.7, 0.72), "stack": 99, "value": 3,
		"arrow_damage": 6.0, "rarity": 1, "model_script": MODEL, "desc": "A bodkin point: +6 damage. Used before plain arrows."},
	"arrow_fire": {"name": "Fire Arrow", "category": "material", "kind": "arrow", "glyph": "↑", "color": Color(1.0, 0.5, 0.2), "stack": 99, "value": 4,
		"arrow_damage": 3.0, "arrow_burn": 4.0, "rarity": 1, "model_script": MODEL, "desc": "Pitch-soaked: sets what it hits alight. Used first."},
	# --- Staffs -----------------------------------------------------------------------
	"staff_apprentice": {"name": "Apprentice's Staff", "category": "weapon", "kind": "staff", "glyph": "|", "color": Color(0.5, 0.36, 0.24),
		"damage": 5.0, "bolt_damage": 13.0, "mana_cost": 6.0, "speed": 1.0, "reach": 2.6, "stack": 1, "value": 14, "rarity": 0, "tier": "wood",
		"rank_req": 0, "model_script": MODEL, "desc": "A walking stick with a glass focus. Attack: arcane bolt (6 mana)."},
	"staff_ember": {"name": "Ember Staff", "category": "weapon", "kind": "staff", "glyph": "|", "color": Color(0.9, 0.35, 0.15),
		"damage": 7.0, "bolt_damage": 20.0, "mana_cost": 7.0, "burn": 3.0, "speed": 1.0, "reach": 2.6, "stack": 1, "value": 90, "rarity": 1, "tier": "iron",
		"rank_req": 2, "model_script": MODEL, "desc": "A ruby that never cools. Bolts burn. Mage rank 2."},
	"staff_frost": {"name": "Rimecall Staff", "category": "weapon", "kind": "staff", "glyph": "|", "color": Color(0.6, 0.85, 1.0),
		"damage": 8.0, "bolt_damage": 28.0, "mana_cost": 8.0, "speed": 1.0, "reach": 2.6, "stack": 1, "value": 200, "rarity": 2, "tier": "steel",
		"rank_req": 4, "model_script": MODEL, "desc": "Frost shards bound in steel. Mage rank 4."},
	"staff_storm": {"name": "Stormcaller Staff", "category": "weapon", "kind": "staff", "glyph": "|", "color": Color(0.6, 0.5, 1.0),
		"damage": 9.0, "bolt_damage": 37.0, "mana_cost": 9.0, "speed": 1.0, "reach": 2.6, "stack": 1, "value": 360, "rarity": 3, "tier": "mithril",
		"rank_req": 6, "model_script": MODEL, "desc": "Amethyst crackling on emberwood. Mage rank 6."},
	"staff_void": {"name": "Voidglass Staff", "category": "weapon", "kind": "staff", "glyph": "|", "color": Color(0.35, 0.2, 0.55),
		"damage": 10.0, "bolt_damage": 48.0, "mana_cost": 10.0, "speed": 1.0, "reach": 2.6, "stack": 1, "value": 600, "rarity": 4, "tier": "adamantite",
		"rank_req": 8, "model_script": MODEL, "desc": "Starmetal and ryftwood around a hole in the sky. Mage rank 8."},
	# --- Books ------------------------------------------------------------------------
	"book_spells_novice": {"name": "Glyphs of the Novice", "category": "book", "book": "book_spells_novice", "glyph": "▤", "color": Color(0.35, 0.45, 0.75),
		"stack": 1, "value": 40, "rarity": 1, "model_script": MODEL, "desc": "Read it (right click): Frost Lance, Iron Ward and Blink."},
	"book_spells_adept": {"name": "Tome of Storm and Stone", "category": "book", "book": "book_spells_adept", "glyph": "▤", "color": Color(0.45, 0.35, 0.7),
		"stack": 1, "value": 90, "rarity": 2, "model_script": MODEL, "desc": "Read it: Chain Lightning, Earthshatter, Arcane Nova, Rain of Arrows."},
	"book_spells_master": {"name": "Codex of Cinders", "category": "book", "book": "book_spells_master", "glyph": "▤", "color": Color(0.75, 0.3, 0.15),
		"stack": 1, "value": 180, "rarity": 3, "model_script": MODEL, "desc": "Read it: Meteor and Whirlwind."},
	"book_potions_novice": {"name": "A Hedge-Brewer's Primer", "category": "book", "book": "book_potions_novice", "glyph": "▤", "color": Color(0.4, 0.6, 0.3),
		"stack": 1, "value": 35, "rarity": 1, "model_script": MODEL, "desc": "Read it: three cauldron brews, step by step."},
	"book_potions_adept": {"name": "Waters of the Deep Fen", "category": "book", "book": "book_potions_adept", "glyph": "▤", "color": Color(0.3, 0.55, 0.55),
		"stack": 1, "value": 80, "rarity": 2, "model_script": MODEL, "desc": "Read it: Fireward and the Everbloom elixir."},
	"book_potions_master": {"name": "Draconic Distillations", "category": "book", "book": "book_potions_master", "glyph": "▤", "color": Color(0.6, 0.15, 0.12),
		"stack": 1, "value": 160, "rarity": 3, "model_script": MODEL, "desc": "Read it: brews of dragon blood and bone."},
	"book_crafting_fletcher": {"name": "The Fletcher's Craft", "category": "book", "book": "book_crafting_fletcher", "glyph": "▤", "color": Color(0.55, 0.45, 0.25),
		"stack": 1, "value": 30, "rarity": 1, "model_script": MODEL, "desc": "Read it: every bow and arrow, and where to make them."},
	"book_crafting_staves": {"name": "Staves and Foci", "category": "book", "book": "book_crafting_staves", "glyph": "▤", "color": Color(0.5, 0.3, 0.6),
		"stack": 1, "value": 30, "rarity": 1, "model_script": MODEL, "desc": "Read it: every staff, and how to forge a cauldron."},
	# --- Potions (brewed in the cauldron) -----------------------------------------------
	"potion_mana": {"name": "Mana Draught", "category": "consumable", "glyph": "!", "color": Color(0.3, 0.45, 1.0), "mana": 60.0,
		"stack": 10, "value": 20, "rarity": 1, "model_script": MODEL, "desc": "Restores 60 mana (or fury, or focus)."},
	"potion_swiftness": {"name": "Swiftness Tonic", "category": "consumable", "glyph": "!", "color": Color(0.9, 0.9, 0.4), "buff": "swift", "buff_time": 90.0,
		"stack": 10, "value": 30, "rarity": 1, "model_script": MODEL, "desc": "Run 25% faster for 90 seconds."},
	"potion_featherfall": {"name": "Featherfall Draught", "category": "consumable", "glyph": "!", "color": Color(0.85, 0.9, 1.0), "buff": "featherfall", "buff_time": 120.0,
		"stack": 10, "value": 35, "rarity": 1, "model_script": MODEL, "desc": "For two minutes: no fall damage, and hold jump to glide."},
	"potion_fireward": {"name": "Fireward Philtre", "category": "consumable", "glyph": "!", "color": Color(1.0, 0.45, 0.15), "buff": "fireward", "buff_time": 120.0,
		"stack": 10, "value": 45, "rarity": 2, "model_script": MODEL, "desc": "40% fire resistance for two minutes."},
	"elixir_everbloom": {"name": "Everbloom Elixir", "category": "consumable", "glyph": "!", "color": Color(0.5, 1.0, 0.6), "heal": 120.0, "buff": "clarity", "buff_time": 60.0,
		"stack": 10, "value": 90, "rarity": 3, "model_script": MODEL, "desc": "Restores 120 health; mana returns twice as fast for a minute."},
	"potion_dragon_vigor": {"name": "Dragon's Vigor", "category": "consumable", "glyph": "!", "color": Color(0.85, 0.12, 0.1), "heal": 60.0, "buff": "vigor", "buff_time": 180.0,
		"stack": 5, "value": 150, "rarity": 4, "model_script": MODEL, "desc": "Restores 60 health; for three minutes +15 defence and +15% damage."},
	"elixir_bonemarrow": {"name": "Marrow of Ages", "category": "consumable", "glyph": "!", "color": Color(0.95, 0.9, 0.75), "buff": "ironskin", "buff_time": 300.0,
		"stack": 5, "value": 140, "rarity": 4, "model_script": MODEL, "desc": "Ironskin for five minutes."},
	"brew_sludge": {"name": "Cauldron Sludge", "category": "material", "glyph": "~", "color": Color(0.3, 0.28, 0.2), "stack": 20, "value": 0,
		"model_script": MODEL, "desc": "What a brew becomes when the steps are not followed. Smells of failure."},
	# --- Brewing ingredients (placeholders; other systems may define the real ones) ----------
	"dragon_fang": {"name": "Dragon Fang", "category": "material", "glyph": "v", "color": Color(0.95, 0.9, 0.78), "stack": 20, "value": 60, "rarity": 3,
		"model_script": MODEL, "desc": "A fang as long as your hand."},
	"dragon_blood": {"name": "Dragon Blood", "category": "material", "glyph": "o", "color": Color(0.7, 0.05, 0.05), "stack": 20, "value": 80, "rarity": 3,
		"model_script": MODEL, "desc": "Still warm in its flask. Volatile when heated."},
	"dragon_femur": {"name": "Dragon Femur", "category": "material", "glyph": "-", "color": Color(0.9, 0.86, 0.72), "stack": 10, "value": 70, "rarity": 3,
		"model_script": MODEL, "desc": "A thighbone, heavy as an anvil."},
	"everbloom_leaf": {"name": "Everbloom Leaf", "category": "material", "glyph": "\"", "color": Color(0.4, 0.9, 0.5), "stack": 99, "value": 12, "rarity": 2,
		"model_script": MODEL, "desc": "It glows faintly, even picked."},
	"everbloom_fruit": {"name": "Everbloom Fruit", "category": "material", "glyph": "o", "color": Color(0.95, 0.6, 0.8), "stack": 20, "value": 25, "rarity": 2,
		"model_script": MODEL, "desc": "Sweet and luminous."},
	"everbloom_sap": {"name": "Everbloom Sap", "category": "material", "glyph": "o", "color": Color(0.9, 0.85, 0.35), "stack": 20, "value": 30, "rarity": 2,
		"model_script": MODEL, "desc": "Thick golden sap. Binds a brew."},
	# --- The cauldron --------------------------------------------------------------------
	"cauldron": {"name": "Cauldron", "category": "station", "place_station": "cauldron", "glyph": "U", "color": Color(0.25, 0.25, 0.27), "stack": 1, "value": 40,
		"model_script": MODEL, "desc": "Iron pot on legs. Place it, then brew potions step by step (heat, ingredients, stirring, waiting)."},
}

const RECIPES := {
	"bow_hunting": {"inputs": {"planks": 3, "stick": 2, "leather": 1}, "station": "workbench", "group": "weapons"},
	"bow_yew": {"inputs": {"ironwood": 3, "spider_silk": 2, "iron_ingot": 1}, "station": "workbench", "group": "weapons"},
	"bow_longbow": {"inputs": {"ironwood": 4, "steel_ingot": 2, "spider_silk": 3}, "station": "anvil", "group": "weapons"},
	"bow_emberwood": {"inputs": {"emberwood": 4, "ember_crystal": 2, "spider_silk": 3}, "station": "anvil", "group": "weapons"},
	"bow_ryftwood": {"inputs": {"ryftwood": 4, "mithril_ingot": 2, "amethyst": 2, "spider_silk": 4}, "station": "anvil", "group": "weapons"},
	"arrow": {"inputs": {"stick": 2, "stone": 1}, "count": 8, "station": "", "group": "weapons"},
	"arrow_iron": {"inputs": {"stick": 2, "iron_ingot": 1}, "count": 12, "station": "anvil", "group": "weapons"},
	"arrow_fire": {"inputs": {"arrow": 6, "coal": 1, "emberleaf": 1}, "count": 6, "station": "workbench", "group": "weapons"},
	"staff_apprentice": {"inputs": {"wood": 2, "stick": 2, "glass_vial": 1}, "station": "workbench", "group": "weapons"},
	"staff_ember": {"inputs": {"ironwood": 2, "ruby": 1, "gold_ingot": 1}, "station": "anvil", "group": "weapons"},
	"staff_frost": {"inputs": {"ironwood": 2, "frost_shard": 3, "steel_ingot": 2}, "station": "anvil", "group": "weapons"},
	"staff_storm": {"inputs": {"emberwood": 2, "amethyst": 2, "mithril_ingot": 2}, "station": "anvil", "group": "weapons"},
	"staff_void": {"inputs": {"ryftwood": 3, "starmetal": 2, "sapphire": 2}, "station": "anvil", "group": "weapons"},
	"cauldron": {"inputs": {"iron_ingot": 6, "stone": 4}, "station": "anvil", "group": "stations"},
	# The cauldron's one quick simmer (the real brews are step-by-step, see Brewing).
	"potion_health_simmer": {"result": "potion_health", "inputs": {"swamp_herb": 3, "glass_vial": 1}, "time": 4.0, "station": "cauldron", "group": "potions"},
}

## What reading each book teaches: spells, brews (Brewing.RECIPES ids) and crafts (ItemDB recipe ids).
const BOOKS := {
	"book_spells_novice": {"spells": ["frost_lance", "ward", "blink"]},
	"book_spells_adept": {"spells": ["chain_lightning", "earthshatter", "arcane_nova", "rain_of_arrows"]},
	"book_spells_master": {"spells": ["meteor", "whirlwind"]},
	"book_potions_novice": {"brews": ["potion_mana", "potion_swiftness", "potion_featherfall"]},
	"book_potions_adept": {"brews": ["potion_fireward", "elixir_everbloom"]},
	"book_potions_master": {"brews": ["potion_dragon_vigor", "elixir_bonemarrow"]},
	"book_crafting_fletcher": {"crafts": ["bow_hunting", "bow_yew", "bow_longbow", "bow_emberwood", "bow_ryftwood", "arrow", "arrow_iron", "arrow_fire"]},
	"book_crafting_staves": {"crafts": ["staff_apprentice", "staff_ember", "staff_frost", "staff_storm", "staff_void", "cauldron", "potion_health_simmer"]},
}

## Extra buffs (merged with Inventory.BUFFS by Inventory._buff_sum).
const BUFFS := {
	"ward": {"defense": 60.0},
	"fireward": {"fire_resist": 0.4},
	"vigor": {"defense": 15.0, "damage_mult": 0.15},
	"swift": {},
	"featherfall": {},
	"clarity": {},
}

## Loot additions by chest tier (Chest.LOOT format: [id, chance, min, max]).
const CHEST_LOOT := {
	1: [["book_potions_novice", 0.12, 1, 1], ["book_crafting_fletcher", 0.1, 1, 1], ["book_crafting_staves", 0.1, 1, 1], ["arrow", 0.35, 6, 14]],
	2: [["book_spells_novice", 0.2, 1, 1], ["book_potions_adept", 0.12, 1, 1], ["potion_mana", 0.3, 1, 2], ["arrow_iron", 0.25, 6, 12]],
	3: [["book_spells_adept", 0.25, 1, 1], ["book_spells_master", 0.1, 1, 1], ["book_potions_master", 0.12, 1, 1], ["arrow_fire", 0.3, 6, 12]],
}


## Arrow ids a bow can loose, best first.
const ARROWS := ["arrow_fire", "arrow_iron", "arrow"]


static func merge_into(items: Dictionary, recipes: Dictionary) -> void:
	for id: String in ITEMS:
		if not items.has(id):
			items[id] = ITEMS[id]
	for rid: String in RECIPES:
		if not recipes.has(rid):
			recipes[rid] = RECIPES[rid]


static func book_knowledge(item_id: String) -> String:
	return String(ItemDB.info(item_id).get("book", ""))
