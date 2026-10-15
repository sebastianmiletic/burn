class_name DeathScreen
extends Control
## "YOU BURNED OUT": the view sinks into red ash, the cause is written below,
## then you may return at the last shrine.
## In a party with shrine respawns off the player is *downed* instead
## (player.downed, player.bleed_left): the screen stays light so you can see
## companions coming, says a teammate can revive you and counts the bleed-out
## down; there is no shrine button (you rise on your own after bleed-out).

const LINES := [
	"The ash takes everyone eventually. Not yet.",
	"Embers cool. Embers rekindle.",
	"The shrine remembers your warmth.",
]

var is_open := false
var _t := 0.0
var _bg: ColorRect
var _ash: EmberBackground
var _title: Label
var _cause: Label
var _line: Label
var _respawn: Button
var _menu: Button
var _armed := false
var _downed := false
var _bleed: BleedBar


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_bg = ColorRect.new()
	_bg.color = Color(0.12, 0.01, 0.0, 0.0)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_ash = EmberBackground.new()
	_ash.intensity = 0.0
	_ash.modulate.a = 0.0
	add_child(_ash)
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -400
	box.offset_right = 400
	box.offset_top = -140
	box.offset_bottom = 200
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(box)
	_title = UiTheme.title("YOU BURNED OUT", 64, Color(0.95, 0.3, 0.18), 900)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_cause = UiTheme.label("", UiTheme.SIZE_LARGE, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_cause)
	_line = UiTheme.title("", 15, UiTheme.TEXT_DIM, 500)
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_line)
	box.add_child(UiTheme.spacer(18))
	_bleed = BleedBar.new()
	_bleed.visible = false
	box.add_child(_bleed)
	box.add_child(UiTheme.spacer(12))
	var acts := HBoxContainer.new()
	acts.alignment = BoxContainer.ALIGNMENT_CENTER
	_respawn = UiTheme.button("RISE AT THE LAST SHRINE", _on_respawn, 18)
	_respawn.add_theme_font_override("font", UiTheme.title_font(700))
	acts.add_child(_respawn)
	_menu = UiTheme.button("Quit to title", func() -> void: UiContext.game_call("quit_to_menu"), 14)
	acts.add_child(_menu)
	box.add_child(acts)
	UiContext.on("player_died", show_death)
	UiContext.on("player_respawned", hide_death)


func show_death(cause: String) -> void:
	is_open = true
	visible = true
	_t = 0.0
	_cause.text = cause if cause != "" else "Consumed by the dark."
	_line.text = LINES[randi() % LINES.size()]
	_respawn.disabled = true
	_armed = false
	_set_downed(false)
	UiContext.set_ui_open(true)


func hide_death() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	UiContext.set_ui_open(false)


func _on_respawn() -> void:
	_respawn.disabled = true
	UiContext.call_on(UiContext.player(), "request_respawn")


func _set_downed(on: bool) -> void:
	_downed = on
	_title.text = "DOWNED" if on else "YOU BURNED OUT"
	_respawn.visible = not on
	_bleed.visible = on
	if on:
		_line.text = "A companion can revive you — hold on."
	elif _line.text.begins_with("A companion"):
		_line.text = LINES[randi() % LINES.size()]


func _process(delta: float) -> void:
	if not is_open:
		return
	_t += delta
	var player := UiContext.player()
	var downed: bool = player != null and player.get("downed") == true
	if downed != _downed:
		_set_downed(downed)
	if downed:
		var left: Variant = player.get("bleed_left")
		_bleed.left = float(left) if left != null else 0.0
	# Downed: keep the world visible behind a lighter veil.
	_bg.color.a = minf(0.32 if downed else 0.78, _t * 0.6)
	_ash.modulate.a = clampf(_t * 0.5, 0.0, 0.25 if downed else 0.7)
	_ash.intensity = clampf(_t * 0.4, 0.0, 0.8)
	_bleed.modulate.a = clampf((_t - 1.2) / 0.8, 0.0, 1.0)
	_title.modulate.a = clampf((_t - 0.4) / 1.2, 0.0, 1.0)
	var spread := 1.0 - clampf((_t - 0.4) / 2.0, 0.0, 1.0)
	_title.scale = Vector2.ONE * (1.0 + spread * 0.06)
	_title.pivot_offset = _title.size * 0.5
	_cause.modulate.a = clampf((_t - 1.2) / 0.8, 0.0, 1.0)
	_line.modulate.a = clampf((_t - 1.8) / 0.8, 0.0, 1.0)
	var buttons_a := clampf((_t - 2.2) / 0.6, 0.0, 1.0)
	_respawn.modulate.a = buttons_a
	_menu.modulate.a = buttons_a
	if _t > 2.2 and not _armed:
		_armed = true
		_respawn.disabled = false
		_respawn.grab_focus()


## "Bleeding out" countdown under the downed title.
class BleedBar:
	extends Control

	const TOTAL := 90.0
	var left := TOTAL:
		set(v):
			left = v
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(460, 46)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := 420.0
		var x := (size.x - w) * 0.5
		var f := clampf(left / TOTAL, 0.0, 1.0)
		var text := "Bleeding out   %d:%02d" % [int(left) / 60, int(left) % 60]
		var font := UiTheme.MONO_BOLD
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		draw_string(font, Vector2((size.x - ts.x) * 0.5, 16), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				UiTheme.TEXT if left > 15.0 else UiTheme.DANGER)
		var bar := Rect2(x, 28, w, 6)
		draw_rect(bar.grow(1), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(w * f, bar.size.y)), Color(0.85, 0.2, 0.14))
		draw_rect(Rect2(bar.position, Vector2(w * f, 2)), Color(1, 0.45, 0.3))
