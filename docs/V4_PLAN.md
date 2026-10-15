# Round 4: no blocks anywhere, professional bosses and battlegrounds, solid first person

The user's request (verbatim, 15 Oct evening):
"continue working and complete and fix the 3d models for the village houses, the rendering of the moutians for far
away, completing the bosses to actually look professional adn good, the only good looking and professional one is
the levithan, complete all of this, and also fix mining and 1st person seeing their own character glitches, and the
annoying thing that shows up when i have my pickaxe out, and completely fix 1st person, 3rd person, movement,
animations and more. also add much better rendering inside of caves, like i just see white for things that are far
away etc, and the bosses can all heal to max health straight away and stuff, add more thigns and stuff apart from
bosses for the players to do that are fun, not boring quests for the villagers, like going and talking to people and
completely fix the npcs to work proplerly, and MOST IMPORTANTLY COMPLETE THE BATTLEGROUNDS 3d models and everything
for all the bossfights and after this there must be no block 3d models or any blocks at all, for the village,
bosses, bossfights etc"

Current state (captures 15 Oct, High, ASCII off): every boss arena is still built from visible cubes (crypt depths,
mountain hall checkerboard floor, Dragon's Keep cube castle and floor, Tartarus/Throne red cube pillars, Drowned
Spire cube walls, Hagsfen box hut); village houses are plain boxes; the dragon is primitive red shapes, the Mountain
King a green blob, Hades a thin figure; caves (Broodmother lair, crystal sanctuaries) render nearly white; distant
mountains render as white jagged spikes; the first-person arms are two skin cylinders holding an oversized tool.
The Leviathan (models/creatures/leviathan_model.gd, SerpentChain, organic mesh builder) is the quality bar.

## Rules for everyone
* **No visible blocks.** Nothing may render as a cube from the voxel grid except natural smooth terrain. Buildings
  and arenas are modelled meshes (world/structures/architecture.gd pattern: `Location.props` turned into meshes
  by the director) with `Blocks.STRUCTURE` (invisible) for collision. Blueprints may no longer write CUBE-family
  blocks (cobble, brick, planks, logs, thatch, mossy cobble, runestone, gold block, iron bars, chest). Arena gates
  that open/close must be modelled (portcullis, rock slab, web curtain, ...) driven by the gate state.
* Read docs/ARCHITECTURE.md, docs/REALISM_CONTRACTS.md, docs/V3_CONTRACTS.md, docs/DEVELOPMENT.md (test process:
  isolated `--data-dir`, `tools/check_log.py`), docs/WORLD_V2.md, docs/BOSS_GUIDE.md.
* Test process (docs/DEVELOPMENT.md): import, unit tests, playtest, flow test, all with `--data-dir` under your
  worktree's `build/validation`, and `python3 tools/check_log.py <log>`. macOS has no `timeout`: use
  `perl -e 'alarm N; exec @ARGV' <cmd>`. GPU captures take over the screen: serialize with
  `until mkdir /tmp/burn_gpu.lock 2>/dev/null; do sleep 3; done; <run>; rmdir /tmp/burn_gpu.lock`, always pass
  `--no-update --data-dir=<your build dir>` and `--style=4 --quality=2`. `tests/gpu/game_capture.gd` has stops
  `arena_<location_id>` (stands 18 m in front of the boss spawn), village, vista, peaks, sanctuary, geyser, mine,
  ryft..., `--hold=<item id>`, `--action=attack`. Look at the PNGs yourself and iterate until it is genuinely
  professional; keep captures small (disk is limited: delete old capture folders, keep < 300 MB).
* Keep 60 fps at High on the user's Apple M4 (2940x1846 output): measure your feature's cost.
* Commit on your branch with messages ending `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Owners
| Area | Owner | Files |
|---|---|---|
| Player: first/third person, camera, viewmodel arms, movement, animation of the local player, mining feel, pickaxe target indicator | lead | entities/player/*, models/humanoid_model.gd, models/character/*, physics/*, world/voxel/*, world/game_world.gd, world/replicator.gd, core/*, network/* |
| Battlegrounds: modelled arenas for every boss (Warden/crypt depths, Mountain King/hall, Ashvane/Dragon's Keep, Broodmother lair, Bog Hag/Hagsfen, Leviathan/Drowned Spire, Cerberus/Tartarus, Hades/Gates + Throne, Ryft boss lairs) with props, lighting, hazards, modelled gates | battlegrounds | world/structures/lairs.gd, new world/structures/battlegrounds.gd (move the boss-location builders out of structures.gd into it; in structures.gd only delete/redirect those), new world/architecture/arenas/* |
| Villages and all other structures: houses, smithy, tavern, chapel, walls, docks, shrines, towers, ruins, mines, wrecks, portals, Ryft non-boss structures | villages | world/structures/architecture.gd, world/structures/structures.gd (non-boss parts), ruins_kit.gd, exploration_sites.gd, world/location_director.gd, new world/architecture/village/* |
| Beast bosses: Ashvane (dragon), Cerberus, Vexhira the Broodmother — models, animation, attacks, VFX | beasts | models/creatures/dragon_model.gd, cerberus_model.gd, spider/broodmother models, entities/bosses/dragon_boss.gd, cerberus_boss.gd, broodmother_boss.gd |
| Humanoid & other bosses: Warden, Mountain King, Hades, Old Mother Mire, Ryft bosses — models, attacks; boss base logic (healing/reset/scaling bugs) | bosses | entities/bosses/boss.gd and the other boss scripts, combat/*, new models/creatures/<boss>_model.gd |
| World rendering: cave lighting/fog/exposure (no white-out), distant mountains/horizon LOD, adaptive resolution quality, sky/fog | rendering | world/sky/*, rendering/*, world/distant_land.gd, world/materials/distant_land.gdshader, world/cave_biomes.gd (lights), world/environment_details.gd |
| Fun activities and NPCs | activities | quests/*, entities/npc/*, items/item_db.gd (additions), new world/activities/*, ui/quest_*, ui/dialog_box.gd, new ui/activity_* |
