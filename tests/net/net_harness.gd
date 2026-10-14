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
	events = root.get_node("Events")
	events.chat_message.connect(func(from: String, text: String, _ch: String) -> void: chats.append([from, text]))
	if args.get("role") == "host":
		await _host()
	else:
		await _client()
	_finish()


func _finish() -> void:
	print("%s %s: %s" % ["RESULT", args.get("role"), "ok" if failures == 0 else "%d failure(s)" % failures])
	net.leave()
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
	if args.has("expect-host-close"):
		var closed: bool = await wait_until(func() -> bool: return failed_reason[0] != "", 15.0)
		check(closed and String(failed_reason[0]).contains("closed") and not net.is_online(),
				"host leaving reported: \"%s\", back to solo (server=%s)" % [failed_reason[0], net.is_server()])
		return

	net.send_chat("hello from " + me)
	var relayed: bool = await wait_until(func() -> bool: return not take_chat(func(_f: String, t: String) -> bool: return t == "hi " + me).is_empty(), 15.0)
	check(relayed, "chat relayed through the host")

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
		net.send_chat("session ok")

	await wait_seconds(3.0)
	var rtt: float = net.ping_ms()
	print("INFO: client ping to host = %.0f ms (sim latency %.0f ms, loss %.3f)" % [rtt, net.sim_latency_ms, net.sim_loss])
	if args.has("rtt"):
		var r := String(args["rtt"]).split("-")
		check(rtt >= float(r[0]) and rtt <= float(r[1]), "round trip %.0f ms within %s ms" % [rtt, args["rtt"]])
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
