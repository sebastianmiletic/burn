class_name KrakenBoss
extends Boss
## The Abyssal Kraken, risen from the trench beneath its graveyard of ships.
##
## It holds the flooded pool in the middle of a ring of wreck decks and rock
## outcrops (the boss position is the mantle's anchor at the water line) and
## can only be hurt while its mantle is up out of the water (`flying` =
## surfaced, replicated). Players fight it from the decks; nothing needs
## swimming, and anyone who falls into the pool is spouted back onto a deck.
##   Phase 1: tentacle slam (a marked lane across a deck), sweep (one of two
##            deck bands), wreck grab (an arm tears up wreckage and hurls it
##            at the marked spots)
##   Phase 2: + ink cloud (a marked circle fills with blinding ink), + whirlpool
##            (the decks' pull towards the pool, then the arms close on the
##            inner edge), + drowned thralls climb onto the decks
##            + crush (two arms close on a marked spot and squeeze it)
##   Phase 3: + frenzy (slams in quick succession around the ring), + lash (a
##            feeding tentacle cracks down along a lane right across the
##            arena), faster tempo
## Also from phase 1: beak lunge (the mantle heaves over the pool edge at its
## target, a marked cone) and shift (it sinks, moves to another part of the
## pool and bursts up there, a marked ring of surf round where it rises), so
## its arms reach different decks as the fight goes on.
## Every damaging blow is telegraphed and lands when its marker fills.

const POOL := 9.0          ## radius of the open water in the middle
const DECK := 18.0         ## outer radius of the decks
const DRIFT := 2.0         ## how far the mantle drifts towards its target
const ROAM := 4.5          ## how far from the pool's centre the mantle may settle

var arena_center := Vector3.ZERO
var water_y := 13.0
var _spout_t := 0.0
## Where in the pool the mantle has settled (offset from the centre; `shift` moves it).
var _anchor := Vector3.ZERO


func _init() -> void:
	kind = "kraken"
	display_name = "The Abyssal Kraken"
	relic = "kraken_beak"
	xp_value = 2600
	base_health = 6200.0
	walk_speed = 4.0
	melee_range = 30.0
	aggro_radius = 26.0
	arena_radius = 24.0
	enrage_time = 600.0
	hit_radius = 7.6
	hit_height = 10.0
	body.half_extents = Vector3(3.0, 3.0, 3.0)
	body.fly = true
	body.collides = false
	body.gravity = 0.0
	loot = [["potion_greater", 1.0, 3, 5], ["kraken_ink", 1.0, 4, 7], ["pearl", 1.0, 3, 6], ["sapphire", 1.0, 2, 5],
		["gold_ore", 1.0, 10, 16], ["mithril_ore", 0.8, 3, 6], ["silver_ore", 1.0, 6, 10]]


func _ready() -> void:
	super._ready()
	if not ItemDB.exists(relic):
		relic = ""
	_set_arena(spawn_point)
	global_position = _rest_point()


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
	var km := model as KrakenModel
	if km != null:
		km.water_y = water_y
		km.arena_center = arena_center


func _rest_point() -> Vector3:
	return Vector3(arena_center.x + _anchor.x, water_y, arena_center.z + _anchor.z)


## The mantle drifts a little towards whoever it is fighting (in reach from the inner deck edge).
func _drift(delta: float, towards: Entity, reach := DRIFT) -> void:
	var goal := _rest_point()
	if towards != null:
		var to := towards.global_position - goal
		to.y = 0.0
		if to.length() > 0.5:
			goal += to.normalized() * reach
		_face(towards.global_position, delta, 3.0)
	global_position = global_position.lerp(goal, 1.0 - exp(-1.5 * delta))


# --- Damage: only the surfaced mantle can be hurt ----------------------------------------------

func take_damage(amount: float, source_id := 0, damage_kind := "hit") -> float:
	if not flying and engaged:
		return 0.0
	return super.take_damage(amount, source_id, damage_kind)


func _idle(delta: float) -> void:
	flying = false
	_drift(delta, null)
	yaw += delta * 0.1


func _approach(delta: float) -> void:
	# Between attacks the mantle sinks back under the water.
	flying = false
	_drift(delta, _target)


func _physics(delta: float) -> void:
	rotation.y = yaw
	if model != null:
		model.move_speed = 0.0
		model.grounded = true
		model.turn_rate = angle_difference(_last_yaw, yaw) / maxf(delta, 0.001)
		_last_yaw = yaw
		model.set_burning(burning > 0.0)
	_sync_model()


func _sync_model() -> void:
	var km := model as KrakenModel
	if km != null:
		km.surfaced = flying
		km.engaged = engaged


func _process(delta: float) -> void:
	super._process(delta)
	_sync_model()


func server_tick(delta: float) -> void:
	super.server_tick(delta)
	if engaged and not dead:
		_spout_fallen(delta)


## Anyone in the pool is thrown back up onto the decks by a spout (marked first).
func _spout_fallen(delta: float) -> void:
	_spout_t -= delta
	if _spout_t > 0.0:
		return
	_spout_t = 2.5
	for p in _players():
		var d := p.global_position - arena_center
		if Vector2(d.x, d.z).length() < POOL - 0.5 and d.y < -1.2:
			var at := Vector3(p.global_position.x, water_y, p.global_position.z)
			_tele("circle:spout", at, _fwd(), Vector3(3.0, 0, 0), 0.9, 8.0, "hit", 0.0,
				func() -> void: _fling_out(at, 3.5, 14.0))


## Throws everyone near `at` up and outward (onto the decks / over the rim).
func _fling_out(at: Vector3, radius: float, up: float) -> void:
	for p in _players():
		var d := p.global_position - at
		if Vector2(d.x, d.z).length() > radius:
			continue
		var out := p.global_position - arena_center
		out.y = 0.0
		out = out.normalized() if out.length() > 0.1 else Vector3.RIGHT
		_knockback(p, out * 7.0 + Vector3.UP * up)


func _engage() -> void:
	if engaged:
		return
	super._engage()
	_start("emerge")


func _reset() -> void:
	super._reset()
	_anchor = Vector3.ZERO
	global_position = _rest_point()


func _start(attack_name: String) -> void:
	_attack = attack_name
	_attack_t = 0.0
	_attack_data = {}
	_begin_attack(attack_name)


# --- Attacks -------------------------------------------------------------------------------

func _attacks() -> Dictionary:
	return {
		"slam": {"phase": 1, "weight": 3.0, "cooldown": 0.9},
		"sweep": {"phase": 1, "weight": 1.6, "cooldown": 1.1},
		"grab": {"phase": 1, "weight": 2.0, "cooldown": 1.2},
		"ink": {"phase": 2, "weight": 1.4, "cooldown": 1.4},
		"whirlpool": {"phase": 2, "weight": 1.1, "cooldown": 1.8},
		"summon": {"phase": 2, "weight": 1.3, "cooldown": 1.5, "ok": func() -> bool: return summons.size() < 3},
		"frenzy": {"phase": 3, "weight": 1.6, "cooldown": 1.6},
		"beak": {"phase": 1, "weight": 1.6, "cooldown": 1.0},
		"shift": {"phase": 1, "weight": 1.0, "cooldown": 0.8},
		"crush": {"phase": 2, "weight": 1.5, "cooldown": 1.2},
		"lash": {"phase": 3, "weight": 1.3, "cooldown": 1.3},
		"emerge": {"phase": 99, "weight": 0.0, "cooldown": 0.8},
	}


func _target_point() -> Vector3:
	var p := _target if _target != null else _random_player()
	var at := p.global_position if p != null else arena_center + Vector3(POOL + 4.0, 0, 0)
	at.y = arena_center.y
	return at


func _begin_attack(attack_name: String) -> void:
	match attack_name:
		"emerge":
			flying = true
			_play("roar", 2.0)
			Audio.play("leviathan_roar", global_position + Vector3(0, 6, 0), 6.0, 0.7)
			_shake_near(arena_center, 0.5)
		"slam":
			flying = true
			_slam(_target_point(), 1.25, 36.0)
		"sweep":
			flying = true
			_play("sweep", 2.0)
			var outer := _rng.randf() < 0.5
			var band := Vector3(POOL + 0.5, 13.5, 0) if outer else Vector3(13.5, DECK + 1.5, 0)
			_tele("ring:sweep", arena_center, _fwd(), band, 1.6, 28.0, "hit", 9.0,
				func() -> void: Audio.play("wave_crash", arena_center, 6.0))
		"grab":
			flying = true
			_play("throw", 2.4)
			_attack_data["shots"] = 0
			Audio.play("hit_heavy", arena_center, 3.0, 0.5)
		"ink":
			flying = false
			_play("cast", 1.8)
			var c := _target_point()
			_tele("circle:ink", c, _fwd(), Vector3(6.5, 0, 0), 1.6, 14.0, "hit", 0.0)
		"whirlpool":
			flying = false
			_play("summon", 3.0)
			# The water drags everyone on the decks towards the pool, then the arms close on the edge.
			_tele("ring:whirlpool", arena_center, _fwd(), Vector3(POOL - 0.5, DECK + 2.0, 0), 1.5, 8.0, "hit", -11.0)
			_tele("circle:maw", arena_center, _fwd(), Vector3(POOL + 2.8, 0, 0), 2.6, 34.0, "hit", 14.0,
				func() -> void:
					_shake_near(arena_center, 0.8)
					Audio.play("wave_crash", arena_center, 8.0))
		"summon":
			flying = true
			_play("roar", 1.8)
			_summon_drowned(2 if phase < 3 else 3)
		"frenzy":
			flying = true
			_play("slam", 3.0)
			_attack_data["slams"] = 0
			_attack_data["angle"] = _rng.randf() * TAU
		"beak":
			flying = true
			var at := _target_point()
			var origin := Vector3(global_position.x, arena_center.y, global_position.z)
			var to := at - origin
			to.y = 0.0
			var dir := to.normalized() if to.length() > 0.1 else _fwd()
			yaw = atan2(-dir.x, -dir.z)
			# The beak lunge peaks at 55 % of the model's action.
			_play("bite", 1.0 / 0.55)
			_tele("cone:bite", origin, dir, Vector3(POOL + 7.0, 50.0, 0), 1.0, 40.0, "hit", 10.0,
				func() -> void:
					_shake_near(origin + dir * 8.0, 0.6)
					Audio.play("hit_heavy", origin + dir * 8.0, 4.0, 0.5))
			Audio.play("roar", global_position + Vector3(0, 6, 0), 3.0, 0.6)
		"shift":
			flying = false
			_play("submerge", 1.6)
			var a := _rng.randf() * TAU
			var p := _target if _target != null else _random_player()
			if p != null and _rng.randf() < 0.7:
				# Rise on the side of the pool nearest the target (its arms reach those decks).
				a = atan2(p.global_position.z - arena_center.z, p.global_position.x - arena_center.x) + _rng.randf_range(-0.6, 0.6)
			_attack_data["to"] = Vector3(cos(a), 0, sin(a)) * _rng.randf_range(ROAM * 0.5, ROAM)
			Audio.play("splash_big", global_position, 4.0, 0.7)
		"crush":
			flying = true
			var at := _target_point()
			# The arms close at 62 % of the model's grab; the squeeze lands then.
			_play("grab", 1.5 / 0.62)
			_tele("circle:grab", at, _fwd(), Vector3(4.2, 0, 0), 1.5, 42.0, "hit", 6.0,
				func() -> void:
					_shake_near(at, 0.6)
					Audio.play("hit_heavy", at, 4.0, 0.4))
		"lash":
			flying = true
			var at := _target_point()
			var to := at - arena_center
			to.y = 0.0
			var dir := to.normalized() if to.length() > 0.1 else _fwd()
			var start := arena_center - dir * (DECK + 1.0)
			# The tentacle cracks down at 60 % of the model's whip.
			_play("whip", 1.3 / 0.6)
			_tele("line:lash", start, dir, Vector3((DECK + 1.0) * 2.0, 3.2, 0), 1.3, 38.0, "hit", 11.0,
				func() -> void:
					_shake_near(arena_center, 0.7)
					Audio.play("wave_crash", arena_center, 6.0, 0.8))


func _update_attack(attack_name: String, t: float, delta: float) -> bool:
	if attack_name == "beak":
		# Heave towards the target for the lunge, settle back after it.
		_drift(delta, _target, DRIFT * 2.5 if t < 1.2 else 0.0)
	elif attack_name != "shift":
		_drift(delta, _target)
	match attack_name:
		"beak":
			return t > 2.2
		"crush":
			return t > 2.8
		"lash":
			return t > 2.8
		"shift":
			return _update_shift(t, delta)
		"emerge":
			return t > 2.2
		"slam":
			return t > 2.4
		"sweep":
			return t > 2.4
		"grab":
			var shots: int = _attack_data.get("shots", 0)
			if shots < 2 + phase and t > 0.8 + shots * 0.45:
				_attack_data["shots"] = shots + 1
				_hurl_wreckage()
			return t > 3.2
		"ink":
			if t > 1.8:
				flying = true
			return t > 2.6
		"whirlpool":
			if t > 2.7:
				flying = true
			return t > 3.6
		"summon":
			return t > 2.0
		"frenzy":
			var n: int = _attack_data.get("slams", 0)
			var total := 4 + (1 if fight_time > enrage_time else 0)
			if n < total and t > 0.3 + n * 0.55:
				_attack_data["slams"] = n + 1
				var a := float(_attack_data["angle"]) + n * TAU / total * 1.37
				var aim := arena_center + Vector3(cos(a), 0, sin(a)) * (POOL + 4.0)
				_slam(aim, 1.1, 30.0)
			return t > 0.3 + total * 0.55 + 1.6
	return t > 4.0


## Sink, glide under the water to the new spot, then burst up there; the surf
## of its rising (a marked ring round the new spot) knocks back anyone at the pool edge.
func _update_shift(t: float, delta: float) -> bool:
	if t < 0.9:
		return false
	var to: Vector3 = _attack_data["to"]
	if t < 2.2:
		_anchor = _anchor.lerp(to, 1.0 - exp(-3.0 * delta))
		global_position = global_position.lerp(_rest_point(), 1.0 - exp(-4.0 * delta))
		if _target != null:
			_face(_target.global_position, delta, 2.0)
		return false
	if not _attack_data.has("rose"):
		_attack_data["rose"] = true
		_anchor = to
		var at := _rest_point()
		at.y = arena_center.y
		_tele("ring:wave", at, _fwd(), Vector3(POOL - 3.0, POOL + 4.0, 0), 1.0, 26.0, "hit", 10.0,
			func() -> void:
				flying = true
				_play("emerge", 1.8)
				_shake_near(at, 0.6)
				Audio.play("splash_big", at, 6.0, 0.8))
	global_position = global_position.lerp(_rest_point(), 1.0 - exp(-4.0 * delta))
	return t > 3.8


## A heavy blow while the mantle is up and its arms are idle makes it recoil.
func _flinch(dealt: float) -> void:
	if not engaged or not flying or _flinch_t > 0.0 or dealt < max_health * 0.015 or not is_server():
		return
	if not _pending.is_empty() or _attack in ["grab", "frenzy", "beak", "crush", "lash", "sweep", "slam"]:
		return
	_flinch_t = flinch_cooldown
	_play("hit", 0.7)


## A tentacle lifts and crashes down along a lane from the pool edge across the deck.
func _slam(at: Vector3, duration: float, base: float) -> void:
	var dir := at - arena_center
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else _fwd()
	var start := arena_center + dir * (POOL - 1.0)
	_play("slam", duration + 0.6)
	_tele("line:slam", start, dir, Vector3(DECK - POOL + 3.0, 3.6, 0), duration, base, "hit", 9.0,
		func() -> void:
			_shake_near(start + dir * 5.0, 0.7)
			Audio.play("hit_heavy", start + dir * 5.0, 4.0, 0.6))


## Wreckage torn from the graveyard and hurled at a marked spot.
func _hurl_wreckage() -> void:
	var w = _w()
	var p := _random_player()
	if w == null or p == null:
		return
	var target := p.global_position + Vector3(_rng.randf_range(-2.0, 2.0), 0.0, _rng.randf_range(-2.0, 2.0))
	var origin := global_position + Vector3(0, 9.0, 0)
	var flight := 1.3
	var g := 16.0
	var vel := (target - origin) / flight + Vector3(0, 0.5 * g * flight, 0)
	w.telegraph("circle:wreck", target, _fwd(), Vector3(3.4, 0, 0), flight, dimension)
	w.spawn_projectile("boulder", origin, vel, net_id, Team.MONSTERS, dimension, _dmg(30.0))


func _summon_drowned(count: int) -> void:
	var w = _w()
	if w == null:
		return
	for i in count:
		var a := _rng.randf() * TAU
		var pos := arena_center + Vector3(cos(a), 0, sin(a)) * (POOL + 3.0) + Vector3(0, 0.6, 0)
		var e: Entity = w.spawn_entity("drowned", pos, dimension, {"summoned": true})
		if e != null:
			summons.append(e)


func _on_phase_changed(_new_phase: int) -> void:
	_next_attack = 1.0
	if _attack == "":
		_start("emerge")
