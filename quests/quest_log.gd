class_name QuestLog
extends RefCounted
## The local player's quests: progress, tracking, completion and rewards.
## Progress comes from `on_event(type, key, amount)`; "collect" and "have"
## objectives are re-evaluated from the inventory.

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


func accept(id: String) -> bool:
	if _active.has(id) or _completed.has(id):
		return false
	var q := QuestDB.any(id)
	if q.is_empty():
		return false
	var progress := PackedInt32Array()
	progress.resize((q["objectives"] as Array).size())
	_active[id] = {"progress": progress, "tracked": true}
	_refresh_inventory_objectives()
	Events.quest_updated.emit(id)
	Events.notify.emit("New quest: " + String(q["title"]), "quest")
	Audio.play_ui("quest")
	return true


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
			if o["key"] != key and not (type == "discover" and key.begins_with(o["key"])):
				continue
			if progress[i] < int(o["count"]):
				progress[i] = mini(int(o["count"]), progress[i] + amount)
				touched = true
		_active[id]["progress"] = progress
		if touched:
			Events.quest_updated.emit(id)
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
				var n := mini(inventory.count_of(o["key"]), int(o["count"]))
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
		var q := QuestDB.any(id)
		if String(q["giver"]) == "" and _objectives_done(id):
			complete(id)
		elif String(q["giver"]) != "" and _objectives_done(id) and not _active[id].get("announced", false):
			_active[id]["announced"] = true
			Events.notify.emit("%s — return to %s" % [q["title"], _giver_label(q["giver"])], "quest")


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
	if next != "" and QuestDB.main_quest(next).get("giver", "x") == "":
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
	return {"id": id, "title": q["title"], "description": q["description"], "objectives": list,
		"rewards": ", ".join(rewards), "tracked": (not done) and _active[id]["tracked"], "main": not id.begins_with("side_"),
		"ready": ready, "turn_in": _giver_label(q["giver"]) if ready else ""}


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
		_active[id] = {"progress": PackedInt32Array(a[id]["progress"]), "tracked": a[id]["tracked"]}
	for id: String in d.get("completed", []):
		_completed[id] = true
	var act: Variant = d.get("activity", {})
	activity = (act as Dictionary).duplicate(true) if act is Dictionary else {}


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
			var kind := "main" if not id.begins_with("side_") else "side"
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
