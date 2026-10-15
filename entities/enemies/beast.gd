class_name Beast
extends Enemy
## Creatures with behaviours beyond the base monster state machine
## (stats in MobDB, "ai" key):
##   pack   - wolves and hellhounds: when one notices you it howls and the
##            rest of its pack within 22 m joins the hunt
##   swim   - sharks and sea serpents: never leave the water; they hold a depth
##            between the bottom and the surface and circle if you stand ashore
##   ambush - bog lurkers: lie still and half-sunk until you come close, then
##            lunge out at once
##   swoop  - cave bats: erratic flight, dive in to bite and pull away
## Everything else (bears, spiders, golems, scorpions, elementals, drowned)
## uses the base behaviour with its own stats and model.

const PACK_RADIUS := 22.0

var ai := ""
var _water_top := NAN
var _water_floor := NAN
var _water_t := 0.0
var _swoop := 0.0
var _hidden := false


static func create(beast_kind: String) -> Enemy:
	var e := Beast.new()
	e.kind = beast_kind
	return e


func _ready() -> void:
	super._ready()
	ai = String(stats.get("ai", ""))
	if ai == "swim":
		body.fly = true
	_hidden = ai == "ambush"
	_swoop = _rng.randf() * TAU
	respawn_seconds = 120.0


func _scan(w: Variant, aggro: float) -> bool:
	if ai == "swim":
		# Sharks only notice what is in or right at the water.
		var p: Entity = w.nearest_player(global_position, dimension, aggro)
		if p == null or p.dead or not _reachable_in_water(p.global_position):
			return false
	var found := super._scan(w, aggro)
	if found:
		_hidden = false
		if ai == "pack":
			_alert_pack(w)
		elif stats.has("sound") and stats["sound"] != "growl":
			Audio.play(String(stats["sound"]), center(), -2.0)
	return found


## The rest of the pack joins the hunt.
func _alert_pack(w: Variant) -> void:
	if not w.has_method("entities_near"):
		return
	for e: Entity in w.entities_near(global_position, PACK_RADIUS, dimension, Team.MONSTERS):
		if e == self or e.kind != kind or not e is Beast:
			continue
		var b := e as Beast
		if b._target == null and not b.dead:
			b._target = _target
			b._set_state(State.CHASE)
	Audio.play("growl", center(), 0.0, 0.6 if kind == "dire_wolf" else 0.85)


func _think(delta: float) -> void:
	if ai == "ambush" and _hidden and state in [State.IDLE, State.PATROL]:
		# Lie in wait: no patrols, a short sharp aggro radius, then lunge.
		_steer(global_position, 0.0, delta)
		var w = _w()
		if w != null and _scan(w, float(stats["aggro"])):
			_cooldown = 0.0
		return
	if ai == "swim" and _target != null and state == State.CHASE and not _reachable_in_water(_target.global_position):
		# The prey climbed out: circle offshore, then give up.
		var around := _target.global_position + (global_position - _target.global_position).normalized() * 9.0
		_steer(around, float(stats["speed"]), delta)
		if _state_t < -6.0:
			_target = null
			_set_state(State.RETURN, 10.0)
		return
	super._think(delta)


func _steer(target: Vector3, speed: float, delta: float) -> void:
	if ai == "swim":
		_swim_steer(target, speed, delta)
		return
	if ai == "swoop" and body.fly and speed > 0.0:
		# Erratic bat flight: weave around the line to the target.
		_swoop += delta * 5.0
		var side := Vector3(cos(_swoop), 0, sin(_swoop * 1.3)) * 1.6
		target += side
	super._steer(target, speed, delta)
	if ai == "swoop" and _target != null:
		# Swoop down to head height to bite, hang higher while recovering.
		var want := _target.global_position.y + (1.1 if state in [State.CHASE, State.ATTACK] else 2.6)
		body.velocity.y = lerpf(body.velocity.y, clampf((want - global_position.y) * 2.5, -5.0, 5.0), 1.0 - exp(-5.0 * delta))


## Water creatures: move only through liquid, keep a depth band.
func _swim_steer(target: Vector3, speed: float, delta: float) -> void:
	_update_water(delta)
	var to := target - global_position
	to.y = 0.0
	var desired := Vector3.ZERO
	if to.length() > 0.4 and speed > 0.0:
		desired = to.normalized() * speed
		var ahead := global_position + to.normalized() * (hit_radius + 1.0)
		if not _is_water(ahead):
			desired = Vector3.ZERO
		_face(target, delta, 5.0)
	body.velocity.x = lerpf(body.velocity.x, desired.x, 1.0 - exp(-4.0 * delta))
	body.velocity.z = lerpf(body.velocity.z, desired.z, 1.0 - exp(-4.0 * delta))
	var want := global_position.y
	if not is_nan(_water_top):
		var lo := (_water_floor + 0.8) if not is_nan(_water_floor) else _water_top - 6.0
		var hi := _water_top - (0.9 if kind == "shark" else 1.4)
		var aim := target.y if _target != null else _water_top - 2.5
		want = clampf(aim, minf(lo, hi), hi)
	body.velocity.y = lerpf(body.velocity.y, clampf((want - global_position.y) * 1.5, -3.0, 3.0), 1.0 - exp(-3.0 * delta))


func _update_water(delta: float) -> void:
	_water_t -= delta
	if _water_t > 0.0:
		return
	_water_t = 0.5
	var v := voxels()
	if v == null:
		_water_top = global_position.y + 2.5
		_water_floor = global_position.y - 4.0
		return
	var p := Vector3i(global_position.floor())
	_water_top = NAN
	for dy in range(0, 24):
		var b := v.get_block(p + Vector3i(0, dy, 0))
		if b < 0:
			break
		if not Blocks.is_liquid(b):
			_water_top = float(p.y + dy)
			break
	_water_floor = NAN
	for dy in range(0, 30):
		var b := v.get_block(p - Vector3i(0, dy, 0))
		if b < 0:
			break
		if b != Blocks.AIR and Blocks.is_solid(b):
			_water_floor = float(p.y - dy + 1)
			break


func _is_water(pos: Vector3) -> bool:
	var v := voxels()
	if v == null:
		return true
	var b := v.get_block(Vector3i(pos.floor()))
	return b > 0 and Blocks.is_liquid(b) and b != Blocks.LAVA


## A swimmer can reach a point if there is water at it or just below it.
func _reachable_in_water(pos: Vector3) -> bool:
	var v := voxels()
	if v == null:
		return true
	for dy in range(0, 3):
		var b := v.get_block(Vector3i(pos.floor()) - Vector3i(0, dy, 0))
		if b > 0 and Blocks.is_liquid(b) and b != Blocks.LAVA:
			return true
	return false


func _process(delta: float) -> void:
	super._process(delta)
	if ai == "ambush" and not is_server() and _hidden and (anim != 0 or _vis_speed > 0.4):
		_hidden = false
	if model is QuadrupedModel and ai == "ambush":
		# Half-sunk and still while waiting.
		model.position.y = lerpf(model.position.y, -0.35 if (_hidden and not dead) else 0.0, 1.0 - exp(-3.0 * delta))
