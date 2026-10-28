class_name CharybdisModel
extends CreatureModel
## Charybdis, the Maw of the Sea: a whirlpool 24 m across draining into a living
## throat. The funnel wall is one animated water surface spiralling down; at its
## heart a ringed maw (a fleshy lip ring, three concentric rows of hooked teeth
## that open and grind, a glowing gullet) heaves up the funnel to bite and sinks
## back; wreckage (hull planks, a mast, barrels, a figurehead) orbits in the
## current and is flung out of it.
##
## The entity position is the maw. Set `risen`, `engaged`, `fury` (0..1),
## `water_y` and `arena_center` (and `lean_to`, the offset it is wandering
## towards: the risen maw tilts that way); actions: bite (gulp), throw (debris),
## summon (vortex/spin/undertow), roar, lunge (heaves over the rim towards
## `lean_to`), spout (sinks and blasts geysers up), hit (recoil), die (the
## rings slacken, the gullet dies and the whirlpool winds down).

var risen := false
var engaged := false
var fury := 0.0
var water_y := 13.0
var arena_center := Vector3.INF
var lean_to := Vector3.ZERO

const RIM := 11.6
const DEPTH := 13.0

var funnel: MeshInstance3D
var maw: Node3D
var rings: Array[Node3D] = []
var gullet: MeshInstance3D
var debris: Array = []   # [node, radius, height, phase, speed]
var _rise := 0.0
var _open := 0.3
var _spin := 1.0
var _tilt := Vector3.ZERO
var _drop := 0.0


func _init() -> void:
	dissolve_delay = 3.0
	dissolve_time = 3.0
	durations["bite"] = 2.2
	durations["throw"] = 3.0
	durations["summon"] = 3.0
	durations["roar"] = 2.4
	durations["lunge"] = 2.7
	durations["spout"] = 2.0
	durations["hit"] = 0.7


func _ember_extents() -> Vector3:
	return Vector3(5.0, 2.0, 5.0)


func _lod_size() -> float:
	return 30.0


func set_boss_state(is_engaged: bool, phase: int, dead: bool) -> void:
	engaged = is_engaged
	fury = 0.0 if dead else float(phase) / 3.0


## A surface of revolution: profile points (radius, y) from top to bottom; UV.x around, UV.y along.
static func _lathe(profile: PackedVector2Array, segments: int, inward := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := profile.size()
	var length := 0.0
	var acc := PackedFloat32Array([0.0])
	for i in range(1, n):
		length += profile[i].distance_to(profile[i - 1])
		acc.append(length)
	for i in n:
		for s in segments + 1:
			var a := TAU * s / segments
			var p := profile[i]
			var d := (profile[mini(i + 1, n - 1)] - profile[maxi(i - 1, 0)]).normalized()
			var nrm2 := Vector2(d.y, -d.x) * (-1.0 if inward else 1.0)
			st.set_uv(Vector2(float(s) / segments, acc[i] / maxf(length, 0.001)))
			st.set_normal(Vector3(cos(a) * nrm2.x, nrm2.y, sin(a) * nrm2.x).normalized())
			st.add_vertex(Vector3(cos(a) * p.x, p.y, sin(a) * p.x))
	var row := segments + 1
	for i in n - 1:
		for s in segments:
			var a0 := i * row + s
			var b0 := a0 + row
			if inward:
				st.add_index(a0)
				st.add_index(a0 + 1)
				st.add_index(b0)
				st.add_index(a0 + 1)
				st.add_index(b0 + 1)
				st.add_index(b0)
			else:
				st.add_index(a0)
				st.add_index(b0)
				st.add_index(a0 + 1)
				st.add_index(a0 + 1)
				st.add_index(b0)
				st.add_index(b0 + 1)
	st.generate_tangents()
	return st.commit()


static var _funnel_mesh: ArrayMesh
static var _throat_mesh: ArrayMesh
static var _lip_mesh: ArrayMesh


func _build() -> void:
	if _funnel_mesh == null:
		# A flat lip out over the sea hides where the open funnel meets the water around it.
		var prof := PackedVector2Array([Vector2(15.8, 0.02), Vector2(14.2, 0.08)])
		for i in 25:
			var t := float(i) / 24.0
			# A steepening spiral funnel: wide shallow rim, plunging throat.
			prof.append(Vector2(lerpf(RIM + 1.2, 2.4, pow(t, 0.62)), -DEPTH * pow(t, 1.6) + 0.15))
		_funnel_mesh = _lathe(prof, 64, true)
		_throat_mesh = _lathe(PackedVector2Array([Vector2(3.6, 0.6), Vector2(3.2, -0.4), Vector2(2.6, -1.6), Vector2(1.4, -3.0), Vector2(0.3, -4.0)]), 32, true)
		var lip := PackedVector2Array()
		for i in 13:
			var a := PI * float(i) / 12.0
			lip.append(Vector2(4.3 + cos(a) * 0.9, sin(a) * 0.75 + 0.15))
		_lip_mesh = _lathe(lip, 40)
	var water := ShaderMaterial.new()
	water.shader = preload("res://models/creatures/vortex.gdshader")
	funnel = ModelKit.part(self, _funnel_mesh, water)
	funnel.top_level = true
	funnel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flesh := CreatureSkin.smooth(Color(0.36, 0.14, 0.16), Color(0.62, 0.32, 0.3), {"wet": 0.9, "bump": 1.4,
		"accent": Color(0.18, 0.05, 0.07), "accent_mode": 3, "accent_amount": 0.6, "accent_scale": 0.6})
	var barnacle := CreatureSkin.rock(Color(0.5, 0.48, 0.42), {"wet": 0.6, "pattern_scale": 3.0})
	var tooth := CreatureSkin.keratin(Color(0.86, 0.83, 0.72))
	maw = Node3D.new()
	maw.name = "Maw"
	add_child(maw)
	ModelKit.part(maw, _lip_mesh, flesh)
	ModelKit.part(maw, _throat_mesh, CreatureSkin.mouth(Color(0.3, 0.06, 0.08)))
	gullet = ModelKit.part(maw, ModelKit.sphere(1.3, 14), ModelKit.glow(Color(0.3, 1.0, 0.75), 4.0, 0.4), Vector3(0, -3.4, 0), Vector3.ZERO, Vector3(1.4, 0.6, 1.4))
	# Barnacle crust and rock plates around the lip.
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	for i in 22:
		var a := TAU * i / 22.0 + rng.randf() * 0.15
		var r := 5.1 + rng.randf_range(-0.2, 0.3)
		ModelKit.part(maw, OrganicMesh.blob("chary_barnacle_%d" % (i % 4), Vector3(0.7, 0.45, 0.6), 0.35, 20 + i % 4, 10), barnacle,
			Vector3(cos(a) * r, 0.35 + rng.randf() * 0.2, sin(a) * r), Vector3(0, -rad_to_deg(a), rng.randf_range(-15, 15)))
	# Three rings of hooked teeth, the outer ones longest; each ring is a joint that opens and turns.
	for ring in 3:
		var holder := ModelKit.joint(maw, "Ring%d" % ring, Vector3(0, -ring * 0.9, 0))
		var count: int = [26, 20, 14][ring]
		var radius: float = [3.9, 2.9, 1.9][ring]
		var length: float = [1.9, 1.5, 1.1][ring]
		var tm := OrganicMesh.bezier("chary_tooth_%d" % ring, Vector3.ZERO, Vector3(0, length * 0.7, -length * 0.1), Vector3(0, length, -length * 0.55), length * 0.16, length * 0.02, 6, 6)
		for t in count:
			var a := TAU * float(t) / count + ring * 0.2
			var tooth_node := ModelKit.part(holder, tm, tooth, Vector3(cos(a) * radius, 0.1, sin(a) * radius))
			tooth_node.rotation = Vector3(0, -a - PI / 2.0, 0)
			tooth_node.rotate_object_local(Vector3.RIGHT, -0.5)
		rings.append(holder)
	# Wreckage orbiting in the current.
	var wood := ModelKit.mat(Color(0.33, 0.26, 0.19), AsciiMaterialId.SOLID, 0.9)
	var dark_wood := ModelKit.mat(Color(0.22, 0.17, 0.13), AsciiMaterialId.SOLID, 0.9)
	var pieces := [ModelKit.box(Vector3(0.5, 0.18, 4.2)), ModelKit.cylinder(0.22, 0.28, 7.0, 8), ModelKit.cylinder(0.55, 0.5, 1.3, 12),
			ModelKit.box(Vector3(1.6, 0.2, 2.8)), OrganicMesh.blob("chary_rock", Vector3(1.0, 0.8, 0.9), 0.3, 5, 10)]
	for i in 16:
		var mesh: Mesh = pieces[i % pieces.size()]
		var node := ModelKit.part(self, mesh, barnacle if i % pieces.size() == 4 else (dark_wood if i % 3 == 0 else wood))
		node.top_level = true
		debris.append([node, rng.randf_range(4.0, RIM - 0.5), rng.randf(), rng.randf() * TAU, rng.randf_range(0.7, 1.3), rng.randf() * TAU])


func _animate(delta: float) -> void:
	if maw == null:
		return
	var c := arena_center if arena_center.is_finite() else global_position + Vector3(0, 12.0, 0)
	var top := water_y + 0.1
	var p := action_progress()
	var w := action_weight(0.15, 0.25)
	_spin = damp(_spin, (1.0 + fury * 1.2) * (1.8 if (_action in ["summon", "throw"] and p >= 0.0) else 1.0) * (0.0 if _dead else 1.0) + 0.15, 1.5, delta)
	funnel.global_transform = Transform3D(Basis(Vector3.UP, -_time * 0.35 * _spin), Vector3(c.x, top, c.z))
	funnel.set_instance_shader_parameter(&"spin", _spin)
	funnel.set_instance_shader_parameter(&"fury", fury)
	_rise = damp(_rise, 1.0 if (risen and not _dead) else 0.0, 2.0, delta)
	var open_t := 0.35 + 0.15 * sin(_time * 1.1)
	if p >= 0.0 and not _dead:
		match _action:
			"bite":
				open_t = keys(p, [[0, 0.4], [0.35, 1.0], [0.55, 0.0], [0.8, 0.1], [1, 0.4]])
			"roar", "summon":
				open_t = lerpf(open_t, 1.0, w)
			"throw":
				open_t = lerpf(open_t, 0.8 + 0.2 * sin(_time * 9.0), w)
			"lunge":
				open_t = keys(p, [[0, 0.4], [0.45, 1.1], [0.6, 0.0], [0.8, 0.2], [1, 0.4]])
			"spout":
				open_t = lerpf(open_t, 1.1, w)
			"hit":
				open_t = lerpf(open_t, 0.05, sin(PI * p))
	if _dead:
		open_t = 0.9
	_open = damp(_open, open_t, 8.0, delta)
	# The maw rides the entity (risen to the rim or deep in the throat); it never leaves the funnel axis.
	var my := global_position.y
	# The maw wanders round the funnel with the entity (never past its walls) and
	# tilts towards where it is heading once it has risen; it heaves and jolts.
	var off := Vector3(global_position.x - c.x, 0, global_position.z - c.z).limit_length(RIM - 5.5)
	var tilt_goal := Vector3(lean_to.x, 0, lean_to.z).limit_length(1.0) * 0.35 * _rise
	var drop_goal := 0.0
	if p >= 0.0 and not _dead:
		match _action:
			"lunge":
				tilt_goal *= 1.0 + keys(p, [[0, 0], [0.45, 0.6], [0.6, 1.6], [1, 0.4]])
				drop_goal = -keys(p, [[0, 0], [0.45, 1.5], [0.6, 2.5], [1, 0]])
			"spout":
				drop_goal = keys(p, [[0, 0], [0.4, 2.5], [0.65, -1.0], [1, 0]])
			"hit":
				drop_goal = 1.2 * sin(PI * p)
	_tilt = _tilt.lerp(tilt_goal, 1.0 - exp(-4.0 * delta))
	_drop = damp(_drop, drop_goal, 9.0, delta)
	var tilt_axis := Vector3(_tilt.z, 0, -_tilt.x)
	var mb := Basis(Vector3.UP, _time * 0.25 * _spin)
	if tilt_axis.length() > 0.001:
		mb = Basis(tilt_axis.normalized(), tilt_axis.length()) * mb
	maw.global_transform = Transform3D(mb, Vector3(c.x + off.x, my - _drop, c.z + off.z))
	for i in rings.size():
		var ring := rings[i]
		ring.rotation.y = _time * (0.4 + i * 0.25) * (1.0 if i % 2 == 0 else -1.0) * (0.5 + fury)
		ring.scale = Vector3.ONE * lerpf(0.75, 1.15, _open)
	gullet.set_instance_shader_parameter(&"intensity", 0.0 if _dead else 0.5 + fury * 1.5 + _open)
	# Debris orbit: the funnel's spiral current, faster near the throat, lifting when flung.
	var fling := w if (_action == "throw" and p >= 0.0) else 0.0
	for d: Array in debris:
		var node: MeshInstance3D = d[0]
		var r: float = d[1]
		var hf: float = d[2]
		d[3] = float(d[3]) + delta * _spin * float(d[4]) * (6.0 / maxf(r, 2.0))
		var a := float(d[3])
		var y := top - 0.2 - DEPTH * pow(clampf(1.0 - (r - 2.4) / (RIM - 2.4), 0.0, 1.0), 1.6) * 0.9 + hf * 0.6
		y += fling * sin(PI * clampf(p * 1.4 - hf * 0.3, 0.0, 1.0)) * 9.0
		var pos := Vector3(c.x + cos(a) * r, y, c.z + sin(a) * r)
		node.global_transform = Transform3D(Basis(Vector3.UP, -a) * Basis(Vector3.RIGHT, sin(_time + float(d[5])) * 0.5) * Basis(Vector3.FORWARD, float(d[5])), pos)
		node.visible = not _dead or _dead_t < 3.0
