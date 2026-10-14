class_name ToastFeed
extends VBoxContainer
## Right-side stacked notifications from Events.notify(text, kind).

const LIFETIME := 4.5
const MAX_TOASTS := 6
const STYLES := {
	"info": [UiTheme.TEXT, UiTheme.BORDER, "·"],
	"loot": [Color(0.95, 0.85, 0.55), UiTheme.ACCENT_DIM, "+"],
	"quest": [UiTheme.ACCENT_HOT, UiTheme.ACCENT, "◆"],
	"warn": [Color(1.0, 0.55, 0.45), UiTheme.DANGER, "!"],
	"rank": [Color(1.0, 0.9, 0.6), UiTheme.ACCENT_HOT, "▲"],
}

var _toasts: Array = []  # [PanelContainer, age]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 4)
	custom_minimum_size = Vector2(340, 0)
	UiContext.on("notify", push)


func push(text: String, kind := "info") -> void:
	var style: Array = STYLES.get(kind, STYLES["info"])
	# Merge repeated loot lines ("+1 Stone" x5) into one.
	for t: Array in _toasts:
		var p: PanelContainer = t[0]
		if p.get_meta("text", "") == text and t[1] < LIFETIME - 0.3:
			t[1] = 0.0
			var n := int(p.get_meta("count", 1)) + 1
			p.set_meta("count", n)
			(p.get_meta("label") as Label).text = "%s  %s  ×%d" % [style[2], text, n]
			return
	var panel := PanelContainer.new()
	var box := UiTheme.panel_box(Color(0.03, 0.025, 0.022, 0.88), style[1])
	box.border_width_top = 0
	box.border_width_bottom = 0
	box.border_width_right = 0
	box.border_width_left = 2
	box.set_content_margin_all(6)
	box.content_margin_left = 10
	panel.add_theme_stylebox_override("panel", box)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiTheme.label("%s  %s" % [style[2], text], 13, style[0])
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 320
	panel.add_child(l)
	panel.set_meta("text", text)
	panel.set_meta("label", l)
	panel.modulate.a = 0.0
	add_child(panel)
	_toasts.append([panel, 0.0])
	while _toasts.size() > MAX_TOASTS:
		(_toasts.pop_front()[0] as Node).queue_free()


func _process(delta: float) -> void:
	for i in range(_toasts.size() - 1, -1, -1):
		var t: Array = _toasts[i]
		t[1] += delta
		var p: PanelContainer = t[0]
		var age: float = t[1]
		p.modulate.a = clampf(age / 0.2, 0.0, 1.0) * clampf((LIFETIME - age) / 0.6, 0.0, 1.0)
		if age >= LIFETIME:
			p.queue_free()
			_toasts.remove_at(i)
