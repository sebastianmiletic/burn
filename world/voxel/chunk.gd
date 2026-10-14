class_name Chunk
extends RefCounted
## Chunk geometry constants and index helpers. Chunk data itself is a plain
## PackedByteArray of SIZE^3 block ids (index = x + z*16 + y*256) so it can be
## passed to worker threads cheaply (copy-on-write).

const SIZE := 16
const AREA := 256
const VOLUME := 4096


static func index(x: int, y: int, z: int) -> int:
	return x + z * SIZE + y * AREA


static func key_of(block: Vector3i) -> Vector3i:
	return Vector3i(floori(block.x / 16.0), floori(block.y / 16.0), floori(block.z / 16.0))


static func origin(key: Vector3i) -> Vector3i:
	return key * SIZE


static func local(block: Vector3i) -> Vector3i:
	return Vector3i(posmod(block.x, SIZE), posmod(block.y, SIZE), posmod(block.z, SIZE))


static func empty() -> PackedByteArray:
	var a := PackedByteArray()
	a.resize(VOLUME)
	return a


static func is_all(data: PackedByteArray, value: int) -> bool:
	# Fast path for the very common all-air / all-stone chunks.
	if data.is_empty():
		return value == 0
	if data[0] != value or data[VOLUME - 1] != value:
		return false
	return data.count(value) == VOLUME
