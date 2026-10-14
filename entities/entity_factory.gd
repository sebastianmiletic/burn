class_name EntityFactory
extends RefCounted
## Creates any entity by kind name (used by GameWorld on server and clients).

const ENEMY_KINDS := ["skeleton", "archer", "ghoul", "troll", "imp", "shade"]
const BOSS_KINDS := ["warden", "mountain_king", "dragon", "cerberus", "hades"]


static func create(kind: String, _data := {}) -> Entity:
	match kind:
		"player":
			return Player.new()
		"npc":
			return Npc.new()
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
	if kind in ENEMY_KINDS:
		return _from_script("res://entities/enemies/enemy.gd", kind)
	if kind in BOSS_KINDS:
		return _from_script("res://entities/bosses/boss.gd", kind)
	return null


static func _from_script(path: String, kind: String) -> Entity:
	if not ResourceLoader.exists(path):
		push_warning("Entity kind %s needs %s" % [kind, path])
		return null
	var script: Script = load(path)
	return script.call("create", kind) as Entity
