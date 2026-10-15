extends Node
## Stages and photographs villagers and activities (see activity_capture.gd).

var _out := ""
var _w: GameWorld
var _p: Player
var _acts: ActivityDirector
var _shots := PackedStringArray(["npc", "smith", "night", "board", "elite", "tracks", "treasure", "meteor", "crater", "ring", "raid"])


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a.begins_with("--shots="):
			_shots = a.trim_prefix("--shots=").split(",")
		elif a.begins_with("--style="):
			_set_graphics("style", int(a.trim_prefix("--style=")))
		elif a.begins_with("--quality="):
			_set_graphics("quality", int(a.trim_prefix("--quality=")))
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _set_graphics(key: String, value: Variant) -> void:
	Settings._data["graphics"][key] = value
	Settings.changed.emit("graphics", key)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _wait_for(cond: Callable, s: float) -> bool:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _goto(pos: Vector3) -> void:
	_p.invulnerable_until = Time.get_ticks_msec() / 1000.0 + 3600.0
	var vw := _w.world_for(0)
	_p.global_position = pos + Vector3(0, 20, 0)
	vw.focus = pos
	await _wait_for(func() -> bool: return vw.is_area_loaded(pos) and vw.loading_progress() > 0.95, 40.0)
	var g := vw.ground_below(pos.x, pos.y + 60.0, pos.z, 140.0)
	if absf(g) < 1e6:
		_p.global_position = Vector3(pos.x, g + 0.05, pos.z)
	_p.body.velocity = Vector3.ZERO
	await _wait(1.0)


## Point the first-person camera at `target`.
func _look(target: Vector3, pitch_bias := 0.0) -> void:
	var eye := _p.global_position + Vector3(0, 1.62, 0)
	var d := target - eye
	_p.camera.yaw = atan2(-d.x, -d.z)
	_p.camera.pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()) + pitch_bias, -1.2, 1.2)


func _shot(name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.get_width() > 1600:
		img.resize(1600, int(img.get_height() * 1600.0 / img.get_width()), Image.INTERPOLATE_BILINEAR)
	img.save_jpg(_out.path_join(name + ".jpg"), 0.86)
	print("[activity-capture] ", name)


func _npcs(role := "") -> Array:
	return _w.all_entities().filter(func(e: Entity) -> bool: return e is Npc and (role == "" or (e as Npc).role == role))


func _run() -> void:
	_w = GameWorld.instance
	_p = _w.local_player
	_acts = ActivityDirector.of(_w)
	var home := _w.location_by_id(&"emberfall")
	_w.weather.force("clear")
	await _wait(2.0)
	if "npc" in _shots:
		_w.sky.time_of_day = 10.5
		await _goto(home.center + Vector3(2, 0, 9))
		await _wait(4.0)
		var people := _npcs("villager")
		if not people.is_empty():
			var n: Npc = people[0]
			_p.global_position = n.global_position + Vector3(0, 0.05, 2.2)
			await _wait(0.3)
			_look(n.global_position + Vector3(0, 1.55, 0))
			n.local_interact(_p)
			await _wait(2.5)
			_look(n.global_position + Vector3(0, 1.55, 0))
			await _shot("npc_talk")
			Events.dialog_close.emit()
	if "face" in _shots:
		_w.sky.time_of_day = 10.5
		await _goto(home.center + Vector3(2, 0, 9))
		await _wait(3.0)
		var who := _npcs("villager")
		if not who.is_empty():
			var n: Npc = who[0]
			_p.global_position = n.global_position + Vector3(1.4, 0.05, 1.4)
			n.server_interact(_p)
			await _wait(2.0)
			_look(n.global_position + Vector3(0, 1.5, 0))
			await _shot("face_check_npc")
		var sk := _w.spawn_entity("skeleton", _p.global_position + Vector3(0, 0.3, -4), 0, {})
		await _wait(1.5)
		if sk != null:
			_look(sk.global_position + Vector3(0, 1.4, 0))
			await _shot("face_check_skeleton")
			_w.despawn_entity(sk)
	if "smith" in _shots:
		var smiths := _npcs("blacksmith")
		if not smiths.is_empty():
			var s: Npc = smiths[0]
			await _wait(2.0)
			var anvil := s.layout.anvil() if s.layout != null else s.global_position
			var side := (s.global_position - anvil).normalized()
			_p.global_position = s.global_position + side.rotated(Vector3.UP, 1.1) * 3.2
			await _wait(1.5)
			_look(s.global_position + Vector3(0, 1.2, 0))
			await _wait(0.6)
			await _shot("smith_at_anvil")
	if "night" in _shots:
		_w.sky.time_of_day = 21.3
		_p.global_position = home.center + Vector3(-6, 0.5, 6)
		await _wait(6.0)
		var guards := _npcs("guard")
		var target := home.center if guards.is_empty() else (guards[0] as Npc).global_position
		_look(target + Vector3(0, 1.4, 0), -0.05)
		await _wait(0.5)
		await _shot("night_watch")
		_w.sky.time_of_day = 11.0
	if "board" in _shots:
		await _wait_for(func() -> bool: return not _w.all_entities().filter(func(e: Entity) -> bool: return e is BountyBoard).is_empty(), 10.0)
		var boards := _w.all_entities().filter(func(e: Entity) -> bool: return e is BountyBoard)
		if not boards.is_empty():
			var b: BountyBoard = boards[0]
			var front := Vector3(sin(b.yaw), 0, cos(b.yaw))
			_p.global_position = b.global_position + front * 3.4
			await _wait(1.0)
			_look(b.global_position + Vector3(0, 1.4, 0))
			await _shot("bounty_board")
			b.local_interact(_p)
			await _wait(2.0)
			await _shot("bounty_board_read")
			Events.dialog_close.emit()
	if "elite" in _shots or "tracks" in _shots:
		# Make sure a hunt is posted so the tracks can be photographed.
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		for i in 40:
			var h := Bounties.make_contract(_w.gen_for(0), _w.locations(0), 900 + i, rng)
			if not h.is_empty() and h["type"] == "hunt":
				(_acts.shared["contracts"] as Array).append(h)
				break
		var c: Dictionary = {}
		for o: Dictionary in _acts.bounties.contracts():
			if o["state"] == "open" and (o["type"] == "hunt" or c.is_empty()):
				c = o
		if not c.is_empty():
			_acts.request("contract_accept", {"id": int(c["id"])})
			await _goto((c["area"] as Vector3) + Vector3(3, 0, 0))
			await _wait_for(func() -> bool: return _acts.bounties._targets.has(int(c["id"])), 10.0)
			if _acts.bounties._targets.has(int(c["id"])):
				var ids: Array = _acts.bounties._targets[int(c["id"])]
				var tracks := _w.entity(int(ids[2])) as TrackTrail
				if tracks != null and "tracks" in _shots:
					_p.global_position = tracks.points[0] - (tracks.points[3] - tracks.points[0]).normalized() * 2.0
					await _wait(0.8)
					_look(tracks.points[mini(5, tracks.points.size() - 1)], -0.25)
					await _wait(0.5)
					await _shot("hunt_tracks")
				var target := _w.entity(int(ids[0]))
				if target != null and "elite" in _shots:
					_p.global_position = target.global_position + Vector3(6, 0.3, 4)
					target.set("state", 0)
					await _wait(1.2)
					_look(target.global_position + Vector3(0, 1.3, 0))
					await _shot("elite_" + String(c["mob"]))
	if "treasure" in _shots:
		_p.inventory.add("treasure_map", 1)
		await _wait_for(func() -> bool: return not _acts.treasure.active().is_empty(), 3.0)
		var hunt := _acts.treasure.active()
		if not hunt.is_empty():
			var spot: Vector3 = hunt["spot"]
			await _goto(hunt["landmark_pos"] + Vector3(5, 0, 5))
			await _goto(spot + Vector3(3.5, 0, 0))
			await _wait(1.5)
			_look(spot, -0.1)
			await _shot("treasure_x_marks")
			await _wait_for(func() -> bool: return not _w.all_entities().filter(func(e: Entity) -> bool: return e is BuriedCache).is_empty(), 15.0)
			var caches := _w.all_entities().filter(func(e: Entity) -> bool: return e is BuriedCache)
			if not caches.is_empty():
				var cache: BuriedCache = caches[0]
				_p.inventory.slots[1] = {"id": "pickaxe_iron", "count": 1}
				_p.inventory.select(1)
				_p.inventory.changed.emit()
				for i in 30:
					if cache.is_exposed():
						break
					var g := _w.world_for(0).ground_below(spot.x, spot.y + 4.0, spot.z, 8.0)
					_w.replicator.request_dig(Vector3(spot.x, g - 0.2, spot.z), 0.95, Player.STRIKE_TIME, "pickaxe_iron", 0)
					await _wait(0.36)
				_p.global_position = Vector3(spot.x + 2.2, _p.global_position.y, spot.z)
				await _wait(0.8)
				_look(cache.global_position + Vector3(0, 0.6, 0))
				await _shot("treasure_dug")
				cache.local_interact(_p)
				await _wait(1.4)
				_look(cache.global_position + Vector3(0, 0.6, 0))
				await _shot("treasure_open")
	if "meteor" in _shots or "crater" in _shots:
		_w.sky.time_of_day = 22.5
		var started := false
		for off: Vector3 in [Vector3(70, 0, 50), Vector3(-70, 0, 50), Vector3(60, 0, -60), Vector3(-60, 0, -60), Vector3(0, 0, 90)]:
			await _goto(home.center + off)
			await _wait(1.0)
			if _acts.events.start_meteor(_p.global_position):
				started = true
				break
		if started:
			var site: Vector3 = _acts.events.event()["pos"]
			_look(site + Vector3(0, 40, 0), 0.0)
			await _wait(3.6)
			await _shot("meteor_falling")
			await _wait(1.8)
			_look(site, 0.0)
			await _wait(0.25)
			await _shot("meteor_impact")
			await _wait(3.0)
			_p.global_position = site + Vector3(6.5, 0.0, 2.0)
			var g := _w.world_for(0).ground_below(_p.global_position.x, site.y + 6.0, _p.global_position.z, 12.0)
			if absf(g) < 1e6:
				_p.global_position.y = g + 0.05
			await _wait(1.0)
			_look(site + Vector3(0, -1.6, 0))
			await _shot("meteor_crater_night")
			_w.sky.time_of_day = 9.0
			await _wait(1.0)
			await _shot("meteor_crater_day")
	if "ring" in _shots:
		_w.sky.time_of_day = 17.6
		var site := _acts.ring.site()
		if site != Vector3.INF:
			await _goto(site + Vector3(0, 0, 9))
			await _wait_for(func() -> bool: return not _w.all_entities().filter(func(e: Entity) -> bool: return e is ArenaRing).is_empty(), 10.0)
			await _wait(1.0)
			_look(site + Vector3(0, 1.6, 0), 0.02)
			await _shot("proving_ring")
			_p.global_position = site + Vector3(0, 0.3, 3)
			_acts.request("arena_start")
			await _wait(9.5)
			_look(site + Vector3(-8, 1.2, -8), 0.0)
			await _shot("proving_ring_wave")
			_p.global_position = site + Vector3(60, 2, 0)
			await _wait(10.0)
	if "raid" in _shots:
		_w.sky.time_of_day = 18.7
		await _goto(home.center + Vector3(0, 0, 8))
		_acts.events.start_raid(home)
		await _wait(1.0)
		await _shot("raid_banner")
		await _wait_for(func() -> bool: return _acts.events.event().get("stage", "") == "fight", 20.0)
		await _wait(6.0)
		var near: Entity = null
		for id: int in _acts.events._raiders:
			var e := _w.entity(id)
			if e != null:
				near = e
				break
		if near != null:
			_p.global_position = near.global_position + (home.center - near.global_position).normalized() * 9.0
			await _wait(0.6)
			_look(near.global_position + Vector3(0, 1.2, 0))
			await _shot("raid_wave")
	print("[activity-capture] done")
	get_tree().quit()
