class_name ServerList
extends Node
## Client of the master server (server/burn_master.py): fetches the public
## server list for the browser, and keeps a hosted public server registered
## (register, heartbeat every ~15 s, unregister on leave).
##
## Every request has a timeout, so an unreachable master shows a message
## instead of hanging. The master records the host's IP itself.

## Fetched list: servers (Array of Dictionary) or a human-readable error.
signal listed(servers: Array, error: String)
## Hosting: "registering", "registered", "failed"; detail = message / address.
signal registration_changed(state: String, detail: String)

## Used when Settings online/master_server_url is empty. Change this to the
## deployed master's URL (see server/README.md) before shipping a build.
const DEFAULT_MASTER_URL := "http://127.0.0.1:47290"
const TIMEOUT := 8.0
const RETRY := 20.0

var registered_id := ""
var verified: Variant = null   ## master's reachability probe: null pending, true/false
var registration_error := ""
var _token := ""
var _info := Callable()        ## () -> Dictionary of listing fields (players, name, ...)
var _beat := 0.0
var _beat_every := 15.0
var _hosting := false
var _busy := false
var _failures := 0
## HTTPRequest -> [deadline msec, callback]. Wall-clock timeouts: HTTPRequest's
## own timer counts frame deltas, and the first frame after a long load can
## expire it at once.
var _pending := {}


static func master_url() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var s: Node = tree.root.get_node_or_null("Settings") if tree != null else null
	var url := String(s.call("get_value", "online", "master_server_url")) if s != null else ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--master="):
			url = a.trim_prefix("--master=")
	url = url.strip_edges().trim_suffix("/")
	return url if url != "" else DEFAULT_MASTER_URL


## Fetch the list (emits `listed`).
func fetch() -> void:
	_request(HTTPClient.METHOD_GET, "/v1/servers", null, func(code: int, data: Variant, err: String) -> void:
		if err != "":
			listed.emit([], err)
		elif code != 200 or not data is Dictionary or not (data as Dictionary).get("servers") is Array:
			listed.emit([], "The server list at %s answered with an error (%d)." % [master_url(), code])
		else:
			var out: Array = []
			for s: Variant in data["servers"]:
				if s is Dictionary:
					out.append(sanitize_entry(s))
			listed.emit(out, ""))


## A server list entry with known types and bounded strings (the master and
## the network are not trusted).
static func sanitize_entry(s: Dictionary) -> Dictionary:
	var ip := String(s.get("ip", "")).left(64)
	return {
		"name": _short(s.get("name"), 48), "description": _short(s.get("description"), 160),
		"version": _short(s.get("version"), 24), "protocol": int(s.get("protocol", 0)) if s.get("protocol") is float or s.get("protocol") is int else 0,
		"region": _short(s.get("region"), 16), "mode": _short(s.get("mode"), 24),
		"players": clampi(int(s.get("players", 0)) if s.get("players") is float or s.get("players") is int else 0, 0, 64),
		"max_players": clampi(int(s.get("max_players", 8)) if s.get("max_players") is float or s.get("max_players") is int else 8, 1, 64),
		"password": s.get("password") is bool and s.get("password"), "ip": ip,
		"port": clampi(int(s.get("port", 0)) if s.get("port") is float or s.get("port") is int else 0, 0, 65535),
		"verified": s.get("verified") if s.get("verified") is bool else null, "source": "online",
	}


static func _short(v: Variant, n: int) -> String:
	return String(v).replace("\n", " ").strip_edges().left(n) if v is String else ""


# --- Hosting -----------------------------------------------------------------------------

## Register a public server; `info` returns the current listing fields.
func start_hosting(info: Callable) -> void:
	stop_hosting()
	_info = info
	_hosting = true
	_register()


func stop_hosting() -> void:
	if registered_id != "" and _token != "":
		var id := registered_id
		var token := _token
		_request(HTTPClient.METHOD_DELETE, "/v1/servers/" + id, {"token": token}, func(_c: int, _d: Variant, _e: String) -> void: pass)
	_hosting = false
	registered_id = ""
	_token = ""
	verified = null
	registration_error = ""
	_failures = 0


func is_hosting() -> bool:
	return _hosting


func _register() -> void:
	if not _hosting or _busy:
		return
	_busy = true
	registration_changed.emit("registering", master_url())
	_request(HTTPClient.METHOD_POST, "/v1/servers", _info.call(), func(code: int, data: Variant, err: String) -> void:
		_busy = false
		if not _hosting:
			return
		if err == "" and code == 201 and data is Dictionary:
			registered_id = String(data.get("id", ""))
			_token = String(data.get("token", ""))
			verified = data.get("verified")
			_beat_every = clampf(float(data.get("heartbeat_seconds", 15)), 5.0, 60.0)
			_beat = _beat_every
			registration_error = ""
			_failures = 0
			registration_changed.emit("registered", String(data.get("address", "")))
		else:
			registration_error = err if err != "" else "The server list refused this server: %s" % \
					(String(data.get("error", code)) if data is Dictionary else str(code))
			# Retry soon after a first failure (e.g. a busy first frame), then back off.
			_failures += 1
			_beat = 4.0 if _failures == 1 else RETRY
			registration_changed.emit("failed", registration_error))


func _process(delta: float) -> void:
	_check_timeouts()
	if not _hosting or _busy:
		return
	_beat -= delta
	if _beat > 0.0:
		return
	if registered_id == "":
		_register()
		return
	_beat = _beat_every
	var body: Dictionary = _info.call()
	body.erase("port")
	body["token"] = _token
	_busy = true
	_request(HTTPClient.METHOD_POST, "/v1/servers/%s/heartbeat" % registered_id, body, func(code: int, data: Variant, _err: String) -> void:
		_busy = false
		if not _hosting:
			return
		if code == 404 or code == 403:
			registered_id = ""   # expired (e.g. the master restarted): register again
			_beat = 0.0
		elif code == 200 and data is Dictionary:
			if data.get("verified") != verified:
				verified = data.get("verified")
				registration_changed.emit("registered", String(data.get("address", ""))))


# --- HTTP -------------------------------------------------------------------------------

## cb(code: int, data: Variant (parsed JSON or null), error: String ("" when a reply arrived)).
func _request(method: int, path: String, body: Variant, cb: Callable) -> void:
	var url := master_url()
	if not (url.begins_with("http://") or url.begins_with("https://")):
		cb.call(0, null, "The master server address \"%s\" is not an http(s) URL." % url)
		return
	var http := HTTPRequest.new()
	http.max_redirects = 2
	http.body_size_limit = 512 * 1024
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, raw: PackedByteArray) -> void:
		if not _pending.has(http):
			return
		_pending.erase(http)
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			var why := "timed out" if result == HTTPRequest.RESULT_TIMEOUT else "unreachable"
			cb.call(0, null, "The server list (%s) is %s. Check your connection or the master server address." % [url, why])
			return
		cb.call(code, JSON.parse_string(raw.get_string_from_utf8()) if not raw.is_empty() else null, ""))
	var headers := PackedStringArray(["Content-Type: application/json", "User-Agent: Burn"])
	var err := http.request(url + path, headers, method, JSON.stringify(body) if body != null else "")
	if err != OK:
		http.queue_free()
		cb.call(0, null, "Could not contact the server list at %s." % url)
		return
	_pending[http] = [Time.get_ticks_msec() + int(TIMEOUT * 1000.0), cb, url]


func _check_timeouts() -> void:
	var now := Time.get_ticks_msec()
	for http: HTTPRequest in _pending.keys():
		var p: Array = _pending[http]
		if now > int(p[0]):
			_pending.erase(http)
			http.cancel_request()
			http.queue_free()
			(p[1] as Callable).call(0, null, "The server list (%s) did not answer in time. Check your connection or the master server address." % p[2])


# --- Ping ---------------------------------------------------------------------------------

## Measures the round trip to a game host with a bare ENet handshake (the
## host sees a connection that closes again before any hello). Poll each
## frame; `ms` is -1 until done, then the time or -2 on failure.
class Ping:
	extends RefCounted
	var ms := -1.0
	var _peer: ENetMultiplayerPeer
	var _start := 0
	var _timeout := 3000

	func _init(address: String, port: int, timeout_ms := 3000) -> void:
		_timeout = timeout_ms
		_peer = ENetMultiplayerPeer.new()
		if address == "" or port <= 0 or _peer.create_client(address, port, 3) != OK:
			ms = -2.0
			_peer = null
			return
		_start = Time.get_ticks_usec()

	## Returns true once finished.
	func poll() -> bool:
		if _peer == null:
			return true
		_peer.poll()
		var status := _peer.get_connection_status()
		if status == MultiplayerPeer.CONNECTION_CONNECTED:
			ms = (Time.get_ticks_usec() - _start) / 1000.0
		elif status == MultiplayerPeer.CONNECTION_DISCONNECTED or (Time.get_ticks_usec() - _start) / 1000 > _timeout:
			ms = -2.0
		else:
			return false
		_peer.close()
		_peer = null
		return true

	func cancel() -> void:
		if _peer != null:
			_peer.close()
			_peer = null
