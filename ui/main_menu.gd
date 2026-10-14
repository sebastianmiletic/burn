class_name MainMenu
extends Control
## Title screen: burning logo over a drifting ember field, the main actions on
## the left, and a side panel for save slots, multiplayer and credits.

const VERSION := "v1.0 · built with Godot 4.7"
const TAGLINES := [
	"The world is ash. Something beneath it still burns.",
	"Dig deep enough and the earth grows warm.",
	"Three seals. One gate. No way back.",
]

var _bg: EmberBackground
var _title: BurningTitle
var _buttons: VBoxContainer
var _side: TermFrame
var _side_box: VBoxContainer
var _settings: SettingsMenu
var _first_button: Button


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg = EmberBackground.new()
	add_child(_bg)

	var grad := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.82))
	g.set_color(1, Color(0, 0, 0, 0.0))
	grad.gradient = g
	grad.fill_to = Vector2(0.75, 0.0)
	var tex_rect := TextureRect.new()
	tex_rect.texture = grad
	tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tex_rect)

	var left := VBoxContainer.new()
	left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left.offset_left = 80
	left.offset_right = 720
	left.offset_top = 70
	left.offset_bottom = -60
	left.add_theme_constant_override("separation", 4)
	add_child(left)

	_title = BurningTitle.new()
	_title.custom_minimum_size = Vector2(560, 190)
	_title.flames = 0.9
	left.add_child(_title)
	var tag := UiTheme.title(TAGLINES[randi() % TAGLINES.size()], 15, UiTheme.TEXT_DIM, 500)
	left.add_child(tag)
	left.add_child(UiTheme.spacer(36))

	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 2)
	left.add_child(_buttons)
	if bool(UiContext.game_call("has_save", [], false)):
		_add_main_button("Continue", _on_continue)
	_add_main_button("Solo", _show_solo)
	_add_main_button("Multiplayer", _show_multiplayer)
	_add_main_button("Settings", _show_settings)
	_add_main_button("Credits", _show_credits)
	_add_main_button("Quit", func() -> void: get_tree().quit())

	_side = TermFrame.new()
	_side.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_side.anchor_left = 0.5
	_side.anchor_right = 0.5
	_side.offset_left = 120
	_side.offset_right = 640
	_side.anchor_top = 0.5
	_side.anchor_bottom = 0.5
	_side.offset_top = -170
	_side.offset_bottom = 230
	_side.visible = false
	add_child(_side)
	_side_box = VBoxContainer.new()
	_side.add_child(_side_box)

	var ver := UiTheme.label(VERSION, UiTheme.SIZE_SMALL, UiTheme.TEXT_FAINT, HORIZONTAL_ALIGNMENT_RIGHT)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_left = -420
	ver.offset_right = -24
	ver.offset_top = -34
	ver.offset_bottom = -14
	add_child(ver)
	var who := UiTheme.label("", UiTheme.SIZE_SMALL, UiTheme.TEXT_FAINT)
	who.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	who.offset_left = 82
	who.offset_right = 600
	who.offset_top = -34
	who.offset_bottom = -14
	who.text = "wanderer  %s" % str(UiContext.setting("gameplay", "player_name"))
	add_child(who)

	_first_button.grab_focus.call_deferred()
	UiContext.call_on(get_node_or_null("/root/Audio"), "set_music", ["menu"])


func _add_main_button(text: String, cb: Callable) -> void:
	var b := UiTheme.button(text.to_upper(), cb, 20)
	b.add_theme_font_override("font", UiTheme.title_font(600))
	b.custom_minimum_size = Vector2(320, 46)
	_buttons.add_child(b)
	if _first_button == null:
		_first_button = b


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _side.visible:
		_close_side()
		get_viewport().set_input_as_handled()


func _open_side(title: String) -> void:
	for c in _side_box.get_children():
		c.queue_free()
	_side.title = title
	_side.visible = true
	UiContext.sound("ui_open")


func _close_side() -> void:
	_side.visible = false
	UiContext.sound("ui_back")
	_first_button.grab_focus()


# --- Actions ---------------------------------------------------------------------

func _on_continue() -> void:
	if UiContext.game_has("continue_game"):
		UiContext.game_call("continue_game")
		return
	var slot: int = UiContext.game_call("last_slot", [], -1)
	if slot < 0:
		for s: Dictionary in _slots():
			if s.get("exists", false):
				slot = int(s["slot"])
				break
	if slot >= 0:
		UiContext.game_call("start_solo", [slot, false])


func _slots() -> Array:
	var slots: Variant = UiContext.game_call("save_slots", [], null)
	if slots is Array:
		return slots
	return [{"slot": 0, "exists": false}, {"slot": 1, "exists": false}, {"slot": 2, "exists": false}]


func _show_solo() -> void:
	_open_side("JOURNEYS")
	_side_box.add_child(UiTheme.label("Choose a save slot.", UiTheme.SIZE_BODY, UiTheme.TEXT_DIM))
	_side_box.add_child(UiTheme.spacer(6))
	var first: Button = null
	for s: Dictionary in _slots():
		var slot := int(s.get("slot", 0))
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		var head := HBoxContainer.new()
		var name_l := UiTheme.label("SLOT %d" % (slot + 1), UiTheme.SIZE_SMALL, UiTheme.ACCENT_DIM)
		name_l.custom_minimum_size.x = 70
		head.add_child(name_l)
		if s.get("exists", false):
			var rank := int(s.get("rank", 0))
			var title := str(ItemDB.RANK_TITLES[clampi(rank, 0, ItemDB.RANK_TITLES.size() - 1)])
			head.add_child(UiTheme.label("%s  ·  %s" % [s.get("name", "Wanderer"), title], UiTheme.SIZE_BODY, UiTheme.TEXT))
			row.add_child(head)
			row.add_child(UiTheme.label("        %s  ·  %s" % [s.get("location", "Unknown"), UiTheme.format_time(float(s.get("play_time", 0.0)))],
					UiTheme.SIZE_SMALL, UiTheme.TEXT_DIM))
			var acts := HBoxContainer.new()
			var cont := UiTheme.button("Continue", func() -> void: UiContext.game_call("start_solo", [slot, false]))
			acts.add_child(cont)
			var fresh := UiTheme.button("Begin anew", func() -> void: _confirm_new(slot))
			acts.add_child(fresh)
			row.add_child(acts)
			if first == null:
				first = cont
		else:
			head.add_child(UiTheme.label("— empty —", UiTheme.SIZE_BODY, UiTheme.TEXT_FAINT))
			row.add_child(head)
			var start := UiTheme.button("Begin a new journey", func() -> void: UiContext.game_call("start_solo", [slot, true]))
			row.add_child(start)
			if first == null:
				first = start
		_side_box.add_child(row)
		_side_box.add_child(UiTheme.hsep())
	if first != null:
		first.grab_focus()


func _confirm_new(slot: int) -> void:
	_open_side("BEGIN ANEW")
	var msg := UiTheme.label("The journey in slot %d will be lost to the ash.\nThis cannot be undone." % (slot + 1), UiTheme.SIZE_BODY, UiTheme.TEXT)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD
	_side_box.add_child(msg)
	_side_box.add_child(UiTheme.spacer(10))
	var yes := UiTheme.button("Burn it and begin", func() -> void: UiContext.game_call("start_solo", [slot, true]))
	yes.add_theme_color_override("font_color", UiTheme.DANGER)
	_side_box.add_child(yes)
	_side_box.add_child(UiTheme.button("Keep it", _show_solo))
	yes.grab_focus()


func _show_multiplayer() -> void:
	_open_side("WARBAND")
	var info := UiTheme.label("Play together over the same network.\nThe host shares four runes; companions carve them to join.", UiTheme.SIZE_BODY, UiTheme.TEXT_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_side_box.add_child(info)
	_side_box.add_child(UiTheme.spacer(8))
	var runes := HBoxContainer.new()
	runes.alignment = BoxContainer.ALIGNMENT_CENTER
	for r in [0, 8, 14, 15]:
		var g := RuneGlyph.new()
		g.rune = r
		g.custom_minimum_size = Vector2(40, 54)
		runes.add_child(g)
	_side_box.add_child(runes)
	_side_box.add_child(UiTheme.spacer(8))
	var host := UiTheme.button("Host a party", func() -> void: UiContext.game_call("open_lobby_host"), 16)
	_side_box.add_child(host)
	_side_box.add_child(UiTheme.button("Join with runes", func() -> void: UiContext.game_call("open_lobby_join"), 16))
	host.grab_focus()


func _show_settings() -> void:
	if _settings != null:
		return
	_settings = SettingsMenu.new()
	add_child(_settings)
	_settings.closed.connect(func() -> void:
		_settings = null
		_first_button.grab_focus())


func _show_credits() -> void:
	_open_side("CREDITS")
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.custom_minimum_size = Vector2(460, 0)
	text.add_theme_font_size_override("normal_font_size", 13)
	text.add_theme_color_override("default_color", UiTheme.TEXT_DIM)
	text.text = VictoryScreen.credits_bbcode()
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(470, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(text)
	_side_box.add_child(scroll)
	var back := UiTheme.button("Back", _close_side)
	_side_box.add_child(back)
	back.grab_focus()
