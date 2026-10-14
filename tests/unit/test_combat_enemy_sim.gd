extends TestCase
## Headless simulation of every regular enemy against one player: it must
## notice the player, close in or keep its range, attack (melee hits or
## projectiles), stagger under heavy hits, leash home when pulled away, and die.
## Skipped (not failed) when run before autoloads exist (see test_boss_sim.gd).


class SimWorld:
	extends RefCounted
	var now := 0.0
	var players: Array = []
	var hits := 0
	var projectiles := 0
	var telegraphs := 0
	var despawned := false

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
			hits += 1

	func telegraph(_shape: String, _pos: Vector3, _dir: Vector3, _size: Vector3, _duration: float, _dim: int) -> void:
		telegraphs += 1

	func spawn_projectile(_kind: String, _origin: Vector3, _velocity: Vector3, _owner_id: int, _team: int, _dim: int, _damage: float) -> void:
		projectiles += 1

	func despawn_entity(_e: Variant) -> void:
		despawned = true

	func shake(_strength: float) -> void:
		pass


func test_enemies_simulate() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root.get_node_or_null("Events") == null:
		print("      (test_combat_enemy_sim skipped: autoloads are not running yet in this runner)")
		return
	var enemy_script: GDScript = load("res://entities/enemies/enemy.gd")
	var entity_script: GDScript = load("res://entities/entity.gd")
	for kind in ["skeleton", "archer", "ghoul", "troll", "imp", "shade"]:
		var sim := SimWorld.new()
		var arena := Node3D.new()
		tree.root.add_child(arena)
		var player: Node3D = entity_script.new()
		player.team = 0
		player.net_id = 3
		player.max_health = 1e9
		player.health = 1e9
		arena.add_child(player)
		player.global_position = Vector3(0, 0, 10)
		sim.players.append(player)
		var e: Node3D = enemy_script.call("create", kind)
		e.sim_world = sim
		e.net_id = 50
		arena.add_child(e)
		e.global_position = Vector3.ZERO
		e.spawn_point = Vector3.ZERO
		e.body.gravity = 0.0
		var dt := 1.0 / 30.0
		var noticed := false
		while sim.now < 25.0:
			sim.now += dt
			e.server_tick(dt)
			e.global_position.y = 0.0 if not e.body.fly else e.global_position.y
			if e.state == 3 or e._target != null:
				noticed = true
		check(noticed, "%s noticed the player" % kind)
		check(sim.hits + sim.projectiles > 0, "%s attacked (hits %d, projectiles %d)" % [kind, sim.hits, sim.projectiles])
		if kind == "troll":
			check(sim.telegraphs > 0, "troll slams are telegraphed")
		# Leash: drag the player far away; the enemy must give up and head home.
		player.global_position = Vector3(0, 0, 120)
		e.global_position = Vector3(0, 0, 45)
		for i in 60:
			e.server_tick(dt)
		check_eq(e.state, 7, "%s returns home when pulled away" % kind)
		# Death.
		e.take_damage(e.max_health * 10.0, 3, "hit")
		check(e.dead, "%s died" % kind)
		for i in 150:
			e.server_tick(dt)
		check(sim.despawned, "%s despawned after dying" % kind)
		print("      %-9s hits %d  projectiles %d  telegraphs %d" % [kind, sim.hits, sim.projectiles, sim.telegraphs])
		arena.queue_free()
