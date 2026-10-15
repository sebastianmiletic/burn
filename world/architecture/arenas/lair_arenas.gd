class_name LairArenas
extends RefCounted
## Modelled lairs (Lairs blueprints): the Drowned Spire (Leviathan), the
## Broodmother's webbed cavern and Hagsfen (Old Mother Mire). Centre-relative
## coordinates, floor top at y = 0.

const K := preload("res://world/architecture/arenas/arena_kit.gd")
const P := preload("res://world/architecture/arenas/arena_pieces.gd")

const SEA_STONE := Color(0.62, 0.64, 0.6)
const WITCH := Color(0.45, 1.0, 0.35)
const EGG := Color(0.75, 0.95, 0.35)


static func _local(b: ArenaBuild) -> void:
	for kit: K in [b.shell, b.detail]:
		kit.push(Transform3D(Basis.IDENTITY, b.center))
		kit.ao_floor = 0.0
	b.web.push(Transform3D(Basis.IDENTITY, b.center))
	b.web.raw = true


# --- Shared organic pieces ----------------------------------------------------------

## A gnarled dead tree: a twisting trunk splitting into crooked branches.
static func dead_tree(k: K, at: Vector3, h: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	k.mat(K.BARK, Color(0.42, 0.38, 0.34), 0.6)
	_branch(k, rng, at + Vector3(0, -0.4, 0), Vector3(rng.randf_range(-0.2, 0.2), 1, rng.randf_range(-0.2, 0.2)).normalized(), h * 0.55, h * 0.045, 0)
	# roots
	for i in 5:
		var a := TAU * i / 5.0 + rng.randf() * 0.5
		var dir := Vector3(cos(a), -0.35, sin(a)).normalized()
		var path := K.bezier(at + Vector3(0, 0.5, 0), at + dir * 0.9 + Vector3(0, 0.2, 0), at + dir * 1.8 + Vector3(0, -0.4, 0), 6)
		var r := PackedFloat32Array()
		for j in path.size():
			r.append(lerpf(h * 0.035, 0.03, float(j) / (path.size() - 1)))
		k.sweep(path, r, 6)


static func _branch(k: K, rng: RandomNumberGenerator, from: Vector3, dir: Vector3, length: float, radius: float, depth: int) -> void:
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	var steps := 6
	var p := from
	var d := dir
	for i in steps + 1:
		path.append(p)
		radii.append(lerpf(radius, radius * 0.55, float(i) / steps))
		d = (d + Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.1, 0.25), rng.randf_range(-0.35, 0.35))).normalized()
		p += d * length / steps
	k.sweep(path, radii, 7 if depth == 0 else 5)
	if depth >= 3 or radius < 0.03:
		return
	var n := rng.randi_range(2, 3)
	for i in n:
		var at := path[rng.randi_range(steps / 2, steps)]
		var nd := (d + Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.1, 0.6), rng.randf_range(-1.0, 1.0))).normalized()
		_branch(k, rng, at, nd, length * rng.randf_range(0.5, 0.7), radius * 0.55, depth + 1)


## Weathered standing stone (an irregular monolith), optionally rune-carved.
static func monolith(k: K, at: Vector3, h: float, yaw: float, seed_value: int, runes: bool, tint := Color(0.55, 0.56, 0.52)) -> void:
	k.push_at(at, yaw)
	k.mat(K.TRI + K.GRANITE, tint, 0.45)
	k.rock(Vector3(0, h * 0.48, 0), Vector3(0.75, h * 0.52, 0.45), 0.18, 3, seed_value, 0.95, 0.35)
	if runes:
		k.mat(K.GLOW, WITCH, 1.0, 2.0)
		for j in 4:
			var y := h * (0.3 + j * 0.15)
			k.beam(Vector3(-0.2, y, 0.47), Vector3(0.18, y + 0.12, 0.47), 0.05, 0.02, 0.0)
			k.beam(Vector3(0.0, y - 0.1, 0.48), Vector3(0.0, y + 0.18, 0.48), 0.05, 0.02, 0.0)
	k.pop()


# --- The Drowned Spire ------------------------------------------------------------

static func spire(b: ArenaBuild) -> void:
	var pr := b.prop
	b.params = {"moss": 0.55, "grime": 0.5, "grime_color": Color(0.26, 0.3, 0.26), "outdoor": 1.0}
	_local(b)
	var k := b.shell
	var d := b.detail
	var away: Vector3 = pr["away"]
	# Platform: concentric rings of worn flagstones and a compass rose.
	k.ao_floor = -INF
	var r := 2.4
	var ring := 0
	while r < 16.0:
		var w := minf(2.0, 16.4 - r)
		var n := int(TAU * (r + w * 0.5) / 1.9)
		var off := k.rng.randf() * TAU
		for i in n:
			var a0 := off + TAU * i / n + 0.01
			var a1 := off + TAU * (i + 1) / n - 0.01
			if k.rng.randf() < 0.04:
				continue
			k.mat(K.LIMESTONE if (i + ring) % 5 else K.MOSSY_WALL, SEA_STONE * (1.0 + k.rng.randf_range(-0.1, 0.08)), 0.45)
			var hh := k.rng.randf_range(-0.04, 0.02)
			k.lathe(PackedVector2Array([Vector2(r + 0.025, -0.35), Vector2(r + 0.025, hh), Vector2(r + w - 0.025, hh), Vector2(r + w - 0.025, -0.35)]), 3, a0, a1)
		r += w
		ring += 1
	k.mat(K.MARBLE, Color(0.55, 0.55, 0.52), 0.4)
	k.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(2.4, 0.0), Vector2(2.4, -0.35)]), 32)
	k.mat(K.MARBLE, Color(0.2, 0.22, 0.24), 0.4)
	for i in 8:
		var a := TAU * i / 8.0
		var l := 2.3 if i % 2 == 0 else 1.4
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		k.ptri(dir * l + Vector3(0, 0.012, 0), side * 0.3 + Vector3(0, 0.012, 0), -side * 0.3 + Vector3(0, 0.012, 0), Vector3.UP)
	k.ao_floor = 0.0
	# The old foundation wall rising from the sea, weed and barnacles at the waterline.
	k.mat(K.MOSSY_WALL, SEA_STONE * Color(0.8, 0.85, 0.8), 0.3)
	k.lathe(PackedVector2Array([Vector2(17.6, -4.5), Vector2(16.8, -1.2), Vector2(16.6, 0.0), Vector2(16.0, 0.0)]), 72, 0.0, TAU, 0.02)
	d.mat(K.TRI + K.ROCK, Color(0.3, 0.33, 0.28), 0.6)
	for i in 40:
		var a := d.rng.randf() * TAU
		d.rock(Vector3(cos(a), 0, sin(a)) * 17.3 + Vector3(0, -2.3 + d.rng.randf_range(-0.4, 0.4), 0), Vector3(0.6, 0.25, 0.5) * d.rng.randf_range(0.6, 1.3), 0.4, 1, i)
	# Balustrade: balusters and a rail where the blueprint has collision.
	var rail: PackedByteArray = pr["rail"]
	for i in 72:
		if rail[i] == 0:
			continue
		var a0 := TAU * float(i) / 72.0 - TAU / 144.0
		var a1 := a0 + TAU / 72.0
		k.mat(K.LIMESTONE, SEA_STONE, 0.45)
		k.lathe(PackedVector2Array([Vector2(15.55, 0.0), Vector2(15.55, 0.25), Vector2(16.45, 0.25), Vector2(16.45, 0.0)]), 2, a0, a1)
		if k.rng.randf() < 0.85:
			k.lathe(PackedVector2Array([Vector2(15.6, 0.95), Vector2(15.6, 1.1), Vector2(16.4, 1.1), Vector2(16.4, 0.95)]), 2, a0, a1)
		for j in 2:
			var a := lerpf(a0, a1, 0.25 + j * 0.5)
			k.push(Transform3D(Basis.IDENTITY, Vector3(cos(a), 0, sin(a)) * 16.0))
			k.lathe(PackedVector2Array([Vector2(0.12, 0.25), Vector2(0.17, 0.4), Vector2(0.1, 0.6), Vector2(0.14, 0.8), Vector2(0.1, 0.95)]), 8)
			k.pop()
	# Columns: standing (some snapped), stubs, fallen drums.
	for col: Array in pr["columns"]:
		var at: Vector3 = col[0]
		var a := float(col[1])
		var kind := int(col[2])
		var h := float(col[3])
		k.mat(K.MARBLE, Color(0.7, 0.72, 0.68), 0.35)
		if kind == 0:
			var along := Vector3(-sin(a), 0, cos(a))
			for s in 4:
				var p := at + along * (s * 1.15 + 0.3)
				k.push(Transform3D(Basis(Vector3.UP, atan2(along.x, along.z) + k.rng.randf_range(-0.15, 0.15)) * Basis(Vector3.RIGHT, PI / 2.0), p + Vector3(0, 0.82, 0)))
				k.lathe(PackedVector2Array([Vector2(0.82, -0.52), Vector2(0.84, 0.52)]), 14)
				k.lathe(PackedVector2Array([Vector2(0.84, 0.52), Vector2(0.0, 0.53)]), 14)
				k.lathe(PackedVector2Array([Vector2(0.0, -0.53), Vector2(0.82, -0.52)]), 14)
				k.pop()
			P.rubble(d, at + along * 2.0, 2.2, 10, K.MARBLE, Color(0.7, 0.72, 0.68))
		elif h >= 8.0:
			k.column(at, h + 1.0, 0.85, "fluted", 0.0, 16)
		else:
			k.column(at, maxf(h, 1.2), 0.85, "fluted", 0.92 if h > 1.5 else 0.5, 16)
			if h > 1.5:
				P.rubble(d, at + Vector3(k.rng.randf_range(-2, 2), 0, k.rng.randf_range(-2, 2)), 1.6, 6, K.MARBLE, Color(0.7, 0.72, 0.68))
	# The drowned tower.
	var tc: Vector3 = pr["tower"]
	var tb := float(pr["tower_base"])
	var th := float(pr["tower_h"])
	P.round_tower(k, Vector3(tc.x, tb, tc.z), 5.5, th - tb, true, false, K.MOSSY_WALL, SEA_STONE * Color(0.85, 0.88, 0.85))
	k.mat(K.PLANKS, Color(0.4, 0.34, 0.28), 0.6)
	for fy: float in [4.0, 12.0, 20.0]:
		k.lathe(PackedVector2Array([Vector2(0.0, fy), Vector2(4.6, fy), Vector2(4.6, fy - 0.25)]), 16, 0.3, 4.9)
	k.mat(K.DARK, Color(0.03, 0.03, 0.03), 0.4)
	for i in 10:
		var a := TAU * float(i) / 10.0
		var y := 6.5 + (i % 3) * 7.0
		k.push(Transform3D(Basis(Vector3.UP, -a + PI / 2.0), Vector3(tc.x, 0, tc.z) + Vector3(cos(a), 0, sin(a)) * 5.52))
		k.box(Vector3(0, y, 0), Vector3(1.1, 1.9, 0.05), 0.0)
		k.pop()
	b.light(b.center + Vector3(tc.x, 13.0, tc.z), Color(1.0, 0.7, 0.4), 2.0, 12.0, 0, 0.3, 1.0)
	b.flame(b.center + Vector3(tc.x, 12.2, tc.z), 0.6, "fire")
	b.flame(b.center + Vector3(tc.x, 20.2, tc.z), 0.6, "fire")
	# Lamp posts.
	for lp: Vector3 in pr["lamps"]:
		d.mat(K.IRON, Color(1, 1, 1), 1.0)
		d.sweep(PackedVector3Array([lp, lp + Vector3(0, 3.2, 0)]), PackedFloat32Array([0.09, 0.06]), 8)
		d.lathe(PackedVector2Array([Vector2(0.3, 0.0), Vector2(0.18, 0.25), Vector2(0.09, 0.5)]), 8, 0.0, TAU)
		d.push(Transform3D(Basis.IDENTITY, lp + Vector3(0, 3.2, 0)))
		d.lathe(PackedVector2Array([Vector2(0.05, 0.0), Vector2(0.22, 0.1), Vector2(0.22, 0.55), Vector2(0.3, 0.6), Vector2(0.05, 0.85)]), 6)
		d.pop()
		b.flame(b.center + lp + Vector3(0, 3.3, 0), 0.4, "fire")
		b.light(b.center + lp + Vector3(0, 3.6, 0), Color(1.0, 0.68, 0.35), 2.0, 11.0, 0, 0.3, 0.8)
	for bz: Vector3 in pr["braziers"]:
		P.fire_basin(b, k, bz, b.center + bz, 0.9, "fire", K.LIMESTONE, Color(1.0, 0.6, 0.3), 1)
	_sea_ribs(d, pr["ribs"], atan2(away.z, away.x))
	TartarusArena._bones(d, pr["bones"], 7)
	if pr.has("causeway"):
		_causeway(b, k, d, pr["causeway"])


static func _sea_ribs(d: K, at: Vector3, yaw: float) -> void:
	d.push_at(at, yaw)
	d.mat(K.BONE, Color(0.82, 0.8, 0.72), 0.7)
	var spine := K.bezier(Vector3(0, 0.0, -9.0), Vector3(0, 1.4, 0.0), Vector3(0, -0.5, 9.0), 18)
	for i in spine.size():
		d.rock(spine[i], Vector3(0.55, 0.45, 0.4), 0.15, 2, i)
		if i % 2 == 1 and i > 1 and i < 17:
			for s: float in [-1.0, 1.0]:
				var p := spine[i]
				var path := K.bezier(p, p + Vector3(s * 3.6, 4.5, 0.3), p + Vector3(s * 4.2, -1.5, 1.2), 10)
				var rr := PackedFloat32Array()
				for j in path.size():
					rr.append(lerpf(0.26, 0.08, float(j) / 10.0))
				d.sweep(path, rr, 7)
	d.pop()


static func _causeway(b: ArenaBuild, k: K, d: K, cw: Dictionary) -> void:
	var a: Vector3 = (cw["from"] as Vector3) - b.center
	var e: Vector3 = (cw["to"] as Vector3) - b.center
	var length := Vector2(a.x, a.z).distance_to(Vector2(e.x, e.z))
	var dir := Vector3(e.x - a.x, 0, e.z - a.z).normalized()
	var side := Vector3(-dir.z, 0, dir.x)
	var deck := a.y
	var gaps: Array = cw["gaps"]
	var yaw := atan2(dir.x, dir.z)
	var in_gap := func(t: float) -> bool:
		for g: float in gaps:
			if absf(t - g) < 1.3:
				return true
		return false
	# Deck slabs, edge kerbs, low walls.
	var t := 0.0
	while t < length:
		var step := k.rng.randf_range(0.9, 1.4)
		var tm := t + step * 0.5
		if not in_gap.call(tm):
			var p := a + dir * tm
			p.y = deck
			k.mat(K.MOSSY_WALL if k.rng.randf() < 0.3 else K.LIMESTONE, SEA_STONE * (1.0 + k.rng.randf_range(-0.12, 0.06)), 0.45)
			k.push(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_euler(Vector3(k.rng.randf_range(-0.02, 0.02), 0, k.rng.randf_range(-0.03, 0.03))), p))
			k.box(Vector3(0, -0.45, 0), Vector3(3.5, 0.9, step - 0.04), 0.05)
			if fmod(tm, 9.0) < 5.0 and tm > 2.0 and tm < length - 2.0:
				for s: float in [-1.0, 1.0]:
					k.mat(K.MOSSY_WALL, SEA_STONE * Color(0.85, 0.9, 0.85), 0.35)
					k.box(Vector3(s * 2.15, 0.45 + k.rng.randf_range(-0.1, 0.05), 0), Vector3(0.75, 0.9, step), 0.08)
			k.pop()
		else:
			# broken deck ends spill rubble into the sea
			P.rubble(d, a + dir * tm + Vector3(0, deck - 2.2, 0), 1.6, 5, K.LIMESTONE, SEA_STONE)
		t += step
	# Piers with arches between them.
	var piers: PackedFloat32Array = cw["piers"]
	for pd in piers:
		var p := a + dir * pd
		k.mat(K.MOSSY_WALL, SEA_STONE * Color(0.8, 0.85, 0.8), 0.32)
		k.push(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, deck, p.z)))
		k.box(Vector3(0, -9.0, 0), Vector3(3.2, 16.0, 2.4), 0.08)
		k.box(Vector3(0, -2.0, 0), Vector3(3.6, 0.5, 2.8), 0.06)
		k.pop()
	for i in piers.size() - 1:
		var mid := (piers[i] + piers[i + 1]) * 0.5
		if in_gap.call(mid):
			continue
		var p := a + dir * mid
		k.mat(K.MOSSY_WALL, SEA_STONE * Color(0.85, 0.88, 0.85), 0.32)
		k.push(Transform3D(Basis(Vector3.UP, yaw + PI / 2.0), Vector3(p.x, deck - 6.6, p.z)))
		k.arch(piers[i + 1] - piers[i] - 2.4, 0.0, 0.8, 2.6, 9, 0.0)
		k.pop()
	# The ruined gateway.
	var g := a + dir * (length * float(cw["gateway"]))
	k.mat(K.MOSSY_WALL, SEA_STONE, 0.32)
	for s: float in [-1.0, 1.0]:
		var p := Vector3(g.x, deck, g.z) + side * s * 2.5
		k.push(Transform3D(Basis(Vector3.UP, yaw), p))
		k.box(Vector3(0, 3.0, 0), Vector3(1.1, 7.0, 1.1), 0.08)
		k.box(Vector3(0, 6.6, 0), Vector3(1.4, 0.4, 1.4), 0.06)
		k.pop()
	k.push(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), 0.1), Vector3(g.x, deck + 7.3, g.z) - side * 0.6))
	k.box(Vector3.ZERO, Vector3(4.6, 0.8, 1.0), 0.08)
	k.pop()


# --- The Broodmother's cavern ----------------------------------------------------------

static func brood(b: ArenaBuild) -> void:
	var pr := b.prop
	b.params = {"grime": 0.5, "grime_color": Color(0.25, 0.24, 0.22), "ambient": 0.6}
	_local(b)
	var k := b.shell
	var d := b.detail
	var w := b.web
	var along: Vector3 = pr["along"]
	var across: Vector3 = pr["across"]
	var cav := float(pr["cav_r"])
	var pillars: Array = pr["pillars"]
	var rng := k.rng
	# Great web sheets between the rock pillars and the walls.
	for i in pillars.size():
		var p: Vector3 = pillars[i]
		var q: Vector3 = pillars[(i + 1) % pillars.size()]
		var out := Vector3(p.x, 0, p.z).normalized()
		_web_quad(w, p + Vector3(0, 3.0, 0), q + Vector3(0, 4.0, 0), q + Vector3(0, 13.0, 0), p + Vector3(0, 12.0, 0), i * 7 + 1, 0 if i % 2 == 0 else 1)
		_web_quad(w, p + out * 1.5 + Vector3(0, 6.0, 0), p + out * (cav - p.length() - 0.5) + Vector3(0, 9.0, 0), p + out * (cav - p.length() - 1.5) + Vector3(0, 16.0, 0), p + out * 1.5 + Vector3(0, 14.0, 0), i * 7 + 3, 2)
	# Silk carpets on the floor and threads from the roof.
	for i in 8:
		var a := rng.randf() * TAU
		var c := Vector3(cos(a), 0, sin(a)) * rng.randf_range(8.0, cav - 4.0)
		var s := rng.randf_range(2.5, 5.0)
		_web_quad(w, c + Vector3(-s, 0.05, -s), c + Vector3(s, 0.07, -s), c + Vector3(s, 0.05, s), c + Vector3(-s, 0.06, s), 40 + i, 1)
	d.mat(K.CLOTH, Color(0.85, 0.85, 0.8), 1.0)
	for i in 40:
		var a := rng.randf() * TAU
		var r := rng.randf_range(4.0, cav - 3.0)
		var top := 9.0 + 13.0 * sqrt(maxf(0.0, 1.0 - pow(r / cav, 2.0))) - 0.5
		var c := Vector3(cos(a) * r, top, sin(a) * r)
		d.sweep(PackedVector3Array([c, c + Vector3(rng.randf_range(-0.3, 0.3), -rng.randf_range(4.0, top - 1.0), rng.randf_range(-0.3, 0.3))]), PackedFloat32Array([0.012, 0.008]), 3, 1.0, Vector3.UP, false)
	# Silk bridges high across the cavern (above the Broodmother's climb).
	for i in 5:
		var a0 := rng.randf() * TAU
		var a1 := a0 + PI + rng.randf_range(-0.6, 0.6)
		var y0 := rng.randf_range(15.0, 18.0)
		var p0 := Vector3(cos(a0), 0, sin(a0)) * (cav - 6.0) + Vector3(0, y0, 0)
		var p1 := Vector3(cos(a1), 0, sin(a1)) * (cav - 6.0) + Vector3(0, y0 + rng.randf_range(-1.5, 1.5), 0)
		for j in 6:
			var o := Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.3, 0.3), rng.randf_range(-0.4, 0.4))
			d.sweep(K.sag_curve(p0 + o, p1 + o, rng.randf_range(1.0, 2.5), 16), _const_radii(17, 0.035), 4, 1.0, Vector3.UP, false)
	# Egg clutches glowing against the walls.
	for i in 6:
		var a := TAU * i / 6.0 + 0.4
		var c := Vector3(cos(a), 0, sin(a)) * (cav - 5.5)
		_eggs(b, d, c, 10 + i)
	# Cocoons hanging on silk.
	for i in 9:
		var a := rng.randf() * TAU
		var r := rng.randf_range(12.0, cav - 4.0)
		var top := 9.0 + 13.0 * sqrt(maxf(0.0, 1.0 - pow(r / cav, 2.0))) - 0.5
		var c := Vector3(cos(a) * r, rng.randf_range(6.5, 10.0), sin(a) * r)
		d.mat(K.CLOTH, Color(0.82, 0.8, 0.74), 1.0)
		d.rock(c, Vector3(0.45, 1.1, 0.45), 0.25, 2, 60 + i, 0.95, 0.0)
		d.sweep(PackedVector3Array([c + Vector3(0, 1.0, 0), Vector3(c.x, top, c.z)]), PackedFloat32Array([0.05, 0.02]), 4, 1.0, Vector3.UP, false)
		# wrapped bands
		for j in 4:
			d.push(Transform3D(Basis(Vector3.RIGHT, PI / 2.0) * Basis(Vector3.FORWARD, rng.randf_range(-0.3, 0.3)), c + Vector3(0, -0.7 + j * 0.45, 0)))
			d.lathe(PackedVector2Array([Vector2(0.44, -0.04), Vector2(0.48, 0.0), Vector2(0.44, 0.04)]), 10)
			d.pop()
	# Bone piles and stalagmites.
	for i in 6:
		var a := rng.randf() * TAU
		TartarusArena._bones(d, Vector3(cos(a), 0, sin(a)) * rng.randf_range(6.0, 20.0), 80 + i)
	k.mat(K.TRI + K.ROCK, Color(0.55, 0.52, 0.5), 0.4)
	for i in 18:
		var a := rng.randf() * TAU
		var c := Vector3(cos(a), -0.2, sin(a)) * rng.randf_range(cav - 6.0, cav - 1.5)
		k.spike(c, Vector3(rng.randf_range(-0.15, 0.15), 1, rng.randf_range(-0.15, 0.15)).normalized(), rng.randf_range(1.2, 3.8), rng.randf_range(0.35, 0.8), 7, i)
	# Webs in the tunnel and the sinkhole stones.
	var to: Vector3 = pr["tunnel_origin"]
	for tp: Vector3 in pr["tunnel"]:
		var c := to + tp
		_web_quad(w, c + across * -3.0 + Vector3(0, 0.3, 0), c + across * 3.0 + Vector3(0, 0.3, 0), c + across * 3.0 + Vector3(0, 4.8, 0), c + across * -3.0 + Vector3(0, 4.8, 0), int(tp.z * 3.0), 0)
	for st: Array in pr["stones"]:
		var p: Vector3 = to + Vector3(0, 1, 0) + (st[0] as Vector3)
		monolith(k, p, float(st[1]) + 0.3, float(st[2]), int(p.x * 13.0), false)
	b.light(b.center + Vector3(0, 12.0, 0), Color(0.55, 0.6, 0.75), 2.0, 26.0, 0, 0.0, 1.5)
	b.light(b.center + (pr["mouth"] as Vector3) + Vector3(0, 3.0, 0), Color(0.7, 0.75, 0.9), 1.5, 12.0, 0, 0.0, 1.0)
	# The web curtain over the cavern mouth (arena gate).
	var mouth: Vector3 = pr["mouth"]
	var g := K.new(5)
	g.raw = true
	for j in 3:
		var o := float(j) * 0.12
		_web_quad(g, Vector3(-3.8, -0.2, o), Vector3(3.8, -0.2, o), Vector3(3.8, 6.4, o), Vector3(-3.8, 6.4, o), 90 + j, 1 if j == 1 else 0)
	b.gate(int(pr.get("gate", 0)), g, Transform3D(Basis(across, Vector3.UP, along), b.center + mouth), "web", 0.0)


static func _const_radii(n: int, r: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	out.fill(r)
	return out


static func _web_quad(w: K, a: Vector3, b: Vector3, c: Vector3, d: Vector3, seed_value: int, style: int) -> void:
	w.mat(posmod(seed_value, 40), Color(1, 1, 1), 1.0, float(style))
	w.quad(a, b, c, d, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))


static func _eggs(b: ArenaBuild, d: K, at: Vector3, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	d.mat(K.CLOTH, Color(0.8, 0.78, 0.7), 1.0)
	d.rock(at + Vector3(0, 0.1, 0), Vector3(1.8, 0.35, 1.6), 0.3, 2, seed_value, 0.2)
	d.mat(K.GLOW, EGG, 1.0, 1.4)
	for i in 14:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 1.4)
		var s := rng.randf_range(0.3, 0.55)
		d.rock(at + Vector3(cos(a) * r, 0.35 + s * 0.6, sin(a) * r), Vector3(s, s * 1.3, s), 0.06, 2, seed_value * 20 + i)
	b.light(b.center + at + Vector3(0, 1.5, 0), Color(0.7, 1.0, 0.35), 3.2, 14.0, 1, 0.15, 1.2)


# --- Hagsfen ------------------------------------------------------------------------------

static func hagsfen(b: ArenaBuild) -> void:
	var pr := b.prop
	b.params = {"moss": 0.6, "grime": 0.5, "grime_color": Color(0.26, 0.28, 0.2), "outdoor": 1.0}
	_local(b)
	var k := b.shell
	var d := b.detail
	var hut: Vector3 = pr["hut"]
	_hut(b, k, d, hut, float(pr["hut_floor"]))
	# Cauldron of green brew.
	var cp: Vector3 = pr["cauldron"]
	k.push(Transform3D(Basis.IDENTITY, cp))
	k.mat(K.TRI + K.ROCK, Color(0.4, 0.38, 0.35), 0.5)
	for i in 5:
		var a := TAU * i / 5.0
		k.rock(Vector3(cos(a), 0.15, sin(a)) * 0.95, Vector3(0.35, 0.25, 0.3), 0.3, 1, i)
	k.mat(K.IRON, Color(1, 1, 1), 1.0)
	k.lathe(PackedVector2Array([Vector2(0.15, 0.35), Vector2(0.75, 0.55), Vector2(0.95, 0.95), Vector2(0.88, 1.35), Vector2(0.95, 1.45), Vector2(0.8, 1.45)]), 18)
	k.mat(K.GLOW, WITCH, 1.0, 2.2)
	k.lathe(PackedVector2Array([Vector2(0.82, 1.3), Vector2(0.0, 1.32)]), 18)
	k.pop()
	b.flame(b.center + cp + Vector3(0, 0.3, 0), 0.7, "fire")
	b.flame(b.center + cp + Vector3(0.2, 1.35, 0.1), 0.5, "green")
	b.light(b.center + cp + Vector3(0, 2.0, 0), WITCH, 3.0, 13.0, 1, 0.35, 1.5)
	b.embers.append([b.center + cp + Vector3(0, 1.4, 0), Vector3(0.4, 0.1, 0.4), 10, "green"])
	# Standing stones.
	for st: Array in pr["stones"]:
		monolith(k, st[0], float(st[1]) + 0.4, float(st[2]), int((st[0] as Vector3).x * 7.0 + 3), bool(st[3]))
	# Bone totems with witch-lights.
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		var p := Vector3(cos(a), 0, sin(a)) * 16.5
		d.mat(K.BARK, Color(0.38, 0.33, 0.28), 0.6)
		d.sweep(PackedVector3Array([p + Vector3(0, -0.3, 0), p + Vector3(0.1, 1.5, 0.05), p + Vector3(-0.05, 3.0, 0.0)]), PackedFloat32Array([0.12, 0.1, 0.07]), 6)
		d.mat(K.BONE, Color(0.85, 0.8, 0.7), 0.7)
		d.rock(p + Vector3(0, 3.1, 0), Vector3(0.22, 0.26, 0.26), 0.1, 2, i)
		for s: float in [-1.0, 1.0]:
			d.sweep(K.bezier(p + Vector3(s * 0.15, 3.2, 0), p + Vector3(s * 0.7, 3.6, 0.1), p + Vector3(s * 0.9, 4.2, -0.1), 6), PackedFloat32Array([0.05, 0.045, 0.04, 0.035, 0.03, 0.02, 0.01]), 5)
		b.flame(b.center + p + Vector3(0, 2.4, 0.25), 0.35, "green")
		b.light(b.center + p + Vector3(0, 2.6, 0.4), WITCH, 1.4, 8.0, 0, 0.4, 0.8)
	# Gnarled dead trees around the hut and the clearing.
	for i in 6:
		var a := k.rng.randf() * TAU
		var r := k.rng.randf_range(19.0, 23.0)
		dead_tree(k, Vector3(cos(a) * r, 0, sin(a) * r), k.rng.randf_range(6.0, 10.0), 300 + i)
	dead_tree(k, hut + Vector3(6.5, 0, 1.5), 9.0, 333)
	dead_tree(k, hut + Vector3(-7.0, 0, -2.0), 7.5, 334)
	# Pools: rotting roots and stumps on the banks.
	for pl: Array in pr["pools"]:
		var c: Vector3 = pl[0]
		var r := float(pl[1])
		d.mat(K.BARK, Color(0.3, 0.27, 0.23), 0.6)
		for j in 5:
			var a := d.rng.randf() * TAU
			var p := c + Vector3(cos(a), 0, sin(a)) * (r + 0.4)
			var q := c + Vector3(cos(a + 0.6), 0, sin(a + 0.6)) * (r - 0.6)
			d.sweep(K.bezier(p + Vector3(0, 0.1, 0), (p + q) * 0.5 + Vector3(0, 0.45, 0), q + Vector3(0, -0.3, 0), 6), PackedFloat32Array([0.12, 0.1, 0.09, 0.08, 0.06, 0.05, 0.04]), 5)
	TartarusArena._bones(d, Vector3(5, 0, -4), 3)
	TartarusArena._bones(d, Vector3(-7, 0, 3), 4)


static func _hut(b: ArenaBuild, k: K, d: K, c: Vector3, floor_y: float) -> void:
	var x0 := c.x - 4.5
	var x1 := c.x + 4.5
	var z0 := c.z - 3.5
	var z1 := c.z + 3.5
	var rng := k.rng
	# Crooked stilts.
	k.mat(K.BARK, Color(0.4, 0.34, 0.28), 0.6)
	for px: float in [x0 + 0.5, c.x, x1 - 0.5]:
		for pz: float in [z0 + 0.5, z1 - 0.5]:
			var lean := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
			k.sweep(PackedVector3Array([Vector3(px, -1.5, pz) + lean, Vector3(px, floor_y * 0.5, pz) + lean * 0.4, Vector3(px, floor_y + 4.2, pz)]), PackedFloat32Array([0.24, 0.2, 0.18]), 7)
	# cross bracing
	for pz: float in [z0 + 0.5, z1 - 0.5]:
		k.beam(Vector3(x0 + 0.5, 0.3, pz), Vector3(c.x, floor_y - 0.3, pz), 0.12, 0.12, 0.02)
		k.beam(Vector3(x1 - 0.5, 0.3, pz), Vector3(c.x, floor_y - 0.3, pz), 0.12, 0.12, 0.02)
	# Platform of uneven boards (porch included).
	k.mat(K.PLANKS, Color(0.5, 0.42, 0.34), 0.7)
	var z := z0
	while z < z1 + 1.0:
		var wb := rng.randf_range(0.22, 0.32)
		k.push(Transform3D(Basis.from_euler(Vector3(0, rng.randf_range(-0.02, 0.02), rng.randf_range(-0.02, 0.02))), Vector3(c.x + rng.randf_range(-0.15, 0.15), floor_y - 0.06, z + wb * 0.5)))
		k.box(Vector3.ZERO, Vector3(9.2 + rng.randf_range(-0.3, 0.2), 0.12, wb - 0.02), 0.01)
		k.pop()
		z += wb
	# Walls of vertical boards (door and windows left open), corner posts.
	var wall_h := 4.0
	var faces := [[Vector3(x0 + 0.1, 0, z0 + 0.1), Vector3(x1 - 0.1, 0, z0 + 0.1), Vector3(0, 0, -1)], [Vector3(x1 - 0.1, 0, z0 + 0.1), Vector3(x1 - 0.1, 0, z1 - 0.1), Vector3(1, 0, 0)],
			[Vector3(x1 - 0.1, 0, z1 - 0.1), Vector3(x0 + 0.1, 0, z1 - 0.1), Vector3(0, 0, 1)], [Vector3(x0 + 0.1, 0, z1 - 0.1), Vector3(x0 + 0.1, 0, z0 + 0.1), Vector3(-1, 0, 0)]]
	for f: Array in faces:
		var a: Vector3 = f[0]
		var e: Vector3 = f[1]
		var out: Vector3 = f[2]
		var along := (e - a).normalized()
		var length := a.distance_to(e)
		var t := 0.0
		while t < length - 0.05:
			var wb := minf(rng.randf_range(0.2, 0.3), length - t)
			var p := a + along * (t + wb * 0.5)
			var top := floor_y + wall_h + rng.randf_range(-0.1, 0.1)
			var door := out.z > 0.5 and absf(p.x - c.x) < 0.6
			var window := absf(out.x) > 0.5 and absf(p.z - c.z) < 0.55
			k.mat(K.PLANKS, Color(0.42, 0.36, 0.3) * (1.0 + rng.randf_range(-0.12, 0.08)), 0.7)
			k.push(Transform3D(P._basis_for(along, out) * Basis(Vector3(1, 0, 0), rng.randf_range(-0.02, 0.02)), p))
			if door:
				k.box(Vector3(0, (floor_y + 2.2 + top) * 0.5, 0), Vector3(0.08, top - floor_y - 2.2, wb - 0.015), 0.01)
			elif window:
				k.box(Vector3(0, floor_y + 0.8, 0), Vector3(0.08, 1.6, wb - 0.015), 0.01)
				k.box(Vector3(0, (floor_y + 2.6 + top) * 0.5, 0), Vector3(0.08, top - floor_y - 2.6, wb - 0.015), 0.01)
			else:
				k.box(Vector3(0, (floor_y + top) * 0.5, 0), Vector3(0.08, top - floor_y, wb - 0.015), 0.01)
			k.pop()
			t += wb
		k.mat(K.BARK, Color(0.38, 0.32, 0.27), 0.6)
		k.sweep(PackedVector3Array([a + Vector3(0, floor_y, 0), a + Vector3(0, floor_y + wall_h + 0.3, 0)]), PackedFloat32Array([0.14, 0.13]), 6)
	# window shutters hanging askew
	for s: float in [-1.0, 1.0]:
		k.mat(K.PLANKS, Color(0.38, 0.33, 0.28), 0.7)
		k.push(Transform3D(Basis(Vector3.UP, s * 0.9) * Basis(Vector3(0, 0, 1), 0.15), Vector3(c.x + s * 4.7, floor_y + 2.0, c.z + 0.6)))
		k.box(Vector3.ZERO, Vector3(0.06, 1.0, 0.6), 0.01)
		k.pop()
		k.mat(K.DARK, Color(0.03, 0.04, 0.02), 0.5)
		k.box(Vector3(c.x + s * (4.4 - 0.05), floor_y + 2.1, c.z), Vector3(0.02, 1.0, 1.1), 0.0)
	k.mat(K.DARK, Color(0.03, 0.04, 0.02), 0.5)
	k.box(Vector3(c.x, floor_y + 1.1, z1 - 0.15), Vector3(1.2, 2.2, 0.02), 0.0)
	# Gable ends and a sagging, overhanging thatch roof with a ridge pole.
	var eave := floor_y + wall_h
	var ridge := eave + 3.6
	k.mat(K.PLANKS, Color(0.4, 0.34, 0.28), 0.7)
	for gx: float in [x0 + 0.1, x1 - 0.1]:
		k.push(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(gx, 0, c.z)))
		k.extrude(PackedVector2Array([Vector2(-3.5, eave), Vector2(3.5, eave), Vector2(0.0, ridge)]), -0.05, 0.05)
		k.pop()
	k.mat(K.THATCH, Color(0.52, 0.47, 0.36), 0.5)
	for s: float in [-1.0, 1.0]:
		var nx := 10
		var nz := 6
		var grid := []
		for i in nx + 1:
			var row := PackedInt32Array()
			for j in nz + 1:
				var u := float(i) / nx
				var v := float(j) / nz
				var x := lerpf(x0 - 0.9, x1 + 0.9, u)
				var zz := c.z + s * lerpf(0.0, 4.7, v)
				var y := lerpf(ridge + 0.25, eave - 0.9, v) - sin(u * PI) * 0.25 * sin(v * PI) - (0.15 if i % 3 == 1 and j == nz else 0.0)
				var nrm := Vector3(0, 1.0, s * 0.8).normalized()
				row.append(k._v(Vector3(x, y, zz), nrm, Vector2(x, zz * 1.4)))
				row.append(k._v(Vector3(x, y - 0.35, zz), -nrm, Vector2(x, zz * 1.4)))
			grid.append(row)
		for i in nx:
			for j in nz:
				var r0: PackedInt32Array = grid[i]
				var r1: PackedInt32Array = grid[i + 1]
				k._t(r0[j * 2], r1[j * 2], r1[j * 2 + 2])
				k._t(r0[j * 2], r1[j * 2 + 2], r0[j * 2 + 2])
				k._t(r0[j * 2 + 1], r1[j * 2 + 3], r1[j * 2 + 1])
				k._t(r0[j * 2 + 1], r0[j * 2 + 3], r1[j * 2 + 3])
	k.mat(K.BARK, Color(0.36, 0.3, 0.25), 0.6)
	k.sweep(PackedVector3Array([Vector3(x0 - 1.0, ridge + 0.25, c.z), Vector3(c.x, ridge + 0.1, c.z), Vector3(x1 + 1.0, ridge + 0.3, c.z)]), PackedFloat32Array([0.14, 0.15, 0.13]), 6)
	# Stone chimney.
	k.mat(K.TRI + K.ROCK, Color(0.45, 0.42, 0.38), 0.5)
	var yy := floor_y
	while yy < ridge + 1.5:
		k.rock(Vector3(x1 - 1.2, yy + 0.25, c.z - 2.2), Vector3(0.5, 0.28, 0.5), 0.35, 1, int(yy * 10.0))
		yy += 0.45
	# Porch rail, stairs with rails.
	k.mat(K.BARK, Color(0.4, 0.34, 0.28), 0.6)
	for px: float in [x0 + 0.3, c.x - 1.6, c.x + 1.6, x1 - 0.3]:
		k.sweep(PackedVector3Array([Vector3(px, floor_y, z1 + 0.85), Vector3(px, floor_y + 1.1, z1 + 0.85)]), PackedFloat32Array([0.07, 0.06]), 5)
	k.beam(Vector3(x0 + 0.3, floor_y + 1.05, z1 + 0.85), Vector3(c.x - 1.6, floor_y + 1.0, z1 + 0.85), 0.08, 0.08, 0.01)
	k.beam(Vector3(c.x + 1.6, floor_y + 1.0, z1 + 0.85), Vector3(x1 - 0.3, floor_y + 1.08, z1 + 0.85), 0.08, 0.08, 0.01)
	k.mat(K.PLANKS, Color(0.48, 0.4, 0.33), 0.7)
	for i in 3:
		var sz := z1 + 3.5 - i
		k.box(Vector3(c.x, float(i + 1) - 0.1, sz), Vector3(3.0, 0.16, 0.95), 0.02)
		k.box(Vector3(c.x, float(i + 1) * 0.5 - 0.5, sz), Vector3(2.6, float(i + 1) - 0.2, 0.08), 0.0)
	# Hanging skulls, bundles and a witch-lantern under the eaves.
	for i in 5:
		var p := Vector3(lerpf(x0, x1, (float(i) + 0.5) / 5.0), eave - 0.6, z1 + 0.7)
		d.mat(K.CLOTH, Color(0.4, 0.38, 0.3), 1.0)
		d.sweep(PackedVector3Array([p + Vector3(0, 0.6, 0), p]), PackedFloat32Array([0.01, 0.01]), 3, 1.0, Vector3.UP, false)
		if i % 2 == 0:
			d.mat(K.BONE, Color(0.85, 0.8, 0.7), 0.7)
			d.rock(p - Vector3(0, 0.15, 0), Vector3(0.12, 0.14, 0.14), 0.1, 2, i)
		else:
			d.mat(K.THATCH, Color(0.4, 0.45, 0.25), 0.5)
			d.rock(p - Vector3(0, 0.25, 0), Vector3(0.1, 0.3, 0.1), 0.3, 1, i)
	d.mat(K.IRON, Color(1, 1, 1), 1.0)
	var lp := Vector3(c.x + 1.2, eave - 0.9, z1 + 0.8)
	d.push(Transform3D(Basis.IDENTITY, lp))
	d.lathe(PackedVector2Array([Vector2(0.05, -0.2), Vector2(0.18, -0.1), Vector2(0.18, 0.2), Vector2(0.04, 0.35)]), 6)
	d.pop()
	b.flame(b.center + lp - Vector3(0, 0.15, 0), 0.25, "green")
	b.light(b.center + lp, WITCH, 1.8, 9.0, 0, 0.4, 0.8)
	b.light(b.center + Vector3(c.x, floor_y + 2.0, c.z), Color(1.0, 0.6, 0.3), 1.2, 6.0, 0, 0.3, 0.3)
