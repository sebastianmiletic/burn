extends RefCounted
## Procedural flora geometry, built once by Flora.warmup() on the main thread.
##
## Trees are grown as skeletons (tapered tubes + leaf cards) in metres, then meshed at
## three detail levels and normalised to unit height (the instance scale is the tree height).
## Vertex colour layout (read by the flora shaders, see flora_common.gdshaderinc):
##   trees/bushes: r branch weight (0 trunk .. 1 twig tip), g branch phase, b leaf flutter, a occlusion
##   grass:        r blade random, g dry tip, b seed head / cattail
##   plants:       r part (0 green, .5 centre, 1 petal), g random, b shape id / 7, a bend weight

const TILE_OAK := 0
const TILE_RUSSET := 1
const TILE_AMBER := 2
const TILE_CRIMSON := 3
const TILE_PINE := 4
const TILE_GREEN := 5
const TILE_LITTER := 6
const TILE_TWIGS := 7

## Surface accumulator.
class Surf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var tg := PackedFloat32Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()

	func vert(p: Vector3, nrm: Vector3, tan: Vector3, t: Vector2, col: Color) -> int:
		v.append(p)
		n.append(nrm)
		tg.append(tan.x)
		tg.append(tan.y)
		tg.append(tan.z)
		tg.append(1.0)
		uv.append(t)
		c.append(col)
		return v.size() - 1

	## Godot treats clockwise (seen from the front) as front-facing.
	func tri(a: int, b: int, d: int) -> void:
		idx.append(a)
		idx.append(b)
		idx.append(d)

	func scale_all(s: float) -> void:
		for i in v.size():
			v[i] *= s

	func commit(mesh: ArrayMesh, mat: Material) -> void:
		if v.is_empty():
			# Keep the surface layout stable (bark = 0, leaves = 1) with a degenerate triangle.
			for k in 3:
				vert(Vector3.ZERO, Vector3.UP, Vector3.RIGHT, Vector2.ZERO, Color(0, 0, 0, 1))
			tri(0, 1, 2)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_TANGENT] = tg
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


## Tree skeleton: tubes and leaf cards in metres.
class Skeleton:
	var tubes: Array = []    # {pts: PackedVector3Array, rad: PackedFloat32Array, w: PackedFloat32Array, level, phase}
	var cards: Array = []    # {p, n, up, size, tile, w, phase, aspect}
	var height := 1.0
	var tex_size := Vector2(1.0, 2.0)   # bark texture footprint (m)
	var flare := 0.5
	var crown_center := Vector3(0, 5, 0)
	var crown_radius := 4.0
	var conifer := false


static func atlas_uv(tile: int, u: float, v: float) -> Vector2:
	return Vector2((float(tile % 4) + clampf(u, 0.002, 0.998)) / 4.0, (float(tile / 4) + clampf(v, 0.002, 0.998)) / 2.0)


static func _perp(d: Vector3) -> Vector3:
	var a := Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT
	return d.cross(a).normalized()


static func _rand_dir_cone(rng: RandomNumberGenerator, axis: Vector3, angle: float, azimuth: float) -> Vector3:
	var p := _perp(axis)
	var q := axis.cross(p).normalized()
	var radial := (p * cos(azimuth) + q * sin(azimuth)).normalized()
	return (axis * cos(angle) + radial * sin(angle)).normalized()


# --------------------------------------------------------------------------- skeleton growth

## Grows one branch as a polyline; returns the tube dictionary (already appended).
static func _grow(sk: Skeleton, rng: RandomNumberGenerator, start: Vector3, dir: Vector3, length: float,
		r0: float, r1: float, level: int, w0: float, w1: float, segs: int, wobble: float,
		up_pull: float, droop: float) -> Dictionary:
	var pts := PackedVector3Array()
	var rad := PackedFloat32Array()
	var ws := PackedFloat32Array()
	var p := start
	var d := dir.normalized()
	pts.append(p)
	rad.append(r0)
	ws.append(w0)
	var step := length / segs
	for i in segs:
		var t := float(i + 1) / segs
		var jitter := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * wobble
		d = (d + jitter + Vector3.UP * up_pull - Vector3.UP * droop * t).normalized()
		p += d * step
		pts.append(p)
		rad.append(lerpf(r0, r1, pow(t, 0.8)))
		ws.append(lerpf(w0, w1, t))
	var tube := {"pts": pts, "rad": rad, "w": ws, "level": level, "phase": rng.randf()}
	sk.tubes.append(tube)
	return tube


## Point, direction and radius at fraction t along a tube.
static func _along(tube: Dictionary, t: float) -> Array:
	var pts: PackedVector3Array = tube.pts
	var rad: PackedFloat32Array = tube.rad
	var ws: PackedFloat32Array = tube.w
	var f := clampf(t, 0.0, 1.0) * (pts.size() - 1)
	var i := mini(int(f), pts.size() - 2)
	var k := f - i
	return [pts[i].lerp(pts[i + 1], k), (pts[i + 1] - pts[i]).normalized(), lerpf(rad[i], rad[i + 1], k),
			lerpf(ws[i], ws[i + 1], k)]


static func _tube_length(tube: Dictionary) -> float:
	var pts: PackedVector3Array = tube.pts
	var l := 0.0
	for i in pts.size() - 1:
		l += pts[i].distance_to(pts[i + 1])
	return l


static func _add_card(sk: Skeleton, rng: RandomNumberGenerator, p: Vector3, outward: Vector3, size: float,
		tile: int, w: float, phase: float, up_hint := Vector3.ZERO) -> void:
	# Leaf clusters face mostly outward/up with plenty of randomness.
	var n := (outward * 0.8 + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1.2), rng.randf_range(-1, 1)) * 0.8).normalized()
	var up := up_hint
	if up == Vector3.ZERO:
		up = (outward + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.2, 0.8), rng.randf_range(-0.6, 0.6))).normalized()
	up = (up - n * up.dot(n))
	if up.length() < 0.01:
		up = _perp(n)
	up = up.normalized()
	sk.cards.append({"p": p, "n": n, "up": up, "size": size, "tile": tile, "w": w, "phase": phase, "aspect": 1.0})


static func _pick_tile(rng: RandomNumberGenerator, weights: Array) -> int:
	# weights: [[tile, weight], ...]
	var total := 0.0
	for e in weights:
		total += e[1]
	var r := rng.randf() * total
	for e in weights:
		r -= e[1]
		if r <= 0.0:
			return e[0]
	return weights[0][0]


## Broad deciduous tree (oak / crimson). `upright` 0 spreading .. 1 tall and rounded.
static func skeleton_broadleaf(rng: RandomNumberGenerator, tiles: Array, upright: float) -> Skeleton:
	var sk := Skeleton.new()
	sk.tex_size = Vector2(1.1, 2.2)
	sk.flare = 0.65
	var trunk_len := rng.randf_range(3.6, 4.8) * (1.0 + upright * 0.15)
	var r0 := rng.randf_range(0.3, 0.38)
	var lean := Vector3(rng.randf_range(-0.12, 0.12), 1.0, rng.randf_range(-0.12, 0.12)).normalized()
	var trunk := _grow(sk, rng, Vector3.ZERO, lean, trunk_len, r0, r0 * 0.62, 0, 0.0, 0.05, 9, 0.05, 0.05, 0.0)
	var limbs: Array = []
	var top: Array = _along(trunk, 1.0)
	var n_major := rng.randi_range(3, 4)
	var az0 := rng.randf() * TAU
	for i in n_major:
		var az := az0 + TAU * i / n_major + rng.randf_range(-0.4, 0.4)
		var ang := deg_to_rad(rng.randf_range(22, 48) * (1.0 - upright * 0.35))
		var d := _rand_dir_cone(rng, Vector3.UP, ang, az)
		var len := rng.randf_range(3.4, 4.6) * (1.0 + upright * 0.1)
		var start: Vector3 = top[0] - top[1] * 0.25
		limbs.append(_grow(sk, rng, start, d, len, top[2] * 0.72, 0.06, 1, 0.05, 0.35, 7, 0.12, 0.06, 0.08))
	# Lower side limbs from the upper trunk.
	var n_side := rng.randi_range(2, 3)
	for i in n_side:
		var t := rng.randf_range(0.55, 0.88)
		var at: Array = _along(trunk, t)
		var az := az0 + PI / n_major + TAU * i / n_side + rng.randf_range(-0.5, 0.5)
		var ang := deg_to_rad(rng.randf_range(52, 72) * (1.0 - upright * 0.25))
		var d := _rand_dir_cone(rng, Vector3.UP, ang, az)
		limbs.append(_grow(sk, rng, at[0], d, rng.randf_range(2.6, 3.8), at[2] * 0.55, 0.05, 1, 0.03, 0.4, 6, 0.12, 0.08, 0.12))
	var leaf_pts := PackedVector3Array()
	for limb: Dictionary in limbs:
		var ll := _tube_length(limb)
		var n_kids := rng.randi_range(4, 6)
		for k in n_kids:
			var t := lerpf(0.28, 0.95, (k + rng.randf_range(0.0, 0.8)) / n_kids)
			var at: Array = _along(limb, t)
			var az := k * 2.4 + rng.randf() * 0.6
			var d := _rand_dir_cone(rng, at[1], deg_to_rad(rng.randf_range(35, 62)), az)
			d = (d + Vector3.UP * 0.25 * (1.0 + upright)).normalized()
			var len := ll * rng.randf_range(0.42, 0.62) * (1.0 - t * 0.3)
			var br := _grow(sk, rng, at[0], d, len, maxf(at[2] * 0.6, 0.025), 0.015, 2, at[3], 0.75, 4, 0.18, 0.05, 0.15)
			# Twigs carrying the leaf clusters.
			var bl := _tube_length(br)
			var n_tw := rng.randi_range(2, 4)
			for j in n_tw:
				var tt := lerpf(0.35, 1.0, (j + rng.randf()) / n_tw)
				var bt: Array = _along(br, tt)
				var td := _rand_dir_cone(rng, bt[1], deg_to_rad(rng.randf_range(30, 60)), j * 2.4 + rng.randf())
				var tw := _grow(sk, rng, bt[0], td, bl * rng.randf_range(0.35, 0.55), maxf(bt[2] * 0.6, 0.012), 0.006, 3, bt[3], 1.0, 2, 0.2, 0.08, 0.1)
				var twl := _tube_length(tw)
				var n_c := maxi(1, int(twl / 0.55))
				for c in n_c:
					var ct: Array = _along(tw, lerpf(0.45, 1.0, float(c) / maxf(n_c - 1, 1)))
					leaf_pts.append(ct[0])
					_add_card(sk, rng, ct[0] + ct[1] * 0.2, ct[1], rng.randf_range(1.1, 1.55), _pick_tile(rng, tiles), ct[3], tw.phase)
			# Leaves on the branch itself too.
			var bend: Array = _along(br, 1.0)
			_add_card(sk, rng, bend[0], bend[1], rng.randf_range(1.2, 1.6), _pick_tile(rng, tiles), bend[3], br.phase)
			leaf_pts.append(bend[0])
	_finish_crown(sk, leaf_pts)
	return sk


static func skeleton_pine(rng: RandomNumberGenerator) -> Skeleton:
	var sk := Skeleton.new()
	sk.tex_size = Vector2(0.9, 0.9)
	sk.flare = 0.4
	sk.conifer = true
	var h := rng.randf_range(11.0, 13.0)
	var r0 := rng.randf_range(0.24, 0.3)
	var trunk := _grow(sk, rng, Vector3.ZERO, Vector3(rng.randf_range(-0.03, 0.03), 1, rng.randf_range(-0.03, 0.03)),
			h, r0, 0.015, 0, 0.0, 0.25, 14, 0.015, 0.02, 0.0)
	var h0 := rng.randf_range(1.6, 2.6)
	var y := h0
	var az := rng.randf() * TAU
	var leaf_pts := PackedVector3Array()
	while y < h - 0.5:
		var t := y / h
		var at: Array = _along(trunk, t)
		var rel := (y - h0) / (h - h0)
		var blen := pow(1.0 - rel, 0.9) * rng.randf_range(2.9, 3.4) + 0.35
		var n_b := rng.randi_range(4, 6)
		for i in n_b:
			var a := az + TAU * i / n_b + rng.randf_range(-0.3, 0.3)
			var droop := lerpf(0.25, -0.05, rel)
			var d := Vector3(cos(a), -droop + rng.randf_range(-0.08, 0.08), sin(a)).normalized()
			var br := _grow(sk, rng, at[0], d, blen, maxf(at[2] * 0.35, 0.02), 0.008, 1, at[3], 0.9, 4, 0.06, 0.07, 0.0)
			var bl := _tube_length(br)
			var n_c := maxi(1, int(bl / 0.5))
			for c in n_c:
				var ct: Array = _along(br, lerpf(0.12, 0.92, float(c) / maxf(n_c - 1, 1)))
				var side := ct[1].cross(Vector3.UP).normalized() as Vector3
				# Needle sprays lie roughly flat along the branch, tilted a little either way.
				var tilt := rng.randf_range(-0.45, 0.45)
				var nrm := (Vector3.UP * cos(tilt) + side * sin(tilt)).normalized()
				var size := rng.randf_range(0.85, 1.15) * clampf(0.55 + bl * 0.22, 0.6, 1.2)
				sk.cards.append({"p": ct[0] + ct[1] * size * 0.15, "n": nrm, "up": ct[1], "size": size,
						"tile": TILE_PINE, "w": ct[3], "phase": br.phase, "aspect": 1.0})
				if c % 2 == 1:
					var nrm2 := (Vector3.UP * cos(tilt + 1.3) + side * sin(tilt + 1.3)).normalized()
					sk.cards.append({"p": ct[0], "n": nrm2, "up": ct[1], "size": size * 0.85,
							"tile": TILE_PINE, "w": ct[3], "phase": br.phase, "aspect": 1.0})
				leaf_pts.append(ct[0])
		az += 2.4
		y += rng.randf_range(0.42, 0.6)
	# Leader: crossed upright sprays at the very top.
	var tip: Array = _along(trunk, 0.97)
	for k in 3:
		var nrm := Vector3(cos(k * 1.05), 0, sin(k * 1.05))
		sk.cards.append({"p": tip[0] - Vector3.UP * 0.35, "n": nrm, "up": Vector3.UP, "size": 0.9,
				"tile": TILE_PINE, "w": 0.4, "phase": 0.3, "aspect": 1.0})
	_finish_crown(sk, leaf_pts)
	return sk


static func skeleton_dead(rng: RandomNumberGenerator) -> Skeleton:
	var sk := Skeleton.new()
	sk.tex_size = Vector2(0.9, 1.0)
	sk.flare = 0.8
	var trunk_len := rng.randf_range(4.0, 6.0)
	var r0 := rng.randf_range(0.26, 0.34)
	var broken := rng.randf() < 0.4
	var trunk := _grow(sk, rng, Vector3.ZERO, Vector3(rng.randf_range(-0.2, 0.2), 1, rng.randf_range(-0.2, 0.2)),
			trunk_len, r0, r0 * (0.55 if broken else 0.2), 0, 0.0, 0.05, 9, 0.16, 0.04, 0.0)
	var n_l := rng.randi_range(3, 5)
	var tips := PackedVector3Array()
	for i in n_l:
		var t := rng.randf_range(0.45, 0.95)
		var at: Array = _along(trunk, t)
		var d := _rand_dir_cone(rng, Vector3.UP, deg_to_rad(rng.randf_range(30, 75)), i * 2.4 + rng.randf())
		var len := rng.randf_range(1.8, 3.6) * (0.5 if rng.randf() < 0.2 else 1.0)
		var limb := _grow(sk, rng, at[0], d, len, at[2] * 0.6, 0.03, 1, 0.03, 0.4, 6, 0.3, 0.05, 0.05)
		var ll := _tube_length(limb)
		for k in rng.randi_range(2, 4):
			var bt: Array = _along(limb, rng.randf_range(0.35, 1.0))
			var bd := _rand_dir_cone(rng, bt[1], deg_to_rad(rng.randf_range(30, 70)), k * 2.4 + rng.randf())
			var br := _grow(sk, rng, bt[0], bd, ll * rng.randf_range(0.35, 0.6), maxf(bt[2] * 0.6, 0.015), 0.008, 2, bt[3], 0.8, 4, 0.35, 0.04, 0.05)
			var bl := _tube_length(br)
			for j in rng.randi_range(1, 3):
				var ct: Array = _along(br, rng.randf_range(0.4, 1.0))
				var cd := _rand_dir_cone(rng, ct[1], deg_to_rad(rng.randf_range(30, 70)), j * 2.4 + rng.randf())
				var tw := _grow(sk, rng, ct[0], cd, bl * rng.randf_range(0.3, 0.5), maxf(ct[2] * 0.6, 0.008), 0.004, 3, ct[3], 1.0, 2, 0.4, 0.03, 0.0)
				var e: Array = _along(tw, 1.0)
				tips.append(e[0])
				_add_card(sk, rng, e[0], e[1], rng.randf_range(0.7, 1.1), TILE_TWIGS, e[3], tw.phase, e[1])
	if not broken:
		var top: Array = _along(trunk, 1.0)
		_add_card(sk, rng, top[0], top[1], 1.0, TILE_TWIGS, 0.3, 0.5, top[1])
	_finish_crown(sk, tips)
	return sk


## A bush: several stems from the ground with leaf clusters (about 1 m tall).
static func skeleton_bush(rng: RandomNumberGenerator, tiles: Array) -> Skeleton:
	var sk := Skeleton.new()
	sk.tex_size = Vector2(0.4, 0.6)
	sk.flare = 0.0
	var pts := PackedVector3Array()
	var n := rng.randi_range(6, 8)
	for i in n:
		var d := _rand_dir_cone(rng, Vector3.UP, deg_to_rad(rng.randf_range(10, 50)), TAU * i / n + rng.randf())
		var st := _grow(sk, rng, Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08)), d,
				rng.randf_range(0.75, 1.15), 0.022, 0.006, 2, 0.1, 0.8, 3, 0.2, 0.08, 0.1)
		for k in 4:
			var ct: Array = _along(st, 0.35 + 0.2 * k)
			var tw := _grow(sk, rng, ct[0], _rand_dir_cone(rng, ct[1], deg_to_rad(rng.randf_range(30, 70)), k * 2.4 + rng.randf()),
					rng.randf_range(0.2, 0.35), 0.008, 0.003, 3, ct[3], 1.0, 2, 0.2, 0.05, 0.0)
			var e: Array = _along(tw, 1.0)
			pts.append(e[0])
			var out := Vector3(e[0].x, 0.0, e[0].z).normalized() + Vector3.UP * 0.6
			_add_card(sk, rng, e[0], out.normalized(), rng.randf_range(0.36, 0.5), _pick_tile(rng, tiles), e[3], st.phase)
	_finish_crown(sk, pts)
	return sk


static func _finish_crown(sk: Skeleton, pts: PackedVector3Array) -> void:
	var top := 0.0
	for tube: Dictionary in sk.tubes:
		for p: Vector3 in tube.pts:
			top = maxf(top, p.y)
	for c: Dictionary in sk.cards:
		top = maxf(top, c.p.y + c.size * 0.4)
	sk.height = top
	if pts.is_empty():
		sk.crown_center = Vector3(0, top * 0.6, 0)
		sk.crown_radius = top * 0.4
		return
	var acc := Vector3.ZERO
	for p in pts:
		acc += p
	sk.crown_center = acc / pts.size()
	var r := 0.0
	for p in pts:
		r += p.distance_to(sk.crown_center)
	sk.crown_radius = maxf(r / pts.size() * 1.3, 0.3)


# --------------------------------------------------------------------------- meshing

## lod: 0 full, 1 medium, 2 far. Returns a 2-surface mesh (bark, leaves) normalised to unit height
## (or left in metres when normalise is false).
static func mesh_tree(sk: Skeleton, lod: int, bark_mat: Material, leaf_mat: Material, normalise := true) -> ArrayMesh:
	var bark := Surf.new()
	var leaves := Surf.new()
	var max_level: int = [3, 2, 1][lod]
	if sk.conifer:
		max_level = [1, 1, 0][lod]
	for tube: Dictionary in sk.tubes:
		var level: int = tube.level
		if level > max_level:
			continue
		var sides: int = [[14, 8, 5, 3], [7, 4, 3, 3], [5, 3, 3, 3]][lod][level]
		var stride := 1 if lod == 0 else 2
		if level == 0 and lod == 0:
			stride = 1
		_tube(bark, sk, tube, sides, stride)
	var cards: Array = sk.cards
	var keep_every: int = [1, 3, 0][lod]
	var grow: float = [1.0, 1.6, 1.0][lod]
	if sk.conifer:
		keep_every = [1, 2, 0][lod]
		grow = [1.0, 1.35, 1.0][lod]
	if lod == 2:
		var want := 34 if sk.conifer else 22
		keep_every = maxi(1, int(round(float(cards.size()) / want)))
		grow = clampf(sqrt(float(keep_every)) * 0.95, 1.0, 3.2)
	for i in cards.size():
		if i % keep_every != 0:
			continue
		_card(leaves, sk, cards[i], grow)
	var mesh := ArrayMesh.new()
	if normalise:
		var s := 1.0 / sk.height
		bark.scale_all(s)
		leaves.scale_all(s)
	bark.commit(mesh, bark_mat)
	leaves.commit(mesh, leaf_mat)
	return mesh


static func _tube(s: Surf, sk: Skeleton, tube: Dictionary, sides: int, stride: int) -> void:
	var pts: PackedVector3Array = tube.pts
	var rad: PackedFloat32Array = tube.rad
	var ws: PackedFloat32Array = tube.w
	var level: int = tube.level
	var phase: float = tube.phase
	var rings: Array[int] = []
	for i in range(0, pts.size(), stride):
		rings.append(i)
	if rings[-1] != pts.size() - 1:
		rings.append(pts.size() - 1)
	var circumference := TAU * rad[0]
	var u_tiles := maxf(1.0, round(circumference / sk.tex_size.x))
	var base := s.v.size()
	# Parallel-transport frame.
	var d0 := (pts[1] - pts[0]).normalized()
	var nrm := _perp(d0)
	var dist := 0.0
	var prev := pts[0]
	var flare_n := 5.0
	for ri in rings.size():
		var i := rings[ri]
		var p := pts[i]
		dist += p.distance_to(prev)
		prev = p
		var d: Vector3
		if i == 0:
			d = d0
		elif i == pts.size() - 1:
			d = (pts[i] - pts[i - 1]).normalized()
		else:
			d = (pts[i + 1] - pts[i - 1]).normalized()
		nrm = (nrm - d * nrm.dot(d)).normalized()
		var bin := d.cross(nrm).normalized()
		var r := rad[i]
		var ao := 1.0
		if level == 0:
			ao = lerpf(0.55, 1.0, clampf(p.y / 1.4, 0.0, 1.0))
		for j in sides + 1:
			var a := TAU * j / sides
			var radial := nrm * cos(a) + bin * sin(a)
			var rr := r
			if level == 0 and sk.flare > 0.0:
				var lobes := 0.6 + 0.4 * absf(sin(a * flare_n * 0.5 + phase * 6.0))
				rr *= 1.0 + sk.flare * exp(-p.y / 0.45) * lobes * 1.4
				rr *= 1.0 + 0.04 * sin(a * 3.0 + p.y * 2.0 + phase * 9.0)
			var pos := p + radial * rr
			var tan := -nrm * sin(a) + bin * cos(a)
			var uv := Vector2(float(j) / sides * u_tiles, dist / sk.tex_size.y)
			s.vert(pos, radial, tan, uv, Color(ws[i], phase, 0.0, ao))
	for ri in rings.size() - 1:
		for j in sides:
			var a := base + ri * (sides + 1) + j
			var b := a + sides + 1
			s.tri(a, a + 1, b)
			s.tri(a + 1, b + 1, b)


static func _card(s: Surf, sk: Skeleton, card: Dictionary, grow: float) -> void:
	var p: Vector3 = card.p
	var n: Vector3 = card.n
	var up: Vector3 = card.up
	var size: float = card.size * grow
	var right := up.cross(n).normalized()
	var tile: int = card.tile
	var w: float = card.w
	var phase: float = card.phase
	# Shading normal: mostly the crown's outward direction (soft, volumetric light), some face normal.
	var outward: Vector3
	if sk.conifer:
		outward = Vector3(p.x, 0.0, p.z)
		outward = (outward.normalized() if outward.length() > 0.01 else Vector3.RIGHT) * 0.7 + Vector3.UP * 0.6
	else:
		outward = p - sk.crown_center
		outward = outward.normalized() if outward.length() > 0.01 else Vector3.UP
		outward = outward + Vector3.UP * 0.25
	var sh := (outward.normalized() * 0.7 + n * 0.3).normalized()
	var dc := (p - sk.crown_center).length() / maxf(sk.crown_radius, 0.1)
	var ao := clampf(0.55 + 0.45 * smoothstep(0.15, 1.0, dc), 0.55, 1.0)
	if sk.conifer:
		var radial := Vector2(p.x, p.z).length()
		ao = clampf(0.45 + radial * 0.25, 0.45, 1.0)
	# Base of the card at the twig, so the stem in the texture meets the branch.
	var base := p - up * size * 0.45
	var corners := [base - right * size * 0.5, base + right * size * 0.5,
			base + right * size * 0.5 + up * size, base - right * size * 0.5 + up * size]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	var i0 := s.v.size()
	for k in 4:
		var wk := w + (0.12 if k >= 2 else 0.0)
		var uv: Vector2 = uvs[k]
		s.vert(corners[k], sh, right, atlas_uv(tile, uv.x, uv.y), Color(minf(wk, 1.0), phase, 1.0, ao))
	s.tri(i0, i0 + 2, i0 + 1)
	s.tri(i0, i0 + 3, i0 + 2)


# --------------------------------------------------------------------------- props

## Lying log (metres, no normalisation): along +X, centred, resting on y = 0.
static func mesh_log(rng: RandomNumberGenerator, bark_mat: Material) -> ArrayMesh:
	var sk := Skeleton.new()
	sk.tex_size = Vector2(1.1, 2.2)
	sk.flare = 0.0
	var length := rng.randf_range(3.2, 4.8)
	var r := rng.randf_range(0.24, 0.34)
	var t := _grow(sk, rng, Vector3(-length * 0.5, r * 0.8, 0), Vector3.RIGHT, length, r, r * 0.8, 1, 0.0, 0.0, 8, 0.03, 0.0, 0.0)
	for k in rng.randi_range(2, 3):
		var at: Array = _along(t, rng.randf_range(0.25, 0.8))
		var d := _rand_dir_cone(rng, Vector3.RIGHT, deg_to_rad(rng.randf_range(40, 70)), rng.randf() * TAU)
		if d.y < -0.2:
			d.y = -d.y
		_grow(sk, rng, at[0], d, rng.randf_range(0.35, 0.8), at[2] * 0.35, at[2] * 0.25, 2, 0.0, 0.0, 2, 0.05, 0.0, 0.0)
	var s := Surf.new()
	for tube: Dictionary in sk.tubes:
		_tube(s, sk, tube, 10 if tube.level == 1 else 5, 1)
		# Cap the broken/cut ends.
		var pts: PackedVector3Array = tube.pts
		var rad: PackedFloat32Array = tube.rad
		for e in [0, pts.size() - 1]:
			var d := (pts[1] - pts[0]).normalized() if e == 0 else (pts[e] - pts[e - 1]).normalized()
			var outn := -d if e == 0 else d
			var c := s.vert(pts[e] + outn * rad[e] * 0.15, outn, _perp(outn), Vector2(0.5, 0.5), Color(0, 0, 0, 0.6))
			var nn := _perp(outn)
			var bb := outn.cross(nn)
			var first := s.v.size()
			for j in 9:
				var a := TAU * j / 8.0
				var q := pts[e] + (nn * cos(a) + bb * sin(a)) * rad[e] * 0.97
				s.vert(q, outn, nn, Vector2(0.5 + cos(a) * 0.3, 0.5 + sin(a) * 0.3), Color(0, 0, 0, 0.7))
			for j in 8:
				if e == 0:
					s.tri(c, first + j, first + j + 1)
				else:
					s.tri(c, first + j + 1, first + j)
	var mesh := ArrayMesh.new()
	s.commit(mesh, bark_mat)
	return mesh


## Displaced icosphere rock, unit size (radius ~0.5), flattened, base slightly below y = 0.
static func mesh_rock(seed_value: int, subdiv: int, flatten: float) -> Dictionary:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.6
	noise.fractal_octaves = 3
	var verts := PackedVector3Array()
	var faces: Array = []
	var t := (1.0 + sqrt(5.0)) / 2.0
	for p in [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
			Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]:
		verts.append((p as Vector3).normalized())
	faces = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6],
			[7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for k in subdiv:
		var cache := {}
		var nf: Array = []
		for f: Array in faces:
			var m := []
			for e in 3:
				var a: int = f[e]
				var b: int = f[(e + 1) % 3]
				var key := mini(a, b) * 100000 + maxi(a, b)
				if not cache.has(key):
					verts.append((verts[a] + verts[b]).normalized())
					cache[key] = verts.size() - 1
				m.append(cache[key])
			nf.append([f[0], m[0], m[2]])
			nf.append([f[1], m[1], m[0]])
			nf.append([f[2], m[2], m[1]])
			nf.append([m[0], m[1], m[2]])
		faces = nf
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var squash := Vector3(rng.randf_range(0.85, 1.15), flatten, rng.randf_range(0.8, 1.1))
	var pos := PackedVector3Array()
	pos.resize(verts.size())
	for i in verts.size():
		var p := verts[i]
		var dsp := 1.0 + noise.get_noise_3dv(p * 1.3) * 0.35 + noise.get_noise_3dv(p * 4.0) * 0.08
		# Faceted, fractured look: pull some vertices onto planes.
		var q := p * dsp * 0.5 * squash
		q.y = maxf(q.y, -0.12)
		pos[i] = q
	# Flat-ish shading with smoothed normals.
	var nrm := PackedVector3Array()
	nrm.resize(pos.size())
	var idx := PackedInt32Array()
	for f: Array in faces:
		var a := pos[f[0]]
		var b := pos[f[1]]
		var c := pos[f[2]]
		var fn := (b - a).cross(c - a)
		for k in 3:
			nrm[f[k]] += fn
		idx.append(f[0])
		idx.append(f[2])
		idx.append(f[1])
	for i in nrm.size():
		nrm[i] = nrm[i].normalized()
	return {"v": pos, "n": nrm, "i": idx}


static func mesh_rocks(parts: Array, mat: Material) -> ArrayMesh:
	# parts: [[rock_dict, Transform3D], ...] merged into one surface.
	var s := Surf.new()
	for part: Array in parts:
		var r: Dictionary = part[0]
		var xf: Transform3D = part[1]
		var base := s.v.size()
		var pv: PackedVector3Array = r.v
		var pn: PackedVector3Array = r.n
		for i in pv.size():
			s.vert(xf * pv[i], (xf.basis * pn[i]).normalized(), Vector3.RIGHT, Vector2.ZERO, Color(1, 1, 1, 1))
		var pi: PackedInt32Array = r.i
		for i in range(0, pi.size(), 3):
			s.tri(base + pi[i], base + pi[i + 1], base + pi[i + 2])
	var mesh := ArrayMesh.new()
	s.commit(mesh, mat)
	return mesh


# --------------------------------------------------------------------------- grass

## One blade: root at `root`, height h, width w, leaning along `lean` (xz, radians-ish), curling.
## Grass LOD while meshing clumps: 0 full blades, 1 far (40 % of the blades, single triangles, wider).
static var _blade_lod := 0
static var _blade_n := 0


static func _blade(s: Surf, rng: RandomNumberGenerator, root: Vector3, h: float, w: float, lean: Vector2,
		col: Color, segs := 3, seed_frac := 0.0, seed_w := 0.0) -> void:
	_blade_n += 1
	if _blade_lod == 1:
		if _blade_n % 5 == 0 or _blade_n % 5 == 2 or _blade_n % 5 == 4:
			return
		segs = 1 if seed_frac <= 0.0 else 2
		w *= 1.9
		seed_w *= 1.5
	var face_a := rng.randf() * TAU
	var side := Vector3(cos(face_a), 0, sin(face_a))
	var fwd := Vector3(-side.z, 0, side.x)
	var lean3 := Vector3(lean.x, 0, lean.y)
	var base := s.v.size()
	var prev_c := root
	for i in segs + 1:
		var t := float(i) / segs
		# Curved: lean grows quadratically toward the tip.
		var c := root + Vector3.UP * h * t * (1.0 - 0.25 * lean.length_squared() * t * t) + lean3 * h * t * t
		var dir := (c - prev_c).normalized() if i > 0 else Vector3.UP
		prev_c = c
		var hw := w * 0.5 * (1.0 - pow(t, 1.6) * 0.92)
		var cc := col
		if seed_frac > 0.0 and t >= 1.0 - seed_frac:
			hw = seed_w * 0.5 * sin(PI * clampf((t - (1.0 - seed_frac)) / seed_frac * 0.9 + 0.1, 0.0, 1.0))
			cc.b = 1.0
		var face_n := side.cross(dir).normalized()
		if i == segs and seed_frac <= 0.0:
			s.vert(c, face_n, side, Vector2(0.5, t), cc)
		else:
			# Slight V-fold: edge normals tilt outward.
			s.vert(c - side * hw, (face_n - side * 0.45).normalized(), side, Vector2(0.0, t), cc)
			s.vert(c + side * hw, (face_n + side * 0.45).normalized(), side, Vector2(1.0, t), cc)
	var k := base
	for i in segs:
		if i == segs - 1 and seed_frac <= 0.0:
			s.tri(k, k + 2, k + 1)
		else:
			s.tri(k, k + 2, k + 1)
			s.tri(k + 1, k + 2, k + 3)
		k += 2


## Grass clump at reference height 1 (instance scale y sets the real height).
static func mesh_grass(kind: String, mat: Material, lod := 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	_blade_lod = lod
	_blade_n = 0
	var s := Surf.new()
	match kind:
		"short":
			for i in 20:
				var r := sqrt(rng.randf()) * 0.22
				var a := rng.randf() * TAU
				var root := Vector3(cos(a) * r, 0, sin(a) * r)
				var lean := Vector2(cos(a), sin(a)) * rng.randf_range(0.1, 0.6) + Vector2(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.15, 0.15))
				_blade(s, rng, root, rng.randf_range(0.45, 1.0), rng.randf_range(0.04, 0.06), lean,
						Color(rng.randf(), pow(rng.randf(), 3.0), 0.0, 1.0))
		"tall":
			for i in 16:
				var r := sqrt(rng.randf()) * 0.18
				var a := rng.randf() * TAU
				var lean := Vector2(cos(a), sin(a)) * rng.randf_range(0.15, 0.5)
				_blade(s, rng, Vector3(cos(a) * r, 0, sin(a) * r), rng.randf_range(0.55, 0.95), rng.randf_range(0.03, 0.045), lean,
						Color(rng.randf(), 0.4 + rng.randf() * 0.6, 0.0, 1.0), 4)
			for i in 3:
				var a := rng.randf() * TAU
				var lean := Vector2(cos(a), sin(a)) * rng.randf_range(0.05, 0.3)
				_blade(s, rng, Vector3(cos(a) * 0.05, 0, sin(a) * 0.05), rng.randf_range(0.95, 1.15), 0.012, lean,
						Color(rng.randf(), 0.8, 0.0, 1.0), 4, 0.24, 0.045)
		"reeds":
			for i in 9:
				var r := sqrt(rng.randf()) * 0.12
				var a := rng.randf() * TAU
				var lean := Vector2(cos(a), sin(a)) * rng.randf_range(0.05, 0.35)
				_blade(s, rng, Vector3(cos(a) * r, 0, sin(a) * r), rng.randf_range(0.6, 1.0), rng.randf_range(0.035, 0.05), lean,
						Color(rng.randf(), 0.3 + rng.randf() * 0.4, 0.0, 1.0), 4)
			for i in 2:
				var a := rng.randf() * TAU
				_blade(s, rng, Vector3(cos(a) * 0.04, 0, sin(a) * 0.04), rng.randf_range(0.95, 1.1), 0.014,
						Vector2(cos(a), sin(a)) * 0.08, Color(rng.randf(), 0.2, 0.0, 1.0), 6, 0.17, 0.1)
		"stubble":
			for i in 8:
				var r := sqrt(rng.randf()) * 0.18
				var a := rng.randf() * TAU
				var lean := Vector2(cos(a), sin(a)) * rng.randf_range(0.0, 0.5)
				_blade(s, rng, Vector3(cos(a) * r, 0, sin(a) * r), rng.randf_range(0.35, 1.0), rng.randf_range(0.025, 0.04), lean,
						Color(rng.randf(), 0.0, 0.0, 1.0), 2)
		"tuft":
			for i in 9:
				var r := sqrt(rng.randf()) * 0.1
				var a := rng.randf() * TAU
				var lean := Vector2(cos(a), sin(a)) * rng.randf_range(0.3, 0.8)
				_blade(s, rng, Vector3(cos(a) * r, 0, sin(a) * r), rng.randf_range(0.5, 1.0), rng.randf_range(0.025, 0.04), lean,
						Color(rng.randf(), 0.6 + rng.randf() * 0.4, 0.0, 1.0))
	_blade_lod = 0
	var mesh := ArrayMesh.new()
	s.commit(mesh, mat)
	return mesh


# --------------------------------------------------------------------------- plants (flowers, ferns)

## A UV quad for the plant shader. centre at `p`, axes `ax` (width, u) and `up` (height, v), v=0 at p - up/2.
static func _pquad(s: Surf, p: Vector3, ax: Vector3, up: Vector3, part: float, rnd: float, shape: int, t0: float, t1: float) -> void:
	var n := ax.cross(up).normalized()
	if n.y < 0.0:
		n = -n
	var b := s.v.size()
	var sh := shape / 7.0
	s.vert(p - ax * 0.5 - up * 0.5, n, ax.normalized(), Vector2(0, 0), Color(part, rnd, sh, t0))
	s.vert(p + ax * 0.5 - up * 0.5, n, ax.normalized(), Vector2(1, 0), Color(part, rnd, sh, t0))
	s.vert(p + ax * 0.5 + up * 0.5, n, ax.normalized(), Vector2(1, 1), Color(part, rnd, sh, t1))
	s.vert(p - ax * 0.5 + up * 0.5, n, ax.normalized(), Vector2(0, 1), Color(part, rnd, sh, t1))
	s.tri(b, b + 2, b + 1)
	s.tri(b, b + 3, b + 2)


static func _stem(s: Surf, a: Vector3, b: Vector3, w: float, rnd: float, t0: float, t1: float) -> void:
	var d := b - a
	var side := d.cross(Vector3(0.3, 0.1, 1.0)).normalized() * w
	_pquad(s, (a + b) * 0.5, side, d, 0.0, rnd, 0, t0, t1)
	var side2 := d.cross(side).normalized() * w
	_pquad(s, (a + b) * 0.5, side2, d, 0.0, rnd, 0, t0, t1)


## A radial flower head at `c` facing `n`: `count` petals of `plen` x `pw`, cupped by `cup` (0 flat .. 1 closed).
static func _flower_head(s: Surf, rng: RandomNumberGenerator, c: Vector3, n: Vector3, count: int, plen: float, pw: float,
		cup: float, shape: int, centre: float, centre_dark: float, t: float) -> void:
	var p := _perp(n)
	var q := n.cross(p)
	var a0 := rng.randf() * TAU
	for i in count:
		var a := a0 + TAU * i / count
		var radial := p * cos(a) + q * sin(a)
		var dir := (radial * cos(cup * 1.2) + n * sin(cup * 1.2)).normalized()
		var side := radial.cross(n).normalized() * pw
		_pquad(s, c + dir * plen * 0.5, side, dir * plen, 1.0, rng.randf(), shape, t, t)
	if centre > 0.0:
		var side := p * centre
		_pquad(s, c + n * 0.006, side, q * centre, 0.5, centre_dark, 2, t, t)


static func mesh_plant(kind: String, mat: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) + 17
	var s := Surf.new()
	match kind:
		"daisy":   # meadow daisies / cornflowers: a few stems with radial heads
			for k in 3:
				var base := Vector3(rng.randf_range(-0.07, 0.07), 0, rng.randf_range(-0.07, 0.07))
				var h := rng.randf_range(0.22, 0.38)
				var top := base + Vector3(rng.randf_range(-0.04, 0.04), h, rng.randf_range(-0.04, 0.04))
				_stem(s, base, top, 0.006, rng.randf(), 0.0, 1.0)
				var nn := (Vector3.UP + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))).normalized()
				_flower_head(s, rng, top, nn, 12, 0.035, 0.012, 0.12, 1, 0.022, 0.0, 1.0)
			for k in 4:
				var a := rng.randf() * TAU
				var d := Vector3(cos(a), 0.6, sin(a)).normalized()
				_pquad(s, d * 0.05, Vector3(-sin(a), 0, cos(a)) * 0.03, d * 0.11, 0.0, rng.randf(), 4, 0.0, 0.3)
		"poppy":   # cupped four-petal flowers with dark centres
			for k in 2:
				var base := Vector3(rng.randf_range(-0.06, 0.06), 0, rng.randf_range(-0.06, 0.06))
				var h := rng.randf_range(0.35, 0.55)
				var top := base + Vector3(rng.randf_range(-0.05, 0.05), h, rng.randf_range(-0.05, 0.05))
				_stem(s, base, top, 0.005, rng.randf(), 0.0, 1.0)
				_flower_head(s, rng, top, Vector3.UP, 4, 0.05, 0.05, 0.45, 2, 0.018, 0.95, 1.0)
			for k in 4:
				var a := rng.randf() * TAU
				var d := Vector3(cos(a), 0.5, sin(a)).normalized()
				_pquad(s, d * 0.06, Vector3(-sin(a), 0, cos(a)) * 0.035, d * 0.12, 0.0, rng.randf(), 4, 0.0, 0.3)
		"buttercup":
			for k in 4:
				var base := Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08))
				var top := base + Vector3(rng.randf_range(-0.05, 0.05), rng.randf_range(0.18, 0.32), rng.randf_range(-0.05, 0.05))
				_stem(s, base, top, 0.004, rng.randf(), 0.0, 1.0)
				_flower_head(s, rng, top, Vector3.UP, 5, 0.022, 0.024, 0.5, 2, 0.01, 0.2, 1.0)
		"spike":   # lupins / foxgloves: tall racemes of small bells
			for k in 2:
				var base := Vector3(rng.randf_range(-0.05, 0.05), 0, rng.randf_range(-0.05, 0.05))
				var h := rng.randf_range(0.6, 0.85)
				var top := base + Vector3(rng.randf_range(-0.03, 0.03), h, rng.randf_range(-0.03, 0.03))
				_stem(s, base, top, 0.008, rng.randf(), 0.0, 1.0)
				var whorls := 9
				for wv in whorls:
					var t := lerpf(0.45, 0.97, float(wv) / (whorls - 1))
					var c := base.lerp(top, t)
					var size := lerpf(0.035, 0.018, float(wv) / whorls)
					for j in 4:
						var a := j * TAU / 4.0 + wv * 0.8
						var out := Vector3(cos(a), -0.35, sin(a)).normalized()
						var side := Vector3(-sin(a), 0, cos(a)) * size * 0.8
						_pquad(s, c + out * size * 0.55, side, out * size * 1.1, 1.0, float(wv) / whorls, 6, t, t)
			for k in 6:
				var a := rng.randf() * TAU
				var d := Vector3(cos(a), 0.35, sin(a)).normalized()
				_pquad(s, d * 0.08, Vector3(-sin(a), 0, cos(a)) * 0.06, d * 0.16, 0.0, rng.randf(), 1, 0.0, 0.25)
		"heather":
			for k in 9:
				var base := Vector3(rng.randf_range(-0.14, 0.14), 0, rng.randf_range(-0.14, 0.14))
				var top := base + Vector3(rng.randf_range(-0.06, 0.06), rng.randf_range(0.14, 0.26), rng.randf_range(-0.06, 0.06))
				_stem(s, base, top, 0.004, 0.2, 0.0, 1.0)
				var mid := base.lerp(top, 0.7)
				var a := rng.randf() * TAU
				_pquad(s, mid, Vector3(cos(a), 0, sin(a)) * 0.04, (top - base) * 0.55, 1.0, rng.randf(), 7, 0.6, 1.0)
				_pquad(s, mid, Vector3(-sin(a), 0, cos(a)) * 0.04, (top - base) * 0.55, 1.0, rng.randf(), 7, 0.6, 1.0)
				_pquad(s, base.lerp(top, 0.35), Vector3(cos(a + 1.0), 0, sin(a + 1.0)) * 0.05, (top - base) * 0.4, 0.0, 0.3, 3, 0.2, 0.5)
		"iris":    # marsh iris: sword leaves + drooping falls
			for k in 7:
				var a := rng.randf() * TAU
				var d := (Vector3.UP + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.1, 0.35)).normalized()
				var h := rng.randf_range(0.45, 0.7)
				_pquad(s, d * h * 0.5, Vector3(-sin(a), 0, cos(a)) * 0.035, d * h, 0.0, rng.randf(), 4, 0.0, 1.0)
			var top := Vector3(0.02, 0.62, 0.0)
			_stem(s, Vector3.ZERO, top, 0.006, 0.5, 0.0, 1.0)
			for j in 3:
				var a := j * TAU / 3.0
				var fall := Vector3(cos(a), -0.6, sin(a)).normalized()
				_pquad(s, top + fall * 0.035, Vector3(-sin(a), 0, cos(a)) * 0.035, fall * 0.07, 1.0, 0.8, 1, 1.0, 1.0)
				var std := Vector3(cos(a + 1.05) * 0.3, 1.0, sin(a + 1.05) * 0.3).normalized()
				_pquad(s, top + std * 0.03, Vector3(-sin(a + 1.05), 0, cos(a + 1.05)) * 0.025, std * 0.06, 1.0, 0.3, 1, 1.0, 1.0)
		"asphodel":   # pale star flowers on a tall raceme
			for k in 2:
				var base := Vector3(rng.randf_range(-0.05, 0.05), 0, rng.randf_range(-0.05, 0.05))
				var top := base + Vector3(rng.randf_range(-0.04, 0.04), rng.randf_range(0.65, 0.9), rng.randf_range(-0.04, 0.04))
				_stem(s, base, top, 0.006, 0.5, 0.0, 1.0)
				for j in 9:
					var t := lerpf(0.6, 1.0, float(j) / 8.0)
					var a := j * 2.4
					var c := base.lerp(top, t) + Vector3(cos(a), 0, sin(a)) * 0.03
					var nn := (Vector3(cos(a), 0.4, sin(a))).normalized()
					var side := _perp(nn) * 0.045
					_pquad(s, c, side, nn.cross(side).normalized() * 0.045, 1.0, rng.randf(), 5, t, t)
			for k in 7:
				var a := rng.randf() * TAU
				var d := (Vector3.UP * 0.8 + Vector3(cos(a), 0, sin(a))).normalized()
				_pquad(s, d * 0.15, Vector3(-sin(a), 0, cos(a)) * 0.025, d * 0.3, 0.0, rng.randf(), 4, 0.0, 0.6)
		"fern":
			var n := 8
			for k in n:
				var a := TAU * k / n + rng.randf_range(-0.25, 0.25)
				var out := Vector3(cos(a), 0, sin(a))
				var side := Vector3(-sin(a), 0, cos(a))
				var len := rng.randf_range(0.65, 1.0)
				var rise := rng.randf_range(0.9, 1.3)
				# Arching frond in 4 segments; one shape quad spanning them via v ranges.
				var segs := 4
				var prev := Vector3.ZERO
				for j in segs:
					var t0 := float(j) / segs
					var t1 := float(j + 1) / segs
					var p1 := out * len * t1 + Vector3.UP * len * (rise * t1 - 1.25 * t1 * t1) * 0.9
					if j == 0:
						prev = Vector3.ZERO
					var w := 0.32 * len
					var b := s.v.size()
					var nrm := Vector3.UP
					s.vert(prev - side * w * 0.5, nrm, side, Vector2(0, t0), Color(0, k / float(n), 3.0 / 7.0, t0))
					s.vert(prev + side * w * 0.5, nrm, side, Vector2(1, t0), Color(0, k / float(n), 3.0 / 7.0, t0))
					s.vert(p1 + side * w * 0.5, nrm, side, Vector2(1, t1), Color(0, k / float(n), 3.0 / 7.0, t1))
					s.vert(p1 - side * w * 0.5, nrm, side, Vector2(0, t1), Color(0, k / float(n), 3.0 / 7.0, t1))
					s.tri(b, b + 2, b + 1)
					s.tri(b, b + 3, b + 2)
					prev = p1
	var mesh := ArrayMesh.new()
	s.commit(mesh, mat)
	return mesh


## Fallen-leaf litter patch (lies on the ground, 1 m across), drawn with the leaf material.
static func mesh_litter(mat: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	var s := Surf.new()
	for k in 3:
		var a := rng.randf() * TAU
		var right := Vector3(cos(a), 0, sin(a))
		var fwd := Vector3(-sin(a), 0, cos(a))
		var c := Vector3(rng.randf_range(-0.2, 0.2), 0.015 + k * 0.006, rng.randf_range(-0.2, 0.2))
		var size := rng.randf_range(0.8, 1.1)
		var i0 := s.v.size()
		var corners := [c - right * size * 0.5 - fwd * size * 0.5, c + right * size * 0.5 - fwd * size * 0.5,
				c + right * size * 0.5 + fwd * size * 0.5, c - right * size * 0.5 + fwd * size * 0.5]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for j in 4:
			var uv: Vector2 = uvs[j]
			s.vert(corners[j], Vector3.UP, right, atlas_uv(TILE_LITTER, uv.x, uv.y), Color(0, 0, 0, 0.85))
		s.tri(i0, i0 + 1, i0 + 2)
		s.tri(i0, i0 + 2, i0 + 3)
	var mesh := ArrayMesh.new()
	s.commit(mesh, mat)
	return mesh
