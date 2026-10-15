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
