class_name Hud
extends CanvasLayer
## The in-game interface. Lays out every HUD widget, owns the in-game screens
## (inventory, shop, dialog, journal, map, pause, death, victory) and their
## hotkeys. GameWorld only needs to add one Hud.
##
## Layout: minimap top-left with the location / health / rank panel beside
## it, boss bar top-centre, quests top-right, toasts right, hotbar and
## abilities bottom-centre, chat on the left between minimap and hotbar,
## crosshair and prompts centre.

var root: Control
var minimap: Minimap
var status: StatusPanel
var hotbar: Hotbar
var boss_bar: BossBar
var quests: QuestTracker
var toasts: ToastFeed
var chat: ChatBox
var crosshair: Crosshair
var banner: LocationBanner
var damage_numbers: DamageNumbers

var inventory_screen: InventoryScreen
var shop_screen: ShopScreen
var dialog: DialogBox
var quest_log: QuestLogScreen
var map_screen: MapScreen
var pause_menu: PauseMenu
var death_screen: DeathScreen
var victory_screen: VictoryScreen
var perf: PerfOverlay

var _vignette_mat := ShaderMaterial.new()
var _low := 0.0
var _hit := 0.0
var _time := 0.0
var _gameplay_widgets: Array[Control] = []
var top_left: HBoxContainer


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.theme = UiTheme.theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var vignette := ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_mat.shader = preload("res://ui/shaders/damage_vignette.gdshader")
	vignette.material = _vignette_mat
	root.add_child(vignette)

	damage_numbers = DamageNumbers.new()
	root.add_child(damage_numbers)
	crosshair = Crosshair.new()
	root.add_child(crosshair)
	banner = LocationBanner.new()
	root.add_child(banner)

	top_left = HBoxContainer.new()
	top_left.position = Vector2(18, 16)
	top_left.add_theme_constant_override("separation", 14)
	top_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap = Minimap.new()
	top_left.add_child(minimap)
	status = StatusPanel.new()
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_left.add_child(status)
	root.add_child(top_left)

	boss_bar = BossBar.new()
	boss_bar.anchor_left = 0.5
	boss_bar.anchor_right = 0.5
	boss_bar.offset_left = -320
	boss_bar.offset_right = 320
	boss_bar.offset_top = 22
	boss_bar.offset_bottom = 96
	root.add_child(boss_bar)

	quests = QuestTracker.new()
	quests.anchor_left = 1.0
	quests.anchor_right = 1.0
	quests.offset_left = -(QuestTracker.WIDTH + 22)
	quests.offset_right = -22
	quests.offset_top = 20
	root.add_child(quests)

	toasts = ToastFeed.new()
	toasts.anchor_left = 1.0
	toasts.anchor_right = 1.0
	toasts.anchor_top = 0.38
	toasts.anchor_bottom = 0.75
	toasts.offset_left = -364
	toasts.offset_right = -22
	root.add_child(toasts)

	hotbar = Hotbar.new()
	hotbar.anchor_left = 0.0
	hotbar.anchor_right = 0.0
	hotbar.anchor_top = 1.0
	hotbar.anchor_bottom = 1.0
	hotbar.offset_left = 22
	hotbar.offset_right = 386
	hotbar.offset_top = -166
	hotbar.offset_bottom = -22
	root.add_child(hotbar)

	# Left side, below the minimap / status block and above the hotbar.
	chat = ChatBox.new()
	chat.anchor_top = 0.0
	chat.anchor_bottom = 1.0
	chat.offset_left = 26
	chat.offset_right = 486
	chat.offset_top = 252
	chat.offset_bottom = -192
	root.add_child(chat)
	chat.typing_changed.connect(func(on: bool) -> void:
		if not on and not any_screen_open():
			UiContext.set_ui_open(false))

	_gameplay_widgets = [crosshair, hotbar]

	inventory_screen = InventoryScreen.new()
	root.add_child(inventory_screen)
	shop_screen = ShopScreen.new()
	root.add_child(shop_screen)
	quest_log = QuestLogScreen.new()
	root.add_child(quest_log)
	map_screen = MapScreen.new()
	root.add_child(map_screen)
	dialog = DialogBox.new()
	root.add_child(dialog)
	death_screen = DeathScreen.new()
	root.add_child(death_screen)
	victory_screen = VictoryScreen.new()
	root.add_child(victory_screen)
	pause_menu = PauseMenu.new()
	root.add_child(pause_menu)

	perf = PerfOverlay.new()
	add_child(perf)

	UiContext.on("player_health_changed", func(h: float, mx: float) -> void:
		var r := h / maxf(mx, 1.0)
		if r < _last_ratio - 0.001:
			_hit = minf(1.0, _hit + 0.6 + (_last_ratio - r) * 2.0)
		_last_ratio = r
		_low = clampf((0.35 - r) / 0.35, 0.0, 1.0))
	UiContext.on("shop_open", func(_k: String) -> void: _close_screens(shop_screen))


var _last_ratio := 1.0


## True while any screen that wants the mouse is open (gameplay should not
## react to clicks or mouse look).
func _crafting_screen() -> UiModal:
	return get_tree().get_first_node_in_group(&"crafting_screen") as UiModal


func any_screen_open() -> bool:
	var craft := _crafting_screen()
	if craft != null and craft.is_open:
		return true
	return inventory_screen.is_open or shop_screen.is_open or quest_log.is_open or map_screen.is_open \
			or pause_menu.is_open or dialog.is_open or death_screen.is_open or victory_screen.is_open or chat.is_typing()


func _process(delta: float) -> void:
	_time += delta
	_hit = maxf(0.0, _hit - delta * 2.2)
	_vignette_mat.set_shader_parameter(&"low", _low)
	_vignette_mat.set_shader_parameter(&"hit", _hit)
	_vignette_mat.set_shader_parameter(&"time", _time)
	# Keep the boss bar centred but clear of the minimap / status block.
	var w := root.size.x
	var bar_w := clampf(w * 0.42, 420.0, 720.0)
	var left := maxf(w * 0.5 - bar_w * 0.5, top_left.position.x + top_left.size.x + 28.0)
	bar_w = minf(bar_w, quests.position.x - 28.0 - left) if quests.get_child_count() > 0 else minf(bar_w, w - left - 28.0)
	boss_bar.offset_left = left - w * 0.5
	boss_bar.offset_right = left + bar_w - w * 0.5
	var screens := any_screen_open() and not chat.is_typing()
	for widget in _gameplay_widgets:
		widget.modulate.a = move_toward(widget.modulate.a, 0.25 if screens else 1.0, delta * 6.0)


func _close_screens(except: Control = null) -> void:
	var screens: Array = [inventory_screen, shop_screen, quest_log, map_screen]
	var craft := _crafting_screen()
	if craft != null:
		screens.append(craft)
	for s: UiModal in screens:
		if s != except and s.is_open:
			s.close()


func _unhandled_input(event: InputEvent) -> void:
	if death_screen.is_open or victory_screen.is_open or chat.is_typing() or dialog.is_open:
		return
	if event.is_action_pressed("pause"):
		if pause_menu.is_open:
			return
		_close_screens()
		pause_menu.open()
		get_viewport().set_input_as_handled()
	elif pause_menu.is_open:
		return
	elif event.is_action_pressed("inventory"):
		_close_screens(inventory_screen)
		inventory_screen.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quests"):
		_close_screens(quest_log)
		quest_log.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map"):
		_close_screens(map_screen)
		map_screen.toggle()
		get_viewport().set_input_as_handled()
	elif not any_screen_open() and chat.is_enabled() and (event.is_action_pressed("chat") or _is_enter(event)):
		chat.open()
		get_viewport().set_input_as_handled()
	elif not any_screen_open() and chat.is_enabled() and event.is_action_pressed("chat_command"):
		chat.open("/")
		get_viewport().set_input_as_handled()


static func _is_enter(event: InputEvent) -> bool:
	var k := event as InputEventKey
	return k != null and k.pressed and not k.echo and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER)
