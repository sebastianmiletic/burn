class_name BreathStream
extends Node3D
## A creature's breath weapon, blown along the node's -Z: torn flame licks that roll along the ground where they land
## (they collide with a ground plane, see `set_ground`), soot billowing off
## the stream and a flickering light. Presets: "fire" (Ashvane), "hellfire"
## (Cerberus), "ash" (Cerberus' smothering ash cloud).
##
##   var b := BreathStream.new().setup(18.0, 9.0, "fire")
##   mouth.add_child(b); b.set_on(true)

const FLAME := preload("res://models/creatures/breath_fx.gdshader")
const SMOKE := preload("res://models/creatures/breath_smoke.gdshader")

const PRESETS := {
	"fire": {"hot": Color(1.0, 0.93, 0.7), "mid": Color(1.0, 0.5, 0.12), "cool": Color(0.6, 0.1, 0.02), "smoke": Color(0.08, 0.06, 0.05),
		"lit": Color(0.55, 0.22, 0.06), "light": Color(1.0, 0.55, 0.2), "intensity": 1.7},
	"hellfire": {"hot": Color(1.0, 0.85, 0.55), "mid": Color(1.0, 0.32, 0.06), "cool": Color(0.45, 0.04, 0.02), "smoke": Color(0.06, 0.04, 0.04),
		"lit": Color(0.5, 0.12, 0.04), "light": Color(1.0, 0.4, 0.15), "intensity": 1.8},
	"ash": {"hot": Color(0.9, 0.55, 0.3), "mid": Color(0.45, 0.2, 0.1), "cool": Color(0.18, 0.1, 0.08), "smoke": Color(0.16, 0.14, 0.13),
		"lit": Color(0.35, 0.18, 0.1), "light": Color(1.0, 0.35, 0.12), "intensity": 1.0},
}

var length := 16.0
var on := false
var flames: GPUParticles3D
var smoke: GPUParticles3D
var light: OmniLight3D
var _collider: GPUParticlesCollisionBox3D
var _strength := 0.0
var _energy := 6.0
var _flicker := 0.0


func setup(stream_length := 16.0, spread_deg := 9.0, preset := "fire", size := 1.6) -> BreathStream:
	length = stream_length
	var p: Dictionary = PRESETS.get(preset, PRESETS["fire"])
	var ash := preset == "ash"
	flames = GPUParticles3D.new()
	flames.name = "Flames"
	flames.amount = 120 if ash else 280
	flames.lifetime = 0.95 if not ash else 1.3
	flames.local_coords = false
	flames.emitting = false
	flames.fixed_fps = 0
	flames.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
	flames.visibility_aabb = AABB(Vector3(-length, -length * 1.2, -length * 1.6), Vector3(length * 2, length * 2.4, length * 2.2))
	flames.process_material = _process_material(length * (1.15 if not ash else 0.75), spread_deg, Vector3(0, 2.5 if not ash else 1.0, 0), 0.6 if not ash else 0.9, [0.35, 1.0, 2.6] if not ash else [0.5, 1.4, 3.2], true)
	var fq := QuadMesh.new()
	fq.size = Vector2.ONE * size * (1.0 if ash else 1.3)
	var fm := ShaderMaterial.new()
	fm.shader = FLAME
	fm.set_shader_parameter(&"hot_color", p["hot"])
	fm.set_shader_parameter(&"mid_color", p["mid"])
	fm.set_shader_parameter(&"cool_color", p["cool"])
	fm.set_shader_parameter(&"intensity", float(p["intensity"]))
	fq.material = fm
	flames.draw_pass_1 = fq
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flames)

	smoke = GPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.amount = 46 if not ash else 90
	smoke.lifetime = 2.4
	smoke.local_coords = false
	smoke.emitting = false
	smoke.visibility_aabb = AABB(Vector3(-length, -length, -length * 1.8), Vector3(length * 2, length * 2.6, length * 2.4))
	smoke.process_material = _process_material(length * (0.55 if not ash else 0.6), spread_deg * 1.6, Vector3(0, 3.0, 0), 1.6, [0.6, 1.6, 3.6], true)
	(smoke.process_material as ParticleProcessMaterial).emission_sphere_radius = 0.6
	var sq := QuadMesh.new()
	sq.size = Vector2.ONE * size * 1.4
	var sm := ShaderMaterial.new()
	sm.shader = SMOKE
	sm.set_shader_parameter(&"smoke_color", p["smoke"])
	sm.set_shader_parameter(&"lit_color", p["lit"])
	sm.set_shader_parameter(&"density", 0.28 if not ash else 0.6)
	sq.material = sm
	smoke.draw_pass_1 = sq
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smoke)

	light = OmniLight3D.new()
	light.light_color = p["light"]
	light.omni_range = length * 0.9
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.position = Vector3(0, 0, -length * 0.4)
	light.light_volumetric_fog_energy = 2.5
	add_child(light)
	_energy = 7.0 if not ash else 2.0
	return self


func _process_material(speed: float, spread_deg: float, gravity: Vector3, damping: float, scale_curve: Array, collide: bool) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.direction = Vector3(0, 0, -1)
	pm.spread = spread_deg
	pm.flatness = 0.0
	pm.initial_velocity_min = speed * 0.85
	pm.initial_velocity_max = speed * 1.15
	pm.gravity = gravity
	pm.damping_min = damping
	pm.damping_max = damping * 1.8
	# No turbulence: it bleeds the velocity away every frame and the stream
	# collapses into a ball. Spread, size and the torn shader do the work.
	pm.radial_velocity_min = -0.5
	pm.radial_velocity_max = 0.8
	var c := Curve.new()
	c.max_value = 4.0
	c.add_point(Vector2(0, float(scale_curve[0])))
	c.add_point(Vector2(0.35, float(scale_curve[1])))
	c.add_point(Vector2(1, float(scale_curve[2])))
	var ct := CurveTexture.new()
	ct.curve = c
	pm.scale_curve = ct
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	# The shaders read the particle's age from this ramp's alpha.
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	if collide:
		# Flames splash and roll along the ground instead of passing through it.
		pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
		pm.collision_friction = 0.35
		pm.collision_bounce = 0.08
		pm.collision_use_scale = false
	return pm


## The ground the stream rolls along (world height); the collider follows the stream.
func set_ground(y: float) -> void:
	if _collider == null:
		_collider = GPUParticlesCollisionBox3D.new()
		_collider.name = "Ground"
		_collider.top_level = true
		_collider.size = Vector3(length * 3.0, 2.0, length * 3.0)
		add_child(_collider)
	var g := global_position if is_inside_tree() else Vector3.ZERO
	_collider.global_transform = Transform3D(Basis(), Vector3(g.x, y - 1.0, g.z))


func set_on(value: bool) -> void:
	on = value
	if flames != null:
		flames.emitting = value
	if smoke != null:
		smoke.emitting = value


func _process(delta: float) -> void:
	_strength = move_toward(_strength, 1.0 if on else 0.0, delta * (6.0 if on else 3.0))
	_flicker += delta
	if light != null:
		light.light_energy = _energy * _strength * (0.85 + 0.15 * sin(_flicker * 31.0) * sin(_flicker * 17.0))
	if _collider != null and is_inside_tree():
		var g := global_position
		_collider.global_position = Vector3(g.x, _collider.global_position.y, g.z)


## Where the stream's centre line meets the ground (y = ground), or INF.
func ground_hit(ground: float) -> Vector3:
	var o := global_position
	var d := -global_transform.basis.z.normalized()
	if d.y > -0.05:
		return Vector3.INF
	var t := (ground - o.y) / d.y
	if t < 0.0 or t > length * 1.3:
		return Vector3.INF
	return o + d * t
