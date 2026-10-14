class_name Portal
extends Entity
## A gateway between dimensions. The Gates of Hades stay sealed until the
## traveller carries the three seals (Warden's Sigil, Frost Crown, Dragonheart).

const SEALS := ["warden_sigil", "frost_crown", "dragonheart"]

var to_dimension := 1
var size := Vector2(10, 14)
var _veil: MeshInstance3D
var _veil_mat: ShaderMaterial
var _sparks: GPUParticles3D
var _light: OmniLight3D


func _init() -> void:
	kind = "portal"
	team = Team.NEUTRAL
	hit_radius = 2.5
	body.collides = false
	body.gravity = 0.0


func on_spawned(data: Dictionary) -> void:
	to_dimension = int(data.get("to", 1))
	size = data.get("size", Vector2(10, 14))
	_veil = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	_veil.mesh = q
	_veil.position.y = size.y * 0.5
	_veil_mat = ShaderMaterial.new()
	_veil_mat.shader = preload("res://world/materials/portal_veil.gdshader")
	_veil.material_override = _veil_mat
	_veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_veil)
	_light = OmniLight3D.new()
	_light.position = Vector3(0, size.y * 0.5, 1.5)
	_light.light_color = Color(1.0, 0.35, 0.12) if to_dimension == 1 else Color(0.6, 0.75, 1.0)
	_light.omni_range = size.y * 1.3
	_light.light_energy = 2.5
	_light.light_volumetric_fog_energy = 3.0
	add_child(_light)
	_sparks = GPUParticles3D.new()
	_sparks.amount = 60
	_sparks.lifetime = 2.5
	_sparks.position.y = size.y * 0.5
	_sparks.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(size.x * 0.45, size.y * 0.45, 0.2)
	pm.direction = Vector3(0, 1, 0.3)
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0, 0.6, 0)
	pm.color_ramp = Torch._fade_gradient()
	_sparks.process_material = pm
	var sq := QuadMesh.new()
	sq.size = Vector2(0.12, 0.12)
	sq.material = MaterialLibrary.fx(Color(1.0, 0.8, 0.5), Color(1.0, 0.3, 0.1), 8.0)
	_sparks.draw_pass_1 = sq
	add_child(_sparks)
	_veil_mat.set_shader_parameter(&"color_a", Color(1.0, 0.3, 0.06) if to_dimension == 1 else Color(0.45, 0.6, 1.0))
	_veil_mat.set_shader_parameter(&"color_b", Color(0.4, 0.02, 0.0) if to_dimension == 1 else Color(0.1, 0.1, 0.3))


func _process(_delta: float) -> void:
	var w := world()
	if w == null or w.local_player == null:
		return
	var open := _is_open(w.local_player)
	_veil_mat.set_shader_parameter(&"open", 1.0 if open else 0.15)
	_sparks.emitting = open
	_light.light_energy = 2.5 if open else 0.6


func _is_open(p: Player) -> bool:
	if to_dimension == 0:
		return true
	for s: String in SEALS:
		if not p.inventory.has(s):
			return false
	return true


func interact_prompt(p: Player) -> String:
	if to_dimension == 0:
		return "Return to the world above"
	return "Enter the Gates of Hades" if _is_open(p) else "The Gates are sealed"


func local_interact(p: Player) -> void:
	if not _is_open(p):
		var missing := PackedStringArray()
		for s: String in SEALS:
			if not p.inventory.has(s):
				missing.append(ItemDB.display_name(s))
		Events.notify.emit("Three seals bar the way. Missing: " + ", ".join(missing), "warn")
		Audio.play("door", global_position, 0.0, 0.6)
		return
	world().travel(to_dimension)
