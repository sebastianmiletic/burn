class_name CerberusBoss
extends Boss
## Cerberus, Hound of Tartarus.
##   Phase 1: triple snap (the heads strike in turn across a wide cone),
##            lunge (a marked lane straight ahead), pounce (leaps onto a
##            marked circle at a player).
##   Phase 2: + breath (the outer heads pour hellfire that sweeps inwards
##            across a marked cone while the middle head chokes it with ash),
##            + howl (calls hellhounds, its pups), + rearing ground slam
##            (circle under its forepaws, then a shockwave ring).
##   Phase 3: enraged - the cracks in its hide blaze, pounces chain twice,
##            howls throw out a ring of fire, faster tempo.
## Every blow is telegraphed and lands as its warning fills (timings from
## CerberusModel.IMPACT). Arena bounds come from the home location.

const BREATH_TIME := 3.2

var arena_center := Vector3.ZERO
var arena_r := 26.0
var floor_y := 0.0


func _init() -> void:
	kind = "cerberus"
	display_name = "Cerberus, Hound of Tartarus"
	relic = "cerberus_fang"
	xp_value = 1500
	base_health = 3600.0
	walk_speed = 5.0
	melee_range = 7.5
	aggro_radius = 28.0
	arena_radius = 32.0
	enrage_time = 480.0
	hit_radius = 3.4
	hit_height = 5.8
	body.half_extents = Vector3(2.2, 2.0, 2.2)
	loot = [["potion_greater", 1.0, 3, 5], ["hellstone", 1.0, 6, 10], ["obsidian", 1.0, 4, 8]]


func _ready() -> void:
	super._ready()
	_read_arena()


func on_spawned(data: Dictionary) -> void:
	if data.has("home"):
		home_location = String(data["home"])
	_read_arena()


func _read_arena() -> void:
	arena_center = spawn_point if spawn_point != Vector3.ZERO else global_position
	arena_r = arena_radius * 0.8
	var w = _w()
	if w != null and home_location != "" and w.has_method("location_by_id"):
		var loc: Location = w.location_by_id(StringName(home_location))
		if loc != null:
			for s in loc.spawns_of("boss"):
				arena_center = s["pos"]
				if s.has("arena_radius"):
					arena_r = float(s["arena_radius"])
			arena_r = minf(arena_r, maxf(14.0, loc.radius - 6.0))
	floor_y = arena_center.y
	var cm := model as CerberusModel
	if cm != null:
		cm.ground_y = floor_y


func _attacks() -> Dictionary:
	return {
		"bite": {"phase": 1, "weight": 3.0, "max": 10.0, "cooldown": 0.9},
		"lunge": {"phase": 1, "weight": 1.8, "min": 4.0, "max": 13.0, "cooldown": 1.0},
		"pounce": {"phase": 1, "weight": 2.0, "min": 8.0, "max": 28.0, "cooldown": 1.2},
		"breath": {"phase": 2, "weight": 2.0, "max": 15.0, "cooldown": 1.6},
		"slam": {"phase": 2, "weight": 1.5, "max": 9.0, "cooldown": 1.4},
		"howl": {"phase": 2, "weight": 1.0, "cooldown": 2.2, "ok": func() -> bool: return summons.size() < 3 or phase >= 3},
	}


func _ground_at(p: Vector3) -> Vector3:
	return Vector3(p.x, floor_y, p.z)


func _dur(action: String, tele: float) -> float:
	return tele / float(CerberusModel.IMPACT.get(action, 0.5))


func _inside(p: Vector3, margin := 4.0) -> Vector3:
	var off := Vector3(p.x - arena_center.x, 0, p.z - arena_center.z)
	if off.length() > arena_r - margin:
		off = off.normalized() * (arena_r - margin)
	return Vector3(arena_center.x + off.x, p.y, arena_center.z + off.z)


func _begin_attack(name: String) -> void:
	if _target != null and name != "howl":
		_face(_target.global_position, 1.0, 60.0)
	var g := _ground_at(global_position)
	match name:
		"bite":
			var tele := 0.62
			_play("bite", _dur("bite", tele))
			Audio.play("wolf_growl", center(), 6.0, 0.5)
			_tele("cone", g + _fwd() * 2.0, _fwd(), Vector3(10.0, 42.0, 0), tele, 36.0, "hit", 6.0,
				func() -> void:
					Audio.play("hit_heavy", g + _fwd() * 7.0, 4.0, 0.6)
					_shake_near(global_position, 0.3))
		"lunge":
			var tele := 0.5
			_play("lunge", _dur("lunge", tele))
			_attack_data["from"] = global_position
			_tele("line", g + _fwd() * 1.0, _fwd(), Vector3(12.0, 6.0, 0), tele, 32.0, "hit", 9.0,
				func() -> void: Audio.play("wolf_growl", center(), 6.0, 0.6))
		"pounce":
			_start_pounce()
		"breath":
			_attack_data["origin"] = g + _fwd() * 3.0
			_attack_data["dir"] = _fwd()
			_play("breath", BREATH_TIME)
			Audio.play("wolf_growl", center(), 6.0, 0.45)
			var w = _w()
			if w != null:
				w.telegraph("cone", _attack_data["origin"], _fwd(), Vector3(15.0, 44.0, 0), BREATH_TIME * CerberusModel.BREATH_ON, dimension)
		"slam":
			var tele := 0.9
			var c := g + _fwd() * 3.8
			_play("slam", _dur("slam", tele))
			Audio.play("roar", center(), 4.0, 0.6)
			_tele("circle", c, _fwd(), Vector3(5.5, 0, 0), tele, 40.0, "hit", 10.0,
				func() -> void: _shake_near(c, 0.8))
			_tele("ring", c, _fwd(), Vector3(5.5, 11.0, 0), tele + 0.35, 22.0, "fire", 8.0,
				func() -> void:
					for i in 10:
						var a := TAU * i / 10.0
						_fx_burst(c + Vector3(cos(a), 0.3, sin(a)) * 8.5, true, 0.7))
		"howl":
			_play("howl", 2.0)
			Audio.play("wolf_howl", center(), 8.0, 0.55)
			Audio.play("roar_big", center(), 4.0, 1.2)
			if phase >= 3:
				_tele("ring", g, _fwd(), Vector3(3.0, 13.0, 0), 1.4, 26.0, "fire", 9.0,
					func() -> void:
						_shake_near(global_position, 0.6)
						for i in 12:
							var a := TAU * i / 12.0
							_fx_burst(g + Vector3(cos(a), 0.3, sin(a)) * 8.0, true, 0.7))


func _start_pounce() -> void:
	var target := _target.global_position if _target != null else global_position + _fwd() * 12.0
	target = _inside(_ground_at(target), 5.0)
	var approach := target - global_position
	approach.y = 0.0
	_attack_data["from"] = global_position
	# Land just short of the target: the forepaws (and the impact circle) cover it.
	_attack_data["to"] = target - approach.normalized() * minf(3.5, approach.length() * 0.5)
	_attack_data["real"] = 0.0
	_face(target, 1.0, 60.0)
	var dur := 1.4
	_attack_data["dur"] = dur
	_play("pounce", dur)
	Audio.play("wolf_growl", center(), 6.0, 0.6)
	_tele("circle", target, _fwd(), Vector3(5.0, 0, 0), dur * CerberusModel.IMPACT["pounce"], 42.0, "hit", 11.0,
		func() -> void:
			_fx_burst(target + Vector3(0, 0.3, 0), true, 1.4)
			_shake_near(target, 0.7)
			Audio.play("stomp", target, 6.0, 0.6))


func _update_attack(name: String, t: float, delta: float) -> bool:
	match name:
		"bite":
			return t > _dur("bite", 0.62)
		"lunge":
			# The body surges forward with the strike.
			var dur := _dur("lunge", 0.5)
			var f := clampf((t / dur - 0.25) / 0.25, 0.0, 1.0)
			if f > 0.0 and f < 1.0:
				var from: Vector3 = _attack_data["from"]
				var to := _inside(from + _fwd() * 4.0, 3.0)
				var pos := from.lerp(to, f * f * (3.0 - 2.0 * f))
				body.velocity.x = (pos.x - global_position.x) / maxf(delta, 0.001)
				body.velocity.z = (pos.z - global_position.z) / maxf(delta, 0.001)
			else:
				body.velocity.x = 0.0
				body.velocity.z = 0.0
			return t > dur
		"pounce":
			return _update_pounce(delta)
		"breath":
			_attack_data["real"] = float(_attack_data.get("real", 0.0)) + delta
			var p: float = float(_attack_data["real"]) / BREATH_TIME
			if p > CerberusModel.BREATH_ON and p < CerberusModel.BREATH_OFF:
				_attack_data["tick"] = float(_attack_data.get("tick", 0.0)) - delta
				if float(_attack_data["tick"]) <= 0.0:
					_attack_data["tick"] = 0.25
					var o: Vector3 = _attack_data["origin"]
					var d: Vector3 = _attack_data["dir"]
					for k: int in [0, 2]:
						var dir := d.rotated(Vector3.UP, CerberusModel.breath_yaw(k, p))
						_hit_shape("cone", o, dir, Vector3(14.0, 13.0, 0), _dmg(8.0), "fire", 0.0)
					_hit_shape("cone", o, d, Vector3(11.0, 15.0, 0), _dmg(4.0), "hit", 0.0)
			return p > 1.02
		"slam":
			return t > _dur("slam", 0.9) + 0.1
		"howl":
			if t > 0.9 and not _attack_data.has("done"):
				_attack_data["done"] = true
				if summons.size() < 3:
					_summon("hellhound", 2, 7.0)
			return t > 2.0
	return true


## Crouch, then a ballistic leap landing exactly when the warning fills.
func _update_pounce(delta: float) -> bool:
	_attack_data["real"] = float(_attack_data["real"]) + delta
	var t: float = _attack_data["real"]
	var dur: float = _attack_data["dur"]
	var leap_start := dur * 0.33
	var land := dur * CerberusModel.IMPACT["pounce"]
	if t >= leap_start and t < land:
		var f := (t - leap_start) / (land - leap_start)
		var from: Vector3 = _attack_data["from"]
		var to: Vector3 = _attack_data["to"]
		var pos := from.lerp(to, f)
		pos.y = lerpf(from.y, floor_y, f) + sin(PI * f) * 5.0
		global_position = pos
		body.velocity = Vector3.ZERO
		body.fly = true
		flying = true
	elif t >= land and flying:
		body.fly = false
		flying = false
		global_position = _attack_data["to"]
		body.velocity = Vector3.ZERO
	if phase >= 3 and t > dur and not _attack_data.has("again") and _target != null:
		_attack_data["again"] = true
		_start_pounce()
		_attack_data["again"] = true
		return false
	return t > dur + 0.15


func _physics(delta: float) -> void:
	if flying:
		rotation.y = yaw
		if model != null:
			model.grounded = false
			model.move_speed = 0.0
			model.turn_rate = 0.0
			model.set_burning(burning > 0.0)
		return
	super._physics(delta)


func _process(delta: float) -> void:
	super._process(delta)
	var cm := model as CerberusModel
	if cm == null:
		return
	cm.rage = 1.0 if phase >= 3 else (0.35 if phase == 2 else 0.0)
	if is_nan(cm.ground_y):
		cm.ground_y = floor_y
	var look := Vector3.INF
	if _target != null and is_instance_valid(_target):
		look = _target.global_position + Vector3(0, 1.6, 0)
	else:
		var w = _w()
		if w != null and w.has_method("nearest_player"):
			var p = w.nearest_player(global_position, dimension, 50.0)
			if p != null:
				look = (p as Node3D).global_position + Vector3(0, 1.6, 0)
	cm.look_target = look


func _on_phase_changed(new_phase: int) -> void:
	_play("howl", 2.0)
	Audio.play("wolf_howl", center(), 8.0, 0.5)
	Audio.play("roar_big", center(), 5.0, 1.1)
	_shake_near(global_position, 0.6)
	_next_attack = 1.4 if new_phase < 3 else 1.0


func _reset() -> void:
	flying = false
	body.fly = false
	super._reset()
