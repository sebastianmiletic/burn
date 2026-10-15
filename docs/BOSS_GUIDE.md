# Boss progression and encounter rules

Suggested progression, not a guarantee of difficulty. Bring healing supplies and upgrade equipment before each step.

| Encounter | Intended place in progression | Preparation |
| --- | --- | --- |
| Warden | First main boss, after the village quests | Iron equipment; learn telegraphs and dodge timing |
| Mountain King | Midgame mountain challenge | Hiking boots for the approach, upgraded armour and weapons |
| Ashvane (dragon) | Later overworld challenge | Stronger equipment, healing reserves, space to evade |
| Cerberus | Underworld challenge | Late-overworld equipment and fire protection |
| Hades | Main campaign finale | Endgame equipment, fire protection and careful arena positioning |
| Broodmother, Bog Hag, Leviathan | Optional regional bosses, not starter encounters | Return with upgraded equipment; learn their area attacks |
| Prism Sentinel, Void Sovereign | Post-game Ryft Island challenges | Mithril gear, many potions, space to dodge rings |

## Boss health and encounter rules

Implemented in `entities/bosses/boss.gd` and `entities/bosses/boss_ledger.gd`, proven by `tests/unit/test_boss_rules.gd`.

- **Nothing heals a boss in a fight.** Disengaging, leaving and re-entering the arena, a client joining, a phase change,
  replication, or the boss being despawned and spawned again (players walking far away) all keep its remaining health,
  its phase and its party scaling. The world's boss ledger remembers wounds per arena, and they are saved with the world.
- **Recovery needs a long genuine disengage:** 10 minutes of game time (`BossLedger.RECOVER_SECONDS`) in which nobody
  fought or hurt the boss. Only then does it return to full health, and it scales again for whoever pulls it next.
  There is no regeneration before that.
- **Party scaling happens once per encounter**: at the pull, plus players who arrive within the first 15 seconds of a
  fresh pull. Late scaling keeps the health *fraction*, so the bar never moves up.
- **Attacks from outside the arena are evaded**: a player beyond the arena (or far above/below it) cannot pull or chip
  the boss. Burns already on the boss keep ticking but cannot pull it, and disengaging clears them.
- **Phases are never skipped**: a blow that crosses two thresholds runs both transitions in order.
- A boss that falls out of its arena, wanders far off, or is stuck on geometry for several seconds returns to its spawn.
  It does not walk beyond the arena edge while chasing (ranged attacks still reach).
- Boss snapshots carry the scaled maximum health, so the boss bar matches on every machine; players who join mid-fight
  see the bar and hear the boss music.

Creative inspection is a solo testing aid, not evidence that a fight is balanced for ordinary play.

## Ryft bosses

- **The Prism Sentinel** guards the Broken Observatory (Ryft isle 1): crystal lances, shard novas, a sweeping prism beam.
- **The Void Sovereign** waits on the Crown of the Ryft (isle 2): void lashes, imploding rifts, starfall, eclipse rings.

Difficulty labels are design guidance. Human playtesting across equipment tiers remains necessary.
