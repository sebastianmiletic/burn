class_name KeepArena
extends RefCounted
## The Dragon's Keep (Ashvane): ruined curtain walls with corner towers, a
## gatehouse with a portcullis, the shell of a great keep, scorched
## flagstones, fire basins, banners and the bones of an older dragon.
## Geometry mirrors Battlegrounds.castle (centre-relative cells).

const K := preload("res://world/architecture/arenas/arena_kit.gd")
const P := preload("res://world/architecture/arenas/arena_pieces.gd")


static func build(b: ArenaBuild) -> void:
	var pr := b.prop
	var half := int(pr["half"])
	var wall_h := float(pr["wall_h"])
	var c := b.center
	b.params = {"soot": 0.3, "outdoor": 1.0, "grime": 0.4, "grime_color": Color(0.3, 0.27, 0.24)}
	var k := b.shell
	var d := b.detail
	for kit: K in [k, d]:
		kit.push(Transform3D(Basis.IDENTITY, c))
		kit.ao_floor = 0.0
	var stone_tint := Color(0.86, 0.82, 0.78)
	var hf := float(half)
	# --- Curtain walls ---------------------------------------------------------------
	var breaches: Array = pr["breaches"]
	var runs := [
		[0, Vector3(-hf - 0.5, 0, -hf), Vector3(-6.5, 0, -hf), Vector3(0, 0, -1), -hf - 0.5],
		[0, Vector3(6.5, 0, -hf), Vector3(hf + 0.5, 0, -hf), Vector3(0, 0, -1), 6.5],
		[1, Vector3(hf, 0, -hf - 0.5), Vector3(hf, 0, hf + 0.5), Vector3(1, 0, 0), -hf - 0.5],
		[2, Vector3(hf + 0.5, 0, hf), Vector3(-hf - 0.5, 0, hf), Vector3(0, 0, 1), -hf - 0.5],
		[3, Vector3(-hf, 0, hf + 0.5), Vector3(-hf, 0, -hf - 0.5), Vector3(-1, 0, 0), -hf - 0.5],
	]
	for run: Array in runs:
		var side := int(run[0])
		var a: Vector3 = run[1]
		var e: Vector3 = run[2]
		var t0 := float(run[4])
		var length := a.distance_to(e)
		var tops := PackedFloat32Array()
		for i in int(ceil(length)):
			var t := roundi(t0 + i + 0.5)
			var top := wall_h
			for br: Array in breaches:
				if int(br[0]) == side and t >= int(br[1]) and t <= int(br[2]):
					top = float(br[3])
			tops.append(top)
		P.castle_wall(k, a, e, run[3], 3.0, wall_h, tops, true, K.CASTLE, stone_tint)
		# Rubble below breaches, inside and out.
		for br: Array in breaches:
			if int(br[0]) != side:
				continue
			var mid_t := (float(br[1]) + float(br[2])) * 0.5
			var along := (e - a).normalized()
			var at := a + along * (mid_t - t0)
			var out: Vector3 = run[3]
			P.rubble(k, at - out * 3.2, 3.2, 26, K.CASTLE, stone_tint)
			P.rubble(k, at + out * 3.4, 3.6, 22, K.CASTLE, stone_tint)
	# Inner buttresses (collision cells one in from the wall face).
	k.mat(K.CASTLE, stone_tint, 0.28)
	for side in 4:
		for t in range(-30, 31, 10):
			if side == 0 and absi(t) < 12:
				continue
			var cell := Battlegrounds._side_cell(side, t, half - 2)
			var dir_in := -_side_out(side)
			var p := Vector3(cell.x, 0, cell.y)
			var top := _wall_top(breaches, side, t, wall_h)
			if top < wall_h:
				continue
			k.push(Transform3D(P._basis_for(_side_along(side), dir_in), p))
			k.box(Vector3(-0.15, 5.0, 0), Vector3(1.3, 10.0, 1.4), 0.05)
			k.push(Transform3D(Basis(Vector3(0, 0, 1), -0.7), Vector3(-0.35, 10.0, 0)))
			k.box(Vector3.ZERO, Vector3(1.0, 1.2, 1.5), 0.05, false)
			k.pop()
			k.pop()
	# --- Towers --------------------------------------------------------------------------
	for t: Array in pr["towers"]:
		P.round_tower(k, t[0], float(t[1]), float(t[2]), bool(t[3]), true, K.CASTLE, stone_tint)
		if bool(t[3]):
			var at: Vector3 = t[0]
			var inward := -Vector3(signf(at.x), 0, signf(at.z)).normalized()
			P.rubble(k, at + inward * 8.0, 3.0, 20, K.CASTLE, stone_tint)
	# --- Gatehouse -----------------------------------------------------------------------
	_gatehouse(b, k, d, -hf, wall_h, stone_tint)
	# --- Keep ------------------------------------------------------------------------------
	_keep(b, k, d, pr, stone_tint)
	# --- Courtyard -----------------------------------------------------------------------
	var basins: Array = pr["basins"]
	var skull: Vector3 = pr["skull"]
	var skip := func(x: float, z: float) -> bool:
		if z > 15.0 and absf(x) < 13.0:
			return true
		for bs: Vector3 in basins:
			if Vector2(x - bs.x, z - bs.z).length() < 1.4:
				return true
		return false
	k.mat(K.LIMESTONE, Color(0.9, 0.84, 0.76), 0.42)
	k.ao_floor = -INF
	k.flagstones(-hf + 1.5, -hf + 1.5, hf - 1.5, hf - 1.5, 0.0, 1.3, 0.05, 0.3, 0.025, skip)
	# Floor bed under broken flagstones and along the walls.
	k.mat(K.ASH, Color(0.3, 0.27, 0.25), 0.35)
	k.pquad(Vector3(-hf, -0.12, -hf), Vector3(hf, -0.12, -hf), Vector3(hf, -0.12, hf), Vector3(-hf, -0.12, hf), Vector3.UP)
	k.ao_floor = 0.0
	# Scorched ash drifts.
	for i in 10:
		var a := k.rng.randf() * TAU
		var r := k.rng.randf_range(10.0, 34.0)
		var p := Vector3(cos(a) * r, -0.12, sin(a) * r)
		if p.z > 14.0 and absf(p.x) < 14.0:
			continue
		k.mat(K.TRI + K.ASH, Color(0.62, 0.56, 0.52), 0.35)
		k.rock(p, Vector3(k.rng.randf_range(1.2, 2.6), 0.2, k.rng.randf_range(1.0, 2.2)), 0.3, 2, i, 0.1)
	for i in basins.size():
		var bs: Vector3 = basins[i]
		P.fire_basin(b, k, bs, c + bs, 1.0, "fire", K.GRANITE, Color(1.0, 0.55, 0.22), 1)
	_dragon_bones(k, skull, float(pr["bone_side"]))
	# Banners and sconces on the inner wall faces.
	var banner_red := Color(0.42, 0.05, 0.04)
	var trim := Color(0.12, 0.08, 0.05)
	for side in 4:
		var out := _side_out(side)
		for j in range(-3, 4):
			var t := j * 10 + 5
			if side == 0 and absi(t) < 14:
				continue
			if _wall_top(breaches, side, t, wall_h) < wall_h:
				continue
			var cell := Battlegrounds._side_cell(side, t, half - 1)
			var face := Vector3(cell.x, 0, cell.y) - out * 0.0 + out * 0.5 - out * 1.0
			face = Vector3(cell.x, 0, cell.y) + out * 0.5 - out * 1.0
			face = _inner_face(side, t, half)
			if j % 2 == 0:
				P.banner(d, face + Vector3(0, 12.5, 0), -out, 2.0, 7.5, banner_red, trim, side * 31 + j)
			else:
				P.sconce(b, d, face + Vector3(0, 4.2, 0), -out, c + face + Vector3(0, 4.2, 0))
	# Crates, barrels and a broken cart against the walls.
	_clutter(k, d, half)
	# Gate: portcullis in the gatehouse slot.
	var g := P.portcullis(9.0, 9.2)
	b.gate(int(pr["gate"]), g, Transform3D(Basis.IDENTITY, c + Vector3(0, 0, -hf)), "drop", 9.4)


static func _side_out(side: int) -> Vector3:
	return [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)][side]


static func _side_along(side: int) -> Vector3:
	return [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 0, -1)][side]


## Point on the courtyard face of the curtain wall at position t along `side`.
static func _inner_face(side: int, t: int, half: int) -> Vector3:
	var cell := Battlegrounds._side_cell(side, t, half)
	return Vector3(cell.x, 0, cell.y) - _side_out(side) * 1.5


static func _wall_top(breaches: Array, side: int, t: int, wall_h: float) -> float:
	for br: Array in breaches:
		if int(br[0]) == side and t >= int(br[1]) - 2 and t <= int(br[2]) + 2:
			return float(br[3])
	return wall_h


static func _gatehouse(b: ArenaBuild, k: K, d: K, gz: float, wall_h: float, tint: Color) -> void:
	k.mat(K.CASTLE, tint, 0.28)
	var z0 := gz - 2.5
	var z1 := gz + 2.5
	var top := wall_h + 6.0
	for gx: float in [-8.0, 8.0]:
		P.round_tower(k, Vector3(gx, 0, gz), 3.6, wall_h + 5.0, false, true, K.CASTLE, tint)
	k.mat(K.CASTLE, tint, 0.28)
	# piers and upper block
	k.box(Vector3(-5.5, 4.5, gz), Vector3(2.0, 9.0, 5.0), 0.04)
	k.box(Vector3(5.5, 4.5, gz), Vector3(2.0, 9.0, 5.0), 0.04)
	k.box(Vector3(0, (9.0 + top) * 0.5, gz), Vector3(13.0, top - 9.0, 5.0), 0.04)
	# Pointed arch faces with the vault between them.
	var spring := 3.4
	var poly := PackedVector2Array([Vector2(-4.5, spring), Vector2(-4.5, 9.6), Vector2(4.5, 9.6), Vector2(4.5, spring)])
	for i in range(1, 16):
		poly.append(K._arch_pt(float(16 - i) / 16.0, 4.5, spring, 0.25))
	k.mat(K.CASTLE, tint * Color(0.9, 0.9, 0.9), 0.28)
	k.push(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
	k.extrude(poly, z0 + 0.01, z1 - 0.01, true)
	k.pop()
	k.mat(K.CASTLE, tint * Color(1.06, 1.04, 1.0), 0.3)
	for z: float in [z0 - 0.15, z1 + 0.15]:
		k.push(Transform3D(Basis.IDENTITY, Vector3(0, 0, z)))
		k.arch(9.0, spring, 0.95, 0.5, 15, 0.25, 0.02)
		k.pop()
	# portcullis grooves and the dark slot above
	k.mat(K.DARK, Color(0.05, 0.045, 0.04), 0.5)
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(s * 4.47, 4.5, gz), Vector3(0.08, 9.0, 0.35), 0.0)
	# Machicolations and battlements on the outer (north) face.
	k.mat(K.CASTLE, tint * Color(0.88, 0.88, 0.88), 0.3)
	for i in 9:
		var x := -6.0 + i * 1.5
		k.box(Vector3(x, top - 2.4, z0 - 0.35), Vector3(0.4, 1.0, 0.7), 0.04, false)
	k.mat(K.CASTLE, tint, 0.28)
	k.box(Vector3(0, top - 1.5, z0 - 0.45), Vector3(13.4, 0.9, 0.9), 0.05, false)
	for i in 7:
		var x := -6.0 + i * 2.0
		k.vary(0.05)
		k.box(Vector3(x, top + 0.55, z0 + 0.1), Vector3(1.1, 1.1, 0.8), 0.06)
		k.box(Vector3(x, top + 0.55, z1 - 0.3), Vector3(1.1, 1.1, 0.6), 0.06)
	# Banners flanking the gate inside.
	for s: float in [-1.0, 1.0]:
		P.banner(d, Vector3(s * 5.6, 15.5, z1 + 0.1), Vector3(0, 0, 1), 1.8, 6.5, Color(0.42, 0.05, 0.04), Color(0.12, 0.08, 0.05), 7 + int(s))
		P.sconce(b, d, Vector3(s * 5.6, 4.5, z1), Vector3(0, 0, 1), b.center + Vector3(s * 5.6, 4.5, z1), "fire", Color(1.0, 0.58, 0.25), 2.0)


static func _keep(b: ArenaBuild, k: K, d: K, pr: Dictionary, tint: Color) -> void:
	var k0: Vector3 = (pr["keep"] as Array)[0]
	var k1: Vector3 = (pr["keep"] as Array)[1]
	var x0 := k0.x - 0.5
	var x1 := k1.x + 0.5
	var z0 := k0.z - 0.5
	var z1 := k1.z + 0.5
	var top := k1.y
	var collapse := int(pr["collapse"])
	var ccx := 12.0 if collapse == 0 else -12.0
	var col_top := func(x: float, z: float) -> float:
		var dist := Vector2(x - ccx, (z - 16.0) * 0.8).length()
		return clampf(14.0 + maxf(0.0, dist - 2.0) / 0.6, 14.0, top)
	var thick := 2.0
	# Four faces as columns stepping down into the collapse.
	var faces := [[Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(0, 0, -1)], [Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(1, 0, 0)],
			[Vector3(x1, 0, z1), Vector3(x0, 0, z1), Vector3(0, 0, 1)], [Vector3(x0, 0, z1), Vector3(x0, 0, z0), Vector3(-1, 0, 0)]]
	for f: Array in faces:
		var a: Vector3 = f[0]
		var e: Vector3 = f[1]
		var out: Vector3 = f[2]
		var along := (e - a).normalized()
		var length := a.distance_to(e)
		var n := int(round(length / 1.5))
		var step := length / n
		for i in n:
			var p := a + along * (float(i) + 0.5) * step - out * thick * 0.5
			var h: float = col_top.call(p.x, p.z)
			var broken := h < top - 0.1
			if broken:
				h += k.rng.randf_range(-1.2, 0.8)
			k.mat(K.CASTLE, tint, 0.28)
			k.vary(0.04)
			k.push(Transform3D(P._basis_for(along, out), p))
			var door := out.z < -0.5 and absf(p.x) < 3.2
			if door:
				k.box(Vector3(0, (6.0 + h) * 0.5, 0), Vector3(thick, h - 6.0, step + 0.01), 0.0)
			else:
				k.box(Vector3(0, h * 0.5, 0), Vector3(thick, h, step + 0.01), 0.0)
			k.pop()
		# battered plinth and string courses
		k.mat(K.CASTLE, tint * Color(0.9, 0.9, 0.9), 0.28)
		if out.z < -0.5:
			k.moulding(a, Vector3(-3.0, 0, z0), out, PackedVector2Array([Vector2(0.6, 0.0), Vector2(0.0, 1.8)]))
			k.moulding(Vector3(3.0, 0, z0), e, out, PackedVector2Array([Vector2(0.6, 0.0), Vector2(0.0, 1.8)]))
		else:
			k.moulding(a, e, out, PackedVector2Array([Vector2(0.6, 0.0), Vector2(0.0, 1.8)]))
		for y: float in [8.5, 16.5]:
			var band := PackedVector2Array([Vector2(0.0, y - 0.18), Vector2(0.22, y - 0.08), Vector2(0.22, y + 0.08), Vector2(0.0, y + 0.18)])
			# only where the wall still stands that high
			var s0 := -1.0
			var tt := 0.0
			while tt <= length:
				var q := a + along * tt
				var ok := float(col_top.call(q.x, q.z)) > y + 0.5 and tt < length - 0.01
				if ok and s0 < 0.0:
					s0 = tt
				elif not ok and s0 >= 0.0:
					k.moulding(a + along * s0, a + along * tt, out, band)
					s0 = -1.0
				tt += 0.5
		# windows
		for wy: float in [11.0, 19.0, 23.0]:
			var count := int(length / 5.0)
			for j in count:
				var q := a + along * ((float(j) + 0.5) * length / count)
				if float(col_top.call(q.x, q.z)) < wy + 2.0:
					continue
				P.window(k, q + Vector3(0, wy, 0), out, 0.9 if wy > 12.0 else 1.2, 2.2, K.CASTLE, tint)
		# parapet merlons where the wall is whole
		var m := int(length / 2.0)
		for j in m:
			var q := a + along * ((float(j) + 0.5) * length / m)
			if float(col_top.call(q.x, q.z)) < top - 0.1:
				continue
			k.mat(K.CASTLE, tint, 0.28)
			k.vary(0.05)
			k.push(Transform3D(P._basis_for(along, out), q - out * 0.35))
			k.box(Vector3(0, top + 0.6, 0), Vector3(0.7, 1.2, 1.1), 0.06)
			k.box(Vector3(0, top + 1.25, 0), Vector3(0.82, 0.12, 1.2), 0.04)
			k.pop()
	# Clasping corner buttresses.
	for cx: float in [x0, x1]:
		for cz: float in [z0, z1]:
			var h: float = col_top.call(cx, cz)
			if h < top - 0.1:
				h = maxf(4.0, h - 4.0)
			k.mat(K.CASTLE, tint * Color(0.95, 0.95, 0.95), 0.28)
			k.box(Vector3(cx, h * 0.5, cz), Vector3(3.0, h, 3.0), 0.06)
			if h >= top - 4.5:
				P.round_tower(k, Vector3(cx + signf(cx) * 0.4, top - 2.0, cz + signf(cz - 26.0) * 0.4), 1.6, 5.0, false, true, K.CASTLE, tint)
	# The doorway: arched portal.
	var dz := z0
	var spring := 3.5
	var poly := PackedVector2Array([Vector2(-2.5, spring), Vector2(-2.5, 6.6), Vector2(2.5, 6.6), Vector2(2.5, spring)])
	for i in range(1, 12):
		poly.append(K._arch_pt(float(12 - i) / 12.0, 2.5, spring, 0.0))
	k.mat(K.CASTLE, tint * Color(0.9, 0.9, 0.9), 0.28)
	k.extrude(poly, dz, dz + thick, true)
	k.mat(K.CASTLE, tint * Color(1.08, 1.05, 1.0), 0.3)
	k.push(Transform3D(Basis.IDENTITY, Vector3(0, 0, dz - 0.15)))
	k.arch(5.0, spring, 0.8, 0.4, 11)
	k.pop()
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(s * 2.85, spring * 0.5, dz - 0.15), Vector3(0.7, spring, 0.5), 0.05)
	# Fallen door leaf.
	d.mat(K.PLANKS, Color(0.55, 0.45, 0.38), 0.6)
	d.push(Transform3D(Basis.from_euler(Vector3(-1.45, 0.3, 0.0)), Vector3(-1.4, 0.15, dz - 2.6)))
	d.box(Vector3.ZERO, Vector3(2.3, 5.2, 0.18), 0.02, false)
	d.mat(K.IRON, Color(1, 1, 1), 1.0)
	for y: float in [-1.8, 0.0, 1.8]:
		d.box(Vector3(0, y, 0.1), Vector3(2.2, 0.14, 0.04), 0.01, false)
	d.pop()
	# Collapse rubble spilling into the courtyard.
	P.rubble(k, Vector3(ccx + signf(ccx) * 1.5, 0, z0 - 3.0), 5.5, 60, K.CASTLE, tint)
	P.rubble(k, Vector3(ccx + signf(ccx) * 3.5, 0, z0 + 4.0), 4.0, 30, K.CASTLE, tint)
	# Hall interior: floor, timber ceiling, pillars, a brazier and the chest dais.
	var hx0 := -10.5
	var hx1 := 10.5
	var hz0 := z0 + thick
	var hz1 := z1 - thick
	k.mat(K.GRANITE, Color(0.6, 0.57, 0.55), 0.45)
	k.flagstones(hx0, hz0, hx1, hz1, 0.0, 1.4, 0.05, 0.25)
	k.mat(K.PLANKS, Color(0.5, 0.4, 0.32), 0.5)
	k.box(Vector3(0, 8.15, (hz0 + hz1) * 0.5), Vector3(hx1 - hx0 + 0.2, 0.4, hz1 - hz0 + 0.2), 0.0, false)
	k.mat(K.BARK, Color(0.45, 0.36, 0.28), 0.5)
	var bz := hz0 + 1.0
	while bz < hz1:
		k.box(Vector3(0, 7.65, bz), Vector3(hx1 - hx0, 0.6, 0.45), 0.04, false)
		bz += 2.2
	for px: float in [-5.0, 5.0]:
		for pz: float in [hz0 + 5.0, hz1 - 5.0]:
			k.mat(K.CASTLE, tint, 0.28)
			k.column(Vector3(px, 0, pz), 7.6, 0.55, "plain")
	P.fire_basin(b, k, Vector3(0, 0, hz1 - 6.0), b.center + Vector3(0, 0, hz1 - 6.0), 0.8, "fire", K.GRANITE, Color(1.0, 0.55, 0.22), 0)
	k.mat(K.CASTLE, tint, 0.28)
	k.box(Vector3(0, 0.25, hz1 - 2.0), Vector3(5.0, 0.5, 2.6), 0.05)


## An ancient dragon skeleton half sunk in the courtyard.
static func _dragon_bones(k: K, skull: Vector3, side: float) -> void:
	var face := Vector3(-side, 0, 0.35).normalized()   # skull looks back into the courtyard
	var yaw := atan2(face.x, face.z)
	k.push_at(skull, yaw)
	k.ao_floor = 0.0
	k.mat(K.BONE, Color(0.9, 0.86, 0.76), 0.7)
	# cranium and snout
	k.rock(Vector3(0, 0.8, -0.4), Vector3(1.35, 1.0, 1.7), 0.12, 3, 11, 0.7)
	k.rock(Vector3(0, 0.55, 1.6), Vector3(0.8, 0.55, 1.6), 0.1, 3, 12, 0.7)
	# brow ridges and horns sweeping back
	for s: float in [-1.0, 1.0]:
		k.rock(Vector3(s * 0.75, 1.35, 0.4), Vector3(0.45, 0.28, 0.7), 0.15, 2, 13 + int(s))
		var hp := K.bezier(Vector3(s * 0.8, 1.4, -0.6), Vector3(s * 1.6, 2.2, -2.2), Vector3(s * 1.3, 2.0, -4.0), 8)
		var hr := PackedFloat32Array()
		for i in hp.size():
			hr.append(lerpf(0.32, 0.03, float(i) / (hp.size() - 1)))
		k.sweep(hp, hr, 8)
		var hp2 := K.bezier(Vector3(s * 0.9, 1.0, -1.2), Vector3(s * 1.9, 1.1, -2.2), Vector3(s * 2.1, 0.7, -3.2), 6)
		var hr2 := PackedFloat32Array()
		for i in hp2.size():
			hr2.append(lerpf(0.18, 0.02, float(i) / (hp2.size() - 1)))
		k.sweep(hp2, hr2, 6)
	# eye sockets and nostrils
	k.mat(K.DARK, Color(0.05, 0.04, 0.035), 0.5)
	for s: float in [-1.0, 1.0]:
		k.rock(Vector3(s * 0.72, 1.05, 0.55), Vector3(0.32, 0.28, 0.36), 0.1, 2, 21)
		k.rock(Vector3(s * 0.3, 0.75, 3.05), Vector3(0.12, 0.1, 0.12), 0.1, 1, 22)
	# lower jaw lying open, and teeth
	k.mat(K.BONE, Color(0.86, 0.82, 0.72), 0.7)
	k.push(Transform3D(Basis.from_euler(Vector3(0.25, 0.18, 0.0)), Vector3(0.2, 0.15, 0.9)))
	for s: float in [-1.0, 1.0]:
		k.sweep(K.bezier(Vector3(s * 0.75, 0, -1.2), Vector3(s * 0.7, 0.1, 1.0), Vector3(s * 0.25, 0.05, 2.6), 8), PackedFloat32Array([0.2, 0.2, 0.19, 0.18, 0.17, 0.16, 0.14, 0.13, 0.12]), 7)
	k.pop()
	for i in 9:
		for s: float in [-1.0, 1.0]:
			var z := 0.4 + i * 0.32
			k.spike(Vector3(s * (0.68 - i * 0.04), 0.35, z), Vector3(0, -1, 0.1).normalized(), 0.45 - i * 0.02, 0.07, 5, i)
	# Spine curving away behind the skull, ribs arching from it.
	var spine := K.bezier(Vector3(0, 0.3, -2.2), Vector3(side * -3.0, 0.9, -12.0), Vector3(side * 2.5, 0.2, -22.0), 26)
	for i in spine.size():
		var p := spine[i]
		var s := lerpf(0.55, 0.25, float(i) / spine.size())
		k.mat(K.BONE, Color(0.88, 0.84, 0.74), 0.7)
		k.rock(p, Vector3(s, s * 0.9, s * 0.7), 0.15, 2, 40 + i)
		k.spike(p + Vector3(0, s * 0.6, 0), Vector3(0, 1, -0.3).normalized(), s * 2.2, s * 0.35, 5, i)
		if i >= 3 and i <= 17 and i % 2 == 1:
			var tang := (spine[mini(i + 1, spine.size() - 1)] - spine[maxi(i - 1, 0)]).normalized()
			var lat := tang.cross(Vector3.UP).normalized()
			var span := lerpf(3.8, 2.0, absf(float(i) - 9.0) / 9.0)
			for sd: float in [-1.0, 1.0]:
				if k.rng.randf() < 0.18:
					continue
				var broken := k.rng.randf() < 0.3
				var p2 := p + lat * sd * span * 0.75 + Vector3(0, span * 0.9, 0)
				var p3 := p + lat * sd * span * 1.15 + Vector3(0, -0.3, 0) - tang * 0.6
				var path := K.bezier(p, p2, p3, 10)
				if broken:
					path = path.slice(0, 7)
				var radii := PackedFloat32Array()
				for j in path.size():
					radii.append(lerpf(0.17, 0.07, float(j) / 10.0))
				k.sweep(path, radii, 6)
	# Ash mound the bones are sinking into.
	k.mat(K.TRI + K.ASH, Color(0.5, 0.46, 0.44), 0.35)
	for i in 8:
		var p := spine[i * 3]
		k.rock(p + Vector3(k.rng.randf_range(-1, 1), -0.35, k.rng.randf_range(-1, 1)), Vector3(2.4, 0.5, 2.2), 0.3, 2, 70 + i, 0.2)
	k.pop()


static func _clutter(k: K, d: K, half: int) -> void:
	var hf := float(half)
	for i in 10:
		var side := i % 4
		var t := k.rng.randf_range(-28.0, 28.0)
		if side == 0 and absf(t) < 12.0:
			continue
		var out := _side_out(side)
		var along := _side_along(side)
		var base := out * (hf - 2.6) + along * t
		for j in k.rng.randi_range(2, 4):
			var p := base + along * k.rng.randf_range(-1.6, 1.6) - out * k.rng.randf_range(0.0, 1.2)
			if k.rng.randf() < 0.55:
				_barrel(d, p, k.rng.randf() * TAU, k.rng.randf() < 0.25)
			else:
				var s := k.rng.randf_range(0.7, 1.1)
				d.mat(K.PLANKS, Color(0.6, 0.5, 0.42), 0.6)
				d.vary(0.1)
				d.push_at(p, k.rng.randf() * TAU)
				d.box(Vector3(0, s * 0.5, 0), Vector3(s, s, s), 0.04)
				d.mat(K.IRON, Color(1, 1, 1), 1.0)
				d.box(Vector3(0, s * 0.5, 0), Vector3(s + 0.02, 0.08, s + 0.02), 0.01)
				d.pop()


static func _barrel(d: K, p: Vector3, yaw: float, fallen: bool) -> void:
	d.push(Transform3D(Basis(Vector3.UP, yaw) * (Basis(Vector3.RIGHT, PI / 2.0) if fallen else Basis.IDENTITY), p + (Vector3(0, 0.38, 0) if fallen else Vector3.ZERO)))
	d.mat(K.PLANKS, Color(0.55, 0.42, 0.32), 0.7)
	d.lathe(PackedVector2Array([Vector2(0.32, -0.45 if fallen else 0.0), Vector2(0.38, 0.45 - (0.45 if fallen else 0.0)), Vector2(0.32, 0.9 - (0.45 if fallen else 0.0))]), 12)
	d.lathe(PackedVector2Array([Vector2(0.32, 0.9 - (0.45 if fallen else 0.0)), Vector2(0.0, 0.88 - (0.45 if fallen else 0.0))]), 12)
	d.mat(K.IRON, Color(1, 1, 1), 1.0)
	for y: float in [0.12, 0.78]:
		var yy := y - (0.45 if fallen else 0.0)
		d.lathe(PackedVector2Array([Vector2(0.35, yy - 0.04), Vector2(0.36, yy), Vector2(0.35, yy + 0.04)]), 12)
	d.pop()
