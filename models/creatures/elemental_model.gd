class_name ElementalModel
extends MobModel
## Fire elemental of the Cinder Wastes and the underworld: a living inferno.
## A white-hot heart burns inside a ribcage of cracked, cooling lava shards
## over a body of molten rock; a skull of slag with hollow burning eyes and a
## crest of fire streaming back from its crown; shoulders of jagged basalt;
## arms of magma armoured in slag gauntlets that end in burning claws; no
## legs, only a twisting vortex of flame down to the ground with fragments of
## rock orbiting it. The flames are their own skinned mesh with an animated
## fire shader (rising, licking tongues, white core cooling to red), so they
## follow every limb. Lights its surroundings.
##
## Motion: hovering bob, swirling vortex, slow drifting arms; a throw that
## winds back, gathers a fireball in the claw and hurls it at the release
## point; a roar that flares every flame; a guttering flinch; and a death in
## which the fire dies, the body sinks and the shards fall smoking. Faces -Z.

const BASE := 2.2
## Fraction of a throw at which the fireball leaves the hand (windup / duration).
const RELEASE := 0.67

const S_ROCK := 0
const S_MAGMA := 1
const S_EYE := 2
const S_HEART := 3

const WAIST := 0
const CHEST := 1
const HEAD := 2
const SH_L := 3
const SH_R := 6
const V1 := 9
const V2 := 10
const V3 := 11

var size := 2.2

static var _flame_material: ShaderMaterial

var flame_mi: MeshInstance3D
var _shards: MultiMeshInstance3D
var _shard_data: Array = []   # [radius, height, speed, phase, tumble axis]
var _fireball: MeshInstance3D
var _flames: GPUParticles3D
var _light: OmniLight3D
var _flare := 1.0
var _charge := 0.0
var _swirl := 0.0
var _lean := 0.0
var _death_pose := false
var _dead_gb: Array[Basis] = []
var _dead_gp := PackedVector3Array()


func _init(variant_seed := 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = variant_seed
	size = rng.randf_range(2.0, 2.5)
	dissolve_delay = 1.6
	dissolve_time = 1.0
	durations["throw"] = 1.05
	durations["roar"] = 1.4


func _ember_extents() -> Vector3:
	return Vector3(0.4, 0.8, 0.4) * size * 0.5


func _lod_size() -> float:
	return size


# --- Build ---------------------------------------------------------------------------------

func _bones(r: MobRig) -> void:
	r.bone("waist", -1, Vector3(0, 1.05, 0))
	r.bone("chest", WAIST, Vector3(0, 1.45, 0))
	r.bone("head", CHEST, Vector3(0, 1.93, -0.07))
	for side: float in [-1.0, 1.0]:
		var sfx := "_l" if side < 0.0 else "_r"
		var sh := r.bone("sh" + sfx, CHEST, Vector3(side * 0.4, 1.68, 0.0))
		r.bone("el" + sfx, sh, Vector3(side * 0.6, 1.27, -0.06))
		r.bone("hand" + sfx, sh + 1, Vector3(side * 0.66, 0.88, -0.16))
	r.bone("v1", WAIST, Vector3(0, 0.66, 0))
	r.bone("v2", V1, Vector3(0, 0.22, 0))
	r.bone("v3", V2, Vector3(0, -0.2, 0))


func _build() -> void:
	var rock := CreatureSkin.rock(Color(0.11, 0.075, 0.065), {"use_rest": true, "pattern_scale": 7.0, "bump": 1.5,
		"glow_mode": 2, "glow_color": Color(1.0, 0.38, 0.06), "glow_amount": 0.14, "glow_energy": 5.0, "glow_pulse": 0.8,
		"glow_sparsity": 0.45, "rim": 0.1})
	var magma := CreatureSkin.smooth(Color(0.32, 0.07, 0.02), Color(0.2, 0.04, 0.01), {"use_rest": true, "pattern": CreatureSkin.Pattern.ROCK,
		"pattern_scale": 12.0, "bump": 1.0, "roughness": 0.6, "glow_mode": 2, "glow_color": Color(1.0, 0.55, 0.14), "glow_amount": 0.3,
		"glow_energy": 5.0, "glow_pulse": 0.9, "glow_sparsity": 0.5, "rim": 0.6, "belly_mix": 0.0})
	var eye := ModelKit.glow(Color(1.0, 0.9, 0.55), 12.0, 0.2)
	var heart := ModelKit.glow(Color(1.0, 0.82, 0.45), 9.0, 0.5)
	rig_instance(_rig_data(), [rock, magma, eye, heart], size / BASE, 1.0)
	# Flames: a second skinned mesh on the same skeleton.
	var fd := _flame_data()
	flame_mi = MeshInstance3D.new()
	flame_mi.name = "Flames"
	flame_mi.mesh = fd["mesh"]
	flame_mi.skin = fd["skin"]
	flame_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame_mi.material_override = _flame_mat()
	skel.add_child(flame_mi)
	flame_mi.skeleton = NodePath("..")
	var ab: AABB = (fd["mesh"] as ArrayMesh).get_aabb()
	flame_mi.custom_aabb = ab.grow(1.2)
	# Orbiting fragments of rock round the vortex: one MultiMesh.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = GolemModel.chunk("elem_shard", Vector3(0.11, 0.15, 0.09), 7, 6, 0.2, false)
	mm.instance_count = 9
	_shards = MultiMeshInstance3D.new()
	_shards.multimesh = mm
	_shards.material_override = CreatureSkin.rock(Color(0.11, 0.075, 0.065), {"pattern_scale": 7.0, "bump": 1.5,
		"glow_mode": 2, "glow_color": Color(1.0, 0.38, 0.06), "glow_amount": 0.18, "glow_energy": 5.0, "glow_pulse": 0.8, "rim": 0.1})
	_shards.custom_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 4, 4))
	add_child(_shards)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in mm.instance_count:
		_shard_data.append([rng.randf_range(0.45, 0.75), rng.randf_range(0.15, 1.05), rng.randf_range(0.7, 1.5) * (1.0 if i % 2 else -1.0),
			rng.randf() * TAU, Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()])
	# Fireball gathering in the right claw.
	var hand := follow(SH_R + 2, "Fireball")
	_fireball = ModelKit.part(hand, ModelKit.sphere(0.13, 12), ModelKit.glow(Color(1.0, 0.7, 0.3), 10.0, 0.6), Vector3(0, -0.12, -0.08))
	_fireball.visible = false
	_flames = ModelKit.embers(self, 46, Vector3(0.3, 0.5, 0.3), 0.9, 0.12, 2.6)
	_flames.position = Vector3(0, 1.0, 0) * rig_scale
	_flames.emitting = true
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.light_energy = 3.0
	_light.omni_range = 9.0 * rig_scale
	_light.shadow_enabled = false
	_light.light_volumetric_fog_energy = 2.0
	follow(CHEST, "Light").add_child(_light)


func _flame_mat() -> ShaderMaterial:
	if _flame_material == null:
		_flame_material = ShaderMaterial.new()
		_flame_material.shader = preload("res://models/creatures/flame_body.gdshader")
	return _flame_material


func _shard(r: MobRig, sz: Vector3, pos: Vector3, rot_deg: Vector3, b: int, seed_value: int, cuts := 6) -> void:
	r.slot(S_ROCK).rigid(GolemModel.chunk("elem", sz, seed_value, cuts, 0.2, false), Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)), pos), b)


func _rig_data() -> Dictionary:
	if MobRig.has("elemental"):
		return MobRig.cached("elemental")
	var r := MobRig.new(4)
	_bones(r)
	# Molten body under the slag.
	var rs := MobRig.resample(PackedVector3Array([Vector3(0, 0.62, 0), Vector3(0, 0.95, 0), Vector3(0, 1.3, 0), Vector3(0, 1.55, -0.01),
		Vector3(0, 1.76, -0.04), Vector3(0, 1.88, -0.06)]),
		PackedVector2Array([Vector2(0.08, 0.08), Vector2(0.17, 0.15), Vector2(0.22, 0.17), Vector2(0.26, 0.19), Vector2(0.12, 0.11), Vector2(0.09, 0.09)]),
		[V1, WAIST, CHEST, CHEST, HEAD, HEAD], 18)
	r.slot(S_MAGMA).tube(rs[0], rs[1], rs[2], 0.15, 12)
	for side: float in [-1.0, 1.0]:
		var sh := SH_L if side < 0.0 else SH_R
		r.slot(S_MAGMA).limb(PackedVector3Array([r.rest[CHEST] + Vector3(side * 0.18, 0.15, 0), r.rest[sh], r.rest[sh + 1], r.rest[sh + 2]]),
			[CHEST, sh, sh + 1], [[0.0, 0.1, 0.1], [0.35, 0.085, 0.085], [0.65, 0.075, 0.075], [1.0, 0.06, 0.06]], 12, 9, Vector3.BACK, 0.1)
	# The heart, seen through the ribs.
	r.slot(S_HEART).rigid(ModelKit.sphere(0.13, 12), Transform3D(Basis(), Vector3(0, 1.47, -0.05)), CHEST)
	# Ribcage of slag shards: curving round the chest with a gap down the front.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var sd := 100
	for row in 4:
		var y := 1.28 + row * 0.11
		var rad := 0.27 - absf(float(row) - 1.5) * 0.02
		for side: float in [-1.0, 1.0]:
			for k in 3:
				var a := side * (0.55 + k * 0.62 + row * 0.04)
				var pos := Vector3(sin(a) * rad, y, -cos(a) * rad * 0.9)
				var yaw := rad_to_deg(-a)
				_shard(r, Vector3(0.085, 0.045, 0.06) * rng.randf_range(0.9, 1.2), pos, Vector3(rng.randf_range(-10, 10), yaw + 90.0, side * 8.0), CHEST, sd)
				sd += 1
	# Back plates and spine ridge.
	_shard(r, Vector3(0.22, 0.2, 0.09), Vector3(0, 1.5, 0.2), Vector3(10, 0, 0), CHEST, 140)
	for k in 4:
		_shard(r, Vector3(0.04, 0.09, 0.05), Vector3(0, 1.32 + k * 0.13, 0.27), Vector3(-30, 0, 0), CHEST, 141 + k, 4)
	# Shoulders: jagged basalt with spikes.
	for side: float in [-1.0, 1.0]:
		var sh := SH_L if side < 0.0 else SH_R
		var s0: Vector3 = r.rest[sh]
		_shard(r, Vector3(0.19, 0.12, 0.19), s0 + Vector3(side * 0.03, 0.07, 0), Vector3(0, 0, side * -22), sh, 150 + int(side + 1.0))
		for k in 3:
			var l := 0.17 - k * 0.03
			r.slot(S_ROCK).rigid(BossKit.crystal_mesh("elem_spike_%d" % k, l * 0.22, l, 5, 0.6, 0.1, 0.15), Transform3D(Basis.from_euler(Vector3(0.3 * (k - 1), 0, side * -(0.5 + k * 0.25))), s0 + Vector3(side * (0.06 + k * 0.05), 0.12, (k - 1) * 0.06)), sh)
		var e0: Vector3 = r.rest[sh + 1]
		var h0: Vector3 = r.rest[sh + 2]
		_shard(r, Vector3(0.075, 0.15, 0.075), s0.lerp(e0, 0.55), Vector3(0, 0, side * 10), sh, 153 + int(side + 1.0))
		# Gauntlet: two shards round the forearm, knuckles and claws.
		_shard(r, Vector3(0.1, 0.17, 0.085), e0.lerp(h0, 0.45) + Vector3(side * 0.03, 0, 0.02), Vector3(0, 0, side * 6), sh + 1, 156 + int(side + 1.0))
		_shard(r, Vector3(0.08, 0.14, 0.07), e0.lerp(h0, 0.5) + Vector3(-side * 0.03, 0, -0.05), Vector3(-8, 0, 0), sh + 1, 159 + int(side + 1.0))
		_shard(r, Vector3(0.08, 0.06, 0.085), h0 + Vector3(0, -0.04, -0.02), Vector3(0, 0, 0), sh + 2, 162 + int(side + 1.0), 5)
		for k in 3:
			var x := (float(k) - 1.0) * 0.045
			var claw := OrganicMesh.bezier("elem_claw", Vector3.ZERO, Vector3(0, -0.06, -0.03), Vector3(0, -0.13, 0.02), 0.022, 0.003, 6, 5)
			r.slot(S_ROCK).rigid(claw, Transform3D(Basis(Vector3.UP, x * 3.0), h0 + Vector3(x, -0.07, -0.06)), sh + 2)
		r.slot(S_ROCK).rigid(OrganicMesh.bezier("elem_thumb", Vector3.ZERO, Vector3(0, -0.05, -0.04), Vector3(0, -0.09, -0.02), 0.02, 0.003, 5, 5), Transform3D(Basis(), h0 + Vector3(-side * 0.065, -0.04, -0.03)), sh + 2)
	# Hip shards where the body becomes the vortex.
	for k in 5:
		var a := TAU * float(k) / 5.0 + 0.3
		_shard(r, Vector3(0.1, 0.11, 0.06), Vector3(sin(a) * 0.17, 0.9, -cos(a) * 0.15), Vector3(-25, rad_to_deg(-a), 0), WAIST, 170 + k, 5)
	# Skull of slag: cranium, two brow plates over hollow eyes, cheekbones, jaw, swept horns.
	var hd: Vector3 = r.rest[HEAD]
	_shard(r, Vector3(0.14, 0.13, 0.16), hd + Vector3(0, 0.07, 0.02), Vector3(0, 0, 0), HEAD, 180, 7)
	for side: float in [-1.0, 1.0]:
		_shard(r, Vector3(0.075, 0.032, 0.06), hd + Vector3(side * 0.055, 0.075, -0.12), Vector3(-10, side * -15, side * 18), HEAD, 181 + int(side + 1.0), 4)
		_shard(r, Vector3(0.045, 0.045, 0.07), hd + Vector3(side * 0.085, -0.01, -0.09), Vector3(0, side * 15, 0), HEAD, 184 + int(side + 1.0), 4)
		r.slot(S_EYE).rigid(ModelKit.sphere(1.0, 10), Transform3D(Basis.from_euler(Vector3(0, 0, side * 0.3)).scaled(Vector3(0.032, 0.016, 0.02)), hd + Vector3(side * 0.05, 0.035, -0.14)), HEAD)
		for k in 2:
			var horn := OrganicMesh.bezier("elem_horn_%d" % k, Vector3.ZERO, Vector3(side * 0.04, 0.07, 0.06), Vector3(side * 0.07, 0.11 - k * 0.03, 0.2 - k * 0.04), 0.03 - k * 0.006, 0.003, 8, 6)
			r.slot(S_ROCK).rigid(horn, Transform3D(Basis(), hd + Vector3(side * (0.06 + k * 0.03), 0.12 - k * 0.04, -0.02 + k * 0.03)), HEAD)
	_shard(r, Vector3(0.09, 0.045, 0.09), hd + Vector3(0, -0.07, -0.07), Vector3(12, 0, 0), HEAD, 188, 5)
	return r.build("elemental")


func _flame_data() -> Dictionary:
	if MobRig.has("elemental_flame"):
		return MobRig.cached("elemental_flame")
	var r := MobRig.new(1)
	_bones(r)
	# Body envelope rising into a crest that streams back off the crown.
	var rs := MobRig.resample(PackedVector3Array([Vector3(0, 0.78, 0), Vector3(0, 1.1, 0), Vector3(0, 1.45, 0.0), Vector3(0, 1.82, -0.02),
		Vector3(0, 2.1, 0.06), Vector3(0, 2.38, 0.22), Vector3(0, 2.6, 0.42)]),
		PackedVector2Array([Vector2(0.16, 0.16), Vector2(0.22, 0.2), Vector2(0.31, 0.25), Vector2(0.17, 0.17), Vector2(0.17, 0.15), Vector2(0.11, 0.09), Vector2(0.01, 0.01)]),
		[V1, WAIST, CHEST, HEAD, HEAD, HEAD, HEAD], 24)
	r.tube(rs[0], rs[1], rs[2], 0.15, 14)
	# The vortex: a twisting cone of fire down to the ground.
	# (The entity hovers half a metre up: the vortex licks the ground below.)
	var vs := MobRig.resample(PackedVector3Array([Vector3(0, 1.05, 0), Vector3(0, 0.66, 0), Vector3(0, 0.22, 0), Vector3(0, -0.2, 0), Vector3(0, -0.5, 0)]),
		PackedVector2Array([Vector2(0.3, 0.3), Vector2(0.24, 0.24), Vector2(0.16, 0.16), Vector2(0.1, 0.1), Vector2(0.03, 0.03)]),
		[WAIST, V1, V2, V3, V3], 22)
	r.tube(vs[0], vs[1], vs[2], 0.12, 14)
	# A crest of fire streaming back from the crown, flames off the shoulders.
	var cs := MobRig.resample(PackedVector3Array([Vector3(0, 1.98, -0.04), Vector3(0, 2.22, 0.06), Vector3(0, 2.48, 0.24), Vector3(0, 2.78, 0.5)]),
		PackedVector2Array([Vector2(0.13, 0.12), Vector2(0.12, 0.11), Vector2(0.08, 0.07), Vector2(0.01, 0.01)]), [HEAD, HEAD, HEAD, HEAD], 14)
	r.tube(cs[0], cs[1], cs[2], 0.1, 10)
	for side: float in [-1.0, 1.0]:
		var s0: Vector3 = r.rest[SH_L if side < 0.0 else SH_R]
		var ss := MobRig.resample(PackedVector3Array([s0 + Vector3(0, 0.05, 0), s0 + Vector3(side * 0.04, 0.25, 0.08), s0 + Vector3(side * 0.06, 0.5, 0.2)]),
			PackedVector2Array([Vector2(0.11, 0.11), Vector2(0.07, 0.07), Vector2(0.01, 0.01)]), [SH_L if side < 0.0 else SH_R, CHEST, CHEST], 10)
		r.tube(ss[0], ss[1], ss[2], 0.1, 8)
	# Burning arms and fists of fire.
	for side: float in [-1.0, 1.0]:
		var sh := SH_L if side < 0.0 else SH_R
		var h0: Vector3 = r.rest[sh + 2]
		var tip := h0 + (h0 - r.rest[sh + 1]).normalized() * 0.22
		r.limb(PackedVector3Array([r.rest[sh], r.rest[sh + 1], h0, tip]), [sh, sh + 1, sh + 2],
			[[0.0, 0.08, 0.08], [0.4, 0.09, 0.09], [0.75, 0.13, 0.13], [0.88, 0.12, 0.12], [1.0, 0.01, 0.01]], 16, 10, Vector3.BACK, 0.1)
	return r.build("elemental_flame")


# --- Animation -----------------------------------------------------------------------------

func _animate(delta: float) -> void:
	if skel == null:
		return
	var p := action_progress()
	var w := action_weight(0.12, 0.2)
	var act := _action if p >= 0.0 and not _dead else ""
	var speed := move_speed / rig_scale
	var flare := 1.0 + sin(_time * 7.3) * 0.06 + sin(_time * 13.1) * 0.04
	var arm := [Vector3(0.25 + sin(_time * 1.3) * 0.12, 0, -0.35 + sin(_time * 1.7) * 0.08), Vector3(0.25 + sin(_time * 1.1 + 1.0) * 0.12, 0, 0.35 - sin(_time * 1.5) * 0.08)]
	var elbow := [0.45 + sin(_time * 1.9) * 0.1, 0.45 + sin(_time * 1.6 + 2.0) * 0.1]
	var chest_t := Vector3(0, sin(_time * 0.7) * 0.1, 0)
	var head_t := Vector3(sin(_time * 0.9) * 0.08, sin(_time * 0.6) * 0.2, 0)
	var charge := 0.0
	match act:
		"throw", "attack", "cast", "shoot", "attack2":
			var wind := keys(p, [[0, 0], [0.5, 1.0], [RELEASE - 0.04, 1.0], [RELEASE + 0.06, 0.0], [1, 0]])
			var hurl := keys(p, [[0, 0], [RELEASE - 0.04, 0.0], [RELEASE + 0.08, 1.0], [0.9, 0.7], [1, 0]])
			arm[1] = (arm[1] as Vector3).lerp(Vector3(-1.1, 0.0, 0.9), wind).lerp(Vector3(1.5, 0, 0.15), hurl)
			elbow[1] = lerpf(lerpf(float(elbow[1]), 1.4, wind), 0.1, hurl)
			arm[0] = (arm[0] as Vector3).lerp(Vector3(0.9, 0, -0.5), wind)
			chest_t += Vector3(0.15 * wind - 0.25 * hurl, 0.5 * wind - 0.55 * hurl, 0)
			charge = smoothstep(0.08, RELEASE - 0.05, p) * (1.0 if p < RELEASE else 0.0)
			flare += 0.4 * wind + 0.6 * hurl
		"roar", "summon", "howl", "slam":
			arm[0] = (arm[0] as Vector3).lerp(Vector3(0.4, 0, -1.4), w)
			arm[1] = (arm[1] as Vector3).lerp(Vector3(0.4, 0, 1.4), w)
			elbow = [lerpf(float(elbow[0]), 0.3, w), lerpf(float(elbow[1]), 0.3, w)]
			chest_t.x -= 0.3 * w
			head_t.x += 0.5 * w
			flare += 1.3 * w
		"hit":
			var s := sin(PI * clampf(p * 1.3, 0.0, 1.0))
			chest_t.x -= 0.35 * s
			head_t.x += 0.3 * s
			flare *= 1.0 - 0.6 * s * (0.5 + 0.5 * sin(_time * 60.0))
		"lunge", "bite":
			chest_t.x += 0.3 * w
			arm[0] = (arm[0] as Vector3).lerp(Vector3(1.4, 0, -0.2), w)
			arm[1] = (arm[1] as Vector3).lerp(Vector3(1.4, 0, 0.2), w)
			flare += 0.5 * w
	_charge = damp(_charge, charge, 14.0, delta)
	_flare = damp(_flare, flare, 10.0, delta)
	_lean = damp(_lean, clampf(speed * 0.08, 0.0, 0.35), 4.0, delta)
	_swirl += delta * (3.0 + speed)

	var hover := sin(_time * 2.0) * 0.06
	place(WAIST, rest[WAIST] + Vector3(0, hover, 0), Basis.from_euler(Vector3(-_lean, sin(_time * 0.5) * 0.15, sin(_time * 1.2) * 0.04)))
	fk(CHEST, Vector3(chest_t.x - _lean * 0.3, chest_t.y, chest_t.z))
	fk(HEAD, Vector3(head_t.x + _lean * 0.5, head_t.y, 0))
	for i in 2:
		var sh := SH_L if i == 0 else SH_R
		fk(sh, arm[i])
		fk(sh + 1, Vector3(float(elbow[i]), 0, 0))
		fk(sh + 2, Vector3(0.2 + sin(_time * 2.3 + i) * 0.15, 0, 0))
	# The vortex twists and trails behind when moving.
	fk(V1, Vector3(_lean * 0.8 + sin(_time * 2.6) * 0.12, _swirl * 0.3, cos(_time * 2.1) * 0.12))
	fk(V2, Vector3(_lean * 0.6 + sin(_time * 3.1 + 1.0) * 0.18, _swirl * 0.3, cos(_time * 2.7) * 0.15))
	fk(V3, Vector3(sin(_time * 3.7 + 2.0) * 0.2, _swirl * 0.3, 0))

	if _dead:
		_pose_dead()
		body_mi.set_instance_shader_parameter(&"intensity", _death_fade())
	commit()

	var f := _flare
	if _dead:
		f = maxf(0.0, 1.0 - _dead_t * 1.2)
		_flames.emitting = _dead_t < 0.5
	flame_mi.set_instance_shader_parameter(&"flare", f)
	body_mi.set_instance_shader_parameter(&"inner_glow", (f - 1.0) * 0.8 if not _dead else -clampf(_dead_t, 0.0, 1.0))
	_fireball.visible = _charge > 0.02 and not _dead
	if _fireball.visible:
		_fireball.scale = Vector3.ONE * (0.3 + _charge * 0.9) * (1.0 + sin(_time * 25.0) * 0.08)
	_light.light_energy = maxf(0.0, 2.6 * f + _charge * 2.0 + sin(_time * 13.0) * 0.25)
	# Orbiting fragments.
	var mm := _shards.multimesh
	for i in _shard_data.size():
		var sdat: Array = _shard_data[i]
		var a := float(sdat[3]) + _time * float(sdat[2])
		var rad := float(sdat[0]) * (1.0 + 0.15 * (_flare - 1.0))
		var pos := Vector3(cos(a) * rad, float(sdat[1]) + sin(_time * 1.3 + a) * 0.05 + hover, sin(a) * rad)
		var b := Basis(sdat[4] as Vector3, _time * float(sdat[2]) * 0.7)
		if _dead:
			var t := clampf(_dead_t / 0.8, 0.0, 1.0)
			pos.y = lerpf(pos.y, 0.08, t * t)
		mm.set_instance_transform(i, Transform3D(b.scaled(Vector3.ONE * rig_scale), pos * rig_scale))


## The fire gutters out: the body sinks into the dying vortex, arms fall, head bows.
func _pose_dead() -> void:
	if not _death_pose:
		_death_pose = true
		_dead_gb = gb.duplicate()
		_dead_gp = gp.duplicate()
	var t := clampf(_dead_t / 1.0, 0.0, 1.0)
	var e := t * t * (3.0 - 2.0 * t)
	place(WAIST, Vector3(0, 0.05, 0.05), Basis.from_euler(Vector3(-0.5, 0.2, 0.15)))
	fk(CHEST, Vector3(-0.5, 0, 0.1))
	fk(HEAD, Vector3(-0.6, 0.3, 0))
	for i in 2:
		var sh := SH_L if i == 0 else SH_R
		fk(sh, Vector3(0.2, 0, (0.4 if i == 1 else -0.4)))
		fk(sh + 1, Vector3(0.2, 0, 0))
		fk(sh + 2, Vector3(0.0, 0, 0))
	fk(V1, Vector3(0.3, 0, 0))
	fk(V2, Vector3(0.5, 0, 0))
	fk(V3, Vector3(0.5, 0, 0))
	for b in bone_count:
		gb[b] = Basis(_dead_gb[b].get_rotation_quaternion().slerp(gb[b].get_rotation_quaternion(), e))
		gp[b] = _dead_gp[b].lerp(gp[b], e)


## Eyes (and the elemental's heart) go dark as it dies, before the body crumbles.
func _death_fade() -> float:
	return 1.0 if not _dead else clampf(1.0 - _dead_t / 0.5, 0.0, 1.0)


func set_glow_intensity(v: float) -> void:
	super.set_glow_intensity(v * _death_fade())


func set_dead(dead: bool) -> void:
	super.set_dead(dead)
	if not dead:
		_death_pose = false
		if _flames != null:
			_flames.emitting = true
