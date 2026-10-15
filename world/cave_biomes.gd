class_name CaveBiomes
extends RefCounted
## Aligned regions make the chamber field continuous across chunk boundaries.
## One crystal refuge in 32 regions; its rich deposits are finite and tier-gated.
## Revision 3 adds flooded grottos (chamber lakes; whole aquifers of neighbouring regions flood
## together, joined by underground rivers) and magma vaults in the deepest layer (lava pools).
enum Kind { KARST, GEYSER, FUNGAL, FROST, CRYSTAL_REFUGE, MAGMA, FLOODED }
const NAMES := ["Limestone Galleries", "Geyser Caverns", "Glowroot Hollows", "Glacial Grottos", "Crystal Sanctuary",
		"Magma Vaults", "Flooded Grottos"]
const CELL := Vector3(128, 64, 128)
## CaveDecor's kind for abandoned mine workings (no dripstone; rubble, webs, puddles).
const DECOR_MINE := 7
## Bounds of the current overworld's mine workings (set by WorldGen.prepare, read-only after).
static var mine_boxes: Array[AABB] = []


## Decoration kind at a point: mine workings, the regional chamber biome below y = -8, else karst.
static func decor_kind(pos: Vector3, seed_value: int) -> int:
	for b in mine_boxes:
		if b.has_point(pos):
			return DECOR_MINE
	return kind_at(pos, seed_value) if pos.y < -8.0 else Kind.KARST
const RADII := Vector3(48, 20, 48)


static func region(pos: Vector3, seed_value: int, revision := 3) -> Dictionary:
	var key := Vector3i((pos / CELL).floor())
	var h := WorldGen._hash3(key.x, key.y, key.z, seed_value + 902)
	var roll := h % 32
	var kind := Kind.CRYSTAL_REFUGE if roll == 0 else (Kind.GEYSER if roll < 8 else (Kind.FUNGAL if roll < 16 else (Kind.FROST if roll < 21 else Kind.KARST)))
	if revision >= 3 and kind != Kind.CRYSTAL_REFUGE:
		if key.y <= -2 and roll >= 21 and roll < 27:
			kind = Kind.MAGMA
		elif key.y == -1 and (roll >= 8 and roll < 16 or roll >= 21):
			# Aquifers: blocks of 2x2 regions flood together.
			var aquifer := WorldGen._hash3(key.x >> 1, 7, key.z >> 1, seed_value + 911) % 5
			if aquifer == 0:
				kind = Kind.FLOODED
	var center := (Vector3(key) + Vector3(0.5, 0.5, 0.5)) * CELL
	return {"key": key, "center": center, "kind": kind, "seed": h}


static func distance_to_chamber(pos: Vector3, region_data: Dictionary) -> float:
	return ((pos - (region_data["center"] as Vector3)) / RADII).length()


static func kind_at(pos: Vector3, seed_value: int, revision := 3) -> int:
	var r := region(pos, seed_value, revision)
	return int(r["kind"]) if distance_to_chamber(pos, r) < 1.14 else Kind.KARST


static func sanctuary(pos: Vector3, seed_value: int, revision := 3) -> bool:
	return pos.y < -8 and kind_at(pos, seed_value, revision) == Kind.CRYSTAL_REFUGE


## Height of the water (flooded) or lava (magma) pool filling a chamber's floor, or -INF.
static func pool_level(region_data: Dictionary) -> float:
	var kind := int(region_data["kind"])
	var c: Vector3 = region_data["center"]
	if kind == Kind.FLOODED:
		return c.y - RADII.y * 0.3
	if kind == Kind.MAGMA:
		return c.y - RADII.y * 0.42
	return -INF


## Chamber wall material; `floor_side` is 1 for the floor half of the chamber, 0 for the walls
## and roof (revision 3), -1 for the revision 2 palette.
static func wall_material(pos: Vector3i, kind: int, seed_value: int, floor_side := -1) -> int:
	var h := WorldGen._hash3(pos.x >> 3, pos.y >> 2, pos.z >> 3, seed_value + 907)
	if floor_side < 0:
		match kind:
			Kind.CRYSTAL_REFUGE:
				return [Blocks.AMETHYST, Blocks.RUBY_ORE, Blocks.SAPPHIRE_ORE, Blocks.GOLD_ORE, Blocks.SILVER_ORE, Blocks.MITHRIL_ORE, Blocks.MARBLE, Blocks.MARBLE][h % 8]
			Kind.GEYSER:
				return Blocks.COPPER_ORE if h % 11 == 0 else Blocks.BASALT
			Kind.FUNGAL:
				return Blocks.CLAY if h % 5 == 0 else Blocks.LIMESTONE
			Kind.FROST:
				return Blocks.CRYSTAL if h % 9 == 0 else Blocks.ICE
		return Blocks.LIMESTONE
	match kind:
		Kind.CRYSTAL_REFUGE:
			return [Blocks.AMETHYST, Blocks.RUBY_ORE, Blocks.SAPPHIRE_ORE, Blocks.GOLD_ORE, Blocks.SILVER_ORE, Blocks.MITHRIL_ORE, Blocks.MARBLE, Blocks.MARBLE][h % 8]
		Kind.GEYSER:
			if floor_side == 1 and h % 3 != 0:
				return Blocks.GEYSERITE
			return Blocks.COPPER_ORE if h % 11 == 0 else Blocks.BASALT
		Kind.FUNGAL:
			if floor_side == 1:
				return Blocks.MYCELIUM if h % 4 != 0 else Blocks.CLAY
			return Blocks.CLAY if h % 5 == 0 else Blocks.LIMESTONE
		Kind.FROST:
			return Blocks.CRYSTAL if h % 9 == 0 else Blocks.ICE
		Kind.MAGMA:
			if h % 5 == 0:
				return Blocks.OBSIDIAN
			return Blocks.MAGMA_ROCK if (floor_side == 1 and h % 2 == 0) or h % 7 == 0 else Blocks.BASALT
		Kind.FLOODED:
			return Blocks.FLOWSTONE if h % 3 != 0 else (Blocks.CLAY if floor_side == 1 else Blocks.LIMESTONE)
	if floor_side == 0 and h % 4 == 0:
		return Blocks.FLOWSTONE
	return Blocks.LIMESTONE
