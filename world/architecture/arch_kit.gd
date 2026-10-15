class_name ArchKit
extends RefCounted
## Architectural parts emitted into ArchMesh buckets: walls with openings,
## timber framing, windows, doors, gable roofs (thatch, slate, shingle),
## chimneys and hearths. Worker-thread safe (pure geometry).
##
## Building frame: origin at the footprint centre on the floor (y = 0 is the
## floor top), +x along the width, +z out of the front (door) wall.
## Wall frame (side_frame): x along the wall as seen from outside, y up,
## z out of the wall; the outer face is z = 0, the wall runs to z = -t.

const L = ArchMaterials.L

const WINDOW_SILL := 0.95
const WINDOW_H := 1.05
const DOOR_H := 2.12


## Wall frame of side 0 front (+z), 1 back (-z), 2 left (-x), 3 right (+x).
static func side_frame(side: int, w: float, d: float) -> Transform3D:
	match side:
		0:
			return Transform3D(Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK), Vector3(-w * 0.5, 0, d * 0.5))
		1:
			return Transform3D(Basis(Vector3.LEFT, Vector3.UP, Vector3.FORWARD), Vector3(w * 0.5, 0, -d * 0.5))
		2:
			return Transform3D(Basis(Vector3.BACK, Vector3.UP, Vector3.LEFT), Vector3(-w * 0.5, 0, -d * 0.5))
	return Transform3D(Basis(Vector3.FORWARD, Vector3.UP, Vector3.RIGHT), Vector3(w * 0.5, 0, d * 0.5))


static func side_length(side: int, w: float, d: float) -> float:
	return w if side < 2 else d


# --- Walls ---------------------------------------------------------------------

## Rectangles of [u0, u1] x [v0, v1] not covered by any hole (Rect2 list).
static func solid_rects(u0: float, u1: float, v0: float, v1: float, holes: Array) -> Array[Rect2]:
	var cuts: Array[float] = [u0, u1]
	for h: Rect2 in holes:
		for x: float in [h.position.x, h.end.x]:
			if x > u0 + 0.001 and x < u1 - 0.001:
				cuts.append(x)
	cuts.sort()
	var out: Array[Rect2] = []
	for i in cuts.size() - 1:
		var a := cuts[i]
		var b := cuts[i + 1]
		if b - a < 0.001:
			continue
		var mid := (a + b) * 0.5
		var spans: Array[Vector2] = [Vector2(v0, v1)]
		for h: Rect2 in holes:
			if mid > h.position.x and mid < h.end.x:
				var next: Array[Vector2] = []
				for s in spans:
					if h.end.y <= s.x or h.position.y >= s.y:
						next.append(s)
						continue
					if h.position.y > s.x:
						next.append(Vector2(s.x, h.position.y))
					if h.end.y < s.y:
						next.append(Vector2(h.end.y, s.y))
				spans = next
		for s in spans:
			if s.y - s.x > 0.001:
				out.append(Rect2(a, s.x, b - a, s.y - s.x))
	return out


## A wall slab in the current wall frame. Outer face over u 0..length, inner
## face (when inner_layer >= 0) over inner_from..inner_to. Holes get reveals.
static func wall(m: ArchMesh, length: float, base: float, height: float, t: float, holes: Array,
		outer_layer: int, outer_tint: Color, wear: float,
		inner_layer := -1, inner_tint := Color(1, 1, 1), inner_from := 0.0, inner_to := -1.0, top := true) -> void:
	if inner_to < 0.0:
		inner_to = length
	m.mat(outer_layer, outer_tint, wear)
	for r in solid_rects(0.0, length, base, height, holes):
		m.rect(Vector3(r.position.x, r.position.y, 0.0), Vector3.RIGHT, Vector3.UP, r.size.x, r.size.y, Vector2(r.position.x, -r.position.y))
	for h: Rect2 in holes:
		var hb := maxf(h.position.y, base)
		var hh := minf(h.end.y, height) - hb
		if hh <= 0.0:
			continue
		m.rect(Vector3(h.position.x, hb, 0.0), Vector3.FORWARD, Vector3.UP, t, hh, Vector2(0, -hb))
		m.rect(Vector3(h.end.x, hb, -t), Vector3.BACK, Vector3.UP, t, hh, Vector2(0, -hb))
		if h.end.y < height:
			m.rect(Vector3(h.position.x, h.end.y, -t), Vector3.RIGHT, Vector3.BACK, h.size.x, t, Vector2(h.position.x, 0))
		if h.position.y > base:
			m.rect(Vector3(h.position.x, h.position.y, 0.0), Vector3.RIGHT, Vector3.FORWARD, h.size.x, t, Vector2(h.position.x, 0))
	if top:
		m.rect(Vector3(0.0, height, 0.0), Vector3.RIGHT, Vector3.FORWARD, length, t, Vector2.ZERO)
	if inner_layer >= 0:
		m.mat(inner_layer, inner_tint, wear * 0.3)
		for r in solid_rects(inner_from, inner_to, base, height, holes):
			m.rect(Vector3(r.end.x, r.position.y, -t), Vector3.LEFT, Vector3.UP, r.size.x, r.size.y, Vector2(-r.end.x, -r.position.y))


## Triangular gable infill in the wall frame: base at height h over u 0..length,
## apex at (length / 2, h + rise). Optional inner face.
static func gable(m: ArchMesh, length: float, h: float, rise: float, t: float, layer: int, tint: Color, wear: float, inner := false, inner_layer := L.PLASTER, inner_tint := Color(1, 1, 1)) -> void:
	m.mat(layer, tint, wear)
	var pts := PackedVector2Array([Vector2(0, h), Vector2(length, h), Vector2(length * 0.5, h + rise)])
	m.prism(Vector3(0, 0, -t), Vector3.RIGHT, Vector3.UP, pts, t, false, false)
	if inner:
		m.mat(inner_layer, inner_tint, wear * 0.3)
		m.tri(Vector3(0, h, -t), Vector3(length, h, -t), Vector3(length * 0.5, h + rise, -t),
				Vector2(0, -h), Vector2(length, -h), Vector2(length * 0.5, -h - rise), Vector3.FORWARD)


# --- Timber framing ------------------------------------------------------------

## Exposed oak frame over a plastered wall (wall frame). Posts flank every
## hole and stand at most ~1.6 m apart; rails at the sill, window head and
## wall plate; braces in the closed bays near the corners. `corners` adds the
## square corner posts (front and back walls only, so corners never overlap).
static func timber_frame(m: ArchMesh, length: float, height: float, holes: Array, corners: bool, rng: RandomNumberGenerator, tint: Color, base := 0.42, braces := true, pattern := 0) -> void:
	m.mat(L.TIMBER, tint, 0.35)
	var post_w := 0.2
	var posts: Array[float] = []
	if corners:
		m.beam(Vector3(0.0925, base, -0.1), Vector3(0.0925, height, -0.1), 0.315, 0.32, Vector3.BACK, 0.025)
		m.beam(Vector3(length - 0.0925, base, -0.1), Vector3(length - 0.0925, height, -0.1), 0.315, 0.32, Vector3.BACK, 0.025)
	var edges: Array[float] = [0.25, length - 0.25]
	for h: Rect2 in holes:
		edges.append(h.position.x - post_w * 0.5 - 0.03)
		edges.append(h.end.x + post_w * 0.5 + 0.03)
	edges.sort()
	# Fill long gaps with evenly spaced studs.
	posts.append(edges[0])
	for i in range(1, edges.size()):
		var a := posts[posts.size() - 1]
		var b := edges[i]
		if b - a < 0.35:
			continue
		var n := int(ceil((b - a) / 1.6))
		for k in range(1, n):
			posts.append(lerpf(a, b, float(k) / n))
		posts.append(b)
	for i in posts.size():
		var u := posts[i]
		if i == 0 or i == posts.size() - 1:
			continue  # corner posts (or the neighbouring wall's) stand here
		var wob := rng.randf_range(-0.012, 0.012)
		m.beam(Vector3(u, base, -0.07), Vector3(u + wob, height, -0.07), post_w, 0.24, Vector3.BACK, 0.02)
	# Rails between posts.
	var rails := [base + 0.1, WINDOW_SILL - 0.06, WINDOW_SILL + WINDOW_H + 0.06, height - 0.11]
	for ri in rails.size():
		var v: float = rails[ri]
		var rh := 0.2 if ri == 0 or ri == rails.size() - 1 else 0.16
		for i in posts.size() - 1:
			var a := posts[i] + post_w * 0.5
			var b := posts[i + 1] - post_w * 0.5
			if i == 0:
				a = 0.25
			if i == posts.size() - 2:
				b = length - 0.25
			if b - a < 0.05:
				continue
			var mid := (a + b) * 0.5
			var blocked := false
			for h: Rect2 in holes:
				if mid > h.position.x and mid < h.end.x and v > h.position.y - 0.12 and v < h.end.y + 0.12:
					# The rail becomes the hole's sill / head instead.
					if absf(v - h.position.y) > 0.13 and absf(v - h.end.y) > 0.13:
						blocked = true
			if blocked:
				continue
			m.beam(Vector3(a, v, -0.075), Vector3(b, v, -0.075), rh, 0.24, Vector3.BACK, 0.015)
	if not braces:
		return
	# Braces in closed bays: lower panels get a diagonal, some a St Andrew's cross.
	for i in posts.size() - 1:
		var a := posts[i] + post_w * 0.5
		var b := posts[i + 1] - post_w * 0.5
		if b - a < 0.6:
			continue
		var mid := (a + b) * 0.5
		var closed := true
		for h: Rect2 in holes:
			if mid > h.position.x - 0.1 and mid < h.end.x + 0.1:
				closed = false
		if not closed:
			# Under a window: a small cross in the sill panel.
			if pattern == 1:
				var y0: float = rails[0] + 0.1
				var y1: float = rails[1] - 0.08
				m.beam(Vector3(a, y0, -0.08), Vector3(b, y1, -0.08), 0.12, 0.2, Vector3.BACK, 0.012)
				m.beam(Vector3(a, y1, -0.085), Vector3(b, y0, -0.085), 0.12, 0.2, Vector3.BACK, 0.012)
			continue
		var near_corner := i == 0 or i == posts.size() - 2
		if near_corner or rng.randf() < 0.35:
			var lo: float = rails[0] + 0.1
			var hi: float = rails[3] - 0.1
			if i == 0:
				m.beam(Vector3(a, lo, -0.08), Vector3(b, hi, -0.08), 0.16, 0.2, Vector3.BACK, 0.015)
			else:
				m.beam(Vector3(b, lo, -0.08), Vector3(a, hi, -0.08), 0.16, 0.2, Vector3.BACK, 0.015)


## King post, collar and struts on a gable (wall frame of the gable side).
static func gable_frame(m: ArchMesh, length: float, h: float, rise: float, tint: Color) -> void:
	m.mat(L.TIMBER, tint, 0.35)
	var c := length * 0.5
	m.beam(Vector3(c, h, -0.07), Vector3(c, h + rise - 0.25, -0.07), 0.2, 0.24, Vector3.BACK, 0.02)
	var collar_y := h + rise * 0.42
	var half := length * 0.5 * (1.0 - 0.42) - 0.15
	m.beam(Vector3(c - half, collar_y, -0.075), Vector3(c + half, collar_y, -0.075), 0.18, 0.22, Vector3.BACK, 0.015)
	for s: float in [-1.0, 1.0]:
		m.beam(Vector3(c + s * 0.1, h + 0.12, -0.08), Vector3(c + s * half * 0.75, collar_y - 0.06, -0.08), 0.14, 0.2, Vector3.BACK, 0.012)


# --- Openings ------------------------------------------------------------------

## Casement window in a hole `r` of a wall of thickness t (wall frame).
## lit: the window glows at night. inner: also glazed from inside.
static func window(b: ArchBuild, r: Rect2, t: float, frame_tint: Color, sill_layer: int, sill_tint: Color, lit: bool, inner: bool, shutters: Color, shutter_z := 0.0) -> void:
	var m := b.shell
	var fz := -minf(0.11, t * 0.4)
	m.mat(L.TIMBER, frame_tint, 0.2)
	var fw := 0.075
	m.box(Vector3(r.position.x + fw * 0.5, r.get_center().y, fz), Vector3(fw, r.size.y, 0.1), 1)
	m.box(Vector3(r.end.x - fw * 0.5, r.get_center().y, fz), Vector3(fw, r.size.y, 0.1), 1)
	m.box(Vector3(r.get_center().x, r.end.y - fw * 0.5, fz), Vector3(r.size.x - fw * 2.0, fw, 0.1), 0)
	m.box(Vector3(r.get_center().x, r.position.y + fw * 0.5, fz), Vector3(r.size.x - fw * 2.0, fw, 0.1), 0)
	# Mullion and transom.
	m.box(Vector3(r.get_center().x, r.get_center().y, fz + 0.005), Vector3(0.05, r.size.y - fw * 2.0, 0.07), 1)
	var ty := r.position.y + r.size.y * 0.66
	m.box(Vector3(r.get_center().x, ty, fz + 0.006), Vector3(r.size.x - fw * 2.0, 0.045, 0.07), 0)
	# Glass.
	m.mat(L.GLASS, Color(1, 1, 1), 1.0 if lit else 0.0)
	var g0 := Vector3(r.position.x + fw, r.position.y + fw, fz)
	m.rect(g0, Vector3.RIGHT, Vector3.UP, r.size.x - fw * 2.0, r.size.y - fw * 2.0, Vector2(g0.x, -g0.y))
	if inner:
		m.mat(L.GLASS, Color(1, 1, 1), 0.0)
		m.rect(Vector3(r.end.x - fw, r.position.y + fw, fz - 0.01), Vector3.LEFT, Vector3.UP, r.size.x - fw * 2.0, r.size.y - fw * 2.0)
	# Sill: projects and sheds rain.
	m.mat(sill_layer, sill_tint, 0.6)
	m.box(Vector3(r.get_center().x, r.position.y - 0.045, -0.02), Vector3(r.size.x + 0.18, 0.09, 0.2), 0)
	if shutters.a > 0.0:
		for s: float in [-1.0, 1.0]:
			var pw := r.size.x * 0.5 + 0.02
			var cx := r.position.x - pw * 0.5 - 0.03 if s < 0.0 else r.end.x + pw * 0.5 + 0.03
			_shutter(b.detail, Vector3(cx, r.get_center().y, shutter_z + 0.022), pw, r.size.y + 0.04, shutters, s)


static func _shutter(m: ArchMesh, c: Vector3, w: float, h: float, tint: Color, side: float) -> void:
	m.mat(L.BOARDS, tint, 0.4)
	m.box(c, Vector3(w, h, 0.035), 1)
	for y: float in [-h * 0.32, h * 0.32]:
		m.box(c + Vector3(0, y, 0.025), Vector3(w - 0.04, 0.09, 0.025), 0)
	m.beam(c + Vector3(-w * 0.4 * side, -h * 0.26, 0.026), c + Vector3(w * 0.4 * side, h * 0.26, 0.026), 0.07, 0.022, Vector3.BACK)
	m.mat(L.IRON, Color(0.8, 0.8, 0.8), 0.0)
	for y: float in [-h * 0.32, h * 0.32]:
		m.box(c + Vector3(side * w * 0.15, y, 0.042), Vector3(w * 0.75, 0.035, 0.008), 0)


## Plank door in hole `r` (u0, 0, w, h). open: swung into the room.
static func door(b: ArchBuild, r: Rect2, t: float, frame_layer: int, frame_tint: Color, leaf_tint: Color, open: bool, wide := false) -> void:
	var m := b.shell
	m.mat(frame_layer, frame_tint, 0.3)
	var jw := 0.16
	var z0 := -t - 0.015
	var z1 := 0.06
	m.box(Vector3(r.position.x - jw * 0.5 + 0.012, r.size.y * 0.5, (z0 + z1) * 0.5), Vector3(jw, r.size.y, z1 - z0), 1)
	m.box(Vector3(r.end.x + jw * 0.5 - 0.012, r.size.y * 0.5, (z0 + z1) * 0.5), Vector3(jw, r.size.y, z1 - z0), 1)
	m.box(Vector3(r.get_center().x, r.size.y + 0.11, (z0 + z1) * 0.5 + 0.005), Vector3(r.size.x + 0.5, 0.24, z1 - z0 + 0.01), 0)
	# Threshold stone.
	m.mat(L.ASHLAR, Color(0.85, 0.83, 0.8), 0.4)
	m.box(Vector3(r.get_center().x, -0.04, -t * 0.5 + 0.12), Vector3(r.size.x + 0.3, 0.12, t + 0.24), 0)
	var leaves := 2 if wide else 1
	var lw := r.size.x / leaves
	for k in leaves:
		var hinge := Vector3(r.position.x + 0.02, 0.02, -t + 0.05) if k == 0 else Vector3(r.end.x - 0.02, 0.02, -t + 0.05)
		var dir := 1.0 if k == 0 else -1.0
		var angle := (1.85 if open else 0.0) * dir
		var basis := Basis(Vector3.UP, angle)
		var leaf_xf := Transform3D(basis, hinge)
		if not open:
			leaf_xf = Transform3D(Basis.IDENTITY, Vector3(hinge.x, hinge.y, -0.13))
		m.push(leaf_xf)
		_leaf(m, lw - 0.04, r.size.y - 0.04, dir, leaf_tint)
		m.pop()


## A ledged and braced plank leaf in its own frame: hinge edge at x = 0, the
## leaf runs along +x (dir 1) or -x (dir -1), outer face +z.
static func _leaf(m: ArchMesh, w: float, h: float, dir: float, tint: Color) -> void:
	var cx := w * 0.5 * dir
	m.mat(L.BOARDS, tint, 0.35)
	m.box(Vector3(cx, h * 0.5, 0.0), Vector3(w, h, 0.055), 1)
	# Ledges and brace on the inside.
	for y: float in [0.25, h * 0.5, h - 0.25]:
		m.box(Vector3(cx, y, -0.045), Vector3(w - 0.08, 0.13, 0.035), 0)
	m.beam(Vector3(cx - w * 0.38, 0.32, -0.045), Vector3(cx + w * 0.38, h * 0.5 - 0.06, -0.045), 0.1, 0.03, Vector3.BACK)
	m.beam(Vector3(cx - w * 0.38, h * 0.5 + 0.06, -0.045), Vector3(cx + w * 0.38, h - 0.32, -0.045), 0.1, 0.03, Vector3.BACK)
	# Iron strap hinges, ring handle and studs outside.
	m.mat(L.IRON, Color(0.85, 0.85, 0.85), 0.0)
	for y: float in [0.3, h - 0.3]:
		m.box(Vector3(w * 0.36 * dir, y, 0.032), Vector3(w * 0.72, 0.05, 0.01), 0)
		m.lathe(Vector3(w * 0.72 * dir, y, 0.03), PackedVector2Array([Vector2(0.035, -0.006), Vector2(0.035, 0.006)]), 6)
	var hx := (w - 0.14) * dir
	m.cylinder(Vector3(hx, 1.0, 0.03), Vector3(hx, 1.0, 0.06), 0.035, -1.0, 6)
	m.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(hx, 0.93, 0.07)))
	m.lathe(Vector3.ZERO, PackedVector2Array([Vector2(0.06, -0.008), Vector2(0.075, 0.0), Vector2(0.06, 0.008), Vector2(0.06, -0.008)]), 10, false, false)
	m.pop()


## Small pent hood over a door: two brackets and a little shingled roof.
static func door_hood(b: ArchBuild, cx: float, y: float, w: float, roof_layer: int, roof_tint: Color, wood: Color) -> void:
	var m := b.detail
	m.mat(L.TIMBER, wood, 0.3)
	for s: float in [-1.0, 1.0]:
		var x := cx + s * (w * 0.5 - 0.12)
		m.beam(Vector3(x, y - 0.55, 0.02), Vector3(x, y + 0.02, 0.72), 0.1, 0.12, Vector3.RIGHT, 0.01)
		m.beam(Vector3(x, y, 0.0), Vector3(x, y, 0.78), 0.1, 0.12, Vector3.RIGHT, 0.01)
	var pitch := deg_to_rad(28.0)
	var o := Vector3(cx - w * 0.5, y + 0.07, 0.9)
	var v := Vector3(0, sin(pitch), -cos(pitch))
	var length := 0.95 / cos(pitch)
	m.mat(roof_layer, roof_tint, 0.5)
	m.rect(o, Vector3.RIGHT, v, w, length, Vector2(o.x, 0))
	m.mat(L.BOARDS, wood, 0.2)
	m.rect(o + Vector3(w, -0.04, 0), Vector3.LEFT, v, w, length)
	m.box(Vector3(cx, o.y - 0.02, o.z), Vector3(w + 0.02, 0.09, 0.04), 0)


# --- Roofs ---------------------------------------------------------------------

## Gable roof over a w x d footprint (building frame), ridge along x.
## opts: kind ("thatch" | "slate" | "shingle"), pitch (deg), eave, verge,
## tint, wood (bargeboards / rafters), interior (rafters inside), horns
## (crossed bargeboards past the ridge), snow. Returns the ridge height.
static func gable_roof(b: ArchBuild, w: float, d: float, wall_h: float, opts: Dictionary) -> float:
	var kind: String = opts.get("kind", "thatch")
	var pitch := deg_to_rad(float(opts.get("pitch", 48.0)))
	var eave: float = opts.get("eave", 0.55)
	var verge: float = opts.get("verge", 0.35)
	var tint: Color = opts.get("tint", Color(1, 1, 1))
	var wood: Color = opts.get("wood", Color(0.62, 0.5, 0.4))
	var wear: float = opts.get("wear", 0.4)
	var c := cos(pitch)
	var s := sin(pitch)
	var tn := tan(pitch)
	var th := 0.42 if kind == "thatch" else 0.1
	var ridge := wall_h + d * 0.5 * tn
	var lr := w + verge * 2.0
	for side: float in [1.0, -1.0]:
		# Slope frame: origin at the underside eave line, u along x, v up the slope.
		var basis := Basis(Vector3.RIGHT, Vector3(0, s, -c), Vector3(0, c, s))
		var o := Vector3(-w * 0.5 - verge, wall_h - eave * tn, d * 0.5 + eave)
		var xf := Transform3D(basis, o)
		if side < 0.0:
			xf = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * xf
		var lu := (d * 0.5 + eave) / c
		var lt := (d * 0.5 + eave + th * s) / c
		b.push(xf)
		if kind == "thatch":
			_thatch_side(b, lr, lu, lt, th, tint, wear, opts.get("interior", false), wood)
		else:
			_tiled_side(b, kind, lr, lu, lt, th, tint, wear, wood)
		_eave_rafters(b, lr, verge, eave / c, wood, w)
		if kind != "thatch" and opts.get("interior", false):
			_inner_rafters(b, lr, lu, wood, (eave + 0.5) / c)
		b.pop()
	# Ridge.
	var apex := ridge + th / c
	if kind == "thatch":
		b.shell.mat(L.THATCH, tint * Color(0.92, 0.9, 0.84), wear * 0.6)
		b.shell.cylinder(Vector3(-lr * 0.5 - 0.06, apex - 0.16, 0), Vector3(lr * 0.5 + 0.06, apex - 0.16, 0), 0.24, -1.0, 10)
	elif kind == "slate":
		b.shell.mat(L.ASHLAR, Color(0.45, 0.45, 0.47), 0.3)
		b.shell.cylinder(Vector3(-lr * 0.5 - 0.02, apex - 0.02, 0), Vector3(lr * 0.5 + 0.02, apex - 0.02, 0), 0.09, -1.0, 8)
	else:
		b.shell.mat(L.BOARDS, wood * Color(0.85, 0.85, 0.85), 0.5)
		for sd: float in [1.0, -1.0]:
			var down := Vector3(0, -s, c * sd)
			var nrm := Vector3(0, c, s * sd)
			var mid := Vector3(0, apex + 0.03, 0) + down * 0.1 + nrm * 0.02
			b.shell.beam(mid - Vector3(lr * 0.5 + 0.02, 0, 0), mid + Vector3(lr * 0.5 + 0.02, 0, 0), 0.24, 0.035, nrm)
	# Bargeboards on the gable verges.
	if kind != "thatch" or opts.get("horns", false):
		var horn: float = 0.85 if opts.get("horns", false) else 0.0
		b.shell.mat(L.BOARDS, wood, 0.5)
		for end: float in [-1.0, 1.0]:
			var x := end * (lr * 0.5 + 0.025)
			for sd: float in [1.0, -1.0]:
				var nrm := Vector3(0, c, s * sd)
				var eave_pt := Vector3(x, wall_h - eave * tn + th * c, sd * (d * 0.5 + eave + th * s)) - nrm * 0.13
				var top_pt := Vector3(x, apex, 0) - nrm * 0.13
				var dir := (top_pt - eave_pt).normalized()
				b.shell.beam(eave_pt - dir * 0.05, top_pt + dir * (horn + 0.04), 0.3, 0.05, Vector3.RIGHT)
	return ridge


static func _thatch_side(b: ArchBuild, lr: float, lu: float, lt: float, th: float, tint: Color, wear: float, interior: bool, wood: Color) -> void:
	var m := b.shell
	var seed_v := b.frame().origin.x * 3.1 + b.frame().origin.z * 1.7
	var lump := func(u: float, v: float) -> float:
		var edge := clampf(minf(minf(u, lr - u), minf(v, lt - v) * 1.5) / 0.6, 0.0, 1.0)
		var n := sin(u * 2.3 + seed_v) * 0.5 + sin(u * 5.1 + v * 1.3 + seed_v * 2.0) * 0.3 + sin(v * 3.7 + u * 0.7) * 0.25
		return n * 0.035 * edge
	# Top surface (lumpy), from the outer eave edge up to the ridge plane.
	m.mat(L.THATCH, tint, wear)
	var top_o := Vector3(0, 0, th)
	var nu := maxi(2, int(lr / 0.5))
	var nv := maxi(2, int(lt / 0.5))
	m.patch(top_o, Vector3.RIGHT, Vector3.UP, lr, lt, nu, nv, lump, Vector2(0.0, 0.0))
	# Underside: the reeds' cut ends.
	m.mat(L.THATCH, tint * Color(0.7, 0.66, 0.6), wear * 0.5)
	m.rect(Vector3(lr, 0, 0), Vector3.LEFT, Vector3.UP, lr, lu)
	# Thick rounded eave and verges: the thatcher's trimmed edges.
	m.mat(L.THATCH, tint * Color(0.88, 0.85, 0.78), wear)
	var steps := 4
	for i in steps:
		var a0 := float(i) / steps
		var a1 := float(i + 1) / steps
		var p0 := Vector3(0, -sin(a0 * PI) * 0.1, th * a0)
		var p1 := Vector3(0, -sin(a1 * PI) * 0.1, th * a1)
		m.quad(Vector3(0, p0.y, p0.z), Vector3(lr, p0.y, p0.z), Vector3(lr, p1.y, p1.z), Vector3(0, p1.y, p1.z),
				Vector2(0, a0 * 0.4), Vector2(lr, a0 * 0.4), Vector2(lr, a1 * 0.4), Vector2(0, a1 * 0.4),
				Vector3(0, -(p1.z - p0.z), p1.y - p0.y).normalized())
	for end: float in [0.0, 1.0]:
		var x := lr * end
		var out := -1.0 if end == 0.0 else 1.0
		for i in steps:
			var a0 := float(i) / steps
			var a1 := float(i + 1) / steps
			var z0 := th * a0
			var z1 := th * a1
			var b0 := sin(a0 * PI) * 0.08 * out
			var b1 := sin(a1 * PI) * 0.08 * out
			var vt0 := lerpf(lu, lt, a0)
			var vt1 := lerpf(lu, lt, a1)
			m.quad(Vector3(x + b0, 0, z0), Vector3(x + b1, 0, z1), Vector3(x + b1, vt1, z1), Vector3(x + b0, vt0, z0),
					Vector2(0, 0), Vector2(0.4, 0), Vector2(0.4, -vt1), Vector2(0, -vt0), Vector3(out, 0, 0))
	# Block-cut ridge band with scalloped edge, pinned by hazel spars.
	var band := PackedVector2Array()
	band.append(Vector2(lr, lt))
	band.append(Vector2(0.0, lt))
	var span := 0.6
	var n_sc := maxi(2, int(lr / span))
	for i in n_sc + 1:
		var u := lr * float(i) / n_sc
		band.append(Vector2(u, lt - 0.62))
		if i < n_sc:
			band.append(Vector2(u + lr / n_sc * 0.5, lt - 0.86))
	# Reorder to a proper outline: top edge right-to-left, then the scallops left-to-right.
	m.mat(L.THATCH, tint * Color(1.05, 1.02, 0.95), wear * 0.3)
	m.prism(Vector3(0, 0, th - 0.01), Vector3.RIGHT, Vector3.UP, band, 0.085, false, true)
	m.mat(L.TIMBER, wood * Color(1.1, 1.0, 0.9), 0.2)
	for v: float in [lt - 0.18, lt - 0.5]:
		m.beam(Vector3(0.1, v, th + 0.085), Vector3(lr - 0.1, v, th + 0.085), 0.025, 0.025, Vector3.BACK)
	var zig := maxi(2, int(lr / 0.45))
	for i in zig:
		var u0 := lr * float(i) / zig + 0.1
		var u1 := lr * float(i + 1) / zig - 0.1
		var flip := i % 2 == 0
		m.beam(Vector3(u0, lt - (0.5 if flip else 0.18), th + 0.09), Vector3(u1, lt - (0.18 if flip else 0.5), th + 0.09), 0.02, 0.02, Vector3.BACK)
	if interior:
		_inner_rafters(b, lr, lu, wood, lu * 0.25)


static func _tiled_side(b: ArchBuild, kind: String, lr: float, lu: float, lt: float, th: float, tint: Color, wear: float, wood: Color) -> void:
	var m := b.shell
	var layer := L.SLATE if kind == "slate" else L.SHINGLE
	var course: float = ArchMaterials.SLATE_COURSE if kind == "slate" else ArchMaterials.SHINGLE_COURSE
	var lift := 0.022 if kind == "slate" else 0.03
	m.mat(layer, tint, wear)
	var n := int(ceil(lt / course))
	for k in n:
		var s0 := k * course
		var s1 := minf(lt, s0 + course)
		var z0 := th + lift
		var z1 := th + lift * (1.0 - (s1 - s0) / course)
		m.quad(Vector3(0, s0, z0), Vector3(lr, s0, z0), Vector3(lr, s1, z1), Vector3(0, s1, z1),
				Vector2(0, -s0), Vector2(lr, -s0), Vector2(lr, -s1), Vector2(0, -s1), Vector3(0, -(z1 - z0), s1 - s0).normalized())
		# Butt edge of the course.
		m.quad(Vector3(0, s0, th), Vector3(lr, s0, th), Vector3(lr, s0, z0), Vector3(0, s0, z0),
				Vector2(0, -s0 + 0.01), Vector2(lr, -s0 + 0.01), Vector2(lr, -s0), Vector2(0, -s0), Vector3(0, -1, 0))
	# Underside sarking boards and the fascia covering the slab edge.
	m.mat(L.BOARDS, wood * Color(0.8, 0.78, 0.75), 0.2)
	m.rect(Vector3(lr, 0, 0), Vector3.LEFT, Vector3.UP, lr, lu)
	m.box(Vector3(lr * 0.5, 0.02, th * 0.5 + 0.005), Vector3(lr + 0.02, 0.05, th + 0.05), 0)
	for end: float in [0.0, 1.0]:
		var x := lr * end
		var out := -1.0 if end == 0.0 else 1.0
		m.quad(Vector3(x, 0, 0), Vector3(x, 0, th + lift), Vector3(x, lt, th + lift), Vector3(x, lu, 0),
				Vector2(0, 0), Vector2(th, 0), Vector2(th, -lt), Vector2(0, -lu), Vector3(out, 0, 0))


## Rafter tails under the eave overhang (and full rafters inside).
static func _eave_rafters(b: ArchBuild, lr: float, verge: float, eave: float, wood: Color, w: float) -> void:
	var m := b.detail
	m.mat(L.TIMBER, wood, 0.3)
	var n := maxi(2, int(w / 0.62))
	for i in n + 1:
		var u := verge + 0.1 + (w - 0.2) * float(i) / n
		m.beam(Vector3(u, 0.02, -0.07), Vector3(u, eave + 0.15, -0.07), 0.09, 0.13, Vector3.BACK, 0.01)


static func _inner_rafters(b: ArchBuild, lr: float, lu: float, wood: Color, start_v: float) -> void:
	var m := b.interior
	m.mat(L.TIMBER, wood, 0.2)
	var n := maxi(2, int(lr / 0.62))
	for i in n + 1:
		var u := 0.2 + (lr - 0.4) * float(i) / n
		m.beam(Vector3(u, start_v, -0.08), Vector3(u, lu - 0.1, -0.08), 0.1, 0.15, Vector3.BACK, 0.01)
	# Purlins.
	for f: float in [0.4, 0.75]:
		m.beam(Vector3(0.3, lu * f, -0.2), Vector3(lr - 0.3, lu * f, -0.2), 0.16, 0.16, Vector3.BACK, 0.015)


# --- Chimneys and hearths --------------------------------------------------------

## Stone chimney stack standing in a gable wall (building frame) at x = side *
## w / 2, rising `above` m over the ridge. With `hearth`, a fireplace opens
## into the room (fire, light) and smoke rises from the pots.
static func chimney(b: ArchBuild, side: float, w: float, d: float, ridge: float, t: float, layer: int, tint: Color, hearth: bool, above := 0.9, stack_w := 1.3) -> void:
	var m := b.shell
	var outer_x := side * (w * 0.5 + 0.28)
	var inner_x := side * (w * 0.5 - t - (0.62 if hearth else -0.02))
	var x_mid := (outer_x + inner_x) * 0.5
	var depth := absf(outer_x - inner_x)
	var top := ridge + above
	m.mat(layer, tint, 0.5)
	var dirt_y := m.dirt_y
	var dirt_h := m.dirt_h
	# Lower breast (wide), weathered shoulders, then the stack.
	var shoulder := ridge - 1.0
	m.box(Vector3(x_mid, (shoulder - 0.6) * 0.5, 0), Vector3(depth, shoulder + 0.6, stack_w), 1, (2 if side > 0.0 else 1) if hearth else 0)
	var stack_d := minf(depth, 0.95)
	var sx := outer_x - side * stack_d * 0.5
	m.box(Vector3(sx, (shoulder + top) * 0.5, 0), Vector3(stack_d, top - shoulder, stack_w * 0.72), 1)
	# Cap and pots, sooty at the top.
	m.dirt_y = top - 0.2
	m.dirt_h = -1.0
	m.mat(L.ASHLAR, tint * Color(0.9, 0.9, 0.9), 0.3, 0.55)
	m.box(Vector3(sx, top + 0.06, 0), Vector3(stack_d + 0.14, 0.12, stack_w * 0.72 + 0.14), 1)
	m.mat(L.FLAT, Color(0.5, 0.3, 0.22), 0.0, 0.5)
	for pz: float in [-0.18, 0.18]:
		m.lathe(Vector3(sx, top + 0.12, pz), PackedVector2Array([Vector2(0.12, 0.0), Vector2(0.1, 0.28), Vector2(0.13, 0.32), Vector2(0.13, 0.36)]), 8, false, false)
	m.dirt_y = dirt_y
	m.dirt_h = dirt_h
	if hearth:
		b.add_smoke(Vector3(sx, top + 0.45, 0), 1.0)
		_fireplace(b, side, inner_x, stack_w, tint, layer)


## Fireplace on the room side of a chimney breast at x = inner_x.
static func _fireplace(b: ArchBuild, side: float, inner_x: float, width: float, tint: Color, layer: int) -> void:
	var m := b.interior
	var face := Vector3(-side, 0, 0)
	var x := inner_x
	var open_w := 0.9
	var open_h := 0.95
	m.mat(layer, tint, 0.2, 0.75)
	# Breast face around the opening (the shell box has no room-side face).
	var hw := width * 0.5
	var ow := open_w * 0.5
	m.push(Transform3D(Basis(Vector3(0, 0, side), Vector3.UP, face), Vector3(x, 0, 0)))
	# Here x runs along the breast, z out into the room.
	m.rect(Vector3(-hw, 0, 0), Vector3.RIGHT, Vector3.UP, hw - ow, 2.6)
	m.rect(Vector3(ow, 0, 0), Vector3.RIGHT, Vector3.UP, hw - ow, 2.6)
	m.rect(Vector3(-ow, open_h, 0), Vector3.RIGHT, Vector3.UP, open_w, 2.6 - open_h)
	# Firebox (sooty).
	m.mat(layer, tint * Color(0.5, 0.48, 0.45), 0.0, 0.25)
	m.rect(Vector3(-ow, 0, -0.55), Vector3.RIGHT, Vector3.UP, open_w, open_h)
	m.rect(Vector3(-ow, 0, 0), Vector3.FORWARD, Vector3.UP, 0.55, open_h)
	m.rect(Vector3(ow, 0, -0.55), Vector3.BACK, Vector3.UP, 0.55, open_h)
	m.rect(Vector3(-ow, open_h, -0.55), Vector3.RIGHT, Vector3.BACK, open_w, 0.55)
	# Oak bressummer (mantel beam) and hearth stone.
	m.mat(L.TIMBER, Color(0.5, 0.38, 0.28), 0.1, 0.7)
	m.box(Vector3(0, open_h + 0.12, 0.08), Vector3(open_w + 0.5, 0.24, 0.18), 0)
	m.mat(L.ASHLAR, Color(0.7, 0.68, 0.65), 0.2, 0.6)
	m.box(Vector3(0, 0.04, 0.25), Vector3(open_w + 0.6, 0.08, 0.5), 0)
	# Logs on firedogs over glowing embers.
	m.mat(L.EMBER, Color(1, 1, 1), 0.0)
	m.lathe(Vector3(0, 0.0, -0.28), PackedVector2Array([Vector2(0.32, 0.0), Vector2(0.22, 0.06), Vector2(0.0, 0.09)]), 8, false, false)
	m.mat(L.TIMBER, Color(0.35, 0.27, 0.2), 0.0, 0.4)
	m.cylinder(Vector3(-0.3, 0.1, -0.22), Vector3(0.28, 0.12, -0.34), 0.06, -1.0, 6)
	m.cylinder(Vector3(-0.25, 0.14, -0.38), Vector3(0.3, 0.1, -0.24), 0.055, -1.0, 6)
	m.pop()
	b.add_fire(Vector3(x + side * 0.28, 0.12, 0), 0.8, 7.5, 1.9)


# --- Stairs and steps -------------------------------------------------------------

## A flight of `count` treads rising `rise` over `run` (building frame,
## starting at `a`, going along `dir`), with stringers.
static func stair(m: ArchMesh, a: Vector3, dir: Vector3, width: float, rise: float, run: float, count: int, layer: int, tint: Color) -> void:
	var side := Vector3.UP.cross(dir).normalized()
	m.mat(layer, tint, 0.4)
	for i in count:
		var c := a + dir * (run * (i + 0.5) / count) + Vector3.UP * (rise * (i + 1) / count - 0.03)
		m.push(Transform3D(Basis(side, Vector3.UP, -dir), c))
		m.box(Vector3.ZERO, Vector3(width, 0.06, run / count + 0.04), 0)
		m.pop()
	for s: float in [-1.0, 1.0]:
		var p0 := a + side * s * (width * 0.5 + 0.04)
		m.beam(p0 + Vector3.UP * 0.0, p0 + dir * run + Vector3.UP * rise, 0.06, 0.22, side)
