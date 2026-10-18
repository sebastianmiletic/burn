class_name EntityFactory
extends RefCounted
## Creates any entity by kind name (used by GameWorld on server and clients).

const ENEMY_KINDS := ["skeleton", "archer", "ghoul", "troll", "imp", "shade"]
const BOSS_KINDS := ["warden", "mountain_king", "dragon", "cerberus", "hades", "leviathan", "broodmother", "bog_hag",
		"ryft_sentinel", "void_sovereign", "kraken", "charybdis"]
## Hostile creatures with their own behaviours (entities/enemies/beast.gd, stats in mob_db.gd).
const BEAST_KINDS := ["wolf", "dire_wolf", "frost_wolf", "hellhound", "bear", "giant_spider", "spiderling",
		"cave_bat", "cave_crawler", "rock_golem", "scorpion", "fire_elemental", "bog_lurker", "shark",
		"sea_serpent", "drowned"]
## Passive wildlife (entities/wildlife/*).
const WILDLIFE_KINDS := ["deer", "stag", "rabbit", "goat", "boar"]
const FLOCK_KINDS := ["bird_flock", "gull_flock", "crow_flock", "fish_school", "bat_swarm"]


static func create(kind: String, _data := {}) -> Entity:
	match kind:
		"player":
			return Player.new()
		"npc":
			return Npc.new()
		"calypso":
			return Calypso.new()
		"ogygia_raft":
			return OgygiaRaft.new()
		"drop":
			return ItemDrop.new()
		"chest":
			return Chest.new()
		"shrine":
			return Shrine.new()
		"portal":
			return Portal.new()
		"lore":
			return LoreStone.new()
		"decor":
			return LairDecor.new()
		"station":
			return Station.new()
		"well":
			return WellEntity.new()
	if kind.begins_with("act_"):
		# Activity props and markers (world/activities/*).
		return ActivityDirector.create_entity(kind)
	if kind in ENEMY_KINDS:
		return _from_script("res://entities/enemies/enemy.gd", kind)
	if kind in BEAST_KINDS:
		return _from_script("res://entities/enemies/beast.gd", kind)
	if kind in WILDLIFE_KINDS:
		return _from_script("res://entities/wildlife/wildlife.gd", kind)
	if kind in FLOCK_KINDS:
		return _from_script("res://entities/wildlife/flock.gd", kind)
	if kind in BOSS_KINDS:
		return _from_script("res://entities/bosses/boss.gd", kind)
	return null


static func _from_script(path: String, kind: String) -> Entity:
	if not ResourceLoader.exists(path):
		push_warning("Entity kind %s needs %s" % [kind, path])
		return null
	var script: Script = load(path)
	return script.call("create", kind) as Entity
