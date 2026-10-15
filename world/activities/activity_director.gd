class_name ActivityDirector
extends Node
## Things to do besides the campaign. Lives at /root/GameWorld/Activities on
## every peer (RPC paths match) and runs four activities:
##
##   TreasureHunt    (per player) maps from the merchant, chests and bounties hold
##                   a riddle: reach the landmark, search warmer/colder for the X,
##                   dig the buried chest out with a pickaxe, open it.
##   Bounties        (party) the bounty board in each village posts elite monster
##                   contracts and legendary hunts whose quarry is found by
##                   following fresh tracks. Paid on the kill.
##   WorldEvents     (party) meteor showers at night: race to the crater, dig
##                   through star-ore to the starmetal core before it is claimed;
##                   raids on the village you are in at dusk: defend it in waves.
##   ProvingGrounds  (party) a ring of standing stones near Emberfall: sound the war
##                   horn for escalating waves, milestone gear, per-save honours.
##
## Authority: the server decides spawns, voxel edits, rewards and shared state
## (`shared`, synced to every client); per-player progress lives in
## QuestLog.activity (saved with the character). Clients ask through
## `request()`. World-level state is saved through `save_state()`.

const ENTITY_SCRIPTS := {
	"act_cache": "res://world/activities/buried_cache.gd",
	"act_board": "res://world/activities/bounty_board.gd",
	"act_meteor": "res://world/activities/meteorite.gd",
	"act_elite": "res://world/activities/elite_mark.gd",
	"act_tracks": "res://world/activities/track_trail.gd",
	"act_arena": "res://world/activities/arena_ring.gd",
}

signal state_changed
signal banner(title: String, subtitle: String, color: Color)

var treasure: TreasureHunt
var bounties: Bounties
var events: WorldEvents
var ring: ProvingGrounds
var weather_craft: WeatherCraft
var hud: Node

## Server-authoritative state every client mirrors (contracts, the current
## event, the Proving Ring, honours).
var shared := {}
## Server-only persistent bookkeeping (cooldowns, milestone records).
var world := {}

var _tick := 0.0
var _local_tick := 0.0
var _dirty := false
var _fixtures := {}       # key -> net_id (boards, the ring)
var _resend := 0.0


static func of(gw: Node) -> ActivityDirector:
	return gw.get_node_or_null(^"Activities") as ActivityDirector if gw != null else null


## EntityFactory hook: "act_*" kinds.
static func create_entity(kind: String) -> Entity:
	var path: String = ENTITY_SCRIPTS.get(kind, "")
	if path == "":
		return null
	return (load(path) as Script).new() as Entity


func gw() -> GameWorld:
	return get_parent() as GameWorld


func _ready() -> void:
	name = "Activities"
	treasure = TreasureHunt.new(self)
	bounties = Bounties.new(self)
	events = WorldEvents.new(self)
	ring = ProvingGrounds.new(self)
	weather_craft = WeatherCraft.new(self)
	var w := gw()
	if w != null:
		if Net.is_server():
			var save: Dictionary = w.session.get("save", {})
			load_state(save.get("activities", {}))
		w.quests.marker_providers.append(markers)
	var hud_script: Script = load("res://ui/activity_hud.gd")
	hud = hud_script.new()
	hud.set("director", self)
	add_child(hud)
	if Net.is_online() and not Net.is_server():
		_hello.call_deferred()


func _process(delta: float) -> void:
	var w := gw()
	if w == null or w.local_player == null:
		return
	if Net.is_server():
		_tick -= delta
		if _tick <= 0.0:
			_tick = 0.5
			_server_fixtures()
			bounties.server_tick(0.5)
			events.server_tick(0.5)
			ring.server_tick(0.5)
			weather_craft.server_tick(0.5)
		_resend -= delta
		if _dirty or (_resend <= 0.0 and Net.is_online()):
			_dirty = false
			_resend = 5.0
			_broadcast(&"_state", [shared])
	_local_tick -= delta
	if _local_tick <= 0.0:
		_local_tick = 0.25
		treasure.local_tick(0.25)
		weather_craft.local_tick()
		_tips()


# --- Shared state ---------------------------------------------------------------

func set_shared(key: String, value: Variant) -> void:
	shared[key] = value
	_dirty = true
	state_changed.emit()


func mark_dirty() -> void:
	_dirty = true
	state_changed.emit()


@rpc("authority", "reliable")
func _state(s: Dictionary) -> void:
	if Net.is_server():
		return
	shared = s
	state_changed.emit()


@rpc("any_peer", "reliable")
func _hello_server() -> void:
	if multiplayer.is_server():
		_state.rpc_id(multiplayer.get_remote_sender_id(), shared)


func _hello() -> void:
	if is_inside_tree() and Net.is_online() and not Net.is_server():
		_hello_server.rpc_id(1)


## Runs `method` here and on every loaded peer.
func _broadcast(method: StringName, args: Array, local := false) -> void:
	if local:
		callv(method, args)
	if not Net.is_online():
		return
	var w := gw()
	if w == null or w.replicator == null:
		return
	for peer: int in w.replicator.call("_targets"):
		callv("rpc_id", [peer, method] + args)


# --- Requests (client -> server) -------------------------------------------------------

## Ask the server to do something on this player's behalf.
func request(action: String, args := {}) -> void:
	if Net.is_server():
		_handle(multiplayer.get_unique_id(), action, args)
	else:
		_request.rpc_id(1, action, args)


@rpc("any_peer", "reliable")
func _request(action: String, args: Dictionary) -> void:
	if multiplayer.is_server():
		_handle(multiplayer.get_remote_sender_id(), action, args)


func player_of(peer: int) -> Player:
	var w := gw()
	return w.entity(Replicator.player_net_id(peer)) as Player if w != null else null


func _handle(peer: int, action: String, args: Dictionary) -> void:
	var p := player_of(peer)
	if p == null or p.dead or action.length() > 32:
		return
	match action:
		"cache":
			treasure.server_spawn_cache(p, args)
		"contract_accept":
			bounties.server_accept(p, int(args.get("id", -1)))
		"contract_abandon":
			bounties.server_abandon(p, int(args.get("id", -1)))
		"arena_start":
			ring.server_start(p)
		"charm":
			weather_craft.server_use(p, String(args.get("kind", "")))


# --- Server -> clients --------------------------------------------------------------------

## A toast for one player.
func tell(peer: int, text: String, kind := "info") -> void:
	if peer == multiplayer.get_unique_id() or not Net.is_online():
		_tell(text, kind)
	else:
		_tell.rpc_id(peer, text, kind)


@rpc("authority", "reliable")
func _tell(text: String, kind: String) -> void:
	Events.notify.emit(text, kind)
	if kind == "quest":
		Audio.play_ui("quest")


## A banner + sound for everyone in a dimension (dim -1: all).
func announce(title: String, subtitle: String, color: Color, sound := "", dim := 0) -> void:
	_broadcast(&"_announce", [title, subtitle, color, sound, dim], true)


@rpc("authority", "reliable")
func _announce(title: String, subtitle: String, color: Color, sound: String, dim: int) -> void:
	var w := gw()
	if w == null or (dim >= 0 and w.local_dimension != dim):
		return
	banner.emit(title, subtitle, color)
	if sound != "":
		Audio.play_ui(sound)


## Visual effects on every machine (meteor streaks, impacts, horn blasts).
func fx(kind: String, data: Dictionary) -> void:
	_broadcast(&"_fx", [kind, data], true)


@rpc("authority", "reliable")
func _fx(kind: String, data: Dictionary) -> void:
	var w := gw()
	if w == null:
		return
	ActivityFx.play(w, kind, data)


## Server: terrain edits (craters, ore) applied on every machine and saved
## with the world like any other edit.
func sculpt(changes: PackedInt32Array, dim: int) -> void:
	if changes.is_empty():
		return
	_broadcast(&"_voxels", [changes, dim], true)
	NpcNav.forget_cache()


@rpc("authority", "reliable")
func _voxels(changes: PackedInt32Array, dim: int) -> void:
	var vw := gw().world_for(dim)
	if vw != null:
		vw.set_voxels(changes)


# --- Fixtures: bounty boards, the Proving Ring ------------------------------------------

func _server_fixtures() -> void:
	var w := gw()
	var players := w.players_in(0)
	for loc in w.locations(0):
		if loc.kind != Location.Kind.VILLAGE:
			continue
		_keep_fixture("board:" + String(loc.id), loc.center, players, func() -> Entity:
			var spot := bounties.board_spot(loc)
			if spot.is_empty():
				return null
			return w.spawn_entity("act_board", spot["pos"], 0, {"village": String(loc.id), "yaw": spot["yaw"]}))
	var site: Variant = shared.get("arena_site")
	if site is Vector3:
		_keep_fixture("ring", site, players, func() -> Entity:
			var g := w.world_for(0).ground_below(site.x, site.y + 20.0, site.z, 40.0)
			var at := Vector3(site.x, g if absf(g) < 1e6 else site.y, site.z)
			return w.spawn_entity("act_arena", at, 0, {"radius": ProvingGrounds.RADIUS}))


func _keep_fixture(key: String, at: Vector3, players: Array[Player], make: Callable) -> void:
	var w := gw()
	var near := INF
	for p in players:
		near = minf(near, Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length())
	var id: int = _fixtures.get(key, 0)
	var e := w.entity(id) if id != 0 else null
	if e == null and near < 150.0:
		var vw := w.world_for(0)
		if vw == null or not vw.is_area_loaded(at):
			return
		var made: Variant = make.call()
		if made is Entity:
			_fixtures[key] = (made as Entity).net_id
	elif e != null and near > 240.0:
		w.despawn_entity(e)
		_fixtures.erase(key)


# --- Guidance -------------------------------------------------------------------------------

## Activity markers for QuestLog.markers() (and so the compass, minimap, map).
func markers() -> Array:
	var out: Array = []
	out.append_array(treasure.markers())
	out.append_array(bounties.markers())
	out.append_array(events.markers())
	out.append_array(ring.markers())
	return out


## Lines for the quest tracker: [{title, lines: PackedStringArray, kind}].
func tracker_entries() -> Array:
	var out: Array = []
	out.append_array(events.tracker())
	out.append_array(weather_craft.tracker())
	out.append_array(ring.tracker())
	out.append_array(treasure.tracker())
	out.append_array(bounties.tracker())
	return out


## Whether a village is being raided right now (NPCs shelter, guards fight).
func raid_at(village: String) -> bool:
	var ev: Dictionary = shared.get("event", {})
	return String(ev.get("kind", "")) == "raid" and String(ev.get("village", "")) == village and String(ev.get("stage", "")) != "over"


## Extra dialogue for villagers: activity options and a rumour pointing at something to do.
func dialog_extra(npc: Npc) -> Dictionary:
	var options: Array = []
	var rumour := ""
	match npc.role:
		"merchant":
			options.append({"text": "Buy a treasure map (%d gold)." % int(ItemDB.SHOP.get("treasure_map", 40)), "id": "act:buy_map"})
			rumour = "Maps come from dead men's pockets. Most lead somewhere. Bring a pickaxe — the X is always under a foot of dirt."
		"elder", "chief":
			rumour = "The bounty board by the well pays for monsters with names. And if the horns sound at dusk, we'll need your blade."
		"guard":
			var c := bounties.first_active()
			if not c.is_empty():
				rumour = "%s? Last seen near %s. Bring potions." % [String(c["name"]), String(c["where"])]
			else:
				rumour = "There's a ring of old stones out on the plains. Sound the horn there if you want a real fight."
		"blacksmith":
			if not events.recent_meteor().is_empty():
				rumour = "Saw a star come down last night. Bring me starmetal and I'll forge you something the dragon would envy."
		_:
			var m := events.recent_meteor()
			if not m.is_empty():
				rumour = "Did you see the falling star last night? It came down past the fields — the ground there still glows."
	return {"options": options, "rumour": rumour}


func on_dialog_choice(npc: Npc, choice: String) -> void:
	var p := gw().local_player
	match choice:
		"buy_map":
			if p.buy("treasure_map"):
				Events.notify.emit("Bought a treasure map. Its riddle is in your journal.", "loot")
			else:
				Events.notify.emit("Not enough gold.", "warn")
			npc.call("_open_dialog")


## Arrow on a villager's head for activities (e.g. the trader when you have no map yet).
func npc_marker(_npc: Npc) -> String:
	return ""


# --- One-time tips ----------------------------------------------------------------------------

func _tips() -> void:
	var w := gw()
	var q := w.quests
	var tips: Dictionary = q.activity.get("tips", {})
	if q.is_completed("kindling") and not tips.has("board"):
		tips["board"] = true
		Events.notify.emit("Tip: the bounty board by Emberfall's well posts monster hunts, and the trader sells treasure maps.", "info")
	var site: Variant = shared.get("arena_site")
	if site is Vector3 and not tips.has("ring") and w.local_dimension == 0 \
			and w.local_player.global_position.distance_to(site) < 70.0:
		tips["ring"] = true
		Events.notify.emit("The Proving Ring: sound the war horn at its centre to face waves of monsters for loot and honour.", "quest")
	q.activity["tips"] = tips


# --- Save ------------------------------------------------------------------------------------

func save_state() -> Dictionary:
	return {"shared": _persistent_shared(), "world": world.duplicate(true)}


func _persistent_shared() -> Dictionary:
	var out := {}
	for k: String in ["contracts", "leaderboard", "arena_site", "contract_seq", "last_meteor"]:
		if shared.has(k):
			out[k] = shared[k]
	# Contracts in progress resume as accepted; their quarry respawns on approach.
	if out.has("contracts"):
		var list: Array = (out["contracts"] as Array).duplicate(true)
		for c: Dictionary in list:
			c.erase("spawned")
			c.erase("target")
			c.erase("tracks")
		out["contracts"] = list
	return out


func load_state(d: Dictionary) -> void:
	var s: Variant = d.get("shared", {})
	if s is Dictionary:
		shared = (s as Dictionary).duplicate(true)
	var wd: Variant = d.get("world", {})
	if wd is Dictionary:
		world = (wd as Dictionary).duplicate(true)
	if not shared.has("arena_site") and gw() != null and gw().gen_for(0) != null:
		var site := ProvingGrounds.find_site(gw())
		if site != Vector3.INF:
			shared["arena_site"] = site
	_dirty = true
