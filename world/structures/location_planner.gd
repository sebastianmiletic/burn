class_name LocationPlanner
extends RefCounted
## Decides where every named place goes and builds its blueprint.
##
## Overworld layout (2 km island, centre 1024,1024):
##   Emberfall (start village) in the Ashen Plains at the centre,
##   Frost Peaks to the north with the Hall of the Mountain King,
##   Emberwood (autumn forest) to the east, Blackmarsh with the Silent Crypt
##   to the west, the Cinder Wastes to the south with the Dragon's Keep, and
##   the Gates of Hades deep beneath the Cinder Crater.

var gen: WorldGen
var rng := RandomNumberGenerator.new()
var _detail: FastNoiseLite
var _ridge: FastNoiseLite


func _init(world_gen: WorldGen) -> void:
	gen = world_gen
	rng.seed = gen.world_seed * 7919 + 17
	_detail = gen.make_detail_noise()
	_ridge = gen.make_ridge_noise()


func plan() -> Array[Location]:
	ArchClearings.reset(gen.dimension, gen.world_seed)
	if gen.dimension == WorldGen.Dimension.RYFT:
		return ExplorationSites.ryft(gen)
	if gen.dimension == WorldGen.Dimension.HELL:
		return _plan_hell()
	return _plan_overworld()


func _ground(x: float, z: float) -> int:
	return int(floorf(gen.raw_height(int(x), int(z), _detail, _ridge)))


func _jitter(p: Vector2, amount: float) -> Vector2:
	return p + Vector2(rng.randf_range(-amount, amount), rng.randf_range(-amount, amount))


# --- Overworld ---------------------------------------------------------------

func _plan_overworld() -> Array[Location]:
	var out: Array[Location] = []
	var villages := [
		[&"emberfall", "Emberfall", Vector2(1024, 1024)],
		[&"ashford", "Ashford", _jitter(Vector2(1215, 875), 20)],
		[&"thornwick", "Thornwick", _jitter(Vector2(1575, 1045), 20)],
		[&"frosthold", "Frosthold", _jitter(Vector2(1000, 575), 15)],
		[&"mirewatch", "Mirewatch", _jitter(Vector2(540, 905), 20)],
		[&"cinderreach", "Cinderreach", _jitter(Vector2(850, 1510), 15)],
	]
	for v: Array in villages:
		var p: Vector2 = v[2]
		var g := maxi(_ground(p.x, p.y), WorldGen.SEA_LEVEL + 2)
		var loc := Location.new(v[0], v[1], Location.Kind.VILLAGE, Vector3(p.x, g, p.y))
		loc.major = true
		Structures.village(loc, rng, v[0] == &"emberfall")
		if gen.revision >= 2 and gen.biome_at(int(p.x), int(p.y)) == WorldGen.Biome.PEAKS:
			loc.pad_falloff = 65.0
		out.append(loc)
		out.append(_shrine(StringName(String(v[0]) + "_shrine"), "%s Shrine" % v[1], p + Vector2(0, 21)))

	out.append_array(_crypt(Vector2(410, 1110)))
	out.append_array(_mountain_hall(Vector2(1024, 300)))
	out.append_array(_keep(Vector2(1040, 1800)))
	out.append_array(_gates(Vector3(1024, -100, 1555)))

	# Watchtowers along the roads and scattered ruins.
	var tower_names := ["Ashwatch Tower", "Greyspire", "Old Beacon", "Hollow Tower", "Wardens' Post", "Sunken Tower"]
	for i in tower_names.size():
		var a := TAU * float(i) / tower_names.size() + 0.4
		var p := Vector2(1024, 1024) + Vector2(cos(a), sin(a)) * rng.randf_range(260, 420)
		var g := maxi(_ground(p.x, p.y), WorldGen.SEA_LEVEL + 2)
		var loc := Location.new(StringName("tower_%d" % i), tower_names[i], Location.Kind.TOWER, Vector3(p.x, g, p.y))
		Structures.tower(loc, rng)
		out.append(loc)
	var ruin_names := ["Fallen Chapel", "Broken Aqueduct", "Ruined Manor", "Cairn of Kings", "Burnt Mill",
			"Forgotten Shrine", "Ashen Barrow", "Weeping Stones", "Old Battlefield", "The Hollow Ring"]
	for i in ruin_names.size():
		var p := Vector2.ZERO
		for attempt in 20:
			var a := rng.randf() * TAU
			p = Vector2(1024, 1024) + Vector2(cos(a), sin(a)) * rng.randf_range(150, 820)
			if _far_from(out, p, 90.0) and _ground(p.x, p.y) > WorldGen.SEA_LEVEL + 1:
				break
		var g := maxi(_ground(p.x, p.y), WorldGen.SEA_LEVEL + 2)
		var loc := Location.new(StringName("ruin_%d" % i), ruin_names[i], Location.Kind.RUIN, Vector3(p.x, g, p.y))
		Structures.ruin(loc, rng)
		out.append(loc)
	# Creature lairs: planned last with their own random stream so every
	# location above keeps its place in existing worlds.
	var lair_rng := RandomNumberGenerator.new()
	lair_rng.seed = gen.world_seed * 104729 + 31
	out.append_array(_drowned_spire(out, lair_rng))
	out.append_array(_weeping_hollow(out, lair_rng))
	out.append_array(_hagsfen(out, lair_rng))
	if gen.revision >= 3:
		var mine_rng := RandomNumberGenerator.new()
		mine_rng.seed = gen.world_seed * 7727 + 3
		for site: Array in [["old_ember_mine", "Old Ember Mine", Vector2(1280, 1140), {"ore": Blocks.COPPER_ORE, "rich": Blocks.IRON_ORE, "levels": 2, "guardian": "troll"}],
				["frost_adit", "Frosthold Adit", Vector2(870, 650), {"ore": Blocks.TIN_ORE, "rich": Blocks.SILVER_ORE, "levels": 2, "guardian": "rock_golem"}]]:
			out.append_array(_full_mine(out, StringName(site[0]), site[1], site[2], site[3], mine_rng))
	elif gen.revision >= 2:
		for site: Array in [["old_ember_mine", "Old Ember Mine", Vector2(1280, 1140)], ["frost_adit", "Frosthold Adit", Vector2(870, 650)]]:
			var p: Vector2 = site[2]
			var mine := Location.new(StringName(site[0]), site[1], Location.Kind.CRYPT, Vector3(p.x, _ground(p.x, p.y) + 1, p.y))
			ExplorationSites.mine(mine)
			out.append(mine)
	if gen.revision >= 2:
		var wreck_count := 0
		for i in 48:
			var angle := i * TAU / 48.0
			var p := gen.center() + Vector2(cos(angle), sin(angle)) * 975.0
			var h := _ground(p.x, p.y)
			if h < WorldGen.SEA_LEVEL - 4 and h > -16 and _far_from(out, p, 100):
				var wreck := Location.new(StringName("wreck_%d" % wreck_count), ["The Cinderwake", "Saltbound Wreck", "The Lost Lantern", "Reefrunner's Rest"][wreck_count], Location.Kind.RUIN, Vector3(p.x, h + 1, p.y))
				ExplorationSites.shipwreck(wreck)
				if gen.revision >= 4:
					for prop: Dictionary in wreck.props:
						prop["sunken"] = true  # coral and weed on the old wrecks too (visual only)
				out.append(wreck)
				wreck_count += 1
				if wreck_count == 4:
					break
	if gen.revision >= 3:
		out.append_array(_plan_new_lands(out))
	if gen.revision >= 4:
		out.append_array(_plan_sea(out))
	# The endgame gateway exists from the start, visibly sealed until Hades falls.
	var hub := out[0]
	hub.add_spawn("portal", hub.center + Vector3(0, 1, -12), {"to": 2, "size": Vector2(3, 5)})
	for loc in out:
		loc.dimension = 0
	# Paths out to the roads, palisade gates and the grass-free ground.
	VillagePlan.finish(out, gen)
	return out


func _inside(p: Vector2, margin: float) -> bool:
	return p.x > margin and p.y > margin and p.x < gen.size - margin and p.y < gen.size - margin


## The Leviathan's islet: the shortest hop from the coast out into deep water,
## away from everything else, joined to the shore by a broken causeway.
func _drowned_spire(existing: Array[Location], lrng: RandomNumberGenerator) -> Array[Location]:
	var c := gen.center()
	var best := {}
	var best_score := INF
	for i in 36:
		var a := TAU * float(i) / 36.0
		var d := Vector2(cos(a), sin(a))
		var r := 300.0
		var r_land := -1.0
		var found := false
		while r < 1000.0 and _inside(c + d * r, 60.0):
			if gen.smooth_height((c + d * r).x, (c + d * r).y) < WorldGen.SEA_LEVEL - 2:
				found = true
				break
			r_land = r
			r += 4.0
		if not found or r_land < 0.0:
			continue
		var deep := true
		for k in range(10, 100, 10):
			var q := c + d * (r + float(k))
			if not _inside(q, 45.0) or gen.smooth_height(q.x, q.y) > WorldGen.SEA_LEVEL - 3:
				deep = false
				break
		if not deep:
			continue
		var islet := c + d * (r + (85.0 if gen.revision >= 3 else 60.0))
		if not _far_from(existing, islet, 170.0) or not _far_from(existing, c + d * (r_land - 8.0), 70.0):
			continue
		if gen.revision >= 3:
			# Open water all round the islet for the Leviathan to circle in.
			var open_sea := true
			for k in 12:
				var q := islet + Vector2.from_angle(TAU * k / 12.0) * 30.0
				if gen.smooth_height(q.x, q.y) > WorldGen.SEA_LEVEL - 9:
					open_sea = false
					break
			if not open_sea:
				continue
		var score := r + lrng.randf() * 40.0
		if score < best_score:
			best_score = score
			best = {"dir": d, "islet": islet, "land": c + d * (r_land - 2.0)}
	if best.is_empty():
		return []
	var d: Vector2 = best["dir"]
	var islet: Vector2 = best["islet"]
	var land: Vector2 = best["land"]
	var spire := Location.new(&"drowned_spire", "The Drowned Spire", Location.Kind.TOWER, Vector3(islet.x, WorldGen.SEA_LEVEL + 2, islet.y))
	spire.major = true
	Lairs.drowned_spire(spire, d, lrng)
	Lairs.causeway(spire, land, islet - d * 16.0, lrng)
	return [spire, _shrine(&"tidewatch_shrine", "Tidewatch Shrine", land - d * 8.0)]


## The Broodmother's cavern beneath Emberwood.
func _weeping_hollow(existing: Array[Location], lrng: RandomNumberGenerator) -> Array[Location]:
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0)]
	var candidates: Array[Vector2] = []
	for gz in range(-7, 8):
		for gx in range(-7, 8):
			candidates.append(Vector2(1400, 1060) + Vector2(gx, gz) * 28.0)
	candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(Vector2(1400, 1060)) < b.distance_squared_to(Vector2(1400, 1060)))
	for p: Vector2 in candidates:
		if not _inside(p, 140.0) or gen.biome_at(int(p.x), int(p.y)) != WorldGen.Biome.FOREST:
			continue
		var g := _ground(p.x, p.y)
		if g < WorldGen.SEA_LEVEL + 6 or not _far_from(existing, p, 150.0):
			continue
		for dv: Vector2i in dirs:
			var cav := p + Vector2(dv) * 101.0
			if not _inside(cav, 40.0) or not _far_from(existing, cav, 110.0):
				continue
			var gc := _ground(cav.x, cav.y)
			if gc < WorldGen.SEA_LEVEL + 6:
				continue
			var floor_y := clampi(mini(g, gc) - 42, -70, 10)
			var surface := Location.new(&"weeping_hollow", "The Weeping Hollow", Location.Kind.RUIN, Vector3(p.x, g, p.y))
			surface.major = true
			var lair := Location.new(&"broodmother_lair", "The Broodmother's Lair", Location.Kind.CRYPT, Vector3(cav.x, floor_y, cav.y))
			lair.major = true
			Lairs.weeping_hollow(surface, lair, dv, floor_y, lrng)
			return [surface, lair, _shrine(&"hollow_shrine", "Emberwood Shrine", p - Vector2(dv) * 16.0)]
	return []


## The bog witch's clearing in Blackmarsh.
func _hagsfen(existing: Array[Location], lrng: RandomNumberGenerator) -> Array[Location]:
	var centre := Vector2(400, 860)
	var candidates: Array[Vector2] = []
	for gz in range(-9, 10):
		for gx in range(-9, 10):
			candidates.append(centre + Vector2(gx, gz) * 26.0)
	candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(centre) < b.distance_squared_to(centre))
	for p: Vector2 in candidates:
		if not _inside(p, 60.0) or gen.biome_at(int(p.x), int(p.y)) != WorldGen.Biome.MARSH:
			continue
		if not _far_from(existing, p, 130.0):
			continue
		var g := maxi(_ground(p.x, p.y), WorldGen.SEA_LEVEL + 2)
		var loc := Location.new(&"hagsfen", "Hagsfen", Location.Kind.RUIN, Vector3(p.x, g, p.y))
		loc.major = true
		Lairs.hagsfen(loc, lrng)
		return [loc]
	return []


func _far_from(locs: Array[Location], p: Vector2, dist: float) -> bool:
	for l in locs:
		if Vector2(l.center.x, l.center.z).distance_to(p) < dist:
			return false
	return true


func _shrine(id: StringName, shrine_name: String, p: Vector2) -> Location:
	var g := maxi(_ground(p.x, p.y), WorldGen.SEA_LEVEL + 2)
	var loc := Location.new(id, shrine_name, Location.Kind.SHRINE, Vector3(p.x, g, p.y))
	Structures.shrine(loc)
	return loc


func _crypt(p: Vector2) -> Array[Location]:
	var g := maxi(_ground(p.x, p.y), WorldGen.SEA_LEVEL + 2)
	var surface := Location.new(&"silent_crypt", "The Silent Crypt", Location.Kind.CRYPT, Vector3(p.x, g, p.y))
	surface.major = true
	var depths := Location.new(&"crypt_depths", "Crypt Depths", Location.Kind.CRYPT, Vector3(p.x, g - 18, p.y - 34))
	depths.half_height = 10.0
	depths.radius = 34.0
	depths.major = true
	Structures.crypt(surface, depths)
	return [surface, depths, _shrine(&"crypt_shrine", "Marsh Shrine", p + Vector2(0, 22))]


func _mountain_hall(near: Vector2) -> Array[Location]:
	# Pick the bulkiest mountain near `near`: highest minimum height over the hall footprint.
	var best := near
	var best_score := -1e9
	for gz in range(-6, 7):
		for gx in range(-6, 7):
			var c := near + Vector2(gx, gz) * 22.0
			var lowest := 1e9
			for s: Vector2 in [Vector2(-18, -30), Vector2(18, -30), Vector2(-18, 30), Vector2(18, 30), Vector2(0, 0)]:
				lowest = minf(lowest, _ground(c.x + s.x, c.y + s.y))
			if lowest > best_score:
				best_score = lowest
				best = c
	var floor_y := clampi(int(best_score) - 22, 30, 300 if gen.revision >= 2 else 80)
	# Tunnel towards whichever side falls away fastest.
	var dirs := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]
	var exit_dir: Vector2i = dirs[0]
	var lowest_exit := 1e9
	for d: Vector2i in dirs:
		var e := best + Vector2(d) * 90.0
		var h := _ground(e.x, e.y)
		if h < lowest_exit:
			lowest_exit = h
			exit_dir = d
	var exit_p := best + Vector2(exit_dir) * 90.0
	var exit_y := maxi(_ground(exit_p.x, exit_p.y), WorldGen.SEA_LEVEL + 2)
	var hall := Location.new(&"mountain_hall", "Hall of the Mountain King", Location.Kind.HALL, Vector3(best.x, floor_y + 1, best.y))
	hall.radius = 40.0
	hall.half_height = 14.0
	hall.major = true
	Structures.mountain_hall(hall, exit_dir, exit_y, rng)
	var shrine_p := exit_p + Vector2(exit_dir) * 6.0
	return [hall, _shrine(&"hall_shrine", "Frostgate Shrine", shrine_p)]


func _keep(p: Vector2) -> Array[Location]:
	var g := maxi(_ground(p.x, p.y), WorldGen.SEA_LEVEL + 3)
	var keep := Location.new(&"dragons_keep", "The Dragon's Keep", Location.Kind.CASTLE, Vector3(p.x, g, p.y))
	keep.major = true
	Structures.castle(keep, rng)
	return [keep, _shrine(&"keep_shrine", "Keep Shrine", p + Vector2(0, -60))]


func _gates(c: Vector3) -> Array[Location]:
	var gate := Location.new(&"gates_of_hades", "Gates of Hades", Location.Kind.GATE, c)
	gate.radius = 46.0
	gate.half_height = 24.0
	gate.major = true
	Structures.gates_of_hades(gate, rng)
	var rim := Vector2(c.x, c.z) + Vector2(gen._crater.z * 0.95, 0)
	var crater := Location.new(&"cinder_crater", "The Cinder Crater", Location.Kind.RUIN, Vector3(c.x, _ground(c.x, c.z), c.z))
	crater.radius = gen._crater.z
	crater.major = true
	Structures.crater_marker(crater, rng)
	return [gate, crater, _shrine(&"crater_shrine", "Crater Shrine", rim)]


# --- Revision 3: the Eastreach and the Sunderlands ------------------------------------------

## New villages: id, name, nominal position, biome (searched for level ground nearby).
const NEW_VILLAGES := [
	[&"elderhollow", "Elderhollow", Vector2(2430, 1120), WorldGen.Biome.REDWOOD],
	[&"highmere", "Highmere", Vector2(3060, 960), WorldGen.Biome.ALPINE],
	[&"kaldvik", "Kaldvik", Vector2(3860, 1180), WorldGen.Biome.FJORD],
	[&"frostmark", "Frostmark", Vector2(3930, 640), WorldGen.Biome.TUNDRA],
	[&"redmesa", "Redmesa", Vector2(3320, 1880), WorldGen.Biome.CANYON],
	[&"brimhold", "Brimhold", Vector2(1560, 2440), WorldGen.Biome.VOLCANIC],
	[&"cedarfall", "Cedarfall", Vector2(800, 3080), WorldGen.Biome.REDWOOD],
	[&"redcliff", "Redcliff", Vector2(1930, 3140), WorldGen.Biome.CANYON],
	[&"sunderholm", "Sunderholm", Vector2(1380, 3680), WorldGen.Biome.PLAINS],
	[&"meadowmere", "Meadowmere", Vector2(3200, 1250), WorldGen.Biome.PLAINS],
]
## New mines: id, name, nominal position, biome, spec.
const NEW_MINES := [
	[&"redrock_delve", "Redrock Delve", Vector2(3480, 2020), WorldGen.Biome.CANYON, {"ore": Blocks.COPPER_ORE, "rich": Blocks.GOLD_ORE, "levels": 3, "guardian": "troll"}],
	[&"kaldvik_silverworks", "Kaldvik Silverworks", Vector2(3740, 1330), WorldGen.Biome.FJORD, {"ore": Blocks.SILVER_ORE, "rich": Blocks.SAPPHIRE_ORE, "levels": 2, "guardian": "rock_golem"}],
	[&"highmere_deepworks", "Highmere Deepworks", Vector2(2880, 760), WorldGen.Biome.ALPINE, {"ore": Blocks.IRON_ORE, "rich": Blocks.MITHRIL_ORE, "levels": 3, "guardian": "rock_golem"}],
	[&"brimstone_pit", "Brimstone Pit", Vector2(1380, 2760), WorldGen.Biome.VOLCANIC, {"ore": Blocks.COAL_ORE, "rich": Blocks.EMBER_ORE, "levels": 2, "guardian": "fire_elemental"}],
	[&"elder_root_mine", "Elder Root Mine", Vector2(2620, 1300), WorldGen.Biome.REDWOOD, {"ore": Blocks.IRON_ORE, "rich": Blocks.GOLD_ORE, "levels": 2, "guardian": "troll"}],
	[&"sunderdeep_mine", "Sunderdeep Mine", Vector2(1100, 3300), WorldGen.Biome.REDWOOD, {"ore": Blocks.TIN_ORE, "rich": Blocks.RUBY_ORE, "levels": 2, "guardian": "troll"}],
]
const NEW_TOWERS := [["Elder Watch", Vector2(2300, 980)], ["Pass Tower", Vector2(2950, 1050)], ["Fjordwatch", Vector2(3980, 1250)],
		["Mesa Lookout", Vector2(3060, 2050)], ["Ashen Beacon", Vector2(1250, 2350)], ["Southwatch", Vector2(1700, 3400)]]
const NEW_RUINS := [["Giant's Stair", WorldGen.Biome.ALPINE], ["The Frozen Barrow", WorldGen.Biome.TUNDRA], ["Sunken Hall", WorldGen.Biome.FJORD],
		["Red Arches", WorldGen.Biome.CANYON], ["Cinder Temple", WorldGen.Biome.VOLCANIC], ["Elder Ring", WorldGen.Biome.REDWOOD],
		["Hollow Mesa", WorldGen.Biome.CANYON], ["Root Shrine", WorldGen.Biome.REDWOOD], ["Glass Fields", WorldGen.Biome.VOLCANIC],
		["Old Fjord Hall", WorldGen.Biome.FJORD]]


func _plan_new_lands(existing: Array[Location]) -> Array[Location]:
	var out: Array[Location] = []
	var lrng := RandomNumberGenerator.new()
	lrng.seed = gen.world_seed * 15485863 + 101
	var all: Array = existing.duplicate()
	for v: Array in NEW_VILLAGES:
		var p := _site(v[2], 260.0, [v[3]], 0.0, 0.16, all, 160.0, lrng)
		if p.x < 0.0:
			p = _site(v[2], 360.0, [], 0.0, 0.2, all, 160.0, lrng)
		if p.x < 0.0:
			continue
		var g := maxi(_ground(p.x, p.y), WorldGen.SEA_LEVEL + 2)
		var loc := Location.new(v[0], v[1], Location.Kind.VILLAGE, Vector3(p.x, g, p.y))
		loc.major = true
		Structures.village(loc, lrng, false)
		if v[3] in [WorldGen.Biome.ALPINE, WorldGen.Biome.FJORD, WorldGen.Biome.CANYON]:
			loc.pad_falloff = 40.0
		out.append(loc)
		all.append(loc)
		var shrine := _shrine(StringName(String(v[0]) + "_shrine"), "%s Shrine" % v[1], p + Vector2(0, 21))
		out.append(shrine)
		all.append(shrine)
	for m: Array in NEW_MINES:
		var locs := _full_mine(all, m[0], m[1], m[2], m[4], lrng, m[3])
		out.append_array(locs)
		all.append_array(locs)
	for i in NEW_TOWERS.size():
		var t: Array = NEW_TOWERS[i]
		var p := _site(t[1], 160.0, [], 0.0, 0.35, all, 110.0, lrng)
		if p.x < 0.0:
			continue
		var g := maxi(_ground(p.x, p.y), WorldGen.SEA_LEVEL + 2)
		var loc := Location.new(StringName("tower_e%d" % i), t[0], Location.Kind.TOWER, Vector3(p.x, g, p.y))
		Structures.tower(loc, lrng)
		out.append(loc)
		all.append(loc)
	for i in NEW_RUINS.size():
		var r: Array = NEW_RUINS[i]
		var p := Vector2(-1, -1)
		for attempt in 60:
			var q := Vector2(lrng.randf_range(300, gen.size - 300), lrng.randf_range(200, gen.size - 300))
			if gen.biome_at(int(q.x), int(q.y)) == r[1]:
				p = _site(q, 120.0, [r[1]], 0.0, 0.3, all, 120.0, lrng)
				if p.x >= 0.0:
					break
		if p.x < 0.0:
			continue
		var g := maxi(_ground(p.x, p.y), WorldGen.SEA_LEVEL + 2)
		var loc := Location.new(StringName("ruin_e%d" % i), r[0], Location.Kind.RUIN, Vector3(p.x, g, p.y))
		Structures.ruin(loc, lrng)
		out.append(loc)
		all.append(loc)
	return out


## Searches around `nominal` for ground of one of `biomes` (any if empty) whose slope over
## ~16 m lies in [min_slope, max_slope], dry and away from other places. (-1, -1) if none.
func _site(nominal: Vector2, radius: float, biomes: Array, min_slope: float, max_slope: float, others: Array, spacing: float, lrng: RandomNumberGenerator) -> Vector2:
	var best := Vector2(-1, -1)
	var best_score := INF
	for attempt in 70:
		var q := nominal if attempt == 0 else nominal + Vector2.from_angle(lrng.randf() * TAU) * radius * sqrt(lrng.randf())
		if not _inside(q, 120.0):
			continue
		if not biomes.is_empty() and not gen.biome_at(int(q.x), int(q.y)) in biomes:
			continue
		var g := float(_ground(q.x, q.y))
		if g < WorldGen.SEA_LEVEL + 4 or gen.lake_level(q.x, q.y).x > -INF:
			continue
		var slope := 0.0
		for k in 4:
			var o := Vector2.from_angle(TAU * k / 4.0) * 16.0
			slope = maxf(slope, absf(_ground(q.x + o.x, q.y + o.y) - g) / 16.0)
		if slope < min_slope or slope > max_slope:
			continue
		var ok := true
		for l: Location in others:
			if l.dimension == 0 and Vector2(l.center.x, l.center.z).distance_to(q) < spacing:
				ok = false
				break
		if not ok:
			continue
		var score := q.distance_to(nominal) + slope * 200.0
		if score < best_score:
			best_score = score
			best = q
	return best


## A full mine: a hillside portal (searched near `nominal`) and its workings.
func _full_mine(others: Array, id: StringName, mine_name: String, nominal: Vector2, spec: Dictionary, mrng: RandomNumberGenerator, biome := -1) -> Array[Location]:
	var p := _site(nominal, 220.0, [] if biome < 0 else [biome], 0.28, 0.95, others, 120.0, mrng)
	if p.x < 0.0:
		p = _site(nominal, 320.0, [], 0.18, 1.2, others, 90.0, mrng)
	if p.x < 0.0:
		return []
	var g := float(_ground(p.x, p.y))
	var grad := Vector2(_ground(p.x + 6, p.y) - _ground(p.x - 6, p.y), _ground(p.x, p.y + 6) - _ground(p.x, p.y - 6))
	var heading := grad.normalized() if grad.length() > 0.01 else Vector2.RIGHT
	var surface := Location.new(id, mine_name, Location.Kind.MINE, Vector3(p.x, g + 1.0, p.y))
	var depths := Location.new(StringName(String(id) + "_workings"), "%s Workings" % mine_name, Location.Kind.MINE, Vector3(p.x, g - 20.0, p.y))
	ExplorationSites.full_mine(surface, depths, gen, heading, mrng, spec)
	return [surface, depths]


static func roads(world_gen: WorldGen, locs: Array[Location] = []) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var by_id := {}
	for l in (locs if not locs.is_empty() else world_gen.locations):
		by_id[l.id] = l
	var hub := Vector2(world_gen.size * 0.5, world_gen.size * 0.5)
	var targets: Array = []
	if world_gen.dimension == WorldGen.Dimension.OVERWORLD:
		if by_id.has(&"emberfall"):
			hub = Vector2(by_id[&"emberfall"].center.x, by_id[&"emberfall"].center.z)
		for id: StringName in [&"ashford", &"thornwick", &"frosthold", &"mirewatch", &"cinderreach", &"silent_crypt", &"hall_shrine", &"keep_shrine", &"crater_shrine", &"tidewatch_shrine"]:
			if by_id.has(id):
				targets.append(by_id[id])
	else:
		if by_id.has(&"asphodel"):
			hub = Vector2(by_id[&"asphodel"].center.x, by_id[&"asphodel"].center.z)
		for id: StringName in [&"tartarus", &"throne_of_hades"]:
			if by_id.has(id):
				targets.append(by_id[id])
	var rng := RandomNumberGenerator.new()
	rng.seed = world_gen.world_seed + 4242
	var chains: Array = []
	if world_gen.revision >= 3 and world_gen.dimension == WorldGen.Dimension.OVERWORLD:
		# Over the land bridges to the new villages: [from, via (land-bridge waypoints), to].
		var east := [Vector2(1900, 1075), Vector2(2040, 1095), Vector2(2180, 1085)]
		var south := [Vector2(1010, 1990), Vector2(1050, 2140)]
		chains = [[&"thornwick", east, &"elderhollow"], [&"elderhollow", [], &"meadowmere"], [&"meadowmere", [], &"highmere"],
				[&"meadowmere", [], &"kaldvik"], [&"highmere", [], &"frostmark"], [&"meadowmere", [], &"redmesa"],
				[&"cinderreach", south, &"brimhold"], [&"brimhold", [], &"redcliff"], [&"brimhold", [], &"cedarfall"],
				[&"redcliff", [], &"sunderholm"]]
	for chain: Array in chains:
		if not by_id.has(chain[0]) or not by_id.has(chain[2]):
			continue
		var from: Location = by_id[chain[0]]
		var to: Location = by_id[chain[2]]
		var way: Array = [Vector2(from.center.x, from.center.z)]
		way.append_array(chain[1])
		way.append(Vector2(to.center.x, to.center.z))
		var pts := PackedVector2Array([way[0]])
		for k in way.size() - 1:
			var a: Vector2 = way[k]
			var b: Vector2 = way[k + 1]
			var n := maxi(2, int(a.distance_to(b) / 70.0))
			var side := (b - a).orthogonal().normalized()
			var bend := rng.randf_range(-30, 30) if a.distance_to(b) > 200.0 else 0.0
			for i in range(1, n):
				var f := float(i) / n
				pts.append(a.lerp(b, f) + side * sin(f * PI) * bend)
			pts.append(b)
		out.append(pts)
	for t: Location in targets:
		var end := Vector2(t.center.x, t.center.z)
		var pts := PackedVector2Array([hub])
		var n := maxi(2, int(hub.distance_to(end) / 70.0))
		var side := (end - hub).orthogonal().normalized()
		for i in range(1, n):
			var f := float(i) / n
			pts.append(hub.lerp(end, f) + side * sin(f * PI) * rng.randf_range(-40, 40))
		pts.append(end)
		out.append(pts)
	return out


# --- Revision 4: the sea -----------------------------------------------------------------------

## The ocean bosses' lairs, planned on their own random stream after everything else.
func _plan_sea(existing: Array[Location]) -> Array[Location]:
	var out: Array[Location] = []
	var srng := RandomNumberGenerator.new()
	srng.seed = gen.world_seed * 2750159 + 47
	var all: Array[Location] = existing.duplicate()
	for spec: Array in [[&"kraken_graveyard", "The Kraken's Graveyard", gen.KRAKEN_SITE, 30.0, &"wreckwatch_shrine", "Wreckwatch Shrine"],
			[&"maw_of_the_sea", "The Maw of the Sea", gen.MAELSTROM_SITE, 34.0, &"maelstrom_shrine", "Maelstrom Shrine"]]:
		var site := sea_lair_site(spec[2], float(spec[3]), all)
		if site.is_empty():
			continue
		var c: Vector2 = site["center"]
		var land: Vector2 = site["land"]
		var to_coast := (land - c).normalized()
		var loc := Location.new(spec[0], spec[1], Location.Kind.RUIN, Vector3(c.x, WorldGen.SEA_LEVEL + 2, c.y))
		loc.major = true
		var rim := 18.0
		if spec[0] == &"kraken_graveyard":
			SeaLairs.kraken(loc, to_coast, srng)
		else:
			SeaLairs.charybdis(loc, to_coast, srng)
			rim = 21.0
		# The causeway runs from the beach to the platform rim.
		Lairs.causeway(loc, land, c + to_coast * (rim - 1.5), srng)
		var shrine := _shrine(spec[4], spec[5], land + to_coast * 8.0)
		out.append(loc)
		out.append(shrine)
		all.append(loc)
		all.append(shrine)
	# Wrecks with their cargo, and drowned ruins crusted with coral, on the sea beds.
	for spec: Array in SEA_SITES:
		var p := _seabed_site(spec[2], spec[3], all, srng)
		if p.x < 0.0:
			continue
		var h := _ground(p.x, p.y)
		var loc := Location.new(spec[0], spec[1], Location.Kind.RUIN, Vector3(p.x, h + 1, p.y))
		loc.major = true
		if String(spec[0]).begins_with("wreck"):
			ExplorationSites.shipwreck(loc)
			for prop: Dictionary in loc.props:
				prop["sunken"] = true
			loc.add_spawn("chest", loc.center + Vector3(-1, 1.2, 1), {"tier": 3 if spec[2] in [WorldGen.Sea.ABYSS, WorldGen.Sea.FROZEN, WorldGen.Sea.VENTS] else 2})
		else:
			loc.center.y = h
			loc.ground_y = h
			Structures.ruin(loc, srng)
			for prop: Dictionary in loc.props:
				prop["sunken"] = true
			loc.add_spawn("chest", loc.center + Vector3(2.5, 1.0, 2.5), {"tier": 2})
			loc.add_spawn("enemy", loc.center + Vector3(-4, 1, 3), {"kind": "drowned"})
		out.append(loc)
		all.append(loc)
	return out


## Sea-bed sites (revision 4): id, name, ocean biome, nominal position.
const SEA_SITES := [
	[&"wreck_gilded_gull", "Wreck of the Gilded Gull", WorldGen.Sea.REEF, Vector2(300, 3100)],
	[&"wreck_widows_keel", "Wreck of the Widow's Keel", WorldGen.Sea.KELP, Vector2(2250, 2450)],
	[&"wreck_frostbound", "Wreck of the Frostbound", WorldGen.Sea.FROZEN, Vector2(4470, 1000)],
	[&"wreck_ashen_barque", "Wreck of the Ashen Barque", WorldGen.Sea.VENTS, Vector2(700, 2200)],
	[&"wreck_lantern_queen", "Wreck of the Lantern Queen", WorldGen.Sea.ABYSS, Vector2(3800, 2900)],
	[&"sunken_chapel", "The Sunken Chapel", WorldGen.Sea.SEAGRASS, Vector2(2250, 1900)],
	[&"drowned_manor", "The Drowned Manor", WorldGen.Sea.REEF, Vector2(1150, 4350)],
	[&"drowned_ring", "The Drowned Ring", WorldGen.Sea.SEAGRASS, Vector2(2500, 3600)],
]


## Level sea bed in ocean biome `sea` near `nominal`, 4-30 m down, away from other places.
func _seabed_site(sea: int, nominal: Vector2, others: Array[Location], srng: RandomNumberGenerator) -> Vector2:
	for attempt in 120:
		var q := nominal + Vector2.from_angle(srng.randf() * TAU) * srng.randf_range(0.0, 60.0 + attempt * 4.0)
		if not _inside(q, 80.0) or gen.sea_at(q.x, q.y) != sea:
			continue
		var g := float(_ground(q.x, q.y))
		if g > WorldGen.SEA_LEVEL - 4 or g < WorldGen.SEA_LEVEL - 30:
			continue
		var flat := true
		for k in 4:
			var o := Vector2.from_angle(TAU * k / 4.0) * 10.0
			if absf(_ground(q.x + o.x, q.y + o.y) - g) > 3.0:
				flat = false
				break
		if flat and _far_from(others, q, 120.0):
			return q
	return Vector2(-1, -1)


## A spot of open deep water near `nominal` (searched outwards) with a coast within reach:
## {"center": Vector2, "land": Vector2 (the beach the causeway starts from)}, or {}.
func sea_lair_site(nominal: Vector2, open_radius: float, others: Array[Location]) -> Dictionary:
	for ring in 16:
		var r := ring * 45.0
		var n := maxi(1, ring * 8)
		for k in n:
			var c := nominal + Vector2.from_angle(TAU * k / n + ring * 0.37) * r
			if not _inside(c, 120.0) or not _far_from(others, c, 230.0):
				continue
			var open := true
			for j in 16:
				var q := c + Vector2.from_angle(TAU * j / 16.0) * open_radius
				if gen.smooth_height(q.x, q.y) > WorldGen.SEA_LEVEL - 8 or gen.smooth_height(c.x, c.y) > WorldGen.SEA_LEVEL - 8:
					open = false
					break
			if not open:
				continue
			# The nearest beach along 24 headings, 45-170 m away.
			var best := Vector2(-1, -1)
			var best_d := INF
			for j in 24:
				var dir := Vector2.from_angle(TAU * j / 24.0)
				var d := open_radius + 15.0
				while d < 170.0:
					var q := c + dir * d
					if gen.smooth_height(q.x, q.y) > WorldGen.SEA_LEVEL + 2:
						if d < best_d:
							best_d = d
							best = q
						break
					d += 4.0
			if best_d < INF and _far_from(others, best, 90.0):
				return {"center": c, "land": best}
	return {}


# --- Hell ----------------------------------------------------------------------

func _plan_hell() -> Array[Location]:
	var out: Array[Location] = []
	var c := gen.center()
	var g := maxi(_ground(c.x, c.y), WorldGen.LAVA_LEVEL + 4)
	var spawn := Location.new(&"asphodel", "Asphodel Fields", Location.Kind.HELL_SPAWN, Vector3(c.x, g, c.y))
	spawn.radius = 24.0
	spawn.major = true
	Structures.hell_spawn(spawn)
	out.append(spawn)
	var tp := Vector2(c.x, c.y - 210)
	var tg := maxi(_ground(tp.x, tp.y), WorldGen.LAVA_LEVEL + 4)
	var tartarus := Location.new(&"tartarus", "Tartarus", Location.Kind.TARTARUS, Vector3(tp.x, tg, tp.y))
	tartarus.major = true
	Structures.tartarus(tartarus, rng)
	out.append(tartarus)
	var hp := Vector2(c.x, c.y + 220)
	var hg := maxi(_ground(hp.x, hp.y), WorldGen.LAVA_LEVEL + 4)
	var throne := Location.new(&"throne_of_hades", "Throne of Hades", Location.Kind.THRONE, Vector3(hp.x, hg, hp.y))
	throne.major = true
	Structures.throne(throne, rng)
	out.append(throne)
	for loc in out:
		loc.dimension = 1
	return out
