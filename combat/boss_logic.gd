class_name BossLogic
extends RefCounted
## Pure boss decision rules: phases, enrage, target selection. Kept apart
## from the Boss node so they can be unit tested.

const PHASE_2 := 2.0 / 3.0
const PHASE_3 := 1.0 / 3.0


## 1: 100-66 %, 2: 66-33 %, 3: 33-0 %.
static func phase_for(health_fraction: float) -> int:
	if health_fraction > PHASE_2:
		return 1
	if health_fraction > PHASE_3:
		return 2
	return 3


static func is_enraged(elapsed: float, enrage_time: float) -> bool:
	return enrage_time > 0.0 and elapsed >= enrage_time


## Attack speed multiplier (higher = faster) once enraged.
static func tempo(elapsed: float, enrage_time: float, phase: int) -> float:
	var t := 1.0 + 0.12 * (phase - 1)
	if is_enraged(elapsed, enrage_time):
		t *= 1.35
	return t


## Highest threat wins, with a bias towards players who are close.
## threat: id -> damage dealt; distance: id -> metres. Ignores ids without a distance (gone/dead).
## With no threat at all, the nearest player is chosen.
static func pick_target(threat: Dictionary, distance: Dictionary, proximity_bias := 0.6, max_range := 40.0) -> int:
	var best := -1
	var best_score := -INF
	var any_threat := false
	for id: int in distance:
		if float(threat.get(id, 0.0)) > 0.0:
			any_threat = true
	for id: int in distance:
		var d: float = distance[id]
		if d > max_range:
			continue
		var near := clampf(1.0 - d / max_range, 0.0, 1.0)
		var score: float
		if any_threat:
			score = float(threat.get(id, 0.0)) * (1.0 + proximity_bias * near) + near * 0.01
		else:
			score = near
		if score > best_score:
			best_score = score
			best = id
	return best


## Weighted random pick of an attack name from {name: weight}; roll in 0..1.
static func pick_weighted(weights: Dictionary, roll: float) -> String:
	var total := 0.0
	for k: String in weights:
		total += maxf(0.0, float(weights[k]))
	if total <= 0.0:
		return ""
	var r := roll * total
	for k: String in weights:
		r -= maxf(0.0, float(weights[k]))
		if r <= 0.0:
			return k
	return weights.keys()[weights.size() - 1]
