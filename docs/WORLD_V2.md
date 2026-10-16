# World revision 2

- `WorldGen.revision` is saved as `world_revision`. A save without the field retains revision 1.
  Revision 2 enlarges the extent to 3072 m but leaves campaign coordinates near (1024, 1024).
  Always use `gen.center()` for the campaign island, not half the map extent.
- Dimensions: 0 overworld, 1 underworld, 2 Ryft. Ryft is a finite two-surface field with four floating
  islands and continuous connecting paths. Its edits, spawns and unlock survive save/load and joining.
- Natural mining uses `VoxelWorld.plan_dig`, a density brush. The replicator checks reach, tool identity,
  finite inputs and strike cadence. `_resolve_block` refuses to delete smooth terrain as a cube.
- `CaveBiomes` partitions the underground into deterministic 128×64×128 m regions. Ellipsoidal chambers
  join the original winding tunnels. Chamber radii leave room between region boundaries so the field
  remains continuous. Rich crystal refuges occur in approximately 1/32 regions; normal wild spawning
  is suppressed there. Materials remain finite and use the established tool ladder.
- `EnvironmentDetails` caps nearby decorative content. Geyser visuals follow the network clock;
  host-side damage uses the same timed cycle. Kelp is instanced. Cave plants/crystals are decorative;
  mine the surrounding terrain veins for resources.
- `Architecture` batches continuous house/prop geometry by material. `Blocks.STRUCTURE` stores invisible,
  unbreakable collision for it. Roofs are pitched meshes. Legacy towers/castles and some village props
  still use voxel-derived geometry, not finished architectural assets.
- `DistantLand` is a non-colliding height-field horizon: 8 m tiles with a 32 m far LOD, geomorphing to a softened
  massif shape with distance, the terrain's own materials, snowcaps, canopy tint, horizon shadows and its own
  aerial perspective; the render camera's far plane is 4.2 km. Detailed streaming includes the vertical range
  between each chunk-column's low and high samples, preventing gaps on large slopes. Horizon geometry
  cannot display distant excavation; it is replaced by edited detailed terrain nearby.
- `MapImage` uses actual column heights, contours, bathymetry, roads and roof footprints. `Minimap` only
  uploads an immutable world image once. Underground slices sample loaded cells once per second.
- The first-person camera is mandatory for gameplay. Old third-person preferences do not override it.
  The ASCII renderer has been removed; the 3D world renders directly with MetalFX / FSR upscaling. Grain is off by default.
- Hades death synchronizes `ryft_unlocked`; the final quest grants the unique bound sword and mithril axe.
  The next quest directs the player to Emberfall's Ryft gateway. Old completed campaigns gain that quest.
- `RuntimePaths.file()` routes settings, saves and procedural sound caches through `--data-dir` for tests.
  Normal builds retain OS-standard user-data paths. Test harness logs must explicitly use `--log-file`.

The previous architecture docs describe the original two-dimension design. They remain useful for the
entity, rendering and audio contracts, but these additions supersede their world-size, camera and HUD notes.

# World revision 3 (new worlds; saves keep the revision they were made with)

- `WorldGen.LATEST_REVISION` (3) is used for new games (core/game.gd, world/game_world.gd). Revision 2 code
  paths are untouched, so 0.4 saves generate exactly as before.
- Extent 4608 m (2.25x the area), land ~9.7 km2 (3.3x). The campaign island keeps its places; land bridges
  lead east from Thornwick to the Eastreach and south from the Dragon's Keep to the Sunderlands.
- New biomes (`WorldGen.Biome`, names in `BIOME_NAMES`, map colours in `BIOME_COLORS`): REDWOOD "The
  Elderwood", CANYON "The Red Mesas", ALPINE "Highmere Alps", TUNDRA "The Pale Tundra", VOLCANIC
  "Brimstone Badlands", FJORD "Kaldfjord Coast". New blocks 63..72: red rock, red sand, scoria, permafrost,
  redwood trunk, umber rock, flowstone, geyserite, mycelium, magma rock.
- `prepare()`: a 32 m biome-blend grid and the 4 m terrain maps on the WorkerThreadPool, then lakes,
  locations, protected sites, the cave network, pads/roads. `height_map()` (parallel, cached) feeds the
  world map and the horizon. Chunk columns are cached (`_columns_v3`).
- Mountains are sculpted massifs (`PEAKS`): concave peak profiles, ridged ridgelines and spurs,
  couloirs that converge on each summit (`_couloirs`), scree, fell-field and slope-aware snowcaps.
  Mesas/canyons (`_mesa`, banded red beds), the caldera volcano with a lava lake, fjord inlets with
  sheer walls, glacial tarns and frozen ponds (`lakes`, `lake_level()`), ravines (`_ravine`).
- `CaveNetwork` (world/caves/cave_network.gd): signed-distance carvers evaluated per chunk — natural cave
  mouths on hillsides and pit entrances, sinkholes, winding passages down to the regional chamber,
  underground rivers between flooded chambers, and mine workings. Chambers have flat floors; flooded
  grottos hold lakes and magma vaults lava pools (`CaveBiomes.pool_level`), guarded so no tunnel breaches
  a pool.
- Full mines (`MineLayout`, world/caves/mine_layout.gd): hillside portal, adit, 2-3 levels joined by
  declines, stopes with ore seams, storerooms, a caved-in crosscut hiding a rich stope, a flooded sump,
  the deep gallery with a guardian and a tier-3 chest, and a breakthrough into the caves. The workings
  location (`<id>_workings`, `Location.Kind.MINE`) carries `get_meta(&"mine")["props"]` for MineDressing.
- Queries: `cave_name_at(pos)`, `is_underground(pos)`, `cave_biome_at(x, y, z)`, `climate_at(pos)` (weather
  snow/dust/haze), `horizon_color(x, z, h, slope)`, `mountain_weight(x, z)`, `is_protected(x, z)`.
- `tools/world_bench.gd` prints prepare timings, land/biome areas, chunk costs and can save the map.
- Terrain textures gained a seventh row of layers (`TerrainTextures.L.CLIFF`, `BASALT_ROCK`, `SCREE`,
  `RED_CLIFF`). Steep columns show the bedrock of their height (`WorldGen.FACE`), so faces read as one rock.
- Cave decoration (CaveDecor), mine dressing (MineDressing) and the geyser vents are modelled meshes in
  world/caves/*; `CaveBiomes.decor_kind()` tells CaveDecor where the mine workings are.
- Weather (world/sky/weather.gd) reads `climate_at()` for revision 3; the horizon (world/distant_land.gd)
  colours its mesh with `horizon_color()`.
- Weather (world/sky/weather.gd) changes on its own: the host walks a weighted chain of states
  (clear, overcast, rain, storm, fog, snow, blizzard, heatwave, dust_storm, ember_storm, and on clear
  nights aurora / meteor_shower), each lasting minutes, synced through `Replicator.broadcast_clock`.
  Thunderstorms strike near players (a strike within 3.5 m deals 28 damage). Gameplay can summon
  weather with `world.weather.request(state, seconds, source_peer := 0) -> bool`: server-authoritative,
  clients forward the request to the host (RPC on the `Weather` node), `seconds` is clamped to 10..900
  and holds the state before the natural chain resumes; unknown states return false. Read-outs:
  `state_name()`, `hold_left()`, `visibility()`, `heat_amount()`, `aurora_amount()`, `ember_amount()`,
  `meteor_amount()` besides the older rain/snow/dust/storm/fog/wind accessors.
- Underground, SkyController blends to the cave's palette (CaveBiomes.palette_at: dark tinted murk,
  bounce fill, haze), occludes the sky's radiance (no sky reflections or sky light in caves) and lets
  terrain ambient back in as the cave fill; the horizon is hidden more than 14 m down.
