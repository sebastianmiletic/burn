class_name SeaArenas
extends RefCounted
## Modelled lairs of the ocean bosses (SeaLairs blueprints): the Kraken's
## Graveyard (wreck decks round a flooded pool) and the Maw of the Sea (a
## drowned temple's platforms on sea stacks round Charybdis's whirlpool).
## Centre-relative coordinates, deck top at y = 0.

const K := preload("res://world/architecture/arenas/arena_kit.gd")
const P := preload("res://world/architecture/arenas/arena_pieces.gd")

const WOOD := Color(0.46, 0.38, 0.3)
const WET_WOOD := Color(0.3, 0.26, 0.22)
const TEMPLE := Color(0.74, 0.74, 0.7)
const CORAL := Color(0.95, 0.55, 0.5)


static func _local(b: ArenaBuild) -> void:
	for kit: K in [b.shell, b.detail]:
		kit.push(Transform3D(Basis.IDENTITY, b.center))
		kit.ao_floor = 0.0


## Planks laid round a ring band between radii r0..r1 from angle a0 to a1 (curved decking).
static func _ring_planks(k: K, r0: float, r1: float, a0: float, a1: float, holes: float) -> void:
	var r := r0
	while r < r1 - 0.05:
		var w := minf(0.32, r1 - r)
		var a := a0
		while a < a1 - 0.01:
			var len := minf(k.rng.randf_range(2.2, 4.0) / maxf(r, 1.0), a1 - a)
			if k.rng.randf() >= holes:
				k.mat(K.PLANKS, WOOD * (0.85 + k.rng.randf() * 0.3), 0.8)
				var hh := k.rng.randf_range(-0.03, 0.02)
				k.lathe(PackedVector2Array([Vector2(r + 0.02, -0.12), Vector2(r + 0.02, hh), Vector2(r + w - 0.02, hh), Vector2(r + w - 0.02, -0.12)]), 2, a + 0.004, a + len - 0.004)
			a += len
		r += w


# --- The Kraken's Graveyard -------------------------------------------------------------------

static func kraken(b: ArenaBuild) -> void:
	var pr := b.prop
	b.params = {"moss": 0.5, "grime": 0.6, "grime_color": Color(0.22, 0.26, 0.22), "outdoor": 1.0}
	_local(b)
	var k := b.shell
	var d := b.detail
	var pool := float(pr["pool"])
	var deck := float(pr["deck"])
	var sectors: Array = pr["sectors"]
	k.ao_floor = -INF
	for s: Vector2 in sectors:
		# A wreck's deck: curved planking with a few holes, a dark hold beneath.
		_ring_planks(k, pool + 0.3, deck, s.x, s.y, 0.05)
		k.mat(K.DARK, Color(0.05, 0.04, 0.035), 0.5)
		k.lathe(PackedVector2Array([Vector2(pool + 0.3, -0.5), Vector2(deck - 0.2, -0.5)]), 10, s.x, s.y)
		# Hull sides: planked curves down into the sea, the outer one with ribs showing.
		k.mat(K.PLANKS, WET_WOOD, 0.6)
		k.lathe(PackedVector2Array([Vector2(deck + 0.1, 0.1), Vector2(deck + 0.35, -1.2), Vector2(deck + 0.1, -3.0), Vector2(deck - 0.9, -5.0)]), 14, s.x, s.y)
		k.lathe(PackedVector2Array([Vector2(pool + 0.6, -5.0), Vector2(pool, -2.6), Vector2(pool + 0.1, -0.9), Vector2(pool + 0.3, 0.1)]), 10, s.x, s.y)
		# Gunwale rail along the outer edge.
		k.mat(K.PLANKS, WOOD * 0.8, 0.7)
		k.lathe(PackedVector2Array([Vector2(deck - 0.3, 0.0), Vector2(deck - 0.3, 0.7), Vector2(deck + 0.15, 0.7), Vector2(deck + 0.15, 0.0)]), 12, s.x + 0.04, s.y - 0.04)
		# Ribs along the hull, barnacles and weed at the water line.
		var n := int((s.y - s.x) * deck / 1.6)
		for i in n + 1:
			var a := lerpf(s.x, s.y, float(i) / maxf(n, 1))
			var dir := Vector3(cos(a), 0, sin(a))
			k.mat(K.PLANKS, WET_WOOD * 0.85, 0.6)
			k.sweep(K.bezier(dir * (deck + 0.45) + Vector3(0, 0.6, 0), dir * (deck + 0.75) + Vector3(0, -2.0, 0), dir * (deck - 0.6) + Vector3(0, -5.2, 0), 6),
					PackedFloat32Array([0.13, 0.15, 0.15, 0.14, 0.13, 0.12, 0.11]), 5)
			d.mat(K.TRI + K.ROCK, Color(0.5, 0.48, 0.42), 0.8)
			d.rock(dir * (deck + 0.5) + Vector3(0, -1.0 + d.rng.randf_range(-0.2, 0.2), 0), Vector3(0.35, 0.25, 0.35) * d.rng.randf_range(0.7, 1.4), 0.4, 1, i)
		# Hatches, coils of rope, crates and barrels on the deck.
		var mid := (s.x + s.y) * 0.5
		var hatch := Vector3(cos(mid), 0, sin(mid)) * (pool + deck) * 0.5
		k.mat(K.PLANKS, WOOD * 0.7, 0.7)
		k.push(Transform3D(Basis(Vector3.UP, -mid), hatch))
		k.box(Vector3(0, 0.12, 0), Vector3(2.0, 0.25, 1.6), 0.03)
		k.mat(K.IRON, Color(0.4, 0.38, 0.35), 0.5)
		k.box(Vector3(0, 0.27, 0), Vector3(2.05, 0.06, 0.12), 0.0)
		k.pop()
		for c in 3:
			var a := lerpf(s.x, s.y, d.rng.randf_range(0.15, 0.85))
			var p := Vector3(cos(a), 0, sin(a)) * d.rng.randf_range(pool + 1.5, deck - 1.5)
			if c == 0:
				d.mat(K.PLANKS, WOOD * 0.9, 0.7)
				d.push(Transform3D(Basis(Vector3.UP, d.rng.randf() * TAU), p))
				d.box(Vector3(0, 0.4, 0), Vector3(0.8, 0.8, 0.8), 0.04)
				d.pop()
			else:
				d.mat(K.PLANKS, WOOD * 0.75, 0.6)
				d.push(Transform3D(Basis.IDENTITY, p))
				d.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.3, 0.0), Vector2(0.36, 0.45), Vector2(0.3, 0.9), Vector2(0.0, 0.9)]), 12)
				d.pop()
	# Plank bridges over the gaps between the wrecks.
	for s: Vector2 in sectors:
		var mid := s.y + 0.16
		var dir := Vector3(cos(mid), 0, sin(mid))
		var side := Vector3(-dir.z, 0, dir.x)
		var t := pool + 1.0
		while t < deck - 1.5:
			k.mat(K.PLANKS, WOOD * (0.8 + k.rng.randf() * 0.3), 0.8)
			k.push(Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)) * Basis(Vector3.BACK, k.rng.randf_range(-0.03, 0.03)), dir * (t + 0.2)))
			k.box(Vector3(0, -0.08, 0), Vector3(2.4, 0.14, 0.34), 0.02)
			k.pop()
			t += 0.4
		for sg: float in [-1.0, 1.0]:
			d.mat(K.PLANKS, WOOD * 0.6, 0.6)
			var a0 := dir * (pool + 1.2) + side * sg * 1.2
			var a1 := dir * (deck - 1.6) + side * sg * 1.2
			d.sweep(PackedVector3Array([a0, a0 + Vector3(0, 1.0, 0)]), PackedFloat32Array([0.06, 0.05]), 5)
			d.sweep(PackedVector3Array([a1, a1 + Vector3(0, 1.0, 0)]), PackedFloat32Array([0.06, 0.05]), 5)
			d.mat(K.CLOTH, Color(0.55, 0.48, 0.36), 0.8)
			d.sweep(K.sag_curve(a0 + Vector3(0, 0.95, 0), a1 + Vector3(0, 0.95, 0), 0.35, 10), PackedFloat32Array([0.025, 0.025, 0.025, 0.025, 0.025, 0.025, 0.025, 0.025, 0.025, 0.025, 0.025]), 4)
	# Broken masts with yards, torn sails and rigging; lanterns hang from them.
	for m: Array in pr["masts"]:
		var at: Vector3 = m[0]
		var h := float(m[1])
		var tilt := float(m[2])
		var top := at + Vector3(tilt * h, h, -tilt * h * 0.5)
		k.mat(K.BARK, Color(0.38, 0.3, 0.24), 0.6)
		k.sweep(PackedVector3Array([at + Vector3(0, -1.0, 0), at.lerp(top, 0.5), top]), PackedFloat32Array([0.32, 0.27, 0.2]), 10)
		k.mat(K.PLANKS, WOOD * 0.7, 0.6)
		var yard_at := at.lerp(top, 0.78)
		var yard_dir := Vector3(-at.z, 0, at.x).normalized()
		k.sweep(PackedVector3Array([yard_at - yard_dir * 3.2 + Vector3(0, -0.4, 0), yard_at + yard_dir * 3.0]), PackedFloat32Array([0.12, 0.12]), 6)
		# A torn sail hanging from the yard.
		d.mat(K.CLOTH, Color(0.66, 0.6, 0.48), 0.7)
		var y0 := yard_at.y - 0.15
		var steps := 6
		for j in steps:
			var u0 := -2.6 + 5.0 * j / steps
			var u1 := -2.6 + 5.0 * (j + 1) / steps
			var drop0 := 2.4 + sin(j * 1.7) * 0.9
			var drop1 := 2.4 + sin((j + 1) * 1.7) * 0.9
			var p0 := yard_at + yard_dir * u0
			var p1 := yard_at + yard_dir * u1
			var outw := at.normalized() * 0.3
			d.quad(Vector3(p0.x, y0, p0.z), Vector3(p1.x, y0, p1.z), Vector3(p1.x, y0 - drop1, p1.z) + outw, Vector3(p0.x, y0 - drop0, p0.z) + outw,
					Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
			d.quad(Vector3(p0.x, y0 - drop0, p0.z) + outw, Vector3(p1.x, y0 - drop1, p1.z) + outw, Vector3(p1.x, y0, p1.z), Vector3(p0.x, y0, p0.z),
					Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
		d.mat(K.CLOTH, Color(0.4, 0.36, 0.28), 0.8)
		for sg: float in [-1.0, 1.0]:
			var anchor := at + yard_dir * sg * 2.5 + Vector3(0, 0.6, 0)
			d.sweep(K.sag_curve(top, anchor, 0.4, 8), PackedFloat32Array([0.03, 0.03, 0.03, 0.03, 0.03, 0.03, 0.03, 0.03, 0.03]), 4)
		d.mat(K.IRON, Color(0.3, 0.3, 0.3), 0.6)
		var lamp := yard_at + yard_dir * 2.4 + Vector3(0, -0.8, 0)
		d.push(Transform3D(Basis.IDENTITY, lamp))
		d.lathe(PackedVector2Array([Vector2(0.05, -0.4), Vector2(0.2, -0.3), Vector2(0.2, 0.1), Vector2(0.05, 0.25)]), 6)
		d.pop()
		b.flame(b.center + lamp + Vector3(0, -0.1, 0), 0.35, "fire")
		b.light(b.center + lamp, Color(1.0, 0.7, 0.4), 1.8, 12.0, 0, 0.3, 0.8)
	# Ribs of older wrecks sticking out of the water outside the ring.
	var coast: Vector3 = pr["coast"]
	for i in 3:
		var a := atan2(coast.z, coast.x) + PI + (i - 1) * 0.9
		var at := Vector3(cos(a), 0, sin(a)) * (deck + 9.0) + Vector3(0, -2.0, 0)
		d.push_at(at, a)
		d.mat(K.PLANKS, WET_WOOD * 0.8, 0.6)
		for j in 6:
			var z := -3.0 + j * 1.2
			for sg: float in [-1.0, 1.0]:
				d.sweep(K.bezier(Vector3(0, -1.5, z), Vector3(sg * 2.8, 0.5, z), Vector3(sg * 2.0, 3.0 + j * 0.2, z), 6), PackedFloat32Array([0.16, 0.15, 0.14, 0.13, 0.12, 0.1, 0.08]), 5)
		d.pop()
	b.light(b.center + Vector3(0, 6.0, 0), Color(0.45, 0.8, 1.0), 0.8, 26.0, 1, 0.1, 0.4)
	if pr.has("causeway"):
		LairArenas._causeway(b, k, d, pr["causeway"])


# --- The Maw of the Sea -----------------------------------------------------------------------

static func charybdis(b: ArenaBuild) -> void:
	var pr := b.prop
	b.params = {"moss": 0.6, "grime": 0.5, "grime_color": Color(0.24, 0.3, 0.26), "outdoor": 1.0}
	_local(b)
	var k := b.shell
	var d := b.detail
	var inner := float(pr["inner"])
	var outer := float(pr["outer"])
	var sectors: Array = pr["sectors"]
	k.ao_floor = -INF
	for s: Vector2 in sectors:
		# Temple platforms: rings of worn flagstones, broken at the ends.
		var r := inner
		var ring := 0
		while r < outer:
			var w := minf(1.8, outer - r)
			var n := maxi(2, int((s.y - s.x) * (r + w * 0.5) / 1.7))
			for i in n:
				var a0 := lerpf(s.x, s.y, float(i) / n) + 0.008
				var a1 := lerpf(s.x, s.y, float(i + 1) / n) - 0.008
				k.mat(K.LIMESTONE if (i + ring) % 4 else K.MOSSY_WALL, TEMPLE * (1.0 + k.rng.randf_range(-0.1, 0.06)), 0.45)
				var hh := k.rng.randf_range(-0.04, 0.02)
				k.lathe(PackedVector2Array([Vector2(r + 0.025, -0.45), Vector2(r + 0.025, hh), Vector2(r + w - 0.025, hh), Vector2(r + w - 0.025, -0.45)]), 3, a0, a1)
			r += w
			ring += 1
		# The platform's edge: a moulded kerb and a stone skirt down to the sea stack.
		k.mat(K.MOSSY_WALL, TEMPLE * 0.8, 0.35)
		k.lathe(PackedVector2Array([Vector2(outer + 0.2, -3.5), Vector2(outer + 0.25, -0.5), Vector2(outer + 0.45, -0.3), Vector2(outer + 0.45, 0.2), Vector2(outer, 0.2)]), 16, s.x, s.y, 0.02)
		k.lathe(PackedVector2Array([Vector2(inner, 0.2), Vector2(inner - 0.3, 0.2), Vector2(inner - 0.3, -0.5), Vector2(inner + 0.4, -3.5)]), 12, s.x, s.y, 0.02)
	# Arched stone bridges over the gaps.
	for s: Vector2 in sectors:
		var mid := s.y + 0.18
		var dir := Vector3(cos(mid), 0, sin(mid))
		var yaw := atan2(dir.x, dir.z)
		var a := dir * (inner + 1.5)
		var e := dir * (outer - 1.5)
		k.mat(K.LIMESTONE, TEMPLE * 0.92, 0.4)
		k.push(Transform3D(Basis(Vector3.UP, yaw), (a + e) * 0.5))
		k.box(Vector3(0, -0.3, 0), Vector3(2.8, 0.6, a.distance_to(e) + 0.4), 0.05)
		for sg: float in [-1.0, 1.0]:
			k.box(Vector3(sg * 1.3, 0.35, 0), Vector3(0.3, 0.7, a.distance_to(e)), 0.04)
		k.pop()
		k.mat(K.MOSSY_WALL, TEMPLE * 0.8, 0.32)
		k.push(Transform3D(Basis(Vector3.UP, yaw + PI / 2.0), (a + e) * 0.5 + Vector3(0, -4.2, 0)))
		k.arch(a.distance_to(e) - 1.0, 0.0, 0.7, 2.6, 9, 0.0)
		k.pop()
	# Columns of the drowned temple, some broken, crusted with coral and weed.
	for c: Array in pr["columns"]:
		var at: Vector3 = c[0]
		var h := float(c[1])
		k.mat(K.MARBLE, Color(0.7, 0.72, 0.68), 0.35)
		k.column(at, h + 1.0, 0.85, "fluted", 0.9 if h < 7.0 else 0.0, 16)
		_coral_crust(d, at, h * 0.6, 0.95)
	# Two coral-crusted statues of the sea god's priests, facing the maw.
	for i in 2:
		var s: Vector2 = sectors[i * 3]
		var a := (s.x + s.y) * 0.5
		var at := Vector3(cos(a), 0, sin(a)) * (outer - 2.2)
		P.statue(k, at, -a - PI / 2.0, 4.2, K.MARBLE, Color(0.62, 0.66, 0.62), i == 0, i == 1)
		_coral_crust(d, at, 2.5, 1.2)
	# Braziers.
	for i in 3:
		var s: Vector2 = sectors[i * 2]
		var a := lerpf(s.x, s.y, 0.7)
		var at := Vector3(cos(a), 0, sin(a)) * (inner + 2.6)
		P.fire_basin(b, k, at, b.center + at, 0.85, "fire", K.LIMESTONE, Color(1.0, 0.62, 0.32), 1)
	b.light(b.center + Vector3(0, -6.0, 0), Color(0.3, 1.0, 0.75), 1.6, 18.0, 1, 0.2, 0.5)
	if pr.has("causeway"):
		LairArenas._causeway(b, k, d, pr["causeway"])


## Coral heads, fans and weed crusting a column or statue up to `h`.
static func _coral_crust(d: K, at: Vector3, h: float, r: float) -> void:
	for i in 7:
		var a := d.rng.randf() * TAU
		var y := d.rng.randf_range(0.1, h)
		var p := at + Vector3(cos(a) * r, y, sin(a) * r)
		var tint := [CORAL, Color(0.95, 0.75, 0.4), Color(0.6, 0.45, 0.85), Color(0.4, 0.75, 0.6)][i % 4] as Color
		d.mat(K.TRI + K.LIMESTONE, tint, 0.9)
		d.rock(p, Vector3(0.28, 0.22, 0.28) * d.rng.randf_range(0.7, 1.5), 0.45, 1, i + int(at.x))
		if i % 3 == 0:
			# A small branching coral sprouting from the crust.
			for j in 3:
				var dir := (Vector3(cos(a), 0.8, sin(a)) + Vector3(d.rng.randf_range(-0.4, 0.4), 0, d.rng.randf_range(-0.4, 0.4))).normalized()
				d.sweep(K.bezier(p, p + dir * 0.25 + Vector3(0, 0.1, 0), p + dir * 0.5 + Vector3(0, 0.15, 0), 4), PackedFloat32Array([0.05, 0.045, 0.035, 0.025, 0.015]), 5)
