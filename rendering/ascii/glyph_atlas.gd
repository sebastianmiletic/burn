class_name GlyphAtlas
extends Node
## Renders every glyph the ASCII pass uses into a one-row atlas, at exactly
## the cell size in physical pixels, so glyphs stay crisp at every preset.
## Also measures each glyph's ink coverage to sort the brightness ramps.

signal built(image: Image, cell: Vector2i, table: PackedInt32Array)

const FONT_REGULAR := "res://assets/fonts/JetBrainsMono-Regular.ttf"
const FONT_BOLD := "res://assets/fonts/JetBrainsMono-Bold.ttf"

var _generation := 0


## Starts an asynchronous build; `built` fires a couple of frames later.
## A newer request supersedes any build still in flight.
func build(cell: Vector2i, bold: bool) -> void:
	_generation += 1
	var generation := _generation
	var glyphs := GlyphSet.all_glyphs()
	var font: FontFile = load(FONT_BOLD if bold else FONT_REGULAR)
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font.hinting = TextServer.HINTING_LIGHT
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	var font_size := fit_font_size(font, cell)

	var viewport := SubViewport.new()
	viewport.size = Vector2i(cell.x * glyphs.length(), cell.y)
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var canvas := _GlyphCanvas.new(font, font_size, cell, glyphs)
	canvas.size = Vector2(viewport.size)
	viewport.add_child(canvas)
	add_child(viewport)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	if generation != _generation:
		return

	image.convert(Image.FORMAT_R8)
	var coverage := {}
	for i in glyphs.length():
		var sum := 0.0
		for y in cell.y:
			for x in cell.x:
				sum += image.get_pixel(i * cell.x + x, y).r
		coverage[glyphs[i]] = sum / float(cell.x * cell.y)
	built.emit(image, cell, GlyphSet.build_table(coverage))


## Largest font size whose glyphs fit the cell.
static func fit_font_size(font: Font, cell: Vector2i) -> int:
	for s in range(96, 3, -1):
		var w := font.get_char_size("M".unicode_at(0), s).x
		var h := font.get_ascent(s) + font.get_descent(s)
		if w <= float(cell.x) and h <= float(cell.y) * 1.08:
			return s
	return 4


class _GlyphCanvas:
	extends Control

	var _font: Font
	var _font_size: int
	var _cell: Vector2i
	var _glyphs: String

	func _init(font: Font, font_size: int, cell: Vector2i, glyphs: String) -> void:
		_font = font
		_font_size = font_size
		_cell = cell
		_glyphs = glyphs

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
		var ascent := _font.get_ascent(_font_size)
		var descent := _font.get_descent(_font_size)
		var baseline := floorf((float(_cell.y) - (ascent + descent)) * 0.5 + ascent)
		for i in _glyphs.length():
			var ch := _glyphs[i]
			var advance := _font.get_char_size(ch.unicode_at(0), _font_size).x
			var x := float(i * _cell.x) + floorf((float(_cell.x) - advance) * 0.5)
			draw_char(_font, Vector2(x, baseline), ch, _font_size, Color.WHITE)
