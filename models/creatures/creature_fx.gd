class_name CreatureFx
extends RefCounted
## Pooled one-shot particle effects for creatures and telegraph landings:
## water splashes and geysers, dust, venom, webs, mud, frost. Emitters are
## created once per (scene, style) and re-triggered, so a boss fight does not
## allocate particle systems every second.
##
##   CreatureFx.play(parent, "splash", pos, 1.5)

const MAX_PER_STYLE := 6
const SMOKE := preload("res://models/creatures/breath_smoke.gdshader")

## style -> {amount, lifetime, speed, spread, gravity, size, hot, cool, intensity, radius, up}
const STYLES := {
	"splash": {"amount": 70, "lifetime": 1.3, "speed": 9.0, "spread": 35.0, "gravity": -16.0, "size": 0.9,
		"hot": Color(0.85, 0.95, 1.0), "cool": Color(0.25, 0.45, 0.6), "intensity": 1.6, "radius": 1.2, "damping": 0.5},
	"geyser": {"amount": 120, "lifetime": 1.6, "speed": 17.0, "spread": 9.0, "gravity": -14.0, "size": 1.1,
		"hot": Color(0.9, 0.97, 1.0), "cool": Color(0.3, 0.55, 0.7), "intensity": 1.8, "radius": 1.0, "damping": 0.3},
	"foam": {"amount": 40, "lifetime": 1.8, "speed": 2.5, "spread": 80.0, "gravity": -1.0, "size": 1.3,
		"hot": Color(0.8, 0.9, 0.95), "cool": Color(0.3, 0.4, 0.5), "intensity": 1.0, "radius": 2.0, "damping": 1.5},
	"dust": {"amount": 50, "lifetime": 1.2, "speed": 4.0, "spread": 70.0, "gravity": 0.6, "size": 1.0,
		"hot": Color(0.75, 0.68, 0.58), "cool": Color(0.3, 0.26, 0.22), "intensity": 0.9, "radius": 1.0, "damping": 2.5},
	"venom": {"amount": 50, "lifetime": 0.9, "speed": 6.0, "spread": 60.0, "gravity": -9.0, "size": 0.6,
		"hot": Color(0.75, 1.0, 0.35), "cool": Color(0.15, 0.45, 0.05), "intensity": 3.5, "radius": 0.8, "damping": 1.0},
	"web": {"amount": 60, "lifetime": 1.6, "speed": 7.0, "spread": 90.0, "gravity": -2.0, "size": 0.5,
		"hot": Color(0.95, 0.95, 0.92), "cool": Color(0.5, 0.5, 0.5), "intensity": 1.2, "radius": 1.5, "damping": 3.0},
	"mud": {"amount": 60, "lifetime": 1.1, "speed": 8.0, "spread": 40.0, "gravity": -14.0, "size": 0.8,
		"hot": Color(0.45, 0.5, 0.25), "cool": Color(0.12, 0.13, 0.06), "intensity": 1.2, "radius": 1.0, "damping": 0.8},
	"hex": {"amount": 60, "lifetime": 1.2, "speed": 5.0, "spread": 50.0, "gravity": 2.0, "size": 0.7,
		"hot": Color(0.7, 1.0, 0.6), "cool": Color(0.1, 0.5, 0.25), "intensity": 4.5, "radius": 1.2, "damping": 1.5},
	"frost": {"amount": 60, "lifetime": 1.2, "speed": 6.0, "spread": 70.0, "gravity": -3.0, "size": 0.7,
		"hot": Color(0.9, 0.97, 1.0), "cool": Color(0.4, 0.6, 0.9), "intensity": 2.5, "radius": 1.2, "damping": 2.0},
	# Billowing (not glowing) clouds for big impacts: wing buffets, landings, stomps.
	"dust_cloud": {"amount": 36, "lifetime": 2.2, "speed": 5.0, "spread": 75.0, "gravity": 0.8, "size": 2.6,
		"hot": Color(0.42, 0.34, 0.26), "cool": Color(0.24, 0.19, 0.15), "intensity": 0.7, "radius": 1.5, "damping": 3.0, "smoke": true},
	"ash_cloud": {"amount": 36, "lifetime": 2.4, "speed": 4.0, "spread": 80.0, "gravity": 1.2, "size": 2.6,
		"hot": Color(0.45, 0.18, 0.08), "cool": Color(0.1, 0.08, 0.08), "intensity": 0.8, "radius": 1.5, "damping": 3.0, "smoke": true},
	"embers": {"amount": 60, "lifetime": 1.0, "speed": 6.0, "spread": 80.0, "gravity": 2.0, "size": 0.5,
		"hot": Color(1.0, 0.85, 0.5), "cool": Color(1.0, 0.3, 0.05), "intensity": 6.0, "radius": 0.8, "damping": 2.0},
}

static var _pools := {}  # "parent_id|style" -> Array[GPUParticles3D]


static func play(parent: Node3D, style: String, pos: Vector3, scale := 1.0) -> void:
	if parent == null or not parent.is_inside_tree() or not STYLES.has(style):
		return
	var key := "%d|%s" % [parent.get_instance_id(), style]
	var pool: Array = _pools.get(key, [])
	var pick: GPUParticles3D = null
	for p: GPUParticles3D in pool:
		if is_instance_valid(p) and not p.emitting:
			pick = p
			break
	pool = pool.filter(func(p: Variant) -> bool: return is_instance_valid(p))
	if pick == null:
		if pool.size() >= MAX_PER_STYLE:
			pick = pool[0]
			pool.remove_at(0)
			pool.append(pick)
		else:
			pick = _make(style)
			parent.add_child(pick)
			pool.append(pick)
	_pools[key] = pool
	pick.global_position = pos
	pick.scale = Vector3.ONE * scale
	pick.restart()
	pick.emitting = true


static func _make(style: String) -> GPUParticles3D:
	var s: Dictionary = STYLES[style]
	var p := GPUParticles3D.new()
	p.amount = int(s["amount"])
	p.lifetime = float(s["lifetime"])
	p.one_shot = true
	p.explosiveness = 0.9
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-20, -10, -20), Vector3(40, 40, 40))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = float(s["radius"])
	pm.direction = Vector3.UP
	pm.spread = float(s["spread"])
	pm.initial_velocity_min = float(s["speed"]) * 0.45
	pm.initial_velocity_max = float(s["speed"])
	pm.gravity = Vector3(0, float(s["gravity"]), 0)
	pm.damping_min = float(s["damping"])
	pm.damping_max = float(s["damping"]) * 1.6
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	pm.particle_flag_disable_z = false
	var c := Curve.new()
	c.add_point(Vector2(0, 0.6))
	c.add_point(Vector2(0.3, 1.0))
	c.add_point(Vector2(1, 0.25))
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
	quad.size = Vector2.ONE * float(s["size"])
	if s.get("smoke", false):
		var sm := ShaderMaterial.new()
		sm.shader = SMOKE
		sm.set_shader_parameter(&"smoke_color", s["cool"])
		sm.set_shader_parameter(&"lit_color", s["hot"])
		sm.set_shader_parameter(&"density", float(s["intensity"]))
		quad.material = sm
	else:
		quad.material = MaterialLibrary.fx(s["hot"], s["cool"], float(s["intensity"]))
	p.draw_pass_1 = quad
	return p


## A continuous emitter (wakes, drips, auras) owned by the caller.
static func emitter(parent: Node3D, style: String, amount: int, extents: Vector3, scale := 1.0) -> GPUParticles3D:
	var p := _make(style)
	p.one_shot = false
	p.explosiveness = 0.0
	p.amount = amount
	var pm := p.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	p.scale = Vector3.ONE * scale
	parent.add_child(p)
	return p
