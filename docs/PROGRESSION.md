# Progression ladder

What the player does from the first minute to the endgame, and what each step unlocks. The data lives in
`quests/quest_db.gd`: `FIRST_STEPS` (the guided start), `MAIN` (the story chain), `OPTIONAL` (regional
boss contracts) and `PATH` (the ladder shown on the journal's **Path** tab). Tests: `tests/unit/test_progression.gd`,
and the early steps are walked in `tests/game/playtest.gd`.

## Tool tiers (pickaxe `mine_tier`, items/item_db.gd)

| Pick | Mines | Ore depth (y) |
| --- | --- | --- |
| Stone (starting kit, tier 2) | stone, coal, copper, tin, iron | coal < 60, copper/tin < 40, iron < 20 |
| Bronze / iron (3) | silver, gold, ruby, sapphire, amethyst, frost crystal, ironwood | silver < -10, gold < -25, gems < -40 |
| Steel (4) | mithril, ember crystal, emberwood | < -60 |
| Mithril (5) | adamantite, obsidian, ryftwood | < -95 / < -100 |
| Adamantite (6) | hellstone (underworld only) | |
| Infernal (7) | everything | |

Mithril gear also needs silver ingots, adamantite needs gold ingots, infernal needs hellstone + adamantite + ember crystal.
The village smith in every village counts as workbench + furnace + anvil.

## The ladder

Each row: goal, where, what you need, what you get / unlock.

| # | Step (quest id) | Where | Needs | Gives / unlocks |
| --- | --- | --- | --- | --- |
| 1 | Gather wood (`fs_timber`) | Around the Emberfall Shrine (spawn) | Starting pick-axe fells trees | 4+ wood |
| 2 | Workbench (`fs_workbench`) | Anywhere | Planks by hand (Tab/I), workbench, place it | Workbench crafting |
| 3 | Stone tools (`fs_stone_tools`) | Bare rock | 6 stone, 4 sticks, stone axe/spear/warhammer | Stone tier, torches |
| 4 | Make camp (`fs_campfire`) | Anywhere | Campfire (5 stone, 2 wood, 2 sticks), place it | Light at night, roast meat/fish |
| 5 | Rekindle the shrine (`kindling`, parallel from minute one) | Emberfall Shrine, then Elder Maren | Interact with shrine | Respawn point, potions; guide ends by talking to Maren (`fs_village`) |
| 6 | Iron in the Deep (`iron_in_the_deep`, Brannoc) | Dig below the plains / Old Ember Mine | 5 iron ore, 3 coal | Iron sword; copper/iron tier |
| 7 | Tempered in Iron (`tempered`, Brannoc) | Furnace + anvil or the smithy | 6 iron ingots, 1 iron armour piece | Iron gear |
| 8 | The Silent Crypt (`silent_crypt`, Maren) — **Warden** | Blackmarsh, west | Iron gear recommended | Warden's Sigil (seal 1); optional hunts open |
| 9 | Steel and Frost (`steel_and_frost`, Brannoc) | Furnace + anvil | 4 steel ingots, Ironspike Hiking Boots | Steel tier, steep paths |
| 10 | Hall of the Mountain King (`mountain_king`) — **Mountain King** | Beyond Frosthold | Steel recommended | Frost Crown (seal 2) |
| 11 | Ashvane (`ashvane`) — **Ashvane** | Dragon's Keep, Cinder Wastes | Steel or mithril, fire resist (ruby/ember sockets) | Dragonheart (seal 3) |
| 12 | Into the Deep (`into_the_deep`) | Dig under the Cinder Crater (~y -112) | All three seals | Gates of Hades portal -> underworld |
| 13 | Hound of the Underworld (`hound`) — **Cerberus** | Tartarus | Mithril/adamantite, fire resist | Cerberus Fang, hellstone (infernal tier) |
| 14 | The Throne of Hades (`throne`) — **Hades** | Throne of Hades | Adamantite or infernal | Gatebreaker, mithril axe; Ryft gateway opens |
| 15 | Beyond the Broken Sky (`ryft`) | Ryft gateway in Emberfall | Mithril axe | Ryftwood, phoenix elixirs |
| 16 | The Prism Sentinel (`prism_sentinel`) | Broken Observatory | Infernal or starfall | Prism Heart, starmetal |
| 17 | The Void Sovereign (`void_sovereign`) | Crown of the Ryft | Infernal or starfall | Void Crown, Storm Horn |

## Optional hunts (OPTIONAL)

Offered by the giver once the requirement is done; handed back to the giver. Ocean bosses stay hidden until their
boss kind exists in `EntityFactory.BOSS_KINDS` (they come from the oceans branch), so nothing breaks before then.

| Quest | Boss | Giver | Opens after | Gear |
| --- | --- | --- | --- | --- |
| `opt_broodmother` | Broodmother (Weeping Hollow) | Thornwick chief | Warden | Steel |
| `opt_bog_hag` | Old Mother Mire (Hagsfen) | Mirewatch chief | Warden | Steel |
| `opt_leviathan` | Leviathan (Drowned Spire) | Elder Maren | Mountain King | Steel or mithril |
| `opt_kraken` | `kraken`, deep trench | Kaldvik chief | Ashvane | Mithril |
| `opt_charybdis` | `charybdis` | Kaldvik chief | Kraken | Mithril or adamantite |

## Rules the code keeps

- Objective types: `gather` (items picked up), `craft` (items made), `place` (station set down), `talk` (giver key),
  plus the older `reach`, `interact`, `boss`, `kill`, `mine`, `collect`/`have` (inventory), `dimension`, `discover`.
  Keys may list alternatives (`axe_stone|spear_stone`).
- Bosses never respawn, so `boss`/`reach` objectives also count bosses already slain and places already found
  (`QuestLog.known_bosses/known_places`, re-applied on load).
- Old saves: quests inserted before the player's furthest main quest count as done (no rewards), and the guide is
  skipped once Kindling is done. Saved progress arrays are padded if a quest's objectives changed.
- No quest or hint mentions breathing or drowning; `test_no_breathing_hints` guards it.
