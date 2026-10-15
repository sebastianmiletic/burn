class_name ItemTooltip
extends Control
## Floating item card: name in its rarity colour, type and rarity, stats with
## a comparison against what you currently use (▲ better / ▼ worse), socketed
## gem, description, crafting hint and value. Positions itself next to an
## anchor rect and stays on screen.

const WIDTH := 300.0

var _box: VBoxContainer
var _anchor := Rect2()
var _id := ""


func _ready() -> void:
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50
	visible = false
	_box = VBoxContainer.new()
	_box.position = Vector2(16, 14)
	_box.custom_minimum_size = Vector2(WIDTH - 32, 0)
	_box.add_theme_constant_override("separation", 3)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)


## Shows the card for a slot dictionary ({id, count, gem}) next to `anchor`
## (global rect). `compare` is the slot it is compared with ({} = none).
func show_item(slot: Dictionary, anchor: Rect2, compare := {}) -> void:
	if slot.is_empty():
		hide_tip()
		return
	_id = String(slot["id"])
	_anchor = anchor
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_fill(slot, compare)
	visible = true
	await get_tree().process_frame
	if not is_instance_valid(self) or not visible:
		return
	size = Vector2(WIDTH, _box.get_combined_minimum_size().y + 28)
	_place()
	queue_redraw()


func hide_tip() -> void:
	visible = false
	_id = ""


func _place() -> void:
	var vp := get_viewport_rect().size
	var pos := Vector2(_anchor.end.x + 12, _anchor.position.y)
	if pos.x + size.x > vp.x - 8:
		pos.x = _anchor.position.x - size.x - 12
	pos.y = clampf(pos.y, 8, vp.y - size.y - 8)
	global_position = pos


func _label(text: String, fs: int, col: Color, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	if font != null:
		l.add_theme_font_override("font", font)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH - 32
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _rich(text: String, fs := 12) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.custom_minimum_size.x = WIDTH - 32
	r.add_theme_font_size_override("normal_font_size", fs)
	r.add_theme_font_override("normal_font", UiTheme.MONO)
	r.add_theme_font_override("bold_font", UiTheme.MONO_BOLD)
	r.add_theme_color_override("default_color", ItemStyle.TEXT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.text = text
	return r


func _fill(slot: Dictionary, compare: Dictionary) -> void:
	var id := String(slot["id"])
	var inf := ItemDB.info(id)
	var rc := ItemDB.rarity_color(id)
	_box.add_child(_label(ItemDB.display_name(id), 20, rc, ItemStyle.title_font(700)))
	var count := int(slot.get("count", 1))
	_box.add_child(_label("%s  ·  %s%s" % [ItemDB.RARITY_NAMES[ItemDB.rarity(id)], ItemDB.type_label(id), "  ·  ×%d" % count if count > 1 else ""], 11, ItemStyle.TEXT_DIM))
	_box.add_child(_spacer(4))
	var lines := stat_lines(slot, compare)
	if not lines.is_empty():
		_box.add_child(_rich("\n".join(lines), 13))
	if slot.has("gem"):
		var g := String(slot["gem"])
		_box.add_child(_rich("[color=#%s]◆ %s[/color]  [color=#%s]%s[/color]" % [ItemDB.color(g).to_html(false), ItemDB.display_name(g), ItemStyle.TEXT_DIM.to_html(false),
			ItemDB.socket_text(g, ItemDB.category(id))], 11))
	elif ItemDB.is_gear(id):
		_box.add_child(_rich("[color=#%s]◇ Empty socket — drag a gem onto this item[/color]" % ItemStyle.TEXT_FAINT.to_html(false), 11))
	if ItemDB.category(id) == "gem" or ItemDB.SOCKETS.has(id):
		_box.add_child(_rich("[color=#%s]%s[/color]" % [Color(0.75, 0.68, 0.95).to_html(false), String(ItemDB.SOCKETS.get(id, {}).get("text", ""))], 11))
	var desc := String(inf.get("desc", ""))
	if desc != "":
		_box.add_child(_spacer(2))
		_box.add_child(_label(desc, 12, Color(0.78, 0.72, 0.62)))
	var hint := _hint(id)
	if hint != "":
		_box.add_child(_label(hint, 11, ItemStyle.GOLD_DIM))
	var value := int(inf.get("value", 0))
	if value > 0:
		_box.add_child(_rich("[color=#%s]◎ %d gold[/color]" % [Color(1.0, 0.82, 0.4).to_html(false), value], 11))


func _hint(id: String) -> String:
	var inf := ItemDB.info(id)
	if inf.has("place_station"):
		return "Right-click with it in hand to place."
	if inf.has("place_block"):
		return "Right-click with it in hand to place."
	if ItemDB.category(id) == "armor":
		return "Right-click to wear."
	if inf.has("heal") or inf.has("buff"):
		return "Right-click to use."
	if ItemDB.fuel_value(id) > 0:
		return "Furnace fuel: %d unit%s." % [ItemDB.fuel_value(id), "" if ItemDB.fuel_value(id) == 1 else "s"]
	return ""


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Stat rows as bbcode, with deltas against `compare`.
static func stat_lines(slot: Dictionary, compare := {}) -> PackedStringArray:
	var id := String(slot.get("id", ""))
	var inf := ItemDB.info(id)
	var out := PackedStringArray()
	var cmp_id := String(compare.get("id", ""))
	var inv := Inventory.new()
	var a := inv.item_attack_stats(slot)
	var b := inv.item_attack_stats(compare) if cmp_id != "" else {}
	var cinf := ItemDB.info(cmp_id)
	if inf.has("damage") and ItemDB.is_gear(id) and ItemDB.category(id) != "armor":
		out.append(_row("Damage", "%.1f" % float(a["damage"]), float(a["damage"]), float(b.get("damage", -1.0)), cmp_id != ""))
		out.append(_row("Speed", "%.2f" % float(a["speed"]), float(a["speed"]), float(b.get("speed", -1.0)), cmp_id != ""))
		out.append(_row("DPS", "%.1f" % (float(a["damage"]) * float(a["speed"])), float(a["damage"]) * float(a["speed"]),
			float(b.get("damage", 0.0)) * float(b.get("speed", 0.0)), cmp_id != ""))
		out.append(_row("Reach", "%.1f m" % float(a["reach"]), float(a["reach"]), float(b.get("reach", -1.0)), cmp_id != ""))
		if float(a["burn"]) > 0.0:
			out.append(_row("Burn", "%d / s" % int(a["burn"]), float(a["burn"]), float(b.get("burn", 0.0)), cmp_id != ""))
		if bool(a.get("heavy", false)):
			out.append("[color=#%s]Heavy · staggers[/color]" % Color(0.9, 0.7, 0.45).to_html(false))
	if inf.has("mine_tier") and String(inf.get("kind", "")) == "pickaxe":
		var t := int(inf["mine_tier"])
		out.append(_row("Mining tier", "%s (%d)" % [ItemDB.MINE_TIER_LABELS[clampi(t, 0, 7)], t], float(t), float(cinf.get("mine_tier", -1)), cmp_id != "" and cinf.has("mine_tier")))
		out.append(_row("Dig speed", "×%.1f" % float(inf["mine_speed"]), float(inf["mine_speed"]), float(cinf.get("mine_speed", -1.0)), cmp_id != "" and cinf.has("mine_tier")))
		var ores := PackedStringArray()
		for k in range(1, t + 1):
			ores.append_array(ItemDB.ores_for_tier(k))
		if not ores.is_empty():
			out.append("[color=#%s]Breaks: %s[/color]" % [ItemStyle.TEXT_DIM.to_html(false), ", ".join(ores)])
	if inf.has("chop_speed"):
		out.append(_row("Chopping", "×%.1f" % float(inf["chop_speed"]), float(inf["chop_speed"]), float(cinf.get("chop_speed", -1.0)), cmp_id != "" and cinf.has("chop_speed")))
	if inf.has("defense"):
		var d := float(inf["defense"]) + float(ItemDB.socket_bonus(String(slot.get("gem", "")), "armor").get("defense", 0.0))
		var cd := float(cinf.get("defense", 0.0)) + float(ItemDB.socket_bonus(String(compare.get("gem", "")), "armor").get("defense", 0.0))
		out.append(_row("Defence", "%.1f" % d, d, cd, cmp_id != ""))
		if inf.has("fire_resist"):
			out.append(_row("Fire resist", "%d%%" % int(float(inf["fire_resist"]) * 100.0), float(inf["fire_resist"]), float(cinf.get("fire_resist", 0.0)), cmp_id != ""))
	if inf.has("heal"):
		out.append(_row("Restores", "%d health" % int(inf["heal"]), 0.0, 0.0, false))
	if inf.has("buff"):
		out.append(_row("Lasts", "%d s" % int(inf.get("buff_time", 60)), 0.0, 0.0, false))
	return out


static func _row(label: String, value: String, v: float, other: float, compare: bool) -> String:
	var s := "[color=#%s]%s[/color]  [b]%s[/b]" % [ItemStyle.TEXT_DIM.to_html(false), label.rpad(12), value]
	if compare and other >= 0.0:
		var d := v - other
		if absf(d) > 0.001:
			var good := d > 0.0
			s += "  [color=#%s]%s %s[/color]" % [(ItemStyle.GOOD if good else ItemStyle.BAD).to_html(false), "▲" if good else "▼", ("%.1f" % absf(d)).trim_suffix(".0")]
	return s


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	for i in 4:
		draw_rect(r.grow(2.0 + i * 3.0), Color(0, 0, 0, 0.1))
	ItemStyle.vgradient(self, r, Color(0.11, 0.09, 0.075, 0.98), Color(0.05, 0.04, 0.035, 0.98))
	var rc := ItemDB.rarity_color(_id) if _id != "" else ItemStyle.GOLD
	draw_texture_rect(ItemStyle.radial(), Rect2(Vector2(-size.x * 0.2, -60), Vector2(size.x * 1.4, 160)), false, Color(rc.r, rc.g, rc.b, 0.12))
	draw_texture_rect(ItemStyle.grain(), r, true, Color(1, 1, 1, 0.04))
	draw_rect(r, Color(0, 0, 0, 0.9), false, 1.0)
	draw_rect(r.grow(-2), Color(rc.r, rc.g, rc.b, 0.75), false, 1.0)
	ItemStyle.hgradient(self, Rect2(Vector2(2, 2), Vector2(size.x - 4, 2)), Color(rc.r, rc.g, rc.b, 0.0), Color(rc.r, rc.g, rc.b, 0.9))
	ItemStyle.diamond(self, Vector2(size.x * 0.5, 2), 4.0, rc)
