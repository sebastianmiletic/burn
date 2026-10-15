class_name MoveFx
extends Node3D
## Pooled one-shot movement particles: take-off dust bursts, landing rings,
## footstep puffs, sprint debris. One pool per viewport (so it survives entities
## being freed); every effect reuses a GPUParticles3D from a small ring buffer,
## so firing an effect allocates nothing.
##
##   MoveFx.landing(self, global_position, impact_speed, ground_block)
##   MoveFx.takeoff(self, pos, ground_block)
##   MoveFx.footstep(self, pos, strength, ground_block, direction)

const DUST := preload("res://models/fx/dust.gdshader")

enum Kind { PUFF, BURST, RING, DEBRIS }
const POOL_SIZE := [10, 4, 4, 6]

static var _pools := {}

var _emitters: Array = []   # per kind: Array[GPUParticles3D]
var _next := PackedInt32Array([0, 0, 0, 0])
var _materials: Dictionary = {}


## Ground colour of the dust kicked up from a block (dim, so it never glows).
static func dust_color(block: int) -> Color:
	match block:
		Blocks.SNOW:
			return Color(0.78, 0.8, 0.84)
		Blocks.SAND:
			return Color(0.62, 0.52, 0.36)
		Blocks.GRASS, Blocks.DRY_GRASS:
			return Color(0.42, 0.38, 0.28)
		Blocks.DIRT, Blocks.MUD:
			return Color(0.4, 0.32, 0.24)
		Blocks.ASH, Blocks.SOUL_SAND:
			return Color(0.35, 0.33, 0.32)
	if block > 0:
		var c := Blocks.color(block)
		return c.lerp(Color(0.5, 0.47, 0.42), 0.5)
	return Color(0.48, 0.43, 0.36)


static func _pool(from: Node) -> MoveFx:
	if from == null or not from.is_inside_tree():
		return null
	var vp := from.get_viewport()
	if vp == null:
		return null
	var key := vp.get_instance_id()
	var p: MoveFx = _pools.get(key)
	if p == null or not is_instance_valid(p):
		p = MoveFx.new()
		p.name = "MoveFx"
		vp.add_child.call_deferred(p)
		p._build()
		_pools[key] = p
	return p


static func takeoff(from: Node, pos: Vector3, block := -1, strength := 1.0) -> void:
	var p := _pool(from)
	if p != null:
		p._fire(Kind.BURST, pos, strength, block, Vector3.ZERO)


static func landing(from: Node, pos: Vector3, impact: float, block := -1) -> void:
	var p := _pool(from)
	if p == null:
		return
	var s := clampf(impact / 12.0, 0.25, 1.6)
	p._fire(Kind.RING, pos, s, block, Vector3.ZERO)
	if impact > 12.0:
		p._fire(Kind.DEBRIS, pos, 1.2, block, Vector3.ZERO)


static func footstep(from: Node, pos: Vector3, strength: float, block := -1, dir := Vector3.ZERO) -> void:
	var p := _pool(from)
	if p == null:
		return
	p._fire(Kind.PUFF, pos, strength, block, dir)
	if strength > 0.85 and block != Blocks.SNOW and block != Blocks.GRASS:
		p._fire(Kind.DEBRIS, pos, 0.5, block, dir)


func _build() -> void:
	for kind in 4:
		var list: Array[GPUParticles3D] = []
		for i in int(POOL_SIZE[kind]):
			list.append(_make(kind))
		_emitters.append(list)


func _material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = DUST
	return m


func _make(kind: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.9
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 5, 8))
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3(0, 0.15, 0)
	pm.damping_min = 3.0
	pm.damping_max = 5.0
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.add_point(0.12, Color(1, 1, 1, 1.0))
	g.set_offset(g.get_point_count() - 1, 1.0)
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.35))
	grow.add_point(Vector2(1, 1.0))
	var gc := CurveTexture.new()
	gc.curve = grow
	pm.scale_curve = gc
	var quad := QuadMesh.new()
	var mat := _material()
	match kind:
		Kind.PUFF:
			p.amount = 6
			p.lifetime = 0.8
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 0.08
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 70.0
			pm.initial_velocity_min = 0.3
			pm.initial_velocity_max = 0.9
			quad.size = Vector2(0.45, 0.45)
		Kind.BURST:
			p.amount = 16
			p.lifetime = 0.9
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			pm.emission_ring_axis = Vector3.UP
			pm.emission_ring_radius = 0.25
			pm.emission_ring_inner_radius = 0.1
			pm.emission_ring_height = 0.02
			pm.direction = Vector3(0, 0.4, 0)
			pm.spread = 20.0
			pm.radial_velocity_min = 1.2
			pm.radial_velocity_max = 2.6
			pm.initial_velocity_min = 0.3
			pm.initial_velocity_max = 0.8
			quad.size = Vector2(0.55, 0.55)
		Kind.RING:
			p.amount = 28
			p.lifetime = 1.1
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			pm.emission_ring_axis = Vector3.UP
			pm.emission_ring_radius = 0.35
			pm.emission_ring_inner_radius = 0.2
			pm.emission_ring_height = 0.02
			pm.direction = Vector3(0, 0.25, 0)
			pm.spread = 15.0
			pm.radial_velocity_min = 2.0
			pm.radial_velocity_max = 4.5
			pm.initial_velocity_min = 0.2
			pm.initial_velocity_max = 0.7
			pm.damping_min = 4.0
			pm.damping_max = 6.0
			quad.size = Vector2(0.7, 0.7)
		Kind.DEBRIS:
			p.amount = 8
			p.lifetime = 0.7
			p.explosiveness = 1.0
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 0.12
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 40.0
			pm.initial_velocity_min = 1.5
			pm.initial_velocity_max = 3.2
			pm.gravity = Vector3(0, -9.8, 0)
			pm.damping_min = 0.5
			pm.damping_max = 1.0
			var flat := Curve.new()
			flat.add_point(Vector2(0, 1.0))
			flat.add_point(Vector2(1, 0.7))
			var fc := CurveTexture.new()
			fc.curve = flat
			pm.scale_curve = fc
			quad.size = Vector2(0.07, 0.07)
			mat.set_shader_parameter(&"density", 1.0)
			mat.set_shader_parameter(&"soft_distance", 0.05)
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	quad.material = mat
	p.process_material = pm
	p.draw_pass_1 = quad
	add_child(p)
	return p


func _fire(kind: int, pos: Vector3, strength: float, block: int, dir: Vector3) -> void:
	if not is_inside_tree():
		return
	var list: Array = _emitters[kind]
	var i := _next[kind]
	_next[kind] = (i + 1) % list.size()
	var p: GPUParticles3D = list[i]
	var pm := p.process_material as ParticleProcessMaterial
	var c := dust_color(block)
	var snow := block == Blocks.SNOW
	var sand := block == Blocks.SAND or block == Blocks.SOUL_SAND or block == Blocks.ASH
	if kind == Kind.DEBRIS:
		c = c.darkened(0.35)
	c.a = 1.0
	pm.color = c
	var s := clampf(strength, 0.1, 2.0)
	pm.scale_min = 0.6 * lerpf(0.7, 1.3, minf(s, 1.0)) * (1.25 if snow else 1.0)
	pm.scale_max = 1.3 * lerpf(0.7, 1.4, minf(s, 1.0)) * (1.25 if snow else 1.0)
	match kind:
		Kind.RING:
			pm.radial_velocity_min = 1.6 * s
			pm.radial_velocity_max = 4.2 * s
			pm.gravity = Vector3(0, -1.5 if sand else (0.05 if snow else 0.2), 0)
			p.amount_ratio = clampf(0.45 + 0.4 * s, 0.3, 1.0)
		Kind.BURST:
			pm.gravity = Vector3(0, -1.5 if sand else 0.15, 0)
			p.amount_ratio = clampf(0.5 + 0.5 * s, 0.3, 1.0)
		Kind.PUFF:
			if dir != Vector3.ZERO:
				pm.direction = (Vector3(0, 1.0, 0) - dir.normalized() * 0.8).normalized()
			pm.initial_velocity_max = 0.6 + 0.8 * s
			pm.gravity = Vector3(0, -1.2 if sand else (0.0 if snow else 0.15), 0)
			p.amount_ratio = clampf(0.35 + 0.65 * s, 0.2, 1.0) * (1.4 if snow or sand else 1.0)
		Kind.DEBRIS:
			p.amount_ratio = clampf(s, 0.2, 1.0)
	p.global_position = pos + Vector3(0, 0.05, 0)
	p.restart()
	p.emitting = true
