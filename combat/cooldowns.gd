class_name Cooldowns
extends RefCounted
## Ability cooldown tracker. Owners call `advance(delta)` every frame.

const DEFAULTS := {"fireball": 4.0, "burst": 12.0, "dodge": 0.8, "potion": 2.0, "attack": 0.35}

var time := 0.0
var _ends := {}
var _totals := {}


func advance(delta: float) -> void:
	time += delta


func ready(ability: String) -> bool:
	return time >= float(_ends.get(ability, -1.0))


## Starts the cooldown if ready. Returns false (and does nothing) otherwise.
func trigger(ability: String, duration := -1.0) -> bool:
	if not ready(ability):
		return false
	var d := duration if duration >= 0.0 else float(DEFAULTS.get(ability, 1.0))
	_ends[ability] = time + d
	_totals[ability] = d
	return true


func remaining(ability: String) -> float:
	return maxf(0.0, float(_ends.get(ability, 0.0)) - time)


func total(ability: String) -> float:
	return float(_totals.get(ability, DEFAULTS.get(ability, 1.0)))


## 0 just triggered .. 1 ready.
func progress(ability: String) -> float:
	var t := total(ability)
	if t <= 0.0:
		return 1.0
	return 1.0 - clampf(remaining(ability) / t, 0.0, 1.0)


func reset(ability := "") -> void:
	if ability == "":
		_ends.clear()
	else:
		_ends.erase(ability)
