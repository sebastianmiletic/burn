class_name BroodmotherBoss
extends Boss
## Vexhira, the Broodmother: a giant spider queen in the Weeping Hollow, a
## cavern deep beneath Emberwood.
##   Phase 1: bite (cone), leg stab (two marked circles), web lash (a lane of
##            silk that knocks you down), venom volley (lobbed globs)
##   Phase 2: + brood (egg sacs burst into spiderlings), + pounce (leaps onto
##            a marked spot)
##   Phase 3: climbs to the ceiling on a silk line, rains venom on marked
##            spots, then drops onto one of them; plus everything above.
## `flying` (replicated) = hanging from the ceiling.

var _hang_y := 0.0


func _init() -> void:
	kind = "broodmother"
	display_name = "Vexhira, the Broodmother"
	relic = "brood_heart"
	xp_value = 1400
	base_health = 3800.0
	walk_speed = 4.6
	melee_range = 5.5
	aggro_radius = 22.0
	arena_radius = 30.0
	enrage_time = 480.0
	hit_radius = 2.8
	hit_height = 3.6
	body.half_extents = Vector3(1.6, 1.4, 1.6)
	loot = [["potion_greater", 1.0, 2, 4], ["silver_ore", 1.0, 6, 10], ["amethyst", 1.0, 3, 6], ["spider_silk", 1.0, 6, 12],
		["gold_ore", 1.0, 6, 10], ["ruby", 0.7, 1, 3], ["ember_crystal", 1.0, 3, 6]]


func _ready() -> void:
	super._ready()
	if not ItemDB.exists(relic):
		relic = ""


func _attacks() -> Dictionary:
	return {
		"bite": {"phase": 1, "weight": 3.0, "max": 8.0, "cooldown": 0.9},
		"stab": {"phase": 1, "weight": 2.0, "max": 7.0, "cooldown": 1.0},
		"web": {"phase": 1, "weight": 2.0, "min": 3.0, "cooldown": 1.3},
		"venom": {"phase": 1, "weight": 1.6, "min": 4.0, "cooldown": 1.4},
		"brood": {"phase": 2, "weight": 1.0, "cooldown": 1.6, "ok": func() -> bool: return summons.size() < 5},
		"pounce": {"phase": 2, "weight": 1.6, "min": 6.0, "cooldown": 1.2},
		"ceiling": {"phase": 3, "weight": 1.6, "cooldown": 1.5},
	}


func _begin_attack(name: String) -> void:
	if _target != null:
		_face(_target.global_position, 1.0, 60.0)
	match name:
		"bite":
			_play("bite", 0.9)
			_tele("cone", global_position + _fwd() * 1.5, _fwd(), Vector3(7.0, 32.0, 0), 0.6, 34.0, "hit", 5.0,
				func() -> void: Audio.play("growl", center(), 3.0, 1.4))
		"stab":
			_play("slam", 1.1)
			var right := _fwd().cross(Vector3.UP)
			for side: float in [-1.0, 1.0]:
				var c := global_position + _fwd() * 4.2 + right * side * 2.2
				_tele("circle:slam", c, _fwd(), Vector3(2.4, 0, 0), 0.75 + (0.18 if side > 0 else 0.0), 30.0, "hit", 6.0)
		"web":
			_play("shoot", 0.9)
			var dir := _fwd()
			if _target != null:
				dir = (_target.global_position - global_position)
				dir.y = 0.0
				dir = dir.normalized()
			_tele("line:web", global_position + dir * 1.5, dir, Vector3(20.0, 3.4, 0), 0.9, 26.0, "hit", 9.0,
				func() -> void: Audio.play("swing", center(), 4.0, 0.5))
		"venom":
			_play("shoot", 1.4)
			_attack_data["shots"] = 0
		"brood":
			_play("summon", 1.6)
			Audio.play("growl", center(), 4.0, 0.8)
		"pounce":
			var target := (_target.global_position if _target != null else global_position + _fwd() * 8.0)
			_attack_data["mark"] = target
			_attack_data["from"] = global_position
			_play("lunge", 0.7)
			_tele("circle:slam", target, _fwd(), Vector3(5.0, 0, 0), 1.25, 44.0, "hit", 10.0,
				func() -> void:
					_shake_near(target, 0.7)
					Audio.play("stomp", target, 4.0, 0.7))
		"ceiling":
			_play("roar", 1.0)
			Audio.play("growl", center(), 6.0, 0.6)
			_attack_data["rained"] = 0


func _update_attack(name: String, t: float, delta: float) -> bool:
	match name:
		"bite", "web":
			return t > 1.0
		"stab":
			return t > 1.3
		"venom":
			var shots: int = _attack_data["shots"]
			var total := 3 + phase
			if shots < total and t > 0.35 + shots * 0.22:
				_attack_data["shots"] = shots + 1
				_venom_glob()
			return t > 0.6 + total * 0.22
		"brood":
			if t > 0.9 and not _attack_data.has("done"):
				_attack_data["done"] = true
				_summon("spiderling", 3 if phase < 3 else 4, 3.5)
			return t > 1.8
		"pounce":
			# Crouch, leap in an arc, land as the marker fills.
			if t > 0.45 and t < 1.25:
				var f := (t - 0.45) / 0.8
				var a: Vector3 = _attack_data["from"]
				var b: Vector3 = _attack_data["mark"]
				var pos := a.lerp(b, f)
				pos.y = lerpf(a.y, b.y, f) + sin(PI * f) * 5.0
				global_position = pos
				body.velocity = Vector3.ZERO
			return t > 1.8
		"ceiling":
			return _update_ceiling(t, delta)
	return true


func _physics(delta: float) -> void:
	if _attack == "pounce" and _attack_t > 0.45 and _attack_t < 1.25:
		rotation.y = yaw
		_sync()
		return
	if flying:
		global_position += body.velocity * delta
		rotation.y = yaw
		_sync()
		return
	super._physics(delta)
	_sync()


func _sync() -> void:
	var am := model as ArachnidModel
	if am != null:
		am.set("hanging", flying)


func _venom_glob() -> void:
	var w = _w()
	var p := _random_player()
	if w == null or p == null:
		return
	var target := p.global_position + Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5))
	var origin := global_position + Vector3(0, 3.0, 0) + _fwd() * 2.0
	var flight := 0.9
	var vel := (target - origin) / flight + Vector3(0, 0.5 * 9.0 * flight, 0)
	w.telegraph("circle:venom", target, _fwd(), Vector3(2.6, 0, 0), flight, dimension)
	w.spawn_projectile("bile", origin, vel, net_id, Team.MONSTERS, dimension, _dmg(22.0))


## Up the silk line, rain venom, then drop onto a marked spot.
func _update_ceiling(t: float, delta: float) -> bool:
	if t < 1.6:
		if not flying:
			flying = true
			body.fly = true
			_hang_y = global_position.y
		body.velocity = Vector3(0, 9.0 if t > 0.4 else 0.0, 0)
	elif t < 4.2:
		body.velocity = body.velocity.lerp(Vector3.ZERO, 1.0 - exp(-4.0 * delta))
		var rained: int = _attack_data["rained"]
		if rained < 7 and t > 1.8 + rained * 0.32:
			_attack_data["rained"] = rained + 1
			var p := _random_player()
			if p != null:
				var c := p.global_position + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3))
				_tele("circle:venom", c, _fwd(), Vector3(2.8, 0, 0), 1.1, 24.0)
	elif t < 5.4:
		if not _attack_data.has("mark"):
			var target := _target.global_position if _target != null else spawn_point
			_attack_data["mark"] = target
			_tele("circle:slam", target, _fwd(), Vector3(6.0, 0, 0), 1.2, 52.0, "hit", 12.0,
				func() -> void:
					_shake_near(target, 1.0)
					Audio.play("stomp", target, 6.0, 0.5))
		var mark: Vector3 = _attack_data["mark"]
		var hover := Vector3(mark.x, global_position.y, mark.z)
		body.velocity = (hover - global_position) * 3.0
		if t > 4.95:
			# Drop: arrive exactly as the marker fills.
			var remaining := maxf(0.05, 5.4 - t)
			body.velocity = (mark - global_position) / remaining
	elif t < 6.4:
		if flying:
			flying = false
			body.fly = false
			body.velocity = Vector3.ZERO
			_play("hit", 0.5)
	else:
		return true
	return false


func _on_phase_changed(new_phase: int) -> void:
	_play("roar", 1.4)
	Audio.play("growl", center(), 6.0, 0.5)
	_shake_near(global_position, 0.5)
	_next_attack = 1.0
	if new_phase == 2 and _attack == "":
		_attack = "brood"
		_attack_t = 0.0
		_attack_data = {}
		_begin_attack("brood")


func _reset() -> void:
	flying = false
	body.fly = false
	super._reset()
