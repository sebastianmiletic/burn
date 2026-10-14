class_name Hotbar
extends HBoxContainer
## Bottom-centre: the three held-item slots and the ability cooldowns.

const ABILITIES := [
	["fireball", "ability_fire", "✶", "Fireball"],
	["burst", "ability_burst", "☼", "Light burst"],
	["dodge", "dodge", "»", "Dodge roll"],
	["potion", "potion", "!", "Potion"],
]

var _slots: Array[ItemSlot] = []
var _abilities := {}
var _name_label: Label
var _name_timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	alignment = BoxContainer.ALIGNMENT_CENTER
	for i in 3:
		var s := ItemSlot.new()
		s.index = i
		s.key_hint = str(i + 1)
		s.custom_minimum_size = Vector2(62, 62)
		add_child(s)
		_slots.append(s)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(22, 0)
	add_child(gap)
	for a: Array in ABILITIES:
		var w := AbilityIcon.new()
		w.glyph = a[2]
		w.action = a[1]
		w.tooltip_name = a[3]
		w.custom_minimum_size = Vector2(46, 46)
		w.size_flags_vertical = Control.SIZE_SHRINK_END
		add_child(w)
		_abilities[a[0]] = w
	_name_label = UiTheme.label("", UiTheme.SIZE_BODY, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_name_label.top_level = true
	_name_label.modulate.a = 0.0
	add_child(_name_label)

	UiContext.on("inventory_changed", refresh)
	UiContext.on("hotbar_selected", func(i: int) -> void:
		refresh()
		_show_name(i))
	UiContext.on("ability_cooldown", func(ability: String, remaining: float, total: float) -> void:
		if _abilities.has(ability):
			(_abilities[ability] as AbilityIcon).set_cooldown(remaining, total))
	refresh()


func refresh() -> void:
	var inv := UiContext.inventory()
	var sel := int(inv.get("selected")) if inv != null else 0
	for i in 3:
		var item: Dictionary = UiContext.call_on(inv, "get_slot", [i], {})
		if _slots[i].item != item:
			_slots[i].pulse()
		_slots[i].item = item.duplicate()
		_slots[i].selected = i == sel
	var potions := 0
	if inv != null:
		potions = int(UiContext.call_on(inv, "count_of", ["potion_health"], 0)) + int(UiContext.call_on(inv, "count_of", ["potion_greater"], 0))
	(_abilities["potion"] as AbilityIcon).count = potions


func _show_name(i: int) -> void:
	var inv := UiContext.inventory()
	var item: Dictionary = UiContext.call_on(inv, "get_slot", [i], {})
	_name_label.text = ItemDB.display_name(item["id"]) if not item.is_empty() else "empty hand"
	_name_timer = 1.6


func _process(delta: float) -> void:
	_name_timer -= delta
	_name_label.modulate.a = clampf(_name_timer / 0.4, 0.0, 1.0)
	if _name_label.modulate.a > 0.0:
		_name_label.size = Vector2(300, 20)
		_name_label.global_position = global_position + Vector2(_slots[1].position.x + 31 - 150, -26)


## First binding of an input action as short text ("Q", "Ctrl", "M2").
static func key_label(action: String) -> String:
	if not InputMap.has_action(action):
		return ""
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			return OS.get_keycode_string(k.physical_keycode if k.physical_keycode != 0 else k.keycode)
		if ev is InputEventMouseButton:
			return "M%d" % (ev as InputEventMouseButton).button_index
	return ""


## A square ability button with a radial cooldown sweep.
class AbilityIcon:
	extends Control

	var glyph := "?"
	var action := ""
	var tooltip_name := ""
	var count := -1:
		set(v):
			count = v
			queue_redraw()
	var _remaining := 0.0
	var _total := 1.0
	var _ready_flash := 0.0

	func set_cooldown(remaining: float, total: float) -> void:
		_remaining = remaining
		_total = maxf(total, 0.001)
		queue_redraw()

	func _process(delta: float) -> void:
		if _remaining > 0.0:
			_remaining = maxf(0.0, _remaining - delta)
			if _remaining == 0.0:
				_ready_flash = 1.0
			queue_redraw()
		if _ready_flash > 0.0:
			_ready_flash = maxf(0.0, _ready_flash - delta * 2.5)
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var usable := _remaining <= 0.0 and count != 0
		draw_rect(r, Color(0.02, 0.016, 0.015, 0.85))
		draw_rect(r.grow(-0.5), UiTheme.ACCENT_DIM if usable else UiTheme.BORDER, false, 1.0)
		var font := UiTheme.MONO_BOLD
		var fs := 20
		var gs := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var col := UiTheme.ACCENT_HOT if usable else UiTheme.TEXT_FAINT
		draw_string(font, Vector2((size.x - gs.x) * 0.5, size.y * 0.5 + fs * 0.36), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		if _remaining > 0.0:
			var f := _remaining / _total
			var c := size * 0.5
			var pts := PackedVector2Array([c])
			var steps := 24
			for i in steps + 1:
				var a := -PI * 0.5 + TAU * f * float(i) / steps
				var p := c + Vector2(cos(a), sin(a)) * size.length()
				pts.append(Vector2(clampf(p.x, 0, size.x), clampf(p.y, 0, size.y)))
			draw_colored_polygon(pts, Color(0, 0, 0, 0.6))
			var t := "%.1f" % _remaining if _remaining < 10.0 else str(int(_remaining))
			var ts := UiTheme.MONO.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
			draw_string(UiTheme.MONO, Vector2((size.x - ts.x) * 0.5, size.y - 4), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.TEXT)
		if _ready_flash > 0.0:
			draw_rect(r, Color(1, 0.7, 0.3, _ready_flash * 0.3))
		var key := Hotbar.key_label(action)
		if key.length() > 5:
			key = key.substr(0, 4)
		draw_string(UiTheme.MONO, Vector2(3, 11), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UiTheme.TEXT_FAINT)
		if count >= 0:
			var ct := str(count)
			var cs := UiTheme.MONO_BOLD.get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
			draw_string(UiTheme.MONO_BOLD, Vector2(size.x - cs.x - 3, 11), ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.TEXT if count > 0 else UiTheme.DANGER)
