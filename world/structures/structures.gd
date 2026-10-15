class_name Structures
extends RefCounted
## Blueprint builders for every kind of location. Coordinates inside a
## builder are local to its blueprint; `w()` converts back to world space for
## spawn points.



static func _bp(loc: Location, half: Vector3i, below: int, above: int) -> Blueprint:
	var c := Vector3i(loc.center.round())
	var bp := Blueprint.new(Vector3i(c.x - half.x, loc.ground_y - below, c.z - half.z),
			Vector3i(half.x * 2 + 1, below + above, half.z * 2 + 1))
	loc.blueprints.append(bp)
	return bp


static func _w(bp: Blueprint, local: Vector3) -> Vector3:
	return Vector3(bp.origin) + local + Vector3(0.5, 0.0, 0.5)


# --- Village -------------------------------------------------------------------

static func village(loc: Location, rng: RandomNumberGenerator, is_start: bool) -> void:
	# Modelled buildings, green and yards (world/architecture/village/), on the
	# village's own random stream.
	var own := RandomNumberGenerator.new()
	own.seed = rng.seed ^ hash(String(loc.id))
	VillagePlan.village(loc, own, is_start)
	# Replay the draws the old block village took from the planner's stream so
	# every location planned afterwards keeps its place in existing worlds.
	var count := 6 + rng.randi_range(0, 2)
	for i in count:
		rng.randf_range(-0.15, 0.15)
		rng.randf_range(16.0, 22.0)
		if i >= 2:
			rng.randi_range(0, 1)
			rng.randi_range(0, 2)
	for i in 4:
		rng.randf()


# --- Shrine, tower, ruins -------------------------------------------------------

static func shrine(loc: Location) -> void:
	SitePlan.shrine(loc)


static func tower(loc: Location, rng: RandomNumberGenerator) -> void:
	SitePlan.tower(loc)
	# The planner's stream keeps the draws the old block tower took.
	for i in 3:
		rng.randf()
		rng.randi_range(5, 14)


static func ruin(loc: Location, rng: RandomNumberGenerator) -> void:
	SitePlan.ruin(loc)
	# Replay the old block ruin's draws so later locations keep their places.
	for i in 6:
		rng.randf()
		rng.randf_range(3.0, 10.0)
		rng.randi_range(2, 7)
		rng.randf()
		var length := rng.randi_range(3, 7)
		for j in length:
			rng.randi_range(0, 3)
			rng.randf()
	for i in 3:
		rng.randf()
		rng.randi_range(3, 8)
	if rng.randf() < 0.6:
		var c := loc.center.round()
		loc.add_spawn("chest", Vector3(c.x + 0.5, loc.ground_y + 1, c.z + 0.5), {"tier": 1})


# --- The Silent Crypt -------------------------------------------------------------

## Moved to Battlegrounds (modelled arena, STRUCTURE collision).
static func crypt(surface: Location, depths: Location) -> void:
	Battlegrounds.crypt(surface, depths)


# --- Hall of the Mountain King ---------------------------------------------------

## Moved to Battlegrounds (modelled arena, STRUCTURE collision).
static func mountain_hall(loc: Location, exit_dir: Vector2i, exit_y: int, rng: RandomNumberGenerator) -> void:
	Battlegrounds.mountain_hall(loc, exit_dir, exit_y, rng)


# --- The Dragon's Keep ------------------------------------------------------------

## Moved to Battlegrounds (modelled arena, STRUCTURE collision).
static func castle(loc: Location, rng: RandomNumberGenerator) -> void:
	Battlegrounds.castle(loc, rng)


# --- Gates of Hades --------------------------------------------------------------

## Moved to Battlegrounds (modelled arena, STRUCTURE collision).
static func gates_of_hades(loc: Location, rng: RandomNumberGenerator) -> void:
	Battlegrounds.gates_of_hades(loc, rng)


static func crater_marker(loc: Location, rng: RandomNumberGenerator) -> void:
	SitePlan.crater_marker(loc)
	for i in 9:
		rng.randf_range(-0.2, 0.2)
		rng.randf_range(12.0, 30.0)
		rng.randf_range(0.8, 1.8)
		rng.randi_range(4, 11)


# --- Hell -------------------------------------------------------------------------

static func hell_spawn(loc: Location) -> void:
	SitePlan.hell_spawn(loc)


## Moved to Battlegrounds (modelled arena, STRUCTURE collision).
static func tartarus(loc: Location, rng: RandomNumberGenerator) -> void:
	Battlegrounds.tartarus(loc, rng)


## Moved to Battlegrounds (modelled arena, STRUCTURE collision).
static func throne(loc: Location, rng: RandomNumberGenerator) -> void:
	Battlegrounds.throne(loc, rng)
