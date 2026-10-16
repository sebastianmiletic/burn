class_name CreatureSkin
extends RefCounted
## Cached creature surface materials (models/creatures/creature_skin.gdshader).
## Every material declares its ASCII class. Extra keys in `extra` override any
## shader uniform (belly_mix, accent, glow_mode, wet, use_uv...).

const SHADER := preload("res://models/creatures/creature_skin.gdshader")
const FUR_SHELL := preload("res://models/creatures/fur_shell.gdshader")

enum Pattern { SMOOTH, SCALES, FUR, CHITIN, ROCK, HIDE, FEATHERS, MEMBRANE }

static var _cache := {}


static func make(params: Dictionary) -> ShaderMaterial:
	var key := str(params)
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	for k: String in params:
		var v: Variant = params[k]
		m.set_shader_parameter(StringName(k), v)
	_cache[key] = m
	return m


static func _with(base: Dictionary, extra: Dictionary) -> ShaderMaterial:
	var p := base.duplicate()
	p.merge(extra, true)
	return make(p)


static func scales(color: Color, belly_color: Color, scale := 4.0, extra := {}) -> ShaderMaterial:
	return _with({"albedo": color, "belly": belly_color, "belly_mix": 0.85, "pattern": Pattern.SCALES,
		"pattern_scale": scale, "roughness": 0.5, "bump": 0.8, "rim": 0.3, "specular_amount": 0.45}, extra)


static func fur(color: Color, belly_color: Color, extra := {}) -> ShaderMaterial:
	return _with({"albedo": color, "belly": belly_color, "belly_mix": 0.7, "pattern": Pattern.FUR,
		"pattern_scale": 6.0, "roughness": 0.95, "bump": 0.45, "rim": 0.5, "specular_amount": 0.15,
		"ascii_id": AsciiMaterialId.CLOTH}, extra)


static func chitin(color: Color, extra := {}) -> ShaderMaterial:
	return _with({"albedo": color, "belly": color.lightened(0.15), "belly_mix": 0.5, "pattern": Pattern.CHITIN,
		"pattern_scale": 3.0, "roughness": 0.35, "bump": 0.7, "rim": 0.35, "specular_amount": 0.6}, extra)


static func rock(color: Color, extra := {}) -> ShaderMaterial:
	return _with({"albedo": color, "belly": color.darkened(0.2), "belly_mix": 0.4, "pattern": Pattern.ROCK,
		"pattern_scale": 1.6, "roughness": 0.92, "bump": 1.2, "rim": 0.15, "specular_amount": 0.2}, extra)


static func hide(color: Color, belly_color: Color, extra := {}) -> ShaderMaterial:
	return _with({"albedo": color, "belly": belly_color, "belly_mix": 0.7, "pattern": Pattern.HIDE,
		"pattern_scale": 3.5, "roughness": 0.7, "bump": 0.9, "rim": 0.3, "specular_amount": 0.3}, extra)


static func feathers(color: Color, belly_color: Color, extra := {}) -> ShaderMaterial:
	return _with({"albedo": color, "belly": belly_color, "belly_mix": 0.7, "pattern": Pattern.FEATHERS,
		"pattern_scale": 7.0, "roughness": 0.8, "bump": 0.7, "rim": 0.4, "specular_amount": 0.25,
		"ascii_id": AsciiMaterialId.CLOTH}, extra)


static func membrane(color: Color, extra := {}) -> ShaderMaterial:
	return _with({"albedo": color, "belly": color.darkened(0.2), "belly_mix": 0.3, "pattern": Pattern.MEMBRANE,
		"pattern_scale": 1.5, "roughness": 0.6, "bump": 0.4, "rim": 0.5, "backlight": 0.8, "specular_amount": 0.3,
		"ascii_id": AsciiMaterialId.CLOTH}, extra)


static func smooth(color: Color, belly_color: Color, extra := {}) -> ShaderMaterial:
	return _with({"albedo": color, "belly": belly_color, "belly_mix": 0.6, "pattern": Pattern.SMOOTH,
		"pattern_scale": 2.0, "roughness": 0.55, "bump": 0.3, "rim": 0.3, "specular_amount": 0.4}, extra)


## Teeth, claws, horns, tusks: keratin / enamel.
static func keratin(color := Color(0.86, 0.82, 0.7), extra := {}) -> ShaderMaterial:
	return _with({"albedo": color, "belly": color.darkened(0.3), "belly_mix": 0.3, "pattern": Pattern.HIDE,
		"pattern_scale": 12.0, "roughness": 0.4, "bump": 0.25, "rim": 0.2, "specular_amount": 0.5}, extra)


## Wet, dark inside of a mouth.
static func mouth(color := Color(0.32, 0.08, 0.08)) -> ShaderMaterial:
	return make({"albedo": color, "pattern": Pattern.HIDE, "pattern_scale": 6.0, "roughness": 0.3, "wet": 0.8,
		"bump": 0.5, "specular_amount": 0.6})


## A copy of `base` (a fur material on a MobRig body, use_rest) with
## `layers` fur shells (fur_shell.gdshader) chained as next passes: a soft,
## strand-broken coat `length` metres deep. `extra` overrides shell uniforms
## (density, clump_scale, droop, tip_color, tip_mix, fur_distance...).
static func with_fur(base: ShaderMaterial, length: float, layers := 3, extra := {}) -> ShaderMaterial:
	var key := "fur|%d|%s|%.4f|%d|%s" % [base.get_instance_id(), str(base.get_shader_parameter(&"albedo")), length, layers, str(extra)]
	if _cache.has(key):
		return _cache[key]
	var m := base.duplicate() as ShaderMaterial
	var prev: ShaderMaterial = m
	for i in layers:
		var s := ShaderMaterial.new()
		s.shader = FUR_SHELL
		for pname: StringName in [&"albedo", &"belly", &"belly_mix", &"accent", &"accent_mode", &"accent_amount", &"accent_scale", &"rim", &"ascii_id"]:
			var v: Variant = base.get_shader_parameter(pname)
			if v != null:
				s.set_shader_parameter(pname, v)
		s.set_shader_parameter(&"fur_length", length)
		s.set_shader_parameter(&"layer", float(i + 1) / layers)
		for k: String in extra:
			s.set_shader_parameter(StringName(k), extra[k])
		prev.next_pass = s
		prev = s
	_cache[key] = m
	return m


## Glossy eye with a glowing iris (glow material so it passes through the ASCII grid).
static func eye(color: Color, energy := 6.0, pulse := 0.15) -> ShaderMaterial:
	return ModelKit.glow(color, energy, pulse)
