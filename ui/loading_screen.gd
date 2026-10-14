class_name LoadingScreen
extends CanvasLayer
## Shown while a world is generated and the first chunks stream in.

const TIPS := [
	"Shrines remember you. Rest at one and the ash will return you there.",
	"Stone pickaxes cannot bite gold. Bring iron ore to a blacksmith.",
	"Ember crystals glow in the deep places, far below the roots of the world.",
	"Heavy attacks are written on the ground first. Read them, then roll.",
	"Torches are cheap. The dark is not.",
	"The Gates of Hades lie beneath the Cinder Crater. Three seals open them.",
	"Villagers trade gold for ore. Merchants trade potions for gold.",
	"Dodge rolls make you untouchable for a heartbeat. Use it.",
	"The Mountain King hates the cold less than he hates guests.",
	"Lava does not care how brave you are.",
]

var _root: Control
var _bar_fill: ColorRect
var _bar_back: ColorRect
var _status: Label
var _tip: Label
var _percent: Label
var _tip_timer := 0.0
var _progress := 0.0
var _shown := 0.0


func _ready() -> void:
	layer = 80
	_root = Control.new()
	_root.theme = UiTheme.theme()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var black := ColorRect.new()
	black.color = Color(0.01, 0.008, 0.007)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(black)
	var bg := EmberBackground.new()
	bg.intensity = 0.6
	_root.add_child(bg)

	var title := BurningTitle.new()
	title.anchor_left = 0.5
	title.anchor_right = 0.5
	title.anchor_top = 0.5
	title.anchor_bottom = 0.5
	title.offset_left = -300
	title.offset_right = 300
	title.offset_top = -210
	title.offset_bottom = -30
	title.flames = 0.6
	_root.add_child(title)

	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -320
	box.offset_right = 320
	box.offset_top = 10
	box.offset_bottom = 200
	box.add_theme_constant_override("separation", 10)
	_root.add_child(box)

	var row := HBoxContainer.new()
	_status = UiTheme.label("Kindling", UiTheme.SIZE_BODY, UiTheme.ACCENT)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_status)
	_percent = UiTheme.label("0%", UiTheme.SIZE_BODY, UiTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(_percent)
	box.add_child(row)

	var bar := Control.new()
	bar.custom_minimum_size = Vector2(640, 6)
	_bar_back = ColorRect.new()
	_bar_back.color = Color(0.2, 0.12, 0.08)
	_bar_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(_bar_back)
	_bar_fill = ColorRect.new()
	_bar_fill.color = UiTheme.ACCENT
	_bar_fill.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	bar.add_child(_bar_fill)
	box.add_child(bar)
	box.add_child(UiTheme.spacer(20))
	_tip = UiTheme.label("", UiTheme.SIZE_BODY, UiTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_tip)
	_next_tip()


func set_progress(f: float, text: String) -> void:
	_progress = clampf(f, 0.0, 1.0)
	if text != "":
		_status.text = text


func _process(delta: float) -> void:
	_shown = move_toward(_shown, _progress, delta * 1.5)
	_bar_fill.size.x = _bar_back.size.x * _shown
	_bar_fill.color = UiTheme.ACCENT.lerp(UiTheme.ACCENT_HOT, 0.5 + 0.5 * sin(Time.get_ticks_msec() / 180.0))
	_percent.text = "%d%%" % roundi(_shown * 100.0)
	_tip_timer -= delta
	if _tip_timer <= 0.0:
		_next_tip()


func _next_tip() -> void:
	_tip_timer = 6.0
	_tip.text = "“%s”" % TIPS[randi() % TIPS.size()]
