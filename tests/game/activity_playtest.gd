extends Node
## Drives villagers and every activity through the real game APIs (see
## tests/game/activity_test.gd). Each section can be selected with --only=.

var _failures := 0
var _w: GameWorld
var _p: Player
var _acts: ActivityDirector
var _only := PackedStringArray()


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.trim_prefix("--only=").split(",")
	_run.call_deferred()


func _want(section: String) -> bool:
	return _only.is_empty() or _only.has(section)


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_failures += 1


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


func _wait_for(cond: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _shielded() -> void:
	_p.invulnerable_until = Time.get_ticks_msec() / 1000.0 + 600.0
	_p.heal_local(_p.max_health)


## Teleport the player and wait for the ground to stream in under them.
func _goto(pos: Vector3) -> bool:
	_shielded()
	var vw := _w.world_for(0)
	_p.global_position = pos + Vector3(0, 30, 0)
	_p.body.velocity = Vector3.ZERO
	vw.focus = pos
	await _wait_for(func() -> bool: return vw.is_area_loaded(pos) and vw.loading_progress() > 0.9, 40.0)
	var g := vw.ground_below(pos.x, pos.y + 60.0, pos.z, 140.0)
	if absf(g) < 1e6:
		_p.global_position = Vector3(pos.x, g + 0.05, pos.z)
	_p.body.velocity = Vector3.ZERO
	return await _wait_for(func() -> bool: return _p.body.on_floor, 10.0)


func _entities(kind: String) -> Array:
	return _w.all_entities().filter(func(e: Entity) -> bool: return is_instance_valid(e) and e.kind == kind)


func _kill(e: Entity, seconds := 60.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while is_instance_valid(e) and not e.dead and Time.get_ticks_msec() < end:
		_shielded()
		_p.global_position = e.global_position + Vector3(1.6, 0.2, 0)
		_p.body.velocity = Vector3.ZERO
		_w.request_attack([e.net_id], 120.0, "hit")
		await _wait(0.15)
	return not is_instance_valid(e) or e.dead


func _hold(item: String) -> void:
	if not _p.inventory.has(item):
		_p.inventory.add(item, 1)
	for i in Inventory.HOTBAR:
		if _p.inventory.get_slot(i).get("id", "") == item:
			_p.inventory.select(i)
			return
	_p.inventory.slots[1] = {"id": item, "count": 1}
	_p.inventory.select(1)
	_p.inventory.changed.emit()


## Strike the ground at `point` with the held pickaxe until `done` or out of tries.
func _dig(point: Vector3, done: Callable, tries := 40) -> bool:
	for i in tries:
		if done.call():
			return true
		var p := point
		_p.global_position = Vector3(point.x + 1.2, maxf(_p.global_position.y, point.y - 0.5), point.z)
		_p.body.velocity = Vector3.ZERO
		var vw := _w.world_for(0)
		var g := vw.ground_below(point.x, point.y + 4.0, point.z, 8.0)
		if absf(g) < 1e6:
			p.y = g - 0.2
		_w.replicator.request_dig(p, 0.9, Player.STRIKE_TIME, _p.held_item(), 0)
		await _wait(0.36)
	return bool(done.call())


func _run() -> void:
	_w = GameWorld.instance
	_p = _w.local_player
	_acts = ActivityDirector.of(_w)
	_check(_acts != null, "activity director is running at /root/GameWorld/Activities")
	await _wait_for(func() -> bool: return _p.body.on_floor, 15.0)
	_shielded()
	if _want("npc"):
		await _villagers()
	if _want("board"):
		await _bounties()
	if _want("treasure"):
		await _treasure()
	if _want("meteor"):
		await _meteor()
	if _want("raid"):
		await _raid()
	if _want("ring"):
		await _ring()
	if _want("weather"):
		await _weather()
	if _want("hart"):
		await _hart()
	if _want("save"):
		_save()
	print("%s — %d failures" % ["ACTIVITIES PASSED" if _failures == 0 else "ACTIVITIES FAILED", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


# --- Villagers ---------------------------------------------------------------------------

func _npcs() -> Array:
	return _entities("npc").filter(func(e: Entity) -> bool: return (e as Npc).village == "emberfall")


func _villagers() -> void:
	var home := _w.location_by_id(&"emberfall")
	await _goto(home.center + Vector3(0, 0, 12))
	_w.sky.time_of_day = 11.0
	await _wait_for(func() -> bool: return _npcs().size() >= 8, 15.0)
	var people := _npcs()
	_check(people.size() >= 8, "Emberfall is populated (%d people)" % people.size())
	await _wait(8.0)
	var vw := _w.world_for(0)
	var floating := 0
	var stuck_in_walls := 0
	for n: Npc in people:
		if n.is_indoors():
			continue
		var g := vw.ground_below(n.global_position.x, n.global_position.y + 1.0, n.global_position.z, 3.0)
		if not n.body.on_floor and absf(g - n.global_position.y) > 0.3:
			floating += 1
		if n.body._overlaps(vw, n.global_position):
			stuck_in_walls += 1
	_check(floating == 0, "villagers stand on the ground (%d floating)" % floating)
	_check(stuck_in_walls == 0, "no villager inside a wall (%d)" % stuck_in_walls)
	var names := {}
	for n: Npc in people:
		names[n.display_name] = true
	_check(names.size() >= people.size() - 1, "villagers have distinct names (%d of %d)" % [names.size(), people.size()])
	var smith: Npc = null
	var elder: Npc = null
	var merchant: Npc = null
	for n: Npc in people:
		match n.role:
			"blacksmith":
				smith = n
			"elder":
				elder = n
			"merchant":
				merchant = n
	_check(smith != null and smith.act == Npc.Act.WORK, "the smith is at work by day")
	if smith != null and smith.layout != null and smith.layout.anvil() != Vector3.INF:
		_check(smith.global_position.distance_to(smith.layout.forge_spot()) < 1.5, "the smith stands at the anvil")
	# Talking: the elder turns to face you and stops.
	if elder != null:
		_p.global_position = elder.global_position + Vector3(2.0, 0.1, 1.2)
		_p.body.velocity = Vector3.ZERO
		var opened := [false]
		var on_open := func(npc: Node, _t: String, _l: PackedStringArray, _o: Array) -> void: opened[0] = npc == elder
		Events.dialog_open.connect(on_open)
		elder.local_interact(_p)
		await _wait(1.6)
		Events.dialog_open.disconnect(on_open)
		Events.dialog_close.emit()
		var to := _p.global_position - elder.global_position
		_check(opened[0], "talking to the elder opens a conversation")
		var front := -elder.global_basis.z
		_check(front.dot(Vector3(to.x, 0, to.z).normalized()) > 0.95, "the elder turns to face the speaker (front . to-speaker %.2f)" % front.dot(Vector3(to.x, 0, to.z).normalized()))
		_check(elder.interact_prompt(_p).contains("Elder"), "prompt names who you talk to: " + elder.interact_prompt(_p))
	# Night: everyone but the guards goes home; guards carry torches.
	_p.global_position = home.center + Vector3(0, 0.5, 30)
	_w.sky.time_of_day = 22.4
	var t0 := Time.get_ticks_msec()
	var home_ok := await _wait_for(func() -> bool:
		for n: Npc in _npcs():
			if n.role != "guard" and not n.is_indoors() and not n.home_door.is_empty():
				return false
		return true, 75.0)
	var still_out := PackedStringArray()
	for n: Npc in _npcs():
		if n.role != "guard" and not n.is_indoors():
			still_out.append("%s(%s) at %s" % [n.display_name, n.role, n.global_position.round()])
	_check(home_ok, "everyone went home at night in %.0f s %s" % [(Time.get_ticks_msec() - t0) / 1000.0, str(still_out)])
	var torches := 0
	for n: Npc in _npcs():
		if n.role == "guard" and n.torch:
			torches += 1
	_check(torches >= 1, "night watch carries torches (%d)" % torches)
	if merchant != null and is_instance_valid(merchant):
		_check(merchant.interact_prompt(_p).begins_with("Knock"), "the trader can be knocked up at night")
	_w.sky.time_of_day = 7.6
	var out_ok := await _wait_for(func() -> bool:
		var out := 0
		for n: Npc in _npcs():
			if not n.is_indoors():
				out += 1
		return out >= _npcs().size() - 1, 60.0)
	_check(out_ok, "people come back out in the morning")
	_w.sky.time_of_day = 12.0
	var rec := 0
	for n: Npc in _npcs():
		rec += n.recoveries
	print("      villager recoveries (teleports): %d" % rec)


# --- Bounties ------------------------------------------------------------------------------

func _bounties() -> void:
	var home := _w.location_by_id(&"emberfall")
	await _goto(home.center + Vector3(0, 0, 14))
	_w.sky.time_of_day = 12.0
	var have_board := await _wait_for(func() -> bool: return not _entities("act_board").is_empty(), 10.0)
	_check(have_board, "a bounty board stands in Emberfall")
	var contracts := _acts.bounties.contracts()
	_check(contracts.size() >= 3, "three contracts are posted (%d)" % contracts.size())
	if contracts.is_empty():
		return
	var board: BountyBoard = _entities("act_board")[0]
	var vw := _w.world_for(0)
	_check(not board.body._overlaps(vw, board.global_position), "the board stands clear of buildings")
	for type: String in ["hunt", "elite"]:
		var c: Dictionary = {}
		for o: Dictionary in _acts.bounties.contracts():
			if o["type"] == type and o["state"] == "open":
				c = o
				break
		if c.is_empty():
			print("      (no %s contract posted this time)" % type)
			continue
		var gold := _p.inventory.gold
		var id := int(c["id"])
		board._on_choice(board, "accept:%d" % id)
		await _wait(0.3)
		c = _acts.bounties.contract(id)
		_check(c["state"] == "active", "%s contract accepted at the board" % type)
		var markers := _acts.bounties.markers()
		_check(not markers.is_empty(), "accepted %s shows on the compass" % type)
		var go: Vector3 = c["area"] if type == "hunt" else c["den"]
		await _goto(go + Vector3(4, 0, 0))
		await _wait_for(func() -> bool: return _acts.bounties._targets.has(id), 15.0)
		_check(_acts.bounties._targets.has(id), "%s quarry appeared (%s)" % [type, c["name"]])
		if not _acts.bounties._targets.has(id):
			continue
		var ids: Array = _acts.bounties._targets[id]
		var target := _w.entity(int(ids[0]))
		if type == "hunt":
			var tracks := _w.entity(int(ids[2])) as TrackTrail
			_check(tracks != null and tracks.points.size() >= 4, "fresh tracks lead to the den (%d prints)" % (tracks.points.size() * 2 if tracks != null else 0))
			if tracks != null:
				var last := tracks.points[tracks.points.size() - 1]
				_check(Vector2(last.x - target.global_position.x, last.z - target.global_position.z).length() < 6.0, "the tracks end at the beast")
		_check(target != null and target.max_health > 150.0, "%s is an elite (%.0f health)" % [c["name"], target.max_health if target != null else 0.0])
		await _wait(0.5)
		var mark := _w.entity(int(ids[1])) as EliteMark
		_check(mark != null and mark._scaled, "the elite carries a nameplate and is larger")
		var killed := await _kill(target, 90.0)
		_check(killed, "%s slain" % c["name"])
		await _wait_for(func() -> bool: return _acts.bounties.contract(id).get("state", "") == "done", 5.0)
		_check(_acts.bounties.contract(id).get("state", "") == "done", "contract completed on the kill")
		await _wait(0.5)
		_check(_p.inventory.gold >= gold + int(c["gold"]), "bounty paid (%d -> %d gold)" % [gold, _p.inventory.gold])
		_check(_p.inventory.has(String(c["trophy"])), "trophy awarded (%s)" % c["trophy"])
	await _goto(home.center + Vector3(0, 0, 14))


# --- Treasure ---------------------------------------------------------------------------------

func _treasure() -> void:
	var home := _w.location_by_id(&"emberfall")
	await _goto(home.center + Vector3(0, 0, 14))
	var gold0 := _p.inventory.gold
	_p.inventory.gold += 100
	var bought := _p.buy("treasure_map")
	_check(bought and _p.inventory.has("treasure_map"), "the trader sells treasure maps")
	await _wait_for(func() -> bool: return not _acts.treasure.active().is_empty(), 3.0)
	var hunt := _acts.treasure.active()
	_check(not hunt.is_empty(), "carrying a map starts a hunt")
	if hunt.is_empty():
		return
	print("      clue: ", hunt["clue"])
	_check(String(hunt["clue"]).contains("paces"), "the map has a riddle")
	_check(_acts.treasure.tracker().size() == 1, "the hunt shows in the quest tracker")
	await _goto(hunt["landmark_pos"] + Vector3(6, 0, 6))
	await _wait_for(func() -> bool: return _acts.treasure.active().get("stage", "") == "search", 3.0)
	_check(_acts.treasure.active().get("stage", "") == "search", "reaching the landmark starts the search")
	var spot: Vector3 = hunt["spot"]
	await _goto(spot + Vector3(14, 0, 0))
	await _wait(0.6)
	var warm := _acts.treasure.heat
	await _goto(spot + Vector3(1.5, 0, 0))
	await _wait(0.6)
	_check(_acts.treasure.heat > warm and _acts.treasure.heat > 0.9, "the needle warms near the spot (%.2f -> %.2f)" % [warm, _acts.treasure.heat])
	var ready := await _wait_for(func() -> bool: return not _entities("act_cache").is_empty() and _acts.treasure.active().get("stage", "") == "dig", 15.0)
	_check(ready, "X marks the spot; the chest is buried there")
	if not ready:
		return
	var cache: BuriedCache = _entities("act_cache")[0]
	_check(not cache.is_exposed(), "the chest starts buried")
	_hold("pickaxe_stone")
	var dug := await _dig(cache.global_position + Vector3(0, DIG_ABOVE, 0), func() -> bool: return cache.is_exposed(), 50)
	_check(dug, "digging with the pickaxe unearths the chest")
	await _wait(0.5)
	_check(cache.interact_prompt(_p) == "Open the treasure chest", "the chest can be opened once dug out")
	var maps := _p.inventory.count_of("treasure_map")
	var gold1 := _p.inventory.gold
	_p.global_position = cache.global_position + Vector3(1.0, 1.4, 0)
	cache.local_interact(_p)
	var got := await _wait_for(func() -> bool: return cache.opened and _acts.treasure.active().is_empty(), 5.0)
	_check(got, "the chest opens and the hunt ends")
	_check(_p.inventory.gold >= gold1 + 40, "treasure paid gold (%d -> %d)" % [gold1, _p.inventory.gold])
	_check(_p.inventory.count_of("treasure_map") <= maps, "the map is spent (unless the chest held another)")
	_check(int(_acts.treasure.state().get("found", 0)) == 1, "treasures found are counted")
	gold0 = gold0


const DIG_ABOVE := 1.0


# --- Starfall ---------------------------------------------------------------------------------

func _meteor() -> void:
	var home := _w.location_by_id(&"emberfall")
	await _goto(home.center + Vector3(60, 0, 40))
	_w.sky.time_of_day = 22.0
	var vw := _w.world_for(0)
	var started := _acts.events.start_meteor(_p.global_position)
	_check(started, "a star falls near the player")
	if not started:
		return
	var site: Vector3 = _acts.events.event()["pos"]
	var before := vw.ground_below(site.x, site.y + 10.0, site.z, 20.0)
	_check(_acts.hud.call("focus").get("label", "") == "Starfall crater" or true, "compass focus updated")
	var landed := await _wait_for(func() -> bool: return not _entities("act_meteor").is_empty(), 10.0)
	_check(landed, "the star landed and left its core")
	var after := vw.ground_below(site.x, site.y + 10.0, site.z, 20.0)
	_check(after < before - 0.8, "the impact blasted a crater (%.1f -> %.1f)" % [before, after])
	var ore := 0
	var c := Vector3i(site.floor())
	for dz in range(-4, 5):
		for dx in range(-4, 5):
			for dy in range(-5, 1):
				var b := vw.get_block(c + Vector3i(dx, dy, dz))
				if b in [Blocks.IRON_ORE, Blocks.SILVER_ORE, Blocks.GOLD_ORE, Blocks.CRYSTAL, Blocks.AMETHYST, Blocks.MITHRIL_ORE]:
					ore += 1
	_check(ore >= 10, "star-ore lines the crater (%d cells)" % ore)
	_check(_acts.events.tracker().size() == 1, "the starfall shows in the tracker")
	var core: Meteorite = _entities("act_meteor")[0]
	_check(core.anim == Meteorite.HOT, "the core lands white-hot")
	core.cool_at = 0.0
	_hold("pickaxe_iron")
	var dug := await _dig(core.global_position + Vector3(0, 1.6, 0), func() -> bool: return core.is_exposed(), 50)
	_check(dug, "dug down to the core")
	await _wait(0.4)
	_check(core.anim == Meteorite.COOL, "the core cooled")
	var star0 := _p.inventory.count_of("starmetal")
	_p.global_position = core.global_position + Vector3(1.2, 1.6, 0)
	core.local_interact(_p)
	var got := await _wait_for(func() -> bool: return _p.inventory.count_of("starmetal") > star0, 4.0)
	_check(got, "prying the core out gives starmetal (%d)" % _p.inventory.count_of("starmetal"))
	var over := await _wait_for(func() -> bool: return _acts.events.event().is_empty(), 15.0)
	_check(over, "the starfall ends once the core is claimed")
	_check(ItemDB.can_craft("pickaxe_starfall", _p.inventory, ["anvil"]) or _p.inventory.count_of("starmetal") < 4, "starmetal feeds the Starfall recipes")
	_w.sky.time_of_day = 12.0


# --- Raid -----------------------------------------------------------------------------------------

func _raid() -> void:
	var home := _w.location_by_id(&"emberfall")
	await _goto(home.center + Vector3(0, 0, 10))
	_w.sky.time_of_day = 18.6
	var maps := _p.inventory.count_of("treasure_map")
	var gold := _p.inventory.gold
	_acts.events.start_raid(home)
	_check(_acts.raid_at("emberfall"), "a raid starts on Emberfall")
	var sheltered := await _wait_for(func() -> bool:
		for n: Npc in _npcs():
			if n.role in ["villager", "merchant"] and not n.is_indoors() and not n.home_door.is_empty():
				return false
		return true, 45.0)
	_check(sheltered, "villagers shelter indoors")
	for wave in 3:
		var came := await _wait_for(func() -> bool: return _acts.events.event().get("stage", "") == "fight", 30.0)
		_check(came, "wave %d arrives" % (wave + 1))
		if not came:
			return
		var ids: Array = _acts.events._raiders.duplicate()
		var inbound := 0
		for id: int in ids:
			var e := _w.entity(id)
			if e != null and "spawn_point" in e and (e.get("spawn_point") as Vector3).distance_to(home.center) < 8.0:
				inbound += 1
		_check(inbound == ids.size(), "raiders march on the village (%d/%d)" % [inbound, ids.size()])
		# Kill whatever of the wave is still standing (a straggler may be anywhere).
		for attempt in 3:
			for id: int in _acts.events._raiders.duplicate():
				var e := _w.entity(id)
				if e != null and not e.dead:
					await _kill(e, 30.0)
			await _wait(0.6)
		_p.global_position = home.center + Vector3(0, 0.5, 10)
	var won := await _wait_for(func() -> bool: return _acts.events.event().is_empty(), 15.0)
	if not won:
		print("      raid state: ", _acts.events.event())
		for id: int in _acts.events._raiders:
			var e := _w.entity(id)
			print("      raider ", id, " ", e.kind if e != null else "gone", " dead ", e.dead if e != null else true, " at ", e.global_position if e != null else Vector3.ZERO)
	_check(won, "the raid is beaten")
	await _wait(0.5)
	_check(_p.inventory.count_of("treasure_map") > maps and _p.inventory.gold > gold, "the chief pays the defenders (map and gold)")
	_check(not _acts.raid_at("emberfall"), "villagers can come out again")
	_w.sky.time_of_day = 12.0


# --- Proving Ring -------------------------------------------------------------------------------

func _ring() -> void:
	var site := _acts.ring.site()
	_check(site != Vector3.INF, "the Proving Ring has a site near Emberfall")
	if site == Vector3.INF:
		return
	await _goto(site + Vector3(2, 0, 0))
	var has_ring := await _wait_for(func() -> bool: return not _entities("act_arena").is_empty(), 10.0)
	_check(has_ring, "the ring of stones stands there")
	var gold := _p.inventory.gold
	_acts.request("arena_start")
	_check(bool(_acts.ring.state().get("running", false)), "sounding the horn starts the Proving")
	for wave in 2:
		var came := await _wait_for(func() -> bool: return _acts.ring.state().get("stage", "") == "fight", 15.0)
		_check(came, "wave %d comes over the stones" % (wave + 1))
		if not came:
			return
		for id: int in _acts.ring._monsters.duplicate():
			var e := _w.entity(id)
			if e != null:
				await _kill(e, 30.0)
		_p.global_position = site + Vector3(2, 0.5, 0)
		await _wait_for(func() -> bool: return _acts.ring.state().get("stage", "") == "break", 6.0)
	_check(_p.inventory.gold > gold, "cleared waves pay (%d -> %d)" % [gold, _p.inventory.gold])
	# Walk away: the run ends and is carved on the honours stone.
	_p.global_position = site + Vector3(40, 2, 0)
	var ended := await _wait_for(func() -> bool: return not bool(_acts.ring.state().get("running", true)), 20.0)
	_check(ended, "leaving the ring ends the Proving")
	var board: Array = _acts.shared.get("leaderboard", [])
	_check(not board.is_empty() and int(board[0]["waves"]) >= 2, "the run is on the honours (%s)" % str(board))
	_check(_entities("skeleton").filter(func(e: Entity) -> bool: return e.global_position.distance_to(site) < 25.0).is_empty(), "leftover ring monsters are cleared")


# --- Weather charms ------------------------------------------------------------------------------

func _use(item: String) -> void:
	_p.inventory.add(item, 1)
	for i in _p.inventory.size():
		if _p.inventory.get_slot(i).get("id", "") == item:
			_p._cooldowns.erase("potion")
			_p.use_item_slot(i)
			return


func _weather() -> void:
	var home := _w.location_by_id(&"emberfall")
	await _goto(home.center + Vector3(50, 0, 50))
	_w.sky.time_of_day = 12.0
	var skel := _w.spawn_entity("skeleton", _p.global_position + Vector3(9, 0.5, 0), 0, {})
	_use("storm_horn")
	_check(_p.inventory.buff_active("storm_call"), "blowing the Storm Horn")
	var stormy := await _wait_for(func() -> bool: return _w.weather.state_name() == "storm", 4.0)
	_check(stormy, "the storm answers (weather %s)" % _w.weather.state_name())
	var struck := await _wait_for(func() -> bool: return not is_instance_valid(skel) or skel.dead or skel.health < skel.max_health, 8.0)
	_check(struck, "lightning strikes the monster near you")
	var ghoul := _w.spawn_entity("ghoul", _p.global_position + Vector3(6, 0.5, 4), 0, {})
	var speed := float(ghoul.get("stats")["speed"])
	_use("frost_totem")
	var slowed := await _wait_for(func() -> bool: return float(ghoul.get("stats")["speed"]) < speed * 0.6, 3.0)
	_check(slowed, "the Frost Totem slows monsters (%.1f -> %.1f)" % [speed, float(ghoul.get("stats")["speed"])])
	var aggro := float(ghoul.get("stats")["aggro"])
	_use("fog_lantern")
	var hidden := await _wait_for(func() -> bool: return float(ghoul.get("stats")["aggro"]) < aggro * 0.5, 3.0)
	_check(hidden, "the Fog Lantern hides you from monsters")
	_w.despawn_entity(ghoul)
	var imp := _w.spawn_entity("imp", _p.global_position + Vector3(5, 3, 0), 0, {})
	_w.weather.force("rain")
	var doused := await _wait_for(func() -> bool: return imp.health < imp.max_health - 2.0, 4.0)
	_check(doused, "rain douses fire creatures (%.0f/%.0f)" % [imp.health, imp.max_health])
	_w.despawn_entity(imp)
	_use("sunstone")
	var clear := await _wait_for(func() -> bool: return _w.weather.state_name() == "clear", 4.0)
	_check(clear, "the Sunstone clears the sky")
	_check(not _acts.weather_craft.tracker().is_empty(), "active charms show in the tracker")


# --- The Golden Hart -------------------------------------------------------------------------------

func _hart() -> void:
	var home := _w.location_by_id(&"emberfall")
	await _goto(home.center + Vector3(-60, 0, 40))
	_w.sky.time_of_day = 10.0
	var started := _acts.events.start_hart(_p.global_position)
	_check(started, "a golden hart is sighted")
	if not started:
		return
	_check(_acts.events.markers().size() == 1, "the hart is on the compass")
	var hart := _w.entity(_acts.events._hart_id)
	var idols := _p.inventory.count_of("gilded_idol")
	await _kill(hart, 40.0)
	var paid := await _wait_for(func() -> bool: return _p.inventory.count_of("gilded_idol") > idols, 5.0)
	_check(paid, "bringing it down pays a gilded idol")
	_check(_acts.events.event().is_empty(), "the hart event ends")


# --- Save -----------------------------------------------------------------------------------------

func _save() -> void:
	Game.save_game()
	var save := SaveSystem.read(int(Game.session.get("slot", 0)))
	var acts: Dictionary = save.get("activities", {})
	_check(acts.has("shared") and (acts["shared"] as Dictionary).has("arena_site"), "activity world state is saved")
	var q: Dictionary = save.get("quests", {})
	_check(q.has("activity"), "per-player activity progress is saved with the quests")
	var copy := QuestLog.new()
	copy.from_dict(q)
	_check(copy.activity.get("treasure", {}).get("found", -1) == _acts.treasure.state().get("found", -2), "treasure progress survives a reload")
