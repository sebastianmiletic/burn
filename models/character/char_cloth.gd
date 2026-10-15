class_name CharCloth
extends RefCounted
## Verlet cloth for cloaks and capes: a small grid of particles in world space
## (so running drags it back and stopping lets it swing forward and settle),
## pinned along the top row to the chest, pushed out of capsules around the
## torso and legs, blown by the `wind_dir` / `wind_strength` globals.
## The grid drives one skeleton bone per particle; the cloak mesh is skinned
## bilinearly to them (see CharBody._cloak).

var cols := 5
var rows := 5
var p := PackedVector3Array()      # world positions
var prev := PackedVector3Array()
var rest := PackedVector3Array()   # skeleton-space rest positions (body units)
var _len_h := PackedFloat32Array()
var _len_v := PackedFloat32Array()
var _len_d := PackedFloat32Array()
var _rest_basis: Array[Basis] = []
var _scale := 1.0
var _time := randf() * 10.0
var _ready := false
var _local := PackedVector3Array()

## Capsules (world space): a, b, radius - filled by the model each step.
var cap_a := PackedVector3Array()
var cap_b := PackedVector3Array()
var cap_r := PackedFloat32Array()

static var _wind := Vector3(0.9, 0.0, 0.44) * 0.35
static var _wind_read_t := -10.0
static var _wind_explicit := false


func setup(rest_pos: PackedVector3Array, c: int, r: int, scale: float) -> void:
	cols = c
	rows = r
	rest = rest_pos
	_scale = scale
	p.resize(c * r)
	prev.resize(c * r)
	_len_h.resize(c * r)
	_len_v.resize(c * r)
	_len_d.resize(c * r)
	for i in r:
		for j in c:
			var k := i * c + j
			_len_h[k] = rest[k].distance_to(rest[k + 1]) * scale if j < c - 1 else 0.0
			_len_v[k] = rest[k].distance_to(rest[k + c]) * scale if i < r - 1 else 0.0
			_len_d[k] = rest[k].distance_to(rest[k + c + 1]) * scale if (i < r - 1 and j < c - 1) else 0.0
	_rest_basis.clear()
	for i in r:
		for j in c:
			_rest_basis.append(_frame(rest, i, j))


## Whoever writes the `wind_dir` / `wind_strength` shader globals can mirror them
## here (reading globals back from the RenderingServer is editor-only).
static func set_wind(dir: Vector2, strength: float) -> void:
	_wind = Vector3(dir.x, 0.0, dir.y).normalized() * strength
	_wind_explicit = true


## Shared wind vector: explicit set_wind(), else the weather's wind amount
## (duck-typed, refreshed twice a second) along the project's default wind_dir.
static func wind() -> Vector3:
	if _wind_explicit:
		return _wind
	var now := Time.get_ticks_msec() / 1000.0
	if now - _wind_read_t > 0.5:
		_wind_read_t = now
		var dir := Vector2(0.9, 0.44)
		var g: Variant = ProjectSettings.get_setting("shader_globals/wind_dir", null)
		if g is Dictionary and (g as Dictionary).get("value") is Vector2:
			dir = (g as Dictionary)["value"]
		var strength := 0.35
		var gw := GameWorld.instance
		if gw != null and is_instance_valid(gw):
			var weather: Variant = gw.get("weather")
			if weather is Object and is_instance_valid(weather):
				var wd: Variant = (weather as Object).get("wind_dir")
				if wd is Vector2:
					dir = wd
				var ws: Variant = (weather as Object).get("wind_strength")
				if ws is float:
					strength = ws
				elif (weather as Object).has_method("wind_amount"):
					strength = 0.3 + float((weather as Object).call("wind_amount")) * 0.7
		_wind = Vector3(dir.x, 0.0, dir.y).normalized() * strength
	return _wind


## Place every particle rigidly from the pin transform (world, includes scale).
func reset(pin_xf: Transform3D, chest_rest: Vector3) -> void:
	for k in p.size():
		var w := pin_xf * (rest[k] - chest_rest)
		p[k] = w
		prev[k] = w
	_ready = true


func is_ready() -> bool:
	return _ready


## pin_xf: world transform of the chest bone (skeleton global * chest pose).
## up: world up of the model. back: world "behind the body" direction.
func step(delta: float, pin_xf: Transform3D, chest_rest: Vector3, back: Vector3, iterations := 3) -> void:
	if not _ready:
		reset(pin_xf, chest_rest)
	delta = clampf(delta, 0.001, 0.05)
	_time += delta
	var w := wind()
	var g := Vector3(0, -9.8, 0) * delta * delta
	var n := p.size()
	# Integrate.
	for k in n:
		if k < cols:
			continue
		var cur := p[k]
		var vel := (cur - prev[k]) * 0.965
		var row := k / cols
		var flutter := 0.55 + 0.45 * sin(_time * 7.0 + k * 1.7) * sin(_time * 2.3 + row)
		var a := g + w * (2.6 * flutter * float(row) / (rows - 1)) * delta * delta
		prev[k] = cur
		p[k] = cur + vel + a
	# Pins follow the chest.
	for j in cols:
		var pin := pin_xf * (rest[j] - chest_rest)
		prev[j] = p[j]
		p[j] = pin
	if _ca.is_empty():
		_build_constraints()
	var nc := _ca.size()
	for it in iterations:
		for c in nc:
			var a := _ca[c]
			var b := _cb[c]
			var d := p[b] - p[a]
			var l := d.length()
			if l < 1e-6:
				continue
			var corr := d * ((l - _cl[c]) / l)
			if a < cols:
				p[b] -= corr
			else:
				corr *= 0.5
				p[a] += corr
				p[b] -= corr
	_collide(back)


var _ca := PackedInt32Array()
var _cb := PackedInt32Array()
var _cl := PackedFloat32Array()


func _build_constraints() -> void:
	# Structural (rows and columns) plus one shear diagonal; never pin-to-pin.
	for i in rows:
		for j in cols:
			var k := i * cols + j
			if i < rows - 1:
				_ca.append(k)
				_cb.append(k + cols)
				_cl.append(_len_v[k])
			if j < cols - 1 and i > 0:
				_ca.append(k)
				_cb.append(k + 1)
				_cl.append(_len_h[k])
			if i < rows - 1 and j < cols - 1 and (i + j) % 2 == 0:
				_ca.append(k)
				_cb.append(k + cols + 1)
				_cl.append(_len_d[k])


func _solve(a: int, b: int, length: float) -> void:
	var d := p[b] - p[a]
	var l := d.length()
	if l < 1e-6:
		return
	var diff := (l - length) / l
	var pin_a := a < cols
	var pin_b := b < cols
	if pin_a and pin_b:
		return
	if pin_a:
		p[b] -= d * diff
	elif pin_b:
		p[a] += d * diff
	else:
		p[a] += d * diff * 0.5
		p[b] -= d * diff * 0.5


func _collide(back: Vector3) -> void:
	for k in range(cols, p.size()):
		var x := p[k]
		for c in cap_a.size():
			var a := cap_a[c]
			var ab := cap_b[c] - a
			var t := clampf((x - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			var q := a + ab * t
			var d := x - q
			var l := d.length()
			var r := cap_r[c]
			if l < r:
				if l < 1e-5:
					d = back
					l = 1.0
				x = q + d / l * r
		p[k] = x


## Write bone poses (skeleton space) for bones [first, first + cols*rows).
func write(skel: Skeleton3D, first: int, to_skel: Transform3D) -> void:
	if _local.size() != p.size():
		_local.resize(p.size())
	for k in p.size():
		_local[k] = to_skel * p[k]
	for i in rows:
		for j in cols:
			var k := i * cols + j
			var b := _frame(_local, i, j) * _rest_basis[k].transposed()
			skel.set_bone_pose_position(first + k, _local[k])
			skel.set_bone_pose_rotation(first + k, b.get_rotation_quaternion())


## Rigid fallback for distant characters: everything follows the chest.
func write_rigid(skel: Skeleton3D, first: int, chest_skel: Transform3D, chest_rest: Vector3) -> void:
	var q := chest_skel.basis.get_rotation_quaternion()
	for k in rest.size():
		skel.set_bone_pose_position(first + k, chest_skel * (rest[k] - chest_rest))
		skel.set_bone_pose_rotation(first + k, q)
	_ready = false


func _frame(pts: PackedVector3Array, i: int, j: int) -> Basis:
	var k := i * cols + j
	var tu := pts[i * cols + mini(j + 1, cols - 1)] - pts[i * cols + maxi(j - 1, 0)]
	var tv := pts[mini(i + 1, rows - 1) * cols + j] - pts[maxi(i - 1, 0) * cols + j]
	var x := tu.normalized()
	var nrm := tu.cross(tv).normalized()
	if nrm.length_squared() < 0.5:
		return Basis.IDENTITY
	var y := nrm.cross(x).normalized()
	var _u := k
	return Basis(x, y, nrm)
