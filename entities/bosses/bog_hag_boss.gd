class_name BogHagBoss
extends Boss
## Old Mother Mire, the bog witch of Hagsfen, deep in Blackmarsh.
##   Phase 1: staff swipe (cone), hex bolts (slow homing curses), grasping
##            roots (marked circles erupt under every player)
##   Phase 2: + blink (vanishes in a puff of bog gas and reappears elsewhere in
##            her clearing, the old spot bursts), + calls bog lurkers and
##            ghouls out of the pools
##   Phase 3: + swamp gas (rings with safe bands), + mire rain (many small
##            marked bursts), blinks more often
## She is frail: low health for a boss, but she never stands still.

const CLEARING := 15.0


func _init() -> void:
	kind = "bog_hag"
	display_name = "Old Mother Mire"
	relic = "hag_eye"
	xp_value = 900
	base_health = 2600.0
	walk_speed = 2.8
	melee_range = 3.4
	aggro_radius = 20.0
	arena_radius = 26.0
	enrage_time = 420.0
	hit_radius = 0.8
	hit_height = 2.6
	body.half_extents = Vector3(0.45, 1.3, 0.45)
	loot = [["potion_greater", 1.0, 2, 4], ["potion_health", 1.0, 3, 5], ["amethyst", 1.0, 2, 5], ["silver_ore", 1.0, 4, 8],
		["gold_ore", 1.0, 4, 8], ["swamp_herb", 1.0, 4, 8], ["frost_shard", 0.5, 1, 2]]


func _ready() -> void:
	super._ready()
	if not ItemDB.exists(relic):
		relic = ""


func _attacks() -> Dictionary:
	return {
		"staff": {"phase": 1, "weight": 3.0, "max": 4.5, "cooldown": 0.9},
		"hex": {"phase": 1, "weight": 2.2, "min": 4.0, "cooldown": 1.3},
		"roots": {"phase": 1, "weight": 2.0, "cooldown": 1.2},
		"blink": {"phase": 2, "weight": 1.6, "cooldown": 0.6},
		"summon": {"phase": 2, "weight": 1.0, "cooldown": 1.5, "ok": func() -> bool: return summons.size() < 4},
		"gas": {"phase": 3, "weight": 1.4, "cooldown": 1.4},
		"rain": {"phase": 3, "weight": 1.4, "cooldown": 1.4},
	}


func _begin_attack(name: String) -> void:
	if _target != null:
		_face(_target.global_position, 1.0, 60.0)
	match name:
		"staff":
			_play("attack2", 0.9)
			_tele("cone", global_position + _fwd() * 0.5, _fwd(), Vector3(4.2, 55.0, 0), 0.55, 26.0, "hit", 7.0)
		"hex":
			_play("cast", 1.2)
			_attack_data["shots"] = 0
			Audio.play("fireball_cast", center(), 0.0, 0.6)
		"roots":
			_play("summon", 1.3)
			for p in _players():
				var c := p.global_position
				_tele("circle:roots", c, _fwd(), Vector3(2.6, 0, 0), 1.25, 28.0, "hit", 4.0)
		"blink":
			_play("cast", 0.6)
			var old := global_position
			_tele("circle:hex", old, _fwd(), Vector3(3.5, 0, 0), 0.7, 30.0, "hit", 9.0)
			var a := _rng.randf() * TAU
			var dest := spawn_point + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(4.0, CLEARING - 3.0)
			_attack_data["dest"] = dest
		"summon":
			_play("summon", 1.6)
			Audio.play("growl", center(), 2.0, 0.6)
		"gas":
			_play("summon", 1.4)
			var c := global_position
			c.y = spawn_point.y
			var bands := [Vector2(2.5, 6.0), Vector2(9.0, 13.0)] if _rng.randf() < 0.5 else [Vector2(0.0, 3.5), Vector2(6.5, 10.0), Vector2(13.0, 17.0)]
			for b: Vector2 in bands:
				_tele("ring:hex", c, _fwd(), Vector3(b.x, b.y, 0), 1.6, 30.0, "hit", 6.0)
		"rain":
			_play("cast", 2.0)
			_attack_data["drops"] = 0


func _update_attack(name: String, t: float, delta: float) -> bool:
	match name:
		"staff":
			return t > 1.0
		"hex":
			var shots: int = _attack_data["shots"]
			var total := 2 + phase
			if shots < total and t > 0.5 + shots * 0.28:
				_attack_data["shots"] = shots + 1
				_hex_bolt()
			return t > 0.8 + total * 0.28
		"roots":
			return t > 1.5
		"blink":
			if t > 0.45 and not _attack_data.has("moved"):
				_attack_data["moved"] = true
				global_position = _attack_data["dest"]
				body.velocity = Vector3.ZERO
				_fx_burst(global_position + Vector3(0, 1.0, 0), false, 0.8)
				Audio.play("portal", global_position, -2.0, 1.6)
			return t > 0.9
		"summon":
			if t > 0.9 and not _attack_data.has("done"):
				_attack_data["done"] = true
				_summon("bog_lurker", 1 if phase < 3 else 2, 6.0)
				_summon("ghoul", 1, 4.0)
			return t > 1.7
		"gas":
			return t > 1.9
		"rain":
			var drops: int = _attack_data["drops"]
			if drops < 9 and t > 0.3 + drops * 0.16:
				_attack_data["drops"] = drops + 1
				var p := _random_player()
				var c := (p.global_position if p != null else spawn_point) + Vector3(_rng.randf_range(-4, 4), 0, _rng.randf_range(-4, 4))
				_tele("circle:mud", c, _fwd(), Vector3(2.2, 0, 0), 1.0, 22.0)
			return t > 2.4
	return true


func _hex_bolt() -> void:
	var w = _w()
	var p := _random_player()
	if w == null or p == null:
		return
	var origin := global_position + Vector3(0, 2.4, 0) + _fwd() * 0.6
	var dir := (p.center() - origin).normalized()
	dir = (dir + Vector3(_rng.randf_range(-0.3, 0.3), 0.15, _rng.randf_range(-0.3, 0.3))).normalized()
	w.spawn_projectile("soul_bolt", origin, dir * 9.0, net_id, Team.MONSTERS, dimension, _dmg(20.0))


## She keeps her distance and drifts around her clearing.
func _approach(delta: float) -> void:
	if _target == null:
		_move_towards(spawn_point, walk_speed, delta, 2.0)
		return
	var d := _flat_dist(_target)
	var home := Vector2(global_position.x - spawn_point.x, global_position.z - spawn_point.z).length()
	if d < 3.0 and home < CLEARING - 2.0:
		var away := global_position + (global_position - _target.global_position).normalized() * 4.0
		_move_towards(away, walk_speed * 1.1, delta, 0.5)
	elif d > 9.0:
		_move_towards(_target.global_position, walk_speed, delta, 3.0)
	else:
		_move_towards(global_position, 0.0, delta, 0.5)
	_face(_target.global_position, delta, 5.0)


func _on_phase_changed(_new_phase: int) -> void:
	_play("roar", 1.4)
	Audio.play("imp_screech", center(), 4.0, 0.5)
	_shake_near(global_position, 0.3)
	_next_attack = 0.8
	if _attack == "":
		_attack = "blink"
		_attack_t = 0.0
		_attack_data = {}
		_begin_attack("blink")
