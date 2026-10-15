class_name CaveBiomes
extends RefCounted
## Aligned regions make the chamber field continuous across chunk boundaries.
## One crystal refuge in 32 regions; its rich deposits are finite and tier-gated.
enum Kind { KARST, GEYSER, FUNGAL, FROST, CRYSTAL_REFUGE }
const NAMES := ["Limestone Galleries", "Geyser Caverns", "Glowroot Hollows", "Glacial Grottos", "Crystal Sanctuary"]
const CELL := Vector3(128, 64, 128)
const RADII := Vector3(48, 20, 48)

static func region(pos: Vector3, seed_value: int) -> Dictionary:
	var key := Vector3i((pos / CELL).floor())
	var h := WorldGen._hash3(key.x, key.y, key.z, seed_value + 902)
	var roll := h % 32
	var kind := Kind.CRYSTAL_REFUGE if roll == 0 else (Kind.GEYSER if roll < 8 else (Kind.FUNGAL if roll < 16 else (Kind.FROST if roll < 21 else Kind.KARST)))
	var center := (Vector3(key) + Vector3(0.5, 0.5, 0.5)) * CELL
	return {"key": key, "center": center, "kind": kind, "seed": h}

static func distance_to_chamber(pos: Vector3, region_data: Dictionary) -> float:
	return ((pos - (region_data["center"] as Vector3)) / RADII).length()

static func kind_at(pos: Vector3, seed_value: int) -> int:
	var r := region(pos, seed_value)
	return int(r["kind"]) if distance_to_chamber(pos, r) < 1.14 else Kind.KARST

static func sanctuary(pos: Vector3, seed_value: int) -> bool:
	return pos.y < -8 and kind_at(pos, seed_value) == Kind.CRYSTAL_REFUGE

static func wall_material(pos: Vector3i, kind: int, seed_value: int) -> int:
	var h := WorldGen._hash3(pos.x >> 3, pos.y >> 2, pos.z >> 3, seed_value + 907)
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
