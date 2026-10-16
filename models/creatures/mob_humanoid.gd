class_name MobHumanoid
extends BossHumanoid
## Base for the humanoid monsters (skeletons, archers, ghouls, the drowned,
## trolls). The HumanoidModel underneath still supplies the rig and the
## procedural animator (gait, attacks, hit reacts, death); its generic body is
## hidden and the monster is sculpted in the rig's rest space (body units, a
## 1.8 m human) instead:
##   * flesh: smooth skinned tubes and sculpted parts (MobRig) with the
##     creature skin shader (rotting hide, mottled troll skin, wet pallor...),
##     weights blended across joints so elbows and knees bend without seams
##   * gear and bones: BossKit parts (rusted plate, rags, rope, wood, bone)
##     merged into ONE skinned mesh per material and bound to the same bones
## so a mob draws in a handful of calls (one per material) and every mesh is
## cached per geometry variant: the second skeleton of a kind costs nothing
## to build.
##
## Subclasses implement _sculpt() with flesh_slot() / gear() / gput(), and
## provide the per-individual materials in _flesh_materials() / _gear_materials().

const R2 := preload("res://models/character/char_rig.gd")

static var _built_cache := {}   # key -> {"flesh": [[ArrayMesh, slot]], "gear": [[ArrayMesh, role]]}

## Geometry variant: everything that changes the meshes (kind, gear, proportions).
var variant := ""
var _rig: MobRig
var _gear_parts: Array = []   # [mesh, role, xform, tint, bone, bone2, w2]
var _mob_meshes: Array[MeshInstance3D] = []


func _init(style_dict := {}, variant_key := "") -> void:
	super(style_dict)
	variant = variant_key
	dissolve_delay = 1.4
	dissolve_time = 1.6
	durations["roar"] = 1.4
	durations["summon"] = 1.3


func _kit_key() -> String:
	return "mob_%s" % variant


func _lod_size() -> float:
	return float(style.get("height", 1.8))


func _ember_extents() -> Vector3:
	var h := float(style.get("height", 1.8))
	return Vector3(0.25, 0.5, 0.2) * h


## Override: build the geometry (called once per variant).
func _sculpt() -> void:
	pass


## Override: flesh materials per MobRig slot (per individual).
func _flesh_materials() -> Array:
	return []


## Override: gear materials by role (per individual).
func _gear_materials() -> Dictionary:
	return {}


## Override: extras per individual after the meshes (lights, particles, cloaks).
func _after_mob() -> void:
	pass


func _dress() -> void:
	var key := _kit_key()
	if not _built_cache.has(key):
		_rig = MobRig.new(6)
		for i in R2.BODY_BONES:
			_rig.bone(R2.NAMES[i], R2.PARENTS[i], _rest[i])
		_gear_parts.clear()
		_sculpt()
		var data := _rig.build(key + "_flesh")
		var src: ArrayMesh = data["mesh"]
		var slots: Array = data["slots"]
		var flesh: Array = []
		for si in slots.size():
			var surf := int(slots[si])
			if surf < 0:
				continue
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(surf), [], {}, MobRig.FORMAT_FLAGS)
			flesh.append([m, si])
		_built_cache[key] = {"flesh": flesh, "gear": _bake_gear()}
		_rig = null
		_gear_parts.clear()
	var built: Dictionary = _built_cache[key]
	var fm := _flesh_materials()
	for e: Array in built["flesh"]:
		var si: int = e[1]
		if si < fm.size():
			_mob_meshes.append(_skinned_mi(e[0], fm[si]))
	var gm := _gear_materials()
	for e: Array in built["gear"]:
		var role: String = e[1]
		if gm.has(role):
			var mi := _skinned_mi(e[0], gm[role])
			var sm := gm[role] as ShaderMaterial
			if sm != null and sm.shader == ModelKit.GLOW:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_mob_meshes.append(mi)
	_after_mob()


func _skinned_mi(mesh: ArrayMesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Mob"
	mi.mesh = mesh
	mi.material_override = mat
	mi.skin = body["skin"]
	skeleton.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.custom_aabb = AABB(Vector3(-1.6, -0.4, -1.6), Vector3(3.2, 3.0, 3.2))
	return mi


# --- Sculpting API (rest space, body units) ------------------------------------------------

## The flesh builder writing into material slot `i`.
func flesh_slot(i: int) -> MobRig:
	return _rig.slot(i)


## A rigid gear part following `bone` (optionally blended with bone2).
func gear(role: String, mesh: Mesh, b: int, xf := Transform3D.IDENTITY, tint := Color(1, 1, 1), bone2 := -1, w2 := 0.0) -> void:
	_gear_parts.append([mesh, role, xf, tint, b, bone2, w2])


func gput(role: String, mesh: Mesh, b: int, pos: Vector3, rot_deg := Vector3.ZERO, scl := Vector3.ONE, tint := Color(1, 1, 1)) -> void:
	var bas := Basis.from_euler(rot_deg * (PI / 180.0))
	if scl != Vector3.ONE:
		bas = bas.scaled_local(scl)
	gear(role, mesh, b, Transform3D(bas, pos), tint)


## Flesh limb through rest-space joints (see MobRig.limb), fused to `root`.
func flesh_limb(slot_i: int, joints: PackedVector3Array, seg_bones: Array, prof: Array, root := -1, rings := 16, sides := 12, blend := 0.06) -> void:
	var r := {} if root < 0 else {root: 1.0}
	var root_len := joints[0].distance_to(joints[1]) * 1.1 if root >= 0 else 0.0
	_rig.slot(slot_i).limb(joints, seg_bones, prof, rings, sides, Vector3.BACK, blend, r, root_len)


## Add every part of a BossKit assembly (built with any material) to `role` on `b`.
func take(asm: BossKit.Assembly, role: String, b: int) -> void:
	for p: Array in asm.parts:
		gear(role, p[0], b, p[2], p[3])


## Bake gear parts into one skinned mesh per role: UV = rest xy, UV2 = (rest z,
## part parameter), COLOR = tint (linear, alpha kept), bones from the part.
func _bake_gear() -> Array:
	var groups := {}
	var order: Array = []
	for p: Array in _gear_parts:
		var role: String = p[1]
		if not groups.has(role):
			groups[role] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "uv2": PackedVector2Array(),
				"c": PackedColorArray(), "b": PackedInt32Array(), "w": PackedFloat32Array(), "i": PackedInt32Array()}
			order.append(role)
		_append_part(groups[role], p)
	var out: Array = []
	for role: String in order:
		var g: Dictionary = groups[role]
		if (g["v"] as PackedVector3Array).is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g["v"]
		arrays[Mesh.ARRAY_NORMAL] = g["n"]
		arrays[Mesh.ARRAY_TEX_UV] = g["uv"]
		arrays[Mesh.ARRAY_TEX_UV2] = g["uv2"]
		arrays[Mesh.ARRAY_COLOR] = g["c"]
		arrays[Mesh.ARRAY_BONES] = g["b"]
		arrays[Mesh.ARRAY_WEIGHTS] = g["w"]
		arrays[Mesh.ARRAY_INDEX] = g["i"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.append([mesh, role])
	return out


static func _append_part(g: Dictionary, p: Array) -> void:
	var mesh: Mesh = p[0]
	var xf: Transform3D = p[2]
	var tint: Color = p[3]
	var b0: int = p[4]
	var b1: int = p[5] if int(p[5]) >= 0 else b0
	var w1: float = p[6] if int(p[5]) >= 0 else 0.0
	var lin := tint.srgb_to_linear()
	lin.a = tint.a
	var flip := xf.basis.determinant() < 0.0
	var nb := xf.basis.inverse().transposed()
	var gv: PackedVector3Array = g["v"]
	var gn: PackedVector3Array = g["n"]
	var guv: PackedVector2Array = g["uv"]
	var guv2: PackedVector2Array = g["uv2"]
	var gc: PackedColorArray = g["c"]
	var gb: PackedInt32Array = g["b"]
	var gw: PackedFloat32Array = g["w"]
	var gi: PackedInt32Array = g["i"]
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n := PackedVector3Array()
		if arr[Mesh.ARRAY_NORMAL] != null:
			n = arr[Mesh.ARRAY_NORMAL]
		var uv2 := PackedVector2Array()
		if arr[Mesh.ARRAY_TEX_UV2] != null:
			uv2 = arr[Mesh.ARRAY_TEX_UV2]
		var base := gv.size()
		for i in v.size():
			var q := xf * v[i]
			gv.append(q)
			gn.append((nb * n[i]).normalized() if n.size() > i else xf.basis.y.normalized())
			guv.append(Vector2(q.x, q.y))
			guv2.append(Vector2(q.z, uv2[i].y if uv2.size() > i else 0.0))
			gc.append(lin)
			gb.append_array([b0, b1, 0, 0])
			gw.append_array([1.0 - w1, w1, 0.0, 0.0])
		var ind: Variant = arr[Mesh.ARRAY_INDEX]
		var idx := PackedInt32Array()
		if ind == null or (ind as PackedInt32Array).is_empty():
			for i in v.size():
				idx.append(i)
		else:
			idx = ind
		for t in range(0, idx.size() - 2, 3):
			if flip:
				gi.append_array([base + idx[t], base + idx[t + 2], base + idx[t + 1]])
			else:
				gi.append_array([base + idx[t], base + idx[t + 1], base + idx[t + 2]])
	g["v"] = gv
	g["n"] = gn
	g["uv"] = guv
	g["uv2"] = guv2
	g["c"] = gc
	g["b"] = gb
	g["w"] = gw
	g["i"] = gi


func _build_held(item_id: String) -> void:
	if item_id == "sword_rusty":
		_rusty_sword()
	else:
		super._build_held(item_id)


## A notched, rust-eaten arming sword in the right hand (skeletons, the drowned).
func _rusty_sword() -> void:
	_held_id = "sword_rusty"
	if _held != null:
		_held.queue_free()
	_held = Node3D.new()
	_held.name = "Sword"
	grip_r.add_child(_held)
	var k := "mob_rusty_sword"
	var iron := BossKit.metal({"albedo": Color(0.55, 0.52, 0.48), "rust": 0.55, "wear": 0.6, "grime": 0.6, "roughness": 0.6})
	var leather := BossKit.leather({"albedo": Color(0.35, 0.25, 0.18)})
	var asm := BossKit.assembly()
	asm.add(BossKit.blade(k + "_blade", 0.68, [[0.0, 0.024, 0.006], [0.08, 0.026, 0.006], [0.55, 0.021, 0.005], [0.86, 0.016, 0.004], [1.0, 0.0, 0.002]], 0.4), iron, Transform3D(Basis(), Vector3(0, 0.115, 0)), Color(0.85, 0.8, 0.75))
	asm.add(OrganicMesh.profile(k + "_guard", Vector3(-0.09, 0, 0), Vector3(0.09, 0, 0), [[0.0, 0.012, 0.012], [0.15, 0.009, 0.01], [0.5, 0.012, 0.014], [0.85, 0.009, 0.01], [1.0, 0.012, 0.012]], 8, 8), iron, Transform3D(Basis(), Vector3(0, 0.105, 0)), Color(0.6, 0.55, 0.5))
	asm.add(BossKit.lathe(k + "_grip", PackedVector2Array([Vector2(0.014, -0.08), Vector2(0.016, -0.03), Vector2(0.016, 0.05), Vector2(0.014, 0.095)]), 8), leather, Transform3D.IDENTITY, Color(1, 1, 1))
	asm.add(OrganicMesh.blob(k + "_pommel", Vector3(0.022, 0.02, 0.016), 0.05, 3, 8), iron, Transform3D(Basis(), Vector3(0, -0.095, 0)), Color(0.6, 0.55, 0.5))
	bake_into(_held, "rsword", asm)
	_held_len = 0.8


## A helper transform: local +Y from `from` to `to` (BossHumanoid.along).
static func span(from: Vector3, to: Vector3, roll := 0.0) -> Transform3D:
	return BossHumanoid.along(from, to, roll)
