class_name FireballOrbiter
extends Node3D
## A fireball circling the courtyard: additive core + trailing embers and a
## moving shadow-casting light. Shows glow spilling over the glyph grid.

@export var orbit_radius := 6.0
@export var orbit_height := 2.6
@export var orbit_speed := 0.45

var _ball: Node3D
var _t := 0.0


func _ready() -> void:
	_ball = Node3D.new()
	add_child(_ball)

	var core := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	core.mesh = quad
	core.material_override = MaterialLibrary.fx(Color(1.0, 0.92, 0.7), Color(1.0, 0.35, 0.06), 9.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ball.add_child(core)

	var trail := GPUParticles3D.new()
	trail.amount = 90
	trail.lifetime = 0.8
	trail.local_coords = false
	trail.visibility_aabb = AABB(Vector3(-12, -4, -12), Vector3(24, 10, 24))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.18
	pm.gravity = Vector3(0.0, 0.6, 0.0)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.3
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.scale_curve = Torch._curve([Vector2(0.0, 1.0), Vector2(1.0, 0.0)])
	pm.color_ramp = Torch._fade_gradient()
	trail.process_material = pm
	var tq := QuadMesh.new()
	tq.size = Vector2(0.45, 0.45)
	tq.material = MaterialLibrary.fx(Color(1.0, 0.75, 0.35), Color(0.9, 0.18, 0.03), 5.0)
	trail.draw_pass_1 = tq
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ball.add_child(trail)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.2)
	light.light_energy = 3.0
	light.omni_range = 9.0
	light.shadow_enabled = true
	light.light_volumetric_fog_energy = 2.5
	_ball.add_child(light)


func _process(delta: float) -> void:
	_t += delta * orbit_speed
	_ball.position = Vector3(cos(_t) * orbit_radius, orbit_height + sin(_t * 2.3) * 0.5, sin(_t) * orbit_radius)
