class_name GolemModel
extends MobModel
## Deep-cave rock golem: a hunched, gorilla-built being of fitted, chiselled
## stone plates over a dark core whose glowing crystal veins (amethyst, ember
## or frost by variant) show in every seam. Faceted crystal clusters erupt
## from its back, shoulders and forearms; moss and lichen grow on the upper
## faces. Massive forearms end in knuckled block fists that hang by its
## knees; short pillar legs on broad feet; a small head sunk between the
## shoulders under a heavy brow with a burning eye slit.
##
## One skinned mesh (MobRig): the core is a set of skinned tubes, every plate
## a rigid chunk bound to its bone, so the whole golem draws in 5 calls.
## Motion: a grinding, weight-shifting gait with planted feet (IK), arms
## swinging from the shoulders; a two-fist overhead slam that lands at the
## end of the wind-up with dust, alternating punches, a roar that flares the
## veins, a jolting flinch, and a death in which it buckles to its knees and
## crumbles apart. Faces -Z.

const BASE := 2.6
## Fraction of a slam at which the fists land (entity windup / duration).
const SLAM_IMPACT := 0.76

const S_PLATE := 0
const S_CORE := 1
const S_CRYSTAL := 2
const S_MOSS := 3
const S_EYE := 4

const PELVIS := 0
const SPINE := 1
const CHEST := 2
const HEAD := 3
const JAW := 4
const SH_L := 5
const SH_R := 8
const HIP_L := 11
const HIP_R := 14

var size := 2.6
var vein := Color(0.75, 0.4, 1.0)

var _gait := 0.0
var _walk := 0.0
var _crouch := 0.0
var _lean := 0.0
var _flare := 0.0
var _impact_done := false
var _death_pose := false
var _dead_gb: Array[Basis] = []
var _dead_gp := PackedVector3Array()
var _scatter: Array[Vector3] = []
var _dust_done := false
var _light: OmniLight3D

static var _chunks := {}


func _init(variant_seed := 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = variant_seed
	size = rng.randf_range(2.4, 3.0)
	var veins := [Color(0.75, 0.4, 1.0), Color(1.0, 0.45, 0.12), Color(0.45, 0.85, 1.0)]
	vein = veins[rng.randi() % veins.size()]
	dissolve_delay = 2.6
	dissolve_time = 1.6
	durations["slam"] = 1.55
	durations["roar"] = 1.6
	durations["attack"] = 0.9
	durations["attack2"] = 0.9


func _ember_extents() -> Vector3:
	return Vector3(0.6, 1.0, 0.5) * size * 0.5


func _lod_size() -> float:
	return size * 1.2


# --- Stone ------------------------------------------------------------------------------

## A fractured stone chunk: a lumpy ellipsoid cut by `cuts` random planes into
## flat chiselled faces whose edges stay slightly rounded (worn, chipped).
## `flat_back` adds a cut on +Z so plates sit snugly on the body. Cached.
static func chunk(key: String, sz: Vector3, seed_value: int, cuts := 6, lumps := 0.14, flat_back := true) -> ArrayMesh:
	var ck := "%s|%s|%d|%d|%d" % [key, str(sz), seed_value, cuts, int(flat_back)]
	if _chunks.has(ck):
		return _chunks[ck]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.4
	noise.fractal_octaves = 3
	# Resolution by size: big plates keep round, worn edges; knuckles stay cheap.
	var big := maxf(sz.x, maxf(sz.y, sz.z))
	var seg := 12 if big > 0.25 else (10 if big > 0.12 else 8)
	var rings := 8 if big > 0.25 else (6 if big > 0.12 else 5)
	var verts := PackedVector3Array()
	var cut_n := PackedVector3Array()
	var dirs := PackedVector3Array()
	for i in rings + 1:
		var phi := PI * float(i) / rings
		for j in seg:
			var th := TAU * float(j) / seg
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var disp := 1.0 + noise.get_noise_3dv(d * 1.5) * lumps
			verts.append(Vector3(d.x * sz.x, d.y * sz.y, d.z * sz.z) * disp)
			cut_n.append(Vector3.ZERO)
			dirs.append(d)
	var planes: Array = []
	for c in cuts:
		var n := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.8, 1.0), rng.randf_range(-1.0, 0.6)).normalized()
		var support := Vector3(n.x * sz.x, n.y * sz.y, n.z * sz.z).length()
		planes.append([n, support * rng.randf_range(0.5, 0.8)])
	if flat_back:
		planes.append([Vector3.BACK, sz.z * 0.55])
	for pl: Array in planes:
		var n: Vector3 = pl[0]
		var off: float = pl[1]
		for i in verts.size():
			var over := verts[i].dot(n) - off
			if over > 0.0:
				verts[i] -= n * over
				cut_n[i] += n
	var ring := seg
	var idx := PackedInt32Array()
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in rings + 1:
		for j in seg:
			var a := i * ring + j
			if cut_n[a] != Vector3.ZERO:
				normals[a] = cut_n[a].normalized()
				continue
			var du := verts[i * ring + (j + 1) % seg] - verts[i * ring + (j - 1 + seg) % seg]
			var dv := verts[mini(rings, i + 1) * ring + j] - verts[maxi(0, i - 1) * ring + j]
			var nn := du.cross(dv)
			if nn.length_squared() < 1e-12 or i == 0 or i == rings:
				nn = dirs[a] / sz
			nn = nn.normalized()
			if nn.dot(dirs[a]) < 0.0:
				nn = -nn
			normals[a] = nn
	for i in rings:
		for j in seg:
			var a := i * ring + j
			var b := i * ring + (j + 1) % seg
			var c := (i + 1) * ring + (j + 1) % seg
			var d := (i + 1) * ring + j
			for t: Array in [[a, b, c], [a, c, d]]:
				var p0 := verts[t[0]]
				var f := (verts[t[1]] - p0).cross(verts[t[2]] - p0)
				if f.length_squared() < 1e-12:
					continue
				var nsum: Vector3 = normals[t[0]] + normals[t[1]] + normals[t[2]]
				if f.dot(nsum) > 0.0:
					idx.append_array([t[0], t[2], t[1]])
				else:
					idx.append_array([t[0], t[1], t[2]])
	var uvs := PackedVector2Array()
	for v in verts:
		uvs.append(Vector2(v.x + v.z, v.y))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_chunks[ck] = mesh
	return mesh


# --- Build -------------------------------------------------------------------------------

func _build() -> void:
	var stone := CreatureSkin.rock(Color(0.34, 0.32, 0.3), {"use_rest": true, "pattern_scale": 3.2, "bump": 1.5, "bump_distance": 40.0,
		"accent": Color(0.42, 0.45, 0.33), "accent_mode": 2, "accent_amount": 0.22, "accent_scale": 3.5, "rim": 0.12})
	var core := CreatureSkin.rock(Color(0.17, 0.16, 0.155), {"use_rest": true, "pattern_scale": 6.0, "bump": 1.6,
		"glow_mode": 2, "glow_color": vein, "glow_amount": 0.04, "glow_energy": 4.0, "glow_pulse": 0.6, "glow_sparsity": 0.8, "rim": 0.0})
	var crystal := CreatureSkin.smooth(vein.darkened(0.55), vein.darkened(0.3), {"use_rest": true, "roughness": 0.06, "specular_amount": 1.0,
		"rim": 2.2, "bump": 0.15, "glow_mode": 2, "glow_color": vein, "glow_amount": 0.7, "glow_energy": 2.6, "glow_pulse": 0.5,
		"pattern_scale": 2.5, "belly_mix": 0.0, "ascii_id": AsciiMaterialId.EMISSIVE})
	var moss := CreatureSkin.fur(Color(0.2, 0.27, 0.11), Color(0.15, 0.2, 0.09), {"use_rest": true, "pattern_scale": 40.0, "bump": 1.4,
		"accent": Color(0.32, 0.34, 0.14), "accent_mode": 2, "accent_amount": 0.5, "accent_scale": 6.0})
	var eye := ModelKit.glow(vein.lightened(0.45), 14.0, 0.25)
	rig_instance(_rig_data(), [stone, core, crystal, moss, eye], size / BASE, 0.9)
	_light = OmniLight3D.new()
	_light.light_color = vein
	_light.light_energy = 1.2
	_light.omni_range = 6.0 * size / BASE
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0.0, -0.45)
	follow(CHEST, "Glow").add_child(_light)


func _plate(r: MobRig, slot_i: int, sz: Vector3, pos: Vector3, rot_deg: Vector3, b: int, seed_value: int, cuts := 6, flat := true) -> void:
	r.slot(slot_i).rigid(chunk("golem", sz, seed_value, cuts, 0.14, flat), Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)), pos), b)


func _rig_data() -> Dictionary:
	if MobRig.has("golem"):
		return MobRig.cached("golem")
	var r := MobRig.new(5)
	r.bone("pelvis", -1, Vector3(0, 1.0, 0.1))
	r.bone("spine", PELVIS, Vector3(0, 1.32, 0.06))
	r.bone("chest", SPINE, Vector3(0, 1.7, -0.02))
	r.bone("head", CHEST, Vector3(0, 2.02, -0.56))
	r.bone("jaw", HEAD, Vector3(0, 1.96, -0.59))
	for side: float in [-1.0, 1.0]:
		var sfx := "_l" if side < 0.0 else "_r"
		var sh := r.bone("sh" + sfx, CHEST, Vector3(side * 0.82, 1.98, -0.05))
		r.bone("el" + sfx, sh, Vector3(side * 0.98, 1.28, -0.2))
		r.bone("fist" + sfx, sh + 1, Vector3(side * 1.0, 0.56, -0.3))
	for side: float in [-1.0, 1.0]:
		var sfx := "_l" if side < 0.0 else "_r"
		var hp := r.bone("hip" + sfx, PELVIS, Vector3(side * 0.36, 0.98, 0.12))
		r.bone("knee" + sfx, hp, Vector3(side * 0.42, 0.56, 0.02))
		r.bone("foot" + sfx, hp + 1, Vector3(side * 0.44, 0.15, 0.1))

	# --- The dark veined core under the plates.
	var rs := MobRig.resample(PackedVector3Array([Vector3(0, 0.82, 0.16), Vector3(0, 1.1, 0.1), Vector3(0, 1.4, 0.04), Vector3(0, 1.72, -0.02),
		Vector3(0, 1.95, -0.25), Vector3(0, 2.02, -0.42)]),
		PackedVector2Array([Vector2(0.3, 0.2), Vector2(0.4, 0.28), Vector2(0.44, 0.32), Vector2(0.62, 0.44), Vector2(0.32, 0.26), Vector2(0.16, 0.15)]),
		[PELVIS, PELVIS, SPINE, CHEST, CHEST, HEAD], 22)
	r.slot(S_CORE).tube(rs[0], rs[1], rs[2], 0.25, 14)
	for side: float in [-1.0, 1.0]:
		var sh := SH_L if side < 0.0 else SH_R
		var hp := HIP_L if side < 0.0 else HIP_R
		r.slot(S_CORE).limb(PackedVector3Array([r.rest[CHEST] + Vector3(side * 0.45, 0.2, 0), r.rest[sh], r.rest[sh + 1], r.rest[sh + 2]]),
			[CHEST, sh, sh + 1], [[0.0, 0.22, 0.22], [0.35, 0.2, 0.2], [0.6, 0.19, 0.2], [0.8, 0.22, 0.22], [1.0, 0.17, 0.17]], 14, 10, Vector3.BACK, 0.18)
		r.slot(S_CORE).limb(PackedVector3Array([r.rest[hp] + Vector3(0, 0.15, 0), r.rest[hp], r.rest[hp + 1], r.rest[hp + 2]]),
			[PELVIS, hp, hp + 1], [[0.0, 0.24, 0.24], [0.4, 0.22, 0.22], [0.7, 0.2, 0.2], [1.0, 0.19, 0.19]], 12, 10, Vector3.BACK, 0.15)

	# --- Plates of the torso.
	var sd := 10
	for side: float in [-1.0, 1.0]:
		var sx := side
		# Pectoral slabs and rib flanks.
		_plate(r, S_PLATE, Vector3(0.36, 0.3, 0.2), Vector3(sx * 0.3, 1.8, -0.38), Vector3(-8, sx * 18, sx * 6), CHEST, sd + int(side + 1.0))
		_plate(r, S_PLATE, Vector3(0.22, 0.32, 0.3), Vector3(sx * 0.58, 1.6, -0.06), Vector3(0, sx * 20, sx * -8), CHEST, sd + 3 + int(side + 1.0))
		# The hunched back and trapezius mass.
		_plate(r, S_PLATE, Vector3(0.36, 0.34, 0.3), Vector3(sx * 0.42, 1.82, 0.3), Vector3(20, sx * -15, sx * 10), CHEST, sd + 6 + int(side + 1.0))
		_plate(r, S_PLATE, Vector3(0.3, 0.2, 0.3), Vector3(sx * 0.46, 2.12, 0.02), Vector3(10, 0, sx * -18), CHEST, sd + 9 + int(side + 1.0), 5, false)
		# Flanks of the belly and the pelvis girdle.
		_plate(r, S_PLATE, Vector3(0.2, 0.22, 0.26), Vector3(sx * 0.38, 1.3, -0.02), Vector3(0, sx * 25, 0), SPINE, sd + 12 + int(side + 1.0))
		_plate(r, S_PLATE, Vector3(0.24, 0.22, 0.26), Vector3(sx * 0.36, 1.0, 0.1), Vector3(0, sx * 20, sx * 10), PELVIS, sd + 15 + int(side + 1.0))
	_plate(r, S_PLATE, Vector3(0.5, 0.16, 0.22), Vector3(0, 1.98, -0.1), Vector3(-20, 0, 0), CHEST, 31, 5)
	_plate(r, S_PLATE, Vector3(0.62, 0.42, 0.38), Vector3(0, 2.06, 0.22), Vector3(22, 0, 0), CHEST, 32, 7, false)
	_plate(r, S_PLATE, Vector3(0.34, 0.15, 0.18), Vector3(0, 1.44, -0.33), Vector3(-6, 0, 2), SPINE, 33)
	_plate(r, S_PLATE, Vector3(0.3, 0.14, 0.17), Vector3(0, 1.24, -0.3), Vector3(-2, 0, -3), SPINE, 34)
	_plate(r, S_PLATE, Vector3(0.44, 0.26, 0.24), Vector3(0, 1.38, 0.27), Vector3(10, 0, 0), SPINE, 35)
	_plate(r, S_PLATE, Vector3(0.48, 0.2, 0.3), Vector3(0, 1.0, -0.08), Vector3(0, 0, 0), PELVIS, 36)
	_plate(r, S_PLATE, Vector3(0.4, 0.22, 0.24), Vector3(0, 1.04, 0.3), Vector3(15, 0, 0), PELVIS, 37)

	# --- Head: a small cranium sunk under a heavy, overhanging brow.
	var hd: Vector3 = r.rest[HEAD]
	_plate(r, S_PLATE, Vector3(0.24, 0.21, 0.24), hd + Vector3(0, 0.05, 0.03), Vector3(0, 0, 0), HEAD, 41, 7, false)
	_plate(r, S_PLATE, Vector3(0.32, 0.09, 0.15), hd + Vector3(0, 0.14, -0.18), Vector3(-18, 0, 0), HEAD, 42, 5, false)
	for side: float in [-1.0, 1.0]:
		_plate(r, S_PLATE, Vector3(0.09, 0.08, 0.11), hd + Vector3(side * 0.14, -0.01, -0.12), Vector3(0, side * 20, 0), HEAD, 43 + int(side + 1.0), 4, false)
		# Eye slits: thin, slanted, deep under the brow.
		r.slot(S_EYE).rigid(ModelKit.sphere(1.0, 10), Transform3D(Basis.from_euler(Vector3(0, 0, side * 0.22)).scaled(Vector3(0.075, 0.018, 0.03)), hd + Vector3(side * 0.085, 0.065, -0.225)), HEAD)
	_plate(r, S_PLATE, Vector3(0.19, 0.085, 0.16), r.rest[JAW] + Vector3(0, -0.03, -0.06), Vector3(8, 0, 0), JAW, 47, 5, false)

	# --- Arms: huge pauldrons, plated upper arms, massive forearms, block fists.
	for side: float in [-1.0, 1.0]:
		var sh := SH_L if side < 0.0 else SH_R
		var s0: Vector3 = r.rest[sh]
		var e0: Vector3 = r.rest[sh + 1]
		var f0: Vector3 = r.rest[sh + 2]
		var o := 50 + int(side + 1.0) * 10
		_plate(r, S_PLATE, Vector3(0.42, 0.33, 0.42), s0 + Vector3(side * 0.06, 0.15, 0.0), Vector3(0, 0, side * -18), sh, o, 7, false)
		_plate(r, S_PLATE, Vector3(0.21, 0.3, 0.23), s0.lerp(e0, 0.55) + Vector3(side * 0.04, 0, 0), Vector3(0, 0, side * 8), sh, o + 1)
		_plate(r, S_PLATE, Vector3(0.17, 0.26, 0.15), s0.lerp(e0, 0.5) + Vector3(-side * 0.03, 0.02, -0.12), Vector3(-6, 0, 0), sh, o + 7, 5, false)
		_plate(r, S_PLATE, Vector3(0.16, 0.24, 0.15), s0.lerp(e0, 0.45) + Vector3(-side * 0.02, 0.0, 0.13), Vector3(8, 0, 0), sh, o + 8, 5, false)
		_plate(r, S_PLATE, Vector3(0.16, 0.14, 0.16), e0 + Vector3(0, 0.02, 0.1), Vector3(20, 0, 0), sh + 1, o + 2, 4, false)
		_plate(r, S_PLATE, Vector3(0.29, 0.4, 0.3), e0.lerp(f0, 0.5) + Vector3(side * 0.03, 0, 0), Vector3(0, side * 10, side * 4), sh + 1, o + 3, 7, false)
		_plate(r, S_PLATE, Vector3(0.12, 0.28, 0.14), e0.lerp(f0, 0.45) + Vector3(side * 0.22, 0.02, 0.05), Vector3(0, 0, side * 6), sh + 1, o + 4, 5)
		_plate(r, S_PLATE, Vector3(0.2, 0.3, 0.16), e0.lerp(f0, 0.4) + Vector3(-side * 0.08, 0.02, -0.18), Vector3(-5, 0, 0), sh + 1, o + 10, 5, false)
		_plate(r, S_PLATE, Vector3(0.2, 0.26, 0.16), e0.lerp(f0, 0.35) + Vector3(-side * 0.06, 0.04, 0.17), Vector3(6, 0, 0), sh + 1, o + 11, 5, false)
		# Fist: a palm block, four knuckles, a thumb.
		_plate(r, S_PLATE, Vector3(0.27, 0.22, 0.29), f0 + Vector3(0, -0.1, 0), Vector3(0, side * 10, 0), sh + 2, o + 5, 6, false)
		for k in 4:
			var x := (float(k) - 1.5) * 0.11
			_plate(r, S_PLATE, Vector3(0.075, 0.085, 0.09), f0 + Vector3(x * 0.9 + side * 0.02, -0.26, -0.14 + absf(x) * 0.15), Vector3(10, 0, 0), sh + 2, o + 6 + k, 4, false)
		_plate(r, S_PLATE, Vector3(0.08, 0.13, 0.08), f0 + Vector3(-side * 0.17, -0.12, -0.12), Vector3(0, 0, side * 25), sh + 2, o + 9, 4, false)
	# --- Legs: thick thighs, knee caps, shins, broad feet.
	for side: float in [-1.0, 1.0]:
		var hp := HIP_L if side < 0.0 else HIP_R
		var h0: Vector3 = r.rest[hp]
		var k0: Vector3 = r.rest[hp + 1]
		var ft: Vector3 = r.rest[hp + 2]
		var o := 80 + int(side + 1.0) * 10
		_plate(r, S_PLATE, Vector3(0.28, 0.32, 0.3), h0.lerp(k0, 0.5) + Vector3(side * 0.03, 0, 0), Vector3(0, side * 8, 0), hp, o, 7, false)
		_plate(r, S_PLATE, Vector3(0.15, 0.13, 0.12), k0 + Vector3(0, 0.02, -0.16), Vector3(-10, 0, 0), hp + 1, o + 1, 4, false)
		_plate(r, S_PLATE, Vector3(0.24, 0.3, 0.26), k0.lerp(ft, 0.5) + Vector3(0, 0.02, 0.01), Vector3(0, side * -6, 0), hp + 1, o + 2, 6, false)
		_plate(r, S_PLATE, Vector3(0.2, 0.26, 0.14), k0.lerp(ft, 0.45) + Vector3(0, 0.0, -0.17), Vector3(-6, 0, 0), hp + 1, o + 7, 6, false)
		_plate(r, S_PLATE, Vector3(0.22, 0.26, 0.15), h0.lerp(k0, 0.55) + Vector3(0, 0, -0.18), Vector3(-10, 0, 0), hp, o + 8, 6, false)
		_plate(r, S_PLATE, Vector3(0.22, 0.24, 0.15), h0.lerp(k0, 0.5) + Vector3(0, 0, 0.18), Vector3(8, 0, 0), hp, o + 9, 6, false)
		_plate(r, S_PLATE, Vector3(0.27, 0.12, 0.34), ft + Vector3(0, -0.04, -0.1), Vector3(0, side * 6, 0), hp + 2, o + 3, 6, false)
		for k in 3:
			_plate(r, S_PLATE, Vector3(0.085, 0.07, 0.1), ft + Vector3((float(k) - 1.0) * 0.14, -0.08, -0.4 + absf(float(k) - 1.0) * 0.04), Vector3(0, 0, 0), hp + 2, o + 4 + k, 4, false)

	# --- Crystal clusters erupting from the back, shoulders and forearms.
	var clusters := [[Vector3(0.0, 2.32, 0.26), Vector3(0.0, 1.0, 0.45), CHEST, 6, 0.7], [Vector3(-0.35, 2.1, 0.42), Vector3(-0.5, 0.9, 0.6), CHEST, 4, 0.5],
		[Vector3(0.38, 2.05, 0.44), Vector3(0.6, 0.8, 0.6), CHEST, 4, 0.48], [Vector3(-0.92, 2.25, -0.02), Vector3(-0.6, 1.0, -0.1), SH_L, 4, 0.42],
		[Vector3(0.92, 2.25, 0.0), Vector3(0.6, 1.0, -0.05), SH_R, 5, 0.45], [Vector3(-1.22, 1.0, -0.2), Vector3(-1.0, 0.5, 0.3), SH_L + 1, 3, 0.28],
		[Vector3(1.22, 1.05, -0.1), Vector3(1.0, 0.4, 0.2), SH_R + 1, 2, 0.24], [Vector3(0.0, 1.5, 0.45), Vector3(0.0, 0.4, 1.0), SPINE, 3, 0.32],
		[Vector3(-0.5, 1.92, -0.42), Vector3(-0.4, 0.6, -0.8), CHEST, 2, 0.22]]
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for ci in clusters.size():
		var cl: Array = clusters[ci]
		var at: Vector3 = cl[0]
		var out := (cl[1] as Vector3).normalized()
		for k in int(cl[3]):
			var l := float(cl[4]) * rng.randf_range(0.45, 1.0) * (1.25 if k == 0 else 1.0)
			var dir := (out + Vector3(rng.randf_range(-0.55, 0.55), rng.randf_range(-0.25, 0.35), rng.randf_range(-0.55, 0.55)) * (0.0 if k == 0 else 1.0)).normalized()
			var b := MobModel._frame(dir, Vector3.FORWARD if absf(dir.z) < 0.9 else Vector3.RIGHT)
			b = b * Basis(Vector3.UP, rng.randf() * TAU)
			var cm := BossKit.crystal_mesh("golem_cr_%d" % int(l * 100.0), l * 0.2, l, 6, 0.35, 0.12, rng.randf_range(-0.2, 0.2))
			r.slot(S_CRYSTAL).rigid(cm, Transform3D(b, at - dir * l * 0.18), int(cl[2]))
	# --- Moss and lichen on the upward faces.
	var moss := [[Vector3(0.0, 2.27, 0.05), Vector3(0.42, 0.06, 0.28), CHEST], [Vector3(-0.85, 2.3, -0.06), Vector3(0.24, 0.05, 0.22), SH_L],
		[Vector3(0.88, 2.29, 0.04), Vector3(0.2, 0.05, 0.25), SH_R], [Vector3(0.03, 2.17, -0.38), Vector3(0.13, 0.04, 0.12), HEAD],
		[Vector3(0.5, 1.98, 0.34), Vector3(0.2, 0.05, 0.16), CHEST], [Vector3(-0.42, 1.18, 0.3), Vector3(0.16, 0.04, 0.12), SPINE]]
	for mi in moss.size():
		var m: Array = moss[mi]
		r.slot(S_MOSS).rigid(OrganicMesh.blob("golem_moss_%d" % mi, m[1], 0.45, 60 + mi, 12), Transform3D(Basis(), m[0]), int(m[2]))
	# Hanging moss strands off the back and arms.
	var strand := MobRig.tuft_mesh("golem_moss", 0.12, -0.05, 4)
	for k in 14:
		var a := rng.randf_range(-1.0, 1.0)
		var at := Vector3(a * 0.5, rng.randf_range(1.85, 2.2), 0.28 + rng.randf_range(0.0, 0.15))
		var l := rng.randf_range(0.12, 0.28)
		r.slot(S_MOSS).rigid(strand, Transform3D(Basis(Vector3.RIGHT, PI * 0.92).scaled(Vector3(l * 0.8, l, l)), at), CHEST)
	return r.build("golem")


# --- Animation ----------------------------------------------------------------------------

func _on_action(_action_name: String) -> void:
	_impact_done = false


func _fx_parent() -> Node3D:
	var ent := get_parent()
	if ent != null and ent.get_parent() is Node3D:
		return ent.get_parent() as Node3D
	return self


func _fx_at_bone(b: int, style: String, scale_fx: float) -> void:
	if not is_inside_tree():
		return
	var pos := global_transform * to_model(gp[b])
	pos.y = global_position.y + 0.1
	CreatureFx.play(_fx_parent(), style, pos, scale_fx)


func _animate(delta: float) -> void:
	if skel == null:
		return
	var p := action_progress()
	var w := action_weight(0.12, 0.2)
	var act := _action if p >= 0.0 and not _dead else ""
	var speed := move_speed / rig_scale
	_walk = damp(_walk, clampf(speed / 1.4, 0.0, 1.0), 4.0, delta)
	_gait = fposmod(_gait + delta * speed / 1.7, 1.0)
	var g := _gait * TAU

	var lean := 0.0
	var crouch := 0.0
	var flare := 0.0
	var arm_x := [0.15 + sin(g) * 0.4 * _walk, 0.15 - sin(g) * 0.4 * _walk]
	var arm_z := [-0.12, 0.12]
	var elbow := [0.35 + maxf(0.0, -sin(g)) * 0.25 * _walk, 0.35 + maxf(0.0, sin(g)) * 0.25 * _walk]
	var chest_yaw := -sin(g) * 0.12 * _walk
	var head_x := sin(_time * 0.5) * 0.05
	var head_y := sin(_time * 0.3) * 0.18
	var jaw := 0.0
	match act:
		"slam", "spikes":
			var up := keys(p, [[0, 0], [0.55, 1.0], [0.66, 1.0], [0.76, 0.0], [1, 0]])
			var down := keys(p, [[0, 0], [0.68, 0.0], [0.76, 1.0], [0.9, 1.0], [1, 0]])
			for i in 2:
				arm_x[i] = lerpf(float(arm_x[i]), 2.9, up)
				arm_x[i] = lerpf(float(arm_x[i]), 1.25, down)
				arm_z[i] = lerpf(float(arm_z[i]), 0.25 * (1.0 if i == 1 else -1.0), up)
				elbow[i] = lerpf(lerpf(float(elbow[i]), 0.7, up), 0.15, down)
			lean = -0.22 * up + 0.55 * down
			crouch = 0.1 * up + 0.24 * down
			flare = maxf(up, down)
			jaw = 0.6 * up
			head_x += 0.3 * up - 0.2 * down
			if p >= SLAM_IMPACT and not _impact_done:
				_impact_done = true
				_fx_at_bone(SH_L + 2, "dust_cloud", 1.3)
				_fx_at_bone(SH_R + 2, "dust_cloud", 1.3)
				_fx_at_bone(SH_R + 2, "dust", 1.6)
		"attack", "attack2", "throw", "shoot", "cast":
			var i := 1 if act != "attack2" else 0
			var wind := keys(p, [[0, 0], [0.4, 1.0], [0.55, 0.0], [1, 0]])
			var hit := keys(p, [[0, 0], [0.45, 0.0], [0.6, 1.0], [0.8, 0.8], [1, 0]])
			arm_x[i] = float(arm_x[i]) - 0.7 * wind + 1.45 * hit
			elbow[i] = float(elbow[i]) + 1.1 * wind - 0.3 * hit
			arm_z[i] = float(arm_z[i]) + (0.25 if i == 1 else -0.25) * wind
			chest_yaw += (0.45 if i == 1 else -0.45) * wind - (0.5 if i == 1 else -0.5) * hit
			lean = 0.25 * hit
			crouch = 0.06 * hit
			flare = 0.4 * hit
		"roar", "summon", "howl":
			lean = -0.3 * w
			head_x -= 0.55 * w
			jaw = 0.9 * w
			arm_x = [lerpf(float(arm_x[0]), 0.5, w), lerpf(float(arm_x[1]), 0.5, w)]
			arm_z = [lerpf(-0.12, -1.0, w), lerpf(0.12, 1.0, w)]
			elbow = [lerpf(float(elbow[0]), 0.9, w), lerpf(float(elbow[1]), 0.9, w)]
			flare = w * (1.0 + 0.3 * sin(_time * 22.0))
		"hit":
			var s := sin(PI * clampf(p * 1.3, 0.0, 1.0))
			lean = -0.18 * s
			head_x -= 0.3 * s
			head_y += 0.25 * s
			chest_yaw += 0.15 * s
			flare = 0.5 * s
	_lean = damp(_lean, lean, 9.0, delta)
	_crouch = damp(_crouch, crouch, 9.0, delta)
	_flare = damp(_flare, flare, 8.0, delta)

	# Body: heavy weight shift over the planted foot, a hunched stoop.
	var sway := sin(g) * 0.07 * _walk
	var bob := -absf(cos(g)) * 0.05 * _walk + sin(_time * 1.1) * 0.01
	var pel: Vector3 = rest[PELVIS] + Vector3(sway, bob - _crouch, 0)
	place(PELVIS, pel, Basis.from_euler(Vector3(0, chest_yaw * -0.4, -sway * 0.7)))
	fk(SPINE, Vector3(-0.12 - _lean * 0.5, chest_yaw * 0.5, sway * 0.4))
	fk(CHEST, Vector3(-0.1 - _lean * 0.5 + sin(_time * 1.1) * 0.015, chest_yaw * 0.5, sway * 0.3))
	fk(HEAD, Vector3(0.25 + _lean * 0.6 + head_x, head_y, 0))
	fk(JAW, Vector3(-jaw * 0.35, 0, 0))
	for i in 2:
		var sh := SH_L if i == 0 else SH_R
		fk(sh, Vector3(float(arm_x[i]), 0, float(arm_z[i])))
		fk(sh + 1, Vector3(float(elbow[i]), 0, 0))
		fk(sh + 2, Vector3(0.1, 0, 0))
	# Legs: planted feet by IK.
	for i in 2:
		var hp := HIP_L if i == 0 else HIP_R
		fk(hp)
		var ph := fposmod(_gait + (0.0 if i == 0 else 0.5), 1.0)
		var foot: Vector3 = rest[hp + 2]
		var duty := 0.62
		var stride := 0.62 * _walk
		var lift := 0.0
		if ph < duty:
			foot.z += stride * (-0.5 + ph / duty)
		else:
			var s := (ph - duty) / (1.0 - duty)
			lift = sin(PI * s)
			foot.z += stride * (0.5 - s * s * (3.0 - 2.0 * s))
			foot.y += lift * 0.2 * _walk
		foot.x += sway * 0.2
		ik(hp, hp + 1, hp + 2, foot, gb[PELVIS] * Vector3(0, 0, -1))
		gb[hp + 2] = Basis(Vector3.RIGHT, -lift * 0.25 * _walk)

	if _dead:
		_pose_dead()
		body_mi.set_instance_shader_parameter(&"intensity", _death_fade())
	commit()
	var glow := _flare * 1.6 + sin(_time * 1.3) * 0.1
	if _dead:
		glow = -clampf(_dead_t / 2.0, 0.0, 1.0)
	body_mi.set_instance_shader_parameter(&"inner_glow", glow)
	_light.light_energy = maxf(0.0, 1.2 + _flare * 2.0 + glow * 0.5) if not _dead else maxf(0.0, 1.2 * (1.0 - _dead_t))


## Buckle to the knees, topple forward, then the plates fall apart.
func _pose_dead() -> void:
	if not _death_pose:
		_death_pose = true
		_dead_gb = gb.duplicate()
		_dead_gp = gp.duplicate()
		_scatter.clear()
		var rng := RandomNumberGenerator.new()
		rng.seed = get_instance_id()
		for b in bone_count:
			_scatter.append(Vector3(rng.randf_range(-1, 1), rng.randf_range(0.0, 1.0), rng.randf_range(-1, 1)))
	var t := _dead_t
	var kneel := clampf(t / 0.7, 0.0, 1.0)
	kneel = kneel * kneel * (3.0 - 2.0 * kneel)
	var topple := clampf((t - 0.5) / 0.6, 0.0, 1.0)
	topple = topple * topple
	var apart := clampf((t - 0.95) / 0.8, 0.0, 1.0)
	# Kneeling, slumping forward.
	place(PELVIS, rest[PELVIS] + Vector3(0, -0.52 * kneel - 0.2 * topple, -0.25 * topple), Basis(Vector3.RIGHT, -0.5 * topple))
	fk(SPINE, Vector3(-0.3 * kneel - 0.25 * topple, 0, 0))
	fk(CHEST, Vector3(-0.25 * kneel - 0.2 * topple, 0, 0.05))
	fk(HEAD, Vector3(-0.4 * kneel, 0.2, 0))
	fk(JAW, Vector3(-0.3, 0, 0))
	for i in 2:
		var sh := SH_L if i == 0 else SH_R
		fk(sh, Vector3(0.3 + 0.6 * topple, 0, (0.25 if i == 1 else -0.25) * kneel))
		fk(sh + 1, Vector3(0.2, 0, 0))
		fk(sh + 2, Vector3(0, 0, 0))
		var hp := HIP_L if i == 0 else HIP_R
		fk(hp, Vector3(0.25 * kneel, 0, (0.15 if i == 1 else -0.15) * kneel))
		fk(hp + 1, Vector3(-1.45 * kneel, 0, 0))
		fk(hp + 2, Vector3(0.9 * kneel, 0, 0))
	var f := clampf(t / 0.5, 0.0, 1.0)
	for b in bone_count:
		gb[b] = _dead_gb[b].slerp(gb[b], f).orthonormalized()
		gp[b] = _dead_gp[b].lerp(gp[b], f)
	if apart > 0.0:
		if not _dust_done:
			_dust_done = true
			_fx_at_bone(CHEST, "dust_cloud", 1.0)
		# The stones come apart and settle on the ground.
		for b in bone_count:
			var sc: Vector3 = _scatter[b]
			var settle := 0.22 + sc.y * 0.12
			var target := Vector3(gp[b].x + sc.x * 0.45, settle, gp[b].z + sc.z * 0.45 - 0.2)
			var e := apart * apart
			gp[b] = gp[b].lerp(target, e)
			gb[b] = (gb[b] * Basis(Vector3(sc.z, 0.3, -sc.x).normalized(), 1.2 * e * (sc.y - 0.5))).orthonormalized()


## Eyes (and the elemental's heart) go dark as it dies, before the body crumbles.
func _death_fade() -> float:
	return 1.0 if not _dead else clampf(1.0 - _dead_t / 0.8, 0.0, 1.0)


func set_glow_intensity(v: float) -> void:
	super.set_glow_intensity(v * _death_fade())


func set_dead(dead: bool) -> void:
	super.set_dead(dead)
	if not dead:
		_death_pose = false
		_dust_done = false
