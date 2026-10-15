class_name VillageProps
extends RefCounted
## Furniture and village props, modelled into ArchMesh buckets: tables,
## benches, beds, shelves, barrels, crates, sacks, carts, hay, the well,
## market stalls, lamp posts, signposts, fences, woodpiles, the smithy's kit,
## the chapel's pews and the tavern's sign. Worker-thread safe.

const L = ArchMaterials.L

const OAK := Color(0.62, 0.47, 0.34)
const DARK_OAK := Color(0.42, 0.32, 0.24)
const LINEN := Color(0.86, 0.82, 0.72)


# --- Small props (any frame) ----------------------------------------------------

static func barrel(m: ArchMesh, p: Vector3, h := 0.95, r := 0.36, yaw := 0.0, lying := false) -> void:
	var t := Transform3D(Basis(Vector3.UP, yaw), p)
	if lying:
		t = t * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, r, -0.0)) * Transform3D(Basis.IDENTITY, Vector3(0, -h * 0.5, 0))
	m.push(t)
	m.mat(L.BOARDS, OAK * Color(1.1, 1.0, 0.92), 0.3)
	var prof := PackedVector2Array()
	for i in 7:
		var f := float(i) / 6.0
		prof.append(Vector2(r * (0.86 + 0.14 * sin(f * PI)), h * f))
	m.lathe(Vector3.ZERO, prof, 14, true, false)
	m.mat(L.BOARDS, OAK * Color(0.95, 0.85, 0.75), 0.2)
	m.lathe(Vector3(0, h - 0.035, 0), PackedVector2Array([Vector2(r * 0.8, 0.0), Vector2(r * 0.8, 0.01)]), 14, false, true)
	m.mat(L.IRON, Color(0.8, 0.8, 0.8), 0.0)
	for f: float in [0.1, 0.32, 0.68, 0.9]:
		var rr := r * (0.86 + 0.14 * sin(f * PI)) + 0.008
		m.lathe(Vector3(0, h * f - 0.025, 0), PackedVector2Array([Vector2(rr, 0.0), Vector2(rr, 0.05)]), 14, false, false)
	m.pop()


static func crate(m: ArchMesh, p: Vector3, s := 0.6, yaw := 0.0) -> void:
	m.push(Transform3D(Basis(Vector3.UP, yaw), p))
	m.mat(L.BOARDS, OAK * Color(1.15, 1.05, 0.95), 0.3)
	m.box(Vector3(0, s * 0.5, 0), Vector3(s, s, s) * 0.96, 0)
	m.mat(L.TIMBER, OAK * Color(0.9, 0.85, 0.8), 0.3)
	var e := s * 0.5
	for a: float in [-1.0, 1.0]:
		for c: float in [-1.0, 1.0]:
			m.box(Vector3(a * (e - 0.03), e, c * (e - 0.03)), Vector3(0.07, s, 0.07), 1)
			m.box(Vector3(a * (e - 0.03), s - 0.035 if c > 0.0 else 0.035, 0), Vector3(0.07, 0.07, s), 2)
			m.box(Vector3(0, s - 0.035 if c > 0.0 else 0.035, a * (e - 0.03)), Vector3(s, 0.07, 0.07), 0)
	m.pop()


static func sack(m: ArchMesh, p: Vector3, h := 0.7, yaw := 0.0, tint := Color(0.72, 0.6, 0.45)) -> void:
	m.push(Transform3D(Basis(Vector3.UP, yaw), p))
	m.mat(L.LINEN, tint, 0.2)
	m.lathe(Vector3.ZERO, PackedVector2Array([Vector2(0.22, 0.0), Vector2(0.3, 0.12), Vector2(0.29, h * 0.55), Vector2(0.2, h * 0.85), Vector2(0.08, h * 0.92), Vector2(0.1, h)]), 10, true, true, yaw)
	m.pop()


static func hay_bale(m: ArchMesh, p: Vector3, yaw := 0.0, r := 0.65, length := 1.1) -> void:
	m.push(Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, r, 0)))
	m.push(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO))
	m.mat(L.THATCH, Color(1.08, 0.98, 0.72), 0.25)
	var prof := PackedVector2Array()
	prof.append(Vector2(0.0, -length * 0.5))
	prof.append(Vector2(r * 0.9, -length * 0.5))
	prof.append(Vector2(r, -length * 0.42))
	prof.append(Vector2(r, length * 0.42))
	prof.append(Vector2(r * 0.9, length * 0.5))
	prof.append(Vector2(0.0, length * 0.5))
	m.lathe(Vector3.ZERO, prof, 16, false, false)
	m.pop()
	m.pop()


static func woodpile(m: ArchMesh, p: Vector3, length := 1.6, yaw := 0.0, rows := 3) -> void:
	m.push(Transform3D(Basis(Vector3.UP, yaw), p))
	m.mat(L.TIMBER, Color(0.75, 0.62, 0.5), 0.3)
	var r := 0.11
	for row in rows:
		var n := int(length / (r * 2.1)) - row
		for i in n:
			var x := -length * 0.5 + r + (row * r) + i * r * 2.1
			var y := r + row * r * 1.75
			m.cylinder(Vector3(x, y, -0.4), Vector3(x, y, 0.4), r * (0.85 + 0.15 * sin(i * 3.1 + row)), -1.0, 7)
	m.pop()


static func bench(m: ArchMesh, p: Vector3, length := 1.6, yaw := 0.0, back := false) -> void:
	m.push(Transform3D(Basis(Vector3.UP, yaw), p))
	m.mat(L.FLOOR, OAK, 0.3)
	m.box(Vector3(0, 0.44, 0), Vector3(length, 0.06, 0.34), 0)
	m.mat(L.TIMBER, OAK * Color(0.9, 0.88, 0.85), 0.3)
	for s: float in [-1.0, 1.0]:
		var x := s * (length * 0.5 - 0.15)
		m.box(Vector3(x, 0.21, 0), Vector3(0.07, 0.42, 0.3), 1)
		m.box(Vector3(x, 0.07, 0), Vector3(0.09, 0.07, 0.36), 2)
	m.box(Vector3(0, 0.2, 0), Vector3(length - 0.3, 0.06, 0.06), 0)
	if back:
		m.mat(L.FLOOR, OAK, 0.3)
		m.box(Vector3(0, 0.82, -0.16), Vector3(length, 0.22, 0.04), 0)
		for s: float in [-1.0, 1.0]:
			m.box(Vector3(s * (length * 0.5 - 0.15), 0.64, -0.16), Vector3(0.07, 0.5, 0.05), 1)
	m.pop()


static func table(m: ArchMesh, p: Vector3, size: Vector2, yaw := 0.0, rng: RandomNumberGenerator = null, laid := true) -> void:
	m.push(Transform3D(Basis(Vector3.UP, yaw), p))
	m.mat(L.FLOOR, OAK * Color(1.05, 1.0, 0.95), 0.2)
	m.box(Vector3(0, 0.75, 0), Vector3(size.x, 0.07, size.y), 0)
	m.mat(L.TIMBER, OAK * Color(0.85, 0.8, 0.75), 0.2)
	for a: float in [-1.0, 1.0]:
		for c: float in [-1.0, 1.0]:
			m.box(Vector3(a * (size.x * 0.5 - 0.12), 0.36, c * (size.y * 0.5 - 0.1)), Vector3(0.08, 0.72, 0.08), 1)
		m.box(Vector3(a * (size.x * 0.5 - 0.12), 0.12, 0), Vector3(0.06, 0.06, size.y - 0.2), 2)
	m.box(Vector3(0, 0.12, 0), Vector3(size.x - 0.24, 0.06, 0.06), 0)
	if laid and rng != null:
		var n := rng.randi_range(2, 4)
		for i in n:
			var q := Vector3(rng.randf_range(-size.x * 0.35, size.x * 0.35), 0.785, rng.randf_range(-size.y * 0.3, size.y * 0.3))
			match rng.randi() % 4:
				0:
					tankard(m, q)
				1:
					m.mat(L.FLAT, Color(0.55, 0.36, 0.25), 0.0)
					m.lathe(q, PackedVector2Array([Vector2(0.06, 0.0), Vector2(0.13, 0.05), Vector2(0.14, 0.07)]), 10, true, false)
				2:
					m.mat(L.FLAT, Color(0.72, 0.5, 0.26), 0.0)
					m.push(Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 0.6, 1.5)), q))
					m.lathe(Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.09, 0.02), Vector2(0.1, 0.07), Vector2(0.06, 0.11), Vector2(0.0, 0.12)]), 8, false, false)
					m.pop()
				_:
					candle(m, q)
	m.pop()


static func tankard(m: ArchMesh, p: Vector3) -> void:
	m.mat(L.BOARDS, OAK * Color(1.1, 1.0, 0.9), 0.2)
	m.lathe(p, PackedVector2Array([Vector2(0.05, 0.0), Vector2(0.055, 0.14), Vector2(0.05, 0.14)]), 10, true, false)
	m.mat(L.IRON, Color(0.8, 0.8, 0.8), 0.0)
	m.lathe(p + Vector3(0, 0.02, 0), PackedVector2Array([Vector2(0.056, 0.0), Vector2(0.056, 0.02)]), 10, false, false)
	m.lathe(p + Vector3(0, 0.11, 0), PackedVector2Array([Vector2(0.058, 0.0), Vector2(0.058, 0.02)]), 10, false, false)


static func candle(m: ArchMesh, p: Vector3) -> void:
	m.mat(L.IRON, Color(0.7, 0.62, 0.45), 0.0)
	m.lathe(p, PackedVector2Array([Vector2(0.06, 0.0), Vector2(0.06, 0.012), Vector2(0.015, 0.02), Vector2(0.015, 0.03)]), 8, true, false)
	m.mat(L.FLAT, Color(0.92, 0.88, 0.78), 0.0)
	m.lathe(p + Vector3(0, 0.03, 0), PackedVector2Array([Vector2(0.018, 0.0), Vector2(0.018, 0.13)]), 6, false, true)
	m.mat(L.EMBER, Color(1.4, 1.2, 0.9), 0.0)
	m.lathe(p + Vector3(0, 0.16, 0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.012, 0.015), Vector2(0.0, 0.05)]), 5, false, false)


static func stool(m: ArchMesh, p: Vector3) -> void:
	m.mat(L.FLOOR, OAK, 0.2)
	m.lathe(p + Vector3(0, 0.44, 0), PackedVector2Array([Vector2(0.17, 0.0), Vector2(0.18, 0.02), Vector2(0.17, 0.05)]), 10, true, true)
	m.mat(L.TIMBER, OAK * Color(0.85, 0.8, 0.75), 0.2)
	for i in 3:
		var a := TAU * i / 3.0
		m.cylinder(p + Vector3(cos(a) * 0.17, 0.0, sin(a) * 0.17), p + Vector3(cos(a) * 0.1, 0.45, sin(a) * 0.1), 0.022, -1.0, 5)


static func bed(m: ArchMesh, p: Vector3, yaw: float, blanket: Color) -> void:
	m.push(Transform3D(Basis(Vector3.UP, yaw), p))
	# Frame: along +x 1.9 m, 0.95 wide.
	m.mat(L.TIMBER, OAK * Color(0.95, 0.88, 0.8), 0.2)
	for x: float in [-0.9, 0.9]:
		for z: float in [-0.42, 0.42]:
			var top := 0.95 if x < 0.0 else 0.6
			m.box(Vector3(x, top * 0.5, z), Vector3(0.09, top, 0.09), 1)
	m.box(Vector3(-0.9, 0.78, 0), Vector3(0.05, 0.3, 0.84), 2)
	for z: float in [-0.42, 0.42]:
		m.box(Vector3(0, 0.3, z), Vector3(1.75, 0.14, 0.05), 0)
	for x: float in [-0.9, 0.9]:
		m.box(Vector3(x, 0.3, 0), Vector3(0.05, 0.14, 0.8), 2)
	# Straw mattress, blanket and pillow.
	m.mat(L.LINEN, LINEN * Color(1.0, 0.95, 0.82), 0.1)
	m.box(Vector3(0, 0.44, 0), Vector3(1.76, 0.16, 0.82), 0)
	m.mat(L.LINEN, blanket, 0.1)
	m.box(Vector3(0.22, 0.535, 0), Vector3(1.32, 0.05, 0.9), 0)
	m.box(Vector3(0.22, 0.4, 0.45), Vector3(1.32, 0.3, 0.025), 0)
	m.box(Vector3(0.22, 0.4, -0.45), Vector3(1.32, 0.3, 0.025), 0)
	m.mat(L.LINEN, LINEN * Color(1.1, 1.08, 1.02), 0.05)
	m.push(Transform3D(Basis.IDENTITY.scaled(Vector3(0.6, 0.35, 1.0)), Vector3(-0.68, 0.57, 0)))
	m.lathe(Vector3.ZERO, PackedVector2Array([Vector2(0.0, -0.3), Vector2(0.25, -0.25), Vector2(0.3, 0.0), Vector2(0.25, 0.25), Vector2(0.0, 0.3)]), 8, false, false)
	m.pop()
	m.pop()


static func shelf(m: ArchMesh, p: Vector3, yaw: float, length: float, rng: RandomNumberGenerator) -> void:
	m.push(Transform3D(Basis(Vector3.UP, yaw), p))
	for k in 2:
		var y := 1.2 + k * 0.45
		m.mat(L.FLOOR, OAK, 0.2)
		m.box(Vector3(0, y, 0.14), Vector3(length, 0.04, 0.28), 0)
		m.mat(L.IRON, Color(0.7, 0.7, 0.7), 0.0)
		for s: float in [-1.0, 1.0]:
			m.box(Vector3(s * (length * 0.5 - 0.1), y - 0.08, 0.04), Vector3(0.03, 0.16, 0.08), 1)
		var x := -length * 0.5 + 0.12
		while x < length * 0.5 - 0.15:
			var q := Vector3(x, y + 0.02, 0.14)
			match rng.randi() % 5:
				0:
					m.mat(L.FLAT, Color(0.58, 0.36, 0.24), 0.0)
					m.lathe(q, PackedVector2Array([Vector2(0.06, 0.0), Vector2(0.09, 0.08), Vector2(0.07, 0.17), Vector2(0.04, 0.2), Vector2(0.045, 0.23)]), 9, true, false)
				1:
					m.mat(L.FLAT, Color(0.42, 0.45, 0.4), 0.0)
					m.lathe(q, PackedVector2Array([Vector2(0.07, 0.0), Vector2(0.08, 0.12), Vector2(0.05, 0.15)]), 9, true, true)
				2:
					m.mat(L.FLAT, Color(0.86, 0.72, 0.36), 0.0)
					m.lathe(q, PackedVector2Array([Vector2(0.11, 0.0), Vector2(0.12, 0.05), Vector2(0.11, 0.09)]), 10, true, true)
				3:
					sack(m, q, 0.28, rng.randf() * TAU)
				_:
					m.mat(L.FLAT, Color(0.7, 0.66, 0.6), 0.0)
					m.lathe(q, PackedVector2Array([Vector2(0.05, 0.0), Vector2(0.11, 0.04), Vector2(0.12, 0.06)]), 10, true, false)
			x += rng.randf_range(0.18, 0.32)
	m.pop()


static func rug(m: ArchMesh, p: Vector3, size: Vector2, yaw: float, a: Color, b: Color) -> void:
	m.push(Transform3D(Basis(Vector3.UP, yaw), p))
	var n := 7
	for i in n:
		m.mat(L.LINEN, a if i % 2 == 0 else b, 0.1)
		var z := -size.y * 0.5 + size.y * (i + 0.5) / n
		m.box(Vector3(0, 0.012, z), Vector3(size.x, 0.02, size.y / n), 0)
	m.pop()


static func cauldron(m: ArchMesh, p: Vector3) -> void:
	m.mat(L.IRON, Color(0.55, 0.55, 0.55), 0.0)
	m.lathe(p, PackedVector2Array([Vector2(0.0, 0.08), Vector2(0.15, 0.1), Vector2(0.24, 0.2), Vector2(0.25, 0.32), Vector2(0.22, 0.42), Vector2(0.24, 0.44), Vector2(0.21, 0.44), Vector2(0.2, 0.38)]), 12, false, false)
	m.mat(L.FLAT, Color(0.3, 0.2, 0.12), 0.0)
	m.lathe(p + Vector3(0, 0.36, 0), PackedVector2Array([Vector2(0.205, 0.0), Vector2(0.0, 0.0)]), 12, false, false)
	for i in 3:
		var a := TAU * i / 3.0
		m.cylinder(p + Vector3(cos(a) * 0.14, 0.0, sin(a) * 0.14), p + Vector3(cos(a) * 0.16, 0.14, sin(a) * 0.16), 0.02, -1.0, 4)


# --- Interiors ----------------------------------------------------------------------

## Furniture from the plan's cells (spec["furniture"]), plus loose clutter.
static func furnish(b: ArchBuild, spec: Dictionary, rng: RandomNumberGenerator, t: float) -> void:
	var m := b.interior
	var w := float(spec["w"])
	var d := float(spec["d"])
	var kind := String(spec["kind"])
	var blanket: Color = [Color(0.55, 0.16, 0.12), Color(0.2, 0.32, 0.22), Color(0.22, 0.28, 0.42), Color(0.6, 0.45, 0.2)][rng.randi() % 4]
	for f: Dictionary in spec.get("furniture", []):
		var cell: Vector2i = f["cell"]
		var size: Vector2i = f.get("size", Vector2i.ONE)
		var c := Vector3(cell.x + size.x * 0.5 - w * 0.5, 0.0, cell.y + size.y * 0.5 - d * 0.5)
		match String(f["kind"]):
			"bed":
				var yaw := 0.0 if size.x >= size.y else PI * 0.5
				bed(m, c, yaw + (PI if c.x > 0.0 and size.x >= size.y else 0.0), blanket)
				rug(m, c + Vector3(0, 0, 0.75 if c.z < 0.0 else -0.75), Vector2(1.2, 0.6), 0.0, Color(0.5, 0.2, 0.15), Color(0.7, 0.6, 0.4))
			"table":
				var along_x := size.x >= size.y
				table(m, c, Vector2(1.7, 0.85) if along_x else Vector2(0.85, 1.7), 0.0, rng)
				for s: float in [-1.0, 1.0]:
					if along_x:
						bench(m, c + Vector3(0, 0, s * 0.68), 1.5, 0.0)
					else:
						bench(m, c + Vector3(s * 0.68, 0, 0), 1.5, PI * 0.5)
			"counter":
				_counter(m, c, size, rng)
			"barrels":
				for i in 3:
					barrel(m, c + Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25)) + Vector3(-0.3 + i * 0.32, 0, 0), 0.9, 0.3, rng.randf() * TAU)
			"long_hearth":
				_long_hearth(b, c, size)
			"high_seat":
				_high_seat(m, c, spec)
			_:
				pass
	# Shelves on the back wall, a cauldron by the hearth, sacks and a barrel.
	var back_z := -d * 0.5 + t
	if kind != "tavern":
		shelf(m, Vector3(rng.randf_range(-w * 0.15, w * 0.15), 0, back_z), 0.0, minf(1.8, w * 0.3), rng)
	var chimney := int(spec.get("chimney", 0))
	if chimney != 0:
		cauldron(m, Vector3(chimney * (w * 0.5 - t - 1.1), 0, 0.85))
		woodpile(m, Vector3(chimney * (w * 0.5 - t - 0.85), 0, -1.0), 0.8, PI * 0.5, 2)
	var corner := Vector3(-chimney * (w * 0.5 - t - 0.45) if chimney != 0 else w * 0.5 - t - 0.45, 0, d * 0.5 - t - 0.45)
	barrel(m, corner, 0.85, 0.3, rng.randf() * TAU)
	sack(m, corner + Vector3(0, 0, -0.65), 0.65, rng.randf() * TAU)
	# Hanging herbs from a beam and a light that keeps the room warm.
	b.add_light(Vector3(0, 2.3, 0), Color(1.0, 0.7, 0.42), maxf(w, d) * 0.75, 0.55, false)


static func _counter(m: ArchMesh, c: Vector3, size: Vector2i, rng: RandomNumberGenerator) -> void:
	var length := float(maxi(size.x, size.y))
	var along_x := size.x >= size.y
	m.push(Transform3D(Basis(Vector3.UP, 0.0 if along_x else PI * 0.5), c))
	m.mat(L.BOARDS, DARK_OAK * Color(1.2, 1.1, 1.0), 0.2)
	m.box(Vector3(0, 0.5, 0), Vector3(length - 0.1, 1.0, 0.55), 1)
	m.mat(L.FLOOR, DARK_OAK * Color(1.3, 1.2, 1.1), 0.1)
	m.box(Vector3(0, 1.04, 0.03), Vector3(length, 0.08, 0.68), 0)
	for i in int(length / 0.45):
		if rng.randf() < 0.5:
			tankard(m, Vector3(-length * 0.5 + 0.3 + i * 0.45, 1.08, 0.1))
	m.pop()


## The longhouse's central fire pit, lined with stones.
static func _long_hearth(b: ArchBuild, c: Vector3, size: Vector2i) -> void:
	var m := b.interior
	var length := float(maxi(size.x, size.y)) - 0.4
	var width := float(mini(size.x, size.y)) - 0.3
	m.mat(L.RUBBLE, Color(0.7, 0.68, 0.65), 0.0, 0.5)
	var n := int(length / 0.35)
	for i in n:
		for s: float in [-1.0, 1.0]:
			var x := -length * 0.5 + (i + 0.5) * length / n
			m.box(c + Vector3(x, 0.1, s * width * 0.5), Vector3(length / n * 0.92, 0.2, 0.26), 0)
	m.mat(L.EMBER, Color(1, 1, 1), 0.0)
	m.push(Transform3D(Basis.IDENTITY.scaled(Vector3(length * 0.5 / 0.4, 1.0, width * 0.5 / 0.4)), c))
	m.lathe(Vector3.ZERO, PackedVector2Array([Vector2(0.4, 0.0), Vector2(0.3, 0.05), Vector2(0.0, 0.08)]), 10, false, false)
	m.pop()
	m.mat(L.TIMBER, Color(0.35, 0.27, 0.2), 0.0, 0.4)
	m.cylinder(c + Vector3(-0.5, 0.1, -0.1), c + Vector3(0.4, 0.12, 0.15), 0.07, -1.0, 6)
	m.cylinder(c + Vector3(-0.2, 0.15, 0.2), c + Vector3(0.6, 0.1, -0.15), 0.065, -1.0, 6)
	b.add_fire(c + Vector3(0, 0.12, 0), 1.2, 9.0, 2.2)
	cauldron(m, c + Vector3(length * 0.35, 0, 0))


static func _high_seat(m: ArchMesh, c: Vector3, spec: Dictionary) -> void:
	m.push(Transform3D(Basis.IDENTITY, c))
	m.mat(L.TIMBER, DARK_OAK, 0.2)
	m.box(Vector3(0, 0.2, 0), Vector3(1.6, 0.4, 0.9), 0)
	m.box(Vector3(0, 0.62, -0.05), Vector3(0.8, 0.08, 0.6), 0)
	m.box(Vector3(0, 1.3, -0.33), Vector3(0.9, 1.4, 0.1), 1)
	for s: float in [-1.0, 1.0]:
		m.box(Vector3(s * 0.42, 0.85, -0.05), Vector3(0.08, 0.5, 0.6), 1)
		m.mat(L.TIMBER, DARK_OAK * Color(1.3, 1.2, 1.0), 0.1)
		m.cylinder(Vector3(s * 0.45, 0.4, -0.35), Vector3(s * 0.45, 2.2, -0.35), 0.06, -1.0, 6)
		m.mat(L.TIMBER, DARK_OAK, 0.2)
	m.mat(L.LINEN, _style_color(spec, "banner", Color(0.5, 0.12, 0.1)), 0.1)
	m.box(Vector3(0, 1.75, -0.4), Vector3(0.7, 1.0, 0.02), 1)
	m.pop()


static func _style_color(spec: Dictionary, key: String, fallback: Color) -> Color:
	var st: Dictionary = spec.get("style", {})
	return st.get(key, fallback)


# --- Smithy, chapel, tavern -----------------------------------------------------------

## Bellows, quench trough, tool rack, grindstone, coal and stock.
static func smithy_kit(b: ArchBuild, spec: Dictionary, rng: RandomNumberGenerator, fx: float, fz: float) -> void:
	var m := b.interior
	var w := float(spec["w"])
	var d := float(spec["d"])
	# Bellows beside the forge.
	m.push(Transform3D(Basis(Vector3.UP, 0.3), Vector3(fx + 1.35, 0.55, fz + 0.1)))
	m.mat(L.TIMBER, DARK_OAK, 0.2)
	m.box(Vector3(0, 0.0, 0), Vector3(0.55, 0.05, 1.0), 2)
	m.box(Vector3(0, 0.22, 0.05), Vector3(0.5, 0.05, 0.9), 2)
	m.mat(L.LINEN, Color(0.42, 0.28, 0.18), 0.1)
	m.box(Vector3(0, 0.11, 0.05), Vector3(0.46, 0.18, 0.8), 2)
	m.mat(L.IRON, Color(0.7, 0.7, 0.7), 0.0)
	m.cylinder(Vector3(0, 0.1, -0.5), Vector3(0, 0.1, -0.8), 0.04, 0.025, 6)
	m.mat(L.TIMBER, OAK, 0.2)
	for s: float in [-1.0, 1.0]:
		m.box(Vector3(s * 0.2, -0.28, 0.0), Vector3(0.06, 0.55, 0.06), 1)
	m.pop()
	# Quench trough.
	var tq := Vector3(fx - 0.2, 0, fz + 1.3)
	m.mat(L.BOARDS, DARK_OAK * Color(1.1, 1.0, 0.9), 0.4)
	m.box(tq + Vector3(0, 0.25, 0.25), Vector3(1.2, 0.5, 0.06), 0)
	m.box(tq + Vector3(0, 0.25, -0.25), Vector3(1.2, 0.5, 0.06), 0)
	m.box(tq + Vector3(0.57, 0.25, 0), Vector3(0.06, 0.5, 0.44), 2)
	m.box(tq + Vector3(-0.57, 0.25, 0), Vector3(0.06, 0.5, 0.44), 2)
	m.box(tq + Vector3(0, 0.04, 0), Vector3(1.1, 0.06, 0.44), 0)
	m.mat(L.WATER, Color(1, 1, 1), 0.0)
	m.rect(tq + Vector3(-0.54, 0.42, 0.22), Vector3.RIGHT, Vector3.FORWARD, 1.08, 0.44)
	# Tool rack on the back wall with tongs and hammers.
	var rack := Vector3(w * 0.5 - 1.6, 1.5, -d * 0.5 + 0.58)
	m.mat(L.TIMBER, OAK, 0.2)
	m.box(rack, Vector3(1.6, 0.1, 0.06), 0)
	m.mat(L.IRON, Color(0.6, 0.6, 0.62), 0.0)
	for i in 6:
		var x := rack.x - 0.65 + i * 0.26
		if i % 2 == 0:
			m.beam(Vector3(x - 0.04, rack.y + 0.02, rack.z + 0.05), Vector3(x - 0.08, rack.y - 0.62, rack.z + 0.06), 0.025, 0.02)
			m.beam(Vector3(x + 0.04, rack.y + 0.02, rack.z + 0.05), Vector3(x + 0.08, rack.y - 0.62, rack.z + 0.06), 0.025, 0.02)
		else:
			m.beam(Vector3(x, rack.y + 0.02, rack.z + 0.05), Vector3(x, rack.y - 0.45, rack.z + 0.05), 0.03, 0.03)
			m.box(Vector3(x, rack.y - 0.5, rack.z + 0.06), Vector3(0.14, 0.07, 0.07), 0)
	# Horseshoes on a nail board.
	for i in 4:
		m.push(Transform3D(Basis(Vector3.BACK, PI), Vector3(rack.x - 0.4 + i * 0.27, rack.y + 0.45, rack.z + 0.02)))
		m.lathe(Vector3.ZERO, PackedVector2Array([Vector2(0.07, -0.01), Vector2(0.09, 0.0), Vector2(0.07, 0.01), Vector2(0.07, -0.01)]), 9, false, false)
		m.pop()
	# Grindstone on its frame.
	var g := Vector3(w * 0.5 - 1.2, 0, 0.6)
	m.mat(L.TIMBER, OAK, 0.3)
	for s: float in [-1.0, 1.0]:
		m.box(g + Vector3(s * 0.22, 0.4, 0), Vector3(0.08, 0.8, 0.5), 1)
	m.mat(L.ASHLAR, Color(0.85, 0.8, 0.72), 0.2)
	m.push(Transform3D(Basis(Vector3.BACK, PI * 0.5), g + Vector3(0, 0.75, 0)))
	m.lathe(Vector3(0, -0.08, 0), PackedVector2Array([Vector2(0.38, 0.0), Vector2(0.38, 0.16)]), 16, true, true)
	m.pop()
	m.mat(L.IRON, Color(0.6, 0.6, 0.6), 0.0)
	m.cylinder(g + Vector3(-0.35, 0.75, 0), g + Vector3(0.45, 0.75, 0), 0.025, -1.0, 6)
	# Coal heap, iron stock and barrels.
	m.mat(L.COBBLE, Color(0.25, 0.24, 0.24), 0.0, 0.6)
	m.lathe(Vector3(fx - 1.25, 0, fz + 0.15), PackedVector2Array([Vector2(0.55, 0.0), Vector2(0.4, 0.2), Vector2(0.0, 0.32)]), 9, false, false)
	m.mat(L.IRON, Color(0.6, 0.6, 0.62), 0.0)
	for i in 5:
		m.box(Vector3(w * 0.5 - 0.9, 0.05 + i * 0.05, -d * 0.5 + 1.3 + (i % 2) * 0.03), Vector3(1.0, 0.04, 0.05), 0)
	barrel(b.detail, Vector3(w * 0.5 - 0.6, 0, d * 0.5 + 0.6), 0.9, 0.32, rng.randf() * TAU)
	crate(b.detail, Vector3(-w * 0.5 + 0.6, 0, d * 0.5 + 0.7), 0.6, 0.3)


static func chapel_furniture(b: ArchBuild, spec: Dictionary, rng: RandomNumberGenerator, t: float) -> void:
	var m := b.interior
	var w := float(spec["w"])
	var d := float(spec["d"])
	# Pews either side of the aisle, facing the altar at the back (-z).
	var rows := int((d - 4.0) / 1.0)
	for i in rows:
		var z := -d * 0.5 + 3.2 + i * 1.0
		for s: float in [-1.0, 1.0]:
			bench(m, Vector3(s * (w * 0.25 + 0.15), 0, z), w * 0.5 - 1.2, PI, true)
	# Altar with a cloth, candles and a lectern.
	var az := -d * 0.5 + t + 1.0
	m.mat(L.ASHLAR, Color(0.95, 0.92, 0.86), 0.1)
	m.box(Vector3(0, 0.15, az), Vector3(3.0, 0.3, 2.0), 0)
	m.box(Vector3(0, 0.75, az - 0.2), Vector3(1.8, 0.9, 0.8), 0)
	m.mat(L.LINEN, _style_color(spec, "banner", Color(0.55, 0.12, 0.1)), 0.0)
	m.box(Vector3(0, 1.21, az - 0.2), Vector3(1.9, 0.02, 0.9), 0)
	m.box(Vector3(0, 0.9, az + 0.25), Vector3(1.0, 0.6, 0.02), 0)
	for x: float in [-0.7, -0.35, 0.35, 0.7]:
		candle(m, Vector3(x, 1.22, az - 0.3))
	m.mat(L.TIMBER, DARK_OAK, 0.1)
	m.lathe(Vector3(w * 0.25, 0.3, az + 1.3), PackedVector2Array([Vector2(0.22, 0.0), Vector2(0.06, 0.05), Vector2(0.06, 0.95)]), 8, true, false)
	m.push(Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(w * 0.25, 1.3, az + 1.3)))
	m.box(Vector3.ZERO, Vector3(0.5, 0.04, 0.38), 0)
	m.pop()
	b.add_light(Vector3(0, 1.8, az), Color(1.0, 0.75, 0.45), 7.0, 1.2, false)
	b.add_light(Vector3(0, 2.6, d * 0.1), Color(0.9, 0.8, 0.65), w * 1.1, 0.5, false)


## Hanging sign, benches and barrels in front of the tavern.
static func tavern_front(b: ArchBuild, spec: Dictionary, rng: RandomNumberGenerator) -> void:
	var m := b.detail
	var w := float(spec["w"])
	var d := float(spec["d"])
	var door := float(spec.get("door", int(w) / 2))
	var sx := -w * 0.5 + door + 1.9
	# Sign on an iron bracket.
	m.mat(L.IRON, Color(0.7, 0.7, 0.7), 0.0)
	m.beam(Vector3(sx, 3.2, d * 0.5 + 0.02), Vector3(sx, 3.2, d * 0.5 + 1.15), 0.04, 0.05)
	m.beam(Vector3(sx, 2.8, d * 0.5 + 0.02), Vector3(sx, 3.18, d * 0.5 + 0.7), 0.03, 0.03)
	m.cylinder(Vector3(sx, 3.2, d * 0.5 + 0.35), Vector3(sx, 3.02, d * 0.5 + 0.35), 0.008, -1.0, 4)
	m.cylinder(Vector3(sx, 3.2, d * 0.5 + 1.05), Vector3(sx, 3.02, d * 0.5 + 1.05), 0.008, -1.0, 4)
	m.mat(L.BOARDS, Color(0.55, 0.4, 0.3), 0.3)
	m.box(Vector3(sx, 2.72, d * 0.5 + 0.7), Vector3(0.05, 0.6, 0.85), 2)
	m.mat(L.FLAT, _style_color(spec, "sign", Color(0.75, 0.55, 0.15)), 0.0)
	for s: float in [-1.0, 1.0]:
		m.push(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx + s * 0.03, 2.72, d * 0.5 + 0.7)))
		m.lathe(Vector3(0, 0, 0), PackedVector2Array([Vector2(0.13, -0.012), Vector2(0.17, 0.0), Vector2(0.13, 0.012)]), 12, false, false)
		m.pop()
	# Outside seating.
	var bz := d * 0.5 + 1.6
	for i in 2:
		var x := -w * 0.5 + 1.4 + i * 2.6
		if absf(x - (-w * 0.5 + door + 0.5)) < 1.6:
			x += 3.2
		if x > w * 0.5 - 1.0:
			continue
		table(m, Vector3(x, 0, bz), Vector2(1.5, 0.75), 0.0, rng)
		bench(m, Vector3(x, 0, bz - 0.62), 1.4, 0.0)
		bench(m, Vector3(x, 0, bz + 0.62), 1.4, 0.0)
	barrel(m, Vector3(w * 0.5 - 0.5, 0, d * 0.5 + 0.55), 0.95, 0.34, 0.4)
	barrel(m, Vector3(w * 0.5 - 1.2, 0, d * 0.5 + 0.5), 0.95, 0.34, 1.2)
	barrel(m, Vector3(w * 0.5 - 0.85, 0.95, d * 0.5 + 0.52), 0.95, 0.34, 2.1)
	b.add_light(Vector3(sx, 2.3, d * 0.5 + 0.8), Color(1.0, 0.62, 0.32), 9.0, 1.0, true)


# --- Village furniture (node space, on the ground) --------------------------------------

## The village well: a round stone kerb, a timber frame with a windlass and a
## little roof. p is on the ground at the well's centre.
static func well(b: ArchBuild, p: Vector3, roof_layer: int, roof_tint: Color, stone: Color, wood: Color) -> void:
	var m := b.detail
	b.shell.mat(L.RUBBLE, stone, 0.6)
	var prof := PackedVector2Array([Vector2(1.25, -1.0), Vector2(1.25, 0.82), Vector2(1.18, 0.9)])
	b.shell.lathe(p, prof, 18, false, false)
	b.shell.mat(L.ASHLAR, stone * Color(1.05, 1.03, 1.0), 0.5)
	b.shell.lathe(p + Vector3(0, 0.82, 0), PackedVector2Array([Vector2(1.32, 0.0), Vector2(1.32, 0.14), Vector2(0.9, 0.14), Vector2(0.9, 0.0)]), 18, false, false)
	b.shell.mat(L.RUBBLE, stone * Color(0.6, 0.6, 0.6), 0.2, 0.6)
	b.shell.lathe(p, PackedVector2Array([Vector2(0.9, 0.82), Vector2(0.9, -1.0)]), 18, false, false)
	b.shell.mat(L.WATER, Color(1, 1, 1), 0.0)
	b.shell.lathe(p + Vector3(0, -0.6, 0), PackedVector2Array([Vector2(0.9, 0.0), Vector2(0.0, 0.0)]), 18, false, false)
	# Frame and windlass.
	m.mat(L.TIMBER, wood, 0.4)
	for s: float in [-1.0, 1.0]:
		m.beam(p + Vector3(s * 1.08, 0.7, 0), p + Vector3(s * 1.08, 2.6, 0), 0.16, 0.16, Vector3.BACK, 0.02)
		m.beam(p + Vector3(s * 1.08, 0.75, 0.0), p + Vector3(s * 1.2, 0.0, 0.35), 0.1, 0.1)
	m.cylinder(p + Vector3(-1.2, 1.75, 0), p + Vector3(1.2, 1.75, 0), 0.09, -1.0, 8)
	m.beam(p + Vector3(1.2, 1.75, 0), p + Vector3(1.2, 1.4, 0.0), 0.05, 0.05)
	m.beam(p + Vector3(1.2, 1.4, 0.0), p + Vector3(1.4, 1.4, 0.0), 0.04, 0.04)
	m.mat(L.LINEN, Color(0.7, 0.6, 0.45), 0.1)
	m.cylinder(p + Vector3(-0.35, 1.75, 0), p + Vector3(0.35, 1.75, 0), 0.11, -1.0, 8)
	m.cylinder(p + Vector3(0.1, 1.66, 0.0), p + Vector3(0.1, 0.95, 0.0), 0.012, -1.0, 4)
	m.mat(L.BOARDS, OAK, 0.3)
	m.lathe(p + Vector3(0.1, 0.62, 0), PackedVector2Array([Vector2(0.14, 0.0), Vector2(0.17, 0.3), Vector2(0.155, 0.3), Vector2(0.13, 0.03), Vector2(0.0, 0.03)]), 10, true, false)
	m.mat(L.IRON, Color(0.7, 0.7, 0.7), 0.0)
	m.lathe(p + Vector3(0.1, 0.65, 0), PackedVector2Array([Vector2(0.148, 0.0), Vector2(0.15, 0.03)]), 10, false, false)
	m.lathe(p + Vector3(0.1, 0.86, 0), PackedVector2Array([Vector2(0.168, 0.0), Vector2(0.17, 0.03)]), 10, false, false)
	# Ridge roof.
	var pitch := deg_to_rad(38.0)
	var half := 1.15
	var rise := half * tan(pitch)
	m.mat(L.TIMBER, wood, 0.4)
	m.beam(p + Vector3(-1.4, 2.6, 0), p + Vector3(1.4, 2.6, 0), 0.14, 0.16, Vector3.UP, 0.015)
	var slope := half / cos(pitch)
	for sd: float in [1.0, -1.0]:
		var o := p + Vector3(-1.45, 2.6 - 0.22 * tan(pitch), sd * (half + 0.22))
		var v := Vector3(0, sin(pitch), -cos(pitch) * sd).normalized()
		var u := Vector3.RIGHT if sd > 0.0 else Vector3.LEFT
		if sd < 0.0:
			o.x = p.x + 1.45
		b.detail.mat(roof_layer, roof_tint, 0.5)
		b.detail.rect(o, u, v, 2.9, slope + 0.25, Vector2(0, 0))
		b.detail.mat(L.BOARDS, wood, 0.3)
		b.detail.rect(o + u * 2.9 + Vector3(0, -0.03, 0), -u, v, 2.9, slope + 0.25)
	m.mat(L.BOARDS, wood, 0.3)
	for s: float in [-1.0, 1.0]:
		m.tri(p + Vector3(s * 1.08, 2.6, -half), p + Vector3(s * 1.08, 2.6, half), p + Vector3(s * 1.08, 2.6 + rise, 0), Vector2(0, 0), Vector2(2.3, 0), Vector2(1.15, -rise), Vector3(s, 0, 0))


## Market stall: four posts, a counter with goods, a striped awning.
static func stall(b: ArchBuild, p: Vector3, yaw: float, rng: RandomNumberGenerator, a: Color, c: Color) -> void:
	var m := b.detail
	m.push(Transform3D(Basis(Vector3.UP, yaw), p))
	m.mat(L.TIMBER, OAK, 0.4)
	for x: float in [-1.2, 1.2]:
		m.beam(Vector3(x, 0, 0.6), Vector3(x, 2.2, 0.6), 0.1, 0.1, Vector3.BACK, 0.01)
		m.beam(Vector3(x, 0, -0.6), Vector3(x, 2.5, -0.6), 0.1, 0.1, Vector3.BACK, 0.01)
	m.mat(L.BOARDS, OAK * Color(1.1, 1.0, 0.9), 0.3)
	m.box(Vector3(0, 0.45, 0.45), Vector3(2.5, 0.9, 0.06), 0)
	m.mat(L.FLOOR, OAK, 0.2)
	m.box(Vector3(0, 0.92, 0.25), Vector3(2.6, 0.06, 0.8), 0)
	# Striped awning sloping towards the front.
	var n := 8
	var front := Vector3(0, 2.15, 1.05)
	var back := Vector3(0, 2.55, -0.65)
	for i in n:
		m.mat(L.LINEN, a if i % 2 == 0 else c, 0.1)
		var x0 := -1.35 + 2.7 * float(i) / n
		var x1 := -1.35 + 2.7 * float(i + 1) / n
		m.quad(Vector3(x0, front.y, front.z), Vector3(x1, front.y, front.z), Vector3(x1, back.y, back.z), Vector3(x0, back.y, back.z),
				Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, -1.8), Vector2(x0, -1.8), Vector3(0, 0.97, 0.23).normalized())
		m.quad(Vector3(x1, front.y - 0.01, front.z), Vector3(x0, front.y - 0.01, front.z), Vector3(x0, back.y - 0.01, back.z), Vector3(x1, back.y - 0.01, back.z),
				Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, -1.8), Vector2(x0, -1.8), Vector3(0, -0.97, -0.23).normalized())
		# Scalloped valance.
		m.quad(Vector3(x0, front.y, front.z), Vector3(x1, front.y, front.z), Vector3((x0 + x1) * 0.5, front.y - 0.28, front.z), Vector3(x0, front.y - 0.2, front.z),
				Vector2(0, 0), Vector2(0.3, 0), Vector2(0.15, 0.28), Vector2(0, 0.2), Vector3.BACK)
		m.quad(Vector3(x1, front.y, front.z - 0.005), Vector3(x0, front.y, front.z - 0.005), Vector3(x0, front.y - 0.2, front.z - 0.005), Vector3((x0 + x1) * 0.5, front.y - 0.28, front.z - 0.005),
				Vector2(0, 0), Vector2(0.3, 0), Vector2(0.15, 0.28), Vector2(0, 0.2), Vector3.FORWARD)
	# Goods: baskets of produce, crates, a sack.
	for i in 4:
		var q := Vector3(-0.95 + i * 0.63, 0.95, 0.25 + rng.randf_range(-0.1, 0.1))
		m.mat(L.THATCH, Color(0.75, 0.58, 0.38), 0.2)
		m.lathe(q, PackedVector2Array([Vector2(0.14, 0.0), Vector2(0.22, 0.14), Vector2(0.24, 0.16), Vector2(0.225, 0.16), Vector2(0.13, 0.03), Vector2(0.0, 0.03)]), 10, true, false)
		var fruit: Color = [Color(0.7, 0.12, 0.08), Color(0.85, 0.55, 0.1), Color(0.35, 0.5, 0.15), Color(0.55, 0.32, 0.5)][rng.randi() % 4]
		m.mat(L.FLAT, fruit, 0.0)
		for k in 5:
			var fa := TAU * k / 5.0 + rng.randf()
			m.lathe(q + Vector3(cos(fa) * 0.1, 0.12, sin(fa) * 0.1), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.05, 0.02), Vector2(0.055, 0.05), Vector2(0.04, 0.085), Vector2(0.0, 0.095)]), 7, false, false)
	crate(m, Vector3(-0.7, 0, -0.3), 0.55, 0.2)
	sack(m, Vector3(0.6, 0, -0.25), 0.7, 0.5)
	m.pop()


## Lamp post with a hanging lantern; lit at dusk.
static func lamp_post(b: ArchBuild, p: Vector3, yaw: float) -> void:
	var m := b.detail
	m.push(Transform3D(Basis(Vector3.UP, yaw), p))
	m.mat(L.TIMBER, DARK_OAK, 0.4)
	m.beam(Vector3(0, -0.4, 0), Vector3(0, 3.0, 0), 0.16, 0.16, Vector3.BACK, 0.025)
	m.beam(Vector3(0, 2.8, 0), Vector3(0, 2.8, 0.75), 0.08, 0.1)
	m.beam(Vector3(0, 2.3, 0.0), Vector3(0, 2.78, 0.5), 0.06, 0.06)
	m.mat(L.IRON, Color(0.55, 0.55, 0.55), 0.0)
	var lp := Vector3(0, 2.38, 0.68)
	m.cylinder(lp + Vector3(0, 0.42, 0), lp + Vector3(0, 0.3, 0), 0.008, -1.0, 4)
	m.lathe(lp + Vector3(0, 0.22, 0), PackedVector2Array([Vector2(0.15, 0.0), Vector2(0.03, 0.09)]), 6, true, false)
	m.lathe(lp, PackedVector2Array([Vector2(0.1, 0.0), Vector2(0.12, 0.025)]), 6, true, false)
	for i in 6:
		var a := TAU * i / 6.0
		m.beam(lp + Vector3(cos(a) * 0.11, 0.02, sin(a) * 0.11), lp + Vector3(cos(a) * 0.13, 0.22, sin(a) * 0.13), 0.015, 0.015)
	m.mat(L.GLASS, Color(1, 1, 1), 1.0)
	m.lathe(lp + Vector3(0, 0.025, 0), PackedVector2Array([Vector2(0.105, 0.0), Vector2(0.125, 0.19)]), 6, false, false)
	m.mat(L.EMBER, Color(1.5, 1.2, 0.8), 0.0)
	m.lathe(lp + Vector3(0, 0.05, 0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.025, 0.04), Vector2(0.0, 0.11)]), 5, false, false)
	m.pop()
	b.lights.append({"pos": b.detail.xf * (p + Basis(Vector3.UP, yaw) * Vector3(0, 2.45, 0.68)), "color": Color(1.0, 0.66, 0.34), "range": 11.0, "energy": 1.5, "night": true})


## A signpost with arms pointing along the given directions (node space).
static func signpost(b: ArchBuild, p: Vector3, dirs: Array) -> void:
	var m := b.detail
	m.mat(L.TIMBER, OAK * Color(0.9, 0.85, 0.8), 0.5)
	m.beam(p + Vector3(0, -0.3, 0), p + Vector3(0, 2.6, 0), 0.13, 0.13, Vector3.BACK, 0.02)
	m.lathe(p + Vector3(0, 2.6, 0), PackedVector2Array([Vector2(0.09, 0.0), Vector2(0.0, 0.14)]), 4, true, false, PI * 0.25)
	var y := 2.3
	for dir: Vector3 in dirs:
		var dd := Vector3(dir.x, 0, dir.z).normalized()
		if dd == Vector3.ZERO:
			continue
		var yaw := atan2(dd.x, dd.z)
		m.push(Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, y, 0)))
		m.mat(L.BOARDS, OAK * Color(1.2, 1.1, 1.0), 0.5)
		var pts := PackedVector2Array([Vector2(-0.12, -0.09), Vector2(0.75, -0.09), Vector2(0.9, 0.0), Vector2(0.75, 0.09), Vector2(-0.12, 0.09)])
		m.prism(Vector3(0.0, 0.0, 0.0), Vector3.BACK, Vector3.UP, pts, 0.035, true, true)
		m.pop()
		y -= 0.3


## Post-and-rail fence between two node-space ground points, following the ground.
static func fence(b: ArchBuild, a: Vector3, c: Vector3, wood: Color, wattle := false) -> void:
	var m := b.detail
	var length := Vector2(c.x - a.x, c.z - a.z).length()
	var n := maxi(1, int(ceil(length / 2.0)))
	var prev := Vector3.ZERO
	for i in n + 1:
		var f := float(i) / n
		var q := a.lerp(c, f)
		q.y = b.ground(q)
		m.mat(L.TIMBER, wood, 0.6)
		m.cylinder(q + Vector3(0, -0.3, 0), q + Vector3(0, 1.15, 0), 0.07, 0.06, 6)
		if i > 0:
			if wattle:
				m.mat(L.THATCH, Color(0.62, 0.5, 0.36), 0.4)
				var dir := (q - prev)
				var side := dir.cross(Vector3.UP).normalized()
				m.quad(prev + Vector3(0, 0.1, 0), q + Vector3(0, 0.1, 0), q + Vector3(0, 0.95, 0), prev + Vector3(0, 0.95, 0),
						Vector2(0, 0), Vector2(dir.length(), 0), Vector2(dir.length(), -0.85), Vector2(0, -0.85), side)
				m.quad(q + Vector3(0, 0.1, 0), prev + Vector3(0, 0.1, 0), prev + Vector3(0, 0.95, 0), q + Vector3(0, 0.95, 0),
						Vector2(0, 0), Vector2(dir.length(), 0), Vector2(dir.length(), -0.85), Vector2(0, -0.85), -side)
				m.mat(L.TIMBER, wood, 0.5)
				m.beam(prev + Vector3(0, 0.95, 0), q + Vector3(0, 0.95, 0), 0.05, 0.05)
			else:
				m.mat(L.TIMBER, wood * Color(1.1, 1.05, 1.0), 0.5)
				m.beam(prev + Vector3(0, 1.0, 0), q + Vector3(0, 1.0, 0), 0.07, 0.11, Vector3.UP, 0.01)
				m.beam(prev + Vector3(0, 0.55, 0), q + Vector3(0, 0.55, 0), 0.07, 0.11, Vector3.UP, 0.01)
		prev = q


## A two-wheeled hand cart, resting on its legs.
static func cart(b: ArchBuild, p: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var m := b.detail
	m.push(Transform3D(Basis(Vector3.UP, yaw), p))
	var tilt := Basis(Vector3.RIGHT, -0.09)
	m.push(Transform3D(tilt, Vector3(0, 0.62, 0)))
	m.mat(L.BOARDS, OAK * Color(1.1, 1.0, 0.92), 0.4)
	m.box(Vector3(0, 0.05, 0), Vector3(1.3, 0.06, 2.0), 2)
	for s: float in [-1.0, 1.0]:
		m.box(Vector3(s * 0.63, 0.25, 0), Vector3(0.04, 0.36, 2.0), 2)
	m.box(Vector3(0, 0.25, 0.98), Vector3(1.3, 0.36, 0.04), 0)
	m.box(Vector3(0, 0.25, -0.98), Vector3(1.3, 0.36, 0.04), 0)
	m.mat(L.TIMBER, OAK, 0.4)
	for s: float in [-1.0, 1.0]:
		m.beam(Vector3(s * 0.45, -0.02, 0.9), Vector3(s * 0.4, -0.02, -2.1), 0.08, 0.08)
		m.beam(Vector3(s * 0.45, -0.02, 0.8), Vector3(s * 0.45, -0.62, 0.95), 0.06, 0.06)
	# Load: a few sacks and a barrel.
	sack(m, Vector3(-0.3, 0.08, 0.4), 0.6, 0.2)
	sack(m, Vector3(0.25, 0.08, 0.35), 0.55, 1.4)
	barrel(m, Vector3(0.1, 0.08, -0.45), 0.8, 0.28, rng.randf() * TAU)
	m.pop()
	# Wheels.
	for s: float in [-1.0, 1.0]:
		m.push(Transform3D(Basis(Vector3.BACK, PI * 0.5 * s), Vector3(s * 0.76, 0.52, 0.0)))
		m.mat(L.TIMBER, OAK * Color(0.85, 0.8, 0.75), 0.4)
		m.lathe(Vector3(0, -0.05, 0), PackedVector2Array([Vector2(0.44, 0.0), Vector2(0.52, 0.0), Vector2(0.52, 0.09), Vector2(0.44, 0.09), Vector2(0.44, 0.0)]), 18, false, false)
		m.lathe(Vector3(0, -0.07, 0), PackedVector2Array([Vector2(0.09, 0.0), Vector2(0.09, 0.15)]), 8, true, true)
		for k in 8:
			var a := TAU * k / 8.0
			m.beam(Vector3(cos(a) * 0.08, 0.0, sin(a) * 0.08), Vector3(cos(a) * 0.45, 0.0, sin(a) * 0.45), 0.04, 0.04)
		m.mat(L.IRON, Color(0.6, 0.6, 0.6), 0.0)
		m.lathe(Vector3(0, -0.055, 0), PackedVector2Array([Vector2(0.525, 0.0), Vector2(0.525, 0.1)]), 18, false, false)
		m.pop()
	m.pop()


## A vegetable bed of cabbages / leeks inside a wattle fence.
static func garden(b: ArchBuild, c: Vector3, size: Vector2, yaw: float, rng: RandomNumberGenerator) -> void:
	var m := b.detail
	var basis := Basis(Vector3.UP, yaw)
	var corners: Array[Vector3] = []
	for k in 4:
		var s := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)][k] as Vector2
		corners.append(c + basis * Vector3(s.x * size.x * 0.5, 0, s.y * size.y * 0.5))
	for k in 4:
		if k == 2:
			continue  # the gate side stays open
		fence(b, corners[k], corners[(k + 1) % 4], Color(0.55, 0.45, 0.36), true)
	var rows := int(size.y / 0.6)
	for r in rows:
		for i in int(size.x / 0.5):
			var q := c + basis * Vector3(-size.x * 0.5 + 0.35 + i * 0.5, 0, -size.y * 0.5 + 0.4 + r * 0.6)
			q.y = b.ground(q)
			m.mat(L.COBBLE, Color(0.35, 0.27, 0.2), 0.0, 0.7)
			m.lathe(q, PackedVector2Array([Vector2(0.25, 0.0), Vector2(0.18, 0.06), Vector2(0.0, 0.08)]), 6, false, false)
			m.mat(L.FLAT, Color(0.28, 0.42, 0.18) * (0.85 + rng.randf() * 0.3), 0.0)
			m.lathe(q + Vector3(0, 0.05, 0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.14, 0.05), Vector2(0.16, 0.12), Vector2(0.1, 0.2), Vector2(0.0, 0.22)]), 7, false, false, rng.randf())
