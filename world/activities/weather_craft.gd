class_name WeatherCraft
extends RefCounted
## Using the weather. Four craftable (and findable) charms call the sky:
##   Storm Horn   - calls a thunderstorm; for 90 s lightning seeks out monsters
##                  around you (one strike every few seconds).
##   Sunstone     - burns the clouds away; for 60 s sunlight sears the undead
##                  near you (skeletons, ghouls, shades, the drowned).
##   Fog Lantern  - rolls in a fog; for 90 s monsters near you barely notice
##                  you (sneak past, pick your fights).
##   Frost Totem  - calls snow and a biting cold; for 60 s monsters near where
##                  you raised it move at half speed.
## And the weather itself matters: in rain and storms fire creatures (imps,
## fire elementals, hellhounds) sputter and lose health.
##
## Charms are consumables with a "buff" (the hotbar "use" drinks them, no
## player code needed): the local director notices the buff and asks the
## server, which changes the weather through Weather.request() (falls back to
## a synced state change while that API is not available) and runs the effect.

const CHARMS := {
	"storm_call": {"weather": "storm", "seconds": 150.0, "effect": 90.0, "title": "THE STORM ANSWERS", "sub": "Lightning seeks out the monsters around you."},
	"sun_call": {"weather": "clear", "seconds": 240.0, "effect": 60.0, "title": "THE CLOUDS BURN AWAY", "sub": "Sunlight sears the undead near you."},
	"fog_call": {"weather": "fog", "seconds": 180.0, "effect": 90.0, "title": "FOG ROLLS IN", "sub": "Monsters near you can barely see you."},
	"frost_call": {"weather": "snow", "seconds": 180.0, "effect": 60.0, "title": "A BITING COLD", "sub": "Monsters around the totem are slowed."},
}
const UNDEAD := ["skeleton", "archer", "ghoul", "shade", "drowned"]
const FIRE_KINDS := ["imp", "fire_elemental", "hellhound"]

var d: ActivityDirector
var _seen := {}          # local: buff -> end time already acted on
var _effects: Array = [] # server: [{kind, peer, until, pos, t}]
var _modded := {}        # server: entity id -> original stats (fog/frost)
var _rain_t := 0.0


func _init(director: ActivityDirector) -> void:
	d = director


# --- Client: notice a charm being used --------------------------------------------------

func local_tick() -> void:
	var p := d.gw().local_player
	if p == null:
		return
	var buffs: Dictionary = p.inventory.buffs
	for b: String in CHARMS:
		var end := float(buffs.get(b, 0.0))
		if end > Time.get_ticks_msec() / 1000.0 and float(_seen.get(b, -1.0)) != end:
			_seen[b] = end
			d.request("charm", {"kind": b})


# --- Server -----------------------------------------------------------------------------

func server_use(p: Player, kind: String) -> void:
	if not CHARMS.has(kind) or p.dimension == 1:
		return
	var c: Dictionary = CHARMS[kind]
	request_weather(d.gw(), String(c["weather"]), float(c["seconds"]), p.peer_id)
	_effects.append({"kind": kind, "peer": p.peer_id, "until": _now() + float(c["effect"]), "pos": p.global_position, "t": 0.0})
	d.tell(p.peer_id, "%s — %s" % [String(c["title"]).capitalize(), c["sub"]], "quest")
	d.fx("burst", {"pos": p.global_position + Vector3(0, 1.5, 0), "color": _colour(kind), "dim": p.dimension})


static func _colour(kind: String) -> Color:
	match kind:
		"storm_call":
			return Color(0.6, 0.7, 1.0)
		"sun_call":
			return Color(1.0, 0.85, 0.4)
		"fog_call":
			return Color(0.75, 0.8, 0.85)
	return Color(0.6, 0.9, 1.0)


## Ask the sky for `state` for `seconds` (the rendering owner's Weather.request
## when present; otherwise a synced state change that the normal weather
## cycle replaces later).
static func request_weather(w: GameWorld, state: String, seconds: float, peer := 0) -> void:
	var wx: Object = w.weather
	if wx == null:
		return
	if wx.has_method("request"):
		wx.call("request", state, seconds, peer)
		return
	var s := "rain" if state == "snow" else state
	if wx.has_method("sync_state"):
		wx.call("sync_state", s)
		if "_next_change" in wx:
			wx.set("_next_change", seconds)
		if w.replicator != null and w.sky != null:
			w.replicator.broadcast_clock(w.sky.time_of_day, w.sky.day, s)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func server_tick(dt: float) -> void:
	var w := d.gw()
	var now := _now()
	for i in range(_effects.size() - 1, -1, -1):
		var e: Dictionary = _effects[i]
		if now > float(e["until"]):
			_effects.remove_at(i)
			continue
		e["t"] = float(e["t"]) - dt
		var p := d.player_of(int(e["peer"]))
		var centre: Vector3 = e["pos"] if e["kind"] == "frost_call" or p == null else p.global_position
		match String(e["kind"]):
			"storm_call":
				if float(e["t"]) <= 0.0:
					e["t"] = 2.5
					_strike(w, centre, int(e["peer"]))
			"sun_call":
				if float(e["t"]) <= 0.0:
					e["t"] = 1.0
					for m in w.entities_near(centre, 30.0, 0, Entity.Team.MONSTERS):
						if m.kind in UNDEAD:
							w.damage(m, 6.0, Replicator.player_net_id(int(e["peer"])), "fire")
							m.burning = maxf(m.burning, 1.5)
			"fog_call":
				for m in w.entities_near(centre, 40.0, 0, Entity.Team.MONSTERS):
					_modify(m, "aggro", 0.35, float(e["until"]))
			"frost_call":
				for m in w.entities_near(centre, 18.0, 0, Entity.Team.MONSTERS):
					_modify(m, "speed", 0.5, float(e["until"]))
					_modify(m, "chase", 0.5, float(e["until"]))
	_restore(now)
	_rain_t -= dt
	if _rain_t <= 0.0:
		_rain_t = 1.0
		_rain_hurts_fire(w)


func _strike(w: GameWorld, centre: Vector3, peer: int) -> void:
	var best: Entity = null
	var best_d := 30.0
	for m in w.entities_near(centre, 30.0, 0, Entity.Team.MONSTERS):
		if m.dead or (m.has_method("is_boss") and m.call("is_boss")):
			continue
		var dd := m.global_position.distance_to(centre)
		if dd < best_d and dd > 2.0:
			best_d = dd
			best = m
	if best == null:
		return
	w.replicator.broadcast_lightning(best.global_position, 0)
	w.damage(best, 45.0, Replicator.player_net_id(peer), "hit")
	best.burning = maxf(best.burning, 2.0)


## Temporarily scales one stat of a monster (restored when the effect ends).
func _modify(m: Entity, stat: String, factor: float, until: float) -> void:
	if not ("stats" in m):
		return
	var key := "%d:%s" % [m.net_id, stat]
	if _modded.has(key):
		_modded[key][1] = maxf(float(_modded[key][1]), until)
		return
	var st: Dictionary = (m.get("stats") as Dictionary).duplicate()
	if not st.has(stat):
		return
	_modded[key] = [float(st[stat]), until, m.net_id, stat]
	st[stat] = float(st[stat]) * factor
	m.set("stats", st)


func _restore(now: float) -> void:
	var w := d.gw()
	for key: String in _modded.keys():
		var rec: Array = _modded[key]
		if now < float(rec[1]):
			continue
		_modded.erase(key)
		var m := w.entity(int(rec[2]))
		if m != null and "stats" in m:
			var st: Dictionary = (m.get("stats") as Dictionary).duplicate()
			st[String(rec[3])] = rec[0]
			m.set("stats", st)


## Rain and storms douse fire creatures on the surface.
func _rain_hurts_fire(w: GameWorld) -> void:
	if w.weather == null or not (w.weather.state_name() in ["rain", "storm"]):
		return
	for p in w.players_in(0):
		for m in w.entities_near(p.global_position, 60.0, 0, Entity.Team.MONSTERS):
			if m.kind in FIRE_KINDS and not m.dead:
				var g := w.gen_for(0).surface_height(int(m.global_position.x), int(m.global_position.z))
				if m.global_position.y > g - 4.0:
					w.damage(m, 3.0, 0, "hit")
					m.burning = 0.0


func active_for(peer: int) -> Array:
	var out: Array = []
	for e: Dictionary in _effects:
		if int(e["peer"]) == peer:
			out.append(e["kind"])
	return out


## Charms you have going (for the quest tracker).
func tracker() -> Array:
	var p := d.gw().local_player
	if p == null:
		return []
	var out: Array = []
	var now := Time.get_ticks_msec() / 1000.0
	for b: String in CHARMS:
		var left := float(p.inventory.buffs.get(b, 0.0)) - now
		if left > 0.0:
			var c: Dictionary = CHARMS[b]
			out.append({"title": String(c["title"]).capitalize(), "lines": PackedStringArray(["%s (%d s)" % [c["sub"], ceili(left)]]), "kind": "event"})
	return out
