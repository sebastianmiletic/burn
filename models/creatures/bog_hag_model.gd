class_name BogHagModel
extends BossHumanoid
## Old Mother Mire, the bog witch of Hagsfen: a hunched crone with a humped
## back under layered, rotting robes, a tattered shawl and a pointed hood. A
## crooked nose and a warty chin jut from the hood's shadow, one eye burns
## marsh-green, the other is milk-white, and grey matted hair hangs to her
## waist. Her arms are long and bony, her fingers end in black nails; a rope
## belt jingles with bottles, bones, skulls and herb bundles, and she leans
## on a gnarled staff crowned with roots that cage a glowing bog-light. Marsh
## fireflies drift around her. She mutters over the staff while she waits.

const SKIN := Color(0.46, 0.52, 0.4)
const SKIN2 := Color(0.36, 0.33, 0.3)
const ROBE := Color(0.16, 0.15, 0.11)
const ROBE2 := Color(0.28, 0.3, 0.18)
const SHAWL := Color(0.12, 0.13, 0.1)
const HOOD := Color(0.2, 0.22, 0.15)
const HAIR := Color(0.58, 0.6, 0.55)
const WOOD := Color(0.34, 0.26, 0.18)
const BONE := Color(0.78, 0.74, 0.62)
const BOG := Color(0.5, 1.0, 0.35)
const ROPE := Color(0.46, 0.4, 0.28)

var _charms: Array = []   # [pivot: Node3D, swing: Vector2, vel: Vector2, length]
var _prev_pos := Vector3.INF
var _orb_light: OmniLight3D


## Fraction of each action at which its blow lands (BogHagBoss plays the
## action for telegraph / IMPACT so her move meets the filled warning).
const IMPACT := {"swipe": 0.6, "curse": 0.6, "spit": 0.6, "summon": 0.56, "burst": 0.8}
## Pounce: airborne from POUNCE[0], lands at POUNCE[1] of POUNCE_TIME seconds.
const POUNCE := [0.3, 0.6]
const POUNCE_TIME := 1.8


func _init() -> void:
	super({"height": 2.8, "bulk": 0.95, "gaunt": true, "hunch": -0.55, "arm_length": 1.3, "cloak": true, "cloak_hem": 0.85,
		"tattered": true, "held": "hag_staff", "eyes": BOG, "cloak_color": SHAWL})
	durations["cast"] = 1.2
	durations["attack2"] = 0.9
	death_kneel = false
	# A witch's tricks: a spiteful staff swipe, hexes flicked from her claw,
	# the staff stabbed into the mud for the roots, a gob of bog bile, a
	# whirl into gas when she blinks, a scuttling pounce, the dead called up,
	# arms flung up to burst the swamp gas, and the staff stirring the sky
	# for the mire rain.
	moves["swipe"] = Moves.sweep(IMPACT["swipe"])
	moves["hex"] = Moves.fling(0.5 / 1.92, 1.06 / 1.92, 3)
	moves["curse"] = Moves.plant(IMPACT["curse"], Vector3(0.08, 1.0, -0.36), Vector3.UP)
	moves["spit"] = _spit(IMPACT["spit"])
	moves["teleport"] = Moves.spin(0.25, 0.55, 1.0)
	moves["summon"] = Moves.invoke(IMPACT["summon"])
	moves["pounce"] = Moves.leap(POUNCE[0], POUNCE[1], 0.45)
	moves["burst"] = Moves.invoke(IMPACT["burst"])
	moves["volley"] = _stir()
	moves["phase"] = _cackle()
	moves["hit"] = Moves.flinch()
	moves["roar"] = _cackle()


## Hexes: one flick of the claw per bolt (2 + phase bolts; HexBolt timing in BogHagBoss).
func _on_action(action_name: String) -> void:
	super._on_action(action_name)
	if action_name == "hex":
		var total := 2 + boss_phase
		var dur := 0.8 + total * 0.28
		moves["hex"] = Moves.fling(0.5 / dur, (0.5 + (total - 1) * 0.28) / dur, total)


## Bog bile: she rears back, then pitches forward with her jaw gaping wide.
func _spit(i: float) -> Dictionary:
	var z := Vector3.ZERO
	var b := i * 0.7
	return {
		R.SPINE: [[0, z], [b, Vector3(0.35, 0, 0)], [i, Vector3(-0.45, 0, 0)], [minf(1.0, i + 0.2), Vector3(-0.4, 0, 0)], [1, z]],
		R.CHEST: [[0, z], [b, Vector3(0.2, 0, 0)], [i, Vector3(-0.2, 0, 0)], [1, z]],
		R.NECK: [[0, z], [b, Vector3(0.2, 0, 0)], [i, Vector3(-0.35, 0, 0)], [1, z]],
		R.HEAD: [[0, z], [b, Vector3(0.45, 0, 0)], [i, Vector3(-0.1, 0, 0)], [1, z]],
		R.UARM_L: [[0, Moves.ARM_L], [b, Vector3(0.2, 0, -0.7)], [i, Vector3(0.6, 0, -0.5)], [1, Moves.ARM_L]],
		"hips": [[0, z], [b, Vector3(0, 0.03, 0.06)], [i, Vector3(0, -0.08, -0.1)], [1, z]],
		"jaw": [[0, 0.0], [b, 0.15], [i, 0.7], [minf(1.0, i + 0.2), 0.6], [1, 0.0]],
		"fing": [[0, 1.0], [b, 1.6], [i, -0.2], [1, 1.0]],
	}


## Stirring the clouds: the staff raised high and turned in slow circles.
func _stir() -> Dictionary:
	var arm := [[0.0, Moves.ARM_R]]
	var chest := [[0.0, Vector3.ZERO]]
	for k in 7:
		var p := 0.15 + k * 0.11
		var a := k * PI * 0.5
		arm.append([p, Vector3(2.5 + sin(a) * 0.25, cos(a) * 0.35, 0.3)])
		chest.append([p, Vector3(0.2, cos(a) * 0.2, sin(a) * 0.08)])
	arm.append([1.0, Moves.ARM_R])
	chest.append([1.0, Vector3.ZERO])
	return {
		R.UARM_R: arm,
		R.FARM_R: [[0, Vector3(0.7, 0, 0)], [0.15, Vector3(0.3, 0, 0)], [0.85, Vector3(0.3, 0, 0)], [1, Vector3(0.7, 0, 0)]],
		R.UARM_L: [[0, Moves.ARM_L], [0.2, Vector3(1.0, 0.3, -0.9)], [0.85, Vector3(1.0, 0.3, -0.9)], [1, Moves.ARM_L]],
		R.CHEST: chest,
		R.HEAD: [[0, Vector3.ZERO], [0.15, Vector3(0.5, 0, 0)], [0.85, Vector3(0.5, 0, 0)], [1, Vector3.ZERO]],
		"jaw": [[0, 0.0], [0.2, 0.3], [0.85, 0.3], [1, 0.0]],
		"shake": [[0, 0.0], [0.2, 0.5], [0.85, 0.5], [1, 0.0]],
		"fing": [[0, 1.0], [0.2, -0.2], [0.85, -0.2], [1, 1.0]],
	}


## A shrieking cackle, hunched over, claws hooked up by her face, shoulders shaking.
func _cackle() -> Dictionary:
	var z := Vector3.ZERO
	return {
		R.SPINE: [[0, z], [0.25, Vector3(-0.35, 0, 0)], [0.55, Vector3(0.3, 0, 0)], [0.85, Vector3(0.25, 0, 0)], [1, z]],
		R.HEAD: [[0, z], [0.25, Vector3(-0.2, 0, 0)], [0.55, Vector3(0.6, 0, 0)], [0.85, Vector3(0.55, 0, 0)], [1, z]],
		R.UARM_L: [[0, Moves.ARM_L], [0.3, Vector3(1.2, -0.5, -0.4)], [0.85, Vector3(1.3, -0.4, -0.6)], [1, Moves.ARM_L]],
		R.FARM_L: [[0, Vector3(0.3, 0, 0)], [0.3, Vector3(2.2, 0, 0)], [0.85, Vector3(2.0, 0, 0)], [1, Vector3(0.3, 0, 0)]],
		"hips": [[0, z], [0.25, Vector3(0, -0.1, 0)], [0.55, Vector3(0, 0.02, 0)], [1, z]],
		"jaw": [[0, 0.0], [0.5, 0.6], [0.6, 0.2], [0.7, 0.6], [0.8, 0.2], [0.9, 0.5], [1, 0.0]],
		"shake": [[0, 0.0], [0.45, 1.0], [0.9, 1.0], [1, 0.0]],
		"fing": [[0, 1.0], [0.3, 1.7], [1, 1.0]],
	}


func _ember_extents() -> Vector3:
	return Vector3(0.35, 0.9, 0.3)


func _lod_size() -> float:
	return 2.5


func _dress() -> void:
	var k := _kit_key()
	var skin := BossKit.skin(SKIN2, {"albedo": Color(1, 1, 1), "pattern_scale": 14.0, "rim": 0.0})
	var robe := BossKit.cloth(ROBE, ROBE2, {"tatter": 0.45, "grime": 0.85})
	var over := BossKit.cloth(ROBE2, ROBE, {"tatter": 0.6, "grime": 0.7})
	var shawl := BossKit.cloth(SHAWL, Color(0.22, 0.2, 0.15), {"tatter": 0.6, "grime": 0.6})
	var hood := BossKit.cloth(Color(1, 1, 1), Color(0.3, 0.28, 0.2), {"grime": 0.6})
	var hair := BossKit.fur(Color(0.42, 0.44, 0.4), {"pattern_scale": 26.0})
	var bone := BossKit.bone()
	var nail := ModelKit.mat(Color(0.06, 0.05, 0.04), AsciiMaterialId.SOLID, 0.4, 0.1, 0.2)
	var eye := BossKit.glow(BOG, 7.0, 0.3)
	var milk := ModelKit.mat(Color(0.82, 0.84, 0.78), AsciiMaterialId.SOLID, 0.3, 0.05, 0.4)
	var dark := ModelKit.mat(Color(0.015, 0.015, 0.01), AsciiMaterialId.SOLID, 0.9, 0.0, 0.0)
	_dress_head(k, skin, hood, hair, eye, milk, dark)
	_dress_body(k, skin, hood, nail, bone)
	skinned(BossKit.robe(k + "_robe", _rest, 1.02, 0.0, Vector2(0.17, 0.14), Vector2(0.26, 0.24), 26, 12, -PI, PI, 0.012, 0.02), robe)
	skinned(BossKit.robe(k + "_over", _rest, 1.04, 0.42, Vector2(0.185, 0.155), Vector2(0.25, 0.22), 22, 8, -PI * 0.75, PI * 0.75, 0.012, 0.015), over)
	skinned(BossKit.cloak(k + "_shawl", body, style, 15, 9, 0.01, 1.35, 0.0), shawl)
	_dress_charms(k, bone)
	# Marsh fireflies and a low bog mist.
	var flies := fx_point(R.CHEST, Vector3(0, 1.3, 0))
	BossKit.emitter(flies, "mote", 16, Vector3(1.6, 1.0, 1.6), BOG, 0.08, 3.0, 0.2)
	var mist := fx_point(R.HIPS, Vector3(0, 0.15, 0))
	BossKit.emitter(mist, "smoke", 14, Vector3(1.2, 0.1, 1.2), Color(0.2, 0.26, 0.16), 1.2, 3.0, 0.15)


func _dress_head(k: String, skin: Material, hood: Material, hair: Material, eye: Material, milk: Material, dark: Material) -> void:
	var head := part(R.HEAD)
	# The face, deep in the hood: gaunt cheeks, a long hooked nose, a jutting chin.
	head.put(OrganicMesh.blob(k + "_face", Vector3(0.085, 0.11, 0.095), 0.1, 61, 14), skin, Vector3(0, 1.69, -0.01), Vector3.ZERO, Vector3.ONE, SKIN)
	var nose := OrganicMesh.bezier(k + "_nose", Vector3.ZERO, Vector3(0, -0.01, -0.06), Vector3(0, -0.07, -0.085), 0.026, 0.008, 10, 8)
	head.add(nose, skin, Transform3D(Basis.IDENTITY, Vector3(0, 1.72, -0.085)), SKIN)
	head.put(ModelKit.sphere(0.009, 6), skin, Vector3(0.012, 1.69, -0.155), Vector3.ZERO, Vector3.ONE, SKIN2)
	head.put(OrganicMesh.blob(k + "_chin", Vector3(0.03, 0.035, 0.035), 0.15, 62, 10), skin, Vector3(0, 1.6, -0.075), Vector3(-20, 0, 0), Vector3.ONE, SKIN)
	head.put(ModelKit.sphere(0.008, 6), skin, Vector3(-0.015, 1.588, -0.102), Vector3.ZERO, Vector3.ONE, SKIN2)
	head.put(OrganicMesh.blob(k + "_mouth", Vector3(0.03, 0.006, 0.01), 0.0, 2, 8), dark, Vector3(0, 1.635, -0.088))
	for sx: float in [-1.0, 1.0]:
		head.put(OrganicMesh.blob(k + "_cheek", Vector3(0.028, 0.035, 0.03), 0.2, 63, 8), skin, Vector3(sx * 0.05, 1.67, -0.065), Vector3.ZERO, Vector3.ONE, SKIN2)
		head.put(OrganicMesh.blob(k + "_lid", Vector3(0.022, 0.012, 0.016), 0.1, 64, 8), skin, Vector3(sx * 0.033, 1.718, -0.08), Vector3.ZERO, Vector3.ONE, SKIN2)
	head.put(ModelKit.sphere(0.014, 8), eye, Vector3(-0.033, 1.708, -0.084))
	head.put(ModelKit.sphere(0.013, 8), milk, Vector3(0.033, 1.708, -0.083))
	# Pointed hood with its tip slumping back, open in front.
	var spec := [[1.9, 0.03, 0.035], [1.86, 0.075, 0.085], [1.81, 0.115, 0.125], [1.75, 0.14, 0.15], [1.69, 0.148, 0.16], [1.62, 0.15, 0.162], [1.55, 0.17, 0.17]]
	var rows: Array = []
	for i in spec.size():
		var r: Array = spec[i]
		var pts := PackedVector3Array()
		var gap := lerpf(0.0, 0.72, smoothstep(0.0, 3.0, float(i)))
		for c in 19:
			var a := lerpf(gap - PI + 0.01, PI - gap - 0.01, c / 18.0) + PI
			var back := (1.0 - float(i) / spec.size()) * 0.07
			pts.append(Vector3(sin(a) * float(r[1]), float(r[0]), -cos(a) * float(r[2]) + back + 0.01))
		rows.append(pts)
	head.add(BossKit.plate(k + "_hood", rows, 0.014, Vector3(0, 1.7, 0.02)), hood, Transform3D.IDENTITY, HOOD)
	head.put(OrganicMesh.blob(k + "_hoodshadow", Vector3(0.12, 0.13, 0.08), 0.0, 2, 10), dark, Vector3(0, 1.72, 0.035))
	# Matted grey hair spilling out of the hood.
	for i in 10:
		var sx := -1.0 if i < 5 else 1.0
		var j := i % 5
		var root := Vector3(sx * (0.07 + j * 0.012), 1.75 - j * 0.02, -0.04 + j * 0.02)
		var len := 0.3 + 0.08 * sin(i * 2.1)
		var hm := OrganicMesh.bezier("%s_hair_%d" % [k, i], Vector3.ZERO, Vector3(sx * 0.04, -len * 0.45, -0.03), Vector3(sx * 0.06, -len, 0.0), 0.016, 0.004, 9, 5, 0.5)
		head.add(hm, hair, Transform3D(Basis.IDENTITY, root), HAIR.darkened(0.1 * (j % 3)))


func _dress_body(k: String, skin: Material, hood: Material, nail: Material, bone: Material) -> void:
	# The hump, under the shawl.
	part(R.CHEST).put(OrganicMesh.blob(k + "_hump", Vector3(0.15, 0.14, 0.12), 0.2, 65, 12), hood, Vector3(0.02, 1.36, 0.1), Vector3.ZERO, Vector3.ONE, Color(0.16, 0.16, 0.12))
	part(R.CHEST).put(OrganicMesh.blob(k + "_torso", Vector3(0.15, 0.2, 0.11), 0.1, 66, 12), hood, Vector3(0, 1.25, 0.0), Vector3.ZERO, Vector3.ONE, Color(0.2, 0.19, 0.14))
	# Rope belt.
	part(R.HIPS).put(BossKit.torus(k + "_rope", 0.165, 0.012, 24, 5, 1.0), hood, Vector3(0, 1.0, 0.0), Vector3(4, 0, 0), Vector3(1.0, 1.0, 0.86), ROPE)
	for side: float in [-1.0, 1.0]:
		var o := 0 if side < 0.0 else 5
		var sh := _rest[R.UARM_L + o]
		var el := _rest[R.FARM_L + o]
		var wr := _rest[R.HAND_L + o]
		var fi := _rest[R.FING_L + o]
		# Sleeves: a narrow upper sleeve, a ragged bell over the forearm.
		var ua := part(R.UARM_L + o)
		var up := PackedVector2Array([Vector2(0.06, 0.0), Vector2(0.055, 0.15), Vector2(0.058, el.distance_to(sh))])
		ua.add(BossKit.lathe(k + "_usleeve", up, 12), hood, along(sh + Vector3(0, 0.02, 0), el), ROBE.lightened(0.05))
		var fa := part(R.FARM_L + o)
		var bell := PackedVector2Array([Vector2(0.05, 0.0), Vector2(0.06, 0.1), Vector2(0.085, 0.2), Vector2(0.1, 0.24)])
		fa.add(BossKit.lathe(k + "_bell", bell, 12), hood, along(el + Vector3(0, 0.03, 0), wr + Vector3(0, 0.08, 0)), ROBE)
		fa.add(OrganicMesh.bezier(k + "_wrist", Vector3.ZERO, (wr - el) * 0.5, wr - el, 0.025, 0.02, 6, 8), skin, Transform3D(Basis.IDENTITY, el), SKIN)
		# Bony hands with long fingers and black nails.
		var hand := part(R.HAND_L + o)
		hand.put(OrganicMesh.blob(k + "_palm", Vector3(0.022, 0.045, 0.035), 0.15, 67, 10), skin, (wr + fi) * 0.5, Vector3.ZERO, Vector3.ONE, SKIN)
		hand.add(OrganicMesh.bezier(k + "_thumb", Vector3.ZERO, Vector3(0, -0.03, -0.025), Vector3(0, -0.065, -0.02), 0.009, 0.007, 6, 6), skin, Transform3D(Basis.IDENTITY, wr + Vector3(0, -0.02, -0.03)), SKIN)
		var fing := part(R.FING_L + o)
		for f in 4:
			var z := lerpf(-0.024, 0.024, f / 3.0)
			var l := 0.085 if f in [1, 2] else 0.07
			fing.add(OrganicMesh.bezier("%s_finger_%d" % [k, f], Vector3.ZERO, Vector3(0, -l * 0.5, 0), Vector3(0, -l, -0.01), 0.0085, 0.006, 6, 6), skin, Transform3D(Basis.IDENTITY, fi + Vector3(0, 0.02, z)), SKIN)
			fing.add(OrganicMesh.bezier("%s_nail" % k, Vector3.ZERO, Vector3(0, -0.012, -0.002), Vector3(0, -0.026, -0.008), 0.006, 0.0008, 4, 5), nail, Transform3D(Basis.IDENTITY, fi + Vector3(0, 0.02 - l, z - 0.01)))
	var _u := bone


## Charms on the rope belt: each hangs on a string and swings on its own.
func _dress_charms(k: String, bone: Material) -> void:
	var glass := BossKit.crystal(Color(0.6, 0.8, 0.5), BOG, 0.5)
	var wood := BossKit.wood(Color(0.2, 0.15, 0.1))
	var string := ModelKit.mat(Color(0.3, 0.27, 0.2), AsciiMaterialId.CLOTH, 0.9, 0.2, 0.0)
	var herbs := BossKit.fur(Color(0.3, 0.4, 0.18), {"albedo": Color(0.36, 0.42, 0.22), "pattern_scale": 30.0})
	var charms := [["bottle", -0.6, 0.1], ["skull", 0.4, 0.13], ["bone", 1.2, 0.08], ["herbs", -1.3, 0.11], ["bottle2", 2.2, 0.12],
		["feather", -2.1, 0.09], ["skull2", 2.8, 0.1]]
	for c: Array in charms:
		var a: float = c[1]
		var len: float = c[2]
		var at := Vector3(sin(a) * 0.17, 0.99, -cos(a) * 0.145)
		var p := pivot(R.HIPS, at, "Charm")
		var asm := BossKit.assembly()
		asm.add(OrganicMesh.bezier(k + "_string_%d" % int(len * 100), Vector3.ZERO, Vector3(0, -len * 0.5, 0), Vector3(0, -len, 0), 0.002, 0.002, 2, 3), string, Transform3D.IDENTITY)
		var end := Vector3(0, -len, 0)
		match String(c[0]):
			"bottle", "bottle2":
				var prof := PackedVector2Array([Vector2(0.0, -0.06), Vector2(0.022, -0.058), Vector2(0.026, -0.03), Vector2(0.018, -0.008), Vector2(0.008, 0.0), Vector2(0.009, 0.012)])
				asm.add(BossKit.lathe(k + "_bottle", prof, 10, 1.0, 1.0, true, true), glass, Transform3D(Basis.IDENTITY, end + Vector3(0, -0.005, 0)))
				asm.add(ModelKit.cylinder(0.008, 0.008, 0.012, 6), wood, Transform3D(Basis.IDENTITY, end + Vector3(0, 0.012, 0)))
			"skull", "skull2":
				asm.add(OrganicMesh.blob(k + "_cskull", Vector3(0.025, 0.028, 0.03), 0.1, 68, 10), bone, Transform3D(Basis.IDENTITY, end + Vector3(0, -0.025, 0)), BONE)
			"bone":
				asm.add(OrganicMesh.bezier(k + "_cbone", Vector3.ZERO, Vector3(0.01, -0.03, 0), Vector3(0.0, -0.07, 0), 0.008, 0.008, 4, 6), bone, Transform3D(Basis.IDENTITY, end), BONE)
			"herbs":
				for h in 5:
					var d := Vector3(sin(h * 1.3) * 0.015, -0.07, cos(h * 1.3) * 0.015)
					asm.add(OrganicMesh.bezier(k + "_herb", Vector3.ZERO, d * 0.5, d, 0.006, 0.002, 4, 4), herbs, Transform3D(Basis.IDENTITY, end))
			"feather":
				var fpts := PackedVector2Array([Vector2(0, 0), Vector2(0.012, -0.03), Vector2(0.01, -0.08), Vector2(0, -0.1), Vector2(-0.01, -0.07), Vector2(-0.009, -0.02)])
				asm.add(OrganicMesh.membrane(k + "_feather", fpts, 0.004, 0.003), herbs, Transform3D(Basis.IDENTITY, end), Color(0.2, 0.2, 0.2))
		bake_into(p, "charm_%s" % c[0], asm)
		_charms.append([p, Vector2.ZERO, Vector2.ZERO, len])


## The staff: a gnarled, twisting branch; at its crown, roots cage a bog-light.
func _build_held(item_id: String) -> void:
	_held_id = item_id
	if _held != null:
		_held.queue_free()
		_held = null
	if item_id == "":
		return
	_held = Node3D.new()
	_held.name = "Staff"
	grip_r.add_child(_held)
	var k := _kit_key()
	var wood := BossKit.wood(Color(0.2, 0.14, 0.09), {"albedo": Color(1, 1, 1)})
	var bone := BossKit.bone()
	var orb := BossKit.glow(BOG, 6.0, 0.35)
	var asm := BossKit.assembly()
	var path := PackedVector3Array()
	var radii := PackedVector2Array()
	for i in 21:
		var t := float(i) / 20.0
		var y := lerpf(-0.75, 0.62, t)
		path.append(Vector3(sin(t * 9.0) * 0.012 + sin(t * 23.0) * 0.004, y, cos(t * 7.0) * 0.012))
		var r := lerpf(0.017, 0.024, t) + 0.004 * maxf(0.0, sin(t * 31.0))
		radii.append(Vector2(r, r * 0.9))
	asm.add(OrganicMesh.sweep(k + "_staff", path, radii, 8), wood, Transform3D.IDENTITY, WOOD)
	# Roots twisting up and over the bog-light.
	for i in 5:
		var a := TAU * i / 5.0
		var out := Vector3(cos(a), 0, sin(a))
		var root := OrganicMesh.bezier("%s_root_%d" % [k, i], Vector3.ZERO, out * 0.07 + Vector3(0, 0.08, 0), out * 0.01 + Vector3(0, 0.2, 0), 0.012, 0.004, 8, 5)
		asm.add(root, wood, Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0)), WOOD.darkened(0.2))
	asm.add(ModelKit.sphere(0.04, 12), orb, Transform3D(Basis.IDENTITY, Vector3(0, 0.71, 0)))
	asm.add(OrganicMesh.blob(k + "_staffskull", Vector3(0.028, 0.032, 0.032), 0.1, 69, 10), bone, Transform3D(Basis.IDENTITY, Vector3(0, 0.56, -0.025)), BONE)
	for sx: float in [-1.0, 1.0]:
		asm.add(OrganicMesh.bezier("%s_antler_%d" % [k, int(sx)], Vector3.ZERO, Vector3(sx * 0.06, 0.04, 0), Vector3(sx * 0.09, 0.12, 0.02), 0.009, 0.002, 6, 5), bone, Transform3D(Basis.IDENTITY, Vector3(sx * 0.02, 0.6, 0)), BONE)
	bake_into(_held, "staff", asm)
	var fx := Node3D.new()
	fx.position = Vector3(0, 0.71, 0)
	fx.scale = Vector3.ONE / _s
	_held.add_child(fx)
	_orb_light = add_light(fx, Vector3.ZERO, BOG, 1.6, 7.0)
	BossKit.emitter(fx, "wisp", 10, Vector3(0.05, 0.05, 0.05), BOG, 0.08, 1.0, 0.4)
	_held_len = 0.75


func _tick_boss(delta: float) -> void:
	var pos := global_position
	if not _prev_pos.is_finite():
		_prev_pos = pos
	var vel := (pos - _prev_pos) / maxf(delta, 0.001)
	_prev_pos = pos
	var local_v := global_transform.basis.inverse() * vel
	var kick := Vector2(local_v.z, -local_v.x) * 0.08
	var hip_sway := sin(_phase * TAU) * _mv * 0.6
	for c: Array in _charms:
		var p: Node3D = c[0]
		var sw: Vector2 = c[1]
		var v: Vector2 = c[2]
		var stiff := 9.8 / maxf(0.05, float(c[3]) * _s) * 2.0
		v += (-sw * stiff - v * 2.0) * delta + (kick + Vector2(0, hip_sway)) * delta * 5.0
		sw += v * delta
		sw = sw.limit_length(1.0)
		c[1] = sw
		c[2] = v
		p.rotation = Vector3(sw.x, 0, sw.y)


## The staff stays upright in her right hand whenever she is not casting with it.
func _pose(dt: float) -> void:
	super._pose(dt)
	if _dead or _action != "" or _dormant_w > 0.5:
		return
	var w := 1.0 - _dormant_w
	var step := sin(_phase * TAU) * _mv * 0.06
	hand_goals[1] = [Vector3(0.24, 1.0 + step, -0.3), Vector3.UP, Vector3(-0.4, 0.0, -1.0), w]


func _on_boss_phase(new_phase: int) -> void:
	if new_phase >= 2:
		var p := fx_point(R.HIPS, Vector3(0, 0.6, 0))
		BossKit.emitter(p, "wisp", 18 * new_phase, Vector3(0.8, 0.6, 0.8), BOG, 0.12, 1.4, 0.6)


func _on_boss_death() -> void:
	if not is_inside_tree():
		return
	var parent := get_parent() as Node3D
	if parent == null:
		return
	var at := global_position + Vector3(0, 1.0, 0)
	ModelKit.burst(parent, at, 80, 0.8, 5.0, 0.7, BOG.lightened(0.3), Color(0.15, 0.35, 0.1), 1.6)
	ModelKit.flash_light(parent, at, BOG, 5.0, 10.0, 1.0)


## Waiting: both hands on the staff planted before her, head nodding as she mutters.
func _pose_dormant(t: PackedVector3Array, w: float) -> void:
	var mutter := sin(_time * 5.0) * 0.06 + sin(_time * 1.3) * 0.08
	t[R.HEAD] = t[R.HEAD].lerp(Vector3(0.15 + mutter, sin(_time * 0.7) * 0.2, 0), w)
	t[R.JAW] = Vector3(maxf(0.0, sin(_time * 7.0)) * -0.15 * w, 0, 0)
	_fing[0] = lerpf(_fing[0], 1.3, w)
	_fing[1] = lerpf(_fing[1], 1.4, w)
	hand_goals[1] = [Vector3(0.08, 1.12, -0.36), Vector3.UP, Vector3(-1.0, 0.0, 0.2), w]
	hand_goals[0] = [Vector3(-0.0, 1.2, -0.37), Vector3.UP, Vector3(1.0, 0.0, 0.2), w]
