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
	if gen.revision >= 2:
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
				out.append(wreck)
				wreck_count += 1
				if wreck_count == 4:
					break
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
		var islet := c + d * (r + 60.0)
		if not _far_from(existing, islet, 170.0) or not _far_from(existing, c + d * (r_land - 8.0), 70.0):
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
