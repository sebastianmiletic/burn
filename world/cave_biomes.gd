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
		return PALETTES.get(kind_at(pos, seed_value), PALETTES[Kind.KARST])
	return PALETTES[Kind.KARST]
