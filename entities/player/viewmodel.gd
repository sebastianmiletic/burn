class_name Viewmodel
extends Node3D
## First-person arms: a sleeved right forearm and hand holding the selected
## item (and a left hand for two-handed tools), parented to the camera and
## animated procedurally from the player's state: idle sway, walk bob, sprint
## tuck, mouse-look lag, sword combos, pickaxe strikes, casting, drinking,
## dodging and landing.

var player: Player

var _arm_r: Node3D
var _arm_l: Node3D
var _grip: Node3D
var _item: Node3D
var _item_id := "~"
var _t := 0.0
var _sway := Vector2.ZERO
var _last_yaw := 0.0
var _last_pitch := 0.0
var _bob := 0.0
var _land := 0.0
var _equip := 1.0
var _skin_mat: Material
var _sleeve_mat: Material


func _ready() -> void:
	_skin_mat = ModelKit.mat(Color(0.74, 0.58, 0.46), AsciiMaterialId.SOLID, 0.7, 0.12)
	var cloth: Color = player.model.get("style").get("cloth", Color(0.36, 0.3, 0.25)) if player != null and player.model != null and player.model.get("style") is Dictionary else Color(0.36, 0.3, 0.25)
	_sleeve_mat = ModelKit.cloth(cloth)
	_arm_r = _make_arm(true)
	_arm_l = _make_arm(false)
	add_child(_arm_r)
	add_child(_arm_l)
	_grip = Node3D.new()
	_arm_r.get_node("Hand").add_child(_grip)
	_grip.position = Vector3(0, -0.02, -0.02)


## Forearm (sleeve with a cuff) and a hand. The arm's origin is the elbow; the
## hand sits at the wrist, 0.27 m along -Z.
func _make_arm(right: bool) -> Node3D:
	var arm := Node3D.new()
	arm.name = "ArmR" if right else "ArmL"
	var sleeve := ModelKit.part(arm, ModelKit.cylinder(0.042, 0.052, 0.24, 24), _sleeve_mat, Vector3(0, 0, -0.11), Vector3(90, 0, 0))
	sleeve.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cuff := ModelKit.part(arm, ModelKit.cylinder(0.047, 0.047, 0.035, 24), _sleeve_mat, Vector3(0, 0, -0.22), Vector3(90, 0, 0))
	cuff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hand := Node3D.new()
	hand.name = "Hand"
	hand.position = Vector3(0, 0, -0.27)
	arm.add_child(hand)
	var s := 1.0 if right else -1.0
	var palm := ModelKit.part(hand, ModelKit.capsule(0.032, 0.09, 24), _skin_mat, Vector3(0, -0.005, -0.03), Vector3(90, 0, 0), Vector3(1.25, 1.0, 0.8))
	palm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Curled fingers around the grip and a thumb.
	for i in 4:
		var f := ModelKit.part(hand, ModelKit.capsule(0.011, 0.05, 12), _skin_mat, Vector3(s * (-0.024 + i * 0.016), -0.03, -0.07), Vector3(60, 0, 0))
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var thumb := ModelKit.part(hand, ModelKit.capsule(0.012, 0.05, 12), _skin_mat, Vector3(s * 0.035, 0.0, -0.05), Vector3(70, 0, s * 40.0))
	thumb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return arm


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
		for g: GeometryInstance3D in _item.find_children("*", "GeometryInstance3D", true, false):
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	if player == null or player.camera == null:
		return
	visible = player.camera.first_person and not player.dead
	if not visible:
		return
	_t += delta
	var id := player.held_item()
	_set_item(id)
	var info := ItemDB.info(id)
	var kind := String(info.get("kind", ""))
	var two_handed := kind in ["pickaxe", "axe", "greataxe", "warhammer", "spear"]
	_equip = minf(1.0, _equip + delta * 4.0)

	# Mouse-look lag: the arms trail the view a little.
	var cam := player.camera
	var dyaw := wrapf(cam.yaw - _last_yaw, -PI, PI)
	var dpitch := cam.pitch - _last_pitch
	_last_yaw = cam.yaw
	_last_pitch = cam.pitch
	_sway = _sway.lerp(Vector2(clampf(dyaw * 3.0, -0.12, 0.12), clampf(dpitch * 3.0, -0.12, 0.12)), 1.0 - exp(-delta * 10.0))
	_sway = _sway.lerp(Vector2.ZERO, 1.0 - exp(-delta * 6.0))

	# Walk bob in figure eight, stronger and lower when sprinting.
	var speed := player.body.velocity.length() if player.body.on_floor else 0.0
	_bob += delta * (4.6 + speed * 0.7)
	var walk := clampf(speed / 4.6, 0.0, 1.6)
	var sprint := speed > 6.0
	var bob := Vector3(sin(_bob) * 0.012, absf(cos(_bob)) * 0.016, 0.0) * walk
	var breathe := Vector3(0, sin(_t * 1.6) * 0.004, 0)
	if not player.body.on_floor:
		_land = minf(_land + delta * 0.6, 0.08)
	else:
		_land = lerpf(_land, 0.0, 1.0 - exp(-delta * 9.0))

	# Rest pose: right hand low and to the right, item angled up and inwards.
	# (Rotating about X by a negative angle tips the item's +Y away from the eye.)
	var rest_r := Transform3D(Basis.from_euler(Vector3(deg_to_rad(-38), deg_to_rad(-8), deg_to_rad(10))), Vector3(0.27, -0.31, -0.42))
	var rest_l := Transform3D(Basis.from_euler(Vector3(deg_to_rad(-20), deg_to_rad(18), 0)), Vector3(-0.28, -0.36, -0.38))
	if two_handed:
		rest_r = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-30), deg_to_rad(-15), deg_to_rad(35))), Vector3(0.24, -0.3, -0.44))
		rest_l = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-25), deg_to_rad(10), deg_to_rad(30))), Vector3(0.05, -0.36, -0.5))
	if sprint:
		rest_r = rest_r.rotated_local(Vector3.RIGHT, deg_to_rad(-25)).translated(Vector3(0.02, -0.06, 0.05))
	var r := rest_r
	var l := rest_l
	var action: String = player.get("_action")
	var at: float = player.get("_action_time")
	var dur := maxf(0.01, player.anim_time)
	var k := clampf(at / dur, 0.0, 1.0)
	match action:
		"attack", "attack2":
			# Wind up to one side, slash across the view, recover.
			var dir := 1.0 if action == "attack" else -1.0
			var wind := smoothstep(0.0, 0.25, k)
			var cut := smoothstep(0.2, 0.55, k)
			var back := smoothstep(0.6, 1.0, k)
			var yaw_s := dir * (0.9 * wind - 2.1 * cut) * (1.0 - back)
			var pitch_s := (deg_to_rad(30.0) * wind - deg_to_rad(45.0) * cut) * (1.0 - back)
			var off := Vector3(0.12 * wind * dir - 0.38 * cut * dir, 0.12 * wind - 0.1 * cut, -0.16 * cut) * (1.0 - back)
			r = Transform3D(Basis(Vector3.UP, yaw_s) * Basis(Vector3.RIGHT, pitch_s) * r.basis, r.origin + off)
		"mine":
			# Overhead strike down onto the crosshair.
			var up := smoothstep(0.0, 0.35, k)
			var down := smoothstep(0.35, 0.55, k)
			var rec := smoothstep(0.6, 1.0, k)
			var ang := (deg_to_rad(-70.0) * up + deg_to_rad(115.0) * down) * (1.0 - rec)
			r = r.rotated_local(Vector3.RIGHT, ang).translated(Vector3(-0.06, 0.12 * up - 0.16 * down, -0.1 * down) * (1.0 - rec))
			l = l.rotated_local(Vector3.RIGHT, ang * 0.8).translated(Vector3(0.0, 0.1 * up - 0.14 * down, -0.08 * down) * (1.0 - rec))
		"cast":
			var push := sin(k * PI)
			l = Transform3D(l.basis.rotated(Vector3.RIGHT, deg_to_rad(-60) * push), l.origin.lerp(Vector3(-0.08, -0.12, -0.42), push))
		"drink":
			var lift := sin(k * PI)
			r = Transform3D(r.basis.rotated(Vector3.RIGHT, deg_to_rad(-70) * lift), r.origin.lerp(Vector3(0.05, -0.08, -0.16), lift))
		"interact":
			var reach := sin(k * PI)
			r = Transform3D(r.basis, r.origin + Vector3(-0.05, 0.05, -0.12) * reach)
		"dodge":
			var dip := sin(k * PI)
			r = r.translated(Vector3(0, -0.15 * dip, 0.05))
			l = l.translated(Vector3(0, -0.15 * dip, 0.05))
	var shift := Vector3(-_sway.x * 0.35, _sway.y * 0.3, 0) + bob + breathe + Vector3(0, -_land, 0)
	var lower := Vector3(0, -0.3 * (1.0 - _equip), 0)
	_arm_r.transform = Transform3D(r.basis, r.origin + shift + lower)
	_arm_l.transform = Transform3D(l.basis, l.origin + shift * 0.9 + lower)
	_arm_l.visible = two_handed or action in ["cast", "dodge"] or id == ""
