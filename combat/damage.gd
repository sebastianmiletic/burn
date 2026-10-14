class_name Damage
extends RefCounted
## Damage maths shared by players, monsters and bosses. Pure functions so the
## numbers are testable and identical on every machine.

const CRIT_CHANCE := 0.1
const CRIT_MULT := 1.75
const FIST_DAMAGE := 3.0
const BURN_TICK := 0.5        ## seconds between burn ticks
const BURN_SECONDS := 3.0     ## how long a fire hit keeps burning

## Fraction of damage resisted per creature and damage kind (negative = weakness).
const RESIST := {
	"skeleton": {"hit": 0.0, "fire": -0.25},
	"archer": {"hit": 0.0, "fire": -0.25},
	"ghoul": {"hit": 0.0, "fire": -0.4},
	"troll": {"hit": 0.2, "fire": -0.3},
	"imp": {"hit": 0.0, "fire": 0.85},
	"shade": {"hit": 0.35, "fire": -0.2},
	"warden": {"hit": 0.15, "fire": -0.2},
	"mountain_king": {"hit": 0.2, "fire": -0.35},
	"dragon": {"hit": 0.15, "fire": 0.8},
	"cerberus": {"hit": 0.1, "fire": 0.7},
	"hades": {"hit": 0.2, "fire": 0.5},
	"player": {"hit": 0.0, "fire": 0.0},
}

## Ability base damage before rank scaling.
const ABILITIES := {"player_fireball": 24.0, "burst": 32.0}


static func rank_multiplier(rank: int) -> float:
	return 1.0 + 0.07 * maxi(0, rank)


static func weapon_base(item_id: String) -> float:
	var info := ItemDB.info(item_id)
	if info.is_empty():
		return FIST_DAMAGE
	return float(info.get("damage", FIST_DAMAGE))


## A player's melee hit. `roll` in 0..1 (random) decides the crit.
## Returns {amount, crit, kind, burn} where burn is damage per second for BURN_SECONDS.
static func melee(item_id: String, rank: int, roll: float) -> Dictionary:
	var amount := weapon_base(item_id) * rank_multiplier(rank)
	var crit := roll < CRIT_CHANCE
	if crit:
		amount *= CRIT_MULT
	var info := ItemDB.info(item_id)
	var burn := float(info.get("burn", 0.0))
	return {"amount": amount, "crit": crit, "kind": "fire" if burn > 0.0 else "hit", "burn": burn}


static func ability(name: String, rank: int) -> float:
	return float(ABILITIES.get(name, 0.0)) * rank_multiplier(rank)


static func resist(target_kind: String, damage_kind: String) -> float:
	return float(RESIST.get(target_kind, {}).get(damage_kind, 0.0))


## Damage after the target's resistances. Never negative.
static func apply(amount: float, target_kind: String, damage_kind: String) -> float:
	return maxf(0.0, amount * (1.0 - resist(target_kind, damage_kind)))


## Monster / boss outgoing damage.
static func monster(base: float, enraged: bool, party_size := 1) -> float:
	var m := 1.5 if enraged else 1.0
	return base * m * (1.0 + 0.1 * maxi(0, party_size - 1))


## Boss health scales with the number of players fighting it.
static func boss_health(base: float, players: int) -> float:
	return base * (1.0 + 0.65 * maxi(0, players - 1))


## Total damage a burn deals over its whole duration.
static func burn_total(dps: float) -> float:
	return dps * BURN_SECONDS


## Damage of one burn tick.
static func burn_tick(dps: float) -> float:
	return dps * BURN_TICK
