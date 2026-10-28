class_name Viewmodel
extends Node3D
## First-person arms. The arms are the character's own arm-and-hand geometry
## (CharBody, so sleeves, gloves and skin match the body) on a small skeleton
## parented to the camera. Each frame the animation decides where each hand
## grips (a transform in camera space); two-bone IK places the elbows and the
## hand bones wrap around the grip. The held item sits in the right grip.
##
## Animation is procedural from the player's state: idle breathing, walk and
## sprint bob, mouse-look lag, landing dip, sword combos, pickaxe strikes,
## axe chops, casting, drinking, interacting and dodging. In water the item
## is stowed and the arms swim: breaststroke, front crawl when sprinting,
## sculling (treading water) at rest.



var player: Player

var _skel: Skeleton3D
var _arms: MeshInstance3D
var _grip: Node3D
var _item: Node3D
var _item_id := "~"
var _rest := PackedVector3Array()
var _len_u := 0.285
var _len_f := 0.255
var _t := 0.0
var _sway := Vector2.ZERO
var _last_yaw := 0.0
var _last_pitch := 0.0
var _bob := 0.0
var _land := 0.0
var _equip := 1.0
var _style_key := ""
var _swim := 0.0         ## 0..1 blend into the swimming arms
var _swim_phase := 0.0
var _crawl := 0.0        ## 0 breaststroke .. 1 front crawl
var _curl := [95.0, 95.0]   ## finger curl per hand (degrees): wrapped grip .. flat


func _ready() -> void:
	_grip = Node3D.new()
	_grip.name = "Grip"
	add_child(_grip)
	_build_arms()


func _player_style() -> Dictionary:
	if player != null and player.model != null and player.model.get("style") is Dictionary:
		return player.model.get("style")
	return Models.player_style(0)


func _build_arms() -> void:
	var st := _player_style()
	_style_key = str(st.hash())
	if _arms != null:
		_arms.queue_free()
		_skel.queue_free()
	var pr := CharRig.proportions(st)
	_rest = CharRig.rest_positions(pr)
	_len_u = (_rest[CharRig.FARM_R] - _rest[CharRig.UARM_R]).length()
	_len_f = (_rest[CharRig.HAND_R] - _rest[CharRig.FARM_R]).length()
	var g := CharGeo.new()
	CharBody._arms(g, st, pr, _rest, true)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, g.to_arrays(), [], {}, CharGeo.FORMAT_FLAGS)
	mesh.surface_set_material(0, CharBody.material())
	_skel = Skeleton3D.new()
	_skel.name = "ArmsSkeleton"
	var skin := Skin.new()
	for i in CharRig.BODY_BONES:
		_skel.add_bone(CharRig.NAMES[i])
		var parent: int = CharRig.PARENTS[i]
		if parent >= 0:
			_skel.set_bone_parent(i, parent)
		var local := _rest[i] - (_rest[parent] if parent >= 0 else Vector3.ZERO)
		_skel.set_bone_rest(i, Transform3D(Basis.IDENTITY, local))
		skin.add_bind(i, Transform3D(Basis.IDENTITY, -_rest[i]))
	add_child(_skel)
	_arms = MeshInstance3D.new()
	_arms.name = "Arms"
	_arms.mesh = mesh
	_arms.skin = skin
	_arms.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Never culled away by the skeleton's moving bounds.
	_arms.extra_cull_margin = 2.0
	_skel.add_child(_arms)
	_arms.skeleton = NodePath("..")
	if player != null and player.model != null and player.model.has_method("palette_colors"):
		var cols: Dictionary = player.model.call("palette_colors")
		for k: StringName in cols:
			var c: Color = (cols[k] as Color).srgb_to_linear()
			_arms.set_instance_shader_parameter(k, Vector3(c.r, c.g, c.b))


func _set_item(id: String) -> void:
	if id == _item_id:
		return
	_item_id = id
	_equip = 0.0
	if _item != null:
		_item.queue_free()
		_item = null
	if id == "":
		return
	_item = HeldItems.build(id, 1.0, false)
	if _item != null:
		_grip.add_child(_item)
		# A hand's width of handle shows below the fist.
		_item.position = Vector3(0, -0.07, 0)
		for g: GeometryInstance3D in _item.find_children("*", "GeometryInstance3D", true, false):
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --- Animation ------------------------------------------------------------------------------

## A grip in camera space (-Z ahead, +X right, +Y up). Its basis is the held
## item's frame: +Y runs up the handle (towards the blade / head).
static func _at(pos: Vector3, pitch_deg: float, yaw_deg: float, roll_deg: float) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), deg_to_rad(roll_deg))), pos)


func _process(delta: float) -> void:
	if player == null or player.camera == null:
		return
	visible = player.camera.first_person and not player.dead
	if not visible:
		return
	var st := _player_style()
	if str(st.hash()) != _style_key:
		_build_arms()
	_t += delta
	var id := player.held_item()
	_set_item(id)
	var info := ItemDB.info(id)
	var kind := String(info.get("kind", ""))
	var two_handed := kind in ["pickaxe", "axe", "greataxe", "warhammer", "spear"]
	_equip = minf(1.0, _equip + delta * 4.0)

	# Mouse-look lag: the arms trail the view a little, then settle.
	var cam := player.camera
	var dyaw := wrapf(cam.yaw - _last_yaw, -PI, PI)
	var dpitch := cam.pitch - _last_pitch
	_last_yaw = cam.yaw
	_last_pitch = cam.pitch
	_sway = _sway.lerp(Vector2(clampf(dyaw * 2.5, -0.1, 0.1), clampf(dpitch * 2.5, -0.1, 0.1)), 1.0 - exp(-delta * 10.0))
	_sway = _sway.lerp(Vector2.ZERO, 1.0 - exp(-delta * 7.0))

	var speed := Vector2(player.body.velocity.x, player.body.velocity.z).length() if player.body.on_floor else 0.0
	_bob += delta * (4.4 + speed * 0.75)
	var walk := clampf(speed / 4.6, 0.0, 1.6)
	var sprint := speed > 6.0
	var bob := Vector3(sin(_bob) * 0.011, -absf(cos(_bob)) * 0.014, 0.0) * walk
	var breathe := Vector3(0, sin(_t * 1.5) * 0.004, 0)
	_land = minf(_land + delta * 0.5, 0.06) if not player.body.on_floor else lerpf(_land, 0.0, 1.0 - exp(-delta * 9.0))

	# Rest grips. One-handed: item held low-right, angled up and slightly in.
	var r := _at(Vector3(0.25, -0.29, -0.4), -58.0, 4.0, -6.0)
	var l := _at(Vector3(-0.24, -0.34, -0.33), -10.0, -10.0, 12.0)
	if two_handed:
		# Both hands on the haft, the head forward and up to the right.
		r = _at(Vector3(0.2, -0.27, -0.38), -50.0, 10.0, -20.0)
		l = Transform3D(r.basis, r.origin + r.basis * Vector3(0, -0.22, 0))
	if id == "":
		r = _at(Vector3(0.21, -0.32, -0.32), -5.0, 10.0, -10.0)
	if sprint:
		r = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-22)) * r.basis, r.origin + Vector3(0.02, -0.06, 0.06))
		l = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-22)) * l.basis, l.origin + Vector3(-0.02, -0.06, 0.06))
	var action: String = player.get("_action")
	var at: float = player.get("_action_time")
	var k := clampf(at / maxf(0.01, player.anim_time), 0.0, 1.0)
	var show_left := two_handed or id == ""
	match action:
		"attack", "attack2":
			# Wind up to one side, slash across the view, recover.
			var dir := 1.0 if action == "attack" else -1.0
			var wind := smoothstep(0.0, 0.25, k)
			var cut := smoothstep(0.2, 0.55, k)
			var back := smoothstep(0.62, 1.0, k)
			var amt := 1.0 - back
			var yaw_s := dir * (0.7 * wind - 1.7 * cut) * amt
			var pitch_s := (deg_to_rad(28.0) * wind - deg_to_rad(52.0) * cut) * amt
			var off := Vector3(0.1 * wind * dir - 0.3 * cut * dir, 0.1 * wind - 0.12 * cut, -0.1 * cut) * amt
			r = Transform3D(Basis(Vector3.UP, yaw_s) * Basis(Vector3.RIGHT, pitch_s) * r.basis, r.origin + off)
			if two_handed:
				l = Transform3D(r.basis, r.origin + r.basis * Vector3(0, -0.24, 0))
		"mine":
			# Raise overhead, drive down onto the crosshair, rebound.
			var up := smoothstep(0.0, 0.38, k)
			var down := smoothstep(0.38, 0.56, k)
			var rec := smoothstep(0.62, 1.0, k)
			var amt := 1.0 - rec
			var ang := (deg_to_rad(55.0) * up - deg_to_rad(105.0) * down) * amt
			var lift := Vector3(-0.05, 0.16 * up - 0.2 * down, 0.06 * up - 0.12 * down) * amt
			r = Transform3D(Basis(Vector3.RIGHT, ang) * r.basis, r.origin + lift)
			if two_handed:
				l = Transform3D(r.basis, r.origin + r.basis * Vector3(0, -0.24, 0))
		"cast":
			var push := sin(k * PI)
			l = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-70) * push) * l.basis, l.origin.lerp(Vector3(-0.1, -0.16, -0.46), push))
			show_left = true
		"drink":
			var lift := sin(k * PI)
			r = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(65) * lift) * r.basis, r.origin.lerp(Vector3(0.05, -0.12, -0.2), lift))
		"interact":
			var reach := sin(k * PI)
			r = Transform3D(r.basis, r.origin + Vector3(-0.06, 0.06, -0.12) * reach)
		"dodge":
			var dip := sin(k * PI)
			r = Transform3D(r.basis, r.origin + Vector3(0, -0.14 * dip, 0.05))
			l = Transform3D(l.basis, l.origin + Vector3(0, -0.14 * dip, 0.05))
	# Swimming: the item is stowed, both arms stroke (or scull at rest).
	_swim = move_toward(_swim, 1.0 if player.swimming else 0.0, delta * 3.0)
	if _item != null:
		_item.visible = _swim < 0.5
	var curl_target := 95.0
	if _swim > 0.0:
		var sw := _swim_pose(delta)
		var w := smoothstep(0.0, 1.0, _swim)
		r = _blend(r, sw[1], w)
		l = _blend(l if show_left else Transform3D(l.basis, Vector3(-0.3, -0.72, 0.05)), sw[0], w)
		show_left = true
		curl_target = lerpf(95.0, 18.0, w)
		bob *= 1.0 - w
		_land *= 1.0 - w
	_curl[0] = curl_target
	_curl[1] = curl_target
	var shift := Vector3(-_sway.x * 0.3, _sway.y * 0.25, 0) + bob + breathe + Vector3(0, -_land, 0)
	shift += Vector3(0, -0.35 * (1.0 - _equip), 0.05 * (1.0 - _equip))
	r.origin += shift
	l.origin += shift * 0.9
	_grip.transform = r
	_pose_arm(1, r)
	# An idle left arm hangs out of view.
	_pose_arm(0, l if show_left else Transform3D(l.basis, Vector3(-0.3, -0.72, 0.05)))


static func _blend(a: Transform3D, b: Transform3D, w: float) -> Transform3D:
	return Transform3D(Basis(a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), w)), a.origin.lerp(b.origin, w))


## A grip frame whose hand points its fingers along `fingers` with the thumb
## towards `thumb` (camera space): the inverse of _pose_arm's hand mapping.
static func _hand(side: int, pos: Vector3, fingers: Vector3, thumb: Vector3) -> Transform3D:
	var sg := -1.0 if side == 0 else 1.0
	var f_local := Vector3(-sg * 0.75, -0.2, -0.65).normalized()
	return Transform3D(_frame(fingers, thumb) * _frame(f_local, Vector3.UP).inverse(), pos)


## Piecewise smooth path through keys [[t, value], ...] (t ascending, 0..1).
static func _path(k: float, keys: Array) -> Variant:
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if k <= b[0]:
			var u := smoothstep(0.0, 1.0, (k - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-4))
			return lerp(a[1], b[1], u)
	return keys[keys.size() - 1][1]


## [left grip, right grip] while swimming. Breaststroke: hands together
## forward, sweep out and back, scoop in under the chin, shoot forward again,
## glide. Front crawl (sprinting): alternating arms reach in from above,
## catch and pull down out of view. Treading water: hands scull low in front.
func _swim_pose(delta: float) -> Array:
	var v := player.body.velocity
	var mv := clampf(Vector2(v.x, v.z).length() / Player.SWIM_SPEED, 0.0, 1.5)
	var moving := smoothstep(0.15, 0.6, mv)
	_crawl = move_toward(_crawl, 1.0 if mv > 1.15 else 0.0, delta * 2.0)
	_swim_phase = fmod(_swim_phase + delta * lerpf(0.55, 0.85 + 0.25 * _crawl, moving), 1.0)
	var out: Array = [Transform3D.IDENTITY, Transform3D.IDENTITY]
	for side in 2:
		var sg := -1.0 if side == 0 else 1.0
		var ph := _swim_phase
		# Breaststroke.
		var bp: Vector3 = _path(ph, [
			[0.0, Vector3(sg * 0.07, -0.16, -0.5)],
			[0.32, Vector3(sg * 0.36, -0.2, -0.36)],
			[0.5, Vector3(sg * 0.1, -0.3, -0.2)],
			[0.78, Vector3(sg * 0.06, -0.15, -0.52)],
			[1.0, Vector3(sg * 0.07, -0.16, -0.5)]])
		var b_th: Vector3 = _path(ph, [
			[0.0, Vector3(-sg, 0.0, 0.0)],
			[0.25, Vector3(-sg * 0.35, -0.9, 0.0)],
			[0.5, Vector3(0.0, 0.2, -1.0)],
			[0.72, Vector3(-sg, 0.1, 0.0)],
			[1.0, Vector3(-sg, 0.0, 0.0)]])
		var b_f: Vector3 = _path(ph, [
			[0.0, Vector3(sg * 0.15, 0.05, -1.0)],
			[0.3, Vector3(sg * 0.6, -0.2, -0.8)],
			[0.5, Vector3(-sg * 0.7, 0.3, -0.6)],
			[0.75, Vector3(sg * 0.05, 0.0, -1.0)],
			[1.0, Vector3(sg * 0.15, 0.05, -1.0)]])
		var breast := _hand(side, bp, b_f, b_th)
		# Front crawl: each arm half a cycle apart.
		var cp_ph := fmod(ph + (0.5 if side == 0 else 0.0), 1.0)
		var cp: Vector3 = _path(cp_ph, [
			[0.0, Vector3(sg * 0.12, 0.1, -0.5)],
			[0.3, Vector3(sg * 0.14, -0.3, -0.4)],
			[0.55, Vector3(sg * 0.22, -0.68, -0.05)],
			[0.8, Vector3(sg * 0.32, -0.3, 0.1)],
			[1.0, Vector3(sg * 0.12, 0.1, -0.5)]])
		var crawl := _hand(side, cp, Vector3(sg * 0.05, -0.35 - 0.6 * smoothstep(0.0, 0.6, cp_ph), -1.0), Vector3(-sg, 0.1, 0.2))
		# Treading water: small sculling figure-eights low in front.
		var tp := _swim_phase * TAU * 1.6 + side * PI
		var tread := _hand(side, Vector3(sg * (0.24 + 0.07 * sin(tp)), -0.42 + 0.03 * sin(tp * 2.0), -0.32),
				Vector3(sg * 0.35, -0.15, -1.0), Vector3(-sg, 0.25 * sin(tp), 0.0))
		var swim := _blend(breast, crawl, _crawl)
		out[side] = _blend(tread, swim, moving)
	return out


## Two-bone IK for one arm: the shoulder is fixed just behind and below the
## eye; the wrist sits behind the grip; the hand wraps the handle.
func _pose_arm(side: int, grip: Transform3D) -> void:
	var sg := -1.0 if side == 0 else 1.0
	var o := 0 if side == 0 else 5
	var shoulder := Vector3(sg * 0.17, -0.2, 0.1)
	# The palm wraps the handle at the grip point; the wrist sits behind it.
	var fing_dir := (grip.basis * Vector3(-sg * 0.75, -0.2, -0.65)).normalized()
	var wrist := grip.origin - fing_dir * 0.06 + grip.basis * Vector3(sg * 0.02, -0.015, 0.0)
	var d := wrist - shoulder
	var reach := _len_u + _len_f - 0.002
	if d.length() > reach:
		wrist = shoulder + d.normalized() * reach
		d = wrist - shoulder
	var dist := maxf(d.length(), 0.05)
	var dn := d / dist
	# Elbow: out, down and slightly back, like a relaxed grip.
	var pole := Vector3(sg * 0.7, -1.0, 0.35).normalized()
	var pole_perp := (pole - dn * dn.dot(pole)).normalized()
	var a := (_len_u * _len_u - _len_f * _len_f + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(0.0, _len_u * _len_u - a * a))
	var elbow := shoulder + dn * a + pole_perp * h

	var rest_u := (_rest[CharRig.FARM_L + o] - _rest[CharRig.UARM_L + o]).normalized()
	var rest_f := (_rest[CharRig.HAND_L + o] - _rest[CharRig.FARM_L + o]).normalized()
	var bu := Basis(Quaternion(rest_u, (elbow - shoulder).normalized()))
	var bf := Basis(Quaternion(rest_f, (wrist - elbow).normalized()))
	# Hand: rest fingers point down the arm with the thumb forward; when
	# gripping, the fingers wrap across the handle and the thumb runs up it.
	var rest_fing := (_rest[CharRig.FING_L + o] - _rest[CharRig.HAND_L + o]).normalized()
	var rest_thumb := Vector3(0, 0, -1)
	var want_fing := fing_dir
	var want_thumb := grip.basis.y
	var bh := _frame(want_fing, want_thumb) * _frame(rest_fing, rest_thumb).inverse()
	# Fingers curl towards the palm (the palm faces the body's midline at rest).
	var palm_n := Vector3(-sg, 0, 0)
	var curl := Basis(rest_fing.cross(palm_n).normalized(), deg_to_rad(-float(_curl[side])))

	_set_pose(CharRig.CLAV_L + o, bu, shoulder + bu * (_rest[CharRig.CLAV_L + o] - _rest[CharRig.UARM_L + o]))
	_set_pose(CharRig.UARM_L + o, bu, shoulder)
	_set_pose(CharRig.FARM_L + o, bf, elbow)
	_set_pose(CharRig.HAND_L + o, bh, wrist)
	_set_pose(CharRig.FING_L + o, bh * curl, wrist + bh * (_rest[CharRig.FING_L + o] - _rest[CharRig.HAND_L + o]))


static func _frame(primary: Vector3, secondary: Vector3) -> Basis:
	var x := primary.normalized()
	var y := (secondary - x * x.dot(secondary)).normalized()
	return Basis(x, y, x.cross(y))


func _set_pose(bone: int, b: Basis, origin: Vector3) -> void:
	_skel.set_bone_global_pose(bone, Transform3D(b.orthonormalized(), origin))
