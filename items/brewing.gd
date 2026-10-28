class_name Brewing
extends RefCounted
## Cauldron brewing: a potion is a sequence of exact steps.
##   heat  {level}          0 cold, 1 low, 2 steady, 3 roaring (the last setting before the next step counts)
##   add   {item, count}    in order; adding the same thing twice in a row adds up
##   stir  {count}          consecutive stirs add up
##   wait  {seconds}        any pause of WAIT_MIN s or longer between two actions is a wait;
##                          it must be within max(WAIT_TOLERANCE_S, WAIT_TOLERANCE * wanted)
## Bottling ends the brew (one glass vial per potion made).
## Outcomes (evaluate()):
##   exact match of a recipe               -> that potion (an accidental one if you meant another)
##   right ingredients, a count/time off    -> the recipe's "near_miss" potion if it has one, else sludge
##   volatile ingredient left roaring       -> explosion (hurts, throws you back)
##   toxic ingredient in a failed brew      -> poison cloud
##   anything else                          -> sludge

const WAIT_MIN := 4.0
const WAIT_TOLERANCE := 0.25
const WAIT_TOLERANCE_S := 3.0
const HEAT_NAMES := ["cold", "low", "steady", "roaring"]
## Volatile at a roar: left longer than this at heat 3 they explode (unless the brew is exact).
const VOLATILE := ["dragon_blood", "ember_crystal"]
const VOLATILE_SECONDS := 8.0
const TOXIC := ["venom_sac", "bat_wing"]

const RECIPES := {
	"potion_mana": {"yield": 2, "near_miss": "potion_health", "steps": [
		{"do": "heat", "level": 1}, {"do": "add", "item": "emberleaf", "count": 2}, {"do": "stir", "count": 3}, {"do": "wait", "seconds": 8.0},
		{"do": "add", "item": "amethyst", "count": 1}, {"do": "heat", "level": 2}, {"do": "stir", "count": 2}, {"do": "wait", "seconds": 12.0}]},
	"potion_swiftness": {"yield": 2, "near_miss": "", "steps": [
		{"do": "heat", "level": 2}, {"do": "add", "item": "swamp_herb", "count": 2}, {"do": "add", "item": "bat_wing", "count": 1},
		{"do": "stir", "count": 4}, {"do": "wait", "seconds": 10.0}]},
	"potion_featherfall": {"yield": 2, "near_miss": "potion_swiftness", "steps": [
		{"do": "heat", "level": 1}, {"do": "add", "item": "bat_wing", "count": 2}, {"do": "stir", "count": 2}, {"do": "wait", "seconds": 6.0},
		{"do": "add", "item": "emberleaf", "count": 1}, {"do": "stir", "count": 5}, {"do": "wait", "seconds": 6.0}]},
	"potion_fireward": {"yield": 2, "near_miss": "", "steps": [
		{"do": "heat", "level": 2}, {"do": "add", "item": "frost_shard", "count": 1}, {"do": "stir", "count": 5}, {"do": "wait", "seconds": 15.0},
		{"do": "heat", "level": 1}, {"do": "add", "item": "pearl", "count": 1}, {"do": "stir", "count": 1}]},
	"elixir_everbloom": {"yield": 2, "near_miss": "potion_greater", "steps": [
		{"do": "heat", "level": 1}, {"do": "add", "item": "everbloom_leaf", "count": 2}, {"do": "wait", "seconds": 15.0},
		{"do": "add", "item": "everbloom_fruit", "count": 1}, {"do": "stir", "count": 3}, {"do": "wait", "seconds": 10.0},
		{"do": "add", "item": "everbloom_sap", "count": 1}, {"do": "stir", "count": 1}]},
	"potion_dragon_vigor": {"yield": 1, "near_miss": "", "steps": [
		{"do": "heat", "level": 3}, {"do": "add", "item": "dragon_blood", "count": 1}, {"do": "stir", "count": 6}, {"do": "wait", "seconds": 6.0},
		{"do": "heat", "level": 1}, {"do": "add", "item": "dragon_fang", "count": 1}, {"do": "stir", "count": 2}, {"do": "wait", "seconds": 20.0}]},
	"elixir_bonemarrow": {"yield": 1, "near_miss": "", "steps": [
		{"do": "heat", "level": 2}, {"do": "add", "item": "dragon_femur", "count": 1}, {"do": "stir", "count": 8}, {"do": "wait", "seconds": 25.0},
		{"do": "add", "item": "bone", "count": 3}, {"do": "heat", "level": 3}, {"do": "stir", "count": 3}, {"do": "wait", "seconds": 5.0}]},
}


## Raw actions [{do, t, ...}] -> steps in recipe form.
static func normalize(log: Array) -> Array:
	var out: Array = []
	var last_t := -1.0
	for a: Dictionary in log:
		var t := float(a.get("t", 0.0))
		if last_t >= 0.0 and t - last_t >= WAIT_MIN:
			out.append({"do": "wait", "seconds": snappedf(t - last_t, 0.1)})
		last_t = t
		var prev: Dictionary = out[out.size() - 1] if not out.is_empty() else {}
		match String(a.get("do", "")):
			"heat":
				if String(prev.get("do", "")) == "heat":
					prev["level"] = int(a.get("level", 0))
				else:
					out.append({"do": "heat", "level": int(a.get("level", 0))})
			"add":
				if String(prev.get("do", "")) == "add" and String(prev.get("item", "")) == String(a.get("item", "")):
					prev["count"] = int(prev["count"]) + int(a.get("count", 1))
				else:
					out.append({"do": "add", "item": String(a.get("item", "")), "count": int(a.get("count", 1))})
			"stir":
				if String(prev.get("do", "")) == "stir":
					prev["count"] = int(prev["count"]) + 1
				else:
					out.append({"do": "stir", "count": 1})
	# A cold first "heat 0" means nothing.
	if not out.is_empty() and String(out[0].get("do", "")) == "heat" and int(out[0]["level"]) == 0:
		out.pop_front()
	return out


static func _wait_ok(actual: float, wanted: float) -> bool:
	return absf(actual - wanted) <= maxf(WAIT_TOLERANCE_S, WAIT_TOLERANCE * wanted)


## 2 exact, 1 same skeleton (types, items, heat) with counts/times off, 0 different.
static func compare(steps: Array, recipe_steps: Array) -> int:
	if steps.size() != recipe_steps.size():
		return 0
	var exact := true
	for i in steps.size():
		var a: Dictionary = steps[i]
		var b: Dictionary = recipe_steps[i]
		if String(a["do"]) != String(b["do"]):
			return 0
		match String(b["do"]):
			"heat":
				if int(a["level"]) != int(b["level"]):
					return 0
			"add":
				if String(a["item"]) != String(b["item"]):
					return 0
				if int(a["count"]) != int(b["count"]):
					exact = false
			"stir":
				if int(a["count"]) != int(b["count"]):
					if absi(int(a["count"]) - int(b["count"])) > 2:
						return 0
					exact = false
			"wait":
				if not _wait_ok(float(a["seconds"]), float(b["seconds"])):
					if absf(float(a["seconds"]) - float(b["seconds"])) > float(b["seconds"]) * 0.75 + 4.0:
						return 0
					exact = false
	return 2 if exact else 1


## Seconds spent at heat 3 with a volatile ingredient in the pot.
static func roaring_volatile_seconds(log: Array) -> float:
	var heat := 0
	var volatile := false
	var last_t := -1.0
	var total := 0.0
	for a: Dictionary in log:
		var t := float(a.get("t", 0.0))
		if last_t >= 0.0 and heat == 3 and volatile:
			total += t - last_t
		last_t = t
		match String(a.get("do", "")):
			"heat":
				heat = int(a.get("level", 0))
			"add":
				if String(a.get("item", "")) in VOLATILE:
					volatile = true
	return total


## The whole verdict for a finished brew (log includes the bottling time as a
## final {"do": "bottle", t}). Returns {outcome, item, count, recipe, text}
##   outcome: "potion" | "accident" | "near_miss" | "explosion" | "poison" | "sludge"
static func evaluate(log: Array, intended := "") -> Dictionary:
	var steps := normalize(log)
	var added := {}
	for s: Dictionary in steps:
		if String(s["do"]) == "add":
			added[String(s["item"])] = true
	if steps.is_empty() or added.is_empty():
		return {"outcome": "sludge", "item": "", "count": 0, "recipe": "", "text": "Hot water. Nothing to bottle."}
	for rid: String in RECIPES:
		if compare(steps, RECIPES[rid]["steps"]) == 2:
			var r: Dictionary = RECIPES[rid]
			var accident := intended != "" and intended != rid
			return {"outcome": "accident" if accident else "potion", "item": rid, "count": int(r["yield"]), "recipe": rid,
				"text": ("Not what you meant, but it worked: %s." if accident else "The brew settles clear: %s.") % ItemDB.display_name(rid)}
	if roaring_volatile_seconds(log) > VOLATILE_SECONDS:
		return {"outcome": "explosion", "item": "", "count": 0, "recipe": "", "text": "The pot roars, bulges and BURSTS."}
	for rid: String in RECIPES:
		if compare(steps, RECIPES[rid]["steps"]) == 1:
			var miss := String(RECIPES[rid].get("near_miss", ""))
			if miss != "" and ItemDB.exists(miss):
				return {"outcome": "near_miss", "item": miss, "count": 1, "recipe": rid,
					"text": "Close, but not %s. It turned into %s." % [ItemDB.display_name(rid), ItemDB.display_name(miss)]}
			break
	for t: String in TOXIC:
		if added.has(t):
			return {"outcome": "poison", "item": "", "count": 0, "recipe": "", "text": "A green, choking cloud boils out of the pot."}
	return {"outcome": "sludge", "item": "brew_sludge", "count": 1, "recipe": "", "text": "The brew curdles into sludge."}


## Human-readable steps (the Codex and the brewing screen's guide).
static func step_text(step: Dictionary) -> String:
	match String(step.get("do", "")):
		"heat":
			return "Set the fire %s (%d)." % [HEAT_NAMES[clampi(int(step["level"]), 0, 3)], int(step["level"])]
		"add":
			return "Add %d %s." % [int(step["count"]), ItemDB.display_name(String(step["item"]))]
		"stir":
			return "Stir %d time%s." % [int(step["count"]), "" if int(step["count"]) == 1 else "s"]
		"wait":
			return "Wait %d seconds." % int(step["seconds"])
	return ""


static func recipe_lines(rid: String) -> PackedStringArray:
	var out := PackedStringArray()
	var r: Dictionary = RECIPES.get(rid, {})
	var i := 1
	for s: Dictionary in r.get("steps", []):
		out.append("%d. %s" % [i, step_text(s)])
		i += 1
	var steps: Array = r.get("steps", [])
	var prompt := steps.is_empty() or String((steps[steps.size() - 1] as Dictionary).get("do", "")) == "wait"
	out.append("%d. Bottle it%s (%d glass vial%s)." % [i, "" if prompt else " straight away", int(r.get("yield", 1)), "" if int(r.get("yield", 1)) == 1 else "s"])
	return out


static func ingredients(rid: String) -> Dictionary:
	var out := {}
	for s: Dictionary in RECIPES.get(rid, {}).get("steps", []):
		if String(s["do"]) == "add":
			out[String(s["item"])] = int(out.get(String(s["item"]), 0)) + int(s["count"])
	return out


## A pot over a fire: what the brewing screen drives. Times come from `now`.
class Pot:
	extends RefCounted
	var log: Array = []
	var heat := 0
	var contents := {}   # item -> count (to show what is in it)

	func is_empty() -> bool:
		return log.is_empty()

	func set_heat(level: int, now: float) -> void:
		heat = clampi(level, 0, 3)
		log.append({"do": "heat", "level": heat, "t": now})

	func add(item: String, count: int, now: float) -> void:
		log.append({"do": "add", "item": item, "count": count, "t": now})
		contents[item] = int(contents.get(item, 0)) + count

	func stir(now: float) -> void:
		log.append({"do": "stir", "t": now})

	func since_last(now: float) -> float:
		return now - float(log[log.size() - 1]["t"]) if not log.is_empty() else 0.0

	func finish(now: float, intended := "") -> Dictionary:
		log.append({"do": "bottle", "t": now})
		var result := Brewing.evaluate(log, intended)
		log.clear()
		contents.clear()
		heat = 0
		return result

	func dump() -> void:
		log.clear()
		contents.clear()
		heat = 0
