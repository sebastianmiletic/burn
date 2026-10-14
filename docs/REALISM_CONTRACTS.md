# Realism overhaul: shared contracts

The world stops looking like blocks. The voxel grid stays underneath as the authoritative data (mining, building,
saves, networking and AI all keep working on block ids), but it is no longer drawn as cubes:

* **Natural terrain** (stone, dirt, grass, sand, snow, ores, basalt, ash, mud, hell rock, bone...) is meshed as a
  smooth surface (Surface Nets over a per-voxel density byte), textured with PBR materials, and walked on with
  smooth-surface physics. Mining digs smooth holes.
* **Built things** (planks, cobble, castle brick, logs used as posts, runestone...) stay as crisp cubes with good
  textures, because real walls are flat.
* **Trees** are no longer voxels: the generator writes only a trunk column of a dedicated block (`OAK_TRUNK`,
  `CRIMSON_TRUNK`, `PINE_TRUNK`, `DEAD_TRUNK`) for collision/chopping, and the mesher hands the tree roots to
  `Flora`, which draws real tree meshes. Chopping any trunk block fells the whole tree.
* **Grass, flowers, reeds, pebbles, bushes** are scattered by `Flora` on upward-facing smooth triangles.

Ownership (each part is written by one person; touch other parts only through these contracts):

| Area | Owner | Files |
|---|---|---|
| Terrain density, smooth mesher, terrain textures/shader, physics, raycast, mining, felling logic, integration | lead | world/voxel/*, physics/*, world/materials/terrain*, entities/player/*, world/game_world.gd |
| Character models + animation + movement FX | character | models/humanoid_model.gd, models/character/* (new), models/fx/* (new); wiring in entities/enemies, entities/npc, entities/bosses |
| Flora: trees, grass, bushes, rocks, interaction | flora | world/flora/* (new) |
| Sky, weather, lighting, water/lava shader, quality presets | atmosphere | world/sky/*, rendering/graphics_quality.gd, world/materials/voxel_liquid.gdshader |
| Sound | audio | audio/* |

## Global shader uniforms (project.godot `[shader_globals]`)

| Name | Type | Written by | Meaning |
|---|---|---|---|
| `wind_dir` | vec2 | atmosphere (Weather) | normalised horizontal wind direction (x, z) |
| `wind_strength` | float | atmosphere | 0 calm, 0.35 breeze, 1.0 storm |
| `wetness` | float | atmosphere | 0 dry .. 1 soaked (surfaces darken, get glossy, puddles) |
| `snow_cover` | float | atmosphere | 0..1 fresh snow dusting on up-facing surfaces (snowfall weather in the peaks) |
| `foliage_pushers` | sampler2D | flora (FoliageInteraction) | RGBA32F texture, 16x1: xyz = world position of a pusher's feet, w = radius (m); w = 0 unused |
| `foliage_pusher_count` | int | flora | number of valid texels in `foliage_pushers` |

Read them in shaders with `global uniform float wind_strength;` etc. Set them with
`RenderingServer.global_shader_parameter_set(&"wind_strength", v)`.

## Blocks (world/voxel/blocks.gd)

New ids: `OAK_TRUNK = 41`, `CRIMSON_TRUNK = 42`, `PINE_TRUNK = 43`, `DEAD_TRUNK = 44`.
`Blocks.family(id)` -> `Blocks.Family.SMOOTH | CUBE | SMALL | TREE | LIQUID | NONE`.
LEAVES / PINE_LEAVES / CRIMSON_LEAVES are no longer generated (kept for old saves; invisible, not solid).

## Flora (world/flora/flora.gd, `class_name Flora`)

```gdscript
enum Tree { OAK, CRIMSON, PINE, DEAD }

## Main thread, once on the loading screen. Builds and caches every mesh/material. Budget ~1.5 s.
static func warmup() -> void

## WORKER THREAD (must not touch the scene tree; pure data in, pure data out).
## origin: chunk origin in world blocks (world position of chunk-local (0,0,0)).
## surface: upward-facing (normal.y > 0.5) triangles of this chunk's smooth terrain:
##   {"tris": PackedVector3Array  (3 chunk-local vertices per triangle),
##    "normals": PackedVector3Array (one per triangle),
##    "blocks": PackedByteArray (block id of the material each triangle belongs to),
##    "sky": PackedFloat32Array (0 = deep cave .. 1 = open sky, one per triangle)}
## trees: Array of [Vector3 root (chunk-local; trunk centre at ground level), int kind (Flora.Tree), float height_m, int seed]
## dimension: 0 overworld, 1 hell. Returns an opaque Dictionary consumed by build_chunk.
static func plan_chunk(origin: Vector3i, surface: Dictionary, trees: Array, dimension: int, seed: int) -> Dictionary

## MAIN THREAD, must be fast (< 0.5 ms typical): turn a plan into nodes (MultiMeshInstance3D etc.).
## The returned node is added as a child of the chunk's MeshInstance3D (chunk-local coordinates).
## quality: Settings.Quality (0 low .. 3 ultra) - controls density / draw distance.
static func build_chunk(plan: Dictionary, quality: int) -> Node3D

## Felling FX (main thread): the tree at root_world topples along direction and breaks up. Purely visual.
static func fell(parent: Node3D, root_world: Vector3, kind: int, height: float, seed: int, direction: Vector3) -> void
```

`FoliageInteraction` (world/flora/foliage_interaction.gd, a Node): GameWorld adds one. Each frame it collects the
local player, other players and nearby creatures (`GameWorld.instance.entities_near(...)`) and writes the
`foliage_pushers` globals so grass bends away from bodies and recovers over ~1-2 s.

All flora materials write their ASCII class (`ascii_roughness(r, ASCII_FOLIAGE)`, see
rendering/materials/ascii_material.gdshaderinc) and sway with `wind_dir` / `wind_strength`.

## Character (HumanoidModel additions)

Everything existing stays (`move_speed`, `grounded`, `play()`, `set_held()`, `flash()`, `set_dead()`, styles).
New, set/called by the owner every frame (Player, Enemy, Npc, bosses):

```gdscript
var velocity := Vector3.ZERO     # owner's world-space velocity
var sprinting := false
var ground_block := -1           # block id under the feet (dust colour, snow puffs...), -1 unknown
func on_jump() -> void           # take-off: anticipation pose + dust
func on_land(impact_speed: float) -> void   # touchdown, impact_speed = downward m/s; > 12 heavy landing
signal footstep(strength: float) # emitted when a foot plants; owner plays the step sound (0.3 walk .. 1 sprint)
```

## Audio additions

New sound names (playable through `Audio.play(name, pos, volume_db, pitch)` like the existing ones):
`jump, land, land_heavy, roll, step_run (generic sprint scuff), swing_light, swing_heavy, swing_blunt,
hit_flesh, hit_bone, hit_metal, hit_wood, pick_stone, pick_dirt, pick_wood, break_stone, break_dirt, break_wood,
break_crystal, tree_creak, tree_fall, rustle, splash_small, water_wade, equip, cloth`.
Ambience keys added to `Audio.set_ambience`: `birds`, `insects`, `crickets`, `leaves` (0..1).

## Second wave (added after the user's follow-up request)

Additional owners:

| Area | Owner | Files |
|---|---|---|
| Items, materials, ores->ingots, tools/weapons/armour tiers, crafting stations (workbench, furnace, anvil, ...), item 3D models, item icons, inventory / crafting / station UIs, hotbar visuals | items | items/*, models/held_items.gd, models/items/* (new), entities/interact/station.gd (new), ui/inventory_screen.gd, ui/hotbar.gd, ui/shop_screen.gd, ui/crafting_* (new), ui/item_* (new), quests/* (only to keep quests consistent with new items) |
| Main menu (centred, live world fly-over behind it), intro, settings/lobby screen polish | menu | ui/main_menu.gd, ui/intro_screen.gd, ui/menu_backdrop* (new), ui/settings_menu.gd, ui/lobby_screen.gd, ui/ui_theme.gd |
| Creatures, mobs, wildlife, bosses (incl. the Leviathan sea boss), their locations | creatures | entities/enemies/*, entities/bosses/*, entities/wildlife/* (new), models/creatures/*, models/creature_model.gd, combat/*, world/structures/*, world/wild_spawner.gd, world/location_director.gd |

The character person also edits entities/enemies/enemy.gd, entities/npc/npc.gd, entities/bosses/*.gd only to wire
the HumanoidModel hooks (velocity/sprinting/on_jump/on_land/footstep) - keep edits there small and local.

### New blocks (world/voxel/blocks.gd), all SMOOTH terrain, generated by WorldGen (lead) in depth layers
Rocks: `GRANITE 45, SANDSTONE 46, MARBLE 47, SLATE 48, CLAY 49, LIMESTONE 50`.
Ores/gems: `COPPER_ORE 51, TIN_ORE 52, SILVER_ORE 53, MITHRIL_ORE 54, ADAMANTITE_ORE 55, RUBY_ORE 56,
SAPPHIRE_ORE 57, AMETHYST 58` (existing: COAL_ORE, IRON_ORE, GOLD_ORE, EMBER_ORE, OBSIDIAN, HELLSTONE, CRYSTAL).
Drops (item ids the items person must define): granite, sandstone, marble, slate, clay, limestone, copper_ore,
tin_ore, silver_ore, mithril_ore, adamantite_ore, ruby, sapphire, amethyst (+ existing ones).
Depth bands (approximate y, surface is ~10..90): copper/tin/coal near the surface down to -20, iron < 20,
silver < -10, gold < -25, ruby/sapphire/amethyst < -40, mithril/ember < -60, adamantite/obsidian < -95 (near lava).
Hardness / tier / drop live in `Blocks.DATA`; the items person may retune the tier and hardness columns to fit the
tool progression (keep tier as "minimum pickaxe tier").

### Crafting stations
Stations are entities (kind `"station"`, data `{"station": "workbench"|"furnace"|"anvil"|...}`), created with
`EntityFactory.create("station")` and spawned server-side with `GameWorld.spawn_entity("station", pos, dim, data)`.
Players place one with an item that has `"place_station": "<kind>"`; the Player calls
`GameWorld.instance.request_place_station(kind, pos, yaw, dim)` (lead implements: server spawns it, saves it).
Interacting emits `Events.station_open(kind, station)`; the UI opens the matching crafting screen.
Villages already have smiths: the creatures/structures person places stations in villages through the location
`spawns` list: `{"type": "station", "station": "anvil", "pos": Vector3, "yaw": float}` (lead's LocationDirector
glue spawns them via the factory).
`ItemDB.RECIPES[id]` gains `"station"` ("" = by hand). The Player's `craft(recipe_id)` keeps its signature and must
check that a matching station is within 4 m (items person: put the check in ItemDB/Inventory helpers, e.g.
`ItemDB.can_craft_at(recipe_id, station_kinds_nearby)`; lead wires it).
