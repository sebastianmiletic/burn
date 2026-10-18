class_name MapMarkers
extends RefCounted
## The local player's own map markers (bases, caches, danger...) and the ones
## the party shares. Placed, named, recoloured and deleted on the world map
## (MapScreen); shown on the minimap and the compass strip (ActivityHud).
##
## One instance per GameWorld (`MapMarkers.of(world)`, kept as world metadata).
## Persistence: own markers ride with the fog of war (MapFog.to_dict "markers"),
## so they are saved per run exactly like the explored map (and in a party
## guest's character file). Shared markers reach the party through MapShare.
##
## A marker: {"id", "name", "icon" (MapIcons.MARKER_ICONS), "color" (html),
##            "pos" Vector3, "dim" int, "shared" bool}; party ones add "owner".

const META := &"map_markers"
const MAX := 64
const NAME_MAX := 32

var own: Array = []
var party := {}          # peer id -> Array of marker dictionaries
## Bumped on every change, so views can cache.
var revision := 0
var _world: WeakRef


static func of(world: Object) -> MapMarkers:
	if world == null or not is_instance_valid(world):
		return null
	if world.has_meta(META):
		return world.get_meta(META)
	var m := MapMarkers.new()
	m._world = weakref(world)
	world.set_meta(META, m)
	MapFog.of(world)   # loads the saved markers with the fog
	return m


func add(pos: Vector3, dim: int, marker_name := "", icon: StringName = &"pin", color := Color(), shared := false) -> Dictionary:
	if own.size() >= MAX:
		return {}
	var m := {"id": "%d_%d" % [Time.get_ticks_usec(), randi() % 100000], "name": _clean(marker_name, own.size() + 1),
		"icon": String(icon if icon in MapIcons.MARKER_ICONS else &"pin"),
		"color": (color if color.a > 0.0 else MapIcons.MARKER_COLOURS[0]).to_html(false),
		"pos": pos, "dim": dim, "shared": shared}
	own.append(m)
	_changed(shared)
	return m


## Changes fields of one of your markers ("name", "icon", "color" Color or html, "shared").
func edit(id: String, fields: Dictionary) -> void:
	var m := find(id)
	if m.is_empty():
		return
	var was_shared: bool = m.get("shared", false)
	if fields.has("name"):
		m["name"] = _clean(String(fields["name"]), own.find(m) + 1)
	if fields.has("icon") and StringName(fields["icon"]) in MapIcons.MARKER_ICONS:
		m["icon"] = String(fields["icon"])
	if fields.has("color"):
		var c: Variant = fields["color"]
		m["color"] = (c as Color).to_html(false) if c is Color else String(c)
	if fields.has("pos") and fields["pos"] is Vector3:
		m["pos"] = fields["pos"]
	if fields.has("shared"):
		m["shared"] = bool(fields["shared"])
	_changed(was_shared or m["shared"])


func remove(id: String) -> void:
	var m := find(id)
	if m.is_empty():
		return
	own.erase(m)
	_changed(m.get("shared", false))


## One of your own markers by id ({} if none).
func find(id: String) -> Dictionary:
	for m: Dictionary in own:
		if m["id"] == id:
			return m
	return {}


## Markers to show in `dim`: yours, then the party's (each gets "mine").
func visible(dim: int) -> Array:
	var out: Array = []
	for m: Dictionary in own:
		if int(m["dim"]) == dim:
			m["mine"] = true
			out.append(m)
	for peer: int in party:
		for m: Dictionary in party[peer]:
			if int(m.get("dim", 0)) == dim:
				m["mine"] = false
				out.append(m)
	return out


static func colour(m: Dictionary) -> Color:
	return Color.from_string(String(m.get("color", "")), MapIcons.MARKER_COLOURS[0])


static func icon(m: Dictionary) -> StringName:
	var i := StringName(String(m.get("icon", "pin")))
	return i if i in MapIcons.MARKER_ICONS else &"pin"


## Your markers marked "shared", as sent to the party.
func shared_list() -> Array:
	var out: Array = []
	for m: Dictionary in own:
		if m.get("shared", false):
			out.append({"id": m["id"], "name": m["name"], "icon": m["icon"], "color": m["color"], "pos": m["pos"], "dim": m["dim"]})
	return out


## The party's markers from MapShare (sanitised: they come off the network).
func set_party(by_peer: Dictionary, self_id: int) -> void:
	party.clear()
	for peer: Variant in by_peer:
		if int(peer) == self_id or not (by_peer[peer] is Array):
			continue
		var list: Array = []
		for raw: Variant in (by_peer[peer] as Array).slice(0, MAX):
			if not (raw is Dictionary) or not ((raw as Dictionary).get("pos") is Vector3):
				continue
			var d: Dictionary = raw
			list.append({"id": str(d.get("id", "")), "name": str(d.get("name", "")).left(NAME_MAX), "icon": String(icon(d)),
				"color": str(d.get("color", "")), "pos": d["pos"], "dim": int(d.get("dim", 0)), "owner": str(d.get("owner", "")).left(24)})
		party[int(peer)] = list
	revision += 1


# --- Persistence (through MapFog) ------------------------------------------------------

func to_array() -> Array:
	var out: Array = []
	for m: Dictionary in own:
		out.append({"id": m["id"], "name": m["name"], "icon": m["icon"], "color": m["color"], "pos": m["pos"], "dim": m["dim"],
			"shared": m.get("shared", false)})
	return out


func from_array(list: Variant) -> void:
	own.clear()
	if list is Array:
		for raw: Variant in list:
			if raw is Dictionary and (raw as Dictionary).get("pos") is Vector3 and own.size() < MAX:
				var d: Dictionary = raw
				own.append({"id": str(d.get("id", str(own.size()))), "name": str(d.get("name", "")).left(NAME_MAX),
					"icon": String(icon(d)), "color": str(d.get("color", MapIcons.MARKER_COLOURS[0].to_html(false))),
					"pos": d["pos"], "dim": int(d.get("dim", 0)), "shared": bool(d.get("shared", false))})
	revision += 1


func _changed(share: bool) -> void:
	revision += 1
	var w: Object = _world.get_ref() if _world != null else null
	var fog := MapFog.of(w)
	if fog != null:
		fog.mark_unsaved()
	if share:
		MapShare.push(w)


static func _clean(text: String, n: int) -> String:
	var t := text.strip_edges().replace("\n", " ").left(NAME_MAX)
	return t if t != "" else "Marker %d" % n
