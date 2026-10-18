class_name CharybdisBoss
extends Boss
## Charybdis, the Maw of the Sea: a vast whirlpool with a ringed throat of
## teeth at its heart, walled in by a ring of sea stacks and the broken
## platforms of an old sea temple. The boss position is the maw at the bottom
## of the funnel; it can only be hurt while the maw has risen into the vortex
## (`flying` = risen, replicated). Players fight from the platforms; anyone
## sucked down the funnel is spat back out onto them.
##   Phase 1: vortex pull (the platforms drag towards the rim, then the maw
##            snaps shut over the inner edge), debris storm (wreckage flung at
##            marked spots), tidal surge (a wave across the arena; one strip
##            stays dry), gulp (the maw heaves up and lingers: the opening)
##            lunge (the maw slides to one side of the funnel and heaves over
##            the rim onto a marked stretch of platform, then lingers there)
##   Phase 2: + spin (lanes sweep round from the vortex one after another),
##            + drowned rise from the deep, + geysers (spouts under everyone)
##   Phase 3: + maelstrom (rings with safe bands, a stronger pull), + undertow
##            (two opposite halves of the arena are dragged in, one after the
##            other), faster tempo
## The maw is never still: it wanders round the funnel towards whoever it is
## fighting and tilts towards them when it rises. A heavy blow while it
## lingers risen makes it recoil.

const FUNNEL := 11.0       ## radius of the open vortex
const DECK := 21.0         ## outer radius of the platform ring
const PIT_DEPTH := 12.0    ## how far below the platforms the maw sits at rest
const WANDER := 4.5        ## how far the maw may move off the funnel's axis

var arena_center := Vector3.ZERO
var water_y := 13.0
var _spit_t := 0.0
## Horizontal offset of the maw from the funnel's axis (it wanders and lunges).
var _maw_off := Vector3.ZERO
var _maw_goal := Vector3.ZERO


func _init() -> void:
	kind = "charybdis"
	display_name = "Charybdis, the Maw of the Sea"
	relic = "charybdis_heartstone"
	xp_value = 2800
	base_health = 6800.0
	walk_speed = 2.0
	melee_range = 30.0
	aggro_radius = 28.0
	arena_radius = 26.0
	enrage_time = 600.0
	hit_radius = 9.4
	hit_height = 6.0
	body.half_extents = Vector3(4.0, 2.0, 4.0)
	body.fly = true
	body.collides = false
	body.gravity = 0.0
	loot = [["potion_greater", 1.0, 3, 5], ["tide_pearl", 1.0, 3, 6], ["pearl", 1.0, 3, 6], ["sapphire", 1.0, 3, 6],
		["gold_ore", 1.0, 12, 18], ["mithril_ore", 0.9, 4, 7], ["frost_shard", 0.6, 2, 4]]


func _ready() -> void:
	super._ready()
	if not ItemDB.exists(relic):
		relic = ""
	_set_arena(spawn_point)
	global_position = _maw_point(0.0)


func on_spawned(data: Dictionary) -> void:
	var w := world()
	if w == null or not data.has("home"):
		return
	var loc := w.location_by_id(StringName(String(data["home"])))
	if loc == null:
		return
	var spots := loc.spawns_of("boss")
	if not spots.is_empty():
		_set_arena(spots[0]["pos"])
		spawn_point = arena_center


func _set_arena(center: Vector3) -> void:
	arena_center = center
	water_y = center.y - 2.0
	var cm := model as CharybdisModel
	if cm != null:
		cm.water_y = water_y
		cm.arena_center = arena_center


## Where the maw sits: rise 0 at rest deep in the funnel .. 1 heaved up to the rim.
func _maw_point(rise: float) -> Vector3:
	return arena_center + _maw_off + Vector3(0, lerpf(-PIT_DEPTH, -2.6, rise), 0)


func _hover(delta: float) -> void:
	_maw_off = _maw_off.lerp(_maw_goal, 1.0 - exp(-1.2 * delta))
	global_position = global_position.lerp(_maw_point(1.0 if flying else 0.0), 1.0 - exp(-2.5 * delta))
	yaw += delta * (0.6 + phase * 0.25)


## Aim the maw's wandering at `p` (a fraction of WANDER towards it).
func _wander_towards(p: Vector3, frac: float) -> void:
	var to := p - arena_center
	to.y = 0.0
	_maw_goal = to.normalized() * WANDER * clampf(frac, 0.0, 1.0) if to.length() > 0.5 else Vector3.ZERO


func take_damage(amount: float, source_id := 0, damage_kind := "hit") -> float:
	if not flying and engaged:
		return 0.0
	return super.take_damage(amount, source_id, damage_kind)


## The arena is the platform ring around the maw, measured from the platforms (not the pit).
func _in_arena(p: Node3D) -> bool:
	var d := p.global_position - arena_center
	return Vector2(d.x, d.z).length() < arena_radius * 1.6 and absf(d.y) < arena_height


func _keep_in_arena(_delta: float) -> bool:
	return false


func _idle(delta: float) -> void:
	flying = false
	_maw_goal = Vector3.ZERO
	_hover(delta)


func _approach(delta: float) -> void:
	if _target != null:
		_wander_towards(_target.global_position, 0.6 + 0.2 * sin(fight_time * 0.7))
	_hover(delta)


func _physics(delta: float) -> void:
	rotation.y = yaw
	if model != null:
		model.move_speed = 0.0
		model.grounded = true
		model.turn_rate = 0.0
		_last_yaw = yaw
		model.set_burning(burning > 0.0)
	_sync_model()


func _sync_model() -> void:
	var cm := model as CharybdisModel
	if cm != null:
		cm.risen = flying
		cm.engaged = engaged
		cm.fury = float(phase) / 3.0
		# From the (replicated) position, so clients tilt it the same way.
		cm.lean_to = Vector3(global_position.x - arena_center.x, 0, global_position.z - arena_center.z) / WANDER


func _process(delta: float) -> void:
	super._process(delta)
	_sync_model()


func server_tick(delta: float) -> void:
	super.server_tick(delta)
	if engaged and not dead:
		_spit_fallen(delta)


## Anyone dragged down the funnel is spat back up over the rim (marked first).
func _spit_fallen(delta: float) -> void:
	_spit_t -= delta
	if _spit_t > 0.0:
		return
	_spit_t = 2.5
	for p in _players():
		var d := p.global_position - arena_center
		if Vector2(d.x, d.z).length() < FUNNEL and d.y < -2.5:
			var at := p.global_position
			_tele("circle:spit", at, _fwd(), Vector3(3.5, 0, 0), 0.9, 10.0, "hit", 0.0,
				func() -> void: _fling_out(at, 4.0, 31.0))


## Throws everyone near `at` up out of the funnel and over the rim onto the platforms.
func _fling_out(at: Vector3, radius: float, up: float) -> void:
	for p in _players():
		var d := p.global_position - at
		if Vector2(d.x, d.z).length() > radius:
			continue
		var out := p.global_position - arena_center
		out.y = 0.0
		out = out.normalized() if out.length() > 0.1 else Vector3.RIGHT
		_knockback(p, out * 8.5 + Vector3.UP * up)


func _engage() -> void:
	if engaged:
		return
	super._engage()
	_start("gulp")


func _reset() -> void:
	super._reset()
	_maw_off = Vector3.ZERO
	_maw_goal = Vector3.ZERO
	global_position = _maw_point(0.0)


func _start(attack_name: String) -> void:
	_attack = attack_name
	_attack_t = 0.0
	_attack_data = {}
	_begin_attack(attack_name)


# --- Attacks -------------------------------------------------------------------------------

func _attacks() -> Dictionary:
	return {
		"vortex": {"phase": 1, "weight": 2.2, "cooldown": 1.2},
		"debris": {"phase": 1, "weight": 2.4, "cooldown": 1.0},
		"surge": {"phase": 1, "weight": 1.8, "cooldown": 1.2},
		"gulp": {"phase": 1, "weight": 2.0, "cooldown": 1.0},
		"spin": {"phase": 2, "weight": 1.5, "cooldown": 1.4},
		"summon": {"phase": 2, "weight": 0.7, "cooldown": 1.5, "ok": func() -> bool: return summons.size() < 3},
		"maelstrom": {"phase": 3, "weight": 1.5, "cooldown": 1.8},
		"lunge": {"phase": 1, "weight": 1.8, "cooldown": 1.1},
		"geyser": {"phase": 2, "weight": 1.3, "cooldown": 1.0},
		"undertow": {"phase": 3, "weight": 1.3, "cooldown": 1.6},
	}


func _begin_attack(attack_name: String) -> void:
	match attack_name:
		"vortex":
			flying = true
			_play("summon", 3.0)
			_tele("ring:vortex", arena_center, _fwd(), Vector3(FUNNEL - 0.5, DECK + 2.0, 0), 1.5, 8.0, "hit", -12.0)
			_tele("circle:maw", arena_center, _fwd(), Vector3(FUNNEL + 2.6, 0, 0), 2.7, 36.0, "hit", 15.0,
				func() -> void:
					_shake_near(arena_center, 0.9)
					Audio.play("roar_big", arena_center, 4.0, 0.5))
		"debris":
			flying = true
			_play("throw", 3.0)
			_attack_data["shots"] = 0
			Audio.play("wave_crash", arena_center, 5.0, 0.7)
		"surge":
			flying = false
			_play("roar", 2.4)
			var a := _rng.randf() * TAU
			var dir := Vector3(cos(a), 0, sin(a))
			var side := Vector3(-dir.z, 0, dir.x)
			var offset := 8.0 if _rng.randf() < 0.5 else -8.0
			var start := arena_center - dir * (DECK + 6.0) + side * offset
			_tele("line:surge", start, dir, Vector3((DECK + 6.0) * 2.0, 26.0, 0), 2.2, 30.0, "hit", 13.0,
				func() -> void:
					_shake_near(arena_center, 0.7)
					Audio.play("wave_crash", arena_center, 8.0))
		"gulp":
			flying = true
			_play("bite", 2.2)
			Audio.play("roar_big", arena_center, 5.0, 0.6)
			_tele("circle:gulp", arena_center, _fwd(), Vector3(FUNNEL + 1.6, 0, 0), 1.4, 40.0, "hit", 12.0,
				func() -> void: _shake_near(arena_center, 0.8))
		"spin":
			flying = false
			_play("summon", 3.0)
			_attack_data["lanes"] = 0
			_attack_data["angle"] = _rng.randf() * TAU
		"summon":
			flying = true
			_play("roar", 1.8)
			_summon_drowned(2 if phase < 3 else 3)
		"lunge":
			flying = true
			var p := _target if _target != null else _random_player()
			var at := p.global_position if p != null else arena_center + Vector3(DECK, 0, 0)
			var to := at - arena_center
			to.y = 0.0
			var dir := to.normalized() if to.length() > 0.5 else _fwd()
			_maw_goal = dir * WANDER * 1.15
			var rim := arena_center + dir * (FUNNEL + 2.5)
			# The maw heaves over the rim at 60 % of the model's lunge.
			_play("lunge", 1.6 / 0.6)
			Audio.play("roar_big", arena_center, 5.0, 0.55)
			_tele("circle:gulp", rim, dir, Vector3(5.5, 0, 0), 1.6, 42.0, "hit", 12.0,
				func() -> void:
					_shake_near(rim, 0.8)
					Audio.play("wave_crash", rim, 6.0, 0.7))
		"geyser":
			flying = false
			_play("spout", 2.0)
			var spots: Array[Vector3] = []
			for p in _players():
				spots.append(Vector3(p.global_position.x, maxf(p.global_position.y, arena_center.y), p.global_position.z))
			for i in 2:
				var a := _rng.randf() * TAU
				spots.append(arena_center + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(FUNNEL + 2.0, DECK - 1.0))
			for c: Vector3 in spots:
				_tele("circle:geyser", c, _fwd(), Vector3(3.0, 0, 0), 1.3, 30.0, "hit", 10.0)
			Audio.play("splash_big", arena_center, 5.0, 0.8)
		"undertow":
			flying = false
			_play("summon", 3.6)
			var a := _rng.randf() * TAU
			var dir := Vector3(cos(a), 0, sin(a))
			_attack_data["dir"] = dir
			# Each half of the arena is dragged in turn towards the maw (pull) and
			# raked by the current; the far half is safe until its turn.
			_tele("cone:wave", arena_center, dir, Vector3(DECK + 2.0, 110.0, 0), 1.4, 26.0, "hit", -7.0)
			_tele("cone:wave", arena_center, -dir, Vector3(DECK + 2.0, 110.0, 0), 2.7, 26.0, "hit", -7.0,
				func() -> void: _shake_near(arena_center, 0.6))
		"maelstrom":
			flying = true
			_play("summon", 4.0)
			_tele("ring:vortex", arena_center, _fwd(), Vector3(FUNNEL - 0.5, DECK + 2.0, 0), 1.2, 6.0, "hit", -9.0)
			for b: Vector2 in [Vector2(FUNNEL, 14.5), Vector2(18.0, DECK + 2.0)]:
				_tele("ring:maelstrom", arena_center, _fwd(), Vector3(b.x, b.y, 0), 2.0, 30.0, "hit", 8.0)
			_tele("ring:maelstrom", arena_center, _fwd(), Vector3(14.5, 18.0, 0), 3.4, 30.0, "hit", 8.0)


func _update_attack(attack_name: String, t: float, delta: float) -> bool:
	_hover(delta)
	match attack_name:
		"vortex":
			return t > 3.6
		"debris":
			var shots: int = _attack_data.get("shots", 0)
			if shots < 3 + phase and t > 0.6 + shots * 0.4:
				_attack_data["shots"] = shots + 1
				_fling_debris()
			return t > 3.4
		"surge":
			return t > 3.0
		"gulp":
			# The maw lingers at the rim after it bites: the opening.
			return t > 4.4 - (0.8 if phase == 3 else 0.0)
		"spin":
			var n: int = _attack_data.get("lanes", 0)
			if n < 6 and t > 0.2 + n * 0.35:
				_attack_data["lanes"] = n + 1
				var a := float(_attack_data["angle"]) + n * 0.55
				var dir := Vector3(cos(a), 0, sin(a))
				_tele("line:spin", arena_center + dir * (FUNNEL - 1.0), dir, Vector3(DECK - FUNNEL + 3.0, 4.0, 0), 1.3, 26.0, "hit", 9.0)
			if t > 2.4:
				flying = true
			return t > 3.6
		"summon":
			return t > 2.0
		"maelstrom":
			return t > 4.4
		"lunge":
			# It lingers heaved up at the rim: the opening.
			return t > 4.0 - (0.6 if phase == 3 else 0.0)
		"geyser":
			return t > 2.4
		"undertow":
			if t > 2.8:
				flying = true
				_maw_goal = Vector3.ZERO
			return t > 4.4
	return t > 4.0


## A heavy blow while the maw lingers risen (no blow of its own pending) makes it recoil.
func _flinch(dealt: float) -> void:
	if not engaged or not flying or _flinch_t > 0.0 or dealt < max_health * 0.015 or not is_server():
		return
	if not _pending.is_empty() or _attack in ["debris", "spin", "maelstrom"]:
		return
	_flinch_t = flinch_cooldown
	_play("hit", 0.7)


func _fling_debris() -> void:
	var w = _w()
	if w == null:
		return
	var p := _random_player()
	var target := arena_center
	if p != null and _rng.randf() < 0.7:
		target = p.global_position + Vector3(_rng.randf_range(-2.5, 2.5), 0.0, _rng.randf_range(-2.5, 2.5))
	else:
		var a := _rng.randf() * TAU
		target = arena_center + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(FUNNEL + 2.0, DECK - 1.0)
	target.y = maxf(target.y, arena_center.y)
	var origin := arena_center + _maw_off + Vector3(0, 3.0, 0)
	var flight := 1.4
	var g := 16.0
	var vel := (target - origin) / flight + Vector3(0, 0.5 * g * flight, 0)
	w.telegraph("circle:debris", target, _fwd(), Vector3(3.4, 0, 0), flight, dimension)
	w.spawn_projectile("boulder", origin, vel, net_id, Team.MONSTERS, dimension, _dmg(28.0))


func _summon_drowned(count: int) -> void:
	var w = _w()
	if w == null:
		return
	for i in count:
		var a := _rng.randf() * TAU
		var pos := arena_center + Vector3(cos(a), 0, sin(a)) * (FUNNEL + 4.0) + Vector3(0, 0.6, 0)
		var e: Entity = w.spawn_entity("drowned", pos, dimension, {"summoned": true})
		if e != null:
			summons.append(e)


func _on_phase_changed(new_phase: int) -> void:
	_next_attack = 1.0
	# The deep gives up its drowned as the maw is first wounded badly.
	if new_phase == 2:
		_summon_drowned(2)
	if _attack == "":
		_start("gulp")
