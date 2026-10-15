class_name MapImage
extends RefCounted
## Shaded relief uses the actual continuous height field, not biome averages.
## Four-metre world texels; local cave maps are sampled from loaded edited data.
const BIOME_COLORS := {
	WorldGen.Biome.OCEAN: Color(0.08, 0.12, 0.16),
	WorldGen.Biome.PLAINS: Color(0.5, 0.45, 0.28),
	WorldGen.Biome.FOREST: Color(0.42, 0.36, 0.18),
	WorldGen.Biome.PEAKS: Color(0.6, 0.62, 0.66),
	WorldGen.Biome.MARSH: Color(0.24, 0.27, 0.18),
	WorldGen.Biome.WASTES: Color(0.36, 0.3, 0.28),
	WorldGen.Biome.ASPHODEL: Color(0.35, 0.28, 0.26),
	WorldGen.Biome.LAKE_OF_FIRE: Color(0.85, 0.3, 0.06),
	WorldGen.Biome.TARTARUS: Color(0.22, 0.18, 0.18),
	WorldGen.Biome.RYFT: Color(0.4, 0.35, 0.55),
	WorldGen.Biome.REDWOOD: WorldGen.BIOME_COLORS[WorldGen.Biome.REDWOOD],
	WorldGen.Biome.CANYON: WorldGen.BIOME_COLORS[WorldGen.Biome.CANYON],
	WorldGen.Biome.ALPINE: WorldGen.BIOME_COLORS[WorldGen.Biome.ALPINE],
	WorldGen.Biome.TUNDRA: WorldGen.BIOME_COLORS[WorldGen.Biome.TUNDRA],
	WorldGen.Biome.VOLCANIC: WorldGen.BIOME_COLORS[WorldGen.Biome.VOLCANIC],
	WorldGen.Biome.FJORD: WorldGen.BIOME_COLORS[WorldGen.Biome.FJORD],
}

static func build(gen: WorldGen) -> Image:
	var n := gen._coarse_n
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var sea := WorldGen.SEA_LEVEL if gen.dimension == 0 else WorldGen.LAVA_LEVEL
	# Computed once, in parallel, and shared with the horizon.
	var heights := gen.height_map()
	for z in n:
		for x in n:
			var i := x + z * n
			var h := heights[i]
			var c: Color = BIOME_COLORS.get(gen._biome[i], Color.GRAY)
			if gen._biome[i] == WorldGen.Biome.FOREST:
				c = WorldGen.FOREST_COLORS[gen.forest_region(x * 4 + 2, z * 4 + 2)]
			if gen.dimension == 0 and h > 100:
				c = c.lerp(Color(0.88, 0.9, 0.91), smoothstep(100, 180, h))
			var left := heights[maxi(x - 1, 0) + z * n]
			var up := heights[x + maxi(z - 1, 0) * n]
			c *= clampf(1.0 + ((h - left) + (h - up)) * 0.055, 0.48, 1.35)
			# Ten-metre contours make steep ridgelines and valleys readable.
			if int(floor(h / 10)) != int(floor(left / 10)) or int(floor(h / 10)) != int(floor(up / 10)):
				c *= 0.76
			if h < sea:
				c = Color(0.065, 0.12, 0.18).lerp(Color(0.19, 0.39, 0.42), clampf((h - sea + 25) / 25, 0, 1)) if gen.dimension == 0 else Color(0.7, 0.2, 0.06)
				if gen.dimension == 2:
					c = Color(0.065, 0.05, 0.1)
			elif h < sea + 2 and gen.dimension == 0:
				c = Color(0.72, 0.64, 0.43)
			img.set_pixel(x, z, c.clamp())
	# Lakes: alpine tarns, frozen ponds, the caldera's lava.
	for lake: Array in gen.lakes:
		var c: Vector2 = lake[0]
		var r: float = lake[1]
		var lava: bool = lake[3] == Blocks.LAVA
		var frozen: bool = lake[3] == Blocks.ICE
		for z in range(maxi(0, int((c.y - r) / 4)), mini(n, int((c.y + r) / 4) + 1)):
			for x in range(maxi(0, int((c.x - r) / 4)), mini(n, int((c.x + r) / 4) + 1)):
				if Vector2(x * 4 + 2, z * 4 + 2).distance_to(c) < r and heights[x + z * n] < float(lake[2]):
					img.set_pixel(x, z, Color(0.95, 0.42, 0.1) if lava else (Color(0.72, 0.8, 0.86) if frozen else Color(0.16, 0.34, 0.42)))
	for key: int in gen._pads:
		if (gen._pads[key] as Vector3).z >= 0.5:
			img.set_pixel((key % gen.size) / 4, (key / gen.size) / 4, Color(0.78, 0.66, 0.46))
	# Building silhouettes, not generic village dots.
	for loc in gen.locations:
		for prop: Dictionary in loc.props:
			if prop["material"] != "roof":
				continue
			var p: Vector3 = prop["at"]
			var s: Vector3 = prop["size"]
			var rect := Rect2i(Vector2i((p.x - s.x * 0.5) / 4, (p.z - s.z * 0.5) / 4), Vector2i(maxi(1, ceili(s.x / 4)), maxi(1, ceili(s.z / 4))))
			img.fill_rect(rect.intersection(Rect2i(0, 0, n, n)), Color(0.78, 0.75, 0.67))
	return img

static func cave_slice(vw: VoxelWorld, center: Vector3) -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for z in 64:
		for x in 64:
			var p := Vector3i(center.floor()) + Vector3i((x - 32) * 3, 1, (z - 32) * 3)
			var b := vw.get_block(p)
			var color := Color(0.045, 0.04, 0.06)
			if b == Blocks.AIR:
				color = Color(0.42, 0.43, 0.4)
			elif b > 0:
				color = Blocks.color(b) * (0.9 if Blocks.light(b) > 0 else 0.4)
			img.set_pixel(x, z, color)
	return img
