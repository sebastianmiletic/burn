class_name LeviathanBoss
extends Boss
## The Leviathan, terror of the Grey Sea, coiled around the Drowned Spire.
##
## It never leaves the water: it circles the islet's platform (the boss
## position is its head at the water line) and can only be hurt while its
## head is out of the water (`flying` = surfaced, replicated to clients).
##   Phase 1: bite (rears up at the platform edge, lunges, then rests its head
##            on the edge - the opening to hit it), bile spit (lobbed globs,
##            landing spots marked), tail slam (the tail lifts out of the sea
##            and crashes across the platform), geysers under every player
##   Phase 2: + tidal wave (sweeps two thirds of the platform; one strip stays
##            dry), + calls drowned thralls up the islet's sides, + head sweep
##            (rears at the edge and swings its head across a marked cone),
##            + coil (races round the islet; its coils crush the platform rim)
##   Phase 3: + breach (leaps clean over the platform along a marked lane),
##            + maelstrom (rings of geysers with safe bands), + frenzy (three
##            snapping bites at whoever is nearest, one after another), faster tempo
## Between attacks it circles the islet, reversing direction now and then, and
## surfaces wherever its target stands. A heavy blow while its head rests on
## the platform makes it recoil.
## Every damaging blow is telegraphed and lands when its marker fills.

const RING := 23.0         ## circling radius around the platform centre while fighting
const IDLE_RING := 30.0
const PLATFORM := 16.0     ## platform radius

var arena_center := Vector3.ZERO
var water_y := 13.0
var _angle := 0.0
var _dir := 1.0
var _breach := {}


func _init() -> void:
	kind = "leviathan"
	display_name = "The Leviathan"
	relic = "leviathan_heart"
	xp_value = 2200
	base_health = 5600.0
	walk_speed = 8.0
	melee_range = 30.0
	aggro_radius = 34.0
	arena_radius = 34.0
	enrage_time = 600.0
	hit_radius = 5.0
	hit_height = 9.0
	body.half_extents = Vector3(2.0, 2.0, 2.0)
	body.fly = true
	body.collides = false
	body.gravity = 0.0
	loot = [["potion_greater", 1.0, 3, 5], ["gold_ore", 1.0, 12, 18], ["ember_crystal", 1.0, 6, 10],
		["sapphire", 1.0, 3, 6], ["pearl", 1.0, 2, 5], ["leviathan_scale", 1.0, 4, 8], ["mithril_ore", 0.8, 3, 6],
		["silver_ore", 1.0, 6, 10], ["frost_shard", 0.6, 2, 4]]


func _ready() -> void:
	super._ready()
	if not ItemDB.exists(relic):
		relic = ""
	_set_arena(spawn_point)
	_angle = _rng.randf() * TAU
	global_position = _ring_point(IDLE_RING)


func on_spawned(data: Dictionary) -> void:
	# Late-joining clients get the boss's current position as their spawn
	# position; the arena comes from the (deterministic) location instead.
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
	var lm := model as LeviathanModel
	if lm != null:
		lm.water_y = water_y
		lm.arena_center = arena_center
		lm.platform_y = center.y


func _ring_point(radius: float) -> Vector3:
	return arena_center + Vector3(cos(_angle), 0, sin(_angle)) * radius + Vector3(0, water_y - arena_center.y, 0)


func _angle_of(p: Vector3) -> float:
	return atan2(p.z - arena_center.z, p.x - arena_center.x)


## Swim along the ring at `speed`; face along the swim direction (or the arena).
func _swim(radius: float, speed: float, delta: float, face_center := false) -> void:
	_angle = wrapf(_angle + _dir * speed / radius * delta, -PI, PI)
	var target := _ring_point(radius)
	global_position = global_position.lerp(target, 1.0 - exp(-5.0 * delta))
	if face_center:
		_face(arena_center, delta, 6.0)
	else:
		var tangent := Vector3(-sin(_angle), 0, cos(_angle)) * _dir
		_face(global_position + tangent, delta, 4.0)


## Swim towards `angle`; true once there.
func _travel(angle: float, delta: float, speed := 16.0) -> bool:
	var diff := angle_difference(_angle, angle)
	if absf(diff) < 0.06:
		return true
	_dir = signf(diff)
	_swim(RING, minf(speed, absf(diff) * RING / maxf(delta, 0.001)), delta)
	return false


# --- Damage: only the surfaced head can be hurt ------------------------------------------

func take_damage(amount: float, source_id := 0, damage_kind := "hit") -> float:
	if not flying and engaged:
		return 0.0
	return super.take_damage(amount, source_id, damage_kind)


# --- Movement overrides ------------------------------------------------------------------

func _idle(delta: float) -> void:
	flying = false
	_swim(IDLE_RING, 3.5, delta)


func _approach(delta: float) -> void:
	flying = false
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe_t = 5.0 + _rng.randf() * 6.0
		if _rng.randf() < 0.45:
			_dir = -_dir
	# It swims a little wider or tighter as it circles, so the coils move.
	_swim(RING + sin(fight_time * 0.4) * 3.0, 7.0 + phase * 1.5, delta)


func _physics(delta: float) -> void:
	rotation.y = yaw
	if model != null:
		model.move_speed = walk_speed
		model.grounded = true
		model.turn_rate = angle_difference(_last_yaw, yaw) / maxf(delta, 0.001)
		_last_yaw = yaw
		model.set_burning(burning > 0.0)
	_sync_model()


func _sync_model() -> void:
	var lm := model as LeviathanModel
	if lm != null:
		lm.surfaced = flying
		lm.engaged = engaged


func _process(delta: float) -> void:
	super._process(delta)
	_sync_model()


func _engage() -> void:
	if engaged:
		return
	super._engage()
	_start("emerge")


func _reset() -> void:
	super._reset()
	_breach.clear()
	global_position = _ring_point(IDLE_RING)


func _start(name: String) -> void:
	_attack = name
	_attack_t = 0.0
	_attack_data = {}
	_begin_attack(name)


# --- Attacks ------------------------------------------------------------------------------

func _attacks() -> Dictionary:
	return {
		"bite": {"phase": 1, "weight": 3.0, "cooldown": 1.0},
		"spit": {"phase": 1, "weight": 2.0, "cooldown": 1.2},
		"tail": {"phase": 1, "weight": 2.2, "cooldown": 1.0},
		"geyser": {"phase": 1, "weight": 1.5, "cooldown": 0.8},
		"wave": {"phase": 2, "weight": 1.3, "cooldown": 1.6},
		"summon": {"phase": 2, "weight": 0.8, "cooldown": 1.5, "ok": func() -> bool: return summons.size() < 3},
		"breach": {"phase": 3, "weight": 1.8, "cooldown": 1.4},
		"maelstrom": {"phase": 3, "weight": 1.1, "cooldown": 1.6},
		"sweep": {"phase": 2, "weight": 1.4, "cooldown": 1.2},
		"coil": {"phase": 2, "weight": 1.0, "cooldown": 1.4},
		"frenzy": {"phase": 3, "weight": 1.4, "cooldown": 1.6},
		"emerge": {"phase": 99, "weight": 0.0, "cooldown": 0.8},
	}


func _begin_attack(name: String) -> void:
	_attack_data["stage"] = "travel"
	_attack_data["stage_t"] = 0.0
	match name:
		"bite", "spit", "summon", "sweep", "frenzy":
			var p := _target if _target != null else _random_player()
			var a := _angle_of(p.global_position) if p != null else _angle
			if name == "spit":
				a += _rng.randf_range(-0.7, 0.7)
			_attack_data["angle"] = a
		"emerge":
			_attack_data["angle"] = _angle
		"wave":
			var a := _rng.randf() * TAU
			_attack_data["dir"] = Vector3(cos(a), 0, sin(a))
			_attack_data["angle"] = a + PI
			_attack_data["offset"] = 7.0 if _rng.randf() < 0.5 else -7.0
		"breach":
			var p := _target if _target != null else _random_player()
			_attack_data["angle"] = _angle_of(p.global_position) + PI if p != null else _angle
		"tail":
			_tail_slam()
		"geyser":
			_geysers(1)
		"maelstrom":
			_maelstrom()
		"coil":
			_coil()


func _stage(name: String) -> void:
	_attack_data["stage"] = name
	_attack_data["stage_t"] = 0.0


func _update_attack(name: String, t: float, delta: float) -> bool:
	var stage: String = _attack_data.get("stage", "")
	_attack_data["stage_t"] = float(_attack_data.get("stage_t", 0.0)) + delta
	var st: float = _attack_data["stage_t"]
	match name:
		"tail":
			_swim(RING, 3.0, delta)
			return t > 2.2
		"geyser":
			_swim(RING, 6.0, delta)
			return t > 1.7
		"maelstrom":
			_swim(RING, 12.0, delta)
			return t > 3.4
		"coil":
			_swim(PLATFORM + 4.0, 20.0, delta)
			return t > 2.9
		"breach":
			return _update_breach(stage, st, delta)
	# Surface-and-act attacks: travel -> rise -> act -> linger -> sink.
	match stage:
		"travel":
			if _travel(float(_attack_data["angle"]), delta) or st > 3.0:
				_stage("rise")
				flying = true
				Audio.play("splash_big", global_position, 6.0)
		"rise":
			_swim(RING - 2.5, 0.0, delta, true)
			if st > 1.0:
				_stage("act")
				_act(name)
		"act":
			_swim(RING - 2.5, 0.0, delta, true)
			_act_update(name, st)
			var act_len := {"bite": 1.6, "spit": 2.6, "emerge": 2.0, "summon": 1.8, "wave": 2.4, "sweep": 2.0, "frenzy": 3.2}
			if st > float(act_len.get(name, 1.5)):
				_stage("linger")
		"linger":
			_swim(RING - 2.5, 0.0, delta, true)
			var linger := {"bite": 2.0, "spit": 1.0, "emerge": 0.8, "summon": 0.6, "wave": 0.8, "sweep": 1.2, "frenzy": 1.8}
			if st > float(linger.get(name, 1.0)) - (0.6 if phase == 3 else 0.0):
				_stage("sink")
				_play("dive", 1.0)
		"sink":
			_swim(RING, 4.0, delta)
			if st > 0.35:
				flying = false
			if st > 1.0:
				return true
	return t > 14.0


func _act(name: String) -> void:
	match name:
		"bite":
			_snap(_target if _target != null else _random_player(), 0.8, 46.0)
		"frenzy":
			_attack_data["snaps"] = 1
			_snap(_nearest_player(), 0.7, 34.0)
			Audio.play("leviathan_roar", global_position + Vector3(0, 8, 0), 5.0, 1.2)
		"sweep":
			# The head rears at the edge and swings across a cone of the platform.
			var to := arena_center - global_position
			to.y = 0.0
			var dir := to.normalized() if to.length() > 0.1 else _fwd()
			_face(arena_center, 1.0, 60.0)
			_play("swipe", 2.0)
			var origin := global_position
			origin.y = arena_center.y
			_tele("cone:wave", origin, dir, Vector3(RING + 2.0, 70.0, 0), 1.1, 38.0, "hit", 11.0,
				func() -> void:
					_shake_near(arena_center, 0.5)
					Audio.play("wave_crash", arena_center, 5.0, 0.8))
		"spit":
			_play("breath", 1.6)
			_attack_data["shots"] = 0
			Audio.play("roar", global_position + Vector3(0, 8, 0), 2.0, 0.7)
		"emerge", "summon":
			_play("summon" if name == "summon" else "roar", 1.8)
			Audio.play("leviathan_roar", global_position + Vector3(0, 8, 0), 6.0)
			_shake_near(global_position, 0.5)
			if name == "summon":
				_summon_drowned(2 if phase < 3 else 3)
		"wave":
			_play("roar", 2.0)
			var dir: Vector3 = _attack_data["dir"]
			var side := Vector3(-dir.z, 0, dir.x)
			var start := arena_center - dir * (PLATFORM + 8.0) + side * float(_attack_data["offset"])
			_tele("line:wave", start, dir, Vector3((PLATFORM + 8.0) * 2.0, 20.0, 0), 2.2, 40.0, "hit", 14.0,
				func() -> void:
					_shake_near(arena_center, 0.7)
					Audio.play("wave_crash", arena_center, 8.0))


func _act_update(name: String, st: float) -> void:
	if name == "frenzy":
		var snaps: int = _attack_data.get("snaps", 1)
		if snaps < 3 and st > snaps * 1.05:
			_attack_data["snaps"] = snaps + 1
			_snap(_nearest_player(), 0.7, 34.0)
		return
	if name != "spit":
		return
	var shots: int = _attack_data.get("shots", 0)
	var total := 3 + phase
	if shots < total and st > 0.5 + shots * 0.3:
		_attack_data["shots"] = shots + 1
		_bile_at_player()


## The head lunges and bites at `p` (a marked circle at the platform edge).
func _snap(p: Entity, tele: float, base: float) -> void:
	var head := global_position
	var aim := (p.global_position if p != null else arena_center) - head
	aim.y = 0.0
	aim = aim.limit_length(13.0)
	if aim.length() < 6.0:
		aim = aim.normalized() * 6.0 if aim.length() > 0.1 else _fwd() * 6.0
	var c := head + aim
	c.y = arena_center.y
	_face(c, 1.0, 60.0)
	# The model's bite lunge peaks halfway through its action.
	_play("bite", tele * 2.0)
	_tele("circle:bite", c, aim.normalized(), Vector3(5.0, 0, 0), tele, base, "hit", 8.0,
		func() -> void:
			_shake_near(c, 0.6)
			Audio.play("hit_heavy", c, 4.0, 0.6))


func _nearest_player() -> Entity:
	var best: Entity = null
	var best_d := INF
	for p in _players():
		var d := p.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	return best if best != null else _target


## The Leviathan races round the islet; its coils crush the platform's rim
## (a marked band) and throw whoever stands there inwards.
func _coil() -> void:
	_play("whip", 2.8)
	Audio.play("wave_crash", arena_center, 6.0, 0.7)
	_tele("ring:wave", arena_center, _fwd(), Vector3(PLATFORM - 4.0, PLATFORM + 2.0, 0), 2.0, 36.0, "hit", -9.0,
		func() -> void:
			_shake_near(arena_center, 0.7)
			Audio.play("hit_heavy", arena_center, 6.0, 0.5))


## A heavy blow while its head rests on the platform makes it recoil (the
## base flinch only reacts outside attacks, and this boss is only hurt in them).
func _flinch(dealt: float) -> void:
	if not engaged or _flinch_t > 0.0 or dealt < max_health * 0.015 or not is_server():
		return
	if String(_attack_data.get("stage", "")) != "linger":
		return
	_flinch_t = flinch_cooldown
	_play("hit", 0.6)


func _bile_at_player() -> void:
	var w = _w()
	var p := _random_player()
	if w == null or p == null:
		return
	var target := p.global_position + Vector3(_rng.randf_range(-2.0, 2.0), 0.0, _rng.randf_range(-2.0, 2.0))
	var origin := global_position + Vector3(0, 8.0, 0) + _fwd() * 3.0
	var flight := 1.1
	var g := 9.0
	var vel := (target - origin) / flight + Vector3(0, 0.5 * g * flight, 0)
	w.telegraph("circle:bile", target, _fwd(), Vector3(2.6, 0, 0), flight, dimension)
	w.spawn_projectile("bile", origin, vel, net_id, Team.MONSTERS, dimension, _dmg(24.0))


## The tail lifts out of the sea behind the head and crashes across the platform.
func _tail_slam() -> void:
	var tip := Vector3.INF
	var lm := model as LeviathanModel
	if lm != null and lm.chain != null and lm.chain._ready_chain:
		tip = lm.chain.tail_tip()
	if not tip.is_finite() or Vector2(tip.x - arena_center.x, tip.z - arena_center.z).length() > RING * 2.0:
		var a := _angle - _dir * 1.7
		tip = arena_center + Vector3(cos(a), 0, sin(a)) * RING
	tip.y = arena_center.y
	var to := arena_center - tip
	to.y = 0.0
	var dir := to.normalized() if to.length() > 0.1 else -_fwd()
	_play("slam", 2.0)
	_tele("line:tail", tip, dir, Vector3(21.0, 7.0, 0), 1.4, 42.0, "hit", 10.0,
		func() -> void:
			_shake_near(tip + dir * 12.0, 0.8)
			Audio.play("wave_crash", tip + dir * 12.0, 6.0))


func _geysers(extra: int) -> void:
	var ps := _players()
	for p in ps:
		var c := p.global_position
		c.y = arena_center.y
		_tele("circle:geyser", c, _fwd(), Vector3(3.2, 0, 0), 1.3, 30.0, "hit", 9.0)
	if phase >= 2:
		for i in extra + 1:
			var a := _rng.randf() * TAU
			var c := arena_center + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(3.0, PLATFORM - 2.0)
			_tele("circle:geyser", c, _fwd(), Vector3(3.2, 0, 0), 1.5, 30.0, "hit", 9.0)
	Audio.play("splash", arena_center, 4.0, 0.6)


## Rings of geysers with safe bands between them, then the other bands.
func _maelstrom() -> void:
	_play("roar", 0.5)
	var first := [Vector2(0.0, 4.5), Vector2(8.5, 12.5)]
	var second := [Vector2(4.5, 8.5), Vector2(12.5, PLATFORM + 2.0)]
	for b: Vector2 in first:
		_tele("ring:geyser", arena_center, _fwd(), Vector3(b.x, b.y, 0), 1.4, 34.0, "hit", 8.0)
	for b: Vector2 in second:
		_tele("ring:geyser", arena_center, _fwd(), Vector3(b.x, b.y, 0), 2.6, 34.0, "hit", 8.0)


func _update_breach(stage: String, st: float, delta: float) -> bool:
	match stage:
		"travel":
			if _travel(float(_attack_data["angle"]), delta) or st > 3.0:
				_stage("mark")
				var start := _ring_point(RING)
				start.y = arena_center.y
				var dir := arena_center - start
				dir.y = 0.0
				dir = dir.normalized()
				_breach = {"start": _ring_point(RING), "end": _ring_point(RING) + dir * RING * 2.0}
				_tele("line:breach", start, dir, Vector3(RING * 2.0, 9.0, 0), 1.9, 55.0, "hit", 12.0,
					func() -> void:
						_shake_near(arena_center, 1.0)
						Audio.play("explosion", arena_center, 4.0, 0.5))
				_play("dive", 1.0)
		"mark":
			_swim(RING + 2.0, 0.0, delta, true)
			if st > 1.2:
				_stage("leap")
				flying = true
				_play("roar", 1.3)
				Audio.play("leviathan_roar", global_position, 6.0)
		"leap":
			var f := clampf(st / 1.3, 0.0, 1.0)
			var a: Vector3 = _breach["start"]
			var b: Vector3 = _breach["end"]
			var pos := a.lerp(b, f)
			pos.y = water_y + sin(PI * f) * 15.0
			_face(b, delta, 8.0)
			global_position = pos
			if f >= 1.0:
				_angle = _angle_of(b)
				_stage("sink")
				flying = false
		"sink":
			_swim(RING, 5.0, delta)
			if st > 1.0:
				return true
	return false


func _summon_drowned(count: int) -> void:
	var w = _w()
	if w == null:
		return
	for i in count:
		var a := _angle + (float(i) - (count - 1) * 0.5) * 0.45
		var pos := arena_center + Vector3(cos(a), 0, sin(a)) * (PLATFORM - 2.5) + Vector3(0, 0.6, 0)
		var e: Entity = w.spawn_entity("drowned", pos, dimension, {"summoned": true})
		if e != null:
			summons.append(e)


func _on_phase_changed(_new_phase: int) -> void:
	_next_attack = 1.0
	_dir = -_dir
	if _attack == "":
		_start("emerge")
