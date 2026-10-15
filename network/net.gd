extends Node
## Autoload "Net": LAN parties joined with a four-rune code.
##
## Solo play runs on an OfflineMultiplayerPeer, so `multiplayer.is_server()`
## is true and gameplay RPCs with `call_local` behave exactly as when hosting.
##
## Hosting: ENet server (port 47211, or the next free one up to 47220) plus a
## LanDiscovery responder. Joining: LanDiscovery finds the host by runes, then
## ENet connects, the client says hello (name, protocol version, runes) and the
## host either accepts (lobby broadcast to everyone) or rejects with a reason.
##
## The lobby (`players`) is host-authoritative and mirrored on every peer.
## start_campaign() ships an opaque info Dictionary (compressed, chunked, on its
## own reliable channel) to every peer, and later to anyone who joins mid-game.
##
## Testing aids: sim_latency_ms / sim_loss wrap the ENet peer in a LagPeer
## (also from the command line: --sim-latency=150 --sim-loss=0.02), and
## --host / --join=R3-R12-R0-R7 / --name=Ash start a party from the command line.

signal lobby_changed
signal session_started(info: Dictionary)
signal join_failed(reason: String)
signal peer_left(id: int, player_name: String)
## Emitted on the host when it starts a party with a new rune code.
signal hosting_started(runes: PackedInt32Array)
## Joiner progress for the lobby UI: "searching", "connecting", "joined".
signal join_status(state: String)
## Host: the internet address friends outside the LAN can join with (after UPnP).
signal public_address_changed(address: String)

const PROTOCOL_VERSION := 2
## Hello code for players who joined by address instead of runes.
const ADDRESS_JOIN := -1
const MAX_PLAYERS := 8
const ENET_PORTS: Array[int] = [47211, 47212, 47213, 47214, 47215, 47216, 47217, 47218, 47219, 47220]
const CHUNK_BYTES := 32 * 1024
const BULK_CHANNEL := 1
const HELLO_TIMEOUT := 10.0
const PALETTE: Array[Color] = [
	Color(1.0, 0.55, 0.2), Color(0.3, 0.8, 0.85), Color(0.7, 0.45, 0.95), Color(0.95, 0.8, 0.3),
	Color(0.9, 0.25, 0.3), Color(0.45, 0.85, 0.4), Color(0.45, 0.6, 1.0), Color(0.95, 0.5, 0.7),
]

## peer_id -> {"name": String, "color": Color, "ready": bool}
var players := {}
## The current party's code (empty when not in a party).
var runes := PackedInt32Array()
## The info the campaign was started with (host and clients), {} before.
var session_info := {}
## Host: optional builder for the info sent to players who join mid-game
## (e.g. the current world edits). Default: the original session_info.
var late_join_info := Callable()
var enet_port := 0
## Host's public "ip:port" once the router opened the port via UPnP ("" otherwise).
var public_address := ""
var _upnp_thread: Thread
var _upnp_port := 0
var _join_by_address := false

var sim_latency_ms := 0.0:
	set(v):
		sim_latency_ms = v
		if _lag != null:
			_lag.latency_ms = v
var sim_loss := 0.0:
	set(v):
		sim_loss = v
		if _lag != null:
			_lag.loss = v

var _discovery := LanDiscovery.new()
var _lag: LagPeer
var _enet: ENetMultiplayerPeer
var _joining_runes := PackedInt32Array()
var _joining_name := ""
var _rejected_reason := ""
var _pending_hello := {}      # host: peer_id -> seconds waited
var _incoming := {}           # transfer id -> {total, raw, parts: Array}
var _clock_offset := 0.0      # client: host clock - local clock (seconds)
var _offset_ready := false
var _ping := {}               # peer -> smoothed ms (host: per client; client: key 1)
var _ping_timer := 0.0
var _campaign_started := false


func _ready() -> void:
	add_child(_discovery)
	_discovery.found.connect(_on_found)
	_discovery.failed.connect(_on_discovery_failed)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_go_offline()
	_handle_command_line.call_deferred()


func _handle_command_line() -> void:
	var name_arg := ""
	var join_arg := ""
	var addr_arg := ""
	var host := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sim-latency="):
			sim_latency_ms = float(arg.trim_prefix("--sim-latency="))
		elif arg.begins_with("--sim-loss="):
			sim_loss = float(arg.trim_prefix("--sim-loss="))
		elif arg.begins_with("--name="):
			name_arg = arg.trim_prefix("--name=")
		elif arg == "--host":
			host = true
		elif arg.begins_with("--join="):
			join_arg = arg.trim_prefix("--join=")
		elif arg.begins_with("--join-address="):
			addr_arg = arg.trim_prefix("--join-address=")
	var who := name_arg if name_arg != "" else _default_name()
	if host:
		var code := host_party(who)
		print("BURN_RUNES %s" % RuneCode.to_text(code))
	elif addr_arg != "":
		join_status.connect(func(state: String) -> void:
			if state == "joined":
				print("BURN_JOINED %s as %s" % [addr_arg, _my_name()]))
		join_failed.connect(func(reason: String) -> void: print("BURN_JOIN_FAILED %s" % reason))
		join_address(addr_arg, who)
	elif join_arg != "":
		var code := RuneCode.from_text(join_arg)
		if code.is_empty():
			push_error("--join: not a rune code: %s" % join_arg)
		else:
			join_status.connect(func(state: String) -> void:
				if state == "joined":
					print("BURN_JOINED %s as %s" % [RuneCode.to_text(runes), _my_name()]))
			join_failed.connect(func(reason: String) -> void: print("BURN_JOIN_FAILED %s" % reason))
			join_party(code, who)


func _default_name() -> String:
	var s := get_node_or_null("/root/Settings")
	return String(s.get_value("gameplay", "player_name")) if s != null else "Wanderer"


# --- Public API -----------------------------------------------------------------

## Host a party. Returns the rune code to share ([] on failure, join_failed emitted).
func host_party(player_name: String, forced_runes := PackedInt32Array()) -> PackedInt32Array:
	leave()
	_enet = ENetMultiplayerPeer.new()
	var err := ERR_CANT_CREATE
	for port in ENET_PORTS:
		err = _enet.create_server(port, MAX_PLAYERS - 1, 3)
		if err == OK:
			enet_port = port
			break
		_enet = ENetMultiplayerPeer.new()
	if err != OK:
		_enet = null
		join_failed.emit("Could not open a port to host the party (another program may be using it).")
		return PackedInt32Array()
	_install_peer(_enet)
	runes = forced_runes if RuneCode.is_valid(forced_runes) else RuneCode.random()
	players = {1: {"name": _clean_name(player_name), "color": PALETTE[0], "ready": true}}
	var derr := _discovery.start_responder(RuneCode.encode(runes), enet_port, players[1]["name"], PROTOCOL_VERSION,
			func() -> int: return players.size(), MAX_PLAYERS)
	if derr != OK:
		push_warning("LAN discovery port busy: friends on other machines may not find this party.")
	_campaign_started = false
	session_info = {}
	_open_router_port(enet_port)
	hosting_started.emit(runes)
	lobby_changed.emit()
	return runes


## Find a party by runes on the LAN and join it. Progress via join_status,
## outcome via lobby_changed (joined) or join_failed.
func join_party(code: PackedInt32Array, player_name: String) -> void:
	leave()
	if not RuneCode.is_valid(code):
		join_failed.emit("Those runes are not a valid party code.")
		return
	_joining_runes = code
	_joining_name = _clean_name(player_name)
	join_status.emit("searching")
	_discovery.search(RuneCode.encode(code), PROTOCOL_VERSION)


## Join a party over the internet (or a LAN without broadcast) by address,
## "host:port" or a bare host (default port). Runes are optional here: an
## address is already private enough to share between friends.
func join_address(address: String, player_name: String, code := PackedInt32Array()) -> void:
	leave()
	var host := address.strip_edges()
	var port := ENET_PORTS[0]
	var colon := host.rfind(":")
	if colon > 0 and host.count(":") == 1:
		port = int(host.substr(colon + 1))
		host = host.substr(0, colon)
	if host == "" or port <= 0:
		join_failed.emit("That isn't a valid address.")
		return
	_joining_runes = code
	_joining_name = _clean_name(player_name)
	_join_by_address = true
	join_status.emit("connecting")
	_on_found(host, port, host)


## Ask the router (UPnP) to forward the game port so friends can join over the
## internet. Runs on a thread: discovery can take a few seconds.
func _open_router_port(port: int) -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return
	_close_router_port()
	_upnp_port = port
	_upnp_thread = Thread.new()
	_upnp_thread.start(func() -> void:
		var upnp := UPNP.new()
		if upnp.discover(2500, 2, "InternetGatewayDevice") != UPNP.UPNP_RESULT_SUCCESS:
			return
		var gw := upnp.get_gateway()
		if gw == null or not gw.is_valid_gateway():
			return
		if upnp.add_port_mapping(port, port, "Burn party", "UDP", 0) != UPNP.UPNP_RESULT_SUCCESS:
			return
		var ip := upnp.query_external_address()
		if ip != "":
			_set_public_address.call_deferred("%s:%d" % [ip, port]))


func _set_public_address(address: String) -> void:
	public_address = address
	public_address_changed.emit(address)


func _close_router_port() -> void:
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if _upnp_port != 0 and public_address != "":
		var port := _upnp_port
		var t := Thread.new()
		t.start(func() -> void:
			var upnp := UPNP.new()
			if upnp.discover(1500, 2, "InternetGatewayDevice") == UPNP.UPNP_RESULT_SUCCESS:
				upnp.delete_port_mapping(port, "UDP"))
		t.wait_to_finish()
	_upnp_port = 0
	if public_address != "":
		_set_public_address("")


## Leave the party (or stop hosting) and return to solo.
func leave() -> void:
	_close_router_port()
	_join_by_address = false
	_discovery.stop_responder()
	_discovery.stop_search()
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	_go_offline()


func set_ready(ready: bool) -> void:
	if not is_online():
		return
	if is_server():
		_set_ready_for(1, ready)
	else:
		_rpc_set_ready.rpc_id(1, ready)


func kick(peer_id: int, reason := "You were removed from the party.") -> void:
	if is_online() and is_server() and peer_id != 1:
		_reject(peer_id, reason)


## Host: start (or restart) the campaign for everyone.
func start_campaign(info: Dictionary) -> void:
	if not is_server():
		return
	session_info = info
	_campaign_started = true
	if is_online():
		_send_session(0, info)
	session_started.emit(info)


func send_chat(text: String) -> void:
	var t := _clean_chat(text)
	if t == "":
		return
	if not is_online():
		_emit_chat(_my_name(), t)
	elif is_server():
		_rpc_chat.rpc(players.get(1, {}).get("name", "Host"), t)
	else:
		_rpc_chat_request.rpc_id(1, t)


func is_online() -> bool:
	var p := multiplayer.multiplayer_peer
	return p != null and not p is OfflineMultiplayerPeer \
			and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_server() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


func is_host() -> bool:
	return is_online() and is_server()


func my_id() -> int:
	return multiplayer.get_unique_id()


func player_name(peer_id: int) -> String:
	return String(players.get(peer_id, {}).get("name", "Wanderer"))


func player_color(peer_id: int) -> Color:
	return players.get(peer_id, {}).get("color", PALETTE[0])


## Shared clock in seconds: the host's clock, estimated on clients.
func server_time() -> float:
	var local := Time.get_ticks_usec() / 1000000.0
	return local if is_server() else local + _clock_offset


## Round trip in ms. Client: to the host. Host: to `peer_id` (worst client if -1).
func ping_ms(peer_id := -1) -> float:
	if not is_online():
		return 0.0
	if not is_server():
		return float(_ping.get(1, 0.0))
	if peer_id > 0:
		return float(_ping.get(peer_id, 0.0))
	var worst := 0.0
	for id: int in _ping:
		worst = maxf(worst, _ping[id])
	return worst


# --- Peer plumbing ----------------------------------------------------------------

func _install_peer(peer: MultiplayerPeer) -> void:
	if sim_latency_ms > 0.0 or sim_loss > 0.0:
		_lag = LagPeer.new(peer, sim_latency_ms, sim_loss)
		multiplayer.multiplayer_peer = _lag
	else:
		_lag = null
		multiplayer.multiplayer_peer = peer
	var sm := multiplayer as SceneMultiplayer
	if sm != null:
		sm.server_relay = true


func _go_offline() -> void:
	_lag = null
	_enet = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players = {}
	runes = PackedInt32Array()
	_pending_hello.clear()
	_incoming.clear()
	_ping.clear()
	_offset_ready = false
	_clock_offset = 0.0
	_campaign_started = false
	enet_port = 0


func _on_found(address: String, port: int, host_name: String) -> void:
	join_status.emit("connecting")
	_enet = ENetMultiplayerPeer.new()
	var err := _enet.create_client(address, port, 3)
	if err != OK:
		_enet = null
		join_failed.emit("Could not connect to %s's party." % host_name)
		return
	_install_peer(_enet)


func _on_discovery_failed(reason: String) -> void:
	join_failed.emit(reason)


func _on_connected_to_server() -> void:
	var code := RuneCode.encode(_joining_runes) if RuneCode.is_valid(_joining_runes) else ADDRESS_JOIN
	_rpc_hello.rpc_id(1, _joining_name, PROTOCOL_VERSION, code)


func _on_connection_failed() -> void:
	_go_offline()
	join_failed.emit("Could not connect to the party host.")


func _on_server_disconnected() -> void:
	var reason := _rejected_reason if _rejected_reason != "" else "The host closed the party."
	_rejected_reason = ""
	_go_offline()
	lobby_changed.emit()
	join_failed.emit(reason)


func _on_peer_connected(id: int) -> void:
	_tune_enet_peer(id)
	if is_server() and id != 1:
		_pending_hello[id] = 0.0


## ENet's adaptive throttle drops unreliable packets for seconds after a burst
## of reliable traffic (e.g. the session payload) inflates the round trip. On a
## LAN that only loses snapshots, so keep the throttle at maximum.
func _tune_enet_peer(id: int) -> void:
	if _enet == null:
		return
	var p := _enet.get_peer(id)
	if p != null:
		p.throttle_configure(5000, 32, 0)


func _on_peer_disconnected(id: int) -> void:
	_pending_hello.erase(id)
	_ping.erase(id)
	if not is_server() or not players.has(id):
		return
	var who: String = players[id]["name"]
	players.erase(id)
	_broadcast_lobby()
	_rpc_peer_left.rpc(id, who)
	peer_left.emit(id, who)


func _process(delta: float) -> void:
	if not is_online():
		return
	if is_server():
		for id: int in _pending_hello.keys():
			_pending_hello[id] += delta
			if _pending_hello[id] > HELLO_TIMEOUT:
				_pending_hello.erase(id)
				multiplayer.multiplayer_peer.disconnect_peer(id)
	_ping_timer -= delta
	if _ping_timer <= 0.0:
		_ping_timer = 1.0 if _offset_ready else 0.25
		var now := Time.get_ticks_usec() / 1000000.0
		if is_server():
			for id: int in players:
				if id != 1:
					_rpc_host_ping.rpc_id(id, now)
		else:
			_rpc_ping.rpc_id(1, now)


# --- Lobby (host authoritative) -----------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(requested_name: String, version: int, code: int) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	_pending_hello.erase(id)
	if version != PROTOCOL_VERSION:
		_reject(id, "That party is running a different version of Burn.")
		return
	if code != RuneCode.encode(runes) and code != ADDRESS_JOIN:
		_reject(id, "No party with those runes was found on your network.")
		return
	if players.size() >= MAX_PLAYERS:
		_reject(id, "That party is full.")
		return
	players[id] = {"name": _unique_name(_clean_name(requested_name)), "color": _free_color(), "ready": false}
	_broadcast_lobby()
	lobby_changed.emit()
	if _campaign_started:
		var info: Dictionary = late_join_info.call() if late_join_info.is_valid() else session_info
		_send_session(id, info)


func _reject(id: int, reason: String) -> void:
	_rpc_rejected.rpc_id(id, reason)
	# Give the reason a moment to arrive before dropping the connection.
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
			multiplayer.multiplayer_peer.disconnect_peer(id))


@rpc("authority", "call_remote", "reliable")
func _rpc_rejected(reason: String) -> void:
	_rejected_reason = reason


func _broadcast_lobby() -> void:
	for id: int in players:
		if id != 1:
			_rpc_lobby.rpc_id(id, players, RuneCode.encode(runes))


@rpc("authority", "call_remote", "reliable")
func _rpc_lobby(lobby: Dictionary, code: int) -> void:
	var first := players.is_empty()
	players = lobby
	runes = RuneCode.decode(code)
	if first:
		join_status.emit("joined")
	lobby_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_ready(ready: bool) -> void:
	if is_server():
		_set_ready_for(multiplayer.get_remote_sender_id(), ready)


func _set_ready_for(id: int, ready: bool) -> void:
	if not players.has(id):
		return
	players[id]["ready"] = ready
	_broadcast_lobby()
	lobby_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_peer_left(id: int, who: String) -> void:
	peer_left.emit(id, who)


func _unique_name(n: String) -> String:
	var taken := {}
	for id: int in players:
		taken[String(players[id]["name"]).to_lower()] = true
	if not taken.has(n.to_lower()):
		return n
	var i := 2
	while taken.has(("%s (%d)" % [n, i]).to_lower()):
		i += 1
	return "%s (%d)" % [n, i]


func _free_color() -> Color:
	for c in PALETTE:
		var used := false
		for id: int in players:
			if players[id]["color"] == c:
				used = true
		if not used:
			return c
	return PALETTE[players.size() % PALETTE.size()]


static func _clean_name(n: String) -> String:
	var s := n.strip_edges().replace("|", "/").left(20)
	return s if s != "" else "Wanderer"


static func _clean_chat(t: String) -> String:
	return t.strip_edges().replace("\n", " ").left(200)


func _my_name() -> String:
	if players.has(my_id()):
		return players[my_id()]["name"]
	return _clean_name(_default_name())


# --- Chat -----------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _rpc_chat_request(text: String) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id):
		return
	var t := _clean_chat(text)
	if t != "":
		_rpc_chat.rpc(players[id]["name"], t)


@rpc("authority", "call_local", "reliable")
func _rpc_chat(from_name: String, text: String) -> void:
	_emit_chat(from_name, text)


func _emit_chat(from_name: String, text: String) -> void:
	var ev := get_node_or_null("/root/Events")
	if ev != null:
		ev.chat_message.emit(from_name, text, "party")


# --- Session transfer -------------------------------------------------------------------

## target 0 = every accepted peer.
func _send_session(target: int, info: Dictionary) -> void:
	var raw := var_to_bytes(info)
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var total := maxi(1, ceili(packed.size() / float(CHUNK_BYTES)))
	var transfer := randi()
	var targets: Array[int] = []
	if target == 0:
		for id: int in players:
			if id != 1:
				targets.append(id)
	else:
		targets.append(target)
	for id in targets:
		for i in total:
			_rpc_session_chunk.rpc_id(id, transfer, i, total, raw.size(), packed.slice(i * CHUNK_BYTES, (i + 1) * CHUNK_BYTES))


@rpc("authority", "call_remote", "reliable", BULK_CHANNEL)
func _rpc_session_chunk(transfer: int, index: int, total: int, raw_size: int, data: PackedByteArray) -> void:
	if not _incoming.has(transfer):
		var parts := []
		parts.resize(total)
		_incoming[transfer] = {"total": total, "raw": raw_size, "parts": parts, "have": 0}
	var t: Dictionary = _incoming[transfer]
	if t["parts"][index] == null:
		t["parts"][index] = data
		t["have"] += 1
	if t["have"] < t["total"]:
		return
	_incoming.erase(transfer)
	var packed := PackedByteArray()
	for p: PackedByteArray in t["parts"]:
		packed.append_array(p)
	var raw := packed.decompress(int(t["raw"]), FileAccess.COMPRESSION_ZSTD)
	var info: Variant = bytes_to_var(raw)
	if info is Dictionary:
		session_info = info
		_campaign_started = true
		session_started.emit(info)
	else:
		push_error("Net: received a corrupt session payload.")


# --- Clock and ping ------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable")
func _rpc_ping(client_time: float) -> void:
	if is_server():
		_rpc_pong.rpc_id(multiplayer.get_remote_sender_id(), client_time, Time.get_ticks_usec() / 1000000.0)


@rpc("authority", "call_remote", "unreliable")
func _rpc_pong(client_time: float, host_time: float) -> void:
	var now := Time.get_ticks_usec() / 1000000.0
	var rtt := maxf(0.0, now - client_time)
	var offset := host_time + rtt * 0.5 - now
	if not _offset_ready:
		_clock_offset = offset
		_offset_ready = true
		_ping[1] = rtt * 1000.0
	else:
		_clock_offset = lerpf(_clock_offset, offset, 0.15)
		_ping[1] = lerpf(float(_ping.get(1, rtt * 1000.0)), rtt * 1000.0, 0.25)


@rpc("authority", "call_remote", "unreliable")
func _rpc_host_ping(host_time: float) -> void:
	_rpc_host_pong.rpc_id(1, host_time)


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_host_pong(host_time: float) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var rtt := maxf(0.0, Time.get_ticks_usec() / 1000000.0 - host_time) * 1000.0
	_ping[id] = lerpf(float(_ping.get(id, rtt)), rtt, 0.25)
