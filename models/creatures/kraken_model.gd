class_name KrakenModel
extends CreatureModel
## The Abyssal Kraken: a 12 m mantle (fluted fins at its crown, a ridged hide
## with pale suckered undersides and glowing photophores), two great slit-pupil
## eyes, a hooked beak ringed by a fleshy buccal crown, eight 19 m arms and two
## 26 m feeding tentacles with barbed clubs. Each arm is one smooth skinned
## tube posed every frame (SerpentChain display points), curling on the water
## when idle, rising behind the mantle when it surfaces, and crashing down on
## the telegraphed lanes. Ink clouds bloom where the boss's ink lands.
##
## The entity position is the mantle's anchor at the water line. Set
## `surfaced`, `engaged`, `water_y` and `arena_center`; one-shot actions:
## slam, sweep, throw (wreck grab), cast (ink), summon (whirlpool), roar, die.

var surfaced := false
var engaged := false
var water_y := 13.0
var arena_center := Vector3.INF

const ARMS := 8
const ARM_LEN := 19.0
const CLUB_LEN := 26.0
const ARM_BONES := 14

var mantle: Node3D
var arms: Array[SerpentChain] = []
var eyes: Array[MeshInstance3D] = []
var beak: Node3D
var held: MeshInstance3D
var _glow: Array[MeshInstance3D] = []
var _surf := 0.0
var _slam_target := Vector3.INF
var _slam_arm := 0
var _slammed := false
var _phase_power := 0.0
var _clouds: Array = []   # [node, age]
var _pending_ink: Array = []   # [pos, radius, time left]


func _init() -> void:
	dissolve_delay = 3.5
	dissolve_time = 3.0
	durations["slam"] = 1.8
	durations["sweep"] = 2.0
	durations["throw"] = 2.4
	durations["cast"] = 1.8
	durations["summon"] = 3.0
	durations["roar"] = 2.0


func _enter_tree() -> void:
	TelegraphFx.listen(_on_telegraph)


func _exit_tree() -> void:
	TelegraphFx.unlisten(_on_telegraph)
	for c: Array in _clouds:
		if is_instance_valid(c[0]):
			(c[0] as Node).queue_free()
	_clouds.clear()


func _on_telegraph(style: String, shape: String, pos: Vector3, dir: Vector3, size: Vector3, duration: float) -> void:
	if not is_inside_tree() or pos.distance_to(global_position) > 80.0:
		return
	match style:
		"slam":
			_slam_target = pos + Vector3(dir.x, 0, dir.z).normalized() * size.x * 0.55
			_slam_arm = _arm_towards(_slam_target)
			_slammed = false
		"ink":
			_pending_ink.append([pos, size.x, duration])
	var _u := shape


func _ember_extents() -> Vector3:
	return Vector3(4.0, 5.0, 4.0)


func _lod_size() -> float:
	return 30.0


func set_boss_state(is_engaged: bool, phase: int, dead: bool) -> void:
	engaged = is_engaged
	_phase_power = 0.0 if dead else float(phase - 1) / 2.0


func _build() -> void:
	var skin := CreatureSkin.smooth(Color(0.32, 0.07, 0.1), Color(0.78, 0.6, 0.55), {"wet": 0.8, "bump": 1.1,
		"bump_distance": 120.0, "accent": Color(0.12, 0.02, 0.05), "accent_mode": 3, "accent_amount": 0.65, "accent_scale": 0.35,
		"glow_mode": 1, "glow_color": Color(0.35, 0.85, 1.0), "glow_amount": 0.05, "glow_energy": 3.0, "glow_pulse": 0.5})
	var arm_skin := CreatureSkin.smooth(Color(0.34, 0.07, 0.1), Color(0.6, 0.32, 0.3), {"use_uv": true, "belly_mix": 0.35, "wet": 0.85, "bump": 1.3,
		"bump_distance": 100.0, "accent": Color(0.95, 0.82, 0.76), "accent_mode": 3, "accent_amount": 0.55, "accent_scale": 0.9,
		"glow_mode": 1, "glow_color": Color(0.35, 0.85, 1.0), "glow_amount": 0.04, "glow_energy": 2.5, "glow_pulse": 0.7})
	var fin := CreatureSkin.membrane(Color(0.42, 0.1, 0.14), {"backlight": 1.2, "accent": Color(0.15, 0.03, 0.06), "accent_mode": 1, "accent_amount": 0.5})
	var horn := CreatureSkin.keratin(Color(0.12, 0.1, 0.09), {"roughness": 0.35})
	var lip := CreatureSkin.mouth(Color(0.42, 0.1, 0.14))

	mantle = Node3D.new()
	mantle.name = "Mantle"
	mantle.top_level = true
	add_child(mantle)
	# The mantle: a long tapering hood standing up from the head, ridged along its back.
	var hood := OrganicMesh.profile("kraken_mantle", Vector3(0, 0.6, 0), Vector3(0, 12.5, 0.4),
		[[0.0, 3.4, 3.2, 0.0], [0.12, 4.1, 3.8, 0.1], [0.38, 4.0, 3.6, 0.35], [0.62, 3.3, 3.0, 0.3],
		[0.82, 2.2, 2.0, 0.1], [0.95, 1.1, 1.0, 0.0], [1.0, 0.2, 0.2, 0.0]], 28, 22, Vector3.BACK)
	ModelKit.part(mantle, hood, skin)
	# Lateral fins at the crown of the mantle.
	for side: float in [-1.0, 1.0]:
		var pts := PackedVector2Array([Vector2(0, 0), Vector2(2.8, 1.2), Vector2(4.2, 3.6), Vector2(3.0, 5.6), Vector2(0.8, 6.4), Vector2(0, 5.0)])
		for i in pts.size():
			pts[i].x *= side
		ModelKit.part(mantle, OrganicMesh.membrane("kraken_fin_%d" % int(side), pts, 0.6, 0.12), fin, Vector3(side * 1.6, 6.4, 0.6), Vector3(0, side * 12.0, 0))
	# Dorsal ridges and photophores.
	for i in 7:
		var y := 2.5 + i * 1.35
		ModelKit.part(mantle, OrganicMesh.blob("kraken_ridge", Vector3(0.45, 0.6, 1.1), 0.3, 4, 10), skin, Vector3(0, y, 3.5 - i * 0.28), Vector3(-20, 0, 0))
	var photo := ModelKit.glow(Color(0.35, 0.9, 1.0), 4.0, 0.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 71
	for i in 26:
		var a := rng.randf() * TAU
		var y := rng.randf_range(1.0, 9.5)
		var r := 3.9 - maxf(0.0, y - 5.0) * 0.3
		_glow.append(ModelKit.part(mantle, ModelKit.sphere(0.12, 6), photo, Vector3(cos(a) * r, y, sin(a) * r * 0.92)))
	# Head: eyes on either side above the arm crown.
	var head := OrganicMesh.blob("kraken_head", Vector3(3.3, 2.1, 3.0), 0.12, 9, 16)
	ModelKit.part(mantle, head, skin, Vector3(0, 0.2, 0))
	for side: float in [-1.0, 1.0]:
		ModelKit.part(mantle, OrganicMesh.blob("kraken_lid", Vector3(1.0, 0.9, 0.9), 0.15, 12, 12), skin, Vector3(side * 2.75, 0.75, -0.9))
		var eye := ModelKit.part(mantle, ModelKit.sphere(0.72, 14), CreatureSkin.eye(Color(1.0, 0.72, 0.18), 5.0, 0.2), Vector3(side * 3.15, 0.75, -1.0), Vector3.ZERO, Vector3(0.7, 1.0, 1.0))
		eyes.append(eye)
		ModelKit.part(mantle, ModelKit.box(Vector3(0.1, 0.95, 0.22)), ModelKit.mat(Color(0.01, 0.01, 0.01), AsciiMaterialId.SOLID, 0.2), Vector3(side * 3.62, 0.75, -1.05))
	# Beak in a fleshy crown below the head.
	beak = ModelKit.joint(mantle, "Beak", Vector3(0, -1.6, 0))
	for i in 10:
		var a := TAU * i / 10.0
		ModelKit.part(beak, OrganicMesh.blob("kraken_lip", Vector3(0.7, 0.5, 0.9), 0.2, 5, 10), lip, Vector3(cos(a) * 1.3, 0, sin(a) * 1.3), Vector3(0, -rad_to_deg(a), 0))
	for side: float in [-1.0, 1.0]:
		var bm := OrganicMesh.bezier("kraken_beak_%d" % int(side), Vector3.ZERO, Vector3(side * 0.5, -0.9, 0.3), Vector3(side * 0.15, -1.6, -0.6), 0.75, 0.05, 10, 10, 0.6)
		ModelKit.part(beak, bm, horn, Vector3(side * 0.35, 0.2, 0))
	# Arms and the two feeding tentacles.
	var prof := [[0.0, 0.95, 0.85], [0.1, 0.9, 0.8], [0.5, 0.55, 0.5], [0.85, 0.24, 0.22], [1.0, 0.06, 0.06]]
	var club_prof := [[0.0, 0.6, 0.55], [0.5, 0.32, 0.3], [0.78, 0.22, 0.2], [0.86, 0.55, 0.42], [0.95, 0.4, 0.3], [1.0, 0.05, 0.05]]
	var arm_mesh := OrganicMesh.skinned_tube("kraken_arm", ARM_LEN, ARM_BONES, prof, 56, 14)
	var club_mesh := OrganicMesh.skinned_tube("kraken_club", CLUB_LEN, ARM_BONES + 4, club_prof, 64, 12)
	for i in ARMS + 2:
		var club := i >= ARMS
		var chain := SerpentChain.new().setup(club_mesh if club else arm_mesh, arm_skin, ARM_BONES + (4 if club else 0), CLUB_LEN if club else ARM_LEN, 60.0)
		chain.name = "Arm%d" % i
		add_child(chain)
		arms.append(chain)
		if club:
			# Barbed hooks on the club.
			var hold := Node3D.new()
			chain.attach(chain.bones - 3, hold)
			for h in 5:
				var a := TAU * h / 5.0
				var hm := OrganicMesh.bezier("kraken_hook", Vector3.ZERO, Vector3(0, 0.25, 0.1), Vector3(0, 0.35, 0.4), 0.08, 0.01, 5, 5)
				ModelKit.part(hold, hm, horn, Vector3(cos(a) * 0.45, sin(a) * 0.45, 0), Vector3(0, 0, rad_to_deg(a) - 90.0))
	# Wreckage the grabbing arm carries (a broken spar with a hanging plank).
	held = ModelKit.part(self, ModelKit.cylinder(0.25, 0.32, 5.0, 8), ModelKit.mat(Color(0.33, 0.25, 0.18), AsciiMaterialId.SOLID, 0.9))
	held.top_level = true
	held.visible = false


func _arm_anchor(i: int, base: Vector3, yaw_b: Basis) -> Vector3:
	var a := TAU * (float(i) + 0.5) / ARMS if i < ARMS else (-0.35 if i == ARMS else 0.35)
	var r := 2.2 if i < ARMS else 1.4
	return base + yaw_b * Vector3(sin(a) * r, -1.8, -cos(a) * r)


func _arm_dir(i: int, yaw_b: Basis) -> Vector3:
	var a := TAU * (float(i) + 0.5) / ARMS if i < ARMS else (-0.25 if i == ARMS else 0.25)
	return yaw_b * Vector3(sin(a), 0, -cos(a))


func _arm_towards(p: Vector3) -> int:
	var best := 0
	var best_d := -INF
	var yb := Basis(Vector3.UP, global_rotation.y)
	var to := p - global_position
	to.y = 0.0
	to = to.normalized()
	for i in ARMS:
		var d := _arm_dir(i, yb).dot(to)
		if d > best_d:
			best_d = d
			best = i
	return best


func _animate(delta: float) -> void:
	if mantle == null:
		return
	var base := global_position
	var yb := Basis(Vector3.UP, global_rotation.y)
	var p := action_progress()
	var w := action_weight(0.12, 0.25)
	_surf = damp(_surf, 1.0 if (surfaced and not _dead) else 0.0, 1.8, delta)
	var sink := clampf(_dead_t / 6.0, 0.0, 1.0) if _dead else 0.0
	# The mantle: below the waves when submerged, reared up out of the water when surfaced.
	var rise := lerpf(-9.5, 1.6, _surf) - sink * 8.0
	var lean := lerpf(0.05, -0.32, _surf)
	var bob := sin(_time * 0.9) * 0.35
	var shake := 0.0
	if p >= 0.0 and not _dead:
		match _action:
			"roar", "summon":
				lean -= 0.2 * w
				shake = 0.08 * w
			"cast":
				rise -= 3.0 * w
			"slam":
				lean += 0.15 * w
	var mpos := Vector3(base.x, water_y + rise + bob, base.z)
	if shake > 0.0:
		mpos += Vector3(sin(_time * 29.0), 0, cos(_time * 25.0)) * shake * 3.0
	mantle.global_transform = Transform3D(yb * Basis(Vector3.RIGHT, lean), mpos)
	beak.rotation.x = sin(_time * 1.3) * 0.05 + (0.25 * w if _action in ["roar", "summon"] else 0.0)
	for e in eyes:
		e.set_instance_shader_parameter(&"intensity", 0.0 if _dead else 1.0 + _phase_power * 0.8)
	for g in _glow:
		g.set_instance_shader_parameter(&"intensity", 0.0 if _dead else 0.6 + _phase_power + 0.4 * sin(_time * 2.0 + g.position.y))
	var crown := mantle.global_transform * Vector3(0, -1.2, 0)
	for i in arms.size():
		_pose_arm(i, crown, yb, p, w, delta, sink)
	_update_ink(delta)


## Arms: curling out on the water (idle), raised and writhing behind the mantle
## (surfaced), one crashing down on the slam lane, all whirling in the whirlpool.
func _pose_arm(i: int, crown: Vector3, yb: Basis, p: float, w: float, delta: float, sink: float) -> void:
	var chain := arms[i]
	var n := chain.bones
	var anchor := _arm_anchor(i, crown, yb) + Vector3(0, 1.8, 0)
	var dir := _arm_dir(i, yb)
	var club := i >= ARMS
	var length := chain.length
	var ph := float(i) * 1.7
	var whirl := 0.0
	if _action == "summon" and p >= 0.0:
		whirl = w
	var side := Vector3(-dir.z, 0, dir.x)
	var raise := _surf * (0.6 if not club else 0.9)
	for j in n:
		var t := float(j) / (n - 1)
		var out := dir * length * t * lerpf(0.82, 0.55, raise)
		var curl := sin(_time * 0.8 + ph + t * 5.0) * (1.0 + 2.5 * t)
		var up := lerpf(water_y - 0.6 - anchor.y + sin(_time * 1.1 + ph + t * 6.0) * 0.6 * t, 9.0 * sin(PI * t * 0.9), raise)
		var q := anchor + out + side * curl * (0.5 + 0.5 * raise) + Vector3.UP * up
		if t < 0.1:
			q = anchor + dir * length * t * 0.5
		if whirl > 0.0:
			var a := _time * 2.5 + t * 2.2
			var spin := Vector3(cos(a + ph), 0, sin(a + ph)) * length * t * 0.7
			q = q.lerp(anchor + spin + Vector3(0, water_y - anchor.y - 0.4, 0), whirl * t)
		q.y -= sink * 6.0
		chain.display[j] = q
	# The slam: the chosen arm arcs high and crashes onto the lane.
	if (_action == "slam" and p >= 0.0 and i == _slam_arm and _slam_target.is_finite()):
		var lift := keys(p, [[0, 0], [0.45, 1.0], [0.62, 1.05], [0.72, 0.0], [1, 0]])
		var reach := keys(p, [[0, 0.3], [0.5, 0.75], [0.72, 1.0], [1, 1.0]])
		var start := chain.display[1]
		var target := _slam_target
		target.y = arena_center.y + 0.3 if arena_center.is_finite() else water_y + 1.0
		var end := start.lerp(target, reach) + Vector3.UP * lift * 9.0
		var ctrl := start.lerp(target, 0.4) + Vector3.UP * (6.0 + lift * 12.0)
		for j in range(1, n):
			var t := float(j) / (n - 1)
			var a := start.lerp(ctrl, t)
			var b := ctrl.lerp(end, t)
			chain.display[j] = chain.display[j].lerp(a.lerp(b, t), w)
		if p > 0.7 and not _slammed:
			_slammed = true
			if particles_enabled:
				CreatureFx.play(_fx_parent(), "splash", target, 2.4)
	# The wreck grab: a feeding tentacle lifts its prize overhead.
	if i == ARMS and _action == "throw" and p >= 0.0:
		var top := crown + Vector3(0, 14.0, 0) + dir * 4.0
		for j in range(1, n):
			var t := float(j) / (n - 1)
			chain.display[j] = chain.display[j].lerp(chain.display[0].lerp(top, t) + side * sin(t * PI) * 3.0, w * smoothstep(0.0, 0.6, t))
		held.visible = w > 0.2 and p < 0.55
		held.global_transform = Transform3D(chain.frame(n - 2), chain.joint(n - 2))
	elif i == ARMS:
		held.visible = false
	chain.apply()
	var _u := delta


func _fx_parent() -> Node3D:
	var ent := get_parent()
	if ent != null and ent.get_parent() is Node3D:
		return ent.get_parent() as Node3D
	return self


# --- Ink -----------------------------------------------------------------------------------

const INK := preload("res://models/creatures/ink_cloud.gdshader")
static var _ink_mesh: SphereMesh
static var _ink_mat: ShaderMaterial


## A billowing cloud of ink where the ink lands: inside it the world goes black (it is
## drawn from inside too), so a player caught in it is blinded until it thins out.
func _update_ink(delta: float) -> void:
	for k in range(_pending_ink.size() - 1, -1, -1):
		var e: Array = _pending_ink[k]
		e[2] = float(e[2]) - delta
		if float(e[2]) <= 0.0:
			_pending_ink.remove_at(k)
			_spawn_ink(e[0], float(e[1]))
	for k in range(_clouds.size() - 1, -1, -1):
		var c: Array = _clouds[k]
		var node := c[0] as MeshInstance3D
		c[1] = float(c[1]) + delta
		if not is_instance_valid(node) or float(c[1]) > 8.0:
			if is_instance_valid(node):
				node.queue_free()
			_clouds.remove_at(k)
			continue
		var age := float(c[1])
		var r := float(c[2]) * lerpf(0.4, 1.0, smoothstep(0.0, 0.8, age))
		node.scale = Vector3(r * 1.15, r * 0.75, r * 1.15)
		node.set_instance_shader_parameter(&"density", (1.0 - smoothstep(5.0, 8.0, age)) * smoothstep(0.0, 0.3, age))


func _spawn_ink(pos: Vector3, radius: float) -> void:
	if _ink_mesh == null:
		_ink_mesh = SphereMesh.new()
		_ink_mesh.radius = 1.0
		_ink_mesh.height = 2.0
		_ink_mesh.radial_segments = 24
		_ink_mesh.rings = 12
		_ink_mat = ShaderMaterial.new()
		_ink_mat.shader = INK
	var mi := MeshInstance3D.new()
	mi.mesh = _ink_mesh
	mi.material_override = _ink_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	_fx_parent().add_child(mi)
	mi.global_position = pos + Vector3(0, 1.2, 0)
	mi.scale = Vector3.ONE * radius * 0.4
	mi.set_instance_shader_parameter(&"density", 0.0)
	_clouds.append([mi, 0.0, radius])
	if particles_enabled:
		CreatureFx.play(_fx_parent(), "mud", pos, 2.0)
