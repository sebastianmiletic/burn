class_name VillageLayout
extends RefCounted
## Where a village's people live and work. Doors are read from the collision
## of the village's buildings (the STRUCTURE / wall cells of its blueprints, which
## by contract match the modelled houses), so routines follow the real
## buildings whatever their shape. Work places come from the location's spawns
## (stations, the merchant's stall, the guard post). Cached per location.
##
## A door: {"pos": threshold (feet), "out": unit vector pointing outside,
##          "outside": stand point in front of it, "inside": point within,
##          "width": cells, "hall": bool (the widest door, the chief's hall)}

static var _cache := {}

var location_id: StringName = &""
var center := Vector3.ZERO
var doors: Array[Dictionary] = []
var stations := {}          # station kind -> Vector3
var guard_post := Vector3.INF
var merchant_spot := Vector3.INF


static func of(loc: Location) -> VillageLayout:
	if loc == null:
		return null
	if _cache.has(loc.id):
		return _cache[loc.id]
	var v := VillageLayout.new()
	v._read(loc)
	_cache[loc.id] = v
	return v


## Tests build layouts for synthetic locations; drop cached ones.
static func forget(loc_id: StringName) -> void:
	_cache.erase(loc_id)


func _read(loc: Location) -> void:
	location_id = loc.id
	center = loc.center
	for s: Dictionary in loc.spawns:
		match String(s["type"]):
			"station":
				stations[String(s.get("station", "workbench"))] = s["pos"]
			"guard_post":
				guard_post = s["pos"]
			"npc":
				if String(s.get("role", "")) == "merchant":
					merchant_spot = s["pos"]
			"door":
				# Explicit doors from the village builder win over detection.
				var out: Vector3 = s.get("out", Vector3.FORWARD)
				doors.append(_door(s["pos"], out, int(s.get("width", 1)), bool(s.get("hall", false))))
	if doors.is_empty():
		for bp in loc.blueprints:
			_scan_doors(bp)
	if not doors.is_empty():
		var widest := 0
		for d in doors:
			widest = maxi(widest, int(d["width"]))
		if widest >= 2:
			for d in doors:
				d["hall"] = int(d["width"]) == widest
	# Doors nearest the plaza first: stable assignment order.
	doors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["pos"] as Vector3).distance_squared_to(center) < (b["pos"] as Vector3).distance_squared_to(center))


static func _door(threshold: Vector3, out: Vector3, width: int, hall: bool) -> Dictionary:
	out = Vector3(out.x, 0.0, out.z).normalized()
	return {"pos": threshold, "out": out, "outside": threshold + out * 1.4, "inside": threshold - out * 1.6,
		"width": width, "hall": hall}


static func _solid(v: int) -> bool:
	return v != Blueprint.KEEP and v != Blueprint.CARVE and v != Blocks.AIR and Blocks.is_solid(v) and not Blocks.is_smooth(v)


static func _open(v: int) -> bool:
	return v == Blueprint.KEEP or v == Blueprint.CARVE or v == Blocks.AIR or not Blocks.is_solid(v)


## A door is an opening at least two cells tall in a wall, standing on a solid
## threshold, with a roofed room on one side and open air on the other.
func _scan_doors(bp: Blueprint) -> void:
	var sx := bp.size.x
	var sz := bp.size.z
	var layer := sx * sz
	var found := {}  # Vector3i local bottom cell -> axis (0 = wall along x, 1 = along z)
	var i := bp.data.find(Blueprint.CARVE)
	while i >= 0:
		var y := i / layer
		var z := (i % layer) / sx
		var x := i % sx
		i = bp.data.find(Blueprint.CARVE, i + 1)
		if y < 1 or not _solid(bp.get_local(x, y - 1, z)) or not _open(bp.get_local(x, y + 1, z)):
			continue
		# A lintel two or three cells up: the opening is in a wall, not a room.
		if not _lintel(bp, Vector3i(x, y, z)):
			continue
		for axis in 2:
			var a := Vector3i(1, 0, 0) if axis == 0 else Vector3i(0, 0, 1)
			var b := Vector3i(0, 0, 1) if axis == 0 else Vector3i(1, 0, 0)
			if not _open(bp.get_local(x + b.x, y, z + b.z)) or not _open(bp.get_local(x - b.x, y, z - b.z)):
				continue
			# Jambs: the wall continues on both sides (possibly past a wide door).
			if not _jamb(bp, Vector3i(x, y, z), a) or not _jamb(bp, Vector3i(x, y, z), -a):
				continue
			var roof_plus := _roofed(bp, Vector3i(x, y, z) + b * 2)
			var roof_minus := _roofed(bp, Vector3i(x, y, z) - b * 2)
			if roof_plus == roof_minus:
				continue
			found[Vector3i(x, y, z)] = [axis, b if roof_minus else -b]
			break
	# Merge neighbouring cells of one doorway.
	var used := {}
	for cell: Vector3i in found:
		if used.has(cell):
			continue
		var axis: int = found[cell][0]
		var out: Vector3i = found[cell][1]
		var a := Vector3i(1, 0, 0) if axis == 0 else Vector3i(0, 0, 1)
		var cells: Array[Vector3i] = [cell]
		used[cell] = true
		for dir: Vector3i in [a, -a]:
			var n := cell + dir
			while found.has(n) and not used.has(n):
				used[n] = true
				cells.append(n)
				n += dir
		var sum := Vector3.ZERO
		for c in cells:
			sum += Vector3(c)
		var mid := sum / cells.size()
		var threshold := Vector3(bp.origin) + mid + Vector3(0.5, 0.0, 0.5)
		doors.append(_door(threshold, Vector3(out), cells.size(), false))


func _lintel(bp: Blueprint, cell: Vector3i) -> bool:
	if _solid(bp.get_local(cell.x, cell.y + 2, cell.z)):
		return true
	return _open(bp.get_local(cell.x, cell.y + 2, cell.z)) and _solid(bp.get_local(cell.x, cell.y + 3, cell.z))


func _jamb(bp: Blueprint, cell: Vector3i, dir: Vector3i) -> bool:
	for k in range(1, 4):
		var c := cell + dir * k
		var v := bp.get_local(c.x, c.y, c.z)
		if _solid(v):
			return true
		if v != Blueprint.CARVE or not _lintel(bp, c):
			return false
	return false


func _roofed(bp: Blueprint, cell: Vector3i) -> bool:
	if _solid(bp.get_local(cell.x, cell.y, cell.z)):
		return false
	for dy in range(2, 12):
		if _solid(bp.get_local(cell.x, cell.y + dy, cell.z)):
			return true
	return false


## The door a person of `role` calls home. `seed` spreads villagers over the houses.
func home_door(role: String, seed_value: int, near: Vector3) -> Dictionary:
	if doors.is_empty():
		return {}
	var houses: Array[Dictionary] = []
	var hall: Dictionary = {}
	for d in doors:
		if d["hall"] and hall.is_empty():
			hall = d
		else:
			houses.append(d)
	if role in ["elder", "chief"] and not hall.is_empty():
		return hall
	if houses.is_empty():
		return hall
	if role in ["merchant", "blacksmith"]:
		return _nearest(houses, near)
	return houses[absi(seed_value) % houses.size()]


static func _nearest(list: Array[Dictionary], p: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for d in list:
		var dd := (d["pos"] as Vector3).distance_squared_to(p)
		if dd < best_d:
			best_d = dd
			best = d
	return best


## Where the smith stands to work the anvil (beside it, on the plaza side).
func forge_spot() -> Vector3:
	if not stations.has("anvil"):
		return Vector3.INF
	var anvil: Vector3 = stations["anvil"]
	var to := center - anvil
	to.y = 0.0
	return anvil + (to.normalized() if to.length() > 0.1 else Vector3.BACK) * 1.15


func anvil() -> Vector3:
	return stations.get("anvil", Vector3.INF)
