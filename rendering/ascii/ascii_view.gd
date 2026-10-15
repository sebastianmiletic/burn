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
## Far plane of the rendered view (metres).
const HORIZON_FAR := 4200.0

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
const ADAPT_MIN := 0.55
const ADAPT_WINDOW := 0.5
const ADAPT_PROBE := 4.0
var _adaptive_scale := 1.0
var _frame_average := 1.0 / 60.0
var _scale_timer := 0.0
var _window_time := 0.0
var _window_cpu := 0.0
var _window_frames := 0
var _ceiling := 1.0
var _probe_timer := 0.0
var _probe_wait := ADAPT_PROBE
var _applied_size := Vector2i.ZERO


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.name = "WorldViewport"
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false
	viewport.positional_shadow_atlas_size = 4096
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
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
	if viewport.size != _applied_size:
		# Someone else (the menu backdrop) sized the view directly: that size is
		# the render resolution, so no upscaling on top of it.
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		viewport.scaling_3d_scale = 1.0
		_applied_size = viewport.size
	_update_adaptive_resolution(delta)
	_time += delta
	flash = maxf(0.0, flash - delta * 4.0)
	if source_camera != null and is_instance_valid(source_camera):
		camera.global_transform = source_camera.global_transform
		camera.fov = source_camera.fov
		camera.near = source_camera.near
		# The horizon (DistantLand) reaches the far side of the island; gameplay
		# cameras keep their own (shorter) far plane for picking.
		camera.far = maxf(source_camera.far, HORIZON_FAR)
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
	var screen := Ascii.screen_scale()
	var logical := Vector2(window) / screen
	var scale := Settings.render_scale()
	var off := Ascii.style() == Settings.Style.OFF
	if off and float(Settings.get_value("graphics", "render_scale")) < 0:
		scale = [0.65, 0.8, 1.0, 1.25][int(Settings.get_value("graphics", "quality"))]
	var internal := Vector2i((logical * scale * _adaptive_scale).round()).max(Vector2i(64, 64))
	var upscaler := _upscaler() if off else Viewport.SCALING_3D_MODE_BILINEAR
	if upscaler != Viewport.SCALING_3D_MODE_BILINEAR:
		# Plain 3D view: render at the internal resolution and let the temporal
		# upscaler (MetalFX on Metal, FSR 2 elsewhere) reconstruct the full
		# window resolution; it doubles as the anti-aliasing.
		viewport.size = window.max(Vector2i(64, 64))
		viewport.scaling_3d_mode = upscaler
		viewport.scaling_3d_scale = clampf(float(internal.x) / float(viewport.size.x), 0.25, 1.0)
	else:
		# The ASCII pass analyses the scene at the internal size itself.
		viewport.size = internal
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		viewport.scaling_3d_scale = 1.0
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if off and upscaler == Viewport.SCALING_3D_MODE_BILINEAR else Viewport.SCREEN_SPACE_AA_DISABLED
	_applied_size = viewport.size
	Ascii.effect.output_size = window
	Ascii.effect.output_cell = Ascii.atlas_cell if Ascii.atlas_cell != Vector2i.ZERO else Ascii.output_cell_size()
	_material.set_shader_parameter(&"target_px", Vector2(window))


## The resolution the 3D scene is actually rendered at (before upscaling).
func internal_size() -> Vector2i:
	if viewport == null:
		return Vector2i.ZERO
	return Vector2i((Vector2(viewport.size) * viewport.scaling_3d_scale).round())


## Temporal upscaler for the plain 3D view on this renderer, or bilinear.
static func _upscaler() -> Viewport.Scaling3DMode:
	if "--no-upscaler" in OS.get_cmdline_user_args() or RenderingServer.get_current_rendering_method() != "forward_plus":
		return Viewport.SCALING_3D_MODE_BILINEAR
	if RenderingServer.get_current_rendering_driver_name() == "metal":
		return Viewport.SCALING_3D_MODE_METALFX_TEMPORAL
	return Viewport.SCALING_3D_MODE_FSR2


## Adaptive resolution. It only trades pixels when pixels are the problem:
## frames over budget whose time is mostly spent outside the CPU (GPU-bound)
## drop the scale in one step sized to the overshoot; CPU-bound frames (where a
## smaller image would not help) never lower it. With vsync a frame on budget
## looks the same at any load, so the scale climbs straight back to the last
## level that held 60 fps and probes above it every few seconds, backing off
## after a failed probe.
func _update_adaptive_resolution(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var enabled := bool(Settings.get_value("graphics", "adaptive_resolution")) and float(Settings.get_value("graphics", "render_scale")) < 0
	var cap := int(Settings.get_value("display", "fps_cap"))
	if not enabled or (cap > 0 and cap < 60):
		if _adaptive_scale != 1.0:
			_adaptive_scale = 1.0
			_ceiling = 1.0
			_resize()
		return
	# Loading stalls and hitches are not a resolution problem.
	_window_time += minf(delta, 0.05)
	_window_cpu += _cpu_frame_time()
	_window_frames += 1
	_scale_timer += delta
	if _scale_timer < ADAPT_WINDOW:
		return
	var avg := _window_time / _window_frames
	var cpu := _window_cpu / _window_frames
	_window_time = 0.0
	_window_cpu = 0.0
	_window_frames = 0
	_scale_timer = 0.0
	_frame_average = avg
	var budget := 1.0 / 60.0
	var old := _adaptive_scale
	_probe_timer += ADAPT_WINDOW
	if avg > budget * 1.07:
		if 1.0 - cpu / avg > 0.2:
			# Pixel cost scales with the square of the scale.
			var want := _adaptive_scale * sqrt(budget / avg) * 0.97
			_adaptive_scale = clampf(minf(want, _adaptive_scale - 0.04), ADAPT_MIN, 1.0)
			if _probe_timer < _probe_wait * 1.5:
				_probe_wait = minf(_probe_wait * 2.0, 40.0)   # a probe just failed: wait longer
			_ceiling = maxf(old - 0.03, _adaptive_scale)
			_probe_timer = 0.0
	elif avg < budget * 1.03:
		if _adaptive_scale < _ceiling:
			_adaptive_scale = minf(_ceiling, _adaptive_scale + 0.06)
		elif _ceiling < 1.0 and _probe_timer >= _probe_wait:
			_ceiling = minf(1.0, _ceiling + 0.05)
			_adaptive_scale = _ceiling
			_probe_timer = 0.0
		elif _probe_timer > _probe_wait * 3.0:
			_probe_wait = maxf(ADAPT_PROBE, _probe_wait * 0.5)   # stable: probe sooner again
	if not is_equal_approx(old, _adaptive_scale):
		_resize()


## Main-thread CPU time of the last frame: scripts, physics, render setup and
## the 3D view's render submission (s).
func _cpu_frame_time() -> float:
	var t := Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	t += RenderingServer.get_frame_setup_time_cpu() / 1000.0
	if viewport != null:
		t += RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid()) / 1000.0
	return t


## Adaptive scale (1 = the preset's resolution) and average frame time (ms), for F3 and reports.
func adaptive_state() -> Vector2:
	return Vector2(_adaptive_scale, _frame_average * 1000.0)

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
