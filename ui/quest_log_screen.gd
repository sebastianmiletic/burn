class_name QuestLogScreen
extends UiModal
## The journal. Tabs (Main story / Side / Activities / Completed / Path), a list of
## quest cards on the left, and the selected quest on the right with its
## current objective up top (progress, distance and direction), the steps,
## the story and the rewards. Track / untrack and "show on map" buttons.
## The Path tab shows the progression ladder (QuestLog.path()) and optional hunts.
## Keys: 1-5 or Q/E tabs, up/down (W/S) select, T track, M show on map.
##
## Categories come from the quest dictionaries: `category` ("main", "side",
## "activity") when present, otherwise `main` (bool) picks main or side.

enum Tab { MAIN, SIDE, ACTIVITY, DONE, PATH }
const TAB_NAMES := ["MAIN STORY", "SIDE QUESTS", "ACTIVITIES", "COMPLETED", "PATH"]
const TAB_COUNT := 5
const EMPTY_TEXT := [
	"The story waits. Speak with Elder Maren in Emberfall.",
	"No side quests yet. Villagers with a need will ask for help.",
	"No activities under way. Look for hunts, races and contests in the villages and the wilds.",
	"Nothing finished yet.",
	"",
]
const CARD_H := 62.0

var _tab := Tab.MAIN
var _tabs: Array[TabButton] = []
var _list: VBoxContainer
var _scroll: ScrollContainer
var _cards: Array[QuestCard] = []
var _detail: VBoxContainer
var _empty: Label
var _kind: Label
var _title: Label
var _objective_box: ObjectiveBox
var _steps: VBoxContainer
var _desc: Label
var _rewards: HFlowContainer
var _rewards_head: Control
var _track_btn: Button
var _map_btn: Button
var _turn_in: Label
var _selected := ""
var _path_scroll: ScrollContainer
var _path_box: HBoxContainer
var _by_tab := [[], [], [], [], []]
var _quest := {}


func _init() -> void:
	panel_size = Vector2(1180, 720)
	panel_title = "JOURNAL"
	scrim_alpha = 0.78


func _build() -> void:
	content.add_theme_constant_override("separation", 10)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	for i in TAB_COUNT:
		var t := TabButton.new()
		t.index = i
		t.label = TAB_NAMES[i]
		t.pressed.connect(func() -> void: _set_tab(i))
		bar.add_child(t)
		_tabs.append(t)
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spring)
	var keys := UiTheme.label("1–5 tabs   ↑↓ select   T track   M map", 11, UiTheme.TEXT_FAINT)
	keys.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(keys)
	content.add_child(bar)
	var rule := ColorRect.new()
	rule.color = Color(UiTheme.BORDER, 0.6)
	rule.custom_minimum_size = Vector2(0, 1)
	content.add_child(rule)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(360, 0)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	_scroll.add_child(_list)
	body.add_child(_scroll)

	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 8)
	body.add_child(_detail)
	_kind = UiTheme.label("", 11, UiTheme.ACCENT_DIM)
	_kind.add_theme_font_override("font", UiTheme.title_font_spaced(700, 3))
	_detail.add_child(_kind)
	_title = UiTheme.title("", 28, UiTheme.ACCENT_HOT, 700)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(_title)
	_objective_box = ObjectiveBox.new()
	_detail.add_child(_objective_box)
	_turn_in = UiTheme.label("", UiTheme.SIZE_BODY, UiTheme.GOOD)
	_turn_in.visible = false
	_detail.add_child(_turn_in)
	_detail.add_child(_heading("STEPS"))
	_steps = VBoxContainer.new()
	_steps.add_theme_constant_override("separation", 3)
	_detail.add_child(_steps)
	_detail.add_child(UiTheme.spacer(2))
	_desc = UiTheme.label("", 13, UiTheme.TEXT_DIM)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(_desc)
	_rewards_head = _heading("REWARDS")
	_detail.add_child(_rewards_head)
	_rewards = HFlowContainer.new()
	_rewards.add_theme_constant_override("h_separation", 8)
	_rewards.add_theme_constant_override("v_separation", 6)
	_detail.add_child(_rewards)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_child(fill)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	_track_btn = _action_button("TRACK", _toggle_track)
	actions.add_child(_track_btn)
	_map_btn = _action_button("SHOW ON MAP", _show_on_map)
	actions.add_child(_map_btn)
	_detail.add_child(actions)
	_empty = UiTheme.label("", UiTheme.SIZE_BODY, UiTheme.TEXT_DIM)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.visible = false
	body.add_child(_empty)
	_empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_scroll = ScrollContainer.new()
	_path_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_path_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_scroll.visible = false
	_path_box = HBoxContainer.new()
	_path_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_box.add_theme_constant_override("separation", 28)
	_path_scroll.add_child(_path_box)
	body.add_child(_path_scroll)
	UiContext.on("quest_updated", func(_id: String) -> void:
		if is_open:
			_refresh())
	UiContext.on("quest_completed", func(_id: String) -> void:
		if is_open:
			_refresh())


func _heading(text: String) -> Control:
	var l := UiTheme.title(text, 12, UiTheme.ACCENT_DIM, 700)
	l.add_theme_font_override("font", UiTheme.title_font_spaced(700, 3))
	return l


func _action_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(190, 40)
	b.add_theme_font_override("font", UiTheme.title_font_spaced(700, 2))
	b.add_theme_font_size_override("font_size", 14)
	var normal := UiTheme.panel_box(Color(0.06, 0.045, 0.04, 0.9), UiTheme.BORDER, 1)
	var hover := UiTheme.panel_box(Color(0.16, 0.09, 0.04, 0.95), UiTheme.ACCENT, 1)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("disabled", UiTheme.panel_box(Color(0.04, 0.035, 0.03, 0.6), Color(UiTheme.BORDER, 0.4), 1))
	b.pressed.connect(cb)
	return b


func _on_open() -> void:
	fit_panel(panel_size, Vector2(40, 36))
	_refresh()
	# Open on the tab of the selected (or first tracked) quest.
	if _selected == "" or _tab_of(_selected) < 0:
		for t in [Tab.MAIN, Tab.SIDE, Tab.ACTIVITY]:
			if not (_by_tab[t] as Array).is_empty():
				_tab = t
				break
	else:
		_tab = _tab_of(_selected)
	_rebuild_list()


static func category_of(quest: Dictionary) -> int:
	if quest.get("completed", false):
		return Tab.DONE
	match str(quest.get("category", "")):
		"main", "story":
			return Tab.MAIN
		"side":
			return Tab.SIDE
		"activity", "activities", "event":
			return Tab.ACTIVITY
	return Tab.MAIN if quest.get("main", false) else Tab.SIDE


func _tab_of(id: String) -> int:
	for t in TAB_COUNT:
		for q: Dictionary in _by_tab[t]:
			if str(q.get("id", "")) == id:
				return t
	return -1


func _refresh() -> void:
	_by_tab = [[], [], [], [], []]
	var q := UiContext.quests()
	var active: Variant = UiContext.call_on(q, "active", [], [])
	var done: Variant = UiContext.call_on(q, "completed", [], [])
	if active is Array:
		for quest: Dictionary in active:
			var cat := category_of(quest)
			(_by_tab[Tab.SIDE if cat == Tab.DONE else cat] as Array).append(quest)
	# Activities and live events in progress (ActivityDirector.tracker_entries()).
	var w := UiContext.world()
	var acts: Node = w.get_node_or_null(^"Activities") if w != null else null
	var entries: Variant = UiContext.call_on(acts, "tracker_entries", [], [])
	if entries is Array:
		var points: Array = QuestMarkers.points(w).filter(func(pt: Dictionary) -> bool: return str(pt.get("quest_id", "")) == "")
		var i := 0
		for e: Dictionary in entries:
			i += 1
			var lines: Array = Array(e.get("lines", PackedStringArray()))
			var objectives: Array = []
			var rewards := ""
			for line: Variant in lines:
				var t := str(line)
				if t.begins_with("Reward:"):
					rewards = t.trim_prefix("Reward:").strip_edges()
				else:
					objectives.append({"text": t, "current": 0, "target": 1, "done": false})
			var title := str(e.get("title", ""))
			var aq := {"id": "act:%s" % title, "title": title, "objectives": objectives, "rewards": rewards, "category": "activity",
				"activity": true, "tracked": true, "event": e.get("kind", "") == "event",
				"description": "A live event — it will not wait for you." if e.get("kind", "") == "event" else ""}
			var m := _match_point(title, points)
			if not m.is_empty():
				aq["marker"] = {"pos": m["pos"], "dim": m["dim"], "text": m.get("text", "")}
			(_by_tab[Tab.ACTIVITY] as Array).append(aq)
	if done is Array:
		for quest: Dictionary in done:
			var d := quest.duplicate()
			d["completed"] = true
			(_by_tab[Tab.DONE] as Array).append(d)
	# Tracked first, then the rest in their given order.
	for t in 3:
		(_by_tab[t] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return bool(a.get("tracked", false)) and not bool(b.get("tracked", false)))
	(_by_tab[Tab.DONE] as Array).reverse()
	for t in TAB_COUNT:
		_tabs[t].count = (_by_tab[t] as Array).size()
	var steps: Variant = UiContext.call_on(q, "path", [], [])
	_tabs[Tab.PATH].count = (steps as Array).filter(func(s: Dictionary) -> bool: return s.get("state", "") == "done").size() if steps is Array else 0
	_rebuild_list()


## The activity map point that best matches an activity title (shared words).
static func _match_point(title: String, points: Array) -> Dictionary:
	var words := {}
	for wd in title.to_lower().replace(":", " ").split(" ", false):
		if wd.length() > 3:
			words[wd] = true
	var best: Dictionary = {}
	var best_n := 0
	for pt: Dictionary in points:
		var n := 0
		for wd in str(pt.get("text", "")).to_lower().replace(":", " ").split(" ", false):
			if words.has(wd):
				n += 1
		if n > best_n:
			best_n = n
			best = pt
	if best.is_empty() and points.size() == 1:
		best = points[0]
	return best


## Where a journal entry points: its own marker (activities) or the quest's.
static func marker_of(quest: Dictionary) -> Dictionary:
	if quest.has("marker"):
		return quest["marker"]
	if quest.get("activity", false):
		return {}
	return QuestMarkers.of(UiContext.world(), str(quest.get("id", "")))


func _set_tab(t: int) -> void:
	if t == _tab:
		return
	_tab = t
	UiContext.sound("ui_click")
	var list: Array = _by_tab[t]
	_selected = str(list[0].get("id", "")) if not list.is_empty() else ""
	_rebuild_list()


func _rebuild_list() -> void:
	for t in TAB_COUNT:
		_tabs[t].selected = t == _tab
	_path_scroll.visible = _tab == Tab.PATH
	if _tab == Tab.PATH:
		_scroll.visible = false
		_detail.visible = false
		_empty.visible = false
		_quest = {}
		_build_path()
		return
	for c in _list.get_children():
		c.queue_free()
	_cards.clear()
	var list: Array = _by_tab[_tab]
	var found := false
	for quest: Dictionary in list:
		if str(quest.get("id", "")) == _selected:
			found = true
	if not found:
		_selected = str(list[0].get("id", "")) if not list.is_empty() else ""
	for quest: Dictionary in list:
		var card := QuestCard.new()
		card.quest = quest
		card.screen = self
		card.selected = str(quest.get("id", "")) == _selected
		var id := str(quest.get("id", ""))
		card.pressed.connect(func() -> void: _select(id))
		_list.add_child(card)
		_cards.append(card)
	_show(_selected)


## The Path tab: the progression ladder (QuestLog.path()) on the left, the
## optional boss contracts (QuestLog.optional_path()) on the right.
func _build_path() -> void:
	for c in _path_box.get_children():
		_path_box.remove_child(c)
		c.queue_free()
	var q := UiContext.quests()
	var steps: Variant = UiContext.call_on(q, "path", [], [])
	var extras: Variant = UiContext.call_on(q, "optional_path", [], [])
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.6
	left.add_theme_constant_override("separation", 2)
	left.add_child(_heading("THE PATH"))
	if steps is Array:
		for s: Dictionary in steps:
			left.add_child(_path_row(s))
	_path_box.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	right.add_child(_heading("OPTIONAL HUNTS"))
	var any := false
	if extras is Array:
		for e: Dictionary in extras:
			var st := str(e.get("state", "locked"))
			if st == "locked":
				continue
			any = true
			var mark: String = {"done": "✓", "active": "▶", "available": "!"}.get(st, "·")
			var col: Color = UiTheme.TEXT_FAINT if st == "done" else (UiTheme.ACCENT_HOT if st == "active" else UiTheme.TEXT)
			right.add_child(UiTheme.label("%s  %s" % [mark, str(e.get("title", ""))], 15, col))
			var sub := "Defeated" if st == "done" else ("In your journal" if st == "active" else "Ask " + str(e.get("giver", "")))
			var l := UiTheme.label("     %s  ·  gear: %s" % [sub, str(e.get("tier", ""))], 12, UiTheme.TEXT_DIM)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			right.add_child(l)
	if not any:
		var l := UiTheme.label("Rumours of other monsters will reach you as your name grows.", 13, UiTheme.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right.add_child(l)
	_path_box.add_child(right)


func _path_row(s: Dictionary) -> Control:
	var st := str(s.get("state", "locked"))
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var mark: String = {"done": "✓", "current": "▶", "next": "◇"}.get(st, "·")
	var col: Color = {"done": UiTheme.TEXT_FAINT, "current": UiTheme.ACCENT_HOT, "next": UiTheme.TEXT}.get(st, Color(UiTheme.TEXT_FAINT, 0.6))
	var head := HBoxContainer.new()
	var t := UiTheme.label("%s  %s" % [mark, str(s.get("title", ""))], 16 if st == "current" else 14, col)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	if st != "locked":
		head.add_child(UiTheme.label(str(s.get("tier", "")), 12, UiTheme.ACCENT_DIM if st != "done" else UiTheme.TEXT_FAINT, HORIZONTAL_ALIGNMENT_RIGHT))
	row.add_child(head)
	if st == "current" or st == "next":
		var h := UiTheme.label("     " + str(s.get("hint", "")), 12, UiTheme.TEXT_DIM)
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(h)
	return row


func _select(id: String) -> void:
	if id == _selected:
		return
	_selected = id
	UiContext.sound("ui_hover")
	for c in _cards:
		c.selected = str(c.quest.get("id", "")) == id
		c.queue_redraw()
	_show(id)


func _show(id: String) -> void:
	var list: Array = _by_tab[_tab]
	_quest = {}
	for quest: Dictionary in list:
		if str(quest.get("id", "")) == id:
			_quest = quest
	var empty := _quest.is_empty()
	_detail.visible = not empty
	_empty.visible = empty
	_scroll.visible = not list.is_empty()
	if empty:
		_empty.text = EMPTY_TEXT[_tab]
		return
	var done: bool = _quest.get("completed", false)
	var cat := category_of(_quest)
	var kinds := ["MAIN STORY", "SIDE QUEST", "ACTIVITY", "COMPLETED"]
	_kind.text = ("LIVE EVENT" if _quest.get("event", false) else kinds[cat]) + ("" if done or _quest.get("activity", false) else ("  ·  TRACKED" if _quest.get("tracked", false) else ""))
	_title.text = str(_quest.get("title", ""))
	_title.add_theme_color_override("font_color", UiTheme.TEXT_DIM if done else UiTheme.ACCENT_HOT)
	_objective_box.screen = self
	_objective_box.quest = _quest
	_objective_box.visible = not done
	var ready: bool = _quest.get("ready", false)
	_turn_in.visible = ready and str(_quest.get("turn_in", "")) != ""
	_turn_in.text = "✓  All done — return to %s." % str(_quest.get("turn_in", ""))
	for c in _steps.get_children():
		c.queue_free()
	for o: Dictionary in _quest.get("objectives", []):
		var tgt := int(o.get("target", 1))
		var od: bool = o.get("done", false) or done
		var line := UiTheme.label("%s  %s%s" % ["✓" if od else "◇", o.get("text", ""), "   %d / %d" % [mini(int(o.get("current", 0)), tgt), tgt] if tgt > 1 else ""],
				13, UiTheme.TEXT_FAINT if od else UiTheme.TEXT)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_steps.add_child(line)
	_desc.text = str(_quest.get("description", ""))
	for c in _rewards.get_children():
		c.queue_free()
	var rewards := str(_quest.get("rewards", "")).replace(" · ", ", ")
	var parts := rewards.split(", ", false)
	_rewards_head.visible = not parts.is_empty()
	for p in parts:
		_rewards.add_child(_chip(p.strip_edges(), done))
	_track_btn.visible = not done and not _quest.get("activity", false)
	_track_btn.text = "UNTRACK   [T]" if _quest.get("tracked", false) else "TRACK   [T]"
	var marker := marker_of(_quest)
	_map_btn.visible = not done
	_map_btn.disabled = marker.is_empty()
	_map_btn.text = "SHOW ON MAP   [M]"
	_map_btn.tooltip_text = "" if not marker.is_empty() else "This step has no single place on the map."


func _chip(text: String, faded: bool) -> Control:
	var p := PanelContainer.new()
	var sb := UiTheme.panel_box(Color(0.1, 0.07, 0.04, 0.9), Color(0.55, 0.4, 0.2, 0.8), 1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	var lower := text.to_lower()
	var col := Color(1, 0.85, 0.5)
	if lower.ends_with("xp"):
		col = Color(0.75, 0.9, 1.0)
	elif lower.ends_with("gold"):
		col = Color(1, 0.82, 0.3)
	if faded:
		col = col.darkened(0.45)
	p.add_child(UiTheme.label(text, 13, col))
	return p


func _toggle_track() -> void:
	if _quest.is_empty() or _quest.get("completed", false) or _quest.get("activity", false):
		return
	var id := str(_quest.get("id", ""))
	var on := not bool(_quest.get("tracked", false))
	UiContext.call_on(UiContext.quests(), "set_tracked", [id, on])
	UiContext.emit_event("quest_updated", [id])
	UiContext.sound("ui_click")
	_selected = id
	_refresh()


func _show_on_map() -> void:
	var marker := marker_of(_quest)
	if marker.is_empty():
		return
	var map: MapScreen = null
	for c in get_parent().get_children():
		if c is MapScreen:
			map = c
	if map == null:
		return
	close()
	map.focus_on(marker["pos"], 4.0)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo:
		var handled := true
		match k.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				_set_tab(k.keycode - KEY_1)
			KEY_Q:
				_set_tab(posmod(_tab - 1, TAB_COUNT))
			KEY_E, KEY_TAB:
				_set_tab(posmod(_tab + 1, TAB_COUNT))
			KEY_UP, KEY_W:
				_step(-1)
			KEY_DOWN, KEY_S:
				_step(1)
			KEY_T:
				_toggle_track()
			KEY_M:
				_show_on_map()
			_:
				handled = false
		if handled:
			get_viewport().set_input_as_handled()
			return
	super(event)


func _step(d: int) -> void:
	var list: Array = _by_tab[_tab]
	if list.is_empty():
		return
	var i := 0
	for j in list.size():
		if str(list[j].get("id", "")) == _selected:
			i = j
	i = clampi(i + d, 0, list.size() - 1)
	_select(str(list[i].get("id", "")))
	if i < _cards.size():
		_scroll.ensure_control_visible(_cards[i])


func _process(_delta: float) -> void:
	if is_open and _objective_box.visible:
		_objective_box.queue_redraw()
		for c in _cards:
			c.queue_redraw()


## Distance / direction to a quest's marker: {"metres", "bearing", "text"} or {}.
func nav_to(quest: Dictionary) -> Dictionary:
	var world := UiContext.world()
	var player := UiContext.player()
	var m := marker_of(quest)
	if m.is_empty() or player == null:
		return {}
	var pdim: Variant = player.get("dimension")
	if pdim != null and int(pdim) != int(m.get("dim", 0)):
		return {"metres": -1.0, "text": ["Overworld", "Underworld", "the Ryft"][clampi(int(m.get("dim", 0)), 0, 2)]}
	var off: Vector3 = (m["pos"] as Vector3) - (player as Node3D).global_position
	var flat := Vector2(off.x, off.z).length()
	var yaw := float(UiContext.call_on(world, "camera_yaw", [], player.get("yaw") if player.get("yaw") != null else 0.0))
	var bearing := atan2(off.x, -off.z) + yaw
	return {"metres": flat, "bearing": bearing, "text": "%s  ·  %s" % [QuestMarkers.distance_text(flat), QuestMarkers.compass(off)],
		"label": str(m.get("text", ""))}


## The first unfinished objective of a quest (or {}).
static func current_objective(quest: Dictionary) -> Dictionary:
	for o: Dictionary in quest.get("objectives", []):
		if not o.get("done", false):
			return o
	return {}


## Draws a small arrow pointing `bearing` radians clockwise from up.
static func draw_arrow(ci: CanvasItem, at: Vector2, bearing: float, s: float, col: Color) -> void:
	var pts := PackedVector2Array([Vector2(0, -1.1), Vector2(0.75, 0.75), Vector2(0, 0.38), Vector2(-0.75, 0.75)])
	for i in pts.size():
		pts[i] = at + pts[i].rotated(bearing) * s
	ci.draw_colored_polygon(pts, col)
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, col, 1.0, true)


# --- Widgets ------------------------------------------------------------------------------

## A tab: spaced Cinzel caption with its count, amber underline when selected.
class TabButton:
	extends Button

	var index := 0
	var label := ""
	var count := 0:
		set(v):
			count = v
			queue_redraw()
	var selected := false:
		set(v):
			selected = v
			queue_redraw()

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(150, 38)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for s in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			add_theme_stylebox_override(s, StyleBoxEmpty.new())
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var hover := is_hovered()
		var f := UiTheme.title_font_spaced(700, 2)
		var col := UiTheme.ACCENT_HOT if selected else (UiTheme.TEXT if hover else UiTheme.TEXT_DIM)
		if selected:
			draw_rect(Rect2(0, 0, size.x, size.y), Color(1, 0.62, 0.22, 0.07))
			draw_rect(Rect2(0, size.y - 2, size.x, 2), UiTheme.ACCENT)
		var text := label
		var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		var cs := UiTheme.MONO_BOLD.get_string_size(str(count), HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		var total := ts.x + 8 + cs.x + 10
		var x := (size.x - total) * 0.5
		draw_string(f, Vector2(x, size.y * 0.5 + 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
		var badge := Rect2(x + ts.x + 8, size.y * 0.5 - 8, cs.x + 10, 16)
		draw_rect(badge, Color(UiTheme.ACCENT, 0.18 if count > 0 else 0.06))
		draw_string(UiTheme.MONO_BOLD, badge.position + Vector2(5, 12), str(count), HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				UiTheme.ACCENT_HOT if count > 0 else UiTheme.TEXT_FAINT)


## One quest in the list: title, its current step, distance, tracked pin.
class QuestCard:
	extends Button

	var quest := {}
	var screen: QuestLogScreen
	var selected := false

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(340, CARD_H)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for s in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			add_theme_stylebox_override(s, StyleBoxEmpty.new())
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var hover := is_hovered()
		var done: bool = quest.get("completed", false)
		var bg := Color(1, 0.62, 0.22, 0.11) if selected else (Color(1, 1, 1, 0.035) if hover else Color(1, 1, 1, 0.015))
		draw_rect(Rect2(Vector2.ZERO, size), bg)
		if selected:
			draw_rect(Rect2(0, 0, 3, size.y), UiTheme.ACCENT)
		var tracked: bool = quest.get("tracked", false)
		var tf := UiTheme.title_font(700)
		var title_col := UiTheme.TEXT_DIM if done else (UiTheme.ACCENT_HOT if selected else UiTheme.TEXT)
		var right := 14.0
		var nav: Dictionary = {} if done or screen == null else screen.nav_to(quest)
		if not nav.is_empty() and float(nav.get("metres", -1.0)) >= 0.0:
			var dt := QuestMarkers.distance_text(float(nav["metres"]))
			var ds := UiTheme.MONO.get_string_size(dt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
			draw_string(UiTheme.MONO, Vector2(size.x - 14 - ds.x, 22), dt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.TEXT_DIM)
			QuestLogScreen.draw_arrow(self, Vector2(size.x - 24 - ds.x, 18), float(nav["bearing"]), 5.0, MapIcons.QUEST if tracked else UiTheme.TEXT_DIM)
			right = 40.0 + ds.x
		if tracked and not done:
			MapIcons.draw_glyph(self, &"quest", Vector2(18, 20), 7.0, MapIcons.QUEST, Color(0, 0, 0, 0.8))
		elif done:
			draw_string(UiTheme.MONO_BOLD, Vector2(12, 25), "✓", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.GOOD.darkened(0.2))
		else:
			draw_arc(Vector2(18, 20), 4.0, 0, TAU, 16, UiTheme.TEXT_FAINT, 1.0, true)
		var title := str(quest.get("title", ""))
		draw_string(tf, Vector2(34, 26), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 34 - right, 16, title_col)
		var sub := ""
		if done:
			sub = "Completed"
		elif quest.get("ready", false):
			sub = "Return to " + str(quest.get("turn_in", "the quest giver"))
		else:
			var o := QuestLogScreen.current_objective(quest)
			if not o.is_empty():
				sub = str(o.get("text", ""))
				if int(o.get("target", 1)) > 1:
					sub += "  %d/%d" % [int(o.get("current", 0)), int(o.get("target", 1))]
		draw_string(UiTheme.MONO, Vector2(34, 47), sub, HORIZONTAL_ALIGNMENT_LEFT, size.x - 48, 12,
				UiTheme.GOOD if quest.get("ready", false) else UiTheme.TEXT_DIM)


## The prominent "current objective" panel with progress and a compass arrow.
class ObjectiveBox:
	extends Control

	var screen: QuestLogScreen
	var quest := {}:
		set(v):
			quest = v
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(0, 96)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.09, 0.06, 0.035, 0.85))
		draw_rect(Rect2(0, 0, 3, size.y), UiTheme.ACCENT)
		draw_rect(r, Color(UiTheme.ACCENT_DIM, 0.6), false, 1.0)
		var head := UiTheme.title_font_spaced(700, 3)
		draw_string(head, Vector2(18, 22), "CURRENT OBJECTIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.ACCENT_DIM)
		var o := QuestLogScreen.current_objective(quest)
		var text := str(o.get("text", "All steps done"))
		if quest.get("ready", false):
			text = "Return to " + str(quest.get("turn_in", "the quest giver"))
		var nav: Dictionary = screen.nav_to(quest) if screen != null else {}
		var text_w := size.x - 36.0 - (190.0 if not nav.is_empty() else 0.0)
		draw_string(UiTheme.title_font(700), Vector2(18, 52), text, HORIZONTAL_ALIGNMENT_LEFT, text_w, 19, Color(0.97, 0.93, 0.85))
		var tgt := int(o.get("target", 1))
		if tgt > 1 and not quest.get("ready", false):
			var cur := mini(int(o.get("current", 0)), tgt)
			var bar := Rect2(18, 66, minf(text_w, 320.0), 6)
			draw_rect(bar, Color(0.2, 0.12, 0.07))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(cur) / tgt, bar.size.y)), UiTheme.ACCENT)
			draw_string(UiTheme.MONO_BOLD, Vector2(bar.end.x + 10, 73), "%d / %d" % [cur, tgt], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.TEXT)
		elif nav.is_empty():
			draw_string(UiTheme.MONO, Vector2(18, 76), "No single place on the map for this step.", HORIZONTAL_ALIGNMENT_LEFT, text_w, 11, UiTheme.TEXT_FAINT)
		if not nav.is_empty():
			var c := Vector2(size.x - 150, size.y * 0.5 + 4)
			if float(nav.get("metres", -1.0)) >= 0.0:
				draw_circle(c, 22, Color(0, 0, 0, 0.45), true, -1.0, true)
				draw_arc(c, 22, 0, TAU, 32, Color(UiTheme.ACCENT_DIM, 0.8), 1.0, true)
				QuestLogScreen.draw_arrow(self, c, float(nav["bearing"]), 12.0, MapIcons.QUEST)
				var parts := str(nav["text"]).split("  ·  ")
				draw_string(UiTheme.MONO_BOLD, c + Vector2(34, -3), parts[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiTheme.TEXT)
				if parts.size() > 1:
					draw_string(UiTheme.MONO, c + Vector2(34, 15), parts[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.TEXT_DIM)
			else:
				draw_string(UiTheme.MONO, c + Vector2(-30, 4), "In " + str(nav.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.TEXT_DIM)
