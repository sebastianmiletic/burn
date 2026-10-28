class_name Professions
extends RefCounted
## Every villager's trade: the smith, the trader (merchant) and the fisher
## by role; ordinary villagers are farmers, fishers, herbalists, scribes,
## hunters or masons by their seed (fishers only where there is water to
## fish). Each trade has what it sells (with a day's stock) and what it
## buys (with a day's appetite); some wares appear only for customers the
## village knows well (reputation tier, CharacterLife.TIERS: 2 Familiar,
## 3 Friend, 4 Honoured).
##
## sells: [item, base price, stock per day, min tier]
## buys:  [item, base price, wanted per day]

const TITLES := {"smith": "Blacksmith", "trader": "Trader", "farmer": "Farmer", "fisher": "Fisher", "herbalist": "Herbalist",
		"scribe": "Scribe", "hunter": "Hunter", "mason": "Mason", "elder": "Elder", "chief": "Chief", "guard": "Guard"}

const GREETINGS := {
	"smith": "Steel, iron, ingots. Bring me ore and I'll pay fair.",
	"trader": "A bit of everything, and gold for anything shiny.",
	"farmer": "Fresh from the fields. And I'll take seaweed and bone meal for the soil.",
	"fisher": "Rods, line, bait, and today's catch. Sell me your fish if the price is right.",
	"herbalist": "Tinctures and simples. Bring me venom, herbs and wings.",
	"scribe": "Maps, lore and old letters. I pay well for what the sea gives up.",
	"hunter": "Meat, leather and good boots. Pelts fetch a fair price here.",
	"mason": "Stone, brick and slate, cut true. Marble and obsidian wanted.",
}

const TRADES := {
	"smith": {
		"sells": [["copper_ingot", 7, 12, 1], ["iron_ingot", 15, 10, 1], ["bronze_ingot", 11, 8, 1], ["steel_ingot", 32, 6, 2],
			["pickaxe_iron", 70, 1, 1], ["axe_iron", 64, 1, 1], ["sword_iron", 70, 1, 2], ["spear_iron", 66, 1, 2],
			["helmet_iron", 80, 1, 2], ["chestplate_iron", 140, 1, 3], ["pickaxe_steel", 150, 1, 3], ["sword_steel", 160, 1, 3],
			["mithril_ingot", 70, 3, 4], ["lantern", 12, 4, 1]],
		"buys": [["copper_ore", 2, 30], ["tin_ore", 2, 30], ["iron_ore", 5, 25], ["coal", 2, 40], ["silver_ore", 8, 15], ["gold_ore", 10, 15],
			["mithril_ore", 24, 8], ["adamantite_ore", 45, 6], ["iron_ingot", 9, 10], ["old_boot", 1, 5]],
	},
	"trader": {
		"sells": [["potion_health", 12, 6, 1], ["bread", 3, 15, 1], ["apple", 2, 15, 1], ["torch", 1, 30, 1], ["glass_vial", 4, 10, 1],
			["coal", 3, 20, 1], ["stick", 1, 30, 1], ["lantern", 10, 3, 1], ["campfire", 5, 2, 1], ["potion_greater", 40, 2, 2],
			["treasure_map", 40, 1, 2], ["fog_lantern", 75, 1, 3], ["bait_worms", 1, 20, 1]],
		"buys": [["ruby", 25, 5], ["sapphire", 25, 5], ["amethyst", 22, 5], ["pearl", 30, 5], ["ancient_coin", 28, 6], ["gilded_idol", 60, 3],
			["gold_ingot", 14, 10], ["silver_ingot", 10, 10], ["trophy_fang", 40, 3], ["trophy_pelt", 45, 3], ["trophy_skull", 50, 3]],
	},
	"farmer": {
		"sells": [["bread", 3, 20, 1], ["apple", 2, 25, 1], ["cheese", 5, 10, 1], ["wool", 4, 12, 1], ["raw_meat", 3, 10, 1],
			["bait_worms", 1, 30, 1], ["thatch", 2, 20, 1], ["cooked_meat", 6, 8, 2], ["fish_stew", 16, 3, 3]],
		"buys": [["seaweed", 1, 30], ["bone", 1, 30], ["rabbit_hide", 2, 10], ["wolf_pelt", 7, 5], ["driftwood", 1, 20], ["swamp_herb", 2, 15]],
	},
	"fisher": {
		"sells": [["rod_wood", 8, 2, 1], ["rod_reed", 22, 2, 1], ["fishing_line", 2, 20, 1], ["river_reed", 2, 20, 1], ["bait_worms", 1, 40, 1],
			["bait_glowgrub", 5, 15, 2], ["rod_iron", 60, 1, 3], ["bait_lure", 14, 8, 3], ["smoked_fish", 8, 10, 1],
			["fish_herring", 3, 10, 1], ["fish_cod", 9, 5, 2], ["cooked_fish", 5, 10, 1]],
		"buys": [["fish_perch", 2, 20], ["fish_carp", 2, 20], ["fish_trout", 4, 20], ["fish_catfish", 4, 15], ["fish_pike", 7, 12], ["fish_eel", 5, 12],
			["fish_herring", 2, 25], ["fish_mackerel", 3, 25], ["fish_cod", 6, 15], ["fish_salmon", 10, 12], ["fish_bass", 9, 12], ["fish_tuna", 18, 8],
			["fish_frostfin", 20, 6], ["fish_ember_eel", 24, 6], ["fish_glowfin", 11, 8], ["fish_swordfish", 45, 4], ["fish_golden_koi", 140, 2],
			["fish_ghost_carp", 100, 2], ["fish_abyssal_angler", 300, 1], ["raw_fish", 1, 20], ["tangled_net", 2, 10], ["pearl", 26, 3]],
	},
	"herbalist": {
		"sells": [["potion_health", 11, 8, 1], ["emberleaf", 3, 20, 1], ["swamp_herb", 2, 20, 1], ["glass_vial", 4, 15, 1],
			["potion_ironskin", 42, 2, 2], ["potion_might", 42, 2, 2], ["potion_greater", 38, 3, 3], ["potion_tidebreath", 60, 1, 3],
			["potion_phoenix", 105, 1, 4]],
		"buys": [["venom_sac", 10, 10], ["bat_wing", 2, 20], ["emberleaf", 2, 30], ["swamp_herb", 1, 30], ["frost_shard", 9, 10],
			["amethyst", 18, 4], ["spider_silk", 3, 20], ["fish_glowfin", 12, 6], ["kraken_ink", 30, 3]],
	},
	"scribe": {
		"sells": [["treasure_map", 38, 1, 1], ["glass_vial", 4, 6, 1], ["lantern", 10, 2, 1], ["fog_lantern", 70, 1, 2],
			["sunstone", 90, 1, 3], ["storm_horn", 90, 1, 3], ["frost_totem", 60, 1, 2]],
		"buys": [["bottled_letter", 40, 6], ["ancient_coin", 30, 6], ["gilded_idol", 65, 2], ["kraken_ink", 28, 3], ["trophy_skull", 55, 2],
			["amethyst", 20, 3], ["sunken_coffer", 35, 2]],
	},
	"hunter": {
		"sells": [["raw_meat", 3, 15, 1], ["cooked_meat", 6, 10, 1], ["leather", 6, 12, 1], ["hiking_boots", 45, 1, 2],
			["spear_stone", 10, 2, 1], ["bait_lure", 15, 4, 3], ["wolf_pelt", 14, 3, 2]],
		"buys": [["wolf_pelt", 8, 10], ["frost_pelt", 14, 6], ["bear_pelt", 18, 5], ["leather", 3, 20], ["rabbit_hide", 2, 20],
			["antler", 5, 10], ["tusk", 6, 10], ["lurker_hide", 11, 5], ["shark_tooth", 7, 10], ["chitin", 4, 15], ["old_boot", 1, 6]],
	},
	"mason": {
		"sells": [["stone", 1, 64, 1], ["cobble", 1, 64, 1], ["brick", 2, 40, 1], ["slate", 2, 30, 1], ["granite", 2, 30, 1],
			["limestone", 2, 30, 2], ["sandstone", 2, 30, 2], ["marble", 4, 20, 3], ["anvil", 34, 1, 2], ["furnace", 14, 1, 1]],
		"buys": [["clay", 2, 30], ["marble", 3, 20], ["granite", 1, 30], ["obsidian", 8, 10], ["basalt", 1, 30], ["slate", 1, 30]],
	},
}

## The trade of a villager. `coastal`: the village has fishable water near.
static func of(role: String, seed_value: int, coastal := false) -> String:
	match role:
		"blacksmith":
			return "smith"
		"merchant":
			return "trader"
		"fisher":
			return "fisher"
		"elder", "chief", "guard":
			return role
	var pool := ["farmer", "farmer", "herbalist", "scribe", "hunter", "mason"]
	if coastal:
		pool.append_array(["fisher", "fisher"])
	return pool[absi(seed_value * 2246822519 + 3266489917) % pool.size()]


static func title(profession: String) -> String:
	return String(TITLES.get(profession, "Villager"))


static func trades(profession: String) -> bool:
	return TRADES.has(profession)


static func greeting(profession: String) -> String:
	return String(GREETINGS.get(profession, ""))
