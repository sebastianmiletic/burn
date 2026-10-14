class_name MiningFx
extends Node3D
## Pooled debris for digging and chopping: chips of the material flying off the
## surface (lit, so they become glyphs) and a puff of dust.

const POOL := 6

var _chips: Array[GPUParticles3D] = []
var _dust: Array[GPUParticles3D] = []
var _next := 0


func _ready() -> void:
	for i in POOL:
		_chips.append(_make_chips())
		_dust.append(_make_dust())


## A pickaxe strike: a few chips. Breaking: many chips and dust.
func debris(point: Vector3, normal: Vector3, color: Color, breaking: bool) -> void:
	var i := _next
	_next = (_next + 1) % POOL
	var c := _chips[i]
	c.global_position = point + normal * 0.05
	c.amount_ratio = 1.0 if breaking else 0.35
	var pm := c.process_material as ParticleProcessMaterial
	pm.direction = normal
	pm.color = color.darkened(0.1)
	c.restart()
	if breaking:
		var d := _dust[i]
		d.global_position = point + normal * 0.2
		(d.process_material as ParticleProcessMaterial).color = Color(color.lightened(0.25), 0.55)
		d.restart()


func _make_chips() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 28
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 0.95
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 55.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.5
	pm.gravity = Vector3(0, -18, 0)
	pm.angular_velocity_min = -720.0
	pm.angular_velocity_max = 720.0
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_bounce = 0.25
	pm.collision_friction = 0.6
	p.process_material = pm
	var box := BoxMesh.new()
	box.size = Vector3(0.07, 0.05, 0.06)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = AsciiMaterialId.encode_roughness(0.85, AsciiMaterialId.SOLID)
	box.material = m
	p.draw_pass_1 = box
	add_child(p)
	return p


func _make_dust() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 1.6
	p.one_shot = true
	p.explosiveness = 0.9
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	pm.direction = Vector3.UP
	pm.spread = 80.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, 0.25, 0)
	pm.damping_min = 1.5
	pm.damping_max = 2.5
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.8))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 0.6)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	q.material = m
	p.draw_pass_1 = q
	add_child(p)
	return p


static var _dot: ImageTexture


static func _soft_dot() -> ImageTexture:
	if _dot == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32:
				var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 2.0))
		_dot = ImageTexture.create_from_image(img)
	return _dot
