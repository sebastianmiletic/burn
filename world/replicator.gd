class_name Replicator
extends Node
## Every gameplay message between peers. Lives at /root/GameWorld/Replicator.
##
## * Players: each peer simulates its own player and sends its state to the
##   server at 20 Hz; the server relays it to the others.
## * Server entities (monsters, bosses, NPCs, drops, shrines, chests,
##   portals): spawned/despawned reliably, state snapshots at 15 Hz,
##   unreliable, only for entities within INTEREST_RADIUS of each peer.
## * Requests (attack, block edit, pickup, interact) go to the server, which
##   validates them before acting.
## In solo the OfflineMultiplayerPeer makes this machine the server and the
## same code paths run locally.

const SNAPSHOT_HZ := 15.0
const PLAYER_HZ := 20.0
const INTEREST_RADIUS := 120.0
const MAX_REACH := 7.5

var _snap_accum := 0.0
var _state_accum := 0.0
var _peer_dim := {}        # peer -> dimension (server)
var _dig_at := {}         # peer -> last accepted sculpt strike (seconds)
var _known := {}           # peer -> {net_id: true} spawned on that peer (server)


static func player_net_id(peer: int) -> int:
	return -peer


## Peers whose GameWorld has finished loading (server side). Gameplay RPCs go
## only to them; a peer still loading gets everything in _client_ready.
var _ready_peers := {}


## Peers that have loaded the world and receive gameplay RPCs.
func ready_peers() -> Array:
	return _targets()


func _targets() -> Array:
	var out := []
	for peer in multiplayer.get_peers():
		if _ready_peers.has(peer):
			out.append(peer)
	return out


## Runs `method` here (if `local`) and on every loaded peer.
func _broadcast(method: StringName, args: Array, local := true) -> void:
	if local:
		callv(method, args)
	if not Net.is_online():
		return
	for peer in _targets():
		callv("rpc_id", [peer, method] + args)


func gw() -> GameWorld:
	return get_parent() as GameWorld


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _process(delta: float) -> void:
	var w := gw()
	if w == null or w.local_player == null:
		return
	_state_accum += delta
	if _state_accum >= 1.0 / PLAYER_HZ:
		_state_accum = 0.0
		_send_local_state()
	if Net.is_server() and Net.is_online():
		_snap_accum += delta
		if _snap_accum >= 1.0 / SNAPSHOT_HZ:
			_snap_accum = 0.0
			_send_snapshots()


func _now() -> float:
	return Net.server_time() if Net.has_method("server_time") else Time.get_ticks_msec() / 1000.0


# --- Players ------------------------------------------------------------------------

func _send_local_state() -> void:
	if not Net.is_online():
		return
	var p := gw().local_player
	var state := [p.dimension, p.global_position, p.yaw, p.anim, p.anim_time, p.held_item(), p.health, p.max_health,
			(2 if p.downed else 1) if p.dead else 0, p.display_name, p.offhand_light]
	if Net.is_server():
		_relay_player_state(multiplayer.get_unique_id(), state)
	else:
		_player_state.rpc_id(1, state)


@rpc("any_peer", "unreliable_ordered")
func _player_state(state: Array) -> void:
	if not multiplayer.is_server() or not valid_player_state(state):
		return
	var peer := multiplayer.get_remote_sender_id()
	if not _ready_peers.has(peer) or not gw().worlds.has(int(state[0])) or (int(state[0]) == 2 and not gw().ryft_unlocked):
		return
	_apply_player_state(peer, state)
	_relay_player_state(peer, state)


static func valid_player_state(state: Array) -> bool:
	if state.size() != 11 or not state[0] is int or not state[1] is Vector3:
		return false
	if not (state[1] as Vector3).is_finite() or (state[1] as Vector3).length() > 20000:
		return false
	for index in [2, 3, 4, 6, 7, 8]:
		if not (state[index] is float or state[index] is int) or not is_finite(float(state[index])):
			return false
	return state[5] is String and state[9] is String and state[10] is bool and String(state[9]).length() <= 64 and float(state[7]) > 0 and float(state[7]) <= 10000 and float(state[6]) >= 0 and float(state[6]) <= float(state[7])

func _relay_player_state(peer: int, state: Array) -> void:
	_peer_dim[peer] = int(state[0])
	for other in _targets():
		if other != peer:
			_player_state_relayed.rpc_id(other, peer, state)


@rpc("authority", "unreliable_ordered")
func _player_state_relayed(peer: int, state: Array) -> void:
	_apply_player_state(peer, state)


func _apply_player_state(peer: int, state: Array) -> void:
	var w := gw()
	if peer == multiplayer.get_unique_id():
		return
	var id := player_net_id(peer)
	var p := w.entity(id) as Player
	if p == null:
		p = EntityFactory.create("player") as Player
		p.net_id = id
		p.peer_id = peer
		p.is_local = false
		w._add_entity(p)
		p.global_position = state[1]
	p.apply_remote_state(state, _now())
	p.visible = p.dimension == w.local_dimension


func _on_peer_disconnected(peer: int) -> void:
	var w := gw()
	if w == null:
		return
	w.remove_entity(player_net_id(peer))
	_ready_peers.erase(peer)
	_peer_dim.erase(peer)
	_known.erase(peer)
	_dig_at.erase(peer)


func notify_dimension(dim: int) -> void:
	if Net.is_online() and not Net.is_server():
		_client_dimension.rpc_id(1, dim)
	elif Net.is_server():
		_peer_dim[multiplayer.get_unique_id()] = dim


@rpc("any_peer", "reliable")
func _client_dimension(dim: int) -> void:
	if multiplayer.is_server() and gw().worlds.has(dim) and (dim != 2 or gw().ryft_unlocked):
		_peer_dim[multiplayer.get_remote_sender_id()] = dim


## A client finished loading: send it everything that already exists.
func client_ready() -> void:
	if Net.is_online() and not Net.is_server():
		_client_ready.rpc_id(1, gw().local_dimension)


@rpc("any_peer", "reliable")
func _client_ready(dim: int) -> void:
	if not multiplayer.is_server() or not gw().worlds.has(dim) or (dim == 2 and not gw().ryft_unlocked):
		return
	var peer := multiplayer.get_remote_sender_id()
	_peer_dim[peer] = dim
	_known[peer] = {}
	_ready_peers[peer] = true
	# Reconcile changes made while this peer was loading. One chunk per
	# reliable message avoids a giant packet and preserves edit ordering.
	for dimension: int in gw().worlds:
		var edits := gw().world_for(dimension).get_edits()
		for key: Vector3i in edits:
			_sync_edits.rpc_id(peer, dimension, {key: edits[key]})
	_sync_bosses.rpc_id(peer, gw().bosses_defeated.keys())
	_clock.rpc_id(peer, gw().sky.time_of_day, gw().sky.day, gw().weather.state_name())


@rpc("authority", "reliable")
func _sync_edits(dim: int, edits: Dictionary) -> void:
	var vw := gw().world_for(dim)
	if vw != null:
		vw.apply_edits(edits)

# --- Spawning ------------------------------------------------------------------------

func broadcast_spawn(e: Entity, data: Dictionary) -> void:
	e.set_meta("spawn_data", data)
	if not Net.is_online():
		return
	for peer in _targets():
		_spawn_on(peer, e)


func _spawn_on(peer: int, e: Entity) -> void:
	if not _known.has(peer):
		_known[peer] = {}
	_known[peer][e.net_id] = true
	_spawn.rpc_id(peer, e.net_id, e.kind, e.global_position, e.dimension, e.get_meta("spawn_data", {}))


@rpc("authority", "reliable")
func _spawn(id: int, kind: String, pos: Vector3, dim: int, data: Dictionary) -> void:
	gw().client_spawn(id, kind, pos, dim, data)


func broadcast_despawn(id: int) -> void:
	if not Net.is_online():
		return
	for peer in _targets():
		if _known.has(peer) and _known[peer].has(id):
			_known[peer].erase(id)
			_despawn.rpc_id(peer, id)


@rpc("authority", "reliable")
func _despawn(id: int) -> void:
	gw().remove_entity(id)


func _send_snapshots() -> void:
	var w := gw()
	var now := _now()
	for peer in _targets():
		var p := w.entity(player_net_id(peer)) as Player
		if p == null:
			continue
		var dim := p.dimension
		var batch: Array = []
		for e: Entity in w.all_entities():
			if e is Player or e.dimension != dim:
				continue
			if e.global_position.distance_squared_to(p.global_position) > INTEREST_RADIUS * INTEREST_RADIUS:
				continue
			if not _known.get(peer, {}).has(e.net_id):
				_spawn_on(peer, e)
			batch.append([e.net_id, e.snapshot()])
		if not batch.is_empty():
			_snapshot.rpc_id(peer, now, batch)


@rpc("authority", "unreliable_ordered")
func _snapshot(time: float, batch: Array) -> void:
	var w := gw()
	for entry: Array in batch:
		var e := w.entity(int(entry[0]))
		if e != null:
			e.apply_snapshot(entry[1], time)


# --- Combat --------------------------------------------------------------------------

func request_attack(targets: Array, amount: float, kind: String) -> void:
	if Net.is_server():
		_resolve_attack(multiplayer.get_unique_id(), targets, amount, kind)
	else:
		_request_attack.rpc_id(1, targets, amount, kind)


@rpc("any_peer", "reliable")
func _request_attack(targets: Array, amount: float, kind: String) -> void:
	if multiplayer.is_server():
		_resolve_attack(multiplayer.get_remote_sender_id(), targets, amount, kind)


func _resolve_attack(peer: int, targets: Array, amount: float, kind: String) -> void:
	var w := gw()
	var attacker := w.entity(player_net_id(peer)) as Player
	if attacker == null or attacker.dead:
		return
	amount = clampf(amount, 0.0, 400.0)  # no client can claim absurd damage
	for id: int in targets:
		var t := w.entity(id)
		if t == null or t.dead or t.team == Entity.Team.PLAYERS or t.dimension != attacker.dimension:
			continue
		if t.global_position.distance_to(attacker.global_position) > MAX_REACH + t.hit_radius * 2.0 and kind != "spell":
			continue
		if kind == "burn_hit":
			t.burning = maxf(t.burning, 4.0)
		w.damage(t, amount, attacker.net_id, "crit" if kind == "crit" else ("burn" if kind == "burn" else "hit"))
		if t.has_method("add_threat"):
			t.call("add_threat", attacker.net_id, amount)


func hurt_player(peer: int, amount: float, source_id: int, kind: String) -> void:
	if peer == multiplayer.get_unique_id() or not Net.is_online():
		_hurt.call(amount, source_id, kind)
	else:
		_hurt.rpc_id(peer, amount, source_id, kind)


@rpc("authority", "reliable")
func _hurt(amount: float, source_id: int, kind: String) -> void:
	var w := gw()
	var src := w.entity(source_id)
	w.local_player.receive_damage(amount, src.global_position if src != null else Vector3.INF, kind, src.display_name if src != null else "")


func knockback_player(peer: int, impulse: Vector3) -> void:
	if peer == multiplayer.get_unique_id() or not Net.is_online():
		_knockback(impulse)
	else:
		_knockback.rpc_id(peer, impulse)


@rpc("authority", "reliable")
func _knockback(impulse: Vector3) -> void:
	var p := gw().local_player
	if p != null and not p.dead:
		p.body.velocity += impulse


func damage_fx(pos: Vector3, amount: int, crit: bool, kind: String, dim: int) -> void:
	_broadcast(&"_damage_fx", [pos, amount, crit, kind, dim])


@rpc("authority", "unreliable", "call_local")
func _damage_fx(pos: Vector3, amount: int, crit: bool, kind: String, dim: int) -> void:
	if dim != gw().local_dimension:
		return
	Events.damage_number.emit(pos, amount, crit, kind)
	Audio.play("crit" if crit else "hit", pos)


func broadcast_projectile(kind: String, origin: Vector3, velocity: Vector3, owner_id: int, team: int, dim: int, dmg: float) -> void:
	_broadcast(&"_projectile", [kind, origin, velocity, owner_id, team, dim, dmg])


@rpc("authority", "reliable", "call_local")
func _projectile(kind: String, origin: Vector3, velocity: Vector3, owner_id: int, team: int, dim: int, dmg: float) -> void:
	var p := Projectile.new().setup(kind, origin, velocity, owner_id, team, dim, dmg)
	gw().add_child(p)
	p.visible = dim == gw().local_dimension
	if kind.contains("fire"):
		Audio.play("fireball_cast", origin)
	elif kind == "arrow":
		Audio.play("bow", origin)


## Player-cast projectiles are requested by clients and spawned by the server.
func request_projectile(kind: String, origin: Vector3, velocity: Vector3, dmg: float) -> void:
	if Net.is_server():
		_spawn_player_projectile(multiplayer.get_unique_id(), kind, origin, velocity, dmg)
	else:
		_request_projectile.rpc_id(1, kind, origin, velocity, dmg)


@rpc("any_peer", "reliable")
func _request_projectile(kind: String, origin: Vector3, velocity: Vector3, dmg: float) -> void:
	if multiplayer.is_server():
		_spawn_player_projectile(multiplayer.get_remote_sender_id(), kind, origin, velocity, dmg)


func _spawn_player_projectile(peer: int, kind: String, origin: Vector3, velocity: Vector3, dmg: float) -> void:
	var p := gw().entity(player_net_id(peer)) as Player
	if p == null or p.dead or origin.distance_to(p.global_position) > 4.0:
		return
	broadcast_projectile(kind, origin, velocity.limit_length(40.0), p.net_id, Entity.Team.PLAYERS, p.dimension, clampf(dmg, 0.0, 200.0))


func broadcast_telegraph(shape: String, pos: Vector3, dir: Vector3, size: Vector3, duration: float, dim: int) -> void:
	_broadcast(&"_telegraph", [shape, pos, dir, size, duration, dim])


@rpc("authority", "reliable", "call_local")
func _telegraph(shape: String, pos: Vector3, dir: Vector3, size: Vector3, duration: float, dim: int) -> void:
	gw().show_telegraph(shape, pos, dir, size, duration, dim)


func broadcast_shake(strength: float, at: Vector3, dim: int) -> void:
	_broadcast(&"_shake", [strength, at, dim])


@rpc("authority", "unreliable", "call_local")
func _shake(strength: float, at: Vector3, dim: int) -> void:
	var w := gw()
	if dim >= 0 and dim != w.local_dimension:
		return
	var s := strength
	if at != Vector3.INF:
		s *= clampf(1.0 - w.local_player.global_position.distance_to(at) / 40.0, 0.0, 1.0)
	if s > 0.01:
		Events.screen_shake.emit(s)


# --- Bosses ---------------------------------------------------------------------------

func broadcast_boss_state(id: int, engaged: bool, kind: String, defeated := false) -> void:
	_broadcast(&"_boss_state", [id, engaged, kind, defeated])


@rpc("authority", "reliable", "call_local")
func _boss_state(id: int, engaged: bool, kind: String, defeated: bool) -> void:
	var w := gw()
	var boss := w.entity(id)
	if not Net.is_server():
		w._active_boss = boss if engaged else null
	if engaged:
		if boss != null and boss.dimension == w.local_dimension:
			Events.boss_engaged.emit(boss, boss.display_name)
			Audio.set_music("boss")
	else:
		if not defeated:
			Events.boss_disengaged.emit(boss)
		if defeated:
			w.bosses_defeated[kind] = true
			if kind == "hades":
				w.ryft_unlocked = true
			Events.boss_defeated.emit(kind, boss.display_name if boss != null else kind)
			Events.slow_motion.emit(1.4, 0.3)
			w.quests.on_event("boss", kind)
			Audio.play_ui("levelup")
		Audio.set_music("hell" if w.local_dimension == 1 else "explore")


func sync_bosses_defeated(defeated: Dictionary) -> void:
	_broadcast(&"_sync_bosses", [defeated.keys()], false)


@rpc("authority", "reliable")
func _sync_bosses(kinds: Array) -> void:
	for k in kinds:
		gw().bosses_defeated[String(k)] = true
		if String(k) == "hades":
			gw().ryft_unlocked = true


func broadcast_victory() -> void:
	_broadcast(&"_victory", [])


@rpc("authority", "reliable", "call_local")
func _victory() -> void:
	gw().ryft_unlocked = true
	Events.notify.emit("The Ryft gateway in Emberfall is open. Your journey continues beyond the sky.", "quest")
	gw().get_tree().create_timer(4.0).timeout.connect(func() -> void: Events.campaign_won.emit())


# --- Rewards ---------------------------------------------------------------------------

func give_xp_to(peer: int, xp: int, killed_kind: String) -> void:
	if peer == multiplayer.get_unique_id() or not Net.is_online():
		_give_xp(xp, killed_kind)
	else:
		_give_xp.rpc_id(peer, xp, killed_kind)


@rpc("authority", "reliable")
func _give_xp(xp: int, killed_kind: String) -> void:
	var w := gw()
	w.local_player.add_xp(xp)
	if killed_kind != "":
		w.quests.on_event("kill", killed_kind)
		Events.enemy_killed.emit(killed_kind, true)


func give_gold_to(peer: int, gold: int) -> void:
	if peer == multiplayer.get_unique_id() or not Net.is_online():
		_give_gold(gold)
	else:
		_give_gold.rpc_id(peer, gold)


@rpc("authority", "reliable")
func _give_gold(gold: int) -> void:
	var inv := gw().local_player.inventory
	inv.gold += gold
	inv.changed.emit()
	Audio.play_ui("coin")


func give_item_to(peer: int, item: String, count: int) -> void:
	if peer == multiplayer.get_unique_id() or not Net.is_online():
		_give_item(item, count)
	else:
		_give_item.rpc_id(peer, item, count)


@rpc("authority", "reliable")
func _give_item(item: String, count: int) -> void:
	gw().local_player.give_item(item, count)


# --- Blocks ------------------------------------------------------------------------------

## A player places a crafting station (workbench, furnace, anvil...).
func request_station(kind: String, pos: Vector3, yaw: float, dim: int) -> void:
	if Net.is_server():
		_request_station_on_server(Net.my_id(), kind, pos, yaw, dim)
	else:
		_request_station.rpc_id(1, kind, pos, yaw, dim)


@rpc("any_peer", "reliable")
func _request_station(kind: String, pos: Vector3, yaw: float, dim: int) -> void:
	_request_station_on_server(multiplayer.get_remote_sender_id(), kind, pos, yaw, dim)


func _request_station_on_server(peer: int, kind: String, pos: Vector3, yaw: float, dim: int) -> void:
	var w := gw()
	var p := w.entity(player_net_id(peer)) as Player
	if not Net.is_server() or p == null or p.dead or p.dimension != dim or not pos.is_finite() or not is_finite(yaw) or not ItemDB.STATIONS.has(kind) or pos.distance_to(p.global_position) > MAX_REACH + 1.0:
		return
	w.place_station(kind, pos, yaw, dim)


# --- Sculpting ---------------------------------------------------------------------------

## A pickaxe strike: carve the ground around `point` (server decides what comes off).
# --- Reviving teammates ----------------------------------------------------------------------

func request_revive(target_net_id: int) -> void:
	if Net.is_server():
		_resolve_revive(multiplayer.get_unique_id(), target_net_id)
	else:
		_request_revive.rpc_id(1, target_net_id)


@rpc("any_peer", "reliable")
func _request_revive(target_net_id: int) -> void:
	if multiplayer.is_server():
		_resolve_revive(multiplayer.get_remote_sender_id(), target_net_id)


func _resolve_revive(peer: int, target_net_id: int) -> void:
	var w := gw()
	var helper := w.entity(player_net_id(peer)) as Player
	var target := w.entity(target_net_id) as Player
	if helper == null or target == null or helper.dead or not target.dead or not target.downed:
		return
	if helper.dimension != target.dimension or helper.global_position.distance_to(target.global_position) > 3.5:
		return
	_broadcast(&"_revived", [target_net_id, helper.display_name])


@rpc("authority", "reliable", "call_local")
func _revived(target_net_id: int, helper_name: String) -> void:
	var p := gw().entity(target_net_id) as Player
	if p != null and p.is_local:
		p.revive(helper_name)


var _wipe_check := 0.0


## Server: if every player is down at once, nobody can revive anybody - the
## whole party rises at their shrines.
func check_party_wipe(delta: float) -> void:
	if not Net.is_server() or not Net.is_online():
		return
	_wipe_check -= delta
	if _wipe_check > 0.0:
		return
	_wipe_check = 1.0
	var players := gw().players_in(-1)
	if players.size() < 2:
		return
	var any_downed := false
	for p in players:
		if not p.dead:
			return
		any_downed = any_downed or p.downed
	if any_downed:
		_broadcast(&"_party_wiped", [])


@rpc("authority", "reliable", "call_local")
func _party_wiped() -> void:
	var p := gw().local_player
	if p != null and p.dead:
		Events.notify.emit("The whole party has fallen. You rise at your shrine.", "warn")
		p.request_respawn(true)


func request_dig(point: Vector3, radius: float, seconds: float, item_id: String, dim: int) -> void:
	if Net.is_server():
		_resolve_dig(multiplayer.get_unique_id(), point, radius, seconds, item_id, dim)
	else:
		_request_dig.rpc_id(1, point, radius, seconds, item_id, dim)


@rpc("any_peer", "reliable")
func _request_dig(point: Vector3, radius: float, seconds: float, item_id: String, dim: int) -> void:
	if multiplayer.is_server():
		_resolve_dig(multiplayer.get_remote_sender_id(), point, radius, seconds, item_id, dim)


func _resolve_dig(peer: int, point: Vector3, radius: float, seconds: float, item_id: String, dim: int) -> void:
	var w := gw()
	var p := w.entity(player_net_id(peer)) as Player
	if p == null or p.dead or p.dimension != dim or not point.is_finite() or not is_finite(radius) or not is_finite(seconds) or point.distance_to(p.global_position + Vector3(0, 1.4, 0)) > MAX_REACH:
		return
	var info := ItemDB.info(item_id)
	if info.get("category", "") != "tool" or item_id != p.held_item():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_dig_at.get(peer, -100.0)) < 0.32:
		return
	_dig_at[peer] = now
	var vw := w.world_for(dim)
	var allowed_radius := 0.8 + int(info.get("mine_tier", 1)) * 0.06
	var plan := vw.plan_dig(point, clampf(radius, 0.3, allowed_radius), clampf(seconds, 0.0, Player.STRIKE_TIME), item_id)
	var changes: PackedInt32Array = plan["changes"]
	if changes.is_empty():
		return
	_broadcast(&"_voxels", [changes, dim])
	var removed: Dictionary = plan["removed"]
	for b: int in removed:
		var drop := Blocks.drop(b)
		if drop != "":
			w.drop_item(point, drop, int(removed[b]), dim)
		w.replicator.notify_mined(peer, b, int(removed[b]))


## Building up the ground with dirt, stone, sand...
func request_fill(point: Vector3, radius: float, block: int, dim: int) -> void:
	if Net.is_server():
		_resolve_fill(multiplayer.get_unique_id(), point, radius, block, dim)
	else:
		_request_fill.rpc_id(1, point, radius, block, dim)


@rpc("any_peer", "reliable")
func _request_fill(point: Vector3, radius: float, block: int, dim: int) -> void:
	if multiplayer.is_server():
		_resolve_fill(multiplayer.get_remote_sender_id(), point, radius, block, dim)


func _resolve_fill(peer: int, point: Vector3, radius: float, block: int, dim: int) -> void:
	var w := gw()
	var p := w.entity(player_net_id(peer)) as Player
	if p == null or p.dead or p.dimension != dim or block <= 0 or block >= Blocks.COUNT or not point.is_finite() or not is_finite(radius) or not Blocks.is_smooth(block):
		return
	if point.distance_to(p.global_position + Vector3(0, 1.4, 0)) > MAX_REACH:
		return
	# Never bury anyone.
	for e in w.entities_near(point, radius + 1.2, dim):
		if e.kind == "drop":
			continue  # loose items just pop back out of the ground
		if e.global_position.distance_to(point) < radius + 0.6 or e.center().distance_to(point) < radius + 0.6:
			return
	var changes := w.world_for(dim).plan_fill(point, clampf(radius, 0.3, 1.2), block)
	if not changes.is_empty():
		_broadcast(&"_voxels", [changes, dim])


@rpc("authority", "reliable", "call_local")
func _voxels(changes: PackedInt32Array, dim: int) -> void:
	var vw := gw().world_for(dim)
	if vw != null:
		vw.set_voxels(changes)


## Tell the miner what they got (quests count mined materials).
func notify_mined(peer: int, block: int, count: int) -> void:
	if peer == multiplayer.get_unique_id():
		_mined(block, count)
	else:
		_mined.rpc_id(peer, block, count)


@rpc("authority", "reliable")
func _mined(block: int, count: int) -> void:
	for i in count:
		Events.block_mined.emit(block, true)
		gw().quests.on_event("mine", Blocks.name_of(block).to_lower())


func request_block(pos: Vector3i, block: int, dim: int) -> void:
	if Net.is_server():
		_resolve_block(multiplayer.get_unique_id(), pos, block, dim)
	else:
		_request_block.rpc_id(1, pos, block, dim)


@rpc("any_peer", "reliable")
func _request_block(pos: Vector3i, block: int, dim: int) -> void:
	if multiplayer.is_server():
		_resolve_block(multiplayer.get_remote_sender_id(), pos, block, dim)


func _resolve_block(peer: int, pos: Vector3i, block: int, dim: int) -> void:
	var w := gw()
	var p := w.entity(player_net_id(peer)) as Player
	if p == null or p.dead or p.dimension != dim or block < 0 or block >= Blocks.COUNT:
		return
	if (Vector3(pos) + Vector3(0.5, 0.5, 0.5)).distance_to(p.global_position + Vector3(0, 1.4, 0)) > MAX_REACH:
		if OS.is_debug_build() and "--mp-test=host" in OS.get_cmdline_user_args():
			print("MP HOST note: block edit out of reach: %s vs player %s" % [pos, p.global_position])
		return
	var vw := w.world_for(dim)
	var current := vw.get_block(pos)
	if current < 0:
		return
	if block == Blocks.AIR:
		# Natural terrain can only be excavated through the density brush.
		if Blocks.is_smooth(current):
			return
		if not Blocks.is_breakable(current):
			return
		if Blocks.is_trunk(current):
			if not ItemDB.can_mine(p.held_item(), current):
				return
			_fell_tree(p, pos, current, dim)
			return
		broadcast_block(pos, Blocks.AIR, dim)
		var drop := Blocks.drop(current)
		if drop != "":
			w.drop_item(Vector3(pos) + Vector3(0.5, 0.5, 0.5), drop, 1, dim)
	else:
		if current != Blocks.AIR and not Blocks.is_liquid(current):
			return
		for e in w.entities_near(Vector3(pos) + Vector3(0.5, 0.0, 0.5), 2.0, dim):
			if e.body.overlaps_block(e.global_position, pos):
				return
		broadcast_block(pos, block, dim)


## Chopping any trunk block brings the whole tree down.
func _fell_tree(p: Player, pos: Vector3i, trunk: int, dim: int) -> void:
	var w := gw()
	var vw := w.world_for(dim)
	var bottom := pos
	while vw.get_block(bottom - Vector3i(0, 1, 0)) == trunk:
		bottom.y -= 1
	var cells: Array[Vector3i] = []
	var q := bottom
	while vw.get_block(q) == trunk and cells.size() < 16:
		cells.append(q)
		q.y += 1
	var dir := Vector3(bottom) + Vector3(0.5, 0, 0.5) - p.global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
	_broadcast(&"_fell", [bottom, trunk, dim, dir])
	for c in cells:
		broadcast_block(c, Blocks.AIR, dim)
	var info := WorldGen.tree_info(trunk, bottom)
	var logs := 2 + int(float(info[1]) / 2.5)
	w.drop_item(Vector3(bottom) + Vector3(0.5, 0.6, 0.5) + dir * 2.5, Blocks.drop(trunk), logs, dim)


@rpc("authority", "reliable", "call_local")
func _fell(root: Vector3i, trunk: int, dim: int, dir: Vector3) -> void:
	gw().fell_tree_fx(root, trunk, dim, dir)


func broadcast_block(pos: Vector3i, block: int, dim: int) -> void:
	_broadcast(&"_block", [pos, block, dim])


@rpc("authority", "reliable", "call_local")
func _block(pos: Vector3i, block: int, dim: int) -> void:
	var vw := gw().world_for(dim)
	if vw != null:
		vw.set_block(pos, block)


# --- Pickups and interaction -----------------------------------------------------------------

func request_pickup(id: int) -> void:
	if Net.is_server():
		_resolve_pickup(multiplayer.get_unique_id(), id)
	else:
		_request_pickup.rpc_id(1, id)


@rpc("any_peer", "reliable")
func _request_pickup(id: int) -> void:
	if multiplayer.is_server():
		_resolve_pickup(multiplayer.get_remote_sender_id(), id)


func _resolve_pickup(peer: int, id: int) -> void:
	var w := gw()
	var drop := w.entity(id)
	var p := w.entity(player_net_id(peer)) as Player
	if drop == null or p == null or drop.get_meta("taken", false):
		return
	if drop.global_position.distance_to(p.global_position) > 3.5:
		return
	drop.set_meta("taken", true)
	var data: Dictionary = drop.get_meta("spawn_data", {})
	give_item_to(peer, data.get("item", ""), int(data.get("count", 1)))
	w.despawn_entity(drop)


func request_interact(id: int) -> void:
	if Net.is_server():
		_resolve_interact(multiplayer.get_unique_id(), id)
	else:
		_request_interact.rpc_id(1, id)


@rpc("any_peer", "reliable")
func _request_interact(id: int) -> void:
	if multiplayer.is_server():
		_resolve_interact(multiplayer.get_remote_sender_id(), id)


func _resolve_interact(peer: int, id: int) -> void:
	var w := gw()
	var target := w.entity(id)
	var p := w.entity(player_net_id(peer)) as Player
	if target == null or p == null or target.global_position.distance_to(p.global_position) > 5.0:
		return
	if target.has_method("server_interact"):
		target.call("server_interact", p)


func broadcast_entity_event(id: int, event: String, arg: Variant = null) -> void:
	_broadcast(&"_entity_event", [id, event, arg])


@rpc("authority", "reliable", "call_local")
func _entity_event(id: int, event: String, arg: Variant) -> void:
	var e := gw().entity(id)
	if e != null and e.has_method("on_event"):
		e.call("on_event", event, arg)


# --- Clock and weather ----------------------------------------------------------------------

func broadcast_clock(t: float, day: int, weather_state: String) -> void:
	if Net.is_online() and Net.is_server():
		_broadcast(&"_clock", [t, day, weather_state], false)


@rpc("authority", "unreliable")
func _clock(t: float, day: int, weather_state: String) -> void:
	var w := gw()
	w.sky.sync_time(t, day)
	w.weather.sync_state(weather_state)


func broadcast_lightning(pos: Vector3, dim: int) -> void:
	_broadcast(&"_lightning", [pos, dim])


@rpc("authority", "reliable", "call_local")
func _lightning(pos: Vector3, dim: int) -> void:
	var w := gw()
	if dim == w.local_dimension:
		w.weather.strike_fx(pos)
