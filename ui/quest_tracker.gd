class_name QuestTracker
extends VBoxContainer
## Top-right: what you are doing. Live events (a raid, a falling star, the
## Proving Ring) first, then tracked quests with their objectives, then
## activities in progress (treasure maps, bounties).

const MAX_SHOWN := 3

var _dirty := true
var _flash := {}
var _activity_sig := ""
var _poll := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 2)
	custom_minimum_size = Vector2(300, 0)
	UiContext.on("quest_updated", func(id: String) -> void:
		_flash[id] = 1.0
		_dirty = true)
	UiContext.on("quest_completed", func(_id: String) -> void: _dirty = true)


func _process(delta: float) -> void:
	for k: String in _flash.keys():
		_flash[k] = float(_flash[k]) - delta
		if _flash[k] <= 0.0:
			_flash.erase(k)
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.4
		var sig := str(_activities())
		if sig != _activity_sig:
			_activity_sig = sig
			_dirty = true
	if _dirty:
		_dirty = false
		_rebuild()


func _activities() -> Array:
	var w := UiContext.world()
	if w == null:
		return []
	var acts := w.get_node_or_null(^"Activities")
	var out: Variant = UiContext.call_on(acts, "tracker_entries", [], [])
	return out if out is Array else []


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	var q := UiContext.quests()
	var tracked: Variant = UiContext.call_on(q, "tracked", [], [])
	var acts := _activities()
	var events: Array = acts.filter(func(e: Dictionary) -> bool: return e.get("kind", "") == "event")
	var others: Array = acts.filter(func(e: Dictionary) -> bool: return e.get("kind", "") != "event")
	var has_quests := tracked is Array and not (tracked as Array).is_empty()
	if not has_quests and acts.is_empty():
		return
	var head := UiTheme.label("QUESTS  [J]", 11, UiTheme.ACCENT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(head)
	for e: Dictionary in events:
		_entry(String(e.get("title", "")), e.get("lines", PackedStringArray()), Color(1.0, 0.55, 0.35), false)
	var shown := 0
	if has_quests:
		for quest: Dictionary in tracked:
			if shown >= MAX_SHOWN:
				break
			shown += 1
			var title := UiTheme.title(str(quest.get("title", "")), 15, UiTheme.ACCENT_HOT, 700)
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			if _flash.has(quest.get("id", "")):
				title.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
			add_child(title)
			if bool(quest.get("ready", false)):
				_line("» Return to " + str(quest.get("turn_in", "")), Color(0.6, 1.0, 0.5))
			else:
				for o: Dictionary in quest.get("objectives", []):
					var done: bool = o.get("done", false)
					var tgt := int(o.get("target", 1))
					var counter := "  %d/%d" % [int(o.get("current", 0)), tgt] if tgt > 1 else ""
					_line(("✓ " if done else "◇ ") + str(o.get("text", "")) + counter, UiTheme.TEXT_FAINT if done else UiTheme.TEXT)
			add_child(UiTheme.spacer(6))
	for e: Dictionary in others:
		_entry(String(e.get("title", "")), e.get("lines", PackedStringArray()), Color(1.0, 0.82, 0.45), true)


func _entry(title_text: String, lines: PackedStringArray, colour: Color, dim_first: bool) -> void:
	var title := UiTheme.title(title_text, 15, colour, 700)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(title)
	for i in lines.size():
		var italic := dim_first and i == 0 and lines.size() > 1
		_line(("" if italic else "◇ ") + lines[i], UiTheme.TEXT_DIM if italic else UiTheme.TEXT)
	add_child(UiTheme.spacer(6))


func _line(text: String, colour: Color) -> void:
	var line := UiTheme.label(text, 12, colour, HORIZONTAL_ALIGNMENT_RIGHT)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size.x = 300
	add_child(line)
