# Round 3: "not a block game", first person, bigger world, story to the Ryft

The user's direction (paraphrased from their request): no visible blocks anywhere, mining sculpts the ground
instead of removing blocks, first-person by default, ASCII off by default (and a much better coloured ASCII when on),
a larger irregular map with real mountains, cave biomes, a richer ocean, abandoned mines and portals, high-quality
modelled villages and creatures, hyperreal bosses with cool attacks, worthwhile quests with clear guidance, a final
boss at the Gates of Hades that unlocks the Ryft Island (rifts, floating islands), 60 fps minimum on Windows, macOS
and Linux, GitHub distribution with auto-update, working multiplayer.

Read docs/ARCHITECTURE.md and docs/REALISM_CONTRACTS.md for the existing contracts; this file adds to them.

## Owners

| Area | Owner | Files |
|---|---|---|
| Mining as sculpting, voxel engine, meshers, physics, first-person camera + viewmodel, player, networking, game state, performance, GitHub/CI/auto-update | lead | world/voxel/*, physics/*, entities/player/*, world/game_world.gd, world/replicator.gd, core/*, network/*, project.godot, rendering/graphics_quality.gd, world/sky/* |
| World generation: larger irregular map, mountains, cave biomes, ocean floor and islands, Ryft dimension terrain, location planning | worldgen | world/voxel/world_gen.gd, world/structures/location_planner.gd, world/caves/* (new), world/materials/terrain_textures.gd (table entries for new materials), assets/terrain/* |
| Architecture: modelled villages, houses, castles, crypts, ruins, towers, shrines, abandoned mines, portals, shipwrecks, Ryft structures | structures | world/structures/* (except location_planner.gd), world/architecture/* (new), world/location_director.gd |
| Vegetation: rare trees, felling/leaf/grass FX, alpine, underwater (kelp, coral, seagrass), cave vegetation (glow mushrooms, moss, roots), Ryft flora | flora | world/flora/* |
| Creatures and bosses: hyperreal models for every mob/boss (dragon, Cerberus, imp, shade still use old models), attacks and VFX, Hades as the final boss at the Gates, Ryft creatures and bosses, cave/ocean life, spawning by cave biome | creatures | entities/enemies/*, entities/bosses/*, entities/wildlife/*, models/creatures/*, models/creature_model.gd, models/models.gd, combat/*, world/wild_spawner.gd |
| Story, quests, guidance, rewards (incl. the OP Hades rewards and new items), NPC dialogue | quests | quests/*, items/item_db.gd + items/inventory.gd (additions), entities/npc/*, ui/quest_*, ui/dialog_box.gd |
| HUD and screens: detailed minimap + world map, hotbar as a triangle bottom-left, first-person HUD, objective markers/compass, settings defaults | ui | ui/* (except the files above), world/map_image.gd |
| ASCII renderer quality (coloured, detailed) | ascii | rendering/ascii/*, rendering/materials/* |
| Characters (HumanoidModel) | lead (small fixes only) | models/humanoid_model.gd, models/character/* |

## Blocks (world/voxel/blocks.gd)

* `STRUCTURE = 59`: invisible, solid, unbreakable collision for modelled buildings (family `STRUCTURE`).
  Blueprints write it wherever the building's visual mesh is solid (walls, floors, roofs, stairs as half-steps are
  not possible: use ramps of full cells or leave stairs walkable by step-up, which climbs 1 block).
* Rare trunks: `IRONWOOD_TRUNK = 60` (axe tier 2), `EMBERWOOD_TRUNK = 61` (tier 3), `RYFTWOOD_TRUNK = 62` (tier 4).
  Drops "ironwood", "emberwood", "ryftwood" (quests/items owner defines the items).
* Ids 63..119 belong to the worldgen owner for new natural materials (cave stones, geyserite, glowing gem crystal,
  mushroom soil, coral rock, ryft stone, floating-island soil, ...). Add each to `Blocks.DATA`, to `SMOOTH_BLOCKS`, and
  to `TerrainTextures._table()` (codes up to 119; 120..127 are SmoothMesher biome codes).
* The crisp CUBE family is no longer generated anywhere (no block placing either). Old saves may still contain cubes.

## Mining is sculpting (lead)

`VoxelWorld.dig(center: Vector3, radius: float, strength: float, max_tier: int) -> Dictionary` removes density in a
sphere (smooth falloff); voxels whose density falls below 0.5 become empty. Returns `{block_id: amount}` of material
removed (1.0 = one voxel). The server turns amounts into item drops. `VoxelWorld.fill(center, radius, block)` adds
ground back (terraforming with dirt/stone). Edits are stored as `block | (density << 8)` per voxel.
Trees: chopping hits a trunk; the whole tree falls (needs the trunk's axe tier).

## Dimensions

`WorldGen.Dimension`: OVERWORLD = 0, HELL = 1, RYFT = 2 (new, worldgen owner): an island of rifts and floating
islands (3D density, not a heightmap), its own biomes and locations. GameWorld prepares all three. Travel to the
Ryft is through a portal that only works once `GameWorld.ryft_unlocked` is true (set when Hades is defeated; saved).
Heights: Y range is -128..255 for every dimension (mountains may reach ~240).

## World queries the worldgen owner provides (thread-safe)

```gdscript
func cave_biome_at(x: int, y: int, z: int) -> int   # WorldGen.CaveBiome: NONE (not a cave), STONE, GEYSER, GEM, MUSHROOM, ICE, LAVA, FLOODED, ... ; GEM caves: rich, no mobs, rare
func biome_at(x: int, z: int) -> int                 # existing; add MOUNTAINS (big, snow-capped) and others as you like
func ground_level(x: float, z: float) -> float       # existing
```
Geysers, steam vents and other interactive cave features: world/caves/* (worldgen owner) as a Node the lead adds to
GameWorld (`CaveFeatures`), working from the player's position.

## Flora contract additions

`SmoothMesher` passes to `Flora.plan_chunk(origin, surface, trees, dimension, seed)`:
* `surface` gains `"cave": PackedByteArray` (cave biome per upward triangle, 0 = open air) and `"ceiling"`:
  `{"tris": PackedVector3Array, "normals": PackedVector3Array, "blocks": PackedByteArray, "cave": PackedByteArray}`
  for downward-facing cave triangles (stalactite moss, hanging roots, glow worms). Underwater triangles are the
  ones below `WorldGen.SEA_LEVEL + 0.5` (kelp, coral, seagrass).
* `trees` kinds gain IRONWOOD = 4, EMBERWOOD = 5, RYFTWOOD = 6.

## Architecture contract

Locations carry visual props: `Location.props: Array` of `{"type": String, "transform": Transform3D, ...}`
filled by the structures owner when building blueprints. `Architecture.build(location: Location) -> Node3D`
(world/architecture/architecture.gd) turns them into meshes; LocationDirector instantiates it when the player is
within ~300 m and frees it beyond ~400 m (use threads / budgets so it never hitches). Collision comes from
STRUCTURE blocks in the blueprint, which must match the visual geometry closely.

## Guidance (quests owner, read by ui owner)

`QuestLog.markers() -> Array` of `{"pos": Vector3, "dim": int, "label": String, "kind": "main"|"side"|"turn_in"}`
for the minimap, world map and on-screen compass/objective marker.

## Defaults

Settings defaults: render style OFF (ASCII off), first-person camera (V toggles third person), quality HIGH.
Target: 60 fps minimum at High on the user's Apple M4 (2940x1846) and on mid-range Windows/Linux GPUs.

## Testing rules for everyone

* macOS has no `timeout`; use `perl -e 'alarm N; exec @ARGV' <cmd>`.
* `godot --headless --path . --import` after adding class_name scripts.
* `godot --headless --path . -s res://tests/run_tests.gd`, `godot --headless --path . -- --playtest` and
  `godot --headless --path . -s res://tests/game/flow_test.gd` must stay green.
* GPU captures take over the screen and need `--fullscreen`; serialize with
  `until mkdir /tmp/burn_gpu.lock 2>/dev/null; do sleep 3; done; <run>; rmdir /tmp/burn_gpu.lock`.
  `tests/gpu/game_capture.gd` supports `--style=4` (ASCII off), `--weather=`, `--time=`, `--quality=` and many stops.
* Never touch the user's saves (`user://saves`) or their settings except through throwaway slots; restore
  anything you change.
