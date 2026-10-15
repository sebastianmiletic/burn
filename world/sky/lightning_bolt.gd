class_name LightningBolt
extends MeshInstance3D
## A cloud-to-ground lightning strike: a jagged, branching channel built by
## midpoint displacement, drawn as camera-facing ribbons with an additive HDR
## material (after the ASCII pass, so it stays a searing line and blooms),
## with the classic flicker of return strokes, a light at the channel and a
## short-lived afterglow. Frees itself.

const SHADER := preload("res://world/sky/lightning.gdshader")

var _life := 0.0
var _duration := 0.55
var _strokes: PackedFloat32Array = []
var _light: OmniLight3D
var _mat := ShaderMaterial.new()


## ground: strike point; top: where the channel leaves the cloud base.
static func strike(parent: Node3D, ground: Vector3, top_height: float, camera_pos: Vector3, rng_seed: int) -> LightningBolt:
	var bolt := LightningBolt.new()
	parent.add_child(bolt)
	bolt.global_position = Vector3.ZERO
	bolt._build(ground, top_height, camera_pos, rng_seed)
	return bolt


func _build(ground: Vector3, top_height: float, cam: Vector3, rng_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var top := ground + Vector3(rng.randf_range(-25, 25), top_height, rng.randf_range(-25, 25))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var main := _channel(top, ground, 7, 0.16, rng)
	_ribbon(st, main, cam, 1.4, 0.6, 1.0)
	# Branches peel off the upper two thirds of the channel and fade out.
	var branches := rng.randi_range(3, 6)
	for b in branches:
		var i := rng.randi_range(2, int(main.size() * 0.7))
		var start := main[i]
		var down := (main[mini(i + 4, main.size() - 1)] - start).normalized()
		var side := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
		var length := rng.randf_range(15.0, 45.0)
		var end := start + (down * 0.6 + side * 0.8).normalized() * length
		var path := _channel(start, end, 5, 0.22, rng)
		_ribbon(st, path, cam, 0.7, 0.25, 0.55)
		if rng.randf() < 0.5:
			var j := rng.randi_range(1, path.size() - 2)
			var sub := _channel(path[j], path[j] + (down + side * rng.randf_range(-1, 1)).normalized() * length * 0.4, 4, 0.25, rng)
			_ribbon(st, sub, cam, 0.4, 0.15, 0.35)
	mesh = st.commit()
	_mat.shader = SHADER
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Return strokes: 2-4 pulses, then a fading afterglow.
	var t := 0.0
	for k in rng.randi_range(2, 4):
		_strokes.append(t)
		t += rng.randf_range(0.05, 0.12)
	_duration = t + 0.25
	_light = OmniLight3D.new()
	_light.light_color = Color(0.78, 0.84, 1.0)
	_light.omni_range = 140.0
	_light.omni_attenuation = 1.2
	_light.shadow_enabled = false
	_light.light_volumetric_fog_energy = 4.0
	add_child(_light)
	_light.global_position = ground.lerp(top, 0.3)
	_update(0.0)


static func _channel(a: Vector3, b: Vector3, depth: int, roughness: float, rng: RandomNumberGenerator) -> PackedVector3Array:
	var pts := PackedVector3Array([a, b])
	var amp := a.distance_to(b) * roughness
	for level in depth:
		var next := PackedVector3Array()
		for i in pts.size() - 1:
			var p0 := pts[i]
			var p1 := pts[i + 1]
			next.append(p0)
			var mid := (p0 + p1) * 0.5
			mid += Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 0.4), rng.randf_range(-1, 1)) * amp
			next.append(mid)
		next.append(pts[pts.size() - 1])
		pts = next
		amp *= 0.55
	return pts


static func _ribbon(st: SurfaceTool, pts: PackedVector3Array, cam: Vector3, w0: float, w1: float, heat: float) -> void:
	var n := pts.size()
	for i in n - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var axis := (b - a).normalized()
		var side_a := axis.cross((cam - a).normalized()).normalized()
		var f0 := float(i) / float(n - 1)
		var f1 := float(i + 1) / float(n - 1)
		var wa := lerpf(w0, w1, f0)
		var wb := lerpf(w0, w1, f1)
		var ca := Color(heat * (1.0 - f0 * 0.3), 0, 0)
		var cb := Color(heat * (1.0 - f1 * 0.3), 0, 0)
		# UV.x across the ribbon (0..1) for the soft core.
		st.set_color(ca)
		st.set_uv(Vector2(0, f0))
		st.add_vertex(a - side_a * wa)
		st.set_uv(Vector2(1, f0))
		st.add_vertex(a + side_a * wa)
		st.set_color(cb)
		st.set_uv(Vector2(1, f1))
		st.add_vertex(b + side_a * wb)
		st.set_color(ca)
		st.set_uv(Vector2(0, f0))
		st.add_vertex(a - side_a * wa)
		st.set_color(cb)
		st.set_uv(Vector2(1, f1))
		st.add_vertex(b + side_a * wb)
		st.set_uv(Vector2(0, f1))
		st.add_vertex(b - side_a * wb)


func _process(delta: float) -> void:
	_life += delta
	if _life >= _duration:
		queue_free()
		return
	_update(_life)


func _update(t: float) -> void:
	var k := 0.0
	for s in _strokes:
		if t >= s:
			k = maxf(k, exp(-(t - s) * 28.0))
	# Afterglow of the ionised channel.
	k = maxf(k, 0.18 * clampf(1.0 - (t - _strokes[_strokes.size() - 1]) / 0.25, 0.0, 1.0))
	_mat.set_shader_parameter(&"intensity", 22.0 * k)
	_light.light_energy = 14.0 * k
