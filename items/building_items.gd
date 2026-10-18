class_name BuildingItems
extends RefCounted
## Items and recipes of player building (one item per piece and material,
## see BuildPieces), storage, and what village wells bring up. Registered
## into ItemDB from its _static_init. Also the model builder for these items
## (ItemDB "model_script"): pieces are shown as miniatures of their real mesh.

const SCRIPT := "res://items/building_items.gd"

## Village well finds (WellEntity's table names these).
const WELL_ITEMS := {
	"well_water": {"name": "Bucket of Well Water", "category": "consumable", "glyph": "u", "color": Color(0.45, 0.6, 0.75), "heal": 6.0, "stack": 10, "value": 1, "food": true,
		"desc": "Cold, clear and tasting faintly of stone. Restores a little health."},
	"pebbles": {"name": "Well Pebbles", "category": "material", "glyph": ".", "color": Color(0.6, 0.58, 0.55), "stack": 99, "value": 0,
		"desc": "Smooth little stones from the bottom of a well. Worth nothing at all."},
	"old_boot": {"name": "Old Boot", "category": "treasure", "glyph": "L", "color": Color(0.35, 0.26, 0.18), "stack": 10, "value": 1,
		"desc": "Waterlogged, laceless and alone. Somebody hopped home."},
	"rusty_coin": {"name": "Rusty Coin", "category": "treasure", "glyph": "o", "color": Color(0.55, 0.4, 0.28), "stack": 99, "value": 1,
		"desc": "A wish someone made long ago. The face on it is gone."},
	"silver_ring": {"name": "Tarnished Silver Ring", "category": "treasure", "glyph": "o", "color": Color(0.82, 0.84, 0.88), "stack": 10, "value": 90, "rarity": 2,
		"desc": "Dropped down a well by a lover or a thief. A jeweller will pay well for it."},
}

const GROUP_NAMES := {"build_frame": "Foundations, floors & frame", "build_walls": "Walls", "build_openings": "Doors & windows",
	"build_roofs": "Roofs", "build_furniture": "Furniture & light", "build_storage": "Storage"}
const GROUP_ORDER := ["build_frame", "build_walls", "build_openings", "build_roofs", "build_furniture", "build_storage"]


static func register(items: Dictionary, recipes: Dictionary) -> void:
	for id: String in WELL_ITEMS:
		var w: Dictionary = WELL_ITEMS[id].duplicate()
		w["model_script"] = SCRIPT
		items[id] = w
	var order := 0
	for pair: Array in BuildPieces.all_pairs():
		var kind: String = pair[0]
		var mat: String = pair[1]
		var id := BuildPieces.item_id(kind, mat)
		var p: Dictionary = BuildPieces.PIECES[kind]
		var use := BuildPieces.use_of(kind)
		var desc := _desc(kind, mat)
		items[id] = {"name": BuildPieces.display_name(kind, mat), "category": "building", "glyph": "#",
			"color": _color(mat), "stack": 20 if not use == "container" else 5, "value": 2,
			"rarity": 1 if mat in ["ironwood", "reinforced"] or kind == "chest_iron" else 0,
			"build_piece": [kind, mat], "model_script": SCRIPT, "desc": desc}
		recipes[id] = {"inputs": BuildPieces.cost(kind, mat), "station": String(p.get("station", "workbench")),
			"group": String(p["group"]), "order": order, "time": 0.8}
		order += 1


static func _color(mat: String) -> Color:
	match mat:
		"stone", "cobble", "slate":
			return Color(0.6, 0.58, 0.55)
		"reinforced":
			return Color(0.55, 0.56, 0.6)
		"brick":
			return Color(0.65, 0.35, 0.28)
		"plaster":
			return Color(0.88, 0.82, 0.7)
		"thatch":
			return Color(0.8, 0.68, 0.4)
	return Color(0.6, 0.44, 0.3)


static func _desc(kind: String, mat: String) -> String:
	var hp := int(BuildPieces.max_hp(kind, mat))
	var s := BuildPieces.size_of(kind)
	var line := "%d x %d x %d m, %d durability." % [s.x, s.y, s.z, hp]
	match BuildPieces.use_of(kind):
		"door":
			line += " E opens and closes it."
		"bed":
			line += " Rest in it (E) to wake here when you fall."
		"container":
			line += " Holds %d stacks; E opens it. Breaking it spills what is inside." % BuildPieces.container_slots(kind)
	return "Hold it and right-click to build; R turns it. " + line


static func is_building(id: String) -> bool:
	return ItemDB.info(id).has("build_piece")


# --- Models --------------------------------------------------------------------------------

## ItemDB model_script hook: a miniature of the piece, or a well find.
static func build(body: Node3D, id: String) -> bool:
	var info := ItemDB.info(id)
	if info.has("build_piece"):
		var bp: Array = info["build_piece"]
		var model := PieceMesh.get_model(bp[0], bp[1])
		var holder := Node3D.new()
		var size := Vector3(BuildPieces.size_of(bp[0]))
		var k := 0.34 / maxf(size.x, maxf(size.y, size.z))
		holder.scale = Vector3.ONE * k
		holder.position = Vector3(-size.x * 0.5, 0.0, -size.z * 0.5) * k
		var mi := MeshInstance3D.new()
		mi.mesh = model["mesh"]
		holder.add_child(mi)
		for leaf: Dictionary in model["leaves"]:
			var lm := MeshInstance3D.new()
			lm.mesh = leaf["mesh"]
			lm.position = leaf["pivot"]
			holder.add_child(lm)
		body.add_child(holder)
		return true
	match id:
		"well_water":
			ModelKit.part(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.075, 0.0), Vector2(0.09, 0.16), Vector2(0.083, 0.16), Vector2(0.07, 0.01)])), ItemMats.wood(Color(0.55, 0.4, 0.26)))
			ModelKit.part(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.084, 0.0)])), ItemMats.liquid(Color(0.4, 0.6, 0.75)), Vector3(0, 0.14, 0))
			for y: float in [0.03, 0.13]:
				ModelKit.part(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.081 + y * 0.09, 0.0), Vector2(0.083 + y * 0.09, 0.012)])), ItemMats.metal("iron"), Vector3(0, y, 0))
		"pebbles":
			for i in 5:
				var a := TAU * i / 5.0
				ModelKit.part(body, ItemMesh.rock(0.025 + i * 0.003, 31 + i, 0.15, 1, Vector3(1.2, 0.7, 1.0), true), ItemMats.stone(Color(0.62, 0.6, 0.56)), Vector3(cos(a) * 0.04, 0.015, sin(a) * 0.04))
		"old_boot":
			ModelKit.part(body, ItemMesh.bevel_box(Vector3(0.08, 0.16, 0.08), 0.02), ItemMats.leather(Color(0.3, 0.22, 0.15)), Vector3(0, 0.1, -0.03))
			ModelKit.part(body, ItemMesh.bevel_box(Vector3(0.085, 0.06, 0.2), 0.025), ItemMats.leather(Color(0.28, 0.2, 0.13)), Vector3(0, 0.03, 0.02))
		"rusty_coin":
			ModelKit.part(body, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.05, 0.0), Vector2(0.05, 0.008), Vector2(0.0, 0.008)]), 20), ItemMats.metal("rust"), Vector3(0, 0.0, 0), Vector3(70, 0, 0))
		"silver_ring":
			var ring := ItemMesh.lathe(PackedVector2Array([Vector2(0.045, -0.006), Vector2(0.052, 0.0), Vector2(0.045, 0.006), Vector2(0.04, 0.0), Vector2(0.045, -0.006)]), 24)
			ModelKit.part(body, ring, ItemMats.metal("silver"), Vector3(0, 0.05, 0), Vector3(80, 0, 0))
			ModelKit.part(body, ItemMesh.gem_cut(0.012), ItemMats.gem(Color(0.3, 0.5, 0.9)), Vector3(0, 0.1, 0.0))
		_:
			return false
	return true
