class_name RyftModel
extends CreatureModel
## Base for the floating Ryft bosses (the Prism Sentinel, the Void Sovereign):
## rigid parts on pivot nodes, merged per material (BossKit), hovering and
## animated procedurally; the same boss-state hooks as BossHumanoid (brooding
## idle, phase power, death).

var boss_phase := 1
var boss_engaged := false
var dormant := false
var _power := 0.0
var _power_target := 0.0
var _phase_t := 9.0
var _lights: Array[OmniLight3D] = []
var _light_energy: Array[float] = []
var _hover := 0.0
var _break := 0.0
## Motion read from the node itself (works on clients too): velocity in the
## model's own frame (-Z forward) and yaw rate, smoothed.
var _vel_local := Vector3.ZERO
var _yaw_rate := 0.0
var _prev_pos := Vector3.INF
var _prev_yaw := 0.0
## Body lean from motion: x pitches forward into travel, z banks into turns.
var _lean := Vector3.ZERO
## Random tumble axis for the death collapse.
var _tumble := Vector3(0.7, 0.0, 0.4)


func _init() -> void:
	dissolve_delay = 2.6
	dissolve_time = 2.4
	durations["cast"] = 1.2
	durations["slam"] = 1.4
	durations["summon"] = 1.8
	durations["roar"] = 2.0
	durations["sweep"] = 1.3
	durations["teleport"] = 0.9
	# Bespoke Ryft moves (the bosses pass exact lengths; these are defaults).
	for a: Array in [["thrust", 2.0], ["nova", 2.2], ["swipe", 1.5], ["beam", 2.6], ["volley", 2.4], ["special1", 2.5],
			["special2", 4.0], ["charge", 1.8], ["spin", 2.2], ["phase", 2.0], ["lash", 1.6], ["rift", 2.3], ["pull", 2.0],
			["starfall", 2.6], ["eclipse", 3.6], ["hit", 0.5], ["die", 3.0]]:
		durations[a[0]] = a[1]


func _kit_key() -> String:
	return "ryft_%s" % get_script().get_global_name()


func node(parent: Node3D, pos: Vector3, node_name := "Pivot") -> Node3D:
	return ModelKit.joint(parent, node_name, pos)


func bake(parent: Node3D, key: String, asm: BossKit.Assembly) -> void:
	BossKit.instance(parent, "%s_%s" % [_kit_key(), key], asm)


func add_light(parent: Node3D, pos: Vector3, color: Color, energy: float, radius: float) -> OmniLight3D:
	var l := BossKit.light(parent, pos, color, energy, radius)
	_lights.append(l)
	_light_energy.append(energy)
	return l


func _collect(n: Node) -> void:
	super._collect(n)
	if n == self:
		_collect_boss(self)


func _collect_boss(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D and not c is GPUParticles3D:
			var m := (c as GeometryInstance3D).material_override as ShaderMaterial
			if m != null and m.shader == BossKit.SURFACE and not _geoms.has(c):
				_geoms.append(c)
		_collect_boss(c)


func set_boss_state(engaged_now: bool, phase_now: int, _is_dead := false) -> void:
	boss_engaged = engaged_now
	dormant = not engaged_now
	if phase_now != boss_phase:
		var old := boss_phase
		boss_phase = phase_now
		_phase_t = 0.0
		if phase_now > old:
			_on_boss_phase(phase_now)
	_power_target = clampf((boss_phase - 1) * 0.5, 0.0, 1.0)


func _on_boss_phase(_new_phase: int) -> void:
	pass


func _animate(delta: float) -> void:
	_phase_t += delta
	var p := move_toward(_power, _power_target + (0.7 if _phase_t < 2.0 else 0.0) * (1.0 - _phase_t / 2.0), delta * 0.8)
	if absf(p - _power) > 0.002:
		_power = p
		_set_param(&"power", _power)
	if _dead:
		_break = minf(1.0, _break + delta * 0.6)
	_track_motion(delta)
	_pose_ryft(delta)
	var fade := 1.0 - _dissolve if _dead else 1.0
	for i in _lights.size():
		if is_instance_valid(_lights[i]):
			_lights[i].light_energy = _light_energy[i] * fade * (1.0 + _power * 0.6)


func _track_motion(delta: float) -> void:
	if not is_inside_tree() or delta <= 0.0:
		return
	var gp := global_position
	var gy := global_rotation.y
	if _prev_pos.is_finite():
		var v := (gp - _prev_pos) / delta
		# Blinks and resets are jumps, not motion.
		if v.length() < 45.0:
			_vel_local = damp_v(_vel_local, global_transform.basis.orthonormalized().inverse() * v, 5.0, delta)
			_yaw_rate = damp(_yaw_rate, angle_difference(_prev_yaw, gy) / delta, 5.0, delta)
	_prev_pos = gp
	_prev_yaw = gy
	var target := Vector3(clampf(_vel_local.z * 0.035, -0.35, 0.35), 0.0,
		clampf(-_vel_local.x * 0.035 + _yaw_rate * 0.12, -0.35, 0.35))
	_lean = damp_v(_lean, Vector3.ZERO if _dead else target, 4.0, delta)


## 0..1 flinch envelope while the "hit" action plays.
func hit_recoil() -> float:
	if _action != "hit" or _dead:
		return 0.0
	return keys(action_progress(), [[0, 0], [0.18, 1.0], [0.5, 0.45], [1, 0]])


## 0..1 envelope of the last phase change (a violent transformation, ~2 s).
func phase_surge() -> float:
	return keys(_phase_t, [[0, 0], [0.25, 1.0], [1.4, 0.8], [2.2, 0]]) if _phase_t < 2.2 else 0.0


## Arm pose: `forward` raises the arm in front (PI/2 = level, PI = overhead,
## negative = drawn back), `out` spreads it sideways, `bend` folds the
## forearm forward. Mirrored for the left arm (side -1).
static func arm(sh: Node3D, el: Node3D, side: float, forward: float, out: float, bend: float, rate: float, delta: float) -> void:
	pose(sh, Vector3(forward, 0.0, side * out), rate, delta)
	pose(el, Vector3(bend, 0.0, 0.0), rate, delta)


## Override: pose every part (actions via _action / action_progress()).
func _pose_ryft(_delta: float) -> void:
	pass
