class_name QuestLog
extends RefCounted
## The local player's quests: progress, tracking, completion and rewards.
## Progress comes from `on_event(type, key, amount)`; "collect" and "have"
## objectives are re-evaluated from the inventory. Event objectives count from
## the moment the quest is accepted ("gather" = items picked up, "craft" =
## items made, "place" = stations set down), except "boss" and "reach", which
## also count bosses already slain and places already found in this world
## (`known_bosses` / `known_places`), so doing things early never strands a quest.

signal completed_quest(quest: Dictionary)

var _active := {}       # id -> {"progress": PackedInt32Array, "tracked": bool}
var _completed := {}    # id -> true
var inventory: Inventory
## Per-player activity progress (treasure hunts, bounty renown, personal
## bests). Owned by the ActivityDirector; saved with the quests so it travels
## with the character into other players' worlds.
var activity := {}
## Extra guidance sources (the ActivityDirector): Callable() -> Array of markers.
var marker_providers: Array[Callable] = []
## World facts shared by reference with GameWorld (bosses_defeated: kind ->
## true, discovered: location id -> true). Empty outside a world.
var known_bosses := {}
var known_places := {}


func accept(id: String) -> bool:
	if _active.has(id) or _completed.has(id):
		return false
	var q := QuestDB.any(id)
	if q.is_empty():
		return false
	var progress := PackedInt32Array()
	progress.resize((q["objectives"] as Array).size())
	_active[id] = {"progress": progress, "tracked": true}
	_apply_world_facts(id)
	_refresh_inventory_objectives()
	Events.quest_updated.emit(id)
	Events.notify.emit("New quest: " + String(q["title"]), "quest")
	Audio.play_ui("quest")
	_check_completion()
	return true


## Bosses already slain and places already found count for a new quest.
func _apply_world_facts(id: String) -> void:
	var objs: Array = QuestDB.any(id)["objectives"]
	var progress: PackedInt32Array = _active[id]["progress"]
	for i in objs.size():
		var o: Dictionary = objs[i]
		var key := String(o["key"])
		var known := false
		match String(o["type"]):
			"boss":
				known = known_bosses.has(key)
			"reach":
				known = known_places.has(StringName(key)) or known_places.has(key)
		if known:
			progress[i] = int(o["count"])
	_active[id]["progress"] = progress


## Does an event key satisfy an objective key? Objective keys may list
## alternatives ("axe_stone|spear_stone"); "discover" matches by prefix.
static func key_matches(objective_key: String, type: String, key: String) -> bool:
	for alt in objective_key.split("|"):
		if alt == key or (type == "discover" and key.begins_with(alt)):
			return true
	return false


func is_active(id: String) -> bool:
	return _active.has(id)


func is_completed(id: String) -> bool:
	return _completed.has(id)


func set_tracked(id: String, on: bool) -> void:
	if _active.has(id):
		_active[id]["tracked"] = on
		Events.quest_updated.emit(id)


## Feed a game event to every active quest.
func on_event(type: String, key: String, amount := 1) -> void:
	var touched := false
	for id: String in _active.keys():
		var q := QuestDB.any(id)
		var objs: Array = q["objectives"]
		var progress: PackedInt32Array = _active[id]["progress"]
		for i in objs.size():
			var o: Dictionary = objs[i]
			if o["type"] != type:
				continue
			if not key_matches(String(o["key"]), type, key):
				continue
			if progress[i] < int(o["count"]):
				progress[i] = mini(int(o["count"]), progress[i] + amount)
				touched = true
		_active[id]["progress"] = progress
		if touched:
			Events.quest_updated.emit(id)
			touched = false
	if type == "collect" or type == "have":
		_refresh_inventory_objectives()
	_check_completion()


func _refresh_inventory_objectives() -> void:
	if inventory == null:
		return
	for id: String in _active:
		var q := QuestDB.any(id)
		var objs: Array = q["objectives"]
		var progress: PackedInt32Array = _active[id]["progress"]
		var changed := false
		for i in objs.size():
			var o: Dictionary = objs[i]
			if o["type"] == "collect" or o["type"] == "have":
				var n := 0
				for alt in String(o["key"]).split("|"):
					n += inventory.count_of(alt)
				n = mini(n, int(o["count"]))
				if n != progress[i]:
					progress[i] = n
					changed = true
		_active[id]["progress"] = progress
		if changed:
			Events.quest_updated.emit(id)


func inventory_changed() -> void:
	_refresh_inventory_objectives()
	_check_completion()


## Quests whose objectives are all done but need handing in to their giver.
func ready_to_turn_in(giver: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in _active:
		var q := QuestDB.any(id)
		if q["giver"] == giver and _objectives_done(id):
			out.append(id)
	return out


func _objectives_done(id: String) -> bool:
	var q := QuestDB.any(id)
	var objs: Array = q["objectives"]
	var progress: PackedInt32Array = _active[id]["progress"]
	for i in objs.size():
		if progress[i] < int(objs[i]["count"]):
			return false
	return true


## Quests without a giver to return to complete as soon as objectives are met.
func _check_completion() -> void:
	for id: String in _active.keys():
		if not _active.has(id):
			continue  # finished by a nested completion (accepting a successor)
		var q := QuestDB.any(id)
		if String(q["giver"]) == "" and _objectives_done(id):
			complete(id)
		elif String(q["giver"]) != "" and _objectives_done(id) and not _active[id].get("announced", false):
			_active[id]["announced"] = true
			Events.notify.emit("%s — return to %s" % [q["title"], _giver_label(q["giver"])], "quest")


## A journal entry that is complete the moment it happens (no toast spam,
## no rewards). Returns false if it was already recorded.
func record_lore(id: String) -> bool:
	if _completed.has(id) or QuestDB.any(id).is_empty():
		return false
	_active.erase(id)
	_completed[id] = true
	Events.quest_updated.emit(id)
	return true


func complete(id: String) -> void:
	if not _active.has(id):
		return
	var q := QuestDB.any(id)
	_active.erase(id)
	_completed[id] = true
	completed_quest.emit(q)
	Events.quest_completed.emit(id)
	Events.notify.emit("Quest complete: " + String(q["title"]), "quest")
	var next := String(q.get("next", ""))
	if next != "" and QuestDB.any(next).get("giver", "x") == "":
		accept(next)


static func _giver_label(giver: String) -> String:
	match giver:
		"elder": return "Elder Maren in Emberfall"
		"blacksmith": return "the blacksmith"
	if giver.begins_with("villager@"):
		return "the villagers of " + String(QuestDB.VILLAGE_NAMES.get(giver.trim_prefix("villager@"), "the village"))
	return giver


# --- UI queries ----------------------------------------------------------------

func active() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in _active:
		out.append(_describe(id, false))
	return out


func completed() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in _completed:
		out.append(_describe(id, true))
	return out


func tracked() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in _active:
		if _active[id]["tracked"]:
			out.append(_describe(id, false))
	return out


func completed_ids() -> Array:
	return _completed.keys()


func _describe(id: String, done: bool) -> Dictionary:
	var q := QuestDB.any(id)
	var objs: Array = q["objectives"]
	var progress: PackedInt32Array = PackedInt32Array() if done else _active[id]["progress"]
	var list: Array[Dictionary] = []
	for i in objs.size():
		var target := int(objs[i]["count"])
		var cur := target if done else progress[i]
		list.append({"text": objs[i]["text"], "type": objs[i]["type"], "key": objs[i]["key"], "current": cur, "target": target, "done": cur >= target})
	var rewards := PackedStringArray()
	var r: Dictionary = q["rewards"]
	if r.has("xp"):
		rewards.append("%d XP" % r["xp"])
	if r.has("gold"):
		rewards.append("%d gold" % r["gold"])
	for item: String in r.get("items", {}):
		rewards.append("%s x%d" % [ItemDB.display_name(item), r["items"][item]])
	var ready := not done and _objectives_done(id) and String(q["giver"]) != ""
	var category := QuestDB.category_of(id)
	return {"id": id, "title": q["title"], "description": q["description"], "objectives": list,
		"rewards": ", ".join(rewards), "tracked": (not done) and _active[id]["tracked"], "main": category == "main",
		"category": category, "ready": ready, "turn_in": _giver_label(q["giver"]) if ready else ""}


# --- Save --------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var a := {}
	for id: String in _active:
		a[id] = {"progress": Array(_active[id]["progress"]), "tracked": _active[id]["tracked"]}
	return {"active": a, "completed": _completed.keys(), "activity": activity.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	_active.clear()
	_completed.clear()
	var a: Dictionary = d.get("active", {})
	for id: String in a:
		if QuestDB.any(id).is_empty():
			continue  # a quest that no longer exists in this version
		var progress := PackedInt32Array(a[id]["progress"])
		progress.resize((QuestDB.any(id)["objectives"] as Array).size())  # objectives may have changed
		_active[id] = {"progress": progress, "tracked": a[id]["tracked"]}
	for id: String in d.get("completed", []):
		_completed[id] = true
	var act: Variant = d.get("activity", {})
	activity = (act as Dictionary).duplicate(true) if act is Dictionary else {}
	migrate()


## Re-applies slain bosses and found places to every active quest (after a
## load: older saves could hold a boss quest accepted after its boss died).
func sync_world_facts() -> void:
	for id: String in _active.keys():
		_apply_world_facts(id)
		Events.quest_updated.emit(id)
	_check_completion()


## Starts the first-steps guide unless this character has begun (or skipped) it.
func start_guide() -> void:
	for q: Dictionary in QuestDB.FIRST_STEPS:
		if _active.has(q["id"]) or _completed.has(q["id"]):
			return
	accept(String(QuestDB.FIRST_STEPS[0]["id"]))


## The progression ladder for the journal's Path tab:
## [{title, hint, tier, quest, state: "done"|"current"|"next"|"locked"}].
## Only the current step and the one after it reveal their hints, so the
## ladder guides without spoiling what lies further on.
func path() -> Array:
	var out: Array = []
	var current := -1
	for i in QuestDB.PATH.size():
		var step: Dictionary = QuestDB.PATH[i]
		var state := "locked"
		if _completed.has(String(step["quest"])):
			state = "done"
		elif current < 0:
			current = i
			state = "current"
		elif i == current + 1:
			state = "next"
		var d := step.duplicate()
		d["state"] = state
		d["active"] = _active.has(String(step["quest"]))
		out.append(d)
	return out


## Optional boss contracts for the Path tab: [{id, title, tier, giver,
## state: "done"|"active"|"available"|"locked"}]. Bosses this build lacks are left out.
func optional_path() -> Array:
	var out: Array = []
	for q: Dictionary in QuestDB.OPTIONAL:
		if not QuestDB.boss_available(q):
			continue
		var id: String = q["id"]
		var state := "locked"
		if _completed.has(id):
			state = "done"
		elif _active.has(id):
			state = "active"
		elif String(q.get("requires", "")) == "" or _completed.has(String(q["requires"])):
			state = "available"
		out.append({"id": id, "title": q["title"], "tier": q.get("tier", ""), "giver": _giver_label(String(q["giver"])), "state": state})
	return out


## Keeps saves from older versions moving after quests were added to the
## ladder: a quest inserted before one the player has already reached counts
## as done (no rewards), and the first-steps guide is skipped for characters
## that already have a story under way.
func migrate() -> void:
	var reached := -1
	for i in QuestDB.MAIN.size():
		var id: String = QuestDB.MAIN[i]["id"]
		if _active.has(id) or _completed.has(id):
			reached = i
	for i in reached:
		var id: String = QuestDB.MAIN[i]["id"]
		if not _completed.has(id) and not _active.has(id):
			_completed[id] = true
	var started_guide := false
	for q: Dictionary in QuestDB.FIRST_STEPS:
		if _active.has(q["id"]) or _completed.has(q["id"]):
			started_guide = true
	var story_started := reached > 0 or _completed.has("kindling")
	if not started_guide and story_started:
		for q: Dictionary in QuestDB.FIRST_STEPS:
			_completed[q["id"]] = true


# --- Guidance ------------------------------------------------------------------

## Where to go next, for the compass, the on-screen objective marker, the
## minimap and the map: [{pos: Vector3, dim: int, label: String,
## kind: "main"|"side"|"turn_in"|"activity", id: String, radius: float (optional search circle)}].
## Tracked quests contribute their next objective that has a place (or their
## giver once ready to hand in); activity providers add theirs.
func markers() -> Array:
	# Several widgets ask every frame; recompute a few times a second.
	var now := Time.get_ticks_msec()
	if now - _markers_at < 200 and _markers_at >= 0:
		return _markers_cache
	_markers_at = now
	_markers_cache = _compute_markers()
	return _markers_cache


var _markers_cache: Array = []
var _markers_at := -1


func _compute_markers() -> Array:
	var out: Array = []
	var gw := GameWorld.instance
	if gw != null:
		for id: String in _active:
			if not _active[id]["tracked"]:
				continue
			var q := QuestDB.any(id)
			if q.is_empty():
				continue
			var kind := "main" if QuestDB.category_of(id) == "main" else "side"
			if _objectives_done(id):
				if String(q["giver"]) != "":
					var giver := _giver_marker(gw, String(q["giver"]))
					if not giver.is_empty():
						giver["label"] = "Hand in: " + String(q["title"])
						giver["kind"] = "turn_in"
						giver["id"] = id
						out.append(giver)
				continue
			var objs: Array = q["objectives"]
			var progress: PackedInt32Array = _active[id]["progress"]
			for i in objs.size():
				var o: Dictionary = objs[i]
				if progress[i] >= int(o["count"]):
					continue
				var m := _objective_marker(gw, o)
				if m.is_empty():
					continue
				m["label"] = String(o["text"])
				m["kind"] = kind
				m["id"] = id
				out.append(m)
				break
	for provider in marker_providers:
		if provider.is_valid():
			var extra: Variant = provider.call()
			if extra is Array:
				out.append_array(extra)
	return out


static func _objective_marker(gw: GameWorld, o: Dictionary) -> Dictionary:
	var key := String(o.get("key", ""))
	match String(o.get("type", "")):
		"talk":
			return _giver_marker(gw, key)
		"reach":
			var loc := gw.location_by_id(StringName(key))
			if loc != null:
				return {"pos": loc.center, "dim": loc.dimension}
		"interact":
			var loc2 := gw.location_by_id(StringName(key.get_slice("@", 1)))
			if loc2 != null:
				var p := loc2.center
				for s in loc2.spawns_of("shrine"):
					p = s["pos"]
				return {"pos": p, "dim": loc2.dimension}
		"boss":
			for d: int in gw.gens:
				for loc3 in gw.locations(d):
					for s in loc3.spawns_of("boss"):
						if String(s.get("kind", "")) == key:
							return {"pos": s["pos"], "dim": d}
		"dimension":
			if key == "1":
				var gate := gw.location_by_id(&"gates_of_hades")
				if gate != null:
					for s in gate.spawns_of("portal"):
						return {"pos": s["pos"], "dim": gate.dimension}
			elif key == "2":
				var home := gw.location_by_id(&"emberfall")
				if home != null:
					for s in home.spawns_of("portal"):
						if int(s.get("to", 0)) == 2:
							return {"pos": s["pos"], "dim": home.dimension}
					return {"pos": home.center, "dim": home.dimension}
	return {}


## The giver's actual position when they are about, else their village.
static func _giver_marker(gw: GameWorld, giver: String) -> Dictionary:
	var village := "emberfall"
	var role := ""
	match giver:
		"elder":
			role = "elder"
		"blacksmith":
			role = "blacksmith"
		_:
			if giver.begins_with("villager@"):
				village = giver.trim_prefix("villager@")
				role = "chief"
	for e in gw.all_entities():
		if e is Npc and (e as Npc).village == village and ((e as Npc).role == role or (role == "chief" and (e as Npc).role == "elder")):
			return {"pos": (e as Npc).global_position, "dim": (e as Npc).dimension}
	var loc := gw.location_by_id(StringName(village))
	if loc != null:
		return {"pos": loc.center, "dim": loc.dimension}
	return {}
