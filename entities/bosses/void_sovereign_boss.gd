class_name VoidSovereignBoss
extends Boss
## The Void Sovereign, who waits on the Crown of the Ryft: a towering shape
## cut out of the night sky, a regal torso of starlight above a trailing
## vortex of void, crowned by orbiting crystal shards.
##   Phase 1: void lash (a wide cone of tendrils), star orbs (homing bolts),
##            rift (a marked circle under its target that implodes)
##   Phase 2: + starfall (many small marked impacts), + blink (it folds space
##            and reappears beside a player, lashing), + calls shades
##   Phase 3: + eclipse (the whole crown erupts in rings with safe bands),
##            rifts open under everyone

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
	body.half_extents = Vector3(1.2, 3.0, 1.2)
	loot = [["potion_greater", 1.0, 4, 6], ["amethyst", 1.0, 8, 14], ["mithril_ore", 1.0, 6, 10], ["sapphire", 1.0, 3, 6],
		["gold_ore", 1.0, 14, 20], ["ryftwood", 1.0, 6, 10]]


func _ready() -> void:
	super._ready()
	if not ItemDB.exists(relic):
		relic = ""


func _attacks() -> Dictionary:
	return {
		"lash": {"phase": 1, "weight": 3.0, "max": 9.0, "cooldown": 1.0},
		"orbs": {"phase": 1, "weight": 2.0, "min": 5.0, "cooldown": 1.4},
		"rift": {"phase": 1, "weight": 1.8, "cooldown": 1.3},
		"starfall": {"phase": 2, "weight": 1.6, "cooldown": 1.6},
		"blink": {"phase": 2, "weight": 1.2, "min": 9.0, "cooldown": 0.8},
		"summon": {"phase": 2, "weight": 0.8, "cooldown": 2.0, "ok": func() -> bool: return summons.size() < 3},
		"eclipse": {"phase": 3, "weight": 1.8, "cooldown": 2.2},
	}


func _begin_attack(name: String) -> void:
	if _target != null:
		_face(_target.global_position, 1.0, 60.0)
	match name:
		"lash":
			_lash()
		"orbs":
			_play("cast", 1.8)
			_attack_data["shots"] = 0
			Audio.play("fireball_cast", center(), 2.0, 0.4)
		"rift":
			_play("cast", 1.4)
			var targets: Array[Entity] = _players() if phase >= 3 else ([_target] as Array[Entity])
			for p in targets:
				if p == null:
					continue
				var c := p.global_position
				_tele("circle:void", c, _fwd(), Vector3(3.6, 0, 0), 1.3, 36.0, "hit", -6.0)
			Audio.play("portal", center(), 2.0, 0.5)
		"starfall":
			_play("summon", 2.2)
			_attack_data["drops"] = 0
		"blink":
			_play("teleport", 0.9)
			_tele("circle:void", global_position, _fwd(), Vector3(4.0, 0, 0), 0.8, 28.0, "hit", 8.0)
			Audio.play("portal", center(), 2.0, 0.6)
		"summon":
			_play("summon", 1.6)
			Audio.play("roar_big", center(), 2.0, 0.5)
		"eclipse":
			_play("summon", 3.4)
			Audio.play("roar_big", center(), 5.0, 0.45)
			var c := global_position
			_tele("circle:void", c, _fwd(), Vector3(4.0, 0, 0), 1.4, 36.0, "hit", 8.0)
			_tele("ring:void", c, _fwd(), Vector3(7.0, 11.0, 0), 2.0, 36.0, "hit", 6.0)
			_tele("ring:void", c, _fwd(), Vector3(14.0, 19.0, 0), 2.6, 36.0, "hit", 6.0)
			_tele("ring:void", c, _fwd(), Vector3(4.0, 7.0, 0), 3.3, 36.0, "hit", 6.0)
			_tele("ring:void", c, _fwd(), Vector3(11.0, 14.0, 0), 3.3, 36.0, "hit", 6.0)


func _lash() -> void:
	_play("sweep", 1.3)
	_tele("cone:void", global_position, _fwd(), Vector3(9.0, 70.0, 0), 0.9, 40.0, "hit", 8.0,
		func() -> void: Audio.play("swing", center(), 4.0, 0.5))


func _update_attack(name: String, t: float, _delta: float) -> bool:
	match name:
		"lash":
			return t > 1.3
		"orbs":
			var shots: int = _attack_data["shots"]
			var count := 4 + phase * 2
			if shots < count and t > 0.5 + shots * 0.2:
				_attack_data["shots"] = shots + 1
				_orb(shots)
			return t > 0.6 + count * 0.2 + 0.4
		"rift":
			return t > 1.7
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
				var dest := _target.global_position + Vector3(cos(a), 0, sin(a)) * 6.0
				var from_home := dest - spawn_point
				from_home.y = 0.0
				if from_home.length() > arena_radius:
					dest = spawn_point + from_home.normalized() * arena_radius + Vector3(0, dest.y - spawn_point.y, 0)
				global_position = Vector3(dest.x, maxf(dest.y, _target.global_position.y), dest.z)
				body.velocity = Vector3.ZERO
				_face(_target.global_position, 1.0, 60.0)
				_fx_burst(center(), false, 1.4)
			if t > 0.85 and not _attack_data.has("swung"):
				_attack_data["swung"] = true
				_lash()
			return t > 2.2
		"summon":
			if t > 0.9 and not _attack_data.has("done"):
				_attack_data["done"] = true
				_summon("shade", 2 if phase < 3 else 3, 6.0)
			return t > 1.6
		"eclipse":
			return t > 3.6
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


## Glides, never quite walking; keeps lash range.
func _approach(delta: float) -> void:
	if _target == null:
		_move_towards(spawn_point, walk_speed, delta, 2.0)
		return
	var d := _flat_dist(_target)
	if d > melee_range:
		_move_towards(_target.global_position, walk_speed * (1.4 if d > melee_range * 2.5 else 1.0), delta, melee_range * 0.8)
	else:
		_move_towards(global_position, 0.0, delta, 0.5)
	_face(_target.global_position, delta, 3.0)


func _on_phase_changed(new_phase: int) -> void:
	_play("roar", 2.2)
	Audio.play("roar_big", center(), 5.0, 0.4)
	_shake_near(global_position, 0.7)
	_tele("ring:void", global_position, _fwd(), Vector3(1.0, 7.0, 0), 1.6, 28.0, "hit", 10.0)
	if new_phase >= 2:
		_summon("shade", 2, 7.0)
	_next_attack = 2.0
