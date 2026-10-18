class_name ChatHub
extends Node
## The chat's memory and brain, shared by every ChatBox (lobby and HUD), so
## history survives screen changes. Collects messages from Events.chat_message
## (party chat, whispers, system lines from Net) and turns game events into
## system lines; runs slash commands typed into a ChatBox.
## Lives under the root as "ChatHub" (created on first use, like MenuBackdrop).

signal added(entry: Dictionary)
signal cleared

const MAX_HISTORY := 120
## Words the optional filter masks (whole words, case-insensitive; simple by design).
const PROFANITY := ["fuck", "fucking", "fucker", "shit", "bitch", "cunt", "asshole", "bastard", "dick",
	"pussy", "slut", "whore", "nigger", "nigga", "faggot", "fag", "retard", "motherfucker", "cock", "wanker"]
const COMMANDS := [
	["/help", "this list"], ["/me <action>", "describe what you do"],
	["/w <player> <text>", "whisper (also /msg, /tell)"], ["/r <text>", "reply to the last whisper"],
	["/players", "who is here (also /list)"], ["/ping", "your round trip to the host"],
	["/seed", "the world seed"], ["/time", "time of day"], ["/coords", "where you stand"],
	["/clear", "empty the chat"], ["/kick <player> [reason]", "host only: remove a player"],
]

## {from, text, channel, time (msec)}
var history: Array[Dictionary] = []
var last_whisper_from := ""


static func instance() -> ChatHub:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var hub := tree.root.get_node_or_null("ChatHub") as ChatHub
	if hub == null:
		hub = ChatHub.new()
		hub.name = "ChatHub"
		tree.root.add_child(hub)
	return hub


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiContext.on("chat_message", _on_chat)
	UiContext.on("boss_defeated", func(_k: String, display_name: String) -> void:
		system("%s has been defeated." % display_name))
	UiContext.on("quest_completed", func(id: String) -> void:
		var q: Dictionary = QuestDB.any(id)
		system("Quest completed: %s." % String(q.get("title", id))))
	UiContext.on("rank_up", func(rank: int, title: String) -> void:
		system("You reached rank %d: %s." % [rank, title]))
	UiContext.on("player_died", _on_died)
	UiContext.on("campaign_won", func() -> void: system("The campaign is won."))
	var net := UiContext.net()
	if net != null and net.has_signal("peer_left"):
		net.connect("peer_left", func(_id: int, who: String) -> void: system("%s left." % who))


func _on_chat(from_name: String, text: String, channel: String) -> void:
	if channel == "whisper":
		last_whisper_from = from_name
	add(from_name, text, channel)


func _on_died(cause: String) -> void:
	if bool(UiContext.call_on(UiContext.net(), "is_online", [], false)):
		UiContext.call_on(UiContext.net(), "announce_death", [cause])
	else:
		system("You fell%s." % ((" (%s)" % cause) if cause != "" else ""))


func add(from_name: String, text: String, channel: String) -> void:
	if channel == "system" and not bool(UiContext.setting("chat", "show_system", true)):
		return
	var e := {"from": from_name, "text": text, "channel": channel, "time": Time.get_ticks_msec()}
	history.append(e)
	while history.size() > MAX_HISTORY:
		history.pop_front()
	added.emit(e)


func system(text: String) -> void:
	add("", text, "system")


## Feedback only this player sees (command results); shown even when system lines are hidden.
func info(text: String) -> void:
	var e := {"from": "", "text": text, "channel": "info", "time": Time.get_ticks_msec()}
	history.append(e)
	added.emit(e)


func clear() -> void:
	history.clear()
	cleared.emit()


# --- Sending and commands ---------------------------------------------------------------

func submit(raw: String) -> void:
	var text := raw.strip_edges()
	if text == "":
		return
	if not text.begins_with("/") or text.begins_with("//"):
		_say(text.trim_prefix("/") if text.begins_with("//") else text)
		return
	var space := text.find(" ")
	var cmd := (text if space < 0 else text.substr(0, space)).to_lower()
	var rest := "" if space < 0 else text.substr(space + 1).strip_edges()
	var net := UiContext.net()
	var online := bool(UiContext.call_on(net, "is_online", [], false))
	match cmd:
		"/help", "/?", "/commands":
			info("Commands:")
			for c: Array in COMMANDS:
				info("  %s  —  %s" % [c[0], c[1]])
		"/me":
			if rest != "":
				_say("/me " + rest)
		"/w", "/msg", "/tell", "/whisper":
			var parts := split_target(rest, _names())
			if parts[0] == "" or parts[1] == "":
				info("Usage: %s <player> <message>" % cmd)
			else:
				UiContext.call_on(net, "send_whisper", [parts[0], parts[1]])
		"/r", "/reply":
			if last_whisper_from == "":
				info("Nobody has whispered to you yet.")
			elif rest != "":
				UiContext.call_on(net, "send_whisper", [last_whisper_from, rest])
		"/clear", "/cls":
			clear()
		"/players", "/list", "/who", "/online":
			_list_players(net, online)
		"/ping":
			if not online:
				info("You are playing solo: no ping.")
			elif bool(UiContext.call_on(net, "is_server", [], true)):
				info("You are the host. Worst player ping: %d ms." % roundi(float(UiContext.call_on(net, "ping_ms", [], 0.0))))
			else:
				info("Ping to the host: %d ms." % roundi(float(UiContext.call_on(net, "ping_ms", [], 0.0))))
		"/seed":
			var game := UiContext.autoload("Game")
			var session: Variant = game.get("session") if game != null else null
			if session is Dictionary and (session as Dictionary).has("seed"):
				info("World seed: %d" % int(session["seed"]))
			else:
				info("No world is loaded.")
		"/time":
			if UiContext.world() == null:
				info("No world is loaded.")
			else:
				info("Day %d, %s." % [int(UiContext.world_call("day", [], 1)), UiTheme.clock(float(UiContext.world_call("time_of_day", [], 12.0)))])
		"/coords", "/pos", "/where":
			var p := UiContext.player() as Node3D
			if p == null:
				info("You are not in the world.")
			else:
				var v := p.global_position
				info("You stand at x %d, y %d, z %d." % [roundi(v.x), roundi(v.y), roundi(v.z)])
		"/kick":
			_kick(net, online, rest)
		_:
			info("Unknown command %s. Type /help." % cmd)


func _say(text: String) -> void:
	var net := UiContext.net()
	if net != null and net.has_method("send_chat"):
		net.call("send_chat", text)
	else:
		add(str(UiContext.setting("gameplay", "player_name", "You")), text, "local")


func _names() -> Array:
	var out := []
	var players: Variant = UiContext.net().get("players") if UiContext.net() != null else null
	if players is Dictionary:
		for id: int in players:
			out.append(String(players[id].get("name", "")))
	return out


## "Twin (2) hello there" -> ["Twin (2)", "hello there"]: the longest known
## player name the text starts with, else the first word.
static func split_target(rest: String, names: Array) -> Array:
	var best := ""
	for n: String in names:
		if n.length() > best.length() and rest.to_lower().begins_with(n.to_lower() + " "):
			best = n
	if best == "":
		var space := rest.find(" ")
		if space < 0:
			return [rest, ""]
		return [rest.substr(0, space), rest.substr(space + 1).strip_edges()]
	return [best, rest.substr(best.length() + 1).strip_edges()]


func _list_players(net: Node, online: bool) -> void:
	if not online:
		info("Solo: just you, %s." % str(UiContext.setting("gameplay", "player_name", "Wanderer")))
		return
	var players: Dictionary = net.get("players")
	var host := bool(net.call("is_server"))
	var me := int(net.call("my_id"))
	var lines := PackedStringArray()
	var ids := players.keys()
	ids.sort()
	for id: int in ids:
		var p: Dictionary = players[id]
		if p.get("server", false):
			continue
		var tags := PackedStringArray()
		if id == 1:
			tags.append("host")
		if id == me:
			tags.append("you")
		elif host:
			tags.append("%d ms" % roundi(float(net.call("ping_ms", id))))
		lines.append("%s%s" % [p.get("name", "?"), (" (%s)" % ", ".join(tags)) if not tags.is_empty() else ""])
	info("%d here: %s" % [lines.size(), ", ".join(lines)])


func _kick(net: Node, online: bool, rest: String) -> void:
	if not online or not bool(net.call("is_server")):
		info("Only the host can kick players.")
		return
	var parts := split_target(rest, _names())
	var id := int(net.call("find_player", parts[0]))
	if id < 0:
		info("Nobody called \"%s\" is here." % parts[0])
	elif id == 1:
		info("You cannot kick yourself.")
	else:
		var who := String(net.call("player_name", id))
		var reason: String = parts[1] if parts[1] != "" else "The host removed you from the server."
		net.call("kick", id, reason, 300.0)
		net.call("broadcast_system", "%s was removed by the host." % who)


# --- Display helpers ----------------------------------------------------------------------

## Masks listed words with asterisks (whole words only, keeps punctuation).
static func filter_profanity(text: String) -> String:
	var re := RegEx.create_from_string("[\\p{L}']+")
	var out := text
	for m in re.search_all(text):
		var w := m.get_string()
		if PROFANITY.has(w.to_lower()):
			out = out.substr(0, m.get_start()) + w[0] + "*".repeat(w.length() - 1) + out.substr(m.get_end())
	return out


static func escape(s: String) -> String:
	return s.replace("[", "[lb]")
