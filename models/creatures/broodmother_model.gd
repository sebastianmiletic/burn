class_name BroodmotherModel
extends CreatureModel
## Vexhira, the Broodmother: a 14 m (leg span) spider queen.
##
## * Segmented chitin: a ridged carapace over the cephalothorax, a pedicel,
##   and a huge banded abdomen marked in bone-white, carrying a clutch of
##   glowing, pulsing egg sacs that burst when she calls her brood.
## * Eight eyes (two great principal eyes), heavy chelicerae with long
##   hinged fangs that unfold to strike, twitching pedipalps, bristles on
##   the legs and back, spinnerets.
## * Eight legs with knees high above the body, solved with IK each frame
##   from an alternating-tetrapod gait (feet plant), twitchy idle.
## * Actions: bite, slam (front legs stab), shoot (web lash from the
##   spinnerets along the marked lane), cast (venom spit), summon (brood),
##   roar (threat display: rears, front legs raised and spread), lunge /
##   pounce (crouch, leap), hit, die (legs curl). `hanging` = climbed to the
##   cavern roof on a silk line (`ceiling_y` sets where it is anchored).
## Faces -Z; the origin is the ground under the body.

const BODY_H := 2.7
## Fraction of an action at which its blow lands (the boss times telegraphs to these).
const IMPACT := {"bite": 0.55, "slam": 0.5, "lunge": 0.7, "shoot": 0.45, "cast": 0.5}

var hanging := false
var ceiling_y := NAN
var ground_y := NAN
var look_target := Vector3.INF

var body: Node3D
var head: Node3D
var abdomen: Node3D
var fangs: Array[Node3D] = []
var chelicerae: Array[Node3D] = []
var palps: Array[Node3D] = []
var legs: Array = []
var eyes: MeshInstance3D
var sacs: Array[MeshInstance3D] = []
var thread: MeshInstance3D
var web_line: MeshInstance3D

var _gait := 0.0
var _walk := 0.0
var _prev_root := Vector3.INF
var _vel := Vector3.ZERO
var _last_ground := 0.0
var _impact_done := false
var _twitch := []
var _twitch_t := 0.0
var _rng := RandomNumberGenerator.new()
var _sac_pop := 0.0
var _hang := 0.0
var _web_t := -1.0
var _web_from := Vector3.ZERO
var _web_to := Vector3.ZERO
var _body_pos := Vector3(0, BODY_H, 0)
var _body_rot := Vector3.ZERO
var _foot_was_down := []
var _was_hanging := false


func _init() -> void:
	dissolve_delay = 3.0
	dissolve_time = 2.6
	durations["bite"] = 1.1
	durations["slam"] = 1.3
	durations["shoot"] = 1.0
	durations["cast"] = 1.2
	durations["summon"] = 1.8
	durations["roar"] = 1.8
	durations["lunge"] = 1.2
	_rng.seed = 909


func _enter_tree() -> void:
	TelegraphFx.listen(_on_telegraph)


func _exit_tree() -> void:
	TelegraphFx.unlisten(_on_telegraph)


## A web lash marked on the ground: shoot the silk along that lane.
func _on_telegraph(style: String, shape: String, pos: Vector3, dir: Vector3, size: Vector3, duration: float) -> void:
	if not is_inside_tree() or style != "web" or shape != "line" or pos.distance_to(global_position) > 30.0:
		return
	_web_from = pos
	_web_to = pos + Vector3(dir.x, 0, dir.z).normalized() * size.x
	_web_t = -maxf(0.0, duration - 0.18)


func _ember_extents() -> Vector3:
	return Vector3(2.5, 1.5, 4.0)


func _lod_size() -> float:
	return 7.0


# --- Build -------------------------------------------------------------------------------

func _build() -> void:
	var black := Color(0.075, 0.06, 0.08)
	var bone := Color(0.82, 0.78, 0.68)
	var glow := Color(0.72, 0.35, 1.0)
	var shell := CreatureSkin.chitin(black, {"pattern_scale": 1.6, "accent": Color(0.35, 0.3, 0.27), "accent_mode": 1, "accent_amount": 0.18,
		"accent_scale": 1.4, "roughness": 0.28, "specular_amount": 0.65, "rim": 0.4, "bump": 1.2, "bump_distance": 80.0})
	var leg_mat := CreatureSkin.chitin(black, {"pattern_scale": 2.4, "accent": Color(0.42, 0.36, 0.3), "accent_mode": 1,
		"accent_amount": 0.55, "accent_scale": 0.9, "roughness": 0.32, "specular_amount": 0.6, "rim": 0.4, "bump": 1.0})
	var abd_mat := CreatureSkin.chitin(Color(0.1, 0.07, 0.1), {"pattern_scale": 1.1, "accent": bone, "accent_mode": 2,
		"accent_amount": 0.85, "accent_scale": 0.55, "glow_mode": 2, "glow_color": glow, "glow_amount": 0.12, "glow_energy": 1.6,
		"glow_pulse": 1.0, "roughness": 0.3, "specular_amount": 0.6, "rim": 0.45, "bump": 1.1, "belly": Color(0.22, 0.12, 0.2), "belly_mix": 0.7})
	var bristle := CreatureSkin.keratin(Color(0.05, 0.04, 0.05), {"roughness": 0.6})
	var fang_mat := CreatureSkin.keratin(Color(0.08, 0.06, 0.06), {"roughness": 0.2, "specular_amount": 0.8})
	var sac_mat := CreatureSkin.membrane(Color(0.78, 0.74, 0.62), {"glow_mode": 1, "glow_color": glow, "glow_amount": 0.55,
		"glow_energy": 2.4, "glow_pulse": 1.0, "backlight": 1.8, "pattern_scale": 3.0})

	body = ModelKit.joint(self, "Body", Vector3(0, BODY_H, 0))
	# Cephalothorax with a ridged carapace and bristles.
	var ceph: Array = []
	ceph.append([OrganicMesh.profile("brood_ceph", Vector3(0, -0.1, 0.9), Vector3(0, 0.05, -2.7),
		[[0.0, 0.5, 0.4], [0.15, 1.35, 0.85, 0.05], [0.5, 1.55, 1.0, 0.12], [0.82, 1.15, 0.8, 0.1], [1.0, 0.45, 0.4, 0.0]], 20, 14), Transform3D()])
	ceph.append([OrganicMesh.blob("brood_carapace", Vector3(1.2, 0.45, 1.5), 0.12, 31, 16), Transform3D(Basis(), Vector3(0, 0.62, -0.75))])
	for i in 5:
		var a := lerpf(-1.1, 1.1, float(i) / 4.0)
		ceph.append([OrganicMesh.blob("brood_groove", Vector3(0.12, 0.12, 0.9), 0.1, 5 + i, 8), Transform3D(Basis(Vector3.UP, a), Vector3(sin(a) * 0.75, 0.82, -0.75 + cos(a) * 0.3))])
	ModelKit.part(body, OrganicMesh.merge("brood_ceph_all", ceph), shell)
	var hairs: Array = []
	for i in 40:
		var a := _rng.randf_range(-1.6, 1.6)
		var z := _rng.randf_range(-2.0, 0.6)
		var l := _rng.randf_range(0.25, 0.55)
		var base := Vector3(sin(a) * 1.3, cos(a) * 0.85 + 0.05, z)
		hairs.append([OrganicMesh.bezier("brood_hair", Vector3.ZERO, Vector3(0, 0.6, 0.15), Vector3(0, 1.0, 0.5), 0.05, 0.005, 3, 4), Transform3D(Basis(Vector3.BACK, -a) * Basis().scaled(Vector3.ONE * l), base)])
	ModelKit.part(body, OrganicMesh.merge("brood_hairs", hairs), bristle)

	# Head: eyes, chelicerae, fangs, palps.
	head = ModelKit.joint(body, "Head", Vector3(0, 0.2, -2.45))
	var eye_parts: Array = []
	var spots := [[Vector3(-0.28, 0.42, -0.1), 0.2], [Vector3(0.28, 0.42, -0.1), 0.2], [Vector3(-0.62, 0.38, 0.05), 0.15], [Vector3(0.62, 0.38, 0.05), 0.15],
		[Vector3(-0.3, 0.72, 0.15), 0.13], [Vector3(0.3, 0.72, 0.15), 0.13], [Vector3(-0.72, 0.6, 0.35), 0.11], [Vector3(0.72, 0.6, 0.35), 0.11]]
	for sp: Array in spots:
		eye_parts.append([ModelKit.sphere(1.0, 12), Transform3D(Basis().scaled(Vector3.ONE * float(sp[1])), sp[0])])
	eyes = ModelKit.part(head, OrganicMesh.merge("brood_eyes", eye_parts), CreatureSkin.eye(Color(0.85, 0.25, 1.0), 4.5, 0.25))
	for side: float in [-1.0, 1.0]:
		var ch := ModelKit.joint(head, "Chelicera", Vector3(side * 0.38, -0.05, -0.1))
		ModelKit.part(ch, OrganicMesh.profile("brood_chel", Vector3(0, 0.1, 0.1), Vector3(0, -1.05, -0.45),
			[[0.0, 0.42, 0.42], [0.4, 0.46, 0.44], [1.0, 0.26, 0.24]], 12, 8), shell)
		var fang := ModelKit.joint(ch, "Fang", Vector3(0, -1.0, -0.42))
		ModelKit.part(fang, OrganicMesh.bezier("brood_fang_%d" % int(side), Vector3.ZERO, Vector3(side * -0.1, -0.35, -0.25), Vector3(side * -0.35, -0.7, 0.15), 0.15, 0.012, 8, 6), fang_mat)
		chelicerae.append(ch)
		fangs.append(fang)
		var palp := ModelKit.joint(head, "Palp", Vector3(side * 0.8, -0.1, -0.05))
		ModelKit.part(palp, OrganicMesh.bezier("brood_palp_%d" % int(side), Vector3.ZERO, Vector3(side * 0.35, 0.3, -0.7), Vector3(side * 0.45, -0.5, -1.3), 0.15, 0.12, 8, 6), leg_mat)
		palps.append(palp)

	# Pedicel and the great banded abdomen with its clutch of egg sacs.
	abdomen = ModelKit.joint(body, "Abdomen", Vector3(0, 0.25, 0.95))
	var ab := Vector3(2.15, 1.85, 2.75)
	var abd: Array = []
	abd.append([OrganicMesh.blob("brood_abd", ab, 0.05, 17, 24), Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(0, ab.y * 0.45, ab.z * 0.92))])
	abd.append([OrganicMesh.profile("brood_pedicel", Vector3(0, 0, -0.3), Vector3(0, 0.25, 0.7), [[0.0, 0.42, 0.38], [0.5, 0.32, 0.3], [1.0, 0.6, 0.55]], 10, 6), Transform3D()])
	for side: float in [-1.0, 1.0]:
		abd.append([OrganicMesh.bezier("brood_spinneret", Vector3.ZERO, Vector3(0, -0.1, 0.25), Vector3(side * 0.1, -0.05, 0.55), 0.17, 0.07, 5, 6), Transform3D(Basis(), Vector3(side * 0.22, ab.y * 0.15, ab.z * 1.82))])
	ModelKit.part(abdomen, OrganicMesh.merge("brood_abd_all", abd), abd_mat)
	var ab_hairs: Array = []
	for i in 46:
		var th := _rng.randf_range(-1.4, 1.4)
		var ph := _rng.randf_range(0.2, 2.6)
		var n := Vector3(sin(th) * sin(ph), cos(ph) * 0.3 + 0.75, -cos(ph) * 0.8).normalized()
		var p := Vector3(n.x * ab.x, n.y * ab.y, n.z * ab.z * 0.9) * 0.97 + Vector3(0, ab.y * 0.45, ab.z * 0.92)
		var l := _rng.randf_range(0.3, 0.7)
		var b := Basis(Quaternion(Vector3.UP, n)) * Basis().scaled(Vector3.ONE * l)
		ab_hairs.append([OrganicMesh.bezier("brood_hair", Vector3.ZERO, Vector3(0, 0.6, 0.15), Vector3(0, 1.0, 0.5), 0.05, 0.005, 3, 4), Transform3D(b, p)])
	ModelKit.part(abdomen, OrganicMesh.merge("brood_abd_hairs", ab_hairs), bristle)
	for i in 9:
		var a := TAU * float(i) / 9.0 + 0.3
		var r := 0.55 + 0.25 * float(i % 3)
		var n := Vector3(cos(a) * r, 0.85, sin(a) * r * 0.9 + 0.1).normalized()
		var p := Vector3(n.x * ab.x, n.y * ab.y, n.z * ab.z) + Vector3(0, ab.y * 0.45, ab.z * 0.92)
		var sz := 0.38 + 0.12 * float(i % 3)
		var sac := ModelKit.part(abdomen, OrganicMesh.blob("brood_sac_%d" % (i % 3), Vector3(1.0, 0.85, 1.1), 0.12, 40 + i, 10), sac_mat, p, Vector3(0, a * 57.0, 0), Vector3.ONE * sz)
		sac.set_meta("size", sz)
		sacs.append(sac)

	thread = ModelKit.part(self, ModelKit.cylinder(0.06, 0.06, 1.0, 5), LairDecor.silk(), Vector3.ZERO)
	thread.visible = false
	thread.top_level = true
	web_line = ModelKit.part(self, ModelKit.cylinder(0.12, 0.12, 1.0, 5), LairDecor.silk(), Vector3.ZERO)
	web_line.visible = false
	web_line.top_level = true

	# Legs: hips round the cephalothorax, feet on a wide ellipse, knees high.
	for side: float in [-1.0, 1.0]:
		for i in 4:
			var f := float(i) / 3.0
			var hip := Vector3(side * 1.05, -0.05, lerpf(-1.85, 0.35, f))
			var ang := deg_to_rad(lerpf(-58.0, 62.0, f))
			var reach := 6.8 - absf(f - 0.45) * 1.6
			var foot := Vector3(side * cos(ang) * reach, 0.0, sin(ang) * reach * 1.05 - 0.6)
			var la := 4.1 if i == 0 else 3.7
			var lb := 4.4 if i == 0 else 4.0
			var lc := 1.5
			var segs: Array[Node3D] = []
			for k in 3:
				var n := Node3D.new()
				n.top_level = true
				add_child(n)
				segs.append(n)
			var key := "brood_leg%d" % (0 if i == 0 else 1)
			var parts_a: Array = [[OrganicMesh.profile(key + "_a", Vector3.ZERO, Vector3(0, la, 0), [[0.0, 0.5, 0.5], [0.12, 0.6, 0.58], [0.5, 0.52, 0.5], [0.85, 0.42, 0.42], [1.0, 0.46, 0.46]], 10, 8, Vector3.BACK), Transform3D()]]
			var parts_b: Array = [[OrganicMesh.profile(key + "_b", Vector3.ZERO, Vector3(0, lb, 0), [[0.0, 0.42, 0.42], [0.08, 0.38, 0.38], [0.5, 0.32, 0.32], [0.9, 0.22, 0.22], [1.0, 0.2, 0.2]], 10, 8, Vector3.BACK), Transform3D()]]
			parts_a.append([OrganicMesh.blob("brood_knee", Vector3(0.58, 0.54, 0.58), 0.1, 7, 8), Transform3D(Basis(), Vector3(0, la, 0))])
			for h in 12:
				var y := lerpf(0.4, la - 0.3, float(h) / 11.0)
				var a := float(h) * 2.3
				parts_a.append([OrganicMesh.bezier("brood_hair", Vector3.ZERO, Vector3(0, 0.6, 0.15), Vector3(0, 1.0, 0.5), 0.05, 0.005, 3, 4), Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 1.1) * Basis().scaled(Vector3.ONE * 0.75), Vector3(sin(a) * 0.45, y, cos(a) * 0.45))])
				parts_b.append([OrganicMesh.bezier("brood_hair", Vector3.ZERO, Vector3(0, 0.6, 0.15), Vector3(0, 1.0, 0.5), 0.05, 0.005, 3, 4), Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 1.2) * Basis().scaled(Vector3.ONE * 0.6), Vector3(sin(a) * 0.3, lerpf(0.3, lb - 0.3, float(h) / 11.0), cos(a) * 0.3))])
			ModelKit.part(segs[0], OrganicMesh.merge(key + "_a_all", parts_a), leg_mat)
			ModelKit.part(segs[1], OrganicMesh.merge(key + "_b_all", parts_b), leg_mat)
			ModelKit.part(segs[2], OrganicMesh.merge("brood_tarsus", [[OrganicMesh.profile("brood_leg_c", Vector3.ZERO, Vector3(0, lc, 0), [[0.0, 0.2, 0.2], [0.7, 0.13, 0.13], [1.0, 0.03, 0.03]], 8, 6, Vector3.BACK), Transform3D()]]), fang_mat)
			var group := (i + (0 if side < 0.0 else 1)) % 2
			legs.append({"hip": hip, "segs": segs, "rest": foot, "group": group, "la": la, "lb": lb, "lc": lc, "side": side, "i": i})
			_twitch.append(0.0)
			_foot_was_down.append(true)


# --- Animation ---------------------------------------------------------------------------

func _on_action(action_name: String) -> void:
	_impact_done = false
	if action_name == "summon":
		_sac_pop = 0.0


func _fx_parent() -> Node3D:
	var ent := get_parent()
	if ent != null and ent.get_parent() is Node3D:
		return ent.get_parent() as Node3D
	return self


func _ground() -> float:
	return ground_y if not is_nan(ground_y) else _last_ground


func _animate(delta: float) -> void:
	if body == null:
		return
	var root := global_transform
	var basis := root.basis.orthonormalized()
	if not _prev_root.is_finite():
		_prev_root = root.origin
	_vel = _vel.lerp((root.origin - _prev_root) / maxf(delta, 0.001), 1.0 - exp(-6.0 * delta))
	_prev_root = root.origin
	var p := action_progress()
	var w := action_weight(0.1, 0.2)
	var act := _action if p >= 0.0 else ""
	_hang = damp(_hang, 1.0 if hanging and not _dead else 0.0, 4.0, delta)
	if _was_hanging and not hanging and not _dead:
		# Dropped from the roof: a crashing landing.
		_hang = 0.0
		_fx("dust_cloud", Vector3.ZERO, 1.6)
		for i in 4:
			var a := TAU * float(i) / 4.0 + 0.4
			_fx("dust_cloud", Vector3(cos(a), 0, sin(a)) * 5.0, 1.0)
		_quake(root.origin, 0.6)
	_was_hanging = hanging
	if not hanging and _hang < 0.05 and act != "lunge":
		_last_ground = root.origin.y
	var speed := Vector2(_vel.x, _vel.z).length() if not hanging else 0.0
	_walk = damp(_walk, clampf(maxf(speed, move_speed) / 4.0, 0.0, 1.0), 6.0, delta)
	_gait += delta * clampf(maxf(speed, move_speed) / 3.2 + absf(turn_rate) * 0.4, 0.0, 2.4)

	# Idle twitches: a leg taps or shifts now and then, unsettlingly.
	_twitch_t -= delta
	if _twitch_t <= 0.0:
		_twitch_t = _rng.randf_range(0.25, 1.1)
		_twitch[_rng.randi() % _twitch.size()] = 1.0
	for i in _twitch.size():
		_twitch[i] = maxf(0.0, float(_twitch[i]) - delta * 3.5)

	var breathe := sin(_time * 1.7)
	var t_pos := Vector3(0, BODY_H + breathe * 0.05 - absf(sin(_gait * TAU * 2.0)) * 0.1 * _walk, 0)
	var t_rot := Vector3(0, 0, sin(_gait * TAU) * 0.025 * _walk)
	var fang_open := 0.1 + maxf(0.0, sin(_time * 2.3)) * 0.15
	var front_raise := 0.0
	var second_raise := 0.0
	var spread := 0.0
	var abd_t := Vector3(sin(_time * 1.1) * 0.03, sin(_time * 0.7) * 0.03, 0)
	var crouch := 0.0
	var stab := 0.0
	var eye_t := 1.0
	match act:
		"bite", "attack":
			var wind := keys(p, [[0, 0], [0.35, 1.0], [0.5, 0.2], [0.6, 0.0], [1, 0]])
			var strike := keys(p, [[0, 0], [0.4, 0.0], [0.55, 1.0], [0.7, 1.0], [1, 0]])
			t_pos += Vector3(0, 0.6 * wind - 0.8 * strike, 0.6 * wind - 1.6 * strike)
			t_rot.x += 0.25 * wind - 0.3 * strike
			fang_open = keys(p, [[0, 0.1], [0.4, 1.3], [0.55, -0.2], [0.75, 0.0], [1, 0.1]])
			front_raise = 0.5 * wind
			if p > IMPACT["bite"] and not _impact_done:
				_impact_done = true
				_fx("dust_cloud", Vector3(0, 0, -5.5), 0.7)
		"slam", "spikes":
			stab = keys(p, [[0, 0], [0.38, -1.0], [0.5, 1.0], [0.7, 1.0], [1, 0]])
			front_raise = maxf(0.0, -stab)
			t_rot.x += 0.35 * front_raise - 0.15 * maxf(0.0, stab)
			t_pos.y += 0.5 * front_raise - 0.4 * maxf(0.0, stab)
			fang_open = 0.6 * w
			if p > IMPACT["slam"] and not _impact_done:
				_impact_done = true
				for side: float in [-1.0, 1.0]:
					_fx("dust_cloud", Vector3(side * 3.0, 0, -6.5), 0.8)
				_quake(global_position, 0.3)
		"shoot":
			var aim := keys(p, [[0, 0], [0.3, 1.0], [0.6, 1.0], [1, 0]])
			abd_t += Vector3(-0.9 * aim, 0, 0)
			t_rot.x -= 0.25 * aim
			t_pos.y -= 0.4 * aim
			fang_open = 0.4
		"cast", "throw":
			var spit := keys(p, [[0, 0], [0.35, 1.0], [0.5, -0.6], [0.75, 0.0], [1, 0]])
			t_rot.x += 0.3 * maxf(0.0, spit) - 0.2 * maxf(0.0, -spit)
			t_pos.y += 0.4 * maxf(0.0, spit)
			fang_open = 1.2 * absf(spit)
			front_raise = 0.4 * maxf(0.0, spit)
		"roar", "howl":
			front_raise = w
			second_raise = 0.7 * w
			spread = w
			t_rot.x += 0.3 * w
			t_pos.y += 0.9 * w
			fang_open = lerpf(fang_open, 1.3 + sin(_time * 30.0) * 0.12, w)
			abd_t += Vector3(sin(_time * 14.0) * 0.06, 0, 0) * w
			eye_t = 1.0 + 1.2 * w
		"summon":
			front_raise = 0.4 * w
			t_rot.x += 0.2 * w
			abd_t += Vector3(0.25 * w + sin(_time * 18.0) * 0.06 * w, 0, 0)
			eye_t = 1.0 + 0.8 * w
			_sac_pop = clampf(_sac_pop + delta / 0.6 * (1.0 if p > 0.45 else 0.0), 0.0, 1.0)
			if p > 0.5 and not _impact_done:
				_impact_done = true
				for s in sacs:
					CreatureFx.play(_fx_parent(), "web", s.global_position, 0.7)
				_fx("venom", Vector3(0, 0, 3.5), 2.0)
		"lunge", "pounce":
			crouch = keys(p, [[0, 0], [0.3, 1.0], [0.42, -0.6], [0.65, -0.3], [0.75, 0.6], [1, 0]])
			t_rot.x -= 0.2 * crouch
			fang_open = maxf(fang_open, 1.0 * w)
			front_raise = maxf(0.0, -crouch) * 0.9
			if p > IMPACT["lunge"] and not _impact_done:
				_impact_done = true
				_fx("dust_cloud", Vector3(0, 0, -1.0), 1.4)
				_quake(global_position, 0.45)
		"hit":
			var s := sin(PI * p)
			t_rot += Vector3(0.18, 0, 0.1) * s
			t_pos.y += 0.3 * s
	t_pos.y -= crouch * 1.0
	if _dead:
		var f := clampf(_dead_t / 1.0, 0.0, 1.0)
		t_pos = Vector3(0, lerpf(BODY_H, 1.2, f), 0)
		t_rot = Vector3(0.1, 0, 0.12) * f
		fang_open = 0.5
		eye_t = 0.0
	# Hanging from the roof: legs drawn in, slowly turning on the line.
	if _hang > 0.01:
		t_rot = t_rot.lerp(Vector3(0.25, sin(_time * 0.6) * 0.5, sin(_time * 1.1) * 0.08), _hang)
		front_raise = lerpf(front_raise, 0.6, _hang)
	_body_pos = _body_pos.lerp(t_pos, 1.0 - exp(-12.0 * delta))
	_body_rot = _body_rot.lerp(t_rot, 1.0 - exp(-10.0 * delta))
	body.position = _body_pos
	body.rotation = _body_rot
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		pose(chelicerae[i], Vector3(-fang_open * 0.25, side * fang_open * 0.15, 0), 16.0, delta)
		pose(fangs[i], Vector3(-fang_open * 0.9, 0, side * fang_open * 0.35), 18.0, delta)
		pose(palps[i], Vector3(sin(_time * 5.0 + i * 2.5) * 0.25 - front_raise * 0.5, side * sin(_time * 3.1 + i) * 0.15, 0), 12.0, delta)
	pose(abdomen, abd_t, 7.0, delta)
	eyes.set_instance_shader_parameter(&"intensity", eye_t)
	# Egg sacs pulse; on a summon they burst and slowly grow back.
	if act != "summon":
		_sac_pop = maxf(0.0, _sac_pop - delta * 0.05)
	for i in sacs.size():
		var sac := sacs[i]
		var sz: float = sac.get_meta("size")
		var pulse := 1.0 + sin(_time * 2.4 + i * 1.7) * 0.06
		sac.scale = Vector3.ONE * sz * pulse * (1.0 - _sac_pop * 0.85)
	_pose_legs(delta, root, basis, front_raise, second_raise, spread, stab, crouch)
	_update_threads(delta, root)


func _pose_legs(delta: float, root: Transform3D, basis: Basis, front_raise: float, second_raise: float, spread: float, stab: float, crouch: float) -> void:
	var ground := _ground()
	var bt := root * Transform3D(Basis.from_euler(body.rotation), body.position)
	for li in legs.size():
		var leg: Dictionary = legs[li]
		var segs: Array = leg["segs"]
		var rest: Vector3 = leg["rest"]
		var side: float = leg["side"]
		var idx: int = leg["i"]
		var hip := bt * (leg["hip"] as Vector3)
		var ph := fposmod(_gait + (0.5 if int(leg["group"]) == 1 else 0.0), 1.0)
		var duty := 0.55
		var stride := 2.2 * minf(1.0, _walk * 2.0)
		var foot_l := rest
		var lift := 0.0
		if ph < duty:
			foot_l.z += stride * (ph / duty - 0.5)
		else:
			var s := (ph - duty) / (1.0 - duty)
			foot_l.z += stride * (0.5 - s)
			lift = sin(PI * s) * 1.2 * minf(1.0, _walk * 2.0)
		lift += float(_twitch[li]) * 0.6 * (1.0 - _walk)
		var down_now := lift < 0.05
		if down_now and not bool(_foot_was_down[li]) and _walk > 0.4 and li % 3 == 0:
			var fw := root * foot_l
			fw.y = ground
			CreatureFx.play(_fx_parent(), "dust_cloud", fw, 0.35)
		_foot_was_down[li] = down_now
		var foot := root * foot_l
		foot.y = ground + lift
		# Threat display / stabs: the front pairs rise above the body.
		var raise := 0.0
		if idx == 0:
			raise = front_raise
		elif idx == 1:
			raise = second_raise
		if raise > 0.0:
			var up_pos := bt * Vector3(side * (2.4 + spread * 1.5), 3.4 + spread * 0.6, -3.6 - float(idx) * 0.5 + spread * 0.8)
			foot = foot.lerp(up_pos, raise)
		if idx == 0 and stab > 0.0:
			var hit := root * Vector3(side * 3.0, 0, -6.5)
			hit.y = ground
			foot = foot.lerp(hit, stab)
		if crouch < 0.0:
			foot = foot.lerp(bt * (Vector3(rest.x * 0.75, -1.2, rest.z * 1.25)), -crouch * 0.6)
		if _hang > 0.01:
			foot = foot.lerp(bt * Vector3(side * 2.6, -0.8 + float(idx) * 0.15, rest.z * 0.45), _hang)
		if _dead:
			var curl := bt * Vector3(side * 1.4, -0.5, rest.z * 0.35)
			foot = foot.lerp(curl, clampf(_dead_t / 1.2, 0.0, 1.0))
		var la: float = leg["la"]
		var lb: float = leg["lb"]
		var lc: float = leg["lc"]
		var tip := foot + Vector3(0, lc * 0.92, 0) + (foot - hip).normalized() * 0.15
		var pole := (basis * Vector3(side, 2.2, 0)).normalized()
		var knee := ArachnidModel._ik_knee(hip, tip, la, lb, pole)
		DragonModel._orient(segs[0], hip, knee, basis.z)
		DragonModel._orient(segs[1], knee, tip, basis.z)
		DragonModel._orient(segs[2], tip, foot, basis.z)


## The dragline to the roof while hanging, and the web lash shot along its lane.
func _update_threads(delta: float, root: Transform3D) -> void:
	thread.visible = _hang > 0.05 and not _dead
	if thread.visible:
		var top := root.origin.y + 40.0 if is_nan(ceiling_y) else ceiling_y
		var from := root * Vector3(0, BODY_H + 1.5, 2.0)
		var span := maxf(0.5, top - from.y)
		thread.global_transform = Transform3D(Basis().scaled(Vector3(1, span, 1)), from + Vector3(0, span * 0.5, 0))
	if _web_t > -10.0:
		_web_t += delta
		var shoot := clampf(_web_t / 0.18, 0.0, 1.0)
		var fade := 1.0 - clampf((_web_t - 0.6) / 0.6, 0.0, 1.0)
		web_line.visible = _web_t > 0.0 and fade > 0.0 and not _dead
		if web_line.visible:
			var origin := abdomen.global_transform * Vector3(0, 0.5, 4.9)
			var end := origin.lerp(_web_to + Vector3(0, 0.3, 0), shoot)
			var d := end - origin
			if d.length() > 0.1:
				var y := d.normalized()
				var x := y.cross(Vector3.UP)
				if x.length_squared() < 1e-4:
					x = Vector3.RIGHT
				x = x.normalized()
				var z := x.cross(y)
				web_line.global_transform = Transform3D(Basis(x * fade, y * d.length(), z * fade), origin + d * 0.5)
		if _web_t > 1.4:
			_web_t = -100.0
			web_line.visible = false


func _fx(style: String, local_offset: Vector3, scale := 1.0) -> void:
	var pos := global_transform * local_offset
	pos.y = _ground() + 0.2
	CreatureFx.play(_fx_parent(), style, pos, scale)


func _quake(at: Vector3, strength: float) -> void:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null:
		return
	var d := cam.global_position.distance_to(at)
	var s := strength * clampf(1.0 - (d - 6.0) / 35.0, 0.0, 1.0)
	if s > 0.02 and Engine.get_main_loop() is SceneTree and (Engine.get_main_loop() as SceneTree).root.has_node("Events"):
		Events.screen_shake.emit(s)
