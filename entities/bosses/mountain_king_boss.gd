class_name MountainKingBoss
extends Boss
## The Mountain King: a towering troll king in a frost crown.
##   Phase 1: ground slam (circle in front), boulder throw at a random player
##   Phase 2: + ice spikes (lines towards every player), + roar (knockback circle)
##   Phase 3: + summons trolls, slams come in pairs


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
	body.half_extents = Vector3(1.2, 2.9, 1.2)
	loot = [["potion_greater", 1.0, 2, 4], ["frost_shard", 1.0, 6, 10], ["gold_ore", 1.0, 6, 10], ["ember_crystal", 0.6, 2, 4]]


func _attacks() -> Dictionary:
	return {
		"slam": {"phase": 1, "weight": 3.0, "max": 9.0, "cooldown": 1.6},
		"boulder": {"phase": 1, "weight": 2.0, "min": 6.0, "cooldown": 1.4},
		"ice_spikes": {"phase": 2, "weight": 2.0, "cooldown": 1.8},
		"roar": {"phase": 2, "weight": 1.0, "max": 8.0, "cooldown": 1.5},
		"summon": {"phase": 3, "weight": 0.8, "cooldown": 2.0, "ok": func() -> bool: return summons.size() < 2},
	}


func _slam_center() -> Vector3:
	return global_position + _fwd() * 3.5


func _begin_attack(name: String) -> void:
	match name:
		"slam":
			_play("slam", 1.5)
			_tele("circle", _slam_center(), _fwd(), Vector3(6.0, 0, 0), 1.25, 46.0, "hit", 6.0, _slam_land)
			if phase >= 3:
				_attack_data["second"] = true
		"boulder":
			var target := _random_player()
			if target == null:
				target = _target
			_attack_data["target"] = target.global_position if target != null else global_position + _fwd() * 10.0
			_play("throw", 1.2)
			_face(_attack_data["target"], 1.0, 50.0)
		"ice_spikes":
			_play("spikes", 1.4)
			var players := _players()
			for p in players:
				var dir := p.global_position - global_position
				dir.y = 0.0
				_tele("line", global_position, dir.normalized(), Vector3(18.0, 2.2, 0), 1.3, 34.0, "hit", 3.0,
					_ice_line.bind(global_position, dir.normalized()))
			if players.size() < 3:
				for k in 3 - players.size():
					var a := _rng.randf() * TAU
					var dir := Vector3(cos(a), 0, sin(a))
					_tele("line", global_position, dir, Vector3(18.0, 2.2, 0), 1.3, 34.0, "hit", 3.0,
						_ice_line.bind(global_position, dir))
		"roar":
			_play("roar", 1.4)
			_tele("circle", global_position, _fwd(), Vector3(8.0, 0, 0), 1.0, 12.0, "hit", 14.0,
				func() -> void:
					Audio.play("roar_big", center(), 4.0, 0.8)
					_shake_near(global_position, 0.6))
		"summon":
			_play("summon", 1.4)


func _update_attack(name: String, t: float, _delta: float) -> bool:
	match name:
		"slam":
			if _attack_data.get("second", false) and t > 1.35 and not _attack_data.has("second_done"):
				_attack_data["second_done"] = true
				_play("slam", 1.5)
				_tele("circle", _slam_center(), _fwd(), Vector3(6.0, 0, 0), 1.25, 46.0, "hit", 6.0, _slam_land)
			return t > (2.9 if _attack_data.get("second", false) else 1.6)
		"boulder":
			if t > 0.65 and not _attack_data.has("thrown"):
				_attack_data["thrown"] = true
				_throw_boulder(_attack_data["target"])
			return t > 1.2
		"ice_spikes":
			return t > 1.6
		"roar":
			return t > 1.4
		"summon":
			if t > 0.9 and not _attack_data.has("done"):
				_attack_data["done"] = true
				_summon("troll", 2, 7.0)
			return t > 1.5
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
	var w := world()
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
	_play("roar", 1.4)
	Audio.play("roar_big", center(), 4.0, 0.75)
	_shake_near(global_position, 0.5)
	if new_phase == 3:
		_summon("troll", 1, 6.0)
	_next_attack = 1.6
