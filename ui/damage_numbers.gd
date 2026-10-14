class_name DamageNumbers
extends Control
## Floating numbers from Events.damage_number, anchored to world positions
## and projected through GameWorld.view each frame.

const LIFETIME := 1.1
const COLORS := {
	"hit": Color(1.0, 0.86, 0.6),
	"crit": Color(1.0, 0.95, 0.4),
	"heal": Color(0.55, 0.95, 0.5),
	"player": Color(1.0, 0.32, 0.25),
	"fire": Color(1.0, 0.5, 0.15),
}

var _items: Array = []  # [Vector3 pos, text, colour, size, age, drift]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiContext.on("damage_number", add)


func add(pos: Vector3, amount: int, crit: bool, kind := "hit") -> void:
	var color: Color = COLORS.get("crit" if crit and kind == "hit" else kind, COLORS["hit"])
	var size_px := 18 if crit else (13 if kind == "player" else 15)
	var drift := Vector2(randf_range(-18, 18), 0)
	_items.append([pos, format(amount, crit, kind), color, size_px, 0.0, drift])
	if _items.size() > 60:
		_items.pop_front()


static func format(amount: int, crit: bool, kind: String) -> String:
	var t := str(absi(amount))
	if kind == "heal":
		t = "+" + t
	elif kind == "player":
		t = "-" + t
	if crit:
		t += "!"
	return t


func _process(delta: float) -> void:
	for i in range(_items.size() - 1, -1, -1):
		_items[i][4] += delta
		if _items[i][4] >= LIFETIME:
			_items.remove_at(i)
	queue_redraw()


func _draw() -> void:
	var world := UiContext.world()
	if world == null:
		return
	var view: Variant = world.get("view")
	var cam := get_viewport().get_camera_3d()
	for it: Array in _items:
		var pos: Vector3 = it[0]
		var screen := Vector2(-1, -1)
		if view is Object and (view as Object).has_method("unproject"):
			var src: Variant = (view as Object).get("source_camera")
			if src is Camera3D and (src as Camera3D).is_position_behind(pos):
				continue
			screen = (view as Object).call("unproject", pos)
		elif cam != null and not cam.is_position_behind(pos):
			screen = cam.unproject_position(pos)
		else:
			continue
		var age: float = it[4]
		var t := age / LIFETIME
		var rise := -46.0 * (1.0 - pow(1.0 - t, 2.0))
		var pop := 1.0 + maxf(0.0, 0.35 - age) * 1.4
		var fs := int(float(it[3]) * pop)
		var alpha := clampf((1.0 - t) * 2.2, 0.0, 1.0)
		var font := UiTheme.MONO_BOLD
		var text: String = it[1]
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var drift: Vector2 = it[5]
		var p: Vector2 = screen + drift * t + Vector2(-ts.x * 0.5, rise)
		var col: Color = it[2]
		draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8 * alpha))
		draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.r, col.g, col.b, alpha))
