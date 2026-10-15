class_name SwingTrail
extends MeshInstance3D
## A ribbon that follows a weapon's edge through a swing: every frame while
## recording it samples the grip and tip in world space; samples fade out over
## `life` seconds. Rebuilt with an ImmediateMesh only while something is visible.

const SHADER := preload("res://models/fx/swing_trail.gdshader")
const MAX := 48

var life := 0.2
var _base := PackedVector3Array()
var _tip := PackedVector3Array()
var _age := PackedFloat32Array()
var _count := 0
var _head := 0
var _recording := false
var _im := ImmediateMesh.new()
var _mat := ShaderMaterial.new()


func _init() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = _im
	_mat.shader = SHADER
	material_override = _mat
	_base.resize(MAX)
	_tip.resize(MAX)
	_age.resize(MAX)
	extra_cull_margin = 4.0
	visible = false


func set_color(c: Color) -> void:
	_mat.set_shader_parameter(&"color", c)


func set_recording(on: bool) -> void:
	_recording = on


func push(base: Vector3, tip: Vector3) -> void:
	if not _recording:
		return
	# Skip near-duplicate samples (standing still).
	if _count > 0:
		var last := (_head - 1 + MAX) % MAX
		if _tip[last].distance_squared_to(tip) < 0.0004:
			_age[last] = 0.0
			return
	# Fast swings move the tip a long way per frame: fill in samples along an
	# arc (direction slerped around the grip) so the ribbon stays curved.
	var steps := 1
	var last_base := base
	var last_tip := tip
	if _count > 0:
		var last := (_head - 1 + MAX) % MAX
		last_base = _base[last]
		last_tip = _tip[last]
		steps = clampi(int(ceil(last_tip.distance_to(tip) / 0.07)), 1, 6)
	var d0 := last_tip - last_base
	var d1 := tip - base
	var l0 := d0.length()
	var l1 := d1.length()
	for i in range(1, steps + 1):
		var f := float(i) / steps
		var b := last_base.lerp(base, f)
		var dir := d1 / maxf(l1, 0.001)
		if l0 > 0.001 and l1 > 0.001 and steps > 1:
			dir = (d0 / l0).slerp(d1 / l1, f)
		_base[_head] = b
		_tip[_head] = b + dir * lerpf(l0 if steps > 1 else l1, l1, f)
		_age[_head] = (1.0 - f) * 0.016
		_head = (_head + 1) % MAX
		_count = mini(_count + 1, MAX)


func tick(delta: float) -> void:
	var alive := 0
	for i in _count:
		var k := (_head - 1 - i + MAX * 2) % MAX
		_age[k] += delta
		if _age[k] < life:
			alive += 1
	_count = alive
	if alive < 2:
		if visible:
			_im.clear_surfaces()
			visible = false
		return
	visible = true
	global_transform = Transform3D.IDENTITY
	_im.clear_surfaces()
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(alive - 1, -1, -1):
		var k := (_head - 1 - i + MAX * 2) % MAX
		var along := 1.0 - float(i) / float(maxi(alive - 1, 1))
		var fade := 1.0 - clampf(_age[k] / life, 0.0, 1.0)
		_im.surface_set_color(Color(1, 1, 1, fade))
		_im.surface_set_uv(Vector2(along, 0.0))
		_im.surface_add_vertex(_base[k])
		_im.surface_set_color(Color(1, 1, 1, fade))
		_im.surface_set_uv(Vector2(along, 1.0))
		_im.surface_add_vertex(_tip[k])
	_im.surface_end()
