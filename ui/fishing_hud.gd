class_name FishingHud
extends CanvasLayer
## The reel-in display while a fish is on: a curved tension gauge over the
## crosshair (green slack zone, amber working zone, red snapping zone), the
## line left to reel in, and a short hint. Also flashes "Bite!".

var _root: Control
var _gauge: Gauge
var _hint: Label
var _flash: Label
var _flash_t := 0.0


func _ready() -> void:
	layer = 6
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_gauge = Gauge.new()
	_gauge.anchor_left = 0.5
	_gauge.anchor_right = 0.5
	_gauge.anchor_top = 0.5
	_gauge.anchor_bottom = 0.5
	_gauge.offset_left = -170
	_gauge.offset_right = 170
	_gauge.offset_top = 70
	_gauge.offset_bottom = 190
	_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge.visible = false
	_root.add_child(_gauge)
	_hint = UiTheme.label("", 15, ItemStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.anchor_top = 0.5
	_hint.anchor_bottom = 0.5
	_hint.offset_left = -260
	_hint.offset_right = 260
	_hint.offset_top = 196
	_hint.offset_bottom = 222
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.visible = false
	_root.add_child(_hint)
	_flash = UiTheme.label("", 30, ItemStyle.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_flash.add_theme_font_override("font", ItemStyle.title_font(700))
	_flash.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_flash.add_theme_constant_override("outline_size", 8)
	_flash.anchor_left = 0.5
	_flash.anchor_right = 0.5
	_flash.anchor_top = 0.5
	_flash.anchor_bottom = 0.5
	_flash.offset_left = -300
	_flash.offset_right = 300
	_flash.offset_top = -120
	_flash.offset_bottom = -80
	_flash.visible = false
	_root.add_child(_flash)


func flash(text: String, seconds: float) -> void:
	_flash.text = text
	_flash.visible = true
	_flash_t = seconds


func show_fight(is_fish: bool) -> void:
	_gauge.visible = true
	_hint.visible = true
	_hint.text = "Hold [Right-click] to reel  ·  ease off when the line strains" if is_fish else "Something heavy... hold [Right-click] to reel"


func hide_fight() -> void:
	_gauge.visible = false
	_hint.visible = false


func update_fight(f: FishingDB.ReelFight, reeling: bool) -> void:
	_gauge.tension = f.tension / f.strength
	_gauge.distance = f.distance
	_gauge.surging = f.surging > 0.0
	_gauge.reeling = reeling
	_gauge.queue_redraw()


func _process(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t -= delta
		_flash.modulate.a = clampf(_flash_t * 3.0, 0.0, 1.0)
		if _flash_t <= 0.0:
			_flash.visible = false


## Arc gauge: tension needle over coloured zones, line-left bar beneath.
class Gauge:
	extends Control
	var tension := 0.0
	var distance := 1.0
	var surging := false
	var reeling := false

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y * 0.95)
		var r := size.x * 0.42
		var a0 := PI * 1.15
		var a1 := PI * 1.85
		# Zones.
		var zones := [[0.0, 0.08, Color(0.45, 0.6, 0.9, 0.85)], [0.08, 0.72, Color(0.45, 0.8, 0.4, 0.85)],
			[0.72, 0.9, Color(0.95, 0.7, 0.25, 0.9)], [0.9, 1.0, Color(0.95, 0.25, 0.2, 0.95)]]
		draw_arc(c, r, a0, a1, 48, Color(0, 0, 0, 0.55), 16.0, true)
		for z: Array in zones:
			draw_arc(c, r, lerpf(a0, a1, float(z[0])), lerpf(a0, a1, float(z[1])), 24, z[2], 10.0, true)
		# Needle.
		var a := lerpf(a0, a1, clampf(tension, 0.0, 1.0))
		var tip := c + Vector2(cos(a), sin(a)) * (r + 12.0)
		draw_line(c + Vector2(cos(a), sin(a)) * (r - 18.0), tip, Color(1, 1, 1, 0.95), 3.0, true)
		draw_circle(tip, 4.0, Color(1, 0.95, 0.85))
		var font := ItemStyle.title_font(700)
		var label := "TENSION" if not surging else "IT'S RUNNING!"
		draw_string(font, Vector2(0, c.y - r - 22.0), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, Color(1, 0.85, 0.5) if surging else Color(0.9, 0.86, 0.79))
		# Line left to reel in.
		var bar := Rect2(Vector2(size.x * 0.18, c.y - 6.0), Vector2(size.x * 0.64, 7.0))
		draw_rect(bar, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * (1.0 - distance), bar.size.y)), Color(0.85, 0.75, 0.5, 0.95) if reeling else Color(0.6, 0.55, 0.45, 0.9))
		draw_string(font, Vector2(0, c.y - 12.0), "%d%%" % int((1.0 - distance) * 100.0), HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, Color(0.9, 0.86, 0.79, 0.9))
