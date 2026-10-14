extends Node
## Autoload "Events": game-wide signal bus. Systems announce what happened
## here; UI, audio and quests listen. Keeps gameplay code free of hard
## references to the HUD and vice versa.

# --- UI / feedback ---
signal notify(text: String, kind: String)                      ## toast: "info", "loot", "quest", "warn", "rank"
signal location_changed(title: String, subtitle: String, first_visit: bool)
signal interact_prompt(text: String)                           ## "" hides the prompt
signal damage_number(pos: Vector3, amount: int, crit: bool, kind: String)  ## kind: "hit", "heal", "player", "fire"
signal screen_shake(strength: float)
signal screen_flash(amount: float)
signal hit_stop(seconds: float)
signal slow_motion(seconds: float, scale: float)
signal dialog_open(npc: Node, title: String, lines: PackedStringArray, options: Array)  ## options: [{text, id}]
signal dialog_choice(npc: Node, option_id: String)
signal dialog_close
signal shop_open(kind: String)                                 ## "blacksmith", "merchant"
signal chat_message(from_name: String, text: String, channel: String)

# --- Player ---
signal player_health_changed(health: float, max_health: float)
signal player_died(cause: String)
signal player_respawned
signal xp_changed(xp: int, rank: int, into_rank: float)        ## into_rank 0..1
signal rank_up(rank: int, title: String)
signal inventory_changed
signal hotbar_selected(index: int)
signal ability_cooldown(ability: String, remaining: float, total: float)
signal mining_progress(fraction: float)                        ## <0 hides

# --- World / combat ---
signal boss_engaged(boss: Node, display_name: String)
signal boss_health_changed(boss: Node, health: float, max_health: float, phase: int)
signal boss_defeated(kind: String, display_name: String)
signal boss_disengaged(boss: Node)                             ## fight abandoned / reset
signal enemy_killed(kind: String, by_local_player: bool)
signal block_mined(block: int, by_local_player: bool)
signal item_picked_up(item_id: String, count: int)
signal location_discovered(location_id: StringName)
signal dimension_changed(dimension: int)
signal quest_updated(quest_id: String)
signal quest_completed(quest_id: String)
signal campaign_won
signal weather_changed(state: String)
signal lightning(position: Vector3)
