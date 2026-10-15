class_name QuestTracker
extends VBoxContainer
## Top-right: what you are doing, compact and right-aligned. Live events (a
## raid, a falling star, the Proving Ring) first, then tracked quests (title,
## current step with a counter, and a live arrow with the distance when the
## step has a place), then activities in progress (treasure maps, bounties)
## from ActivityDirector.tracker_entries() -> [{title, lines, kind}].

const MAX_SHOWN := 3
const WIDTH := 320.0

var _dirty := true
var _flash := {}
var _entries: Array[Entry] = []
var _activity_sig := ""
var _poll := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(WIDTH, 0)
	UiContext.on("quest_updated", func(id: String) -> void:
		_flash[id] = 1.2
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
	for e in _entries:
		e.flash = float(_flash.get(str(e.quest.get("id", "")), 0.0))
		e.queue_redraw()


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
	_entries.clear()
	var tracked: Variant = UiContext.call_on(UiContext.quests(), "tracked", [], [])
	var quests: Array = tracked if tracked is Array else []
	var acts := _activities()
	var events: Array = acts.filter(func(e: Dictionary) -> bool: return e.get("kind", "") == "event")
	var others: Array = acts.filter(func(e: Dictionary) -> bool: return e.get("kind", "") != "event")
	if quests.is_empty() and acts.is_empty():
		return
	add_child(Header.new())
	for e: Dictionary in events:
		_add(Entry.activity(e, Color(1.0, 0.55, 0.35), false))
	var shown := 0
	for quest: Dictionary in quests:
		if shown >= MAX_SHOWN:
			break
		shown += 1
		var e := Entry.new()
		e.quest = quest
		_add(e)
	if quests.size() > MAX_SHOWN:
		add_child(UiTheme.label("+%d more in the journal" % (quests.size() - MAX_SHOWN), 11, UiTheme.TEXT_FAINT, HORIZONTAL_ALIGNMENT_RIGHT))
	for e: Dictionary in others:
		_add(Entry.activity(e, Color(1.0, 0.82, 0.45), true))


func _add(e: Entry) -> void:
	add_child(e)
	_entries.append(e)


class Header:
	extends Control

	func _init() -> void:
		custom_minimum_size = Vector2(WIDTH, 16)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var f := UiTheme.title_font_spaced(700, 3)
		var text := "JOURNAL"
		var key := "J"
		var ks := UiTheme.MONO_BOLD.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
		var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		var x := size.x - ks.x - 12.0
		draw_rect(Rect2(x - 4, 1, ks.x + 8, 14), Color(0, 0, 0, 0.0), false)
		draw_rect(Rect2(x - 4, 1, ks.x + 8, 14), UiTheme.ACCENT_DIM, false, 1.0)
		draw_string(UiTheme.MONO_BOLD, Vector2(x, 12), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UiTheme.ACCENT)
		draw_string(f, Vector2(x - 12 - ts.x, 12), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.ACCENT_DIM)
		draw_line(Vector2(size.x - 160, 15.5), Vector2(size.x, 15.5), Color(UiTheme.BORDER, 0.5), 1.0)


## One tracked quest, right-aligned over a soft dark gradient.
class Entry:
	extends Control

	var quest := {}
	var flash := 0.0
	## Activity / event entries: a title and plain lines instead of a quest.
	var title_override := ""
	var colour := UiTheme.ACCENT_HOT
	var _lines: Array = []   # [text, done, good]

	static func activity(e: Dictionary, col: Color, dim_first: bool) -> Entry:
		var en := Entry.new()
		en.title_override = String(e.get("title", ""))
		en.colour = col
		var lines: Variant = e.get("lines", PackedStringArray())
		var arr: Array = Array(lines) if (lines is PackedStringArray or lines is Array) else []
		for i in arr.size():
			en._lines.append([str(arr[i]), dim_first and i == 0 and arr.size() > 1, false])
		return en

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		if title_override != "":
			custom_minimum_size = Vector2(WIDTH, 26 + _lines.size() * 18 + 4)
			return
		_lines.clear()
		if quest.get("ready", false):
			_lines.append(["Return to " + str(quest.get("turn_in", "the quest giver")), false, true])
		else:
			var shown := 0
			for o: Dictionary in quest.get("objectives", []):
				if o.get("done", false) or shown >= 2:
					continue
				shown += 1
				var tgt := int(o.get("target", 1))
				var counter := "  %d/%d" % [mini(int(o.get("current", 0)), tgt), tgt] if tgt > 1 else ""
				_lines.append([str(o.get("text", "")) + counter, false, false])
		custom_minimum_size = Vector2(WIDTH, 26 + _lines.size() * 18 + 20)

	func _draw() -> void:
		var w := size.x
		# Readability: a dark band fading to the left.
		var band := PackedVector2Array([Vector2(w * 0.15, 0), Vector2(w + 8, 0), Vector2(w + 8, size.y), Vector2(w * 0.15, size.y)])
		draw_polygon(band, PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.5), Color(0, 0, 0, 0.5), Color(0, 0, 0, 0)]))
		var tf := UiTheme.title_font(700)
		var title := title_override if title_override != "" else str(quest.get("title", ""))
		var col := colour.lerp(Color(1, 1, 0.92), clampf(flash, 0.0, 1.0))
		var ts := tf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		draw_string_outline(tf, Vector2(w - ts.x - 4, 19), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, 0.6))
		draw_string(tf, Vector2(w - ts.x - 4, 19), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
		if title_override == "":
			MapIcons.draw_glyph(self, &"quest", Vector2(w - ts.x - 18, 13), 6.0, MapIcons.QUEST, Color(0, 0, 0, 0.8))
		var y := 38.0
		for line: Array in _lines:
			var text: String = line[0]
			var c := UiTheme.GOOD if line[2] else (UiTheme.TEXT_DIM if line[1] else UiTheme.TEXT)
			var ls := UiTheme.MONO.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
			var x := maxf(4.0, w - ls.x - 4)
			draw_string_outline(UiTheme.MONO, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, w - 8, 13, 4, Color(0, 0, 0, 0.6))
			draw_string(UiTheme.MONO, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, w - 8, 13, c)
			y += 18.0
		# Live direction and distance to the step's place.
		var nav := _nav() if title_override == "" else {}
		if not nav.is_empty():
			var t: String = nav["text"]
			var ds := UiTheme.MONO_BOLD.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
			var ty := y - 1.0
			draw_string_outline(UiTheme.MONO_BOLD, Vector2(w - ds.x - 4, ty), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.6))
			draw_string(UiTheme.MONO_BOLD, Vector2(w - ds.x - 4, ty), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MapIcons.QUEST)
			if nav.has("bearing"):
				var at := Vector2(w - ds.x - 18, ty - 4)
				draw_circle(at, 8.0, Color(0, 0, 0, 0.55), true, -1.0, true)
				QuestLogScreen.draw_arrow(self, at, float(nav["bearing"]), 5.5, MapIcons.QUEST)

	func _nav() -> Dictionary:
		var world := UiContext.world()
		var player := UiContext.player()
		var m := QuestMarkers.of(world, str(quest.get("id", "")))
		if m.is_empty() or player == null:
			return {}
		var pdim: Variant = player.get("dimension")
		if pdim != null and int(pdim) != int(m.get("dim", 0)):
			return {"text": "in " + ["the Overworld", "the Underworld", "the Ryft"][clampi(int(m.get("dim", 0)), 0, 2)]}
		var off: Vector3 = (m["pos"] as Vector3) - (player as Node3D).global_position
		var flat := Vector2(off.x, off.z).length()
		if flat < 12.0:
			return {"text": "here"}
		var yaw := float(UiContext.call_on(world, "camera_yaw", [], player.get("yaw") if player.get("yaw") != null else 0.0))
		return {"text": QuestMarkers.distance_text(flat), "bearing": atan2(off.x, -off.z) + yaw}
