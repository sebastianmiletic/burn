# BURN: handoff notes (16 Oct 2026)

Written for whoever continues this project (human or another AI). It covers what the game is, what state it is in, what was being worked on, what is left, how to test, and the gotchas that cost time.

## 0. Continuation update (16 Oct 2026)

**Read this first: sections 1–8 below are the previous handoff and some branch/release statements are historical.**

- Both WIP branches are now merged into `main`: rendering `831cf10`, creatures `b2c154c`. No conflicts.
- Full isolated validation passed after rendering (149 unit tests), after creatures (149), for release
  (151), and on post-release main (**152**). Latest all-green logs: `build/validation/horizon-safety/`;
  `results.txt` records engine and log-check exit codes. Both network scripts checked child/engine logs.
  Two additional simulated-lag gameplay runs passed (`mp-repeat-1.log`, `mp-repeat-2.log`). Linux
  **main CI run 38900890509 passed** the full process (152 units), all log checks and all three exports;
  workflow-dispatch artifacts only, not a new release. Log: `build/validation/main-ci-success.log`.
- A transport-only test sampled 94 ms localhost RTT immediately after bulk transfer. `911538a` allows
  bounded settling without widening latency limits or accepting a missing/zero ping.
- Follow-up visual work: `6bddd85` reduces excessive organic bump relief, filters fur aliasing, adds
  finer first-person hands and reduces red underworld fog; moves offhand light to the correct side.
- `27d4e08` fixes held-item/elevated-view capture fixtures and removes unused gameplay particles from
  the loading film's private viewport. This clears the reproduced Metal particle-shader/RID errors.
  In-game Leviathan effects are unchanged. A no-particles animation regression test was added.
- `77dac51` adds a bounded ring fallback when random event placement probes miss open ground. Activity
  integration now tests three Golden Hart placement streams and reports its world seed. The reproducible
  full activity command includes `--seed=1717`; CI now runs it (`c2f6c5b`).
- GPU captures were actually opened: caves/mines, mountain/shore views, weather, boss arenas,
  first-person tools/actions, and the 45-shot creature gallery/contact sheets. Latest world tour:
  `build/validation/visual/final/`, log `build/validation/visual-final.log` (exit 0, checker 0).
  Earlier failed probe/capture logs are retained, not counted as passes.
- **Visual acceptance is NOT complete.** Models remain stylized; faces/anatomy/fur, first-person
  torch highlights, overly busy ore patches, terrain seams and flora need substantial work.
  No honest claim can be made that the game is hyperrealistic or fully professional yet.
- **60 fps is NOT met.** Latest M4 High/adaptive/MetalFX tour at 2940×1846: 26–44 fps averages,
  worst sampled frames ~75 ms, internal resolution 809×508–1169×734. GPU timestamps are zero on
  Metal. The extra game process from the initial runs was gone for the final run, but other desktop
  work was not controlled. Draw calls/streaming/CPU load need profiling.
- Native Windows/Linux graphics and mixed-OS play remain unverified. Only macOS runs here; Linux
  headless CI is automated coverage, not graphical/laptop certification.
- **v0.5.0 is published as a prerelease**, tag at `9b3ae03`. First GitHub run `38858855851` failed
  activities before export. Fixed vertical event queries/test teleports/ring ownership; retagged run
  **38860699636 passed** all Linux checks, exports and publication. Windows/Linux/macOS downloaded
  archives match checksums. Actual macOS app: ad-hoc signature verification, isolated headless menu
  and solo/world-load smoke tests passed (`export-menu.log`, `export-solo-confirm.log`). Not graphical
  Windows/Linux certification. Do NOT promote to stable yet.
- **Source main is now unreleased 0.5.1 / protocol 4**, not the downloadable protocol-3 v0.5.0.
  `092554f` implements guest-lobby party-rule mirroring, live changes, read-only summaries and reset
  on leave; transport tests cover those cases and session consistency. Both UI states captured and
  opened in `lobby-ui-fixed/`; its log passes. Use matching source builds in co-op.
- `131fdd9` avoids captured freed Nodes in death-cleanup timers and isolates weather-charm test
  effects/targets. `b050442` keeps horizon generator sampling on the preparation worker after a
  native MP-loading crash in `_surface_v3` (`mp.LFUpmR/client.txt`). Full suite + two repeat MP runs
  then passed. **Sporadic native crash elimination is not proven; stress loading/teardown further.**
- Pending section-3 backlog: true species flora/missing ground cover, surface rivers, mini-boss mine
  guardians, boss warmup, bespoke humanoid attack animation, art/performance/native-platform gates.
- Disk: removed obsolete worktree `build/` outputs (~1.5 GB) and redundant generated **test audio
  caches under `build/validation/` only** (~5.8 GB). Logs, test saves, worktrees/branches and all real
  player data remain intact. About 11 GiB free at last check; recheck before exports/downloads.

### Where to continue next

1. Profile High on a quiet machine, starting with village draw calls/vegetation and streaming; the
   measured 26–44 fps is a real blocker, not something to hide by lowering internal resolution.
2. Stress repeated host/client loading and shutdown on both macOS and Linux after the horizon-worker
   mitigation. Keep the failed `mp.LFUpmR` log for comparison. Do not call it conclusively fixed yet.
3. Continue section 3's remaining world/art work: species-specific flora and missing ground cover,
   surface rivers, scaled mine guardians, loading-time boss warmup and boss attack animations.
4. Obtain actual Windows/Linux laptop and mixed-OS playtests, plus exported updater/migration tests.
5. If releasing the post-release lobby fix, use a **new** tag (e.g. v0.5.1), do not move v0.5.0 again.

See `docs/RELEASE_STATUS.md` for the current verification record and limitations.

---

## 1. What this is

**BURN** is a first-person, open-world, dark-fantasy action RPG made in **Godot 4.7.2** (GDScript, Forward+ renderer).

- **Project:** `/Users/sebastianmiletic/Coding/Burn`. Git `main` is the source of truth.
- **GitHub:** https://github.com/sebastianmiletic/burn. Latest published preview: **v0.5.0**. Source main contains post-release work (see section 0).
- **Version:** `config/version` in `project.godot` (currently unreleased `0.5.1`).
- **Running it:**
  - Install Godot 4.7.2.
  - On first run, import assets: `godot --headless --path . --import`
  - Then play: `godot --path .`

### What the player gets (all on `main`, tested)

- **World and terrain**
  - Smooth sculpted voxel terrain (Surface Nets over a density field) with PBR textures. Nothing renders as blocks.
  - The **world revision 3** map is 4608 m across, about 9.7 km² of land, with 13+ biomes. New biomes include the Elderwood redwoods, Red Mesas, Highmere Alps, Pale Tundra, Brimstone Badlands volcano and Kaldfjord coast.
  - Real mountains, lakes and ravines. There is no surface river system yet.
  - Cave network with natural mouths, pits, sinkholes and underground rivers, plus cave biomes: geyser, crystal sanctuary, mushroom, ice, magma, flooded.
  - **8 full abandoned mines**: multi-level, with timber, rails, carts, ore seams, loot, a guardian and a breakthrough into the caves.
  - Modelled cave decor: ore crusts and crystals, dripstone, glowing fungi, real webs.
- **Mining and building**
  - Mining *sculpts* the ground with a server-side `plan_dig`.
  - The **pick-axe is a multitool**: it digs, and fells trees as fast as an axe of its tier.
  - Each strike shows a fading crack decal (no selection box).
  - Dirt, stone and sand can be packed back onto the ground (`plan_fill`).
  - Felling a tree drops the whole tree. Rare woods need higher-tier tools.
- **First person (default)**
  - The arms are real skinned character arms on an IK rig, holding the item.
  - In first person the player's own body is shadow-only, so there is no self-clipping.
  - `V` toggles third person.
  - Movement has a jump buffer, coyote time and no bunny-hopping.
  - The camera can't see through terrain.
  - Looking at something for 1 s shows what it is next to the minimap (`Events.look_info`).
- **Buildings and arenas**
  - Villages, houses, shrines, towers and ruins are modelled architecture with interiors.
  - **Every boss arena (the battlegrounds) is modelled** with animated gates. That covers the Dragon's Keep, crypt, Mountain Hall, Broodmother lair, Hagsfen, Drowned Spire, Gates of Hades, Tartarus, Throne of Hades and both Ryft lairs.
  - Collision is invisible `Blocks.STRUCTURE`; unit tests forbid visible cube blocks.
- **Bosses**
  - Ashvane (dragon), Cerberus, Vexhira (Broodmother), Warden, Mountain King, Hades, Old Mother Mire, the Leviathan, Prism Sentinel and Void Sovereign. All have bespoke models and multi-phase fights.
  - **Bosses do not heal to full.** `BossLedger` keeps wounds per arena, saved with the world; a boss only recovers after 10 minutes untouched.
- **Activities**: treasure maps, village bounty boards, starfall nights, village raids, the Golden Hart, the Proving Ring, and weather charms (Storm Horn, Sunstone, Fog Lantern, Frost Totem).
- **NPCs**: they navigate around buildings, follow day/night routines, face the player when talked to, and give quests.
- **UI**
  - Smooth minimap and world map with grey fog of war, boss icons and activity markers.
  - Journal with tabs, quest tracker and compass.
  - Leviathan loading film and the main menu.
  - Boss bar that hides away from the fight.
- **Multiplayer**
  - LAN rune codes, or join by address with UPnP.
  - The host is authoritative.
  - **Revives**: with the host lobby option "Shrine respawns" off (the default), downed players can be revived by a teammate (E for 3 s), otherwise they bleed out after 90 s; if the whole party is down, everyone respawns at their shrines.
- **Platforms**
  - On first launch, integrated laptop GPUs start at Medium quality.
  - Renderer fallbacks are set: D3D12, Vulkan, OpenGL.
- **Updates**: the auto-updater (`core/updater.gd`) downloads update packs from GitHub *stable* releases.

---

## 2. Work in progress: two finished-but-unmerged branches

Both were paused just before their final test run. **Both already contain the latest `main`**; each is ahead of `main` by its own commits only.

| Branch (local; short alias shown) | Ahead of main | What it does | State |
|---|---|---|---|
| `worktree-agent-a55155e555e9708e5` (alias `wip/rendering`) | 10 commits | **Removes the ASCII renderer entirely.** WorldView renders the world directly with MetalFX/FSR spatial upscaling and measured adaptive resolution. Also: cave lighting palettes (no white-out), geomorphing distant-mountain horizon with snowcaps and haze matched to the sky (never white), ultra lighting tweaks, a random **weather system with events** and a `Weather.request(state, seconds, source_peer)` summon API (the weather charms use it), and a real snow state. | Feature-complete. Was doing a final high-viewpoint mountain check. **Run the full tests, look at GPU captures, then merge.** `rendering/materials/ascii_material*` remains on purpose: it is only a material-class encoding helper, harmless, and could be cleaned up later. |
| `worktree-agent-a3d1eafe28f6deca9` (alias `wip/creatures`) | 13 commits | **Rebuilds every ordinary mob to boss quality** with skinned bodies (MobRig/MobModel):<br>• quadrupeds with fur shells<br>• spiders and scorpions with IK gait<br>• centipede, shark, fish<br>• shade (hooded wraith), imp, cave bat, birds<br>• golem, fire elemental<br>• sculpted skeletons, archers, trolls, ghouls, the drowned<br>Mob meshes are prebuilt while the world loads (`Models.warmup_mobs`). | Feature-complete. Was about to run the full test process. **Run the tests, look at the creature gallery, then merge.** |

These branches exist only on this Mac (not pushed to GitHub yet). To share them: `git push origin main wip/rendering wip/creatures`.

They are also left as git worktrees under `.claude/worktrees/agent-…`. Those folders can be deleted once the branches are merged (`git worktree remove --force <path>`, then `git branch -D <branch>`).

### Suggested order

1. Merge the rendering branch.
   - `git merge wip/rendering` (or the local `worktree-agent-a55155e555e9708e5`).
   - Resolve conflicts if any. This touches a lot: `world/game_world.gd`, `ui/menu_backdrop.gd`, the `world/sky/*` files, `rendering/*`, `core/settings.gd` (the style key removed), `ui/settings_menu.gd`, and tests that referenced ASCII.
2. Run the full test process (section 4). Fix anything red.
3. Merge the creatures branch the same way, then run the full test process again.
4. Run the GPU captures (section 4) and look at them. Especially check:
   - caves (`sanctuary`, `geyser`, `w_mine`, `w_minein`)
   - mountains (`vista`, `w_peak`, `w_vista`)
   - weather (`storm`, `snow`)
   - creatures (`--mobs`, and `tests/gpu/creature_gallery.tscn`)
   - boss arenas (`arena_<id>` or the `cam:` stops)
   - first person (`--hold=pickaxe_stone`, `--hold=sword_iron`, `--action=attack`, `--dig=10`)
5. Update the README: remove the ASCII sections, describe the new features and controls, and fix the download links.
6. Release (section 5).

---

## 3. The user's requests: status checklist

The user wants a complete, professional, hyperrealistic, first-person game with no blocky models anywhere, that they and their friends can download and play together on Windows, macOS and Linux laptops.

**Done on `main`:** everything in section 1, which covers these requests:

- [x] Not a block game: smooth terrain, modelled buildings, modelled arenas.
- [x] Mining that doesn't mine blocks: sculpting.
- [x] Multitool pick-axe, no white square, break effect where it hits.
- [x] First person by default, own-character glitches fixed, third person on V.
- [x] Movement fixes; no seeing through ground and walls while mining or climbing.
- [x] All boss arenas (battlegrounds) modelled, no cubes.
- [x] All boss models rebuilt (the Leviathan was the quality bar).
- [x] Bosses don't heal to full.
- [x] Fun activities beyond boss fights and talk quests; NPCs fixed.
- [x] Weather charms (summon or use weather). They need the rendering branch's `Weather.request` to be fully effective; they fall back gracefully without it.
- [x] Map 2–3× bigger with new complete biomes, real mountains, cave openings, connected full mines, better caves, modelled ores/mushrooms/webs.
- [x] Minimap not blocky; grey until discovered; boss icons (skull, fish, dragon, spider, crown, flame, paw, witch hat, crystal).
- [x] Better quest UI (journal tabs, current objective, show on map).
- [x] Leviathan loading cinematic.
- [x] Multiplayer revive teammates; host lobby option "Shrine respawns" (default off).
- [x] Look-at info next to the minimap.
- [x] Boss bar hides when you're not at the boss.
- [x] Location label doesn't say "Frosthold" when you're in a cave under it.
- [x] Laptop-friendly defaults and renderer fallbacks.

**Done on the unmerged branches (section 2):**

- [~] Remove ASCII completely; ultra-realistic lighting; caves lit naturally and never white; distant mountains never white; weather that genuinely changes randomly with events. (`wip/rendering`)
- [~] Ordinary mobs no longer blocky. (`wip/creatures`)

**Not done or not verified:**

- [x] **Publish a new release**: v0.5.0 prerelease, all three platforms; see section 0 for verification limits.
- [ ] **60 fps minimum at High on all hardware**: not verified. On the user's Apple M4 at 2940×1846 most scenes ran around 45–60 fps, but always under heavy load from other processes. Measure on a quiet machine with `F3` and the capture tool's report.
- [ ] **Native testing on Windows and Linux laptops**: never done. Only macOS has been run, and the Linux CI runner runs the headless tests.
- [x] Guest lobby party rules: fixed and tested on **unreleased 0.5.1 main**, not the v0.5.0 downloads.
- [ ] Flora gaps:
  - no true redwood or birch models (redwoods are scaled pines, and Flora caps trees at 20 m);
  - no cacti or tundra lichen;
  - some new soils grow no ground flora.
- [ ] No surface river system.
- [ ] Mine guardians are ordinary mobs, not scaled mini-bosses.
- [ ] Bosses' first spawn can hitch 0.4–3 s while their model builds. It is cached afterwards; warming boss models during loading would fix it.
- [ ] Boss attack animations still use the shared humanoid animator for the humanoid bosses (idle/wait poses are custom).
- [ ] Hell arenas are washed strongly red by the underworld fog. The rendering branch may already improve this; check.
- [ ] Small visual nits listed in section 6.

---

## 4. How to test (do this after every merge)

Read `docs/DEVELOPMENT.md` for the full version. Key points:

```sh
cd /Users/sebastianmiletic/Coding/Burn
mkdir -p build/validation
godot --headless --path . --import > build/validation/import.log 2>&1
godot --headless --path . -s res://tests/run_tests.gd -- --data-dir="$PWD/build/validation/user" > build/validation/unit.log 2>&1
godot --headless --path . -- --playtest --no-update --data-dir="$PWD/build/validation/play-user" > build/validation/play.log 2>&1
godot --headless --path . -s res://tests/game/flow_test.gd -- --data-dir="$PWD/build/validation/flow-user" > build/validation/flow.log 2>&1
godot --headless --path . -s res://tests/game/activity_test.gd -- --seed=1717 --data-dir="$PWD/build/validation/act-user" > build/validation/act.log 2>&1
bash tests/net/run_net_test.sh            # LAN discovery/lobby scenarios
bash tests/net/run_game_mp_test.sh --address --latency 150 --loss 0.02   # host+client play, revive
for f in import unit play flow act; do python3 tools/check_log.py build/validation/$f.log; done
grep "tests," build/validation/unit.log          # expect "N tests, 0 failures" (154 at last count on main)
```

**Test gotchas**

- The unit suite takes **15–25 minutes** (boss fight simulations). Give it a long timeout.
- `tools/check_log.py` fails on script or shader errors even when Godot exits 0. Always run it.
- Run the `tests/net/*.sh` scripts with **bash**, not zsh. One of them uses a variable named `status`, which is read-only in zsh.
- macOS has no `timeout` command. Use `perl -e 'alarm 600; exec @ARGV' <cmd>`.
- After adding a new `class_name` script, run `godot --headless --path . --import` again, or other scripts fail to parse.
- The playtest check "packed earth back into the hole" was flaky once (dropped items used to block filling). That is fixed, but watch for it.

**GPU captures (visual checks)**

```sh
godot --path . --fullscreen -- --capture-game="$PWD/build/validation/shots" \
  --tour=village,vista,peaks,arena_dragons_keep,sanctuary --quality=2 --no-update \
  --data-dir="$PWD/build/validation/gpu-user" [--hold=pickaxe_stone] [--action=attack] [--dig=10] \
  [--third-person] [--press=move_forward,sprint] [--no-hud] [--ui=map,journal]
```

- Captures take over the screen; the window must stay focused.
- The capture writes PNGs plus `report.txt` (fps, draw calls).
- **Stops:** see `STOPS` in `tests/gpu/game_capture.gd`. There are also `arena_<location id>`, `cam:<loc>:ox:oy:oz:yaw:pitch[:time]` and the `w_…` world stops (`w_peak`, `w_mine`, `w_mouth`…).
- **`--style=4`:** existed for ASCII-off. After the rendering merge, ASCII styles are gone and the flag may be ignored.
- **Galleries:** `tests/gpu/creature_gallery.tscn`, `boss_gallery.tscn`, `model_gallery.tscn`, `ui_gallery.tscn`, `items_gallery.tscn`. Run with `--fullscreen` and `-- --capture=/abs/dir`.
- **Agent-only lock:** helper agents serialized GPU runs with a lock directory, `/tmp/burn_gpu.lock` (`mkdir`/`rmdir`). Only needed if several processes capture at once.

---

## 5. Releasing (so friends can download)

The release pipeline is `.github/workflows/release.yml`. On a pushed tag `v*` it:

1. installs Godot 4.7.2 and its export templates on an Ubuntu runner;
2. imports assets;
3. runs unit, playtest, flow and network tests (log-checked);
4. exports Windows (`Burn.exe`), Linux (`Burn.x86_64`) and macOS (universal zip, ad-hoc signed);
5. builds per-platform update packs and `SHA256SUMS.txt`;
6. publishes a GitHub **prerelease** with all files.

Steps:

1. Bump `config/version` in `project.godot` (numeric `MAJOR.MINOR.PATCH`, e.g. `0.5.0`).
2. Commit, then `git push origin main`.
3. Tag: `git tag v0.5.0 && git push origin v0.5.0`.
4. Watch the run: `gh run watch` or the repo's Actions tab.
   - If the CI tests fail, fix and re-tag (delete the bad tag first).
   - The CI unit suite is long; the job timeout is 60 min, so raise it if needed.
5. Download the artifacts and smoke-test them (at least macOS here).
6. **Auto-update** only picks up *stable* releases (`/releases/latest` excludes prereleases). Once the builds are checked on real Windows, Linux and macOS machines, mark the release as stable in GitHub so installed copies update themselves. `docs/RELEASE_STATUS.md` has the release-quality policy written by an earlier session.
7. Update `README.md`'s download table and `docs/RELEASE_STATUS.md`.

Player instructions (also in the README):

- **Windows:** unzip and run `Burn.exe` (SmartScreen: More info → Run anyway).
- **macOS:** move the app to Applications, then right-click → Open (or `xattr -dr com.apple.quarantine /Applications/Burn.app`).
- **Linux:** `tar xzf …` then `./Burn.x86_64`. Needs Vulkan; there is an OpenGL fallback.
- **Multiplayer:**
  - On the same Wi-Fi, host → share the 4 runes.
  - Over the internet, host → UPnP shows an address, or forward UDP 47211, or use Tailscale/ZeroTier.
  - Windows and macOS firewalls will ask to allow the game the first time.

---

## 6. Known issues and nits collected from the work reports

**Characters, creatures and NPCs**

- The first time each new boss or creature appears there can be a short hitch while its mesh builds. The creatures branch warms mob meshes during loading; bosses are not yet warmed.
- The bog hag's face is the simplest part of her model. Cerberus is the weakest of the three beasts: its heads sit close together.
- Bosses in arena captures idled without turning to the player before the fight. The beast bosses now head-track; this is unverified in-game.
- Hunt tracks for legendary bounties are easy to lose in tall grass by day.
- Guests' rank isn't known on the host, so starfall guardian strength uses the host's view of it.
- First-person arms use the character's real arm mesh; the hand fist can look slightly blocky up close.

**Buildings and arenas**

- Collision cells are 1 m, so there are small invisible margins around round pillars and towers, and the visual stairs don't match the 1 m step-ups exactly.
- In Frosthold, snow-covered paths read a little flat.
- Broodmother sheet webs read as straight crossing strands.

**Terrain, weather and the world**

- From far away, snow and ash material boundaries show 1 m stair-stepped edges, a limit of the voxel material system.
- The Elderwood draws a lot of trees; redwood stands were thinned. Check the frame time there.
- One capture crashed once inside the threaded `WorldGen.prepare()` biome-blend pass (signal 11). It could not be reproduced.
- The weather charms need `Weather.request` (on the rendering branch) to be fully effective.

**Menus, loading and saves**

- The menu backdrop prepares a revision-3 world (slower).
- The loading film averages about 53 fps during a real world load, with main-thread spikes from world spin-up (architecture, flora warmup, mesh uploads).
- The fog-of-war side file (`saves/map_fog_<slot>.burn`) is per machine; the main save also stores it.
- The unit test runner prints ObjectDB leak warnings at exit. These are known and harmless.

---

## 7. Where things are (code map)

**Core and player**

| Area | Files |
|---|---|
| App flow, saves, settings, keybinds, updater | `core/` (`game.gd`, `settings.gd`, `keybinds.gd`, `updater.gd`, `save_system.gd`, `events.gd`) |
| Networking (runes, LAN discovery, ENet, UPnP, lobby options) | `network/net.gd`, `network/lan_discovery.gd`, `network/rune_code.gd` |
| Player (first person, viewmodel, movement, mining, revive, look-at info) | `entities/player/` (`player.gd`, `player_camera.gd`, `viewmodel.gd`, `look_inspector.gd`, `block_highlight.gd`) |
| Physics (smooth-field and box collision, step-up) | `physics/voxel_body.gd` |

**World**

| Area | Files |
|---|---|
| Voxel world, density, meshers, dig/fill | `world/voxel/` (`voxel_world.gd`, `smooth_mesher.gd`, `chunk_mesher.gd`, `world_gen.gd`, `blocks.gd`) |
| World generation (revision 3), caves, mines | `world/voxel/world_gen.gd`, `world/caves/`, `world/cave_biomes.gd`, `world/environment_details.gd` |
| Locations, villages, architecture | `world/structures/` (`location_planner.gd`, `structures.gd`, `architecture.gd`, `exploration_sites.gd`), `world/architecture/` |
| Battlegrounds | `world/structures/battlegrounds.gd`, `world/structures/lairs.gd`, `world/architecture/arenas/` |
| Game world, replication, director, spawner | `world/game_world.gd`, `world/replicator.gd`, `world/location_director.gd`, `world/wild_spawner.gd`, `world/location_tracker.gd` |
| Sky, weather, lighting, distant land | `world/sky/`, `world/distant_land.gd`, `rendering/graphics_quality.gd` |
| Flora | `world/flora/` |
| Activities | `world/activities/` |

**Content and UI**

| Area | Files |
|---|---|
| Bosses and mobs | `entities/bosses/`, `entities/enemies/`, `entities/wildlife/`, `models/creatures/`, `models/models.gd`, `combat/` |
| Characters (humanoids) | `models/humanoid_model.gd`, `models/character/` |
| Items, crafting, quests | `items/`, `models/items/`, `models/held_items.gd`, `quests/` |
| NPCs | `entities/npc/` (`npc.gd`, `npc_nav.gd`, `village_layout.gd`, `npc_dialogue.gd`) |
| UI | `ui/` (HUD, minimap and map layers, journal, menus, lobby, loading film) |
| Audio | `audio/` |
| Tests | `tests/unit/`, `tests/game/`, `tests/net/`, `tests/gpu/`, `tools/check_log.py` |

**Documents:**

- `docs/ARCHITECTURE.md`: module contracts. Partly outdated: it still describes ASCII.
- `docs/DEVELOPMENT.md`: tests and release.
- `docs/V4_PLAN.md`: last round's rules and ownership.
- `docs/WORLD_V2.md`: world generation.
- `docs/BOSS_GUIDE.md`: boss rules and progression.
- `docs/RELEASE_STATUS.md`: release policy and verification record.
- `docs/REALISM_CONTRACTS.md` / `V3_CONTRACTS.md`: older contracts.

---

## 8. Practical gotchas

- **Disk space:** on this machine it has run low several times. Each git worktree plus its `.godot` import is about 300 MB. Delete old capture folders and `build/` exports when space gets tight. Never delete `~/Library/Application Support/Godot/app_userdata/Burn`: that folder holds the user's saves and settings.
- **Test isolation:** never let tests use the user's saves. Always pass `--data-dir=<somewhere under build/>`.
- **Another Claude session:** one once worked in the same folder concurrently. Check `git status` and file timestamps before big edits.
- **Edit outside the editor:** Godot's editor isn't needed. Everything is built in code; scenes are thin.
- **Save compatibility:** keep old saves loading. World revisions are versioned (`WorldGen.LATEST_REVISION = 3`, while old saves keep revision 2). Edits are stored as `block | (density + 1) << 8`.
- **User preferences:** first person, no ASCII, no blocky models, realistic lighting, 60 fps, friends on Windows, macOS and Linux. They also like being told plainly what was done and what wasn't.
