class_name QuestLogScreen
extends UiModal
## Quest journal: active and completed quests on the left, details right.

var _list: VBoxContainer
var _title: Label
var _desc: Label
var _objectives: VBoxContainer
var _rewards: Label
var _track: CheckBox
var _selected := ""
var _quests := {}


func _init() -> void:
	panel_size = Vector2(900, 560)
	panel_title = "JOURNAL"


func _build() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 0)
	scroll.add_child(_list)
	row.add_child(scroll)
	var sep := VSeparator.new()
	row.add_child(sep)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	_title = UiTheme.title("", 24, UiTheme.ACCENT_HOT, 700)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD
	right.add_child(_title)
	_desc = UiTheme.label("", UiTheme.SIZE_BODY, UiTheme.TEXT)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	_desc.custom_minimum_size.x = 480
	right.add_child(_desc)
	right.add_child(UiTheme.label("OBJECTIVES", UiTheme.SIZE_SMALL, UiTheme.ACCENT_DIM))
	_objectives = VBoxContainer.new()
	right.add_child(_objectives)
	right.add_child(UiTheme.label("REWARDS", UiTheme.SIZE_SMALL, UiTheme.ACCENT_DIM))
	_rewards = UiTheme.label("", UiTheme.SIZE_BODY, Color(1, 0.85, 0.5))
	_rewards.autowrap_mode = TextServer.AUTOWRAP_WORD
	right.add_child(_rewards)
	var spring := Control.new()
	spring.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spring)
	_track = CheckBox.new()
	_track.text = "Track on screen"
	_track.toggled.connect(func(on: bool) -> void:
		if _selected != "":
			UiContext.call_on(UiContext.quests(), "set_tracked", [_selected, on])
			UiContext.emit_event("quest_updated", [_selected]))
	right.add_child(_track)
	UiContext.on("quest_updated", func(_id: String) -> void:
		if is_open:
			_refresh())


func _on_open() -> void:
	_refresh()


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	_quests.clear()
	var q := UiContext.quests()
	var active: Array = UiContext.call_on(q, "active", [], [])
	var done: Array = UiContext.call_on(q, "completed", [], [])
	_section("ACTIVE  (%d)" % active.size(), active, false)
	_list.add_child(UiTheme.spacer(10))
	_section("COMPLETED  (%d)" % done.size(), done, true)
	if _selected == "" or not _quests.has(_selected):
		_selected = str(active[0]["id"]) if not active.is_empty() else (str(done[0]["id"]) if not done.is_empty() else "")
	_show(_selected)


func _section(title: String, quests: Array, completed: bool) -> void:
	_list.add_child(UiTheme.label(title, UiTheme.SIZE_SMALL, UiTheme.ACCENT_DIM))
	if quests.is_empty():
		_list.add_child(UiTheme.label("  —", UiTheme.SIZE_BODY, UiTheme.TEXT_FAINT))
	for quest: Dictionary in quests:
		var id := str(quest.get("id", ""))
		_quests[id] = quest
		var b := UiTheme.button(str(quest.get("title", id)), func() -> void: _show(id))
		b.add_theme_color_override("font_color", UiTheme.TEXT_FAINT if completed else UiTheme.TEXT)
		_list.add_child(b)


func _show(id: String) -> void:
	_selected = id
	for c in _objectives.get_children():
		c.queue_free()
	if not _quests.has(id):
		_title.text = "No quests yet"
		_desc.text = "Speak with the people of Emberfall. Someone always needs a fire carried."
		_rewards.text = ""
		_track.visible = false
		return
	var quest: Dictionary = _quests[id]
	_title.text = str(quest.get("title", ""))
	_desc.text = str(quest.get("description", ""))
	for o: Dictionary in quest.get("objectives", []):
		var tgt := int(o.get("target", 1))
		var done: bool = o.get("done", false)
		var line := UiTheme.label("%s  %s%s" % ["✓" if done else "◇", o.get("text", ""), "   %d / %d" % [int(o.get("current", 0)), tgt] if tgt > 1 else ""],
				UiTheme.SIZE_BODY, UiTheme.TEXT_FAINT if done else UiTheme.TEXT)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD
		line.custom_minimum_size.x = 480
		_objectives.add_child(line)
	_rewards.text = str(quest.get("rewards", ""))
	var tracked: Variant = UiContext.call_on(UiContext.quests(), "is_tracked", [id], quest.get("tracked", false))
	_track.visible = not bool(quest.get("completed", false))
	_track.set_pressed_no_signal(bool(tracked))
