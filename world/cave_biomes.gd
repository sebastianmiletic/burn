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
			# Pale marble and flowstone with rich seams (a third of the walls), not wall-to-wall ore.
			if h % 3 != 0:
				return Blocks.MARBLE if h % 5 != 0 else Blocks.FLOWSTONE
			return [Blocks.AMETHYST, Blocks.RUBY_ORE, Blocks.SAPPHIRE_ORE, Blocks.GOLD_ORE, Blocks.SILVER_ORE, Blocks.MITHRIL_ORE][(h / 3) % 6]
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

## Underground light palette (linear HDR) for SkyController and the cave
## decorations: `fog` is the colour distance falls off into (dark, faintly
## tinted, never sky-coloured), `bounce` the fill light the rock gives back,
## `glow` the colour of the biome's own luminous things (fungi, crystals, lava),
## `haze` the volumetric fog albedo around torches.
const PALETTES := {
	Kind.KARST: {"fog": Color(0.0312, 0.0283, 0.0254), "bounce": Color(0.11, 0.095, 0.08), "glow": Color(1.0, 0.62, 0.32), "haze": Color(0.7, 0.62, 0.52)},
	Kind.GEYSER: {"fog": Color(0.0585, 0.0254, 0.0117), "bounce": Color(0.17, 0.085, 0.04), "glow": Color(1.0, 0.42, 0.14), "haze": Color(0.85, 0.62, 0.48)},
	Kind.FUNGAL: {"fog": Color(0.0117, 0.0429, 0.039), "bounce": Color(0.04, 0.15, 0.13), "glow": Color(0.2, 0.95, 0.72), "haze": Color(0.45, 0.8, 0.72)},
	Kind.FROST: {"fog": Color(0.0175, 0.0312, 0.0585), "bounce": Color(0.07, 0.11, 0.18), "glow": Color(0.45, 0.75, 1.0), "haze": Color(0.62, 0.75, 0.92)},
	Kind.MAGMA: {"fog": Color(0.066, 0.018, 0.0066), "bounce": Color(0.24, 0.075, 0.02), "glow": Color(1.0, 0.33, 0.07), "haze": Color(0.9, 0.48, 0.3)},
	Kind.FLOODED: {"fog": Color(0.008, 0.02, 0.026), "bounce": Color(0.05, 0.12, 0.15), "glow": Color(0.35, 0.8, 0.9), "haze": Color(0.55, 0.75, 0.82)},
	Kind.CRYSTAL_REFUGE: {"fog": Color(0.0331, 0.0156, 0.0585), "bounce": Color(0.13, 0.065, 0.19), "glow": Color(0.72, 0.38, 1.0), "haze": Color(0.72, 0.55, 0.9)},
}
## Deep lava caverns, worked mines, crypts and lairs (picked by location id).
const DEEP_PALETTE := {"fog": Color(0.078, 0.0215, 0.0078), "bounce": Color(0.22, 0.07, 0.02), "glow": Color(1.0, 0.35, 0.08), "haze": Color(0.9, 0.5, 0.32)}
const MINE_PALETTE := {"fog": Color(0.039, 0.0254, 0.0137), "bounce": Color(0.15, 0.09, 0.045), "glow": Color(1.0, 0.6, 0.28), "haze": Color(0.8, 0.62, 0.45)}
const CRYPT_PALETTE := {"fog": Color(0.0195, 0.0215, 0.0312), "bounce": Color(0.075, 0.08, 0.1), "glow": Color(0.55, 0.7, 1.0), "haze": Color(0.62, 0.66, 0.75)}
const LAIR_PALETTE := {"fog": Color(0.0234, 0.0292, 0.0175), "bounce": Color(0.085, 0.1, 0.06), "glow": Color(0.62, 0.9, 0.35), "haze": Color(0.66, 0.72, 0.55)}
const HELL_PALETTE := {"fog": Color(0.1073, 0.0234, 0.0097), "bounce": Color(0.3, 0.08, 0.03), "glow": Color(1.0, 0.3, 0.06), "haze": Color(0.9, 0.42, 0.25)}


## The palette at a position underground. `location_id` (may be empty) picks
## the hand-built places first.
static func palette_at(pos: Vector3, seed_value: int, dimension: int, revision: int, location_id := "") -> Dictionary:
	if dimension == 1:
		return HELL_PALETTE
	var id := location_id.to_lower()
	if id.contains("mine"):
		return MINE_PALETTE
	if id.contains("lair") or id.contains("brood") or id.contains("spider"):
		return LAIR_PALETTE
	if id.contains("crypt") or id.contains("tomb") or id.contains("hall"):
		return CRYPT_PALETTE
	if pos.y < -60.0:
		return DEEP_PALETTE
	if revision >= 2 and pos.y < -8.0:
		return PALETTES.get(kind_at(pos, seed_value, revision), PALETTES[Kind.KARST])
	return PALETTES[Kind.KARST]
