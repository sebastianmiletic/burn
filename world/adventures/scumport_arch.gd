class_name ScumportArch
extends RefCounted
## Modelled Scumport (ScumportPlan lays it out): plank boardwalks on piles,
## rope bridges, the packed jettied houses (2-4 storeys of weathered or tarred
## boards, grimy plaster and rusted sheet metal under gable, shed or flat
## roofs), taverns and shops with rooms, the market quay, piers, skiffs, two
## hulks, cranes, lanterns, washing lines and clutter. Runs on a worker thread
## into one ArchBuild (one mesh per level of detail for the whole town).

const L := ArchMaterials.L
const DECK := ScumportPlan.DECK
const STOREY := ScumportPlan.STOREY
const TIMBER := Color(0.27, 0.21, 0.16)
const PLANK := Color(0.46, 0.4, 0.33)
const ROPE := Color(0.6, 0.52, 0.38)


static func build(b: ArchBuild, prop: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(prop.get("seed", 1))
	var town: Dictionary = prop["town"]
	var top := float(DECK + 1) - b.origin.y
	if b.far_only:
		_far(b, prop, top)
		return
	_decks(b, town, top, rng)
	for h: Dictionary in prop["houses"]:
		_house(b, h, rng)
	_bridges(b, prop["bridges"], top)
	_market(b, prop, top, rng)
	_harbour(b, prop, top, rng)
	_streets(b, prop, top, rng)


# --- Boardwalks ---------------------------------------------------------------------------

static func _decks(b: ArchBuild, town: Dictionary, top: float, rng: RandomNumberGenerator) -> void:
	var x0: int = town["x0"]
	var z0: int = town["z0"]
	var nx: int = town["nx"]
	var nz: int = town["nz"]
	var m := b.shell
	# Planks: one slab per run of deck cells along x, a slightly different tint per row.
	for z in nz:
		var x := 0
		while x < nx:
			var t := ScumportPlan.cell(town, x0 + x, z0 + z)
			if t == ScumportPlan.T_OUT or t == ScumportPlan.T_WATER or t == ScumportPlan.T_BRIDGE:
				x += 1
				continue
			var start := x
			while x < nx:
				var t2 := ScumportPlan.cell(town, x0 + x, z0 + z)
				if t2 == ScumportPlan.T_OUT or t2 == ScumportPlan.T_WATER or t2 == ScumportPlan.T_BRIDGE:
					break
				x += 1
			var a := Vector3(x0 + start, 0, z0 + z) - b.origin
			var length := float(x - start)
			m.mat(L.BOARDS, PLANK * (0.85 + 0.25 * fposmod(z * 0.37, 1.0)), 0.25)
			m.box(Vector3(a.x + length * 0.5, top - 0.1, a.z + 0.5), Vector3(length, 0.2, 0.98), 0, 0)
	# Piles where the deck stands over water or a muddy beach, cross beams under the planks.
	m.mat(L.TIMBER, TIMBER, 0.9)
	for z in range(1, nz, 3):
		for x in range(1, nx, 3):
			var t := ScumportPlan.cell(town, x0 + x, z0 + z)
			if t == ScumportPlan.T_OUT or t == ScumportPlan.T_WATER:
				continue
			var p := Vector3(x0 + x + 0.5, 0, z0 + z + 0.5) - b.origin
			var g := b.ground(p)
			if g > top - 0.6:
				continue
			m.cylinder(Vector3(p.x, g - 0.6, p.z), Vector3(p.x + rng.randf_range(-0.08, 0.08), top - 0.2, p.z), 0.17, 0.14, 6, false)
			if ScumportPlan.cell(town, x0 + x + 3, z0 + z) != ScumportPlan.T_OUT:
				m.beam(Vector3(p.x, top - 0.32, p.z), Vector3(p.x + 3.0, top - 0.32, p.z), 0.16, 0.2)
	# Railings along the edges over water.
	var d := b.detail
	d.mat(L.TIMBER, TIMBER * 1.2, 0.7)
	for z in nz:
		for x in nx:
			var t := ScumportPlan.cell(town, x0 + x, z0 + z)
			if not ScumportPlan.walkable(t) or t == ScumportPlan.T_BRIDGE:
				continue
			for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := ScumportPlan.cell(town, x0 + x + dir.x, z0 + z + dir.y)
				if n != ScumportPlan.T_WATER:
					continue
				var c := Vector3(x0 + x + 0.5 + dir.x * 0.45, top, z0 + z + 0.5 + dir.y * 0.45) - b.origin
				var along := Vector3(dir.y, 0, dir.x) * 0.5
				d.beam(c - along + Vector3(0, 0.95, 0), c + along + Vector3(0, 0.95, 0), 0.08, 0.08)
				if (x + z) % 2 == 0:
					d.beam(c - along, c - along + Vector3(0, 1.0, 0), 0.1, 0.1)


static func _bridges(b: ArchBuild, bridges: Array, top: float) -> void:
	var m := b.shell
	var d := b.detail
	for br: Array in bridges:
		var a := (br[0] as Vector3) - b.origin
		var z := (br[1] as Vector3) - b.origin
		var width := z.x - a.x
		var length := z.z - a.z
		# Slatted planks with gaps, lashed to two ropes; sagging hand ropes on posts.
		m.mat(L.BOARDS, PLANK * 0.9, 0.3)
		var n := int(length / 0.45)
		for k in n:
			var zz := a.z + (k + 0.5) * length / n
			var sag := 0.12 * sin(PI * (k + 0.5) / n)
			m.box(Vector3(a.x + width * 0.5, top - 0.08 - sag, zz), Vector3(width - 0.2, 0.08, 0.34), 0)
		d.mat(L.LINEN, ROPE, 0.5)
		for s: float in [a.x + 0.15, z.x - 0.15]:
			m.mat(L.TIMBER, TIMBER, 0.8)
			for zz: float in [a.z - 0.2, z.z + 0.2]:
				m.cylinder(Vector3(s, top - 1.5, zz), Vector3(s, top + 1.3, zz), 0.12, 0.1, 6)
			var prev := Vector3(s, top + 1.2, a.z - 0.2)
			for k in 7:
				var f := float(k + 1) / 7.0
				var p := Vector3(s, top + 1.2 - 0.45 * sin(PI * f), lerpf(a.z - 0.2, z.z + 0.2, f))
				d.beam(prev, p, 0.04, 0.04)
				prev = p


# --- Houses ---------------------------------------------------------------------------------

static func _house(b: ArchBuild, h: Dictionary, rng: RandomNumberGenerator) -> void:
	var w := float(h["w"])
	var d := float(h["d"])
	var n: int = h["storeys"]
	var role := String(h["role"])
	var enterable: bool = h["enterable"]
	var mats: Array = h["mats"]
	var t := 0.22
	var xf := BuildingMesh.frame(h, b.origin)
	b.push(xf)
	var hr := RandomNumberGenerator.new()
	hr.seed = int(h["seed"])
	var y := 0.0
	var prev_over := 0.0
	var dd := d
	var zc := 0.0
	for s in n:
		var over := (minf(s, 2.0) * 0.55) if bool(h["jetty"]) else 0.0
		dd = d + over
		zc = over * 0.5
		var spec_m: Array = ScumportPlan.WALLS[int(mats[s])]
		var layer: int = spec_m[0]
		var tint: Color = spec_m[1]
		b.push(Transform3D(Basis.IDENTITY, Vector3(0, y, zc)))
		for side in 4:
			var length := ArchKit.side_length(side, w, dd)
			var holes := _holes(h, side, s, length, hr)
			b.push(ArchKit.side_frame(side, w, dd))
			var inner := enterable and s == 0
			ArchKit.wall(b.shell, length, 0.0, STOREY, t, holes, layer, tint, 0.45, L.BOARDS if inner else -1, tint * 0.8,
					t if side >= 2 else 0.0, length - t if side >= 2 else length)
			if side < 2:
				# Corner posts only (a town this size can't afford a post per bay).
				b.shell.mat(L.TIMBER, TIMBER, 0.6)
				b.shell.box(Vector3(0.1, STOREY * 0.5, -0.08), Vector3(0.22, STOREY, 0.22), 1)
				b.shell.box(Vector3(length - 0.1, STOREY * 0.5, -0.08), Vector3(0.22, STOREY, 0.22), 1)
			for hole: Rect2 in holes:
				if hole.position.y < 0.5:
					ArchKit.door(b, hole, t, L.TIMBER, TIMBER, Color(0.3, 0.22, 0.16), enterable, hole.size.x > 1.5)
				else:
					_window(b, hole, t, hr.randf() < 0.7, hr.randf() < 0.3)
			b.pop()
		# Floor band between storeys; the jetty's underside and joist ends.
		b.shell.mat(L.TIMBER, TIMBER, 0.6)
		b.shell.box(Vector3(0, 0.06, dd * 0.5 + 0.05), Vector3(w + 0.1, 0.22, 0.14), 0)
		b.pop()
		if over > prev_over:
			var zf := d * 0.5 + prev_over
			b.shell.mat(L.FLOOR, TIMBER * 1.1, 0.5)
			b.shell.box(Vector3(0, y - 0.08, zf + (over - prev_over) * 0.5), Vector3(w, 0.16, over - prev_over), 0)
			b.shell.mat(L.TIMBER, TIMBER, 0.6)
			for k in int(w / 1.5):
				var x := -w * 0.5 + 0.75 + k * 1.5
				b.shell.beam(Vector3(x, y - 0.24, zf - 0.3), Vector3(x, y - 0.24, d * 0.5 + over), 0.12, 0.16)
			# Braces under the jetty.
			for sx: float in [-w * 0.5 + 0.3, w * 0.5 - 0.3]:
				b.shell.beam(Vector3(sx, y - 1.1, d * 0.5 + prev_over), Vector3(sx, y - 0.1, d * 0.5 + over - 0.1), 0.1, 0.1)
		prev_over = over
		y += STOREY
	_roof(b, h, w, dd, zc, y, hr)
	# Signs, lanterns and clutter at the door.
	var front := d * 0.5
	var door_x := -w * 0.5 + float(h["door"]) + float(h["door_w"]) * 0.5
	if role in ["tavern", "shop"]:
		var sx := door_x + (1.0 if door_x < 0.0 else -1.0) * (float(h["door_w"]) * 0.5 + 0.6)
		b.detail.mat(L.IRON, Color(0.18, 0.16, 0.15), 0.6)
		b.detail.beam(Vector3(sx, 2.7, front), Vector3(sx, 2.7, front + 1.0), 0.05, 0.05)
		b.detail.mat(L.BOARDS, Color(0.5, 0.2, 0.14) if role == "tavern" else Color(0.25, 0.35, 0.3), 0.6)
		b.detail.box(Vector3(sx, 2.25, front + 0.75), Vector3(0.06, 0.6, 0.8), 1)
		b.add_light(Vector3(door_x, 2.6, front + 0.5), Color(1.0, 0.6, 0.3), 7.0, 0.9, false)
	if hr.randf() < 0.6:
		var p := Vector3(-w * 0.5 + 0.5 + hr.randf() * (w - 1.0), 0, front + 0.45)
		if absf(p.x - door_x) > 1.2:
			if hr.randf() < 0.5:
				VillageProps.barrel(b.detail, p, 0.9, 0.3, hr.randf() * TAU)
			else:
				VillageProps.crate(b.detail, p, hr.randf_range(0.45, 0.7), hr.randf() * 0.4)
	if enterable:
		BuildingMesh._floor(b, w, d, t, false)
		BuildingMesh._ceiling(b, w, d, t, STOREY - 0.05, TIMBER)
		VillageProps.furnish(b, h, hr, t)
	b.pop()


## Door (ground floor front), windows on the front and back of every storey,
## and on the ends of a few.
static func _holes(h: Dictionary, side: int, storey: int, length: float, rng: RandomNumberGenerator) -> Array:
	var holes: Array = []
	var door_u := float(h["door"])
	var door_w := float(h["door_w"])
	if side == 0 and storey == 0:
		holes.append(Rect2(door_u, 0.0, door_w, ArchKit.DOOR_H + (0.15 if door_w > 1.0 else 0.0)))
		if String(h["role"]) == "shop" and length >= 4.0:
			var u := 1.0 if door_u > length * 0.5 else length - 2.6
			holes.append(Rect2(u, 0.7, 1.6, 1.4))
			return holes
	if side >= 2 and (rng.randf() < 0.6 or length < 4.0):
		return holes
	var i := 1
	while i < int(length) - 1:
		var u := float(i) + 0.5
		if side == 0 and storey == 0 and absf(u - (door_u + door_w * 0.5)) < door_w * 0.5 + 0.9:
			i += 1
			continue
		if rng.randf() < 0.7:
			holes.append(Rect2(u - 0.35, 0.95, 0.7, 1.05))
			i += 2
		else:
			i += 1
	return holes


static func _roof(b: ArchBuild, h: Dictionary, w: float, dd: float, zc: float, y: float, rng: RandomNumberGenerator) -> void:
	var kind := String(h["roof"])
	var tint: Color = h["roof_tint"]
	var m := b.shell
	b.push(Transform3D(Basis.IDENTITY, Vector3(0, 0, zc)))
	match kind:
		"gable":
			var pitch := rng.randf_range(34.0, 48.0)
			var rise := dd * 0.5 * tan(deg_to_rad(pitch))
			var spec_m: Array = ScumportPlan.WALLS[int(h["mats"][-1])]
			for side in [2, 3]:
				b.push(ArchKit.side_frame(side, w, dd))
				ArchKit.gable(m, dd, y, rise, 0.22, spec_m[0], spec_m[1], 0.9)
				b.pop()
			_slab_roof(b, w, dd, y, pitch, L.SHINGLE if rng.randf() < 0.6 else L.SLATE, tint)
			if rng.randf() < 0.5:
				_patches(b, w, dd, y, rise, rng)
		"shed":
			# A mono-pitch roof of rusted sheet iron, falling to the front.
			var hi := y + rng.randf_range(1.0, 1.8)
			var lo := y + 0.15
			var e := 0.35
			var a0 := Vector3(-w * 0.5 - 0.2, lo - e * 0.3, dd * 0.5 + e)
			var a1 := Vector3(w * 0.5 + 0.2, lo - e * 0.3, dd * 0.5 + e)
			var b1 := Vector3(w * 0.5 + 0.2, hi, -dd * 0.5 - 0.2)
			var b0 := Vector3(-w * 0.5 - 0.2, hi, -dd * 0.5 - 0.2)
			m.mat(L.IRON, Color(0.46, 0.33, 0.25) * rng.randf_range(0.8, 1.15), 1.0)
			var slope := (b0 - a0).length()
			m.quad(a0, a1, b1, b0, Vector2(0, 0), Vector2(w, 0), Vector2(w, -slope), Vector2(0, -slope))
			m.quad(b0 + Vector3(0, -0.04, 0), b1 + Vector3(0, -0.04, 0), a1 + Vector3(0, -0.04, 0), a0 + Vector3(0, -0.04, 0),
					Vector2(0, 0), Vector2(w, 0), Vector2(w, slope), Vector2(0, slope))
			# Corrugation ribs.
			for k in int(w / 0.5):
				var x := -w * 0.5 + 0.25 + k * 0.5
				m.beam(Vector3(x, lo - e * 0.3 + 0.03, dd * 0.5 + e), Vector3(x, hi + 0.03, -dd * 0.5 - 0.2), 0.05, 0.04)
			var spec_m: Array = ScumportPlan.WALLS[int(h["mats"][-1])]
			m.mat(spec_m[0], spec_m[1], 0.9)
			for sx: float in [-w * 0.5, w * 0.5]:
				var nrm := Vector3(signf(sx), 0, 0)
				m.tri(Vector3(sx, y, dd * 0.5), Vector3(sx, y, -dd * 0.5), Vector3(sx, hi, -dd * 0.5), Vector2(0, 0), Vector2(dd, 0), Vector2(dd, y - hi), nrm)
				m.tri(Vector3(sx, y, -dd * 0.5), Vector3(sx, y, dd * 0.5), Vector3(sx, hi, -dd * 0.5), Vector2(0, 0), Vector2(dd, 0), Vector2(0, y - hi), -nrm)
			m.box(Vector3(0, (y + hi) * 0.5, -dd * 0.5 + 0.08), Vector3(w, hi - y, 0.16), 1)
		_:
			# Flat tarred roof behind a low parapet, a water butt and junk on it.
			m.mat(L.FLAT, Color(0.12, 0.11, 0.1), 0.6)
			m.box(Vector3(0, y + 0.05, 0), Vector3(w, 0.12, dd), 0)
			m.mat(L.BOARDS, TIMBER * 1.3, 0.9)
			for sz: float in [-1.0, 1.0]:
				m.box(Vector3(0, y + 0.35, sz * (dd * 0.5 - 0.08)), Vector3(w, 0.6, 0.16), 0)
			for sx: float in [-1.0, 1.0]:
				m.box(Vector3(sx * (w * 0.5 - 0.08), y + 0.35, 0), Vector3(0.16, 0.6, dd), 2)
			VillageProps.barrel(b.detail, Vector3(rng.randf_range(-w * 0.3, w * 0.3), y + 0.1, -dd * 0.2), 1.2, 0.5, 0.0)
			VillageProps.crate(b.detail, Vector3(rng.randf_range(-w * 0.3, w * 0.3), y + 0.1, dd * 0.2), 0.7, rng.randf())
	# A stove pipe, smoking now and then.
	if rng.randf() < 0.55:
		var p := Vector3(rng.randf_range(-w * 0.3, w * 0.3), y, rng.randf_range(-dd * 0.25, 0.0))
		m.mat(L.IRON, Color(0.2, 0.18, 0.17), 0.8)
		m.cylinder(p, p + Vector3(0, 3.0, 0), 0.16, 0.16, 7)
		m.cylinder(p + Vector3(0, 3.0, 0), p + Vector3(0, 3.25, 0), 0.26, 0.2, 7)
		if rng.randf() < 0.5:
			b.add_smoke(p + Vector3(0, 3.4, 0), 0.5)
	b.pop()


## A cheap pitched roof: two slabs and a ridge board (hundreds of these in one town).
static func _slab_roof(b: ArchBuild, w: float, dd: float, y: float, pitch_deg: float, layer: int, tint: Color) -> void:
	var m := b.shell
	var pitch := deg_to_rad(pitch_deg)
	var eave := 0.4
	var run := dd * 0.5 + eave
	var slope := run / cos(pitch)
	var rise := dd * 0.5 * tan(pitch)
	for s: float in [1.0, -1.0]:
		var mid := Vector3(0, y + rise - run * 0.5 * tan(pitch) + 0.12, s * run * 0.5)
		m.mat(layer, tint, 0.3)
		m.push(Transform3D(Basis(Vector3.RIGHT, s * pitch), mid))
		m.box(Vector3.ZERO, Vector3(w + 0.5, 0.12, slope), 2)
		m.pop()
	m.mat(L.TIMBER, TIMBER, 0.8)
	m.box(Vector3(0, y + rise + 0.2, 0), Vector3(w + 0.55, 0.16, 0.22), 0)


## A cheap casement: a dark or lit pane in a plain frame, sometimes boarded up.
static func _window(b: ArchBuild, r: Rect2, t: float, lit: bool, boarded: bool) -> void:
	var m := b.shell
	var c := r.get_center()
	m.mat(L.TIMBER, TIMBER * 1.25, 0.6)
	m.box(Vector3(c.x, r.position.y - 0.05, -0.02), Vector3(r.size.x + 0.2, 0.1, 0.18), 0)
	m.box(Vector3(c.x, r.end.y + 0.05, -0.04), Vector3(r.size.x + 0.2, 0.1, 0.14), 0)
	m.box(Vector3(c.x, c.y, -t * 0.6), Vector3(0.05, r.size.y, 0.05), 1)
	if boarded:
		m.mat(L.BOARDS, Color(0.4, 0.34, 0.27), 1.0)
		m.push(Transform3D(Basis(Vector3.BACK, 0.12), Vector3(c.x, c.y, 0.03)))
		m.box(Vector3.ZERO, Vector3(r.size.x + 0.3, 0.22, 0.04), 0)
		m.pop()
	m.mat(L.GLASS, Color(1, 1, 1), 1.0 if lit else 0.0)
	m.rect(Vector3(r.position.x, r.position.y, -t * 0.65), Vector3.RIGHT, Vector3.UP, r.size.x, r.size.y)


## Sheet-iron and plank patches nailed over a pitched roof.
static func _patches(b: ArchBuild, w: float, dd: float, y: float, rise: float, rng: RandomNumberGenerator) -> void:
	var m := b.detail
	for k in rng.randi_range(1, 3):
		var x := rng.randf_range(-w * 0.35, w * 0.35)
		var f := rng.randf_range(0.2, 0.7)
		var p := Vector3(x, y + rise * f + 0.18, dd * 0.5 * (1.0 - f))
		var nrm := Vector3(0, dd * 0.5, rise).normalized()
		m.mat(L.IRON if k % 2 == 0 else L.BOARDS, Color(0.5, 0.36, 0.26) if k % 2 == 0 else Color(0.5, 0.44, 0.36), 1.0)
		m.push(Transform3D(Basis(Vector3.RIGHT, nrm.cross(Vector3.RIGHT).normalized() * -1.0, nrm).orthonormalized(), p))
		m.box(Vector3.ZERO, Vector3(rng.randf_range(0.8, 1.6), rng.randf_range(0.6, 1.2), 0.04), 0)
		m.pop()


# --- Market, harbour, streets -----------------------------------------------------------------

static func _market(b: ArchBuild, prop: Dictionary, top: float, rng: RandomNumberGenerator) -> void:
	var cloths := [Color(0.5, 0.18, 0.15), Color(0.25, 0.35, 0.32), Color(0.55, 0.45, 0.25), Color(0.32, 0.25, 0.38), Color(0.42, 0.3, 0.2)]
	for st: Dictionary in prop["stalls"]:
		var p := (st["at"] as Vector3) - b.origin
		p.y = top
		VillageProps.stall(b, p, float(st["yaw"]), rng, cloths[rng.randi() % cloths.size()], Color(0.6, 0.5, 0.35))
	var plaza: Rect2i = prop["plaza"]
	for i in 14:
		var p := Vector3(plaza.position.x + rng.randf_range(0.8, plaza.size.x - 0.8), top, plaza.position.y + rng.randf_range(0.8, plaza.size.y - 0.8)) - Vector3(b.origin.x, 0, b.origin.z)
		var c := Vector3(plaza.get_center().x, top, plaza.get_center().y) - Vector3(b.origin.x, 0, b.origin.z)
		if Vector2(p.x - c.x, p.z - c.z).length() < 3.5:
			continue
		if rng.randf() < 0.5:
			VillageProps.barrel(b.detail, p, 0.9, 0.32, rng.randf() * TAU)
		elif rng.randf() < 0.5:
			VillageProps.sack(b.detail, p, 0.7, rng.randf() * TAU)
		else:
			VillageProps.crate(b.detail, p, rng.randf_range(0.5, 0.8), rng.randf())


static func _harbour(b: ArchBuild, prop: Dictionary, top: float, rng: RandomNumberGenerator) -> void:
	var m := b.shell
	var water := float(WorldGen.SEA_LEVEL) + 0.85 - b.origin.y
	for pr: Dictionary in prop["piers"]:
		var a := Vector3(float(pr["x0"]), top, float(pr["z"]) - 1.0) - Vector3(b.origin.x, 0, b.origin.z)
		var length := float(pr["x1"]) - float(pr["x0"])
		m.mat(L.BOARDS, PLANK * 0.95, 0.3)
		m.box(Vector3(a.x + length * 0.5, top - 0.1, a.z + 1.5), Vector3(length, 0.2, 3.0), 0)
		m.mat(L.TIMBER, TIMBER, 0.9)
		for k in int(length / 3.0) + 1:
			for s: float in [0.15, 2.85]:
				var p := Vector3(a.x + k * 3.0 + 0.2, 0, a.z + s)
				var g := b.ground(p)
				m.cylinder(Vector3(p.x, g - 0.6, p.z), Vector3(p.x, top + 0.6, p.z), 0.17, 0.15, 6)
		# Skiffs tied along the pier.
		for k in 2:
			var bp := Vector3(a.x + 4.0 + k * 8.0 + rng.randf() * 2.0, water, a.z - 1.5 if k == 0 or not pr["hulk"] else a.z - 1.5)
			VillageGreen._rowboat(b, bp, PI * 0.5 + rng.randf_range(-0.15, 0.15))
		if pr["hulk"]:
			_hulk(b, Vector3(float(pr["x0"]) + 12.0, 0, float(pr["z"]) + 5.5) - Vector3(b.origin.x, 0, b.origin.z), top, rng)
		else:
			_crane(b, a + Vector3(1.5, 0, 1.5), top)
	# Warehouses get a hoist beam over their doors.


static func _hulk(b: ArchBuild, c: Vector3, top: float, rng: RandomNumberGenerator) -> void:
	var m := b.shell
	var hl := 10.8
	var hw := 3.4
	var keel := top - 3.2
	m.mat(L.BOARDS, Color(0.3, 0.25, 0.21), 1.0)
	# Hull: rings of planking from the keel up to the gunwale, pointed both ends.
	var rings := 12
	for i in rings:
		var f0 := -1.0 + 2.0 * float(i) / rings
		var f1 := -1.0 + 2.0 * float(i + 1) / rings
		for s: float in [-1.0, 1.0]:
			var w0 := hw * sqrt(maxf(0.0, 1.0 - pow(absf(f0), 2.4)))
			var w1 := hw * sqrt(maxf(0.0, 1.0 - pow(absf(f1), 2.4)))
			var p0 := c + Vector3(f0 * hl, keel, 0)
			var p1 := c + Vector3(f1 * hl, keel, 0)
			var q0 := c + Vector3(f0 * hl, top + 1.0, s * w0)
			var q1 := c + Vector3(f1 * hl, top + 1.0, s * w1)
			var nrm := Vector3(0, -0.3, s).normalized()
			if s > 0.0:
				m.quad(p0, p1, q1, q0, Vector2(0, 0), Vector2(hl * 0.17, 0), Vector2(hl * 0.17, -4), Vector2(0, -4), nrm)
			else:
				m.quad(p1, p0, q0, q1, Vector2(0, 0), Vector2(hl * 0.17, 0), Vector2(hl * 0.17, -4), Vector2(0, -4), nrm)
			# The deck.
			m.quad(c + Vector3(f0 * hl, top, 0), c + Vector3(f1 * hl, top, 0), c + Vector3(f1 * hl, top, s * w1 * 0.95), c + Vector3(f0 * hl, top, s * w0 * 0.95),
					Vector2(f0 * hl, 0), Vector2(f1 * hl, 0), Vector2(f1 * hl, w1), Vector2(f0 * hl, w0), Vector3.UP)
			m.quad(c + Vector3(f0 * hl, top, s * w0 * 0.95), c + Vector3(f1 * hl, top, s * w1 * 0.95), c + Vector3(f1 * hl, top, 0), c + Vector3(f0 * hl, top, 0),
					Vector2(f0 * hl, 0), Vector2(f1 * hl, 0), Vector2(f1 * hl, w1), Vector2(f0 * hl, w0), Vector3.UP)
	# Stumps of masts, a deckhouse, a torn sail and rigging.
	m.mat(L.TIMBER, TIMBER, 0.9)
	m.cylinder(c + Vector3(-3.0, top, 0), c + Vector3(-3.0, top + 11.0, 0), 0.32, 0.22, 8)
	m.cylinder(c + Vector3(4.0, top, 0), c + Vector3(4.0, top + 6.5, 0), 0.3, 0.26, 8)
	m.beam(c + Vector3(-3.0, top + 8.5, -3.2), c + Vector3(-3.0, top + 8.5, 3.2), 0.18, 0.18)
	m.mat(L.BOARDS, Color(0.36, 0.3, 0.25), 1.0)
	m.box(c + Vector3(7.0, top + 1.1, 0), Vector3(3.0, 2.2, 3.4))
	b.detail.mat(L.LINEN, Color(0.55, 0.5, 0.42), 1.0)
	b.detail.push(Transform3D(Basis(Vector3.UP, 0.1 + rng.randf() * 0.2), c + Vector3(-3.3, top + 6.5, 0)))
	b.detail.box(Vector3.ZERO, Vector3(0.04, 3.8, 5.0), 1)
	b.detail.pop()
	b.detail.mat(L.LINEN, ROPE, 0.6)
	for s: float in [-1.0, 1.0]:
		b.detail.beam(c + Vector3(-3.0, top + 10.8, 0), c + Vector3(-8.5, top + 1.0, s * 2.6), 0.04, 0.04)
		b.detail.beam(c + Vector3(-3.0, top + 10.8, 0), c + Vector3(2.0, top + 1.0, s * 3.2), 0.04, 0.04)
	b.add_light(c + Vector3(7.0, top + 2.6, 2.0), Color(1.0, 0.6, 0.3), 9.0, 0.9, false)


static func _crane(b: ArchBuild, p: Vector3, top: float) -> void:
	var m := b.shell
	m.mat(L.TIMBER, TIMBER, 0.9)
	var base := Vector3(p.x, top, p.z)
	m.beam(base, base + Vector3(0, 7.5, 0), 0.4, 0.4)
	for s: float in [-1.0, 1.0]:
		m.beam(base + Vector3(s * 1.2, 0, 0), base + Vector3(0, 3.0, 0), 0.16, 0.16)
	m.beam(base + Vector3(0.6, 7.0, 0), base + Vector3(-5.5, 7.8, 0), 0.3, 0.3)
	m.beam(base + Vector3(0, 4.5, 0), base + Vector3(-3.2, 7.4, 0), 0.16, 0.16)
	b.detail.mat(L.LINEN, ROPE, 0.6)
	b.detail.beam(base + Vector3(-5.3, 7.6, 0), base + Vector3(-5.3, 3.2, 0), 0.03, 0.03)
	VillageProps.crate(b.detail, base + Vector3(-5.3, 2.4, 0), 0.9, 0.3)


## Lantern posts, washing lines strung across the alleys, crates and barrels.
static func _streets(b: ArchBuild, prop: Dictionary, top: float, rng: RandomNumberGenerator) -> void:
	var town: Dictionary = prop["town"]
	var lit := 0
	for lw: Vector3 in prop["lamps"]:
		var p := lw - b.origin
		p.y = top
		var off := Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		b.shell.mat(L.TIMBER, TIMBER, 0.9)
		b.shell.cylinder(p + off, p + off + Vector3(0, 3.0, 0), 0.08, 0.07, 6)
		b.shell.beam(p + off + Vector3(0, 2.9, 0), p + off + Vector3(0.6, 2.9, 0), 0.07, 0.07)
		b.detail.mat(L.IRON, Color(0.2, 0.18, 0.16), 0.6)
		b.detail.box(p + off + Vector3(0.6, 2.55, 0), Vector3(0.3, 0.4, 0.3))
		b.detail.mat(L.GLASS, Color(1, 1, 1), 1.0)
		b.detail.box(p + off + Vector3(0.6, 2.55, 0), Vector3(0.24, 0.32, 0.32))
		if lit % 2 == 0:
			b.add_light(p + off + Vector3(0.6, 2.4, 0), Color(1.0, 0.62, 0.28), 8.0, 1.0, false)
		lit += 1
	# Washing lines across alleys between upper windows; clutter at the walls.
	var cloth := [Color(0.75, 0.72, 0.62), Color(0.55, 0.2, 0.16), Color(0.3, 0.38, 0.5), Color(0.62, 0.55, 0.3), Color(0.4, 0.45, 0.35)]
	var x0: int = town["x0"]
	var z0: int = town["z0"]
	for i in 220:
		var x := x0 + rng.randi_range(1, int(town["nx"]) - 2)
		var z := z0 + rng.randi_range(1, int(town["nz"]) - 2)
		if ScumportPlan.cell(town, x, z) != ScumportPlan.T_STREET:
			continue
		# Walk both ways along x and z to the house walls.
		for axis: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			var a := Vector2i(x, z)
			var c := Vector2i(x, z)
			while ScumportPlan.walkable(ScumportPlan.cell(town, a.x, a.y)) and (c - a).length() < 6:
				a -= axis
			while ScumportPlan.walkable(ScumportPlan.cell(town, c.x, c.y)) and (c - a).length() < 6:
				c += axis
			if ScumportPlan.cell(town, a.x, a.y) != ScumportPlan.T_LOT or ScumportPlan.cell(town, c.x, c.y) != ScumportPlan.T_LOT:
				continue
			var span := (c - a).length()
			if span < 2 or span > 5:
				continue
			var hy := top + rng.randf_range(3.6, 6.2)
			var pa := Vector3(a.x + 1.0 if axis.x != 0 else x + 0.5, hy, a.y + 1.0 if axis.y != 0 else z + 0.5) - Vector3(b.origin.x, 0, b.origin.z)
			var pc := Vector3(c.x if axis.x != 0 else x + 0.5, hy, c.y if axis.y != 0 else z + 0.5) - Vector3(b.origin.x, 0, b.origin.z)
			b.detail.mat(L.LINEN, ROPE, 0.6)
			b.detail.beam(pa, pc, 0.025, 0.025)
			var n := rng.randi_range(2, 4)
			for k in n:
				var f := (k + 0.5) / n
				var q := pa.lerp(pc, f) + Vector3(0, -0.06 - 0.25 * sin(PI * f), 0)
				b.detail.mat(L.LINEN, cloth[rng.randi() % cloth.size()], 0.7)
				var size := Vector3(0.05, rng.randf_range(0.5, 0.9), rng.randf_range(0.4, 0.8))
				if axis.y != 0:
					size = Vector3(size.z, size.y, 0.05)
				b.detail.box(q - Vector3(0, size.y * 0.5, 0), size, 1)
			break
		if rng.randf() < 0.5:
			var p := Vector3(x + 0.5, top, z + 0.5) - Vector3(b.origin.x, 0, b.origin.z)
			if rng.randf() < 0.5:
				VillageProps.barrel(b.detail, p, 0.9, 0.3, rng.randf() * TAU, rng.randf() < 0.2)
			else:
				VillageProps.crate(b.detail, p, rng.randf_range(0.45, 0.75), rng.randf())


# --- Far silhouette -------------------------------------------------------------------------

static func _far(b: ArchBuild, prop: Dictionary, top: float) -> void:
	var m := b.far
	for h: Dictionary in prop["houses"]:
		var lot: Rect2i = h["lot"]
		var hh := float(h["wall_h"])
		var spec_m: Array = ScumportPlan.WALLS[int(h["mats"][0])]
		m.mat(spec_m[0], spec_m[1], 0.6)
		var c := Vector3(lot.get_center().x, top + hh * 0.5, lot.get_center().y) - Vector3(b.origin.x, 0, b.origin.z)
		m.box(c, Vector3(lot.size.x, hh, lot.size.y), 1, 8)
		m.mat(L.SHINGLE, h.get("roof_tint", Color(0.35, 0.3, 0.26)), 0.6)
		m.box(c + Vector3(0, hh * 0.5 + 0.6, 0), Vector3(lot.size.x + 0.4, 1.2, lot.size.y + 0.4), 0, 8)
