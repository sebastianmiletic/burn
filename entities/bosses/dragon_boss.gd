class_name DragonBoss
extends Boss
## Ashvane, the Last Dragon, in the courtyard of the Dragon's Keep.
##
##   Phase 1 (ground): bite (narrow cone at the head), claw rake (circle at a
##            foreleg), tail sweep (wide cone behind, knocks you flying), a
##            sweeping fire breath (wide cone marked first; the stream then
##            sweeps across it and only burns where it currently points) and a
##            charge (a marked lane it thunders down).
##   Phase 2: + wing buffet (cone, huge knockback), + rearing stomp (circle and
##            shockwave), + takes to the air for a sky spell: it circles the
##            arena on the wing and, from the air, makes strafing runs (a lane
##            is marked, then it flies the lane breathing fire on it), hovering
##            fireball volleys (every landing spot marked) and low claw swoops
##            (a marked lane), then lands near its target.
##   Phase 3: longer sky spells, + fire rain while circling (a chain of marked
##            circles), + dive bomb (climbs, marks a spot, crashes onto it: a
##            heavy landing that leaves it staggered - the opening; it ends the
##            sky spell), + shockwave roar (ring with a safe centre).
## In the air it stays inside the arena's air volume (arena circle, floor up to
## air_ceiling); `flying`, position and `anim` replicate, so clients show the
## same flight.
## Every damaging blow is telegraphed and lands as its warning fills; model
## timings come from DragonModel.IMPACT so the animation and the hit agree.
## Arena bounds come from the home location (boss spawn = centre).

const FLY_ALT := 9.0      ## hover height of the feet above the arena floor
const STRAFE_ALT := 7.0
const DIVE_ALT := 15.0
const BREATH_TIME := 3.4
const ORBIT_SPEED := 13.0  ## circling speed on the wing
const CHARGE_TELE := 1.3
const SWOOP_TELE := 2.0

var arena_center := Vector3.ZERO
var arena_r := 34.0
var floor_y := 0.0
var _stagger := 0.0
var _flights := 0
var _queued := ""
## Seconds left of the current sky spell (airborne) / until it may take off again.
var _sky_t := 0.0
var _sky_cd := 0.0
var _orbit_a := 0.0
var _orbit_dir := 1.0


func _init() -> void:
	kind = "dragon"
	display_name = "Ashvane, the Last Dragon"
	relic = "dragonheart"
	xp_value = 1200
	base_health = 4200.0
	walk_speed = 3.6
	melee_range = 9.0
	aggro_radius = 30.0
	arena_radius = 40.0
	enrage_time = 540.0
	hit_radius = 4.0
	hit_height = 6.5
	body.half_extents = Vector3(2.4, 2.2, 2.4)
	air_ceiling = DIVE_ALT + 3.0
	strafe_speed = 1.6
	loot = [["potion_greater", 1.0, 3, 5], ["ember_crystal", 1.0, 8, 12], ["gold_ore", 1.0, 10, 16], ["obsidian", 1.0, 4, 8]]


func _ready() -> void:
	super._ready()
	_read_arena()


func on_spawned(data: Dictionary) -> void:
	if data.has("home"):
		home_location = String(data["home"])
	_read_arena()


## Centre, radius and floor of the arena from the home location (flexible:
## the boss spawn is the centre; the radius is clamped to the location's).
func _read_arena() -> void:
	arena_center = spawn_point if spawn_point != Vector3.ZERO else global_position
	floor_y = arena_center.y
	arena_r = arena_radius * 0.85
	var w = _w()
	if w != null and home_location != "" and w.has_method("location_by_id"):
		var loc: Location = w.location_by_id(StringName(home_location))
		if loc != null:
			for s in loc.spawns_of("boss"):
				arena_center = s["pos"]
				if s.has("arena_radius"):
					arena_r = float(s["arena_radius"])
			arena_r = minf(arena_r, maxf(16.0, loc.radius - 6.0))
	floor_y = arena_center.y
	var dm := model as DragonModel
	if dm != null:
		dm.ground_y = floor_y


func _behind() -> bool:
	for p in _players():
		var to := p.global_position - global_position
		to.y = 0.0
		if to.length() < 15.0 and to.normalized().dot(_fwd()) < -0.3:
			return true
	return false


func _grounded() -> bool:
	return not flying


func _aloft() -> bool:
	return flying and _sky_t > 0.0


func _attacks() -> Dictionary:
	return {
		# On the ground.
		"bite": {"phase": 1, "weight": 3.0, "max": 12.0, "cooldown": 1.0, "ok": _grounded},
		"claw": {"phase": 1, "weight": 2.2, "max": 10.0, "cooldown": 1.0, "ok": _grounded},
		"tail": {"phase": 1, "weight": 4.0, "cooldown": 1.2, "ok": func() -> bool: return not flying and _behind()},
		"breath": {"phase": 1, "weight": 2.0, "min": 6.0, "max": 22.0, "cooldown": 1.8, "ok": _grounded},
		"charge": {"phase": 1, "weight": 1.4, "min": 12.0, "max": 40.0, "cooldown": 1.4, "ok": _grounded},
		"gust": {"phase": 2, "weight": 2.0, "max": 15.0, "cooldown": 1.6, "ok": _grounded},
		"stomp": {"phase": 2, "weight": 2.6, "max": 14.0, "cooldown": 1.5, "ok": _grounded},
		"roar": {"phase": 3, "weight": 2.2, "cooldown": 1.6, "ok": _grounded},
		"takeoff": {"phase": 2, "weight": 4.0, "cooldown": 0.3, "ok": func() -> bool: return not flying and _sky_cd <= 0.0},
		# On the wing.
		"strafe": {"phase": 2, "weight": 2.0, "cooldown": 1.0, "ok": _aloft},
		"barrage": {"phase": 2, "weight": 1.4, "cooldown": 1.0, "ok": _aloft},
		"swoop": {"phase": 2, "weight": 1.6, "cooldown": 1.0, "ok": _aloft},
		"rain": {"phase": 3, "weight": 1.5, "cooldown": 1.0, "ok": _aloft},
		# Phase 3 sky spells end in a dive bomb rather than a landing.
		"dive": {"phase": 3, "weight": 4.0, "cooldown": 1.5, "ok": func() -> bool: return flying and _sky_t < 8.0},
		"land": {"phase": 1, "weight": 50.0, "cooldown": 1.0, "ok": func() -> bool: return flying and _sky_t <= 0.0 and phase < 3},
	}


func _head() -> Vector3:
	return global_position + _fwd() * 8.0 + Vector3(0, 7.0, 0)


func _right() -> Vector3:
	return _fwd().cross(Vector3.UP)


func _ground_at(p: Vector3) -> Vector3:
	return Vector3(p.x, floor_y, p.z)


## Model duration so the blow lands exactly when the telegraph fills.
func _dur(action: String, tele: float) -> float:
	return tele / float(DragonModel.IMPACT.get(action, 0.5))


func _begin_attack(name: String) -> void:
	if _target != null and name in ["bite", "claw", "breath", "gust", "roar", "charge", "stomp"]:
		_face(_target.global_position, 1.0, 60.0)
	var g := _ground_at(global_position)
	match name:
		"bite":
			var tele := 0.72
			_play("bite", _dur("bite", tele))
			_tele("cone", g + _fwd() * 3.0, _fwd(), Vector3(9.5, 24.0, 0), tele, 40.0, "hit", 6.0,
				func() -> void:
					Audio.play("hit_heavy", _head(), 4.0, 0.5)
					_shake_near(global_position, 0.35))
		"claw":
			var side := -1.0 if _rng.randf() < 0.5 else 1.0
			if _target != null:
				side = 1.0 if (_target.global_position - global_position).dot(_right()) >= 0.0 else -1.0
			var c := g + _fwd() * 6.4 + _right() * side * 2.3
			var tele := 0.68
			_play("claw", _dur("claw", tele))
			_tele("circle:claw", c, _fwd(), Vector3(3.6, 0, 0), tele, 32.0, "hit", 7.0,
				func() -> void:
					Audio.play("stomp", c, 4.0, 0.7)
					_shake_near(c, 0.4))
		"tail":
			var tele := 0.82
			_play("tail", _dur("tail", tele))
			Audio.play("growl", _head(), 3.0, 0.5)
			_tele("cone", g - _fwd() * 1.0, -_fwd(), Vector3(15.0, 72.0, 0), tele, 34.0, "hit", 12.0,
				func() -> void:
					_shake_near(global_position, 0.5)
					Audio.play("swing_heavy", global_position - _fwd() * 8.0, 6.0, 0.4))
		"breath":
			var d := BREATH_TIME
			_attack_data["dur"] = d
			_attack_data["origin"] = g + _fwd() * 2.0
			_attack_data["dir"] = _fwd()
			_play("breath", d)
			Audio.play("growl", _head(), 4.0, 0.4)
			var w = _w()
			if w != null:
				w.telegraph("cone", _attack_data["origin"], _fwd(), Vector3(20.0, rad_to_deg(DragonModel.SWEEP) + 14.0, 0), d * DragonModel.BREATH_ON, dimension)
		"charge":
			# A lane through the target; it thunders down it as the warning fills.
			var dir := _fwd()
			var to := (_target.global_position if _target != null else global_position + dir * 20.0) - global_position
			to.y = 0.0
			if to.length() > 1.0:
				dir = to.normalized()
			var end := _inside(_ground_at(global_position + dir * clampf(to.length() + 7.0, 12.0, 30.0)), 5.0)
			var length := maxf(6.0, _flat_to(end))
			_attack_data["from"] = global_position
			_attack_data["end"] = Vector3(end.x, global_position.y, end.z)
			_attack_data["dir"] = dir
			_play("charge", CHARGE_TELE + 0.5)
			Audio.play("roar", _head(), 5.0, 0.7)
			_tele("line", g, dir, Vector3(length + 4.0, 7.5, 0), CHARGE_TELE, 38.0, "hit", 13.0,
				func() -> void:
					_shake_near(global_position, 0.6)
					Audio.play("land_heavy", global_position, 6.0, 0.5))
		"stomp":
			var tele := 1.0
			var c := g + _fwd() * 5.0
			_play("stomp", _dur("stomp", tele))
			Audio.play("roar", _head(), 5.0, 0.55)
			_tele("circle", c, _fwd(), Vector3(5.5, 0, 0), tele, 44.0, "hit", 10.0,
				func() -> void:
					_shake_near(c, 0.9)
					Audio.play("explosion", c, 6.0, 0.4))
			_tele("ring", c, _fwd(), Vector3(5.5, 12.0, 0), tele + 0.4, 20.0, "hit", 9.0,
				func() -> void:
					for i in 8:
						var a := TAU * i / 8.0
						_fx_burst(c + Vector3(cos(a), 0.4, sin(a)) * 9.0, false, 0.7))
		"gust":
			var tele := 0.8
			_play("gust", _dur("gust", tele))
			Audio.play("wing_flap", center(), 6.0, 0.6)
			_tele("cone", g, _fwd(), Vector3(16.0, 55.0, 0), tele, 12.0, "hit", 19.0,
				func() -> void:
					Audio.play("wing_flap", center(), 8.0, 0.45)
					_shake_near(global_position, 0.6))
		"roar":
			_play("roar", 2.0)
			Audio.play("roar_big", _head(), 6.0, 0.75)
			_tele("ring", g, _fwd(), Vector3(5.0, 17.0, 0), 1.3, 28.0, "fire", 10.0,
				func() -> void:
					_shake_near(global_position, 0.8)
					for i in 10:
						var a := TAU * i / 10.0
						_fx_burst(g + Vector3(cos(a), 0.4, sin(a)) * 11.0, true, 0.8))
		"takeoff":
			_stage("takeoff")
			_flights += 1
			_play("takeoff", 1.7)
			Audio.play("wing_flap", center(), 6.0, 0.6)
			Audio.play("roar", _head(), 4.0, 0.6)
		"strafe", "barrage", "dive", "swoop":
			_play("fly")
			_plan_flight(name)
		"rain":
			_stage("rain")
			_attack_data["drops"] = 0
			_play("roar", 1.2)
			Audio.play("roar_big", center(), 5.0, 0.9)
		"land":
			var p := _target if _target != null else _random_player()
			var aim := p.global_position if p != null else arena_center
			var off := global_position - aim
			off.y = 0.0
			off = off.normalized() * 11.0 if off.length() > 0.5 else _fwd() * -11.0
			var spot := _inside(_ground_at(aim + off), 7.0)
			_attack_data["start"] = Vector3(spot.x, floor_y + FLY_ALT * 0.7, spot.z)
			_attack_data["face"] = aim
			_stage("reposition")


func _update_attack(name: String, t: float, delta: float) -> bool:
	match name:
		"bite":
			return t > _dur("bite", 0.72) + 0.1
		"claw":
			return t > _dur("claw", 0.68) + 0.1
		"tail":
			return t > _dur("tail", 0.82) + 0.05
		"breath":
			return _update_breath(t, delta)
		"charge":
			return _update_charge(delta)
		"stomp":
			return t > _dur("stomp", 1.0) + 0.2
		"gust":
			return t > _dur("gust", 0.8)
		"roar":
			return t > 2.0
		"takeoff", "strafe", "barrage", "dive", "swoop", "rain", "land":
			return _update_flight(name, delta)
	return true


## The stream sweeps across the marked cone; only the part it points at burns.
func _update_breath(_t: float, delta: float) -> bool:
	# Real time (not the tempo-scaled attack clock), so the fire never
	# starts before its warning has filled.
	_attack_data["real"] = float(_attack_data.get("real", 0.0)) + delta
	var d: float = _attack_data["dur"]
	var p: float = float(_attack_data["real"]) / d
	if p > DragonModel.BREATH_ON and p < DragonModel.BREATH_OFF:
		_attack_data["tick"] = float(_attack_data.get("tick", 0.0)) - delta
		if float(_attack_data["tick"]) <= 0.0:
			_attack_data["tick"] = 0.22
			var dir: Vector3 = (_attack_data["dir"] as Vector3).rotated(Vector3.UP, DragonModel.breath_yaw(p))
			_hit_shape("cone", _attack_data["origin"], dir, Vector3(20.0, 15.0, 0), _dmg(9.0), "fire", 0.0)
	return p > 1.03


## Lowered head, then the run down the lane: it reaches the end as the warning fills.
func _update_charge(delta: float) -> bool:
	_attack_data["real"] = float(_attack_data.get("real", 0.0)) + delta
	var rt: float = _attack_data["real"]
	var run_from := CHARGE_TELE * 0.55
	if rt >= run_from and rt < CHARGE_TELE:
		var f := (rt - run_from) / (CHARGE_TELE - run_from)
		var a: Vector3 = _attack_data["from"]
		var b: Vector3 = _attack_data["end"]
		var pos := a.lerp(b, f * f * (3.0 - 2.0 * f))
		body.velocity.x = (pos.x - global_position.x) / maxf(delta, 0.001)
		body.velocity.z = (pos.z - global_position.z) / maxf(delta, 0.001)
		var dir: Vector3 = _attack_data["dir"]
		yaw = atan2(-dir.x, -dir.z)
	else:
		body.velocity.x = 0.0
		body.velocity.z = 0.0
	return rt > CHARGE_TELE + 0.55


# --- Flight ---------------------------------------------------------------------------

func _stage(name: String) -> void:
	_attack_data["stage"] = name
	_attack_data["st"] = 0.0


func _inside(p: Vector3, margin := 4.0) -> Vector3:
	var off := Vector3(p.x - arena_center.x, 0, p.z - arena_center.z)
	var r := arena_r - margin
	if off.length() > r:
		off = off.normalized() * r
	return Vector3(arena_center.x + off.x, p.y, arena_center.z + off.z)


## A point clamped to the air volume: inside the arena, floor..air_ceiling.
func _air(p: Vector3, margin := 3.0) -> Vector3:
	var q := _inside(p, margin)
	q.y = clampf(p.y, floor_y, floor_y + air_ceiling)
	return q


## Glide towards `to` (world) at up to `speed`, facing `face`.
func _glide(to: Vector3, speed: float, delta: float, face: Vector3) -> bool:
	to = _air(to, 2.0)
	var d := to - global_position
	var step := d.limit_length(speed * delta)
	global_position += step
	body.velocity = step / maxf(delta, 0.001)
	_face(face, delta, 3.0)
	return d.length() < 0.6


func _update_flight(name: String, delta: float) -> bool:
	_attack_data["st"] = float(_attack_data["st"]) + delta
	var st: float = _attack_data["st"]
	var stage: String = _attack_data["stage"]
	match stage:
		"takeoff":
			if st > 0.55:
				if not flying:
					flying = true
					body.fly = true
					_attack_data["alt0"] = global_position.y
				var rise := clampf((st - 0.55) / 1.15, 0.0, 1.0)
				var alt := FLY_ALT * rise * rise * (3.0 - 2.0 * rise)
				global_position.y = maxf(float(_attack_data["alt0"]), floor_y + alt)
				# Climb out along its heading, towards the arena's middle.
				global_position = global_position.lerp(_inside(global_position + _fwd() * 3.0, 8.0), delta * 1.5)
				body.velocity = Vector3.ZERO
			if st > 1.7:
				_play("fly")
				_sky_t = (13.0 if phase < 3 else 17.0) + _rng.randf() * 3.0
				var off := global_position - arena_center
				_orbit_a = atan2(off.z, off.x)
				_orbit_dir = -1.0 if _rng.randf() < 0.5 else 1.0
				return true
		"reposition":
			var to: Vector3 = _attack_data["start"]
			var face: Vector3 = _attack_data.get("face", to)
			if _glide(to, 14.0, delta, face) or st > 3.6:
				if name == "land":
					_stage("descend")
				else:
					_stage("mark")
					_mark_flight(name)
		"mark":
			var face: Vector3 = _attack_data.get("face", global_position + _fwd())
			_face(face, delta, 4.0)
			body.velocity = Vector3.ZERO
			if name == "barrage":
				_update_barrage(st)
				if st > 3.4:
					return _back_to_orbit()
			elif name == "strafe" and st > 1.15:
				_stage("pass")
				_play("breath", 2.3)
				Audio.play("furnace_roar", center(), 8.0, 0.6)
			elif name == "swoop" and st > SWOOP_TELE * 0.5:
				_stage("swoop")
				_play("rake", SWOOP_TELE * 0.5 + 0.4)
				Audio.play("wing_flap", center(), 8.0, 0.5)
			elif name == "dive":
				if _target != null and st < 0.9:
					_attack_data["mark"] = _ground_at(_target.global_position)
				if st > 1.0 and not _attack_data.has("marked"):
					_attack_data["marked"] = true
					_mark_dive()
				if _attack_data.has("marked") and st > 1.0 + 1.6 - 0.95:
					_stage("dive")
					_play("dive", 0.5)
					Audio.play("roar_big", center(), 5.0, 1.1)
		"pass":
			var from: Vector3 = _attack_data["start"]
			var to: Vector3 = _attack_data["end"]
			var f := clampf(st / 2.3, 0.0, 1.0)
			global_position = from.lerp(to, f)
			body.velocity = (to - from) / 2.3
			_face(to + (to - from), delta, 6.0)
			_attack_data["tick"] = float(_attack_data.get("tick", 0.0)) - delta
			if float(_attack_data["tick"]) <= 0.0 and f < 0.97:
				_attack_data["tick"] = 0.2
				var dir: Vector3 = _attack_data["dir"]
				_hit_shape("circle", _ground_at(global_position + dir * 11.0), dir, Vector3(5.0, 0, 0), _dmg(11.0), "fire", 0.0)
			if f >= 1.0:
				return _back_to_orbit()
		"swoop":
			# Low over the marked lane, claws first; it reaches the end as it fills.
			var from: Vector3 = _attack_data["start"]
			var to: Vector3 = _attack_data["end"]
			var dur := SWOOP_TELE * 0.5
			var f := clampf(st / dur, 0.0, 1.0)
			var pos := from.lerp(to, f)
			pos.y = lerpf(from.y, to.y, f) - sin(PI * f) * (STRAFE_ALT * 0.8 - 3.0)
			global_position = pos
			body.velocity = (to - from) / dur
			_face(to + (to - from), delta, 6.0)
			if st > dur + 0.25:
				return _back_to_orbit()
		"rain":
			# Keeps circling while fire falls on a chain of marked spots.
			_orbit(delta, 1.15)
			var drops: int = _attack_data["drops"]
			var total := 6 + (2 if phase >= 3 else 0)
			if drops < total and st > 0.6 + drops * 0.42:
				_attack_data["drops"] = drops + 1
				var p := _random_player()
				var aim := p.global_position if p != null else arena_center
				var c := _inside(_ground_at(aim + Vector3(_rng.randf_range(-4, 4), 0, _rng.randf_range(-4, 4))), 3.0)
				_tele("circle:fire", c, _fwd(), Vector3(3.2, 0, 0), 1.2, 24.0, "fire", 4.0,
					func() -> void: _fx_burst(c + Vector3(0, 0.4, 0), true, 0.9))
				if drops % 2 == 0:
					_play("attack", 0.5)
			if st > 0.6 + total * 0.42 + 1.3:
				return _back_to_orbit()
		"dive":
			var mark: Vector3 = _attack_data["mark"]
			var remaining := maxf(0.05, 0.95 - st)
			global_position += (mark - global_position) * minf(1.0, delta / remaining)
			body.velocity = Vector3.ZERO
			_face(mark, delta, 8.0)
			if st > 0.95 - 0.56 and not _attack_data.has("slam"):
				_attack_data["slam"] = true
				_play("slam", 1.6)
			if st >= 0.95:
				global_position = mark
				_touch_down()
				_stagger = 2.4
				_stage("stagger")
		"descend":
			var land := _ground_at(global_position)
			var f := clampf(st / 1.1, 0.0, 1.0)
			if not _attack_data.has("land"):
				_attack_data["land"] = true
				_attack_data["alt"] = global_position.y
				_play("land", 1.2)
			global_position.y = lerpf(float(_attack_data["alt"]), land.y, f * f)
			body.velocity = Vector3.ZERO
			if _target != null:
				_face(_target.global_position, delta, 2.0)
			if f >= 1.0:
				_touch_down()
				_stage("settle")
		"settle":
			if st > 0.8:
				return true
		"stagger":
			# The crash leaves it reeling: the opening to punish it.
			if st > _stagger:
				return true
	return false


## Back to circling after a run (it stays in the air).
func _back_to_orbit() -> bool:
	_play("fly")
	var off := global_position - arena_center
	_orbit_a = atan2(off.z, off.x)
	return true


func _touch_down() -> void:
	flying = false
	body.fly = false
	body.velocity = Vector3.ZERO
	global_position.y = floor_y
	_sky_t = 0.0
	_sky_cd = 12.0 if phase < 3 else 10.0
	_shake_near(global_position, 0.6)
	Audio.play("land_heavy", global_position, 6.0, 0.45)


## Circle the arena on the wing (between air attacks), banking round.
func _orbit(delta: float, speed_scale := 1.0) -> void:
	var r := arena_r * 0.62
	_orbit_a += _orbit_dir * ORBIT_SPEED * speed_scale / r * delta
	var lead := _orbit_a + _orbit_dir * 0.35
	var goal := arena_center + Vector3(cos(lead), 0, sin(lead)) * r
	goal.y = floor_y + FLY_ALT + 2.0 * sin(_orbit_a * 2.0)
	_fly_towards(goal, ORBIT_SPEED * speed_scale * 1.3, delta, 0.5)


func _approach(delta: float) -> void:
	if flying:
		_orbit(delta)
		return
	# Flankers get the tail: it reacts quickly to anyone behind it.
	if _next_attack > 0.0 and _behind():
		_next_attack = 0.0
	super._approach(delta)


## Where the flight goes once airborne.
func _plan_flight(name: String) -> void:
	var p := _target if _target != null else _random_player()
	var aim := p.global_position if p != null else arena_center
	match name:
		"strafe", "swoop":
			var dir := aim - arena_center
			dir.y = 0.0
			if dir.length() < 2.0:
				dir = _fwd()
			var turn := _rng.randf_range(-0.5, 0.5) + (PI * 0.5 if name == "swoop" and _rng.randf() < 0.5 else 0.0)
			dir = dir.normalized().rotated(Vector3.UP, turn)
			var span := arena_r * (0.78 if name == "strafe" else 0.6)
			var start := _inside(aim - dir * span, 6.0)
			var end := _inside(aim + dir * span * 0.9, 6.0)
			dir = end - start
			dir.y = 0.0
			dir = dir.normalized()
			var alt := STRAFE_ALT if name == "strafe" else STRAFE_ALT * 0.8
			start.y = floor_y + alt
			end.y = floor_y + alt
			_attack_data["start"] = start
			_attack_data["end"] = end
			_attack_data["dir"] = dir
			_attack_data["face"] = start + dir * 10.0
		"barrage":
			var to := aim - arena_center
			to.y = 0.0
			var hover := _inside(arena_center + (to.normalized() * -arena_r * 0.45 if to.length() > 1.0 else Vector3.ZERO), 8.0)
			hover.y = floor_y + FLY_ALT
			_attack_data["start"] = hover
			_attack_data["face"] = aim
		"dive":
			var hover := _inside(aim + Vector3(_rng.randf_range(-6, 6), 0, _rng.randf_range(-6, 6)), 10.0)
			hover.y = floor_y + DIVE_ALT
			_attack_data["start"] = hover
			_attack_data["face"] = aim
			_attack_data["mark"] = _ground_at(aim)
	_stage("reposition")


func _mark_flight(name: String) -> void:
	match name:
		"strafe":
			var start: Vector3 = _attack_data["start"]
			var end: Vector3 = _attack_data["end"]
			var dir: Vector3 = _attack_data["dir"]
			var a := _ground_at(start + dir * 8.0)
			var length := start.distance_to(end) + 5.0
			var w = _w()
			if w != null:
				w.telegraph("line", a, dir, Vector3(length, 10.0, 0), 1.15, dimension)
			Audio.play("roar_big", center(), 5.0, 0.8)
		"swoop":
			var start: Vector3 = _attack_data["start"]
			var end: Vector3 = _attack_data["end"]
			var dir: Vector3 = _attack_data["dir"]
			var length := start.distance_to(end)
			_tele("line", _ground_at(start), dir, Vector3(length, 6.0, 0), SWOOP_TELE, 36.0, "hit", 12.0,
				func() -> void: Audio.play("swing_heavy", center(), 6.0, 0.5))
			Audio.play("roar", center(), 5.0, 0.8)
		"barrage":
			_attack_data["shots"] = 0
			_play("hover", 3.6)


func _update_barrage(st: float) -> void:
	var shots: int = _attack_data.get("shots", 0)
	var total := 5 + (1 if phase >= 3 else 0)
	if shots < total and st > 0.6 + shots * 0.45:
		_attack_data["shots"] = shots + 1
		_play("attack", 0.5)
		_fireball_at_player()


func _mark_dive() -> void:
	var mark: Vector3 = _attack_data["mark"]
	_tele("circle:crash", mark, _fwd(), Vector3(7.0, 0, 0), 1.6, 58.0, "hit", 16.0,
		func() -> void:
			_fx_burst(mark + Vector3(0, 0.5, 0), true, 2.4)
			_shake_near(mark, 1.0)
			Audio.play("explosion", mark, 6.0, 0.6))
	# Rubble and fire ring out from the crash.
	_tele("ring", mark, _fwd(), Vector3(7.0, 12.0, 0), 1.9, 22.0, "fire", 6.0)


func _fireball_at_player() -> void:
	var w = _w()
	var p := _random_player()
	if w == null or p == null:
		return
	var target := _ground_at(p.global_position) + Vector3(_rng.randf_range(-1.5, 1.5), 0.0, _rng.randf_range(-1.5, 1.5))
	var origin := _head()
	var flight := 1.05
	w.telegraph("circle:fire", target, _fwd(), Vector3(2.6, 0, 0), flight, dimension)
	w.spawn_projectile("fireball", origin, (target - origin) / flight, net_id, Team.MONSTERS, dimension, _dmg(26.0))


# --- Phases, movement ---------------------------------------------------------------

func server_tick(delta: float) -> void:
	if dead:
		# Brought down: it falls out of the sky onto the arena floor.
		if global_position.y > floor_y + 0.05:
			body.velocity.y -= 20.0 * delta
			global_position.y = maxf(floor_y, global_position.y + body.velocity.y * delta)
		super.server_tick(delta)
		return
	if engaged:
		if flying and _attack != "takeoff":
			_sky_t -= delta
		elif not flying:
			_sky_cd -= delta
	super.server_tick(delta)


func _on_died() -> void:
	flying = false
	body.fly = false
	super._on_died()


func _on_phase_changed(new_phase: int) -> void:
	# Mid-attack the blow keeps its animation (it stays in sync with its warning).
	if _attack == "":
		_play("phase", 2.0)
	Audio.play("roar_big", center(), 6.0, 0.75)
	_shake_near(global_position, 0.7)
	_next_attack = 2.0
	# Each new phase opens with its signature: into the sky (phase 2), or a
	# dive bomb when it is already up there (phase 3).
	_queued = "takeoff" if not flying else "dive"
	_sky_cd = 0.0
	if new_phase >= 3 and flying:
		_sky_t = maxf(_sky_t, 6.0)
	# The opener follows the phase roar (at the next attack choice).


func _start_queued() -> void:
	var opener := _queued
	var a: Dictionary = _attacks().get(opener, {})
	if a.is_empty() or phase < int(a.get("phase", 1)) or (a.has("ok") and not (a["ok"] as Callable).call()):
		return
	_queued = ""
	_attack = opener
	_attack_t = 0.0
	_attack_data = {}
	_begin_attack(opener)


func _choose_attack() -> void:
	if _queued != "":
		_start_queued()
		if _attack != "":
			return
		_queued = ""
	super._choose_attack()


func _physics(delta: float) -> void:
	if flying or _attack in ["takeoff", "strafe", "barrage", "dive", "swoop", "rain", "land"]:
		# Flight is flown directly (no gravity, no voxel collision up there),
		# always inside the air volume.
		if flying and _attack_data.get("stage", "") not in ["pass", "swoop", "dive", "reposition", "descend", "takeoff"]:
			global_position += body.velocity * delta
		if flying:
			global_position = _air(global_position, 1.0)
		rotation.y = yaw
		if model != null:
			model.move_speed = Vector2(body.velocity.x, body.velocity.z).length()
			model.grounded = false
			model.turn_rate = angle_difference(_last_yaw, yaw) / maxf(delta, 0.001)
			_last_yaw = yaw
			model.set_burning(burning > 0.0)
			(model as DragonModel).flying = flying
		return
	super._physics(delta)


func _process(delta: float) -> void:
	super._process(delta)
	var dm := model as DragonModel
	if dm == null:
		return
	dm.flying = flying
	if is_nan(dm.ground_y):
		dm.ground_y = floor_y
	dm.look_target = _look_point(60.0)


## Where the head tracks: the target, else the nearest player close by.
func _look_point(radius: float) -> Vector3:
	if _target != null and is_instance_valid(_target):
		return _target.global_position + Vector3(0, 1.6, 0)
	var w = _w()
	if w != null and w.has_method("nearest_player"):
		var p = w.nearest_player(global_position, dimension, radius)
		if p != null:
			return (p as Node3D).global_position + Vector3(0, 1.6, 0)
	return Vector3.INF


func _reset() -> void:
	flying = false
	body.fly = false
	_stagger = 0.0
	_queued = ""
	_sky_t = 0.0
	_sky_cd = 0.0
	super._reset()
	global_position.y = floor_y
