class_name AsciiDebugOverlay
extends CanvasLayer
## Renderer debug panel and hotkeys for the ASCII pass.

signal rain_toggled(on: bool)
signal orbit_toggled(on: bool)

var _panel := TerminalPanel.new()
var _rain_on := true
var _orbit_on := true
var _visible_help := true


func _ready() -> void:
	layer = 50
	_panel.title = "ASCII RENDERER"
	_panel.position = Vector2(16, 16)
	add_child(_panel)
	Ascii.cell_size_changed.connect(func(_p: int, _c: Vector2i) -> void: _refresh())
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var fx := Ascii.effect
	match key.keycode:
		KEY_F1:
			Ascii.set_enabled(not Ascii.is_enabled())
		KEY_F2:
			fx.debug_view = AsciiEffect.DebugView.NONE if fx.debug_view == AsciiEffect.DebugView.EDGES else AsciiEffect.DebugView.EDGES
		KEY_F4:
			fx.debug_view = AsciiEffect.DebugView.NONE if fx.debug_view == AsciiEffect.DebugView.MATERIALS else AsciiEffect.DebugView.MATERIALS
		KEY_F5:
			fx.grid_overlay = not fx.grid_overlay
		KEY_1:
			Ascii.set_cell_preset(Ascii.CellPreset.FINE)
		KEY_2:
			Ascii.set_cell_preset(Ascii.CellPreset.DEFAULT)
		KEY_3:
			Ascii.set_cell_preset(Ascii.CellPreset.CHUNKY)
		KEY_G:
			fx.classic_ramp = not fx.classic_ramp
		KEY_E:
			fx.draw_edges = not fx.draw_edges
		KEY_B:
			fx.background_tint = 0.0 if fx.background_tint > 0.0 else 0.18
		KEY_L:
			fx.flicker = 0.0 if fx.flicker > 0.0 else 0.6
		KEY_K:
			fx.shimmer = 0.0 if fx.shimmer > 0.0 else 0.8
		KEY_V:
			fx.vignette = 0.0 if fx.vignette > 0.0 else 0.35
		KEY_N:
			fx.grain = 0.0 if fx.grain > 0.0 else 0.12
		KEY_R:
			_rain_on = not _rain_on
			rain_toggled.emit(_rain_on)
		KEY_O:
			_orbit_on = not _orbit_on
			orbit_toggled.emit(_orbit_on)
		KEY_H:
			_visible_help = not _visible_help
			_panel.visible = _visible_help
		_:
			return
	get_viewport().set_input_as_handled()
	_refresh()


func _refresh() -> void:
	var fx := Ascii.effect
	var cell := fx.current_cell_size()
	var views := ["off", "edges", "materials"]
	_panel.lines = [
		_row("F1", "ascii", Ascii.is_enabled()),
		[["F2/F4 ", TerminalPanel.ACCENT], ["debug view  ", TerminalPanel.TEXT], [views[fx.debug_view], TerminalPanel.ACCENT]],
		_row("F5", "cell grid", fx.grid_overlay),
		[["1 2 3 ", TerminalPanel.ACCENT], ["cells       ", TerminalPanel.TEXT],
			["%s (%dx%d px)" % [Ascii.PRESET_NAMES[Ascii.cell_preset], cell.x, cell.y], TerminalPanel.ACCENT]],
		[["G     ", TerminalPanel.ACCENT], ["glyph set   ", TerminalPanel.TEXT], ["classic" if fx.classic_ramp else "material", TerminalPanel.ACCENT]],
		_row("E", "edge glyphs", fx.draw_edges),
		_row("B", "bg tint", fx.background_tint > 0.0),
		_row("L", "flicker", fx.flicker > 0.0),
		_row("K", "shimmer", fx.shimmer > 0.0),
		_row("V", "vignette", fx.vignette > 0.0),
		_row("N", "film grain", fx.grain > 0.0),
		_row("R", "rain", _rain_on),
		_row("O", "auto orbit", _orbit_on),
		[["F3    ", TerminalPanel.ACCENT], ["perf overlay", TerminalPanel.TEXT]],
		[["H     ", TerminalPanel.ACCENT], ["hide panel", TerminalPanel.DIM]],
		[["drag  ", TerminalPanel.DIM], ["orbit  ", TerminalPanel.DIM], ["wheel ", TerminalPanel.DIM], ["zoom  ", TerminalPanel.DIM], ["WASD ", TerminalPanel.DIM], ["move", TerminalPanel.DIM]],
	]


func _row(key: String, label: String, on: bool) -> Array:
	return [
		[key.rpad(6), TerminalPanel.ACCENT],
		[label.rpad(12), TerminalPanel.TEXT],
		["on" if on else "off", TerminalPanel.ACCENT if on else TerminalPanel.DIM],
	]
