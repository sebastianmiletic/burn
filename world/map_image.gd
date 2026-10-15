class_name MapImage
extends RefCounted
## The world map, built once per dimension on a loading worker thread.
##
## `build()` returns the land colour image (biome colours with baked hillshade;
## sea floor where there is water, because the map shaders draw the liquid
## themselves from the height layer, so coastlines stay smooth at any zoom).
## Extra layers ride along as metadata on that Image, so GameWorld's
## `map_image(dim)` API does not change:
##   "height"            Image RH, terrain height per texel (metres)
##   "detail"            Image RG8 at a finer scale: R = roads, G = buildings
##   "detail_mpp"        metres per detail texel
##   "metres_per_pixel"  metres per colour/height texel
##   "world_size"        world extent in metres
##   "sea_level"         liquid surface height
##   "liquid"            0 water, 1 lava, 2 void (the Ryft)
## ui/shaders/map_common.gdshaderinc renders all of this; MapLayers uploads it.

## Legacy palette (distant terrain colouring reads this; keep it stable).
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
}
## The map's own palette: muted, readable under relief shading.
const MAP_COLORS := {
	WorldGen.Biome.OCEAN: Color(0.36, 0.33, 0.25),
	WorldGen.Biome.PLAINS: Color(0.55, 0.52, 0.33),
	WorldGen.Biome.FOREST: Color(0.3, 0.38, 0.2),
	WorldGen.Biome.PEAKS: Color(0.5, 0.49, 0.47),
	WorldGen.Biome.MARSH: Color(0.3, 0.33, 0.22),
	WorldGen.Biome.WASTES: Color(0.45, 0.35, 0.28),
	WorldGen.Biome.ASPHODEL: Color(0.4, 0.33, 0.3),
	WorldGen.Biome.LAKE_OF_FIRE: Color(0.45, 0.2, 0.1),
	WorldGen.Biome.TARTARUS: Color(0.26, 0.21, 0.21),
	WorldGen.Biome.RYFT: Color(0.4, 0.36, 0.52),
}
const SNOW := Color(0.9, 0.91, 0.93)
const SAND := Color(0.74, 0.67, 0.5)
## The finest detail layer we keep (roads, buildings); coarser on huge worlds.
const DETAIL_MPP := 2.0
const DETAIL_MAX := 2048


## Map colour for a biome id. Biomes added later by world generation can
## provide `biome_map_color(id)` on WorldGen; unknown ids get a muted colour.
static func biome_color(gen: WorldGen, biome: int) -> Color:
	if MAP_COLORS.has(biome):
		return MAP_COLORS[biome]
	if gen != null and gen.has_method("biome_map_color"):
		var c: Variant = gen.call("biome_map_color", biome)
		if c is Color:
			return c
	var h := fposmod(float(biome) * 0.618034, 1.0)
	return Color.from_hsv(h, 0.28, 0.5)


static func build(gen: WorldGen) -> Image:
	var n := gen._coarse_n
	var mpp := float(gen.size) / float(n)
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var sea := float(WorldGen.SEA_LEVEL if gen.dimension == 0 else WorldGen.LAVA_LEVEL)
	var detail := gen.make_detail_noise()
	var ridge := gen.make_ridge_noise()
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	var half := int(mpp * 0.5)
	for z in n:
		for x in n:
			heights[x + z * n] = gen.column_f(int(x * mpp) + half, int(z * mpp) + half, detail, ridge).x
	var forest := gen.dimension == 0
	# Light from the north-west, a little from above; a second softer light
	# from the north-east keeps east-facing slopes from going flat.
	var l1 := Vector3(-0.62, 0.62, -0.48).normalized()
	var l2 := Vector3(0.5, 0.75, -0.42).normalized()
	# Gradients over +-2 texels: broad landforms, not every noise ripple.
	var exaggerate := 2.4 / mpp
	var colors := {}
	for z in n:
		var zu := maxi(z - 2, 0) * n
		var zd := mini(z + 2, n - 1) * n
		for x in n:
			var i := x + z * n
			var h := heights[i]
			var b := gen._biome[i]
			var c: Color
			if forest and b == WorldGen.Biome.FOREST:
				# Forest kinds only tint the canopy: their regions are coarse cells.
				c = (MAP_COLORS[WorldGen.Biome.FOREST] as Color).lerp(WorldGen.FOREST_COLORS[gen.forest_region(int(x * mpp) + half, int(z * mpp) + half)], 0.18)
			elif colors.has(b):
				c = colors[b]
			else:
				c = biome_color(gen, b)
				colors[b] = c
			if gen.dimension == 0:
				if h > 95.0:
					c = c.lerp(SNOW, smoothstep(95.0, 165.0, h))
				# The sea floor (the shader lays the water and beaches over it).
				if h < sea:
					c = SAND.lerp(Color(0.3, 0.32, 0.3), smoothstep(sea, sea - 16.0, h))
			var hl := heights[maxi(x - 2, 0) + z * n]
			var hr := heights[mini(x + 2, n - 1) + z * n]
			var hu := heights[x + zu]
			var hd := heights[x + zd]
			var nrm := Vector3((hl - hr) * exaggerate, 4.0, (hu - hd) * exaggerate).normalized()
			var shade := maxf(nrm.dot(l1), 0.0) * 0.75 + maxf(nrm.dot(l2), 0.0) * 0.35
			var flat := l1.y * 0.75 + l2.y * 0.35
			c = c * clampf(0.62 + 0.55 * shade / flat - 0.17, 0.42, 1.32)
			img.set_pixel(x, z, c.clamp())
	img.set_meta("metres_per_pixel", mpp)
	img.set_meta("world_size", float(gen.size))
	img.set_meta("sea_level", sea)
	img.set_meta("liquid", [0, 1, 2][clampi(gen.dimension, 0, 2)])
	var height := Image.create_from_data(n, n, false, Image.FORMAT_RF, heights.to_byte_array())
	height.convert(Image.FORMAT_RH)  # half floats always filter linearly
	img.set_meta("height", height)
	var dmpp := maxf(DETAIL_MPP, ceilf(float(gen.size) / DETAIL_MAX))
	img.set_meta("detail", _detail(gen, dmpp))
	img.set_meta("detail_mpp", dmpp)
	return img


## Roads (from the world's road columns) and building roofs at a finer scale.
static func _detail(gen: WorldGen, dmpp: float) -> Image:
	var dn := int(ceil(gen.size / dmpp))
	var data := PackedByteArray()
	data.resize(dn * dn * 2)
	var per := int(ceil(255.0 / (dmpp * dmpp)))
	var size := gen.size
	for key: int in gen._pads:
		var v: Vector3 = gen._pads[key]
		if v.z < 0.5:
			continue
		var x := int((key % size) / dmpp)
		var z := int((key / size) / dmpp)
		if x >= dn or z >= dn:
			continue
		var i := (x + z * dn) * 2
		data[i] = mini(255, data[i] + per)
	var img := Image.create_from_data(dn, dn, false, Image.FORMAT_RG8, data)
	for loc in gen.locations:
		for prop: Dictionary in loc.props:
			if prop.get("material", "") != "roof" or not prop.has("at") or not prop.has("size"):
				continue
			var p: Vector3 = prop["at"]
			var s: Vector3 = prop["size"]
			var r := Rect2i(Vector2i(int((p.x - s.x * 0.5) / dmpp), int((p.z - s.z * 0.5) / dmpp)),
					Vector2i(maxi(1, ceili(s.x / dmpp)), maxi(1, ceili(s.z / dmpp)))).intersection(Rect2i(0, 0, dn, dn))
			for z in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					var c := img.get_pixel(x, z)
					img.set_pixel(x, z, Color(c.r, 1.0, 0.0))
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
