class_name MountainKingBoss
extends Boss
## The Mountain King: a towering troll king in a frost crown. Slow on his
## feet, but he closes ground with crushing leaps and an avalanche charge.
##   Phase 1: ground slam (circle in front), backhand swipe (wide cone, throws
##            you back), boulder throw at a random player, stomp (a circle at
##            his feet, then a shockwave ring rolling outward)
##   Phase 2: + ice spikes (lines towards every player), + war cry (knockback
##            circle), + leap (marked circle where he lands)
##   Phase 3: + avalanche charge (line), + summons trolls, slams come in pairs
## Model timings come from MountainKingModel.IMPACT / LEAP / CHARGE.


func _init() -> void:
	kind = "mountain_king"
	display_name = "The Mountain King"
	relic = "frost_crown"
	xp_value = 700
	base_health = 2400.0
	walk_speed = 2.4
	melee_range = 6.0
	aggro_radius = 26.0
	arena_radius = 34.0
	enrage_time = 480.0
	hit_radius = 1.6
	hit_height = 6.2
	strafe_speed = 0.9
	body.half_extents = Vector3(1.2, 2.9, 1.2)
	loot = [["potion_greater", 1.0, 2, 4], ["frost_shard", 1.0, 6, 10], ["gold_ore", 1.0, 6, 10], ["ember_crystal", 0.6, 2, 4]]


func _attacks() -> Dictionary:
	return {
		"slam": {"phase": 1, "weight": 3.0, "max": 9.0, "cooldown": 1.6},
		"swipe": {"phase": 1, "weight": 2.2, "max": 8.0, "cooldown": 1.3},
		"boulder": {"phase": 1, "weight": 2.0, "min": 6.0, "cooldown": 1.4},
		"stomp": {"phase": 1, "weight": 1.5, "max": 10.0, "cooldown": 1.5},
		"ice_spikes": {"phase": 2, "weight": 2.0, "cooldown": 1.8},
		"roar": {"phase": 2, "weight": 1.0, "max": 8.0, "cooldown": 1.5},
		"leap": {"phase": 2, "weight": 1.4, "min": 9.0, "max": 26.0, "cooldown": 1.6},
		"charge": {"phase": 3, "weight": 1.4, "min": 7.0, "max": 24.0, "cooldown": 1.8},
		"summon": {"phase": 3, "weight": 0.8, "cooldown": 2.0, "ok": func() -> bool: return summons.size() < 2},
	}


func _slam_center() -> Vector3:
	return global_position + _fwd() * 3.5


func _aim() -> Vector3:
	if _target == null:
		return _fwd()
	var d := _target.global_position - global_position
	d.y = 0.0
	return d.normalized() if d.length() > 0.1 else _fwd()


func _turn_to(dir: Vector3) -> void:
	yaw = atan2(-dir.x, -dir.z)


func _begin_attack(name: String) -> void:
	var I: Dictionary = MountainKingModel.IMPACT
	match name:
		"slam":
			_turn_to(_aim())
			_play("slam", 1.25 / I["slam"])
			_tele("circle", _slam_center(), _fwd(), Vector3(6.0, 0, 0), 1.25, 46.0, "hit", 6.0, _slam_land)
			if phase >= 3:
				_attack_data["second"] = true
		"swipe":
			_turn_to(_aim())
			_play("swipe", 0.9 / I["swipe"])
			_tele("cone", global_position, _fwd(), Vector3(8.0, 110.0, 0), 0.9, 34.0, "hit", 12.0,
				func() -> void:
					Audio.play("swing", center(), 4.0, 0.5)
					_shake_near(global_position, 0.3))
		"boulder":
			var target := _random_player()
			if target == null:
				target = _target
			_attack_data["target"] = target.global_position if target != null else global_position + _fwd() * 10.0
			_play("throw", 0.65 / I["throw"])
			_face(_attack_data["target"], 1.0, 50.0)
		"stomp":
			_play("stomp", 1.0 / I["stomp"])
			_tele("circle:frost", global_position, _fwd(), Vector3(4.5, 0, 0), 1.0, 30.0, "hit", 6.0,
				func() -> void:
					_fx_burst(global_position + Vector3(0, 0.3, 0), false, 1.6)
					_shake_near(global_position, 0.7)
					Audio.play("stomp", global_position, 4.0, 0.7))
			_tele("ring:frost", global_position, _fwd(), Vector3(6.0, 11.0, 0), 1.6, 26.0, "hit", 8.0,
				func() -> void:
					for i in 12:
						var a := TAU * i / 12.0
						_fx_burst(global_position + Vector3(cos(a), 0.3, sin(a)) * 8.5, false, 0.6))
		"ice_spikes":
			_play("spikes", 1.3 / I["spikes"])
			var players := _players()
			for p in players:
				var dir := p.global_position - global_position
				dir.y = 0.0
				_tele("line:frost", global_position, dir.normalized(), Vector3(18.0, 2.2, 0), 1.3, 34.0, "hit", 3.0,
					_ice_line.bind(global_position, dir.normalized()))
			if players.size() < 3:
				for k in 3 - players.size():
					var a := _rng.randf() * TAU
					var dir := Vector3(cos(a), 0, sin(a))
					_tele("line:frost", global_position, dir, Vector3(18.0, 2.2, 0), 1.3, 34.0, "hit", 3.0,
						_ice_line.bind(global_position, dir))
		"roar":
			_play("roar", 1.0 / I["roar"])
			_tele("circle", global_position, _fwd(), Vector3(8.0, 0, 0), 1.0, 12.0, "hit", 14.0,
				func() -> void:
					Audio.play("roar_big", center(), 4.0, 0.8)
					_shake_near(global_position, 0.6))
		"leap":
			var T: float = MountainKingModel.LEAP_TIME
			var dest := _clamp_arena(_target.global_position - _aim() * 2.0 if _target != null else global_position + _fwd() * 10.0, 0.9)
			dest.y = global_position.y
			_attack_data["from"] = global_position
			_attack_data["dest"] = dest
			_turn_to(_aim())
			_play("leap", T)
			_tele("circle:frost", dest, _fwd(), Vector3(6.5, 0, 0), MountainKingModel.LEAP[1] * T, 52.0, "hit", 10.0,
				func() -> void:
					_fx_burst(dest + Vector3(0, 0.3, 0), false, 2.4)
					_shake_near(dest, 1.0)
					Audio.play("stomp", dest, 6.0, 0.6))
		"charge":
			var dir := _aim()
			_attack_data["dir"] = dir
			# The run stops short of the arena's edge.
			var run := global_position.distance_to(_clamp_arena(global_position + dir * 20.0, 0.95))
			_attack_data["run"] = run
			_turn_to(dir)
			var T: float = MountainKingModel.CHARGE_TIME
			_play("charge", T)
			_tele("line:frost", global_position, dir, Vector3(run + 3.0, 4.0, 0), MountainKingModel.CHARGE[0] * T, 44.0, "hit", 14.0)
		"summon":
			_play("summon", 1.6)


func _update_attack(name: String, t: float, _delta: float) -> bool:
	match name:
		"phase":
			return t > 2.6
		"slam":
			if _attack_data.get("second", false) and t > 1.55 and not _attack_data.has("second_done"):
				_attack_data["second_done"] = true
				_turn_to(_aim())
				_play("slam", 1.25 / MountainKingModel.IMPACT["slam"])
				_tele("circle", _slam_center(), _fwd(), Vector3(6.0, 0, 0), 1.25, 46.0, "hit", 6.0, _slam_land)
			return t > (3.3 if _attack_data.get("second", false) else 1.8)
		"swipe":
			return t > 1.45
		"boulder":
			if t > 0.65 and not _attack_data.has("thrown"):
				_attack_data["thrown"] = true
				_throw_boulder(_attack_data["target"])
			return t > 1.2
		"stomp":
			return t > 1.7
		"ice_spikes":
			return t > 2.1
		"roar":
			return t > 2.0
		"leap":
			var T: float = MountainKingModel.LEAP_TIME
			var up: float = MountainKingModel.LEAP[0] * T
			var land: float = MountainKingModel.LEAP[1] * T
			if t > up and t < land:
				var v: Vector3 = (_attack_data["dest"] - _attack_data["from"]) / (land - up)
				body.velocity.x = v.x
				body.velocity.z = v.z
			elif t >= land:
				body.velocity.x = 0.0
				body.velocity.z = 0.0
			return t > T
		"charge":
			var T: float = MountainKingModel.CHARGE_TIME
			var go: float = MountainKingModel.CHARGE[0] * T
			var stop: float = MountainKingModel.CHARGE[1] * T
			var dir: Vector3 = _attack_data["dir"]
			if t > go and t < stop:
				var run: float = _attack_data["run"]
				body.velocity.x = dir.x * run / (stop - go)
				body.velocity.z = dir.z * run / (stop - go)
				if not _attack_data.has("rumble"):
					_attack_data["rumble"] = true
					_shake_near(global_position, 0.5)
			elif t >= stop:
				body.velocity.x = 0.0
				body.velocity.z = 0.0
			return t > T
		"summon":
			if t > 0.9 and not _attack_data.has("done"):
				_attack_data["done"] = true
				_summon("troll", 2, 7.0)
			return t > 1.6
	return true


func _slam_land() -> void:
	_fx_burst(_slam_center() + Vector3(0, 0.3, 0), false, 2.0)
	_shake_near(global_position, 0.8)
	Audio.play("stomp", _slam_center(), 4.0, 0.8)


func _ice_line(from: Vector3, dir: Vector3) -> void:
	for i in 6:
		_fx_burst(from + dir * (3.0 + i * 3.0) + Vector3(0, 0.4, 0), false, 0.8)
	Audio.play("block_break", from + dir * 8.0, 2.0, 0.7)


func _throw_boulder(target: Vector3) -> void:
	var w = _w()
	if w == null:
		return
	var origin := global_position + Vector3(0, hit_height * 0.95, 0) + _fwd() * 1.5
	var dist := Vector2(target.x - origin.x, target.z - origin.z).length()
	var flight := clampf(dist / 16.0, 0.9, 2.0)
	var g := float(Projectile.KINDS["boulder"]["gravity"])
	var v := (target - origin) / flight
	v.y = (target.y - origin.y) / flight + 0.5 * g * flight
	w.telegraph("circle", target, _fwd(), Vector3(3.4, 0, 0), flight, dimension)
	w.spawn_projectile("boulder", origin, v, net_id, Team.MONSTERS, dimension, _dmg(40.0))
	Audio.play("swing", center(), 2.0, 0.6)


func _on_phase_changed(new_phase: int) -> void:
	_play("phase", 2.6)
	Audio.play("roar_big", center(), 4.0, 0.75)
	_shake_near(global_position, 0.5)
	if _attack == "":
		_attack = "phase"
		_attack_t = 0.0
		_attack_data = {}
	if new_phase == 3:
		_summon("troll", 1, 6.0)
	_next_attack = 1.6
