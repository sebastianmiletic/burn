extends TestCase
## Chat sanitising/formatting/commands and server-browser list logic.

const NetScript := preload("res://network/net.gd")


func test_clean_chat_strips_tags_controls_and_length() -> void:
	check_eq(NetScript.clean_chat("  hi [color=red]there[/color]\nfriend "), "hi there friend")
	check_eq(NetScript.clean_chat("[url=http://x]click[/url]"), "click")
	check_eq(NetScript.clean_chat("a" + String.chr(0x202E) + "b"), "a b")
	check_eq(NetScript.clean_chat("x".repeat(5000)).length(), NetScript.CHAT_MAX)
	check_eq(NetScript.clean_chat("[1] is fine"), "[1] is fine", "non-tag brackets survive (escaped on display)")


func test_clean_name() -> void:
	check_eq(NetScript._clean_name("  [b]Ash|x[/b] "), "(b)Ash/x(/b)")
	check_eq(NetScript._clean_name("y".repeat(500)).length(), 20)
	check_eq(NetScript._clean_name("\n\t"), "Wanderer")


func test_display_escapes_bbcode() -> void:
	var s := ChatBox.format_entry({"from": "[b]Evil", "text": "[img]x[/img]", "channel": "party"})
	check(not s.contains("[img]") and s.contains("[lb]img]"), s)
	check(not s.contains("[b]Evil"), s)
	var me := ChatBox.format_entry({"from": "Ash", "text": "/me waves", "channel": "party"})
	check(me.contains("* Ash waves"), me)
	var w := ChatBox.format_entry({"from": "Ash", "text": "psst", "channel": "whisper"})
	check(w.contains("Ash whispers:"), w)


func test_profanity_filter() -> void:
	check_eq(ChatHub.filter_profanity("well shit, Shit happens"), "well s***, S*** happens")
	check_eq(ChatHub.filter_profanity("shitake mushrooms"), "shitake mushrooms", "whole words only")


func test_split_target() -> void:
	check_eq(ChatHub.split_target("Twin (2) hello there", ["Twin", "Twin (2)"]), ["Twin (2)", "hello there"])
	check_eq(ChatHub.split_target("ash hi", ["Ash"]), ["Ash", "hi"])
	check_eq(ChatHub.split_target("Bob yo", ["Ash"]), ["Bob", "yo"])
	check_eq(ChatHub.split_target("Bob", []), ["Bob", ""])


func test_solo_commands_and_history() -> void:
	var hub := ChatHub.instance()
	hub.clear()
	hub.submit("/help")
	check(hub.history.size() > 5, "help lists commands")
	hub.submit("/clear")
	check_eq(hub.history.size(), 0)
	hub.submit("/nonsense")
	check(String(hub.history[-1]["text"]).contains("Unknown command"))
	hub.submit("/w Bob hi")
	check(String(hub.history[-1]["text"]).contains("online"), "whispers explain they need an online game")
	hub.submit("/kick Bob")
	check(String(hub.history[-1]["text"]).contains("Only the host"))
	hub.submit("hello world")
	check_eq(String(hub.history[-1]["text"]), "hello world", "solo chat echoes locally")
	hub.clear()


func test_browser_filter_and_sort() -> void:
	var p := Net.PROTOCOL_VERSION
	var list := [
		{"name": "Alpha", "players": 8, "max_players": 8, "protocol": p, "password": false, "ping": 40.0, "mode": "Campaign"},
		{"name": "beta", "players": 2, "max_players": 8, "protocol": p, "password": true, "ping": -2.0, "mode": "Campaign"},
		{"name": "Gamma", "players": 1, "max_players": 4, "protocol": p - 1, "password": false, "ping": 20.0, "mode": "Hardcore"},
	]
	var names := func(a: Array) -> Array: return a.map(func(e: Dictionary) -> String: return e["name"])
	check_eq(names.call(ServerBrowser.visible_entries(list, "", false, false, false, "players", true)), ["Alpha", "beta", "Gamma"])
	check_eq(names.call(ServerBrowser.visible_entries(list, "", true, true, true, "players", true)), [])
	check_eq(names.call(ServerBrowser.visible_entries(list, "", true, false, false, "name", false)), ["beta", "Gamma"])
	check_eq(names.call(ServerBrowser.visible_entries(list, "", false, false, false, "ping", false)), ["Gamma", "Alpha", "beta"], "failed pings sort last")
	check_eq(names.call(ServerBrowser.visible_entries(list, "hard", false, false, false, "name", false)), ["Gamma"])


func test_master_entry_sanitizing() -> void:
	var e := ServerList.sanitize_entry({"name": "x".repeat(300), "players": 999, "max_players": "8", "password": "yes", "port": 47211.0, "ip": "1.2.3.4"})
	check_eq(String(e["name"]).length(), 48)
	check_eq(e["players"], 64)
	check_eq(e["max_players"], 8)
	check_eq(e["password"], false)
	check_eq(e["port"], 47211)


func test_lan_list_reply() -> void:
	var e := LanDiscovery.parse_list_reply("BURNLIST!47212|Ash|5|2|8|1|Campaign|dig|ging", "10.0.0.2")
	check_eq(e.get("port"), 47212)
	check_eq(e.get("password"), true)
	check_eq(e.get("description"), "dig|ging")
	check(LanDiscovery.parse_list_reply("BURN!1|2", "x").is_empty())
