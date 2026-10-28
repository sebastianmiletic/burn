class_name VoidSovereignBoss
extends "res://entities/bosses/ryft_boss.gd"
## The Void Sovereign, who waits on the Crown of the Ryft: a towering shape
## cut out of the night sky, a regal torso of starlight above a trailing
## vortex of void, crowned by orbiting crystal shards. It glides on an orbit
## round its target at lash range, sweeps to new vantage points, folds space
## to blink, rises over the crown to call down stars and plunges along void
## lanes (ryft_boss.gd: the air volume).
##   Phase 1: void lash (a wide cone of tendrils), star orbs (homing bolts),
##            rift (a marked circle under its target that implodes), gravity
##            well (a wide pull towards it, then a crushing centre)
##   Phase 2: + starfall (rises; many small marked impacts), + blink (folds
##            space beside a player and lashes), + void dash (a marked lane
##            it tears along), + calls shades
##   Phase 3: + eclipse (the whole crown erupts in rings with safe bands),
##            + mirrored clones (three reflections round its target, each
##            lashes in turn), + black hole (rises over the centre: a pull,
##            then an outward burst with a safe band), rifts open under
##            everyone
## Model actions strike at 55 % of their length, so every animation lands as
## its telegraph fills.

const IMPACT := 0.55


func _init() -> void:
	kind = "void_sovereign"
	display_name = "The Void Sovereign"
	relic = "void_crown"
	xp_value = 3200
	base_health = 6200.0
	walk_speed = 2.8
	melee_range = 7.0
	aggro_radius = 26.0
	arena_radius = 32.0
	enrage_time = 600.0
	hit_radius = 1.6
	hit_height = 7.6
	base_alt = 0.6
	orbit_range = 7.5
	body.half_extents = Vector3(1.2, 3.0, 1.2)
	loot = [["potion_greater", 1.0, 4, 6], ["amethyst", 1.0, 8, 14], ["mithril_ore", 1.0, 6, 10], ["sapphire", 1.0, 3, 6],
		["gold_ore", 1.0, 14, 20], ["ryftwood", 1.0, 6, 10]]


func _ready() -> void:
	super._ready()
	air_ceiling = 16.0
	if not ItemDB.exists(relic):
		relic = ""


func _attacks() -> Dictionary:
	return {
		"lash": {"phase": 1, "weight": _wt("lash", 2.6), "max": 10.0, "cooldown": 1.0},
		"orbs": {"phase": 1, "weight": _wt("orbs", 1.8), "min": 5.0, "cooldown": 1.4},
		"rift": {"phase": 1, "weight": _wt("rift", 1.8), "cooldown": 1.3},
		"well": {"phase": 1, "weight": _wt("well", 1.4), "max": 14.0, "cooldown": 1.6},
		"starfall": {"phase": 2, "weight": _wt("starfall", 1.5), "cooldown": 1.6},
		"blink": {"phase": 2, "weight": _wt("blink", 1.2), "min": 8.0, "cooldown": 0.8},
		"dash": {"phase": 2, "weight": _wt("dash", 1.3), "min": 5.0, "cooldown": 1.4},
		"summon": {"phase": 2, "weight": _wt("summon", 0.8), "cooldown": 2.0, "ok": func() -> bool: return summons.size() < 3},
		"eclipse": {"phase": 3, "weight": _wt("eclipse", 1.6), "cooldown": 2.2},
		"clones": {"phase": 3, "weight": _wt("clones", 1.4), "cooldown": 1.8},
		"blackhole": {"phase": 3, "weight": _wt("blackhole", 1.2), "cooldown": 2.2},
	}


func _strike(action: String, tele: float) -> void:
	_play(action, tele / IMPACT)


func _begin_attack(name: String) -> void:
	_note_attack(name)
	if _target != null:
		_face(_target.global_position, 1.0, 60.0)
	match name:
		"lash":
			_lash(_ground_here(), _fwd(), 0.9)
		"orbs":
			_alt = 2.0
			_play("volley", 0.6 + (4 + phase * 2) * 0.2 + 0.4)
			_attack_data["shots"] = 0
			Audio.play("fireball_cast", center(), 2.0, 0.4)
		"rift":
			_strike("rift", 1.3)
			var targets: Array[Entity] = _players() if phase >= 3 else ([_target] as Array[Entity])
			for p in targets:
				if p == null:
					continue
				_tele("circle:void", p.global_position, _fwd(), Vector3(3.6, 0, 0), 1.3, 36.0, "hit", -6.0)
			Audio.play("portal", center(), 2.0, 0.5)
		"well":
			# A gravity well: everyone near is dragged in, then the centre crushes.
			_alt = 1.5
			_strike("pull", 1.1)
			var c := _ground_here()
			_tele("ring:void", c, _fwd(), Vector3(4.5, 13.0, 0), 1.1, 12.0, "hit", -9.0)
			_tele("circle:void", c, _fwd(), Vector3(4.5, 0, 0), 2.0, 40.0, "hit", 9.0,
				func() -> void:
					_shake_near(c, 0.6)
					_fx_burst(c + Vector3(0, 1.0, 0), false, 1.4))
			Audio.play("portal", center(), 3.0, 0.35)
		"starfall":
			_alt = 7.0
			var total := 10 + phase * 2
			_play("starfall", 0.5 + total * 0.12 + 1.2)
			_attack_data["drops"] = 0
		"blink":
			_play("teleport", 0.9)
			_tele("circle:void", _ground_here(), _fwd(), Vector3(4.0, 0, 0), 0.8, 28.0, "hit", 8.0)
			Audio.play("portal", center(), 2.0, 0.6)
		"dash":
			_alt = 0.4
			var dir := _dir_to(_target)
			var length := clampf(_flat_dist(_target) + 7.0, 10.0, 26.0)
			_attack_data["dir"] = dir
			_attack_data["len"] = length
			_strike("charge", 1.0)
			_tele("line:void", _ground_here(), dir, Vector3(length, 3.6, 0), 1.0, 42.0, "hit", 9.0)
			Audio.play("roar_big", center(), 2.0, 0.6)
		"summon":
			_play("summon", 1.6)
			Audio.play("roar_big", center(), 2.0, 0.5)
		"eclipse":
			_alt = 3.0
			_strike("eclipse", 2.0)
			Audio.play("roar_big", center(), 5.0, 0.45)
			var c := _ground_here()
			_tele("circle:void", c, _fwd(), Vector3(4.0, 0, 0), 1.4, 36.0, "hit", 8.0)
			_tele("ring:void", c, _fwd(), Vector3(7.0, 11.0, 0), 2.0, 36.0, "hit", 6.0)
			_tele("ring:void", c, _fwd(), Vector3(14.0, 19.0, 0), 2.6, 36.0, "hit", 6.0)
			_tele("ring:void", c, _fwd(), Vector3(4.0, 7.0, 0), 3.3, 36.0, "hit", 6.0)
			_tele("ring:void", c, _fwd(), Vector3(11.0, 14.0, 0), 3.3, 36.0, "hit", 6.0)
		"clones":
			# Three reflections stand round the target; each lashes in turn.
			_alt = 2.0
			_strike("special1", 1.2)
			var tp := _target.global_position if _target != null else spawn_point
			var a0 := _rng.randf() * TAU
			for i in 3:
				var a := a0 + TAU * i / 3.0
				var at := _clamp_arena(tp + Vector3(cos(a), 0, sin(a)) * 6.0, 0.95)
				var d := tp - at
				d.y = 0.0
				d = d.normalized() if d.length() > 0.1 else _fwd()
				_fx_burst(_gp(at) + Vector3(0, 3.0, 0), false, 1.1)
				_tele("cone:void", _gp(at), d, Vector3(8.0, 40.0, 0), 1.2 + i * 0.45, 32.0, "hit", 6.0)
			Audio.play("portal", center(), 3.0, 0.45)
		"blackhole":
			# Rises over the centre: everything is drawn in, then hurled out.
			_alt = 6.0
			_strike("special2", 1.4)
			_attack_data["at"] = _clamp_arena(spawn_point, 0.2)
			var c := _gp(_attack_data["at"])
			_tele("circle:void", c, _fwd(), Vector3(16.0, 0, 0), 1.4, 10.0, "hit", -10.0)
			_tele("circle:void", c, _fwd(), Vector3(5.0, 0, 0), 2.6, 46.0, "hit", 12.0,
				func() -> void: _shake_near(c, 0.9))
			_tele("ring:void", c, _fwd(), Vector3(9.0, 15.0, 0), 3.2, 34.0, "hit", 8.0)
			Audio.play("roar_big", center(), 5.0, 0.35)


func _lash(at: Vector3, dir: Vector3, tele: float) -> void:
	_strike("lash", tele)
	_tele("cone:void", at, dir, Vector3(9.0, 70.0, 0), tele, 40.0, "hit", 8.0,
		func() -> void: Audio.play("swing", center(), 4.0, 0.5))


func _update_attack(name: String, t: float, delta: float) -> bool:
	_hover(delta, 2.0)
	if not name in ["dash", "blackhole"]:
		body.velocity.x = lerpf(body.velocity.x, 0.0, 1.0 - exp(-4.0 * delta))
		body.velocity.z = lerpf(body.velocity.z, 0.0, 1.0 - exp(-4.0 * delta))
	match name:
		"lash":
			return t > 1.4
		"orbs":
			var shots: int = _attack_data["shots"]
			var count := 4 + phase * 2
			if shots < count and t > 0.5 + shots * 0.2:
				_attack_data["shots"] = shots + 1
				_orb(shots)
			return t > 0.6 + count * 0.2 + 0.4
		"rift":
			return t > 1.8
		"well":
			return t > 2.4
		"starfall":
			var drops: int = _attack_data["drops"]
			var total := 10 + phase * 2
			if drops < total and t > 0.3 + drops * 0.12:
				_attack_data["drops"] = drops + 1
				var p := _random_player()
				var c := (p.global_position if p != null else spawn_point) + Vector3(_rng.randf_range(-6, 6), 0, _rng.randf_range(-6, 6))
				_tele("circle:star", c, _fwd(), Vector3(2.2, 0, 0), 1.2, 22.0, "fire")
			return t > 0.5 + total * 0.12 + 1.2
		"blink":
			if t > 0.5 and not _attack_data.has("moved") and _target != null:
				_attack_data["moved"] = true
				var a := _rng.randf() * TAU
				_blink_to(_target.global_position + Vector3(cos(a), 0, sin(a)) * 6.0)
				_face(_target.global_position, 1.0, 60.0)
			if t > 0.85 and not _attack_data.has("swung"):
				_attack_data["swung"] = true
				_lash(_ground_here(), _fwd(), 0.9)
			return t > 2.2
		"dash":
			var dir: Vector3 = _attack_data["dir"]
			var length: float = _attack_data["len"]
			if t > 1.0 and t < 1.4:
				body.velocity.x = dir.x * length / 0.4
				body.velocity.z = dir.z * length / 0.4
				yaw = atan2(-dir.x, -dir.z)
			else:
				body.velocity.x = lerpf(body.velocity.x, 0.0, 1.0 - exp(-8.0 * delta))
				body.velocity.z = lerpf(body.velocity.z, 0.0, 1.0 - exp(-8.0 * delta))
			var out := global_position - spawn_point
			out.y = 0.0
			if out.length() > arena_radius * 0.92 and Vector2(body.velocity.x, body.velocity.z).dot(Vector2(out.x, out.z)) > 0.0:
				body.velocity.x = 0.0
				body.velocity.z = 0.0
			return t > 2.0
		"summon":
			if t > 0.9 and not _attack_data.has("done"):
				_attack_data["done"] = true
				_summon("shade", 2 if phase < 3 else 3, 6.0)
			return t > 1.6
		"eclipse":
			return t > 3.6
		"clones":
			return t > 2.6
		"blackhole":
			var at: Vector3 = _attack_data["at"]
			_glide(at, walk_speed * 2.5, delta)
			return t > 3.5
	return true


func _orb(i: int) -> void:
	var w = _w()
	var p := _random_player()
	if w == null or p == null:
		return
	var a := TAU * float(i) / 8.0
	var origin := global_position + Vector3(cos(a) * 2.4, hit_height * 0.85, sin(a) * 2.4)
	var dir := (p.center() - origin).normalized()
	w.spawn_projectile("soul_bolt", origin, dir * 11.0, net_id, Team.MONSTERS, dimension, _dmg(18.0))


func _on_phase_changed(new_phase: int) -> void:
	_play("phase", 2.2)
	Audio.play("roar_big", center(), 5.0, 0.4)
	_shake_near(global_position, 0.7)
	_alt = 3.0
	_tele("ring:void", _ground_here(), _fwd(), Vector3(1.0, 7.0, 0), 1.6, 28.0, "hit", 10.0)
	if new_phase >= 2:
		_summon("shade", 2, 7.0)
	_next_attack = 2.0
