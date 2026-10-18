extends TestCase
## The beast bosses' full movesets: Ashvane, Cerberus and the Broodmother use
## every attack across their phases, every hit is telegraphed, they move
## around their arenas, Ashvane spends a real share of the fight on the wing
## and never leaves its air volume, and every new animation poses the model.
## Skipped (not failed) when autoloads are missing (see test_boss_sim).


class SimWorld:
	extends RefCounted
	var now := 0.0
	var players: Array = []
	var telegraphs: Array = []  # [time, shape, duration]
	var hits: Array = []
	var spawned := 0
	var projectiles := 0
	var finished := false

	func players_in(_dim: int) -> Array:
		return players.filter(func(p: Node3D) -> bool: return not p.dead)

	func nearest_player(pos: Vector3, _dim: int, max_dist: float) -> Variant:
		var best: Variant = null
		var best_d := max_dist
		for p in players_in(0):
			var d: float = p.global_position.distance_to(pos)
			if d < best_d:
				best_d = d
				best = p
		return best

	func damage(target: Node3D, amount: float, source_id: int, kind := "hit") -> void:
		var dealt: float = target.take_damage(amount, source_id, kind)
		if target.team == 0 and dealt > 0.0:
			hits.append([now, dealt])

	func telegraph(shape: String, _pos: Vector3, _dir: Vector3, _size: Vector3, duration: float, _dim: int) -> void:
		telegraphs.append([now, shape, duration])

	func spawn_projectile(_k: String, _o: Vector3, _v: Vector3, _id: int, _t: int, _d: int, _dmg: float) -> void:
		projectiles += 1

	func spawn_entity(_kind: String, _pos: Vector3, _dim: int, _data := {}) -> Variant:
		spawned += 1
		return null

	func despawn_entity(_e: Variant) -> void:
		pass

	func boss_started(_b: Variant) -> void:
		pass

	func boss_finished(_b: Variant) -> void:
		finished = true

	func boss_reset(_b: Variant) -> void:
		pass

	func shake(_s: float) -> void:
		pass


func _tree() -> SceneTree:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root.get_node_or_null("Events") == null or tree.root.get_node_or_null("Audio") == null:
		return null
	return tree


## A slow fight (so every phase lasts) with the player kiting round the arena,
## sometimes behind the boss. Records attacks, movement and flight.
func _fight(kind: String, id := 0) -> Dictionary:
	var tree := _tree()
	var sim := SimWorld.new()
	var arena := Node3D.new()
	tree.root.add_child(arena)
	var entity_script: GDScript = load("res://entities/entity.gd")
	var player: Node3D = entity_script.new()
	player.team = 0
	player.net_id = 7
	player.max_health = 1e9
	player.health = 1e9
	player.hit_radius = 0.4
	player.hit_height = 1.8
	arena.add_child(player)
	player.global_position = Vector3(0, 0, 9)
	sim.players.append(player)
	var boss: Boss = Boss.create(kind)
	boss.net_id = id
	boss.sim_world = sim
	boss.body.gravity = 0.0
	arena.add_child(boss)
	boss.global_position = Vector3.ZERO
	var dt := 1.0 / 30.0
	var acc := 0.0
	var used := {}
	var path := 0.0
	var last := boss.global_position
	var air := 0.0
	var outside := 0
	var max_alt := 0.0
	var max_phase := 1
	var move := 0.0
	var spots := [Vector3(0, 0, 9), Vector3(16, 0, 6), Vector3(-6, 0, -15), Vector3(-14, 0, 10), Vector3(4, 0, 18), Vector3(0, 0, 3)]
	var spot := 0
	while sim.now < 500.0 and not boss.dead:
		sim.now += dt
		acc += dt
		move += dt
		if move > 7.0:
			move = 0.0
			spot = (spot + 1) % spots.size()
			player.global_position = spots[spot]
			# Now and then the player slips round behind it.
			if spot % 2 == 1:
				player.global_position = boss.global_position - boss._fwd() * 6.0
				player.global_position.y = 0.0
		boss.server_tick(dt)
		if boss._attack != "":
			used[boss._attack] = true
		path += Vector2(boss.global_position.x - last.x, boss.global_position.z - last.z).length()
		last = boss.global_position
		max_phase = maxi(max_phase, boss.phase)
		if boss.flying and kind == "dragon":
			air += dt
			max_alt = maxf(max_alt, boss.global_position.y)
			var flat := Vector2(boss.global_position.x, boss.global_position.z).length()
			if flat > boss.arena_radius or boss.global_position.y > boss.air_ceiling + 0.01 or boss.global_position.y < -0.01:
				outside += 1
		if acc >= 0.5 and boss.engaged:
			acc = 0.0
			boss.take_damage(boss.max_health * 0.003, 7, "hit")
	var unfair := 0
	for h: Array in sim.hits:
		var ok := false
		for t: Array in sim.telegraphs:
			var end: float = t[0] + t[2]
			if end <= h[0] + 0.001 and h[0] - end < 3.0:
				ok = true
				break
		if not ok:
			unfair += 1
	var all: Array = boss._attacks().keys()
	var missing: Array = all.filter(func(a: String) -> bool: return not used.has(a))
	var out := {"dead": boss.dead, "finished": sim.finished, "phase": max_phase, "missing": missing, "count": all.size(),
		"unfair": unfair, "hits": sim.hits.size(), "path": path, "air": air, "fight": sim.now, "outside": outside,
		"alt": max_alt, "telegraphs": sim.telegraphs.size()}
	print("      %-12s attacks %d (missing %s)  hits %d  telegraphs %d  path %.0fm  air %.0fs of %.0fs  alt %.1f" % [
		kind, all.size(), str(missing), sim.hits.size(), sim.telegraphs.size(), path, air, sim.now, max_alt])
	arena.queue_free()
	return out


## Two fights (different rolls); every attack must turn up in at least one.
func _fights(kind: String) -> Dictionary:
	var a := _fight(kind, 0)
	var b := _fight(kind, 31)
	a["missing"] = (a["missing"] as Array).filter(func(x: String) -> bool: return (b["missing"] as Array).has(x))
	for k: String in ["unfair", "outside"]:
		a[k] = int(a[k]) + int(b[k])
	for k: String in ["dead", "finished"]:
		a[k] = bool(a[k]) and bool(b[k])
	a["phase"] = mini(int(a["phase"]), int(b["phase"]))
	a["path"] = minf(float(a["path"]), float(b["path"]))
	a["air"] = float(a["air"]) + float(b["air"])
	a["fight"] = float(a["fight"]) + float(b["fight"])
	a["alt"] = minf(float(a["alt"]), float(b["alt"]))
	return a


func _check_fight(kind: String, s: Dictionary, min_attacks: int) -> void:
	check(bool(s["dead"]) and bool(s["finished"]), "%s died and reported it" % kind)
	check_eq(int(s["phase"]), 3, "%s reached phase 3" % kind)
	check(int(s["count"]) >= min_attacks, "%s has a wide moveset (%d attacks)" % [kind, int(s["count"])])
	check((s["missing"] as Array).is_empty(), "%s used every attack (missing %s)" % [kind, str(s["missing"])])
	check(int(s["hits"]) > 0, "%s landed hits" % kind)
	check_eq(int(s["unfair"]), 0, "%s hits without a filled telegraph" % kind)
	check(float(s["path"]) > 80.0, "%s moves around its arena (%.0f m)" % [kind, float(s["path"])])


func test_dragon_full_moveset_and_flight() -> void:
	if _tree() == null:
		print("      (test_boss_moves_beast skipped: autoloads are not running yet in this runner)")
		return
	var s := _fights("dragon")
	_check_fight("dragon", s, 12)
	check(float(s["air"]) > float(s["fight"]) * 0.2, "Ashvane spends a real share of the fight on the wing (%.0fs of %.0fs)" % [float(s["air"]), float(s["fight"])])
	check(float(s["alt"]) > 8.0, "Ashvane climbs high (%.1f m)" % float(s["alt"]))
	check_eq(int(s["outside"]), 0, "Ashvane never leaves its air volume")


func test_cerberus_full_moveset() -> void:
	if _tree() == null:
		return
	_check_fight("cerberus", _fights("cerberus"), 10)


func test_broodmother_full_moveset() -> void:
	if _tree() == null:
		return
	_check_fight("broodmother", _fights("broodmother"), 10)


## Every new animation actually moves the model (not a silent no-op).
func test_new_animations_pose_the_models() -> void:
	var tree := _tree()
	if tree == null:
		return
	var arena := Node3D.new()
	tree.root.add_child(arena)
	var sets := {
		"dragon": ["charge", "stomp", "rake", "hover", "phase", "takeoff", "land", "dive", "hit"],
		"cerberus": ["rake", "kick", "charge", "spit", "combo", "phase", "pounce", "hit"],
		"broodmother": ["web", "sweep", "spit", "dodge", "phase", "glide", "lunge", "hit"],
	}
	for kind: String in sets:
		for a: String in sets[kind]:
			check(Boss.ACTIONS.has(a), "%s action %s replicates (in Boss.ACTIONS)" % [kind, a])
			var m := Models.create(kind)
			m.lod_enabled = false
			arena.add_child(m)
			if m is DragonModel and a in ["rake", "hover"]:
				(m as DragonModel).flying = true
			for i in 20:
				m._process(1.0 / 30.0)
			var before := _pose_sig(m)
			m.play(a)
			var moved := 0.0
			for i in 30:
				m._process(1.0 / 30.0)
				moved = maxf(moved, _pose_diff(before, _pose_sig(m)))
			check(moved > 0.05, "%s animates %s (%.2f)" % [kind, a, moved])
			m.queue_free()
	arena.queue_free()


func _pose_sig(m: Node) -> Array:
	var out: Array = []
	if m is DragonModel:
		out.append((m as DragonModel).head.global_position)
		for l: Dictionary in (m as DragonModel).legs:
			out.append((l["foot"] as Node3D).global_position)
	elif m is CerberusModel:
		for h in (m as CerberusModel).heads:
			out.append(h.global_position)
		for l: Dictionary in (m as CerberusModel).legs:
			out.append((l["foot"] as Node3D).global_position)
	elif m is BroodmotherModel:
		out.append((m as BroodmotherModel).body.global_position)
		out.append((m as BroodmotherModel).body.global_rotation)
		out.append((m as BroodmotherModel).fangs[0].rotation)
	return out


func _pose_diff(a: Array, b: Array) -> float:
	var d := 0.0
	for i in mini(a.size(), b.size()):
		d = maxf(d, (a[i] as Vector3).distance_to(b[i] as Vector3))
	return d
