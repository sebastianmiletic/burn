class_name QuestDB
extends RefCounted
## Quest definitions. Objectives are matched against game events:
##   talk(giver key)  interact(kind @ location)  mine(block)  collect(item)
##   kill(enemy kind)  boss(kind)  reach(location id)  have(item)
##   gather(item: picked up)  craft(item: made)  place(item: station set down)
##   dimension(id)  discover(location kind)
## Keys may list alternatives: "axe_stone|spear_stone".
## The main campaign is a chain (`next`); FIRST_STEPS is the guided start for
## new characters (it runs beside Kindling); OPTIONAL holds the regional boss
## contracts, offered by a giver once `requires` is done. PATH is the ladder
## the journal shows (docs/PROGRESSION.md describes it in full).

## The guided start: survival basics, one small step at a time. No givers, so
## each completes itself and opens the next.
const FIRST_STEPS := [
	{
		"id": "fs_timber", "title": "Embers and Timber", "giver": "",
		"description": "You wake beside a cold shrine with a pick-axe and little else. Its axe bit fells trees: chop one down and gather the logs.",
		"objectives": [{"type": "gather", "key": "wood", "count": 4, "text": "Gather wood: chop down a tree"}],
		"rewards": {"xp": 15}, "next": "fs_workbench",
	},
	{
		"id": "fs_workbench", "title": "A Place to Work", "giver": "",
		"description": "Split logs into planks by hand (open your pack with Tab or I), build a workbench and set it down on level ground.",
		"objectives": [
			{"type": "craft", "key": "planks", "count": 4, "text": "Split wood into planks"},
			{"type": "craft", "key": "workbench", "count": 1, "text": "Craft a workbench"},
			{"type": "place", "key": "workbench", "count": 1, "text": "Place the workbench"},
		],
		"rewards": {"xp": 25}, "next": "fs_stone_tools",
	},
	{
		"id": "fs_stone_tools", "title": "Stone and Haft", "giver": "",
		"description": "Dig into bare rock for stone, whittle planks into sticks and make yourself a proper stone tool at the workbench.",
		"objectives": [
			{"type": "gather", "key": "stone", "count": 6, "text": "Dig stone with your pick-axe"},
			{"type": "craft", "key": "stick", "count": 4, "text": "Make sticks from planks"},
			{"type": "craft", "key": "axe_stone|spear_stone|warhammer_stone", "count": 1, "text": "Make a stone axe, spear or warhammer"},
		],
		"rewards": {"xp": 30, "items": {"torch": 4}}, "next": "fs_campfire",
	},
	{
		"id": "fs_campfire", "title": "A Fire of Your Own", "giver": "",
		"description": "Nights are long and the dead walk in them. Ring stones round a few logs: a campfire gives light and cooks what you hunt.",
		"objectives": [
			{"type": "craft", "key": "campfire", "count": 1, "text": "Build a campfire"},
			{"type": "place", "key": "campfire", "count": 1, "text": "Set the campfire down"},
		],
		"rewards": {"xp": 30, "items": {"raw_meat": 2}}, "next": "fs_village",
	},
	{
		"id": "fs_village", "title": "The Last Village", "giver": "",
		"description": "Emberfall lies just north of the shrine. Its elder, Maren, keeps the story of the grey sky; the smith Brannoc keeps its forge.",
		"objectives": [
			{"type": "talk", "key": "elder", "count": 1, "text": "Find the village and speak with Elder Maren"},
		],
		"rewards": {"xp": 20, "gold": 5}, "next": "",
	},
]

const MAIN := [
	{
		"id": "kindling", "title": "Kindling", "giver": "elder",
		"description": "Rekindle the Emberfall Shrine, the last warm light on the plains. Fall in battle and you wake beside a lit shrine.",
		"objectives": [{"type": "interact", "key": "shrine@emberfall_shrine", "count": 1, "text": "Rekindle the Emberfall Shrine"}],
		"rewards": {"xp": 60, "gold": 10, "items": {"potion_health": 2}}, "next": "iron_in_the_deep",
	},
	{
		"id": "iron_in_the_deep", "title": "Iron in the Deep", "giver": "blacksmith",
		"description": "Brannoc can't forge with ash. Dig under the plains for iron ore and coal and he'll make you a real blade.",
		"objectives": [
			{"type": "collect", "key": "iron_ore", "count": 5, "text": "Mine iron ore"},
			{"type": "collect", "key": "coal", "count": 3, "text": "Mine coal"},
		],
		"rewards": {"xp": 120, "gold": 15, "items": {"sword_iron": 1}, "take": {"iron_ore": 5, "coal": 3}}, "next": "tempered",
	},
	{
		"id": "tempered", "title": "Tempered in Iron", "giver": "blacksmith",
		"description": "A blade alone won't keep you alive in the crypt. Smelt iron at a furnace (or Brannoc's forge) and hammer yourself some armour.",
		"objectives": [
			{"type": "craft", "key": "iron_ingot", "count": 6, "text": "Smelt iron ingots"},
			{"type": "craft", "key": "helmet_iron|chestplate_iron|greaves_iron|boots_iron", "count": 1, "text": "Forge a piece of iron armour"},
		],
		"rewards": {"xp": 150, "gold": 20, "items": {"potion_health": 2}}, "next": "silent_crypt",
	},
	{
		"id": "silent_crypt", "title": "The Silent Crypt", "giver": "elder",
		"description": "Something woke beneath the Blackmarsh to the west. The Warden of the Silent Crypt holds the first of three seals. Take it.",
		"objectives": [
			{"type": "reach", "key": "silent_crypt", "count": 1, "text": "Find the Silent Crypt in the Blackmarsh"},
			{"type": "boss", "key": "warden", "count": 1, "text": "Defeat the Warden"},
		],
		"rewards": {"xp": 250, "gold": 60, "items": {"potion_greater": 1}}, "next": "steel_and_frost",
	},
	{
		"id": "steel_and_frost", "title": "Steel and Frost", "giver": "blacksmith",
		"description": "Iron cracks in the mountain cold. Fold coal into iron to make steel, and forge spiked boots for the steep paths beyond Frosthold.",
		"objectives": [
			{"type": "craft", "key": "steel_ingot", "count": 4, "text": "Smelt steel ingots"},
			{"type": "craft", "key": "hiking_boots", "count": 1, "text": "Forge Ironspike Hiking Boots"},
		],
		"rewards": {"xp": 220, "gold": 40, "items": {"potion_greater": 1}}, "next": "mountain_king",
	},
	{
		"id": "mountain_king", "title": "Hall of the Mountain King", "giver": "elder",
		"description": "Beyond Frosthold a troll king sits on a stolen throne inside the mountain. His crown is the second seal.",
		"objectives": [
			{"type": "reach", "key": "mountain_hall", "count": 1, "text": "Enter the Hall of the Mountain King"},
			{"type": "boss", "key": "mountain_king", "count": 1, "text": "Defeat the Mountain King"},
		],
		"rewards": {"xp": 350, "gold": 90}, "next": "ashvane",
	},
	{
		"id": "ashvane", "title": "Ashvane", "giver": "elder",
		"description": "Ashvane nests in the Dragon's Keep across the Cinder Wastes. Its still-burning heart is the last seal.",
		"objectives": [
			{"type": "reach", "key": "dragons_keep", "count": 1, "text": "Reach the Dragon's Keep"},
			{"type": "boss", "key": "dragon", "count": 1, "text": "Slay Ashvane"},
		],
		"rewards": {"xp": 500, "gold": 150}, "next": "into_the_deep",
	},
	{
		"id": "into_the_deep", "title": "Into the Deep", "giver": "elder",
		"description": "Three seals open the Gates of Hades, far below the Cinder Crater. Take a pickaxe and dig deeper than anyone has dared.",
		"objectives": [
			{"type": "have", "key": "warden_sigil", "count": 1, "text": "Carry the Warden's Sigil"},
			{"type": "have", "key": "frost_crown", "count": 1, "text": "Carry the Frost Crown"},
			{"type": "have", "key": "dragonheart", "count": 1, "text": "Carry the Dragonheart"},
			{"type": "reach", "key": "gates_of_hades", "count": 1, "text": "Dig down to the Gates of Hades"},
			{"type": "dimension", "key": "1", "count": 1, "text": "Pass through the Gates"},
		],
		"rewards": {"xp": 400, "gold": 100}, "next": "hound",
	},
	{
		"id": "hound", "title": "Hound of the Underworld", "giver": "",
		"description": "Cerberus guards the road from Tartarus to the throne. Nothing reaches Hades past that hound alive.",
		"objectives": [
			{"type": "reach", "key": "tartarus", "count": 1, "text": "Find Tartarus"},
			{"type": "boss", "key": "cerberus", "count": 1, "text": "Defeat Cerberus"},
		],
		"rewards": {"xp": 700, "gold": 200}, "next": "throne",
	},
	{
		"id": "throne", "title": "The Throne of Hades", "giver": "",
		"description": "Hades waits on his throne. Break him and the sealed Ryft gateway in Emberfall wakes. His hoard holds one-of-a-kind weapons.",
		"objectives": [
			{"type": "reach", "key": "throne_of_hades", "count": 1, "text": "Approach the Throne of Hades"},
			{"type": "boss", "key": "hades", "count": 1, "text": "Defeat Hades"},
		],
		"rewards": {"xp": 1500, "gold": 500, "items": {"sword_gatebreaker": 1, "axe_mithril": 1}}, "next": "ryft",
	},
	{
		"id": "ryft", "title": "Beyond the Broken Sky", "giver": "",
		"description": "The violet gateway in Emberfall is open. Cross the stone arches of Ryft Island, rest at the landing shrine and climb to the Crown. A mithril axe fells Ryftwood.",
		"objectives": [
			{"type": "dimension", "key": "2", "count": 1, "text": "Enter the Ryft gateway in Emberfall"},
			{"type": "reach", "key": "ryft_isle_1", "count": 1, "text": "Explore the Broken Observatory"},
			{"type": "reach", "key": "ryft_isle_2", "count": 1, "text": "Reach the Crown of the Ryft"},
			{"type": "collect", "key": "ryftwood", "count": 6, "text": "Harvest Ryftwood with a mithril axe"},
		],
		"rewards": {"xp": 800, "gold": 120, "items": {"potion_phoenix": 3}}, "next": "prism_sentinel",
	},
	{
		"id": "prism_sentinel", "title": "The Prism Sentinel", "giver": "",
		"description": "Something of glass and light guards the Broken Observatory. Shatter it and take its heart.",
		"objectives": [
			{"type": "reach", "key": "ryft_isle_1", "count": 1, "text": "Return to the Broken Observatory"},
			{"type": "boss", "key": "ryft_sentinel", "count": 1, "text": "Defeat the Prism Sentinel"},
		],
		"rewards": {"xp": 1100, "gold": 260, "items": {"potion_phoenix": 2, "starmetal": 2}}, "next": "void_sovereign",
	},
	{
		"id": "void_sovereign", "title": "The Void Sovereign", "giver": "",
		"description": "On the Crown of the Ryft a ruler of nothing waits. Take its crown and the broken sky is yours.",
		"objectives": [
			{"type": "reach", "key": "ryft_isle_2", "count": 1, "text": "Climb to the Crown of the Ryft"},
			{"type": "boss", "key": "void_sovereign", "count": 1, "text": "Defeat the Void Sovereign"},
		],
		"rewards": {"xp": 1800, "gold": 450, "items": {"starmetal": 4, "storm_horn": 1}}, "next": "",
	},
]

## Optional regional bosses: offered by `giver` once `requires` is complete
## (and, for bosses added by later builds, once the boss kind exists in this
## build: `boss_kind` must be in EntityFactory.BOSS_KINDS). Handed back to the
## giver. `tier` is the recommended equipment.
const OPTIONAL := [
	{
		"id": "opt_broodmother", "title": "The Weeping Hollow", "giver": "villager@thornwick", "requires": "silent_crypt",
		"boss_kind": "broodmother", "tier": "Steel",
		"description": "Webs choke the forest east of Thornwick and the hunters stopped coming home. Something old breeds beneath the Weeping Hollow.",
		"objectives": [
			{"type": "reach", "key": "broodmother_lair", "count": 1, "text": "Descend beneath the Weeping Hollow"},
			{"type": "boss", "key": "broodmother", "count": 1, "text": "Kill Vexhira, the Broodmother"},
		],
		"rewards": {"xp": 400, "gold": 120, "items": {"potion_greater": 2}}, "next": "",
	},
	{
		"id": "opt_bog_hag", "title": "Old Mother Mire", "giver": "villager@mirewatch", "requires": "silent_crypt",
		"boss_kind": "bog_hag", "tier": "Steel",
		"description": "Mirewatch's children dream of a woman in the reeds who sings their names. The hag of the Hagsfen has to be put down.",
		"objectives": [
			{"type": "reach", "key": "hagsfen", "count": 1, "text": "Find the Hagsfen in the marsh"},
			{"type": "boss", "key": "bog_hag", "count": 1, "text": "Defeat Old Mother Mire"},
		],
		"rewards": {"xp": 380, "gold": 110, "items": {"potion_ironskin": 2}}, "next": "",
	},
	{
		"id": "opt_leviathan", "title": "The Drowned Spire", "giver": "elder", "requires": "mountain_king",
		"boss_kind": "leviathan", "tier": "Steel or mithril",
		"description": "A broken causeway runs out to a drowned tower, and something vast circles it. The fishers of the coast want their sea back.",
		"objectives": [
			{"type": "reach", "key": "drowned_spire", "count": 1, "text": "Reach the Drowned Spire"},
			{"type": "boss", "key": "leviathan", "count": 1, "text": "Slay the Leviathan"},
		],
		"rewards": {"xp": 600, "gold": 180, "items": {"potion_phoenix": 1}}, "next": "",
	},
	{
		"id": "opt_kraken", "title": "Ink in the Trench", "giver": "villager@kaldvik", "requires": "ashvane",
		"boss_kind": "kraken", "tier": "Mithril",
		"description": "Kaldvik's boats come back crushed, or not at all. Their chief swears the deep trench off the fjord has arms.",
		"objectives": [{"type": "boss", "key": "kraken", "count": 1, "text": "Slay the Abyssal Kraken in the deep trench"}],
		"rewards": {"xp": 800, "gold": 240, "items": {"potion_phoenix": 2}}, "next": "",
	},
	{
		"id": "opt_charybdis", "title": "The Maw of the Sea", "giver": "villager@kaldvik", "requires": "opt_kraken",
		"boss_kind": "charybdis", "tier": "Mithril or adamantite",
		"description": "With the Kraken dead the sailors talk of worse: a whirlpool that swallows ships whole, and the thing that drinks at its bottom.",
		"objectives": [{"type": "boss", "key": "charybdis", "count": 1, "text": "Defeat Charybdis, the Maw of the Sea"}],
		"rewards": {"xp": 1000, "gold": 300, "items": {"potion_phoenix": 2, "starmetal": 1}}, "next": "",
	},
]

## The ladder shown on the journal's Path tab. Each step is done when its
## `quest` is completed. `tier` is the gear the step expects or unlocks.
const PATH := [
	{"quest": "fs_timber", "title": "Gather wood", "hint": "Fell a tree with your pick-axe.", "tier": "Starting kit"},
	{"quest": "fs_workbench", "title": "Build a workbench", "hint": "Planks by hand, then the bench. Set it down.", "tier": "Workbench"},
	{"quest": "fs_stone_tools", "title": "Stone tools", "hint": "Dig stone, make sticks, craft at the workbench.", "tier": "Stone"},
	{"quest": "fs_campfire", "title": "Make camp", "hint": "A campfire lights the night and cooks meat.", "tier": "Campfire"},
	{"quest": "kindling", "title": "Rekindle the shrine", "hint": "Light the Emberfall Shrine, then see Elder Maren.", "tier": "Respawn point"},
	{"quest": "iron_in_the_deep", "title": "Iron in the deep", "hint": "Dig below the plains for iron ore and coal.", "tier": "Copper, iron sword"},
	{"quest": "tempered", "title": "Forge iron gear", "hint": "Smelt iron and forge armour at Brannoc's forge.", "tier": "Iron"},
	{"quest": "silent_crypt", "title": "The first seal", "hint": "Something waits in a crypt in the western marsh.", "tier": "Iron recommended"},
	{"quest": "steel_and_frost", "title": "Steel", "hint": "Steel ingots, and boots for steep paths.", "tier": "Steel, silver, gold"},
	{"quest": "mountain_king", "title": "The second seal", "hint": "A king under the mountain beyond Frosthold.", "tier": "Steel recommended"},
	{"quest": "ashvane", "title": "The third seal", "hint": "Fire nests across the Cinder Wastes. Bring fire resistance.", "tier": "Steel or mithril, fire resist"},
	{"quest": "into_the_deep", "title": "The way down", "hint": "Carry all three seals and dig deeper than anyone.", "tier": "Mithril, adamantite"},
	{"quest": "hound", "title": "The hound", "hint": "A guardian on the road through the underworld.", "tier": "Mithril or adamantite"},
	{"quest": "throne", "title": "The throne", "hint": "The lord of the underworld.", "tier": "Adamantite or infernal"},
	{"quest": "ryft", "title": "Beyond the broken sky", "hint": "A gateway in Emberfall wakes.", "tier": "Mithril axe, Ryftwood"},
	{"quest": "prism_sentinel", "title": "Glass and light", "hint": "A guardian of the floating isles.", "tier": "Infernal or starfall"},
	{"quest": "void_sovereign", "title": "The crown of nothing", "hint": "The last power above the world.", "tier": "Infernal or starfall"},
]

## Legacy village side quests (no longer offered: villages now post bounty
## contracts and run activities, see world/activities). Kept so saves that
## have them active can still finish and hand them in.
const SIDE_TEMPLATES := [
	{"title": "Bones in the Fields", "description": "Skeletons have been seen near %s. Put them back in the ground.",
		"objectives": [{"type": "kill", "key": "skeleton", "count": 6, "text": "Destroy skeletons"}], "rewards": {"xp": 90, "gold": 25}},
	{"title": "Ghoul Hunt", "description": "Ghouls dig at the graves around %s at night.",
		"objectives": [{"type": "kill", "key": "ghoul", "count": 4, "text": "Slay ghouls"}], "rewards": {"xp": 100, "gold": 30, "items": {"potion_health": 1}}},
	{"title": "Fuel for the Hearth", "description": "Winter comes early to %s. Bring coal.",
		"objectives": [{"type": "collect", "key": "coal", "count": 10, "text": "Gather coal"}], "rewards": {"xp": 70, "gold": 20, "items": {"bread": 4}, "take": {"coal": 10}}},
	{"title": "A Glint of Gold", "description": "The merchant of %s wants gold ore and asks no questions.",
		"objectives": [{"type": "collect", "key": "gold_ore", "count": 4, "text": "Bring gold ore"}], "rewards": {"xp": 120, "gold": 80, "take": {"gold_ore": 4}}},
	{"title": "Embers Below", "description": "A scholar in %s pays for ember crystals from the deep caves.",
		"objectives": [{"type": "collect", "key": "ember_crystal", "count": 3, "text": "Bring ember crystals"}], "rewards": {"xp": 180, "gold": 90, "take": {"ember_crystal": 3}}},
	{"title": "Archers on the Road", "description": "Skeleton archers shoot at travellers outside %s.",
		"objectives": [{"type": "kill", "key": "archer", "count": 4, "text": "Defeat skeleton archers"}], "rewards": {"xp": 110, "gold": 35}},
	{"title": "The Troll Bridge", "description": "Trolls came down from the peaks near %s.",
		"objectives": [{"type": "kill", "key": "troll", "count": 2, "text": "Kill trolls"}], "rewards": {"xp": 160, "gold": 50, "items": {"potion_greater": 1}}},
	{"title": "Old Stones", "description": "Visit the forgotten places the people of %s still whisper about.",
		"objectives": [{"type": "discover", "key": "ruin", "count": 3, "text": "Discover ruins"}], "rewards": {"xp": 130, "gold": 40}},
]

const VILLAGES := ["emberfall", "ashford", "thornwick", "frosthold", "mirewatch", "cinderreach"]
const VILLAGE_NAMES := {"emberfall": "Emberfall", "ashford": "Ashford", "thornwick": "Thornwick",
		"frosthold": "Frosthold", "mirewatch": "Mirewatch", "cinderreach": "Cinderreach", "kaldvik": "Kaldvik"}


static func main_quest(id: String) -> Dictionary:
	for q: Dictionary in MAIN:
		if q["id"] == id:
			return q
	return {}


static func side_quests_for(village: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var vi := VILLAGES.find(village)
	if vi < 0:
		return out
	for n in 2:
		var t: Dictionary = SIDE_TEMPLATES[(vi * 3 + n * 5) % SIDE_TEMPLATES.size()].duplicate(true)
		t["id"] = "side_%s_%d" % [village, n]
		t["giver"] = "villager@" + village
		t["description"] = String(t["description"]) % VILLAGE_NAMES[village]
		t["next"] = ""
		out.append(t)
	return out


static func first_step(id: String) -> Dictionary:
	for q: Dictionary in FIRST_STEPS:
		if q["id"] == id:
			return q
	return {}


static func optional_quest(id: String) -> Dictionary:
	for q: Dictionary in OPTIONAL:
		if q["id"] == id:
			return q
	return {}


## "main" (story and first steps) or "side" (optional bosses, village quests).
static func category_of(id: String) -> String:
	if not main_quest(id).is_empty() or not first_step(id).is_empty():
		return "main"
	return "side"


## Is an optional quest's boss part of this build? Bosses can arrive in later
## builds; their quests stay hidden until then.
static func boss_available(q: Dictionary) -> bool:
	var kind := String(q.get("boss_kind", ""))
	return kind == "" or kind in EntityFactory.BOSS_KINDS


static func any(id: String) -> Dictionary:
	var q := main_quest(id)
	if not q.is_empty():
		return q
	q = first_step(id)
	if not q.is_empty():
		return q
	q = optional_quest(id)
	if not q.is_empty():
		return q
	for v: String in VILLAGES:
		for s in side_quests_for(v):
			if s["id"] == id:
				return s
	return {}
