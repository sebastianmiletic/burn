extends TestCase
## Mining physics regressions: digging around the body never launches it
## through the rock (old "buried -> climb" rescue + smooth step-up into a
## pickaxe notch), and the first-person eye keeps clear of the terrain mesh.

var _vw: VoxelWorld
var _owner: Node3D
var _body: VoxelBody


func _make_world(sdf: Callable) -> void:
	_vw = VoxelWorld.new()
	for cz in range(-3, 3):
		for cy in range(-3, 3):
			for cx in range(-3, 3):
				var k := Vector3i(cx, cy, cz)
				var blocks := Chunk.empty()
				var dens := Chunk.empty()
				for i in Chunk.VOLUME:
					var y := i / Chunk.AREA
					var z := (i % Chunk.AREA) / Chunk.SIZE
					var x := i % Chunk.SIZE
					var p := Vector3(k * 16 + Vector3i(x, y, z)) + Vector3(0.5, 0.5, 0.5)
					var d: float = sdf.call(p)  # > 0 inside air
					var v := clampi(int(round((0.5 - d * 0.5) * 255.0)), 0, 255)
					if v >= 128:
						blocks[i] = Blocks.STONE
					dens[i] = v
				_vw._chunks[k] = blocks
				_vw._density[k] = dens
	_owner = Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(_owner)
	_body = VoxelBody.new()
	_body.half_extents = Vector3(0.32, 0.9, 0.32)


func _free() -> void:
	_owner.queue_free()
	_vw.free()


func _sim(seconds: float, wish := Vector3.ZERO) -> float:
	var top := -INF
	var n := int(seconds * 60.0)
	for i in n:
		var hv := Vector3(_body.velocity.x, 0, _body.velocity.z).lerp(wish * 4.6, 1.0 - exp(-13.0 / 60.0))
		_body.velocity.x = hv.x
		_body.velocity.z = hv.z
		_body.step(_owner, _vw, 1.0 / 60.0)
		top = maxf(top, _owner.global_position.y)
	return top


func _strike(yaw: float, pitch: float) -> bool:
	var eye := _owner.global_position + Vector3(0, 1.62, 0)
	var dir := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD
	var hit := _vw.raycast(eye, dir, 6.7)
	if hit.is_empty():
		return false
	var point: Vector3 = hit.get("point", Vector3(hit["pos"]) + Vector3(0.5, 0.5, 0.5))
	var nrm: Vector3 = hit.get("surface_normal", Vector3.UP)
	if (Vector3(hit["pos"]) + Vector3(0.5, 0.5, 0.5)).distance_to(_owner.global_position + Vector3(0, 1.5, 0)) > 5.5:
		return false
	var plan := _vw.plan_dig(point - nrm * 0.25, 0.86, 0.42, "pickaxe_stone")
	_vw.set_voxels(plan["changes"])
	return true


func _tunnel(p: Vector3) -> float:
	# Air inside a 3 m tall, 3 m wide tunnel along x; floor at y = 0.
	var dz := 1.5 - absf(p.z)
	var dy := minf(p.y - 0.0, 3.0 - p.y)
	return minf(dz, dy)


func test_dig_down() -> void:
	_make_world(_tunnel)
	_owner.global_position = Vector3(0.3, 0.05, 0.2)
	_sim(1.0)
	var y0 := _owner.global_position.y
	print("      settle y ", y0)
	var worst := 0.0
	for s in 40:
		_strike(0.0, -1.5)
		var top := _sim(0.42)
		worst = maxf(worst, top - y0)
		y0 = minf(y0, _owner.global_position.y)
	print("      dig down: final y %.2f, worst rise above lowest %.2f" % [_owner.global_position.y, worst])
	check(worst < 1.3, "digging down never launches (rise %.2f)" % worst)
	_free()


func test_dig_stairs() -> void:
	_make_world(_tunnel)
	_owner.global_position = Vector3(0.3, 0.05, 0.2)
	_sim(1.0)
	var lowest := _owner.global_position.y
	var worst := 0.0
	for s in 60:
		_strike(PI * 0.5, -0.7)  # facing -x... yaw PI/2 faces -x
		var top := _sim(0.42, Vector3(-1, 0, 0))
		worst = maxf(worst, top - lowest)
		lowest = minf(lowest, _owner.global_position.y)
	print("      stairs: final %s worst %.2f" % [str(_owner.global_position), worst])
	check(worst < 1.3, "digging a stair never launches (rise %.2f)" % worst)
	_free()


func test_dig_wall() -> void:
	_make_world(_tunnel)
	_owner.global_position = Vector3(0.3, 0.05, 0.0)
	_sim(1.0)
	var lowest := _owner.global_position.y
	var worst := 0.0
	for s in 60:
		_strike(PI, -0.15 + 0.3 * (s % 3) / 2.0)  # facing +z into the wall
		var top := _sim(0.42, Vector3(0, 0, 1))
		worst = maxf(worst, top - lowest)
		lowest = minf(lowest, _owner.global_position.y)
	print("      wall: final %s worst %.2f" % [str(_owner.global_position), worst])
	check(worst < 1.3, "digging sideways never launches (rise %.2f)" % worst)
	_free()


func test_dig_up() -> void:
	_make_world(_tunnel)
	_owner.global_position = Vector3(0.3, 0.05, 0.0)
	_sim(1.0)
	var lowest := _owner.global_position.y
	var worst := 0.0
	for s in 40:
		_strike(0.0, 1.4)
		var top := _sim(0.42)
		worst = maxf(worst, top - lowest)
	print("      up: final %s worst %.2f" % [str(_owner.global_position), worst])
	check(worst < 1.3, "digging up never launches (rise %.2f)" % worst)
	_free()


func test_fuzz() -> void:
	var rng := RandomNumberGenerator.new()
	for trial in 6:
		rng.seed = 77 + trial
		_make_world(_tunnel)
		_owner.global_position = Vector3(0.3, 0.05, 0.0)
		_sim(0.5)
		var max_jump := 0.0
		var buried_frames := 0
		var yaw := rng.randf() * TAU
		for s in 120:
			yaw += rng.randf_range(-0.6, 0.6)
			var pitch := rng.randf_range(-1.5, 0.9)
			_strike(yaw, pitch)
			var wish := Basis(Vector3.UP, yaw) * Vector3.FORWARD * (1.0 if rng.randf() < 0.7 else 0.0)
			if rng.randf() < 0.2 and _body.on_floor:
				_body.velocity.y = 9.2
			for f in 25:
				var y0 := _owner.global_position.y
				var hv := Vector3(_body.velocity.x, 0, _body.velocity.z).lerp(wish * 4.6, 1.0 - exp(-13.0 / 60.0))
				_body.velocity.x = hv.x
				_body.velocity.z = hv.z
				_body.step(_owner, _vw, 1.0 / 60.0)
				var p := _owner.global_position
				max_jump = maxf(max_jump, p.y - y0 - maxf(0.0, _body.velocity.y) / 60.0)
				if _vw.field(p + Vector3(0, 0.6, 0)) >= 0.5:
					buried_frames += 1
		print("      fuzz %d: end %s max frame rise %.2f buried frames %d" % [trial, str(_owner.global_position), max_jump, buried_frames])
		check(max_jump < 1.1 and buried_frames < 3 and _owner.global_position.y < 6.0, "fuzz %d: no launch (rise %.2f, buried %d)" % [trial, max_jump, buried_frames])
		_free()


func _mesh_tris() -> PackedVector3Array:
	var tris := PackedVector3Array()
	for cz in range(-2, 2):
		for cy in range(-2, 2):
			for cx in range(-2, 2):
				var k := Vector3i(cx, cy, cz)
				var nb := []
				var dn := []
				for dz in range(-1, 2):
					for dy in range(-1, 2):
						for dx in range(-1, 2):
							nb.append(_vw._chunks[k + Vector3i(dx, dy, dz)])
							dn.append(_vw._density[k + Vector3i(dx, dy, dz)])
				var surface := PackedInt32Array()
				surface.resize(256)
				var biomes := PackedByteArray()
				biomes.resize(256)
				var r := SmoothMesher.build(nb, dn, surface, biomes, k * 16, 0)
				if r.has("terrain"):
					for v: Vector3 in r["terrain"][Mesh.ARRAY_VERTEX]:
						tris.append(v + Vector3(k * 16))
	return tris


static func _pt_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var cp := Geometry3D.get_closest_point_to_segment(p, a, b)
	var best := p.distance_to(cp)
	best = minf(best, p.distance_to(Geometry3D.get_closest_point_to_segment(p, b, c)))
	best = minf(best, p.distance_to(Geometry3D.get_closest_point_to_segment(p, c, a)))
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return best
	n = n.normalized()
	var d := (p - a).dot(n)
	var q := p - n * d
	var hit: Variant = Geometry3D.ray_intersects_triangle(q + n * 0.001, -n, a, b, c)
	if hit != null:
		best = minf(best, absf(d))
	return best


func test_camera_clearance() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	_make_world(_tunnel)
	for s in 30:
		var p := Vector3(rng.randf_range(-6, 6), rng.randf_range(0.5, 2.5), rng.randf_range(-1.6, 1.6))
		var plan := _vw.plan_dig(p, 0.86, 0.42, "pickaxe_stone")
		_vw.set_voxels(plan["changes"])
	var tris := _mesh_tris()
	var cam := PlayerCamera.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(cam)
	var worst := 9.0
	var bad := 0
	for trial in 200:
		_owner.global_position = Vector3(rng.randf_range(-5, 5), 0.3, rng.randf_range(-1, 1))
		_body.velocity = Vector3.ZERO
		_sim(0.3)
		var yaw := rng.randf() * TAU
		_sim(0.8, Basis(Vector3.UP, yaw) * Vector3.FORWARD)
		cam.yaw = yaw
		cam.pitch = rng.randf_range(-1.4, 1.4)
		for f in 5:
			cam.follow(_vw, _owner.global_position, 1.0 / 60.0)
		var eye := cam.global_position
		var dmin := 9.0
		for i in range(0, tris.size(), 3):
			if tris[i].distance_squared_to(eye) > 4.0:
				continue
			dmin = minf(dmin, _pt_tri(eye, tris[i], tris[i + 1], tris[i + 2]))
		worst = minf(worst, dmin)
		if dmin < 0.14:
			bad += 1
	print("      camera: closest eye-to-terrain-mesh %.3f m, %d/200 under 0.14 m" % [worst, bad])
	check(bad == 0, "eye keeps the near plane clear of the terrain mesh (worst %.3f, %d bad)" % [worst, bad])
	cam.queue_free()
	_free()
