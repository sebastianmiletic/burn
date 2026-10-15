class_name VillageGreen
extends RefCounted
## The village green and its ways: a cobbled square round the well, market
## stalls, lamp posts, a signpost, cobbled paths to every door and out to the
## roads, and the yard props planned by VillagePlan. Worker thread.

const L = ArchMaterials.L


static func build(b: ArchBuild, spec: Dictionary) -> void:
	var st: Dictionary = spec["style"]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 3))
	var center: Vector3 = (spec["at"] as Vector3) - b.origin
	var ground := center.y
	var wood: Color = st.get("timber", Color(0.5, 0.4, 0.3))
	var stone: Color = st.get("stone", Color(0.95, 0.92, 0.86))
	var roof_layer := L.SHINGLE if (st["roofs"] as Array).has("shingle") else L.THATCH
	# Cobbled square with a ragged edge.
	_square(b, center, 8.6, rng)
	VillageProps.well(b, center, roof_layer, st.get("roof_tint", Color(1, 1, 1)), stone, wood)
	far(b, spec)
	# Market stalls on the north-west side, facing the well.
	var awnings := [[Color(0.75, 0.2, 0.15), Color(0.9, 0.86, 0.75)], [Color(0.2, 0.35, 0.55), Color(0.9, 0.86, 0.75)], [Color(0.4, 0.5, 0.2), Color(0.88, 0.8, 0.5)]]
	for k in 3:
		var a := deg_to_rad(205.0 + k * 50.0)
		var p := center + Vector3(cos(a), 0, sin(a)) * 7.2
		var yaw := atan2(-cos(a), -sin(a))
		var cols: Array = awnings[k % awnings.size()]
		VillageProps.stall(b, p, yaw, rng, cols[0], cols[1])
	# Lamp posts round the edge of the square, clear of the paths.
	var path_angles: Array[float] = []
	for p: Array in spec.get("paths", []):
		var pts: PackedVector2Array = p[0]
		for q in [pts[0], pts[pts.size() - 1]]:
			var rel := Vector2(q.x - b.origin.x - center.x, q.y - b.origin.z - center.z)
			if rel.length() < 11.0:
				path_angles.append(rel.angle())
	var lamps := 0
	for k in 12:
		var a := deg_to_rad(15.0 + k * 30.0)
		var clear := lamps < 5
		for pa in path_angles:
			if absf(angle_difference(a, pa)) < deg_to_rad(16.0):
				clear = false
		if absf(angle_difference(a, deg_to_rad(255.0))) < deg_to_rad(40.0):
			clear = false  # behind the stalls
		if not clear:
			continue
		lamps += 1
		var p := center + Vector3(cos(a), 0, sin(a)) * 9.3
		VillageProps.lamp_post(b, p, atan2(-cos(a), -sin(a)))
	# Paths to the doors and out to the roads (planned in VillagePlan.finish);
	# the signpost points along the roads.
	for p: Array in spec.get("paths", []):
		var pts: Array = []
		for q: Vector2 in (p[0] as PackedVector2Array):
			pts.append(Vector3(q.x - b.origin.x, 0.0, q.y - b.origin.z))
		_path(b, pts, float(p[1]), rng)
	var road_dirs: Array = []
	for e: Vector2 in spec.get("road_ends", []):
		road_dirs.append(Vector3(e.x - b.origin.x - center.x, 0, e.y - b.origin.z - center.z).normalized())
	if not road_dirs.is_empty():
		var main: Vector3 = road_dirs[0]
		var side := Vector3(-main.z, 0, main.x)
		VillageProps.signpost(b, center + main * 9.4 + side * 1.6, road_dirs)
	palisade(b, spec, rng)
	docks(b, spec, rng)
	# Yard props.
	for item: Dictionary in spec.get("items", []):
		var p: Vector3 = (item["pos"] as Vector3) - b.origin
		p.y = b.ground(p)
		var yaw: float = item.get("yaw", 0.0)
		match String(item["prop"]):
			"barrels":
				VillageProps.barrel(b.detail, p + Basis(Vector3.UP, yaw) * Vector3(-0.3, 0, 0), 0.95, 0.34, rng.randf() * TAU)
				VillageProps.barrel(b.detail, p + Basis(Vector3.UP, yaw) * Vector3(0.38, 0, 0.05), 0.95, 0.34, rng.randf() * TAU)
				if rng.randf() < 0.5:
					VillageProps.crate(b.detail, p + Basis(Vector3.UP, yaw) * Vector3(0.0, 0, 0.55), 0.5, yaw + 0.3)
			"bench":
				VillageProps.bench(b.detail, p, 1.5, yaw, true)
			"woodpile":
				VillageProps.woodpile(b.detail, p, 1.6, yaw, 4)
			"cart":
				VillageProps.cart(b, p, yaw, rng)
			"hay":
				VillageProps.hay_bale(b.detail, p, yaw + rng.randf_range(-0.3, 0.3))
			"garden":
				VillageProps.garden(b, p, item.get("size", Vector2(4, 3)), yaw, rng)


static func _square(b: ArchBuild, center: Vector3, radius: float, rng: RandomNumberGenerator) -> void:
	var m := b.shell
	m.mat(L.COBBLE, Color(0.95, 0.92, 0.88), 0.4, 1.0)
	var rings := 6
	var segs := 40
	var edge := PackedFloat32Array()
	for s in segs:
		edge.append(radius + rng.randf_range(-0.7, 0.4))
	var pt := func(ring: int, s: int) -> Vector3:
		var f := float(ring) / rings
		var r := lerpf(1.3, edge[s % segs], f)
		var a := TAU * float(s) / segs
		var q := center + Vector3(cos(a) * r, 0, sin(a) * r)
		q.y = b.ground(q) + 0.035
		return q
	for ring in rings:
		for s in segs:
			var a0: Vector3 = pt.call(ring, s)
			var a1: Vector3 = pt.call(ring, s + 1)
			var b1: Vector3 = pt.call(ring + 1, s + 1)
			var b0: Vector3 = pt.call(ring + 1, s)
			m.quad(a0, a1, b1, b0, Vector2(a0.x, a0.z), Vector2(a1.x, a1.z), Vector2(b1.x, b1.z), Vector2(b0.x, b0.z), Vector3.UP)
	# Kerb stones along the ragged edge.
	m.mat(L.ASHLAR, Color(0.8, 0.78, 0.74), 0.5)
	for s in segs:
		var a: Vector3 = pt.call(rings, s)
		var c: Vector3 = pt.call(rings, s + 1)
		var mid := (a + c) * 0.5
		var dir := (c - a)
		m.push(Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z) + PI * 0.5), mid + Vector3(0, -0.02, 0)))
		m.box(Vector3.ZERO, Vector3(dir.length() * 0.95, 0.12, 0.22), 0)
		m.pop()


## A cobbled path ribbon along node-space points, hugging the ground, with
## kerb stones down both edges.
static func _path(b: ArchBuild, pts: Array, width: float, rng: RandomNumberGenerator) -> void:
	var m := b.shell
	var dense: Array[Vector3] = []
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var c: Vector3 = pts[i + 1]
		var n := maxi(1, int(Vector2(c.x - a.x, c.z - a.z).length() / 0.6))
		for k in n:
			dense.append(a.lerp(c, float(k) / n))
	dense.append(pts[pts.size() - 1])
	if dense.size() < 2:
		return
	var left: Array[Vector3] = []
	var right: Array[Vector3] = []
	for i in dense.size():
		var p := dense[i]
		var t := (dense[mini(i + 1, dense.size() - 1)] - dense[maxi(i - 1, 0)])
		t.y = 0.0
		t = t.normalized()
		var side := Vector3(-t.z, 0, t.x)
		var hw := width * 0.5 * (1.0 + rng.randf_range(-0.08, 0.08))
		var l := p + side * hw
		var r := p - side * hw
		l.y = b.ground(l) + 0.04
		r.y = b.ground(r) + 0.04
		left.append(l)
		right.append(r)
	m.mat(L.COBBLE, Color(0.92, 0.9, 0.86), 0.5, 1.0)
	var run := 0.0
	for i in dense.size() - 1:
		var step := Vector2(dense[i + 1].x - dense[i].x, dense[i + 1].z - dense[i].z).length()
		m.quad(left[i], left[i + 1], right[i + 1], right[i], Vector2(0, -run), Vector2(0, -run - step), Vector2(width, -run - step), Vector2(width, -run), Vector3.UP)
		run += step
	m.mat(L.ASHLAR, Color(0.78, 0.76, 0.72), 0.5)
	for i in range(0, dense.size() - 1):
		for edge: Array in [left, right]:
			var a: Vector3 = edge[i]
			var c: Vector3 = edge[i + 1]
			var dir := c - a
			if dir.length() < 0.05:
				continue
			m.push(Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), (a + c) * 0.5 + Vector3(0, -0.015, 0)))
			m.box(Vector3.ZERO, Vector3(0.18, 0.1, dir.length() * 0.92), 2)
			m.pop()


## Sharpened-log palisade or drystone wall round the village, with gateways
## where the roads come in.
static func palisade(b: ArchBuild, spec: Dictionary, rng: RandomNumberGenerator) -> void:
	var pal: Dictionary = spec.get("palisade", {})
	if pal.is_empty():
		return
	var center: Vector3 = (spec["at"] as Vector3) - b.origin
	var r: float = pal["r"]
	var gates: Array = pal["gates"]
	var stone := String(pal["kind"]) == "stone"
	var st: Dictionary = spec["style"]
	var wood: Color = st.get("timber", Color(0.5, 0.4, 0.3)) * Color(1.1, 1.05, 1.0)
	var m := b.shell
	var step := 0.4 if not stone else 0.9
	var n := int(TAU * r / step)
	var prev := Vector3.INF
	for i in n:
		var a := TAU * i / n
		var gate := false
		for ga: float in gates:
			if absf(angle_difference(a, ga)) * r < 2.6:
				gate = true
		var p := center + Vector3(cos(a), 0, sin(a)) * r
		p.y = b.ground(p)
		if gate:
			prev = Vector3.INF
			continue
		if stone:
			if prev != Vector3.INF:
				var dir := p - prev
				var mid := (p + prev) * 0.5
				m.mat(L.RUBBLE, st.get("stone", Color(0.6, 0.58, 0.55)), 0.6)
				m.push(Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), mid))
				m.box(Vector3(0, 0.7, 0), Vector3(1.0, 3.2, Vector2(dir.x, dir.z).length() + 0.02), 2)
				m.mat(L.ASHLAR, st.get("stone", Color(0.6, 0.58, 0.55)) * Color(1.1, 1.08, 1.05), 0.4)
				m.box(Vector3(0, 2.38, 0), Vector3(1.2, 0.16, Vector2(dir.x, dir.z).length() + 0.04), 2)
				m.pop()
			prev = p
			continue
		var h := 3.1 + rng.randf_range(-0.25, 0.35)
		var rr := rng.randf_range(0.15, 0.2)
		var lean := Vector3(rng.randf_range(-0.04, 0.04), 1.0, rng.randf_range(-0.04, 0.04)).normalized()
		m.mat(L.TIMBER, wood * Color(rng.randf_range(0.85, 1.1), 1.0, 1.0), 0.6)
		m.cylinder(p - Vector3(0, 0.6, 0), p + lean * h, rr, rr * 0.9, 6)
		m.cylinder(p + lean * h, p + lean * (h + 0.45), rr * 0.9, 0.0, 6, false)
		if i % 6 == 0 and prev != Vector3.INF:
			pass
		prev = p
	# Rails on the inside, tying the logs together.
	if not stone:
		m.mat(L.TIMBER, wood * Color(0.85, 0.8, 0.75), 0.6)
		var segs := int(TAU * r / 2.4)
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var skip := false
			for ga: float in gates:
				if absf(angle_difference((a0 + a1) * 0.5, ga)) * r < 3.6:
					skip = true
			if skip:
				continue
			for y: float in [1.1, 2.5]:
				var p0 := center + Vector3(cos(a0), 0, sin(a0)) * (r - 0.3)
				var p1 := center + Vector3(cos(a1), 0, sin(a1)) * (r - 0.3)
				p0.y = b.ground(p0) + y
				p1.y = b.ground(p1) + y
				m.beam(p0, p1, 0.14, 0.12, Vector3.UP, 0.01)
	# Gateways: tall posts, a lintel with a lantern, the gates swung open.
	for ga: float in gates:
		var d := Vector3(cos(ga), 0, sin(ga))
		var side := Vector3(-d.z, 0, d.x)
		var gp := center + d * r
		gp.y = b.ground(gp)
		for s: float in [-1.0, 1.0]:
			var q := gp + side * s * 2.45
			q.y = b.ground(q)
			if stone:
				m.mat(L.ASHLAR, st.get("stone", Color(0.6, 0.58, 0.55)), 0.5)
				m.push(Transform3D(Basis(Vector3.UP, atan2(d.x, d.z)), q))
				m.box(Vector3(0, 1.2, 0), Vector3(1.3, 4.0, 1.3), 1)
				m.box(Vector3(0, 3.3, 0), Vector3(1.5, 0.25, 1.5), 1)
				m.pop()
			else:
				m.mat(L.TIMBER, wood * Color(0.8, 0.75, 0.7), 0.6)
				m.cylinder(q - Vector3(0, 0.6, 0), q + Vector3(0, 4.4, 0), 0.26, 0.24, 8)
				# Open gate leaf, swung inwards against the palisade.
				var hinge := q - side * s * 0.25
				var leaf_dir := (-d * 0.8 + side * s * 0.6).normalized()
				m.mat(L.TIMBER, wood, 0.6)
				for k in 5:
					var bpos := hinge + leaf_dir * (0.22 + k * 0.42)
					bpos.y = q.y
					m.cylinder(bpos - Vector3(0, 0.2, 0), bpos + Vector3(0, 2.8, 0), 0.15, 0.15, 6)
				m.beam(hinge + Vector3(0, 0.6, 0), hinge + leaf_dir * 2.1 + Vector3(0, 0.6, 0), 0.14, 0.14)
				m.beam(hinge + Vector3(0, 2.2, 0), hinge + leaf_dir * 2.1 + Vector3(0, 2.2, 0), 0.14, 0.14)
		var top := gp + Vector3(0, 4.2 if not stone else 3.5, 0)
		m.mat(L.TIMBER if not stone else L.ASHLAR, wood * Color(0.8, 0.75, 0.7) if not stone else st.get("stone", Color(0.6, 0.58, 0.55)), 0.6)
		m.beam(top - side * 3.0, top + side * 3.0, 0.4, 0.4, Vector3.UP, 0.04)
		VillageProps.lamp_post(b, gp + side * 3.2 - d * 0.6, atan2(-side.x, -side.z))


## Mirewatch's pier: a plank deck on posts with a rail, mooring posts, a
## rowboat and a net-drying rack.
static func docks(b: ArchBuild, spec: Dictionary, rng: RandomNumberGenerator) -> void:
	var dk: Dictionary = spec.get("docks", {})
	if dk.is_empty():
		return
	var s2: Vector2 = dk["start"]
	var e2: Vector2 = dk["end"]
	var deck: float = float(dk["deck"]) - b.origin.y
	var a := Vector3(s2.x - b.origin.x, 0, s2.y - b.origin.z)
	var e := Vector3(e2.x - b.origin.x, 0, e2.y - b.origin.z)
	var dir := (e - a).normalized()
	var side := Vector3(-dir.z, 0, dir.x)
	var length := a.distance_to(e)
	var wood := Color(0.55, 0.5, 0.43)
	var m := b.shell
	# Where the land is higher than the deck, the boardwalk starts further out.
	var t0 := 0.0
	while t0 < length and b.ground(a + dir * t0) > deck - 0.15:
		t0 += 0.5
	# A short ramp of planks down from the bank.
	var bank := a + dir * maxf(0.0, t0 - 2.0)
	bank.y = b.ground(bank) + 0.05
	var deck0 := a + dir * t0
	deck0.y = deck
	m.mat(L.FLOOR, wood, 0.8)
	m.quad(bank - side * 1.1, bank + side * 1.1, deck0 + side * 1.1, deck0 - side * 1.1, Vector2(0, 0), Vector2(2.2, 0), Vector2(2.2, -2.0), Vector2(0, -2.0), Vector3.UP)
	var t := t0
	while t < length:
		var p := a + dir * t
		p.y = deck
		var plank_len := minf(2.0, length - t)
		m.mat(L.FLOOR, wood * Color(rng.randf_range(0.85, 1.1), 1, 1), 0.8)
		m.push(Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), p + dir * plank_len * 0.5 + Vector3(0, -0.04, 0)))
		m.box(Vector3.ZERO, Vector3(2.3, 0.08, plank_len - 0.02), 0)
		m.pop()
		# Posts and bearers.
		m.mat(L.TIMBER, wood * Color(0.7, 0.66, 0.6), 0.9)
		for s: float in [-1.05, 1.05]:
			var q := p + side * s
			m.cylinder(Vector3(q.x, b.ground(q) - 0.5, q.z), q + Vector3(0, -0.05 + (0.9 if s > 0.0 else 0.0), 0), 0.12, 0.11, 6)
		m.beam(p - side * 1.15 + Vector3(0, -0.15, 0), p + side * 1.15 + Vector3(0, -0.15, 0), 0.14, 0.16, Vector3.UP)
		# Rail on one side.
		var nxt := minf(t + 2.0, length)
		m.beam(p + side * 1.05 + Vector3(0, 0.85, 0), a + dir * nxt + side * 1.05 + Vector3(0, deck + 0.85, 0), 0.07, 0.09, Vector3.UP)
		t += 2.0
	# Mooring posts at the end and a rowboat tied alongside.
	m.mat(L.TIMBER, wood * Color(0.6, 0.55, 0.5), 0.9)
	for s: float in [-1.0, 1.0]:
		var q := e + side * s * 1.1
		m.cylinder(Vector3(q.x, b.ground(q) - 0.5, q.z), Vector3(q.x, deck + 0.7, q.z), 0.16, 0.14, 7)
	var boat := e - dir * 3.0 - side * 2.6
	boat.y = float(WorldGen.SEA_LEVEL) + 0.85 - b.origin.y
	_rowboat(b, boat, atan2(dir.x, dir.z))
	# Drying rack with nets on the bank.
	var rack := a - side * 3.0 + dir * 0.5
	rack.y = b.ground(rack)
	m.mat(L.TIMBER, wood, 0.7)
	for s: float in [-1.4, 1.4]:
		m.cylinder(rack + dir * s, rack + dir * s + Vector3(0, 2.0, 0), 0.07, 0.06, 6)
	m.beam(rack - dir * 1.5 + Vector3(0, 1.95, 0), rack + dir * 1.5 + Vector3(0, 1.95, 0), 0.08, 0.08)
	b.detail.mat(L.LINEN, Color(0.45, 0.42, 0.36), 0.6)
	b.detail.quad(rack - dir * 1.3 + Vector3(0, 1.9, 0), rack + dir * 1.3 + Vector3(0, 1.9, 0), rack + dir * 1.2 + side * 0.15 + Vector3(0, 0.6, 0), rack - dir * 1.2 + side * 0.15 + Vector3(0, 0.6, 0),
			Vector2(0, 0), Vector2(2.6, 0), Vector2(2.4, 1.3), Vector2(0.1, 1.3))
	b.detail.quad(rack + dir * 1.3 + Vector3(0, 1.9, 0) - side * 0.01, rack - dir * 1.3 + Vector3(0, 1.9, 0) - side * 0.01, rack - dir * 1.2 + side * 0.14 + Vector3(0, 0.6, 0), rack + dir * 1.2 + side * 0.14 + Vector3(0, 0.6, 0),
			Vector2(0, 0), Vector2(2.6, 0), Vector2(2.4, 1.3), Vector2(0.1, 1.3))
	VillageProps.barrel(b.detail, Vector3(a.x, b.ground(a), a.z) + side * 1.8, 0.9, 0.32, 0.3)
	VillageProps.crate(b.detail, Vector3(a.x, b.ground(a), a.z) + side * 1.9 + dir * 0.8, 0.6, 0.5)


static func _rowboat(b: ArchBuild, p: Vector3, yaw: float) -> void:
	var m := b.shell
	m.push(Transform3D(Basis(Vector3.UP, yaw), p))
	var wood := Color(0.5, 0.42, 0.34)
	var length := 3.6
	var section := func(z: float, t: float, s: float) -> Vector3:
		var f := clampf(z / (length * 0.5), -1.0, 1.0)
		var w := 0.7 * sqrt(maxf(0.0, 1.0 - pow(absf(f), 2.2)))
		var ang := t * PI * 0.5
		return Vector3(s * w * sin(ang), -0.45 * cos(ang) + 0.1 * f * f, z)
	m.mat(L.BOARDS, wood, 0.6)
	var nz := 10
	for s: float in [-1.0, 1.0]:
		for k in 4:
			var t0 := float(k) / 4.0
			var t1 := float(k + 1) / 4.0
			for i in nz:
				var z0 := -length * 0.5 + length * float(i) / nz
				var z1 := -length * 0.5 + length * float(i + 1) / nz
				var q0: Vector3 = section.call(z0, t0, s)
				var q1: Vector3 = section.call(z1, t0, s)
				var q2: Vector3 = section.call(z1, t1, s)
				var q3: Vector3 = section.call(z0, t1, s)
				var nrm := (q1 - q0).cross(q3 - q0).normalized()
				if nrm.dot(Vector3(s, -0.5, 0)) < 0.0:
					nrm = -nrm
				m.quad(q0, q1, q2, q3, Vector2(z0, -t0), Vector2(z1, -t0), Vector2(z1, -t1), Vector2(z0, -t1), nrm)
				m.quad(q3 - nrm * 0.03, q2 - nrm * 0.03, q1 - nrm * 0.03, q0 - nrm * 0.03, Vector2(z0, -t1), Vector2(z1, -t1), Vector2(z1, -t0), Vector2(z0, -t0), -nrm)
	m.mat(L.TIMBER, wood * Color(0.8, 0.75, 0.7), 0.5)
	for z: float in [-0.6, 0.5]:
		m.box(Vector3(0, -0.12, z), Vector3(1.2, 0.05, 0.25), 0)
	m.beam(Vector3(0.3, -0.05, -0.2), Vector3(1.3, 0.05, 1.2), 0.06, 0.03)
	m.pop()


## The distant silhouette of the green: the well and the palisade ring.
static func far(b: ArchBuild, spec: Dictionary) -> void:
	var center: Vector3 = (spec["at"] as Vector3) - b.origin
	var st: Dictionary = spec["style"]
	var m := b.far
	m.mat(L.RUBBLE, st.get("stone", Color(0.9, 0.88, 0.85)), 0.3)
	m.lathe(center, PackedVector2Array([Vector2(1.3, 0.0), Vector2(1.3, 0.9), Vector2(0.0, 0.9)]), 8, false, false)
	var pal: Dictionary = spec.get("palisade", {})
	if pal.is_empty():
		return
	var r: float = pal["r"]
	var stone := String(pal["kind"]) == "stone"
	if stone:
		m.mat(L.RUBBLE, st.get("stone", Color(0.6, 0.58, 0.55)), 0.4)
	else:
		m.mat(L.TIMBER, st.get("timber", Color(0.5, 0.4, 0.3)), 0.5)
	var h := 2.3 if stone else 3.3
	var n := 32
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := center + Vector3(cos(a0), 0, sin(a0)) * r
		var p1 := center + Vector3(cos(a1), 0, sin(a1)) * r
		p0.y = b.ground(p0) - 0.5
		p1.y = b.ground(p1) - 0.5
		var nrm := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
		m.quad(p0, p1, p1 + Vector3(0, h + 0.5, 0), p0 + Vector3(0, h + 0.5, 0), Vector2(0, 0), Vector2(6, 0), Vector2(6, -h), Vector2(0, -h), nrm)
		m.quad(p1, p0, p0 + Vector3(0, h + 0.5, 0), p1 + Vector3(0, h + 0.5, 0), Vector2(0, 0), Vector2(6, 0), Vector2(6, -h), Vector2(0, -h), -nrm)
