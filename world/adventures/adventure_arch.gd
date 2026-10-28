class_name AdventureArch
extends RefCounted
## Modelled architecture of the revision 5 places (Architecture "builder" props,
## run on worker threads into an ArchBuild; node space = world - b.origin).
## Animated and glowing pieces (lava, runes, the gate leaf, the mirror) live
## in AdventureFx, not here.

const L := ArchMaterials.L
const OBSIDIAN := Color(0.07, 0.06, 0.07)
const BASALT := Color(0.24, 0.21, 0.2)
const MARBLE := Color(0.78, 0.84, 0.84)
const BRONZE := Color(0.55, 0.42, 0.24)


static func _n(b: ArchBuild, w: Vector3) -> Vector3:
	return w - b.origin


## Hemisphere seen from outside (`inside` false) or from within.
static func _dome(m: ArchMesh, c: Vector3, r: float, h: float, segs: int, inside: bool) -> void:
	var prof := PackedVector2Array()
	for i in 9:
		var a := PI * 0.5 * float(i) / 8.0
		prof.append(Vector2(r * cos(a), h * sin(a)))
	if inside:
		prof.reverse()
	m.lathe(c, prof, segs, false, false)


## Upward-facing ring between two radii.
static func _ring_floor(m: ArchMesh, c: Vector3, r0: float, r1: float, segs: int) -> void:
	m.lathe(c, PackedVector2Array([Vector2(r1, 0.0), Vector2(r0, 0.0)]), segs, false, false)


static func _column(m: ArchMesh, base: Vector3, h: float, r: float, broken: bool, seed_value: int) -> void:
	m.lathe(base, PackedVector2Array([Vector2(r * 1.45, 0.0), Vector2(r * 1.45, 0.35), Vector2(r * 1.15, 0.5), Vector2(r * 1.0, 0.7)]), 12, false, true)
	var top := h - (0.0 if broken else 0.8)
	m.cylinder(base + Vector3(0, 0.7, 0), base + Vector3(0, top, 0), r, r * 0.92, 12, false)
	if broken:
		m.rock(base + Vector3(0, top - 0.2, 0), Vector3(r * 2.0, 0.6, r * 2.0), seed_value, 3, 7)
	else:
		m.lathe(base + Vector3(0, top, 0), PackedVector2Array([Vector2(r * 0.95, 0.0), Vector2(r * 1.35, 0.35), Vector2(r * 1.55, 0.55), Vector2(r * 1.55, 0.8)]), 12, false, true)


# --- Mount Pyrrhos: the altar island, the causeway and the Fire Road gate -----------------------

static func pyrrhos(b: ArchBuild, prop: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(prop.get("seed", 1))
	var altar := _n(b, prop["altar"])
	var notch: Vector2 = prop["notch"]
	var n3 := Vector3(notch.x, 0, notch.y)
	var side := Vector3(-notch.y, 0, notch.x)
	var m := b.shell
	var d := b.detail
	if b.far_only:
		b.far.mat(L.FLAT, OBSIDIAN)
		b.far.cylinder(altar, altar + Vector3(0, 6, 0), 1.6, 0.4, 6)
		return
	# Stepped octagonal dais of obsidian, the cracked stone on top.
	m.mat(L.FLAT, OBSIDIAN, 0.2, 0.8)
	m.lathe(altar + Vector3(0, -1.2, 0), PackedVector2Array([Vector2(4.6, 0.0), Vector2(4.6, 0.5), Vector2(3.7, 0.5), Vector2(3.7, 1.0),
			Vector2(2.8, 1.0), Vector2(2.8, 1.25)]), 8, false, true, PI / 8.0)
	m.mat(L.RUBBLE, BASALT.darkened(0.2), 0.3, 0.6)
	m.rock(altar + Vector3(0, -0.15, 0), Vector3(1.9, 1.35, 1.6), rng.randi(), 4, 8)
	# Glowing cracks in the stone (embers), radiating from where the blade went in.
	d.mat(L.EMBER, Color(1.0, 0.8, 0.6))
	for i in 7:
		var a := TAU * i / 7.0 + rng.randf() * 0.4
		var from := altar + Vector3(0, 1.12, 0)
		var to := altar + Vector3(cos(a) * 0.95, 0.35 + rng.randf() * 0.5, sin(a) * 0.85)
		d.beam(from, to, 0.07, 0.05, Vector3.UP)
	for i in 10:
		var a := TAU * i / 10.0
		d.beam(altar + Vector3(cos(a) * 2.9, 0.06, sin(a) * 2.9), altar + Vector3(cos(a + 0.4) * 4.4, 0.06 - 0.5, sin(a + 0.4) * 4.4), 0.12, 0.04, Vector3.UP)
	# Four obsidian spires round the island, ember-veined.
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		var p := altar + Vector3(cos(a), 0, sin(a)) * 6.4
		p.y = b.ground(p) - 0.4
		m.mat(L.FLAT, OBSIDIAN, 0.1, 0.9)
		m.lathe(p, PackedVector2Array([Vector2(1.1, 0.0), Vector2(0.9, 2.0), Vector2(0.55, 5.5), Vector2(0.0, 8.0 + rng.randf() * 2.0)]), 6, false, true, rng.randf())
		d.mat(L.EMBER, Color(1.0, 0.7, 0.5))
		d.beam(p + Vector3(0.0, 0.5, 0.0), p + Vector3(0.0, 6.0, 0.0), 0.08, 0.08, Vector3.FORWARD)
	# The causeway: obsidian posts and ember braziers both sides.
	var lake: float = prop["lake"]
	var v: Vector2 = prop["v"]
	for k in 6:
		var along := 8.0 + k * (lake / 5.5)
		for s: float in [-1.0, 1.0]:
			var w := Vector3(v.x, 0, v.y) + n3 * along + side * 3.1 * s
			var p := _n(b, w)
			p.y = b.ground(p)
			m.mat(L.FLAT, OBSIDIAN, 0.1)
			m.cylinder(p, p + Vector3(0, 1.6, 0), 0.22, 0.16, 6)
			if k % 3 == 0:
				m.mat(L.IRON, Color(0.25, 0.22, 0.2), 0.5)
				m.lathe(p + Vector3(0, 1.6, 0), PackedVector2Array([Vector2(0.1, 0.0), Vector2(0.42, 0.25), Vector2(0.48, 0.45)]), 8, true, false)
				b.add_fire(p + Vector3(0, 1.95, 0), 0.6, 7.0, 1.6)
	# The Fire Road gate: two great pillars and a lintel of black glass over the canyon.
	var gate := _n(b, prop["gate"])
	gate.y = b.ground(gate)
	for s: float in [-1.0, 1.0]:
		var p := gate + side * 7.0 * s
		m.mat(L.FLAT, OBSIDIAN, 0.15, 0.8)
		m.lathe(p, PackedVector2Array([Vector2(1.6, 0.0), Vector2(1.4, 1.0), Vector2(1.1, 9.0), Vector2(1.5, 10.0), Vector2(1.5, 11.0)]), 8, false, true)
		d.mat(L.EMBER, Color(1.0, 0.75, 0.55))
		for k in 4:
			d.box(p + Vector3(0, 2.5 + k * 1.8, 0) - n3 * 1.15, Vector3(0.5, 0.9, 0.06), 1)
		b.add_fire(p + Vector3(0, 11.4, 0), 1.1, 12.0, 2.2)
	m.mat(L.FLAT, OBSIDIAN, 0.2)
	m.beam(gate + side * -8.4 + Vector3(0, 11.2, 0), gate + side * 8.4 + Vector3(0, 11.2, 0), 1.4, 1.3, Vector3.UP, 0.15)
	b.far.mat(L.FLAT, OBSIDIAN)
	b.far.beam(gate + side * -8.4 + Vector3(0, 11.2, 0), gate + side * 8.4 + Vector3(0, 11.2, 0), 1.4, 1.3)


# --- Kilnhollow: hearth-domes of the Pyrrhai -----------------------------------------------

static func kilnhollow(b: ArchBuild, prop: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(prop.get("seed", 1))
	for hut: Dictionary in prop["huts"]:
		var c := _n(b, hut["at"])
		var r: float = hut["r"]
		var h: float = hut["h"]
		var door: Vector2 = hut["door"]
		var kind := String(hut["kind"])
		if b.far_only:
			b.far.mat(L.FLAT, OBSIDIAN)
			b.far.lathe(c, PackedVector2Array([Vector2(r, 0.0), Vector2(r, h), Vector2(r * 0.6, h + r * 0.5), Vector2(0.0, h + r * 0.7)]), 8, false, true)
			continue
		if kind == "forge":
			_forge(b, c, r, rng)
			continue
		_hearth_dome(b, c, r, h, door, kind == "hall", rng)


static func _hearth_dome(b: ArchBuild, c: Vector3, r: float, h: float, door: Vector2, hall: bool, rng: RandomNumberGenerator) -> void:
	var m := b.shell
	var segs := 14 if hall else 10
	var door_a := atan2(door.y, door.x)
	var door_half := asin(clampf(1.25 / r, 0.0, 1.0)) * (1.6 if hall else 1.0)
	# Walls: basalt blocks in segments, a doorway towards the lake.
	m.mat(L.RUBBLE, BASALT, 0.4, 0.7)
	b.dirt(c.y, 1.2, 0.5)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var mid := (a0 + a1) * 0.5
		if absf(angle_difference(mid, door_a)) < door_half + PI / segs * 0.5:
			# The lintel over the door.
			var p0 := c + Vector3(cos(a0), 0, sin(a0)) * r
			var p1 := c + Vector3(cos(a1), 0, sin(a1)) * r
			m.beam(p0 + Vector3(0, h - 0.4, 0), p1 + Vector3(0, h - 0.4, 0), 0.8, 0.8, Vector3.UP)
			continue
		var p0 := c + Vector3(cos(a0), 0, sin(a0)) * (r - 0.4)
		var p1 := c + Vector3(cos(a1), 0, sin(a1)) * (r - 0.4)
		m.beam(p0 + Vector3(0, h * 0.5, 0), p1 + Vector3(0, h * 0.5, 0), h + 0.2, 0.8, Vector3.UP)
	b.dirt(0.0, 0.0)
	# The obsidian dome, its smoke vent, an ember band under the eaves.
	m.mat(L.FLAT, OBSIDIAN, 0.15, 0.85)
	_dome(m, c + Vector3(0, h, 0), r + 0.3, r * 0.75, segs, false)
	b.interior.mat(L.RUBBLE, BASALT.darkened(0.3), 0.2, 0.5)
	_dome(b.interior, c + Vector3(0, h, 0), r - 0.5, r * 0.65, segs, true)
	b.interior.mat(L.COBBLE, BASALT.darkened(0.1), 0.3)
	_ring_floor(b.interior, c + Vector3(0, 0.03, 0), 0.0, r - 0.3, segs)
	b.detail.mat(L.EMBER, Color(1.0, 0.6, 0.4))
	b.detail.lathe(c + Vector3(0, h + 0.05, 0), PackedVector2Array([Vector2(r + 0.42, 0.0), Vector2(r + 0.42, 0.14)]), segs, false, false)
	m.mat(L.FLAT, OBSIDIAN)
	m.cylinder(c + Vector3(0, h + r * 0.62, 0), c + Vector3(0, h + r * 0.62 + 0.9, 0), 0.45, 0.35, 8)
	b.add_smoke(c + Vector3(0, h + r * 0.62 + 1.0, 0), 0.6)
	# A hearth of glowing coals inside; the hall has a seat of honour and banners.
	b.interior.mat(L.EMBER, Color(1.0, 0.8, 0.6))
	b.interior.lathe(c + Vector3(0, 0.02, 0), PackedVector2Array([Vector2(0.9, 0.0), Vector2(0.75, 0.18), Vector2(0.0, 0.22)]), 8, false, true)
	if hall or rng.randf() < 0.35:
		b.add_fire(c + Vector3(0, 0.25, 0), 0.5 if not hall else 0.8, 5.0, 1.2)
	var dv := Vector3(door.x, 0, door.y)
	if hall:
		b.interior.mat(L.FLAT, OBSIDIAN)
		b.interior.box(c - dv * (r - 1.6) + Vector3(0, 0.6, 0), Vector3(1.4, 1.2, 1.0))
		b.interior.box(c - dv * (r - 1.2) + Vector3(0, 1.6, 0), Vector3(1.4, 2.2, 0.3))
		b.detail.mat(L.LINEN, Color(0.75, 0.22, 0.06), 0.4)
		for s: float in [-1.0, 1.0]:
			var side := Vector3(-door.y, 0, door.x)
			var p := c + dv * (r + 0.2) + side * 2.2 * s
			b.detail.box(p + Vector3(0, h - 1.2, 0), Vector3(0.9, 2.0, 0.05))
	# Door glow: ember stones either side of the doorway.
	b.detail.mat(L.EMBER, Color(1.0, 0.7, 0.5))
	var sidev := Vector3(-door.y, 0, door.x)
	for s: float in [-1.0, 1.0]:
		b.detail.box(c + dv * (r + 0.05) + sidev * 1.45 * s + Vector3(0, 1.2, 0), Vector3(0.18, 1.8, 0.18))
	# Obsidian shards and slag heaps round the hut.
	m.mat(L.FLAT, OBSIDIAN, 0.1)
	for i in 3:
		var a := rng.randf() * TAU
		var p := c + Vector3(cos(a), 0, sin(a)) * (r + rng.randf_range(1.0, 2.5))
		p.y = b.ground(p) - 0.2
		m.lathe(p, PackedVector2Array([Vector2(0.35, 0.0), Vector2(0.0, rng.randf_range(0.8, 1.8))]), 5, false, false, rng.randf())


static func _forge(b: ArchBuild, c: Vector3, r: float, rng: RandomNumberGenerator) -> void:
	var m := b.shell
	m.mat(L.FLAT, OBSIDIAN, 0.2, 0.7)
	for i in 6:
		var a := TAU * i / 6.0
		var p := c + Vector3(cos(a), 0, sin(a)) * r
		m.cylinder(p, p + Vector3(0, 3.6, 0), 0.32, 0.26, 6)
	m.lathe(c + Vector3(0, 3.6, 0), PackedVector2Array([Vector2(r + 0.8, 0.0), Vector2(r * 0.4, 1.6), Vector2(0.6, 2.0)]), 6, true, false)
	m.cylinder(c + Vector3(0, 5.5, 0), c + Vector3(0, 6.6, 0), 0.6, 0.45, 8)
	b.add_smoke(c + Vector3(0, 6.7, 0), 1.2)
	# The lava hearth and an anvil of black stone.
	m.mat(L.RUBBLE, BASALT, 0.3)
	m.lathe(c, PackedVector2Array([Vector2(1.3, 0.0), Vector2(1.3, 1.0), Vector2(1.0, 1.1)]), 10, false, true)
	b.detail.mat(L.EMBER, Color(1.0, 0.85, 0.7))
	b.detail.lathe(c + Vector3(0, 1.1, 0), PackedVector2Array([Vector2(1.0, 0.0), Vector2(0.0, 0.05)]), 10, false, true)
	b.add_fire(c + Vector3(0, 1.3, 0), 1.0, 9.0, 2.0)
	m.mat(L.FLAT, OBSIDIAN)
	var ap := c + Vector3(2.4, 0, 0.8)
	m.box(ap + Vector3(0, 0.4, 0), Vector3(0.5, 0.8, 0.5))
	m.box(ap + Vector3(0, 0.88, 0), Vector3(1.0, 0.2, 0.4))
	for i in 4:
		var p := c + Vector3(rng.randf_range(-3.0, 3.0), 0, rng.randf_range(-3.0, 3.0))
		if p.distance_to(c) < 1.8:
			continue
		m.rock(Vector3(p.x, b.ground(p) - 0.1, p.z), Vector3(0.5, 0.35, 0.5), rng.randi())


# --- Atlantis -------------------------------------------------------------------------------

static func atlantis(b: ArchBuild, prop: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(prop.get("seed", 1))
	var c := _n(b, prop["center"])
	var vest := _n(b, prop["vest"])
	var tre := _n(b, prop["treasury"])
	var gate := _n(b, prop["gate"])
	var g2: Vector2 = prop["g"]
	var g := Vector3(g2.x, 0, g2.y)
	var side := Vector3(-g2.y, 0, g2.x)
	if b.far_only:
		b.far.mat(L.ASHLAR, MARBLE)
		_dome(b.far, c, 30.6, 26.6, 12, false)
		_dome(b.far, vest, 10.6, 9.6, 8, false)
		return
	var m := b.shell
	# The great dome: marble, ribbed, crusted with the sea; its inner vault.
	m.mat(L.ASHLAR, MARBLE, 0.95, 0.6)
	_dome(m, c, 30.8, 26.8, 28, false)
	b.interior.mat(L.ASHLAR, MARBLE.lightened(0.05), 0.4, 0.8)
	_dome(b.interior, c, 29.4, 25.4, 28, true)
	m.mat(L.ASHLAR, MARBLE.darkened(0.15), 0.9)
	for i in 14:
		var a := TAU * i / 14.0
		var prev := Vector3.ZERO
		for k in 9:
			var t := PI * 0.5 * float(k) / 8.0
			var p := c + Vector3(cos(a) * cos(t) * 31.2, sin(t) * 27.2, sin(a) * cos(t) * 31.2)
			if k > 0:
				m.beam(prev, p, 0.9, 0.7, Vector3.UP)
			prev = p
	# Floor of the throne hall round the moon pool, its rim, and the throne itself.
	var pool: float = prop["pool"]
	b.interior.mat(L.FLOOR, Color(0.7, 0.76, 0.78), 0.3)
	_ring_floor(b.interior, c + Vector3(0, 0.02, 0), pool + 1.0, 29.5, 28)
	m.mat(L.ASHLAR, MARBLE, 0.6)
	m.lathe(c, PackedVector2Array([Vector2(pool + 1.5, 0.0), Vector2(pool + 1.5, 0.45), Vector2(pool + 0.1, 0.45), Vector2(pool + 0.1, -1.6)]), 28, false, false)
	var throne := c - g * 24.0
	m.mat(L.ASHLAR, MARBLE.darkened(0.05), 0.5)
	m.box(throne + Vector3(0, 1.2, 0), Vector3(6.0, 2.4, 3.0))
	m.box(throne - g * 1.3 + Vector3(0, 5.0, 0), Vector3(6.0, 7.6, 0.8))
	m.mat(L.IRON, BRONZE, 0.7)
	m.lathe(throne - g * 1.0 + Vector3(0, 9.0, 0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.4, 0.6), Vector2(0.9, 2.2), Vector2(0.0, 3.0)]), 10, false, false)
	# Colossal statues of the sea-kings flank the pool, tridents raised.
	for s: float in [-1.0, 1.0]:
		var p := c + side * 21.0 * s - g * 6.0
		m.mat(L.ASHLAR, MARBLE, 0.8)
		m.lathe(p, PackedVector2Array([Vector2(2.0, 0.0), Vector2(2.0, 1.2), Vector2(1.5, 1.4)]), 8, false, true)
		m.lathe(p + Vector3(0, 1.4, 0), PackedVector2Array([Vector2(1.3, 0.0), Vector2(1.6, 4.0), Vector2(1.1, 7.0), Vector2(1.5, 8.2), Vector2(0.7, 9.4), Vector2(0.8, 10.6), Vector2(0.0, 11.4)]), 10, false, true)
		m.mat(L.IRON, BRONZE, 0.8)
		var tp := p + side * -1.6 * s
		m.cylinder(tp + Vector3(0, 1.4, 0), tp + Vector3(0, 15.0, 0), 0.14, 0.14, 6)
		for k in 3:
			m.beam(tp + Vector3(0, 14.6, 0) + g * (k - 1) * 0.5, tp + Vector3(0, 16.6, 0) + g * (k - 1) * 0.7, 0.12, 0.12, g)
	# Vestibule and treasury domes, the corridors between them.
	for hall: Array in [[vest, 10.0, 9.0], [tre, 6.5, 6.0]]:
		var hc: Vector3 = hall[0]
		m.mat(L.ASHLAR, MARBLE, 0.95, 0.6)
		_dome(m, hc, float(hall[1]) + 0.8, float(hall[2]) + 0.8, 18, false)
		b.interior.mat(L.ASHLAR, MARBLE.lightened(0.05), 0.3)
		_dome(b.interior, hc, float(hall[1]) - 0.6, float(hall[2]) - 0.6, 18, true)
		b.interior.mat(L.FLOOR, Color(0.66, 0.72, 0.74), 0.3)
		_ring_floor(b.interior, hc + Vector3(0, 0.02, 0), 0.0, float(hall[1]) - 0.4, 18)
	_tube(b, c + g * 27.0, vest - g * 7.0, 2.4, 5.4)
	_tube(b, vest + side * 7.0, tre - side * 4.0, 2.0, 4.4)
	# The Tide Gate's frame: a great bronze ring set in a marble portal.
	var gp := vest + g * 9.8
	m.mat(L.ASHLAR, MARBLE.darkened(0.1), 0.9)
	m.box(gp + side * 2.6 + Vector3(0, 3.0, 0), Vector3(1.4, 6.0, 1.4) )
	m.box(gp - side * 2.6 + Vector3(0, 3.0, 0), Vector3(1.4, 6.0, 1.4))
	m.beam(gp + side * 3.4 + Vector3(0, 6.3, 0), gp - side * 3.4 + Vector3(0, 6.3, 0), 1.3, 1.1, Vector3.UP)
	m.mat(L.IRON, BRONZE, 0.7)
	m.push(Transform3D(Basis(side, g, Vector3.UP).orthonormalized(), gp + Vector3(0, 2.5, 0)))
	m.lathe(Vector3.ZERO, PackedVector2Array([Vector2(2.6, -0.25), Vector2(2.6, 0.25), Vector2(2.2, 0.25), Vector2(2.2, -0.25)]), 20, false, false)
	m.pop()
	# The processional avenue out from the gate, paved; the columns.
	m.mat(L.COBBLE, Color(0.62, 0.68, 0.68), 0.95)
	for k in 9:
		var p := gate + g * (4.0 + k * 8.0)
		p.y = b.ground(p) + 0.05
		m.beam(p - g * 4.0, p + g * 4.0, 10.0, 0.25, Vector3.UP)
	for col: Array in prop["columns"]:
		var p := _n(b, col[0])
		var h: float = col[1]
		m.mat(L.ASHLAR, MARBLE.darkened(rng.randf() * 0.15), 0.95, 0.6)
		_column(m, p, h, 0.55, h < 12.0, rng.randi())
	# Ruined halls: broken drum walls round a fallen roof.
	for ru: Dictionary in prop["ruins"]:
		var p := _n(b, ru["at"])
		var r: float = ru["r"]
		var broken: float = ru["broken"]
		m.mat(L.ASHLAR, MARBLE.darkened(0.1), 1.0, 0.5)
		var segs := 12
		for i in segs:
			if rng.randf() < broken * 0.6:
				continue
			var a0 := TAU * i / segs + float(ru["yaw"])
			var a1 := a0 + TAU / segs
			var hh := rng.randf_range(2.0, 7.0) * (1.0 - broken * 0.5)
			var p0 := p + Vector3(cos(a0), 0, sin(a0)) * r
			var p1 := p + Vector3(cos(a1), 0, sin(a1)) * r
			m.beam(p0 + Vector3(0, hh * 0.5 - 0.5, 0), p1 + Vector3(0, hh * 0.5 - 0.5, 0), hh, 0.9, Vector3.UP)
		for k in 4:
			m.rock(p + Vector3(rng.randf_range(-r, r) * 0.6, -0.3, rng.randf_range(-r, r) * 0.6), Vector3(rng.randf_range(1.0, 2.4), 0.8, rng.randf_range(1.0, 2.0)), rng.randi())
	# Rune lamps on the domes and the avenue (the glow itself comes from AdventureFx).
	b.add_light(c + Vector3(0, 18.0, 0), Color(0.35, 0.8, 1.0), 40.0, 1.6, false)
	b.add_light(vest + Vector3(0, 6.0, 0), Color(0.35, 0.8, 1.0), 16.0, 1.2, false)
	b.add_light(tre + Vector3(0, 4.0, 0), Color(0.95, 0.75, 0.35), 10.0, 1.2, false)
	b.add_light(gate + Vector3(0, 6.0, 0) + g * 2.0, Color(0.35, 0.8, 1.0), 22.0, 1.4, false)


## An air passage: a barrel vault over a paved floor.
static func _tube(b: ArchBuild, a: Vector3, z: Vector3, half_w: float, h: float) -> void:
	var dir := (z - a)
	var length := dir.length()
	var u := dir / length
	var basis := Basis(u.cross(Vector3.UP).normalized(), Vector3.UP, -u).orthonormalized()
	var m := b.shell
	m.mat(L.ASHLAR, MARBLE, 0.95, 0.6)
	m.push(Transform3D(basis, a))
	for k in 8:
		var t0 := PI * float(k) / 8.0
		var t1 := PI * float(k + 1) / 8.0
		var p0 := Vector3(cos(t0) * (half_w + 0.6), (h - 2.0) + sin(t0) * 2.6, 0)
		var p1 := Vector3(cos(t1) * (half_w + 0.6), (h - 2.0) + sin(t1) * 2.6, 0)
		m.quad(p1, p0, p0 + Vector3(0, 0, -length), p1 + Vector3(0, 0, -length), Vector2(0, 0), Vector2(1, 0), Vector2(1, length), Vector2(0, length))
		b.interior.mat(L.ASHLAR, MARBLE.lightened(0.05), 0.3)
		b.interior.push(Transform3D(basis, a))
		b.interior.quad(p0 * Vector3(0.88, 0.94, 1), p1 * Vector3(0.88, 0.94, 1), p1 * Vector3(0.88, 0.94, 1) + Vector3(0, 0, -length), p0 * Vector3(0.88, 0.94, 1) + Vector3(0, 0, -length),
				Vector2(0, 0), Vector2(1, 0), Vector2(1, length), Vector2(0, length))
		b.interior.pop()
	for s: float in [-1.0, 1.0]:
		m.box(Vector3(s * (half_w + 0.3), (h - 2.0) * 0.5, -length * 0.5), Vector3(0.6, h - 2.0, length))
	b.interior.mat(L.FLOOR, Color(0.66, 0.72, 0.74), 0.3)
	b.interior.push(Transform3D(basis, a))
	b.interior.box(Vector3(0, 0.0, -length * 0.5), Vector3(half_w * 2.0, 0.06, length))
	b.interior.pop()
	m.pop()


# --- Scumport -------------------------------------------------------------------------------

static func scumport(b: ArchBuild, prop: Dictionary) -> void:
	if b.far_only:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(prop.get("seed", 1))
	var m := b.shell
	var d := b.detail
	var timber := Color(0.3, 0.24, 0.18)
	# Piers: plank decks on pairs of crooked piles, lashed with rope.
	for pr: Array in prop["piers"]:
		var a := _n(b, pr[0])
		var z := _n(b, pr[1])
		var dir := (z - a).normalized()
		var sidev := Vector3(-dir.z, 0, dir.x)
		var length := a.distance_to(z)
		var deck_y := float(WorldGen.SEA_LEVEL + 3) - b.origin.y
		m.mat(L.BOARDS, Color(0.42, 0.36, 0.3), 0.9)
		var steps := int(length / 2.0)
		for s in steps:
			var p := a + dir * (s * 2.0 + 1.0)
			p.y = deck_y - 0.12
			m.beam(p - sidev * 1.6, p + sidev * 1.6, 1.9, 0.12, Vector3.UP)
		m.mat(L.TIMBER, timber, 0.9)
		for s in int(length / 4.0) + 1:
			for sg: float in [-1.0, 1.0]:
				var p := a + dir * (s * 4.0) + sidev * 1.55 * sg
				var bottom := b.ground(p) - 0.5
				m.cylinder(Vector3(p.x, bottom, p.z), Vector3(p.x + rng.randf_range(-0.1, 0.1), deck_y + 0.9, p.z), 0.16, 0.14, 6)
		d.mat(L.LINEN, Color(0.62, 0.55, 0.42), 0.6)
		for sg: float in [-1.0, 1.0]:
			d.beam(a + sidev * 1.55 * sg + Vector3(0, deck_y + 0.75 - a.y, 0), z + sidev * 1.55 * sg + Vector3(0, deck_y + 0.75 - z.y, 0), 0.04, 0.04)
		# A moored skiff at the end of each pier.
		var bp := z + sidev * 3.2
		bp.y = float(WorldGen.SEA_LEVEL) + 0.85 - b.origin.y
		VillageGreen._rowboat(b, bp, atan2(dir.x, dir.z))
	# Lanterns on poles: grimy glass, warm light (lit all the time; it's Scumport).
	for lw: Vector3 in prop["lamps"]:
		var p := _n(b, lw)
		p.y = maxf(b.ground(p), float(WorldGen.SEA_LEVEL + 3) - b.origin.y)
		m.mat(L.TIMBER, timber, 0.9)
		m.cylinder(p, p + Vector3(0, 3.2, 0), 0.09, 0.07, 6)
		m.beam(p + Vector3(0, 3.1, 0), p + Vector3(0.7, 3.1, 0), 0.08, 0.08)
		d.mat(L.IRON, Color(0.2, 0.18, 0.16), 0.6)
		d.box(p + Vector3(0.7, 2.75, 0), Vector3(0.32, 0.42, 0.32))
		d.mat(L.GLASS, Color(1, 1, 1), 1.0)
		d.box(p + Vector3(0.7, 2.75, 0), Vector3(0.26, 0.34, 0.34))
		b.add_light(p + Vector3(0.7, 2.6, 0), Color(1.0, 0.62, 0.28), 9.0, 1.1, false)
	# The market square: stalls under patched awnings, crates, barrels, nets, a crane on the quay.
	var sq := _n(b, prop["square"])
	for i in 4:
		var a := TAU * i / 4.0 + 0.6
		var p := sq + Vector3(cos(a), 0, sin(a)) * 5.2
		p.y = b.ground(p)
		m.mat(L.TIMBER, timber, 0.9)
		for cx: float in [-1.0, 1.0]:
			for cz: float in [-1.0, 1.0]:
				m.cylinder(p + Vector3(cx * 1.1, 0, cz * 0.7), p + Vector3(cx * 1.1, 2.3 - (0.3 if cz > 0 else 0.0), cz * 0.7), 0.06, 0.06, 5)
		m.mat(L.BOARDS, Color(0.45, 0.38, 0.3), 0.8)
		m.box(p + Vector3(0, 0.9, 0), Vector3(2.4, 0.1, 1.5))
		d.mat(L.LINEN, [Color(0.5, 0.18, 0.15), Color(0.25, 0.35, 0.32), Color(0.55, 0.45, 0.25), Color(0.32, 0.25, 0.38)][i], 0.8)
		d.push(Transform3D(Basis(Vector3.RIGHT, 0.18), p + Vector3(0, 2.15, 0)))
		d.box(Vector3.ZERO, Vector3(2.6, 0.04, 1.9))
		d.pop()
		VillageProps.crate(d, p + Vector3(1.6, 0, 0.6), 0.6, 0.55)
		VillageProps.barrel(d, p + Vector3(-1.7, 0, 0.5), 0.9, 0.32, 0.3)
	var west: Vector2 = prop["west"]
	var quay := sq + Vector3(west.x, 0, west.y) * 22.0
	quay.y = b.ground(quay)
	m.mat(L.TIMBER, timber, 0.9)
	m.beam(quay, quay + Vector3(0, 7.0, 0), 0.4, 0.4)
	m.beam(quay + Vector3(0, 6.6, 0), quay + Vector3(west.x * 5.0, 7.4, west.y * 5.0), 0.3, 0.3)
	d.mat(L.LINEN, Color(0.6, 0.55, 0.45), 0.6)
	d.beam(quay + Vector3(west.x * 4.8, 7.2, west.y * 4.8), quay + Vector3(west.x * 4.8, 3.0, west.y * 4.8), 0.03, 0.03)
	VillageProps.crate(d, quay + Vector3(west.x * 4.8, 2.4, west.y * 4.8), 0.9, 0.8)
	for i in 10:
		var p := sq + Vector3(rng.randf_range(-16.0, 16.0), 0, rng.randf_range(-14.0, 14.0))
		if p.distance_to(sq) < 8.0:
			continue
		p.y = b.ground(p)
		if rng.randf() < 0.5:
			VillageProps.barrel(d, p, 0.9, 0.32, 0.3)
		else:
			VillageProps.crate(d, p, rng.randf_range(0.5, 0.8), 0.6)


# --- Stormbreak Light -------------------------------------------------------------------------

static func stormbreak(b: ArchBuild, prop: Dictionary) -> void:
	var at := _n(b, prop["at"]) + Vector3(-7.0, 0, -3.0)
	at.y = b.ground(at) - 0.3
	var m := b.shell
	if b.far_only:
		b.far.mat(L.PLASTER, Color(0.85, 0.84, 0.8))
		b.far.cylinder(at, at + Vector3(0, 19, 0), 2.6, 1.8, 8)
		return
	# A tapered white tower banded in red, the lantern room of glass and iron on top.
	m.mat(L.PLASTER, Color(0.86, 0.85, 0.8), 0.8, 0.7)
	m.lathe(at, PackedVector2Array([Vector2(3.0, 0.0), Vector2(2.9, 1.0), Vector2(2.2, 17.0), Vector2(2.6, 17.4), Vector2(2.6, 17.8)]), 16, false, true)
	m.mat(L.PLASTER, Color(0.62, 0.14, 0.1), 0.8, 0.7)
	for k in 3:
		var y0 := 4.0 + k * 4.6
		var r0 := lerpf(2.95, 2.2, y0 / 17.0) + 0.04
		var r1 := lerpf(2.95, 2.2, (y0 + 1.6) / 17.0) + 0.04
		m.lathe(at + Vector3(0, y0, 0), PackedVector2Array([Vector2(r0, 0.0), Vector2(r1, 1.6)]), 16, false, false)
	m.mat(L.IRON, Color(0.18, 0.18, 0.18), 0.5)
	for i in 8:
		var a := TAU * i / 8.0
		m.cylinder(at + Vector3(cos(a) * 1.6, 17.8, sin(a) * 1.6), at + Vector3(cos(a) * 1.6, 20.0, sin(a) * 1.6), 0.07, 0.07, 4)
	m.lathe(at + Vector3(0, 20.0, 0), PackedVector2Array([Vector2(2.0, 0.0), Vector2(0.2, 1.4), Vector2(0.0, 1.9)]), 12, true, false)
	b.detail.mat(L.GLASS, Color(1, 1, 1), 1.0)
	b.detail.lathe(at + Vector3(0, 17.8, 0), PackedVector2Array([Vector2(1.55, 0.0), Vector2(1.55, 2.2)]), 12, false, false)
	b.add_light(at + Vector3(0, 19.0, 0), Color(1.0, 0.85, 0.55), 28.0, 2.4, false)
	# The keeper's cottage, roofless; driftwood and wreckage on the rocks.
	var cot := at + Vector3(6.0, 0, 6.0)
	cot.y = b.ground(cot)
	m.mat(L.RUBBLE, Color(0.55, 0.55, 0.52), 0.9)
	for s in 4:
		var a := s * PI * 0.5
		var u := Vector3(cos(a), 0, sin(a))
		m.box(cot + u * 2.6 + Vector3(0, 1.0, 0), (Vector3(0.6, 2.0, 5.6) if s % 2 == 0 else Vector3(5.6, 2.0 - (0.8 if s == 3 else 0.0), 0.6)))


# --- The Isle of Hollow Crowns ----------------------------------------------------------------

static func hollow_crowns(b: ArchBuild, prop: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(prop.get("seed", 1))
	var c := _n(b, prop["at"])
	var m := b.shell
	var stone := Color(0.62, 0.6, 0.66)
	if b.far_only:
		b.far.mat(L.ASHLAR, stone)
		b.far.cylinder(c, c + Vector3(0, 6, 0), 1.2, 1.0, 6)
		return
	# A round dais of pale stone, three steps, a star inlaid in silver.
	m.mat(L.ASHLAR, stone, 0.85)
	m.lathe(c + Vector3(0, -0.6, 0), PackedVector2Array([Vector2(13.0, 0.0), Vector2(13.0, 0.4), Vector2(9.0, 0.4), Vector2(9.0, 0.75),
			Vector2(5.0, 0.75), Vector2(5.0, 1.0), Vector2(0.0, 1.0)]), 32, false, true)
	b.detail.mat(L.IRON, Color(0.75, 0.78, 0.85), 0.2)
	for i in 8:
		var a := TAU * i / 8.0
		b.detail.beam(c + Vector3(0, 0.42, 0), c + Vector3(cos(a) * 4.6, 0.42, sin(a) * 4.6), 0.12 if i % 2 == 0 else 0.07, 0.02)
	# The pillars, each crowned with a broken stone circlet.
	for p_: Array in prop["pillars"]:
		var p := _n(b, p_[0])
		p.y = b.ground(p) - 0.3
		var h: float = p_[1]
		m.mat(L.ASHLAR, stone.darkened(rng.randf() * 0.15), 0.9)
		_column(m, p, h, 0.5, h < 6.0, rng.randi())
		if h >= 6.0:
			m.mat(L.IRON, Color(0.62, 0.55, 0.38), 0.8)
			for k in 7:
				var a := TAU * k / 7.0
				m.lathe(p + Vector3(cos(a) * 0.62, h + 0.05, sin(a) * 0.62), PackedVector2Array([Vector2(0.12, 0.0), Vector2(0.0, 0.42 + (k % 2) * 0.2)]), 4, false, false)
	# The Mirror of Stars' frame: a tall pointed arch of tarnished silver on a plinth.
	var mp := c + Vector3(0, 0.4, 0.2)
	m.mat(L.ASHLAR, stone.darkened(0.2), 0.6)
	m.box(mp + Vector3(0, 0.35, -0.3), Vector3(3.6, 0.7, 1.2))
	m.mat(L.IRON, Color(0.7, 0.72, 0.78), 0.4)
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for k in 13:
		var t := float(k) / 12.0
		var y := 0.7 + t * 4.6
		var x := 1.35 if t < 0.6 else 1.35 * cos((t - 0.6) / 0.4 * PI * 0.5)
		var pl := mp + Vector3(-x, y, -0.3)
		var pr := mp + Vector3(x, y, -0.3)
		if k > 0:
			m.beam(prev_l, pl, 0.22, 0.22, Vector3.BACK)
			m.beam(prev_r, pr, 0.22, 0.22, Vector3.BACK)
		prev_l = pl
		prev_r = pr
	b.add_light(mp + Vector3(0, 3.0, 1.0), Color(0.6, 0.65, 1.0), 10.0, 1.0, false)
