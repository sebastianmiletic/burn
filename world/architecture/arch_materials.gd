class_name ArchMaterials
extends RefCounted
## The shared architecture material (one ShaderMaterial for every modelled
## building, so a village batches into a handful of draw calls), its texture
## layers, and the shared smoke / flame particle resources. Main thread only.

const SHADER := preload("res://world/architecture/architecture.gdshader")
const ALBEDO_PATH := "res://assets/architecture/arch_albedo.jpg"
const NORMAL_PATH := "res://assets/architecture/arch_normal.webp"

## Texture layers (ArchMesh.layer). 0..11 are CC0 Poly Haven sets
## (tools/textures/pack_architecture.py), the rest procedural.
enum L { PLASTER, TIMBER, BOARDS, RUBBLE, ASHLAR, THATCH, SLATE, SHINGLE, IRON, LINEN, COBBLE, FLOOR,
	GLASS, EMBER, FLAT, WATER }

## World size (m) of one texture tile per layer: (u, v). Roofs are cropped to
## whole courses: slate courses are 0.1036 m, shingle courses 0.1125 m.
const TILE := [Vector2(2.0, 2.0), Vector2(0.5, 0.5), Vector2(2.0, 2.0), Vector2(1.5, 1.5), Vector2(1.52, 1.52),
	Vector2(2.5, 2.314), Vector2(3.0, 2.591), Vector2(3.0, 1.462), Vector2(1.0, 1.0), Vector2(0.6, 0.6),
	Vector2(1.95, 1.95), Vector2(1.0, 1.0)]
const SLATE_COURSE := 2.591 / 25.0
const SHINGLE_COURSE := 1.462 / 13.0
const ROUGHNESS := [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.9, 1.0, 0.75, 1.0, 1.0, 0.95]

static var _main: ShaderMaterial
static var _smoke_mat: Material
static var _smoke_process: ParticleProcessMaterial
static var _smoke_mesh: QuadMesh
static var _flame_process: ParticleProcessMaterial
static var _flame_mesh: QuadMesh


static func main() -> ShaderMaterial:
	if _main != null:
		return _main
	_main = ShaderMaterial.new()
	_main.shader = SHADER
	if ResourceLoader.exists(ALBEDO_PATH):
		_main.set_shader_parameter(&"albedo_tex", load(ALBEDO_PATH))
		_main.set_shader_parameter(&"normal_tex", load(NORMAL_PATH))
	var info := PackedVector4Array()
	info.resize(16)
	for i in 16:
		var cls := AsciiMaterialId.SOLID
		if i == L.THATCH or i == L.LINEN:
			cls = AsciiMaterialId.CLOTH
		elif i == L.EMBER or i == L.GLASS:
			cls = AsciiMaterialId.EMISSIVE
		elif i == L.WATER:
			cls = AsciiMaterialId.LIQUID
		if i < TILE.size():
			var tile: Vector2 = TILE[i]
			info[i] = Vector4(1.0 / tile.x, 1.0 / tile.y, ROUGHNESS[i], cls)
		else:
			info[i] = Vector4(1, 1, 1, cls)
	_main.set_shader_parameter(&"layer_info", info)
	return _main


## 0 by day .. 1 at night: windows glow from within.
static func set_night(amount: float) -> void:
	main().set_shader_parameter(&"night_glow", amount)


## Soft chimney smoke rising and drifting with the wind.
static func smoke(parent: Node3D, pos: Vector3, strength := 1.0) -> GPUParticles3D:
	if _smoke_process == null:
		_smoke_process = ParticleProcessMaterial.new()
		_smoke_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		_smoke_process.emission_sphere_radius = 0.15
		_smoke_process.direction = Vector3(0.15, 1, 0.05)
		_smoke_process.spread = 12.0
		_smoke_process.initial_velocity_min = 0.5
		_smoke_process.initial_velocity_max = 0.9
		_smoke_process.gravity = Vector3(0.35, 0.25, 0.12)
		_smoke_process.damping_min = 0.05
		_smoke_process.damping_max = 0.15
		_smoke_process.angle_min = 0.0
		_smoke_process.angle_max = 360.0
		_smoke_process.angular_velocity_min = -12.0
		_smoke_process.angular_velocity_max = 12.0
		_smoke_process.scale_min = 0.6
		_smoke_process.scale_max = 1.0
		_smoke_process.scale_curve = Torch._curve([Vector2(0.0, 0.35), Vector2(0.4, 0.8), Vector2(1.0, 1.6)])
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.55, 0.53, 0.5, 0.0))
		ramp.set_color(1, Color(0.7, 0.7, 0.72, 0.0))
		ramp.add_point(0.12, Color(0.42, 0.4, 0.38, 0.42))
		ramp.add_point(0.55, Color(0.6, 0.6, 0.6, 0.22))
		var tex := GradientTexture1D.new()
		tex.gradient = ramp
		_smoke_process.color_ramp = tex
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 1.0
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.albedo_texture = _puff_texture()
		mat.proximity_fade_enabled = true
		mat.proximity_fade_distance = 0.6
		mat.disable_receive_shadows = true
		_smoke_mat = mat
		_smoke_mesh = QuadMesh.new()
		_smoke_mesh.size = Vector2(1.4, 1.4)
		_smoke_mesh.material = _smoke_mat
	var p := GPUParticles3D.new()
	p.amount = int(14 * strength) + 4
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.position = pos
	p.process_material = _smoke_process
	p.draw_pass_1 = _smoke_mesh
	p.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(14, 12, 10))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_range_end = 220.0
	p.visibility_range_end_margin = 20.0
	p.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(p)
	return p


## A small open fire (hearths, forges, braziers): additive flame and a warm light.
static func fire(parent: Node3D, pos: Vector3, size := 1.0, light_range := 6.0, energy := 1.6) -> OmniLight3D:
	if _flame_process == null:
		_flame_process = ParticleProcessMaterial.new()
		_flame_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		_flame_process.emission_sphere_radius = 0.12
		_flame_process.direction = Vector3.UP
		_flame_process.spread = 8.0
		_flame_process.initial_velocity_min = 0.4
		_flame_process.initial_velocity_max = 0.9
		_flame_process.gravity = Vector3(0, 1.2, 0)
		_flame_process.scale_curve = Torch._curve([Vector2(0.0, 0.6), Vector2(0.3, 1.0), Vector2(1.0, 0.0)])
		_flame_process.color_ramp = Torch._fade_gradient()
		_flame_mesh = QuadMesh.new()
		_flame_mesh.size = Vector2(0.32, 0.45)
		_flame_mesh.material = MaterialLibrary.fx(Color(1.0, 0.85, 0.5), Color(1.0, 0.3, 0.05), 5.0)
	var f := GPUParticles3D.new()
	f.amount = int(18 * size) + 6
	f.lifetime = 0.7
	f.position = pos
	f.scale = Vector3.ONE * size
	f.local_coords = false
	f.process_material = _flame_process
	f.draw_pass_1 = _flame_mesh
	f.visibility_aabb = AABB(Vector3(-1, -0.5, -1), Vector3(2, 2.5, 2))
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f.visibility_range_end = 90.0
	parent.add_child(f)
	var light := OmniLight3D.new()
	light.position = pos + Vector3(0, 0.35 * size, 0)
	light.light_color = Color(1.0, 0.56, 0.26)
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = 1.3
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 55.0
	light.distance_fade_length = 15.0
	light.light_volumetric_fog_energy = 0.6
	parent.add_child(light)
	return light


static var _puff: Texture2D


## Soft round puff with a little internal billow.
static func _puff_texture() -> Texture2D:
	if _puff != null:
		return _puff
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.09
	noise.seed = 7
	for y in s:
		for x in s:
			var d := Vector2(x - s * 0.5 + 0.5, y - s * 0.5 + 0.5).length() / (s * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			a *= 0.75 + 0.25 * noise.get_noise_2d(x, y)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	img.generate_mipmaps()
	_puff = ImageTexture.create_from_image(img)
	return _puff
