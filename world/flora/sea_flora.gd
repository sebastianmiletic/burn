class_name SeaFlora
extends RefCounted
## Underwater plants on flooded sea-bed triangles (Flora.plan_chunk hands them over):
## seagrass meadows on silt and sand, kelp forests on rock and gravel, branching and
## fan corals, brain corals and anemones on reef rock, glowing anemones by the vents,
## lake weed in fresh water. Modelled meshes in the flora mesh-kit style (tapered
## stems, ribbon blades, tubes), instanced per chunk and swaying with a slow current
## (sea_plant.gdshader). Pure data on worker threads; meshes are built once in warmup().

const MeshKit := preload("res://world/flora/flora_mesh_kit.gd")

enum S { SEAGRASS, KELP, CORAL_BRANCH, CORAL_FAN, CORAL_BRAIN, ANEMONE, LAKE_WEED }
const COUNT := 7
## Visible range per quality (Low..Ultra); water hides anything farther anyway.
const RANGE := [35.0, 50.0, 65.0, 80.0]

## Rules per sea-bed block: [layer, density /m2, scale min, max, min depth m, palette].
const RULES := {
	Blocks.SAND: [[S.SEAGRASS, 0.12, 0.6, 1.1, 1.5, "grass"], [S.KELP, 0.006, 0.8, 1.2, 8.0, "kelp"]],
	Blocks.SILT: [[S.SEAGRASS, 2.2, 0.6, 1.25, 1.0, "grass"], [S.ANEMONE, 0.01, 0.7, 1.2, 3.0, "anemone"]],
	Blocks.MUD: [[S.SEAGRASS, 0.6, 0.5, 1.0, 1.0, "grass"]],
	Blocks.CORAL_ROCK: [[S.CORAL_BRANCH, 0.32, 0.6, 1.4, 1.2, "coral"], [S.CORAL_FAN, 0.1, 0.7, 1.5, 2.0, "fan"],
		[S.CORAL_BRAIN, 0.16, 0.5, 1.5, 1.0, "brain"], [S.ANEMONE, 0.07, 0.6, 1.3, 1.5, "anemone"], [S.SEAGRASS, 0.15, 0.5, 0.9, 1.0, "grass"]],
	Blocks.GRAVEL: [[S.KELP, 0.09, 0.8, 1.2, 5.0, "kelp"], [S.SEAGRASS, 0.1, 0.5, 0.9, 1.0, "grass"]],
	Blocks.STONE: [[S.KELP, 0.11, 0.8, 1.2, 5.0, "kelp"], [S.ANEMONE, 0.03, 0.6, 1.2, 3.0, "anemone"]],
	Blocks.GRANITE: [[S.KELP, 0.1, 0.8, 1.2, 5.0, "kelp"]],
	Blocks.LIMESTONE: [[S.KELP, 0.08, 0.8, 1.2, 5.0, "kelp"], [S.CORAL_BRAIN, 0.03, 0.5, 1.0, 2.0, "brain"]],
	Blocks.SANDSTONE: [[S.KELP, 0.06, 0.8, 1.2, 5.0, "kelp"]],
	Blocks.BASALT: [[S.ANEMONE, 0.06, 0.6, 1.3, 2.0, "vent"]],
	Blocks.SCORIA: [[S.ANEMONE, 0.06, 0.6, 1.3, 2.0, "vent"]],
	Blocks.SLATE: [[S.ANEMONE, 0.02, 0.6, 1.2, 10.0, "vent"]],
}
const LAKE_BLOCKS := [Blocks.SAND, Blocks.MUD, Blocks.GRAVEL, Blocks.DIRT, Blocks.GRASS, Blocks.CLAY]
const PAL := {
	"grass": [Color(0.2, 0.36, 0.12), Color(0.26, 0.4, 0.14), Color(0.3, 0.38, 0.12)],
	"kelp": [Color(0.32, 0.26, 0.06), Color(0.26, 0.22, 0.05), Color(0.36, 0.3, 0.08)],
	"coral": [Color(0.95, 0.45, 0.4), Color(0.98, 0.7, 0.35), Color(0.75, 0.42, 0.85), Color(0.95, 0.85, 0.7), Color(0.4, 0.75, 0.7)],
	"fan": [Color(0.75, 0.2, 0.45), Color(0.9, 0.5, 0.2), Color(0.55, 0.35, 0.85)],
	"brain": [Color(0.75, 0.68, 0.45), Color(0.6, 0.72, 0.5), Color(0.85, 0.6, 0.5)],
	"anemone": [Color(0.95, 0.4, 0.55), Color(0.55, 0.85, 0.6), Color(0.95, 0.75, 0.4)],
	"vent": [Color(0.9, 0.85, 0.8), Color(0.95, 0.5, 0.35)],
	"weed": [Color(0.25, 0.32, 0.12), Color(0.3, 0.3, 0.1)],
}

static var _meshes: Array = []
static var _mats: Array = []
static var _warm := false


# =========================================================================== planning (worker threads)

## Instances for the flooded triangles `wet` (indices into the flora surface arrays).
## Returns [{"sea": layer, "buf", "count", "aabb"}] (Flora's 16-float MultiMesh layout).
static func plan(o: Vector3, tris: PackedVector3Array, normals: PackedVector3Array, blocks: PackedByteArray, wet: PackedInt32Array, rng: RandomNumberGenerator) -> Array:
	var batches := {}
	for i in wet:
		var nrm := normals[i]
		if nrm.y < 0.55:
			continue
		var a := tris[i * 3]
		var b := tris[i * 3 + 1]
		var c := tris[i * 3 + 2]
		var area := (b - a).cross(c - a).length() * 0.5
		var cen := o + (a + b + c) / 3.0
		var depth := float(WorldGen.SEA_LEVEL + 1) - cen.y
		var block: int = blocks[i]
		var rules: Array = []
		if depth > 0.4:
			rules = RULES.get(block, [])
		elif block in LAKE_BLOCKS:
			# Fresh water (lakes, flooded hollows): weed only.
			rules = [[S.LAKE_WEED, 0.35, 0.5, 1.0, 0.0, "weed"]]
			depth = 2.0
		for rule: Array in rules:
			if depth < float(rule[4]):
				continue
			# Plants need light: nothing but anemones grows deeper than ~30 m (the trench floor stays bare).
			if depth > 30.0 and int(rule[0]) != S.ANEMONE:
				continue
			var layer: int = rule[0]
			var expect := area * float(rule[1])
			var n := int(expect)
			if rng.randf() < expect - n:
				n += 1
			for k in n:
				var r1 := rng.randf()
				var r2 := rng.randf()
				if r1 + r2 > 1.0:
					r1 = 1.0 - r1
					r2 = 1.0 - r2
				var p := a + (b - a) * r1 + (c - a) * r2
				var s := rng.randf_range(rule[2], rule[3])
				var sy := s
				if layer == S.KELP:
					# Kelp reaches most of the way to the surface.
					sy = clampf(depth * rng.randf_range(0.55, 0.85), 3.0, 14.0) / 8.0
				elif layer == S.SEAGRASS or layer == S.LAKE_WEED:
					sy = minf(s, depth * 0.8)
				var up := Vector3.UP.lerp(nrm, 0.5 if layer in [S.CORAL_BRAIN, S.ANEMONE] else 0.15).normalized()
				var basis := Flora._orient(up, rng.randf() * TAU).scaled(Vector3(s, sy, s))
				var pal: Array = PAL[rule[5]]
				var col: Color = pal[rng.randi() % pal.size()]
				if not batches.has(layer):
					batches[layer] = Flora.Batch.new()
				(batches[layer] as Flora.Batch).add(basis, p - Vector3(0, 0.05, 0), Color(col.r, col.g, col.b, rng.randf()), 0.0)
	var out: Array = []
	for layer: int in batches:
		var g := (batches[layer] as Flora.Batch).finish(Vector3(2, 0.5, 2), 14.0 if layer == S.KELP else 2.0)
		g["sea"] = layer
		out.append(g)
	return out


# =========================================================================== building (main thread)

static func build(groups: Array, quality: int, root: Node3D) -> void:
	if groups.is_empty():
		return
	warmup()
	var reach: float = RANGE[clampi(quality, 0, 3)]
	for g: Dictionary in groups:
		var layer: int = g["sea"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _meshes[layer]
		mm.instance_count = g["count"]
		mm.buffer = g["buf"]
		mm.custom_aabb = g["aabb"]
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.custom_aabb = g["aabb"]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = reach * (1.3 if layer == S.KELP else 1.0) + Flora.CHUNK_MARGIN
		root.add_child(mmi)


static func warmup() -> void:
	if _warm:
		return
	_warm = true
	var sh := load("res://world/flora/shaders/sea_plant.gdshader") as Shader
	# [sway amplitude, sway speed, translucency, glow, pattern (0 plain, 1 polyps, 2 brain grooves, 3 fan mesh)]
	var looks := [[0.35, 0.9, 0.6, 0.0, 0.0], [0.9, 0.45, 0.55, 0.0, 0.0], [0.03, 0.5, 0.2, 0.0, 1.0], [0.12, 0.6, 0.5, 0.0, 3.0],
			[0.0, 0.5, 0.1, 0.0, 2.0], [0.25, 1.1, 0.6, 1.2, 0.0], [0.3, 0.8, 0.5, 0.0, 0.0]]
	_mats.clear()
	for l: Array in looks:
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter(&"sway", l[0])
		m.set_shader_parameter(&"speed", l[1])
		m.set_shader_parameter(&"translucency", l[2])
		m.set_shader_parameter(&"glow", l[3])
		m.set_shader_parameter(&"pattern", l[4])
		_mats.append(m)
	_meshes.clear()
	_meshes.append(_seagrass(_mats[S.SEAGRASS], 11))
	_meshes.append(_kelp(_mats[S.KELP]))
	_meshes.append(_branching(_mats[S.CORAL_BRANCH]))
	_meshes.append(_fan(_mats[S.CORAL_FAN]))
	_meshes.append(_brain(_mats[S.CORAL_BRAIN]))
	_meshes.append(_anemone(_mats[S.ANEMONE]))
	_meshes.append(_seagrass(_mats[S.LAKE_WEED], 7))


static func mesh(layer: int) -> Mesh:
	warmup()
	return _meshes[layer]


# =========================================================================== meshes

## Vertex colour: r sway weight (0 root .. 1 tip), g random, b glow mask, a occlusion.
static func _tube(s: MeshKit.Surf, pts: PackedVector3Array, radii: PackedFloat32Array, sides: int, w0: float, w1: float, rnd: float, glow_tip := 0.0) -> void:
	var n := pts.size()
	var base := s.v.size()
	for i in n:
		var d := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := MeshKit._perp(d)
		var up := d.cross(side)
		var t := float(i) / (n - 1)
		for k in sides + 1:
			var a := TAU * k / sides
			var nrm := (side * cos(a) + up * sin(a)).normalized()
			s.vert(pts[i] + nrm * radii[i], nrm, d, Vector2(float(k) / sides, t), Color(lerpf(w0, w1, t), rnd, glow_tip * smoothstep(0.7, 1.0, t), lerpf(0.55, 1.0, t)))
	for i in n - 1:
		for k in sides:
			var a := base + i * (sides + 1) + k
			var b := a + sides + 1
			s.tri(a, a + 1, b)
			s.tri(a + 1, b + 1, b)


## A ribbon blade from `root` along `dir` (bending by `lean`), width `w`, twisting slightly.
static func _ribbon(s: MeshKit.Surf, root: Vector3, h: float, w: float, lean: Vector3, segs: int, w0: float, w1: float, rnd: float, ruffle := 0.0) -> void:
	var base := s.v.size()
	var side := lean.cross(Vector3.UP).normalized() if lean.length() > 0.01 else Vector3.RIGHT
	for i in segs + 1:
		var t := float(i) / segs
		var c := root + Vector3.UP * h * t + lean * h * t * t
		var tw := side.rotated(Vector3.UP, sin(t * 3.0 + rnd * 6.0) * 0.6)
		var hw := w * 0.5 * (1.0 - pow(t, 2.5) * 0.85) * (1.0 + ruffle * sin(t * 40.0 + rnd * 9.0))
		var nrm := tw.cross(Vector3.UP).normalized()
		var col := Color(lerpf(w0, w1, t), rnd, 0.0, lerpf(0.5, 1.0, t))
		s.vert(c - tw * hw, nrm, tw, Vector2(0, t), col)
		s.vert(c + tw * hw, nrm, tw, Vector2(1, t), col)
	for i in segs:
		var k := base + i * 2
		s.tri(k, k + 2, k + 1)
		s.tri(k + 1, k + 2, k + 3)


static func _commit(s: MeshKit.Surf, mat: Material) -> ArrayMesh:
	var m := ArrayMesh.new()
	s.commit(m, mat)
	return m


static func _seagrass(mat: Material, blades: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 501 + blades
	var s := MeshKit.Surf.new()
	for i in blades:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.12
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.05, 0.35)
		_ribbon(s, Vector3(cos(a) * r, 0, sin(a) * r), rng.randf_range(0.55, 1.0), rng.randf_range(0.025, 0.04), lean, 5, 0.0, 1.0, rng.randf())
	return _commit(s, mat)


## Giant kelp, 8 m reference height: a stipe with gas bladders and long ruffled blades.
static func _kelp(mat: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 733
	var s := MeshKit.Surf.new()
	for st in 3:
		var a0 := rng.randf() * TAU
		var root := Vector3(cos(a0), 0, sin(a0)) * rng.randf_range(0.0, 0.25)
		var h := 8.0 * rng.randf_range(0.75, 1.0)
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i in 13:
			var t := float(i) / 12.0
			pts.append(root + Vector3(sin(t * 4.0 + a0) * 0.25 * t, h * t, cos(t * 3.0 + a0) * 0.25 * t))
			radii.append(lerpf(0.045, 0.02, t))
		var rnd := rng.randf()
		_tube(s, pts, radii, 5, 0.0, 1.0, rnd)
		# Blades every ~0.4 m on alternating sides, each with a bladder at its base.
		var y := 0.6
		while y < h - 0.3:
			var t := y / h
			var at := root + Vector3(sin(t * 4.0 + a0) * 0.25 * t, y, cos(t * 3.0 + a0) * 0.25 * t)
			var dir := Vector3(cos(y * 2.3 + a0), 0, sin(y * 2.3 + a0))
			_ribbon(s, at + dir * 0.06, rng.randf_range(0.7, 1.1), rng.randf_range(0.09, 0.14), dir * rng.randf_range(0.35, 0.6), 4, t, minf(t + 0.15, 1.0), rnd, 0.12)
			var bp := PackedVector3Array([at + dir * 0.02, at + dir * 0.06 + Vector3(0, 0.05, 0), at + dir * 0.09 + Vector3(0, 0.12, 0)])
			_tube(s, bp, PackedFloat32Array([0.025, 0.045, 0.02]), 5, t, t, rnd)
			y += rng.randf_range(0.3, 0.5)
	return _commit(s, mat)


## Staghorn coral: thick forking branches with rounded tips, ~0.6 m.
static func _branching(mat: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 919
	var s := MeshKit.Surf.new()
	var stack: Array = [[Vector3.ZERO, Vector3.UP, 0.32, 0.055, 0]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var p: Vector3 = e[0]
		var d: Vector3 = e[1]
		var len := float(e[2])
		var r := float(e[3])
		var depth := int(e[4])
		var end := p + d * len
		var mid := p.lerp(end, 0.5) + MeshKit._perp(d) * rng.randf_range(-0.03, 0.03)
		var w0 := clampf(p.y / 0.6, 0.0, 1.0)
		var w1 := clampf(end.y / 0.6, 0.0, 1.0)
		_tube(s, PackedVector3Array([p, mid, end]), PackedFloat32Array([r, r * 0.92, r * 0.8]), 6, w0, w1, rng.randf())
		if depth >= 3:
			_tube(s, PackedVector3Array([end, end + d * r * 0.6]), PackedFloat32Array([r * 0.8, r * 0.2]), 6, w1, w1, rng.randf())
			continue
		var forks := 2 if depth > 0 else 4
		for f in forks:
			var nd := (d + Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(0.0, 0.5), rng.randf_range(-0.9, 0.9))).normalized()
			if nd.y < 0.15:
				nd = (nd + Vector3(0, 0.4, 0)).normalized()
			stack.append([end, nd, len * rng.randf_range(0.65, 0.9), r * 0.78, depth + 1])
	return _commit(s, mat)


## Sea fan: a flat lattice of fine branches in one plane on a short stalk (~0.9 m).
static func _fan(mat: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1201
	var s := MeshKit.Surf.new()
	var stack: Array = [[Vector3.ZERO, Vector3.UP, 0.18, 0.02, 0]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var p: Vector3 = e[0]
		var d: Vector3 = e[1]
		var len := float(e[2])
		var r := float(e[3])
		var depth := int(e[4])
		var end := p + d * len
		_tube(s, PackedVector3Array([p, end]), PackedFloat32Array([r, r * 0.85]), 4, clampf(p.y, 0.0, 1.0), clampf(end.y, 0.0, 1.0), rng.randf())
		if depth >= 5:
			continue
		for f in 2:
			var ang := rng.randf_range(0.25, 0.6) * (1.0 if f == 0 else -1.0)
			var nd := Vector3(d.x * cos(ang) - d.y * sin(ang), d.x * sin(ang) + d.y * cos(ang), 0.0).normalized()
			if nd.y < 0.1:
				nd = Vector3(nd.x, 0.1, 0).normalized()
			stack.append([end, nd, len * rng.randf_range(0.75, 0.95), r * 0.8, depth + 1])
	# The fine mesh between the branches is cut by the shader on two crossed quads.
	var b := s.v.size()
	for q in 4:
		var x0 := -0.45
		var x1 := 0.45
		var y0 := 0.15
		var y1 := 0.95
		var z := 0.003 if q % 2 == 0 else -0.003
		var nrm := Vector3(0, 0, 1 if q % 2 == 0 else -1)
		s.vert(Vector3(x0, y0, z), nrm, Vector3.RIGHT, Vector2(0, 0), Color(y0, 0.5, 0.5, 1.0))
		s.vert(Vector3(x1, y0, z), nrm, Vector3.RIGHT, Vector2(1, 0), Color(y0, 0.5, 0.5, 1.0))
		s.vert(Vector3(x1, y1, z), nrm, Vector3.RIGHT, Vector2(1, 1), Color(y1, 0.5, 0.5, 1.0))
		s.vert(Vector3(x0, y1, z), nrm, Vector3.RIGHT, Vector2(0, 1), Color(y1, 0.5, 0.5, 1.0))
		var k := b + q * 4
		s.tri(k, k + 2, k + 1)
		s.tri(k, k + 3, k + 2)
	return _commit(s, mat)


## Brain coral: a lumpy dome (grooves are drawn by the shader), ~0.5 m.
static func _brain(mat: Material) -> ArrayMesh:
	var s := MeshKit.Surf.new()
	var rings := 8
	var segs := 16
	for i in rings + 1:
		var v := float(i) / rings
		var ph := v * PI * 0.55
		for k in segs + 1:
			var a := TAU * k / segs
			var bump := 1.0 + 0.08 * sin(a * 3.0 + v * 5.0) + 0.05 * cos(a * 5.0 - v * 3.0)
			var nrm := Vector3(cos(a) * sin(ph), cos(ph), sin(a) * sin(ph)).normalized()
			var p := Vector3(cos(a) * sin(ph) * 0.5, cos(ph) * 0.38 - 0.05, sin(a) * sin(ph) * 0.5) * bump
			s.vert(p, nrm, Vector3(-sin(a), 0, cos(a)), Vector2(float(k) / segs, v), Color(0.0, 0.5, 0.0, lerpf(1.0, 0.6, v)))
	for i in rings:
		for k in segs:
			var a := i * (segs + 1) + k
			var b := a + segs + 1
			s.tri(a, b, a + 1)
			s.tri(a + 1, b, b + 1)
	return _commit(s, mat)


## Anemone: a soft column crowned by a ring of tapering tentacles (glowing tips by the vents).
static func _anemone(mat: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1777
	var s := MeshKit.Surf.new()
	_tube(s, PackedVector3Array([Vector3(0, -0.02, 0), Vector3(0, 0.1, 0), Vector3(0, 0.2, 0)]), PackedFloat32Array([0.1, 0.085, 0.11]), 10, 0.0, 0.1, 0.3)
	for i in 18:
		var a := TAU * i / 18.0 + rng.randf() * 0.1
		var out := Vector3(cos(a), 0, sin(a))
		var root := Vector3(0, 0.2, 0) + out * rng.randf_range(0.03, 0.09)
		var len := rng.randf_range(0.18, 0.3)
		var pts := K_bezier(root, root + out * len * 0.5 + Vector3(0, len * 0.6, 0), root + out * len * 0.9 + Vector3(0, len * 0.35, 0), 4)
		_tube(s, pts, PackedFloat32Array([0.016, 0.014, 0.011, 0.008, 0.004]), 4, 0.2, 1.0, rng.randf(), 1.0)
	return _commit(s, mat)


static func K_bezier(p0: Vector3, p1: Vector3, p2: Vector3, steps: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in steps + 1:
		var t := float(i) / steps
		out.append(p0.lerp(p1, t).lerp(p1.lerp(p2, t), t))
	return out
