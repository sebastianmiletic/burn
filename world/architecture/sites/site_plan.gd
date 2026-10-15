class_name SitePlan
extends RefCounted
## Plans the modelled non-village structures: collision (Blocks.STRUCTURE),
## spawns and the "site" props SiteMesh models later. Each site draws from its
## own random stream; callers replay the planner's legacy draws so every
## location planned afterwards keeps its place.


static func _bp(loc: Location, half: Vector3i, below: int, above: int) -> Blueprint:
	var c := Vector3i(loc.center.round())
	var bp := Blueprint.new(Vector3i(c.x - half.x, loc.ground_y - below, c.z - half.z), Vector3i(half.x * 2 + 1, below + above, half.z * 2 + 1))
	loc.blueprints.append(bp)
	return bp


static func _rng(loc: Location, salt := 0) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(String(loc.id)) ^ (salt * 7919)
	return r


static func _put(bp: Blueprint, world: Vector3i, block: int) -> void:
	var l := world - bp.origin
	bp.set_local(l.x, l.y, l.z, block)


static func _column(bp: Blueprint, x: int, z: int, y0: int, y1: int, block := Blocks.STRUCTURE) -> void:
	for y in range(y0, y1 + 1):
		_put(bp, Vector3i(x, y, z), block)


static func _site(loc: Location, site: String, extra := {}) -> Dictionary:
	var p := {"type": "site", "site": site, "material": "stone", "at": loc.center, "size": Vector3.ONE, "seed": hash(String(loc.id))}
	p.merge(extra, true)
	loc.props.append(p)
	return p


# --- Shrine ---------------------------------------------------------------------

## A paved ring of standing stones round the ember brazier.
static func shrine(loc: Location, clear_dim := 0, clear_seed := 0, register := false) -> void:
	loc.radius = 7.0
	loc.pad_radius = 5.5
	loc.pad_falloff = 5.0
	var bp := _bp(loc, Vector3i(6, 0, 6), 2, 8)
	var c := Vector3i(loc.center.round())
	var g := loc.ground_y
	var rng := _rng(loc)
	var stones: Array = []
	var n := 5
	var phase := rng.randf() * TAU
	for i in n:
		var a := phase + TAU * i / n + rng.randf_range(-0.12, 0.12)
		var p := Vector2(c.x + 0.5, c.z + 0.5) + Vector2(cos(a), sin(a)) * 4.3
		var cell := Vector2i(floori(p.x), floori(p.y))
		var h := rng.randf_range(2.3, 3.2)
		stones.append({"cell": cell, "pos": p, "h": h, "yaw": a, "lean": rng.randf_range(-0.06, 0.06)})
		_column(bp, cell.x, cell.y, g + 1, g + ceili(h))
	_site(loc, "shrine", {"at": Vector3(c.x + 0.5, g + 1, c.z + 0.5), "stones": stones})
	loc.add_spawn("shrine", Vector3(c.x + 0.5, g + 1, c.z + 0.5))
	if register:
		ArchClearings.add_disc(clear_dim, clear_seed, Vector2(c.x + 0.5, c.z + 0.5), 3.8)


# --- Watchtower -------------------------------------------------------------------

const TOWER_RING := [Vector2i(2, 0), Vector2i(2, 1), Vector2i(1, 2), Vector2i(0, 2), Vector2i(-1, 2), Vector2i(-2, 1),
	Vector2i(-2, 0), Vector2i(-2, -1), Vector2i(-1, -2), Vector2i(0, -2), Vector2i(1, -2), Vector2i(2, -1)]
const TOWER_STEPS := 14
const TOWER_FIRST := 2
const TOWER_LANDING := 10
const TOWER_TOP := 15


## A round stone watchtower with a spiral stair, a landing and a parapet.
static func tower(loc: Location) -> void:
	loc.radius = 9.0
	loc.pad_radius = 6.0
	loc.pad_falloff = 5.0
	var bp := _bp(loc, Vector3i(6, 0, 6), 3, 22)
	var c := Vector3i(loc.center.round())
	var g := loc.ground_y
	var rng := _rng(loc)
	# Stair cells: step k sits at height g + 1 + k.
	var steps := {}
	for k in TOWER_STEPS:
		var rc: Vector2i = TOWER_RING[(TOWER_FIRST + k) % TOWER_RING.size()]
		steps[k] = rc
	for dz in range(-4, 5):
		for dx in range(-4, 5):
			var d := Vector2(dx, dz).length()
			var x := c.x + dx
			var z := c.z + dz
			if d > 2.5 and d < 3.95:
				# Wall, with the doorway on the east side.
				for y in range(g, g + TOWER_TOP + 3):
					var door := dz == 0 and dx > 0 and y >= g + 1 and y <= g + 2
					_put(bp, Vector3i(x, y, z), Blueprint.CARVE if door else Blocks.STRUCTURE)
			elif d <= 2.5:
				_put(bp, Vector3i(x, g, z), Blocks.STRUCTURE)
				for y in range(g + 1, g + TOWER_TOP + 4):
					_put(bp, Vector3i(x, y, z), Blueprint.CARVE)
	for k: int in steps:
		var rc: Vector2i = steps[k]
		_column(bp, c.x + rc.x, c.z + rc.y, g + 1 + k, g + 1 + k)
	# Landing and the top platform, open above the steps that climb through them.
	for floor_k: int in [TOWER_LANDING, TOWER_TOP]:
		var fy := g + floor_k
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				if Vector2(dx, dz).length() > 2.5:
					continue
				var open := false
				for k: int in steps:
					var sy := g + 1 + k
					if steps[k] == Vector2i(dx, dz) and sy < fy and sy >= fy - 2:
						open = true
				if not open:
					_put(bp, Vector3i(c.x + dx, fy, c.z + dz), Blocks.STRUCTURE)
	_site(loc, "tower", {"at": Vector3(c.x + 0.5, g + 1, c.z + 0.5), "broken": rng.randf() * TAU, "ruin": rng.randf_range(0.3, 1.0)})
	var top := Vector3(c.x + 0.5, g + TOWER_TOP + 1, c.z + 0.5)
	loc.add_spawn("enemy", top + Vector3(-1.0, 0, -1.0), {"kind": "archer"})
	loc.add_spawn("enemy", Vector3(c.x + 6.5, g + 1, c.z + 0.5), {"kind": "skeleton"})
	loc.add_spawn("chest", Vector3(c.x + 0.5, g + TOWER_LANDING + 1, c.z + 0.5), {"tier": 1})


# --- Ruins ------------------------------------------------------------------------

## Ruins by name: a fallen chapel, an aqueduct, a manor, a cairn or barrow, a
## burnt mill, a forgotten colonnade, a stone circle, an old battlefield.
static func ruin(loc: Location) -> void:
	loc.radius = 14.0
	loc.pad_radius = 10.0
	loc.pad_falloff = 6.0
	var bp := _bp(loc, Vector3i(12, 0, 12), 3, 14)
	var c := Vector3i(loc.center.round())
	var g := loc.ground_y
	var rng := _rng(loc)
	var name := loc.name.to_lower()
	var style := "circle"
	for key: String in ["chapel", "aqueduct", "manor", "cairn", "mill", "shrine", "barrow", "stones", "battlefield", "ring"]:
		if name.contains(key):
			style = key
	if style == "barrow":
		style = "cairn"
	if style == "ring" or style == "stones":
		style = "circle"
	var pieces: Array = []   # {kind, pos (world), size, yaw, h}
	var keep_free := [Vector2i(c.x, c.z), Vector2i(c.x, c.z - 3), Vector2i(c.x + 3, c.z + 2)]
	var solid := func(cell: Vector2i, h: int) -> void:
		if cell in keep_free:
			return
		_column(bp, cell.x, cell.y, g + 1, g + h)
	match style:
		"chapel", "manor":
			var w := 7 if style == "chapel" else 9
			var d := 11 if style == "chapel" else 7
			var x0 := c.x - w / 2
			var z0 := c.z - d / 2
			for k in d:
				for i in w:
					var edge := i == 0 or i == w - 1 or k == 0 or k == d - 1
					if not edge:
						continue
					var door := (k == d - 1 and absi(i - w / 2) <= (1 if style == "chapel" else 0))
					if door:
						continue
					# Broken wall height: high near the gable, crumbling elsewhere.
					var h := 1 + int(absf(sin(float(i * 3 + k * 7) + rng.randf())) * (5.0 if style == "chapel" else 3.5))
					if style == "chapel" and k == 0:
						h = 7
					if rng.randf() < 0.18:
						h = 1
					var cell := Vector2i(x0 + i, z0 + k)
					solid.call(cell, h)
					pieces.append({"kind": "wall", "cell": cell, "h": h, "edge": [i == 0, i == w - 1, k == 0, k == d - 1]})
			pieces.append({"kind": "frame", "x0": x0, "z0": z0, "w": w, "d": d})
		"aqueduct":
			var along_x := rng.randf() < 0.5
			for i in 6:
				var o := -10 + i * 4
				var cell := Vector2i(c.x + o, c.z) if along_x else Vector2i(c.x, c.z + o)
				var broken := i == 2 or (i == 4 and rng.randf() < 0.5)
				var h := 3 if broken else 7
				solid.call(cell, h)
				pieces.append({"kind": "pier", "cell": cell, "h": h, "along_x": along_x, "broken": broken, "i": i})
		"cairn":
			for i in 10:
				var a := TAU * i / 10.0
				var cell := Vector2i(c.x + roundi(cos(a) * 7.0), c.z + roundi(sin(a) * 7.0))
				solid.call(cell, 1)
				pieces.append({"kind": "kerb", "cell": cell, "a": a})
			for cell: Vector2i in [Vector2i(c.x - 1, c.z - 5), Vector2i(c.x + 1, c.z - 5), Vector2i(c.x, c.z - 6)]:
				solid.call(cell, 2)
			pieces.append({"kind": "dolmen", "cell": Vector2i(c.x, c.z - 5)})
			pieces.append({"kind": "heap", "cell": Vector2i(c.x + 4, c.z + 4)})
			solid.call(Vector2i(c.x + 4, c.z + 4), 1)
		"mill":
			var x0 := c.x - 3
			var z0 := c.z - 3
			for k in 7:
				for i in 7:
					if i == 0 or i == 6 or k == 0 or k == 6:
						if k == 6 and i == 3:
							continue
						solid.call(Vector2i(x0 + i, z0 + k), 2)
			pieces.append({"kind": "mill", "x0": x0, "z0": z0})
		"shrine":
			for i in 8:
				var a := TAU * i / 8.0
				var cell := Vector2i(c.x + roundi(cos(a) * 6.0), c.z + roundi(sin(a) * 6.0))
				var broken := rng.randf() < 0.45
				solid.call(cell, 2 if broken else 5)
				pieces.append({"kind": "column", "cell": cell, "broken": broken, "a": a})
			solid.call(Vector2i(c.x, c.z + 2), 1)
			pieces.append({"kind": "altar", "cell": Vector2i(c.x, c.z + 2)})
		"battlefield":
			for i in 14:
				var a := rng.randf() * TAU
				var r := rng.randf_range(6.0, 11.0)
				pieces.append({"kind": "stake", "pos": Vector2(c.x + 0.5 + cos(a) * r, c.z + 0.5 + sin(a) * r), "lean": rng.randf_range(-0.4, 0.4), "yaw": rng.randf() * TAU})
			for i in 3:
				var a := rng.randf() * TAU
				var cell := Vector2i(c.x + roundi(cos(a) * 5.0), c.z + roundi(sin(a) * 5.0))
				solid.call(cell, 1)
				pieces.append({"kind": "barrow_cairn", "cell": cell})
			pieces.append({"kind": "wagon", "pos": Vector2(c.x - 4.5, c.z + 5.5), "yaw": rng.randf() * TAU})
		_:
			var n := 11
			for i in n:
				var a := TAU * i / n + rng.randf_range(-0.1, 0.1)
				var cell := Vector2i(c.x + roundi(cos(a) * 8.0), c.z + roundi(sin(a) * 8.0))
				var fallen := rng.randf() < 0.22
				if not fallen:
					solid.call(cell, 3)
				pieces.append({"kind": "menhir", "cell": cell, "fallen": fallen, "a": a, "h": rng.randf_range(2.2, 3.4)})
			pieces.append({"kind": "altar", "cell": Vector2i(c.x, c.z + 2)})
			solid.call(Vector2i(c.x, c.z + 2), 1)
	_site(loc, "ruin", {"style": style, "pieces": pieces, "at": Vector3(c.x + 0.5, g + 1, c.z + 0.5)})
	loc.add_spawn("enemy", Vector3(c.x + 0.5, g + 1, c.z - 2.5), {"kind": "skeleton"})
	loc.add_spawn("enemy", Vector3(c.x + 3.5, g + 1, c.z + 2.5), {"kind": "ghoul"})


# --- Crater and Asphodel -------------------------------------------------------------

## Basalt organ-pipe columns round a carved obelisk on the crater floor.
static func crater_marker(loc: Location) -> void:
	var bp := _bp(loc, Vector3i(40, 0, 40), 2, 14)
	var c := Vector3i(loc.center.round())
	var g := loc.ground_y
	var rng := _rng(loc)
	var clusters: Array = []
	for i in 9:
		var a := TAU * i / 9.0 + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(12.0, 30.0)
		var cell := Vector2i(c.x + roundi(cos(a) * r), c.z + roundi(sin(a) * r))
		var h := rng.randf_range(3.0, 10.0)
		var rad := rng.randf_range(0.9, 1.8)
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				if Vector2(dx, dz).length() <= rad:
					_column(bp, cell.x + dx, cell.y + dz, g + 1, g + floori(h * 0.8))
		clusters.append({"cell": cell, "h": h, "r": rad})
	_column(bp, c.x, c.z, g + 1, g + 4)
	_site(loc, "crater", {"at": Vector3(c.x + 0.5, g + 1, c.z + 0.5), "clusters": clusters})
	loc.add_spawn("lore", Vector3(c.x + 0.5, g + 1, c.z + 2.5), {"text": "crater"})


## Asphodel Fields: a ring of basalt flagstones, the obsidian gate home and
## bone braziers.
static func hell_spawn(loc: Location) -> void:
	loc.pad_radius = 16.0
	loc.pad_falloff = 10.0
	var bp := _bp(loc, Vector3i(14, 0, 14), 3, 20)
	var c := Vector3i(loc.center.round())
	var g := loc.ground_y
	# Gate pillars.
	for side: int in [-1, 1]:
		for dz in range(-8, -6):
			_column(bp, c.x + side * 5, c.z + dz, g + 1, g + 13)
	var braziers: Array = []
	for i in 8:
		var a := TAU * i / 8.0
		var cell := Vector2i(c.x + roundi(cos(a) * 8.0), c.z + roundi(sin(a) * 8.0))
		if cell.y < c.z - 5 and absi(cell.x - c.x) < 6:
			continue
		_column(bp, cell.x, cell.y, g + 1, g + 2)
		braziers.append(cell)
	_site(loc, "asphodel", {"at": Vector3(c.x + 0.5, g + 1, c.z + 0.5), "braziers": braziers})
	loc.add_spawn("portal", Vector3(c.x + 0.5, g + 1, c.z - 6.5), {"to": 0, "size": Vector2(8, 12)})
	loc.add_spawn("shrine", Vector3(c.x + 0.5, g + 1, c.z + 4.5))
