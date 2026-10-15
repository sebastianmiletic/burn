extends TestCase
## Creatures added with the Leviathan: every model builds and animates, the
## three new bosses (Leviathan, Broodmother, Bog Hag) are beatable through all
## phases with fair (fully telegraphed) hits and reset when abandoned, the new
## hostile creatures notice / attack / leash / die, wildlife flees and flocks
## startle. Skipped (not failed) when autoloads are missing (see test_boss_sim).

const MODEL_KINDS := ["leviathan", "sea_serpent", "broodmother", "giant_spider", "spiderling", "scorpion",
	"wolf", "dire_wolf", "frost_wolf", "hellhound", "bear", "deer", "stag", "rabbit", "goat", "boar", "bog_lurker",
	"cave_bat", "bird_flock", "crow_flock", "gull_flock", "fish_school", "bat_swarm", "rock_golem", "fire_elemental",
	"cave_crawler", "shark", "drowned", "bog_hag", "skeleton", "archer", "ghoul", "troll"]
const BEASTS := ["wolf", "dire_wolf", "frost_wolf", "hellhound", "bear", "giant_spider", "spiderling", "cave_bat",
	"cave_crawler", "rock_golem", "scorpion", "fire_elemental", "bog_lurker", "shark", "sea_serpent", "drowned"]


class SimWorld:
	extends RefCounted
	var now := 0.0
	var players: Array = []
	var telegraphs: Array = []  # [time, shape, duration]
	var hits: Array = []
	var started := false
	var finished := false
	var resets := 0
	var spawned := 0
	var projectiles := 0
	var despawned := false

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
		despawned = true

	func boss_started(_boss: Variant) -> void:
		started = true

	func boss_finished(_boss: Variant) -> void:
		finished = true

	func boss_reset(_boss: Variant) -> void:
		resets += 1

	func shake(_strength: float) -> void:
		pass


func _ready_tree() -> SceneTree:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root.get_node_or_null("Events") == null or tree.root.get_node_or_null("Audio") == null:
		return null
	return tree


func _player(arena: Node3D, pos: Vector3) -> Node3D:
	var entity_script: GDScript = load("res://entities/entity.gd")
	var player: Node3D = entity_script.new()
	player.team = 0
	player.net_id = 7
	player.max_health = 1e9
	player.health = 1e9
	player.hit_radius = 0.4
	player.hit_height = 1.8
	arena.add_child(player)
	player.global_position = pos
	return player


func _count_geometry(n: Node) -> int:
	var c := 1 if (n is MeshInstance3D or n is MultiMeshInstance3D) else 0
	for ch in n.get_children():
		c += _count_geometry(ch)
	return c


func test_models_build_and_animate() -> void:
	var tree := _ready_tree()
	if tree == null:
		print("      (test_creature_sim skipped: autoloads are not running yet in this runner)")
		return
	var arena := Node3D.new()
	tree.root.add_child(arena)
	var t0 := Time.get_ticks_usec()
	for kind: String in MODEL_KINDS:
		var m := Models.create_mob(kind, 3)
		check(m != null, "%s has a model" % kind)
		if m == null:
			continue
		m.lod_enabled = false
		arena.add_child(m)
		m.move_speed = 2.0
		for i in 12:
			m._process(1.0 / 30.0)
		for action: String in ["attack", "bite", "roar", "slam", "lunge", "hit"]:
			m.play(action)
			for i in 6:
				m._process(1.0 / 30.0)
		# Humanoids are one smooth skinned body (plus gear); other creatures are built from parts.
		var need := 1 if (m is FlockModel or m is HumanoidModel) else 6
		check(_count_geometry(m) >= need, "%s has a detailed model (%d parts)" % [kind, _count_geometry(m)])
		m.set_dead(true)
		for i in 10:
			m._process(0.1)
	print("      %d creature models built and animated in %.0f ms" % [MODEL_KINDS.size(), (Time.get_ticks_usec() - t0) / 1000.0])
	# Variants differ within a kind.
	var a := Models.create_mob("wolf", 1) as QuadrupedModel
	var b := Models.create_mob("wolf", 2) as QuadrupedModel
	check(a.k != b.k or a.spec["back"] != b.spec["back"], "wolves vary in size or coat")
	arena.queue_free()


func test_new_bosses_simulate() -> void:
	var tree := _ready_tree()
	if tree == null:
		return
	var boss_script: GDScript = load("res://entities/bosses/boss.gd")
	for kind: String in ["leviathan", "broodmother", "bog_hag"]:
		var sim := SimWorld.new()
		var arena := Node3D.new()
		tree.root.add_child(arena)
		var player := _player(arena, Vector3(0, 0, 6))
		sim.players.append(player)
		var boss: Node3D = boss_script.call("create", kind)
		check(boss.kind == kind, "%s created" % kind)
		boss.sim_world = sim
		boss.body.gravity = 0.0
		arena.add_child(boss)
		boss.global_position = Vector3.ZERO if kind != "leviathan" else boss.global_position
		var dt := 1.0 / 30.0
		var max_phase := 1
		var acc := 0.0
		var steps := 0
		var surfaced_time := 0.0
		while sim.now < 300.0 and not boss.dead:
			sim.now += dt
			steps += 1
			acc += dt
			boss.server_tick(dt)
			if boss.flying:
				surfaced_time += dt
			max_phase = maxi(max_phase, boss.phase)
			if acc >= 0.5 and boss.engaged:
				acc = 0.0
				boss.take_damage(boss.max_health * 0.012, 7, "hit" if steps % 3 else "fire")
		check(sim.started, "%s engaged" % kind)
		check_eq(max_phase, 3, "%s reached phase 3" % kind)
		check(boss.dead, "%s died" % kind)
		check(sim.finished, "%s reported its death" % kind)
		check(sim.telegraphs.size() >= 8, "%s telegraphed (%d)" % [kind, sim.telegraphs.size()])
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
		if kind == "leviathan":
			check(surfaced_time > 10.0 and surfaced_time < sim.now * 0.8, "leviathan surfaces and dives (surfaced %.0fs of %.0fs)" % [surfaced_time, sim.now])
			check(sim.spawned > 0, "leviathan summoned thralls")
		if kind == "broodmother":
			check(sim.spawned > 0, "broodmother hatched spiderlings")
		print("      %-12s phases→%d  telegraphs %d  hits %d  summons %d  projectiles %d  fight %.0fs" % [kind, max_phase, sim.telegraphs.size(), sim.hits.size(), sim.spawned, sim.projectiles, sim.now])
		arena.queue_free()


func test_new_bosses_reset_when_abandoned() -> void:
	var tree := _ready_tree()
	if tree == null:
		return
	var boss_script: GDScript = load("res://entities/bosses/boss.gd")
	for kind: String in ["leviathan", "broodmother", "bog_hag"]:
		var sim := SimWorld.new()
		var arena := Node3D.new()
		tree.root.add_child(arena)
		var player := _player(arena, Vector3(0, 0, 6))
		sim.players.append(player)
		var boss: Node3D = boss_script.call("create", kind)
		boss.sim_world = sim
		boss.body.gravity = 0.0
		arena.add_child(boss)
		var dt := 1.0 / 30.0
		for i in 300:
			sim.now += dt
			boss.server_tick(dt)
			if i % 15 == 0:
				boss.take_damage(boss.max_health * 0.01, 7, "hit")
		check(boss.engaged, "%s engaged" % kind)
		var wounded: float = boss.health
		# Everyone leaves.
		player.global_position = Vector3(0, 0, 500)
		for i in 30 * 14:
			sim.now += dt
			boss.server_tick(dt)
		check(not boss.engaged, "%s reset after the party left" % kind)
		check(sim.resets > 0, "%s reported its reset" % kind)
		check_near(boss.health, wounded, 0.01, "%s preserves damage on reset" % kind)
		arena.queue_free()


func test_beasts_simulate() -> void:
	var tree := _ready_tree()
	if tree == null:
		return
	for kind: String in BEASTS:
		var sim := SimWorld.new()
		var arena := Node3D.new()
		tree.root.add_child(arena)
		var player := _player(arena, Vector3(0, 0, 8))
		sim.players.append(player)
		var e: Node3D = EntityFactory.create(kind)
		check(e != null and e is Beast, "%s is a beast" % kind)
		if e == null:
			arena.queue_free()
			continue
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
			if not e.body.fly:
				e.global_position.y = 0.0
			if e._target != null:
				noticed = true
		check(noticed, "%s noticed the player" % kind)
		check(sim.hits.size() + sim.projectiles > 0, "%s attacked (hits %d, projectiles %d)" % [kind, sim.hits.size(), sim.projectiles])
		player.global_position = Vector3(0, 0, 120)
		e.global_position = Vector3(0, 0, 45)
		for i in 60:
			e.server_tick(dt)
		check_eq(e.state, 7, "%s returns home when pulled away" % kind)
		e.take_damage(e.max_health * 10.0, 7, "hit")
		check(e.dead, "%s died" % kind)
		for i in 150:
			e.server_tick(dt)
		check(sim.despawned, "%s despawned after dying" % kind)
		arena.queue_free()


func test_wildlife_flees_and_flocks_startle() -> void:
	var tree := _ready_tree()
	if tree == null:
		return
	for kind: String in ["deer", "rabbit", "goat", "stag"]:
		var sim := SimWorld.new()
		var arena := Node3D.new()
		tree.root.add_child(arena)
		var player := _player(arena, Vector3(0, 0, 40))
		sim.players.append(player)
		var e: Node3D = EntityFactory.create(kind)
		check(e is Wildlife, "%s is wildlife" % kind)
		e.sim_world = sim
		arena.add_child(e)
		e.body.gravity = 0.0
		var dt := 1.0 / 30.0
		for i in 60:
			e.server_tick(dt)
		check(e.anim != Wildlife.FLEE, "%s calm while nobody is near" % kind)
		player.global_position = e.global_position + Vector3(0, 0, 3)
		var start: Vector3 = e.global_position
		for i in 90:
			e.server_tick(dt)
			e.global_position.y = 0.0
		check_eq(e.anim, Wildlife.FLEE, "%s flees" % kind)
		check(e.global_position.distance_to(player.global_position) > start.distance_to(player.global_position) + 2.0, "%s ran away" % kind)
		e.take_damage(1000.0, 7, "hit")
		check(e.dead, "%s can be hunted" % kind)
		arena.queue_free()
	# Boars fight back.
	var sim2 := SimWorld.new()
	var arena2 := Node3D.new()
	tree.root.add_child(arena2)
	var p2 := _player(arena2, Vector3(0, 0, 4))
	sim2.players.append(p2)
	var boar: Node3D = EntityFactory.create("boar")
	boar.sim_world = sim2
	arena2.add_child(boar)
	boar.body.gravity = 0.0
	boar.take_damage(5.0, 7, "hit")
	for i in 120:
		boar.server_tick(1.0 / 30.0)
		boar.global_position.y = 0.0
	check(sim2.hits.size() > 0, "a hurt boar charges back")
	arena2.queue_free()
	# Flocks startle.
	for kind: String in ["bird_flock", "fish_school", "bat_swarm"]:
		var sim := SimWorld.new()
		var arena := Node3D.new()
		tree.root.add_child(arena)
		var player := _player(arena, Vector3(0, 0, 30))
		sim.players.append(player)
		var f: Node3D = EntityFactory.create(kind)
		check(f is Flock, "%s is a flock" % kind)
		f.sim_world = sim
		arena.add_child(f)
		for i in 30:
			f.server_tick(1.0 / 30.0)
		check_eq(f.anim, 0, "%s calm" % kind)
		player.global_position = Vector3(0, 0, 2)
		for i in 30:
			f.server_tick(1.0 / 30.0)
		check_eq(f.anim, 1, "%s startled" % kind)
		check_eq(f.take_damage(100.0, 7, "hit"), 0.0, "%s cannot be hurt" % kind)
		arena.queue_free()


func test_styled_telegraphs_keep_their_shape() -> void:
	var o := Vector3.ZERO
	var fwd := Vector3(0, 0, -1)
	check(TelegraphShape.contains("circle:geyser", o, fwd, Vector3(3, 0, 0), Vector3(2, 0, 0)), "styled circle hits inside")
	check(not TelegraphShape.contains("circle:geyser", o, fwd, Vector3(3, 0, 0), Vector3(4, 0, 0)), "styled circle misses outside")
	check(TelegraphShape.contains("line:wave", o, fwd, Vector3(10, 4, 0), Vector3(1, 0, -5)), "styled line")
	check_eq(TelegraphShape.base("ring:hex"), "ring")
	check_eq(TelegraphShape.style("ring:hex"), "hex")
	check_eq(TelegraphShape.style("cone"), "")


func test_lairs_planned() -> void:
	var g := WorldGen.new(WorldGen.Dimension.OVERWORLD, 1234)
	g.prepare()
	var by_id := {}
	var bosses := {}
	for loc in g.locations:
		by_id[loc.id] = loc
		for s in loc.spawns_of("boss"):
			bosses[s["kind"]] = loc
	for kind: String in ["leviathan", "broodmother", "bog_hag"]:
		check(bosses.has(kind), "%s has a lair" % kind)
	if by_id.has(&"drowned_spire"):
		var spire: Location = by_id[&"drowned_spire"]
		var c := g.center()
		check(Vector2(spire.center.x, spire.center.z).distance_to(c) > 600.0, "the Drowned Spire is far out at sea")
		var boss_pos: Vector3 = spire.spawns_of("boss")[0]["pos"]
		check(boss_pos.y > WorldGen.SEA_LEVEL + 1.5, "the arena platform is above the waves")
		var p := Vector3i(boss_pos.floor()) + Vector3i(0, -1, 0)
		var data := g.generate_chunk(Chunk.key_of(p))
		var l := Chunk.local(p)
		check(Blocks.is_solid(data[Chunk.index(l.x, l.y, l.z)]), "the platform is solid underfoot")
		# Deep water around the islet for the Leviathan to swim in.
		var ring := Vector3i(boss_pos.floor()) + Vector3i(23, -6, 0)
		var wdata := g.generate_chunk(Chunk.key_of(ring))
		var wl := Chunk.local(ring)
		check(Blocks.is_liquid(wdata[Chunk.index(wl.x, wl.y, wl.z)]), "the Leviathan's ring is under water")
		check(by_id.has(&"tidewatch_shrine"), "a shrine on the coast")
	if by_id.has(&"broodmother_lair"):
		var lair: Location = by_id[&"broodmother_lair"]
		var bp: Vector3 = lair.spawns_of("boss")[0]["pos"]
		var q := Vector3i(bp.floor()) + Vector3i(0, 3, 0)
		var cdata := g.generate_chunk(Chunk.key_of(q))
		var cl := Chunk.local(q)
		check_eq(cdata[Chunk.index(cl.x, cl.y, cl.z)], Blocks.AIR, "the Broodmother's cavern is carved")
	for loc in g.locations:
		for s in loc.spawns_of("decor"):
			check(String(s.get("decor", "")) != "", "decor spawns are named")
