class_name AdventureSites
extends RefCounted
## Places of world revision 5 (planned after everything else, with their own
## random stream, so older places keep theirs):
##
##   mount_pyrrhos     Mount Pyrrhos: the volcano, the Fire Road gate, the altar
##                     of the Emberheart on its island in the lava lake.
##   fire_village      Kilnhollow, the village of the Pyrrhai (the Fire People)
##                     on the caldera floor: obsidian hearth-domes, the
##                     Ember-Mother's hall, a lava forge.
##   atlantis          Atlantis at the bottom of the Abyssal Trench: the sealed
##                     Tide Gate, the air-filled vestibule and treasury, the
##                     drowned avenue and colonnades.
##   atlantis_throne   the Kraken's Throne: the great air dome over the moon pool
##                     where the Abyssal Kraken now lives (revision 5 moves it
##                     from the Kraken's Graveyard).
##   scumport          Scumport, the smugglers' harbour on its own isle.
##   scumport_cove     the Cutthroat Cove on the far side of that isle.
##   stormbreak        Stormbreak Light, a lighthouse on a storm-wracked crag.
##   hollow_crowns     the Isle of Hollow Crowns and the Mirror of Stars on its
##                     summit, the way into the Celestial Prison (dimension 4).
##
## Each place sets the meta `map_kind` (for the map's icon registry) and, where
## the adventure director spawns its own things, `adv` (a Dictionary).

const S := Blocks.STRUCTURE
const SEA := WorldGen.SEA_LEVEL


static func plan(planner: LocationPlanner, existing: Array[Location]) -> Array[Location]:
	var out: Array[Location] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = planner.gen.world_seed * 9973 + 501
	out.append_array(_volcano(planner, rng))
	out.append_array(_atlantis(planner, rng))
	out.append_array(_scumport(planner, rng))
	out.append(_stormbreak(planner, rng))
	out.append(_hollow_crowns(planner, rng))
	for loc in out:
		loc.dimension = 0
	return out


static func _g(planner: LocationPlanner, x: float, z: float) -> int:
	return planner._ground(x, z)


static func _put(bp: Blueprint, w: Vector3i, block: int) -> void:
	var l := w - bp.origin
	bp.set_local(l.x, l.y, l.z, block)


static func _xz(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


## A round hut: levelled floor, a wall ring with a doorway towards `door_dir`,
## the room carved, a flat roof collision under the modelled dome.
static func _round_hut(bp: Blueprint, c: Vector2, fy: int, r: float, h: int, door_dir: Vector2) -> void:
	var ri := int(ceilf(r)) + 1
	for dz in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var q := Vector2(dx + 0.5, dz + 0.5)
			var d := q.length()
			if d > r + 0.3:
				continue
			var wx := floori(c.x) + dx
			var wz := floori(c.y) + dz
			for y in range(fy - 3, fy + 1):
				_put(bp, Vector3i(wx, y, wz), S)
			var door := q.normalized().dot(door_dir) > 0.86 and d > r - 1.6
			for y in range(fy + 1, fy + h + 1):
				if d > r - 0.9 and not (door and y <= fy + 3):
					_put(bp, Vector3i(wx, y, wz), S)
				else:
					_put(bp, Vector3i(wx, y, wz), Blueprint.CARVE)
			_put(bp, Vector3i(wx, fy + h + 1, wz), S if d < r - 0.4 else Blueprint.CARVE)
			for y in range(fy + h + 2, fy + h + 5):
				_put(bp, Vector3i(wx, y, wz), Blueprint.CARVE)


# --- Mount Pyrrhos and Kilnhollow --------------------------------------------------------

static func _volcano(planner: LocationPlanner, rng: RandomNumberGenerator) -> Array[Location]:
	var V := AdventureTerrain.V
	var na := AdventureTerrain.notch_angle()
	var notch := AdventureTerrain.NOTCH
	var floor_ref := V + notch.rotated(PI) * 70.0
	var fy0 := _g(planner, floor_ref.x, floor_ref.y)
	var isle_y := _g(planner, V.x, V.y)
	var volcano := Location.new(&"mount_pyrrhos", "Mount Pyrrhos", Location.Kind.RUIN, Vector3(V.x, fy0 + 1, V.y))
	volcano.radius = AdventureTerrain.RC
	volcano.major = true
	volcano.set_meta(&"map_kind", "volcano")
	var village := Location.new(&"fire_village", "Kilnhollow", Location.Kind.RUIN, Vector3.ZERO)
	village.major = true
	village.set_meta(&"map_kind", "fire_village")
	var hall_at := V + AdventureTerrain.dir(na + 0.62) * 84.0
	village.center = Vector3(hall_at.x, _g(planner, hall_at.x, hall_at.y) + 1, hall_at.y)
	village.ground_y = int(village.center.y) - 1
	village.radius = 48.0
	var rc := AdventureTerrain.RC
	var bp := Blueprint.new(Vector3i(floori(V.x - rc), fy0 - 30, floori(V.y - rc)), Vector3i(int(rc * 2.0) + 2, 70, int(rc * 2.0) + 2))
	volcano.blueprints.append(bp)
	# Keep clear of the Fire Road, the causeway, the lava rivers and the waterfall's stream.
	var avoid: Array[float] = [na, na + float(AdventureTerrain.WATERFALL)]
	for fa: float in AdventureTerrain.FALLS:
		avoid.append(na + fa)
	var huts: Array = []
	var folk: Array = []
	# The Ember-Mother's hall and the forge, then the hearth-domes round the lake.
	var hall_fy := _g(planner, hall_at.x, hall_at.y)
	_round_hut(bp, hall_at, hall_fy, 7.0, 5, (V - hall_at).normalized())
	huts.append({"at": _xz(hall_at, hall_fy + 1), "r": 7.0, "h": 5.0, "door": (V - hall_at).normalized(), "kind": "hall"})
	folk.append({"pos": _xz(hall_at + (V - hall_at).normalized() * 9.0, hall_fy + 1), "role": "chief", "seed": 1})
	var forge_at := V + AdventureTerrain.dir(na - 0.62) * 80.0
	var forge_fy := _g(planner, forge_at.x, forge_at.y)
	huts.append({"at": _xz(forge_at, forge_fy + 1), "r": 4.5, "h": 3.0, "door": (V - forge_at).normalized(), "kind": "forge"})
	for dz in range(-4, 5):
		for dx in range(-4, 5):
			if Vector2(dx, dz).length() < 4.6:
				for y in range(forge_fy - 3, forge_fy + 1):
					_put(bp, Vector3i(floori(forge_at.x) + dx, y, floori(forge_at.y) + dz), S)
				for y in range(forge_fy + 1, forge_fy + 5):
					_put(bp, Vector3i(floori(forge_at.x) + dx, y, floori(forge_at.y) + dz), Blueprint.CARVE)
	for y in range(forge_fy + 1, forge_fy + 3):
		_put(bp, Vector3i(floori(forge_at.x), y, floori(forge_at.y)), S)  # the forge's hearth stone
	folk.append({"pos": _xz(forge_at + (V - forge_at).normalized() * 3.0, forge_fy + 1), "role": "smith", "seed": 2})
	var placed: Array[Vector2] = [hall_at, forge_at]
	var count := 0
	for attempt in 80:
		if count >= 14:
			break
		var a := na + rng.randf() * TAU
		var r := rng.randf_range(58.0, 104.0)
		var ok := true
		for av: float in avoid:
			if absf(angle_difference(a, av)) * r < 13.0:
				ok = false
		var p := V + AdventureTerrain.dir(a) * r
		for q: Vector2 in placed:
			if q.distance_to(p) < 15.0:
				ok = false
		if not ok:
			continue
		placed.append(p)
		var fy := _g(planner, p.x, p.y)
		var hr := rng.randf_range(3.2, 4.2)
		var door := (V - p).normalized()
		_round_hut(bp, p, fy, hr, 3, door)
		huts.append({"at": _xz(p, fy + 1), "r": hr, "h": 3.0, "door": door, "kind": "hut", "seed": rng.randi()})
		folk.append({"pos": _xz(p + door * (hr + 1.8), fy + 1), "role": "villager", "seed": 10 + count})
		count += 1
	# Guards at the causeway and the top of the Fire Road; the keeper of the altar.
	var cause_end := V + notch * (AdventureTerrain.LAKE_R + 6.0)
	for s: float in [-1.0, 1.0]:
		var gp := cause_end + Vector2(-notch.y, notch.x) * 3.5 * s
		folk.append({"pos": _xz(gp, _g(planner, gp.x, gp.y) + 1), "role": "guard", "seed": 40 + int(s)})
		var rp := V + notch * (rc * 0.86) + Vector2(-notch.y, notch.x) * 6.0 * s
		folk.append({"pos": _xz(rp, _g(planner, rp.x, rp.y) + 1), "role": "guard", "seed": 50 + int(s)})
	var keeper := V + notch * (AdventureTerrain.LAKE_R + 10.0) + Vector2(-notch.y, notch.x) * 7.0
	folk.append({"pos": _xz(keeper, _g(planner, keeper.x, keeper.y) + 1), "role": "keeper", "seed": 60})
	# The altar on the island: a cracked stone, the sword lodged in it.
	var altar := Vector3(V.x, isle_y + 1, V.y)
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			_put(bp, Vector3i(floori(V.x) + dx, isle_y, floori(V.y) + dz), S)
	_put(bp, Vector3i(floori(V.x), isle_y + 1, floori(V.y)), S)
	var gate_at := V + notch * (rc * 1.0)
	var gate_y := _g(planner, gate_at.x, gate_at.y)
	for s: float in [-1.0, 1.0]:
		var pp := gate_at + Vector2(-notch.y, notch.x) * 7.0 * s
		for y in range(gate_y + 1, gate_y + 12):
			_put(bp, Vector3i(floori(pp.x), y, floori(pp.y)), S)
	volcano.props.append({"type": "builder", "builder": Callable(AdventureArch, "pyrrhos"), "altar": altar, "gate": _xz(gate_at, gate_y + 1),
			"notch": notch, "lake": AdventureTerrain.LAKE_R, "v": V, "seed": rng.randi()})
	village.props.append({"type": "builder", "builder": Callable(AdventureArch, "kilnhollow"), "huts": huts, "seed": rng.randi()})
	volcano.set_meta(&"adv", {"altar": altar, "gate": _xz(gate_at, gate_y + 1), "floor_y": float(fy0 + 1)})
	village.set_meta(&"adv", {"fire_folk": folk})
	return [volcano, village]


# --- Atlantis ---------------------------------------------------------------------------------

static func _atlantis(planner: LocationPlanner, rng: RandomNumberGenerator) -> Array[Location]:
	var A := AdventureTerrain.ATLANTIS
	var fy := _g(planner, A.x, A.y)
	# The approach comes from up the trench (north-west).
	var g := (Vector2(3800, 2850) - A).normalized()
	var side := Vector2(-g.y, g.x)
	var vest := A + g * 56.0
	var treasury := vest + side * 16.0
	var gate := A + g * 65.0
	var half := 140
	var bp := Blueprint.new(Vector3i(floori(A.x) - half, fy - 12, floori(A.y) - half), Vector3i(half * 2 + 1, 56, half * 2 + 1))
	var c3 := Vector3(A.x, fy + 1, A.y)
	# The great dome over the moon pool.
	_dome(bp, A, fy, 30.0, 26.0)
	var pool := 9.0
	for dz in range(-10, 11):
		for dx in range(-10, 11):
			var d := Vector2(dx + 0.5, dz + 0.5).length()
			if d < pool:
				for y in range(fy - 9, fy + 1):
					_put(bp, Vector3i(floori(A.x) + dx, y, floori(A.y) + dz), Blocks.WATER)
				_put(bp, Vector3i(floori(A.x) + dx, fy - 10, floori(A.y) + dz), S)
			elif d < pool + 1.2:
				for y in range(fy - 10, fy + 1):
					_put(bp, Vector3i(floori(A.x) + dx, y, floori(A.y) + dz), S)
	# The vestibule behind the Tide Gate and the treasury beside it.
	_dome(bp, vest, fy, 10.0, 9.0)
	_dome(bp, treasury, fy, 6.5, 6.0)
	_corridor(bp, A + g * 27.0, vest - g * 7.0, fy, 2.2, 5)
	_corridor(bp, vest + side * 7.0, treasury - side * 4.0, fy, 1.8, 4)
	# The Tide Gate: a doorway in the vestibule's outer wall, sealed until the Tidestone opens it.
	var gate_cells: Array = []
	for depth: float in [8.2, 9.0, 9.8, 10.6]:
		for k in range(-1, 2):
			var p := vest + g * depth + side * k
			for y in range(fy + 1, fy + 5):
				var cell := Vector3i(floori(p.x), y, floori(p.y))
				if not cell in gate_cells:
					_put(bp, cell, S)
					gate_cells.append(cell)
	# Columns of the drowned city (solid), in rings and down the processional avenue.
	var columns: Array = []
	for ring: Array in [[42.0, 16], [78.0, 22]]:
		for i in int(ring[1]):
			var a := TAU * float(i) / float(ring[1]) + float(ring[0]) * 0.01
			var p := A + AdventureTerrain.dir(a) * float(ring[0])
			if absf(angle_difference(a, g.angle())) < 0.35 or (float(ring[0]) < 50.0 and absf(angle_difference(a, side.angle())) < 0.3):
				continue
			var h := rng.randi_range(4, 14) if rng.randf() < 0.4 else 14
			columns.append([_xz(p, fy + 1), float(h)])
	for k in 7:
		for s: float in [-1.0, 1.0]:
			var p := gate + g * (8.0 + k * 10.0) + side * 7.0 * s
			var h := 12 if k % 3 != 2 else rng.randi_range(3, 8)
			columns.append([_xz(p, _g(planner, p.x, p.y) + 1), float(h)])
	for col: Array in columns:
		var p: Vector3 = col[0]
		for y in range(int(p.y), int(p.y) + int(col[1])):
			_put(bp, Vector3i(floori(p.x), y, floori(p.z)), S)
	# Ruined halls round the city (half-domes, water-filled): visual + low wall collision.
	var ruins: Array = []
	for i in 6:
		var a := g.angle() + PI * 0.35 + TAU * float(i) / 7.0
		var p := A + AdventureTerrain.dir(a) * rng.randf_range(95.0, 120.0)
		ruins.append({"at": _xz(p, _g(planner, p.x, p.y) + 1), "r": rng.randf_range(7.0, 11.0), "broken": rng.randf_range(0.3, 0.7), "yaw": rng.randf() * TAU})
	var atl := Location.new(&"atlantis", "Atlantis", Location.Kind.RUIN, _xz(vest, fy + 1))
	atl.radius = 120.0
	atl.half_height = 70.0
	atl.major = true
	atl.set_meta(&"map_kind", "atlantis")
	atl.blueprints.append(bp)
	atl.props.append({"type": "builder", "builder": Callable(AdventureArch, "atlantis"), "center": c3, "g": g, "vest": _xz(vest, fy + 1),
			"treasury": _xz(treasury, fy + 1), "gate": _xz(gate, fy + 1), "columns": columns, "ruins": ruins, "pool": pool, "seed": rng.randi()})
	atl.add_spawn("chest", _xz(treasury + side * 2.5, fy + 1), {"tier": 3})
	atl.add_spawn("chest", _xz(treasury + side * 2.5 + g * 2.4, fy + 1), {"tier": 3})
	# The guarded approach: sharks and a serpent in the trench, drowned thralls on the avenue.
	for k in 3:
		var p := gate + g * (25.0 + k * 22.0) + side * (k - 1) * 9.0
		atl.add_spawn("enemy", _xz(p, fy + 8 + k * 4), {"kind": "shark"})
	atl.add_spawn("enemy", _xz(gate + g * 60.0, fy + 20), {"kind": "sea_serpent"})
	for k in 4:
		var p := gate + g * (6.0 + k * 9.0) + side * (3.0 if k % 2 == 0 else -3.0)
		atl.add_spawn("enemy", _xz(p, _g(planner, p.x, p.y) + 1), {"kind": "drowned"})
	atl.set_meta(&"adv", {"gate": _xz(gate - g * 0.6, fy + 1), "gate_cells": gate_cells, "g": g, "center": c3})
	# The throne: the boss's own place under the great dome.
	var throne := Location.new(&"atlantis_throne", "The Kraken's Throne", Location.Kind.RUIN, c3)
	throne.radius = 30.0
	throne.half_height = 26.0
	throne.major = true
	throne.set_meta(&"map_kind", "atlantis")
	throne.add_spawn("boss", c3, {"kind": "kraken"})
	return [atl, throne]


## A hemispherical air hall: solid floor and shell, air inside.
static func _dome(bp: Blueprint, c: Vector2, fy: int, r: float, h: float) -> void:
	var ri := int(ceilf(r)) + 1
	for dz in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var q := Vector2(dx + 0.5, dz + 0.5)
			var d := q.length()
			if d > r + 0.5:
				continue
			var wx := floori(c.x) + dx
			var wz := floori(c.y) + dz
			for y in range(fy - 3, fy + 1):
				_put(bp, Vector3i(wx, y, wz), S)
			for yy in range(0, int(h) + 2):
				var e := Vector2(d / r, float(yy) / h).length()
				var cell := Vector3i(wx, fy + 1 + yy, wz)
				if e <= 1.0 - 1.4 / r:
					_put(bp, cell, Blueprint.CARVE)
				elif e <= 1.0 + 0.6 / r:
					_put(bp, cell, S)


## A straight air passage (floor, walls, vault) between two points.
static func _corridor(bp: Blueprint, a: Vector2, b: Vector2, fy: int, half_w: float, h: int) -> void:
	var ab := b - a
	var length := ab.length()
	var u := ab / length
	var n := Vector2(-u.y, u.x)
	var steps := int(length) + 1
	for s in steps + 1:
		for k in range(-int(half_w) - 2, int(half_w) + 3):
			var p := a + u * float(s) + n * float(k) * 0.9
			var cell := Vector2i(floori(p.x), floori(p.y))
			var across := absf(float(k) * 0.9)
			for y in range(fy - 2, fy + h + 2):
				var w := Vector3i(cell.x, y, cell.y)
				if y <= fy:
					_put(bp, w, S)
				elif across < half_w and y <= fy + h:
					if bp.get_local(w.x - bp.origin.x, w.y - bp.origin.y, w.z - bp.origin.z) != Blueprint.CARVE:
						_put(bp, w, Blueprint.CARVE)
				elif bp.get_local(w.x - bp.origin.x, w.y - bp.origin.y, w.z - bp.origin.z) != Blueprint.CARVE:
					_put(bp, w, S)


# --- Scumport ------------------------------------------------------------------------------

const SCUM_STYLE := {
	"name": "scum", "walls": "boards", "roofs": ["shingle", "shingle", "thatch"],
	"plaster": [Color(0.55, 0.5, 0.42), Color(0.48, 0.44, 0.4)],
	"timber": Color(0.28, 0.22, 0.17), "stone": Color(0.42, 0.42, 0.4), "roof_tint": Color(0.42, 0.4, 0.36),
	"shutters": [Color(0.3, 0.16, 0.12), Color(0.18, 0.24, 0.22)],
	"door": Color(0.28, 0.2, 0.15), "banner": Color(0.4, 0.12, 0.14), "sign": Color(0.7, 0.5, 0.2),
	"wear": 1.0, "snow": 0.0, "stone_ratio": 0.0, "tavern": "The Drowned Rat", "chapel": false, "fence": "wattle",
	"stilts": true, "flowers": 0.0,
}


static func _scumport(planner: LocationPlanner, rng: RandomNumberGenerator) -> Array[Location]:
	var isle: Array = AdventureTerrain.ISLES["scumport"]
	var C: Vector2 = isle[0]
	# The harbour faces the mainland (west): walk out until the ground meets the sea.
	var west := Vector2(-1, 0)
	var shore := C
	for i in 60:
		var q := C + west * (i * 3.0)
		if _g(planner, q.x, q.y) <= SEA + 1:
			shore = q
			break
	var T := shore - west * 30.0
	var fy := SEA + 3
	var loc := Location.new(&"scumport", "Scumport", Location.Kind.RUIN, Vector3(T.x, fy + 1, T.y))
	loc.ground_y = fy
	loc.radius = 46.0
	loc.pad_radius = 24.0
	loc.pad_falloff = 10.0
	loc.major = true
	loc.set_meta(&"map_kind", "scumport")
	var bp := Blueprint.new(Vector3i(floori(T.x) - 80, fy - 12, floori(T.y) - 46), Vector3i(130, 40, 93))
	loc.blueprints.append(bp)
	var ctx := {"loc": loc, "bp": bp, "rng": rng, "style": SCUM_STYLE, "rects": [] as Array[Rect2],
			"c": Vector2i(roundi(T.x), roundi(T.y)), "fy": fy}
	# The square in the middle, buildings round it; stilt shacks over the water on the piers.
	var list := [
		[{"role": "tavern", "kind": "tavern", "w": 9, "d": 7, "enterable": true}, Rect2(4, -16, 9, 7), 3],
		[{"role": "hall", "kind": "stilt", "w": 8, "d": 6, "enterable": true}, Rect2(-6, -17, 8, 6), 2],
		[{"role": "house", "kind": "stilt", "w": 6, "d": 5, "enterable": true}, Rect2(12, -2, 6, 5), 3],
		[{"role": "house", "kind": "stilt", "w": 6, "d": 5, "enterable": false}, Rect2(12, 7, 6, 5), 3],
		[{"role": "house", "kind": "stilt", "w": 7, "d": 5, "enterable": true}, Rect2(2, 11, 7, 5), 0],
		[{"role": "house", "kind": "stilt", "w": 6, "d": 5, "enterable": false}, Rect2(-8, 11, 6, 5), 0],
		[{"role": "smithy", "kind": "smithy", "w": 8, "d": 6, "enterable": true}, Rect2(-19, 8, 8, 6), 1],
	]
	var placed: Array = []
	for it: Array in list:
		placed.append(VillagePlan._commit(ctx, it[0], it[1], it[2]))
	# Piers out into the harbour on stilts, shacks along them.
	var piers: Array = []
	var deck := SEA + 2
	for k in 3:
		var start := shore + west * -4.0 + Vector2(0, (k - 1) * 18.0)
		var length := 34.0 if k == 1 else 24.0
		var p0 := start
		var p1 := start + west * length
		piers.append([_xz(p0, deck + 1), _xz(p1, deck + 1)])
		for s in int(length) + 1:
			var p := p0 + west * s
			for w in range(-1, 2):
				var cell := Vector3i(floori(p.x), deck, floori(p.y) + w)
				_put(bp, cell, S)
				for y in range(deck + 1, deck + 5):
					_put(bp, Vector3i(cell.x, y, cell.z), Blueprint.CARVE)
		if k != 1:
			var sc := p1 + west * 0.0 + Vector2(0, -6.0 if k == 0 else 6.0)
			var shack_ctx := ctx.duplicate()
			shack_ctx["fy"] = deck
			var rel := Rect2(sc.x - T.x - 3.0, sc.y - T.y - 2.5, 6, 5)
			placed.append(VillagePlan._commit(shack_ctx, {"role": "house", "kind": "stilt", "w": 6, "d": 5, "enterable": k == 0}, rel, 0 if k == 2 else 2))
	# Lanterns on poles along the piers and round the square.
	var lamps: Array = []
	for pr: Array in piers:
		var a: Vector3 = pr[0]
		var b: Vector3 = pr[1]
		for s in 4:
			lamps.append(a.lerp(b, (s + 0.5) / 4.0) + Vector3(0, 0, 1.6 if s % 2 == 0 else -1.6))
	for i in 6:
		var a := TAU * i / 6.0 + 0.3
		lamps.append(Vector3(T.x + cos(a) * 9.0, fy + 1, T.y + sin(a) * 9.0))
	loc.props.append({"type": "builder", "builder": Callable(AdventureArch, "scumport"), "piers": piers, "lamps": lamps, "square": Vector3(T.x, fy + 1, T.y),
			"west": west, "seed": rng.randi()})
	var folk: Array = [
		{"pos": Vector3(T.x + 3.0, fy + 1, T.y - 4.0), "role": "fixer", "seed": 101},
		{"pos": Vector3(T.x - 4.0, fy + 1, T.y + 3.0), "role": "fence", "seed": 102},
		{"pos": _xz(shore + west * -2.0 + Vector2(0, 2.0), fy + 1), "role": "harbourmaster", "seed": 103},
	]
	for i in 5:
		var a := TAU * i / 5.0
		folk.append({"pos": Vector3(T.x + cos(a) * 6.5, fy + 1, T.y + sin(a) * 6.5), "role": "dockhand", "seed": 110 + i})
	loc.set_meta(&"adv", {"scum_folk": folk, "dock": _xz(shore + west * 10.0 + Vector2(0, 9.0), SEA + 1)})
	# The Cutthroat Cove on the far (east) side of the isle.
	var east := C + Vector2(1, 0) * 95.0
	for i in 40:
		var q := C + Vector2(1, 0) * (i * 3.0)
		if _g(planner, q.x, q.y) <= SEA + 2:
			east = q - Vector2(1, 0) * 8.0
			break
	var cy := _g(planner, east.x, east.y)
	var cove := Location.new(&"scumport_cove", "Cutthroat Cove", Location.Kind.RUIN, Vector3(east.x, cy + 1, east.y))
	cove.radius = 22.0
	cove.set_meta(&"map_kind", "smuggler_cove")
	SitePlan.ruin(cove)
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		cove.add_spawn("enemy", Vector3(east.x + cos(a) * 7.0, cy + 1, east.y + sin(a) * 7.0), {"kind": "adv_cutthroat"})
	cove.add_spawn("chest", Vector3(east.x + 0.5, cy + 1, east.y + 0.5), {"tier": 2})
	return [loc, cove]


# --- Stormbreak Light -----------------------------------------------------------------------

static func _stormbreak(planner: LocationPlanner, rng: RandomNumberGenerator) -> Location:
	var isle: Array = AdventureTerrain.ISLES["stormbreak"]
	var C: Vector2 = isle[0]
	# The lighthouse stands on the crag's shoulder, not the needle top.
	var p := C + Vector2(-1, 0.3).normalized() * 30.0
	var g := _g(planner, p.x, p.y)
	var loc := Location.new(&"stormbreak", "Stormbreak Light", Location.Kind.TOWER, Vector3(p.x, g, p.y))
	loc.major = true
	loc.set_meta(&"map_kind", "stormbreak")
	Structures.tower(loc, rng)
	loc.add_spawn("enemy", loc.center + Vector3(9, 1, 4), {"kind": "drowned"})
	loc.add_spawn("enemy", loc.center + Vector3(-7, 1, 8), {"kind": "drowned"})
	loc.add_spawn("enemy", loc.center + Vector3(5, 1, -9), {"kind": "adv_cutthroat"})
	loc.props.append({"type": "builder", "builder": Callable(AdventureArch, "stormbreak"), "at": loc.center, "seed": rng.randi()})
	loc.set_meta(&"adv", {"cache": loc.center + Vector3(2.5, 1.0, 2.5), "storm": true})
	return loc


# --- The Isle of Hollow Crowns ----------------------------------------------------------------

static func _hollow_crowns(planner: LocationPlanner, rng: RandomNumberGenerator) -> Location:
	var isle: Array = AdventureTerrain.ISLES["hollow_crowns"]
	var C: Vector2 = isle[0]
	var g := _g(planner, C.x, C.y)
	var loc := Location.new(&"hollow_crowns", "Isle of Hollow Crowns", Location.Kind.RUIN, Vector3(C.x, g + 1, C.y))
	loc.ground_y = g
	loc.radius = 40.0
	loc.pad_radius = 13.0
	loc.pad_falloff = 10.0
	loc.major = true
	loc.set_meta(&"map_kind", "celestial_prison")
	var bp := Blueprint.new(Vector3i(floori(C.x) - 20, g - 4, floori(C.y) - 20), Vector3i(41, 20, 41))
	loc.blueprints.append(bp)
	# A ring of broken crowned pillars round the Mirror of Stars.
	var pillars: Array = []
	for i in 9:
		var a := TAU * i / 9.0
		var pp := C + AdventureTerrain.dir(a) * 11.0
		var h := 7 if i % 3 != 1 else rng.randi_range(2, 4)
		pillars.append([Vector3(pp.x, g + 1, pp.y), float(h)])
		for y in range(g + 1, g + 1 + h):
			_put(bp, Vector3i(floori(pp.x), y, floori(pp.y)), S)
	for dx in range(-1, 2):
		_put(bp, Vector3i(floori(C.x) + dx, g + 1, floori(C.y) - 1), S)
	loc.props.append({"type": "builder", "builder": Callable(AdventureArch, "hollow_crowns"), "at": loc.center, "pillars": pillars, "seed": rng.randi()})
	loc.add_spawn("enemy", loc.center + Vector3(16, 0, 6), {"kind": "skeleton"})
	loc.add_spawn("enemy", loc.center + Vector3(-14, 0, 10), {"kind": "skeleton"})
	loc.add_spawn("enemy", loc.center + Vector3(4, 0, -17), {"kind": "archer"})
	loc.add_spawn("chest", loc.center + Vector3(-5.5, 0, -5.5), {"tier": 2})
	loc.set_meta(&"adv", {"mirror": loc.center + Vector3(0, 0, 0.2)})
	return loc
