class_name Flora
extends RefCounted
## Trees, grass, wildflowers, ferns, bushes, litter, boulders, logs and pebbles drawn on the
## smooth terrain (contract: docs/REALISM_CONTRACTS.md, "Flora").
##
## * warmup()      main thread, once: grows every tree variant (3 LODs), grass clumps, plants,
##                 rocks; creates the shared materials.
## * plan_chunk()  WORKER THREAD, pure data: scatters instances on the up-facing triangles and
##                 returns ready-to-upload MultiMesh buffers (PackedFloat32Array, 16 floats each:
##                 3x4 transform + custom data).
## * build_chunk() main thread: one MultiMeshInstance3D per layer, buffers assigned in one call.
## * fell()        felling FX.
##
## Level of detail is decided per instance in the shaders (distance from the camera): trees
## cross-fade LOD0 -> LOD1 -> LOD2 with a dither, LOD1 doubles as the shadow caster of nearby
## trees; grass and flowers thin out and sink into the ground. Node visibility ranges only cull
## whole chunks beyond the farthest band.

## Tree kinds. (The contract's `enum Tree` cannot be declared: `Tree` is a native Godot class and
## GDScript refuses to shadow it, so the enum is `TreeKind`; Flora.OAK etc. are shortcuts.)
enum TreeKind { OAK, CRIMSON, PINE, DEAD }
const OAK := TreeKind.OAK
const CRIMSON := TreeKind.CRIMSON
const PINE := TreeKind.PINE
const DEAD := TreeKind.DEAD

const VARIANTS := 4
const FLOATS := 16   # per instance: 12 transform + 4 custom

## Ground layers. Each is one mesh + material, instanced per chunk.
enum L { GRASS, TALL_GRASS, REEDS, STUBBLE, TUFT, BEACH, SOUL_GRASS, DAISY, POPPY, BUTTERCUP, SPIKE,
		HEATHER, IRIS, ASPHODEL, FERN, BUSH_AUTUMN, BUSH_GREEN, LITTER, PEBBLES, BOULDER, LOG }
const LAYER_COUNT := 21

## Which layers are "small" (thinned by quality, no shadows) and their material family.
const _GRASSY := [L.GRASS, L.TALL_GRASS, L.REEDS, L.STUBBLE, L.TUFT, L.BEACH, L.SOUL_GRASS]
const _PLANTS := [L.DAISY, L.POPPY, L.BUTTERCUP, L.SPIKE, L.HEATHER, L.IRIS, L.ASPHODEL, L.FERN]

## Distances per quality (Low, Medium, High, Ultra), metres.
const GRASS_RANGE := [35.0, 50.0, 70.0, 90.0]
const GRASS_SPLIT := [10.0, 12.0, 14.0, 18.0]   # near (full clumps) / far (sparse clumps) switch
const PLANT_RANGE := [35.0, 50.0, 62.0, 85.0]
const BUSH_RANGE := [55.0, 70.0, 90.0, 120.0]
const ROCK_RANGE := [65.0, 90.0, 115.0, 150.0]
const TREE_LOD0 := [22.0, 34.0, 48.0, 66.0]
const TREE_LOD1 := [70.0, 95.0, 120.0, 150.0]
const TREE_FAR := [150.0, 175.0, 210.0, 250.0]
## Node visibility ranges are measured to the chunk AABB centre: half the
## diagonal of a 16 m chunk's footprint reaches its farthest corner.
const CHUNK_MARGIN := 11.5

const MeshKit := preload("res://world/flora/flora_mesh_kit.gd")
const FellFx := preload("res://world/flora/fell_fx.gd")

const BLOCK_GRASS := 3
const BLOCK_DIRT := 2
const BLOCK_STONE := 1
const BLOCK_SAND := 4
const BLOCK_SNOW := 5
const BLOCK_GRAVEL := 12
const BLOCK_ASH := 22
const BLOCK_DRY_GRASS := 34
const BLOCK_MUD := 38
const BLOCK_SOUL_SAND := 39

static var _warm := false
static var _quality := -1
static var _layer_mesh: Array = []          # [L] -> Mesh
static var _layer_far: Array = []           # [L] -> far LOD Mesh (grassy layers) or null
static var _tree_mesh: Array = []           # [kind][variant][lod] -> ArrayMesh
static var _tree_skel: Array = []           # [kind][variant] -> Skeleton (metres)
static var _mats := {}                      # name -> ShaderMaterial
static var warmup_ms := 0.0


# =========================================================================== warmup

static func is_warm() -> bool:
	return _warm


## Main thread, once on the loading screen. Builds and caches every mesh/material.
static func warmup() -> void:
	if _warm:
		return
	var t0 := Time.get_ticks_usec()
	_make_materials()
	var rng := RandomNumberGenerator.new()
	_tree_mesh.clear()
	_tree_skel.clear()
	for kind in 4:
		var meshes := []
		var skels := []
		for v in VARIANTS:
			rng.seed = 7919 * (kind + 1) + 104729 * v
			var sk: MeshKit.Skeleton
			match kind:
				TreeKind.OAK:
					var tiles: Array = [[[MeshKit.TILE_OAK, 5.0], [MeshKit.TILE_RUSSET, 2.0], [MeshKit.TILE_AMBER, 2.0]],
							[[MeshKit.TILE_OAK, 3.0], [MeshKit.TILE_AMBER, 4.0], [MeshKit.TILE_RUSSET, 1.0]],
							[[MeshKit.TILE_RUSSET, 4.0], [MeshKit.TILE_OAK, 3.0], [MeshKit.TILE_CRIMSON, 0.5]],
							[[MeshKit.TILE_OAK, 4.0], [MeshKit.TILE_AMBER, 1.0], [MeshKit.TILE_GREEN, 1.0], [MeshKit.TILE_RUSSET, 1.0]]][v]
					sk = MeshKit.skeleton_broadleaf(rng, tiles, 0.15 * v)
				TreeKind.CRIMSON:
					var tiles: Array = [[MeshKit.TILE_CRIMSON, 6.0], [MeshKit.TILE_RUSSET, 1.0 + v * 0.5]]
					sk = MeshKit.skeleton_broadleaf(rng, tiles, 0.55 + 0.12 * v)
				TreeKind.PINE:
					sk = MeshKit.skeleton_pine(rng)
				_:
					sk = MeshKit.skeleton_dead(rng)
			skels.append(sk)
			var lods := []
			for lod in 3:
				lods.append(MeshKit.mesh_tree(sk, lod, _mats["bark_%d_%d" % [kind, lod]], _mats["leaves_%d_%d" % [kind, lod]]))
			meshes.append(lods)
		_tree_mesh.append(meshes)
		_tree_skel.append(skels)
	_layer_mesh.resize(LAYER_COUNT)
	_layer_far.resize(LAYER_COUNT)
	for e in [[L.GRASS, "short", "g_grass"], [L.TALL_GRASS, "tall", "g_tall"], [L.REEDS, "reeds", "g_reeds"],
			[L.STUBBLE, "stubble", "g_stubble"], [L.TUFT, "tuft", "g_tuft"], [L.BEACH, "tall", "g_beach"], [L.SOUL_GRASS, "tall", "g_soul"]]:
		_layer_far[e[0]] = MeshKit.mesh_grass(e[1], _mats[e[2] + "_far"], 1)
	_layer_mesh[L.GRASS] = MeshKit.mesh_grass("short", _mats["g_grass"])
	_layer_mesh[L.TALL_GRASS] = MeshKit.mesh_grass("tall", _mats["g_tall"])
	_layer_mesh[L.REEDS] = MeshKit.mesh_grass("reeds", _mats["g_reeds"])
	_layer_mesh[L.STUBBLE] = MeshKit.mesh_grass("stubble", _mats["g_stubble"])
	_layer_mesh[L.TUFT] = MeshKit.mesh_grass("tuft", _mats["g_tuft"])
	_layer_mesh[L.BEACH] = MeshKit.mesh_grass("tall", _mats["g_beach"])
	_layer_mesh[L.SOUL_GRASS] = MeshKit.mesh_grass("tall", _mats["g_soul"])
	_layer_mesh[L.DAISY] = MeshKit.mesh_plant("daisy", _mats["p_flower"])
	_layer_mesh[L.POPPY] = MeshKit.mesh_plant("poppy", _mats["p_poppy"])
	_layer_mesh[L.BUTTERCUP] = MeshKit.mesh_plant("buttercup", _mats["p_flower"])
	_layer_mesh[L.SPIKE] = MeshKit.mesh_plant("spike", _mats["p_flower"])
	_layer_mesh[L.HEATHER] = MeshKit.mesh_plant("heather", _mats["p_heather"])
	_layer_mesh[L.IRIS] = MeshKit.mesh_plant("iris", _mats["p_flower"])
	_layer_mesh[L.ASPHODEL] = MeshKit.mesh_plant("asphodel", _mats["p_soul"])
	_layer_mesh[L.FERN] = MeshKit.mesh_plant("fern", _mats["p_fern"])
	rng.seed = 4242
	var bush_a := MeshKit.skeleton_bush(rng, [[MeshKit.TILE_OAK, 3.0], [MeshKit.TILE_RUSSET, 2.0], [MeshKit.TILE_AMBER, 2.0]])
	_layer_mesh[L.BUSH_AUTUMN] = MeshKit.mesh_tree(bush_a, 0, _mats["bush_bark"], _mats["bush_leaves"], false)
	var bush_g := MeshKit.skeleton_bush(rng, [[MeshKit.TILE_GREEN, 4.0], [MeshKit.TILE_AMBER, 1.0]])
	_layer_mesh[L.BUSH_GREEN] = MeshKit.mesh_tree(bush_g, 0, _mats["bush_bark"], _mats["bush_leaves"], false)
	_layer_mesh[L.LITTER] = MeshKit.mesh_litter(_mats["litter"])
	var pebble_parts := []
	rng.seed = 77
	for i in 7:
		var r := MeshKit.mesh_rock(100 + i, 1, rng.randf_range(0.5, 0.8))
		var s := rng.randf_range(0.06, 0.2)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s),
				Vector3(rng.randf_range(-0.45, 0.45), -0.01, rng.randf_range(-0.45, 0.45)))
		pebble_parts.append([r, xf])
	_layer_mesh[L.PEBBLES] = MeshKit.mesh_rocks(pebble_parts, _mats["pebble"])
	_layer_mesh[L.BOULDER] = MeshKit.mesh_rocks([[MeshKit.mesh_rock(9001, 3, 0.82), Transform3D()]], _mats["boulder"])
	rng.seed = 555
	_layer_mesh[L.LOG] = MeshKit.mesh_log(rng, _mats["log"])
	_warm = true
	_apply_quality(_settings_quality())
	warmup_ms = (Time.get_ticks_usec() - t0) / 1000.0


## Current Settings quality, without a compile-time dependency on the autoload (tools run without it).
static func _settings_quality() -> int:
	var loop := Engine.get_main_loop() as SceneTree
	var s: Node = loop.root.get_node_or_null(^"Settings") if loop != null and loop.root != null else null
	if s != null and s.has_method(&"gfx"):
		return clampi(int(s.call(&"gfx", "foliage")), 0, 3)
	return int(s.call(&"get_value", "graphics", "quality")) if s != null else 1


static func _shader(path: String) -> Shader:
	return load(path) as Shader


static func _make_materials() -> void:
	var bark_sh := _shader("res://world/flora/shaders/flora_bark.gdshader")
	var leaf_sh := _shader("res://world/flora/shaders/flora_leaves.gdshader")
	var grass_sh := _shader("res://world/flora/shaders/flora_grass.gdshader")
	var plant_sh := _shader("res://world/flora/shaders/flora_plant.gdshader")
	var rock_sh := _shader("res://world/flora/shaders/flora_rock.gdshader")
	var atlas := load("res://world/flora/textures/leaf_atlas.png") as Texture2D
	var atlas_n := load("res://world/flora/textures/leaf_atlas_n.png") as Texture2D
	var barks := [
		[load("res://world/flora/textures/oak_bark_diff.jpg"), load("res://world/flora/textures/oak_bark_nor.jpg"), Color(0.95, 0.88, 0.8), 0.35],
		[load("res://world/flora/textures/oak_bark_diff.jpg"), load("res://world/flora/textures/oak_bark_nor.jpg"), Color(0.72, 0.62, 0.58), 0.25],
		[load("res://world/flora/textures/pine_bark_diff.jpg"), load("res://world/flora/textures/pine_bark_nor.jpg"), Color(0.9, 0.82, 0.78), 0.15],
		[load("res://world/flora/textures/dead_bark_diff.jpg"), load("res://world/flora/textures/dead_bark_nor.jpg"), Color(0.78, 0.74, 0.7), 0.1],
	]
	var snow_hold := [0.55, 0.5, 1.0, 0.0]
	for kind in 4:
		for lod in 4:   # lod 3 = static (felling FX)
			var b := ShaderMaterial.new()
			b.shader = bark_sh
			b.set_shader_parameter(&"albedo_tex", barks[kind][0])
			b.set_shader_parameter(&"normal_tex", barks[kind][1])
			b.set_shader_parameter(&"bark_tint", barks[kind][2])
			b.set_shader_parameter(&"moss", barks[kind][3])
			b.set_shader_parameter(&"shadow_proxy", lod == 1)
			b.set_shader_parameter(&"static_mesh", lod == 3)
			var lf := ShaderMaterial.new()
			lf.shader = leaf_sh
			lf.set_shader_parameter(&"albedo_tex", atlas)
			lf.set_shader_parameter(&"normal_tex", atlas_n)
			lf.set_shader_parameter(&"snow_hold", snow_hold[kind])
			lf.set_shader_parameter(&"shadow_proxy", lod == 1)
			lf.set_shader_parameter(&"static_mesh", lod == 3)
			if kind == TreeKind.PINE:
				lf.set_shader_parameter(&"translucency", 0.35)
			if kind == TreeKind.DEAD:
				lf.set_shader_parameter(&"translucency", 0.1)
			_mats["bark_%d_%d" % [kind, lod]] = b
			_mats["leaves_%d_%d" % [kind, lod]] = lf
	for k in ["bush_bark", "log"]:
		var b := ShaderMaterial.new()
		b.shader = bark_sh
		b.set_shader_parameter(&"albedo_tex", barks[0][0])
		b.set_shader_parameter(&"normal_tex", barks[0][1])
		b.set_shader_parameter(&"bark_tint", Color(0.8, 0.72, 0.65))
		b.set_shader_parameter(&"moss", 0.9 if k == "log" else 0.2)
		b.set_shader_parameter(&"wind_sway", k != "log")
		_mats[k] = b
	for k in ["bush_leaves", "litter", "fx_leaves"]:
		var lf := ShaderMaterial.new()
		lf.shader = leaf_sh
		lf.set_shader_parameter(&"albedo_tex", atlas)
		lf.set_shader_parameter(&"normal_tex", atlas_n)
		lf.set_shader_parameter(&"snow_hold", 0.7 if k == "bush_leaves" else 1.0)
		if k == "litter":
			lf.set_shader_parameter(&"translucency", 0.05)
		if k == "fx_leaves":
			lf.set_shader_parameter(&"static_mesh", true)
		_mats[k] = lf
	# Grass families: [name, flex, frost, seed colour, translucency]
	for g in [["g_grass", 1.0, 1.0, Color(0.5, 0.4, 0.2), 0.35], ["g_tall", 1.3, 0.8, Color(0.5, 0.4, 0.24), 0.4],
			["g_reeds", 0.75, 0.6, Color(0.24, 0.15, 0.08), 0.45], ["g_stubble", 0.15, 0.4, Color(0.1, 0.08, 0.07), 0.05],
			["g_tuft", 0.8, 1.6, Color(0.6, 0.6, 0.55), 0.4], ["g_beach", 1.2, 0.6, Color(0.7, 0.62, 0.4), 0.5],
			["g_soul", 1.1, 0.0, Color(0.8, 0.85, 0.9), 0.9]]:
		var m := ShaderMaterial.new()
		m.shader = grass_sh
		m.set_shader_parameter(&"flex", g[1])
		m.set_shader_parameter(&"frost", g[2])
		m.set_shader_parameter(&"seed_color", g[3])
		m.set_shader_parameter(&"translucency", g[4])
		_mats[g[0]] = m
		var far := m.duplicate() as ShaderMaterial
		far.set_shader_parameter(&"lod_far", true)
		_mats[g[0] + "_far"] = far
	for p in [["p_flower", Color(0.2, 0.3, 0.08), Color(0.9, 0.7, 0.1), false], ["p_poppy", Color(0.22, 0.32, 0.1), Color(0.95, 0.75, 0.2), false],
			["p_heather", Color(0.2, 0.22, 0.1), Color(0.6, 0.3, 0.5), false], ["p_fern", Color(0.3, 0.38, 0.1), Color(0.5, 0.5, 0.2), true],
			["p_soul", Color(0.42, 0.5, 0.46), Color(0.95, 0.9, 0.7), false]]:
		var m := ShaderMaterial.new()
		m.shader = plant_sh
		m.set_shader_parameter(&"leaf_color", p[1])
		m.set_shader_parameter(&"centre_color", p[2])
		m.set_shader_parameter(&"tint_leaves", p[3])
		_mats[p[0]] = m
	var rock_a := load("res://world/flora/textures/rock_diff.jpg")
	var rock_n := load("res://world/flora/textures/rock_nor.jpg")
	for r in [["boulder", 0.35, 0.0], ["pebble", 1.2, 4.0]]:
		var m := ShaderMaterial.new()
		m.shader = rock_sh
		m.set_shader_parameter(&"albedo_tex", rock_a)
		m.set_shader_parameter(&"normal_tex", rock_n)
		m.set_shader_parameter(&"tex_scale", r[1])
		m.set_shader_parameter(&"ascii_class", r[2])
		_mats[r[0]] = m


## Pushes the quality's distances into the shared materials (cheap; only when it changes).
static func _apply_quality(q: int) -> void:
	q = clampi(q, 0, 3)
	if q == _quality:
		return
	_quality = q
	var md := _mesh_detail() if _warm else q
	for kind in 4:
		var bands := [[0.0, TREE_LOD0[md]], [TREE_LOD0[md], TREE_LOD1[md]], [TREE_LOD1[md], TREE_FAR[q]], [0.0, 100000.0]]
		for lod in 4:
			for m: ShaderMaterial in [_mats["bark_%d_%d" % [kind, lod]], _mats["leaves_%d_%d" % [kind, lod]]]:
				m.set_shader_parameter(&"lod_begin", bands[lod][0])
				m.set_shader_parameter(&"lod_end", bands[lod][1])
				m.set_shader_parameter(&"lod_fade", 4.0 if lod < 2 else 10.0)
	for k in ["bush_bark", "bush_leaves", "log"]:
		_mats[k].set_shader_parameter(&"lod_end", BUSH_RANGE[q] if k != "log" else ROCK_RANGE[q])
		_mats[k].set_shader_parameter(&"lod_fade", 8.0)
	_mats["litter"].set_shader_parameter(&"lod_end", PLANT_RANGE[q] * 0.7)
	_mats["litter"].set_shader_parameter(&"lod_fade", 8.0)
	for k in ["g_grass", "g_tall", "g_reeds", "g_stubble", "g_tuft", "g_beach", "g_soul"]:
		for m: ShaderMaterial in [_mats[k], _mats[k + "_far"]]:
			m.set_shader_parameter(&"fade_end", GRASS_RANGE[q])
			m.set_shader_parameter(&"fade_len", GRASS_RANGE[q] * 0.18)
			m.set_shader_parameter(&"thin_start", GRASS_RANGE[q] * 0.3)
			m.set_shader_parameter(&"lod_split", GRASS_SPLIT[q])
	for k in ["p_flower", "p_poppy", "p_heather", "p_fern", "p_soul"]:
		var m: ShaderMaterial = _mats[k]
		m.set_shader_parameter(&"fade_end", PLANT_RANGE[q])
		m.set_shader_parameter(&"fade_len", PLANT_RANGE[q] * 0.15)
		m.set_shader_parameter(&"thin_start", PLANT_RANGE[q] * 0.35)
	for k in ["boulder", "pebble"]:
		_mats[k].set_shader_parameter(&"fade_end", ROCK_RANGE[q] if k == "boulder" else PLANT_RANGE[q] * 0.4)


## A cached flora mesh (for tools/tests). kind: Tree, variant 0..3, lod 0..2.
static func tree_mesh(kind: int, variant: int, lod: int) -> ArrayMesh:
	warmup()
	return _tree_mesh[kind][variant][lod]


static func material(mat_name: String) -> ShaderMaterial:
	warmup()
	return _mats.get(mat_name)


# =========================================================================== planning (worker)

## Per-tree choices derived from the tree's seed only (so fell() matches what plan_chunk drew).
## Returns [variant, yaw, tint: Color, random 0..1].
static func tree_params(kind: int, seed_value: int) -> Array:
	var h := _hash_i(seed_value * 31 + kind * 977 + 12345)
	var variant := h % VARIANTS
	var yaw := float((h >> 4) & 1023) / 1024.0 * TAU
	var r1 := float((h >> 14) & 255) / 255.0
	var r2 := float((h >> 22) & 255) / 255.0
	var tint := Color(1, 1, 1)
	match kind:
		TreeKind.OAK:
			tint = Color(lerpf(0.88, 1.1, r1), lerpf(0.8, 1.1, r2), lerpf(0.8, 1.0, r1 * r2))
		TreeKind.CRIMSON:
			tint = Color(lerpf(0.85, 1.1, r1), lerpf(0.8, 1.05, r2), lerpf(0.85, 1.05, r2))
		TreeKind.PINE:
			tint = Color(lerpf(0.85, 1.05, r1), lerpf(0.9, 1.08, r2), lerpf(0.85, 1.0, r1))
		_:
			tint = Color(1, 1, 1)
	return [variant, yaw, tint, float(h & 1023) / 1023.0]


static func _hash_i(x: int) -> int:
	x = (x ^ (x >> 16)) * 0x45d9f3b
	x = x & 0x7fffffff
	x = (x ^ (x >> 16)) * 0x45d9f3b
	x = x & 0x7fffffff
	return x ^ (x >> 16)


## Colour palettes for the ground layers (instance colours; the shaders add per-instance variation).
const PAL := {
	"grass": [Color(0.15, 0.22, 0.05), Color(0.21, 0.26, 0.07), Color(0.3, 0.29, 0.09), Color(0.18, 0.24, 0.06)],
	"grass_dry": [Color(0.42, 0.34, 0.15), Color(0.36, 0.3, 0.13)],
	"grass_mud": [Color(0.14, 0.2, 0.05), Color(0.2, 0.22, 0.07)],
	"grass_dirt": [Color(0.28, 0.27, 0.1), Color(0.23, 0.23, 0.08)],
	"tall": [Color(0.5, 0.4, 0.19), Color(0.44, 0.35, 0.16), Color(0.38, 0.34, 0.14), Color(0.55, 0.45, 0.23)],
	"tall_green": [Color(0.3, 0.31, 0.11), Color(0.36, 0.33, 0.13), Color(0.27, 0.3, 0.09)],
	"reeds": [Color(0.36, 0.4, 0.14), Color(0.48, 0.45, 0.2), Color(0.55, 0.48, 0.24)],
	"stubble": [Color(0.1, 0.085, 0.07), Color(0.16, 0.13, 0.1), Color(0.22, 0.2, 0.18)],
	"frost": [Color(0.58, 0.6, 0.5), Color(0.62, 0.64, 0.56)],
	"tuft": [Color(0.5, 0.48, 0.26), Color(0.44, 0.44, 0.22)],
	"beach": [Color(0.62, 0.62, 0.4), Color(0.55, 0.58, 0.36), Color(0.7, 0.64, 0.42)],
	"soul": [Color(0.55, 0.6, 0.6), Color(0.62, 0.66, 0.64), Color(0.48, 0.55, 0.58)],
	"daisy": [Color(0.95, 0.94, 0.88), Color(0.95, 0.94, 0.88), Color(0.28, 0.4, 0.9), Color(0.95, 0.85, 0.9)],
	"buttercup": [Color(1.0, 0.78, 0.08), Color(1.0, 0.85, 0.2)],
	"poppy": [Color(0.85, 0.1, 0.05), Color(0.9, 0.18, 0.05), Color(0.95, 0.42, 0.06)],
	"spike": [Color(0.48, 0.3, 0.82), Color(0.85, 0.42, 0.65), Color(0.72, 0.32, 0.58), Color(0.95, 0.92, 0.95), Color(0.35, 0.38, 0.9)],
	"heather": [Color(0.62, 0.3, 0.58), Color(0.72, 0.4, 0.66), Color(0.55, 0.25, 0.48)],
	"iris": [Color(0.36, 0.3, 0.85), Color(0.5, 0.25, 0.7), Color(0.95, 0.8, 0.15)],
	"asphodel": [Color(0.93, 0.92, 0.96), Color(0.88, 0.84, 0.92), Color(0.9, 0.92, 0.88)],
	"fern": [Color(0.32, 0.4, 0.1), Color(0.5, 0.42, 0.12), Color(0.62, 0.36, 0.1), Color(0.55, 0.28, 0.08)],
	"bush": [Color(1.0, 0.95, 0.9), Color(0.9, 0.9, 0.85), Color(1.05, 1.0, 0.92)],
	"white": [Color(1, 1, 1)],
	"pebble": [Color(0.2, 0.5, 0.2), Color(0.1, 0.2, 0.4), Color(0.35, 0.8, 0.1)],
	"pebble_hell": [Color(0.0, 0.0, 0.6)],
	"boulder": [Color(0.55, 0.3, 0.1), Color(0.3, 0.7, 0.2), Color(0.75, 0.5, 0.3), Color(0.15, 0.2, 0.05)],
}

## Scatter rules per block id: [layer, max density /m2, scale min, scale max, xz/y ratio min, max,
## palette, sink m, tilt toward the ground normal 0..1, allowed without trees in the chunk].
const RULES := {
	3: [[L.GRASS, 8.0, 0.3, 0.55, 0.85, 1.3, "grass", 0.02, 0.3, true], [L.TALL_GRASS, 0.9, 0.7, 1.1, 0.9, 1.3, "tall_green", 0.02, 0.2, true],
		[L.DAISY, 0.6, 0.8, 1.2, 1.0, 1.0, "daisy", 0.0, 0.2, true], [L.BUTTERCUP, 0.45, 0.8, 1.2, 1.0, 1.0, "buttercup", 0.0, 0.2, true],
		[L.POPPY, 0.35, 0.8, 1.15, 1.0, 1.0, "poppy", 0.0, 0.2, true], [L.SPIKE, 0.25, 0.75, 1.25, 0.85, 1.15, "spike", 0.0, 0.1, true],
		[L.HEATHER, 0.3, 0.8, 1.3, 0.9, 1.6, "heather", 0.02, 0.4, false], [L.FERN, 0.6, 0.55, 0.95, 0.9, 1.2, "fern", 0.03, 0.3, false],
		[L.BUSH_AUTUMN, 0.05, 0.7, 1.4, 0.9, 1.4, "bush", 0.05, 0.0, true], [L.BUSH_GREEN, 0.012, 0.7, 1.3, 0.9, 1.4, "bush", 0.05, 0.0, true],
		[L.LITTER, 0.9, 1.0, 1.0, 0.8, 1.6, "white", -0.005, 1.0, false], [L.BOULDER, 0.006, 0.6, 1.6, 0.9, 1.3, "boulder", 0.15, 0.6, true],
		[L.LOG, 0.02, 0.85, 1.15, 1.0, 1.0, "white", 0.08, 1.0, false], [L.PEBBLES, 0.02, 0.7, 1.4, 1.0, 1.0, "pebble", 0.0, 1.0, true]],
	34: [[L.TALL_GRASS, 5.0, 0.7, 1.15, 0.9, 1.3, "tall", 0.02, 0.2, true], [L.GRASS, 2.2, 0.35, 0.6, 0.85, 1.3, "grass_dry", 0.02, 0.3, true],
		[L.POPPY, 0.4, 0.8, 1.15, 1.0, 1.0, "poppy", 0.0, 0.2, true], [L.SPIKE, 0.12, 0.75, 1.2, 0.85, 1.15, "spike", 0.0, 0.1, true],
		[L.BUSH_AUTUMN, 0.01, 0.7, 1.3, 0.9, 1.4, "bush", 0.05, 0.0, true], [L.BOULDER, 0.004, 0.6, 1.5, 0.9, 1.3, "boulder", 0.15, 0.6, true],
		[L.PEBBLES, 0.03, 0.7, 1.4, 1.0, 1.0, "pebble", 0.0, 1.0, true]],
	38: [[L.REEDS, 2.2, 1.1, 1.8, 0.8, 1.1, "reeds", 0.02, 0.1, true], [L.GRASS, 1.6, 0.35, 0.6, 0.85, 1.3, "grass_mud", 0.02, 0.3, true],
		[L.IRIS, 0.3, 0.85, 1.2, 1.0, 1.0, "iris", 0.0, 0.1, true], [L.FERN, 0.2, 0.55, 0.9, 0.9, 1.2, "fern", 0.03, 0.3, true]],
	5: [[L.TUFT, 0.6, 0.2, 0.38, 0.9, 1.3, "frost", 0.01, 0.3, true], [L.HEATHER, 0.06, 0.7, 1.1, 0.9, 1.4, "heather", 0.02, 0.4, false],
		[L.PEBBLES, 0.02, 0.7, 1.3, 1.0, 1.0, "pebble", 0.0, 1.0, true]],
	4: [[L.BEACH, 0.35, 0.55, 0.9, 0.7, 1.0, "beach", 0.03, 0.2, true], [L.PEBBLES, 0.03, 0.6, 1.2, 1.0, 1.0, "pebble", 0.0, 1.0, true]],
	22: [[L.STUBBLE, 0.9, 0.15, 0.4, 0.8, 1.4, "stubble", 0.02, 0.3, true], [L.PEBBLES, 0.05, 0.7, 1.4, 1.0, 1.0, "pebble", 0.0, 1.0, true]],
	2: [[L.GRASS, 1.2, 0.3, 0.5, 0.85, 1.3, "grass_dirt", 0.02, 0.3, true], [L.TUFT, 0.3, 0.22, 0.4, 0.9, 1.3, "tuft", 0.01, 0.3, true],
		[L.PEBBLES, 0.08, 0.7, 1.4, 1.0, 1.0, "pebble", 0.0, 1.0, true], [L.FERN, 0.15, 0.5, 0.85, 0.9, 1.2, "fern", 0.03, 0.3, false]],
	1: [[L.PEBBLES, 0.3, 0.7, 1.5, 1.0, 1.0, "pebble", 0.0, 1.0, true], [L.BOULDER, 0.02, 0.5, 1.4, 0.9, 1.3, "boulder", 0.15, 0.6, true],
		[L.TUFT, 0.12, 0.2, 0.35, 0.9, 1.3, "tuft", 0.01, 0.3, true], [L.HEATHER, 0.08, 0.7, 1.1, 0.9, 1.4, "heather", 0.02, 0.4, true]],
	12: [[L.PEBBLES, 0.35, 0.7, 1.5, 1.0, 1.0, "pebble", 0.0, 1.0, true], [L.TUFT, 0.1, 0.2, 0.35, 0.9, 1.3, "tuft", 0.01, 0.3, true]],
}
const RULES_HELL := {
	22: [[L.SOUL_GRASS, 2.2, 0.5, 0.95, 0.9, 1.3, "soul", 0.02, 0.2, true], [L.ASPHODEL, 0.35, 0.8, 1.2, 1.0, 1.0, "asphodel", 0.0, 0.2, true],
		[L.PEBBLES, 0.04, 0.7, 1.3, 1.0, 1.0, "pebble_hell", 0.0, 1.0, true]],
	39: [[L.SOUL_GRASS, 2.2, 0.5, 0.95, 0.9, 1.3, "soul", 0.02, 0.2, true], [L.ASPHODEL, 0.35, 0.8, 1.2, 1.0, 1.0, "asphodel", 0.0, 0.2, true]],
	1: [[L.PEBBLES, 0.12, 0.7, 1.4, 1.0, 1.0, "pebble_hell", 0.0, 1.0, true]],
	12: [[L.PEBBLES, 0.12, 0.7, 1.4, 1.0, 1.0, "pebble_hell", 0.0, 1.0, true]],
}

const CELL := 4.0   # scatter cells (m): rules and noise are evaluated per cell, not per instance


## Instance batch for one layer. Instances go to 4 random tiers so the first N of the final
## buffer are a uniform random subset (quality thinning = MultiMesh.visible_instance_count).
class Batch:
	var t0 := PackedFloat32Array()
	var t1 := PackedFloat32Array()
	var t2 := PackedFloat32Array()
	var t3 := PackedFloat32Array()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var count := 0

	func add(b: Basis, o: Vector3, cu: Color, tier: float) -> void:
		var row := PackedFloat32Array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y,
				b.x.z, b.y.z, b.z.z, o.z, cu.r, cu.g, cu.b, cu.a])
		if tier < 0.4:
			t0.append_array(row)
		elif tier < 0.65:
			t1.append_array(row)
		elif tier < 0.85:
			t2.append_array(row)
		else:
			t3.append_array(row)
		lo = lo.min(o)
		hi = hi.max(o)
		count += 1

	func finish(margin: Vector3, up: float) -> Dictionary:
		var buf := PackedFloat32Array()
		buf.append_array(t0)
		buf.append_array(t1)
		buf.append_array(t2)
		buf.append_array(t3)
		var tier_counts := PackedInt32Array([t0.size() / 16, t1.size() / 16, t2.size() / 16, t3.size() / 16])
		var aabb := AABB(lo - margin, (hi - lo) + margin * 2.0 + Vector3(0, up, 0))
		return {"buf": buf, "count": count, "aabb": aabb, "tiers": tier_counts}


## Triangles of one block inside one scatter cell, with an area-weighted picker.
class Cell:
	var cum := PackedFloat32Array()
	var tri := PackedInt32Array()
	var area := 0.0
	var nsum := Vector3.ZERO
	var csum := Vector3.ZERO
	var block := 0

	func add(i: int, a: float, n: Vector3, c: Vector3) -> void:
		area += a
		cum.append(area)
		tri.append(i)
		nsum += n * a
		csum += c * a


## WORKER THREAD (pure data in, pure data out). See docs/REALISM_CONTRACTS.md.
static func plan_chunk(origin: Vector3i, surface: Dictionary, trees: Array, dimension: int, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = _hash_i(origin.x * 92837111 ^ origin.y * 689287499 ^ origin.z * 283923481 ^ seed_value)
	var o := Vector3(origin)
	var hell := dimension == 1

	# ---- trees
	var tree_groups := {}   # kind*VARIANTS+variant -> Batch
	var far_groups := {}    # kind -> Batch
	var tree_pts: Array = []   # [Vector3 local, kind, height]
	for t: Array in trees:
		var root: Vector3 = t[0]
		var kind: int = clampi(int(t[1]), 0, 3)
		var hgt: float = clampf(float(t[2]), 2.0, 20.0)
		var tp := tree_params(kind, int(t[3]))
		var basis := Basis(Vector3.UP, tp[1]).scaled(Vector3.ONE * hgt)
		var pos := root - Vector3(0, 0.12, 0)
		var tint: Color = tp[2]
		var cu := Color(tint.r, tint.g, tint.b, tp[3])
		var key: int = kind * VARIANTS + int(tp[0])
		if not tree_groups.has(key):
			tree_groups[key] = Batch.new()
		(tree_groups[key] as Batch).add(basis, pos, cu, 0.0)
		if not far_groups.has(kind):
			far_groups[kind] = Batch.new()
		(far_groups[kind] as Batch).add(basis, pos, cu, 0.0)
		tree_pts.append([root, kind, hgt])

	# ---- bucket the up-facing triangles into cells per block
	var tris: PackedVector3Array = surface.get("tris", PackedVector3Array())
	var normals: PackedVector3Array = surface.get("normals", PackedVector3Array())
	var blocks: PackedByteArray = surface.get("blocks", PackedByteArray())
	var sky: PackedFloat32Array = surface.get("sky", PackedFloat32Array())
	var rules_by_block: Dictionary = RULES_HELL if hell else RULES
	var ntri := mini(tris.size() / 3, mini(normals.size(), mini(blocks.size(), sky.size())))
	var cells := {}
	for i in ntri:
		var sk := sky[i]
		if sk < 0.3:
			continue
		var nrm := normals[i]
		if nrm.y < 0.5:
			continue
		var block: int = blocks[i]
		if not rules_by_block.has(block):
			continue
		var a := tris[i * 3]
		var b := tris[i * 3 + 1]
		var c := tris[i * 3 + 2]
		# Paved squares, paths and building floors stay clear (ArchClearings).
		if ArchClearings.is_clear(dimension, seed_value, floori(o.x + a.x), floori(o.z + a.z)):
			continue
		# Caves mouths and overhangs get less light: thin the cover with the sky term.
		var area := (b - a).cross(c - a).length() * 0.5 * minf((sk - 0.3) * 2.0, 1.0)
		if area <= 0.0001:
			continue
		var cen := (a + b + c) * 0.33333
		var key := (int(cen.x / CELL) & 7) | ((int(cen.z / CELL) & 7) << 3) | ((int(cen.y / CELL) & 7) << 6) | (block << 9)
		var cell: Cell = cells.get(key)
		if cell == null:
			cell = Cell.new()
			cell.block = block
			cells[key] = cell
		cell.add(i, area, nrm, cen)

	# ---- scatter
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.seed = seed_value
	fn.frequency = 1.0
	fn.fractal_type = FastNoiseLite.FRACTAL_NONE
	var batches := {}
	var fields := PackedFloat32Array()
	fields.resize(7)
	var forest := 0
	for tp: Array in tree_pts:
		if tp[1] != TreeKind.DEAD:
			forest += 1
	var log_budget := 1 if forest >= 2 else 0
	for cell: Cell in cells.values():
		var cen := cell.csum / cell.area
		var nrm := cell.nsum.normalized()
		var wc := o + cen
		# Noise fields at the cell centre, 0..1.
		fields[0] = fn.get_noise_2d(wc.x * 0.07, wc.z * 0.07) * 0.5 + 0.5           # grass patches
		fields[1] = fn.get_noise_2d(wc.x * 0.05 + 100.0, wc.z * 0.05) * 0.5 + 0.5   # tall grass
		fields[2] = fn.get_noise_2d(wc.x * 0.08 + 200.0, wc.z * 0.08) * 0.5 + 0.5   # flower drifts
		fields[3] = fn.get_noise_2d(wc.x * 0.035 + 300.0, wc.z * 0.035) * 0.5 + 0.5 # flower species
		fields[4] = fn.get_noise_2d(wc.x * 0.11 + 400.0, wc.z * 0.11) * 0.5 + 0.5   # misc patches
		fields[5] = fn.get_noise_2d(wc.x * 0.04 + 500.0, wc.z * 0.04) * 0.5 + 0.5   # colour zones
		fields[6] = fn.get_noise_2d(wc.x * 0.13 + 600.0, wc.z * 0.13) * 0.5 + 0.5   # second patch field
		var near_d := 1000.0
		var near_kind := -1
		var trunks: Array = []
		for tp: Array in tree_pts:
			var d := Vector2(cen.x - tp[0].x, cen.z - tp[0].z).length()
			if d < near_d:
				near_d = d
				near_kind = tp[1]
			if d < CELL * 0.75 + 1.0:
				trunks.append(tp[0])
		for rule: Array in rules_by_block[cell.block]:
			var layer: int = rule[0]
			if not rule[9] and tree_pts.is_empty():
				continue
			var f := _cell_factor(layer, fields, near_d, near_kind, nrm.y)
			if f <= 0.0:
				continue
			var expect: float = cell.area * float(rule[1]) * f
			var n := int(expect)
			if rng.randf() < expect - n:
				n += 1
			if layer == L.LOG:
				if log_budget <= 0 or nrm.y < 0.9:
					continue
				n = mini(n, log_budget)
				log_budget -= n
			if n == 0:
				continue
			var bt: Batch = batches.get(layer)
			if bt == null:
				bt = Batch.new()
				batches[layer] = bt
			var pal: Array = PAL[rule[6]]
			var smin: float = rule[2]
			var smax: float = rule[3]
			var rmin: float = rule[4]
			var rmax: float = rule[5]
			var sink: float = rule[7]
			var up := Vector3.UP.lerp(nrm, rule[8]).normalized()
			var tilt := _orient(up, 0.0)
			var base_col: Color = pal[int(fields[5] * 0.999 * pal.size())]
			var mixed := layer == L.GRASS or layer == L.FERN or layer == L.TALL_GRASS
			var cnt := cell.tri.size()
			for k in n:
				var ti := cell.tri[mini(cell.cum.bsearch(rng.randf() * cell.area), cnt - 1)] * 3
				var r1 := rng.randf()
				var r2 := rng.randf()
				if r1 + r2 > 1.0:
					r1 = 1.0 - r1
					r2 = 1.0 - r2
				var a := tris[ti]
				var p := a + (tris[ti + 1] - a) * r1 + (tris[ti + 2] - a) * r2
				if not trunks.is_empty() and layer != L.LITTER and _in_trunk(p, trunks):
					continue
				var sy := rng.randf_range(smin, smax)
				var sx := sy * rng.randf_range(rmin, rmax)
				var col: Color = pal[rng.randi() % pal.size()]
				if mixed:
					col = base_col.lerp(col, 0.35)
				var basis := tilt * Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sx, sy, sx))
				# The thinning hash doubles as the tier, so the buffer is ordered by it and
				# far chunks can stop drawing the clumps the shader would thin out anyway.
				var thin := rng.randf()
				rng.randf()
				bt.add(basis, p - up * sink, Color(col.r, col.g, col.b, thin), thin)

	var groups: Array = []
	for layer: int in batches:
		var bt: Batch = batches[layer]
		var margin := Vector3(1.2, 0.3, 1.2)
		if layer == L.BOULDER or layer == L.LOG:
			margin = Vector3(3.0, 0.5, 3.0)
		var g := bt.finish(margin, 1.8)
		g["layer"] = layer
		groups.append(g)
	var tgroups: Array = []
	for key: int in tree_groups:
		var g := (tree_groups[key] as Batch).finish(Vector3(8, 1, 8), 14.0)
		g["kind"] = key / VARIANTS
		g["variant"] = key % VARIANTS
		tgroups.append(g)
	var fgroups: Array = []
	for kind: int in far_groups:
		var g := (far_groups[kind] as Batch).finish(Vector3(8, 1, 8), 14.0)
		g["kind"] = kind
		fgroups.append(g)
	var tree_info := PackedVector4Array()
	for tp: Array in tree_pts:
		var r: Vector3 = tp[0]
		tree_info.append(Vector4(r.x, r.y, r.z, float(tp[1]) + minf(tp[2], 99.0) / 100.0))
	return {"groups": groups, "trees": tgroups, "far": fgroups, "tree_info": tree_info, "dimension": dimension}


static func _in_trunk(p: Vector3, trunks: Array) -> bool:
	for r: Vector3 in trunks:
		if (p.x - r.x) * (p.x - r.x) + (p.z - r.z) * (p.z - r.z) < 0.36:
			return true
	return false


const _SPECIES_CENTRE := {L.DAISY: 0.2, L.BUTTERCUP: 0.42, L.POPPY: 0.62, L.SPIKE: 0.82}


## Density multiplier 0..1 for `layer` in a cell. f: noise fields (see plan_chunk).
static func _cell_factor(layer: int, f: PackedFloat32Array, near_d: float, near_kind: int, ny: float) -> float:
	var shade := 1.0 - smoothstep(2.0, 6.0, near_d)   # under a canopy
	match layer:
		L.GRASS:
			return clampf(0.65 + f[0] * 0.5, 0.0, 1.0) * (1.0 - shade * 0.55)
		L.TALL_GRASS:
			return (0.3 + 0.7 * smoothstep(0.45, 0.7, f[1])) * (1.0 - shade * 0.6)
		L.REEDS:
			return smoothstep(0.3, 0.6, f[4])
		L.DAISY, L.BUTTERCUP, L.POPPY, L.SPIKE:
			# Flowers grow in drifts; the species field decides which one dominates a drift.
			var species := 1.0 - smoothstep(0.08, 0.2, absf(f[3] - float(_SPECIES_CENTRE[layer])))
			return (smoothstep(0.55, 0.75, f[2]) * species + 0.03) * (1.0 - shade * 0.8)
		L.HEATHER:
			if near_kind != TreeKind.PINE and near_kind != -1:
				return 0.0
			return smoothstep(0.35, 0.6, f[6])
		L.IRIS:
			return smoothstep(0.55, 0.75, f[6])
		L.FERN:
			if near_kind == TreeKind.DEAD:
				return 0.0
			if near_kind == -1:
				return 0.3 * smoothstep(0.55, 0.7, f[4])
			return (1.0 - smoothstep(3.0, 10.0, near_d)) * smoothstep(0.3, 0.55, f[4])
		L.LITTER:
			if near_kind != TreeKind.OAK and near_kind != TreeKind.CRIMSON:
				return 0.0
			return 1.0 - smoothstep(2.5, 7.0, near_d)
		L.BUSH_AUTUMN:
			if near_kind == -1:
				return 0.3
			return 0.25 + 0.75 * (1.0 - smoothstep(3.0, 10.0, near_d))
		L.BUSH_GREEN:
			return 1.0 if near_d > 3.0 else 0.0
		L.BOULDER:
			return 1.0 if near_d > 2.5 and ny > 0.7 else 0.0
		L.LOG:
			return 1.0 if near_d > 2.5 and near_d < 12.0 else 0.0
		L.TUFT, L.STUBBLE, L.BEACH, L.SOUL_GRASS:
			return clampf(0.35 + f[4], 0.0, 1.0)
		L.ASPHODEL:
			return smoothstep(0.45, 0.7, f[2]) + 0.05
	return 1.0


## Basis with +Y along `up` and a yaw around it.
static func _orient(up: Vector3, yaw: float) -> Basis:
	var b := Basis(Vector3.UP, yaw)
	var axis := Vector3.UP.cross(up)
	if axis.length() < 0.0001:
		return b
	return Basis(axis.normalized(), Vector3.UP.angle_to(up)) * b


# =========================================================================== build (main thread)

static func build_chunk(plan: Dictionary, quality: int) -> Node3D:
	if not _warm:
		warmup()
	_apply_quality(quality)
	var q := clampi(quality, 0, 3)
	var root := Node3D.new()
	root.name = "Flora"
	for g: Dictionary in plan.get("groups", []):
		var layer: int = g.layer
		var mmi := _mmi(_layer_mesh[layer], g)
		_tag(mmi, 0, layer, g.tiers)
		if _layer_far[layer] != null:
			# Full clumps near the camera, sparse single-triangle clumps beyond the split.
			var far := _mmi(_layer_far[layer], g)
			_tag(far, 1, layer, g.tiers)
			root.add_child(far)
		root.add_child(mmi)
	for g: Dictionary in plan.get("trees", []):
		var lods: Array = _tree_mesh[g.kind][g.variant]
		root.add_child(_tag(_mmi(lods[0], g), 2, -1, PackedInt32Array()))
		root.add_child(_tag(_mmi(lods[1], g), 3, -1, PackedInt32Array()))
	for g: Dictionary in plan.get("far", []):
		root.add_child(_tag(_mmi(_tree_mesh[g.kind][0][2], g), 4, -1, PackedInt32Array()))
	_configure(root, q)
	var info: PackedVector4Array = plan.get("tree_info", PackedVector4Array())
	root.set_meta(&"trees", info)
	root.add_to_group(&"flora_chunks")
	return root


## Re-applies a quality to every flora chunk already in the scene (the
## graphics settings changed): instance counts, draw distances, shadows.
static func requalify(tree: SceneTree, quality: int) -> void:
	if not _warm:
		return
	_quality = -1
	_apply_quality(quality)
	for root: Node in tree.get_nodes_in_group(&"flora_chunks"):
		_configure(root as Node3D, clampi(quality, 0, 3))
		root.set_meta(&"lod_band", -1)
	_lod_cam = Vector3.INF


## Role of a flora MultiMeshInstance3D: 0 layer (near), 1 grass far LOD,
## 2 tree LOD0, 3 tree LOD1 (shadow caster), 4 tree far billboard.
static func _tag(mmi: MultiMeshInstance3D, role: int, layer: int, tiers: PackedInt32Array) -> MultiMeshInstance3D:
	mmi.set_meta(&"flora", [role, layer, tiers])
	return mmi


static func _configure(root: Node3D, q: int) -> void:
	var md := _mesh_detail()
	for c in root.get_children():
		var mmi := c as MultiMeshInstance3D
		if mmi == null or not mmi.has_meta(&"flora"):
			continue
		var tag: Array = mmi.get_meta(&"flora")
		var role: int = tag[0]
		var layer: int = tag[1]
		var mm := mmi.multimesh
		mmi.visibility_range_begin = 0.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		match role:
			0, 1:
				var small: bool = layer in _GRASSY or layer in _PLANTS or layer == L.LITTER or layer == L.PEBBLES
				if small:
					var tiers: PackedInt32Array = tag[2]
					var n := 0
					for t in q + 1:
						n += tiers[t]
					mm.visible_instance_count = n
				var reach: float = GRASS_RANGE[q]
				if layer in _PLANTS or layer == L.LITTER:
					reach = PLANT_RANGE[q]
				elif layer == L.BUSH_AUTUMN or layer == L.BUSH_GREEN:
					reach = BUSH_RANGE[q]
					# Bush shadows (600+ triangles each, every cascade) on Ultra only.
					if q >= 3:
						mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				elif layer == L.BOULDER or layer == L.LOG:
					reach = ROCK_RANGE[q]
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				elif layer == L.PEBBLES:
					reach = PLANT_RANGE[q] * 0.4
				mmi.visibility_range_end = reach + CHUNK_MARGIN
				if _layer_far[layer] != null:
					if role == 0:
						mmi.visibility_range_end = GRASS_SPLIT[q] + 4.0 + CHUNK_MARGIN
					else:
						mmi.visibility_range_begin = maxf(GRASS_SPLIT[q] - CHUNK_MARGIN, 0.0)
			2:
				mmi.visibility_range_end = TREE_LOD0[md] + CHUNK_MARGIN
			3:
				mmi.visibility_range_end = TREE_LOD1[md] + CHUNK_MARGIN
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			4:
				mmi.visibility_range_begin = maxf(TREE_LOD1[md] - CHUNK_MARGIN - 6.0, 0.0)
				mmi.visibility_range_end = TREE_FAR[q] + CHUNK_MARGIN


const _TIER_LO := [0.0, 0.4, 0.65, 0.85]
static var _lod_cursor := 0
static var _lod_cam := Vector3.INF
static var _lod_roots: Array = []
static var _lod_idle := 0


## Per chunk, draws only the grass and plant clumps the shaders keep at that
## distance (they thin with distance; dropped clumps used to still cost their
## vertices). A slice of the chunks per call; a full pass after the camera
## moved a few metres.
static func update_distance_lod(tree: SceneTree, cam: Vector3) -> void:
	if not _warm or _quality < 0:
		return
	_lod_idle += 1
	if _lod_roots.is_empty():
		if _lod_cam.distance_squared_to(cam) < 16.0 and _lod_idle < 90:
			return
		_lod_idle = 0
		_lod_cam = cam
		_lod_roots = tree.get_nodes_in_group(&"flora_chunks")
		_lod_cursor = 0
	var q := _quality
	var n := mini(_lod_roots.size(), _lod_cursor + 160)
	for i in range(_lod_cursor, n):
		var root := _lod_roots[i] as Node3D
		if root == null or not is_instance_valid(root) or not root.is_inside_tree():
			continue
		var d := maxf((root.global_position + Vector3(8, 8, 8)).distance_to(cam) - CHUNK_MARGIN, 0.0)
		var band := int(d / 6.0)
		if root.get_meta(&"lod_band", -1) == band:
			continue
		root.set_meta(&"lod_band", band)
		for c in root.get_children():
			var mmi := c as MultiMeshInstance3D
			if mmi == null or not mmi.has_meta(&"flora"):
				continue
			var tag: Array = mmi.get_meta(&"flora")
			var layer: int = tag[1]
			if int(tag[0]) > 1 or not (layer in _GRASSY or layer in _PLANTS):
				continue
			var grassy: bool = layer in _GRASSY
			var start: float = GRASS_RANGE[q] * 0.3 if grassy else PLANT_RANGE[q] * 0.35
			var end: float = GRASS_RANGE[q] if grassy else PLANT_RANGE[q]
			var keep := lerpf(1.0, 0.35 if grassy else 0.4, smoothstep(start, end, float(band) * 6.0))
			var tiers: PackedInt32Array = tag[2]
			var count := 0
			for t in q + 1:
				if _TIER_LO[t] < keep:
					count += tiers[t]
			mmi.multimesh.visible_instance_count = count
	_lod_cursor = n
	if _lod_cursor >= _lod_roots.size():
		_lod_roots = []


## Mesh detail (Settings.gfx "mesh_detail"): where trees switch level of detail.
static func _mesh_detail() -> int:
	var loop := Engine.get_main_loop() as SceneTree
	var s: Node = loop.root.get_node_or_null(^"Settings") if loop != null and loop.root != null else null
	return clampi(int(s.call(&"gfx", "mesh_detail")), 0, 3) if s != null and s.has_method(&"gfx") else _quality


static func _mmi(mesh: Mesh, g: Dictionary) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = g.count
	mm.buffer = g.buf
	mm.custom_aabb = g.aabb
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.custom_aabb = g.aabb
	return mmi


# =========================================================================== felling

## The tree at root_world topples along `direction`, bounces, breaks up into leaves and dust,
## and is gone after ~2.5 s. Purely visual.
static func fell(parent: Node3D, root_world: Vector3, kind: int, height: float, seed_value: int, direction: Vector3) -> void:
	warmup()
	var tp := tree_params(kind, seed_value)
	var fx: Node3D = FellFx.new()
	fx.setup(_tree_mesh[kind][tp[0]][0], [_mats["bark_%d_3" % kind], _mats["leaves_%d_3" % kind]],
			kind, height, tp[1], direction, seed_value)
	parent.add_child(fx)
	fx.global_position = root_world
