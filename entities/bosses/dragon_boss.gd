class_name DragonBoss
extends Boss
## Ashvane, the dragon of the Keep.
##   Phase 1: bite (cone at the head), claw swipe (circle), tail sweep (cone behind),
##            fire breath (wide cone, then a sweeping stream that burns while you stand in it)
##   Phase 2: + fireball barrage at random players (each landing spot marked),
##            + wing gust (pushes everyone in front far back)
##   Phase 3: takes off, circles, marks a spot and dive-bombs it (repeats), plus everything above.


func _init() -> void:
	kind = "dragon"
	display_name = "Ashvane, the Last Dragon"
	relic = "dragonheart"
	xp_value = 1200
	base_health = 4200.0
	walk_speed = 3.6
	melee_range = 8.0
	aggro_radius = 30.0
	arena_radius = 40.0
	enrage_time = 540.0
	hit_radius = 3.0
	hit_height = 4.6
	body.half_extents = Vector3(1.8, 2.0, 1.8)
	loot = [["potion_greater", 1.0, 3, 5], ["ember_crystal", 1.0, 8, 12], ["gold_ore", 1.0, 10, 16], ["obsidian", 1.0, 4, 8]]


func _behind() -> bool:
	for p in _players():
		var to := p.global_position - global_position
		to.y = 0.0
		if to.length() < 13.0 and to.normalized().dot(_fwd()) < -0.35:
			return true
	return false


func _attacks() -> Dictionary:
	return {
		"bite": {"phase": 1, "weight": 3.0, "max": 10.0, "cooldown": 1.1},
		"claw": {"phase": 1, "weight": 2.0, "max": 7.0, "cooldown": 1.0},
		"tail": {"phase": 1, "weight": 3.0, "cooldown": 1.3, "ok": _behind},
		"breath": {"phase": 1, "weight": 2.0, "max": 18.0, "cooldown": 2.0},
		"barrage": {"phase": 2, "weight": 1.6, "cooldown": 1.8},
		"gust": {"phase": 2, "weight": 1.2, "max": 14.0, "cooldown": 1.6},
		"dive": {"phase": 3, "weight": 2.2, "cooldown": 1.5},
	}


func _head() -> Vector3:
	return global_position + _fwd() * 6.5 + Vector3(0, 1.0, 0)


func _begin_attack(name: String) -> void:
	match name:
		"bite":
			_play("bite", 0.9)
			_tele("cone", global_position + _fwd() * 3.0, _fwd(), Vector3(8.5, 26.0, 0), 0.65, 38.0, "hit", 5.0,
				func() -> void: Audio.play("growl", _head(), 2.0, 0.6))
		"claw":
			var right := _fwd().cross(Vector3.UP)
			var c := global_position + _fwd() * 4.0 + right * 1.6
			_play("claw", 0.9)
			_tele("circle", c, _fwd(), Vector3(3.8, 0, 0), 0.7, 30.0, "hit", 6.0,
				func() -> void: _fx_burst(c + Vector3(0, 0.3, 0), false, 1.0))
		"tail":
			_play("tail", 1.3)
			_tele("cone", global_position - _fwd() * 2.0, -_fwd(), Vector3(13.0, 70.0, 0), 0.95, 34.0, "hit", 11.0,
				func() -> void:
					_shake_near(global_position, 0.4)
					Audio.play("swing", global_position - _fwd() * 6.0, 4.0, 0.5))
		"breath":
			if _target != null:
				_face(_target.global_position, 1.0, 60.0)
			_attack_data["origin"] = global_position + _fwd() * 5.0
			_attack_data["dir"] = _fwd()
			_play("roar", 1.0)
			var w := world()
			if w != null:
				w.telegraph("cone", _attack_data["origin"], _fwd(), Vector3(17.0, 42.0, 0), 1.0, dimension)
		"barrage":
			_play("roar", 2.6)
			_attack_data["shots"] = 0
		"gust":
			_play("gust", 1.4)
			_tele("cone", global_position, _fwd(), Vector3(16.0, 55.0, 0), 0.9, 10.0, "hit", 17.0,
				func() -> void:
					Audio.play("wing_flap", center(), 6.0, 0.7)
					_shake_near(global_position, 0.5))
		"dive":
			_play("takeoff", 1.6)
			Audio.play("wing_flap", center(), 4.0, 0.8)


func _update_attack(name: String, t: float, delta: float) -> bool:
	match name:
		"bite":
			return t > 1.0
		"claw":
			return t > 1.0
		"tail":
			return t > 1.4
		"breath":
			if t > 1.0 and not _attack_data.has("flame"):
				_attack_data["flame"] = true
				_play("breath", 2.4)
				Audio.play("fireball_cast", _head(), 6.0, 0.6)
			if t > 1.3 and t < 3.0:
				_attack_data["tick"] = float(_attack_data.get("tick", 0.0)) - delta
				if float(_attack_data["tick"]) <= 0.0:
					_attack_data["tick"] = 0.3
					_hit_shape("cone", _attack_data["origin"], _attack_data["dir"], Vector3(17.0, 42.0, 0), _dmg(9.0), "fire", 0.0)
			return t > 3.3
		"barrage":
			var shots: int = _attack_data["shots"]
			if shots < 6 and t > 0.4 + shots * 0.38:
				_attack_data["shots"] = shots + 1
				_fireball_at_player()
			return t > 3.2
		"gust":
			return t > 1.5
		"dive":
			return _update_dive(t, delta)
	return true


func _fireball_at_player() -> void:
	var w := world()
	var p := _random_player()
	if w == null or p == null:
		return
	var target := p.global_position + Vector3(_rng.randf_range(-1.5, 1.5), 0.0, _rng.randf_range(-1.5, 1.5))
	var origin := _head() + Vector3(0, 1.5, 0)
	var flight := 1.0
	w.telegraph("circle", target, _fwd(), Vector3(2.4, 0, 0), flight, dimension)
	w.spawn_projectile("fireball", origin, (target - origin) / flight, net_id, Team.MONSTERS, dimension, _dmg(26.0))


## Take off, circle above the arena, mark a spot, dive onto it, land.
func _update_dive(t: float, delta: float) -> bool:
	if t < 1.6:
		flying = true
		body.fly = true
		body.velocity = Vector3(0, 9.0 if t > 0.4 else 0.0, 0)
	elif t < 3.4:
		if _attack_data.get("phase", "") != "circle":
			_attack_data["phase"] = "circle"
			_play("fly")
		var target := _target.global_position if _target != null else spawn_point
		var above := target + Vector3(0, 13.0, 0)
		var to := above - global_position
		body.velocity = to.limit_length(14.0)
		_face(target, delta, 3.0)
	elif t < 4.4:
		if not _attack_data.has("mark"):
			var target := _target.global_position if _target != null else spawn_point
			_attack_data["mark"] = target
			_tele("circle", target, _fwd(), Vector3(6.5, 0, 0), 1.6, 55.0, "fire", 15.0,
				func() -> void:
					_fx_burst(target + Vector3(0, 0.5, 0), true, 2.2)
					_shake_near(target, 1.0)
					Audio.play("explosion", target, 6.0, 0.7))
		body.velocity = body.velocity.lerp(Vector3.ZERO, 1.0 - exp(-3.0 * delta))
		_face(_attack_data["mark"], delta, 6.0)
	elif t < 5.0:
		if _attack_data.get("phase", "") != "dive":
			_attack_data["phase"] = "dive"
			_play("dive", 0.7)
			Audio.play("roar_big", center(), 4.0, 1.1)
		var mark: Vector3 = _attack_data["mark"] + Vector3(0, 0.5, 0)
		var remaining := maxf(0.05, 5.0 - t)
		body.velocity = (mark - global_position) / remaining
		_face(mark, delta, 10.0)
	elif t < 6.2:
		if flying:
			flying = false
			body.fly = false
			body.velocity = Vector3.ZERO
			_play("land", 1.0)
	else:
		return true
	return false


func _on_phase_changed(new_phase: int) -> void:
	_play("roar", 1.4)
	Audio.play("roar_big", center(), 5.0, 0.8)
	_shake_near(global_position, 0.6)
	_next_attack = 1.2
	if new_phase == 3 and _attack == "":
		_attack = "dive"
		_attack_t = 0.0
		_attack_data = {}
		_begin_attack("dive")


func _reset() -> void:
	flying = false
	body.fly = false
	super._reset()
