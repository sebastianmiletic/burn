extends TestCase
## Settings, keybinds (conflicts, controller) and the scripts they are wired into.


func _settings() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("Settings")


func test_wired_scripts_compile() -> void:
	for p in ["res://core/settings.gd", "res://core/keybinds.gd", "res://core/game.gd", "res://audio/audio.gd",
			"res://entities/player/player_camera.gd", "res://entities/player/player.gd", "res://ui/settings_menu.gd",
			"res://ui/main_menu.gd", "res://ui/menu/run_row.gd", "res://rendering/world_view.gd", "res://world/sky/weather.gd"]:
		var s: GDScript = load(p)
		check(s != null and s.can_instantiate(), "%s compiles" % p)


func test_rebinding_swaps_conflicts_and_keeps_controller() -> void:
	var s := _settings()
	Keybinds.reset()
	check(Keybinds.pad_list("jump").has(Keybinds.PAD_BUTTON + JOY_BUTTON_A), "controller defaults")
	check(Keybinds.pad_list("move_forward").size() == 1, "left stick moves")
	# E (interact) onto jump: jump's Space goes to interact.
	var taken := Keybinds.set_binding("jump", 0, KEY_E)
	check_eq(taken, "interact")
	check_eq(Keybinds.key_list("jump"), [KEY_E])
	check_eq(Keybinds.key_list("interact"), [KEY_SPACE], "swapped")
	Keybinds.set_binding("jump", 1, KEY_K)
	check_eq(Keybinds.key_list("jump"), [KEY_E, KEY_K], "secondary binding")
	Keybinds.set_binding("jump", 1, 0)
	check_eq(Keybinds.key_list("jump"), [KEY_E], "cleared")
	Keybinds.set_binding("dodge", 0, Keybinds.PAD_BUTTON + JOY_BUTTON_A, true)
	check(Keybinds.pad_list("dodge").has(Keybinds.PAD_BUTTON + JOY_BUTTON_A))
	check(Keybinds.pad_list("jump").has(Keybinds.PAD_BUTTON + JOY_BUTTON_B), "controller swap")
	# What is stored loads back the same.
	var stored: Dictionary = s.get("_data")["controls"]
	Keybinds.apply(stored)
	check_eq(Keybinds.key_list("interact"), [KEY_SPACE], "stored bindings reload")
	# Older files stored only key lists: controller defaults remain.
	Keybinds.apply({"jump": [KEY_SPACE]})
	check(Keybinds.pad_list("jump").has(Keybinds.PAD_BUTTON + JOY_BUTTON_A), "old controls files keep pad defaults")
	Keybinds.reset_action("jump")
	check_eq(Keybinds.key_list("jump"), [KEY_SPACE])
	s.call("reset_section", "controls")
	check_eq(Keybinds.key_list("interact"), [KEY_E], "reset")
	check_eq(Keybinds.code_name(Keybinds.PAD_AXIS + JOY_AXIS_TRIGGER_RIGHT * 2 + 1), "RT / R2")


func test_toggle_and_comfort_options() -> void:
	var s := _settings()
	check_eq(s.call("action_held", "sprint"), false)
	s.call("set_value", "accessibility", "reduce_flashing", true)
	check_near(float(s.call("flash_scale")), 0.25, 0.001)
	s.call("set_value", "accessibility", "reduce_motion", true)
	check(float(s.call("motion_scale")) < 1.0)
	s.call("reset_keys", [["accessibility", "reduce_flashing"], ["accessibility", "reduce_motion"]])
	check_near(float(s.call("flash_scale")), 1.0, 0.001)
	check_eq(Settings.parse_resolution("1600x900"), Vector2i(1600, 900))
	check_eq(Settings.parse_resolution("bad"), Vector2i.ZERO)
	check(s.get_value("display", "vsync") is int, "vsync is a mode")
