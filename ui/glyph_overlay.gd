class_name GlyphOverlay
extends CanvasLayer
## The glyph being drawn (hold a cast key and move the mouse, see PlayerArcana)
## as a glowing line, and the last verdict (spell name / fizzle) for a moment.

const VERDICT_SHOW := 1.6

var arcana: PlayerArcana
var _canvas: Control


func _ready() -> void:
	layer = 40
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_glyph)
	add_child(_canvas)
	if arcana != null:
		arcana.stroke_changed.connect(_canvas.queue_redraw)


func _process(_delta: float) -> void:
	# Fade the verdict out (only redraws while one is showing).
	if arcana != null and not arcana.drawing and _verdict_age() < VERDICT_SHOW + 0.1:
		_canvas.queue_redraw()


func _verdict_age() -> float:
	if arcana == null or arcana.last_verdict.is_empty():
		return INF
	return Time.get_ticks_msec() / 1000.0 - float(arcana.last_verdict.get("t", 0.0))


func _draw_glyph() -> void:
	if arcana == null:
		return
	var role_col: Color = Roles.ROLES.get(arcana.player.role, Roles.ROLES[Roles.DEFAULT])["color"]
	if arcana.drawing and arcana.stroke.size() > 1:
		_canvas.draw_polyline(arcana.stroke, Color(role_col, 0.35), 9.0, true)
		_canvas.draw_polyline(arcana.stroke, Color(1, 1, 1, 0.9), 3.0, true)
		_canvas.draw_circle(arcana.cursor, 5.0, Color(1, 1, 1, 0.9))
		return
	var age := _verdict_age()
	if age > VERDICT_SHOW:
		return
	var v := arcana.last_verdict
	var ok := String(v.get("result", "")) in ["cast", "weak", "wrong"]
	var spell := String(v.get("spell", ""))
	var text := String(Spells.SPELLS[spell]["name"]) if ok and Spells.SPELLS.has(spell) else "Fizzle"
	var font := ThemeDB.fallback_font
	var size := 30
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var vp := _canvas.size
	var col := Color(role_col if ok else Color(0.7, 0.7, 0.7), clampf(1.0 - age / VERDICT_SHOW, 0.0, 1.0))
	_canvas.draw_string(font, Vector2((vp.x - w) * 0.5, vp.y * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
