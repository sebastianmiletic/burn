class_name AchievementToast
extends CanvasLayer
## "Achievement unlocked" banner sliding in at the top right. One layer under
## the tree root, shared by menus and the game; queued if several arrive.

static var _instance: AchievementToast

var _queue: Array[String] = []
var _panel: PanelContainer
var _title: Label
var _name: Label
var _desc: Label
var _t := -1.0

const SHOW := 4.2


static func show_for(id: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	if _instance == null or not is_instance_valid(_instance):
		_instance = AchievementToast.new()
		tree.root.add_child.call_deferred(_instance)
	_instance._queue.append(id)


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.035, 0.03, 0.94)
	sb.border_color = UiTheme.ACCENT
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -400
	_panel.offset_right = -24
	_panel.offset_top = 24
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_panel.add_child(box)
	_title = UiTheme.label("ACHIEVEMENT UNLOCKED", UiTheme.SIZE_SMALL, UiTheme.ACCENT_DIM)
	box.add_child(_title)
	_name = UiTheme.title("", 22, UiTheme.ACCENT_HOT, 700)
	box.add_child(_name)
	_desc = UiTheme.label("", UiTheme.SIZE_BODY, UiTheme.TEXT)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	_desc.custom_minimum_size.x = 340
	box.add_child(_desc)
	add_child(_panel)
	_panel.visible = false


func _process(delta: float) -> void:
	if _t < 0.0:
		if _queue.is_empty():
			return
		var id: String = _queue.pop_front()
		var a: Dictionary = Achievements.LIST.get(id, {})
		_name.text = String(a.get("name", id))
		_desc.text = String(a.get("desc", ""))
		_panel.visible = true
		_t = 0.0
		UiContext.sound("levelup")
	_t += delta
	var slide := clampf(minf(_t / 0.3, (SHOW - _t) / 0.4), 0.0, 1.0)
	_panel.modulate.a = slide
	_panel.offset_top = lerpf(-80.0, 24.0, slide)
	if _t >= SHOW:
		_t = -1.0
		_panel.visible = false
