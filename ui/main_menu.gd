class_name MainMenu
extends Control
## Title screen. A live fly-over of the world plays behind everything
## (MenuBackdrop, through the player's render style); the burning BURN
## title, a tagline and the option stack sit centred over a soft dark band.
## Sub-pages (runs, new run, online, credits) open in a framed panel in the
## same place; Esc goes back one page. Settings opens its own overlay.
##
## Main stack: PLAY (the runs page), ONLINE, SETTINGS, CREDITS, QUIT.

const VERSION := "v1.0  ·  built with Godot 4.7"
const TAGLINES := [
	"The world is ash. Something beneath it still burns.",
	"Dig deep enough and the earth grows warm.",
	"Three seals. One gate. No way back.",
]
const RUN_NAMES := ["The Ashen Road", "Cinderfall", "Last Embers", "The Long Dark", "Kindling", "Smoke and Iron",
	"The Hollow Crown", "Pyre Song", "Under the Ash", "The Burning Deep"]
const DIFFICULTY_TEXT := [
	"Enemies hit for half damage. For exploring and the story.",
	"The intended balance.",
	"Enemies hit 50% harder. Every mistake costs.",
]

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
var _panel_tall := false
var _dim := 0.0
## Esc on a sub-page: where to go back to (empty: close the panel).
var _back := Callable()
## Runs page state.
var _runs: Array = []
var _selected_id := ""
var _rows: Array[RunRow] = []
var _details: VBoxContainer
var _play_button: MenuOption
## The credits text while the credits page is open (arrow keys scroll it).
var _credits_text: RichTextLabel


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
	var play := _add_main_button("Play", _show_runs)
	play.detail = _play_detail()
	if play.detail != "":
		play.custom_minimum_size.y = 68
	_add_main_button("Online", _show_online)
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
		title_h = clampf(h * (0.11 if _panel_tall else 0.15), 80.0, 170.0)
	_title.custom_minimum_size = Vector2(title_h * 3.4, title_h)
	var cut := _panel_open and (h < 760.0 or _panel_tall)
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
	UiTheme.fit_scale(_column, size - Vector2(40, 100))
	_hints.visible = size.x >= 1100.0 and not _panel_tall
	_dim = move_toward(_dim, 0.25 if _panel_open else 0.0, delta * 1.5)
	_stage.focus_dim = _dim


func _input(event: InputEvent) -> void:
	# The credits scroll with up / down (the buttons below sit in a row).
	if _credits_text == null or not is_instance_valid(_credits_text) or not _credits_text.is_visible_in_tree():
		return
	var step := 0.0
	if event.is_action_pressed("ui_up", true):
		step = -70.0
	elif event.is_action_pressed("ui_down", true):
		step = 70.0
	elif event.is_action_pressed("ui_page_up", true):
		step = -_credits_text.size.y * 0.85
	elif event.is_action_pressed("ui_page_down", true):
		step = _credits_text.size.y * 0.85
	if step != 0.0:
		var bar := _credits_text.get_v_scroll_bar()
		bar.value = clampf(bar.value + step, 0.0, bar.max_value)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _panel_open:
		_go_back()
		get_viewport().set_input_as_handled()


func _go_back() -> void:
	if _back.is_valid():
		UiContext.sound("ui_back")
		_back.call()
	else:
		_close_panel()


# --- Panel ---------------------------------------------------------------------------

func _open_panel(title: String, subtitle := "", width := 620.0, tall := false) -> void:
	if not _panel_open:
		var f := get_viewport().gui_get_focus_owner()
		_return_focus = f if f != null and _stack.is_ancestor_of(f) else _first_button
	for c in _panel_box.get_children():
		_panel_box.remove_child(c)
		c.queue_free()
	_rows.clear()
	_details = null
	_play_button = null
	_credits_text = null
	_back = Callable()
	_panel.title = title
	_panel.subtitle = subtitle
	_panel.custom_minimum_size = Vector2(width, 0)
	_panel_tall = tall
	_panel_open = true
	_stack.visible = false
	_panel.visible = true
	_panel.modulate.a = 0.0
	create_tween().tween_property(_panel, "modulate:a", 1.0, 0.22)
	_layout()
	UiContext.sound("ui_open")


func _close_panel() -> void:
	_panel_open = false
	_panel_tall = false
	_credits_text = null
	_back = Callable()
	_panel.visible = false
	_stack.visible = true
	_layout()
	UiContext.sound("ui_back")
	var f := _return_focus if _return_focus != null and is_instance_valid(_return_focus) else _first_button
	f.grab_focus()


## Warrior / Archer / Mage, chosen before loading (solo too). Kept in the
## profile (PlayerProfile) and applied when the world loads (GameWorld).
func _role_picker() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var pick := OptionButton.new()
	for r: String in Roles.ORDER:
		pick.add_item("Role: %s (%s)" % [Roles.role_name(r), String(Roles.ROLES[r]["weapon"])])
	pick.select(maxi(0, Roles.ORDER.find(PlayerProfile.role())))
	pick.custom_minimum_size = Vector2(320, 34)
	box.add_child(pick)
	var hint := UiTheme.label(String(Roles.ROLES[PlayerProfile.role()]["desc"]), UiTheme.SIZE_SMALL, UiTheme.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.custom_minimum_size.x = 320
	box.add_child(hint)
	pick.item_selected.connect(func(i: int) -> void:
		var r: String = Roles.ORDER[clampi(i, 0, Roles.ORDER.size() - 1)]
		PlayerProfile.set_role(r)
		hint.text = String(Roles.ROLES[r]["desc"]))
	return box


func _panel_button(text: String, cb: Callable, width := 300.0, size_px := 17) -> MenuOption:
	var b := MenuOption.new(text.to_upper(), cb, size_px)
	b.custom_minimum_size = Vector2(width, size_px * 2.4)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b


func _back_button(cb := Callable()) -> MenuOption:
	return _panel_button("Back", cb if cb.is_valid() else _go_back, 200.0, 15)


func _text(t: String, color := UiTheme.TEXT_DIM, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := UiTheme.label(t, UiTheme.SIZE_BODY, color, align)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size.x = 520
	return l


func _row_of(items: Array, sep := 6) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", sep)
	for c: Control in items:
		row.add_child(c)
	return row


# --- Main stack ------------------------------------------------------------------------

func _play_detail() -> String:
	var runs := _list_runs()
	if runs.is_empty():
		return ""
	var r: Dictionary = runs[0]
	return "%s  ·  %s" % [str(r.get("title", "")), UiTheme.format_time(float(r.get("play_time", 0.0)))]


func _list_runs() -> Array:
	var runs: Variant = UiContext.game_call("list_runs", [], null)
	return runs if runs is Array else []


func _show_online() -> void:
	if UiContext.game_has("open_server_browser"):
		UiContext.game_call("open_server_browser")
		return
	_open_panel("ONLINE", "servers and friends")
	_panel_box.add_child(_text("The server browser is not available in this build yet.\nTo play with friends, host a run from Play or join with the host's runes."))
	_panel_box.add_child(UiTheme.spacer(6))
	var join := _panel_button("Join with runes", func() -> void: UiContext.game_call("open_lobby_join"), 340.0, 17)
	_panel_box.add_child(join)
	_panel_box.add_child(_back_button())
	join.grab_focus()


# --- Runs ------------------------------------------------------------------------------

## The runs page: every run, most recently played first, with the chosen
## run's details and actions beside the list.
func _show_runs(select_id := "") -> void:
	_runs = _list_runs()
	_open_panel("RUNS", "every world you have lit, most recent first", 940.0, true)
	if select_id == "" and _selected_id != "":
		select_id = _selected_id
	var new_run := _panel_button("New run", _show_new_run, 200.0, 16)
	var host := _panel_button("Host co-op", func() -> void: UiContext.game_call("open_lobby_host"), 220.0, 16)
	var join := _panel_button("Join with runes", func() -> void: UiContext.game_call("open_lobby_join"), 260.0, 16)
	_panel_box.add_child(_row_of([new_run, host, join], 10))
	var hint := UiTheme.label("Host co-op opens the shared warband world. To bring friends into one of your runs, choose it and press Host for friends.",
			UiTheme.SIZE_SMALL, UiTheme.TEXT_FAINT, HORIZONTAL_ALIGNMENT_CENTER)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.custom_minimum_size.x = 600
	_panel_box.add_child(hint)

	if _runs.is_empty():
		_panel_box.add_child(UiTheme.spacer(18))
		_panel_box.add_child(UiTheme.title("No runs yet", 20, UiTheme.TEXT, 600))
		(_panel_box.get_child(-1) as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_panel_box.add_child(_text("Light your first fire: start a new run."))
		_panel_box.add_child(UiTheme.spacer(18))
		_panel_box.add_child(_back_button())
		new_run.grab_focus()
		return

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	_panel_box.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.custom_minimum_size = Vector2(500, clampf(size.y * 0.46, 230.0, 470.0))
	body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	_details = VBoxContainer.new()
	_details.custom_minimum_size = Vector2(340, 0)
	_details.add_theme_constant_override("separation", 3)
	body.add_child(_details)

	var focus_row: RunRow = null
	for r: Dictionary in _runs:
		var row := RunRow.new(r)
		row.chosen.connect(_select_run)
		row.activated.connect(func(info: Dictionary) -> void: _play_run(str(info["id"])))
		list.add_child(row)
		_rows.append(row)
		if str(r["id"]) == select_id:
			focus_row = row
	if focus_row == null:
		focus_row = _rows[0]
	# Up from the first run reaches the buttons above; down from the last wraps to Back.
	_panel_box.add_child(UiTheme.spacer(4))
	var back := _back_button()
	_panel_box.add_child(back)
	for b: Control in [new_run, host, join]:
		b.focus_neighbor_bottom = b.get_path_to(_rows[0])
	_rows[0].focus_neighbor_top = _rows[0].get_path_to(new_run)
	_rows[-1].focus_neighbor_bottom = _rows[-1].get_path_to(back)
	back.focus_neighbor_top = back.get_path_to(_rows[-1])
	_select_run(focus_row.run)
	focus_row.grab_focus.call_deferred()


func _run_by_id(id: String) -> Dictionary:
	for r: Dictionary in _runs:
		if str(r["id"]) == id:
			return r
	return {}


func _select_run(info: Dictionary) -> void:
	_selected_id = str(info.get("id", ""))
	for row in _rows:
		row.selected = str(row.run.get("id", "")) == _selected_id
	if _details == null:
		return
	for c in _details.get_children():
		_details.remove_child(c)
		c.queue_free()
	var title := UiTheme.title(str(info.get("title", "")), 20, UiTheme.ACCENT_HOT, 700)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	title.custom_minimum_size.x = 330
	_details.add_child(title)
	_details.add_child(UiTheme.label(RunRow.line_rank(info), UiTheme.SIZE_SMALL, UiTheme.ACCENT))
	_details.add_child(UiTheme.spacer(4))
	var difficulty := clampi(int(info.get("difficulty", SaveSystem.DIFFICULTY_NORMAL)), 0, SaveSystem.DIFFICULTIES.size() - 1)
	for pair: Array in [
			["Time played", UiTheme.format_time(float(info.get("play_time", 0.0)))],
			["Last played", RunRow.date_text(float(info.get("saved_at", 0.0)))],
			["Created", RunRow.date_text(float(info.get("created_at", 0.0)))],
			["World seed", str(int(info.get("seed", 0)))],
			["Difficulty", str(SaveSystem.DIFFICULTIES[difficulty])],
			["Wanderer", str(info.get("name", ""))],
		]:
		var line := HBoxContainer.new()
		var k := UiTheme.label(str(pair[0]), UiTheme.SIZE_SMALL, UiTheme.TEXT_DIM)
		k.custom_minimum_size.x = 110
		line.add_child(k)
		line.add_child(UiTheme.label(str(pair[1]), UiTheme.SIZE_SMALL, UiTheme.TEXT))
		_details.add_child(line)
	if bool(info.get("legacy", false)):
		_details.add_child(UiTheme.label("from an earlier version (%s)" % str(info["id"]).replace("_", " "), UiTheme.SIZE_SMALL, UiTheme.TEXT_FAINT))
	_details.add_child(UiTheme.spacer(8))
	var id := _selected_id
	_details.add_child(_role_picker())
	_play_button = _panel_button("Play", func() -> void: _play_run(id), 320.0, 18)
	_details.add_child(_play_button)
	var host := _panel_button("Host for friends", func() -> void: UiContext.game_call("open_lobby_host", [id]), 320.0, 15)
	_details.add_child(host)
	var rename := _panel_button("Rename", func() -> void: _show_rename(id), 320.0, 15)
	_details.add_child(rename)
	var del := _panel_button("Delete", func() -> void: _confirm_delete(id), 320.0, 15)
	del.danger = true
	_details.add_child(del)
	# Right from any run goes to its actions; left from the actions returns to it.
	var sel: RunRow = null
	for row in _rows:
		if row.selected:
			sel = row
	if sel != null:
		for row in _rows:
			row.focus_neighbor_right = row.get_path_to(_play_button)
		for b: Control in [_play_button, host, rename, del]:
			b.focus_neighbor_left = b.get_path_to(sel)
	host.focus_neighbor_top = host.get_path_to(_play_button)
	_play_button.focus_neighbor_bottom = _play_button.get_path_to(host)


func _play_run(id: String) -> void:
	if id == "":
		return
	UiContext.game_call("start_solo", [id, false])


func _show_new_run() -> void:
	_open_panel("NEW RUN", "a new world, a new wanderer", 680.0)
	_back = _show_runs
	var form := GridContainer.new()
	form.columns = 2
	form.add_theme_constant_override("h_separation", 16)
	form.add_theme_constant_override("v_separation", 10)
	_panel_box.add_child(form)
	form.add_child(_form_label("Name"))
	var name_edit := LineEdit.new()
	name_edit.text = _suggest_name()
	name_edit.max_length = 40
	name_edit.custom_minimum_size = Vector2(400, 36)
	name_edit.select_all_on_focus = true
	form.add_child(name_edit)
	form.add_child(_form_label("World seed"))
	var seed_edit := LineEdit.new()
	seed_edit.placeholder_text = "random"
	seed_edit.max_length = 40
	seed_edit.custom_minimum_size = Vector2(400, 36)
	form.add_child(seed_edit)
	form.add_child(Control.new())
	var seed_hint := UiTheme.label("Leave empty for a random world. A number or any phrase gives the same world every time.",
			UiTheme.SIZE_SMALL, UiTheme.TEXT_FAINT)
	seed_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	seed_hint.custom_minimum_size.x = 400
	form.add_child(seed_hint)
	form.add_child(_form_label("Difficulty"))
	var diff := OptionButton.new()
	for d: String in SaveSystem.DIFFICULTIES:
		diff.add_item(d)
	diff.select(SaveSystem.DIFFICULTY_NORMAL)
	diff.custom_minimum_size = Vector2(400, 36)
	form.add_child(diff)
	form.add_child(Control.new())
	var diff_hint := UiTheme.label(DIFFICULTY_TEXT[SaveSystem.DIFFICULTY_NORMAL], UiTheme.SIZE_SMALL, UiTheme.TEXT_DIM)
	diff_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	diff_hint.custom_minimum_size.x = 400
	form.add_child(diff_hint)
	diff.item_selected.connect(func(i: int) -> void: diff_hint.text = DIFFICULTY_TEXT[clampi(i, 0, DIFFICULTY_TEXT.size() - 1)])
	_panel_box.add_child(UiTheme.spacer(8))
	var begin := func() -> void:
		UiContext.game_call("create_run", [name_edit.text, seed_edit.text, diff.selected])
	var start := _panel_button("Begin", begin, 340.0, 18)
	_panel_box.add_child(start)
	_panel_box.add_child(_back_button())
	name_edit.text_submitted.connect(func(_t: String) -> void: seed_edit.grab_focus())
	seed_edit.text_submitted.connect(func(_t: String) -> void: start.grab_focus())
	name_edit.grab_focus.call_deferred()


func _form_label(t: String) -> Label:
	var l := UiTheme.label(t, UiTheme.SIZE_BODY, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	l.custom_minimum_size = Vector2(120, 36)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _suggest_name() -> String:
	var used := {}
	for r: Dictionary in _list_runs():
		used[str(r.get("title", ""))] = true
	var start := randi() % RUN_NAMES.size()
	for i in RUN_NAMES.size():
		var n: String = RUN_NAMES[(start + i) % RUN_NAMES.size()]
		if not used.has(n):
			return n
	return "Run %d" % (used.size() + 1)


func _show_rename(id: String) -> void:
	var info := _run_by_id(id)
	_open_panel("RENAME RUN", "", 620.0)
	_back = _show_runs.bind(id)
	var edit := LineEdit.new()
	edit.text = str(info.get("title", ""))
	edit.max_length = 40
	edit.custom_minimum_size = Vector2(440, 38)
	edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	edit.select_all_on_focus = true
	_panel_box.add_child(edit)
	_panel_box.add_child(UiTheme.spacer(6))
	var save := func() -> void:
		if edit.text.strip_edges() != "":
			UiContext.game_call("rename_run", [id, edit.text])
		_show_runs(id)
	edit.text_submitted.connect(func(_t: String) -> void: save.call())
	_panel_box.add_child(_panel_button("Save name", save, 300.0, 17))
	_panel_box.add_child(_back_button())
	edit.grab_focus.call_deferred()


func _confirm_delete(id: String) -> void:
	var info := _run_by_id(id)
	_open_panel("DELETE RUN", "", 620.0)
	_back = _show_runs.bind(id)
	_panel_box.add_child(_text("“%s” will be lost to the ash: its world, wanderer and explored map.\nThis cannot be undone." % str(info.get("title", "")), UiTheme.TEXT))
	_panel_box.add_child(UiTheme.spacer(8))
	var keep := _panel_button("Keep it", _show_runs.bind(id), 340.0, 17)
	var yes := _panel_button("Delete forever", func() -> void:
		UiContext.game_call("delete_run", [id])
		_selected_id = ""
		_show_runs(), 340.0, 15)
	yes.danger = true
	_panel_box.add_child(keep)
	_panel_box.add_child(yes)
	keep.grab_focus.call_deferred()


# --- Settings and credits ------------------------------------------------------------------

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
	_open_panel("CREDITS", "", 860.0, true)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.scroll_active = true
	text.scroll_following = false
	text.meta_underlined = true
	text.selection_enabled = false
	text.focus_mode = Control.FOCUS_NONE
	text.custom_minimum_size = Vector2(780, clampf(size.y * 0.5, 240.0, 520.0))
	text.add_theme_font_size_override("normal_font_size", 14)
	text.add_theme_font_size_override("bold_font_size", 15)
	text.add_theme_font_override("normal_font", UiTheme.MONO)
	text.add_theme_font_override("bold_font", UiTheme.title_font(700))
	text.add_theme_color_override("default_color", UiTheme.TEXT)
	text.add_theme_constant_override("line_separation", 3)
	text.text = "[center]" + VictoryScreen.credits_bbcode() + "[/center]"
	text.meta_clicked.connect(VictoryScreen.open_link)
	text.meta_hover_started.connect(func(_m: Variant) -> void: text.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND)
	text.meta_hover_ended.connect(func(_m: Variant) -> void: text.mouse_default_cursor_shape = Control.CURSOR_ARROW)
	_panel_box.add_child(text)
	_credits_text = text
	var hint := UiTheme.label("↑ ↓ scroll   ·   click a link to open it in your browser", UiTheme.SIZE_SMALL, UiTheme.TEXT_FAINT, HORIZONTAL_ALIGNMENT_CENTER)
	_panel_box.add_child(hint)
	var repo := _panel_button("BURN on GitHub", func() -> void: VictoryScreen.open_link(VictoryScreen.REPO_URL), 250.0, 14)
	var profile := _panel_button("GitHub profile", func() -> void: VictoryScreen.open_link(VictoryScreen.PROFILE_URL), 230.0, 14)
	var back := _back_button()
	_panel_box.add_child(_row_of([repo, profile, back], 8))
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
