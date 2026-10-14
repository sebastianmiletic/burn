class_name LobbyScreen
extends Control
## Multiplayer lobby. Host mode shows the party's four runes and who has
## joined; join mode is a rune keypad (click or type the rune keys).

signal closed

enum Mode { HOST, JOIN }

var mode := Mode.HOST

var _code_row: HBoxContainer
var _players: VBoxContainer
var _status: Label
var _begin: Button
var _entry: Array[RuneGlyph] = []
var _typed := PackedInt32Array()
var _join_button: Button
var _keys: Array[RuneGlyph] = []
var _joining := false
var _ready_box: CheckBox


func _init(is_host := true) -> void:
	mode = Mode.HOST if is_host else Mode.JOIN


static func create(lobby_mode: Mode) -> LobbyScreen:
	return LobbyScreen.new(lobby_mode == Mode.HOST)


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(EmberBackground.new())
	add_child(UiTheme.scrim(0.35))

	var frame := TermFrame.new()
	frame.title = "HOST A WARBAND" if mode == Mode.HOST else "JOIN A WARBAND"
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -440
	frame.offset_right = 440
	frame.offset_top = -310
	frame.offset_bottom = 310
	add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	frame.add_child(box)

	var name_row := HBoxContainer.new()
	name_row.add_child(UiTheme.label("Your name", UiTheme.SIZE_BODY, UiTheme.TEXT_DIM))
	var name_edit := LineEdit.new()
	name_edit.text = str(UiContext.setting("gameplay", "player_name"))
	name_edit.max_length = 20
	name_edit.custom_minimum_size = Vector2(240, 0)
	name_edit.text_changed.connect(func(t: String) -> void:
		if t.strip_edges() != "":
			UiContext.set_setting("gameplay", "player_name", t.strip_edges()))
	name_row.add_child(name_edit)
	box.add_child(name_row)
	box.add_child(UiTheme.hsep())

	if mode == Mode.HOST:
		_build_host(box)
	else:
		_build_join(box)

	_status = UiTheme.label("", UiTheme.SIZE_BODY, UiTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_status)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	if mode == Mode.HOST:
		_begin = UiTheme.button("Begin the campaign", func() -> void: UiContext.game_call("start_campaign"), 18)
		_begin.add_theme_font_override("font", UiTheme.title_font(700))
		actions.add_child(_begin)
	else:
		_join_button = UiTheme.button("Join", _try_join, 18)
		_join_button.add_theme_font_override("font", UiTheme.title_font(700))
		actions.add_child(_join_button)
		_ready_box = CheckBox.new()
		_ready_box.text = "Ready"
		_ready_box.visible = false
		_ready_box.toggled.connect(func(on: bool) -> void: UiContext.call_on(UiContext.net(), "set_ready", [on]))
		actions.add_child(_ready_box)
	actions.add_child(UiTheme.button("Leave", _leave, 18))
	box.add_child(actions)

	var net := UiContext.net()
	if net != null:
		net.connect("lobby_changed", _refresh)
		net.connect("join_failed", _on_join_failed)
		if net.has_signal("hosting_started"):
			net.connect("hosting_started", func(_r: PackedInt32Array) -> void: _refresh())
		if net.has_signal("join_status"):
			net.connect("join_status", _on_join_status)
		if net.has_signal("peer_left"):
			net.connect("peer_left", func(_id: int, who: String) -> void: _set_status("%s left the warband." % who, UiTheme.TEXT_DIM))
	if mode == Mode.HOST and net != null:
		var runes: Variant = net.get("runes")
		if not (runes is PackedInt32Array) or (runes as PackedInt32Array).size() != 4:
			runes = net.call("host_party", str(UiContext.setting("gameplay", "player_name")))
	_refresh()
	UiContext.sound("ui_open")


func _build_host(box: VBoxContainer) -> void:
	var hint := UiTheme.label("Companions on your network carve these runes to join you.", UiTheme.SIZE_BODY, UiTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(hint)
	_code_row = HBoxContainer.new()
	_code_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_code_row.add_theme_constant_override("separation", 26)
	for i in 4:
		var g := RuneGlyph.new()
		g.rune = -1
		g.stroke_width = 4.0
		g.show_name = true
		g.custom_minimum_size = Vector2(96, 140)
		_code_row.add_child(g)
	box.add_child(_code_row)
	box.add_child(UiTheme.hsep())
	box.add_child(UiTheme.label("WARBAND", UiTheme.SIZE_SMALL, UiTheme.ACCENT_DIM))
	_players = VBoxContainer.new()
	_players.custom_minimum_size = Vector2(0, 120)
	box.add_child(_players)


func _build_join(box: VBoxContainer) -> void:
	box.add_child(UiTheme.label("Carve the host's four runes. Click them, or type their keys.", UiTheme.SIZE_BODY, UiTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var entry_row := HBoxContainer.new()
	entry_row.alignment = BoxContainer.ALIGNMENT_CENTER
	entry_row.add_theme_constant_override("separation", 22)
	for i in 4:
		var g := RuneGlyph.new()
		g.rune = -1
		g.stroke_width = 4.0
		g.custom_minimum_size = Vector2(76, 104)
		entry_row.add_child(g)
		_entry.append(g)
	box.add_child(entry_row)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var center := CenterContainer.new()
	center.add_child(grid)
	for r in 16:
		var k := RuneGlyph.new()
		k.rune = r
		k.lit = false
		k.clickable = true
		k.show_name = true
		k.custom_minimum_size = Vector2(70, 84)
		k.pressed.connect(_type_rune)
		grid.add_child(k)
		_keys.append(k)
	box.add_child(center)
	var hint := UiTheme.label("Backspace removes a rune  ·  Enter joins", UiTheme.SIZE_SMALL, UiTheme.TEXT_FAINT, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(hint)
	_players = VBoxContainer.new()
	box.add_child(_players)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_leave()
		return
	if mode != Mode.JOIN or _joining:
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_BACKSPACE:
		if not _typed.is_empty():
			_typed.resize(_typed.size() - 1)
			UiContext.sound("ui_back")
			_update_entry()
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
		_try_join()
		get_viewport().set_input_as_handled()
	else:
		var r := RuneGlyph.key_to_rune(k.keycode)
		if r >= 0 and not (get_viewport().gui_get_focus_owner() is LineEdit):
			_keys[r].flash()
			UiContext.sound("rune")
			_type_rune(r)
			get_viewport().set_input_as_handled()


func _type_rune(r: int) -> void:
	if _typed.size() >= 4 or _joining:
		return
	_typed.append(r)
	_update_entry()


func _update_entry() -> void:
	for i in 4:
		_entry[i].rune = _typed[i] if i < _typed.size() else -1
		if i == _typed.size() - 1:
			_entry[i].flash()
	_join_button.disabled = _typed.size() != 4
	_set_status(RuneGlyph.code_text(_typed) if not _typed.is_empty() else "", UiTheme.ACCENT_DIM)


func _try_join() -> void:
	if _typed.size() != 4 or _joining:
		return
	var net := UiContext.net()
	if net == null:
		return
	_joining = true
	_join_button.disabled = true
	_set_status("Listening for the host's fire…", UiTheme.ACCENT)
	net.call("join_party", _typed, str(UiContext.setting("gameplay", "player_name")))


func _on_join_status(state: String) -> void:
	match state:
		"searching":
			_set_status("Listening for the host's fire…", UiTheme.ACCENT)
		"connecting":
			_set_status("Found the warband. Crossing over…", UiTheme.ACCENT_HOT)
		"joined":
			_joining = false
			_set_status("Joined. Waiting for the host to begin the campaign…", UiTheme.GOOD)
			if _ready_box != null:
				_ready_box.visible = true
			if _join_button != null:
				_join_button.visible = false


func _on_join_failed(reason: String) -> void:
	_joining = false
	if _join_button != null:
		_join_button.disabled = _typed.size() != 4
	_set_status(reason, UiTheme.DANGER)
	UiContext.sound("ui_back")


func _leave() -> void:
	var net := UiContext.net()
	if net != null:
		net.call("leave")
	UiContext.sound("ui_back")
	closed.emit()
	if UiContext.game_has("open_main_menu"):
		UiContext.game_call("open_main_menu")
	else:
		queue_free()


func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func _refresh() -> void:
	var net := UiContext.net()
	if net == null:
		return
	if mode == Mode.HOST and _code_row != null:
		var runes: Variant = net.get("runes")
		if runes is PackedInt32Array and (runes as PackedInt32Array).size() == 4:
			for i in 4:
				var g: RuneGlyph = _code_row.get_child(i)
				if g.rune != runes[i]:
					g.rune = runes[i]
					g.flash()
		else:
			_set_status("Could not open a party on this network.", UiTheme.DANGER)
	var players: Dictionary = net.get("players") if net.get("players") is Dictionary else {}
	for c in _players.get_children():
		c.queue_free()
	if mode == Mode.JOIN and players.is_empty():
		return
	if mode == Mode.JOIN:
		_players.add_child(UiTheme.label("WARBAND", UiTheme.SIZE_SMALL, UiTheme.ACCENT_DIM))
		if _ready_box != null:
			_ready_box.visible = true
	var ids := players.keys()
	ids.sort()
	for id: int in ids:
		var p: Dictionary = players[id]
		var row := HBoxContainer.new()
		var color: Color = p.get("color", UiContext.call_on(net, "player_color", [id], UiTheme.ACCENT))
		var dot := UiTheme.label("●", UiTheme.SIZE_BODY, color)
		row.add_child(dot)
		var who := str(p.get("name", UiContext.call_on(net, "player_name", [id], "Wanderer")))
		var name_l := UiTheme.label(who, UiTheme.SIZE_BODY, UiTheme.TEXT)
		name_l.custom_minimum_size.x = 220
		row.add_child(name_l)
		if p.get("ready", false):
			row.add_child(UiTheme.label("ready", UiTheme.SIZE_SMALL, UiTheme.GOOD))
		if id != int(UiContext.call_on(net, "my_id", [], 0)) and UiContext.call_on(net, "is_online", [], false):
			var ping: Variant = UiContext.call_on(net, "ping_ms", [id], null)
			if ping != null and float(ping) >= 0.0:
				row.add_child(UiTheme.label("%d ms" % roundi(float(ping)), UiTheme.SIZE_SMALL, UiTheme.TEXT_FAINT))
		if id == 1:
			row.add_child(UiTheme.label("host", UiTheme.SIZE_SMALL, UiTheme.ACCENT_DIM))
		if id == int(UiContext.call_on(net, "my_id", [], 0)):
			row.add_child(UiTheme.label("you", UiTheme.SIZE_SMALL, UiTheme.TEXT_FAINT))
		_players.add_child(row)
	if mode == Mode.HOST:
		var n := players.size()
		if _status.text == "" or _status.text.begins_with("Waiting") or _status.text.ends_with("ready."):
			_set_status("Waiting for companions…  (%d in the warband)" % n if n <= 1 else "%d in the warband — ready." % n, UiTheme.TEXT_DIM)
