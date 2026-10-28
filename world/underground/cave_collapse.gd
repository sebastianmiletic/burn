class_name CaveCollapse
extends Node
## Server: the roof of a cavern falling in (the Everbloom cavern once its tree dies).
## For DURATION seconds rubble piles up on the floor around `center` and falling rock
## hurts anyone still inside. Added to GameWorld by Everbloom._on_died; frees itself.

const DURATION := 14.0
const STEP := 0.35
const PILE := Blocks.SCREE

var center := Vector3.ZERO
var radius := 40.0
var floor_y := 0.0
var dimension := 0
var _left := DURATION
var _next := 0.0
var _rng := RandomNumberGenerator.new()


func setup(c: Vector3, r: float, floor_level: float, dim: int, seed_value: int) -> CaveCollapse:
	center = c
	radius = r
	floor_y = floor_level
	dimension = dim
	_rng.seed = seed_value
	return self


## Where the next pile of rubble lands (deterministic per seed; inside the cavern).
func next_point() -> Vector3:
	var a := _rng.randf() * TAU
	var d := sqrt(_rng.randf()) * radius
	return Vector3(center.x + cos(a) * d, floor_y + _rng.randf_range(0.6, 2.0), center.z + sin(a) * d)


func _process(delta: float) -> void:
	_left -= delta
	_next -= delta
	if _left <= 0.0:
		queue_free()
		return
	if _next > 0.0:
		return
	_next = STEP
	var w := GameWorld.instance
	if w == null or not Net.is_server():
		return
	var vw := w.world_for(dimension)
	if vw == null:
		return
	var p := next_point()
	var near := false
	for e in w.entities_near(p, 2.5, dimension):
		if e is Player:
			near = true
	if not near:
		var changes := vw.plan_fill(p, 1.2, PILE)
		if not changes.is_empty():
			w.replicator.broadcast_voxels(changes, dimension)
	for pl in w.players_in(dimension):
		if not pl.dead and pl.global_position.distance_to(center) < radius + 12.0 and _rng.randf() < 0.18:
			pl.take_damage(5.0, 0, "crush")
