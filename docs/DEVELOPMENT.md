# Development and releases

## Requirements

Godot 4.7.2, its export templates, Git, Python 3, and Bash for the test scripts. On Windows use
Git Bash or WSL for shell scripts; the game itself does not require either. Vulkan/Metal is required
for GPU tests. Headless tests do not measure rendering quality or frame rate.

## Isolated validation

Run from the project directory. All commands below keep test saves, caches and logs under `build/`.
Do not use your real save folder for scripted playtests.

```sh
mkdir -p build/validation
godot --headless --path . --import --log-file "$PWD/build/validation/import-engine.log"
godot --headless --path . --log-file "$PWD/build/validation/unit-engine.log" \
  -s res://tests/run_tests.gd -- --data-dir="$PWD/build/validation/user" > build/validation/unit.log 2>&1
python3 tools/check_log.py build/validation/unit.log
godot --headless --path . --log-file "$PWD/build/validation/play-engine.log" \
  -- --playtest --no-update --data-dir="$PWD/build/validation/play-user" > build/validation/play.log 2>&1
python3 tools/check_log.py build/validation/play.log
godot --headless --path . --log-file "$PWD/build/validation/flow-engine.log" \
  -s res://tests/game/flow_test.gd -- --data-dir="$PWD/build/validation/flow-user" > build/validation/flow.log 2>&1
python3 tools/check_log.py build/validation/flow.log
godot --headless --path . --log-file "$PWD/build/validation/act-engine.log" \
  -s res://tests/game/activity_test.gd -- --data-dir="$PWD/build/validation/act-user" > build/validation/act.log 2>&1
python3 tools/check_log.py build/validation/act.log   # villagers + every activity (--only=npc,board,treasure,...)
bash tests/net/run_net_test.sh
bash tests/net/run_game_mp_test.sh --address --latency 150 --loss 0.02
```

Always check the engine exit code **and** scan logs. Godot can print runtime errors yet exit zero.
`check_log.py` rejects script/shader errors; an existing resource-at-exit warning is documented separately.

The gameplay test covers actual smooth mining, item drops/pickup, filling, quests, combat, death,
respawn, Hades rewards, gated Ryft travel and saved unlocks. Boss phase/attack simulations are in unit tests.
Multiplayer tests use separate processes and isolated characters. Run LAN discovery tests sequentially
with other network tests to avoid port collisions.

## Visual checks and profiling

```sh
godot --path . --log-file "$PWD/build/validation/gpu-engine.log" -- \
  --capture-game="$PWD/build/validation/captures" --tour=village,peaks,dragonfight \
  --style=4 --quality=2 --no-update --data-dir="$PWD/build/validation/gpu-user"
```

Villagers and activities in first person (JPGs; `--shots=npc,smith,night,board,elite,tracks,treasure,meteor,ring,raid`):

```sh
godot --path . --resolution 1600x900 -s res://tests/gpu/activity_capture.gd -- --out="$PWD/build/validation/act-shots" \
  --style=4 --quality=2 --no-update --data-dir="$PWD/build/validation/gpu-user"
```

`--ui=map,journal` also shoots those HUD screens at every stop; `--load-timing` prints the loading film's
frame stats (`[loading] ... frames > 33 ms`). The UI gallery (`res://tests/gpu/ui_gallery.tscn -- --capture=<dir>
--only=hud,journal,map,icons,loading,lobby,downed`) covers the HUD, map symbols, the loading film and the lobby.
The capture directory contains PNGs and `report.txt`. `--style=1` tests full-colour ASCII. F3 shows live
performance. Record hardware, window/output resolution, actual viewport resolution, graphics preset,
render style, adaptive resolution, averages and worst frames. Do not report headless frame rates as game FPS.
Captures can warm shader caches, so also measure a cold start and travel into new chunks.

## Export locally

```sh
mkdir -p build/windows build/linux build/macos
godot --headless --path . --export-release Windows build/windows/Burn.exe
godot --headless --path . --export-release Linux build/linux/Burn.x86_64
godot --headless --path . --export-release macOS build/macos/Burn.zip
```

Exports use embedded data for Windows/Linux and a universal macOS bundle. They are unsigned/ad-hoc signed.
Keep test recordings, private credentials, export signing keys, caches and saves out of version control.
`build/` and `dist/` are ignored. Version/platform/engine-qualified update packs are separate `.pck` assets.

## GitHub release workflow

`.github/workflows/release.yml` imports assets, runs unit/gameplay/multiplayer checks, exports the three
platforms, produces update packs/checksums and attaches artifacts. It requires repository Actions to be
enabled, permission to write releases, and the referenced official Godot release/templates to be available.

1. Update `application/config/version` in `project.godot` and release notes. Keep it numeric `MAJOR.MINOR.PATCH`.
2. Run validation and inspect GPU captures. Back up old saves and test migrations.
3. Commit the source, then push a version tag, for example `v0.4.1`.
4. The workflow creates a **prerelease** by default. Test those actual downloads on native Windows, macOS
   (both architectures where possible) and Linux. Check firewall, controller-free mouse capture, sound,
   save/continue, co-op, old saves, cold start and shader compilation.
5. Test the updater using two exported versions: valid digest, corrupted download, interrupted download,
   failed restart, rollback, offline launch, and an update completing while playing.
6. Only after those checks, promote the release to stable in GitHub. Stable promotion makes it eligible
   for auto-updates. Never publish a half-tested build as stable just to make `/releases/latest` work.

GitHub publishes a SHA-256 digest for release assets. The updater refuses packs without that digest.
The release's `SHA256SUMS.txt` also lets players check the full downloads manually:

- Linux: `sha256sum -c SHA256SUMS.txt` (download all listed files, or check your chosen file separately).
- macOS: `shasum -a 256 Burn-0.4.0-macOS.zip` and compare its line in `SHA256SUMS.txt`.
- PowerShell: `Get-FileHash .\Burn-0.4.0-Windows.zip -Algorithm SHA256`.

## Co-op trust model

The host controls enemies, drops, terrain changes and progression unlocks. Player movement/inventory is
client-local. The protocol rejects malformed positions and invalid dimensions, checks digging distance,
held tool and timing, and rejects cube deletion of natural ground. This is not a complete anti-cheat
system. Do not expose a server to untrusted players expecting authoritative inventories or movement.

No relay service, account system, matchmaking service, host migration or dedicated-server distribution
is included. Internet connectivity depends on routing/UPnP/port forwarding or a private VPN.
