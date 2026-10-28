class_name VillageGoods
extends RefCounted
## Items and recipes added by village life: fishing (rods by tier, line,
## bait, the catch, junk and treasure), cooked fish dishes and a few trade
## goods. ItemDB._static_init merges these in without overwriting anything,
## so other modules may define the same ids.
##
## Fishing rods: category "fishing", "rod_tier" 1..5, "use_script" (right
## click casts / strikes / reels, see FishingSession). Bait: "bait" strength.
## Fish: food, "fish" size class ("small" cooks to Grilled Fish, "large" to
## fish steaks, "trophy" is a prize for the fisher, not dinner).

const MODEL := "res://items/fishing/fishing_models.gd"
const ROD_USE := "res://items/fishing/fishing_rod.gd"
const OPEN_USE := "res://items/village_goods.gd"

const ITEMS := {
	# Rods ----------------------------------------------------------------------
	"rod_wood": {"name": "Willow Rod", "category": "fishing", "kind": "fishing_rod", "rod_tier": 1, "glyph": "/", "color": Color(0.6, 0.45, 0.25),
		"stack": 1, "value": 6, "rarity": 0, "pose": "diagonal", "desc": "A springy willow pole, a cork grip and a wooden reel. Right-click to cast."},
	"rod_reed": {"name": "Reed Rod", "category": "fishing", "kind": "fishing_rod", "rod_tier": 2, "glyph": "/", "color": Color(0.72, 0.66, 0.38),
		"stack": 1, "value": 18, "rarity": 0, "pose": "diagonal", "desc": "Jointed river reed, light and quick. Feels the faintest nibble."},
	"rod_iron": {"name": "Iron Rod", "category": "fishing", "kind": "fishing_rod", "rod_tier": 3, "glyph": "/", "color": Color(0.62, 0.62, 0.64),
		"stack": 1, "value": 45, "rarity": 1, "pose": "diagonal", "desc": "Iron-ringed ash with a geared reel. Holds pike and salmon."},
	"rod_mithril": {"name": "Mithril Rod", "category": "fishing", "kind": "fishing_rod", "rod_tier": 4, "glyph": "/", "color": Color(0.7, 0.86, 1.0),
		"stack": 1, "value": 130, "rarity": 3, "pose": "diagonal", "desc": "Silk line on a mithril blank. Deep-water fish cannot snap it."},
	"rod_tideborn": {"name": "Tideborn Rod", "category": "fishing", "kind": "fishing_rod", "rod_tier": 5, "glyph": "/", "color": Color(0.25, 0.7, 0.75),
		"stack": 1, "value": 320, "rarity": 4, "pose": "diagonal", "desc": "Leviathan scale and kraken ink. The sea gives up its strangest fish to it."},
	# Tackle ---------------------------------------------------------------------
	"fishing_line": {"name": "Fishing Line", "category": "material", "glyph": "~", "color": Color(0.85, 0.85, 0.8), "stack": 99, "value": 2, "desc": "Twisted line for rods and nets."},
	"river_reed": {"name": "River Reed", "category": "material", "glyph": "|", "color": Color(0.7, 0.68, 0.4), "stack": 99, "value": 2, "desc": "Hollow cane cut from the shallows. Fishers sell it by the bundle."},
	"bait_worms": {"name": "Earthworms", "category": "material", "glyph": "s", "color": Color(0.7, 0.4, 0.38), "bait": 1, "stack": 50, "value": 1,
		"desc": "Bait. Fish bite sooner. Used up one per catch while carried."},
	"bait_glowgrub": {"name": "Glowgrub Bait", "category": "material", "glyph": "s", "color": Color(0.6, 0.95, 0.45), "bait": 2, "stack": 50, "value": 4, "rarity": 1,
		"desc": "Bait that glows in dark water. Bites come quickly; rarer fish take notice."},
	"bait_lure": {"name": "Feathered Lure", "category": "material", "glyph": "v", "color": Color(0.9, 0.4, 0.25), "bait": 3, "stack": 20, "value": 12, "rarity": 2,
		"desc": "A bright jig of copper and feathers. The best bait for big and rare fish."},
	# Fish -----------------------------------------------------------------------
	"fish_perch": {"name": "Striped Perch", "category": "consumable", "glyph": "o", "color": Color(0.55, 0.6, 0.3), "heal": 3.0, "food": true, "fish": "small", "stack": 20, "value": 3, "desc": "Common in lakes and ponds. Cook it first."},
	"fish_carp": {"name": "Mud Carp", "category": "consumable", "glyph": "o", "color": Color(0.62, 0.52, 0.3), "heal": 3.0, "food": true, "fish": "small", "stack": 20, "value": 3, "desc": "Bronze-scaled and lazy. Bites by day in still water."},
	"fish_trout": {"name": "Brook Trout", "category": "consumable", "glyph": "o", "color": Color(0.5, 0.55, 0.5), "heal": 3.0, "food": true, "fish": "small", "stack": 20, "value": 5, "desc": "Speckled, cold-water fish of the mountains."},
	"fish_catfish": {"name": "Whiskered Catfish", "category": "consumable", "glyph": "o", "color": Color(0.35, 0.33, 0.3), "heal": 3.0, "food": true, "fish": "small", "stack": 20, "value": 5, "desc": "A night feeder of the marsh mud."},
	"fish_pike": {"name": "Marsh Pike", "category": "consumable", "glyph": "o", "color": Color(0.4, 0.5, 0.3), "heal": 4.0, "food": true, "fish": "large", "stack": 20, "value": 9, "rarity": 1, "desc": "All teeth and temper. Strikes at dawn and dusk."},
	"fish_eel": {"name": "Black Eel", "category": "consumable", "glyph": "s", "color": Color(0.2, 0.2, 0.18), "heal": 3.0, "food": true, "fish": "small", "stack": 20, "value": 7, "desc": "Slithers out at night. Smoked eel is a delicacy."},
	"fish_herring": {"name": "Silver Herring", "category": "consumable", "glyph": "o", "color": Color(0.75, 0.8, 0.85), "heal": 3.0, "food": true, "fish": "small", "stack": 20, "value": 3, "desc": "Schools by the thousand off every coast."},
	"fish_mackerel": {"name": "Tiger Mackerel", "category": "consumable", "glyph": "o", "color": Color(0.3, 0.55, 0.55), "heal": 3.0, "food": true, "fish": "small", "stack": 20, "value": 4, "desc": "Striped and oily. Shallow sea water."},
	"fish_cod": {"name": "Grey Cod", "category": "consumable", "glyph": "o", "color": Color(0.55, 0.52, 0.45), "heal": 4.0, "food": true, "fish": "large", "stack": 20, "value": 8, "desc": "A cold-sea staple. Fills a pot."},
	"fish_salmon": {"name": "Fjord Salmon", "category": "consumable", "glyph": "o", "color": Color(0.85, 0.5, 0.4), "heal": 4.0, "food": true, "fish": "large", "stack": 20, "value": 12, "rarity": 1, "desc": "Fights like a wolf. Fjords and cold coasts."},
	"fish_bass": {"name": "Reef Bass", "category": "consumable", "glyph": "o", "color": Color(0.35, 0.6, 0.75), "heal": 4.0, "food": true, "fish": "large", "stack": 20, "value": 11, "rarity": 1, "desc": "Bright and heavy. Lives among the coral."},
	"fish_tuna": {"name": "Bluefin Tuna", "category": "consumable", "glyph": "o", "color": Color(0.2, 0.3, 0.5), "heal": 5.0, "food": true, "fish": "large", "stack": 10, "value": 22, "rarity": 2, "desc": "A deep-water runner. Needs an iron rod or better."},
	"fish_frostfin": {"name": "Frostfin", "category": "consumable", "glyph": "o", "color": Color(0.75, 0.9, 1.0), "heal": 4.0, "food": true, "fish": "large", "stack": 10, "value": 24, "rarity": 2, "desc": "Translucent and ice-cold, from the Rime Sea."},
	"fish_ember_eel": {"name": "Ember Eel", "category": "consumable", "glyph": "s", "color": Color(1.0, 0.45, 0.15), "heal": 4.0, "food": true, "fish": "large", "stack": 10, "value": 28, "rarity": 2, "desc": "Warm to the touch. Swims by the boiling vents."},
	"fish_glowfin": {"name": "Cave Glowfin", "category": "consumable", "glyph": "o", "color": Color(0.5, 1.0, 0.8), "heal": 4.0, "food": true, "fish": "small", "stack": 20, "value": 14, "rarity": 1, "desc": "Blind, pale and softly glowing. Underground water."},
	"fish_swordfish": {"name": "Swordfish", "category": "consumable", "glyph": "/", "color": Color(0.3, 0.38, 0.55), "heal": 6.0, "food": true, "fish": "large", "stack": 5, "value": 55, "rarity": 3, "desc": "A sea-going duellist. Mithril rods only."},
	"fish_golden_koi": {"name": "Golden Koi", "category": "treasure", "glyph": "o", "color": Color(1.0, 0.75, 0.25), "fish": "trophy", "stack": 5, "value": 120, "rarity": 4, "desc": "A legend of still lakes. Fishers pay a fortune for one."},
	"fish_ghost_carp": {"name": "Ghost Carp", "category": "treasure", "glyph": "o", "color": Color(0.85, 0.9, 0.95), "fish": "trophy", "stack": 5, "value": 90, "rarity": 3, "desc": "Pale as moonlight. Only bites at night."},
	"fish_abyssal_angler": {"name": "Abyssal Angler", "category": "treasure", "glyph": "o", "color": Color(0.15, 0.2, 0.3), "fish": "trophy", "stack": 5, "value": 260, "rarity": 5, "desc": "Its lantern still glows. From the bottom of the world."},
	# Dishes ---------------------------------------------------------------------
	"fish_steak": {"name": "Fish Steak", "category": "consumable", "glyph": "o", "color": Color(0.85, 0.6, 0.4), "heal": 40.0, "food": true, "stack": 20, "value": 9, "desc": "Thick, seared and buttery. Restores 40 health."},
	"smoked_fish": {"name": "Smoked Fish", "category": "consumable", "glyph": "o", "color": Color(0.6, 0.38, 0.2), "heal": 32.0, "food": true, "stack": 20, "value": 7, "desc": "Keeps for a season. Restores 32 health."},
	"fish_stew": {"name": "Fisher's Stew", "category": "consumable", "glyph": "u", "color": Color(0.75, 0.55, 0.35), "heal": 70.0, "food": true, "stack": 10, "value": 16, "rarity": 1, "desc": "Fish, apple and bread in one bowl. Restores 70 health."},
	"cheese": {"name": "Wheel of Cheese", "category": "consumable", "glyph": "o", "color": Color(0.95, 0.8, 0.4), "heal": 18.0, "food": true, "stack": 20, "value": 5, "desc": "Sharp farmhouse cheese. Restores 18 health."},
	# Junk and treasure ---------------------------------------------------------------
	"old_boot": {"name": "Waterlogged Boot", "category": "material", "glyph": "L", "color": Color(0.3, 0.24, 0.18), "stack": 10, "value": 1, "desc": "Someone's left boot. Leatherworkers will take it for scrap."},
	"driftwood": {"name": "Driftwood", "category": "material", "glyph": "=", "color": Color(0.7, 0.66, 0.6), "stack": 99, "value": 1, "desc": "Silver-grey and salt-cured. Burns, or splits into sticks."},
	"tangled_net": {"name": "Tangled Net", "category": "material", "glyph": "#", "color": Color(0.55, 0.5, 0.4), "stack": 10, "value": 2, "desc": "Unpick it for fishing line."},
	"seaweed": {"name": "Seaweed", "category": "material", "glyph": "\"", "color": Color(0.2, 0.4, 0.2), "stack": 99, "value": 1, "desc": "Slimy. Farmers spread it on their fields."},
	"bottled_letter": {"name": "Message in a Bottle", "category": "treasure", "glyph": "!", "color": Color(0.6, 0.8, 0.7), "stack": 10, "value": 25, "rarity": 1, "desc": "A sealed bottle with a letter inside. Scribes collect them."},
	"sunken_coffer": {"name": "Sunken Coffer", "category": "treasure", "glyph": "n", "color": Color(0.5, 0.35, 0.2), "stack": 10, "value": 30, "rarity": 2,
		"use_script": OPEN_USE, "desc": "Barnacled and locked with rust. Right-click to prise it open."},
}

## Hand-written recipes (same shape as ItemDB.BASE_RECIPES).
const RECIPES := {
	"fishing_line": {"inputs": {"wool": 1}, "count": 2, "station": "", "group": "basics"},
	"fishing_line_silk": {"result": "fishing_line", "inputs": {"spider_silk": 1}, "count": 3, "station": "", "group": "basics"},
	"fishing_line_net": {"result": "fishing_line", "inputs": {"tangled_net": 1}, "count": 2, "station": "", "group": "basics"},
	"stick_driftwood": {"result": "stick", "inputs": {"driftwood": 1}, "count": 3, "station": "", "group": "basics"},
	"bait_worms": {"inputs": {"dirt": 2}, "count": 3, "station": "", "group": "basics"},
	"bait_glowgrub": {"inputs": {"bait_worms": 2, "emberleaf": 1}, "count": 2, "station": "workbench", "group": "basics"},
	"bait_lure": {"inputs": {"copper_ingot": 1, "fishing_line": 1, "bone": 1}, "count": 3, "station": "workbench", "group": "basics"},
	"rod_wood": {"inputs": {"stick": 3, "fishing_line": 1}, "station": "", "group": "tools"},
	"rod_reed": {"inputs": {"river_reed": 3, "fishing_line": 2, "copper_ingot": 1}, "station": "workbench", "group": "tools"},
	"rod_iron": {"inputs": {"iron_ingot": 3, "planks": 2, "fishing_line": 2}, "station": "anvil", "group": "tools"},
	"rod_mithril": {"inputs": {"mithril_ingot": 2, "silver_ingot": 1, "spider_silk": 3}, "station": "anvil", "group": "tools"},
	"rod_tideborn": {"inputs": {"leviathan_scale": 2, "tide_pearl": 2, "mithril_ingot": 2, "kraken_ink": 1}, "station": "anvil", "group": "tools"},
	"fish_stew": {"inputs": {"cooked_fish": 2, "apple": 1, "bread": 1}, "time": 3.0, "station": "campfire", "group": "food"},
	"smoked_fish": {"inputs": {"cooked_fish": 1, "wood": 1}, "time": 3.0, "station": "campfire", "group": "food"},
}

## Fish that cook into each dish: small fish grill, large fish become steaks.
const COOK_SMALL := "cooked_fish"
const COOK_LARGE := "fish_steak"


## Called from ItemDB._static_init: adds what is not defined yet.
static func register(items: Dictionary, recipes: Dictionary) -> void:
	for id: String in ITEMS:
		if not items.has(id):
			var d: Dictionary = (ITEMS[id] as Dictionary).duplicate()
			d["model_script"] = MODEL
			if d.has("rod_tier"):
				d["use_script"] = ROD_USE
			items[id] = d
	for rid: String in RECIPES:
		if not recipes.has(rid):
			recipes[rid] = RECIPES[rid]
	# Every fish cooks: at a campfire, and in a furnace like meat.
	for id: String in ITEMS:
		var size := String((ITEMS[id] as Dictionary).get("fish", ""))
		if size in ["small", "large"]:
			var out := COOK_SMALL if size == "small" else COOK_LARGE
			var key := "%s_cook_%s" % [out, id.trim_prefix("fish_")]
			if not recipes.has(key):
				recipes[key] = {"result": out, "inputs": {id: 1}, "time": 2.0 if size == "small" else 2.8, "station": "campfire", "group": "food"}
			var fkey := "%s_furnace_%s" % [out, id.trim_prefix("fish_")]
			if not recipes.has(fkey):
				recipes[fkey] = {"result": out, "inputs": {id: 1}, "fuel": 1, "time": 2.2, "station": "furnace", "group": "food"}


## All fish ids (food and trophies).
static func fish_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in ITEMS:
		if (ITEMS[id] as Dictionary).has("fish"):
			out.append(id)
	return out


static func is_fish(id: String) -> bool:
	return id == "raw_fish" or ItemDB.info(id).has("fish")


static func is_meat(id: String) -> bool:
	return id in ["raw_meat", "cooked_meat"]


# --- "use_script" for the coffer ---------------------------------------------------

## Right-click a Sunken Coffer: gold and a trinket or two.
static func use(player: Node, id: String) -> void:
	if id != "sunken_coffer" or player == null:
		return
	var inv: Inventory = player.get("inventory")
	if inv == null or not inv.has(id):
		return
	inv.remove(id, 1)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var gold := rng.randi_range(12, 45)
	inv.gold += gold
	inv.changed.emit()
	Events.notify.emit("The coffer gives up %d gold." % gold, "loot")
	var prizes := ["pearl", "ancient_coin", "ruby", "sapphire", "amethyst", "silver_ingot", "bait_lure", "treasure_map"]
	for i in rng.randi_range(1, 2):
		player.call("give_item", prizes[rng.randi() % prizes.size()], 1)
	Audio.play_ui("coin")
