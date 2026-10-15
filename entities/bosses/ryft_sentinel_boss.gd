class_name RyftSentinelBoss
extends Boss
## The Prism Sentinel, keeper of the Broken Observatory on Ryft Island: a
## floating crystal construct held together by bronze astrolabe rings, with a
## burning prism heart. It never touches the ground and turns slowly, like an
## instrument tracking a star.
##   Phase 1: crystal lance (a line at its target), shard nova (two rings, the
##            outer one later), prism slam (its fists crash down in front)
##   Phase 2: + sweeping prism beam (a fan of lines that fill one after
##            another), + shard rain (marked circles under everyone)
##   Phase 3: + constellation (a star pattern of circles around it, then the
##            centre), the heart is exposed and everything comes faster

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
	body.half_extents = Vector3(1.3, 2.6, 1.3)
	loot = [["potion_greater", 1.0, 3, 5], ["amethyst", 1.0, 6, 10], ["mithril_ore", 1.0, 4, 8], ["sapphire", 0.8, 2, 4],
		["ryftwood", 1.0, 4, 8], ["gold_ore", 1.0, 8, 12]]


func _ready() -> void:
	super._ready()
	if not ItemDB.exists(relic):
		relic = ""


func _attacks() -> Dictionary:
	return {
		"lance": {"phase": 1, "weight": 2.6, "min": 3.0, "cooldown": 1.2},
		"nova": {"phase": 1, "weight": 1.6, "max": 11.0, "cooldown": 1.5},
		"slam": {"phase": 1, "weight": 2.4, "max": 9.0, "cooldown": 1.3},
		"beam": {"phase": 2, "weight": 1.8, "cooldown": 1.8},
		"rain": {"phase": 2, "weight": 1.6, "cooldown": 1.4},
		"constellation": {"phase": 3, "weight": 1.6, "cooldown": 2.0},
	}


func _begin_attack(name: String) -> void:
	if _target != null:
		_face(_target.global_position, 1.0, 60.0)
	match name:
		"lance":
			_play("cast", 1.4)
			var dir := _dir_to(_target)
			_attack_data["dir"] = dir
			_tele("line:crystal", global_position, dir, Vector3(20.0, 2.6, 0), 1.1, 38.0, "hit", 5.0)
			Audio.play("portal", center(), 0.0, 1.8)
		"nova":
			_play("summon", 1.8)
			_tele("ring:crystal", global_position, _fwd(), Vector3(2.0, 8.0, 0), 1.2, 34.0, "hit", 7.0)
			_tele("ring:crystal", global_position, _fwd(), Vector3(10.0, 15.0, 0), 2.0, 30.0, "hit", 5.0)
			Audio.play("roar_big", center(), 0.0, 1.6)
		"slam":
			_play("slam", 1.5)
			_tele("circle:crystal", global_position + _fwd() * 4.0, _fwd(), Vector3(4.6, 0, 0), 1.1, 44.0, "hit", 7.0,
				func() -> void:
					_shake_near(global_position, 0.6)
					Audio.play("stomp", global_position + _fwd() * 4.0, 4.0, 0.7))
		"beam":
			_play("cast", 2.8)
			# A sweeping beam: lines fanning across, each fills before it fires.
			var base := atan2(-_fwd().x, -_fwd().z)
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			var count := 7 if phase < 3 else 9
			for i in count:
				var a := base + side * deg_to_rad(-60.0 + 120.0 * float(i) / (count - 1))
				var d := Vector3(-sin(a), 0, -cos(a))
				_tele("line:prism", global_position, d, Vector3(22.0, 2.2, 0), 1.0 + i * 0.22, 30.0, "fire", 3.0)
			Audio.play("fireball_cast", center(), 2.0, 0.5)
		"rain":
			_play("cast", 1.6)
			_attack_data["drops"] = 0
		"constellation":
			_play("summon", 2.6)
			var r := 9.0
			for i in 5:
				var a := TAU * i / 5.0 + _rng.randf() * 0.3
				_tele("circle:crystal", global_position + Vector3(cos(a), 0, sin(a)) * r, _fwd(), Vector3(4.0, 0, 0), 1.3 + i * 0.12, 34.0, "hit", 4.0)
			_tele("circle:prism", global_position, _fwd(), Vector3(5.5, 0, 0), 2.4, 40.0, "fire", 9.0,
				func() -> void: _shake_near(global_position, 0.7))
			Audio.play("roar_big", center(), 3.0, 1.4)


func _update_attack(name: String, t: float, _delta: float) -> bool:
	match name:
		"lance":
			return t > 1.6
		"nova":
			return t > 2.3
		"slam":
			return t > 1.6
		"beam":
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
		"constellation":
			return t > 2.8
	return true


func _dir_to(e: Entity) -> Vector3:
	if e == null:
		return _fwd()
	var d := e.global_position - global_position
	d.y = 0.0
	return d.normalized() if d.length() > 0.1 else _fwd()


## It drifts rather than walks, and keeps a little distance for its lances.
func _approach(delta: float) -> void:
	if _target == null:
		_move_towards(spawn_point, walk_speed, delta, 2.0)
		return
	var d := _flat_dist(_target)
	if d > melee_range + 2.0:
		_move_towards(_target.global_position, walk_speed, delta, melee_range)
	else:
		_move_towards(global_position, 0.0, delta, 0.5)
	_face(_target.global_position, delta, 2.2)


func _on_phase_changed(new_phase: int) -> void:
	_play("roar", 2.0)
	Audio.play("roar_big", center(), 4.0, 1.5)
	_shake_near(global_position, 0.5)
	# The construct sheds its shell: a burst ring around it, clearly marked.
	_tele("ring:crystal", global_position, _fwd(), Vector3(1.5, 6.0 + new_phase, 0), 1.5, 26.0, "hit", 9.0)
	_next_attack = 2.0
