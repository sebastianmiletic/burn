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

	print("[playtest] initial health=", p.health, " dead=", p.dead, " pos=", p.global_position, " loaded=", vw.is_area_loaded(p.global_position))
	# --- Spawn ---------------------------------------------------------------
	await _wait_for(func() -> bool: return p.body.on_floor, 10.0)
	if "--ogygia-only" in OS.get_cmdline_user_args():
		# Quick iteration on the swimming / drowning / Ogygia section alone.
		p.respawn_point = p.global_position
		await _ogygia(p)
		print("%s — %d failures" % ["PLAYTEST PASSED" if _failures == 0 else "PLAYTEST FAILED", _failures])
		get_tree().quit(1 if _failures > 0 else 0)
		return
	print("[playtest] settled health=", p.health, " dead=", p.dead, " velocity=", p.body.velocity, " floor=", p.body.on_floor, " loaded=", vw.is_area_loaded(p.global_position))
	_check(p.body.on_floor and not p.dead, "player spawns standing on ground at %s" % str(p.global_position.round()))
	_check(p.inventory.has("pickaxe_stone") and p.inventory.has("sword_rusty"), "starting kit given")
	_check(_w.quests.is_active("kindling"), "first quest active")
	await _early_ladder(p)

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
		_check(_w.quests.is_completed("fs_village"), "speaking with the elder ends the guide")
		_check(p.xp > 0 and p.inventory.has("potion_health", 3), "quest rewards granted (xp %d)" % p.xp)
		var smith := _find("npc", func(e: Entity) -> bool: return e.get("role") == "blacksmith") as Npc
		_check(smith != null, "blacksmith present")
		if smith != null:
			smith.local_interact(p)
			Events.dialog_choice.emit(smith, "accept:iron_in_the_deep")
			_check(_w.quests.is_active("iron_in_the_deep"), "blacksmith gives the next main quest")

	# --- Mining and building ---------------------------------------------------
	# Mining sculpts: strike the ground a few times beside the player.
	# Looking at something for a second names it beside the minimap.
	var looked := [""]
	var on_look := func(t: String, _s: String, _d: String) -> void: looked[0] = t
	Events.look_info.connect(on_look)
	p.camera.pitch = -1.2
	await get_tree().create_timer(1.6).timeout
	_check(looked[0] != "", "looking at the ground names it (%s)" % looked[0])
	p.camera.pitch = 1.3  # at the sky: nothing
	await get_tree().create_timer(0.5).timeout
	_check(looked[0] == "", "looking away clears it")
	Events.look_info.disconnect(on_look)
	p.camera.pitch = -0.2

	# Find natural ground nearby (the village plaza is paved).
	var dig_at := p.global_position + Vector3(2.5, -0.3, 0)
	var g := -INF
	for r in range(2, 14):
		var found := false
		for a in 8:
			var c := p.global_position + Vector3(cos(a * TAU / 8.0), 0, sin(a * TAU / 8.0)) * float(r)
			var gg := vw.ground_below(c.x, c.y + 4.0, c.z, 10.0)
			if absf(gg) < 1e6 and Blocks.is_smooth(vw.get_block(Vector3i(Vector3(c.x, gg - 0.4, c.z).floor()))) \
					and Blocks.tier(vw.get_block(Vector3i(Vector3(c.x, gg - 0.4, c.z).floor()))) <= 1:
				dig_at = Vector3(c.x, gg - 0.2, c.z)
				g = gg
				found = true
				break
		if found:
			break
	var before := vw.get_block(Vector3i(dig_at.floor()))
	var dropped_before := _count("drop")
	var mined_item := Blocks.drop(before)
	var mined_before := p.inventory.count_of(mined_item)
	p.inventory.select(1)  # Equip the pick, as a real player must.
	for i in 8:
		_w.replicator.request_dig(dig_at, 0.9, 0.42, "pickaxe_stone", 0)
		await _wait(Player.STRIKE_TIME)
	var after := vw.ground_below(dig_at.x, dig_at.y + 3.0, dig_at.z, 8.0)
	_check(absf(g) < 1e6 and after < g - 0.4, "dug a hole into %s (ground %.2f -> %.2f)" % [Blocks.name_of(before), g, after])
	var drop := _find("drop")
	_check((_count("drop") > dropped_before and drop != null) or p.inventory.count_of(mined_item) > mined_before, "digging dropped material (or picked it up automatically)")
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
			await _wait(0.12)
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
		p.invulnerable_until = Time.get_ticks_msec() / 1000.0 + 120.0
		await _wait(1.5)
		var guard := 0
		while not warden.dead and guard < 400:
			if warden.has_method("add_threat"):
				warden.call("add_threat", p.net_id, 10.0)
			# This checks reward integration, not AI navigation or survival.
			p.global_position = warden.global_position + Vector3(2, 0, 0)
			p.body.velocity = Vector3.ZERO
			p.heal_local(p.max_health)
			_w.request_attack([warden.net_id], 60.0, "hit")
			guard += 1
			await _wait(0.12)
		_check(warden.dead, "Warden defeated")
		await _wait_for(func() -> bool: return _w.bosses_defeated.has("warden"), 5.0)
		_check(_w.bosses_defeated.has("warden"), "boss recorded as defeated")
		await _wait_for(func() -> bool: return p.inventory.has("warden_sigil"), 5.0)
		_check(p.inventory.has("warden_sigil"), "relic (Warden's Sigil) awarded")
	p.invulnerable_until = 0.0
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

	# --- Endgame travel and persistent unlock ----------------------------------------------
	_w.travel(2)
	_check(p.dimension != 2, "Ryft cannot be entered before Hades falls")
	_w.quests.accept("throne")
	_w.quests.on_event("reach", "throne_of_hades")
	var hades := _w.spawn_entity("hades", p.global_position + Vector3(3, 0, 0), p.dimension, {})
	_check(hades != null, "Hades reward encounter created")
	if hades != null:
		# Phase/attack simulations live in test_boss_sim; this checks the real
		# death -> rewards -> unlock -> travel -> save integration.
		hades.take_damage(100000, p.net_id)
		_check(_w.ryft_unlocked, "Hades unlocks the Ryft for the party")
		_check(p.inventory.has("sword_gatebreaker"), "unique endgame reward granted")
		_check(_w.quests.is_active("ryft"), "endgame has a clear follow-up quest")
		_w.travel(2)
		var ryft := _w.world_for(2)
		await _wait_for(func() -> bool: return ryft.is_area_loaded(p.global_position) and p.body.on_floor, 30)
		_check(p.dimension == 2 and p.body.on_floor, "Ryft landing is streamed and walkable")
		_w.travel(0)
		_check(p.global_position.distance_to(_w.default_spawn(0)) < 1, "return from Ryft leads home, not the Hades cavern")

	# --- Swimming, drowning and Ogygia ------------------------------------------------------------
	await _ogygia(p)

	# --- Save -------------------------------------------------------------------------------------
	Game.save_game()
	var save := SaveSystem.read(int(Game.session.get("slot", 0)))
	_check(save.get("bosses_defeated", []).has("warden"), "save contains defeated bosses")
	_check(bool(save.get("ryft_unlocked", false)), "Ryft unlock is saved")
	_check(save.get("edits", {}).has(2), "Ryft terrain edits are included in saves")
	_check(save.get("world_revision", 0) == WorldGen.LATEST_REVISION, "world generation revision is saved")
	_check((save.get("edits", {}).get(0, {}) as Dictionary).size() > 0, "save contains block edits")

	print("%s — %d failures" % ["PLAYTEST PASSED" if _failures == 0 else "PLAYTEST FAILED", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## The guided first steps through the real crafting and placing paths:
## gather wood -> planks -> workbench (placed) -> stone tool -> campfire (placed).
func _early_ladder(p: Player) -> void:
	var q := _w.quests
	_check(q.is_active("fs_timber"), "guide starts: gather wood")
	p.give_item("wood", 6)  # what a felled tree's logs give on pickup
	_check(q.is_completed("fs_timber") and q.is_active("fs_workbench"), "wood gathered, workbench step next")
	_check(p.craft("planks") and p.craft("workbench"), "planks and a workbench crafted by hand")
	_check(await _place(p, "workbench"), "workbench placed in the world")
	_check(q.is_completed("fs_workbench") and q.is_active("fs_stone_tools"), "workbench step done")
	p.give_item("stone", 11)
	_check(p.craft("planks") and p.craft("stick"), "sticks whittled")
	_check("workbench" in p.nearby_station_kinds(), "the placed workbench is within reach")
	_check(p.craft("axe_stone"), "stone axe made at the workbench")
	_check(q.is_completed("fs_stone_tools") and q.is_active("fs_campfire"), "stone tools step done")
	_check(p.craft("campfire"), "campfire crafted")
	p.global_position += Vector3(0, 0, 2.5)
	await _frames(2)
	_check(await _place(p, "campfire"), "campfire placed in the world")
	_check(q.is_completed("fs_campfire") and q.is_active("fs_village"), "campfire step done, find the village next")
	p.give_item("raw_meat", 1)
	_check("campfire" in p.nearby_station_kinds() and p.craft("cooked_meat_campfire"), "meat roasted on the campfire")


## Selects the item in the hotbar and uses it on the ground in front; true when a station appeared.
func _place(p: Player, item: String) -> bool:
	var before := _count("station")
	var slot := -1
	for i in Inventory.HOTBAR:
		if String(p.inventory.get_slot(i).get("id", "")) == item:
			slot = i
	if slot < 0:
		p.inventory.swap(_slot_of(p, item), 2)
		slot = 2
	p.inventory.select(slot)
	p.camera.pitch = -0.9
	await _frames(3)
	p._use()
	return await _wait_for(func() -> bool: return _count("station") > before, 3.0)


func _slot_of(p: Player, item: String) -> int:
	for i in 64:
		if String(p.inventory.get_slot(i).get("id", "")) == item:
			return i
	return 0


func _ogygia(p: Player) -> void:
	# The sea gives this one back (the host's roll, forced here).
	var bag := p.inventory.to_dict()
	_w.replicator.force_drown_outcome = 1
	_w.replicator.request_drown_outcome()
	var isle := _w.world_for(Ogygia.DIM)
	_check(p.dimension == Ogygia.DIM and _w.local_dimension == Ogygia.DIM, "a rare drowning wakes on Ogygia")
	await _wait_for(func() -> bool: return isle.is_area_loaded(p.global_position) and p.body.on_floor, 30.0)
	_check(p.body.on_floor and not p.dead and p.global_position.y > OgygiaGen.SEA, "standing on Ogygia's beach at %s" % str(p.global_position.round()))
	_check(_w.quests.is_completed(Ogygia.LORE_ID), "first visit writes Ogygia into the journal")
	await _wait_for(func() -> bool: return _count("calypso") == 1 and _count("ogygia_raft") == 1, 5.0)
	_check(_count("calypso") == 1 and _count("ogygia_raft") == 1, "Calypso and her raft are on the island")
	_check(GameWorld.biome_name(_w, p.global_position, Ogygia.DIM) == "Ogygia", "the island is named")
	# Swimming in the lagoon: a 10 m drop into deep water does no harm and the body treads water.
	var sea := Vector3(OgygiaGen.CENTER.x, OgygiaGen.SEA + 10.0, OgygiaGen.CENTER.y + 112.0)
	p.global_position = sea
	p.body.velocity = Vector3.ZERO
	p.body.fly = true  # hover until the sea there has streamed in
	await _wait_for(func() -> bool: return isle.is_area_loaded(sea) and isle.is_area_loaded(sea - Vector3(0, 16, 0)) and isle.loading_progress() > 0.9, 40.0)
	p.global_position = sea
	p.body.fly = false
	var hp := p.health
	_check(await _wait_for(func() -> bool: return p.swimming, 15.0), "falling into the sea starts swimming")
	await _wait(4.0)
	var eye := p.global_position.y + 1.62
	_check(p.swimming and absf(eye - p.water_surface - 0.2) < 0.35, "treading water with the eyes above the surface (eye %.2f, surface %.2f)" % [eye, p.water_surface])
	_check(p.health >= hp, "diving into deep water does no fall damage")
	# Swim forward where the camera looks (down-forward dives). Earlier
	# dialogues may have left the controls with the UI: take them back.
	Events.dialog_close.emit()
	_w.set_ui_open(false)
	p.set_input_enabled(true)
	p.camera.pitch = -0.6
	Input.action_press("move_forward")
	await _wait(1.5)
	Input.action_release("move_forward")
	_check(p.head_under and p.global_position.y < sea.y - 12.0, "swimming follows the look direction under water (y %.1f)" % p.global_position.y)
	# Hold your breath too long: the dark closes in and the sea keeps you.
	var causes: Array = []
	var on_died := func(c: String) -> void: causes.append(c)
	Events.player_died.connect(on_died)
	_w.replicator.force_drown_outcome = 0
	p.air = 1.5
	Input.action_press("dodge")
	await _wait_for(func() -> bool: return p.dead, 15.0)
	Input.action_release("dodge")
	Events.player_died.disconnect(on_died)
	_check(p.dead and causes.size() == 1 and String(causes[0]).contains("Drowned"), "drowning is a death (%s)" % str(causes))
	p.request_respawn()
	_check(not p.dead and p.dimension == 0 and p.suffocation == 0.0, "drowned on Ogygia, rise at the shrine with clear eyes")
	# Back to the island; Calypso's gift; save while there; the raft home.
	_w.replicator.force_drown_outcome = 1
	_w.replicator.request_drown_outcome()
	await _wait_for(func() -> bool: return isle.is_area_loaded(p.global_position) and p.body.on_floor, 30.0)
	var calypso := _find("calypso") as Calypso
	if calypso != null:
		calypso.local_interact(p)
		Events.dialog_choice.emit(calypso, "gift")
		Events.dialog_choice.emit(calypso, "bye")
	_check(p.inventory.has(Calypso.GIFT_ITEM), "Calypso's gift")
	Game.save_game()
	var isle_save := SaveSystem.read(int(Game.session.get("slot", 0)))
	_check(int((isle_save.get("player", {}) as Dictionary).get("dim", -1)) == Ogygia.DIM, "a save made on Ogygia keeps the player there")
	var raft := _find("ogygia_raft")
	var had := p.inventory.count_of("pickaxe_stone")
	if raft != null:
		raft.call("local_interact", p)
	_check(p.dimension == p.respawn_dimension and p.global_position.distance_to(p.respawn_point) < 1.0, "the raft returns you to your last shrine")
	_check(p.inventory.count_of("pickaxe_stone") == had and had > 0 and bag.size() > 0, "inventory intact after Ogygia")
	_w.replicator.force_drown_outcome = -1
	await _wait(0.5)


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
