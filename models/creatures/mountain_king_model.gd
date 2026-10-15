class_name MountainKingModel
extends BossHumanoid
## The Mountain King: a colossal giant of the high peaks, his body living
## granite veined with frost-blue runes, girded in rimed iron - a rune-cut
## breastplate, banded bracers, a great belt and boulder pauldrons sprouting
## ice - under a white fur mantle and a heavy cape. A long braided beard of
## frost-white hair hangs to his belt, an iron crown of ice crystals sits on
## his brow, and he wields a rune-bound warhammer the size of a cart. Asleep,
## he leans on the hammer, its head planted in the floor. Phase 2 kindles the
## runes in his cracks, phase 3 wreathes him in a freezing storm.

const STONE := Color(0.5, 0.52, 0.55)
const STONE_DARK := Color(0.38, 0.4, 0.43)
const LICHEN := Color(0.34, 0.37, 0.32)
const IRON := Color(0.38, 0.4, 0.43)
const IRON_DARK := Color(0.24, 0.25, 0.27)
const RUNE_IRON := Color(0.34, 0.36, 0.39, 0.0)
const FUR := Color(0.86, 0.87, 0.86)
const FUR_SHADE := Color(0.62, 0.64, 0.66)
const BEARD := Color(0.88, 0.9, 0.93)
const CAPE := Color(0.16, 0.2, 0.3)
const LEATHER := Color(0.25, 0.18, 0.12)
const ICE := Color(0.62, 0.86, 1.0)
const FROST := Color(0.55, 0.85, 1.0)

var _storm: Array[GPUParticles3D] = []
var _breath: GPUParticles3D
var _breath_t := 2.0
var _crystals: Array[Node3D] = []


func _init() -> void:
	super({"height": 7.0, "bulk": 1.75, "hunch": -0.12, "arm_length": 1.15, "cloak": true, "cloak_hem": 0.22,
		"held": "giant_club", "eyes": FROST, "cloak_color": CAPE})
	durations["slam"] = 1.5
	durations["throw"] = 1.2


func _ember_extents() -> Vector3:
	return Vector3(1.4, 3.0, 1.0)


func _lod_size() -> float:
	return 7.0


func _dress() -> void:
	var k := _kit_key()
	var rock := BossKit.rock(LICHEN, {"frost": 0.55, "rune": 1.0, "rune_color": FROST, "rune_energy": 1.6, "pattern_scale": 9.0})
	var iron := BossKit.metal({"rust": 0.25, "wear": 0.35, "grime": 0.5, "frost": 0.45, "roughness": 0.5, "rune": 1.0, "rune_color": FROST, "rune_energy": 3.0, "rune_scale": 9.0})
	var fur := BossKit.fur(FUR_SHADE, {"frost": 0.25})
	var beard := BossKit.fur(Color(0.62, 0.66, 0.72), {"pattern_scale": 22.0, "frost": 0.1})
	var leather := BossKit.leather({"frost": 0.2, "albedo": LEATHER})
	var ice := BossKit.crystal(Color(0.85, 0.95, 1.0), ICE, 0.7)
	var cape := BossKit.cloth(CAPE, Color(0.3, 0.34, 0.42), {"tatter": 0.35, "grime": 0.4, "frost": 0.3})
	var eye := BossKit.glow(FROST, 7.0, 0.2)
	var dark := ModelKit.mat(Color(0.02, 0.025, 0.03), AsciiMaterialId.SOLID, 0.9, 0.0, 0.0)
	_dress_head(k, rock, iron, beard, ice, eye, dark)
	_dress_body(k, rock, iron, fur, leather, ice)
	_dress_limbs(k, rock, iron, fur, leather, ice)
	skinned(BossKit.robe(k + "_kilt_f", _rest, 0.93, 0.5, Vector2(0.24, 0.2), Vector2(0.27, 0.24), 10, 8, PI * 0.72, PI * 1.28, 0.012), leather)
	skinned(BossKit.robe(k + "_kilt_b", _rest, 0.93, 0.46, Vector2(0.25, 0.2), Vector2(0.29, 0.25), 10, 8, -PI * 0.3, PI * 0.3, 0.012), leather)
	skinned(BossKit.cloak(k + "_cape", body, style, 17, 15, 0.016, 1.2, 0.02), cape)
	# Cold light from the crown and a slow fall of snow off the shoulders.
	var crown := fx_point(R.HEAD, Vector3(0, 1.92, 0))
	add_light(crown, Vector3.ZERO, ICE, 1.6, 12.0)
	for side: float in [-1.0, 1.0]:
		var o := 0 if side < 0.0 else 5
		var p := fx_point(R.UARM_L + o, _rest[R.UARM_L + o] + Vector3(side * 0.1, 0.18, 0))
		_storm.append(BossKit.emitter(p, "frost", 10, Vector3(0.4, 0.1, 0.4), Color(0.85, 0.92, 1.0), 0.18, 3.0, 0.1))
	var mouth := fx_point(R.JAW, Vector3(0, 1.62, -0.16))
	_breath = BossKit.emitter(mouth, "frost", 24, Vector3(0.05, 0.03, 0.05), Color(0.8, 0.9, 1.0), 0.5, 1.4, 1.2)
	(_breath.process_material as ParticleProcessMaterial).direction = Vector3(0, -0.2, -1)
	_breath.emitting = false


func _dress_head(k: String, rock: Material, iron: Material, beard: Material, ice: Material, eye: Material, dark: Material) -> void:
	var head := part(R.HEAD)
	# A craggy head: skull, heavy brow, broad nose, cheekbones, sunken glowing eyes.
	head.put(OrganicMesh.blob(k + "_skull", Vector3(0.125, 0.145, 0.135), 0.18, 21, 16), rock, Vector3(0, 1.73, 0.0), Vector3.ZERO, Vector3.ONE, STONE)
	head.put(OrganicMesh.blob(k + "_brow", Vector3(0.12, 0.035, 0.06), 0.25, 22, 12), rock, Vector3(0, 1.765, -0.105), Vector3(8, 0, 0), Vector3.ONE, STONE_DARK)
	head.put(OrganicMesh.blob(k + "_nose", Vector3(0.032, 0.055, 0.04), 0.2, 23, 10), rock, Vector3(0, 1.715, -0.14), Vector3(-12, 0, 0), Vector3.ONE, STONE)
	for sx: float in [-1.0, 1.0]:
		head.put(OrganicMesh.blob(k + "_cheek", Vector3(0.045, 0.035, 0.04), 0.25, 24, 10), rock, Vector3(sx * 0.07, 1.705, -0.1), Vector3.ZERO, Vector3.ONE, STONE_DARK)
		head.put(OrganicMesh.blob(k + "_socket", Vector3(0.03, 0.018, 0.02), 0.0, 2, 8), dark, Vector3(sx * 0.047, 1.742, -0.118))
		head.put(ModelKit.sphere(0.013, 8), eye, Vector3(sx * 0.047, 1.742, -0.128), Vector3.ZERO, Vector3(1.3, 0.8, 0.6))
		head.put(OrganicMesh.blob(k + "_ear", Vector3(0.02, 0.045, 0.03), 0.2, 25, 8), rock, Vector3(sx * 0.125, 1.72, 0.0), Vector3.ZERO, Vector3.ONE, STONE_DARK)
	# Long hair down the back.
	for i in 7:
		var x := lerpf(-0.11, 0.11, i / 6.0)
		var len := 0.32 + 0.06 * sin(i * 1.7)
		var strand := OrganicMesh.bezier("%s_hair_%d" % [k, i], Vector3.ZERO, Vector3(x * 0.4, -len * 0.4, 0.08), Vector3(x * 0.6, -len, 0.06), 0.045, 0.012, 8, 7, 0.6)
		head.add(strand, beard, Transform3D(Basis.IDENTITY, Vector3(x, 1.8, 0.07)), BEARD.darkened(0.08 * (i % 3)))
	# Iron crown with crenellations and ice crystals.
	var band := PackedVector2Array([Vector2(0.142, 1.8), Vector2(0.146, 1.83), Vector2(0.145, 1.865), Vector2(0.15, 1.875)])
	head.add(BossKit.lathe(k + "_crown", band, 22, 1.0, 1.06), iron, Transform3D.IDENTITY, RUNE_IRON)
	for i in 8:
		var a := TAU * i / 8.0 + PI / 8.0
		var p := Vector3(cos(a) * 0.146, 1.875, sin(a) * 0.155)
		head.put(OrganicMesh.bezier(k + "_crenel", Vector3.ZERO, Vector3(0, 0.025, 0), Vector3(0, 0.045, 0), 0.02, 0.006, 4, 5), iron, p, Vector3.ZERO, Vector3.ONE, IRON)
	for i in 5:
		var a := -PI * 0.5 + (i - 2) * 0.5
		var h := 0.16 - absf(i - 2) * 0.035
		var p := Vector3(cos(a) * 0.14, 1.86, sin(a) * 0.15)
		var tilt := Vector3(sin(a) * 0.0, 0, 0)
		head.put(BossKit.crystal_mesh("%s_crownice_%d" % [k, i], 0.03, h, 6, 0.35, 0.1, 0.2), ice, p, Vector3(-cos(a) * 8.0, 0, (i - 2) * -9.0) + tilt, Vector3.ONE, Color(1, 1, 1))
	# The jaw carries the beard so it parts when he roars.
	var jaw := part(R.JAW)
	jaw.put(OrganicMesh.blob(k + "_jaw", Vector3(0.105, 0.055, 0.1), 0.2, 26, 12), rock, Vector3(0, 1.635, -0.045), Vector3.ZERO, Vector3.ONE, STONE_DARK)
	# The beard: a full mass of hair over the chest, combed into many flat locks.
	jaw.put(OrganicMesh.blob(k + "_beardmass", Vector3(0.11, 0.14, 0.06), 0.15, 27, 16), beard, Vector3(0, 1.53, -0.13), Vector3(-10, 0, 0), Vector3.ONE, BEARD.darkened(0.35))
	# Layered sheets of hair, each a flat lock curving over the chest.
	for i in 11:
		var u := float(i) / 10.0
		var x := lerpf(-0.1, 0.1, u)
		var centre := 1.0 - absf(x) / 0.1
		var len := 0.26 + 0.22 * centre + 0.03 * sin(i * 2.7)
		var root := Vector3(x, 1.655 - centre * 0.05, -0.1 - centre * 0.04)
		var path := PackedVector3Array()
		var widths := PackedFloat32Array()
		for j in 7:
			var t := j / 6.0
			path.append(root + Vector3(x * 0.3 * t + sin(t * 3.0 + i) * 0.008, -len * t, -0.08 * sin(t * PI * 0.8) - 0.02 * t))
			widths.append(lerpf(0.022, 0.006, t * t))
		jaw.add(BossKit.ribbon("%s_lock_%d" % [k, i], path, widths, Vector3.RIGHT, 0.006), beard, Transform3D.IDENTITY, BEARD.darkened(0.1 * float(i % 3)))
	# Three thick braids bound with iron rings.
	for b in 3:
		var x := (b - 1) * 0.05
		var top := Vector3(x, 1.6, -0.13)
		var mid := Vector3(x * 1.2, 1.38, -0.2)
		var end := Vector3(x * 1.3, 1.12, -0.17)
		jaw.add(OrganicMesh.bezier("%s_braid_%d" % [k, b], Vector3.ZERO, mid - top, end - top, 0.04, 0.02, 12, 8), beard, Transform3D(Basis.IDENTITY, top), BEARD)
		for r in 3:
			var t := 0.35 + r * 0.25
			var p := top.lerp(mid, t).lerp(mid.lerp(end, t), t)
			jaw.put(BossKit.torus(k + "_braidring", 0.035, 0.009, 14, 5), iron, p, Vector3(10, 0, 0), Vector3.ONE, IRON)
	# Mustache.
	for sx: float in [-1.0, 1.0]:
		head.put(OrganicMesh.bezier("%s_mous_%d" % [k, int(sx)], Vector3.ZERO, Vector3(sx * 0.05, -0.02, -0.01), Vector3(sx * 0.07, -0.11, 0.0), 0.022, 0.008, 8, 6), beard, Vector3(sx * 0.012, 1.685, -0.145), Vector3.ZERO, Vector3.ONE, BEARD)


func _dress_body(k: String, rock: Material, iron: Material, fur: Material, leather: Material, ice: Material) -> void:
	var chest := part(R.CHEST)
	chest.put(OrganicMesh.blob(k + "_chest", Vector3(0.3, 0.24, 0.2), 0.12, 31, 18), rock, Vector3(0, 1.3, 0.0), Vector3.ZERO, Vector3.ONE, STONE)
	for sx: float in [-1.0, 1.0]:
		chest.put(OrganicMesh.blob(k + "_trap", Vector3(0.12, 0.08, 0.12), 0.2, 32, 12), rock, Vector3(sx * 0.15, 1.46, 0.02), Vector3(0, 0, sx * -20), Vector3.ONE, STONE_DARK)
	# Rune-cut breastplate over the heart and the straps that hold it.
	var plate := BossKit.wrap_rows([[1.46, 0.2, 0.17, 0.0], [1.4, 0.25, 0.21, 0.02], [1.32, 0.27, 0.22, 0.03], [1.22, 0.25, 0.21, 0.03], [1.14, 0.22, 0.2, 0.02]], -1.25, 1.25, 17)
	chest.add(BossKit.plate(k + "_breast", plate, 0.03, Vector3(0, 1.3, 0.05)), iron, Transform3D.IDENTITY, RUNE_IRON)
	var rim := PackedVector3Array()
	var rim_r := PackedVector2Array()
	for i in 11:
		var a := lerpf(-1.25, 1.25, i / 10.0)
		rim.append(Vector3(sin(a) * 0.205, 1.462, -cos(a) * 0.172))
		rim_r.append(Vector2(0.016, 0.016))
	chest.add(OrganicMesh.sweep(k + "_brim", rim, rim_r, 6), iron, Transform3D.IDENTITY, IRON_DARK)
	for sx: float in [-1.0, 1.0]:
		var strap := PackedVector3Array([Vector3(sx * 0.17, 1.44, -0.17), Vector3(sx * 0.24, 1.47, -0.05), Vector3(sx * 0.24, 1.46, 0.1), Vector3(sx * 0.16, 1.36, 0.2)])
		var sr := PackedVector2Array([Vector2(0.035, 0.008), Vector2(0.035, 0.008), Vector2(0.035, 0.008), Vector2(0.035, 0.008)])
		chest.add(OrganicMesh.sweep("%s_strap_%d" % [k, int(sx)], strap, sr, 6, Vector3.UP), leather, Transform3D.IDENTITY, Color(1, 1, 1))
	# The white fur mantle across the shoulders and back.
	for i in 9:
		var a := lerpf(-0.2, PI + 0.2, i / 8.0)
		var p := Vector3(cos(a) * 0.27, 1.5 + sin(a) * 0.01, sin(a) * 0.1 + 0.04)
		chest.put(OrganicMesh.blob("%s_fur_%d" % [k, i % 3], Vector3(0.11, 0.075, 0.1), 0.35, 40 + i % 3, 12), fur, p, Vector3(0, -a * 57.0, 0), Vector3.ONE, FUR.darkened(0.05 * (i % 2)))
	# Belly and the great belt.
	var spine := part(R.SPINE)
	spine.put(OrganicMesh.blob(k + "_belly", Vector3(0.27, 0.19, 0.21), 0.15, 33, 16), rock, Vector3(0, 1.08, -0.02), Vector3.ZERO, Vector3.ONE, STONE_DARK)
	var hips := part(R.HIPS)
	hips.put(OrganicMesh.blob(k + "_pelvis", Vector3(0.25, 0.12, 0.18), 0.15, 34, 14), rock, Vector3(0, 0.93, 0.0), Vector3.ZERO, Vector3.ONE, STONE)
	var belt := PackedVector2Array([Vector2(0.27, 0.92), Vector2(0.285, 0.95), Vector2(0.285, 1.0), Vector2(0.272, 1.03)])
	hips.add(BossKit.lathe(k + "_belt", belt, 26, 1.0, 0.82), leather, Transform3D.IDENTITY, Color(1, 1, 1))
	var buckle := BossKit.wrap_rows([[1.05, 0.11, 0.24, 0.0], [0.98, 0.125, 0.25, 0.01], [0.9, 0.11, 0.24, 0.0]], -0.5, 0.5, 9)
	hips.add(BossKit.plate(k + "_buckle", buckle, 0.03, Vector3(0, 0.97, 0.05)), iron, Transform3D.IDENTITY, RUNE_IRON)
	for i in 6:
		var a := TAU * i / 6.0 + 0.5
		hips.put(ModelKit.sphere(0.018, 6), iron, Vector3(cos(a) * 0.29, 0.975, sin(a) * 0.24), Vector3.ZERO, Vector3.ONE, IRON)


func _dress_limbs(k: String, rock: Material, iron: Material, fur: Material, leather: Material, ice: Material) -> void:
	for side: float in [-1.0, 1.0]:
		var o := 0 if side < 0.0 else 5
		var sh := _rest[R.UARM_L + o]
		var el := _rest[R.FARM_L + o]
		var wr := _rest[R.HAND_L + o]
		var fi := _rest[R.FING_L + o]
		var ua := part(R.UARM_L + o)
		# Boulder pauldron rimmed with iron, ice growing from it.
		ua.put(OrganicMesh.blob(k + "_pboulder", Vector3(0.19, 0.14, 0.19), 0.3, 35, 16), rock, sh + Vector3(side * 0.04, 0.06, 0.0), Vector3(0, 0, side * -18), Vector3.ONE, STONE_DARK)
		ua.put(BossKit.torus(k + "_prim", 0.17, 0.02, 24, 6, 1.4), iron, sh + Vector3(side * 0.05, -0.0, 0.0), Vector3(0, 0, side * -22), Vector3(1.0, 1.0, 1.08), IRON_DARK)
		for i in 4:
			var h := 0.11 + 0.06 * (i % 2)
			ua.put(BossKit.crystal_mesh("%s_pice_%d" % [k, i], 0.028, h, 6, 0.4, 0.1, 0.15 * i), ice, sh + Vector3(side * (0.06 + i * 0.03), 0.16 - i * 0.012, -0.05 + i * 0.035),
				Vector3(-10 + i * 7, 0, side * (-15 - i * 9)), Vector3.ONE, Color(1, 1, 1))
		ua.add(OrganicMesh.bezier(k + "_uarm", Vector3.ZERO, (el - sh) * 0.5 + Vector3(side * 0.02, 0, 0), el - sh, 0.115, 0.095, 8, 12), rock, Transform3D(Basis.IDENTITY, sh), STONE)
		var fa := part(R.FARM_L + o)
		fa.add(OrganicMesh.bezier(k + "_farm", Vector3.ZERO, (wr - el) * 0.5, wr - el, 0.1, 0.085, 8, 12), rock, Transform3D(Basis.IDENTITY, el), STONE)
		plate_tube(fa, iron, "bracer", el + Vector3(0, -0.06, 0), wr + Vector3(0, 0.03, 0), 0.11, 0.098, RUNE_IRON)
		for b in 2:
			var y := lerpf(el.y - 0.07, wr.y + 0.05, b)
			fa.put(BossKit.torus(k + "_bband", 0.113 - b * 0.012, 0.013, 20, 5), iron, Vector3(lerpf(el.x, wr.x, b), y, lerpf(el.z, wr.z, b)), Vector3.ZERO, Vector3.ONE, IRON_DARK)
		var hand := part(R.HAND_L + o)
		hand.put(OrganicMesh.blob(k + "_palm", Vector3(0.05, 0.075, 0.07), 0.2, 36, 12), rock, (wr + fi) * 0.5 + Vector3(side * 0.005, 0.005, 0), Vector3.ZERO, Vector3.ONE, STONE)
		hand.add(OrganicMesh.bezier(k + "_thumb", Vector3.ZERO, Vector3(0, -0.05, -0.04), Vector3(0, -0.1, -0.03), 0.026, 0.02, 6, 8), rock, Transform3D(Basis.IDENTITY, wr + Vector3(-side * 0.005, -0.03, -0.055)), STONE_DARK)
		var fing := part(R.FING_L + o)
		for f in 4:
			var z := lerpf(-0.045, 0.045, f / 3.0)
			var l := 0.085 if f in [1, 2] else 0.07
			fing.add(OrganicMesh.bezier("%s_finger_%d" % [k, f], Vector3.ZERO, Vector3(0, -l * 0.5, 0), Vector3(0, -l, -l * 0.1), 0.021, 0.016, 6, 7), rock, Transform3D(Basis.IDENTITY, fi + Vector3(0, 0.02, z)), STONE_DARK)
	for side: float in [-1.0, 1.0]:
		var o := 0 if side < 0.0 else 4
		var th := _rest[R.THIGH_L + o]
		var kn := _rest[R.SHIN_L + o]
		var an := _rest[R.FOOT_L + o]
		var to := _rest[R.TOE_L + o]
		var tp := part(R.THIGH_L + o)
		tp.add(OrganicMesh.bezier(k + "_thigh", Vector3.ZERO, (kn - th) * 0.5 + Vector3(side * 0.015, 0, -0.01), kn - th, 0.14, 0.11, 8, 12), rock, Transform3D(Basis.IDENTITY, th + Vector3(0, -0.02, 0)), STONE)
		var sp := part(R.SHIN_L + o)
		var cop := BossKit.wrap_rows([[0.08, 0.08, 0.085, 0.01], [0.02, 0.095, 0.1, 0.03], [-0.04, 0.09, 0.096, 0.03], [-0.09, 0.075, 0.085, 0.01]], -1.4, 1.4, 13)
		sp.add(BossKit.plate(k + "_knee", cop, 0.016, Vector3(0, 0, 0.06)), iron, Transform3D(Basis.IDENTITY, kn + Vector3(0, 0.0, -0.02)), IRON)
		sp.add(OrganicMesh.bezier(k + "_shin", Vector3.ZERO, (an - kn) * 0.5 + Vector3(0, 0, 0.01), an - kn, 0.105, 0.085, 8, 12), rock, Transform3D(Basis.IDENTITY, kn), STONE_DARK)
		# Fur wrappings round the calves.
		var wrap := PackedVector2Array([Vector2(0.105, 0.0), Vector2(0.125, 0.05), Vector2(0.13, 0.15), Vector2(0.118, 0.24), Vector2(0.1, 0.28)])
		sp.add(BossKit.lathe(k + "_legfur", wrap, 16, 1.0, 1.05), fur, Transform3D(Basis.IDENTITY, an + Vector3(0, 0.03, 0.0)), FUR_SHADE)
		sp.put(BossKit.torus(k + "_legstrap", 0.12, 0.012, 16, 5), leather, an + Vector3(0, 0.13, 0), Vector3(8, 0, 0), Vector3.ONE, Color(1, 1, 1))
		var fp := part(R.FOOT_L + o)
		fp.put(OrganicMesh.blob(k + "_foot", Vector3(0.085, 0.07, 0.13), 0.25, 37, 12), rock, an.lerp(to, 0.5) + Vector3(0, 0.02, 0), Vector3.ZERO, Vector3.ONE, STONE)
		for t in 3:
			part(R.TOE_L + o).put(OrganicMesh.blob(k + "_toe", Vector3(0.026, 0.024, 0.035), 0.2, 38, 8), rock, to + Vector3((t - 1) * 0.04, 0.0, -0.02), Vector3.ZERO, Vector3.ONE, STONE_DARK)


## The warhammer: a long iron-banded haft and an octagonal head of rune-cut
## stone bound in iron, with a spike crowned in ice.
func _build_held(item_id: String) -> void:
	_held_id = item_id
	if _held != null:
		_held.queue_free()
		_held = null
	if item_id == "":
		return
	_held = Node3D.new()
	_held.name = "Warhammer"
	grip_r.add_child(_held)
	var k := _kit_key()
	var wood := BossKit.wood(Color(0.24, 0.17, 0.11), {"frost": 0.3})
	var iron := BossKit.metal({"rust": 0.2, "wear": 0.5, "grime": 0.4, "frost": 0.4, "roughness": 0.45, "rune": 1.0, "rune_color": FROST, "rune_energy": 3.5, "rune_scale": 10.0})
	var rock := BossKit.rock(LICHEN, {"frost": 0.5, "rune": 1.0, "rune_color": FROST, "rune_energy": 5.0, "pattern_scale": 12.0})
	var ice := BossKit.crystal(Color(0.85, 0.95, 1.0), ICE, 0.8)
	var asm := BossKit.assembly()
	var haft := PackedVector2Array([Vector2(0.03, -0.42), Vector2(0.034, -0.3), Vector2(0.03, 0.4), Vector2(0.033, 1.15), Vector2(0.036, 1.25)])
	asm.add(BossKit.lathe(k + "_haft", haft, 10), wood, Transform3D.IDENTITY, Color(0.45, 0.33, 0.22))
	for i in 5:
		var y := -0.38 + i * 0.36
		asm.add(BossKit.torus(k + "_haftband", 0.036, 0.009, 12, 5), iron, Transform3D(Basis.IDENTITY, Vector3(0, y, 0)), IRON_DARK)
	asm.add(OrganicMesh.blob(k + "_pommel", Vector3(0.05, 0.05, 0.05), 0.1, 41, 10), iron, Transform3D(Basis.IDENTITY, Vector3(0, -0.45, 0)), IRON)
	# Head across the haft (along X): octagonal stone with iron caps and bands.
	var head_prof := PackedVector2Array([Vector2(0.0, -0.3), Vector2(0.13, -0.3), Vector2(0.15, -0.27), Vector2(0.15, 0.27), Vector2(0.13, 0.3), Vector2(0.0, 0.3)])
	var head_basis := Basis(Vector3.FORWARD, PI * 0.5)
	asm.add(BossKit.lathe(k + "_hhead", head_prof, 8, 1.0, 1.0), rock, Transform3D(head_basis, Vector3(0, 1.32, 0)), STONE_DARK)
	for sx: float in [-1.0, 1.0]:
		var cap := PackedVector2Array([Vector2(0.155, 0.0), Vector2(0.165, 0.02), Vector2(0.16, 0.07), Vector2(0.12, 0.09), Vector2(0.0, 0.095)])
		var cb := Basis(Vector3.FORWARD, -sx * PI * 0.5)
		asm.add(BossKit.lathe(k + "_hcap", cap, 8, 1.0, 1.0, false, true), iron, Transform3D(cb, Vector3(sx * 0.26, 1.32, 0)), RUNE_IRON)
	asm.add(BossKit.lathe(k + "_hband", PackedVector2Array([Vector2(0.158, -0.035), Vector2(0.165, 0.0), Vector2(0.158, 0.035)]), 8, 1.0, 1.0), iron, Transform3D(head_basis, Vector3(0, 1.32, 0)), IRON_DARK)
	asm.add(BossKit.crystal_mesh(k + "_hspike", 0.045, 0.3, 6, 0.45, 0.1, 0.2), ice, Transform3D(Basis.IDENTITY, Vector3(0, 1.43, 0)), Color(1, 1, 1))
	bake_into(_held, "hammer", asm)
	_held_len = 1.6


func _tick_boss(delta: float) -> void:
	# Frost breath in slow puffs (and a roar of it).
	if _breath != null:
		_breath_t -= delta
		if _action == "roar":
			_breath.emitting = true
		elif _breath_t <= 0.0:
			_breath.emitting = not _breath.emitting
			_breath_t = 0.9 if _breath.emitting else 3.2
		elif not _breath.emitting:
			pass
	for s in _storm:
		if is_instance_valid(s):
			s.amount_ratio = clampf(0.4 + _power * 0.6, 0.0, 1.0)


func _on_boss_phase(new_phase: int) -> void:
	if new_phase >= 3 and _storm.size() < 4:
		var p := fx_point(R.HIPS, Vector3(0, 1.0, 0))
		_storm.append(BossKit.emitter(p, "frost", 70, Vector3(2.4, 1.6, 2.4), Color(0.85, 0.93, 1.0), 0.25, 2.2, 1.0))
		var q := fx_point(R.CHEST, Vector3(0, 1.3, 0))
		_storm.append(BossKit.emitter(q, "shard", 30, Vector3(1.0, 0.8, 1.0), ICE, 0.12, 1.4, 0.6))


func _on_boss_death() -> void:
	if not is_inside_tree():
		return
	var parent := get_parent() as Node3D
	if parent == null:
		return
	var at := global_position + Vector3(0, 3.5, 0)
	ModelKit.burst(parent, at, 120, 2.2, 8.0, 1.2, Color(0.9, 0.97, 1.0), Color(0.4, 0.6, 0.85), 1.8)
	ModelKit.flash_light(parent, at, ICE, 6.0, 22.0, 1.4)


## Asleep on his feet: both hands on the hammer's haft, its head planted in the floor.
func _pose_dormant(t: PackedVector3Array, w: float) -> void:
	t[R.SPINE] = t[R.SPINE].lerp(Vector3(0.18, 0, 0), w)
	t[R.CHEST] = t[R.CHEST].lerp(Vector3(0.1, 0, 0), w)
	t[R.NECK] = t[R.NECK].lerp(Vector3(0.25, 0, 0), w)
	t[R.HEAD] = t[R.HEAD].lerp(Vector3(0.3, 0, 0), w)
	_hips_tgt.y -= 0.03 * w
	_fing[0] = lerpf(_fing[0], 1.4, w)
	_fing[1] = lerpf(_fing[1], 1.45, w)
	_foot[0] += Vector3(-0.08, 0, 0.04) * w
	_foot[1] += Vector3(0.08, 0, 0.04) * w
	hand_goals[1] = [Vector3(0.04, 1.08, -0.42), Vector3.DOWN, Vector3(-1.0, 0.0, 0.35), w]
	hand_goals[0] = [Vector3(-0.05, 1.18, -0.42), Vector3.DOWN, Vector3(1.0, 0.0, 0.35), w]
