class_name ChunkMesher
extends RefCounted
## Builds the mesh arrays for one chunk (runs on worker threads).
##
## Input: the chunk's 26 neighbours are folded into an 18^3 padded block
## array so faces on chunk borders are culled correctly and ambient
## occlusion can look one block outside.
## Output: up to two surfaces, opaque blocks and liquids.
##
## Per vertex: COLOR.rgb = ambient occlusion (cube faces) or colour (torches, liquids), COLOR.a = ASCII
## material class / 7, UV = position on the face (for edge shading),
## UV2 = (block id, skylight).
## Liquid top faces instead carry UV = (water depth under the corner in metres, 0): 0 on
## the shore, so the wave shader can calm the swell there and let it shoal in the shallows.
## Water also gets a "shore skirt": its surface continues one cell into the solid ground
## around it, so the water's edge is wherever the smooth terrain rises through the surface
## (the shader fades it out by depth) instead of a stair-stepped voxel outline.

const P := 18
const P2 := 324
const AO_CURVE := [0.42, 0.62, 0.8, 1.0]
## Drawn height of a water surface above its top block's base (the swim physics use it too).
## The generator floods a column when its ground (the smooth surface, at the column height
## + 0.5..1.5) is below the half block, so the surface at +0.5 meets the terrain exactly
## where the water blocks end; any higher and dry land next to the water would sit under it.
const WATER_TOP := 0.5

static var _face_corners: Array = []  # [dir] -> Array of 4 Vector3
static var _face_ao: Array = []       # [dir] -> PackedInt32Array 12 deltas (side1, side2, corner) x4
static var _normal_delta := PackedInt32Array()
static var _normals: Array[Vector3] = []


static func _static_init() -> void:
	var dirs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	for d: Vector3i in dirs:
		var axis := 0 if d.x != 0 else (1 if d.y != 0 else 2)
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		var corners: Array[Vector3] = []
		var ao := PackedInt32Array()
		for c: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
			var pos := Vector3.ZERO
			pos[axis] = 1.0 if (d[axis] > 0) else 0.0
			pos[u] = c.x
			pos[v] = c.y
			corners.append(pos)
			var su := Vector3i.ZERO
			su[u] = 1 if c.x == 1 else -1
			var sv := Vector3i.ZERO
			sv[v] = 1 if c.y == 1 else -1
			ao.append(_delta(d + su))
			ao.append(_delta(d + sv))
			ao.append(_delta(d + su + sv))
		# Godot treats clockwise triangles (seen from outside) as front faces.
		var n := Vector3(d)
		var cross := (corners[1] - corners[0]).cross(corners[2] - corners[0])
		if cross.dot(n) > 0.0:
			corners.reverse()
			var rev := PackedInt32Array()
			for i in [3, 2, 1, 0]:
				rev.append_array(ao.slice(i * 3, i * 3 + 3))
			ao = rev
		_face_corners.append(corners)
		_face_ao.append(ao)
		_normal_delta.append(_delta(d))
		_normals.append(n)


static func _delta(o: Vector3i) -> int:
	return o.x + o.z * P + o.y * P2


## neighbours: Array of 27 PackedByteArray (index (dx+1) + (dy+1)*3 + (dz+1)*9),
## empty arrays meaning all air. surface: 256 column heights for skylight.
## ground: 17x17 generated ground heights at the chunk's column corners (index cx + cz * 17,
## empty = unknown), used for the water depth that shapes the waves.
static func build(neighbours: Array, surface: PackedInt32Array, origin_y: int, ground := PackedFloat32Array()) -> Dictionary:
	var pad := pad_blocks(neighbours)
	var opaque := _occluders()
	var family := Blocks.family_table()
	var liquid := Blocks.liquid_table()
	var classes := Blocks.class_table()
	var colors := Blocks.color_table()

	# Flattened lookup tables (locals are much faster than statics in GDScript).
	var nd := _normal_delta
	var aod := PackedInt32Array()
	var corner := PackedVector3Array()
	for d in 6:
		aod.append_array(_face_ao[d])
		for c in 4:
			corner.append(_face_corners[d][c])
	var normals := PackedVector3Array(_normals)
	var curve := PackedFloat32Array(AO_CURVE)
	var uv0 := Vector2(0, 0)
	var uv1 := Vector2(1, 0)
	var uv2 := Vector2(1, 1)
	var uv3 := Vector2(0, 1)

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()

	var l_verts := PackedVector3Array()
	var l_norms := PackedVector3Array()
	var l_cols := PackedColorArray()
	var l_uvs := PackedVector2Array()
	var l_uv2s := PackedVector2Array()
	var l_idx := PackedInt32Array()

	for y in Chunk.SIZE:
		var wy := origin_y + y
		for z in Chunk.SIZE:
			var base := (z + 1) * P + (y + 1) * P2 + 1
			for x in Chunk.SIZE:
				var pi := base + x
				var b := pad[pi]
				if b == 0:
					continue
				# Smooth terrain and trees are drawn elsewhere.
				var fam := family[b]
				if fam != Blocks.Family.CUBE and fam != Blocks.Family.SMALL and fam != Blocks.Family.LIQUID:
					continue
				# Fully buried opaque blocks are the common case: skip fast.
				if opaque[b] == 1 and opaque[pad[pi + 1]] == 1 and opaque[pad[pi - 1]] == 1 and opaque[pad[pi + P2]] == 1 \
						and opaque[pad[pi - P2]] == 1 and opaque[pad[pi + P]] == 1 and opaque[pad[pi - P]] == 1:
					continue
				var sky_h := surface[x + z * Chunk.SIZE]
				var sky := clampf(1.0 - float(sky_h - wy - 1) / 7.0, 0.04, 1.0)
				var col := colors[b]
				var cls := float(classes[b]) / 7.0
				var bpos := Vector3(x, y, z)
				if Blocks.shape(b) == Blocks.Shape.SMALL:
					_small(b, bpos, col, cls, sky, verts, norms, cols, uvs, uv2s, idx)
					continue
				var is_liquid := liquid[b] == 1
				var bid := Vector2(b, sky)
				for d in 6:
					var n := pad[pi + nd[d]]
					if is_liquid:
						if n == b or opaque[n] == 1 or liquid[n] == 1:
							continue
						if d != 2 and n != 0:
							continue
					elif opaque[n] == 1:
						continue
					var o0 := 3
					var o1 := 3
					var o2 := 3
					var o3 := 3
					if not is_liquid:
						var ab := d * 12
						var s1 := opaque[pad[pi + aod[ab]]]
						var s2 := opaque[pad[pi + aod[ab + 1]]]
						o0 = 0 if s1 + s2 == 2 else 3 - (s1 + s2 + opaque[pad[pi + aod[ab + 2]]])
						s1 = opaque[pad[pi + aod[ab + 3]]]
						s2 = opaque[pad[pi + aod[ab + 4]]]
						o1 = 0 if s1 + s2 == 2 else 3 - (s1 + s2 + opaque[pad[pi + aod[ab + 5]]])
						s1 = opaque[pad[pi + aod[ab + 6]]]
						s2 = opaque[pad[pi + aod[ab + 7]]]
						o2 = 0 if s1 + s2 == 2 else 3 - (s1 + s2 + opaque[pad[pi + aod[ab + 8]]])
						s1 = opaque[pad[pi + aod[ab + 9]]]
						s2 = opaque[pad[pi + aod[ab + 10]]]
						o3 = 0 if s1 + s2 == 2 else 3 - (s1 + s2 + opaque[pad[pi + aod[ab + 11]]])
					var nrm := normals[d]
					var cb := d * 4
					var fsky := bid if d != 3 else Vector2(b, sky * 0.6)
					var a0 := curve[o0]
					var a1 := curve[o1]
					var a2 := curve[o2]
					var a3 := curve[o3]
					var start: int
					if is_liquid:
						start = l_verts.size()
						# Top faces sit at the water surface; side faces (falls, drop-offs)
						# end there too unless more water stands on top.
						var top_open := liquid[pad[pi + P2]] == 0
						for i in 4:
							var cv := corner[cb + i]
							if cv.y > 0.5 and (d == 2 or top_open):
								cv.y = WATER_TOP
							l_verts.append(bpos + cv)
						for i in 4:
							l_norms.append(nrm)
							l_cols.append(Color(col.r, col.g, col.b, cls))
							l_uv2s.append(fsky)
						if d == 2:
							for i in 4:
								var cv := corner[cb + i]
								l_uvs.append(Vector2(_corner_depth(pad, pi, b, int(cv.x), int(cv.z), x, z, wy, ground), 0.0))
						else:
							l_uvs.append(uv0)
							l_uvs.append(uv1)
							l_uvs.append(uv2)
							l_uvs.append(uv3)
						l_idx.append_array([start, start + 1, start + 2, start, start + 2, start + 3])
						if d == 2:
							# Seen from below too (inside caves, underwater).
							l_idx.append_array([start, start + 2, start + 1, start, start + 3, start + 2])
						continue
					start = verts.size()
					verts.append(bpos + corner[cb])
					verts.append(bpos + corner[cb + 1])
					verts.append(bpos + corner[cb + 2])
					verts.append(bpos + corner[cb + 3])
					norms.append(nrm)
					norms.append(nrm)
					norms.append(nrm)
					norms.append(nrm)
					# Textured faces: COLOR.rgb carries only the ambient occlusion.
					cols.append(Color(a0, a0, a0, cls))
					cols.append(Color(a1, a1, a1, cls))
					cols.append(Color(a2, a2, a2, cls))
					cols.append(Color(a3, a3, a3, cls))
					uvs.append(uv0)
					uvs.append(uv1)
					uvs.append(uv2)
					uvs.append(uv3)
					uv2s.append(fsky)
					uv2s.append(fsky)
					uv2s.append(fsky)
					uv2s.append(fsky)
					if o0 + o2 < o1 + o3:
						idx.append_array([start + 1, start + 2, start + 3, start + 1, start + 3, start])
					else:
						idx.append_array([start, start + 1, start + 2, start, start + 2, start + 3])
	if pad.has(Blocks.WATER):
		_shore_skirt(pad, surface, origin_y, opaque, liquid, corner, l_verts, l_norms, l_cols, l_uvs, l_uv2s, l_idx)
	var out := {}
	if not verts.is_empty():
		out["opaque"] = _arrays(verts, norms, cols, uvs, uv2s, idx)
	if not l_verts.is_empty():
		out["liquid"] = _arrays(l_verts, l_norms, l_cols, l_uvs, l_uv2s, l_idx)
	return out


static func _arrays(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, u: PackedVector2Array, u2: PackedVector2Array, i: PackedInt32Array) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_TEX_UV] = u
	arrays[Mesh.ARRAY_TEX_UV2] = u2
	arrays[Mesh.ARRAY_INDEX] = i
	return arrays


## Water depth (m) under the top-face corner (cx, cz in 0/1) of the liquid cell at pad index
## pi: 0 unless all four cells around the corner are this liquid (the shoreline), else the
## depth to the generated ground (at least 1 m: dug pools, caves). Only pad data and world
## columns go in, so neighbouring chunks agree on shared corners.
static func _corner_depth(pad: PackedByteArray, pi: int, b: int, cx: int, cz: int, x: int, z: int, wy: int, ground: PackedFloat32Array) -> float:
	var c := pi + (cx - 1) + (cz - 1) * P
	if pad[c] != b or pad[c + 1] != b or pad[c + P] != b or pad[c + P + 1] != b:
		return 0.0
	if ground.is_empty():
		return 4.0
	return clampf(float(wy) + WATER_TOP - ground[(x + cx) + (z + cz) * (Chunk.SIZE + 1)], 1.0, 40.0)


## The water surface continued over the solid cells next to open water (8-neighbours on
## the same level), at the same height, with depth 0 so no waves lift it. The smooth
## terrain hides it wherever the ground is above the water; where the ground dips below
## the water level inside such a cell the water now covers it, so the visible shoreline
## follows the terrain contour (softened by the shader's depth fade), not the voxel grid.
## Water cells in the pad border count too, so skirts match across chunk borders.
static func _shore_skirt(pad: PackedByteArray, surface: PackedInt32Array, origin_y: int, opaque: PackedByteArray, liquid: PackedByteArray,
		corner: PackedVector3Array, l_verts: PackedVector3Array, l_norms: PackedVector3Array, l_cols: PackedColorArray,
		l_uvs: PackedVector2Array, l_uv2s: PackedVector2Array, l_idx: PackedInt32Array) -> void:
	var w := Blocks.WATER
	var family := Blocks.family_table()
	var mark := PackedByteArray()
	mark.resize(Chunk.VOLUME)
	var any := false
	for y in Chunk.SIZE:
		for pz in P:
			var row := pz * P + (y + 1) * P2
			for px in P:
				var pi := row + px
				if pad[pi] != w:
					continue
				var up := pad[pi + P2]
				if up == w or opaque[up] == 1 or liquid[up] == 1:
					continue
				for dz in range(-1, 2):
					var nz := pz - 1 + dz
					if nz < 0 or nz >= Chunk.SIZE:
						continue
					for dx in range(-1, 2):
						var nx := px - 1 + dx
						if nx < 0 or nx >= Chunk.SIZE:
							continue
						var ni := pi + dx + dz * P
						# Only ground: a plant or torch cell stands on lower ground.
						var c := pad[ni]
						if family[c] != Blocks.Family.SMOOTH and opaque[c] == 0:
							continue
						var above := pad[ni + P2]
						if liquid[above] == 1 or opaque[above] == 1:
							continue
						mark[nx + nz * Chunk.SIZE + y * Chunk.AREA] = 1
						any = true
	if not any:
		return
	var cb := 2 * 4
	var lift := Vector3(0, WATER_TOP - 1.0, 0)
	var nrm := Vector3.UP
	var col: Color = Blocks.color_table()[w]
	var cls := float(Blocks.class_table()[w]) / 7.0
	var zero := Vector2.ZERO
	for i in Chunk.VOLUME:
		if mark[i] == 0:
			continue
		var x := i % Chunk.SIZE
		var z := (i / Chunk.SIZE) % Chunk.SIZE
		var y := i / Chunk.AREA
		var sky := clampf(1.0 - float(surface[x + z * Chunk.SIZE] - (origin_y + y) - 1) / 7.0, 0.04, 1.0)
		var bpos := Vector3(x, y, z) + lift
		var start := l_verts.size()
		for c in 4:
			l_verts.append(bpos + corner[cb + c])
			l_norms.append(nrm)
			l_cols.append(Color(col.r, col.g, col.b, cls))
			l_uvs.append(zero)
			l_uv2s.append(Vector2(w, sky))
		l_idx.append_array([start, start + 1, start + 2, start, start + 2, start + 3])
		l_idx.append_array([start, start + 2, start + 1, start, start + 3, start + 2])


## Faces are hidden only behind other crisp cubes: smooth terrain may not
## reach a voxel's face, so cubes next to it keep their faces.
static var _occl := PackedByteArray()


static func _occluders() -> PackedByteArray:
	if _occl.is_empty():
		var t := PackedByteArray()
		t.resize(256)
		var opaque := Blocks.opaque_table()
		var family := Blocks.family_table()
		for i in 256:
			t[i] = 1 if opaque[i] == 1 and family[i] == Blocks.Family.CUBE else 0
		_occl = t
	return _occl


## Torches and lanterns: a small box in the middle of the block.
static func _small(b: int, p: Vector3, col: Color, cls: float, sky: float, verts: PackedVector3Array, norms: PackedVector3Array,
		cols: PackedColorArray, uvs: PackedVector2Array, uv2s: PackedVector2Array, idx: PackedInt32Array) -> void:
	var half := Vector3(0.09, 0.32, 0.09) if b == Blocks.TORCH else Vector3(0.22, 0.3, 0.22)
	var center := p + Vector3(0.5, half.y if b == Blocks.TORCH else 0.35, 0.5)
	for d in 6:
		var corners: Array = _face_corners[d]
		var start := verts.size()
		for c in 4:
			var cv: Vector3 = corners[c]
			verts.append(center + (cv * 2.0 - Vector3.ONE) * half)
			norms.append(_normals[d])
			cols.append(Color(col.r, col.g, col.b, cls))
			uvs.append(Vector2(c & 1, c >> 1))
			uv2s.append(Vector2(b, sky))
		idx.append_array([start, start + 1, start + 2, start, start + 2, start + 3])


static func pad_blocks(neighbours: Array) -> PackedByteArray:
	var pad := PackedByteArray()
	pad.resize(P * P * P)
	for dz in range(-1, 2):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var data: PackedByteArray = neighbours[(dx + 1) + (dy + 1) * 3 + (dz + 1) * 9]
				if data.is_empty():
					continue
				# Source range inside the neighbour, destination inside the pad.
				var sx0 := 15 if dx < 0 else 0
				var sx1 := 0 if dx > 0 else 15
				if dx == 0:
					sx0 = 0
					sx1 = 15
				var sy0 := 15 if dy < 0 else 0
				var sy1 := 0 if dy > 0 else 15
				if dy == 0:
					sy0 = 0
					sy1 = 15
				var sz0 := 15 if dz < 0 else 0
				var sz1 := 0 if dz > 0 else 15
				if dz == 0:
					sz0 = 0
					sz1 = 15
				for sy in range(sy0, sy1 + 1):
					var py := sy + 1 + dy * 16
					for sz in range(sz0, sz1 + 1):
						var pz := sz + 1 + dz * 16
						var src_row := sz * 16 + sy * 256
						var dst_row := pz * P + py * P2 + 1 + dx * 16
						if dx == 0:
							# Whole row: copy 16 bytes at once.
							var row := data.slice(src_row, src_row + 16)
							for i in 16:
								pad[dst_row + i] = row[i]
						else:
							for sx in range(sx0, sx1 + 1):
								pad[dst_row + sx] = data[src_row + sx]
	return pad
