class_name CaveDecor
extends RefCounted
## Cave decorations drawn on the smooth terrain of a chunk, following the Flora contract:
##
## * plan_chunk()  WORKER THREAD, pure data: walks the chunk's terrain triangles, finds exposed
##                 ore, cave floors, walls and ceilings, and scatters decorations
##                 deterministically (one candidate per 1 m cell for ore, per 2 m cell and
##                 orientation for everything else). Returns MultiMesh buffers and up to two
##                 light points for glowing decor (fed into VoxelWorld's pooled lights).
## * build_chunk() main thread: one MultiMeshInstance3D per (mesh, material) batch.
## * warmup()      main thread, once: grows every template mesh and creates the materials.
##
## Ore nodules, crystals and geodes sit on exposed ore anywhere (also on cliffs); the rest
## depends on the cave biome (CaveBiomes.kind_at): limestone dripstone, webs and roots in
## karst, terraced sinter in geyser caves, giant glowing fungi in fungal hollows, icicles and
## ice crystals in glacial grottos, gem clusters in sanctuaries, basalt and glowing cracks in
## magma vaults, wet dripstone, moss and pools in flooded grottos. Purely decorative: mining
## the surrounding terrain re-plans the chunk, so decor on dug-away rock disappears with it.

const FLOATS := 16
const KARST := 0
const GEYSER := 1
const FUNGAL := 2
const FROST := 3
const CRYSTAL_REFUGE := 4
const MAGMA := 5
const FLOODED := 6
## Worked-out mine galleries (WorldGen may report this kind for mine tunnels): no dripstone,
## just fallen rock, standing water, cobwebs and roots.
const MINE := 7

# Template meshes (index into _meshes).
enum M { STALACTITE = 0, STALAGMITE = 3, ICICLES = 5, NODULES = 6, LENS = 8, CRYSTALS_SMALL = 10, CRYSTALS_LARGE = 12,
	GEODE = 14, SHARDS = 15, BASALT = 17, EMBER_CRACKS = 18, RUBBLE = 19, SINTER = 21, GLOWCAPS = 23, PUFFBALLS = 25,
	SHELF = 26, GIANT = 28, WEB_ORB = 30, WEB_DRAPE = 32, ROOTS = 33, MOSS = 35, PUDDLE = 37, CRUST = 39, COUNT = 41 }

# Materials (index into _mats, < 64).
enum T { R_KARST, R_WET, R_BASALT, R_SINTER, R_FROST, R_OCHRE, R_MARBLE,
	O_COAL, O_IRON, O_GOLD, O_EMBER, O_OBSIDIAN, O_FROST, O_COPPER, O_TIN, O_SILVER, O_MITHRIL, O_ADAMANT,
	O_RUBY, O_SAPPHIRE, O_AMETHYST, O_HELL, O_QUARTZ, ICE, EMBER_CRACK, GEM_EMERALD,
	F_GLOWCAP, F_PUFF, F_SHELF, F_GIANT, F_GIANT2, WEB, ROOT, MOSS, MOSS_GLOW, PUDDLE, PUDDLE_WARM, F_SHELF_PALE, COUNT }

# Placement modes.
const P_NORMAL := 0   # local +Y along the surface normal
const P_UPRIGHT := 1  # floor growth: mostly world up
const P_HANG := 2     # ceiling growth hanging straight down
const P_SHELF := 3    # wall brackets: +Y out of the wall, +Z world up
const P_WEB := 4      # orb web perpendicular to the wall
const P_FLAT := 5     # exactly level (pools)

# Fade classes (instance custom.a = metres / 200).
const F_SMALL := 0.15
const F_MED := 0.24
const F_LARGE := 0.6

## Ore block id -> [mesh, variants, material, min scale, max scale, extra mesh, extra material]
const ORES := {
	13: [M.LENS, 2, T.O_COAL, 0.8, 1.3, -1, -1],
	14: [M.CRUST, 2, T.O_IRON, 0.8, 1.4, -1, -1],
	15: [M.CRUST, 2, T.O_GOLD, 0.7, 1.2, M.CRYSTALS_SMALL, T.O_QUARTZ],
	16: [M.CRYSTALS_SMALL, 2, T.O_EMBER, 0.9, 1.5, -1, -1],
	17: [M.SHARDS, 2, T.O_OBSIDIAN, 0.7, 1.3, -1, -1],
	24: [M.SHARDS, 2, T.O_HELL, 0.7, 1.2, -1, -1],
	36: [M.CRYSTALS_SMALL, 2, T.O_FROST, 1.2, 2.0, -1, -1],
	51: [M.CRUST, 2, T.O_COPPER, 0.8, 1.4, -1, -1],
	52: [M.CRYSTALS_SMALL, 2, T.O_TIN, 0.6, 1.0, -1, -1],
	53: [M.CRUST, 2, T.O_SILVER, 0.7, 1.2, -1, -1],
	54: [M.CRYSTALS_SMALL, 2, T.O_MITHRIL, 0.9, 1.4, -1, -1],
	55: [M.CRYSTALS_SMALL, 2, T.O_ADAMANT, 0.9, 1.4, -1, -1],
	56: [M.CRYSTALS_SMALL, 2, T.O_RUBY, 0.8, 1.3, -1, -1],
	57: [M.CRYSTALS_SMALL, 2, T.O_SAPPHIRE, 0.8, 1.3, -1, -1],
	58: [M.GEODE, 1, T.O_AMETHYST, 0.8, 1.6, M.CRYSTALS_SMALL, T.O_AMETHYST],
}

## World revision 5 cave biomes (CaveBiomes.Kind >= 8) borrow the decoration of a related
## kind: moss caves and the Everbloom grow glowroot, violet deeps crystals, lava tubes embers.
const DECOR_ALIAS := {8: FUNGAL, 14: FUNGAL, 12: CRYSTAL_REFUGE, 16: MAGMA}
## Per cave kind: [floor entries, wall entries, ceiling entries]; entry =
## [mesh, variants, material, probability per cell, min scale, max scale, placement, fade, light colour, light strength]
const NONE := Color(0, 0, 0, 0)
static var TABLES := {
	KARST: [
		[[M.STALAGMITE, 2, T.R_KARST, 0.16, 0.5, 2.0, P_UPRIGHT, F_MED, NONE, 0.0],
			[M.RUBBLE, 2, T.R_KARST, 0.08, 0.6, 1.5, P_NORMAL, F_SMALL, NONE, 0.0],
			[M.PUDDLE, 2, T.PUDDLE, 0.06, 0.7, 1.6, P_FLAT, F_SMALL, NONE, 0.0],
			[M.GLOWCAPS, 2, T.F_GLOWCAP, 0.03, 0.8, 1.4, P_UPRIGHT, F_SMALL, Color(0.3, 0.85, 1.0), 1.2],
			[M.MOSS, 2, T.MOSS, 0.03, 0.7, 1.3, P_NORMAL, F_SMALL, NONE, 0.0]],
		[[M.WEB_ORB, 2, T.WEB, 0.035, 0.9, 1.7, P_WEB, F_SMALL, NONE, 0.0],
			[M.SHELF, 2, T.F_SHELF_PALE, 0.02, 0.7, 1.3, P_SHELF, F_SMALL, NONE, 0.0]],
		[[M.STALACTITE, 3, T.R_KARST, 0.24, 0.5, 2.6, P_HANG, F_MED, NONE, 0.0],
			[M.WEB_DRAPE, 1, T.WEB, 0.04, 0.8, 1.5, P_HANG, F_SMALL, NONE, 0.0]],
	],
	GEYSER: [
		[[M.SINTER, 2, T.R_SINTER, 0.08, 0.7, 1.6, P_FLAT, F_MED, NONE, 0.0],
			[M.RUBBLE, 2, T.R_OCHRE, 0.07, 0.6, 1.4, P_NORMAL, F_SMALL, NONE, 0.0],
			[M.PUDDLE, 2, T.PUDDLE_WARM, 0.06, 0.6, 1.4, P_FLAT, F_SMALL, NONE, 0.0]],
		[[M.NODULES, 2, T.O_COPPER, 0.03, 0.6, 1.0, P_NORMAL, F_SMALL, NONE, 0.0]],
		[[M.STALACTITE, 3, T.R_OCHRE, 0.16, 0.4, 1.6, P_HANG, F_MED, NONE, 0.0]],
	],
	FUNGAL: [
		[[M.GIANT, 2, T.F_GIANT, 0.05, 1.8, 4.6, P_UPRIGHT, F_LARGE, Color(0.6, 0.45, 1.0), 2.4],
			[M.GIANT, 2, T.F_GIANT2, 0.035, 1.6, 3.8, P_UPRIGHT, F_LARGE, Color(0.3, 1.0, 0.8), 2.2],
			[M.GLOWCAPS, 2, T.F_GLOWCAP, 0.2, 0.8, 1.8, P_UPRIGHT, F_SMALL, Color(0.3, 0.85, 1.0), 1.4],
			[M.PUFFBALLS, 1, T.F_PUFF, 0.13, 0.8, 1.6, P_UPRIGHT, F_SMALL, Color(0.5, 1.0, 0.4), 1.1],
			[M.MOSS, 2, T.MOSS_GLOW, 0.22, 0.8, 1.8, P_NORMAL, F_SMALL, NONE, 0.0]],
		[[M.SHELF, 2, T.F_SHELF, 0.2, 0.8, 1.6, P_SHELF, F_SMALL, Color(1.0, 0.6, 0.25), 0.9],
			[M.MOSS, 2, T.MOSS_GLOW, 0.1, 0.6, 1.2, P_NORMAL, F_SMALL, NONE, 0.0]],
		[[M.ROOTS, 2, T.ROOT, 0.14, 0.8, 1.5, P_HANG, F_MED, NONE, 0.0],
			[M.STALACTITE, 3, T.R_WET, 0.1, 0.4, 1.4, P_HANG, F_MED, NONE, 0.0]],
	],
	FROST: [
		[[M.CRYSTALS_LARGE, 2, T.O_FROST, 0.06, 0.7, 2.2, P_UPRIGHT, F_LARGE, Color(0.55, 0.85, 1.0), 2.0],
			[M.STALAGMITE, 2, T.R_FROST, 0.1, 0.5, 1.6, P_UPRIGHT, F_MED, NONE, 0.0],
			[M.CRYSTALS_SMALL, 2, T.O_FROST, 0.08, 1.0, 2.0, P_NORMAL, F_SMALL, NONE, 0.0]],
		[[M.CRYSTALS_SMALL, 2, T.O_FROST, 0.06, 1.0, 1.8, P_NORMAL, F_SMALL, NONE, 0.0]],
		[[M.ICICLES, 1, T.ICE, 0.42, 0.6, 2.2, P_HANG, F_MED, NONE, 0.0],
			[M.STALACTITE, 3, T.R_FROST, 0.1, 0.4, 1.6, P_HANG, F_MED, NONE, 0.0]],
	],
	CRYSTAL_REFUGE: [
		[[M.CRYSTALS_LARGE, 2, T.O_AMETHYST, 0.09, 0.8, 3.2, P_UPRIGHT, F_LARGE, Color(0.75, 0.4, 1.0), 2.6],
			[M.CRYSTALS_LARGE, 2, T.O_SAPPHIRE, 0.06, 0.7, 2.6, P_UPRIGHT, F_LARGE, Color(0.35, 0.55, 1.0), 2.4],
			[M.CRYSTALS_LARGE, 2, T.GEM_EMERALD, 0.05, 0.7, 2.4, P_UPRIGHT, F_LARGE, Color(0.35, 1.0, 0.55), 2.2],
			[M.CRYSTALS_LARGE, 2, T.O_RUBY, 0.03, 0.6, 2.0, P_UPRIGHT, F_LARGE, Color(1.0, 0.3, 0.35), 2.0],
			[M.PUDDLE, 2, T.PUDDLE, 0.04, 0.6, 1.4, P_FLAT, F_SMALL, NONE, 0.0]],
		[[M.CRYSTALS_SMALL, 2, T.O_AMETHYST, 0.12, 1.2, 2.4, P_NORMAL, F_SMALL, NONE, 0.0]],
		[[M.CRYSTALS_LARGE, 2, T.O_AMETHYST, 0.1, 0.5, 1.6, P_NORMAL, F_LARGE, Color(0.75, 0.4, 1.0), 1.8],
			[M.STALACTITE, 3, T.R_MARBLE, 0.12, 0.4, 1.8, P_HANG, F_MED, NONE, 0.0]],
	],
	MAGMA: [
		[[M.BASALT, 1, T.R_BASALT, 0.12, 0.8, 2.4, P_UPRIGHT, F_LARGE, NONE, 0.0],
			[M.EMBER_CRACKS, 1, T.EMBER_CRACK, 0.15, 0.9, 2.2, P_FLAT, F_MED, Color(1.0, 0.4, 0.1), 2.0],
			[M.SHARDS, 2, T.O_OBSIDIAN, 0.08, 0.8, 1.8, P_UPRIGHT, F_SMALL, NONE, 0.0],
			[M.RUBBLE, 2, T.R_BASALT, 0.07, 0.6, 1.5, P_NORMAL, F_SMALL, NONE, 0.0]],
		[[M.SHARDS, 2, T.O_OBSIDIAN, 0.04, 0.6, 1.2, P_NORMAL, F_SMALL, NONE, 0.0]],
		[[M.STALACTITE, 3, T.R_BASALT, 0.12, 0.4, 1.4, P_HANG, F_MED, NONE, 0.0]],
	],
	MINE: [
		[[M.RUBBLE, 2, T.R_KARST, 0.07, 0.4, 1.0, P_NORMAL, F_SMALL, NONE, 0.0],
			[M.PUDDLE, 2, T.PUDDLE, 0.06, 0.5, 0.9, P_FLAT, F_SMALL, NONE, 0.0]],
		[[M.WEB_ORB, 2, T.WEB, 0.05, 0.8, 1.4, P_WEB, F_SMALL, NONE, 0.0],
			[M.SHELF, 2, T.F_SHELF_PALE, 0.02, 0.5, 0.9, P_SHELF, F_SMALL, NONE, 0.0]],
		[[M.WEB_DRAPE, 1, T.WEB, 0.08, 0.7, 1.3, P_HANG, F_SMALL, NONE, 0.0]],
	],
	FLOODED: [
		[[M.STALAGMITE, 2, T.R_WET, 0.15, 0.5, 1.8, P_UPRIGHT, F_MED, NONE, 0.0],
			[M.PUDDLE, 2, T.PUDDLE, 0.15, 0.7, 1.8, P_FLAT, F_SMALL, NONE, 0.0],
			[M.MOSS, 2, T.MOSS, 0.12, 0.8, 1.6, P_NORMAL, F_SMALL, NONE, 0.0]],
		[[M.MOSS, 2, T.MOSS, 0.1, 0.6, 1.3, P_NORMAL, F_SMALL, NONE, 0.0],
			[M.SHELF, 2, T.F_SHELF_PALE, 0.02, 0.6, 1.1, P_SHELF, F_SMALL, NONE, 0.0]],
		[[M.STALACTITE, 3, T.R_WET, 0.4, 0.5, 2.6, P_HANG, F_MED, NONE, 0.0]],
	],
}

## Visibility (m) per fade class at fade_scale 1; quality scales these.
const FADE_SCALE := [0.65, 0.8, 1.0, 1.25]

static var _meshes: Array[Mesh] = []
static var _mats: Array[ShaderMaterial] = []
static var _quality := -1
static var _ore_lut := PackedInt32Array()
static var warmup_ms := 0.0
## Profiling switch: `--no-cave-decor` on the command line disables all decor.
static var enabled := not ("--no-cave-decor" in OS.get_cmdline_user_args())


# =========================================================================== worker side

static func _h01(x: int, y: int, z: int, s: int) -> float:
	return float(WorldGen._hash3(x, y, z, s) & 0xffff) / 65535.0


## WORKER THREAD. terrain: SmoothMesher "terrain" arrays (chunk-local unindexed triangles).
## blocks (optional): the chunk's block ids, used to light exposed lava.
## force_kind >= 0 overrides the cave biome (galleries, tests).
static func plan_chunk(origin: Vector3i, terrain: Array, dimension: int, world_seed: int, blocks := PackedByteArray(), force_kind := -1) -> Dictionary:
	var verts: PackedVector3Array = terrain[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = terrain[Mesh.ARRAY_NORMAL]
	var custom: PackedFloat32Array = terrain[Mesh.ARRAY_CUSTOM0]
	var uv2: PackedVector2Array = terrain[Mesh.ARRAY_TEX_UV2]
	var ntri := mini(verts.size(), uv2.size()) / 3
	if not enabled or ntri == 0 or custom.size() < ntri * 12:
		return {}
	var o := Vector3(origin)
	var ore_seen := PackedByteArray()
	ore_seen.resize(18 * 18 * 18)
	var cell_seen := PackedByteArray()
	cell_seen.resize(10 * 10 * 10 * 3)
	var kinds := PackedInt32Array()
	kinds.resize(125)
	kinds.fill(-1)
	var batches := {}
	var glow: Array = []   # [strength, Vector3 world, Color]
	var hell := dimension == 1
	var chunk_hash := WorldGen._hash3(origin.x, origin.y, origin.z, world_seed + 77)
	var seed_ore := world_seed + 5501
	var seed_dec := world_seed + 6607
	for t in ntri:
		var i := t * 3
		var sky := uv2[i].x
		var ci := i * 4
		var code := int(custom[ci])
		var ore: Variant = ORES.get(code)
		if ore == null:
			code = int(custom[ci + 1])
			ore = ORES.get(code)
			if ore == null:
				code = int(custom[ci + 2])
				ore = ORES.get(code)
		if ore == null and sky >= 0.9:
			continue
		var p := (verts[i] + verts[i + 1] + verts[i + 2]) / 3.0
		var n := (norms[i] + norms[i + 1] + norms[i + 2]).normalized()
		if ore != null:
			var cx := clampi(int(floorf(p.x)) + 1, 0, 17)
			var cy := clampi(int(floorf(p.y)) + 1, 0, 17)
			var cz := clampi(int(floorf(p.z)) + 1, 0, 17)
			var oi := cx + cy * 18 + cz * 324
			if ore_seen[oi] != 0:
				continue
			ore_seen[oi] = 1
			var wx := origin.x + cx
			var wy := origin.y + cy
			var wz := origin.z + cz
			if _h01(wx, wy, wz, seed_ore) > 0.5:
				continue
			var e: Array = ore
			var r2 := _h01(wx, wy, wz, seed_ore + 1)
			var s := lerpf(float(e[3]), float(e[4]), r2)
			# One template variant per chunk and kind keeps the batch (draw call) count low;
			# instances still differ in scale, spin and tint.
			var mesh_id: int = int(e[0]) + ((chunk_hash + code) % int(e[1]))
			var xf := _basis(n, P_NORMAL, _h01(wx, wy, wz, seed_ore + 3) * TAU)
			_add(batches, mesh_id, int(e[2]), xf.scaled(Vector3.ONE * s), p - n * 0.04 * s,
				Color(r2, _h01(wx, wy, wz, seed_ore + 4), 0.6 + r2 * 0.6, F_SMALL))
			if int(e[5]) >= 0 and r2 < 0.5:
				var off := xf * Vector3(0.18, 0, 0.1) * s
				_add(batches, int(e[5]), int(e[6]), _basis(n, P_NORMAL, r2 * 9.0).scaled(Vector3.ONE * s * 0.8), p + off - n * 0.03, Color(r2, 0.3, 0.6, F_SMALL))
			continue
		# Cave surfaces only.
		var cls := 0
		if n.y > 0.6:
			cls = 0
		elif n.y < -0.55:
			cls = 2
		else:
			cls = 1
		if (cls != 2 and sky >= 0.45) or (cls == 2 and sky >= 0.85):
			continue
		var gx := clampi(int(floorf(p.x * 0.5)) + 1, 0, 9)
		var gy := clampi(int(floorf(p.y * 0.5)) + 1, 0, 9)
		var gz := clampi(int(floorf(p.z * 0.5)) + 1, 0, 9)
		var gi := (gx + gy * 10 + gz * 100) * 3 + cls
		if cell_seen[gi] != 0:
			continue
		cell_seen[gi] = 1
		var wx := origin.x * 1 + gx * 2
		var wy := origin.y + gy * 2
		var wz := origin.z + gz * 2
		var r := _h01(wx, wy * 3 + cls, wz, seed_dec)
		var kind := MAGMA if hell else KARST
		if force_kind >= 0:
			kind = force_kind
		elif not hell:
			var ki := clampi(int(floorf((p.x + 1.0) * 0.25)), 0, 4) + clampi(int(floorf((p.y + 1.0) * 0.25)), 0, 4) * 5 + clampi(int(floorf((p.z + 1.0) * 0.25)), 0, 4) * 25
			kind = kinds[ki]
			if kind < 0:
				var wp := o + p
				kind = CaveBiomes.decor_kind(wp, world_seed)
				kind = int(DECOR_ALIAS.get(kind, kind))
				if not TABLES.has(kind):
					kind = KARST
				kinds[ki] = kind
		var entries: Array = TABLES[kind][cls]
		# Hanging roots grow only a few metres under the surface (sky term > 0.05).
		if cls == 2 and sky > 0.05 and sky < 0.9 and kind in [KARST, FLOODED, FUNGAL] and r < 0.3:
			var rs := lerpf(0.7, 1.5, _h01(wx, wy, wz, seed_dec + 9))
			_add(batches, M.ROOTS + (int(r * 100.0) & 1), T.ROOT, _basis(n, P_HANG, r * 40.0).scaled(Vector3.ONE * rs), p + Vector3(0, 0.05, 0),
				Color(r, _h01(wx, wy, wz, seed_dec + 3), 0.0, F_MED))
			continue
		if cls == 2 and sky >= 0.6:
			continue
		var acc := 0.0
		for entry: Array in entries:
			acc += float(entry[3])
			if r >= acc:
				continue
			var placement: int = entry[6]
			if placement == P_FLAT and n.y < (0.965 if int(entry[0]) == M.PUDDLE else 0.9):
				break
			if int(entry[0]) == M.WEB_ORB and (sky > 0.3 or n.y < -0.2):
				break
			var r2 := _h01(wx, wy, wz, seed_dec + 1)
			var s := lerpf(float(entry[4]), float(entry[5]), r2 * r2)
			var variant := (chunk_hash + int(entry[0])) % int(entry[1])
			var spin := _h01(wx, wy, wz, seed_dec + 4) * TAU
			var b := _basis(n, placement, spin)
			var sc := Vector3.ONE * s
			var pos := p
			match placement:
				P_HANG:
					var th := lerpf(0.75, 1.3, _h01(wx, wy, wz, seed_dec + 5))
					sc = Vector3(s * th, s, s * th) if int(entry[0]) == M.STALACTITE else sc
					pos = p + Vector3(0, 0.06 * s, 0)
				P_UPRIGHT:
					var th := lerpf(0.8, 1.25, _h01(wx, wy, wz, seed_dec + 5))
					sc = Vector3(s * th, s, s * th)
					pos = p - Vector3(0, 0.05, 0)
				P_FLAT:
					pos = p + Vector3(0, 0.03 if int(entry[0]) == M.PUDDLE else -0.02, 0)
					if int(entry[0]) == M.PUDDLE:
						sc = Vector3.ONE * minf(s, 0.9)
				P_WEB:
					pos = p + n * 0.42 * s + Vector3(0, 0.3 * s, 0)
				P_SHELF:
					pos = p - n * 0.04
				_:
					pos = p - n * 0.03 * s
			var lit: Color = entry[8]
			_add(batches, int(entry[0]) + variant, int(entry[2]), b.scaled(sc), pos,
				Color(r2, _h01(wx, wy, wz, seed_dec + 6), 0.6 + r2 * 0.7, float(entry[7])))
			if lit.a > 0.0:
				glow.append([float(entry[9]) * (0.7 + 0.3 * s), o + pos + b.y * s * 0.5, lit])
			break
	# Exposed lava lights up its cavern.
	if not blocks.is_empty() and dimension == 0 and blocks.find(Blocks.LAVA) >= 0:
		var lava := _lava_point(blocks)
		if lava != Vector3.INF:
			glow.append([9.0, o + lava, Color(1.0, 0.42, 0.12)])
	var lights: Array = []
	glow.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for g: Array in glow:
		var ok := true
		for l: Array in lights:
			if (l[0] as Vector3).distance_squared_to(g[1]) < 49.0:
				ok = false
				break
		if ok:
			lights.append([g[1], g[2], minf(float(g[0]), 3.2)])
			if lights.size() >= 2:
				break
	if batches.is_empty() and lights.is_empty():
		return {}
	var out := {}
	for key: int in batches:
		var bt: Array = batches[key]
		var lo: Vector3 = bt[2]
		var hi: Vector3 = bt[3]
		out[key] = [bt[0], bt[1], AABB(lo - Vector3(5, 5, 5), hi - lo + Vector3(10, 10, 10))]
	return {"batches": out, "lights": lights}


static func _lava_point(blocks: PackedByteArray) -> Vector3:
	var best := Vector3.INF
	var best_d := 1e9
	for y in range(0, 15, 2):
		for z in range(1, 16, 3):
			for x in range(1, 16, 3):
				var i := x + z * 16 + y * 256
				if blocks[i] == Blocks.LAVA and blocks[i + 256] == Blocks.AIR:
					var p := Vector3(x + 0.5, y + 1.6, z + 0.5)
					var d := p.distance_squared_to(Vector3(8, 8, 8))
					if d < best_d:
						best_d = d
						best = p
	return best


static func _basis(n: Vector3, placement: int, spin: float) -> Basis:
	var y := n
	match placement:
		P_UPRIGHT:
			y = (Vector3.UP * 3.0 + n).normalized()
		P_HANG:
			y = (Vector3.UP * 4.0 - n).normalized()
		P_FLAT:
			y = Vector3.UP
		P_SHELF:
			var out := Vector3(n.x, 0, n.z)
			out = out.normalized() if out.length_squared() > 0.01 else Vector3.FORWARD
			var up := Vector3.UP
			return Basis(out.cross(up).normalized(), out, up).rotated(out, (spin - PI) * 0.08)
		P_WEB:
			var out := Vector3(n.x, 0, n.z)
			out = out.normalized() if out.length_squared() > 0.01 else Vector3.FORWARD
			var wy := Vector3.UP.rotated(out, (spin - PI) * 0.12)
			return Basis(out, wy, out.cross(wy).normalized())
	var ref := Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.BACK
	var x := ref.cross(y).normalized()
	x = x.rotated(y, spin)
	return Basis(x, y, x.cross(y).normalized())


static func _add(batches: Dictionary, mesh_id: int, mat: int, b: Basis, o: Vector3, cu: Color) -> void:
	var key := mesh_id * 64 + mat
	var bt: Array = batches.get(key, [])
	if bt.is_empty():
		bt = [PackedFloat32Array(), 0, o, o]
		batches[key] = bt
	var buf: PackedFloat32Array = bt[0]
	buf.append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z, cu.r, cu.g, cu.b, cu.a])
	bt[1] = int(bt[1]) + 1
	bt[2] = (bt[2] as Vector3).min(o)
	bt[3] = (bt[3] as Vector3).max(o)


# =========================================================================== main thread

static func is_warm() -> bool:
	return not _meshes.is_empty()


static func warmup() -> void:
	if is_warm():
		return
	var t0 := Time.get_ticks_usec()
	var m: Array[Mesh] = []
	m.resize(M.COUNT)
	for v in 3:
		m[M.STALACTITE + v] = CaveShapes.stalactite(v)
	for v in 2:
		m[M.STALAGMITE + v] = CaveShapes.stalagmite(v)
		m[M.NODULES + v] = CaveShapes.nodules(v)
		m[M.LENS + v] = CaveShapes.lens(v)
		m[M.CRYSTALS_SMALL + v] = CaveShapes.crystals_small(v)
		m[M.CRYSTALS_LARGE + v] = CaveShapes.crystals_large(v)
		m[M.SHARDS + v] = CaveShapes.shards(v)
		m[M.RUBBLE + v] = CaveShapes.rubble(v)
		m[M.SINTER + v] = CaveShapes.sinter(v)
		m[M.GLOWCAPS + v] = CaveShapes.glowcaps(v)
		m[M.SHELF + v] = CaveShapes.shelf(v)
		m[M.GIANT + v] = CaveShapes.giant_mushroom(v)
		m[M.WEB_ORB + v] = CaveShapes.web_orb(v)
		m[M.ROOTS + v] = CaveShapes.roots(v)
		m[M.MOSS + v] = CaveShapes.moss(v)
		m[M.PUDDLE + v] = CaveShapes.puddle(v)
		m[M.CRUST + v] = CaveShapes.crust(v)
	m[M.ICICLES] = CaveShapes.icicles()
	m[M.GEODE] = CaveShapes.geode()
	m[M.BASALT] = CaveShapes.basalt()
	m[M.EMBER_CRACKS] = CaveShapes.ember_cracks()
	m[M.PUFFBALLS] = CaveShapes.puffballs()
	m[M.WEB_DRAPE] = CaveShapes.web_drape()
	for i in m.size():
		m[i] = _with_lods(m[i])
	_mats = _make_materials()
	_meshes = m
	warmup_ms = (Time.get_ticks_usec() - t0) / 1000.0


## Automatic level-of-detail chain (meshoptimizer): distant chunks draw simplified decor.
static func _with_lods(src: Mesh) -> Mesh:
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(0))
	im.generate_lods(25.0, 60.0, [])
	var out := im.get_mesh()
	return out if out != null else src


static func mesh(id: int) -> Mesh:
	warmup()
	return _meshes[id]


static func material(id: int) -> ShaderMaterial:
	warmup()
	return _mats[id]


## Main thread: nodes for one chunk's plan (null when there is nothing to draw).
static func build_chunk(plan: Dictionary, quality: int) -> Node3D:
	var batches: Dictionary = plan.get("batches", {})
	if batches.is_empty():
		return null
	warmup()
	_apply_quality(quality)
	var root := Node3D.new()
	root.name = "CaveDecor"
	var scale: float = FADE_SCALE[clampi(quality, 0, 3)]
	for key: int in batches:
		var bt: Array = batches[key]
		var mesh_id := key >> 6
		var mat_id := key & 63
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _meshes[mesh_id]
		mm.instance_count = int(bt[1])
		mm.buffer = bt[0]
		mm.custom_aabb = bt[2]
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _mats[mat_id]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var buf: PackedFloat32Array = bt[0]
		mi.visibility_range_end = buf[15] * 200.0 * scale + 24.0
		root.add_child(mi)
	return root


static func _apply_quality(quality: int) -> void:
	if quality == _quality:
		return
	_quality = quality
	var s: float = FADE_SCALE[clampi(quality, 0, 3)]
	for mat in _mats:
		mat.set_shader_parameter(&"fade_scale", s)


static func _shader(path: String, params: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(path)
	for k: String in params:
		mat.set_shader_parameter(StringName(k), params[k])
	return mat


static func _rock(tint: Color, tint2: Color, extra := {}) -> ShaderMaterial:
	var p := {"albedo_tex": load("res://world/flora/textures/rock_diff.jpg"), "normal_tex": load("res://world/flora/textures/rock_nor.jpg"),
		"tint": tint, "tint2": tint2}
	p.merge(extra, true)
	return _shader("res://world/caves/cave_rock.gdshader", p)


static func _mineral(a: Color, b: Color, extra := {}) -> ShaderMaterial:
	var p := {"color_a": a, "color_b": b}
	p.merge(extra, true)
	return _shader("res://world/caves/cave_mineral.gdshader", p)


static func _fungus(cap: Color, cap2: Color, gill: Color, glow: Color, energy: float, extra := {}) -> ShaderMaterial:
	var p := {"cap_color": cap, "cap_color2": cap2, "gill_color": gill, "glow_color": glow, "glow_energy": energy}
	p.merge(extra, true)
	return _shader("res://world/caves/cave_fungus.gdshader", p)


static func _make_materials() -> Array[ShaderMaterial]:
	var mats: Array[ShaderMaterial] = []
	mats.resize(T.COUNT)
	var matrix := Color(0.3, 0.29, 0.27)
	mats[T.R_KARST] = _rock(Color(0.56, 0.49, 0.4), Color(0.72, 0.64, 0.52), {"band_amount": 0.16, "translucency": 0.15, "tex_mix": 0.85})
	mats[T.R_WET] = _rock(Color(0.4, 0.37, 0.32), Color(0.55, 0.5, 0.42), {"band_amount": 0.14, "wet_tip": 0.8, "base_rough": 0.55, "tex_mix": 0.85})
	mats[T.R_BASALT] = _rock(Color(0.17, 0.16, 0.16), Color(0.26, 0.22, 0.2), {"band_amount": 0.15, "tex_mix": 0.8, "wet_tip": 0.0, "base_rough": 0.75})
	mats[T.R_SINTER] = _rock(Color(0.86, 0.8, 0.68), Color(0.78, 0.48, 0.2), {"band_amount": 0.22, "band_freq": 24.0, "tex_mix": 0.5, "wet_tip": 0.3,
		"pool_color": Color(0.05, 0.22, 0.22), "pool_glow": Color(0.04, 0.2, 0.17)})
	mats[T.R_FROST] = _rock(Color(0.72, 0.8, 0.88), Color(0.9, 0.95, 1.0), {"band_amount": 0.3, "wet_tip": 0.9, "base_rough": 0.4, "translucency": 0.4})
	mats[T.R_OCHRE] = _rock(Color(0.62, 0.42, 0.24), Color(0.78, 0.6, 0.38), {"band_amount": 0.2})
	mats[T.R_MARBLE] = _rock(Color(0.86, 0.82, 0.86), Color(0.95, 0.9, 0.98), {"band_amount": 0.15, "tex_mix": 0.3, "translucency": 0.35})
	mats[T.O_COAL] = _mineral(Color(0.035, 0.034, 0.036), matrix, {"roughness": 0.22, "sparkle": 0.6})
	mats[T.O_IRON] = _mineral(Color(0.2, 0.17, 0.16), Color(0.42, 0.19, 0.07), {"color_c": Color(0.45, 0.22, 0.08), "metallic": 0.7, "roughness": 0.35, "pattern": 2})
	mats[T.O_GOLD] = _mineral(Color(1.0, 0.74, 0.3), Color(0.8, 0.78, 0.72), {"metallic": 1.0, "roughness": 0.25, "pattern": 4, "sparkle": 1.0})
	mats[T.O_EMBER] = _mineral(Color(1.0, 0.45, 0.12), Color(0.16, 0.12, 0.1), {"clarity": 0.8, "roughness": 0.15, "emission": Color(1.0, 0.42, 0.1), "emission_energy": 1.6})
	mats[T.O_OBSIDIAN] = _mineral(Color(0.025, 0.022, 0.03), Color(0.12, 0.1, 0.1), {"roughness": 0.04, "sparkle": 0.3, "clarity": 0.12})
	mats[T.O_FROST] = _mineral(Color(0.55, 0.85, 1.0), Color(0.5, 0.55, 0.6), {"clarity": 1.0, "roughness": 0.06, "emission": Color(0.35, 0.7, 1.0), "emission_energy": 0.55})
	mats[T.O_COPPER] = _mineral(Color(0.85, 0.46, 0.27), Color(0.09, 0.4, 0.27), {"color_c": Color(0.12, 0.5, 0.36), "metallic": 1.0, "roughness": 0.32, "pattern": 1})
	mats[T.O_TIN] = _mineral(Color(0.1, 0.085, 0.075), matrix, {"roughness": 0.12, "sparkle": 0.9, "clarity": 0.15})
	mats[T.O_SILVER] = _mineral(Color(0.9, 0.9, 0.93), Color(0.16, 0.16, 0.17), {"color_c": Color(0.08, 0.08, 0.09), "metallic": 1.0, "roughness": 0.22, "pattern": 3, "sparkle": 0.8})
	mats[T.O_MITHRIL] = _mineral(Color(0.62, 0.86, 1.0), Color(0.24, 0.26, 0.3), {"metallic": 0.8, "roughness": 0.18, "clarity": 0.5, "emission": Color(0.3, 0.7, 1.2), "emission_energy": 0.9, "sparkle": 1.0})
	mats[T.O_ADAMANT] = _mineral(Color(0.1, 0.42, 0.2), Color(0.12, 0.13, 0.12), {"metallic": 0.55, "roughness": 0.14, "clarity": 0.5, "emission": Color(0.2, 1.0, 0.45), "emission_energy": 0.5, "sparkle": 1.0})
	mats[T.O_RUBY] = _mineral(Color(0.75, 0.03, 0.07), Color(0.26, 0.25, 0.27), {"clarity": 1.0, "roughness": 0.05, "emission": Color(0.6, 0.02, 0.05), "emission_energy": 0.35, "sparkle": 0.8})
	mats[T.O_SAPPHIRE] = _mineral(Color(0.06, 0.16, 0.75), Color(0.26, 0.25, 0.27), {"clarity": 1.0, "roughness": 0.05, "emission": Color(0.05, 0.15, 0.7), "emission_energy": 0.35, "sparkle": 0.8})
	mats[T.O_AMETHYST] = _mineral(Color(0.58, 0.3, 0.9), Color(0.42, 0.4, 0.42), {"clarity": 1.0, "roughness": 0.07, "emission": Color(0.65, 0.3, 1.0), "emission_energy": 0.35, "sparkle": 0.8})
	mats[T.O_HELL] = _mineral(Color(0.7, 0.08, 0.04), Color(0.1, 0.06, 0.05), {"clarity": 0.6, "roughness": 0.2, "emission": Color(1.0, 0.18, 0.05), "emission_energy": 2.2})
	mats[T.O_QUARTZ] = _mineral(Color(0.92, 0.92, 0.9), Color(0.82, 0.8, 0.74), {"clarity": 0.5, "roughness": 0.1})
	mats[T.ICE] = _mineral(Color(0.7, 0.86, 0.97), Color(0.82, 0.9, 0.97), {"clarity": 0.8, "roughness": 0.05, "emission": Color(0.25, 0.45, 0.6), "emission_energy": 0.25})
	mats[T.EMBER_CRACK] = _mineral(Color(1.0, 0.4, 0.1), Color(0.07, 0.06, 0.06), {"pattern": 5, "roughness": 0.6, "sparkle": 0.0})
	mats[T.GEM_EMERALD] = _mineral(Color(0.08, 0.62, 0.3), Color(0.3, 0.3, 0.3), {"clarity": 1.0, "roughness": 0.06, "emission": Color(0.1, 0.8, 0.35), "emission_energy": 0.25, "sparkle": 0.8})
	mats[T.F_GLOWCAP] = _fungus(Color(0.12, 0.32, 0.42), Color(0.45, 0.85, 0.95), Color(0.5, 0.9, 1.0), Color(0.25, 0.85, 1.0), 2.2)
	mats[T.F_PUFF] = _fungus(Color(0.55, 0.78, 0.4), Color(0.75, 1.0, 0.6), Color(0.6, 0.9, 0.4), Color(0.45, 1.0, 0.35), 1.6, {"spot_amount": 0.8})
	mats[T.F_SHELF] = _fungus(Color(0.62, 0.32, 0.1), Color(0.95, 0.62, 0.22), Color(0.95, 0.75, 0.4), Color(1.0, 0.55, 0.15), 1.2, {"spot_amount": 0.0})
	mats[T.F_GIANT] = _fungus(Color(0.26, 0.14, 0.42), Color(0.55, 0.34, 0.85), Color(0.7, 0.55, 1.0), Color(0.6, 0.4, 1.0), 1.3, {"spot_amount": 0.7})
	mats[T.F_GIANT2] = _fungus(Color(0.08, 0.26, 0.25), Color(0.25, 0.7, 0.58), Color(0.4, 1.0, 0.8), Color(0.25, 1.0, 0.75), 1.3, {"spot_amount": 0.6})
	mats[T.F_SHELF_PALE] = _fungus(Color(0.42, 0.33, 0.24), Color(0.7, 0.6, 0.46), Color(0.75, 0.68, 0.55), Color(0.0, 0.0, 0.0), 0.0, {"spot_amount": 0.0})
	mats[T.WEB] = _shader("res://world/caves/cave_web.gdshader", {})
	mats[T.ROOT] = _shader("res://world/caves/cave_organic.gdshader", {"mode": 0})
	mats[T.MOSS] = _shader("res://world/caves/cave_organic.gdshader", {"mode": 1, "color_a": Color(0.16, 0.24, 0.07), "color_b": Color(0.42, 0.52, 0.16)})
	mats[T.MOSS_GLOW] = _shader("res://world/caves/cave_organic.gdshader", {"mode": 1, "color_a": Color(0.1, 0.22, 0.16), "color_b": Color(0.26, 0.48, 0.36),
		"glow_color": Color(0.25, 1.0, 0.75), "glow_energy": 1.2})
	mats[T.PUDDLE] = _shader("res://world/caves/cave_puddle.gdshader", {})
	mats[T.PUDDLE_WARM] = _shader("res://world/caves/cave_puddle.gdshader", {"warm": 1.0, "shore_color": Color(0.55, 0.42, 0.25)})
	return mats
