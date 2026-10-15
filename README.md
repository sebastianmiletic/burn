# BURN

A first-person exploration and combat RPG built with **Godot 4.7.2 / Forward+**.
Explore an irregular island chain, sculpt tunnels with a pickaxe, fell trees, forge equipment,
complete village quests, and battle through the Gates of Hades to unlock **Ryft Island**.

**Status: playable development preview, not a finished commercial release.** Terrain, villages,
characters, creatures and effects are procedural. They are not photorealistic assets. See
[verification and remaining work](docs/RELEASE_STATUS.md) before downloading.

## Download and play

Download a platform archive from [GitHub Releases](https://github.com/sebastianmiletic/burn/releases).
Preview releases are listed on that page, not necessarily under `/releases/latest`.

| System | Archive | Launch |
| --- | --- | --- |
| Windows 10/11, x86_64 | `Burn-0.4.1-Windows.zip` | Extract the entire archive, then run `Burn.exe`. |
| macOS, Apple Silicon or Intel | `Burn-0.4.1-macOS.zip` | Extract, move `Burn.app` to Applications, then open it. |
| Linux, x86_64 | `Burn-0.4.1-Linux.tar.gz` | Extract, then run `chmod +x Burn.x86_64 && ./Burn.x86_64`. |

The builds are not commercially signed/notarized. Review the source and verify the archive against
`SHA256SUMS.txt` before accepting an OS unknown-publisher warning. On macOS, use the OS's per-app
**Privacy & Security → Open Anyway** option if available. Do not disable system-wide security.

A Vulkan-capable GPU on Windows/Linux or a Metal-capable Mac is required. Install current GPU drivers.
Start with 8 GB RAM and allow at least 1 GB of free disk space for the game, sound cache, saves and updates.
Windows and Linux exports need native hardware testing; export success alone is not certification.

First launch prepares procedural audio. A new world also needs a loading pass. Later launches reuse
the sound cache. If performance is poor, select **Settings → Graphics → Medium or Low**.

### Defaults

- First-person gameplay.
- Film grain off by default.
- High quality, with adaptive scene resolution targeting 60 FPS. UI stays at native resolution.
- Mountain snow and distant blur intensify with altitude. Disable distance blur independently in Settings.

There is **no guaranteed 60 FPS minimum**. Frame rate depends on hardware, resolution, streaming,
scene complexity and settings. The performance overlay is available with F3.

## First steps

1. Start a new solo world, or host a multiplayer party.
2. Follow the `!` marker to the Emberfall shrine and press **E**. This sets your checkpoint.
3. Speak with Elder Maren, then the blacksmith. The quest tracker and **J** journal explain your objectives.
4. Select the pickaxe with **2** and hold left mouse on natural ground. Each strike removes a rounded
   volume, not a cube. Place torches with right mouse and bring food and potions underground.
5. Mine iron and coal, use the village furnace/anvil, and improve tools before pursuing the three seals.

The main route is **Emberfall → Silent Crypt/Warden → Frost Peaks/Mountain King → Ashvane →
Gates of Hades → Cerberus → Hades**. Defeating Hades opens the violet gateway in Emberfall.
The final quest awards Gatebreaker and a mithril axe once per character. Gatebreaker has no resale
value; the Ryft follow-up quest leads across connected floating islands and rewards exploration.
The broader story remains provisional.

## World and activities

New worlds use a **3,072 × 3,072 metre** extent with an asymmetric main island, outlying islands and ocean.
Only nearby detailed terrain is streamed; a coarse horizon keeps distant ridgelines visible.

- **Terrain and mining:** smooth density surfaces, photographic terrain materials, slope blending,
  rounded excavation, ore veins and material/tool tiers. The internal voxel grid is storage and collision,
  not the intended visual style. Some legacy structures still need conversion.
- **Caves:** limestone galleries, geyser caverns with timed steam hazards, glowroot hollows,
  glacial grottos, and rare crystal sanctuaries with dense, finite, tier-gated resources and no wild spawns.
  Old Ember Mine and Frosthold Adit provide descending routes into the underground.
- **Mountains:** larger ridged peaks, snow-covered rock, altitude snowfall, haze and optional distance blur.
- **Ocean:** kelp beds, four loot-bearing shipwrecks, fish schools, sharks, sea serpents and the Drowned Spire.
- **Villages:** continuous plaster/timber house meshes and pitched roofs replace cube-rendered houses.
  NPCs, merchants, smiths, crafting stations, side quests and shrines remain interactive.
- **Trees:** chopping a trunk fells the whole tree with falling and leaf effects. Ironwood requires
  an iron-tier tool, emberwood steel, and Ryftwood mithril. Rare woods have crafting uses.
- **Navigation:** shaded relief, contours, coast/depth colors, roads, building footprints, quest markers,
  altitude readout and an underground slice sampled from loaded terrain, including edits.
- **Endgame:** Ryft Island has floating land, walkable stone connections, hostile encounters, loot,
  a landing shrine and a return gateway.

Older saves retain generation revision 1 to avoid moving terrain underneath existing edits.
**Start a new world for the larger map, new cave system and taller mountains.** Back up saves before updates.

## Controls

All active gameplay bindings can be changed under Settings → Controls.

| Action | Default |
| --- | --- |
| Move / sprint / jump or swim up | WASD / Shift / Space |
| Look | Mouse |
| Attack / hold to excavate with a pick / chop with an axe | Left mouse |
| Use / place torch or material | Right mouse |
| Equipment, arranged in a bottom-left triangle | 1, 2, 3 / mouse wheel |
| Dodge | Ctrl |
| Fireball / light burst | Q / R |
| Drink potion | F |
| Interact | E |
| Inventory / journal / world map | Tab or I / J / M |
| Multiplayer chat | T |
| Pause / performance overlay | Esc / F3 |

## Multiplayer

Use the **same game version** on every machine (this preview uses network protocol 3).

**LAN:** Multiplayer → Host. Friends choose Join and enter the host's four runes. The host begins the
campaign once everyone is in the lobby. Joining an active campaign is also supported.

**Internet:** the host attempts UPnP. If a public address appears, share it and use Join by address.
Otherwise forward the displayed UDP game port (normally **47211**) to the host, or use a private
VPN such as Tailscale/ZeroTier. Rune discovery uses LAN broadcast UDP **47210**; it is not a global
matchmaking service. Carrier-grade NAT may prevent direct public hosting.

The host simulates monsters, bosses, drops, terrain edits and steam damage. Clients receive edit
reconciliation after loading and party-wide boss unlocks. Characters/inventories remain client-local:
**this is trusted-friends co-op, not an anti-cheat-secure public server**. Host migration is not supported.
Allow the game through your firewall only on networks you trust.

## Graphics

The world renders in full 3D with filmic (AgX) tonemapping, SDFGI and screen-space indirect light at High, volumetric
fog and soft shadows. The 3D resolution follows the quality preset (or the 3D resolution setting) and is upscaled to
the window with MetalFX temporal on macOS or FSR 2 elsewhere; adaptive resolution only lowers it when the GPU is the
bottleneck and climbs straight back when there is headroom. F3 shows the render resolution and upscaler.

## Saves, updates and privacy

Normal installations save under Godot's platform user-data directory:

- Windows: `%APPDATA%\Godot\app_userdata\Burn`
- macOS: `~/Library/Application Support/Godot/app_userdata/Burn`
- Linux: `~/.local/share/godot/app_userdata/Burn` (or the configured XDG data location)

Copy the `saves` folder to back up progress. Updates do not intentionally delete it.

Exported builds check `api.github.com` for the latest **stable** release on startup, when auto-update
is enabled. A matching platform/engine `.pck` is downloaded to user data, checked against GitHub's
SHA-256 asset digest, and applied by relaunching at the title screen or on the next launch. A running
campaign is not interrupted. The previous pack is kept for boot-failure rollback. Engine upgrades require
a full archive download. Missing verification metadata causes an update to be refused.

**Preview releases are not auto-installed.** No telemetry is implemented. The update request reveals the
usual network information to GitHub. Disable it under Settings → Gameplay → Auto-update, or use `--no-update`.
The updater still needs exported-build, end-to-end validation on all three operating systems.

## Run from source

Install [Godot 4.7.2](https://godotengine.org/download), then:

```sh
git clone https://github.com/sebastianmiletic/burn.git
cd burn
godot --headless --path . --import
godot --path .
```

Open `project.godot` in the Godot editor to inspect or develop the game. Assets are local; gameplay
does not require an asset service. Third-party asset credits/licenses are in [CREDITS.md](CREDITS.md).

Useful flags after `--`:

```text
--skip-intro
--solo --seed=1234 --slot=0
--solo --continue --slot=0
--host --name=Ash
--join-address=127.0.0.1:47211 --name=Ember
--no-update
--data-dir=/absolute/path/to/sandbox
```

## Test, build and release

See [DEVELOPMENT.md](docs/DEVELOPMENT.md) for isolated tests, cross-platform exports, release steps,
profiling commands and checksums. [RELEASE_STATUS.md](docs/RELEASE_STATUS.md) distinguishes tested
behavior from remaining work. [ARCHITECTURE.md](docs/ARCHITECTURE.md) describes the original modules;
the current additions are summarized in [WORLD_V2.md](docs/WORLD_V2.md).
