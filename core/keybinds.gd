class_name Keybinds
extends RefCounted
## Input actions and their default bindings, plus rebinding support.
## Actions are registered at runtime so the project file stays minimal.

const ACTIONS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"dodge": [KEY_CTRL],
	"interact": [KEY_E],
	"attack": [MOUSE_BUTTON_LEFT],
	"use": [MOUSE_BUTTON_RIGHT],
	"ability_fire": [KEY_Q],
	"ability_burst": [KEY_R],
	"potion": [KEY_F],
	"slot_1": [KEY_1],
	"slot_2": [KEY_2],
	"slot_3": [KEY_3],
	"inventory": [KEY_TAB, KEY_I],
	"map": [KEY_M],
	"quests": [KEY_J],
	"chat": [KEY_T],
	"pause": [KEY_ESCAPE],
	"perf": [KEY_F3],
	"screenshot": [KEY_F12],
	"toggle_view": [KEY_V],
}

## Human-readable names for the settings screen.
const LABELS := {
	"move_forward": "Move forward", "move_back": "Move back", "move_left": "Move left",
	"move_right": "Move right", "jump": "Jump", "sprint": "Sprint", "dodge": "Dodge roll",
	"interact": "Interact", "attack": "Attack / mine", "use": "Use / place",
	"ability_fire": "Fireball", "ability_burst": "Light burst", "potion": "Drink potion",
	"slot_1": "Hotbar 1", "slot_2": "Hotbar 2", "slot_3": "Hotbar 3",
	"inventory": "Inventory", "map": "World map", "quests": "Quest log", "chat": "Chat",
	"pause": "Pause", "perf": "Performance overlay", "screenshot": "Screenshot", "toggle_view": "First / third person",
}


static func apply(overrides: Dictionary) -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		InputMap.action_erase_events(action)
		var codes: Array = overrides.get(action, ACTIONS[action])
		for code: int in codes:
			InputMap.action_add_event(action, _event(code))


static func reset() -> void:
	apply({})


static func rebind(action: String, code: int) -> void:
	var controls := {}
	for a: String in ACTIONS:
		controls[a] = codes_for(a)
	controls[action] = [code]
	apply(controls)
	Settings.store_controls(controls)


static func codes_for(action: String) -> Array:
	var out := []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			out.append((ev as InputEventKey).physical_keycode)
		elif ev is InputEventMouseButton:
			out.append((ev as InputEventMouseButton).button_index)
	return out


static func label_for(action: String) -> String:
	var parts := PackedStringArray()
	for code: int in codes_for(action):
		parts.append(code_name(code))
	return " / ".join(parts)


static func code_name(code: int) -> String:
	if code < 16:
		return ["", "Mouse L", "Mouse R", "Mouse M", "Wheel up", "Wheel down", "", "", "Mouse 4", "Mouse 5"][clampi(code, 0, 9)]
	return OS.get_keycode_string(code)


static func _event(code: int) -> InputEvent:
	if code < 16:
		var mb := InputEventMouseButton.new()
		mb.button_index = code as MouseButton
		return mb
	var key := InputEventKey.new()
	key.physical_keycode = code as Key
	return key
