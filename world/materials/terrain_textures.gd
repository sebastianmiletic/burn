class_name TerrainTextures
extends RefCounted
## The PBR texture arrays (CC0 Poly Haven sets, see CREDITS.md) and the
## per-material table shared by the smooth terrain shader and the crisp cube
## shader. A material code is a block id, or one of SmoothMesher's biome codes.

const ALBEDO_PATH := "res://assets/terrain/terrain_albedo.jpg"
const NORMAL_PATH := "res://assets/terrain/terrain_normal.webp"

# Texture array layers.
enum L { LUSH, DRY, DIRT, FOREST, ROCK, SAND, SNOW, TRAIL, MUD, ASH, DARK, MARBLE, SANDSTONE, CLAY, GRANITE,
	LIMESTONE, MOSSY, PLANKS, BARK, COBBLE, CASTLE, MOSSY_WALL, THATCH, CARVED }

const ASCII_SOLID := 0
const ASCII_GROUND := 4
const ASCII_EMISSIVE := 5
const ASCII_CLOTH := 6
const ASCII_LIQUID := 2

static var _albedo: TextureLayered
static var _normal: TextureLayered
static var _tables: Array = []


## code: [layer, cliff layer, tiles/m, roughness mult, tint, ascii class, ore colour, ore amount, emission, metallic]
static func _table() -> Dictionary:
	var t := {}
	var rock := [L.ROCK, L.ROCK, 0.22, 1.0, Color(0.92, 0.9, 0.88), ASCII_SOLID]
	var deep := [L.ROCK, L.ROCK, 0.22, 1.0, Color(0.52, 0.55, 0.62), ASCII_SOLID]
	var dark := [L.DARK, L.DARK, 0.2, 1.0, Color(0.85, 0.82, 0.82), ASCII_SOLID]
	t[Blocks.STONE] = rock
	t[Blocks.DIRT] = [L.DIRT, L.ROCK, 0.3, 1.0, Color(0.95, 0.9, 0.85), ASCII_GROUND]
	t[Blocks.GRASS] = [L.LUSH, L.DIRT, 0.28, 1.0, Color(0.95, 0.92, 0.8), ASCII_GROUND]
	t[Blocks.SAND] = [L.SAND, L.SANDSTONE, 0.3, 1.0, Color(1.0, 0.97, 0.9), ASCII_GROUND]
	t[Blocks.SNOW] = [L.SNOW, L.ROCK, 0.25, 1.0, Color(1.0, 1.0, 1.02), ASCII_GROUND]
	t[Blocks.ICE] = [L.SNOW, L.SNOW, 0.15, 0.2, Color(0.62, 0.78, 0.92), ASCII_LIQUID]
	t[Blocks.GRAVEL] = [L.TRAIL, L.ROCK, 0.35, 1.0, Color(0.95, 0.92, 0.88), ASCII_GROUND]
	t[Blocks.COAL_ORE] = rock + [Color(0.06, 0.06, 0.06), 0.55, Color(0, 0, 0), 0.0]
	t[Blocks.IRON_ORE] = rock + [Color(0.62, 0.38, 0.24), 0.5, Color(0, 0, 0), 0.3]
	t[Blocks.GOLD_ORE] = rock + [Color(0.95, 0.72, 0.25), 0.45, Color(0.05, 0.03, 0.0), 0.95]
	t[Blocks.EMBER_ORE] = dark + [Color(1.0, 0.45, 0.12), 0.55, Color(2.4, 0.9, 0.2), 0.0]
	t[Blocks.OBSIDIAN] = [L.DARK, L.DARK, 0.25, 0.25, Color(0.22, 0.17, 0.3), ASCII_SOLID]
	t[Blocks.BEDROCK] = [L.DARK, L.DARK, 0.2, 1.0, Color(0.35, 0.33, 0.33), ASCII_SOLID]
	t[Blocks.BASALT] = dark
	t[Blocks.ASH] = [L.ASH, L.DARK, 0.25, 1.0, Color(0.9, 0.86, 0.84), ASCII_GROUND]
	t[Blocks.BONE] = [L.LIMESTONE, L.LIMESTONE, 0.4, 0.9, Color(1.15, 1.1, 0.95), ASCII_SOLID]
	t[Blocks.HELLSTONE] = [L.DARK, L.DARK, 0.25, 0.8, Color(0.7, 0.3, 0.25), ASCII_SOLID, Color(1.0, 0.25, 0.08), 0.7, Color(2.2, 0.35, 0.08), 0.0]
	t[Blocks.DRY_GRASS] = [L.DRY, L.DIRT, 0.28, 1.0, Color(1.0, 0.95, 0.85), ASCII_GROUND]
	t[Blocks.CRYSTAL] = [L.SNOW, L.ROCK, 0.3, 0.2, Color(0.55, 0.85, 1.0), ASCII_SOLID, Color(0.6, 0.9, 1.0), 0.8, Color(0.9, 1.6, 2.2), 0.0]
	t[Blocks.DEEPSLATE] = deep
	t[Blocks.MUD] = [L.MUD, L.MUD, 0.3, 0.7, Color(0.9, 0.88, 0.85), ASCII_GROUND]
	t[Blocks.SOUL_SAND] = [L.SAND, L.ASH, 0.3, 1.0, Color(0.45, 0.33, 0.27), ASCII_GROUND]
	t[Blocks.GRANITE] = [L.GRANITE, L.GRANITE, 0.25, 1.0, Color(1.0, 0.92, 0.9), ASCII_SOLID]
	t[Blocks.SANDSTONE] = [L.SANDSTONE, L.SANDSTONE, 0.2, 1.0, Color(1.0, 0.95, 0.88), ASCII_SOLID]
	t[Blocks.MARBLE] = [L.MARBLE, L.MARBLE, 0.25, 0.7, Color(1.0, 1.0, 1.0), ASCII_SOLID]
	t[Blocks.SLATE] = [L.DARK, L.DARK, 0.3, 0.9, Color(0.75, 0.82, 0.95), ASCII_SOLID]
	t[Blocks.CLAY] = [L.CLAY, L.CLAY, 0.3, 0.9, Color(1.0, 0.95, 0.9), ASCII_GROUND]
	t[Blocks.LIMESTONE] = [L.LIMESTONE, L.LIMESTONE, 0.22, 1.0, Color(0.95, 0.95, 0.92), ASCII_SOLID]
	t[Blocks.COPPER_ORE] = rock + [Color(0.78, 0.42, 0.22), 0.5, Color(0, 0, 0), 0.75]
	t[Blocks.TIN_ORE] = rock + [Color(0.78, 0.8, 0.8), 0.45, Color(0, 0, 0), 0.6]
	t[Blocks.SILVER_ORE] = deep + [Color(0.88, 0.9, 0.95), 0.45, Color(0.02, 0.02, 0.03), 1.0]
	t[Blocks.MITHRIL_ORE] = deep + [Color(0.6, 0.85, 1.0), 0.5, Color(0.35, 0.8, 1.3), 1.0]
	t[Blocks.ADAMANTITE_ORE] = dark + [Color(0.3, 0.9, 0.45), 0.5, Color(0.2, 1.1, 0.4), 1.0]
	t[Blocks.RUBY_ORE] = deep + [Color(0.85, 0.06, 0.1), 0.4, Color(0.6, 0.02, 0.04), 0.3]
	t[Blocks.SAPPHIRE_ORE] = deep + [Color(0.1, 0.25, 0.95), 0.4, Color(0.03, 0.1, 0.7), 0.3]
	t[Blocks.AMETHYST] = deep + [Color(0.65, 0.35, 0.95), 0.85, Color(0.9, 0.35, 1.6), 0.2]
	# World revision 3: canyon, volcanic, tundra and cave-biome materials.
	t[Blocks.RED_ROCK] = [L.SANDSTONE, L.SANDSTONE, 0.18, 1.0, Color(1.22, 0.66, 0.44), ASCII_SOLID]
	t[Blocks.RED_SAND] = [L.SAND, L.SANDSTONE, 0.3, 1.0, Color(1.12, 0.72, 0.5), ASCII_GROUND]
	t[Blocks.UMBER_ROCK] = [L.CLAY, L.SANDSTONE, 0.2, 1.0, Color(0.82, 0.55, 0.42), ASCII_SOLID]
	t[Blocks.SCORIA] = [L.ASH, L.DARK, 0.3, 1.0, Color(0.78, 0.46, 0.38), ASCII_SOLID]
	t[Blocks.PERMAFROST] = [L.TRAIL, L.ROCK, 0.3, 0.9, Color(0.78, 0.82, 0.86), ASCII_GROUND]
	t[Blocks.FLOWSTONE] = [L.MARBLE, L.LIMESTONE, 0.3, 0.45, Color(1.02, 0.9, 0.72), ASCII_SOLID, Color(1.0, 0.94, 0.82), 0.2, Color(0, 0, 0), 0.0]
	t[Blocks.GEYSERITE] = [L.LIMESTONE, L.LIMESTONE, 0.35, 0.8, Color(1.08, 0.86, 0.62), ASCII_SOLID, Color(0.92, 0.42, 0.16), 0.35, Color(0, 0, 0), 0.0]
	t[Blocks.MYCELIUM] = [L.MUD, L.MOSSY, 0.35, 0.8, Color(0.72, 0.62, 0.78), ASCII_GROUND, Color(0.35, 0.9, 0.75), 0.18, Color(0.08, 0.4, 0.32), 0.0]
	t[Blocks.MAGMA_ROCK] = [L.DARK, L.DARK, 0.25, 0.9, Color(0.5, 0.36, 0.32), ASCII_SOLID, Color(1.0, 0.38, 0.08), 0.62, Color(3.2, 0.95, 0.18), 0.0]
	t[SmoothMesher.CODE_FOREST_FLOOR] = [L.FOREST, L.DIRT, 0.3, 1.0, Color(1.0, 0.93, 0.85), ASCII_GROUND]
	t[SmoothMesher.CODE_HELL_ASH] = [L.ASH, L.DARK, 0.25, 1.0, Color(0.75, 0.55, 0.5), ASCII_GROUND]
	t[SmoothMesher.CODE_PEAK_GRASS] = [L.LUSH, L.ROCK, 0.28, 1.0, Color(0.78, 0.82, 0.72), ASCII_GROUND]
	# Crisp cube blocks (voxel.gdshader).
	t[Blocks.PLANKS] = [L.PLANKS, L.PLANKS, 0.5, 1.0, Color(1.0, 0.92, 0.82), ASCII_SOLID]
	t[Blocks.CHEST] = [L.PLANKS, L.PLANKS, 0.5, 1.0, Color(0.85, 0.65, 0.45), ASCII_SOLID]
	t[Blocks.LOG] = [L.BARK, L.BARK, 0.6, 1.0, Color(0.95, 0.9, 0.85), ASCII_SOLID]
	t[Blocks.PINE_LOG] = [L.BARK, L.BARK, 0.6, 1.0, Color(0.7, 0.65, 0.6), ASCII_SOLID]
	t[Blocks.COBBLE] = [L.COBBLE, L.COBBLE, 0.4, 1.0, Color(0.95, 0.95, 0.95), ASCII_SOLID]
	t[Blocks.BRICK] = [L.CASTLE, L.CASTLE, 0.3, 1.0, Color(0.88, 0.86, 0.85), ASCII_SOLID]
	t[Blocks.MOSSY_COBBLE] = [L.MOSSY_WALL, L.MOSSY_WALL, 0.4, 1.0, Color(1, 1, 1), ASCII_SOLID]
	t[Blocks.THATCH] = [L.THATCH, L.THATCH, 0.45, 1.0, Color(1.0, 0.95, 0.85), ASCII_CLOTH]
	t[Blocks.RUNESTONE] = [L.CARVED, L.CARVED, 0.5, 1.0, Color(0.6, 0.58, 0.65), ASCII_SOLID, Color(1.0, 0.45, 0.15), 0.25, Color(2.0, 0.7, 0.2), 0.0]
	t[Blocks.GOLD_BLOCK] = [L.MARBLE, L.MARBLE, 0.4, 0.3, Color(1.0, 0.75, 0.35), ASCII_SOLID, Color(0, 0, 0), 0.0, Color(0, 0, 0), 1.0]
	t[Blocks.IRON_BARS] = [L.DARK, L.DARK, 0.6, 0.6, Color(0.5, 0.5, 0.55), ASCII_SOLID, Color(0, 0, 0), 0.0, Color(0, 0, 0), 0.8]
	return t


static func load_arrays() -> void:
	if _albedo == null and ResourceLoader.exists(ALBEDO_PATH):
		_albedo = load(ALBEDO_PATH)
		_normal = load(NORMAL_PATH)


static func tables() -> Array:
	if not _tables.is_empty():
		return _tables
	var a := PackedVector4Array()
	var tint := PackedVector4Array()
	var ore := PackedVector4Array()
	var emit := PackedVector4Array()
	a.resize(128)
	tint.resize(128)
	ore.resize(128)
	emit.resize(128)
	var t := _table()
	for code in 128:
		var e: Array = t.get(code, [L.ROCK, L.ROCK, 0.25, 1.0, Color(0.9, 0.9, 0.9), ASCII_SOLID])
		var c: Color = e[4]
		a[code] = Vector4(e[0], e[1], e[2], e[3])
		tint[code] = Vector4(c.r, c.g, c.b, e[5])
		if e.size() > 6:
			var oc: Color = e[6]
			var ec: Color = e[8]
			ore[code] = Vector4(oc.r, oc.g, oc.b, e[7])
			emit[code] = Vector4(ec.r, ec.g, ec.b, e[9])
	_tables = [a, tint, ore, emit]
	return _tables


static func apply(mat: ShaderMaterial) -> void:
	load_arrays()
	var tb := tables()
	mat.set_shader_parameter(&"albedo_tex", _albedo)
	mat.set_shader_parameter(&"normal_tex", _normal)
	mat.set_shader_parameter(&"mat_a", tb[0])
	mat.set_shader_parameter(&"mat_tint", tb[1])
	mat.set_shader_parameter(&"mat_ore", tb[2])
	mat.set_shader_parameter(&"mat_emit", tb[3])
