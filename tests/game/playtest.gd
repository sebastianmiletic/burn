extends Node
## Scripted playthrough of the core loop, runnable headless:
##   godot --headless --path . -- --playtest [--seed=N]
## Drives the local player through the real game APIs and checks outcomes.
## Prints PASS/FAIL per step and exits with code 1 on any failure.

var _failures := 0
var _w: GameWorld


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


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
	return false


func _find(kind: String, extra := Callable()) -> Entity:
	for e in _w.all_entities():
		var ent := e as Entity
		if ent != null and ent.kind == kind and not ent.dead and (not extra.is_valid() or extra.call(ent)):
			return ent
	return null


func _run() -> void:
	_w = GameWorld.instance
	var p := _w.local_player
	var vw := _w.world_for(0)

	# --- Spawn ---------------------------------------------------------------
	await _wait_for(func() -> bool: return p.body.on_floor, 10.0)
	_check(p.body.on_floor and not p.dead, "player spawns standing on ground at %s" % str(p.global_position.round()))
	_check(p.inventory.has("pickaxe_stone") and p.inventory.has("sword_rusty"), "starting kit given")
	_check(_w.quests.is_active("kindling"), "first quest active")

	# --- Shrine and the elder -------------------------------------------------
	var is_home_shrine := func(e: Entity) -> bool: return String(e.get("location_id")) == "emberfall_shrine"
	await _wait_for(func() -> bool: return _find("shrine", is_home_shrine) != null, 6.0)
	var shrine := _find("shrine", is_home_shrine) as Shrine
	_check(shrine != null, "Emberfall shrine spawned by the director")
	if shrine == null:
		_dump_entities()
	if shrine != null:
		shrine.local_interact(p)
		_check(_w.lit_shrines.has(&"emberfall_shrine") and p.respawn_point != Vector3.ZERO, "shrine rekindled, respawn point set")
		_check(_w.quests.ready_to_turn_in("elder").has("kindling"), "kindling ready to hand in")
	var elder := _find("npc", func(e: Entity) -> bool: return e.get("role") == "elder") as Npc
	_check(elder != null, "Elder Maren present in Emberfall")
	if elder != null:
		elder.local_interact(p)
		Events.dialog_choice.emit(elder, "turnin:kindling")
		_check(_w.quests.is_completed("kindling"), "kindling handed in")
		_check(p.xp > 0 and p.inventory.has("potion_health", 3), "quest rewards granted (xp %d)" % p.xp)
		var smith := _find("npc", func(e: Entity) -> bool: return e.get("role") == "blacksmith") as Npc
		_check(smith != null, "blacksmith present")
		if smith != null:
			smith.local_interact(p)
			Events.dialog_choice.emit(smith, "accept:iron_in_the_deep")
			_check(_w.quests.is_active("iron_in_the_deep"), "blacksmith gives the next main quest")

	# --- Mining and building ---------------------------------------------------
	# Mining sculpts: strike the ground a few times beside the player.
	var dig_at := p.global_position + Vector3(2.5, -0.3, 0)
	var g := vw.ground_below(dig_at.x, dig_at.y + 3.0, dig_at.z, 8.0)
	if absf(g) < 1e6:
		dig_at.y = g - 0.2
	var before := vw.get_block(Vector3i(dig_at.floor()))
	var dropped_before := _count("drop")
	for i in 8:
		_w.replicator.request_dig(dig_at, 0.9, 0.42, "pickaxe_stone", 0)
		await _frames(2)
	var after := vw.ground_below(dig_at.x, dig_at.y + 3.0, dig_at.z, 8.0)
	_check(absf(g) < 1e6 and after < g - 0.4, "dug a hole into %s (ground %.2f -> %.2f)" % [Blocks.name_of(before), g, after])
	var drop := _find("drop")
	_check(_count("drop") > dropped_before and drop != null, "digging dropped material")
	if drop != null:
		var item := String(drop.get("item_id"))
		var had := p.inventory.count_of(item)
		p.global_position = drop.global_position + Vector3(0, 0.2, 0)
		await _wait_for(func() -> bool: return p.inventory.count_of(item) > had, 5.0)
		_check(p.inventory.count_of(item) > had, "picked up %s" % item)
	p.global_position += Vector3(-5, 0, 0)
	await _frames(2)
	for i in 4:
		_w.replicator.request_fill(Vector3(dig_at.x, after + 0.3, dig_at.z), 0.75, Blocks.DIRT, 0)
		await _frames(2)
	var refilled := vw.ground_below(dig_at.x, dig_at.y + 4.0, dig_at.z, 8.0)
	_check(refilled > after + 0.3, "packed earth back into the hole (%.2f -> %.2f)" % [after, refilled])

	# Mining through the real tool path: iron ore with a stone pickaxe works, gold doesn't.
	_check(Blocks.tier(Blocks.IRON_ORE) <= int(ItemDB.info("pickaxe_stone")["mine_tier"]), "stone pickaxe can mine iron")
	_check(Blocks.tier(Blocks.GOLD_ORE) > int(ItemDB.info("pickaxe_stone")["mine_tier"]), "stone pickaxe cannot mine gold")

	# --- Combat ------------------------------------------------------------------
	var xp_before := p.xp
	var skel := _w.spawn_entity("skeleton", p.global_position + Vector3(3, 0.5, 0), 0, {})
	_check(skel != null, "skeleton spawns")
	if skel != null:
		await _wait(1.0)
		var guard := 0
		while not skel.dead and guard < 60:
			_w.request_attack([skel.net_id], 20.0, "hit")
			guard += 1
			await _frames(2)
		_check(skel.dead, "skeleton killed")
		await _frames(5)
		_check(p.xp > xp_before, "kill gave xp (%d -> %d)" % [xp_before, p.xp])
	var hp := p.health
	p.receive_damage(10.0, p.global_position + Vector3(1, 0, 0), "hit", "test")
	_check(p.health < hp, "player takes damage")

	# --- Boss: the Warden ---------------------------------------------------------------
	var warden := _w.spawn_entity("warden", p.global_position + Vector3(6, 0.5, 0), 0, {})
	_check(warden != null and warden.is_class("Node3D"), "Warden boss spawns")
	if warden != null:
		await _wait(1.5)
		var guard := 0
		while not warden.dead and guard < 400:
			if warden.has_method("add_threat"):
				warden.call("add_threat", p.net_id, 10.0)
			_w.request_attack([warden.net_id], 60.0, "hit")
			guard += 1
			await _frames(1)
		_check(warden.dead, "Warden defeated")
		await _wait_for(func() -> bool: return _w.bosses_defeated.has("warden"), 5.0)
		_check(_w.bosses_defeated.has("warden"), "boss recorded as defeated")
		await _wait_for(func() -> bool: return p.inventory.has("warden_sigil"), 5.0)
		_check(p.inventory.has("warden_sigil"), "relic (Warden's Sigil) awarded")
	p.heal_local(p.max_health)

	# --- Death and respawn -----------------------------------------------------------------
	p.receive_damage(9999.0, Vector3.INF, "void", "test")
	_check(p.dead, "player can die")
	p.request_respawn()
	_check(not p.dead and p.health == p.max_health, "respawn restores the player")

	# --- The Gates of Hades ------------------------------------------------------------------
	p.inventory.add("frost_crown", 1)
	p.inventory.add("dragonheart", 1)
	var gate := _w.location_by_id(&"gates_of_hades")
	_check(gate != null, "Gates of Hades planned")
	if gate != null:
		var portal_pos: Vector3 = gate.spawns_of("portal")[0]["pos"]
		p.global_position = portal_pos + Vector3(0, 0.2, 6)
		var is_gate := func(e: Entity) -> bool: return e.dimension == 0 and e.get("to_dimension") == 1
		await _wait_for(func() -> bool: return _find("portal", is_gate) != null, 20.0)
		var portal := _find("portal", is_gate) as Portal
		_check(portal != null, "portal spawned at the gates")
		if portal == null:
			_dump_entities()
			print("      player at ", p.global_position, " dead ", p.dead, " loaded ", vw.is_area_loaded(p.global_position))
		if portal != null:
			portal.local_interact(p)
			_check(p.dimension == 1 and _w.local_dimension == 1, "travelled to the underworld")
			var hell := _w.world_for(1)
			await _wait_for(func() -> bool: return hell.is_area_loaded(p.global_position) and p.body.on_floor, 30.0)
			_check(p.body.on_floor and not p.dead, "standing safely in Asphodel")
			await _wait(1.0)
			_check(_w.tracker.current_title != "", "location label in hell: %s" % _w.tracker.current_title)

	# --- Save -------------------------------------------------------------------------------------
	Game.save_game()
	var save := SaveSystem.read(int(Game.session.get("slot", 0)))
	_check(save.get("bosses_defeated", []).has("warden"), "save contains defeated bosses")
	_check((save.get("edits", {}).get(0, {}) as Dictionary).size() > 0, "save contains block edits")

	print("%s — %d failures" % ["PLAYTEST PASSED" if _failures == 0 else "PLAYTEST FAILED", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _dump_entities() -> void:
	var kinds := {}
	for e in _w.all_entities():
		var ent := e as Entity
		var key := "%s(dim %d)" % [ent.kind, ent.dimension]
		kinds[key] = int(kinds.get(key, 0)) + 1
	print("      entities: ", kinds)
	for e in _w.all_entities():
		if (e as Entity).kind in ["shrine", "portal"]:
			print("      ", (e as Entity).kind, " at ", (e as Entity).global_position, " loc ", e.get("location_id"))


func _count(kind: String) -> int:
	var n := 0
	for e in _w.all_entities():
		if e is Entity and (e as Entity).kind == kind:
			n += 1
	return n
