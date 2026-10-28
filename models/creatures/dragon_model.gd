class_name DragonModel
extends CreatureModel
## Ashvane, the Last Dragon: a 25 m western dragon drawn the Leviathan way.
##
## * Neck, torso and tail are ONE smooth skinned body (SerpentChain skeleton):
##   the neck is a curve from the withers to the head, the torso follows the
##   pose of the shoulders and hips, the tail is a follow-the-leader chain
##   that lags, drags on the ground and whips. Dorsal spikes ride the same
##   skin. Charcoal scales with bronze belly scutes; the seams of the throat
##   and chest smoulder and blaze up before it breathes.
## * Four muscular legs solved with IK each frame from a lateral-sequence
##   gait (digitigrade hind legs), clawed feet that plant.
## * A horned, armoured skull with a hinged jaw, two rows of teeth, brow and
##   cheek plates, molten eyes and a glowing gullet.
## * Bat-like wings on their own skeletons (humerus, forearm, four finger
##   bones, flank): the membranes are skinned between the fingers, so the
##   wings genuinely fold against the body on the ground and spread to a
##   30 m span to fly.
## * Actions: walk, roar, bite, claw, tail (sweep), gust (wing buffet),
##   breath (sweeping fire stream), takeoff, fly (hover / strafe), dive,
##   land, slam (crash landing), hit, die.
##
## Set `flying` (boss), `look_target` (where the head tracks), `ground_y`
## (arena floor, for flames and landings), `strafe` (breathing on the wing).
## Faces -Z; the origin is the ground under the belly.

const LENGTH := 25.5
const BONES := 28
const NECK := 7          ## joints 0..7: neck (0 behind the skull, 7 at the withers)
const PELVIS := 13       ## joints 7..13: torso, 13..27: tail
const SHOULDER := 8
const HIPS := 12
## Fraction of an action at which its blow lands (the boss times its telegraphs to these).
const IMPACT := {"bite": 0.55, "claw": 0.52, "tail": 0.55, "gust": 0.5, "slam": 0.35, "land": 0.42, "stomp": 0.55}
## Breath: fire from BREATH_ON to BREATH_OFF of the action while the head sweeps +-SWEEP.
const BREATH_ON := 0.3
const BREATH_OFF := 0.9
const SWEEP := 0.62
const CHEST := Vector3(0, 4.45, -2.4)
const HIP_POS := Vector3(0, 4.15, 3.27)

var flying := false
## Hovering and breathing fire on the ground beneath (strafing run).
var strafe := false
var look_target := Vector3.INF
var ground_y := NAN

var chain: SerpentChain
var head: Node3D
var jaw: Node3D
var mouth: Node3D
var breath: BreathStream
var throat: MeshInstance3D
var eyes: Array[MeshInstance3D] = []
var wings: Array = []
var legs: Array = []

var _seg := LENGTH / float(BONES - 1)
var _tail := PackedVector3Array()
var _tail_ready := false
var _walk := 0.0
var _fly := 0.0
var _gait := 0.0
var _flap := 0.0
var _flap_amp := 0.0
var _jaw := 0.0
var _fold := 1.0
var _raise := 0.0
var _rear := 0.0
var _pitch := 0.0
var _roll := 0.0
var _crouch := 0.0
var _lunge := 0.0
var _hip_yaw := 0.0
var _tail_sweep := 0.0
var _throat := 0.2
var _inner := 0.1
var _head_pos := Vector3.INF
var _look := Vector3.FORWARD
var _head_pitch := 0.0
var _prev_root := Vector3.INF
## Heading change measured from the model itself (works on clients too).
var _prev_yaw := NAN
var _yaw_rate := 0.0
var _bank := 0.0
var _vel := Vector3.ZERO
var _last_ground := 0.0
var _fx_t := 0.0
var _impact_done := false
var _death_side := 1.0
var _claw_side := 1.0
var _foot_was_down := []


func _enter_tree() -> void:
	TelegraphFx.listen(_on_telegraph)


func _exit_tree() -> void:
	TelegraphFx.unlisten(_on_telegraph)


## The claw rakes whichever side the boss marked.
func _on_telegraph(style: String, _shape: String, pos: Vector3, _dir: Vector3, _size: Vector3, _duration: float) -> void:
	if not is_inside_tree() or style != "claw" or pos.distance_to(global_position) > 40.0:
		return
	_claw_side = 1.0 if (pos - global_position).dot(global_transform.basis.x) >= 0.0 else -1.0


func _init() -> void:
	dissolve_delay = 4.0
	dissolve_time = 3.0
	durations["breath"] = 3.4
	durations["takeoff"] = 1.7
	durations["dive"] = 1.2
	durations["land"] = 1.2
	durations["slam"] = 1.6
	durations["roar"] = 2.0
	durations["bite"] = 1.3
	durations["claw"] = 1.3
	durations["tail"] = 1.5
	durations["gust"] = 1.6
	durations["fly"] = 1.0
	durations["charge"] = 1.8
	durations["stomp"] = 1.8
	durations["swoop"] = 1.4
	durations["rake"] = 1.4
	durations["hover"] = 3.6
	durations["phase"] = 2.0
	looping["fly"] = true


func _ember_extents() -> Vector3:
	return Vector3(3.0, 2.0, 7.0)


func _lod_size() -> float:
	return 14.0


func mouth_node() -> Node3D:
	return mouth


## Yaw (radians, about +Y) of the fire stream relative to the body at action progress p.
static func breath_yaw(p: float) -> float:
	var f := clampf((p - BREATH_ON) / (BREATH_OFF - BREATH_ON), 0.0, 1.0)
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(SWEEP, -SWEEP, f)


# --- Build -------------------------------------------------------------------------------

func _build() -> void:
	var back := Color(0.15, 0.085, 0.065)
	var belly := Color(0.4, 0.24, 0.14)
	var body_mat := CreatureSkin.scales(back, belly, 3.1, {"use_uv": true, "accent": Color(0.05, 0.03, 0.03), "accent_mode": 3,
		"accent_amount": 0.55, "accent_scale": 0.18, "bump": 1.5, "bump_distance": 130.0, "roughness": 0.42, "specular_amount": 0.5,
		"rim": 0.22, "plates": 1.0, "plate_spacing": 0.46, "plate_color": Color(0.6, 0.4, 0.22), "inner_span": Vector2(0.0, 10.5),
		"inner_color": Color(1.0, 0.42, 0.08), "inner_energy": 6.0, "belly_mix": 0.6})
	var head_mat := CreatureSkin.scales(back.lightened(0.04), belly, 5.0, {"accent": Color(0.05, 0.03, 0.03), "accent_mode": 3,
		"accent_amount": 0.45, "accent_scale": 0.6, "bump": 1.3, "bump_distance": 90.0, "roughness": 0.4, "specular_amount": 0.5, "rim": 0.22})
	var plate := CreatureSkin.scales(back.darkened(0.35), back, 1.7, {"bump": 1.6, "roughness": 0.35, "specular_amount": 0.6, "rim": 0.18, "belly_mix": 0.3})
	var limb_mat := CreatureSkin.scales(back, belly, 3.4, {"accent": Color(0.05, 0.03, 0.03), "accent_mode": 3, "accent_amount": 0.4,
		"accent_scale": 0.3, "bump": 1.4, "bump_distance": 90.0, "roughness": 0.45, "specular_amount": 0.45, "rim": 0.22, "belly_mix": 0.5})
	var horn := CreatureSkin.keratin(Color(0.62, 0.56, 0.45), {"roughness": 0.45, "belly": Color(0.16, 0.12, 0.1), "belly_mix": 0.8})
	var claw := CreatureSkin.keratin(Color(0.1, 0.085, 0.075), {"roughness": 0.25, "specular_amount": 0.7})
	var tooth := CreatureSkin.keratin(Color(0.9, 0.86, 0.74))
	var membrane := CreatureSkin.membrane(Color(0.2, 0.065, 0.045), {"use_uv": true, "backlight": 1.6, "pattern_scale": 0.85,
		"accent": Color(0.12, 0.03, 0.02), "accent_mode": 2, "accent_amount": 0.35, "accent_scale": 0.35, "rim": 0.35, "roughness": 0.55})

	# --- Body: neck + torso + tail -------------------------------------------------
	var prof := [[0.0, 0.62, 0.7, 0.0], [0.1, 0.66, 0.76, -0.02], [0.2, 0.86, 1.0, -0.1], [0.27, 1.45, 1.7, -0.3],
		[0.32, 1.78, 1.98, -0.32], [0.39, 1.72, 1.82, -0.18], [0.45, 1.5, 1.55, -0.02], [0.5, 1.44, 1.42, 0.06],
		[0.55, 1.12, 1.12, 0.05], [0.64, 0.78, 0.8, 0.0], [0.76, 0.48, 0.5, 0.0], [0.88, 0.26, 0.28, 0.0], [1.0, 0.07, 0.07, 0.0]]
	var tube := OrganicMesh.skinned_tube("dragon_body", LENGTH, BONES, prof, 96, 18)
	var spikes: Array = []
	for i in range(1, BONES - 1):
		var t := float(i) / (BONES - 1)
		var s := OrganicMesh._sample(prof, t)
		var top: float = s[1] + s[2]
		var h := 0.0
		if i < NECK:
			h = lerpf(0.45, 0.7, float(i) / NECK)
		elif i <= PELVIS:
			h = 1.05 - absf(float(i) - 9.0) * 0.06
		else:
			h = lerpf(0.75, 0.2, float(i - PELVIS) / (BONES - 1 - PELVIS))
		var sm := OrganicMesh.bezier("dragon_spike_%d" % int(h * 100.0), Vector3.ZERO, Vector3(0, h * 0.65, h * 0.25), Vector3(0, h, h * 0.75), h * 0.24, h * 0.02, 6, 6, 0.55)
		spikes.append([sm, Transform3D(Basis(), Vector3(0, top - 0.12, i * _seg)), i])
		if i > PELVIS + 1 and i < BONES - 3 and i % 2 == 0:
			for side: float in [-1.0, 1.0]:
				var lh := h * 0.45
				var lm := OrganicMesh.bezier("dragon_tspike_%d" % int(lh * 100.0), Vector3.ZERO, Vector3(0, lh * 0.6, lh * 0.3), Vector3(0, lh, lh * 0.8), lh * 0.25, lh * 0.03, 5, 5, 0.6)
				spikes.append([lm, Transform3D(Basis(Vector3.BACK, side * 1.05), Vector3(side * s[0] * 0.8, s[2] + s[1] * 0.45, i * _seg)), i])
	# The tail ends in a barbed blade.
	var blade := OrganicMesh.membrane("dragon_tail_blade", PackedVector2Array([Vector2(0, 0.0), Vector2(0.5, -0.35), Vector2(0.22, -1.0),
		Vector2(0, -1.5), Vector2(-0.22, -1.0), Vector2(-0.5, -0.35)]), 0.04, 0.1)
	spikes.append([blade, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.05, LENGTH - 0.6)), BONES - 1])
	var body_mesh := OrganicMesh.skinned_mesh("dragon_body_full", [OrganicMesh.surface_arrays(tube), OrganicMesh.skinned_parts(spikes)])
	chain = SerpentChain.new().setup(body_mesh, body_mat, BONES, LENGTH, 60.0)
	chain.name = "Chain"
	chain.stiffness = 0.0
	add_child(chain)
	chain.mesh_instance.material_override = null
	chain.mesh_instance.set_surface_override_material(0, body_mat)
	chain.mesh_instance.set_surface_override_material(1, horn)
	_geoms.append(chain.mesh_instance)
	_tail.resize(BONES)

	# --- Head -------------------------------------------------------------------------
	_build_head(head_mat, plate, horn, tooth)

	# --- Legs -------------------------------------------------------------------------
	for spec: Array in [[true, -1.0, 0.25], [true, 1.0, 0.75], [false, -1.0, 0.0], [false, 1.0, 0.5]]:
		legs.append(_build_leg(spec[0], spec[1], spec[2], limb_mat, plate, claw))
		_foot_was_down.append(true)

	# --- Wings ------------------------------------------------------------------------
	for side: float in [-1.0, 1.0]:
		wings.append(_build_wing(side, membrane, limb_mat, claw))


func _build_head(head_mat: Material, plate: Material, horn: Material, tooth: Material) -> void:
	head = Node3D.new()
	head.name = "Head"
	head.top_level = true
	add_child(head)
	var skull_prof := [[0.0, 0.55, 0.62, 0.0], [0.12, 0.88, 0.8, 0.1], [0.27, 0.86, 0.72, 0.16], [0.48, 0.64, 0.52, 0.06],
		[0.72, 0.5, 0.4, -0.02], [0.9, 0.38, 0.31, -0.05], [1.0, 0.14, 0.13, -0.07]]
	var skull := OrganicMesh.profile("dragon_skull", Vector3(0, 0.15, 0.5), Vector3(0, -0.12, -3.5), skull_prof, 20, 18)
	var parts_plate: Array = []
	var parts_horn: Array = []
	for side: float in [-1.0, 1.0]:
		# Brow ridge sweeping back into the horn bases, armoured cheeks.
		parts_plate.append([OrganicMesh.blob("dragon_brow", Vector3(0.32, 0.22, 1.25), 0.25, 3, 12), Transform3D(Basis.from_euler(Vector3(0.12, side * 0.22, side * -0.3)), Vector3(side * 0.52, 0.62, -0.95))])
		parts_plate.append([OrganicMesh.blob("dragon_cheek", Vector3(0.3, 0.42, 1.0), 0.3, 5, 12), Transform3D(Basis.from_euler(Vector3(0, side * 0.12, 0)), Vector3(side * 0.82, -0.1, -0.3))])
		parts_plate.append([OrganicMesh.blob("dragon_snout_plate", Vector3(0.2, 0.12, 0.8), 0.2, 9, 10), Transform3D(Basis.from_euler(Vector3(0.08, side * 0.1, side * -0.25)), Vector3(side * 0.28, 0.36, -2.5))])
		# Main horns: thick, ridged, sweeping back and up.
		var hm := OrganicMesh.bezier("dragon_horn_%d" % int(side), Vector3.ZERO, Vector3(side * 0.45, 0.35, 1.7), Vector3(side * 0.7, 1.35, 3.1), 0.36, 0.03, 12, 10)
		parts_horn.append([hm, Transform3D(Basis(), Vector3(side * 0.55, 0.62, 0.05))])
		var hm2 := OrganicMesh.bezier("dragon_horn2_%d" % int(side), Vector3.ZERO, Vector3(side * 0.55, -0.05, 1.0), Vector3(side * 0.95, 0.35, 2.0), 0.22, 0.02, 9, 8)
		parts_horn.append([hm2, Transform3D(Basis(), Vector3(side * 0.85, 0.12, 0.1))])
		# Jaw frill spikes along the cheek.
		for k in 3:
			var l := 0.75 - k * 0.15
			var fm := OrganicMesh.bezier("dragon_frill_%d" % int(l * 100.0), Vector3.ZERO, Vector3(side * l * 0.6, -l * 0.15, l * 0.4), Vector3(side * l, -l * 0.1, l * 0.9), 0.12, 0.015, 6, 6)
			parts_horn.append([fm, Transform3D(Basis(), Vector3(side * 0.95, -0.35 - k * 0.05, 0.1 - k * 0.55))])
		# Eye: molten iris, slit pupil, deep in the socket under the brow.
		var eye := ModelKit.part(head, ModelKit.sphere(0.17, 12), CreatureSkin.eye(Color(1.0, 0.62, 0.12), 9.0, 0.15), Vector3(side * 0.66, 0.42, -1.18), Vector3.ZERO, Vector3(0.65, 0.8, 1.2))
		eyes.append(eye)
		ModelKit.part(head, ModelKit.sphere(0.07, 6), ModelKit.mat(Color(0.02, 0.01, 0.01), AsciiMaterialId.SOLID, 0.2), Vector3(side * 0.755, 0.42, -1.2), Vector3.ZERO, Vector3(0.35, 1.9, 0.9))
	# Nasal horn and a crest of spikes along the skull.
	parts_horn.append([OrganicMesh.bezier("dragon_nasal", Vector3.ZERO, Vector3(0, 0.3, 0.05), Vector3(0, 0.45, 0.35), 0.13, 0.015, 6, 6), Transform3D(Basis(), Vector3(0, 0.3, -2.9))])
	for i in 4:
		var hs := 0.55 - i * 0.08
		parts_horn.append([OrganicMesh.bezier("dragon_crest_%d" % i, Vector3.ZERO, Vector3(0, hs * 0.6, hs * 0.2), Vector3(0, hs, hs * 0.75), 0.13, 0.015, 6, 5),
			Transform3D(Basis(), Vector3(0, 0.82 - i * 0.03, -0.25 + i * 0.45))])
	ModelKit.part(head, skull, head_mat)
	ModelKit.part(head, OrganicMesh.merge("dragon_head_plates", parts_plate), plate)
	ModelKit.part(head, OrganicMesh.merge("dragon_head_horns", parts_horn), horn)
	var maw := CreatureSkin.mouth(Color(0.3, 0.06, 0.04))
	ModelKit.part(head, OrganicMesh.blob("dragon_maw", Vector3(0.62, 0.2, 1.6), 0.1, 7, 12), maw, Vector3(0, -0.4, -1.75))
	# Nostrils smoulder.
	for side: float in [-1.0, 1.0]:
		ModelKit.part(head, ModelKit.sphere(0.07, 6), ModelKit.glow(Color(1.0, 0.4, 0.1), 3.0, 0.5), Vector3(side * 0.2, 0.2, -3.38), Vector3.ZERO, Vector3(0.8, 0.5, 1.4))
	ModelKit.part(head, _teeth("dragon_teeth_up", 12, -1.0), tooth)
	throat = ModelKit.part(head, ModelKit.sphere(0.3, 10), ModelKit.glow(Color(1.0, 0.5, 0.12), 6.0, 0.4), Vector3(0, -0.3, -1.05), Vector3.ZERO, Vector3(0.9, 0.5, 1.8))
	jaw = ModelKit.joint(head, "Jaw", Vector3(0, -0.42, 0.0))
	var jaw_mesh := OrganicMesh.profile("dragon_jaw", Vector3(0, 0, 0.25), Vector3(0, -0.02, -3.3),
		[[0.0, 0.62, 0.32, 0.0], [0.2, 0.6, 0.3, -0.06], [0.55, 0.46, 0.24, -0.04], [0.85, 0.32, 0.18, 0.0], [1.0, 0.14, 0.1, 0.02]], 16, 14)
	ModelKit.part(jaw, jaw_mesh, head_mat)
	var chin: Array = []
	for side: float in [-1.0, 1.0]:
		chin.append([OrganicMesh.blob("dragon_chin", Vector3(0.24, 0.24, 1.2), 0.25, 11, 10), Transform3D(Basis.from_euler(Vector3(0, side * 0.08, 0)), Vector3(side * 0.42, -0.2, -1.5))])
		for k in 2:
			chin.append([OrganicMesh.bezier("dragon_chin_spike", Vector3.ZERO, Vector3(0, -0.25, 0.1), Vector3(0, -0.35, 0.4), 0.09, 0.012, 5, 5), Transform3D(Basis(), Vector3(side * 0.4, -0.3, -0.5 - k * 0.6))])
	ModelKit.part(jaw, OrganicMesh.merge("dragon_chin", chin), plate)
	ModelKit.part(jaw, OrganicMesh.blob("dragon_tongue", Vector3(0.32, 0.1, 1.3), 0.15, 13, 10), CreatureSkin.mouth(Color(0.42, 0.1, 0.08)), Vector3(0, 0.12, -1.4))
	ModelKit.part(jaw, _teeth("dragon_teeth_low", 10, 1.0), tooth)
	mouth = ModelKit.joint(head, "Mouth", Vector3(0, -0.5, -3.3))
	breath = BreathStream.new().setup(22.0, 7.0, "fire", 1.9)
	breath.name = "Breath"
	mouth.add_child(breath)


## Teeth along a jaw edge, merged into one mesh. dir -1 = hanging (upper), +1 = upward (lower).
func _teeth(key: String, count: int, dir: float) -> ArrayMesh:
	var parts: Array = []
	for side: float in [-1.0, 1.0]:
		for i in count:
			var f := float(i) / (count - 1)
			var z := lerpf(-0.75, -3.25, f)
			var half_w := lerpf(0.66, 0.16, f) if dir < 0.0 else lerpf(0.52, 0.12, f)
			var fang := i == 2 or i == count - 2
			var l := (0.42 if fang else lerpf(0.26, 0.16, f)) * (0.85 if dir > 0.0 else 1.0)
			var tm := OrganicMesh.bezier("dragon_tooth_%d_%d" % [int(dir), int(l * 100.0)], Vector3.ZERO, Vector3(0, dir * l * 0.6, 0.04 * l), Vector3(0, dir * l, 0.3 * l), l * 0.2, l * 0.02, 5, 6)
			var y := (-0.38 if dir < 0.0 else 0.08)
			parts.append([tm, Transform3D(Basis(Vector3.BACK, side * dir * -0.12), Vector3(side * half_w, y, z))])
	var m := OrganicMesh.merge(key, parts)
	return m


func _build_leg(front: bool, side: float, phase: float, skin: Material, plate: Material, claw_mat: Material) -> Dictionary:
	var lens := [1.95, 1.95, 0.85] if front else [2.15, 2.25, 1.35]
	var segs: Array[Node3D] = []
	var key := "dragon_%s" % ("arm" if front else "leg")
	var profs := []
	if front:
		profs = [[[0.0, 0.85, 0.95], [0.25, 0.72, 0.85], [0.7, 0.46, 0.55], [1.0, 0.36, 0.42]],
			[[0.0, 0.4, 0.46], [0.2, 0.42, 0.5], [0.8, 0.3, 0.34], [1.0, 0.27, 0.3]],
			[[0.0, 0.3, 0.3], [1.0, 0.32, 0.25]]]
	else:
		profs = [[[0.0, 0.95, 1.15], [0.3, 0.88, 1.05], [0.75, 0.55, 0.62], [1.0, 0.4, 0.45]],
			[[0.0, 0.42, 0.5], [0.25, 0.46, 0.58], [0.8, 0.28, 0.32], [1.0, 0.24, 0.26]],
			[[0.0, 0.25, 0.27], [0.5, 0.21, 0.22], [1.0, 0.22, 0.2]]]
	for k in 3:
		var n := Node3D.new()
		n.name = "%s%d" % ["Arm" if front else "Leg", k]
		n.top_level = true
		add_child(n)
		var l: float = lens[k]
		ModelKit.part(n, OrganicMesh.profile("%s_%d" % [key, k], Vector3.ZERO, Vector3(0, l, 0), profs[k], 14, 10, Vector3.BACK), skin)
		segs.append(n)
	# Elbow / knee guard plate.
	ModelKit.part(segs[1], OrganicMesh.blob("dragon_knee", Vector3(0.38, 0.5, 0.42), 0.25, 21, 10), plate, Vector3(0, 0.05, 0.15 if front else -0.2))
	var foot := Node3D.new()
	foot.name = "Foot"
	foot.top_level = true
	add_child(foot)
	var toes: Array = []
	var claws: Array = []
	var n_toes := 4 if front else 3
	for t in n_toes:
		var a := lerpf(-0.42, 0.42, float(t) / (n_toes - 1))
		var tl := (0.95 if front else 1.25) * (1.0 - absf(a) * 0.35)
		var dir := Vector3(sin(a), 0, -cos(a))
		var tm := OrganicMesh.bezier("dragon_toe_%d" % int(tl * 100.0), Vector3.ZERO, dir * tl * 0.5 + Vector3(0, 0.12, 0), dir * tl + Vector3(0, -0.02, 0), 0.24, 0.15, 6, 8)
		toes.append([tm, Transform3D(Basis(), Vector3(0, 0.22, 0))])
		var cl := OrganicMesh.bezier("dragon_claw", Vector3.ZERO, Vector3(0, 0.12, -0.3), Vector3(0, -0.25, -0.55), 0.13, 0.01, 6, 6)
		claws.append([cl, Transform3D(Basis(Vector3.UP, -a), dir * tl + Vector3(0, 0.2, 0))])
	if not front:
		var hal := OrganicMesh.bezier("dragon_hallux", Vector3.ZERO, Vector3(0, 0.0, 0.3), Vector3(0, -0.15, 0.55), 0.16, 0.1, 5, 6)
		toes.append([hal, Transform3D(Basis(), Vector3(0, 0.3, 0.1))])
		claws.append([OrganicMesh.bezier("dragon_claw", Vector3.ZERO, Vector3(0, 0.12, -0.3), Vector3(0, -0.25, -0.55), 0.13, 0.01, 6, 6), Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.22, 0.6))])
	toes.append([OrganicMesh.blob("dragon_pad", Vector3(0.5, 0.3, 0.55), 0.15, 5, 10), Transform3D(Basis(), Vector3(0, 0.28, 0.05))])
	ModelKit.part(foot, OrganicMesh.merge("dragon_foot_%s" % ("f" if front else "h"), toes), skin)
	var cm := ModelKit.part(foot, OrganicMesh.merge("dragon_claws_%s" % ("f" if front else "h"), claws), claw_mat)
	cm.visibility_range_end = 120.0
	var joint := SHOULDER if front else HIPS
	var hip_off := Vector3(side * 1.3, -0.95, 0.3) if front else Vector3(side * 1.22, -0.55, 0.35)
	var rest := Vector3(side * 2.0, 0.0, -2.55) if front else Vector3(side * 1.95, 0.0, 3.4)
	return {"front": front, "side": side, "phase": phase, "lens": lens, "segs": segs, "foot": foot, "joint": joint,
		"off": hip_off, "rest": rest, "pos": Vector3.INF, "lift": 0.0}


## One wing: a Skeleton3D (root, humerus, forearm, hand, four fingers, flank)
## with the membrane and the arm skinned to it. Rest pose = fully spread.
func _build_wing(side: float, membrane: Material, arm_mat: Material, claw_mat: Material) -> Dictionary:
	var s := side
	var elbow := Vector3(3.6 * s, 0.35, 0.3)
	var wrist := Vector3(8.2 * s, 0.75, -0.2)
	var digit_dirs := [Vector3(1.0 * s, 0.04, -0.14), Vector3(0.8 * s, -0.02, 0.6), Vector3(0.38 * s, -0.04, 0.93), Vector3(-0.02 * s, -0.06, 1.0)]
	var digit_lens := [6.4, 6.9, 6.3, 5.2]
	var flank_end := Vector3(0.35 * s, -1.75, 6.2)
	var sk := Skeleton3D.new()
	sk.name = "Wing%s" % ("L" if s < 0.0 else "R")
	var holder := Node3D.new()
	chain.attach(SHOULDER, holder)
	var mount := ModelKit.joint(holder, "WingMount", Vector3(s * 0.95, 1.35, -0.35))
	mount.add_child(sk)
	var names := ["root", "humerus", "forearm", "hand", "d2", "d3", "d4", "d5", "flank"]
	var parents := [-1, 0, 1, 2, 3, 3, 3, 3, 0]
	var rests := [Vector3.ZERO, Vector3.ZERO, elbow, wrist - elbow, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	for i in names.size():
		sk.add_bone(names[i])
	for i in names.size():
		if parents[i] >= 0:
			sk.set_bone_parent(i, parents[i])
		sk.set_bone_rest(i, Transform3D(Basis(), rests[i]))
	sk.reset_bone_poses()

	# --- Fold pose: elbow up and back, wrist forward by the neck, fingers along the flank.
	var elbow_f := Vector3(0.75 * s, 2.7, 1.7)
	var fore_f := Vector3(0.2 * s, -0.5, -0.85).normalized()
	var digit_f := [Vector3(0.14 * s, -0.28, 1.0), Vector3(0.17 * s, -0.36, 1.0), Vector3(0.2 * s, -0.45, 0.95), Vector3(0.22 * s, -0.55, 0.9)]
	var q_hum := Quaternion(elbow.normalized(), elbow_f.normalized())
	var q_fore := Quaternion((wrist - elbow).normalized(), q_hum.inverse() * fore_f)
	var q_digits: Array[Quaternion] = []
	for d in 4:
		q_digits.append(Quaternion((digit_dirs[d] as Vector3).normalized(), (q_hum * q_fore).inverse() * (digit_f[d] as Vector3).normalized()))

	# --- Membrane (skinned between the finger bones and the flank).
	var mesh := _wing_membrane(s, wrist, elbow, digit_dirs, digit_lens, flank_end)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = membrane
	mi.custom_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
	sk.add_child(mi)
	mi.skeleton = NodePath("..")
	# --- Arm and finger bones.
	var bone_parts: Array = []
	bone_parts.append([OrganicMesh.profile("dragon_humerus_%d" % int(s), Vector3.ZERO, elbow, [[0.0, 0.62, 0.7], [0.3, 0.55, 0.6], [0.8, 0.34, 0.38], [1.0, 0.3, 0.32]], 12, 8), Transform3D(), 1])
	bone_parts.append([OrganicMesh.profile("dragon_forearm_%d" % int(s), elbow, wrist, [[0.0, 0.3, 0.32], [0.2, 0.33, 0.34], [0.85, 0.2, 0.22], [1.0, 0.24, 0.24]], 10, 8), Transform3D(), 2])
	bone_parts.append([OrganicMesh.blob("dragon_wrist", Vector3(0.36, 0.3, 0.42), 0.15, 4, 10), Transform3D(Basis(), wrist), 3])
	for d in 4:
		var dir: Vector3 = (digit_dirs[d] as Vector3).normalized()
		var tip: Vector3 = wrist + dir * float(digit_lens[d])
		var mid := wrist.lerp(tip, 0.5) + Vector3(0, 0.1, 0)
		bone_parts.append([OrganicMesh.bezier("dragon_digit_%d_%d" % [d, int(s)], wrist, mid, tip, 0.17, 0.04, 8, 6), Transform3D(), 4 + d])
	var arm_mesh := OrganicMesh.skinned_mesh("dragon_wingarm_%d" % int(s), [OrganicMesh.skinned_parts(bone_parts)])
	var ai := MeshInstance3D.new()
	ai.mesh = arm_mesh
	ai.material_override = arm_mat
	ai.custom_aabb = mi.custom_aabb
	sk.add_child(ai)
	ai.skeleton = NodePath("..")
	var thumb := OrganicMesh.bezier("dragon_thumb_%d" % int(s), Vector3.ZERO, Vector3(0.15 * s, 0.35, -0.35), Vector3(0.05 * s, 0.1, -0.85), 0.16, 0.012, 7, 6)
	var claw_mesh := OrganicMesh.skinned_mesh("dragon_thumbclaw_%d" % int(s), [OrganicMesh.skinned_parts([[thumb, Transform3D(Basis(), wrist + Vector3(0, 0.2, -0.2)), 3]])])
	var ci := MeshInstance3D.new()
	ci.mesh = claw_mesh
	ci.material_override = claw_mat
	ci.custom_aabb = mi.custom_aabb
	sk.add_child(ci)
	ci.skeleton = NodePath("..")
	return {"side": s, "skel": sk, "q_hum": q_hum, "q_fore": q_fore, "q_digits": q_digits, "mount": mount}


## Wing membrane in the rest (spread) pose, skinned to the wing bones:
## three fans between the fingers and the big panel from the arm and fifth
## finger to the flank, scalloped trailing edges, both faces.
func _wing_membrane(s: float, wrist: Vector3, elbow: Vector3, dirs: Array, lens: Array, flank_end: Vector3) -> ArrayMesh:
	var key := "dragon_membrane_%d" % int(s)
	if OrganicMesh.has(key):
		return OrganicMesh.skinned_mesh(key, [])
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var grids: Array = []   # [start index, rows, cols]
	var nr := 8
	var nf := 6
	for panel in 3:
		var da: Vector3 = (dirs[panel] as Vector3).normalized() * float(lens[panel])
		var db: Vector3 = (dirs[panel + 1] as Vector3).normalized() * float(lens[panel + 1])
		var start := verts.size()
		for ri in nr:
			var r := float(ri + 1) / nr
			for fi in nf:
				var f := float(fi) / (nf - 1)
				var edge := da.lerp(db, f)
				var scallop := 1.0 - 0.3 * sin(PI * f) * pow(r, 3.0)
				var droop := Vector3(0, -0.35 * sin(PI * f) * r, 0)
				var p := wrist + edge * r * scallop + droop
				verts.append(p)
				uvs.append(Vector2(p.x, p.z))
				bones.append_array([4 + panel, 5 + panel, 0, 0])
				weights.append_array([1.0 - f, f, 0.0, 0.0])
		grids.append([start, nr, nf, true])
	# Panel from the arm + fifth finger to the flank.
	var tip5: Vector3 = wrist + (dirs[3] as Vector3).normalized() * float(lens[3])
	var a_pts := [Vector3.ZERO, elbow, wrist, tip5]
	var a_len := [0.0]
	for i in range(1, 4):
		a_len.append(float(a_len[i - 1]) + (a_pts[i] as Vector3).distance_to(a_pts[i - 1]))
	var total: float = a_len[3]
	var nt := 12
	var nu := 7
	var start_d := verts.size()
	var edge_out := ((tip5 + flank_end) * 0.5 - wrist * 0.4)
	edge_out.y = 0.0
	edge_out = edge_out.normalized()
	for ti in nt:
		var t := float(ti + 1) / nt
		var at := t * total
		var seg := 0
		while seg < 2 and at > float(a_len[seg + 1]):
			seg += 1
		var lf := (at - float(a_len[seg])) / maxf(0.001, float(a_len[seg + 1]) - float(a_len[seg]))
		var pa := (a_pts[seg] as Vector3).lerp(a_pts[seg + 1], lf)
		var pb := flank_end * t
		# Bone along the outer curve: humerus, forearm, fifth finger (blended near the joints).
		var b_a := [1, 2, 7][seg] as int
		var b_next := [2, 7, 7][seg] as int
		var blend := smoothstep(0.75, 1.0, lf) * 0.5 if seg < 2 else 0.0
		for ui in nu:
			var u := float(ui) / (nu - 1)
			var p := pa.lerp(pb, u)
			p -= edge_out * 0.9 * sin(PI * u) * pow(t, 4.0)
			p.y -= 0.45 * sin(PI * u) * t
			verts.append(p)
			uvs.append(Vector2(p.x, p.z))
			var wa := (1.0 - u) * (1.0 - blend)
			var wn := (1.0 - u) * blend
			bones.append_array([b_a, b_next, 8, 0])
			weights.append_array([wa, wn, u, 0.0])
	grids.append([start_d, nt, nu, false])
	# Normals: the membrane is nearly flat; approximate per grid from neighbours.
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for g: Array in grids:
		var st: int = g[0]
		var rows: int = g[1]
		var cols: int = g[2]
		for r in rows:
			for c in cols:
				var i := st + r * cols + c
				var du := verts[st + r * cols + mini(c + 1, cols - 1)] - verts[st + r * cols + maxi(c - 1, 0)]
				var dv := verts[st + mini(r + 1, rows - 1) * cols + c] - verts[st + maxi(r - 1, 0) * cols + c]
				var nn := du.cross(dv)
				if nn.length_squared() < 1e-8:
					nn = Vector3.UP
				nn = nn.normalized()
				if nn.y < 0.0:
					nn = -nn
				normals[i] = nn
	# Faces (fans start at the wrist / shoulder point).
	var idx := PackedInt32Array()
	var hub_w := verts.size()
	verts.append(wrist)
	uvs.append(Vector2(wrist.x, wrist.z))
	normals.append(Vector3.UP)
	bones.append_array([3, 0, 0, 0])
	weights.append_array([1.0, 0.0, 0.0, 0.0])
	var hub_s := verts.size()
	verts.append(Vector3.ZERO)
	uvs.append(Vector2.ZERO)
	normals.append(Vector3.UP)
	bones.append_array([0, 0, 0, 0])
	weights.append_array([1.0, 0.0, 0.0, 0.0])
	var top := PackedInt32Array()
	for g: Array in grids:
		var st: int = g[0]
		var rows: int = g[1]
		var cols: int = g[2]
		var hub := hub_w if g[3] else hub_s
		for c in cols - 1:
			top.append_array([hub, st + c, st + c + 1])
		for r in rows - 1:
			for c in cols - 1:
				var a := st + r * cols + c
				var b := a + 1
				var d := a + cols
				var e := d + 1
				top.append_array([a, d, b, b, d, e])
	# Front face (normals up) and back face (offset down, flipped).
	var n_front := verts.size()
	var thick := 0.05
	for i in n_front:
		verts.append(verts[i] - normals[i] * thick)
		uvs.append(uvs[i])
		normals.append(-normals[i])
		bones.append_array([bones[i * 4], bones[i * 4 + 1], bones[i * 4 + 2], bones[i * 4 + 3]])
		weights.append_array([weights[i * 4], weights[i * 4 + 1], weights[i * 4 + 2], weights[i * 4 + 3]])
	for i in range(0, top.size(), 3):
		OrganicMesh._tri_out(idx, verts, normals, top[i], top[i + 1], top[i + 2])
		OrganicMesh._tri_out(idx, verts, normals, top[i] + n_front, top[i + 1] + n_front, top[i + 2] + n_front)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = idx
	return OrganicMesh.skinned_mesh(key, [arrays])


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
	if not is_nan(ground_y):
		return ground_y
	return _last_ground


func _animate(delta: float) -> void:
	if chain == null:
		return
	var root := global_transform
	var basis := root.basis.orthonormalized()
	var fwd := -basis.z
	var up := basis.y
	var right := basis.x
	if not _prev_root.is_finite():
		_prev_root = root.origin
	_vel = _vel.lerp((root.origin - _prev_root) / maxf(delta, 0.001), 1.0 - exp(-5.0 * delta))
	_prev_root = root.origin
	var yaw_now := atan2(-fwd.x, -fwd.z)
	if not is_nan(_prev_yaw):
		_yaw_rate = lerpf(_yaw_rate, angle_difference(_prev_yaw, yaw_now) / maxf(delta, 0.001), 1.0 - exp(-6.0 * delta))
	_prev_yaw = yaw_now
	var air := flying and not _dead
	if not air and _fly < 0.3:
		_last_ground = root.origin.y
	var p := action_progress()
	var w := action_weight(0.1, 0.2)
	var act := _action if p >= 0.0 else ""
	var speed := Vector2(_vel.x, _vel.z).length() if not air else 0.0
	_walk = damp(_walk, clampf(maxf(speed, move_speed if not air else 0.0) / 4.0, 0.0, 1.0), 4.0, delta)
	_fly = damp(_fly, 1.0 if air else 0.0, 2.5, delta)
	var step_rate := maxf(speed, move_speed) / 3.4 + absf(maxf(absf(turn_rate), absf(_yaw_rate))) * 0.35
	_gait += delta * clampf(step_rate, 0.0, 1.6) * (1.0 - _fly)
	var breathe := sin(_time * 1.1)

	# --- Targets for this frame ------------------------------------------------------
	var t_rear := 0.0
	var t_pitch := 0.0
	var t_roll := 0.0
	var t_crouch := 0.0
	var t_lunge := 0.0
	var t_hip_yaw := 0.0
	var t_fold := 1.0 - _fly
	var t_raise := 0.0
	var t_flap := _fly
	var t_jaw := 0.06 + maxf(0.0, sin(_time * 0.7)) * 0.05
	var t_throat := 0.25 + 0.1 * sin(_time * 2.0)
	var t_inner := 0.12 + 0.06 * sin(_time * 0.9)
	var t_sweep := 0.0
	# Head target in model space and a pitch offset; the head looks at look_target.
	var head_l := CHEST + Vector3(0, 3.35, -4.05)
	var t_head_pitch := -0.12
	var aim_ground := Vector3.INF
	var claw_lift := 0.0
	var claw_reach := 0.0
	var breath_on := false
	var flap_speed := 0.95

	var strafing := air and (strafe or act == "breath")
	if air:
		# Cruising: nose down with speed, nose up when climbing or hovering;
		# banks into turns; glides between bursts of wingbeats at speed.
		var air_speed := Vector2(_vel.x, _vel.z).length()
		var cruise := clampf(air_speed / 12.0, 0.0, 1.0)
		t_pitch = (lerpf(0.3, 0.04, cruise) - clampf(_vel.y * 0.03, -0.25, 0.25)) if not strafing else 0.02
		_bank = damp(_bank, clampf(-_yaw_rate * 0.55, -0.6, 0.6) * cruise, 3.0, delta)
		t_roll = _bank
		t_fold = 0.0
		head_l = CHEST + Vector3(0, 2.2, -4.9)
		t_head_pitch = -0.35
		flap_speed = 1.05 if not strafing else 0.75
		if not strafing and cruise > 0.6 and _vel.y > -2.0:
			var glide := smoothstep(0.1, 0.7, sin(_time * 0.55))
			t_flap = lerpf(1.0, 0.18, glide)
			t_raise = 0.12 * glide
		if strafing:
			breath_on = act != "breath" or (p > 0.04 and p < 0.96)
			head_l = CHEST + Vector3(0, 0.4, -5.6)
			t_head_pitch = -0.75
			t_jaw = 0.85
			t_throat = 2.2
			t_inner = 2.0

	match act:
		"bite":
			var wind := keys(p, [[0, 0], [0.3, 1.0], [0.45, 0.6], [0.55, 0.0], [1, 0]])
			var strike := keys(p, [[0, 0], [0.38, 0.0], [0.55, 1.0], [0.68, 1.0], [1, 0]])
			head_l += Vector3(0, 1.3, 1.6) * wind
			head_l = head_l.lerp(Vector3(0, 1.7, -10.2), strike)
			t_head_pitch = lerpf(t_head_pitch, -0.45, strike) + wind * 0.25
			t_jaw = keys(p, [[0, 0.1], [0.3, 0.75], [0.48, 1.0], [0.56, 0.0], [0.8, 0.05], [1, 0.08]])
			t_lunge = strike * 1.3
			t_crouch = strike * 0.55
			t_pitch -= strike * 0.06
			t_throat = 0.5
			if p > IMPACT["bite"] and not _impact_done:
				_impact_done = true
				_fx("dust_cloud", Vector3(0, 0, -10.0), 0.9)
		"claw":
			claw_lift = keys(p, [[0, 0], [0.32, 1.0], [0.44, 1.0], [0.52, 0.0], [1, 0]])
			claw_reach = keys(p, [[0, 0], [0.32, 0.5], [0.52, 1.0], [0.75, 1.0], [1, 0]])
			t_roll = -_claw_side * 0.1 * claw_lift - _claw_side * 0.06 * claw_reach
			t_rear = 0.12 * claw_lift
			t_lunge = 0.6 * claw_reach
			head_l += Vector3(_claw_side * 1.0, -0.8, -0.5) * claw_reach
			t_jaw = 0.45 * w
			if p > IMPACT["claw"] and not _impact_done:
				_impact_done = true
				_fx("dust_cloud", Vector3(_claw_side * 2.3, 0, -6.4), 0.9)
				_quake(root * Vector3(_claw_side * 2.3, 0, -6.4), 0.25)
		"tail":
			t_sweep = keys(p, [[0, 0], [0.32, 1.0], [0.42, 0.85], [0.62, -1.15], [0.8, -0.9], [1, 0]])
			t_hip_yaw = keys(p, [[0, 0], [0.32, -0.22], [0.62, 0.28], [1, 0]])
			head_l += Vector3(-2.0, -0.6, 2.2) * keys(p, [[0, 0], [0.3, 1.0], [0.62, -0.4], [1, 0]])
			t_crouch = 0.3 * w
			t_jaw = 0.35 * w
			if p > IMPACT["tail"] and not _impact_done:
				_impact_done = true
				for i in 3:
					_fx("dust_cloud", Vector3(-3.0 + i * 3.0, 0, 9.0 + absf(i - 1) * -2.0), 0.9)
		"gust":
			t_rear = keys(p, [[0, 0], [0.32, 0.42], [0.5, 0.3], [0.7, 0.2], [1, 0]])
			t_fold = 1.0 - keys(p, [[0, 0], [0.22, 1.0], [0.75, 1.0], [1, 0]])
			t_raise = keys(p, [[0, 0], [0.3, 1.0], [0.42, 0.8], [0.52, -0.55], [0.7, -0.3], [1, 0]])
			t_flap = 0.0
			head_l += Vector3(0, 1.4, 0.6) * w
			t_head_pitch += 0.2 * w
			t_jaw = 0.8 * w
			if p > IMPACT["gust"] and not _impact_done:
				_impact_done = true
				for i in 5:
					var a := (float(i) - 2.0) * 0.35
					_fx("dust_cloud", Vector3(0, 0, -7.0).rotated(Vector3.UP, a), 1.2)
		"roar", "summon", "howl":
			t_rear = 0.22 * w
			head_l += Vector3(0, 1.5, -0.6) * w
			t_head_pitch = lerpf(t_head_pitch, 0.35, w)
			t_jaw = lerpf(t_jaw, 1.05 + sin(_time * 40.0) * 0.04, w)
			t_fold = lerpf(t_fold, 0.45, w)
			t_raise = 0.45 * w
			t_flap = 0.0
			t_throat = 2.0
			t_inner = 0.6
			if p > 0.25 and not _impact_done:
				_impact_done = true
				_fx("dust_cloud", Vector3(0, 0, -4.0), 1.2)
		"attack":
			# Spitting a fireball from the air (or a snap on the ground).
			var spit := keys(p, [[0, 0], [0.35, -0.6], [0.55, 1.0], [1, 0]])
			head_l += Vector3(0, 0.6, 1.2) * minf(0.0, spit) * -1.0 + Vector3(0, -0.5, -1.4) * maxf(0.0, spit)
			t_jaw = maxf(t_jaw, 0.9 * w)
			t_throat = 2.5 * w + 0.4
		"breath" when not air:
			var wind := keys(p, [[0, 0], [0.22, 1.0], [BREATH_ON, 0.0], [1, 0]])
			var fire := keys(p, [[0, 0], [BREATH_ON - 0.04, 0.0], [BREATH_ON + 0.02, 1.0], [BREATH_OFF, 1.0], [1, 0]])
			head_l += Vector3(0, 1.4, 1.9) * wind
			t_head_pitch += 0.35 * wind
			t_jaw = lerpf(0.35 * wind, 0.82, fire)
			t_inner = 0.2 + 2.6 * keys(p, [[0, 0], [0.25, 1.0], [BREATH_OFF, 0.9], [1, 0]])
			t_throat = 0.5 + 3.0 * maxf(wind, fire)
			t_rear = 0.12 * wind
			t_crouch = 0.3 * fire
			breath_on = p > BREATH_ON and p < BREATH_OFF
			var yaw := breath_yaw(p)
			t_hip_yaw = -yaw * 0.25 * fire
			aim_ground = Vector3(0, 0, -15.0).rotated(Vector3.UP, yaw)
			var hp := Vector3(0, 6.3, -6.2).rotated(Vector3.UP, yaw * 0.85)
			head_l = head_l.lerp(hp, fire)
		"takeoff":
			t_crouch = keys(p, [[0, 0], [0.28, 1.1], [0.42, -0.4], [0.6, 0.0], [1, 0]])
			t_fold = 1.0 - keys(p, [[0, 0], [0.2, 1.0], [1, 1.0]])
			t_raise = keys(p, [[0, 0], [0.28, 1.05], [0.38, 1.0], [0.52, -0.7], [0.75, 0.6], [0.9, -0.5], [1, 0]])
			t_flap = 0.0
			t_pitch = keys(p, [[0, 0], [0.28, 0.12], [0.5, 0.3], [1, 0.2]])
			head_l += Vector3(0, 1.0, -0.5) * w
			if p > 0.42 and not _impact_done:
				_impact_done = true
				_fx("dust_cloud", Vector3(0, 0, 0), 1.6)
				_fx("dust_cloud", Vector3(-7, 0, 0), 1.3)
				_fx("dust_cloud", Vector3(7, 0, 0), 1.3)
				_quake(root.origin, 0.3)
		"land", "slam":
			var heavy := act == "slam"
			var hit_at: float = IMPACT[act]
			t_fold = keys(p, [[0, 0.0], [hit_at, 0.05], [hit_at + 0.2, 0.35 if not heavy else 0.2], [1, 1.0]])
			t_raise = keys(p, [[0, 0.7], [hit_at, 0.4], [hit_at + 0.12, -0.5 if heavy else -0.2], [1, 0]])
			t_flap = 0.0
			t_pitch = keys(p, [[0, 0.3 if not heavy else -0.25], [hit_at, 0.1 if not heavy else -0.12], [hit_at + 0.15, -0.05], [1, 0]])
			t_crouch = keys(p, [[0, 0], [hit_at, 0.2], [hit_at + 0.12, 1.3 if heavy else 0.9], [1, 0]])
			t_jaw = (0.9 if heavy else 0.4) * keys(p, [[0, 0.3], [hit_at + 0.1, 1.0], [1, 0]])
			if heavy:
				head_l += Vector3(0, -1.6, -0.8) * keys(p, [[0, 0], [hit_at + 0.1, 1.0], [0.8, 0.5], [1, 0]])
			if p > hit_at and not _impact_done:
				_impact_done = true
				_fx("dust_cloud", Vector3.ZERO, 1.8 if heavy else 1.3)
				for i in 6:
					var a := TAU * float(i) / 6.0
					_fx("dust_cloud", Vector3(cos(a), 0, sin(a)) * (7.0 if heavy else 5.0), 1.0)
				if heavy:
					_fx("embers", Vector3(0, 0.5, -3.0), 3.0)
				_quake(root.origin, 0.6 if heavy else 0.35)
				Audio.play("land_heavy", root.origin, 6.0, 0.45)
		"dive":
			t_pitch = -0.55
			t_fold = 0.55
			t_raise = 0.25
			t_flap = 0.0
			t_jaw = 0.9
			head_l = CHEST + Vector3(0, 0.6, -5.8)
			t_head_pitch = -0.6
			t_throat = 1.6
		"charge":
			# Head down, shoulders driving: wind-up, then the run.
			var wind := keys(p, [[0, 0], [0.3, 1.0], [0.42, 0.6], [1, 0.4]])
			var run := keys(p, [[0, 0], [0.38, 0.0], [0.45, 1.0], [0.75, 1.0], [1, 0]])
			t_crouch = 0.5 * wind + 0.25 * run
			t_lunge = 1.2 * run
			t_pitch = -0.1 * run + 0.06 * wind
			head_l = head_l.lerp(Vector3(0, 3.1, -9.6), maxf(wind * 0.6, run))
			t_head_pitch = lerpf(t_head_pitch, -0.6, run)
			t_jaw = 0.4 + 0.5 * run
			t_fold = lerpf(t_fold, 0.55, run)
			t_raise = 0.25 * run
			t_throat = 0.6 + run
			_gait += delta * 1.8 * run
			if p > 0.45 and not _impact_done:
				_impact_done = true
				_fx("dust_cloud", Vector3(0, 0, 2.0), 1.4)
		"stomp":
			var hit_at: float = IMPACT["stomp"]
			var rise := keys(p, [[0, 0], [hit_at - 0.12, 1.0], [hit_at, 0.0], [1, 0]])
			var down := keys(p, [[0, 0], [hit_at - 0.04, 0.0], [hit_at + 0.04, 1.0], [0.85, 0.6], [1, 0]])
			t_rear = 0.6 * rise
			t_crouch = 1.0 * down
			t_fold = 1.0 - 0.8 * rise
			t_raise = 0.9 * rise - 0.4 * down
			t_flap = 0.0
			claw_lift = rise
			claw_reach = 0.4 * rise + 0.6 * down
			head_l += Vector3(0, 2.0, 1.2) * rise + Vector3(0, -1.4, -1.2) * down
			t_head_pitch += 0.4 * rise - 0.3 * down
			t_jaw = 0.4 + 0.6 * maxf(rise, down)
			if p > hit_at and not _impact_done:
				_impact_done = true
				_fx("dust_cloud", Vector3(0, 0, -5.0), 1.8)
				for i in 6:
					var a := TAU * float(i) / 6.0
					_fx("dust_cloud", Vector3(cos(a), 0, sin(a)) * 7.0 + Vector3(0, 0, -5.0), 1.0)
				_quake(root * Vector3(0, 0, -5.0), 0.7)
				Audio.play("land_heavy", root.origin, 6.0, 0.5)
		"swoop", "rake":
			# Low pass: talons thrown forward, wings swept back.
			var talon := keys(p, [[0, 0], [0.3, 1.0], [0.7, 1.0], [1, 0]])
			t_pitch = lerpf(t_pitch, -0.25, talon)
			t_fold = 0.35 * talon
			t_flap = lerpf(t_flap, 0.1, talon)
			t_raise = 0.35 * talon
			claw_lift = talon
			claw_reach = talon
			head_l = head_l.lerp(CHEST + Vector3(0, 1.0, -5.8), talon)
			t_head_pitch = lerpf(t_head_pitch, -0.5, talon)
			t_jaw = 0.85 * talon
			t_throat = 1.2
		"hover":
			# Upright hover, deep slow beats (fireball volleys).
			t_pitch = lerpf(t_pitch, 0.55, w)
			flap_speed = 0.8
			t_flap = 1.0
			head_l += Vector3(0, 0.8, -0.4) * w
			t_head_pitch = lerpf(t_head_pitch, -0.55, w)
			t_throat = 1.4 * w + 0.3
			t_inner = 0.6 * w
		"phase":
			# Rears up and spreads its wings with a roar; its fire wells up.
			t_rear = 0.45 * w if not air else 0.0
			t_pitch = (0.4 * w) if air else t_pitch
			head_l += Vector3(0, 2.0, -0.4) * w
			t_head_pitch = lerpf(t_head_pitch, 0.55, w)
			t_jaw = lerpf(t_jaw, 1.1 + sin(_time * 40.0) * 0.05, w)
			t_fold = lerpf(t_fold, 0.0, w)
			t_raise = 1.0 * w
			t_flap = t_flap * (1.0 - w) + (0.6 * w if air else 0.0)
			t_throat = 3.0 * w
			t_inner = 2.4 * w
			if p > 0.2 and not _impact_done:
				_impact_done = true
				_fx("embers", Vector3(0, 1.0, -3.0), 3.0)
				_fx("dust_cloud", Vector3(0, 0, 0), 1.6)
				_quake(root.origin, 0.4)
		"hit":
			var s := sin(PI * p)
			head_l += Vector3(0.8, 0.6, 1.4) * s
			t_head_pitch += 0.3 * s
			t_roll = 0.08 * s
			t_jaw = maxf(t_jaw, 0.6 * s)

	if _dead:
		var f := clampf(_dead_t / 2.2, 0.0, 1.0)
		t_crouch = 2.8 * f
		t_roll = _death_side * 0.5 * f
		t_pitch = 0.0
		t_rear = 0.0
		t_fold = lerpf(1.0, 0.45, f)
		t_raise = -0.35 * f
		t_flap = 0.0
		t_jaw = 0.5
		t_throat = 0.0
		t_inner = 0.0
		head_l = Vector3(_death_side * 3.5, 1.1, -7.0).lerp(head_l, 1.0 - f)
		t_head_pitch = -0.1
		breath_on = false
		if not air:
			_fly = damp(_fly, 0.0, 3.0, delta)

	# --- Smooth the pose -------------------------------------------------------------
	var rate := 7.0
	_rear = damp(_rear, t_rear, rate, delta)
	_pitch = damp(_pitch, t_pitch, 3.0, delta)
	_roll = damp(_roll, t_roll, 4.0, delta)
	_crouch = damp(_crouch, t_crouch, 9.0 if act in ["land", "slam", "takeoff"] else 5.0, delta)
	_lunge = damp(_lunge, t_lunge, 10.0, delta)
	_hip_yaw = damp(_hip_yaw, t_hip_yaw, 6.0, delta)
	_fold = damp(_fold, t_fold, 4.5 if act != "gust" else 9.0, delta)
	_raise = damp(_raise, t_raise, 9.0, delta)
	_flap_amp = damp(_flap_amp, t_flap, 3.0, delta)
	_tail_sweep = damp(_tail_sweep, t_sweep, 9.0, delta)
	_jaw = damp(_jaw, t_jaw, 16.0, delta)
	_throat = damp(_throat, t_throat, 5.0, delta)
	_inner = damp(_inner, t_inner, 3.0, delta)
	_head_pitch = damp(_head_pitch, t_head_pitch, 6.0, delta)
	_flap += delta * TAU * flap_speed * maxf(_flap_amp, 0.0)

	# --- Torso ------------------------------------------------------------------------
	var bob := breathe * 0.05 - absf(sin(_gait * TAU)) * 0.1 * _walk
	var flap_s := sin(_flap)
	var hover_bob := (flap_s * 0.45) * _flap_amp
	var pivot := Vector3(0, 4.3, 0.4)
	var body_rot := Basis(Vector3.RIGHT, _pitch) * Basis(Vector3.BACK, _roll)
	var chest := pivot + body_rot * (CHEST - pivot)
	var pelvis := pivot + body_rot * (HIP_POS - pivot)
	chest = pelvis + Basis(Vector3.RIGHT, _rear) * (chest - pelvis)
	var down := Vector3(0, -_crouch * 0.55 + bob + hover_bob, 0)
	chest += down + Vector3(0, 0, -_lunge)
	pelvis += down * 0.8 + Vector3(0, 0, -_lunge * 0.6)
	pelvis = chest + Basis(Vector3.UP, _hip_yaw) * (pelvis - chest)
	var chest_w := root * chest
	var pelvis_w := root * pelvis
	var body_up := (basis * (body_rot * Vector3.UP)).normalized()
	var body_fwd := (chest_w - pelvis_w).normalized()
	for j in range(NECK, PELVIS + 1):
		var f := float(j - NECK) / (PELVIS - NECK)
		chain.display[j] = chest_w.lerp(pelvis_w, f) + body_up * 0.28 * sin(PI * f)

	# --- Head and neck ----------------------------------------------------------------
	if aim_ground.is_finite() or look_target.is_finite():
		pass
	var head_w := root * (head_l + Vector3(0, down.y, -_lunge))
	# Turn the neck towards what it is looking at.
	var look_dir := fwd
	if look_target.is_finite() and not _dead and act not in ["bite", "tail", "breath", "claw"]:
		var to := look_target - head_w
		var flat := Vector3(to.x, 0, to.z)
		if flat.length() > 2.0:
			var yaw := clampf(fwd.signed_angle_to(flat.normalized(), Vector3.UP), -1.15, 1.15)
			head_w = chest_w + (head_w - chest_w).rotated(Vector3.UP, yaw * 0.55)
			look_dir = fwd.rotated(Vector3.UP, yaw)
			var pitch_to := atan2(to.y, flat.length())
			_head_pitch = damp(_head_pitch, clampf(pitch_to, -0.75, 0.35) + t_head_pitch * 0.4 + 0.12, 3.0, delta)
	if aim_ground.is_finite():
		var aim_w := root * aim_ground
		aim_w.y = _ground()
		var to := aim_w - head_w
		look_dir = Vector3(to.x, 0, to.z).normalized()
		_head_pitch = damp(_head_pitch, atan2(to.y, Vector2(to.x, to.z).length()) + 0.18, 10.0, delta)
	elif strafe and air:
		look_dir = fwd
	var reach := LENGTH / (BONES - 1) * NECK * 1.12
	var from_chest := head_w - chest_w
	if from_chest.length() > reach:
		head_w = chest_w + from_chest.normalized() * reach
	if not _head_pos.is_finite():
		_head_pos = head_w
	var head_rate := 14.0 if act in ["bite", "claw"] else 6.0
	_head_pos = _head_pos.lerp(head_w, 1.0 - exp(-head_rate * delta))
	_look = turn_dir(_look, look_dir, 1.0 - exp(-5.0 * delta))
	var hb := Basis.looking_at(_look, Vector3.UP) * Basis(Vector3.RIGHT, _head_pitch)
	if _dead:
		hb = hb * Basis(Vector3.BACK, _death_side * 0.9 * clampf(_dead_t / 2.0, 0.0, 1.0))
	head.global_transform = Transform3D(hb, _head_pos)
	jaw.rotation.x = _jaw * 0.62
	# Neck: a cubic curve from the skull (joint 0) to the withers (joint NECK), even spacing.
	var p0 := _head_pos + hb.z * 0.35
	var p1 := p0 + hb.z * 2.1
	var p3 := chest_w
	var p2 := p3 + body_fwd * 1.6 + body_up * 1.9
	_neck_curve(p0, p1, p2, p3)

	# --- Tail ------------------------------------------------------------------------
	_tail_sim(delta, pelvis_w, body_fwd, body_up, basis, air)
	chain.apply()

	# --- Glow --------------------------------------------------------------------------
	chain.mesh_instance.set_instance_shader_parameter(&"inner_glow", _inner)
	throat.set_instance_shader_parameter(&"intensity", _throat * (0.6 + _jaw))
	for e in eyes:
		e.set_instance_shader_parameter(&"intensity", 0.0 if _dead else (1.0 + 0.6 * clampf(_throat - 1.0, 0.0, 1.0)))

	# --- Breath ----------------------------------------------------------------------
	if breath_on != breath.on:
		breath.set_on(breath_on)
		if breath_on:
			Audio.play("furnace_roar", _head_pos, 8.0, 0.7)
	if breath.on:
		breath.set_ground(_ground())
		_fx_t -= delta
		if _fx_t <= 0.0:
			_fx_t = 0.16
			var hit := breath.ground_hit(_ground())
			if hit.is_finite():
				CreatureFx.play(_fx_parent(), "embers", hit + Vector3(0, 0.3, 0), 2.2)
				CreatureFx.play(_fx_parent(), "ash_cloud", hit, 0.7)

	# --- Legs, wings ------------------------------------------------------------------
	_pose_legs(delta, root, basis, chest_w, pelvis_w, body_rot, claw_lift, claw_reach, air)
	_pose_wings(delta, flap_s)


func _neck_curve(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> void:
	var samples := 18
	var pts := PackedVector3Array()
	var acc := PackedFloat32Array()
	var total := 0.0
	for i in samples + 1:
		var t := float(i) / samples
		var u := 1.0 - t
		var q := p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t)
		if i > 0:
			total += q.distance_to(pts[i - 1])
		pts.append(q)
		acc.append(total)
	var k := 0
	for j in NECK:
		var target := total * float(j) / NECK
		while k < samples - 1 and acc[k + 1] < target:
			k += 1
		var f := (target - acc[k]) / maxf(0.0001, acc[k + 1] - acc[k])
		chain.display[j] = pts[k].lerp(pts[k + 1], clampf(f, 0.0, 1.0))


## Follow-the-leader tail: each joint keeps its distance from the one in front,
## eases towards a drooping rest direction (plus a lazy sway, or the sweep),
## and stays above the ground.
func _tail_sim(delta: float, pelvis_w: Vector3, body_fwd: Vector3, body_up: Vector3, basis: Basis, air: bool) -> void:
	var n := BONES
	var back := -body_fwd
	var ground := _ground()
	if not _tail_ready:
		_tail_ready = true
		for i in range(PELVIS, n):
			_tail[i] = pelvis_w + back * _seg * (i - PELVIS)
	_tail[PELVIS] = pelvis_w
	var prev := back
	var sway_amp := 0.1 + 0.08 * _walk
	var k := 1.0 - exp(-7.0 * delta)
	for i in range(PELVIS + 1, n):
		var f := float(i - PELVIS) / (n - 1 - PELVIS)
		var yaw := sin(_time * 0.9 - f * 3.0) * sway_amp * (0.3 + f) + _tail_sweep * (0.12 + 0.11 * f * 10.0 / 10.0) * (1.0 if i < n - 2 else 1.1)
		var droop := (-0.8 + f * 0.9) if not air else (-0.25 + f * 0.1)
		if _dead:
			droop = -0.2
			yaw = 0.25 * _death_side * f
		var want := back.rotated(Vector3.UP, yaw)
		want = (want + Vector3.UP * droop).normalized()
		var d := _tail[i] - _tail[i - 1]
		d = d.normalized() if d.length_squared() > 1e-6 else want
		d = d.lerp(want, k * (0.5 + (1.0 - f) * 1.5)).normalized()
		d = d.lerp(prev, 0.25).normalized()
		var pt := _tail[i - 1] + d * _seg
		var r: float = lerpf(1.2, 0.08, f)
		if not air and pt.y < ground + r * 0.9:
			pt.y = ground + r * 0.9
		_tail[i] = pt
		prev = d
	for i in range(PELVIS + 1, n):
		chain.display[i] = _tail[i]


func _pose_legs(delta: float, root: Transform3D, basis: Basis, chest_w: Vector3, pelvis_w: Vector3, body_rot: Basis, claw_lift: float, claw_reach: float, air: bool) -> void:
	var fwd := -basis.z
	var ground := _ground()
	for li in legs.size():
		var leg: Dictionary = legs[li]
		var front: bool = leg["front"]
		var side: float = leg["side"]
		var jf := chain.frame(int(leg["joint"]))
		var jp := chain.joint(int(leg["joint"]))
		var hip := jp + jf * (leg["off"] as Vector3)
		var rest: Vector3 = leg["rest"]
		# Gait: stance (foot travels back under the body) then swing (lifted forward).
		var ph := fposmod(_gait + float(leg["phase"]), 1.0)
		var duty := 0.68
		var stride := 3.0 * _walk
		var foot_l := rest
		var lift := 0.0
		if ph < duty:
			foot_l.z += stride * (ph / duty - 0.5)
		else:
			var s := (ph - duty) / (1.0 - duty)
			foot_l.z += stride * (0.5 - s)
			lift = sin(PI * s) * 0.9 * _walk
		foot_l.y = lift
		var down_now := lift < 0.05
		if down_now and not bool(_foot_was_down[li]) and _walk > 0.3:
			var fw := root * foot_l
			fw.y = ground
			CreatureFx.play(_fx_parent(), "dust_cloud", fw, 0.45)
			Audio.play("stomp", fw, -6.0, 0.55 + randf() * 0.1)
			_quake(fw, 0.12)
		_foot_was_down[li] = down_now
		var foot_w := root * foot_l
		foot_w.y = ground + lift
		# The claw: one foreleg rears up, then rakes down ahead.
		if front and side == _claw_side and (claw_lift > 0.0 or claw_reach > 0.0):
			var raised := root * Vector3(side * 1.7, 3.6, -4.2)
			var struck := root * Vector3(side * 2.3, 0.0, -6.4)
			struck.y = ground
			foot_w = foot_w.lerp(struck, claw_reach).lerp(raised, claw_lift)
		if _dead:
			var splay := root * Vector3(side * (3.4 if front else 3.0), 0.0, rest.z * 1.15)
			splay.y = ground + 0.3
			foot_w = foot_w.lerp(splay, clampf(_dead_t / 1.6, 0.0, 1.0))
		if _fly > 0.01:
			# Tucked: forelegs folded to the chest, hind legs trailing.
			var tuck_l := Vector3(side * 1.1, -1.3, -1.5) if front else Vector3(side * 1.1, -1.5, 3.6)
			var tuck := (chest_w if front else pelvis_w) + basis * (body_rot * tuck_l)
			foot_w = foot_w.lerp(tuck, _fly)
		var lens: Array = leg["lens"]
		var a: float = lens[0]
		var b: float = lens[1]
		var c: float = lens[2]
		var segs: Array = leg["segs"]
		var up := Vector3.UP
		var back_dir := basis.z
		var ankle: Vector3
		var pole: Vector3
		if front:
			ankle = foot_w + up * c * 0.92 + back_dir * c * 0.2
			pole = back_dir * 1.0 + basis.x * side * 0.25
		else:
			ankle = foot_w + up * c * 0.82 + back_dir * c * 0.55
			pole = -back_dir + basis.x * side * 0.2
		if _fly > 0.01:
			ankle = ankle.lerp(foot_w + back_dir * c * 0.8, _fly)
		var knee := ArachnidModel._ik_knee(hip, ankle, a, b, pole)
		var side_ref := basis.x
		_orient(segs[0], hip, knee, side_ref)
		_orient(segs[1], knee, ankle, side_ref)
		_orient(segs[2], ankle, foot_w + up * 0.25, side_ref)
		var foot: Node3D = leg["foot"]
		var foot_basis := Basis.looking_at(fwd, Vector3.UP)
		if _fly > 0.01:
			foot_basis = foot_basis.slerp(Basis.looking_at(fwd.lerp(Vector3.DOWN, 0.7).normalized(), basis.z), _fly)
		if front and side == _claw_side and claw_lift > 0.0:
			foot_basis = foot_basis * Basis(Vector3.RIGHT, -claw_lift * 0.9)
		foot.global_transform = Transform3D(foot_basis, foot_w)


## Direction a turned towards b by fraction t (safe for opposite / zero vectors).
static func turn_dir(a: Vector3, b: Vector3, t: float) -> Vector3:
	if b.length_squared() < 1e-8:
		return a
	if a.length_squared() < 1e-8:
		return b.normalized()
	var v := a.normalized().lerp(b.normalized(), clampf(t, 0.0, 1.0))
	if v.length_squared() < 1e-6:
		v = a.normalized().rotated(Vector3.UP, 0.3)
	return v.normalized()


static func _orient(seg: Node3D, from: Vector3, to: Vector3, side_ref: Vector3) -> void:
	var y := to - from
	if y.length_squared() < 1e-8:
		return
	y = y.normalized()
	var x := side_ref - y * side_ref.dot(y)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	seg.global_transform = Transform3D(Basis(x, y, z), from)


func _pose_wings(_delta: float, flap_s: float) -> void:
	for wd: Dictionary in wings:
		var s: float = wd["side"]
		var sk: Skeleton3D = wd["skel"]
		var fold := clampf(_fold, 0.0, 1.0)
		# Flapping: downstroke quick, upstroke with the wing half folded.
		var stroke := flap_s * 0.95 * _flap_amp
		var up_fold := maxf(0.0, cos(_flap)) * 0.35 * _flap_amp
		var raise := _raise + stroke
		var f_eff := clampf(fold + up_fold, 0.0, 1.0)
		var q_raise := Quaternion(Vector3.BACK, s * raise * 0.9)
		var q_sweep := Quaternion(Vector3.UP, s * -0.15 * sin(_flap - 0.6) * _flap_amp)
		var idle := Quaternion(Vector3.BACK, s * 0.03 * sin(_time * 1.1)) if fold > 0.8 else Quaternion.IDENTITY
		var qh: Quaternion = (wd["q_hum"] as Quaternion)
		sk.set_bone_pose_rotation(1, q_raise * q_sweep * idle * Quaternion.IDENTITY.slerp(qh, f_eff))
		var qf: Quaternion = wd["q_fore"]
		var lag := Quaternion(Vector3.BACK, s * -0.35 * sin(_flap - 0.9) * _flap_amp)
		sk.set_bone_pose_rotation(2, lag * Quaternion.IDENTITY.slerp(qf, f_eff))
		var qd: Array = wd["q_digits"]
		for d in 4:
			var curl := Quaternion(Vector3.BACK, s * -0.18 * sin(_flap - 1.3) * _flap_amp * (0.5 + d * 0.2))
			sk.set_bone_pose_rotation(4 + d, curl * Quaternion.IDENTITY.slerp(qd[d] as Quaternion, f_eff))


## Dust / embers at a point given in model space (relative to the origin, model axes).
func _fx(style: String, local_offset: Vector3, scale := 1.0) -> void:
	var pos := global_transform * local_offset
	pos.y = _ground() + 0.2
	CreatureFx.play(_fx_parent(), style, pos, scale)


## A local camera shake that fades with distance (footfalls, landings).
func _quake(at: Vector3, strength: float) -> void:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null:
		return
	var d := cam.global_position.distance_to(at)
	var s := strength * clampf(1.0 - (d - 8.0) / 45.0, 0.0, 1.0)
	if s > 0.02 and Engine.get_main_loop() is SceneTree and (Engine.get_main_loop() as SceneTree).root.has_node("Events"):
		Events.screen_shake.emit(s)
