class_name ArenaMaterials
extends RefCounted
## Shared materials for the arenas (main thread). The architecture material is
## one ShaderMaterial per arena parameter set over the shared terrain texture
## arrays; flames, silk and flows are shared by kind.

const ARENA_SHADER := preload("res://world/architecture/arenas/arena.gdshader")
const FLAME_SHADER := preload("res://world/architecture/arenas/arena_flame.gdshader")
const WEB_SHADER := preload("res://world/architecture/arenas/arena_web.gdshader")
const FLOW_SHADER := preload("res://world/architecture/arenas/arena_flow.gdshader")

const FLAME_KINDS := {
	"fire": [Color(1.0, 0.86, 0.55), Color(1.0, 0.32, 0.05), 4.0, 1.0],
	"candle": [Color(1.0, 0.9, 0.62), Color(1.0, 0.45, 0.1), 3.5, 1.4],
	"soul": [Color(0.75, 1.0, 1.0), Color(0.1, 0.55, 0.9), 4.5, 0.8],
	"green": [Color(0.85, 1.0, 0.6), Color(0.25, 0.75, 0.15), 4.0, 0.9],
	"hell": [Color(1.0, 0.75, 0.45), Color(0.9, 0.12, 0.03), 5.0, 1.2],
}

static var _cache := {}


static func arena(params: Dictionary) -> ShaderMaterial:
	var key := "arena:" + str(params)
	if _cache.has(key):
		return _cache[key]
	TerrainTextures.load_arrays()
	var m := ShaderMaterial.new()
	m.shader = ARENA_SHADER
	m.set_shader_parameter(&"albedo_tex", TerrainTextures._albedo)
	m.set_shader_parameter(&"normal_tex", TerrainTextures._normal)
	for k: String in params:
		m.set_shader_parameter(StringName(k), params[k])
	_cache[key] = m
	return m


static func flame(flame_kind: String) -> ShaderMaterial:
	var key := "flame:" + flame_kind
	if _cache.has(key):
		return _cache[key]
	var d: Array = FLAME_KINDS.get(flame_kind, FLAME_KINDS["fire"])
	var m := ShaderMaterial.new()
	m.shader = FLAME_SHADER
	m.set_shader_parameter(&"hot_color", d[0])
	m.set_shader_parameter(&"cool_color", d[1])
	m.set_shader_parameter(&"intensity", d[2])
	m.set_shader_parameter(&"speed", d[3])
	_cache[key] = m
	return m


static func web() -> ShaderMaterial:
	if _cache.has("web"):
		return _cache["web"]
	var m := ShaderMaterial.new()
	m.shader = WEB_SHADER
	_cache["web"] = m
	return m


static func flow(settings: Dictionary) -> ShaderMaterial:
	var key := "flow:" + str(settings)
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = FLOW_SHADER
	for k: String in settings:
		m.set_shader_parameter(StringName(k), settings[k])
	_cache[key] = m
	return m


## A unit flame quad (x -0.5..0.5, y 0..1) for the flame MultiMesh.
static func flame_quad() -> ArrayMesh:
	if _cache.has("flame_quad"):
		return _cache["flame_quad"]
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)])
	a[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	a[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	a[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	_cache["flame_quad"] = mesh
	return mesh
