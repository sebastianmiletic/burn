class_name Keybinds
extends RefCounted
## Input actions and their default bindings, plus rebinding support.
## Actions are registered at runtime so the project file stays minimal.
##
## Every action has up to two keyboard / mouse bindings (primary, secondary)
## and one controller binding. Bindings are stored as ints in Settings'
## "controls" section: "<action>" -> [key or mouse codes] (as in older
## settings files) and "pad_<action>" -> [controller code].
## Codes: < 16 mouse button, < PAD_BUTTON physical key, PAD_BUTTON + button,
## PAD_AXIS + axis * 2 (+1 for the positive direction).

const PAD_BUTTON := 1 << 29
const PAD_AXIS := 1 << 30
const KEY_SLOTS := 2

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
	"chat_command": [KEY_SLASH],
	"pause": [KEY_ESCAPE],
	"perf": [KEY_F3],
	"screenshot": [KEY_F12],
	"toggle_view": [KEY_V],
}

## Controller defaults (Xbox layout names; other pads map to the same positions).
const PAD := {
	"move_forward": [PAD_AXIS + JOY_AXIS_LEFT_Y * 2],
	"move_back": [PAD_AXIS + JOY_AXIS_LEFT_Y * 2 + 1],
	"move_left": [PAD_AXIS + JOY_AXIS_LEFT_X * 2],
	"move_right": [PAD_AXIS + JOY_AXIS_LEFT_X * 2 + 1],
	"jump": [PAD_BUTTON + JOY_BUTTON_A],
	"sprint": [PAD_BUTTON + JOY_BUTTON_LEFT_STICK],
	"dodge": [PAD_BUTTON + JOY_BUTTON_B],
	"interact": [PAD_BUTTON + JOY_BUTTON_X],
	"attack": [PAD_AXIS + JOY_AXIS_TRIGGER_RIGHT * 2 + 1],
	"use": [PAD_AXIS + JOY_AXIS_TRIGGER_LEFT * 2 + 1],
	"ability_fire": [PAD_BUTTON + JOY_BUTTON_RIGHT_SHOULDER],
	"ability_burst": [PAD_BUTTON + JOY_BUTTON_LEFT_SHOULDER],
	"potion": [PAD_BUTTON + JOY_BUTTON_Y],
	"slot_1": [PAD_BUTTON + JOY_BUTTON_DPAD_LEFT],
	"slot_2": [PAD_BUTTON + JOY_BUTTON_DPAD_UP],
	"slot_3": [PAD_BUTTON + JOY_BUTTON_DPAD_RIGHT],
	"inventory": [PAD_BUTTON + JOY_BUTTON_BACK],
	"map": [PAD_BUTTON + JOY_BUTTON_DPAD_DOWN],
	"pause": [PAD_BUTTON + JOY_BUTTON_START],
	"toggle_view": [PAD_BUTTON + JOY_BUTTON_RIGHT_STICK],
}

## Human-readable names for the settings screen.
const LABELS := {
	"move_forward": "Move forward", "move_back": "Move back", "move_left": "Move left",
	"move_right": "Move right", "jump": "Jump", "sprint": "Sprint", "dodge": "Dodge roll",
	"interact": "Interact", "attack": "Attack / mine", "use": "Use / place",
	"ability_fire": "Fireball", "ability_burst": "Light burst", "potion": "Drink potion",
	"slot_1": "Hotbar 1", "slot_2": "Hotbar 2", "slot_3": "Hotbar 3",
	"inventory": "Inventory", "map": "World map", "quests": "Quest log", "chat": "Chat", "chat_command": "Chat command (/)",
	"pause": "Pause", "perf": "Performance overlay", "screenshot": "Screenshot", "toggle_view": "First / third person",
}

const PAD_BUTTON_NAMES := {
	JOY_BUTTON_A: "A / Cross", JOY_BUTTON_B: "B / Circle", JOY_BUTTON_X: "X / Square", JOY_BUTTON_Y: "Y / Triangle",
	JOY_BUTTON_BACK: "View / Select", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Menu / Start",
	JOY_BUTTON_LEFT_STICK: "Left stick press", JOY_BUTTON_RIGHT_STICK: "Right stick press",
	JOY_BUTTON_LEFT_SHOULDER: "LB / L1", JOY_BUTTON_RIGHT_SHOULDER: "RB / R1",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down", JOY_BUTTON_DPAD_LEFT: "D-pad left",
	JOY_BUTTON_DPAD_RIGHT: "D-pad right", JOY_BUTTON_MISC1: "Share / Capture",
}
const PAD_AXIS_NAMES := ["Left stick", "Left stick", "Right stick", "Right stick", "LT / L2", "RT / R2"]


static func apply(overrides: Dictionary) -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		InputMap.action_erase_events(action)
		for code: int in key_codes(action, overrides):
			InputMap.action_add_event(action, _event(code))
		for code: int in pad_codes(action, overrides):
			InputMap.action_add_event(action, _event(code))


## Keyboard / mouse codes for an action from saved overrides (or defaults).
static func key_codes(action: String, overrides: Dictionary) -> Array:
	var out := []
	for code: Variant in overrides.get(action, ACTIONS.get(action, [])):
		if (code is int or code is float) and int(code) > 0 and int(code) < PAD_BUTTON:
			out.append(int(code))
	return out


static func pad_codes(action: String, overrides: Dictionary) -> Array:
	var out := []
	for code: Variant in overrides.get("pad_" + action, PAD.get(action, [])):
		if (code is int or code is float) and int(code) >= PAD_BUTTON:
			out.append(int(code))
	return out


static func reset() -> void:
	apply({})


## Current bindings of every action in the stored form.
static func current() -> Dictionary:
	var controls := {}
	for a: String in ACTIONS:
		var keys := []
		var pads := []
		for code: int in codes_for(a):
			if code >= PAD_BUTTON:
				pads.append(code)
			else:
				keys.append(code)
		controls[a] = keys
		controls["pad_" + a] = pads
	return controls


## Binds `code` to `action`: keyboard slot `index` (0 primary, 1 secondary)
## or, for controller codes, the controller slot. code 0 clears the slot.
## Another action already using the code gets this action's old binding in
## exchange (or loses it). Returns the action it was taken from ("" if none).
static func set_binding(action: String, index: int, code: int, pad := false) -> String:
	var controls := current()
	var key := ("pad_" + action) if pad else action
	var mine: Array = controls[key]
	var old := 0
	var slot := 0 if pad else clampi(index, 0, KEY_SLOTS - 1)
	if slot < mine.size():
		old = int(mine[slot])
	var taken := ""
	if code != 0:
		for a: String in ACTIONS:
			var other_key := ("pad_" + a) if pad else a
			if a == action:
				continue
			var list: Array = controls[other_key]
			var at := list.find(code)
			if at >= 0:
				taken = a
				if old != 0 and not list.has(old):
					list[at] = old
				else:
					list.remove_at(at)
		var dup := mine.find(code)
		if dup >= 0 and dup != slot:
			mine.remove_at(dup)
			if dup < slot:
				slot -= 1
	if code == 0:
		if slot < mine.size():
			mine.remove_at(slot)
	elif slot < mine.size():
		mine[slot] = code
	else:
		mine.append(code)
	apply(controls)
	Settings.store_controls(controls)
	return taken


## Older entry point: makes `code` the only keyboard / mouse binding.
static func rebind(action: String, code: int) -> void:
	var controls := current()
	controls[action] = [code]
	apply(controls)
	Settings.store_controls(controls)


## Restores one action's defaults (keys and controller).
static func reset_action(action: String) -> void:
	var controls := current()
	controls[action] = (ACTIONS[action] as Array).duplicate()
	controls["pad_" + action] = (PAD.get(action, []) as Array).duplicate()
	apply(controls)
	Settings.store_controls(controls)


static func codes_for(action: String) -> Array:
	var out := []
	if not InputMap.has_action(action):
		return out
	for ev in InputMap.action_get_events(action):
		var code := event_code(ev)
		if code != 0:
			out.append(code)
	return out


## The code a pressed input event would bind (0: not bindable).
static func event_code(ev: InputEvent) -> int:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		return int(k.physical_keycode) if k.physical_keycode != 0 else int(k.keycode)
	if ev is InputEventMouseButton:
		return int((ev as InputEventMouseButton).button_index)
	if ev is InputEventJoypadButton:
		return PAD_BUTTON + int((ev as InputEventJoypadButton).button_index)
	if ev is InputEventJoypadMotion:
		var m := ev as InputEventJoypadMotion
		return PAD_AXIS + int(m.axis) * 2 + (1 if m.axis_value > 0.0 else 0)
	return 0


static func key_list(action: String) -> Array:
	return codes_for(action).filter(func(c: int) -> bool: return c < PAD_BUTTON)


static func pad_list(action: String) -> Array:
	return codes_for(action).filter(func(c: int) -> bool: return c >= PAD_BUTTON)


static func label_for(action: String) -> String:
	var parts := PackedStringArray()
	for code: int in key_list(action):
		parts.append(code_name(code))
	return " / ".join(parts)


static func code_name(code: int) -> String:
	if code <= 0:
		return "—"
	if code >= PAD_AXIS:
		var axis := (code - PAD_AXIS) / 2
		var positive := (code - PAD_AXIS) % 2 == 1
		var base: String = PAD_AXIS_NAMES[axis] if axis < PAD_AXIS_NAMES.size() else "Axis %d" % axis
		if axis == JOY_AXIS_LEFT_X or axis == JOY_AXIS_RIGHT_X:
			return base + (" right" if positive else " left")
		if axis == JOY_AXIS_LEFT_Y or axis == JOY_AXIS_RIGHT_Y:
			return base + (" down" if positive else " up")
		return base
	if code >= PAD_BUTTON:
		return str(PAD_BUTTON_NAMES.get(code - PAD_BUTTON, "Button %d" % (code - PAD_BUTTON)))
	if code < 16:
		return ["", "Mouse L", "Mouse R", "Mouse M", "Wheel up", "Wheel down", "", "", "Mouse 4", "Mouse 5"][clampi(code, 0, 9)]
	return OS.get_keycode_string(code)


static func _event(code: int) -> InputEvent:
	if code >= PAD_AXIS:
		var m := InputEventJoypadMotion.new()
		m.device = -1
		m.axis = ((code - PAD_AXIS) / 2) as JoyAxis
		m.axis_value = 1.0 if (code - PAD_AXIS) % 2 == 1 else -1.0
		return m
	if code >= PAD_BUTTON:
		var b := InputEventJoypadButton.new()
		b.device = -1
		b.button_index = (code - PAD_BUTTON) as JoyButton
		return b
	if code < 16:
		var mb := InputEventMouseButton.new()
		mb.button_index = code as MouseButton
		return mb
	var key := InputEventKey.new()
	key.physical_keycode = code as Key
	return key
