class_name UiContext
extends RefCounted
## How UI reaches gameplay without hard class dependencies.
## The in-game root (GameWorld) is found through the "game_world" group;
## methods are called duck-typed so the UI also works in menus and in the
## gallery with mock objects.


static func tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func world() -> Node:
	var t := tree()
	if t == null:
		return null
	var w := t.get_first_node_in_group(&"game_world")
	if w == null:
		w = t.root.get_node_or_null("GameWorld")
	return w


static func player() -> Object:
	var w := world()
	if w == null:
		return null
	var p: Variant = w.get("local_player")
	return p if p is Object and is_instance_valid(p) else null


static func inventory() -> Object:
	var p := player()
	if p == null:
		return null
	var inv: Variant = p.get("inventory")
	return inv if inv is Object else null


static func quests() -> Object:
	var w := world()
	if w == null:
		return null
	var q: Variant = w.get("quests")
	return q if q is Object else null


## Calls `method` on `target` if it exists; returns `fallback` otherwise.
static func call_on(target: Object, method: String, args: Array = [], fallback: Variant = null) -> Variant:
	if target == null or not is_instance_valid(target) or not target.has_method(method):
		return fallback
	return target.callv(method, args)


static func world_call(method: String, args: Array = [], fallback: Variant = null) -> Variant:
	return call_on(world(), method, args, fallback)


static func game_call(method: String, args: Array = [], fallback: Variant = null) -> Variant:
	var t := tree()
	var game: Node = t.root.get_node_or_null("Game") if t != null else null
	return call_on(game, method, args, fallback)


static func game_has(method: String) -> bool:
	var t := tree()
	var game: Node = t.root.get_node_or_null("Game") if t != null else null
	return game != null and game.has_method(method)


static func net() -> Node:
	var t := tree()
	return t.root.get_node_or_null("Net") if t != null else null


static func sound(name: String) -> void:
	var t := tree()
	var audio: Node = t.root.get_node_or_null("Audio") if t != null else null
	if audio != null and audio.has_method("play_ui"):
		audio.call("play_ui", name)


## Tell gameplay a menu opened/closed so it frees or recaptures the mouse.
static func set_ui_open(open: bool) -> void:
	var w := world()
	if w != null and w.has_method("set_ui_open"):
		w.call("set_ui_open", open)
	elif open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- Autoloads by path, so ui/ compiles even where autoloads aren't registered ---

static func autoload(name: String) -> Node:
	var t := tree()
	return t.root.get_node_or_null(name) if t != null else null


## Connects to a signal on the Events bus.
static func on(signal_name: String, callable: Callable) -> void:
	var ev := autoload("Events")
	if ev != null and ev.has_signal(signal_name):
		ev.connect(signal_name, callable)


static func emit_event(signal_name: String, args: Array = []) -> void:
	var ev := autoload("Events")
	if ev != null and ev.has_signal(signal_name):
		ev.callv("emit_signal", [signal_name] + args)


static func setting(section: String, key: String, fallback: Variant = null) -> Variant:
	var s := autoload("Settings")
	if s == null:
		return fallback
	var v: Variant = s.call("get_value", section, key)
	return fallback if v == null else v


static func set_setting(section: String, key: String, value: Variant) -> void:
	var s := autoload("Settings")
	if s != null:
		s.call("set_value", section, key, value)


## A constant array from the Settings script (option names).
static func settings_const(name: String) -> Array:
	var s := autoload("Settings")
	var v: Variant = s.get(name) if s != null else null
	return v if v is Array else []
