extends TestCase
## Headless fight simulation for every boss: a stand-in world (duck-typed via
## Boss.sim_world) and one stationary player who keeps hitting the boss.
## Checks: the boss engages, passes through all three phases, every hit on the
## player was announced by a telegraph that had fully filled, and it dies.
##
## Boss scripts use autoloads (Events, Audio), which only exist once the
## SceneTree is running; when a runner executes tests earlier (inside
## SceneTree._init) this test reports itself skipped instead of failing.


class SimWorld:
	extends RefCounted
	var now := 0.0
	var players: Array = []
	var telegraphs: Array = []  # [time, shape, duration]
	var hits: Array = []        # [time, amount]
	var started := false
	var finished := false
	var spawned := 0
	var projectiles := 0

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

	func spawn_projectile(_kind: String, _origin: Vector3, _velocity: Vector3, _owner_id: int, _team: int, _dim: int, _damage: float) -> void:
		projectiles += 1

	func spawn_entity(_kind: String, _pos: Vector3, _dim: int, _data := {}) -> Variant:
		spawned += 1
		return null

	func despawn_entity(_e: Variant) -> void:
		pass

	func boss_started(_boss: Variant) -> void:
		started = true

	func boss_finished(_boss: Variant) -> void:
		finished = true

	func shake(_strength: float) -> void:
		pass


func _autoloads_ready() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	return tree != null and tree.root.get_node_or_null("Events") != null and tree.root.get_node_or_null("Audio") != null


func test_bosses_simulate() -> void:
	if not _autoloads_ready():
		print("      (test_boss_sim skipped: autoloads are not running yet in this runner)")
		return
	var tree := Engine.get_main_loop() as SceneTree
	var boss_script: GDScript = load("res://entities/bosses/boss.gd")
	var entity_script: GDScript = load("res://entities/entity.gd")
	for kind in ["warden", "mountain_king", "dragon", "cerberus", "hades"]:
		var sim := SimWorld.new()
		var arena := Node3D.new()
		tree.root.add_child(arena)
		var player: Node3D = entity_script.new()
		player.team = 0
		player.net_id = 7
		player.max_health = 1e9
		player.health = 1e9
		player.hit_radius = 0.4
		player.hit_height = 1.8
		arena.add_child(player)
		player.global_position = Vector3(0, 0, 6)
		sim.players.append(player)
		var boss: Node3D = boss_script.call("create", kind)
		boss.sim_world = sim
		boss.body.gravity = 0.0
		arena.add_child(boss)
		boss.global_position = Vector3.ZERO
		var dt := 1.0 / 30.0
		var max_phase := 1
		var hit_every := 0.5
		var acc := 0.0
		var steps := 0
		while sim.now < 240.0 and not boss.dead:
			sim.now += dt
			steps += 1
			acc += dt
			boss.server_tick(dt)
			max_phase = maxi(max_phase, boss.phase)
			if acc >= hit_every and boss.engaged:
				acc = 0.0
				boss.take_damage(boss.max_health * 0.012, 7, "hit" if steps % 3 else "fire")
		check(sim.started, "%s engaged" % kind)
		check_eq(max_phase, 3, "%s reached phase 3" % kind)
		check(boss.dead, "%s died" % kind)
		check(sim.finished, "%s reported its death" % kind)
		check(sim.telegraphs.size() >= 6, "%s telegraphed (%d)" % [kind, sim.telegraphs.size()])
		check(sim.hits.size() > 0, "%s landed hits" % kind)
		# Every hit must follow a telegraph that had finished filling.
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
		check_eq(unfair, 0, "%s hits without a filled telegraph" % kind)
		print("      %-14s phases→%d  telegraphs %d  hits %d  summons %d  projectiles %d  fight %.0fs" % [kind, max_phase, sim.telegraphs.size(), sim.hits.size(), sim.spawned, sim.projectiles, sim.now])
		arena.queue_free()
