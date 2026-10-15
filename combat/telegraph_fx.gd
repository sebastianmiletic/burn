class_name TelegraphFx
extends MeshInstance3D
## Visual for a telegraphed attack (see TelegraphShape for the geometry).
## Fills over `duration`, flashes as the attack lands, then fades away.
##
## Styled shapes ("circle:geyser", "line:wave", "line:tail", "circle:web"...)
## also play a themed landing effect on every machine, because telegraphs are
## broadcast to all clients while a boss's own on-land callbacks only run on
## the server. Models can listen for telegraphs (the Leviathan aims its tail
## and jaws at them) through `listen()`.

const SHADER := preload("res://combat/telegraph.gdshader")
const SHAPES := {"circle": 0, "cone": 1, "line": 2, "ring": 3}
## Warning colour per style (most stay the classic ember red-orange).
const COLORS := {
	"geyser": Color(0.45, 0.8, 1.0), "wave": Color(0.45, 0.8, 1.0), "bile": Color(0.6, 1.0, 0.2),
	"venom": Color(0.6, 1.0, 0.2), "web": Color(0.9, 0.9, 0.85), "hex": Color(0.45, 1.0, 0.55),
	"frost": Color(0.6, 0.85, 1.0),
}

static var _listeners: Array[Callable] = []

var _mat := ShaderMaterial.new()
var _style := ""
var _shape := ""
var _size := Vector3.ZERO
var _dir := Vector3.FORWARD
var _wave: GPUParticles3D
var _duration := 1.0
var _t := 0.0
var _landed := false


## callback(style: String, shape: String, pos: Vector3, dir: Vector3, size: Vector3, duration: float)
static func listen(callback: Callable) -> void:
	if not _listeners.has(callback):
		_listeners.append(callback)


static func unlisten(callback: Callable) -> void:
	_listeners.erase(callback)


static func spawn(parent: Node3D, shape: String, pos: Vector3, dir: Vector3, size: Vector3, duration: float) -> TelegraphFx:
	var fx := TelegraphFx.new()
	parent.add_child(fx)
	fx._setup(shape, pos, dir, size, duration)
	var style := TelegraphShape.style(shape)
	if style != "":
		for cb in _listeners.duplicate():
			if cb.is_valid():
				cb.call(style, TelegraphShape.base(shape), pos, dir, size, duration)
			else:
				_listeners.erase(cb)
	return fx


func _setup(shape_full: String, pos: Vector3, dir: Vector3, size: Vector3, duration: float) -> void:
	var shape := TelegraphShape.base(shape_full)
	_style = TelegraphShape.style(shape_full)
	_shape = shape
	_size = size
	_dir = Vector3(dir.x, 0, dir.z).normalized() if Vector2(dir.x, dir.z).length() > 1e-3 else Vector3.FORWARD
	_duration = maxf(0.05, duration)
	var plane := PlaneMesh.new()
	match shape:
		"circle":
			plane.size = Vector2(size.x, size.x) * 2.0
		"ring":
			plane.size = Vector2(size.y, size.y) * 2.0
		"cone":
			plane.size = Vector2(size.x, size.x) * 2.0
		"line":
			plane.size = Vector2(size.y, size.x)
			plane.center_offset = Vector3(0, 0, -size.x * 0.5)
	plane.subdivide_width = 0
	plane.subdivide_depth = 0
	mesh = plane
	_mat.shader = SHADER
	_mat.set_shader_parameter(&"shape", SHAPES.get(shape, 0))
	_mat.set_shader_parameter(&"size", Vector2(size.x, size.y))
	if COLORS.has(_style):
		_mat.set_shader_parameter(&"color", COLORS[_style])
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	global_position = pos + Vector3(0, 0.08, 0)
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length_squared() > 1e-6:
		look_at(global_position + flat.normalized(), Vector3.UP)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter(&"fill", v), 0.0, 1.0, _duration)
	tw.tween_callback(_land)
	tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter(&"flash", v), 1.0, 0.0, 0.3)
	tw.parallel().tween_method(func(v: float) -> void: _mat.set_shader_parameter(&"alpha", v), 1.0, 0.0, 0.35)
	tw.tween_interval(0.6 if _style == "wave" else 0.0)
	tw.tween_callback(queue_free)
	_begin_style()


func _fx_parent() -> Node3D:
	return get_parent() as Node3D


## Effects that run while the warning fills.
func _begin_style() -> void:
	match _style:
		"geyser":
			var c := global_position
			if _shape == "circle":
				CreatureFx.play(_fx_parent(), "foam", c, _size.x / 3.0)
		"wave":
			# A wall of spray rolling in from the sea along the lane.
			_wave = CreatureFx.emitter(self, "splash", 160, Vector3(_size.y * 0.5, 0.4, 1.0))
			_wave.emitting = true
			_wave.position = Vector3(0, 0, 18.0)
			var pm := _wave.process_material as ParticleProcessMaterial
			pm.initial_velocity_min = 5.0
			pm.initial_velocity_max = 11.0
			pm.spread = 20.0
			set_process(true)


func _process(delta: float) -> void:
	if _wave == null:
		return
	_t += delta
	# Roll in to the start of the lane while filling, then sweep across it.
	var z: float
	if _t < _duration:
		z = lerpf(18.0, 0.0, _t / _duration)
	else:
		z = lerpf(0.0, -_size.x, clampf((_t - _duration) / 0.55, 0.0, 1.0))
		if _t > _duration + 0.55:
			_wave.emitting = false
	_wave.position = Vector3(0, 0.5, z)


## The attack lands: themed burst for styled telegraphs.
func _land() -> void:
	if _landed:
		return
	_landed = true
	var parent := _fx_parent()
	if parent == null:
		return
	var c := global_position
	match _style:
		"geyser":
			if _shape == "ring":
				var r := (_size.x + _size.y) * 0.5
				var n := clampi(int(TAU * r / 5.0), 3, 8)
				for i in n:
					var a := TAU * float(i) / n
					CreatureFx.play(parent, "geyser", c + Vector3(cos(a), 0, sin(a)) * r, maxf(1.0, (_size.y - _size.x) / 3.0))
			else:
				CreatureFx.play(parent, "geyser", c, _size.x / 3.0)
			Audio.play("splash", c, 2.0, 0.7)
		"bite", "slam":
			CreatureFx.play(parent, "dust", c, _size.x / 3.0)
			CreatureFx.play(parent, "splash", c, _size.x / 4.0)
		"tail", "breach":
			for i in 4:
				var p := c + _dir * _size.x * (0.2 + i * 0.25)
				CreatureFx.play(parent, "splash", p, 1.8)
				CreatureFx.play(parent, "dust", p, 1.4)
		"wave":
			for i in 3:
				CreatureFx.play(parent, "splash", c + _dir * _size.x * (0.3 + i * 0.3), 2.5)
		"bile", "venom":
			CreatureFx.play(parent, "venom", c, _size.x / 2.0)
		"web":
			if _shape == "line":
				for i in 3:
					CreatureFx.play(parent, "web", c + _dir * _size.x * (0.2 + i * 0.3), 1.2)
			else:
				CreatureFx.play(parent, "web", c, _size.x / 2.0)
		"mud", "roots":
			CreatureFx.play(parent, "mud", c, _size.x / 2.5)
			CreatureFx.play(parent, "dust", c, _size.x / 3.0)
		"hex":
			CreatureFx.play(parent, "hex", c, _size.x / 2.5)
		"frost":
			CreatureFx.play(parent, "frost", c, _size.x / 2.5)
		"fire":
			CreatureFx.play(parent, "embers", c, _size.x / 2.5)
