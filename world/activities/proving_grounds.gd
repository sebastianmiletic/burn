class_name ProvingGrounds
extends RefCounted
## The Proving Ring: eight standing stones on the plains near Emberfall. Sound
## the war horn at its centre and waves of monsters come over the stones, each
## wave larger and meaner, a named champion every fifth. Everyone inside the
## ring when it starts fights; leave the ring for long, or fall, and you are out.
## Every cleared wave pays; waves 3/6/9/12 spill a reward cache; first-time
## milestones (5, 10, 15 waves) award the Ring Champion's gear. The best runs
## are carved on the honours stone (per save). Server-run.

const RADIUS := 14.0
const COUNTDOWN := 6.0
const BREAK := 7.0
const OUT_SECONDS := 8.0
const MAX_WAVES := 15
const WAVES := [
	[["skeleton", 3]],
	[["wolf", 3], ["skeleton", 1]],
	[["skeleton", 2], ["archer", 2]],
	[["ghoul", 4]],
	[["skeleton", 2], ["*troll", 1]],
	[["dire_wolf", 3], ["archer", 1]],
	[["ghoul", 2], ["archer", 2], ["troll", 1]],
	[["giant_spider", 4], ["skeleton", 1]],
	[["troll", 2], ["skeleton", 2]],
	[["archer", 2], ["*rock_golem", 1], ["ghoul", 2]],
]
const MILESTONES := {5: "helm_ringchampion", 10: "cuirass_ringchampion", 15: "sword_champion"}
const CACHE_WAVES := {3: [["potion_health", 3], ["iron_ingot", 3]], 6: [["potion_greater", 2], ["ruby", 1], ["treasure_map", 1], ["frost_totem", 1]],
	9: [["potion_greater", 2], ["gold_ingot", 3], ["sapphire", 1], ["storm_horn", 1]], 12: [["potion_phoenix", 1], ["mithril_ingot", 2], ["treasure_map", 1]]}

var d: ActivityDirector
var _monsters: Array[int] = []
var _participants := {}    # peer -> seconds outside the ring (or -1 when out)
var rng := RandomNumberGenerator.new()


func _init(director: ActivityDirector) -> void:
	d = director
	rng.randomize()


func state() -> Dictionary:
	return d.shared.get("arena", {})


func site() -> Vector3:
	var s: Variant = d.shared.get("arena_site")
	return s if s is Vector3 else Vector3.INF


## A flat, dry, open place 70–130 m from Emberfall (deterministic per world).
static func find_site(gw: GameWorld) -> Vector3:
	var gen := gw.gen_for(0)
	var home := gw.location_by_id(&"emberfall")
	if gen == null or home == null:
		return Vector3.INF
	var best := Vector3.INF
	var best_score := INF
	var locs := gw.locations(0)
	for ring_i in 4:
		var r := 75.0 + ring_i * 18.0
		for i in 24:
			var a := TAU * float(i) / 24.0
			var x := home.center.x + cos(a) * r
			var z := home.center.z + sin(a) * r
			if not TreasureHunt.spot_ok(gen, locs, x, z):
				continue
			var near_loc := false
			for loc in locs:
				if loc.dimension == 0 and Vector2(loc.center.x - x, loc.center.z - z).length() < loc.radius + RADIUS + 10.0:
					near_loc = true
					break
			if near_loc:
				continue
			var lo := INF
			var hi := -INF
			var dry := true
			for k in 12:
				var b := TAU * float(k) / 12.0
				for rr: float in [RADIUS * 0.5, RADIUS + 2.0]:
					var h := float(gen.surface_height(int(x + cos(b) * rr), int(z + sin(b) * rr)))
					lo = minf(lo, h)
					hi = maxf(hi, h)
					if h < WorldGen.SEA_LEVEL + 1:
						dry = false
			if not dry:
				continue
			var score := (hi - lo) + r * 0.01
			if score < best_score:
				best_score = score
				best = Vector3(x, gen.ground_level(x, z), z)
	return best


# --- Server -------------------------------------------------------------------------------

func server_start(p: Player) -> void:
	var c := site()
	if c == Vector3.INF or p.dimension != 0 or Vector2(p.global_position.x - c.x, p.global_position.z - c.z).length() > 7.0:
		return
	var st := state()
	if bool(st.get("running", false)):
		return
	_participants.clear()
	var names := PackedStringArray()
	for q in d.gw().players_in(0):
		if not q.dead and Vector2(q.global_position.x - c.x, q.global_position.z - c.z).length() < RADIUS + 2.0:
			_participants[q.peer_id] = 0.0
			names.append(q.display_name)
	d.set_shared("arena", {"running": true, "stage": "countdown", "wave": 0, "left": 0, "next_in": COUNTDOWN, "names": " & ".join(names), "fighters": names.size()})
	d.fx("horn", {"pos": c + Vector3(0, 2, 0), "dim": 0})
	d.announce("THE PROVING BEGINS", "Stay inside the stones. Waves come from every side.", Color(1.0, 0.6, 0.25), "quest")


func server_tick(dt: float) -> void:
	var st := state()
	if not bool(st.get("running", false)):
		return
	var w := d.gw()
	var c := site()
	# Who is still in?
	var inside := 0
	for peer: int in _participants.keys():
		if float(_participants[peer]) < 0.0:
			continue
		var p := d.player_of(peer)
		if p == null or p.dead:
			_participants[peer] = -1.0
			d.tell(peer, "You fell in the Proving Ring.", "warn")
			continue
		var out := Vector2(p.global_position.x - c.x, p.global_position.z - c.z).length() > RADIUS + 4.0 or p.dimension != 0
		if out:
			_participants[peer] = float(_participants[peer]) + dt
			if float(_participants[peer]) > OUT_SECONDS:
				_participants[peer] = -1.0
				d.tell(peer, "You left the ring: the Proving goes on without you.", "warn")
				continue
		else:
			_participants[peer] = 0.0
		inside += 1
	if inside == 0:
		_finish(st)
		return
	var alive := 0
	for id in _monsters:
		var e := w.entity(id)
		if e != null and not e.dead:
			alive += 1
	st["left"] = alive
	match String(st["stage"]):
		"countdown", "break":
			st["next_in"] = float(st["next_in"]) - dt
			if float(st["next_in"]) <= 0.0:
				st["wave"] = int(st["wave"]) + 1
				_spawn_wave(int(st["wave"]), inside)
				st["stage"] = "fight"
				st["left"] = _monsters.size()
		"fight":
			if alive == 0:
				var wave := int(st["wave"])
				_wave_cleared(wave)
				if wave >= MAX_WAVES:
					st["cleared"] = wave
					_finish(st, true)
					return
				st["stage"] = "break"
				st["next_in"] = BREAK
	d.mark_dirty()


## Monsters of `wave` for `fighters` people: [[kind, count, champion]].
static func wave_plan(wave: int, fighters: int) -> Array:
	var base: Array = WAVES[(wave - 1) % WAVES.size()]
	var loops := (wave - 1) / WAVES.size()
	var out: Array = []
	for entry: Array in base:
		var kind := String(entry[0])
		var champ := kind.begins_with("*")
		kind = kind.trim_prefix("*")
		var n := int(entry[1])
		if not champ:
			n += loops + maxi(0, fighters - 1)
		out.append([kind, n, champ])
	if wave % 5 == 0 and wave > 10:
		out.append(["troll", 1, true])
	return out


func _spawn_wave(wave: int, fighters: int) -> void:
	var w := d.gw()
	var vw := w.world_for(0)
	var c := site()
	_monsters.clear()
	var hp := 1.0 + 0.09 * (wave - 1)
	var count := 0
	for entry: Array in wave_plan(wave, fighters):
		for i in int(entry[1]):
			count += 1
			var a := rng.randf() * TAU
			for attempt in 5:
				var r := RADIUS + rng.randf_range(2.0, 5.0)
				var x := c.x + cos(a) * r
				var z := c.z + sin(a) * r
				if vw == null or not vw.is_area_loaded(Vector3(x, c.y, z)):
					a += 0.7
					continue
				var g := vw.ground_below(x, c.y + 20.0, z, 40.0)
				if absf(g) > 1e6:
					a += 0.7
					continue
				var e := w.spawn_entity(String(entry[0]), Vector3(x, g + 0.3, z), 0, {})
				if e == null:
					break
				e.set_meta("proving_ring", true)
				e.max_health *= hp
				e.health = e.max_health
				if "spawn_point" in e:
					e.set("spawn_point", c)
				if bool(entry[2]):
					var title := "%s the Unbroken" % ["Gorm", "Varra", "Old Tusk", "Brakka"][wave / 5 % 4]
					Bounties.apply_elite(e, 2, title, fighters, c)
					w.spawn_entity("act_elite", e.global_position, 0, {"target": e.net_id, "name": title + " · Ring Champion", "size": 1.35, "max_health": e.max_health})
				_monsters.append(e.net_id)
				break
	d.announce("WAVE %d" % wave, "%d foes" % _monsters.size(), Color(1.0, 0.55, 0.3), "", 0)


func _wave_cleared(wave: int) -> void:
	var w := d.gw()
	var c := site()
	var gold := 8 * wave + 4
	var milestones: Dictionary = d.world.get("ring_milestones", {})
	for peer: int in _participants:
		if float(_participants[peer]) < 0.0:
			continue
		var p := d.player_of(peer)
		if p == null:
			continue
		w.replicator.give_gold_to(peer, gold)
		w.replicator.give_xp_to(peer, 25 + 10 * wave, "")
		var got := int(milestones.get(p.display_name, 0))
		if MILESTONES.has(wave) and got < wave:
			milestones[p.display_name] = wave
			w.replicator.give_item_to(peer, MILESTONES[wave], 1)
			d.tell(peer, "Milestone: %d waves! You earned the %s." % [wave, ItemDB.display_name(MILESTONES[wave])], "quest")
	d.world["ring_milestones"] = milestones
	if CACHE_WAVES.has(wave):
		for entry: Array in CACHE_WAVES[wave]:
			w.drop_item(c + Vector3(0, 1.5, 0), entry[0], int(entry[1]), 0)
		d.fx("burst", {"pos": c + Vector3(0, 1.2, 0), "color": Color(1.0, 0.75, 0.3), "dim": 0})
	d.announce("WAVE %d CLEARED" % wave, "+%d gold each" % gold, Color(1.0, 0.8, 0.4), "coin", 0)


func _finish(st: Dictionary, champion := false) -> void:
	var w := d.gw()
	for id in _monsters:
		var e := w.entity(id)
		if e != null and not e.dead:
			w.despawn_entity(e)
	_monsters.clear()
	var cleared := int(st.get("wave", 0)) - (0 if champion else 1)
	cleared = maxi(0, cleared)
	var board: Array = d.shared.get("leaderboard", [])
	if cleared > 0:
		board.append({"names": String(st.get("names", "?")), "waves": cleared, "day": w.day()})
		board.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["waves"]) > int(b["waves"]))
		if board.size() > 5:
			board.resize(5)
		d.shared["leaderboard"] = board
	var best := int(board[0]["waves"]) if not board.is_empty() else 0
	d.set_shared("arena", {"running": false, "stage": "over", "last": cleared, "best": best})
	_participants.clear()
	var title := "CHAMPION OF THE RING" if champion else "THE PROVING ENDS"
	d.announce(title, "%d waves held. Best in this world: %d." % [cleared, best], Color(1.0, 0.75, 0.35), "victory" if champion else "", 0)


func is_participant(peer: int) -> bool:
	return _participants.has(peer) and float(_participants[peer]) >= 0.0


# --- Client --------------------------------------------------------------------------------

func markers() -> Array:
	var c := site()
	if c == Vector3.INF:
		return []
	var w := d.gw()
	var me := w.local_player.global_position if w.local_player != null else Vector3.ZERO
	var st := state()
	if bool(st.get("running", false)):
		return [{"pos": c, "dim": 0, "label": "The Proving Ring", "kind": "activity", "icon": "ring", "priority": 4, "radius": RADIUS}]
	if Vector2(me.x - c.x, me.z - c.z).length() < 260.0:
		return [{"pos": c, "dim": 0, "label": "The Proving Ring", "kind": "activity", "icon": "ring", "priority": 0}]
	return []


func tracker() -> Array:
	var st := state()
	if not bool(st.get("running", false)):
		return []
	var line := ""
	match String(st.get("stage", "")):
		"countdown":
			line = "First wave in %d s — stay inside the stones" % ceili(float(st.get("next_in", 0.0)))
		"break":
			line = "Wave %d cleared — next in %d s" % [int(st["wave"]), ceili(float(st.get("next_in", 0.0)))]
		"fight":
			line = "Wave %d — %d left" % [int(st["wave"]), int(st.get("left", 0))]
	var board: Array = d.shared.get("leaderboard", [])
	var best := "Best: %d waves" % int(board[0]["waves"]) if not board.is_empty() else "No honours carved yet"
	return [{"title": "The Proving Ring", "lines": PackedStringArray([line, best]), "kind": "event"}]


func honours_text() -> String:
	var board: Array = d.shared.get("leaderboard", [])
	if board.is_empty():
		return "The honours stone is blank. Sound the horn and carve your name."
	var lines := PackedStringArray(["HONOURS OF THE RING"])
	for i in board.size():
		var e: Dictionary = board[i]
		lines.append("%d.  %s — %d waves (day %d)" % [i + 1, e["names"], int(e["waves"]), int(e["day"])])
	return "\n".join(lines)
