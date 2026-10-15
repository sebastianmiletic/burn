class_name Location
extends RefCounted
## A named place in the world: its footprint, the blocks it stamps into the
## terrain, and what it spawns (NPCs, enemies, bosses, chests, shrines, portals).

enum Kind { VILLAGE, CASTLE, HALL, GATE, CRYPT, SHRINE, TOWER, RUIN, HELL_SPAWN, TARTARUS, THRONE }

const KIND_LABELS := ["Village", "Castle", "Hall", "Gate", "Crypt", "Shrine", "Watchtower", "Ruins",
		"Portal", "Fortress", "Palace"]

var id: StringName
var name := ""
var kind := Kind.RUIN
var center := Vector3.ZERO
## Horizontal radius within which the HUD says "you are here".
var radius := 20.0
## Vertical extent for underground / interior places (0 = any height).
var half_height := 0.0
var ground_y := 0
var pad_radius := 0.0
var pad_falloff := 8.0
var blueprints: Array[Blueprint] = []
## Each spawn: {"type": String, "pos": Vector3, ...extra}
var spawns: Array[Dictionary] = []
## Visual props Architecture.build() turns into meshes: [{type, transform, ...}].
var props: Array = []
var dimension := 0
## Bosses and key places show on the map once discovered; ruins only when visited.
var major := false


func _init(loc_id: StringName, loc_name: String, loc_kind: Kind, at: Vector3) -> void:
	id = loc_id
	name = loc_name
	kind = loc_kind
	center = at
	ground_y = int(at.y)


func contains(p: Vector3) -> bool:
	var d := Vector2(p.x - center.x, p.z - center.z).length()
	if d > radius:
		return false
	if half_height > 0.0 and absf(p.y - center.y) > half_height:
		return false
	return true


func add_spawn(type: String, pos: Vector3, extra := {}) -> void:
	var s := {"type": type, "pos": pos}
	s.merge(extra)
	spawns.append(s)


func spawns_of(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in spawns:
		if s["type"] == type:
			out.append(s)
	return out


func kind_label() -> String:
	return KIND_LABELS[kind]
