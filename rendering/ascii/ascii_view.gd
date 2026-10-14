class_name AsciiView
extends Node
## The game's 3D view. Renders the world through `source_camera` into a
## reduced-resolution SubViewport (where AsciiEffect analyses it), then draws
## the glyph grid full-screen at native resolution behind the UI.
##
## Gameplay code keeps using an ordinary Camera3D in the main tree (ray
## picking, screen projection all work in window coordinates); this node
## mirrors it every frame. The root viewport's own 3D rendering is disabled so
## the world is only rendered once.

const COMPOSITE := preload("res://rendering/ascii/ascii_composite.gdshader")

@export var source_camera: Camera3D

## Short white-hot flash (lightning, big hits). Decays automatically.
var flash := 0.0
## Multiplies the final image (damage vignette, underworld grade).
var tint := Color.WHITE

var viewport: SubViewport
var camera: Camera3D

var _layer: CanvasLayer
var _rect: ColorRect
var _material: ShaderMaterial
var _cell_color := Texture2DRD.new()
var _cell_aux := Texture2DRD.new()
var _published: Array = []
var _time := 0.0


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.name = "WorldViewport"
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false
	viewport.positional_shadow_atlas_size = 4096
	viewport.audio_listener_enable_3d = true
	camera = Camera3D.new()
	camera.name = "AsciiCamera"
	camera.compositor = Ascii.make_compositor()
	viewport.add_child(camera)
	add_child(viewport)

	_material = ShaderMaterial.new()
	_material.shader = COMPOSITE
	_material.set_shader_parameter(&"fx_layer", viewport.get_texture())

	_layer = CanvasLayer.new()
	_layer.layer = -10
	_rect = ColorRect.new()
	_rect.color = Color.BLACK
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.material = _material
	_layer.add_child(_rect)
	add_child(_layer)

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--composite-debug="):
			_material.set_shader_parameter(&"debug_mode", int(arg.trim_prefix("--composite-debug=")))
	get_tree().root.disable_3d = true
	Ascii.atlas_changed.connect(_on_atlas)
	if Ascii.atlas_texture != null:
		_on_atlas(Ascii.atlas_texture, Ascii.atlas_cell)
	Settings.changed.connect(func(_s: String, _k: String) -> void: _apply_settings())
	_apply_settings()
	_resize()
	get_tree().root.size_changed.connect(_resize)


func _exit_tree() -> void:
	get_tree().root.disable_3d = false


func _process(delta: float) -> void:
	_time += delta
	flash = maxf(0.0, flash - delta * 4.0)
	if source_camera != null and is_instance_valid(source_camera):
		camera.global_transform = source_camera.global_transform
		camera.fov = source_camera.fov
		camera.near = source_camera.near
		camera.far = source_camera.far
		camera.cull_mask = source_camera.cull_mask
		if source_camera.attributes != null:
			camera.attributes = source_camera.attributes
	Ascii.effect.z_near = camera.near
	Ascii.effect.z_far = camera.far

	var published := Ascii.effect.published_cells()
	if published != _published:
		_published = published
		_cell_color.texture_rd_rid = published[0]
		_cell_aux.texture_rd_rid = published[1]
		# Re-bind: the material resolves a texture's RID when the parameter is
		# set, and a Texture2DRD only gets one once it wraps a real texture.
		_material.set_shader_parameter(&"cell_color", _cell_color)
		_material.set_shader_parameter(&"cell_color_soft", _cell_color)
		_material.set_shader_parameter(&"cell_aux", _cell_aux)
		_material.set_shader_parameter(&"grid", Vector2(published[2]))

	var window := DisplayServer.window_get_size() if DisplayServer.get_name() != "headless" else Vector2i(1280, 720)
	if Vector2i(Ascii.effect.output_size) != window:
		_resize()
	_material.set_shader_parameter(&"time", _time)
	_material.set_shader_parameter(&"flash", flash)
	_material.set_shader_parameter(&"tint", Vector3(tint.r, tint.g, tint.b))
	_material.set_shader_parameter(&"raw_mode", not Ascii.effect.enabled or Ascii.effect.debug_view != AsciiEffect.DebugView.NONE or not Ascii.effect.is_ready())


## Screen-space position of a world point, in the main window's coordinates.
func unproject(world: Vector3) -> Vector2:
	return source_camera.unproject_position(world) if source_camera != null else Vector2.ZERO


func _resize() -> void:
	var window := DisplayServer.window_get_size() if DisplayServer.get_name() != "headless" else Vector2i(1280, 720)
	var logical := Vector2(window) / Ascii.screen_scale()
	viewport.size = Vector2i((logical * Settings.render_scale()).round()).max(Vector2i(64, 64))
	Ascii.effect.output_size = window
	Ascii.effect.output_cell = Ascii.atlas_cell if Ascii.atlas_cell != Vector2i.ZERO else Ascii.output_cell_size()
	_material.set_shader_parameter(&"target_px", Vector2(window))


func _on_atlas(texture: ImageTexture, cell: Vector2i) -> void:
	_material.set_shader_parameter(&"atlas", texture)
	_material.set_shader_parameter(&"cell_px", Vector2(cell))
	Ascii.effect.output_cell = cell
	_resize()


func _apply_settings() -> void:
	var style := Ascii.style()
	_material.set_shader_parameter(&"style", clampi(style if style != Settings.Style.CLASSIC else Settings.Style.FULL_COLOUR, 0, 3))
	_material.set_shader_parameter(&"brightness", float(Settings.get_value("graphics", "brightness")))
	_material.set_shader_parameter(&"vignette", float(Settings.get_value("graphics", "vignette")))
	_material.set_shader_parameter(&"grain", float(Settings.get_value("graphics", "grain")))
	_material.set_shader_parameter(&"shimmer", 0.8 if Settings.get_value("graphics", "shimmer") else 0.0)
	_material.set_shader_parameter(&"bg_fill", float(Settings.get_value("graphics", "bg_fill")))
	_material.set_shader_parameter(&"glyph_glow", 0.35 * float(Settings.get_value("graphics", "bloom")))
	if viewport != null:
		_resize()
