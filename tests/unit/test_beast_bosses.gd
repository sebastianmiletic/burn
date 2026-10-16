extends TestCase
## The beast bosses (Ashvane, Cerberus, Vexhira): their models build and play
## every action, the dragon's wings really fold and spread, and each fight
## uses its signature mechanics (the dragon flies strafing runs and crash
## lands, Cerberus leaps, the Broodmother climbs to the roof and drops) while
## staying inside its arena and only hitting through filled telegraphs.
## Skipped (not failed) when autoloads are missing (see test_boss_sim).


class SimWorld:
	extends RefCounted
	var now := 0.0
	var players: Array = []
	var telegraphs: Array = []
	var hits: Array = []
	var started := false
	var finished := false
	var spawned := 0

	func players_in(_dim: int) -> Array:
		return players.filter(func(p: Node3D) -> bool: return not p.dead)

	func nearest_player(pos: Vector3, _dim: int, max_dist: float) -> Variant:
		for p in players_in(0):
			if p.global_position.distance_to(pos) < max_dist:
				return p
		return null

	func damage(target: Node3D, amount: float, source_id: int, kind := "hit") -> void:
		var dealt: float = target.take_damage(amount, source_id, kind)
		if target.team == 0 and dealt > 0.0:
			hits.append([now, dealt])

	func telegraph(shape: String, _pos: Vector3, _dir: Vector3, _size: Vector3, duration: float, _dim: int) -> void:
		telegraphs.append([now, shape, duration])

	func spawn_projectile(_k: String, _o: Vector3, _v: Vector3, _id: int, _t: int, _d: int, _dmg: float) -> void:
		pass

	func spawn_entity(_kind: String, _pos: Vector3, _dim: int, _data := {}) -> Variant:
		spawned += 1
		return null

	func despawn_entity(_e: Variant) -> void:
		pass

	func boss_started(_b: Variant) -> void:
		started = true

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


func test_models_play_every_action() -> void:
	var tree := _tree()
	if tree == null:
		print("      (test_beast_bosses skipped: autoloads are not running yet in this runner)")
		return
	var arena := Node3D.new()
	tree.root.add_child(arena)
	var actions := ["bite", "claw", "tail", "gust", "roar", "breath", "takeoff", "fly", "attack", "dive", "slam", "land",
		"hit", "pounce", "lunge", "howl", "summon", "shoot", "cast"]
	for kind: String in ["dragon", "cerberus", "broodmother"]:
		var m := Models.create(kind)
		m.lod_enabled = false
		arena.add_child(m)
		var t0 := Time.get_ticks_usec()
		var frames := 0
		for a: String in actions:
			m.play(a)
			for i in 8:
				m._process(1.0 / 30.0)
				frames += 1
		var per_frame := (Time.get_ticks_usec() - t0) / 1000.0 / frames
		m.set_dead(true)
		for i in 60:
			m._process(0.2)
		check(m.is_dissolved(), "%s dissolves after death" % kind)
		print("      %-12s %d frames, %.3f ms per animated frame (headless)" % [kind, frames, per_frame])
	arena.queue_free()


func test_loading_leviathan_animates_without_gameplay_particles() -> void:
	var tree := _tree()
	if tree == null:
		return
	var scene := Node3D.new()
	tree.root.add_child(scene)
	var m := Models.create("leviathan") as LeviathanModel
	m.particles_enabled = false
	m.lod_enabled = false
	m.water_y = 0.0
	scene.add_child(m)
	for action: String in ["roar", "bite", "dive", "slam"]:
		m.play(action)
		for i in 60:
			m.position.x += 0.1
			m._process(1.0 / 30.0)
	check(m.find_children("*", "GPUParticles3D", true, false).is_empty(), "film model creates no gameplay emitters")
	check(m.head != null and m.chain != null, "the real animated model is preserved")
	scene.free()


## The wings are skinned to a skeleton: folded on the ground, spread in the air.
func test_dragon_wings_fold_and_spread() -> void:
	var tree := _tree()
	if tree == null:
		return
	var arena := Node3D.new()
	tree.root.add_child(arena)
	var d := Models.create("dragon") as DragonModel
	d.lod_enabled = false
	arena.add_child(d)
	for i in 90:
		d._process(1.0 / 30.0)
	var folded := _wingtip_span(d)
	d.flying = true
	d.grounded = false
	for i in 90:
		d._process(1.0 / 30.0)
	var spread := _wingtip_span(d)
	check(spread > 20.0, "spread wingspan is huge (%.1f m)" % spread)
	check(folded < spread * 0.55, "wings fold against the body on the ground (%.1f m folded vs %.1f m spread)" % [folded, spread])
	arena.queue_free()


## Distance between the two second-finger tips (bone 5 of each wing skeleton).
func _wingtip_span(d: DragonModel) -> float:
	var tips: Array[Vector3] = []
	for w: Dictionary in d.wings:
		var sk: Skeleton3D = w["skel"]
		var pose := sk.get_bone_global_pose(5)
		tips.append(sk.global_transform * (pose * Vector3(float(w["side"]) * 6.9 * 0.8, 0, 6.9 * 0.6)))
	return tips[0].distance_to(tips[1])


func _fight(kind: String, watch: Callable) -> Dictionary:
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
	var boss: Node3D = Boss.create(kind)
	boss.sim_world = sim
	boss.body.gravity = 0.0
	arena.add_child(boss)
	boss.global_position = Vector3.ZERO
	var dt := 1.0 / 30.0
	var acc := 0.0
	var stats := {"max_r": 0.0, "phase": 1}
	var move := 0.0
	var spots := [Vector3(0, 0, 9), Vector3(18, 0, 6), Vector3(-6, 0, -17), Vector3(-16, 0, 10), Vector3(4, 0, 20)]
	var spot := 0
	while sim.now < 400.0 and not boss.dead:
		sim.now += dt
		acc += dt
		# The player kites around the arena now and then.
		move += dt
		if move > 9.0:
			move = 0.0
			spot = (spot + 1) % spots.size()
			player.global_position = spots[spot]
		boss.server_tick(dt)
		watch.call(boss, stats, dt)
		stats["max_r"] = maxf(float(stats["max_r"]), Vector2(boss.global_position.x, boss.global_position.z).length())
		stats["phase"] = maxi(int(stats["phase"]), boss.phase)
		if acc >= 0.5 and boss.engaged:
			acc = 0.0
			boss.take_damage(boss.max_health * 0.006, 7, "hit")
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
	stats["unfair"] = unfair
	stats["dead"] = boss.dead
	stats["hits"] = sim.hits.size()
	stats["spawned"] = sim.spawned
	stats["arena_r"] = float(boss.get("arena_r"))
	arena.queue_free()
	return stats


func test_dragon_flies_and_crash_lands() -> void:
	if _tree() == null:
		return
	var s := _fight("dragon", func(b: Node3D, st: Dictionary, dt: float) -> void:
		if b.flying:
			st["air"] = float(st.get("air", 0.0)) + dt
			st["alt"] = maxf(float(st.get("alt", 0.0)), b.global_position.y)
		if b._attack == "dive" and b._attack_data.get("stage", "") == "stagger":
			st["staggered"] = true)
	check(bool(s["dead"]), "dragon died")
	check_eq(int(s["phase"]), 3, "dragon reached phase 3")
	check(float(s.get("air", 0.0)) > 8.0, "dragon took to the air (%.0fs airborne)" % float(s.get("air", 0.0)))
	check(float(s.get("alt", 0.0)) > 6.0, "dragon flew high (%.1f m)" % float(s.get("alt", 0.0)))
	check(bool(s.get("staggered", false)), "dive bomb ends in a staggered crash landing")
	check_eq(int(s["unfair"]), 0, "dragon hits without a filled telegraph")
	check(float(s["max_r"]) < float(s["arena_r"]) + 2.0, "dragon stays in its arena (%.1f of %.1f m)" % [float(s["max_r"]), float(s["arena_r"])])


func test_cerberus_leaps() -> void:
	if _tree() == null:
		return
	var s := _fight("cerberus", func(b: Node3D, st: Dictionary, _dt: float) -> void:
		if b.flying:
			st["leapt"] = true)
	check(bool(s["dead"]), "cerberus died")
	check_eq(int(s["phase"]), 3, "cerberus reached phase 3")
	check(bool(s.get("leapt", false)), "cerberus pounced")
	check(int(s["spawned"]) > 0, "cerberus called its hellhounds")
	check_eq(int(s["unfair"]), 0, "cerberus hits without a filled telegraph")


func test_broodmother_climbs_and_drops() -> void:
	if _tree() == null:
		return
	var s := _fight("broodmother", func(b: Node3D, st: Dictionary, _dt: float) -> void:
		if b.flying:
			st["top"] = maxf(float(st.get("top", 0.0)), b.global_position.y))
	check(bool(s["dead"]), "broodmother died")
	check(float(s.get("top", 0.0)) > 6.0, "broodmother climbed to the roof (%.1f m)" % float(s.get("top", 0.0)))
	check(int(s["spawned"]) > 0, "broodmother hatched her brood")
	check_eq(int(s["unfair"]), 0, "broodmother hits without a filled telegraph")
