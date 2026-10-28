class_name Skins
extends RefCounted
## Character skins / outfits: overrides merged into Models.player_style().
## Unlocked per profile (PlayerProfile) by reaching role ranks or finishing
## quests while playing a role; chosen in the lobby and replicated to everyone
## (SpellNet sends role + skin, remote players rebuild their model).
##   unlock: {"role": r, "rank": n} | {"quest": id, "role": r} | {"pvp_wins": n} | free

const DEFAULT := "wanderer"

const SKINS := {
	"wanderer": {"name": "Wanderer", "free": true, "desc": "Hood, cloak and road dust. Coloured like your place in the warband.", "style": {}},
	# Warrior
	"ember_knight": {"name": "Ember Knight", "unlock": {"role": "warrior", "rank": 3}, "desc": "Chainmail under an ember tabard.",
		"style": {"hood": false, "helmet": "nasal", "chainmail": true, "tabard": true, "cloth": Color(0.32, 0.2, 0.14), "cloth2": Color(0.78, 0.32, 0.12), "cloak": true, "cloak_color": Color(0.36, 0.14, 0.08)}},
	"iron_vanguard": {"name": "Iron Vanguard", "unlock": {"role": "warrior", "rank": 6}, "desc": "Full plate, pauldrons and a war cape.",
		"style": {"hood": false, "helmet": "kettle", "plate": true, "pauldrons": true, "cloak": false, "cape": true, "cloth": Color(0.25, 0.25, 0.27), "cloth2": Color(0.6, 0.58, 0.55)}},
	"phoenix_champion": {"name": "Phoenix Champion", "unlock": {"role": "warrior", "rank": 9}, "desc": "Gilded plate and a crown of living flame.",
		"style": {"hood": false, "plate": true, "pauldrons": true, "cape": true, "cloak": false, "crown": Color(1.0, 0.55, 0.15), "cloth": Color(0.42, 0.16, 0.08), "cloth2": Color(0.95, 0.68, 0.22)}},
	# Archer
	"ranger": {"name": "Greenwood Ranger", "unlock": {"role": "archer", "rank": 3}, "desc": "Moss-green hood and leather bracers.",
		"style": {"hood": true, "bracers": true, "cloth": Color(0.22, 0.3, 0.18), "cloth2": Color(0.42, 0.55, 0.26), "cloak": true, "cloak_color": Color(0.2, 0.27, 0.16)}},
	"shadow_stalker": {"name": "Shadow Stalker", "unlock": {"role": "archer", "rank": 6}, "desc": "Soot-black leathers that drink the light.",
		"style": {"hood": true, "bracers": true, "sash": true, "cloth": Color(0.09, 0.09, 0.1), "cloth2": Color(0.28, 0.24, 0.3), "cloak": true, "cloak_color": Color(0.07, 0.07, 0.08)}},
	"sky_warden": {"name": "Sky Warden", "unlock": {"role": "archer", "rank": 9}, "desc": "Storm-blue cape and a heron's plume.",
		"style": {"hood": false, "helmet": "nasal", "plume": true, "cape": true, "cloak": false, "bracers": "metal", "cloth": Color(0.2, 0.26, 0.38), "cloth2": Color(0.6, 0.72, 0.9)}},
	# Mage
	"acolyte": {"name": "Ember Acolyte", "unlock": {"role": "mage", "rank": 3}, "desc": "A scholar's robe and a pointed hat.",
		"style": {"hood": false, "robe": true, "hat": "pointed", "cloth": Color(0.3, 0.16, 0.12), "cloth2": Color(0.7, 0.4, 0.18), "cloak": false}},
	"stormcaller": {"name": "Stormcaller", "unlock": {"role": "mage", "rank": 6}, "desc": "Violet robes stitched with lightning.",
		"style": {"hood": true, "robe": true, "sash": true, "cloth": Color(0.22, 0.16, 0.34), "cloth2": Color(0.55, 0.45, 0.9), "cloak": true, "cloak_color": Color(0.16, 0.12, 0.26)}},
	"archmagus": {"name": "Archmagus", "unlock": {"role": "mage", "rank": 9}, "desc": "White robes, a cape of night and a crown of cold fire.",
		"style": {"hood": false, "robe": true, "cape": true, "cloak": false, "crown": Color(0.5, 0.75, 1.0), "cloth": Color(0.8, 0.78, 0.74), "cloth2": Color(0.3, 0.4, 0.75)}},
	# Quests with a role
	"wardens_bane": {"name": "Warden's Bane", "unlock": {"quest": "silent_crypt", "role": "warrior"}, "desc": "Finish The Silent Crypt as a Warrior.",
		"style": {"hood": false, "helmet": "kettle", "chainmail": true, "pauldrons": true, "cloth": Color(0.2, 0.22, 0.2), "cloth2": Color(0.5, 0.6, 0.45)}},
	"dragonstalker": {"name": "Dragonstalker", "unlock": {"quest": "ashvane", "role": "archer"}, "desc": "Slay Ashvane as an Archer.",
		"style": {"hood": true, "bracers": "metal", "cloth": Color(0.4, 0.12, 0.08), "cloth2": Color(0.9, 0.5, 0.2), "cloak": true, "cloak_color": Color(0.3, 0.08, 0.05)}},
	"hadesbane": {"name": "Hadesbane", "unlock": {"quest": "throne", "role": "mage"}, "desc": "Overthrow Hades as a Mage.",
		"style": {"hood": false, "robe": true, "crown": Color(0.45, 1.0, 0.7), "cape": true, "cloak": false, "cloth": Color(0.1, 0.12, 0.12), "cloth2": Color(0.3, 0.8, 0.6)}},
	# PvP
	"arena_champion": {"name": "Arena Champion", "unlock": {"pvp_wins": 1}, "desc": "Win a PvP round.",
		"style": {"hood": false, "helmet": "nasal", "tabard": true, "cape": true, "cloak": false, "cloth": Color(0.5, 0.42, 0.12), "cloth2": Color(0.95, 0.85, 0.4)}},
}


static func display_name(id: String) -> String:
	return String(SKINS.get(id, SKINS[DEFAULT])["name"])


## The player model style for a skin over the base (player colour) style.
static func style(skin_id: String, colour_index: int, torch_shadows := true) -> Dictionary:
	var st := Models.player_style(colour_index, torch_shadows)
	var s: Dictionary = SKINS.get(skin_id, SKINS[DEFAULT])
	st.merge(s.get("style", {}), true)
	return st


static func unlock_text(id: String) -> String:
	var s: Dictionary = SKINS.get(id, {})
	if s.get("free", false):
		return "Always yours."
	var u: Dictionary = s.get("unlock", {})
	if u.has("rank"):
		return "Reach rank %d (%s) as a %s." % [int(u["rank"]), Roles.title(int(u["rank"])), Roles.role_name(String(u["role"]))]
	if u.has("quest"):
		return String(s.get("desc", ""))
	if u.has("pvp_wins"):
		return "Win %d PvP round%s." % [int(u["pvp_wins"]), "" if int(u["pvp_wins"]) == 1 else "s"]
	return ""


static func for_rank(role: String, rank: int) -> Array:
	var out: Array = []
	for id: String in SKINS:
		var u: Dictionary = SKINS[id].get("unlock", {})
		if String(u.get("role", "")) == role and int(u.get("rank", -1)) == rank:
			out.append(id)
	return out


## Skins earned by reaching `rank` in `role` (and every rank below).
static func earned_by_rank(role: String, rank: int) -> Array:
	var out: Array = []
	for id: String in SKINS:
		var u: Dictionary = SKINS[id].get("unlock", {})
		if String(u.get("role", "")) == role and u.has("rank") and rank >= int(u["rank"]):
			out.append(id)
	return out


static func earned_by_quest(quest_id: String, role: String) -> Array:
	var out: Array = []
	for id: String in SKINS:
		var u: Dictionary = SKINS[id].get("unlock", {})
		if String(u.get("quest", "")) == quest_id and String(u.get("role", "")) == role:
			out.append(id)
	return out
