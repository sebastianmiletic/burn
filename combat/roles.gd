class_name Roles
extends RefCounted
## The three roles a character takes into a game, and each role's rank path.
##
## Ranks are per role: a character keeps one XP pool per role (Player.role_xp)
## and the rank of the role it is playing is Player.rank. Titles come from
## ItemDB.RANK_TITLES, thresholds from ItemDB.RANK_XP (deliberately steep).
## Every rank grants something: stat growth, a spell/ability (cast by drawing
## its glyph, see Spells) or a movement upgrade, and some gear asks for a rank
## ("rank_req" on items, see rank_ok()).

const DEFAULT := "warrior"

const ROLES := {
	"warrior": {"name": "Warrior", "weapon": "Sword", "resource": "Fury", "color": Color(0.95, 0.42, 0.22), "icon": "/",
		"desc": "Steel and nerve. Hits hardest up close, shrugs off blows, and learns war-glyphs that cleave and shake the ground.",
		"kit": [["sword_rusty", 1], ["pickaxe_stone", 1], ["torch", 8], ["bread", 3], ["potion_health", 2]], "gold": 10},
	"archer": {"name": "Archer", "weapon": "Bow", "resource": "Focus", "color": Color(0.55, 0.85, 0.4), "icon": ")",
		"desc": "Patience and a steady draw. Kills from range, moves like the wind, and learns volleys and arrow-rains.",
		"kit": [["bow_hunting", 1], ["pickaxe_stone", 1], ["arrow", 40], ["torch", 6], ["bread", 3], ["potion_health", 2]], "gold": 10},
	"mage": {"name": "Mage", "weapon": "Staff", "resource": "Mana", "color": Color(0.55, 0.65, 1.0), "icon": "|",
		"desc": "Glyph and ember. Fragile, but the staff spits arcane bolts and drawn glyphs call fire, frost and lightning.",
		"kit": [["staff_apprentice", 1], ["pickaxe_stone", 1], ["potion_mana", 2], ["torch", 6], ["bread", 3], ["potion_health", 2]], "gold": 10},
}

const ORDER := ["warrior", "archer", "mage"]

## Per role, per rank (index = rank 0..9): what that rank gives.
##   health / mana: added to the maximum; power: damage multiplier added (role's own weapon/spells);
##   move: movement upgrades unlocked (double_jump, dash, air_dash, wall_kick, glide);
##   swim: swim speed fraction; draw: bow draw speed fraction; regen: mana regen fraction;
##   undying: once per 5 minutes a lethal blow leaves you at 1 health; pierce: arrows pass through.
## Spells unlocked at a rank come from Spells.SPELLS[*].ranks.
const PATH := {
	"warrior": [
		{"health": 0.0, "note": "Sword, steady nerve. Glyph: Cleave."},
		{"health": 20.0, "power": 0.05, "note": "+20 health, +5% sword damage."},
		{"move": ["dash"], "note": "Dash: your roll becomes a long, fast dash (Ctrl)."},
		{"health": 20.0, "note": "+20 health. Glyph: Iron Ward."},
		{"move": ["double_jump"], "note": "Double jump: jump again in the air."},
		{"health": 20.0, "power": 0.1, "note": "+20 health, +10% sword damage. Glyph: Second Wind."},
		{"move": ["wall_kick"], "note": "Wall-kick: jump off a wall you run into while airborne."},
		{"move": ["air_dash"], "power": 0.05, "note": "Air dash: dash in mid-air. +5% sword damage."},
		{"health": 30.0, "power": 0.1, "note": "+30 health, +10% sword damage. Glyph: Whirlwind."},
		{"undying": true, "note": "Undying: once every 5 minutes a killing blow leaves you at 1 health."},
	],
	"archer": [
		{"note": "Bow and quiver. Glyph: Volley."},
		{"draw": 0.15, "note": "Draw 15% faster."},
		{"move": ["double_jump"], "note": "Double jump: jump again in the air."},
		{"power": 0.1, "health": 10.0, "note": "+10% bow damage, +10 health."},
		{"move": ["glide"], "note": "Glide: hold jump while falling to glide."},
		{"move": ["dash"], "health": 10.0, "note": "Dash: your roll becomes a long, fast dash. +10 health."},
		{"move": ["wall_kick"], "note": "Wall-kick: jump off a wall you run into while airborne."},
		{"move": ["air_dash"], "draw": 0.15, "note": "Air dash, and draw another 15% faster."},
		{"power": 0.15, "swim": 0.3, "note": "+15% bow damage, swim 30% faster."},
		{"pierce": true, "note": "Piercing arrows: fully drawn arrows pass through their first target."},
	],
	"mage": [
		{"note": "Staff and glyphs. Glyph: Fireball."},
		{"mana": 25.0, "note": "+25 mana. Glyph: Mend."},
		{"move": ["glide"], "note": "Glide: hold jump while falling to drift down on a warm draft."},
		{"power": 0.1, "note": "+10% spell power."},
		{"swim": 0.4, "health": 10.0, "note": "Swim 40% faster, +10 health. Glyph: Arcane Nova."},
		{"move": ["double_jump"], "mana": 25.0, "note": "Double jump, +25 mana. Glyph: Ward."},
		{"regen": 0.5, "note": "Mana returns 50% faster. Glyph: Chain Lightning."},
		{"move": ["air_dash"], "note": "Air dash: blink-step in mid-air (Ctrl)."},
		{"power": 0.15, "mana": 25.0, "note": "+15% spell power, +25 mana. Glyph: Meteor."},
		{"regen": 1.0, "mana": 50.0, "note": "Arcane surge: +50 mana, mana returns twice as fast."},
	],
}

const BASE_MANA := {"warrior": 60.0, "archer": 70.0, "mage": 100.0}
const BASE_MANA_REGEN := {"warrior": 4.0, "archer": 4.0, "mage": 6.0}


static func is_role(r: String) -> bool:
	return ROLES.has(r)


static func role_name(r: String) -> String:
	return String(ROLES.get(r, ROLES[DEFAULT])["name"])


static func title(rank: int) -> String:
	return ItemDB.RANK_TITLES[clampi(rank, 0, ItemDB.RANK_TITLES.size() - 1)]


## Everything the role has earned up to `rank` (inclusive), summed:
## {health, mana, power, swim, draw, regen, move: {name: true}, undying, pierce}.
static func perks(r: String, rank: int) -> Dictionary:
	var out := {"health": 0.0, "mana": 0.0, "power": 0.0, "swim": 0.0, "draw": 0.0, "regen": 0.0, "move": {}, "undying": false, "pierce": false}
	var path: Array = PATH.get(r, PATH[DEFAULT])
	for i in mini(rank + 1, path.size()):
		var p: Dictionary = path[i]
		for k: String in ["health", "mana", "power", "swim", "draw", "regen"]:
			out[k] = float(out[k]) + float(p.get(k, 0.0))
		for m: String in p.get("move", []):
			(out["move"] as Dictionary)[m] = true
		if p.get("undying", false):
			out["undying"] = true
		if p.get("pierce", false):
			out["pierce"] = true
	return out


static func has_move(r: String, rank: int, move: String) -> bool:
	return (perks(r, rank)["move"] as Dictionary).has(move)


static func max_mana(r: String, rank: int) -> float:
	return float(BASE_MANA.get(r, 60.0)) + float(perks(r, rank)["mana"])


static func mana_regen(r: String, rank: int) -> float:
	return float(BASE_MANA_REGEN.get(r, 4.0)) * (1.0 + float(perks(r, rank)["regen"]))


## The role's weapon kind(s) that its power bonus applies to.
static func weapon_kinds(r: String) -> Array:
	match r:
		"archer":
			return ["bow"]
		"mage":
			return ["staff"]
	return ["sword", "dagger", "spear", "greataxe", "warhammer", "axe"]


## Gear with a "rank_req" asks for that rank in its role (role from the item's
## kind: bows -> archer, staffs -> mage, the rest -> warrior). Other gear: always ok.
static func rank_ok(item_id: String, role_ranks: Dictionary) -> bool:
	var inf := ItemDB.info(item_id)
	var req := int(inf.get("rank_req", 0))
	if req <= 0:
		return true
	return int(role_ranks.get(role_for_item(item_id), 0)) >= req


static func role_for_item(item_id: String) -> String:
	match String(ItemDB.info(item_id).get("kind", "")):
		"bow":
			return "archer"
		"staff":
			return "mage"
	return "warrior"


## What the rank path screen shows for a rank: [title, xp needed, note, spells].
static func rank_rows(r: String) -> Array:
	var rows: Array = []
	var path: Array = PATH.get(r, PATH[DEFAULT])
	for i in path.size():
		var spells: Array = []
		for sid: String in Spells.SPELLS:
			if int((Spells.SPELLS[sid]["ranks"] as Dictionary).get(r, -1)) == i:
				spells.append(sid)
		var gear: Array = []
		for id: String in ArcanaItems.ITEMS:
			var inf: Dictionary = ArcanaItems.ITEMS[id]
			if int(inf.get("rank_req", 0)) == i and i > 0 and role_for_item(id) == r and inf.has("rank_req"):
				gear.append(id)
		rows.append({"rank": i, "title": title(i), "xp": ItemDB.RANK_XP[mini(i, ItemDB.RANK_XP.size() - 1)],
			"note": String((path[i] as Dictionary).get("note", "")), "spells": spells, "gear": gear,
			"skins": Skins.for_rank(r, i)})
	return rows
