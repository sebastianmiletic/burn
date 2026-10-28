class_name CaveBiomes
extends RefCounted
## Aligned regions make the chamber field continuous across chunk boundaries.
## One crystal refuge in 32 regions; its rich deposits are finite and tier-gated.
## Revision 3 adds flooded grottos (chamber lakes; whole aquifers of neighbouring regions flood
## together, joined by underground rivers) and magma vaults in the deepest layer (lava pools).
## Revision 5 turns most plain limestone regions into distinct cave biomes (lush moss hollows,
## dripstone halls, ochre / verdigris / violet mineral caves, layered sandstone) and gives every
## chamber its own proportions (domes, towering halls, wide low galleries, long halls). The
## underground planner (world/underground/underground_plan.gd) adds `zones`: great caverns,
## lava tubes, the Everbloom cavern and Hearthold, which name and decorate their own volume.
enum Kind { KARST, GEYSER, FUNGAL, FROST, CRYSTAL_REFUGE, MAGMA, FLOODED,
	LUSH = 8, DRIPSTONE, OCHRE, VERDIGRIS, VIOLET, SANDSTONE, EVERBLOOM, CITY, TUBE }
const NAMES := ["Limestone Galleries", "Geyser Caverns", "Glowroot Hollows", "Glacial Grottos", "Crystal Sanctuary",
		"Magma Vaults", "Flooded Grottos", "Old Workings", "Mossdeep Hollows", "Dripstone Halls", "Ochre Caverns",
		"Verdigris Grottos", "Violet Deeps", "Sandstone Strata", "The Everbloom Cavern", "Hearthold", "Old Lava Tubes"]
const CELL := Vector3(128, 64, 128)
## CaveDecor's kind for abandoned mine workings (no dripstone; rubble, webs, puddles).
const DECOR_MINE := 7
## Bounds of the current overworld's mine workings (set by WorldGen.prepare, read-only after).
static var mine_boxes: Array[AABB] = []
## Revision of the current overworld (set by WorldGen.prepare) for callers without a WorldGen.
static var revision := 3
## Planned underground volumes of the current overworld (revision 5, set by WorldGen.prepare):
## [AABB, Kind, name]. Checked before the regional chambers by decor_kind, palette_at, zone_at.
static var zones: Array = []
## Region cells taken over by a planned site (revision 5): Vector3i -> Kind. Their own chamber
## is suppressed so the site's carvers alone shape the space.
static var special_cells := {}


## Decoration kind at a point: mine workings, planned zones, the regional chamber biome below
## y = -8, else karst.
static func decor_kind(pos: Vector3, seed_value: int) -> int:
	for b in mine_boxes:
		if b.has_point(pos):
			return DECOR_MINE
	var z := zone_at(pos)
	if not z.is_empty():
		return int(z[1])
	return kind_at(pos, seed_value, revision if revision >= 5 else 3) if pos.y < -8.0 else Kind.KARST


## The planned zone ([AABB, Kind, name]) containing a point, or [].
static func zone_at(pos: Vector3) -> Array:
	for z: Array in zones:
		if (z[0] as AABB).has_point(pos):
			return z
	return []


const RADII := Vector3(48, 20, 48)
## Revision 5 chamber proportions: dome, towering hall, wide low gallery, long halls (x / z).
## Every shape stays inside its 128 x 64 x 128 cell (with the wall noise) so the field is continuous.
const SHAPES := [Vector3(48, 20, 48), Vector3(34, 27, 34), Vector3(54, 12, 54), Vector3(54, 17, 30), Vector3(30, 17, 54), Vector3(42, 23, 42)]


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
	if revision < 5:
		return {"key": key, "center": center, "kind": kind, "seed": h}
	# Revision 5: plain limestone (and some geyser) regions become the new cave biomes.
	var h5 := WorldGen._hash3(key.x, key.y, key.z, seed_value + 917)
	if kind == Kind.KARST or (kind == Kind.GEYSER and roll >= 5):
		kind = [Kind.KARST, Kind.LUSH, Kind.DRIPSTONE, Kind.OCHRE, Kind.VERDIGRIS, Kind.VIOLET, Kind.SANDSTONE, Kind.DRIPSTONE,
				Kind.LUSH, Kind.KARST][h5 % 10]
		if kind == Kind.SANDSTONE and key.y <= -2:
			kind = Kind.OCHRE  # the sandstone beds lie near the surface
	var radii: Vector3 = SHAPES[(h5 >> 8) % SHAPES.size()]
	if kind == Kind.FLOODED or kind == Kind.MAGMA or kind == Kind.GEYSER:
		radii = RADII  # pools and vents keep the shape their rivers, passages and vents were planned for
	if special_cells.has(key):
		kind = int(special_cells[key])
		radii = Vector3(0.01, 0.01, 0.01)
	return {"key": key, "center": center, "kind": kind, "seed": h, "radii": radii}


## Chamber radii of a region (revision 5 varies them).
static func radii_of(region_data: Dictionary) -> Vector3:
	return region_data.get("radii", RADII)


static func distance_to_chamber(pos: Vector3, region_data: Dictionary) -> float:
	return ((pos - (region_data["center"] as Vector3)) / radii_of(region_data)).length()


static func kind_at(pos: Vector3, seed_value: int, revision := 3) -> int:
	var r := region(pos, seed_value, revision)
	return int(r["kind"]) if distance_to_chamber(pos, r) < 1.14 else Kind.KARST


static func sanctuary(pos: Vector3, seed_value: int, revision := 3) -> bool:
	return pos.y < -8 and kind_at(pos, seed_value, revision) == Kind.CRYSTAL_REFUGE


## Height of the water (flooded) or lava (magma) pool filling a chamber's floor, or -INF.
static func pool_level(region_data: Dictionary) -> float:
	var kind := int(region_data["kind"])
	var c: Vector3 = region_data["center"]
	var r := radii_of(region_data)
	if kind == Kind.FLOODED:
		return c.y - r.y * 0.3
	if kind == Kind.MAGMA:
		return c.y - r.y * 0.42
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
		Kind.LUSH, Kind.DRIPSTONE, Kind.OCHRE, Kind.VERDIGRIS, Kind.VIOLET, Kind.SANDSTONE, Kind.EVERBLOOM, Kind.CITY, Kind.TUBE:
			return scheme_block(kind, pos, floor_side == 1, h)
	if floor_side == 0 and h % 4 == 0:
		return Blocks.FLOWSTONE
	return Blocks.LIMESTONE


## Rock of the revision 5 cave biomes and of carved zones (CaveNetwork.F_SCHEME holds a Kind).
## `h` is a coarse hash of the voxel (patches of 8 x 4 x 8 m).
static func scheme_block(kind: int, pos: Vector3i, on_floor: bool, h: int) -> int:
	match kind:
		Kind.LUSH, Kind.EVERBLOOM:
			if on_floor:
				return Blocks.CAVE_MOSS if h % 5 != 0 else Blocks.MUD
			return Blocks.CAVE_MOSS if h % 3 == 0 else (Blocks.FLOWSTONE if h % 7 == 0 else Blocks.LIMESTONE)
		Kind.DRIPSTONE:
			if on_floor:
				return Blocks.FLOWSTONE if h % 4 != 0 else Blocks.CLAY
			return Blocks.FLOWSTONE if h % 3 != 0 else (Blocks.MARBLE if h % 5 == 0 else Blocks.LIMESTONE)
		Kind.OCHRE:
			if h % 13 == 0:
				return Blocks.IRON_ORE
			return Blocks.OCHRE_ROCK if ((pos.y >> 1) + (h & 1)) % 3 != 0 else Blocks.RUST_ROCK
		Kind.VERDIGRIS:
			if h % 9 == 0:
				return Blocks.COPPER_ORE
			if on_floor:
				return Blocks.TEAL_ROCK if h % 3 != 0 else Blocks.CLAY
			return Blocks.TEAL_ROCK if h % 4 != 0 else Blocks.SLATE
		Kind.VIOLET:
			if h % 12 == 0:
				return Blocks.AMETHYST
			if h % 5 != 0:
				return Blocks.VIOLET_ROCK
			return Blocks.OBSIDIAN if h % 10 == 0 else Blocks.SLATE
		Kind.SANDSTONE:
			if on_floor and h % 3 == 0:
				return Blocks.RED_SAND
			# Thin horizontal beds of buff, red, umber and ochre stone.
			return [Blocks.SANDSTONE, Blocks.RED_ROCK, Blocks.SANDSTONE, Blocks.UMBER_ROCK, Blocks.OCHRE_ROCK][posmod(pos.y, 10) >> 1]
		Kind.CITY:
			return Blocks.GRANITE if h % 4 != 0 else Blocks.SLATE
		Kind.TUBE:
			if on_floor and h % 5 == 0:
				return Blocks.SCORIA
			return Blocks.BASALT if h % 6 != 0 else Blocks.OBSIDIAN
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
	Kind.LUSH: {"fog": Color(0.016, 0.034, 0.014), "bounce": Color(0.07, 0.13, 0.05), "glow": Color(0.62, 1.0, 0.45), "haze": Color(0.6, 0.78, 0.5)},
	Kind.DRIPSTONE: {"fog": Color(0.036, 0.03, 0.022), "bounce": Color(0.14, 0.115, 0.08), "glow": Color(1.0, 0.78, 0.5), "haze": Color(0.8, 0.72, 0.6)},
	Kind.OCHRE: {"fog": Color(0.05, 0.028, 0.012), "bounce": Color(0.17, 0.095, 0.04), "glow": Color(1.0, 0.6, 0.25), "haze": Color(0.85, 0.62, 0.4)},
	Kind.VERDIGRIS: {"fog": Color(0.01, 0.034, 0.032), "bounce": Color(0.04, 0.13, 0.12), "glow": Color(0.3, 1.0, 0.8), "haze": Color(0.5, 0.8, 0.75)},
	Kind.VIOLET: {"fog": Color(0.028, 0.014, 0.045), "bounce": Color(0.1, 0.05, 0.15), "glow": Color(0.78, 0.45, 1.0), "haze": Color(0.68, 0.55, 0.85)},
	Kind.SANDSTONE: {"fog": Color(0.05, 0.034, 0.02), "bounce": Color(0.17, 0.12, 0.07), "glow": Color(1.0, 0.7, 0.4), "haze": Color(0.88, 0.72, 0.52)},
	Kind.EVERBLOOM: {"fog": Color(0.012, 0.04, 0.036), "bounce": Color(0.09, 0.2, 0.16), "glow": Color(0.55, 1.0, 0.8), "haze": Color(0.6, 0.9, 0.8)},
	Kind.CITY: {"fog": Color(0.05, 0.026, 0.012), "bounce": Color(0.2, 0.11, 0.05), "glow": Color(1.0, 0.55, 0.22), "haze": Color(0.9, 0.62, 0.4)},
	Kind.TUBE: {"fog": Color(0.03, 0.016, 0.012), "bounce": Color(0.09, 0.05, 0.035), "glow": Color(1.0, 0.4, 0.15), "haze": Color(0.7, 0.5, 0.4)},
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
	if dimension == 0 and revision >= 5:
		var z := zone_at(pos)
		if not z.is_empty():
			return PALETTES.get(int(z[1]), PALETTES[Kind.KARST])
	if pos.y < -60.0:
		return DEEP_PALETTE
	if revision >= 2 and pos.y < -8.0:
		return PALETTES.get(kind_at(pos, seed_value, revision), PALETTES[Kind.KARST])
	return PALETTES[Kind.KARST]
