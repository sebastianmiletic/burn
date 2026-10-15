class_name CrawlerModel
extends CreatureModel
## Long-bodied creatures on a SerpentChain whose body follows the path of
## the head (the entity position):
##   "cave_crawler": a giant armoured centipede of the deep caves - glossy
##                   segmented chitin, a pair of legs on every segment rippling
##                   in a metachronal wave, venom forcipules, feelers, a row
##                   of glowing eyes.
##   "shark":        a grey reef shark - countershaded spindle body, dorsal,
##                   pectoral and crescent tail fins, rows of teeth.
## Faces -Z.

var species := "cave_crawler"
var k := 1.0
var chain: SerpentChain
var head: Node3D
var jaw: Node3D
var legs: Array = []   # [pivot, side, index]
var feelers: Array[Node3D] = []
var _prev := Vector3.INF
var _vel := Vector3.ZERO
var _look := Vector3.FORWARD
var _len := 5.0


func _init(kind_name := "cave_crawler", variant_seed := 0) -> void:
	species = kind_name
	var rng := RandomNumberGenerator.new()
	rng.seed = variant_seed
	k = rng.randf_range(0.9, 1.15)
	_len = (5.5 if species == "cave_crawler" else 3.4) * k
	dissolve_delay = 1.4


func _ember_extents() -> Vector3:
	return Vector3(0.5, 0.3, _len * 0.4)


func _lod_size() -> float:
	return _len * 0.6


func _build() -> void:
	if species == "shark":
		_build_shark()
	else:
		_build_crawler()


func _build_crawler() -> void:
	var bones := 14
	var shell := CreatureSkin.chitin(Color(0.3, 0.12, 0.08), {"use_uv": true, "pattern_scale": 1.0 / (_len / (bones - 1)) * 0.5,
		"accent": Color(0.85, 0.55, 0.15), "accent_mode": 3, "accent_amount": 0.35, "accent_scale": 1.0})
	var leg_mat := CreatureSkin.chitin(Color(0.55, 0.32, 0.12), {"pattern_scale": 8.0})
	var prof := [[0.0, 0.28 * k, 0.2 * k], [0.15, 0.36 * k, 0.24 * k], [0.7, 0.32 * k, 0.22 * k], [1.0, 0.12 * k, 0.1 * k]]
	var mesh := OrganicMesh.skinned_tube("crawler_body_%.2f" % k, _len, bones, prof, 56, 12)
	chain = SerpentChain.new().setup(mesh, shell, bones, _len, 20.0)
	chain.wave_amp = 0.12 * k
	chain.wave_count = 2.5
	chain.wave_speed = 6.0
	chain.stiffness = 0.15
	add_child(chain)
	# Segment ridges and legs.
	for i in range(1, bones - 1):
		var holder := Node3D.new()
		chain.attach(i, holder)
		ModelKit.part(holder, OrganicMesh.blob("crawler_plate_%.2f" % k, Vector3(0.38, 0.12, 0.16) * k, 0.05, 3, 12), shell, Vector3(0, 0.12 * k, 0))
		for side: float in [-1.0, 1.0]:
			var pivot := ModelKit.joint(holder, "Leg", Vector3(side * 0.28 * k, -0.02, 0))
			ModelKit.part(pivot, OrganicMesh.bezier("crawler_leg_%.2f_%d" % [k, int(side)], Vector3.ZERO, Vector3(side * 0.35, 0.15, 0) * k, Vector3(side * 0.55, -0.22, 0.05) * k, 0.04 * k, 0.012 * k, 6, 5), leg_mat)
			legs.append([pivot, side, i])
	head = Node3D.new()
	head.top_level = true
	add_child(head)
	ModelKit.part(head, OrganicMesh.blob("crawler_head_%.2f" % k, Vector3(0.32, 0.2, 0.36) * k, 0.08, 9, 12), shell, Vector3(0, 0, -0.15 * k))
	var eye := CreatureSkin.eye(Color(0.5, 1.0, 0.7), 6.0, 0.3)
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		ModelKit.part(head, ModelKit.sphere(0.035 * k, 6), eye, Vector3(side * (0.12 + (i / 2) * 0.06), 0.12, -0.38 + (i / 2) * 0.07) * k)
	for side: float in [-1.0, 1.0]:
		var f := ModelKit.joint(head, "Feeler", Vector3(side * 0.12, 0.1, -0.45) * k)
		ModelKit.part(f, OrganicMesh.bezier("crawler_feeler_%d" % int(side), Vector3.ZERO, Vector3(side * 0.3, 0.35, -0.4) * k, Vector3(side * 0.6, 0.2, -0.9) * k, 0.02 * k, 0.005 * k, 8, 4), leg_mat)
		feelers.append(f)
	jaw = ModelKit.joint(head, "Jaws", Vector3(0, -0.06, -0.45) * k)
	for side: float in [-1.0, 1.0]:
		ModelKit.part(jaw, OrganicMesh.bezier("crawler_fang_%d" % int(side), Vector3.ZERO, Vector3(side * 0.15, 0, -0.12) * k, Vector3(side * 0.02, -0.02, -0.28) * k, 0.045 * k, 0.006 * k, 6, 5), CreatureSkin.keratin(Color(0.1, 0.06, 0.05)), Vector3(side * 0.12 * k, 0, 0))


func _build_shark() -> void:
	var bones := 9
	var skin := CreatureSkin.smooth(Color(0.32, 0.36, 0.4), Color(0.88, 0.88, 0.86), {"use_uv": true, "belly_mix": 1.0, "wet": 0.8, "pattern": CreatureSkin.Pattern.HIDE, "pattern_scale": 3.0, "bump": 0.3})
	var fin := CreatureSkin.smooth(Color(0.28, 0.31, 0.35), Color(0.75, 0.76, 0.75), {"wet": 0.8})
	var prof := [[0.0, 0.32 * k, 0.36 * k], [0.25, 0.42 * k, 0.48 * k], [0.6, 0.28 * k, 0.32 * k], [0.88, 0.1 * k, 0.12 * k], [1.0, 0.06 * k, 0.08 * k]]
	var mesh := OrganicMesh.skinned_tube("shark_body_%.2f" % k, _len * 0.82, bones, prof, 40, 14)
	chain = SerpentChain.new().setup(mesh, skin, bones, _len * 0.82, 12.0)
	chain.wave_amp = 0.35 * k
	chain.wave_count = 0.8
	chain.wave_speed = 5.0
	chain.stiffness = 0.4
	add_child(chain)
	var dorsal := Node3D.new()
	chain.attach(2, dorsal)
	ModelKit.part(dorsal, OrganicMesh.membrane("shark_dorsal_%.2f" % k, _sc(PackedVector2Array([Vector2(0.3, 0), Vector2(-0.05, 0.62), Vector2(-0.2, 0.55), Vector2(-0.35, 0)])), 0.0, 0.05 * k), fin, Vector3(0, 0.42 * k, 0), Vector3(0, 90, 0))
	var pecs := Node3D.new()
	chain.attach(1, pecs)
	for side: float in [-1.0, 1.0]:
		var pts := _sc(PackedVector2Array([Vector2(0, 0.15), Vector2(side * 0.7, -0.3), Vector2(side * 0.55, -0.42), Vector2(0, -0.12)]))
		ModelKit.part(pecs, OrganicMesh.membrane("shark_pec_%.2f_%d" % [k, int(side)], pts, 0.0, 0.04 * k), fin, Vector3(side * 0.3 * k, -0.28 * k, 0), Vector3(-80, 0, side * -20))
	var tail := Node3D.new()
	chain.attach(bones - 1, tail)
	ModelKit.part(tail, OrganicMesh.membrane("shark_tail_%.2f" % k, _sc(PackedVector2Array([Vector2(0.15, 0), Vector2(-0.35, 0.85), Vector2(-0.5, 0.75), Vector2(-0.2, 0.0), Vector2(-0.4, -0.45), Vector2(-0.25, -0.5)])), 0.0, 0.04 * k), fin, Vector3(0, 0, 0.1 * k), Vector3(0, 90, 0))
	head = Node3D.new()
	head.top_level = true
	add_child(head)
	ModelKit.part(head, OrganicMesh.profile("shark_snout_%.2f" % k, Vector3(0, 0, 0.3 * k), Vector3(0, 0.02 * k, -0.62 * k), [[0.0, 0.32 * k, 0.36 * k], [0.55, 0.26 * k, 0.26 * k], [0.9, 0.12 * k, 0.12 * k], [1.0, 0.03 * k, 0.03 * k]], 14, 10), skin)
	jaw = ModelKit.joint(head, "Jaw", Vector3(0, -0.18, -0.05) * k)
	ModelKit.part(jaw, OrganicMesh.profile("shark_jaw_%.2f" % k, Vector3.ZERO, Vector3(0, 0, -0.42 * k), [[0.0, 0.22 * k, 0.1 * k], [1.0, 0.1 * k, 0.05 * k]], 10, 6), skin)
	var tooth := CreatureSkin.keratin(Color(0.92, 0.9, 0.85))
	for side: float in [-1.0, 1.0]:
		for i in 5:
			ModelKit.part(head, ModelKit.cone(0.018 * k, 0.07 * k, 4), tooth, Vector3(side * (0.18 - i * 0.025) * k, -0.17 * k, (-0.1 - i * 0.07) * k), Vector3(180, 0, 0))
		ModelKit.part(head, ModelKit.sphere(0.04 * k, 6), CreatureSkin.smooth(Color(0.02, 0.02, 0.02), Color(0.02, 0.02, 0.02), {"roughness": 0.05, "specular_amount": 1.0}), Vector3(side * 0.2 * k, 0.06 * k, -0.32 * k))
		for g in 4:
			ModelKit.part(head, ModelKit.box(Vector3(0.01, 0.16, 0.012) * k), CreatureSkin.mouth(Color(0.2, 0.1, 0.1)), Vector3(side * 0.31 * k, -0.02 * k, (0.12 + g * 0.06) * k), Vector3(0, side * 10, 0))


func _animate(delta: float) -> void:
	if chain == null:
		return
	var base := global_position
	if not _prev.is_finite():
		_prev = base
		chain.reset(base, global_transform.basis.z)
	_vel = _vel.lerp((base - _prev) / maxf(delta, 0.001), 1.0 - exp(-8.0 * delta))
	_prev = base
	var speed := _vel.length()
	var fwd := -global_transform.basis.z
	var look := _vel.normalized() if speed > 0.4 else fwd
	if species == "cave_crawler":
		look.y = clampf(look.y, -0.5, 0.5)
	_look = _look.slerp(look.normalized(), 1.0 - exp(-6.0 * delta)).normalized()
	if absf(_look.y) > 0.95:
		_look = fwd
	var p := action_progress()
	var w := action_weight()
	var lift := 0.3 * k if species == "cave_crawler" else 0.0
	var lunge := Vector3.ZERO
	var jaw_t := 0.05
	if p >= 0.0 and not _dead:
		match _action:
			"attack", "bite", "lunge", "attack2":
				var s := keys(p, [[0, 0], [0.35, -0.6], [0.55, 1.0], [1, 0]])
				lunge = fwd * s * 0.6 * k + Vector3.UP * maxf(0.0, -s) * 0.4 * k
				jaw_t = keys(p, [[0, 0.1], [0.4, 0.8], [0.6, 0.0], [1, 0.1]])
			"roar":
				lunge = Vector3.UP * 0.8 * k * w
				jaw_t = 0.8 * w
	if _dead:
		lift = 0.05
	var head_pos := base + Vector3.UP * lift + lunge
	var hb := Basis.looking_at(_look, Vector3.UP)
	head.global_transform = Transform3D(hb, head_pos)
	# Crawlers hug the ground they walk on; sharks keep level in the water.
	chain.rest_height = base.y + (0.25 * k if species == "cave_crawler" else 0.0)
	chain.rest_rate = 8.0 if species == "cave_crawler" else 2.0
	chain.simulate(head_pos, delta, 0.3 + speed / 3.0)
	chain.apply()
	if species == "shark":
		jaw.rotation.x = damp(jaw.rotation.x, jaw_t * 0.6, 14.0, delta)
		return
	for i in feelers.size():
		feelers[i].rotation = Vector3(sin(_time * 3.0 + i) * 0.25, sin(_time * 2.3 + i * 1.7) * 0.3, 0)
	for side_i in 2:
		jaw.rotation.y = 0.0
	jaw.scale = Vector3(1.0 + jaw_t * 0.4, 1.0, 1.0)
	var step := _time * (4.0 + speed * 3.0)
	for l: Array in legs:
		var pivot: Node3D = l[0]
		var side: float = l[1]
		var i: int = l[2]
		var ph := step - float(i) * 0.7 + (PI if side > 0.0 else 0.0)
		var amp := 0.15 + clampf(speed * 0.15, 0.0, 0.4)
		if _dead:
			pivot.rotation = Vector3(0, 0, side * 0.8)
		else:
			pivot.rotation = Vector3(0, sin(ph) * amp, side * maxf(0.0, cos(ph)) * 0.35)


func _sc(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p * k)
	return out
