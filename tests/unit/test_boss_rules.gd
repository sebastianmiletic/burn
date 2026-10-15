extends TestCase
## Boss health and encounter rules (entities/bosses/boss.gd, boss_ledger.gd,
## docs/BOSS_GUIDE.md). Each test reproduces a way bosses used to heal to full
## or misbehave, in a headless stand-in world:
##   * disengaging, leaving and re-entering the arena keep the wounds
##   * despawning and spawning again (location deactivation) keeps the wounds
##   * a save/reload keeps the wounds
##   * only a long genuine disengage restores full health
##   * party scaling happens once per pull (late arrivals keep the fraction)
##   * players outside the arena cannot pull or chip the boss
##   * a blow that crosses two phase thresholds runs both transitions
##   * a dead boss cannot die twice or report twice
##   * snapshots carry max health and the first one is not a "hit"
##   * bosses that fall out of / wander off the arena return to their spawn


class SimWorld:
	extends RefCounted
	var now := 0.0
	var boss_ledger := BossLedger.new()
	var players: Array = []
	var telegraphs := 0
	var spawned := 0
	var started := 0
	var finished := 0
	var resets := 0
	var despawned: Array = []

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
		target.take_damage(amount, source_id, kind)

	func telegraph(_shape: String, _pos: Vector3, _dir: Vector3, _size: Vector3, _duration: float, _dim: int) -> void:
		telegraphs += 1

	func spawn_projectile(_kind: String, _origin: Vector3, _velocity: Vector3, _owner_id: int, _team: int, _dim: int, _damage: float) -> void:
		pass

	func spawn_entity(_kind: String, _pos: Vector3, _dim: int, _data := {}) -> Variant:
		spawned += 1
		return null

	func despawn_entity(e: Variant) -> void:
		despawned.append(e)

	func boss_started(_boss: Variant) -> void:
		started += 1

	func boss_finished(_boss: Variant) -> void:
		finished += 1

	func boss_reset(_boss: Variant) -> void:
		resets += 1

	func shake(_strength: float) -> void:
		pass


## A boss whose phase transitions are recorded.
class PhaseProbe:
	extends WardenBoss
	var transitions: Array[int] = []

	func _on_phase_changed(new_phase: int) -> void:
		transitions.append(new_phase)


var _tree: SceneTree
var _arena: Node3D


func _autoloads_ready() -> bool:
	_tree = Engine.get_main_loop() as SceneTree
	return _tree != null and _tree.root.get_node_or_null("Events") != null and _tree.root.get_node_or_null("Audio") != null


func _player(sim: SimWorld, id: int, pos: Vector3) -> Node3D:
	var entity_script: GDScript = load("res://entities/entity.gd")
	var p: Node3D = entity_script.new()
	p.team = 0
	p.net_id = id
	p.max_health = 1e9
	p.health = 1e9
	_arena.add_child(p)
	p.global_position = pos
	sim.players.append(p)
	return p


func _boss(sim: SimWorld, kind := "warden", home := "crypt_depths") -> Boss:
	var b := Boss.create(kind)
	b.sim_world = sim
	b.body.gravity = 0.0
	b.home_location = home
	_arena.add_child(b)
	b.global_position = Vector3.ZERO
	b.spawn_point = Vector3.ZERO
	return b


## Hit the boss (as player 7) down to `frac` of its maximum, after resistances.
func _wound(sim: SimWorld, b: Boss, frac: float) -> void:
	var amount := (b.health - frac * b.max_health) / (1.0 - Damage.resist(b.kind, "hit"))
	b.take_damage(amount, 7, "hit")
	_tick(sim, b, 0.05)


func _tick(sim: SimWorld, b: Boss, seconds: float) -> void:
	var dt := 1.0 / 20.0
	var t := 0.0
	while t < seconds and not b.dead:
		t += dt
		sim.now += dt
		b.server_tick(dt)


func _begin() -> bool:
	if not _autoloads_ready():
		print("      (test_boss_rules skipped: autoloads are not running yet in this runner)")
		return false
	_arena = Node3D.new()
	_tree.root.add_child(_arena)
	return true


func _end() -> void:
	_arena.free()


func test_leaving_and_reentering_keeps_wounds() -> void:
	if not _begin():
		return
	var sim := SimWorld.new()
	var p := _player(sim, 7, Vector3(0, 0, 8))
	var b := _boss(sim)
	_tick(sim, b, 0.5)
	check(b.engaged, "player in aggro range pulls the boss")
	_wound(sim, b, 0.5)
	var wounded := b.health
	var max_h := b.max_health
	check_eq(b.phase, 2, "half health is phase 2")
	# The player runs out of the arena: the boss gives up after a few seconds.
	p.global_position = Vector3(300, 0, 0)
	_tick(sim, b, Boss.DISENGAGE_SECONDS + 1.0)
	check(not b.engaged, "boss disengages when the arena is empty")
	check_eq(sim.resets, 1, "arena reopened once")
	check_eq(b.health, wounded, "disengaging does not heal")
	check_eq(b.max_health, max_h, "disengaging does not rescale")
	check_eq(b.phase, 2, "phase is kept")
	# Idle for five minutes in the arena: still wounded, no regeneration.
	_tick(sim, b, 300.0)
	check_eq(b.health, wounded, "no regeneration while idle")
	p.global_position = Vector3(0, 0, 8)
	_tick(sim, b, 0.5)
	check(b.engaged, "re-entering pulls it again")
	check_eq(b.health, wounded, "re-engaging does not heal")
	check_eq(b.max_health, max_h, "re-engaging does not rescale")
	check_eq(b.phase, 2, "re-engages in phase 2")
	_end()


func test_despawn_and_respawn_keeps_wounds() -> void:
	if not _begin():
		return
	var sim := SimWorld.new()
	var p := _player(sim, 7, Vector3(0, 0, 8))
	var b := _boss(sim, "mountain_king", "mountain_hall")
	_tick(sim, b, 0.5)
	_wound(sim, b, 0.3)
	var wounded := b.health
	var max_h := b.max_health
	# Everyone leaves; the location deactivates and frees the boss.
	p.global_position = Vector3(500, 0, 0)
	_tick(sim, b, Boss.DISENGAGE_SECONDS + 1.0)
	b.free()
	_tick_world(sim, 60.0)
	# Players return: the location spawns a fresh boss entity.
	var b2 := _boss(sim, "mountain_king", "mountain_hall")
	_tick(sim, b2, 0.1)
	check_eq(b2.health, wounded, "respawned boss keeps its wounds")
	check_eq(b2.max_health, max_h, "respawned boss keeps its scaling")
	check_eq(b2.phase, 3, "respawned boss keeps its phase")
	p.global_position = Vector3(0, 0, 8)
	_tick(sim, b2, 0.5)
	check(b2.engaged, "respawned boss engages")
	check_eq(b2.health, wounded, "engaging the respawned boss does not heal")
	# A different arena's boss is unaffected.
	var other := _boss(sim, "warden", "crypt_depths")
	_tick(sim, other, 0.1)
	check_eq(other.health, other.max_health, "other bosses are not wounded")
	_end()


func _tick_world(sim: SimWorld, seconds: float) -> void:
	sim.now += seconds


func test_reload_keeps_wounds() -> void:
	if not _begin():
		return
	var sim := SimWorld.new()
	_player(sim, 7, Vector3(0, 0, 8))
	var b := _boss(sim, "hades", "throne_of_hades")
	_tick(sim, b, 0.5)
	b.take_damage(b.max_health * 0.4, 7)
	var wounded := b.health
	var saved := sim.boss_ledger.to_save(sim.now)
	# A JSON round trip like the save system.
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
	var sim2 := SimWorld.new()
	sim2.now = sim.now
	sim2.boss_ledger.from_save(parsed)
	_player(sim2, 7, Vector3(0, 0, 40))
	var b2 := _boss(sim2, "hades", "throne_of_hades")
	_tick(sim2, b2, 0.1)
	check_near(b2.health, wounded, 0.01, "reloaded boss keeps its wounds")
	_end()


func test_only_long_disengage_recovers() -> void:
	if not _begin():
		return
	var sim := SimWorld.new()
	var p := _player(sim, 7, Vector3(0, 0, 8))
	var b := _boss(sim)
	_tick(sim, b, 0.5)
	b.take_damage(b.max_health * 0.6, 7)
	var wounded := b.health
	p.global_position = Vector3(400, 0, 0)
	_tick(sim, b, Boss.DISENGAGE_SECONDS + 1.0)
	_tick(sim, b, BossLedger.RECOVER_SECONDS - 30.0)
	check_eq(b.health, wounded, "still wounded just before the recovery time")
	_tick(sim, b, 40.0)
	check_eq(b.health, b.max_health, "recovered after a long genuine disengage")
	check_eq(b.phase, 1, "back to phase 1")
	check_eq(b.max_health, b.base_health, "scaling is redone at the next pull")
	# The same rule for a despawned boss: the ledger entry expires.
	var b2 := _boss(sim, "warden", "other_arena")
	p.global_position = Vector3(0, 0, 8)
	_tick(sim, b2, 0.5)
	b2.take_damage(b2.max_health * 0.5, 7)
	p.global_position = Vector3(400, 0, 0)
	_tick(sim, b2, Boss.DISENGAGE_SECONDS + 1.0)
	b2.free()
	sim.now += BossLedger.RECOVER_SECONDS + 1.0
	var b3 := _boss(sim, "warden", "other_arena")
	_tick(sim, b3, 0.1)
	check_eq(b3.health, b3.max_health, "expired wounds are forgotten")
	_end()


func test_party_scaling_once_per_pull() -> void:
	if not _begin():
		return
	var sim := SimWorld.new()
	_player(sim, 7, Vector3(0, 0, 8))
	_player(sim, 8, Vector3(2, 0, 8))
	var b := _boss(sim)
	_tick(sim, b, 0.5)
	check_near(b.max_health, Damage.boss_health(b.base_health, 2), 0.01, "scaled for the two players at the pull")
	b.take_damage(b.max_health * 0.2, 7)
	var frac := b.health / b.max_health
	# A third player arrives within the pull window: scaled up, fraction kept.
	var late := _player(sim, 9, Vector3(-2, 0, 8))
	_tick(sim, b, 0.5)
	check_near(b.max_health, Damage.boss_health(b.base_health, 3), 0.01, "late arrival in the pull window scales the boss")
	check_near(b.health / b.max_health, frac, 0.0001, "the health fraction is kept (never a heal)")
	# After the window nobody changes the scaling, arriving or leaving.
	_tick(sim, b, Boss.PULL_WINDOW + 1.0)
	var max_h := b.max_health
	var h := b.health
	_player(sim, 10, Vector3(0, 0, 10))
	late.global_position = Vector3(500, 0, 0)
	_tick(sim, b, 1.0)
	check_eq(b.max_health, max_h, "no rescale after the pull window")
	check(b.health <= h, "health never goes up")
	_end()


func test_attacks_from_outside_the_arena_are_evaded() -> void:
	if not _begin():
		return
	var sim := SimWorld.new()
	_player(sim, 7, Vector3(0, 0, 150))
	var b := _boss(sim)
	var dealt := b.take_damage(200.0, 7, "hit")
	check_eq(dealt, 0.0, "a hit from outside the arena is evaded")
	check(not b.engaged, "and does not pull the boss")
	check_eq(sim.started, 0, "the arena gates stay open")
	check_eq(b.health, b.max_health, "no chip damage")
	# A player above the arena (a cliff over the crypt) does not count either.
	var above := _player(sim, 8, Vector3(0, 60, 4))
	check_eq(b.take_damage(200.0, 8, "hit"), 0.0, "a hit from far above the arena is evaded")
	above.global_position = Vector3(0, 0, 6)
	check(b.take_damage(200.0, 8, "hit") > 0.0, "a hit from inside the arena lands")
	check(b.engaged, "and pulls the boss")
	_end()


func test_phases_are_never_skipped() -> void:
	if not _begin():
		return
	var sim := SimWorld.new()
	_player(sim, 7, Vector3(0, 0, 8))
	var b := PhaseProbe.new()
	b.sim_world = sim
	b.body.gravity = 0.0
	_arena.add_child(b)
	b.global_position = Vector3.ZERO
	_tick(sim, b, 0.5)
	# One huge blow from full to 20 %.
	b.take_damage(b.max_health * 0.8 / (1.0 - Damage.resist("warden", "hit")), 7)
	_tick(sim, b, 0.1)
	check_eq(b.phase, 3, "now in phase 3")
	check_eq(b.transitions, [2, 3] as Array[int], "both transitions ran, in order")
	_end()


func test_no_double_death() -> void:
	if not _begin():
		return
	var sim := SimWorld.new()
	_player(sim, 7, Vector3(0, 0, 8))
	var b := _boss(sim)
	_tick(sim, b, 0.5)
	b.take_damage(b.max_health * 10.0, 7)
	check(b.dead, "dead")
	check_eq(b.take_damage(500.0, 7), 0.0, "a corpse takes no damage")
	b.burning = 3.0
	_tick_dead(sim, b, 14.0)
	check_eq(sim.finished, 1, "reported its death exactly once")
	check_eq(sim.despawned.count(b), 1, "despawned exactly once")
	check(sim.boss_ledger.recall("crypt_depths", sim.now).is_empty(), "a dead boss leaves no wounds behind")
	_end()


func _tick_dead(sim: SimWorld, b: Boss, seconds: float) -> void:
	var dt := 1.0 / 20.0
	var t := 0.0
	while t < seconds:
		t += dt
		sim.now += dt
		b.server_tick(dt)


func test_disengage_clears_burns_and_summons() -> void:
	if not _begin():
		return
	var sim := SimWorld.new()
	var p := _player(sim, 7, Vector3(0, 0, 8))
	var b := _boss(sim)
	_tick(sim, b, 0.5)
	b.take_damage(30.0, 7, "fire")
	check(b.burning > 0.0, "fire sets it burning")
	p.global_position = Vector3(400, 0, 0)
	_tick(sim, b, 2.0)
	b.burning = 60.0
	_tick(sim, b, Boss.DISENGAGE_SECONDS)
	check_eq(b.burning, 0.0, "a disengaged boss stops burning (no kill without the party)")
	var h := b.health
	_tick(sim, b, 10.0)
	check_eq(b.health, h, "nothing ticks on it afterwards")
	_end()


func test_snapshot_carries_max_health() -> void:
	if not _begin():
		return
	var sim := SimWorld.new()
	_player(sim, 7, Vector3(0, 0, 8))
	_player(sim, 8, Vector3(2, 0, 8))
	var b := _boss(sim)
	_tick(sim, b, 0.5)
	b.take_damage(b.max_health * 0.5, 7)
	var snap := b.snapshot()
	# A client's copy of the boss starts at base health (its _ready).
	var c := Boss.create("warden")
	_arena.add_child(c)
	check_eq(c.max_health, c.base_health, "client copy starts unscaled")
	c.apply_snapshot(snap, 1.0)
	check_eq(c.max_health, b.max_health, "max health replicated (boss bar shows the scaled maximum)")
	check_eq(c.health, b.health, "health replicated")
	check_eq(c.phase, b.phase, "phase replicated")
	check(c.engaged, "engaged replicated")
	check_eq(c._last_health, c.health, "the first snapshot is not shown as a hit")
	check(c._seen_alive, "a living boss is marked as seen alive")
	_end()


func test_returns_when_fallen_or_lost() -> void:
	if not _begin():
		return
	var sim := SimWorld.new()
	var p := _player(sim, 7, Vector3(0, 0, 8))
	var b := _boss(sim)
	_tick(sim, b, 0.5)
	b.global_position = Vector3(3, -60, 0)
	_tick(sim, b, 0.1)
	check(b.global_position.distance_to(b.spawn_point) < 2.0, "a boss that fell out of the arena returns to its spawn")
	b.global_position = Vector3(b.arena_radius * 3.0, 0, 0)
	_tick(sim, b, 0.1)
	check(b.global_position.distance_to(b.spawn_point) < 2.0, "a boss far outside its arena returns")
	# Leash: chasing a player at the arena's edge, it does not walk out of it.
	p.global_position = Vector3(b.arena_radius * 1.5, 0, 0)
	_tick(sim, b, 12.0)
	var out := Vector2(b.global_position.x - b.spawn_point.x, b.global_position.z - b.spawn_point.z).length()
	check(out < b.arena_radius * 1.3, "leashed to the arena (%.1f m out, arena %.0f m)" % [out, b.arena_radius])
	_end()
