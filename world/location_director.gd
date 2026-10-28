class_name LocationDirector
extends Node
## Server: brings locations to life when a player approaches (NPCs, monsters,
## bosses, chests, shrines, portals) and tears them down when everyone has
## left. Dead monsters respawn after a while, out of sight.

const ACTIVATE_DISTANCE := 130.0
const DEACTIVATE_DISTANCE := 210.0
const RESPAWN_SECONDS := 150.0

var _active := {}   # location id -> {"loc": Location, "spawned": {index: net_id}, "dead_at": {index: time}}
var _timer := 0.0


func gw() -> GameWorld:
	return get_parent() as GameWorld


func _process(delta: float) -> void:
	if not Net.is_server():
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0
	var w := gw()
	for dim: int in w.gens:
		var players := w.players_in(dim)
		for loc in w.locations(dim):
			var d := _nearest_player_distance(loc, players)
			var active := _active.has(loc.id)
			if not active and d < ACTIVATE_DISTANCE:
				_activate(loc, dim)
			elif active and d > DEACTIVATE_DISTANCE:
				_deactivate(loc)
			elif active:
				_respawn_dead(loc, dim, players)


func _nearest_player_distance(loc: Location, players: Array[Player]) -> float:
	var best := 1e9
	for p in players:
		var to := p.global_position - loc.center
		if loc.half_height <= 0.0:
			to.y = 0.0
		best = minf(best, to.length() - loc.radius * 0.5)
	return best


func _activate(loc: Location, dim: int) -> void:
	var entry := {"loc": loc, "spawned": {}, "dead_at": {}}
	_active[loc.id] = entry
	for i in loc.spawns.size():
		_spawn(loc, dim, i, entry)


func _spawn(loc: Location, dim: int, i: int, entry: Dictionary) -> void:
	var w := gw()
	var s: Dictionary = loc.spawns[i]
	var pos: Vector3 = s["pos"]
	var e: Entity = null
	match String(s["type"]):
		"npc":
			e = w.spawn_entity("npc", pos, dim, {"role": s.get("role", "villager"), "village": String(loc.id), "seed": hash(String(loc.id)) + i})
		"guard_post":
			for g in 2:
				var gp := pos + Vector3(-3.0 + g * 6.0, 0, 5.0)
				var guard := w.spawn_entity("npc", gp, dim, {"role": "guard", "village": String(loc.id), "seed": hash(String(loc.id)) + 100 + g})
				entry["spawned"]["%d_%d" % [i, g]] = guard.net_id if guard != null else 0
			return
		"chest":
			var key := "%s:%d" % [loc.id, i]
			e = w.spawn_entity("chest", pos, dim, {"key": key, "tier": int(s.get("tier", 1)), "opened": w.opened_chests.has(key)})
		"shrine":
			e = w.spawn_entity("shrine", pos, dim, {"location": String(loc.id)})
		"portal":
			e = w.spawn_entity("portal", pos, dim, {"to": int(s.get("to", 1)), "size": s.get("size", Vector2(10, 14))})
		"lore":
			e = w.spawn_entity("lore", pos, dim, {"text": s.get("text", "")})
		"well":
			e = w.spawn_entity("well", pos, dim, {"key": String(loc.id)})
		"decor":
			e = w.spawn_entity("decor", pos, dim, {"decor": s.get("decor", "bones"), "size": s.get("size", 1.0),
				"yaw": s.get("yaw", 0.0), "tilt": s.get("tilt", 0.0), "seed": s.get("seed", i)})
		"station":
			# Crafting stations (entities/interact/station.gd, items) once that kind exists.
			if ResourceLoader.exists("res://entities/interact/station.gd"):
				e = w.spawn_entity("station", pos, dim, {"station": s.get("station", "workbench"), "yaw": s.get("yaw", 0.0), "fixed": true})
		"enemy":
			e = w.spawn_entity(String(s.get("kind", "skeleton")), pos, dim, {"home": String(loc.id)})
			if e != null:
				e.set_meta("spawn_index", i)
				e.died.connect(func(_x: Entity) -> void: entry["dead_at"][i] = Time.get_ticks_msec() / 1000.0)
		"boss":
			var boss_kind := String(s.get("kind", ""))
			if not w.bosses_defeated.has(boss_kind):
				e = w.spawn_entity(boss_kind, pos, dim, {"home": String(loc.id)})
				if e != null:
					e.set("home_location", String(loc.id))
	if e != null:
		entry["spawned"][i] = e.net_id


func _respawn_dead(loc: Location, dim: int, players: Array[Player]) -> void:
	var entry: Dictionary = _active[loc.id]
	var now := Time.get_ticks_msec() / 1000.0
	for i: int in entry["dead_at"].keys():
		if now - float(entry["dead_at"][i]) < RESPAWN_SECONDS:
			continue
		var pos: Vector3 = loc.spawns[i]["pos"]
		var seen := false
		for p in players:
			if p.global_position.distance_to(pos) < 30.0:
				seen = true
				break
		if seen:
			continue
		entry["dead_at"].erase(i)
		_spawn(loc, dim, i, entry)


func _deactivate(loc: Location) -> void:
	var w := gw()
	var entry: Dictionary = _active[loc.id]
	for key: Variant in entry["spawned"]:
		var e := w.entity(int(entry["spawned"][key]))
		if e == null:
			continue
		if e.has_method("is_engaged") and e.call("is_engaged"):
			continue
		w.despawn_entity(e)
	_active.erase(loc.id)


## Bosses reset when their fight is abandoned: called by Boss when it leashes.
func reset_location(loc_id: StringName) -> void:
	if _active.has(loc_id):
		_deactivate(_active[loc_id]["loc"])
