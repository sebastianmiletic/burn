class_name ServerBrowser
extends Control
## ONLINE: public servers from the master list plus listed servers on the LAN.
## Columns: lock, name, mode, players, ping (measured with an ENet handshake),
## version. Search, filters, sortable columns, refresh, join (password prompt
## when locked), direct connect by address and "Host public server".
## Drawn like the other title screens (MenuStage + MenuPanel). Esc goes back.

signal closed

const COLS := [["", 30], ["Name", 330], ["Mode", 120], ["Players", 90], ["Ping", 80], ["Version", 110]]
const SORT_KEYS := ["password", "name", "mode", "players", "ping", "protocol"]
const MAX_PINGS := 6

## Skip the master / LAN queries (UI gallery fixtures).
var offline_preview := false

var _entries: Array = []          # merged online + LAN entries
var _rows: Array = []             # [Button, entry]
var _list: VBoxContainer
var _status: Label
var _search: LineEdit
var _hide_full: CheckBox
var _hide_incompatible: CheckBox
var _hide_locked: CheckBox
var _headers: Array[Button] = []
var _sort_col := 3
var _sort_desc := true
var _selected: Dictionary = {}
var _frame: MenuPanel
var _overlay: Control
var _overlay_focus: Control
var _master_edit: LineEdit
var _join_button: MenuOption
var _pings: Array = []            # [ServerList.Ping, entry]
var _ping_queue: Array = []
var _fetching := false
var _joining := false
var _list_client: ServerList
var _lan: LanDiscovery


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var stage := MenuStage.new()
	stage.focus_dim = 0.3
	stage.show_caption = false
	add_child(stage)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_frame = MenuPanel.new("ONLINE")
	_frame.subtitle = "public servers and listed fires on your network"
	_frame.custom_minimum_size = Vector2(900, 0)
	center.add_child(_frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_frame.add_child(box)

	# Search and filters.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	_search = LineEdit.new()
	_search.placeholder_text = "search servers…"
	_search.custom_minimum_size = Vector2(260, 0)
	_search.max_length = 48
	_search.text_changed.connect(func(_t: String) -> void: _rebuild())
	bar.add_child(_search)
	_hide_full = _filter_box(bar, "Hide full")
	_hide_incompatible = _filter_box(bar, "Hide incompatible")
	_hide_locked = _filter_box(bar, "Hide locked")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var refresh := UiTheme.button("Refresh", refresh)
	refresh.tooltip_text = "Fetch the list again (F5)"
	bar.add_child(refresh)
	box.add_child(bar)

	# Column headers (click to sort; again to reverse).
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	for i in COLS.size():
		var h := Button.new()
		h.flat = true
		h.text = COLS[i][0]
		if i == 0:
			var icon := LockIcon.new()
			icon.position = Vector2(9, 6)
			icon.modulate = UiTheme.ACCENT_DIM
			h.add_child(icon)
		h.alignment = HORIZONTAL_ALIGNMENT_LEFT
		h.custom_minimum_size = Vector2(COLS[i][1], 26)
		h.add_theme_font_override("font", UiTheme.title_font_spaced(700, 2))
		h.add_theme_font_size_override("font_size", 13)
		h.add_theme_color_override("font_color", UiTheme.ACCENT_DIM)
		h.add_theme_color_override("font_hover_color", UiTheme.ACCENT_HOT)
		h.add_theme_color_override("font_focus_color", UiTheme.ACCENT_HOT)
		h.tooltip_text = "Sort by %s" % (COLS[i][0] if i > 0 else "password")
		h.pressed.connect(_sort_by.bind(i))
		head.add_child(h)
		_headers.append(h)
	box.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 1)
	scroll.add_child(_list)
	box.add_child(scroll)

	_status = UiTheme.label("", UiTheme.SIZE_BODY, UiTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.custom_minimum_size = Vector2(0, 40)
	box.add_child(_status)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 6)
	_join_button = _action(actions, "JOIN", _join_selected, 170)
	_action(actions, "DIRECT CONNECT", _show_direct, 230)
	_action(actions, "HOST PUBLIC SERVER", _show_host, 270)
	_action(actions, "BACK", _back, 140)
	box.add_child(actions)

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 8)
	foot.add_child(UiTheme.label("Master server", UiTheme.SIZE_SMALL, UiTheme.TEXT_FAINT))
	_master_edit = LineEdit.new()
	_master_edit.custom_minimum_size = Vector2(380, 0)
	_master_edit.max_length = 200
	_master_edit.add_theme_font_size_override("font_size", 12)
	_master_edit.text = ServerList.master_url()
	_master_edit.tooltip_text = "Address of the server list (see server/README.md). Enter saves and refreshes; empty restores the default."
	_master_edit.text_submitted.connect(func(t: String) -> void:
		var v := t.strip_edges()
		UiContext.set_setting("online", "master_server_url", "" if v == ServerList.DEFAULT_MASTER_URL else v)
		_master_edit.text = ServerList.master_url()
		refresh())
	foot.add_child(_master_edit)
	box.add_child(foot)

	_list_client = ServerList.new()
	_list_client.listed.connect(_on_listed)
	add_child(_list_client)
	_lan = LanDiscovery.new()
	_lan.browsed.connect(_on_lan)
	add_child(_lan)
	var net := UiContext.net()
	if net != null:
		net.connect("join_failed", _on_join_failed)
		net.connect("join_status", _on_join_status)
	_update_headers()
	if not offline_preview:
		refresh()
	_join_button.grab_focus.call_deferred()
	UiContext.sound("ui_open")


func _filter_box(parent: Control, text: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.toggled.connect(func(_on: bool) -> void:
		UiContext.sound("ui_click")
		_rebuild())
	parent.add_child(c)
	return c


func _action(parent: Control, text: String, cb: Callable, w: float) -> MenuOption:
	var b := MenuOption.new(text, cb, 15)
	b.custom_minimum_size = Vector2(w, 42)
	parent.add_child(b)
	return b


func _process(_delta: float) -> void:
	UiTheme.fit_scale(_frame, size - Vector2(40, 60))
	var done: Array = []
	for p: Array in _pings:
		if (p[0] as ServerList.Ping).poll():
			p[1]["ping"] = (p[0] as ServerList.Ping).ms
			done.append(p)
	for p: Array in done:
		_pings.erase(p)
	while _pings.size() < MAX_PINGS and not _ping_queue.is_empty():
		var e: Dictionary = _ping_queue.pop_front()
		_pings.append([ServerList.Ping.new(String(e["ip"]), int(e["port"])), e])
	if not done.is_empty():
		_rebuild()


# --- Data ------------------------------------------------------------------------------------

func refresh() -> void:
	if _fetching or offline_preview:
		return
	for p: Array in _pings:
		(p[0] as ServerList.Ping).cancel()
	_pings.clear()
	_ping_queue.clear()
	_entries.clear()
	_fetching = true
	_set_status("Asking the server list at %s…" % ServerList.master_url(), UiTheme.ACCENT)
	_list_client.fetch()
	_lan.browse()
	_rebuild()


## Gallery / tests: show these entries instead of fetching.
func show_entries(entries: Array, status := "") -> void:
	_entries = entries.duplicate(true)
	_rebuild()
	_set_status(status if status != "" else "%d servers" % _entries.size(), UiTheme.TEXT_DIM)


## The merged list as currently known (tests).
func entries() -> Array:
	return _entries


func _on_listed(servers: Array, error: String) -> void:
	_fetching = false
	for s: Dictionary in servers:
		_merge(s)
	if error != "":
		_set_status(error + "\nServers on your network still appear below.", UiTheme.DANGER)
	else:
		_set_status("%d public server%s online." % [servers.size(), "" if servers.size() == 1 else "s"] if not servers.is_empty() \
				else "No public servers right now. Host one, or try again later.", UiTheme.TEXT_DIM)
	_rebuild()


func _on_lan(entry: Dictionary) -> void:
	_merge(entry)
	_rebuild()


## Adds an entry unless the same server is known; a LAN sighting wins over the
## internet listing of the same server (closer address).
func _merge(e: Dictionary) -> void:
	var key := "%s|%d" % [String(e.get("name", "")).to_lower(), int(e.get("port", 0))]
	for i in _entries.size():
		var o: Dictionary = _entries[i]
		if "%s|%d" % [String(o.get("name", "")).to_lower(), int(o.get("port", 0))] == key:
			if e.get("source") == "lan" and o.get("source") != "lan":
				e["ping"] = -1.0
				_entries[i] = e
				_ping_queue.append(e)
			return
	e["ping"] = -1.0
	_entries.append(e)
	_ping_queue.append(e)


## This build's network protocol (looked up at runtime: no autoload dependency).
static func protocol() -> int:
	var net := UiContext.net()
	return int(net.get_script().get_script_constant_map().get("PROTOCOL_VERSION", 0)) if net != null else 0


static func compatible(e: Dictionary) -> bool:
	return int(e.get("protocol", 0)) == protocol()


## Filtered and sorted view of `entries` (static so tests can check it).
static func visible_entries(entries: Array, search: String, hide_full: bool, hide_incompatible: bool, hide_locked: bool,
		sort_key: String, desc: bool) -> Array:
	var q := search.strip_edges().to_lower()
	var out: Array = []
	for e: Dictionary in entries:
		if q != "" and not (String(e.get("name", "")).to_lower().contains(q) or String(e.get("description", "")).to_lower().contains(q) \
				or String(e.get("mode", "")).to_lower().contains(q)):
			continue
		if hide_full and int(e.get("players", 0)) >= int(e.get("max_players", 1)):
			continue
		if hide_incompatible and not compatible(e):
			continue
		if hide_locked and bool(e.get("password", false)):
			continue
		out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var va: Variant = a.get(sort_key, 0)
		var vb: Variant = b.get(sort_key, 0)
		if sort_key == "ping":  # unknown / failed pings last either way
			va = float(va) if float(va) >= 0.0 else 1e9
			vb = float(vb) if float(vb) >= 0.0 else 1e9
		elif va is String:
			va = (va as String).to_lower()
			vb = String(vb).to_lower()
		elif va is bool:
			va = 1 if va else 0
			vb = 1 if vb else 0
		if va == vb:
			return String(a.get("name", "")).to_lower() < String(b.get("name", "")).to_lower()
		return va > vb if desc else va < vb)
	return out


func _sort_by(col: int) -> void:
	if _sort_col == col:
		_sort_desc = not _sort_desc
	else:
		_sort_col = col
		_sort_desc = col == 3  # players: most first; everything else ascending
	UiContext.sound("ui_click")
	_update_headers()
	_rebuild()


func _update_headers() -> void:
	for i in _headers.size():
		var base: String = COLS[i][0]
		_headers[i].text = base + ((" ▼" if _sort_desc else " ▲") if i == _sort_col else "")


func _rebuild() -> void:
	if _list == null:
		return
	var had_focus := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var focus_key := ""
	for r: Array in _rows:
		if r[0] == had_focus:
			focus_key = _key(r[1])
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()
	var shown := visible_entries(_entries, _search.text, _hide_full.button_pressed, _hide_incompatible.button_pressed,
			_hide_locked.button_pressed, SORT_KEYS[_sort_col], _sort_desc)
	var i := 0
	for e: Dictionary in shown:
		var row := _row(e, i)
		_list.add_child(row)
		_rows.append([row, e])
		if focus_key != "" and _key(e) == focus_key:
			row.grab_focus.call_deferred()
		i += 1
	if shown.is_empty():
		var empty := UiTheme.label("—" if not _fetching else "…", UiTheme.SIZE_BODY, UiTheme.TEXT_FAINT, HORIZONTAL_ALIGNMENT_CENTER)
		empty.custom_minimum_size = Vector2(0, 60)
		_list.add_child(empty)
	_join_button.disabled = shown.is_empty()


static func _key(e: Dictionary) -> String:
	return "%s|%s|%d" % [e.get("name", ""), e.get("ip", ""), int(e.get("port", 0))]


func _row(e: Dictionary, index: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 34)
	b.focus_mode = Control.FOCUS_ALL
	var base := UiTheme.flat(Color(1, 1, 1, 0.03 if index % 2 == 0 else 0.0), 0)
	var lit := UiTheme.flat(UiTheme.BG_HOVER, 0)
	lit.border_color = UiTheme.ACCENT
	lit.border_width_left = 2
	b.add_theme_stylebox_override("normal", base)
	b.add_theme_stylebox_override("hover", lit)
	b.add_theme_stylebox_override("focus", lit)
	b.add_theme_stylebox_override("pressed", lit)
	var ok := compatible(e)
	var dim := UiTheme.TEXT if ok else UiTheme.TEXT_FAINT
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.add_theme_constant_override("separation", 0)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var full := int(e.get("players", 0)) >= int(e.get("max_players", 1))
	var ping := float(e.get("ping", -1.0))
	var ping_text := "…" if ping == -1.0 else ("—" if ping < 0.0 else "%d ms" % roundi(ping))
	var ping_col := UiTheme.TEXT_FAINT if ping < 0.0 else (UiTheme.GOOD if ping < 80.0 else (UiTheme.ACCENT if ping < 160.0 else UiTheme.DANGER))
	var name_text := String(e.get("name", "?"))
	if e.get("source") == "lan":
		name_text += "   · LAN"
	elif e.get("verified") is bool and not e.get("verified"):
		name_text += "   · unverified"
	var version := String(e.get("version", ""))
	var cells := [
		["", UiTheme.ACCENT],
		[name_text, dim],
		[String(e.get("mode", "")), UiTheme.TEXT_DIM],
		["%d / %d" % [int(e.get("players", 0)), int(e.get("max_players", 0))], UiTheme.DANGER if full else dim],
		[ping_text, ping_col],
		[(version if version != "" else "p%d" % int(e.get("protocol", 0))) + ("" if ok else "  ✕"), UiTheme.GOOD if ok else UiTheme.DANGER],
	]
	for i in cells.size():
		var l := UiTheme.label(String(cells[i][0]), UiTheme.SIZE_BODY, cells[i][1])
		l.custom_minimum_size = Vector2(COLS[i][1], 34)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i == 0 and e.get("password", false):
			var icon := LockIcon.new()
			icon.position = Vector2(9, 9)
			l.add_child(icon)
		h.add_child(l)
	b.add_child(h)
	var desc := String(e.get("description", ""))
	b.tooltip_text = "%s\n%s%s" % [e.get("name", ""), desc + "\n" if desc != "" else "", "Region: %s" % e.get("region", "") if String(e.get("region", "")) != "" else ""]
	b.focus_entered.connect(func() -> void:
		_selected = e
		UiContext.sound("ui_hover"))
	b.pressed.connect(func() -> void:
		_selected = e
		_join(e))
	return b


# --- Joining ------------------------------------------------------------------------------

func _join_selected() -> void:
	if _selected.is_empty() and not _rows.is_empty():
		_selected = _rows[0][1]
	if not _selected.is_empty():
		_join(_selected)


func _join(e: Dictionary, password := "") -> void:
	if _joining:
		return
	if not compatible(e):
		_set_status("That server runs a different version of Burn (protocol %d, you have %d)." % [int(e.get("protocol", 0)), protocol()], UiTheme.DANGER)
		return
	if int(e.get("players", 0)) >= int(e.get("max_players", 1)):
		_set_status("That server is full.", UiTheme.DANGER)
		return
	if bool(e.get("password", false)) and password == "":
		_show_password(e)
		return
	join_entry(e, password)


## Connects to a listed server through Net's normal host-authoritative join.
func join_entry(e: Dictionary, password := "") -> void:
	var net := UiContext.net()
	if net == null:
		return
	_joining = true
	_selected = e
	var ip := String(e.get("ip", ""))
	var addr := ("[%s]:%d" if ip.contains(":") else "%s:%d") % [ip, int(e.get("port", 0))]
	_set_status("Crossing over to %s…" % e.get("name", addr), UiTheme.ACCENT_HOT)
	net.call("join_address", addr, str(UiContext.setting("gameplay", "player_name")), PackedInt32Array(), password)


func _on_join_status(state: String) -> void:
	if state == "joined":
		_set_status("Joined. Entering the world…", UiTheme.GOOD)
		# Public servers start at once; one still in its lobby gets the lobby screen.
		get_tree().create_timer(2.5).timeout.connect(func() -> void:
			if is_inside_tree() and _joining and bool(UiContext.call_on(UiContext.net(), "is_online", [], false)) \
					and (UiContext.net().get("session_info") as Dictionary).is_empty():
				UiContext.game_call("open_lobby_join"))


func _on_join_failed(reason: String) -> void:
	if not _joining:
		if _overlay == null:
			_set_status(reason, UiTheme.DANGER)
		return
	_joining = false
	_set_status(reason, UiTheme.DANGER)
	UiContext.sound("ui_back")
	if reason.contains("password") and not _selected.is_empty():
		_show_password(_selected, reason)


# --- Overlays (password, direct connect, host) ----------------------------------------------

func _open_overlay(title: String, subtitle: String) -> VBoxContainer:
	_close_overlay()
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(UiTheme.scrim(0.6))
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(c)
	var panel := MenuPanel.new(title)
	panel.subtitle = subtitle
	panel.custom_minimum_size = Vector2(560, 0)
	c.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	add_child(_overlay)
	_overlay_focus = get_viewport().gui_get_focus_owner()
	UiContext.sound("ui_open")
	return box


func _close_overlay() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
		var f := _overlay_focus if _overlay_focus != null and is_instance_valid(_overlay_focus) else _join_button
		f.grab_focus.call_deferred()


func _field(box: Control, label: String, edit: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := UiTheme.label(label, UiTheme.SIZE_BODY, UiTheme.TEXT_DIM)
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	box.add_child(row)


func _buttons(box: Control, ok_text: String, ok: Callable) -> MenuOption:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var b := _action(row, ok_text, ok, 220)
	_action(row, "CANCEL", _close_overlay, 160)
	box.add_child(row)
	return b


func _show_password(e: Dictionary, note := "") -> void:
	var box := _open_overlay("LOCKED FIRE", String(e.get("name", "")))
	if note != "":
		var l := UiTheme.label(note, UiTheme.SIZE_BODY, UiTheme.DANGER, HORIZONTAL_ALIGNMENT_CENTER)
		box.add_child(l)
	var pw := LineEdit.new()
	pw.secret = true
	pw.max_length = 64
	pw.placeholder_text = "password"
	_field(box, "Password", pw)
	var go := func() -> void:
		if pw.text == "":
			return
		var p := pw.text
		_close_overlay()
		join_entry(e, p)
	pw.text_submitted.connect(func(_t: String) -> void: go.call())
	_buttons(box, "JOIN", go)
	pw.grab_focus.call_deferred()


func _show_direct() -> void:
	var box := _open_overlay("DIRECT CONNECT", "an address your host shared: ip or ip:port")
	var addr := LineEdit.new()
	addr.max_length = 100
	addr.placeholder_text = "203.0.113.7:47211"
	_field(box, "Address", addr)
	var pw := LineEdit.new()
	pw.secret = true
	pw.max_length = 64
	pw.placeholder_text = "only if the server has one"
	_field(box, "Password", pw)
	var go := func() -> void:
		var a := addr.text.strip_edges()
		if a == "":
			return
		_close_overlay()
		_joining = true
		_selected = {}
		_set_status("Connecting to %s…" % a, UiTheme.ACCENT_HOT)
		UiContext.call_on(UiContext.net(), "join_address", [a, str(UiContext.setting("gameplay", "player_name")), PackedInt32Array(), pw.text])
	addr.text_submitted.connect(func(_t: String) -> void: go.call())
	pw.text_submitted.connect(func(_t: String) -> void: go.call())
	_buttons(box, "CONNECT", go)
	addr.grab_focus.call_deferred()


func _show_host() -> void:
	var box := _open_overlay("HOST PUBLIC SERVER", "anyone can find and join; you play while they do")
	var player := str(UiContext.setting("gameplay", "player_name", "Wanderer"))
	var name_e := LineEdit.new()
	name_e.max_length = 48
	var saved_name := str(UiContext.setting("online", "server_name", ""))
	name_e.text = saved_name if saved_name != "" else "%s's fire" % player
	_field(box, "Server name", name_e)
	var desc_e := LineEdit.new()
	desc_e.max_length = 160
	desc_e.text = str(UiContext.setting("online", "server_description", ""))
	desc_e.placeholder_text = "what you are up to (optional)"
	_field(box, "Description", desc_e)
	var max_o := OptionButton.new()
	for n in range(2, 9):
		max_o.add_item("%d players" % n, n)
	max_o.select(clampi(int(UiContext.setting("online", "max_players", 8)), 2, 8) - 2)
	_field(box, "Max players", max_o)
	var pw := LineEdit.new()
	pw.secret = true
	pw.max_length = 64
	pw.placeholder_text = "empty = open to everyone"
	_field(box, "Password", pw)
	var run_o := OptionButton.new()
	run_o.add_item("A new world", -1)
	var slots: Variant = UiContext.game_call("save_slots", [], [])
	if slots is Array:
		for s: Dictionary in slots:
			if s.get("exists", false):
				run_o.add_item("Run %d — %s, rank %d" % [int(s["slot"]) + 1, s.get("name", "?"), int(s.get("rank", 0))], int(s["slot"]))
	if FileAccess.file_exists(SaveSystem.path(9)):
		run_o.add_item("The warband world", 9)
	if FileAccess.file_exists(SaveSystem.path(7)):
		run_o.add_item("Your last public world", 7)
	run_o.select(run_o.item_count - 1 if run_o.item_count > 1 else 0)
	_field(box, "Run", run_o)
	var internet := CheckBox.new()
	internet.text = "List on the internet (also always listed on your network)"
	internet.button_pressed = true
	box.add_child(internet)
	var note := UiTheme.label("Your UDP port 47211 must be reachable: the game asks your router (UPnP), or forward it yourself.",
			UiTheme.SIZE_SMALL, UiTheme.TEXT_FAINT, HORIZONTAL_ALIGNMENT_CENTER)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(note)
	var go := func() -> void:
		var n := name_e.text.strip_edges()
		if n == "":
			n = "%s's fire" % player
		UiContext.set_setting("online", "server_name", n)
		UiContext.set_setting("online", "server_description", desc_e.text.strip_edges())
		UiContext.set_setting("online", "max_players", max_o.get_selected_id())
		var cfg := {"name": n, "description": desc_e.text.strip_edges(), "max_players": max_o.get_selected_id(),
			"password": pw.text, "mode": "Campaign", "lan": true, "internet": internet.button_pressed,
			"slot": run_o.get_selected_id()}
		_close_overlay()
		_set_status("Lighting the fire…", UiTheme.ACCENT_HOT)
		if not bool(UiContext.game_call("host_public", [cfg], false)):
			_set_status("Could not open a port to host (another program may be using it).", UiTheme.DANGER)
	_buttons(box, "HOST", go)
	name_e.grab_focus.call_deferred()


# --- Navigation ------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _overlay != null:
			_close_overlay()
			UiContext.sound("ui_back")
		else:
			_back()
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_F5:
		refresh()
		get_viewport().set_input_as_handled()


func _back() -> void:
	if _joining:
		UiContext.call_on(UiContext.net(), "leave")
		_joining = false
	UiContext.sound("ui_back")
	closed.emit()
	if UiContext.game_has("show_menu") and get_parent() == get_tree().root:
		UiContext.game_call("show_menu")
	else:
		queue_free()


func _exit_tree() -> void:
	for p: Array in _pings:
		(p[0] as ServerList.Ping).cancel()
	_pings.clear()


func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


## A small padlock (fonts here have no lock glyph).
class LockIcon:
	extends Control

	func _init() -> void:
		custom_minimum_size = Vector2(12, 15)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := UiTheme.ACCENT
		draw_arc(Vector2(6, 6), 3.6, PI, TAU, 10, c, 1.6, true)
		draw_line(Vector2(2.4, 6), Vector2(2.4, 7.5), c, 1.6)
		draw_line(Vector2(9.6, 6), Vector2(9.6, 7.5), c, 1.6)
		draw_rect(Rect2(0.5, 7, 11, 7.5), c)
		draw_rect(Rect2(5.2, 9.5, 1.6, 3), Color(0.05, 0.03, 0.02))
