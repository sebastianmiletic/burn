class_name PerfOverlay
extends CanvasLayer
## F3 performance overlay: fps, CPU/GPU frame time, draw calls, objects.
## Network fields read "offline" until the multiplayer milestone wires them.

var _panel := TerminalPanel.new()
var _accum := 0.0
var _frames := 0
var _worst_ms := 0.0
var _fps := 0.0


func _ready() -> void:
	layer = 51
	visible = false
	_panel.title = "PERF"
	_panel.min_columns = 26
	add_child(_panel)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F3:
		visible = not visible
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_accum += delta
	_frames += 1
	_worst_ms = maxf(_worst_ms, delta * 1000.0)
	if _accum < 0.5:
		return
	_fps = _frames / _accum
	var vp := get_viewport().get_viewport_rid()
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var size := get_viewport().get_texture().get_size()
	if visible:
		var a := TerminalPanel.ACCENT
		var t := TerminalPanel.TEXT
		_panel.lines = [
			[["fps        ", t], ["%.0f" % _fps, a]],
			[["frame      ", t], ["%.2f ms (worst %.1f)" % [1000.0 / maxf(_fps, 0.001), _worst_ms], a]],
			[["cpu render ", t], ["%.2f ms" % cpu, a]],
			[["gpu        ", t], ["%.2f ms" % gpu, a]],
			[["draw calls ", t], ["%d" % draws, a]],
			[["primitives ", t], ["%d" % prims, a]],
			[["nodes      ", t], ["%d" % nodes, a]],
			[["resolution ", t], ["%dx%d" % [size.x, size.y], a]],
			[["3d view    ", t], [_view_text(), a]],
			[["ping       ", t], ["offline", TerminalPanel.DIM]],
			[["server tick", t], [" offline", TerminalPanel.DIM]],
		]
		_panel.position = Vector2(get_viewport().get_visible_rect().size.x - _panel.size.x - 16, 16)
	_accum = 0.0
	_frames = 0
	_worst_ms = 0.0


func fps() -> float:
	return _fps


## The 3D view's render resolution, upscaler and adaptive scale.
func _view_text() -> String:
	var w := GameWorld.instance
	if w == null or w.view == null or w.view.viewport == null:
		return "-"
	var view := w.view
	var inner: Vector2i = view.internal_size()
	var mode: String = ["bilinear", "FSR", "FSR 2", "MetalFX", "MetalFX temporal", "nearest"][clampi(view.viewport.scaling_3d_mode, 0, 5)]
	var state: Vector2 = view.adaptive_state()
	return "%dx%d %s x%.2f" % [inner.x, inner.y, mode, state.x]
