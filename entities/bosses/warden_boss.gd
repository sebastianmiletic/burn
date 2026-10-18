class_name WardenBoss
extends Boss
## The Warden of the Silent Crypt: a giant skeleton knight with a greatsword.
## It fences like the knight it was: it circles its prey between blows and
## closes distance with lunges, leaps and charges.
##   Phase 1: sweep (cone), overhead slam (line), lunging thrust (narrow line)
##   Phase 2: + three-blow combo (cone, cone, line; each re-aimed and marked),
##            + leaping strike (circle where it lands), + summon skeletons,
##            + bone spikes ring
##   Phase 3: + whirlwind (two marked circles around it), + charge (line dash),
##            spikes become a double ring
## Every blow lands as its telegraph fills; the model's timings come from
## WardenModel.IMPACT / COMBO / SPIN / CHARGE.


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
	strafe_speed = 1.3
	body.half_extents = Vector3(0.8, 2.1, 0.8)
	loot = [["potion_greater", 1.0, 2, 3], ["gold_ore", 1.0, 4, 8], ["iron_ore", 1.0, 4, 6], ["sword_iron", 0.5, 1, 1]]


func _attacks() -> Dictionary:
	return {
		"sweep": {"phase": 1, "weight": 3.0, "max": 6.0, "cooldown": 1.2},
		"slam": {"phase": 1, "weight": 2.0, "max": 10.0, "cooldown": 1.5},
		"thrust": {"phase": 1, "weight": 1.8, "min": 3.0, "max": 11.0, "cooldown": 1.2},
		"combo": {"phase": 2, "weight": 1.6, "max": 7.0, "cooldown": 1.8},
		"leap": {"phase": 2, "weight": 1.3, "min": 7.0, "max": 18.0, "cooldown": 1.6},
		"summon": {"phase": 2, "weight": 1.0, "cooldown": 2.0, "ok": func() -> bool: return summons.size() < 3},
		"spikes": {"phase": 2, "weight": 1.5, "max": 12.0, "cooldown": 1.8},
		"spin": {"phase": 3, "weight": 1.4, "max": 8.0, "cooldown": 1.6},
		"charge": {"phase": 3, "weight": 1.6, "min": 6.0, "max": 20.0, "cooldown": 1.6},
	}


func _aim() -> Vector3:
	if _target == null:
		return _fwd()
	var d := _target.global_position - global_position
	d.y = 0.0
	return d.normalized() if d.length() > 0.1 else _fwd()


func _turn_to(dir: Vector3) -> void:
	yaw = atan2(-dir.x, -dir.z)


func _begin_attack(name: String) -> void:
	var I: Dictionary = WardenModel.IMPACT
	match name:
		"sweep":
			_turn_to(_aim())
			_play("sweep", 0.85 / I["sweep"])
			_tele("cone", global_position, _fwd(), Vector3(6.0, 75.0, 0), 0.85, 28.0, "hit", 7.0,
				func() -> void: Audio.play("swing", center(), 2.0, 0.7))
		"slam":
			_turn_to(_aim())
			_play("slam", 1.0 / I["slam"])
			_tele("line", global_position, _fwd(), Vector3(10.0, 2.6, 0), 1.0, 40.0, "hit", 4.0, _slam_land)
		"thrust":
			_turn_to(_aim())
			_play("thrust", 0.75 / I["thrust"])
			_attack_data["dir"] = _fwd()
			_tele("line", global_position, _fwd(), Vector3(11.0, 1.8, 0), 0.75, 34.0, "hit", 6.0,
				func() -> void: Audio.play("swing", center(), 2.0, 0.85))
		"combo":
			_turn_to(_aim())
			_play("combo", WardenModel.COMBO_TIME)
			var t0: float = WardenModel.COMBO[0] * WardenModel.COMBO_TIME
			_tele("cone", global_position, _fwd(), Vector3(6.0, 70.0, 0), t0, 22.0, "hit", 4.0)
		"leap":
			var dest := _clamp_arena(_target.global_position - _aim() * 1.5 if _target != null else global_position + _fwd() * 8.0, 0.9)
			dest.y = global_position.y
			_attack_data["from"] = global_position
			_attack_data["dest"] = dest
			_turn_to(_aim())
			var land: float = I["leap"] * 2.2
			_play("leap", 2.2)
			_tele("circle:soul", dest, _fwd(), Vector3(4.5, 0, 0), land, 44.0, "hit", 8.0,
				func() -> void:
					_fx_burst(dest + Vector3(0, 0.3, 0), false, 1.8)
					_shake_near(dest, 0.7)
					Audio.play("stomp", dest, 3.0, 0.8))
		"summon":
			_play("summon", 1.6)
			Audio.play("bone_rattle", center(), 2.0, 0.7)
		"spikes":
			_play("spikes", 1.4 / I["spikes"])
			var land := func() -> void:
				_shake_near(global_position, 0.35)
				for i in 10:
					var a := TAU * i / 10.0
					_fx_burst(global_position + Vector3(cos(a), 0.2, sin(a)) * 6.0, false, 0.6)
			_tele("ring:soul", global_position, _fwd(), Vector3(3.0, 9.0, 0), 1.4, 30.0, "hit", 3.0, land)
			if phase >= 3:
				_tele("circle:soul", global_position, _fwd(), Vector3(3.0, 0, 0), 2.2, 30.0, "hit", 6.0)
		"spin":
			_play("spin", WardenModel.SPIN_TIME)
			var a: float = WardenModel.SPIN[0] * WardenModel.SPIN_TIME
			var b: float = WardenModel.SPIN[1] * WardenModel.SPIN_TIME
			_tele("circle", global_position, _fwd(), Vector3(5.5, 0, 0), a, 26.0, "hit", 6.0,
				func() -> void: Audio.play("swing", center(), 3.0, 0.6))
			_tele("circle", global_position, _fwd(), Vector3(5.5, 0, 0), b, 26.0, "hit", 9.0,
				func() -> void: Audio.play("swing", center(), 3.0, 0.75))
		"charge":
			var dir := _aim()
			_attack_data["dir"] = dir
			_turn_to(dir)
			_play("charge", WardenModel.CHARGE_TIME)
			_tele("line", global_position, dir, Vector3(15.0, 3.0, 0), 0.9, 36.0, "hit", 8.0)


func _update_attack(name: String, t: float, delta: float) -> bool:
	match name:
		"phase":
			return t > 2.2
		"sweep":
			return t > 1.3
		"slam":
			return t > 1.5
		"thrust":
			# The lunge carries it forward as the point goes in.
			if t > 0.45 and t < 0.8:
				var dir: Vector3 = _attack_data["dir"]
				body.velocity.x = dir.x * 7.0
				body.velocity.z = dir.z * 7.0
			elif t >= 0.8:
				body.velocity.x = 0.0
				body.velocity.z = 0.0
			return t > 1.35
		"combo":
			return _combo(t, delta)
		"leap":
			var land: float = WardenModel.IMPACT["leap"] * 2.2
			var up := 0.3 * 2.2
			if t > up and t < land:
				var from: Vector3 = _attack_data["from"]
				var dest: Vector3 = _attack_data["dest"]
				var v := (dest - from) / (land - up)
				body.velocity.x = v.x
				body.velocity.z = v.z
			elif t >= land:
				body.velocity.x = 0.0
				body.velocity.z = 0.0
			return t > 2.2
		"summon":
			if t > 0.9 and not _attack_data.has("done"):
				_attack_data["done"] = true
				_summon("skeleton", 2 if phase < 3 else 3, 4.5)
			return t > 1.6
		"spikes":
			return t > (2.4 if phase >= 3 else 2.5)
		"spin":
			# It drifts towards its target while spinning.
			if _target != null and t > 0.5 and t < 1.8:
				var d := _aim()
				body.velocity.x = d.x * 1.2
				body.velocity.z = d.z * 1.2
			if t > 2.1:
				_reposition_to(global_position - _aim() * 5.0)
				return true
			return false
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


## Three blows, each re-aimed at the target and marked before it lands:
## a flat cut, the backhand return, then an overhead chop down a line.
func _combo(t: float, delta: float) -> bool:
	var T: float = WardenModel.COMBO_TIME
	var c: Array = WardenModel.COMBO
	var i1: float = c[1] * T
	var i2: float = c[2] * T
	if t > i1 - 0.6 and not _attack_data.has("b2"):
		_attack_data["b2"] = true
		_tele("cone", global_position, _fwd(), Vector3(6.0, 70.0, 0), 0.6, 22.0, "hit", 4.0)
	if t > i2 - 0.7 and not _attack_data.has("b3"):
		_attack_data["b3"] = true
		_tele("line", global_position, _fwd(), Vector3(10.0, 2.6, 0), 0.7, 34.0, "hit", 5.0, _slam_land)
	# Between blows it steps after its target and keeps facing it.
	if _target != null and not _attack_data.has("b3"):
		_face(_target.global_position, delta, 3.0)
		var d := _aim()
		body.velocity.x = d.x * 1.5
		body.velocity.z = d.z * 1.5
	else:
		body.velocity.x = 0.0
		body.velocity.z = 0.0
	return t > T


func _slam_land() -> void:
	_fx_burst(global_position + _fwd() * 4.0, false, 1.4)
	_shake_near(global_position, 0.5)
	Audio.play("stomp", global_position)


func _on_phase_changed(new_phase: int) -> void:
	_play("phase", 2.2)
	if _attack == "":
		# It stops to plant its blade and roar.
		_attack = "phase"
		_attack_t = 0.0
		_attack_data = {}
	Audio.play("roar_big", center(), 2.0, 0.9)
	if new_phase == 2:
		_summon("skeleton", 2, 5.0)
	_next_attack = 2.0
