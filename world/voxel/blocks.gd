class_name Blocks
extends RefCounted
## Block type table. Ids are bytes stored in chunk data.
##
## Per block: display name, base colour, ASCII material class, hardness
## (seconds to mine with a tier-1 pickaxe), required pickaxe tier, the item it
## drops, light emission, and whether it is solid / opaque / liquid.

const AIR := 0
const STONE := 1
const DIRT := 2
const GRASS := 3
const SAND := 4
const SNOW := 5
const ICE := 6
const LOG := 7
const LEAVES := 8
const PLANKS := 9
const COBBLE := 10
const BRICK := 11
const GRAVEL := 12
const COAL_ORE := 13
const IRON_ORE := 14
const GOLD_ORE := 15
const EMBER_ORE := 16
const OBSIDIAN := 17
const BEDROCK := 18
const WATER := 19
const LAVA := 20
const BASALT := 21
const ASH := 22
const BONE := 23
const HELLSTONE := 24
const THATCH := 25
const PINE_LOG := 26
const PINE_LEAVES := 27
const MOSSY_COBBLE := 28
const TORCH := 29
const GOLD_BLOCK := 30
const RUNESTONE := 31
const IRON_BARS := 32
const CHEST := 33
const DRY_GRASS := 34
const CRIMSON_LEAVES := 35
const CRYSTAL := 36
const DEEPSLATE := 37
const MUD := 38
const SOUL_SAND := 39
const LANTERN := 40
const COUNT := 41

## Block shape families used by the mesher.
enum Shape { CUBE, NONE, SMALL }

# name, colour, ascii class, hardness, tier, drop item, light, solid, opaque, liquid, shape
const DATA := [
	["Air", Color(0, 0, 0), 0, 0.0, 0, "", 0.0, false, false, false, Shape.NONE],
	["Stone", Color(0.42, 0.41, 0.4), AsciiMaterialId.SOLID, 1.1, 1, "stone", 0.0, true, true, false, Shape.CUBE],
	["Dirt", Color(0.36, 0.25, 0.16), AsciiMaterialId.GROUND, 0.45, 0, "dirt", 0.0, true, true, false, Shape.CUBE],
	["Grass", Color(0.36, 0.42, 0.17), AsciiMaterialId.GROUND, 0.5, 0, "dirt", 0.0, true, true, false, Shape.CUBE],
	["Sand", Color(0.76, 0.66, 0.45), AsciiMaterialId.GROUND, 0.4, 0, "sand", 0.0, true, true, false, Shape.CUBE],
	["Snow", Color(0.9, 0.9, 0.92), AsciiMaterialId.GROUND, 0.35, 0, "snow", 0.0, true, true, false, Shape.CUBE],
	["Ice", Color(0.62, 0.75, 0.85), AsciiMaterialId.LIQUID, 0.6, 1, "", 0.0, true, true, false, Shape.CUBE],
	["Log", Color(0.33, 0.22, 0.13), AsciiMaterialId.SOLID, 0.9, 0, "wood", 0.0, true, true, false, Shape.CUBE],
	["Autumn leaves", Color(0.82, 0.42, 0.14), AsciiMaterialId.FOLIAGE, 0.15, 0, "", 0.0, true, true, false, Shape.CUBE],
	["Planks", Color(0.55, 0.38, 0.22), AsciiMaterialId.SOLID, 0.8, 0, "planks", 0.0, true, true, false, Shape.CUBE],
	["Cobblestone", Color(0.38, 0.37, 0.36), AsciiMaterialId.SOLID, 1.3, 1, "cobble", 0.0, true, true, false, Shape.CUBE],
	["Castle brick", Color(0.33, 0.31, 0.3), AsciiMaterialId.SOLID, 1.8, 1, "brick", 0.0, true, true, false, Shape.CUBE],
	["Gravel", Color(0.45, 0.43, 0.41), AsciiMaterialId.GROUND, 0.5, 0, "gravel", 0.0, true, true, false, Shape.CUBE],
	["Coal ore", Color(0.25, 0.24, 0.24), AsciiMaterialId.SOLID, 1.4, 1, "coal", 0.0, true, true, false, Shape.CUBE],
	["Iron ore", Color(0.55, 0.45, 0.38), AsciiMaterialId.SOLID, 1.8, 1, "iron_ore", 0.0, true, true, false, Shape.CUBE],
	["Gold ore", Color(0.75, 0.62, 0.25), AsciiMaterialId.SOLID, 2.2, 2, "gold_ore", 0.0, true, true, false, Shape.CUBE],
	["Ember crystal", Color(1.0, 0.45, 0.15), AsciiMaterialId.EMISSIVE, 2.6, 2, "ember_crystal", 2.0, true, true, false, Shape.CUBE],
	["Obsidian", Color(0.1, 0.07, 0.12), AsciiMaterialId.SOLID, 6.0, 3, "obsidian", 0.0, true, true, false, Shape.CUBE],
	["Bedrock", Color(0.12, 0.12, 0.12), AsciiMaterialId.SOLID, -1.0, 99, "", 0.0, true, true, false, Shape.CUBE],
	["Water", Color(0.1, 0.16, 0.2), AsciiMaterialId.LIQUID, -1.0, 99, "", 0.0, false, false, true, Shape.CUBE],
	["Lava", Color(1.0, 0.35, 0.05), AsciiMaterialId.EMISSIVE, -1.0, 99, "", 3.0, false, false, true, Shape.CUBE],
	["Basalt", Color(0.2, 0.18, 0.18), AsciiMaterialId.SOLID, 1.5, 1, "basalt", 0.0, true, true, false, Shape.CUBE],
	["Ash", Color(0.3, 0.27, 0.26), AsciiMaterialId.GROUND, 0.4, 0, "ash", 0.0, true, true, false, Shape.CUBE],
	["Bone", Color(0.82, 0.78, 0.68), AsciiMaterialId.SOLID, 1.0, 1, "bone", 0.0, true, true, false, Shape.CUBE],
	["Hellstone", Color(0.75, 0.12, 0.08), AsciiMaterialId.EMISSIVE, 3.0, 3, "hellstone", 1.2, true, true, false, Shape.CUBE],
	["Thatch", Color(0.62, 0.5, 0.25), AsciiMaterialId.CLOTH, 0.3, 0, "thatch", 0.0, true, true, false, Shape.CUBE],
	["Pine log", Color(0.24, 0.17, 0.11), AsciiMaterialId.SOLID, 0.9, 0, "wood", 0.0, true, true, false, Shape.CUBE],
	["Pine needles", Color(0.13, 0.2, 0.13), AsciiMaterialId.FOLIAGE, 0.15, 0, "", 0.0, true, true, false, Shape.CUBE],
	["Mossy cobble", Color(0.32, 0.38, 0.27), AsciiMaterialId.SOLID, 1.3, 1, "cobble", 0.0, true, true, false, Shape.CUBE],
	["Torch", Color(1.0, 0.7, 0.35), AsciiMaterialId.EMISSIVE, 0.05, 0, "torch", 3.0, false, false, false, Shape.SMALL],
	["Gold block", Color(0.95, 0.75, 0.3), AsciiMaterialId.SOLID, 3.0, 2, "gold_ore", 0.0, true, true, false, Shape.CUBE],
	["Runestone", Color(0.3, 0.28, 0.32), AsciiMaterialId.SOLID, -1.0, 99, "", 0.6, true, true, false, Shape.CUBE],
	["Iron bars", Color(0.25, 0.25, 0.27), AsciiMaterialId.SOLID, -1.0, 99, "", 0.0, true, true, false, Shape.CUBE],
	["Chest", Color(0.5, 0.33, 0.15), AsciiMaterialId.SOLID, 0.6, 0, "", 0.0, true, true, false, Shape.CUBE],
	["Dry grass", Color(0.5, 0.42, 0.22), AsciiMaterialId.GROUND, 0.5, 0, "dirt", 0.0, true, true, false, Shape.CUBE],
	["Crimson leaves", Color(0.55, 0.08, 0.06), AsciiMaterialId.FOLIAGE, 0.15, 0, "", 0.0, true, true, false, Shape.CUBE],
	["Frost crystal", Color(0.55, 0.85, 1.0), AsciiMaterialId.EMISSIVE, 2.0, 2, "frost_shard", 1.5, true, true, false, Shape.CUBE],
	["Deepslate", Color(0.22, 0.22, 0.25), AsciiMaterialId.SOLID, 1.8, 1, "stone", 0.0, true, true, false, Shape.CUBE],
	["Mud", Color(0.2, 0.15, 0.1), AsciiMaterialId.GROUND, 0.45, 0, "dirt", 0.0, true, true, false, Shape.CUBE],
	["Soul sand", Color(0.3, 0.22, 0.18), AsciiMaterialId.GROUND, 0.5, 0, "soul_sand", 0.0, true, true, false, Shape.CUBE],
	["Lantern", Color(1.0, 0.75, 0.4), AsciiMaterialId.EMISSIVE, 0.3, 0, "lantern", 3.0, true, false, false, Shape.SMALL],
]

static var _solid := PackedByteArray()
static var _opaque := PackedByteArray()
static var _liquid := PackedByteArray()
static var _class := PackedByteArray()
static var _colors := PackedColorArray()
static var _light := PackedFloat32Array()


static func _static_init() -> void:
	_solid.resize(256)
	_opaque.resize(256)
	_liquid.resize(256)
	_class.resize(256)
	_colors.resize(256)
	_light.resize(256)
	for i in DATA.size():
		var d: Array = DATA[i]
		_solid[i] = 1 if d[7] else 0
		_opaque[i] = 1 if d[8] else 0
		_liquid[i] = 1 if d[9] else 0
		_class[i] = d[2]
		_colors[i] = d[1]
		_light[i] = d[6]


static func name_of(id: int) -> String:
	return DATA[id][0] if id < DATA.size() else "?"


static func color(id: int) -> Color:
	return _colors[id]


static func ascii_class(id: int) -> int:
	return _class[id]


static func hardness(id: int) -> float:
	return DATA[id][3]


static func tier(id: int) -> int:
	return DATA[id][4]


static func drop(id: int) -> String:
	return DATA[id][5]


static func light(id: int) -> float:
	return _light[id]


static func is_solid(id: int) -> bool:
	return _solid[id] == 1


static func is_opaque(id: int) -> bool:
	return _opaque[id] == 1


static func is_liquid(id: int) -> bool:
	return _liquid[id] == 1


static func shape(id: int) -> int:
	return DATA[id][10]


static func is_breakable(id: int) -> bool:
	return id != AIR and DATA[id][3] >= 0.0


## Lookup tables for the mesher (thread-safe: read-only after static init).
static func opaque_table() -> PackedByteArray:
	return _opaque


static func liquid_table() -> PackedByteArray:
	return _liquid


static func class_table() -> PackedByteArray:
	return _class


static func color_table() -> PackedColorArray:
	return _colors
