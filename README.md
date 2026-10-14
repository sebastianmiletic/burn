# BURN

An open-world action RPG drawn entirely in coloured ASCII. A realistically lit 3D voxel world — villages, castles,
caves you dig into with a pickaxe, the Gates of Hades far below the Cinder Crater, and the underworld beyond —
is rendered through a GPU ASCII pass and composed glyph by glyph at your screen's native resolution.
Play solo, or with friends on the same Wi-Fi: the host shows four ancient runes, everyone else types them in.

Built with **Godot 4.7** (Forward+, GDScript). All content — terrain, structures, creatures, sound, music — is generated
procedurally at runtime; the only shipped assets are two OFL fonts (see `CREDITS.md`).

## Running

```sh
# from this directory
godot --path .            # or open project.godot in the Godot editor and press Play
```

The game opens as a borderless window covering the whole screen (Settings → Display lets you choose windowed or
true fullscreen). First launch imports resources, which takes a few seconds.

Useful command-line flags (after `--`):

| Flag | Effect |
|---|---|
| `--skip-intro` | straight to the main menu |
| `--solo [--slot=N] [--seed=N] [--continue]` | jump straight into a solo game |
| `--host` / `--join=R3-R12-R0-R7` | host or join a LAN party from the terminal (prints the rune code) |
| `--sim-latency=150 --sim-loss=0.02` | network latency / packet-loss simulator |
| `--name=Ash` | player name for this run |

## Multiplayer (LAN)

1. Host: **Multiplayer → Host**. Four glowing runes appear — that is the party code.
2. Friends on the same network: **Multiplayer → Join**, click (or type) the same four runes, **Join**.
3. When everyone is in the lobby, the host presses **Begin campaign**. Players can also join a campaign in progress.

The host's machine is the authoritative server (monsters, bosses, loot, block edits); each player's character
(inventory, rank, quests) is saved on their own machine. Discovery uses UDP broadcast on port 47210 and the game
itself ENet on 47211; macOS may ask to allow incoming connections the first time you host.
`tools/launch_party.sh N [--latency 150 --loss 0.02]` starts a host and N clients on one machine for testing.

## Controls (rebindable in Settings → Controls)

| Action | Default |
|---|---|
| Move / sprint / jump | WASD / Shift / Space |
| Look | Mouse · Shift+wheel zooms the camera |
| Attack · **mine** (hold with a pickaxe) | Left mouse |
| Place block / torch · use item | Right mouse |
| Hotbar (3 slots) | 1 · 2 · 3 · mouse wheel |
| Dodge roll (brief invulnerability) | Ctrl |
| Fireball · Light burst | Q · R |
| Drink potion | F |
| Interact (talk, open, rest at shrines, portals) | E |
| Inventory · Quest log · World map | Tab/I · J · M |
| Chat (multiplayer) | T |
| Pause | Esc |
| Performance overlay | F3 |

## The campaign

Rekindle the Emberfall shrine, forge iron, then take the three seals from the **Warden of the Silent Crypt**
(Blackmarsh, west), the **Mountain King** (his hall inside the Frost Peaks, north) and the dragon **Ashvane**
(the Dragon's Keep, Cinder Wastes, south). Carry them down — far down — beneath the Cinder Crater to the
**Gates of Hades**, cross into the underworld, defeat **Cerberus** in Tartarus and finally **Hades** on his throne.
Six villages offer side quests, a blacksmith forges better tools and blades, merchants trade. Shrines are
checkpoints. Pickaxes have tiers: stone (stone, coal, iron) → iron (gold, ember crystal) → obsidian (obsidian, hellstone).

## Graphics settings

* **Render style**: Ember (warm sepia duotone), Full colour, Classic (long ASCII ramp), Phosphor (green terminal), ASCII off.
* **Cell size**: Fine 6×10, Default 8×14, Chunky 12×20 (logical pixels; doubled on Retina screens).
* **Quality** Low / Medium / High / Ultra: 3D render resolution (50–100 % of the logical window), GI (SDFGI on High+),
  volumetric fog, SSAO/SSIL/SSR, shadow sizes, view distance. Glyphs are always drawn at native resolution.

## How the ASCII renderer works

1. The world renders into a reduced-resolution SubViewport (`AsciiView`).
2. `AsciiEffect` (a `CompositorEffect` at PRE_TRANSPARENT) reads colour, depth and normal/roughness and runs compute passes:
   G-buffer unpack → depth/normal edges → Sobel direction → per-cell glyph choice → adaptive exposure → clear to FX layer.
3. **Per-material glyph styles**: every material encodes a material class in the low 3 bits of its roughness, which
   Godot stores in the normal-roughness buffer (`AsciiMaterialId`, verified by `tests/unit/test_material_id.gd`):
   solid (dense ramp), ground, foliage/leaves (strokes and soft masses), liquid (animated `~ - =`), rain streaks
   (slanted strokes following the streak), emissive (passed through untouched).
4. Fire, sparks, spells and telegraphs are transparent materials drawn **after** the ASCII pass, so they stay
   un-converted and Godot's glow blooms them across the grid.
5. `ascii_composite.gdshader` draws the glyphs at native resolution from a font atlas generated at startup, applies the
   render style, glyph glow, vignette and grain, and adds the FX layer.

## Project layout

```
core/        Game state machine, settings, keybinds, saves, event bus
rendering/   ASCII effect + composite, glyph atlas, materials, quality presets
world/       GameWorld, voxel engine (world/voxel), structures, sky & weather, replication, director/spawner
entities/    Entity base, player, NPCs, interactables, enemies, bosses, projectiles
models/      Procedural creature and character models
combat/      Damage, cooldowns, telegraph FX
items/ quests/ ui/ audio/ network/
tests/       unit tests (headless), GPU capture tools, network integration tests
docs/        ARCHITECTURE.md — module contracts
```

## Tests

```sh
godot --headless --path . --import                         # once, after pulling (also after editing .glsl shaders)
godot --headless --path . -s res://tests/run_tests.gd      # 58 unit tests (+ boss and enemy fight simulations)
godot --headless --path . -- --playtest                    # scripted playthrough: quests, mining, combat, boss, hell, save
godot --headless --path . -s res://tests/game/flow_test.gd # intro -> menu -> new game -> quit -> continue
tests/net/run_net_test.sh                                  # LAN discovery, lobby, payloads, 150 ms / 2 % loss
tests/net/run_game_mp_test.sh [--latency 150 --loss 0.02]  # host + client actually playing together
godot --path . --fullscreen -- --capture-game=/tmp/burn --tour=vista,village,night,dragonfight   # screenshots + timings
```

Developer flags: `--load-timing` (loading phase timings), `--gfx=noshadow,nofog,nossao,noglow,dist4,noascii`
(profiling toggles), `--prof` with `--capture-game` (per-subsystem frame cost), `--print-window`.

## Exporting

`export_presets.cfg` defines macOS, Windows and Linux presets. With the Godot 4.7.2 export templates installed:

```sh
godot --headless --path . --export-release "macOS"   build/macos/Burn.zip     # ~59 MB, universal, ad-hoc signed
godot --headless --path . --export-release "Windows" build/windows/Burn.exe   # ~105 MB, single exe
godot --headless --path . --export-release "Linux"   build/linux/Burn.x86_64  # ~71 MB, single binary
```
