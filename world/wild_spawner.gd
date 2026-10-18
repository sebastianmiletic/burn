class_name WildSpawner
extends Node
## Server: the life around each player, chosen by biome, depth and time of
## day. Two separate budgets:
##   * hostiles - wolves and bears in Emberwood, frost wolves in the peaks,
##     bog lurkers in Blackmarsh, scorpions and fire elementals in the wastes,
##     sharks in the sea, spiders / bats / crawlers / golems by cave depth,
##     the undead at night, hellhounds and imps below. Packs spawn together.
##   * wildlife - deer, stags, rabbits, goats and boars, bird flocks (gulls
##     on the coast, crows over the marsh and wastes), fish schools in any
##     water, bat swarms in caves. Fewer at night.
## None inside villages or other locations (they bring their own); anything
## spawned here despawns once every player is far away.

const CHECK_SECONDS := 4.0
const DESPAWN_DISTANCE := 90.0
const HOSTILE_RADIUS := 55.0
const ANIMAL_RADIUS := 70.0

## [kind, weight, pack_min, pack_max]
const SURFACE_DAY := {
	WorldGen.Biome.PLAINS: [["wolf", 0.4, 2, 3], ["skeleton", 0.3, 1, 1]],
	WorldGen.Biome.FOREST: [["wolf", 1.0, 2, 4], ["bear", 0.5, 1, 1], ["giant_spider", 0.4, 1, 2], ["boar", 0.0, 1, 1]],
	WorldGen.Biome.PEAKS: [["frost_wolf", 1.0, 2, 3], ["troll", 0.3, 1, 1]],
	WorldGen.Biome.MARSH: [["bog_lurker", 0.8, 1, 1], ["ghoul", 0.4, 1, 2]],
	WorldGen.Biome.WASTES: [["scorpion", 1.0, 1, 2], ["fire_elemental", 0.2, 1, 1]],
	WorldGen.Biome.OCEAN: [["drowned", 0.2, 1, 1]],
	WorldGen.Biome.REDWOOD: [["wolf", 0.7, 2, 3], ["bear", 0.8, 1, 1], ["giant_spider", 0.3, 1, 1]],
	WorldGen.Biome.CANYON: [["scorpion", 1.0, 1, 3], ["archer", 0.3, 1, 2], ["fire_elemental", 0.15, 1, 1]],
	WorldGen.Biome.ALPINE: [["frost_wolf", 0.8, 2, 3], ["troll", 0.4, 1, 1], ["bear", 0.3, 1, 1]],
	WorldGen.Biome.TUNDRA: [["frost_wolf", 1.0, 2, 4], ["dire_wolf", 0.3, 1, 2]],
	WorldGen.Biome.VOLCANIC: [["fire_elemental", 0.9, 1, 2], ["scorpion", 0.5, 1, 2], ["imp", 0.3, 1, 2]],
	WorldGen.Biome.FJORD: [["wolf", 0.6, 2, 3], ["troll", 0.3, 1, 1], ["drowned", 0.3, 1, 1]],
}
const SURFACE_NIGHT := {
	WorldGen.Biome.PLAINS: [["skeleton", 1.0, 1, 2], ["ghoul", 0.8, 1, 1], ["archer", 0.6, 1, 1], ["wolf", 0.6, 2, 4]],
	WorldGen.Biome.FOREST: [["wolf", 1.0, 2, 4], ["dire_wolf", 0.6, 1, 3], ["giant_spider", 0.8, 1, 2], ["skeleton", 0.5, 1, 1], ["bear", 0.3, 1, 1]],
	WorldGen.Biome.PEAKS: [["frost_wolf", 1.0, 2, 4], ["troll", 0.6, 1, 1], ["skeleton", 0.4, 1, 1]],
	WorldGen.Biome.MARSH: [["ghoul", 1.0, 1, 2], ["bog_lurker", 0.8, 1, 1], ["drowned", 0.7, 1, 2], ["skeleton", 0.3, 1, 1]],
	WorldGen.Biome.WASTES: [["scorpion", 0.8, 1, 2], ["fire_elemental", 0.7, 1, 1], ["skeleton", 0.6, 1, 2], ["archer", 0.5, 1, 1]],
	WorldGen.Biome.OCEAN: [["drowned", 1.0, 1, 3]],
	WorldGen.Biome.REDWOOD: [["dire_wolf", 0.8, 2, 3], ["giant_spider", 0.9, 1, 3], ["bear", 0.4, 1, 1], ["skeleton", 0.4, 1, 2]],
	WorldGen.Biome.CANYON: [["skeleton", 0.8, 1, 2], ["archer", 0.8, 1, 2], ["scorpion", 0.8, 1, 2], ["ghoul", 0.3, 1, 1]],
	WorldGen.Biome.ALPINE: [["frost_wolf", 1.0, 2, 4], ["troll", 0.7, 1, 1], ["skeleton", 0.3, 1, 1]],
	WorldGen.Biome.TUNDRA: [["frost_wolf", 1.0, 2, 4], ["dire_wolf", 0.6, 2, 3], ["shade", 0.3, 1, 1]],
	WorldGen.Biome.VOLCANIC: [["fire_elemental", 1.0, 1, 2], ["imp", 0.8, 1, 3], ["hellhound", 0.5, 2, 3]],
	WorldGen.Biome.FJORD: [["drowned", 0.8, 1, 2], ["skeleton", 0.5, 1, 2], ["frost_wolf", 0.6, 2, 3], ["troll", 0.3, 1, 1]],
}
const WATER := [["shark", 1.0, 1, 2], ["sea_serpent", 0.2, 1, 1]]
const CAVE_SHALLOW := [["skeleton", 0.8, 1, 1], ["ghoul", 0.6, 1, 1], ["giant_spider", 0.9, 1, 2], ["cave_bat", 0.8, 2, 4]]
const CAVE_MID := [["giant_spider", 1.0, 1, 3], ["cave_crawler", 0.7, 1, 1], ["cave_bat", 0.6, 2, 4], ["ghoul", 0.4, 1, 1], ["skeleton", 0.4, 1, 1]]
const CAVE_DEEP := [["cave_crawler", 1.0, 1, 2], ["rock_golem", 0.7, 1, 1], ["fire_elemental", 0.4, 1, 1], ["ghoul", 0.3, 1, 1], ["imp", 0.3, 1, 1]]
## Extra hostiles by cave biome (CaveBiomes.Kind), mixed into the depth tables.
const CAVE_KIND := {
	CaveBiomes.Kind.FUNGAL: [["giant_spider", 1.0, 1, 3], ["cave_crawler", 0.6, 1, 1]],
	CaveBiomes.Kind.FROST: [["frost_wolf", 0.6, 1, 2], ["rock_golem", 0.4, 1, 1]],
	CaveBiomes.Kind.GEYSER: [["fire_elemental", 0.5, 1, 1], ["cave_crawler", 0.5, 1, 1]],
	CaveBiomes.Kind.MAGMA: [["fire_elemental", 1.0, 1, 2], ["imp", 0.7, 1, 2], ["rock_golem", 0.5, 1, 1]],
	CaveBiomes.Kind.FLOODED: [["drowned", 1.0, 1, 2], ["bog_lurker", 0.6, 1, 1], ["cave_bat", 0.4, 2, 3]],
}
const HELL := [["imp", 1.0, 1, 2], ["shade", 0.4, 1, 1], ["hellhound", 0.7, 2, 3], ["fire_elemental", 0.4, 1, 1]]

const ANIMALS := {
	WorldGen.Biome.PLAINS: [["rabbit", 1.0], ["deer", 0.6], ["bird_flock", 0.9], ["boar", 0.2]],
	WorldGen.Biome.FOREST: [["deer", 1.0], ["stag", 0.4], ["rabbit", 0.6], ["boar", 0.5], ["bird_flock", 0.8], ["crow_flock", 0.2]],
	WorldGen.Biome.PEAKS: [["goat", 1.0], ["crow_flock", 0.3]],
	WorldGen.Biome.MARSH: [["crow_flock", 0.8], ["rabbit", 0.2], ["fish_school", 0.8]],
	WorldGen.Biome.WASTES: [["crow_flock", 0.7], ["rabbit", 0.2]],
	WorldGen.Biome.OCEAN: [["gull_flock", 1.0], ["fish_school", 1.0]],
	WorldGen.Biome.REDWOOD: [["deer", 1.0], ["stag", 0.6], ["boar", 0.5], ["rabbit", 0.4], ["bird_flock", 0.6]],
	WorldGen.Biome.CANYON: [["goat", 0.8], ["rabbit", 0.4], ["crow_flock", 0.6]],
	WorldGen.Biome.ALPINE: [["goat", 1.0], ["deer", 0.5], ["bird_flock", 0.5], ["fish_school", 0.3]],
	WorldGen.Biome.TUNDRA: [["deer", 0.8], ["rabbit", 0.6], ["crow_flock", 0.4]],
	WorldGen.Biome.VOLCANIC: [["crow_flock", 1.0]],
	WorldGen.Biome.FJORD: [["goat", 0.8], ["gull_flock", 1.0], ["fish_school", 0.8], ["deer", 0.4]],
}

var _timer := 0.0
var _rng := RandomNumberGenerator.new()


func gw() -> GameWorld:
	return get_parent() as GameWorld


func _ready() -> void:
	_rng.randomize()


func _process(delta: float) -> void:
	if not Net.is_server():
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_SECONDS
	var w := gw()
	_despawn_far(w)
	for p in w.players_in(-1):
		if p.dead:
			continue
		_populate(w, p)


func _despawn_far(w: GameWorld) -> void:
	for e in w.all_entities():
		if not (e is Entity) or not (e as Entity).has_meta("wild"):
			continue
		var ent := e as Entity
		if ent.dead:
			continue
		if ent.dimension == 0 and w.gen_for(0).revision >= 2 and CaveBiomes.sanctuary(ent.global_position, w.gen_for(0).world_seed, w.gen_for(0).revision):
			w.despawn_entity(ent)
			continue
		if w.nearest_player(ent.global_position, ent.dimension, DESPAWN_DISTANCE) == null:
			w.despawn_entity(ent)


func _count(w: GameWorld, p: Player, role: String, radius: float) -> int:
	var n := 0
	for e in w.entities_near(p.global_position, radius, p.dimension):
		if e.has_meta("wild") and String(e.get_meta("wild_role", "hostile")) == role:
			n += 1
		elif role == "hostile" and e.team == Entity.Team.MONSTERS and not e.has_meta("wild") and not e is Wildlife:
			n += 1  # location monsters count against the budget too
	return n


func _populate(w: GameWorld, p: Player) -> void:
	var vw := w.world_for(p.dimension)
	if vw == null:
		return
	var here := w.location_at(p.global_position, p.dimension)
	if here != null and here.kind in [Location.Kind.VILLAGE, Location.Kind.SHRINE]:
		return
	var pos := p.global_position
	var night := w.sky.darkness() > 0.5 if w.sky != null else false
	if p.dimension >= 2:
		return  # The floating isles have curated encounters; Ogygia is at peace.
	if p.dimension == 1:
		_spawn_hostiles(w, p, HELL, 7, "cave")
		return
	var surface := float(vw.gen.call("ground_level", pos.x, pos.z)) if vw.gen.has_method("ground_level") else float(vw.gen.surface_height(int(pos.x), int(pos.z)))
	var underground := pos.y < surface - 8
	if underground:
		if vw.gen.revision >= 2 and CaveBiomes.sanctuary(pos, vw.gen.world_seed, vw.gen.revision):
			return
		var table: Array = CAVE_SHALLOW if pos.y > -20 else (CAVE_MID if pos.y > -60 else CAVE_DEEP)
		if vw.gen.revision >= 3 and pos.y < -8:
			table = table + CAVE_KIND.get(CaveBiomes.kind_at(pos, vw.gen.world_seed, vw.gen.revision), [])
		_spawn_hostiles(w, p, table, 5 if pos.y > -20 else 6, "cave")
		if _rng.randf() < 0.15:
			_spawn_animals(w, p, [["bat_swarm", 1.0]], 1, "cave")
		return
	var biome := vw.gen.biome_at(int(pos.x), int(pos.z))
	var in_sea := biome == WorldGen.Biome.OCEAN or _water_depth(vw, Vector3i(pos.floor())) > 1
	if in_sea and _rng.randf() < 0.6:
		_spawn_hostiles(w, p, WATER, 3, "water")
	var table: Array = (SURFACE_NIGHT if night else SURFACE_DAY).get(biome, [])
	_spawn_hostiles(w, p, table, 5 if night else 2, "surface")
	var animals: Array = ANIMALS.get(biome, [])
	_spawn_animals(w, p, animals, 3 if night else 6, "surface")


func _pick(table: Array) -> Array:
	var total := 0.0
	for t: Array in table:
		total += float(t[1])
	if total <= 0.0:
		return []
	var r := _rng.randf() * total
	for t: Array in table:
		r -= float(t[1])
		if r <= 0.0:
			return t
	return table[table.size() - 1]


func _spawn_hostiles(w: GameWorld, p: Player, table: Array, cap: int, where: String) -> void:
	if table.is_empty() or _count(w, p, "hostile", HOSTILE_RADIUS) >= cap or _rng.randf() > 0.55:
		return
	var pick := _pick(table)
	if pick.is_empty():
		return
	var kind: String = pick[0]
	var spot_mode := where
	if kind in ["shark", "sea_serpent"]:
		spot_mode = "water"
	elif where == "water":
		return
	var pos := _find_spot(w.world_for(p.dimension), p.global_position, spot_mode, 22.0, 36.0, 4 if kind == "sea_serpent" else 2)
	if pos == Vector3.INF or _in_location(w, pos, p.dimension) or (p.dimension == 0 and w.gen_for(0).revision >= 2 and CaveBiomes.sanctuary(pos, w.gen_for(0).world_seed, w.gen_for(0).revision)):
		return
	var n := _rng.randi_range(int(pick[2]), int(pick[3]))
	for i in n:
		var off := Vector3(_rng.randf_range(-2.5, 2.5), 0, _rng.randf_range(-2.5, 2.5)) if i > 0 else Vector3.ZERO
		var e := w.spawn_entity(kind, pos + off, p.dimension, {})
		if e != null:
			e.set_meta("wild", true)
			e.set_meta("wild_role", "hostile")


func _spawn_animals(w: GameWorld, p: Player, table: Array, cap: int, where: String) -> void:
	if table.is_empty() or _count(w, p, "animal", ANIMAL_RADIUS) >= cap or _rng.randf() > 0.6:
		return
	var pick := _pick(table)
	if pick.is_empty():
		return
	var kind: String = pick[0]
	var mode := where
	if kind == "fish_school":
		mode = "water"
	var pos := _find_spot(w.world_for(p.dimension), p.global_position, mode, 24.0, 45.0, 2)
	if pos == Vector3.INF:
		return
	var here := w.location_at(pos, p.dimension)
	if here != null and here.kind == Location.Kind.VILLAGE and not kind.ends_with("flock"):
		return
	if kind == "bat_swarm":
		pos.y += 2.5
	var herd := 1
	if kind in ["deer", "goat"]:
		herd = _rng.randi_range(1, 3)
	elif kind == "rabbit":
		herd = _rng.randi_range(1, 2)
	for i in herd:
		var off := Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3)) if i > 0 else Vector3.ZERO
		var e := w.spawn_entity(kind, pos + off, p.dimension, {})
		if e != null:
			e.set_meta("wild", true)
			e.set_meta("wild_role", "animal")


func _in_location(w: GameWorld, pos: Vector3, dim: int) -> bool:
	return w.location_at(pos, dim) != null


## Depth of water at a column whose surface is at or below `p`.
func _water_depth(vw: VoxelWorld, p: Vector3i) -> int:
	var depth := 0
	for dy in range(0, 30):
		var b := vw.get_block(p - Vector3i(0, dy, 0))
		if b < 0:
			break
		if b > 0 and Blocks.is_liquid(b) and b != Blocks.LAVA:
			depth += 1
		elif depth > 0 or (b > 0 and Blocks.is_solid(b)):
			break
	return depth


## mode: "surface" (open ground), "cave" (a floor near the player's depth),
## "water" (inside water at least `min_depth` deep; returns a mid-depth point).
func _find_spot(vw: VoxelWorld, around: Vector3, mode: String, r_min: float, r_max: float, min_depth := 2) -> Vector3:
	if vw == null:
		return Vector3.INF
	for attempt in 8:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(r_min, r_max)
		var x := int(around.x + cos(a) * r)
		var z := int(around.z + sin(a) * r)
		if not vw.is_loaded(Vector3i(x, int(around.y), z)):
			continue
		match mode:
			"surface":
				if vw.has_method("ground_below"):
					# Smooth terrain (lead's VoxelWorld): exact ground height, skip buried / missing ground.
					var gy: float = vw.call("ground_below", float(x) + 0.5, around.y + 30.0, float(z) + 0.5, 70.0)
					if not is_finite(gy):
						continue
					var cell := Vector3i(x, int(floor(gy + 0.2)), z)
					var below := vw.get_block(cell - Vector3i(0, 1, 0))
					if below > 0 and Blocks.is_liquid(below):
						continue
					if vw.is_solid(cell + Vector3i(0, 1, 0)) or vw.is_solid(cell + Vector3i(0, 2, 0)):
						continue
					return Vector3(x + 0.5, gy + 0.05, z + 0.5)
				var y := vw.surface_y(x, z)
				var top := vw.get_block(Vector3i(x, y, z))
				if top < 0 or Blocks.is_liquid(top) or not Blocks.is_solid(top):
					continue
				if vw.is_solid(Vector3i(x, y + 1, z)) or vw.is_solid(Vector3i(x, y + 2, z)):
					continue
				return Vector3(x + 0.5, y + 1.02, z + 0.5)
			"water":
				var top_y := WorldGen.SEA_LEVEL if around.y < WorldGen.SEA_LEVEL + 30 else int(around.y)
				var y := vw.surface_y(x, z)
				var top := vw.get_block(Vector3i(x, y, z))
				var start := y if (top > 0 and Blocks.is_liquid(top)) else top_y
				var depth := _water_depth(vw, Vector3i(x, start, z))
				if depth < min_depth:
					continue
				return Vector3(x + 0.5, start - depth * 0.5, z + 0.5)
			_:
				for dy in range(8, -9, -1):
					var y := int(around.y) + dy
					var floor_b := vw.get_block(Vector3i(x, y - 1, z))
					if floor_b > 0 and Blocks.is_solid(floor_b) and vw.get_block(Vector3i(x, y, z)) == Blocks.AIR and vw.get_block(Vector3i(x, y + 1, z)) == Blocks.AIR:
						return Vector3(x + 0.5, y + 0.02, z + 0.5)
	return Vector3.INF
