extends Node
## Two-player gameplay check, attached by Game when run with --mp-test=host|client
## (see tests/net/run_game_mp_test.sh). Prints MP PASS/FAIL lines.

var role := "host"
var _w: GameWorld
const EDIT_OFFSET := Vector3i(3, -1, 0)


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("MP %s %s %s" % [role.to_upper(), "PASS" if ok else "FAIL", what])


func _wait_for(cond: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return false


func _other_player() -> Player:
	for p in _w.players_in(-1):
		if p != _w.local_player:
			return p
	return null


func _run() -> void:
	_w = GameWorld.instance
	var ok := await _wait_for(func() -> bool: return _other_player() != null, 30.0)
	_check(ok, "sees the other player")
	if role == "host":
		await _host()
	else:
		await _client()
	print("MP %s DONE" % role.to_upper())
	# The host stays up a little longer so the client can finish cleanly.
	await get_tree().create_timer(8.0 if role == "host" else 1.0).timeout
	get_tree().quit()


func _host() -> void:
	var other := _other_player()
	if other == null:
		return
	await _wait_for(func() -> bool: return _w.world_for(0).is_area_loaded(other.global_position), 20.0)
	var skel := _w.spawn_entity("skeleton", other.global_position + Vector3(2, 0.5, 0), 0, {})
	_check(skel != null, "spawned a skeleton next to the client")
	var killed := await _wait_for(func() -> bool: return skel == null or not is_instance_valid(skel) or skel.dead, 40.0)
	_check(killed, "client's attacks killed the server skeleton")
	var mined := await _wait_for(func() -> bool:
		for key: Vector3i in _w.world_for(0).get_edits():
			for i: int in _w.world_for(0).get_edits()[key]:
				var y := i / Chunk.AREA
				var pos := key * Chunk.SIZE + Vector3i(i % Chunk.SIZE, y, (i % Chunk.AREA) / Chunk.SIZE)
				if pos.distance_to(Vector3i(other.global_position.floor())) < 8.0:
					return true
		return false, 30.0)
	_check(mined, "client's block edit reached the host world")
	# Down the client (no shrine respawns by default) and revive them.
	other = _other_player()
	if other == null:
		return
	_w.damage(other, 99999.0, 0, "hit")
	var downed := await _wait_for(func() -> bool: return other != null and is_instance_valid(other) and other.dead and other.downed, 15.0)
	_check(downed, "client went down instead of dying (shrine respawns off)")
	var me := _w.local_player
	me.global_position = other.global_position + Vector3(1.2, 0.2, 0)
	me.call("_begin_revive", other)
	var revived := await _wait_for(func() -> bool: return other != null and is_instance_valid(other) and not other.dead, 20.0)
	_check(revived, "host revived the downed client")


func _client() -> void:
	var me := _w.local_player
	var found := await _wait_for(func() -> bool:
		for e in _w.entities_near(me.global_position, 12.0, 0, Entity.Team.MONSTERS):
			return true
		return false, 30.0)
	_check(found, "received the server-spawned skeleton")
	var guard := 0
	while guard < 200:
		var near := _w.entities_near(me.global_position, 12.0, 0, Entity.Team.MONSTERS)
		if near.is_empty():
			break
		var ids: Array = []
		for e in near:
			ids.append(e.net_id)
		_w.request_attack(ids, 25.0, "hit")
		guard += 1
		await get_tree().create_timer(0.1).timeout
	var left := _w.entities_near(me.global_position, 12.0, 0, Entity.Team.MONSTERS)
	for e in left:
		print("MP CLIENT note: still near: %s hp %.0f at %s (me %s)" % [e.kind, e.health, e.global_position, me.global_position])
	_check(left.is_empty(), "killed it (state replicated back)")
	# Smooth terrain must use the same brush as the first-person pickaxe.
	me.inventory.select(1)
	var vw := _w.world_for(0)
	var point := Vector3.INF
	for radius in range(3, 14):
		for i in 16:
			var q := me.global_position + Vector3(cos(i * TAU / 16), 0, sin(i * TAU / 16)) * radius
			var ground := vw.ground_below(q.x, q.y + 5, q.z, 20)
			if not is_finite(ground):
				continue
			var b := vw.get_block(Vector3i(Vector3(q.x, ground - 0.3, q.z).floor()))
			if b > 0 and Blocks.is_smooth(b) and ItemDB.can_mine("pickaxe_stone", b):
				point = Vector3(q.x, ground - 0.25, q.z)
				break
		if point.is_finite():
			break
	_check(point.is_finite(), "found sculptable ground")
	if point.is_finite():
		me.global_position = point + Vector3(1.8, 1.5, 0)
		await get_tree().create_timer(1.2).timeout
		var old := vw.field(point)
		_w.request_set_block(Vector3i(point.floor()), Blocks.AIR, 0)
		await get_tree().create_timer(0.8).timeout
		_check(is_equal_approx(old, vw.field(point)), "host rejects cube deletion of natural terrain")
		for i in 6:
			_w.replicator.request_dig(point, 0.9, Player.STRIKE_TIME, "pickaxe_stone", 0)
			await get_tree().create_timer(0.5).timeout
		_check(vw.field(point) < old, "smooth excavation replicated back from the host")
	# The host knocks us down and revives us.
	var went_down := await _wait_for(func() -> bool: return me.dead, 45.0)
	_check(went_down and me.downed, "client is downed, waiting for a teammate")
	var back := await _wait_for(func() -> bool: return not me.dead, 30.0)
	_check(back and me.health > 0.0, "client revived by the host (%.0f hp)" % me.health)
