class_name SeaLairs
extends RefCounted
## Blueprints for the ocean bosses' lairs (world revision 4):
##   * The Kraken's Graveyard - a ring of wreck decks and rock outcrops round a
##     flooded pool over the deep; the Abyssal Kraken rises in the middle.
##   * The Maw of the Sea - six sea stacks crowned with the broken platforms of
##     a drowned temple round Charybdis's whirlpool; the sea is open air down
##     the funnel to the maw.
## Both are joined to the coast by a broken causeway (Lairs.causeway) so the
## fight never depends on swimming. Built things are invisible STRUCTURE
## collision; the meshes come from the arena props (world/architecture/arenas/sea_arenas.gd).

const SEA := WorldGen.SEA_LEVEL
const S := Blocks.STRUCTURE


static func _w(bp: Blueprint, local: Vector3) -> Vector3:
	return Vector3(bp.origin) + local + Vector3(0.5, 0.0, 0.5)


static func _center(bp: Blueprint, lc: Vector3i) -> Vector3:
	return Vector3(bp.origin + lc) + Vector3(0.5, 1.0, 0.5)


## Deck sectors: [start angle, end angle] pieces of the ring with gaps between them.
static func _sectors(rng: RandomNumberGenerator, count: int, gap: float) -> Array:
	var out: Array = []
	var off := rng.randf() * TAU
	for i in count:
		var a0 := off + TAU * i / count + gap * 0.5
		var a1 := off + TAU * (i + 1) / count - gap * 0.5
		out.append(Vector2(a0, a1))
	return out


static func _in_sector(a: float, sectors: Array) -> bool:
	for s: Vector2 in sectors:
		if angle_difference(s.x, a) >= 0.0 and angle_difference(a, s.y) >= 0.0:
			return true
	return false


# --- The Kraken's Graveyard ------------------------------------------------------------------

## `toward_coast`: horizontal direction from the lair to the shore (the causeway lands there).
static func kraken(loc: Location, toward_coast: Vector2, rng: RandomNumberGenerator) -> void:
	loc.ground_y = SEA + 2
	loc.radius = 34.0
	loc.pad_radius = 0.0
	var pool := 9.0
	var deck := 18.0
	var below := 26
	var half := 26
	var c := Vector3i(roundi(loc.center.x), loc.ground_y, roundi(loc.center.z))
	var bp := Blueprint.new(Vector3i(c.x - half, loc.ground_y - below, c.z - half), Vector3i(half * 2 + 1, below + 24, half * 2 + 1))
	loc.blueprints.append(bp)
	var lc := Vector3i(half, below, half)
	var fy := lc.y
	var coast := Vector3(toward_coast.x, 0, toward_coast.y).normalized()
	var sectors := _sectors(rng, 6, 0.32)
	# The decks: wreck hulls and rock outcrops in six pieces; plank bridges span the gaps.
	for dz in range(-half, half + 1):
		for dx in range(-half, half + 1):
			var r := Vector2(dx + 0.5, dz + 0.5).length()
			if r < pool + 0.3 or r > deck:
				continue
			var a := atan2(float(dz) + 0.5, float(dx) + 0.5)
			var on_deck := _in_sector(a, sectors)
			var bridge := false
			if not on_deck:
				for s: Vector2 in sectors:
					var mid := s.y + 0.16
					var dir := Vector2(cos(mid), sin(mid))
					var along := Vector2(dx + 0.5, dz + 0.5).dot(dir)
					var across := absf(Vector2(dx + 0.5, dz + 0.5).dot(Vector2(-dir.y, dir.x)))
					if across < 1.3 and along > pool + 1.0 and along < deck - 1.5:
						bridge = true
			if not on_deck and not bridge:
				continue
			bp.set_local(lc.x + dx, fy, lc.z + dz, S)
			for up in range(1, 10):
				bp.set_local(lc.x + dx, fy + up, lc.z + dz, Blueprint.CARVE)
			if on_deck and r < deck - 0.8:
				# Hull and rock below the deck down to the sea bed.
				bp.set_local(lc.x + dx, fy - 1, lc.z + dz, S)
				if (dx + dz) % 3 == 0:
					for y in range(maxi(0, fy - 22), fy - 1):
						bp.set_local(lc.x + dx, y, lc.z + dz, S)
	# Rocks breaking the surface between the decks (natural ground).
	var rocks: Array = []
	for i in 7:
		var a := rng.randf() * TAU
		var r := rng.randf_range(deck + 2.0, deck + 7.0)
		var p := lc + Vector3i(roundi(cos(a) * r), rng.randi_range(-6, -2), roundi(sin(a) * r))
		var rr := rng.randf_range(2.5, 4.0)
		bp.sphere(p, rr, Blocks.GRANITE if i % 2 else Blocks.BASALT)
		rocks.append([Vector3(p - lc) - Vector3(0, 1, 0), rr])
	# Broken masts standing up out of the decks.
	var masts: Array = []
	for i in 3:
		var s: Vector2 = sectors[(i * 2) % sectors.size()]
		var a := lerpf(s.x, s.y, rng.randf_range(0.3, 0.7))
		var p := lc + Vector3i(roundi(cos(a) * 14.5), 1, roundi(sin(a) * 14.5))
		var h := rng.randi_range(6, 11)
		bp.fill(p, p + Vector3i(0, h, 0), S)
		masts.append([Vector3(p - lc) - Vector3(0, 1, 0), float(h), rng.randf_range(-0.12, 0.12)])
	var center := _center(bp, lc)
	loc.props.append({"type": "arena", "material": "arena", "arena": "kraken_lair", "center": center, "radius": 60.0, "seed": rng.randi(),
			"pool": pool, "deck": deck, "sectors": sectors, "masts": masts, "rocks": rocks, "coast": coast})
	loc.add_spawn("boss", _w(bp, Vector3(lc) + Vector3(0, 1, 0)), {"kind": "kraken"})
	var landing := Vector3(lc) + coast * (deck - 3.0) + Vector3(0, 1, 0)
	var side := Vector3(-coast.z, 0, coast.x)
	loc.add_spawn("lore", _w(bp, landing + side * 2.0), {"text": "kraken"})
	loc.add_spawn("chest", _w(bp, Vector3(lc) - coast * (deck - 3.0) + Vector3(0, 1, 0)), {"tier": 3})
	for sgn: float in [-1.0, 1.0]:
		loc.add_spawn("enemy", _w(bp, landing + side * sgn * 6.0 - coast * 2.0), {"kind": "drowned"})
	for i in 2:
		var a := atan2(-coast.z, -coast.x) + (1.1 if i == 0 else -1.1)
		loc.add_spawn("enemy", _w(bp, Vector3(lc) + Vector3(cos(a), 0, sin(a)) * 30.0 + Vector3(0, -6, 0)), {"kind": "shark"})
	loc.center = _w(bp, Vector3(lc) + Vector3(0, 1, 0))
	loc.half_height = 0.0


# --- The Maw of the Sea (Charybdis) -----------------------------------------------------------

## Radius of the carved whirlpool funnel at `depth` metres below the sea surface.
static func funnel_radius(depth: float) -> float:
	var t := pow(clampf(depth / 13.0, 0.0, 1.0), 1.0 / 1.6)
	return lerpf(12.8, 2.4, pow(t, 0.62))


static func charybdis(loc: Location, toward_coast: Vector2, rng: RandomNumberGenerator) -> void:
	loc.ground_y = SEA + 2
	loc.radius = 36.0
	loc.pad_radius = 0.0
	var inner := 12.0
	var outer := 21.0
	var below := 28
	var half := 28
	var c := Vector3i(roundi(loc.center.x), loc.ground_y, roundi(loc.center.z))
	var bp := Blueprint.new(Vector3i(c.x - half, loc.ground_y - below, c.z - half), Vector3i(half * 2 + 1, below + 24, half * 2 + 1))
	loc.blueprints.append(bp)
	var lc := Vector3i(half, below, half)
	var fy := lc.y
	var coast := Vector3(toward_coast.x, 0, toward_coast.y).normalized()
	var sectors := _sectors(rng, 6, 0.36)
	var surface := SEA + 1  # world y of the sea surface
	for dz in range(-half, half + 1):
		for dx in range(-half, half + 1):
			var r := Vector2(dx + 0.5, dz + 0.5).length()
			# The whirlpool: open air down the funnel (the funnel wall is modelled), a floor at the bottom.
			if r < 14.4:
				for y in range(0, fy):
					var depth := float(surface - (bp.origin.y + y))
					if depth < -0.5:
						continue
					if depth > 13.5:
						if depth < 14.5:
							bp.set_local(lc.x + dx, y, lc.z + dz, S)
						continue
					if r < funnel_radius(depth) + 0.9:
						bp.set_local(lc.x + dx, y, lc.z + dz, Blueprint.CARVE)
			if r < inner or r > outer:
				continue
			var a := atan2(float(dz) + 0.5, float(dx) + 0.5)
			var on_deck := _in_sector(a, sectors)
			var bridge := false
			if not on_deck:
				for s: Vector2 in sectors:
					var mid := s.y + 0.18
					var dir := Vector2(cos(mid), sin(mid))
					var along := Vector2(dx + 0.5, dz + 0.5).dot(dir)
					var across := absf(Vector2(dx + 0.5, dz + 0.5).dot(Vector2(-dir.y, dir.x)))
					if across < 1.4 and along > inner + 1.5 and along < outer - 1.5:
						bridge = true
			if not on_deck and not bridge:
				continue
			bp.set_local(lc.x + dx, fy, lc.z + dz, S)
			for up in range(1, 10):
				bp.set_local(lc.x + dx, fy + up, lc.z + dz, Blueprint.CARVE)
	# Sea stacks under every platform: natural rock rising from the sea bed.
	var stacks: Array = []
	for s: Vector2 in sectors:
		var a := (s.x + s.y) * 0.5
		var p := lc + Vector3i(roundi(cos(a) * 17.0), 0, roundi(sin(a) * 17.0))
		bp.cylinder(Vector3i(p.x, maxi(0, fy - 24), p.z), 4.2, 24 - 1, Blocks.GRANITE)
		for k in 3:
			bp.sphere(Vector3i(p.x + rng.randi_range(-2, 2), fy - 4 - k * 6, p.z + rng.randi_range(-2, 2)), rng.randf_range(3.5, 5.0), Blocks.GRANITE)
		stacks.append([Vector3(p - lc) - Vector3(0, 1, 0), a])
	# Standing columns of the drowned temple on the platforms.
	var columns: Array = []
	for i in 8:
		var s: Vector2 = sectors[i % sectors.size()]
		var a := lerpf(s.x, s.y, 0.25 + 0.5 * float(i / sectors.size()))
		var p := lc + Vector3i(roundi(cos(a) * 19.0), 1, roundi(sin(a) * 19.0))
		var h := rng.randi_range(2, 9)
		bp.cylinder(p, 0.9, h, S)
		columns.append([Vector3(p - lc) - Vector3(0, 1, 0), float(h)])
	var center := _center(bp, lc)
	loc.props.append({"type": "arena", "material": "arena", "arena": "charybdis_maw", "center": center, "radius": 64.0, "seed": rng.randi(),
			"inner": inner, "outer": outer, "sectors": sectors, "stacks": stacks, "columns": columns, "coast": coast})
	loc.add_spawn("boss", _w(bp, Vector3(lc) + Vector3(0, 1, 0)), {"kind": "charybdis"})
	var landing := Vector3(lc) + coast * (outer - 3.0) + Vector3(0, 1, 0)
	var side := Vector3(-coast.z, 0, coast.x)
	loc.add_spawn("lore", _w(bp, landing + side * 2.0), {"text": "charybdis"})
	loc.add_spawn("chest", _w(bp, Vector3(lc) - coast * (outer - 3.0) + Vector3(0, 1, 0)), {"tier": 3})
	for sgn: float in [-1.0, 1.0]:
		loc.add_spawn("enemy", _w(bp, landing + side * sgn * 6.0 - coast * 2.0), {"kind": "drowned"})
	loc.center = _w(bp, Vector3(lc) + Vector3(0, 1, 0))
	loc.half_height = 0.0
