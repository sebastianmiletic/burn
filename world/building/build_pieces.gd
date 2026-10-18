class_name BuildPieces
extends RefCounted
## The player building catalogue: piece kinds, building materials, their item
## ids, costs and hit points, and the grid maths every peer shares.
##
## Pieces live on the 1 m voxel grid. A piece has a size in cells (x across,
## y up, z depth) in its own frame and a rotation 0..3 (quarter turns about
## +y); `anchor` is the minimum corner cell of its rotated footprint. In the
## piece frame +z is the front (it faces the player who placed it), stairs and
## roofs rise from the front (z = depth) towards the back (z = 0).
##
## Collision is the existing invisible Blocks.STRUCTURE voxel, written into the
## piece's solid cells (only cells that were open air), exactly like modelled
## village architecture. Item ids: "bp_<kind>_<material>" for structural pieces,
## "bp_<kind>" for furniture and storage.

const L = ArchMaterials.L

## Building materials. unit: what one cost unit takes; iron: extra iron ingot
## per two units (banded wood, reinforced stone).
const MATS := {
	"wood": {"name": "Log", "hp": 140.0, "unit": {"wood": 1}, "family": "wood"},
	"plank": {"name": "Plank", "hp": 160.0, "unit": {"planks": 2}, "family": "wood"},
	"ironwood": {"name": "Iron-banded", "hp": 380.0, "unit": {"planks": 2}, "iron": true, "family": "wood"},
	"plaster": {"name": "Timber-framed", "hp": 150.0, "unit": {"planks": 1, "clay": 1}, "family": "wood"},
	"stone": {"name": "Fieldstone", "hp": 320.0, "unit": {"stone": 2}, "family": "stone"},
	"cobble": {"name": "Cobblestone", "hp": 300.0, "unit": {"cobble": 1}, "family": "stone"},
	"brick": {"name": "Brick", "hp": 340.0, "unit": {"brick": 2}, "family": "stone"},
	"reinforced": {"name": "Reinforced Stone", "hp": 700.0, "unit": {"cobble": 2}, "iron": true, "family": "stone"},
	"thatch": {"name": "Thatch", "hp": 80.0, "unit": {"thatch": 2}, "family": "wood"},
	"shingle": {"name": "Shingle", "hp": 150.0, "unit": {"planks": 2}, "family": "wood"},
	"slate": {"name": "Slate", "hp": 260.0, "unit": {"slate": 1, "stone": 1}, "family": "stone"},
}

const WALLS := ["wood", "plank", "ironwood", "plaster", "stone", "cobble", "brick", "reinforced"]
const FLOORS := ["plank", "wood", "stone", "cobble", "brick"]
const FOUNDATIONS := ["stone", "cobble", "brick", "reinforced", "wood"]
const ROOFS := ["thatch", "shingle", "slate"]
const POSTS := ["wood", "plank", "stone", "cobble", "brick", "reinforced"]
const TIMBERS := ["wood", "plank", "ironwood"]
const HATCHES := ["plank", "ironwood"]

## size: cells (x, y, z). solid: "all", "none", "back" (z row 0) or "top" (y row
## h-1). open_solid: solid rule while a door / gate / hatch stands open.
## units: material cost units; extra: other inputs. group: crafting book group.
## use: "door" | "bed" | "container"; mount: wall-mounted (faces out of the wall).
const PIECES := {
	"foundation": {"name": "Foundation", "size": Vector3i(2, 1, 2), "mats": FOUNDATIONS, "units": 4, "solid": "all", "hp": 1.5, "group": "build_frame", "ground": true},
	"floor": {"name": "Floor", "size": Vector3i(2, 1, 2), "mats": FLOORS, "units": 2, "solid": "all", "hp": 0.8, "group": "build_frame"},
	"wall": {"name": "Wall", "size": Vector3i(2, 3, 1), "mats": WALLS, "units": 4, "solid": "all", "hp": 1.0, "group": "build_walls"},
	"wall_half": {"name": "Narrow Wall", "size": Vector3i(1, 3, 1), "mats": WALLS, "units": 2, "solid": "all", "hp": 0.6, "group": "build_walls"},
	"wall_low": {"name": "Half Wall", "size": Vector3i(2, 1, 1), "mats": WALLS, "units": 2, "solid": "all", "hp": 0.6, "group": "build_walls"},
	"wall_gable": {"name": "Gable", "size": Vector3i(2, 1, 1), "mats": WALLS, "units": 2, "solid": "all", "hp": 0.6, "group": "build_walls"},
	"window": {"name": "Window", "size": Vector3i(2, 3, 1), "mats": WALLS, "units": 3, "extra": {"glass_vial": 1}, "solid": "all", "hp": 0.8, "group": "build_openings"},
	"window_arch": {"name": "Arched Window", "size": Vector3i(2, 3, 1), "mats": WALLS, "units": 3, "extra": {"glass_vial": 1}, "solid": "all", "hp": 0.8, "group": "build_openings"},
	"window_shutter": {"name": "Shuttered Window", "size": Vector3i(2, 3, 1), "mats": WALLS, "units": 3, "extra": {"planks": 1}, "solid": "all", "hp": 0.8, "group": "build_openings"},
	"window_slit": {"name": "Arrow Slit", "size": Vector3i(2, 3, 1), "mats": WALLS, "units": 4, "solid": "all", "hp": 1.0, "group": "build_openings"},
	"doorway": {"name": "Doorway", "size": Vector3i(2, 3, 1), "mats": WALLS, "units": 3, "solid": "top", "hp": 0.8, "group": "build_openings"},
	"door": {"name": "Door", "size": Vector3i(2, 3, 1), "mats": WALLS, "units": 3, "extra": {"planks": 4}, "solid": "all", "open_solid": "top", "hp": 1.0, "group": "build_openings", "use": "door"},
	"trapdoor": {"name": "Trapdoor", "size": Vector3i(1, 1, 1), "mats": HATCHES, "units": 2, "solid": "all", "open_solid": "none", "hp": 0.6, "group": "build_openings", "use": "door"},
	"pillar": {"name": "Pillar", "size": Vector3i(1, 3, 1), "mats": POSTS, "units": 2, "solid": "all", "hp": 1.0, "group": "build_frame"},
	"beam": {"name": "Beam", "size": Vector3i(2, 1, 1), "mats": TIMBERS, "units": 1, "solid": "none", "hp": 0.6, "group": "build_frame"},
	"stairs": {"name": "Stairs", "size": Vector3i(2, 1, 2), "mats": FLOORS, "units": 3, "solid": "back", "hp": 0.8, "group": "build_frame"},
	"fence": {"name": "Fence", "size": Vector3i(2, 1, 1), "mats": TIMBERS, "units": 1, "solid": "all", "hp": 0.5, "group": "build_frame"},
	"gate": {"name": "Gate", "size": Vector3i(2, 1, 1), "mats": TIMBERS, "units": 1, "extra": {"stick": 2}, "solid": "all", "open_solid": "none", "hp": 0.6, "group": "build_openings", "use": "door"},
	"roof": {"name": "Roof", "size": Vector3i(2, 1, 1), "mats": ROOFS, "units": 2, "solid": "all", "hp": 0.6, "group": "build_roofs"},
	"roof_low": {"name": "Low Roof", "size": Vector3i(2, 1, 2), "mats": ROOFS, "units": 3, "solid": "back", "hp": 0.7, "group": "build_roofs"},
	"roof_peak": {"name": "Roof Ridge", "size": Vector3i(2, 1, 2), "mats": ROOFS, "units": 4, "solid": "all", "hp": 0.8, "group": "build_roofs"},
	"roof_corner": {"name": "Roof Corner", "size": Vector3i(1, 1, 1), "mats": ROOFS, "units": 1, "solid": "all", "hp": 0.5, "group": "build_roofs"},
	"roof_flat": {"name": "Flat Roof", "size": Vector3i(2, 1, 2), "mats": ROOFS, "units": 3, "solid": "all", "hp": 0.8, "group": "build_roofs"},
	# Furniture and storage (one material).
	"table": {"name": "Table", "size": Vector3i(2, 1, 1), "cost": {"planks": 6}, "solid": "all", "hp": 60.0, "group": "build_furniture"},
	"chair": {"name": "Chair", "size": Vector3i(1, 1, 1), "cost": {"planks": 3, "stick": 2}, "solid": "none", "hp": 40.0, "group": "build_furniture"},
	"bench": {"name": "Bench", "size": Vector3i(2, 1, 1), "cost": {"planks": 4}, "solid": "none", "hp": 50.0, "group": "build_furniture"},
	"bed": {"name": "Bed", "size": Vector3i(1, 1, 2), "cost": {"planks": 6, "wool": 3}, "solid": "none", "hp": 60.0, "group": "build_furniture", "use": "bed"},
	"shelf": {"name": "Wall Shelf", "size": Vector3i(2, 1, 1), "cost": {"planks": 4, "stick": 2}, "solid": "none", "hp": 40.0, "group": "build_furniture", "mount": true},
	"wall_torch": {"name": "Wall Torch", "size": Vector3i(1, 1, 1), "cost": {"torch": 2, "stick": 1}, "solid": "none", "hp": 20.0, "group": "build_furniture", "mount": true, "light": true},
	"lantern_post": {"name": "Lantern Post", "size": Vector3i(1, 3, 1), "cost": {"lantern": 1, "planks": 2}, "solid": "none", "hp": 40.0, "group": "build_furniture", "light": true},
	"chest": {"name": "Wooden Chest", "size": Vector3i(1, 1, 1), "cost": {"planks": 8, "stick": 2}, "solid": "all", "hp": 80.0, "group": "build_storage", "use": "container", "slots": 24},
	"chest_iron": {"name": "Iron-bound Chest", "size": Vector3i(1, 1, 1), "cost": {"planks": 8, "iron_ingot": 2}, "solid": "all", "hp": 220.0, "group": "build_storage", "use": "container", "slots": 36, "station": "anvil"},
	"barrel": {"name": "Barrel", "size": Vector3i(1, 1, 1), "cost": {"planks": 6, "stick": 2}, "solid": "all", "hp": 70.0, "group": "build_storage", "use": "container", "slots": 18},
}

const PREFIX := "bp_"


# --- Item ids -------------------------------------------------------------------

static func item_id(kind: String, mat := "") -> String:
	return PREFIX + kind + ("_" + mat if mat != "" else "")


## [kind, material] of a building item id, or [] when it is not one.
static func parse(id: String) -> Array:
	if not id.begins_with(PREFIX):
		return []
	var rest := id.trim_prefix(PREFIX)
	if PIECES.has(rest) and not PIECES[rest].has("mats"):
		return [rest, ""]
	var cut := rest.rfind("_")
	while cut > 0:
		var kind := rest.substr(0, cut)
		var mat := rest.substr(cut + 1)
		if PIECES.has(kind) and mat in PIECES[kind].get("mats", []):
			return [kind, mat]
		cut = rest.rfind("_", cut - 1)
	return []


static func display_name(kind: String, mat: String) -> String:
	var p: Dictionary = PIECES[kind]
	if mat == "":
		return String(p["name"])
	return "%s %s" % [MATS[mat]["name"], p["name"]]


## Every (kind, material) pair that exists, in catalogue order.
static func all_pairs() -> Array:
	var out: Array = []
	for kind: String in PIECES:
		var mats: Array = PIECES[kind].get("mats", [""])
		for mat: String in mats:
			out.append([kind, mat])
	return out


static func cost(kind: String, mat: String) -> Dictionary:
	var p: Dictionary = PIECES[kind]
	if p.has("cost"):
		return (p["cost"] as Dictionary).duplicate()
	var out := {}
	var units := int(p.get("units", 1))
	var m: Dictionary = MATS[mat]
	for item: String in m["unit"]:
		out[item] = int(out.get(item, 0)) + int(m["unit"][item]) * units
	if m.get("iron", false):
		out["iron_ingot"] = int(out.get("iron_ingot", 0)) + maxi(1, units / 2)
	for item: String in p.get("extra", {}):
		out[item] = int(out.get(item, 0)) + int(p["extra"][item])
	return out


static func max_hp(kind: String, mat: String) -> float:
	var p: Dictionary = PIECES[kind]
	if mat == "":
		return float(p.get("hp", 50.0))
	return float(MATS[mat]["hp"]) * float(p.get("hp", 1.0))


static func use_of(kind: String) -> String:
	return String(PIECES.get(kind, {}).get("use", ""))


static func container_slots(kind: String) -> int:
	return int(PIECES.get(kind, {}).get("slots", 0))


# --- Grid maths -----------------------------------------------------------------------

static func size_of(kind: String) -> Vector3i:
	return PIECES[kind]["size"]


## Footprint size in world cells after `rot` quarter turns.
static func footprint(kind: String, rot: int) -> Vector3i:
	var s := size_of(kind)
	return Vector3i(s.z, s.y, s.x) if posmod(rot, 2) == 1 else s


## Piece frame -> world transform (piece frame origin at its local min corner).
static func transform(kind: String, anchor: Vector3i, rot: int) -> Transform3D:
	var s := size_of(kind)
	var f := footprint(kind, rot)
	var centre := Vector3(anchor) + Vector3(f.x * 0.5, 0.0, f.z * 0.5)
	var basis := Basis(Vector3.UP, posmod(rot, 4) * PI * 0.5)
	return Transform3D(basis, centre) * Transform3D(Basis.IDENTITY, -Vector3(s.x * 0.5, 0.0, s.z * 0.5))


## Every world cell of the footprint, with whether it is solid in `state`
## (0 closed, 1 open): [[Vector3i, bool], ...].
static func cells(kind: String, anchor: Vector3i, rot: int, state := 0) -> Array:
	var out: Array = []
	var s := size_of(kind)
	var xf := transform(kind, anchor, rot)
	var p: Dictionary = PIECES[kind]
	var rule := String(p.get("open_solid", p["solid"])) if state == 1 else String(p["solid"])
	for y in s.y:
		for z in s.z:
			for x in s.x:
				var w := xf * (Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5))
				var solid := rule == "all" or (rule == "back" and z == 0) or (rule == "top" and y == s.y - 1)
				out.append([Vector3i(w.floor()), solid])
	return out


## Quarter turn that makes the piece front (+z) point along `dir` (xz).
static func rot_facing(dir: Vector3) -> int:
	return posmod(roundi(atan2(dir.x, dir.z) / (PI * 0.5)), 4)


## Anchor for a piece whose footprint contains `cell` and grows away from a
## surface with normal `n`. Along axes where the piece is longer than a cell
## the footprint snaps to a grid of its own length, lined up with `align` (the
## anchor of the piece aimed at, so walls meet foundations edge to edge;
## Vector3i.ZERO = the world's even grid).
static func anchor_for(kind: String, rot: int, cell: Vector3i, n: Vector3i, align := Vector3i.ZERO) -> Vector3i:
	var f := footprint(kind, rot)
	var a := cell
	if n.y < 0:
		a.y = cell.y - f.y + 1  # hanging under a ceiling grows downwards
	for axis: int in [0, 2]:
		var size := f[axis]
		if size <= 1:
			continue
		if n[axis] > 0:
			a[axis] = cell[axis]
		elif n[axis] < 0:
			a[axis] = cell[axis] - size + 1
		else:
			a[axis] = cell[axis] - posmod(cell[axis] - align[axis], size)
	return a
