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


func _init() -> void:
	dissolve_delay = 2.6
	dissolve_time = 2.4
	durations["cast"] = 1.2
	durations["slam"] = 1.4
	durations["summon"] = 1.8
	durations["roar"] = 2.0
	durations["sweep"] = 1.3
	durations["teleport"] = 0.9


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
	_pose_ryft(delta)
	var fade := 1.0 - _dissolve if _dead else 1.0
	for i in _lights.size():
		if is_instance_valid(_lights[i]):
			_lights[i].light_energy = _light_energy[i] * fade * (1.0 + _power * 0.6)


## Override: pose every part (actions via _action / action_progress()).
func _pose_ryft(_delta: float) -> void:
	pass
