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
## Everyone: a player was accepted into the party (host decides, then tells all).
signal player_joined(id: int, player_name: String)

## 5: hello carries a server password; chat whispers / system messages.
const PROTOCOL_VERSION := 5
## Hello code for players who joined by address instead of runes.
const ADDRESS_JOIN := -1
const MAX_PLAYERS := 8
const ENET_PORTS: Array[int] = [47211, 47212, 47213, 47214, 47215, 47216, 47217, 47218, 47219, 47220]
const CHUNK_BYTES := 32 * 1024
const BULK_CHANNEL := 1
const HELLO_TIMEOUT := 10.0
## Chat flood control per peer (host side): a burst, then one message per CHAT_REFILL s.
const CHAT_BURST := 5
const CHAT_REFILL := 1.2
const CHAT_MAX := 200
const PASSWORD_MAX := 64
## Wrong passwords per address before the host refuses it for PASSWORD_LOCKOUT s.
const PASSWORD_TRIES := 5
const PASSWORD_LOCKOUT := 60.0
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
## Host-chosen rules, mirrored before the campaign and included in the session.
## shrine_respawn: automatic shrine returns (off: teammates must revive).
const DEFAULT_LOBBY_OPTIONS := {"shrine_respawn": false}
var lobby_options := DEFAULT_LOBBY_OPTIONS.duplicate()
## Host: optional builder for the info sent to players who join mid-game
## (e.g. the current world edits). Default: the original session_info.
var late_join_info := Callable()
var enet_port := 0
## Host's public "ip:port" once the router opened the port via UPnP ("" otherwise).
var public_address := ""
var _upnp_thread: Thread
var _upnp_port := 0
var _join_by_address := false
## Public / listed server settings (host): {"name", "description", "password",
## "max_players", "mode", "internet": register with the master, "lan": answer
## LAN browsing, "dedicated": headless host without a player}. {} = rune party.
var server_config := {}
## Accepted players allowed (excluding a dedicated host).
var max_players := MAX_PLAYERS
## Headless dedicated server: the host's own player is a hidden spectator.
var dedicated := false
## Master server registration while hosting a public server.
var server_list := ServerList.new()
var _password := ""
var _join_password := ""
var _chat_budget := {}        # host: peer -> [tokens, last seconds]
var _bad_password := {}       # host: ip -> [count, first failure seconds]
var _bans := {}               # host: ip -> until (seconds)

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
	server_list.name = "ServerList"
	add_child(server_list)
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
	var pass_arg := ""
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
		elif arg.begins_with("--join-password="):
			pass_arg = arg.trim_prefix("--join-password=")
	var who := name_arg if name_arg != "" else _default_name()
	if host:
		var code := host_party(who)
		print("BURN_RUNES %s" % RuneCode.to_text(code))
	elif addr_arg != "":
		join_status.connect(func(state: String) -> void:
			if state == "joined":
				print("BURN_JOINED %s as %s" % [addr_arg, _my_name()]))
		join_failed.connect(func(reason: String) -> void: print("BURN_JOIN_FAILED %s" % reason))
		join_address(addr_arg, who, PackedInt32Array(), pass_arg)
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
## `config`: see `server_config` (public / LAN-listed / dedicated servers).
func host_party(player_name: String, forced_runes := PackedInt32Array(), config := {}) -> PackedInt32Array:
	leave()
	server_config = config.duplicate()
	dedicated = bool(config.get("dedicated", false))
	max_players = clampi(int(config.get("max_players", MAX_PLAYERS)), 1 if dedicated else 2, MAX_PLAYERS)
	_password = String(config.get("password", "")).left(PASSWORD_MAX)
	_enet = ENetMultiplayerPeer.new()
	var err := ERR_CANT_CREATE
	for port in ENET_PORTS:
		# One spare slot so a full server can still tell a joiner "full".
		err = _enet.create_server(port, max_players - (0 if dedicated else 1) + 1, 3)
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
	if dedicated:
		players[1]["server"] = true
	var derr := _discovery.start_responder(RuneCode.encode(runes), enet_port, players[1]["name"], PROTOCOL_VERSION,
			player_count, max_players)
	if derr != OK:
		push_warning("LAN discovery port busy: friends on other machines may not find this party.")
	elif bool(config.get("lan", false)) or bool(config.get("internet", false)):
		_discovery.listing = {"name": _server_name(), "description": String(config.get("description", "")),
			"mode": String(config.get("mode", "Campaign")), "locked": _password != ""}
	_campaign_started = false
	session_info = {}
	if not dedicated or bool(config.get("upnp", false)):
		_open_router_port(enet_port)
	if bool(config.get("internet", false)):
		server_list.start_hosting(listing_info)
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
## address is already private enough to share between friends. Public servers
## may need `password`.
func join_address(address: String, player_name: String, code := PackedInt32Array(), password := "") -> void:
	leave()
	_join_password = password.left(PASSWORD_MAX)
	var host := address.strip_edges()
	var port := ENET_PORTS[0]
	var colon := host.rfind(":")
	if host.begins_with("[") and host.contains("]"):  # [ipv6]:port
		var close := host.find("]")
		if host.substr(close + 1).begins_with(":"):
			port = int(host.substr(close + 2))
		host = host.substr(1, close - 1)
	elif colon > 0 and host.count(":") == 1:
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
	if (DisplayServer.get_name() == "headless" and not dedicated) or OS.has_feature("web"):
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
	server_list.stop_hosting()
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


## Host: remove a player. `ban_seconds` > 0 refuses their address for that long.
func kick(peer_id: int, reason := "You were removed from the party.", ban_seconds := 0.0) -> void:
	if is_online() and is_server() and peer_id != 1:
		if ban_seconds > 0.0:
			var ip := _peer_ip(peer_id)
			if ip != "":
				_bans[ip] = _now() + ban_seconds
		_reject(peer_id, reason)


## Host: start (or restart) the campaign for everyone.
func set_lobby_option(key: String, value: Variant) -> void:
	if not is_server() or not DEFAULT_LOBBY_OPTIONS.has(key) or not value is bool:
		return
	lobby_options[key] = value
	if is_online():
		_broadcast_lobby()
	lobby_changed.emit()


## A party rule for this session (falls back to the lobby's choice, then default).
func option(key: String, default: Variant = null) -> Variant:
	var opts: Dictionary = session_info.get("options", lobby_options)
	return opts.get(key, lobby_options.get(key, default))


func start_campaign(info: Dictionary) -> void:
	if not is_server():
		return
	if not info.has("options"):
		info["options"] = lobby_options.duplicate()
	session_info = info
	_campaign_started = true
	if is_online():
		_send_session(0, info)
	session_started.emit(info)


func send_chat(text: String) -> void:
	var t := clean_chat(text)
	if t == "":
		return
	if not is_online():
		_emit_chat(_my_name(), t)
	elif is_server():
		_to_party(&"_rpc_chat", [players.get(1, {}).get("name", "Host"), t])
	else:
		_rpc_chat_request.rpc_id(1, t)


## Private message routed by the host. Errors come back as system messages.
func send_whisper(target_name: String, text: String) -> void:
	var t := clean_chat(text)
	if t == "" or target_name.strip_edges() == "":
		return
	if not is_online():
		_emit_system("Whispers reach other players in online games.")
	elif is_server():
		_route_whisper(1, target_name, t)
	else:
		_rpc_whisper_request.rpc_id(1, target_name.left(40), t)


## Tell the party this player fell (host broadcasts a system line).
func announce_death(cause: String) -> void:
	if not is_online():
		return
	if is_server():
		_broadcast_death(1, cause)
	else:
		_rpc_death.rpc_id(1, cause.left(60))


## Host: a system line for everyone in the party (and the host).
func broadcast_system(text: String) -> void:
	if is_server():
		_to_party(&"_rpc_system", [clean_chat(text)])


## Peer id of the player with this name (case-insensitive; a unique prefix also matches). -1 if none.
func find_player(player_name: String) -> int:
	var want := player_name.strip_edges().to_lower()
	if want == "":
		return -1
	var prefix := []
	for id: int in players:
		var n := String(players[id]["name"]).to_lower()
		if n == want:
			return id
		if n.begins_with(want):
			prefix.append(id)
	return prefix[0] if prefix.size() == 1 else -1


## Players in the party, not counting a dedicated server's host.
func player_count() -> int:
	return players.size() - (1 if dedicated and players.has(1) else 0)


## The public listing of this server (master registration, LAN browsing).
func listing_info() -> Dictionary:
	return {"name": _server_name(), "description": String(server_config.get("description", "")).left(160),
		"version": String(ProjectSettings.get_setting("application/config/version", "")).left(24),
		"protocol": PROTOCOL_VERSION, "region": String(server_config.get("region", "")).left(16),
		"mode": String(server_config.get("mode", "Campaign")).left(24), "port": enet_port,
		"players": player_count(), "max_players": max_players, "password": _password != ""}


func _server_name() -> String:
	var n := String(server_config.get("name", "")).strip_edges().left(48)
	return n if n != "" else "%s's fire" % String(players.get(1, {}).get("name", "Wanderer"))


func is_public() -> bool:
	return not server_config.is_empty()


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
	lobby_options = DEFAULT_LOBBY_OPTIONS.duplicate()
	session_info = {}   # a finished session's rules (PvP, respawns) must not leak into the next game
	runes = PackedInt32Array()
	_pending_hello.clear()
	_incoming.clear()
	_ping.clear()
	_offset_ready = false
	_clock_offset = 0.0
	_campaign_started = false
	enet_port = 0
	server_config = {}
	dedicated = false
	max_players = MAX_PLAYERS
	_password = ""
	_chat_budget.clear()


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
	_rpc_hello.rpc_id(1, _joining_name, PROTOCOL_VERSION, code, _join_password)
	_join_password = ""


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
	# Clients see relayed party IDs but have an ENet connection only to host 1.
	if _enet == null or (not is_server() and id != 1):
		return
	var p := _enet.get_peer(id)
	if p != null:
		p.throttle_configure(5000, 32, 0)


func _on_peer_disconnected(id: int) -> void:
	_pending_hello.erase(id)
	_ping.erase(id)
	_chat_budget.erase(id)
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

## `password` defaults so a protocol-4 client's 3-argument hello still gets
## the "different version" answer instead of an RPC error.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(requested_name: String, version: int, code: int, password := "") -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id) or not _pending_hello.has(id):
		return  # a second hello (or one after the timeout) is ignored
	_pending_hello.erase(id)
	var ip := _peer_ip(id)
	var now := _now()
	if float(_bans.get(ip, 0.0)) > now:
		_reject(id, "You were removed from this server. Try again later.")
		return
	if version != PROTOCOL_VERSION:
		_reject(id, "That party is running a different version of Burn.")
		return
	if code != RuneCode.encode(runes) and code != ADDRESS_JOIN:
		_reject(id, "No party with those runes was found on your network.")
		return
	if _password != "":
		var tries: Array = _bad_password.get(ip, [0, now])
		if now - float(tries[1]) > PASSWORD_LOCKOUT:
			tries = [0, now]
		if int(tries[0]) >= PASSWORD_TRIES:
			_reject(id, "Too many wrong passwords. Try again in a minute.")
			return
		if password.left(PASSWORD_MAX) != _password:
			_bad_password[ip] = [int(tries[0]) + 1, float(tries[1])]
			_reject(id, "Wrong password." if password != "" else "This server needs a password.")
			return
		_bad_password.erase(ip)
	if player_count() >= max_players:
		_reject(id, "That party is full.")
		return
	var who := _unique_name(_clean_name(requested_name))
	players[id] = {"name": who, "color": _free_color(), "ready": false}
	_broadcast_lobby()
	lobby_changed.emit()
	broadcast_system("%s joined." % who)
	player_joined.emit(id, who)
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
			_rpc_lobby.rpc_id(id, players, RuneCode.encode(runes), lobby_options)


@rpc("authority", "call_remote", "reliable")
func _rpc_lobby(lobby: Dictionary, code: int, options: Dictionary) -> void:
	var first := players.is_empty()
	players = lobby
	lobby_options = DEFAULT_LOBBY_OPTIONS.duplicate()
	for key: String in DEFAULT_LOBBY_OPTIONS:
		if options.get(key) is bool:
			lobby_options[key] = options[key]
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
	var s := _strip_controls(n.left(64)).replace("|", "/").replace("[", "(").replace("]", ")").strip_edges().left(20)
	return s if s != "" else "Wanderer"


## Chat text as the host relays it: one line, no control characters, no
## BBCode tags (displays escape `[` as well), at most CHAT_MAX characters.
static func clean_chat(t: String) -> String:
	var s := _strip_controls(t.left(CHAT_MAX * 4))
	var re := RegEx.create_from_string("\\[/?[A-Za-z_][A-Za-z0-9_]*(=[^\\]]*)?( [^\\]]*)?\\]")
	s = re.sub(s, "", true)
	return s.strip_edges().left(CHAT_MAX)


static func _strip_controls(t: String) -> String:
	var out := ""
	for i in t.length():
		var c := t.unicode_at(i)
		out += " " if c < 32 or c == 127 or (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E) else t[i]
	return out


func _peer_ip(id: int) -> String:
	if _enet == null:
		return ""
	var p := _enet.get_peer(id)
	return p.get_remote_address() if p != null else ""


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Host: true when `id` may send another chat message now (token bucket).
func _chat_allowed(id: int) -> bool:
	var now := _now()
	var b: Array = _chat_budget.get(id, [float(CHAT_BURST), now])
	var tokens := minf(float(CHAT_BURST), float(b[0]) + (now - float(b[1])) / CHAT_REFILL)
	if tokens < 1.0:
		_chat_budget[id] = [tokens, now]
		return false
	_chat_budget[id] = [tokens - 1.0, now]
	return true


## Host: call an authority RPC on every accepted player, and locally.
func _to_party(method: StringName, args: Array) -> void:
	for id: int in players:
		if id != 1:
			callv("rpc_id", [id, method] + args)
	callv(method, args)


## Host: call an authority RPC on one player (or locally for the host).
func _deliver(id: int, method: StringName, args: Array) -> void:
	if id == 1:
		callv(method, args)
	elif players.has(id):
		callv("rpc_id", [id, method] + args)


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
	var t := clean_chat(text)
	if t == "":
		return
	if not _chat_allowed(id):
		_deliver(id, &"_rpc_system", ["You are sending messages too fast. Wait a moment."])
		return
	_to_party(&"_rpc_chat", [players[id]["name"], t])


@rpc("any_peer", "call_remote", "reliable")
func _rpc_whisper_request(target_name: String, text: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and players.has(id):
		_route_whisper(id, target_name.left(40), text)


func _route_whisper(from_id: int, target_name: String, text: String) -> void:
	var t := clean_chat(text)
	if t == "":
		return
	if from_id != 1 and not _chat_allowed(from_id):
		_deliver(from_id, &"_rpc_system", ["You are sending messages too fast. Wait a moment."])
		return
	var to := find_player(target_name)
	if to < 0 or (dedicated and to == 1):
		_deliver(from_id, &"_rpc_system", ["Nobody called \"%s\" is here." % _clean_name(target_name)])
		return
	if to == from_id:
		_deliver(from_id, &"_rpc_system", ["You mutter to yourself."])
		return
	_deliver(to, &"_rpc_whisper", [player_name(from_id), t, false])
	_deliver(from_id, &"_rpc_whisper", [player_name(to), t, true])


@rpc("authority", "call_remote", "reliable")
func _rpc_whisper(other: String, text: String, outgoing: bool) -> void:
	var ev := get_node_or_null("/root/Events")
	if ev != null:
		ev.chat_message.emit(other, text, "whisper_out" if outgoing else "whisper")


@rpc("authority", "call_remote", "reliable")
func _rpc_system(text: String) -> void:
	_emit_system(text)


func _emit_system(text: String) -> void:
	var ev := get_node_or_null("/root/Events")
	if ev != null:
		ev.chat_message.emit("", text, "system")


@rpc("any_peer", "call_remote", "reliable")
func _rpc_death(cause: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and players.has(id) and _chat_allowed(id):
		_broadcast_death(id, cause)


func _broadcast_death(id: int, cause: String) -> void:
	var c := clean_chat(cause).left(60)
	broadcast_system("%s fell%s." % [player_name(id), (" (%s)" % c) if c != "" else ""])


@rpc("authority", "call_remote", "reliable")
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
