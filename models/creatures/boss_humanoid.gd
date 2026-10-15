class_name BossHumanoid
extends HumanoidModel
## Base for the bespoke humanoid boss models (the Warden, the Mountain King,
## Hades, Old Mother Mire). The HumanoidModel underneath supplies the rig and
## the procedural animator (planted feet, weighty attacks, two-handed grips,
## cloak simulation, death); the body it would draw is hidden and every
## visible surface is the boss's own sculpted armour, flesh, stone and cloth,
## authored in the rig's rest space ("body units": a 1.8 m human) and bound to
## its bones. Parts on one bone merge into a mesh per material (BossKit), so a
## boss of hundreds of parts draws in a few dozen calls.
##
## The boss entity reports its state every frame with set_boss_state():
##   dormant (not engaged, standing still): a brooding idle pose (kneeling
##   over the planted blade, leaning on the hammer...), and the
##   phase (1..3): `power` ramps up (runes, flames, glow) and subclasses
##   transform in _on_boss_phase().

var dormant := false
var boss_phase := 1
var boss_engaged := false
## Draw the HumanoidModel's own skinned body (off: bespoke parts only).
var show_body := false

var _atts := {}        # bone index -> BoneAttachment3D
var _asms := {}        # bone index -> BossKit.Assembly (during the build)
var _dormant_w := 0.0
var _power := 0.0
var _power_target := 0.0
var _phase_t := 9.0
var _engage_t := 9.0
var _fx_nodes: Array[Node3D] = []
var _lights: Array[OmniLight3D] = []
var _light_energy: Array[float] = []


func _init(style_dict := {}) -> void:
	super(style_dict)
	dissolve_delay = 3.2
	dissolve_time = 2.6
	durations["roar"] = 1.8
	durations["summon"] = 1.6


## Key prefix for cached meshes (one per boss kind / style).
func _kit_key() -> String:
	return "boss_%s" % get_script().get_global_name()


func _build() -> void:
	super._build()
	mesh_instance.visible = show_body
	_dress()
	for bone: int in _asms:
		var asm: BossKit.Assembly = _asms[bone]
		var moved := asm.transformed(Transform3D(Basis.IDENTITY, -_rest[bone]))
		BossKit.instance(attachment(bone), "%s_b%d" % [_kit_key(), bone], moved)
	_asms.clear()
	_after_dress()


## Override: add parts with part(bone).put(...) in rest space, skinned cloth, FX.
func _dress() -> void:
	pass


## Override: anything that needs the built parts (pivots, lights).
func _after_dress() -> void:
	pass


## The assembly for parts that follow `bone` (rest-space coordinates).
func part(bone: int) -> BossKit.Assembly:
	if not _asms.has(bone):
		_asms[bone] = BossKit.assembly()
	return _asms[bone]


func attachment(bone: int) -> BoneAttachment3D:
	if _atts.has(bone):
		return _atts[bone]
	var a := BoneAttachment3D.new()
	a.name = "B%d" % bone
	skeleton.add_child(a)
	a.bone_idx = bone
	_atts[bone] = a
	return a


## A node following `bone`, placed at a rest-space point, in body units.
func pivot(bone: int, rest_point: Vector3, node_name := "Pivot") -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = rest_point - _rest[bone]
	attachment(bone).add_child(n)
	return n


## A node following `bone` at a rest-space point whose children are in world
## units (particles, lights): it cancels the model's scale.
func fx_point(bone: int, rest_point: Vector3) -> Node3D:
	var n := pivot(bone, rest_point, "Fx")
	n.scale = Vector3.ONE / _s
	_fx_nodes.append(n)
	return n


## Bake an assembly under a pivot node (parts relative to the pivot).
func bake_into(node: Node3D, key: String, asm: BossKit.Assembly) -> Array[MeshInstance3D]:
	return BossKit.instance(node, "%s_%s" % [_kit_key(), key], asm)


## A skinned mesh bound to this rig (cloaks, robes).
func skinned(mesh: ArrayMesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Cloth"
	mi.mesh = mesh
	mi.material_override = mat
	mi.skin = body["skin"]
	skeleton.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.custom_aabb = AABB(Vector3(-1.6, -0.4, -1.6), Vector3(3.2, 3.0, 3.2))
	return mi


func add_light(parent: Node3D, pos: Vector3, color: Color, energy: float, radius: float) -> OmniLight3D:
	var l := BossKit.light(parent, pos, color, energy, radius)
	_lights.append(l)
	_light_energy.append(energy)
	return l


func _collect(node: Node) -> void:
	super._collect(node)
	if node == self:
		_collect_boss(self)


func _collect_boss(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D and not c is GPUParticles3D:
			var m := (c as GeometryInstance3D).material_override as ShaderMaterial
			if m != null and m.shader == BossKit.SURFACE and not _geoms.has(c):
				_geoms.append(c)
		_collect_boss(c)


# --- Boss state -------------------------------------------------------------------------

func set_boss_state(engaged_now: bool, phase_now: int, _is_dead := false) -> void:
	if engaged_now and not boss_engaged:
		_engage_t = 0.0
		_on_boss_engaged()
	boss_engaged = engaged_now
	dormant = not engaged_now
	if phase_now != boss_phase:
		var old := boss_phase
		boss_phase = phase_now
		_phase_t = 0.0
		if phase_now > old:
			_on_boss_phase(phase_now)
	_power_target = clampf((boss_phase - 1) * 0.5, 0.0, 1.0)


func _on_boss_engaged() -> void:
	pass


func _on_boss_phase(_new_phase: int) -> void:
	pass


func set_dead(is_dead: bool) -> void:
	var was := _dead
	super.set_dead(is_dead)
	if is_dead and not was:
		_on_boss_death()


func _on_boss_death() -> void:
	pass


func _animate(delta: float) -> void:
	super._animate(delta)
	_phase_t += delta
	_engage_t += delta
	var p := move_toward(_power, _power_target + (0.6 if _phase_t < 2.0 else 0.0) * (1.0 - _phase_t / 2.0), delta * 0.8)
	if absf(p - _power) > 0.002:
		_power = p
		_set_param(&"power", _power)
	_tick_boss(delta)
	var fade := 1.0 - _dissolve if _dead else 1.0
	for i in _lights.size():
		if is_instance_valid(_lights[i]):
			_lights[i].visible = _near or _cam_dist < 60.0
			_lights[i].light_energy = _light_energy[i] * fade * (1.0 + _power * 0.5)


## Override: per-frame boss animation (pendulums, flames, orbiting parts).
func _tick_boss(_delta: float) -> void:
	pass


func _pose(dt: float) -> void:
	super._pose(dt)
	var want := 1.0 if (dormant and not _dead and _action == "" and _speed < 0.3) else 0.0
	_dormant_w = damp(_dormant_w, want, 2.5 if want > _dormant_w else 4.0, dt)
	if _dormant_w > 0.01:
		_pose_dormant(_tgt, _dormant_w)


## Override: the brooding idle pose blended by w (0..1). Default: head bowed.
func _pose_dormant(t: PackedVector3Array, w: float) -> void:
	t[R.HEAD] += Vector3(0.35, 0, 0) * w
	t[R.NECK] += Vector3(0.15, 0, 0) * w


## Hand placements applied after the animator: {side: [wrist target (rest space,
## relative to the hips' current position), item direction, finger direction, weight]}.
## Subclasses fill this in _pose_dormant (or any pose) for exact two-hand grips
## such as resting on a planted blade or hammer.
var hand_goals := {}


func _apply(dt: float) -> void:
	super._apply(dt)
	if hand_goals.is_empty() or _dead:
		hand_goals.clear()
		return
	for side: int in hand_goals:
		var g: Array = hand_goals[side]
		_reach(side, _hips_pos - _rest[R.HIPS] + (g[0] as Vector3), g[1], g[2], float(g[3]))
	hand_goals.clear()


## Two-bone IK for one arm towards `wrist` (skeleton space, body units), then
## turn the hand so the held item points along `item_dir` with the fingers
## along `finger_dir`. Blended by w over the animated pose.
func _reach(side: int, wrist: Vector3, item_dir: Vector3, finger_dir: Vector3, w: float) -> void:
	if w <= 0.001:
		return
	var o := 0 if side == 0 else 5
	var clav := _g[R.CHEST] * Transform3D(Basis(_q[R.CLAV_L + o]), _local[R.CLAV_L + o])
	var sh := clav * Transform3D(Basis(_q[R.UARM_L + o]), _local[R.UARM_L + o])
	var s := sh.origin
	var l1 := _local[R.FARM_L + o].length()
	var l2 := _local[R.HAND_L + o].length()
	var to := wrist - s
	var d := clampf(to.length(), absf(l1 - l2) + 0.01, (l1 + l2) * 0.999)
	var dir := to.normalized()
	# Elbows point back and out.
	var sg := -1.0 if side == 0 else 1.0
	var pole := Vector3(sg * 0.6, -0.3, 1.0)
	var perp := (pole - dir * pole.dot(dir)).normalized()
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(0.0, l1 * l1 - a * a))
	var elbow := s + dir * a + perp * h
	var wr := s + dir * d
	var rest1 := _local[R.FARM_L + o].normalized()
	var rest2 := _local[R.HAND_L + o].normalized()
	var b1 := Basis(Quaternion(rest1, (elbow - s).normalized()))
	var b2 := Basis(Quaternion(b1 * rest2, (wr - elbow).normalized())) * b1
	var q1 := (clav.basis.inverse() * b1).get_rotation_quaternion()
	var q2 := (b1.inverse() * b2).get_rotation_quaternion()
	# Hand: the grip's item axis is the hand's -Z; its fingers run along -Y.
	var z := -item_dir.normalized()
	var y := -(finger_dir - z * finger_dir.dot(z)).normalized()
	var x := y.cross(z).normalized()
	var hb := Basis(x, y, z)
	var q3 := (b2.inverse() * hb).get_rotation_quaternion()
	_q[R.UARM_L + o] = _q[R.UARM_L + o].slerp(q1, w)
	_q[R.FARM_L + o] = _q[R.FARM_L + o].slerp(q2, w)
	_q[R.HAND_L + o] = _q[R.HAND_L + o].slerp(q3, w)
	for i in [R.UARM_L + o, R.FARM_L + o, R.HAND_L + o]:
		skeleton.set_bone_pose_rotation(i, _q[i])


# --- Geometry helpers (rest space, body units) ---------------------------------------------

## Transform placing local +Y along from -> to, origin at `from`, with a roll.
static func along(from: Vector3, to: Vector3, roll := 0.0) -> Transform3D:
	var d := to - from
	var len := d.length()
	if len < 1e-5:
		return Transform3D(Basis.IDENTITY, from)
	var y := d / len
	var ref := Vector3.BACK if absf(y.dot(Vector3.BACK)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	var b := Basis(x, y, z)
	if roll != 0.0:
		b = b * Basis(Vector3.UP, roll)
	return Transform3D(b, from)


## A tube of armour (rerebrace, vambrace, greave, cuisse): rolled rims at both
## ends, slight taper. Radii r0 at `from`, r1 at `to`; sx/sz squash it.
func plate_tube(asm: BossKit.Assembly, mat: Material, key: String, from: Vector3, to: Vector3, r0: float, r1: float,
		tint: Color, sx := 1.0, sz := 1.0, rim := 1.12) -> void:
	var len := from.distance_to(to)
	var prof := PackedVector2Array([Vector2(r0 * rim, 0.0), Vector2(r0 * rim, len * 0.035), Vector2(r0, len * 0.07),
		Vector2(lerpf(r0, r1, 0.5) * 1.03, len * 0.5), Vector2(r1, len * 0.93), Vector2(r1 * rim, len * 0.965), Vector2(r1 * rim, len)])
	var m := BossKit.lathe("%s_tube_%s" % [_kit_key(), key], prof, 18, sx, sz)
	asm.add(m, mat, along(from, to), tint)


## A layered pauldron over a shoulder: `layers` lames of decreasing size
## stepping down the arm, the top one a big dome; optional trim bands along
## each lower edge. side: -1 left, +1 right.
func pauldron(asm: BossKit.Assembly, mat: Material, key: String, shoulder: Vector3, side: float, size: float, layers: int,
		tint: Color, trim := Color(1, 1, 1), trim_mat: Material = null) -> void:
	var k := _kit_key()
	var outward := Basis(Vector3.UP, -side * PI * 0.5)
	var dome := BossKit.shell("%s_pauldron_%s" % [k, key], Vector3(size, size * 0.8, size * 1.05), -115, 115, 0, 88, size * 0.08, 16, 9)
	var b := Basis(Vector3.FORWARD, side * 0.32) * outward
	var c := shoulder + Vector3(side * size * 0.15, size * 0.12, 0)
	asm.add(dome, mat, Transform3D(b, c), tint)
	if trim_mat != null:
		var band := BossKit.shell("%s_ptrim_%s" % [k, key], Vector3(size, size * 0.8, size * 1.05) * 1.012, -115, 115, 83, 88, size * 0.03, 16, 1)
		asm.add(band, trim_mat, Transform3D(b, c), trim)
	for i in range(1, layers):
		var s := size * (1.0 - i * 0.12)
		var lame := BossKit.shell("%s_lame_%s_%d" % [k, key, i], Vector3(s * 1.0, s * 0.62, s * 1.02), -82, 82, 48, 90, s * 0.06, 14, 4)
		var p := shoulder + Vector3(side * (size * 0.24 + i * size * 0.07), -i * size * 0.34 + size * 0.06, 0)
		var lb := Basis(Vector3.FORWARD, side * (0.45 + i * 0.1)) * outward
		asm.add(lame, mat, Transform3D(lb, p), tint.darkened(0.1 * (i % 2)))


## An armoured hand: cuff, back plate, four segmented fingers (on the finger
## bone so they curl with the grip) and a thumb.
func gauntlet(mat: Material, key: String, side: float, hand_r: float, tint: Color) -> void:
	var o := 0 if side < 0.0 else 5
	var wrist := _rest[R.HAND_L + o]
	var knuck := _rest[R.FING_L + o]
	var hand := part(R.HAND_L + o)
	var cuff := PackedVector2Array([Vector2(hand_r * 0.95, 0.0), Vector2(hand_r * 1.25, hand_r * 1.0), Vector2(hand_r * 1.45, hand_r * 1.6), Vector2(hand_r * 1.55, hand_r * 1.75)])
	hand.add(BossKit.lathe("%s_cuff_%s" % [_kit_key(), key], cuff, 14), mat, along(wrist + Vector3(0, 0.0, 0), wrist + Vector3(0, hand_r * 1.6, 0)), tint)
	# Back of the hand (faces outward: -X for the left hand, +X for the right).
	var back := BossKit.shell("%s_handback_%s" % [_kit_key(), key], Vector3(hand_r * 0.55, hand_r * 1.2, hand_r * 0.9), -80, 80, 30, 150, hand_r * 0.12, 8, 6)
	var mid := (wrist + knuck) * 0.5
	hand.add(back, mat, Transform3D(Basis(Vector3.UP, side * PI * 0.5), mid + Vector3(side * hand_r * 0.1, 0, 0)), tint)
	hand.add(OrganicMesh.blob("%s_palm_%s" % [_kit_key(), key], Vector3(hand_r * 0.45, hand_r * 1.0, hand_r * 0.8), 0.05, 3, 10), mat, Transform3D(Basis.IDENTITY, mid), tint.darkened(0.25))
	# Thumb.
	var th0 := wrist + Vector3(-side * 0.005, -hand_r * 0.6, -hand_r * 0.7)
	var thumb := OrganicMesh.bezier("%s_thumb_%s" % [_kit_key(), key], Vector3.ZERO, Vector3(0, -hand_r * 0.6, -hand_r * 0.35), Vector3(0, -hand_r * 1.2, -hand_r * 0.2), hand_r * 0.26, hand_r * 0.18, 5, 7)
	hand.add(thumb, mat, Transform3D(Basis.IDENTITY, th0), tint)
	# Fingers on the finger bone.
	var fing := part(R.FING_L + o)
	for f in 4:
		var z := lerpf(-hand_r * 0.6, hand_r * 0.6, f / 3.0)
		var l := hand_r * (1.3 if f in [1, 2] else 1.1)
		var fm := OrganicMesh.bezier("%s_finger_%s_%d" % [_kit_key(), key, f], Vector3.ZERO, Vector3(0, -l * 0.5, 0), Vector3(0, -l, -l * 0.08), hand_r * 0.22, hand_r * 0.17, 5, 7)
		fing.add(fm, mat, Transform3D(Basis.IDENTITY, knuck + Vector3(0, hand_r * 0.25, z)), tint)
		# Knuckle plates.
		fing.add(OrganicMesh.blob("%s_knuckle_%s" % [_kit_key(), key], Vector3(hand_r * 0.24, hand_r * 0.22, hand_r * 0.22), 0.05, 5, 8), mat,
			Transform3D(Basis.IDENTITY, knuck + Vector3(side * hand_r * 0.08, hand_r * 0.1, z)), tint)
