class_name ScumportPlan
extends RefCounted
## Scumport (world revision 5 only): a crowded smugglers' harbour town built out
## over the water on the west shore of its isle. A grid of plank boardwalks on
## piles (narrow alleys, one main street, a canal crossed by rope bridges, a
## waterfront promenade) between blocks of tall, narrow houses packed wall to
## wall in two back-to-back rows: two to four storeys, jettied over the alleys.
## A market quay with stalls; taverns and shops you can walk into; warehouses
## on the waterfront; piers with skiffs, two moored hulks and cranes.
##
## Collision is the usual invisible Blocks.STRUCTURE: every deck cell is solid
## at DECK (people walk at DECK + 1), houses are solid (ground-floor rooms of
## taverns and shops carved), streets carved above the deck. The town keeps
## to columns no higher than DECK + 1, so it follows the shoreline.
##
## Town cells (the `cells` grid, x0/z0 origin, nx * nz): see the T_* constants.

const S := Blocks.STRUCTURE
const SEA := WorldGen.SEA_LEVEL
const DECK := WorldGen.SEA_LEVEL + 2
const STOREY := 2.8
const INLAND := 26
const SEAWARD := 92
const HALF := 82

const T_OUT := 0      ## not part of the town
const T_STREET := 1   ## boardwalk
const T_LOT := 2      ## under a house
const T_WATER := 3    ## open water inside the town (the canal)
const T_PLAZA := 4    ## the market quay
const T_BRIDGE := 5   ## rope bridge over the canal
const T_BLOCK := 6    ## inside a block while planning (yards become street)

const WALLS := [
	[ArchMaterials.L.BOARDS, Color(0.62, 0.55, 0.46)], [ArchMaterials.L.BOARDS, Color(0.24, 0.2, 0.18)],
	[ArchMaterials.L.BOARDS, Color(0.3, 0.4, 0.36)], [ArchMaterials.L.BOARDS, Color(0.5, 0.24, 0.18)],
	[ArchMaterials.L.PLASTER, Color(0.58, 0.53, 0.45)], [ArchMaterials.L.IRON, Color(0.5, 0.36, 0.27)],
	[ArchMaterials.L.BOARDS, Color(0.42, 0.36, 0.3)],
]
const TAVERNS := ["The Drowned Rat", "The Bilge & Barnacle", "The Hanged Gull", "Mother Kelp's"]


static func plan(planner: LocationPlanner, seed_value: int) -> Location:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var C: Vector2 = AdventureTerrain.ISLES["scumport"][0]
	var shore := C
	for i in 60:
		var q := C + Vector2(-i * 3.0, 0)
		if planner._ground(q.x, q.y) <= SEA + 1:
			shore = q
			break
	var o := Vector2i(roundi(shore.x), roundi(shore.y))
	var x0 := o.x - SEAWARD
	var z0 := o.y - HALF
	var nx := SEAWARD + INLAND
	var nz := HALF * 2
	# Ground every 2 m (the town keeps to columns at or below the deck).
	var gw := nx / 2 + 1
	var gh := PackedFloat32Array()
	gh.resize(gw * (nz / 2 + 1))
	for gz in nz / 2 + 1:
		for gx in gw:
			gh[gx + gz * gw] = float(planner._ground(x0 + gx * 2, z0 + gz * 2))
	var town := {"x0": x0, "z0": z0, "nx": nx, "nz": nz, "cells": PackedByteArray(), "gw": gw, "gh": gh}
	var cells: PackedByteArray = town["cells"]
	cells.resize(nx * nz)
	# Streets running along the shore (fixed x bands), seaward first.
	var xstreets: Array = [[x0, x0 + 5]]
	var xblocks: Array = []
	var pos := x0 + 5
	var main_done := false
	while pos < x0 + nx - 6:
		var depth := rng.randi_range(10, 14)
		xblocks.append([pos, mini(pos + depth, x0 + nx)])
		pos += depth
		var wdt := 3
		if not main_done and pos > o.x - 8:
			wdt = 4
			main_done = true
		xstreets.append([pos, pos + wdt])
		pos += wdt
	# Cross streets (fixed z bands): one main street through the middle, a canal each side.
	var zstreets: Array = [[z0, z0 + 3]]
	var zblocks: Array = []
	pos = z0 + 3
	while pos < z0 + nz - 8:
		var length := rng.randi_range(13, 20)
		zblocks.append([pos, mini(pos + length, z0 + nz)])
		pos += length
		var wdt := rng.randi_range(2, 3)
		zstreets.append([pos, pos + wdt])
		pos += wdt
	var mid := 0
	for i in zstreets.size():
		if absi((zstreets[i][0] + zstreets[i][1]) / 2 - o.y) < absi((zstreets[mid][0] + zstreets[mid][1]) / 2 - o.y):
			mid = i
	zstreets[mid][1] = zstreets[mid][0] + 4
	var canals: Array = []
	for k: int in [mid - 2, mid + 2]:
		if k > 0 and k < zstreets.size() - 1:
			canals.append(k)
	# Paint streets, then canals (water between walkways, bridges where streets cross).
	for xs: Array in xstreets:
		_fill(town, Rect2i(xs[0], z0, xs[1] - xs[0], nz), T_STREET)
	for zs: Array in zstreets:
		_fill(town, Rect2i(x0, zs[0], nx, zs[1] - zs[0]), T_STREET)
	var bridges: Array = []
	for k: int in canals:
		var zs: Array = zstreets[k]
		zs[1] = zs[0] + 5
		_fill(town, Rect2i(x0, zs[0] + 1, nx, 3), T_WATER)
		for xs: Array in xstreets:
			_fill(town, Rect2i(xs[0], zs[0] + 1, xs[1] - xs[0], 3), T_BRIDGE)
			bridges.append([Vector3(xs[0], DECK + 1, zs[0] + 1), Vector3(xs[1], DECK + 1, zs[0] + 4)])
	# The market quay: the block nearest the water in front of the main street.
	var plaza := Rect2i()
	var best := 1e9
	var lots: Array = []
	for xb: Array in xblocks:
		for zb: Array in zblocks:
			var r := Rect2i(xb[0], zb[0], xb[1] - xb[0], zb[1] - zb[0])
			var clash := false
			for k: int in canals:
				if r.intersects(Rect2i(x0, zstreets[k][0], nx, 5)):
					clash = true
			if clash:
				r = _trim(r, zstreets, canals)
				if r.size.y < 6:
					continue
			var dc := Vector2(r.get_center()).distance_to(Vector2(o.x - 30, o.y))
			if dc < best:
				best = dc
				plaza = r
			lots.append(r)
	lots.erase(plaza)
	for r: Rect2i in lots:
		_fill_empty(town, r, T_BLOCK)
	_fill(town, plaza, T_PLAZA)
	# Columns too high (the hillside behind) and canal water over dry ground drop out.
	for z in nz:
		for x in nx:
			var g := _ground_at(town, x0 + x, z0 + z)
			if g > DECK + 1:
				cells[x + z * nx] = T_OUT
			elif cells[x + z * nx] == T_WATER and g >= SEA - 1:
				cells[x + z * nx] = T_STREET
	# Houses: each block is two back-to-back rows of narrow lots facing the streets.
	var houses: Array = []
	for r: Rect2i in lots:
		var rows: Array = []
		if r.size.x >= 9:
			var half := r.size.x / 2 + rng.randi_range(-1, 1)
			rows.append([Rect2i(r.position.x, r.position.y, half, r.size.y), Vector2i(-1, 0)])
			rows.append([Rect2i(r.position.x + half, r.position.y, r.size.x - half, r.size.y), Vector2i(1, 0)])
		else:
			rows.append([r, Vector2i(-1, 0)])
		for row: Array in rows:
			var rr: Rect2i = row[0]
			var z := rr.position.y
			while z < rr.end.y:
				var wdt := rng.randi_range(4, 7)
				if rr.end.y - (z + wdt) < 4:
					wdt = rr.end.y - z
				var lot := Rect2i(rr.position.x, z, rr.size.x, wdt)
				z += wdt
				var h := _house(town, lot, row[1], rng)
				if not h.is_empty():
					houses.append(h)
	for i in cells.size():
		if cells[i] == T_BLOCK:
			cells[i] = T_STREET
	# Taverns and shops: the roomiest lots nearest the market.
	var pc := Vector2(plaza.get_center())
	houses.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return Vector2(a["center"].x, a["center"].z).distance_to(pc) < Vector2(b["center"].x, b["center"].z).distance_to(pc))
	var taverns := 0
	var shops := 0
	for h: Dictionary in houses:
		if taverns < TAVERNS.size() and h["w"] >= 6 and h["d"] >= 5 and rng.randf() < 0.5:
			h["role"] = "tavern"
			h["name"] = TAVERNS[taverns]
			taverns += 1
		elif shops < 9 and h["w"] >= 4 and h["d"] >= 4 and rng.randf() < 0.45:
			h["role"] = "shop"
			shops += 1
		elif h["front"] == Vector2i(-1, 0) and int(h["lot"].position.x) < x0 + 22 and h["w"] >= 5 and rng.randf() < 0.6:
			h["role"] = "warehouse"
		_finish_house(h, rng)
	# Piers out into the harbour from the promenade, a hulk moored at two of them.
	var piers: Array = []
	var pz := z0 + 10
	var k_pier := 0
	while pz < z0 + nz - 8:
		var ok := cells[2 + (pz - z0) * nx] == T_STREET
		if ok:
			var length := 22 + (k_pier % 3) * 6
			piers.append({"z": pz, "x1": x0, "x0": x0 - length, "hulk": k_pier % 3 == 1})
			k_pier += 1
		pz += rng.randi_range(17, 24)
	var loc := Location.new(&"scumport", "Scumport", Location.Kind.RUIN, Vector3(plaza.get_center().x, DECK + 1, plaza.get_center().y))
	loc.ground_y = DECK
	loc.radius = 100.0
	loc.major = true
	loc.set_meta(&"map_kind", "scumport")
	var bp := Blueprint.new(Vector3i(x0 - 40, DECK - 2, z0), Vector3i(nx + 40, 26, nz))
	loc.blueprints.append(bp)
	_stamp(bp, town, houses, piers)
	# Market stalls round the quay (counters solid).
	var stalls: Array = []
	var sc := Vector2(plaza.get_center())
	for i in 6:
		var a := TAU * i / 6.0 + 0.4
		var p := sc + Vector2(cos(a) * minf(plaza.size.x, plaza.size.y) * 0.32, sin(a) * plaza.size.y * 0.34)
		var cell := Vector3i(floori(p.x), DECK + 1, floori(p.y))
		stalls.append({"at": Vector3(cell.x + 0.5, DECK + 1, cell.z + 0.5), "yaw": a + PI * 0.5})
		_put(bp, cell, S)
	# People: traders at the stalls and shops, fishers on the piers, crowds in the streets.
	var folk: Array = []
	for st: Dictionary in stalls:
		var at: Vector3 = st["at"]
		var out := (Vector3(sc.x, at.y, sc.y) - at).normalized()
		loc.add_spawn("npc", (at + out * 1.4).floor() + Vector3(0.5, 0, 0.5), {"role": "merchant" if folk.size() % 2 == 0 else "villager"})
		folk.append(at)
	for h: Dictionary in houses:
		var front: Vector3 = h["door_out"]
		loc.add_spawn("door", front - h["out"] * 1.2, {"out": h["out"], "width": h["door_w"], "hall": h["role"] == "tavern"})
		match String(h["role"]):
			"shop":
				loc.add_spawn("npc", h["inside"], {"role": "merchant"})
			"tavern":
				loc.add_spawn("npc", h["inside"], {"role": "villager"})
				loc.add_spawn("npc", front, {"role": "villager"})
	for pr: Dictionary in piers:
		loc.add_spawn("npc", Vector3(pr["x0"] + 3.5, DECK + 1, pr["z"] + 0.5), {"role": "fisher"})
	var streets: Array = []
	for z in range(0, nz, 3):
		for x in range(0, nx, 3):
			if cells[x + z * nx] == T_STREET and _clear(bp, Vector3i(x0 + x, DECK + 1, z0 + z)):
				streets.append(Vector3(x0 + x + 0.5, DECK + 1, z0 + z + 0.5))
	for i in 26:
		if streets.is_empty():
			break
		loc.add_spawn("npc", streets[rng.randi() % streets.size()], {"role": "villager"})
	loc.add_spawn("chest", Vector3(plaza.position.x + 1.5, DECK + 1, plaza.position.y + 1.5), {"tier": 2})
	var lamps: Array = []
	for i in range(0, streets.size(), maxi(1, streets.size() / 70)):
		lamps.append(streets[i])
	loc.props.append({"type": "builder", "builder": Callable(ScumportArch, "build"), "town": town, "houses": houses, "piers": piers,
			"bridges": bridges, "plaza": plaza, "stalls": stalls, "lamps": lamps, "seed": rng.randi()})
	# The map draws each roof (material "roof"); Architecture skips this type.
	for h: Dictionary in houses:
		loc.props.append({"type": "scum_house", "material": "roof", "at": h["center"], "size": h["size"]})
	loc.set_meta(&"adv", {"scum_folk": folk, "dock": Vector3(x0 - 6, SEA + 1, o.y)})
	return loc


static func _fill_empty(town: Dictionary, r: Rect2i, v: int) -> void:
	var cells: PackedByteArray = town["cells"]
	var nx: int = town["nx"]
	for z in range(maxi(r.position.y - town["z0"], 0), mini(r.end.y - town["z0"], int(town["nz"]))):
		for x in range(maxi(r.position.x - town["x0"], 0), mini(r.end.x - town["x0"], nx)):
			if cells[x + z * nx] == T_OUT:
				cells[x + z * nx] = v


static func _fill(town: Dictionary, r: Rect2i, v: int) -> void:
	var cells: PackedByteArray = town["cells"]
	var nx: int = town["nx"]
	var nz: int = town["nz"]
	for z in range(maxi(r.position.y - town["z0"], 0), mini(r.end.y - town["z0"], nz)):
		for x in range(maxi(r.position.x - town["x0"], 0), mini(r.end.x - town["x0"], nx)):
			cells[x + z * nx] = v


## A block cut by a canal band keeps its bigger side.
static func _trim(r: Rect2i, zstreets: Array, canals: Array) -> Rect2i:
	for k: int in canals:
		var a: int = zstreets[k][0]
		var b: int = a + 5
		if r.position.y < a and r.end.y > a:
			r = Rect2i(r.position.x, r.position.y, r.size.x, a - r.position.y) if a - r.position.y >= r.end.y - b else Rect2i(r.position.x, b, r.size.x, r.end.y - b)
		elif r.position.y >= a and r.position.y < b:
			r = Rect2i(r.position.x, b, r.size.x, r.end.y - b)
	return r


static func cell(town: Dictionary, x: int, z: int) -> int:
	var lx: int = x - int(town["x0"])
	var lz: int = z - int(town["z0"])
	if lx < 0 or lz < 0 or lx >= int(town["nx"]) or lz >= int(town["nz"]):
		return T_OUT
	return (town["cells"] as PackedByteArray)[lx + lz * int(town["nx"])]


static func walkable(t: int) -> bool:
	return t == T_STREET or t == T_PLAZA or t == T_BRIDGE


static func _ground_at(town: Dictionary, x: int, z: int) -> float:
	var gw: int = town["gw"]
	var gx := clampi((x - int(town["x0"])) / 2, 0, gw - 1)
	var gz := (z - int(town["z0"])) / 2
	var gh: PackedFloat32Array = town["gh"]
	return gh[clampi(gx + gz * gw, 0, gh.size() - 1)]


## One house on `lot` facing `front` (or the other way if only that side has a
## street). Returns {} when the lot leaves the town or has no street to face.
static func _house(town: Dictionary, lot: Rect2i, front: Vector2i, rng: RandomNumberGenerator) -> Dictionary:
	if lot.size.x < 3 or lot.size.y < 3:
		return {}
	for z in range(lot.position.y, lot.end.y):
		for x in range(lot.position.x, lot.end.x):
			if cell(town, x, z) != T_BLOCK:
				return {}
	# Which side faces a street: the row's own side first.
	var faces: Array = [front, -front, Vector2i(0, 1), Vector2i(0, -1)]
	var face := Vector2i.ZERO
	for f: Vector2i in faces:
		var mid := lot.get_center()
		var probe := Vector2i(lot.position.x if f.x < 0 else (lot.end.x if f.x > 0 else mid.x), lot.position.y if f.y < 0 else (lot.end.y if f.y > 0 else mid.y))
		probe += Vector2i(mini(f.x, 0), mini(f.y, 0))
		if walkable(cell(town, probe.x, probe.y)):
			face = f
			break
	if face == Vector2i.ZERO:
		return {}
	var rot := 0
	match face:
		Vector2i(1, 0):
			rot = 1
		Vector2i(0, -1):
			rot = 2
		Vector2i(-1, 0):
			rot = 3
	var w := lot.size.y if face.x != 0 else lot.size.x
	var d := lot.size.x if face.x != 0 else lot.size.y
	_fill(town, lot, T_LOT)
	var c := Vector2(lot.position) + Vector2(lot.size) * 0.5
	return {"lot": lot, "front": face, "rot": rot, "w": w, "d": d, "center": Vector3(c.x, DECK + 1, c.y), "role": "house",
			"door": clampi(rng.randi_range(1, w - 2), 1, maxi(1, w - 2)), "door_w": 1, "seed": rng.randi() % 100000}


static func _finish_house(h: Dictionary, rng: RandomNumberGenerator) -> void:
	var role := String(h["role"])
	var w: int = h["w"]
	var d: int = h["d"]
	var storeys := [1, 2, 2, 3, 3, 3, 4, 4][rng.randi() % 8] as int
	if role == "warehouse":
		storeys = 2
	elif role == "tavern":
		storeys = maxi(storeys, 3)
	h["storeys"] = storeys
	h["enterable"] = role in ["tavern", "shop"]
	if role in ["tavern", "warehouse"] and w >= 6:
		h["door_w"] = 2
		h["door"] = w / 2 - 1
	var mats: Array = []
	for s in storeys:
		mats.append(rng.randi() % WALLS.size())
	h["mats"] = mats
	h["jetty"] = role != "warehouse" and rng.randf() < 0.75
	h["roof"] = ["gable", "gable", "shed", "shed", "flat"][rng.randi() % 5] if role != "warehouse" else "gable"
	h["roof_tint"] = [Color(0.36, 0.3, 0.26), Color(0.3, 0.26, 0.24), Color(0.45, 0.34, 0.28), Color(0.28, 0.3, 0.3)][rng.randi() % 4]
	h["wall_h"] = storeys * STOREY
	h["kind"] = "tavern" if role == "tavern" else "shop"
	h["chimney"] = 0
	var out := Basis(Vector3.UP, int(h["rot"]) * PI * 0.5) * Vector3.BACK
	h["out"] = out
	h["door_out"] = VillagePlan.to_world(h, Vector3(-w * 0.5 + int(h["door"]) + int(h["door_w"]) * 0.5, 0.0, d * 0.5 + 1.0))
	h["inside"] = h["door_out"]
	var lot: Rect2i = h["lot"]
	h["size"] = Vector3(lot.size.x, storeys * STOREY, lot.size.y)
	# Furniture on the ground floor (local cells, VillageProps.furnish).
	var furn: Array = []
	if role == "tavern":
		furn.append({"kind": "counter", "cell": Vector2i(1, 1), "size": Vector2i(mini(3, w - 3), 1)})
		furn.append({"kind": "barrels", "cell": Vector2i(w - 2, 1), "size": Vector2i.ONE, "solid": false})
		if d >= 6:
			furn.append({"kind": "table", "cell": Vector2i(1, 3), "size": Vector2i(2, 1)})
		if w >= 7 and d >= 6:
			furn.append({"kind": "table", "cell": Vector2i(w - 3, 3), "size": Vector2i(2, 1)})
	elif role == "shop":
		furn.append({"kind": "counter", "cell": Vector2i(1, 1), "size": Vector2i(mini(3, w - 2), 1)})
	h["furniture"] = furn
	if h["enterable"]:
		h["inside"] = VillagePlan.to_world(h, Vector3(-w * 0.5 + int(h["door"]) + 0.5, 0.0, d * 0.5 - 1.5))


static func _put(bp: Blueprint, w: Vector3i, block: int) -> void:
	var l := w - bp.origin
	bp.set_local(l.x, l.y, l.z, block)


static func _clear(bp: Blueprint, w: Vector3i) -> bool:
	var l := w - bp.origin
	var v := bp.get_local(l.x, l.y, l.z)
	return v == Blueprint.KEEP or v == Blueprint.CARVE


## Writes the town's collision into `bp`.
static func _stamp(bp: Blueprint, town: Dictionary, houses: Array, piers: Array) -> void:
	var x0: int = town["x0"]
	var z0: int = town["z0"]
	var nx: int = town["nx"]
	var cells: PackedByteArray = town["cells"]
	for z in town["nz"]:
		for x in nx:
			var t := cells[x + z * nx]
			if t == T_OUT or t == T_WATER:
				continue
			_put(bp, Vector3i(x0 + x, DECK, z0 + z), S)
			for y in range(DECK + 1, DECK + 7):
				_put(bp, Vector3i(x0 + x, y, z0 + z), Blueprint.CARVE)
	for h: Dictionary in houses:
		var w: int = h["w"]
		var d: int = h["d"]
		var top := DECK + ceili(float(h["wall_h"]))
		var enterable: bool = h["enterable"]
		for k in d:
			for i in w:
				var edge := i == 0 or i == w - 1 or k == 0 or k == d - 1
				for y in range(DECK + 1, top + 1):
					var block := S
					if enterable and not edge and y <= DECK + 2:
						block = Blueprint.CARVE
					_put(bp, VillagePlan.cell_world(h, i, k, y), block)
		for i in range(int(h["door"]), int(h["door"]) + int(h["door_w"])):
			for y in range(DECK + 1, DECK + 3):
				_put(bp, VillagePlan.cell_world(h, i, d - 1, y), Blueprint.CARVE if enterable else S)
		for f: Dictionary in h["furniture"]:
			if not f.get("solid", true):
				continue
			var fc: Vector2i = f["cell"]
			var fs: Vector2i = f["size"]
			for dk in fs.y:
				for di in fs.x:
					_put(bp, VillagePlan.cell_world(h, fc.x + di, fc.y + dk, DECK + 1), S)
	for pr: Dictionary in piers:
		for x in range(int(pr["x0"]), int(pr["x1"])):
			for dz in range(-1, 2):
				_put(bp, Vector3i(x, DECK, int(pr["z"]) + dz), S)
		if pr["hulk"]:
			# The hulk alongside: a walkable deck inside a solid gunwale, a gangway to the pier.
			var hc := Vector2(float(pr["x0"]) + 12.0, float(pr["z"]) + 5.5)
			for dz in range(-3, 4):
				for dx in range(-10, 11):
					var e := Vector2(dx / 10.5, dz / 3.2).length()
					if e > 1.0:
						continue
					var cw := Vector3i(floori(hc.x) + dx, DECK, floori(hc.y) + dz)
					_put(bp, cw, S)
					if e > 0.78 and not (dz < 0 and absi(dx) <= 1):
						_put(bp, cw + Vector3i(0, 1, 0), S)
			for dz in range(2, 4):
				_put(bp, Vector3i(floori(hc.x), DECK, int(pr["z"]) + dz), S)
