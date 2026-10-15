class_name ArenaLights
extends Node3D
## Pooled arena lights. An arena declares many light spots (braziers, candles,
## lava, soul fires); only the nearest few get a real OmniLight3D, and only
## the nearest one or two of those cast shadows. Flicker runs on assigned
## lights only. Pool sizes follow the graphics quality.

const POOL := [3, 5, 8, 12]
const SHADOWS := [0, 0, 1, 2]
const REASSIGN := 0.3

var _specs: Array = []          # dicts with local "pos"
var _pool: Array[OmniLight3D] = []
var _assigned := PackedInt32Array()
var _noise := FastNoiseLite.new()
var _t := 0.0
var _reassign := 0.0


func setup(specs: Array, origin: Vector3) -> void:
	for s: Dictionary in specs:
		var d := s.duplicate()
		d["pos"] = (s["pos"] as Vector3) - origin
		_specs.append(d)
	_noise.frequency = 2.0
	var q := clampi(int(Settings.get_value("graphics", "quality")), 0, 3)
	var n := mini(int(POOL[q]), _specs.size())
	for i in n:
		var l := OmniLight3D.new()
		l.omni_attenuation = 1.6
		l.shadow_blur = 1.4
		l.light_size = 0.15
		l.distance_fade_enabled = true
		l.distance_fade_begin = 70.0
		l.distance_fade_length = 20.0
		l.distance_fade_shadow = 35.0
		l.visible = false
		add_child(l)
		_pool.append(l)
		_assigned.append(-1)
	_reassign = 0.0


func _process(delta: float) -> void:
	if _pool.is_empty():
		return
	_t += delta
	_reassign -= delta
	if _reassign <= 0.0:
		_reassign = REASSIGN
		_assign()
	for i in _pool.size():
		var si := _assigned[i]
		if si < 0:
			continue
		var s: Dictionary = _specs[si]
		var fl := float(s["flicker"])
		if fl <= 0.0:
			continue
		var n := _noise.get_noise_2d(_t * 9.0, si * 13.0)
		var n2 := _noise.get_noise_2d(_t * 2.5, si * 13.0 + 50.0)
		_pool[i].light_energy = float(s["energy"]) * (1.0 + n * fl + n2 * fl * 0.6)


func _assign() -> void:
	var w := GameWorld.instance
	if w == null or w.local_player == null:
		return
	var eye := w.local_player.global_position - global_position + Vector3(0, 1.6, 0)
	var order := []
	for i in _specs.size():
		var s: Dictionary = _specs[i]
		var d := eye.distance_to(s["pos"]) - float(s["range"]) * 0.35 - float(s["shadow"]) * 6.0
		order.append([d, i])
	order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var q := clampi(int(Settings.get_value("graphics", "quality")), 0, 3)
	var shadows: int = SHADOWS[q]
	var wanted := {}
	for k in mini(_pool.size(), order.size()):
		wanted[int(order[k][1])] = k
	# Keep lights that stay assigned (no popping), fill the rest.
	var free: Array[int] = []
	for i in _pool.size():
		if not wanted.has(_assigned[i]):
			free.append(i)
		else:
			wanted.erase(_assigned[i])
	for si: int in wanted:
		if free.is_empty():
			break
		var li: int = free.pop_back()
		_assigned[li] = si
		_configure(_pool[li], _specs[si])
	for i in _pool.size():
		var si := _assigned[i]
		var l := _pool[i]
		l.visible = si >= 0
		if si < 0:
			continue
		var rank := -1
		for k in order.size():
			if int(order[k][1]) == si:
				rank = k
				break
		l.shadow_enabled = rank >= 0 and rank < shadows and int(_specs[si]["shadow"]) > 0


func _configure(l: OmniLight3D, s: Dictionary) -> void:
	l.position = s["pos"]
	l.light_color = s["color"]
	l.light_energy = s["energy"]
	l.omni_range = s["range"]
	l.light_volumetric_fog_energy = float(s["fog"])
