class_name RuneGlyph
extends Control
## One of the 16 party runes, drawn as glowing ember strokes.
## Party codes are 4 rune indices (0..15); the network track only uses the
## indices, this file owns how they look and how they are typed.

signal pressed(rune: int)

const NAMES: Array[String] = ["Ash", "Ur", "Thorn", "Ansu", "Raid", "Kaun", "Gyfu", "Wyn",
		"Hagal", "Naud", "Isa", "Jera", "Eoh", "Perth", "Elhaz", "Sol"]
const KEYS: Array[Key] = [KEY_F, KEY_U, KEY_T, KEY_A, KEY_R, KEY_K, KEY_G, KEY_W,
		KEY_H, KEY_N, KEY_I, KEY_J, KEY_E, KEY_P, KEY_Z, KEY_S]

## Strokes in a unit box (x right, y down). Angular, carved-looking forms.
const STROKES := [
	[[Vector2(0.36, 0.04), Vector2(0.36, 0.96)], [Vector2(0.36, 0.32), Vector2(0.74, 0.08)], [Vector2(0.36, 0.58), Vector2(0.74, 0.34)]],
	[[Vector2(0.3, 0.96), Vector2(0.3, 0.06), Vector2(0.72, 0.3), Vector2(0.72, 0.96)]],
	[[Vector2(0.34, 0.04), Vector2(0.34, 0.96)], [Vector2(0.34, 0.26), Vector2(0.7, 0.5), Vector2(0.34, 0.74)]],
	[[Vector2(0.34, 0.04), Vector2(0.34, 0.96)], [Vector2(0.34, 0.06), Vector2(0.72, 0.3)], [Vector2(0.34, 0.36), Vector2(0.72, 0.6)]],
	[[Vector2(0.32, 0.04), Vector2(0.32, 0.96)], [Vector2(0.32, 0.06), Vector2(0.7, 0.26), Vector2(0.32, 0.48), Vector2(0.72, 0.96)]],
	[[Vector2(0.68, 0.1), Vector2(0.32, 0.5), Vector2(0.68, 0.9)], [Vector2(0.32, 0.2), Vector2(0.32, 0.8)]],
	[[Vector2(0.24, 0.12), Vector2(0.76, 0.88)], [Vector2(0.76, 0.12), Vector2(0.24, 0.88)], [Vector2(0.38, 0.5), Vector2(0.62, 0.5)]],
	[[Vector2(0.36, 0.96), Vector2(0.36, 0.04), Vector2(0.7, 0.24), Vector2(0.36, 0.44)]],
	[[Vector2(0.28, 0.04), Vector2(0.28, 0.96)], [Vector2(0.72, 0.04), Vector2(0.72, 0.96)], [Vector2(0.28, 0.34), Vector2(0.72, 0.62)]],
	[[Vector2(0.5, 0.04), Vector2(0.5, 0.96)], [Vector2(0.28, 0.34), Vector2(0.72, 0.62)]],
	[[Vector2(0.5, 0.18), Vector2(0.5, 0.96)], [Vector2(0.34, 0.04), Vector2(0.5, 0.18), Vector2(0.66, 0.04)]],
	[[Vector2(0.46, 0.08), Vector2(0.24, 0.34), Vector2(0.46, 0.6)], [Vector2(0.54, 0.4), Vector2(0.76, 0.66), Vector2(0.54, 0.92)]],
	[[Vector2(0.5, 0.04), Vector2(0.5, 0.96)], [Vector2(0.5, 0.04), Vector2(0.72, 0.22)], [Vector2(0.5, 0.96), Vector2(0.28, 0.78)]],
	[[Vector2(0.66, 0.04), Vector2(0.34, 0.24), Vector2(0.34, 0.76), Vector2(0.66, 0.96)], [Vector2(0.34, 0.24), Vector2(0.66, 0.44)], [Vector2(0.34, 0.76), Vector2(0.66, 0.56)]],
	[[Vector2(0.5, 0.26), Vector2(0.5, 0.96)], [Vector2(0.5, 0.46), Vector2(0.24, 0.06)], [Vector2(0.5, 0.46), Vector2(0.76, 0.06)]],
	[[Vector2(0.7, 0.04), Vector2(0.32, 0.38), Vector2(0.68, 0.62), Vector2(0.3, 0.96)]],
]

@export var rune := 0:
	set(v):
		rune = clampi(v, -1, 15)
		queue_redraw()
## Lit runes glow; unlit ones are carved grey (empty slots, idle keys).
@export var lit := true:
	set(v):
		lit = v
		queue_redraw()
@export var clickable := false
@export var stroke_width := 3.0
@export var show_name := false

var _hover := false
var _t := 0.0
var _pulse := 0.0


func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(48, 64)
	mouse_filter = Control.MOUSE_FILTER_STOP if clickable else Control.MOUSE_FILTER_IGNORE
	if clickable:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void:
			_hover = true
			UiContext.sound("ui_hover")
			queue_redraw())
		mouse_exited.connect(func() -> void:
			_hover = false
			queue_redraw())


func _process(delta: float) -> void:
	_t += delta
	_pulse = maxf(0.0, _pulse - delta * 2.5)
	if lit or _pulse > 0.0 or _hover:
		queue_redraw()


func flash() -> void:
	_pulse = 1.0


func _gui_input(event: InputEvent) -> void:
	if not clickable:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		flash()
		UiContext.sound("rune")
		pressed.emit(rune)
		accept_event()


static func key_to_rune(keycode: int) -> int:
	return KEYS.find(keycode as Key)


static func code_text(runes: PackedInt32Array) -> String:
	var parts := PackedStringArray()
	for r in runes:
		parts.append(NAMES[r] if r >= 0 and r < 16 else "?")
	return " · ".join(parts)


func _draw() -> void:
	var name_h := 16.0 if show_name else 0.0
	var box := Rect2(Vector2.ZERO, size - Vector2(0, name_h))
	# Keep the rune's 3:4 proportions centred in the box.
	var h := minf(box.size.y, box.size.x * 1.35) * 0.86
	var w := h * 0.75
	var origin := box.position + (box.size - Vector2(w, h)) * 0.5
	if _hover:
		draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color(1, 0.6, 0.2, 0.08))
		draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), UiTheme.ACCENT_DIM, false, 1.0)
	if rune < 0:
		# Empty slot: a carved underline.
		draw_line(origin + Vector2(0, h), origin + Vector2(w, h), UiTheme.BORDER, 2.0)
		return
	var glow := 0.75 + 0.25 * sin(_t * 2.3 + rune * 1.7) + _pulse * 0.8
	var core := UiTheme.ACCENT_HOT.lerp(Color(1, 0.95, 0.85), clampf(_pulse, 0, 1)) if lit or _hover else Color(0.45, 0.4, 0.36)
	var width := stroke_width * maxf(1.0, h / 64.0)
	for stroke: Array in STROKES[rune]:
		var pts := PackedVector2Array()
		for p: Vector2 in stroke:
			pts.append(origin + p * Vector2(w, h))
		if lit or _hover:
			draw_polyline(pts, Color(1.0, 0.45, 0.1, 0.07 * glow), width * 5.0, true)
			draw_polyline(pts, Color(1.0, 0.5, 0.15, 0.16 * glow), width * 2.6, true)
		draw_polyline(pts, core, width, true)
	if show_name:
		var font := UiTheme.MONO
		var label := NAMES[rune].to_upper()
		var fs := 10
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var key := OS.get_keycode_string(KEYS[rune])
		draw_string(font, Vector2((size.x - tw) * 0.5, size.y - 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_DIM if not _hover else UiTheme.ACCENT)
		draw_string(font, Vector2(5, 13), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UiTheme.TEXT_FAINT)
