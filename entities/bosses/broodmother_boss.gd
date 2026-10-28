class_name BroodmotherBoss
extends Boss
## Vexhira, the Broodmother: a giant spider queen in the Weeping Hollow, a
## cavern deep beneath Emberwood.
##   Phase 1: bite (cone), leg stab (two marked circles under her raised
##            forelegs), web lash (a lane of silk shot from her spinnerets that
##            knocks you down), venom volley (lobbed globs, landing spots
##            marked), foreleg sweep (wide cone), skitter (scuttles to a
##            flank, often along the cavern wall)
##   Phase 2: + brood (the egg sacs on her back burst into spiderlings),
##            + pounce (crouches, leaps onto a marked spot), + venom spray
##            (a wide marked cone), + silk swing (up her line, then swings
##            down a marked lane across the hollow and lets go at the far end)
##   Phase 3: climbs to the cavern roof on a silk line (the roof height is
##            probed, so any lair works), rains venom on marked spots, then
##            drops onto one of them; plus everything above, faster.
## `flying` (replicated) = hanging from the roof. Timings come from
## BroodmotherModel.IMPACT so the animation and the hit agree.

const HANG_BELOW := 6.5   ## body hangs this far under the roof
const SWING_TELE := 1.4

var arena_center := Vector3.ZERO
var arena_r := 22.0
var floor_y := 0.0
var ceiling_y := NAN
var _hang_y := 0.0
## Phase 2 began mid-attack: the egg sacs burst as soon as that blow ends.
var _brood_due := false


func _init() -> void:
	kind = "broodmother"
	display_name = "Vexhira, the Broodmother"
	relic = "brood_heart"
	xp_value = 1400
	base_health = 3800.0
	walk_speed = 4.4
	melee_range = 6.5
	aggro_radius = 22.0
	arena_radius = 30.0
	enrage_time = 480.0
	hit_radius = 3.6
	hit_height = 4.4
	body.half_extents = Vector3(2.0, 1.6, 2.0)
	strafe_speed = 2.2
	loot = [["potion_greater", 1.0, 2, 4], ["silver_ore", 1.0, 6, 10], ["amethyst", 1.0, 3, 6], ["spider_silk", 1.0, 6, 12],
		["gold_ore", 1.0, 6, 10], ["ruby", 0.7, 1, 3], ["ember_crystal", 1.0, 3, 6]]


func _ready() -> void:
	super._ready()
	if not ItemDB.exists(relic):
		relic = ""
	_read_arena()


func on_spawned(data: Dictionary) -> void:
	if data.has("home"):
		home_location = String(data["home"])
	_read_arena()


## Arena centre / radius from the home location, floor from the spawn, and
## the cavern roof probed straight up through the voxels.
func _read_arena() -> void:
	arena_center = spawn_point if spawn_point != Vector3.ZERO else global_position
	arena_r = arena_radius * 0.75
	var w = _w()
	var loc: Location = null
	if w != null and home_location != "" and w.has_method("location_by_id"):
		loc = w.location_by_id(StringName(home_location))
		if loc != null:
			for s in loc.spawns_of("boss"):
				arena_center = s["pos"]
				if s.has("arena_radius"):
					arena_r = float(s["arena_radius"])
				if s.has("ceiling"):
					ceiling_y = float(s["ceiling"])
			arena_r = minf(arena_r, maxf(12.0, loc.radius - 6.0))
	floor_y = arena_center.y
	if is_nan(ceiling_y):
		ceiling_y = _probe_ceiling(loc)
	var bm := model as BroodmotherModel
	if bm != null:
		bm.ground_y = floor_y
		bm.ceiling_y = ceiling_y


func _probe_ceiling(loc: Location) -> float:
	var fallback := floor_y + (minf(loc.half_height * 1.4, 24.0) if loc != null and loc.half_height > 0.0 else 18.0)
	var vw: VoxelWorld = null
	if sim_world == null and is_inside_tree():
		vw = voxels()
	if vw == null:
		return fallback
	var x := int(floor(arena_center.x))
	var z := int(floor(arena_center.z))
	for dy in range(6, 48):
		if vw.is_solid(Vector3i(x, int(floor_y) + dy, z)):
			return floor_y + dy
	return fallback


func _attacks() -> Dictionary:
	return {
		"bite": {"phase": 1, "weight": 3.0, "max": 9.0, "cooldown": 0.9},
		"stab": {"phase": 1, "weight": 2.0, "max": 9.0, "cooldown": 1.0},
		"web": {"phase": 1, "weight": 2.0, "min": 4.0, "cooldown": 1.3},
		"venom": {"phase": 1, "weight": 1.6, "min": 5.0, "cooldown": 1.4},
		"brood": {"phase": 2, "weight": 1.0, "cooldown": 1.6, "ok": func() -> bool: return summons.size() < 5},
		"pounce": {"phase": 2, "weight": 1.6, "min": 7.0, "cooldown": 1.2},
		"ceiling": {"phase": 3, "weight": 1.6, "cooldown": 1.5},
		"sweep": {"phase": 1, "weight": 2.0, "max": 8.0, "cooldown": 0.9},
		"skitter": {"phase": 1, "weight": 1.2, "cooldown": 0.4},
		"spray": {"phase": 2, "weight": 1.5, "max": 13.0, "cooldown": 1.2},
		"swing": {"phase": 2, "weight": 1.2, "min": 6.0, "cooldown": 1.4},
	}


func _ground_at(p: Vector3) -> Vector3:
	return Vector3(p.x, floor_y, p.z)


func _dur(action: String, tele: float) -> float:
	return tele / float(BroodmotherModel.IMPACT.get(action, 0.5))


func _inside(p: Vector3, margin := 4.0) -> Vector3:
	var off := Vector3(p.x - arena_center.x, 0, p.z - arena_center.z)
	if off.length() > arena_r - margin:
		off = off.normalized() * (arena_r - margin)
	return Vector3(arena_center.x + off.x, p.y, arena_center.z + off.z)


func _begin_attack(name: String) -> void:
	if _target != null:
		_face(_target.global_position, 1.0, 60.0)
	var g := _ground_at(global_position)
	match name:
		"bite":
			var tele := 0.6
			_play("bite", _dur("bite", tele))
			Audio.play("spider_hiss", center(), 4.0, 0.6)
			_tele("cone", g + _fwd() * 2.0, _fwd(), Vector3(8.5, 32.0, 0), tele, 34.0, "hit", 5.0,
				func() -> void: Audio.play("hit_heavy", g + _fwd() * 5.0, 3.0, 0.8))
		"stab":
			var tele := 0.65
			_play("slam", _dur("slam", tele))
			Audio.play("spider_hiss", center(), 5.0, 0.5)
			var right := _fwd().cross(Vector3.UP)
			for side: float in [-1.0, 1.0]:
				var c := g + _fwd() * 6.5 + right * side * 3.0
				_tele("circle", c, _fwd(), Vector3(2.6, 0, 0), tele, 30.0, "hit", 6.0,
					func() -> void:
						Audio.play("stomp", c, 2.0, 1.1)
						_shake_near(c, 0.3))
		"web":
			var tele := 0.9
			_play("web", _dur("shoot", tele))
			var dir := _fwd()
			if _target != null:
				dir = (_target.global_position - global_position)
				dir.y = 0.0
				dir = dir.normalized() if dir.length() > 0.1 else _fwd()
			_tele("line:web", g + dir * 1.5, dir, Vector3(22.0, 3.4, 0), tele, 26.0, "hit", 9.0,
				func() -> void: Audio.play("swing", center(), 4.0, 0.5))
		"venom":
			_play("cast", 1.4)
			Audio.play("spider_hiss", center(), 4.0, 0.9)
			_attack_data["shots"] = 0
		"brood":
			_play("summon", 1.8)
			Audio.play("spider_hiss", center(), 6.0, 0.45)
		"pounce":
			var target := _inside(_ground_at(_target.global_position if _target != null else global_position + _fwd() * 9.0), 4.0)
			_attack_data["mark"] = target
			_attack_data["from"] = global_position
			_attack_data["real"] = 0.0
			var tele := 1.25
			_play("lunge", _dur("lunge", tele))
			Audio.play("spider_hiss", center(), 6.0, 0.7)
			_tele("circle", target, _fwd(), Vector3(5.0, 0, 0), tele, 44.0, "hit", 10.0,
				func() -> void:
					_shake_near(target, 0.7)
					Audio.play("stomp", target, 4.0, 0.7))
		"sweep":
			var tele := 0.55
			_play("sweep", _dur("sweep", tele))
			Audio.play("spider_hiss", center(), 5.0, 0.55)
			_tele("cone", g + _fwd() * 1.0, _fwd(), Vector3(8.0, 120.0, 0), tele, 28.0, "hit", 9.0,
				func() -> void:
					Audio.play("swing_heavy", g + _fwd() * 5.0, 4.0, 0.7)
					_shake_near(global_position, 0.25))
		"skitter":
			# Scuttle to a flank: out towards the cavern wall, round the target.
			var around := (_target.global_position if _target != null else global_position) - arena_center
			around.y = 0.0
			var a := atan2(around.z, around.x) + _rng.randf_range(0.9, 1.9) * (-1.0 if _rng.randf() < 0.5 else 1.0)
			var r := arena_r * _rng.randf_range(0.45, 0.85)
			_attack_data["to"] = _inside(arena_center + Vector3(cos(a), 0, sin(a)) * r, 3.0)
			_play("dodge", 1.4)
			Audio.play("spider_hiss", center(), 3.0, 1.2)
		"spray":
			var tele := 0.8
			_play("spit", _dur("spit", tele))
			Audio.play("spider_hiss", center(), 6.0, 0.5)
			_tele("cone:venom", g + _fwd() * 1.5, _fwd(), Vector3(13.0, 70.0, 0), tele, 30.0, "hit", 4.0,
				func() -> void:
					_fx_burst(g + _fwd() * 7.0 + Vector3(0, 0.5, 0), false, 1.2)
					Audio.play("spider_hiss", g + _fwd() * 6.0, 4.0, 1.4))
		"swing":
			_play("roar", 1.0)
			Audio.play("spider_hiss", center(), 6.0, 0.6)
			_attack_data["real"] = 0.0
		"ceiling":
			_play("roar", 1.4)
			Audio.play("spider_hiss", center(), 8.0, 0.4)
			_attack_data["rained"] = 0
			_attack_data["real"] = 0.0


func _update_attack(name: String, t: float, delta: float) -> bool:
	match name:
		"bite":
			return t > _dur("bite", 0.6)
		"stab":
			return t > _dur("slam", 0.65) + 0.1
		"web":
			return t > _dur("shoot", 0.9)
		"venom":
			var shots: int = _attack_data["shots"]
			var total := 3 + phase
			if shots < total and t > 0.45 + shots * 0.24:
				_attack_data["shots"] = shots + 1
				_venom_glob()
			return t > 0.7 + total * 0.24
		"brood":
			if t > 0.95 and not _attack_data.has("done"):
				_attack_data["done"] = true
				_summon("spiderling", 3 if phase < 3 else 4, 4.5)
			return t > 1.9
		"pounce":
			# Crouch, leap in an arc, land as the marker fills (real time).
			_attack_data["real"] = float(_attack_data["real"]) + delta
			var rt: float = _attack_data["real"]
			if rt > 0.5 and rt < 1.25:
				var f := (rt - 0.5) / 0.75
				var a: Vector3 = _attack_data["from"]
				var b: Vector3 = _attack_data["mark"]
				var pos := a.lerp(b, f)
				pos.y = lerpf(a.y, b.y, f) + sin(PI * f) * 5.5
				global_position = pos
				body.velocity = Vector3.ZERO
			elif rt >= 1.25 and not _attack_data.has("landed"):
				_attack_data["landed"] = true
				global_position = _attack_data["mark"]
			return rt > 1.9
		"ceiling":
			return _update_ceiling(delta)
		"sweep":
			return t > _dur("sweep", 0.55)
		"skitter":
			var to: Vector3 = _attack_data["to"]
			_move_towards(to, walk_speed * 2.4, delta, 1.0)
			_move_intent = false
			if _target != null and _flat_to(to) < 3.0:
				_face(_target.global_position, delta, 6.0)
			return _flat_to(to) < 1.5 or t > 3.0
		"spray":
			return t > _dur("spit", 0.8) + 0.1
		"swing":
			return _update_swing(delta)
	return true


## Up the silk line, then a pendulum swing down a marked lane across the
## hollow (it reaches the far end as the lane fills) and a drop to the floor.
func _update_swing(delta: float) -> bool:
	_attack_data["real"] = float(_attack_data["real"]) + delta
	var t: float = _attack_data["real"]
	var top := clampf(ceiling_y - HANG_BELOW, floor_y + 5.0, floor_y + 12.0)
	if t < 1.0:
		if t > 0.3:
			if not flying:
				flying = true
				body.fly = true
				_hang_y = global_position.y
			var f := clampf((t - 0.3) / 0.7, 0.0, 1.0)
			global_position.y = lerpf(_hang_y, top, f * f * (3.0 - 2.0 * f))
			body.velocity = Vector3.ZERO
		return false
	if not _attack_data.has("from"):
		var aim := _target.global_position if _target != null else arena_center
		var dir := aim - global_position
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.5 else _fwd()
		var from := global_position
		var end := _inside(_ground_at(aim + dir * 8.0), 3.0)
		_attack_data["from"] = from
		_attack_data["end"] = end
		_attack_data["dir"] = dir
		_play("glide", SWING_TELE + 0.6)
		_tele("line:web", _ground_at(from), dir, Vector3(maxf(6.0, Vector2(end.x - from.x, end.z - from.z).length()), 4.5, 0),
			SWING_TELE, 40.0, "hit", 11.0,
			func() -> void:
				_shake_near(global_position, 0.6)
				Audio.play("stomp", global_position, 5.0, 0.6))
	var st := t - 1.0
	var a: Vector3 = _attack_data["from"]
	var b: Vector3 = _attack_data["end"]
	var dir: Vector3 = _attack_data["dir"]
	yaw = lerp_angle(yaw, atan2(-dir.x, -dir.z), 1.0 - exp(-6.0 * delta))
	var swing_from := SWING_TELE * 0.45
	if st >= swing_from and st < SWING_TELE:
		var f := (st - swing_from) / (SWING_TELE - swing_from)
		var pos := a.lerp(b, f)
		# A pendulum arc: low through the middle, rising to the far end.
		pos.y = lerpf(a.y, floor_y + 1.5, f) - sin(PI * f) * maxf(0.0, a.y - floor_y - 2.0) * 0.6
		pos.y = maxf(pos.y, floor_y)
		global_position = pos
		body.velocity = Vector3.ZERO
	elif st >= SWING_TELE:
		if flying:
			flying = false
			body.fly = false
			body.velocity = Vector3.ZERO
			global_position = b
			_play("lunge", 0.6)
		return st > SWING_TELE + 0.6
	return false


func _physics(delta: float) -> void:
	if _attack == "pounce" and float(_attack_data.get("real", 0.0)) > 0.5 and float(_attack_data.get("real", 0.0)) < 1.25:
		rotation.y = yaw
		_sync()
		return
	if flying or (_attack == "swing" and _attack_data.has("from")):
		rotation.y = yaw
		_sync()
		return
	super._physics(delta)
	_sync()


func _process(delta: float) -> void:
	super._process(delta)
	_sync()


func _sync() -> void:
	var bm := model as BroodmotherModel
	if bm == null:
		return
	bm.hanging = flying
	if is_nan(bm.ground_y):
		bm.ground_y = floor_y
	if is_nan(bm.ceiling_y):
		bm.ceiling_y = ceiling_y


func _venom_glob() -> void:
	var w = _w()
	var p := _random_player()
	if w == null or p == null:
		return
	var target := _ground_at(p.global_position) + Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5))
	var origin := global_position + Vector3(0, 3.4, 0) + _fwd() * 3.0
	var flight := 0.95
	var vel := (target - origin) / flight + Vector3(0, 0.5 * 9.0 * flight, 0)
	w.telegraph("circle:venom", target, _fwd(), Vector3(2.6, 0, 0), flight, dimension)
	w.spawn_projectile("bile", origin, vel, net_id, Team.MONSTERS, dimension, _dmg(22.0))


## Up the silk line, rain venom, then drop onto a marked spot.
func _update_ceiling(delta: float) -> bool:
	_attack_data["real"] = float(_attack_data["real"]) + delta
	var t: float = _attack_data["real"]
	var top := maxf(floor_y + 6.0, ceiling_y - HANG_BELOW)
	if t < 1.8:
		if t > 0.5:
			if not flying:
				flying = true
				body.fly = true
				_hang_y = global_position.y
			var f := clampf((t - 0.5) / 1.3, 0.0, 1.0)
			global_position.y = lerpf(_hang_y, top, f * f * (3.0 - 2.0 * f))
			body.velocity = Vector3.ZERO
	elif t < 4.4:
		global_position.y = top + sin(t * 2.0) * 0.15
		var rained: int = _attack_data["rained"]
		if rained < 7 and t > 2.0 + rained * 0.32:
			_attack_data["rained"] = rained + 1
			var p := _random_player()
			if p != null:
				var c := _ground_at(p.global_position) + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3))
				_tele("circle:venom", c, _fwd(), Vector3(2.8, 0, 0), 1.1, 24.0)
				_fx_burst(Vector3(c.x, top + 1.0, c.z), false, 0.5)
	elif t < 5.6:
		if not _attack_data.has("mark"):
			var target := _inside(_ground_at(_target.global_position if _target != null else arena_center), 4.0)
			_attack_data["mark"] = target
			_tele("circle", target, _fwd(), Vector3(6.0, 0, 0), 1.2, 52.0, "hit", 12.0,
				func() -> void:
					_shake_near(target, 1.0)
					Audio.play("stomp", target, 6.0, 0.5))
		var mark: Vector3 = _attack_data["mark"]
		if t < 5.15:
			# Swing over the mark on the line.
			var hover := Vector3(mark.x, top, mark.z)
			global_position = global_position.lerp(hover, 1.0 - exp(-3.0 * delta))
		else:
			# Drop: arrive exactly as the marker fills.
			var remaining := maxf(0.02, 5.6 - t)
			global_position += (mark - global_position) * minf(1.0, delta / remaining)
	elif t < 6.6:
		if flying:
			flying = false
			body.fly = false
			body.velocity = Vector3.ZERO
			global_position = _attack_data["mark"]
			_play("hit", 0.6)
			_shake_near(global_position, 0.7)
	else:
		return true
	return false


func _on_phase_changed(new_phase: int) -> void:
	# Mid-attack the blow keeps its animation (it stays in sync with its warning).
	if _attack == "":
		_play("phase", 2.0)
	Audio.play("spider_hiss", center(), 8.0, 0.4)
	_shake_near(global_position, 0.5)
	_next_attack = 1.0
	if new_phase == 2:
		if _attack == "":
			_attack = "brood"
			_attack_t = 0.0
			_attack_data = {}
			_begin_attack("brood")
		else:
			_brood_due = true


func _choose_attack() -> void:
	if _brood_due:
		_brood_due = false
		_attack = "brood"
		_attack_t = 0.0
		_attack_data = {}
		body.velocity.x = 0.0
		body.velocity.z = 0.0
		_begin_attack("brood")
		return
	super._choose_attack()


func _reset() -> void:
	_brood_due = false
	flying = false
	body.fly = false
	super._reset()
