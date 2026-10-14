class_name MainMenu
extends Control
## Title screen. A live fly-over of the world plays behind everything
## (MenuBackdrop, through the player's render style); the burning BURN
## title, a tagline and the option stack sit centred over a soft dark band.
## Sub-pages (save slots, warband, credits) open in a framed panel in the
## same place; Esc goes back. Settings opens its own overlay.

const VERSION := "v1.0  ·  built with Godot 4.7"
const TAGLINES := [
	"The world is ash. Something beneath it still burns.",
	"Dig deep enough and the earth grows warm.",
	"Three seals. One gate. No way back.",
]
const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"]

static var _capture_started := false

var _stage: MenuStage
var _column: VBoxContainer
var _title: BurningTitle
var _tagline: Label
var _divider: Control
var _stack: VBoxContainer
var _panel: MenuPanel
var _panel_box: VBoxContainer
var _footer: Control
var _hints: Label
var _settings: SettingsMenu
var _first_button: Button
var _return_focus: Control
var _t := 0.0
var _panel_open := false
var _dim := 0.0


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage = MenuStage.new()
	add_child(_stage)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_bottom = -36   # sit a little above the optical centre
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_column = VBoxContainer.new()
	_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_column.add_theme_constant_override("separation", 0)
	center.add_child(_column)

	_title = BurningTitle.new()
	_title.flames = 0.9
	_title.progress = 0.25
	_title.letter_scale = 0.72
	_title.custom_minimum_size = Vector2(680, 200)
	_title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_column.add_child(_title)
	_stage.pool_target = _title
	_tagline = UiTheme.title(TAGLINES[randi() % TAGLINES.size()], 16, UiTheme.TEXT_DIM, 500)
	_tagline.add_theme_font_override("font", UiTheme.title_font_spaced(500, 1))
	_tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tagline.add_theme_color_override("font_outline_color", Color(0.01, 0.006, 0.004, 0.85))
	_tagline.add_theme_constant_override("outline_size", 7)
	_tagline.add_theme_color_override("font_color", UiTheme.TEXT.lerp(UiTheme.TEXT_DIM, 0.4))
	_column.add_child(_tagline)
	_divider = Control.new()
	_divider.custom_minimum_size = Vector2(420, 34)
	_divider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_divider.draw.connect(func() -> void:
		MenuPanel.draw_divider(_divider, Vector2(_divider.size.x * 0.5, _divider.size.y * 0.55), 150.0))
	_column.add_child(_divider)

	_stack = VBoxContainer.new()
	_stack.add_theme_constant_override("separation", 2)
	_stack.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_column.add_child(_stack)
	if bool(UiContext.game_call("has_save", [], false)):
		var cont := _add_main_button("Continue", _on_continue)
		cont.detail = _continue_detail()
		cont.custom_minimum_size.y = 68
	_add_main_button("Solo", _show_solo)
	_add_main_button("Multiplayer", _show_multiplayer)
	_add_main_button("Settings", _show_settings)
	_add_main_button("Credits", _show_credits)
	_add_main_button("Quit", func() -> void: get_tree().quit())
	_wrap_focus(_stack)

	_panel = MenuPanel.new()
	_panel.visible = false
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel.custom_minimum_size = Vector2(620, 0)
	_column.add_child(_panel)
	_panel_box = VBoxContainer.new()
	_panel_box.add_theme_constant_override("separation", 8)
	_panel.add_child(_panel_box)

	_build_footer()
	resized.connect(_layout)
	_layout()
	_first_button.grab_focus.call_deferred()
	_column.modulate.a = 0.0
	UiContext.call_on(get_node_or_null("/root/Audio"), "set_music", ["menu"])
	_maybe_capture()


func _add_main_button(text: String, cb: Callable) -> MenuOption:
	var b := MenuOption.new(text.to_upper(), cb, 22)
	b.custom_minimum_size = Vector2(400, 50)
	b.modulate.a = 0.0
	_stack.add_child(b)
	if _first_button == null:
		_first_button = b
	return b


func _wrap_focus(box: Container) -> void:
	var items: Array[Control] = []
	for c in box.get_children():
		if c is Control and (c as Control).focus_mode != Control.FOCUS_NONE:
			items.append(c)
	if items.size() < 2:
		return
	items[0].focus_neighbor_top = items[0].get_path_to(items[-1])
	items[-1].focus_neighbor_bottom = items[-1].get_path_to(items[0])


func _build_footer() -> void:
	_footer = Control.new()
	_footer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_footer)
	var ver := UiTheme.label(VERSION, UiTheme.SIZE_SMALL, UiTheme.TEXT_FAINT, HORIZONTAL_ALIGNMENT_RIGHT)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_left = -460
	ver.offset_right = -36
	ver.offset_top = -40
	ver.offset_bottom = -20
	_footer.add_child(ver)
	var who := UiTheme.label("", UiTheme.SIZE_SMALL, UiTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	who.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	who.offset_left = -460
	who.offset_right = -36
	who.offset_top = -60
	who.offset_bottom = -40
	who.text = "wanderer  ·  %s" % str(UiContext.setting("gameplay", "player_name"))
	_footer.add_child(who)
	var hints := UiTheme.label("↑ ↓  choose      enter  confirm      esc  back", UiTheme.SIZE_SMALL, UiTheme.TEXT_FAINT, HORIZONTAL_ALIGNMENT_CENTER)
	hints.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hints.offset_left = -300
	hints.offset_right = 300
	hints.offset_top = -40
	hints.offset_bottom = -20
	_footer.add_child(hints)
	_hints = hints


## Title height follows the window so everything fits from small windows up.
func _layout() -> void:
	var h := size.y if size.y > 0.0 else 900.0
	var title_h := clampf(h * 0.21, 110.0, 230.0)
	if _panel_open:
		title_h = clampf(h * 0.15, 90.0, 170.0)
	_title.custom_minimum_size = Vector2(title_h * 3.4, title_h)
	var cut := h < 760.0 and _panel_open
	_tagline.visible = not cut
	_divider.custom_minimum_size.y = 20.0 if cut else 34.0


func _process(delta: float) -> void:
	_t += delta
	_title.progress = minf(1.0, _title.progress + delta * 0.7)
	_column.modulate.a = smoothstep(0.0, 0.6, _t)
	var i := 0
	for b in _stack.get_children():
		(b as Control).modulate.a = smoothstep(0.25 + i * 0.07, 0.75 + i * 0.07, _t)
		i += 1
	UiTheme.fit_scale(_column, size - Vector2(40, 120))
	_hints.visible = size.x >= 1100.0
	_dim = move_toward(_dim, 0.25 if _panel_open else 0.0, delta * 1.5)
	_stage.focus_dim = _dim


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _panel_open:
		_close_panel()
		get_viewport().set_input_as_handled()


# --- Panel ---------------------------------------------------------------------------

func _open_panel(title: String, subtitle := "") -> void:
	if not _panel_open:
		var f := get_viewport().gui_get_focus_owner()
		_return_focus = f if f != null and _stack.is_ancestor_of(f) else _first_button
	for c in _panel_box.get_children():
		_panel_box.remove_child(c)
		c.queue_free()
	_panel.title = title
	_panel.subtitle = subtitle
	_panel_open = true
	_stack.visible = false
	_panel.visible = true
	_panel.modulate.a = 0.0
	create_tween().tween_property(_panel, "modulate:a", 1.0, 0.22)
	_layout()
	UiContext.sound("ui_open")


func _close_panel() -> void:
	_panel_open = false
	_panel.visible = false
	_stack.visible = true
	_layout()
	UiContext.sound("ui_back")
	var f := _return_focus if _return_focus != null and is_instance_valid(_return_focus) else _first_button
	f.grab_focus()


func _panel_button(text: String, cb: Callable, width := 300.0, size_px := 17) -> MenuOption:
	var b := MenuOption.new(text.to_upper(), cb, size_px)
	b.custom_minimum_size = Vector2(width, size_px * 2.4)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b


func _back_button() -> MenuOption:
	var b := _panel_button("Back", _close_panel, 200.0, 15)
	return b


func _text(t: String, color := UiTheme.TEXT_DIM, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := UiTheme.label(t, UiTheme.SIZE_BODY, color, align)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size.x = 520
	return l


# --- Actions ---------------------------------------------------------------------

func _continue_detail() -> String:
	var slot := SaveSystem.most_recent()
	for s: Dictionary in _slots():
		if int(s.get("slot", -1)) == slot and s.get("exists", false):
			var bits := [str(s.get("name", "Wanderer"))]
			if str(s.get("location", "")) != "":
				bits.append(str(s["location"]))
			bits.append(UiTheme.format_time(float(s.get("play_time", 0.0))))
			return "  ·  ".join(bits)
	return ""


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
	_open_panel("JOURNEYS", "choose a hearth to return to, or light a new one")
	var first: Control = null
	var slots := _slots()
	for i in slots.size():
		var s: Dictionary = slots[i]
		var slot := int(s.get("slot", 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var num := UiTheme.title(ROMAN[clampi(slot, 0, ROMAN.size() - 1)], 26, UiTheme.ACCENT_DIM, 700)
		num.custom_minimum_size = Vector2(56, 0)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(num)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(info)
		var acts := VBoxContainer.new()
		acts.add_theme_constant_override("separation", 0)
		acts.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(acts)
		if s.get("exists", false):
			var rank := int(s.get("rank", 0))
			var title := str(ItemDB.RANK_TITLES[clampi(rank, 0, ItemDB.RANK_TITLES.size() - 1)])
			var name_l := UiTheme.title("%s" % s.get("name", "Wanderer"), 18, UiTheme.TEXT, 700)
			info.add_child(name_l)
			info.add_child(UiTheme.label("%s  ·  %s  ·  %s" % [title, s.get("location", "") if str(s.get("location", "")) != "" else "Unknown lands",
					UiTheme.format_time(float(s.get("play_time", 0.0)))], UiTheme.SIZE_SMALL, UiTheme.TEXT_DIM))
			var cont := _panel_button("Continue", func() -> void: UiContext.game_call("start_solo", [slot, false]), 170.0, 15)
			acts.add_child(cont)
			acts.add_child(_panel_button("Begin anew", func() -> void: _confirm_new(slot), 170.0, 13))
			if first == null:
				first = cont
		else:
			info.add_child(UiTheme.title("An unlit hearth", 18, UiTheme.TEXT_FAINT, 500))
			info.add_child(UiTheme.label("empty slot", UiTheme.SIZE_SMALL, UiTheme.TEXT_FAINT))
			var start := _panel_button("Begin", func() -> void: UiContext.game_call("start_solo", [slot, true]), 170.0, 15)
			acts.add_child(start)
			if first == null:
				first = start
		_panel_box.add_child(row)
		if i < slots.size() - 1:
			_panel_box.add_child(_rule())
	_panel_box.add_child(UiTheme.spacer(6))
	_panel_box.add_child(_back_button())
	if first != null:
		first.grab_focus()


func _rule() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 9)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		var y := c.size.y * 0.5
		c.draw_line(Vector2(56, y), Vector2(c.size.x, y), Color(UiTheme.BORDER, 0.45), 1.0))
	return c


func _confirm_new(slot: int) -> void:
	_open_panel("BEGIN ANEW")
	_panel_box.add_child(_text("The journey in hearth %s will be lost to the ash.\nThis cannot be undone." % ROMAN[clampi(slot, 0, ROMAN.size() - 1)], UiTheme.TEXT))
	_panel_box.add_child(UiTheme.spacer(8))
	var yes := _panel_button("Burn it and begin", func() -> void: UiContext.game_call("start_solo", [slot, true]), 340.0, 17)
	yes.danger = true
	_panel_box.add_child(yes)
	_panel_box.add_child(_panel_button("Keep it", _show_solo, 340.0, 15))
	yes.grab_focus()


func _show_multiplayer() -> void:
	_open_panel("WARBAND", "play together on the same network")
	_panel_box.add_child(_text("The host lights a fire and shares four runes.\nCompanions carve the same runes to join."))
	_panel_box.add_child(UiTheme.spacer(4))
	var runes := HBoxContainer.new()
	runes.alignment = BoxContainer.ALIGNMENT_CENTER
	runes.add_theme_constant_override("separation", 18)
	for r in [0, 8, 14, 15]:
		var g := RuneGlyph.new()
		g.rune = r
		g.custom_minimum_size = Vector2(44, 60)
		runes.add_child(g)
	_panel_box.add_child(runes)
	_panel_box.add_child(UiTheme.spacer(6))
	var host := _panel_button("Host a warband", func() -> void: UiContext.game_call("open_lobby_host"), 340.0, 18)
	_panel_box.add_child(host)
	_panel_box.add_child(_panel_button("Join with runes", func() -> void: UiContext.game_call("open_lobby_join"), 340.0, 18))
	_panel_box.add_child(UiTheme.spacer(2))
	_panel_box.add_child(_back_button())
	host.grab_focus()


func _show_settings() -> void:
	if _settings != null:
		return
	_return_focus = get_viewport().gui_get_focus_owner()
	_settings = SettingsMenu.new()
	add_child(_settings)
	_column.visible = false
	_settings.closed.connect(func() -> void:
		_settings = null
		_column.visible = true
		var f := _return_focus if _return_focus != null and is_instance_valid(_return_focus) else _first_button
		f.grab_focus())


func _show_credits() -> void:
	_open_panel("CREDITS")
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.custom_minimum_size = Vector2(540, 0)
	text.add_theme_font_size_override("normal_font_size", 13)
	text.add_theme_color_override("default_color", UiTheme.TEXT_DIM)
	text.text = "[center]" + VictoryScreen.credits_bbcode() + "[/center]"
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(550, clampf(size.y * 0.36, 200.0, 360.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(text)
	_panel_box.add_child(scroll)
	var back := _back_button()
	_panel_box.add_child(back)
	back.grab_focus()


# --- Development capture ---------------------------------------------------------------

func _maybe_capture() -> void:
	if _capture_started:
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture-menu="):
			_capture_started = true
			var script: Script = load("res://tests/gpu/menu_capture.gd")
			var cap: Node = script.new()
			cap.set("out_dir", a.get_slice("=", 1))
			cap.set("menu", self)
			get_tree().root.add_child.call_deferred(cap)
