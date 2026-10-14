class_name MapImage
extends RefCounted
## Builds the world map (1 px = 4 m) from the generator's coarse maps:
## biome colours, hill shading, water, and roads. Used by the minimap and
## the full map screen. Thread-safe (reads only prepared data).

const BIOME_COLORS := {
	WorldGen.Biome.OCEAN: Color(0.08, 0.12, 0.16),
	WorldGen.Biome.PLAINS: Color(0.5, 0.45, 0.28),
	WorldGen.Biome.FOREST: Color(0.62, 0.32, 0.12),
	WorldGen.Biome.PEAKS: Color(0.6, 0.62, 0.66),
	WorldGen.Biome.MARSH: Color(0.24, 0.27, 0.18),
	WorldGen.Biome.WASTES: Color(0.36, 0.3, 0.28),
	WorldGen.Biome.ASPHODEL: Color(0.35, 0.28, 0.26),
	WorldGen.Biome.LAKE_OF_FIRE: Color(0.85, 0.3, 0.06),
	WorldGen.Biome.TARTARUS: Color(0.22, 0.18, 0.18),
}


static func build(gen: WorldGen) -> Image:
	var n := gen._coarse_n
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var sea := WorldGen.SEA_LEVEL if gen.dimension == WorldGen.Dimension.OVERWORLD else WorldGen.LAVA_LEVEL
	for z in n:
		for x in n:
			var i := x + z * n
			var h := gen._base[i] + gen._ridge[i] * 0.45
			var biome := gen._biome[i]
			var c: Color = BIOME_COLORS.get(biome, Color.GRAY)
			if gen.dimension == WorldGen.Dimension.OVERWORLD and biome == WorldGen.Biome.PEAKS and h > 70.0:
				c = Color(0.85, 0.86, 0.9)
			var left := gen._base[maxi(i - 1, 0)] + gen._ridge[maxi(i - 1, 0)] * 0.45
			var up := gen._base[maxi(i - n, 0)] + gen._ridge[maxi(i - n, 0)] * 0.45
			var shade := clampf(1.0 + ((h - left) + (h - up)) * 0.08, 0.55, 1.4)
			c = c * shade
			if h < sea:
				if gen.dimension == WorldGen.Dimension.OVERWORLD:
					c = Color(0.06, 0.1, 0.14).lerp(Color(0.12, 0.2, 0.26), clampf((h - sea + 20.0) / 20.0, 0.0, 1.0))
				else:
					c = Color(0.9, 0.32, 0.06).lerp(Color(1.0, 0.6, 0.2), clampf((h - sea + 10.0) / 10.0, 0.0, 1.0))
			img.set_pixel(x, z, Color(clampf(c.r, 0, 1), clampf(c.g, 0, 1), clampf(c.b, 0, 1)))
	# Roads.
	for key: int in gen._pads:
		var p: Vector3 = gen._pads[key]
		if p.z < 0.5:
			continue
		var x := (key % gen.size) / WorldGen.COARSE
		var z := (key / gen.size) / WorldGen.COARSE
		img.set_pixel(x, z, Color(0.78, 0.66, 0.46))
	return img
