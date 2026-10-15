class_name ItemMats
extends RefCounted
## Cached materials for items and stations (models/items/item_material.gdshader).
## Every one declares its ASCII class, so items drawn in the world still
## become the right glyphs.

const SHADER := preload("res://models/items/item_material.gdshader")

enum Finish { PLAIN, METAL, WOOD, STONE, GEM, LEATHER, ORE, CLOTH, BARK, BONE }
enum Emit { NONE, UNIFORM, VEINS, FRESNEL, SHIMMER }

static var _cache := {}


static func make(params: Dictionary) -> ShaderMaterial:
	var keys := params.keys()
	keys.sort()
	var key := ""
	for k: String in keys:
		key += "%s=%s;" % [k, str(params[k])]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	for k: String in params:
		m.set_shader_parameter(StringName(k), params[k])
	_cache[key] = m
	return m


# --- Metals --------------------------------------------------------------------------

## Tier metals: copper, bronze, iron, steel, mithril, adamantite, infernal, plus gold, silver, tin, dark_iron.
static func metal(tier: String) -> ShaderMaterial:
	match tier:
		"copper":
			return make({"albedo": Color(0.92, 0.47, 0.33), "accent": Color(0.2, 0.55, 0.45), "metallic": 0.92, "roughness": 0.36, "finish": Finish.METAL, "wear": 0.55})
		"bronze":
			return make({"albedo": Color(0.84, 0.62, 0.34), "accent": Color(0.25, 0.4, 0.3), "metallic": 0.92, "roughness": 0.3, "finish": Finish.METAL, "wear": 0.4})
		"iron":
			return make({"albedo": Color(0.56, 0.56, 0.57), "accent": Color(0.35, 0.2, 0.12), "metallic": 0.88, "roughness": 0.42, "finish": Finish.METAL, "wear": 0.5})
		"steel":
			return make({"albedo": Color(0.74, 0.78, 0.84), "accent": Color(0.2, 0.22, 0.26), "metallic": 0.95, "roughness": 0.2, "finish": Finish.METAL, "wear": 0.2})
		"mithril":
			return make({"albedo": Color(0.82, 0.9, 1.0), "accent": Color(0.4, 0.6, 0.9), "metallic": 0.97, "roughness": 0.14, "finish": Finish.METAL, "wear": 0.05,
				"emission_mode": Emit.SHIMMER, "emission_color": Color(0.45, 0.75, 1.0), "emission_energy": 0.9})
		"adamantite":
			return make({"albedo": Color(0.2, 0.5, 0.36), "accent": Color(0.04, 0.16, 0.1), "metallic": 0.95, "roughness": 0.24, "finish": Finish.METAL, "wear": 0.3,
				"emission_mode": Emit.FRESNEL, "emission_color": Color(0.15, 0.8, 0.45), "emission_energy": 0.25})
		"infernal":
			return make({"albedo": Color(0.3, 0.17, 0.13), "accent": Color(0.4, 0.1, 0.05), "metallic": 0.8, "roughness": 0.34, "finish": Finish.METAL, "wear": 0.3,
				"emission_mode": Emit.VEINS, "emission_color": Color(1.0, 0.4, 0.08), "emission_energy": 9.0, "detail_scale": 3.5})
		"gold":
			return make({"albedo": Color(1.0, 0.77, 0.34), "accent": Color(0.5, 0.3, 0.1), "metallic": 1.0, "roughness": 0.22, "finish": Finish.METAL, "wear": 0.15})
		"silver":
			return make({"albedo": Color(0.93, 0.94, 0.96), "accent": Color(0.2, 0.2, 0.25), "metallic": 1.0, "roughness": 0.18, "finish": Finish.METAL, "wear": 0.3})
		"tin":
			return make({"albedo": Color(0.78, 0.79, 0.78), "accent": Color(0.3, 0.3, 0.3), "metallic": 0.85, "roughness": 0.4, "finish": Finish.METAL, "wear": 0.3})
		"dark_iron":
			return make({"albedo": Color(0.22, 0.22, 0.23), "accent": Color(0.3, 0.15, 0.08), "metallic": 0.8, "roughness": 0.5, "finish": Finish.METAL, "wear": 0.6})
		"brass":
			return make({"albedo": Color(0.9, 0.72, 0.4), "accent": Color(0.3, 0.25, 0.1), "metallic": 0.95, "roughness": 0.28, "finish": Finish.METAL, "wear": 0.35})
		"rust":
			return make({"albedo": Color(0.5, 0.33, 0.24), "accent": Color(0.55, 0.25, 0.1), "metallic": 0.55, "roughness": 0.7, "finish": Finish.METAL, "wear": 0.9})
		"obsidian":
			return gem(Color(0.16, 0.08, 0.22), 0.12)
		"bone":
			return bone()
	return make({"albedo": Color(0.6, 0.6, 0.6), "metallic": 0.9, "roughness": 0.35, "finish": Finish.METAL})


## Decorative trim metal that goes with a tier (guards, pommels, rivets).
static func trim(tier: String) -> ShaderMaterial:
	match tier:
		"copper", "bronze":
			return metal("bronze")
		"iron":
			return metal("dark_iron")
		"steel":
			return metal("brass")
		"mithril":
			return metal("silver")
		"adamantite":
			return metal("gold")
		"infernal":
			return metal("dark_iron")
	return metal("iron")


# --- Organics ---------------------------------------------------------------------------

## grain: direction the wood fibres run in the mesh's local space.
static func wood(color := Color(0.5, 0.33, 0.19), knot := Color(0.25, 0.15, 0.08), grain := Vector3.UP) -> ShaderMaterial:
	return make({"albedo": color, "accent": knot, "roughness": 0.72, "finish": Finish.WOOD, "specular_amount": 0.35, "grain_dir": grain})


static func bark(color := Color(0.3, 0.22, 0.15)) -> ShaderMaterial:
	return make({"albedo": color, "accent": Color(0.28, 0.32, 0.16), "roughness": 0.95, "finish": Finish.BARK, "bump_amount": 2.0})


static func leather(color := Color(0.32, 0.19, 0.11)) -> ShaderMaterial:
	return make({"albedo": color, "roughness": 0.68, "finish": Finish.LEATHER, "specular_amount": 0.4, "ascii_id": AsciiMaterialId.CLOTH})


static func cloth(color: Color) -> ShaderMaterial:
	return make({"albedo": color, "roughness": 0.92, "finish": Finish.CLOTH, "specular_amount": 0.2, "ascii_id": AsciiMaterialId.CLOTH})


static func bone(color := Color(0.88, 0.84, 0.72)) -> ShaderMaterial:
	return make({"albedo": color, "accent": Color(0.6, 0.5, 0.35), "roughness": 0.55, "finish": Finish.BONE})


static func food(color: Color, roughness := 0.6) -> ShaderMaterial:
	return make({"albedo": color, "accent": color.darkened(0.35), "roughness": roughness, "finish": Finish.PLAIN, "specular_amount": 0.45})


# --- Minerals ---------------------------------------------------------------------------

static func stone(color: Color, accent := Color(0.3, 0.3, 0.3), roughness := 0.85, detail := 2.5) -> ShaderMaterial:
	return make({"albedo": color, "accent": accent, "roughness": roughness, "finish": Finish.STONE, "detail_scale": detail})


## Host rock with metallic flecks of `fleck`.
static func ore_rock(color: Color, fleck: Color) -> ShaderMaterial:
	return make({"albedo": color, "accent": fleck, "roughness": 0.85, "finish": Finish.ORE})


static func gem(color: Color, roughness := 0.06, glow := 0.0) -> ShaderMaterial:
	var p := {"albedo": color, "roughness": roughness, "finish": Finish.GEM, "bump_amount": 0.0}
	if glow > 0.0:
		p["emission_mode"] = Emit.FRESNEL
		p["emission_color"] = color
		p["emission_energy"] = glow
	return make(p)


## Glowing crystal / ember / magic part. Tagged EMISSIVE: passes through the ASCII grid and blooms.
static func glow(color: Color, energy := 3.0) -> ShaderMaterial:
	return make({"albedo": color * 0.3, "roughness": 0.4, "finish": Finish.PLAIN, "ascii_id": AsciiMaterialId.EMISSIVE,
		"emission_mode": Emit.UNIFORM, "emission_color": color, "emission_energy": energy, "bump_amount": 0.0})


static func molten(base: Color, glow_color: Color, energy := 6.0) -> ShaderMaterial:
	return make({"albedo": base, "accent": base.darkened(0.4), "roughness": 0.7, "finish": Finish.STONE,
		"emission_mode": Emit.VEINS, "emission_color": glow_color, "emission_energy": energy})


static func liquid(color: Color) -> ShaderMaterial:
	return make({"albedo": color, "roughness": 0.05, "finish": Finish.GEM, "bump_amount": 0.0, "sparkle_amount": 0.35,
		"emission_mode": Emit.FRESNEL, "emission_color": color, "emission_energy": 1.1})


static func glass(tint := Color(0.75, 0.88, 0.9)) -> ShaderMaterial:
	return make({"albedo": tint * 0.55, "roughness": 0.04, "finish": Finish.GEM, "bump_amount": 0.0, "sparkle_amount": 0.12})
