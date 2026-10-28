extends TestCase
## The Ryft bosses (Prism Sentinel, Void Sovereign) fly: they hold `flying`,
## move round their arena's air volume (never leaving it), use their whole
## phase-dependent moveset, only land telegraphed hits and die; their models
## play every bespoke action, flinch, transform and collapse.

const KINDS := ["ryft_sentinel", "void_sovereign"]
const MOVES := {
	"ryft_sentinel": ["lance", "nova", "slam", "swipe", "beam", "rain", "mirrors", "refract", "charge", "orbit", "constellation"],
	"void_sovereign": ["lash", "orbs", "rift", "well", "starfall", "blink", "dash", "summon", "eclipse", "clones", "blackhole"],
}
const MODEL_ACTIONS := ["thrust", "nova", "swipe", "slam", "beam", "volley", "special1", "special2", "teleport", "charge",
	"spin", "phase", "lash", "rift", "pull", "starfall", "eclipse", "summon", "roar", "hit", "cast", "sweep"]


class SimWorld:
	extends RefCounted
	var now := 0.0
	var players: Array = []
	var telegraphs: Array = []  # [time, shape, duration]
	var hits: Array = []
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

	func boss_reset(_boss: Variant) -> void:
		pass

	func shake(_strength: float) -> void:
		pass


func _ready_tree() -> SceneTree:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root.get_node_or_null("Events") == null or tree.root.get_node_or_null("Audio") == null:
		return null
	return tree


func test_ryft_bosses_fly_and_use_their_moveset() -> void:
	var tree := _ready_tree()
	if tree == null:
		print("      (test_boss_moves_ryft skipped: autoloads are not running yet in this runner)")
		return
	var boss_script: GDScript = load("res://entities/bosses/boss.gd")
	var entity_script: GDScript = load("res://entities/entity.gd")
	for kind: String in KINDS:
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
		player.global_position = Vector3(0, 0, 8)
		sim.players.append(player)
		var boss: Boss = boss_script.call("create", kind)
		boss.sim_world = sim
		arena.add_child(boss)
		boss.global_position = Vector3.ZERO
		boss.spawn_point = Vector3.ZERO
		var used := {}
		var dt := 1.0 / 30.0
		var acc := 0.0
		var steps := 0
		var max_phase := 1
		var travelled := 0.0
		var last := boss.global_position
		var max_off := 0.0
		var max_alt := -INF
		var min_alt := INF
		var grounded_engaged := 0
		while sim.now < 420.0 and not boss.dead:
			sim.now += dt
			steps += 1
			acc += dt
			# The player walks a slow figure round the arena (near and far).
			var a := sim.now * 0.15
			player.global_position = Vector3(cos(a) * (6.0 + 8.0 * absf(sin(sim.now * 0.07))), 0, sin(a) * 9.0)
			boss.server_tick(dt)
			if boss._attack != "":
				used[boss._attack] = true
			max_phase = maxi(max_phase, boss.phase)
			travelled += boss.global_position.distance_to(last)
			last = boss.global_position
			var off := boss.global_position - boss.spawn_point
			max_off = maxf(max_off, Vector2(off.x, off.z).length())
			if boss.engaged:
				max_alt = maxf(max_alt, off.y)
				min_alt = minf(min_alt, off.y)
				if not boss.flying:
					grounded_engaged += 1
			if acc >= 0.5 and boss.engaged:
				acc = 0.0
				boss.take_damage(boss.max_health * 0.0035, 7, "hit" if steps % 3 else "fire")
		check(sim.started, "%s engaged" % kind)
		check_eq(max_phase, 3, "%s reached phase 3" % kind)
		check(boss.dead, "%s died (fight %.0fs)" % [kind, sim.now])
		check(sim.finished, "%s reported its death" % kind)
		check_eq(grounded_engaged, 0, "%s ticks spent grounded while fighting" % kind)
		var missing: Array = []
		for m: String in MOVES[kind]:
			if not used.has(m):
				missing.append(m)
		check(missing.is_empty(), "%s used its whole moveset (missing %s)" % [kind, missing])
		check(MOVES[kind].size() >= 7, "%s has a wide moveset" % kind)
		check(travelled > 60.0, "%s moves round its arena (%.0f m)" % [kind, travelled])
		check(max_off <= boss.arena_radius * 0.96, "%s stays inside its arena (%.1f of %.0f)" % [kind, max_off, boss.arena_radius])
		check(max_alt <= boss.air_ceiling + 0.5 and min_alt > -1.0, "%s stays in its air volume (%.1f..%.1f)" % [kind, min_alt, max_alt])
		check(max_alt > 4.0, "%s rises for its aerial attacks (%.1f)" % [kind, max_alt])
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
		print("      %-15s moves %d  telegraphs %d  hits %d  travelled %.0f m  alt %.1f..%.1f  fight %.0fs" % [kind, used.size(), sim.telegraphs.size(), sim.hits.size(), travelled, min_alt, max_alt, sim.now])
		arena.queue_free()


func test_ryft_models_play_every_action() -> void:
	var tree := _ready_tree()
	if tree == null:
		return
	for kind: String in KINDS:
		var m := Models.create(kind)
		tree.root.add_child(m)
		m.call("set_boss_state", true, 1, false)
		var moved := 0
		for phase in [1, 2, 3]:
			m.call("set_boss_state", true, phase, false)
			for a: String in MODEL_ACTIONS:
				m.play(a)
				var rest := {}
				for n: Node3D in m.find_children("Shoulder", "Node3D", true, false):
					rest[n] = n.rotation
				for i in 20:
					m.position.x += 0.1
					m.rotation.y += 0.02
					m._process(1.0 / 30.0)
				for n: Node3D in rest:
					if n.rotation.distance_to(rest[n]) > 0.05:
						moved += 1
						break
		check(moved >= MODEL_ACTIONS.size() * 2, "%s poses its arms for its actions (%d)" % [kind, moved])
		m.set_dead(true)
		for i in 200:
			m._process(1.0 / 30.0)
		check(m.is_dissolved(), "%s collapses and dissolves" % kind)
		m.free()
