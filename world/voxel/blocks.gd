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
## Natural tree trunks: collision and chopping only; Flora draws the tree.
const OAK_TRUNK := 41
const CRIMSON_TRUNK := 42
const PINE_TRUNK := 43
const DEAD_TRUNK := 44
# Rock strata
const GRANITE := 45
const SANDSTONE := 46
const MARBLE := 47
const SLATE := 48
const CLAY := 49
const LIMESTONE := 50
# Ores and gems (deeper is richer)
const COPPER_ORE := 51
const TIN_ORE := 52
const SILVER_ORE := 53
const MITHRIL_ORE := 54
const ADAMANTITE_ORE := 55
const RUBY_ORE := 56
const SAPPHIRE_ORE := 57
const AMETHYST := 58
## Invisible, unbreakable collision for modelled buildings (Architecture draws them).
const STRUCTURE := 59
# Rare trees: chopping needs a stronger axe (tier column).
const IRONWOOD_TRUNK := 60
const EMBERWOOD_TRUNK := 61
const RYFTWOOD_TRUNK := 62
## Ids 63..119 are reserved for the world-generation owner (cave, mountain, ocean
## and Ryft materials). Material codes 120..127 are SmoothMesher biome variants.
# World revision 3: new biomes and cave biomes.
const RED_ROCK := 63
const RED_SAND := 64
const SCORIA := 65
const PERMAFROST := 66
## Old-growth redwood (Elderwood): trunk column like the other trees.
const REDWOOD_TRUNK := 67
const UMBER_ROCK := 68
const FLOWSTONE := 69
const GEYSERITE := 70
const MYCELIUM := 71
const MAGMA_ROCK := 72
## Loose grey talus below mountain faces.
const SCREE := 73
## Fractured grey cliff rock of the high mountains.
const ALPINE_ROCK := 74
# World revision 4: sea beds.
## Pale, porous reef rock (coral reefs and lagoons).
const CORAL_ROCK := 75
## Soft grey-green sea-bed silt (seagrass meadows, the deep).
const SILT := 76
# World revision 5: the underground (cave biomes, the Everbloom, Hearthold).
## Springy green moss carpeting lush caves.
const CAVE_MOSS := 77
## Yellow-brown iron-stained rock of the ochre caverns.
const OCHRE_ROCK := 78
## Deep rust-red rock banded through the ochre caverns.
const RUST_ROCK := 79
## Copper-stained blue-green rock of the verdigris grottos.
const TEAL_ROCK := 80
## Dusky purple rock around the amethyst deeps.
const VIOLET_ROCK := 81
const COUNT := 82

## Block shape families used by the mesher.
enum Shape { CUBE, NONE, SMALL }
## How a block is drawn: SMOOTH terrain surface, crisp CUBE, SMALL prop, TREE (Flora), LIQUID, NONE.
enum Family { NONE, SMOOTH, CUBE, SMALL, TREE, LIQUID, STRUCTURE }

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
	["Castle brick", Color(0.33, 0.31, 0.3), AsciiMaterialId.SOLID, 1.8, 2, "brick", 0.0, true, true, false, Shape.CUBE],
	["Gravel", Color(0.45, 0.43, 0.41), AsciiMaterialId.GROUND, 0.5, 0, "gravel", 0.0, true, true, false, Shape.CUBE],
	["Coal ore", Color(0.25, 0.24, 0.24), AsciiMaterialId.SOLID, 1.3, 1, "coal", 0.0, true, true, false, Shape.CUBE],
	["Iron ore", Color(0.55, 0.45, 0.38), AsciiMaterialId.SOLID, 1.8, 2, "iron_ore", 0.0, true, true, false, Shape.CUBE],
	["Gold ore", Color(0.75, 0.62, 0.25), AsciiMaterialId.SOLID, 2.3, 3, "gold_ore", 0.0, true, true, false, Shape.CUBE],
	["Ember crystal", Color(1.0, 0.45, 0.15), AsciiMaterialId.EMISSIVE, 2.8, 4, "ember_crystal", 2.0, true, true, false, Shape.CUBE],
	["Obsidian", Color(0.1, 0.07, 0.12), AsciiMaterialId.SOLID, 6.0, 5, "obsidian", 0.0, true, true, false, Shape.CUBE],
	["Bedrock", Color(0.12, 0.12, 0.12), AsciiMaterialId.SOLID, -1.0, 99, "", 0.0, true, true, false, Shape.CUBE],
	["Water", Color(0.1, 0.16, 0.2), AsciiMaterialId.LIQUID, -1.0, 99, "", 0.0, false, false, true, Shape.CUBE],
	["Lava", Color(1.0, 0.35, 0.05), AsciiMaterialId.EMISSIVE, -1.0, 99, "", 3.0, false, false, true, Shape.CUBE],
	["Basalt", Color(0.2, 0.18, 0.18), AsciiMaterialId.SOLID, 1.6, 2, "basalt", 0.0, true, true, false, Shape.CUBE],
	["Ash", Color(0.3, 0.27, 0.26), AsciiMaterialId.GROUND, 0.4, 0, "ash", 0.0, true, true, false, Shape.CUBE],
	["Bone", Color(0.82, 0.78, 0.68), AsciiMaterialId.SOLID, 1.0, 1, "bone", 0.0, true, true, false, Shape.CUBE],
	["Hellstone", Color(0.75, 0.12, 0.08), AsciiMaterialId.EMISSIVE, 3.6, 6, "hellstone", 1.2, true, true, false, Shape.CUBE],
	["Thatch", Color(0.62, 0.5, 0.25), AsciiMaterialId.CLOTH, 0.3, 0, "thatch", 0.0, true, true, false, Shape.CUBE],
	["Pine log", Color(0.24, 0.17, 0.11), AsciiMaterialId.SOLID, 0.9, 0, "wood", 0.0, true, true, false, Shape.CUBE],
	["Pine needles", Color(0.13, 0.2, 0.13), AsciiMaterialId.FOLIAGE, 0.15, 0, "", 0.0, true, true, false, Shape.CUBE],
	["Mossy cobble", Color(0.32, 0.38, 0.27), AsciiMaterialId.SOLID, 1.3, 1, "cobble", 0.0, true, true, false, Shape.CUBE],
	["Torch", Color(1.0, 0.7, 0.35), AsciiMaterialId.EMISSIVE, 0.05, 0, "torch", 3.0, false, false, false, Shape.SMALL],
	["Gold block", Color(0.95, 0.75, 0.3), AsciiMaterialId.SOLID, 3.0, 3, "gold_ore", 0.0, true, true, false, Shape.CUBE],
	["Runestone", Color(0.3, 0.28, 0.32), AsciiMaterialId.SOLID, -1.0, 99, "", 0.6, true, true, false, Shape.CUBE],
	["Iron bars", Color(0.25, 0.25, 0.27), AsciiMaterialId.SOLID, -1.0, 99, "", 0.0, true, true, false, Shape.CUBE],
	["Chest", Color(0.5, 0.33, 0.15), AsciiMaterialId.SOLID, 0.6, 0, "", 0.0, true, true, false, Shape.CUBE],
	["Dry grass", Color(0.5, 0.42, 0.22), AsciiMaterialId.GROUND, 0.5, 0, "dirt", 0.0, true, true, false, Shape.CUBE],
	["Crimson leaves", Color(0.55, 0.08, 0.06), AsciiMaterialId.FOLIAGE, 0.15, 0, "", 0.0, true, true, false, Shape.CUBE],
	["Frost crystal", Color(0.55, 0.85, 1.0), AsciiMaterialId.EMISSIVE, 2.0, 3, "frost_shard", 1.5, true, true, false, Shape.CUBE],
	["Deepslate", Color(0.22, 0.22, 0.25), AsciiMaterialId.SOLID, 2.0, 2, "stone", 0.0, true, true, false, Shape.CUBE],
	["Mud", Color(0.2, 0.15, 0.1), AsciiMaterialId.GROUND, 0.45, 0, "dirt", 0.0, true, true, false, Shape.CUBE],
	["Soul sand", Color(0.3, 0.22, 0.18), AsciiMaterialId.GROUND, 0.5, 0, "soul_sand", 0.0, true, true, false, Shape.CUBE],
	["Lantern", Color(1.0, 0.75, 0.4), AsciiMaterialId.EMISSIVE, 0.3, 0, "lantern", 3.0, true, false, false, Shape.SMALL],
	["Oak", Color(0.33, 0.22, 0.13), AsciiMaterialId.SOLID, 0.9, 0, "wood", 0.0, true, true, false, Shape.NONE],
	["Crimson oak", Color(0.3, 0.2, 0.13), AsciiMaterialId.SOLID, 0.9, 0, "wood", 0.0, true, true, false, Shape.NONE],
	["Pine", Color(0.24, 0.17, 0.11), AsciiMaterialId.SOLID, 0.9, 0, "wood", 0.0, true, true, false, Shape.NONE],
	["Dead tree", Color(0.28, 0.24, 0.2), AsciiMaterialId.SOLID, 0.7, 0, "wood", 0.0, true, true, false, Shape.NONE],
	["Granite", Color(0.52, 0.45, 0.43), AsciiMaterialId.SOLID, 1.7, 2, "granite", 0.0, true, true, false, Shape.CUBE],
	["Sandstone", Color(0.74, 0.6, 0.42), AsciiMaterialId.SOLID, 0.9, 1, "sandstone", 0.0, true, true, false, Shape.CUBE],
	["Marble", Color(0.85, 0.84, 0.8), AsciiMaterialId.SOLID, 1.6, 2, "marble", 0.0, true, true, false, Shape.CUBE],
	["Slate", Color(0.27, 0.29, 0.32), AsciiMaterialId.SOLID, 1.4, 2, "slate", 0.0, true, true, false, Shape.CUBE],
	["Clay", Color(0.62, 0.45, 0.36), AsciiMaterialId.GROUND, 0.5, 0, "clay", 0.0, true, true, false, Shape.CUBE],
	["Limestone", Color(0.7, 0.68, 0.6), AsciiMaterialId.SOLID, 1.0, 1, "limestone", 0.0, true, true, false, Shape.CUBE],
	["Copper ore", Color(0.62, 0.42, 0.3), AsciiMaterialId.SOLID, 1.3, 1, "copper_ore", 0.0, true, true, false, Shape.CUBE],
	["Tin ore", Color(0.6, 0.6, 0.58), AsciiMaterialId.SOLID, 1.3, 1, "tin_ore", 0.0, true, true, false, Shape.CUBE],
	["Silver ore", Color(0.72, 0.74, 0.78), AsciiMaterialId.SOLID, 2.2, 3, "silver_ore", 0.0, true, true, false, Shape.CUBE],
	["Mithril ore", Color(0.55, 0.75, 0.85), AsciiMaterialId.SOLID, 3.4, 4, "mithril_ore", 0.4, true, true, false, Shape.CUBE],
	["Adamantite ore", Color(0.35, 0.65, 0.4), AsciiMaterialId.SOLID, 4.8, 5, "adamantite_ore", 0.4, true, true, false, Shape.CUBE],
	["Ruby ore", Color(0.7, 0.15, 0.18), AsciiMaterialId.SOLID, 2.6, 3, "ruby", 0.3, true, true, false, Shape.CUBE],
	["Sapphire ore", Color(0.2, 0.3, 0.75), AsciiMaterialId.SOLID, 2.6, 3, "sapphire", 0.3, true, true, false, Shape.CUBE],
	["Amethyst", Color(0.6, 0.35, 0.85), AsciiMaterialId.EMISSIVE, 2.0, 3, "amethyst", 1.0, true, true, false, Shape.CUBE],
	["Building", Color(0.52, 0.46, 0.35), AsciiMaterialId.SOLID, -1.0, 99, "", 0.0, true, true, false, Shape.NONE],
	["Ironwood", Color(0.25, 0.22, 0.18), AsciiMaterialId.SOLID, 3.0, 3, "ironwood", 0.0, true, true, false, Shape.NONE],
	["Emberwood", Color(0.42, 0.16, 0.08), AsciiMaterialId.SOLID, 4.0, 4, "emberwood", 0.0, true, true, false, Shape.NONE],
	["Ryftwood", Color(0.28, 0.22, 0.42), AsciiMaterialId.SOLID, 5.0, 5, "ryftwood", 0.0, true, true, false, Shape.NONE],
	["Red rock", Color(0.64, 0.33, 0.21), AsciiMaterialId.SOLID, 1.0, 1, "sandstone", 0.0, true, true, false, Shape.CUBE],
	["Red sand", Color(0.78, 0.46, 0.29), AsciiMaterialId.GROUND, 0.4, 0, "sand", 0.0, true, true, false, Shape.CUBE],
	["Scoria", Color(0.32, 0.19, 0.16), AsciiMaterialId.SOLID, 1.2, 1, "basalt", 0.0, true, true, false, Shape.CUBE],
	["Permafrost", Color(0.42, 0.42, 0.42), AsciiMaterialId.GROUND, 0.8, 0, "dirt", 0.0, true, true, false, Shape.CUBE],
	["Redwood", Color(0.45, 0.22, 0.14), AsciiMaterialId.SOLID, 1.2, 0, "wood", 0.0, true, true, false, Shape.NONE],
	["Umber rock", Color(0.45, 0.29, 0.21), AsciiMaterialId.SOLID, 1.0, 1, "sandstone", 0.0, true, true, false, Shape.CUBE],
	["Flowstone", Color(0.8, 0.72, 0.58), AsciiMaterialId.SOLID, 1.0, 1, "limestone", 0.0, true, true, false, Shape.CUBE],
	["Geyserite", Color(0.84, 0.66, 0.46), AsciiMaterialId.SOLID, 0.9, 1, "limestone", 0.0, true, true, false, Shape.CUBE],
	["Mycelium", Color(0.4, 0.35, 0.42), AsciiMaterialId.GROUND, 0.5, 0, "dirt", 0.0, true, true, false, Shape.CUBE],
	["Magma rock", Color(0.9, 0.32, 0.08), AsciiMaterialId.EMISSIVE, 1.8, 2, "basalt", 1.4, true, true, false, Shape.CUBE],
	["Scree", Color(0.5, 0.5, 0.49), AsciiMaterialId.GROUND, 0.6, 0, "gravel", 0.0, true, true, false, Shape.CUBE],
	["Mountain rock", Color(0.52, 0.53, 0.55), AsciiMaterialId.SOLID, 1.5, 1, "stone", 0.0, true, true, false, Shape.CUBE],
	["Coral rock", Color(0.86, 0.74, 0.66), AsciiMaterialId.SOLID, 0.9, 1, "limestone", 0.0, true, true, false, Shape.CUBE],
	["Silt", Color(0.36, 0.38, 0.33), AsciiMaterialId.GROUND, 0.4, 0, "clay", 0.0, true, true, false, Shape.CUBE],
	["Cave moss", Color(0.24, 0.36, 0.14), AsciiMaterialId.GROUND, 0.45, 0, "dirt", 0.0, true, true, false, Shape.CUBE],
	["Ochre rock", Color(0.7, 0.5, 0.22), AsciiMaterialId.SOLID, 1.0, 1, "stone", 0.0, true, true, false, Shape.CUBE],
	["Rust rock", Color(0.5, 0.22, 0.13), AsciiMaterialId.SOLID, 1.1, 1, "stone", 0.0, true, true, false, Shape.CUBE],
	["Verdigris rock", Color(0.22, 0.46, 0.42), AsciiMaterialId.SOLID, 1.2, 1, "stone", 0.0, true, true, false, Shape.CUBE],
	["Violet rock", Color(0.34, 0.24, 0.42), AsciiMaterialId.SOLID, 1.3, 1, "stone", 0.0, true, true, false, Shape.CUBE],
]

## Blocks drawn as the smooth terrain surface.
const SMOOTH_BLOCKS := [STONE, DIRT, GRASS, SAND, SNOW, ICE, GRAVEL, COAL_ORE, IRON_ORE, GOLD_ORE, EMBER_ORE,
		OBSIDIAN, BEDROCK, BASALT, ASH, BONE, HELLSTONE, DRY_GRASS, CRYSTAL, DEEPSLATE, MUD, SOUL_SAND,
		GRANITE, SANDSTONE, MARBLE, SLATE, CLAY, LIMESTONE, COPPER_ORE, TIN_ORE, SILVER_ORE, MITHRIL_ORE,
		ADAMANTITE_ORE, RUBY_ORE, SAPPHIRE_ORE, AMETHYST, THATCH,
		RED_ROCK, RED_SAND, SCORIA, PERMAFROST, UMBER_ROCK, FLOWSTONE, GEYSERITE, MYCELIUM, MAGMA_ROCK, SCREE, ALPINE_ROCK,
		CORAL_ROCK, SILT, CAVE_MOSS, OCHRE_ROCK, RUST_ROCK, TEAL_ROCK, VIOLET_ROCK]

static var _solid := PackedByteArray()
static var _opaque := PackedByteArray()
static var _liquid := PackedByteArray()
static var _class := PackedByteArray()
static var _colors := PackedColorArray()
static var _light := PackedFloat32Array()
static var _family := PackedByteArray()


static func _static_init() -> void:
	_solid.resize(256)
	_opaque.resize(256)
	_liquid.resize(256)
	_class.resize(256)
	_colors.resize(256)
	_light.resize(256)
	_family.resize(256)
	for i in DATA.size():
		var d: Array = DATA[i]
		_solid[i] = 1 if d[7] else 0
		_opaque[i] = 1 if d[8] else 0
		_liquid[i] = 1 if d[9] else 0
		_class[i] = d[2]
		_colors[i] = d[1]
		_light[i] = d[6]
		if i == AIR or i == LEAVES or i == PINE_LEAVES or i == CRIMSON_LEAVES:
			_family[i] = Family.NONE
			# Leaves are drawn by Flora now; old saves may still contain them.
			_solid[i] = 0
			_opaque[i] = 0
		elif d[9]:
			_family[i] = Family.LIQUID
		elif is_trunk(i):
			_family[i] = Family.TREE
		elif i == STRUCTURE:
			_family[i] = Family.STRUCTURE
		elif d[10] == Shape.SMALL:
			_family[i] = Family.SMALL
		elif i in SMOOTH_BLOCKS:
			_family[i] = Family.SMOOTH
		else:
			_family[i] = Family.CUBE


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


static func family(id: int) -> int:
	return _family[id]


static func is_smooth(id: int) -> bool:
	return _family[id] == Family.SMOOTH


static func is_trunk(id: int) -> bool:
	return (id >= OAK_TRUNK and id <= DEAD_TRUNK) or (id >= IRONWOOD_TRUNK and id <= RYFTWOOD_TRUNK) or id == REDWOOD_TRUNK


## Material family for sounds and debris: "stone", "dirt", "sand", "snow", "wood", "crystal", "metal".
static func sound_family(id: int) -> String:
	match id:
		DIRT, GRASS, DRY_GRASS, MUD, CLAY, ASH, SOUL_SAND, THATCH, LEAVES, PINE_LEAVES, CRIMSON_LEAVES, PERMAFROST, MYCELIUM:
			return "dirt"
		SAND, GRAVEL, RED_SAND, SCREE:
			return "sand"
		SNOW:
			return "snow"
		LOG, PINE_LOG, PLANKS, CHEST, OAK_TRUNK, CRIMSON_TRUNK, PINE_TRUNK, DEAD_TRUNK, IRONWOOD_TRUNK, EMBERWOOD_TRUNK, RYFTWOOD_TRUNK, REDWOOD_TRUNK:
			return "wood"
		ICE, CRYSTAL, AMETHYST, EMBER_ORE, RUBY_ORE, SAPPHIRE_ORE:
			return "crystal"
		IRON_BARS, GOLD_BLOCK:
			return "metal"
	return "stone"


static func family_table() -> PackedByteArray:
	return _family


static func is_breakable(id: int) -> bool:
	return id > AIR and id < DATA.size() and DATA[id][3] >= 0.0


## Lookup tables for the mesher (thread-safe: read-only after static init).
static func opaque_table() -> PackedByteArray:
	return _opaque


static func liquid_table() -> PackedByteArray:
	return _liquid


static func class_table() -> PackedByteArray:
	return _class


static func color_table() -> PackedColorArray:
	return _colors
