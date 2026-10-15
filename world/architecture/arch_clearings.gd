class_name ArchClearings
extends RefCounted
## Ground that architecture keeps clear of grass and bushes: paved squares,
## paths, building footprints, yards. Filled while locations are planned
## (before any chunk streams), then only read, by Flora.plan_chunk on worker
## threads. Keyed by dimension and world seed so the menu backdrop's world and
## the game's world never mix.

static var _sets := {}   # Vector2i(dimension, seed) -> {Vector2i cell: true}


static func _set_for(dim: int, seed_value: int) -> Dictionary:
	var key := Vector2i(dim, seed_value)
	if not _sets.has(key):
		_sets[key] = {}
	return _sets[key]


static func reset(dim: int, seed_value: int) -> void:
	_sets.erase(Vector2i(dim, seed_value))


static func is_clear(dim: int, seed_value: int, x: int, z: int) -> bool:
	var cells: Variant = _sets.get(Vector2i(dim, seed_value))
	return cells != null and (cells as Dictionary).has(Vector2i(x, z))


static func add_rect(dim: int, seed_value: int, r: Rect2) -> void:
	var cells := _set_for(dim, seed_value)
	for z in range(floori(r.position.y), ceili(r.end.y)):
		for x in range(floori(r.position.x), ceili(r.end.x)):
			cells[Vector2i(x, z)] = true


static func add_disc(dim: int, seed_value: int, c: Vector2, radius: float) -> void:
	var cells := _set_for(dim, seed_value)
	for z in range(floori(c.y - radius), ceili(c.y + radius) + 1):
		for x in range(floori(c.x - radius), ceili(c.x + radius) + 1):
			if Vector2(x + 0.5, z + 0.5).distance_to(c) <= radius:
				cells[Vector2i(x, z)] = true


## A polyline of world xz points, `width` wide.
static func add_path(dim: int, seed_value: int, pts: PackedVector2Array, width: float) -> void:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var n := maxi(1, int(a.distance_to(b) / 0.5))
		for k in n + 1:
			add_disc(dim, seed_value, a.lerp(b, float(k) / n), width * 0.5)
