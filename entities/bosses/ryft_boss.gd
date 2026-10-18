extends Boss
## Shared movement for the floating Ryft bosses (Prism Sentinel, Void
## Sovereign). They never walk: `flying` is set (and replicates) while they
## hold their altitude above the arena floor, drift on an orbit around their
## target, now and then glide to a new vantage point, and rise or swoop for
## particular attacks. Every position goal is clamped to the arena's air
## volume (Boss._clamp_air / air_ceiling). Telegraphs are placed on the floor
## (`_gp`), never at the floating body's height.
##
## Attack selection favours moves not yet used in the current phase, so the
## whole moveset shows up in every fight.

## Hover altitude (above the floor reference) while drifting.
var base_alt := 0.8
## Preferred distance from the target while drifting between attacks.
var orbit_range := 8.0
## Current altitude goal (attacks raise or lower it).
var _alt := 0.8
var _ref_y := INF
var _orbit_dir := 1.0
var _orbit_t := 0.0
var _vantage := Vector3.INF
var _vantage_t := 6.0
var _used := {}
var _last_pick := ""


func _ready() -> void:
	super._ready()
	air_ceiling = 14.0
	_alt = base_alt
	_take_off()


func _take_off() -> void:
	flying = true
	body.fly = true


## Floor height the boss hovers over and telegraphs are placed on.
func _floor_y() -> float:
	return _ref_y if is_finite(_ref_y) else spawn_point.y


## `p` on the arena floor (for telegraphs).
func _gp(p: Vector3) -> Vector3:
	return Vector3(p.x, _floor_y(), p.z)


func _ground_here() -> Vector3:
	return _gp(global_position)


func _track_floor(delta: float) -> void:
	var want := spawn_point.y
	if _target != null:
		want = clampf(_target.global_position.y, spawn_point.y - 6.0, spawn_point.y + 8.0)
	_ref_y = want if not is_finite(_ref_y) else lerpf(_ref_y, want, 1.0 - exp(-1.5 * delta))


## Holds the altitude goal (smoothly) inside the air volume.
func _hover(delta: float, rate := 3.0) -> void:
	_track_floor(delta)
	var goal_y := clampf(_floor_y() + _alt, spawn_point.y - 6.0, spawn_point.y + air_ceiling)
	var vy := clampf((goal_y - global_position.y) * rate, -14.0, 14.0)
	body.velocity.y = lerpf(body.velocity.y, vy, 1.0 - exp(-6.0 * delta))


## Horizontal glide towards `p` (clamped inside the arena), facing `look`.
func _glide(p: Vector3, speed: float, delta: float, look := Vector3.INF, accel := 3.0) -> bool:
	var goal := _clamp_arena(p, 0.92)
	var to := goal - global_position
	to.y = 0.0
	var arrived := to.length() < 1.0
	var desired := Vector3.ZERO if arrived else to.normalized() * minf(speed, to.length() * 2.0)
	body.velocity.x = lerpf(body.velocity.x, desired.x, 1.0 - exp(-accel * delta))
	body.velocity.z = lerpf(body.velocity.z, desired.z, 1.0 - exp(-accel * delta))
	if look.is_finite():
		_face(look, delta, 2.6)
	elif to.length() > 0.5:
		_face(goal, delta, 2.6)
	return arrived


func _idle(delta: float) -> void:
	_take_off()
	_alt = base_alt
	_glide(spawn_point, walk_speed * 0.6, delta)
	_hover(delta)


## Between attacks: orbit the target at `orbit_range`, changing direction now
## and then, and every few seconds glide to a fresh vantage point.
func _approach(delta: float) -> void:
	_take_off()
	_alt = move_toward(_alt, base_alt, delta * 2.0)
	if _target == null:
		_glide(spawn_point, walk_speed, delta)
		_hover(delta)
		return
	var tp := _target.global_position
	_vantage_t -= delta
	if _vantage.is_finite():
		if _glide(_vantage, walk_speed * 1.8, delta, tp) or _vantage_t < -4.0:
			_vantage = Vector3.INF
			_vantage_t = 5.0 + _rng.randf() * 4.0
		_hover(delta)
		return
	if _vantage_t <= 0.0:
		var a := _rng.randf() * TAU
		_vantage = _clamp_arena(tp + Vector3(cos(a), 0, sin(a)) * orbit_range * 1.2, 0.85)
		_hover(delta)
		return
	_orbit_t -= delta
	if _orbit_t <= 0.0:
		_orbit_t = 2.0 + _rng.randf() * 3.0
		_orbit_dir = -1.0 if _rng.randf() < 0.5 else 1.0
	var off := global_position - tp
	off.y = 0.0
	if off.length() < 0.1:
		off = -_fwd()
	var d := off.length()
	var ang := atan2(off.z, off.x) + _orbit_dir * delta * walk_speed * 0.7 / maxf(d, 3.0)
	var r := lerpf(d, orbit_range, 1.0 - exp(-0.8 * delta))
	if d > orbit_range * 1.8:
		r = orbit_range
	var goal := tp + Vector3(cos(ang), 0, sin(ang)) * r
	var out := goal - spawn_point
	out.y = 0.0
	if out.length() > arena_radius * 0.88:
		_orbit_dir = -_orbit_dir
	_glide(goal, walk_speed * (1.5 if d > orbit_range * 1.8 else 1.0), delta, tp)
	_hover(delta)


## Attack weights: moves not yet used in this phase are favoured, an
## immediate repeat is discouraged.
func _wt(name: String, base: float) -> float:
	var w := base
	if int(_used.get("%d:%s" % [phase, name], 0)) == 0:
		w *= 4.0
	if name == _last_pick:
		w *= 0.3
	return w


func _note_attack(name: String) -> void:
	var k := "%d:%s" % [phase, name]
	_used[k] = int(_used.get(k, 0)) + 1
	_last_pick = name


func _dir_to(e: Entity) -> Vector3:
	if e == null:
		return _fwd()
	var d := e.global_position - global_position
	d.y = 0.0
	return d.normalized() if d.length() > 0.1 else _fwd()


## Folds space: vanishes and reappears at `dest` (clamped to the arena).
func _blink_to(dest: Vector3) -> void:
	_fx_burst(center(), false, 1.2)
	var q := _clamp_arena(dest, 0.85)
	q.y = _floor_y() + _alt
	global_position = q
	body.velocity = Vector3.ZERO
	_fx_burst(center(), false, 1.4)
	Audio.play("portal", center(), 2.0, 0.7)


func _reset() -> void:
	super._reset()
	_alt = base_alt
	_vantage = Vector3.INF
	_used.clear()
	_take_off()
