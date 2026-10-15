extends TestCase
## Villagers on a synthetic village (flat smooth ground, two houses built from
## invisible STRUCTURE collision like the real modelled houses, a forge):
## door detection, route planning around buildings, day/night routines (home
## at night, forge and stall by day), facing whoever talks to them, recovering
## from falls and walls without popping in front of players, smooth turning,
## guards defending during raids, dialogue markers/options and what clients
## see. Skipped when autoloads are missing.

const GROUND := 10          ## ground surface height (cells below are solid)
const MIN_C := Vector3i(-3, 0, -3)
const MAX_C := Vector3i(3, 1, 3)


class Sim:
	extends RefCounted
	var now := 0.0
	var hour := 12.0
	var vw: VoxelWorld
	var loc: Location
	var players: Array = []
	var entities: Array = []
	var raid := false
	var damage_dealt := 0.0

	func world_for(_dim: int) -> VoxelWorld:
		return vw

	func location_by_id(id: StringName) -> Location:
		return loc if loc != null and loc.id == id else null

	func time_of_day() -> float:
		return hour

	func raid_at(_village: String) -> bool:
		return raid

	func nearest_player(pos: Vector3, _dim: int, max_dist: float) -> Variant:
		var best: Variant = null
		var bd := max_dist
		for p: Node3D in players:
			var d := p.global_position.distance_to(pos)
			if d < bd:
				bd = d
				best = p
		return best

	func entity(id: int) -> Variant:
		for e: Node3D in players + entities:
			if e.net_id == id:
				return e
		return null

	func entities_near(pos: Vector3, radius: float, _dim: int, team := -1) -> Array:
		var out: Array = []
		for e: Node3D in players + entities:
			if e.dead or (team >= 0 and e.team != team):
				continue
			if e.global_position.distance_to(pos) <= radius:
				out.append(e)
		return out

	func damage(target: Node3D, amount: float, source_id: int, kind := "hit") -> void:
		damage_dealt += target.take_damage(amount, source_id, kind)


func _tree() -> SceneTree:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root.get_node_or_null("Events") == null:
		return null
	return tree


## Flat grass world with the village blueprint stamped in.
func _make_world(bp: Blueprint) -> VoxelWorld:
	var vw := VoxelWorld.new()
	for cx in range(MIN_C.x, MAX_C.x):
		for cy in range(MIN_C.y, MAX_C.y + 1):
			for cz in range(MIN_C.z, MAX_C.z):
				var key := Vector3i(cx, cy, cz)
				var data := Chunk.empty()
				var dens := Chunk.empty()
				for i in Chunk.VOLUME:
					var y := cy * 16 + i / Chunk.AREA
					if y < GROUND:
						data[i] = Blocks.GRASS
						dens[i] = 255
				vw._chunks[key] = data
				vw._density[key] = dens
	if bp != null:
		for y in bp.size.y:
			for z in bp.size.z:
				for x in bp.size.x:
					var v := bp.get_local(x, y, z)
					if v == Blueprint.KEEP:
						continue
					var p := bp.origin + Vector3i(x, y, z)
					_put(vw, p, Blocks.AIR if v == Blueprint.CARVE else v, 0 if v == Blueprint.CARVE else (230 if p.y < GROUND else 0))
	return vw


func _put(vw: VoxelWorld, p: Vector3i, block: int, density: int) -> void:
	var key := Chunk.key_of(p)
	if not vw._chunks.has(key):
		return
	var l := Chunk.local(p)
	var i := Chunk.index(l.x, l.y, l.z)
	var data: PackedByteArray = vw._chunks[key]
	var dens: PackedByteArray = vw._density[key]
	data[i] = block
	dens[i] = density
	vw._chunks[key] = data
	vw._density[key] = dens
	vw._fk = Vector3i(1 << 20, 0, 0)


## A house: STRUCTURE floor, walls and roof, carved interior, a door facing +z.
func _house(bp: Blueprint, x0: int, z0: int, w: int, d: int, wall_h: int, door_w: int) -> void:
	var x1 := x0 + w - 1
	var z1 := z0 + d - 1
	var s := Blocks.STRUCTURE
	bp.fill(Vector3i(x0, GROUND - 1, z0), Vector3i(x1, GROUND - 1, z1), s)
	bp.fill(Vector3i(x0, GROUND, z0), Vector3i(x1, GROUND + wall_h - 1, z1), s)
	bp.fill(Vector3i(x0 + 1, GROUND, z0 + 1), Vector3i(x1 - 1, GROUND + wall_h - 1, z1 - 1), Blueprint.CARVE)
	bp.fill(Vector3i(x0 - 1, GROUND + wall_h, z0 - 1), Vector3i(x1 + 1, GROUND + wall_h, z1 + 1), s)
	var cx := x0 + w / 2
	var dh := 3 if door_w > 1 else 2
	bp.fill(Vector3i(cx - door_w / 2, GROUND, z1), Vector3i(cx + door_w / 2, GROUND + dh - 1, z1), Blueprint.CARVE)
	# A window (must not be mistaken for a door).
	bp.set_local(x0, GROUND + 1, z0 + 2, Blueprint.CARVE)


func _village() -> Location:
	var loc := Location.new(&"testville", "Testville", Location.Kind.VILLAGE, Vector3(12, GROUND, 18))
	var bp := Blueprint.new(Vector3i(0, 0, 0), Vector3i(40, 24, 40))
	_house(bp, 2, 2, 7, 6, 4, 1)      # door at (5, z=7)
	_house(bp, 15, 0, 11, 9, 5, 3)    # the hall, door at (20, z=8)
	loc.blueprints.append(bp)
	loc.add_spawn("station", Vector3(11.5, GROUND, 14.5), {"station": "anvil"})
	loc.add_spawn("npc", Vector3(7.5, GROUND, 16.5), {"role": "merchant"})
	loc.add_spawn("guard_post", Vector3(12.5, GROUND, 19.5), {})
	VillageLayout.forget(loc.id)
	return loc


func _sim() -> Sim:
	var s := Sim.new()
	s.loc = _village()
	s.vw = _make_world(s.loc.blueprints[0])
	NpcNav.forget_cache()
	return s


func _npc(s: Sim, arena: Node3D, role: String, pos: Vector3, seed_value := 3, id := 40) -> Npc:
	var n := Npc.new()
	n.sim_world = s
	n.net_id = id
	n.position = pos
	arena.add_child(n)
	n.on_spawned({"role": role, "village": "testville", "seed": seed_value})
	s.entities.append(n)
	return n


func _player(arena: Node3D, pos: Vector3, id := -1) -> Node3D:
	var p: Node3D = load("res://entities/entity.gd").new()
	p.team = Entity.Team.PLAYERS
	p.net_id = id
	arena.add_child(p)
	p.global_position = pos
	return p


## Runs `seconds` of simulation; returns the worst per-tick jump and turn.
func _run(s: Sim, npcs: Array, seconds: float, dt := 1.0 / 30.0) -> Vector2:
	var worst := Vector2.ZERO
	var t := 0.0
	while t < seconds:
		t += dt
		s.now += dt
		for n: Npc in npcs:
			var before := n.global_position
			var yaw0 := n.yaw
			var rec := n.recoveries
			var was_in := n.is_indoors()
			n.server_tick(dt)
			if n.recoveries == rec and was_in == n.is_indoors():
				worst.x = maxf(worst.x, Vector2(n.global_position.x - before.x, n.global_position.z - before.z).length())
				worst.y = maxf(worst.y, absf(angle_difference(yaw0, n.yaw)))
	return worst


## Humanoid models look down their local -Z (like every creature model).
func _front(n: Node3D) -> Vector3:
	return -n.global_basis.z


func _overlapping(n: Npc, vw: VoxelWorld) -> bool:
	return n.body._overlaps(vw, n.global_position)


# --- Tests -------------------------------------------------------------------------

func test_doors_found_from_building_collision() -> void:
	var loc := _village()
	var lay := VillageLayout.of(loc)
	check_eq(lay.doors.size(), 2, "two doorways, the window ignored")
	var hall: Dictionary = {}
	var house: Dictionary = {}
	for d in lay.doors:
		if d["hall"]:
			hall = d
		else:
			house = d
	check(not hall.is_empty() and int(hall["width"]) == 3, "the 3-wide door is the hall")
	check(not house.is_empty(), "the cottage door is found")
	if house.is_empty() or hall.is_empty():
		return
	check_near((house["pos"] as Vector3).x, 5.5, 0.01, "cottage door x")
	check_near((house["pos"] as Vector3).z, 7.5, 0.01, "cottage door z")
	check((house["out"] as Vector3).dot(Vector3.BACK) > 0.99, "door opens towards +z (the street)")
	var inside: Vector3 = house["inside"]
	check(inside.z < 7.0 and inside.z > 2.5, "inside point is within the walls")
	check_eq(lay.home_door("elder", 1, Vector3.ZERO), hall, "the elder lives in the hall")
	check_eq(lay.home_door("villager", 7, Vector3.ZERO), house, "villagers live in the cottage")
	check(lay.forge_spot() != Vector3.INF and lay.forge_spot().distance_to(lay.anvil()) < 1.3, "smith stands at the anvil")


func test_route_around_a_house() -> void:
	var s := _sim()
	# Behind the cottage (north side) to its door (south side): the walls are in the way.
	var from := Vector3(5.5, GROUND, 0.5)
	var to := Vector3(5.5, GROUND, 8.9)
	check(not NpcNav.segment_clear(s.vw, 0, from, to), "straight line through the house is blocked")
	var q := NpcNav.plan(s.vw, 0, from, to, 30.0)
	var guard := 0
	while not NpcNav.step(q, 200) and guard < 100:
		guard += 1
	check(q.ok, "a route exists")
	check(q.path.size() >= 2, "route has corners (%d points)" % q.path.size())
	var prev := from
	var length := 0.0
	for p in q.path:
		check(NpcNav.segment_clear(s.vw, 0, prev, p), "each leg is walkable %s -> %s" % [prev, p])
		length += prev.distance_to(p)
		prev = p
	check(length < 22.0, "route is direct-ish (%.1f m)" % length)
	check(prev.distance_to(to) < 1.0, "route ends at the door")


func test_villager_goes_home_at_night_and_comes_out_in_the_morning() -> void:
	var tree := _tree()
	if tree == null:
		print("      (test_npc skipped: autoloads are not running)")
		return
	var s := _sim()
	var arena := Node3D.new()
	tree.root.add_child(arena)
	var n := _npc(s, arena, "villager", Vector3(9.5, GROUND, 17.5), 7)
	s.hour = 14.0
	var worst := _run(s, [n], 30.0)
	check(not n.is_indoors(), "out and about by day")
	check(n.body.on_floor and absf(n.global_position.y - GROUND) < 0.2, "stands on the ground by day (y %.2f)" % n.global_position.y)
	check(not _overlapping(n, s.vw), "never inside a wall")
	s.hour = 21.5
	var walked := 0.0
	var steps := 0
	var t := 0.0
	var prev := n.global_position
	while t < 60.0 and not n.is_indoors():
		_run(s, [n], 0.5)
		t += 0.5
		walked += prev.distance_to(n.global_position)
		prev = n.global_position
		check(not _overlapping(n, s.vw), "walking home never clips a wall (%s)" % n.global_position)
		steps += 1
	check(n.is_indoors(), "went indoors at night within a minute (%.0f s)" % t)
	check(walked > 2.0, "walked there rather than vanishing (%.1f m)" % walked)
	check(n.global_position.z < 7.0 and n.global_position.x > 2.0 and n.global_position.x < 8.0, "indoors means inside the cottage %s" % n.global_position)
	check_eq(n.interact_prompt(null), "", "nobody answers a villager's door at night")
	check_eq(n.recoveries, 0, "no teleports were needed")
	s.hour = 7.5
	_run(s, [n], 20.0)
	check(not n.is_indoors(), "came back out in the morning")
	check(n.global_position.z > 7.6, "walked out through the door %s" % n.global_position)
	check(worst.x < 0.2 and worst.y < 0.25, "smooth: max step %.2f m, max turn %.2f rad per tick" % [worst.x, worst.y])
	arena.queue_free()


func test_smith_works_the_anvil_by_day_and_merchant_keeps_stall() -> void:
	var tree := _tree()
	if tree == null:
		return
	var s := _sim()
	var arena := Node3D.new()
	tree.root.add_child(arena)
	var smith := _npc(s, arena, "blacksmith", Vector3(14.5, GROUND, 20.5), 4, 41)
	var merchant := _npc(s, arena, "merchant", Vector3(7.5, GROUND, 16.5), 5, 42)
	s.hour = 10.0
	var strikes := {}
	var t := 0.0
	while t < 25.0:
		_run(s, [smith, merchant], 0.25)
		t += 0.25
		if smith.act == Npc.Act.WORK:
			strikes[smith.anim_time] = true
	var lay := VillageLayout.of(s.loc)
	check(smith.global_position.distance_to(lay.forge_spot()) < 0.8, "smith at the anvil (%.2f m away)" % smith.global_position.distance_to(lay.forge_spot()))
	check_eq(smith.act, Npc.Act.WORK, "smith is working")
	check(strikes.size() >= 8, "hammer keeps falling (%d strikes)" % strikes.size())
	var to_anvil := lay.anvil() - smith.global_position
	check(_front(smith).dot(Vector3(to_anvil.x, 0, to_anvil.z).normalized()) > 0.95, "smith faces the anvil")
	check(merchant.global_position.distance_to(Vector3(7.5, GROUND, 16.5)) < 0.8 and merchant.act == Npc.Act.WORK, "merchant keeps the stall")
	check(merchant.interact_prompt(null).begins_with("Talk to"), "merchant talks by day")
	s.hour = 23.0
	_run(s, [smith, merchant], 45.0)
	check(smith.is_indoors() and merchant.is_indoors(), "both went home at night")
	check(merchant.interact_prompt(null).begins_with("Knock"), "the merchant can be knocked up at night")
	arena.queue_free()


func test_faces_whoever_talks_and_resumes() -> void:
	var tree := _tree()
	if tree == null:
		return
	var s := _sim()
	var arena := Node3D.new()
	tree.root.add_child(arena)
	var n := _npc(s, arena, "villager", Vector3(10.5, GROUND, 18.5), 9)
	s.hour = 12.0
	_run(s, [n], 6.0)
	var p := _player(arena, n.global_position + Vector3(2.0, 0, 1.0), -7)
	s.players = [p]
	n.server_interact(p)
	var start := n.global_position
	_run(s, [n], 1.5)
	var to := p.global_position - n.global_position
	check(_front(n).dot(Vector3(to.x, 0, to.z).normalized()) > 0.98, "turned to face the speaker (front . to-speaker %.2f)" % _front(n).dot(Vector3(to.x, 0, to.z).normalized()))
	check(n.global_position.distance_to(start) < 0.3, "stands still while talking")
	check_eq(n.act, Npc.Act.TALK, "talking")
	s.players = []
	p.global_position = Vector3(30, GROUND, 30)
	_run(s, [n], Npc.TALK_SECONDS + 15.0)
	check(n.act != Npc.Act.TALK, "goes back to their day")
	arena.queue_free()


func test_recovers_from_pits_and_walls_only_when_unobserved() -> void:
	var tree := _tree()
	if tree == null:
		return
	var s := _sim()
	var arena := Node3D.new()
	tree.root.add_child(arena)
	var n := _npc(s, arena, "villager", Vector3(12.5, GROUND, 22.5), 11)
	s.hour = 12.0
	_run(s, [n], 2.0)
	# Someone dug a deep pit under them.
	var at := Vector3i(n.global_position.floor())
	for y in range(GROUND - 12, GROUND):
		for z in range(at.z - 2, at.z + 3):
			for x in range(at.x - 2, at.x + 3):
				_put(s.vw, Vector3i(x, y, z), Blocks.AIR, 0)
	n.home = Vector3(at.x + 0.5, GROUND, at.z + 0.5)
	NpcNav.forget_cache()
	var watcher := _player(arena, Vector3(at.x + 0.5, GROUND, at.z + 8.0), -3)
	s.players = [watcher]
	_run(s, [n], 6.0)
	check(n.global_position.y < GROUND - 5.0, "fell into the pit while watched (no pop)")
	check_eq(n.recoveries, 0, "no teleport in front of a player")
	s.players = []
	_run(s, [n], 6.0)
	check(n.recoveries >= 1 and n.global_position.y > GROUND - 1.0, "climbed back home once nobody watched (y %.1f)" % n.global_position.y)
	# Walled in: STRUCTURE all around.
	var c := Vector3i(n.global_position.floor())
	for z in range(c.z - 2, c.z + 3):
		for x in range(c.x - 2, c.x + 3):
			if absi(x - c.x) == 2 or absi(z - c.z) == 2:
				for y in range(GROUND, GROUND + 3):
					_put(s.vw, Vector3i(x, y, z), Blocks.STRUCTURE, 0)
	NpcNav.forget_cache()
	var rec := n.recoveries
	_run(s, [n], 40.0)
	check(not _overlapping(n, s.vw), "never ends up inside the walls")
	check(n.recoveries >= rec, "handled being boxed in without errors")
	arena.queue_free()


func test_guards_defend_during_raids_and_villagers_shelter() -> void:
	var tree := _tree()
	if tree == null:
		return
	var s := _sim()
	var arena := Node3D.new()
	tree.root.add_child(arena)
	var guard := _npc(s, arena, "guard", Vector3(12.5, GROUND, 19.5), 2, 50)
	var villager := _npc(s, arena, "villager", Vector3(9.5, GROUND, 16.5), 7, 51)
	s.hour = 13.0
	_run(s, [guard, villager], 3.0)
	var monster: Node3D = load("res://entities/entity.gd").new()
	monster.team = Entity.Team.MONSTERS
	monster.net_id = 99
	monster.max_health = 500.0
	monster.health = 500.0
	arena.add_child(monster)
	s.entities.append(monster)
	s.raid = true
	var t := 0.0
	while t < 40.0:
		monster.global_position = guard.global_position + Vector3(1.2, 0, 0.4)
		_run(s, [guard, villager], 0.5)
		t += 0.5
	check(s.damage_dealt > 30.0, "guard fought the raider (%.0f damage)" % s.damage_dealt)
	check(villager.is_indoors(), "villager sheltered indoors during the raid")
	check(guard.torch == false, "no torch by day")
	s.raid = false
	s.hour = 22.0
	_run(s, [guard], 5.0)
	check(guard.torch and (guard.anim & Npc.TORCH_FLAG) != 0, "night patrol carries a torch (replicated)")
	arena.queue_free()


func test_people_do_not_walk_through_each_other() -> void:
	var tree := _tree()
	if tree == null:
		return
	var s := _sim()
	var arena := Node3D.new()
	tree.root.add_child(arena)
	var a := _npc(s, arena, "villager", Vector3(8.5, GROUND, 24.5), 21, 60)
	var b := _npc(s, arena, "villager", Vector3(18.5, GROUND, 24.5), 22, 61)
	s.hour = 12.0
	_run(s, [a, b], 0.2)
	a._goal_kind = "x"
	b._goal_kind = "x"
	a._set_goal(Vector3(18.5, GROUND, 24.5))
	b._set_goal(Vector3(8.5, GROUND, 24.5))
	var closest := INF
	var t := 0.0
	while t < 15.0:
		_run(s, [a, b], 0.1)
		t += 0.1
		closest = minf(closest, Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length())
	check(closest > 0.55, "kept their distance (closest %.2f m)" % closest)
	arena.queue_free()


func test_dialogue_markers_and_options() -> void:
	var q := QuestLog.new()
	q.accept("kindling")
	check_eq(NpcDialogue.marker(q, "elder", "emberfall"), "", "nothing to say while the shrine is unlit")
	q.on_event("interact", "shrine@emberfall_shrine")
	check_eq(NpcDialogue.marker(q, "elder", "emberfall"), "?", "elder waits for the hand-in")
	var d := NpcDialogue.build({"role": "elder", "village": "emberfall", "name": "Elder Maren"}, q)
	var ids := []
	for o: Dictionary in d["options"]:
		ids.append(o["id"])
	check(ids.has("turnin:kindling"), "hand-in offered")
	check(ids.back() == "bye", "farewell last")
	q.complete("kindling")
	check_eq(NpcDialogue.marker(q, "blacksmith", "emberfall"), "!", "smith has the next quest")
	check_eq(NpcDialogue.marker(q, "blacksmith", "ashford"), "", "other smiths don't")
	var smith := NpcDialogue.build({"role": "blacksmith", "village": "emberfall"}, q)
	var sids := []
	for o: Dictionary in smith["options"]:
		sids.append(o["id"])
	check(sids.has("accept:iron_in_the_deep") and sids.has("shop:blacksmith"), "smith offers the quest and the forge")
	for line in d["lines"] + smith["lines"]:
		check(String(line).length() <= 220, "lines stay short: " + String(line))
	var knock := NpcDialogue.build({"role": "merchant", "village": "ashford", "indoors": true}, q)
	check(String(knock["lines"][0]).begins_with("("), "night visits open at the door")


func test_clients_see_the_routine() -> void:
	var tree := _tree()
	if tree == null:
		return
	var s := _sim()
	var arena := Node3D.new()
	tree.root.add_child(arena)
	var n := _npc(s, arena, "guard", Vector3(12.5, GROUND, 19.5), 2, 70)
	s.hour = 22.0
	_run(s, [n], 3.0)
	var snap := n.snapshot()
	var copy := Npc.new()
	copy.net_id = 70
	arena.add_child(copy)
	copy.on_spawned({"role": "guard", "village": "testville", "seed": 2})
	copy.apply_snapshot(snap, 1.0)
	copy.act = copy.anim & Npc.ACT_MASK
	copy.torch = (copy.anim & Npc.TORCH_FLAG) != 0
	check(copy.torch, "client sees the night torch")
	check_eq(copy.display_name, n.display_name, "same name on every machine")
	var house := _npc(s, arena, "villager", Vector3(9.5, GROUND, 16.5), 7, 71)
	s.hour = 23.0
	_run(s, [house], 50.0)
	var hidden := Npc.new()
	hidden.net_id = 72
	arena.add_child(hidden)
	hidden.on_spawned({"role": "villager", "village": "testville", "seed": 7})
	hidden.apply_snapshot(house.snapshot(), 1.0)
	hidden.act = hidden.anim & Npc.ACT_MASK
	hidden._present(0.016)
	check(not hidden._model.visible, "indoors people are hidden on clients")
	arena.queue_free()
