# 0.5.0 preview: verification and limitations

This is a playable development preview, **not a finished, hyperrealistic or universally 60-fps game**.
Do not promote it to stable until the native-platform and updater release gates below are verified.
Published: [v0.5.0 downloads](https://github.com/sebastianmiletic/burn/releases/tag/v0.5.0).
Source `main` has since advanced to **0.5.1 development (protocol 4)**; v0.5.0 downloads use protocol 3.

## What changed

- Rendering and creatures work branches merged into main, preserving both sets of features.
- Direct 3D world rendering through WorldView; the glyph postprocessor and its settings are removed.
  Legacy material helper names remain but no longer encode roughness for a glyph renderer.
- Filmic lighting, cave-specific bounce/haze, distant mountain horizon, random weather events,
  real snow and the server-authoritative `Weather.request(state, seconds, source_peer)` API.
- Skinned ordinary mobs, IK gaits, fur shells, sculpted undead/humanoid enemies and loading-time mob caches.
- Revision-3 world (4608 m extent), expanded biomes, connected caves/eight mines, smooth excavation,
  modelled villages/arenas, first-person arms, boss wounds, activities, revives and map/journal improvements.
- Visual follow-up: reduced excessive creature bump relief, filtered subpixel fur noise, finer first-person
  hand meshes, corrected offhand light position and a less saturated underworld haze.
- Loading cinematic omits unused gameplay particles in its private viewport, eliminating the reproduced
  Metal particle-shader shutdown errors in the completed in-game capture run.
- Capture fixes: elevated world stops retain flight and held items can be moved out of the bag into the hotbar.
- Transport test keeps its RTT limits but waits for bounded post-transfer settling; missing pongs cannot pass.
- World-event placement falls back to bounded ring samples when random probes miss open ground.
- Release CI now includes the activity test as well as the existing unit/gameplay/flow/network checks.

## Local verification (16 Oct 2026)

Environment: macOS, Apple M4 (8-core GPU), Godot 4.7.2, Metal Forward+ for visible captures.
All test data was isolated under `build/`; the player's actual saves/settings were not used.

| Check | Result / evidence |
| --- | --- |
| Rendering-only merge | Full suite passed; 149 unit tests, zero failures (`build/validation/rendering/`) |
| Combined merge | Full suite passed after RTT harness correction; 149 unit tests (`combined-fixed/`) |
| Final release candidate | Import, 151 unit tests, playtest, flow, activities, both network scripts passed (`release-candidate/`, repeated after CI fixes in `ci-fixes/`) |
| Log checks | Every suite log and network child/engine log scanned with `tools/check_log.py` |
| Network | Six lobby scenarios; two-process combat, smooth mining, terrain validation and teammate revive at 150 ms one-way simulated latency / 2% loss |
| GPU tour | Villages, mountain views, sanctuary/geyser caves, mine workings, rain/storm/snow, Dragon's Keep and Hades arena captured and inspected |
| Creature gallery | Ordinary mob/action/head views captured; representative creatures inspected directly and gallery contact sheets reviewed |
| First person | Pick-axe/mining and iron sword/action captures; closeup mesh/light refinements inspected |
| GPU diagnostics | Latest complete world tour exits zero and passes log checker (`visual-final.log`, `visual/final/`) |

The unit runner still emits its documented ObjectDB/resource-at-exit diagnostics. The log checker permits
only the existing resource-at-exit message; particle shader/RID errors were not suppressed.

Earlier failed rounds are retained for diagnosis: localhost RTT 94 ms after bulk transfer, a Golden Hart
placement miss in a random world, and private-viewport particle shader teardown errors. They are not
represented as passes. The isolated experimental particle probes also crashed twice during native engine
shutdown; subsequent warmup probes and the final complete tour passed. Broader long-session shutdown
stability still needs testing.

## Performance and visual acceptance

The latest High/adaptive tour at **2940×1846 output** averaged **26–44 fps** across sampled scenes,
with worst sampled frames up to about **75 ms**. Actual internal 3D resolution varied roughly from
809×508 to 1169×734; MetalFX spatial was used. Metal GPU timestamps report zero, so these are wall-clock
frame timings, not GPU timings. Other desktop work was not controlled; the second game instance from
initial captures was no longer running for the final tour.

These measurements **do not meet the 60-fps requirement**, even at the reduced internal resolutions.
CPU work/draw calls/streaming need profiling rather than further blind resolution reductions.

Screenshots show improvement, not production-quality art acceptance. Remaining visible problems include
stylized anatomy/faces and fur tufts, overbright first-person fingers near torches, overly busy/saturated
ore patches, some distant terrain/streaming seams, and repeated/simple flora. No claim is made that
all geometry is now professional or hyperrealistic. Cave/mountain captures checked were not solid-white
washouts; that is a sampled check, not an all-world/all-weather guarantee.

## Publication record

First tagged run [38858855851](https://github.com/sebastianmiletic/burn/actions/runs/38858855851)
passed Linux unit/gameplay/flow but failed activity checks before export; no download was published.
The follow-up fixes query candidate ground near its actual surface (not unloaded high air), hold test
teleports during streaming and check ring-owned enemies rather than unrelated wildlife. The full local
suite passed again (`ci-fixes/`). The retagged run
[38860699636](https://github.com/sebastianmiletic/burn/actions/runs/38860699636) then passed all Linux
checks (151 unit tests, gameplay, flow, activities, both network scripts and engine log scanning),
exported all three platforms and published **v0.5.0 as a prerelease** at commit `9b3ae03`.

Downloaded Windows, Linux and macOS archives all match `SHA256SUMS.txt`. The actual macOS app passes
`codesign --verify --deep --strict`, isolated headless menu startup and a 60-second isolated solo run
that completed world loading, all log-checked (`export-menu.log`, `export-solo-confirm.log`). This is
not native graphical Windows/Linux or Intel macOS certification.

## Post-release main (unreleased 0.5.1)

- `092554f`: host rules mirror to guests before play, update live, are read-only for guests, reset on
  leave and match the campaign payload. Network protocol bumped to 4 for the changed lobby RPC;
  do not mix source main with v0.5.0 downloads. Both guest-rule states were captured and inspected
  (`lobby-ui-fixed/`, log checker passed).
- `131fdd9`: delayed dead-entity cleanup binds an ID, not a freed Node. Weather integration fixtures
  remain outside lightning's 2 m exclusion and expire the storm before testing unrelated charms.
- `b050442`: generator sampling for the distant horizon stays on the existing preparation worker.
  A previous two-process test crashed natively in parallel `_surface_v3` sampling
  (`mp.LFUpmR/client.txt`). This is a mitigation, **not proof the sporadic crash is eliminated**.
- Full suite passed afterwards in `build/validation/horizon-safety/`: **152 unit tests**, gameplay,
  flow, activities and both network scripts, all log-checked. Two additional simulated-lag multiplayer
  runs passed (`mp-repeat-1.log`, `mp-repeat-2.log`, with engine logs checked).
- Linux main run [38900890509](https://github.com/sebastianmiletic/burn/actions/runs/38900890509)
  passed the same full test process (152 units), log checks and Windows/macOS/Linux exports. It was a
  workflow-dispatch build, so it uploaded development artifacts without publishing another release.
- Earlier post-release rounds failed weather fixture/lifetime checks and one native multiplayer load;
  those failures are retained in their logs and are not represented as passes.

## Remaining release gates and content work

1. **Art:** production-grade characters, creatures, flora and cave materials; first-person grip/lighting,
   body joins and animation polish. Review all arenas and weather combinations, not just selected views.
2. **Performance:** reach 60 fps on High on measured target laptops; record cold starts, traversal,
   worst frames, resolutions and hardware. Dense vegetation and model/mesh uploads still cost heavily.
3. **Platforms:** native Windows/Linux graphics, input, audio, saves, firewalls and mixed-OS multiplayer;
   Intel macOS runtime checks. Exports/headless Linux CI are not graphical certification.
4. **Updater:** exported two-version tests for digest validation, interruption, offline use, restart,
   failure rollback and updates completing during play. Prereleases intentionally do not auto-install.
5. **Networking:** guest party-rule mirroring is fixed on unreleased main, not in v0.5.0 downloads.
   Real internet UPnP/routing and prolonged co-op still need testing. Movement/inventories trust clients;
   no anti-cheat or relay service. Stress the sporadic native loading crash mitigation before another release.
6. **World/content:** true redwood/birch/cactus/lichen models, missing ground flora, surface rivers,
   mine mini-boss guardians, boss warmup, bespoke humanoid attack animation and longer human playtesting.
7. **Save compatibility:** revisions remain versioned and automated save/continue passes, but exhaustive
   migrations with copies of historic saves and full exported-build testing are still pending.

Publish as a **prerelease** until these gates are addressed. Stable promotion must not be used merely
as a way to trigger the updater.
