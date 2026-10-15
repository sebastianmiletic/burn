class_name BossLedger
extends RefCounted
## Server memory of wounded bosses, so a boss never heals by being despawned
## and spawned again (players walking away from the arena, the location
## deactivating, a client joining, a save being reloaded).
##
## The rule (docs/BOSS_GUIDE.md):
##   * A boss keeps its remaining health, its phase and the party size its
##     health was scaled for for the whole arena session.
##   * The session ends only after a long, genuine disengage: RECOVER_SECONDS
##     of game time in which nobody fought or hurt the boss. Only then does it
##     recover to full health (and scale again for whoever pulls it next).
##   * There is no regeneration in between, and nothing else heals a boss.
##
## Entries are keyed by the arena (the boss's home location, or its kind when
## it has none) and timed with the world's play clock, which is saved, so the
## rule holds across reloads too.

const RECOVER_SECONDS := 600.0

## key -> {"health", "max", "base", "party", "t"}
var entries := {}


## The remembered state for `key`, or {} when there is none or it has expired.
func recall(key: String, now: float) -> Dictionary:
	if not entries.has(key):
		return {}
	var e: Dictionary = entries[key]
	if expired(e, now):
		entries.erase(key)
		return {}
	return e


func record(key: String, health: float, max_health: float, base_health: float, party: int, now: float) -> void:
	entries[key] = {"health": health, "max": max_health, "base": base_health, "party": party, "t": now}


## Refresh the activity time only (the boss is still being fought).
func touch(key: String, now: float) -> void:
	if entries.has(key):
		entries[key]["t"] = now


func forget(key: String) -> void:
	entries.erase(key)


static func expired(e: Dictionary, now: float) -> bool:
	return now - float(e.get("t", 0.0)) >= RECOVER_SECONDS


## Save form: wounds still inside their session.
func to_save(now: float) -> Dictionary:
	var out := {}
	for k: String in entries:
		var e: Dictionary = entries[k]
		if not expired(e, now):
			out[k] = e.duplicate()
	return out


func from_save(data: Dictionary) -> void:
	entries.clear()
	for k: Variant in data:
		var e: Variant = data[k]
		if e is Dictionary and (e as Dictionary).has("health") and (e as Dictionary).has("max"):
			entries[String(k)] = (e as Dictionary).duplicate()
