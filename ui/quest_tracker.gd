class_name QuestTracker
extends VBoxContainer
## Top-right: tracked quests with their objectives.

const MAX_SHOWN := 3

var _dirty := true
var _flash := {}


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
	if _dirty:
		_dirty = false
		_rebuild()


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	var q := UiContext.quests()
	var tracked: Variant = UiContext.call_on(q, "tracked", [], [])
	if not (tracked is Array) or (tracked as Array).is_empty():
		return
	var head := UiTheme.label("QUESTS  [J]", 11, UiTheme.ACCENT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(head)
	var shown := 0
	for quest: Dictionary in tracked:
		if shown >= MAX_SHOWN:
			break
		shown += 1
		var title := UiTheme.title(str(quest.get("title", "")), 15, UiTheme.ACCENT_HOT, 700)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if _flash.has(quest.get("id", "")):
			title.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
		add_child(title)
		for o: Dictionary in quest.get("objectives", []):
			var done: bool = o.get("done", false)
			var tgt := int(o.get("target", 1))
			var counter := "  %d/%d" % [int(o.get("current", 0)), tgt] if tgt > 1 else ""
			var line := UiTheme.label(("✓ " if done else "◇ ") + str(o.get("text", "")) + counter, 12,
					UiTheme.TEXT_FAINT if done else UiTheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.custom_minimum_size.x = 300
			add_child(line)
		add_child(UiTheme.spacer(6))
