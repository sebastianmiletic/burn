class_name CharBones
extends RefCounted
## Anatomical skeleton for undead styles: skull with sockets, nasal cavity,
## teeth and a hinged mandible; vertebrae; ribcage with sternum and clavicles;
## scapulae; pelvis; knobbly long bones (paired in the forearm and shin);
## finger and foot bones. Everything is rigidly skinned to the rig.

const R := preload("res://models/character/char_rig.gd")


static func _bone_seg(g: CharGeo, a: Vector3, b: Vector3, r_end: float, r_mid: float, bone_a: int, bone_b := -1, sides := 8) -> void:
	# A long bone: knobbed ends, slender shaft.
	var d := b - a
	var pts := PackedVector3Array([a, a + d * 0.1, a + d * 0.3, a + d * 0.7, a + d * 0.9, b])
	var rings: Array = [Vector4(r_end, r_end, r_end, 2.0), Vector4(r_end * 0.85, r_end * 0.8, r_end * 0.8, 2.0),
		Vector4(r_mid, r_mid, r_mid, 2.0), Vector4(r_mid, r_mid, r_mid, 2.0), Vector4(r_end * 0.8, r_end * 0.8, r_end * 0.8, 2.0),
		Vector4(r_end * 0.95, r_end * 0.9, r_end * 0.9, 2.0)]
	var ws: Array = []
	if bone_b >= 0:
		for i in 6:
			ws.append(Vector3(bone_a, bone_b, 0.0 if i < 5 else 0.3))
	else:
		g.bone(bone_a)
	g.tube(pts, rings, sides, ws, 2, 2)


static func skull(g: CharGeo, glow: Dictionary, st: Dictionary, hp: Dictionary) -> void:
	var c: Vector3 = hp["c"] + Vector3(0, 0.008, 0)
	var r: Vector3 = hp["r"] * Vector3(0.98, 0.88, 1.02)
	g.mat(CharGeo.SKIN, CharGeo.M_BONE)
	g.bone(R.HEAD)
	# Cranium + upper face.
	var v0 := g.vertex_count()
	g.ellipsoid(c + Vector3(0, 0.012, 0.006), r, 20, 28, Basis.IDENTITY, 2.0, func(d: Vector3, p: Vector3) -> Vector3:
		var q := p
		if d.y < 0.0:
			q.x *= lerpf(1.0, 0.72, -d.y)
			if q.z > 0.0:
				q.z *= lerpf(1.0, 0.6, -d.y)
		if d.z < -0.4:
			q.z *= 0.9
		# Temples pinch in.
		q.x *= 1.0 - 0.08 * exp(-pow((d.y - 0.05) / 0.25, 2.0)) * smoothstep(-0.2, -0.8, d.z)
		return q)
	# Cheekbones / zygomatic arches.
	for sg: float in [-1.0, 1.0]:
		g.tube(PackedVector3Array([c + Vector3(sg * 0.035, -0.03, -r.z * 0.8), c + Vector3(sg * 0.062, -0.025, -r.z * 0.45), c + Vector3(sg * 0.07, -0.02, -0.01)]),
			[Vector4(0.012, 0.008, 0.008, 2.0), Vector4(0.008, 0.006, 0.006, 2.0), Vector4(0.006, 0.005, 0.005, 2.0)], 6, [], 1, 1)
	# Eye sockets and nasal cavity (dark, slightly inset).
	g.mat(CharGeo.FIXED, CharGeo.M_DARK)
	var fz := -r.z * 0.86 + c.z
	for sg: float in [-1.0, 1.0]:
		g.ellipsoid(Vector3(c.x + sg * 0.03, c.y + 0.0, fz + 0.008), Vector3(0.019, 0.017, 0.014), 8, 12)
	g.ellipsoid(Vector3(c.x, c.y - 0.034, fz + 0.004), Vector3(0.009, 0.014, 0.01), 6, 8, Basis(Vector3.RIGHT, -0.2))
	var eye_glow: Variant = st.get("eyes", null)
	if eye_glow != null:
		if not glow.has("eyes"):
			glow["eyes"] = CharGeo.new()
		var eg: CharGeo = glow["eyes"]
		eg.bone(R.HEAD)
		eg.mat(CharGeo.FIXED, CharGeo.M_DARK)
		for sg: float in [-1.0, 1.0]:
			eg.ellipsoid(Vector3(c.x + sg * 0.03, c.y + 0.0, fz + 0.004), Vector3(0.0065, 0.0065, 0.004), 6, 8)
	# Upper teeth.
	g.mat(CharGeo.FIXED, CharGeo.M_IVORY)
	for i in 8:
		var a := lerpf(-0.75, 0.75, float(i) / 7.0)
		var p := c + Vector3(sin(a) * 0.033, -0.06, -cos(a) * r.z * 0.72)
		g.ellipsoid(p, Vector3(0.0052, 0.008, 0.004), 4, 6, Basis(Vector3.UP, -a))
	# Mandible: U-shaped jaw on its own bone, with lower teeth.
	g.mat(CharGeo.SKIN, CharGeo.M_BONE)
	g.bone(R.JAW)
	var jaw := PackedVector3Array()
	var jr: Array = []
	for i in 9:
		var f := float(i) / 8.0
		var a := lerpf(-1.25, 1.25, f)
		var y := -0.085 + 0.045 * pow(absf(a) / 1.25, 3.0)
		jaw.append(c + Vector3(sin(a) * 0.05, y, -cos(a) * r.z * 0.68 + 0.025))
		jr.append(Vector4(0.007, 0.012, 0.012, 2.0))
	g.tube(jaw, jr, 8, [], 1, 1, Vector3.UP)
	g.mat(CharGeo.FIXED, CharGeo.M_IVORY)
	for i in 7:
		var a := lerpf(-0.65, 0.65, float(i) / 6.0)
		g.ellipsoid(c + Vector3(sin(a) * 0.031, -0.072, -cos(a) * r.z * 0.68 + 0.004), Vector3(0.0048, 0.0065, 0.0038), 4, 6, Basis(Vector3.UP, -a))
	var _u := v0


static func body(g: CharGeo, st: Dictionary, pr: Dictionary, rest: PackedVector3Array) -> void:
	var b: float = pr["bulk"]
	g.mat(CharGeo.SKIN, CharGeo.M_BONE)
	# Spine: vertebrae from the sacrum to the skull.
	var n := 16
	for i in n:
		var f := float(i) / (n - 1)
		var y := lerpf(0.98, 1.6, f)
		var z := 0.045 - 0.02 * sin(f * PI) + 0.01 * f
		var bone := R.HIPS
		var bone2 := R.SPINE
		var bf := 0.0
		if y > 1.5:
			bone = R.NECK
			bone2 = R.HEAD
			bf = smoothstep(1.55, 1.62, y)
		elif y > 1.27:
			bone = R.CHEST
			bone2 = R.NECK
			bf = smoothstep(1.45, 1.5, y)
		elif y > 1.09:
			bone = R.SPINE
			bone2 = R.CHEST
			bf = smoothstep(1.2, 1.27, y)
		else:
			bf = smoothstep(1.03, 1.09, y)
		g.bone2(bone, bone2, bf)
		var s := lerpf(1.25, 0.75, f)
		g.ellipsoid(Vector3(0, y, z), Vector3(0.022, 0.014, 0.02) * s, 5, 8)
		g.ellipsoid(Vector3(0, y - 0.004, z + 0.022 * s), Vector3(0.006, 0.01, 0.014) * s, 4, 6)
	# Ribcage.
	g.bone(R.CHEST)
	for i in 7:
		var y := 1.43 - i * 0.045
		var w := (0.1 + 0.035 * sin(float(i + 1) / 7.0 * PI)) * b
		var d := 0.085 + 0.012 * sin(float(i + 1) / 7.0 * PI)
		var drop := 0.05 + i * 0.006
		for sg: float in [-1.0, 1.0]:
			var pts := PackedVector3Array()
			var rings: Array = []
			var m := 7
			for k in m:
				var a := lerpf(0.0, PI * (0.92 if i < 5 else 0.75), float(k) / (m - 1))
				pts.append(Vector3(sg * sin(a) * w, y - drop * (1.0 - cos(a * 0.5)) * 1.2, cos(a) * d * 0.6 + 0.04 - a * 0.012))
				rings.append(Vector4(0.0075, 0.0045, 0.0045, 2.0))
			g.tube(pts, rings, 5, [], 1, 1, Vector3.UP)
	# Sternum.
	g.ellipsoid(Vector3(0, 1.36, -0.085), Vector3(0.016, 0.09, 0.008), 6, 8)
	# Clavicles and scapulae.
	for sg: float in [-1.0, 1.0]:
		var o := 0 if sg < 0.0 else 5
		g.bone2(R.CHEST, R.CLAV_L + o, 0.6)
		g.tube(PackedVector3Array([Vector3(sg * 0.02, 1.445, -0.07), Vector3(sg * 0.09, 1.46, -0.05), rest[R.UARM_L + o] + Vector3(-sg * 0.01, 0.025, -0.01)]),
			[Vector4(0.008, 0.007, 0.007, 2.0), Vector4(0.007, 0.006, 0.006, 2.0), Vector4(0.01, 0.009, 0.009, 2.0)], 6, [], 1, 1, Vector3.UP)
		g.bone2(R.CHEST, R.CLAV_L + o, 0.4)
		g.ellipsoid(Vector3(sg * 0.1 * b, 1.37, 0.085), Vector3(0.05, 0.07, 0.008), 6, 10, Basis(Vector3.UP, sg * 0.4))
	# Pelvis: iliac wings, sacrum, pubic arch.
	g.bone(R.HIPS)
	for sg: float in [-1.0, 1.0]:
		g.ellipsoid(Vector3(sg * 0.085 * b, 1.0, 0.01), Vector3(0.06, 0.055, 0.01), 8, 12, Basis(Vector3.UP, sg * 0.9) * Basis(Vector3.BACK, sg * 0.35))
		g.tube(PackedVector3Array([Vector3(sg * 0.1 * b, 0.95, 0.0), Vector3(sg * 0.07, 0.9, -0.04), Vector3(sg * 0.01, 0.9, -0.06)]),
			[Vector4(0.014, 0.012, 0.012, 2.0), Vector4(0.011, 0.01, 0.01, 2.0), Vector4(0.012, 0.012, 0.012, 2.0)], 6, [], 1, 1, Vector3.UP)
		# Hip socket ball.
		g.ellipsoid(rest[R.THIGH_L + (0 if sg < 0.0 else 4)], Vector3(0.022, 0.022, 0.022), 6, 8)
	g.ellipsoid(Vector3(0, 0.97, 0.05), Vector3(0.035, 0.05, 0.015), 6, 8, Basis(Vector3.RIGHT, 0.3))
	# Limbs.
	for side in 2:
		var sg := -1.0 if side == 0 else 1.0
		var a := 0 if side == 0 else 5
		var l := 0 if side == 0 else 4
		var lm := float(pr["limb"]) * 1.25
		_bone_seg(g, rest[R.UARM_L + a] + Vector3(0, 0.01, 0), rest[R.FARM_L + a], 0.022 * lm, 0.011 * lm, R.UARM_L + a)
		var e := rest[R.FARM_L + a]
		var w := rest[R.HAND_L + a]
		_bone_seg(g, e + Vector3(sg * 0.008, 0, 0.008), w + Vector3(sg * 0.012, 0, 0.004), 0.013 * lm, 0.007 * lm, R.FARM_L + a)
		_bone_seg(g, e + Vector3(-sg * 0.006, -0.01, -0.006), w + Vector3(-sg * 0.002, 0, -0.008), 0.011 * lm, 0.0065 * lm, R.FARM_L + a)
		# Hand: carpals, metacarpals and phalanges.
		g.bone(R.HAND_L + a)
		g.ellipsoid(w + Vector3(0, -0.018, 0), Vector3(0.012, 0.014, 0.022), 5, 8)
		for f in 4:
			var z := lerpf(-0.022, 0.022, f / 3.0)
			var base := w + Vector3(sg * 0.002, -0.03, z)
			g.bone(R.HAND_L + a)
			g.tube(PackedVector3Array([base, base + Vector3(0, -0.05, 0)]), [Vector4(0.004, 0.004, 0.004, 2.0), Vector4(0.0045, 0.0045, 0.0045, 2.0)], 5, [], 1, 1)
			g.bone(R.FING_L + a)
			var fl := 0.045 + (0.008 if f in [1, 2] else 0.0)
			g.tube(PackedVector3Array([base + Vector3(0, -0.058, 0), base + Vector3(-sg * 0.004, -0.058 - fl * 0.5, 0), base + Vector3(-sg * 0.012, -0.058 - fl, 0)]),
				[Vector4(0.0042, 0.0042, 0.0042, 2.0), Vector4(0.0036, 0.0036, 0.0036, 2.0), Vector4(0.003, 0.003, 0.003, 2.0)], 5, [], 1, 1)
		g.bone(R.HAND_L + a)
		g.tube(PackedVector3Array([w + Vector3(-sg * 0.01, -0.02, -0.025), w + Vector3(-sg * 0.02, -0.05, -0.045), w + Vector3(-sg * 0.026, -0.075, -0.05)]),
			[Vector4(0.0048, 0.0048, 0.0048, 2.0), Vector4(0.0042, 0.0042, 0.0042, 2.0), Vector4(0.0035, 0.0035, 0.0035, 2.0)], 5, [], 1, 1)
		# Leg.
		_bone_seg(g, rest[R.THIGH_L + l] + Vector3(-sg * 0.01, 0.0, 0.0), rest[R.SHIN_L + l], 0.025 * lm, 0.013 * lm, R.THIGH_L + l)
		g.bone(R.SHIN_L + l)
		g.ellipsoid(rest[R.SHIN_L + l] + Vector3(0, 0.01, -0.03), Vector3(0.018, 0.022, 0.01), 5, 8)
		var k := rest[R.SHIN_L + l]
		var an := rest[R.FOOT_L + l]
		_bone_seg(g, k + Vector3(0, -0.012, 0), an + Vector3(0, 0.012, 0), 0.02 * lm, 0.011 * lm, R.SHIN_L + l)
		_bone_seg(g, k + Vector3(sg * 0.022, -0.03, 0.01), an + Vector3(sg * 0.022, 0.0, 0.01), 0.009 * lm, 0.005 * lm, R.SHIN_L + l)
		# Foot: heel, tarsals, metatarsals, toes.
		g.bone(R.FOOT_L + l)
		g.ellipsoid(an + Vector3(0, -0.035, 0.035), Vector3(0.02, 0.022, 0.03), 5, 8)
		g.ellipsoid(an + Vector3(0, -0.04, -0.02), Vector3(0.024, 0.014, 0.035), 5, 8)
		for t in 5:
			var x := lerpf(-0.022, 0.022, t / 4.0)
			g.bone(R.FOOT_L + l)
			g.tube(PackedVector3Array([an + Vector3(x, -0.045, -0.04), an + Vector3(x * 1.2, -0.06, -0.11)]), [Vector4(0.005, 0.005, 0.005, 2.0), Vector4(0.0045, 0.0045, 0.0045, 2.0)], 5, [], 1, 1)
			g.bone(R.TOE_L + l)
			g.tube(PackedVector3Array([an + Vector3(x * 1.2, -0.062, -0.12), an + Vector3(x * 1.25, -0.066, -0.16)]), [Vector4(0.0042, 0.0042, 0.0042, 2.0), Vector4(0.0036, 0.0036, 0.0036, 2.0)], 5, [], 1, 1)
	var _u := st
