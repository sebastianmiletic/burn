class_name CerberusModel
extends CreatureModel
## Cerberus, Hound of Tartarus: a 10 m, three-headed hellhound.
##
## * Torso and tail are one smooth skinned body (SerpentChain skeleton) of
##   ember-cracked hide: the cracks glow, and blaze hotter as it rages.
## * Three necks, each its own skinned chain from the chest to a head that is
##   animated on its own: snap, howl, fire / ash breath, looking around.
##   Wolfish skulls with heavy brows, swept ears, short horns, hinged jaws with
##   fangs, burning eyes and a glowing gullet.
## * A smouldering mane of spiked fur over the shoulders, spiked iron collars
##   with broken chains swinging from them, embers rising off its back.
## * Muscular digitigrade legs solved with IK from a trotting gait, big
##   clawed paws that plant; crouch, pounce (stretched leap), lunge, rearing
##   ground slam, death.
##
## Faces -Z; the origin is the ground under the belly. `look_target` turns
## the heads, `rage` (0..1) stokes the cracks and the mane.

const LENGTH := 9.3
const BONES := 14
const PELVIS := 7
const SHOULDER := 1
const HIPS := 6
const NECK_LEN := 3.4
const NECK_BONES := 6
## Fraction of an action at which the blow lands (the boss times telegraphs to these).
const IMPACT := {"bite": 0.5, "lunge": 0.45, "slam": 0.55, "pounce": 0.78, "rake": 0.5, "kick": 0.5, "combo": 0.82}
## Breath: fire from BREATH_ON to BREATH_OFF of the action.
const BREATH_ON := 0.28
const BREATH_OFF := 0.88
const CHEST := Vector3(0, 4.3, -2.3)
const HIP_POS := Vector3(0, 4.0, 2.65)
## Neck roots (model space) and idle head positions.
const ROOTS := [Vector3(-1.15, 4.7, -2.3), Vector3(0, 5.05, -2.6), Vector3(1.15, 4.7, -2.3)]
const HEADS := [Vector3(-2.9, 5.6, -4.9), Vector3(0, 6.7, -6.0), Vector3(2.9, 5.6, -4.9)]

var look_target := Vector3.INF
var rage := 0.0
var ground_y := NAN

var chain: SerpentChain
var necks: Array[SerpentChain] = []
var heads: Array[Node3D] = []
var jaws: Array[Node3D] = []
var mouths: Array[Node3D] = []
var breaths: Array[BreathStream] = []
var throats: Array[MeshInstance3D] = []
var eyes: Array[MeshInstance3D] = []
var legs: Array = []
var chains: Array = []      # [pivot: Node3D, swing: Vector2, prev_pos: Vector3]
var mane_fx: GPUParticles3D
var tail_fx: GPUParticles3D

var _seg := LENGTH / float(BONES - 1)
var _tail := PackedVector3Array()
var _tail_ready := false
var _walk := 0.0
var _gait := 0.0
var _crouch := 0.0
var _pitch := 0.0
var _roll := 0.0
var _rear := 0.0
var _lunge := 0.0
var _stretch := 0.0
var _head_pos: Array[Vector3] = [Vector3.INF, Vector3.INF, Vector3.INF]
var _head_look: Array[Vector3] = [Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD]
var _jaw := [0.0, 0.0, 0.0]
var _pitch_h := [0.0, 0.0, 0.0]
var _throat := [0.3, 0.3, 0.3]
var _rage := 0.0
var _prev_root := Vector3.INF
## Heading change measured from the model itself (turning steps on clients too).
var _prev_yaw := NAN
var _yaw_rate := 0.0
var _vel := Vector3.ZERO
var _last_ground := 0.0
var _impact_done := false
var _fx_t := 0.0
var _death_side := 1.0
var _foot_was_down := [true, true, true, true]


func _init() -> void:
	dissolve_delay = 3.5
	dissolve_time = 2.8
	durations["breath"] = 3.2
	durations["bite"] = 1.2
	durations["howl"] = 2.0
	durations["pounce"] = 1.4
	durations["lunge"] = 1.0
	durations["slam"] = 1.6
	durations["summon"] = 2.0
	durations["rake"] = 1.1
	durations["kick"] = 1.1
	durations["charge"] = 2.2
	durations["spit"] = 1.6
	durations["combo"] = 2.0
	durations["phase"] = 2.2


func _ember_extents() -> Vector3:
	return Vector3(2.0, 1.6, 4.0)


func _lod_size() -> float:
	return 7.0


func mouth_node(i := 1) -> Node3D:
	return mouths[clampi(i, 0, mouths.size() - 1)] if not mouths.is_empty() else null


# --- Build -------------------------------------------------------------------------------

func _build() -> void:
	var hide := Color(0.085, 0.06, 0.055)
	var belly := Color(0.16, 0.08, 0.06)
	var crack := Color(1.0, 0.38, 0.08)
	var body_mat := CreatureSkin.fur(Color(0.075, 0.055, 0.05), belly, {"use_uv": true, "pattern_scale": 4.5, "bump": 1.2, "bump_distance": 90.0,
		"roughness": 0.85, "rim": 0.45, "glow_mode": 2, "glow_color": crack, "glow_amount": 0.0, "glow_energy": 2.4, "glow_pulse": 0.6, "glow_sparsity": 1.0,
		"accent": Color(0.32, 0.1, 0.04), "accent_mode": 1, "accent_amount": 0.3, "accent_scale": 0.9, "ascii_id": AsciiMaterialId.SOLID})
	var head_mat := CreatureSkin.hide(hide.lightened(0.03), belly, {"pattern_scale": 7.0, "bump": 1.3, "bump_distance": 70.0,
		"roughness": 0.72, "rim": 0.35, "glow_mode": 2, "glow_color": crack, "glow_amount": 0.0, "glow_energy": 2.2, "glow_pulse": 0.6, "glow_sparsity": 0.95})
	var limb_mat := CreatureSkin.hide(hide, belly, {"pattern_scale": 6.0, "bump": 1.3, "bump_distance": 70.0, "roughness": 0.78,
		"rim": 0.35, "glow_mode": 2, "glow_color": crack, "glow_amount": 0.0, "glow_energy": 2.4, "glow_pulse": 0.5, "glow_sparsity": 0.95})
	var fur := CreatureSkin.fur(Color(0.07, 0.05, 0.045), Color(0.3, 0.1, 0.04), {"pattern_scale": 5.0, "accent": Color(0.55, 0.16, 0.04),
		"accent_mode": 1, "accent_amount": 0.35, "accent_scale": 2.0, "glow_mode": 2, "glow_color": crack, "glow_amount": 0.08, "glow_energy": 2.0})
	var bone := CreatureSkin.keratin(Color(0.8, 0.74, 0.62), {"belly": Color(0.25, 0.18, 0.12), "belly_mix": 0.6})
	var claw := CreatureSkin.keratin(Color(0.09, 0.07, 0.06), {"roughness": 0.25, "specular_amount": 0.7})
	var iron := ModelKit.metal(Color(0.2, 0.18, 0.17))

	# --- Torso + tail -------------------------------------------------------------
	var prof := [[0.0, 0.35, 0.4, -0.1], [0.035, 1.25, 1.45, -0.2], [0.07, 1.52, 1.74, -0.25], [0.16, 1.62, 1.82, -0.3], [0.3, 1.32, 1.4, 0.05],
		[0.4, 1.22, 1.25, 0.12], [0.48, 1.3, 1.3, 0.08], [0.55, 0.95, 0.95, 0.05], [0.6, 0.48, 0.5, 0.0],
		[0.78, 0.36, 0.38, 0.0], [0.92, 0.26, 0.26, 0.0], [1.0, 0.06, 0.06, 0.0]]
	var tube := OrganicMesh.skinned_tube("cerberus_body", LENGTH, BONES, prof, 72, 18)
	var extras: Array = []
	# Spines of bony ridge along the back.
	for i in range(1, PELVIS + 2):
		var s := OrganicMesh._sample(prof, float(i) / (BONES - 1))
		var h := 0.55 - absf(float(i) - 2.0) * 0.05
		extras.append([OrganicMesh.bezier("cerb_ridge_%d" % int(h * 100.0), Vector3.ZERO, Vector3(0, h * 0.6, h * 0.3), Vector3(0, h, h * 0.85), h * 0.22, h * 0.02, 5, 5), Transform3D(Basis(), Vector3(0, float(s[1]) + float(s[2]) - 0.15, i * _seg)), i])
	var body_mesh := OrganicMesh.skinned_mesh("cerberus_body_full", [OrganicMesh.surface_arrays(tube), OrganicMesh.skinned_parts(extras)])
	chain = SerpentChain.new().setup(body_mesh, body_mat, BONES, LENGTH, 40.0)
	chain.name = "Chain"
	add_child(chain)
	chain.mesh_instance.material_override = null
	chain.mesh_instance.set_surface_override_material(0, body_mat)
	chain.mesh_instance.set_surface_override_material(1, bone)
	_geoms.append(chain.mesh_instance)
	_tail.resize(BONES)

	# Mane: a crest of spiked, smouldering fur over the shoulders and neck roots.
	var mane_holder := Node3D.new()
	chain.attach(SHOULDER, mane_holder)
	var tufts: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 666
	for i in 46:
		var a := rng.randf_range(-1.9, 1.9)
		var z := rng.randf_range(-1.2, 1.4)
		var r := 1.55 - z * 0.12
		var base := Vector3(sin(a) * r * 0.95, cos(a) * r * 0.9 - 0.1, z)
		var l := rng.randf_range(0.9, 1.7) * (1.0 - absf(a) * 0.18)
		var out := Vector3(sin(a) * 0.55, cos(a), 0.0).normalized()
		var tip := out * l + Vector3(0, 0, l * 0.9)
		var tm := OrganicMesh.bezier("cerb_tuft_%d" % (i % 7), Vector3.ZERO, Vector3(0, 0.55, 0.25), Vector3(0, 1.0, 0.75), 0.2, 0.02, 5, 5, 0.6)
		var yb := Basis.looking_at(-tip.normalized(), Vector3.UP if absf(tip.normalized().y) < 0.95 else Vector3.BACK)
		tufts.append([tm, Transform3D(yb * Basis(Vector3.RIGHT, PI * 0.5) * Basis().scaled(Vector3.ONE * l), base)])
	ModelKit.part(mane_holder, OrganicMesh.merge("cerb_mane", tufts), fur)
	mane_fx = ModelKit.embers(mane_holder, 46, Vector3(1.4, 0.5, 1.3), 1.3, 0.16, 2.4)
	mane_fx.position = Vector3(0, 1.4, 0.0)
	mane_fx.emitting = true

	# --- Necks and heads --------------------------------------------------------------
	var neck_prof := [[0.0, 0.62, 0.7, 0.0], [0.4, 0.74, 0.82, 0.0], [0.8, 0.92, 1.0, -0.05], [1.0, 0.95, 1.05, -0.1]]
	var neck_tube := OrganicMesh.skinned_tube("cerberus_neck", NECK_LEN, NECK_BONES, neck_prof, 24, 14)
	for k in 3:
		var nc := SerpentChain.new().setup(neck_tube, body_mat, NECK_BONES, NECK_LEN, 20.0)
		nc.name = "Neck%d" % k
		add_child(nc)
		necks.append(nc)
		# Spiked collar with a broken chain swinging from it.
		var collar_holder := Node3D.new()
		nc.attach(3, collar_holder)
		var cparts: Array = []
		var tor := TorusMesh.new()
		tor.inner_radius = 0.82
		tor.outer_radius = 1.08
		tor.rings = 16
		tor.ring_segments = 6
		cparts.append([tor, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)])
		for i in 8:
			var a := TAU * float(i) / 8.0
			var sp := OrganicMesh.bezier("cerb_collar_spike", Vector3.ZERO, Vector3(0, 0.25, 0), Vector3(0, 0.5, 0), 0.11, 0.01, 4, 5)
			cparts.append([sp, Transform3D(Basis(Vector3.BACK, a), Vector3(-sin(a), cos(a), 0) * 1.0)])
		ModelKit.part(collar_holder, OrganicMesh.merge("cerb_collar", cparts), iron)
		var pivot := ModelKit.joint(collar_holder, "ChainPivot", Vector3(0, -1.0, 0))
		var links: Array = []
		var link := TorusMesh.new()
		link.inner_radius = 0.1
		link.outer_radius = 0.19
		link.rings = 8
		link.ring_segments = 4
		var n_links := 5 + k % 2 * 2
		for i in n_links:
			var b := Basis(Vector3.UP, PI * 0.5 * (i % 2)) * Basis(Vector3.BACK, PI * 0.5) * Basis().scaled(Vector3(1.0, 1.0, 1.55))
			links.append([link, Transform3D(b, Vector3(0, -0.12 - i * 0.42, 0))])
		ModelKit.part(pivot, OrganicMesh.merge("cerb_chain_%d" % n_links, links), iron)
		chains.append([pivot, Vector2.ZERO, Vector2.ZERO])
		_build_head(k, head_mat, fur, bone, claw)

	# --- Legs -------------------------------------------------------------------------
	for spec: Array in [[true, -1.0, 0.5], [true, 1.0, 0.0], [false, -1.0, 0.0], [false, 1.0, 0.5]]:
		legs.append(_build_leg(spec[0], spec[1], spec[2], limb_mat, fur, claw))

	# The tail ends in a flame.
	var tip := Node3D.new()
	chain.attach(BONES - 1, tip)
	tail_fx = ModelKit.embers(tip, 26, Vector3(0.25, 0.25, 0.25), 0.7, 0.4, 2.2)
	tail_fx.emitting = true
	ModelKit.part(tip, ModelKit.sphere(0.22, 8), ModelKit.glow(Color(1.0, 0.45, 0.1), 5.0, 0.6), Vector3(0, 0, 0.1))


func _build_head(k: int, head_mat: Material, fur: Material, bone: Material, claw: Material) -> void:
	var head := Node3D.new()
	head.name = "Head%d" % k
	head.top_level = true
	add_child(head)
	var sc := 1.0 if k == 1 else 0.92
	head.set_meta("scale", sc)
	var skull_prof := [[0.0, 0.62, 0.66, 0.05], [0.14, 0.78, 0.74, 0.12], [0.3, 0.66, 0.6, 0.08], [0.48, 0.42, 0.42, -0.04],
		[0.78, 0.36, 0.34, -0.1], [0.94, 0.32, 0.28, -0.12], [1.0, 0.16, 0.14, -0.12]]
	var horn_parts: Array = []
	var brow_parts: Array = [[OrganicMesh.profile("cerb_skull", Vector3(0, 0.1, 0.45), Vector3(0, -0.14, -2.6), skull_prof, 18, 16), Transform3D()]]
	for side: float in [-1.0, 1.0]:
		brow_parts.append([OrganicMesh.blob("cerb_brow", Vector3(0.3, 0.2, 0.75), 0.3, 3, 10), Transform3D(Basis.from_euler(Vector3(0.15, side * 0.25, side * -0.35)), Vector3(side * 0.45, 0.58, -0.75))])
		brow_parts.append([OrganicMesh.blob("cerb_cheek", Vector3(0.3, 0.38, 0.6), 0.3, 5, 10), Transform3D(Basis(), Vector3(side * 0.72, -0.12, -0.25))])
		# Ears: long, swept back, torn.
		var ear := OrganicMesh.membrane("cerb_ear_%d" % int(side), PackedVector2Array([Vector2(0, 0), Vector2(side * 0.32, 0.15), Vector2(side * 0.18, 1.25), Vector2(side * 0.05, 0.9), Vector2(side * -0.12, 0.55)]), 0.12, 0.09)
		brow_parts.append([ear, Transform3D(Basis.from_euler(Vector3(-1.05, side * 0.35, side * -0.25)), Vector3(side * 0.6, 0.6, 0.15))])
		# Short curved horns.
		horn_parts.append([OrganicMesh.bezier("cerb_horn_%d" % int(side), Vector3.ZERO, Vector3(side * 0.35, 0.5, 0.35), Vector3(side * 0.3, 0.95, 1.05), 0.17, 0.02, 9, 7), Transform3D(Basis(), Vector3(side * 0.42, 0.62, -0.25))])
		var eye := ModelKit.part(head, ModelKit.sphere(0.13, 10), CreatureSkin.eye(Color(1.0, 0.32, 0.06), 5.0, 0.25), Vector3(side * 0.5, 0.36, -0.95), Vector3.ZERO, Vector3(0.75, 0.65, 1.2))
		eyes.append(eye)
	ModelKit.part(head, OrganicMesh.merge("cerb_head_plates", brow_parts), head_mat)
	horn_parts.append([_teeth("cerb_teeth_up", -1.0), Transform3D()])
	ModelKit.part(head, OrganicMesh.merge("cerb_horns", horn_parts), bone)
	# Ruff of fur at the back of the head.
	var ruff: Array = []
	for i in 9:
		var a := lerpf(-1.4, 1.4, float(i) / 8.0)
		var l := 0.75 + 0.25 * cos(a * 2.0)
		ruff.append([OrganicMesh.bezier("cerb_ruff", Vector3.ZERO, Vector3(0, 0.5, 0.3), Vector3(0, 0.85, 0.95), 0.18, 0.02, 5, 5, 0.6), Transform3D(Basis(Vector3.BACK, a) * Basis().scaled(Vector3.ONE * l), Vector3(sin(a) * 0.6, cos(a) * 0.55, 0.35))])
	ModelKit.part(head, OrganicMesh.merge("cerb_ruff", ruff), fur)
	var maw := CreatureSkin.mouth(Color(0.28, 0.05, 0.03))
	ModelKit.part(head, OrganicMesh.merge("cerb_maw", [[OrganicMesh.blob("cerb_maw_in", Vector3(0.42, 0.14, 1.0), 0.1, 7, 10), Transform3D(Basis(), Vector3(0, -0.36, -1.2))],
		[OrganicMesh.blob("cerb_nose", Vector3(0.24, 0.16, 0.18), 0.2, 5, 8), Transform3D(Basis(), Vector3(0, 0.08, -2.55))]]), maw)
	var throat := ModelKit.part(head, ModelKit.sphere(0.3, 8), ModelKit.glow(Color(1.0, 0.42, 0.08), 6.0, 0.5), Vector3(0, -0.35, -0.5), Vector3.ZERO, Vector3(1.0, 0.6, 1.6))
	throats.append(throat)
	var jaw := ModelKit.joint(head, "Jaw", Vector3(0, -0.38, 0.05))
	ModelKit.part(jaw, OrganicMesh.profile("cerb_jaw", Vector3(0, 0, 0.2), Vector3(0, -0.04, -2.4),
		[[0.0, 0.55, 0.3], [0.25, 0.48, 0.26, -0.04], [0.7, 0.36, 0.2], [1.0, 0.16, 0.1, 0.02]], 14, 12), head_mat)
	ModelKit.part(jaw, OrganicMesh.blob("cerb_tongue", Vector3(0.25, 0.08, 0.85), 0.15, 13, 8), CreatureSkin.mouth(Color(0.42, 0.08, 0.06)), Vector3(0, 0.1, -0.9))
	ModelKit.part(jaw, _teeth("cerb_teeth_low", 1.0), bone)
	var mouth := ModelKit.joint(head, "Mouth", Vector3(0, -0.42, -2.45))
	var b := BreathStream.new().setup(15.0 if k != 1 else 12.0, 9.0 if k != 1 else 16.0, "hellfire" if k != 1 else "ash", 1.6 if k != 1 else 2.2)
	mouth.add_child(b)
	heads.append(head)
	jaws.append(jaw)
	mouths.append(mouth)
	breaths.append(b)


func _teeth(key: String, dir: float) -> ArrayMesh:
	var parts: Array = []
	for side: float in [-1.0, 1.0]:
		for i in 7:
			var f := float(i) / 6.0
			var z := lerpf(-0.7, -2.45, f)
			var half_w := lerpf(0.42, 0.14, f) if dir < 0.0 else lerpf(0.36, 0.12, f)
			var fang := i == 5
			var l := (0.5 if fang else lerpf(0.2, 0.13, f)) * (0.8 if dir > 0.0 else 1.0)
			var tm := OrganicMesh.bezier("cerb_tooth_%d_%d" % [int(dir), int(l * 100.0)], Vector3.ZERO, Vector3(0, dir * l * 0.6, 0.04 * l), Vector3(0, dir * l, 0.28 * l), l * 0.2, l * 0.02, 5, 6)
			parts.append([tm, Transform3D(Basis(Vector3.BACK, side * dir * -0.1), Vector3(side * half_w, -0.34 if dir < 0.0 else 0.06, z))])
	return OrganicMesh.merge(key, parts)


func _build_leg(front: bool, side: float, phase: float, skin: Material, fur: Material, claw_mat: Material) -> Dictionary:
	var lens := [1.75, 1.95, 0.8] if front else [1.9, 2.05, 1.35]
	var profs := []
	if front:
		profs = [[[0.0, 0.85, 1.0], [0.3, 0.72, 0.85], [0.75, 0.48, 0.55], [1.0, 0.38, 0.42]],
			[[0.0, 0.42, 0.5], [0.25, 0.44, 0.52], [0.8, 0.3, 0.32], [1.0, 0.26, 0.28]],
			[[0.0, 0.27, 0.28], [1.0, 0.3, 0.28]]]
	else:
		profs = [[[0.0, 0.92, 1.15], [0.3, 0.86, 1.05], [0.75, 0.52, 0.6], [1.0, 0.38, 0.42]],
			[[0.0, 0.4, 0.5], [0.3, 0.42, 0.55], [0.8, 0.26, 0.3], [1.0, 0.22, 0.25]],
			[[0.0, 0.22, 0.25], [0.5, 0.2, 0.22], [1.0, 0.24, 0.24]]]
	var segs: Array[Node3D] = []
	for k in 3:
		var n := Node3D.new()
		n.top_level = true
		add_child(n)
		ModelKit.part(n, OrganicMesh.profile("cerb_%s_%d" % ["arm" if front else "leg", k], Vector3.ZERO, Vector3(0, float(lens[k]), 0), profs[k], 14, 10, Vector3.BACK), skin)
		segs.append(n)
	# Shaggy fur at the elbows / hocks.
	var tuft: Array = []
	for i in 5:
		var a := lerpf(-1.0, 1.0, float(i) / 4.0)
		tuft.append([OrganicMesh.bezier("cerb_legtuft", Vector3.ZERO, Vector3(0, -0.3, 0.2), Vector3(0, -0.55, 0.55), 0.13, 0.02, 4, 5, 0.6), Transform3D(Basis(Vector3.UP, a), Vector3(sin(a) * 0.3, 0.2, cos(a) * 0.3))])
	ModelKit.part(segs[1], OrganicMesh.merge("cerb_legtuft", tuft), fur, Vector3(0, 0.1, 0.0))
	var foot := Node3D.new()
	foot.top_level = true
	add_child(foot)
	var toes: Array = []
	var claws: Array = []
	for t in 4:
		var a := lerpf(-0.5, 0.5, float(t) / 3.0)
		var tl := 0.55 * (1.0 - absf(a) * 0.3)
		var dir := Vector3(sin(a), 0, -cos(a))
		toes.append([OrganicMesh.blob("cerb_toe", Vector3(0.2, 0.2, 0.3), 0.15, 3, 8), Transform3D(Basis(Vector3.UP, -a), dir * tl + Vector3(0, 0.18, 0))])
		claws.append([OrganicMesh.bezier("cerb_claw", Vector3.ZERO, Vector3(0, 0.08, -0.22), Vector3(0, -0.15, -0.4), 0.09, 0.01, 5, 5), Transform3D(Basis(Vector3.UP, -a), dir * (tl + 0.22) + Vector3(0, 0.2, 0))])
	toes.append([OrganicMesh.blob("cerb_pad", Vector3(0.48, 0.28, 0.5), 0.15, 5, 10), Transform3D(Basis(), Vector3(0, 0.26, 0.12))])
	ModelKit.part(foot, OrganicMesh.merge("cerb_paw", toes), skin)
	var cm := ModelKit.part(foot, OrganicMesh.merge("cerb_claws", claws), claw_mat)
	cm.visibility_range_end = 110.0
	var hip_off := Vector3(side * 1.15, -0.85, 0.35) if front else Vector3(side * 1.1, -0.5, 0.3)
	var rest := Vector3(side * 1.45, 0.0, -2.25) if front else Vector3(side * 1.45, 0.0, 3.0)
	return {"front": front, "side": side, "phase": phase, "lens": lens, "segs": segs, "foot": foot,
		"joint": SHOULDER if front else HIPS, "off": hip_off, "rest": rest}


# --- Animation ---------------------------------------------------------------------------

func _on_action(action_name: String) -> void:
	_impact_done = false
	_fx_t = 0.0
	if action_name == "die":
		_death_side = 1.0 if randf() < 0.5 else -1.0


func _fx_parent() -> Node3D:
	var ent := get_parent()
	if ent != null and ent.get_parent() is Node3D:
		return ent.get_parent() as Node3D
	return self


func _ground() -> float:
	return ground_y if not is_nan(ground_y) else _last_ground


func _fx(style: String, local_offset: Vector3, scale := 1.0) -> void:
	var pos := global_transform * local_offset
	pos.y = _ground() + 0.2
	CreatureFx.play(_fx_parent(), style, pos, scale)


## Yaw (radians) of head k's breath relative to the body at progress p.
static func breath_yaw(k: int, p: float) -> float:
	var f := clampf((p - BREATH_ON) / (BREATH_OFF - BREATH_ON), 0.0, 1.0)
	f = f * f * (3.0 - 2.0 * f)
	match k:
		0:
			return lerpf(0.55, 0.05, f)
		2:
			return lerpf(-0.55, -0.05, f)
	return 0.0


func _animate(delta: float) -> void:
	if chain == null:
		return
	var root := global_transform
	var basis := root.basis.orthonormalized()
	var fwd := -basis.z
	if not _prev_root.is_finite():
		_prev_root = root.origin
	_vel = _vel.lerp((root.origin - _prev_root) / maxf(delta, 0.001), 1.0 - exp(-6.0 * delta))
	_prev_root = root.origin
	var yaw_now := atan2(-fwd.x, -fwd.z)
	if not is_nan(_prev_yaw):
		_yaw_rate = lerpf(_yaw_rate, angle_difference(_prev_yaw, yaw_now) / maxf(delta, 0.001), 1.0 - exp(-6.0 * delta))
	_prev_yaw = yaw_now
	var p := action_progress()
	var w := action_weight(0.1, 0.2)
	var act := _action if p >= 0.0 else ""
	var airborne := not grounded and act == "pounce"
	if grounded and act != "pounce":
		_last_ground = root.origin.y
	var speed := Vector2(_vel.x, _vel.z).length()
	_walk = damp(_walk, clampf(maxf(speed, move_speed) / 5.0, 0.0, 1.0), 5.0, delta)
	var rate := maxf(speed, move_speed) / 4.2 + maxf(absf(turn_rate), absf(_yaw_rate)) * 0.3
	_gait += delta * clampf(rate, 0.0, 2.2)
	_rage = damp(_rage, rage, 1.0, delta)
	var breathe := sin(_time * 1.6)

	var t_crouch := 0.0
	var t_pitch := 0.0
	var t_roll := 0.0
	var t_rear := 0.0
	var t_lunge := 0.0
	var t_stretch := 0.0
	var head_t: Array[Vector3] = []
	var pitch_t := [-0.15, -0.2, -0.15]
	var jaw_t := [0.0, 0.0, 0.0]
	var throat_t := [0.35, 0.35, 0.35]
	var breath_t := [false, false, false]
	var aim := [Vector3.INF, Vector3.INF, Vector3.INF]
	for k in 3:
		var idle := Vector3(sin(_time * 0.7 + k * 2.1) * 0.25, sin(_time * 0.9 + k * 1.3) * 0.2, cos(_time * 0.6 + k) * 0.2)
		head_t.append((HEADS[k] as Vector3) + idle)
		jaw_t[k] = 0.06 + maxf(0.0, sin(_time * 2.2 + k * 2.0)) * 0.22
		pitch_t[k] = -0.15 + sin(_time * 0.8 + k) * 0.08

	match act:
		"bite", "attack":
			for k in 3:
				var off := [0.12, 0.0, 0.24][k] as float
				var lp := clampf((p - off) / 0.65, 0.0, 1.0)
				var wind := keys(lp, [[0, 0], [0.4, 1.0], [0.6, 0.0], [1, 0]])
				var strike := keys(lp, [[0, 0], [0.5, 0.0], [0.72, 1.0], [0.85, 1.0], [1, 0]])
				var tgt := Vector3((k - 1) * 1.6, 1.9, -9.0)
				head_t[k] = head_t[k] + Vector3(0, 0.8, 1.2) * wind
				head_t[k] = head_t[k].lerp(tgt, strike)
				jaw_t[k] = keys(lp, [[0, 0.1], [0.45, 1.0], [0.7, 1.0], [0.76, 0.0], [1, 0.1]])
				pitch_t[k] = lerpf(pitch_t[k], -0.55, strike) + 0.25 * wind
			t_lunge = keys(p, [[0, 0], [0.45, 0.0], [0.6, 1.2], [0.85, 1.0], [1, 0]])
			t_crouch = 0.3 * w
			if p > IMPACT["bite"] and not _impact_done:
				_impact_done = true
				_fx("dust_cloud", Vector3(0, 0, -9.0), 0.7)
		"lunge":
			var strike := keys(p, [[0, 0], [0.25, -0.5], [0.45, 1.0], [0.7, 1.0], [1, 0]])
			t_lunge = maxf(0.0, strike) * 2.6
			t_crouch = keys(p, [[0, 0], [0.25, 0.8], [0.45, 0.1], [1, 0]])
			t_pitch = -0.08 * maxf(0.0, strike)
			for k in 3:
				head_t[k] = head_t[k].lerp(Vector3((k - 1) * 1.8, 2.4, -9.5), maxf(0.0, strike))
				jaw_t[k] = keys(p, [[0, 0.1], [0.3, 1.0], [0.47, 0.0], [1, 0.1]])
				pitch_t[k] = lerpf(pitch_t[k], -0.45, maxf(0.0, strike))
			if p > IMPACT["lunge"] and not _impact_done:
				_impact_done = true
				_fx("dust_cloud", Vector3(0, 0, -7.0), 0.9)
		"pounce":
			var coil := keys(p, [[0, 0], [0.25, 1.0], [0.35, 0.0], [1, 0]])
			var leap := keys(p, [[0, 0], [0.3, 0.0], [0.4, 1.0], [0.7, 1.0], [0.8, 0.0], [1, 0]])
			var land := keys(p, [[0, 0], [0.76, 0.0], [0.82, 1.0], [1, 0]])
			t_crouch = coil * 1.1 + land * 0.9
			t_pitch = coil * -0.12 + leap * 0.08 - land * 0.1
			t_stretch = leap
			for k in 3:
				head_t[k] = head_t[k] + Vector3(0, -0.6, -1.4) * leap + Vector3(0, -1.6, -1.0) * coil
				jaw_t[k] = 0.9 * leap + 0.3 * coil
				pitch_t[k] -= 0.35 * leap
			if p > IMPACT["pounce"] and not _impact_done:
				_impact_done = true
				_fx("ash_cloud", Vector3(0, 0, -3.5), 1.5)
				_fx("embers", Vector3(0, 0.3, -3.5), 2.0)
				_quake(root.origin, 0.45)
				Audio.play("land_heavy", root.origin, 5.0, 0.5)
		"slam":
			var up := keys(p, [[0, 0], [0.4, 1.0], [0.5, 0.6], [0.56, 0.0], [1, 0]])
			var down := keys(p, [[0, 0], [0.5, 0.0], [0.56, 1.0], [0.8, 0.7], [1, 0]])
			t_rear = up * 0.75
			t_crouch = down * 0.9
			t_pitch = -down * 0.1
			for k in 3:
				head_t[k] = head_t[k] + Vector3(0, 1.8, 1.4) * up + Vector3(0, -1.5, -1.0) * down
				jaw_t[k] = 0.4 + 0.6 * maxf(up, down)
				pitch_t[k] += 0.5 * up - 0.4 * down
			if p > IMPACT["slam"] and not _impact_done:
				_impact_done = true
				_fx("ash_cloud", Vector3(0, 0, -3.8), 1.6)
				for i in 8:
					var a := TAU * float(i) / 8.0
					_fx("embers", Vector3(cos(a), 0, sin(a)) * 6.0 + Vector3(0, 0, -2.0), 1.6)
				_quake(root.origin, 0.6)
				Audio.play("stomp", root.origin, 8.0, 0.5)
		"howl", "roar", "summon":
			t_rear = 0.18 * w
			for k in 3:
				var off := float(k) * 0.08
				var hw := clampf((p - off) / 0.25, 0.0, 1.0) * (1.0 - smoothstep(0.82, 1.0, p))
				head_t[k] = head_t[k] + Vector3((k - 1) * 0.5, 1.6, 1.0) * hw
				pitch_t[k] = lerpf(pitch_t[k], 0.95, hw)
				jaw_t[k] = lerpf(jaw_t[k], 0.85 + sin(_time * 28.0 + k) * 0.05, hw)
				throat_t[k] = 0.4 + 1.6 * hw
		"breath":
			var wind := keys(p, [[0, 0], [0.2, 1.0], [BREATH_ON, 0.0], [1, 0]])
			var fire := keys(p, [[0, 0], [BREATH_ON - 0.04, 0.0], [BREATH_ON + 0.02, 1.0], [BREATH_OFF, 1.0], [1, 0]])
			t_crouch = 0.35 * fire
			for k in 3:
				head_t[k] = head_t[k] + Vector3(0, 0.9, 1.2) * wind
				var yaw := breath_yaw(k, p)
				var hp := Vector3((k - 1) * 1.6, 4.6 if k != 1 else 5.3, -5.6).rotated(Vector3.UP, yaw * 0.6)
				head_t[k] = head_t[k].lerp(hp, fire)
				aim[k] = Vector3(0, 0, -8.5 if k != 1 else -7.0).rotated(Vector3.UP, yaw) + Vector3((k - 1) * 1.2, 0, 0)
				jaw_t[k] = lerpf(0.35 * wind, 0.85, fire)
				throat_t[k] = 0.5 + 2.8 * maxf(wind, fire)
				breath_t[k] = p > BREATH_ON and p < BREATH_OFF
		"rake":
			# Right forepaw raised, then swept across the front.
			var up := keys(p, [[0, 0], [0.35, 1.0], [0.5, 0.3], [1, 0]])
			var sweep := keys(p, [[0, 0], [0.4, 0.0], [0.55, 1.0], [0.8, 1.0], [1, 0]])
			t_roll = 0.12 * up - 0.1 * sweep
			t_rear = 0.15 * up
			t_lunge = 0.6 * sweep
			for k in 3:
				head_t[k] = head_t[k] + Vector3(-0.8, 0.4, 0.4) * up + Vector3(1.0, -0.6, -0.6) * sweep
				jaw_t[k] = 0.3 + 0.6 * maxf(up, sweep)
			if p > IMPACT["rake"] and not _impact_done:
				_impact_done = true
				_fx("ash_cloud", Vector3(-1.5, 0, -6.5), 1.0)
				_quake(root * Vector3(0, 0, -6.0), 0.25)
		"kick":
			# Hind legs buck out behind; the heads drop.
			var coil := keys(p, [[0, 0], [0.35, 1.0], [0.48, 0.0], [1, 0]])
			var buck := keys(p, [[0, 0], [0.42, 0.0], [0.52, 1.0], [0.75, 0.7], [1, 0]])
			t_pitch = 0.12 * coil - 0.32 * buck
			t_crouch = 0.4 * coil
			for k in 3:
				head_t[k] = head_t[k] + Vector3(0, -1.4, -0.6) * buck
				pitch_t[k] -= 0.3 * buck
				jaw_t[k] = 0.3 + 0.5 * buck
			if p > IMPACT["kick"] and not _impact_done:
				_impact_done = true
				_fx("ash_cloud", Vector3(0, 0, 7.0), 1.3)
				_quake(root * Vector3(0, 0, 6.0), 0.3)
		"charge":
			# Wind-up crouch, then a headlong gallop with the heads low.
			var wind := keys(p, [[0, 0], [0.3, 1.0], [0.45, 0.0], [1, 0]])
			var run := keys(p, [[0, 0], [0.4, 0.0], [0.5, 1.0], [0.85, 1.0], [1, 0]])
			t_crouch = 0.9 * wind + 0.3 * run
			t_pitch = -0.1 * run
			t_lunge = 0.8 * run
			_gait += delta * 2.2 * run
			for k in 3:
				head_t[k] = head_t[k].lerp(Vector3((k - 1) * 1.7, 2.6, -8.5), run) + Vector3(0, -0.8, 0.6) * wind
				jaw_t[k] = 0.4 + 0.6 * run
				pitch_t[k] = lerpf(pitch_t[k], -0.5, run)
				throat_t[k] = 0.5 + run
		"spit":
			# Each head in turn rears back and spits a gout of fire.
			for k in 3:
				var off := [0.0, 0.25, 0.5][k] as float
				var lp := clampf((p - off) / 0.4, 0.0, 1.0)
				var back := keys(lp, [[0, 0], [0.5, 1.0], [0.65, 0.0], [1, 0]])
				var spit := keys(lp, [[0, 0], [0.55, 0.0], [0.7, 1.0], [1, 0]])
				head_t[k] = head_t[k] + Vector3(0, 0.9, 1.3) * back + Vector3(0, -0.4, -1.4) * spit
				pitch_t[k] += 0.5 * back - 0.3 * spit
				jaw_t[k] = maxf(0.3 * back, 1.0 * spit)
				throat_t[k] = 0.5 + 2.5 * maxf(back, spit)
		"combo":
			# The heads strike one after another: left, centre, right.
			for k in 3:
				var off := [0.0, 0.3, 0.6][k] as float
				var lp := clampf((p - off) / 0.4, 0.0, 1.0)
				var wind := keys(lp, [[0, 0], [0.45, 1.0], [0.55, 0.0], [1, 0]])
				var strike := keys(lp, [[0, 0], [0.5, 0.0], [0.6, 1.0], [0.8, 1.0], [1, 0]])
				var tgt := Vector3((k - 1) * 3.8, 1.9, -8.6)
				head_t[k] = (head_t[k] + Vector3(0, 0.9, 1.3) * wind).lerp(tgt, strike)
				jaw_t[k] = keys(lp, [[0, 0.1], [0.5, 1.0], [0.62, 0.0], [1, 0.1]])
				pitch_t[k] = lerpf(pitch_t[k], -0.55, strike) + 0.25 * wind
			t_lunge = 0.6 * w
			t_roll = 0.06 * sin(p * TAU)
		"phase":
			# Rears onto its hind legs, all three heads howling, the cracks blazing.
			t_rear = 0.5 * w
			t_crouch = -0.1 * w
			for k in 3:
				head_t[k] = head_t[k] + Vector3((k - 1) * 0.9, 2.2, 1.2) * w
				pitch_t[k] = lerpf(pitch_t[k], 1.0, w)
				jaw_t[k] = lerpf(jaw_t[k], 0.95 + sin(_time * 30.0 + k) * 0.05, w)
				throat_t[k] = 0.4 + 2.4 * w
			if p > 0.3 and not _impact_done:
				_impact_done = true
				_fx("embers", Vector3(0, 0.5, -2.0), 3.0)
				_quake(root.origin, 0.5)
		"hit":
			var s := sin(PI * p)
			t_roll = 0.08 * s
			for k in 3:
				head_t[k] = head_t[k] + Vector3(0.4 * (k - 1), 0.5, 1.0) * s
				jaw_t[k] = maxf(jaw_t[k], 0.5 * s)

	if _dead:
		var f := clampf(_dead_t / 1.8, 0.0, 1.0)
		t_crouch = 2.9 * f
		t_roll = _death_side * 0.55 * f
		t_pitch = 0.0
		t_rear = 0.0
		for k in 3:
			head_t[k] = (head_t[k] as Vector3).lerp(Vector3(_death_side * 2.0 + (k - 1) * 2.4, 0.9, -5.5 + absf(k - 1) * 1.0), f)
			jaw_t[k] = 0.45
			pitch_t[k] = -0.1
			throat_t[k] = 0.0
			breath_t[k] = false

	_crouch = damp(_crouch, t_crouch, 10.0, delta)
	_pitch = damp(_pitch, t_pitch, 6.0, delta)
	_roll = damp(_roll, t_roll, 4.0, delta)
	_rear = damp(_rear, t_rear, 7.0, delta)
	_lunge = damp(_lunge, t_lunge, 12.0, delta)
	_stretch = damp(_stretch, t_stretch, 10.0, delta)

	# --- Torso ------------------------------------------------------------------------
	var trot := sin(_gait * TAU * 2.0)
	var bob := breathe * 0.04 - absf(trot) * 0.12 * _walk
	var pivot := Vector3(0, 4.1, 0.2)
	var body_rot := Basis(Vector3.RIGHT, _pitch + trot * 0.02 * _walk) * Basis(Vector3.BACK, _roll + sin(_gait * TAU) * 0.025 * _walk)
	var chest := pivot + body_rot * (CHEST - pivot)
	var pelvis := pivot + body_rot * (HIP_POS - pivot)
	chest = pelvis + Basis(Vector3.RIGHT, _rear) * (chest - pelvis)
	var down := Vector3(0, -_crouch * 0.6 + bob, 0)
	chest += down + Vector3(0, 0, -_lunge - _stretch * 0.4)
	pelvis += down * 0.85 + Vector3(0, 0, -_lunge * 0.7 + _stretch * 0.4)
	var chest_w := root * chest
	var pelvis_w := root * pelvis
	var body_up := (basis * (body_rot * Vector3.UP)).normalized()
	var body_fwd := (chest_w - pelvis_w).normalized()
	var torso_up := body_up * 0.22
	for j in range(0, PELVIS + 1):
		var f := float(j) / PELVIS
		chain.display[j] = chest_w.lerp(pelvis_w, f) + torso_up * sin(PI * f)
	_tail_sim(delta, pelvis_w, body_fwd)
	chain.apply()
	var torso_glow := _rage * 1.2 + 0.1 * sin(_time * 1.3)
	chain.mesh_instance.set_instance_shader_parameter(&"inner_glow", torso_glow)
	mane_fx.amount_ratio = 0.5 + 0.5 * _rage

	# --- Heads and necks --------------------------------------------------------------
	for k in 3:
		var root_w: Vector3 = root * ((ROOTS[k] as Vector3) + down + Vector3(0, 0, -_lunge - _stretch * 0.4))
		var target_w: Vector3 = root * ((head_t[k] as Vector3) + down * 0.6 + Vector3(0, 0, -_lunge))
		var look := fwd.rotated(Vector3.UP, (1 - k) * 0.25)
		if look_target.is_finite() and not _dead and act not in ["bite", "attack", "lunge", "breath", "pounce"]:
			var to := look_target - target_w
			var flat := Vector3(to.x, 0, to.z)
			if flat.length() > 1.5:
				var yaw := clampf(fwd.signed_angle_to(flat.normalized(), Vector3.UP) + (1 - k) * 0.2, -1.0, 1.0)
				look = fwd.rotated(Vector3.UP, yaw)
				target_w = root_w + (target_w - root_w).rotated(Vector3.UP, yaw * 0.4)
				pitch_t[k] = lerpf(pitch_t[k], clampf(atan2(to.y, flat.length()), -0.6, 0.3), 0.6)
		var a: Vector3 = aim[k]
		if a.is_finite():
			var aw := root * a
			aw.y = _ground()
			var to := aw - target_w
			look = Vector3(to.x, 0, to.z).normalized()
			pitch_t[k] = atan2(to.y, Vector2(to.x, to.z).length()) + 0.15
		var reach := NECK_LEN * 1.25
		if target_w.distance_to(root_w) > reach:
			target_w = root_w + (target_w - root_w).normalized() * reach
		var hp: Vector3 = _head_pos[k]
		if not hp.is_finite():
			hp = target_w
		var hr := 15.0 if act in ["bite", "attack", "lunge"] else 7.0
		hp = hp.lerp(target_w, 1.0 - exp(-hr * delta))
		_head_pos[k] = hp
		var hl: Vector3 = _head_look[k]
		hl = DragonModel.turn_dir(hl, look, 1.0 - exp(-6.0 * delta))
		_head_look[k] = hl
		_pitch_h[k] = damp(float(_pitch_h[k]), float(pitch_t[k]), 8.0, delta)
		_jaw[k] = damp(float(_jaw[k]), float(jaw_t[k]), 16.0, delta)
		_throat[k] = damp(float(_throat[k]), float(throat_t[k]), 6.0, delta)
		var hb := Basis.looking_at(hl, Vector3.UP) * Basis(Vector3.RIGHT, float(_pitch_h[k]))
		if _dead:
			hb = hb * Basis(Vector3.BACK, _death_side * 0.8 * clampf(_dead_t / 1.5, 0.0, 1.0))
		var head: Node3D = heads[k]
		head.global_transform = Transform3D(hb.scaled(Vector3.ONE * float(head.get_meta("scale", 1.0))), hp)
		(jaws[k] as Node3D).rotation.x = float(_jaw[k]) * 0.7
		(throats[k] as MeshInstance3D).set_instance_shader_parameter(&"intensity", float(_throat[k]) * (0.5 + float(_jaw[k])))
		eyes[k * 2].set_instance_shader_parameter(&"intensity", 0.0 if _dead else 1.0 + _rage * 0.6)
		eyes[k * 2 + 1].set_instance_shader_parameter(&"intensity", 0.0 if _dead else 1.0 + _rage * 0.6)
		# Neck: a curve from the root inside the chest to the back of the skull.
		var nc: SerpentChain = necks[k]
		var p0 := hp + hb.z * 0.3
		var p1 := p0 + hb.z * 1.2
		var p3 := root_w
		var p2 := p3 + body_fwd * 1.1 + body_up * 0.9
		_curve(nc, p0, p1, p2, p3)
		nc.apply()
		nc.mesh_instance.set_instance_shader_parameter(&"inner_glow", torso_glow)
		# Breath.
		var b: BreathStream = breaths[k]
		var on: bool = breath_t[k]
		if on != b.on:
			b.set_on(on)
			if on and k != 1:
				Audio.play("furnace_roar", hp, 5.0, 0.8)
		if b.on:
			b.set_ground(_ground())
	if breaths[0].on or breaths[2].on:
		_fx_t -= delta
		if _fx_t <= 0.0:
			_fx_t = 0.2
			for k: int in [0, 2]:
				var hit := (breaths[k] as BreathStream).ground_hit(_ground())
				if hit.is_finite():
					CreatureFx.play(_fx_parent(), "embers", hit + Vector3(0, 0.3, 0), 1.8)
	_swing_chains(delta)
	_pose_legs(delta, root, basis, chest_w, pelvis_w, body_rot, airborne)


func _curve(nc: SerpentChain, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> void:
	var n := nc.bones
	for j in n:
		var t := float(j) / (n - 1)
		var u := 1.0 - t
		nc.display[j] = p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t)


func _tail_sim(delta: float, pelvis_w: Vector3, body_fwd: Vector3) -> void:
	var n := BONES
	var back := -body_fwd
	if not _tail_ready:
		_tail_ready = true
		for i in range(PELVIS, n):
			_tail[i] = pelvis_w + back * _seg * (i - PELVIS)
	_tail[PELVIS] = pelvis_w
	var k := 1.0 - exp(-8.0 * delta)
	var wag := 0.25 + 0.25 * _walk + 0.3 * _rage
	var prev := back
	for i in range(PELVIS + 1, n):
		var f := float(i - PELVIS) / (n - 1 - PELVIS)
		var yaw := sin(_time * (2.4 + _rage * 2.0) - f * 2.5) * wag * f - turn_rate * 0.08 * f
		var lift := 0.35 - f * 0.55
		if _dead:
			lift = -0.4
			yaw = 0.6 * _death_side * f
		var want := (back.rotated(Vector3.UP, yaw) + Vector3.UP * lift).normalized()
		var d := _tail[i] - _tail[i - 1]
		d = d.normalized() if d.length_squared() > 1e-6 else want
		d = d.lerp(want, k * (0.6 + (1.0 - f))).normalized()
		d = d.lerp(prev, 0.2).normalized()
		var pt := _tail[i - 1] + d * _seg
		if pt.y < _ground() + 0.3:
			pt.y = _ground() + 0.3
		_tail[i] = pt
		prev = d
	for i in range(PELVIS + 1, n):
		chain.display[i] = _tail[i]


## Broken chains hang from the collars and swing with the necks (damped pendulums).
func _swing_chains(delta: float) -> void:
	for c: Array in chains:
		var pivot: Node3D = c[0]
		var parent := pivot.get_parent() as Node3D
		var pos := parent.global_transform * Vector3(0, -1.0, 0)
		var prev: Vector2 = c[2]
		var vel := Vector2(pos.x - prev.x, pos.z - prev.y) / maxf(delta, 0.001)
		c[2] = Vector2(pos.x, pos.z)
		var swing: Vector2 = c[1]
		swing += (-vel * 0.03 - swing * 6.0 * delta) * minf(1.0, delta * 10.0)
		swing = swing.limit_length(0.9)
		c[1] = swing
		# Hang down in world space, tilted by the swing.
		var hang := (Vector3.DOWN + Vector3(swing.x, 0, swing.y)).normalized()
		var x := Vector3.RIGHT - hang * Vector3.RIGHT.dot(hang)
		if x.length_squared() < 1e-4:
			x = Vector3.BACK
		x = x.normalized()
		var y := -hang
		var z := x.cross(y).normalized()
		pivot.global_transform = Transform3D(Basis(x, y, z), pos)


func _pose_legs(_delta: float, root: Transform3D, basis: Basis, chest_w: Vector3, pelvis_w: Vector3, body_rot: Basis, airborne: bool) -> void:
	var fwd := -basis.z
	var ground := _ground()
	var act := _action if action_progress() >= 0.0 else ""
	var p := action_progress()
	for li in legs.size():
		var leg: Dictionary = legs[li]
		var front: bool = leg["front"]
		var side: float = leg["side"]
		var hip := chain.joint(int(leg["joint"])) + chain.frame(int(leg["joint"])) * (leg["off"] as Vector3)
		var rest: Vector3 = leg["rest"]
		var ph := fposmod(_gait + float(leg["phase"]), 1.0)
		var duty := 0.6
		var stride := 2.4 * minf(1.0, _walk * 2.0)
		var foot_l := rest
		var lift := 0.0
		if ph < duty:
			foot_l.z += stride * (ph / duty - 0.5)
		else:
			var s := (ph - duty) / (1.0 - duty)
			foot_l.z += stride * (0.5 - s)
			lift = sin(PI * s) * 0.8 * minf(1.0, _walk * 2.0)
		var down_now := lift < 0.05
		if down_now and not bool(_foot_was_down[li]) and _walk > 0.35:
			var fw := root * foot_l
			fw.y = ground
			CreatureFx.play(_fx_parent(), "ash_cloud", fw, 0.4)
			Audio.play("stomp", fw, -9.0, 0.75)
			_quake(fw, 0.08)
		_foot_was_down[li] = down_now
		var foot_w := root * foot_l
		foot_w.y = ground + lift
		var c: float = leg["lens"][2]
		# Rearing slam: forepaws lifted high, then hammered down ahead.
		if front and act == "slam":
			var up := keys(p, [[0, 0], [0.4, 1.0], [0.5, 0.6], [0.56, 0.0], [1, 0]])
			var raised := root * Vector3(side * 1.3, 4.2, -3.6)
			var struck := root * Vector3(side * 1.4, 0.0, -3.8)
			struck.y = ground
			foot_w = foot_w.lerp(struck, keys(p, [[0, 0], [0.5, 0.0], [0.56, 1.0], [0.85, 1.0], [1, 0]])).lerp(raised, up)
		# Rake: the right forepaw lifts and sweeps from right to left.
		if front and act == "rake" and side > 0.0:
			var up := keys(p, [[0, 0], [0.35, 1.0], [0.55, 0.6], [0.8, 0.2], [1, 0]])
			var sweep := keys(p, [[0, 0], [0.4, 0.0], [0.55, 1.0], [1, 1.0]])
			var paw := root * Vector3(lerpf(2.6, -2.2, sweep), 0.4 + 2.6 * up, -5.2 - 1.2 * up)
			paw.y = maxf(paw.y, ground)
			foot_w = foot_w.lerp(paw, keys(p, [[0, 0], [0.2, 1.0], [0.85, 1.0], [1, 0]]))
		# Kick: both hind legs thrown out behind.
		if not front and act == "kick":
			var buck := keys(p, [[0, 0], [0.42, 0.0], [0.52, 1.0], [0.75, 0.7], [1, 0]])
			var out := root * Vector3(side * 1.3, 2.2, rest.z + 3.4)
			foot_w = foot_w.lerp(out, buck)
		if act == "pounce" and _stretch > 0.01:
			var reach := (chest_w if front else pelvis_w) + basis * (body_rot * (Vector3(side * 1.2, -2.6, -3.0) if front else Vector3(side * 1.2, -2.4, 3.2)))
			foot_w = foot_w.lerp(reach, _stretch)
		if _dead:
			var splay := root * Vector3(side * 3.2, 0.0, rest.z * 1.1)
			splay.y = ground + 0.3
			foot_w = foot_w.lerp(splay, clampf(_dead_t / 1.4, 0.0, 1.0))
		var lens: Array = leg["lens"]
		var segs: Array = leg["segs"]
		var back_dir := basis.z
		var ankle: Vector3
		var pole: Vector3
		if front:
			ankle = foot_w + Vector3.UP * c * 0.95 + back_dir * c * 0.15
			pole = back_dir + basis.x * side * 0.2
		else:
			ankle = foot_w + Vector3.UP * c * 0.85 + back_dir * c * 0.5
			pole = -back_dir + basis.x * side * 0.2
		var knee := ArachnidModel._ik_knee(hip, ankle, float(lens[0]), float(lens[1]), pole)
		DragonModel._orient(segs[0], hip, knee, basis.x)
		DragonModel._orient(segs[1], knee, ankle, basis.x)
		DragonModel._orient(segs[2], ankle, foot_w + Vector3.UP * 0.22, basis.x)
		var foot: Node3D = leg["foot"]
		var fb := Basis.looking_at(fwd, Vector3.UP)
		if airborne:
			fb = fb * Basis(Vector3.RIGHT, -0.6 if front else 0.6)
		foot.global_transform = Transform3D(fb, foot_w)


func _quake(at: Vector3, strength: float) -> void:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null:
		return
	var d := cam.global_position.distance_to(at)
	var s := strength * clampf(1.0 - (d - 6.0) / 35.0, 0.0, 1.0)
	if s > 0.02 and Engine.get_main_loop() is SceneTree and (Engine.get_main_loop() as SceneTree).root.has_node("Events"):
		Events.screen_shake.emit(s)
