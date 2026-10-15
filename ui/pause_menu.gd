class_name PauseMenu
extends UiModal
## Esc menu. Pauses the game in solo; in a warband the world keeps running.

var _settings: SettingsMenu
var _resume: Button
var _status: Label
var _paused_tree := false
var _creative: Button
var _destinations: OptionButton
var _teleport: Button


func _init() -> void:
	panel_size = Vector2(460, 560)
	panel_title = "PAUSED"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _build() -> void:
	content.add_theme_constant_override("separation", 4)
	_resume = _entry("Resume", close)
	_entry("Settings", _open_settings)
	_creative = _entry("Creative inspection: off", _toggle_creative)
	_destinations = OptionButton.new()
	_destinations.custom_minimum_size.y = 40
	content.add_child(_destinations)
	var w := GameWorld.instance
	if w != null:
		for dim: int in w.gens:
			for loc: Location in w.locations(dim):
				if not loc.spawns_of("boss").is_empty() or loc.kind == Location.Kind.VILLAGE:
					_destinations.add_item(loc.name)
					_destinations.set_item_metadata(_destinations.item_count - 1, loc.id)
	_teleport = _entry("Teleport to selected location", _teleport_selected)
	_refresh_creative()
	_entry("Save journey", _save)
	_entry("Quit to title", func() -> void:
		_unpause()
		UiContext.game_call("quit_to_menu"))
	_entry("Quit game", func() -> void: get_tree().quit())
	content.add_child(UiTheme.spacer(8))
	_status = UiTheme.label("", UiTheme.SIZE_SMALL, UiTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	content.add_child(_status)


func _entry(text: String, cb: Callable) -> Button:
	var b := UiTheme.button(text.to_upper(), cb, 18)
	b.add_theme_font_override("font", UiTheme.title_font(600))
	b.custom_minimum_size = Vector2(0, 42)
	content.add_child(b)
	return b


func _on_open() -> void:
	var online: bool = UiContext.call_on(UiContext.net(), "is_online", [], false)
	_status.text = "The warband fights on while you rest." if online else "The world holds its breath."
	if not online:
		get_tree().paused = true
		_paused_tree = true
	_resume.grab_focus.call_deferred()


func close() -> void:
	_unpause()
	super()


func _unpause() -> void:
	if _paused_tree:
		get_tree().paused = false
		_paused_tree = false


func _refresh_creative() -> void:
	var w := GameWorld.instance
	var allowed := w != null and w.local_player != null and not Net.is_online()
	var enabled := allowed and w.local_player.creative
	_creative.disabled = not allowed
	_creative.text = "CREATIVE INSPECTION: " + ("ON" if enabled else "OFF")
	_destinations.disabled = not enabled
	_teleport.disabled = not enabled or _destinations.item_count == 0


func _toggle_creative() -> void:
	var w := GameWorld.instance
	if w == null or Net.is_online():
		return
	w.local_player.creative = not w.local_player.creative
	_refresh_creative()
	_status.text = "Invulnerable. Teleports do not unlock quests. Solo only." if w.local_player.creative else "Normal damage restored."


func _teleport_selected() -> void:
	if _destinations.selected < 0:
		return
	if GameWorld.instance.creative_teleport(_destinations.get_item_metadata(_destinations.selected)):
		close()


func _save() -> void:
	var ok: Variant = UiContext.game_call("save_game", [], null)
	_status.text = "Journey saved." if ok != false else "Only the host can save the warband's journey."


func _open_settings() -> void:
	if _settings != null:
		return
	_settings = SettingsMenu.new()
	_settings.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_settings)
	_settings.closed.connect(func() -> void:
		_settings = null
		_resume.grab_focus())


func _unhandled_input(event: InputEvent) -> void:
	if _settings != null:
		return
	if is_open and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
		return
	super(event)
