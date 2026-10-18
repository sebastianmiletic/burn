class_name Crosshair
extends Control
## Screen centre: a small reticle, the mining progress ring around it and the
## interaction prompt below it.

var _mining := -1.0
var _prompt := ""
var _prompt_alpha := 0.0
var _hit_marker := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiContext.on("mining_progress", func(f: float) -> void:
		_mining = f
		queue_redraw())
	UiContext.on("interact_prompt", func(t: String) -> void:
		if t != "":
			_prompt = t
		_prompt_alpha = 1.0 if t != "" else _prompt_alpha
		set_meta("prompt_on", t != ""))
	UiContext.on("damage_number", func(_p: Vector3, _a: int, _c: bool, kind: String) -> void:
		if kind == "hit" or kind == "fire":
			_hit_marker = 1.0)


func _process(delta: float) -> void:
	if not get_meta("prompt_on", false):
		_prompt_alpha = maxf(0.0, _prompt_alpha - delta * 5.0)
	_hit_marker = maxf(0.0, _hit_marker - delta * 5.0)
	queue_redraw()


func _draw() -> void:
	var c := (size * 0.5).round()
	# Settings > Gameplay: reticle style and colour; Accessibility: high contrast.
	var style := int(UiContext.setting("hud", "crosshair", 0))
	var colors: Array = UiContext.settings_const("CROSSHAIR_COLORS")
	var ci := int(UiContext.setting("hud", "crosshair_color", 0))
	var col: Color = colors[ci] if ci >= 0 and ci < colors.size() else Color(1, 0.9, 0.75)
	col.a = 0.85
	var high := bool(UiContext.setting("accessibility", "high_contrast", false))
	var shade := Color(0, 0, 0, 0.95 if high else 0.6)
	var w := 2.0 if high else 1.0
	var gap := 4.0
	var len := 5.0
	if style == 0 or style == 3:
		for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_line(c + d * gap, c + d * (gap + len), shade, w + 2.0)
			draw_line(c + d * gap, c + d * (gap + len), col, w)
	if style == 2:
		draw_arc(c, 6.0, 0, TAU, 32, shade, w + 2.0, true)
		draw_arc(c, 6.0, 0, TAU, 32, col, w, true)
	if style != 4:
		var dot := 2.0 if style == 0 else 3.0
		if style != 0:
			draw_rect(Rect2(c - Vector2(dot, dot) * 0.5 - Vector2(1, 1), Vector2(dot + 2, dot + 2)), shade)
		draw_rect(Rect2(c - Vector2(dot, dot) * 0.5, Vector2(dot, dot)), col)
	if _hit_marker > 0.0:
		var hc := Color(1, 0.6, 0.3, _hit_marker)
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d * 7.0, c + d * 12.0, hc, 2.0)
	if _mining >= 0.0:
		draw_arc(c, 16.0, 0, TAU, 40, Color(0, 0, 0, 0.55), 4.0, true)
		draw_arc(c, 16.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(_mining, 0.0, 1.0), 40, UiTheme.ACCENT_HOT, 2.0, true)
	if _prompt_alpha > 0.0 and _prompt != "":
		var font := UiTheme.MONO_BOLD
		var fs := 14
		var ts := font.get_string_size(_prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var box := Rect2(c + Vector2(-ts.x * 0.5 - 12, 34), Vector2(ts.x + 24, 26))
		draw_rect(box, Color(0.02, 0.016, 0.014, 0.8 * _prompt_alpha))
		draw_line(box.position, box.position + Vector2(0, box.size.y), Color(UiTheme.ACCENT, _prompt_alpha), 2.0)
		draw_string(font, box.position + Vector2(12, 18), _prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiTheme.ACCENT_HOT, _prompt_alpha))
