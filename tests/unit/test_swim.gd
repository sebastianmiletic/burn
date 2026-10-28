extends TestCase
## The swimming posture: in deep water the player's box lies down (low and
## short round the torso), so it fits through 1 m gaps and reaches the
## seabed; out of the water it stands up only where there is room, and the
## body never ends up inside rock on the way. Runs the Player's own water,
## posture and swim-steering code against hand-built voxel pools.

const DT := 1.0 / 60.0
const EAST := -PI / 2.0  ## camera yaw looking along +x


## Smooth stone (full density) wherever `solid` says, water wherever `wet`
## says, air elsewhere; the world spans -32..31 on every axis.
func _pool(solid: Callable, wet: Callable) -> VoxelWorld:
	var vw := VoxelWorld.new()
	for cz in range(-2, 2):
		for cy in range(-2, 2):
			for cx in range(-2, 2):
				var k := Vector3i(cx, cy, cz)
				var blocks := Chunk.empty()
				var dens := Chunk.empty()
				for i in Chunk.VOLUME:
					var p := k * 16 + Vector3i(i % 16, i / Chunk.AREA, (i / 16) % 16)
					if solid.call(p):
						blocks[i] = Blocks.STONE
						dens[i] = 255
					elif wet.call(p):
						blocks[i] = Blocks.WATER
				vw._chunks[k] = blocks
				vw._density[k] = dens
	return vw


func _player(at: Vector3) -> Player:
	var p := Player.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(p)
	p.set_process(false)
	p.global_position = at
	return p


## The swimmer's box is in rock: its middle anywhere, or its corners deep in
## (VoxelBody lets the lowest corners brush the bevelled edge of a bank it
## is climbing, as a walking body does on a slope).
func _inside(vw: VoxelWorld, p: Player) -> bool:
	var h := p.body.half_extents
	var c := p.global_position
	for y: float in [0.12, h.y, h.y * 2.0 - 0.05]:
		for o: Vector2 in [Vector2.ZERO, Vector2(h.x - 0.05, h.z - 0.05), Vector2(-h.x + 0.05, h.z - 0.05), Vector2(h.x - 0.05, -h.z + 0.05), Vector2(-h.x + 0.05, -h.z + 0.05)]:
			var q := c + Vector3(o.x, y, o.y)
			if vw.field(q) >= (0.55 if o == Vector2.ZERO else 0.75) or vw.is_box_solid(Vector3i(q.floor())):
				return true
	return false


## One frame of the local player's water / posture / movement loop (input as
## the move stick: forward is -y). `hold_y` steers the pitch to keep the body
## at that height (what a player does to line up with a tunnel). Returns
## false if the body ended the frame inside rock.
func _frame(p: Player, vw: VoxelWorld, yaw: float, pitch: float, input: Vector2, hold_y := NAN) -> bool:
	p._water_update(vw)
	p._posture_update(vw, DT)
	p.body.climb_step = Player.SWIM_CLIMB if p.lie > 0.5 else VoxelBody.MAX_STEP
	p.body.swimming = p.swimming
	if not is_nan(hold_y):
		pitch = clampf((hold_y - p.global_position.y) * 2.0, -0.6, 0.6)
	var look := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	if p.swimming:
		p.swim_steer(DT, look, input, 0.0, false)
	else:
		var wish := Basis(Vector3.UP, yaw) * Vector3(input.x, 0, input.y) * Player.WALK_SPEED * lerpf(1.0, 0.4, p.lie)
		p.body.velocity.x = wish.x
		p.body.velocity.z = wish.z
	p.body.step(p, vw, DT)
	if _inside(vw, p):
		print("      inside rock at ", p.global_position, " lie ", p.lie, " swimming ", p.swimming)
		return false
	return true


func test_swimmer_lies_down_and_fits_a_1m_gap() -> void:
	# A lake (floor y = 0, surface 7.88) cut by a rock wall at x 4..9 with a
	# flooded tunnel 1 m high (y 2..3) and 5 m wide through it.
	var vw := _pool(func(c: Vector3i) -> bool:
		return c.y < 0 or (c.x >= 4 and c.x <= 9 and c.y <= 8 and not (c.y == 2 and absi(c.z) <= 2)),
		func(c: Vector3i) -> bool: return c.y <= 7)
	var p := _player(Vector3(1.5, 1.4, 0.5))
	check(not p._fits_with_half(vw, Vector3(6.5, 2.02, 0.5), Player.STAND_HALF_HEIGHT), "a standing body can't fit the tunnel")
	var clear := true
	for f in 30:
		clear = _frame(p, vw, EAST, 0.0, Vector2.ZERO, 2.12) and clear
	check(p.swimming and p.lie == 1.0, "in deep water the body lies flat (lie %.2f)" % p.lie)
	check_near(p.body.half_extents.y * 2.0, 0.7, 0.01, "the lying box is 0.7 m tall")
	check_near(p.hit_height, 0.7, 0.01, "enemies hit the lying shape")
	check(p.hit_radius >= Player.SWIM_HIT_RADIUS - 0.01, "the long body widens the hit radius")
	var lowest_lie := 1.0
	for f in 360:
		clear = _frame(p, vw, EAST, 0.0, Vector2(0, -1), 2.12) and clear
		if p.global_position.x > 4.0 and p.global_position.x < 10.0:
			lowest_lie = minf(lowest_lie, p.lie)
	check(p.global_position.x > 10.5, "the swimmer comes out the far end of the 1 m tunnel (x %.2f)" % p.global_position.x)
	check(lowest_lie == 1.0, "flat all the way through")
	check(clear, "never inside the rock")
	p.queue_free()
	vw.free()


func test_diving_reaches_the_seabed() -> void:
	var vw := _pool(func(c: Vector3i) -> bool: return c.y < 0, func(c: Vector3i) -> bool: return c.y <= 7)
	var p := _player(Vector3(0.5, 6.0, 0.5))
	var clear := true
	for f in 240:
		clear = _frame(p, vw, EAST, 0.0, Vector2.ZERO) and clear
	var eye := p.global_position.y + p.eye_height()
	check(p.swimming and absf(eye - 7.88 - Player.TREAD_EYE) < 0.15, "treading flat with the eyes above the surface (eye %.2f)" % eye)
	check(not p.head_under, "head out of the water while treading")
	check(p.global_position.y > 7.88 - 1.0, "floating at the surface, not sinking (y %.2f)" % p.global_position.y)
	# Look down and swim forward: down until the body rests on the bottom.
	for f in 420:
		clear = _frame(p, vw, EAST, -0.8, Vector2(0, -1)) and clear
	check(p.global_position.y < 0.08 and p.body.on_floor, "down-forward reaches the seabed (y %.2f)" % p.global_position.y)
	check(p.global_position.y + p.eye_height() < 0.75, "the eye is low over the seabed, not 1.6 m up")
	check(p.head_under and p.swimming and p.lie == 1.0, "still swimming flat under water")
	check(clear, "never inside the seabed")
	p.queue_free()
	vw.free()


func test_standing_up_needs_room() -> void:
	# Dry ground at y = 0 with a 1 m-high crawlway (roof from y = 1) for x < 3.
	var vw := _pool(func(c: Vector3i) -> bool: return c.y < 0 or (c.x < 3 and c.y >= 1 and c.y <= 4),
		func(_c: Vector3i) -> bool: return false)
	var p := _player(Vector3(0.5, 0.02, 0.5))
	p._apply_lie(1.0, 0.02)
	var clear := true
	for f in 90:
		clear = _frame(p, vw, EAST, 0.0, Vector2.ZERO) and clear
	check(not p.swimming and p.lie > 0.6, "out of water under a low roof the body stays low (lie %.2f)" % p.lie)
	check(p.global_position.y + p.body.half_extents.y * 2.0 <= 1.03, "growing only as far as the roof (top %.2f)" % (p.global_position.y + p.body.half_extents.y * 2.0))
	check(p.global_position.y > -0.05, "and not down into the floor")
	# Crawl out from under it: stands up in the open.
	for f in 240:
		clear = _frame(p, vw, EAST, 0.0, Vector2(0, -1)) and clear
	check(p.global_position.x > 3.4 and p.lie == 0.0, "standing again once there is room (x %.2f, lie %.2f)" % [p.global_position.x, p.lie])
	check_near(p.body.half_extents.y, Player.STAND_HALF_HEIGHT, 0.001, "full standing height restored")
	check(absf(p.global_position.y) < 0.1, "on the ground, not launched (y %.2f)" % p.global_position.y)
	check(clear, "never inside the rock")
	p.queue_free()
	vw.free()


func test_climbing_out_of_the_water_stands_up() -> void:
	# A lake (surface 7.88) against a shelf whose top (y = 8) is just above the water.
	var vw := _pool(func(c: Vector3i) -> bool: return c.y < 0 or (c.x >= 4 and c.y <= 7),
		func(c: Vector3i) -> bool: return c.y <= 7)
	var p := _player(Vector3(1.5, 6.0, 0.5))
	var clear := true
	for f in 240:
		clear = _frame(p, vw, EAST, 0.0, Vector2.ZERO) and clear
	check(p.swimming and p.lie == 1.0, "swimming flat before the bank")
	var top := -INF
	for f in 300:
		clear = _frame(p, vw, EAST, 0.0, Vector2(0, -1)) and clear
		top = maxf(top, p.global_position.y)
	check(not p.swimming and p.global_position.x > 4.3, "hauled out onto the shelf (x %.2f, y %.2f)" % [p.global_position.x, p.global_position.y])
	check(p.lie == 0.0 and absf(p.body.half_extents.y - Player.STAND_HALF_HEIGHT) < 0.001, "standing height once out of the water")
	check(absf(p.global_position.y - 8.0) < 0.1 and top < 9.6, "standing on the shelf, never flung up (y %.2f, top %.2f)" % [p.global_position.y, top])
	check_near(p.hit_height, 1.8, 0.01, "full hit height again")
	check(clear, "never inside the rock")
	p.queue_free()
	vw.free()


func test_wading_out_of_shallows_stands_up() -> void:
	# The lake floor rises in steps towards +x: deep, then waist-deep, then dry.
	var vw := _pool(func(c: Vector3i) -> bool: return c.y < 0 or (c.x >= 4 and c.y < 7) or (c.x >= 9 and c.y < 8),
		func(c: Vector3i) -> bool: return c.y <= 7)
	var p := _player(Vector3(1.5, 5.0, 0.5))
	var clear := true
	for f in 240:
		clear = _frame(p, vw, EAST, 0.0, Vector2.ZERO) and clear
	check(p.swimming and p.lie == 1.0, "swimming flat in deep water")
	var stood_at := INF
	for f in 300:
		clear = _frame(p, vw, EAST, 0.0, Vector2(0, -1)) and clear
		if stood_at == INF and p.lie == 0.0:
			stood_at = p.global_position.x
	check(stood_at < 9.0, "stands up over the waist-deep shelf (x %.2f)" % stood_at)
	check(not p.swimming and p.lie == 0.0, "walking, not swimming, in the shallows")
	check(clear, "never inside the rock")
	p.queue_free()
	vw.free()
