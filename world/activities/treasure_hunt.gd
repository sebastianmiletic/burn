class_name TreasureHunt
extends RefCounted
## Treasure maps. Carrying a Weathered Treasure Map starts a hunt: its riddle
## names a landmark and a bearing ("From the Old Beacon, 32 paces north-east,
## where the ash lies deep"). Reach the landmark, then search: the HUD dowsing
## needle runs cold -> warm -> burning, and near the spot two crossed stakes
## mark the X. Dig down with a pickaxe (mining sculpts the ground) until the
## chest's lid shows, open it, and the map is spent. Chests pay gold, gems,
## valuables, sometimes rare gear and often the next map.
##
## Per player: the hunt lives in QuestLog.activity["treasure"]. The chest is a
## server entity (owner = the hunter's peer) so everyone sees it unearthed.

const DIRS := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
const HINTS := {
	WorldGen.Biome.PLAINS: "where the ash lies deep",
	WorldGen.Biome.FOREST: "under the old trees",
	WorldGen.Biome.PEAKS: "beneath the snow",
	WorldGen.Biome.MARSH: "where the reeds whisper",
	WorldGen.Biome.WASTES: "in the black sand",
}
const LOOT := {
	1: {"gold": [40, 75], "rolls": 2, "pool": [["potion_health", 2, 3], ["iron_ingot", 2, 4], ["ruby", 1, 1], ["sapphire", 1, 1], ["amethyst", 1, 1], ["ancient_coin", 3, 6], ["lantern", 1, 1], ["torch", 6, 10]],
		"map": 0.3, "rare": [["gilded_idol", 0.25], ["potion_ironskin", 0.3], ["fog_lantern", 0.2]]},
	2: {"gold": [70, 130], "rolls": 3, "pool": [["potion_greater", 1, 2], ["gold_ingot", 1, 3], ["ruby", 1, 2], ["sapphire", 1, 2], ["amethyst", 1, 2], ["ancient_coin", 5, 10], ["steel_ingot", 2, 3], ["ember_crystal", 1, 2]],
		"map": 0.35, "rare": [["gilded_idol", 0.4], ["sword_ember", 0.08], ["potion_might", 0.35], ["frost_totem", 0.2], ["storm_horn", 0.12]]},
	3: {"gold": [120, 220], "rolls": 3, "pool": [["potion_phoenix", 1, 1], ["mithril_ingot", 1, 2], ["ember_crystal", 2, 3], ["gilded_idol", 1, 1], ["ancient_coin", 8, 14], ["ruby", 2, 3], ["sapphire", 2, 3]],
		"map": 0.4, "rare": [["pickaxe_obsidian", 0.1], ["sword_ember", 0.15], ["starmetal", 0.3], ["storm_horn", 0.3], ["sunstone", 0.25]]},
}
const LANDMARK_TIERS := {Location.Kind.SHRINE: 1, Location.Kind.VILLAGE: 1, Location.Kind.TOWER: 2, Location.Kind.RUIN: 2,
		Location.Kind.CRYPT: 3, Location.Kind.CASTLE: 3, Location.Kind.HALL: 3}
const SEARCH_RADIUS := 45.0     ## reaching this close to the landmark starts the search
const DIG_DEPTH := 1.35         ## chest base below the surface

var d: ActivityDirector
var _mark: Node3D               ## the X (local only)
var _requested_at := -100.0
var heat := -1.0                ## 0 cold .. 1 burning; -1 not searching (for the HUD)

# Server: (peer:hunt) -> net id of the chest.
var _caches := {}


func _init(director: ActivityDirector) -> void:
	d = director


func state() -> Dictionary:
	var q := d.gw().quests
	if not q.activity.has("treasure"):
		q.activity["treasure"] = {"active": {}, "found": 0, "seq": 0}
	return q.activity["treasure"]


func active() -> Dictionary:
	return state().get("active", {})


# --- Client ---------------------------------------------------------------------------

func local_tick(_dt: float) -> void:
	var w := d.gw()
	var p := w.local_player
	if p == null or p.dead:
		return
	var st := state()
	var hunt: Dictionary = st.get("active", {})
	var maps := p.inventory.count_of("treasure_map")
	if hunt.is_empty():
		heat = -1.0
		_clear_mark()
		if maps > 0 and p.dimension == 0:
			hunt = begin(w, p)
			if not hunt.is_empty():
				Events.notify.emit("You unfold the map: \"%s\"" % String(hunt["clue"]), "quest")
				Audio.play_ui("quest")
		return
	if maps <= 0 and String(hunt.get("stage", "")) != "open":
		st["active"] = {}
		Events.notify.emit("Without the map the trail goes cold.", "warn")
		_clear_mark()
		return
	var spot: Vector3 = hunt["spot"]
	var here := p.global_position
	var flat := Vector2(here.x - spot.x, here.z - spot.z).length()
	match String(hunt["stage"]):
		"landmark":
			heat = -1.0
			var lm: Vector3 = hunt["landmark_pos"]
			if p.dimension == 0 and Vector2(here.x - lm.x, here.z - lm.z).length() < SEARCH_RADIUS:
				hunt["stage"] = "search"
				Events.notify.emit("This is the place on the map. Search for the spot — the needle grows warmer as you near it.", "quest")
		"search", "dig":
			heat = clampf(1.0 - (flat - 2.0) / 60.0, 0.0, 1.0) if p.dimension == 0 else -1.0
			if flat < 40.0:
				_show_mark(w, spot)
			if flat < 26.0 and Time.get_ticks_msec() / 1000.0 - _requested_at > 12.0 and _find_cache(w, hunt).is_empty():
				_requested_at = Time.get_ticks_msec() / 1000.0
				d.request("cache", {"hunt": int(hunt["id"]), "x": spot.x, "z": spot.z, "tier": int(hunt["tier"]), "seed": int(hunt["seed"])})
			if flat < 4.0 and hunt["stage"] == "search":
				hunt["stage"] = "dig"
				Events.notify.emit("X marks the spot. Dig down with your pickaxe.", "quest")
			var cache := _find_cache(w, hunt)
			if not cache.is_empty() and bool(cache[0].get("exposed")) and hunt["stage"] == "dig":
				hunt["stage"] = "open"
				Events.notify.emit("The lid of a chest! Open it.", "quest")
		"open":
			heat = 1.0


## Starts a hunt for the local player from the map they carry.
func begin(w: GameWorld, p: Player) -> Dictionary:
	var st := state()
	var seq := int(st.get("seq", 0))
	var hunt := generate(w.gen_for(0), w.locations(0), p.global_position, hash([w.gen_for(0).world_seed, p.display_name, seq]))
	if hunt.is_empty():
		return {}
	st["seq"] = seq + 1
	hunt["id"] = seq + 1
	st["active"] = hunt
	return hunt


## A hunt near a landmark 120–700 m from `from`: {landmark, landmark_pos,
## landmark_name, spot, clue, tier, seed, stage}. Pure (testable).
static func generate(gen: WorldGen, locs: Array[Location], from: Vector3, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var candidates: Array[Location] = []
	for loc in locs:
		if not LANDMARK_TIERS.has(loc.kind) or loc.half_height > 0.0 or loc.center.y < WorldGen.SEA_LEVEL:
			continue
		var dist := Vector2(loc.center.x - from.x, loc.center.z - from.z).length()
		if dist > 90.0 and dist < 750.0:
			candidates.append(loc)
	if candidates.is_empty():
		for loc in locs:
			if LANDMARK_TIERS.has(loc.kind) and loc.half_height <= 0.0:
				candidates.append(loc)
	if candidates.is_empty():
		return {}
	for attempt in 40:
		var lm: Location = candidates[rng.randi() % candidates.size()]
		var dir_i := rng.randi() % 8
		var paces := rng.randi_range(int(lm.radius) + 14, int(lm.radius) + 40)
		var a := float(dir_i) * TAU / 8.0
		# North is -Z on every map in the game.
		var off := Vector2(sin(a), -cos(a)) * paces
		var x := lm.center.x + off.x
		var z := lm.center.z + off.y
		if not spot_ok(gen, locs, x, z):
			continue
		var biome := gen.biome_at(int(x), int(z))
		var hint: String = HINTS.get(biome, "where the ground is soft")
		var tier: int = LANDMARK_TIERS[lm.kind]
		if rng.randf() < 0.2:
			tier = mini(3, tier + 1)
		var clue := "From %s, %d paces %s, %s." % [lm.name, paces, DIRS[dir_i], hint]
		return {"landmark": String(lm.id), "landmark_name": lm.name, "landmark_pos": lm.center,
			"spot": Vector3(x, gen.ground_level(x, z), z), "clue": clue, "tier": tier, "seed": rng.randi(), "stage": "landmark"}
	return {}


## Dry, gentle, open ground away from buildings.
static func spot_ok(gen: WorldGen, locs: Array[Location], x: float, z: float) -> bool:
	if x < 24.0 or z < 24.0 or x > gen.size - 24.0 or z > gen.size - 24.0:
		return false
	var h := gen.surface_height(int(x), int(z))
	if h < WorldGen.SEA_LEVEL + 1:
		return false
	for o: Vector2i in [Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(0, -3)]:
		var h2 := gen.surface_height(int(x) + o.x, int(z) + o.y)
		if absi(h2 - h) > 2 or h2 < WorldGen.SEA_LEVEL + 1:
			return false
	for loc in locs:
		if loc.dimension == 0 and Vector2(loc.center.x - x, loc.center.z - z).length() < loc.radius + 6.0:
			return false
	return true


func _find_cache(w: GameWorld, hunt: Dictionary) -> Array:
	var me := w.multiplayer.get_unique_id()
	for e in w.all_entities():
		if e is BuriedCache and (e as BuriedCache).owner_peer == me and (e as BuriedCache).hunt_id == int(hunt.get("id", -1)):
			return [e]
	return []


## Called on every machine when a chest opens; finishes the owner's hunt.
func on_cache_opened(cache: BuriedCache) -> void:
	var w := d.gw()
	if cache.owner_peer != w.multiplayer.get_unique_id():
		return
	var st := state()
	var hunt: Dictionary = st.get("active", {})
	if hunt.is_empty() or int(hunt.get("id", -1)) != cache.hunt_id:
		return
	w.local_player.inventory.remove("treasure_map", 1)
	st["found"] = int(st.get("found", 0)) + 1
	st["active"] = {}
	heat = -1.0
	_clear_mark()
	Events.notify.emit("Treasure found! (%d so far)" % int(st["found"]), "quest")


func _show_mark(w: GameWorld, spot: Vector3) -> void:
	if _mark != null and is_instance_valid(_mark):
		return
	var vw := w.world_for(0)
	if vw == null or not vw.is_area_loaded(spot):
		return
	var g := vw.ground_below(spot.x, spot.y + 30.0, spot.z, 60.0)
	if absf(g) > 1e6:
		return
	_mark = Node3D.new()
	_mark.name = "TreasureMark"
	ActivityModels.dig_mark(_mark, int(spot.x) ^ int(spot.z))
	w.add_child(_mark)
	_mark.global_position = Vector3(spot.x, g - 0.05, spot.z)


func _clear_mark() -> void:
	if _mark != null and is_instance_valid(_mark):
		_mark.queue_free()
	_mark = null


func markers() -> Array:
	var hunt := active()
	if hunt.is_empty():
		return []
	var spot: Vector3 = hunt["spot"]
	match String(hunt["stage"]):
		"landmark":
			return [{"pos": hunt["landmark_pos"], "dim": 0, "label": "Treasure: " + String(hunt["landmark_name"]), "kind": "activity", "icon": "treasure", "priority": 2}]
		"search":
			# A fuzzy circle around the spot, not the spot itself.
			var rng := RandomNumberGenerator.new()
			rng.seed = int(hunt["seed"])
			var off := Vector3(rng.randf_range(-8.0, 8.0), 0.0, rng.randf_range(-8.0, 8.0))
			return [{"pos": spot + off, "dim": 0, "label": "Search for the X", "kind": "activity", "radius": 14.0, "icon": "treasure", "priority": 2}]
		"dig", "open":
			return [{"pos": spot, "dim": 0, "label": "Dig here" if hunt["stage"] == "dig" else "Open the chest", "kind": "activity", "icon": "treasure", "priority": 3}]
	return []


func tracker() -> Array:
	var hunt := active()
	if hunt.is_empty():
		return []
	var line := ""
	match String(hunt["stage"]):
		"landmark":
			line = "Reach %s" % String(hunt["landmark_name"])
		"search":
			line = "Search: " + heat_word(heat)
		"dig":
			line = "Dig at the X with a pickaxe"
		"open":
			line = "Open the chest"
	return [{"title": "Treasure Map", "lines": PackedStringArray(["\"%s\"" % String(hunt["clue"]), line]), "kind": "activity"}]


static func heat_word(h: float) -> String:
	if h < 0.0:
		return ""
	if h > 0.93:
		return "burning hot!"
	if h > 0.75:
		return "hot"
	if h > 0.5:
		return "warm"
	if h > 0.25:
		return "cool"
	return "cold"


# --- Server -----------------------------------------------------------------------------

func server_spawn_cache(p: Player, args: Dictionary) -> void:
	var w := d.gw()
	var hunt_id := int(args.get("hunt", -1))
	var x := float(args.get("x", 0.0))
	var z := float(args.get("z", 0.0))
	if hunt_id < 0 or p.dimension != 0 or not is_finite(x) or not is_finite(z):
		return
	if Vector2(p.global_position.x - x, p.global_position.z - z).length() > 40.0:
		return
	var key := "%d:%d" % [p.peer_id, hunt_id]
	if _caches.has(key) and w.entity(int(_caches[key])) != null:
		return
	var vw := w.world_for(0)
	if vw == null or not vw.is_area_loaded(Vector3(x, p.global_position.y, z)):
		return
	var g := vw.ground_below(x, p.global_position.y + 40.0, z, 90.0)
	if absf(g) > 1e6:
		return
	var e := w.spawn_entity("act_cache", Vector3(x, g - DIG_DEPTH, z), 0, {"owner": p.peer_id, "hunt": hunt_id,
		"tier": clampi(int(args.get("tier", 1)), 1, 3), "seed": int(args.get("seed", 0))})
	if e != null:
		_caches[key] = e.net_id


## Server: what a chest of `tier` holds. Pure apart from the rng.
static func roll_loot(tier: int, rng: RandomNumberGenerator) -> Dictionary:
	var t: Dictionary = LOOT.get(clampi(tier, 1, 3), LOOT[1])
	var items := {}
	var pool: Array = (t["pool"] as Array).duplicate()
	for i in int(t["rolls"]):
		if pool.is_empty():
			break
		var k := rng.randi() % pool.size()
		var entry: Array = pool[k]
		pool.remove_at(k)
		items[entry[0]] = int(items.get(entry[0], 0)) + rng.randi_range(int(entry[1]), int(entry[2]))
	for r: Array in t["rare"]:
		if rng.randf() < float(r[1]):
			items[r[0]] = int(items.get(r[0], 0)) + 1
	if rng.randf() < float(t["map"]):
		items["treasure_map"] = int(items.get("treasure_map", 0)) + 1
	var gold: Array = t["gold"]
	return {"gold": rng.randi_range(int(gold[0]), int(gold[1])), "items": items, "xp": 40 * tier}
