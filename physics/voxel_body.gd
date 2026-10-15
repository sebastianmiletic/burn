class_name VoxelBody
extends RefCounted
## Kinematic body physics against the voxel world. Deterministic, cheap and
## free of physics-engine shapes, so every entity (and every client) moves
## the same way. The owner's position is the bottom centre of the body.
##
## Two kinds of obstacle:
##  * the smooth terrain surface (VoxelWorld.field): bodies stand on it, climb
##    slopes up to ~60 degrees and are stopped by steeper ground and overhangs;
##  * crisp cubes (walls, floors, trunks): axis-aligned boxes, with step-up
##    onto one-block ledges.

const MAX_STEP := 0.6     ## smooth ground a body walks up without jumping (m)
const SNAP_DOWN := 0.5    ## stay glued to the ground when walking downhill (m)

var velocity := Vector3.ZERO
var half_extents := Vector3(0.3, 0.9, 0.3)
var gravity := 26.0
var on_floor := false
var in_liquid := 0         ## block id of the liquid around the body's centre, 0 = none
var hit_wall := false
var climb_step := MAX_STEP
var can_step := true       ## walk up one-block ledges without jumping
var max_fall_speed := 40.0
var fly := false           ## flying creatures ignore gravity
var collides := true
## Set when the body stepped up this frame; owners can smooth the visual.
var stepped := 0.0
## Normal of the ground under the body (for slope effects), UP when airborne.
var ground_normal := Vector3.UP


func step(owner: Node3D, world: VoxelWorld, delta: float) -> void:
	stepped = 0.0
	hit_wall = false
	var pos := owner.global_position
	if world != null and collides and not world.is_area_loaded(pos):
		# The ground isn't streamed in yet: hold still instead of free-falling.
		velocity = Vector3.ZERO
		return
	in_liquid = 0
	if world != null:
		var mid := world.get_block(Vector3i((pos + Vector3(0, half_extents.y, 0)).floor()))
		if mid > 0 and Blocks.is_liquid(mid):
			in_liquid = mid
	if not fly:
		var g := gravity * (0.25 if in_liquid != 0 else 1.0)
		velocity.y = maxf(velocity.y - g * delta, -max_fall_speed * (0.2 if in_liquid != 0 else 1.0))
	if in_liquid != 0:
		velocity.x *= 1.0 - minf(1.0, delta * 3.0)
		velocity.z *= 1.0 - minf(1.0, delta * 3.0)
	if world == null or not collides:
		owner.global_position = pos + velocity * delta
		return
	var motion := velocity * delta
	var steps := maxi(1, ceili(motion.length() / 0.3))
	var part := motion / steps
	var was_on_floor := on_floor
	on_floor = false
	for i in steps:
		pos = _move_axis(world, pos, 1, part.y)
		pos = _smooth_vertical(world, pos, part.y)
		var before := pos
		pos = _move_axis(world, pos, 0, part.x)
		pos = _move_axis(world, pos, 2, part.z)
		if can_step and (was_on_floor or on_floor) and (absf(pos.x - before.x - part.x) > 0.001 or absf(pos.z - before.z - part.z) > 0.001):
			# Blocked by a crisp block: try again one block higher.
			var up := before + Vector3(0, 1.001, 0)
			if not _overlaps(world, up) and not _smooth_blocked(world, up):
				var try_pos := _move_axis(world, up, 0, part.x)
				try_pos = _move_axis(world, try_pos, 2, part.z)
				if Vector2(try_pos.x - before.x, try_pos.z - before.z).length() > Vector2(pos.x - before.x, pos.z - before.z).length() + 0.01:
					stepped += try_pos.y - pos.y
					pos = try_pos
					hit_wall = false
	# Settle onto the ground after the horizontal moves (walking uphill).
	if velocity.y <= 0.0:
		var y0 := pos.y
		pos = _smooth_vertical(world, pos, 0.0)
		if pos.y > y0 + 0.02:
			stepped += pos.y - y0
		if not on_floor and was_on_floor:
			# Walking downhill: stay on the ground instead of skipping off it.
			var g := _ground(world, pos, pos.y + 0.05, SNAP_DOWN)
			if g > -INF and g < INF:
				pos.y = g
				on_floor = true
				velocity.y = 0.0
	owner.global_position = pos


## Smooth-ground vertical resolution: land on (or step up onto) the surface
## below, or stop at an overhang above.
func _smooth_vertical(world: VoxelWorld, pos: Vector3, dy: float) -> Vector3:
	if dy > 0.0:
		var head := pos + Vector3(0, half_extents.y * 2.0, 0)
		if world.field(head) >= 0.5:
			pos.y -= dy
			velocity.y = 0.0
		return pos
	var reach := climb_step if not fly else 0.05
	var g := _ground(world, pos, pos.y + reach, reach + 0.02)
	if g == INF:
		# Buried (a block placed on us, terrain streamed in): climb out.
		pos.y += 0.25
		return pos
	if g > -INF and g >= pos.y - 0.001:
		pos.y = g
		on_floor = true
		velocity.y = 0.0
	return pos


## Highest smooth ground under the body's footprint, searching down from
## `from_y` for `depth` m. -INF if none, INF if the centre is buried.
func _ground(world: VoxelWorld, pos: Vector3, from_y: float, depth: float) -> float:
	var r := half_extents.x * 0.55
	var best := world.ground_below(pos.x, from_y, pos.z, depth)
	if best == INF:
		return INF
	var normal_samples := PackedFloat32Array([best, best, best, best])
	var offs := [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]
	for i in 4:
		var o: Vector2 = offs[i]
		var g := world.ground_below(pos.x + o.x, from_y, pos.z + o.y, depth)
		if g == INF:
			continue
		normal_samples[i] = g
		if g > best:
			best = g
	if best > -INF:
		var sx := normal_samples[0] - normal_samples[1]
		var sz := normal_samples[2] - normal_samples[3]
		if absf(sx) < 2.0 and absf(sz) < 2.0:
			ground_normal = Vector3(-sx, 2.0 * r, -sz).normalized()
	return best


## Smooth ground intruding into the body above step height (a wall or overhang).
func _smooth_blocked(world: VoxelWorld, pos: Vector3) -> bool:
	var h := half_extents
	var heights := [climb_step + 0.02, h.y * 2.0 - 0.1]
	if h.y * 2.0 > 2.4:
		heights.append(h.y)
	for y: float in heights:
		for o: Vector2 in [Vector2(h.x, h.z), Vector2(-h.x, h.z), Vector2(h.x, -h.z), Vector2(-h.x, -h.z)]:
			if world.field(pos + Vector3(o.x, y, o.y)) >= 0.5:
				return true
	return false


func _move_axis(world: VoxelWorld, pos: Vector3, axis: int, amount: float) -> Vector3:
	if amount == 0.0:
		return pos
	var target := pos
	target[axis] += amount
	if axis != 1 and _smooth_blocked(world, target) and not _smooth_blocked(world, pos):
		hit_wall = true
		velocity[axis] = 0.0
		return pos
	if not _overlaps(world, target):
		return target
	# Snap against the face we hit.
	if axis == 1:
		if amount < 0.0:
			target.y = floorf(target.y) + 1.0
			if _overlaps(world, target):
				return pos
			on_floor = true
			ground_normal = Vector3.UP
		else:
			var top := target.y + half_extents.y * 2.0
			target.y = floorf(top) - half_extents.y * 2.0 - 0.001
			if _overlaps(world, target):
				return pos
		velocity.y = 0.0
		return target
	var h := half_extents[axis]
	if amount > 0.0:
		target[axis] = floorf(target[axis] + h) - h - 0.001
	else:
		target[axis] = floorf(target[axis] - h) + 1.0 + h + 0.001
	hit_wall = true
	if _overlaps(world, target):
		return pos
	velocity[axis] = 0.0
	return target


## Overlap with crisp blocks (cubes, trunks). Unloaded space counts as solid.
func _overlaps(world: VoxelWorld, pos: Vector3) -> bool:
	var mn := pos - Vector3(half_extents.x, 0.0, half_extents.z)
	var mx := pos + Vector3(half_extents.x, half_extents.y * 2.0, half_extents.z)
	for y in range(floori(mn.y + 0.001), floori(mx.y - 0.001) + 1):
		for z in range(floori(mn.z), floori(mx.z) + 1):
			for x in range(floori(mn.x), floori(mx.x) + 1):
				var b := world.get_block(Vector3i(x, y, z))
				if b < 0 or (b > 0 and Blocks.is_solid(b) and not Blocks.is_smooth(b)):
					return true
	return false


func overlaps_block(pos: Vector3, block: Vector3i) -> bool:
	var mn := pos - Vector3(half_extents.x, 0.0, half_extents.z)
	var mx := pos + Vector3(half_extents.x, half_extents.y * 2.0, half_extents.z)
	return block.x + 1 > mn.x and block.x < mx.x and block.y + 1 > mn.y and block.y < mx.y and block.z + 1 > mn.z and block.z < mx.z
