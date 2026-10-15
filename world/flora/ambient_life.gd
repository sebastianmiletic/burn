class_name AmbientLife
extends Node3D
## Subtle ambient life around the camera, animated almost entirely on the GPU:
##   * pollen / dust motes drifting with the wind (by day; pale wisps in the underworld)
##   * butterflies fluttering low over the ground (day, dry, not too windy)
##   * fireflies blinking near the ground (dusk and night)
##   * autumn leaves falling from nearby oaks/crimsons (Flora chunks) and drifting downwind
##   * leaves swirling and skittering along the ground in gusts
##
## GameWorld adds one (anywhere; it places itself at the world origin). It reads the time of
## day, dimension, underground state and ground height from GameWorld.instance; set
## `time_of_day`, `dimension`, `ground_height` to drive it without a GameWorld (tests).
## CPU cost: a few dozen instance updates every 0.3 s.

const MOTES := 140
const FIREFLIES := 44
const BUTTERFLIES := 9
const FALLING := 64
const SWIRL := 28
const RADIUS := 22.0

var time_of_day := -1.0          ## hours; < 0 = read from GameWorld.sky
var dimension := -1              ## < 0 = GameWorld.local_dimension
var ground_height: Callable      ## (x: float, z: float) -> float; default: VoxelWorld.surface_y
var enabled := true
## Weather inputs (the shader globals cannot be read back at runtime). < 0 = from GameWorld.weather.
var wind := -1.0
var wetness := -1.0

var _motes: MultiMeshInstance3D
var _flies: MultiMeshInstance3D
var _butterflies: MultiMeshInstance3D
var _falling: MultiMeshInstance3D
var _swirl: MultiMeshInstance3D
var _rng := RandomNumberGenerator.new()
var _tick := 0.0
var _leaf_tick := 0.0
var _leaf_key := ""
var _cam := Vector3.ZERO

static var _glow_shader: Shader
static var _critter_shader: Shader


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_rng.seed = 4711
	if _glow_shader == null:
		_glow_shader = load("res://world/flora/shaders/ambient_glow.gdshader")
		_critter_shader = load("res://world/flora/shaders/ambient_critter.gdshader")
	_motes = _make(MOTES, _quad(), _glow_mat(0, Color(1.0, 0.86, 0.62), 0.028, 0.0))
	for i in MOTES:
		_motes.multimesh.set_instance_custom_data(i, Color(_rng.randf(), _rng.randf(), _rng.randf(), _rng.randf()))
	_flies = _make(FIREFLIES, _quad(), _glow_mat(1, Color(0.75, 1.0, 0.35), 0.05, 0.0))
	for i in FIREFLIES:
		_flies.multimesh.set_instance_custom_data(i, Color(0, 0, 0, _rng.randf()))
		_flies.multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -1000, 0)))
	_butterflies = _make(BUTTERFLIES, _wings(), _critter_mat(0, 0.075))
	var wing_cols := [Color(0.95, 0.5, 0.08), Color(0.95, 0.92, 0.85), Color(0.98, 0.85, 0.25), Color(0.35, 0.5, 0.95), Color(0.85, 0.3, 0.1)]
	for i in BUTTERFLIES:
		var c: Color = wing_cols[i % wing_cols.size()]
		_butterflies.multimesh.set_instance_custom_data(i, Color(c.r, c.g, c.b, _rng.randf()))
		_butterflies.multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -1000, 0)))
	_falling = _make(FALLING, _quad_xz(), _critter_mat(1, 0.09))
	for i in FALLING:
		_falling.multimesh.set_instance_custom_data(i, Color(2.0, 6.0, _rng.randf(), _rng.randf()))
		_falling.multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -1000, 0)))
	_swirl = _make(SWIRL, _quad_xz(), _critter_mat(2, 0.085))
	for i in SWIRL:
		_swirl.multimesh.set_instance_custom_data(i, Color(0, 0, _rng.randf(), _rng.randf()))
		_swirl.multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -1000, 0)))


func _make(count: int, mesh: Mesh, mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	# Everything is positioned in the shaders around the camera: never frustum-cull the batch.
	mm.custom_aabb = AABB(Vector3(-1e5, -1e4, -1e5), Vector3(2e5, 2e4, 2e5))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mmi)
	return mmi


func _glow_mat(mode: int, tint: Color, size: float, intensity: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _glow_shader
	m.set_shader_parameter(&"mode", mode)
	m.set_shader_parameter(&"tint", tint)
	m.set_shader_parameter(&"size", size)
	m.set_shader_parameter(&"intensity", intensity)
	return m


func _critter_mat(mode: int, size: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _critter_shader
	m.set_shader_parameter(&"mode", mode)
	m.set_shader_parameter(&"size", size)
	return m


static func _quad() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
		st.set_uv(v)
		st.add_vertex(Vector3(v.x - 0.5, v.y - 0.5, 0))
	return st.commit()


## Flat quad in XZ, centred (a leaf), UV y along -Z..+Z.
static func _quad_xz() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
		st.set_uv(v)
		st.set_uv2(Vector2.ZERO)
		st.add_vertex(Vector3((v.x - 0.5) * 0.7, 0, v.y - 0.5))
	return st.commit()


## Two wing quads hinged on the body axis (z); UV.x 0 at the body .. 1 at the tip, UV2.x = side.
static func _wings() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		var quad := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]
		for v: Vector2 in quad:
			st.set_uv(v)
			st.set_uv2(Vector2(side, 0))
			st.add_vertex(Vector3(side * v.x, 0, (v.y - 0.5) * 1.1))
	return st.commit()


func _process(delta: float) -> void:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null:
		return
	_cam = cam.global_position
	var tod := time_of_day
	var dim := dimension
	var underground := false
	var w: GameWorld = GameWorld.instance
	if w != null and is_instance_valid(w):
		if tod < 0.0 and w.sky != null:
			tod = w.sky.time_of_day
		if dim < 0:
			dim = w.local_dimension
		if w.tracker != null:
			underground = w.tracker.underground
	if tod < 0.0:
		tod = 12.0
	dim = maxi(dim, 0)
	var day := smoothstep(6.0, 8.0, tod) * (1.0 - smoothstep(17.5, 19.5, tod))
	var dusk := smoothstep(18.5, 20.5, tod) + (1.0 - smoothstep(3.5, 5.5, tod))
	dusk = clampf(dusk, 0.0, 1.0)
	var wet := wetness
	var wnd := wind
	if w != null and is_instance_valid(w) and w.weather != null:
		if wnd < 0.0 and w.weather.has_method(&"wind_amount"):
			wnd = float(w.weather.call(&"wind_amount"))
		if wet < 0.0 and w.weather.has_method(&"rain_amount"):
			wet = float(w.weather.call(&"rain_amount"))
	wnd = 0.35 if wnd < 0.0 else wnd
	wet = 0.0 if wet < 0.0 else wet
	var on := enabled and not underground
	var hell := dim == 1
	var mm := _motes.material_override as ShaderMaterial
	if hell:
		mm.set_shader_parameter(&"tint", Color(0.55, 0.75, 1.0))
		mm.set_shader_parameter(&"intensity", 0.5 if on else 0.0)
	else:
		mm.set_shader_parameter(&"tint", Color(1.0, 0.86, 0.62))
		mm.set_shader_parameter(&"intensity", (0.08 + 0.55 * day) * (1.0 - wet * 0.8) if on else 0.0)
	(_flies.material_override as ShaderMaterial).set_shader_parameter(&"intensity",
			(1.6 * dusk * (1.0 - wet * 0.7)) if on and not hell else 0.0)
	_flies.visible = on and not hell and dusk > 0.01
	var bf := day * (1.0 - smoothstep(0.2, 0.5, wet)) * (1.0 - smoothstep(0.7, 1.0, wnd))
	(_butterflies.material_override as ShaderMaterial).set_shader_parameter(&"visible_amount", bf if on and not hell else 0.0)
	_butterflies.visible = on and not hell and bf > 0.01
	_falling.visible = on and not hell
	(_swirl.material_override as ShaderMaterial).set_shader_parameter(&"visible_amount", smoothstep(0.2, 0.45, wnd))
	_swirl.visible = on and not hell and wnd > 0.2
	(_falling.material_override as ShaderMaterial).set_shader_parameter(&"visible_amount", 0.55 + 0.45 * smoothstep(0.2, 0.8, wnd))

	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.3
		_rehome(_flies.multimesh, FIREFLIES, RADIUS, 0.0, 6)
		_rehome(_butterflies.multimesh, BUTTERFLIES, RADIUS * 0.8, 0.0, 3)
		_rehome(_swirl.multimesh, SWIRL, RADIUS * 0.7, 0.0, 5)
	_leaf_tick -= delta
	if _leaf_tick <= 0.0:
		_leaf_tick = 1.0
		_assign_leaves()


## Moves up to `budget` instances that drifted out of range to fresh homes on the ground.
func _rehome(mm: MultiMesh, count: int, radius: float, lift: float, budget: int) -> void:
	for i in count:
		if budget <= 0:
			return
		var p := mm.get_instance_transform(i).origin
		var d := Vector2(p.x - _cam.x, p.z - _cam.z).length()
		if d < radius and absf(p.y - _cam.y) < 30.0:
			continue
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * radius * 0.95 + 1.5
		var x := _cam.x + cos(a) * r
		var z := _cam.z + sin(a) * r
		var y := _ground(x, z)
		if is_nan(y):
			continue
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(x, y + lift, z)))
		budget -= 1


func _ground(x: float, z: float) -> float:
	if ground_height.is_valid():
		return ground_height.call(x, z)
	var w: GameWorld = GameWorld.instance
	if w != null and is_instance_valid(w):
		var vw := w.world_for(w.local_dimension)
		if vw != null:
			return float(vw.surface_y(int(floor(x)), int(floor(z)))) + 1.0
	return _cam.y - 1.7


## Hands the falling-leaf instances to the nearest autumn trees (from Flora chunk metadata).
func _assign_leaves() -> void:
	var crowns: Array = []   # [dist, crown centre, radius, fall, hue]
	for n: Node in get_tree().get_nodes_in_group(&"flora_chunks"):
		var node := n as Node3D
		if node == null or not node.is_inside_tree():
			continue
		var base := node.global_position
		if Vector2(base.x + 8.0 - _cam.x, base.z + 8.0 - _cam.z).length() > 45.0:
			continue
		var info: PackedVector4Array = node.get_meta(&"trees", PackedVector4Array())
		for t in info:
			var kind := int(t.w)
			if kind != Flora.OAK and kind != Flora.CRIMSON:
				continue
			var h := fmod(t.w, 1.0) * 100.0
			var root := node.global_transform * Vector3(t.x, t.y, t.z)
			var d := root.distance_to(_cam)
			if d > 32.0:
				continue
			var hue := 0.15 if kind == Flora.OAK else 0.8
			crowns.append([d, root + Vector3(0, h * 0.62, 0), h * 0.38, h * 0.55, hue])
	crowns.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	crowns = crowns.slice(0, 10)
	var key := ""
	for c: Array in crowns:
		key += str(Vector3i(c[1]))
	if key == _leaf_key:
		return
	_leaf_key = key
	var mm := _falling.multimesh
	if crowns.is_empty():
		for i in FALLING:
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -1000, 0)))
		return
	for i in FALLING:
		var c: Array = crowns[i % crowns.size()]
		mm.set_instance_transform(i, Transform3D(Basis(), c[1]))
		var old := mm.get_instance_custom_data(i)
		mm.set_instance_custom_data(i, Color(c[2], c[3], fract_hue(c[4] + _rng.randf() * 0.3), old.a))


static func fract_hue(h: float) -> float:
	return h - floorf(h)
