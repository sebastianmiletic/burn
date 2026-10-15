class_name ArchBuild
extends RefCounted
## Everything one location's architecture builds on a worker thread: meshes by
## level of detail, and lists of lights / smoke / fires / instanced props for
## the main thread to instantiate. Positions are local to `origin` (the node).

## Walls, roofs, frames, chimneys: drawn to SHELL_RANGE.
var shell := ArchMesh.new()
## Windows, doors, trims, small exterior props: drawn to DETAIL_RANGE.
var detail := ArchMesh.new()
## Furniture and interior faces: drawn to INTERIOR_RANGE, no shadows.
var interior := ArchMesh.new()
## The cheap far silhouette: from FAR_BEGIN to FAR_RANGE.
var far := ArchMesh.new()

const SHELL_RANGE := 260.0
const DETAIL_RANGE := 95.0
const INTERIOR_RANGE := 55.0
const FAR_BEGIN := 230.0
const FAR_RANGE := 1700.0

## {pos, color, range, energy, night (only lit at night)}
var lights: Array = []
## {pos, strength}
var smoke: Array = []
## {pos, size, range, energy}
var fires: Array = []

var origin := Vector3.ZERO
var gen: WorldGen
var _detail_noise: FastNoiseLite
var _ridge_noise: FastNoiseLite
## Only the far silhouette is wanted (cheap pass for distant places).
var far_only := false
## Deterministic per-location stream for variation.
var rng := RandomNumberGenerator.new()
## Building footprint rectangles (node space, xz) for ground-hugging props to avoid.
var keep_out: Array[Rect2] = []


func _init(world_gen: WorldGen, node_origin: Vector3, seed_value: int) -> void:
	gen = world_gen
	origin = node_origin
	rng.seed = seed_value
	if gen != null:
		_detail_noise = gen.make_detail_noise()
		_ridge_noise = gen.make_ridge_noise()


var _columns := {}


## Smooth ground height (world y) at world x, z, ignoring edits. Thread-safe:
## uses this build's own noise objects and column cache.
func ground_world(x: float, z: float) -> float:
	if gen == null:
		return origin.y
	var ix := floori(x)
	var iz := floori(z)
	var tx := x - ix
	var tz := z - iz
	var a := lerpf(_column(ix, iz), _column(ix + 1, iz), tx)
	var b := lerpf(_column(ix, iz + 1), _column(ix + 1, iz + 1), tx)
	return lerpf(a, b, tz) + 1.0


func _column(ix: int, iz: int) -> float:
	var key := Vector2i(ix, iz)
	var h: Variant = _columns.get(key)
	if h != null:
		return h
	# Fully flattened building pads need no noise.
	var pad: Variant = gen._pads.get(ix + iz * gen.size) if gen.in_bounds(ix, iz) else null
	var v := 0.0
	if pad != null and (pad as Vector3).y >= 0.999:
		v = (pad as Vector3).x
	else:
		v = gen.column_f(ix, iz, _detail_noise, _ridge_noise).x
	_columns[key] = v
	return v


## Ground height in node space at a node-space position.
func ground(p: Vector3) -> float:
	return ground_world(p.x + origin.x, p.z + origin.z) - origin.y


func meshes() -> Array[ArchMesh]:
	return [shell, detail, interior, far]


func push(t: Transform3D) -> void:
	for m in meshes():
		m.push(t)


func pop() -> void:
	for m in meshes():
		m.pop()


## Current shell transform (the frame everything is being emitted in).
func frame() -> Transform3D:
	return shell.xf


func dirt(y: float, h: float, amount := 0.45) -> void:
	for m in meshes():
		m.dirt_y = y
		m.dirt_h = h
		m.dirt_amount = amount


func snow(amount: float) -> void:
	for m in meshes():
		m.snow = amount


func add_light(local_pos: Vector3, color: Color, light_range: float, energy: float, night_only := true) -> void:
	lights.append({"pos": frame() * local_pos, "color": color, "range": light_range, "energy": energy, "night": night_only})


func add_smoke(local_pos: Vector3, strength := 1.0) -> void:
	smoke.append({"pos": frame() * local_pos, "strength": strength})


func add_fire(local_pos: Vector3, size := 1.0, light_range := 6.0, energy := 1.6) -> void:
	fires.append({"pos": frame() * local_pos, "size": size, "range": light_range, "energy": energy})
