class_name MobModel
extends CreatureModel
## Base for creatures drawn as one smooth skinned body (MobRig): wolves,
## bears, deer, spiders, shades, imps... Subclasses build a MobRig in
## _build(), call rig_instance(), and every frame pose the bones in rig space
## (model space before `rig_scale`) with fk() / ik() / place(), then commit().
##
##   fk(neck, Vector3(pitch, yaw, roll))   # rotate relative to the parent
##   ik(thigh, shin, foot, target, pole)   # two-bone leg reaching `target`
##   place(root, pos, basis)               # set a bone directly
##   commit()                              # write the pose to the skeleton
##
## Bones must be posed parent-first (MobRig bones are created in that order).
## Rest rotations are identity, so Basis() is the rest pose of every bone.

var skel: Skeleton3D
var body_mi: MeshInstance3D
var rest := PackedVector3Array()
var parents := PackedInt32Array()
var bone_count := 0
var rig_scale := 1.0
## Pose of the current frame in rig space.
var gb: Array[Basis] = []
var gp := PackedVector3Array()


## Skeleton + skinned mesh from MobRig.build() data; `materials[i]` for slot i.
func rig_instance(data: Dictionary, materials: Array, scale := 1.0, aabb_pad := 1.0) -> MeshInstance3D:
	rig_scale = scale
	rest = data["rest"]
	parents = data["parents"]
	bone_count = rest.size()
	skel = Skeleton3D.new()
	skel.name = "Rig"
	skel.scale = Vector3.ONE * scale
	add_child(skel)
	var names: PackedStringArray = data["names"]
	for i in bone_count:
		skel.add_bone(names[i])
	for i in bone_count:
		var p := parents[i]
		if p >= 0:
			skel.set_bone_parent(i, p)
		skel.set_bone_rest(i, Transform3D(Basis(), rest[i] - (rest[p] if p >= 0 else Vector3.ZERO)))
	skel.reset_bone_poses()
	body_mi = MeshInstance3D.new()
	body_mi.name = "Body"
	body_mi.mesh = data["mesh"]
	body_mi.skin = data["skin"]
	skel.add_child(body_mi)
	body_mi.skeleton = NodePath("..")
	var slots: Array = data["slots"]
	for i in slots.size():
		if int(slots[i]) >= 0 and i < materials.size():
			body_mi.set_surface_override_material(int(slots[i]), materials[i])
	# Skinned meshes keep their rest bounds: pad them so poses (rearing,
	# leaping, dying on the side) are not culled.
	var ab: AABB = (data["mesh"] as ArrayMesh).get_aabb()
	body_mi.custom_aabb = ab.grow(maxf(ab.size.x, maxf(ab.size.y, ab.size.z)) * 0.5 * aabb_pad)
	gb.resize(bone_count)
	gp.resize(bone_count)
	for i in bone_count:
		gb[i] = Basis()
		gp[i] = rest[i]
	return body_mi


func _collect(node: Node) -> void:
	super._collect(node)
	if node == self and body_mi != null and not _geoms.has(body_mi):
		_geoms.append(body_mi)


func set_glow_intensity(v: float) -> void:
	super.set_glow_intensity(v)
	if body_mi != null:
		body_mi.set_instance_shader_parameter(&"intensity", v)


# --- Posing ----------------------------------------------------------------------------

## Set bone `b` directly (rig space).
func place(b: int, pos: Vector3, basis := Basis()) -> void:
	gp[b] = pos
	gb[b] = basis


## Bone `b` rotated by `euler` (radians, YXZ like Node3D) relative to its parent.
func fk(b: int, euler := Vector3.ZERO) -> void:
	var p := parents[b]
	if p < 0:
		gb[b] = Basis.from_euler(euler)
		return
	gb[b] = gb[p] * Basis.from_euler(euler)
	gp[b] = gp[p] + gb[p] * (rest[b] - rest[p])


## Like fk() with a basis relative to the parent.
func fkb(b: int, local: Basis) -> void:
	var p := parents[b]
	gb[b] = gb[p] * local
	gp[b] = gp[p] + gb[p] * (rest[b] - rest[p])


## Like fk() but the bone also moves by `offset` (in the parent's frame).
func fk_move(b: int, euler: Vector3, offset: Vector3) -> void:
	var p := parents[b]
	gb[b] = gb[p] * Basis.from_euler(euler)
	gp[b] = gp[p] + gb[p] * (rest[b] - rest[p] + offset)


## Two-bone IK: `upper` (already placed by fk) and its child `lower` bend so
## `end` (child of lower) reaches `target`; the middle joint bends towards
## `pole` (rig-space direction). Returns the middle joint position.
func ik(upper: int, lower: int, end: int, target: Vector3, pole: Vector3) -> Vector3:
	var hip := gp[upper]
	var d0 := rest[lower] - rest[upper]
	var d1 := rest[end] - rest[lower]
	var knee := ArachnidModel._ik_knee(hip, target, d0.length(), d1.length(), pole)
	var pb := gb[parents[upper]] if parents[upper] >= 0 else Basis()
	var pole_rest := pb.transposed() * pole
	gb[upper] = swing(d0, knee - hip, pole_rest, pole)
	gp[lower] = knee
	gb[lower] = swing(d1, target - knee, pole_rest, pole)
	gp[end] = knee + gb[lower] * d1
	return knee


## Point bone `b` (placed already) so its rest direction towards `child`
## follows `dir`, twisting so `pole_rest` maps near `pole`.
func aim(b: int, child: int, dir: Vector3, pole_rest: Vector3, pole: Vector3) -> void:
	gb[b] = swing(rest[child] - rest[b], dir, pole_rest, pole)


## Rotation taking direction d0 to d1, with p0 (perpendicular hint) going to p1.
static func swing(d0: Vector3, d1: Vector3, p0: Vector3, p1: Vector3) -> Basis:
	return _frame(d1, p1) * _frame(d0, p0).transposed()


static func _frame(d: Vector3, p: Vector3) -> Basis:
	var y := d.normalized() if d.length_squared() > 1e-10 else Vector3.UP
	var z := p - y * p.dot(y)
	if z.length_squared() < 1e-8:
		z = Vector3.BACK - y * Vector3.BACK.dot(y)
		if z.length_squared() < 1e-8:
			z = Vector3.RIGHT
	z = z.normalized()
	return Basis(y.cross(z), y, z)


## Write the pose to the skeleton.
func commit() -> void:
	for b in bone_count:
		var p := parents[b]
		if p < 0:
			skel.set_bone_pose(b, Transform3D(gb[b], gp[b]))
		else:
			var inv := gb[p].transposed()
			skel.set_bone_pose(b, Transform3D(inv * gb[b], inv * (gp[b] - gp[p])))


## Rig-space point -> model space.
func to_model(p: Vector3) -> Vector3:
	return p * rig_scale


## Model-space point -> rig space.
func to_rig(p: Vector3) -> Vector3:
	return p / rig_scale


## A node that follows bone `b` (eyes with their own material, particles).
func follow(b: int, node_name := "Follow") -> BoneAttachment3D:
	var a := BoneAttachment3D.new()
	a.name = node_name
	skel.add_child(a)
	a.bone_idx = b
	return a
