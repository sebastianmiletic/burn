class_name WildSpawner
extends Node
## Server: roaming monsters around players. More at night, in deep caves and
## in the underworld; none inside villages.

const CHECK_SECONDS := 4.0
const DESPAWN_DISTANCE := 85.0

var _timer := 0.0


func gw() -> GameWorld:
	return get_parent() as GameWorld


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
		_maybe_spawn_near(w, p)


func _despawn_far(w: GameWorld) -> void:
	for e in w.all_entities():
		if not (e is Entity) or not (e as Entity).has_meta("wild"):
			continue
		var ent := e as Entity
		var near := w.nearest_player(ent.global_position, ent.dimension, DESPAWN_DISTANCE)
		if near == null and not ent.dead:
			w.despawn_entity(ent)


func _maybe_spawn_near(w: GameWorld, p: Player) -> void:
	var vw := w.world_for(p.dimension)
	var here := w.location_at(p.global_position, p.dimension)
	if here != null and (here.kind == Location.Kind.VILLAGE or here.kind == Location.Kind.SHRINE):
		return
	var surface := vw.gen.surface_height(int(p.global_position.x), int(p.global_position.z))
	var underground := p.global_position.y < surface - 8
	var night := w.sky.darkness() > 0.5
	var cap := 0
	var kinds: Array[String] = []
	if p.dimension == 1:
		cap = 6
		kinds.assign(["imp", "imp", "shade"])
	elif underground:
		cap = 5
		kinds.assign(["skeleton", "ghoul", "skeleton"] if p.global_position.y > -60 else ["ghoul", "imp", "skeleton"])
	elif night:
		cap = 5
		var biome := vw.gen.biome_at(int(p.global_position.x), int(p.global_position.z))
		kinds.assign(["skeleton", "ghoul", "archer"])
		if biome == WorldGen.Biome.PEAKS:
			kinds.append("troll")
	else:
		cap = 1
		kinds.assign(["skeleton"])
	var count := 0
	for e in w.entities_near(p.global_position, 50.0, p.dimension, Entity.Team.MONSTERS):
		count += 1
	if count >= cap or randf() > 0.55:
		return
	var pos := _find_spot(vw, p.global_position, underground)
	if pos == Vector3.INF:
		return
	if w.location_at(pos, p.dimension) != null and w.location_at(pos, p.dimension).kind == Location.Kind.VILLAGE:
		return
	var e := w.spawn_entity(kinds[randi() % kinds.size()], pos, p.dimension, {})
	if e != null:
		e.set_meta("wild", true)


func _find_spot(vw: VoxelWorld, around: Vector3, underground: bool) -> Vector3:
	for attempt in 6:
		var a := randf() * TAU
		var r := randf_range(22.0, 36.0)
		var x := int(around.x + cos(a) * r)
		var z := int(around.z + sin(a) * r)
		if not vw.is_loaded(Vector3i(x, int(around.y), z)):
			continue
		if not underground:
			var y := vw.surface_y(x, z)
			var top := vw.get_block(Vector3i(x, y, z))
			if top < 0 or Blocks.is_liquid(top) or not Blocks.is_solid(top):
				continue
			if vw.is_solid(Vector3i(x, y + 1, z)) or vw.is_solid(Vector3i(x, y + 2, z)):
				continue
			return Vector3(x + 0.5, y + 1.02, z + 0.5)
		# Caves: look for a floor with two air blocks above near the player's depth.
		for dy in range(8, -9, -1):
			var y := int(around.y) + dy
			var floor_b := vw.get_block(Vector3i(x, y - 1, z))
			if floor_b > 0 and Blocks.is_solid(floor_b) and vw.get_block(Vector3i(x, y, z)) == Blocks.AIR and vw.get_block(Vector3i(x, y + 1, z)) == Blocks.AIR:
				return Vector3(x + 0.5, y + 0.02, z + 0.5)
	return Vector3.INF
