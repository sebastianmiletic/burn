class_name WorldView
extends Node
## The game's 3D view. The world is rendered straight to the window through
## `source_camera` (made current here) at full quality: an edge-aware upscaler
## (MetalFX spatial on Metal, AMD FSR on Vulkan / D3D12) with FXAA brings the
## 3D render resolution up to the window resolution.
## Adaptive resolution trades render resolution for frame rate only when the
## GPU is the bottleneck. A thin overlay adds the screen effects gameplay asks
## for: `tint` (damage, underworld), `flash` (lightning, big hits), vignette
## and film grain from the settings.

## The horizon (DistantLand) reaches the far side of the island.
const HORIZON_FAR := 4200.0
## Render-resolution presets per quality, as a fraction of the logical
## (UI-point) window size; on a 2x display High renders at half the physical
## resolution per axis and the upscaler (MetalFX spatial / FSR) fills in the rest.
const PRESET_SCALE := [0.65, 0.8, 1.0, 1.25]
const ADAPT_MIN := 0.55
const ADAPT_WINDOW := 0.5
const ADAPT_PROBE := 4.0

const MUL_SHADER := """
shader_type canvas_item;
render_mode unshaded, blend_mul;
uniform vec3 tint = vec3(1.0);
uniform float vignette = 0.3;
uniform float grain = 0.0;
uniform float time = 0.0;
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
void fragment() {
	vec2 uv = UV - 0.5;
	float v = clamp(1.0 - vignette * dot(uv, uv) * 2.4, 0.0, 1.0);
	float g = grain > 0.0 ? 1.0 - hash12(FRAGCOORD.xy + fract(time * 13.7) * 1000.0) * grain : 1.0;
	COLOR = vec4(tint * v * g, 1.0);
}
"""
const ADD_SHADER := """
shader_type canvas_item;
render_mode unshaded, blend_add;
uniform float flash = 0.0;
void fragment() {
	COLOR = vec4(vec3(0.9, 0.95, 1.0) * flash, 1.0);
}
"""

@export var source_camera: Camera3D

## Short white-hot flash (lightning, big hits). Decays automatically.
var flash := 0.0
## Multiplies the final image (damage vignette, underworld grade).
var tint := Color.WHITE
## The viewport the world renders into (the window's).
var viewport: Viewport
## The camera rendering the world (the source camera).
var camera: Camera3D:
	get:
		return source_camera

var _layer: CanvasLayer
var _mul: ColorRect
var _add: ColorRect
var _mul_mat := ShaderMaterial.new()
var _add_mat := ShaderMaterial.new()
var _time := 0.0
var _adaptive_scale := 1.0
var _frame_average := 1.0 / 60.0
var _scale_timer := 0.0
var _window_time := 0.0
var _window_frames := 0
var _ceiling := 1.0
var _probe_timer := 0.0
var _probe_wait := ADAPT_PROBE
var _verify_avg := 0.0
var _verify_scale := 1.0
var _cpu_hold := 0.0
var _window := Vector2i.ZERO
var _vignette := 0.3
var _no_horizon := "--no-horizon" in OS.get_cmdline_user_args()   # profiling aid


func _ready() -> void:
	viewport = get_viewport()
	viewport.disable_3d = false
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.use_taa = false
	viewport.positional_shadow_atlas_size = 4096
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)

	var mul_shader := Shader.new()
	mul_shader.code = MUL_SHADER
	_mul_mat.shader = mul_shader
	var add_shader := Shader.new()
	add_shader.code = ADD_SHADER
	_add_mat.shader = add_shader
	_layer = CanvasLayer.new()
	_layer.layer = -10   # above the 3D world, below every UI layer
	_mul = _overlay(_mul_mat)
	_add = _overlay(_add_mat)
	add_child(_layer)

	Settings.changed.connect(func(section: String, _k: String) -> void:
		if section == "graphics" or section == "display":
			_apply_settings())
	_apply_settings()
	get_tree().root.size_changed.connect(_resize)


func _overlay(mat: ShaderMaterial) -> ColorRect:
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.material = mat
	r.visible = false
	_layer.add_child(r)
	return r


func _exit_tree() -> void:
	if viewport != null:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		viewport.scaling_3d_scale = 1.0


func _process(delta: float) -> void:
	_update_adaptive_resolution(delta)
	_time += delta
	flash = maxf(0.0, flash - delta * 4.0)
	if source_camera != null and is_instance_valid(source_camera) and source_camera.is_inside_tree():
		if not source_camera.current:
			source_camera.make_current()
		if not _no_horizon:
			source_camera.far = maxf(source_camera.far, HORIZON_FAR)
	if DisplayServer.get_name() != "headless" and DisplayServer.window_get_size() != _window:
		_resize()
	var tinted := not tint.is_equal_approx(Color.WHITE)
	_mul.visible = tinted or _vignette > 0.001 or float(Settings.get_value("graphics", "grain")) > 0.0
	if _mul.visible:
		_mul_mat.set_shader_parameter(&"tint", Vector3(tint.r, tint.g, tint.b))
		_mul_mat.set_shader_parameter(&"time", _time)
	_add.visible = flash > 0.001
	if _add.visible:
		# Subtle: the sky and the bolt's own light carry lightning.
		_add_mat.set_shader_parameter(&"flash", flash * 0.22)


## Screen-space position of a world point, in the main window's coordinates.
func unproject(world: Vector3) -> Vector2:
	return source_camera.unproject_position(world) if source_camera != null else Vector2.ZERO


func _apply_settings() -> void:
	_vignette = float(Settings.get_value("graphics", "vignette"))
	_mul_mat.set_shader_parameter(&"vignette", _vignette)
	_mul_mat.set_shader_parameter(&"grain", float(Settings.get_value("graphics", "grain")))
	_resize()


func _resize() -> void:
	if viewport == null:
		return
	var window := DisplayServer.window_get_size() if DisplayServer.get_name() != "headless" else Vector2i(1280, 720)
	_window = window
	var screen := maxf(1.0, DisplayServer.screen_get_scale(DisplayServer.window_get_current_screen())) if DisplayServer.get_name() != "headless" else 1.0
	var forced := float(Settings.get_value("graphics", "render_scale"))
	var preset: float = forced if forced > 0.0 else PRESET_SCALE[clampi(int(Settings.get_value("graphics", "quality")), 0, 3)]
	# Fraction of the physical window the 3D scene is rendered at.
	var scale := clampf(preset * _adaptive_scale / screen, 0.25, 1.0)
	var upscaler := _upscaler()
	viewport.scaling_3d_mode = upscaler
	viewport.scaling_3d_scale = scale
	# FXAA unless a temporal upscaler is smoothing edges already.
	var temporal := upscaler == Viewport.SCALING_3D_MODE_FSR2 or upscaler == Viewport.SCALING_3D_MODE_METALFX_TEMPORAL
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if temporal else Viewport.SCREEN_SPACE_AA_FXAA
	# Spatial upscalers sharpen; keep textures crisp at the output size.
	viewport.fsr_sharpness = 0.35


## The resolution the 3D scene is actually rendered at (before upscaling).
func internal_size() -> Vector2i:
	if viewport == null:
		return Vector2i.ZERO
	var full := Vector2((viewport as Window).size) if viewport is Window else viewport.get_visible_rect().size
	return Vector2i((full * viewport.scaling_3d_scale).round())


## Temporal upscaler on this renderer, or bilinear where none is available.
static func _upscaler() -> Viewport.Scaling3DMode:
	if "--no-upscaler" in OS.get_cmdline_user_args() or RenderingServer.get_current_rendering_method() != "forward_plus":
		return Viewport.SCALING_3D_MODE_BILINEAR
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--upscaler="):
			var named := {"bilinear": Viewport.SCALING_3D_MODE_BILINEAR, "fsr": Viewport.SCALING_3D_MODE_FSR,
				"fsr2": Viewport.SCALING_3D_MODE_FSR2, "metalfx_spatial": Viewport.SCALING_3D_MODE_METALFX_SPATIAL,
				"metalfx_temporal": Viewport.SCALING_3D_MODE_METALFX_TEMPORAL}
			return named.get(arg.trim_prefix("--upscaler="), Viewport.SCALING_3D_MODE_BILINEAR)
	if DisplayServer.get_name() == "headless":
		return Viewport.SCALING_3D_MODE_BILINEAR
	# Spatial upscalers: measured on the M4 at 2940x1652 output, MetalFX
	# temporal cost ~15 ms a frame more than MetalFX spatial / FSR 1 for the
	# same render resolution, which no amount of saved pixels pays back.
	# (--upscaler=metalfx_temporal / fsr2 still selects the temporal ones.)
	if RenderingServer.get_current_rendering_driver_name() == "metal":
		return Viewport.SCALING_3D_MODE_METALFX_SPATIAL
	return Viewport.SCALING_3D_MODE_FSR


## Adaptive resolution. It only trades pixels when pixels are the problem.
## A window of frames over budget drops the scale in one step sized to the
## overshoot; the next window checks the drop helped. If it did not (the
## frame is CPU-bound - on Metal the driver's GPU wait shows up as CPU time, so
## this has to be measured, not read), the old resolution comes back and no
## drop is tried again for a while. With vsync a frame on budget looks the
## same at any load, so the scale climbs straight back to the last level that
## held 60 fps and probes above it every few seconds, backing off after a
## failed probe.
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
	_window_frames += 1
	_scale_timer += delta
	if _scale_timer < ADAPT_WINDOW:
		return
	var avg := _window_time / _window_frames
	_window_time = 0.0
	_window_frames = 0
	_scale_timer = 0.0
	_frame_average = avg
	var budget := 1.0 / 60.0
	var old := _adaptive_scale
	_probe_timer += ADAPT_WINDOW
	_cpu_hold = maxf(0.0, _cpu_hold - ADAPT_WINDOW)
	if _verify_avg > 0.0:
		# The window after a drop: did fewer pixels buy frame time?
		if avg > _verify_avg * 0.93 and avg > budget * 1.07:
			_adaptive_scale = _verify_scale
			_ceiling = maxf(_ceiling, _verify_scale)
			_cpu_hold = 20.0
		_verify_avg = 0.0
	elif avg > budget * 1.07:
		if _cpu_hold <= 0.0 and _adaptive_scale > ADAPT_MIN + 0.001:
			# Pixel cost scales with the square of the scale.
			var want := _adaptive_scale * sqrt(budget / avg) * 0.97
			_verify_scale = _adaptive_scale
			_verify_avg = avg
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


## Adaptive scale (1 = the preset's resolution) and average frame time (ms), for F3 and reports.
func adaptive_state() -> Vector2:
	return Vector2(_adaptive_scale, _frame_average * 1000.0)
