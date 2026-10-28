class_name Spells
extends RefCounted
## Spells and role abilities. Every one is cast by drawing its glyph (hold the
## cast key, draw with the mouse, release; see PlayerArcana). How well the
## glyph matched decides the outcome:
##   clean (score >= CLEAN)  full power
##   shaky (>= SHAKY)        weaker; if another glyph you know was nearly as
##                           close, the wrong spell may go off instead
##   below                   fizzle (some of the mana is lost)
## ranks: role -> rank at which that role learns it. book: a book that must
## have been read first (its knowledge, see Codex), or "".
## Damage/heal scale with Roles power and rank; the server applies them (SpellNet).

const CLEAN := 0.78
const SHAKY := 0.6
const SHAKY_POWER := 0.55
const FIZZLE_COST := 0.35

const SPELLS := {
	# --- Warrior --------------------------------------------------------------------
	"cleave": {"name": "Cleave", "glyph": "caret", "ranks": {"warrior": 0}, "book": "", "mana": 20.0, "cooldown": 5.0,
		"kind": "melee_arc", "power": 26.0, "radius": 4.2,
		"desc": "A sweeping strike that hits everything in a wide arc before you."},
	"war_cry": {"name": "War Cry", "glyph": "vee", "ranks": {"warrior": 2}, "book": "", "mana": 30.0, "cooldown": 30.0,
		"kind": "buff_allies", "buff": "might", "seconds": 20.0, "radius": 12.0,
		"desc": "You and companions near you hit 25% harder for 20 seconds."},
	"ward": {"name": "Iron Ward", "glyph": "square", "ranks": {"warrior": 3, "mage": 5}, "book": "book_spells_novice", "mana": 35.0, "cooldown": 25.0,
		"kind": "buff_self", "buff": "ward", "seconds": 10.0,
		"desc": "A shell of force: +60 defence for 10 seconds."},
	"second_wind": {"name": "Second Wind", "glyph": "circle", "ranks": {"warrior": 5}, "book": "", "mana": 40.0, "cooldown": 40.0,
		"kind": "heal", "power": 0.35, "radius": 0.0,
		"desc": "Catch your breath: restore 35% of your health."},
	"earthshatter": {"name": "Earthshatter", "glyph": "zigzag", "ranks": {"warrior": 6}, "book": "book_spells_adept", "mana": 45.0, "cooldown": 18.0,
		"kind": "nova", "power": 38.0, "radius": 6.5, "fx": "earth",
		"desc": "Slam the ground: damage and hurl back everything around you."},
	"whirlwind": {"name": "Whirlwind", "glyph": "spiral", "ranks": {"warrior": 8}, "book": "book_spells_master", "mana": 55.0, "cooldown": 22.0,
		"kind": "nova", "power": 70.0, "radius": 5.0, "fx": "steel",
		"desc": "Spin with your blade out: heavy damage to everything within reach."},
	# --- Archer ----------------------------------------------------------------------
	"volley": {"name": "Volley", "glyph": "triangle", "ranks": {"archer": 0}, "book": "", "mana": 25.0, "cooldown": 6.0,
		"kind": "volley", "power": 14.0, "count": 5,
		"desc": "Loose five arrows in a fan (no arrows used)."},
	"frost_lance": {"name": "Frost Lance", "glyph": "caret", "ranks": {"archer": 2, "mage": 2}, "book": "book_spells_novice", "mana": 22.0, "cooldown": 3.0,
		"kind": "projectile", "projectile": "frost_lance", "power": 30.0, "speed": 34.0,
		"desc": "A spear of ice that flies straight and hits hard."},
	"blink": {"name": "Blink", "glyph": "wave", "ranks": {"archer": 3, "mage": 3}, "book": "book_spells_novice", "mana": 30.0, "cooldown": 8.0,
		"kind": "blink", "range": 14.0,
		"desc": "Step through the air to where you look (up to 14 m)."},
	"mend": {"name": "Mend", "glyph": "vee", "ranks": {"archer": 5, "mage": 1}, "book": "", "mana": 35.0, "cooldown": 14.0,
		"kind": "heal", "power": 0.3, "radius": 8.0,
		"desc": "Warm light restores 30% health to you and companions near you."},
	"rain_of_arrows": {"name": "Rain of Arrows", "glyph": "spiral", "ranks": {"archer": 7}, "book": "book_spells_adept", "mana": 50.0, "cooldown": 20.0,
		"kind": "rain", "power": 16.0, "radius": 5.0, "count": 14,
		"desc": "Arrows fall from the sky where you aim."},
	"chain_lightning": {"name": "Chain Lightning", "glyph": "zigzag", "ranks": {"archer": 9, "mage": 6}, "book": "book_spells_adept", "mana": 40.0, "cooldown": 9.0,
		"kind": "chain", "power": 34.0, "range": 22.0, "jumps": 4,
		"desc": "Lightning leaps from your target to four more nearby."},
	# --- Mage ------------------------------------------------------------------------
	"fireball": {"name": "Fireball", "glyph": "circle", "ranks": {"mage": 0}, "book": "", "mana": 18.0, "cooldown": 2.5,
		"kind": "projectile", "projectile": "player_fireball", "power": 24.0, "speed": 26.0,
		"desc": "The first glyph every mage learns. Explodes on impact."},
	"arcane_nova": {"name": "Arcane Nova", "glyph": "triangle", "ranks": {"mage": 4}, "book": "book_spells_adept", "mana": 40.0, "cooldown": 12.0,
		"kind": "nova", "power": 34.0, "radius": 7.0, "fx": "arcane",
		"desc": "A ring of force bursts out from you."},
	"meteor": {"name": "Meteor", "glyph": "spiral", "ranks": {"mage": 8}, "book": "book_spells_master", "mana": 70.0, "cooldown": 30.0,
		"kind": "meteor", "power": 90.0, "radius": 5.0,
		"desc": "Call a burning stone down on where you aim."},
	# --- Every role, from books ------------------------------------------------------
	"veil": {"name": "Veil", "glyph": "veil", "ranks": {"warrior": 4, "archer": 4, "mage": 3}, "book": "book_spells_adept", "mana": 45.0, "cooldown": 45.0,
		"kind": "buff_self", "buff": "invisible", "seconds": 15.0,
		"desc": "Invisibility: monsters lose sight of you until it fades or you strike."},
	"flight": {"name": "Flight", "glyph": "rise", "ranks": {"warrior": 7, "archer": 6, "mage": 5}, "book": "book_spells_master", "mana": 60.0, "cooldown": 60.0,
		"kind": "buff_self", "buff": "flight", "seconds": 12.0,
		"desc": "Fly: hold jump to climb, sprint to dive, and you never take fall damage while it lasts."},
}


## Spells this role knows at `rank`, given the books it has read (knowledge ids).
static func known(role: String, rank: int, knowledge: Dictionary) -> Array:
	var out: Array = []
	for id: String in SPELLS:
		if can_cast(id, role, rank, knowledge):
			out.append(id)
	return out


static func can_cast(id: String, role: String, rank: int, knowledge: Dictionary) -> bool:
	var s: Dictionary = SPELLS.get(id, {})
	if s.is_empty():
		return false
	var r: Dictionary = s["ranks"]
	if not r.has(role) or rank < int(r[role]):
		return false
	var book := String(s.get("book", ""))
	return book == "" or knowledge.has(book)


## The role's spell for a glyph (each role has at most one spell per glyph).
static func for_glyph(role: String, glyph: String) -> String:
	for id: String in SPELLS:
		if String(SPELLS[id]["glyph"]) == glyph and (SPELLS[id]["ranks"] as Dictionary).has(role):
			return id
	return ""


## Spells that a role can ever learn, in rank order.
static func for_role(role: String) -> Array:
	var out: Array = []
	for id: String in SPELLS:
		if (SPELLS[id]["ranks"] as Dictionary).has(role):
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool: return int(SPELLS[a]["ranks"][role]) < int(SPELLS[b]["ranks"][role]))
	return out


## Decide what a drawn glyph does.
##   recognition: GlyphRecognizer.recognize() result. known: spell ids the caster knows.
## Returns {result: "cast"|"weak"|"wrong"|"fizzle"|"unknown", spell, power (0..1), text}
static func resolve(role: String, recognition: Dictionary, known_spells: Array) -> Dictionary:
	var score := float(recognition.get("score", 0.0))
	var glyph := String(recognition.get("glyph", ""))
	if not bool(recognition.get("valid", false)) or score < SHAKY:
		return {"result": "fizzle", "spell": "", "power": 0.0, "text": "The glyph falls apart. It fizzles."}
	var spell := for_glyph(role, glyph)
	if spell == "" or not spell in known_spells:
		return {"result": "unknown", "spell": "", "power": 0.0,
			"text": "You drew a %s, but it means nothing to you yet." % String(GlyphRecognizer.GLYPHS.get(glyph, {}).get("name", glyph)).to_lower()}
	if score >= CLEAN:
		return {"result": "cast", "spell": spell, "power": 1.0, "text": ""}
	# Shaky: a nearly-as-good other glyph you also know can go off instead.
	var second := String(recognition.get("second", ""))
	var other := for_glyph(role, second)
	if other != "" and other in known_spells and score - float(recognition.get("second_score", 0.0)) < 0.05:
		return {"result": "wrong", "spell": other, "power": SHAKY_POWER, "text": "Your hand slips: %s goes off instead." % String(SPELLS[other]["name"])}
	return {"result": "weak", "spell": spell, "power": SHAKY_POWER, "text": "A shaky glyph: %s comes out weak." % String(SPELLS[spell]["name"])}


static func glyph_name(glyph: String) -> String:
	return String(GlyphRecognizer.GLYPHS.get(glyph, {}).get("name", glyph))
