class_name SmoothMesher
extends RefCounted
## Smooth terrain surface for one chunk (runs on worker threads).
##
## Naive Surface Nets over the density field: one vertex per cell that the
## surface crosses (placed at the average of its edge crossings), one quad
## per sign-changing edge. Solidity comes from the block ids (SMOOTH family,
## plus built blocks sunk into the ground), the sub-voxel position from the
## per-voxel density bytes, so the
## surface is exactly consistent with mining, physics and saves.
##
## Samples sit at voxel centres. The chunk owns the cells whose minimum
## corner is in [-1, 15] and the edges that start in [0, 15], so neighbouring
## chunks share identical border vertices and the surface is seamless.
##
## Output vertex format (unindexed triangles, for per-triangle material blending):
##   CUSTOM0.rgb  material codes of the triangle's three corners (block id, or a biome variant code)
##   COLOR.rgb    barycentric selector (1,0,0) / (0,1,0) / (0,0,1)
##   COLOR.a      ambient occlusion
##   UV2.x        skylight 0..1

const P := 18
const P2 := 324
const C := 17      # cells per axis (-1..15)
const C2 := 289

## Material codes above the block id range: biome variants of a block.
const CODE_FOREST_FLOOR := 120
const CODE_HELL_ASH := 121
const CODE_PEAK_GRASS := 122

# Corner k: bit0 = +x, bit1 = +z, bit2 = +y.
const CORNER_OFS := [0, 1, P, P + 1, P2, P2 + 1, P2 + P, P2 + P + 1]
const EDGES := [0, 1, 2, 3, 4, 5, 6, 7, 0, 2, 1, 3, 4, 6, 5, 7, 0, 4, 1, 5, 2, 6, 3, 7]


## neighbours / densities: 27 arrays each (index (dx+1) + (dy+1)*3 + (dz+1)*9); empty block
## arrays are all air, empty density arrays are derived from the blocks.
## surface: 256 column heights (skylight). biomes: 256 biome ids. dim: 0 overworld, 1 hell.
static func build(neighbours: Array, densities: Array, surface: PackedInt32Array, biomes: PackedByteArray, origin: Vector3i, dim: int) -> Dictionary:
	var pb := ChunkMesher.pad_blocks(neighbours)
	var pd := _pad_density(neighbours, densities)
	var fam := Blocks.family_table()
	var smooth_fam := Blocks.Family.SMOOTH

	# Field values and solidity per padded sample.
	var n := P * P * P
	var f := PackedFloat32Array()
	f.resize(n)
	var sol := PackedByteArray()
	sol.resize(n)
	var any_solid := false
	var any_air := false
	var cube_fam := Blocks.Family.CUBE
	var struct_fam := Blocks.Family.STRUCTURE
	for i in n:
		var d := pd[i]
		var fb := fam[pb[i]]
		if fb == smooth_fam:
			sol[i] = 1
			f[i] = float(maxi(d, 128)) / 255.0
			any_solid = true
		elif (fb == cube_fam or fb == struct_fam) and d >= 128:
			# A built block set into the ground (floors, foundations): the ground
			# continues just under it so there are no pits around it.
			sol[i] = 1
			f[i] = 0.52
			any_solid = true
		else:
			f[i] = float(mini(d, 127)) / 255.0
			any_air = true
	var out := {}
	out["trees"] = _find_trees(neighbours[13], pb, f, origin)
	if not any_solid or not any_air:
		return out

	var corner_ofs := PackedInt32Array(CORNER_OFS)
	var edges := PackedInt32Array(EDGES)
	var cpos := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1),
			Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(0, 1, 1), Vector3(1, 1, 1)])

	# --- Vertices: one per active cell ---
	var cell_vid := PackedInt32Array()
	cell_vid.resize(C * C * C)
	cell_vid.fill(-1)
	var vpos := PackedVector3Array()
	var vnrm := PackedVector3Array()
	var vcode := PackedInt32Array()
	var vao := PackedFloat32Array()
	var vsky := PackedFloat32Array()
	var fv := PackedFloat32Array()
	fv.resize(8)
	for cy in C:
		for cz in C:
			var row := cz * P + cy * P2
			for cx in C:
				var base := row + cx
				# Cheap reject: all eight corners on the same side.
				var s0 := sol[base]
				if s0 == sol[base + 1] and s0 == sol[base + P] and s0 == sol[base + P + 1] and s0 == sol[base + P2] \
						and s0 == sol[base + P2 + 1] and s0 == sol[base + P2 + P] and s0 == sol[base + P2 + P + 1]:
					continue
				var sum := 0.0
				for k in 8:
					var v := f[base + corner_ofs[k]]
					fv[k] = v
					sum += v
				var acc := Vector3.ZERO
				var cnt := 0
				for e in 12:
					var a := edges[e * 2]
					var b := edges[e * 2 + 1]
					var fa := fv[a]
					var fb := fv[b]
					if (fa >= 0.5) != (fb >= 0.5):
						var t := clampf((fa - 0.5) / (fa - fb), 0.0, 1.0)
						acc += cpos[a].lerp(cpos[b], t)
						cnt += 1
				var p := acc / float(cnt)
				# Gradient of the trilinear field at the cell: the normal points to lower density.
				var gx := (fv[1] - fv[0]) + (fv[3] - fv[2]) + (fv[5] - fv[4]) + (fv[7] - fv[6])
				var gz := (fv[2] - fv[0]) + (fv[3] - fv[1]) + (fv[6] - fv[4]) + (fv[7] - fv[5])
				var gy := (fv[4] - fv[0]) + (fv[5] - fv[1]) + (fv[6] - fv[2]) + (fv[7] - fv[3])
				var nrm := -Vector3(gx, gy, gz)
				nrm = nrm.normalized() if nrm.length_squared() > 1e-8 else Vector3.UP
				# Material: the highest solid corner (grass over dirt, ceilings over walls).
				var best := -1
				var best_y := -1
				for k in 8:
					var idx := base + corner_ofs[k]
					if sol[idx] == 1:
						var ky := k >> 2
						if ky > best_y:
							best_y = ky
							best = pb[idx]
				# Pad index -> chunk-local: sample i sits at voxel i-1, centre +0.5.
				var local := Vector3(cx - 0.5, cy - 0.5, cz - 0.5) + p
				var code := best
				if best == Blocks.GRASS:
					var bi := biomes[clampi(cx - 1, 0, 15) + clampi(cz - 1, 0, 15) * 16]
					if bi == WorldGen.Biome.FOREST:
						code = CODE_FOREST_FLOOR
					elif bi == WorldGen.Biome.PEAKS:
						code = CODE_PEAK_GRASS
				elif best == Blocks.ASH and dim == 1:
					code = CODE_HELL_ASH
				var sky_h := surface[clampi(cx - 1, 0, 15) + clampi(cz - 1, 0, 15) * 16]
				var wy := float(origin.y) + local.y
				var sky := clampf(1.0 - (float(sky_h) - wy) / 7.0, 0.04, 1.0)
				var avg := sum / 8.0
				cell_vid[cx + cz * C + cy * C2] = vpos.size()
				vpos.append(local)
				vnrm.append(nrm)
				vcode.append(code)
				vao.append(clampf(1.0 - (avg - 0.5) * 1.5, 0.35, 1.0))
				vsky.append(sky)
	if vpos.is_empty():
		return out

	# --- Quads: one per sign-changing edge starting inside the chunk ---
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var custom := PackedFloat32Array()
	var uv2s := PackedVector2Array()
	var f_tris := PackedVector3Array()
	var f_norms := PackedVector3Array()
	var f_blocks := PackedByteArray()
	var f_sky := PackedFloat32Array()
	var quad := PackedInt32Array()
	quad.resize(4)
	for sy in 16:
		for sz in 16:
			for sx in 16:
				var pi := (sx + 1) + (sz + 1) * P + (sy + 1) * P2
				var s_here := sol[pi]
				# axis 0: x, 1: y, 2: z
				for axis in 3:
					var pn := pi + (1 if axis == 0 else (P2 if axis == 1 else P))
					if sol[pn] == s_here:
						continue
					# The four cells around the edge (cell coords = sample coords + 1 - offsets).
					var bx := sx + 1
					var by := sy + 1
					var bz := sz + 1
					if axis == 0:
						quad[0] = cell_vid[bx + bz * C + by * C2]
						quad[1] = cell_vid[bx + (bz - 1) * C + by * C2]
						quad[2] = cell_vid[bx + (bz - 1) * C + (by - 1) * C2]
						quad[3] = cell_vid[bx + bz * C + (by - 1) * C2]
					elif axis == 1:
						quad[0] = cell_vid[bx + bz * C + by * C2]
						quad[1] = cell_vid[(bx - 1) + bz * C + by * C2]
						quad[2] = cell_vid[(bx - 1) + (bz - 1) * C + by * C2]
						quad[3] = cell_vid[bx + (bz - 1) * C + by * C2]
					else:
						quad[0] = cell_vid[bx + bz * C + by * C2]
						quad[1] = cell_vid[(bx - 1) + bz * C + by * C2]
						quad[2] = cell_vid[(bx - 1) + bz * C + (by - 1) * C2]
						quad[3] = cell_vid[bx + bz * C + (by - 1) * C2]
					if quad[0] < 0 or quad[1] < 0 or quad[2] < 0 or quad[3] < 0:
						continue
					var outward := Vector3.ZERO
					outward[axis] = 1.0 if s_here == 1 else -1.0
					var p0 := vpos[quad[0]]
					var p1 := vpos[quad[1]]
					var p2 := vpos[quad[2]]
					var p3 := vpos[quad[3]]
					# Godot front faces are clockwise seen from outside.
					var flip := (p1 - p0).cross(p2 - p0).dot(outward) > 0.0
					# Split along the shorter diagonal.
					var tris: Array
					if p0.distance_squared_to(p2) <= p1.distance_squared_to(p3):
						tris = [0, 1, 2, 0, 2, 3]
					else:
						tris = [0, 1, 3, 1, 2, 3]
					for t in 2:
						var ia := quad[tris[t * 3]]
						var ib := quad[tris[t * 3 + 1]]
						var ic := quad[tris[t * 3 + 2]]
						if flip:
							var tmp := ib
							ib = ic
							ic = tmp
						var pa := vpos[ia]
						var pb2 := vpos[ib]
						var pc := vpos[ic]
						var fn := (pc - pa).cross(pb2 - pa)
						if fn.length_squared() < 1e-10:
							continue
						var ca := float(vcode[ia])
						var cb := float(vcode[ib])
						var cc := float(vcode[ic])
						verts.append(pa)
						verts.append(pb2)
						verts.append(pc)
						norms.append(vnrm[ia])
						norms.append(vnrm[ib])
						norms.append(vnrm[ic])
						cols.append(Color(1, 0, 0, vao[ia]))
						cols.append(Color(0, 1, 0, vao[ib]))
						cols.append(Color(0, 0, 1, vao[ic]))
						for r in 3:
							custom.append(ca)
							custom.append(cb)
							custom.append(cc)
							custom.append(0.0)
						uv2s.append(Vector2(vsky[ia], 0))
						uv2s.append(Vector2(vsky[ib], 0))
						uv2s.append(Vector2(vsky[ic], 0))
						var face_n := fn.normalized()
						if face_n.y > 0.5:
							f_tris.append(pa)
							f_tris.append(pb2)
							f_tris.append(pc)
							f_norms.append(face_n)
							f_blocks.append(_block_of_code(vcode[ia]))
							f_sky.append((vsky[ia] + vsky[ib] + vsky[ic]) / 3.0)
	if verts.is_empty():
		return out
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	out["terrain"] = arrays
	out["flora_surface"] = {"tris": f_tris, "normals": f_norms, "blocks": f_blocks, "sky": f_sky}
	return out


## Mesh format flags for the terrain arrays (CUSTOM0 as four floats).
static func format_flags() -> int:
	return Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT


static func _block_of_code(code: int) -> int:
	match code:
		CODE_FOREST_FLOOR, CODE_PEAK_GRASS:
			return Blocks.GRASS
		CODE_HELL_ASH:
			return Blocks.ASH
	return code


## Tree roots in the centre chunk: the lowest block of each trunk column.
## Returns [Vector3 root (chunk-local, at the smooth ground), kind, height, seed].
static func _find_trees(center: PackedByteArray, pb: PackedByteArray, f: PackedFloat32Array, origin: Vector3i) -> Array:
	var trees: Array = []
	if center.is_empty():
		return trees
	var fam := Blocks.family_table()
	for i in Chunk.VOLUME:
		var b := center[i]
		if b == 0 or fam[b] != Blocks.Family.TREE:
			continue
		var y := i / Chunk.AREA
		var z := (i % Chunk.AREA) / Chunk.SIZE
		var x := i % Chunk.SIZE
		var pi := (x + 1) + (z + 1) * P + (y + 1) * P2
		if pb[pi - P2] == b:
			continue  # not the bottom of the trunk
		# Ground under the trunk: where the field crosses 0.5 between this sample and the one below.
		var fa := f[pi - P2]
		var fb := f[pi]
		var gy := float(y)
		if fa >= 0.5 and fb < 0.5:
			gy = float(y) - 0.5 + clampf((fa - 0.5) / (fa - fb), 0.0, 1.0)
		var info := WorldGen.tree_info(b, origin + Vector3i(x, y, z))
		trees.append([Vector3(x + 0.5, gy, z + 0.5), info[0], info[1], info[2]])
	return trees


static func _pad_density(neighbours: Array, densities: Array) -> PackedByteArray:
	var arrays := []
	arrays.resize(27)
	for i in 27:
		var d: PackedByteArray = densities[i]
		if d.is_empty():
			d = derive_density(neighbours[i])
		arrays[i] = d
	return ChunkMesher.pad_blocks(arrays)


## Density for a chunk that has none stored: fully inside smooth blocks or fully outside.
static func derive_density(blocks: PackedByteArray) -> PackedByteArray:
	if blocks.is_empty():
		return PackedByteArray()
	var out := PackedByteArray()
	out.resize(Chunk.VOLUME)
	var fam := Blocks.family_table()
	if fam[blocks[0]] == Blocks.Family.SMOOTH and blocks.count(blocks[0]) == Chunk.VOLUME:
		out.fill(255)
		return out
	for i in Chunk.VOLUME:
		if fam[blocks[i]] == Blocks.Family.SMOOTH:
			out[i] = 255
	return out
