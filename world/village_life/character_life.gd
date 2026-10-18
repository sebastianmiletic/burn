class_name CharacterLife
extends RefCounted
## What a character carries between sessions besides their pack: standing
## with each village (reputation), what each villager has left to sell or
## still wants to buy today (stock restocks over days), tamed pets, and the
## fishing log. Saved inside the character (Player.to_dict "life"), so a
## guest brings their pets and reputation into a host's world.
##
## Reputation per village: trades raise it (1 point per 12 gold of business,
## capped per day), angering a villager drops it. Tiers unlock better offers
## and prices (Trading).

const TIERS := [[-1000, "Distrusted"], [0, "Stranger"], [15, "Familiar"], [45, "Friend"], [100, "Honoured"]]
const DAILY_REP_CAP := 12

var reputation := {}      ## village id -> int
var rep_today := {}       ## village id -> [day, points earned that day]
var stock := {}           ## villager key -> {"day": int, "sold": {item: n}, "bought": {item: n}}
var pets: Array = []      ## [{uid, kind, name, variant, mode}]
var fish_log := {}        ## item id -> count caught
var _next_uid := 1


## The local character's record (kept on the Player node).
static func of(player: Object) -> CharacterLife:
	if player == null:
		return CharacterLife.new()
	if not player.has_meta("character_life"):
		player.set_meta("character_life", CharacterLife.new())
	return player.get_meta("character_life") as CharacterLife


# --- Reputation --------------------------------------------------------------------------

func rep(village: String) -> int:
	return int(reputation.get(village, 0))


## 0 Distrusted, 1 Stranger, 2 Familiar, 3 Friend, 4 Honoured.
func tier(village: String) -> int:
	return tier_for(rep(village))


static func tier_for(points: int) -> int:
	var t := 0
	for i in TIERS.size():
		if points >= int(TIERS[i][0]):
			t = i
	return t


static func tier_name(t: int) -> String:
	return String(TIERS[clampi(t, 0, TIERS.size() - 1)][1])


## Points to the next tier (0 at the top).
func to_next(village: String) -> int:
	var t := tier(village)
	if t >= TIERS.size() - 1:
		return 0
	return int(TIERS[t + 1][0]) - rep(village)


func add_rep(village: String, points: int) -> void:
	if village == "" or points == 0:
		return
	var before := tier(village)
	reputation[village] = clampi(rep(village) + points, -200, 999)
	var after := tier(village)
	if after > before:
		Events.notify.emit("%s now calls you %s." % [village.capitalize(), tier_name(after)], "quest")
	elif after < before:
		Events.notify.emit("%s now thinks you %s." % [village.capitalize(), tier_name(after).to_lower()], "warn")


## Business done: reputation from gold traded, at most DAILY_REP_CAP a day.
func trade_rep(village: String, gold: int, day: int) -> void:
	var rec: Array = rep_today.get(village, [day, 0])
	if int(rec[0]) != day:
		rec = [day, 0]
	var carry := (float(rec[2]) if rec.size() > 2 else 0.0) + gold / 12.0
	var pts := mini(int(carry), DAILY_REP_CAP - int(rec[1]))
	if pts > 0:
		add_rep(village, pts)
		rec[1] = int(rec[1]) + pts
	rec.resize(3)
	rec[2] = carry - float(int(carry))
	rep_today[village] = rec


# --- Stock ------------------------------------------------------------------------------

func _stock(key: String, day: int, restock: Callable) -> Dictionary:
	var s: Dictionary = stock.get(key, {"day": day, "sold": {}, "bought": {}})
	var days := day - int(s.get("day", day))
	if days > 0:
		# Restock: each day brings back half of a full shelf, and the villager wants more again.
		for kind: String in ["sold", "bought"]:
			var d: Dictionary = s.get(kind, {})
			for item: String in d.keys():
				var full := int(restock.call(kind, item))
				d[item] = maxi(0, int(d[item]) - maxi(1, ceili(full * 0.5)) * days)
				if int(d[item]) <= 0:
					d.erase(item)
			s[kind] = d
		s["day"] = day
	stock[key] = s
	return s


## How many of `item` this villager can still sell (`kind` "sold") or buy ("bought") today.
func remaining(key: String, kind: String, item: String, full: int, day: int) -> int:
	var s := _stock(key, day, func(_k: String, _i: String) -> int: return full)
	return maxi(0, full - int((s[kind] as Dictionary).get(item, 0)))


func take(key: String, kind: String, item: String, n: int, day: int, full: int) -> void:
	var s := _stock(key, day, func(_k: String, _i: String) -> int: return full)
	var d: Dictionary = s[kind]
	d[item] = int(d.get(item, 0)) + n


# --- Pets -------------------------------------------------------------------------------

func add_pet(kind: String, pet_name: String, variant: int) -> Dictionary:
	var p := {"uid": _next_uid, "kind": kind, "name": pet_name, "variant": variant, "mode": "follow"}
	_next_uid += 1
	pets.append(p)
	return p


func pet(uid: int) -> Dictionary:
	for p: Dictionary in pets:
		if int(p["uid"]) == uid:
			return p
	return {}


func remove_pet(uid: int) -> void:
	for i in pets.size():
		if int(pets[i]["uid"]) == uid:
			pets.remove_at(i)
			return


# --- Fishing ----------------------------------------------------------------------------

## Records a catch; true the first time this kind is landed.
func log_catch(item: String) -> bool:
	var first := not fish_log.has(item)
	fish_log[item] = int(fish_log.get(item, 0)) + 1
	return first


# --- Save -------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"reputation": reputation.duplicate(), "rep_today": rep_today.duplicate(true), "stock": stock.duplicate(true),
		"pets": pets.duplicate(true), "fish_log": fish_log.duplicate(), "next_uid": _next_uid}


func from_dict(d: Dictionary) -> void:
	reputation = (d.get("reputation", {}) as Dictionary).duplicate()
	rep_today = (d.get("rep_today", {}) as Dictionary).duplicate(true)
	stock = (d.get("stock", {}) as Dictionary).duplicate(true)
	pets = (d.get("pets", []) as Array).duplicate(true)
	fish_log = (d.get("fish_log", {}) as Dictionary).duplicate()
	_next_uid = int(d.get("next_uid", 1))
	for p: Dictionary in pets:
		_next_uid = maxi(_next_uid, int(p.get("uid", 0)) + 1)
