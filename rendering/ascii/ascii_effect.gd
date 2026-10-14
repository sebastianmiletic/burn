@tool
class_name AsciiEffect
extends CompositorEffect
## Scene analysis half of the ASCII renderer.
##
## Runs at PRE_TRANSPARENT inside the (reduced-resolution) 3D viewport, after
## lighting, GI, SSAO, SSR and volumetric fog. It decides, for every screen
## cell, which glyph to show and in what colour, and stores that in two small
## cell textures. ascii_composite.gdshader then draws the glyphs at native
## screen resolution, so they stay sharp while the 3D scene renders at a
## fraction of the pixels.
##
## Finally the scene colour is cleared (except emissive pass-through cells):
## Godot then draws the transparent FX (fire, sparks, spells) and its glow on
## black, and that image becomes the additive FX layer of the composite, so FX
## are never turned into glyphs and their bloom spills across the grid.
##
## Passes (rendering/ascii/shaders):
##   prep     -> per-pixel normal, linear depth, luminance, material id
##   edges    -> depth / normal (/ luminance) edge mask
##   sobel    -> edge direction per pixel
##   cells    -> per-cell glyph choice and colour
##   exposure -> adapted scene brightness for the next frame
##   finish   -> clear to the FX layer (or draw a debug view)

enum DebugView { NONE, EDGES, MATERIALS }

const CTX_PIXELS := &"ascii_pixels"
const SHADER_FILES := {
	&"prep": "res://rendering/ascii/shaders/ascii_prep.glsl",
	&"edges": "res://rendering/ascii/shaders/ascii_edges.glsl",
	&"sobel": "res://rendering/ascii/shaders/ascii_sobel.glsl",
	&"cells": "res://rendering/ascii/shaders/ascii_cells.glsl",
	&"exposure": "res://rendering/ascii/shaders/ascii_exposure.glsl",
	&"finish": "res://rendering/ascii/shaders/ascii_finish.glsl",
}

const FLAG_EDGES := 1
const FLAG_CLASSIC := 2
const FLAG_DITHER := 4
const FLAG_FLICKER := 8
const FLAG_RAIN := 16

# --- Output (set by AsciiView every frame) ------------------------------------
## Size of the final screen in physical pixels, and the glyph cell size there.
var output_size := Vector2i(1920, 1080)
var output_cell := Vector2i(8, 14)

# --- Look -------------------------------------------------------------------
var exposure := 1.0
## How strongly glyph choice follows the adapted scene brightness (0 = fixed).
var adaptation := 0.75
var adaptation_speed := 1.5
var exposure_key := 0.5
var gamma := 0.72
var saturation := 1.1
var contrast := 1.05
var classic_ramp := false
var dither := true
var rain_strokes := true
var liquid_speed := 1.4
var star_threshold := 0.05
var wind_slant := 0.4

# --- Edges ------------------------------------------------------------------
var draw_edges := true
var edge_fraction := 0.1
var depth_threshold := 0.18
var normal_threshold := 1.1
var edge_max_distance := 90.0
var luminance_edges := false
var dog_sigma := 1.0
var dog_scale := 1.6
var dog_threshold := 0.6

var flicker := 0.0
var debug_view := DebugView.NONE

# --- Camera (set from the main thread; used to linearise depth) ---------------
var z_near := 0.05
var z_far := 4000.0

var _rd: RenderingDevice
var _shaders := {}
var _pipelines := {}
var _nearest: RID
var _table: RID
var _exposure: RID
var _cell_color: RID
var _cell_aux: RID
var _cell_lum: RID
var _grid := Vector2i.ZERO
var _lock := Mutex.new()
var _pending_table := PackedInt32Array()
var _published := [RID(), RID(), Vector2i.ZERO]
var _start_usec := Time.get_ticks_usec()
var _last_frame_usec := 0


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT
	needs_normal_roughness = true
	RenderingServer.call_on_render_thread(_initialize)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		for rid: RID in [_cell_color, _cell_aux, _cell_lum]:
			if rid.is_valid():
				_rd.free_rid(rid)
		for key: StringName in _shaders:
			_rd.free_rid(_shaders[key])  # pipelines are freed with their shader
		for rid: RID in [_nearest, _table, _exposure]:
			if rid.is_valid():
				_rd.free_rid(rid)


## Glyph ramp table (see GlyphSet). Safe to call from the main thread.
func set_glyph_table(table: PackedInt32Array) -> void:
	_lock.lock()
	_pending_table = table
	_lock.unlock()


## [cell colour RID, cell aux RID, grid size] as last created on the render
## thread. AsciiView wraps the RIDs in Texture2DRD for the composite shader.
func published_cells() -> Array:
	_lock.lock()
	var out := _published.duplicate()
	_lock.unlock()
	return out


func is_ready() -> bool:
	return _table.is_valid()


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
	_nearest = _rd.sampler_create(state)
	_exposure = _rd.storage_buffer_create(8, PackedFloat32Array([0.0, 0.0]).to_byte_array())


func _consume_pending_table() -> void:
	_lock.lock()
	var table := _pending_table
	_pending_table = PackedInt32Array()
	_lock.unlock()
	if table.is_empty():
		return
	if _table.is_valid():
		_rd.free_rid(_table)
	var bytes := table.to_byte_array()
	_table = _rd.storage_buffer_create(bytes.size(), bytes)


func _ensure_cells(grid: Vector2i) -> void:
	if grid == _grid and _cell_color.is_valid():
		return
	_free_cells()
	var fmt := RDTextureFormat.new()
	fmt.width = grid.x
	fmt.height = grid.y
	fmt.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	_cell_color = _rd.texture_create(fmt, RDTextureView.new())
	_cell_aux = _rd.texture_create(fmt, RDTextureView.new())
	var lum_fmt := RDTextureFormat.new()
	lum_fmt.width = grid.x
	lum_fmt.height = grid.y
	lum_fmt.format = RenderingDevice.DATA_FORMAT_R16G16_SFLOAT
	lum_fmt.usage_bits = fmt.usage_bits
	_cell_lum = _rd.texture_create(lum_fmt, RDTextureView.new())
	_grid = grid
	_lock.lock()
	_published = [_cell_color, _cell_aux, grid]
	_lock.unlock()


func _free_cells() -> void:
	for rid: RID in [_cell_color, _cell_aux, _cell_lum]:
		if rid.is_valid():
			_rd.free_rid(rid)
	_cell_color = RID()
	_cell_aux = RID()
	_cell_lum = RID()


func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if _rd == null or callback_type != effect_callback_type:
		return
	_consume_pending_table()
	if not _table.is_valid():
		return

	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	if size.x <= 0 or size.y <= 0:
		return
	if not buffers.has_texture(&"forward_clustered", &"normal_roughness"):
		return

	var out_size := output_size
	var out_cell := output_cell
	var grid := Vector2i(ceili(out_size.x / float(out_cell.x)), ceili(out_size.y / float(out_cell.y)))
	_ensure_cells(grid)
	# Cell size in internal pixels; fractional when the 3D view is scaled.
	var csz := Vector2(out_cell) * Vector2(size) / Vector2(out_size)

	var px_groups := Vector2i(ceili(size.x / 8.0), ceili(size.y / 8.0))
	var cell_groups := Vector2i(ceili(grid.x / 8.0), ceili(grid.y / 8.0))
	var now := Time.get_ticks_usec()
	var t := float(now - _start_usec) / 1000000.0
	var dt := clampf(float(now - _last_frame_usec) / 1000000.0, 0.0, 0.25)
	_last_frame_usec = now
	var blend := 1.0 - exp(-dt * adaptation_speed)

	var usage := RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	var gbuf := _texture(buffers, &"gbuf", RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, size, usage)
	var lummat := _texture(buffers, &"lummat", RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, size, usage)
	var edge := _texture(buffers, &"edge", RenderingDevice.DATA_FORMAT_R16_SFLOAT, size, usage)
	var dir := _texture(buffers, &"dir", RenderingDevice.DATA_FORMAT_R16_SFLOAT, size, usage)

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
			_image(4, _cell_color),
			_image(5, _cell_aux),
			_storage(6, _table),
			_image(7, _cell_lum),
			_storage(8, _exposure),
		], [
			w, h, csz.x, csz.y,
			float(grid.x), float(grid.y), t, float(flags),
			exposure, gamma, edge_fraction, saturation,
			contrast, 1.0, flicker, liquid_speed,
			wind_slant, star_threshold, adaptation, exposure_key,
		], cell_groups)

		_dispatch(&"exposure", [
			_image(0, _cell_lum),
			_storage(1, _exposure),
		], [float(grid.x), float(grid.y), blend, 0.0], Vector2i(1, 1))

		_dispatch(&"finish", [
			_image(0, color),
			_image(1, _cell_aux),
			_image(2, lummat),
			_image(3, dir),
		], [
			w, h, csz.x, csz.y,
			float(grid.x), float(grid.y), float(debug_view), 0.0,
		], px_groups)


func _texture(buffers: RenderSceneBuffersRD, tex_name: StringName, format: int, size: Vector2i, usage: int) -> RID:
	if buffers.has_texture(CTX_PIXELS, tex_name):
		var f := buffers.get_texture_format(CTX_PIXELS, tex_name)
		if f.width == size.x and f.height == size.y:
			return buffers.get_texture(CTX_PIXELS, tex_name)
		buffers.clear_context(CTX_PIXELS)
	return buffers.create_texture(CTX_PIXELS, tex_name, format, usage, RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, true, false)


func _dispatch(shader: StringName, uniforms: Array, push: Array, groups: Vector2i) -> void:
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
