class_name MapLayers
extends RefCounted
## GPU textures for one dimension's map image (see MapImage), shared by the
## minimap and the world map, and the uniforms that feed map_common.

var color: ImageTexture
var height: ImageTexture
var detail: ImageTexture
var metres_per_pixel := 4.0
var world_size := 2048.0
var sea_level := 12.0
var liquid := 0

static var _cache: Array = []   # [WeakRef(image), MapLayers], most recent last


## Layers for `img` (cached; the world images never change after loading).
## `fallback_mpp` is used for images without MapImage metadata.
static func for_image(img: Image, fallback_mpp := 4.0) -> MapLayers:
	if img == null:
		return null
	for entry: Array in _cache:
		if (entry[0] as WeakRef).get_ref() == img:
			return entry[1]
	var l := MapLayers.new()
	l._build(img, fallback_mpp)
	_cache.append([weakref(img), l])
	while _cache.size() > 4:
		_cache.pop_front()
	return l


## Layers of the world's map for `dim` (null while there is none).
static func of(world: Object, dim: int) -> MapLayers:
	var img: Variant = UiContext.call_on(world, "map_image", [dim], null)
	if not (img is Image):
		return null
	return for_image(img, float(UiContext.call_on(world, "map_metres_per_pixel", [dim], 4.0)))


func _build(img: Image, fallback_mpp: float) -> void:
	color = ImageTexture.create_from_image(img)
	metres_per_pixel = float(img.get_meta("metres_per_pixel", fallback_mpp))
	world_size = float(img.get_meta("world_size", img.get_width() * metres_per_pixel))
	sea_level = float(img.get_meta("sea_level", WorldGen.SEA_LEVEL))
	liquid = int(img.get_meta("liquid", 0))
	var h: Variant = img.get_meta("height") if img.has_meta("height") else null
	if h is Image:
		height = ImageTexture.create_from_image(h)
	var d: Variant = img.get_meta("detail") if img.has_meta("detail") else null
	if d is Image:
		detail = ImageTexture.create_from_image(d)


## World position -> map uv.
func uv(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z) / world_size


func apply(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter(&"color_tex", color)
	mat.set_shader_parameter(&"has_map", true)
	mat.set_shader_parameter(&"has_height", height != null)
	if height != null:
		mat.set_shader_parameter(&"height_tex", height)
		mat.set_shader_parameter(&"height_size", Vector2(height.get_width(), height.get_height()))
	mat.set_shader_parameter(&"has_detail", detail != null)
	if detail != null:
		mat.set_shader_parameter(&"detail_tex", detail)
	mat.set_shader_parameter(&"world_size", world_size)
	mat.set_shader_parameter(&"sea_level", sea_level)
	mat.set_shader_parameter(&"liquid", liquid)
