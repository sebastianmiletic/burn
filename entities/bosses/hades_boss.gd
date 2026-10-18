class_name HadesBoss
extends Boss
## Hades, lord of the underworld. The final boss.
## He glides around his foes between blows and vanishes to strike from behind.
##   Phase 1: bident sweep (wide cone), soul bolt barrage (homing bolts),
##            double-pronged lunge (narrow line)
##   Phase 2: + pillars of fire (lines towards players), + summon shades,
##            + teleport behind a player and sweep, + chains of the dead
##            (lines to every player that drag them towards him)
##   Phase 3: + arena-wide rings with safe gaps between them, + a reaping
##            combination (cone, cone, line), bigger volleys, everything faster
## Model timings come from HadesModel.IMPACT / BOLT_TIME / COMBO.


func _init() -> void:
	kind = "hades"
	display_name = "Hades, Lord of the Dead"
	relic = "crown_of_hades"
	xp_value = 3000
	base_health = 5200.0
	walk_speed = 3.2
	melee_range = 6.0
	aggro_radius = 28.0
	arena_radius = 36.0
	enrage_time = 600.0
	hit_radius = 1.3
	hit_height = 5.0
	strafe_speed = 1.5
	body.half_extents = Vector3(0.9, 2.4, 0.9)
	loot = [["potion_greater", 1.0, 4, 6], ["hellstone", 1.0, 10, 16], ["gold_ore", 1.0, 20, 30]]


func _attacks() -> Dictionary:
	return {
		"sweep": {"phase": 1, "weight": 3.0, "max": 7.5, "cooldown": 1.0},
		"bolts": {"phase": 1, "weight": 2.0, "min": 4.0, "cooldown": 1.4},
		"thrust": {"phase": 1, "weight": 1.6, "min": 3.0, "max": 10.0, "cooldown": 1.1},
		"chains": {"phase": 2, "weight": 1.2, "min": 6.0, "cooldown": 1.6},
		"combo": {"phase": 3, "weight": 1.5, "max": 7.5, "cooldown": 1.6},
		"pillars": {"phase": 2, "weight": 2.0, "cooldown": 1.6},
		"summon": {"phase": 2, "weight": 0.9, "cooldown": 2.0, "ok": func() -> bool: return summons.size() < 3},
		"teleport": {"phase": 2, "weight": 1.2, "min": 8.0, "cooldown": 0.6},
		"rings": {"phase": 3, "weight": 2.0, "cooldown": 2.2},
	}


func _begin_attack(name: String) -> void:
	match name:
		"sweep":
			_sweep()
		"thrust":
			_turn_to(_aim())
			_play("thrust", 0.8 / HadesModel.IMPACT["thrust"])
			_attack_data["dir"] = _fwd()
			_tele("line:spirit", global_position, _fwd(), Vector3(10.0, 2.0, 0), 0.8, 40.0, "hit", 6.0,
				func() -> void: Audio.play("swing", center(), 3.0, 0.7))
		"chains":
			_play("pull", 1.0 / HadesModel.IMPACT["pull"])
			Audio.play("bone_rattle", center(), 3.0, 0.5)
			for p in _players():
				var d := p.global_position - global_position
				d.y = 0.0
				_tele("line:spirit", global_position, d.normalized(), Vector3(minf(d.length() + 4.0, 24.0), 2.2, 0), 1.0, 20.0, "fire", -9.0)
		"combo":
			_turn_to(_aim())
			_play("combo", HadesModel.COMBO_TIME)
			_tele("cone", global_position, _fwd(), Vector3(7.5, 75.0, 0), HadesModel.COMBO[0] * HadesModel.COMBO_TIME, 30.0, "hit", 5.0)
		"bolts":
			_play("cast" if phase < 3 else "volley", HadesModel.BOLT_TIME[0 if phase < 3 else 1])
			_attack_data["shots"] = 0
			Audio.play("fireball_cast", center(), 2.0, 0.6)
		"pillars":
			_play("smash", 1.3 / HadesModel.IMPACT["smash"])
			var dirs: Array[Vector3] = []
			for p in _players():
				var d := p.global_position - global_position
				d.y = 0.0
				dirs.append(d.normalized())
			while dirs.size() < 4:
				var a := _rng.randf() * TAU
				dirs.append(Vector3(cos(a), 0, sin(a)))
			for d in dirs:
				_tele("line:spirit", global_position, d, Vector3(22.0, 2.6, 0), 1.3, 38.0, "fire", 4.0, _pillar_line.bind(global_position, d))
		"summon":
			_play("summon", 1.6)
		"teleport":
			_play("teleport", 0.9)
			_fx_burst(center(), false, 1.4)
			Audio.play("portal", center(), 2.0, 1.3)
		"rings":
			_play("nova", 3.4)
			Audio.play("roar_big", center(), 4.0, 0.6)
			# Three bands with safe gaps (6-8 m and 13-15 m) and a delayed inner circle.
			_tele("ring:spirit", global_position, _fwd(), Vector3(2.0, 6.0, 0), 1.5, 34.0, "fire", 5.0, _ring_fx.bind(4.0))
			_tele("ring:spirit", global_position, _fwd(), Vector3(8.0, 13.0, 0), 2.1, 34.0, "fire", 5.0, _ring_fx.bind(10.5))
			_tele("ring:spirit", global_position, _fwd(), Vector3(15.0, 22.0, 0), 2.7, 34.0, "fire", 5.0, _ring_fx.bind(18.5))
			_tele("circle:spirit", global_position, _fwd(), Vector3(2.0, 0, 0), 3.2, 34.0, "fire", 8.0)


func _aim() -> Vector3:
	if _target == null:
		return _fwd()
	var d := _target.global_position - global_position
	d.y = 0.0
	return d.normalized() if d.length() > 0.1 else _fwd()


func _turn_to(dir: Vector3) -> void:
	yaw = atan2(-dir.x, -dir.z)


func _sweep() -> void:
	_turn_to(_aim())
	_play("sweep", 0.85 / HadesModel.IMPACT["sweep"])
	_tele("cone", global_position, _fwd(), Vector3(7.5, 80.0, 0), 0.85, 42.0, "hit", 8.0,
		func() -> void: Audio.play("swing", center(), 4.0, 0.6))


func _update_attack(name: String, t: float, delta: float) -> bool:
	match name:
		"phase":
			return t > 2.2
		"sweep":
			return t > 1.3
		"thrust":
			if t > 0.35 and t < 0.75:
				var dir: Vector3 = _attack_data["dir"]
				body.velocity.x = dir.x * 6.0
				body.velocity.z = dir.z * 6.0
			elif t >= 0.75:
				body.velocity.x = 0.0
				body.velocity.z = 0.0
			return t > 1.4
		"chains":
			return t > 1.8
		"combo":
			var T: float = HadesModel.COMBO_TIME
			if t > HadesModel.COMBO[1] * T - 0.6 and not _attack_data.has("b2"):
				_attack_data["b2"] = true
				_tele("cone", global_position, _fwd(), Vector3(7.5, 75.0, 0), 0.6, 30.0, "hit", 5.0)
			if t > HadesModel.COMBO[2] * T - 0.7 and not _attack_data.has("b3"):
				_attack_data["b3"] = true
				_tele("line:spirit", global_position, _fwd(), Vector3(10.0, 2.0, 0), 0.7, 36.0, "hit", 7.0)
			if _target != null and not _attack_data.has("b3"):
				_face(_target.global_position, delta, 3.0)
			return t > T
			var shots: int = _attack_data["shots"]
			var count := 5 if phase < 3 else 8
			if shots < count and t > 0.5 + shots * 0.22:
				_attack_data["shots"] = shots + 1
				_soul_bolt(shots)
			return t > 0.6 + count * 0.22 + 0.4
		"pillars":
			return t > 2.1
		"summon":
			if t > 0.9 and not _attack_data.has("done"):
				_attack_data["done"] = true
				_summon("shade", 2 if phase < 3 else 3, 5.0)
			return t > 1.6
		"teleport":
			if t > 0.45 and not _attack_data.has("moved") and _target != null:
				_attack_data["moved"] = true
				var behind := _target.global_position - _target_forward() * 4.0
				global_position = Vector3(behind.x, maxf(behind.y, _target.global_position.y), behind.z)
				_face(_target.global_position, 1.0, 60.0)
				_fx_burst(center(), false, 1.4)
			if t > 0.8 and not _attack_data.has("swung"):
				_attack_data["swung"] = true
				_sweep()
			return t > 2.1
		"rings":
			if t > 3.4:
				# Then he glides off to another part of his hall.
				var a := _rng.randf() * TAU
				_reposition_to(spawn_point + Vector3(cos(a), 0, sin(a)) * arena_radius * 0.4)
				return true
			return false
	return true


func _target_forward() -> Vector3:
	if _target == null:
		return _fwd()
	return Vector3(-sin(_target.yaw), 0, -cos(_target.yaw))


func _soul_bolt(i: int) -> void:
	var w = _w()
	var p := _random_player()
	if w == null or p == null:
		return
	var a := TAU * float(i) / 6.0
	var origin := global_position + Vector3(cos(a) * 1.8, hit_height + 0.6, sin(a) * 1.8)
	var dir := (p.center() - origin).normalized()
	w.spawn_projectile("soul_bolt", origin, dir * 12.0, net_id, Team.MONSTERS, dimension, _dmg(18.0))


func _pillar_line(from: Vector3, dir: Vector3) -> void:
	for i in 8:
		_fx_burst(from + dir * (2.0 + i * 2.6) + Vector3(0, 0.5, 0), true, 0.9)
	_shake_near(from, 0.4)
	Audio.play("explosion", from + dir * 10.0, 2.0, 0.8)


func _ring_fx(radius: float) -> void:
	for i in 16:
		var a := TAU * i / 16.0
		_fx_burst(global_position + Vector3(cos(a), 0.4, sin(a)) * radius, true, 0.7)
	_shake_near(global_position, 0.3)


func _on_phase_changed(new_phase: int) -> void:
	_play("phase", 2.2)
	if _attack == "":
		_attack = "phase"
		_attack_t = 0.0
		_attack_data = {}
	Audio.play("roar_big", center(), 5.0, 0.55)
	_shake_near(global_position, 0.6)
	if new_phase >= 2:
		_summon("shade", 2, 6.0)
	_next_attack = 1.4
