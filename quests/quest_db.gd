class_name QuestDB
extends RefCounted
## Quest definitions. Objectives are matched against game events:
##   talk(role)  interact(kind @ location)  mine(block)  collect(item)
##   kill(enemy kind)  boss(kind)  reach(location id)  have(item)
## The main campaign is a chain (`next`); side quests come from villages.

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
		"rewards": {"xp": 120, "gold": 15, "items": {"sword_iron": 1}, "take": {"iron_ore": 5, "coal": 3}}, "next": "silent_crypt",
	},
	{
		"id": "silent_crypt", "title": "The Silent Crypt", "giver": "elder",
		"description": "Something woke beneath the Blackmarsh to the west. The Warden of the Silent Crypt holds the first of three seals. Take it.",
		"objectives": [
			{"type": "reach", "key": "silent_crypt", "count": 1, "text": "Find the Silent Crypt in the Blackmarsh"},
			{"type": "boss", "key": "warden", "count": 1, "text": "Defeat the Warden"},
		],
		"rewards": {"xp": 250, "gold": 60, "items": {"potion_greater": 1}}, "next": "mountain_king",
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
		"description": "Cerberus guards the road from Tartarus to the throne. Its fang opens the way.",
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
		"frosthold": "Frosthold", "mirewatch": "Mirewatch", "cinderreach": "Cinderreach"}


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


## Journal entries recorded (already complete) when something rare happens.
const LORE := [
	{
		"id": "lore_ogygia", "title": "Ogygia", "giver": "",
		"description": "The sea took you, and then, against all custom, gave you back. You woke on Ogygia, the island of the nymph Calypso, far from every chart: violets and wild parsley, cypress and poplar, a spring, and a grotto where her fire never goes out. She mended your sail. The gods do not do this twice for anyone lightly.",
		"objectives": [{"type": "dimension", "key": "3", "count": 1, "text": "Wake on Calypso's island"}],
		"rewards": {},
	},
	{
		"id": "lore_calypso_gift", "title": "Calypso's Gift", "giver": "",
		"description": "Before you left her island, Calypso pressed a phoenix draught into your hands: for the next time the dark comes.",
		"objectives": [{"type": "talk", "key": "calypso", "count": 1, "text": "Accept Calypso's gift"}],
		"rewards": {},
	},
]


static func any(id: String) -> Dictionary:
	var q := main_quest(id)
	if not q.is_empty():
		return q
	for l: Dictionary in LORE:
		if l["id"] == id:
			return l
	for v: String in VILLAGES:
		for s in side_quests_for(v):
			if s["id"] == id:
				return s
	return {}
