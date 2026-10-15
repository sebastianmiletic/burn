class_name LookInspector
extends Node
## Tells the HUD what the player is looking at once the crosshair has rested
## on it for a moment (Events.look_info): ores and rocks with what they drop
## and whether the held tool can work them, trees and their wood, creatures
## with their health, villagers, items, stations. Clears when the gaze moves.

const DWELL := 1.0
const RANGE := 28.0

var player: Player
var _key := ""
var _held := 0.0
var _shown := ""
var _tick := 0.0
var _info: Array = []


func _process(delta: float) -> void:
	if player == null or player.camera == null or player.dead:
		_clear()
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.1
		var found := _probe()
		var key: String = found[0]
		if key != _key:
			_key = key
			_held = 0.0
			_info = found
			if _shown != "" and key != _shown:
				_clear()
	if _key == "":
		return
	_held += delta
	if _held >= DWELL and _shown != _key:
		_shown = _key
		Events.look_info.emit(String(_info[1]), String(_info[2]), String(_info[3]))


func _clear() -> void:
	if _shown != "":
		_shown = ""
		Events.look_info.emit("", "", "")


## [key, title, subtitle, detail] for whatever is under the crosshair.
func _probe() -> Array:
	var ray: Array = player.camera.aim_ray()
	var origin: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	var w := player.world()
	if w == null:
		return [""]
	var vw := player.voxels()
	var ground_t := RANGE
	var hit := {}
	if vw != null:
		hit = vw.raycast(origin, dir, RANGE, true)
		if not hit.is_empty():
			ground_t = float(hit["distance"])
	# Creatures, people and things in front of the ground.
	var best: Entity = null
	var best_t := ground_t
	for e in w.entities_near(origin + dir * (RANGE * 0.5), RANGE * 0.5 + 2.0, player.dimension):
		if e == player or e.dead:
			continue
		var c := e.center()
		var t := (c - origin).dot(dir)
		if t < 0.3 or t > best_t:
			continue
		var miss := (origin + dir * t).distance_to(c)
		if miss < maxf(0.35, e.hit_radius * 1.1):
			best = e
			best_t = t
	if best != null:
		return _entity_info(best)
	if not hit.is_empty():
		return _block_info(int(hit["block"]), hit["pos"])
	return [""]


func _entity_info(e: Entity) -> Array:
	var name := e.display_name if e.display_name != "" else e.kind.capitalize().replace("_", " ")
	var key := "e%d" % e.net_id
	if e is ItemDrop:
		var d := e as ItemDrop
		return [key, ItemDB.display_name(d.item_id), "Item" + (" ×%d" % d.count if d.count > 1 else ""), "Walk over it to pick it up."]
	if e is Station:
		return [key, String((e as Station).station_kind).capitalize().replace("_", " "), "Crafting station", "Press E to craft here."]
	if e is Npc:
		return [key, name, String((e as Npc).role).capitalize(), "Press E to talk."]
	if e is Player:
		return [key, name, "Adventurer", "%d / %d health" % [int(e.health), int(e.max_health)]]
	var what := "Boss" if e.has_method("is_boss") and bool(e.call("is_boss")) else ("Creature" if e.team != Entity.Team.MONSTERS else "Hostile")
	return [key, name, what, "%d / %d health" % [int(ceilf(e.health)), int(e.max_health)]]


func _block_info(b: int, pos: Vector3i) -> Array:
	if b <= 0 or Blocks.family(b) == Blocks.Family.NONE:
		return [""]
	var key := "b%d" % b  # same material reads the same wherever you look
	var name := Blocks.name_of(b)
	if b == Blocks.STRUCTURE:
		var loc := player.world().location_at(Vector3(pos), player.dimension)
		return ["s%s" % (String(loc.id) if loc != null else "x"), loc.name if loc != null else "Old stonework", "Structure", "Built long ago; it can't be broken."]
	if Blocks.is_liquid(b):
		return [key, name, "Liquid", "Deadly to touch." if b == Blocks.LAVA else "Swim with Space."]
	var kind := "Rock"
	if Blocks.is_trunk(b):
		kind = "Tree"
	elif b in [Blocks.DIRT, Blocks.GRASS, Blocks.DRY_GRASS, Blocks.MUD, Blocks.CLAY, Blocks.SAND, Blocks.SNOW, Blocks.ASH, Blocks.SOUL_SAND, Blocks.GRAVEL]:
		kind = "Soil"
	elif Blocks.drop(b).ends_with("_ore") or b in [Blocks.COAL_ORE, Blocks.EMBER_ORE, Blocks.RUBY_ORE, Blocks.SAPPHIRE_ORE, Blocks.AMETHYST, Blocks.CRYSTAL]:
		kind = "Ore"
	var drop := Blocks.drop(b)
	var sub := kind + ((" · yields " + ItemDB.display_name(drop)) if drop != "" else "")
	var held := player.held_item()
	var detail := ""
	if not Blocks.is_breakable(b):
		detail = "Unbreakable."
	elif held != "" and ItemDB.info(held).get("category", "") == "tool":
		var t := ItemDB.mine_time(held, b)
		detail = ("Your %s can work this." % ItemDB.display_name(held)) if t >= 0.0 else ("Too hard for your %s: needs a tier %d tool." % [ItemDB.display_name(held), Blocks.tier(b)])
	else:
		detail = "Needs a tier %d pick-axe." % Blocks.tier(b) if Blocks.tier(b) > 0 else "Dig it with a pick-axe."
	return [key, name, sub, detail]
