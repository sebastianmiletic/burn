class_name DistantLand
extends Node3D
## The horizon: a non-colliding height-field of the whole island beyond the
## streamed chunks, so mountains, coasts and forests stay visible to the edge
## of the world.
##
##  * Shape: the real terrain function (WorldGen.column_f) sampled every 8 m in
##    256 m tiles; beyond LOD_DISTANCE each tile swaps to a 32 m version made by
##    tent-filtering the fine heights (no aliased ridge spikes). Tiles carry
##    skirts so LOD borders never open cracks.
##  * Materials: per-vertex blend weights of the same surface materials the
##    streamed terrain uses (grass, dry grass, forest floor, mountain grass,
##    sand, ash, mud, rock), sampled from the same texture arrays and tints;
##    rock on steep faces, snow above the same altitude the terrain snows at,
##    autumn/pine canopy tint where trees grow, a sea surface on the water.
##  * Light: sun-facing faces lit, valleys shadowed by the ridges to the east /
##    west (per-vertex horizon angles), so low sun casts long mountain shadows.
##  * Haze: custom aerial perspective that matches the environment fog where
##    the streamed terrain ends and thins with distance and altitude, so far
##    ranges fade into a blue horizon instead of a white wall.
## Where the streamed chunks of a column are ready the horizon is discarded
## (VoxelWorld.horizon_coverage); around the rim it is sunk below the detailed
## field, so there is no z-fighting, no hole while streaming and nothing to pop.

const FINE := 8
const COARSE := 32
const TILE := 256
const LOD_DISTANCE := 1150.0
const LOD_MARGIN := 120.0
const SKIRT := 24.0
const WATER_Y := float(WorldGen.SEA_LEVEL) + 0.85
## Material classes (index -> material code); keep in step with the shader.
const CLASSES := [Blocks.GRASS, Blocks.DRY_GRASS, SmoothMesher.CODE_FOREST_FLOOR, SmoothMesher.CODE_PEAK_GRASS,
		Blocks.SAND, Blocks.ASH, Blocks.MUD, Blocks.STONE]
## Sun azimuths the horizon angles are traced along (the sun's path rises in
## the east-north-east and sets in the west-north-west, see SkyController).
const SUN_EAST := Vector2(0.925, 0.381)
const SUN_WEST := Vector2(-0.925, 0.381)

var gen: WorldGen
var _mat: ShaderMaterial
var _tiles: Array[MeshInstance3D] = []
var _profile_off := "--no-horizon" in OS.get_cmdline_user_args()
var _coverage: ImageTexture
var _coverage_timer := 0.0


## Heavy part (loading worker thread): heights, materials, horizons, arrays.
## Returns [tiles, skirt] where tiles = [[fine arrays, coarse arrays, aabb], ...].
static func arrays_for(world_gen: WorldGen) -> Array:
	var n := world_gen.size / FINE + 1
	var heights := PackedFloat32Array()
	var cls := PackedByteArray()
	var water := PackedByteArray()
	var peaks := PackedFloat32Array()
	var canopy := PackedColorArray()
	heights.resize(n * n)
	cls.resize(n * n)
	water.resize(n * n)
	peaks.resize(n * n)
	canopy.resize(n * n)
	# Sample rows in parallel (pure reads of the generator), then stitch.
	var rows: Array = []
	rows.resize(n)
	var task := WorkerThreadPool.add_group_task(func(z: int) -> void:
		rows[z] = _sample_row(world_gen, z, n), n, -1, true, "distant land rows")
	WorkerThreadPool.wait_for_group_task_completion(task)
	for z in n:
		var row: Array = rows[z]
		var h: PackedFloat32Array = row[0]
		var c: PackedByteArray = row[1]
		var wtr: PackedByteArray = row[2]
		var pk: PackedFloat32Array = row[3]
		var cp: PackedColorArray = row[4]
		for x in n:
			var i := x + z * n
			heights[i] = h[x]
			cls[i] = c[x]
			water[i] = wtr[x]
			peaks[i] = pk[x]
			canopy[i] = cp[x]
	var hz := _horizons(heights, n)
	var soft := _soften(heights, water, n)
	var per := TILE / FINE
	var tn := ceili(float(n - 1) / per)
	var tiles := []
	tiles.resize(tn * tn)
	var tile_task := WorkerThreadPool.add_group_task(func(t: int) -> void:
		tiles[t] = _tile(heights, soft, water, cls, peaks, canopy, hz, n, (t % tn) * per, (t / tn) * per, per), tn * tn, -1, true, "distant land tiles")
	WorkerThreadPool.wait_for_group_task_completion(tile_task)
	return [tiles, _sea_skirt(float(world_gen.size))]


## One row of samples: [heights, material class, sea flag, mountain flag, canopy].
static func _sample_row(world_gen: WorldGen, z: int, n: int) -> Array:
	var detail := world_gen.make_detail_noise()
	var ridge := world_gen.make_ridge_noise()
	var h := PackedFloat32Array()
	var c := PackedByteArray()
	var wtr := PackedByteArray()
	var pk := PackedFloat32Array()
	var cp := PackedColorArray()
	h.resize(n)
	c.resize(n)
	wtr.resize(n)
	pk.resize(n)
	cp.resize(n)
	var over := world_gen.dimension == 0
	var wz := mini(z * FINE, world_gen.size - 1)
	for x in n:
		var wx := mini(x * FINE, world_gen.size - 1)
		# Open sea: the highest the noise could lift it is still under water.
		if over and world_gen.smooth_height(wx, wz) + world_gen._coarse_sample(world_gen._amp, wx, wz) \
				+ world_gen._coarse_sample(world_gen._ridge, wx, wz) < WorldGen.SEA_LEVEL - 2.0:
			h[x] = WATER_Y
			wtr[x] = 1
			continue
		var col := world_gen.column_f(wx, wz, detail, ridge)
		var ground := col.x + 1.0   # the smooth surface lies one unit above the column value
		var biome := world_gen.biome_at(wx, wz)
		var hi := int(floorf(col.x + 0.5))
		if over and ground < WATER_Y and biome != WorldGen.Biome.MARSH:
			h[x] = WATER_Y
			wtr[x] = 1
			continue
		h[x] = ground
		var code := world_gen._ground_block(wx, hi, wz, hi, biome, 0)
		if code == Blocks.GRASS:
			if biome == WorldGen.Biome.FOREST:
				code = SmoothMesher.CODE_FOREST_FLOOR
			elif biome == WorldGen.Biome.PEAKS:
				code = SmoothMesher.CODE_PEAK_GRASS
		var k := CLASSES.find(code)
		if k < 0:
			k = 7 if code in [Blocks.SNOW, Blocks.GRANITE, Blocks.BASALT, Blocks.GRAVEL] else (1 if code == Blocks.DIRT else 0)
		c[x] = k
		pk[x] = 1.0 if biome == WorldGen.Biome.PEAKS else 0.0
		cp[x] = _canopy(biome, hi)
	return [h, c, wtr, pk, cp]


## [fine arrays, coarse arrays, aabb] for the tile whose corner is fine cell (x0, z0).
static func _tile(heights: PackedFloat32Array, soft: PackedFloat32Array, water: PackedByteArray, cls: PackedByteArray,
		peaks: PackedFloat32Array, canopy: PackedColorArray, hz: PackedVector2Array, n: int, x0: int, z0: int, per: int) -> Array:
	var x1 := mini(x0 + per, n - 1)
	var z1 := mini(z0 + per, n - 1)
	var all_water := true
	var lo := 1e9
	var hi_y := -1e9
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var i := x + z * n
			if water[i] == 0:
				all_water = false
			lo = minf(lo, heights[i])
			hi_y = maxf(hi_y, heights[i])
	if all_water:
		var flat := _water_quad(Vector2(x0 * FINE, z0 * FINE), Vector2(x1 * FINE, z1 * FINE))
		return [flat, flat, AABB(Vector3(x0 * FINE, WATER_Y - 1, z0 * FINE), Vector3((x1 - x0) * FINE, 2, (z1 - z0) * FINE))]
	var fine := _grid_arrays(heights, soft, water, cls, peaks, canopy, hz, n, x0, z0, x1, z1, 1)
	var coarse := _grid_arrays(heights, soft, water, cls, peaks, canopy, hz, n, x0, z0, x1, z1, COARSE / FINE)
	return [fine, coarse, AABB(Vector3(x0 * FINE, lo - SKIRT, z0 * FINE), Vector3((x1 - x0) * FINE, hi_y - lo + SKIRT + 12.0, (z1 - z0) * FINE))]


## The terrain with its finest ridged detail (spires narrower than ~90 m)
## smoothed away but the massifs kept, peaks max-biased so they don't sag.
## Distant fine tiles morph towards it, so far ranges read as mountains, not
## a comb of needles; near the streamed rim they keep the exact shape.
static func _soften(heights: PackedFloat32Array, water: PackedByteArray, n: int) -> PackedFloat32Array:
	const R := 6
	var rows: Array = []
	rows.resize(n)
	var pass1 := WorkerThreadPool.add_group_task(func(z: int) -> void:
		var row := PackedFloat32Array()
		row.resize(n)
		for x in n:
			var sum := 0.0
			for d in range(-R, R + 1):
				sum += heights[clampi(x + d, 0, n - 1) + z * n] * float(R + 1 - absi(d))
			row[x] = sum / float((R + 1) * (R + 1))
		rows[z] = row, n, -1, true, "distant land soften x")
	WorkerThreadPool.wait_for_group_task_completion(pass1)
	var cols: Array = []
	cols.resize(n)
	var pass2 := WorkerThreadPool.add_group_task(func(x: int) -> void:
		var col := PackedFloat32Array()
		col.resize(n)
		for z in n:
			var sum := 0.0
			var top := -1e9
			for d in range(-R, R + 1):
				var zz := clampi(z + d, 0, n - 1)
				sum += (rows[zz] as PackedFloat32Array)[x] * float(R + 1 - absi(d))
				top = maxf(top, heights[x + zz * n])
			var avg := sum / float((R + 1) * (R + 1))
			col[z] = WATER_Y if water[x + z * n] == 1 else lerpf(avg, maxf(avg, top), 0.3)
		cols[x] = col, n, -1, true, "distant land soften z")
	WorkerThreadPool.wait_for_group_task_completion(pass2)
	var out := PackedFloat32Array()
	out.resize(n * n)
	for x in n:
		var col: PackedFloat32Array = cols[x]
		for z in n:
			out[x + z * n] = col[z]
	return out


## Tree cover (rgb canopy colour, a coverage) from the same chances the
## streamed world plants trees with.
static func _canopy(biome: int, h: int) -> Color:
	match biome:
		WorldGen.Biome.FOREST:
			return Color(0.42, 0.13, 0.06, 0.58)   # Emberwood: autumn crowns
		WorldGen.Biome.PEAKS:
			return Color(0.07, 0.11, 0.07, 0.3) if h <= 70 else Color(0, 0, 0, 0)
		WorldGen.Biome.MARSH:
			return Color(0.22, 0.1, 0.06, 0.15)
		WorldGen.Biome.PLAINS:
			return Color(0.36, 0.14, 0.06, 0.05)
	return Color(0, 0, 0, 0)


## Tangent of the terrain horizon seen from each vertex towards the rising and
## the setting sun, traced on a 32 m lattice and interpolated.
static func _horizons(heights: PackedFloat32Array, n: int) -> PackedVector2Array:
	var step := COARSE / FINE
	var cn := (n - 1) / step + 1
	var rows: Array = []
	rows.resize(cn)
	var task := WorkerThreadPool.add_group_task(func(cz: int) -> void:
		var row := PackedVector2Array()
		row.resize(cn)
		for cx in cn:
			var x := cx * step
			var z := cz * step
			var h0 := heights[x + z * n]
			var out := Vector2.ZERO
			for d in 2:
				var dir: Vector2 = SUN_EAST if d == 0 else SUN_WEST
				var best := -1.0
				var t := 24.0
				while t < 1800.0:
					var sx := roundi((x * FINE + dir.x * t) / FINE)
					var sz := roundi((z * FINE + dir.y * t) / FINE)
					if sx < 0 or sz < 0 or sx >= n or sz >= n:
						break
					best = maxf(best, (heights[sx + sz * n] - h0) / t)
					t += 16.0 + t * 0.07
				if d == 0:
					out.x = best
				else:
					out.y = best
			row[cx] = out
		rows[cz] = row, cn, -1, true, "distant land horizons")
	WorkerThreadPool.wait_for_group_task_completion(task)
	var coarse := PackedVector2Array()
	for cz in cn:
		coarse.append_array(rows[cz])
	var hz := PackedVector2Array()
	hz.resize(n * n)
	for z in n:
		for x in n:
			var fx := float(x) / step
			var fz := float(z) / step
			var ix := mini(int(fx), cn - 2)
			var iz := mini(int(fz), cn - 2)
			var tx := fx - ix
			var tz := fz - iz
			var a := coarse[ix + iz * cn].lerp(coarse[ix + 1 + iz * cn], tx)
			var b := coarse[ix + (iz + 1) * cn].lerp(coarse[ix + 1 + (iz + 1) * cn], tx)
			hz[x + z * n] = a.lerp(b, tz)
	return hz


## Mesh arrays for one tile at `step` fine cells per vertex, with skirts.
static func _grid_arrays(heights: PackedFloat32Array, soft: PackedFloat32Array, water: PackedByteArray, cls: PackedByteArray,
		peaks: PackedFloat32Array, canopy: PackedColorArray, hz: PackedVector2Array, n: int,
		x0: int, z0: int, x1: int, z1: int, step: int) -> Array:
	var cols := (x1 - x0) / step + 1
	var rows := (z1 - z0) / step + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	var custom0 := PackedFloat32Array()
	var custom1 := PackedFloat32Array()
	var custom2 := PackedFloat32Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var grid_h := PackedFloat32Array()
	grid_h.resize(cols * rows)
	for r in rows:
		for c in cols:
			var x := mini(x0 + c * step, n - 1)
			var z := mini(z0 + r * step, n - 1)
			grid_h[c + r * cols] = _filtered_height(heights, water, n, x, z, step)
	for r in rows:
		for c in cols:
			var x := mini(x0 + c * step, n - 1)
			var z := mini(z0 + r * step, n - 1)
			var i := x + z * n
			var h := grid_h[c + r * cols]
			# Normal from the neighbouring (possibly coarse) samples.
			var hl := _h_at(heights, water, n, x - step, z, step) if c == 0 else grid_h[c - 1 + r * cols]
			var hr := _h_at(heights, water, n, x + step, z, step) if c == cols - 1 else grid_h[c + 1 + r * cols]
			var hd := _h_at(heights, water, n, x, z - step, step) if r == 0 else grid_h[c + (r - 1) * cols]
			var hu := _h_at(heights, water, n, x, z + step, step) if r == rows - 1 else grid_h[c + (r + 1) * cols]
			var nrm := Vector3(hl - hr, 2.0 * step * FINE, hd - hu).normalized()
			_push_vertex(Vector3(x * FINE, h, z * FINE), nrm, x, z, n, water, cls, peaks, canopy, hz,
					verts, norms, colors, custom0, custom1, uv, uv2)
			# Far shape (geomorph target): the softened field on the fine LOD.
			if step == 1:
				var sl := soft[maxi(x - 1, 0) + z * n]
				var sr := soft[mini(x + 1, n - 1) + z * n]
				var sd := soft[x + maxi(z - 1, 0) * n]
				var su := soft[x + mini(z + 1, n - 1) * n]
				var sn := Vector3(sl - sr, 2.0 * FINE, sd - su).normalized()
				custom2.append_array([soft[i], sn.x, sn.y, sn.z])
			else:
				custom2.append_array([h, nrm.x, nrm.y, nrm.z])
	for r in rows - 1:
		for c in cols - 1:
			var a := c + r * cols
			idx.append_array([a, a + 1, a + cols, a + 1, a + cols + 1, a + cols])
	# Skirts: a strip hanging down from every edge hides LOD cracks.
	var rings := [[], [], [], []]
	for c in cols:
		rings[0].append(c)
		rings[1].append(c + (rows - 1) * cols)
	for r in rows:
		rings[2].append(r * cols)
		rings[3].append(cols - 1 + r * cols)
	for side in 4:
		var ring: Array = rings[side]
		var base := verts.size()
		for k in ring.size():
			var src: int = ring[k]
			verts.append(verts[src] - Vector3(0, SKIRT, 0))
			norms.append(norms[src])
			colors.append(colors[src])
			for q in 4:
				custom0.append(custom0[src * 4 + q])
				custom1.append(custom1[src * 4 + q])
			custom2.append_array([custom2[src * 4] - SKIRT, custom2[src * 4 + 1], custom2[src * 4 + 2], custom2[src * 4 + 3]])
			uv.append(uv[src])
			uv2.append(uv2[src])
		for k in ring.size() - 1:
			var a: int = ring[k]
			var b: int = ring[k + 1]
			var sa := base + k
			var sb := base + k + 1
			# Both windings: a skirt is seen from whichever side is open.
			idx.append_array([a, b, sa, b, sb, sa, a, sa, b, b, sa, sb])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = norms
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_CUSTOM0] = custom0
	out[Mesh.ARRAY_CUSTOM1] = custom1
	out[Mesh.ARRAY_CUSTOM2] = custom2
	out[Mesh.ARRAY_TEX_UV] = uv
	out[Mesh.ARRAY_TEX_UV2] = uv2
	out[Mesh.ARRAY_INDEX] = idx
	return out


## Appends one vertex; material weights, snow flag and canopy are averaged
## over the 3x3 samples around it so materials blend across cells.
static func _push_vertex(p: Vector3, nrm: Vector3, x: int, z: int, n: int, water: PackedByteArray, cls: PackedByteArray,
		peaks: PackedFloat32Array, canopy: PackedColorArray, hz: PackedVector2Array,
		verts: PackedVector3Array, norms: PackedVector3Array, colors: PackedColorArray, custom0: PackedFloat32Array,
		custom1: PackedFloat32Array, uv: PackedVector2Array, uv2: PackedVector2Array) -> void:
	var i := x + z * n
	var w := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
	var count := 0.0
	var pk := 0.0
	var cp := Color(0, 0, 0, 0)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var j := clampi(x + dx, 0, n - 1) + clampi(z + dz, 0, n - 1) * n
			if water[j] == 1:
				continue
			w[cls[j]] += 1.0
			pk += peaks[j]
			cp += canopy[j]
			count += 1.0
	if count > 0.0:
		for k in 8:
			w[k] /= count
		pk /= count
		cp /= count
	else:
		w[0] = 1.0
	verts.append(p)
	norms.append(nrm)
	colors.append(Color(w[0], w[1], w[2], w[3]))
	custom0.append_array([w[4], w[5], w[6], w[7]])
	custom1.append_array([cp.r, cp.g, cp.b, cp.a])
	uv.append(Vector2(pk, float(water[i])))
	uv2.append(hz[i])


static func _h_at(heights: PackedFloat32Array, water: PackedByteArray, n: int, x: int, z: int, step: int) -> float:
	return _filtered_height(heights, water, n, clampi(x, 0, n - 1), clampi(z, 0, n - 1), step)


## Fine LOD: the sample itself. Coarse: a tent filter over the coarse cell, so
## ridges are band-limited instead of aliased into spikes; the peak keeps most
## of its height (max-biased) so ranges don't sag in the distance.
static func _filtered_height(heights: PackedFloat32Array, water: PackedByteArray, n: int, x: int, z: int, step: int) -> float:
	if step <= 1:
		return heights[x + z * n]
	var sum := 0.0
	var wsum := 0.0
	var top := -1e9
	var half := maxi(1, step / 2)
	for oz in range(-2, 3):
		for ox in range(-2, 3):
			var sx := clampi(x + ox * half, 0, n - 1)
			var sz := clampi(z + oz * half, 0, n - 1)
			var w := float(3 - absi(ox)) * float(3 - absi(oz))
			var h := heights[sx + sz * n]
			sum += h * w
			wsum += w
			if absi(ox) <= 1 and absi(oz) <= 1:
				top = maxf(top, h)
	var avg := sum / wsum
	if water[x + z * n] == 1 and avg < WATER_Y + 0.5:
		return WATER_Y
	return lerpf(avg, maxf(avg, top), 0.35)


static func _water_quad(a: Vector2, b: Vector2) -> Array:
	var verts := PackedVector3Array([Vector3(a.x, WATER_Y, a.y), Vector3(b.x, WATER_Y, a.y), Vector3(a.x, WATER_Y, b.y), Vector3(b.x, WATER_Y, b.y)])
	return _flat_arrays(verts, PackedInt32Array([0, 1, 2, 1, 3, 2]))


## A wide sea ring around the map so the ocean meets the sky at the horizon.
static func _sea_skirt(size: float) -> Array:
	var far := 12000.0
	var verts := PackedVector3Array([
		Vector3(-far, WATER_Y, -far), Vector3(size + far, WATER_Y, -far), Vector3(size + far, WATER_Y, size + far), Vector3(-far, WATER_Y, size + far),
		Vector3(0, WATER_Y, 0), Vector3(size, WATER_Y, 0), Vector3(size, WATER_Y, size), Vector3(0, WATER_Y, size)])
	var idx := PackedInt32Array()
	for k in 4:
		var o0 := k
		var o1 := (k + 1) % 4
		var i0 := k + 4
		var i1 := (k + 1) % 4 + 4
		idx.append_array([o0, o1, i0, o1, i1, i0])
	return _flat_arrays(verts, idx)


static func _flat_arrays(verts: PackedVector3Array, idx: PackedInt32Array) -> Array:
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	var custom := PackedFloat32Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	for v in verts:
		norms.append(Vector3.UP)
		colors.append(Color(1, 0, 0, 0))
		custom.append_array([0.0, 0.0, 0.0, 0.0])
		uv.append(Vector2(0, 1))
		uv2.append(Vector2(-1, -1))
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = norms
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_CUSTOM0] = custom
	out[Mesh.ARRAY_CUSTOM1] = custom.duplicate()
	var c2 := PackedFloat32Array()
	for v in verts:
		c2.append_array([v.y, 0.0, 1.0, 0.0])
	out[Mesh.ARRAY_CUSTOM2] = c2
	out[Mesh.ARRAY_TEX_UV] = uv
	out[Mesh.ARRAY_TEX_UV2] = uv2
	out[Mesh.ARRAY_INDEX] = idx
	return out


func setup(world_gen: WorldGen, data: Array) -> void:
	gen = world_gen
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://world/materials/distant_land.gdshader")
	TerrainTextures.apply(_mat)
	var codes := PackedInt32Array()
	for c: int in CLASSES:
		codes.append(c)
	_mat.set_shader_parameter(&"class_codes", codes)
	_mat.set_shader_parameter(&"snow_code", Blocks.SNOW)
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
			| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
	if data.size() < 2:
		return
	for t: Array in data[0]:
		var aabb: AABB = t[2]
		var same := is_same(t[0], t[1])
		for lod in (1 if same else 2):
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, t[lod], [], {}, flags)
			mesh.custom_aabb = aabb
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = _mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			if not same:
				# Fine near, filtered far, cross-faded over the margin.
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				if lod == 0:
					mi.visibility_range_end = LOD_DISTANCE
					mi.visibility_range_end_margin = LOD_MARGIN
				else:
					mi.visibility_range_begin = LOD_DISTANCE
					mi.visibility_range_begin_margin = LOD_MARGIN
			add_child(mi)
			_tiles.append(mi)
	var sea := ArrayMesh.new()
	sea.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data[1], [], {}, flags)
	var smi := MeshInstance3D.new()
	smi.mesh = sea
	smi.material_override = _mat
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(smi)


func _process(delta: float) -> void:
	var w := GameWorld.instance
	if w == null or w.local_player == null or _mat == null:
		return
	# Deep underground the horizon cannot be seen; skip drawing it.
	var buried := w.tracker != null and w.tracker.underground and w.tracker.depth > 14.0
	visible = w.local_dimension == gen.dimension and not buried and not _profile_off
	if not visible:
		return
	_coverage_timer -= delta
	if _coverage_timer <= 0.0:
		_coverage_timer = 0.25
		var image := w.world_for(gen.dimension).horizon_coverage()
		if _coverage == null:
			_coverage = ImageTexture.create_from_image(image)
			_mat.set_shader_parameter(&"coverage", _coverage)
			_mat.set_shader_parameter(&"world_size", float(image.get_width() * Chunk.SIZE))
		else:
			_coverage.update(image)
	var pos := w.local_player.global_position
	var cam := w.view.camera if w.view != null else null
	_mat.set_shader_parameter(&"focus", pos)
	# The streamed field is a circle of view_radius chunks around the player's
	# chunk; inside it the horizon is discarded, around its rim it is sunk.
	var stream := float(w.world_for(gen.dimension).view_radius * 16)
	_mat.set_shader_parameter(&"near_radius", maxf(32.0, stream - 40.0))
	_mat.set_shader_parameter(&"near_end", stream + 24.0)
	if w.sky != null:
		var haze: Dictionary = w.sky.haze_params()
		for k: String in haze:
			_mat.set_shader_parameter(StringName(k), haze[k])
	if cam != null:
		_mat.set_shader_parameter(&"cam_height", cam.global_position.y)
