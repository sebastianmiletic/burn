class_name PvpArena
extends Node
## PvP servers. A server hosted from the browser in a PvP mode (session option
## "pvp" = "all" | "sword" | "bow" | "mage", listed as "PvP: <category>")
## turns the world around the Emberfall shrine into an arena: a ring of
## burning pillars, everyone spawns inside it with their role's kit (the
## category forces the role), players can hurt each other (only here),
## the fallen respawn after a few seconds, and rounds are scored:
## first to KILL_TARGET or the most kills when the clock runs out.
## Host authoritative: kills, scores, rounds and the leaderboard come from the host.
## PvP characters are never saved (Game skips saving while active()).

const CATEGORIES := {"all": "All", "sword": "Sword", "bow": "Bow", "mage": "Mage"}
const CATEGORY_ROLE := {"sword": "warrior", "bow": "archer", "mage": "mage"}
const RADIUS := 30.0
const PILLARS := 16
const ROUND_TIME := 300.0
const KILL_TARGET := 15
const WARMUP := 6.0
const INTERMISSION := 12.0
const RESPAWN := 4.0
const CREDIT_WINDOW := 15.0

## Host: victim peer -> [attacker peer, seconds]
static var last_hit := {}

var center := Vector3.ZERO
## Shared state (host -> everyone): {phase, time, round, scores: {peer: {name, kills, deaths}}, winner, feed}
var state := {"phase": "warmup", "time": WARMUP, "round": 1, "scores": {}, "winner": -1, "feed": ""}
var _broadcast_t := 0.0
var _respawn_t := -1.0
var _edge_warned := 0.0


static func category() -> String:
	var c: Variant = Net.option("pvp", "")
	return String(c) if c is String and CATEGORIES.has(String(c)) else ""


static func active() -> bool:
	return Net.is_online() and category() != ""


static func mode_label(cat: String) -> String:
	return "PvP: " + String(CATEGORIES.get(cat, "All")) if CATEGORIES.has(cat) else "Campaign"


## The role a player enters as: the category's, or their own choice in "all".
static func forced_role(chosen: String) -> String:
	if not active():
		return chosen
	return String(CATEGORY_ROLE.get(category(), chosen))


## Host: remember who last hurt whom (kill credit). From GameWorld.damage.
static func note_hit(target: Entity, source_id: int) -> void:
	if target is Player and source_id < 0 and active():
		last_hit[(target as Player).peer_id] = [-source_id, Time.get_ticks_msec() / 1000.0]


func gw() -> GameWorld:
	return get_parent().get_parent() as GameWorld


func _ready() -> void:
	var w := gw()
	var g := w.gen_for(0)
	var base := w.default_spawn(0) + Vector3(64, 0, 0)
	if g != null:
		base.x = clampf(base.x, 80.0, g.size - 80.0)
		base.y = g.surface_height(int(base.x), int(base.z)) + 1.0
	center = base
	_build_ring()
	Events.player_died.connect(_on_local_died)
	if Net.is_server():
		last_hit.clear()
		if w.spawner != null:
			w.spawner.process_mode = Node.PROCESS_MODE_DISABLED
		for peer in _all_peers():
			_ensure_score(peer)
	_enter_arena(true)
	Events.notify.emit("PvP arena (%s): stay inside the ring of fire. First to %d kills wins the round." % [String(CATEGORIES[category()]), KILL_TARGET], "quest")


func _all_peers() -> Array:
	var out: Array = []
	for id: int in Net.players:
		if not (Net.dedicated and id == 1):
			out.append(id)
	return out


func _ensure_score(peer: int) -> void:
	var scores: Dictionary = state["scores"]
	if not scores.has(peer):
		scores[peer] = {"name": Net.player_name(peer), "kills": 0, "deaths": 0}


## A spawn point on the ring's inner edge, spread around by peer.
func spawn_point(peer: int) -> Vector3:
	var a := TAU * fposmod(float(peer) * 0.618 + randf() * 0.25, 1.0)
	var p := center + Vector3(cos(a), 0, sin(a)) * (RADIUS * 0.7)
	var g := gw().gen_for(0)
	if g != null:
		p.y = g.surface_height(int(p.x), int(p.z)) + 1.05
	return p


## Put the local player in the arena with a fresh kit (session start and every new round).
func _enter_arena(new_kit: bool) -> void:
	var p := gw().local_player
	if p == null or (Net.dedicated and Net.is_server()):
		return
	if gw().local_dimension != 0:
		gw().travel(0)
	var at := spawn_point(Net.my_id())
	p.respawn_point = at
	p.respawn_dimension = 0
	if p.dead:
		p.request_respawn(true)
	p.global_position = at
	var vw := gw().world_for(0)
	if vw != null and p.body._overlaps(vw, at):
		var open := p.body.find_open_spot(vw, at, 3.0)
		if open != Vector3.INF:
			p.global_position = open
	p.body.velocity = Vector3.ZERO
	p.health = p.max_health
	if new_kit:
		_give_kit(p)
	Events.player_health_changed.emit(p.health, p.max_health)


func _give_kit(p: Player) -> void:
	p.inventory.from_dict({})
	var r: Dictionary = Roles.ROLES.get(p.role, Roles.ROLES[Roles.DEFAULT])
	for entry: Array in r["kit"]:
		var id := String(entry[0])
		if id in ["pickaxe_stone", "torch", "bread"]:
			continue
		p.inventory.add(id, int(entry[1]) * (2 if id in ["arrow", "potion_mana"] else 1))
	p.inventory.add("potion_health", 2)
	p.inventory.select(0)
	if p.arcana != null:
		p.arcana.on_rank_changed()


func _on_local_died(_cause: String) -> void:
	var p := gw().local_player
	if p == null:
		return
	p.downed = false
	_respawn_t = RESPAWN
	if Net.is_server():
		_on_death(multiplayer.get_unique_id())
	else:
		_rpc_died.rpc_id(1)


@rpc("any_peer", "reliable")
func _rpc_died() -> void:
	if multiplayer.is_server():
		_on_death(multiplayer.get_remote_sender_id())


func _on_death(victim: int) -> void:
	_ensure_score(victim)
	var scores: Dictionary = state["scores"]
	scores[victim]["deaths"] = int(scores[victim]["deaths"]) + 1
	var lh: Array = last_hit.get(victim, [])
	last_hit.erase(victim)
	var feed := "%s fell." % Net.player_name(victim)
	if not lh.is_empty() and int(lh[0]) != victim and Time.get_ticks_msec() / 1000.0 - float(lh[1]) <= CREDIT_WINDOW and state["phase"] == "fight":
		var killer := int(lh[0])
		_ensure_score(killer)
		scores[killer]["kills"] = int(scores[killer]["kills"]) + 1
		feed = "%s defeated %s." % [Net.player_name(killer), Net.player_name(victim)]
		if killer == multiplayer.get_unique_id():
			_rpc_credit()
		else:
			_rpc_credit.rpc_id(killer)
		if int(scores[killer]["kills"]) >= KILL_TARGET:
			_end_round()
	state["feed"] = feed
	Net.broadcast_system(feed)
	_send_state()


@rpc("authority", "reliable")
func _rpc_credit() -> void:
	Achievements.unlock("first_blood")


func _process(delta: float) -> void:
	if Net.is_server():
		_server_tick(delta)
	var p := gw().local_player
	if p == null or (Net.dedicated and Net.is_server()):
		return
	if _respawn_t >= 0.0:
		_respawn_t -= delta
		if _respawn_t < 0.0:
			_enter_arena(false)
			_refill(p)
	elif not p.dead:
		var off := Vector2(p.global_position.x - center.x, p.global_position.z - center.z)
		if off.length() > RADIUS + 3.0:
			var back := -Vector3(off.x, 0, off.y).normalized()
			p.body.velocity = back * 10.0 + Vector3(0, 4.0, 0)
			_edge_warned -= delta
			if _edge_warned <= 0.0:
				_edge_warned = 3.0
				Events.notify.emit("The arena's fire throws you back.", "warn")


func _refill(p: Player) -> void:
	if p.role == "archer" and p.inventory.count_of("arrow") < 30:
		p.inventory.add("arrow", 30 - p.inventory.count_of("arrow"))
	if p.inventory.count_of("potion_health") < 1:
		p.inventory.add("potion_health", 1)
	if p.arcana != null:
		p.arcana.on_rank_changed()


func _server_tick(delta: float) -> void:
	for peer in _all_peers():
		_ensure_score(peer)
	var scores: Dictionary = state["scores"]
	for peer: int in scores.keys():
		if not Net.players.has(peer):
			scores.erase(peer)
	state["time"] = float(state["time"]) - delta
	if float(state["time"]) <= 0.0:
		match String(state["phase"]):
			"warmup":
				state["phase"] = "fight"
				state["time"] = ROUND_TIME
				state["feed"] = "Round %d: fight!" % int(state["round"])
				Net.broadcast_system(String(state["feed"]))
			"fight":
				_end_round()
			"end":
				state["round"] = int(state["round"]) + 1
				state["phase"] = "warmup"
				state["time"] = WARMUP
				state["winner"] = -1
				for peer: int in scores:
					scores[peer]["kills"] = 0
					scores[peer]["deaths"] = 0
				_rpc_new_round()
				if Net.is_online():
					for peer in gw().replicator.ready_peers():
						_rpc_new_round.rpc_id(peer)
	_broadcast_t -= delta
	if _broadcast_t <= 0.0:
		_send_state()


func _end_round() -> void:
	if String(state["phase"]) == "end":
		return
	var best := -1
	var best_k := -1
	var scores: Dictionary = state["scores"]
	for peer: int in scores:
		var k := int(scores[peer]["kills"])
		if k > best_k or (k == best_k and int(scores[peer]["deaths"]) < int(scores.get(best, {}).get("deaths", 999))):
			best_k = k
			best = peer
	state["phase"] = "end"
	state["time"] = INTERMISSION
	state["winner"] = best if best_k > 0 else -1
	state["feed"] = ("%s wins round %d with %d kills!" % [Net.player_name(best), int(state["round"]), best_k]) if best_k > 0 else "Round over: no victor."
	Net.broadcast_system(String(state["feed"]))
	_send_state()


func _send_state() -> void:
	_broadcast_t = 1.0
	_rpc_state(state)
	if Net.is_online():
		for peer in gw().replicator.ready_peers():
			_rpc_state.rpc_id(peer, state)


@rpc("authority", "unreliable_ordered")
func _rpc_state(s: Dictionary) -> void:
	var was_end := String(state.get("phase", "")) == "end"
	state = s
	if not was_end and String(s.get("phase", "")) == "end" and int(s.get("winner", -1)) == Net.my_id() and not (Net.dedicated and Net.is_server()):
		var wins := PlayerProfile.add_stat("pvp_wins")
		Achievements.unlock("arena_victor")
		for id: String in Skins.SKINS:
			var u: Dictionary = Skins.SKINS[id].get("unlock", {})
			if u.has("pvp_wins") and wins >= int(u["pvp_wins"]) and PlayerProfile.unlock_skin(id):
				Events.notify.emit("New outfit unlocked: %s." % Skins.display_name(id), "rank")


@rpc("authority", "reliable")
func _rpc_new_round() -> void:
	_respawn_t = -1.0
	_enter_arena(true)


## Leaderboard rows, best first: [{peer, name, kills, deaths}].
func leaderboard() -> Array:
	var rows: Array = []
	var scores: Dictionary = state.get("scores", {})
	for peer: int in scores:
		var r: Dictionary = (scores[peer] as Dictionary).duplicate()
		r["peer"] = peer
		rows.append(r)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["kills"]) != int(b["kills"]):
			return int(a["kills"]) > int(b["kills"])
		return int(a["deaths"]) < int(b["deaths"]))
	return rows


func _build_ring() -> void:
	var root := Node3D.new()
	root.name = "ArenaRing"
	gw().add_child(root)
	var g := gw().gen_for(0)
	var stone := ItemMats.stone(Color(0.3, 0.28, 0.27))
	for i in PILLARS:
		var a := TAU * i / PILLARS
		var p := center + Vector3(cos(a), 0, sin(a)) * RADIUS
		if g != null:
			p.y = g.surface_height(int(p.x), int(p.z))
		ModelKit.part(root, ModelKit.cylinder(0.45, 0.6, 4.5, 8), stone, p + Vector3(0, 2.0, 0))
		ModelKit.part(root, ModelKit.cylinder(0.55, 0.45, 0.4, 8), stone, p + Vector3(0, 4.4, 0))
		var fire := ModelKit.embers(root, 24, Vector3(0.25, 0.1, 0.25), 0.9, 0.18, 1.6)
		fire.position = p + Vector3(0, 4.7, 0)
		fire.emitting = true
		if i % 4 == 0:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.55, 0.25)
			l.light_energy = 2.0
			l.omni_range = 14.0
			l.position = p + Vector3(0, 5.0, 0)
			root.add_child(l)
