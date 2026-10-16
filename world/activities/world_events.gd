class_name WorldEvents
extends RefCounted
## Things that happen to the world, server-run, one at a time:
##
##  Starfall (nights): a star streaks down 35–75 m from someone on the surface.
##    The impact blasts a crater lined with star-ore (iron, silver, gold, frost
##    crystal, amethyst, mithril, set in basalt) over a starmetal core. Dig to
##    the core, let it cool, pry it out with a pickaxe; the first to do so gets
##    the starmetal (the Starfall Pickaxe and Blade need it). Ember guardians
##    crawl out of the crater after a while. The core is gone at dawn.
##  Raid (dusk): while you are in a village, raiders attack in three waves from
##    the fields. Villagers shelter indoors and the guards fight beside you.
##    Hold the village to be paid by its chief: gold, XP, a treasure map, a potion.
##  The Golden Hart (days): a gilded stag is sighted nearby. It bolts when you
##    come close; bring it down within two minutes for a gilded idol, coins, a
##    legendary pelt and gold.
##
## State for the HUD is in `shared["event"]`.

const RAIDERS := {
	"emberfall": ["skeleton", "ghoul"], "ashford": ["skeleton", "archer"], "thornwick": ["ghoul", "wolf"],
	"frosthold": ["frost_wolf", "skeleton"], "mirewatch": ["ghoul", "skeleton"], "cinderreach": ["skeleton", "scorpion"],
}
const CAPTAINS := {"emberfall": "troll", "ashford": "skeleton", "thornwick": "dire_wolf", "frosthold": "troll", "mirewatch": "bog_lurker", "cinderreach": "troll"}
const STAR_ORE := [[Blocks.BASALT, 34], [Blocks.IRON_ORE, 20], [Blocks.SILVER_ORE, 12], [Blocks.GOLD_ORE, 12],
		[Blocks.CRYSTAL, 8], [Blocks.AMETHYST, 6], [Blocks.MITHRIL_ORE, 8]]
const RAID_WAVES := 3
const RAID_TIMEOUT := 330.0

var d: ActivityDirector
var _wait := -1.0           # seconds until a scheduled starfall
var _core_id := 0
var _guardians: Array[int] = []
var _raiders: Array[int] = []
var _check := 0.0
var _absent := 0.0
var rng := RandomNumberGenerator.new()


func _init(director: ActivityDirector) -> void:
	d = director
	rng.randomize()


func event() -> Dictionary:
	return d.shared.get("event", {})


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func recent_meteor() -> Dictionary:
	var m: Variant = d.shared.get("last_meteor", {})
	if m is Dictionary and not (m as Dictionary).is_empty() and d.gw().day() - int((m as Dictionary).get("day", -99)) <= 1:
		return m
	return {}


# --- Server -------------------------------------------------------------------------------

func server_tick(dt: float) -> void:
	var ev := event()
	if ev.is_empty():
		_maybe_start(dt)
		return
	match String(ev.get("kind", "")):
		"meteor":
			_tick_meteor(ev)
		"raid":
			_tick_raid(ev, dt)
		"hart":
			_tick_hart(ev)


func _maybe_start(dt: float) -> void:
	var w := d.gw()
	var h := w.time_of_day()
	var day := w.day()
	if w.active_boss() != null:
		return
	# Starfall: one roll per night, at a random moment.
	if h >= 21.0 or h < 4.0:
		var night := day if h >= 21.0 else day - 1
		if int(d.world.get("meteor_night", -1)) != night:
			d.world["meteor_night"] = night
			var since := night - int(d.world.get("meteor_last_night", -10))
			_wait = rng.randf_range(15.0, 160.0) if (rng.randf() < 0.6 or since >= 2) else -1.0
		if _wait >= 0.0:
			_wait -= dt
			if _wait < 0.0:
				var surface := _surface_players()
				if not surface.is_empty():
					start_meteor(surface[rng.randi() % surface.size()].global_position)
		return
	_wait = -1.0
	# The Golden Hart: one chance a day, mid-morning to afternoon.
	if h >= 8.0 and h < 16.0 and int(d.world.get("hart_day", -1)) != day:
		d.world["hart_day"] = day
		d.world["hart_wait"] = rng.randf_range(20.0, 200.0) if rng.randf() < 0.7 else -1.0
	if h >= 8.0 and h < 16.0 and float(d.world.get("hart_wait", -1.0)) >= 0.0:
		d.world["hart_wait"] = float(d.world["hart_wait"]) - dt
		if float(d.world["hart_wait"]) < 0.0:
			d.world["hart_wait"] = -1.0
			var surface := _surface_players()
			if not surface.is_empty():
				start_hart(surface[rng.randi() % surface.size()].global_position)
		return
	# Raids at dusk, on a village someone is standing in.
	if h < 18.0 or h >= 21.0:
		return
	_check -= dt
	if _check > 0.0:
		return
	_check = 5.0
	if not _raids_unlocked():
		return
	if int(d.world.get("raid_day", -10)) >= day:
		return
	for loc in w.locations(0):
		if loc.kind != Location.Kind.VILLAGE:
			continue
		if day - int(d.world.get("raid_day_" + String(loc.id), -10)) < 2:
			continue
		for p in w.players_in(0):
			if not p.dead and Vector2(p.global_position.x - loc.center.x, p.global_position.z - loc.center.z).length() < loc.radius + 6.0:
				if rng.randf() < 0.03:
					start_raid(loc)
				return


func _raids_unlocked() -> bool:
	var w := d.gw()
	return w.quests.is_completed("iron_in_the_deep") or w.day() >= 3


func _surface_players() -> Array[Player]:
	var w := d.gw()
	var out: Array[Player] = []
	for p in w.players_in(0):
		var g := w.gen_for(0).surface_height(int(p.global_position.x), int(p.global_position.z))
		if not p.dead and p.global_position.y > g - 5.0:
			out.append(p)
	return out


## Server: a star falls near `near` (tests and the night roll call this).
func start_meteor(near: Vector3) -> bool:
	var w := d.gw()
	var site := _meteor_site(near)
	if site == Vector3.INF:
		return false
	var dir := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
	var eta := 5.5
	d.set_shared("event", {"kind": "meteor", "pos": site, "stage": "falling", "cool_left": 0.0, "impact_at_local": _now() + eta})
	d.fx("meteor", {"from": site + dir * 120.0 + Vector3(0, 170, 0), "to": site + Vector3(0, 0.4, 0), "eta": eta, "dim": 0})
	d.announce("A STAR FALLS", "It came down near %s. Claim its starmetal before anyone else!" % _place_name(site), Color(0.65, 0.75, 1.0), "quest")
	d.world["meteor_last_night"] = int(d.world.get("meteor_night", w.day()))
	w.get_tree().create_timer(eta).timeout.connect(_impact.bind(site))
	return true


func _place_name(p: Vector3) -> String:
	var w := d.gw()
	var best := ""
	var bd := 400.0
	for loc in w.locations(0):
		var dd := Vector2(loc.center.x - p.x, loc.center.z - p.z).length()
		if dd < bd and loc.half_height <= 0.0:
			bd = dd
			best = loc.name
	return best if best != "" else GameWorld.biome_name(w, p, 0)


func _meteor_site(near: Vector3) -> Vector3:
	var w := d.gw()
	var vw := w.world_for(0)
	var gen := w.gen_for(0)
	# Random probes preserve varied sightings. If they all hit the same
	# excluded village/lake sector, cover the nearby rings before giving up.
	# Both stages still require loaded, dry, smooth, unobstructed ground.
	for attempt in 72:
		var a: float
		var r: float
		if attempt < 24:
			a = rng.randf() * TAU
			r = rng.randf_range(35.0, 75.0) if attempt < 16 else rng.randf_range(18.0, 40.0)
		else:
			a = TAU * float((attempt - 24) % 16) / 16.0
			r = [24.0, 45.0, 65.0][(attempt - 24) / 16]
		var x := near.x + cos(a) * r
		var z := near.z + sin(a) * r
		if not TreasureHunt.spot_ok(gen, w.locations(0), x, z):
			continue
		# Query just above the candidate's surface, not 60 m above the
		# player. Unloaded upper chunks read as solid; a high ray origin
		# incorrectly rejects every candidate on a freshly streamed column.
		var top := float(gen.surface_height(int(x), int(z))) + 5.0
		if vw == null or not vw.is_area_loaded(Vector3(x, top, z)):
			continue
		var g := vw.ground_below(x, top, z, 40.0)
		if absf(g) > 1e6:
			continue
		var b := vw.get_block(Vector3i(floori(x), floori(g - 0.5), floori(z)))
		if b <= 0 or Blocks.is_liquid(b) or not Blocks.is_smooth(b):
			continue
		return Vector3(x, g, z)
	return Vector3.INF


func _impact(site: Vector3) -> void:
	var ev := event()
	if String(ev.get("kind", "")) != "meteor":
		return
	var w := d.gw()
	d.sculpt(crater_changes(site, rng.randi()), 0)
	w.shake(1.0, site, 0)
	# Anyone standing in the blast is thrown clear.
	for e in w.entities_near(site, 6.0, 0):
		if e is Player:
			w.knockback(e, (e.global_position - site).normalized() * 9.0 + Vector3(0, 7, 0))
			w.damage(e, 12.0, 0, "fire")
	var core := w.spawn_entity("act_meteor", site + Vector3(0, -2.75 - 0.55, 0), 0, {"cool_at": _now() + 25.0, "seed": rng.randi()})
	_core_id = core.net_id if core != null else 0
	ev["stage"] = "cooling"
	ev["guard_at_local"] = _now() + 16.0
	ev["cool_at_local"] = _now() + 25.0
	d.shared["last_meteor"] = {"pos": site, "day": w.day()}
	d.set_shared("event", ev)


## Voxel edits for a crater at `site` (ground point): a bowl, a raised rim of
## ash and basalt, and a lens of star-ore over the core's hollow.
static func crater_changes(site: Vector3, seed_value: int) -> PackedInt32Array:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var out := PackedInt32Array()
	var bowl_c := site + Vector3(0, 2.2, 0)
	const BOWL_R := 3.6
	var core_c := site + Vector3(0, -2.75, 0)
	var total := 0
	for row: Array in STAR_ORE:
		total += int(row[1])
	var c := Vector3i(site.floor())
	for dz in range(-6, 7):
		for dx in range(-6, 7):
			for dy in range(-5, 3):
				var cell := c + Vector3i(dx, dy, dz)
				var p := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
				var hd := Vector2(p.x - site.x, p.z - site.z).length()
				var in_bowl := p.distance_to(bowl_c)
				var in_core := p.distance_to(core_c)
				if in_core < 0.95:
					out.append_array([cell.x, cell.y, cell.z, Blocks.AIR, 0])
				elif in_bowl < BOWL_R:
					out.append_array([cell.x, cell.y, cell.z, Blocks.AIR, 0])
				elif in_core < 1.55 and p.y < site.y - 0.6:
					# Fused ash right around the core: any pickaxe digs through to it.
					out.append_array([cell.x, cell.y, cell.z, Blocks.ASH if r.randf() < 0.55 else Blocks.GRAVEL, 255])
				elif in_core < 2.5 and p.y < site.y - 0.6:
					var pick := r.randi() % total
					var block := Blocks.BASALT
					for row: Array in STAR_ORE:
						pick -= int(row[1])
						if pick < 0:
							block = int(row[0])
							break
					out.append_array([cell.x, cell.y, cell.z, block, 255])
				elif hd > 2.6 and hd < 4.6 and p.y > site.y - 0.5 and p.y < site.y + 0.9:
					# Thrown-up rim.
					var k := 1.0 - absf(hd - 3.6) / 1.0
					var dens := int(clampf(140.0 + 115.0 * k - (p.y - site.y) * 120.0, 0.0, 255.0))
					if dens >= 128:
						out.append_array([cell.x, cell.y, cell.z, Blocks.ASH if r.randf() < 0.6 else Blocks.BASALT, dens])
	return out


func _tick_meteor(ev: Dictionary) -> void:
	var w := d.gw()
	var now := _now()
	if ev.get("stage") == "cooling":
		ev["cool_left"] = maxf(0.0, float(ev.get("cool_at_local", now)) - now)
		if ev.has("guard_at_local") and now >= float(ev["guard_at_local"]):
			ev.erase("guard_at_local")
			_spawn_guardians(ev["pos"])
		var core := w.entity(_core_id)
		var h := w.time_of_day()
		if core == null or (h >= 6.0 and h < 18.0):
			if core != null:
				w.despawn_entity(core)
			_end_meteor()
			return
		d.mark_dirty()


func _spawn_guardians(site: Vector3) -> void:
	var w := d.gw()
	var best := 0
	for p in w.players_in(0):
		if p.global_position.distance_to(site) < 120.0:
			best = maxi(best, p.rank)
	var kind := "fire_elemental" if best >= 4 else ("imp" if best >= 2 else "skeleton")
	var n := 2 if best < 6 else 3
	for i in n:
		var a := TAU * float(i) / n + rng.randf()
		var at := site + Vector3(cos(a) * 3.0, 0.8, sin(a) * 3.0)
		var e := w.spawn_entity(kind, at, 0, {})
		if e != null:
			e.display_name = "Star-touched " + e.display_name
			e.burning = 0.0
			_guardians.append(e.net_id)
	d.announce("SOMETHING CRAWLS FROM THE CRATER", "", Color(1.0, 0.5, 0.25), "", 0)


func on_core_taken(p: Player, count: int) -> void:
	d.tell(p.peer_id, "You pry the starmetal core loose! +%d starmetal. A smith can forge it." % count, "quest")
	var ev := event()
	if String(ev.get("kind", "")) == "meteor":
		ev["stage"] = "taken"
		d.set_shared("event", ev)
		d.gw().get_tree().create_timer(8.0).timeout.connect(_end_meteor)


func _end_meteor() -> void:
	if String(event().get("kind", "")) != "meteor":
		return
	var w := d.gw()
	for id in _guardians:
		var e := w.entity(id)
		if e != null and not e.dead and w.nearest_player(e.global_position, 0, 50.0) == null:
			w.despawn_entity(e)
	_guardians.clear()
	_core_id = 0
	d.set_shared("event", {})


# --- The Golden Hart ------------------------------------------------------------------------

const HART_SECONDS := 120.0
var _hart_id := 0


## Server: a golden hart appears 35–60 m from `near`.
func start_hart(near: Vector3) -> bool:
	var w := d.gw()
	var site := _meteor_site(near)
	if site == Vector3.INF:
		return false
	var e := w.spawn_entity("stag", site + Vector3(0, 0.3, 0), 0, {})
	if e == null:
		return false
	e.max_health *= 3.0
	e.health = e.max_health
	e.display_name = "The Golden Hart"
	if "stats" in e:
		var st: Dictionary = (e.get("stats") as Dictionary).duplicate()
		st["run"] = 6.8
		st["alarm"] = 22.0
		e.set("stats", st)
	w.spawn_entity("act_elite", e.global_position, 0, {"target": e.net_id, "name": "The Golden Hart", "size": 1.2, "max_health": e.max_health})
	_hart_id = e.net_id
	d.set_shared("event", {"kind": "hart", "pos": site, "left": HART_SECONDS, "until_local": _now() + HART_SECONDS})
	d.announce("A GOLDEN HART", "Sighted near %s. Bring it down before it escapes!" % _place_name(site), Color(1.0, 0.85, 0.4), "quest")
	return true


func _tick_hart(ev: Dictionary) -> void:
	var w := d.gw()
	var hart := w.entity(_hart_id)
	if hart != null and hart.dead:
		for p in w.players_near_credit(hart):
			w.replicator.give_gold_to(p.peer_id, 60)
			w.replicator.give_item_to(p.peer_id, "gilded_idol", 1)
			w.replicator.give_item_to(p.peer_id, "ancient_coin", 6)
			w.replicator.give_item_to(p.peer_id, "trophy_pelt", 1)
			d.tell(p.peer_id, "The Golden Hart falls: a gilded idol, old coins and a shining pelt.", "quest")
		d.fx("burst", {"pos": hart.center(), "color": Color(1.0, 0.85, 0.4), "dim": 0})
		_hart_id = 0
		d.set_shared("event", {})
		return
	var left := float(ev["until_local"]) - _now()
	if hart == null or left <= 0.0:
		if hart != null:
			w.despawn_entity(hart)
			d.announce("THE HART ESCAPED", "It vanished into the trees.", Color(0.8, 0.75, 0.6), "", 0)
		_hart_id = 0
		d.set_shared("event", {})
		return
	ev["pos"] = hart.global_position
	ev["left"] = left
	d.mark_dirty()


# --- Raids ----------------------------------------------------------------------------------

## Server: raiders come for `loc` (a village).
func start_raid(loc: Location) -> void:
	var w := d.gw()
	d.world["raid_day"] = w.day()
	d.world["raid_day_" + String(loc.id)] = w.day()
	d.set_shared("event", {"kind": "raid", "village": String(loc.id), "name": loc.name, "pos": loc.center, "stage": "warning",
		"wave": 0, "waves": RAID_WAVES, "left": 0, "next_in": 14.0, "started_local": _now()})
	d.announce("RAID ON %s" % loc.name.to_upper(), "Raiders are coming out of the dusk. Hold the village for three waves!", Color(1.0, 0.4, 0.3), "quest")
	d.fx("horn", {"pos": loc.center + Vector3(0, 3, 0), "dim": 0})
	_absent = 0.0


func _tick_raid(ev: Dictionary, dt: float) -> void:
	var w := d.gw()
	var center: Vector3 = ev["pos"]
	var someone := w.nearest_player(center, 0, 100.0) != null
	_absent = 0.0 if someone else _absent + dt
	if _absent > 30.0 or _now() - float(ev.get("started_local", _now())) > RAID_TIMEOUT:
		_end_raid(ev, false)
		return
	var alive := 0
	for id in _raiders:
		var e := w.entity(id)
		if e != null and not e.dead:
			alive += 1
	ev["left"] = alive
	match String(ev["stage"]):
		"warning", "lull":
			ev["next_in"] = float(ev["next_in"]) - dt
			if float(ev["next_in"]) <= 0.0:
				ev["wave"] = int(ev["wave"]) + 1
				_spawn_wave(ev)
				ev["stage"] = "fight"
		"fight":
			if alive == 0:
				if int(ev["wave"]) >= int(ev["waves"]):
					_end_raid(ev, true)
					return
				ev["stage"] = "lull"
				ev["next_in"] = 8.0
				d.announce("WAVE %d HELD" % int(ev["wave"]), "More are coming...", Color(1.0, 0.75, 0.4), "", 0)
	d.mark_dirty()


func _spawn_wave(ev: Dictionary) -> void:
	var w := d.gw()
	var vw := w.world_for(0)
	var center: Vector3 = ev["pos"]
	var village := String(ev["village"])
	var kinds: Array = RAIDERS.get(village, ["skeleton", "ghoul"])
	var wave := int(ev["wave"])
	var players := 0
	for p in w.players_in(0):
		if p.global_position.distance_to(center) < 90.0:
			players += 1
	var count := 2 + wave + maxi(0, players - 1) * 2
	_raiders.clear()
	var side := rng.randf() * TAU
	for i in count:
		var a := side + (PI if i % 3 == 2 else 0.0) + rng.randf_range(-0.35, 0.35)
		var kind: String = kinds[i % kinds.size()]
		var e := _spawn_raider(vw, center, a, kind)
		if e != null:
			_raiders.append(e.net_id)
	if wave >= int(ev["waves"]):
		var cap := _spawn_raider(vw, center, side, String(CAPTAINS.get(village, "troll")))
		if cap != null:
			Bounties.apply_elite(cap, 1, "Raid Captain", players, center)
			w.spawn_entity("act_elite", cap.global_position, 0, {"target": cap.net_id, "name": "Raid Captain", "size": 1.3, "max_health": cap.max_health})
			_raiders.append(cap.net_id)
	ev["left"] = _raiders.size()
	d.announce("WAVE %d" % wave, "%d raiders from the %s" % [_raiders.size(), _compass_word(side)], Color(1.0, 0.45, 0.35), "", 0)


static func _compass_word(a: float) -> String:
	# Spawn direction (cos a, sin a) in x/z; north is -z.
	var deg := fposmod(rad_to_deg(atan2(cos(a), -sin(a))), 360.0)
	return ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"][int(round(deg / 45.0)) % 8]


func _spawn_raider(vw: VoxelWorld, center: Vector3, angle: float, kind: String) -> Entity:
	var w := d.gw()
	for attempt in 6:
		var r := rng.randf_range(34.0, 44.0) - attempt * 3.0
		var a := angle + rng.randf_range(-0.2, 0.2)
		var x := center.x + cos(a) * r
		var z := center.z + sin(a) * r
		if vw == null or not vw.is_area_loaded(Vector3(x, center.y, z)):
			continue
		var g := vw.ground_below(x, center.y + 30.0, z, 60.0)
		if absf(g) > 1e6 or g < WorldGen.SEA_LEVEL - 0.5:
			continue
		var e := w.spawn_entity(kind, Vector3(x, g + 0.3, z), 0, {})
		if e == null:
			return null
		if "spawn_point" in e:
			e.set("spawn_point", center + Vector3(rng.randf_range(-5, 5), 0, rng.randf_range(-5, 5)))
		e.set_meta("raider", true)
		return e
	return null


func _end_raid(ev: Dictionary, won: bool) -> void:
	var w := d.gw()
	var center: Vector3 = ev["pos"]
	if won:
		for p in w.players_in(0):
			if p.global_position.distance_to(center) > 75.0:
				continue
			var gold := 60 + 25 * int(ev["waves"])
			w.replicator.give_gold_to(p.peer_id, gold)
			w.replicator.give_xp_to(p.peer_id, 160, "")
			w.replicator.give_item_to(p.peer_id, "treasure_map", 1)
			w.replicator.give_item_to(p.peer_id, "potion_greater", 1)
			d.tell(p.peer_id, "%s thanks you: %d gold, a potion and an old map from the chief's chest." % [ev["name"], gold], "quest")
		d.announce("%s HOLDS" % String(ev["name"]).to_upper(), "The raiders are broken. The chief has paid every defender.", Color(0.6, 1.0, 0.55), "victory", 0)
	else:
		for id in _raiders:
			var e := w.entity(id)
			if e != null and not e.dead:
				w.despawn_entity(e)
		d.announce("THE RAIDERS WITHDRAW", "They slipped away with what they could carry.", Color(0.8, 0.7, 0.6), "", 0)
	_raiders.clear()
	ev["stage"] = "over"
	d.set_shared("event", {})


# --- Client ---------------------------------------------------------------------------------

func markers() -> Array:
	var ev := event()
	if ev.is_empty():
		return []
	var w := d.gw()
	var me := w.local_player.global_position if w.local_player != null else Vector3.ZERO
	match String(ev.get("kind", "")):
		"meteor":
			if ev.get("stage") in ["cooling", "falling"]:
				return [{"pos": ev["pos"], "dim": 0, "label": "Starfall crater", "kind": "activity", "icon": "star", "priority": 4}]
		"raid":
			if me.distance_to(ev["pos"]) < 500.0:
				return [{"pos": ev["pos"], "dim": 0, "label": "Defend " + String(ev["name"]), "kind": "activity", "icon": "raid", "priority": 5}]
		"hart":
			return [{"pos": ev["pos"], "dim": 0, "label": "The Golden Hart", "kind": "activity", "icon": "hart", "priority": 4}]
	return []


func tracker() -> Array:
	var ev := event()
	if ev.is_empty():
		return []
	match String(ev.get("kind", "")):
		"meteor":
			var lines := PackedStringArray()
			match String(ev.get("stage", "")):
				"falling":
					lines.append("Something is falling from the sky!")
				"cooling":
					lines.append("Dig through the star-ore to the core")
					var cl := float(ev.get("cool_left", 0.0))
					lines.append("The core is cooling (%d s)" % ceili(cl) if cl > 0.0 else "Pry out the core with a pickaxe")
				"taken":
					lines.append("The core has been claimed")
			return [{"title": "Starfall", "lines": lines, "kind": "event"}]
		"raid":
			var lines2 := PackedStringArray()
			match String(ev.get("stage", "")):
				"warning":
					lines2.append("Raiders approaching (%d s)" % ceili(float(ev.get("next_in", 0.0))))
				"lull":
					lines2.append("Wave %d held — next in %d s" % [int(ev["wave"]), ceili(float(ev.get("next_in", 0.0)))])
				"fight":
					lines2.append("Wave %d/%d — %d raiders left" % [int(ev["wave"]), int(ev["waves"]), int(ev.get("left", 0))])
			return [{"title": "Raid on " + String(ev["name"]), "lines": lines2, "kind": "event"}]
		"hart":
			return [{"title": "The Golden Hart", "lines": PackedStringArray(["Bring it down before it escapes (%d s)" % ceili(float(ev.get("left", 0.0)))]), "kind": "event"}]
	return []
