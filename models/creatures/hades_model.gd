class_name HadesModel
extends BossHumanoid
## Hades, Lord of the Dead: a towering god in a blackened-bronze Corinthian
## helm whose crest is a sunburst crown of iron spikes burning with soul fire,
## his eyes cold stars in its shadow and a beard of smoke spilling from under
## the cheek guards. A gilded muscle cuirass, layered pauldrons bearing skulls,
## clawed gauntlets, leather pteruges over a floor-length robe whose hem
## dissolves into ghostly smoke, a vast cape, and a bident with a soul caught
## between its prongs. He waits upright, the bident planted at his side.
## Phase 2: the soul fire breaks through cracks in his armour and the crown
## blazes. Phase 3, his true form: he grows taller, the dead circle him in a
## ring of souls and his shoulders and robe burn with spirit flame.

const BRONZE := Color(0.2, 0.19, 0.21)
const BRONZE_LIT := Color(0.3, 0.28, 0.3)
const RUNE_BRONZE := Color(0.22, 0.2, 0.22, 0.0)
const GOLD := Color(0.86, 0.66, 0.32)
const ROBE := Color(0.09, 0.06, 0.1)
const ROBE2 := Color(0.32, 0.06, 0.06)
const CAPE := Color(0.18, 0.03, 0.04)
const LEATHER := Color(0.16, 0.11, 0.09)
const BONE := Color(0.8, 0.76, 0.66)
const SOUL := Color(0.45, 0.78, 1.0)
const SMOKE := Color(0.1, 0.1, 0.16)

var _flames: Array[GPUParticles3D] = []
var _souls: Node3D
var _soul_orbs: Array[Node3D] = []
var _grow := 1.0
var _grow_target := 1.0


## Fraction of each action at which its blow lands (HadesBoss plays the
## action for telegraph / IMPACT so the bident meets the filled warning).
const IMPACT := {"sweep": 0.65, "thrust": 0.55, "smash": 0.6, "summon": 0.56, "pull": 0.55, "nova": 0.44}
## Soul bolt casts (5 bolts, 8 bolts): action lengths in seconds.
const BOLT_TIME := [2.1, 2.76]
## The reaping combination: blows land at these fractions of COMBO_TIME.
const COMBO := [0.28, 0.55, 0.86]
const COMBO_TIME := 2.5


func _init() -> void:
	super({"height": 5.6, "bulk": 1.4, "cloak": true, "cloak_hem": 0.03, "held": "scythe", "eyes": SOUL, "cloak_color": CAPE})
	durations["sweep"] = 1.3
	durations["cast"] = 1.2
	durations["summon"] = 1.8
	durations["teleport"] = 0.9
	# A god's duelling: long reaping sweeps, a double-pronged lunge, soul
	# bolts flung from the off hand, the bident's butt rammed down for the
	# fire pillars, chains of the dead yanked tight, the dead called up, a
	# reaping combination, and the arms raised for the rings of soul fire.
	moves["sweep"] = Moves.sweep(IMPACT["sweep"])
	moves["thrust"] = Moves.thrust(IMPACT["thrust"], 0.5)
	moves["cast"] = Moves.fling(0.5 / BOLT_TIME[0], (0.5 + 4 * 0.22) / BOLT_TIME[0], 5)
	moves["volley"] = Moves.fling(0.5 / BOLT_TIME[1], (0.5 + 7 * 0.22) / BOLT_TIME[1], 8)
	moves["smash"] = Moves.plant(IMPACT["smash"], Vector3(0.22, 1.05, -0.42), Vector3.UP)
	moves["summon"] = Moves.invoke(IMPACT["summon"], 0.08)
	moves["pull"] = Moves.yank(IMPACT["pull"])
	moves["nova"] = Moves.invoke(IMPACT["nova"], 0.2)
	moves["combo"] = Moves.chain([[Moves.sweep(0.7), 0.0, 0.4], [Moves.backhand(0.6), 0.4, 0.65], [Moves.thrust(0.6, 0.5), 0.65, 1.0]])
	moves["teleport"] = _vanish()
	moves["phase"] = Moves.invoke(0.6, 0.3)
	moves["phase"]["shake"] = [[0, 0.0], [0.6, 1.0], [0.85, 0.6], [1, 0.0]]
	moves["hit"] = Moves.flinch()
	moves["roar"] = Moves.bellow(0.35)


## Vanishing: he draws the cape about him with the off arm and sinks into
## the floor's shadow, then rises where he reappears.
func _vanish() -> Dictionary:
	var z := Vector3.ZERO
	return {
		R.UARM_L: [[0, Moves.ARM_L], [0.35, Vector3(1.3, -0.9, -0.2)], [0.7, Vector3(1.3, -0.9, -0.2)], [1, Moves.ARM_L]],
		R.FARM_L: [[0, Vector3(0.3, 0, 0)], [0.35, Vector3(1.9, 0, 0)], [0.7, Vector3(1.9, 0, 0)], [1, Vector3(0.3, 0, 0)]],
		R.SPINE: [[0, z], [0.35, Vector3(-0.3, 0, 0)], [0.6, Vector3(-0.3, 0, 0)], [1, z]],
		R.HEAD: [[0, z], [0.35, Vector3(-0.35, 0, 0)], [1, z]],
		"hips": [[0, z], [0.45, Vector3(0, -0.4, 0)], [0.6, Vector3(0, -0.4, 0)], [1, z]],
		"fing": [[0, 1.2], [1, 1.2]],
	}


func _ember_extents() -> Vector3:
	return Vector3(1.0, 2.6, 0.8)


func _lod_size() -> float:
	return 5.6


func _dress() -> void:
	var k := _kit_key()
	var bronze := BossKit.metal({"rust": 0.0, "wear": 0.35, "grime": 0.45, "roughness": 0.36, "metallic": 0.75, "rune": 1.0,
		"rune_color": SOUL, "rune_energy": 2.5, "rune_scale": 10.0, "pattern_scale": 14.0})
	var robe := BossKit.cloth(ROBE, ROBE2, {"tatter": 0.75, "grime": 0.2})
	var cape := BossKit.cloth(CAPE, Color(0.08, 0.02, 0.03), {"tatter": 0.45, "grime": 0.3})
	var leather := BossKit.leather({"albedo": LEATHER})
	var bone := BossKit.bone()
	var beard := BossKit.fur(Color(0.18, 0.2, 0.3), {"pattern_scale": 22.0, "roughness": 0.7})
	var soul := BossKit.glow(SOUL, 6.0, 0.3)
	var dark := ModelKit.mat(Color(0.01, 0.01, 0.015), AsciiMaterialId.SOLID, 0.9, 0.0, 0.0)
	var skin := BossKit.skin(Color(0.45, 0.48, 0.58), {"albedo": Color(0.55, 0.57, 0.64)})
	_dress_head(k, bronze, beard, soul, dark, skin)
	_dress_torso(k, bronze, leather, bone, soul)
	_dress_arms(k, bronze, bone)
	_dress_legs(k, bronze)
	skinned(BossKit.robe(k + "_robe", _rest, 1.0, 0.0, Vector2(0.23, 0.19), Vector2(0.36, 0.32), 30, 14, -PI, PI, 0.015, 0.02), robe)
	skinned(BossKit.cloak(k + "_cape", body, style, 19, 19, 0.014, 1.55, 0.04), cape)
	# Smoke rolling off the hem, soul fire on the crown.
	var hem := fx_point(R.HIPS, Vector3(0, 0.08, 0.05))
	BossKit.emitter(hem, "smoke", 30, Vector3(1.0, 0.1, 1.0), SMOKE, 2.0, 3.0, 0.5)
	var crown := fx_point(R.HEAD, Vector3(0, 1.95, 0.08))
	_flames.append(BossKit.emitter(crown, "wisp", 40, Vector3(0.6, 0.15, 0.25), SOUL, 0.32, 0.9, 2.2))
	add_light(crown, Vector3(0, -0.5, -0.6), SOUL, 1.8, 11.0)
	var chin := fx_point(R.JAW, Vector3(0, 1.4, -0.16))
	BossKit.emitter(chin, "smoke", 10, Vector3(0.12, 0.05, 0.05), SMOKE, 0.5, 1.6, 0.3)
	# The ring of souls (shown in his true form).
	_souls = Node3D.new()
	_souls.name = "Souls"
	_souls.position = Vector3(0, 1.4, 0) * _s
	_souls.visible = false
	add_child(_souls)
	for i in 7:
		var orb := Node3D.new()
		_souls.add_child(orb)
		var a := TAU * i / 7.0
		orb.position = Vector3(cos(a), 0, sin(a)) * 3.2
		ModelKit.part(orb, ModelKit.sphere(0.22, 10), soul)
		BossKit.emitter(orb, "wisp", 12, Vector3(0.1, 0.1, 0.1), SOUL, 0.35, 0.8, 0.3)
		_soul_orbs.append(orb)


func _dress_head(k: String, bronze: Material, beard: Material, soul: Material, dark: Material, skin: Material) -> void:
	var head := part(R.HEAD)
	# Corinthian helm: dome, brow band, nose guard, long cheek guards leaving a T-shaped opening.
	var dome := PackedVector2Array([Vector2(0.14, 1.7), Vector2(0.145, 1.75), Vector2(0.138, 1.8), Vector2(0.115, 1.845), Vector2(0.07, 1.872), Vector2(0.0, 1.88)])
	head.add(BossKit.lathe(k + "_dome", dome, 24, 0.95, 1.12, false, true), bronze, Transform3D.IDENTITY, BRONZE)
	var back := BossKit.wrap_rows([[1.71, 0.14, 0.15], [1.65, 0.138, 0.15], [1.59, 0.13, 0.14], [1.54, 0.14, 0.15]], PI - 1.9, PI + 1.9, 15)
	head.add(BossKit.plate(k + "_neckguard", back, 0.012, Vector3(0, 1.66, 0)), bronze, Transform3D.IDENTITY, BRONZE)
	var brow := BossKit.wrap_rows([[1.75, 0.142, 0.16, 0.012], [1.73, 0.142, 0.165, 0.02], [1.715, 0.14, 0.162, 0.018]], -1.6, 1.6, 17)
	head.add(BossKit.plate(k + "_brow", brow, 0.012, Vector3(0, 1.72, 0.02)), bronze, Transform3D.IDENTITY, GOLD)
	for sx: float in [-1.0, 1.0]:
		var a0 := 0.17 if sx > 0.0 else -1.62
		var a1 := 1.62 if sx > 0.0 else -0.17
		var cheek := BossKit.wrap_rows([[1.705, 0.14, 0.162, 0.0], [1.67, 0.136, 0.168, 0.0], [1.62, 0.122, 0.162, 0.0], [1.565, 0.105, 0.14, 0.0], [1.53, 0.09, 0.12, 0.0]], a0, a1, 9)
		head.add(BossKit.plate("%s_cheek_%d" % [k, int(sx)], cheek, 0.012, Vector3(0, 1.63, 0.03)), bronze, Transform3D.IDENTITY, BRONZE)
		head.put(ModelKit.sphere(0.018, 8), soul, Vector3(sx * 0.046, 1.7, -0.13), Vector3.ZERO, Vector3(1.5, 0.75, 0.6))
	var nose := BossKit.wrap_rows([[1.72, 0.022, 0.172, 0.0], [1.69, 0.018, 0.18, 0.0], [1.655, 0.014, 0.182, 0.0]], -0.9, 0.9, 5)
	head.add(BossKit.plate(k + "_nose", nose, 0.01, Vector3(0, 1.69, 0)), bronze, Transform3D.IDENTITY, GOLD)
	# Shadow inside the helm, a pale chin and the smoke-dark beard.
	head.put(OrganicMesh.blob(k + "_shadow", Vector3(0.11, 0.1, 0.1), 0.0, 2, 12), dark, Vector3(0, 1.68, -0.04))
	var jaw := part(R.JAW)
	jaw.put(OrganicMesh.blob(k + "_chin", Vector3(0.045, 0.04, 0.04), 0.1, 51, 10), skin, Vector3(0, 1.585, -0.115), Vector3.ZERO, Vector3.ONE, Color(1, 1, 1))
	for i in 9:
		var x := lerpf(-0.09, 0.09, i / 8.0)
		var len := 0.34 + 0.12 * cos((i - 4) * 0.5)
		var root := Vector3(x, 1.56 + absf(x) * 0.4, -0.1 + absf(x) * 0.25)
		var bm := OrganicMesh.bezier("%s_beard_%d" % [k, i], Vector3.ZERO, Vector3(x * 0.3, -len * 0.45, -0.06), Vector3(x * 0.15, -len, -0.02), 0.04, 0.006, 10, 7, 0.6)
		jaw.add(bm, beard, Transform3D(Basis.IDENTITY, root), Color(0.5, 0.55, 0.7).darkened(0.1 * (i % 3)))
	# Sunburst crown: iron spikes fanning from the helm, tipped with soul fire.
	var count := 13
	for i in count:
		var t := float(i) / (count - 1)
		var a := lerpf(-1.25, 1.25, t)
		var h := 0.24 + 0.16 * cos(a * 1.2) - 0.05 * (i % 2)
		var base := Vector3(sin(a) * 0.12, 1.83 + cos(a) * 0.02, 0.06 + absf(sin(a)) * 0.02)
		var dir := Vector3(sin(a) * 0.9, cos(a), 0.15).normalized()
		var sp := OrganicMesh.bezier("%s_ray_%d" % [k, int(h * 1000)], Vector3.ZERO, dir * h * 0.5 + Vector3(0, 0, 0.02), dir * h, 0.022, 0.003, 6, 6)
		head.add(sp, bronze, Transform3D(Basis.IDENTITY, base), BRONZE_LIT)
		head.put(ModelKit.sphere(0.012, 6), soul, base + dir * h * 0.98)
	head.put(BossKit.torus(k + "_crownband", 0.143, 0.014, 28, 6, 1.4), bronze, Vector3(0, 1.8, 0.0), Vector3(-8, 0, 0), Vector3(0.96, 1.0, 1.13), GOLD)


func _dress_torso(k: String, bronze: Material, leather: Material, bone: Material, soul: Material) -> void:
	var chest := part(R.CHEST)
	# Muscle cuirass: sculpted pectorals and a ridged belly in blackened bronze.
	var rows: Array = []
	var spec := [[1.48, 0.2, 0.11, 0.0, 0.0], [1.43, 0.255, 0.16, 0.01, 0.025], [1.36, 0.27, 0.18, 0.012, 0.045], [1.29, 0.262, 0.178, 0.01, 0.03],
		[1.22, 0.24, 0.165, 0.018, 0.0], [1.15, 0.225, 0.16, 0.02, 0.0], [1.08, 0.215, 0.158, 0.015, 0.0]]
	for r: Array in spec:
		var pts := PackedVector3Array()
		for c in 21:
			var a := lerpf(-1.8, 1.8, c / 20.0)
			var pec := float(r[4]) * exp(-pow((absf(a) - 0.5) / 0.32, 2.0))
			var groove := -float(r[3]) * exp(-pow(a / 0.08, 2.0))
			var z := -(cos(a) * float(r[2]) + pec + groove)
			pts.append(Vector3(sin(a) * float(r[1]), float(r[0]), z + 0.02))
		rows.append(pts)
	chest.add(BossKit.plate(k + "_cuirass", rows, 0.028, Vector3(0, 1.27, 0.05)), bronze, Transform3D.IDENTITY, RUNE_BRONZE)
	var back := BossKit.wrap_rows([[1.48, 0.2, 0.11], [1.4, 0.255, 0.155], [1.3, 0.262, 0.16], [1.2, 0.24, 0.155], [1.09, 0.215, 0.15]], PI - 1.5, PI + 1.5, 17, Vector3(0, 0, 0.02))
	chest.add(BossKit.plate(k + "_backplate", back, 0.025, Vector3(0, 1.27, 0.0)), bronze, Transform3D.IDENTITY, BRONZE)
	# Gold edging at the neck and the soul gem over the heart in a bone setting.
	var collar := PackedVector3Array()
	var collar_r := PackedVector2Array()
	for i in 15:
		var a := lerpf(-1.8, 1.8, i / 14.0)
		collar.append(Vector3(sin(a) * 0.205, 1.482, -cos(a) * 0.116 + 0.02))
		collar_r.append(Vector2(0.014, 0.014))
	chest.add(OrganicMesh.sweep(k + "_collar", collar, collar_r, 6), bronze, Transform3D.IDENTITY, GOLD)
	chest.put(OrganicMesh.blob(k + "_gemset", Vector3(0.05, 0.06, 0.02), 0.1, 52, 10), bone, Vector3(0, 1.38, -0.2), Vector3.ZERO, Vector3.ONE, BONE)
	chest.put(BossKit.crystal_mesh(k + "_gem", 0.03, 0.08, 6, 0.4, 0.4), soul, Vector3(0, 1.34, -0.215))
	# Belt with skull clasp; leather pteruges.
	var hips := part(R.HIPS)
	hips.put(BossKit.torus(k + "_belt", 0.218, 0.022, 30, 6, 1.6), bronze, Vector3(0, 1.0, 0.02), Vector3.ZERO, Vector3(1.0, 1.0, 0.82), GOLD)
	hips.put(OrganicMesh.blob(k + "_skull", Vector3(0.04, 0.046, 0.036), 0.1, 53, 10), bone, Vector3(0, 1.0, -0.17), Vector3.ZERO, Vector3.ONE, BONE)
	for i in 14:
		var a := TAU * i / 14.0
		var front := cos(a - PI)
		var path := PackedVector3Array()
		var widths := PackedFloat32Array()
		var dir := Vector3(sin(a), 0, cos(a))
		for j in 4:
			var t := j / 3.0
			path.append(Vector3(dir.x * (0.225 + t * 0.03), 0.99 - t * 0.2, dir.z * (0.19 + t * 0.03) + 0.02))
			widths.append(0.036)
		var strip := BossKit.ribbon("%s_pteryx" % k, path, widths, Vector3(dir.z, 0, -dir.x), 0.01) if i == 0 else BossKit.ribbon("%s_pteryx_%d" % [k, i], path, widths, Vector3(dir.z, 0, -dir.x), 0.01)
		hips.add(strip, leather, Transform3D.IDENTITY, Color(1, 1, 1).darkened(0.15 * (i % 2)))
		hips.put(ModelKit.sphere(0.01, 5), bronze, path[3] + dir * 0.008, Vector3.ZERO, Vector3.ONE, GOLD)
		var _u := front


func _dress_arms(k: String, bronze: Material, bone: Material) -> void:
	for side: float in [-1.0, 1.0]:
		var o := 0 if side < 0.0 else 5
		var sh := _rest[R.UARM_L + o]
		var el := _rest[R.FARM_L + o]
		var wr := _rest[R.HAND_L + o]
		var fi := _rest[R.FING_L + o]
		var ua := part(R.UARM_L + o)
		pauldron(ua, bronze, "h", sh + Vector3(side * 0.02, 0.03, 0.0), side, 0.21, 3, BRONZE, GOLD, bronze)
		ua.put(OrganicMesh.blob(k + "_pskull", Vector3(0.045, 0.052, 0.042), 0.1, 54, 10), bone, sh + Vector3(side * 0.2, 0.06, -0.02), Vector3(0, side * -70, side * 30), Vector3.ONE, BONE)
		for i in 3:
			var sp := OrganicMesh.bezier("%s_pspike_%d" % [k, i], Vector3.ZERO, Vector3(side * 0.03, 0.07, 0.0), Vector3(side * 0.08, 0.13 + i * 0.03, 0.03), 0.02, 0.003, 6, 6)
			ua.add(sp, bronze, Transform3D(Basis.IDENTITY, sh + Vector3(side * (0.05 + i * 0.04), 0.17 - i * 0.03, 0.04)), BRONZE_LIT)
		plate_tube(ua, bronze, "rere", sh + Vector3(0, -0.1, 0), el + Vector3(0, 0.03, 0), 0.068, 0.06, BRONZE)
		var fa := part(R.FARM_L + o)
		plate_tube(fa, bronze, "vamb", el + Vector3(0, -0.02, 0), wr + Vector3(0, 0.02, 0), 0.06, 0.053, RUNE_BRONZE)
		for b in 3:
			var p := el.lerp(wr, 0.1 + b * 0.4)
			fa.put(BossKit.torus(k + "_vring", 0.062 - b * 0.003, 0.008, 16, 5), bronze, p, Vector3.ZERO, Vector3.ONE, GOLD)
		gauntlet(bronze, "h", side, 0.05, BRONZE)
		var fing := part(R.FING_L + o)
		for f in 4:
			var z := lerpf(-0.03, 0.03, f / 3.0)
			var claw := OrganicMesh.bezier("%s_claw" % k, Vector3.ZERO, Vector3(0, -0.03, -0.005), Vector3(-side * 0.01, -0.055, -0.02), 0.01, 0.001, 5, 5)
			fing.add(claw, bronze, Transform3D(Basis.IDENTITY, fi + Vector3(0, -0.055, z)), GOLD)


func _dress_legs(k: String, bronze: Material) -> void:
	for side: float in [-1.0, 1.0]:
		var o := 0 if side < 0.0 else 4
		var kn := _rest[R.SHIN_L + o]
		var an := _rest[R.FOOT_L + o]
		var to := _rest[R.TOE_L + o]
		var sp := part(R.SHIN_L + o)
		var gr := BossKit.wrap_rows([[0.02, 0.07, 0.075, 0.02], [-0.12, 0.074, 0.078, 0.024], [-0.28, 0.062, 0.066, 0.016], [-0.4, 0.056, 0.062, 0.01]], -PI, PI, 19)
		sp.add(BossKit.plate(k + "_greave", gr, 0.01, Vector3(0, -0.2, 0)), bronze, Transform3D(Basis.IDENTITY, kn + Vector3(0, -0.02, 0.0)), BRONZE)
		var fp := part(R.FOOT_L + o)
		fp.put(BossKit.shell(k + "_boot", Vector3(0.065, 0.06, 0.12), -110, 110, 0, 95, 0.012, 12, 5), bronze, an.lerp(to, 0.45) + Vector3(0, 0.02, 0), Vector3(-6, 0, 0), Vector3.ONE, BRONZE)


## The bident: a long black shaft ringed in gold, two hooked prongs with a
## soul held burning between them, and a spiked butt.
func _build_held(item_id: String) -> void:
	_held_id = item_id
	if _held != null:
		_held.queue_free()
		_held = null
	if item_id == "":
		return
	_held = Node3D.new()
	_held.name = "Bident"
	grip_r.add_child(_held)
	var k := _kit_key()
	var bronze := BossKit.metal({"wear": 0.3, "grime": 0.3, "roughness": 0.32, "rune": 1.0, "rune_color": SOUL, "rune_energy": 3.0, "rune_scale": 14.0})
	var soul := BossKit.glow(SOUL, 7.0, 0.4)
	var asm := BossKit.assembly()
	var shaft := PackedVector2Array([Vector2(0.022, -0.95), Vector2(0.026, -0.9), Vector2(0.024, 0.5), Vector2(0.026, 1.4), Vector2(0.03, 1.48)])
	asm.add(BossKit.lathe(k + "_shaft", shaft, 10), bronze, Transform3D.IDENTITY, Color(0.12, 0.11, 0.13))
	for y: float in [-0.9, -0.2, 0.2, 0.9, 1.45]:
		asm.add(BossKit.torus(k + "_sring", 0.03, 0.008, 12, 5), bronze, Transform3D(Basis.IDENTITY, Vector3(0, y, 0)), GOLD)
	asm.add(OrganicMesh.bezier(k + "_butt", Vector3.ZERO, Vector3(0, -0.06, 0), Vector3(0, -0.14, 0), 0.026, 0.002, 5, 6), bronze, Transform3D(Basis.IDENTITY, Vector3(0, -0.95, 0)), GOLD)
	# Head: a collar, then two prongs curving out and up.
	var collar := PackedVector2Array([Vector2(0.03, 1.48), Vector2(0.05, 1.52), Vector2(0.06, 1.56), Vector2(0.045, 1.6)])
	asm.add(BossKit.lathe(k + "_hcollar", collar, 12), bronze, Transform3D.IDENTITY, GOLD)
	for sx: float in [-1.0, 1.0]:
		var prong := OrganicMesh.bezier("%s_prong_%d" % [k, int(sx)], Vector3.ZERO, Vector3(sx * 0.16, 0.12, 0), Vector3(sx * 0.1, 0.5, 0), 0.03, 0.004, 12, 7, 0.7)
		asm.add(prong, bronze, Transform3D(Basis.IDENTITY, Vector3(0, 1.58, 0)), Color(0.16, 0.15, 0.17))
		var barb := OrganicMesh.bezier("%s_barb_%d" % [k, int(sx)], Vector3.ZERO, Vector3(sx * 0.04, -0.02, 0), Vector3(sx * 0.07, -0.07, 0), 0.016, 0.002, 5, 5)
		asm.add(barb, bronze, Transform3D(Basis.IDENTITY, Vector3(sx * 0.14, 1.9, 0)), GOLD)
	asm.add(ModelKit.sphere(0.06, 12), soul, Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 1.4, 1.0)), Vector3(0, 1.82, 0)))
	bake_into(_held, "bident", asm)
	var fx := Node3D.new()
	fx.position = Vector3(0, 1.82, 0)
	fx.scale = Vector3.ONE / _s
	_held.add_child(fx)
	_flames.append(BossKit.emitter(fx, "wisp", 18, Vector3(0.1, 0.15, 0.1), SOUL, 0.22, 0.7, 1.0))
	_held_len = 2.0


func _tick_boss(delta: float) -> void:
	for f in _flames:
		if is_instance_valid(f):
			f.amount_ratio = clampf(0.45 + _power * 0.55, 0.0, 1.0)
	_grow = move_toward(_grow, _grow_target, delta * 0.12)
	if absf(scale.x - _grow) > 0.0005:
		scale = Vector3.ONE * _grow
	if _souls != null and _souls.visible:
		_souls.rotation.y += delta * 0.9
		for i in _soul_orbs.size():
			_soul_orbs[i].position.y = sin(_time * 1.7 + i) * 0.6


func _on_boss_phase(new_phase: int) -> void:
	if new_phase >= 2 and _flames.size() < 4:
		for side: float in [-1.0, 1.0]:
			var o := 0 if side < 0.0 else 5
			var p := fx_point(R.UARM_L + o, _rest[R.UARM_L + o] + Vector3(side * 0.08, 0.2, 0))
			_flames.append(BossKit.emitter(p, "wisp", 22, Vector3(0.2, 0.06, 0.2), SOUL, 0.3, 0.8, 1.6))
	if new_phase >= 3:
		_grow_target = 1.16
		if _souls != null:
			_souls.visible = true
		var hem := fx_point(R.HIPS, Vector3(0, 0.2, 0.0))
		_flames.append(BossKit.emitter(hem, "wisp", 50, Vector3(1.0, 0.2, 1.0), SOUL, 0.4, 1.0, 1.8))


func _on_boss_death() -> void:
	if not is_inside_tree():
		return
	if _souls != null:
		_souls.visible = false
	var parent := get_parent() as Node3D
	if parent == null:
		return
	var at := global_position + Vector3(0, 3.2, 0)
	ModelKit.burst(parent, at, 160, 2.0, 10.0, 1.2, SOUL.lightened(0.5), Color(0.2, 0.3, 0.8), 2.2)
	ModelKit.flash_light(parent, at, SOUL, 10.0, 26.0, 1.6)


## Waiting upright and proud, the bident planted beside him, left hand on his belt.
func _pose_dormant(t: PackedVector3Array, w: float) -> void:
	t[R.HEAD] = t[R.HEAD].lerp(Vector3(-0.08, 0, 0), w)
	t[R.CHEST] = t[R.CHEST].lerp(Vector3(-0.05, 0, 0), w)
	_fing[1] = lerpf(_fing[1], 1.45, w)
	_foot[0] += Vector3(-0.04, 0, 0.04) * w
	_foot[1] += Vector3(0.06, 0, -0.02) * w
	hand_goals[1] = [Vector3(0.36, 1.08, -0.14), Vector3.UP, Vector3(-0.3, 0.0, -1.0), w]
	hand_goals[0] = [Vector3(-0.2, 0.98, -0.12), Vector3(0, -1, 0.3), Vector3(1.0, 0.0, 0.0), w * 0.8]
