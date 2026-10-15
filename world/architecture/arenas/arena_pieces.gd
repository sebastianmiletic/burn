class_name ArenaPieces
extends RefCounted
## Architectural pieces shared by the arena builders (worker thread). All take
## a kit and work in the kit's current coordinates (y up, floor at y = 0 unless
## stated). Materials are set by the caller unless a piece needs its own.

const K := preload("res://world/architecture/arenas/arena_kit.gd")

# --- Masonry ----------------------------------------------------------------------

## A straight castle wall from a to b along the floor. `out` = outward normal
## (the side with the parapet). tops: optional per-metre heights (breaches).
## Adds battered plinths, a string course, corbels under the parapet walk and
## merlons; broken stretches get a jagged top.
static func castle_wall(k: K, a: Vector3, b: Vector3, out: Vector3, thick: float, height: float, tops: PackedFloat32Array = PackedFloat32Array(), merlons := true, stone := K.CASTLE, tint := Color(1, 1, 1)) -> void:
	var along := (b - a)
	var length := along.length()
	var dir := along / length
	out = out.normalized()
	var inner := -out
	var n := maxi(1, int(round(length / 1.5)))
	var step := length / n
	var full := tops.is_empty()
	# Body in columns so broken stretches can step down.
	for i in n:
		var t0 := float(i) * step
		var t1 := t0 + step
		var top := height
		if not full:
			var ti := clampi(int((t0 + t1) * 0.5), 0, tops.size() - 1)
			top = tops[ti]
		var broken := top < height - 0.5
		if broken:
			top += k.rng.randf_range(-0.9, 0.6)
		var mid := a + dir * (t0 + t1) * 0.5
		k.mat(stone, tint, 0.28)
		k.vary(0.05)
		k.push(Transform3D(_basis_for(dir, out), mid))
		k.box(Vector3(0, top * 0.5, 0), Vector3(thick, top, step + 0.01), 0.0)
		if broken:
			# Jagged broken masonry on top.
			for j in 3:
				var bs := Vector3(k.rng.randf_range(0.5, thick * 0.8), k.rng.randf_range(0.3, 0.8), k.rng.randf_range(0.4, step * 0.7))
				k.push(Transform3D(Basis.from_euler(Vector3(k.rng.randf_range(-0.3, 0.3), k.rng.randf_range(-0.4, 0.4), k.rng.randf_range(-0.3, 0.3))),
						Vector3(k.rng.randf_range(-thick * 0.3, thick * 0.3), top + bs.y * 0.2, k.rng.randf_range(-step * 0.3, step * 0.3))))
				k.box(Vector3.ZERO, bs, 0.06, false)
				k.pop()
		k.pop()
	# Battered plinth on both faces, string course, corbels and parapet on the outside.
	k.mat(stone, tint * Color(0.92, 0.92, 0.92), 0.28)
	var batter := PackedVector2Array([Vector2(0.75, 0.0), Vector2(0.62, 0.35), Vector2(0.0, 2.4)])
	k.moulding(a + out * thick * 0.5, b + out * thick * 0.5, out, batter)
	k.moulding(b + inner * thick * 0.5, a + inner * thick * 0.5, inner, PackedVector2Array([Vector2(0.4, 0.0), Vector2(0.0, 1.3)]))
	var low := height
	if not full:
		for v in tops:
			low = minf(low, v)
	if low > 6.0:
		var sy := minf(height * 0.55, low - 1.5)
		var band := PackedVector2Array([Vector2(0.0, sy - 0.18), Vector2(0.2, sy - 0.1), Vector2(0.22, sy + 0.06), Vector2(0.0, sy + 0.16)])
		k.moulding(a + out * thick * 0.5, b + out * thick * 0.5, out, band)
		k.moulding(b + inner * thick * 0.5, a + inner * thick * 0.5, inner, band)
	if not merlons:
		return
	# Parapet and merlons only over intact stretches.
	var t := 0.6
	while t < length - 0.6:
		var top := height
		if not full:
			top = tops[clampi(int(t), 0, tops.size() - 1)]
		if top >= height - 0.01:
			var p := a + dir * t + out * (thick * 0.5)
			# corbel under the parapet
			k.mat(stone, tint * Color(0.85, 0.85, 0.85), 0.3)
			k.push(Transform3D(_basis_for(dir, out), p + Vector3(0, height - 0.55, 0)))
			k.box(Vector3(0.18, 0, 0), Vector3(0.36, 0.55, 0.32), 0.04, false)
			k.pop()
		t += 1.0
	# parapet band (projecting on the corbels) and merlons
	var segs: Array = []
	var s0 := -1.0
	var tt := 0.0
	while tt <= length:
		var top := height
		if not full:
			top = tops[clampi(int(tt), 0, tops.size() - 1)]
		var ok := top >= height - 0.01 and tt < length - 0.01
		if ok and s0 < 0.0:
			s0 = tt
		elif not ok and s0 >= 0.0:
			segs.append([s0, tt])
			s0 = -1.0
		tt += 0.5
	for sg: Array in segs:
		var pa := a + dir * float(sg[0])
		var pb := a + dir * float(sg[1])
		var seg_len := float(sg[1]) - float(sg[0])
		if seg_len < 1.0:
			continue
		k.mat(stone, tint, 0.28)
		k.push(Transform3D(_basis_for(dir, out), (pa + pb) * 0.5 + out * (thick * 0.5 - 0.15) + Vector3(0, height, 0)))
		k.box(Vector3(0, 0.45, 0), Vector3(0.7, 0.9, seg_len), 0.05)
		var m := int(seg_len / 1.9)
		for j in m:
			var z := -seg_len * 0.5 + (float(j) + 0.5) * seg_len / m
			k.vary(0.06)
			k.box(Vector3(0, 1.45, z), Vector3(0.7, 1.2, 1.05), 0.06)
			# merlon cap
			k.box(Vector3(0, 2.1, z), Vector3(0.82, 0.12, 1.15), 0.04)
		k.pop()


## Basis with z along the wall and x pointing outwards.
static func _basis_for(dir: Vector3, out: Vector3) -> Basis:
	var x := out - dir * out.dot(dir)
	x.y = 0.0
	x = x.normalized()
	return Basis(x, Vector3.UP, x.cross(Vector3.UP).normalized())


## Round tower: battered base, string courses, arrow slits, corbelled parapet
## with merlons and a conical slate roof; or a ruined jagged top.
static func round_tower(k: K, at: Vector3, r: float, top: float, broken: bool, roof := true, stone := K.CASTLE, tint := Color(1, 1, 1)) -> void:
	k.push_at(at)
	k.mat(stone, tint, 0.28)
	var seg := 28
	k.lathe(PackedVector2Array([Vector2(r + 0.9, 0.0), Vector2(r + 0.75, 0.5), Vector2(r, 2.8)]), seg)
	var body_top := top if not broken else top - 2.0
	var prof := PackedVector2Array([Vector2(r, 2.8), Vector2(r, body_top)])
	k.lathe(prof, seg)
	# string courses
	k.mat(stone, tint * Color(0.9, 0.9, 0.9), 0.3)
	for y: float in [top * 0.4, top * 0.72]:
		if y < body_top - 1.0:
			k.lathe(PackedVector2Array([Vector2(r, y - 0.18), Vector2(r + 0.18, y - 0.08), Vector2(r + 0.2, y + 0.08), Vector2(r, y + 0.18)]), seg)
	# arrow slits
	for level: float in [top * 0.3, top * 0.58, top * 0.82]:
		if level > body_top - 1.5:
			continue
		for j in 3:
			var a := k.rng.randf() * TAU
			_slit(k, Vector3(cos(a) * r, level, sin(a) * r), Vector3(cos(a), 0, sin(a)), stone, tint)
	if broken:
		# jagged crown with an inner face
		var pieces := 14
		for j in pieces:
			var a0 := TAU * j / pieces
			var a1 := TAU * (j + 1) / pieces
			var h := body_top + k.rng.randf_range(-1.5, 2.5) * (0.5 + 0.5 * absf(sin(j * 1.7)))
			k.mat(stone, tint, 0.28)
			k.vary(0.05)
			k.lathe(PackedVector2Array([Vector2(r, body_top - 0.01), Vector2(r, h), Vector2(r - 1.2, h), Vector2(r - 1.2, body_top - 0.01)]), 3, a0, a1)
		k.pop()
		return
	# corbel ring, parapet, merlons
	k.mat(stone, tint * Color(0.88, 0.88, 0.88), 0.3)
	var corbels := int(TAU * r / 0.9)
	for j in corbels:
		var a := TAU * j / corbels
		k.push(Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * (r + 0.2), top - 0.4, sin(a) * (r + 0.2))))
		k.box(Vector3.ZERO, Vector3(0.42, 0.7, 0.32), 0.04, false)
		k.pop()
	k.mat(stone, tint, 0.28)
	k.lathe(PackedVector2Array([Vector2(r, top - 0.05), Vector2(r + 0.45, top), Vector2(r + 0.45, top + 1.0)]), seg)
	var mer := int(TAU * (r + 0.45) / 1.8)
	for j in mer:
		var a0 := TAU * (j + 0.2) / mer
		var a1 := TAU * (j + 0.8) / mer
		k.vary(0.05)
		k.lathe(PackedVector2Array([Vector2(r + 0.45, top + 1.0), Vector2(r + 0.45, top + 2.1), Vector2(r - 0.25, top + 2.1), Vector2(r - 0.25, top + 1.0)]), 3, a0, a1)
	if roof:
		k.mat(K.DARK, Color(0.55, 0.6, 0.68), 0.6)
		var rr := r + 0.2
		k.lathe(PackedVector2Array([Vector2(rr + 0.5, top + 1.2), Vector2(rr * 0.7, top + 1.2 + rr * 0.55), Vector2(rr * 0.25, top + 1.2 + rr * 1.25), Vector2(0.05, top + 1.2 + rr * 1.6)]), seg)
		k.mat(K.IRON, Color(1, 1, 1), 1.0)
		k.sweep(PackedVector3Array([Vector3(0, top + 1.1 + rr * 1.6, 0), Vector3(0, top + 2.4 + rr * 1.6, 0)]), PackedFloat32Array([0.06, 0.02]), 5)
	k.pop()


## Arrow slit: a dark recess with a dressed stone frame, on a face at p with normal n.
static func _slit(k: K, p: Vector3, n: Vector3, stone: int, tint: Color) -> void:
	var b := _basis_for(n.cross(Vector3.UP).normalized(), n)
	k.push(Transform3D(b, p))
	k.mat(K.DARK, Color(0.04, 0.035, 0.03), 0.5)
	k.box(Vector3(0.02, 0, 0), Vector3(0.06, 1.3, 0.16), 0.0)
	k.box(Vector3(0.02, 0, 0), Vector3(0.06, 0.16, 0.5), 0.0)
	k.mat(stone, tint * Color(1.08, 1.05, 1.0), 0.35)
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(0.05, 0, s * 0.17), Vector3(0.12, 1.5, 0.12), 0.02)
	k.box(Vector3(0.05, 0.72, 0), Vector3(0.12, 0.14, 0.46), 0.02)
	k.box(Vector3(0.05, -0.72, 0), Vector3(0.12, 0.14, 0.46), 0.02)
	k.pop()


## A dark window recess with an arched head and stone surround on a wall face.
static func window(k: K, p: Vector3, n: Vector3, w: float, h: float, stone: int, tint: Color) -> void:
	var b := _basis_for(n.cross(Vector3.UP).normalized(), n)
	k.push(Transform3D(b, p))
	k.mat(K.DARK, Color(0.03, 0.028, 0.025), 0.5)
	k.box(Vector3(0.01, 0, 0), Vector3(0.04, h, w), 0.0)
	k.mat(stone, tint * Color(1.05, 1.03, 1.0), 0.3)
	k.box(Vector3(0.12, -h * 0.5 - 0.1, 0), Vector3(0.36, 0.2, w + 0.5), 0.03)
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(0.08, -0.05, s * (w * 0.5 + 0.12)), Vector3(0.22, h - 0.1, 0.24), 0.03)
	k.push(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0.08, h * 0.5 - w * 0.5 - 0.05, 0)))
	k.arch(w, 0.0, 0.32, 0.24, 5)
	k.pop()
	k.pop()


## Pile of broken masonry and stones around `at` (radius r).
static func rubble(k: K, at: Vector3, r: float, count: int, stone := K.CASTLE, tint := Color(1, 1, 1)) -> void:
	for i in count:
		var a := k.rng.randf() * TAU
		var d := sqrt(k.rng.randf()) * r
		var h := (1.0 - d / r) * r * 0.35
		var s := Vector3(k.rng.randf_range(0.35, 1.1), k.rng.randf_range(0.25, 0.6), k.rng.randf_range(0.35, 0.9)) * (1.0 - d / r * 0.4)
		var p := at + Vector3(cos(a) * d, h * k.rng.randf() + s.y * 0.2, sin(a) * d)
		if i % 3 == 0:
			k.mat(K.TRI + K.ROCK, Color(0.8, 0.78, 0.75), 0.6)
			k.rock(p, s * 0.6, 0.3, 1, i + int(at.x * 7.0))
		else:
			k.mat(stone, tint, 0.3)
			k.vary(0.1)
			k.push(Transform3D(Basis.from_euler(Vector3(k.rng.randf_range(-0.5, 0.5), k.rng.randf() * TAU, k.rng.randf_range(-0.5, 0.5))), p))
			k.box(Vector3.ZERO, s, 0.05, false)
			k.pop()


# --- Fire and furniture ----------------------------------------------------------------

## Stone fire basin on an octagonal pedestal: flame, light, embers.
static func fire_basin(b: ArenaBuild, k: K, at: Vector3, world_at: Vector3, scale := 1.0, flame_kind := "fire", stone := K.GRANITE, light_color := Color(1.0, 0.55, 0.22), shadow := 1) -> void:
	k.push_at(at, 0.0, Vector3(scale, scale, scale))
	k.mat(stone, Color(0.75, 0.72, 0.7), 0.5)
	var oct := PackedVector2Array()
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		oct.append(Vector2(cos(a), sin(a)) * 1.25)
	k.push(Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3.ZERO))
	k.extrude(oct, 0.0, 0.35)
	var oct2 := PackedVector2Array()
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		oct2.append(Vector2(cos(a), sin(a)) * 0.75)
	k.extrude(oct2, 0.35, 1.0)
	k.pop()
	k.lathe(PackedVector2Array([Vector2(0.78, 1.0), Vector2(0.95, 1.1), Vector2(0.95, 1.2)]), 16)
	k.mat(K.IRON, Color(1, 1, 1), 1.0)
	k.lathe(PackedVector2Array([Vector2(0.55, 1.18), Vector2(1.0, 1.35), Vector2(1.35, 1.75), Vector2(1.42, 1.85), Vector2(1.3, 1.85), Vector2(1.2, 1.72)]), 20)
	k.mat(K.GLOW, Color(1.0, 0.42, 0.1) if flame_kind != "soul" else Color(0.3, 0.8, 1.0), 1.0, 2.2)
	for i in 6:
		var a := TAU * i / 6.0
		k.rock(Vector3(cos(a) * 0.55, 1.62, sin(a) * 0.55), Vector3(0.32, 0.18, 0.3), 0.35, 1, i)
	k.rock(Vector3(0, 1.68, 0), Vector3(0.4, 0.2, 0.4), 0.35, 1, 9)
	k.pop()
	b.flame(world_at + Vector3(0, 1.6 * scale, 0), 2.6 * scale, flame_kind)
	b.flame(world_at + Vector3(0.45, 1.6 * scale, 0.2) * Vector3(scale, 1, scale), 1.6 * scale, flame_kind)
	b.flame(world_at + Vector3(-0.35, 1.6 * scale, -0.35) * Vector3(scale, 1, scale), 1.9 * scale, flame_kind)
	b.light(world_at + Vector3(0, 2.6 * scale, 0), light_color, 4.5 * scale, 22.0 * scale, shadow, 0.3, 1.5)
	b.embers.append([world_at + Vector3(0, 2.0 * scale, 0), Vector3(0.6, 0.2, 0.6) * scale, 14, "fire"])


## Iron wall sconce with a burning torch on a wall face (p on the face, n outward).
static func sconce(b: ArenaBuild, k: K, p: Vector3, n: Vector3, world_p: Vector3, flame_kind := "fire", light_color := Color(1.0, 0.58, 0.25), energy := 2.2) -> void:
	var bas := _basis_for(n.cross(Vector3.UP).normalized(), n)
	k.push(Transform3D(bas, p))
	k.mat(K.IRON, Color(1, 1, 1), 1.0)
	k.box(Vector3(0.03, 0, 0), Vector3(0.06, 0.5, 0.22), 0.01)
	k.sweep(PackedVector3Array([Vector3(0.05, -0.1, 0), Vector3(0.3, 0.0, 0), Vector3(0.42, 0.22, 0)]), PackedFloat32Array([0.025, 0.025, 0.025]), 5)
	k.lathe(PackedVector2Array([Vector2(0.02, 0.2), Vector2(0.11, 0.3), Vector2(0.13, 0.42)]), 8, 0.0, TAU)
	k.pop()
	var tip := world_p + n * 0.42 + Vector3(0, 0.62, 0)
	k.push(Transform3D(bas, p))
	k.mat(K.BARK, Color(0.5, 0.4, 0.3), 1.0)
	k.sweep(PackedVector3Array([Vector3(0.42, 0.15, 0), Vector3(0.44, 0.55, 0)]), PackedFloat32Array([0.045, 0.06]), 6)
	k.pop()
	b.flame(tip - Vector3(0, 0.08, 0), 0.75, flame_kind)
	b.light(tip + n * 0.3, light_color, energy, 11.0, 0, 0.35, 0.8)


## Tattered cloth banner hanging from an iron rod on a wall face (top centre at p).
static func banner(k: K, p: Vector3, n: Vector3, w: float, h: float, color: Color, trim: Color, seed_value: int) -> void:
	var bas := _basis_for(n.cross(Vector3.UP).normalized(), n)
	k.push(Transform3D(bas, p + n * 0.25))
	k.mat(K.IRON, Color(1, 1, 1), 1.0)
	k.sweep(PackedVector3Array([Vector3(0, 0, -w * 0.5 - 0.2), Vector3(0, 0, w * 0.5 + 0.2)]), PackedFloat32Array([0.035, 0.035]), 6)
	for s: float in [-1.0, 1.0]:
		k.sweep(PackedVector3Array([Vector3(-0.25, 0.05, s * (w * 0.5 + 0.1)), Vector3(0, 0, s * (w * 0.5 + 0.1))]), PackedFloat32Array([0.025, 0.025]), 4)
	var cols := 8
	var rows := 14
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var tear := PackedFloat32Array()
	for i in cols + 1:
		tear.append(rng.randf_range(0.0, 0.22) * h + (0.12 * h if i % 3 == 1 else 0.0))
	for face: float in [1.0, -1.0]:
		var grid := []
		for j in rows + 1:
			var row := PackedInt32Array()
			var v := float(j) / rows
			for i in cols + 1:
				var u := float(i) / cols
				var y := -v * (h - tear[i] * v)
				var x := 0.03 + sin(v * 2.4 + u * 1.3 + seed_value) * 0.12 * v + v * v * 0.1
				var z := (u - 0.5) * w * (1.0 - v * 0.08)
				var edge := u < 0.1 or u > 0.9 or v > 0.86
				k.mat(K.CLOTH, trim if edge else color, 1.0)
				row.append(k._v(Vector3(x + face * 0.004, y, z), Vector3(face, 0, 0), Vector2(u * w, v * h)))
			grid.append(row)
		for j in rows:
			for i in cols:
				var r0: PackedInt32Array = grid[j]
				var r1: PackedInt32Array = grid[j + 1]
				k._t(r0[i], r0[i + 1], r1[i + 1])
				k._t(r0[i], r1[i + 1], r1[i])
	k.pop()


## A colossal robed and hooded statue holding a sword point-down (guardians,
## kings). at = base centre on the floor, facing +z rotated by yaw. h = total height.
## beard: a long carved beard instead of a dark hood (dwarf kings).
static func statue(k: K, at: Vector3, yaw: float, h: float, code: int, tint: Color, beard := false, crown := false) -> void:
	k.push_at(at, yaw)
	var s := h / 8.0
	k.mat(code, tint, 0.35)
	# plinth
	k.box(Vector3(0, 0.45 * s, 0), Vector3(2.6 * s, 0.9 * s, 2.6 * s), 0.08 * s)
	k.box(Vector3(0, 1.0 * s, 0), Vector3(2.2 * s, 0.2 * s, 2.2 * s), 0.05 * s)
	# robe with deep folds
	k.lathe(PackedVector2Array([Vector2(1.0 * s, 1.1 * s), Vector2(0.92 * s, 2.0 * s), Vector2(0.72 * s, 3.6 * s), Vector2(0.6 * s, 4.6 * s),
			Vector2(0.72 * s, 5.5 * s), Vector2(0.78 * s, 6.0 * s), Vector2(0.55 * s, 6.35 * s)]), 20, 0.0, TAU, 0.12)
	# shoulders / mantle
	k.rock(Vector3(0, 5.95 * s, 0), Vector3(1.05 * s, 0.42 * s, 0.62 * s), 0.08, 2, 7)
	# arms folded forward to the hilt
	for side: float in [-1.0, 1.0]:
		var path := K.bezier(Vector3(side * 0.85 * s, 5.8 * s, 0.0), Vector3(side * 0.95 * s, 4.7 * s, 0.35 * s), Vector3(side * 0.18 * s, 4.75 * s, 0.75 * s), 8)
		var radii := PackedFloat32Array()
		for i in path.size():
			radii.append(lerpf(0.3, 0.22, float(i) / path.size()) * s)
		k.sweep(path, radii, 8)
	k.rock(Vector3(0, 4.8 * s, 0.82 * s), Vector3(0.3 * s, 0.25 * s, 0.22 * s), 0.1, 2, 8)
	# sword, point down in front
	k.mat(code, tint * Color(0.85, 0.85, 0.9), 0.35)
	k.box(Vector3(0, 3.2 * s, 0.95 * s), Vector3(0.36 * s, 3.2 * s, 0.1 * s), 0.02 * s)
	k.box(Vector3(0, 4.95 * s, 0.95 * s), Vector3(1.3 * s, 0.16 * s, 0.2 * s), 0.03 * s)
	k.box(Vector3(0, 5.35 * s, 0.95 * s), Vector3(0.14 * s, 0.7 * s, 0.14 * s), 0.02 * s)
	k.rock(Vector3(0, 5.75 * s, 0.95 * s), Vector3(0.13 * s, 0.13 * s, 0.13 * s), 0.05, 1, 9)
	k.spike(Vector3(0, 1.6 * s, 0.95 * s), Vector3.DOWN, 0.5 * s, 0.18 * s, 4, 3)
	k.mat(code, tint, 0.35)
	if beard:
		k.rock(Vector3(0, 6.75 * s, 0.05 * s), Vector3(0.42 * s, 0.48 * s, 0.42 * s), 0.08, 2, 10)
		k.lathe(PackedVector2Array([Vector2(0.05 * s, 4.9 * s), Vector2(0.4 * s, 5.4 * s), Vector2(0.48 * s, 6.1 * s), Vector2(0.38 * s, 6.55 * s)]), 12, -0.6 + PI * 0.5, 0.6 + PI * 0.5, 0.15)
		k.push(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.18 * s)))
		k.lathe(PackedVector2Array([Vector2(0.05 * s, 4.9 * s), Vector2(0.36 * s, 5.4 * s), Vector2(0.44 * s, 6.1 * s), Vector2(0.36 * s, 6.55 * s)]), 12, 0.0, TAU, 0.15)
		k.pop()
		if crown:
			k.mat(K.GOLD, Color(1, 1, 1), 1.0)
			k.lathe(PackedVector2Array([Vector2(0.44 * s, 7.05 * s), Vector2(0.46 * s, 7.3 * s)]), 14)
			for i in 7:
				var a := TAU * i / 7.0
				k.spike(Vector3(cos(a) * 0.42 * s, 7.25 * s, sin(a) * 0.42 * s), Vector3.UP, 0.4 * s, 0.09 * s, 4, i)
	else:
		# deep hood with a shadowed face
		k.lathe(PackedVector2Array([Vector2(0.62 * s, 6.2 * s), Vector2(0.6 * s, 6.9 * s), Vector2(0.45 * s, 7.45 * s), Vector2(0.08 * s, 7.85 * s)]), 16, 0.0, TAU, 0.06)
		k.mat(K.DARK, Color(0.02, 0.02, 0.02), 0.5)
		k.rock(Vector3(0, 6.75 * s, 0.38 * s), Vector3(0.36 * s, 0.42 * s, 0.25 * s), 0.05, 2, 11)
		if crown:
			k.mat(K.GLOW, Color(0.3, 0.85, 1.0), 1.0, 3.0)
			for side: float in [-1.0, 1.0]:
				k.rock(Vector3(side * 0.13 * s, 6.85 * s, 0.6 * s), Vector3(0.05, 0.035, 0.03) * s, 0.0, 1, 12)
	k.pop()


## Portcullis grid in gate space: x across (-w/2..w/2), y up (0..h), thin in z.
static func portcullis(w: float, h: float, seed_value := 3) -> K:
	var g := K.new(seed_value)
	g.mat(K.IRON, Color(1, 1, 1), 1.0)
	var bars := maxi(3, int(w / 0.42))
	for i in bars + 1:
		var x := -w * 0.5 + w * float(i) / bars
		g.box(Vector3(x, h * 0.5, 0), Vector3(0.1, h, 0.1), 0.015, false)
		g.spike(Vector3(x, 0.05, 0), Vector3.DOWN, 0.4, 0.07, 4, i)
	var rows := maxi(2, int(h / 0.85))
	for j in rows:
		var y := 0.6 + (h - 0.8) * float(j) / (rows - 1)
		g.box(Vector3(0, y, 0), Vector3(w + 0.1, 0.12, 0.16), 0.02, false)
	# rivets
	for j in rows:
		var y := 0.6 + (h - 0.8) * float(j) / (rows - 1)
		for i in range(0, bars + 1, 2):
			var x := -w * 0.5 + w * float(i) / bars
			g.box(Vector3(x, y, 0.1), Vector3(0.09, 0.09, 0.06), 0.02, false)
	return g
