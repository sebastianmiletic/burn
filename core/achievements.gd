class_name Achievements
extends Node
## Achievements: stored per profile (PlayerProfile), unlocked in game with a
## toast (AchievementToast), listed from the main menu (ACHIEVEMENTS).
## As a node (added to the GameWorld by SpellNet) it listens to the game's
## events and unlocks what was earned; unlock() can be called from anywhere.

signal unlocked(id: String)

const CATEGORIES := ["Exploration", "Bosses", "Roles", "Ranks", "Crafting", "Glyphs", "PvP", "Secrets"]

## id -> {name, desc, cat, secret?}
const LIST := {
	"first_light": {"name": "First Light", "desc": "Discover your first place in the world.", "cat": "Exploration"},
	"wayfarer": {"name": "Wayfarer", "desc": "Discover 10 places.", "cat": "Exploration"},
	"cartographer": {"name": "Cartographer", "desc": "Discover 30 places.", "cat": "Exploration"},
	"below": {"name": "Gates Behind You", "desc": "Enter the underworld.", "cat": "Exploration"},
	"broken_sky": {"name": "Broken Sky", "desc": "Walk the Ryft.", "cat": "Exploration"},
	"slay_warden": {"name": "Crypt Breaker", "desc": "Defeat the Warden.", "cat": "Bosses"},
	"slay_mountain_king": {"name": "Kingslayer", "desc": "Defeat the Mountain King.", "cat": "Bosses"},
	"slay_dragon": {"name": "Ashvane Falls", "desc": "Defeat Ashvane the dragon.", "cat": "Bosses"},
	"slay_cerberus": {"name": "Good Dog", "desc": "Defeat Cerberus.", "cat": "Bosses"},
	"slay_hades": {"name": "Usurper", "desc": "Defeat Hades.", "cat": "Bosses"},
	"boss_hunter": {"name": "Boss Hunter", "desc": "Defeat 8 bosses (across all your runs).", "cat": "Bosses"},
	"warrior_path": {"name": "Steel", "desc": "Enter a world as a Warrior.", "cat": "Roles"},
	"archer_path": {"name": "String", "desc": "Enter a world as an Archer.", "cat": "Roles"},
	"mage_path": {"name": "Glyph", "desc": "Enter a world as a Mage.", "cat": "Roles"},
	"all_roles": {"name": "Jack of All Fires", "desc": "Play all three roles.", "cat": "Roles"},
	"rank_3": {"name": "Ember", "desc": "Reach rank 3 in any role.", "cat": "Ranks"},
	"rank_6": {"name": "Pyre", "desc": "Reach rank 6 in any role.", "cat": "Ranks"},
	"rank_9": {"name": "Eternal Flame", "desc": "Reach rank 9 in any role.", "cat": "Ranks"},
	"polymath": {"name": "Polymath", "desc": "Reach rank 3 in every role.", "cat": "Ranks"},
	"first_craft": {"name": "Maker", "desc": "Craft something.", "cat": "Crafting"},
	"artisan": {"name": "Artisan", "desc": "Craft 100 things.", "cat": "Crafting"},
	"first_brew": {"name": "Bubble and Toil", "desc": "Brew a potion in a cauldron.", "cat": "Crafting"},
	"master_brewer": {"name": "Master Brewer", "desc": "Brew every cauldron recipe.", "cat": "Crafting"},
	"scholar": {"name": "Scholar", "desc": "Read 3 books.", "cat": "Crafting"},
	"librarian": {"name": "Librarian", "desc": "Read every book.", "cat": "Crafting"},
	"first_glyph": {"name": "First Glyph", "desc": "Cast a spell by drawing its glyph.", "cat": "Glyphs"},
	"glyphwright": {"name": "Glyphwright", "desc": "Cast 200 spells.", "cat": "Glyphs"},
	"clean_hand": {"name": "Clean Hand", "desc": "Draw 25 glyphs cleanly in a row.", "cat": "Glyphs"},
	"first_blood": {"name": "First Blood", "desc": "Win a duel in a PvP arena.", "cat": "PvP"},
	"arena_victor": {"name": "Arena Victor", "desc": "Win a PvP round.", "cat": "PvP"},
	"kaboom": {"name": "Kaboom", "desc": "Blow up a cauldron.", "cat": "Secrets", "secret": true},
	"butterfingers": {"name": "Butterfingers", "desc": "Fizzle 10 glyphs.", "cat": "Secrets", "secret": true},
	"castaway": {"name": "Castaway", "desc": "Wake on Calypso's island.", "cat": "Secrets", "secret": true},
}

const BOSS_IDS := {"warden": "slay_warden", "mountain_king": "slay_mountain_king", "dragon": "slay_dragon", "cerberus": "slay_cerberus", "hades": "slay_hades"}

static var _listeners: Array[Callable] = []


## Unlock (once per profile). Returns true when newly unlocked.
static func unlock(id: String) -> bool:
	if not LIST.has(id) or not PlayerProfile.mark_achievement(id):
		return false
	for c in _listeners:
		if c.is_valid():
			c.call(id)
	AchievementToast.show_for(id)
	return true


static func listen(c: Callable) -> void:
	_listeners.append(c)


static func is_unlocked(id: String) -> bool:
	return PlayerProfile.has_achievement(id)


static func count_unlocked() -> int:
	var n := 0
	for id: String in LIST:
		if is_unlocked(id):
			n += 1
	return n


## Bump a lifetime counter and unlock achievements at thresholds.
static func progress(stat: String, amount := 1) -> void:
	var v := PlayerProfile.add_stat(stat, amount)
	match stat:
		"crafted":
			unlock("first_craft")
			if v >= 100:
				unlock("artisan")
		"spells":
			unlock("first_glyph")
			if v >= 200:
				unlock("glyphwright")
		"fizzles":
			if v >= 10:
				unlock("butterfingers")
		"bosses":
			if v >= 8:
				unlock("boss_hunter")


## Rank achievements given every role's rank.
static func check_ranks(ranks: Dictionary) -> void:
	var best := 0
	var all3 := true
	for r: String in Roles.ORDER:
		var k := int(ranks.get(r, 0))
		best = maxi(best, k)
		if k < 3:
			all3 = false
	if best >= 3:
		unlock("rank_3")
	if best >= 6:
		unlock("rank_6")
	if best >= 9:
		unlock("rank_9")
	if all3:
		unlock("polymath")


# --- In-game tracker -----------------------------------------------------------------

var world: GameWorld
var _clean_streak := 0


func _ready() -> void:
	Events.location_discovered.connect(func(_id: StringName) -> void:
		if world == null:
			return
		var n := world.discovered.size()
		unlock("first_light")
		if n >= 10:
			unlock("wayfarer")
		if n >= 30:
			unlock("cartographer"))
	Events.dimension_changed.connect(func(dim: int) -> void:
		if dim == 1:
			unlock("below")
		elif dim == 2:
			unlock("broken_sky")
		elif dim == 3:
			unlock("castaway"))
	Events.boss_defeated.connect(func(kind: String, _n: String) -> void:
		progress("bosses")
		if BOSS_IDS.has(kind):
			unlock(BOSS_IDS[kind]))


## A drawn glyph's verdict (from PlayerArcana).
func on_glyph(result: String) -> void:
	if result == "cast":
		_clean_streak += 1
		if _clean_streak >= 25:
			unlock("clean_hand")
	else:
		_clean_streak = 0
	if result in ["cast", "weak", "wrong"]:
		progress("spells")
	elif result == "fizzle":
		progress("fizzles")


static func on_role_played(role: String) -> void:
	unlock(role + "_path")
	PlayerProfile.data()["stats"]["played_" + role] = 1
	PlayerProfile.save()
	var all := true
	for r: String in Roles.ORDER:
		if PlayerProfile.stat("played_" + r) <= 0:
			all = false
	if all:
		unlock("all_roles")


static func on_books(knowledge: Dictionary) -> void:
	var n := 0
	for b: String in ArcanaItems.BOOKS:
		if knowledge.has(b):
			n += 1
	if n >= 3:
		unlock("scholar")
	if n >= ArcanaItems.BOOKS.size():
		unlock("librarian")


static func on_brew(result: Dictionary) -> void:
	match String(result.get("outcome", "")):
		"potion", "accident":
			unlock("first_brew")
			var key := "brewed_" + String(result.get("recipe", ""))
			PlayerProfile.data()["stats"][key] = 1
			PlayerProfile.save()
			var all := true
			for rid: String in Brewing.RECIPES:
				if PlayerProfile.stat("brewed_" + rid) <= 0:
					all = false
			if all:
				unlock("master_brewer")
		"explosion":
			unlock("kaboom")
