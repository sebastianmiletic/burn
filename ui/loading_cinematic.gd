class_name LoadingCinematic
extends Node3D
## The loading screen's film: the Leviathan (the real boss model) circling in
## a night storm at sea, rearing out of the swell under lightning, roaring,
## snapping, and diving again, filmed by a slowly orbiting, wave-rocked camera.
## Lives in its own World3D inside LoadingScreen's SubViewport; everything is
## freed with the loading screen.
##
## Cost is kept small: no shadows, no SSAO/SSR/GI/volumetrics, a faked sea
## reflection, one creature, and the viewport renders at reduced scale.
## Animation runs on a clamped delta, so a long main-thread stall while the
## game world spins up slows the film for a frame instead of jumping it.

const LOOP := 27.0
const CIRCLE_R := 34.0
const CAM_R := 78.0
const T_REAR := 10.0
const T_ROAR := 12.6
const T_BITE := 16.2
const T_DIVE := 19.2

## 0..1 brightness of the current lightning (LoadingScreen washes the overlay with it).
var flash := 0.0
## Frames rendered so far (the screen fades the film in after a few, once shaders are warm).
var frames := 0

var _cam: Camera3D
var _env: Environment
var _sky_mat: ShaderMaterial
var _sea_mat: ShaderMaterial
var _sea: MeshInstance3D
var _moon: DirectionalLight3D
var _strike_light: DirectionalLight3D
var _holder: Node3D
var _lev: LeviathanModel
var _bolt: MeshInstance3D
var _bolt_mat: StandardMaterial3D
var _t := 0.0            # film time (clamped deltas)
var _loop_t := 0.0
var _loop_i := -1
var _phi := 0.0          # leviathan angle on its circle
var _omega := 0.26       # rad/s
var _cam_theta := 0.9
var _look := Vector3.ZERO
var _flash_t := 99.0
var _flash_peak := 0.0
var _next_sheet := 3.0
var _bolt_t := 99.0
var _fired := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7071
	_environment()
	_build_sea()
	_build_set()
	_cam = Camera3D.new()
	_cam.fov = 52.0
	_cam.near = 0.3
	_cam.far = 1600.0
	_cam.current = true
	add_child(_cam)
	_holder = Node3D.new()
	_holder.name = "LeviathanHolder"
	add_child(_holder)
	_lev = Models.create("leviathan") as LeviathanModel
	_lev.lod_enabled = false
	# The sea shader already supplies foam. Omit gameplay particle systems
	# in this short-lived private viewport (also avoids a Metal particle
	# shader leak when its World3D is destroyed after loading).
	_lev.particles_enabled = false
	_lev.water_y = 0.0
	_holder.add_child(_lev)
	_phi = _cam_theta + 2.4
	_place_holder(0.0)
	_look = Vector3(0, 4, 0)
	_update_camera(0.0)


func _environment() -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://ui/shaders/storm_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.32, 0.38, 0.48)
	_env.ambient_light_energy = 0.55
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.35
	_env.glow_enabled = true
	_env.glow_intensity = 0.55
	_env.glow_bloom = 0.04
	_env.glow_hdr_threshold = 1.3
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.06, 0.075, 0.095)
	_env.fog_light_energy = 1.0
	_env.fog_density = 0.0055
	_env.fog_sky_affect = 0.35
	_env.adjustment_enabled = true
	_env.adjustment_contrast = 1.08
	_env.adjustment_saturation = 0.85
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_moon = DirectionalLight3D.new()
	_moon.rotation = Vector3(deg_to_rad(-24.0), deg_to_rad(155.0), 0)
	_moon.light_color = Color(0.62, 0.7, 0.9)
	_moon.light_energy = 0.55
	_moon.shadow_enabled = false
	add_child(_moon)
	_strike_light = DirectionalLight3D.new()
	_strike_light.light_color = Color(0.8, 0.86, 1.0)
	_strike_light.light_energy = 0.0
	_strike_light.shadow_enabled = false
	add_child(_strike_light)


func _build_sea() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(900, 900)
	plane.subdivide_width = 220
	plane.subdivide_depth = 220
	_sea = MeshInstance3D.new()
	_sea.mesh = plane
	_sea_mat = ShaderMaterial.new()
	_sea_mat.shader = preload("res://ui/shaders/storm_sea.gdshader")
	_sea.material_override = _sea_mat
	_sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sea.extra_cull_margin = 8.0
	add_child(_sea)


## Rocks and a drowned tower for scale; the fog turns them to silhouettes.
func _build_set() -> void:
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.05, 0.05, 0.055)
	rock.roughness = 0.95
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.09, 0.085, 0.08)
	stone.roughness = 0.9
	# Sea stacks: faceted, tapering crags; one bears the drowned spire.
	var stacks := [
		# [position, radius, height, tilt (x, z), segments]
		[Vector3(-150, -4, -215), 22.0, 44.0, Vector2(0.06, -0.04), 7],
		[Vector3(-122, -4, -236), 11.0, 62.0, Vector2(-0.05, 0.08), 6],
		[Vector3(-178, -4, -190), 9.0, 26.0, Vector2(0.12, 0.1), 5],
		[Vector3(215, -4, -168), 16.0, 30.0, Vector2(-0.08, 0.05), 6],
		[Vector3(238, -4, -150), 7.0, 38.0, Vector2(0.1, -0.06), 5],
		[Vector3(-330, -6, 70), 30.0, 52.0, Vector2(0.04, 0.03), 7],
		[Vector3(90, -4, 230), 12.0, 18.0, Vector2(0.0, 0.1), 6],
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for st: Array in stacks:
		var c := CylinderMesh.new()
		c.top_radius = float(st[1]) * rng.randf_range(0.06, 0.16)
		c.bottom_radius = float(st[1])
		c.height = float(st[2])
		c.radial_segments = int(st[4])
		c.rings = 3
		var mi := MeshInstance3D.new()
		mi.mesh = c
		mi.position = (st[0] as Vector3) + Vector3(0, float(st[2]) * 0.5, 0)
		mi.rotation = Vector3((st[3] as Vector2).x, rng.randf() * TAU, (st[3] as Vector2).y)
		mi.material_override = rock
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var c2 := CylinderMesh.new()
		c2.top_radius = float(st[1]) * 0.05
		c2.bottom_radius = float(st[1]) * 0.6
		c2.height = float(st[2]) * rng.randf_range(0.45, 0.7)
		c2.radial_segments = 5
		var m2 := MeshInstance3D.new()
		m2.mesh = c2
		var side := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * float(st[1]) * 0.75
		m2.position = (st[0] as Vector3) + side + Vector3(0, c2.height * 0.5, 0)
		m2.rotation = Vector3(side.z * 0.012, rng.randf() * TAU, -side.x * 0.012)
		m2.material_override = rock
		m2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m2)
	# The drowned spire: a slender broken tower on the tallest stack.
	var spire := CylinderMesh.new()
	spire.top_radius = 1.6
	spire.bottom_radius = 3.4
	spire.height = 34.0
	spire.radial_segments = 8
	var sp := MeshInstance3D.new()
	sp.mesh = spire
	sp.position = Vector3(-122, 70, -236)
	sp.rotation = Vector3(-0.04, 0.0, 0.1)
	sp.material_override = stone
	add_child(sp)
	var ember := MeshInstance3D.new()
	var em := SphereMesh.new()
	em.radius = 0.9
	em.height = 1.8
	ember.mesh = em
	var em_mat := StandardMaterial3D.new()
	em_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em_mat.albedo_color = Color(3.0, 1.6, 0.7)
	em_mat.disable_fog = true
	ember.material_override = em_mat
	ember.position = Vector3(-120.5, 84, -235)
	add_child(ember)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.6, 0.3)
	lamp.light_energy = 2.0
	lamp.omni_range = 18.0
	lamp.position = Vector3(-120, 84, -236)
	add_child(lamp)
	_bolt_mat = StandardMaterial3D.new()
	_bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bolt_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_bolt_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bolt_mat.albedo_color = Color(2.6, 2.8, 3.4, 1.0)
	_bolt_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bolt_mat.disable_fog = true
	_bolt = MeshInstance3D.new()
	_bolt.material_override = _bolt_mat
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.visible = false
	add_child(_bolt)


func _process(frame_delta: float) -> void:
	frames += 1
	var delta := minf(frame_delta, 1.0 / 30.0)
	_t += delta
	_loop_t = fmod(_t, LOOP)
	var i := int(_t / LOOP)
	if i != _loop_i:
		_loop_i = i
		_fired.clear()
	_cam_theta += delta * 0.045
	_leviathan(delta)
	_lightning(delta)
	_update_camera(delta)
	# Keep the sea under the camera (its waves are in world space).
	_sea.global_position = Vector3(snappedf(_cam.global_position.x, 8.0), 0.0, snappedf(_cam.global_position.z, 8.0))


func _once(key: String, at: float) -> bool:
	if _loop_t >= at and not _fired.has(key):
		_fired[key] = true
		return true
	return false


func _leviathan(delta: float) -> void:
	var lt := _loop_t
	var rearing := lt >= T_REAR - 1.2 and lt < T_DIVE + 1.0
	# Cruise so the rear-up happens on the near side of the circle, a little
	# off-centre: steer the angular speed towards that rendezvous.
	if lt < T_REAR - 1.2:
		var target := _cam_theta + (T_REAR - lt) * 0.045 + 0.32
		var need := wrapf(target - _phi, 0.0, TAU)
		if need < 0.6:
			need += TAU
		var wanted := clampf(need / maxf(T_REAR - 1.2 - lt, 0.5), 0.16, 0.42)
		_omega = lerpf(_omega, wanted, 1.0 - exp(-delta * 0.8))
	elif rearing:
		_omega = lerpf(_omega, 0.0, 1.0 - exp(-delta * 1.6))
	else:
		_omega = lerpf(_omega, 0.28, 1.0 - exp(-delta * 0.6))
	_phi += _omega * delta
	_place_holder(delta)
	if _once("rear", T_REAR):
		_lev.surfaced = true
		_lev.engaged = true
		CreatureFx.play(self, "geyser", _holder.global_position + Vector3(0, 0, 0), 3.0)
		CreatureFx.play(self, "foam", _holder.global_position, 4.0)
	if _once("roar", T_ROAR):
		_lev.play("roar", 2.6)
		_strike(true)
	if _once("bite", T_BITE):
		_lev.play("bite")
	if _once("dive", T_DIVE):
		_lev.play("dive", 1.6)
		_lev.surfaced = false
		_lev.engaged = false
		CreatureFx.play(self, "splash", _holder.global_position, 3.5)


func _place_holder(delta: float) -> void:
	var pos := Vector3(cos(_phi), 0.0, sin(_phi)) * CIRCLE_R
	_holder.global_position = pos
	# Swim along the circle; when reared, turn to face the camera.
	var tangent := Vector3(-sin(_phi), 0.0, cos(_phi))
	var heading := atan2(-tangent.x, -tangent.z)
	if _cam != null and _lev != null and _lev.surfaced:
		var to_cam := _cam.global_position - pos
		heading = atan2(-to_cam.x, -to_cam.z) + 0.25
	if delta <= 0.0:
		_holder.rotation.y = heading
	else:
		_holder.rotation.y = lerp_angle(_holder.rotation.y, heading, 1.0 - exp(-delta * 1.8))


func _update_camera(delta: float) -> void:
	var t := _t
	var base := Vector3(cos(_cam_theta), 0.0, sin(_cam_theta)) * CAM_R
	# A boat's motion: slow heave, pitch and roll.
	var heave := sin(t * 0.7) * 1.1 + sin(t * 1.31 + 1.0) * 0.45
	# Close in and drop low while it rears, so it towers against the sky.
	var rear := _rear_weight()
	base = base.lerp(Vector3(_holder.global_position.x, 0, _holder.global_position.z) + (base - _holder.global_position).normalized() * 40.0, rear * 0.85)
	var pos := base + Vector3(0, lerpf(9.5, 4.2, rear) + heave * lerpf(1.0, 0.6, rear), 0)
	var head := _lev.head.global_position if _lev != null and _lev.head != null else Vector3(0, 4, 0)
	var focus := Vector3(_holder.global_position.x, 3.0, _holder.global_position.z).lerp(head, 0.25 + 0.4 * rear)
	focus = focus.lerp(Vector3(0, 3, 0), 0.25 * (1.0 - rear))
	_look = focus if delta <= 0.0 else _look.lerp(focus, 1.0 - exp(-delta * 1.2))
	_cam.global_position = pos
	_cam.look_at(_look, Vector3.UP)
	_cam.rotate_object_local(Vector3.FORWARD, sin(t * 0.53) * 0.025)
	_cam.rotate_object_local(Vector3.RIGHT, sin(t * 0.81 + 0.4) * 0.012)


## 0 cruising .. 1 reared (smooth, for the camera).
var _rear_w := 0.0
func _rear_weight() -> float:
	var lt := _loop_t
	var goal := 1.0 if (lt >= T_REAR - 1.5 and lt < T_DIVE + 0.8) else 0.0
	_rear_w = lerpf(_rear_w, goal, 1.0 - exp(-get_process_delta_time() * 0.9))
	return smoothstep(0.0, 1.0, _rear_w)


# --- Lightning ----------------------------------------------------------------------------

func _lightning(delta: float) -> void:
	_next_sheet -= delta
	if _next_sheet <= 0.0:
		_next_sheet = _rng.randf_range(3.5, 8.0)
		var near_roar := absf(_loop_t - T_ROAR) < 2.5
		if not near_roar:
			_strike(_rng.randf() < 0.3)
	_flash_t += delta
	_bolt_t += delta
	# A strike flickers: a bright stroke, a dip, a second return stroke, decay.
	var f := 0.0
	if _flash_t < 1.4:
		var x := _flash_t
		f = exp(-x * 9.0) + 0.7 * exp(-pow((x - 0.18) * 14.0, 2.0)) + 0.45 * exp(-pow((x - 0.42) * 10.0, 2.0)) * (1.0 - x / 1.4)
	flash = clampf(f * _flash_peak, 0.0, 1.5)
	_sky_mat.set_shader_parameter(&"flash", flash)
	_sea_mat.set_shader_parameter(&"flash", flash)
	_strike_light.light_energy = flash * 1.3
	_env.fog_light_color = Color(0.06, 0.075, 0.095).lerp(Color(0.35, 0.4, 0.5), clampf(flash * 0.6, 0.0, 1.0))
	_env.ambient_light_energy = 0.55 + flash * 0.8
	if _bolt.visible:
		var a := clampf(1.0 - _bolt_t / 0.55, 0.0, 1.0) * clampf(f * 1.4, 0.0, 1.0)
		_bolt_mat.albedo_color = Color(2.6, 2.8, 3.4, a)
		if _bolt_t > 0.6:
			_bolt.visible = false


## Lightning: `bolt` draws a stroke behind the scene; otherwise sheet lightning.
func _strike(bolt: bool) -> void:
	_flash_t = 0.0
	_flash_peak = _rng.randf_range(0.75, 1.0) if bolt else _rng.randf_range(0.3, 0.55)
	# Strike behind the action as seen from the camera, a little to one side.
	var away := (Vector3(_holder.global_position.x, 0, _holder.global_position.z) - Vector3(_cam.global_position.x, 0, _cam.global_position.z)).normalized()
	if away.length_squared() < 0.5:
		away = Vector3(0, 0, -1)
	var side := away.cross(Vector3.UP).normalized()
	var ground := _cam.global_position + away * _rng.randf_range(230.0, 320.0) + side * _rng.randf_range(-90.0, 90.0)
	ground.y = 0.0
	var dir := (ground + Vector3(0, 120, 0) - _cam.global_position).normalized()
	_sky_mat.set_shader_parameter(&"flash_dir", dir)
	_sea_mat.set_shader_parameter(&"flash_dir", dir)
	_strike_light.look_at_from_position(ground + Vector3(0, 200, 0), _holder.global_position + Vector3(0, 6, 0), Vector3.UP)
	if bolt:
		_build_bolt(ground)


func _build_bolt(ground: Vector3) -> void:
	var to_cam := (_cam.global_position - ground)
	to_cam.y = 0.0
	var side := Vector3.UP.cross(to_cam.normalized()).normalized()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := ground + Vector3(_rng.randf_range(-30, 30), 190.0, 0)
	var main := _zigzag(top, ground, 22, 9.0)
	_ribbon(st, main, side, 1.6, 0.5)
	# A few forks off the main channel.
	for k in 3:
		var from_i := _rng.randi_range(3, main.size() - 6)
		var start: Vector3 = main[from_i]
		var end := start + Vector3(_rng.randf_range(-40, 40), -_rng.randf_range(30, 70), _rng.randf_range(-10, 10))
		_ribbon(st, _zigzag(start, end, 8, 5.0), side, 0.8, 0.4)
	_bolt.mesh = st.commit()
	_bolt.visible = true
	_bolt_t = 0.0


func _zigzag(a: Vector3, b: Vector3, steps: int, jag: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in steps + 1:
		var f := float(i) / steps
		var p := a.lerp(b, f)
		if i > 0 and i < steps:
			p += Vector3(_rng.randf_range(-jag, jag), _rng.randf_range(-jag, jag) * 0.3, _rng.randf_range(-jag, jag) * 0.4)
		pts.append(p)
	return pts


func _ribbon(st: SurfaceTool, pts: PackedVector3Array, side: Vector3, w0: float, w1: float) -> void:
	for i in pts.size() - 1:
		var f0 := float(i) / (pts.size() - 1)
		var f1 := float(i + 1) / (pts.size() - 1)
		var a0 := pts[i] - side * lerpf(w0, w1, f0)
		var a1 := pts[i] + side * lerpf(w0, w1, f0)
		var b0 := pts[i + 1] - side * lerpf(w0, w1, f1)
		var b1 := pts[i + 1] + side * lerpf(w0, w1, f1)
		for v in [a0, a1, b1, a0, b1, b0]:
			st.add_vertex(v)
