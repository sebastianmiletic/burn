class_name CharHead
extends RefCounted
## Heads: a sculpted skull with brow, cheekbones, jaw and chin, separate nose,
## ears, lips, eyeballs and brows; hair styles, beards, hats, helmets, hoods,
## horns, tusks and crowns. Built in the bind pose (body units, faces -Z).

const R := preload("res://models/character/char_rig.gd")


## Head shape parameters from a style.
static func params(st: Dictionary, pr: Dictionary) -> Dictionary:
	var fem: float = pr["fem"]
	var brute := bool(st.get("tusks", false)) or float(st.get("bulk", 1.0)) > 1.5
	var hs := float(st.get("head_scale", 1.0))
	var age := float(st.get("age", 0.3))
	return {
		"c": Vector3(0, 1.7, -0.012),
		"r": Vector3(0.077, 0.112, 0.097) * hs * Vector3(lerpf(1.0, 0.95, fem), lerpf(1.0, 0.96, fem), lerpf(1.0, 0.96, fem)),
		"hs": hs,
		"jaw": float(st.get("jaw", 1.25 if brute else lerpf(1.0, 0.86, fem))),
		"brow": float(st.get("brow", 0.9 if brute else lerpf(0.45, 0.1, fem))),
		"nose": float(st.get("nose", 1.25 if brute else lerpf(1.0, 0.8, fem))),
		"cheek": float(st.get("cheeks", 0.3 if bool(st.get("gaunt", false)) else 1.0)),
		"age": age,
		"gaunt": bool(st.get("gaunt", false)),
	}


static func _bump(x: float, y: float, cx: float, cy: float, sx: float, sy: float) -> float:
	var dx := (x - cx) / sx
	var dy := (y - cy) / sy
	return exp(-(dx * dx + dy * dy))


## Displaced point of the head surface for unit direction d (local, before features).
static func deform(d: Vector3, p: Vector3, hp: Dictionary) -> Vector3:
	var q := p
	var jaw: float = hp["jaw"]
	if d.y < 0.0:
		var k := -d.y
		q.x *= lerpf(1.0, 0.64 * jaw, k * k)
		if q.z > 0.0:
			q.z *= lerpf(1.0, 0.7, k)
		else:
			q.z -= 0.012 * smoothstep(0.55, 1.0, k) * jaw
	if d.z > 0.0 and d.y > -0.3:
		q.z *= 1.06
		q.y += 0.004 * d.z
	if d.z < 0.0:
		var f := smoothstep(0.25, 0.95, -d.z)
		q.z *= lerpf(1.0, 0.86, f)
		# Sculpt: brow ridge, eye sockets, cheekbones, mouth, chin.
		var brow: float = hp["brow"]
		var x := absf(q.x)
		var s := 0.0
		s += _bump(x, q.y, 0.03, 0.03, 0.03, 0.011) * (0.004 + 0.006 * brow)
		s -= _bump(x, q.y, 0.032, 0.01, 0.016, 0.01) * 0.009
		s += _bump(x, q.y, 0.048, -0.018, 0.016, 0.016) * 0.006 * float(hp["cheek"])
		if hp["gaunt"]:
			s -= _bump(x, q.y, 0.045, -0.045, 0.016, 0.02) * 0.008
		s += _bump(x, q.y, 0.0, -0.088, 0.02, 0.014) * 0.006 * jaw
		s -= _bump(x, q.y, 0.0, -0.06, 0.03, 0.004) * 0.002
		q.z -= s * f
	return q


## Approximate z of the face surface at local (x, y).
static func face_z(hp: Dictionary, x: float, y: float) -> float:
	var r: Vector3 = hp["r"]
	var xs := x
	if y < 0.0:
		var k := -y / r.y
		xs = x / lerpf(1.0, 0.64 * float(hp["jaw"]), k * k)
	var e := 1.0 - (xs / r.x) * (xs / r.x) - (y / r.y) * (y / r.y)
	return -r.z * sqrt(maxf(e, 0.0)) * 0.87


static func _hb(g: CharGeo, p_local: Vector3) -> Variant:
	# Lower face follows the jaw, the nape blends into the neck.
	if p_local.y < -0.045 and p_local.z < 0.02:
		return [[R.HEAD, R.JAW], [1.0 - smoothstep(-0.045, -0.08, p_local.y) * 0.85, smoothstep(-0.045, -0.08, p_local.y) * 0.85]]
	if p_local.y < -0.06 and p_local.z >= 0.02:
		return [[R.HEAD, R.NECK], [0.7, 0.3]]
	var _u := g
	return [[R.HEAD], [1.0]]


static func build(g: CharGeo, glow: Dictionary, st: Dictionary, pr: Dictionary) -> Dictionary:
	var hp := params(st, pr)
	var c: Vector3 = hp["c"]
	var r: Vector3 = hp["r"]
	var info := {"head_center": c, "head_top": c + Vector3(0, r.y + 0.02, 0)}
	if pr["skeleton"]:
		CharBones.skull(g, glow, st, hp)
		_headwear(g, glow, st, hp, true)
		return info
	var decay := float(st.get("decay", 0.0))
	var skin_type := CharGeo.M_DECAY if decay > 0.0 else CharGeo.M_SKIN

	# Neck.
	g.mat(CharGeo.SKIN, skin_type)
	var nr := 0.05 * lerpf(1.0, 0.86, float(pr["fem"])) * (0.85 if pr["gaunt"] else 1.0) * sqrt(float(pr["bulk"]))
	g.tube(PackedVector3Array([Vector3(0, 1.47, 0.01), Vector3(0, 1.53, 0.004), Vector3(0, 1.6, -0.004), Vector3(0, 1.66, -0.004)]),
		[Vector4(nr * 1.25, nr * 1.1, nr * 1.3, 2.0), Vector4(nr, nr * 0.95, nr, 2.0), Vector4(nr * 0.95, nr * 0.95, nr, 2.0), Vector4(nr * 0.9, nr * 0.8, nr, 2.0)],
		14, [Vector3(R.CHEST, R.NECK, 0.3), Vector3(R.NECK, R.CHEST, 0.0), Vector3(R.NECK, R.HEAD, 0.4), Vector3(R.HEAD, R.NECK, 0.0)], 0, 0)

	# Skull and face.
	var v0 := g.vertex_count()
	g.mat(CharGeo.SKIN, skin_type)
	g.ellipsoid(c, r, 26, 36, Basis.IDENTITY, 2.0, func(d: Vector3, p: Vector3) -> Vector3: return deform(d, p, hp))
	g.reweight(v0, g.vertex_count(), func(p: Vector3) -> Variant: return _hb(g, p - c))
	# Cheeks and lips get a little colour; eye sockets and the mouth corners darken.
	g.reshade(v0, g.vertex_count(), func(p: Vector3) -> Variant:
		var l := p - c
		if l.z > -0.03:
			return null
		var x := absf(l.x)
		var sock := _bump(x, l.y, 0.032, 0.01, 0.018, 0.012)
		var cheek := _bump(x, l.y, 0.045, -0.025, 0.02, 0.018)
		return Vector2(1.0 + cheek * 0.04 - sock * 0.12, 1.0 - sock * 0.45))

	# Nose: bridge and tip, embedded in the face.
	var ns: float = hp["nose"]
	var nz := face_z(hp, 0.0, -0.015)
	g.mat(CharGeo.SKIN, skin_type, 1.02)
	g.bone(R.HEAD)
	var nb := Basis(Vector3.RIGHT, deg_to_rad(-18.0))
	g.ellipsoid(c + Vector3(0, -0.016, nz + 0.004), Vector3(0.0105, 0.03, 0.014) * ns, 8, 12, nb)
	g.ellipsoid(c + Vector3(0, -0.038, nz - 0.008 * ns), Vector3(0.0125, 0.011, 0.012) * ns, 8, 12)
	for sg: float in [-1.0, 1.0]:
		g.ellipsoid(c + Vector3(sg * 0.011 * ns, -0.04, nz - 0.001), Vector3(0.008, 0.007, 0.009) * ns, 6, 8)

	# Lips.
	var lz := face_z(hp, 0.0, -0.058)
	g.mat(CharGeo.SKIN, CharGeo.M_LIPS)
	g.bone(R.HEAD)
	g.ellipsoid(c + Vector3(0, -0.053, lz + 0.001), Vector3(0.02, 0.0055, 0.008), 6, 12)
	g.bone2(R.HEAD, R.JAW, 0.7)
	g.ellipsoid(c + Vector3(0, -0.064, lz + 0.002), Vector3(0.018, 0.0065, 0.008), 6, 12)

	# Ears.
	g.mat(CharGeo.SKIN, skin_type, 0.97)
	g.bone(R.HEAD)
	var pointed := str(st.get("ears", "")) == "pointed"
	for sg: float in [-1.0, 1.0]:
		var eb := Basis(Vector3.UP, sg * deg_to_rad(18.0)) * Basis(Vector3.BACK, sg * deg_to_rad(-8.0))
		g.ellipsoid(c + Vector3(sg * r.x * 0.96, -0.004, 0.012), Vector3(0.011, 0.03 if not pointed else 0.045, 0.019), 8, 10, eb)

	# Eyes: glowing for monsters, real eyeballs otherwise.
	var eye_glow: Variant = st.get("eyes", null)
	for sg: float in [-1.0, 1.0]:
		var ex := sg * 0.032
		var ey := 0.011
		var ez := face_z(hp, 0.032, ey) + 0.006
		if eye_glow != null:
			var eg := _glow(glow, "eyes")
			eg.bone(R.HEAD)
			eg.mat(CharGeo.FIXED, CharGeo.M_DARK)
			eg.ellipsoid(c + Vector3(ex, ey, ez - 0.002), Vector3(0.012, 0.0085, 0.008), 6, 10)
		else:
			g.mat(CharGeo.FIXED, CharGeo.M_EYE)
			g.bone(R.HEAD)
			# Local +Y of the eyeball points forward so UV.y is the angle from the pupil.
			g.ellipsoid(c + Vector3(ex, ey, ez + 0.002), Vector3(0.0118, 0.0118, 0.0118), 10, 12, Basis(Vector3.RIGHT, -PI * 0.5))
			# Upper lid.
			g.mat(CharGeo.SKIN, skin_type, 0.9, 0.7)
			g.ellipsoid(c + Vector3(ex, ey + 0.006, ez - 0.0005), Vector3(0.0135, 0.0055, 0.011), 6, 10, Basis(Vector3.BACK, sg * 0.12))
	# Brows.
	if not st.get("skeleton", false):
		g.mat(CharGeo.HAIR, CharGeo.M_HAIR, 0.85)
		g.bone(R.HEAD)
		for sg: float in [-1.0, 1.0]:
			var bz := face_z(hp, 0.03, 0.028) - 0.002
			g.ellipsoid(c + Vector3(sg * 0.031, 0.029, bz), Vector3(0.019, 0.0042, 0.006), 5, 8, Basis(Vector3.BACK, sg * -0.12))

	_hair(g, st, hp)
	_beard(g, st, hp)
	_headwear(g, glow, st, hp, false)
	return info


static func _glow(glow: Dictionary, key: String) -> CharGeo:
	if not glow.has(key):
		glow[key] = CharGeo.new()
	return glow[key]


# --- Hair and beards -----------------------------------------------------------------

static func _hair(g: CharGeo, st: Dictionary, hp: Dictionary) -> void:
	var style := str(st.get("hair_style", "short" if st.get("hair", null) != null else "none"))
	if style == "none" or style == "bald":
		return
	var hv: Variant = st.get("helmet", false)
	var covered: bool = bool(st.get("hood", false)) or (hv is String and hv != "") or (hv is bool and hv)
	var c: Vector3 = hp["c"]
	var r: Vector3 = hp["r"]
	var vol := 1.08 if style != "wild" else 1.14
	var t0 := g.tri_count()
	var v0 := g.vertex_count()
	g.mat(CharGeo.HAIR, CharGeo.M_HAIR)
	g.bone(R.HEAD)
	var wild := style == "wild"
	g.ellipsoid(c + Vector3(0, 0.006, 0.004), r * Vector3(vol, vol * 0.98, vol), 18, 28, Basis.IDENTITY, 2.0,
		func(d: Vector3, p: Vector3) -> Vector3:
			var q := deform(d, p, hp)
			if wild:
				q *= 1.0 + 0.06 * sin(d.x * 23.0) * sin(d.z * 19.0 + d.y * 7.0)
			return q)
	var hairline := 0.035 if style != "receding" else 0.06
	g.clip_tris(t0, func(p: Vector3) -> bool:
		var l := p - c
		var back := clampf((l.z / r.z + 1.0) * 0.5, 0.0, 1.0)
		var line := lerpf(hairline, -0.075 if style in ["long", "wild"] else -0.055, smoothstep(0.25, 0.85, back))
		if absf(l.x) > r.x * 0.8 and l.z < 0.01:
			line = maxf(line, -0.005)  # sideburns stop above the ears
		return l.y > line)
	if covered:
		return
	if style == "long" or style == "wild":
		# Hair falling to the shoulders behind the head.
		var rows := 6
		var cols := 7
		var grid := PackedVector3Array()
		for i in rows:
			var v := float(i) / (rows - 1)
			for j in cols:
				var u := float(j) / (cols - 1) * 2.0 - 1.0
				var y := lerpf(c.y + 0.02, 1.4 if style == "long" else 1.46, v)
				var w := lerpf(r.x * 1.0, r.x * 1.25, v)
				var z := c.z + lerpf(r.z * 0.9, 0.11, v) * cos(u * 1.1) + 0.01
				grid.append(Vector3(u * w, y, z))
		g.sheet(grid, rows, cols, 0.022, Vector3.BACK, func(row: int, _col: int) -> Array:
			var f := float(row) / (rows - 1)
			return [[R.HEAD, R.NECK, R.CHEST], [1.0 - f, f * 0.4, f * 0.6]], Callable(), 0.7)
	elif style == "bun":
		g.ellipsoid(c + Vector3(0, r.y * 0.55, r.z * 0.85), Vector3(0.04, 0.035, 0.04), 8, 12)
	elif style == "ponytail":
		g.tube(PackedVector3Array([c + Vector3(0, r.y * 0.3, r.z * 0.95), c + Vector3(0, r.y * -0.2, r.z * 1.25), c + Vector3(0, -0.2, r.z * 1.2)]),
			[Vector4(0.022, 0.022, 0.022, 2.0), Vector4(0.026, 0.026, 0.026, 2.0), Vector4(0.012, 0.012, 0.012, 2.0)], 8,
			[Vector3(R.HEAD, R.HEAD, 0.0), Vector3(R.HEAD, R.NECK, 0.3), Vector3(R.HEAD, R.CHEST, 0.6)], 1, 2)
	elif style == "topknot":
		g.ellipsoid(c + Vector3(0, r.y * 1.02, 0.01), Vector3(0.03, 0.04, 0.03), 8, 10)
	var _u := v0


static func _beard(g: CharGeo, st: Dictionary, hp: Dictionary) -> void:
	var b: Variant = st.get("beard", false)
	var style := ""
	if b is bool:
		style = "full" if b else ""
	else:
		style = str(b)
	if style == "" or style == "none":
		return
	var c: Vector3 = hp["c"]
	var r: Vector3 = hp["r"]
	g.mat(CharGeo.HAIR, CharGeo.M_HAIR, 0.95)
	if style in ["full", "long", "goatee"]:
		var t0 := g.tri_count()
		var v0 := g.vertex_count()
		g.ellipsoid(c + Vector3(0, -0.004, -0.004), r * Vector3(1.1, 1.06, 1.12), 18, 26, Basis.IDENTITY, 2.0, func(d: Vector3, p: Vector3) -> Vector3: return deform(d, p, hp))
		var goatee := style == "goatee"
		g.clip_tris(t0, func(p: Vector3) -> bool:
			var l := p - c
			if l.z > 0.035:
				return false
			if goatee and absf(l.x) > 0.03:
				return false
			var mouth := absf(l.x) < 0.024 and l.y > -0.072 and l.y < -0.046 and l.z < -0.04
			return l.y < (-0.03 if absf(l.x) < r.x * 0.75 else 0.005) and not mouth)
		g.reweight(v0, g.vertex_count(), func(p: Vector3) -> Variant:
			var l := p - c
			var f := smoothstep(-0.04, -0.09, l.y)
			return [[R.HEAD, R.JAW], [1.0 - f * 0.8, f * 0.8]])
	if style == "long":
		var bz := face_z(hp, 0.0, -0.1)
		g.tube(PackedVector3Array([c + Vector3(0, -0.07, bz + 0.03), c + Vector3(0, -0.13, bz + 0.0), c + Vector3(0, -0.22, bz + 0.005), c + Vector3(0, -0.3, bz + 0.03)]),
			[Vector4(0.06, 0.03, 0.03, 2.2), Vector4(0.055, 0.03, 0.03, 2.2), Vector4(0.04, 0.022, 0.022, 2.2), Vector4(0.015, 0.01, 0.01, 2.0)], 12,
			[Vector3(R.JAW, R.HEAD, 0.2), Vector3(R.JAW, R.NECK, 0.2), Vector3(R.JAW, R.CHEST, 0.5), Vector3(R.JAW, R.CHEST, 0.7)], 0, 2)
	if style in ["full", "long", "mustache"]:
		var mz := face_z(hp, 0.0, -0.045)
		g.bone(R.HEAD)
		g.tube(PackedVector3Array([c + Vector3(-0.03, -0.058, mz + 0.012), c + Vector3(-0.012, -0.046, mz - 0.006), c + Vector3(0.012, -0.046, mz - 0.006), c + Vector3(0.03, -0.058, mz + 0.012)]),
			[Vector4(0.004, 0.004, 0.004, 2.0), Vector4(0.007, 0.006, 0.005, 2.0), Vector4(0.007, 0.006, 0.005, 2.0), Vector4(0.004, 0.004, 0.004, 2.0)], 6, [], 1, 1, Vector3.UP)


# --- Headwear ------------------------------------------------------------------------

static func _headwear(g: CharGeo, glow: Dictionary, st: Dictionary, hp: Dictionary, skeleton: bool) -> void:
	var c: Vector3 = hp["c"]
	var r: Vector3 = hp["r"]
	if st.get("hood", false):
		_hood(g, st, hp)
	var helmet: Variant = st.get("helmet", false)
	if helmet is bool and helmet:
		helmet = "nasal" if not skeleton else "kettle"
	if helmet is String and helmet != "":
		_helmet(g, str(helmet), st, hp)
	var hat: Variant = st.get("hat", false)
	if hat is bool and hat:
		hat = "wide"
	if hat is String and hat != "":
		_hat(g, str(hat), hp)
	if st.get("horns", false):
		var style := str(st.get("horn_style", "bull"))
		g.mat(CharGeo.FIXED, CharGeo.M_HORN)
		g.bone(R.HEAD)
		for sg: float in [-1.0, 1.0]:
			var base := c + Vector3(sg * r.x * 0.75, r.y * 0.6, 0.0)
			var pts := PackedVector3Array()
			var rings: Array = []
			var n := 7
			for i in n:
				var f := float(i) / (n - 1)
				var p: Vector3
				if style == "ram":
					var a := f * 4.4
					p = base + Vector3(sg * (0.03 + 0.06 * f), -0.03 * f, 0.0) + Vector3(0, sin(a) * 0.07 * (0.5 + f), cos(a) * 0.07 * (0.5 + f) - 0.07)
				else:
					p = base + Vector3(sg * (0.13 * f), 0.05 * f + 0.17 * f * f, -0.06 * f * f)
				pts.append(p)
				var rad := lerpf(0.034, 0.004, f)
				rings.append(Vector4(rad, rad, rad, 2.0))
			g.tube(pts, rings, 10, [], 1, 1, Vector3.FORWARD)
	if st.get("tusks", false):
		g.mat(CharGeo.FIXED, CharGeo.M_IVORY)
		g.bone2(R.JAW, R.HEAD, 0.1)
		for sg: float in [-1.0, 1.0]:
			var tz := face_z(hp, 0.03, -0.07)
			var b0 := c + Vector3(sg * 0.03, -0.07, tz + 0.01)
			g.tube(PackedVector3Array([b0, b0 + Vector3(sg * 0.008, 0.035, -0.015), b0 + Vector3(sg * 0.012, 0.06, -0.012)]),
				[Vector4(0.011, 0.011, 0.011, 2.0), Vector4(0.008, 0.008, 0.008, 2.0), Vector4(0.003, 0.003, 0.003, 2.0)], 8, [], 1, 1, Vector3.FORWARD)
	var crown: Variant = st.get("crown", null)
	if crown != null:
		var cg := _glow(glow, "crown")
		cg.mat(CharGeo.FIXED, CharGeo.M_DARK)
		cg.bone(R.HEAD)
		var cy := c.y + r.y * 0.62
		var cr := Vector3(r.x * 1.12, 0.0, r.z * 1.12)
		var band := PackedVector3Array()
		var band_r: Array = []
		var n := 24
		for i in n + 1:
			var a := TAU * float(i) / n
			band.append(Vector3(c.x + cos(a) * cr.x, cy, c.z + sin(a) * cr.z))
			band_r.append(Vector4(0.012, 0.006, 0.006, 2.0))
		cg.tube(band, band_r, 6, [], 0, 0, Vector3.UP)
		for i in 9:
			var a := TAU * float(i) / 9.0
			var b0 := Vector3(c.x + cos(a) * cr.x, cy, c.z + sin(a) * cr.z)
			var h := 0.07 if i % 2 == 0 else 0.045
			var out := Vector3(cos(a), 0, sin(a)) * 0.012
			cg.tube(PackedVector3Array([b0, b0 + Vector3(0, h * 0.6, 0) + out, b0 + Vector3(0, h, 0) + out * 1.4]),
				[Vector4(0.011, 0.011, 0.011, 2.0), Vector4(0.007, 0.007, 0.007, 2.0), Vector4(0.002, 0.002, 0.002, 2.0)], 5, [], 0, 1, Vector3.FORWARD)


static func _hood(g: CharGeo, st: Dictionary, hp: Dictionary) -> void:
	var c: Vector3 = hp["c"]
	var r: Vector3 = hp["r"]
	var slot := CharGeo.CLOAK if st.get("cloak", false) else CharGeo.CLOTH
	var hc := c + Vector3(0, 0.012, 0.014)
	var hr := Vector3(r.x + 0.042, r.y + 0.035, r.z + 0.04)
	var opening := func(p: Vector3) -> bool:
		var l := p - hc
		if l.y < -hr.y * 0.78:
			return false
		var ox := l.x / (r.x * 0.98)
		var oy := (l.y + 0.012) / (r.y * 0.86)
		return not (l.z < -0.01 and ox * ox + oy * oy < 1.0)
	var shape := func(d: Vector3, p: Vector3) -> Vector3:
		var q := p
		# Peak at the back of the crown, loose fabric at the nape.
		var peak := maxf(0.0, d.y) * maxf(0.0, d.z)
		q += Vector3(0, 0.03, 0.06) * peak * peak * 2.0
		if d.y < -0.2 and d.z > -0.2:
			q.z += 0.02 * (-d.y)
		if d.z < -0.6:
			q.z -= 0.012
		return q
	for layer in 2:
		var t0 := g.tri_count()
		var v0 := g.vertex_count()
		var k := 1.0 if layer == 0 else 0.9
		g.mat(slot, CharGeo.M_CLOTH, 1.0 if layer == 0 else 0.45, 1.0 if layer == 0 else 0.35)
		g.ellipsoid(hc, hr * k, 18, 28, Basis.IDENTITY, 2.0, shape)
		g.clip_tris(t0, opening)
		if layer == 1:
			g.flip_tris(t0)
		g.reweight(v0, g.vertex_count(), func(p: Vector3) -> Variant:
			var f := smoothstep(-0.02, -0.12, p.y - hc.y)
			return [[R.HEAD, R.NECK], [1.0 - f * 0.6, f * 0.6]])
		# Darken the inside lip of the opening so the face sits in shadow.
		g.reshade(v0, g.vertex_count(), func(p: Vector3) -> Variant:
			var l := p - hc
			if l.z > -0.02:
				return null
			return Vector2(1.0 if layer == 0 else 0.6, 0.55 if layer == 0 else 0.2))
	# Mantle over the shoulders.
	var b: float = float(st.get("bulk", 1.0))
	g.mat(slot, CharGeo.M_CLOTH, 0.95)
	g.tube(PackedVector3Array([Vector3(0, 1.6, 0.02), Vector3(0, 1.53, 0.012), Vector3(0, 1.45, 0.008), Vector3(0, 1.33, 0.012)]),
		[Vector4(0.09, 0.075, 0.085, 2.0), Vector4(0.13 * b, 0.095, 0.11, 2.0), Vector4(0.24 * b, 0.15, 0.15, 2.3), Vector4(0.27 * b, 0.165, 0.165, 2.3)], 28,
		[Vector3(R.NECK, R.CHEST, 0.5), Vector3(R.CHEST, R.NECK, 0.2), Vector3(R.CHEST, R.CHEST, 0.0), Vector3(R.CHEST, R.SPINE, 0.1)], 0, 0)
	var t1 := g.tri_count()
	g.mat(slot, CharGeo.M_CLOTH, 0.4, 0.3)
	g.tube(PackedVector3Array([Vector3(0, 1.53, 0.012), Vector3(0, 1.45, 0.008), Vector3(0, 1.335, 0.012)]),
		[Vector4(0.12 * b, 0.085, 0.1, 2.0), Vector4(0.23 * b, 0.14, 0.14, 2.3), Vector4(0.26 * b, 0.155, 0.155, 2.3)], 28,
		[Vector3(R.CHEST, R.NECK, 0.2), Vector3(R.CHEST, R.CHEST, 0.0), Vector3(R.CHEST, R.SPINE, 0.1)], 0, 0)
	g.flip_tris(t1)


static func _helmet(g: CharGeo, kind: String, st: Dictionary, hp: Dictionary) -> void:
	var c: Vector3 = hp["c"]
	var r: Vector3 = hp["r"]
	g.mat(CharGeo.METAL, CharGeo.M_METAL)
	g.bone(R.HEAD)
	var hc := c + Vector3(0, 0.02, 0.004)
	var hr := r + Vector3(0.016, 0.006, 0.016)
	if kind == "great":
		# Closed bucket helm with an eye slit and breaths.
		var t0 := g.tri_count()
		g.tube(PackedVector3Array([c + Vector3(0, -0.12, 0.0), c + Vector3(0, 0.0, 0.0), c + Vector3(0, 0.07, 0.0), c + Vector3(0, 0.11, 0.0)]),
			[Vector4(hr.x * 1.05, hr.z * 1.0, hr.z * 0.98, 2.4), Vector4(hr.x * 1.05, hr.z * 1.04, hr.z, 2.4), Vector4(hr.x, hr.z, hr.z, 2.2), Vector4(hr.x * 0.8, hr.z * 0.8, hr.z * 0.8, 2.0)], 24, [], 0, 2)
		var _u := t0
		g.mat(CharGeo.FIXED, CharGeo.M_DARK)
		g.ellipsoid(c + Vector3(0, 0.012, -hr.z * 1.04 + 0.002), Vector3(0.065, 0.006, 0.006), 4, 10, Basis.IDENTITY, 4.0)
		g.mat(CharGeo.METAL, CharGeo.M_METAL, 0.9)
		g.ellipsoid(c + Vector3(0, -0.02, -hr.z * 1.05), Vector3(0.006, 0.07, 0.008), 4, 8)
		return
	# Dome.
	var t1 := g.tri_count()
	g.ellipsoid(hc, hr, 16, 28, Basis.IDENTITY, 2.0, func(d: Vector3, p: Vector3) -> Vector3:
		var q := p
		if kind == "spangen" or kind == "horned":
			q.y += 0.025 * maxf(0.0, d.y) * maxf(0.0, d.y)
		return q)
	g.clip_tris(t1, func(p: Vector3) -> bool:
		var l := p - hc
		var line := 0.0 if l.z < -0.02 else -0.045
		if kind == "kettle" or kind == "skull":
			line = 0.005
		return l.y > line)
	var t2 := g.tri_count()
	g.mat(CharGeo.METAL, CharGeo.M_METAL, 0.5, 0.3)
	g.ellipsoid(hc, hr * 0.96, 16, 28)
	g.clip_tris(t2, func(p: Vector3) -> bool:
		var l := p - hc
		return l.y > (0.0 if l.z < -0.02 else -0.045))
	g.flip_tris(t2)
	g.mat(CharGeo.METAL, CharGeo.M_METAL, 0.85)
	# Rim band.
	var band := PackedVector3Array()
	var rings: Array = []
	for i in 29:
		var a := TAU * float(i) / 28.0
		var y := 0.003 if sin(a) < -0.3 else -0.03
		if kind == "kettle":
			y = 0.008
		band.append(hc + Vector3(cos(a) * hr.x * 1.02, y + 0.004, sin(a) * hr.z * 1.02))
		rings.append(Vector4(0.007, 0.004, 0.004, 2.0))
	g.tube(band, rings, 6, [], 0, 0, Vector3.UP)
	if kind == "nasal" or kind == "horned" or kind == "spangen":
		var fz := face_z(hp, 0.0, 0.0) - 0.012
		g.tube(PackedVector3Array([hc + Vector3(0, 0.0, fz - 0.002), c + Vector3(0, -0.035, fz + 0.002)]),
			[Vector4(0.009, 0.004, 0.004, 3.0), Vector4(0.008, 0.004, 0.004, 3.0)], 6, [], 1, 1, Vector3.RIGHT)
		# Riveted crest.
		g.tube(PackedVector3Array([hc + Vector3(0, hr.y * 0.2, -hr.z * 1.0), hc + Vector3(0, hr.y * 1.0, -0.02), hc + Vector3(0, hr.y * 0.75, hr.z * 0.85)]),
			[Vector4(0.006, 0.004, 0.004, 2.0), Vector4(0.007, 0.005, 0.005, 2.0), Vector4(0.006, 0.004, 0.004, 2.0)], 6, [], 0, 0, Vector3.RIGHT)
	if kind == "kettle":
		g.ellipsoid(hc + Vector3(0, 0.006, 0), Vector3(hr.x * 1.75, 0.006, hr.z * 1.75), 4, 28)
	if kind == "horned" and not st.get("horns", false):
		g.mat(CharGeo.FIXED, CharGeo.M_HORN)
		for sg: float in [-1.0, 1.0]:
			var base := hc + Vector3(sg * hr.x * 0.85, hr.y * 0.25, 0.0)
			g.tube(PackedVector3Array([base, base + Vector3(sg * 0.07, 0.04, -0.01), base + Vector3(sg * 0.1, 0.12, -0.03)]),
				[Vector4(0.024, 0.024, 0.024, 2.0), Vector4(0.015, 0.015, 0.015, 2.0), Vector4(0.003, 0.003, 0.003, 2.0)], 8, [], 1, 1, Vector3.FORWARD)
	if st.get("plume", false):
		g.mat(CharGeo.CLOTH2, CharGeo.M_WOOL)
		g.tube(PackedVector3Array([hc + Vector3(0, hr.y, -0.03), hc + Vector3(0, hr.y + 0.05, 0.03), hc + Vector3(0, hr.y * 0.6, hr.z + 0.08), hc + Vector3(0, hr.y * -0.2, hr.z + 0.1)]),
			[Vector4(0.012, 0.03, 0.03, 2.0), Vector4(0.014, 0.04, 0.04, 2.0), Vector4(0.012, 0.03, 0.03, 2.0), Vector4(0.004, 0.01, 0.01, 2.0)], 8, [], 1, 1, Vector3.RIGHT)


static func _hat(g: CharGeo, kind: String, hp: Dictionary) -> void:
	var c: Vector3 = hp["c"]
	var r: Vector3 = hp["r"]
	g.bone(R.HEAD)
	var top := c + Vector3(0, r.y * 0.62, 0.004)
	match kind:
		"cap":
			g.mat(CharGeo.CLOTH2, CharGeo.M_WOOL)
			var t0 := g.tri_count()
			g.ellipsoid(c + Vector3(0, 0.03, 0.012), r * Vector3(1.12, 0.9, 1.15), 14, 24)
			g.clip_tris(t0, func(p: Vector3) -> bool: return p.y - c.y > 0.035 - maxf(0.0, p.z - c.z) * 0.4)
		"pointed":
			g.mat(CharGeo.CLOTH2, CharGeo.M_CLOTH)
			g.tube(PackedVector3Array([top - Vector3(0, 0.03, 0), top + Vector3(0, 0.08, 0.01), top + Vector3(0, 0.2, 0.06), top + Vector3(0, 0.27, 0.14)]),
				[Vector4(r.x * 1.12, r.z * 1.12, r.z * 1.12, 2.0), Vector4(0.06, 0.06, 0.06, 2.0), Vector4(0.03, 0.03, 0.03, 2.0), Vector4(0.006, 0.006, 0.006, 2.0)], 18, [], 0, 1)
			g.ellipsoid(top - Vector3(0, 0.02, 0), Vector3(0.2, 0.008, 0.2), 4, 28)
		_:
			# Wide-brimmed felt or straw hat.
			g.mat(CharGeo.CLOTH2, CharGeo.M_WOOL)
			g.tube(PackedVector3Array([top - Vector3(0, 0.03, 0), top + Vector3(0, 0.04, 0), top + Vector3(0, 0.085, 0)]),
				[Vector4(r.x * 1.08, r.z * 1.08, r.z * 1.08, 2.0), Vector4(r.x * 1.0, r.z * 1.0, r.z, 2.3), Vector4(r.x * 0.9, r.z * 0.85, r.z * 0.9, 2.3)], 20, [], 0, 2)
			g.ellipsoid(top - Vector3(0, 0.012, 0), Vector3(0.2, 0.01, 0.21), 4, 28, Basis.IDENTITY, 2.0,
				func(d: Vector3, p: Vector3) -> Vector3: return p + Vector3(0, -0.02 * (d.x * d.x + d.z * d.z), 0))
