class_name RyftSentinelModel
extends RyftModel
## The Prism Sentinel of the Broken Observatory: a 6 m construct that never
## touches the ground. A burning prism heart turns inside three bronze
## astrolabe rings; a cracked bronze carapace holds it; a crown of crystal
## spires with one cold eye floats above; its arms are chains of great
## crystal shards with gaps of light between them, ending in clustered
## fists, and a ring of shards orbits its tapering crystal root. Phase 2 sets
## the rings racing, phase 3 bursts the carapace and the heart blazes.

const CRYSTAL := Color(0.62, 0.55, 0.95)
const CRYSTAL2 := Color(0.75, 0.95, 1.0)
const GLOW := Color(0.6, 0.75, 1.0)
const BRONZE := Color(0.62, 0.48, 0.28)
const BRONZE_DARK := Color(0.38, 0.29, 0.18)

var _body: Node3D
var _heart: Node3D
var _rings: Array[Node3D] = []
var _head: Node3D
var _shoulders: Array[Node3D] = []
var _elbows: Array[Node3D] = []
var _fists: Array[Node3D] = []
var _orbit: Node3D
var _carapace: Node3D
var _fall := {}


func _ember_extents() -> Vector3:
	return Vector3(1.4, 2.6, 1.0)


func _lod_size() -> float:
	return 6.4


func _build() -> void:
	var k := _kit_key()
	var crystal := BossKit.crystal(CRYSTAL2, GLOW, 0.55)
	var core := BossKit.crystal(Color(1, 1, 1), Color(0.75, 0.85, 1.0), 2.2)
	var bronze := BossKit.metal({"rust": 0.0, "wear": 0.6, "grime": 0.35, "roughness": 0.32, "pattern_scale": 3.0,
		"rune": 1.0, "rune_color": GLOW, "rune_energy": 3.0, "rune_scale": 2.5})
	var eye := BossKit.glow(Color(0.85, 0.95, 1.0), 9.0, 0.3)
	_body = node(self, Vector3(0, 1.0, 0), "Body")
	# Heart and its light.
	_heart = node(_body, Vector3(0, 2.6, 0), "Heart")
	var h := BossKit.assembly()
	h.add(BossKit.crystal_mesh(k + "_heart", 0.5, 1.5, 4, 0.5, 0.5), core, Transform3D(Basis.IDENTITY, Vector3(0, -0.75, 0)), Color(1, 1, 1))
	bake(_heart, "heart", h)
	add_light(_heart, Vector3.ZERO, GLOW, 3.0, 16.0)
	BossKit.emitter(_heart, "shard", 24, Vector3(0.6, 0.8, 0.6), GLOW, 0.1, 1.2, 0.4)
	# Astrolabe rings.
	for i in 3:
		var r := node(_body, Vector3(0, 2.6, 0), "Ring")
		var asm := BossKit.assembly()
		var rad := 1.25 - i * 0.18
		asm.add(BossKit.torus("%s_ring_%d" % [k, i], rad, 0.045, 48, 6, 1.0), bronze, Transform3D.IDENTITY, BRONZE if i != 1 else Color(0.55, 0.43, 0.26, 0.0))
		for s in 6:
			var a := TAU * s / 6.0
			asm.add(BossKit.crystal_mesh(k + "_stud", 0.06, 0.24, 6, 0.4, 0.4), crystal, Transform3D(Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), PI * 0.5), Vector3(cos(a), 0, sin(a)) * rad), Color(1, 1, 1))
		bake(r, "ring_%d" % i, asm)
		r.rotation = Vector3(0.4 * i, 0.0, 0.7 * (i - 1))
		_rings.append(r)
	# Cracked bronze carapace: shoulder yoke and a broken breastplate.
	_carapace = node(_body, Vector3.ZERO, "Carapace")
	var c := BossKit.assembly()
	c.add(BossKit.shell(k + "_breast", Vector3(1.05, 0.75, 0.62), -75, 75, 35, 125, 0.07, 18, 10), bronze, Transform3D(Basis.IDENTITY, Vector3(0, 3.45, 0)), BRONZE)
	c.add(BossKit.shell(k + "_back", Vector3(1.05, 0.75, 0.62), 110, 250, 35, 125, 0.07, 18, 10), bronze, Transform3D(Basis.IDENTITY, Vector3(0, 3.45, 0)), BRONZE_DARK)
	c.add(BossKit.torus(k + "_collar", 0.7, 0.07, 32, 6, 1.0), bronze, Transform3D(Basis.IDENTITY.scaled(Vector3(1.4, 1.0, 1.0)), Vector3(0, 4.05, 0)), Color(0.5, 0.4, 0.24, 0.0))
	# A bronze spine holding head, heart and root together.
	var spine := PackedVector2Array([Vector2(0.09, 1.6), Vector2(0.12, 2.2), Vector2(0.1, 3.4), Vector2(0.13, 4.5), Vector2(0.08, 4.7)])
	c.add(BossKit.lathe(k + "_spine", spine, 8), bronze, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.55)), BRONZE_DARK)
	for i in 5:
		c.add(BossKit.torus(k + "_vert", 0.16, 0.04, 12, 5), bronze, Transform3D(Basis.IDENTITY, Vector3(0, 2.0 + i * 0.6, 0.55)), BRONZE)
	# A root of crystals tapering to a point beneath.
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		var tilt := Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), 2.9 + 0.12 * (i % 2))
		c.add(BossKit.crystal_mesh("%s_root_%d" % [k, i % 2], 0.22, 1.8 - (i % 2) * 0.4, 6, 0.45, 0.1, 0.2), crystal, Transform3D(tilt, Vector3(cos(a) * 0.3, 2.1, sin(a) * 0.3)), Color(1, 1, 1))
	c.add(BossKit.crystal_mesh(k + "_rootmain", 0.35, 2.4, 6, 0.5, 0.1, 0.1), crystal, Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, 2.2, 0)), Color(1, 1, 1))
	bake(_carapace, "carapace", c)
	# Head: a crown of spires around one eye, a bronze halo behind.
	_head = node(_body, Vector3(0, 4.55, 0), "Head")
	var hd := BossKit.assembly()
	for i in 7:
		var a := TAU * i / 7.0
		var tall := 0.9 + 0.6 * float(i == 0) + 0.2 * (i % 2)
		var lean := Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), -0.25)
		hd.add(BossKit.crystal_mesh("%s_spire_%d" % [k, int(tall * 10)], 0.13, tall, 6, 0.45, 0.15, 0.2), crystal, Transform3D(lean, Vector3(cos(a) * 0.32, 0.0, sin(a) * 0.32)), Color(1, 1, 1))
	hd.add(ModelKit.sphere(0.2, 14), eye, Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 0.7, 0.6)), Vector3(0, 0.35, -0.38)))
	hd.add(BossKit.torus(k + "_halo", 0.75, 0.035, 40, 5), bronze, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.5, 0.45)), Color(0.6, 0.48, 0.28, 0.0))
	bake(_head, "head", hd)
	# Arms: floating shard segments.
	for side: float in [-1.0, 1.0]:
		var sh := node(_body, Vector3(side * 1.55, 3.85, 0), "Shoulder")
		var sa := BossKit.assembly()
		for i in 4:
			var a := TAU * i / 4.0
			sa.add(BossKit.crystal_mesh("%s_sh_%d" % [k, i], 0.2, 0.9 - i * 0.1, 6, 0.45, 0.2, 0.1), crystal,
				Transform3D(Basis(Vector3.FORWARD, side * (0.5 + i * 0.25)).rotated(Vector3.UP, a * 0.3), Vector3(side * 0.1, 0.1, (i - 1.5) * 0.18)), Color(1, 1, 1))
		sa.add(BossKit.shell(k + "_pauldron", Vector3(0.6, 0.45, 0.55), -110, 110, 0, 80, 0.06, 14, 6), bronze, Transform3D(Basis(Vector3.UP, -side * PI * 0.5), Vector3(0, 0.05, 0)), BRONZE)
		sa.add(BossKit.crystal_mesh(k + "_upper", 0.34, 1.45, 6, 0.3, 0.3), crystal, Transform3D(Basis(Vector3.RIGHT, PI), Vector3(side * 0.05, -0.35, 0)), Color(1, 1, 1))
		bake(sh, "shoulder_%d" % int(side), sa)
		var el := node(sh, Vector3(side * 0.05, -1.85, 0), "Elbow")
		var ea := BossKit.assembly()
		ea.add(BossKit.crystal_mesh(k + "_fore", 0.38, 1.55, 6, 0.3, 0.3, 0.15), crystal, Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, -0.15, 0)), Color(1, 1, 1))
		ea.add(BossKit.torus(k + "_bracer", 0.32, 0.05, 24, 5), bronze, Transform3D(Basis.IDENTITY, Vector3(0, -0.55, 0)), BRONZE_DARK)
		bake(el, "elbow_%d" % int(side), ea)
		var fist := node(el, Vector3(0, -1.85, 0), "Fist")
		var fa := BossKit.assembly()
		for i in 5:
			var a := TAU * i / 5.0
			fa.add(BossKit.crystal_mesh(k + "_knuckle", 0.24, 0.85, 6, 0.4, 0.2), crystal,
				Transform3D(Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), 2.7), Vector3(cos(a) * 0.15, 0.1, sin(a) * 0.15)), Color(1, 1, 1))
		bake(fist, "fist", fa)
		_shoulders.append(sh)
		_elbows.append(el)
		_fists.append(fist)
	# Orbiting shards.
	_orbit = node(_body, Vector3(0, 1.0, 0), "Orbit")
	var oa := BossKit.assembly()
	for i in 9:
		var a := TAU * i / 9.0
		oa.add(BossKit.crystal_mesh(k + "_orb", 0.12, 0.55 + 0.15 * (i % 3), 6, 0.45, 0.45), crystal,
			Transform3D(Basis(Vector3.FORWARD, 0.4 * sin(i * 1.7)), Vector3(cos(a), 0.15 * sin(i * 2.0), sin(a)) * Vector3(1.9, 1.0, 1.9)), Color(1, 1, 1))
	bake(_orbit, "orbit", oa)


func _pose_ryft(delta: float) -> void:
	var t := _time
	var p := action_progress()
	var w := action_weight(0.12, 0.22)
	var surge := phase_surge()
	var recoil := hit_recoil()
	var spin := 1.0 + _power * 1.6 + surge * 3.0
	_hover = damp(_hover, 0.0 if _dead else 1.0, 2.0, delta)
	var bob := sin(t * 1.1) * 0.15
	# Action pose parameters: arms (forward, out, bend per side), body pitch /
	# twist / height, heart size, orbit spread, ring alignment, blink scale.
	var r_arm := Vector3(0.15, 0.12, 0.35)
	var l_arm := Vector3(0.15, 0.12, 0.35)
	var pitch := 0.0
	var twist := 0.0
	var lift := 0.0
	var heart := 0.0
	var orbit := 0.0
	var align := 0.0
	var blink := 1.0
	var head_up := 0.0
	if p >= 0.0 and not _dead:
		match _action:
			"thrust", "cast", "throw", "attack":
				# Lance: the right arm draws back while a shard forms, then punches.
				var draw := keys(p, [[0, 0], [0.42, 1.0], [0.55, 0.0]])
				var punch := keys(p, [[0.42, 0.0], [0.55, 1.0], [0.8, 1.0], [1, 0]])
				r_arm = Vector3(lerpf(-0.7 * draw, 1.55, punch), 0.15 + 0.3 * draw, 1.3 * draw)
				l_arm = Vector3(0.5 * draw + 0.2, 0.4, 0.9)
				twist = 0.35 * draw - 0.3 * punch
				pitch = 0.18 * punch - 0.08 * draw
				heart = 0.3 * draw
			"swipe", "sweep", "attack2":
				# Backhand: the right arm swings out and back, then rakes across.
				var wind := keys(p, [[0, 0], [0.4, 1.0], [0.55, 0.0]])
				var rake := keys(p, [[0.4, 0.0], [0.55, 1.0], [0.75, 0.9], [1, 0]])
				r_arm = Vector3(0.6 + 0.8 * rake, 1.4 * wind - 0.5 * rake, 0.2)
				l_arm = Vector3(0.3, 0.5 * wind + 0.2, 0.6)
				twist = 0.6 * wind - 0.7 * rake
				pitch = 0.12 * rake
			"slam", "spikes":
				# Both fists rise overhead, tremble, crash down.
				var up := keys(p, [[0, 0], [0.4, 1.0], [0.5, 1.05], [0.55, 0.0]])
				var down := keys(p, [[0.45, 0.0], [0.55, 1.0], [0.85, 1.0], [1, 0]])
				var arm_f := 2.8 * up + 1.0 * down + sin(t * 40.0) * 0.04 * up
				r_arm = Vector3(arm_f, 0.25 - 0.15 * down, 0.3 * up)
				l_arm = r_arm
				pitch = -0.15 * up + 0.4 * down
				lift = 0.3 * up - 0.5 * down
				head_up = 0.3 * up
			"nova":
				# Curls in around the heart, then bursts open.
				var curl := keys(p, [[0, 0], [0.45, 1.0], [0.55, 0.0]])
				var burst := keys(p, [[0.48, 0.0], [0.58, 1.0], [0.85, 0.6], [1, 0]])
				r_arm = Vector3(1.0 * curl + 0.3 * burst, -0.5 * curl + 1.6 * burst, 1.4 * curl)
				l_arm = r_arm
				pitch = 0.25 * curl - 0.15 * burst
				lift = -0.35 * curl + 0.3 * burst
				heart = -0.25 * curl + 0.7 * burst
				orbit = -0.4 * curl + 1.2 * burst
				spin += 5.0 * burst
			"beam":
				# The heart opens and pours its light forward.
				var open := keys(p, [[0, 0], [0.5, 1.0], [0.9, 1.0], [1, 0]])
				r_arm = Vector3(-0.4 * open, 1.1 * open, 0.4)
				l_arm = r_arm
				pitch = keys(p, [[0, 0], [0.45, -0.2], [0.55, 0.2], [0.9, 0.2], [1, 0]])
				heart = 0.55 * open + 0.1 * sin(t * 18.0) * open
				align = open
				head_up = -0.2 * open
			"volley":
				# Arms raised high, the shard orbit lifts and scatters crystal.
				var raise := keys(p, [[0, 0], [0.2, 1.0], [0.85, 1.0], [1, 0]])
				r_arm = Vector3(2.6 * raise, 0.6 * raise + 0.08 * sin(t * 6.0), 0.2)
				l_arm = Vector3(2.6 * raise, 0.6 * raise + 0.08 * sin(t * 6.0 + 1.5), 0.2)
				head_up = 0.4 * raise
				orbit = 0.9 * raise
				heart = 0.25 * raise
				spin += 2.0 * raise
			"special1":
				# Refraction mirrors: arms aim at different points, the heart
				# pulses once for each mirror.
				var hold := keys(p, [[0, 0], [0.3, 1.0], [0.85, 1.0], [1, 0]])
				r_arm = Vector3(1.5 * hold, 0.9 * hold, 0.1)
				l_arm = Vector3(0.6 * hold, 1.5 * hold, 0.1)
				twist = 0.25 * sin(p * TAU * 1.5) * hold
				heart = 0.4 * absf(sin(p * PI * 3.0)) * hold
				align = hold
			"teleport":
				# Folds into a point of light, then unfolds where it lands.
				blink = keys(p, [[0, 1.0], [0.7, 0.08], [0.78, 0.08], [1, 1.0]])
				r_arm = Vector3(0.8, -0.3, 1.5) * (1.0 - blink)
				l_arm = r_arm
				spin += 6.0 * (1.0 - blink)
			"charge":
				# Rears back, then rams head-first, both fists leading.
				var rear := keys(p, [[0, 0], [0.45, 1.0], [0.55, 0.0]])
				var ram := keys(p, [[0.48, 0.0], [0.56, 1.0], [0.85, 1.0], [1, 0]])
				r_arm = Vector3(-0.8 * rear + 1.6 * ram, 0.5 * rear - 0.15 * ram, 0.4 * rear)
				l_arm = r_arm
				pitch = -0.3 * rear + 0.6 * ram
				lift = 0.2 * rear - 0.3 * ram
				heart = 0.4 * ram
			"spin":
				# Shard orbit: arms out level, the whole body spins twice.
				var out := keys(p, [[0, 0], [0.3, 1.0], [0.85, 1.0], [1, 0]])
				r_arm = Vector3(0.2, 1.5 * out, 0.0)
				l_arm = r_arm
				twist = keys(p, [[0.3, 0.0], [0.9, TAU * 2.0]])
				orbit = 1.6 * out
				spin += 4.0 * out
			"special2":
				# Constellation: rises slowly, arms lift, rings align, the heart blazes.
				var rise := keys(p, [[0, 0], [0.5, 1.0], [0.9, 1.0], [1, 0]])
				var blaze := keys(p, [[0.45, 0.0], [0.55, 1.0], [0.8, 0.5], [1, 0]])
				r_arm = Vector3(1.6 * rise, 1.0 * rise, 0.3)
				l_arm = r_arm
				lift = 0.6 * rise
				head_up = 0.5 * rise
				heart = 0.3 * rise + 0.7 * blaze
				align = rise
			"phase", "roar", "summon":
				r_arm = Vector3(1.0 * w, 1.6 * w, 0.0)
				l_arm = r_arm
				head_up = 0.5 * w
				heart = 0.6 * w
				spin += 3.0 * w
	# Phase change: it shudders and throws its arms wide as the shell breaks.
	if surge > 0.0 and not _dead:
		var shake := sin(t * 47.0) * 0.06 * surge
		r_arm = r_arm.lerp(Vector3(0.9, 1.7, 0.0), surge * 0.7)
		l_arm = l_arm.lerp(Vector3(0.9, 1.7, 0.0), surge * 0.7)
		pitch += shake - 0.2 * surge
		twist += shake
		heart += 0.8 * surge
		head_up += 0.5 * surge
	# A flinch: the body recoils, the head snaps back, the arms jerk out.
	pitch -= 0.3 * recoil
	r_arm += Vector3(-0.3, 0.3, 0.2) * recoil
	l_arm += Vector3(-0.3, 0.3, 0.2) * recoil
	head_up += 0.4 * recoil
	_body.position.y = (1.0 + bob + lift) * _hover - 0.8 * _break
	var tumble := _tumble * _break * 0.9
	_body.rotation = Vector3(pitch + _lean.x + tumble.x, twist, _lean.z + tumble.z)
	_body.scale = Vector3.ONE * blink
	_heart.rotation.y += delta * 0.8 * spin
	_heart.scale = Vector3.ONE * (1.0 + 0.06 * sin(t * 3.0) + _power * 0.15 + heart)
	for i in _rings.size():
		var r := _rings[i]
		r.rotation.y += delta * (0.5 + i * 0.35) * spin * (1.0 if i % 2 == 0 else -1.0)
		r.rotation.x += delta * 0.2 * (i - 1) * spin
		if align > 0.0:
			# The rings line up like an instrument taking aim.
			r.rotation.x = lerp_angle(r.rotation.x, PI * 0.5, 1.0 - exp(-6.0 * align * delta))
			r.rotation.z = lerp_angle(r.rotation.z, 0.0, 1.0 - exp(-6.0 * align * delta))
	_orbit.rotation.y += delta * 0.6 * spin
	_orbit.scale = damp_v(_orbit.scale, Vector3.ONE * (1.0 + orbit + _break * 1.5), 6.0, delta)
	_orbit.position.y = damp(_orbit.position.y, 1.0 + orbit * 1.5 - _break * 0.8, 4.0, delta)
	pose(_head, Vector3(sin(t * 0.7) * 0.05 + head_up * 0.6 - 0.15 * _lean.x, sin(t * 0.4) * 0.15 - twist * 0.3, 0), 8.0, delta)
	_head.position.y = 4.55 + sin(t * 1.3 + 1.0) * 0.08 + head_up * 0.15 + _break * 0.4
	if _dead:
		# Death: the arms fall slack and drift apart as the construct sinks.
		r_arm = Vector3(-0.3 * _break, 0.6 * _break, 0.0)
		l_arm = r_arm
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var a := l_arm if i == 0 else r_arm
		var sway := sin(t * 0.9 + i * 1.7) * 0.06
		arm(_shoulders[i], _elbows[i], side, a.x + sway, a.y + sway, a.z, 10.0, delta)
		_fists[i].rotation.y += delta * 0.6 * spin
		_shoulders[i].position.x = side * (1.55 + _break * 0.8)
		_elbows[i].position.y = -1.85 - _break * 0.6
	if _dead:
		for r in _rings:
			r.position.y = damp(r.position.y, 2.6 - _break * 2.2, 2.0, delta)


func _on_boss_phase(new_phase: int) -> void:
	if new_phase >= 3 and _carapace != null:
		BossKit.emitter(_heart, "shard", 40, Vector3(1.2, 1.2, 1.2), GLOW, 0.14, 1.0, 1.4)
