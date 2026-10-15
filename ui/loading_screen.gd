class_name LoadingScreen
extends CanvasLayer
## Shown while a world is generated and the first chunks stream in: a short
## film (LoadingCinematic: the Leviathan in a night storm) in its own
## SubViewport/World3D, with the title, progress and a tip laid over it.
##
## Transitions: it opens on a still of the previous screen and dissolves from
## it (no hard cut from the menu); the film fades in once its first frames
## are rendered (shaders warm); when loading completes (progress 1) it leaves
## a still of its last frame that dissolves into the game while the 3D scene
## is freed at once. Headless runs get the overlay only (no 3D).

const TIPS := [
	"Shrines remember you. Rest at one and the ash will return you there.",
	"Stone pickaxes cannot bite gold. Bring iron ore to a blacksmith.",
	"Ember crystals glow in the deep places, far below the roots of the world.",
	"Heavy attacks are written on the ground first. Read them, then roll.",
	"Torches are cheap. The dark is not.",
	"The Gates of Hades lie beneath the Cinder Crater. Three seals open them.",
	"Villagers trade gold for ore. Merchants trade potions for gold.",
	"Dodge rolls make you untouchable for a heartbeat. Use it.",
	"The Mountain King hates the cold less than he hates guests.",
	"Lava does not care how brave you are.",
	"The Leviathan circles the Drowned Spire. It surfaces when the storm is loudest.",
	"In a warband, a fallen companion can be raised. Stand close and hold E.",
]
## Film resolution relative to the window (upscaled with FSR); the overlay stays native.
const FILM_SCALE := 0.6
const FILM_FADE_IN := 1.6
const OUTRO := 1.1

var _root: Control
var _film: SubViewport
var _film_rect: TextureRect
var _cinematic: LoadingCinematic
var _veil: ColorRect        # black over the film until it is ready
var _rain_mat: ShaderMaterial
var _rain: ColorRect
var _from: TextureRect      # still of the previous screen, dissolving away
var _title: EmberTitle
var _caption: Label
var _status: Label
var _percent: Label
var _tip: Label
var _bar: ProgressLine
var _tip_timer := 0.0
var _progress := 0.0
var _shown := 0.0
var _time := 0.0
var _film_alpha := 0.0
var _from_alpha := 1.0
var _done := false


func _ready() -> void:
	layer = 80
	_root = Control.new()
	_root.theme = UiTheme.theme()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var black := ColorRect.new()
	black.color = Color(0.008, 0.009, 0.012)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(black)
	var headless := DisplayServer.get_name() == "headless"
	if not headless:
		_build_film()
	# Cinematic grade: soft top/bottom shading for the type, and the rain.
	_root.add_child(_shade(true))
	_root.add_child(_shade(false))
	if not headless:
		_rain_mat = ShaderMaterial.new()
		_rain_mat.shader = preload("res://ui/shaders/rain_overlay.gdshader")
		_rain = ColorRect.new()
		_rain.material = _rain_mat
		_rain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_root.add_child(_rain)
	_build_overlay()
	if not headless:
		_capture_previous_screen()
	_next_tip()


func _build_film() -> void:
	var win := get_viewport().get_visible_rect().size
	_film = SubViewport.new()
	_film.own_world_3d = true
	_film.size = Vector2i(maxi(320, int(win.x)), maxi(180, int(win.y)))
	_film.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	_film.scaling_3d_scale = clampf(FILM_SCALE * 1600.0 / maxf(win.x, 1.0) * 1.6, 0.4, 1.0) if win.x > 1600.0 else FILM_SCALE + 0.15
	_film.msaa_3d = Viewport.MSAA_DISABLED
	_film.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_film.positional_shadow_atlas_size = 0
	_film.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_film.audio_listener_enable_3d = false
	add_child(_film)
	_cinematic = LoadingCinematic.new()
	_film.add_child(_cinematic)
	_film_rect = TextureRect.new()
	_film_rect.texture = _film.get_texture()
	_film_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_film_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_film_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_film_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_film_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_film_rect)
	_veil = ColorRect.new()
	_veil.color = Color(0.008, 0.009, 0.012, 1.0)
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_veil)
	get_viewport().size_changed.connect(_on_resized)


func _on_resized() -> void:
	if _film != null and is_instance_valid(_film):
		var win := get_viewport().get_visible_rect().size
		_film.size = Vector2i(maxi(320, int(win.x)), maxi(180, int(win.y)))


## A vertical gradient band to seat the type (top or bottom).
func _shade(top: bool) -> Control:
	var tex := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.82))
	g.set_color(1, Color(0, 0, 0, 0.0))
	tex.gradient = g
	tex.fill_from = Vector2(0, 0) if top else Vector2(0, 1)
	tex.fill_to = Vector2(0, 1) if top else Vector2(0, 0)
	tex.width = 4
	tex.height = 128
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_left = 0.0
	r.anchor_right = 1.0
	r.anchor_top = 0.0 if top else 0.62
	r.anchor_bottom = 0.22 if top else 1.0
	return r


func _build_overlay() -> void:
	_title = EmberTitle.new()
	_title.anchor_left = 0.0
	_title.anchor_right = 0.0
	_title.anchor_top = 1.0
	_title.anchor_bottom = 1.0
	_title.offset_left = 58
	_title.offset_right = 58 + 520
	_title.offset_top = -210
	_title.offset_bottom = -104
	_root.add_child(_title)

	_caption = UiTheme.title("THE GREY SEA  ·  WHERE THE LEVIATHAN WAKES", 13, Color(0.72, 0.76, 0.82), 600)
	_caption.add_theme_font_override("font", UiTheme.title_font_spaced(600, 3))
	_caption.anchor_top = 1.0
	_caption.anchor_bottom = 1.0
	_caption.offset_left = 64
	_caption.offset_right = 900
	_caption.offset_top = -98
	_caption.offset_bottom = -78
	_root.add_child(_caption)

	var row := HBoxContainer.new()
	row.anchor_left = 0.0
	row.anchor_right = 1.0
	row.anchor_top = 1.0
	row.anchor_bottom = 1.0
	row.offset_left = 64
	row.offset_right = -64
	row.offset_top = -58
	row.offset_bottom = -36
	_status = UiTheme.label("Kindling", 13, UiTheme.ACCENT)
	_status.add_theme_font_override("font", UiTheme.title_font_spaced(700, 2))
	row.add_child(_status)
	_tip = UiTheme.label("", 12, Color(0.7, 0.72, 0.76), HORIZONTAL_ALIGNMENT_CENTER)
	_tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tip.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_tip)
	_percent = UiTheme.label("0%", 13, UiTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_percent.custom_minimum_size.x = 60
	row.add_child(_percent)
	_root.add_child(row)

	_bar = ProgressLine.new()
	_bar.anchor_left = 0.0
	_bar.anchor_right = 1.0
	_bar.anchor_top = 1.0
	_bar.anchor_bottom = 1.0
	_bar.offset_left = 64
	_bar.offset_right = -64
	_bar.offset_top = -28
	_bar.offset_bottom = -20
	_root.add_child(_bar)


## The last frame of whatever was on screen (the menu), to dissolve from.
func _capture_previous_screen() -> void:
	var tex := get_viewport().get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		return
	_from = TextureRect.new()
	_from.texture = ImageTexture.create_from_image(img)
	_from.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_from.stretch_mode = TextureRect.STRETCH_SCALE
	_from.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_from.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_from)


func set_progress(f: float, text: String) -> void:
	_progress = clampf(f, 0.0, 1.0)
	if text != "":
		_status.text = text.to_upper()
	if _progress >= 1.0 and not _done:
		_finish()


func _process(delta: float) -> void:
	_time += delta
	var d := minf(delta, 1.0 / 20.0)
	_shown = move_toward(_shown, _progress, d * 1.2)
	_bar.value = _shown
	_bar.time = _time
	_percent.text = "%d%%" % roundi(_shown * 100.0)
	_tip_timer -= delta
	if _tip_timer <= 0.0:
		_next_tip()
	_tip.modulate.a = clampf(minf(7.0 - _tip_timer, _tip_timer) * 1.5, 0.0, 1.0)
	if _cinematic != null:
		if _cinematic.frames > 4:
			_film_alpha = move_toward(_film_alpha, 1.0, d / FILM_FADE_IN)
		_veil.color.a = 1.0 - smoothstep(0.0, 1.0, _film_alpha)
		_rain_mat.set_shader_parameter(&"time", _time)
		_rain_mat.set_shader_parameter(&"flash", _cinematic.flash * _film_alpha)
		_rain_mat.set_shader_parameter(&"aspect", _root.size.x / maxf(_root.size.y, 1.0))
		_rain_mat.set_shader_parameter(&"intensity", _film_alpha)
		_title.flash = clampf(_cinematic.flash, 0.0, 1.0)
	if _from != null:
		_from_alpha = move_toward(_from_alpha, 0.0, d / 0.7)
		_from.modulate.a = smoothstep(0.0, 1.0, _from_alpha)
		if _from_alpha <= 0.0:
			_from.queue_free()
			_from = null
	_title.time = _time
	_title.modulate.a = clampf(_time / 0.8, 0.0, 1.0)
	_caption.modulate.a = clampf((_time - 0.6) / 1.0, 0.0, 1.0)


func _next_tip() -> void:
	_tip_timer = 7.0
	_tip.text = "“%s”" % TIPS[randi() % TIPS.size()]


## Loading is complete: hand over to the game with a dissolve from our last
## frame, and free the film right away.
func _finish() -> void:
	_done = true
	if not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var img: Image = null
	var tex := get_viewport().get_texture()
	if tex != null:
		img = tex.get_image()
	if _film != null:
		_film.queue_free()
		_film = null
		_cinematic = null
	if img == null or img.is_empty():
		return
	var outro := _Outro.new()
	outro.image = img
	get_tree().root.add_child.call_deferred(outro)


## A still of the loading screen's last frame that dissolves into the game.
class _Outro extends CanvasLayer:
	var image: Image
	var _rect: TextureRect
	var _t := 0.0

	func _ready() -> void:
		layer = 79
		_rect = TextureRect.new()
		_rect.texture = ImageTexture.create_from_image(image)
		_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_rect.stretch_mode = TextureRect.STRETCH_SCALE
		_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_rect)
		image = null

	func _process(delta: float) -> void:
		_t += minf(delta, 1.0 / 20.0)
		var f := clampf(_t / OUTRO, 0.0, 1.0)
		_rect.modulate.a = 1.0 - smoothstep(0.0, 1.0, f)
		# A slow push-in while it dissolves.
		_rect.pivot_offset = _rect.size * 0.5
		_rect.scale = Vector2.ONE * (1.0 + f * 0.04)
		if f >= 1.0:
			queue_free()


## The thin progress rule along the bottom, with a glowing head.
class ProgressLine:
	extends Control

	var value := 0.0:
		set(v):
			value = v
			queue_redraw()
	var time := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var y := size.y * 0.5
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.12), 1.0)
		var x := size.x * clampf(value, 0.0, 1.0)
		draw_line(Vector2(0, y), Vector2(x, y), UiTheme.ACCENT, 2.0)
		var pulse := 0.6 + 0.4 * sin(time * 4.0)
		draw_circle(Vector2(x, y), 5.0, Color(1, 0.62, 0.22, 0.18 * pulse), true, -1.0, true)
		draw_circle(Vector2(x, y), 2.4, UiTheme.ACCENT_HOT, true, -1.0, true)


## "BURN" in spaced Cinzel with a slow ember glow (and a cold rim in lightning).
class EmberTitle:
	extends Control

	var time := 0.0:
		set(v):
			time = v
			queue_redraw()
	var flash := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var f := UiTheme.title_font_spaced(900, 22)
		var fs := 92
		var text := "BURN"
		var base := Vector2(0, size.y - 14)
		var flicker := 0.75 + 0.15 * sin(time * 2.3) + 0.1 * sin(time * 5.1 + 1.3)
		# Glow: wide soft outlines, warm; lightning adds a cold rim.
		for layer: Array in [[34, 0.05], [22, 0.08], [12, 0.12]]:
			var c := Color(1.0, 0.42, 0.12, float(layer[1]) * flicker).lerp(Color(0.6, 0.7, 1.0, float(layer[1])), flash * 0.6)
			draw_string_outline(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(layer[0]), c)
		draw_string_outline(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0.12, 0.04, 0.02, 0.9))
		var fill := Color(1.0, 0.8, 0.52).lerp(Color(0.95, 0.97, 1.0), flash * 0.5)
		draw_string(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fill)
		# A hairline rule under the word.
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_line(Vector2(4, size.y - 2), Vector2(w * 0.55, size.y - 2), Color(1, 0.62, 0.22, 0.6), 1.0)
		draw_circle(Vector2(w * 0.55 + 6, size.y - 2), 2.2, Color(1, 0.7, 0.35, 0.8), true, -1.0, true)
