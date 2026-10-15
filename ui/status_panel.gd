class_name StatusPanel
extends VBoxContainer
## Sits to the right of the minimap: where you are, your health and rank,
## and a coordinates / depth / time line.

var _title: Label
var _subtitle: Label
var _health: StatBar
var _rank: StatBar
var _info: Label
var _detail: Label
var _poll := 0.0
var _rank_index := 0
# Location vs. "what you are looking at" (look_info): the block cross-fades.
var _loc := ["Unknown Lands", ""]
var _look := ["", "", ""]
var _showing_look := false
var _fade := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 3)
	custom_minimum_size = Vector2(300, 0)
	_title = UiTheme.title("Unknown Lands", 19, UiTheme.ACCENT_HOT, 700)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = 300
	add_child(_title)
	_subtitle = UiTheme.label("", UiTheme.SIZE_SMALL, UiTheme.TEXT_DIM)
	add_child(_subtitle)
	_detail = UiTheme.label("", 11, UiTheme.TEXT_FAINT)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size.x = 300
	_detail.visible = false
	add_child(_detail)
	add_child(UiTheme.spacer(4))
	_health = StatBar.new()
	_health.caption = "HP"
	_health.custom_minimum_size = Vector2(300, 16)
	add_child(_health)
	_rank = StatBar.new()
	_rank.caption = "RK"
	_rank.fill_color = UiTheme.ACCENT
	_rank.trail_color = UiTheme.ACCENT_HOT
	_rank.custom_minimum_size = Vector2(300, 14)
	_rank.bar_height = 6.0
	_rank.segment = 4.0
	add_child(_rank)
	add_child(UiTheme.spacer(2))
	_info = UiTheme.label("", 11, UiTheme.TEXT_FAINT)
	add_child(_info)

	UiContext.on("location_changed", _on_location)
	UiContext.on("look_info", _on_look)
	UiContext.on("player_health_changed", func(h: float, mx: float) -> void: _health.set_values(h, mx))
	UiContext.on("xp_changed", _on_xp)
	_health.set_values(100, 100, true)
	_on_xp(0, 0, 0.0)


func _on_location(title: String, subtitle: String, _first: bool) -> void:
	_loc = [title, subtitle]
	if not _showing_look:
		_title.text = title
		_subtitle.text = subtitle


## The player's crosshair rested on something (title "" = looked away).
func _on_look(title: String, subtitle: String, detail: String) -> void:
	_look = [title, subtitle, detail]


func _wants_look() -> bool:
	return _look[0] != ""


func _apply_text() -> void:
	_showing_look = _wants_look()
	if _showing_look:
		_title.text = _look[0]
		_subtitle.text = _look[1]
		_detail.text = _look[2]
		_title.add_theme_color_override("font_color", Color(0.96, 0.93, 0.86))
		_subtitle.add_theme_color_override("font_color", UiTheme.ACCENT)
	else:
		_title.text = _loc[0]
		_subtitle.text = _loc[1]
		_detail.text = ""
		_title.add_theme_color_override("font_color", UiTheme.ACCENT_HOT)
		_subtitle.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_detail.visible = _detail.text != ""


func _on_xp(xp: int, rank: int, into: float) -> void:
	_rank_index = rank
	var title: String = ItemDB.RANK_TITLES[clampi(rank, 0, ItemDB.RANK_TITLES.size() - 1)]
	_rank.right_text = "%s · %s xp" % [title, UiTheme.format_int(xp)]
	_rank.numbers_width = 150.0
	_rank.set_values(into, 1.0)


func _process(delta: float) -> void:
	# Cross-fade: fade out, swap text, fade back in (also when the looked-at thing changes).
	var stale: bool = _wants_look() != _showing_look or (_showing_look and (_title.text != _look[0] or _subtitle.text != _look[1] or _detail.text != _look[2]))
	if stale:
		_fade = move_toward(_fade, 0.0, delta * 7.0)
		if _fade <= 0.0:
			_apply_text()
	else:
		_fade = move_toward(_fade, 1.0, delta * 5.0)
	_title.modulate.a = _fade
	_subtitle.modulate.a = _fade
	_detail.modulate.a = _fade
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.25
	var world := UiContext.world()
	var player := UiContext.player()
	if world == null or player == null:
		_info.text = ""
		return
	var p := (player as Node3D).global_position
	var parts := PackedStringArray()
	parts.append("%d, %d" % [roundi(p.x), roundi(p.z)])
	var surface: Variant = UiContext.call_on(world, "surface_height_at", [p.x, p.z], null)
	if surface != null:
		var below := float(surface) - p.y
		if below > 3.0:
			parts.append("depth %dm" % roundi(below))
		else:
			parts.append("alt %dm" % roundi(p.y))
	else:
		parts.append("alt %dm" % roundi(p.y))
	var tod: Variant = UiContext.call_on(world, "time_of_day", [], null)
	if tod != null:
		var day: Variant = UiContext.call_on(world, "day", [], 1)
		parts.append("day %d · %s %s" % [int(day), UiTheme.clock(float(tod)), _sky_word(float(tod))])
	_info.text = "  ·  ".join(parts)


static func _sky_word(h: float) -> String:
	if h < 5.0 or h >= 21.0:
		return "☾"
	if h < 7.5:
		return "dawn"
	if h < 18.0:
		return "☀"
	return "dusk"
