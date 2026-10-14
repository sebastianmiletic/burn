class_name VoxelBody
extends RefCounted
## Axis-aligned box physics against the voxel grid. Deterministic, cheap and
## free of physics-engine shapes, so every entity (and every client) moves
## the same way. The owner's position is the bottom centre of the box.

var velocity := Vector3.ZERO
var half_extents := Vector3(0.3, 0.9, 0.3)
var gravity := 26.0
var on_floor := false
var in_liquid := 0         ## block id of the liquid around the body's centre, 0 = none
var hit_wall := false
var can_step := true       ## walk up one-block ledges without jumping
var max_fall_speed := 40.0
var fly := false           ## flying creatures ignore gravity
var collides := true
## Set when the body stepped up this frame; owners can smooth the visual.
var stepped := 0.0


func step(owner: Node3D, world: VoxelWorld, delta: float) -> void:
	stepped = 0.0
	hit_wall = false
	var pos := owner.global_position
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
	if not world.is_area_loaded(pos):
		return  # wait for the ground to exist
	var motion := velocity * delta
	var steps := maxi(1, ceili(motion.length() / 0.4))
	var part := motion / steps
	var was_on_floor := on_floor
	on_floor = false
	for i in steps:
		pos = _move_axis(world, pos, 1, part.y)
		var before := pos
		pos = _move_axis(world, pos, 0, part.x)
		pos = _move_axis(world, pos, 2, part.z)
		if can_step and (was_on_floor or on_floor) and (absf(pos.x - before.x - part.x) > 0.001 or absf(pos.z - before.z - part.z) > 0.001):
			# Blocked sideways: try again one block higher.
			var up := before + Vector3(0, 1.001, 0)
			if not _overlaps(world, up):
				var try_pos := _move_axis(world, up, 0, part.x)
				try_pos = _move_axis(world, try_pos, 2, part.z)
				if Vector2(try_pos.x - before.x, try_pos.z - before.z).length() > Vector2(pos.x - before.x, pos.z - before.z).length() + 0.01:
					stepped += try_pos.y - pos.y
					pos = try_pos
					hit_wall = false
	owner.global_position = pos


func _move_axis(world: VoxelWorld, pos: Vector3, axis: int, amount: float) -> Vector3:
	if amount == 0.0:
		return pos
	var target := pos
	target[axis] += amount
	if not _overlaps(world, target):
		return target
	# Snap against the face we hit.
	if axis == 1:
		if amount < 0.0:
			target.y = floorf(target.y) + 1.0
			if _overlaps(world, target):
				return pos
			on_floor = true
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


func _overlaps(world: VoxelWorld, pos: Vector3) -> bool:
	var mn := pos - Vector3(half_extents.x, 0.0, half_extents.z)
	var mx := pos + Vector3(half_extents.x, half_extents.y * 2.0, half_extents.z)
	for y in range(floori(mn.y + 0.001), floori(mx.y - 0.001) + 1):
		for z in range(floori(mn.z), floori(mx.z) + 1):
			for x in range(floori(mn.x), floori(mx.x) + 1):
				if world.is_solid(Vector3i(x, y, z)):
					return true
	return false


func overlaps_block(pos: Vector3, block: Vector3i) -> bool:
	var mn := pos - Vector3(half_extents.x, 0.0, half_extents.z)
	var mx := pos + Vector3(half_extents.x, half_extents.y * 2.0, half_extents.z)
	return block.x + 1 > mn.x and block.x < mx.x and block.y + 1 > mn.y and block.y < mx.y and block.z + 1 > mn.z and block.z < mx.z
