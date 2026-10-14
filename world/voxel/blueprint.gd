class_name Blueprint
extends RefCounted
## A box of blocks stamped into the world during chunk generation.
## Cell values: KEEP leaves the terrain alone, CARVE forces air, anything else
## is a block id. Builders below make writing structures pleasant.

const KEEP := 0
const CARVE := 255

var origin := Vector3i.ZERO  ## world-space min corner
var size := Vector3i.ONE
var data := PackedByteArray()


func _init(world_origin: Vector3i, box_size: Vector3i) -> void:
	origin = world_origin
	size = box_size
	data.resize(size.x * size.y * size.z)


func aabb() -> AABB:
	return AABB(Vector3(origin), Vector3(size))


func intersects_chunk(key: Vector3i) -> bool:
	var co := key * Chunk.SIZE
	return not (co.x >= origin.x + size.x or co.x + Chunk.SIZE <= origin.x
			or co.y >= origin.y + size.y or co.y + Chunk.SIZE <= origin.y
			or co.z >= origin.z + size.z or co.z + Chunk.SIZE <= origin.z)


## Local coordinates (relative to origin).
func set_local(x: int, y: int, z: int, block: int) -> void:
	if x < 0 or y < 0 or z < 0 or x >= size.x or y >= size.y or z >= size.z:
		return
	data[x + z * size.x + y * size.x * size.z] = block


func get_local(x: int, y: int, z: int) -> int:
	if x < 0 or y < 0 or z < 0 or x >= size.x or y >= size.y or z >= size.z:
		return KEEP
	return data[x + z * size.x + y * size.x * size.z]


func fill(from: Vector3i, to: Vector3i, block: int) -> void:
	for y in range(mini(from.y, to.y), maxi(from.y, to.y) + 1):
		for z in range(mini(from.z, to.z), maxi(from.z, to.z) + 1):
			for x in range(mini(from.x, to.x), maxi(from.x, to.x) + 1):
				set_local(x, y, z, block)


## Walls only (floor and ceiling optional).
func hollow(from: Vector3i, to: Vector3i, wall: int, floor_block := -1, ceiling := -1, inside := CARVE) -> void:
	fill(from, to, wall)
	fill(from + Vector3i(1, 1, 1), to - Vector3i(1, 1, 1), inside)
	if floor_block >= 0:
		fill(Vector3i(from.x, from.y, from.z), Vector3i(to.x, from.y, to.z), floor_block)
	if ceiling >= 0:
		fill(Vector3i(from.x, to.y, from.z), Vector3i(to.x, to.y, to.z), ceiling)


func cylinder(center: Vector3i, radius: float, height: int, block: int, hollow_inside := false) -> void:
	var r := int(ceil(radius))
	for y in height:
		for z in range(-r, r + 1):
			for x in range(-r, r + 1):
				var d := sqrt(float(x * x + z * z))
				if d <= radius:
					if hollow_inside and d < radius - 1.0:
						set_local(center.x + x, center.y + y, center.z + z, CARVE)
					else:
						set_local(center.x + x, center.y + y, center.z + z, block)


func sphere(center: Vector3i, radius: float, block: int) -> void:
	var r := int(ceil(radius))
	for y in range(-r, r + 1):
		for z in range(-r, r + 1):
			for x in range(-r, r + 1):
				if x * x + y * y + z * z <= radius * radius:
					set_local(center.x + x, center.y + y, center.z + z, block)


func ellipsoid(center: Vector3i, radii: Vector3, block: int) -> void:
	for y in range(-int(radii.y), int(radii.y) + 1):
		for z in range(-int(radii.z), int(radii.z) + 1):
			for x in range(-int(radii.x), int(radii.x) + 1):
				var v := Vector3(x / radii.x, y / radii.y, z / radii.z)
				if v.length_squared() <= 1.0:
					set_local(center.x + x, center.y + y, center.z + z, block)


## Gabled roof over a rectangle, ridge along x.
func gable_roof(from: Vector3i, to: Vector3i, block: int) -> void:
	var depth := to.z - from.z
	var half := depth / 2
	for i in half + 1:
		fill(Vector3i(from.x, from.y + i, from.z + i), Vector3i(to.x, from.y + i, from.z + i), block)
		fill(Vector3i(from.x, from.y + i, to.z - i), Vector3i(to.x, from.y + i, to.z - i), block)
		# gable ends
		if i > 0:
			fill(Vector3i(from.x, from.y + i, from.z + i + 1), Vector3i(from.x, from.y + i, to.z - i - 1), block)
			fill(Vector3i(to.x, from.y + i, from.z + i + 1), Vector3i(to.x, from.y + i, to.z - i - 1), block)


## Battlements along the top edge of a wall running from `from` to `to` (y = top).
func crenellate(from: Vector3i, to: Vector3i, block: int) -> void:
	var length := maxi(absi(to.x - from.x), absi(to.z - from.z))
	for i in length + 1:
		if i % 2 == 0:
			var t := float(i) / maxf(1.0, length)
			var p := Vector3i(Vector3(from).lerp(Vector3(to), t).round())
			set_local(p.x, p.y + 1, p.z, block)
