extends TestCase
## The humanoid bosses (Warden, Mountain King, Hades, Old Mother Mire) fight
## with their whole movesets: every attack is used, every hit follows a
## filled telegraph, the boss moves about (circling, lunges, leaps, charges,
## blinks) without leaving its arena, plays a bespoke animation for every
## action it sends, and dies. Their models build and play every move.
## Skipped (not failed) when autoloads are missing (see test_boss_sim).

const KINDS := ["warden", "mountain_king", "hades", "bog_hag"]


class SimWorld:
	extends RefCounted
	var now := 0.0
	var players: Array = []
	var telegraphs: Array = []  # [time, shape, duration]
	var hits: Array = []
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
		pass

	func boss_finished(_boss: Variant) -> void:
		finished = true

	func shake(_strength: float) -> void:
		pass


func _ready_tree() -> SceneTree:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root.get_node_or_null("Events") == null or tree.root.get_node_or_null("Audio") == null:
		return null
	return tree


func test_humanoid_bosses_use_their_whole_moveset() -> void:
	var tree := _ready_tree()
	if tree == null:
		print("      (test_boss_moves_humanoid skipped: autoloads are not running yet in this runner)")
		return
	for kind: String in KINDS:
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
		player.global_position = Vector3(0, 0, 6)
		sim.players.append(player)
		var boss := Boss.create(kind)
		boss.sim_world = sim
		boss.body.gravity = 0.0
		arena.add_child(boss)
		boss.global_position = Vector3.ZERO
		var model := boss.model as BossHumanoid
		check(model != null, "%s has a BossHumanoid model" % kind)
		var dt := 1.0 / 30.0
		var used := {}
		var anims := {}
		var travelled := 0.0
		var max_off := 0.0
		var last := boss.global_position
		var last_anim := -1.0
		var acc := 0.0
		var max_phase := 1
		while sim.now < 480.0 and not boss.dead:
			sim.now += dt
			acc += dt
			# The player circles the boss at changing ranges (melee to far).
			var r := 7.5 + 6.0 * sin(sim.now * 0.23)
			var a := sim.now * 0.31
			player.global_position = Vector3(cos(a) * r, 0, sin(a) * r)
			boss.server_tick(dt)
			if boss._attack != "":
				used[boss._attack] = true
			if boss.anim_time != last_anim and boss.anim > 0:
				last_anim = boss.anim_time
				anims[Boss.ACTIONS[boss.anim]] = true
			travelled += boss.global_position.distance_to(last)
			last = boss.global_position
			max_off = maxf(max_off, Vector2(boss.global_position.x, boss.global_position.z).length())
			max_phase = maxi(max_phase, boss.phase)
			if acc >= 0.5 and boss.engaged:
				acc = 0.0
				boss.take_damage(boss.max_health * 0.0035, 7, "hit")
		check(boss.dead, "%s died (%.0fs)" % [kind, sim.now])
		check_eq(max_phase, 3, "%s reached phase 3" % kind)
		check(sim.finished, "%s reported its death" % kind)
		var attacks: Dictionary = boss._attacks()
		check(attacks.size() >= 7, "%s has a wide moveset (%d attacks)" % [kind, attacks.size()])
		var missing: Array = []
		for name: String in attacks:
			if not used.has(name):
				missing.append(name)
		check(missing.is_empty(), "%s used every attack (missing %s)" % [kind, missing])
		check(travelled > 40.0, "%s moves about its arena (%.0f m)" % [kind, travelled])
		check(max_off < boss.arena_radius * 1.2, "%s stays in its arena (%.1f of %.0f m)" % [kind, max_off, boss.arena_radius])
		check(sim.hits.size() > 0, "%s landed hits" % kind)
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
		# Every action it sent has a bespoke move on the model.
		var generic: Array = []
		for act: String in anims:
			if model != null and not model.moves.has(act):
				generic.append(act)
		check(generic.is_empty(), "%s plays bespoke moves only (generic: %s)" % [kind, generic])
		check(anims.has("phase"), "%s plays a phase transition" % kind)
		print("      %-14s attacks %d  anims %d  telegraphs %d  hits %d  moved %.0f m  max off %.1f m  fight %.0fs" % [kind, used.size(), anims.size(), sim.telegraphs.size(), sim.hits.size(), travelled, max_off, sim.now])
		arena.queue_free()


func test_humanoid_boss_models_play_every_move() -> void:
	var tree := _ready_tree()
	if tree == null:
		return
	var arena := Node3D.new()
	tree.root.add_child(arena)
	for kind: String in KINDS:
		var m := Models.create(kind) as BossHumanoid
		check(m != null, "%s model builds" % kind)
		if m == null:
			continue
		m.lod_enabled = false
		arena.add_child(m)
		m.set_boss_state(true, 3)
		check(m.moves.size() >= 8, "%s has bespoke moves (%d)" % [kind, m.moves.size()])
		for action: String in m.moves:
			m.play(action, 1.5)
			var moved := false
			var rest: Array[Quaternion] = []
			for b in 16:
				rest.append(m.skeleton.get_bone_pose_rotation(b))
			for i in 24:
				m._process(1.0 / 16.0)
			for b in 16:
				if not m.skeleton.get_bone_pose_rotation(b).is_equal_approx(rest[b]):
					moved = true
			check(moved, "%s %s animates the rig" % [kind, action])
			for b in m.skeleton.get_bone_count():
				var q := m.skeleton.get_bone_pose_rotation(b)
				if not q.is_finite():
					check(false, "%s %s leaves bone %d finite" % [kind, action, b])
					break
		# Turning on the spot and dying (kneel, then fall) run too.
		m.play("", 0.1)
		m.rotation.y = 0.0
		for i in 10:
			m.rotation.y += 0.12
			m._process(1.0 / 30.0)
		m.set_dead(true)
		for i in 40:
			m._process(0.1)
		check(m.skeleton.get_bone_pose_position(0).is_finite(), "%s dies cleanly" % kind)
	arena.queue_free()
