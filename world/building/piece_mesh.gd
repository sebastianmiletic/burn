class_name PieceMesh
extends RefCounted
## Modelled building pieces (BuildPieces) in the village architecture style:
## the same ArchMesh layers, ArchKit walls, timber framing, windows, door
## leaves and roof slopes, drawn with the one shared architecture material.
##
##   PieceMesh.get_model(kind, mat) -> {
##       "mesh": ArrayMesh (piece frame: cell box from (0,0,0) to the piece size),
##       "leaves": [{mesh, pivot: Vector3, axis: Vector3, open: float}],  # doors, lids
##       "fires": [Vector3], "lights": [Vector3], "aabb": AABB}
## Built once per (kind, material) and cached. Main thread.

const L = ArchMaterials.L

const OAK := Color(0.62, 0.47, 0.34)
const TIMBER := Color(0.52, 0.4, 0.31)
const STONE := Color(1.0, 0.95, 0.87)
const PLASTER := Color(0.95, 0.9, 0.8)
const IRON := Color(0.62, 0.62, 0.64)
const BRICK := Color(0.82, 0.46, 0.36)

## Window, door and slit openings in a 2 x 3 wall (wall frame u along x).
const WINDOW := Rect2(0.5, 0.95, 1.0, 1.1)
const ARCH := Rect2(0.55, 0.85, 0.9, 1.6)
const SLIT := Rect2(0.9, 0.8, 0.2, 1.4)
const DOOR := Rect2(0.42, 0.0, 1.16, 2.18)

static var _cache := {}


static func get_model(kind: String, mat: String) -> Dictionary:
	var key := kind + "|" + mat
	if _cache.has(key):
		return _cache[key]
	var b := ArchBuild.new(null, Vector3.ZERO, hash(key))
	var out := {"leaves": [], "fires": [], "lights": []}
	_emit(b, kind, mat, out)
	var all := ArchMesh.new()
	for m in [b.shell, b.detail, b.interior]:
		all.append(m)
	for f: Dictionary in b.fires:
		out["fires"].append(f["pos"])
	for l: Dictionary in b.lights:
		out["lights"].append(l["pos"])
	out["mesh"] = all.to_mesh(ArchMaterials.main())
	var box := all.aabb()
	for leaf: Dictionary in out["leaves"]:
		var lm: ArchMesh = leaf["arch"]
		leaf["mesh"] = lm.to_mesh(ArchMaterials.main())
		if not lm.is_empty():
			var la := lm.aabb()
			box = box.merge(AABB(la.position + leaf["pivot"], la.size))
		leaf.erase("arch")
	out["aabb"] = box
	_cache[key] = out
	return out


static func _leaf(out: Dictionary, pivot: Vector3, axis: Vector3, open: float) -> ArchMesh:
	var m := ArchMesh.new()
	out["leaves"].append({"arch": m, "pivot": pivot, "axis": axis, "open": open})
	return m


static func _emit(b: ArchBuild, kind: String, mat: String, out: Dictionary) -> void:
	match kind:
		"foundation":
			_foundation(b, mat)
		"floor":
			_floor(b, mat, 2.0, 2.0)
		"wall":
			_wall(b, mat, 2.0, 3.0, [])
		"wall_half":
			_wall(b, mat, 1.0, 3.0, [])
		"wall_low":
			_wall(b, mat, 2.0, 1.0, [])
			_coping(b, mat, 2.0, 1.0)
		"wall_gable":
			_gable(b, mat)
		"window":
			_wall(b, mat, 2.0, 3.0, [WINDOW])
			_in_wall(b, mat)
			ArchKit.window(b, WINDOW, thickness(mat), TIMBER * 1.1, _sill_layer(mat), _sill_tint(mat), false, true, Color(0, 0, 0, 0))
			b.pop()
		"window_shutter":
			_wall(b, mat, 2.0, 3.0, [WINDOW])
			_in_wall(b, mat)
			_shuttered(b, mat)
			b.pop()
		"window_arch":
			_wall(b, mat, 2.0, 3.0, [ARCH])
			_in_wall(b, mat)
			_arched(b, mat)
			b.pop()
		"window_slit":
			_wall(b, mat, 2.0, 3.0, [SLIT])
			_in_wall(b, mat)
			b.shell.mat(_sill_layer(mat), _sill_tint(mat), 0.4)
			b.shell.box(Vector3(SLIT.get_center().x, SLIT.position.y - 0.05, -thickness(mat) * 0.5), Vector3(0.5, 0.1, thickness(mat) + 0.1), 0)
			b.shell.box(Vector3(SLIT.get_center().x, SLIT.end.y + 0.06, -thickness(mat) * 0.5), Vector3(0.6, 0.12, thickness(mat) + 0.06), 0)
			b.pop()
		"doorway", "door":
			_wall(b, mat, 2.0, 3.0, [DOOR])
			_in_wall(b, mat)
			_door_frame(b, mat)
			b.pop()
			if kind == "door":
				var t := thickness(mat)
				var leaf := _leaf(out, Vector3(DOOR.position.x + 0.02, 0.02, 0.5 - t * 0.5 + 0.05), Vector3.UP, 1.7)
				ArchKit._leaf(leaf, DOOR.size.x - 0.04, DOOR.size.y - 0.04, 1.0, OAK * Color(0.95, 0.88, 0.8))
				if MATS_IRON.has(mat):
					_iron_bands(leaf, DOOR.size.x - 0.04, DOOR.size.y - 0.04)
		"trapdoor":
			_trapdoor(b, mat, out)
		"pillar":
			_pillar(b, mat)
		"beam":
			_beam(b, mat)
		"stairs":
			_stairs(b, mat)
		"fence":
			_fence(b, mat, false, out)
		"gate":
			_fence(b, mat, true, out)
		"roof":
			_slope(b, mat, Vector3(0, 0, 1), Vector3(0, 1, 0), 2.0)
		"roof_low":
			_slope(b, mat, Vector3(0, 0, 2), Vector3(0, 1, 0), 2.0)
		"roof_peak":
			_slope(b, mat, Vector3(0, 0, 2), Vector3(0, 1, 1), 2.0)
			b.push(Transform3D(Basis(Vector3.UP, PI), Vector3(2, 0, 2)))
			_slope(b, mat, Vector3(0, 0, 2), Vector3(0, 1, 1), 2.0)
			b.pop()
			_ridge(b, mat)
		"roof_corner":
			_hip_corner(b, mat)
		"roof_flat":
			_flat_roof(b, mat)
		"table":
			VillageProps.table(b.shell, Vector3(1.0, 0.0, 0.5), Vector2(1.8, 0.85), 0.0, null, false)
		"chair":
			_chair(b.shell)
		"bench":
			VillageProps.bench(b.shell, Vector3(1.0, 0.0, 0.55), 1.8, 0.0, true)
		"bed":
			VillageProps.bed(b.shell, Vector3(0.5, 0.0, 1.0), -PI * 0.5, Color(0.55, 0.22, 0.16))
		"shelf":
			var rng := RandomNumberGenerator.new()
			rng.seed = 41
			VillageProps.shelf(b.shell, Vector3(1.0, -1.05, -0.32), 0.0, 1.8, rng)
		"wall_torch":
			_wall_torch(b)
		"lantern_post":
			VillageProps.lamp_post(b, Vector3(0.5, 0.0, 0.3), 0.0)
		"chest", "chest_iron":
			_chest(b.shell, _leaf(out, Vector3(0.5, 0.5, 0.21), Vector3.RIGHT, -1.85), kind == "chest_iron")
		"barrel":
			_barrel(b.shell, _leaf(out, Vector3(0.5, 0.9, 0.18), Vector3.RIGHT, -1.6))


const MATS_IRON := {"ironwood": true, "reinforced": true}


# --- Material looks ----------------------------------------------------------------

static func thickness(mat: String) -> float:
	match mat:
		"wood":
			return 0.3
		"plank", "ironwood", "plaster":
			return 0.24
	return 0.4


static func _layer(mat: String) -> int:
	match mat:
		"wood":
			return L.TIMBER
		"plank", "ironwood":
			return L.BOARDS
		"shingle":
			return L.SHINGLE
		"plaster":
			return L.PLASTER
		"stone":
			return L.RUBBLE
		"cobble":
			return L.COBBLE
		"thatch":
			return L.THATCH
		"slate":
			return L.SLATE
	return L.ASHLAR


static func _tint(mat: String) -> Color:
	match mat:
		"wood":
			return TIMBER * Color(1.15, 1.08, 1.0)
		"plank", "shingle":
			return OAK * Color(1.12, 1.06, 1.0)
		"ironwood":
			return OAK * Color(0.85, 0.8, 0.76)
		"plaster":
			return PLASTER
		"brick":
			return BRICK
		"reinforced":
			return Color(0.86, 0.86, 0.88)
		"cobble":
			return Color(0.88, 0.86, 0.83)
	return STONE


static func _sill_layer(mat: String) -> int:
	return L.TIMBER if BuildPieces.MATS[mat]["family"] == "wood" else L.ASHLAR


static func _sill_tint(mat: String) -> Color:
	return TIMBER if BuildPieces.MATS[mat]["family"] == "wood" else STONE * 0.95


## Scales the UVs emitted since `from` (smaller bricks than the ashlar tile).
static func _scale_uv(m: ArchMesh, from: int, k: float) -> void:
	for i in range(from, m.uvs.size()):
		m.uvs[i] *= k


# --- Walls ----------------------------------------------------------------------------

## Enters the wall frame of a wall centred in its cell row (outer face +z).
static func _in_wall(b: ArchBuild, mat: String) -> void:
	b.push(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.5 + thickness(mat) * 0.5)))


## A wall of `length` x `height` with holes (wall frame rects), dressed by material.
static func _wall(b: ArchBuild, mat: String, length: float, height: float, holes: Array) -> void:
	var t := thickness(mat)
	_in_wall(b, mat)
	var m := b.shell
	var layer := _layer(mat)
	var tint := _tint(mat)
	match mat:
		"wood":
			_log_wall(m, length, height, t, holes)
		"plaster":
			ArchKit.wall(m, length, 0.0, height, t, holes, L.PLASTER, tint, 0.35, L.PLASTER, tint * Color(0.97, 0.95, 0.92))
			var rng := RandomNumberGenerator.new()
			rng.seed = int(length * 10 + height)
			ArchKit.timber_frame(m, length, height, holes, true, rng, TIMBER, 0.0, true)
			m.push(Transform3D(Basis(Vector3.UP, PI), Vector3(length, 0, -t)))
			ArchKit.timber_frame(m, length, height, holes, true, rng, TIMBER, 0.0, length > 1.5)
			m.pop()
		"plank", "ironwood":
			ArchKit.wall(m, length, 0.0, height, t, holes, L.BOARDS, tint, 0.3, L.BOARDS, tint * Color(0.92, 0.88, 0.85))
			m.mat(L.TIMBER, TIMBER, 0.3)
			for u: float in [0.08, length - 0.08]:
				m.box(Vector3(u, height * 0.5, -t * 0.5), Vector3(0.16, height, t + 0.06), 1)
			m.box(Vector3(length * 0.5, height - 0.07, -t * 0.5), Vector3(length, 0.14, t + 0.05), 0)
			m.box(Vector3(length * 0.5, 0.07, -t * 0.5), Vector3(length, 0.14, t + 0.05), 0)
			if mat == "ironwood":
				m.mat(L.IRON, IRON, 0.0)
				for v: float in [0.45, height * 0.5, height - 0.45]:
					if v > height - 0.2:
						continue
					for r in ArchKit.solid_rects(0.0, length, v - 0.05, v + 0.05, holes):
						m.box(Vector3(r.get_center().x, v, 0.012), Vector3(r.size.x, 0.1, 0.02), 0)
						m.box(Vector3(r.get_center().x, v, -t - 0.012), Vector3(r.size.x, 0.1, 0.02), 0)
		_:
			var start := m.uvs.size()
			ArchKit.wall(m, length, 0.0, height, t, holes, layer, tint, 0.3, layer, tint * Color(0.92, 0.9, 0.88))
			if mat == "brick":
				_scale_uv(m, start, 2.6)
			if mat == "reinforced":
				m.mat(L.IRON, IRON * 0.85, 0.0)
				for v: float in [0.35, height - 0.3]:
					for r in ArchKit.solid_rects(0.0, length, v - 0.06, v + 0.06, holes):
						m.box(Vector3(r.get_center().x, v, 0.015), Vector3(r.size.x, 0.12, 0.03), 0)
						m.box(Vector3(r.get_center().x, v, -t - 0.015), Vector3(r.size.x, 0.12, 0.03), 0)
				for u: float in [0.06, length - 0.06]:
					m.box(Vector3(u, height * 0.5, -t * 0.5), Vector3(0.1, height, t + 0.06), 1)
	b.pop()


## Stacked round logs with notched, overhanging ends; openings get plank reveals.
static func _log_wall(m: ArchMesh, length: float, height: float, t: float, holes: Array) -> void:
	var n := maxi(1, roundi(height / 0.28))
	var r := height / n * 0.5
	m.mat(L.TIMBER, TIMBER * Color(1.15, 1.08, 1.0), 0.35)
	# A thin core keeps the chinks between logs closed.
	ArchKit.wall(m, length, 0.0, height, t * 0.6, holes, L.TIMBER, TIMBER * 0.7, 0.4, L.TIMBER, TIMBER * 0.7, 0.0, -1.0, false)
	m.push(Transform3D(Basis.IDENTITY, Vector3(0, 0, -t * 0.2)))
	m.mat(L.TIMBER, TIMBER * Color(1.15, 1.08, 1.0), 0.35)
	for i in n:
		var y := r + i * r * 2.0
		var spans := [Vector2(-0.06, length + 0.06)]
		for h: Rect2 in holes:
			if y > h.position.y and y < h.end.y:
				var next := []
				for s: Vector2 in spans:
					if h.end.x <= s.x or h.position.x >= s.y:
						next.append(s)
						continue
					if h.position.x > s.x:
						next.append(Vector2(s.x, h.position.x))
					if h.end.x < s.y:
						next.append(Vector2(h.end.x, s.y))
				spans = next
		for s: Vector2 in spans:
			if s.y - s.x > 0.05:
				var wob := sin(i * 2.7 + s.x) * 0.012
				m.cylinder(Vector3(s.x, y, -t * 0.3), Vector3(s.y, y, -t * 0.3), r * 1.08 + wob, -1.0, 8)
	m.pop()
	m.mat(L.BOARDS, OAK, 0.3)
	for h: Rect2 in holes:
		m.box(Vector3(h.position.x - 0.03, h.get_center().y, -t * 0.5), Vector3(0.06, h.size.y, t + 0.08), 1)
		m.box(Vector3(h.end.x + 0.03, h.get_center().y, -t * 0.5), Vector3(0.06, h.size.y, t + 0.08), 1)
		if h.end.y < height:
			m.box(Vector3(h.get_center().x, h.end.y + 0.04, -t * 0.5), Vector3(h.size.x + 0.12, 0.08, t + 0.08), 0)


## Cap on a low wall: a coping stone or a timber rail.
static func _coping(b: ArchBuild, mat: String, length: float, height: float) -> void:
	var t := thickness(mat)
	var m := b.shell
	if BuildPieces.MATS[mat]["family"] == "wood":
		m.mat(L.TIMBER, TIMBER, 0.3)
		m.box(Vector3(length * 0.5, height + 0.04, 0.5), Vector3(length, 0.08, t + 0.08), 0)
	else:
		m.mat(L.ASHLAR, _tint(mat) * Color(1.05, 1.03, 1.0), 0.3)
		m.box(Vector3(length * 0.5, height + 0.05, 0.5), Vector3(length, 0.1, t + 0.1), 0)


## Triangular gable infill rising along the wall from u = 0 to u = 2.
static func _gable(b: ArchBuild, mat: String) -> void:
	var t := thickness(mat)
	_in_wall(b, mat)
	var m := b.shell
	var start := m.uvs.size()
	m.mat(_layer(mat), _tint(mat), 0.3)
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(2.0, 0), Vector2(2.0, 1.0)])
	m.prism(Vector3(0, 0, -t), Vector3.RIGHT, Vector3.UP, pts, t, true, true)
	if mat == "brick":
		_scale_uv(m, start, 2.6)
	if mat == "plaster" or mat == "wood" or mat == "plank" or mat == "ironwood":
		m.mat(L.TIMBER, TIMBER, 0.3)
		for z: float in [0.02, -t - 0.02]:
			m.beam(Vector3(0.05, 0.05, z), Vector3(1.95, 0.98, z), 0.14, 0.05, Vector3.BACK, 0.01)
			m.beam(Vector3(1.93, 0.0, z), Vector3(1.93, 0.98, z), 0.14, 0.05, Vector3.BACK, 0.01)
	b.pop()


# --- Openings ---------------------------------------------------------------------------

static func _shuttered(b: ArchBuild, mat: String) -> void:
	var t := thickness(mat)
	var m := b.shell
	var r := WINDOW
	m.mat(L.TIMBER, TIMBER * 1.1, 0.25)
	var fz := -t * 0.5
	m.box(Vector3(r.position.x + 0.04, r.get_center().y, fz), Vector3(0.08, r.size.y, t + 0.04), 1)
	m.box(Vector3(r.end.x - 0.04, r.get_center().y, fz), Vector3(0.08, r.size.y, t + 0.04), 1)
	m.box(Vector3(r.get_center().x, r.end.y - 0.04, fz), Vector3(r.size.x, 0.08, t + 0.04), 0)
	# Iron bars across the opening.
	m.mat(L.IRON, IRON * 0.7, 0.0)
	for k in 3:
		var x := r.position.x + r.size.x * (k + 1) / 4.0
		m.cylinder(Vector3(x, r.position.y, fz), Vector3(x, r.end.y, fz), 0.015, -1.0, 5)
	m.mat(_sill_layer(mat), _sill_tint(mat), 0.5)
	m.box(Vector3(r.get_center().x, r.position.y - 0.045, -0.02), Vector3(r.size.x + 0.18, 0.09, 0.22), 0)
	for s: float in [-1.0, 1.0]:
		var pw := r.size.x * 0.5 + 0.02
		var cx := r.position.x - pw * 0.5 - 0.03 if s < 0.0 else r.end.x + pw * 0.5 + 0.03
		ArchKit._shutter(b.detail, Vector3(cx, r.get_center().y, 0.022), pw, r.size.y + 0.04, Color(0.3, 0.38, 0.28), s)


## Round-headed window: spandrels close the rectangular hole into an arch.
static func _arched(b: ArchBuild, mat: String) -> void:
	var t := thickness(mat)
	var m := b.shell
	var r := ARCH
	var rad := r.size.x * 0.5
	var spring := r.end.y - rad
	var cx := r.get_center().x
	var seg := 8
	var start := m.uvs.size()
	m.mat(_layer(mat), _tint(mat), 0.3)
	for side: float in [-1.0, 1.0]:
		var pts := PackedVector2Array()
		var corner := Vector2(cx + side * rad, r.end.y)
		pts.append(corner)
		for i in seg + 1:
			var a := PI * 0.5 * float(i) / seg
			pts.append(Vector2(cx + side * rad * cos(a), spring + rad * sin(a)))
		if side > 0.0:
			pts.reverse()
		m.prism(Vector3(0, 0, -t), Vector3.RIGHT, Vector3.UP, pts, t, true, true)
	if mat == "brick":
		_scale_uv(m, start, 2.6)
	# Voussoirs round the head and a projecting sill.
	m.mat(_sill_layer(mat), _sill_tint(mat), 0.35)
	for i in seg * 2:
		var a0 := PI * float(i) / (seg * 2)
		var a1 := PI * float(i + 1) / (seg * 2)
		var p0 := Vector3(cx + cos(a0) * (rad + 0.06), spring + sin(a0) * (rad + 0.06), 0.02)
		var p1 := Vector3(cx + cos(a1) * (rad + 0.06), spring + sin(a1) * (rad + 0.06), 0.02)
		m.beam(p0, p1, 0.04, 0.13, Vector3.BACK)
	m.box(Vector3(cx, r.position.y - 0.045, -0.02), Vector3(r.size.x + 0.2, 0.09, 0.22), 0)
	# Leaded glass with a frame.
	var gz := -t * 0.5
	m.mat(L.TIMBER, TIMBER, 0.2)
	m.box(Vector3(cx, (r.position.y + spring) * 0.5, gz), Vector3(0.05, spring - r.position.y, 0.06), 1)
	m.box(Vector3(cx, spring, gz), Vector3(r.size.x, 0.05, 0.06), 0)
	m.mat(L.GLASS, Color(1, 1, 1), 0.0)
	for face: float in [1.0, -1.0]:
		var z := gz + face * 0.004
		var n := Vector3(0, 0, face)
		m.quad(Vector3(r.position.x, r.position.y, z), Vector3(r.end.x, r.position.y, z), Vector3(r.end.x, spring, z), Vector3(r.position.x, spring, z),
				Vector2(r.position.x, -r.position.y), Vector2(r.end.x, -r.position.y), Vector2(r.end.x, -spring), Vector2(r.position.x, -spring), n)
		for i in seg * 2:
			var a0 := PI * float(i) / (seg * 2)
			var a1 := PI * float(i + 1) / (seg * 2)
			var c := Vector3(cx, spring, z)
			var p0 := c + Vector3(cos(a0), sin(a0), 0) * rad
			var p1 := c + Vector3(cos(a1), sin(a1), 0) * rad
			m.tri(c, p0, p1, Vector2(c.x, -c.y), Vector2(p0.x, -p0.y), Vector2(p1.x, -p1.y), n)


static func _door_frame(b: ArchBuild, mat: String) -> void:
	var t := thickness(mat)
	var m := b.shell
	var r := DOOR
	var stone := BuildPieces.MATS[mat]["family"] == "stone"
	m.mat(L.ASHLAR if stone else L.TIMBER, _sill_tint(mat) if stone else TIMBER, 0.3)
	var jw := 0.14
	m.box(Vector3(r.position.x - jw * 0.5 + 0.01, r.size.y * 0.5, -t * 0.5), Vector3(jw, r.size.y, t + 0.08), 1)
	m.box(Vector3(r.end.x + jw * 0.5 - 0.01, r.size.y * 0.5, -t * 0.5), Vector3(jw, r.size.y, t + 0.08), 1)
	m.box(Vector3(r.get_center().x, r.end.y + 0.1, -t * 0.5), Vector3(r.size.x + 0.4, 0.2, t + 0.1), 0)
	m.mat(L.ASHLAR, STONE * 0.9, 0.4)
	m.box(Vector3(r.get_center().x, 0.03, -t * 0.5), Vector3(r.size.x + 0.2, 0.06, t + 0.16), 0)


## Three iron bands with studs across a door leaf (leaf frame, hinge at x = 0).
static func _iron_bands(m: ArchMesh, w: float, h: float) -> void:
	m.mat(L.IRON, IRON * 0.8, 0.0)
	for y: float in [0.55, h * 0.5 + 0.1, h - 0.6]:
		m.box(Vector3(w * 0.5, y, 0.034), Vector3(w - 0.02, 0.08, 0.012), 0)
		for k in 5:
			m.box(Vector3(0.1 + (w - 0.2) * k / 4.0, y, 0.045), Vector3(0.03, 0.03, 0.02), 0)


static func _trapdoor(b: ArchBuild, mat: String, out: Dictionary) -> void:
	var m := b.shell
	m.mat(L.TIMBER, TIMBER, 0.3)
	for z: float in [0.04, 0.96]:
		m.box(Vector3(0.5, 0.92, z), Vector3(1.0, 0.16, 0.08), 0)
	for x: float in [0.04, 0.96]:
		m.box(Vector3(x, 0.92, 0.5), Vector3(0.08, 0.16, 0.84), 2)
	var leaf := _leaf(out, Vector3(0.5, 0.95, 0.08), Vector3.RIGHT, -1.5)
	leaf.mat(L.BOARDS, OAK * Color(1.05, 1.0, 0.95), 0.3)
	leaf.box(Vector3(0, 0.0, 0.42), Vector3(0.84, 0.05, 0.84), 2)
	leaf.mat(L.TIMBER, TIMBER, 0.3)
	for x: float in [-0.28, 0.28]:
		leaf.box(Vector3(x, -0.04, 0.42), Vector3(0.1, 0.035, 0.8), 2)
	leaf.mat(L.IRON, IRON * 0.8, 0.0)
	for x: float in [-0.3, 0.3]:
		leaf.box(Vector3(x, 0.03, 0.2), Vector3(0.06, 0.012, 0.4), 2)
	leaf.cylinder(Vector3(0, 0.03, 0.74), Vector3(0, 0.06, 0.74), 0.05, -1.0, 8)
	if mat == "ironwood":
		_iron_bands_flat(leaf)


static func _iron_bands_flat(m: ArchMesh) -> void:
	m.mat(L.IRON, IRON * 0.8, 0.0)
	for z: float in [0.15, 0.42, 0.69]:
		m.box(Vector3(0, 0.032, z), Vector3(0.82, 0.012, 0.07), 0)


# --- Frame pieces ---------------------------------------------------------------------------

static func _foundation(b: ArchBuild, mat: String) -> void:
	var m := b.shell
	if mat == "wood":
		# Log crib: heavy sill logs round a plank deck on stone pads.
		m.mat(L.RUBBLE, STONE * 0.85, 0.5)
		for x: float in [0.2, 1.8]:
			for z: float in [0.2, 1.8]:
				m.box(Vector3(x, -0.45, z), Vector3(0.45, 0.9, 0.45), 1)
		m.mat(L.TIMBER, TIMBER * Color(1.1, 1.05, 1.0), 0.4)
		for z: float in [0.16, 1.84]:
			m.cylinder(Vector3(-0.05, 0.16, z), Vector3(2.05, 0.16, z), 0.17, -1.0, 8)
		for x: float in [0.16, 1.84]:
			m.cylinder(Vector3(x, 0.5, -0.05), Vector3(x, 0.5, 2.05), 0.17, -1.0, 8)
		m.box(Vector3(1.0, 0.5, 1.0), Vector3(1.6, 0.34, 1.6), 0)
		m.mat(L.FLOOR, OAK, 0.25)
		m.box(Vector3(1.0, 0.86, 1.0), Vector3(2.0, 0.14, 2.0), 0)
		return
	var start := m.uvs.size()
	m.mat(_layer(mat), _tint(mat), 0.45)
	m.box(Vector3(1.0, -0.3, 1.0), Vector3(2.0, 2.2, 2.0), 1, 4)
	if mat == "brick":
		_scale_uv(m, start, 2.6)
	# Dressed top course and flagstones.
	m.mat(L.ASHLAR, _tint(mat) * Color(1.04, 1.02, 1.0) if mat != "brick" else STONE * 0.92, 0.3)
	m.box(Vector3(1.0, 0.88, 1.0), Vector3(2.04, 0.24, 2.04), 0)
	if mat == "reinforced":
		m.mat(L.IRON, IRON * 0.8, 0.0)
		for x: float in [0.0, 2.0]:
			for z: float in [0.0, 2.0]:
				m.box(Vector3(x, 0.25, z), Vector3(0.14, 1.1, 0.14), 1)


static func _floor(b: ArchBuild, mat: String, w: float, d: float) -> void:
	var m := b.shell
	match mat:
		"plank", "wood":
			m.mat(L.FLOOR, OAK * (Color(1.0, 0.96, 0.9) if mat == "plank" else Color(0.85, 0.8, 0.75)), 0.2)
			m.box(Vector3(w * 0.5, 0.93, d * 0.5), Vector3(w, 0.07, d), 2 if mat == "plank" else 0)
			m.mat(L.TIMBER, TIMBER, 0.3)
			for x: float in [0.25, w * 0.5, w - 0.25]:
				m.box(Vector3(x, 0.8, d * 0.5), Vector3(0.14, 0.2, d), 2)
			for z: float in [0.07, d - 0.07]:
				m.box(Vector3(w * 0.5, 0.8, z), Vector3(w, 0.2, 0.14), 0)
		_:
			var start := m.uvs.size()
			m.mat(_layer(mat), _tint(mat), 0.25)
			m.box(Vector3(w * 0.5, 0.9, d * 0.5), Vector3(w, 0.2, d), 0)
			if mat == "brick":
				_scale_uv(m, start, 2.6)
			m.mat(L.TIMBER, TIMBER, 0.3)
			for x: float in [0.3, w - 0.3]:
				m.box(Vector3(x, 0.7, d * 0.5), Vector3(0.16, 0.2, d), 2)


static func _pillar(b: ArchBuild, mat: String) -> void:
	var m := b.shell
	var c := Vector3(0.5, 0, 0.5)
	match mat:
		"wood":
			m.mat(L.TIMBER, TIMBER * Color(1.1, 1.05, 1.0), 0.35)
			m.cylinder(c, c + Vector3(0, 3.0, 0), 0.17, 0.15, 10)
			m.mat(L.RUBBLE, STONE * 0.85, 0.5)
			m.box(c + Vector3(0, 0.08, 0), Vector3(0.44, 0.16, 0.44), 1)
		"plank":
			m.mat(L.TIMBER, TIMBER, 0.3)
			m.beam(c, c + Vector3(0, 3.0, 0), 0.26, 0.26, Vector3.BACK, 0.03)
			for s: float in [-1.0, 1.0]:
				m.beam(c + Vector3(s * 0.08, 2.35, 0), c + Vector3(s * 0.48, 2.94, 0), 0.1, 0.12, Vector3.BACK, 0.01)
		_:
			var start := m.uvs.size()
			m.mat(_layer(mat), _tint(mat), 0.3)
			m.box(c + Vector3(0, 1.5, 0), Vector3(0.5, 2.6, 0.5), 1)
			if mat == "brick":
				_scale_uv(m, start, 2.6)
			m.mat(L.ASHLAR, STONE * 0.95, 0.3)
			m.box(c + Vector3(0, 0.1, 0), Vector3(0.66, 0.2, 0.66), 1)
			m.box(c + Vector3(0, 2.9, 0), Vector3(0.66, 0.2, 0.66), 1)
			if mat == "reinforced":
				m.mat(L.IRON, IRON * 0.8, 0.0)
				for y: float in [0.7, 1.5, 2.3]:
					m.box(c + Vector3(0, y, 0), Vector3(0.54, 0.08, 0.54), 1)


static func _beam(b: ArchBuild, mat: String) -> void:
	var m := b.shell
	m.mat(L.TIMBER, TIMBER * (Color(1.1, 1.05, 1.0) if mat == "wood" else Color(1, 1, 1)), 0.3)
	if mat == "wood":
		m.cylinder(Vector3(-0.02, 0.84, 0.5), Vector3(2.02, 0.84, 0.5), 0.15, -1.0, 8)
	else:
		m.beam(Vector3(0, 0.84, 0.5), Vector3(2.0, 0.84, 0.5), 0.24, 0.3, Vector3.UP, 0.03)
	if mat == "ironwood":
		m.mat(L.IRON, IRON * 0.8, 0.0)
		for x: float in [0.3, 1.0, 1.7]:
			m.box(Vector3(x, 0.84, 0.5), Vector3(0.07, 0.32, 0.26), 0)


static func _stairs(b: ArchBuild, mat: String) -> void:
	var m := b.shell
	var n := 4
	var wood := BuildPieces.MATS[mat]["family"] == "wood"
	for i in n:
		var z1 := 2.0 - i * 0.5
		var z0 := z1 - 0.5
		var top := (i + 1) * 0.25
		if wood:
			m.mat(L.FLOOR, OAK, 0.25)
			m.box(Vector3(1.0, top - 0.03, (z0 + z1) * 0.5 - 0.02), Vector3(1.9, 0.06, 0.54), 0)
			m.mat(L.BOARDS, OAK * 0.9, 0.3)
			m.box(Vector3(1.0, top - 0.14, z1 - 0.03), Vector3(1.86, 0.2, 0.04), 0)
		else:
			var start := m.uvs.size()
			m.mat(_layer(mat), _tint(mat), 0.3)
			m.box(Vector3(1.0, top * 0.5, (z0 + z1) * 0.5), Vector3(2.0, top, 0.5), 1)
			if mat == "brick":
				_scale_uv(m, start, 2.6)
			m.mat(L.ASHLAR, STONE * 0.95, 0.35)
			m.box(Vector3(1.0, top - 0.02, (z0 + z1) * 0.5 + 0.02), Vector3(2.0, 0.05, 0.52), 0)
	if wood:
		m.mat(L.TIMBER, TIMBER, 0.3)
		for x: float in [0.03, 1.97]:
			m.beam(Vector3(x, 0.0, 2.0), Vector3(x, 1.0, 0.0), 0.08, 0.26, Vector3.RIGHT, 0.01)
		m.box(Vector3(1.0, 0.5, 0.08), Vector3(2.0, 1.0, 0.12), 0)


static func _fence(b: ArchBuild, mat: String, gate: bool, out: Dictionary) -> void:
	var m := b.shell
	m.mat(L.TIMBER, TIMBER * Color(1.08, 1.04, 1.0), 0.4)
	for x: float in [0.08, 1.92]:
		if mat == "wood":
			m.cylinder(Vector3(x, 0.0, 0.5), Vector3(x, 1.22, 0.5), 0.08, 0.07, 7)
		else:
			m.beam(Vector3(x, 0.0, 0.5), Vector3(x, 1.25, 0.5), 0.14, 0.14, Vector3.BACK, 0.02)
			m.lathe(Vector3(x, 1.25, 0.5), PackedVector2Array([Vector2(0.1, 0.0), Vector2(0.0, 0.1)]), 4, true, false, PI * 0.25)
	if gate:
		for k in 2:
			var hinge_x := 0.16 if k == 0 else 1.84
			var dir := 1.0 if k == 0 else -1.0
			var leaf := _leaf(out, Vector3(hinge_x, 0.0, 0.5), Vector3.UP, 1.6 * dir)
			_gate_leaf(leaf, mat, dir)
		return
	if mat == "plank":
		m.mat(L.BOARDS, OAK * Color(1.1, 1.05, 1.0), 0.35)
		for y: float in [0.3, 0.85]:
			m.box(Vector3(1.0, y, 0.44), Vector3(1.76, 0.08, 0.05), 0)
		var k := 0
		var x := 0.22
		while x < 1.8:
			var h := 1.05 + (0.04 if k % 2 == 0 else 0.0)
			m.box(Vector3(x, h * 0.5, 0.5), Vector3(0.11, h, 0.025), 1)
			m.lathe(Vector3(x, h, 0.5), PackedVector2Array([Vector2(0.06, 0.0), Vector2(0.0, 0.07)]), 4, false, false, PI * 0.25)
			x += 0.16
			k += 1
	else:
		for y: float in [0.38, 0.86]:
			if mat == "wood":
				m.cylinder(Vector3(0.08, y, 0.5), Vector3(1.92, y + 0.02, 0.5), 0.05, -1.0, 6)
			else:
				m.beam(Vector3(0.08, y, 0.5), Vector3(1.92, y, 0.5), 0.1, 0.12, Vector3.UP, 0.01)
		if mat == "ironwood":
			m.mat(L.IRON, IRON * 0.8, 0.0)
			for x: float in [0.08, 1.92]:
				for y: float in [0.38, 0.86]:
					m.box(Vector3(x, y, 0.5), Vector3(0.18, 0.14, 0.18), 0)


static func _gate_leaf(m: ArchMesh, mat: String, dir: float) -> void:
	var w := 0.82
	m.mat(L.TIMBER, TIMBER * Color(1.08, 1.04, 1.0), 0.35)
	m.box(Vector3(w * 0.5 * dir, 0.6, 0), Vector3(0.08, 0.95, 0.07), 1)
	m.box(Vector3((w - 0.04) * dir, 0.6, 0), Vector3(0.08, 0.95, 0.07), 1)
	for y: float in [0.22, 0.98]:
		m.box(Vector3(w * 0.5 * dir, y, 0), Vector3(w, 0.1, 0.07), 0)
	m.beam(Vector3(0.06 * dir, 0.25, 0.0), Vector3((w - 0.06) * dir, 0.95, 0.0), 0.08, 0.06, Vector3.BACK)
	m.mat(L.BOARDS, OAK * Color(1.1, 1.05, 1.0), 0.35)
	for k in 4:
		m.box(Vector3((0.12 + k * 0.2) * dir, 0.6, 0.045), Vector3(0.1, 0.7, 0.025), 1)
	m.mat(L.IRON, IRON * 0.8, 0.0)
	for y: float in [0.22, 0.98]:
		m.box(Vector3(0.12 * dir, y, 0.04), Vector3(0.26, 0.05, 0.02), 0)
	if mat == "ironwood":
		m.box(Vector3(w * 0.5 * dir, 0.6, -0.04), Vector3(w, 0.06, 0.015), 0)


# --- Roofs -------------------------------------------------------------------------------------

## One roof slope: from the eave line `low` (piece frame, at y = 0 of the slope
## underside) up to `high`, across x 0..width. Uses the village roof cladding.
static func _slope(b: ArchBuild, mat: String, low: Vector3, high: Vector3, width: float) -> void:
	var up := high - low
	var lu := up.length()
	var v := up / lu
	var n := Vector3.RIGHT.cross(v).normalized()
	if n.y < 0.0:
		n = -n
	b.push(Transform3D(Basis(Vector3.RIGHT, v, n), low + Vector3(-0.01, 0, 0)))
	var th := 0.3 if mat == "thatch" else 0.09
	var lt := lu + th * 0.15
	var wood := TIMBER
	if mat == "thatch":
		ArchKit._thatch_side(b, width + 0.02, lu, lt, th, Color(1.0, 0.96, 0.88), 0.4, false, wood)
	else:
		ArchKit._tiled_side(b, mat, width + 0.02, lu, lt, th, Color(1, 1, 1) if mat == "slate" else Color(0.95, 0.9, 0.85), 0.35, wood)
	# Rafters under the slope.
	b.shell.mat(L.TIMBER, wood, 0.3)
	for x: float in [0.2, width * 0.5, width - 0.2]:
		b.shell.beam(Vector3(x, 0.02, -0.07), Vector3(x, lu - 0.02, -0.07), 0.09, 0.13, Vector3.BACK, 0.01)
	b.pop()


static func _ridge(b: ArchBuild, mat: String) -> void:
	var m := b.shell
	match mat:
		"thatch":
			m.mat(L.THATCH, Color(0.92, 0.88, 0.8), 0.3)
			m.cylinder(Vector3(-0.02, 1.12, 1.0), Vector3(2.02, 1.12, 1.0), 0.2, -1.0, 10)
		"slate":
			m.mat(L.ASHLAR, Color(0.45, 0.45, 0.47), 0.3)
			m.cylinder(Vector3(-0.02, 1.12, 1.0), Vector3(2.02, 1.12, 1.0), 0.09, -1.0, 8)
		_:
			m.mat(L.BOARDS, TIMBER * 0.9, 0.4)
			for sd: float in [1.0, -1.0]:
				m.beam(Vector3(-0.02, 1.08, 1.0 + sd * 0.09), Vector3(2.02, 1.08, 1.0 + sd * 0.09), 0.22, 0.035, Vector3(0, 1, sd).normalized())


## Outer hip corner: two slopes meeting on the diagonal, apex at the back-left.
static func _hip_corner(b: ArchBuild, mat: String) -> void:
	var m := b.shell
	var th := 0.3 if mat == "thatch" else 0.1
	m.mat(_layer(mat), Color(1, 1, 1) if mat != "shingle" else Color(0.95, 0.9, 0.85), 0.35)
	var apex := Vector3(0, 1, 0) + Vector3(0, th, 0)
	for face in 2:
		var a := Vector3(0, th, 1) if face == 0 else Vector3(1, th, 1)
		var c := Vector3(1, th, 1) if face == 0 else Vector3(1, th, 0)
		var nrm := Vector3(0, 1, 1).normalized() if face == 0 else Vector3(1, 1, 0).normalized()
		m.tri(apex, a, c, Vector2(0, -1.41), Vector2(0, 0), Vector2(1, 0), nrm)
		# Underside and the eave edge.
		m.tri(apex - Vector3(0, th, 0), c - Vector3(0, th, 0), a - Vector3(0, th, 0), Vector2(0, -1.41), Vector2(1, 0), Vector2(0, 0), -nrm)
		m.quad(a - Vector3(0, th, 0), c - Vector3(0, th, 0), c, a, Vector2(0, 0), Vector2(1, 0), Vector2(1, -th), Vector2(0, -th),
				Vector3(0, 0, 1) if face == 0 else Vector3(1, 0, 0))
	# Hip cap along the diagonal.
	if mat == "thatch":
		m.mat(L.THATCH, Color(0.92, 0.88, 0.8), 0.3)
		m.cylinder(Vector3(1, th, 1), apex, 0.12, 0.14, 8)
	else:
		m.mat(L.ASHLAR if mat == "slate" else L.BOARDS, Color(0.5, 0.5, 0.52) if mat == "slate" else TIMBER, 0.3)
		m.beam(Vector3(1, th + 0.02, 1), apex + Vector3(0, 0.02, 0), 0.14, 0.05, Vector3.UP)


static func _flat_roof(b: ArchBuild, mat: String) -> void:
	var m := b.shell
	m.mat(L.BOARDS, OAK * 0.9, 0.3)
	m.box(Vector3(1.0, 0.87, 1.0), Vector3(2.0, 0.12, 2.0), 0)
	m.mat(_layer(mat), Color(1, 1, 1) if mat != "shingle" else Color(0.95, 0.9, 0.85), 0.35)
	var th := 0.12 if mat == "thatch" else 0.05
	m.box(Vector3(1.0, 0.93 + th * 0.5, 1.0), Vector3(2.0, th, 2.0), 0)
	m.mat(L.TIMBER, TIMBER, 0.3)
	for z: float in [0.25, 1.0, 1.75]:
		m.box(Vector3(1.0, 0.74, z), Vector3(2.0, 0.16, 0.12), 0)


# --- Furniture -------------------------------------------------------------------------------

static func _chair(m: ArchMesh) -> void:
	m.mat(L.FLOOR, OAK, 0.2)
	m.box(Vector3(0.5, 0.46, 0.52), Vector3(0.46, 0.05, 0.44), 0)
	m.mat(L.TIMBER, OAK * Color(0.85, 0.8, 0.75), 0.2)
	for x: float in [0.3, 0.7]:
		m.box(Vector3(x, 0.22, 0.72), Vector3(0.05, 0.44, 0.05), 1)
		m.box(Vector3(x, 0.5, 0.32), Vector3(0.05, 1.0, 0.05), 1)
		m.box(Vector3(x, 0.12, 0.52), Vector3(0.035, 0.035, 0.4), 2)
	for y: float in [0.68, 0.9]:
		m.box(Vector3(0.5, y, 0.32), Vector3(0.4, 0.07, 0.03), 0)


static func _wall_torch(b: ArchBuild) -> void:
	var m := b.shell
	var back := Vector3(0.5, 0.45, -0.3)
	m.mat(L.IRON, IRON * 0.6, 0.0)
	m.box(back, Vector3(0.12, 0.24, 0.03), 1)
	m.beam(back + Vector3(0, -0.04, 0), back + Vector3(0, 0.08, 0.2), 0.03, 0.03, Vector3.UP)
	m.lathe(back + Vector3(0, 0.05, 0.2), PackedVector2Array([Vector2(0.03, 0.0), Vector2(0.05, 0.08)]), 6, false, false)
	m.mat(L.TIMBER, TIMBER * 0.8, 0.4)
	m.cylinder(back + Vector3(0, -0.1, 0.15), back + Vector3(0, 0.2, 0.22), 0.025, 0.032, 6)
	m.mat(L.LINEN, Color(0.25, 0.2, 0.15), 0.1)
	m.cylinder(back + Vector3(0, 0.14, 0.21), back + Vector3(0, 0.24, 0.23), 0.04, 0.035, 6)
	b.add_fire(back + Vector3(0, 0.3, 0.23), 0.45, 8.0, 1.3)


# --- Storage ---------------------------------------------------------------------------------

## A planked chest with iron corners, lock plate and a curved lid (lid frame:
## hinge at the back top edge, lid towards +z).
static func _chest(m: ArchMesh, lid: ArchMesh, iron: bool) -> void:
	var wood := OAK * (Color(0.8, 0.72, 0.65) if iron else Color(1.05, 0.98, 0.9))
	var w := 0.9
	var d := 0.58
	var h := 0.48
	var c := Vector3(0.5, 0, 0.5)
	m.mat(L.BOARDS, wood, 0.3)
	m.box(c + Vector3(0, h * 0.5 + 0.03, 0), Vector3(w - 0.04, h - 0.02, d - 0.04), 0)
	m.mat(L.TIMBER, TIMBER * 0.9, 0.3)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			m.box(c + Vector3(sx * (w * 0.5 - 0.03), h * 0.5 + 0.02, sz * (d * 0.5 - 0.03)), Vector3(0.06, h, 0.06), 1)
	m.box(c + Vector3(0, 0.05, 0), Vector3(w, 0.06, d), 0)
	m.box(c + Vector3(0, h - 0.01, 0), Vector3(w, 0.05, d), 0)
	m.mat(L.IRON, IRON * (0.7 if iron else 0.85), 0.0)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			m.box(c + Vector3(sx * (w * 0.5 - 0.005), h * 0.5 + 0.02, sz * (d * 0.5 - 0.06)), Vector3(0.015, h, 0.12), 1)
			m.box(c + Vector3(sx * (w * 0.5 - 0.06), h * 0.5 + 0.02, sz * (d * 0.5 - 0.005)), Vector3(0.12, h, 0.015), 1)
	if iron:
		for x: float in [-0.25, 0.25]:
			m.box(c + Vector3(x, h * 0.5 + 0.02, d * 0.5 + 0.004), Vector3(0.07, h, 0.012), 1)
			m.box(c + Vector3(x, h * 0.5 + 0.02, -d * 0.5 - 0.004), Vector3(0.07, h, 0.012), 1)
	m.box(c + Vector3(0, h - 0.1, d * 0.5 + 0.01), Vector3(0.14, 0.16, 0.02), 0)
	m.mat(L.FLAT, Color(0.05, 0.04, 0.04), 0.0)
	m.box(c + Vector3(0, h - 0.11, d * 0.5 + 0.021), Vector3(0.025, 0.05, 0.004), 0)
	# Feet.
	m.mat(L.TIMBER, TIMBER * 0.8, 0.3)
	for sx: float in [-1.0, 1.0]:
		m.box(c + Vector3(sx * (w * 0.5 - 0.08), 0.015, 0), Vector3(0.12, 0.03, d - 0.04), 2)
	# Lid: a barrel vault over the box (frame origin at the hinge, d deep along +z).
	var r := d * 0.5
	var seg := 8
	lid.mat(L.BOARDS, wood * 1.05, 0.3)
	for i in seg:
		var a0 := PI * float(i) / seg
		var a1 := PI * float(i + 1) / seg
		var p0 := Vector3(0, sin(a0) * r * 0.75, r - cos(a0) * r)
		var p1 := Vector3(0, sin(a1) * r * 0.75, r - cos(a1) * r)
		var nn := Vector3(0, sin((a0 + a1) * 0.5) / 0.75, -cos((a0 + a1) * 0.5)).normalized()
		lid.quad(p0 + Vector3(-w * 0.5, 0, 0), p0 + Vector3(w * 0.5, 0, 0), p1 + Vector3(w * 0.5, 0, 0), p1 + Vector3(-w * 0.5, 0, 0),
				Vector2(0, i * 0.08), Vector2(w, i * 0.08), Vector2(w, (i + 1) * 0.08), Vector2(0, (i + 1) * 0.08), nn)
		for sx: float in [-1.0, 1.0]:
			lid.tri(Vector3(sx * w * 0.5, 0, r), p0 + Vector3(sx * w * 0.5, 0, 0), p1 + Vector3(sx * w * 0.5, 0, 0),
					Vector2(r, 0), Vector2(p0.z, -p0.y), Vector2(p1.z, -p1.y), Vector3(sx, 0, 0))
	lid.mat(L.BOARDS, wood * 0.8, 0.3)
	lid.box(Vector3(0, 0.005, r), Vector3(w - 0.02, 0.01, d - 0.02), 0)
	lid.mat(L.IRON, IRON * (0.7 if iron else 0.85), 0.0)
	for x: float in ([-0.38, -0.12, 0.12, 0.38] if iron else [-0.36, 0.36]):
		for i in seg:
			var a0 := PI * float(i) / seg
			var a1 := PI * float(i + 1) / seg
			var p0 := Vector3(x, sin(a0) * (r * 0.75 + 0.008), r - cos(a0) * (r + 0.008))
			var p1 := Vector3(x, sin(a1) * (r * 0.75 + 0.008), r - cos(a1) * (r + 0.008))
			lid.beam(p0, p1, 0.05, 0.012, Vector3.UP)
	lid.box(Vector3(0, 0.05, d + 0.008), Vector3(0.1, 0.1, 0.016), 0)


static func _barrel(m: ArchMesh, lid: ArchMesh) -> void:
	VillageProps.barrel(m, Vector3(0.5, 0.0, 0.5), 0.92, 0.34)
	lid.mat(L.BOARDS, OAK * Color(1.05, 0.95, 0.85), 0.25)
	lid.lathe(Vector3(0, 0.0, 0.32), PackedVector2Array([Vector2(0.3, 0.0), Vector2(0.3, 0.035), Vector2(0.0, 0.035)]), 14, true, false)
	lid.mat(L.TIMBER, TIMBER, 0.3)
	lid.box(Vector3(0, 0.06, 0.32), Vector3(0.06, 0.05, 0.4), 2)
