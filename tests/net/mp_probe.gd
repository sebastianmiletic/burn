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
	_check(_w.entities_near(me.global_position, 12.0, 0, Entity.Team.MONSTERS).is_empty(), "killed it (state replicated back)")
	var target := Vector3i(me.global_position.floor()) + EDIT_OFFSET
	var before := _w.world_for(0).get_block(target)
	_w.request_set_block(target, Blocks.AIR, 0)
	var echoed := await _wait_for(func() -> bool: return _w.world_for(0).get_block(target) == Blocks.AIR, 10.0)
	_check(Blocks.is_breakable(before) and echoed, "mined %s through the server" % Blocks.name_of(before))
