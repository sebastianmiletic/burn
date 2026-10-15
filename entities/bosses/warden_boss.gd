class_name WardenBoss
extends Boss
## The Warden of the Silent Crypt: a giant skeleton knight with a greatsword.
##   Phase 1: sweep (cone), overhead slam (line)
##   Phase 2: + summon skeletons, + bone spikes ring
##   Phase 3: + charge (line dash), spikes become a double ring


func _init() -> void:
	kind = "warden"
	display_name = "The Warden of the Silent Crypt"
	relic = "warden_sigil"
	xp_value = 400
	base_health = 1300.0
	walk_speed = 2.8
	melee_range = 4.2
	aggro_radius = 16.0
	arena_radius = 22.0
	enrage_time = 420.0
	hit_radius = 1.1
	hit_height = 4.4
	body.half_extents = Vector3(0.8, 2.1, 0.8)
	loot = [["potion_greater", 1.0, 2, 3], ["gold_ore", 1.0, 4, 8], ["iron_ore", 1.0, 4, 6], ["sword_iron", 0.5, 1, 1]]


func _attacks() -> Dictionary:
	return {
		"sweep": {"phase": 1, "weight": 3.0, "max": 6.0, "cooldown": 1.2},
		"slam": {"phase": 1, "weight": 2.0, "max": 10.0, "cooldown": 1.5},
		"summon": {"phase": 2, "weight": 1.0, "cooldown": 2.0, "ok": func() -> bool: return summons.size() < 3},
		"spikes": {"phase": 2, "weight": 1.5, "max": 12.0, "cooldown": 1.8},
		"charge": {"phase": 3, "weight": 1.6, "min": 6.0, "max": 20.0, "cooldown": 1.6},
	}


func _begin_attack(name: String) -> void:
	match name:
		"sweep":
			_play("sweep", 1.3)
			_tele("cone", global_position, _fwd(), Vector3(6.0, 75.0, 0), 0.85, 28.0, "hit", 7.0)
		"slam":
			_play("slam", 1.4)
			_attack_data["dir"] = _fwd()
			_tele("line", global_position, _fwd(), Vector3(10.0, 2.6, 0), 1.0, 40.0, "hit", 4.0,
				func() -> void:
					_fx_burst(global_position + _fwd() * 4.0, false, 1.4)
					_shake_near(global_position, 0.5)
					Audio.play("stomp", global_position))
		"summon":
			_play("summon", 1.4)
			Audio.play("bone_rattle", center(), 2.0, 0.7)
		"spikes":
			_play("spikes", 1.5)
			var land := func() -> void:
				_shake_near(global_position, 0.35)
				for i in 10:
					var a := TAU * i / 10.0
					_fx_burst(global_position + Vector3(cos(a), 0.2, sin(a)) * 6.0, false, 0.6)
			_tele("ring:soul", global_position, _fwd(), Vector3(3.0, 9.0, 0), 1.4, 30.0, "hit", 3.0, land)
			if phase >= 3:
				_tele("circle:soul", global_position, _fwd(), Vector3(3.0, 0, 0), 2.2, 30.0, "hit", 6.0)
		"charge":
			var dir := _fwd()
			if _target != null:
				dir = (_target.global_position - global_position)
				dir.y = 0.0
				dir = dir.normalized()
			_attack_data["dir"] = dir
			_play("attack2", 1.2)
			_tele("line", global_position, dir, Vector3(15.0, 3.0, 0), 0.9, 36.0, "hit", 8.0)


func _update_attack(name: String, t: float, delta: float) -> bool:
	match name:
		"sweep":
			return t > 1.3
		"slam":
			return t > 1.5
		"summon":
			if t > 0.9 and not _attack_data.has("done"):
				_attack_data["done"] = true
				_summon("skeleton", 2 if phase < 3 else 3, 4.5)
			return t > 1.5
		"spikes":
			return t > (2.4 if phase >= 3 else 1.6)
		"charge":
			if t > 0.9 and t < 1.35:
				var dir: Vector3 = _attack_data["dir"]
				body.velocity.x = dir.x * 30.0
				body.velocity.z = dir.z * 30.0
				yaw = atan2(-dir.x, -dir.z)
			elif t >= 1.35:
				body.velocity.x = 0.0
				body.velocity.z = 0.0
			return t > 1.8
	return true


func _on_phase_changed(new_phase: int) -> void:
	_play("roar", 1.4)
	Audio.play("roar_big", center(), 2.0, 0.9)
	if new_phase == 2:
		_summon("skeleton", 2, 5.0)
	_next_attack = 1.5
