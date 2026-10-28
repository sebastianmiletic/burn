class_name SerpentChain
extends Node3D
## A long body (serpents, eels, sharks, centipedes) drawn as ONE smooth
## skinned tube and driven by a follow-the-leader chain in world space:
## the owner moves the head point, every joint is pulled after the one in
## front at a fixed spacing, buoyancy pulls joints towards a target height,
## and a travelling wave adds the swimming undulation on top (display only).
##
## Works identically on server and clients: it only needs the head path,
## which comes from the (interpolated) entity position.
##
##   var chain := SerpentChain.new()
##   chain.setup(mesh, material, bones, length)
##   add_child(chain); chain.reset(head, back_dir)
##   each frame: chain.simulate(head, delta); (tweak chain.display); chain.apply()
##   chain.attach(i, node) keeps `node` on joint i (fins, legs, head parts).

var bones := 16
var length := 10.0
var seg := 1.0
var skeleton: Skeleton3D
var mesh_instance: MeshInstance3D
## Physical joint positions (world), 0 = head end.
var points := PackedVector3Array()
## Positions actually shown (physics + undulation + overrides).
var display := PackedVector3Array()
## Per-joint orientation: x = side, y = up, z = towards the tail.
var frames: Array[Basis] = []

## Swimming wave: lateral amplitude (m) at the tail tip, waves along the body, speed (rad/s).
var wave_amp := 0.6
var wave_count := 1.4
var wave_speed := 3.0
## Vertical humps (sea-serpent loops breaking the surface), amplitude in metres.
var hump_amp := 0.0
var hump_count := 2.0
## Joints try to settle at this height (NAN = no buoyancy) at this rate.
var rest_height := NAN
var rest_rate := 1.5
## 0..1: how much each segment keeps the direction of the one in front (smooth curves).
var stiffness := 0.35
var head_up := Vector3.UP

## Uniform scale of every bone (the mesh's girth): a smaller copy of a long body whose
## joints the owner places closer together (KrakenModel's roaming kraken).
var bone_scale := 1.0
## Margin (m) added around the joints for the culling box (body radius + attachments).
var aabb_margin := 8.0

var _phase := 0.0
var _attached := {}  # joint index -> Array[Node3D]
var _ready_chain := false


func setup(mesh: ArrayMesh, material: Material, bone_count: int, body_length: float, aabb_extent := 80.0) -> SerpentChain:
	bones = bone_count
	length = body_length
	seg = length / float(bones - 1)
	top_level = true
	skeleton = Skeleton3D.new()
	skeleton.name = "Spine"
	add_child(skeleton)
	for i in bones:
		var b := skeleton.add_bone("b%d" % i)
		skeleton.set_bone_rest(b, Transform3D(Basis(), Vector3(0, 0, seg * i)))
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Body"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.custom_aabb = AABB(-Vector3.ONE * aabb_extent, Vector3.ONE * aabb_extent * 2.0)
	aabb_margin = clampf(aabb_extent * 0.1, 3.0, 12.0)
	skeleton.add_child(mesh_instance)
	mesh_instance.skeleton = NodePath("..")
	points.resize(bones)
	display.resize(bones)
	frames.resize(bones)
	for i in bones:
		frames[i] = Basis()
	return self


## Lay the chain out straight from `head` along `back` (direction towards the tail).
func reset(head: Vector3, back: Vector3) -> void:
	var b := back.normalized() if back.length_squared() > 1e-6 else Vector3.BACK
	for i in bones:
		points[i] = head + b * seg * i
		display[i] = points[i]
	_ready_chain = true
	_update_frames()


func attach(joint_index: int, node: Node3D) -> Node3D:
	if not _attached.has(joint_index):
		_attached[joint_index] = []
	(_attached[joint_index] as Array).append(node)
	add_child(node)
	return node


func simulate(head: Vector3, delta: float, speed := 1.0) -> void:
	if not _ready_chain:
		reset(head, Vector3.BACK)
	points[0] = head
	var prev_dir := Vector3.ZERO
	var k := 1.0 - exp(-rest_rate * delta)
	for i in range(1, bones):
		var p := points[i]
		if not is_nan(rest_height):
			p.y = lerpf(p.y, rest_height, k * (0.3 + 0.7 * float(i) / bones))
		var d := p - points[i - 1]
		if d.length_squared() < 1e-8:
			d = prev_dir if prev_dir != Vector3.ZERO else Vector3.BACK
		d = d.normalized()
		if prev_dir != Vector3.ZERO and stiffness > 0.0:
			d = d.lerp(prev_dir, stiffness).normalized()
		points[i] = points[i - 1] + d * seg
		prev_dir = d
	_phase += delta * wave_speed * clampf(speed, 0.15, 2.5)
	# Undulation (display only): sideways wave growing towards the tail, plus humps.
	_update_frames_from(points)
	for i in bones:
		var t := float(i) / (bones - 1)
		var lateral := sin(_phase - t * wave_count * TAU) * wave_amp * (0.15 + 0.85 * t)
		var hump := 0.0
		if hump_amp != 0.0:
			hump = maxf(0.0, sin(_phase * 0.6 - t * hump_count * TAU)) * hump_amp * smoothstep(0.05, 0.25, t) * (1.0 - smoothstep(0.75, 1.0, t))
		var side := frames[i].x
		side.y = 0.0
		display[i] = points[i] + side.normalized() * lateral + Vector3.UP * hump


## Pose the skeleton and attachments from `display` (call after any tweaks).
func apply() -> void:
	_update_frames_from(display)
	# The chain lives in world space at the origin: keep the culling box around
	# the joints (a fixed box at the origin culled bodies far from it).
	var lo := display[0]
	var hi := display[0]
	for i in range(1, bones):
		lo = lo.min(display[i])
		hi = hi.max(display[i])
	var m := Vector3.ONE * aabb_margin
	mesh_instance.custom_aabb = AABB(lo - m, hi - lo + m * 2.0)
	for i in bones:
		skeleton.set_bone_pose_position(i, display[i])
		skeleton.set_bone_pose_rotation(i, frames[i].get_rotation_quaternion())
		if bone_scale != 1.0:
			skeleton.set_bone_pose_scale(i, Vector3.ONE * bone_scale)
		var nodes: Variant = _attached.get(i)
		if nodes != null:
			for n: Node3D in nodes:
				n.global_transform = Transform3D(frames[i] if bone_scale == 1.0 else frames[i].scaled(Vector3.ONE * bone_scale), display[i])


func _update_frames() -> void:
	_update_frames_from(display)


func _update_frames_from(src: PackedVector3Array) -> void:
	var up := head_up
	for i in bones:
		var a := src[maxi(0, i - 1)]
		var b := src[mini(bones - 1, i + 1)]
		var z := b - a
		if z.length_squared() < 1e-8:
			z = frames[i].z if frames[i].z.length_squared() > 0.5 else Vector3.BACK
		z = z.normalized()
		var y := up - z * up.dot(z)
		if y.length_squared() < 1e-6:
			y = Vector3.UP - z * Vector3.UP.dot(z)
			if y.length_squared() < 1e-6:
				y = Vector3.RIGHT
		y = y.normalized()
		# Ease the roll back towards world-up so the belly stays down.
		var wy := Vector3.UP - z * Vector3.UP.dot(z)
		if wy.length_squared() > 1e-4:
			# Normalised lerp (slerp is undefined for nearly opposite vectors,
			# e.g. a short neck chain that folds over).
			var ly := y.lerp(wy.normalized(), 0.15)
			y = ly.normalized() if ly.length_squared() > 1e-6 else wy.normalized()
		var x := y.cross(z).normalized()
		frames[i] = Basis(x, y, z).orthonormalized()
		up = frames[i].y


func joint(i: int) -> Vector3:
	return display[clampi(i, 0, bones - 1)]


func frame(i: int) -> Basis:
	return frames[clampi(i, 0, bones - 1)]


func tail_tip() -> Vector3:
	return display[bones - 1]
