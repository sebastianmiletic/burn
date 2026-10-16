# BURN

A first-person, open-world dark-fantasy action RPG built with **Godot 4.7.2 / Forward+**.
Explore mountain ranges and abandoned mines, sculpt tunnels with a pick-axe, forge equipment,
help villages, hunt legendary quarry, and fight through Hades' realm to reach the Ryft.
Play solo or in a party of up to eight trusted friends.

**Playable development preview, not a finished or hyperrealistic production game.** Models and
animation are procedural; visual polish, performance and native Windows/Linux testing remain work
in progress. Read [verification and limitations](docs/RELEASE_STATUS.md). There is no guaranteed
60 fps minimum.

## Download

[**v0.5.0 preview downloads**](https://github.com/sebastianmiletic/burn/releases/tag/v0.5.0)
· [All releases](https://github.com/sebastianmiletic/burn/releases)

| Platform | Download | Start |
| --- | --- | --- |
| Windows 10/11, x86_64 | [Windows ZIP](https://github.com/sebastianmiletic/burn/releases/download/v0.5.0/Burn-0.5.0-Windows.zip) | Extract everything and run `Burn.exe`. |
| macOS, Apple Silicon / Intel | [macOS ZIP](https://github.com/sebastianmiletic/burn/releases/download/v0.5.0/Burn-0.5.0-macOS.zip) | Extract, move `Burn.app` into Applications, then open it. |
| Linux, x86_64 | [Linux tar.gz](https://github.com/sebastianmiletic/burn/releases/download/v0.5.0/Burn-0.5.0-Linux.tar.gz) | `tar xzf Burn-0.5.0-Linux.tar.gz`, then `chmod +x Burn.x86_64 && ./Burn.x86_64`. |

These builds are unsigned/ad-hoc signed, not commercially signed or notarized. Verify the archive
against the release's `SHA256SUMS.txt` before accepting an unknown-publisher warning. Windows may
show **More info → Run anyway**; macOS may require right-click → **Open** or **Privacy & Security →
Open Anyway**. Do not disable system-wide security.

Use current GPU drivers. Metal on macOS and Vulkan/D3D12 on Windows/Linux are preferred; the project
also enables an OpenGL compatibility fallback. Start with 8 GB RAM and at least 1 GB free disk space.
Fallback configuration and successful exports do not certify every laptop's compatibility.

First launch prepares a procedural sound cache. World creation and model warmup also take time.
Integrated laptop graphics start at Medium; Apple Silicon and dedicated graphics normally start
at High. Lower the quality or output resolution if needed. **F3** shows frame rate, internal 3D
resolution and the upscaler; the HUD stays at native resolution.

## The world

New worlds use **world revision 3: 4,608 metres across, about 9.7 km² of land**, surrounded by ocean.
Nearby detailed terrain streams in while a distant horizon preserves mountain silhouettes.

- **Explore:** forests, marshes, alpine ranges, red mesas, tundra, volcanic badlands, redwood stands
  and a fjord coast. Some flora still uses placeholder species models.
- **Go underground:** natural cave mouths, sinkholes, underground rivers, crystal sanctuaries,
  fungal hollows, ice and magma chambers, and eight multi-level mines with rails, carts and loot.
- **Shape the land:** smooth rounded digging and filling, ore/tool tiers, and whole-tree felling.
  A pick-axe also cuts trees as effectively as an axe of its tier. Collision/storage uses a voxel
  grid; visible natural terrain is a smooth surface, not cubes.
- **Meet villages:** modelled architecture with interiors, NPC routines, merchants, quests,
  crafting stations, shrines and bounty boards.
- **Find other adventures:** treasure-map riddles and buried chests, elite hunts and tracks,
  starfall craters with starmetal, village raids, the Golden Hart and the escalating Proving Ring.
- **Weather matters:** changing rain, fog, snow and storms, plus blizzards, dust/ember storms,
  heatwaves, auroras and meteor showers. Craft a Storm Horn, Sunstone, Fog Lantern or Frost Totem.
- **Fight:** skinned wildlife and monsters, ten bespoke bosses, modelled battlegrounds and animated
  gates. Boss wounds persist; an untouched boss only recovers after ten minutes.
- **Navigate:** fog-of-war maps, boss/activity symbols, compass objectives and a tabbed journal.
  Looking at a nearby target briefly identifies it beside the minimap.

Older saves keep their recorded generation revision (including revision 1 and 2 worlds) rather
than moving terrain underneath saved edits. **Create a new world for revision-3 geography.** Back up
saves before updating.

## First steps

1. Start solo or host a party. Follow the marker to Emberfall's shrine and press **E** to set a checkpoint.
2. Speak with Elder Maren and the blacksmith; follow the journal's current objective.
3. Select the starting pick-axe with **2**. Hold left mouse to dig or chop; bring torches and potions.
4. Mine iron and coal, use the furnace/anvil, and improve your equipment. Try the bounty board or
   buy a treasure map when you want a break from the campaign.

The main route runs through the Warden, Mountain King and Ashvane, then the Gates of Hades,
Cerberus and Hades. Victory opens the gateway to the Ryft and its follow-up encounters.

## Controls

Rebind gameplay actions under **Settings → Controls**.

| Action | Default |
| --- | --- |
| Move / sprint / jump or swim up | WASD / Shift / Space |
| Look | Mouse |
| Attack / dig / chop | Left mouse |
| Use / place torch or material | Right mouse |
| Select hotbar | 1, 2, 3 / mouse wheel |
| Interact / revive teammate | E / hold E nearby for 3 seconds |
| Dodge | Ctrl |
| Fireball / light burst | Q / R |
| Drink potion | F |
| Inventory / journal / world map | Tab or I / J / M |
| First person ↔ third person | V (first person is the default) |
| Party chat | T |
| Pause / performance / screenshot | Esc / F3 / F12 |

## Multiplayer

Everyone must use the **same game version**. The downloadable v0.5.0 preview uses network protocol 3.
Unreleased source `main` is 0.5.1/protocol 4 and cannot join v0.5.0 parties; it adds live guest-lobby
party-rule summaries.

- **Same Wi-Fi/LAN:** Host a party, share the four runes, and have friends choose Join. Once they
  are ready, the host begins the campaign. Joining an active campaign is supported.
- **Internet:** the host attempts UPnP and may display a public address. Share that address for
  Join by address. Otherwise forward the displayed UDP port (normally **47211**) or use a private
  VPN such as Tailscale/ZeroTier. LAN rune discovery uses UDP **47210**, not global matchmaking.
  Carrier-grade NAT can prevent direct public hosting.
- Allow the game through Windows/macOS/Linux firewalls only on networks you trust.
- With **Shrine respawns off** (the default), teammates can revive downed players by holding E
  for three seconds. Bleed-out takes 90 seconds; a full-party wipe returns everyone to shrines.

The host owns monsters, terrain edits, drops and shared progression. Character inventories and
movement remain client-local: this is **trusted-friends co-op**, not an anti-cheat-secure public
server. No host migration, relay service or global matchmaking is included. Mixed-OS and real
internet play still need native-device testing beyond the automated loopback tests.

## Saves and updates

Normal saves and settings live in:

- Windows: `%APPDATA%\Godot\app_userdata\Burn`
- macOS: `~/Library/Application Support/Godot/app_userdata/Burn`
- Linux: `~/.local/share/godot/app_userdata/Burn` (or your configured XDG data directory)

Copy `saves/` to back up progress. Updates do not intentionally delete it.

Exported builds optionally check GitHub for a **stable** same-engine update, verify the asset's
SHA-256 digest and apply its data pack by relaunching from the menu or on the next launch. A running
campaign is not interrupted; the previous pack is retained for rollback. Engine upgrades need a
full download. **Prereleases are not auto-installed.** The updater still needs exported two-version
testing on all three OSes. Disable checks in Gameplay settings or pass `--no-update`.

No telemetry is implemented. Update requests expose ordinary connection information to GitHub.

## Run from source

Install [Godot 4.7.2](https://godotengine.org/download), then:

```sh
git clone https://github.com/sebastianmiletic/burn.git
cd burn
godot --headless --path . --import
godot --path .
```

Useful flags after `--`: `--skip-intro`, `--solo --seed=1234 --slot=0`,
`--solo --continue --slot=0`, `--host --name=Ash`, `--join-address=127.0.0.1:47211 --name=Ember`,
`--no-update`, `--data-dir=/absolute/path/to/sandbox`.

See [development/testing](docs/DEVELOPMENT.md), [architecture](docs/ARCHITECTURE.md),
[handoff](docs/HANDOFF.md), and [asset credits/licenses](CREDITS.md).
