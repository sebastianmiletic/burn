class_name AdventureTerrain
extends RefCounted
## World revision 5 terrain (new worlds only; revisions 2-4 never call this):
##
##   * Mount Pyrrhos - the Brimstone volcano rebuilt as a huge cone (310 m) with a
##     135 m caldera you can walk into through the Fire Road, a canyon cut through
##     its north flank. On the caldera floor: the village of the Fire People, a
##     lava lake with the Emberheart altar on an island joined by a causeway,
##     three lava falls pouring down the inner wall into pools that run as lava
##     rivers to the lake, and a waterfall hissing onto the hot rock beside one.
##     Three lava channels score the outer flanks, each dropping over a step
##     (the outer lava falls) halfway down.
##   * The outer isles: Scumport (a low muddy harbour island), Stormbreak (a crag
##     with a lighthouse) and the Isle of Hollow Crowns (ruins and the Mirror of
##     Stars on its summit).
##   * The Atlantis basin: a wide flat bowl at the bottom of the Abyssal Trench.
##
## WorldGen calls `volcano()` in place of its own `_volcano` and `shape_column()`
## per coarse cell after the coast is blended; everything else reads the
## constants (planning, scenery, hazards).

const V := Vector2(1250, 2620)        ## volcano centre (same place as revision 3/4)
const R := 560.0                      ## cone radius
const H := 310.0                      ## cone height above the biome base
const RC := 135.0                     ## caldera radius
const FLOOR_DROP := 70.0              ## caldera floor below the rim
const LAKE_R := 38.0                  ## central lava lake
const ISLE_R := 9.0                   ## the altar island
## The Fire Road: the canyon through the north flank (towards the old island).
const NOTCH := Vector2(-0.14, -0.99)
## Outer lava channels and inner lava falls: angles relative to the notch.
const CHANNELS := [2.0, 3.1, 4.2]
const FALLS := [1.6, 3.14, 4.6]
const WATERFALL := 1.2
const POOL_R := 8.0
const STEP_AT := 0.5                  ## outer lava falls at this fraction of the cone radius

## Outer isles: centre, radius, peak above sea level, biome.
const ISLES := {
	"scumport": [Vector2(2650, 3350), 150.0, 22.0, WorldGen.Biome.PLAINS],
	"stormbreak": [Vector2(4380, 2350), 120.0, 64.0, WorldGen.Biome.FJORD],
	"hollow_crowns": [Vector2(260, 4380), 125.0, 46.0, WorldGen.Biome.PLAINS],
}
## Atlantis: the city sits on a flat bowl at the bottom of the trench.
const ATLANTIS := Vector2(3975, 3050)
const ATLANTIS_FLOOR := -92.0
const ATLANTIS_R := 150.0


static func notch_angle() -> float:
	return atan2(NOTCH.y, NOTCH.x)


static func dir(a: float) -> Vector2:
	return Vector2(cos(a), sin(a))


## Height of the caldera rim and floor above the biome base.
static func rim_rel() -> float:
	return H * pow(1.0 - RC / R, 1.55)


static func floor_rel() -> float:
	return rim_rel() - FLOOR_DROP


## Angle of an outer lava channel `k` at distance `d` (they meander a little).
static func channel_angle(k: int, d: float) -> float:
	return notch_angle() + float(CHANNELS[k]) + 0.1 * sin(d * 0.018 + k * 1.7)


static func _ang_dist(a: float, b: float) -> float:
	return absf(angle_difference(a, b))


## The cone above the biome base (replaces WorldGen._volcano for revision 5).
static func volcano(p: Vector2) -> float:
	var rel := p - V
	var d := rel.length()
	if d >= R:
		return 0.0
	var x := d / R
	var ang := atan2(rel.y, rel.x)
	var cone := H * pow(1.0 - x, 1.55)
	# Ribs and gullies down the flanks.
	cone *= 1.0 - 0.05 * (0.5 + 0.5 * sin(ang * 15.0 + d * 0.011)) * smoothstep(0.15, 0.4, x)
	var rim := rim_rel()
	var fl := floor_rel()
	# Caldera: a flat floor, a sheer inner wall up to a lip on the rim.
	var wall := smoothstep(RC * 0.84, RC * 1.0, d)
	var inner := lerpf(fl, rim + 3.0, pow(wall, 1.3))
	var inside := 1.0 - smoothstep(RC * 0.98, RC * 1.12, d)
	var h := lerpf(minf(cone, rim + 3.0), inner, inside)
	var na := notch_angle()
	if d < RC:
		# The lava lake's basin, the altar island and the causeway out to it.
		h -= 7.0 * (1.0 - smoothstep(LAKE_R - 12.0, LAKE_R + 2.0, d))
		h += 10.0 * (1.0 - smoothstep(ISLE_R - 2.0, ISLE_R + 2.5, d))
		var along := rel.dot(NOTCH)
		var across := absf(rel.dot(Vector2(-NOTCH.y, NOTCH.x)))
		if along > 4.0 and along < LAKE_R + 8.0:
			h = maxf(h, fl + 0.8 - 8.5 * smoothstep(2.6, 6.0, across))
		# Pools at the foot of the lava falls, and the rivers they feed.
		for fa: float in FALLS:
			var a := na + fa
			var pc := dir(a) * RC * 0.8
			var pd := rel.distance_to(pc)
			h -= 3.0 * (1.0 - smoothstep(POOL_R - 3.0, POOL_R + 1.5, pd))
			if d > LAKE_R - 4.0 and d < RC * 0.8:
				var across_r := _ang_dist(ang, a) * d
				h -= 2.2 * (1.0 - smoothstep(2.4, 5.5, across_r))
	# The Fire Road: a canyon from the foot of the cone up to the caldera floor.
	var along_n := rel.dot(NOTCH)
	if along_n > RC * 0.7:
		var across_n := absf(rel.dot(Vector2(-NOTCH.y, NOTCH.x)))
		if across_n < 16.0:
			var t := clampf((along_n - RC * 0.82) / (R * 0.98 - RC * 0.82), 0.0, 1.0)
			var path := lerpf(fl + 0.5, 1.0, t)
			h = lerpf(h, minf(h, path), 1.0 - smoothstep(7.0, 16.0, across_n))
	# Outer lava channels, each dropping over a step halfway down.
	if d > RC * 1.0 and d < R * 0.82:
		for k in CHANNELS.size():
			var across_c := _ang_dist(ang, channel_angle(k, d)) * d
			if across_c > 10.0:
				continue
			var groove := 4.0 + 9.0 * smoothstep(R * STEP_AT, R * STEP_AT + 5.0, d) * (1.0 - smoothstep(R * STEP_AT + 30.0, R * 0.8, d))
			groove *= smoothstep(RC * 1.0, RC * 1.1, d) * (1.0 - smoothstep(R * 0.74, R * 0.82, d))
			h -= groove * (1.0 - smoothstep(3.5, 9.0, across_c))
	return h


## Per coarse cell after the coast blend: islands rise out of the sea, the Atlantis
## bowl flattens the trench floor, and the caldera floor loses its noise.
## Returns [base, amp, biome, flags] where flags bit 1 = no ravines.
static func shape_column(p: Vector2, base: float, amp: float, biome: int) -> Array:
	var flags := 0
	var vd := p.distance_to(V)
	if vd < RC * 1.3:
		amp *= lerpf(0.25, 1.0, smoothstep(RC * 0.8, RC * 1.3, vd))
		flags |= 1
	elif vd < R:
		var rel := p - V
		if rel.dot(NOTCH) > RC * 0.7 and absf(rel.dot(Vector2(-NOTCH.y, NOTCH.x))) < 24.0:
			amp *= 0.4
			flags |= 1
	for key: String in ISLES:
		var isle: Array = ISLES[key]
		var c: Vector2 = isle[0]
		var r: float = isle[1]
		var d := p.distance_to(c)
		if d > r * 1.45:
			continue
		var a := atan2(p.y - c.y, p.x - c.x)
		var wob := 1.0 + 0.13 * sin(a * 3.0 + c.x) + 0.07 * sin(a * 7.0 + c.y) + 0.04 * sin(a * 13.0)
		var x := d / (r * wob)
		var peak: float = isle[2]
		var prof := pow(maxf(0.0, 1.0 - x * x), 1.4)
		if key == "stormbreak":
			prof = pow(maxf(0.0, 1.0 - x), 1.15)  # a crag, not a mound
		var hh := WorldGen.SEA_LEVEL - 14.0 + (peak + 14.0) * prof - 40.0 * smoothstep(1.0, 1.45, x)
		if hh > base:
			base = hh
			amp = lerpf(amp, 2.2, smoothstep(0.0, 0.4, prof))
			flags |= 1
			if hh > WorldGen.SEA_LEVEL - 0.5:
				biome = isle[3]
	var ad := p.distance_to(ATLANTIS)
	if ad < ATLANTIS_R * 1.5:
		var w := 1.0 - smoothstep(ATLANTIS_R, ATLANTIS_R * 1.5, ad)
		base = lerpf(base, minf(base, ATLANTIS_FLOOR), w)
		base = lerpf(base, ATLANTIS_FLOOR, 1.0 - smoothstep(ATLANTIS_R * 0.75, ATLANTIS_R, ad))
		amp *= lerpf(1.0, 0.3, w)
	return [base, amp, biome, flags]


## The lava lake round the altar and the pools under the falls (lava lakes are
## level discs; WorldGen fills them where the ground lies below the level).
static func lakes(gen: WorldGen) -> Array:
	var out: Array = []
	var ref := V + NOTCH.rotated(PI) * 70.0
	var fl := gen.smooth_height(ref.x, ref.y)
	out.append([V, LAKE_R, fl - 2.4, Blocks.LAVA])
	for fa: float in FALLS:
		var pc := V + dir(notch_angle() + fa) * RC * 0.8
		out.append([pc, POOL_R, gen.smooth_height(pc.x, pc.y) + 1.6, Blocks.LAVA])
	return out


## Polylines (world xz) of the lava rivers: outer channels from the rim to their
## end, and the inner rivers from each pool to the lake. For scenery and hazards.
static func outer_channel(k: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var d := RC * 1.02
	while d < R * 0.78:
		pts.append(V + dir(channel_angle(k, d)) * d)
		d += 6.0
	return pts


static func inner_river(k: int) -> PackedVector2Array:
	var a := notch_angle() + float(FALLS[k])
	var pts := PackedVector2Array()
	var d := RC * 0.8 - POOL_R * 0.6
	while d > LAKE_R - 6.0:
		pts.append(V + dir(a) * d)
		d -= 5.0
	return pts


## Where the inner lava falls and the waterfall pour over the rim (world xz) and
## where they land.
static func fall_top(a_rel: float) -> Vector2:
	return V + dir(notch_angle() + a_rel) * RC * 1.0


static func fall_foot(a_rel: float) -> Vector2:
	return V + dir(notch_angle() + a_rel) * RC * 0.8


## Is a point inside the caldera (horizontal)?
static func in_caldera(p: Vector3) -> bool:
	return Vector2(p.x, p.z).distance_to(V) < RC * 0.97


## Revision 5: the air halls of Atlantis count as sheltered (no sky light).
static func sheltered(pos: Vector3) -> bool:
	return pos.y < ATLANTIS_FLOOR + 40.0 and Vector2(pos.x, pos.z).distance_to(ATLANTIS) < ATLANTIS_R
