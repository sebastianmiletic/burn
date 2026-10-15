class_name QuestMarkers
extends RefCounted
## Where each active quest wants the player to go next, and every other map
## point of interest the quest log publishes (activities, events), for the
## minimap, world map, journal and on-screen tracker.
##
## `QuestLog.markers()` (when present) returns Dictionaries:
##   {pos: Vector3, dim, label, kind ("main"/"side"/"turn_in"/"activity"),
##    icon ("treasure"/"bounty"/"star"/"raid"/"ring"/"hart"/...), radius, priority, id}
## (`id` is the quest id for quest markers). Quests without a published marker
## (e.g. untracked ones) get one derived from their first unfinished
## objective: reach / interact@location / boss / talk(role) / dimension, or
## the quest giver when ready to hand in.

static var _cache := {}
static var _points: Array = []
static var _cache_frame := -1


## quest id -> {"quest_id", "pos": Vector3, "dim": int, "text": String, "kind"}
static func all(world: Object) -> Dictionary:
	_refresh(world)
	return _cache


## Every marker to draw on a map: quest targets (tracked or not, `tracked`
## says which) and activity / event points. Normalised Dictionaries:
## {pos, dim, text, kind, icon, radius, priority, quest_id, tracked}.
static func points(world: Object) -> Array:
	_refresh(world)
	return _points


static func _refresh(world: Object) -> void:
	var frame := Engine.get_process_frames()
	if frame == _cache_frame:
		return
	_cache_frame = frame
	_cache = {}
	_points = []
	if world == null or not is_instance_valid(world):
		return
	var q: Variant = world.get("quests")
	if not (q is Object):
		return
	var tracked := {}
	var tr: Variant = UiContext.call_on(q, "tracked", [], [])
	if tr is Array:
		for quest: Dictionary in tr:
			tracked[str(quest.get("id", ""))] = true
	var provided: Variant = UiContext.call_on(q, "markers", [], null)
	if provided is Array:
		for m: Variant in provided:
			if not (m is Dictionary):
				continue
			var d: Dictionary = m
			var pos: Variant = d.get("pos", d.get("position", null))
			if not (pos is Vector3):
				continue
			var kind := str(d.get("kind", ""))
			var id := str(d.get("quest_id", d.get("quest", d.get("id", ""))))
			var is_quest := kind in ["main", "side", "turn_in", ""] and id != ""
			var pt := {"pos": pos, "dim": int(d.get("dim", d.get("dimension", 0))), "text": str(d.get("text", d.get("label", ""))),
				"kind": kind if kind != "" else "main", "icon": str(d.get("icon", "")), "radius": float(d.get("radius", 0.0)),
				"priority": float(d.get("priority", 1.0)), "quest_id": id if is_quest else "", "tracked": is_quest and tracked.has(id) or not is_quest}
			_points.append(pt)
			if is_quest and not _cache.has(id):
				_cache[id] = {"quest_id": id, "pos": pos, "dim": pt["dim"], "text": pt["text"], "kind": pt["kind"]}
	var active: Variant = UiContext.call_on(q, "active", [], [])
	if active is Array:
		for quest: Dictionary in active:
			var id := str(quest.get("id", ""))
			if _cache.has(id):
				continue
			var target := _target(world, quest)
			if target.is_empty():
				continue
			target["quest_id"] = id
			target["kind"] = "turn_in" if quest.get("ready", false) else ("main" if quest.get("main", false) else "side")
			_cache[id] = target
			_points.append({"pos": target["pos"], "dim": target["dim"], "text": str(quest.get("title", "")) + " — " + str(target.get("text", "")),
				"kind": target["kind"], "icon": "", "radius": 0.0, "priority": 1.0, "quest_id": id, "tracked": tracked.has(id)})


static func of(world: Object, quest_id: String) -> Dictionary:
	return all(world).get(quest_id, {})


static func _target(world: Object, quest: Dictionary) -> Dictionary:
	if quest.get("ready", false):
		var giver := String(QuestDB.any(str(quest.get("id", ""))).get("giver", ""))
		var t := _giver_target(world, giver)
		if not t.is_empty():
			t["text"] = "Return to " + str(quest.get("turn_in", "the quest giver"))
			return t
	for o: Dictionary in quest.get("objectives", []):
		if o.get("done", false):
			continue
		var key := str(o.get("key", ""))
		var text := str(o.get("text", ""))
		match str(o.get("type", "")):
			"reach":
				return _loc_target(world, StringName(key), text)
			"interact":
				return _loc_target(world, StringName(key.get_slice("@", 1)), text)
			"boss":
				var loc := _boss_location(world, key)
				if loc != null:
					return {"pos": loc.get("center"), "dim": int(loc.get("dimension")), "text": text}
			"talk":
				var t := _giver_target(world, key)
				if not t.is_empty():
					t["text"] = text
					return t
			"dimension":
				var loc: Object = _find_location(world, &"gates_of_hades") if key == "1" else _portal_location(world)
				if loc != null:
					return {"pos": loc.get("center"), "dim": int(loc.get("dimension")), "text": text}
		# Objectives without a place (mine, collect, kill...) have no marker,
		# but a later objective with a place should not show before them.
		return {}
	return {}


static func _loc_target(world: Object, id: StringName, text: String) -> Dictionary:
	var loc := _find_location(world, id)
	if loc == null:
		return {}
	return {"pos": loc.get("center"), "dim": int(loc.get("dimension")), "text": text}


static func _find_location(world: Object, id: StringName) -> Object:
	var l: Variant = UiContext.call_on(world, "location_by_id", [id], null)
	if l is Object:
		return l
	for dim in [0, 1, 2]:
		var locs: Variant = UiContext.call_on(world, "locations", [dim], [])
		if locs is Array:
			for loc: Object in locs:
				if loc != null and loc.get("id") == id:
					return loc
	return null


static func _boss_location(world: Object, kind: String) -> Object:
	for dim in [0, 1, 2]:
		var locs: Variant = UiContext.call_on(world, "locations", [dim], [])
		if locs is Array:
			for loc: Object in locs:
				if loc != null and MapIcons.boss_of(loc) == kind:
					return loc
	return null


static func _portal_location(world: Object) -> Object:
	var home := _find_location(world, &"emberfall")
	if home != null:
		return home
	return null


## An NPC role ("elder", "blacksmith") or "villager@<village id>".
static func _giver_target(world: Object, giver: String) -> Dictionary:
	if giver == "":
		return {}
	if giver.begins_with("villager@"):
		var loc := _find_location(world, StringName(giver.trim_prefix("villager@")))
		return {} if loc == null else {"pos": loc.get("center"), "dim": int(loc.get("dimension")), "text": ""}
	var best: Dictionary = {}
	var locs: Variant = UiContext.call_on(world, "locations", [0], [])
	if locs is Array:
		for loc: Object in locs:
			if loc == null:
				continue
			var spawns: Variant = loc.get("spawns")
			if not (spawns is Array):
				continue
			for s: Dictionary in spawns:
				if s.get("type", "") == "npc" and str(s.get("role", "")) == giver:
					var t := {"pos": s.get("pos", loc.get("center")), "dim": int(loc.get("dimension")), "text": ""}
					if loc.get("id") == &"emberfall":
						return t
					if best.is_empty():
						best = t
	return best


# --- Helpers for UI text -------------------------------------------------------------

## "312 m" / "1.4 km".
static func distance_text(metres: float) -> String:
	if metres >= 1000.0:
		return "%.1f km" % (metres / 1000.0)
	return "%d m" % int(roundf(metres / 5.0) * 5.0)


## "north-east" etc. for a world-space offset (north is -z).
static func compass(offset: Vector3) -> String:
	if Vector2(offset.x, offset.z).length() < 1.0:
		return "here"
	var a := atan2(offset.x, -offset.z)
	var names := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	return names[posmod(int(roundf(a / (PI / 4.0))), 8)]
