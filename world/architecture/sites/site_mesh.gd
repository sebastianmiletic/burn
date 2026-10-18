class_name SiteMesh
extends RefCounted
## Modelled non-village structures from "site" props (SitePlan,
## ExplorationSites): shrines, watchtowers, ruins, the crater obelisk,
## Asphodel's gate, abandoned mines, shipwrecks, the Ryft ruins and the
## ancient gateways. Worker thread, into an ArchBuild.

const L = ArchMaterials.L
const RUNE := Color(1.0, 0.55, 0.25)
const RYFT_RUNE := Color(0.55, 0.45, 1.0)


static func build(b: ArchBuild, prop: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(prop.get("seed", 1))
	var at: Vector3 = (prop.get("at", b.origin) as Vector3) - b.origin
	var site := String(prop.get("site", ""))
	if b.far_only:
		_far(b, site, at, prop)
		return
	match site:
		"shrine":
			_shrine(b, at, prop, rng)
		"tower":
			_tower(b, at, prop, rng)
		"ruin":
			_ruin(b, at, prop, rng)
		"crater":
			_crater(b, at, prop, rng)
		"asphodel":
			_asphodel(b, at, prop, rng)
		"mine":
			_mine(b, prop, rng)
		"wreck":
			_wreck(b, at, prop, rng)
		"gateway":
			_gateway(b, at, prop, rng)
		"ryft":
			_ryft(b, at, prop, rng)
	if prop.get("sunken", false):
		_sunken(b, at, prop, rng)
	_far(b, site, at, prop)


const CORALS := [Color(0.95, 0.55, 0.5), Color(0.98, 0.78, 0.45), Color(0.62, 0.45, 0.85), Color(0.45, 0.78, 0.66), Color(0.86, 0.82, 0.72)]


## Sea-bed sites (revision 4): coral heads and weed crusting the stones and timbers,
## shells and broken amphorae scattered round them.
static func _sunken(b: ArchBuild, at: Vector3, prop: Dictionary, rng: RandomNumberGenerator) -> void:
	var m := b.detail
	var spots: Array = []
	for pc: Dictionary in prop.get("pieces", []):
		var pos: Vector3 = (pc.get("pos", at) as Vector3) - b.origin
		spots.append([pos, float(pc.get("h", 1.0))])
	for i in 18:
		var a := rng.randf() * TAU
		var r := rng.randf_range(1.5, 10.0)
		spots.append([at + Vector3(cos(a) * r, 0, sin(a) * r), 0.0])
	for s: Array in spots:
		var p: Vector3 = s[0]
		var h: float = s[1]
		var n := 2 if h > 0.0 else 1
		for k in n:
			var q := p + Vector3(rng.randf_range(-0.7, 0.7), 0, rng.randf_range(-0.7, 0.7))
			q.y = b.ground(q) + (rng.randf_range(0.2, maxf(h, 0.3)) if h > 0.0 else 0.05)
			m.mat(L.RUBBLE, CORALS[rng.randi() % CORALS.size()], 0.3, 0.6)
			m.rock(q, Vector3(0.32, 0.22, 0.32) * rng.randf_range(0.6, 1.5), rng.randi(), 3, 6)
	# Amphorae half buried in the sand.
	for i in 5:
		var a := rng.randf() * TAU
		var p := at + Vector3(cos(a), 0, sin(a)) * rng.randf_range(2.0, 7.0)
		p.y = b.ground(p) - 0.15
		m.mat(L.RUBBLE, Color(0.62, 0.4, 0.28), 0.4)
		var tilt := Basis(Vector3(cos(a), 0, sin(a)), rng.randf_range(0.9, 1.4))
		b.push(Transform3D(tilt, p))
		m.lathe(Vector3.ZERO, PackedVector2Array([Vector2(0.0, -0.35), Vector2(0.14, -0.3), Vector2(0.22, 0.0), Vector2(0.12, 0.3), Vector2(0.07, 0.42), Vector2(0.09, 0.48)]), 10, true, false)
		b.pop()


static func _far(b: ArchBuild, site: String, at: Vector3, prop: Dictionary) -> void:
	var m := b.far
	match site:
		"tower":
			m.mat(L.ASHLAR, Color(0.85, 0.83, 0.8), 0.3)
			m.lathe(at, PackedVector2Array([Vector2(4.0, -1.0), Vector2(3.9, 16.2), Vector2(0.0, 16.2)]), 10, false, false)
		"asphodel":
			m.mat(L.ASHLAR, Color(0.12, 0.1, 0.13), 0.0)
			for s: float in [-1.0, 1.0]:
				m.box(at + Vector3(s * 5.0, 6.5, -7.0), Vector3(1.4, 13.0, 1.4), 1)
			m.box(at + Vector3(0, 13.4, -7.0), Vector3(12.0, 1.2, 1.6), 0)


static func _ground_at(b: ArchBuild, p: Vector3) -> Vector3:
	return Vector3(p.x, b.ground(p), p.z)


## A rough monolith: tapered, leaning, rune grooves facing `face`.
static func _monolith(b: ArchBuild, base: Vector3, h: float, yaw: float, lean: float, seed_value: int, runes: Color, tint := Color(0.78, 0.77, 0.74)) -> void:
	var m := b.shell
	m.push(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, lean), base + Vector3(0, -0.4, 0)))
	m.mat(L.RUBBLE, tint, 0.8)
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var rings := 7
	var prof: Array[Vector2] = []
	for j in rings + 1:
		var f := float(j) / rings
		prof.append(Vector2((0.62 - 0.26 * f * f) * r.randf_range(0.86, 1.12), (h + 0.4) * f))
	var segs := 7
	var phase := r.randf() * TAU
	var pts: Array[PackedVector3Array] = []
	for j in rings + 1:
		var row := PackedVector3Array()
		for i in segs:
			var a := phase + TAU * i / segs
			var k := r.randf_range(0.74, 1.22)
			row.append(Vector3(cos(a) * prof[j].x * k * 1.25 + r.randf_range(-0.04, 0.04), prof[j].y + r.randf_range(-0.06, 0.06), sin(a) * prof[j].x * k * 0.8))
		pts.append(row)
	for j in rings:
		for i in segs:
			var a := pts[j][i]
			var c := pts[j][(i + 1) % segs]
			var d := pts[j + 1][(i + 1) % segs]
			var e := pts[j + 1][i]
			var mid := (a + c + d + e) * 0.25
			var n := (c - a).cross(e - a).normalized()
			if n.dot(Vector3(mid.x, 0, mid.z)) < 0.0:
				n = -n
			m.quad(a, c, d, e, Vector2(i * 0.5, -a.y), Vector2(i * 0.5 + 0.5, -c.y), Vector2(i * 0.5 + 0.5, -d.y), Vector2(i * 0.5, -e.y), n)
	var top := pts[rings]
	var tc := Vector3(r.randf_range(-0.15, 0.15), top[0].y + r.randf_range(0.05, 0.3), 0)
	for i in segs:
		m.tri(top[i], top[(i + 1) % segs], tc, Vector2(top[i].x, top[i].z), Vector2(top[(i + 1) % segs].x, top[(i + 1) % segs].z), Vector2.ZERO)
	if runes.a > 0.0:
		m.mat(L.EMBER, runes, 0.0)
		var face := -0.62 * 0.8 - 0.01
		for k in 4:
			var y := 0.9 + k * (h - 1.2) / 4.0
			m.box(Vector3(0, y, face * 0.92), Vector3(0.05, 0.32, 0.02), 1)
			m.box(Vector3(0.08 if k % 2 == 0 else -0.08, y + 0.1, face * 0.92), Vector3(0.14, 0.04, 0.02), 0)
	m.pop()


# --- Shrine ------------------------------------------------------------------------

static func _shrine(b: ArchBuild, at: Vector3, prop: Dictionary, rng: RandomNumberGenerator) -> void:
	var m := b.shell
	var g := at
	g.y = b.ground(at)
	# Paved round with a kerb.
	m.mat(L.ASHLAR, Color(0.82, 0.8, 0.76), 0.6)
	m.lathe(g, PackedVector2Array([Vector2(3.4, -0.4), Vector2(3.4, 0.07), Vector2(3.32, 0.1), Vector2(0.0, 0.1)]), 20, false, false)
	m.mat(L.COBBLE, Color(0.85, 0.83, 0.8), 0.7)
	m.lathe(g + Vector3(0, 0.005, 0), PackedVector2Array([Vector2(3.05, 0.1), Vector2(1.0, 0.1)]), 20, false, false)
	m.mat(L.RUBBLE, Color(0.8, 0.78, 0.74), 0.5)
	for i in 14:
		var a := TAU * i / 14.0 + rng.randf_range(-0.1, 0.1)
		var p := g + Vector3(cos(a), 0, sin(a)) * rng.randf_range(3.55, 3.8)
		p.y = b.ground(p) - 0.05
		m.rock(p, Vector3(rng.randf_range(0.25, 0.4), rng.randf_range(0.15, 0.28), rng.randf_range(0.25, 0.4)), rng.randi())
	for s: Dictionary in prop.get("stones", []):
		var p2: Vector2 = s["pos"]
		var base := Vector3(p2.x - b.origin.x, 0, p2.y - b.origin.z)
		base.y = b.ground(base)
		var to_c := g - base
		var yaw := atan2(to_c.x, to_c.z)
		_monolith(b, base, float(s["h"]), yaw, float(s["lean"]), rng.randi(), RUNE * Color(1, 1, 1, 1.0), Color(0.62, 0.62, 0.6))
		# Offerings at the foot of some stones.
		if rng.randf() < 0.5:
			var q := base + to_c.normalized() * 0.75
			q.y = b.ground(q)
			for k in 3:
				VillageProps.candle(b.detail, q + Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2)))


# --- Watchtower ---------------------------------------------------------------------

const T_IN := 2.55
const T_OUT := 3.9


static func _tower(b: ArchBuild, at: Vector3, prop: Dictionary, rng: RandomNumberGenerator) -> void:
	var m := b.shell
	var top := float(SitePlan.TOWER_TOP)
	var broken: float = prop.get("broken", 0.0)
	var ruin: float = prop.get("ruin", 0.6)
	var segs := 24
	var tint := Color(0.88, 0.86, 0.82)
	b.dirt(at.y - 0.5, 3.0, 0.5)
	# Crown height per slice: the broken side has fallen away.
	var crown := PackedFloat32Array()
	for i in segs:
		var a := TAU * (float(i) + 0.5) / segs
		var dist := absf(angle_difference(a, broken))
		var loss := clampf(1.0 - dist / 1.0, 0.0, 1.0) * ruin
		crown.append(top + 1.0 - loss * rng.randf_range(2.5, 4.5))
	var door_h := 2.3
	for i in segs:
		var a0 := TAU * float(i) / segs - TAU / segs * 0.5
		var a1 := a0 + TAU / segs
		var h1 := crown[i]
		var door := i == 0 or i == 1 or i == segs - 1
		var y0 := door_h if door else -1.0
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		# Outer face with a battered foot.
		m.mat(L.ASHLAR, tint, 0.55)
		var bands := [y0, 2.4, 7.4, 7.7, h1] if y0 < 2.4 else [y0, 7.4, 7.7, h1]
		for k in bands.size() - 1:
			var ya: float = bands[k]
			var yb: float = bands[k + 1]
			if yb <= ya:
				continue
			var ra := _tower_r(ya)
			var rb := _tower_r(yb)
			if ya >= 7.4 and yb <= 7.7:
				m.mat(L.ASHLAR, tint * Color(1.05, 1.03, 1.0), 0.4)
				ra = T_OUT + 0.12
				rb = T_OUT + 0.12
			else:
				m.mat(L.ASHLAR, tint, 0.55)
			var u0 := a0 * T_OUT
			var u1 := a1 * T_OUT
			m.quad(at + d0 * ra + Vector3(0, ya, 0), at + d1 * ra + Vector3(0, ya, 0), at + d1 * rb + Vector3(0, yb, 0), at + d0 * rb + Vector3(0, yb, 0),
					Vector2(u0, -ya), Vector2(u1, -ya), Vector2(u1, -yb), Vector2(u0, -yb), ((d0 + d1) * 0.5).normalized())
		# String course undersides.
		m.mat(L.ASHLAR, tint * Color(1.05, 1.03, 1.0), 0.4)
		m.quad(at + d0 * T_OUT + Vector3(0, 7.4, 0), at + d1 * T_OUT + Vector3(0, 7.4, 0), at + d1 * (T_OUT + 0.12) + Vector3(0, 7.4, 0), at + d0 * (T_OUT + 0.12) + Vector3(0, 7.4, 0),
				Vector2.ZERO, Vector2(1, 0), Vector2(1, 0.1), Vector2(0, 0.1), Vector3.DOWN)
		m.quad(at + d0 * (T_OUT + 0.12) + Vector3(0, 7.7, 0), at + d1 * (T_OUT + 0.12) + Vector3(0, 7.7, 0), at + d1 * T_OUT + Vector3(0, 7.7, 0), at + d0 * T_OUT + Vector3(0, 7.7, 0),
				Vector2.ZERO, Vector2(1, 0), Vector2(1, 0.1), Vector2(0, 0.1), Vector3.UP)
		# Inner face.
		m.mat(L.ASHLAR, tint * Color(0.7, 0.68, 0.66), 0.2)
		m.quad(at + d1 * T_IN + Vector3(0, maxf(y0, 0.0), 0), at + d0 * T_IN + Vector3(0, maxf(y0, 0.0), 0), at + d0 * T_IN + Vector3(0, h1, 0), at + d1 * T_IN + Vector3(0, h1, 0),
				Vector2(a1 * T_IN, -y0), Vector2(a0 * T_IN, -y0), Vector2(a0 * T_IN, -h1), Vector2(a1 * T_IN, -h1), -((d0 + d1) * 0.5).normalized())
		# Rough top of the wall.
		m.mat(L.RUBBLE, tint, 0.9)
		var ro := _tower_r(h1)
		m.quad(at + d0 * T_IN + Vector3(0, h1, 0), at + d1 * T_IN + Vector3(0, h1, 0), at + d1 * ro + Vector3(0, h1, 0), at + d0 * ro + Vector3(0, h1, 0),
				Vector2(a0, 0), Vector2(a1, 0), Vector2(a1, 1.2), Vector2(a0, 1.2), Vector3.UP)
		# Merlons on the intact parapet, every other slice.
		if h1 > top + 0.9 and i % 2 == 0:
			m.mat(L.ASHLAR, tint, 0.6)
			var mid := (d0 + d1).normalized()
			m.push(Transform3D(Basis(Vector3.UP, -atan2(mid.z, mid.x) + PI * 0.5), at + mid * ((T_IN + ro) * 0.5) + Vector3(0, h1 + 0.45, 0)))
			m.box(Vector3.ZERO, Vector3(0.9, 0.9, ro - T_IN), 1)
			m.pop()
		# Side faces where the crown height changes.
		var hn := crown[(i + 1) % segs]
		if absf(hn - h1) > 0.05:
			var lo := minf(h1, hn)
			var hi := maxf(h1, hn)
			var n := Vector3(-d1.z, 0, d1.x) * (1.0 if hn < h1 else -1.0)
			m.mat(L.RUBBLE, tint, 0.8)
			m.quad(at + d1 * T_IN + Vector3(0, lo, 0), at + d1 * _tower_r(lo) + Vector3(0, lo, 0), at + d1 * _tower_r(hi) + Vector3(0, hi, 0), at + d1 * T_IN + Vector3(0, hi, 0),
					Vector2(0, -lo), Vector2(1.3, -lo), Vector2(1.3, -hi), Vector2(0, -hi), n)
	# The doorway: a straight passage 1.1 m wide through the wall.
	var hw := 0.55
	var edge := TAU / segs * 1.5
	for sd: float in [-1.0, 1.0]:
		var xo := sqrt(_tower_r(0.0) * _tower_r(0.0) - hw * hw)
		var xi := sqrt(T_IN * T_IN - hw * hw)
		var p_out := at + Vector3(xo, 0, sd * hw)
		var p_in := at + Vector3(xi, 0, sd * hw)
		var e_out := at + Vector3(cos(edge) * _tower_r(0.0), 0, sd * sin(edge) * _tower_r(0.0))
		var e_in := at + Vector3(cos(edge) * T_IN, 0, sd * sin(edge) * T_IN)
		var up := Vector3(0, door_h, 0)
		var dn := Vector3(0, -1.0, 0)
		m.mat(L.ASHLAR, tint, 0.55)
		m.quad(p_out + dn, e_out + dn, e_out + up, p_out + up, Vector2(0, 1), Vector2(1.5, 1), Vector2(1.5, -door_h), Vector2(0, -door_h), Vector3(cos(edge * 0.6), 0, sd * sin(edge * 0.6)))
		m.mat(L.ASHLAR, tint * Color(0.7, 0.68, 0.66), 0.2)
		m.quad(e_in, p_in, p_in + up, e_in + up, Vector2(0, 0), Vector2(1.5, 0), Vector2(1.5, -door_h), Vector2(0, -door_h), -Vector3(cos(edge * 0.6), 0, sd * sin(edge * 0.6)))
		m.mat(L.ASHLAR, tint * Color(0.9, 0.88, 0.85), 0.3)
		m.quad(p_in, p_out + Vector3(0, 0, 0), p_out + up, p_in + up, Vector2(xi, 0), Vector2(xo, 0), Vector2(xo, -door_h), Vector2(xi, -door_h), Vector3(0, 0, -sd))
	m.quad(at + Vector3(sqrt(T_IN * T_IN - hw * hw), door_h, -hw), at + Vector3(sqrt(T_IN * T_IN - hw * hw), door_h, hw),
			at + Vector3(sqrt(_tower_r(door_h) * _tower_r(door_h) - hw * hw), door_h, hw), at + Vector3(sqrt(_tower_r(door_h) * _tower_r(door_h) - hw * hw), door_h, -hw),
			Vector2(0, 0), Vector2(1.1, 0), Vector2(1.1, 1.4), Vector2(0, 1.4), Vector3.DOWN)
	# Door frame and the open leaf.
	m.mat(L.TIMBER, Color(0.45, 0.36, 0.28), 0.3)
	var dp := at + Vector3(T_OUT - 0.25, 0, 0)
	m.beam(dp + Vector3(0, 0, -0.65), dp + Vector3(0, door_h, -0.65), 0.2, 0.24, Vector3.RIGHT, 0.02)
	m.beam(dp + Vector3(0, 0, 0.65), dp + Vector3(0, door_h, 0.65), 0.2, 0.24, Vector3.RIGHT, 0.02)
	m.beam(dp + Vector3(0, door_h + 0.1, -0.85), dp + Vector3(0, door_h + 0.1, 0.85), 0.24, 0.26, Vector3.RIGHT, 0.02)
	m.push(Transform3D(Basis(Vector3.UP, -1.9), at + Vector3(T_IN + 0.1, 0.02, -0.46)))
	ArchKit._leaf(m, 0.88, door_h - 0.1, 1.0, Color(0.48, 0.38, 0.3))
	m.pop()
	# Ground floor flags.
	b.interior.mat(L.COBBLE, Color(0.75, 0.73, 0.7), 0.2)
	b.interior.lathe(at + Vector3(0, 0.02, 0), PackedVector2Array([Vector2(T_IN, 0.0), Vector2(0.0, 0.0)]), 16, false, false)
	# Spiral stair: two treads per one-metre step, cantilevered from the wall.
	var ring: Array = SitePlan.TOWER_RING
	var angles: Array[float] = []
	for k in SitePlan.TOWER_STEPS + 1:
		var rc: Vector2i = ring[(SitePlan.TOWER_FIRST + k) % ring.size()]
		var a := atan2(float(rc.y), float(rc.x))
		if not angles.is_empty():
			while a < angles[angles.size() - 1]:
				a += TAU
		angles.append(a)
	m.mat(L.ASHLAR, tint * Color(0.95, 0.93, 0.9), 0.3)
	for k in SitePlan.TOWER_STEPS:
		var a_mid: float = angles[k]
		var a_prev: float = (angles[k - 1] + a_mid) * 0.5 if k > 0 else a_mid - 0.35
		var a_next: float = (a_mid + angles[k + 1]) * 0.5
		var top_y := 1.0 + k
		_tread(m, at, a_prev, a_mid, 1.15, T_IN + 0.05, top_y - 0.5)
		_tread(m, at, a_mid, a_next, 1.15, T_IN + 0.05, top_y)
	# Landing and top platform, open over the steps that pass through.
	var land_hole: Array = [angles[7] - 0.5, angles[8] + 0.5]
	var top_hole: Array = [angles[12] - 0.5, angles[13] + 0.5]
	_floor_disc(b.interior, at, float(SitePlan.TOWER_LANDING), land_hole, L.FLOOR, Color(0.7, 0.6, 0.5), true)
	_floor_disc(b.shell, at, top, top_hole, L.ASHLAR, tint * Color(0.9, 0.88, 0.85), false)
	# A brazier and a tattered banner on the top.
	var bz := at + Vector3(-1.2, top, -1.0)
	m.mat(L.IRON, Color(0.5, 0.5, 0.5), 0.0)
	m.lathe(bz, PackedVector2Array([Vector2(0.25, 0.0), Vector2(0.05, 0.05), Vector2(0.05, 0.7), Vector2(0.35, 0.85), Vector2(0.4, 1.0), Vector2(0.3, 0.95)]), 10, true, false)
	m.mat(L.EMBER, Color(1, 1, 1), 0.0)
	m.lathe(bz + Vector3(0, 0.9, 0), PackedVector2Array([Vector2(0.3, 0.0), Vector2(0.0, 0.12)]), 9, false, false)
	b.add_fire(bz + Vector3(0, 0.95, 0), 0.9, 10.0, 2.0)
	var pole := at + Vector3(1.6, top, 1.2)
	m.mat(L.TIMBER, Color(0.5, 0.42, 0.34), 0.4)
	m.cylinder(pole, pole + Vector3(0, 4.5, 0), 0.06, 0.045, 6)
	b.detail.mat(L.LINEN, Color(0.55, 0.16, 0.12), 0.4)
	for k in 6:
		var x0 := k * 0.3
		var x1 := x0 + 0.3
		var y0 := 4.2 - absf(sin(k * 1.7)) * 0.08
		var droop0 := sin(x0 * 2.0) * 0.1
		var droop1 := sin(x1 * 2.0) * 0.1
		var len0 := 1.1 - k * 0.12 + (0.2 if k % 2 == 0 else 0.0)
		b.detail.quad(pole + Vector3(0.05 + x0, y0, droop0), pole + Vector3(0.05 + x1, y0, droop1), pole + Vector3(0.05 + x1, y0 - len0, droop1), pole + Vector3(0.05 + x0, y0 - len0, droop0),
				Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, len0), Vector2(x0, len0), Vector3.BACK)
		b.detail.quad(pole + Vector3(0.05 + x1, y0, droop1 - 0.005), pole + Vector3(0.05 + x0, y0, droop0 - 0.005), pole + Vector3(0.05 + x0, y0 - len0, droop0 - 0.005), pole + Vector3(0.05 + x1, y0 - len0, droop1 - 0.005),
				Vector2(x1, 0), Vector2(x0, 0), Vector2(x0, len0), Vector2(x1, len0), Vector3.FORWARD)
	# Arrow slits.
	for k in 6:
		var a := TAU * (k + 0.5) / 6.0 + 0.3
		var y := 3.5 + (k % 3) * 4.0
		if absf(angle_difference(a, 0.0)) < 0.4:
			continue
		var d := Vector3(cos(a), 0, sin(a))
		var r := _tower_r(y)
		b.detail.push(Transform3D(Basis(Vector3.UP, -atan2(d.z, d.x) + PI * 0.5), at + d * (r - 0.03) + Vector3(0, y, 0)))
		b.detail.mat(L.FLAT, Color(0.02, 0.02, 0.02), 0.0)
		b.detail.box(Vector3(0, 0, 0), Vector3(0.1, 1.0, 0.1), 1)
		b.detail.mat(L.ASHLAR, tint * Color(1.05, 1.03, 1.0), 0.4)
		for s: float in [-1.0, 1.0]:
			b.detail.box(Vector3(s * 0.16, 0, 0.02), Vector3(0.22, 1.2, 0.08), 1)
		b.detail.box(Vector3(0, 0.66, 0.02), Vector3(0.6, 0.14, 0.08), 0)
		b.detail.pop()
	# Rubble fallen from the broken crown.
	m.mat(L.ASHLAR, tint, 0.7)
	for k in 9:
		var a := broken + rng.randf_range(-0.8, 0.8)
		var p := at + Vector3(cos(a), 0, sin(a)) * rng.randf_range(4.3, 6.5)
		p.y = b.ground(p) - 0.08
		m.rock(p, Vector3(rng.randf_range(0.3, 0.6), rng.randf_range(0.25, 0.45), rng.randf_range(0.3, 0.55)), rng.randi())
	b.add_light(at + Vector3(0, 9.0, 0), Color(1.0, 0.7, 0.4), 6.0, 0.5, false)


static func _tower_r(y: float) -> float:
	return T_OUT + 0.18 * clampf(1.0 - y / 2.4, 0.0, 1.0)


## An annular-sector tread (top at y, 0.28 thick) between angles a0..a1.
static func _tread(m: ArchMesh, c: Vector3, a0: float, a1: float, r0: float, r1: float, y: float) -> void:
	var p := func(a: float, r: float, h: float) -> Vector3: return c + Vector3(cos(a) * r, h, sin(a) * r)
	var yb := y - 0.28
	var n_top := Vector3.UP
	m.quad(p.call(a0, r0, y), p.call(a0, r1, y), p.call(a1, r1, y), p.call(a1, r0, y), Vector2(a0 * r1, r0), Vector2(a0 * r1, r1), Vector2(a1 * r1, r1), Vector2(a1 * r1, r0), n_top)
	m.quad(p.call(a1, r0, yb), p.call(a1, r1, yb), p.call(a0, r1, yb), p.call(a0, r0, yb), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector3.DOWN)
	var n0 := Vector3(sin(a0), 0, -cos(a0))
	m.quad(p.call(a0, r0, yb), p.call(a0, r1, yb), p.call(a0, r1, y), p.call(a0, r0, y), Vector2(r0, -yb), Vector2(r1, -yb), Vector2(r1, -y), Vector2(r0, -y), n0)
	var n1 := Vector3(-sin(a1), 0, cos(a1))
	m.quad(p.call(a1, r1, yb), p.call(a1, r0, yb), p.call(a1, r0, y), p.call(a1, r1, y), Vector2(r1, -yb), Vector2(r0, -yb), Vector2(r0, -y), Vector2(r1, -y), n1)
	var am := (a0 + a1) * 0.5
	m.quad(p.call(a1, r0, yb), p.call(a0, r0, yb), p.call(a0, r0, y), p.call(a1, r0, y), Vector2(a1, -yb), Vector2(a0, -yb), Vector2(a0, -y), Vector2(a1, -y), -Vector3(cos(am), 0, sin(am)))


## A floor disc inside the tower at height y, with a sector left open.
static func _floor_disc(m: ArchMesh, c: Vector3, y: float, hole: Array, layer: int, tint: Color, joists: bool) -> void:
	m.mat(layer, tint, 0.2)
	var segs := 20
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var am := (a0 + a1) * 0.5
		var open := false
		for k in 2:
			var h0: float = hole[0] + TAU * (k - 1)
			var h1: float = hole[1] + TAU * (k - 1)
			for kk in 3:
				var off := TAU * (kk - 1)
				if am + off > h0 and am + off < h1:
					open = true
		if open:
			continue
		var p0 := c + Vector3(cos(a0) * T_IN, y, sin(a0) * T_IN)
		var p1 := c + Vector3(cos(a1) * T_IN, y, sin(a1) * T_IN)
		m.tri(c + Vector3(0, y, 0), p0, p1, Vector2(c.x, c.z), Vector2(p0.x, p0.z), Vector2(p1.x, p1.z), Vector3.UP)
		m.tri(c + Vector3(0, y - 0.12, 0), p1 - Vector3(0, 0.12, 0), p0 - Vector3(0, 0.12, 0), Vector2(c.x, c.z), Vector2(p1.x, p1.z), Vector2(p0.x, p0.z), Vector3.DOWN)
		# Rim of the opening.
		var prev_open := false
		var am2 := am - TAU / segs
		for kk in 3:
			var off := TAU * (kk - 1)
			if am2 + off > hole[0] and am2 + off < hole[1]:
				prev_open = true
		if prev_open:
			var n := Vector3(-sin(a0), 0, cos(a0))
			m.quad(c + Vector3(0, y - 0.12, 0), p0 - Vector3(0, 0.12, 0), p0, c + Vector3(0, y, 0), Vector2(0, 0.12), Vector2(T_IN, 0.12), Vector2(T_IN, 0), Vector2(0, 0), -n)
	if joists:
		m.mat(L.TIMBER, Color(0.5, 0.4, 0.32), 0.2)
		for x: float in [-1.6, -0.55, 0.55, 1.6]:
			var half := sqrt(maxf(0.0, T_IN * T_IN - x * x))
			m.beam(c + Vector3(x, y - 0.2, -half), c + Vector3(x, y - 0.2, half), 0.14, 0.16, Vector3.UP, 0.015)


# --- Ruins -----------------------------------------------------------------------------

static func _ruin(b: ArchBuild, at: Vector3, prop: Dictionary, rng: RandomNumberGenerator) -> void:
	var style := String(prop.get("style", "circle"))
	var pieces: Array = prop.get("pieces", [])
	var cell_pos := func(cell: Vector2i) -> Vector3:
		var p := Vector3(cell.x + 0.5 - b.origin.x, 0, cell.y + 0.5 - b.origin.z)
		p.y = b.ground(p)
		return p
	var stone := Color(0.8, 0.79, 0.75)
	b.dirt(at.y - 0.3, 2.0, 0.4)
	match style:
		"chapel", "manor":
			_ruined_walls(b, pieces, rng, stone, style == "chapel")
		"aqueduct":
			for pc: Dictionary in pieces:
				var p: Vector3 = cell_pos.call(pc["cell"])
				var h: float = float(pc["h"]) + (0.0 if pc["broken"] else 0.4)
				b.shell.mat(L.ASHLAR, stone, 0.6)
				b.shell.box(p + Vector3(0, h * 0.5 - 0.8, 0), Vector3(1.7, h + 1.6, 1.7), 1)
				b.shell.box(p + Vector3(0, 0.15, 0), Vector3(2.1, 0.5, 2.1), 1)
				if not pc["broken"]:
					b.shell.box(p + Vector3(0, h - 1.6, 0), Vector3(1.95, 0.25, 1.95), 1)
				var along_x: bool = pc["along_x"]
				var dir := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
				# Arch to the next pier unless either is broken.
				var nxt: Dictionary = {}
				for q: Dictionary in pieces:
					if int(q["i"]) == int(pc["i"]) + 1:
						nxt = q
				if not pc["broken"] and not nxt.is_empty() and not nxt["broken"]:
					var mid := p + dir * 2.0
					_arch(b.shell, mid, dir, 2.3 * 0.5 + 0.0, h - 2.6, 1.6, stone)
					b.shell.mat(L.ASHLAR, stone * Color(0.95, 0.93, 0.9), 0.7)
					b.shell.box(mid + Vector3(0, h - 0.6, 0), Vector3(4.05 if along_x else 1.7, 1.2, 1.7 if along_x else 4.05), 0 if along_x else 2)
					b.shell.mat(L.RUBBLE, stone, 0.9)
					b.shell.box(mid + Vector3(0, h + 0.05, 0), Vector3(4.05 if along_x else 0.3, 0.1, 0.3 if along_x else 4.05), 0 if along_x else 2)
				if pc["broken"]:
					_rubble(b, p + dir * 1.8, 2.0, 9, rng, stone)
		"cairn":
			for pc: Dictionary in pieces:
				match String(pc["kind"]):
					"kerb":
						var p: Vector3 = cell_pos.call(pc["cell"])
						b.shell.mat(L.RUBBLE, stone, 0.8)
						b.shell.rock(p - Vector3(0, 0.15, 0), Vector3(0.7, 0.9, 0.6), rng.randi(), 4, 6)
					"dolmen":
						var p: Vector3 = cell_pos.call(pc["cell"])
						b.shell.mat(L.RUBBLE, stone * Color(0.9, 0.9, 0.88), 0.9)
						for o: Vector3 in [Vector3(-1.0, 0, 0.2), Vector3(1.0, 0, 0.2), Vector3(0, 0, -0.9)]:
							b.shell.rock(p + o - Vector3(0, 0.2, 0), Vector3(0.45 if o.z > -0.5 else 1.2, 2.0, 1.0 if o.z > -0.5 else 0.4), rng.randi(), 4, 6)
						b.shell.rock(p + Vector3(0, 1.62, -0.1), Vector3(1.9, 0.55, 1.6), rng.randi(), 3, 7)
						b.shell.mat(L.FLAT, Color(0.02, 0.02, 0.02), 0.0)
						b.shell.box(p + Vector3(0, 0.75, -0.55), Vector3(1.3, 1.4, 0.05), 0)
					"heap":
						_rubble(b, cell_pos.call(pc["cell"]), 1.6, 22, rng, stone, 0.55)
			b.add_light(cell_pos.call(Vector2i(int(at.x + b.origin.x), int(at.z + b.origin.z) - 5)) + Vector3(0, 0.8, 0.6), RUNE, 3.0, 0.6, true)
		"mill":
			var x0: int = (pieces[0] as Dictionary)["x0"]
			var z0: int = (pieces[0] as Dictionary)["z0"]
			var wall_pieces: Array = []
			for k in 7:
				for i in 7:
					if i == 0 or i == 6 or k == 0 or k == 6:
						if k == 6 and i == 3:
							continue
						wall_pieces.append({"kind": "wall", "cell": Vector2i(x0 + i, z0 + k), "h": 2 + int(absf(sin(i * 2.1 + k)) * 1.6), "edge": [i == 0, i == 6, k == 0, k == 6]})
			wall_pieces.append({"kind": "frame", "x0": x0, "z0": z0, "w": 7, "d": 7})
			_ruined_walls(b, wall_pieces, rng, stone * Color(0.85, 0.8, 0.75), false)
			# Charred posts and fallen beams.
			var c0 := Vector3(x0 + 3.5 - b.origin.x, 0, z0 + 3.5 - b.origin.z)
			c0.y = b.ground(c0)
			b.shell.mat(L.TIMBER, Color(0.16, 0.13, 0.12), 0.0, 0.5)
			for o: Vector2 in [Vector2(-2.6, -2.6), Vector2(2.6, -2.6), Vector2(-2.6, 2.6), Vector2(2.6, 2.6), Vector2(0, -2.6)]:
				var hh := rng.randf_range(2.5, 5.5)
				b.shell.beam(c0 + Vector3(o.x, 0, o.y), c0 + Vector3(o.x + rng.randf_range(-0.2, 0.2), hh, o.y + rng.randf_range(-0.2, 0.2)), 0.28, 0.28, Vector3.BACK, 0.03)
			for k in 4:
				var a := rng.randf() * TAU
				var p := c0 + Vector3(rng.randf_range(-1.5, 1.5), 0.2, rng.randf_range(-1.5, 1.5))
				b.shell.beam(p - Vector3(cos(a), -0.15, sin(a)) * 2.0, p + Vector3(cos(a), 0.1, sin(a)) * 2.0, 0.24, 0.26, Vector3.UP, 0.03)
			# Millstones, one lying flat, one leaning.
			b.shell.mat(L.ASHLAR, Color(0.75, 0.72, 0.66), 0.4)
			b.shell.lathe(c0 + Vector3(1.0, 0, 1.2), PackedVector2Array([Vector2(0.75, 0.0), Vector2(0.75, 0.28), Vector2(0.15, 0.28), Vector2(0.15, 0.0)]), 16, false, false)
			b.shell.push(Transform3D(Basis(Vector3.RIGHT, 1.25), c0 + Vector3(-1.4, 0.7, 4.1)))
			b.shell.lathe(Vector3.ZERO, PackedVector2Array([Vector2(0.15, -0.14), Vector2(0.75, -0.14), Vector2(0.75, 0.14), Vector2(0.15, 0.14), Vector2(0.15, -0.14)]), 16, false, false)
			b.shell.pop()
			# The broken waterwheel against the east wall.
			var wheel := c0 + Vector3(4.2, 1.6, 0)
			b.shell.mat(L.TIMBER, Color(0.32, 0.27, 0.22), 0.6)
			b.shell.push(Transform3D(Basis(Vector3.BACK, PI * 0.5) * Basis(Vector3.UP, 0.2), wheel))
			b.shell.lathe(Vector3.ZERO, PackedVector2Array([Vector2(1.7, -0.25), Vector2(1.85, -0.25), Vector2(1.85, 0.25), Vector2(1.7, 0.25), Vector2(1.7, -0.25)]), 20, false, false)
			for k in 8:
				var a := TAU * k / 8.0
				if k == 3:
					continue
				b.shell.beam(Vector3(cos(a) * 0.2, 0, sin(a) * 0.2), Vector3(cos(a) * 1.75, 0, sin(a) * 1.75), 0.1, 0.1)
				b.shell.box(Vector3(cos(a) * 1.85, 0, sin(a) * 1.85), Vector3(0.1, 0.5, 0.5), 0)
			b.shell.pop()
		"shrine":
			for pc: Dictionary in pieces:
				if pc["kind"] == "altar":
					_altar(b, cell_pos.call(pc["cell"]), stone)
					continue
				var p: Vector3 = cell_pos.call(pc["cell"])
				var h := 2.1 if pc["broken"] else 4.6
				_column(b, p, h, 0.38, pc["broken"], rng, stone)
			_rubble(b, at, 5.0, 18, rng, stone, 0.3)
		"battlefield":
			for pc: Dictionary in pieces:
				match String(pc["kind"]):
					"stake":
						var q2: Vector2 = pc["pos"]
						var p := Vector3(q2.x - b.origin.x, 0, q2.y - b.origin.z)
						p.y = b.ground(p)
						var yaw: float = pc["yaw"]
						var lean: float = pc["lean"]
						var dir := Basis(Vector3.UP, yaw) * Vector3(sin(lean), cos(lean), 0)
						b.shell.mat(L.TIMBER, Color(0.38, 0.32, 0.26), 0.5)
						b.shell.cylinder(p - dir * 0.4, p + dir * 2.0, 0.11, 0.09, 6)
						b.shell.cylinder(p + dir * 2.0, p + dir * 2.45, 0.09, 0.0, 6, false)
					"barrow_cairn":
						var p: Vector3 = cell_pos.call(pc["cell"])
						_rubble(b, p, 0.9, 12, rng, stone, 0.4)
						b.shell.mat(L.IRON, Color(0.6, 0.6, 0.62), 0.0)
						b.shell.beam(p + Vector3(0, 0.3, 0), p + Vector3(0.05, 1.5, 0.02), 0.05, 0.012)
						b.shell.beam(p + Vector3(-0.18, 1.2, 0), p + Vector3(0.22, 1.2, 0.0), 0.05, 0.04)
						b.shell.mat(L.BOARDS, Color(0.5, 0.25, 0.18), 0.4)
						b.shell.push(Transform3D(Basis(Vector3.RIGHT, 1.2), p + Vector3(0.6, 0.35, 0.4)))
						b.shell.lathe(Vector3.ZERO, PackedVector2Array([Vector2(0.38, 0.0), Vector2(0.38, 0.04), Vector2(0.0, 0.07)]), 12, true, false)
						b.shell.pop()
					"wagon":
						var q2: Vector2 = pc["pos"]
						var p := Vector3(q2.x - b.origin.x, 0, q2.y - b.origin.z)
						p.y = b.ground(p) - 0.2
						b.push(Transform3D(Basis(Vector3.UP, float(pc["yaw"])) * Basis(Vector3.FORWARD, 0.5), p))
						VillageProps.cart(b, Vector3.ZERO, 0.0, rng)
						b.pop()
		_:
			for pc: Dictionary in pieces:
				if pc["kind"] == "altar":
					_altar(b, cell_pos.call(pc["cell"]), stone)
					continue
				var p: Vector3 = cell_pos.call(pc["cell"])
				var to_c := at - p
				var yaw := atan2(to_c.x, to_c.z)
				if pc["fallen"]:
					b.shell.push(Transform3D(Basis(Vector3.UP, yaw + 1.3) * Basis(Vector3.BACK, PI * 0.47), p + Vector3(0, 0.45, 0)))
					_monolith(b, Vector3.ZERO, float(pc["h"]), 0.0, 0.0, rng.randi(), Color(0, 0, 0, 0))
					b.shell.pop()
				else:
					_monolith(b, p, float(pc["h"]), yaw, rng.randf_range(-0.07, 0.07), rng.randi(), Color(0.6, 0.75, 1.0, 1.0) if rng.randf() < 0.3 else Color(0, 0, 0, 0))
	_rubble(b, at + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4)), 2.5, 10, rng, stone, 0.3)


## Walls left standing from a planned rectangle: each side a continuous
## rubble wall with a crumbling top, its height following the plan's cells.
static func _ruined_walls(b: ArchBuild, pieces: Array, rng: RandomNumberGenerator, stone: Color, chapel: bool) -> void:
	var frame: Dictionary = {}
	var heights := {}
	for pc: Dictionary in pieces:
		if pc["kind"] == "frame":
			frame = pc
		elif pc["kind"] == "wall":
			heights[pc["cell"]] = int(pc["h"])
	if frame.is_empty():
		return
	var x0: int = frame["x0"]
	var z0: int = frame["z0"]
	var w: int = frame["w"]
	var d: int = frame["d"]
	var m := b.shell
	var t := 0.85
	var base_y := b.ground(Vector3(x0 + w * 0.5 - b.origin.x, 0, z0 + d * 0.5 - b.origin.z))
	for side in 4:
		var cells: Array[Vector2i] = []
		var length := w if side < 2 else d
		for i in length:
			match side:
				0:
					cells.append(Vector2i(x0 + i, z0 + d - 1))
				1:
					cells.append(Vector2i(x0 + w - 1 - i, z0))
				2:
					cells.append(Vector2i(x0, z0 + i))
				_:
					cells.append(Vector2i(x0 + w - 1, z0 + d - 1 - i))
		var fxf := ArchKit.side_frame(side, float(w), float(d))
		var origin := Vector3(x0 + w * 0.5 - b.origin.x, base_y, z0 + d * 0.5 - b.origin.z)
		m.push(Transform3D(Basis.IDENTITY, origin) * fxf)
		# Runs of standing wall between gaps.
		var run_pts := PackedVector2Array()
		for i in length + 1:
			var hc := 0
			if i < length:
				hc = heights.get(cells[i], 0)
			var standing := i < length and hc > 0
			if standing:
				if run_pts.is_empty():
					run_pts.append(Vector2(float(i), -0.6))
				var n := 3
				var hp := float(heights.get(cells[i - 1], hc)) if i > 0 else float(hc)
				var hn := float(heights.get(cells[i + 1], hc)) if i < length - 1 else float(hc)
				for k in n:
					var f := (k + 0.5) / n
					var u := float(i) + f
					# Blend towards the neighbours so the top crumbles rather than steps.
					var base := lerpf(lerpf(hp, float(hc), 0.5 + f * 0.5), lerpf(float(hc), hn, f * 0.5), f)
					var hh := base - 0.35 + sin(u * 4.3 + side) * 0.18 + rng.randf_range(-0.22, 0.12)
					run_pts.append(Vector2(u, maxf(0.35, hh)))
			if (not standing or i == length) and not run_pts.is_empty():
				var end_u := float(i)
				run_pts.append(Vector2(end_u, run_pts[run_pts.size() - 1].y * 0.7))
				run_pts.append(Vector2(end_u, -0.6))
				var outline := PackedVector2Array()
				outline.append(run_pts[0])
				for k in range(1, run_pts.size()):
					outline.append(run_pts[k])
				outline.reverse()
				m.mat(L.RUBBLE, stone, 0.75)
				m.prism(Vector3(0, 0, -t), Vector3.RIGHT, Vector3.UP, outline, t, true, true)
				run_pts = PackedVector2Array()
		m.pop()
	# Fallen beams, rubble and a flagged floor.
	var c := Vector3(x0 + w * 0.5 - b.origin.x, base_y, z0 + d * 0.5 - b.origin.z)
	b.interior.mat(L.COBBLE, Color(0.72, 0.7, 0.66), 0.8)
	b.interior.rect(c + Vector3(-w * 0.5 + 0.8, 0.02, d * 0.5 - 0.8), Vector3.RIGHT, Vector3.FORWARD, w - 1.6, d - 1.6)
	m.mat(L.TIMBER, Color(0.3, 0.25, 0.2), 0.6)
	for k in 3:
		var a := rng.randf() * TAU
		var p := c + Vector3(rng.randf_range(-w * 0.25, w * 0.25), 0.1, rng.randf_range(-d * 0.25, d * 0.25))
		var hdir := Vector3(cos(a), 0, sin(a))
		m.beam(p - hdir * 2.2 + Vector3(0, 0.05, 0), p + hdir * 2.2 + Vector3(0, 0.6, 0), 0.24, 0.28, Vector3.UP, 0.03)
	_rubble(b, c + Vector3(-w * 0.3, 0, 0), 1.6, 12, rng, stone)
	_rubble(b, c + Vector3(w * 0.3, 0, d * 0.2), 1.2, 8, rng, stone)


static func _rubble(b: ArchBuild, c: Vector3, radius: float, count: int, rng: RandomNumberGenerator, stone: Color, size := 0.35) -> void:
	var m := b.shell
	m.mat(L.ASHLAR, stone, 0.7)
	for k in count:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		var p := c + Vector3(cos(a) * r, 0, sin(a) * r)
		p.y = b.ground(p) - 0.06 + (radius - r) * 0.15 * (size / 0.35)
		var s := size * rng.randf_range(0.6, 1.3)
		m.rock(p, Vector3(s * rng.randf_range(0.9, 1.5), s * rng.randf_range(0.6, 0.9), s * rng.randf_range(0.9, 1.4)), rng.randi(), 3, 6)


static func _column(b: ArchBuild, p: Vector3, h: float, r: float, broken: bool, rng: RandomNumberGenerator, stone: Color) -> void:
	var m := b.shell
	m.mat(L.ASHLAR, stone * Color(1.05, 1.04, 1.0), 0.6)
	m.box(p + Vector3(0, -0.1, 0), Vector3(r * 2.9, 0.5, r * 2.9), 1)
	m.lathe(p + Vector3(0, 0.15, 0), PackedVector2Array([Vector2(r * 1.25, 0.0), Vector2(r * 1.1, 0.18), Vector2(r * 1.0, 0.3)]), 14, false, false)
	var drums := maxi(2, int(h / 0.9))
	var dh := (h - 0.45) / drums
	for k in drums:
		var top := k == drums - 1
		var y := 0.45 + k * dh
		var prof := PackedVector2Array([Vector2(r, 0.0), Vector2(r * 0.97, dh - 0.01)])
		m.push(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p + Vector3(rng.randf_range(-0.02, 0.02), y, rng.randf_range(-0.02, 0.02))))
		if broken and top:
			# A jagged break.
			m.lathe(Vector3.ZERO, PackedVector2Array([Vector2(r, 0.0), Vector2(r * 0.97, dh * 0.6), Vector2(r * 0.4, dh * 0.9), Vector2(0.0, dh * 0.5)]), 9, false, false)
		else:
			m.lathe(Vector3.ZERO, prof, 14, false, top)
		m.pop()
	if not broken:
		m.box(p + Vector3(0, h + 0.15, 0), Vector3(r * 2.6, 0.3, r * 2.6), 1)
		m.lathe(p + Vector3(0, h - 0.05, 0), PackedVector2Array([Vector2(r, 0.0), Vector2(r * 1.25, 0.06)]), 14, false, false)
	else:
		# The fallen drums.
		var a := rng.randf() * TAU
		for k in 2:
			var q := p + Vector3(cos(a), 0, sin(a)) * (1.3 + k * 1.0)
			q.y = b.ground(q) + r * 0.9
			m.push(Transform3D(Basis(Vector3.UP, a + rng.randf_range(-0.3, 0.3)) * Basis(Vector3.BACK, PI * 0.5), q))
			m.lathe(Vector3(0, -0.4, 0), PackedVector2Array([Vector2(r, 0.0), Vector2(r, 0.8)]), 12, true, true)
			m.pop()


static func _altar(b: ArchBuild, p: Vector3, stone: Color) -> void:
	var m := b.shell
	m.mat(L.ASHLAR, stone * Color(1.05, 1.03, 1.0), 0.6)
	m.box(p + Vector3(0, 0.0, 0), Vector3(2.0, 0.3, 1.3), 0)
	m.box(p + Vector3(0, 0.55, 0), Vector3(1.5, 0.8, 0.85), 0)
	m.box(p + Vector3(0, 1.0, 0), Vector3(1.7, 0.12, 1.0), 0)
	for k in 3:
		VillageProps.candle(b.detail, p + Vector3(-0.5 + k * 0.5, 1.06, 0.2))


## A round arch of voussoirs across `dir` centred at `c` (spring height y).
static func _arch(m: ArchMesh, c: Vector3, dir: Vector3, r: float, y: float, depth: float, stone: Color) -> void:
	m.mat(L.ASHLAR, stone * Color(1.04, 1.02, 1.0), 0.6)
	var side := Vector3.UP.cross(dir).normalized()
	var n := 11
	for i in n:
		var a0 := PI * float(i) / n
		var a1 := PI * float(i + 1) / n
		var mid := (a0 + a1) * 0.5
		var p := c + dir * (-cos(mid) * (r + 0.2)) + Vector3(0, y + sin(mid) * (r + 0.2), 0)
		m.push(Transform3D(Basis(dir, Vector3.UP, side) * Basis(Vector3.BACK, mid - PI * 0.5), p))
		m.box(Vector3.ZERO, Vector3((r + 0.2) * (a1 - a0) * 0.96, 0.42, depth), 0)
		m.pop()


# --- Crater and Asphodel -----------------------------------------------------------------

static func _crater(b: ArchBuild, at: Vector3, prop: Dictionary, rng: RandomNumberGenerator) -> void:
	var m := b.shell
	var basalt := Color(0.32, 0.29, 0.29)
	for cl: Dictionary in prop.get("clusters", []):
		var cell: Vector2i = cl["cell"]
		var c := Vector3(cell.x + 0.5 - b.origin.x, 0, cell.y + 0.5 - b.origin.z)
		c.y = b.ground(c)
		var h: float = cl["h"]
		var r: float = cl["r"]
		var n := 5 + int(r * 4.0)
		for k in n:
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * r
			var q := c + Vector3(cos(a) * d, 0, sin(a) * d)
			var hh := h * rng.randf_range(0.45, 1.0) * (1.0 - d / (r + 0.5) * 0.4)
			m.mat(L.RUBBLE, basalt, 0.1)
			m.lathe(q + Vector3(0, -0.6, 0), PackedVector2Array([Vector2(0.38, 0.0), Vector2(0.36, hh + 0.6)]), 6, false, false, rng.randf())
			m.mat(L.RUBBLE, basalt * Color(1.2, 1.15, 1.1), 0.0)
			m.lathe(q + Vector3(0, hh, 0), PackedVector2Array([Vector2(0.36, 0.0), Vector2(0.0, rng.randf_range(0.05, 0.25))]), 6, false, false, rng.randf())
	# The obelisk.
	var g := at
	g.y = b.ground(at)
	m.mat(L.ASHLAR, Color(0.25, 0.22, 0.22), 0.0)
	m.box(g + Vector3(0, 0.1, 0), Vector3(2.4, 0.5, 2.4), 1)
	m.lathe(g + Vector3(0, 0.35, 0), PackedVector2Array([Vector2(0.75, 0.0), Vector2(0.5, 4.2), Vector2(0.0, 4.9)]), 4, false, false, PI * 0.25)
	m.mat(L.EMBER, Color(1.0, 0.45, 0.2), 0.0)
	for k in 4:
		var a := PI * 0.5 * k
		var d := Vector3(cos(a), 0, sin(a))
		for j in 5:
			var y := 0.9 + j * 0.7
			var r := lerpf(0.75, 0.5, (y - 0.35) / 4.2) * 0.72 + 0.01
			m.push(Transform3D(Basis(Vector3.UP, -a + PI * 0.5), g + d * r + Vector3(0, y, 0)))
			m.box(Vector3.ZERO, Vector3(0.22 if j % 2 == 0 else 0.08, 0.05, 0.02), 0)
			m.box(Vector3(0, 0.12, 0), Vector3(0.05, 0.2, 0.02), 1)
			m.pop()
	b.add_light(g + Vector3(0, 2.5, 0), Color(1.0, 0.45, 0.2), 6.0, 0.8, false)


static func _asphodel(b: ArchBuild, at: Vector3, prop: Dictionary, rng: RandomNumberGenerator) -> void:
	var m := b.shell
	var g := at
	g.y = b.ground(at)
	var obsidian := Color(0.16, 0.13, 0.17)
	# Basalt flags.
	m.mat(L.COBBLE, Color(0.4, 0.34, 0.33), 0.0)
	m.lathe(g, PackedVector2Array([Vector2(6.5, -0.3), Vector2(6.5, 0.08), Vector2(0.0, 0.08)]), 24, false, false)
	# The gate: two carved obsidian pillars, a lintel, horns.
	for s: float in [-1.0, 1.0]:
		var p := g + Vector3(s * 5.0, 0, -7.0)
		m.mat(L.ASHLAR, obsidian, 0.0)
		m.box(p + Vector3(0, 0.35, 0), Vector3(2.0, 0.7, 2.0), 1)
		m.box(p + Vector3(0, 6.6, 0), Vector3(1.3, 12.0, 1.3), 1)
		for y: float in [2.0, 6.0, 10.0]:
			m.mat(L.ASHLAR, obsidian * Color(1.4, 1.2, 1.2), 0.0)
			m.box(p + Vector3(0, y, 0), Vector3(1.5, 0.3, 1.5), 1)
		m.mat(L.EMBER, Color(1.0, 0.35, 0.12), 0.0)
		for y: float in [3.2, 4.4, 7.4, 8.6]:
			m.box(p + Vector3(-s * 0.66, y, 0), Vector3(0.02, 0.7, 0.18), 1)
		m.mat(L.FLAT, Color(0.86, 0.82, 0.72), 0.0)
		m.push(Transform3D(Basis(Vector3.BACK, s * 0.5), p + Vector3(s * 0.3, 13.2, 0)))
		m.lathe(Vector3.ZERO, PackedVector2Array([Vector2(0.28, 0.0), Vector2(0.2, 0.9), Vector2(0.08, 1.7), Vector2(0.0, 2.0)]), 8, true, false)
		m.pop()
	m.mat(L.ASHLAR, obsidian, 0.0)
	m.box(g + Vector3(0, 13.0, -7.0), Vector3(12.4, 1.0, 1.7), 0)
	m.box(g + Vector3(0, 12.4, -7.0), Vector3(10.6, 0.3, 1.4), 0)
	# Bone braziers.
	for cell: Vector2i in prop.get("braziers", []):
		var p := Vector3(cell.x + 0.5 - b.origin.x, 0, cell.y + 0.5 - b.origin.z)
		p.y = b.ground(p)
		m.mat(L.FLAT, Color(0.84, 0.8, 0.7), 0.0)
		for k in 5:
			var a := TAU * k / 5.0
			m.beam(p + Vector3(cos(a) * 0.45, 0, sin(a) * 0.45), p + Vector3(cos(a) * 0.3, 1.3, sin(a) * 0.3), 0.07, 0.07)
			m.lathe(p + Vector3(cos(a) * 0.3, 1.3, sin(a) * 0.3), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.09, 0.05), Vector2(0.0, 0.14)]), 6, false, false)
		m.mat(L.IRON, Color(0.4, 0.38, 0.38), 0.0)
		m.lathe(p + Vector3(0, 1.25, 0), PackedVector2Array([Vector2(0.12, 0.0), Vector2(0.45, 0.25), Vector2(0.42, 0.27)]), 10, true, false)
		m.mat(L.EMBER, Color(1, 1, 1), 0.0)
		m.lathe(p + Vector3(0, 1.45, 0), PackedVector2Array([Vector2(0.4, 0.0), Vector2(0.0, 0.1)]), 9, false, false)
		b.add_fire(p + Vector3(0, 1.5, 0), 1.0, 9.0, 2.2)
	_rubble(b, g + Vector3(0, 0, 3), 6.0, 10, rng, Color(0.35, 0.3, 0.3), 0.4)


# --- Abandoned mine ------------------------------------------------------------------------

## Timber sets down the adit, rails and sleepers, a braced portal, an ore cart
## and lanterns. prop: origin (world), steps, rate, width centre.
static func _mine(b: ArchBuild, prop: Dictionary, rng: RandomNumberGenerator) -> void:
	var o: Vector3 = (prop["origin"] as Vector3) - b.origin
	var steps: int = prop.get("steps", 90)
	var rate: float = prop.get("rate", 0.58)
	var cx: float = prop.get("cx", 12.5)
	var top_z: float = prop.get("top_z", 96.0)
	var floor_at := func(step: float) -> Vector3:
		return o + Vector3(cx, 62.0 - step * rate + 0.05, top_z - step + 0.5)
	var m := b.shell
	var wood := Color(0.5, 0.42, 0.33)
	# Where the adit goes under the hill: the portal stands there.
	var portal_step := 0
	for s in steps:
		var f: Vector3 = floor_at.call(float(s))
		if b.ground(f) > f.y + 5.6:
			portal_step = s
			break
	for s in range(0, steps, 6):
		if s < portal_step:
			continue
		var f: Vector3 = floor_at.call(float(s))
		m.mat(L.TIMBER, wood * Color(rng.randf_range(0.85, 1.1), 1, 1), 0.7)
		for side: float in [-1.0, 1.0]:
			m.cylinder(f + Vector3(side * 3.0, -0.3, 0), f + Vector3(side * 2.85, 4.55, 0), 0.17, 0.15, 7)
		m.beam(f + Vector3(-3.4, 4.65, 0), f + Vector3(3.4, 4.65, 0), 0.32, 0.3, Vector3.UP, 0.04)
		# Lagging boards over the cap and down the sides.
		m.mat(L.BOARDS, wood * Color(0.9, 0.85, 0.8), 0.6)
		for k in 7:
			var x := -3.0 + k
			b.detail.mat(L.BOARDS, wood * Color(0.9, 0.85, 0.8), 0.6)
			b.detail.box(f + Vector3(x, 4.86, 0.0), Vector3(0.9, 0.06, 2.8), 2)
		for side: float in [-1.0, 1.0]:
			for k in 3:
				b.detail.box(f + Vector3(side * 3.2, 1.0 + k * 1.2, 0), Vector3(0.06, 0.9, 2.6), 2)
		# Lantern on every other set.
		if (s / 6) % 2 == 0:
			var lp := f + Vector3(0, 4.1, 0.25)
			b.detail.mat(L.IRON, Color(0.5, 0.5, 0.5), 0.0)
			b.detail.cylinder(lp + Vector3(0, 0.45, 0), lp + Vector3(0, 0.25, 0), 0.008, -1.0, 4)
			b.detail.lathe(lp + Vector3(0, 0.18, 0), PackedVector2Array([Vector2(0.12, 0.0), Vector2(0.02, 0.08)]), 6, true, false)
			b.detail.mat(L.GLASS, Color(1, 1, 1), 1.0)
			b.detail.lathe(lp, PackedVector2Array([Vector2(0.09, 0.0), Vector2(0.1, 0.18)]), 6, true, false)
			b.detail.mat(L.EMBER, Color(1.5, 1.2, 0.8), 0.0)
			b.detail.lathe(lp + Vector3(0, 0.03, 0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.02, 0.03), Vector2(0.0, 0.09)]), 5, false, false)
			b.lights.append({"pos": lp, "color": Color(1.0, 0.65, 0.35), "range": 9.0, "energy": 1.3, "night": false})
	# The portal: heavy posts, cap, braces, a weathered sign.
	var pf: Vector3 = floor_at.call(float(portal_step))
	m.mat(L.TIMBER, wood * Color(0.85, 0.8, 0.75), 0.8)
	for side: float in [-1.0, 1.0]:
		m.cylinder(pf + Vector3(side * 3.25, -0.6, 0.3), pf + Vector3(side * 3.1, 5.1, 0.3), 0.26, 0.23, 8)
		m.beam(pf + Vector3(side * 3.15, 3.6, 0.3), pf + Vector3(side * 1.9, 4.95, 0.3), 0.2, 0.2, Vector3.BACK, 0.02)
		m.beam(pf + Vector3(side * 3.3, -0.2, 1.6), pf + Vector3(side * 3.15, 3.0, 0.4), 0.2, 0.2)
	m.beam(pf + Vector3(-4.0, 5.2, 0.3), pf + Vector3(4.0, 5.2, 0.3), 0.46, 0.42, Vector3.UP, 0.05)
	b.detail.mat(L.BOARDS, Color(0.55, 0.45, 0.36), 0.6)
	b.detail.box(pf + Vector3(0, 5.85, 0.55), Vector3(2.4, 0.55, 0.06), 0)
	b.detail.mat(L.IRON, Color(0.4, 0.4, 0.4), 0.0)
	b.detail.box(pf + Vector3(-0.6, 5.85, 0.59), Vector3(0.5, 0.06, 0.02), 0)
	b.detail.box(pf + Vector3(0.4, 5.85, 0.59), Vector3(0.8, 0.06, 0.02), 0)
	# Rails and sleepers from the mouth down to the gallery.
	var start := maxi(0, portal_step - 8)
	for s in range(start, steps - 2):
		var f: Vector3 = floor_at.call(float(s))
		var f2: Vector3 = floor_at.call(float(s + 1))
		b.detail.mat(L.TIMBER, wood * Color(0.7, 0.65, 0.6), 0.6)
		for k in 2:
			var q := f.lerp(f2, k * 0.5)
			b.detail.box(q + Vector3(0, 0.05, 0), Vector3(1.6, 0.1, 0.22), 0)
		b.detail.mat(L.IRON, Color(0.55, 0.5, 0.48), 0.0)
		for side: float in [-0.55, 0.55]:
			b.detail.beam(f + Vector3(side, 0.15, 0), f2 + Vector3(side, 0.15, 0), 0.07, 0.09, Vector3.UP)
	# An ore cart on the rails by the mouth, a spoil heap outside.
	var cf: Vector3 = floor_at.call(float(maxi(start, portal_step - 3)))
	_ore_cart(b, cf + Vector3(0, 0.2, 0), rng)
	var heap := o + Vector3(cx + 7.0, 0, top_z + 4.0)
	heap.y = b.ground(heap)
	_rubble(b, heap, 2.5, 20, rng, Color(0.55, 0.5, 0.45), 0.45)
	VillageProps.crate(b.detail, _ground_at(b, o + Vector3(cx - 5.0, 0, top_z + 2.0)), 0.7, 0.3)
	VillageProps.barrel(b.detail, _ground_at(b, o + Vector3(cx - 5.5, 0, top_z + 3.2)), 0.95, 0.34, 0.8)
	# The gallery at the bottom: props and a lantern.
	var gal := o + Vector3(12.5, 4.0, 13.5)
	_ore_cart(b, gal + Vector3(3.0, 0.0, 2.0), rng)
	for k in 3:
		VillageProps.crate(b.detail, gal + Vector3(-5.0 + k * 0.75, 0, -4.0), 0.6, rng.randf())
	VillageProps.barrel(b.detail, gal + Vector3(-5.5, 0, -2.8), 0.95, 0.34, rng.randf())
	b.lights.append({"pos": gal + Vector3(0, 3.0, 0), "color": Color(1.0, 0.65, 0.35), "range": 12.0, "energy": 1.4, "night": false})


static func _ore_cart(b: ArchBuild, p: Vector3, rng: RandomNumberGenerator) -> void:
	var m := b.detail
	m.mat(L.BOARDS, Color(0.48, 0.4, 0.32), 0.6)
	m.box(p + Vector3(0, 0.75, 0), Vector3(1.0, 0.75, 1.4), 1)
	m.mat(L.IRON, Color(0.45, 0.42, 0.4), 0.0)
	for y: float in [0.45, 1.05]:
		m.box(p + Vector3(0, y, 0), Vector3(1.04, 0.06, 1.44), 0)
	for sx: float in [-0.55, 0.55]:
		for sz: float in [-0.45, 0.45]:
			m.push(Transform3D(Basis(Vector3.BACK, PI * 0.5), p + Vector3(sx, 0.22, sz)))
			m.lathe(Vector3(0, -0.04, 0), PackedVector2Array([Vector2(0.2, 0.0), Vector2(0.2, 0.08)]), 10, true, true)
			m.pop()
	m.mat(L.RUBBLE, Color(0.45, 0.38, 0.32), 0.0)
	for k in 6:
		m.rock(p + Vector3(rng.randf_range(-0.3, 0.3), 1.05, rng.randf_range(-0.45, 0.45)), Vector3(0.25, 0.2, 0.25), rng.randi(), 3, 5)


# --- Shipwreck ------------------------------------------------------------------------------

## A broken hull lying on its side on the sea floor, ribs showing.
static func _wreck(b: ArchBuild, at: Vector3, prop: Dictionary, rng: RandomNumberGenerator) -> void:
	var m := b.shell
	var g := at
	g.y = b.ground(at) - 0.4
	var wood := Color(0.42, 0.38, 0.33)
	var length := 15.0
	var beam_w := 5.0
	var depth := 3.2
	var xf := Transform3D(Basis(Vector3.UP, float(prop.get("yaw", 0.3))) * Basis(Vector3.RIGHT, 0.0) * Basis(Vector3.BACK, 0.38), g)
	b.push(xf)
	# Hull section: half-width and keel depth along the length (bow at +x).
	var hw := func(x: float) -> float:
		var f := clampf(x / (length * 0.5), -1.0, 1.0)
		return beam_w * 0.5 * sqrt(maxf(0.0, 1.0 - pow(absf(f), 2.4)))
	var section := func(x: float, t: float, side: float) -> Vector3:
		# t: 0 keel .. 1 gunwale
		var w: float = hw.call(x)
		var a := t * PI * 0.5
		return Vector3(x, depth * (1.0 - cos(a)) - 0.0, side * w * sin(a))
	# Ribs.
	m.mat(L.TIMBER, wood, 0.9)
	var nx := 14
	for i in nx + 1:
		var x := -length * 0.5 + 0.6 + (length - 1.2) * float(i) / nx
		for side: float in [-1.0, 1.0]:
			var top_t := 1.0 if side < 0.0 or rng.randf() < 0.4 else rng.randf_range(0.45, 0.8)
			var prev: Vector3 = section.call(x, 0.0, side)
			for k in range(1, 7):
				var t := top_t * float(k) / 6.0
				var q: Vector3 = section.call(x, t, side)
				m.beam(prev, q, 0.16, 0.18, Vector3.RIGHT)
				prev = q
	# Keel, stem and stern posts.
	m.beam(Vector3(-length * 0.5, -0.05, 0), Vector3(length * 0.5, -0.05, 0), 0.32, 0.4, Vector3.UP, 0.04)
	m.beam(Vector3(length * 0.5 - 0.3, 0.0, 0), Vector3(length * 0.5 + 0.6, depth + 1.0, 0), 0.3, 0.3, Vector3.BACK)
	m.beam(Vector3(-length * 0.5 + 0.2, 0.0, 0), Vector3(-length * 0.5 - 0.2, depth + 0.8, 0), 0.3, 0.3, Vector3.BACK)
	# Planking: strakes between the ribs, missing in places (more on the
	# broken upper side).
	m.mat(L.BOARDS, wood * Color(1.1, 1.05, 1.0), 0.95)
	var strakes := 8
	var nseg := 24
	for side: float in [-1.0, 1.0]:
		for k in strakes:
			var t0 := float(k) / strakes
			var t1 := float(k + 1) / strakes - 0.012
			for i in nseg:
				var x0 := -length * 0.5 + length * float(i) / nseg
				var x1 := -length * 0.5 + length * float(i + 1) / nseg
				var missing := (side > 0.0 and t0 > 0.35 and rng.randf() < 0.55) or rng.randf() < 0.08
				if missing:
					continue
				var a: Vector3 = section.call(x0, t0, side)
				var c: Vector3 = section.call(x1, t0, side)
				var d: Vector3 = section.call(x1, t1, side)
				var e: Vector3 = section.call(x0, t1, side)
				var nrm := ((c - a).cross(e - a)).normalized()
				if nrm.dot(Vector3(0, -0.3, side)) < 0.0:
					nrm = -nrm
				var off := nrm * 0.1
				m.quad(a + off, c + off, d + off, e + off, Vector2(x0, -t0 * 3.0), Vector2(x1, -t0 * 3.0), Vector2(x1, -t1 * 3.0), Vector2(x0, -t1 * 3.0), nrm)
				m.quad(e + off * 0.3, d + off * 0.3, c + off * 0.3, a + off * 0.3, Vector2(x0, -t1 * 3.0), Vector2(x1, -t1 * 3.0), Vector2(x1, -t0 * 3.0), Vector2(x0, -t0 * 3.0), -nrm)
	# Deck beams across, a few deck planks.
	m.mat(L.TIMBER, wood, 0.9)
	for i in 6:
		var x := -length * 0.35 + i * 2.0
		var w: float = hw.call(x)
		m.beam(Vector3(x, depth - 0.2, -w), Vector3(x, depth - 0.2, w), 0.22, 0.24, Vector3.UP)
	b.pop()
	# The snapped mast lying beside the hull, cargo strewn about.
	var mast_a := g + Basis(Vector3.UP, float(prop.get("yaw", 0.3))) * Vector3(1.0, 0.3, 4.2)
	m.mat(L.TIMBER, wood * Color(1.1, 1.05, 1.0), 0.9)
	m.cylinder(mast_a, mast_a + Basis(Vector3.UP, float(prop.get("yaw", 0.3)) + 0.4) * Vector3(9.0, 0.6, 0.0), 0.24, 0.17, 8)
	for k in 5:
		var a := rng.randf() * TAU
		var p := g + Vector3(cos(a), 0, sin(a)) * rng.randf_range(5.0, 9.0)
		p.y = b.ground(p) - 0.1
		if k % 2 == 0:
			VillageProps.barrel(b.detail, p, 0.9, 0.32, rng.randf() * TAU, true)
		else:
			b.push(Transform3D(Basis(Vector3.BACK, rng.randf_range(-0.4, 0.4)), Vector3.ZERO))
			VillageProps.crate(b.detail, p, 0.7, rng.randf() * TAU)
			b.pop()


# --- Gateways and the Ryft --------------------------------------------------------------------

## An ancient stone gate round a portal veil: carved pillars, a lintel, runes.
static func _gateway(b: ArchBuild, at: Vector3, prop: Dictionary, rng: RandomNumberGenerator) -> void:
	var m := b.shell
	var g := at
	g.y = b.ground(at)
	var size: Vector2 = prop.get("portal", Vector2(3, 5))
	var yaw: float = prop.get("yaw", 0.0)
	var rune: Color = prop.get("rune", RYFT_RUNE)
	var stone: Color = prop.get("stone", Color(0.62, 0.62, 0.66))
	m.push(Transform3D(Basis(Vector3.UP, yaw), g))
	var half := size.x * 0.5 + 0.55
	m.mat(L.ASHLAR, stone * Color(0.9, 0.9, 0.9), 0.5)
	m.box(Vector3(0, -0.15, 0.6), Vector3(size.x + 3.0, 0.5, 2.8), 0)
	m.box(Vector3(0, 0.12, 1.6), Vector3(size.x + 2.2, 0.24, 0.8), 0)
	for s: float in [-1.0, 1.0]:
		var x := s * half
		m.mat(L.ASHLAR, stone, 0.6)
		m.box(Vector3(x, 0.3, 0), Vector3(1.3, 0.6, 1.3), 1)
		m.beam(Vector3(x, 0.55, 0), Vector3(x, 0.6 + size.y, 0), 0.95, 0.95, Vector3.BACK, 0.2)
		m.beam(Vector3(x, 0.55, 0), Vector3(x, 0.95, 0), 1.15, 1.15, Vector3.BACK, 0.12)
		m.box(Vector3(x, size.y + 0.75, 0), Vector3(1.2, 0.3, 1.2), 1)
		m.mat(L.EMBER, rune, 0.0)
		for k in 5:
			var y := 1.0 + k * (size.y - 0.8) / 5.0
			m.box(Vector3(x - s * 0.48, y, 0), Vector3(0.02, 0.32, 0.12), 1)
			m.box(Vector3(x - s * 0.48, y + 0.2, 0.08 if k % 2 == 0 else -0.08), Vector3(0.02, 0.05, 0.18), 2)
	m.mat(L.ASHLAR, stone * Color(1.05, 1.05, 1.05), 0.5)
	m.beam(Vector3(-half - 0.8, size.y + 1.25, 0), Vector3(half + 0.8, size.y + 1.25, 0), 1.3, 0.7, Vector3.UP, 0.12)
	m.prism(Vector3(-0.9, size.y + 1.6, -0.55), Vector3.RIGHT, Vector3.UP, PackedVector2Array([Vector2(0, 0), Vector2(1.8, 0), Vector2(0.9, 0.9)]), 1.1, true, true)
	m.mat(L.EMBER, rune, 0.0)
	m.lathe(Vector3(0, size.y + 1.95, 0.56), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.18, 0.0)]), 10, false, false)
	m.pop()
	_rubble(b, g + Basis(Vector3.UP, yaw) * Vector3(half + 1.6, 0, 1.2), 1.0, 5, rng, stone, 0.3)


## Ryft ruins: the landing's paving, the observatory, the crystal crown, the
## driftwood refuge.
static func _ryft(b: ArchBuild, at: Vector3, prop: Dictionary, rng: RandomNumberGenerator) -> void:
	var m := b.shell
	var g := at
	g.y = b.ground(at)
	var stone := Color(0.6, 0.58, 0.68)
	match String(prop.get("variant", "")):
		"landing":
			m.mat(L.ASHLAR, stone, 0.6)
			m.lathe(g, PackedVector2Array([Vector2(5.0, -0.4), Vector2(5.0, 0.08), Vector2(0.0, 0.08)]), 20, false, false)
			for k in 5:
				var a := TAU * k / 5.0 + 0.4
				var p := g + Vector3(cos(a), 0, sin(a)) * 6.2
				p.y = b.ground(p)
				_column(b, p, 3.4 if k % 2 == 0 else 1.6, 0.32, k % 2 == 1, rng, stone)
		"observatory":
			# The drum of a fallen observatory and its armillary sphere.
			m.mat(L.ASHLAR, stone, 0.6)
			for i in 20:
				var a0 := TAU * i / 20.0
				var a1 := TAU * (i + 1) / 20.0
				var h := 1.5 + absf(sin(i * 1.3)) * 3.5
				var d0 := Vector3(cos(a0), 0, sin(a0))
				var d1 := Vector3(cos(a1), 0, sin(a1))
				if i % 7 == 3:
					continue
				m.quad(g + d0 * 4.6 + Vector3(0, -0.5, 0), g + d1 * 4.6 + Vector3(0, -0.5, 0), g + d1 * 4.6 + Vector3(0, h, 0), g + d0 * 4.6 + Vector3(0, h, 0),
						Vector2(a0 * 4.6, 0.5), Vector2(a1 * 4.6, 0.5), Vector2(a1 * 4.6, -h), Vector2(a0 * 4.6, -h), ((d0 + d1) * 0.5).normalized())
				m.quad(g + d1 * 4.0 + Vector3(0, -0.5, 0), g + d0 * 4.0 + Vector3(0, -0.5, 0), g + d0 * 4.0 + Vector3(0, h, 0), g + d1 * 4.0 + Vector3(0, h, 0),
						Vector2(a1 * 4.0, 0.5), Vector2(a0 * 4.0, 0.5), Vector2(a0 * 4.0, -h), Vector2(a1 * 4.0, -h), -((d0 + d1) * 0.5).normalized())
				m.quad(g + d0 * 4.0 + Vector3(0, h, 0), g + d1 * 4.0 + Vector3(0, h, 0), g + d1 * 4.6 + Vector3(0, h, 0), g + d0 * 4.6 + Vector3(0, h, 0),
						Vector2(a0, 0), Vector2(a1, 0), Vector2(a1, 0.6), Vector2(a0, 0.6), Vector3.UP)
			m.mat(L.ASHLAR, stone * Color(1.1, 1.1, 1.1), 0.3)
			m.box(g + Vector3(0, 0.5, 0), Vector3(1.4, 1.0, 1.4), 1)
			m.mat(L.IRON, Color(1.0, 0.78, 0.4), 0.0)
			var sc := g + Vector3(0, 2.6, 0)
			m.cylinder(g + Vector3(0, 1.0, 0), sc, 0.08, -1.0, 8)
			for k in 3:
				m.push(Transform3D(Basis(Vector3.RIGHT, k * 1.05) * Basis(Vector3.BACK, 0.4 * k), sc))
				m.lathe(Vector3(0, -0.04, 0), PackedVector2Array([Vector2(1.2, 0.0), Vector2(1.3, 0.0), Vector2(1.3, 0.08), Vector2(1.2, 0.08), Vector2(1.2, 0.0)]), 24, false, false)
				m.pop()
			m.mat(L.EMBER, RYFT_RUNE, 0.0)
			m.lathe(sc - Vector3(0, 0.25, 0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.22, 0.12), Vector2(0.24, 0.25), Vector2(0.22, 0.38), Vector2(0.0, 0.5)]), 10, false, false)
			b.add_light(sc, RYFT_RUNE, 8.0, 1.2, false)
		"crown":
			m.mat(L.ASHLAR, stone, 0.6)
			m.lathe(g, PackedVector2Array([Vector2(3.0, -0.4), Vector2(3.0, 0.35), Vector2(2.6, 0.35), Vector2(2.6, 0.7), Vector2(0.0, 0.7)]), 20, false, false)
			for k in 7:
				var a := TAU * k / 7.0
				var p := g + Vector3(cos(a), 0, sin(a)) * 6.5
				p.y = b.ground(p)
				_column(b, p, 4.2, 0.36, false, rng, stone)
				m.mat(L.EMBER, RYFT_RUNE, 0.0)
				m.lathe(p + Vector3(0, 4.45, 0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.25, 0.3), Vector2(0.18, 0.9), Vector2(0.0, 1.3)]), 6, false, false, rng.randf())
				b.add_light(p + Vector3(0, 5.2, 0), RYFT_RUNE, 7.0, 0.9, false)
		"refuge":
			# A driftwood lean-to with a sailcloth roof and a camp.
			var wood := Color(0.75, 0.72, 0.66)
			m.mat(L.TIMBER, wood, 0.6)
			for x: float in [-2.0, 0.0, 2.0]:
				m.cylinder(g + Vector3(x, -0.3, -1.5), g + Vector3(x, 2.6, -1.5), 0.12, 0.1, 6)
				m.cylinder(g + Vector3(x, -0.3, 1.5), g + Vector3(x, 1.6, 1.5), 0.11, 0.1, 6)
			m.beam(g + Vector3(-2.4, 2.55, -1.5), g + Vector3(2.4, 2.55, -1.5), 0.16, 0.16)
			m.beam(g + Vector3(-2.4, 1.55, 1.5), g + Vector3(2.4, 1.55, 1.5), 0.16, 0.16)
			m.mat(L.BOARDS, wood, 0.7)
			for k in 9:
				var x := -2.2 + k * 0.55
				m.box(g + Vector3(x, 0.9, -1.62), Vector3(0.5, 2.0, 0.06), 1)
			b.detail.mat(L.LINEN, Color(0.82, 0.78, 0.68), 0.5)
			var a0 := g + Vector3(-2.6, 2.7, -1.7)
			var a1 := g + Vector3(2.6, 2.7, -1.7)
			var c0 := g + Vector3(-2.6, 1.6, 1.9)
			var c1 := g + Vector3(2.6, 1.6, 1.9)
			b.detail.quad(a0, a1, c1, c0, Vector2(0, 0), Vector2(5.2, 0), Vector2(5.2, 3.8), Vector2(0, 3.8))
			b.detail.quad(c0, c1, a1, a0, Vector2(0, 0), Vector2(5.2, 0), Vector2(5.2, 3.8), Vector2(0, 3.8))
			var fire := g + Vector3(0.5, 0, 4.0)
			fire.y = b.ground(fire)
			_rubble(b, fire, 0.7, 8, rng, Color(0.5, 0.48, 0.5), 0.2)
			b.detail.mat(L.EMBER, Color(1, 1, 1), 0.0)
			b.detail.lathe(fire, PackedVector2Array([Vector2(0.45, 0.0), Vector2(0.0, 0.12)]), 8, false, false)
			b.add_fire(fire + Vector3(0, 0.12, 0), 0.9, 8.0, 1.8)
			VillageProps.crate(b.detail, g + Vector3(-1.4, 0, -0.6), 0.6, 0.3)
			VillageProps.barrel(b.detail, g + Vector3(1.3, 0, -0.8), 0.9, 0.32, 0.2)
			VillageProps.bench(b.detail, fire + Vector3(0, 0, -1.3), 1.4, 0.0)
