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
var _known := {}           # peer -> {net_id: true} spawned on that peer (server)


static func player_net_id(peer: int) -> int:
	return -peer


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
			1 if p.dead else 0, p.display_name, p.offhand_light]
	if Net.is_server():
		_relay_player_state(multiplayer.get_unique_id(), state)
	else:
		_player_state.rpc_id(1, state)


@rpc("any_peer", "unreliable_ordered")
func _player_state(state: Array) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	_apply_player_state(peer, state)
	_relay_player_state(peer, state)


func _relay_player_state(peer: int, state: Array) -> void:
	_peer_dim[peer] = int(state[0])
	for other in multiplayer.get_peers():
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
	_peer_dim.erase(peer)
	_known.erase(peer)


func notify_dimension(dim: int) -> void:
	if Net.is_online() and not Net.is_server():
		_client_dimension.rpc_id(1, dim)
	elif Net.is_server():
		_peer_dim[multiplayer.get_unique_id()] = dim


@rpc("any_peer", "reliable")
func _client_dimension(dim: int) -> void:
	if multiplayer.is_server():
		_peer_dim[multiplayer.get_remote_sender_id()] = dim


## A client finished loading: send it everything that already exists.
func client_ready() -> void:
	if Net.is_online() and not Net.is_server():
		_client_ready.rpc_id(1, gw().local_dimension)


@rpc("any_peer", "reliable")
func _client_ready(dim: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	_peer_dim[peer] = dim
	_known[peer] = {}
	_sync_bosses.rpc_id(peer, gw().bosses_defeated.keys())
	_clock.rpc_id(peer, gw().sky.time_of_day, gw().sky.day, gw().weather.state_name())


# --- Spawning ------------------------------------------------------------------------

func broadcast_spawn(e: Entity, data: Dictionary) -> void:
	e.set_meta("spawn_data", data)
	if not Net.is_online():
		return
	for peer in multiplayer.get_peers():
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
	for peer in multiplayer.get_peers():
		if _known.has(peer):
			_known[peer].erase(id)
		_despawn.rpc_id(peer, id)


@rpc("authority", "reliable")
func _despawn(id: int) -> void:
	gw().remove_entity(id)


func _send_snapshots() -> void:
	var w := gw()
	var now := _now()
	for peer in multiplayer.get_peers():
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
	_damage_fx.rpc(pos, amount, crit, kind, dim) if Net.is_online() else _damage_fx(pos, amount, crit, kind, dim)


@rpc("authority", "unreliable", "call_local")
func _damage_fx(pos: Vector3, amount: int, crit: bool, kind: String, dim: int) -> void:
	if dim != gw().local_dimension:
		return
	Events.damage_number.emit(pos, amount, crit, kind)
	Audio.play("crit" if crit else "hit", pos)


func broadcast_projectile(kind: String, origin: Vector3, velocity: Vector3, owner_id: int, team: int, dim: int, dmg: float) -> void:
	if Net.is_online():
		_projectile.rpc(kind, origin, velocity, owner_id, team, dim, dmg)
	else:
		_projectile(kind, origin, velocity, owner_id, team, dim, dmg)


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
	if Net.is_online():
		_telegraph.rpc(shape, pos, dir, size, duration, dim)
	else:
		_telegraph(shape, pos, dir, size, duration, dim)


@rpc("authority", "reliable", "call_local")
func _telegraph(shape: String, pos: Vector3, dir: Vector3, size: Vector3, duration: float, dim: int) -> void:
	gw().show_telegraph(shape, pos, dir, size, duration, dim)


func broadcast_shake(strength: float, at: Vector3, dim: int) -> void:
	if Net.is_online():
		_shake.rpc(strength, at, dim)
	else:
		_shake(strength, at, dim)


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
	if Net.is_online():
		_boss_state.rpc(id, engaged, kind, defeated)
	else:
		_boss_state(id, engaged, kind, defeated)


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
		if defeated:
			w.bosses_defeated[kind] = true
			Events.boss_defeated.emit(kind, boss.display_name if boss != null else kind)
			Events.slow_motion.emit(1.4, 0.3)
			w.quests.on_event("boss", kind)
			Audio.play_ui("levelup")
		Audio.set_music("hell" if w.local_dimension == 1 else "explore")


func sync_bosses_defeated(defeated: Dictionary) -> void:
	if Net.is_online():
		_sync_bosses.rpc(defeated.keys())


@rpc("authority", "reliable")
func _sync_bosses(kinds: Array) -> void:
	for k in kinds:
		gw().bosses_defeated[String(k)] = true


func broadcast_victory() -> void:
	if Net.is_online():
		_victory.rpc()
	else:
		_victory()


@rpc("authority", "reliable", "call_local")
func _victory() -> void:
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
	if p == null or p.dimension != dim:
		return
	if (Vector3(pos) + Vector3(0.5, 0.5, 0.5)).distance_to(p.global_position + Vector3(0, 1.4, 0)) > MAX_REACH:
		return
	var vw := w.world_for(dim)
	var current := vw.get_block(pos)
	if current < 0:
		return
	if block == Blocks.AIR:
		if not Blocks.is_breakable(current):
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


func broadcast_block(pos: Vector3i, block: int, dim: int) -> void:
	if Net.is_online():
		_block.rpc(pos, block, dim)
	else:
		_block(pos, block, dim)


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
	if Net.is_online():
		_entity_event.rpc(id, event, arg)
	else:
		_entity_event(id, event, arg)


@rpc("authority", "reliable", "call_local")
func _entity_event(id: int, event: String, arg: Variant) -> void:
	var e := gw().entity(id)
	if e != null and e.has_method("on_event"):
		e.call("on_event", event, arg)


# --- Clock and weather ----------------------------------------------------------------------

func broadcast_clock(t: float, day: int, weather_state: String) -> void:
	if Net.is_online() and Net.is_server():
		_clock.rpc(t, day, weather_state)


@rpc("authority", "unreliable")
func _clock(t: float, day: int, weather_state: String) -> void:
	var w := gw()
	w.sky.sync_time(t, day)
	w.weather.sync_state(weather_state)


func broadcast_lightning(pos: Vector3, dim: int) -> void:
	if Net.is_online():
		_lightning.rpc(pos, dim)
	else:
		_lightning(pos, dim)


@rpc("authority", "reliable", "call_local")
func _lightning(pos: Vector3, dim: int) -> void:
	var w := gw()
	if dim == w.local_dimension:
		w.weather.strike_fx(pos)
