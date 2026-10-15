# 0.4.0 preview: verification and limitations

This is an expanded playable prototype, **not completion of every requested feature**. Do not describe
it as a finished, hyperrealistic, universally 60-FPS game.

## Implemented in this iteration

- Mandatory first-person gameplay, ASCII-off defaults, finer optional coloured glyph rendering.
- Bottom-left triangular equipment layout, detailed relief/quest/underground minimap.
- Larger irregular revision-2 map, larger mountains, streamed slope fixes, distant terrain silhouettes.
- Five cave region types, timed geyser hazards, rare rich sanctuaries, abandoned mine routes.
- Kelp and loot-bearing wrecks, continuous village house meshes and pitched roofs.
- Complete rare-tree material definitions, tool-tier gating, rare-wood crafting uses.
- Hades opening-hit fix, unique final-quest rewards, party-wide Ryft unlock, floating-island travel/return,
  follow-up objectives and saved dimension-2 edits.
- Multiplayer input checks, smooth-mining replication, loading-time edit reconciliation, generation
  revision synchronization, network teardown fixes and isolated test harnesses.
- Adaptive resolution, bounded gem-light candidates, immutable map upload optimization.
- Three-platform export/release workflow, verified-digest update download logic and retained rollback packs.
- Save/continue audio-reference fix and loading-worker shutdown guard.

## Verified locally

Environment: macOS, Apple M4, Godot 4.7.2; visible captures use Metal Forward+.

| Check | Result |
| --- | --- |
| Unit suite | 93 tests, zero assertion failures; no script errors in latest completed run |
| Core gameplay integration | Pass: shrine, quest hand-in, mining/drops/pickup/fill, combat, death/respawn |
| Endgame integration | Pass: sealed Ryft before victory, Hades death, unique reward, follow-up quest, landing/return, save |
| App flow | Pass: intro → menu → new game → quit/save → continue; stale voice error fixed |
| Two-process gameplay co-op | Pass with 150 ms one-way simulated latency and 2% unreliable loss; combat and smooth excavation replicated; cube deletion rejected |
| LAN transport scenarios | All six pass: ordinary party, latency/loss, duplicate names, wrong runes, late join, host leaving |
| GPU smoke checks | Captured villages, mountains, Ryft, geyser caves, sanctuaries and mine entrance; normal 3D and full-colour ASCII tested |
| Cross-platform export | Windows x86_64, Linux x86_64 and universal macOS export successfully |
| Exported macOS startup | Headless menu startup smoke check passed |

Tests scan logs because engine exit status alone can miss script errors. The unit runner still emits
resource/ObjectDB-at-exit diagnostics. Those are not silently claimed to be fixed.

## Performance evidence, not a guarantee

At a 2940×1652 output on the M4, early High/no-ASCII village and mountain captures averaged about
50–60 FPS. More demanding traversal/cave/Ryft captures ranged roughly 34–48 FPS with pronounced
streaming spikes. These observations motivated a cap on gem-light candidates and adaptive resolution.
Subsequent Medium/full-colour ASCII village/sanctuary captures averaged approximately 59–60 FPS,
with worst sampled frames around 32–33 ms. These are different settings/scenes, not a controlled
before/after benchmark. Averages are not minimums, and headless tests are not FPS measurements.

The 60-FPS-minimum requirement is **not met or certified**. GPU timestamps report zero on this Metal
capture path; CPU/frame timing remains available. Use Low/Medium on slower machines and F3 to inspect.

## Still unfinished / release gates

1. **Art:** characters and bosses are procedural, not hyperrealistic production models. Several legacy
   towers, castles, roofs/props and building collision remain voxel-derived. Houses are improved, not
   a complete architectural asset overhaul. Cave visual richness and model animation need more polish.
2. **Performance:** dense vegetation, streaming, procedural mesh uploads and combat still spike. A
   controlled hardware/resolution test matrix, profiling and additional LOD work are required.
3. **Platforms:** native Windows/Linux launch, graphics, input, audio, save and multiplayer testing
   remains required. The macOS archive is ad-hoc signed, not notarized; Intel runtime testing is pending.
4. **Updater:** same-engine verified PCK updates and boot rollback are implemented, but two-version
   exported-build tests across all three OSes remain pending. Previews are deliberately not auto-installed.
5. **Multiplayer:** co-op trusts character inventories and movement. There is no competitive anti-cheat,
   host migration, global matchmaking, relay infrastructure or dedicated-server product. Real internet
   routing/UPnP and mixed-OS play need additional validation beyond loopback/LAN simulations.
6. **World/content:** the main quest chain exists, but story, balance, navigation, cave entrances and
   long-session progression need human playtesting. Ryft is a first endgame area, not a finished expansion.
7. **Save compatibility:** old worlds preserve generation revision 1; fresh worlds get the new terrain.
   Back up saves. Exhaustive migration coverage is not complete.

Publish as a **preview/prerelease** until these release gates are addressed. Stable promotion must not
be used merely to trigger clients' automatic update checks.
