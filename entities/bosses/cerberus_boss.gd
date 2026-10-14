class_name CerberusBoss
extends Boss
## Cerberus, hound of Tartarus.
##   Phase 1: triple bite (wide cone), pounce (landing circle at a player)
##   Phase 2: + fire breath from the two outer heads (two cones), + howl that summons imps
##   Phase 3: pounces chain twice, howl adds a shockwave ring, faster tempo


func _init() -> void:
	kind = "cerberus"
	display_name = "Cerberus, Hound of Tartarus"
	relic = "cerberus_fang"
	xp_value = 1500
	base_health = 3600.0
	walk_speed = 5.0
	melee_range = 6.0
	aggro_radius = 28.0
	arena_radius = 32.0
	enrage_time = 480.0
	hit_radius = 2.0
	hit_height = 3.4
	body.half_extents = Vector3(1.4, 1.6, 1.4)
	loot = [["potion_greater", 1.0, 3, 5], ["hellstone", 1.0, 6, 10], ["obsidian", 1.0, 4, 8]]


func _attacks() -> Dictionary:
	return {
		"bite": {"phase": 1, "weight": 3.0, "max": 8.0, "cooldown": 0.9},
		"pounce": {"phase": 1, "weight": 2.0, "min": 6.0, "max": 26.0, "cooldown": 1.2},
		"breath": {"phase": 2, "weight": 2.0, "max": 14.0, "cooldown": 1.6},
		"howl": {"phase": 2, "weight": 1.0, "cooldown": 2.2, "ok": func() -> bool: return summons.size() < 3 or phase >= 3},
	}


func _begin_attack(name: String) -> void:
	match name:
		"bite":
			_play("bite", 1.0)
			_tele("cone", global_position + _fwd() * 0.5, _fwd(), Vector3(8.5, 48.0, 0), 0.7, 36.0, "hit", 6.0,
				func() -> void: Audio.play("growl", center(), 4.0, 0.7))
		"pounce":
			_start_pounce()
		"breath":
			if _target != null:
				_face(_target.global_position, 1.0, 60.0)
			_play("howl", 0.8)
			var o := global_position + _fwd() * 3.0
			var right := _fwd().cross(Vector3.UP)
			var dir_l := (_fwd() - right * 0.45).normalized()
			var dir_r := (_fwd() + right * 0.45).normalized()
			_attack_data["cones"] = [[o - right * 0.8, dir_l], [o + right * 0.8, dir_r]]
			var w = _w()
			if w != null:
				w.telegraph("cone", o - right * 0.8, dir_l, Vector3(12.0, 20.0, 0), 0.9, dimension)
				w.telegraph("cone", o + right * 0.8, dir_r, Vector3(12.0, 20.0, 0), 0.9, dimension)
		"howl":
			_play("howl", 1.5)
			Audio.play("roar_big", center(), 4.0, 1.3)
			if phase >= 3:
				_tele("ring", global_position, _fwd(), Vector3(2.5, 11.0, 0), 1.3, 26.0, "fire", 9.0,
					func() -> void:
						_shake_near(global_position, 0.6)
						for i in 12:
							var a := TAU * i / 12.0
							_fx_burst(global_position + Vector3(cos(a), 0.3, sin(a)) * 7.0, true, 0.6))


func _start_pounce() -> void:
	var target := _target.global_position if _target != null else global_position + _fwd() * 10.0
	var approach := target - global_position
	approach.y = 0.0
	_attack_data["from"] = global_position
	# Land just short of the target: the impact circle still covers it.
	_attack_data["to"] = target - approach.normalized() * minf(2.5, approach.length() * 0.5)
	_face(target, 1.0, 60.0)
	_play("pounce", 1.2)
	_tele("circle", target, _fwd(), Vector3(4.6, 0, 0), 1.0, 42.0, "hit", 10.0,
		func() -> void:
			_fx_burst(target + Vector3(0, 0.3, 0), true, 1.3)
			_shake_near(target, 0.7)
			Audio.play("stomp", target, 4.0))


func _update_attack(name: String, t: float, delta: float) -> bool:
	match name:
		"bite":
			return t > 1.0
		"pounce":
			# Crouch, then a ballistic leap landing exactly when the warning fills.
			var leap_start := 0.45
			var land := 1.0
			if t >= leap_start and t < land:
				var f := (t - leap_start) / (land - leap_start)
				var from: Vector3 = _attack_data["from"]
				var to: Vector3 = _attack_data["to"]
				var pos := from.lerp(to, f)
				pos.y += sin(PI * f) * 4.0
				body.velocity = (pos - global_position) / maxf(delta, 0.001)
				body.fly = true
			elif t >= land:
				body.fly = false
				body.velocity = Vector3(0, body.velocity.y if body.velocity.y < 0.0 else 0.0, 0)
			if phase >= 3 and t > 1.5 and not _attack_data.has("again") and _target != null:
				_attack_data["again"] = true
				_attack_t = 0.0
				_start_pounce()
				return false
			return t > 1.6
		"breath":
			if t > 0.9 and not _attack_data.has("flame"):
				_attack_data["flame"] = true
				_play("breath", 2.2)
			if t > 1.1 and t < 2.6:
				_attack_data["tick"] = float(_attack_data.get("tick", 0.0)) - delta
				if float(_attack_data["tick"]) <= 0.0:
					_attack_data["tick"] = 0.3
					for c: Array in _attack_data["cones"]:
						_hit_shape("cone", c[0], c[1], Vector3(12.0, 20.0, 0), _dmg(8.0), "fire", 0.0)
			return t > 2.9
		"howl":
			if t > 0.8 and not _attack_data.has("done"):
				_attack_data["done"] = true
				if summons.size() < 3:
					_summon("imp", 2, 6.0)
			return t > 1.6
	return true


func _on_phase_changed(_new_phase: int) -> void:
	_play("howl", 1.5)
	Audio.play("roar_big", center(), 5.0, 1.2)
	_shake_near(global_position, 0.5)
	_next_attack = 1.2
