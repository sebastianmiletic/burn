class_name VoidSovereignModel
extends RyftModel
## The Void Sovereign on the Crown of the Ryft: a towering regal shape cut out
## of the night sky - its body is a window onto stars and slow nebulae, rimmed
## in violet light. A smooth crystal mask with three burning eyes, a halo
## crown of floating shards, broad shoulders split by crystal ridges, long
## arms ending in crystal talons; below the waist it unravels into a trailing
## vortex of void tendrils over a pool of dark mist. Phase 2 sets the halo
## spinning and the tendrils lashing; phase 3 tears open a second, larger
## halo and the void bleeds stars.

const GLOW := Color(0.7, 0.45, 1.0)
const NEBULA := Color(0.25, 0.55, 1.0)
const CRYSTAL := Color(0.85, 0.75, 1.0)

var _body: Node3D
var _head: Node3D
var _halo: Node3D
var _halo2: Node3D
var _shoulders: Array[Node3D] = []
var _elbows: Array[Node3D] = []
var _tendrils: Array = []   # Array of Array[Node3D] (segment pivots)


func _ember_extents() -> Vector3:
	return Vector3(1.4, 3.0, 1.0)


func _lod_size() -> float:
	return 7.6


func _build() -> void:
	var k := _kit_key()
	var void_mat := BossKit.abyss(GLOW, NEBULA, 0.35)
	var crystal := BossKit.crystal(CRYSTAL, GLOW, 0.6)
	var mask := BossKit.crystal(Color(0.9, 0.9, 1.0), Color(0.8, 0.7, 1.0), 0.25)
	var eye := BossKit.glow(Color(1.0, 0.85, 1.0), 9.0, 0.4)
	_body = node(self, Vector3(0, 0.6, 0), "Body")
	# Torso: a tall tapering shape of night with crystal ridges.
	var b := BossKit.assembly()
	var torso := PackedVector2Array([Vector2(0.55, 2.4), Vector2(0.75, 3.0), Vector2(0.95, 3.8), Vector2(1.15, 4.5), Vector2(1.05, 5.0), Vector2(0.6, 5.35), Vector2(0.3, 5.5)])
	b.add(BossKit.lathe(k + "_torso", torso, 24, 1.0, 0.62, true, true), void_mat, Transform3D.IDENTITY)
	var skirt := PackedVector2Array([Vector2(1.25, 1.3), Vector2(1.05, 1.7), Vector2(0.8, 2.1), Vector2(0.6, 2.5)])
	b.add(BossKit.lathe(k + "_skirt", skirt, 24, 1.0, 0.8), void_mat, Transform3D.IDENTITY)
	for side: float in [-1.0, 1.0]:
		b.add(OrganicMesh.blob(k + "_shoulder", Vector3(0.6, 0.38, 0.45), 0.1, 81, 14), void_mat, Transform3D(Basis.IDENTITY, Vector3(side * 1.05, 4.9, 0)))
		for i in 3:
			b.add(BossKit.crystal_mesh(k + "_ridge_%d" % i, 0.1, 1.0 - i * 0.2, 6, 0.5, 0.2), crystal,
				Transform3D(Basis(Vector3.FORWARD, side * (0.35 + i * 0.25)), Vector3(side * (0.9 + i * 0.25), 5.15 - i * 0.12, -0.05 + i * 0.1)), Color(1, 1, 1))
	b.add(BossKit.crystal_mesh(k + "_spine", 0.12, 1.6, 6, 0.3, 0.3), crystal, Transform3D(Basis.IDENTITY, Vector3(0, 3.3, -0.62)), Color(1, 1, 1))
	b.add(BossKit.crystal_mesh(k + "_gem", 0.22, 0.6, 6, 0.5, 0.5), crystal, Transform3D(Basis.IDENTITY, Vector3(0, 4.15, -0.72)), Color(1, 1, 1))
	bake(_body, "body", b)
	add_light(_body, Vector3(0, 4.2, -1.2), GLOW, 2.0, 14.0)
	BossKit.emitter(_body, "shard", 30, Vector3(1.4, 2.0, 1.0), Color(0.9, 0.85, 1.0), 0.07, 2.0, 0.3)
	var mist := node(_body, Vector3(0, 0.0, 0), "Mist")
	BossKit.emitter(mist, "smoke", 26, Vector3(2.0, 0.2, 2.0), Color(0.1, 0.06, 0.18), 2.4, 3.0, 0.3)
	# Head: a smooth crystal mask with three eyes.
	_head = node(_body, Vector3(0, 5.6, 0), "Head")
	var h := BossKit.assembly()
	h.add(OrganicMesh.blob(k + "_skull", Vector3(0.36, 0.55, 0.4), 0.05, 82, 16), void_mat, Transform3D(Basis.IDENTITY, Vector3(0, 0.45, 0)))
	var face := BossKit.wrap_rows([[0.95, 0.24, 0.3, 0.02], [0.7, 0.33, 0.38, 0.06], [0.4, 0.31, 0.37, 0.08], [0.1, 0.22, 0.3, 0.06], [-0.05, 0.1, 0.22, 0.03]], -1.2, 1.2, 13)
	h.add(BossKit.plate(k + "_mask", face, 0.04, Vector3(0, 0.45, 0.2)), mask, Transform3D.IDENTITY, Color(1, 1, 1))
	for e in 3:
		var pos := [Vector3(-0.13, 0.52, -0.42), Vector3(0.13, 0.52, -0.42), Vector3(0, 0.74, -0.4)][e] as Vector3
		h.add(ModelKit.sphere(0.06, 10), eye, Transform3D(Basis.IDENTITY.scaled(Vector3(1.4, 0.6, 0.6)), pos))
	bake(_head, "head", h)
	# Halo crown of floating shards (and a greater one in the last phase).
	_halo = node(_head, Vector3(0, 0.6, 0.3), "Halo")
	_halo2 = node(_body, Vector3(0, 4.4, 0.6), "Halo2")
	for ring in 2:
		var ha := BossKit.assembly()
		var n := 11 if ring == 0 else 17
		var rad := 0.95 if ring == 0 else 2.6
		for i in n:
			var a := TAU * i / n
			var len := (0.55 if ring == 0 else 0.9) * (1.0 + 0.4 * float(i % 2))
			ha.add(BossKit.crystal_mesh("%s_halo_%d_%d" % [k, ring, i % 2], 0.07 if ring == 0 else 0.11, len, 6, 0.45, 0.2), crystal,
				Transform3D(Basis(Vector3.FORWARD, -a + PI * 0.5), Vector3(cos(a), sin(a), 0) * rad), Color(1, 1, 1))
		bake(_halo if ring == 0 else _halo2, "halo_%d" % ring, ha)
	_halo2.visible = false
	# Long arms ending in crystal talons.
	for side: float in [-1.0, 1.0]:
		var sh := node(_body, Vector3(side * 1.25, 4.9, 0), "Shoulder")
		var sa := BossKit.assembly()
		sa.add(OrganicMesh.bezier(k + "_upper", Vector3.ZERO, Vector3(side * 0.15, -0.9, 0), Vector3(side * 0.1, -1.8, 0.05), 0.3, 0.22, 10, 12), void_mat, Transform3D.IDENTITY)
		bake(sh, "shoulder_%d" % int(side), sa)
		var el := node(sh, Vector3(side * 0.1, -1.8, 0.05), "Elbow")
		var ea := BossKit.assembly()
		ea.add(OrganicMesh.bezier(k + "_fore", Vector3.ZERO, Vector3(0, -0.85, -0.05), Vector3(0, -1.7, 0.0), 0.22, 0.15, 10, 12), void_mat, Transform3D.IDENTITY)
		for f in 4:
			var a := lerpf(-0.6, 0.6, f / 3.0)
			ea.add(BossKit.crystal_mesh(k + "_talon", 0.06, 0.9, 6, 0.6, 0.1), crystal,
				Transform3D(Basis(Vector3.RIGHT, PI - 0.25) * Basis(Vector3.FORWARD, a * 0.6), Vector3(sin(a) * 0.14, -1.7, cos(a) * 0.05 - 0.04)), Color(1, 1, 1))
		bake(el, "elbow_%d" % int(side), ea)
		_shoulders.append(sh)
		_elbows.append(el)
	# The vortex: tendrils of void, each a chain of segments.
	for i in 7:
		var a := TAU * i / 7.0
		var root := node(_body, Vector3(cos(a) * 0.95, 1.45, sin(a) * 0.8), "Tendril")
		root.rotation = Vector3(0, -a + PI * 0.5, 0)
		var segs: Array[Node3D] = []
		var parent := root
		for j in 4:
			var seg := node(parent, Vector3(0, 0, 0) if j == 0 else Vector3(0.0, -0.4, 0.0), "Seg")
			var ta := BossKit.assembly()
			ta.add(OrganicMesh.bezier("%s_tseg_%d" % [k, j], Vector3.ZERO, Vector3(0.08, -0.2, 0.0), Vector3(0.0, -0.42, 0.0), 0.22 - j * 0.045, 0.18 - j * 0.045, 6, 8), void_mat, Transform3D.IDENTITY)
			bake(seg, "tseg_%d" % j, ta)
			segs.append(seg)
			parent = seg
		_tendrils.append(segs)


func _pose_ryft(delta: float) -> void:
	var t := _time
	var p := action_progress()
	var w := action_weight(0.12, 0.22)
	var surge := phase_surge()
	var recoil := hit_recoil()
	_hover = damp(_hover, 0.0 if _dead else 1.0, 2.0, delta)
	# Pose parameters: arms (forward, out, bend per side), body pitch / twist /
	# height, halo flare, tendril flare (outward) and whip (forward lash),
	# blink scale, head tilt.
	var r_arm := Vector3(0.12, 0.18, 0.4)
	var l_arm := Vector3(0.12, 0.18, 0.4)
	var pitch := 0.0
	var twist := 0.0
	var lift := 0.0
	var flare := 0.0
	var tflare := 0.0
	var whip := 0.0
	var blink := 1.0
	var head := 0.0
	if p >= 0.0 and not _dead:
		match _action:
			"lash", "sweep", "attack", "attack2":
				# Coils to one side, then the arm and the tendrils whip across.
				var coil := keys(p, [[0, 0], [0.42, 1.0], [0.55, 0.0]])
				var hit := keys(p, [[0.42, 0.0], [0.55, 1.0], [0.75, 0.8], [1, 0]])
				r_arm = Vector3(0.4 + 1.0 * hit, 1.3 * coil - 0.4 * hit, 0.9 * coil)
				l_arm = Vector3(0.3 + 0.4 * coil, 0.4, 0.6)
				twist = 0.55 * coil - 0.6 * hit
				pitch = 0.15 * hit
				whip = hit
				tflare = 0.3 * coil
			"volley", "cast", "throw":
				# Star orbs: both hands raised, palms out, flicking bolts in turn.
				var up := keys(p, [[0, 0], [0.2, 1.0], [0.85, 1.0], [1, 0]])
				var flick := sin(p * PI * 10.0) * up
				r_arm = Vector3(1.9 * up + 0.2 * flick, 0.5 * up, 0.5 - 0.3 * flick)
				l_arm = Vector3(1.9 * up - 0.2 * flick, 0.5 * up, 0.5 + 0.3 * flick)
				flare = 0.6 * up
				head = 0.2 * up
			"rift":
				# Reaches out and clenches: the floor beneath its target folds.
				var reach := keys(p, [[0, 0], [0.4, 1.0], [0.55, 1.0], [0.8, 0.6], [1, 0]])
				var clench := keys(p, [[0.45, 0.0], [0.55, 1.0], [0.85, 1.0], [1, 0]])
				r_arm = Vector3(1.5 * reach, 0.2, 0.2 + 1.2 * clench)
				l_arm = Vector3(0.3, 0.3 + 0.3 * reach, 0.5)
				pitch = 0.2 * reach
				tflare = 0.3 * clench
			"pull":
				# Gravity well: arms flung wide, then dragged in to the chest.
				var open := keys(p, [[0, 0], [0.35, 1.0], [0.55, 0.0]])
				var draw := keys(p, [[0.4, 0.0], [0.55, 1.0], [0.85, 1.0], [1, 0]])
				r_arm = Vector3(0.6 + 0.6 * draw, 1.6 * open - 0.3 * draw, 1.6 * draw)
				l_arm = r_arm
				pitch = -0.2 * open + 0.25 * draw
				tflare = 1.0 * open - 0.4 * draw
				flare = 0.5 * draw
			"starfall":
				# Rises with both arms lifted to the sky, then brings them down.
				var raise := keys(p, [[0, 0], [0.25, 1.0], [0.8, 1.0], [1, 0]])
				r_arm = Vector3(2.9 * raise, 0.4 * raise + 0.06 * sin(t * 5.0), 0.1)
				l_arm = Vector3(2.9 * raise, 0.4 * raise + 0.06 * sin(t * 5.0 + 1.2), 0.1)
				head = 0.6 * raise
				pitch = -0.15 * raise
				flare = 1.0 * raise
				lift = 0.3 * raise
			"teleport":
				# Folds into its own shadow and unfolds where it lands.
				blink = keys(p, [[0, 1.0], [0.5, 0.05], [0.62, 0.05], [1, 1.0]])
				r_arm = Vector3(0.6, -0.2, 1.6) * (1.0 - blink)
				l_arm = r_arm
				tflare = -0.5 * (1.0 - blink)
				flare = 1.0 - blink
			"charge":
				# Rears up, then plunges head-first along the lane, tendrils streaming.
				var rear := keys(p, [[0, 0], [0.45, 1.0], [0.55, 0.0]])
				var dive := keys(p, [[0.48, 0.0], [0.56, 1.0], [0.85, 1.0], [1, 0]])
				r_arm = Vector3(-0.6 * rear + 1.3 * dive, 0.8 * rear + 0.2 * dive, 0.3)
				l_arm = r_arm
				pitch = -0.3 * rear + 0.7 * dive
				lift = 0.3 * rear - 0.2 * dive
				tflare = -0.6 * dive
			"summon", "roar", "phase":
				r_arm = Vector3(1.2 * w, 1.4 * w, 0.2)
				l_arm = r_arm
				head = 0.5 * w
				flare = w
				tflare = 0.6 * w
			"eclipse":
				# Crosses its arms over the mask, then throws them open as the
				# rings erupt one after another.
				var cross := keys(p, [[0, 0], [0.35, 1.0], [0.5, 0.0]])
				var fling := keys(p, [[0.4, 0.0], [0.55, 1.0], [0.9, 1.0], [1, 0]])
				r_arm = Vector3(1.8 * cross + 0.6 * fling, -0.6 * cross + 1.7 * fling, 1.5 * cross)
				l_arm = r_arm
				head = -0.3 * cross + 0.6 * fling
				pitch = 0.2 * cross - 0.2 * fling
				flare = 0.4 * cross + 1.0 * fling
				tflare = 1.0 * fling
				lift = 0.4 * fling
			"special1":
				# Mirrored clones: one arm points at each reflection in turn.
				var hold := keys(p, [[0, 0], [0.25, 1.0], [0.9, 1.0], [1, 0]])
				twist = sin(p * TAU * 1.2) * 0.7 * hold
				r_arm = Vector3(1.5 * hold, 0.6 * hold, 0.1)
				l_arm = Vector3(0.4 * hold, 1.0 * hold, 0.4)
				flare = 0.7 * hold
				whip = 0.5 * hold * absf(sin(p * PI * 3.0))
			"special2":
				# Black hole: arms spread, everything drawn inwards, then a release.
				var spread := keys(p, [[0, 0], [0.3, 1.0], [0.55, 1.0], [0.65, 0.0]])
				var release := keys(p, [[0.55, 0.0], [0.7, 1.0], [1, 0]])
				r_arm = Vector3(0.8 * spread + 0.2 * release, 1.5 * spread + 1.8 * release, 0.8 * spread)
				l_arm = r_arm
				head = 0.3 * spread + 0.5 * release
				pitch = 0.2 * spread - 0.3 * release
				tflare = -0.5 * spread + 1.3 * release
				flare = 0.6 * spread + 1.0 * release
				lift = 0.5 * release
	# Phase change: the shape convulses, arms thrown wide, the halo tears open.
	if surge > 0.0 and not _dead:
		var shake := sin(t * 43.0) * 0.07 * surge
		r_arm = r_arm.lerp(Vector3(1.4, 1.6, 0.0), surge * 0.7)
		l_arm = l_arm.lerp(Vector3(1.4, 1.6, 0.0), surge * 0.7)
		pitch += shake - 0.25 * surge
		twist += shake
		head += 0.6 * surge
		flare += 1.2 * surge
		tflare += 1.0 * surge
	pitch -= 0.3 * recoil
	head -= 0.4 * recoil
	r_arm += Vector3(-0.4, 0.4, 0.3) * recoil
	l_arm += Vector3(-0.4, 0.4, 0.3) * recoil
	tflare += 0.4 * recoil
	_body.position.y = (0.6 + sin(t * 0.8) * 0.18 + lift) * _hover - 1.2 * _break
	var tumble := _tumble * _break * 0.6
	_body.rotation = Vector3(pitch + _lean.x + tumble.x, twist, _lean.z + tumble.z)
	_body.scale = Vector3.ONE * blink
	var spin := 0.4 + _power * 0.9 + flare * 2.5
	_halo.rotation.z += delta * spin
	_halo.scale = damp_v(_halo.scale, Vector3.ONE * (1.0 + 0.25 * flare) * (1.0 - _break * 0.7), 6.0, delta)
	if _halo2.visible:
		_halo2.rotation.z -= delta * spin * 0.6
		_halo2.scale = damp_v(_halo2.scale, Vector3.ONE * (1.0 + 0.2 * flare) * (1.0 - _break), 4.0, delta)
	pose(_head, Vector3(-head * 0.5 + sin(t * 0.5) * 0.04 + _break * 0.7 - 0.1 * _lean.x, sin(t * 0.33) * 0.2 - twist * 0.4, 0), 8.0, delta)
	if _dead:
		# Death: the arms fall slack, the halos dim and shrink, the shape sinks
		# into its own mist.
		r_arm = Vector3(-0.2 * _break, 0.3, 0.2)
		l_arm = r_arm
		tflare = -0.6 * _break
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var a := l_arm if i == 0 else r_arm
		var sway := sin(t * 0.7 + i) * 0.05
		arm(_shoulders[i], _elbows[i], side, a.x + sway, a.y + sway, a.z, 8.0, delta)
	var lash := 1.0 + _power * 1.5 + flare + whip * 2.0
	for i in _tendrils.size():
		var segs: Array = _tendrils[i]
		for j in segs.size():
			var seg: Node3D = segs[j]
			var ph := t * (1.3 + 0.2 * i) * lash - j * 0.9 + i * 1.3
			# Tendrils trail behind travel (lean) and flare outwards on demand.
			var base := 0.55 + tflare * 0.35 - (whip * 0.5 if j > 0 else 0.0)
			var target := Vector3(base + sin(ph) * 0.25 * (1 + j * 0.3) + _break * 0.4 - _lean.x * 0.6,
				0, cos(ph * 0.8) * 0.3)
			seg.rotation = seg.rotation.lerp(target, 1.0 - exp(-12.0 * delta))


func _on_boss_phase(new_phase: int) -> void:
	if new_phase >= 3:
		_halo2.visible = true
		BossKit.emitter(_body, "shard", 60, Vector3(2.2, 2.6, 1.6), GLOW, 0.1, 1.4, 1.0)
