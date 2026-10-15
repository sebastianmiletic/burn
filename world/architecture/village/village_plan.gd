class_name VillagePlan
extends RefCounted
## Lays out a village at world-planning time: picks the buildings and their
## places around the green, writes their invisible collision (Blocks.STRUCTURE,
## carved doorways and rooms) into the village blueprint, adds the spawns, and
## records specs in Location.props for the mesh builders (BuildingMesh,
## VillageProps) to model on a worker thread later.
##
## Villages keep to axis-aligned footprints so collision follows the voxel
## grid exactly. Every door opens onto the green; paths link doors, the green
## and the roads.

const PLAZA_R := 9.5

## Per-village look. Tints multiply the CC0 textures.
const STYLES := {
	&"emberfall": {
		"name": "autumn", "walls": "timber", "roofs": ["thatch", "thatch", "shingle"],
		"plaster": [Color(0.95, 0.9, 0.8), Color(0.93, 0.84, 0.66), Color(0.96, 0.94, 0.9), Color(0.9, 0.78, 0.62)],
		"timber": Color(0.52, 0.4, 0.31), "stone": Color(1.0, 0.94, 0.85), "roof_tint": Color(1.0, 0.96, 0.88),
		"shutters": [Color(0.3, 0.42, 0.3), Color(0.55, 0.22, 0.16), Color(0.25, 0.33, 0.45)],
		"door": Color(0.62, 0.46, 0.34), "banner": Color(0.62, 0.22, 0.1), "sign": Color(0.85, 0.5, 0.15),
		"wear": 0.5, "snow": 0.0, "stone_ratio": 0.25, "tavern": "The Ember Tankard", "chapel": true, "fence": "wattle",
	},
	&"ashford": {
		"name": "plains", "walls": "stone", "roofs": ["shingle", "thatch", "slate"],
		"plaster": [Color(0.96, 0.93, 0.86), Color(0.92, 0.87, 0.76)],
		"timber": Color(0.5, 0.4, 0.33), "stone": Color(1.02, 0.98, 0.9), "roof_tint": Color(0.95, 0.9, 0.85),
		"shutters": [Color(0.24, 0.32, 0.42), Color(0.3, 0.4, 0.28)],
		"door": Color(0.55, 0.42, 0.3), "banner": Color(0.2, 0.3, 0.55), "sign": Color(0.7, 0.7, 0.75),
		"wear": 0.45, "snow": 0.0, "stone_ratio": 0.6, "tavern": "The Ford", "chapel": true, "fence": "rail",
	},
	&"thornwick": {
		"name": "timber", "walls": "boards", "roofs": ["shingle", "shingle", "thatch"],
		"plaster": [Color(0.9, 0.85, 0.74)],
		"timber": Color(0.5, 0.38, 0.28), "stone": Color(0.85, 0.85, 0.8), "roof_tint": Color(0.85, 0.82, 0.78),
		"shutters": [Color(0.42, 0.3, 0.2), Color(0.3, 0.36, 0.26)],
		"door": Color(0.5, 0.38, 0.28), "banner": Color(0.25, 0.4, 0.2), "sign": Color(0.5, 0.65, 0.3),
		"wear": 0.7, "snow": 0.0, "stone_ratio": 0.0, "tavern": "The Thorn & Antler", "chapel": false, "fence": "rail",
		"hall": "longhouse", "palisade": "timber",
	},
	&"frosthold": {
		"name": "snow", "walls": "stone", "roofs": ["slate", "slate", "shingle"],
		"plaster": [Color(0.92, 0.92, 0.9)],
		"timber": Color(0.42, 0.34, 0.28), "stone": Color(0.82, 0.84, 0.88), "roof_tint": Color(0.85, 0.87, 0.92),
		"shutters": [Color(0.22, 0.3, 0.4), Color(0.45, 0.2, 0.15)],
		"door": Color(0.45, 0.34, 0.26), "banner": Color(0.2, 0.32, 0.5), "sign": Color(0.6, 0.75, 0.9),
		"wear": 0.2, "snow": 0.85, "stone_ratio": 0.85, "tavern": "The Hearthstone", "chapel": false, "fence": "rail",
		"hall": "longhouse", "palisade": "timber", "gable": "stone",
	},
	&"mirewatch": {
		"name": "marsh", "walls": "boards", "roofs": ["thatch", "thatch", "thatch"],
		"plaster": [Color(0.85, 0.82, 0.72)],
		"timber": Color(0.46, 0.4, 0.34), "stone": Color(0.78, 0.78, 0.72), "roof_tint": Color(0.68, 0.66, 0.6),
		"shutters": [Color(0.32, 0.38, 0.3)],
		"door": Color(0.45, 0.4, 0.33), "banner": Color(0.3, 0.38, 0.3), "sign": Color(0.5, 0.6, 0.45),
		"wear": 0.85, "snow": 0.0, "stone_ratio": 0.0, "tavern": "The Drowned Lantern", "chapel": false, "fence": "wattle",
		"stilts": true,
	},
	&"cinderreach": {
		"name": "ash", "walls": "stone", "roofs": ["slate", "slate", "slate"],
		"plaster": [Color(0.8, 0.76, 0.7)],
		"timber": Color(0.36, 0.3, 0.26), "stone": Color(0.55, 0.52, 0.5), "roof_tint": Color(0.62, 0.6, 0.6),
		"shutters": [Color(0.4, 0.18, 0.12), Color(0.3, 0.26, 0.22)],
		"door": Color(0.38, 0.3, 0.24), "banner": Color(0.6, 0.18, 0.08), "sign": Color(0.85, 0.35, 0.1),
		"wear": 0.15, "snow": 0.0, "stone_ratio": 1.0, "tavern": "The Cinder Cup", "chapel": true, "fence": "rail",
		"palisade": "stone",
	},
}


static func style_for(id: StringName) -> Dictionary:
	return STYLES.get(id, STYLES[&"emberfall"])


## Builds the whole village into `loc` (blueprint, spawns, props).
static func village(loc: Location, rng: RandomNumberGenerator, is_start: bool) -> void:
	loc.radius = 36.0
	loc.pad_radius = 27.0
	loc.pad_falloff = 12.0
	var bp := Blueprint.new(Vector3i(roundi(loc.center.x) - 32, loc.ground_y - 6, roundi(loc.center.z) - 32), Vector3i(65, 32, 65))
	loc.blueprints.append(bp)
	var st := style_for(loc.id)
	var ctx := {"loc": loc, "bp": bp, "rng": rng, "style": st, "rects": [] as Array[Rect2],
			"c": Vector2i(roundi(loc.center.x), roundi(loc.center.z)), "fy": loc.ground_y}
	# Reserved ground: the green, the shrine garden (its own location 21 m
	# south), the Ryft gateway north of Emberfall's green.
	var rects: Array[Rect2] = ctx["rects"]
	rects.append(Rect2(-PLAZA_R, -PLAZA_R, PLAZA_R * 2.0, PLAZA_R * 2.0))
	rects.append(Rect2(-6.5, 14.0, 13.0, 14.0))
	if is_start:
		rects.append(Rect2(-3.5, -16.0, 7.0, 8.0))
	# Which buildings, biggest first.
	var list: Array = []
	list.append({"role": "hall", "kind": String(st.get("hall", "house")), "w": 10 if st.get("hall", "") == "longhouse" else 9, "d": 7, "enterable": true})
	list.append({"role": "smithy", "kind": "smithy", "w": 8, "d": 6, "enterable": true})
	if st.get("tavern", "") != "":
		list.append({"role": "tavern", "kind": "tavern", "w": 9, "d": 7, "enterable": true})
	if st.get("chapel", false):
		list.append({"role": "chapel", "kind": "chapel", "w": 7, "d": 11, "enterable": true})
	var houses := 4 if is_start else 3 + rng.randi_range(0, 1)
	for i in houses:
		list.append({"role": "house", "kind": "house", "w": 6 + rng.randi_range(0, 2), "d": 5 + rng.randi_range(0, 1), "enterable": i % 2 == 0})
	# Slots round the green; the south one belongs to the shrine.
	var slots: Array[float] = []
	for a in [0.0, 40.0, 140.0, 180.0, 220.0, 270.0, 320.0, 60.0, 120.0, 245.0, 295.0]:
		slots.append(deg_to_rad(a + rng.randf_range(-6.0, 6.0)))
	var placed: Array = []
	for item: Dictionary in list:
		var spec := _place(ctx, item, slots)
		if spec.is_empty():
			continue
		placed.append(spec)
	# Spawns.
	var c: Vector2i = ctx["c"]
	var fy: int = ctx["fy"]
	var ground := float(fy + 1)
	for spec: Dictionary in placed:
		var front: Vector3 = spec["door_out"]
		match String(spec["role"]):
			"hall":
				loc.add_spawn("npc", front, {"role": "elder" if is_start else "chief"})
				loc.add_spawn("chest", spec["chest"], {"tier": 1})
			"smithy":
				loc.add_spawn("npc", spec["smith_pos"], {"role": "blacksmith"})
				for s: Dictionary in spec["stations"]:
					loc.add_spawn("station", s["pos"], {"station": s["station"], "yaw": s["yaw"]})
	for i in 4:
		var ang := TAU * (float(i) + 0.5) / 4.0 + rng.randf_range(-0.3, 0.3)
		loc.add_spawn("npc", Vector3(c.x + 0.5 + cos(ang) * 10.5, ground, c.y + 0.5 + sin(ang) * 10.5), {"role": "villager"})
	# The merchant stands at the first market stall.
	var stall_ang := deg_to_rad(205.0)
	loc.add_spawn("npc", Vector3(c.x + 0.5 + cos(stall_ang) * 5.6, ground, c.y + 0.5 + sin(stall_ang) * 5.6), {"role": "merchant"})
	loc.add_spawn("guard_post", Vector3(c.x + 0.5, ground, c.y + 0.5), {})
	# The green: well, stalls, lamps, signpost; paths are laid at build time.
	var items := _plan_props(ctx, placed)
	var green := {"type": "green", "material": "stone", "at": Vector3(c.x + 0.5, ground, c.y + 0.5), "size": Vector3.ONE,
			"style": st, "start": is_start, "seed": rng.randi(), "village": String(loc.id),
			"doors": placed.map(func(s: Dictionary) -> Vector3: return s["door_out"]),
			"rects": rects.duplicate(), "items": items, "c": c}
	loc.props.append(green)
	# The Ryft gateway north of Emberfall's green: an ancient carved arch.
	if is_start:
		var gate := Vector3(loc.center.x, ground, loc.center.z - 12.0)
		loc.props.append({"type": "site", "site": "gateway", "material": "stone", "at": gate, "size": Vector3.ONE,
				"portal": Vector2(3, 5), "seed": 7})
		for side: float in [-1.0, 1.0]:
			for y in range(1, 7):
				_put(bp, Vector3i(floori(gate.x + side * 2.05), fy + y, floori(gate.z)), Blocks.STRUCTURE)
	# Well collision: the kerb is solid.
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			_put(bp, Vector3i(c.x + dx, fy + 1, c.y + dz), Blocks.STRUCTURE)
	# Stalls: posts are solid, counters too.
	for k in 3:
		var a := deg_to_rad(205.0 + k * 50.0)
		var p := Vector2(c.x + 0.5, c.y + 0.5) + Vector2(cos(a), sin(a)) * 7.2
		_put(bp, Vector3i(floori(p.x), fy + 1, floori(p.y)), Blocks.STRUCTURE)


## Tries the slots in turn for one building; returns its spec, or {} if none fit.
static func _place(ctx: Dictionary, item: Dictionary, slots: Array[float]) -> Dictionary:
	var rng: RandomNumberGenerator = ctx["rng"]
	var rects: Array[Rect2] = ctx["rects"]
	for si in slots.size():
		var ang: float = slots[si]
		for r_try in 6:
			var r := 15.0 + r_try * 1.6 + float(maxi(item["w"], item["d"])) * 0.25
			var off := Vector2(cos(ang), sin(ang)) * r
			# Face the green.
			var rot := 0
			if absf(off.x) > absf(off.y):
				rot = 3 if off.x > 0.0 else 1
			else:
				rot = 2 if off.y > 0.0 else 0
			var w: int = item["w"]
			var d: int = item["d"]
			var wr := w if rot % 2 == 0 else d
			var dr := d if rot % 2 == 0 else w
			var x0 := roundi(off.x - wr * 0.5)
			var z0 := roundi(off.y - dr * 0.5)
			var rect := Rect2(x0, z0, wr, dr)
			# Stay on the flat pad.
			var far := 0.0
			for corner: Vector2 in [rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)]:
				far = maxf(far, corner.length())
			if far > 27.5:
				break
			var grown := rect.grow(2.2)
			var clash := false
			for other in rects:
				if grown.intersects(other):
					clash = true
					break
			if clash:
				continue
			rects.append(rect)
			slots.remove_at(si)
			return _commit(ctx, item, rect, rot)
	return {}


## Writes collision and returns the spec for a building placed at `rect`
## (offset cells from the village centre cell) facing `rot`.
static func _commit(ctx: Dictionary, item: Dictionary, rect: Rect2, rot: int) -> Dictionary:
	var loc: Location = ctx["loc"]
	var bp: Blueprint = ctx["bp"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var st: Dictionary = ctx["style"]
	var c: Vector2i = ctx["c"]
	var fy: int = ctx["fy"]
	var kind := String(item["kind"])
	var role := String(item["role"])
	var w: int = item["w"]
	var d: int = item["d"]
	if kind == "house":
		kind = "stone" if rng.randf() < float(st.get("stone_ratio", 0.3)) else "cottage"
		if st.get("stilts", false):
			kind = "stilt"
	if role == "hall" and kind == "house":
		kind = "stone" if float(st.get("stone_ratio", 0.3)) > 0.5 else "cottage"
	var raise := 1.0 if kind == "stilt" else 0.0
	var center := Vector3(c.x + rect.position.x + rect.size.x * 0.5, fy + 1, c.y + rect.position.y + rect.size.y * 0.5)
	var roofs: Array = st["roofs"]
	var roof: String = roofs[rng.randi() % roofs.size()]
	if kind == "stone" and roof == "thatch" and rng.randf() < 0.5:
		roof = "slate"
	if kind == "chapel":
		roof = "slate" if st.get("name", "") != "autumn" else "shingle"
	if kind == "smithy" and roof == "thatch":
		roof = "shingle"
	var wall_h := 3.0
	match kind:
		"tavern":
			wall_h = 5.4
		"longhouse":
			wall_h = 2.7
		"chapel":
			wall_h = 4.4
		"smithy":
			wall_h = 3.2
		"stone":
			wall_h = 3.0 if role != "hall" else 3.4
		"cottage":
			wall_h = 3.0 if role != "hall" else 3.4
	var pitch := 50.0 if roof == "thatch" else 42.0
	if kind == "longhouse":
		pitch = 52.0
	if st.get("snow", 0.0) > 0.5:
		pitch += 4.0
	var door_w := 2 if role in ["hall", "tavern", "chapel"] else 1
	var door := w / 2 - (1 if door_w == 2 else 0) if kind != "smithy" else w / 2
	if role == "house":
		door = rng.randi_range(1, w - 2 - door_w + 1) if w > 5 else w / 2
		door = clampi(door, 1, w - 1 - door_w)
	var chimney := 0
	if kind in ["cottage", "stone", "tavern", "stilt"] or (kind == "longhouse" and false):
		chimney = -1 if rng.randf() < 0.5 else 1
	var plaster_list: Array = st["plaster"]
	var shutter_list: Array = st["shutters"]
	var style := {
		"plaster": plaster_list[rng.randi() % plaster_list.size()], "timber": st["timber"], "stone": st["stone"],
		"roof_tint": st["roof_tint"], "shutters": shutter_list[rng.randi() % shutter_list.size()], "door": st["door"],
		"wear": st["wear"], "snow": st["snow"], "walls": st["walls"], "banner": st["banner"], "sign": st["sign"],
		"gable": st.get("gable", ""),
	}
	var spec := {
		"type": "building", "material": "roof", "role": role, "kind": kind,
		"at": center, "size": Vector3(rect.size.x, wall_h, rect.size.y),
		"center": center, "rot": rot, "w": w, "d": d, "wall_h": wall_h, "roof": roof, "pitch": pitch,
		"door": door, "door_w": door_w, "enterable": item["enterable"], "chimney": chimney, "raise": raise,
		"style": style, "seed": rng.randi() % 100000, "hood": kind == "cottage" and rng.randf() < 0.6,
	}
	if kind == "tavern":
		spec["lower_h"] = 2.75
	spec["furniture"] = _furniture(spec, rng)
	_collide(bp, spec, fy)
	# The spot just outside the door (world, on the ground).
	var door_local := Vector3(-w * 0.5 + door + door_w * 0.5, 0.0, d * 0.5 + 1.2 + (1.8 if raise > 0.0 else 0.0))
	spec["door_out"] = to_world(spec, door_local) - Vector3(0, raise, 0)
	if role == "hall":
		# The chest stands against the back wall in the first free cell from the middle.
		var used := {}
		for f: Dictionary in spec["furniture"]:
			var fc: Vector2i = f["cell"]
			var fs: Vector2i = f.get("size", Vector2i.ONE)
			for dk in fs.y:
				for di in fs.x:
					used[fc + Vector2i(di, dk)] = true
		var ci := w / 2
		for k in w:
			var i := w / 2 + (k + 1) / 2 * (1 if k % 2 == 0 else -1)
			if i >= 1 and i <= w - 2 and not used.has(Vector2i(i, 1)):
				ci = i
				break
		spec["chest"] = to_world(spec, Vector3(-w * 0.5 + ci + 0.5, 0.0, -d * 0.5 + 1.5))
	if kind == "smithy":
		# Stations inside the open front: anvil in the middle, the furnace by
		# the forge, the workbench along the right side.
		spec["smith_pos"] = to_world(spec, Vector3(0.0, 0.0, d * 0.5 + 1.0))
		var yaw := rot * PI * 0.5
		spec["stations"] = [
			{"station": "anvil", "pos": to_world(spec, Vector3(-0.2, 0.0, 0.6)), "yaw": yaw + PI * 0.5},
			{"station": "furnace", "pos": to_world(spec, Vector3(-w * 0.5 + 3.6, 0.0, -d * 0.5 + 1.25)), "yaw": yaw},
			{"station": "workbench", "pos": to_world(spec, Vector3(w * 0.5 - 1.2, 0.0, -0.6)), "yaw": yaw - PI * 0.5},
		]
	loc.props.append(spec)
	return spec


## Local building position (frame of BuildingMesh) to world.
static func to_world(spec: Dictionary, local: Vector3) -> Vector3:
	var rot := int(spec["rot"])
	return (spec["center"] as Vector3) + Basis(Vector3.UP, rot * PI * 0.5) * (local + Vector3(0, float(spec.get("raise", 0.0)), 0))


## World cell of a building's local cell (i, k) at height `y` (world).
static func cell_world(spec: Dictionary, i: int, k: int, y: int) -> Vector3i:
	var w := float(spec["w"])
	var d := float(spec["d"])
	var rot := int(spec["rot"])
	var local := Vector3(i + 0.5 - w * 0.5, 0.0, k + 0.5 - d * 0.5)
	var p := (spec["center"] as Vector3) + Basis(Vector3.UP, rot * PI * 0.5) * local
	return Vector3i(floori(p.x + 0.001), y, floori(p.z + 0.001))


static func _put(bp: Blueprint, world: Vector3i, block: int) -> void:
	var l := world - bp.origin
	bp.set_local(l.x, l.y, l.z, block)


## Collision: floor, walls with the doorway carved, rooms carved (or filled
## when the house can't be entered), the roof as a solid shell, furniture.
static func _collide(bp: Blueprint, spec: Dictionary, fy: int) -> void:
	var w: int = spec["w"]
	var d: int = spec["d"]
	var kind := String(spec["kind"])
	var raise := int(spec.get("raise", 0.0))
	var floor_y := fy + raise
	var wall_cells := ceili(float(spec["wall_h"]) - 0.05)
	var enterable: bool = spec["enterable"]
	var door: int = spec["door"]
	var door_w: int = spec["door_w"]
	var pitch := deg_to_rad(float(spec["pitch"]))
	var ridge_z := kind == "chapel"
	for k in d:
		for i in w:
			var edge := i == 0 or i == w - 1 or k == 0 or k == d - 1
			_put(bp, cell_world(spec, i, k, floor_y), Blocks.STRUCTURE)
			for y in range(1, raise + 1):
				_put(bp, cell_world(spec, i, k, fy + y), Blocks.STRUCTURE)
			# Height of the roof over this cell (from the floor top).
			var span_pos := float(i) + 0.5 - w * 0.5 if ridge_z else float(k) + 0.5 - d * 0.5
			var half := (w if ridge_z else d) * 0.5
			var roof_h := float(spec["wall_h"]) + (half - absf(span_pos) - 0.5) * tan(pitch)
			var top := floor_y + floori(roof_h)
			for y in range(floor_y + 1, top + 1):
				var block := Blocks.STRUCTURE
				if kind == "smithy":
					block = _smithy_cell(spec, i, k, y - floor_y)
				elif not edge and enterable and y < top:
					block = Blueprint.CARVE
				elif edge and y > floor_y + wall_cells and y < top and enterable:
					block = Blueprint.CARVE if not edge else Blocks.STRUCTURE
				_put(bp, cell_world(spec, i, k, y), block)
	# Doorway.
	if kind != "smithy":
		for i in range(door, door + door_w):
			for y in range(1, 3):
				_put(bp, cell_world(spec, i, d - 1, floor_y + y), Blueprint.CARVE if enterable else Blocks.STRUCTURE)
	# Furniture you bump into.
	if enterable:
		for f: Dictionary in spec.get("furniture", []):
			if not f.get("solid", true):
				continue
			var cell: Vector2i = f["cell"]
			var size: Vector2i = f.get("size", Vector2i.ONE)
			var h: int = f.get("height", 1)
			for dk in size.y:
				for di in size.x:
					for y in range(1, h + 1):
						_put(bp, cell_world(spec, cell.x + di, cell.y + dk, floor_y + y), Blocks.STRUCTURE)


## The smithy: solid back wall and posts, low side walls, open front and floor.
static func _smithy_cell(spec: Dictionary, i: int, k: int, y: int) -> int:
	var w: int = spec["w"]
	var d: int = spec["d"]
	var wall_cells := ceili(float(spec["wall_h"]) - 0.05)
	if y > wall_cells:
		return Blocks.STRUCTURE if (k == 0 or k == d - 1 or i == 0 or i == w - 1) else Blueprint.CARVE
	if k == 0:
		return Blocks.STRUCTURE
	if (i == 0 or i == w - 1) and k < d - 1:
		return Blocks.STRUCTURE if y <= 2 else Blueprint.CARVE
	if k == d - 1:
		var posts := [0, w / 3, w - 1 - w / 3, w - 1]
		return Blocks.STRUCTURE if i in posts else Blueprint.CARVE
	# The forge block against the back wall.
	if k <= 2 and i >= 1 and i <= 2:
		return Blocks.STRUCTURE if y <= 2 else Blueprint.CARVE
	return Blueprint.CARVE


## Furniture cells inside an enterable building (local cells). Keeps the
## doorway, the hearth and a walking line clear.
static func _furniture(spec: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	if not spec["enterable"]:
		return out
	var w: int = spec["w"]
	var d: int = spec["d"]
	var kind := String(spec["kind"])
	var door: int = spec["door"]
	var door_w: int = spec["door_w"]
	var chimney: int = spec["chimney"]
	var taken := {}
	# Doorway and the cells inside it.
	for i in range(door - 1, door + door_w + 1):
		for k in range(d - 3, d):
			taken[Vector2i(i, k)] = true
	if chimney != 0:
		var hi := 1 if chimney < 0 else w - 2
		var kc0 := (d - 1) / 2
		var kc1 := d / 2
		out.append({"kind": "hearth", "cell": Vector2i(hi, kc0), "size": Vector2i(1, kc1 - kc0 + 1), "height": 2})
		for k in range(kc0 - 1, kc1 + 2):
			taken[Vector2i(hi, k)] = true
			taken[Vector2i(hi - chimney, k)] = true
	var try_add := func(kind_name: String, cell: Vector2i, size: Vector2i, solid := true) -> bool:
		for dk in size.y:
			for di in size.x:
				var cc := cell + Vector2i(di, dk)
				if cc.x < 1 or cc.y < 1 or cc.x > w - 2 or cc.y > d - 2 or taken.has(cc):
					return false
		for dk in size.y:
			for di in size.x:
				taken[cell + Vector2i(di, dk)] = true
		out.append({"kind": kind_name, "cell": cell, "size": size, "solid": solid})
		return true
	match kind:
		"tavern":
			try_add.call("counter", Vector2i(w - 4 if chimney < 0 else 1, 1), Vector2i(3, 1))
			try_add.call("barrels", Vector2i(w - 2 if chimney < 0 else 1, 2), Vector2i(1, 1), false)
			for t in [Vector2i(2, 3), Vector2i(5, 3), Vector2i(3, 2), Vector2i(6, 2)]:
				try_add.call("table", t, Vector2i(2, 1))
		"longhouse":
			try_add.call("long_hearth", Vector2i(w / 2 - 2, d / 2 - 1 + (d % 2)), Vector2i(4, 1), true)
			try_add.call("high_seat", Vector2i(w / 2 - 1, 1), Vector2i(2, 1))
			try_add.call("table", Vector2i(1, d / 2 - 1), Vector2i(1, 2))
			try_add.call("table", Vector2i(w - 2, d / 2 - 1), Vector2i(1, 2))
			try_add.call("bed", Vector2i(1, 1), Vector2i(2, 1))
		"chapel", "smithy":
			pass
		_:
			var bed_i := w - 3 if chimney <= 0 else 1
			if not try_add.call("bed", Vector2i(bed_i, 1), Vector2i(2, 1)):
				try_add.call("bed", Vector2i(w - 3 if bed_i == 1 else 1, 1), Vector2i(2, 1))
			var placed := false
			for kk in range(d / 2 - 1, d - 2):
				for ii in range(1, w - 2):
					if not placed and try_add.call("table", Vector2i(ii, kk), Vector2i(2, 1)):
						placed = true
	return out


## Yard props around each building (world positions), with solid cells for the
## bulky ones. Every item: {prop, pos, yaw, ...}.
static func _plan_props(ctx: Dictionary, placed: Array) -> Array:
	var rng: RandomNumberGenerator = ctx["rng"]
	var rects: Array[Rect2] = ctx["rects"]
	var bp: Blueprint = ctx["bp"]
	var c: Vector2i = ctx["c"]
	var fy: int = ctx["fy"]
	var items: Array = []
	var try_item := func(item: Dictionary, half: Vector2, solid: bool) -> bool:
		var p: Vector3 = item["pos"]
		var off := Vector2(p.x - c.x, p.z - c.y)
		var r := Rect2(off - half, half * 2.0)
		if off.length() > 30.0:
			return false
		for other in rects:
			if r.intersects(other):
				return false
		rects.append(r)
		items.append(item)
		if solid:
			for z in range(floori(r.position.y + 0.2), ceili(r.end.y - 0.2)):
				for x in range(floori(r.position.x + 0.2), ceili(r.end.x - 0.2)):
					_put(bp, Vector3i(c.x + x, fy + 1, c.y + z), Blocks.STRUCTURE)
		return true
	for spec: Dictionary in placed:
		var w := float(spec["w"])
		var d := float(spec["d"])
		var rot := int(spec["rot"])
		var yaw := rot * PI * 0.5
		var kind := String(spec["kind"])
		var door_x := -w * 0.5 + float(spec["door"]) + float(spec["door_w"]) * 0.5
		var swap := rot % 2 == 1
		var hv := func(v: Vector2) -> Vector2: return Vector2(v.y, v.x) if swap else v
		if kind == "chapel":
			continue
		# Barrels by the door.
		var bx := door_x + (1.3 if door_x < 0.0 else -1.3)
		try_item.call({"prop": "barrels", "pos": to_world(spec, Vector3(bx, 0, d * 0.5 + 0.55)) - Vector3(0, float(spec["raise"]), 0), "yaw": yaw}, hv.call(Vector2(0.6, 0.5)), true)
		# Bench against the front wall.
		var bench_x := door_x + (-1.9 if door_x > -w * 0.5 + 2.5 else 2.0)
		if absf(bench_x) < w * 0.5 - 0.9 and kind != "smithy" and kind != "stilt":
			try_item.call({"prop": "bench", "pos": to_world(spec, Vector3(bench_x, 0, d * 0.5 + 0.35)), "yaw": yaw}, hv.call(Vector2(0.8, 0.2)), false)
		# Woodpile under the eaves of a gable.
		var gx := 1.0 if int(spec["chimney"]) <= 0 else -1.0
		try_item.call({"prop": "woodpile", "pos": to_world(spec, Vector3(gx * (w * 0.5 + 0.55), 0, -0.3)) - Vector3(0, float(spec["raise"]), 0), "yaw": yaw + PI * 0.5}, hv.call(Vector2(0.45, 0.85)), true)
		match kind:
			"smithy":
				try_item.call({"prop": "cart", "pos": to_world(spec, Vector3(w * 0.5 + 1.6, 0, d * 0.5 - 0.6)), "yaw": yaw + 0.25}, Vector2(1.3, 1.3), true)
				for k in 2:
					try_item.call({"prop": "hay", "pos": to_world(spec, Vector3(-w * 0.5 - 1.1, 0, -d * 0.5 + 1.0 + k * 1.3)), "yaw": yaw + PI * 0.5}, Vector2(0.7, 0.7), true)
			"tavern":
				try_item.call({"prop": "cart", "pos": to_world(spec, Vector3(-w * 0.5 - 1.8, 0, 0.5)), "yaw": yaw - 0.4}, Vector2(1.3, 1.3), true)
			_:
				if rng.randf() < 0.65:
					var gw := clampf(w - 1.5, 3.0, 5.0)
					var item := {"prop": "garden", "pos": to_world(spec, Vector3(0, 0, -d * 0.5 - 2.4)) - Vector3(0, float(spec["raise"]), 0), "yaw": yaw, "size": Vector2(gw, 3.0)}
					try_item.call(item, hv.call(Vector2(gw * 0.5 + 0.2, 1.7)), false)
				if rng.randf() < 0.5:
					try_item.call({"prop": "hay", "pos": to_world(spec, Vector3(-gx * (w * 0.5 + 1.0), 0, -d * 0.5 + 0.8)) - Vector3(0, float(spec["raise"]), 0), "yaw": yaw}, Vector2(0.7, 0.7), true)
	return items


## After every location is planned: paths from each door to the green and
## from the green out to where the roads stop, and the grass-free ground.
static func finish(locs: Array[Location], gen: WorldGen) -> void:
	var roads := LocationPlanner.roads(gen, locs)
	var dim := gen.dimension
	var seed_value := gen.world_seed
	for loc in locs:
		for p: Dictionary in loc.props:
			if p.get("type", "") != "site":
				continue
			var at: Vector3 = p["at"]
			match String(p["site"]):
				"shrine":
					ArchClearings.add_disc(dim, seed_value, Vector2(at.x, at.z), 3.6)
				"tower":
					ArchClearings.add_disc(dim, seed_value, Vector2(at.x, at.z), 4.3)
				"gateway":
					ArchClearings.add_rect(dim, seed_value, Rect2(at.x - 3.5, at.z - 1.2, 7.0, 3.6))
	for loc in locs:
		if loc.kind != Location.Kind.VILLAGE:
			continue
		var green: Dictionary = {}
		for p: Dictionary in loc.props:
			if p.get("type", "") == "green":
				green = p
		if green.is_empty():
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = int(green["seed"]) + 17
		var center: Vector3 = green["at"]
		var c2 := Vector2(center.x, center.z)
		var cell: Vector2i = green["c"]
		var rects: Array = green["rects"]
		var paths: Array = []
		for door: Vector3 in green["doors"]:
			var d := Vector2(door.x, door.z)
			var end := c2 + (d - c2).normalized() * 8.0
			var mid := (d + end) * 0.5 + Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
			paths.append([PackedVector2Array([d, mid, end]), 1.5])
		var ends: Array[Vector2] = []
		for e in road_ends(c2, roads):
			ends.append(e)
			var dir := (e - c2).normalized()
			var start := c2 + dir * 8.2
			var pts := PackedVector2Array([start])
			for i in range(1, 7):
				var q := start.lerp(e, float(i) / 6.0)
				var off := q - Vector2(cell)
				for r: Rect2 in rects:
					var g := r.grow(1.4)
					if g.has_point(off):
						var away := (off - g.get_center()).normalized()
						var push_by := 0.0
						while g.has_point(off + away * push_by) and push_by < 8.0:
							push_by += 0.5
						q += away * push_by
				pts.append(q)
			paths.append([pts, 2.0])
		green["paths"] = paths
		green["road_ends"] = ends
		var st: Dictionary = green["style"]
		if st.get("palisade", "") != "":
			_palisade(loc, gen, green, String(st["palisade"]), c2, ends)
		if st.get("stilts", false):
			_docks(loc, gen, green, c2, ends, dim, seed_value)
		ArchClearings.add_disc(dim, seed_value, c2, 9.2)
		for p: Array in paths:
			ArchClearings.add_path(dim, seed_value, p[0], float(p[1]) + 0.7)
		for p: Dictionary in loc.props:
			if p.get("type", "") == "building":
				var at: Vector3 = p["at"]
				var size: Vector3 = p["size"]
				var grow := 0.6 + (2.0 if float(p.get("raise", 0.0)) > 0.0 else 0.0)
				ArchClearings.add_rect(dim, seed_value, Rect2(at.x - size.x * 0.5, at.z - size.z * 0.5, size.x, size.z).grow(grow))
		for item: Dictionary in green.get("items", []):
			var ip: Vector3 = item["pos"]
			var radius := 2.4 if item["prop"] == "garden" else 1.0
			ArchClearings.add_disc(dim, seed_value, Vector2(ip.x, ip.z), radius)


## Where the roads serving the village at c2 leave its 43 m circle.
static func road_ends(c2: Vector2, roads: Array[PackedVector2Array]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for road in roads:
		for k in 2:
			var pts := road.duplicate()
			if k == 1:
				pts.reverse()
			if pts[0].distance_to(c2) > 2.0:
				continue
			var prev := pts[0]
			var hit := Vector2.INF
			for i in range(1, pts.size()):
				var q := pts[i]
				var steps := int(prev.distance_to(q))
				for s in steps:
					var r := prev.lerp(q, float(s) / maxf(1.0, steps))
					if r.distance_to(c2) > 43.0:
						hit = r
						break
				if hit != Vector2.INF:
					break
				prev = q
			if hit != Vector2.INF:
				out.append(hit)
	return out


const WALL_R := 31.0


## A ring of sharpened logs (or a drystone wall) with gates where the roads
## come in. Collision cells follow the ground of the pad's shoulder.
static func _palisade(loc: Location, gen: WorldGen, green: Dictionary, kind: String, c2: Vector2, ends: Array[Vector2]) -> void:
	var bp: Blueprint = loc.blueprints[0]
	var gates: Array[float] = []
	for e in ends:
		gates.append((e - c2).angle())
	if gates.is_empty():
		gates.append(0.0)
	var detail := gen.make_detail_noise()
	var ridge := gen.make_ridge_noise()
	var falloff := maxf(loc.pad_falloff * 1.8, 10.0)
	var steps := int(TAU * WALL_R / 0.5)
	var done := {}
	for i in steps:
		var a := TAU * i / steps
		var gate := false
		for ga in gates:
			if absf(angle_difference(a, ga)) * WALL_R < 2.6:
				gate = true
		if gate:
			continue
		var p := c2 + Vector2(cos(a), sin(a)) * WALL_R
		var cell := Vector2i(floori(p.x), floori(p.y))
		if done.has(cell):
			continue
		done[cell] = true
		var natural := gen.raw_height(cell.x, cell.y, detail, ridge)
		var w := 1.0 - smoothstep(loc.pad_radius, loc.pad_radius + falloff, Vector2(cell.x + 0.5, cell.y + 0.5).distance_to(c2))
		var h := lerpf(natural, float(loc.ground_y), w)
		var gy := int(floorf(h + 0.5))
		for y in range(gy + 1, gy + 4):
			_put(bp, Vector3i(cell.x, y, cell.y), Blocks.STRUCTURE)
	green["palisade"] = {"kind": kind, "r": WALL_R, "gates": gates}


## A boardwalk pier from the village out over the nearest open water.
static func _docks(loc: Location, gen: WorldGen, green: Dictionary, c2: Vector2, ends: Array[Vector2], dim: int, seed_value: int) -> void:
	var detail := gen.make_detail_noise()
	var ridge := gen.make_ridge_noise()
	var best_a := 0.0
	var best_r := INF
	for i in 24:
		var a := TAU * i / 24.0
		var blocked := false
		for e in ends:
			if absf(angle_difference(a, (e - c2).angle())) < 0.5:
				blocked = true
		if blocked:
			continue
		for r in range(30, 72, 2):
			var q := c2 + Vector2(cos(a), sin(a)) * r
			if gen.raw_height(int(q.x), int(q.y), detail, ridge) < WorldGen.SEA_LEVEL - 0.5:
				if r < best_r:
					best_r = r
					best_a = a
				break
	if best_r == INF:
		return
	var dir := Vector2(cos(best_a), sin(best_a))
	var start := c2 + dir * 24.0
	var end := c2 + dir * (best_r + 9.0)
	var deck_y := WorldGen.SEA_LEVEL + 1   # deck cells; their tops stand 1.5 m over the water
	var lo := Vector2(minf(start.x, end.x), minf(start.y, end.y)) - Vector2(4, 4)
	var hi := Vector2(maxf(start.x, end.x), maxf(start.y, end.y)) + Vector2(4, 4)
	var bp := Blueprint.new(Vector3i(floori(lo.x), deck_y - 1, floori(lo.y)), Vector3i(ceili(hi.x - lo.x) + 1, 6, ceili(hi.y - lo.y) + 1))
	loc.blueprints.append(bp)
	var n := int(start.distance_to(end) / 0.4)
	var side := Vector2(-dir.y, dir.x)
	for k in n + 1:
		var q := start.lerp(end, float(k) / n)
		for w: float in [-1.0, -0.4, 0.4, 1.0]:
			var c := q + side * w
			var cell := Vector3i(floori(c.x), deck_y, floori(c.y))
			var ground := gen.raw_height(cell.x, cell.z, detail, ridge)
			if ground < float(deck_y) - 0.2:
				var l := cell - bp.origin
				bp.set_local(l.x, l.y, l.z, Blocks.STRUCTURE)
	green["docks"] = {"start": start, "end": end, "deck": float(deck_y + 1)}
	ArchClearings.add_path(dim, seed_value, PackedVector2Array([start, end]), 3.0)
