class_name FishingDB
extends RefCounted
## What bites where: pure functions of the water (sea biome, fresh water by
## land biome, underground pools), the hour, the depth under the bobber, the
## rod's tier and the bait carried. Also the reel-in fight (ReelFight), so
## the whole of fishing's game logic is testable without a scene.
##
## Context dictionary (FishingSession.context()):
##   water "sea" | "fresh" | "cave", biome (WorldGen.Biome), sea (WorldGen.Sea),
##   hour 0..24, depth (m of water under the bobber), tier 1..5, bait 0..3,
##   rain (bool).

const B = WorldGen.Biome
const S = WorldGen.Sea

## [id, weight, min rod tier, conditions]
## conditions: water (Array), biomes / seas (Array, any if absent), time
## ("day" | "night" | "twilight"), depth (min metres).
const FISH := [
	["fish_perch", 1.0, 1, {"water": ["fresh"], "time": "day"}],
	["fish_perch", 0.4, 1, {"water": ["fresh"]}],
	["fish_carp", 0.8, 1, {"water": ["fresh"], "time": "day", "biomes": [B.PLAINS, B.FOREST, B.MARSH, B.REDWOOD]}],
	["fish_trout", 1.0, 1, {"water": ["fresh"], "biomes": [B.PEAKS, B.ALPINE, B.TUNDRA, B.FJORD, B.FOREST, B.REDWOOD]}],
	["fish_catfish", 0.9, 1, {"water": ["fresh"], "time": "night", "biomes": [B.MARSH, B.PLAINS, B.FOREST]}],
	["fish_pike", 0.6, 2, {"water": ["fresh"], "time": "twilight"}],
	["fish_pike", 0.3, 2, {"water": ["fresh"], "biomes": [B.MARSH]}],
	["fish_eel", 0.7, 1, {"water": ["fresh", "sea"], "time": "night", "biomes": [B.MARSH, B.OCEAN, B.FJORD]}],
	["fish_herring", 1.0, 1, {"water": ["sea"]}],
	["fish_mackerel", 0.9, 1, {"water": ["sea"], "seas": [S.NONE, S.GREY, S.SHELF, S.REEF, S.SEAGRASS, S.KELP]}],
	["fish_cod", 0.7, 2, {"water": ["sea"], "seas": [S.NONE, S.GREY, S.SHELF, S.KELP, S.FROZEN], "depth": 3.0}],
	["fish_salmon", 0.6, 2, {"water": ["sea", "fresh"], "biomes": [B.FJORD, B.TUNDRA, B.ALPINE, B.OCEAN], "seas": [S.NONE, S.GREY, S.SHELF, S.KELP, S.FROZEN]}],
	["fish_bass", 0.7, 2, {"water": ["sea"], "seas": [S.REEF, S.SEAGRASS, S.SHELF]}],
	["fish_tuna", 0.45, 3, {"water": ["sea"], "depth": 8.0}],
	["fish_frostfin", 0.5, 3, {"water": ["sea", "fresh"], "seas": [S.FROZEN, S.NONE], "biomes": [B.TUNDRA, B.OCEAN, B.FJORD, B.PEAKS, B.ALPINE]}],
	["fish_ember_eel", 0.5, 3, {"water": ["sea"], "seas": [S.VENTS]}],
	["fish_glowfin", 1.0, 2, {"water": ["cave"]}],
	["fish_eel", 0.4, 1, {"water": ["cave"]}],
	["fish_swordfish", 0.25, 4, {"water": ["sea"], "depth": 12.0, "time": "day"}],
	["fish_golden_koi", 0.035, 3, {"water": ["fresh"], "time": "day"}],
	["fish_ghost_carp", 0.05, 2, {"water": ["fresh", "cave"], "time": "night"}],
	["fish_abyssal_angler", 0.12, 5, {"water": ["sea"], "seas": [S.ABYSS, S.MAELSTROM], "depth": 16.0}],
	["fish_abyssal_angler", 0.03, 5, {"water": ["sea"], "time": "night", "depth": 10.0}],
]

const JUNK := [["old_boot", 1.0], ["driftwood", 1.4], ["tangled_net", 0.7], ["seaweed", 1.2]]
const TREASURE := [["bottled_letter", 1.0], ["sunken_coffer", 0.7], ["pearl", 0.5], ["ancient_coin", 0.6], ["treasure_map", 0.25], ["tide_pearl", 0.06]]

## Fight feel per fish: [pull strength, surge rate, stamina (seconds of reeling)].
const FIGHT := {
	"fish_perch": [0.35, 0.5, 2.5], "fish_carp": [0.45, 0.4, 3.5], "fish_trout": [0.5, 0.8, 3.0], "fish_catfish": [0.55, 0.5, 4.0],
	"fish_pike": [0.7, 1.0, 5.0], "fish_eel": [0.55, 1.3, 4.0], "fish_herring": [0.3, 0.7, 2.0], "fish_mackerel": [0.4, 0.9, 2.5],
	"fish_cod": [0.6, 0.6, 5.0], "fish_salmon": [0.75, 1.1, 6.0], "fish_bass": [0.65, 0.8, 5.0], "fish_tuna": [0.85, 1.0, 8.0],
	"fish_frostfin": [0.8, 1.2, 7.0], "fish_ember_eel": [0.8, 1.5, 7.0], "fish_glowfin": [0.5, 1.0, 3.5], "fish_swordfish": [0.95, 1.4, 10.0],
	"fish_golden_koi": [0.7, 1.3, 7.0], "fish_ghost_carp": [0.7, 1.2, 6.5], "fish_abyssal_angler": [1.0, 1.6, 12.0],
}


static func time_band(hour: float) -> String:
	if (hour >= 5.0 and hour < 7.5) or (hour >= 18.0 and hour < 20.5):
		return "twilight"
	return "day" if hour >= 7.5 and hour < 18.0 else "night"


static func _matches(cond: Dictionary, ctx: Dictionary) -> bool:
	if not (cond.get("water", ["fresh"]) as Array).has(String(ctx.get("water", "fresh"))):
		return false
	var band := time_band(float(ctx.get("hour", 12.0)))
	if cond.has("time"):
		var want := String(cond["time"])
		# Twilight counts for both: fish change shifts at dawn and dusk.
		if want != band and band != "twilight":
			return false
		if want == "twilight" and band != "twilight":
			return false
	if float(ctx.get("depth", 2.0)) < float(cond.get("depth", 0.0)):
		return false
	var water := String(ctx.get("water", "fresh"))
	if water == "sea" and cond.has("seas") and int(ctx.get("sea", 0)) != S.NONE:
		if not (cond["seas"] as Array).has(int(ctx.get("sea", 0))):
			return false
	if cond.has("biomes") and water != "cave":
		var biome := int(ctx.get("biome", B.PLAINS))
		if not (cond["biomes"] as Array).has(biome):
			# Sea fish restricted by sea biome only are fine anywhere on a matching sea.
			if not (water == "sea" and cond.has("seas")):
				return false
	return true


## Fish that can bite here with this rod (weights), rarer ones favoured by bait.
static func candidates(ctx: Dictionary) -> Array:
	var out: Array = []
	var tier := int(ctx.get("tier", 1))
	var bait := int(ctx.get("bait", 0))
	for f: Array in FISH:
		if int(f[2]) > tier or not _matches(f[3], ctx):
			continue
		var w := float(f[1])
		var rarity := ItemDB.rarity(String(f[0]))
		w *= 1.0 + 0.35 * bait * rarity
		out.append([f[0], w])
	return out


## Chance the catch is junk / treasure instead of a fish.
static func junk_chance(ctx: Dictionary) -> float:
	return clampf(0.14 - 0.02 * int(ctx.get("tier", 1)) - 0.02 * int(ctx.get("bait", 0)), 0.03, 0.2)


static func treasure_chance(ctx: Dictionary) -> float:
	var c := 0.025 + 0.012 * int(ctx.get("tier", 1)) + 0.01 * int(ctx.get("bait", 0))
	if String(ctx.get("water", "")) == "sea":
		c += 0.015
	return c


static func _pick(table: Array, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for e: Array in table:
		total += float(e[1])
	if total <= 0.0:
		return ""
	var r := rng.randf() * total
	for e: Array in table:
		r -= float(e[1])
		if r <= 0.0:
			return String(e[0])
	return String(table[table.size() - 1][0])


## What is on the hook: a fish id, a junk id or a treasure id.
static func roll(ctx: Dictionary, rng: RandomNumberGenerator) -> String:
	var t := rng.randf()
	if t < treasure_chance(ctx):
		return _pick(TREASURE, rng)
	if t < treasure_chance(ctx) + junk_chance(ctx):
		return _pick(JUNK, rng)
	var fish := candidates(ctx)
	if fish.is_empty():
		return _pick(JUNK, rng)
	return _pick(fish, rng)


## Seconds until something bites: bait and a better rod shorten the wait,
## rain and twilight stir the fish.
static func bite_delay(ctx: Dictionary, rng: RandomNumberGenerator) -> float:
	var d := rng.randf_range(6.0, 17.0)
	d *= [1.0, 0.75, 0.6, 0.5][clampi(int(ctx.get("bait", 0)), 0, 3)]
	d *= 1.0 - 0.05 * (int(ctx.get("tier", 1)) - 1)
	if bool(ctx.get("rain", false)):
		d *= 0.8
	if time_band(float(ctx.get("hour", 12.0))) == "twilight":
		d *= 0.85
	return maxf(2.0, d)


static func is_fish(id: String) -> bool:
	return FIGHT.has(id)


## Rod handling: line strength (tension the line takes) and reel speed.
static func rod_stats(tier: int) -> Dictionary:
	tier = clampi(tier, 1, 5)
	return {"strength": 1.0 + 0.12 * (tier - 1), "reel": 0.18 + 0.03 * (tier - 1), "cast": 13.0 + 3.0 * tier}


## The reel-in fight. Hold to reel: the line closes in but tension rises;
## the fish surges (tension spikes, it takes line). Let tension pass the
## line's strength and it snaps; let the line go slack too long and the
## hook slips. Junk and treasure come in heavy but calm.
class ReelFight:
	extends RefCounted
	var item := ""
	var distance := 1.0      ## 1 = at the bobber, 0 = landed
	var tension := 0.3       ## 0..strength
	var strength := 1.0
	var reel := 0.2
	var pull := 0.4
	var surge_rate := 0.6
	var stamina := 3.0
	var surging := 0.0
	var slack_t := 0.0
	var result := ""         ## "" while fighting, "caught", "snapped", "slipped"
	var _rng := RandomNumberGenerator.new()
	var _surge_cd := 1.0

	func _init(item_id: String, rod_tier: int, seed_value := 0) -> void:
		item = item_id
		var rs := FishingDB.rod_stats(rod_tier)
		strength = float(rs["strength"])
		reel = float(rs["reel"])
		var f: Array = FishingDB.FIGHT.get(item_id, [0.3, 0.15, 2.0])
		pull = float(f[0])
		surge_rate = float(f[1])
		stamina = float(f[2])
		_rng.seed = seed_value if seed_value != 0 else hash(item_id) ^ Time.get_ticks_usec()
		_surge_cd = _rng.randf_range(0.6, 1.6)

	## Advance; `reeling` = the player is holding the reel button.
	func step(delta: float, reeling: bool) -> String:
		if result != "":
			return result
		var tired := clampf(stamina / 6.0, 0.15, 1.0)
		# The fish surges now and then (more often when fresh).
		_surge_cd -= delta * surge_rate * (0.5 + tired)
		if _surge_cd <= 0.0 and surging <= 0.0:
			surging = _rng.randf_range(0.5, 1.2)
			_surge_cd = _rng.randf_range(0.8, 2.2)
		var surge := 1.0 if surging > 0.0 else 0.0
		surging = maxf(0.0, surging - delta)
		if reeling:
			tension += delta * (0.32 + pull * 0.9 * tired + surge * pull * 1.6)
			distance -= delta * reel * (1.0 - 0.6 * surge) * (1.25 - 0.5 * pull * tired)
			stamina = maxf(0.0, stamina - delta * (1.0 + surge))
		else:
			tension -= delta * (0.55 - surge * pull * 0.45)
			distance += delta * pull * 0.08 * surge * tired
		tension = clampf(tension, 0.0, strength * 1.2)
		distance = clampf(distance, 0.0, 1.0)
		if tension >= strength:
			result = "snapped"
		elif distance <= 0.0:
			result = "caught"
		else:
			slack_t = slack_t + delta if tension < 0.06 else 0.0
			if slack_t > 1.8:
				result = "slipped"
		return result
