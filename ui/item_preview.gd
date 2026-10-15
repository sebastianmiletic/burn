class_name ItemPreview
extends SubViewportContainer
## A small live 3D stage for UI: shows an item turning slowly on a plinth of
## light (crafting screen), or the player's character wearing their armour
## and holding the selected item (inventory paper doll). Renders only while
## visible; does nothing on headless / dummy renderers.

enum Mode { ITEM, CHARACTER }

var mode := Mode.ITEM
var spin_speed := 0.5
var _vp: SubViewport
var _pivot: Node3D
var _cam: Camera3D
var _model: Node3D
var _key := ""
var _angle := 0.0
var _drag := false


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if not ItemIcons.available():
		return
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.48)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 1.2
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.9, 0.78)
	key.light_energy = 2.0
	key.rotation_degrees = Vector3(-35, -40, 0)
	key.shadow_enabled = true
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(1.0, 0.6, 0.3)
	rim.light_energy = 2.4
	rim.rotation_degrees = Vector3(-15, 160, 0)
	_vp.add_child(rim)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.55, 0.7, 1.0)
	fill.light_energy = 0.6
	fill.rotation_degrees = Vector3(-5, 60, 0)
	_vp.add_child(fill)
	_cam = Camera3D.new()
	_cam.fov = 24.0
	_vp.add_child(_cam)
	_cam.current = true
	_pivot = Node3D.new()
	_vp.add_child(_pivot)


func _gui_input(event: InputEvent) -> void:
	# Drag to turn the model.
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		_drag = mb.pressed
	var mm := event as InputEventMouseMotion
	if mm != null and _drag:
		_angle += mm.relative.x * 0.012


## Shows an item (ITEM mode).
func show_item(id: String) -> void:
	mode = Mode.ITEM
	if _pivot == null or id == _key:
		return
	_key = id
	_clear()
	if id == "":
		return
	var m := HeldItems.build(id, 1.0, false)
	if m == null:
		return
	var holder := Node3D.new()
	holder.add_child(m)
	if ItemIcons.pose(id) == "diagonal":
		m.rotation_degrees = Vector3(0, 0, -45)
	_pivot.add_child(holder)
	_model = holder
	var box := HeldItems._bounds(holder)
	var c := box.get_center()
	m.position -= c
	var ext := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var dist := ext * 0.5 / tan(deg_to_rad(_cam.fov * 0.5)) * 1.25
	_cam.position = Vector3(0, ext * 0.18, dist)
	_cam.look_at(Vector3.ZERO)


## Shows the player character (CHARACTER mode) wearing `equipment` and holding `held`.
func show_character(equipment: Dictionary, held: String) -> void:
	mode = Mode.CHARACTER
	if _pivot == null:
		return
	var key := "char|%s|%s" % [str(equipment), held]
	if key == _key:
		return
	_key = key
	_clear()
	var style := Models.player_style(0, false)
	var head := String(equipment.get("head", {}).get("id", ""))
	var chest := String(equipment.get("chest", {}).get("id", ""))
	var feet := String(equipment.get("feet", {}).get("id", ""))
	if head != "":
		style["helmet"] = true
		style["hood"] = false
		style["helmet_color"] = ItemDB.color(head)
	if chest != "":
		style["cloth2"] = ItemDB.color(chest).darkened(0.25)
	if feet != "":
		style["boots"] = ItemDB.color(feet).darkened(0.35)
	style["held"] = held
	var model := HumanoidModel.new(style)
	_pivot.add_child(model)
	_model = model
	# Models face -Z; turn the character towards the camera.
	model.rotation.y = PI
	_cam.position = Vector3(0, 1.1, 5.6)
	_cam.look_at(Vector3(0, 0.98, 0))


func _clear() -> void:
	if _model != null and is_instance_valid(_model):
		_model.queue_free()
	_model = null


func _process(delta: float) -> void:
	if _pivot == null or not is_visible_in_tree():
		return
	if not _drag:
		_angle += delta * spin_speed
	_pivot.rotation.y = _angle if mode == Mode.ITEM else sin(_angle * 0.6) * 0.6 + 0.35
