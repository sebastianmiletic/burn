class_name LanDiscovery
extends Node
## Finds a party on the local network from its rune code, no IP typing.
##
## Host: listens on UDP DISCOVERY_PORTS[0] (or the next free one) and answers
##   "BURN?<code>"  with  "BURN!<code>|<enet_port>|<host_name>|<version>|<players>|<max>"
##   only when the code matches.
## Joiner: from an ephemeral port, sends the query every 0.4 s for up to 6 s to
##   255.255.255.255, every local interface's /24 broadcast address and
##   127.0.0.1 (so two copies on one machine find each other), on every
##   discovery port. The first matching reply wins.

signal found(address: String, port: int, host_name: String)
signal failed(reason: String)

const DISCOVERY_PORTS: Array[int] = [47210, 47221, 47222, 47223]  # ENet uses 47211..47220
const QUERY := "BURN?"
const REPLY := "BURN!"
const INTERVAL := 0.4
const TIMEOUT := 6.0

# Host side
var _responder: PacketPeerUDP
var _code := -1
var _enet_port := 0
var _host_name := ""
var _version := 0
var _player_count: Callable  ## () -> int
var _max_players := 8
var bound_port := 0

# Joiner side
var _searcher: PacketPeerUDP
var _search_code := -1
var _search_version := 0
var _elapsed := 0.0
var _since_send := 0.0
var _mismatch := ""


## Host: start answering queries. Returns OK or the bind error.
func start_responder(code: int, enet_port: int, host_name: String, version: int, player_count: Callable, max_players: int) -> Error:
	stop_responder()
	_code = code
	_enet_port = enet_port
	_host_name = host_name.replace("|", "/").left(32)
	_version = version
	_player_count = player_count
	_max_players = max_players
	for port in DISCOVERY_PORTS:
		var udp := PacketPeerUDP.new()
		if udp.bind(port, "*") == OK:
			_responder = udp
			bound_port = port
			return OK
	return ERR_CANT_CREATE


func stop_responder() -> void:
	if _responder != null:
		_responder.close()
	_responder = null
	bound_port = 0


## Joiner: start searching. Emits `found` or `failed`.
func search(code: int, version: int) -> void:
	stop_search()
	_searcher = PacketPeerUDP.new()
	if _searcher.bind(0) != OK:
		_searcher = null
		failed.emit("Could not open a network socket to look for the party.")
		return
	_searcher.set_broadcast_enabled(true)
	_search_code = code
	_search_version = version
	_elapsed = 0.0
	_since_send = INTERVAL
	_mismatch = ""


func stop_search() -> void:
	if _searcher != null:
		_searcher.close()
	_searcher = null


func is_searching() -> bool:
	return _searcher != null


func _process(delta: float) -> void:
	_poll_responder()
	_poll_searcher(delta)


func _poll_responder() -> void:
	if _responder == null:
		return
	while _responder.get_available_packet_count() > 0:
		var pkt := _responder.get_packet().get_string_from_utf8()
		var ip := _responder.get_packet_ip()
		var port := _responder.get_packet_port()
		if not pkt.begins_with(QUERY):
			continue
		if pkt.substr(QUERY.length()).to_int() != _code or not pkt.substr(QUERY.length()).is_valid_int():
			continue
		var count: int = _player_count.call() if _player_count.is_valid() else 1
		var reply := "%s%d|%d|%s|%d|%d|%d" % [REPLY, _code, _enet_port, _host_name, _version, count, _max_players]
		_responder.set_dest_address(ip, port)
		_responder.put_packet(reply.to_utf8_buffer())


func _poll_searcher(delta: float) -> void:
	if _searcher == null:
		return
	_elapsed += delta
	_since_send += delta
	if _since_send >= INTERVAL:
		_since_send = 0.0
		_send_queries()
	while _searcher != null and _searcher.get_available_packet_count() > 0:
		var pkt := _searcher.get_packet().get_string_from_utf8()
		var ip := _searcher.get_packet_ip()
		if not pkt.begins_with(REPLY):
			continue
		var f := pkt.substr(REPLY.length()).split("|")
		if f.size() < 6 or f[0].to_int() != _search_code:
			continue
		if f[3].to_int() != _search_version:
			_mismatch = "That party is running a different version of Burn."
			continue
		if f[4].to_int() >= f[5].to_int():
			_mismatch = "That party is full."
			continue
		stop_search()
		found.emit(ip, f[1].to_int(), f[2])
		return
	if _searcher != null and _elapsed >= TIMEOUT:
		stop_search()
		failed.emit(_mismatch if _mismatch != "" else "No party with those runes was found on your network.")


func _send_queries() -> void:
	var msg := ("%s%d" % [QUERY, _search_code]).to_utf8_buffer()
	for addr in broadcast_addresses():
		for port in DISCOVERY_PORTS:
			_searcher.set_dest_address(addr, port)
			_searcher.put_packet(msg)


## 255.255.255.255, each private IPv4 interface's /24 broadcast, and loopback.
static func broadcast_addresses() -> PackedStringArray:
	var out := PackedStringArray(["255.255.255.255", "127.0.0.1"])
	for iface: Dictionary in IP.get_local_interfaces():
		for addr: String in iface.get("addresses", []):
			var parts := addr.split(".")
			if parts.size() != 4 or addr.begins_with("127."):
				continue
			var b := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
			if not out.has(b):
				out.append(b)
	return out


func _exit_tree() -> void:
	stop_responder()
	stop_search()
