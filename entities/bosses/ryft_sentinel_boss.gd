class_name RyftSentinelBoss
extends "res://entities/bosses/ryft_boss.gd"
## The Prism Sentinel, keeper of the Broken Observatory on Ryft Island: a
## floating crystal construct held together by bronze astrolabe rings, with a
## burning prism heart. It never touches the ground and turns slowly, like an
## instrument tracking a star. It drifts on an orbit around its target at
## lance range, glides to new vantage points, swoops low to slam and rises
## to rain crystal or sweep its beam (ryft_boss.gd: the air volume).
##   Phase 1: crystal lance (a line at its target), shard nova (two rings, the
##            outer one later), prism slam (swoops down, fists crash in
##            front), backhand swipe (a wide cone)
##   Phase 2: + sweeping prism beam (rises; a fan of lines that fill one
##            after another as it turns), + shard rain (rises high; marked
##            circles under everyone), + refraction mirrors (three mirrors
##            round the target, each fires a lance through it), + refracting
##            step (blinks behind its target and swipes)
##   Phase 3: + prism charge (a marked lane, then it rams along it),
##            + shard orbit (rings that sweep outwards in turn), +
##            constellation (star pattern, then the centre); lances come in
##            pairs, the heart is exposed and everything comes faster
## Model actions strike at 55 % of their length (RyftModel.IMPACT), so every
## animation lands as its telegraph fills.

const IMPACT := 0.55


func _init() -> void:
	kind = "ryft_sentinel"
	display_name = "The Prism Sentinel"
	relic = "prism_heart"
	xp_value = 2200
	base_health = 4600.0
	walk_speed = 2.6
	melee_range = 6.5
	aggro_radius = 24.0
	arena_radius = 30.0
	enrage_time = 540.0
	hit_radius = 1.9
	hit_height = 6.4
	base_alt = 0.8
	orbit_range = 9.0
	body.half_extents = Vector3(1.3, 2.6, 1.3)
	loot = [["potion_greater", 1.0, 3, 5], ["amethyst", 1.0, 6, 10], ["mithril_ore", 1.0, 4, 8], ["sapphire", 0.8, 2, 4],
		["ryftwood", 1.0, 4, 8], ["gold_ore", 1.0, 8, 12]]


func _ready() -> void:
	super._ready()
	if not ItemDB.exists(relic):
		relic = ""


func _attacks() -> Dictionary:
	return {
		"lance": {"phase": 1, "weight": _wt("lance", 2.4), "min": 3.0, "cooldown": 1.2},
		"nova": {"phase": 1, "weight": _wt("nova", 1.6), "max": 11.0, "cooldown": 1.5},
		"slam": {"phase": 1, "weight": _wt("slam", 2.0), "max": 11.0, "cooldown": 1.3},
		"swipe": {"phase": 1, "weight": _wt("swipe", 2.0), "max": 9.0, "cooldown": 1.0},
		"beam": {"phase": 2, "weight": _wt("beam", 1.6), "cooldown": 1.8},
		"rain": {"phase": 2, "weight": _wt("rain", 1.4), "cooldown": 1.4},
		"mirrors": {"phase": 2, "weight": _wt("mirrors", 1.4), "cooldown": 1.6},
		"refract": {"phase": 2, "weight": _wt("refract", 1.2), "min": 5.0, "cooldown": 0.8},
		"charge": {"phase": 3, "weight": _wt("charge", 1.5), "min": 5.0, "cooldown": 1.6},
		"orbit": {"phase": 3, "weight": _wt("orbit", 1.3), "max": 14.0, "cooldown": 1.8},
		"constellation": {"phase": 3, "weight": _wt("constellation", 1.4), "cooldown": 2.0},
	}


## Plays `action` so its strike frame meets a telegraph filling in `tele` seconds.
func _strike(action: String, tele: float) -> void:
	_play(action, tele / IMPACT)


func _begin_attack(name: String) -> void:
	_note_attack(name)
	if _target != null:
		_face(_target.global_position, 1.0, 60.0)
	match name:
		"lance":
			_lance(1.1)
			Audio.play("portal", center(), 0.0, 1.8)
		"nova":
			_strike("nova", 1.2)
			_alt = 1.6
			_tele("ring:crystal", _ground_here(), _fwd(), Vector3(2.0, 8.0, 0), 1.2, 34.0, "hit", 7.0)
			_tele("ring:crystal", _ground_here(), _fwd(), Vector3(10.0, 15.0, 0), 2.0, 30.0, "hit", 5.0)
			Audio.play("roar_big", center(), 0.0, 1.6)
		"slam":
			# Swoops in and down: the fists land in front of where it stops.
			_alt = 0.0
			var dir := _dir_to(_target)
			var dist := clampf(_flat_dist(_target) - 4.0, 0.0, 6.0)
			_attack_data["dir"] = dir
			_attack_data["dist"] = dist
			var at := _gp(global_position + dir * (dist + 4.0))
			_strike("slam", 1.2)
			_tele("circle:crystal", at, dir, Vector3(4.6, 0, 0), 1.2, 44.0, "hit", 7.0,
				func() -> void:
					_shake_near(at, 0.6)
					_fx_burst(at + Vector3(0, 0.4, 0), false, 1.2)
					Audio.play("stomp", at, 4.0, 0.7))
		"swipe":
			_swipe(0.8)
		"beam":
			_alt = 4.0
			_strike("beam", 1.0)
			# A sweeping beam: lines fanning across, each fills before it fires.
			var base := atan2(-_fwd().x, -_fwd().z)
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			var count := 7 if phase < 3 else 9
			_attack_data["sweep"] = [base, side, count]
			for i in count:
				var a := base + side * deg_to_rad(-60.0 + 120.0 * float(i) / (count - 1))
				var d := Vector3(-sin(a), 0, -cos(a))
				_tele("line:prism", _ground_here(), d, Vector3(22.0, 2.2, 0), 1.0 + i * 0.22, 30.0, "fire", 3.0)
			Audio.play("fireball_cast", center(), 2.0, 0.5)
		"rain":
			_alt = 7.0
			_play("volley", 0.5 + (6 + phase * 2) * 0.14 + 1.1)
			_attack_data["drops"] = 0
		"mirrors":
			_alt = 2.5
			_strike("special1", 1.4)
			var tp := _target.global_position if _target != null else spawn_point
			var a0 := _rng.randf() * TAU
			for i in 3:
				var a := a0 + TAU * i / 3.0
				var m := _clamp_arena(tp + Vector3(cos(a), 0, sin(a)) * 10.0, 0.95)
				var d := tp - m
				d.y = 0.0
				d = d.normalized() if d.length() > 0.1 else _fwd()
				_fx_burst(_gp(m) + Vector3(0, 2.0, 0), false, 0.9)
				_tele("line:prism", _gp(m), d, Vector3(20.0, 2.4, 0), 1.4 + i * 0.3, 32.0, "fire", 4.0)
			Audio.play("portal", center(), 3.0, 1.4)
		"refract":
			_play("teleport", 0.6)
			var dest := spawn_point
			if _target != null:
				dest = _target.global_position + _dir_to(_target) * 5.0
			_attack_data["dest"] = dest
		"charge":
			_alt = 0.6
			var dir := _dir_to(_target)
			var length := clampf(_flat_dist(_target) + 6.0, 10.0, 24.0)
			_attack_data["dir"] = dir
			_attack_data["len"] = length
			_strike("charge", 1.0)
			_tele("line:crystal", _ground_here(), dir, Vector3(length, 3.4, 0), 1.0, 40.0, "hit", 9.0)
			Audio.play("roar_big", center(), 2.0, 1.7)
		"orbit":
			_strike("spin", 1.2)
			_tele("ring:crystal", _ground_here(), _fwd(), Vector3(2.5, 6.0, 0), 1.2, 30.0, "hit", 6.0)
			_tele("ring:crystal", _ground_here(), _fwd(), Vector3(6.0, 9.5, 0), 1.8, 30.0, "hit", 6.0)
			_tele("ring:crystal", _ground_here(), _fwd(), Vector3(9.5, 13.0, 0), 2.4, 30.0, "hit", 6.0)
			Audio.play("portal", center(), 2.0, 2.0)
		"constellation":
			_alt = 3.0
			_strike("special2", 2.4)
			var r := 9.0
			for i in 5:
				var a := TAU * i / 5.0 + _rng.randf() * 0.3
				_tele("circle:crystal", _ground_here() + Vector3(cos(a), 0, sin(a)) * r, _fwd(), Vector3(4.0, 0, 0), 1.3 + i * 0.12, 34.0, "hit", 4.0)
			_tele("circle:prism", _ground_here(), _fwd(), Vector3(5.5, 0, 0), 2.4, 40.0, "fire", 9.0,
				func() -> void: _shake_near(global_position, 0.7))
			Audio.play("roar_big", center(), 3.0, 1.4)


func _lance(tele: float) -> void:
	_strike("thrust", tele)
	_tele("line:crystal", _ground_here(), _dir_to(_target), Vector3(20.0, 2.6, 0), tele, 38.0, "hit", 5.0)


func _swipe(tele: float) -> void:
	_strike("swipe", tele)
	_tele("cone:crystal", _ground_here(), _fwd(), Vector3(8.0, 55.0, 0), tele, 36.0, "hit", 8.0,
		func() -> void: Audio.play("swing", center(), 4.0, 0.6))


func _update_attack(name: String, t: float, delta: float) -> bool:
	_hover(delta, 2.0)
	if name != "charge":
		body.velocity.x = lerpf(body.velocity.x, 0.0, 1.0 - exp(-4.0 * delta))
		body.velocity.z = lerpf(body.velocity.z, 0.0, 1.0 - exp(-4.0 * delta))
	match name:
		"lance":
			# Phase 3: a second lance, re-aimed, right behind the first.
			if phase >= 3 and t > 0.7 and not _attack_data.has("second"):
				_attack_data["second"] = true
				if _target != null:
					_face(_target.global_position, 1.0, 60.0)
				_lance(0.9)
			return t > (2.4 if phase >= 3 else 1.6)
		"nova":
			return t > 2.3
		"slam":
			if t < 0.8:
				var dir: Vector3 = _attack_data["dir"]
				var dist: float = _attack_data["dist"]
				body.velocity.x = dir.x * dist / 0.8
				body.velocity.z = dir.z * dist / 0.8
			return t > 1.8
		"swipe":
			return t > 1.3
		"beam":
			# The body turns with the sweep so the prism points down each line.
			var sw: Array = _attack_data["sweep"]
			var count: int = sw[2]
			var i := clampi(int((t - 1.0) / 0.22), 0, count - 1)
			var a: float = float(sw[0]) + float(sw[1]) * deg_to_rad(-60.0 + 120.0 * float(i) / (count - 1))
			yaw = lerp_angle(yaw, a, 1.0 - exp(-6.0 * delta))
			return t > (2.9 if phase < 3 else 3.3)
		"rain":
			var drops: int = _attack_data["drops"]
			var total := 6 + phase * 2
			if drops < total and t > 0.3 + drops * 0.14:
				_attack_data["drops"] = drops + 1
				var p := _random_player()
				var c := (p.global_position if p != null else spawn_point) + Vector3(_rng.randf_range(-5, 5), 0, _rng.randf_range(-5, 5))
				_tele("circle:crystal", c, _fwd(), Vector3(2.4, 0, 0), 1.1, 24.0)
			return t > 0.5 + total * 0.14 + 1.1
		"mirrors":
			return t > 2.3
		"refract":
			if t > 0.45 and not _attack_data.has("moved"):
				_attack_data["moved"] = true
				_blink_to(_attack_data["dest"])
				if _target != null:
					_face(_target.global_position, 1.0, 60.0)
			if t > 0.6 and not _attack_data.has("swung"):
				_attack_data["swung"] = true
				_swipe(0.8)
			return t > 2.0
		"charge":
			var dir: Vector3 = _attack_data["dir"]
			var length: float = _attack_data["len"]
			if t > 1.0 and t < 1.45:
				body.velocity.x = dir.x * length / 0.45
				body.velocity.z = dir.z * length / 0.45
				yaw = atan2(-dir.x, -dir.z)
			else:
				body.velocity.x = lerpf(body.velocity.x, 0.0, 1.0 - exp(-8.0 * delta))
				body.velocity.z = lerpf(body.velocity.z, 0.0, 1.0 - exp(-8.0 * delta))
			# Never ram out of the arena.
			var out := global_position - spawn_point
			out.y = 0.0
			if out.length() > arena_radius * 0.92 and Vector2(body.velocity.x, body.velocity.z).dot(Vector2(out.x, out.z)) > 0.0:
				body.velocity.x = 0.0
				body.velocity.z = 0.0
			return t > 2.0
		"orbit":
			return t > 2.7
		"constellation":
			return t > 2.8
	return true


func _on_phase_changed(new_phase: int) -> void:
	_play("phase", 2.0)
	Audio.play("roar_big", center(), 4.0, 1.5)
	_shake_near(global_position, 0.5)
	_alt = 2.5
	# The construct sheds its shell: a burst ring around it, clearly marked.
	_tele("ring:crystal", _ground_here(), _fwd(), Vector3(1.5, 6.0 + new_phase, 0), 1.5, 26.0, "hit", 9.0)
	_next_attack = 2.0
