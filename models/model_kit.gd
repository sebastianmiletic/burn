class_name ModelKit
extends RefCounted
## Building blocks for procedural models: cached primitive meshes and
## materials that declare their ASCII material class. Models face -Z.

const CREATURE := preload("res://models/creature.gdshader")
const GLOW := preload("res://models/glow.gdshader")
const TRAIL := preload("res://models/trail.gdshader")

static var _mats := {}
static var _meshes := {}


## Creature / character surface. ascii_id: AsciiMaterialId.SOLID or CLOTH.
static func mat(color: Color, ascii_id := AsciiMaterialId.SOLID, roughness := 0.8, detail := 0.22, rim := 0.0) -> ShaderMaterial:
	var key := "%s|%d|%.2f|%.2f|%.2f" % [color.to_html(), ascii_id, roughness, detail, rim]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = CREATURE
		m.set_shader_parameter(&"albedo", color)
		m.set_shader_parameter(&"ascii_id", ascii_id)
		m.set_shader_parameter(&"roughness", roughness)
		m.set_shader_parameter(&"detail", detail)
		m.set_shader_parameter(&"rim", rim)
		_mats[key] = m
	return _mats[key]


static func cloth(color: Color) -> ShaderMaterial:
	return mat(color, AsciiMaterialId.CLOTH, 0.95, 0.3)


static func metal(color: Color) -> ShaderMaterial:
	return mat(color, AsciiMaterialId.SOLID, 0.35, 0.12)


## Glowing part (eyes, crowns, runes): passes through the ASCII grid and blooms.
static func glow(color: Color, energy := 5.0, pulse := 0.0) -> ShaderMaterial:
	var key := "glow|%s|%.2f|%.2f" % [color.to_html(), energy, pulse]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = GLOW
		m.set_shader_parameter(&"glow_color", color)
		m.set_shader_parameter(&"energy", energy)
		m.set_shader_parameter(&"pulse", pulse)
		_mats[key] = m
	return _mats[key]


static func trail_material(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TRAIL
	m.set_shader_parameter(&"color", color)
	return m


# --- Meshes (cached by shape) ---------------------------------------------------

static func box(size: Vector3) -> Mesh:
	var key := "box%s" % size
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


static func capsule(radius: float, height: float, sides := 8) -> Mesh:
	var key := "cap%.3f|%.3f|%d" % [radius, height, sides]
	if not _meshes.has(key):
		var m := CapsuleMesh.new()
		m.radius = radius
		m.height = maxf(height, radius * 2.0 + 0.001)
		m.radial_segments = sides
		m.rings = 2
		_meshes[key] = m
	return _meshes[key]


static func cylinder(top: float, bottom: float, height: float, sides := 8) -> Mesh:
	var key := "cyl%.3f|%.3f|%.3f|%d" % [top, bottom, height, sides]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = height
		m.radial_segments = sides
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]


static func cone(radius: float, height: float, sides := 8) -> Mesh:
	return cylinder(0.0, radius, height, sides)


static func sphere(radius: float, segments := 10) -> Mesh:
	var key := "sph%.3f|%d" % [radius, segments]
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		m.radial_segments = segments
		m.rings = maxi(4, segments / 2)
		_meshes[key] = m
	return _meshes[key]


## A flat polygon in the local XY plane, extruded `thickness` along Z.
## Used for wings, blades and fins.
static func slab(points: PackedVector2Array, thickness: float) -> ArrayMesh:
	var key := "slab%s|%.3f" % [str(points), thickness]
	if _meshes.has(key):
		return _meshes[key]
	var tris := Geometry2D.triangulate_polygon(points)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := thickness * 0.5
	for i in range(0, tris.size(), 3):
		var a := points[tris[i]]
		var b := points[tris[i + 1]]
		var c := points[tris[i + 2]]
		var ccw := (b - a).cross(c - a) > 0.0
		_tri(st, Vector3(a.x, a.y, h), Vector3(b.x, b.y, h), Vector3(c.x, c.y, h), Vector3(0, 0, 1), ccw)
		_tri(st, Vector3(a.x, a.y, -h), Vector3(b.x, b.y, -h), Vector3(c.x, c.y, -h), Vector3(0, 0, -1), not ccw)
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var mid := (a + b) * 0.5
		var n2 := Vector2(b.y - a.y, a.x - b.x).normalized()
		# Point the wall normal away from the polygon centre.
		var centroid := Vector2.ZERO
		for p in points:
			centroid += p
		centroid /= points.size()
		if n2.dot(mid - centroid) < 0.0:
			n2 = -n2
		var n := Vector3(n2.x, n2.y, 0)
		var q0 := Vector3(a.x, a.y, h)
		var q1 := Vector3(b.x, b.y, h)
		var q2 := Vector3(b.x, b.y, -h)
		var q3 := Vector3(a.x, a.y, -h)
		_quad(st, q0, q1, q2, q3, n)
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


## Adds a triangle facing `n` (Godot front faces are clockwise seen from outside).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, _hint := false) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	for v: Vector3 in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_tri(st, a, b, c, n)
	_tri(st, a, c, d, n)


## Arc ribbon for weapon trails: a sector of an annulus in the XY plane.
static func arc(inner: float, outer: float, degrees: float, segments := 16) -> ArrayMesh:
	var key := "arc%.2f|%.2f|%.1f" % [inner, outer, degrees]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a0 := deg_to_rad(degrees) * float(i) / segments
		var a1 := deg_to_rad(degrees) * float(i + 1) / segments
		var u0 := float(i) / segments
		var u1 := float(i + 1) / segments
		var p := [Vector3(cos(a0) * inner, sin(a0) * inner, 0), Vector3(cos(a0) * outer, sin(a0) * outer, 0),
				Vector3(cos(a1) * outer, sin(a1) * outer, 0), Vector3(cos(a1) * inner, sin(a1) * inner, 0)]
		var uv := [Vector2(u0, 0), Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0)]
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uv[k])
			st.set_normal(Vector3(0, 0, 1))
			st.add_vertex(p[k])
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


# --- Scene helpers ---------------------------------------------------------------

static func joint(parent: Node3D, joint_name: String, pos := Vector3.ZERO) -> Node3D:
	var j := Node3D.new()
	j.name = joint_name
	j.position = pos
	parent.add_child(j)
	return j


static func part(parent: Node3D, mesh: Mesh, material: Material, pos := Vector3.ZERO, rot_deg := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	parent.add_child(mi)
	return mi


## Additive ember particles that follow a node (burning, dissolving, fire breath).
static func embers(parent: Node3D, amount: int, extents: Vector3, lifetime := 1.2, size := 0.08, rise := 1.5) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(-extents * 3.0 - Vector3(0, 0, 0), extents * 6.0 + Vector3(0, 6, 0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3.UP
	pm.spread = 30.0
	pm.initial_velocity_min = rise * 0.4
	pm.initial_velocity_max = rise
	pm.gravity = Vector3(0, 0.6, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = MaterialLibrary.fx(Color(1.0, 0.85, 0.5), Color(1.0, 0.3, 0.05), 10.0)
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p


## A short burst of fire / sparks at a world position (explosions, impacts).
static func burst(parent: Node3D, pos: Vector3, amount := 40, radius := 0.6, speed := 5.0, size := 0.5, hot := Color(1.0, 0.85, 0.5), cool := Color(1.0, 0.3, 0.05), lifetime := 0.7) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.95
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, 1.0, 0)
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	var c := Curve.new()
	c.add_point(Vector2(0, 1))
	c.add_point(Vector2(1, 0.2))
	var ct := CurveTexture.new()
	ct.curve = c
	pm.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = MaterialLibrary.fx(hot, cool, 8.0)
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


## Brief light flash (explosions, spells). Frees itself.
static func flash_light(parent: Node3D, pos: Vector3, color: Color, energy := 4.0, radius := 8.0, seconds := 0.35) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = radius
	l.shadow_enabled = false
	l.light_volumetric_fog_energy = 2.0
	parent.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, seconds)
	tw.tween_callback(l.queue_free)
