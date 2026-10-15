class_name Boss
extends Entity
## Base for the bosses.
##
## Server: engages when a player comes within `aggro_radius` of its arena,
## scales health to the party, tracks a threat table (damage per player),
## moves into range of its target and picks attacks from `_attacks()` for the
## current phase (1: 100-66 %, 2: 66-33 %, 3: 33-0 %). Heavy attacks always go
## through `_tele()`: the ground warning is shown first and the damage lands
## only when it has filled. After `enrage_time` the boss hits harder and
## faster. If the whole party dies or leaves, it disengages.
##
## Health rules (docs/BOSS_GUIDE.md, tests/unit/test_boss_rules.gd):
##   * Nothing heals a boss in a fight: not disengaging, leaving or re-entering
##     the arena, a client joining, a phase change, replication, or being
##     despawned and spawned again (the world's BossLedger remembers wounds).
##   * Health is scaled for the party once per encounter: at the pull, and for
##     players who join in the first PULL_WINDOW seconds of a fresh pull (the
##     health fraction is kept, so that is never a heal).
##   * Only a long genuine disengage (BossLedger.RECOVER_SECONDS of game time
##     with no fighting) restores full health.
##   * Players outside the arena cannot pull or chip the boss (their hits are
##     evaded); phases are never skipped (every transition runs, in order).
##   * A boss that falls out of its arena, wanders off or gets stuck on
##     geometry returns to its spawn point.
##
## Replication: snapshot() adds [phase, engaged, flying, max_health]; `anim`
## indexes ACTIONS and `anim_time` stamps when it started.

const ACTIONS := ["", "attack", "attack2", "sweep", "slam", "roar", "bite", "claw", "tail", "breath", "gust",
		"takeoff", "land", "dive", "pounce", "howl", "summon", "throw", "cast", "spikes", "teleport", "hit", "fly"]
## Seconds after a fresh pull in which arriving players still scale the boss's health.
const PULL_WINDOW := 15.0
## Seconds without a target before an engaged boss disengages.
const DISENGAGE_SECONDS := 8.0
## A boss further than this below its spawn point has fallen out of the arena.
const FALL_LIMIT := 40.0

var phase := 1
var engaged := false
var flying := false
var relic := ""
var loot: Array = []
var xp_value := 500
var aggro_radius := 24.0
var arena_radius := 45.0
## Players more than this far above or below the spawn point are not in the arena.
var arena_height := 30.0
var enrage_time := 480.0
var base_health := 1500.0
var walk_speed := 3.0
var melee_range := 4.0
var model: CreatureModel
var spawn_point := Vector3.ZERO
var threat := {}
var fight_time := 0.0
var summons: Array[Entity] = []
## Location id this boss guards (set by LocationDirector; arena gates use it).
var home_location := ""

var _attack := ""
var _attack_t := 0.0
var _attack_data := {}
var _next_attack := 2.5
var _target: Entity
var _reset_t := 0.0
var _encounter_scaled := false
var _scaled_party := 0
var _fresh_pull := false
var _pending: Array = []
var _rng := RandomNumberGenerator.new()
var _dead_t := 0.0
var _burn_acc := 0.0
var _last_anim := [-1, -1.0]
var _last_pos := Vector3.ZERO
var _vis_speed := 0.0
var _last_health := -1.0
var _last_engaged := false
var _last_yaw := 0.0
# Ledger (server): wounds survive despawning.
var _ledger_ready := false
var _local_ledger: BossLedger
var _last_active := -INF
var _touch_t := 0.0
# Stuck / fall-out detection (server).
var _stuck_t := 0.0
var _stuck_from := Vector3.INF
var _stuck_tries := 0
var _move_intent := false
# Client presentation.
var _snap_seen := false
var _seen_alive := false
var _announce_t := -1.0
## Headless simulation hook (tests): when set, used instead of GameWorld.instance.
var sim_world: Object = null


func is_boss() -> bool:
	return true


## GameWorld keeps ticking an engaged boss even when nobody is near, so an
## abandoned fight times out and disengages (reopening the arena).
func is_engaged() -> bool:
	return engaged


## The world this creature acts in (duck-typed so tests can stand in for GameWorld).
func _w() -> Variant:
	return sim_world if sim_world != null else world()


static func create(boss_kind: String) -> Boss:
	match boss_kind:
		"warden":
			return WardenBoss.new()
		"mountain_king":
			return MountainKingBoss.new()
		"dragon":
			return DragonBoss.new()
		"cerberus":
			return CerberusBoss.new()
		"hades":
			return HadesBoss.new()
		"leviathan":
			return LeviathanBoss.new()
		"broodmother":
			return BroodmotherBoss.new()
		"bog_hag":
			return BogHagBoss.new()
		"ryft_sentinel":
			return RyftSentinelBoss.new()
		"void_sovereign":
			return VoidSovereignBoss.new()
	push_error("Unknown boss kind %s" % boss_kind)
	return WardenBoss.new()


func _ready() -> void:
	team = Team.MONSTERS
	max_health = base_health
	health = max_health
	if spawn_point == Vector3.ZERO:
		spawn_point = global_position
	_rng.seed = hash(kind + str(net_id))
	model = Models.create(kind)
	add_child(model)
	_last_pos = global_position
	_last_health = health
	_last_yaw = yaw


# --- Overridables ------------------------------------------------------------------

## {name: {"phase": min phase, "weight": w, "min": min range, "max": max range, "cooldown": s}}
func _attacks() -> Dictionary:
	return {}


func _begin_attack(_name: String) -> void:
	pass


## Return true when the attack has finished.
func _update_attack(_name: String, t: float, _delta: float) -> bool:
	return t > 1.0


func _on_phase_changed(_new_phase: int) -> void:
	pass


# --- Damage ---------------------------------------------------------------------

func take_damage(amount: float, source_id := 0, damage_kind := "hit") -> float:
	if dead or amount <= 0.0:
		return 0.0
	_sync_ledger()
	# Players outside the arena cannot pull or whittle the boss from where it
	# cannot follow (their hits are evaded). Burns already on it keep ticking.
	if damage_kind != "burn" and _player_outside_arena(source_id):
		return 0.0
	# Scale encounter health before applying the opening hit. Doing this in
	# _on_damaged used to heal away the first strike (even a killing blow).
	if not engaged and source_id != 0 and damage_kind != "burn":
		_engage()
	var resist_kind := "fire" if damage_kind in ["fire", "burn"] else "hit"
	var dealt := super.take_damage(Damage.apply(amount, kind, resist_kind), source_id, damage_kind)
	if dealt > 0.0:
		if source_id != 0 and damage_kind != "burn":
			threat[source_id] = float(threat.get(source_id, 0.0)) + dealt
		if not dead:
			_last_active = _clock()
			_remember()
	return dealt


func _on_damaged(amount: float, source_id: int, damage_kind: String) -> void:
	if damage_kind == "fire":
		burning = Damage.BURN_SECONDS * 0.6
	if model != null:
		model.flash(Color(1.0, 0.6, 0.35) if damage_kind in ["fire", "burn"] else Color(1, 1, 1))
	Events.damage_number.emit(center() + Vector3(0, hit_height * 0.35, 0), int(round(amount)), damage_kind == "crit", "fire" if damage_kind in ["fire", "burn"] else "hit")
	Events.boss_health_changed.emit(self, health, max_health, phase)
	var _u := source_id


func _on_died() -> void:
	engaged = false
	_attack = ""
	_pending.clear()
	burning = 0.0
	if model != null:
		model.set_dead(true)
		model.set_burning(false)
	# A client that joins after the death only sees the corpse, not the finale.
	if not is_server() and not _seen_alive:
		return
	Events.slow_motion.emit(1.6, 0.3)
	Events.screen_shake.emit(0.8)
	Events.boss_health_changed.emit(self, 0.0, max_health, phase)
	Audio.play("roar_big", center(), 2.0, 0.7)
	if is_server():
		_ledger().forget(_ledger_key())
		for s in summons:
			if is_instance_valid(s) and not s.dead:
				s.take_damage(s.health + 1.0, net_id, "hit")
		var w = _w()
		if w != null:
			w.boss_finished(self)


# --- Snapshot ---------------------------------------------------------------------

func snapshot() -> Array:
	var s := super.snapshot()
	s.append_array([phase, 1 if engaged else 0, 1 if flying else 0, max_health])
	return s


func apply_snapshot(s: Array, at_time: float) -> void:
	if s.size() > 5 and int(s[5]) == 0:
		_seen_alive = true
	if s.size() >= 11:
		# Before the health: the bar must never show health above its maximum.
		max_health = maxf(1.0, float(s[10]))
	super.apply_snapshot(s, at_time)
	if s.size() >= 10:
		phase = int(s[7])
		engaged = int(s[8]) == 1
		flying = int(s[9]) == 1
	if not _snap_seen:
		# The first snapshot brings existing wounds: not a hit to flash or number.
		_snap_seen = true
		_last_health = health


# --- Server ------------------------------------------------------------------------

func server_tick(delta: float) -> void:
	if dead:
		_dead_t += delta
		if _dead_t > 12.0:
			_dead_t = -INF
			var w = _w()
			if w != null:
				w.despawn_entity(self)
		return
	_sync_ledger()
	_tick_burn(delta)
	_tick_pending(delta)
	summons = summons.filter(func(e: Entity) -> bool: return is_instance_valid(e) and not e.dead)
	if _keep_in_arena(delta):
		return
	if not engaged:
		_recover_if_rested()
		_idle(delta)
		if _check_engage():
			_engage()
		_physics(delta)
		return
	fight_time += delta
	_touch_t -= delta
	if _touch_t <= 0.0:
		_touch_t = 1.0
		_last_active = _clock()
		_remember()
	# Every phase transition runs, in order, even when one blow crosses two.
	var new_phase := BossLogic.phase_for(health / max_health)
	while phase < new_phase:
		phase += 1
		_on_phase_changed(phase)
		Events.boss_health_changed.emit(self, health, max_health, phase)
	_scale_for_arrivals()
	_pick_target()
	if _target == null:
		_reset_t += delta
		if _reset_t > DISENGAGE_SECONDS:
			_reset()
			return
	else:
		_reset_t = 0.0
	var tempo := BossLogic.tempo(fight_time, enrage_time, phase)
	if _attack != "":
		_attack_t += delta * (1.0 + (tempo - 1.0) * 0.5)
		if _update_attack(_attack, _attack_t, delta):
			var cd := float(_attacks().get(_attack, {}).get("cooldown", 1.5))
			_attack = ""
			_next_attack = cd / tempo
	else:
		_approach(delta)
		_next_attack -= delta * tempo
		if _next_attack <= 0.0 and _target != null:
			_choose_attack()
	_physics(delta)


func _physics(delta: float) -> void:
	body.step(self, voxels(), delta)
	rotation.y = yaw
	if model != null:
		model.move_speed = Vector2(body.velocity.x, body.velocity.z).length()
		model.grounded = body.on_floor or flying
		model.turn_rate = angle_difference(_last_yaw, yaw) / maxf(delta, 0.001)
		_last_yaw = yaw
		model.set_burning(burning > 0.0)
		HumanoidModel.drive(model, self, body.velocity, body.on_floor or flying)
		if model is DragonModel:
			(model as DragonModel).flying = flying


func _idle(delta: float) -> void:
	_move_towards(spawn_point, walk_speed * 0.6, delta, 2.0)


func _check_engage() -> bool:
	var w = _w()
	if w == null:
		return false
	var p: Entity = w.nearest_player(spawn_point, dimension, aggro_radius)
	return p != null and not p.dead and _in_arena(p)


func _engage() -> void:
	if engaged or dead:
		return
	_sync_ledger()
	engaged = true
	fight_time = 0.0
	threat.clear()
	_reset_t = 0.0
	var party := maxi(1, _players().size())
	# Scale once per encounter, before the opening hit. Leaving the arena must
	# not heal the boss or rescale its remaining health when someone returns.
	_fresh_pull = not _encounter_scaled
	if not _encounter_scaled:
		max_health = Damage.boss_health(base_health, party)
		health = max_health
		_encounter_scaled = true
		_scaled_party = party
	phase = BossLogic.phase_for(health / max_health)
	_last_active = _clock()
	_remember()
	_next_attack = 2.0
	_play("roar")
	Audio.play("roar_big", center(), 2.0)
	Events.screen_shake.emit(0.4)
	var w = _w()
	if w != null:
		w.boss_started(self)
	Events.boss_health_changed.emit(self, health, max_health, phase)


## Players who arrive just after a fresh pull still count: the boss's health
## grows with the party but keeps its fraction (so the bar never moves up).
func _scale_for_arrivals() -> void:
	if not _fresh_pull or fight_time > PULL_WINDOW:
		return
	var party := _players().size()
	if party <= _scaled_party:
		return
	var frac := health / max_health
	_scaled_party = party
	max_health = Damage.boss_health(base_health, party)
	health = max_health * frac
	_remember()
	Events.boss_health_changed.emit(self, health, max_health, phase)


## Disengage: clear attacks, summons and burns, return to the spawn point and
## reopen the arena. Earned damage and the phase are kept.
func _reset() -> void:
	engaged = false
	_attack = ""
	_pending.clear()
	threat.clear()
	burning = 0.0
	phase = BossLogic.phase_for(health / max_health)
	flying = false
	body.fly = false
	_reset_t = 0.0
	_fresh_pull = false
	global_position = spawn_point
	body.velocity = Vector3.ZERO
	for s in summons:
		if is_instance_valid(s) and not s.dead:
			var w0 = _w()
			if w0 != null:
				w0.despawn_entity(s)
	summons.clear()
	_last_active = _clock()
	_remember()
	var w = _w()
	if w != null and w.has_method("boss_reset"):
		w.call("boss_reset", self)
	Events.boss_health_changed.emit(self, health, max_health, phase)


## After a long genuine disengage the boss recovers fully and will scale for
## whoever pulls it next. Nothing else restores its health.
func _recover_if_rested() -> void:
	if not _encounter_scaled and health >= max_health:
		return
	if _clock() - _last_active < BossLedger.RECOVER_SECONDS:
		return
	max_health = base_health
	health = max_health
	phase = 1
	_encounter_scaled = false
	_scaled_party = 0
	_ledger().forget(_ledger_key())


# --- Ledger --------------------------------------------------------------------------

func _ledger_key() -> String:
	return home_location if home_location != "" else kind


func _ledger() -> BossLedger:
	var w = _w()
	if w != null:
		var l: Variant = w.get("boss_ledger")
		if l is BossLedger:
			return l
	if _local_ledger == null:
		_local_ledger = BossLedger.new()
	return _local_ledger


## The world's play clock (saved with the world), so the recovery rule
## survives reloads. Tests use their own clock.
func _clock() -> float:
	var w = _w()
	if w != null:
		var t: Variant = w.get("play_time")
		if t == null:
			t = w.get("now")
		if t != null:
			return float(t)
	return Time.get_ticks_msec() / 1000.0


## Pick up the wounds a previous instance of this boss left (server, once).
func _sync_ledger() -> void:
	if _ledger_ready or not is_server():
		return
	_ledger_ready = true
	var e := _ledger().recall(_ledger_key(), _clock())
	if e.is_empty():
		return
	max_health = maxf(1.0, float(e["max"]))
	health = clampf(float(e["health"]), 1.0, max_health)
	_encounter_scaled = true
	_scaled_party = int(e.get("party", 1))
	phase = BossLogic.phase_for(health / max_health)
	_last_active = float(e.get("t", _clock()))


func _remember() -> void:
	if not is_server() or not _encounter_scaled or dead:
		return
	_ledger().record(_ledger_key(), health, max_health, base_health, _scaled_party, _last_active)


# --- Arena -------------------------------------------------------------------------

func _in_arena(p: Node3D) -> bool:
	var d := p.global_position - spawn_point
	return Vector2(d.x, d.z).length() < arena_radius * 1.6 and absf(d.y) < arena_height


## True when `source_id` is a player of this dimension who is not in the arena.
func _player_outside_arena(source_id: int) -> bool:
	if source_id == 0:
		return false
	var w = _w()
	if w == null:
		return false
	for p in w.players_in(dimension):
		if p.net_id == source_id:
			return not _in_arena(p)
	return false


## Falling out of the arena, wandering off or being stuck on geometry sends
## the boss back to its spawn point. Returns true when it did.
func _keep_in_arena(delta: float) -> bool:
	var off := global_position - spawn_point
	if off.y < -FALL_LIMIT or Vector2(off.x, off.z).length() > arena_radius * 2.5:
		_return_home()
		return true
	var trying := _move_intent
	_move_intent = false
	if not trying or not body.collides or flying or not engaged or _attack != "" or _target == null or _flat_dist(_target) < melee_range * 1.5:
		_stuck_t = 0.0
		_stuck_from = global_position
		_stuck_tries = 0
		return false
	_stuck_t += delta
	if _stuck_t < 2.5:
		return false
	_stuck_t = 0.0
	var moved := global_position.distance_to(_stuck_from) if _stuck_from.is_finite() else 99.0
	_stuck_from = global_position
	if moved > 1.0:
		_stuck_tries = 0
		return false
	_stuck_tries += 1
	if _stuck_tries < 3:
		if body.on_floor:
			body.velocity.y = 11.0
		return false
	_stuck_tries = 0
	_return_home()
	return true


func _return_home() -> void:
	_fx_burst(center(), false, 1.2)
	global_position = spawn_point + Vector3(0, 0.3, 0)
	body.velocity = Vector3.ZERO
	_stuck_from = global_position
	_fx_burst(spawn_point + Vector3(0, hit_height * 0.5, 0), false, 1.6)


func _players() -> Array[Entity]:
	var out: Array[Entity] = []
	var w = _w()
	if w == null:
		return out
	for p in w.players_in(dimension):
		if not p.dead and _in_arena(p):
			out.append(p)
	return out


func _pick_target() -> void:
	var dist := {}
	var by_id := {}
	for p in _players():
		dist[p.net_id] = p.global_position.distance_to(global_position)
		by_id[p.net_id] = p
	var id := BossLogic.pick_target(threat, dist, 0.6, arena_radius * 2.0)
	_target = by_id.get(id) if id != -1 else null


func _random_player() -> Entity:
	var ps := _players()
	if ps.is_empty():
		return null
	return ps[_rng.randi() % ps.size()]


func _choose_attack() -> void:
	var dist := _flat_dist(_target)
	var weights := {}
	for name: String in _attacks():
		var a: Dictionary = _attacks()[name]
		if phase < int(a.get("phase", 1)):
			continue
		if dist < float(a.get("min", 0.0)) or dist > float(a.get("max", 999.0)):
			continue
		if a.has("ok") and not (a["ok"] as Callable).call():
			continue
		weights[name] = float(a.get("weight", 1.0))
	var pick := BossLogic.pick_weighted(weights, _rng.randf())
	if pick == "":
		_next_attack = 0.4
		return
	_attack = pick
	_attack_t = 0.0
	_attack_data = {}
	body.velocity.x = 0.0
	body.velocity.z = 0.0
	_begin_attack(pick)


func _approach(delta: float) -> void:
	if _target == null:
		_move_towards(spawn_point, walk_speed, delta, 2.0)
		return
	var d := _flat_dist(_target)
	if d > melee_range:
		_move_towards(_target.global_position, walk_speed * (1.3 if d > melee_range * 3.0 else 1.0), delta, melee_range * 0.8)
	else:
		_move_towards(global_position, 0.0, delta, 0.5)
		_face(_target.global_position, delta, 4.0)


func _move_towards(target: Vector3, speed: float, delta: float, stop: float) -> void:
	var to := target - global_position
	to.y = 0.0
	var desired := Vector3.ZERO
	if to.length() > stop and speed > 0.0:
		desired = to.normalized() * speed
		_face(target, delta, 3.0)
	# Leash: never walk further out than the arena's edge (ranged attacks reach beyond it).
	var out := global_position - spawn_point
	out.y = 0.0
	if out.length() > arena_radius * 1.15 and desired.dot(out) > 0.0:
		var n := out.normalized()
		desired -= n * desired.dot(n)
	_move_intent = desired.length() > 0.5
	body.velocity.x = lerpf(body.velocity.x, desired.x, 1.0 - exp(-6.0 * delta))
	body.velocity.z = lerpf(body.velocity.z, desired.z, 1.0 - exp(-6.0 * delta))
	if body.hit_wall and body.on_floor and desired.length() > 0.1:
		body.velocity.y = 9.0


func _face(target: Vector3, delta: float, rate: float) -> void:
	var d := target - global_position
	if Vector2(d.x, d.z).length() < 0.05:
		return
	yaw = lerp_angle(yaw, atan2(-d.x, -d.z), 1.0 - exp(-rate * delta))


func _fwd() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func _flat_dist(e: Entity) -> float:
	if e == null:
		return INF
	return Vector2(e.global_position.x - global_position.x, e.global_position.z - global_position.z).length()


func _dmg(base: float) -> float:
	return Damage.monster(base, BossLogic.is_enraged(fight_time, enrage_time), maxi(1, _players().size()))


func _play(action: String, duration := -1.0) -> void:
	var i := ACTIONS.find(action)
	if i <= 0:
		return
	anim = i
	anim_time = Time.get_ticks_msec() / 1000.0 + float(_rng.randi() % 1000) * 1e-6
	if model != null:
		model.play(action, duration)
	_last_anim = [anim, anim_time]


## Telegraphs an attack and lands it when the warning has filled.
## on_land (optional) runs at that moment for effects (bursts, summons...).
func _tele(shape: String, pos: Vector3, dir: Vector3, size: Vector3, duration: float, base_damage: float,
		damage_kind := "hit", knockback := 0.0, on_land: Callable = Callable()) -> void:
	var w = _w()
	if w != null:
		w.telegraph(shape, pos, dir, size, duration, dimension)
	_pending.append({"t": duration, "shape": shape, "pos": pos, "dir": dir, "size": size,
		"damage": _dmg(base_damage), "kind": damage_kind, "knock": knockback, "on_land": on_land})


func _tick_pending(delta: float) -> void:
	for i in range(_pending.size() - 1, -1, -1):
		var p: Dictionary = _pending[i]
		p["t"] = float(p["t"]) - delta
		if float(p["t"]) <= 0.0:
			_pending.remove_at(i)
			_hit_shape(p["shape"], p["pos"], p["dir"], p["size"], p["damage"], p["kind"], p["knock"])
			var cb: Callable = p["on_land"]
			if cb.is_valid():
				cb.call()


func _hit_shape(shape: String, pos: Vector3, dir: Vector3, size: Vector3, amount: float, damage_kind: String, knockback: float) -> void:
	var w = _w()
	if w == null:
		return
	for p in _players():
		if TelegraphShape.contains(shape, pos, dir, size, p.global_position, 5.0):
			w.damage(p, amount, net_id, damage_kind)
			if knockback != 0.0:
				# Negative knockback pulls towards the shape (rifts, whirlpools).
				var away := p.global_position - (pos if shape.get_slice(":", 0) in ["circle", "ring"] else global_position)
				away.y = 0.0
				if away.length() < 0.1:
					away = dir
				_knockback(p, away.normalized() * knockback + Vector3(0, absf(knockback) * 0.45, 0))


func _knockback(p: Entity, impulse: Vector3) -> void:
	var w = _w()
	if w != null and w.has_method("knockback"):
		w.call("knockback", p, impulse)
	else:
		p.body.velocity += impulse


func _summon(summon_kind: String, count: int, radius: float) -> void:
	var w = _w()
	if w == null:
		return
	for i in count:
		var a := TAU * float(i) / count + _rng.randf() * 0.5
		var pos := global_position + Vector3(cos(a), 0, sin(a)) * radius + Vector3(0, 0.5, 0)
		var e: Entity = w.spawn_entity(summon_kind, pos, dimension, {"summoned": true})
		if e != null:
			summons.append(e)
			_fx_burst(pos, false)


func _fx_burst(pos: Vector3, fire := true, scale := 1.0) -> void:
	var parent := get_parent() as Node3D
	if parent == null:
		return
	if fire:
		ModelKit.burst(parent, pos, int(40 * scale), 0.6 * scale, 6.0 * scale, 0.8 * scale)
	else:
		ModelKit.burst(parent, pos, int(30 * scale), 0.5 * scale, 4.0 * scale, 0.6 * scale, Color(0.75, 0.9, 1.0), Color(0.3, 0.45, 0.8))


func _tick_burn(delta: float) -> void:
	if burning <= 0.0:
		return
	burning -= delta
	_burn_acc += delta
	if _burn_acc >= Damage.BURN_TICK:
		_burn_acc -= Damage.BURN_TICK
		var w = _w()
		if w != null:
			w.damage(self, Damage.burn_tick(8.0), last_hit_by, "burn")


func _shake_near(pos: Vector3, strength: float) -> void:
	var w = _w()
	if w != null:
		w.shake(strength)
	elif strength > 0.0:
		Events.screen_shake.emit(strength)
	var _u := pos


# --- Client presentation ----------------------------------------------------------

func _process(delta: float) -> void:
	if model == null:
		return
	# Bespoke boss models brood while idle and transform with the phases.
	if model.has_method("set_boss_state"):
		model.call("set_boss_state", engaged, phase, dead)
	if not is_server():
		interpolate(Time.get_ticks_msec() / 1000.0)
		var moved := (global_position - _last_pos) / maxf(delta, 0.0001)
		_vis_speed = lerpf(_vis_speed, Vector2(moved.x, moved.z).length(), 1.0 - exp(-8.0 * delta))
		model.move_speed = _vis_speed
		model.grounded = not flying
		model.set_burning(burning > 0.0)
		HumanoidModel.drive(model, self, Vector3(moved.x, 0.0, moved.z))
		if model is DragonModel:
			(model as DragonModel).flying = flying
		if _snap_seen and _last_health >= 0.0 and health < _last_health - 0.01:
			model.flash()
			Events.damage_number.emit(center() + Vector3(0, hit_height * 0.35, 0), int(round(_last_health - health)), false, "hit")
			Events.boss_health_changed.emit(self, health, max_health, phase)
		if engaged != _last_engaged:
			Events.boss_health_changed.emit(self, health, max_health, phase)
			_announce_t = 1.0 if engaged else -1.0
		_announce_if_missed(delta)
		if dead and not model._dead:
			model.set_dead(true)
		if anim != _last_anim[0] or anim_time != _last_anim[1]:
			_last_anim = [anim, anim_time]
			if anim > 0 and anim < ACTIONS.size() and not dead:
				model.play(ACTIONS[anim])
	_last_health = health
	_last_engaged = engaged
	_last_pos = global_position


## A client that joined mid-fight never received the "boss engaged" message:
## announce the fight from the replicated state instead (bar, music).
func _announce_if_missed(delta: float) -> void:
	if _announce_t < 0.0:
		return
	_announce_t -= delta
	if _announce_t > 0.0:
		return
	_announce_t = -1.0
	var gw := world()
	if gw == null or not engaged or dead or gw.active_boss() == self or dimension != gw.local_dimension:
		return
	Events.boss_engaged.emit(self, display_name)
	Events.boss_health_changed.emit(self, health, max_health, phase)
	Audio.set_music("boss")
