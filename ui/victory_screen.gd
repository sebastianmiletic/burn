class_name VictoryScreen
extends Control
## Shown on Events.campaign_won: the title burns in a last time, then the
## credits roll. Afterwards the player may keep exploring or leave.

const ROLL_SPEED := 38.0

var is_open := false
var _t := 0.0
var _title: BurningTitle
var _roll: VBoxContainer
var _clip: Control
var _buttons: HBoxContainer


static func credits_bbcode() -> String:
	var a := UiTheme.ACCENT.to_html(false)
	return "\n".join([
		"[color=#%s]BURN[/color]" % a,
		"A tale told in ash.",
		"",
		"[color=#%s]Design, code, art and sound[/color]" % a,
		"Made for this project — every world, creature, sound and line is original.",
		"",
		"[color=#%s]Engine[/color]" % a,
		"Godot Engine 4.7 — MIT licence, © Juan Linietsky, Ariel Manzur and contributors.",
		"",
		"[color=#%s]Fonts[/color]" % a,
		"JetBrains Mono — SIL Open Font License 1.1, © The JetBrains Mono Project Authors.",
		"Cinzel — SIL Open Font License 1.1, © The Cinzel Project Authors.",
		"",
		"[color=#%s]Techniques[/color]" % a,
		"ASCII edge-glyph approach after AcerolaFX ASCII — MIT licence, © Garrett Gunnell.",
		"",
		"[color=#%s]Thanks[/color]" % a,
		"To everyone who carried a torch into the dark.",
	])


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var black := ColorRect.new()
	black.color = Color(0.0, 0.0, 0.0, 0.9)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	add_child(EmberBackground.new())
	_title = BurningTitle.new()
	_title.text = "VICTORY"
	_title.anchor_left = 0.5
	_title.anchor_right = 0.5
	_title.offset_left = -420
	_title.offset_right = 420
	_title.offset_top = 40
	_title.offset_bottom = 230
	_title.progress = 0.0
	add_child(_title)
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.anchor_left = 0.5
	_clip.anchor_right = 0.5
	_clip.anchor_top = 0.0
	_clip.anchor_bottom = 1.0
	_clip.offset_left = -360
	_clip.offset_right = 360
	_clip.offset_top = 250
	_clip.offset_bottom = -90
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)
	_roll = VBoxContainer.new()
	_roll.add_theme_constant_override("separation", 6)
	_roll.custom_minimum_size.x = 720
	_clip.add_child(_roll)
	var intro := UiTheme.title("The Crown of Hades is yours. The underworld bows.", 20, UiTheme.ACCENT_HOT, 600)
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD
	intro.custom_minimum_size.x = 720
	_roll.add_child(intro)
	_roll.add_child(UiTheme.spacer(30))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.custom_minimum_size.x = 720
	text.add_theme_font_size_override("normal_font_size", 15)
	text.add_theme_color_override("default_color", UiTheme.TEXT)
	text.text = "[center]%s[/center]" % credits_bbcode()
	_roll.add_child(text)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_buttons.offset_left = -300
	_buttons.offset_right = 300
	_buttons.offset_top = -70
	_buttons.offset_bottom = -30
	_buttons.add_child(UiTheme.button("Keep exploring", close, 16))
	_buttons.add_child(UiTheme.button("Return to title", func() -> void: UiContext.game_call("quit_to_menu"), 16))
	add_child(_buttons)
	UiContext.on("campaign_won", open)


func open() -> void:
	is_open = true
	visible = true
	_t = 0.0
	_roll.position = Vector2(0, _clip.size.y)
	UiContext.set_ui_open(true)
	UiContext.call_on(get_node_or_null("/root/Audio"), "set_music", ["victory"])


func close() -> void:
	is_open = false
	visible = false
	UiContext.set_ui_open(false)


func _process(delta: float) -> void:
	if not is_open:
		return
	_t += delta
	_title.progress = smoothstep(0.2, 2.8, _t)
	if _t > 2.5:
		_roll.position.y -= ROLL_SPEED * delta
		if _roll.position.y < -_roll.size.y:
			_roll.position.y = _clip.size.y
	_buttons.modulate.a = clampf((_t - 3.0) / 1.0, 0.0, 1.0)
