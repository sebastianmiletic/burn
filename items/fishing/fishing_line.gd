class_name FishingLine
extends Node3D
## The visible part of fishing, for the local angler and for everyone else's:
## a bobber (painted float with a quill) on the water and the line from the
## rod tip to it, sagging when slack and drawn tight while a fish pulls.
## Lives in world space under the GameWorld.

var bobber: Node3D
var tight := 0.0             ## 0 slack .. 1 taut
var tip := Vector3.ZERO
var _line: MeshInstance3D
var _mesh: ImmediateMesh
var _mat: StandardMaterial3D


func _ready() -> void:
	top_level = true
	bobber = Node3D.new()
	add_child(bobber)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.75, 0.1, 0.07)
	red.roughness = 0.35
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.9, 0.84)
	white.roughness = 0.4
	var quill := StandardMaterial3D.new()
	quill.albedo_color = Color(0.3, 0.22, 0.14)
	var top := MeshInstance3D.new()
	var s1 := SphereMesh.new()
	s1.radius = 0.035
	s1.height = 0.05
	s1.is_hemisphere = true
	top.mesh = s1
	top.material_override = red
	bobber.add_child(top)
	var bot := MeshInstance3D.new()
	var s2 := SphereMesh.new()
	s2.radius = 0.035
	s2.height = 0.05
	s2.is_hemisphere = true
	bot.mesh = s2
	bot.rotation_degrees = Vector3(180, 0, 0)
	bot.material_override = white
	bobber.add_child(bot)
	var stick := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.004
	cyl.bottom_radius = 0.006
	cyl.height = 0.12
	stick.mesh = cyl
	stick.position = Vector3(0, 0.07, 0)
	stick.material_override = quill
	bobber.add_child(stick)
	_mesh = ImmediateMesh.new()
	_line = MeshInstance3D.new()
	_line.mesh = _mesh
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(0.86, 0.86, 0.8, 0.75)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line.material_override = _mat
	add_child(_line)


## Redraws the line from `tip` to the bobber.
func draw_line_now() -> void:
	if _mesh == null:
		return
	_mesh.clear_surfaces()
	var a := tip
	var b := bobber.global_position + Vector3(0, 0.02, 0)
	var dist := a.distance_to(b)
	if dist < 0.05:
		return
	var sag := (1.0 - tight) * clampf(dist * 0.12, 0.05, 1.6)
	_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _mat)
	for i in 21:
		var f := float(i) / 20.0
		var p := a.lerp(b, f)
		p.y -= sag * 4.0 * f * (1.0 - f)
		_mesh.surface_add_vertex(p)
	_mesh.surface_end()


## Rod tip of `p`'s held rod: the first-person viewmodel when it is showing,
## otherwise the body model's held item.
static func rod_tip(p: Player) -> Vector3:
	var id := p.held_item()
	var length := FishingModels.rod_length(id)
	var item: Node3D = null
	if p.is_local and p.camera != null and p.camera.first_person:
		for c in p.camera.get_children():
			if c is Viewmodel:
				item = c.get("_item") as Node3D
	elif p.model != null and "_held" in p.model:
		item = p.model.get("_held") as Node3D
	if item != null and is_instance_valid(item) and item.is_inside_tree():
		return item.global_transform * Vector3(0, length, 0)
	var fwd := Vector3(sin(p.yaw), 0, cos(p.yaw))
	return p.global_position + Vector3(0, 2.2, 0) + fwd * 1.2
