class_name WardenModel
extends BossHumanoid
## The Warden of the Silent Crypt: a towering undead knight in blackened,
## rust-eaten gothic plate - creased breastplate, flanged pauldrons, a great
## helm with a deep visor slit, a crown of bone spikes and swept horns - with
## a soul fire leaking through a crack in its chest and the slit of its helm,
## a tattered surcoat and floor-length cloak, a rune-etched greatsword and a
## soul lantern swinging from its belt. While nobody disturbs the crypt it
## stands vigil, head bowed, hands folded on the pommel of its planted blade;
## it wakes when the fight begins. Phase 2 wakes the runes, phase 3 sets its
## shoulders and helm burning with soul fire.

const SOUL := Color(0.42, 1.0, 0.62)
const IRON := Color(0.36, 0.36, 0.36)
const DARK_IRON := Color(0.22, 0.22, 0.22)
const BRONZE := Color(0.5, 0.4, 0.27)
const RUNE_IRON := Color(0.36, 0.37, 0.38, 0.0)   # iron that carries runes
const CLOTH := Color(0.12, 0.14, 0.11)
const LEATHER := Color(0.2, 0.14, 0.1)
const BONE := Color(0.74, 0.7, 0.6)

var _lantern: Node3D
var _lantern_swing := Vector2.ZERO
var _lantern_vel := Vector2.ZERO
var _prev_pos := Vector3.INF
var _soul_flames: Array[GPUParticles3D] = []


func _init() -> void:
	super({"height": 5.0, "bulk": 1.35, "hunch": -0.04, "cloak": true, "cloak_hem": 0.1, "tattered": true,
		"held": "warden_blade", "eyes": SOUL, "cloth": CLOTH, "cloak_color": CLOTH})
	durations["sweep"] = 1.3
	durations["slam"] = 1.4


func _ember_extents() -> Vector3:
	return Vector3(0.9, 2.2, 0.7)


func _lod_size() -> float:
	return 5.0


func _dress() -> void:
	var iron := BossKit.metal({"rust": 0.6, "wear": 0.4, "grime": 0.7, "roughness": 0.5, "rune": 1.0, "rune_color": SOUL, "rune_energy": 2.0, "rune_scale": 12.0})
	var cloth := BossKit.cloth(CLOTH, Color(0.2, 0.19, 0.14), {"tatter": 0.6, "grime": 0.75})
	var leather := BossKit.leather()
	var bone := BossKit.bone()
	var soul := BossKit.glow(SOUL, 5.0, 0.25)
	var dark := ModelKit.mat(Color(0.01, 0.012, 0.01), AsciiMaterialId.SOLID, 0.9, 0.0, 0.0)
	var k := _kit_key()
	_dress_head(iron, bone, soul, dark, k)
	_dress_torso(iron, leather, bone, soul, k)
	_dress_arms(iron, bone, k)
	_dress_legs(iron, k)
	# Surcoat panels front and back (skinned to the legs) and the cloak.
	skinned(BossKit.robe(k + "_tabard_f", _rest, 0.93, 0.36, Vector2(0.19, 0.16), Vector2(0.2, 0.19), 8, 10, PI * 0.8, PI * 1.2, 0.01), cloth)
	skinned(BossKit.robe(k + "_tabard_b", _rest, 0.93, 0.22, Vector2(0.2, 0.17), Vector2(0.23, 0.2), 8, 10, -PI * 0.22, PI * 0.22, 0.01), cloth)
	skinned(BossKit.cloak(k + "_cloak", body, style, 17, 17, 0.012, 1.3, 0.05), cloth)
	_dress_lantern(iron, bone, soul, k)
	# Soul light in the chest and wisps drifting from the visor.
	var cfx := fx_point(R.CHEST, Vector3(0.08, 1.24, -0.2))
	add_light(cfx, Vector3(0, 0, -0.6), SOUL, 0.5, 4.0)
	var hfx := fx_point(R.HEAD, Vector3(0, 1.72, -0.13))
	_soul_flames.append(BossKit.emitter(hfx, "wisp", 8, Vector3(0.1, 0.02, 0.03), SOUL, 0.12, 1.4, 0.5))
	# A low ghost mist around the feet.
	var mist := fx_point(R.HIPS, Vector3(0, 0.25, 0.1))
	BossKit.emitter(mist, "smoke", 16, Vector3(0.9, 0.15, 0.9), Color(0.12, 0.2, 0.15), 1.8, 3.2, 0.2)


func _dress_head(iron: Material, bone: Material, soul: Material, dark: Material, k: String) -> void:
	var head := part(R.HEAD)
	# Skull of the great helm.
	var helm := PackedVector2Array([Vector2(0.122, 1.57), Vector2(0.134, 1.62), Vector2(0.144, 1.69), Vector2(0.146, 1.75),
		Vector2(0.134, 1.81), Vector2(0.104, 1.852), Vector2(0.058, 1.874), Vector2(0.0, 1.88)])
	head.add(BossKit.lathe(k + "_helm", helm, 24, 0.95, 1.12, true, false), iron, Transform3D.IDENTITY, IRON)
	# Brow: a creased plate jutting over the slit.
	var brow := BossKit.wrap_rows([[1.775, 0.15, 0.158, 0.012], [1.75, 0.152, 0.17, 0.02], [1.728, 0.15, 0.176, 0.026], [1.72, 0.146, 0.17, 0.024]], -1.45, 1.45, 17)
	head.add(BossKit.plate(k + "_brow", brow, 0.012, Vector3(0, 1.72, 0.02)), iron, Transform3D.IDENTITY, DARK_IRON)
	# Bevor: the face guard below the slit, creased, with breaths.
	var bevor := BossKit.wrap_rows([[1.698, 0.146, 0.172, 0.03], [1.66, 0.14, 0.17, 0.045], [1.62, 0.128, 0.158, 0.05], [1.58, 0.115, 0.14, 0.04], [1.55, 0.12, 0.132, 0.025]], -1.5, 1.5, 17)
	head.add(BossKit.plate(k + "_bevor", bevor, 0.012, Vector3(0, 1.64, 0.02)), iron, Transform3D.IDENTITY, IRON)
	# The slit: darkness with two cold soul lights behind it.
	head.put(OrganicMesh.blob(k + "_slit", Vector3(0.125, 0.02, 0.06), 0.0, 2, 12), dark, Vector3(0, 1.709, -0.115))
	for sx: float in [-1.0, 1.0]:
		head.put(ModelKit.sphere(0.016, 8), soul, Vector3(sx * 0.044, 1.709, -0.142), Vector3.ZERO, Vector3(1.5, 0.65, 0.6))
		for i in 4:
			head.put(ModelKit.sphere(0.0075, 6), dark, Vector3(sx * (0.028 + i * 0.019), 1.645 - i * 0.006, -0.178 + i * 0.012))
	# Comb ridge over the skull.
	var crest := PackedVector3Array()
	var crest_r := PackedVector2Array()
	for i in 9:
		var a := lerpf(-0.9, 1.3, i / 8.0)
		crest.append(Vector3(0, 1.72 + cos(a) * 0.162, -sin(a) * 0.178))
		crest_r.append(Vector2(0.008, 0.03 * sin(PI * i / 8.0) + 0.005))
	head.add(OrganicMesh.sweep(k + "_crest", crest, crest_r, 6), iron, Transform3D.IDENTITY, DARK_IRON)
	# Crown of bone spikes on a bronze circlet.
	head.put(BossKit.torus(k + "_circlet", 0.149, 0.012, 30, 6, 1.7), iron, Vector3(0, 1.8, 0.0), Vector3.ZERO, Vector3(0.96, 1.0, 1.13), BRONZE)
	for i in 11:
		var a := TAU * i / 11.0 + 0.1
		var front := 1.0 - absf(angle_difference(a, PI * 1.5)) / PI
		var h := 0.06 + 0.13 * front * front
		var base := Vector3(cos(a) * 0.142, 1.8, sin(a) * 0.162)
		var out := Vector3(cos(a), 0, sin(a))
		var sp := OrganicMesh.bezier("%s_cspike_%d" % [k, int(h * 1000)], Vector3.ZERO, Vector3(0, h * 0.6, 0) + out * h * 0.08, Vector3(0, h, 0) + out * h * 0.28, 0.017, 0.002, 6, 6)
		head.add(sp, bone, Transform3D(Basis.IDENTITY, base), BONE)
	# Swept horns.
	for sx: float in [-1.0, 1.0]:
		var hm := OrganicMesh.bezier("%s_horn_%d" % [k, int(sx)], Vector3.ZERO, Vector3(sx * 0.17, 0.06, 0.08), Vector3(sx * 0.24, 0.24, 0.26), 0.036, 0.004, 14, 8)
		head.add(hm, bone, Transform3D(Basis.IDENTITY, Vector3(sx * 0.128, 1.765, 0.03)), Color(0.36, 0.32, 0.27))
		head.put(BossKit.torus(k + "_hornring", 0.036, 0.009, 12, 5), iron, Vector3(sx * 0.146, 1.77, 0.035), Vector3(0, 0, sx * 70), Vector3.ONE, BRONZE)
	# Gorget.
	var gorget := PackedVector2Array([Vector2(0.21, 1.42), Vector2(0.18, 1.46), Vector2(0.14, 1.51), Vector2(0.118, 1.555), Vector2(0.122, 1.575)])
	part(R.NECK).add(BossKit.lathe(k + "_gorget", gorget, 22, 1.12, 1.0), iron, Transform3D.IDENTITY, DARK_IRON)


func _dress_torso(iron: Material, leather: Material, bone: Material, soul: Material, k: String) -> void:
	var chest := part(R.CHEST)
	# Gothic breastplate: creased down the middle, broad at the chest, nipped at the waist.
	var breast := BossKit.wrap_rows([[1.47, 0.2, 0.1, 0.0], [1.42, 0.25, 0.15, 0.02], [1.34, 0.265, 0.175, 0.045], [1.25, 0.25, 0.18, 0.06],
		[1.16, 0.22, 0.168, 0.05], [1.09, 0.2, 0.152, 0.035]], -1.75, 1.75, 21, Vector3(0, 0, 0.02))
	chest.add(BossKit.plate(k + "_breast", breast, 0.025, Vector3(0, 1.27, 0.05)), iron, Transform3D.IDENTITY, IRON)
	var back := BossKit.wrap_rows([[1.47, 0.2, 0.1], [1.4, 0.25, 0.15], [1.3, 0.262, 0.165], [1.2, 0.24, 0.16], [1.1, 0.205, 0.15]], PI - 1.5, PI + 1.5, 17, Vector3(0, 0, 0.02))
	chest.add(BossKit.plate(k + "_back", back, 0.025, Vector3(0, 1.27, 0.0)), iron, Transform3D.IDENTITY, DARK_IRON)
	# A rolled bronze edge along the neck opening, rune-etched plates over the heart.
	var collar := PackedVector3Array()
	var collar_r := PackedVector2Array()
	for i in 13:
		var a := lerpf(-1.75, 1.75, i / 12.0)
		collar.append(Vector3(sin(a) * 0.205, 1.472, -cos(a) * 0.105 + 0.02))
		collar_r.append(Vector2(0.012, 0.012))
	chest.add(OrganicMesh.sweep(k + "_collar", collar, collar_r, 6), iron, Transform3D.IDENTITY, BRONZE)
	# The crack: jagged glowing seams with soul light behind them.
	var crack_pts := [Vector3(-0.04, 1.4, -0.168), Vector3(-0.07, 1.34, -0.19), Vector3(-0.05, 1.28, -0.208), Vector3(-0.1, 1.22, -0.196), Vector3(-0.08, 1.16, -0.18)]
	for i in crack_pts.size() - 1:
		var a: Vector3 = crack_pts[i]
		var b: Vector3 = crack_pts[i + 1]
		chest.add(OrganicMesh.bezier("%s_crack_%d" % [k, i], Vector3.ZERO, (b - a) * 0.5 + Vector3(0, 0, -0.003), b - a, 0.007, 0.005, 3, 5), soul, Transform3D(Basis.IDENTITY, a))
	chest.add(OrganicMesh.bezier(k + "_crack_b", Vector3.ZERO, Vector3(-0.03, -0.01, -0.004), Vector3(-0.055, 0.02, 0.0), 0.005, 0.003, 3, 5), soul, Transform3D(Basis.IDENTITY, Vector3(-0.07, 1.34, -0.19)))
	# Belly lames (spine bone) under the breastplate.
	var spine := part(R.SPINE)
	for i in 3:
		var y := 1.075 - i * 0.04
		var lame := BossKit.wrap_rows([[y + 0.03, 0.198 - i * 0.004, 0.15, 0.03], [y - 0.01, 0.196 - i * 0.004, 0.152, 0.03], [y - 0.035, 0.2 - i * 0.002, 0.155, 0.028]], -1.8, 1.8, 17, Vector3(0, 0, 0.02))
		spine.add(BossKit.plate("%s_belly_%d" % [k, i], lame, 0.015, Vector3(0, y, 0.05)), iron, Transform3D.IDENTITY, IRON if i % 2 == 0 else DARK_IRON)
	# Sword belt with a skull boss.
	var hips := part(R.HIPS)
	hips.put(BossKit.torus(k + "_belt", 0.215, 0.02, 30, 6, 1.7), leather, Vector3(0, 0.955, 0.02), Vector3.ZERO, Vector3(1.0, 1.0, 0.8), LEATHER)
	hips.put(OrganicMesh.blob(k + "_skullbuckle", Vector3(0.036, 0.04, 0.03), 0.1, 7, 10), bone, Vector3(0, 0.958, -0.158), Vector3.ZERO, Vector3.ONE, BONE)
	# Faulds: three lames flaring over the hips.
	for i in 3:
		var y0 := 0.94 - i * 0.05
		var prof := PackedVector2Array([Vector2(0.215 + i * 0.012, y0), Vector2(0.236 + i * 0.016, y0 - 0.05), Vector2(0.242 + i * 0.016, y0 - 0.07)])
		hips.add(BossKit.lathe("%s_fauld_%d" % [k, i], prof, 24, 1.0, 0.8), iron, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.02)), IRON if i % 2 == 0 else DARK_IRON)


func _dress_arms(iron: Material, bone: Material, k: String) -> void:
	for side: float in [-1.0, 1.0]:
		var o := 0 if side < 0.0 else 5
		var sh := _rest[R.UARM_L + o]
		var el := _rest[R.FARM_L + o]
		var wr := _rest[R.HAND_L + o]
		var ua := part(R.UARM_L + o)
		pauldron(ua, iron, "w", sh + Vector3(side * 0.015, 0.03, 0.0), side, 0.2, 3, IRON, BRONZE, iron)
		# Haute-piece: a flange standing up on the inner edge of the pauldron.
		var flange := BossKit.wrap_rows([[0.13, 0.11, 0.1], [0.08, 0.13, 0.12], [0.03, 0.14, 0.13]], -1.1, 1.1, 11)
		ua.add(BossKit.plate("%s_flange" % k, flange, 0.012, Vector3(0, -0.2, 0.3)), iron, Transform3D(Basis(Vector3.UP, side * PI * 0.5) * Basis(Vector3.FORWARD, side * 0.12), sh + Vector3(-side * 0.02, 0.1, 0.0)), DARK_IRON)
		# Bone spikes along the pauldron crown.
		for i in 3:
			var sp := OrganicMesh.bezier("%s_pspike_%d" % [k, i], Vector3.ZERO, Vector3(side * 0.02, 0.06 + i * 0.012, 0.0), Vector3(side * 0.055, 0.12 + i * 0.022, 0.02), 0.022, 0.003, 6, 6)
			ua.add(sp, bone, Transform3D(Basis.IDENTITY, sh + Vector3(side * (0.07 + i * 0.035), 0.165 - i * 0.022, -0.06 + i * 0.06)), BONE)
		plate_tube(ua, iron, "rere", sh + Vector3(0, -0.09, 0), el + Vector3(0, 0.03, 0), 0.07, 0.062, IRON)
		var fa := part(R.FARM_L + o)
		fa.put(BossKit.shell(k + "_couter", Vector3(0.07, 0.07, 0.072), -120, 120, 0, 110, 0.012, 12, 6), iron, el + Vector3(0, 0.0, 0.03), Vector3(-90, 0, 0), Vector3.ONE, DARK_IRON)
		fa.put(BossKit.shell(k + "_couter_fan", Vector3(0.1, 0.07, 0.03), -80, 80, 20, 120, 0.01, 10, 4), iron, el + Vector3(side * 0.05, 0.0, 0.03), Vector3(0, side * -90, 0), Vector3.ONE, IRON)
		plate_tube(fa, iron, "vamb", el + Vector3(0, -0.03, 0), wr + Vector3(0, 0.02, 0), 0.06, 0.054, RUNE_IRON)
		gauntlet(iron, "w", side, 0.05, DARK_IRON)


func _dress_legs(iron: Material, k: String) -> void:
	for side: float in [-1.0, 1.0]:
		var o := 0 if side < 0.0 else 4
		var th := _rest[R.THIGH_L + o]
		var kn := _rest[R.SHIN_L + o]
		var an := _rest[R.FOOT_L + o]
		var to := _rest[R.TOE_L + o]
		var tp := part(R.THIGH_L + o)
		# Tassets: two plates hanging over the front of the thigh.
		for i in 2:
			var tas := BossKit.wrap_rows([[0.0, 0.11, 0.1, 0.01], [-0.06, 0.115, 0.105, 0.015], [-0.12, 0.112, 0.1, 0.012]], -1.3, 1.3, 11)
			tp.add(BossKit.plate("%s_tasset" % k, tas, 0.012, Vector3(0, -0.06, 0.1)), iron, Transform3D(Basis(Vector3.RIGHT, -0.12), th + Vector3(side * 0.012, -0.02 - i * 0.1, -0.005)), IRON if i == 0 else DARK_IRON)
		plate_tube(tp, iron, "cuisse", th + Vector3(0, -0.12, 0), kn + Vector3(0, 0.06, 0), 0.088, 0.072, IRON, 1.0, 1.05)
		var sp := part(R.SHIN_L + o)
		var cop := BossKit.wrap_rows([[0.07, 0.06, 0.062, 0.006], [0.03, 0.072, 0.078, 0.022], [-0.01, 0.074, 0.082, 0.03], [-0.05, 0.066, 0.074, 0.02], [-0.085, 0.058, 0.064, 0.008]], -1.35, 1.35, 13)
		sp.add(BossKit.plate(k + "_poleyn", cop, 0.012, Vector3(0, 0, 0.05)), iron, Transform3D(Basis.IDENTITY, kn + Vector3(0, 0.0, -0.01)), DARK_IRON)
		var wing := BossKit.wrap_rows([[0.05, 0.03, 0.02], [0.0, 0.05, 0.03], [-0.05, 0.03, 0.02]], -1.2, 1.2, 9)
		sp.add(BossKit.plate(k + "_poleyn_wing", wing, 0.008, Vector3(0, 0, 0.05)), iron, Transform3D(Basis(Vector3.UP, -side * PI * 0.5), kn + Vector3(side * 0.06, 0.0, -0.005)), IRON)
		# Greave: a creased shell round the shin.
		var gr := BossKit.wrap_rows([[0.0, 0.068, 0.07, 0.012], [-0.12, 0.072, 0.074, 0.016], [-0.26, 0.062, 0.066, 0.012], [-0.38, 0.056, 0.062, 0.008]], -PI, PI, 19)
		sp.add(BossKit.plate(k + "_greave", gr, 0.01, Vector3(0, -0.2, 0)), iron, Transform3D(Basis.IDENTITY, kn + Vector3(0, -0.05, 0.0)), IRON)
		var fp := part(R.FOOT_L + o)
		for i in 3:
			var t := float(i) / 3.0
			var c := an.lerp(to, t) + Vector3(0, 0.045 - t * 0.02, 0)
			fp.put(BossKit.shell("%s_sabaton_%d" % [k, i], Vector3(0.062 - i * 0.004, 0.05, 0.068), -100, 100, 0, 95, 0.01, 10, 4), iron, c, Vector3(-10, 0, 0), Vector3.ONE, IRON if i % 2 == 0 else DARK_IRON)
		part(R.TOE_L + o).put(BossKit.shell(k + "_toecap", Vector3(0.052, 0.038, 0.072), -100, 100, 0, 95, 0.01, 10, 4), iron, to + Vector3(0, 0.02, -0.01), Vector3(-15, 0, 0), Vector3.ONE, DARK_IRON)


func _dress_lantern(iron: Material, bone: Material, soul: Material, k: String) -> void:
	_lantern = pivot(R.HIPS, Vector3(-0.25, 0.92, -0.07), "Lantern")
	var lan := BossKit.assembly()
	BossKit.chain(lan, iron, Vector3.ZERO, Vector3(0, -0.15, 0), 0.03, DARK_IRON)
	var cage_top := PackedVector2Array([Vector2(0.068, -0.19), Vector2(0.062, -0.175), Vector2(0.03, -0.163), Vector2(0.01, -0.156)])
	lan.add(BossKit.lathe(k + "_lan_top", cage_top, 10, 1.0, 1.0, true, false), iron, Transform3D.IDENTITY, DARK_IRON)
	lan.add(BossKit.torus(k + "_lan_ring", 0.012, 0.004, 10, 4), iron, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, -0.156, 0)), DARK_IRON)
	var cage_bot := PackedVector2Array([Vector2(0.0, -0.36), Vector2(0.03, -0.355), Vector2(0.06, -0.335), Vector2(0.066, -0.325)])
	lan.add(BossKit.lathe(k + "_lan_bot", cage_bot, 10, 1.0, 1.0, false, true), iron, Transform3D.IDENTITY, DARK_IRON)
	for i in 6:
		var a := TAU * i / 6.0
		var p0 := Vector3(cos(a) * 0.06, -0.19, sin(a) * 0.06)
		var p1 := Vector3(cos(a) * 0.06, -0.325, sin(a) * 0.06)
		lan.add(OrganicMesh.bezier("%s_lan_bar" % k, Vector3.ZERO, (p1 - p0) * 0.5 + Vector3(cos(a), 0, sin(a)) * 0.012, p1 - p0, 0.006, 0.006, 4, 4), iron, Transform3D(Basis.IDENTITY, p0), DARK_IRON)
	lan.add(ModelKit.sphere(0.036, 10), soul, Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 1.5, 1.0)), Vector3(0, -0.262, 0)))
	lan.add(OrganicMesh.blob(k + "_lan_skull", Vector3(0.022, 0.026, 0.024), 0.08, 9, 8), bone, Transform3D(Basis.IDENTITY, Vector3(0, -0.308, 0)), BONE)
	bake_into(_lantern, "lantern", lan)
	var lfx := Node3D.new()
	lfx.position = Vector3(0, -0.262, 0)
	lfx.scale = Vector3.ONE / _s
	_lantern.add_child(lfx)
	add_light(lfx, Vector3.ZERO, SOUL, 1.3, 7.0)
	_soul_flames.append(BossKit.emitter(lfx, "wisp", 12, Vector3(0.05, 0.05, 0.05), SOUL, 0.1, 1.2, 0.45))


## The great blade replaces the item: a notched, rune-etched greatsword.
func _build_held(item_id: String) -> void:
	_held_id = item_id
	if _held != null:
		_held.queue_free()
		_held = null
	if item_id == "":
		return
	_held = Node3D.new()
	_held.name = "Greatsword"
	grip_r.add_child(_held)
	var k := _kit_key()
	var iron := BossKit.metal({"rust": 0.45, "wear": 0.6, "grime": 0.55, "roughness": 0.45, "rune": 1.0, "rune_color": SOUL, "rune_energy": 2.2, "rune_scale": 16.0})
	var leather := BossKit.leather()
	var bone := BossKit.bone()
	var asm := BossKit.assembly()
	var blade_prof := [[0.0, 0.082, 0.014], [0.08, 0.078, 0.013], [0.6, 0.07, 0.011], [0.88, 0.058, 0.009], [0.97, 0.026, 0.006], [1.0, 0.002, 0.002]]
	asm.add(BossKit.blade(k + "_blade", 1.28, blade_prof, 0.7), iron, Transform3D(Basis.IDENTITY, Vector3(0, 0.2, 0)), Color(0.48, 0.5, 0.52))
	# A rune-etched fuller inlay.
	asm.add(BossKit.blade(k + "_inlay", 0.9, [[0.0, 0.022, 0.0135], [0.9, 0.018, 0.0125], [1.0, 0.002, 0.011]], 0.0), iron, Transform3D(Basis.IDENTITY, Vector3(0, 0.28, 0)), Color(0.36, 0.38, 0.4, 0.0))
	# Crossguard with down-swept ends and a skull boss.
	var guard := PackedVector3Array([Vector3(-0.2, 0.12, 0), Vector3(-0.15, 0.17, 0), Vector3(-0.07, 0.195, 0), Vector3(0, 0.2, 0),
		Vector3(0.07, 0.195, 0), Vector3(0.15, 0.17, 0), Vector3(0.2, 0.12, 0)])
	var guard_r := PackedVector2Array([Vector2(0.012, 0.012), Vector2(0.02, 0.02), Vector2(0.024, 0.024), Vector2(0.028, 0.03), Vector2(0.024, 0.024), Vector2(0.02, 0.02), Vector2(0.012, 0.012)])
	asm.add(OrganicMesh.sweep(k + "_guard", guard, guard_r, 8), iron, Transform3D.IDENTITY, DARK_IRON)
	asm.add(OrganicMesh.blob(k + "_guardskull", Vector3(0.034, 0.04, 0.03), 0.1, 11, 10), bone, Transform3D(Basis.IDENTITY, Vector3(0, 0.205, -0.02)), BONE)
	# Grip, wrapped; heavy pommel.
	var grip := PackedVector2Array([Vector2(0.024, -0.3), Vector2(0.026, -0.2), Vector2(0.024, -0.05), Vector2(0.026, 0.1), Vector2(0.024, 0.18)])
	asm.add(BossKit.lathe(k + "_grip", grip, 10), leather, Transform3D.IDENTITY, LEATHER)
	for i in 6:
		asm.add(BossKit.torus(k + "_wrap", 0.027, 0.005, 12, 4), leather, Transform3D(Basis(Vector3.FORWARD, 0.25), Vector3(0, -0.26 + i * 0.075, 0)), LEATHER.darkened(0.3))
	asm.add(OrganicMesh.blob(k + "_pommel", Vector3(0.05, 0.055, 0.035), 0.05, 13, 12), iron, Transform3D(Basis.IDENTITY, Vector3(0, -0.34, 0)), BRONZE)
	bake_into(_held, "blade", asm)
	_held_len = 1.48


func _tick_boss(delta: float) -> void:
	# The lantern swings on its chain: a damped pendulum kicked by the body's motion.
	if _lantern == null:
		return
	var pos := _lantern.global_position
	if not _prev_pos.is_finite():
		_prev_pos = pos
	var vel := (pos - _prev_pos) / maxf(delta, 0.001)
	_prev_pos = pos
	var local_v := global_transform.basis.inverse() * vel
	var kick := Vector2(local_v.z, -local_v.x) * 0.05
	_lantern_vel += (-_lantern_swing * 18.0 - _lantern_vel * 2.2) * delta + kick * delta * 6.0
	_lantern_swing += _lantern_vel * delta
	_lantern_swing = _lantern_swing.limit_length(0.9)
	_lantern.rotation = Vector3(_lantern_swing.x + sin(_time * 1.3) * 0.04, 0, _lantern_swing.y)
	for f in _soul_flames:
		if is_instance_valid(f):
			f.amount_ratio = clampf(0.5 + _power * 0.5 + 0.2, 0.0, 1.0)


func _on_boss_phase(new_phase: int) -> void:
	if new_phase >= 3 and _soul_flames.size() < 6:
		for side: float in [-1.0, 1.0]:
			var o := 0 if side < 0.0 else 5
			var p := fx_point(R.UARM_L + o, _rest[R.UARM_L + o] + Vector3(side * 0.1, 0.2, 0))
			_soul_flames.append(BossKit.emitter(p, "wisp", 22, Vector3(0.22, 0.06, 0.22), SOUL, 0.3, 0.9, 1.5))
		var h := fx_point(R.HEAD, Vector3(0, 1.86, 0))
		_soul_flames.append(BossKit.emitter(h, "wisp", 26, Vector3(0.22, 0.04, 0.22), SOUL, 0.35, 1.0, 2.0))


func _on_boss_death() -> void:
	# The soul tears free of the armour.
	if not is_inside_tree():
		return
	var parent := get_parent() as Node3D
	if parent == null:
		return
	var at := global_position + Vector3(0, 2.6, 0)
	ModelKit.burst(parent, at, 90, 1.2, 9.0, 0.9, SOUL.lightened(0.4), SOUL.darkened(0.3), 1.6)
	ModelKit.flash_light(parent, at, SOUL, 8.0, 18.0, 1.2)


## Standing vigil: head bowed, both hands folded on the hilt of the
## greatsword planted point-down in front of it.
func _pose_dormant(t: PackedVector3Array, w: float) -> void:
	t[R.SPINE] = t[R.SPINE].lerp(Vector3(0.1, 0, 0), w)
	t[R.CHEST] = t[R.CHEST].lerp(Vector3(0.06, 0, 0), w)
	t[R.NECK] = t[R.NECK].lerp(Vector3(0.3, 0, 0), w)
	t[R.HEAD] = t[R.HEAD].lerp(Vector3(0.4, 0, 0), w)
	_fing[0] = lerpf(_fing[0], 1.4, w)
	_fing[1] = lerpf(_fing[1], 1.45, w)
	_foot[0] += Vector3(-0.06, 0, 0.03) * w
	_foot[1] += Vector3(0.06, 0, 0.03) * w
	hand_goals[1] = [Vector3(0.035, 1.12, -0.34), Vector3.DOWN, Vector3(-1.0, 0.0, 0.35), w]
	hand_goals[0] = [Vector3(-0.045, 1.1, -0.33), Vector3.DOWN, Vector3(1.0, 0.0, 0.35), w]
