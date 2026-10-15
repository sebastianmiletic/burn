extends SceneTree
## Paints the procedural leaf atlas used by every tree / bush leaf card.
##
##   godot --headless --path . -s res://world/flora/tools/bake_leaf_atlas.gd
##
## Writes world/flora/textures/leaf_atlas.png (RGBA, alpha-cut leaves) and
## leaf_atlas_n.png (OpenGL tangent-space normals). 2048x1024, 4x2 tiles of 512:
##   0 oak orange   1 oak russet   2 oak amber/gold   3 crimson maple
##   4 pine sprig   5 green-gold bush   6 fallen leaves (litter)   7 bare twigs

const W := 2048
const H := 1024
const T := 512

var col := PackedFloat32Array()     # rgb
var alpha := PackedFloat32Array()
var height := PackedFloat32Array()
var rng := RandomNumberGenerator.new()


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	col.resize(W * H * 3)
	alpha.resize(W * H)
	height.resize(W * H)
	rng.seed = 20261015
	_cluster(0, "oak", [Color(0.86, 0.42, 0.1), Color(0.93, 0.56, 0.15), Color(0.75, 0.3, 0.08), Color(0.62, 0.22, 0.07)])
	_cluster(1, "oak", [Color(0.6, 0.2, 0.07), Color(0.72, 0.3, 0.1), Color(0.5, 0.16, 0.08), Color(0.82, 0.4, 0.12)])
	_cluster(2, "oak", [Color(0.92, 0.66, 0.2), Color(0.85, 0.55, 0.13), Color(0.66, 0.6, 0.2), Color(0.95, 0.75, 0.3)])
	_cluster(3, "maple", [Color(0.62, 0.06, 0.05), Color(0.75, 0.1, 0.06), Color(0.5, 0.04, 0.06), Color(0.8, 0.2, 0.08)])
	_pine(4)
	_cluster(5, "ellipse", [Color(0.36, 0.42, 0.12), Color(0.48, 0.48, 0.14), Color(0.62, 0.52, 0.16), Color(0.3, 0.36, 0.1)])
	_litter(6)
	_twigs(7)
	_fill_transparent()
	_save()
	print("leaf atlas baked in %d ms" % (Time.get_ticks_msec() - t0))
	quit()


func _tile_origin(tile: int) -> Vector2i:
	return Vector2i((tile % 4) * T, (tile / 4) * T)


## Paints one leaf. p: stem point (atlas px), dir: unit vector stem->tip, length px, width px.
func _leaf(shape: String, p: Vector2, dir: Vector2, length: float, width: float, c: Color, shade: float, tile: int) -> void:
	var o := _tile_origin(tile)
	var side := Vector2(-dir.y, dir.x)
	var reach := maxf(length, width) + 2.0
	# Leaves that would be cut by the tile border are skipped: straight cut edges read as cards.
	var tip := p + dir * length
	for q: Vector2 in [tip, p + side * width * 0.7 + dir * length * 0.5, p - side * width * 0.7 + dir * length * 0.5]:
		if q.x < o.x + 4 or q.y < o.y + 4 or q.x > o.x + T - 5 or q.y > o.y + T - 5:
			return
	var x0 := maxi(int(p.x - reach), o.x + 1)
	var x1 := mini(int(p.x + reach), o.x + T - 2)
	var y0 := maxi(int(p.y - reach), o.y + 1)
	var y1 := mini(int(p.y + reach), o.y + T - 2)
	var edge_brown := Color(0.32, 0.17, 0.07)
	# A few irregular blotches (fungus / drying) in leaf space: (u, v, radius).
	var spots: Array[Vector3] = []
	if rng.randf() < 0.35:
		for k in rng.randi_range(1, 4):
			spots.append(Vector3(rng.randf_range(0.2, 0.9), rng.randf_range(-0.6, 0.6), rng.randf_range(0.04, 0.12)))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(x + 0.5, y + 0.5) - p
			var u := d.dot(dir) / length            # 0 stem .. 1 tip
			var v := d.dot(side) / width             # -1..1 across
			var inside := 0.0
			var w := 0.0
			match shape:
				"oak":
					if u < -0.12 or u > 1.0:
						continue
					if u < 0.0:
						# Petiole.
						w = 0.06
					else:
						var env := pow(sin(PI * clampf(u, 0.0, 1.0)), 0.7) * (0.75 + 0.25 * u)
						var lobes := 0.62 + 0.38 * absf(sin(u * PI * 4.6 + 0.3))
						w = env * lobes
				"maple":
					if u < -0.15:
						continue
					var q := Vector2(v * width, (u - 0.42) * length) / (length * 0.55)
					var r := q.length()
					var a := atan2(q.x, q.y)
					var star := 0.55 + 0.45 * pow(absf(cos(a * 2.5)), 2.2)
					if a > 2.4 or a < -2.4:
						star *= 0.55
					if r < star * 0.95:
						inside = 1.0
						w = 2.0
				"ellipse":
					if u < -0.1 or u > 1.0:
						continue
					w = 0.05 if u < 0.0 else pow(sin(PI * clampf(u, 0.0, 1.0)), 0.8) * (0.6 + 0.4 * u)
				"needle":
					if u < 0.0 or u > 1.0:
						continue
					w = 1.0 - u * 0.6
			if inside == 0.0:
				if absf(v) > w:
					continue
				inside = 1.0
			var i := y * W + x
			var vn := absf(v) / maxf(w, 0.001) if shape != "maple" else 0.3
			# Colour: base, darker brown rim, veins, slight gradient along the leaf.
			var cc := c
			cc = cc.lerp(c.darkened(0.25), clampf(u, 0.0, 1.0) * 0.4)
			var rim := smoothstep(0.75, 1.0, vn)
			cc = cc.lerp(edge_brown, rim * 0.45)
			var midrib := 1.0 - smoothstep(0.0, 0.07, absf(v))
			var vein := 1.0 - smoothstep(0.0, 0.08, absf(sin((u * 7.0 - absf(v) * 2.2) * PI)))
			cc = cc.lightened(0.18 * midrib + 0.06 * vein * (1.0 - rim))
			for sp in spots:
				var dd := Vector2((u - sp.x) * length, (v - sp.y) * width).length() / length
				if dd < sp.z:
					cc = cc.lerp(Color(0.3, 0.17, 0.07), 0.55 * (1.0 - dd / sp.z))
			var fine := (sin(x * 1.7 + y * 0.9) * sin(y * 1.3 - x * 0.4)) * 0.04
			cc = cc.lightened(fine) if fine > 0.0 else cc.darkened(-fine)
			cc = cc.darkened(1.0 - shade)
			col[i * 3] = cc.r
			col[i * 3 + 1] = cc.g
			col[i * 3 + 2] = cc.b
			alpha[i] = 1.0
			# Height: domed blade, sunk midrib and veins; higher leaves sit on top.
			var dome := sqrt(maxf(1.0 - vn * vn, 0.0))
			height[i] = dome * 0.6 - midrib * 0.35 - vein * 0.12


func _line(a: Vector2, b: Vector2, wa: float, wb: float, c: Color, tile: int) -> void:
	var o := _tile_origin(tile)
	var x0 := maxi(int(minf(a.x, b.x) - wa - 2), o.x + 1)
	var x1 := mini(int(maxf(a.x, b.x) + wa + 2), o.x + T - 2)
	var y0 := maxi(int(minf(a.y, b.y) - wa - 2), o.y + 1)
	var y1 := mini(int(maxf(a.y, b.y) + wa + 2), o.y + T - 2)
	var ab := b - a
	var l2 := maxf(ab.length_squared(), 0.0001)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
			var dist := (a + ab * t - p).length()
			var w := lerpf(wa, wb, t)
			if dist > w:
				continue
			var i := y * W + x
			var k := dist / maxf(w, 0.01)
			var cc := c.darkened(k * 0.35)
			col[i * 3] = cc.r
			col[i * 3 + 1] = cc.g
			col[i * 3 + 2] = cc.b
			alpha[i] = 1.0
			height[i] = sqrt(maxf(1.0 - k * k, 0.0)) * 0.8


## A twig with leaves fanning out from it, filling the tile like a real cut branch.
func _cluster(tile: int, shape: String, palette: Array) -> void:
	var o := Vector2(_tile_origin(tile))
	var stem_c := Color(0.25, 0.16, 0.1)
	var leaves := []   # [p, dir, len, width, colour]
	# Main twig from the bottom centre up, with side twigs.
	var base := o + Vector2(T * 0.5, T * 0.97)
	var tip := o + Vector2(T * 0.5 + rng.randf_range(-40, 40), T * 0.12)
	var twigs := [[base, tip]]
	for k in 5:
		var t := 0.25 + k * 0.15
		var p: Vector2 = base.lerp(tip, t)
		var side_dir := (-1.0 if k % 2 == 0 else 1.0)
		var e := p + Vector2(side_dir * rng.randf_range(110, 190), -rng.randf_range(40, 120))
		twigs.append([p, e])
	for tw in twigs:
		var a: Vector2 = tw[0]
		var b: Vector2 = tw[1]
		var n := 7 if tw == twigs[0] else 5
		for j in n:
			var t := 0.3 + 0.7 * float(j) / float(n - 1)
			var p := a.lerp(b, t)
			var along := (b - a).normalized()
			for s: float in [-1.0, 1.0]:
				var ang := s * rng.randf_range(0.5, 1.2)
				var dir := along.rotated(ang)
				var length := rng.randf_range(70, 115) if shape != "maple" else rng.randf_range(85, 125)
				var width := length * (0.36 if shape == "oak" else (0.5 if shape == "maple" else 0.3))
				leaves.append([p, dir, length, width, palette[rng.randi() % palette.size()]])
		# Terminal leaf.
		var td := (b - a).normalized()
		leaves.append([b - td * 10.0, td, rng.randf_range(80, 110), 34.0, palette[rng.randi() % palette.size()]])
	for tw in twigs:
		_line(tw[0], tw[1], 3.5 if tw == twigs[0] else 2.2, 1.2, stem_c, tile)
	leaves.shuffle()
	for i in leaves.size():
		var L: Array = leaves[i]
		var c: Color = L[4]
		c = Color(c.r * rng.randf_range(0.9, 1.08), c.g * rng.randf_range(0.88, 1.1), c.b * rng.randf_range(0.85, 1.1))
		var shade := 0.72 + 0.28 * float(i) / leaves.size()
		_leaf(shape, L[0], L[1], L[2], L[3], c, shade, tile)


func _pine(tile: int) -> void:
	var o := Vector2(_tile_origin(tile))
	var stem_c := Color(0.3, 0.2, 0.12)
	var base := o + Vector2(T * 0.5, T * 0.98)
	var tip := o + Vector2(T * 0.5, T * 0.04)
	var shoots := [[base, tip]]
	for k in 6:
		var t := 0.15 + k * 0.13
		var p: Vector2 = base.lerp(tip, t)
		var s := -1.0 if k % 2 == 0 else 1.0
		shoots.append([p, p + Vector2(s * rng.randf_range(120, 200), -rng.randf_range(80, 150))])
	for sh in shoots:
		_line(sh[0], sh[1], 3.0 if sh == shoots[0] else 2.0, 1.0, stem_c, tile)
	var greens := [Color(0.1, 0.2, 0.1), Color(0.14, 0.26, 0.12), Color(0.08, 0.16, 0.09), Color(0.18, 0.3, 0.14)]
	for sh in shoots:
		var a: Vector2 = sh[0]
		var b: Vector2 = sh[1]
		var along := (b - a).normalized()
		var n := int((b - a).length() / 5.0)
		for j in n:
			var t := float(j) / n
			if sh == shoots[0] and t < 0.12:
				continue
			var p := a.lerp(b, t)
			for s: float in [-1.0, 1.0]:
				var dir := along.rotated(s * rng.randf_range(0.6, 1.1))
				var length := rng.randf_range(34, 52) * (1.0 - t * 0.35)
				var c: Color = greens[rng.randi() % greens.size()]
				_leaf("needle", p, dir, length, 1.6, c.lightened(rng.randf() * 0.1), 0.8 + 0.2 * t, tile)


func _litter(tile: int) -> void:
	var o := Vector2(_tile_origin(tile))
	var pal := [Color(0.72, 0.36, 0.1), Color(0.55, 0.22, 0.08), Color(0.85, 0.6, 0.2), Color(0.45, 0.25, 0.12),
			Color(0.6, 0.1, 0.06), Color(0.38, 0.28, 0.15)]
	for i in 34:
		var p := o + Vector2(rng.randf_range(50, T - 50), rng.randf_range(50, T - 50))
		var dir := Vector2.from_angle(rng.randf() * TAU)
		var shape := "oak" if rng.randf() < 0.65 else ("maple" if rng.randf() < 0.5 else "ellipse")
		var length := rng.randf_range(60, 100)
		var width := length * (0.36 if shape == "oak" else (0.5 if shape == "maple" else 0.32))
		var c: Color = pal[rng.randi() % pal.size()]
		_leaf(shape, p, dir, length, width, c.darkened(rng.randf() * 0.2), 0.75 + 0.25 * float(i) / 34.0, tile)


func _twigs(tile: int) -> void:
	var o := Vector2(_tile_origin(tile))
	_branch(o + Vector2(T * 0.5, T * 0.98), Vector2(0, -1), 220.0, 9.0, 0, tile)
	_branch(o + Vector2(T * 0.3, T * 0.9), Vector2(-0.5, -1).normalized(), 150.0, 6.0, 1, tile)
	_branch(o + Vector2(T * 0.7, T * 0.85), Vector2(0.6, -1).normalized(), 150.0, 6.0, 1, tile)


func _branch(p: Vector2, dir: Vector2, length: float, width: float, depth: int, tile: int) -> void:
	var c := Color(0.27, 0.22, 0.18).lerp(Color(0.38, 0.32, 0.26), depth * 0.2)
	var e := p + dir * length
	var mid := p.lerp(e, 0.5) + Vector2(-dir.y, dir.x) * rng.randf_range(-12, 12)
	_line(p, mid, width, width * 0.85, c, tile)
	_line(mid, e, width * 0.85, width * 0.55, c, tile)
	if depth >= 4 or length < 18.0:
		return
	var n := 2 if depth < 2 else 3
	for i in n:
		var t := rng.randf_range(0.45, 1.0)
		var q := p.lerp(e, t) if t < 0.5 else mid.lerp(e, (t - 0.5) * 2.0)
		var nd := dir.rotated(rng.randf_range(0.35, 0.8) * (-1.0 if i % 2 == 0 else 1.0))
		_branch(q, nd, length * rng.randf_range(0.5, 0.7), maxf(width * 0.65, 2.2), depth + 1, tile)


## Transparent texels take their tile's average leaf colour so mipmaps don't bleed black.
func _fill_transparent() -> void:
	for tile in 8:
		var o := _tile_origin(tile)
		var acc := Vector3.ZERO
		var n := 0
		for y in range(o.y, o.y + T, 2):
			for x in range(o.x, o.x + T, 2):
				var i := y * W + x
				if alpha[i] > 0.5:
					acc += Vector3(col[i * 3], col[i * 3 + 1], col[i * 3 + 2])
					n += 1
		var avg := acc / maxf(n, 1)
		for y in range(o.y, o.y + T):
			for x in range(o.x, o.x + T):
				var i := y * W + x
				if alpha[i] < 0.5:
					col[i * 3] = avg.x
					col[i * 3 + 1] = avg.y
					col[i * 3 + 2] = avg.z


func _save() -> void:
	var rgba := PackedByteArray()
	rgba.resize(W * H * 4)
	var nrm := PackedByteArray()
	nrm.resize(W * H * 3)
	for y in H:
		for x in W:
			var i := y * W + x
			rgba[i * 4] = int(clampf(col[i * 3], 0.0, 1.0) * 255.0)
			rgba[i * 4 + 1] = int(clampf(col[i * 3 + 1], 0.0, 1.0) * 255.0)
			rgba[i * 4 + 2] = int(clampf(col[i * 3 + 2], 0.0, 1.0) * 255.0)
			rgba[i * 4 + 3] = 255 if alpha[i] > 0.5 else 0
			var xl := maxi(x - 1, 0)
			var xr := mini(x + 1, W - 1)
			var yu := maxi(y - 1, 0)
			var yd := mini(y + 1, H - 1)
			var dx := (height[y * W + xr] - height[y * W + xl]) * 1.6
			var dy := (height[yu * W + x] - height[yd * W + x]) * 1.6
			var n := Vector3(-dx, -dy, 1.0).normalized()
			nrm[i * 3] = int((n.x * 0.5 + 0.5) * 255.0)
			nrm[i * 3 + 1] = int((n.y * 0.5 + 0.5) * 255.0)
			nrm[i * 3 + 2] = int((n.z * 0.5 + 0.5) * 255.0)
	var img := Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, rgba)
	img.save_png("res://world/flora/textures/leaf_atlas.png")
	var nimg := Image.create_from_data(W, H, false, Image.FORMAT_RGB8, nrm)
	nimg.save_png("res://world/flora/textures/leaf_atlas_n.png")
