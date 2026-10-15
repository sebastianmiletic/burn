class_name FlockModel
extends CreatureModel
## A group of small animals drawn with MultiMeshes and animated locally:
## birds (sparrows / crows / gulls) that peck on the ground and burst into
## the air when startled, fish schools that mill in the water and scatter,
## and bat swarms that loop under cave ceilings.
##
## `startled` (from the entity) switches between calm and flight. Members
## move in the model's local space; the entity's position is the group's
## centre (birds' perch ground, fish's mid-depth).

var species := "bird_flock"
var count := 10
var startled := false
var flee_dir := Vector3.FORWARD

var _members: Array = []  # [pos, vel, phase, perch(Vector3), size]
var _bodies: MultiMeshInstance3D
var _wing_l: MultiMeshInstance3D
var _wing_r: MultiMeshInstance3D
## Hand panels of the wings (hinged at `_wing_span` along the arm panel) and beaks / feet.
var _wing_l2: MultiMeshInstance3D
var _wing_r2: MultiMeshInstance3D
var _beaks: MultiMeshInstance3D
var _wing_span := 0.1
var _rng := RandomNumberGenerator.new()
var _startle_t := 0.0


func _init(kind_name := "bird_flock", variant_seed := 0) -> void:
	species = kind_name
	_rng.seed = variant_seed
	match species:
		"fish_school":
			count = _rng.randi_range(9, 16)
		"bat_swarm":
			count = _rng.randi_range(8, 14)
		"gull_flock":
			count = _rng.randi_range(5, 8)
		_:
			count = _rng.randi_range(6, 11)
	dissolve_delay = 0.2


func _lod_size() -> float:
	return 2.0


func _build() -> void:
	var body_mesh: Mesh
	var wing_mesh: Mesh
	var body_mat: Material
	var wing_mat: Material
	var wing2_mesh: Mesh
	var wing2_mat: Material
	var beak_mesh: Mesh
	var beak_mat: Material
	var wing_span := 0.1
	var size := 1.0
	match species:
		"fish_school":
			size = 0.5
			# A laterally flattened, fusiform fish with a forked tail, dorsal and
			# pectoral fins and a gill cover, merged into one mesh.
			var fish_body := OrganicMesh.profile("flock_fish_body", Vector3(0, 0, 0.17), Vector3(0, -0.004, -0.2), [[0.0, 0.007, 0.016], [0.15, 0.013, 0.03],
				[0.42, 0.029, 0.068, 0.004], [0.62, 0.031, 0.066, 0.002], [0.8, 0.025, 0.05], [0.92, 0.016, 0.03, -0.004], [1.0, 0.004, 0.006, -0.006]], 10, 14)
			var tail_fin := OrganicMesh.membrane("flock_fish_tail", PackedVector2Array([Vector2(0.015, 0.012), Vector2(-0.06, 0.06), Vector2(-0.115, 0.095),
				Vector2(-0.085, 0.02), Vector2(-0.075, 0.0), Vector2(-0.085, -0.02), Vector2(-0.115, -0.095), Vector2(-0.06, -0.06), Vector2(0.015, -0.012)]), 0.0, 0.004)
			var dorsal_fin := OrganicMesh.membrane("flock_fish_dorsal", PackedVector2Array([Vector2(0.04, 0.0), Vector2(0.01, 0.045), Vector2(-0.03, 0.04), Vector2(-0.07, 0.012), Vector2(-0.07, 0.0)]), 0.0, 0.004)
			var anal_fin := OrganicMesh.membrane("flock_fish_anal", PackedVector2Array([Vector2(0.02, 0.0), Vector2(-0.04, -0.025), Vector2(-0.05, 0.0)]), 0.0, 0.003)
			var pec_fin := OrganicMesh.membrane("flock_fish_pec", PackedVector2Array([Vector2(0.0, 0.008), Vector2(0.045, -0.006), Vector2(0.035, -0.016), Vector2(0.0, -0.006)]), 0.0, 0.003)
			var gill := OrganicMesh.bezier("flock_fish_gill", Vector3(0, 0.045, 0), Vector3(0, 0.0, 0.012), Vector3(0, -0.045, 0.0), 0.004, 0.003, 5, 4)
			var eye := OrganicMesh.blob("flock_fish_eye", Vector3(0.006, 0.012, 0.012), 0.02, 3, 8)
			var turn := Basis(Vector3.UP, PI * 0.5)
			var fish_parts: Array = [[fish_body, Transform3D()], [tail_fin, Transform3D(turn, Vector3(0, 0, 0.165))],
				[dorsal_fin, Transform3D(turn, Vector3(0, 0.06, -0.02))], [anal_fin, Transform3D(turn, Vector3(0, -0.05, 0.07))]]
			for side: float in [-1.0, 1.0]:
				fish_parts.append([pec_fin, Transform3D(Basis.from_euler(Vector3(0.0, side * -0.5, 0.0)).scaled(Vector3(side, 1, 1)), Vector3(side * 0.024, -0.02, -0.08))])
				fish_parts.append([gill, Transform3D(Basis(), Vector3(side * 0.027, 0.0, -0.105))])
				fish_parts.append([eye, Transform3D(Basis(), Vector3(side * 0.02, 0.012, -0.15))])
			body_mesh = OrganicMesh.merge("flock_fish2", fish_parts)
			body_mat = CreatureSkin.smooth(Color(0.2, 0.27, 0.3), Color(0.88, 0.9, 0.88), {"belly_mix": 1.0, "specular_amount": 0.95,
				"pattern": CreatureSkin.Pattern.HIDE, "pattern_scale": 60.0, "roughness": 0.15, "wet": 0.6, "rim": 0.5, "bump": 0.15, "accent": Color(0.08, 0.1, 0.12), "accent_mode": 3, "accent_amount": 0.5,
				"accent_scale": 30.0, "ascii_id": AsciiMaterialId.LIQUID})
		"bat_swarm":
			# Furry body with big ears; wings in two panels (arm and fingered hand).
			body_mesh = OrganicMesh.merge("flock_bat_body2", [
				[OrganicMesh.profile("flock_bat_torso", Vector3(0, -0.005, 0.075), Vector3(0, 0.005, -0.06), [[0.0, 0.012, 0.012], [0.3, 0.032, 0.03], [0.7, 0.03, 0.028], [1.0, 0.02, 0.02]], 8, 8), Transform3D()],
				[OrganicMesh.blob("flock_bat_head", Vector3(0.022, 0.02, 0.024), 0.05, 3, 8), Transform3D(Basis(), Vector3(0, 0.008, -0.07))],
				[OrganicMesh.membrane("flock_bat_ear", PackedVector2Array([Vector2(-0.008, 0), Vector2(0.008, 0), Vector2(0.002, 0.032)]), 0.003, 0.003), Transform3D(Basis.from_euler(Vector3(0.0, 0.3, 0.35)), Vector3(-0.012, 0.022, -0.068))],
				[OrganicMesh.membrane("flock_bat_ear", PackedVector2Array([Vector2(-0.008, 0), Vector2(0.008, 0), Vector2(0.002, 0.032)]), 0.003, 0.003), Transform3D(Basis.from_euler(Vector3(0.0, -0.3, -0.35)), Vector3(0.012, 0.022, -0.068))]])
			wing_mesh = OrganicMesh.membrane("flock_bat_wing_in2", PackedVector2Array([Vector2(0, 0.02), Vector2(0.105, 0.03), Vector2(0.105, 0.0), Vector2(0.08, -0.045),
				Vector2(0.045, -0.05), Vector2(0.02, -0.07), Vector2(0, -0.075)]), 0.004, 0.004)
			wing2_mesh = OrganicMesh.membrane("flock_bat_wing_out2", PackedVector2Array([Vector2(0, 0.03), Vector2(0.17, 0.0), Vector2(0.12, -0.012), Vector2(0.13, -0.045),
				Vector2(0.07, -0.035), Vector2(0.06, -0.07), Vector2(0.02, -0.045), Vector2(0, -0.045)]), 0.004, 0.004)
			wing_span = 0.105
			body_mat = CreatureSkin.fur(Color(0.17, 0.13, 0.11), Color(0.25, 0.2, 0.17), {"pattern_scale": 60.0, "rim": 0.5})
			wing_mat = CreatureSkin.membrane(Color(0.17, 0.1, 0.09), {"backlight": 1.4, "pattern_scale": 14.0, "bump": 0.1})
		_:
			var dark := species == "crow_flock"
			var gull := species == "gull_flock"
			size = 1.6 if gull else (1.2 if dark else 0.8)
			# Plump body, round head, a fanned tail; beaks and feet are a
			# separate keratin mesh. Wings in two panels: the broad arm and the
			# hand with its fingered primaries.
			var tail := OrganicMesh.membrane("flock_bird_tail", PackedVector2Array([Vector2(-0.018, 0.0), Vector2(0.018, 0.0), Vector2(0.03, -0.07), Vector2(0.012, -0.062),
				Vector2(0.0, -0.072), Vector2(-0.012, -0.062), Vector2(-0.03, -0.07)]), 0.0, 0.004)
			body_mesh = OrganicMesh.merge("flock_bird_body2", [
				[OrganicMesh.profile("flock_bird_torso", Vector3(0, 0.0, 0.085), Vector3(0, 0.022, -0.075), [[0.0, 0.016, 0.01], [0.25, 0.04, 0.042], [0.6, 0.042, 0.046, -0.004], [0.85, 0.03, 0.033], [1.0, 0.018, 0.02]], 10, 10), Transform3D()],
				[OrganicMesh.blob("flock_bird_head", Vector3(0.026, 0.026, 0.03), 0.04, 3, 10), Transform3D(Basis(), Vector3(0, 0.035, -0.085))],
				[tail, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.RIGHT, PI), Vector3(0, 0.006, 0.075))]])
			beak_mesh = OrganicMesh.merge("flock_bird_beak", [
				[OrganicMesh.bezier("flock_bird_bill", Vector3.ZERO, Vector3(0, -0.002, -0.018), Vector3(0, -0.008, -0.032 if not gull else -0.042), 0.008, 0.001, 4, 6), Transform3D(Basis(), Vector3(0, 0.03, -0.108))],
				[OrganicMesh.bezier("flock_bird_leg", Vector3.ZERO, Vector3(0, -0.02, 0.0), Vector3(0, -0.04, -0.01), 0.004, 0.003, 3, 4), Transform3D(Basis(), Vector3(-0.012, -0.02, 0.0))],
				[OrganicMesh.bezier("flock_bird_leg", Vector3.ZERO, Vector3(0, -0.02, 0.0), Vector3(0, -0.04, -0.01), 0.004, 0.003, 3, 4), Transform3D(Basis(), Vector3(0.012, -0.02, 0.0))]])
			wing_mesh = OrganicMesh.membrane("flock_bird_wing_in", PackedVector2Array([Vector2(0, 0.032), Vector2(0.1, 0.03), Vector2(0.105, -0.04), Vector2(0.07, -0.052),
				Vector2(0.035, -0.056), Vector2(0, -0.045)]), 0.008, 0.005)
			wing2_mesh = OrganicMesh.membrane("flock_bird_wing_out", PackedVector2Array([Vector2(0, 0.03), Vector2(0.06, 0.022), Vector2(0.12, 0.0), Vector2(0.135, -0.012),
				Vector2(0.11, -0.016), Vector2(0.125, -0.03), Vector2(0.095, -0.032), Vector2(0.105, -0.045), Vector2(0.075, -0.045), Vector2(0.07, -0.055),
				Vector2(0.04, -0.05), Vector2(0, -0.04)]), 0.006, 0.004)
			wing_span = 0.1
			var c := Color(0.1, 0.095, 0.1) if dark else (Color(0.88, 0.89, 0.88) if gull else Color(0.45, 0.35, 0.25))
			body_mat = CreatureSkin.feathers(c, c.lightened(0.3) if not dark else c.lightened(0.08), {"pattern_scale": 90.0, "rim": 0.5, "bump": 0.3,
				"specular_amount": 0.45 if dark else 0.2, "roughness": 0.55 if dark else 0.8})
			wing_mat = CreatureSkin.feathers(c.darkened(0.2) if not gull else Color(0.55, 0.57, 0.6), c, {"pattern_scale": 110.0, "rim": 0.4, "bump": 0.3})
			wing2_mat = CreatureSkin.feathers(c.darkened(0.35) if not gull else Color(0.1, 0.1, 0.11), c, {"pattern_scale": 110.0, "rim": 0.4, "bump": 0.3})
			beak_mat = CreatureSkin.keratin(Color(0.9, 0.7, 0.2) if gull else Color(0.08, 0.07, 0.06), {"roughness": 0.4})
	_wing_span = wing_span
	_bodies = _multi(body_mesh, body_mat)
	if beak_mesh != null:
		_beaks = _multi(beak_mesh, beak_mat)
	if wing_mesh != null:
		_wing_l = _multi(wing_mesh, wing_mat)
		_wing_r = _multi(wing_mesh, wing_mat)
	if wing2_mesh != null:
		_wing_l2 = _multi(wing2_mesh, wing2_mat if wing2_mat != null else wing_mat)
		_wing_r2 = _multi(wing2_mesh, wing2_mat if wing2_mat != null else wing_mat)
	for i in count:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(0.5, 3.5)
		var perch := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var pos := perch
		if species == "fish_school" or species == "bat_swarm":
			pos = Vector3(cos(a) * r, _rng.randf_range(-0.8, 0.8), sin(a) * r)
		_members.append([pos, Vector3.ZERO, _rng.randf() * TAU, perch, size * _rng.randf_range(0.85, 1.15)])


func _multi(mesh: Mesh, mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 60, 80))
	add_child(mi)
	return mi


func _animate(delta: float) -> void:
	if _bodies == null:
		return
	delta = minf(delta, 0.1)
	_startle_t = _startle_t + delta if startled else 0.0
	var fish := species == "fish_school"
	var bats := species == "bat_swarm"
	for i in count:
		var m: Array = _members[i]
		var pos: Vector3 = m[0]
		var vel: Vector3 = m[1]
		var ph: float = m[2]
		var perch: Vector3 = m[3]
		var sz: float = m[4]
		var flying := false
		var flap := 0.0
		if fish or bats:
			# Orbit the centre with a little wander; scatter faster when startled.
			var speed := (1.2 if fish else 3.0) * (2.2 if startled else 1.0)
			var orbit_r := (2.5 if fish else 3.5) + sin(_time * 0.3 + i) * 1.0 + (2.0 if startled else 0.0)
			var a := atan2(pos.z, pos.x) + speed / orbit_r * delta * (1.0 if i % 3 else -1.0)
			var target := Vector3(cos(a) * orbit_r, sin(_time * (0.7 if fish else 1.6) + i * 1.3) * (0.6 if fish else 1.4), sin(a) * orbit_r)
			vel = vel.lerp((target - pos) * 2.0, 1.0 - exp(-3.0 * delta))
			flying = true
			flap = sin(_time * 18.0 + ph)
		else:
			if startled:
				# Burst up and away, then circle high above while the flock leaves.
				var t := _startle_t + float(i) * 0.04
				var away := flee_dir.normalized() if flee_dir.length() > 0.1 else Vector3.FORWARD
				var target := Vector3(cos(_time * 0.6 + ph) * 6.0, 10.0 + sin(ph) * 2.0, sin(_time * 0.6 + ph) * 6.0) + away * minf(t * 4.0, 30.0)
				var accel := (target - pos) * (3.0 if t < 1.0 else 1.2)
				vel = vel.lerp(accel.limit_length(9.0), 1.0 - exp(-4.0 * delta))
				flying = true
				flap = sin(_time * (22.0 if t < 1.0 else 12.0) + ph)
			else:
				# Peck about on the ground, hop to new spots now and then.
				var hop := fposmod(_time * 0.35 + ph, 3.0) < 0.12
				if hop:
					perch += Vector3(cos(ph * 7.0 + _time), 0, sin(ph * 5.0 + _time)) * 0.03
					perch = perch.limit_length(4.0)
					m[3] = perch
				vel = (perch - pos) * 4.0
				pos.y = maxf(0.0, pos.y)
				if pos.y > 0.3:
					flying = true
					flap = sin(_time * 18.0 + ph)
		pos += vel * delta
		if not fish and not bats and not startled:
			pos.y = lerpf(pos.y, 0.0, 1.0 - exp(-5.0 * delta))
		m[0] = pos
		m[1] = vel
		var dir := vel
		dir.y *= 0.5
		var basis := Basis()
		if dir.length() > 0.05:
			basis = Basis.looking_at(dir.normalized(), Vector3.UP)
		else:
			basis = Basis(Vector3.UP, ph)
		if not flying and not fish:
			var peck := maxf(0.0, sin(_time * 5.0 + ph * 3.0)) * 0.7
			basis = basis * Basis(Vector3.RIGHT, -peck)
		if fish:
			basis = basis * Basis(Vector3.UP, sin(_time * 9.0 + ph) * 0.25)
		var xf := Transform3D(basis.scaled(Vector3.ONE * sz), pos + Vector3(0, 0.05 * sz if not fish else 0.0, 0))
		_bodies.multimesh.set_instance_transform(i, xf)
		if _beaks != null:
			_beaks.multimesh.set_instance_transform(i, xf)
		if _wing_l != null:
			var flat := Basis(Vector3.RIGHT, -PI * 0.5)
			var mirror := Basis.from_scale(Vector3(-1, 1, 1))
			var rb: Basis
			var lb: Basis
			# The hand lags the arm through the beat (it trails on the upstroke,
			# flicks through on the downstroke); folded, it lies back over the arm.
			var hand := Basis()
			if flying:
				var lag := sin(_time * (18.0 if bats else 14.0) + ph - 0.9)
				rb = Basis(Vector3.BACK, flap * 0.8) * flat
				lb = Basis(Vector3.BACK, -flap * 0.8) * flat * mirror
				hand = Basis(Vector3.UP, -lag * 0.55) * Basis(Vector3.BACK, -maxf(0.0, -lag) * 0.35)
			else:
				# Folded back along the body.
				rb = Basis(Vector3.UP, -1.45) * Basis(Vector3.BACK, 0.25) * flat
				lb = Basis(Vector3.UP, 1.45) * Basis(Vector3.BACK, -0.25) * flat * mirror
				hand = Basis(Vector3.BACK, -2.75) * Basis(Vector3.UP, 0.15)
			var rx := xf * Transform3D(rb, Vector3(0.03, 0.025, -0.02))
			var lx := xf * Transform3D(lb, Vector3(-0.03, 0.025, -0.02))
			_wing_r.multimesh.set_instance_transform(i, rx)
			_wing_l.multimesh.set_instance_transform(i, lx)
			if _wing_r2 != null:
				var hx := Transform3D(hand, Vector3(_wing_span, 0, 0))
				_wing_r2.multimesh.set_instance_transform(i, rx * hx)
				_wing_l2.multimesh.set_instance_transform(i, lx * hx)
