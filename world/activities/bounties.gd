class_name Bounties
extends RefCounted
## The bounty boards. Each village's board shows the same three contracts
## (party-wide, refreshed every in-game day):
##   elite - a named, oversized monster (more health and bite, an ember aura and
##           a nameplate) waiting near a landmark; its lair is on the compass.
##   hunt  - a legendary beast. The board only knows where it was last seen: reach
##           that area and fresh tracks lead from its edge to the den.
## Accept up to two at a board. The kill pays every hunter near it: gold, XP, a
## trophy to sell, sometimes a treasure map. Server-run; clients mirror
## `shared["contracts"]`.

const QUARRY := [
	{"mob": "dire_wolf", "type": "hunt", "names": ["Greyfang", "Old Ashjaw", "Nightrunner"], "what": "dire wolf", "tracks": "paw", "tier": 1,
		"biomes": [WorldGen.Biome.PLAINS, WorldGen.Biome.FOREST, WorldGen.Biome.PEAKS]},
	{"mob": "bear", "type": "hunt", "names": ["Thornhide", "Grandmother Bear", "Ironpaw"], "what": "great bear", "tracks": "bear", "tier": 2,
		"biomes": [WorldGen.Biome.FOREST, WorldGen.Biome.PEAKS, WorldGen.Biome.PLAINS]},
	{"mob": "frost_wolf", "type": "hunt", "names": ["Frostmaw", "The White Widow"], "what": "frost wolf", "tracks": "paw", "tier": 2,
		"biomes": [WorldGen.Biome.PEAKS]},
	{"mob": "troll", "type": "elite", "names": ["Gorrak Bridgebreaker", "Mossback"], "what": "troll", "tier": 2,
		"biomes": [WorldGen.Biome.PEAKS, WorldGen.Biome.FOREST, WorldGen.Biome.PLAINS]},
	{"mob": "giant_spider", "type": "elite", "names": ["The Weaver", "Hollowmother"], "what": "giant spider", "tier": 1,
		"biomes": [WorldGen.Biome.FOREST, WorldGen.Biome.MARSH]},
	{"mob": "skeleton", "type": "elite", "names": ["Captain Rattlebone", "Sir Ossian the Hollow"], "what": "skeleton captain", "tier": 1, "minions": "skeleton",
		"biomes": [WorldGen.Biome.PLAINS, WorldGen.Biome.MARSH, WorldGen.Biome.WASTES]},
	{"mob": "ghoul", "type": "elite", "names": ["The Gravedigger", "Hungry Tom"], "what": "ghoul", "tier": 1,
		"biomes": [WorldGen.Biome.MARSH, WorldGen.Biome.PLAINS]},
	{"mob": "rock_golem", "type": "elite", "names": ["The Walking Hill"], "what": "rock golem", "tier": 3,
		"biomes": [WorldGen.Biome.PEAKS, WorldGen.Biome.WASTES]},
	{"mob": "scorpion", "type": "elite", "names": ["Glasstail"], "what": "giant scorpion", "tier": 2,
		"biomes": [WorldGen.Biome.WASTES]},
	{"mob": "bog_lurker", "type": "elite", "names": ["Old Gulp"], "what": "bog lurker", "tier": 2,
		"biomes": [WorldGen.Biome.MARSH]},
]
const MAX_OPEN := 3
const MAX_ACTIVE := 2
const SPAWN_ELITE := 110.0
const SPAWN_HUNT := 55.0
const LEASH := 270.0

var d: ActivityDirector
var _board_spots := {}
var _targets := {}      # contract id -> [target net id, mark net id, tracks net id, minion ids]
var _far := {}          # contract id -> seconds with nobody near


func _init(director: ActivityDirector) -> void:
	d = director


func contracts() -> Array:
	return d.shared.get("contracts", [])


func contract(id: int) -> Dictionary:
	for c: Dictionary in contracts():
		if int(c["id"]) == id:
			return c
	return {}


func first_active() -> Dictionary:
	for c: Dictionary in contracts():
		if c["state"] == "active":
			return c
	return {}


# --- Generation (pure) ----------------------------------------------------------------

## A contract near a landmark whose biome suits the quarry.
static func make_contract(gen: WorldGen, locs: Array[Location], id: int, rng: RandomNumberGenerator) -> Dictionary:
	for attempt in 30:
		var q: Dictionary = QUARRY[rng.randi() % QUARRY.size()]
		var lms: Array[Location] = []
		for loc in locs:
			if loc.dimension != 0 or loc.half_height > 0.0 or loc.kind == Location.Kind.VILLAGE or loc.center.y < WorldGen.SEA_LEVEL:
				continue
			if gen.biome_at(int(loc.center.x), int(loc.center.z)) in q["biomes"]:
				lms.append(loc)
		if lms.is_empty():
			continue
		var lm: Location = lms[rng.randi() % lms.size()]
		for k in 12:
			var a := rng.randf() * TAU
			var r := lm.radius + rng.randf_range(22.0, 48.0)
			var den := Vector3(lm.center.x + cos(a) * r, 0.0, lm.center.z + sin(a) * r)
			if not TreasureHunt.spot_ok(gen, locs, den.x, den.z) or not (gen.biome_at(int(den.x), int(den.z)) in q["biomes"]):
				continue
			den.y = gen.ground_level(den.x, den.z)
			var area := den
			if q["type"] == "hunt":
				var b := rng.randf() * TAU
				area = den + Vector3(cos(b), 0.0, sin(b)) * rng.randf_range(24.0, 34.0)
				area.y = gen.ground_level(area.x, area.z)
			var names: Array = q["names"]
			var tier := int(q["tier"])
			return {"id": id, "type": q["type"], "mob": q["mob"], "name": names[rng.randi() % names.size()], "what": q["what"],
				"where": lm.name, "den": den, "area": area, "tier": tier, "state": "open", "tracks_style": String(q.get("tracks", "paw")),
				"minions": String(q.get("minions", "")),
				"gold": 70 * tier + rng.randi_range(0, 6) * 5, "xp": 110 * tier,
				"trophy": "trophy_pelt" if q["type"] == "hunt" else ("trophy_skull" if tier >= 3 else "trophy_fang")}
	return {}


## Combat numbers for a named monster of `tier` (party of `players`).
static func elite_scale(tier: int, players: int) -> Dictionary:
	return {"health": (3.5 + tier) * (1.0 + 0.5 * maxi(0, players - 1)), "damage": 1.35 + 0.15 * tier, "size": 1.25 + 0.1 * tier, "xp": 5}


# --- Server ------------------------------------------------------------------------------

func server_tick(dt: float) -> void:
	var w := d.gw()
	var list: Array = d.shared.get("contracts", [])
	var day := w.day()
	# Refresh the board each morning: finished and untaken contracts make room.
	if int(d.world.get("contracts_day", -1)) != day:
		d.world["contracts_day"] = day
		list = list.filter(func(c: Dictionary) -> bool: return c["state"] == "active")
	var open := 0
	for c: Dictionary in list:
		if c["state"] != "done":
			open += 1
	var changed := list.size() != contracts().size()
	if open < MAX_OPEN:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([w.gen_for(0).world_seed, day, int(d.shared.get("contract_seq", 0))])
		while open < MAX_OPEN:
			var seq := int(d.shared.get("contract_seq", 0)) + 1
			d.shared["contract_seq"] = seq
			var c := make_contract(w.gen_for(0), w.locations(0), seq, rng)
			if c.is_empty():
				break
			list.append(c)
			open += 1
			changed = true
	if changed:
		d.set_shared("contracts", list)
	for c: Dictionary in list:
		if c["state"] == "active":
			_tick_contract(c, dt)


func _tick_contract(c: Dictionary, dt: float) -> void:
	var w := d.gw()
	var id := int(c["id"])
	var players := w.players_in(0)
	var den: Vector3 = c["den"]
	var area: Vector3 = c["area"]
	var near_den := INF
	var near_area := INF
	var nearest: Player = null
	for p in players:
		if p.dead:
			continue
		var dd := Vector2(p.global_position.x - den.x, p.global_position.z - den.z).length()
		var da := Vector2(p.global_position.x - area.x, p.global_position.z - area.z).length()
		near_den = minf(near_den, dd)
		if da < near_area:
			near_area = da
			nearest = p
	var spawned: Array = _targets.get(id, [])
	if spawned.is_empty():
		var trigger := near_den < SPAWN_ELITE if c["type"] == "elite" else near_area < SPAWN_HUNT
		if trigger:
			_spawn_quarry(c, nearest)
		return
	var target := w.entity(int(spawned[0]))
	if target == null or target.dead:
		if target != null and target.dead:
			_complete(c, target)
		else:
			_targets.erase(id)
			c.erase("tracks_from")
			d.mark_dirty()
		return
	if minf(near_den, near_area) > LEASH:
		_far[id] = float(_far.get(id, 0.0)) + dt
		if float(_far[id]) > 60.0:
			_despawn_quarry(id)
			c.erase("tracks_from")
			d.mark_dirty()
	else:
		_far[id] = 0.0


func _spawn_quarry(c: Dictionary, nearest: Player) -> void:
	var w := d.gw()
	var vw := w.world_for(0)
	var den: Vector3 = c["den"]
	if vw == null or not vw.is_area_loaded(den):
		return
	var g := vw.ground_below(den.x, den.y + 30.0, den.z, 60.0)
	if absf(g) < 1e6:
		den.y = g
	var e := w.spawn_entity(String(c["mob"]), den + Vector3(0, 0.3, 0), 0, {})
	if e == null:
		return
	apply_elite(e, int(c["tier"]), String(c["name"]), w.players_in(0).size(), den)
	var mark := w.spawn_entity("act_elite", den, 0, {"target": e.net_id, "name": "%s, the %s" % [c["name"], c["what"]],
		"size": float(elite_scale(int(c["tier"]), 1)["size"]), "max_health": e.max_health})
	var ids := [e.net_id, mark.net_id if mark != null else 0, 0, []]
	if String(c.get("minions", "")) != "":
		for i in 3:
			var a := TAU * float(i) / 3.0
			var mp := den + Vector3(cos(a) * 3.0, 0.3, sin(a) * 3.0)
			var m := w.spawn_entity(String(c["minions"]), mp, 0, {})
			if m != null:
				(ids[3] as Array).append(m.net_id)
	if c["type"] == "hunt":
		var from: Vector3 = c["area"]
		if nearest != null:
			var area_p: Vector3 = c["area"]
			var to_p := nearest.global_position - area_p
			to_p.y = 0.0
			if to_p.length() > 1.0:
				from = area_p + to_p.normalized() * minf(18.0, to_p.length())
		var pts := trail(vw, from, den, int(c["id"]))
		var tracks := w.spawn_entity("act_tracks", pts[0], 0, {"points": pts, "style": String(c.get("tracks_style", "paw"))})
		ids[2] = tracks.net_id if tracks != null else 0
		c["tracks_from"] = pts[0]
		d.tell(nearest.peer_id if nearest != null else 1, "Fresh tracks! Follow them to %s." % String(c["name"]), "quest")
	_targets[int(c["id"])] = ids
	_far[int(c["id"])] = 0.0
	d.mark_dirty()


## Server: make an ordinary monster a named elite.
static func apply_elite(e: Entity, tier: int, name: String, players: int, home: Vector3) -> void:
	var k := elite_scale(tier, players)
	e.max_health *= float(k["health"])
	e.health = e.max_health
	e.display_name = name
	if "stats" in e:
		var st: Dictionary = (e.get("stats") as Dictionary).duplicate()
		st["damage"] = float(st.get("damage", 10.0)) * float(k["damage"])
		st["aggro"] = float(st.get("aggro", 16.0)) * 1.3
		st["name"] = name
		e.set("stats", st)
	if "xp_value" in e:
		e.set("xp_value", int(e.get("xp_value")) * int(k["xp"]))
	if "spawn_point" in e:
		e.set("spawn_point", home)
	e.set_meta("elite", true)


## Footprints from `from` to `to`: a meandering line of feet positions.
static func trail(vw: VoxelWorld, from: Vector3, to: Vector3, seed_value: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var flat := Vector2(to.x - from.x, to.z - from.z)
	var n := maxi(4, int(flat.length() / 1.6))
	var side := Vector2(-flat.y, flat.x).normalized()
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.08
	var prev_y := from.y
	for i in n + 1:
		var t := float(i) / n
		var wobble := noise.get_noise_1d(float(i)) * 4.0 * sin(t * PI)
		var p2 := Vector2(from.x, from.z) + flat * t + side * wobble
		var y := prev_y
		if vw != null and vw.is_area_loaded(Vector3(p2.x, prev_y, p2.y)):
			var g := vw.ground_below(p2.x, prev_y + 6.0, p2.y, 14.0)
			if absf(g) < 1e6:
				y = g
		out.append(Vector3(p2.x, y, p2.y))
		prev_y = y
	return out


func _complete(c: Dictionary, target: Entity) -> void:
	var w := d.gw()
	var id := int(c["id"])
	c["state"] = "done"
	var paid := 0
	for p in w.players_near_credit(target):
		w.replicator.give_gold_to(p.peer_id, int(c["gold"]))
		w.replicator.give_xp_to(p.peer_id, int(c["xp"]), "")
		w.replicator.give_item_to(p.peer_id, String(c["trophy"]), 1)
		if randf() < 0.3:
			w.replicator.give_item_to(p.peer_id, "treasure_map", 1)
		d.tell(p.peer_id, "Bounty complete: %s is dead. +%d gold." % [c["name"], int(c["gold"])], "quest")
		paid += 1
	d.fx("burst", {"pos": target.center(), "color": Color(1.0, 0.65, 0.25), "dim": 0})
	_despawn_quarry(id, false)
	d.mark_dirty()


func _despawn_quarry(id: int, include_target := true) -> void:
	var w := d.gw()
	var ids: Array = _targets.get(id, [])
	_targets.erase(id)
	if ids.is_empty():
		return
	var all: Array = [ids[1], ids[2]]
	if include_target:
		all.append(ids[0])
		all.append_array(ids[3])
	for nid: int in all:
		var e := w.entity(nid)
		if e != null:
			w.despawn_entity(e)


func server_accept(p: Player, id: int) -> void:
	var c := contract(id)
	if c.is_empty() or c["state"] != "open":
		return
	var active := 0
	for o: Dictionary in contracts():
		if o["state"] == "active":
			active += 1
	if active >= MAX_ACTIVE:
		d.tell(p.peer_id, "You already have %d bounties. Finish one first." % MAX_ACTIVE, "warn")
		return
	c["state"] = "active"
	c["taker"] = p.display_name
	d.mark_dirty()
	d.announce("BOUNTY ACCEPTED", "%s, the %s — near %s" % [c["name"], c["what"], c["where"]], Color(1.0, 0.7, 0.3), "quest")


func server_abandon(_p: Player, id: int) -> void:
	var c := contract(id)
	if c.is_empty() or c["state"] != "active":
		return
	_despawn_quarry(id)
	c["state"] = "open"
	c.erase("tracks_from")
	d.mark_dirty()


## Where a village's board stands: open ground near the plaza, facing it.
func board_spot(loc: Location) -> Dictionary:
	if _board_spots.has(loc.id):
		return _board_spots[loc.id]
	var vw := d.gw().world_for(0)
	if vw == null or not vw.is_area_loaded(loc.center):
		return {}
	var best := {}
	for r: float in [6.5, 8.0, 9.5, 11.0]:
		for i in 16:
			var a := TAU * float(i) / 16.0 + 0.2
			var p := loc.center + Vector3(cos(a) * r, 0.0, sin(a) * r)
			var h := NpcNav.stand_height(vw, 0, p.x, p.z, loc.center.y)
			if is_nan(h) or absf(h - loc.center.y) > 1.5:
				continue
			var face := (loc.center - p).normalized()
			var side := Vector3(-face.z, 0, face.x)
			var ok := true
			for s: float in [-1.0, 1.0]:
				var q := p + side * 1.0 * s
				var hq := NpcNav.stand_height(vw, 0, q.x, q.z, h)
				if is_nan(hq) or absf(hq - h) > 0.5:
					ok = false
			for s2 in loc.spawns:
				if (s2["pos"] as Vector3).distance_to(Vector3(p.x, h, p.z)) < 3.2:
					ok = false
			if ok:
				best = {"pos": Vector3(p.x, h, p.z), "yaw": atan2(face.x, face.z)}
				break
		if not best.is_empty():
			break
	_board_spots[loc.id] = best
	return best


# --- Client -------------------------------------------------------------------------------

func markers() -> Array:
	var out: Array = []
	var w := d.gw()
	var me := w.local_player.global_position if w.local_player != null else Vector3.ZERO
	for c: Dictionary in contracts():
		if c["state"] != "active":
			continue
		if c["type"] == "elite":
			out.append({"pos": c["den"], "dim": 0, "label": "Bounty: " + String(c["name"]), "kind": "activity", "icon": "bounty", "priority": 2})
		elif c.has("tracks_from"):
			var start: Vector3 = c["tracks_from"]
			if me.distance_to(start) > 22.0 and me.distance_to(c["den"]) > 30.0:
				out.append({"pos": start, "dim": 0, "label": "Fresh tracks: " + String(c["name"]), "kind": "activity", "icon": "bounty", "priority": 2})
		else:
			out.append({"pos": c["area"], "dim": 0, "label": "Hunt: %s (last seen)" % String(c["name"]), "kind": "activity", "radius": 30.0, "icon": "bounty", "priority": 1})
	return out


func tracker() -> Array:
	var out: Array = []
	for c: Dictionary in contracts():
		if c["state"] != "active":
			continue
		var line := ""
		if c["type"] == "elite":
			line = "Slay %s near %s" % [c["name"], c["where"]]
		elif c.has("tracks_from"):
			line = "Follow the tracks to its den"
		else:
			line = "Find its trail near %s" % String(c["where"])
		out.append({"title": "Bounty: " + String(c["name"]), "lines": PackedStringArray([line, "Reward: %d gold, trophy" % int(c["gold"])]), "kind": "activity"})
	return out
