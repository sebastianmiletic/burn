@tool
class_name AsciiEffect
extends CompositorEffect
## Compositor effect that redraws the lit opaque scene as coloured glyphs.
##
## Runs at PRE_TRANSPARENT: lighting, GI, SSAO, SSR and volumetric fog are
## already in the colour buffer, but transparent materials are not. Fire,
## sparks and spells use transparent/additive materials, so Godot draws them
## after this pass, on top of the glyphs, and its glow + tonemap passes then
## bloom them across neighbouring cells.
##
## Five compute passes (rendering/ascii/shaders):
##   prep    -> per-pixel normal, linear depth, luminance, material id
##   edges   -> depth / normal / luminance edge mask
##   sobel   -> edge direction per pixel
##   cells   -> per-cell glyph choice and colour
##   compose -> glyph atlas lookup written back into the colour buffer
##
## Settings are plain properties written from the main thread (see the Ascii
## autoload) and read on the render thread each frame.

enum DebugView { NONE, EDGES, MATERIALS }

const CTX_PIXELS := &"ascii_pixels"
const CTX_CELLS := &"ascii_cells"
const SHADER_FILES := {
	&"prep": "res://rendering/ascii/shaders/ascii_prep.glsl",
	&"edges": "res://rendering/ascii/shaders/ascii_edges.glsl",
	&"sobel": "res://rendering/ascii/shaders/ascii_sobel.glsl",
	&"cells": "res://rendering/ascii/shaders/ascii_cells.glsl",
	&"compose": "res://rendering/ascii/shaders/ascii_compose.glsl",
	&"exposure": "res://rendering/ascii/shaders/ascii_exposure.glsl",
}

const FLAG_EDGES := 1
const FLAG_CLASSIC := 2
const FLAG_DITHER := 4
const FLAG_FLICKER := 8
const FLAG_RAIN := 16

# --- Look -------------------------------------------------------------------
var exposure := 1.0
## How strongly glyph choice follows the adapted scene brightness (0 = fixed).
var adaptation := 0.8
var adaptation_speed := 1.5
var exposure_key := 0.45
var gamma := 0.8
var saturation := 1.15
var contrast := 1.08
var glyph_gain := 2.2
var background_tint := 0.18
var background_level := 0.0015
var classic_ramp := false
var dither := true
var rain_strokes := true
var liquid_speed := 1.4
var star_threshold := 0.05
var wind_slant := 0.4

# --- Edges ------------------------------------------------------------------
var draw_edges := true
var edge_fraction := 0.08
var depth_threshold := 0.18
var normal_threshold := 1.1
var edge_max_distance := 90.0
var luminance_edges := false
var dog_sigma := 1.0
var dog_scale := 1.6
var dog_threshold := 0.6

# --- Optional effects ---------------------------------------------------------
var flicker := 0.0
var shimmer := 0.0
var vignette := 0.35
var grain := 0.0

# --- Debug ------------------------------------------------------------------
var debug_view := DebugView.NONE
var grid_overlay := false

# --- Camera (set from the main thread; used to linearise depth) ---------------
var z_near := 0.05
var z_far := 4000.0

var _rd: RenderingDevice
var _shaders := {}
var _pipelines := {}
var _nearest: RID
var _atlas: RID
var _table: RID
var _exposure: RID
var _last_frame_usec := 0
var _cell := Vector2i.ZERO
var _lock := Mutex.new()
var _pending_image: Image
var _pending_table := PackedInt32Array()
var _pending_cell := Vector2i.ZERO
var _start_usec := Time.get_ticks_usec()
var _skip := PackedStringArray()  # profiling: --ascii-skip=prep,edges,...


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ascii-skip="):
			_skip = arg.trim_prefix("--ascii-skip=").split(",")
	effect_callback_type = EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT
	needs_normal_roughness = true
	RenderingServer.call_on_render_thread(_initialize)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		for key: StringName in _shaders:
			_rd.free_rid(_shaders[key])  # pipelines are freed with their shader
		for rid: RID in [_nearest, _atlas, _table, _exposure]:
			if rid.is_valid():
				_rd.free_rid(rid)


## Hands over a new glyph atlas. Safe to call from the main thread; the
## textures are swapped on the render thread before the next frame.
func set_atlas(image: Image, cell: Vector2i, table: PackedInt32Array) -> void:
	_lock.lock()
	_pending_image = image
	_pending_cell = cell
	_pending_table = table
	_lock.unlock()


func current_cell_size() -> Vector2i:
	return _cell


func _initialize() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		if DisplayServer.get_name() == "headless":
			return  # tests and the dedicated server render nothing
		push_error("ASCII pass needs the Forward+ or Mobile renderer (RenderingDevice).")
		return
	for key: StringName in SHADER_FILES:
		var file: RDShaderFile = load(SHADER_FILES[key])
		var spirv: RDShaderSPIRV = file.get_spirv()
		if spirv.compile_error_compute != "":
			push_error("ASCII shader %s failed to compile:\n%s" % [key, spirv.compile_error_compute])
			_rd = null
			return
		var shader := _rd.shader_create_from_spirv(spirv, String(key))
		_shaders[key] = shader
		_pipelines[key] = _rd.compute_pipeline_create(shader)
	var state := RDSamplerState.new()
	state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_nearest = _rd.sampler_create(state)
	_exposure = _rd.storage_buffer_create(8, PackedFloat32Array([0.0, 0.0]).to_byte_array())


func _consume_pending_atlas() -> void:
	_lock.lock()
	var image := _pending_image
	var cell := _pending_cell
	var table := _pending_table
	_pending_image = null
	_lock.unlock()
	if image == null:
		return

	if _atlas.is_valid():
		_rd.free_rid(_atlas)
	if _table.is_valid():
		_rd.free_rid(_table)

	var fmt := RDTextureFormat.new()
	fmt.width = image.get_width()
	fmt.height = image.get_height()
	fmt.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	_atlas = _rd.texture_create(fmt, RDTextureView.new(), [image.get_data()])

	var bytes := table.to_byte_array()
	_table = _rd.storage_buffer_create(bytes.size(), bytes)
	_cell = cell


func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if _rd == null or callback_type != effect_callback_type:
		return
	_consume_pending_atlas()
	if not _atlas.is_valid():
		return

	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	if size.x <= 0 or size.y <= 0:
		return
	if not buffers.has_texture(&"forward_clustered", &"normal_roughness"):
		return

	var csz := _cell
	var grid := Vector2i(ceili(size.x / float(csz.x)), ceili(size.y / float(csz.y)))
	var px_groups := Vector2i(ceili(size.x / 8.0), ceili(size.y / 8.0))
	var cell_groups := Vector2i(ceili(grid.x / 8.0), ceili(grid.y / 8.0))
	var now := Time.get_ticks_usec()
	var t := float(now - _start_usec) / 1000000.0
	var dt := clampf(float(now - _last_frame_usec) / 1000000.0, 0.0, 0.25)
	_last_frame_usec = now
	var blend := 1.0 - exp(-dt * adaptation_speed)

	var usage := RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	var gbuf := _texture(buffers, CTX_PIXELS, &"gbuf", RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, size, usage)
	var lummat := _texture(buffers, CTX_PIXELS, &"lummat", RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, size, usage)
	var edge := _texture(buffers, CTX_PIXELS, &"edge", RenderingDevice.DATA_FORMAT_R16_SFLOAT, size, usage)
	var dir := _texture(buffers, CTX_PIXELS, &"dir", RenderingDevice.DATA_FORMAT_R16_SFLOAT, size, usage)
	var cell_color := _texture(buffers, CTX_CELLS, &"cell_color", RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, grid, usage)
	var cell_info := _texture(buffers, CTX_CELLS, &"cell_info", RenderingDevice.DATA_FORMAT_R32_UINT, grid, usage)
	var cell_lum := _texture(buffers, CTX_CELLS, &"cell_lum", RenderingDevice.DATA_FORMAT_R16G16_SFLOAT, grid, usage)

	var flags := 0
	if draw_edges:
		flags |= FLAG_EDGES
	if classic_ramp:
		flags |= FLAG_CLASSIC
	if dither:
		flags |= FLAG_DITHER
	if flicker > 0.0:
		flags |= FLAG_FLICKER
	if rain_strokes:
		flags |= FLAG_RAIN

	var w := float(size.x)
	var h := float(size.y)

	for view in buffers.get_view_count():
		var color := buffers.get_color_layer(view)
		var depth := buffers.get_depth_layer(view)
		var normal_roughness := buffers.get_texture_slice(&"forward_clustered", &"normal_roughness", view, 0, 1, 1)

		_dispatch(&"prep", [
			_sampled(0, depth),
			_sampled(1, normal_roughness),
			_image(2, color),
			_image(3, gbuf),
			_image(4, lummat),
		], [w, h, z_near, z_far], px_groups)

		_dispatch(&"edges", [
			_image(0, gbuf),
			_image(1, lummat),
			_image(2, edge),
		], [
			w, h, 0.0, 0.0,
			depth_threshold, normal_threshold, edge_max_distance, 1.0 if luminance_edges else 0.0,
			dog_sigma, dog_scale, dog_threshold, 0.0,
		], px_groups)

		_dispatch(&"sobel", [
			_image(0, edge),
			_image(1, dir),
		], [w, h, 0.0, 0.0], px_groups)

		_dispatch(&"cells", [
			_image(0, color),
			_image(1, lummat),
			_image(2, gbuf),
			_image(3, dir),
			_image(4, cell_color),
			_image(5, cell_info),
			_storage(6, _table),
			_image(7, cell_lum),
			_storage(8, _exposure),
		], [
			w, h, float(csz.x), float(csz.y),
			float(grid.x), float(grid.y), t, float(flags),
			exposure, gamma, edge_fraction, saturation,
			contrast, glyph_gain, flicker, liquid_speed,
			wind_slant, star_threshold, adaptation, exposure_key,
		], cell_groups)

		_dispatch(&"exposure", [
			_image(0, cell_lum),
			_storage(1, _exposure),
		], [float(grid.x), float(grid.y), blend, 0.0], Vector2i(1, 1))

		_dispatch(&"compose", [
			_image(0, color),
			_image(1, cell_color),
			_image(2, cell_info),
			_sampled(3, _atlas),
			_image(4, lummat),
			_image(5, dir),
		], [
			w, h, float(csz.x), float(csz.y),
			float(grid.x), float(grid.y), t, float(debug_view),
			background_tint, vignette, grain, shimmer,
			1.0 if grid_overlay else 0.0, background_level, glyph_gain, 0.0,
		], px_groups)


func _texture(buffers: RenderSceneBuffersRD, ctx: StringName, tex_name: StringName, format: int, size: Vector2i, usage: int) -> RID:
	if buffers.has_texture(ctx, tex_name):
		var f := buffers.get_texture_format(ctx, tex_name)
		if f.width == size.x and f.height == size.y:
			return buffers.get_texture(ctx, tex_name)
		# Size changed (e.g. new cell size): drop the whole context and rebuild.
		buffers.clear_context(ctx)
	return buffers.create_texture(ctx, tex_name, format, usage, RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, true, false)


func _dispatch(shader: StringName, uniforms: Array, push: Array, groups: Vector2i) -> void:
	if not _skip.is_empty() and _skip.has(String(shader)):
		return
	var typed: Array[RDUniform] = []
	typed.assign(uniforms)
	var uniform_set := UniformSetCacheRD.get_cache(_shaders[shader], 0, typed)
	var bytes := PackedFloat32Array(push).to_byte_array()
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipelines[shader])
	_rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	_rd.compute_list_set_push_constant(list, bytes, bytes.size())
	_rd.compute_list_dispatch(list, groups.x, groups.y, 1)
	_rd.compute_list_end()


func _image(binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(rid)
	return u


func _sampled(binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u.binding = binding
	u.add_id(_nearest)
	u.add_id(rid)
	return u


func _storage(binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = binding
	u.add_id(rid)
	return u
