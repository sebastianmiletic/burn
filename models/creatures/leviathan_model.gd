class_name LeviathanModel
extends CreatureModel
## The Leviathan of the Grey Sea (and its lesser kin, the sea serpent):
## a 50 m serpent drawn as one smooth skinned body that follows its head
## through the water (SerpentChain), with a long armoured skull, a hinged
## jaw full of curved teeth, glowing eyes, swept horns, flaring gill frills,
## trailing barbels, a dorsal sail, pectoral fins and a crescent tail fluke.
## Photophores glow along its flanks.
##
## The entity position is the head's anchor at the water line. Set
## `surfaced` (rear the head out of the water), `water_y`, `arena_center`
## and `platform_y`; one-shot actions: bite, roar, breath (spit), slam (tail
## slam towards the arena), swipe (head sweep across the platform), whip
## (thrashing coils racing round the islet), summon, dive, hit, die.

var surfaced := false
var engaged := false
var water_y := 13.0
var arena_center := Vector3.INF
var platform_y := 15.0
var variant := "leviathan"

var k := 1.0
## Joints of the neck: drawn as a curve from where the body leaves the water to the head.
const NECK := 4
var body_length := 50.0
var bones := 26
var chain: SerpentChain
var head: Node3D
var jaw: Node3D
var frills: Array[Node3D] = []
var fins: Array = []      # [pivot: Node3D, side: float, phase: float]
var fluke: Node3D
var eyes: Array[MeshInstance3D] = []
var maw_glow: MeshInstance3D

var _surf := 0.0
var _jaw := 0.0
var _frill := 0.0
var _prev_base := Vector3.INF
var _vel := Vector3.ZERO
var _look := Vector3.FORWARD
var _head_pos := Vector3.ZERO
var _was_under := true
var _tail_target := Vector3.INF
var _slammed := false
var _wake: GPUParticles3D
var _sink := 0.0
var _bite_target := Vector3.INF


func _enter_tree() -> void:
	TelegraphFx.listen(_on_telegraph)


func _exit_tree() -> void:
	TelegraphFx.unlisten(_on_telegraph)


## Aim the tail and jaws exactly at the telegraphs the boss announces.
func _on_telegraph(style: String, _shape: String, pos: Vector3, dir: Vector3, _size: Vector3, _duration: float) -> void:
	if not is_inside_tree() or pos.distance_to(global_position) > 90.0 * k:
		return
	if style == "tail":
		_tail_target = pos + Vector3(dir.x, 0, dir.z).normalized() * 13.0 * k
		_slammed = false
	elif style == "bite":
		_bite_target = pos


func _init(kind_name := "leviathan") -> void:
	variant = kind_name
	if variant == "sea_serpent":
		k = 0.36
		body_length = 18.0
		bones = 16
	elif variant == "deep_leviathan":
		# The Dark Ocean's wandering leviathan (an ordinary mob, not the boss): half size.
		k = 0.5
		body_length = 25.0
		bones = 20
	elif variant == "abyssal_eel":
		k = 0.15
		body_length = 7.0
		bones = 12
	dissolve_delay = 3.5
	dissolve_time = 3.0
	durations["bite"] = 1.6
	durations["slam"] = 2.0
	durations["breath"] = 1.6
	durations["roar"] = 2.0
	durations["summon"] = 1.8
	durations["dive"] = 1.2
	durations["swipe"] = 2.0
	durations["whip"] = 2.8
	durations["hit"] = 0.6


func _ember_extents() -> Vector3:
	return Vector3(3.0, 2.0, 6.0) * k


func _lod_size() -> float:
	return 22.0 * k


## Mob variants (Enemy animation codes) borrow the boss's moves.
const MOB_ACTIONS := {"attack": "bite", "lunge": "bite", "throw": "breath", "slam": "swipe"}


func play(action: String, duration := -1.0) -> void:
	if variant in ["deep_leviathan", "abyssal_eel"] and MOB_ACTIONS.has(action):
		action = MOB_ACTIONS[action]
		duration = maxf(duration, float(durations.get(action, 0.6)) * (0.6 if variant == "abyssal_eel" else 1.0))
	super.play(action, duration)


func _palette() -> Dictionary:
	if variant == "deep_leviathan":
		return {"back": Color(0.03, 0.04, 0.06), "belly": Color(0.2, 0.22, 0.26), "accent": Color(0.01, 0.01, 0.02),
			"eye": Color(1.0, 0.25, 0.2), "fin": Color(0.08, 0.1, 0.16), "glow": Color(0.45, 0.35, 1.0)}
	if variant == "abyssal_eel":
		return {"back": Color(0.04, 0.03, 0.06), "belly": Color(0.16, 0.12, 0.2), "accent": Color(0.01, 0.01, 0.02),
			"eye": Color(0.9, 0.95, 0.6), "fin": Color(0.1, 0.06, 0.14), "glow": Color(0.75, 0.4, 1.0)}
	if variant == "sea_serpent":
		return {"back": Color(0.12, 0.2, 0.14), "belly": Color(0.62, 0.6, 0.42), "accent": Color(0.05, 0.09, 0.07),
			"eye": Color(1.0, 0.75, 0.25), "fin": Color(0.35, 0.45, 0.3), "glow": Color(0.6, 1.0, 0.5)}
	return {"back": Color(0.07, 0.14, 0.17), "belly": Color(0.5, 0.58, 0.55), "accent": Color(0.03, 0.06, 0.08),
		"eye": Color(0.35, 1.0, 0.85), "fin": Color(0.2, 0.42, 0.48), "glow": Color(0.35, 0.95, 1.0)}


func _build() -> void:
	var pal := _palette()
	var scale_mat := CreatureSkin.scales(pal["back"], pal["belly"], 2.6 / k, {"use_uv": true, "wet": 0.65,
		"accent": pal["accent"], "accent_mode": 3, "accent_amount": 0.7, "accent_scale": 0.12 / k,
		"glow_mode": 1, "glow_color": pal["glow"], "glow_amount": 0.07, "glow_energy": 3.5, "glow_pulse": 0.6,
		"bump": 1.4, "bump_distance": 110.0})
	var head_mat := CreatureSkin.scales(pal["back"], pal["belly"], 3.2 / k, {"wet": 0.6, "bump": 1.2, "bump_distance": 90.0, "accent": pal["accent"],
		"accent_mode": 3, "accent_amount": 0.5, "accent_scale": 0.5 / k})
	var plate := CreatureSkin.hide((pal["back"] as Color).darkened(0.35), (pal["back"] as Color).darkened(0.1), {"wet": 0.5, "pattern_scale": 2.5 / k})
	var fin_mat := CreatureSkin.membrane(pal["fin"], {"backlight": 1.1, "accent": (pal["fin"] as Color).darkened(0.5),
		"accent_mode": 1, "accent_amount": 0.5, "accent_scale": 1.6 / k})
	var tooth := CreatureSkin.keratin(Color(0.88, 0.86, 0.76))
	var horn := CreatureSkin.keratin(Color(0.32, 0.3, 0.27), {"roughness": 0.5})
	var maw := CreatureSkin.mouth()

	# --- Body ----------------------------------------------------------------------
	var prof := [[0.0, 1.45, 1.35], [0.07, 1.85, 1.7], [0.24, 2.3, 2.1], [0.45, 2.0, 1.85], [0.62, 1.45, 1.35],
			[0.8, 0.85, 0.8], [0.92, 0.45, 0.45], [1.0, 0.16, 0.22]]
	for row: Array in prof:
		row[1] = float(row[1]) * k
		row[2] = float(row[2]) * k
	var mesh := OrganicMesh.skinned_tube("leviathan_body_%s" % variant, body_length, bones, prof, 72 if k > 0.5 else 40, 16)
	chain = SerpentChain.new().setup(mesh, scale_mat, bones, body_length, 120.0 * k)
	chain.name = "Chain"
	chain.wave_amp = 1.3 * k
	chain.wave_count = 1.2
	chain.wave_speed = 1.6
	chain.stiffness = 0.3
	add_child(chain)

	# Dorsal sail: one panel per joint, tallest behind the head.
	var sail_end := int(bones * 0.8)
	for i in range(1, sail_end):
		var t := float(i) / (bones - 1)
		var r := _radius_at(prof, t)
		var h := lerpf(1.7, 0.35, float(i) / sail_end) * k
		var half := chain.seg * 0.62
		var holder := Node3D.new()
		chain.attach(i, holder)
		var pts := PackedVector2Array([Vector2(half, 0), Vector2(half * 0.3, h), Vector2(-half * 0.6, h * 0.82), Vector2(-half, 0)])
		var key := "lev_sail_%s_%d" % [variant, i]
		ModelKit.part(holder, OrganicMesh.membrane(key, pts, 0.0, 0.05 * k), fin_mat, Vector3(0, r.y - 0.2 * k, 0), Vector3(0, 90, 0))
		var spine := OrganicMesh.bezier("lev_spine_%s_%d" % [variant, i], Vector3.ZERO, Vector3(0, h * 0.6, 0.15 * h), Vector3(0, h * 1.08, 0.5 * h), 0.09 * k, 0.012 * k, 6, 5)
		ModelKit.part(holder, spine, horn, Vector3(0, r.y - 0.2 * k, -half * 0.25))

	# Pectoral and pelvic fins.
	for spec: Array in [[NECK + 1, 1.0], [int(bones * 0.5), 0.6]]:
		var ji: int = spec[0]
		var size: float = spec[1] * k
		var r := _radius_at(prof, float(ji) / (bones - 1))
		for side: float in [-1.0, 1.0]:
			var holder := Node3D.new()
			chain.attach(ji, holder)
			var pivot := ModelKit.joint(holder, "Fin", Vector3(side * r.x * 0.85, -r.y * 0.35, 0))
			var pts := PackedVector2Array([Vector2(0, 0.4), Vector2(2.2, 0.6), Vector2(5.2, -0.4), Vector2(6.0, -1.6),
					Vector2(4.2, -2.0), Vector2(2.4, -2.6), Vector2(0.6, -1.4), Vector2(0, -0.6)])
			for p in pts.size():
				pts[p] = Vector2(pts[p].x * side, pts[p].y) * size
			var fin := ModelKit.part(pivot, OrganicMesh.membrane("lev_pec_%s_%d_%d" % [variant, ji, int(side)], pts, 0.25 * size, 0.06 * size), fin_mat, Vector3.ZERO, Vector3(-75, side * 25, 0))
			for f in 4:
				var tip := Vector3(side * (2.2 + f * 1.15), 0, 0.3 + f * 0.25) * size
				var spar := OrganicMesh.bezier("lev_pec_spar_%s_%d_%d_%d" % [variant, ji, int(side), f], Vector3.ZERO, tip * 0.5 + Vector3(0, 0.15 * size, 0), tip, 0.1 * size, 0.02 * size, 5, 5)
				var sp := ModelKit.part(fin, spar, horn, Vector3(0, 0, 0))
				sp.rotation_degrees = Vector3(90, 0, 0)
			fins.append([pivot, side, float(ji) * 0.7])

	# Tail fluke: a vertical crescent.
	fluke = Node3D.new()
	chain.attach(bones - 1, fluke)
	var fpts := PackedVector2Array([Vector2(0.4, 0), Vector2(-1.0, 2.6), Vector2(-3.4, 4.4), Vector2(-2.0, 1.6),
			Vector2(-2.4, 0), Vector2(-2.0, -1.6), Vector2(-3.4, -4.0), Vector2(-1.0, -2.2)])
	for p in fpts.size():
		fpts[p] *= k
	ModelKit.part(fluke, OrganicMesh.membrane("lev_fluke_%s" % variant, fpts, 0.0, 0.08 * k), fin_mat, Vector3(0, 0, 0.4 * k), Vector3(0, 90, 0))

	# --- Head -------------------------------------------------------------------------
	head = Node3D.new()
	head.name = "Head"
	head.top_level = true
	add_child(head)
	var skull := OrganicMesh.profile("lev_skull_%s" % variant, Vector3(0, 0.1, 1.3) * k, Vector3(0, 0, -6.5) * k,
		[[0.0, 1.5 * k, 1.35 * k, 0], [0.16, 1.75 * k, 1.5 * k, 0.2 * k], [0.4, 1.42 * k, 1.12 * k, 0.24 * k],
		[0.66, 1.05 * k, 0.78 * k, 0.04 * k], [0.88, 0.7 * k, 0.5 * k, -0.1 * k], [1.0, 0.28 * k, 0.24 * k, -0.15 * k]], 18, 20)
	ModelKit.part(head, skull, head_mat)
	# Armoured brow and cheek plates.
	for side: float in [-1.0, 1.0]:
		ModelKit.part(head, OrganicMesh.blob("lev_brow_%s" % variant, Vector3(0.5, 0.3, 1.5) * k, 0.2, 3, 12), plate, Vector3(side * 0.95, 0.88, -2.0) * k, Vector3(8, side * 12, side * -14))
		ModelKit.part(head, OrganicMesh.blob("lev_cheek_%s" % variant, Vector3(0.45, 0.6, 1.2) * k, 0.25, 5, 12), plate, Vector3(side * 1.45, -0.05, -0.4) * k, Vector3(0, side * 8, 0))
		var eye_mesh := ModelKit.part(head, ModelKit.sphere(0.3 * k, 12), CreatureSkin.eye(pal["eye"], 7.0, 0.25), Vector3(side * 1.18, 0.55, -2.55) * k, Vector3.ZERO, Vector3(0.8, 0.75, 1.15))
		eyes.append(eye_mesh)
		ModelKit.part(head, ModelKit.sphere(0.13 * k, 8), ModelKit.mat(Color(0.02, 0.02, 0.02), AsciiMaterialId.SOLID, 0.2), Vector3(side * 1.36, 0.56, -2.62) * k, Vector3.ZERO, Vector3(0.5, 1.4, 0.6))
		# Swept-back horns.
		var hm := OrganicMesh.bezier("lev_horn_%s_%d" % [variant, int(side)], Vector3.ZERO, Vector3(side * 0.35, 1.0, 1.8) * k, Vector3(side * 0.75, 0.55, 4.0) * k, 0.34 * k, 0.03 * k, 10, 8)
		ModelKit.part(head, hm, horn, Vector3(side * 0.85, 1.05, 0.0) * k)
		var hm2 := OrganicMesh.bezier("lev_horn2_%s_%d" % [variant, int(side)], Vector3.ZERO, Vector3(side * 0.6, 0.2, 1.0) * k, Vector3(side * 1.1, -0.2, 2.3) * k, 0.2 * k, 0.02 * k, 8, 6)
		ModelKit.part(head, hm2, horn, Vector3(side * 1.25, 0.35, 0.4) * k)
		# Nostril pits.
		ModelKit.part(head, ModelKit.sphere(0.12 * k, 6), maw, Vector3(side * 0.32, 0.28, -5.9) * k, Vector3.ZERO, Vector3(0.8, 0.5, 1.4))
		# Barbels trailing from the snout.
		var bm := OrganicMesh.bezier("lev_barbel_%s_%d" % [variant, int(side)], Vector3.ZERO, Vector3(side * 0.5, -1.3, 0.8) * k, Vector3(side * 0.9, -2.8, 2.6) * k, 0.08 * k, 0.012 * k, 10, 5)
		ModelKit.part(head, bm, head_mat, Vector3(side * 0.55, -0.25, -5.3) * k)
	# Crest spines along the skull.
	for i in 5:
		var z := (-0.4 - i * 0.75) * k
		var hsp := (0.75 - i * 0.1) * k
		var cm := OrganicMesh.bezier("lev_crest_%s_%d" % [variant, i], Vector3.ZERO, Vector3(0, hsp * 0.6, hsp * 0.2), Vector3(0, hsp, hsp * 0.7), 0.13 * k, 0.015 * k, 6, 5)
		ModelKit.part(head, cm, horn, Vector3(0, 1.45 * k - i * 0.1 * k, z))
	# The maw: a wet throat inside, upper teeth hanging from the skull edge.
	ModelKit.part(head, OrganicMesh.blob("lev_maw_%s" % variant, Vector3(1.0, 0.3, 2.7) * k, 0.1, 7, 12), maw, Vector3(0, -0.5, -2.7) * k)
	maw_glow = ModelKit.part(head, ModelKit.sphere(0.6 * k, 10), ModelKit.glow(Color(0.55, 1.0, 0.35), 5.0, 0.5), Vector3(0, -0.45, -1.2) * k, Vector3.ZERO, Vector3(1.2, 0.5, 1.8))
	_teeth(head, tooth, 11, -0.62, -1.3, -6.0, -1.0)
	# Lower jaw.
	jaw = ModelKit.joint(head, "Jaw", Vector3(0, -0.6, 0.35) * k)
	var jaw_mesh := OrganicMesh.profile("lev_jaw_%s" % variant, Vector3(0, 0, 0), Vector3(0, -0.15, -6.0) * k,
		[[0.0, 1.25 * k, 0.6 * k, 0], [0.35, 1.15 * k, 0.52 * k, -0.08 * k], [0.75, 0.78 * k, 0.38 * k, 0], [1.0, 0.32 * k, 0.2 * k, 0.06 * k]], 14, 14)
	ModelKit.part(jaw, jaw_mesh, head_mat)
	_teeth(jaw, tooth, 9, 0.28, -1.7, -6.1, 1.0)
	for side: float in [-1.0, 1.0]:
		ModelKit.part(jaw, OrganicMesh.blob("lev_chin_%s" % variant, Vector3(0.35, 0.4, 1.6) * k, 0.3, 11, 10), plate, Vector3(side * 0.7, -0.35, -2.4) * k)
	# Gill frills: spined fans that flare when it roars.
	for side: float in [-1.0, 1.0]:
		var frill := ModelKit.joint(head, "Frill", Vector3(side * 1.5, 0.1, 0.9) * k)
		var fan := PackedVector2Array()
		fan.append(Vector2.ZERO)
		for a in 9:
			var ang := deg_to_rad(-70.0 + a * 18.0)
			var rr := (2.8 if a % 2 == 0 else 2.3) * k
			fan.append(Vector2(cos(ang), sin(ang)) * rr)
		for p in fan.size():
			fan[p].x *= side
		ModelKit.part(frill, OrganicMesh.membrane("lev_frill_%s_%d" % [variant, int(side)], fan, 0.3 * k, 0.05 * k), fin_mat, Vector3.ZERO, Vector3(0, side * -70, 0))
		for a in range(0, 9, 2):
			var ang := deg_to_rad(-70.0 + a * 18.0)
			var tip := Vector3(cos(ang) * side, sin(ang), 0) * 2.95 * k
			var sm := OrganicMesh.bezier("lev_frill_spine_%s_%d_%d" % [variant, int(side), a], Vector3.ZERO, tip * 0.5, tip, 0.08 * k, 0.012 * k, 5, 5)
			var sp := ModelKit.part(frill, sm, horn, Vector3.ZERO)
			sp.rotation_degrees = Vector3(0, side * -70, 0)
		frills.append(frill)
	if particles_enabled:
		_wake = CreatureFx.emitter(self, "foam", 36, Vector3(1.5, 0.2, 1.5) * k)
		_wake.emitting = false


## Two rows of curved teeth along a jaw edge (y), from z0 to z1. dir -1 = hanging, +1 = upward.
func _teeth(parent: Node3D, mat: Material, count: int, y: float, z0: float, z1: float, dir: float) -> void:
	for side: float in [-1.0, 1.0]:
		for i in count:
			var f := float(i) / (count - 1)
			var z := lerpf(z0, z1, f) * k
			var half_w := lerpf(1.15, 0.3, f) * k
			var fang := i == 1 or i == 2
			var length := (0.85 if fang else lerpf(0.55, 0.3, f)) * k
			if dir > 0.0:
				length *= 0.8
			var key := "lev_tooth_%s_%d_%d" % [variant, int(dir), int(length * 100.0)]
			var tm := OrganicMesh.bezier(key, Vector3.ZERO, Vector3(0, dir * length * 0.6, 0.05 * length), Vector3(0, dir * length, 0.35 * length), length * 0.17, length * 0.02, 5, 6)
			ModelKit.part(parent, tm, mat, Vector3(side * half_w, y * k, z), Vector3(0, 0, side * dir * -8.0))


func _radius_at(prof: Array, t: float) -> Vector2:
	var s := OrganicMesh._sample(prof, t)
	return Vector2(s[0], s[1])


## Where a tail slam starting now would land: from the tail tip towards the arena.
func tail_slam_target() -> Vector3:
	if chain == null:
		return global_position
	var tip := chain.tail_tip()
	var to := (arena_center - tip) if arena_center.is_finite() else -_look
	to.y = 0.0
	if to.length() < 0.1:
		to = Vector3.FORWARD
	var target := tip + to.normalized() * 13.0 * k
	target.y = platform_y if arena_center.is_finite() else water_y
	return target


func _on_action(action_name: String) -> void:
	if action_name == "slam":
		_tail_target = tail_slam_target()
		_slammed = false


func _fx_parent() -> Node3D:
	var ent := get_parent()
	if ent != null and ent.get_parent() is Node3D:
		return ent.get_parent() as Node3D
	return self


func _animate(delta: float) -> void:
	if chain == null:
		return
	var base := global_position
	if not _prev_base.is_finite():
		_prev_base = base
		chain.reset(base + Vector3(0, -2.0 * k, 0), global_transform.basis.z)
	_vel = _vel.lerp((base - _prev_base) / maxf(delta, 0.001), 1.0 - exp(-6.0 * delta))
	_prev_base = base
	var speed := Vector2(_vel.x, _vel.z).length()
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-4 else Vector3.FORWARD
	var p := action_progress()
	var w := action_weight(0.12, 0.22)

	_surf = damp(_surf, 1.0 if (surfaced and not _dead) else 0.0, 2.4, delta)
	var rear := lerpf((-2.2 if engaged else -0.9) * k, 7.5 * k, _surf)
	var pitch := lerpf(0.0, -0.3, _surf)
	var offset := Vector3.ZERO
	var jaw_t := 0.06 + sin(_time * 0.8) * 0.04
	var frill_t := 0.15 + sin(_time * 0.6) * 0.05
	var shake := 0.0
	var maw := 0.15
	if p >= 0.0 and not _dead:
		match _action:
			"bite":
				var lunge := keys(p, [[0, 0], [0.3, -0.35], [0.5, 1.0], [0.75, 1.0], [1, 0]])
				var reach := fwd * 6.5 * k
				var drop := 6.0 * k
				if _bite_target.is_finite():
					reach = _bite_target - base
					reach.y = 0.0
					reach = reach.limit_length(14.0 * k) - reach.normalized() * 2.5 * k
					drop = clampf(base.y + rear - _bite_target.y - 1.5 * k, 2.0 * k, 9.0 * k)
				offset += reach * lunge + Vector3.UP * (-lunge * drop)
				pitch += -lunge * 0.25
				jaw_t = lerpf(jaw_t, keys(p, [[0, 0.1], [0.3, 1.05], [0.5, 0.0], [1, 0.05]]), w)
				frill_t = lerpf(frill_t, 0.9, w)
			"roar", "summon":
				rear += 2.0 * k * w
				pitch = lerpf(pitch, 0.55, w)
				jaw_t = lerpf(jaw_t, 1.1 + sin(_time * 38.0) * 0.04, w)
				frill_t = lerpf(frill_t, 1.0, w)
				shake = 0.12 * w
				maw = 1.0
			"breath":
				var thrust := keys(p, [[0, 0], [0.3, -0.6], [0.45, 0.6], [0.8, 0.5], [1, 0]])
				offset += fwd * thrust * 3.0 * k
				pitch += 0.15 - thrust * 0.2
				jaw_t = lerpf(jaw_t, 0.95, w)
				frill_t = lerpf(frill_t, 0.8, w)
				maw = 2.5
			"dive":
				offset += fwd * 3.0 * k * w
				pitch = lerpf(pitch, -0.9, w)
			"swipe":
				# Wind up to one side, then swing the open jaws across (impact ~55 %).
				var side := fwd.cross(Vector3.UP)
				var swing := keys(p, [[0, 0], [0.35, -1.0], [0.55, 0.9], [0.75, 1.0], [1, 0]])
				offset += side * swing * 7.0 * k + fwd * keys(p, [[0, 0], [0.35, -1.5], [0.55, 4.0], [1, 0]]) * k
				offset += Vector3.UP * -keys(p, [[0, 0], [0.35, -1.0], [0.55, 4.0], [0.8, 3.0], [1, 0]]) * k
				pitch += -0.2 * w
				jaw_t = lerpf(jaw_t, keys(p, [[0, 0.2], [0.35, 1.0], [0.6, 0.9], [1, 0.1]]), w)
				frill_t = lerpf(frill_t, 1.0, w)
			"whip":
				# The coils thrash and the head plunges and rears as it races round.
				pitch = lerpf(pitch, -0.35 + 0.25 * sin(_time * 5.0), w)
				jaw_t = lerpf(jaw_t, 0.6, w)
				frill_t = lerpf(frill_t, 0.9, w)
				shake = 0.08 * w
			"hit":
				offset += -fwd * 1.2 * k * sin(PI * p)
				pitch += 0.25 * sin(PI * p)
				jaw_t = lerpf(jaw_t, 0.5, sin(PI * p))
	if _dead:
		_sink += delta
		rear = lerpf(-1.0 * k, -8.0 * k, clampf(_sink / 8.0, 0.0, 1.0))
		pitch = -0.2
		jaw_t = 0.55
	var head_target := base + Vector3.UP * rear + offset
	if shake > 0.0:
		head_target += Vector3(sin(_time * 31.0), sin(_time * 23.0) * 0.5, cos(_time * 27.0)) * shake * k
	_head_pos = _head_pos.lerp(head_target, 1.0 - exp(-7.0 * delta)) if _head_pos != Vector3.ZERO else head_target

	# Where the head points: along its motion when swimming, at the arena when reared up.
	var swim_dir := _vel.normalized() if _vel.length() > 0.8 else fwd
	swim_dir.y = clampf(swim_dir.y, -0.6, 0.6)
	var look := fwd.lerp(swim_dir.normalized(), 1.0 - _surf).normalized()
	if look.length_squared() < 0.5:
		look = fwd
	_look = _look.slerp(look, 1.0 - exp(-4.0 * delta)).normalized() if _look.length_squared() > 0.5 else look
	var head_basis := Basis.looking_at(_look, Vector3.UP)
	head_basis = head_basis * Basis(Vector3.RIGHT, pitch)
	head.global_transform = Transform3D(head_basis, _head_pos)
	_jaw = damp(_jaw, jaw_t, 12.0, delta)
	# The jaw reaches along -Z from its hinge: a positive X rotation would swing
	# its tip upwards into the skull, so open with a negative one (the jaw drops).
	jaw.rotation.x = -_jaw * 0.75
	_frill = damp(_frill, frill_t, 5.0, delta)
	for i in frills.size():
		var side := -1.0 if i == 0 else 1.0
		frills[i].rotation = Vector3(0, side * (0.9 - _frill * 0.9), side * sin(_time * 1.3 + i) * 0.05)
	maw_glow.set_instance_shader_parameter(&"intensity", lerpf(0.2, maw, w if p >= 0.0 else 0.0) * (0.0 if _dead else 1.0))
	for e in eyes:
		e.set_instance_shader_parameter(&"intensity", 0.0 if _dead else (1.0 + (0.8 if _action == "roar" else 0.0)))

	# Body: cruising with loops breaking the surface, or rising behind the reared head.
	var cruise := 1.0 - _surf
	chain.rest_height = water_y - lerpf(1.7, 1.4, _surf) * k - (3.0 * k * _sink / 8.0 if _dead else 0.0)
	chain.hump_amp = (3.0 * k if not engaged else 2.2 * k) * (0.5 + 0.5 * cruise) * (0.0 if _dead else 1.0)
	chain.wave_amp = (1.3 * k * (0.4 + 0.6 * clampf(speed / 6.0, 0.0, 1.0))) * (0.15 if _dead else 1.0)
	if _action == "whip" and p >= 0.0 and not _dead:
		chain.wave_amp *= 1.0 + 1.6 * w
		chain.hump_amp *= 1.0 + 1.2 * w
	# The body is simulated from the neck base; the neck itself is a curve from
	# there up to the head (straight behind it while swimming, a rearing S when surfaced).
	var flat_look := Vector3(_look.x, 0, _look.z).normalized() if Vector2(_look.x, _look.z).length() > 0.05 else fwd
	var base_cruise := _head_pos - flat_look * chain.seg * NECK
	var base_rear := base - fwd * 7.0 * k + Vector3(0, water_y - base.y - 1.2 * k, 0)
	var neck_base := base_cruise.lerp(base_rear, _surf)
	chain.simulate(neck_base, delta, 0.5 + speed / 6.0)
	for i in range(chain.bones - 1, NECK - 1, -1):
		chain.display[i] = chain.display[i - NECK]
	var rise := maxf(0.0, _head_pos.y - neck_base.y)
	var ctrl := neck_base + Vector3.UP * rise * 0.85 * _surf + (_head_pos - neck_base) * (0.5 - 0.35 * _surf)
	for i in NECK:
		var t := float(i) / NECK
		var a := _head_pos.lerp(ctrl, t)
		var b := ctrl.lerp(neck_base, t)
		chain.display[i] = a.lerp(b, t)
	_tail_override(p, w)
	chain.apply()
	for f: Array in fins:
		var pivot: Node3D = f[0]
		var side: float = f[1]
		var scull := sin(_time * 1.8 + float(f[2])) * 0.35 * (0.3 + cruise)
		pivot.rotation = Vector3(scull * 0.4, side * scull * 0.3, side * (0.2 + scull))

	# Splashes where the head breaks the surface, foam wake while cruising.
	var under := _head_pos.y < water_y - 0.3 * k
	if particles_enabled and under != _was_under and absf(_vel.y) + speed > 1.0 and not _dead:
		CreatureFx.play(_fx_parent(), "splash", Vector3(_head_pos.x, water_y, _head_pos.z), 1.6 * k + 0.4)
	_was_under = under
	var near_surface := absf(chain.joint(2).y - water_y) < 3.0 * k
	if _wake != null:
		_wake.emitting = near_surface and speed > 1.5 and not _dead
		if _wake.emitting:
			_wake.global_position = Vector3(chain.joint(2).x, water_y + 0.2, chain.joint(2).z)


## Tail slam: the last third of the body lifts out of the water in an arc and
## crashes down onto `_tail_target`.
func _tail_override(p: float, w: float) -> void:
	if _action != "slam" or p < 0.0 or not _tail_target.is_finite():
		return
	var n := chain.bones
	var count := int(n * 0.4)
	var start_i := n - 1 - count
	var start := chain.display[start_i]
	var lift := keys(p, [[0, 0], [0.4, 1.0], [0.6, 1.1], [0.72, -0.05], [0.88, 0.0], [1, 0]])
	var reach := keys(p, [[0, 0.4], [0.45, 0.85], [0.72, 1.0], [1, 1.0]])
	var end := start.lerp(_tail_target, reach) + Vector3.UP * lift * 6.0 * k
	var ctrl := start.lerp(_tail_target, 0.35) + Vector3.UP * (5.0 + lift * 13.0) * k
	for j in range(1, count + 1):
		var t := float(j) / count
		var a := start.lerp(ctrl, t)
		var b := ctrl.lerp(end, t)
		var target := a.lerp(b, t)
		var i := start_i + j
		chain.display[i] = chain.display[i].lerp(target, w * smoothstep(0.0, 0.5, t + 0.2))
	if p > 0.7 and not _slammed:
		_slammed = true
		if particles_enabled:
			CreatureFx.play(_fx_parent(), "splash", _tail_target, 2.2 * k)
			CreatureFx.play(_fx_parent(), "dust", _tail_target, 2.0 * k)
