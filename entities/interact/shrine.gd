class_name Shrine
extends Entity
## An Ember Shrine: a stone brazier. Rekindling it sets your respawn point,
## restores you, and counts for quests. Lit state is per player.

var location_id: StringName = &""
var _flame: GPUParticles3D
var _light: OmniLight3D
var _lit_local := false


func _init() -> void:
	kind = "shrine"
	team = Team.NEUTRAL
	hit_radius = 0.6
	body.collides = false
	body.gravity = 0.0


func on_spawned(data: Dictionary) -> void:
	location_id = StringName(String(data.get("location", "")))
	var stone := MaterialLibrary.stone(&"dark")
	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.55
	cyl.bottom_radius = 0.75
	cyl.height = 0.9
	cyl.radial_segments = 8
	base.mesh = cyl
	base.position.y = 0.45
	base.material_override = stone
	add_child(base)
	var bowl := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 0.7
	bc.bottom_radius = 0.4
	bc.height = 0.3
	bc.radial_segments = 8
	bowl.mesh = bc
	bowl.position.y = 1.05
	bowl.material_override = MaterialLibrary.stone(&"iron")
	add_child(bowl)
	var coals := MeshInstance3D.new()
	var cs := SphereMesh.new()
	cs.radius = 0.45
	cs.height = 0.3
	coals.mesh = cs
	coals.position.y = 1.18
	coals.material_override = MaterialLibrary.emissive(Color(1.0, 0.4, 0.1), 2.5)
	add_child(coals)
	_light = OmniLight3D.new()
	_light.position.y = 1.8
	_light.light_color = Color(1.0, 0.55, 0.25)
	_light.omni_range = 11.0
	_light.light_volumetric_fog_energy = 2.0
	add_child(_light)
	_flame = GPUParticles3D.new()
	_flame.amount = 40
	_flame.lifetime = 0.9
	_flame.position.y = 1.25
	_flame.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	pm.direction = Vector3.UP
	pm.spread = 10.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, 1.5, 0)
	pm.scale_curve = Torch._curve([Vector2(0.0, 0.7), Vector2(0.3, 1.0), Vector2(1.0, 0.0)])
	pm.color_ramp = Torch._fade_gradient()
	_flame.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.75)
	quad.material = MaterialLibrary.fx(Color(1.0, 0.85, 0.5), Color(1.0, 0.3, 0.05), 6.0)
	_flame.draw_pass_1 = quad
	add_child(_flame)
	_refresh()


func _process(_delta: float) -> void:
	var w := world()
	if w == null:
		return
	var lit := w.lit_shrines.has(location_id)
	if lit != _lit_local:
		_refresh()
	if _light.visible:
		_light.light_energy = 2.2 + sin(Time.get_ticks_msec() * 0.011) * 0.25 + randf() * 0.15


func _refresh() -> void:
	var w := world()
	_lit_local = w != null and w.lit_shrines.has(location_id)
	_flame.emitting = _lit_local
	_light.visible = true
	_light.light_energy = 2.2 if _lit_local else 0.4
	_light.omni_range = 11.0 if _lit_local else 4.0


func interact_prompt(_p: Player) -> String:
	return "Rest at shrine" if _lit_local else "Rekindle shrine"


func local_interact(p: Player) -> void:
	var w := world()
	var first := not w.lit_shrines.has(location_id)
	w.lit_shrines[location_id] = true
	p.respawn_point = global_position + Vector3(0, 0.05, 2.0)
	p.respawn_dimension = dimension
	p.heal_local(p.max_health)
	_refresh()
	w.view.flash = 0.35
	Audio.play("shrine", global_position)
	w.quests.on_event("interact", "shrine@" + String(location_id))
	if first:
		p.add_xp(25)
		Events.notify.emit("Shrine rekindled. You will wake here if you fall.", "info")
	else:
		Events.notify.emit("You rest by the fire. Health restored.", "info")
	if Game.has_method("save_game") and Net.is_server():
		Game.call("save_game")
