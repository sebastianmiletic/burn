class_name MobDB
extends RefCounted
## Stats for the creatures added alongside the original six monsters. Same
## schema as Enemy.STATS (read through Enemy.stats_for), plus:
##   "ai": "pack" (alerts its pack), "swim" (lives in water), "ambush" (lies
##         hidden until you are close), "swoop" (erratic flyer), "" (default)
##   "sound": the growl it makes when it notices you
## Loot item ids that ItemDB does not (yet) define are skipped when dropped.

const ATTACK := 1
const SLAM := 5
const THROW := 6
const DRAIN := 7

const STATS := {
	"wolf": {"name": "Wolf", "health": 40.0, "damage": 8.0, "speed": 3.0, "chase": 7.0, "aggro": 20.0, "range": 1.8,
		"lunge": 7.0, "windup": 0.35, "cooldown": 1.15, "xp": 20, "radius": 0.5, "height": 0.9, "attack": ATTACK,
		"ai": "pack", "flee_at": 0.15, "sound": "wolf_growl",
		"loot": [["raw_meat", 0.7, 1, 2], ["wolf_pelt", 0.45, 1, 1], ["bone", 0.4, 1, 2]]},
	"dire_wolf": {"name": "Dire Wolf", "health": 90.0, "damage": 14.0, "speed": 3.2, "chase": 7.6, "aggro": 24.0, "range": 2.3,
		"lunge": 8.0, "windup": 0.4, "cooldown": 1.3, "xp": 45, "radius": 0.75, "height": 1.35, "attack": ATTACK,
		"ai": "pack", "stagger_fraction": 0.25, "sound": "wolf_howl",
		"loot": [["raw_meat", 0.9, 1, 3], ["wolf_pelt", 0.7, 1, 2], ["bone", 0.5, 1, 3]]},
	"frost_wolf": {"name": "Frost Wolf", "health": 65.0, "damage": 12.0, "speed": 3.2, "chase": 7.3, "aggro": 22.0, "range": 2.0,
		"lunge": 7.5, "windup": 0.38, "cooldown": 1.2, "xp": 38, "radius": 0.6, "height": 1.1, "attack": ATTACK,
		"ai": "pack", "sound": "wolf_growl",
		"loot": [["raw_meat", 0.8, 1, 2], ["frost_pelt", 0.5, 1, 1], ["frost_shard", 0.25, 1, 1]]},
	"hellhound": {"name": "Hellhound", "health": 95.0, "damage": 16.0, "speed": 3.4, "chase": 7.8, "aggro": 26.0, "range": 2.2,
		"lunge": 8.0, "windup": 0.36, "cooldown": 1.2, "xp": 55, "radius": 0.7, "height": 1.3, "attack": ATTACK,
		"ai": "pack", "sound": "wolf_growl",
		"loot": [["hellstone", 0.35, 1, 2], ["ember_crystal", 0.3, 1, 2], ["bone", 0.4, 1, 2]]},
	"bear": {"name": "Bear", "health": 220.0, "damage": 28.0, "speed": 2.4, "chase": 5.6, "aggro": 13.0, "range": 2.6,
		"windup": 0.95, "cooldown": 2.4, "xp": 80, "radius": 1.0, "height": 1.6, "attack": SLAM, "heavy": true,
		"slam_radius": 2.8, "stagger_fraction": 0.3, "sound": "bear_roar",
		"loot": [["raw_meat", 1.0, 2, 4], ["bear_pelt", 0.6, 1, 1], ["bone", 0.5, 1, 3]]},
	"giant_spider": {"name": "Giant Spider", "health": 60.0, "damage": 11.0, "speed": 3.4, "chase": 6.6, "aggro": 18.0, "range": 1.9,
		"lunge": 7.0, "windup": 0.35, "cooldown": 1.25, "xp": 32, "radius": 0.9, "height": 1.0, "attack": ATTACK, "sound": "spider_hiss",
		"loot": [["spider_silk", 0.7, 1, 3], ["venom_sac", 0.3, 1, 1]]},
	"spiderling": {"name": "Spiderling", "health": 16.0, "damage": 5.0, "speed": 4.0, "chase": 7.0, "aggro": 24.0, "range": 1.2,
		"lunge": 4.0, "windup": 0.25, "cooldown": 0.9, "xp": 6, "radius": 0.35, "height": 0.45, "attack": ATTACK, "sound": "spider_hiss",
		"loot": [["spider_silk", 0.25, 1, 1]]},
	"cave_bat": {"name": "Cave Bat", "health": 14.0, "damage": 4.0, "speed": 4.0, "chase": 6.5, "aggro": 16.0, "range": 1.3,
		"windup": 0.25, "cooldown": 1.0, "xp": 6, "radius": 0.35, "height": 0.5, "attack": ATTACK, "fly": true, "hover": 2.0,
		"drain": 0.3, "ai": "swoop", "sound": "bat_screech",
		"loot": [["bat_wing", 0.4, 1, 1]]},
	"cave_crawler": {"name": "Cave Crawler", "health": 120.0, "damage": 18.0, "speed": 2.6, "chase": 4.8, "aggro": 16.0, "range": 2.4,
		"lunge": 6.0, "windup": 0.45, "cooldown": 1.6, "xp": 60, "radius": 0.7, "height": 0.8, "attack": ATTACK, "sound": "spider_hiss",
		"loot": [["chitin", 0.6, 1, 3], ["venom_sac", 0.4, 1, 1], ["silver_ore", 0.2, 1, 2]]},
	"rock_golem": {"name": "Rock Golem", "health": 320.0, "damage": 32.0, "speed": 1.4, "chase": 2.5, "aggro": 14.0, "range": 3.2,
		"windup": 1.2, "cooldown": 2.8, "xp": 120, "radius": 1.1, "height": 2.8, "attack": SLAM, "heavy": true,
		"slam_radius": 3.4, "stagger_fraction": 0.45, "sound": "stomp",
		"loot": [["iron_ore", 0.8, 2, 5], ["gold_ore", 0.4, 1, 3], ["mithril_ore", 0.25, 1, 2], ["amethyst", 0.3, 1, 2], ["ruby", 0.15, 1, 1]]},
	"scorpion": {"name": "Giant Scorpion", "health": 90.0, "damage": 15.0, "speed": 2.6, "chase": 5.0, "aggro": 16.0, "range": 2.4,
		"windup": 0.5, "cooldown": 1.4, "xp": 40, "radius": 0.9, "height": 0.9, "attack": ATTACK, "sound": "spider_hiss",
		"loot": [["chitin", 0.6, 1, 2], ["venom_sac", 0.45, 1, 1]]},
	"fire_elemental": {"name": "Fire Elemental", "health": 80.0, "damage": 16.0, "speed": 2.4, "chase": 3.8, "aggro": 24.0, "range": 16.0,
		"prefer": 9.0, "windup": 0.7, "cooldown": 2.4, "xp": 50, "radius": 0.6, "height": 2.2, "attack": THROW,
		"projectile": "fireball", "projectile_speed": 14.0, "fly": true, "hover": 0.5, "sound": "fireball_cast",
		"loot": [["ember_crystal", 0.6, 1, 3], ["coal", 0.6, 1, 3]]},
	"bog_lurker": {"name": "Bog Lurker", "health": 110.0, "damage": 20.0, "speed": 1.8, "chase": 6.5, "aggro": 10.0, "range": 2.2,
		"lunge": 6.0, "windup": 0.4, "cooldown": 1.6, "xp": 45, "radius": 0.8, "height": 0.8, "attack": ATTACK, "ai": "ambush", "sound": "growl",
		"loot": [["raw_meat", 0.7, 1, 2], ["lurker_hide", 0.5, 1, 1]]},
	"shark": {"name": "Grey Shark", "health": 70.0, "damage": 17.0, "speed": 3.0, "chase": 7.5, "aggro": 18.0, "range": 1.8,
		"windup": 0.3, "cooldown": 1.3, "xp": 35, "radius": 0.8, "height": 1.0, "attack": ATTACK, "ai": "swim", "fly": true, "sound": "splash",
		"loot": [["raw_fish", 0.8, 1, 3], ["shark_tooth", 0.5, 1, 2]]},
	"sea_serpent": {"name": "Sea Serpent", "health": 160.0, "damage": 22.0, "speed": 3.0, "chase": 6.5, "aggro": 28.0, "range": 16.0,
		"prefer": 10.0, "windup": 0.8, "cooldown": 2.6, "xp": 90, "radius": 1.2, "height": 2.0, "attack": THROW,
		"projectile": "bile", "projectile_speed": 14.0, "ai": "swim", "fly": true, "sound": "roar",
		"loot": [["raw_fish", 0.8, 1, 3], ["leviathan_scale", 0.2, 1, 1], ["pearl", 0.2, 1, 1]]},
	"drowned": {"name": "Drowned Thrall", "health": 50.0, "damage": 10.0, "speed": 2.4, "chase": 4.0, "aggro": 18.0, "range": 2.0,
		"windup": 0.45, "cooldown": 1.3, "xp": 22, "radius": 0.45, "height": 1.85, "attack": ATTACK, "sound": "growl",
		"loot": [["bone", 0.4, 1, 2], ["pearl", 0.05, 1, 1], ["potion_health", 0.08, 1, 1]]},
}
