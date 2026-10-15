class_name Boss
extends Entity
## Base for the five bosses.
##
## Server: engages when a player comes within `aggro_radius` of its arena,
## scales health to the party, tracks a threat table (damage per player),
## moves into range of its target and picks attacks from `_attacks()` for the
## current phase (1: 100-66 %, 2: 66-33 %, 3: 33-0 %). Heavy attacks always go
## through `_tele()`: the ground warning is shown first and the damage lands
## only when it has filled. After `enrage_time` the boss hits harder and
## faster. If the whole party dies or leaves, it resets.
##
## Replication: snapshot() adds [phase, engaged, flying]; `anim` indexes
## ACTIONS and `anim_time` stamps when it started.

const ACTIONS := ["", "attack", "attack2", "sweep", "slam", "roar", "bite", "claw", "tail", "breath", "gust",
		"takeoff", "land", "dive", "pounce", "howl", "summon", "throw", "cast", "spikes", "teleport", "hit", "fly"]

var phase := 1
var engaged := false
var flying := false
var relic := ""
var loot: Array = []
var xp_value := 500
var aggro_radius := 24.0
var arena_radius := 45.0
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
## Headless simulation hook (tests): when set, used instead of GameWorld.instance.
var sim_world: Object = null


## The world this creature acts in (duck-typed so tests can stand in for GameWorld).

func is_boss() -> bool:
	return true


## GameWorld keeps ticking an engaged boss even when nobody is near, so an
## abandoned fight times out and resets (reopening the arena).
func is_engaged() -> bool:
	return engaged

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
	# Scale encounter health before applying the opening hit. Doing this in
	# _on_damaged used to heal away the first strike (even a killing blow).
	if not engaged and not dead and amount > 0 and source_id != 0:
		_engage()
	var resist_kind := "fire" if damage_kind in ["fire", "burn"] else "hit"
	var dealt := super.take_damage(Damage.apply(amount, kind, resist_kind), source_id, damage_kind)
	if dealt > 0.0 and source_id != 0 and damage_kind != "burn":
		threat[source_id] = float(threat.get(source_id, 0.0)) + dealt
	return dealt


func _on_damaged(amount: float, source_id: int, damage_kind: String) -> void:
	if damage_kind == "fire":
		burning = Damage.BURN_SECONDS * 0.6
	if model != null:
		model.flash(Color(1.0, 0.6, 0.35) if damage_kind in ["fire", "burn"] else Color(1, 1, 1))
	Events.damage_number.emit(center() + Vector3(0, hit_height * 0.35, 0), int(round(amount)), damage_kind == "crit", "fire" if damage_kind in ["fire", "burn"] else "hit")
	Events.boss_health_changed.emit(self, health, max_health, phase)


func _on_died() -> void:
	engaged = false
	_attack = ""
	_pending.clear()
	burning = 0.0
	if model != null:
		model.set_dead(true)
		model.set_burning(false)
	Events.slow_motion.emit(1.6, 0.3)
	Events.screen_shake.emit(0.8)
	Events.boss_health_changed.emit(self, 0.0, max_health, phase)
	Audio.play("roar_big", center(), 2.0, 0.7)
	if is_server():
		for s in summons:
			if is_instance_valid(s) and not s.dead:
				s.take_damage(s.health + 1.0, net_id, "hit")
		var w = _w()
		if w != null:
			w.boss_finished(self)


# --- Snapshot ---------------------------------------------------------------------

func snapshot() -> Array:
	var s := super.snapshot()
	s.append_array([phase, 1 if engaged else 0, 1 if flying else 0])
	return s


func apply_snapshot(s: Array, at_time: float) -> void:
	super.apply_snapshot(s, at_time)
	if s.size() >= 10:
		phase = int(s[7])
		engaged = int(s[8]) == 1
		flying = int(s[9]) == 1


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
	_tick_burn(delta)
	_tick_pending(delta)
	summons = summons.filter(func(e: Entity) -> bool: return is_instance_valid(e) and not e.dead)
	if not engaged:
		_idle(delta)
		if _check_engage():
			_engage()
		_physics(delta)
		return
	fight_time += delta
	var new_phase := BossLogic.phase_for(health / max_health)
	if new_phase > phase:
		phase = new_phase
		_on_phase_changed(phase)
		Events.boss_health_changed.emit(self, health, max_health, phase)
	_pick_target()
	if _target == null:
		_reset_t += delta
		if _reset_t > 8.0:
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
	return p != null and not p.dead


func _engage() -> void:
	if engaged:
		return
	engaged = true
	fight_time = 0.0
	threat.clear()
	var w = _w()
	var party := 1
	if w != null:
		party = maxi(1, _players().size())
	max_health = Damage.boss_health(base_health, party)
	health = max_health
	phase = 1
	_next_attack = 2.0
	_play("roar")
	Audio.play("roar_big", center(), 2.0)
	Events.screen_shake.emit(0.4)
	if w != null:
		w.boss_started(self)
	Events.boss_health_changed.emit(self, health, max_health, phase)


func _reset() -> void:
	engaged = false
	_attack = ""
	_pending.clear()
	threat.clear()
	health = max_health
	phase = 1
	flying = false
	body.fly = false
	_reset_t = 0.0
	global_position = spawn_point
	for s in summons:
		if is_instance_valid(s) and not s.dead:
			var w0 = _w()
			if w0 != null:
				w0.despawn_entity(s)
	summons.clear()
	var w = _w()
	if w != null and w.has_method("boss_reset"):
		w.call("boss_reset", self)
	Events.boss_health_changed.emit(self, health, max_health, phase)


func _players() -> Array[Entity]:
	var out: Array[Entity] = []
	var w = _w()
	if w == null:
		return out
	for p in w.players_in(dimension):
		if not p.dead and Vector2(p.global_position.x - spawn_point.x, p.global_position.z - spawn_point.z).length() < arena_radius * 1.6:
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
			if knockback > 0.0:
				var away := p.global_position - (pos if shape in ["circle", "ring"] else global_position)
				away.y = 0.0
				if away.length() < 0.1:
					away = dir
				_knockback(p, away.normalized() * knockback + Vector3(0, knockback * 0.45, 0))


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


# --- Client presentation ----------------------------------------------------------

func _process(delta: float) -> void:
	if model == null:
		return
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
		if _last_health >= 0.0 and health < _last_health - 0.01:
			model.flash()
			Events.damage_number.emit(center() + Vector3(0, hit_height * 0.35, 0), int(round(_last_health - health)), false, "hit")
			Events.boss_health_changed.emit(self, health, max_health, phase)
		if engaged != _last_engaged:
			Events.boss_health_changed.emit(self, health, max_health, phase)
		if dead and not model._dead:
			model.set_dead(true)
		if anim != _last_anim[0] or anim_time != _last_anim[1]:
			_last_anim = [anim, anim_time]
			if anim > 0 and anim < ACTIONS.size() and not dead:
				model.play(ACTIONS[anim])
	_last_health = health
	_last_engaged = engaged
	_last_pos = global_position
