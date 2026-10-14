class_name MaterialLibrary
extends RefCounted
## Shared, cached materials. Every world material goes through here so that
## each one declares its ASCII material class.

const STONE := preload("res://world/materials/stone.gdshader")
const GROUND := preload("res://world/materials/ground.gdshader")
const GRASS := preload("res://world/materials/grass_blade.gdshader")
const PUDDLE := preload("res://world/materials/puddle.gdshader")
const RAIN := preload("res://weather/rain_streak.gdshader")
const FX := preload("res://rendering/materials/fx_additive.gdshader")
const EMISSIVE := preload("res://rendering/materials/emissive_core.gdshader")

static var _cache := {}


static func stone(variant: StringName = &"ruin") -> ShaderMaterial:
	return _cached(&"stone_" + variant, func() -> ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = STONE
		m.set_shader_parameter(&"ascii_id", AsciiMaterialId.SOLID)
		match variant:
			&"dark":
				m.set_shader_parameter(&"color_light", Color(0.3, 0.28, 0.27))
				m.set_shader_parameter(&"color_dark", Color(0.12, 0.11, 0.11))
				m.set_shader_parameter(&"moss_amount", 0.15)
			&"iron":
				m.set_shader_parameter(&"color_light", Color(0.2, 0.18, 0.17))
				m.set_shader_parameter(&"color_dark", Color(0.08, 0.07, 0.07))
				m.set_shader_parameter(&"moss_amount", 0.0)
				m.set_shader_parameter(&"base_roughness", 0.5)
				m.set_shader_parameter(&"noise_scale", 4.0)
		return m)


static func ground() -> ShaderMaterial:
	return _cached(&"ground", func() -> ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = GROUND
		return m)


static func grass() -> ShaderMaterial:
	return _cached(&"grass", func() -> ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = GRASS
		return m)


static func puddle() -> ShaderMaterial:
	return _cached(&"puddle", func() -> ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = PUDDLE
		return m)


static func rain() -> ShaderMaterial:
	return _cached(&"rain", func() -> ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = RAIN
		return m)


## Additive emissive FX material. Not cached: callers usually tweak colours.
static func fx(hot: Color, cool: Color, intensity: float, billboard := true) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FX
	m.set_shader_parameter(&"hot_color", hot)
	m.set_shader_parameter(&"cool_color", cool)
	m.set_shader_parameter(&"intensity", intensity)
	m.set_shader_parameter(&"billboard", billboard)
	return m


static func emissive(color: Color, energy: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = EMISSIVE
	m.set_shader_parameter(&"glow_color", color)
	m.set_shader_parameter(&"energy", energy)
	return m


static func _cached(key: StringName, make: Callable) -> ShaderMaterial:
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]
