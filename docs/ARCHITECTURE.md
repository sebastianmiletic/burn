# Burn — architecture and module contracts

Godot 4.7, GDScript, Forward+. Everything is built in code; scenes are thin.

## Autoloads (in this order)

| Name | File | Role |
|---|---|---|
| `Settings` | core/settings.gd | Options, persisted to user://settings.cfg. `get_value(section, key)`, `set_value`, `changed(section, key)` |
| `Ascii` | rendering/ascii/ascii_config.gd | ASCII effect + glyph atlas |
| `Events` | core/events.gd | Signal bus (see file for every signal) |
| `Audio` | audio/audio.gd | Procedural SFX, ambience, music |
| `Net` | network/net.gd | LAN parties: rune codes, discovery, ENet, lobby, chat |
| `Game` | core/game.gd | App state machine: intro → menu → lobby → loading → playing; save/load |

## Rendering

`AsciiView` (rendering/ascii/ascii_view.gd) renders the world through a mirrored camera into a reduced-resolution
SubViewport, `AsciiEffect` analyses it into cell textures, `ascii_composite.gdshader` draws glyphs at native resolution.
UI is ordinary Control nodes in CanvasLayers above it (never ASCII).
Every 3D material must set `ROUGHNESS = ascii_roughness(r, ASCII_<CLASS>)` (rendering/materials/ascii_material.gdshaderinc)
or use `MaterialLibrary` / `ModelKit` helpers. FX (fire, magic, telegraphs) use transparent additive materials
(`MaterialLibrary.fx(...)`), so they are drawn over the glyphs and bloom.
`AsciiView.flash` (0..1) and `AsciiView.tint` are the screen-flash / grade hooks.

## World

* `WorldGen` (world/voxel/world_gen.gd): deterministic terrain per dimension (0 overworld 2048², 1 hell 640²), `locations`.
* `VoxelWorld` (world/voxel/voxel_world.gd): streaming, `get_block`, `set_block`, `is_solid`, `raycast`, `surface_y`.
* `Location` (world/structures/location.gd): named place, `contains(pos)`, `spawns` = [{type, pos, ...}].
  Spawn types: `npc{role}`, `enemy{kind}`, `boss{kind}`, `chest{tier}`, `shrine`, `portal{to, size}`, `arena_gate{along, across, width, height}`, `lore{text}`, `guard_post`.
* Block ids: `Blocks` (world/voxel/blocks.gd). 1 block = 1 m. Entity position = feet.

## GameWorld (world/game_world.gd) — `GameWorld.instance`

The in-game root. Owns both dimensions, entities, the local player, HUD, sky.
Authority: **server** = host machine (solo counts as server). `Net.is_server()`.

```
var local_player: Player
var view: AsciiView
var quests: QuestLog
var local_dimension: int
func world_for(dim: int) -> VoxelWorld
func locations(dim: int) -> Array[Location]
func location_at(pos: Vector3, dim: int) -> Location        # innermost match or null
func entities_near(pos: Vector3, radius: float, dim: int, team := -1) -> Array[Entity]
func players_in(dim: int) -> Array[Player]
func nearest_player(pos: Vector3, dim: int, max_dist: float) -> Player
# server only (no-ops on clients):
func spawn_entity(kind: String, pos: Vector3, dim: int, data := {}) -> Entity
func despawn_entity(e: Entity) -> void
func damage(target: Entity, amount: float, source_id: int, kind := "hit") -> void
func spawn_projectile(kind: String, origin: Vector3, velocity: Vector3, owner_id: int, team: int, dim: int, damage: float) -> void
func telegraph(shape: String, pos: Vector3, dir: Vector3, size: Vector3, duration: float, dim: int) -> void
       # shape: "circle" (size.x radius), "cone" (size.x range, size.y half-angle deg), "line" (size.x length, size.y width), "ring" (size.x inner, size.y outer)
func drop_item(pos: Vector3, item_id: String, count: int, dim: int) -> void
func boss_started(boss: Boss) -> void      # closes arena gates, boss bar, music
func boss_finished(boss: Boss) -> void     # opens gates, loot, quest credit
func shake(strength: float) -> void        # all clients near
# any machine:
func request_attack(targets: Array[int], amount: float, kind: String) -> void   # local player hit → server
func request_set_block(pos: Vector3i, block: int, dim: int) -> void
```

Entity kinds are spawned through `EntityFactory.create(kind: String) -> Entity` (entities/entity_factory.gd).

## Entities (entities/)

`Entity` base: `net_id, kind, team, dimension, health, max_health, dead, yaw, anim, anim_time, body: VoxelBody`,
`take_damage(amount, source_id, kind)`, `server_tick(delta)`, `snapshot()` / `apply_snapshot()` / `interpolate(now)`.
Teams: PLAYERS, MONSTERS, NEUTRAL.

* `Player` (entities/player/player.gd) — local or remote humanoid. Uses `HumanoidModel`.
* `Npc` (entities/npc/npc.gd) — villagers, quest givers, shops.
* `Enemy` (entities/enemies/enemy.gd) — kinds: `skeleton`, `archer`, `ghoul`, `troll`, `imp`, `shade`.
  State machine idle → patrol → chase → attack → stagger/flee → die, leash to spawn, respawn timer (server).
* `Boss` (entities/bosses/boss.gd) — kinds: `warden`, `mountain_king`, `dragon`, `cerberus`, `hades`.
  Phases by health (100–66, 66–33, 33–0), telegraphed heavy attacks, threat table, enrage timer.
  `display_name`, `phase`, `engaged`, emits through GameWorld.boss_started / boss_finished.
* `Projectile` (entities/projectile.gd) — kinds: `fireball`, `arrow`, `boulder`, `soul_bolt`, `player_fireball`.

## Models (models/)

`HumanoidModel` (models/humanoid_model.gd) — smooth skinned character: one procedurally generated mesh per body
shape (models/character/: CharBody builds it, on a worker thread in the game, cached and shared; CharHead faces/hair/
headwear; CharBones anatomical skeletons; CharStyles seeded villager variety), a 24-bone Skeleton3D (+25 verlet cloak
bones, CharCloth), one shared palette shader (character.gdshader, colours via instance uniforms) and a procedural
animator (leg IK, gait, jump/land, actions, ragdoll-like death). Movement FX in models/fx/ (MoveFx pooled dust,
SwingTrail, SpeedStreaks). All style keys are documented at the top of humanoid_model.gd.
```
HumanoidModel.new(style: Dictionary)   # {skin, cloth, cloth2, hood: bool, cloak: bool, height, bulk, eyes: Color(glow), helmet, beard...}
var move_speed: float          # m/s, drives walk/run cycle
var grounded: bool
var velocity: Vector3          # owner's world velocity; sprinting: bool; ground_block: int
var terrain_probe: Callable    # optional func(world_pos) -> ground y, sampled when a foot plants
func on_jump() / on_land(impact_speed: float)
signal footstep(strength: float)
static func drive(model, owner: Entity, velocity, grounded := true, sprint := false)  # one-line wiring for NPCs/monsters
func play(action: String, duration := -1.0)   # "attack", "attack2", "mine", "cast", "dodge", "hit", "die", "interact", "drink", "jump"
func set_held(item_id: String)                # shows the item in the right hand ("" = empty)
func set_offhand_light(on: bool)              # torch in left hand
func flash(color := Color(1,1,1))             # hit flash
func set_dead(dead: bool)
```
Other creature models are built with `ModelKit` helpers (models/model_kit.gd): material helpers that set ASCII classes.

## Items, quests

* `ItemDB` (items/item_db.gd): ITEMS, RECIPES, SHOP, rank tables.
* `Inventory` (items/inventory.gd): 3 hotbar + 24 bag slots, gold.
* `QuestLog` (quests/quest_log.gd), `QuestDB` (quests/quest_db.gd).

## Audio contract (`Audio` autoload)

```
func play(sound: String, at := Vector3.INF, volume_db := 0.0, pitch := 1.0) -> void   # INF = non-positional
func play_ui(sound: String) -> void
func set_music(state: String) -> void      # "menu", "explore", "night", "cave", "boss", "hell", "victory", "silence"
func set_ambience(levels: Dictionary) -> void   # keys: wind, rain, fire, cave, lava, village (0..1)
```
Sound names: ui_hover, ui_click, ui_back, ui_open, ui_close, rune, step_grass, step_stone, step_wood, step_snow, step_sand,
swing, hit, hit_heavy, crit, block_hit, block_break, block_place, pickup, coin, potion, hurt, death, levelup, quest,
fireball_cast, fireball_hit, explosion, arrow, bow, roar, roar_big, wing_flap, stomp, growl, bone_rattle, imp_screech,
door, chest, shrine, portal, thunder, splash, lava_bubble, burn.

## Networking (`Net` autoload)

```
signal lobby_changed                     # players or state changed
signal session_started(info: Dictionary) # {seed, host_name, ...} → Game loads the world
signal join_failed(reason: String)
signal peer_left(id: int, name: String)
var players: Dictionary                  # peer_id -> {name, color: Color, ready: bool}
var runes: PackedInt32Array              # 4 rune indices 0..15 of the current party
func host_party(player_name: String) -> PackedInt32Array
func join_party(runes: PackedInt32Array, player_name: String) -> void   # LAN discovery then ENet connect
func leave() -> void
func start_campaign(info: Dictionary) -> void   # host
func is_online() -> bool
func is_server() -> bool                 # true in solo
func my_id() -> int
func send_chat(text: String) -> void
```
Rune glyphs (strokes, names, key mapping) live in `RuneGlyph` (ui/rune_glyph.gd); `RuneCode` (network/rune_code.gd)
handles code generation and encoding — the network only ever deals with rune indices 0..15.

## UI (ui/)

Terminal style: dark panels, box-drawing borders (┌─┐│└┘), amber accent, JetBrains Mono; titles in Cinzel.
Screens: IntroScreen (burning BURN title), MainMenu, LobbyScreen (runes), SettingsMenu, LoadingScreen,
Hud (minimap + location, health, rank bar, hotbar ×3, ability cooldowns, boss bar, quest tracker, prompts, toasts,
damage numbers, crosshair), InventoryScreen, ShopScreen, DialogBox, QuestLogScreen, MapScreen, PauseMenu, DeathScreen,
VictoryScreen, ChatBox, PerfOverlay (F3).
