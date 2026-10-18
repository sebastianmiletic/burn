extends SceneTree
## One process of the LAN party integration test (see run_net_test.sh).
##
##   godot --headless --path . -s res://tests/net/net_harness.gd -- --role=host --runes=R1-R2-R3-R4 --clients=1 --payload-mb=2
##   godot --headless --path . -s res://tests/net/net_harness.gd -- --role=client --runes=R1-R2-R3-R4 --name=Ash [--probe] [--sim-latency=150 --sim-loss=0.02 --rtt=250-400]
##   godot --headless --path . -s res://tests/net/net_harness.gd -- --role=client --runes=R9-R9-R9-R9 --expect-fail=No party
##
## Prints PASS:/FAIL: lines and exits 0 when every check passed.

var net: Node
var events: Node
var probe: Node
var args := {}
var failures := 0
var chats: Array = []  # [from, text]
var channels: Array = []  # [from, text, channel]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.trim_prefix("--").split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	probe = Node.new()
	probe.set_script(load("res://tests/net/net_probe.gd"))
	probe.name = "NetProbe"
	root.add_child(probe)
	_main.call_deferred()


func _main() -> void:
	await process_frame
	net = root.get_node("Net")
	# This is a transport-only harness. Do not launch GameWorld on the
	# synthetic session payload and quit while its generation task is alive.
	var game := root.get_node("Game")
	for signal_name in ["session_started", "join_failed"]:
		for connection: Dictionary in net.get_signal_connection_list(signal_name):
			var callback: Callable = connection["callable"]
			if callback.get_object() == game:
				net.disconnect(signal_name, callback)
	events = root.get_node("Events")
	events.chat_message.connect(func(from: String, text: String, ch: String) -> void:
		chats.append([from, text])
		channels.append([from, text, ch]))
	if args.get("role") == "host":
		await _host()
	elif args.get("role") == "public-host":
		await _public_host()
	elif args.get("role") == "browser-client":
		await _browser_client()
	else:
		await _client()
	_finish()


func _finish() -> void:
	net.leave()
	check(not net.lobby_options["shrine_respawn"], "leaving resets party rules to safe defaults")
	print("%s %s: %s" % ["RESULT", args.get("role"), "ok" if failures == 0 else "%d failure(s)" % failures])
	# Let a public host's unregister reach the master before the process exits.
	var deadline := Time.get_ticks_msec() + 4000
	while net.server_list != null and net.server_list.pending_requests() > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	await process_frame
	quit(0 if failures == 0 else 1)


func check(cond: bool, what: String) -> bool:
	print(("PASS: " if cond else "FAIL: ") + "[%s] %s" % [args.get("name", args.get("role")), what])
	if not cond:
		failures += 1
	return cond


func wait_until(cond: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func wait_seconds(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func take_chat(pred: Callable) -> Array:
	for i in chats.size():
		if pred.call(chats[i][0], chats[i][1]):
			return chats.pop_at(i)
	return []


static func digest(b: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(b)
	return h.finish().hex_encode()


# --- Host ----------------------------------------------------------------------------

func _host() -> void:
	var code := RuneCode.from_text(args.get("runes", ""))
	var expected := int(args.get("clients", "1"))
	var got: PackedInt32Array = net.host_party(args.get("name", "Host"), code)
	check(got == code, "hosting with runes %s on ENet port %d" % [RuneCode.to_text(got), net.enet_port])
	check(net.is_online() and net.is_server() and net.is_host(), "host is online and authoritative")
	if args.has("rules"):
		net.set_lobby_option("shrine_respawn", true)
	var mb := float(args.get("payload-mb", "2"))
	var blob := Crypto.new().generate_random_bytes(int(mb * 1024 * 1024))
	var info := {"seed": 42, "blob": blob, "sha": digest(blob), "note": "campaign"}
	if args.has("start-early"):
		net.start_campaign(info)  # clients join a game already in progress
	var joined: bool = await wait_until(func() -> bool: return net.players.size() == expected + 1, 25.0)
	check(joined, "%d client(s) joined the lobby (%s)" % [expected, str(net.players.values().map(func(p: Dictionary) -> String: return p["name"]))])
	if not joined:
		return
	if args.has("close-after-join"):
		await wait_seconds(1.0)
		return
	var names := {}
	for id: int in net.players:
		names[net.players[id]["name"]] = true
	check(names.size() == net.players.size(), "player names are unique")

	var hellos := 0
	var end := Time.get_ticks_msec() + 15000
	while hellos < expected and Time.get_ticks_msec() < end:
		var c := take_chat(func(_f: String, t: String) -> bool: return t.begins_with("hello from "))
		if not c.is_empty():
			hellos += 1
			net.send_chat("hi " + String(c[1]).trim_prefix("hello from "))
		await process_frame
	check(hellos == expected, "received hello chats from every client")
	if args.has("rules"):
		net.set_lobby_option("shrine_respawn", false)
		var confirmations := 0
		var rules_end := Time.get_ticks_msec() + 15000
		while confirmations < expected and Time.get_ticks_msec() < rules_end:
			if not take_chat(func(_f: String, t: String) -> bool: return t == "rules ok").is_empty():
				confirmations += 1
			await process_frame
		check(confirmations == expected, "all guests received the changed rule before campaign start")

	var t0 := Time.get_ticks_msec()
	if not args.has("start-early"):
		net.start_campaign(info)
	var session_ok := 0
	var byes := 0
	end = Time.get_ticks_msec() + 60000
	while byes < expected and Time.get_ticks_msec() < end:
		if not take_chat(func(_f: String, t: String) -> bool: return t == "session ok").is_empty():
			session_ok += 1
			if session_ok == expected:
				print("INFO: %.1f MB session delivered to all clients in %d ms" % [mb, Time.get_ticks_msec() - t0])
		var p := take_chat(func(_f: String, t: String) -> bool: return t == "probes sent")
		if not p.is_empty():
			var sender := _id_of(p[0])
			net.send_chat("probes for %s u=%d bad=%d next=%d" % [p[0], int(probe.unreliable.get(sender, 0)),
					int(probe.reliable_bad.get(sender, 0)), int(probe.reliable_next.get(sender, 0))])
			print("INFO: host ping to %s = %.0f ms" % [p[0], net.ping_ms(sender)])
		if not take_chat(func(_f: String, t: String) -> bool: return t == "bye").is_empty():
			byes += 1
		await process_frame
	check(session_ok == expected, "every client confirmed the %.1f MB session payload" % mb)
	check(byes == expected, "every client finished")


func _id_of(player_name: String) -> int:
	for id: int in net.players:
		if net.players[id]["name"] == player_name:
			return id
	return -1


# --- Client ----------------------------------------------------------------------------

func _client() -> void:
	var code := RuneCode.from_text(args.get("runes", ""))
	var my_name: String = args.get("name", "Client")
	var failed_reason := [""]
	net.join_failed.connect(func(r: String) -> void: failed_reason[0] = r)
	# Before joining we are solo: offline peer, authoritative, chat stays local.
	check(net.is_server() and not net.is_online() and net.my_id() == 1, "solo mode is server-authoritative and offline")
	net.send_chat("solo echo")
	check(not take_chat(func(_f: String, t: String) -> bool: return t == "solo echo").is_empty(), "solo chat echoes locally")
	var t0 := Time.get_ticks_msec()
	net.join_party(code, my_name)

	if args.has("expect-fail"):
		var failed: bool = await wait_until(func() -> bool: return failed_reason[0] != "", 12.0)
		check(failed and String(failed_reason[0]).contains(args["expect-fail"]),
				"join failed as expected after %d ms: \"%s\"" % [Time.get_ticks_msec() - t0, failed_reason[0]])
		return

	var joined: bool = await wait_until(func() -> bool: return net.players.has(net.my_id()) or failed_reason[0] != "", 20.0)
	if not check(joined and failed_reason[0] == "", "joined by runes in %d ms (%s)" % [Time.get_ticks_msec() - t0, failed_reason[0]]):
		return
	var me: String = net.players[net.my_id()]["name"]
	if args.has("expect-name"):
		check(me == args["expect-name"], "lobby gave unique name \"%s\"" % me)
	my_name = me
	args["name"] = me
	check(net.players.has(1) and not net.is_server(), "lobby mirrors the host (%d players)" % net.players.size())
	check(bool(net.lobby_options["shrine_respawn"]) == args.has("rules"), "initial party rule mirrors the host before play")
	if args.has("expect-host-close"):
		var closed: bool = await wait_until(func() -> bool: return failed_reason[0] != "", 15.0)
		check(closed and String(failed_reason[0]).contains("closed") and not net.is_online(),
				"host leaving reported: \"%s\", back to solo (server=%s)" % [failed_reason[0], net.is_server()])
		return

	net.send_chat("hello from " + me)
	var relayed: bool = await wait_until(func() -> bool: return not take_chat(func(_f: String, t: String) -> bool: return t == "hi " + me).is_empty(), 15.0)
	check(relayed, "chat relayed through the host")
	if args.has("rules"):
		var changed: bool = await wait_until(func() -> bool: return not net.lobby_options["shrine_respawn"], 10.0)
		check(changed, "guest receives a live party-rule change")
		net.set_lobby_option("shrine_respawn", true)
		check(not net.lobby_options["shrine_respawn"], "a guest cannot change the host's rule")
		net.send_chat("rules ok")

	var session := [{}]
	net.session_started.connect(func(info: Dictionary) -> void: session[0] = info)
	if not net.session_info.is_empty():
		session[0] = net.session_info
	var t1 := Time.get_ticks_msec()
	var got: bool = await wait_until(func() -> bool: return not (session[0] as Dictionary).is_empty(), 60.0)
	if check(got, "session_started received (%d ms)" % (Time.get_ticks_msec() - t1)):
		var info: Dictionary = session[0]
		var blob: PackedByteArray = info.get("blob", PackedByteArray())
		check(info.get("seed") == 42 and digest(blob) == info.get("sha"), "%d byte payload intact (sha256 matches)" % blob.size())
		check(info.get("options", {}).get("shrine_respawn") == net.lobby_options["shrine_respawn"], "campaign carries the displayed party rule")
		net.send_chat("session ok")

	await wait_seconds(3.0)
	if args.has("rtt"):
		var r := String(args["rtt"]).split("-")
		# The session's bulk transfer can inflate the first RTT samples. Net
		# smooths once per second, so three seconds is not always enough for
		# that history to decay on a busy machine. Keep the same limits, but
		# allow bounded settling; missing pongs must not pass as a zero RTT.
		print("INFO: post-transfer ping = %.0f ms; settling within %s ms" % [net.ping_ms(), args["rtt"]])
		await wait_until(func() -> bool:
			var sample: float = net.ping_ms()
			return sample > 0.0 and sample >= float(r[0]) and sample <= float(r[1]), 12.0)
		var settled: float = net.ping_ms()
		check(settled > 0.0 and settled >= float(r[0]) and settled <= float(r[1]),
				"round trip %.0f ms within %s ms" % [settled, args["rtt"]])
	var rtt: float = net.ping_ms()
	print("INFO: client ping to host = %.0f ms (sim latency %.0f ms, loss %.3f)" % [rtt, net.sim_latency_ms, net.sim_loss])
	check(absf(net.server_time() - Time.get_ticks_usec() / 1000000.0) < 600.0, "server clock estimate is sane")

	if args.has("probe"):
		const N := 200
		# Paced at 60 Hz like real game traffic (headless frames are uncapped,
		# and ENet's throttle deliberately sheds unreliable bursts).
		for i in N:
			probe.probe_unreliable.rpc_id(1, i)
			probe.probe_reliable.rpc_id(1, i)
			await wait_seconds(1.0 / 60.0)
		await wait_seconds(1.0 + net.sim_latency_ms / 500.0)
		net.send_chat("probes sent")
		var reply := [""]
		var ok: bool = await wait_until(func() -> bool:
			var c := take_chat(func(_f: String, t: String) -> bool: return t.begins_with("probes for " + me + " "))
			if not c.is_empty():
				reply[0] = c[1]
			return reply[0] != "", 15.0)
		if check(ok, "host reported probe counts"):
			var f := {}
			for part in String(reply[0]).split(" "):
				if part.contains("="):
					var kv := part.split("=")
					f[kv[0]] = int(kv[1])
			check(f["next"] == N and f["bad"] == 0, "all %d reliable packets arrived in order (next=%d, out-of-order=%d)" % [N, f["next"], f["bad"]])
			var floor_count := int(N * (1.0 - net.sim_loss * 4.0)) - 2
			check(f["u"] >= floor_count and f["u"] <= N, "unreliable packets: %d/%d arrived (loss %.1f%%)" % [f["u"], N, 100.0 * (N - f["u"]) / N])
	net.send_chat("bye")
	await wait_seconds(0.5 + net.sim_latency_ms / 500.0)


# --- Public server (master list) ---------------------------------------------------------
# Host: --role=public-host --master=URL --server-name=... --password=...
# Client: --role=browser-client --master=URL --server-name=... --password=...

func _net_const(n: String) -> Variant:
	return net.get_script().get_script_constant_map().get(n)


func _has_channel(channel: String, needle: String) -> bool:
	for c: Array in channels:
		if c[2] == channel and String(c[1]).contains(needle):
			return true
	return false


func _public_host() -> void:
	var cfg := {"name": args.get("server-name", "Test Fire"), "description": "integration test", "password": args.get("password", ""),
		"max_players": 4, "internet": true, "lan": true, "mode": "Campaign"}
	var code: PackedInt32Array = net.host_party("Host", PackedInt32Array(), cfg)
	check(not code.is_empty() and net.is_public(), "hosting a public server on port %d" % net.enet_port)
	var sl: Node = net.server_list
	var reg: bool = await wait_until(func() -> bool: return sl.registered_id != "", 25.0)
	if sl.registration_error != "":
		print("INFO: registration needed a retry: ", sl.registration_error)
	check(reg and sl.registered_id != "", "registered with the master (%s)" % sl.registration_error)
	net.start_campaign({"seed": 42, "note": "public"})
	var joined: bool = await wait_until(func() -> bool: return net.player_count() >= 2, 45.0)
	check(joined, "a browser client joined (%s)" % str(net.players.values().map(func(p: Dictionary) -> String: return p["name"])))
	var ok: bool = await wait_until(func() -> bool: return sl.verified == true, 15.0)
	check(ok, "master verified the UDP game port through heartbeat (verified=%s)" % str(sl.verified))
	if not joined:
		return
	var guest := ""
	for id: int in net.players:
		if id != 1:
			guest = net.players[id]["name"]
	var w: bool = await wait_until(func() -> bool: return _has_channel("whisper", "psst host"), 15.0)
	check(w, "received the guest's whisper on the whisper channel")
	net.send_whisper(guest, "psst guest")
	var spam_seen := [0]
	var bye: bool = await wait_until(func() -> bool:
		spam_seen[0] = channels.filter(func(c: Array) -> bool: return String(c[1]).begins_with("spam ")).size()
		return not take_chat(func(_f: String, t: String) -> bool: return t == "bye").is_empty(), 40.0)
	check(bye, "guest finished")
	check(spam_seen[0] >= 1 and spam_seen[0] <= int(_net_const("CHAT_BURST")), "chat flood limited: %d of 12 spam lines relayed" % spam_seen[0])
	check(not _has_channel("party", "[b]"), "BBCode tags stripped before relaying")
	await wait_seconds(1.0)


func _browser_client() -> void:
	var server_name: String = args.get("server-name", "Test Fire")
	var failed_reason := [""]
	net.join_failed.connect(func(r: String) -> void: failed_reason[0] = r)
	# The master's own list (not the LAN sighting) must carry the server.
	var lister: Node = load("res://network/server_list.gd").new()
	root.add_child(lister)
	var online := [[]]
	var got_list := [false]
	lister.listed.connect(func(servers: Array, err: String) -> void:
		got_list[0] = true
		online[0] = servers
		if err != "":
			print("INFO: list error ", err))
	var found: Dictionary = {}
	var end := Time.get_ticks_msec() + 30000
	while found.is_empty() and Time.get_ticks_msec() < end:
		got_list[0] = false
		lister.fetch()
		await wait_until(func() -> bool: return got_list[0], 8.0)
		for e: Dictionary in online[0]:
			if e["name"] == server_name:
				found = e
		if found.is_empty():
			await wait_seconds(1.0)
	if not check(not found.is_empty(), "master lists \"%s\"" % server_name):
		return
	check(found["password"] == true and found["protocol"] == int(_net_const("PROTOCOL_VERSION")) and found["max_players"] == 4 and found["ip"] == "127.0.0.1",
			"listing fields: locked, protocol %d, 4 slots, caller IP %s" % [found["protocol"], found["ip"]])

	# Loaded at runtime: the browser's menu backdrop needs the autoloads.
	var browser: Node = load("res://ui/server_browser.gd").new()
	root.add_child(browser)
	var listed: bool = await wait_until(func() -> bool:
		for e: Dictionary in browser.entries():
			if e["name"] == server_name and float(e.get("ping", -1.0)) >= 0.0:
				return true
		return false, 15.0)
	var entry: Dictionary = {}
	for e: Dictionary in browser.entries():
		if e["name"] == server_name:
			entry = e
	check(listed, "browser shows the server with a measured ping (%s ms, %s)" % [str(entry.get("ping")), entry.get("source")])
	if entry.is_empty():
		return
	browser.join_entry(entry, "not-the-password")
	var rejected: bool = await wait_until(func() -> bool: return failed_reason[0] != "", 15.0)
	check(rejected and String(failed_reason[0]).contains("Wrong password"), "wrong password rejected: \"%s\"" % failed_reason[0])
	await wait_seconds(0.5)
	failed_reason[0] = ""
	browser.set("_joining", false)
	browser.join_entry(entry, args.get("password", ""))
	var joined: bool = await wait_until(func() -> bool: return net.players.has(net.my_id()) or failed_reason[0] != "", 20.0)
	if not check(joined and failed_reason[0] == "", "joined from the browser list with the password (%s)" % failed_reason[0]):
		return
	browser.queue_free()
	var me: String = net.players[net.my_id()]["name"]
	var sys: bool = await wait_until(func() -> bool: return _has_channel("system", me + " joined"), 10.0)
	check(sys, "system line announces the join")
	net.send_whisper("host", "psst host")
	var echo: bool = await wait_until(func() -> bool: return _has_channel("whisper_out", "psst host"), 10.0)
	check(echo, "whisper echoed back to the sender")
	var reply: bool = await wait_until(func() -> bool: return _has_channel("whisper", "psst guest"), 10.0)
	check(reply, "whisper from the host arrives")
	net.send_whisper("nobody-here", "hello?")
	var missing: bool = await wait_until(func() -> bool: return _has_channel("system", "Nobody called"), 10.0)
	check(missing, "whisper to an unknown player reports an error")
	net.send_chat("[b]bold[/b] attempt")
	for i in 12:
		net.send_chat("spam %d" % i)
	var limited: bool = await wait_until(func() -> bool: return _has_channel("system", "too fast"), 10.0)
	check(limited, "flooding the chat gets a rate-limit notice")
	await wait_seconds(float(_net_const("CHAT_REFILL")) * 2.0 + 0.5)
	net.send_chat("bye")
	await wait_seconds(1.0)
