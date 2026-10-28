class_name HumanoidModel
extends CreatureModel
## Realistic procedural humanoid: players, villagers, skeletons, ghouls, trolls,
## the Warden, the Mountain King and Hades. One smooth skinned mesh per body
## shape (CharBody, cached and shared), a 24-bone rig (+25 cloak bones), and a
## procedural animator: speed-matched walk/run/sprint cycles with planted feet
## (two-bone leg IK), hip bob/sway/twist, counter-rotating shoulders, arm pump,
## lean into acceleration, banking into turns, head stabilisation, idle breathing
## and weight shifts; jump (crouch, stretch, tuck, reach), landing compression and
## heavy-landing kneel; weighty attack combos with weapon trails, mining, casting,
## a real dodge roll, directional hit reacts and a ragdoll-like death. Cloaks and
## capes are verlet-simulated (CharCloth). Movement dust comes from MoveFx.
##
## Owner contract (set every frame):
##   move_speed (m/s), grounded, velocity (world m/s), sprinting, ground_block
##   on_jump(), on_land(impact_speed) - optional; detected from `grounded` otherwise
##   footstep(strength) signal - play the step sound (0.3 walk .. 1 sprint)
##   terrain_probe: Callable(world_pos: Vector3) -> float ground height (NAN = unknown);
##       optional, lets feet plant on slopes/steps (sampled only when a foot plants).
##
## Style keys (all optional; colours are per instance, shapes are cached):
##   Colours: skin, hair, cloth (tunic/robe), cloth2 (trim, sash, tabard, hat, shield paint),
##     trousers, boots / leather (boots, belt, gloves, apron), metal / helmet_color / armor_color,
##     cloak_color, eyes (Color: glowing eyes), crown (Color: glowing crown)
##   Body: height (m, default 1.8), bulk (width), female, age (0..1: stoop, slower), gaunt,
##     muscle (0..1), belly (0..1), arm_length, hunch (radians, negative = stooped forward),
##     head_scale, jaw, brow, nose, cheeks, hands (scale), ears ("pointed")
##   Hair: hair_style ("short", "long", "bun", "ponytail", "topknot", "wild", "receding", "bald"),
##     beard (true/"full", "long", "goatee", "mustache")
##   Clothes: shirt ("none" = bare chest), sleeves ("long", "elbow", "short", "none"),
##     tunic_length (0 waist .. 1 knee), robe, sash, belt (default true), vest, collar, apron,
##     footwear ("boots", "tall", "shoes", "bare"), gloves, hood, cloak, cape, cloak_hem (y of the hem),
##     tattered (ragged cloak / rags), rags
##   Headwear: hat (true/"wide", "cap", "pointed"), helmet (true, "nasal", "kettle", "great",
##     "horned", "spangen"), plume, horns (horn_style "bull"/"ram"), tusks, crown, crown_fire
##   Armour: chainmail, plate, pauldrons, bracers (true / "metal"), greaves, tabard,
##     shield (true/"round", "kite")
##   Undead: skeleton (anatomical skeleton; `cloth` adds rags), decay (0..1 rotting skin)
##   Misc: held (item id), torch_shadows (held torch casts shadows)

signal footstep(strength: float)

## Profiling accumulators (usec) for tools: locomotion, pose, apply, cloth, fx. Empty = off.
static var prof := PackedInt64Array()

const R := preload("res://models/character/char_rig.gd")
const BOW_ITEMS := ["bow"]
const TWO_HANDED := ["pickaxe_stone", "pickaxe_iron", "pickaxe_obsidian", "giant_club", "scythe", "warden_blade"]
const HEAVY_LAND := 12.0

var style := {}
## Owner's world-space velocity (m/s).
var velocity := Vector3.ZERO
var sprinting := false
## In deep water: breaststroke when moving, treading water when still.
var swimming := false
## Where the owner wants the hips while swimming (model-local metres above the
## root; the centre of a swimmer's low hit box). Negative: the default height.
var swim_hips_height := -1.0
## Block id under the feet (dust colour, snow puffs). -1 unknown.
var ground_block := -1
## Optional ground height probe for foot planting: func(world_pos: Vector3) -> float (NAN = unknown).
var terrain_probe := Callable()
## Set false to suppress dust / trails (e.g. previews).
var fx_enabled := true

var body: Dictionary
var skeleton: Skeleton3D
var mesh_instance: MeshInstance3D
var grip_r: Node3D
var grip_l: Node3D
var head_attachment: BoneAttachment3D

var _root: Node3D
var _s := 1.0
var _b := 1.0
var _local := PackedVector3Array()
var _rest := PackedVector3Array()
var _cloth: CharCloth
var _cloak_first := -1

# Pose buffers (Euler targets / damped values per body bone).
var _tgt := PackedVector3Array()
var _cur := PackedVector3Array()
var _q: Array[Quaternion] = []
var _g: Array[Transform3D] = []
var _hips_tgt := Vector3.ZERO
var _hips_pos := Vector3.ZERO
var _hips_q_override := false
var _hips_q := Quaternion.IDENTITY
var _ik_w := 1.0
var _ik_target := 1.0
var _foot := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
var _foot_pitch := PackedFloat32Array([0.0, 0.0])
var _plant_y := PackedFloat32Array([0.0, 0.0])
var _next_plant_y := PackedFloat32Array([0.0, 0.0])
var _foot_phase_prev := PackedFloat32Array([0.0, 0.5])
var _arm_ik_w := 0.0
var _fing := PackedFloat32Array([0.3, 0.3])

# Locomotion state.
var _speed := 0.0
var _dir := Vector2(0, -1)
var _phase := 0.0
var _mv := 0.0
var _walk := 0.0
var _run := 0.0
var _sprint := 0.0
var _accel := 0.0
var _prev_fwd := 0.0
var _turn := 0.0
var _last_yaw := 0.0
var _bank := 0.0
var _air := 0.0
var _air_t := 0.0
var _vy := 0.0
var _prev_y := 0.0
var _was_grounded := true
var _takeoff_t := 9.0
var _land_t := 9.0
var _land_amt := 0.0
var _land_heavy := false
var _jump_lead := 1.0
var _jump_called_t := -9.0
var _land_called_t := -9.0
var _hunch := 0.0
var _age := 0.0
var _seed := 0.0
var _hit_side := 1.0
var _death_mode := 0
var _cast_hand := 1.0

# LOD.
var _lod_count := 0
var _hum_lod_acc := 0.0
var _near := true
var _cam_dist := 0.0

# Items and FX.
var _held_id := ""
var _held: Node3D
var _held_len := 0.8
var _offhand: Node3D
var _trail: SwingTrail
var _streaks: SpeedStreaks


func _init(style_dict := {}) -> void:
	style = style_dict
	# Humanoids run their own distance/frustum LOD in _animate (with cloth and IK).
	lod_enabled = false


func st(key: String, default: Variant) -> Variant:
	return style.get(key, default)


func _ember_extents() -> Vector3:
	return Vector3(0.3, 0.8, 0.25) * _s * Vector3(_b, 1.0, _b)


## Mesh statistics for the current style (perf reporting).
func triangle_count() -> int:
	return int(body.get("tris", 0))


# --- Owner wiring (enemies, villagers, bosses) -------------------------------------

## Feed a model from its owning entity every frame. Safe for any CreatureModel
## (non-humanoids are ignored). Footsteps play quiet, surface-matched step sounds.
static func drive(model: Node, owner: Entity, vel: Vector3, on_ground := true, sprint := false) -> void:
	var h := model as HumanoidModel
	if h == null:
		return
	h.velocity = vel
	h.sprinting = sprint
	h.grounded = on_ground
	if not h.has_meta(&"step_wired"):
		h.set_meta(&"step_wired", true)
		h.footstep.connect(func(strength: float) -> void: _owner_step(owner, h, strength))
		if not h.terrain_probe.is_valid():
			h.terrain_probe = func(p: Vector3) -> float: return ground_probe(owner, p)


## Smooth ground height under a world point for foot IK (NAN when unknown).
static func ground_probe(owner: Node, p: Vector3) -> float:
	var e := owner as Entity
	if e == null or not is_instance_valid(e):
		return NAN
	var vw := e.voxels()
	if vw == null:
		return NAN
	var g := vw.ground_below(p.x, p.y + 0.8, p.z, 1.6)
	return g if absf(g) < 1e6 else NAN


static func step_sound(block: int) -> String:
	match block:
		Blocks.GRASS, Blocks.DIRT, Blocks.DRY_GRASS, Blocks.MUD, Blocks.LEAVES:
			return "step_grass"
		Blocks.PLANKS, Blocks.LOG, Blocks.THATCH:
			return "step_wood"
		Blocks.SNOW, Blocks.ICE:
			return "step_snow"
		Blocks.SAND, Blocks.ASH, Blocks.GRAVEL, Blocks.SOUL_SAND:
			return "step_sand"
	return "step_stone"


static func _owner_step(owner: Entity, h: HumanoidModel, strength: float) -> void:
	if not is_instance_valid(owner) or not owner.is_inside_tree():
		return
	var pos := owner.global_position
	var vw := owner.voxels()
	if vw != null:
		h.ground_block = vw.get_block(Vector3i((pos - Vector3(0, 0.2, 0)).floor()))
	var gw := GameWorld.instance
	if gw != null and gw.local_player != null and gw.local_player.global_position.distance_to(pos) > 22.0 * maxf(1.0, h._s):
		return
	var big := clampf(h._s, 1.0, 3.5)
	var audio := owner.get_node_or_null(^"/root/Audio")
	if audio != null:
		audio.call(&"play", step_sound(h.ground_block), pos, -17.0 + 6.0 * strength + 4.0 * (big - 1.0), randf_range(0.92, 1.08) / sqrt(big))


# --- Construction ----------------------------------------------------------------

func _resolve_style() -> void:
	# Fill in body-shape defaults implied by the older, coarser keys.
	var bulk := float(st("bulk", 1.0))
	if bulk > 1.5 and not style.has("muscle"):
		style["muscle"] = 0.8
		if not style.has("belly"):
			style["belly"] = 0.5
		if not style.has("hands"):
			style["hands"] = 1.25
	if st("skeleton", false) and st("cloth", null) != null and not style.has("rags"):
		style["rags"] = true
		style["tattered"] = true
	if st("gaunt", false) and not style.has("decay") and not st("skeleton", false):
		style["decay"] = 0.6
		if not style.has("hair_style"):
			style["hair_style"] = "wild"
		if not style.has("shirt"):
			style["shirt"] = "none"
		if not style.has("footwear"):
			style["footwear"] = "bare"
		if not style.has("rags"):
			style["rags"] = true
			style["tattered"] = true
	if st("tusks", false) and not style.has("shirt") and bulk > 1.5 and float(st("height", 1.8)) < 4.0:
		style["shirt"] = "none"
		style["tunic_length"] = 0.5
	if st("robe", false) and not style.has("sleeves"):
		style["sleeves"] = "long"
	if st("hood", false) and not style.has("hair_style") and st("hair", null) == null:
		style["hair_style"] = "none"


func _build() -> void:
	_resolve_style()
	_s = float(st("height", 1.8)) / 1.8
	_b = float(st("bulk", 1.0))
	_age = float(st("age", 0.0))
	_hunch = float(st("hunch", 0.0)) - 0.25 * _age * _age
	_seed = float(absi(hash(str(get_instance_id()))) % 1000) / 1000.0
	# Meshes are generated off the main thread in the game (headless tools build at once).
	body = CharBody.body_for(style, DisplayServer.get_name() != "headless")
	_rest = body["rest"]
	_local = body["local"]
	_root = Node3D.new()
	_root.name = "Body"
	_root.scale = Vector3.ONE * _s
	add_child(_root)
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton"
	var names: PackedStringArray = body["names"]
	var parents: PackedInt32Array = body["parents"]
	for i in names.size():
		skeleton.add_bone(names[i])
	for i in names.size():
		skeleton.set_bone_parent(i, parents[i])
		skeleton.set_bone_rest(i, Transform3D(Basis.IDENTITY, _local[i]))
	skeleton.reset_bone_poses()
	_root.add_child(skeleton)
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.skin = body["skin"]
	skeleton.add_child(mesh_instance)
	mesh_instance.skeleton = NodePath("..")
	mesh_instance.custom_aabb = AABB(Vector3(-1.4, -0.4, -1.4), Vector3(2.8, 2.8, 2.8))
	_attach_mesh()

	# Attachments.
	for side in 2:
		var hand := R.HAND_L if side == 0 else R.HAND_R
		var att := BoneAttachment3D.new()
		att.name = "HandL" if side == 0 else "HandR"
		skeleton.add_child(att)
		att.bone_idx = hand
		var grip := Node3D.new()
		grip.name = "Grip"
		var sg := -1.0 if side == 0 else 1.0
		grip.position = Vector3(-sg * 0.012, -0.082, -0.004) * float(st("hands", 1.0))
		grip.rotation_degrees = Vector3(-90, 0, 0)
		att.add_child(grip)
		if side == 0:
			grip_l = grip
		else:
			grip_r = grip
	head_attachment = BoneAttachment3D.new()
	head_attachment.name = "HeadAtt"
	skeleton.add_child(head_attachment)
	head_attachment.bone_idx = R.HEAD
	if st("crown", null) != null and st("crown_fire", false):
		var top: Vector3 = body.get("head_top", Vector3(0, 1.82, 0))
		var flames := ModelKit.embers(head_attachment, 30, Vector3(0.12, 0.04, 0.12), 0.7, 0.18, 1.6)
		flames.position = top - _rest[R.HEAD] + Vector3(0, 0.03, 0)
		flames.emitting = true

	# Cloak simulation.
	_cloak_first = int(body["cloak_first"])
	if _cloak_first >= 0:
		_cloth = CharCloth.new()
		_cloth.setup(body["cloak_rest"], R.CLOAK_COLS, R.CLOAK_ROWS, _s)

	# Pose buffers.
	_tgt.resize(R.BODY_BONES)
	_cur.resize(R.BODY_BONES)
	_q.resize(R.BODY_BONES)
	_g.resize(R.BODY_BONES)
	for i in R.BODY_BONES:
		_q[i] = Quaternion.IDENTITY
	_hips_pos = _rest[R.HIPS]
	_hips_tgt = _hips_pos
	for side in 2:
		_foot[side] = _rest[R.FOOT_L if side == 0 else R.FOOT_R]
	var start_item: String = st("held", "")
	if start_item != "":
		_build_held(start_item)


## Give the MeshInstance its mesh once the (possibly background) build is done.
func _attach_mesh() -> bool:
	if mesh_instance.mesh != null:
		return true
	if not CharBody.poll(body):
		return false
	mesh_instance.mesh = body["mesh"]
	var roles: Array = body["glow_roles"]
	for i in roles.size():
		var c: Color = st("eyes", Color(1, 0.4, 0.1)) if roles[i] == "eyes" else st("crown", Color(1, 0.8, 0.3))
		var m := ModelKit.glow(c, 6.0 if roles[i] == "eyes" else 4.0, 0.0 if roles[i] == "eyes" else 0.4)
		mesh_instance.set_surface_override_material(i + 1, m)
	_apply_palette()
	if not roles.is_empty() and not _glows.has(mesh_instance) and _built:
		_glows.append(mesh_instance)
	if _built:
		# Re-apply per-instance state the mesh missed while it was building.
		_set_param(&"burn", _burn)
		set_glow_intensity(_glow_intensity)
	return true


## Local first-person view: fragments within this radius of the camera are cut
## away (the head and hood), so the eye camera never sees the inside of the face.
var _fp_radius := 0.0


func set_first_person(on: bool) -> void:
	# In first person the local body is never drawn for its own camera (no
	# clipping, no hollow neck, no cloak in the face) but still casts its
	# shadow; the camera's Viewmodel draws the arms and the held item.
	_fp_radius = 0.0
	_first_person = on
	_apply_first_person()


var _first_person := false


func _apply_first_person() -> void:
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if _first_person else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for g: GeometryInstance3D in find_children("*", "GeometryInstance3D", true, false):
		if g is GPUParticles3D:
			continue
		g.cast_shadow = mode


## Linear-ish palette for the shared character material (also used by the
## first-person arms so they match the body).
func palette_colors() -> Dictionary:
	var skel: bool = st("skeleton", false)
	var cloth: Color = st("cloth", Color(0.3, 0.25, 0.2)) if st("cloth", null) != null else Color(0.3, 0.25, 0.2)
	var cols := {
		&"c_skin": Color(0.8, 0.76, 0.66) if skel else st("skin", Color(0.78, 0.6, 0.48)),
		&"c_hair": st("hair", Color(0.16, 0.11, 0.07)) if st("hair", null) != null else Color(0.16, 0.11, 0.07),
		&"c_cloth": cloth,
		&"c_cloth2": st("cloth2", Color(0.5, 0.25, 0.12)),
		&"c_trousers": st("trousers", cloth.darkened(0.3)),
		&"c_leather": st("leather", st("boots", Color(0.22, 0.14, 0.09))),
		&"c_metal": st("metal", st("armor_color", st("helmet_color", Color(0.5, 0.5, 0.52)))),
		&"c_cloak": st("cloak_color", cloth.darkened(0.15)),
	}
	if st("apron", false) and not style.has("leather"):
		cols[&"c_leather"] = Color(0.36, 0.23, 0.13)
	return cols


func _apply_palette() -> void:
	var cols := palette_colors()
	for k: StringName in cols:
		var c: Color = cols[k]
		var lin := c.srgb_to_linear()
		mesh_instance.set_instance_shader_parameter(k, Vector3(lin.r, lin.g, lin.b))
	mesh_instance.set_instance_shader_parameter(&"fp_hide", _fp_radius)
	if _first_person:
		_apply_first_person.call_deferred()


func _collect(node: Node) -> void:
	super._collect(node)
	if node == self and mesh_instance != null:
		_geoms.append(mesh_instance)
		if mesh_instance.mesh != null and not (body.get("glow_roles", []) as Array).is_empty():
			_glows.append(mesh_instance)


# --- Items ------------------------------------------------------------------------

func set_held(item_id: String) -> void:
	if item_id == _held_id:
		return
	if not _built:
		style["held"] = item_id
		return
	_build_held(item_id)
	refresh_parts()
	if _first_person:
		_apply_first_person()


func _build_held(item_id: String) -> void:
	_held_id = item_id
	if _held != null:
		_held.queue_free()
		_held = null
	if item_id == "":
		return
	_held = HeldItems.build(item_id, 1.0, bool(st("torch_shadows", false)))
	if _held == null:
		return
	(grip_l if item_id in BOW_ITEMS else grip_r).add_child(_held)
	# Length of the item along its +Y axis (for the swing trail).
	var top := 0.3
	for c in _held.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var bb := mi.transform * mi.get_aabb()
			top = maxf(top, bb.end.y)
	_held_len = top
	var t: Color = ItemDB.color(item_id) if ItemDB.exists(item_id) else Color(1.0, 0.7, 0.4)
	if item_id.begins_with("sword_ember") or item_id.begins_with("sword_dragonbone"):
		t = Color(1.0, 0.55, 0.2)
	if _trail != null:
		_trail.set_color(t.lerp(Color(1.0, 0.75, 0.45), 0.5))


func held_item() -> String:
	return _held_id


func set_offhand_light(on: bool) -> void:
	if not _built:
		return
	if on and _offhand == null:
		_offhand = HeldItems.build("torch", 1.0, bool(st("torch_shadows", false)))
		grip_l.add_child(_offhand)
		refresh_parts()
	elif not on and _offhand != null:
		_offhand.queue_free()
		_offhand = null
		refresh_parts()


# --- Owner hooks ------------------------------------------------------------------

## Take-off: stretch from a crouch, dust burst at the feet.
func on_jump() -> void:
	var now := _time
	if now - _jump_called_t < 0.15:
		return
	_jump_called_t = now
	_takeoff_t = 0.0
	_air_t = 0.0
	_land_t = 9.0
	# Lead with whichever leg is swinging forward.
	_jump_lead = -1.0 if fposmod(_phase, 1.0) > 0.5 else 1.0
	if fx_enabled and _near and is_inside_tree():
		MoveFx.takeoff(self, global_position, ground_block, 0.6 + 0.4 * _run)


## Touch-down. impact_speed = downward speed in m/s; above 12 is a heavy, kneeling landing.
func on_land(impact_speed: float) -> void:
	var now := _time
	if now - _land_called_t < 0.15:
		return
	_land_called_t = now
	_land_t = 0.0
	_land_amt = clampf(impact_speed / 10.0, 0.15, 1.0)
	_land_heavy = impact_speed > HEAVY_LAND
	_takeoff_t = 9.0
	if fx_enabled and _near and is_inside_tree() and impact_speed > 3.0:
		MoveFx.landing(self, global_position, impact_speed, ground_block)


func _on_action(action_name: String) -> void:
	match action_name:
		"jump":
			on_jump()
		"hit":
			_hit_side = -1.0 if randf() < 0.5 else 1.0
		"cast", "throw":
			_cast_hand = 1.0
		"die":
			var r := fposmod(_seed * 7.31 + _time, 1.0)
			_death_mode = 0 if r < 0.5 else (1 if r < 0.8 else 2)


func set_dead(is_dead: bool) -> void:
	super.set_dead(is_dead)
	if not is_dead:
		_hips_q_override = false
		if _cloth != null:
			_cloth.reset(Transform3D.IDENTITY, Vector3.ZERO)
			_cloth = CharCloth.new()
			_cloth.setup(body["cloak_rest"], R.CLOAK_COLS, R.CLOAK_ROWS, _s)


# --- Animation --------------------------------------------------------------------

func _update_lod(delta: float) -> bool:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var interval := 1
	if cam != null:
		var head := global_position + Vector3(0, 1.0 * _s, 0)
		_cam_dist = cam.global_position.distance_to(head) / maxf(0.6, sqrt(_s))
		var on_screen := _cam_dist < 4.0 or cam.is_position_in_frustum(head)
		if not on_screen:
			interval = 8
		elif _cam_dist > 60.0:
			interval = 4
		elif _cam_dist > 28.0:
			interval = 2
		_near = on_screen and _cam_dist < 28.0
	else:
		_near = true
	_hum_lod_acc += delta
	_lod_count += 1
	if _lod_count < interval:
		return false
	_lod_count = 0
	return true


func _animate(delta: float) -> void:
	if mesh_instance.mesh == null:
		_attach_mesh()
	if not _update_lod(delta):
		return
	var dt := minf(_hum_lod_acc, 0.25)
	_hum_lod_acc = 0.0
	if prof.is_empty():
		_locomotion(dt)
		_pose(dt)
		_apply(dt)
		if _cloth != null:
			_cloak_step(dt)
		_fx(dt)
		return
	var t0 := Time.get_ticks_usec()
	_locomotion(dt)
	var t1 := Time.get_ticks_usec()
	_pose(dt)
	var t2 := Time.get_ticks_usec()
	_apply(dt)
	var t3 := Time.get_ticks_usec()
	if _cloth != null:
		_cloak_step(dt)
	var t4 := Time.get_ticks_usec()
	_fx(dt)
	var t5 := Time.get_ticks_usec()
	prof[0] += t1 - t0
	prof[1] += t2 - t1
	prof[2] += t3 - t2
	prof[3] += t4 - t3
	prof[4] += t5 - t4


func _locomotion(dt: float) -> void:
	var gb := global_transform.basis
	var v := velocity
	if v == Vector3.ZERO and move_speed > 0.05:
		v = gb * Vector3(0, 0, -move_speed)
	var vl := gb.inverse() * v
	var hv := Vector2(vl.x, vl.z)
	var spd := hv.length() / _s
	_speed = damp(_speed, spd, 10.0, dt)
	if spd > 0.25:
		_dir = _dir.lerp(hv.normalized(), 1.0 - exp(-10.0 * dt)).normalized()
	else:
		_dir = _dir.lerp(Vector2(0, -1), 1.0 - exp(-2.0 * dt)).normalized()
	_mv = damp(_mv, smoothstep(0.12, 0.8, spd), 9.0, dt)
	_walk = _mv
	_run = damp(_run, smoothstep(2.2, 4.2, spd), 6.0, dt)
	var want_sprint := 1.0 if (sprinting or spd > 6.3) and spd > 4.0 else 0.0
	_sprint = damp(_sprint, want_sprint, 5.0, dt)
	var fwd := -vl.z / _s
	_accel = damp(_accel, clampf((fwd - _prev_fwd) / maxf(dt, 0.001), -30.0, 30.0), 5.0, dt)
	_prev_fwd = fwd
	var z := gb.z
	var yaw := atan2(z.x, z.z)
	_turn = damp(_turn, angle_difference(_last_yaw, yaw) / maxf(dt, 0.001), 8.0, dt)
	_last_yaw = yaw
	_bank = damp(_bank, clampf(_turn * _speed * 0.045, -0.32, 0.32), 6.0, dt)
	# Vertical motion: from the owner's velocity, or measured.
	var gy := global_position.y
	var vy := velocity.y if velocity != Vector3.ZERO else (gy - _prev_y) / maxf(dt, 0.001)
	_prev_y = gy
	_vy = vy
	# Detect take-off / touch-down when the owner does not call the hooks.
	if _was_grounded and not grounded and vy > 2.0 and _time - _jump_called_t > 0.3:
		on_jump()
	if not _was_grounded and grounded and _time - _land_called_t > 0.3 and _air_t > 0.25:
		on_land(-minf(vy, 0.0) if velocity != Vector3.ZERO else _air_t * 7.0)
	_was_grounded = grounded
	_air = damp(_air, 0.0 if grounded else 1.0, 14.0 if grounded else 9.0, dt)
	if not grounded:
		_air_t += dt
	else:
		_air_t = 0.0
	_takeoff_t += dt
	_land_t += dt
	# Gait phase: cadence rises with speed so strides stay within reach.
	var cadence := clampf(1.7 + 0.3 * _speed, 1.7, 4.0)
	_phase = fposmod(_phase + dt * cadence * 0.5, 1.0)


## Horizontal offset (+ ahead), lift and pitch of a foot at gait phase ph.
func _foot_cycle(ph: float, stride: float, duty: float) -> Vector3:
	var travel := minf(stride * duty, 0.95)
	var ahead := lerpf(0.5, 0.42, _run)
	if ph < duty:
		var f := ph / duty
		var along := lerpf(travel * ahead, -travel * (1.0 - ahead), f)
		var pitch := -0.75 * smoothstep(0.6, 1.0, f) * (0.6 + 0.4 * _run) + 0.22 * (1.0 - smoothstep(0.0, 0.18, f)) * (1.0 - _run)
		return Vector3(along, 0.0, pitch)
	var s := (ph - duty) / (1.0 - duty)
	var e := s * s * (3.0 - 2.0 * s)
	var along2 := lerpf(-travel * (1.0 - ahead), travel * ahead, e)
	var lift := lerpf(0.075, 0.2, _run) + 0.06 * _sprint
	var y := lift * sin(PI * pow(s, 0.85))
	# Running: heel kicks up behind early in the swing.
	y += _run * 0.2 * sin(PI * minf(1.0, s * 1.7)) * (1.0 - s)
	var pitch2 := lerpf(-0.7, 0.3, smoothstep(0.0, 0.85, s))
	return Vector3(along2, y, pitch2)


func _pose(dt: float) -> void:
	var t := _tgt
	for i in R.BODY_BONES:
		t[i] = Vector3.ZERO
	var mv := _mv
	var idle := 1.0 - mv
	var stride := _speed / maxf(clampf(1.7 + 0.3 * _speed, 1.7, 4.0) * 0.5, 0.01)
	var duty := lerpf(0.62, 0.34, _run)
	var dir3 := Vector3(_dir.x, 0, _dir.y)
	var side_v := Vector3(-dir3.z, 0, dir3.x)
	var hips := _rest[R.HIPS]
	var hips_rot := Vector3.ZERO

	# --- Legs (IK targets) and pelvis -----------------------------------------
	var fw := PackedFloat32Array([0.0, 0.0])
	for side in 2:
		var ph := fposmod(_phase + (0.0 if side == 0 else 0.5), 1.0)
		var c := _foot_cycle(ph, stride, duty)
		var travel := maxf(minf(stride * duty, 0.95), 0.01)
		fw[side] = c.x / (travel * 0.5)
		var base := _rest[R.FOOT_L if side == 0 else R.FOOT_R]
		var sg := -1.0 if side == 0 else 1.0
		base.x *= lerpf(1.08, 0.6, _run * mv)
		var p := base + dir3 * c.x * mv + Vector3(0, c.y * mv, 0)
		# Feet settle slightly apart and one forward when idle (weight shift).
		var shift := sin(_time * 0.37 + _seed * 9.0)
		p += Vector3(sg * 0.012, 0, -0.03 * sg * shift) * idle
		# Ground height under the foot (only sampled at plant time).
		var prev_ph := _foot_phase_prev[side]
		if ph < duty and (prev_ph >= duty or ph < prev_ph):
			_plant_y[side] = _next_plant_y[side]
			if grounded and mv > 0.35 and _air < 0.3:
				_on_plant(side, p)
		elif ph >= duty and prev_ph < duty:
			_next_plant_y[side] = _probe(p + dir3 * stride * 0.5 * mv)
		_foot_phase_prev[side] = ph
		var gy := _plant_y[side]
		if ph >= duty:
			var s := (ph - duty) / (1.0 - duty)
			gy = lerpf(_plant_y[side], _next_plant_y[side], smoothstep(0.2, 0.9, s))
		p.y += gy * mv + (_plant_y[side] * idle)
		_foot[side] = p
		_foot_pitch[side] = c.z * mv
	# Pelvis: bob, sway, twist, drop on the swing side, lean, bank.
	var ph0 := _phase
	var mid := cos(TAU * 2.0 * (ph0 - duty * 0.5))
	hips.y += (0.022 * (1.0 - _run) - 0.04 * _run) * mid * mv
	hips.y -= (0.035 * _run + 0.03 * _sprint) * mv
	hips += side_v * (-0.022 * cos(TAU * (ph0 - duty * 0.5)) * (1.0 - _run) * mv)
	hips_rot.y = -lerpf(0.09, 0.13, _run) * cos(TAU * ph0) * mv
	hips_rot.z = 0.045 * cos(TAU * (ph0 - (1.0 + duty) * 0.5)) * (1.0 - 0.5 * _run) * mv
	hips_rot.x = -(0.05 * _run + 0.05 * _sprint) * mv
	var shift_i := sin(_time * 0.37 + _seed * 9.0)
	hips.x += 0.018 * shift_i * idle
	hips_rot.z += -0.03 * shift_i * idle
	hips_rot.z += _bank
	hips.y += sin(_time * 1.6 + _seed) * 0.003 * idle
	# Lowest foot pulls the pelvis down (slopes, stairs).
	var low := minf(_foot[0].y - _rest[R.FOOT_L].y, _foot[1].y - _rest[R.FOOT_R].y)
	hips.y += minf(low, 0.0) * 0.9 + maxf(low, 0.0)

	# --- Spine, head --------------------------------------------------------------
	var lean := -(0.05 * mv + 0.12 * _run * mv + 0.14 * _sprint) - clampf(_accel * 0.02, -0.12, 0.18)
	var breathe := sin(_time * 1.6 + _seed * 3.0)
	t[R.SPINE] = Vector3(lean * 0.5 + _hunch * 0.6 + breathe * 0.01 * idle, -hips_rot.y * 0.5, -_bank * 0.15)
	t[R.CHEST] = Vector3(lean * 0.5 + _hunch * 0.4 + breathe * 0.022 * idle, -hips_rot.y * (1.1 + 0.3 * _run), -_bank * 0.2)
	t[R.NECK] = Vector3(0, 0, 0)
	var look := sin(_time * 0.23 + _seed * 5.0) * 0.16 * idle
	t[R.HEAD] = Vector3(sin(_time * 0.17 + _seed) * 0.04 * idle, look, 0)

	# --- Arms ---------------------------------------------------------------------
	var amp := (0.32 + 0.3 * _run + 0.35 * _sprint) * mv
	for side in 2:
		var sg := -1.0 if side == 0 else 1.0
		var o := 0 if side == 0 else 5
		var f := fw[side]  # same-side leg forwardness; the arm swings opposite
		var out := sg * (0.07 + 0.09 * (_b - 1.0) + 0.04 * _run + 0.03 * idle)
		t[R.UARM_L + o] = Vector3(-f * amp + 0.06 * _run + breathe * 0.012 * idle, -sg * 0.18 * _run * mv, out)
		var pump := maxf(0.0, -f) * (0.25 + 0.45 * _run) * mv
		t[R.FARM_L + o] = Vector3(0.14 + 1.15 * _run * mv + 0.25 * _sprint + pump, 0, 0)
		t[R.CLAV_L + o] = Vector3(-f * 0.06 * _run * mv, 0, -sg * 0.015 * breathe * idle)
		t[R.HAND_L + o] = Vector3(0.12, 0, sg * 0.05)
		_fing[side] = lerpf(0.3, 0.75, _run * mv) + 0.4 * _sprint
	# Carrying: weapon or tool held up a little; torch held forward in the off hand.
	if _held_id != "":
		if _held_id in BOW_ITEMS:
			t[R.UARM_L] += Vector3(0.1, 0, 0)
			t[R.FARM_L] += Vector3(0.35, 0, 0)
			_fing[0] = 1.35
		else:
			t[R.UARM_R] += Vector3(0.12 * idle + 0.05, 0, 0.02)
			t[R.FARM_R] += Vector3(0.5 * idle + 0.25, 0, 0)
			t[R.HAND_R] += Vector3(-0.15, 0, 0)
			_fing[1] = 1.35
	if _offhand != null:
		t[R.UARM_L] = t[R.UARM_L].lerp(Vector3(0.45, 0.1, -0.15), 0.8)
		t[R.FARM_L] = Vector3(1.05, 0, 0)
		_fing[0] = 1.35

	_hips_tgt = hips
	_hips_q_override = false
	_ik_target = 1.0
	_arm_ik_w = damp(_arm_ik_w, 0.0, 10.0, dt)

	# --- Airborne, take-off and landing -------------------------------------------
	_pose_air_land(t, hips_rot)
	_swim_w = damp(_swim_w, 1.0 if swimming and not _dead else 0.0, 5.0, dt)
	if _swim_w > 0.01:
		_pose_swim(t)
	# --- One-shot actions -----------------------------------------------------------
	var p := action_progress()
	if _dead:
		_pose_dead(t, hips_rot)
	elif p >= 0.0:
		_pose_action(_action, p, action_weight(0.1, 0.22), t, hips_rot)
	# Head stabilisation: keep the eyes level and looking where we go.
	if not _dead:
		var pitch := hips_rot.x + t[R.SPINE].x + t[R.CHEST].x
		var yaw_sum := hips_rot.y + t[R.SPINE].y + t[R.CHEST].y
		var roll := hips_rot.z + t[R.SPINE].z + t[R.CHEST].z
		t[R.NECK] += Vector3(-pitch * 0.4, -yaw_sum * 0.35, -roll * 0.4)
		t[R.HEAD] += Vector3(-pitch * 0.45, -yaw_sum * 0.45, -roll * 0.5)
	t[R.HIPS] = hips_rot
	_ik_w = damp(_ik_w, _ik_target, 16.0, dt)


var _swim_w := 0.0


## Swimming: the body lies flat into a breaststroke with a flutter kick as it
## moves (a front crawl, arms windmilling in turn, when fast); still, it hangs
## upright treading water with sculling hands and a slow bicycle kick.
func _pose_swim(t: PackedVector3Array) -> void:
	var w := _swim_w
	var mvn := clampf(_speed * _s / 2.6, 0.0, 1.0)
	var cyc := _time * lerpf(2.4, 3.6, mvn)
	var stroke := sin(cyc)
	var crawl := smoothstep(2.9, 3.8, _speed * _s)
	# Flat in the water whether moving or still (the swimmer's hit box is low
	# and level); still, the chest rides a little higher for treading.
	var lie := lerpf(-1.2, -1.45, mvn) if swim_hips_height >= 0.0 else lerpf(-0.18, -1.45, mvn)
	_hips_q_override = true
	_hips_q = Quaternion.IDENTITY.slerp(Quaternion.from_euler(Vector3(lie, 0, 0)), w)
	var hips := _rest[R.HIPS] + Vector3(0, -0.05 - 0.25 * mvn, 0.0)
	if swim_hips_height >= 0.0:
		hips = Vector3(_rest[R.HIPS].x, swim_hips_height / _s, _rest[R.HIPS].z)
	_hips_tgt = _hips_tgt.lerp(hips, w)
	_ik_target = lerpf(_ik_target, 0.0, w)
	_ik_w = lerpf(_ik_w, 0.0, w)
	var kick := sin(cyc * 2.0)
	for side in 2:
		var sg := -1.0 if side == 0 else 1.0
		var o := 0 if side == 0 else 5
		var lo := 0 if side == 0 else 4
		var thigh := Vector3(0.25 * (1.0 - mvn) + sg * kick * lerpf(0.25, 0.35, mvn), 0, sg * -0.06)
		var shin := Vector3(-0.35 - 0.3 * maxf(0.0, sg * kick) - 0.25 * (1.0 - mvn), 0, 0)
		t[R.THIGH_L + lo] = t[R.THIGH_L + lo].lerp(thigh, w)
		t[R.SHIN_L + lo] = t[R.SHIN_L + lo].lerp(shin, w)
		# Arms: reach forward and sweep out (moving), or scull at the sides (treading).
		var reach := Vector3(1.9 + 0.5 * stroke, sg * 0.1, sg * (-0.25 - 0.7 * maxf(0.0, -stroke)))
		# Front crawl: the arm circles over (shoulder pitch through a full turn).
		var arm_ph := cyc * 0.5 + side * PI
		var wind := Vector3(1.55 + 1.45 * sin(arm_ph), sg * 0.15 * cos(arm_ph), sg * (-0.2 - 0.35 * maxf(0.0, cos(arm_ph))))
		reach = reach.lerp(wind, crawl)
		var scull := Vector3(0.55 + 0.15 * stroke, sg * 0.3 * stroke, sg * -0.85)
		t[R.UARM_L + o] = t[R.UARM_L + o].lerp(scull.lerp(reach, mvn), w)
		var elbow := 0.35 + 0.6 * maxf(0.0, -stroke) * mvn
		elbow = lerpf(elbow, 0.25 + 0.9 * maxf(0.0, -sin(cyc * 0.5 + side * PI)), crawl)
		t[R.FARM_L + o] = t[R.FARM_L + o].lerp(Vector3(elbow, 0, 0), w)
	# Keep the face up out of the water.
	t[R.NECK] = t[R.NECK].lerp(Vector3(lie * 0.35, 0, 0), w)
	t[R.HEAD] = t[R.HEAD].lerp(Vector3(lie * 0.45, 0, 0), w)
	t[R.SPINE] = t[R.SPINE].lerp(Vector3(lie * 0.08, 0, 0), w)


func _pose_air_land(t: PackedVector3Array, hips_rot: Vector3) -> void:
	var a := _air
	if a > 0.01:
		var up := smoothstep(0.5, 3.5, _vy)
		var down := smoothstep(-1.0, -6.0, _vy)
		var apex := clampf(1.0 - up - down, 0.0, 1.0)
		var lead := 0 if _jump_lead < 0.0 else 1
		var trail := 1 - lead
		var th := [R.THIGH_L, R.THIGH_R]
		var sh := [R.SHIN_L, R.SHIN_R]
		var ft := [R.FOOT_L, R.FOOT_R]
		t[th[lead]] = Vector3(1.0 * up + 1.0 * apex + 0.45 * down, 0, 0)
		t[sh[lead]] = Vector3(-(1.25 * up + 1.55 * apex + 0.5 * down), 0, 0)
		t[th[trail]] = Vector3(-0.3 * up + 0.6 * apex + 0.12 * down, 0, 0)
		t[sh[trail]] = Vector3(-(0.95 * up + 1.25 * apex + 0.3 * down), 0, 0)
		t[ft[lead]] = Vector3(-0.35 * up, 0, 0)
		t[ft[trail]] = Vector3(-0.55 * up - 0.1 * apex, 0, 0)
		var flail := smoothstep(0.6, 1.2, _air_t) * down
		for side in 2:
			var sg := -1.0 if side == 0 else 1.0
			var o := 0 if side == 0 else 5
			var arm := Vector3(0.9 * up + 0.45 * apex + 0.25 * down, 0, sg * (0.25 + 0.75 * down))
			arm += Vector3(sin(_time * 9.0 + side * 2.0) * 0.5, 0, sg * sin(_time * 7.0 + side) * 0.3) * flail
			t[R.UARM_L + o] = t[R.UARM_L + o].lerp(arm, a)
			t[R.FARM_L + o] = t[R.FARM_L + o].lerp(Vector3(0.55 + 0.3 * apex, 0, 0), a)
		t[R.SPINE] += Vector3(-0.12 * apex + 0.06 * up + 0.08 * down, 0, 0) * a
		t[R.CHEST] += Vector3(-0.05 * apex, 0, 0) * a
		_ik_target = 1.0 - a
	var _u := hips_rot
	# Take-off: brief crouch while the body leaves, then a stretch.
	if _takeoff_t < 0.35:
		var k := keys(_takeoff_t, [[0.0, 0.0], [0.05, -0.15], [0.13, 0.05], [0.35, 0.0]])
		_hips_tgt.y += k
		if _takeoff_t < 0.1:
			_ik_target = 1.0
			for side in 2:
				_foot[side].y = _rest[R.FOOT_L].y
		t[R.SPINE] += Vector3(-0.25 * maxf(0.0, -k) * 4.0, 0, 0)
	# Landing: compression scaled by impact; heavy landings kneel with a hand down.
	if _land_t < 1.2 and grounded:
		var amt := _land_amt
		if _land_heavy:
			var hold := keys(_land_t, [[0.0, 0.3], [0.07, 1.0], [0.55, 1.0], [1.05, 0.0]])
			_hips_tgt.y -= 0.44 * hold
			_hips_tgt.z += 0.02 * hold
			_foot[1] += Vector3(0, 0, -0.2) * hold
			_foot[0] += Vector3(0, 0.0, 0.32) * hold
			_foot_pitch[0] = lerpf(_foot_pitch[0], -1.1, hold)
			t[R.SPINE] += Vector3(-0.5, 0, 0.05) * hold
			t[R.CHEST] += Vector3(-0.2, 0, 0) * hold
			t[R.UARM_R] = t[R.UARM_R].lerp(Vector3(0.75, 0, 0.35), hold)
			t[R.FARM_R] = t[R.FARM_R].lerp(Vector3(0.15, 0, 0), hold)
			t[R.HAND_R] = t[R.HAND_R].lerp(Vector3(-0.9, 0, 0), hold)
			t[R.UARM_L] = t[R.UARM_L].lerp(Vector3(0.2, 0, -0.55), hold)
			t[R.FARM_L] = t[R.FARM_L].lerp(Vector3(0.7, 0, 0), hold)
			t[R.HEAD] += Vector3(0.25, 0, 0) * hold
			_ik_target = 1.0
		else:
			var c := keys(_land_t, [[0.0, 0.25], [0.08, 1.0], [0.3, 0.1], [0.42, -0.06], [0.6, 0.0]]) * amt
			_hips_tgt.y -= 0.24 * c
			t[R.SPINE] += Vector3(-0.22 * c, 0, 0)
			t[R.CHEST] += Vector3(-0.08 * c, 0, 0)
			for side in 2:
				var o := 0 if side == 0 else 5
				var sg := -1.0 if side == 0 else 1.0
				t[R.UARM_L + o] += Vector3(0.3 * c, 0, sg * 0.25 * c)
				t[R.FARM_L + o] += Vector3(0.35 * c, 0, 0)
			t[R.HEAD] += Vector3(-0.1 * c, 0, 0)
			_ik_target = 1.0


func _blend(t: PackedVector3Array, i: int, target: Vector3, w: float) -> void:
	t[i] = t[i].lerp(target, w)


func _pose_action(action: String, p: float, w: float, t: PackedVector3Array, hips_rot: Vector3) -> void:
	match action:
		"attack":
			# Forehand diagonal slash: coil, explode, follow through, recover.
			_blend(t, R.UARM_R, Vector3(keys(p, [[0, 0.4], [0.28, 2.5], [0.4, 0.15], [0.55, -0.35], [1, 0.35]]),
				keys(p, [[0, 0.0], [0.28, -0.35], [0.42, 0.45], [0.6, 0.6], [1, 0.0]]),
				keys(p, [[0, 0.25], [0.28, 0.85], [0.42, -0.25], [0.6, -0.45], [1, 0.2]])), w)
			_blend(t, R.FARM_R, Vector3(keys(p, [[0, 0.6], [0.28, 1.7], [0.42, 0.25], [0.6, 0.35], [1, 0.6]]), 0, 0), w)
			_blend(t, R.HAND_R, Vector3(keys(p, [[0, 0.0], [0.28, 0.5], [0.42, -0.4], [1, -0.1]]), 0, 0), w)
			_blend(t, R.CHEST, Vector3(keys(p, [[0, 0.0], [0.28, 0.1], [0.45, -0.2], [1, 0]]), keys(p, [[0, 0.0], [0.28, 0.6], [0.45, -0.6], [0.62, -0.75], [1, 0]]), 0), w)
			_blend(t, R.SPINE, Vector3(keys(p, [[0, 0.0], [0.28, 0.06], [0.45, -0.28], [1, 0]]), keys(p, [[0, 0.0], [0.28, 0.2], [0.45, -0.2], [1, 0]]), 0), w)
			_blend(t, R.UARM_L, Vector3(keys(p, [[0, 0.5], [0.28, 0.9], [0.45, -0.25], [1, 0.4]]), 0, keys(p, [[0, -0.3], [0.28, -0.25], [0.45, -0.55], [1, -0.3]])), w)
			_blend(t, R.FARM_L, Vector3(0.9, 0, 0), w)
			var step := keys(p, [[0, 0.0], [0.28, -0.05], [0.42, 0.24], [0.75, 0.2], [1, 0.0]]) * w
			_foot[0] += Vector3(0, 0, -step)
			_hips_tgt += Vector3(0, -0.07 * maxf(step, 0.0) / 0.24, -step * 0.4)
			_fing[1] = 1.4
			_swing_window(p, 0.26, 0.6)
		"attack2", "sweep":
			# Backhand horizontal sweep.
			_blend(t, R.UARM_R, Vector3(keys(p, [[0, 0.5], [0.26, 1.35], [0.5, 1.35], [1, 0.4]]),
				keys(p, [[0, 0.3], [0.26, 1.05], [0.42, -0.9], [0.62, -1.35], [1, 0.0]]),
				keys(p, [[0, 0.2], [0.26, -0.2], [0.45, 0.3], [1, 0.2]])), w)
			_blend(t, R.FARM_R, Vector3(keys(p, [[0, 0.6], [0.26, 1.2], [0.42, 0.15], [1, 0.6]]), 0, 0), w)
			_blend(t, R.CHEST, Vector3(-0.08, keys(p, [[0, 0], [0.26, 0.7], [0.45, -0.55], [0.65, -0.75], [1, 0]]), 0), w)
			_blend(t, R.SPINE, Vector3(-0.12, keys(p, [[0.26, 0.3], [0.5, -0.35], [1, 0]]), 0), w)
			_blend(t, R.UARM_L, Vector3(0.5, 0, keys(p, [[0, -0.3], [0.26, -0.6], [0.5, -0.2], [1, -0.3]])), w)
			if action == "sweep":
				_blend(t, R.UARM_L, Vector3(1.35, keys(p, [[0, 0.3], [0.26, 1.05], [0.42, -0.9], [0.62, -1.35], [1, 0.0]]) + 0.5, -0.1), w)
				_blend(t, R.FARM_L, Vector3(0.4, 0, 0), w)
			var step := keys(p, [[0, 0.0], [0.26, 0.0], [0.42, 0.18], [1, 0.0]]) * w
			_foot[1] += Vector3(0.08, 0, -0.12) * step / 0.18
			_hips_tgt.y -= 0.06 * step / 0.18
			_fing[1] = 1.4
			_swing_window(p, 0.24, 0.62)
		"mine":
			# Two-handed overhead pickaxe chop with an impact jolt.
			var up := keys(p, [[0, 0.65], [0.45, 2.75], [0.6, 0.35], [0.66, 0.5], [1, 0.65]])
			_blend(t, R.UARM_R, Vector3(up, -0.15, 0.12), w)
			_blend(t, R.FARM_R, Vector3(keys(p, [[0, 0.7], [0.45, 1.3], [0.6, 0.15], [1, 0.7]]), 0, 0), w)
			_blend(t, R.UARM_L, Vector3(up - 0.15, 0.25, -0.05), w)
			_blend(t, R.FARM_L, Vector3(keys(p, [[0, 0.9], [0.45, 1.4], [0.6, 0.4], [1, 0.9]]), 0, 0), w)
			_blend(t, R.SPINE, Vector3(keys(p, [[0, -0.05], [0.45, 0.1], [0.6, -0.38], [0.66, -0.3], [1, -0.05]]), 0, 0), w)
			_blend(t, R.CHEST, Vector3(keys(p, [[0.45, 0.06], [0.6, -0.16], [1, 0.0]]), 0, 0), w)
			_hips_tgt.y -= keys(p, [[0, 0.03], [0.45, 0.0], [0.6, 0.11], [1, 0.03]]) * w
			_foot[0] += Vector3(0, 0, -0.14) * w
			_fing[0] = 1.4
			_fing[1] = 1.4
			_arm_ik_w = w
			_swing_window(p, 0.46, 0.62)
		"cast", "throw":
			# Cock back, then thrust the palm forward; the off hand guides.
			_blend(t, R.UARM_R, Vector3(keys(p, [[0, 0.2], [0.32, -0.35], [0.5, 1.45], [1, 0.3]]), keys(p, [[0.32, 0.0], [0.5, 0.25]]), keys(p, [[0, 0.15], [0.32, 0.7], [0.5, 0.0], [1, 0.15]])), w)
			_blend(t, R.FARM_R, Vector3(keys(p, [[0, 0.3], [0.32, 1.6], [0.5, 0.08], [1, 0.3]]), 0, 0), w)
			_blend(t, R.HAND_R, Vector3(keys(p, [[0.32, 0.3], [0.5, -0.9]]), 0, 0), w)
			_blend(t, R.UARM_L, Vector3(keys(p, [[0, 0.3], [0.32, 1.1], [0.5, 0.4], [1, 0.3]]), 0, -0.3), w)
			_blend(t, R.FARM_L, Vector3(0.6, 0, 0), w)
			_blend(t, R.CHEST, Vector3(keys(p, [[0.32, 0.1], [0.5, -0.15]]), keys(p, [[0, 0], [0.32, 0.55], [0.5, -0.4], [1, 0]]), 0), w)
			_blend(t, R.SPINE, Vector3(keys(p, [[0.32, 0.05], [0.5, -0.18], [1, 0]]), keys(p, [[0.32, 0.2], [0.5, -0.15]]), 0), w)
			var step := keys(p, [[0, 0.0], [0.35, 0.0], [0.5, 0.2], [1, 0.0]]) * w
			_foot[0] += Vector3(0, 0, -step)
			_hips_tgt.z -= step * 0.3
			_fing[1] = keys(p, [[0.32, 1.2], [0.5, 0.0]])
		"shoot":
			# Bow drawn with the right hand to the cheek, released at 70 %.
			_blend(t, R.UARM_L, Vector3(1.5, -0.15, -0.1), w)
			_blend(t, R.FARM_L, Vector3(0.05, 0, 0), w)
			_blend(t, R.UARM_R, Vector3(1.45, keys(p, [[0, 0.0], [0.6, 0.55], [0.72, 0.75]]), keys(p, [[0, 0.1], [0.6, 0.35], [0.72, 0.8]])), w)
			_blend(t, R.FARM_R, Vector3(keys(p, [[0, 0.3], [0.6, 2.3], [0.7, 2.3], [0.75, 1.3]]), 0, 0), w)
			_blend(t, R.CHEST, Vector3(0, 0.55, 0), w)
			_blend(t, R.SPINE, Vector3(0.05, 0.2, 0), w)
			_fing[0] = 1.4
		"dodge":
			_pose_roll(p, t)
		"hit":
			var f := sin(PI * minf(p * 1.4, 1.0)) * w
			var sd := _hit_side
			t[R.SPINE] += Vector3(0.28, 0.12 * sd, 0.1 * sd) * f
			t[R.CHEST] += Vector3(0.12, 0.2 * sd, 0) * f
			t[R.HEAD] += Vector3(0.35, 0.25 * sd, 0.2 * sd) * f
			t[R.UARM_L] += Vector3(-0.35, 0, -0.35) * f
			t[R.UARM_R] += Vector3(-0.35, 0, 0.35) * f
			t[R.FARM_L] += Vector3(0.5, 0, 0) * f
			t[R.FARM_R] += Vector3(0.5, 0, 0) * f
			_hips_tgt += Vector3(0.02 * sd, -0.06, 0.06) * f
		"interact":
			_blend(t, R.UARM_R, Vector3(keys(p, [[0, 0.2], [0.45, 1.15], [1, 0.2]]), 0, 0.1), w)
			_blend(t, R.FARM_R, Vector3(0.25, 0, 0), w)
			_blend(t, R.SPINE, Vector3(-0.3, 0, 0), w)
			_blend(t, R.HEAD, Vector3(-0.15, 0, 0), w)
			_hips_tgt.y -= 0.1 * w
			_fing[1] = keys(p, [[0.3, 0.2], [0.5, 1.2], [1, 0.4]])
		"drink":
			_blend(t, R.UARM_R, Vector3(keys(p, [[0, 0.3], [0.35, 1.75], [0.75, 1.85], [1, 0.3]]), 0.3, 0.35), w)
			_blend(t, R.FARM_R, Vector3(keys(p, [[0, 0.3], [0.35, 2.35], [0.75, 2.4], [1, 0.3]]), 0, 0), w)
			_blend(t, R.HEAD, Vector3(keys(p, [[0.3, 0.0], [0.5, 0.45], [0.8, 0.4], [1, 0]]), 0, 0), w)
			_blend(t, R.CHEST, Vector3(keys(p, [[0.3, 0.0], [0.5, 0.12], [1, 0.0]]), 0, 0), w)
			_fing[1] = 1.3
		"slam", "spikes":
			var arm := keys(p, [[0, 0.3], [0.42, 2.9], [0.58, 0.1], [0.66, 0.25], [1, 0.3]])
			_blend(t, R.UARM_L, Vector3(arm, 0.25, -0.3), w)
			_blend(t, R.UARM_R, Vector3(arm, -0.25, 0.3), w)
			_blend(t, R.FARM_L, Vector3(keys(p, [[0.42, 1.0], [0.58, 0.1]]), 0, 0), w)
			_blend(t, R.FARM_R, Vector3(keys(p, [[0.42, 1.0], [0.58, 0.1]]), 0, 0), w)
			_blend(t, R.SPINE, Vector3(keys(p, [[0, 0], [0.42, 0.22], [0.6, -0.55], [1, 0]]), 0, 0), w)
			_blend(t, R.CHEST, Vector3(keys(p, [[0, 0], [0.42, 0.12], [0.6, -0.2], [1, 0]]), 0, 0), w)
			_hips_tgt.y -= keys(p, [[0.0, 0.0], [0.42, -0.04], [0.6, 0.26], [0.75, 0.22], [1, 0.0]]) * w
			_foot[0] += Vector3(-0.05, 0, -0.1) * w
			_foot[1] += Vector3(0.05, 0, 0.06) * w
			_fing[0] = 1.4
			_fing[1] = 1.4
			_arm_ik_w = w if _held_id in TWO_HANDED else 0.0
			_swing_window(p, 0.42, 0.62)
		"roar", "summon", "howl":
			var up := 2.6 if action == "summon" else 0.35
			var tremble := sin(_time * 34.0) * 0.03
			_blend(t, R.UARM_L, Vector3(up, 0.2, -1.05 + tremble), w)
			_blend(t, R.UARM_R, Vector3(up, -0.2, 1.05 - tremble), w)
			_blend(t, R.FARM_L, Vector3(0.6, 0, 0), w)
			_blend(t, R.FARM_R, Vector3(0.6, 0, 0), w)
			_blend(t, R.CHEST, Vector3(0.28, 0, 0), w)
			_blend(t, R.SPINE, Vector3(0.1, 0, 0), w)
			t[R.HEAD] += Vector3(0.35 + tremble, 0, 0) * w
			t[R.JAW] = Vector3(-0.4 * w, 0, 0)
			_hips_tgt.y -= 0.08 * w
			_foot[0] += Vector3(-0.08, 0, 0) * w
			_foot[1] += Vector3(0.08, 0, 0) * w
			_fing[0] = 1.5
			_fing[1] = 1.5
		"lunge":
			_blend(t, R.SPINE, Vector3(-0.6, 0, 0), w)
			_blend(t, R.UARM_L, Vector3(keys(p, [[0, 0.5], [0.4, 1.8], [1, 0.8]]), 0, -0.25), w)
			_blend(t, R.UARM_R, Vector3(keys(p, [[0, 0.5], [0.4, 1.8], [1, 0.8]]), 0, 0.25), w)
			_blend(t, R.FARM_L, Vector3(0.15, 0, 0), w)
			_blend(t, R.FARM_R, Vector3(0.15, 0, 0), w)
			_blend(t, R.HEAD, Vector3(0.4, 0, 0), w)
			_foot[0] += Vector3(0, 0, -0.35) * w
			_foot[1] += Vector3(0, 0, 0.3) * w
			_hips_tgt.y -= 0.16 * w
			_fing[0] = 0.6
			_fing[1] = 0.6
			t[R.JAW] = Vector3(-0.25 * w, 0, 0)
		"teleport":
			_blend(t, R.SPINE, Vector3(-0.4, 0, 0), w)
			_blend(t, R.UARM_L, Vector3(2.2, 0, -0.8), w)
			_blend(t, R.UARM_R, Vector3(2.2, 0, 0.8), w)
			_hips_tgt.y -= 0.2 * w
		"drain":
			_blend(t, R.UARM_R, Vector3(1.4, 0, 0.2), w)
			_blend(t, R.UARM_L, Vector3(1.4, 0, -0.2), w)
			_blend(t, R.FARM_L, Vector3(0.2, 0, 0), w)
			_blend(t, R.FARM_R, Vector3(0.2, 0, 0), w)
			_fing[0] = 0.2
			_fing[1] = 0.2
	var _u := hips_rot


func _swing_window(p: float, from: float, to: float) -> void:
	if _held_id == "" or _held_id in BOW_ITEMS or not fx_enabled or not _near:
		return
	if _trail == null:
		_trail = SwingTrail.new()
		add_child(_trail)
		var c: Color = ItemDB.color(_held_id) if ItemDB.exists(_held_id) else Color(1.0, 0.7, 0.4)
		if _held_id.begins_with("sword_ember") or _held_id.begins_with("sword_dragonbone"):
			c = Color(1.0, 0.55, 0.2)
		_trail.set_color(c.lerp(Color(1.0, 0.75, 0.45), 0.5))
	_trail.set_recording(p >= from and p <= to)


func _pose_roll(p: float, t: PackedVector3Array) -> void:
	# Dive, tuck, roll over the shoulder, come up on the feet.
	var tuck := keys(p, [[0.0, 0.0], [0.15, 0.8], [0.25, 1.0], [0.72, 1.0], [0.92, 0.2], [1.0, 0.0]])
	var spin := keys(p, [[0.0, 0.0], [0.14, 0.04], [0.8, 0.98], [1.0, 1.0]])
	t[R.THIGH_L] = Vector3(1.9, 0, 0.08) * tuck
	t[R.THIGH_R] = Vector3(1.75, 0, -0.08) * tuck
	t[R.SHIN_L] = Vector3(-2.3, 0, 0) * tuck
	t[R.SHIN_R] = Vector3(-2.2, 0, 0) * tuck
	t[R.FOOT_L] = Vector3(-0.4, 0, 0) * tuck
	t[R.FOOT_R] = Vector3(-0.4, 0, 0) * tuck
	t[R.SPINE] = Vector3(-0.75, 0, 0) * tuck
	t[R.CHEST] = Vector3(-0.35, 0, 0) * tuck
	t[R.NECK] = Vector3(-0.5, 0, 0) * tuck
	t[R.HEAD] = Vector3(-0.3, 0, 0) * tuck
	t[R.UARM_L] = Vector3(1.2, 0, -0.25) * tuck
	t[R.UARM_R] = Vector3(1.2, 0, 0.25) * tuck
	t[R.FARM_L] = Vector3(1.7, 0, 0) * tuck
	t[R.FARM_R] = Vector3(1.7, 0, 0) * tuck
	_fing[0] = 1.3
	_fing[1] = 1.3
	_ik_target = 0.0
	_ik_w = minf(_ik_w, 1.0 - tuck)
	_hips_tgt.y = lerpf(_hips_tgt.y, 0.5, tuck)
	# Roll about the axis across the direction of travel.
	var d := Vector3(_dir.x, 0, _dir.y)
	if d.length_squared() < 0.01:
		d = Vector3.FORWARD
	var axis := Vector3.UP.cross(d).normalized()
	_hips_q_override = true
	_hips_q = Quaternion(axis, TAU * spin)


func _pose_dead(t: PackedVector3Array, hips_rot: Vector3) -> void:
	# Knees buckle, the body topples (accelerating), hits the ground with a small
	# bounce, and the limbs flop and settle.
	var tt := _dead_t
	var buckle := smoothstep(0.0, 0.35, tt)
	var fall := clampf((tt - 0.12) / 0.5, 0.0, 1.0)
	fall = fall * fall
	var bounce := 0.0
	if tt > 0.62:
		bounce = sin((tt - 0.62) * 18.0) * exp(-(tt - 0.62) * 7.0) * 0.08
	var f := clampf(fall - bounce, 0.0, 1.05)
	var mode := _death_mode
	var lie := 0.13
	_ik_target = 0.0
	_ik_w = 0.0
	match mode:
		0:
			# Backwards.
			_hips_q_override = true
			_hips_q = Quaternion.from_euler(Vector3(1.52 * f, 0.15 * f, 0.1 * f))
			_hips_tgt = Vector3(0.0, lerpf(_rest[R.HIPS].y, lie, f) - 0.2 * buckle * (1.0 - f), 0.32 * f)
			t[R.THIGH_L] = Vector3(0.5 * buckle * (1.0 - f) + 0.15 * f, 0, -0.08 * f)
			t[R.THIGH_R] = Vector3(0.3 * buckle * (1.0 - f) + 0.4 * f, 0, 0.12 * f)
			t[R.SHIN_L] = Vector3(-0.9 * buckle * (1.0 - f) - 0.15 * f, 0, 0)
			t[R.SHIN_R] = Vector3(-0.6 * buckle * (1.0 - f) - 0.6 * f, 0, 0)
			t[R.UARM_L] = Vector3(0.6 * buckle - 0.2 * f, 0.2 * f, -1.1 * f)
			t[R.UARM_R] = Vector3(0.4 * buckle + 0.6 * f, -0.3 * f, 0.9 * f)
			t[R.HEAD] = Vector3(0.35 * f, 0.6 * f, 0)
		1:
			# Forwards onto the face, arms failing to brace.
			_hips_q_override = true
			_hips_q = Quaternion.from_euler(Vector3(-1.5 * f, -0.2 * f, -0.08 * f))
			_hips_tgt = Vector3(0.0, lerpf(_rest[R.HIPS].y, lie, f) - 0.25 * buckle * (1.0 - f), -0.35 * f)
			t[R.THIGH_L] = Vector3(0.8 * buckle * (1.0 - f) - 0.1 * f, 0, 0)
			t[R.THIGH_R] = Vector3(0.6 * buckle * (1.0 - f), 0, 0.1 * f)
			t[R.SHIN_L] = Vector3(-1.2 * buckle * (1.0 - f) - 0.3 * f, 0, 0)
			t[R.SHIN_R] = Vector3(-1.0 * buckle * (1.0 - f) - 0.1 * f, 0, 0)
			t[R.UARM_L] = Vector3(0.9 * buckle + 1.4 * f, 0, -0.5 * f)
			t[R.UARM_R] = Vector3(0.6 * buckle + 0.3 * f, 0, 0.9 * f)
			t[R.FARM_L] = Vector3(0.6 * f, 0, 0)
			t[R.HEAD] = Vector3(0.5 * f, -0.9 * f, 0)
		_:
			# Crumple sideways.
			_hips_q_override = true
			_hips_q = Quaternion.from_euler(Vector3(0.25 * f, 0.3 * f, 1.5 * f))
			_hips_tgt = Vector3(-0.3 * f, lerpf(_rest[R.HIPS].y, lie + 0.02, f) - 0.3 * buckle * (1.0 - f), 0.0)
			t[R.THIGH_L] = Vector3(0.9 * buckle, 0, 0.1 * f)
			t[R.THIGH_R] = Vector3(0.4 * buckle + 0.3 * f, 0, 0)
			t[R.SHIN_L] = Vector3(-1.4 * buckle, 0, 0)
			t[R.SHIN_R] = Vector3(-0.9 * buckle, 0, 0)
			t[R.UARM_L] = Vector3(0.4 + 0.8 * f, 0, -0.3)
			t[R.UARM_R] = Vector3(0.2 + 0.9 * f, 0, 1.2 * f)
			t[R.HEAD] = Vector3(0.2 * f, 0.3 * f, -0.4 * f)
	t[R.SPINE] = Vector3(0.12 * f * (1.0 if mode == 0 else -1.0), 0, 0)
	t[R.FARM_L] += Vector3(0.3 + 0.2 * buckle, 0, 0)
	t[R.FARM_R] += Vector3(0.4, 0, 0)
	t[R.JAW] = Vector3(-0.2 * f, 0, 0)
	_fing[0] = 0.5
	_fing[1] = 0.6
	var _u := hips_rot


# --- Applying the pose ----------------------------------------------------------

func _apply(dt: float) -> void:
	var rate := 26.0 if _action != "" else 20.0
	var k := 1.0 - exp(-rate * dt)
	for i in R.BODY_BONES:
		_cur[i] = _cur[i].lerp(_tgt[i], k)
	var dead_rate := 1.0 - exp(-(40.0 if _dead else 22.0) * dt)
	_hips_pos = _hips_pos.lerp(_hips_tgt, 1.0 if _hips_q_override and not _dead else dead_rate)
	var hips_q := _hips_q if _hips_q_override else Quaternion.from_euler(_cur[R.HIPS])
	_q[R.HIPS] = hips_q
	for i in range(1, R.BODY_BONES):
		_q[i] = Quaternion.from_euler(_cur[i])
	# Fingers curl about the hand's forward axis (toward the palm).
	for side in 2:
		var sg := -1.0 if side == 0 else 1.0
		var fb := R.FING_L if side == 0 else R.FING_R
		_q[fb] = Quaternion(Vector3.BACK, -sg * _fing[side])
	# Forward kinematics of the spine (for IK, cloth and the off-hand grip).
	_g[R.HIPS] = Transform3D(Basis(hips_q), _hips_pos)
	_g[R.SPINE] = _g[R.HIPS] * Transform3D(Basis(_q[R.SPINE]), _local[R.SPINE])
	_g[R.CHEST] = _g[R.SPINE] * Transform3D(Basis(_q[R.CHEST]), _local[R.CHEST])
	if _ik_w > 0.01:
		for side in 2:
			_solve_leg(side)
	if _arm_ik_w > 0.02 and _held_id in TWO_HANDED:
		_solve_offhand()
	skeleton.set_bone_pose_position(R.HIPS, _hips_pos)
	for i in R.BODY_BONES:
		skeleton.set_bone_pose_rotation(i, _q[i])


func _solve_leg(side: int) -> void:
	var th := R.THIGH_L if side == 0 else R.THIGH_R
	var sh := th + 1
	var ft := th + 2
	var to := th + 3
	var hips := _g[R.HIPS]
	var a := hips * _local[th]
	var target := _foot[side]
	var l1 := _local[sh].length()
	var l2 := _local[ft].length()
	var d := target - a
	var dist := clampf(d.length(), absf(l1 - l2) + 0.01, (l1 + l2) * 0.999)
	var dn := d.normalized() if d.length_squared() > 1e-8 else Vector3.DOWN
	var sg := -1.0 if side == 0 else 1.0
	var fwd := hips.basis * Vector3(sg * 0.12, 0, -1)
	fwd.y = minf(fwd.y, 0.3)
	var x := dn.cross(fwd)
	if x.length_squared() < 1e-6:
		x = hips.basis.x
	x = x.normalized()
	var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var cos_k := clampf((l1 * l1 + l2 * l2 - dist * dist) / (2.0 * l1 * l2), -1.0, 1.0)
	var alpha := acos(cos_a)
	var bend := PI - acos(cos_k)
	var thigh_dir := dn.rotated(x, alpha)
	var y := -thigh_dir
	var z := x.cross(y).normalized()
	var bt := Basis(x, y, z)
	var q_thigh := (hips.basis.inverse() * bt).get_rotation_quaternion()
	var q_knee := Quaternion(Vector3.RIGHT, -bend)
	var shin_g := bt * Basis(q_knee)
	var foot_g := Basis.from_euler(Vector3(_foot_pitch[side], sg * 0.1, 0))
	var q_foot := (shin_g.inverse() * foot_g).get_rotation_quaternion()
	var w := _ik_w
	_q[th] = _q[th].slerp(q_thigh, w)
	_q[sh] = _q[sh].slerp(q_knee, w)
	_q[ft] = _q[ft].slerp(q_foot, w)
	_q[to] = _q[to].slerp(Quaternion(Vector3.RIGHT, clampf(-_foot_pitch[side] * 0.8, 0.0, 0.9)), w)


func _solve_offhand() -> void:
	# Left hand grips the handle of a two-handed tool below the right hand.
	var clav_r := _g[R.CHEST] * Transform3D(Basis(_q[R.CLAV_R]), _local[R.CLAV_R])
	var uarm_r := clav_r * Transform3D(Basis(_q[R.UARM_R]), _local[R.UARM_R])
	var farm_r := uarm_r * Transform3D(Basis(_q[R.FARM_R]), _local[R.FARM_R])
	var hand_r := farm_r * Transform3D(Basis(_q[R.HAND_R]), _local[R.HAND_R])
	var grip := hand_r * grip_r.transform
	var handle := grip * Vector3(0, -0.2, 0)
	var clav_l := _g[R.CHEST] * Transform3D(Basis(_q[R.CLAV_L]), _local[R.CLAV_L])
	var a := clav_l * _local[R.UARM_L]
	var wrist := handle + (a - handle).normalized() * 0.075
	var l1 := _local[R.FARM_L].length()
	var l2 := _local[R.HAND_L].length()
	var d := wrist - a
	var dist := clampf(d.length(), absf(l1 - l2) + 0.01, (l1 + l2) * 0.999)
	var dn := d.normalized()
	var hint := clav_l.basis * Vector3(-0.4, -0.3, 1.0)
	var x := dn.cross(hint)
	if x.length_squared() < 1e-6:
		return
	x = x.normalized()
	var alpha := acos(clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0))
	var bend := PI - acos(clampf((l1 * l1 + l2 * l2 - dist * dist) / (2.0 * l1 * l2), -1.0, 1.0))
	var up_dir := dn.rotated(x, alpha)
	var y := -up_dir
	var bu := Basis(x, y, x.cross(y).normalized())
	var w := _arm_ik_w
	_q[R.UARM_L] = _q[R.UARM_L].slerp((clav_l.basis.inverse() * bu).get_rotation_quaternion(), w)
	_q[R.FARM_L] = _q[R.FARM_L].slerp(Quaternion(Vector3.RIGHT, -bend), w)


# --- Cloak -----------------------------------------------------------------------

func _cloak_step(dt: float) -> void:
	var chest_rest := _rest[R.CHEST]
	if not _near or _dead and _dissolve > 0.5:
		_cloth.write_rigid(skeleton, _cloak_first, _g[R.CHEST], chest_rest)
		return
	var sk := skeleton.global_transform
	var pin := sk * _g[R.CHEST]
	# Teleports and respawns: start over instead of stretching across the map.
	if _cloth.is_ready() and _cloth.p[0].distance_to(pin * (_cloth.rest[0] - chest_rest)) > 2.0 * _s:
		_cloth.reset(pin, chest_rest)
	var b := _b
	_cloth.cap_a.resize(5)
	_cloth.cap_b.resize(5)
	_cloth.cap_r.resize(5)
	var hips := _g[R.HIPS]
	_cloth.cap_a[0] = sk * (hips * Vector3(0, -0.05, 0.02))
	_cloth.cap_b[0] = sk * (_g[R.CHEST] * Vector3(0, 0.12, 0.0))
	_cloth.cap_r[0] = 0.165 * b * _s
	_cloth.cap_a[1] = sk * (hips * Vector3(-0.07 * b, -0.08, 0.06))
	_cloth.cap_b[1] = sk * (hips * Vector3(0.07 * b, -0.08, 0.06))
	_cloth.cap_r[1] = 0.12 * b * _s
	for side in 2:
		var th := R.THIGH_L if side == 0 else R.THIGH_R
		var thigh := hips * Transform3D(Basis(_q[th]), _local[th])
		var shin := thigh * Transform3D(Basis(_q[th + 1]), _local[th + 1])
		_cloth.cap_a[2 + side] = sk * thigh.origin
		_cloth.cap_b[2 + side] = sk * shin.origin
		_cloth.cap_r[2 + side] = 0.1 * b * _s
		if side == 1:
			_cloth.cap_a[4] = sk * (_g[R.CHEST] * Vector3(0, 0.2, 0.06))
			_cloth.cap_b[4] = sk * (_g[R.CHEST] * Vector3(0, -0.05, 0.08))
			_cloth.cap_r[4] = 0.17 * b * _s
	var back := (global_transform.basis * Vector3.BACK).normalized()
	_cloth.step(dt, pin, chest_rest, back, 2)
	_cloth.write(skeleton, _cloak_first, sk.affine_inverse())


# --- FX ---------------------------------------------------------------------------

func _probe(local_foot: Vector3) -> float:
	if not terrain_probe.is_valid() or not _near or not is_inside_tree():
		return 0.0
	var world := skeleton.global_transform * local_foot
	var h: float = terrain_probe.call(world)
	if is_nan(h):
		return 0.0
	return clampf((h - global_position.y) / _s, -0.45, 0.45)


func _on_plant(side: int, local_foot: Vector3) -> void:
	var strength := clampf(0.3 + 0.7 * (_speed - 1.4) / 5.5, 0.3, 1.0)
	footstep.emit(strength)
	if not fx_enabled or not _near or not is_inside_tree():
		return
	var heavy := _run > 0.6 or ground_block == Blocks.SNOW or ground_block == Blocks.SAND
	if heavy:
		var world := skeleton.global_transform * Vector3(local_foot.x, 0.0, local_foot.z)
		MoveFx.footstep(self, world, strength, ground_block, velocity)
	var _u := side


func _fx(dt: float) -> void:
	if _trail != null:
		if _held != null and _action != "":
			var base := _held.global_position
			var tip := _held.global_transform * Vector3(0, _held_len, 0)
			_trail.push(base.lerp(tip, 0.35), tip)
		else:
			_trail.set_recording(false)
		_trail.tick(dt)
	var streak := 0.0
	if fx_enabled and _near and not _dead:
		streak = maxf(_sprint * smoothstep(5.0, 7.0, _speed * _s) * (1.0 - _air * 0.5), 1.0 if _action == "dodge" else 0.0)
	if streak > 0.05 and _streaks == null and is_inside_tree():
		_streaks = SpeedStreaks.new()
		_streaks.position = Vector3(0, 0.95 * _s, 0)
		add_child(_streaks)
	if _streaks != null:
		_streaks.drive(velocity, streak)
