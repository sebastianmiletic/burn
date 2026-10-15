extends Node3D
## Felled-tree FX (created by Flora.fell): the tree pivots about its root along the fall
## direction, accelerating like a toppling pole, thuds and bounces, then bursts into a puff of
## leaves (or needles / bark chips) and dust and is gone after ~2.5 s.

signal landed(impact_point: Vector3)

const MeshKit := preload("res://world/flora/flora_mesh_kit.gd")

var _pivot := Node3D.new()
var _mesh := MeshInstance3D.new()
var _axis := Vector3.RIGHT
var _dir := Vector3.FORWARD
var _height := 8.0
var _kind := 0
var _seed := 0
var _theta := 0.1
var _omega := 0.3
var _k := 2.0
var _t := 0.0
var _bounces := 0
var _landed_at := -1.0
var _burst := false
const MAX_THETA := 1.47     # rests on its crown/branches a little above flat
const LIFE := 2.5


func setup(mesh: Mesh, mats: Array, kind: int, height: float, yaw: float, direction: Vector3, seed_value: int) -> void:
	_kind = kind
	_height = maxf(height, 1.0)
	_seed = seed_value
	var d := Vector3(direction.x, 0.0, direction.z)
	_dir = d.normalized() if d.length() > 0.001 else Vector3.FORWARD
	_axis = Vector3.UP.cross(_dir).normalized()
	_mesh.mesh = mesh
	for i in mats.size():
		_mesh.set_surface_override_material(i, mats[i])
	_mesh.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * _height), Vector3(0, -0.12, 0))
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# A toppling pole: theta'' = 3g / (2L) sin(theta); a bit faster than physical so it reads in 2.5 s.
	_k = 3.0 * 9.8 / (2.0 * _height * 0.62) * 1.9
	_theta = 0.06
	_omega = 0.35


func _ready() -> void:
	add_child(_pivot)
	_pivot.add_child(_mesh)


func _process(delta: float) -> void:
	_t += delta
	if _landed_at < 0.0 or _bounces < 3:
		_omega += _k * sin(_theta) * delta
		_theta += _omega * delta
		if _theta >= MAX_THETA:
			_theta = MAX_THETA
			if _bounces == 0:
				_landed_at = _t
				landed.emit(global_position + _dir * _height * 0.6)
			_bounces += 1
			_omega = -_omega * (0.22 if _bounces == 1 else 0.1)
			if _bounces >= 3:
				_omega = 0.0
	_pivot.basis = Basis(_axis, _theta)
	var break_at := _landed_at + 0.45 if _landed_at >= 0.0 else LIFE - 0.6
	break_at = minf(break_at, LIFE - 0.6)
	if not _burst and _t >= break_at:
		_burst = true
		_spawn_burst()
	if _burst:
		# Crumble: sink and shrink into the dust over ~0.4 s.
		var k := clampf((_t - break_at) / 0.4, 0.0, 1.0)
		_pivot.scale = Vector3.ONE * maxf(1.0 - k * k, 0.001)
		_pivot.position = -Vector3.UP * k * 0.4
		if k >= 1.0:
			_mesh.visible = false
	if _t >= LIFE + 1.4:
		queue_free()


func _spawn_burst() -> void:
	var crown := _dir * _height * 0.62 + Vector3.UP * 0.6
	# Leaves / needles / bark chips: small alpha-tested atlas cards (FOLIAGE in the ASCII pass).
	var tile := MeshKit.TILE_LITTER
	match _kind:
		2: tile = MeshKit.TILE_PINE
		3: tile = MeshKit.TILE_TWIGS
	var leaves := CPUParticles3D.new()
	leaves.mesh = _leaf_card(tile)
	leaves.material_override = Flora.material("fx_leaves")
	leaves.amount = 90 if _kind != 3 else 40
	leaves.one_shot = true
	leaves.explosiveness = 0.92
	leaves.lifetime = 1.6
	leaves.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	leaves.emission_box_extents = Vector3(_height * 0.25, 0.8, _height * 0.25)
	leaves.direction = Vector3.UP
	leaves.spread = 70.0
	leaves.initial_velocity_min = 1.5
	leaves.initial_velocity_max = 4.5
	leaves.gravity = Vector3(0, -2.2, 0)
	leaves.damping_min = 1.0
	leaves.damping_max = 2.5
	leaves.angular_velocity_min = -360.0
	leaves.angular_velocity_max = 360.0
	leaves.particle_flag_rotate_y = true
	leaves.scale_amount_min = 0.6
	leaves.scale_amount_max = 1.3
	leaves.position = crown
	leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(leaves)
	leaves.emitting = true
	# Dust: soft, lit, translucent puffs drawn over the glyphs.
	var dust := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 1.6)
	dust.mesh = quad
	dust.material_override = _dust_material()
	dust.amount = 26
	dust.one_shot = true
	dust.explosiveness = 0.85
	dust.lifetime = 1.3
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(_height * 0.3, 0.3, _height * 0.3)
	dust.direction = Vector3.UP
	dust.spread = 80.0
	dust.initial_velocity_min = 0.6
	dust.initial_velocity_max = 2.0
	dust.gravity = Vector3(0, 0.25, 0)
	dust.damping_min = 0.8
	dust.damping_max = 1.6
	dust.scale_amount_min = 0.8
	dust.scale_amount_max = 2.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 1.4))
	dust.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.55, 0.47, 0.38, 0.55))
	ramp.set_color(1, Color(0.55, 0.47, 0.38, 0.0))
	dust.color_ramp = ramp
	dust.position = _dir * _height * 0.5 + Vector3.UP * 0.4
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dust)
	dust.emitting = true


static func _leaf_card(tile: int) -> ArrayMesh:
	var s := MeshKit.Surf.new()
	var size := 0.32
	var uv0 := Vector2(0.25, 0.25)
	var uv1 := Vector2(0.75, 0.75)
	var corners := [Vector3(-size, 0, -size), Vector3(size, 0, -size), Vector3(size, 0, size), Vector3(-size, 0, size)]
	var uvs := [Vector2(uv0.x, uv1.y), Vector2(uv1.x, uv1.y), Vector2(uv1.x, uv0.y), Vector2(uv0.x, uv0.y)]
	for k in 4:
		var uv: Vector2 = uvs[k]
		s.vert(corners[k], Vector3.UP, Vector3.RIGHT, MeshKit.atlas_uv(tile, uv.x, uv.y), Color(0, 0, 0, 1))
	s.tri(0, 1, 2)
	s.tri(0, 2, 3)
	var mesh := ArrayMesh.new()
	s.commit(mesh, null)
	return mesh


static var _dust_mat: StandardMaterial3D


static func _dust_material() -> StandardMaterial3D:
	if _dust_mat != null:
		return _dust_mat
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = g
	tex.width = 64
	tex.height = 64
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.roughness = 1.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	_dust_mat = m
	return m
