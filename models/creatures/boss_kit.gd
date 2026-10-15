class_name BossKit
extends RefCounted
## Building blocks for the bespoke boss models (Warden, Mountain King, Hades,
## Old Mother Mire, the Ryft bosses):
##   * materials on one shared surface shader (boss_surface.gdshader): plate
##     metal, cloth, stone skin, crystal, void, bone, leather, skin, fur, wood
##   * mesh builders that OrganicMesh lacks: lathe (revolved profiles: helms,
##     crowns, lanterns), shell (curved armour plates with thickness and a
##     rolled rim), blade (flat-faceted edged weapons), crystal (faceted
##     prisms), torus (rings, chain links), ribbon (hanging cloth strips)
##   * Assembly: parts collected with transforms and per-part tints, merged
##     into one mesh per material and cached, so a boss of a hundred parts
##     draws with a couple of dozen draw calls and the second spawn is free
##   * skinned cloth: cloaks bound to the HumanoidModel's simulated cloak bones
##     and robes bound to the hips and legs
## All meshes are cached by key. Tints are sRGB colours; tint alpha 0 marks a
## part that carries glowing runes.

const SURFACE := preload("res://models/creatures/boss_surface.gdshader")
enum Mode { METAL, CLOTH, ROCK, CRYSTAL, VOID, BONE, LEATHER, SKIN, FUR, WOOD }

static var _mats := {}
static var _meshes := {}
static var _baked := {}


# --- Materials ----------------------------------------------------------------------

static func surface(mode: int, params := {}) -> ShaderMaterial:
	var key := "%d|%s" % [mode, str(params)]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = SURFACE
	m.set_shader_parameter(&"mode", mode)
	if not params.has("ascii_id"):
		m.set_shader_parameter(&"ascii_id", AsciiMaterialId.CLOTH if mode in [Mode.CLOTH, Mode.FUR] else AsciiMaterialId.SOLID)
	for k: String in params:
		m.set_shader_parameter(StringName(k), params[k])
	_mats[key] = m
	return m


static func _with(base: Dictionary, extra: Dictionary) -> Dictionary:
	var p := base.duplicate()
	p.merge(extra, true)
	return p


## Plate metal; colour comes from the part tints (albedo multiplies them).
static func metal(extra := {}) -> ShaderMaterial:
	return surface(Mode.METAL, _with({"albedo": Color(1, 1, 1), "metallic": 0.7, "roughness": 0.42, "wear": 0.45,
		"grime": 0.35, "pattern_scale": 14.0}, extra))


## Cloth: `color` is the albedo (skinned cloth has no vertex tints; merged
## parts multiply theirs in), `color2` the faded / stained variation.
static func cloth(color: Color, color2: Color, extra := {}) -> ShaderMaterial:
	return surface(Mode.CLOTH, _with({"albedo": color, "albedo2": color2, "grime": 0.5, "pattern_scale": 8.0}, extra))


static func rock(color2 := Color(0.3, 0.32, 0.3), extra := {}) -> ShaderMaterial:
	return surface(Mode.ROCK, _with({"albedo": Color(1, 1, 1), "albedo2": color2, "pattern_scale": 9.0, "bump": 1.6}, extra))


static func crystal(color2: Color, glow_color: Color, glow := 0.6, extra := {}) -> ShaderMaterial:
	return surface(Mode.CRYSTAL, _with({"albedo": Color(1, 1, 1), "albedo2": color2, "glow_color": glow_color, "glow": glow,
		"pattern_scale": 5.0, "bump": 0.2}, extra))


static func abyss(glow_color: Color, color2: Color, glow := 0.8, extra := {}) -> ShaderMaterial:
	return surface(Mode.VOID, _with({"albedo": Color(0.05, 0.04, 0.08), "albedo2": color2, "glow_color": glow_color, "glow": glow,
		"bump": 0.0, "rim": 0.0}, extra))


static func bone(extra := {}) -> ShaderMaterial:
	return surface(Mode.BONE, _with({"albedo": Color(1, 1, 1), "grime": 0.6, "pattern_scale": 14.0}, extra))


static func leather(extra := {}) -> ShaderMaterial:
	return surface(Mode.LEATHER, _with({"albedo": Color(1, 1, 1), "pattern_scale": 16.0}, extra))


static func skin(color2: Color, extra := {}) -> ShaderMaterial:
	return surface(Mode.SKIN, _with({"albedo": Color(1, 1, 1), "albedo2": color2, "pattern_scale": 12.0, "bump": 0.6}, extra))


static func fur(color2: Color, extra := {}) -> ShaderMaterial:
	return surface(Mode.FUR, _with({"albedo": Color(1, 1, 1), "albedo2": color2, "pattern_scale": 16.0, "bump": 1.4}, extra))


static func wood(color2: Color, extra := {}) -> ShaderMaterial:
	return surface(Mode.WOOD, _with({"albedo": Color(1, 1, 1), "albedo2": color2, "pattern_scale": 14.0, "bump": 1.2}, extra))


static func glow(color: Color, energy := 5.0, pulse := 0.0) -> ShaderMaterial:
	return ModelKit.glow(color, energy, pulse)


# --- Assemblies -----------------------------------------------------------------------

## Parts collected for one node (usually one bone), merged per material.
class Assembly:
	extends RefCounted
	var parts: Array = []   # [mesh, material, Transform3D, Color]

	func add(mesh: Mesh, mat: Material, xform := Transform3D.IDENTITY, tint := Color(1, 1, 1)) -> Assembly:
		parts.append([mesh, mat, xform, tint])
		return self

	## Place a part at `pos` (rotation in degrees, XYZ order like Node3D) with a scale.
	func put(mesh: Mesh, mat: Material, pos: Vector3, rot_deg := Vector3.ZERO, scl := Vector3.ONE, tint := Color(1, 1, 1)) -> Assembly:
		var b := Basis.from_euler(rot_deg * (PI / 180.0)).scaled_local(scl) if scl != Vector3.ONE else Basis.from_euler(rot_deg * (PI / 180.0))
		parts.append([mesh, mat, Transform3D(b, pos), tint])
		return self

	## Mirror every part across the YZ plane (x -> -x): build one side, get both.
	func mirrored_x() -> Assembly:
		var out := Assembly.new()
		var m := Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)), Vector3.ZERO)
		for p: Array in parts:
			out.parts.append([p[0], p[1], m * (p[2] as Transform3D), p[3]])
		return out

	func append(other: Assembly) -> Assembly:
		parts.append_array(other.parts)
		return self

	func transformed(xf: Transform3D) -> Assembly:
		var out := Assembly.new()
		for p: Array in parts:
			out.parts.append([p[0], p[1], xf * (p[2] as Transform3D), p[3]])
		return out


static func assembly() -> Assembly:
	return Assembly.new()


## Merge an assembly into [[ArrayMesh, Material], ...] (one per material), cached by key.
static func bake(key: String, asm: Assembly) -> Array:
	if _baked.has(key):
		return _baked[key]
	var groups := {}
	var order: Array = []
	for part: Array in asm.parts:
		var mat: Material = part[1]
		if not groups.has(mat):
			groups[mat] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(),
				"uv2": PackedVector2Array(), "c": PackedColorArray(), "i": PackedInt32Array()}
			order.append(mat)
		_append(groups[mat], part[0], part[2], part[3])
	var out: Array = []
	for mat: Material in order:
		var g: Dictionary = groups[mat]
		if (g["v"] as PackedVector3Array).is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g["v"]
		arrays[Mesh.ARRAY_NORMAL] = g["n"]
		arrays[Mesh.ARRAY_TEX_UV] = g["uv"]
		arrays[Mesh.ARRAY_TEX_UV2] = g["uv2"]
		arrays[Mesh.ARRAY_COLOR] = g["c"]
		arrays[Mesh.ARRAY_INDEX] = g["i"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.append([mesh, mat])
	_baked[key] = out
	return out


static func _append(g: Dictionary, mesh: Mesh, xf: Transform3D, tint: Color) -> void:
	# Packed arrays are values: take them out, grow them, put them back.
	var gv: PackedVector3Array = g["v"]
	var gn: PackedVector3Array = g["n"]
	var guv: PackedVector2Array = g["uv"]
	var guv2: PackedVector2Array = g["uv2"]
	var gc: PackedColorArray = g["c"]
	var gi: PackedInt32Array = g["i"]
	var lin := tint.srgb_to_linear()
	lin.a = tint.a
	var flip := xf.basis.determinant() < 0.0
	var nxf := Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO)
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var count := v.size()
		if count == 0:
			continue
		var base := gv.size()
		gv.append_array(xf * v)
		var n: Variant = arr[Mesh.ARRAY_NORMAL]
		if n is PackedVector3Array and (n as PackedVector3Array).size() == count:
			gn.append_array(nxf * (n as PackedVector3Array))
		else:
			var up := PackedVector3Array()
			up.resize(count)
			up.fill(xf.basis.y.normalized())
			gn.append_array(up)
		var uv: Variant = arr[Mesh.ARRAY_TEX_UV]
		if uv is PackedVector2Array and (uv as PackedVector2Array).size() == count:
			guv.append_array(uv)
		else:
			var z := PackedVector2Array()
			z.resize(count)
			guv.append_array(z)
		var uv2: Variant = arr[Mesh.ARRAY_TEX_UV2]
		if uv2 is PackedVector2Array and (uv2 as PackedVector2Array).size() == count:
			guv2.append_array(uv2)
		else:
			var z2 := PackedVector2Array()
			z2.resize(count)
			guv2.append_array(z2)
		var cols := PackedColorArray()
		cols.resize(count)
		cols.fill(lin)
		var src_c: Variant = arr[Mesh.ARRAY_COLOR]
		if src_c is PackedColorArray and (src_c as PackedColorArray).size() == count:
			var sc: PackedColorArray = src_c
			for i in count:
				cols[i] = lin * sc[i]
		gc.append_array(cols)
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
			var ii: PackedInt32Array = idx
			var start := gi.size()
			gi.resize(start + ii.size())
			if flip:
				for t in range(0, ii.size(), 3):
					gi[start + t] = ii[t] + base
					gi[start + t + 1] = ii[t + 2] + base
					gi[start + t + 2] = ii[t + 1] + base
			else:
				for t in ii.size():
					gi[start + t] = ii[t] + base
		else:
			var start := gi.size()
			gi.resize(start + count)
			for t in range(0, count - 2, 3):
				gi[start + t] = base + t
				gi[start + t + 1] = base + (t + 2 if flip else t + 1)
				gi[start + t + 2] = base + (t + 1 if flip else t + 2)
	g["v"] = gv
	g["n"] = gn
	g["uv"] = guv
	g["uv2"] = guv2
	g["c"] = gc
	g["i"] = gi


## Bake `asm` and add one MeshInstance3D per material under `parent`.
static func instance(parent: Node3D, key: String, asm: Assembly, cast_shadows := true) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for entry: Array in bake(key, asm):
		var mi := MeshInstance3D.new()
		mi.mesh = entry[0]
		mi.material_override = entry[1]
		var sm := entry[1] as ShaderMaterial
		if not cast_shadows or (sm != null and sm.shader == ModelKit.GLOW):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		out.append(mi)
	return out


static func is_baked(key: String) -> bool:
	return _baked.has(key)


# --- Mesh builders ---------------------------------------------------------------------

## Surface of revolution about +Y. `prof` rows are (radius, y) from bottom to top.
## sx / sz squash the circle into an ellipse; `sides` around. Smooth normals.
## `uv2_v`: write the profile parameter (0 at the first row .. 1 at the last) in UV2.y.
static func lathe(key: String, prof: PackedVector2Array, sides := 16, sx := 1.0, sz := 1.0, cap_bottom := false, cap_top := false) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var rows := prof.size()
	var ring := sides + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var along := 0.0
	for i in rows:
		if i > 0:
			along += prof[i].distance_to(prof[i - 1])
		var a := prof[maxi(0, i - 1)]
		var b := prof[mini(rows - 1, i + 1)]
		var t := (b - a)
		var n2 := Vector2(t.y, -t.x).normalized() if t.length_squared() > 1e-10 else Vector2(1, 0)
		for j in ring:
			var th := TAU * float(j) / sides
			var c := cos(th)
			var s := sin(th)
			verts.append(Vector3(s * prof[i].x * sx, prof[i].y, -c * prof[i].x * sz))
			normals.append(Vector3(s * n2.x / maxf(sx, 0.01), n2.y, -c * n2.x / maxf(sz, 0.01)).normalized())
			uvs.append(Vector2(float(j) / sides * TAU * maxf(prof[i].x, 0.05), along))
			uv2s.append(Vector2(0.0, float(i) / maxf(1.0, rows - 1)))
	var idx := PackedInt32Array()
	for i in rows - 1:
		for j in sides:
			var a := i * ring + j
			var b := i * ring + j + 1
			var c := (i + 1) * ring + j + 1
			var d := (i + 1) * ring + j
			OrganicMesh._tri_out(idx, verts, normals, a, b, c)
			OrganicMesh._tri_out(idx, verts, normals, a, c, d)
	for end in 2:
		if (end == 0 and not cap_bottom) or (end == 1 and not cap_top):
			continue
		var i := 0 if end == 0 else rows - 1
		var pole := verts.size()
		var dir := Vector3.DOWN if end == 0 else Vector3.UP
		verts.append(Vector3(0, prof[i].y, 0))
		normals.append(dir)
		uvs.append(Vector2.ZERO)
		uv2s.append(Vector2(0.0, float(i) / maxf(1.0, rows - 1)))
		var first := verts.size()
		for j in ring:
			verts.append(verts[i * ring + j])
			normals.append(dir)
			uvs.append(uvs[i * ring + j])
			uv2s.append(uv2s[i * ring + j])
		for j in sides:
			OrganicMesh._tri_out(idx, verts, normals, pole, first + j, first + j + 1)
	var mesh := _commit(verts, normals, uvs, idx, uv2s)
	_meshes[key] = mesh
	return mesh


## A curved armour plate: the patch of an ellipsoid (radii) between azimuths
## az0..az1 (degrees about +Y, 0 = front -Z, 90 = right +X) and polar angles
## pol0..pol1 (degrees from +Y), with `thick` thickness and a rolled rim.
static func shell(key: String, radii: Vector3, az0: float, az1: float, pol0: float, pol1: float, thick := 0.03, seg_az := 12, seg_pol := 8) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var inner := radii - Vector3.ONE * thick
	var na := seg_az + 1
	var np := seg_pol + 1
	for layer in 2:
		var r := radii if layer == 0 else inner
		for i in np:
			var pol := deg_to_rad(lerpf(pol0, pol1, float(i) / seg_pol))
			for j in na:
				var az := deg_to_rad(lerpf(az0, az1, float(j) / seg_az))
				var d := Vector3(sin(pol) * sin(az), cos(pol), -sin(pol) * cos(az))
				var p := d * r
				var n := Vector3(d.x / maxf(r.x, 0.001), d.y / maxf(r.y, 0.001), d.z / maxf(r.z, 0.001)).normalized()
				verts.append(p)
				normals.append(n if layer == 0 else -n)
				uvs.append(Vector2(deg_to_rad(lerpf(az0, az1, float(j) / seg_az)) * r.x, deg_to_rad(lerpf(pol0, pol1, float(i) / seg_pol)) * r.y))
	var off := np * na
	for layer in 2:
		var o := 0 if layer == 0 else off
		for i in seg_pol:
			for j in seg_az:
				var a := o + i * na + j
				var b := o + i * na + j + 1
				var c := o + (i + 1) * na + j + 1
				var d := o + (i + 1) * na + j
				OrganicMesh._tri_out(idx, verts, normals, a, b, c)
				OrganicMesh._tri_out(idx, verts, normals, a, c, d)
	# Rim: join the outer and inner edges with an outward-facing strip.
	var edges: Array = []
	for j in seg_az:
		edges.append([j, j + 1])                                   # top edge (pol0)
		edges.append([seg_pol * na + j, seg_pol * na + j + 1])     # bottom edge (pol1)
	for i in seg_pol:
		edges.append([i * na, (i + 1) * na])                       # az0 side
		edges.append([i * na + seg_az, (i + 1) * na + seg_az])     # az1 side
	var centre := Vector3.ZERO
	for k in off:
		centre += verts[k]
	centre /= float(off)
	for e: Array in edges:
		var a: int = e[0]
		var b: int = e[1]
		var pa := verts[a]
		var pb := verts[b]
		var ia := verts[a + off]
		var ib := verts[b + off]
		var mid := (pa + pb) * 0.5
		var outward := (mid - centre)
		var edge_dir := (pb - pa).normalized()
		var across := (pa - ia).normalized()
		var n := edge_dir.cross(across).normalized()
		if n.dot(outward) < 0.0:
			n = -n
		var base := verts.size()
		for q: Vector3 in [pa, pb, ib, ia]:
			verts.append(q)
			normals.append(n)
			uvs.append(Vector2(q.x + q.z, q.y))
		OrganicMesh._tri_out(idx, verts, normals, base, base + 1, base + 2)
		OrganicMesh._tri_out(idx, verts, normals, base, base + 2, base + 3)
	var mesh := _commit(verts, normals, uvs, idx)
	_meshes[key] = mesh
	return mesh


## A plate of armour from cross-section rows: `rows` is an Array of
## PackedVector3Array, all the same length, each a polyline across the plate
## (e.g. left to right), listed top to bottom. The surface gets `thick`
## thickness inward (towards `inside`, a point inside the body) and a rim, so
## crests, ridges and flares can be drawn exactly. Smooth normals.
static func plate(key: String, rows: Array, thick := 0.02, inside := Vector3.ZERO) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var nr := rows.size()
	var nc := (rows[0] as PackedVector3Array).size()
	var outer := PackedVector3Array()
	for r in nr:
		outer.append_array(rows[r])
	var onorm := PackedVector3Array()
	onorm.resize(nr * nc)
	for r in nr:
		for c in nc:
			var du := outer[r * nc + mini(nc - 1, c + 1)] - outer[r * nc + maxi(0, c - 1)]
			var dv := outer[mini(nr - 1, r + 1) * nc + c] - outer[maxi(0, r - 1) * nc + c]
			var n := du.cross(dv).normalized()
			if n.dot(outer[r * nc + c] - inside) < 0.0:
				n = -n
			onorm[r * nc + c] = n
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for layer in 2:
		for k in nr * nc:
			var n := onorm[k]
			verts.append(outer[k] - (n * thick if layer == 1 else Vector3.ZERO))
			normals.append(n if layer == 0 else -n)
			uvs.append(Vector2(outer[k].x + outer[k].z, outer[k].y))
	var per := nr * nc
	for layer in 2:
		var o := layer * per
		for r in nr - 1:
			for c in nc - 1:
				var a := o + r * nc + c
				OrganicMesh._tri_out(idx, verts, normals, a, a + 1, a + nc + 1)
				OrganicMesh._tri_out(idx, verts, normals, a, a + nc + 1, a + nc)
	# Rim around the four borders.
	var border: Array = []
	for c in nc - 1:
		border.append([c, c + 1])
		border.append([(nr - 1) * nc + c, (nr - 1) * nc + c + 1])
	for r in nr - 1:
		border.append([r * nc, (r + 1) * nc])
		border.append([r * nc + nc - 1, (r + 1) * nc + nc - 1])
	var centre := Vector3.ZERO
	for k in per:
		centre += outer[k]
	centre /= float(per)
	for e: Array in border:
		var a: int = e[0]
		var b: int = e[1]
		var pa := verts[a]
		var pb := verts[b]
		var ia := verts[a + per]
		var ib := verts[b + per]
		var n := (pb - pa).cross(pa - ia).normalized()
		if n.dot((pa + pb) * 0.5 - centre) < 0.0:
			n = -n
		var base := verts.size()
		for q: Vector3 in [pa, pb, ib, ia]:
			verts.append(q)
			normals.append(n)
			uvs.append(Vector2(q.x + q.z, q.y))
		OrganicMesh._tri_out(idx, verts, normals, base, base + 1, base + 2)
		OrganicMesh._tri_out(idx, verts, normals, base, base + 2, base + 3)
	var mesh := _commit(verts, normals, uvs, idx)
	_meshes[key] = mesh
	return mesh


## Rows for a curved plate wrapped round the body's front (or any arc): for each
## height y (top to bottom), points from angle a0 to a1 (radians, 0 = front -Z,
## +PI/2 = right +X) on an ellipse of half width w and depth d, pushed forward by
## `ridge` at the centre line (a crease like gothic plate). spec rows:
## [y, w, d, ridge] (ridge optional). `centre` offsets the whole plate.
static func wrap_rows(spec: Array, a0: float, a1: float, cols := 15, centre := Vector3.ZERO, ridge_width := 0.55) -> Array:
	var rows: Array = []
	for row: Array in spec:
		var y: float = row[0]
		var w: float = row[1]
		var d: float = row[2]
		var rg: float = row[3] if row.size() > 3 else 0.0
		var pts := PackedVector3Array()
		for c in cols:
			var a := lerpf(a0, a1, float(c) / (cols - 1))
			var crease := maxf(0.0, 1.0 - absf(a) / ridge_width)
			var z := -(cos(a) * d + rg * crease * crease)
			pts.append(centre + Vector3(sin(a) * w, y, z))
		rows.append(pts)
	return rows


## An edged blade along +Y from y = 0 with flat facets: `prof` rows are
## [t (0..1), half width, half thickness]; `fuller` > 0 cuts a central groove.
## Cross-section: a flattened hexagon (edge bevels + flat faces).
static func blade(key: String, length: float, prof: Array, fuller := 0.0) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 18
	var secs: Array = []
	for i in rows + 1:
		var t := float(i) / rows
		var s := OrganicMesh._sample(prof, t)
		var w: float = s[0]
		var th: float = s[1]
		var y := t * length
		# Points around the section: edge, bevel top, face top (fuller), ...
		var bev := w * 0.72
		var f := th * (1.0 - fuller * 0.6)
		secs.append([Vector3(w, y, 0), Vector3(bev, y, th), Vector3(0, y, f), Vector3(-bev, y, th),
				Vector3(-w, y, 0), Vector3(-bev, y, -th), Vector3(0, y, -f), Vector3(bev, y, -th)])
	for i in rows:
		var a: Array = secs[i]
		var b: Array = secs[i + 1]
		for k in 8:
			var k2 := (k + 1) % 8
			var p0: Vector3 = a[k]
			var p1: Vector3 = a[k2]
			var p2: Vector3 = b[k2]
			var p3: Vector3 = b[k]
			var n := (p1 - p0).cross(p3 - p0)
			if n.length_squared() < 1e-14:
				n = (p2 - p1).cross(p3 - p1)
			var mid := (p0 + p1) * 0.5
			var outward := Vector3(mid.x, 0, mid.z)
			n = n.normalized()
			if n.dot(outward) < 0.0:
				n = -n
			ModelKit._quad(st, p0, p1, p2, p3, n)
	# Base cap.
	var c0: Array = secs[0]
	for k in 8:
		ModelKit._tri(st, Vector3.ZERO, c0[k], c0[(k + 1) % 8], Vector3.DOWN)
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


## Faceted crystal: a `sides`-gon prism of `radius` and `length` along +Y with
## pointed ends (tip lengths). Flat shaded.
static func crystal_mesh(key: String, radius: float, length: float, sides := 6, tip := 0.4, base_tip := 0.15, twist := 0.0) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y0 := base_tip * length
	var y1 := length * (1.0 - tip)
	var bot := Vector3(0, 0, 0)
	var top := Vector3(0, length, 0)
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var q0 := Vector3(cos(a0) * radius, y0, sin(a0) * radius)
		var q1 := Vector3(cos(a1) * radius, y0, sin(a1) * radius)
		var r0 := Vector3(cos(a0 + twist) * radius * 0.92, y1, sin(a0 + twist) * radius * 0.92)
		var r1 := Vector3(cos(a1 + twist) * radius * 0.92, y1, sin(a1 + twist) * radius * 0.92)
		var mid := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
		var ns := (q1 - q0).cross(r0 - q0).normalized()
		if ns.dot(mid) < 0.0:
			ns = -ns
		ModelKit._quad(st, q0, q1, r1, r0, ns)
		var nt := (r1 - r0).cross(top - r0).normalized()
		if nt.dot(mid + Vector3.UP) < 0.0:
			nt = -nt
		ModelKit._tri(st, r0, r1, top, nt)
		var nb := (q1 - q0).cross(bot - q0).normalized()
		if nb.dot(mid + Vector3.DOWN) < 0.0:
			nb = -nb
		ModelKit._tri(st, q0, q1, bot, nb)
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


## Torus in the XZ plane (ring radius R, tube radius r).
static func torus(key: String, big_r: float, r: float, seg := 16, sides := 8, sy := 1.0) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in seg + 1:
		var a := TAU * i / seg
		var c := Vector3(cos(a), 0, sin(a))
		for j in sides + 1:
			var b := TAU * j / sides
			var n := c * cos(b) + Vector3.UP * sin(b)
			verts.append(c * (big_r + r * cos(b)) + Vector3.UP * r * sin(b) * sy)
			normals.append(Vector3(n.x, n.y / maxf(sy, 0.01), n.z).normalized())
			uvs.append(Vector2(a * big_r, b * r))
	for i in seg:
		for j in sides:
			var a := i * (sides + 1) + j
			var b := a + 1
			var c := (i + 1) * (sides + 1) + j + 1
			var d := (i + 1) * (sides + 1) + j
			OrganicMesh._tri_out(idx, verts, normals, a, b, c)
			OrganicMesh._tri_out(idx, verts, normals, a, c, d)
	var mesh := _commit(verts, normals, uvs, idx)
	_meshes[key] = mesh
	return mesh


## A hanging cloth strip: points down a path with a half width per point,
## spread along `across`, two-sided with `thick`. UV2.y = 0 at the top .. 1 at
## the end (the cloth shader tatters from it).
static func ribbon(key: String, path: PackedVector3Array, half_widths: PackedFloat32Array, across := Vector3.RIGHT, thick := 0.01) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var n := path.size()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	var along := 0.0
	var total := 0.0
	for i in range(1, n):
		total += path[i].distance_to(path[i - 1])
	for side in 2:
		along = 0.0
		for i in n:
			if i > 0:
				along += path[i].distance_to(path[i - 1])
			var t := (path[mini(n - 1, i + 1)] - path[maxi(0, i - 1)]).normalized()
			var face := across.cross(t).normalized()
			if side == 1:
				face = -face
			for k in 2:
				var off := across * half_widths[i] * (-1.0 if k == 0 else 1.0)
				verts.append(path[i] + off + face * thick * 0.5)
				normals.append(face)
				uvs.append(Vector2(off.length() * (-1.0 if k == 0 else 1.0), along))
				uv2s.append(Vector2(0.0, along / maxf(total, 0.001)))
	var per := n * 2
	for side in 2:
		var o := side * per
		for i in n - 1:
			var a := o + i * 2
			OrganicMesh._tri_out(idx, verts, normals, a, a + 1, a + 3)
			OrganicMesh._tri_out(idx, verts, normals, a, a + 3, a + 2)
	var mesh := _commit(verts, normals, uvs, idx, uv2s)
	_meshes[key] = mesh
	return mesh


## Chain of `links` torus links hanging along -Y from the origin (link length `size`).
static func chain(asm: Assembly, mat: Material, from: Vector3, to: Vector3, size: float, tint := Color(1, 1, 1)) -> void:
	var link := torus("chain_link_%.3f" % size, size * 0.42, size * 0.1, 10, 5, 1.0)
	var d := to - from
	var count := maxi(1, int(d.length() / (size * 0.8)))
	var dir := d.normalized()
	var b := Basis(Quaternion(Vector3.UP, dir)) if absf(dir.dot(Vector3.UP)) < 0.999 else Basis.IDENTITY
	for i in count:
		var p := from + d * ((i + 0.5) / count)
		var rot := b * Basis(Vector3.UP, PI * 0.5 * (i % 2)) * Basis(Vector3.RIGHT, PI * 0.5)
		asm.add(link, mat, Transform3D(rot.scaled_local(Vector3(1.0, 1.0, 1.6)), p), tint)


static func _commit(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, idx: PackedInt32Array, uv2s := PackedVector2Array()) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if uv2s.size() == verts.size():
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- Skinned cloth ---------------------------------------------------------------------

## A cloak skinned to the HumanoidModel's simulated cloak bones (body["cloak_first"]).
## The rest shape follows CharBody.cloak_point for this style so it hangs exactly
## where the simulation expects; `flare` widens the hem, `hem_drop` lengthens it
## (body units) past the last bone row. Two-sided. UV holds the rest x,y; UV2 = (rest z, v).
static func cloak(key: String, body: Dictionary, st: Dictionary, cols := 15, rows := 15, thick := 0.012, flare := 1.0, hem_drop := 0.0) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var first: int = body["cloak_first"]
	var pr: Dictionary = body["pr"]
	var C := CharRig.CLOAK_COLS
	var RW := CharRig.CLOAK_ROWS
	var grid := PackedVector3Array()
	for r in rows:
		for c in cols:
			var u := float(c) / (cols - 1)
			var v := float(r) / (rows - 1)
			var p := CharBody.cloak_point(u, v, st, pr)
			# Flare the lower part outward and let the hem fall a little further.
			var out := Vector3(p.x, 0, p.z - 0.02)
			p += out * (flare - 1.0) * v * v
			p.y -= hem_drop * v * v
			grid.append(p)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()
	for layer in 2:
		for r in rows:
			for c in cols:
				var p := grid[r * cols + c]
				var du := grid[r * cols + mini(cols - 1, c + 1)] - grid[r * cols + maxi(0, c - 1)]
				var dv := grid[mini(rows - 1, r + 1) * cols + c] - grid[maxi(0, r - 1) * cols + c]
				var n := du.cross(dv).normalized()
				# Outward = away from the body axis.
				if n.dot(Vector3(p.x, 0, p.z)) < 0.0:
					n = -n
				if layer == 1:
					n = -n
				var q := p + n * thick * 0.5
				verts.append(q)
				normals.append(n)
				uvs.append(Vector2(p.x, p.y))
				var v := float(r) / (rows - 1)
				uv2s.append(Vector2(p.z, v))
				var pu := float(c) / (cols - 1) * (C - 1)
				var pv := float(r) / (rows - 1) * (RW - 1)
				var c0 := mini(int(pu), C - 2)
				var r0 := mini(int(pv), RW - 2)
				var fu := pu - c0
				var fv := pv - r0
				var b00 := first + r0 * C + c0
				bones.append_array([b00, b00 + 1, b00 + C, b00 + C + 1])
				weights.append_array([(1.0 - fu) * (1.0 - fv), fu * (1.0 - fv), (1.0 - fu) * fv, fu * fv])
	var per := rows * cols
	for layer in 2:
		var o := layer * per
		for r in rows - 1:
			for c in cols - 1:
				var a := o + r * cols + c
				OrganicMesh._tri_out(idx, verts, normals, a, a + 1, a + cols + 1)
				OrganicMesh._tri_out(idx, verts, normals, a, a + cols + 1, a + cols)
	var mesh := _commit_skinned(verts, normals, uvs, uv2s, bones, weights, idx)
	_meshes[key] = mesh
	return mesh


## A robe skirt from the waist (top_y) to the hem (hem_y), body units, skinned
## to the hips at the top and to the legs below (left / right by side), so it
## swings with each stride. `r_top` / `r_hem` are (x, z) radii. The skirt runs
## round the angles arc_from..arc_to (radians about +Y; 0 = back +Z, +-PI =
## front -Z, PI/2 = right side): a full robe by default, or a tabard panel.
## Two-sided. UV2.y = 0 waist .. 1 hem.
static func robe(key: String, rest: PackedVector3Array, top_y: float, hem_y: float, r_top: Vector2, r_hem: Vector2,
		sides := 28, rows := 12, arc_from := -PI, arc_to := PI, thick := 0.015, bulge := 0.0) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var R := CharRig
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()
	var knee_y: float = rest[R.SHIN_L].y
	var hip_y: float = rest[R.HIPS].y
	var a0 := arc_from
	var a1 := arc_to
	for layer in 2:
		for i in rows + 1:
			var v := float(i) / rows
			var y := lerpf(top_y, hem_y, v)
			var e := pow(v, 0.8)
			var rx := lerpf(r_top.x, r_hem.x, e) + sin(v * PI) * bulge
			var rz := lerpf(r_top.y, r_hem.y, e) + sin(v * PI) * bulge
			# Legs take over below the hips, more so towards the knees.
			var leg := smoothstep(hip_y + 0.05, knee_y, y) * 0.8
			var shin := smoothstep(knee_y, knee_y - 0.3, y) * 0.5
			for j in sides + 1:
				var a := lerpf(a0, a1, float(j) / sides)
				# a = 0 is the back (+Z), +-PI the front (-Z).
				var dir := Vector3(sin(a), 0, cos(a))
				var p := Vector3(dir.x * rx, y, dir.z * rz)
				var n := Vector3(dir.x / maxf(rx, 0.01), (r_hem.x - r_top.x) / maxf(absf(top_y - hem_y), 0.01) * 0.6, dir.z / maxf(rz, 0.01)).normalized()
				if layer == 1:
					n = -n
					p -= Vector3(dir.x, 0, dir.z) * thick
				verts.append(p)
				normals.append(n)
				uvs.append(Vector2(p.x, p.y))
				uv2s.append(Vector2(p.z, v))
				var side := clampf(0.5 + dir.x * 1.6, 0.0, 1.0)  # 0 left .. 1 right
				var w_shin := shin * leg * absf(side - 0.5) * 2.0
				var wl := (leg - w_shin) * (1.0 - side)
				var wr := (leg - w_shin) * side
				var shin_bone: int = R.SHIN_L if side < 0.5 else R.SHIN_R
				var wh := maxf(0.0, 1.0 - wl - wr - w_shin)
				bones.append_array([R.HIPS, R.THIGH_L, R.THIGH_R, shin_bone])
				weights.append_array([wh, wl, wr, w_shin])
	var ring := sides + 1
	var per := (rows + 1) * ring
	for layer in 2:
		var o := layer * per
		for i in rows:
			for j in sides:
				var a := o + i * ring + j
				OrganicMesh._tri_out(idx, verts, normals, a, a + 1, a + ring + 1)
				OrganicMesh._tri_out(idx, verts, normals, a, a + ring + 1, a + ring)
	var mesh := _commit_skinned(verts, normals, uvs, uv2s, bones, weights, idx)
	_meshes[key] = mesh
	return mesh


static func _commit_skinned(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, uv2s: PackedVector2Array,
		bones: PackedInt32Array, weights: PackedFloat32Array, idx: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- FX ------------------------------------------------------------------------------

## Drifting wisps / smoke / motes that follow a node (world-space particles).
## style: "wisp" (ghost light), "smoke" (dark rising smoke), "mote" (sparks),
## "frost" (breath and snow), "shard" (glittering crystal dust).
static func emitter(parent: Node3D, style: String, amount: int, extents: Vector3, color: Color, size := 0.4, lifetime := 2.0, rise := 0.8) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.emitting = true
	p.visibility_aabb = AABB(-extents * 2.0 - Vector3(2, 2, 2), extents * 4.0 + Vector3(4, 8, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3.UP
	pm.spread = 35.0 if style != "smoke" else 20.0
	pm.initial_velocity_min = rise * 0.3
	pm.initial_velocity_max = rise
	pm.gravity = Vector3(0, -0.4 if style == "frost" else 0.15, 0)
	pm.damping_min = 0.2
	pm.damping_max = 0.8
	pm.turbulence_enabled = style != "shard"
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.3))
	sc.add_point(Vector2(0.3, 1.0))
	sc.add_point(Vector2(1, 0.4 if style != "smoke" else 1.6))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.2, Color(1, 1, 1, 1))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var hot := color.lightened(0.4)
	var energy := 4.0
	match style:
		"smoke":
			energy = 0.6
			hot = color
		"frost":
			energy = 1.4
		"shard":
			energy = 6.0
	quad.material = MaterialLibrary.fx(hot, color, energy)
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p


## A soft light that does not cast shadows (lanterns, soul fire, crystal hearts).
static func light(parent: Node3D, pos: Vector3, color: Color, energy: float, radius: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = radius
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	l.light_volumetric_fog_energy = 0.6
	l.position = pos
	parent.add_child(l)
	return l
