class_name BuildingMesh
extends RefCounted
## Modelled village buildings from a plan spec (VillagePlan): timber-framed
## cottages, stone cottages, longhouses, the tavern, the chapel, the smithy and
## stilt houses. Runs on a worker thread into an ArchBuild.
##
## Spec keys: center (world, footprint centre at floor top), rot (0..3), w, d
## (cells), kind, wall_h, roof, pitch, door (cell along the front), door_w,
## enterable, chimney (-1 / 0 / 1 gable side), raise (stilts), style, seed,
## furniture ([{kind, cell: Vector2i, size: Vector2i}] in local cells).

const L = ArchMaterials.L


static func build(b: ArchBuild, spec: Dictionary) -> void:
	var xf := frame(spec, b.origin)
	b.push(xf)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 1))
	match String(spec["kind"]):
		"smithy":
			_smithy(b, spec, rng)
		"chapel":
			_chapel(b, spec, rng)
		_:
			_house(b, spec, rng)
	b.pop()
	_far(b, spec, xf)


## Only the distant silhouette.
static func far_only(b: ArchBuild, spec: Dictionary) -> void:
	_far(b, spec, frame(spec, b.origin))


## Building frame in node space (origin = node origin).
static func frame(spec: Dictionary, node_origin: Vector3) -> Transform3D:
	var rot := int(spec.get("rot", 0))
	return Transform3D(Basis(Vector3.UP, rot * PI * 0.5), (spec["center"] as Vector3) - node_origin)


static func _style(spec: Dictionary, key: String, fallback: Variant) -> Variant:
	var st: Dictionary = spec.get("style", {})
	return st.get(key, fallback)


## Openings: the door, then windows along each wall (deterministic per seed).
static func openings(spec: Dictionary, rng: RandomNumberGenerator) -> Array:
	var w := float(spec["w"])
	var d := float(spec["d"])
	var holes: Array = [[], [], [], []]
	var door_u := float(spec.get("door", int(w) / 2))
	var door_w := float(spec.get("door_w", 1))
	var door_h := ArchKit.DOOR_H + (0.18 if door_w > 1.0 else 0.0)
	var front_len := w
	holes[0].append(Rect2(door_u, 0.0, door_w, door_h))
	var chimney := int(spec.get("chimney", 0))
	var lower_h := float(spec.get("lower_h", 99.0))
	for side in 4:
		var length := w if side < 2 else d
		if side >= 2 and chimney != 0 and (side == 2) == (chimney < 0):
			continue  # the chimney breast fills this gable
		var cells := int(length)
		for i in range(1, cells - 1):
			var u := float(i) + 0.5
			if side == 0 and absf(u - (door_u + door_w * 0.5)) < door_w * 0.5 + 1.0:
				continue
			if side >= 2 and cells <= 5 and i != cells / 2:
				continue
			# Every other bay keeps some wall between windows.
			if (i + int(spec.get("seed", 0))) % 2 != 0 and length > 4.0:
				continue
			var ww := 0.8 if length < 8.0 else 0.9
			holes[side].append(Rect2(u - ww * 0.5, ArchKit.WINDOW_SILL, ww, ArchKit.WINDOW_H))
			if lower_h < 50.0:
				holes[side].append(Rect2(u - ww * 0.5, lower_h + ArchKit.WINDOW_SILL - 0.1, ww, ArchKit.WINDOW_H - 0.1))
	return holes


# --- Houses ----------------------------------------------------------------------

static func _house(b: ArchBuild, spec: Dictionary, rng: RandomNumberGenerator) -> void:
	var kind := String(spec["kind"])
	var w := float(spec["w"])
	var d := float(spec["d"])
	var wall_h := float(spec.get("wall_h", 3.0))
	var enterable: bool = spec.get("enterable", false)
	var raise := float(spec.get("raise", 0.0))
	var stone := kind == "stone"
	var longhouse := kind == "longhouse"
	var two_storey := kind == "tavern"
	var t := 0.6 if stone else 0.42
	var plaster: Color = _style(spec, "plaster", Color(0.93, 0.88, 0.78))
	var timber: Color = _style(spec, "timber", Color(0.55, 0.42, 0.32))
	var stone_tint: Color = _style(spec, "stone", Color(0.95, 0.92, 0.86))
	var roof_tint: Color = _style(spec, "roof_tint", Color(1, 1, 1))
	var shutters: Color = _style(spec, "shutters", Color(0.32, 0.42, 0.3, 1.0))
	var door_tint: Color = _style(spec, "door", Color(0.62, 0.48, 0.36))
	var wear: float = _style(spec, "wear", 0.45)
	var snow: float = _style(spec, "snow", 0.0)
	var boards := String(_style(spec, "walls", "")) == "boards" or longhouse or kind == "stilt"
	var roof_kind := String(spec.get("roof", "thatch"))
	var holes := openings(spec, rng)
	var lit := rng.randf() < 0.8
	b.dirt(-0.2, 1.4, 0.5)
	b.snow(0.0)
	if raise > 0.0:
		_stilts(b, w, d, raise, timber, stone_tint, spec)
		b.push(Transform3D(Basis.IDENTITY, Vector3(0, raise, 0)))
	# Plinth / footing that meets the ground.
	_plinth(b, w, d, holes[0], L.RUBBLE if not stone else L.ASHLAR, stone_tint, 0.5 if raise == 0.0 else 0.25, 2.2 if raise == 0.0 else 0.25)
	var lower_layer := L.RUBBLE if stone else L.PLASTER
	var lower_tint := stone_tint if stone else plaster
	for side in 4:
		var length := ArchKit.side_length(side, w, d)
		var fxf := ArchKit.side_frame(side, w, d)
		b.push(fxf)
		var inner_from := t if side >= 2 else 0.0
		var inner_to := length - t if side >= 2 else length
		if two_storey:
			# Stone ground floor, timber-framed upper storey with a moulded band.
			var lower := 2.75
			var lower_holes: Array = []
			var upper_holes: Array = []
			for h: Rect2 in holes[side]:
				(lower_holes if h.position.y < lower else upper_holes).append(h)
			ArchKit.wall(b.shell, length, 0.0, lower, t, lower_holes, L.ASHLAR, stone_tint, wear, L.PLASTER if enterable else -1, Color(0.9, 0.86, 0.78), inner_from, inner_to)
			ArchKit.wall(b.shell, length, lower, wall_h, t, upper_holes, L.PLASTER, plaster, wear, -1)
			b.shell.mat(L.TIMBER, timber, 0.3)
			b.shell.box(Vector3(length * 0.5, lower + 0.08, 0.04), Vector3(length + 0.12, 0.16, 0.2), 0)
			b.push(Transform3D(Basis.IDENTITY, Vector3(0, lower, 0)))
			var shifted: Array = []
			for h: Rect2 in upper_holes:
				shifted.append(Rect2(h.position - Vector2(0, lower), h.size))
			ArchKit.timber_frame(b.shell, length, wall_h - lower, shifted, side < 2, rng, timber, 0.18, true, 1)
			b.pop()
			for h: Rect2 in lower_holes:
				_stone_surround(b, h, t, stone_tint)
		elif stone:
			ArchKit.wall(b.shell, length, 0.0, wall_h, t, holes[side], L.RUBBLE, stone_tint, wear, L.PLASTER if enterable else -1, Color(0.88, 0.84, 0.76), inner_from, inner_to)
			for h: Rect2 in holes[side]:
				_stone_surround(b, h, t, stone_tint)
		elif longhouse:
			# Drystone base, then vertical boards between posts.
			ArchKit.wall(b.shell, length, 0.0, 1.05, t + 0.12, _clip(holes[side], 0.0, 1.05), L.RUBBLE, stone_tint, wear, L.RUBBLE if enterable else -1, stone_tint * Color(0.8, 0.8, 0.8), inner_from, inner_to)
			b.push(Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.06)))
			ArchKit.wall(b.shell, length, 1.05, wall_h, t - 0.06, _clip(holes[side], 1.05, wall_h), L.BOARDS, timber * Color(1.15, 1.1, 1.05), wear, L.BOARDS if enterable else -1, timber * Color(0.9, 0.85, 0.8), inner_from, inner_to, false)
			b.pop()
			_board_posts(b.shell, length, 1.05, wall_h, holes[side], timber, side < 2)
		elif boards:
			ArchKit.wall(b.shell, length, 0.0, wall_h, t, holes[side], L.BOARDS, timber * Color(1.2, 1.12, 1.05), wear, L.BOARDS if enterable else -1, timber, inner_from, inner_to)
			_board_posts(b.shell, length, 0.0, wall_h, holes[side], timber, side < 2)
		else:
			ArchKit.wall(b.shell, length, 0.0, wall_h, t, holes[side], L.PLASTER, plaster, wear, L.PLASTER if enterable else -1, plaster * Color(0.97, 0.95, 0.92), inner_from, inner_to)
			ArchKit.timber_frame(b.shell, length, wall_h, holes[side], side < 2, rng, timber, 0.45, true, int(spec.get("seed", 0)) % 2)
		# Windows and the door.
		var frame_tint := timber * Color(1.1, 1.05, 1.0)
		var shutter_z := 0.0 if stone or two_storey else 0.07
		for h: Rect2 in holes[side]:
			if side == 0 and h.position.y < 0.5:
				var wide := h.size.x > 1.5
				ArchKit.door(b, h, t, L.ASHLAR if stone else L.TIMBER, stone_tint if stone else timber, door_tint, enterable, wide)
				if spec.get("hood", false):
					ArchKit.door_hood(b, h.get_center().x, h.end.y + 0.35, h.size.x + 0.9, L.SHINGLE if roof_kind != "slate" else L.SLATE, roof_tint, timber)
				continue
			var with_shutters := shutters if (stone or two_storey or not boards) else Color(0, 0, 0, 0)
			if two_storey and h.position.y > 2.0:
				shutter_z = 0.07
			ArchKit.window(b, h, t, frame_tint, L.ASHLAR if (stone or two_storey) else L.TIMBER, stone_tint if (stone or two_storey) else timber, lit and rng.randf() < 0.85, enterable, with_shutters, shutter_z)
			if side < 2 and h.position.y < 2.0 and rng.randf() < float(_style(spec, "flowers", 0.35)):
				_window_box(b, h, rng, timber)
		b.pop()
	# Corner quoins on stone houses.
	if stone or two_storey:
		_quoins(b, w, d, 2.75 if two_storey else wall_h, stone_tint, rng)
	# Roof and gables.
	var pitch := float(spec.get("pitch", 50.0 if roof_kind == "thatch" else 42.0))
	var rise := d * 0.5 * tan(deg_to_rad(pitch))
	for side in [2, 3]:
		b.push(ArchKit.side_frame(side, w, d))
		var gl := d
		if stone or (longhouse and String(_style(spec, "gable", "")) == "stone"):
			ArchKit.gable(b.shell, gl, wall_h, rise, t, L.RUBBLE, stone_tint, wear, enterable, L.PLASTER, Color(0.88, 0.84, 0.76))
		elif boards or longhouse:
			b.shell.mat(L.BOARDS, timber * Color(1.2, 1.12, 1.05), wear)
			ArchKit.gable(b.shell, gl, wall_h, rise, t, L.BOARDS, timber * Color(1.2, 1.12, 1.05), wear, enterable, L.BOARDS, timber)
		else:
			ArchKit.gable(b.shell, gl, wall_h, rise, t, L.PLASTER, plaster, wear, enterable, L.PLASTER, plaster * Color(0.97, 0.95, 0.92))
			ArchKit.gable_frame(b.shell, gl, wall_h, rise, timber)
		b.pop()
	b.snow(snow)
	var ridge := ArchKit.gable_roof(b, w, d, wall_h, {"kind": roof_kind, "pitch": pitch, "tint": roof_tint, "wood": timber,
			"eave": 0.6 if roof_kind == "thatch" else 0.45, "verge": 0.4 if roof_kind == "thatch" else 0.3,
			"interior": enterable and not two_storey, "horns": longhouse, "wear": wear})
	# Dormers on the bigger tiled roofs.
	if roof_kind != "thatch" and not longhouse and (w >= 8.0 or two_storey) and raise == 0.0:
		var wall_layer := L.BOARDS if boards else L.PLASTER
		var wall_tint := timber * Color(1.2, 1.12, 1.05) if boards else plaster
		var nd := 2 if w >= 9.0 else 1
		for k in nd:
			var cx := 0.0 if nd == 1 else (-w * 0.22 if k == 0 else w * 0.22)
			_dormer(b, cx, d, wall_h, deg_to_rad(pitch), 0.1, L.SLATE if roof_kind == "slate" else L.SHINGLE, roof_tint, wall_layer, wall_tint, timber, rng.randf() < 0.6)
	b.snow(0.0)
	# Chimney.
	var chimney := int(spec.get("chimney", 0))
	if chimney != 0:
		var stack_layer := L.ASHLAR if not longhouse else L.RUBBLE
		ArchKit.chimney(b, float(chimney), w, d, ridge, t, stack_layer, stone_tint, enterable and not two_storey and raise == 0.0 or (enterable and raise > 0.0), 0.85)
		if not enterable or two_storey:
			b.add_smoke(Vector3(float(chimney) * (w * 0.5 + 0.28 - 0.47), ridge + 1.3, 0), 0.8)
	elif longhouse:
		# Smoke louvre on the ridge over the long hearth.
		var top := ridge + (0.42 if roof_kind == "thatch" else 0.1) / cos(deg_to_rad(pitch))
		b.shell.mat(L.TIMBER, timber, 0.3)
		for sx: float in [-0.7, 0.7]:
			for sz: float in [-0.35, 0.35]:
				b.shell.beam(Vector3(sx, top - 0.3, sz), Vector3(sx, top + 0.5, sz), 0.1, 0.1)
		b.shell.beam(Vector3(-0.85, top + 0.5, 0), Vector3(0.85, top + 0.5, 0), 0.12, 0.12)
		b.shell.mat(L.SHINGLE if roof_kind != "slate" else L.SLATE, roof_tint, wear)
		for sd: float in [1.0, -1.0]:
			var e0 := Vector3(-0.95, top + 0.32, sd * 0.75)
			var e1 := Vector3(0.95, top + 0.32, sd * 0.75)
			var r1 := Vector3(0.95, top + 0.85, 0)
			var r0 := Vector3(-0.95, top + 0.85, 0)
			b.shell.quad(e0, e1, r1, r0, Vector2(0, 0), Vector2(1.9, 0), Vector2(1.9, -0.9), Vector2(0, -0.9), Vector3(0, 0.82, sd * 0.57).normalized())
			b.shell.quad(e1, e0, r0, r1, Vector2(0, 0), Vector2(1.9, 0), Vector2(1.9, -0.9), Vector2(0, -0.9), -Vector3(0, 0.82, sd * 0.57).normalized())
		b.add_smoke(Vector3(0, top + 0.6, 0), 1.2)
	# Interior.
	if enterable:
		_floor(b, w, d, t, stone or longhouse)
		if two_storey:
			_ceiling(b, w, d, t, 2.75, timber)
		VillageProps.furnish(b, spec, rng, t)
	if raise > 0.0:
		b.pop()
	# Tavern sign and outside seating.
	if kind == "tavern":
		VillageProps.tavern_front(b, spec, rng)


static func _clip(holes: Array, v0: float, v1: float) -> Array:
	var out: Array = []
	for h: Rect2 in holes:
		var a := maxf(h.position.y, v0)
		var e := minf(h.end.y, v1)
		if e > a:
			out.append(Rect2(h.position.x, a, h.size.x, e - a))
	return out


## Square posts on boarded walls (and the longhouse), framing every opening.
static func _board_posts(m: ArchMesh, length: float, base: float, top: float, holes: Array, timber: Color, corners: bool) -> void:
	m.mat(L.TIMBER, timber, 0.4)
	if corners:
		m.beam(Vector3(0.11, base - 0.05, -0.1), Vector3(0.11, top, -0.1), 0.34, 0.34, Vector3.BACK, 0.03)
		m.beam(Vector3(length - 0.11, base - 0.05, -0.1), Vector3(length - 0.11, top, -0.1), 0.34, 0.34, Vector3.BACK, 0.03)
	var us: Array[float] = []
	for h: Rect2 in holes:
		us.append(h.position.x - 0.12)
		us.append(h.end.x + 0.12)
	var n := int(length / 2.2)
	for i in range(1, n):
		var u := length * float(i) / n
		var clear := true
		for x in us:
			if absf(x - u) < 0.6:
				clear = false
		for h: Rect2 in holes:
			if u > h.position.x - 0.2 and u < h.end.x + 0.2:
				clear = false
		if clear:
			us.append(u)
	for u in us:
		m.beam(Vector3(u, base, -0.06), Vector3(u, top, -0.06), 0.18, 0.2, Vector3.BACK, 0.02)
	m.beam(Vector3(0.28, top - 0.1, -0.07), Vector3(length - 0.28, top - 0.1, -0.07), 0.2, 0.22, Vector3.BACK, 0.02)
	for h: Rect2 in holes:
		if h.position.y > base + 0.1:
			m.beam(Vector3(h.position.x - 0.2, h.position.y - 0.06, -0.06), Vector3(h.end.x + 0.2, h.position.y - 0.06, -0.06), 0.12, 0.2, Vector3.BACK, 0.01)
		m.beam(Vector3(h.position.x - 0.2, h.end.y + 0.06, -0.06), Vector3(h.end.x + 0.2, h.end.y + 0.06, -0.06), 0.12, 0.2, Vector3.BACK, 0.01)


## Dressed jambs, lintel and sill around an opening in a stone wall.
static func _stone_surround(b: ArchBuild, h: Rect2, t: float, tint: Color) -> void:
	var m := b.shell
	m.mat(L.ASHLAR, tint * Color(1.05, 1.03, 1.0), 0.4)
	var door := h.position.y < 0.5
	var lintel_h := 0.3
	m.box(Vector3(h.get_center().x, h.end.y + lintel_h * 0.5 - 0.005, 0.012 - 0.06), Vector3(h.size.x + 0.5, lintel_h, 0.145), 0)
	# Long-and-short jamb stones.
	var y := h.position.y
	var k := 0
	while y < h.end.y - 0.05:
		var sh := minf(0.32, h.end.y - y)
		var ext := 0.32 if k % 2 == 0 else 0.18
		for s: float in [-1.0, 1.0]:
			var x := h.position.x - ext * 0.5 if s < 0.0 else h.end.x + ext * 0.5
			m.box(Vector3(x, y + sh * 0.5, 0.015 - 0.05), Vector3(ext, sh - 0.012, 0.13), 1)
		y += sh
		k += 1
	if not door:
		return


## Long-and-short quoins on the four corners of a stone house.
static func _quoins(b: ArchBuild, w: float, d: float, h: float, tint: Color, rng: RandomNumberGenerator) -> void:
	var m := b.shell
	m.mat(L.ASHLAR, tint * Color(1.06, 1.04, 1.0), 0.45)
	var y := 0.45
	var k := 0
	while y < h - 0.1:
		var sh := minf(0.3 + rng.randf_range(-0.03, 0.03), h - y)
		for cx: float in [-1.0, 1.0]:
			for cz: float in [-1.0, 1.0]:
				var la := 0.58 if k % 2 == 0 else 0.3
				var lb := 0.3 if k % 2 == 0 else 0.58
				var x0 := cx * (w * 0.5 + 0.025)
				var z0 := cz * (d * 0.5 + 0.025)
				var x1 := cx * (w * 0.5 - la)
				var z1 := cz * (d * 0.5 - lb)
				m.box(Vector3((x0 + x1) * 0.5, y + sh * 0.5, (z0 + z1) * 0.5), Vector3(absf(x0 - x1), sh - 0.015, absf(z0 - z1)), 0)
		y += sh
		k += 1


## Stone footing that steps down to meet the ground, with a weathered top.
static func _plinth(b: ArchBuild, w: float, d: float, front_holes: Array, layer: int, tint: Color, top: float, depth: float) -> void:
	var m := b.shell
	m.mat(layer, tint * Color(0.9, 0.88, 0.85), 0.55)
	var out := 0.07
	for side in 4:
		var length := ArchKit.side_length(side, w, d)
		b.push(ArchKit.side_frame(side, w, d))
		var gaps: Array = []
		if side == 0:
			for h: Rect2 in front_holes:
				if h.position.y < 0.5:
					gaps.append(Rect2(h.position.x - 0.1, -depth, h.size.x + 0.2, top + depth + 1.0))
		var u0 := -out if side < 2 else 0.0
		var u1 := length + out if side < 2 else length
		for r in ArchKit.solid_rects(u0, u1, -depth, top, gaps):
			m.box(Vector3(r.get_center().x, r.get_center().y, out * 0.5 - 0.1), Vector3(r.size.x, r.size.y, 0.2 + out), 0, 32)
		b.pop()
	# Door gaps keep a footing below the threshold.
	b.push(ArchKit.side_frame(0, w, d))
	for h: Rect2 in front_holes:
		if h.position.y < 0.5:
			m.box(Vector3(h.get_center().x, -depth * 0.5 - 0.1, out * 0.5 - 0.1), Vector3(h.size.x + 0.2, depth - 0.2, 0.2 + out), 0, 32 | 4)
	b.pop()


static func _floor(b: ArchBuild, w: float, d: float, t: float, flags: bool) -> void:
	var m := b.interior
	if flags:
		m.mat(L.COBBLE, Color(0.85, 0.82, 0.78), 0.1, 0.9)
	else:
		m.mat(L.FLOOR, Color(0.78, 0.68, 0.58), 0.1, 0.9)
	m.rect(Vector3(-w * 0.5 + t * 0.5, 0.005, d * 0.5 - t * 0.5), Vector3.RIGHT, Vector3.FORWARD, w - t, d - t)


static func _ceiling(b: ArchBuild, w: float, d: float, t: float, h: float, timber: Color) -> void:
	var m := b.interior
	m.mat(L.FLOOR, timber * Color(1.1, 1.05, 1.0), 0.0, 0.8)
	m.rect(Vector3(-w * 0.5 + t, h, -d * 0.5 + t), Vector3.RIGHT, Vector3.BACK, w - t * 2.0, d - t * 2.0)
	m.mat(L.TIMBER, timber, 0.2)
	var n := int(w / 0.9)
	for i in range(1, n):
		var x := -w * 0.5 + w * float(i) / n
		m.beam(Vector3(x, h - 0.09, -d * 0.5 + t), Vector3(x, h - 0.09, d * 0.5 - t), 0.14, 0.18, Vector3.UP, 0.015)
	m.beam(Vector3(-w * 0.5 + t, h - 0.2, 0), Vector3(w * 0.5 - t, h - 0.2, 0), 0.3, 0.3, Vector3.UP, 0.03)


## Posts and a deck for houses on stilts, with steps down to the ground.
static func _stilts(b: ArchBuild, w: float, d: float, raise: float, timber: Color, stone: Color, spec: Dictionary) -> void:
	var m := b.shell
	var deck_front := 1.6
	m.mat(L.TIMBER, timber * Color(0.8, 0.78, 0.75), 0.6)
	for x in range(0, int(w / 1.8) + 1):
		var px := -w * 0.5 + 0.15 + (w - 0.3) * float(x) / int(w / 1.8)
		for pz: float in [-d * 0.5 + 0.15, 0.0, d * 0.5 - 0.15, d * 0.5 + deck_front - 0.15]:
			m.cylinder(Vector3(px, -1.6, pz), Vector3(px, raise, pz), 0.13, 0.11, 7)
	# Cross-bracing under the floor.
	for pz: float in [-d * 0.5 + 0.15, d * 0.5 - 0.15]:
		m.beam(Vector3(-w * 0.5 + 0.2, 0.1, pz), Vector3(w * 0.5 - 0.2, raise - 0.25, pz), 0.08, 0.12, Vector3.UP)
	# Deck (porch) in front.
	m.mat(L.FLOOR, timber * Color(1.1, 1.05, 1.0), 0.4)
	m.box(Vector3(0, raise - 0.06, d * 0.5 + deck_front * 0.5), Vector3(w, 0.12, deck_front), 0)
	m.box(Vector3(0, raise - 0.06, 0), Vector3(w + 0.2, 0.12, d + 0.2), 0, 4)
	# Railing.
	b.detail.mat(L.TIMBER, timber, 0.4)
	var door_x := -w * 0.5 + float(spec.get("door", int(w) / 2)) + 0.5
	var zf := d * 0.5 + deck_front - 0.06
	for x in range(0, int(w) + 1):
		var px := -w * 0.5 + float(x)
		if absf(px - door_x) < 0.9:
			continue
		b.detail.beam(Vector3(px, raise, zf), Vector3(px, raise + 0.95, zf), 0.07, 0.07)
	b.detail.beam(Vector3(-w * 0.5, raise + 0.92, zf), Vector3(door_x - 0.9, raise + 0.92, zf), 0.07, 0.09)
	b.detail.beam(Vector3(door_x + 0.9, raise + 0.92, zf), Vector3(w * 0.5, raise + 0.92, zf), 0.07, 0.09)
	# Steps down to the ground in front of the door.
	ArchKit.stair(b.detail, Vector3(door_x, 0.0, zf + 1.6), Vector3.FORWARD, 1.1, raise, 1.6, 4, L.FLOOR, timber * Color(1.1, 1.05, 1.0))


# --- Smithy ------------------------------------------------------------------------

static func _smithy(b: ArchBuild, spec: Dictionary, rng: RandomNumberGenerator) -> void:
	var w := float(spec["w"])
	var d := float(spec["d"])
	var wall_h := float(spec.get("wall_h", 3.2))
	var timber: Color = _style(spec, "timber", Color(0.55, 0.42, 0.32))
	var stone: Color = _style(spec, "stone", Color(0.95, 0.92, 0.86))
	var roof_tint: Color = _style(spec, "roof_tint", Color(1, 1, 1))
	var wear: float = _style(spec, "wear", 0.45)
	var snow: float = _style(spec, "snow", 0.0)
	var roof_kind := String(spec.get("roof", "shingle"))
	var t := 0.55
	b.dirt(-0.2, 1.6, 0.6)
	# Stone back wall, low side walls, open front on posts.
	_plinth(b, w, d, [Rect2(0.3, 0.0, w - 0.6, 3.0)], L.RUBBLE, stone, 0.3, 1.8)
	b.push(ArchKit.side_frame(1, w, d))
	ArchKit.wall(b.shell, w, 0.0, wall_h, t, [], L.RUBBLE, stone, wear, L.RUBBLE, stone * Color(0.75, 0.72, 0.7), 0.0, w)
	b.pop()
	for side in [2, 3]:
		b.push(ArchKit.side_frame(side, w, d))
		ArchKit.wall(b.shell, d, 0.0, 1.25, t, [], L.RUBBLE, stone, wear, L.RUBBLE, stone * Color(0.75, 0.72, 0.7), t, d - t)
		b.pop()
	_quoins(b, w, d, 1.25, stone, rng)
	b.shell.mat(L.TIMBER, timber, 0.45)
	var posts_x: Array[float] = [-w * 0.5 + 0.2, -w * 0.5 + w / 3.0, w * 0.5 - w / 3.0, w * 0.5 - 0.2]
	for x in posts_x:
		b.shell.beam(Vector3(x, 0.0, d * 0.5 - 0.2), Vector3(x, wall_h, d * 0.5 - 0.2), 0.26, 0.26, Vector3.BACK, 0.03)
	for x: float in [-w * 0.5 + 0.2, w * 0.5 - 0.2]:
		b.shell.beam(Vector3(x, 1.25, -d * 0.5 + 0.4), Vector3(x, wall_h, -d * 0.5 + 0.4), 0.24, 0.24, Vector3.BACK, 0.03)
		b.shell.beam(Vector3(x, 1.25, 0.0), Vector3(x, wall_h, 0.0), 0.2, 0.2, Vector3.BACK, 0.03)
	b.shell.beam(Vector3(-w * 0.5, wall_h - 0.14, d * 0.5 - 0.2), Vector3(w * 0.5, wall_h - 0.14, d * 0.5 - 0.2), 0.28, 0.3, Vector3.BACK, 0.03)
	for x: float in [-w * 0.5 + 0.2, w * 0.5 - 0.2]:
		b.shell.beam(Vector3(x, wall_h - 0.14, -d * 0.5 + 0.3), Vector3(x, wall_h - 0.14, d * 0.5 - 0.2), 0.24, 0.26, Vector3.UP, 0.03)
		b.shell.beam(Vector3(x, 1.25 + 0.1, -d * 0.5 + 0.3), Vector3(x, 1.25 + 0.1, d * 0.5 - 0.2), 0.16, 0.6, Vector3.UP, 0.02)
	# Knee braces on the open front.
	for i in posts_x.size():
		var x := posts_x[i]
		for s: float in [-1.0, 1.0]:
			if (i == 0 and s < 0.0) or (i == posts_x.size() - 1 and s > 0.0):
				continue
			b.shell.beam(Vector3(x, wall_h - 0.9, d * 0.5 - 0.2), Vector3(x + s * 0.7, wall_h - 0.2, d * 0.5 - 0.2), 0.14, 0.16, Vector3.BACK, 0.015)
	for side in [2, 3]:
		b.push(ArchKit.side_frame(side, w, d))
		var rise := d * 0.5 * tan(deg_to_rad(40.0))
		ArchKit.gable(b.shell, d, wall_h, rise, 0.1, L.BOARDS, timber * Color(1.2, 1.1, 1.0), wear, true, L.BOARDS, timber)
		b.pop()
	# Cobbled working floor.
	b.interior.mat(L.COBBLE, Color(0.8, 0.78, 0.74), 0.1, 0.7)
	b.interior.rect(Vector3(-w * 0.5 + t, 0.01, d * 0.5), Vector3.RIGHT, Vector3.FORWARD, w - t * 2.0, d - t)
	b.snow(snow)
	var ridge := ArchKit.gable_roof(b, w, d, wall_h, {"kind": roof_kind, "pitch": 40.0, "tint": roof_tint, "wood": timber, "eave": 0.5, "verge": 0.3, "interior": true, "wear": wear})
	b.snow(0.0)
	# The forge: a stone hearth against the back wall with a hood and chimney.
	var fx := -w * 0.5 + 1.9
	var fz := -d * 0.5 + t + 0.75
	var m := b.shell
	m.mat(L.ASHLAR, stone * Color(0.9, 0.88, 0.85), 0.2, 0.8)
	m.box(Vector3(fx, 0.42, fz), Vector3(2.0, 0.84, 1.5), 1)
	m.mat(L.EMBER, Color(1, 1, 1), 0.0)
	m.lathe(Vector3(fx, 0.84, fz + 0.1), PackedVector2Array([Vector2(0.55, 0.0), Vector2(0.4, 0.07), Vector2(0.0, 0.1)]), 10, false, false)
	m.mat(L.ASHLAR, stone * Color(0.75, 0.72, 0.7), 0.1, 0.5)
	# Tapering hood.
	var hood := PackedVector2Array([Vector2(-1.0, 0.0), Vector2(1.0, 0.0), Vector2(0.45, 1.3), Vector2(-0.45, 1.3)])
	m.push(Transform3D(Basis.IDENTITY, Vector3(fx, 1.9, fz - 0.75)))
	m.prism(Vector3.ZERO, Vector3.RIGHT, Vector3.UP, hood, 1.35, false, true)
	m.box(Vector3(0, 1.3 + (ridge + 1.2 - 3.2) * 0.5, 0.45), Vector3(0.9, ridge + 1.2 - 3.2, 0.9), 1)
	m.mat(L.ASHLAR, stone * Color(0.7, 0.68, 0.66), 0.2, 0.5)
	m.box(Vector3(0, ridge + 1.3 - 1.9 + 0.06, 0.45), Vector3(1.05, 0.12, 1.05), 1)
	m.pop()
	b.add_smoke(Vector3(fx, ridge + 1.6, fz - 0.3), 1.6)
	b.add_fire(Vector3(fx, 0.9, fz + 0.1), 1.1, 7.0, 1.5)
	VillageProps.smithy_kit(b, spec, rng, fx, fz)
	_far_shed(b, spec)


# --- Chapel ------------------------------------------------------------------------

## Stone chapel: the ridge runs front to back, the door is in the west gable,
## lancet windows down the sides, buttresses, a bell-cote over the door.
static func _chapel(b: ArchBuild, spec: Dictionary, rng: RandomNumberGenerator) -> void:
	var w := float(spec["w"])
	var d := float(spec["d"])
	var wall_h := float(spec.get("wall_h", 4.4))
	var stone: Color = _style(spec, "stone", Color(0.95, 0.92, 0.86))
	var roof_tint: Color = _style(spec, "roof_tint", Color(1, 1, 1))
	var timber: Color = _style(spec, "timber", Color(0.55, 0.42, 0.32))
	var wear: float = _style(spec, "wear", 0.45)
	var snow: float = _style(spec, "snow", 0.0)
	var t := 0.7
	var door_u := float(spec.get("door", int(w) / 2))
	var door_w := float(spec.get("door_w", 2))
	b.dirt(-0.2, 1.8, 0.5)
	var front := Rect2(door_u, 0.0, door_w, 2.7)
	_plinth(b, w, d, [front], L.ASHLAR, stone, 0.55, 2.2)
	var lancets: Array = [[], [], [], []]
	for side in [2, 3]:
		var n := int(d / 2.4)
		for i in n:
			var u := d * (float(i) + 0.5) / n
			lancets[side].append(Rect2(u - 0.3, 1.5, 0.6, 2.2))
	lancets[1].append(Rect2(w * 0.5 - 0.45, 2.0, 0.9, 1.6))
	for side in 4:
		var length := ArchKit.side_length(side, w, d)
		b.push(ArchKit.side_frame(side, w, d))
		var holes: Array = lancets[side].duplicate()
		if side == 0:
			holes.append(front)
		ArchKit.wall(b.shell, length, 0.0, wall_h, t, holes, L.ASHLAR, stone, wear, L.PLASTER, Color(0.92, 0.9, 0.84), t if side >= 2 else 0.0, length - t if side >= 2 else length)
		for h: Rect2 in lancets[side]:
			_lancet(b, h, t, stone)
		if side == 0:
			ArchKit.door(b, front, t, L.ASHLAR, stone, _style(spec, "door", Color(0.5, 0.36, 0.26)), true, true)
			_arch_head(b, front, t, stone)
		b.pop()
	_quoins(b, w, d, wall_h, stone, rng)
	# Buttresses along the long sides.
	b.shell.mat(L.ASHLAR, stone * Color(0.97, 0.95, 0.92), wear)
	for side_x: float in [-1.0, 1.0]:
		for i in range(0, int(d / 2.4) + 1):
			var z := -d * 0.5 + d * float(i) / int(d / 2.4)
			z = clampf(z, -d * 0.5 + 0.35, d * 0.5 - 0.35)
			var x := side_x * (w * 0.5 + 0.35)
			b.shell.box(Vector3(x, (wall_h - 1.0) * 0.5 - 0.3, z), Vector3(0.7, wall_h - 0.4, 0.6), 1, 0)
			b.shell.prism(Vector3(x - 0.35 * side_x, wall_h - 1.25, z - 0.3), Vector3(side_x, 0, 0), Vector3.UP,
					PackedVector2Array([Vector2(0, 0), Vector2(0.7, 0), Vector2(0, 0.9)]), 0.6, true, true)
	# Gables on the front and back; the roof runs front to back.
	var pitch := 52.0
	var rise := w * 0.5 * tan(deg_to_rad(pitch))
	for side in [0, 1]:
		b.push(ArchKit.side_frame(side, w, d))
		ArchKit.gable(b.shell, w, wall_h, rise, t, L.ASHLAR, stone, wear, true, L.PLASTER, Color(0.92, 0.9, 0.84))
		b.pop()
	b.snow(snow)
	b.push(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO))
	var ridge := ArchKit.gable_roof(b, d, w, wall_h, {"kind": String(spec.get("roof", "slate")), "pitch": pitch, "tint": roof_tint, "wood": timber, "eave": 0.4, "verge": 0.25, "interior": true, "wear": wear})
	b.pop()
	b.snow(0.0)
	# Bell-cote on the front gable.
	var m := b.shell
	var gz := d * 0.5 - t * 0.5
	m.mat(L.ASHLAR, stone, wear)
	m.box(Vector3(0, ridge + 0.35, gz), Vector3(1.5, 0.7, 0.75), 1)
	for s: float in [-1.0, 1.0]:
		m.box(Vector3(s * 0.6, ridge + 1.25, gz), Vector3(0.3, 1.1, 0.7), 1)
	m.prism(Vector3(-0.85, ridge + 1.8, gz - 0.42), Vector3.RIGHT, Vector3.UP, PackedVector2Array([Vector2(0, 0), Vector2(1.7, 0), Vector2(0.85, 0.75)]), 0.84, true, true)
	m.mat(L.IRON, Color(0.65, 0.55, 0.38), 0.0)
	m.lathe(Vector3(0, ridge + 0.85, gz), PackedVector2Array([Vector2(0.32, 0.0), Vector2(0.27, 0.12), Vector2(0.2, 0.45), Vector2(0.12, 0.62), Vector2(0.0, 0.66)]), 12, false, true)
	m.cylinder(Vector3(-0.45, ridge + 1.55, gz), Vector3(0.45, ridge + 1.55, gz), 0.04, -1.0, 6)
	# A stone cross on the back gable.
	m.mat(L.ASHLAR, stone, wear)
	m.box(Vector3(0, ridge + 0.55, -d * 0.5 + t * 0.5), Vector3(0.16, 1.1, 0.16), 1)
	m.box(Vector3(0, ridge + 0.75, -d * 0.5 + t * 0.5), Vector3(0.6, 0.16, 0.16), 0)
	# Interior: flagstones, pews, altar.
	b.interior.mat(L.COBBLE, Color(0.9, 0.88, 0.84), 0.0, 0.9)
	b.interior.rect(Vector3(-w * 0.5 + t * 0.5, 0.005, d * 0.5 - t * 0.5), Vector3.RIGHT, Vector3.FORWARD, w - t, d - t)
	VillageProps.chapel_furniture(b, spec, rng, t)


static func _lancet(b: ArchBuild, h: Rect2, t: float, stone: Color) -> void:
	var m := b.detail
	# Glazing with a pointed head of dressed stone.
	m.mat(L.GLASS, Color(1, 1, 1), 1.0)
	m.rect(Vector3(h.position.x, h.position.y, -t * 0.5), Vector3.RIGHT, Vector3.UP, h.size.x, h.size.y)
	m.mat(L.GLASS, Color(1, 1, 1), 0.0)
	m.rect(Vector3(h.end.x, h.position.y, -t * 0.5 - 0.01), Vector3.LEFT, Vector3.UP, h.size.x, h.size.y)
	m.mat(L.ASHLAR, stone * Color(1.05, 1.03, 1.0), 0.4)
	var hw := h.size.x * 0.5 + 0.16
	var pts := PackedVector2Array([Vector2(-hw, 0), Vector2(hw, 0), Vector2(hw, 0.2), Vector2(0, 0.75), Vector2(-hw, 0.2)])
	m.prism(Vector3(h.get_center().x, h.end.y - 0.02, -t - 0.01), Vector3.RIGHT, Vector3.UP, pts, t + 0.06, false, true)
	m.box(Vector3(h.get_center().x, h.position.y - 0.06, -t * 0.5 + 0.04), Vector3(h.size.x + 0.3, 0.12, t + 0.08), 0)
	for s: float in [-1.0, 1.0]:
		var x := h.position.x - 0.08 if s < 0.0 else h.end.x + 0.08
		m.box(Vector3(x, h.get_center().y, 0.02 - 0.04), Vector3(0.16, h.size.y, 0.1), 1)


## A pointed arch of voussoirs over the chapel door.
static func _arch_head(b: ArchBuild, h: Rect2, t: float, stone: Color) -> void:
	var m := b.shell
	m.mat(L.ASHLAR, stone * Color(1.06, 1.04, 1.0), 0.4)
	var c := h.get_center().x
	var y := h.end.y + 0.24
	var n := 9
	var r := h.size.x * 0.5 + 0.15
	for i in n:
		var a0 := PI * float(i) / n
		var a1 := PI * float(i + 1) / n
		var mid := (a0 + a1) * 0.5
		var p := Vector3(c - cos(mid) * r, y + sin(mid) * r * 0.9, -t * 0.5 + 0.03)
		m.push(Transform3D(Basis(Vector3.BACK, mid - PI * 0.5), p))
		m.box(Vector3.ZERO, Vector3(r * (a1 - a0) * 0.97, 0.36, t + 0.06), 0)
		m.pop()


# --- Far LOD -----------------------------------------------------------------------

## A few dozen triangles per building: walls block and roof prism.
static func _far(b: ArchBuild, spec: Dictionary, xf: Transform3D) -> void:
	var m := b.far
	var w := float(spec["w"])
	var d := float(spec["d"])
	var wall_h := float(spec.get("wall_h", 3.0)) + float(spec.get("raise", 0.0))
	var kind := String(spec["kind"])
	var roof_kind := String(spec.get("roof", "thatch"))
	var ridge_z := kind == "chapel"
	m.push(xf)
	var wall_layer := L.PLASTER
	var tint: Color = _style(spec, "plaster", Color(0.9, 0.86, 0.78))
	if kind in ["stone", "chapel", "smithy"]:
		wall_layer = L.RUBBLE
		tint = _style(spec, "stone", Color(0.95, 0.92, 0.86))
	elif kind in ["longhouse", "stilt"] or String(_style(spec, "walls", "")) == "boards":
		wall_layer = L.BOARDS
		tint = _style(spec, "timber", Color(0.55, 0.42, 0.32))
	m.mat(wall_layer, tint, 0.3)
	m.box(Vector3(0, wall_h * 0.5 - 0.5, 0), Vector3(w, wall_h + 1.0, d), 1, 8)
	var roof_layer := {"thatch": L.THATCH, "slate": L.SLATE, "shingle": L.SHINGLE}.get(roof_kind, L.THATCH) as int
	m.mat(roof_layer, _style(spec, "roof_tint", Color(1, 1, 1)), 0.3)
	m.snow = float(_style(spec, "snow", 0.0))
	var pitch := deg_to_rad(float(spec.get("pitch", 52.0 if kind == "chapel" else (50.0 if roof_kind == "thatch" else 42.0))))
	var span := w if ridge_z else d
	var length := (d if ridge_z else w) + 0.8
	var rise := span * 0.5 * tan(pitch)
	var e := 0.5
	if ridge_z:
		m.push(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO))
	var y0 := wall_h - e * tan(pitch)
	var hz := span * 0.5 + e
	var a0 := Vector3(-length * 0.5, y0, hz)
	var a1 := Vector3(length * 0.5, y0, hz)
	var top0 := Vector3(-length * 0.5, wall_h + rise + 0.3, 0)
	var top1 := Vector3(length * 0.5, wall_h + rise + 0.3, 0)
	var sl := (top0 - a0).length()
	m.quad(a0, a1, top1, top0, Vector2(0, 0), Vector2(length, 0), Vector2(length, -sl), Vector2(0, -sl))
	var b0 := Vector3(length * 0.5, y0, -hz)
	var b1 := Vector3(-length * 0.5, y0, -hz)
	m.quad(b0, b1, top0, top1, Vector2(0, 0), Vector2(length, 0), Vector2(length, -sl), Vector2(0, -sl))
	m.mat(wall_layer, tint, 0.3)
	for s: float in [-1.0, 1.0]:
		var x := s * (length * 0.5 - 0.4)
		m.tri(Vector3(x, wall_h, -span * 0.5), Vector3(x, wall_h, span * 0.5), Vector3(x, wall_h + rise, 0), Vector2(0, 0), Vector2(span, 0), Vector2(span * 0.5, -rise), Vector3(s, 0, 0))
	if ridge_z:
		m.pop()
	m.snow = 0.0
	m.pop()


static func _far_shed(_b: ArchBuild, _spec: Dictionary) -> void:
	pass


## A gabled dormer on the front slope at x = cx: cheeks, a casement and a
## little roof running back into the main roof.
static func _dormer(b: ArchBuild, cx: float, d: float, wall_h: float, pitch: float, th: float, roof_layer: int, roof_tint: Color, wall_layer: int, wall_tint: Color, timber: Color, lit: bool) -> void:
	var m := b.shell
	var tn := tan(pitch)
	var top_at := func(z: float) -> float: return wall_h + (d * 0.5 - absf(z)) * tn + th / cos(pitch)
	var zf := d * 0.5 - 0.35
	var y0: float = top_at.call(zf) - 0.15
	var hw := 0.75
	var front_h := 1.35
	var yr := y0 + front_h + hw * 0.9
	var zb := d * 0.5 - (yr - wall_h - th / cos(pitch)) / tn
	var ye := y0 + front_h
	var ze := d * 0.5 - (ye - wall_h - th / cos(pitch)) / tn
	# Front wall with the window.
	m.mat(wall_layer, wall_tint, 0.4)
	b.push(Transform3D(Basis.IDENTITY, Vector3(cx - hw, y0, zf)))
	ArchKit.wall(m, hw * 2.0, 0.0, front_h, 0.12, [Rect2(hw - 0.38, 0.3, 0.76, 0.85)], wall_layer, wall_tint, 0.4, -1)
	m.mat(wall_layer, wall_tint, 0.4)
	m.tri(Vector3(0, front_h, 0), Vector3(hw * 2.0, front_h, 0), Vector3(hw, front_h + hw * 0.9, 0), Vector2(0, -front_h), Vector2(hw * 2.0, -front_h), Vector2(hw, -front_h - 0.7), Vector3.BACK)
	ArchKit.window(b, Rect2(hw - 0.38, 0.3, 0.76, 0.85), 0.12, timber, L.TIMBER, timber, lit, false, Color(0, 0, 0, 0))
	b.pop()
	# Cheeks down to the roof.
	m.mat(wall_layer, wall_tint * Color(0.95, 0.95, 0.95), 0.4)
	for s: float in [-1.0, 1.0]:
		var x := cx + s * hw
		var n := Vector3(s, 0, 0)
		m.tri(Vector3(x, y0, zf), Vector3(x, ye, zf), Vector3(x, ye, ze), Vector2(zf, -y0), Vector2(zf, -ye), Vector2(ze, -ye), n)
	# The dormer's own roof.
	m.mat(roof_layer, roof_tint, 0.4)
	for s: float in [-1.0, 1.0]:
		var e0 := Vector3(cx + s * (hw + 0.12), ye - 0.1, zf + 0.12)
		var e1 := Vector3(cx + s * (hw + 0.12), ye - 0.1, ze)
		var r0 := Vector3(cx, yr + 0.06, zf + 0.12)
		var r1 := Vector3(cx, yr + 0.06, zb)
		var n := Vector3(s * 0.67, 0.74, 0).normalized()
		m.quad(e0, e1, r1, r0, Vector2(0, 0), Vector2(zf - ze, 0), Vector2(zf - zb, -1.1), Vector2(0, -1.1), n)
	m.mat(L.BOARDS, timber, 0.3)
	for s: float in [-1.0, 1.0]:
		m.beam(Vector3(cx + s * (hw + 0.14), ye - 0.14, zf + 0.15), Vector3(cx, yr + 0.02, zf + 0.15), 0.2, 0.04, Vector3.BACK)


## A planted window box under a casement (wall frame).
static func _window_box(b: ArchBuild, r: Rect2, rng: RandomNumberGenerator, timber: Color) -> void:
	var m := b.detail
	var c := Vector3(r.get_center().x, r.position.y - 0.22, 0.2)
	m.mat(L.BOARDS, timber * Color(1.2, 1.1, 1.0), 0.4)
	m.box(c, Vector3(r.size.x + 0.12, 0.2, 0.24), 0)
	m.mat(L.IRON, Color(0.6, 0.6, 0.6), 0.0)
	for s: float in [-1.0, 1.0]:
		m.beam(c + Vector3(s * r.size.x * 0.35, -0.1, -0.1), c + Vector3(s * r.size.x * 0.35, -0.3, -0.19), 0.025, 0.025)
	var bloom: Color = [Color(0.85, 0.15, 0.12), Color(0.95, 0.75, 0.2), Color(0.75, 0.3, 0.6), Color(0.95, 0.9, 0.85)][rng.randi() % 4]
	var n := int(r.size.x / 0.13)
	for i in n:
		var q := c + Vector3(-r.size.x * 0.5 + 0.08 + i * 0.13 + rng.randf_range(-0.03, 0.03), 0.1, rng.randf_range(-0.06, 0.06))
		m.mat(L.FLAT, Color(0.2, 0.36, 0.14) * rng.randf_range(0.8, 1.2), 0.0)
		m.lathe(q, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.07, 0.06), Vector2(0.05, 0.14), Vector2(0.0, 0.16)]), 6, false, false, rng.randf())
		if rng.randf() < 0.7:
			m.mat(L.FLAT, bloom * rng.randf_range(0.85, 1.1), 0.0)
			m.lathe(q + Vector3(rng.randf_range(-0.03, 0.03), 0.13, 0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.045, 0.03), Vector2(0.0, 0.06)]), 5, false, false)
