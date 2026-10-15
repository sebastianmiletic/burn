class_name Flock
extends Entity
## Ambient groups that make the world feel inhabited: birds pecking in
## meadows (crows in the marsh and wastes, gulls on the coast) that burst
## into the air when you come near and fly off, fish schools in lakes and
## the sea that scatter, and bat swarms looping under cave ceilings.
##
## One entity per group (the members are animated by FlockModel), never
## targeted by anything. `anim` 1 = startled; birds then rise and leave and
## the flock despawns.

const ALARM := {"bird_flock": 9.0, "crow_flock": 11.0, "gull_flock": 10.0, "fish_school": 5.0, "bat_swarm": 7.0}

var model: FlockModel
var _startled_t := 0.0
var _check_t := 0.0
var _flee := Vector3.FORWARD
var _gone := false
var sim_world: Object = null


static func create(flock_kind: String) -> Flock:
	var f := Flock.new()
	f.kind = flock_kind
	return f


func _w() -> Variant:
	return sim_world if sim_world != null else world()


func _ready() -> void:
	team = Team.NEUTRAL
	display_name = kind.capitalize()
	hit_radius = 0.0
	hit_height = 0.0
	max_health = 1.0
	health = 1.0
	body.collides = false
	body.fly = true
	model = Models.create_mob(kind, net_id) as FlockModel
	add_child(model)


func take_damage(_amount: float, _source_id := 0, _damage_kind := "hit") -> float:
	return 0.0


func is_bird() -> bool:
	return kind in ["bird_flock", "crow_flock", "gull_flock"]


func server_tick(delta: float) -> void:
	if _gone:
		return
	if anim == 1:
		_startled_t += delta
		if is_bird():
			# The flock leaves: drift away and up, then vanish.
			global_position += (_flee * 5.0 + Vector3(0, 1.5, 0)) * delta
			if _startled_t > 14.0:
				_gone = true
				var w = _w()
				if w != null:
					w.despawn_entity(self)
		elif _startled_t > 5.0:
			anim = 0
			_startled_t = 0.0
		_sync()
		return
	_check_t -= delta
	if _check_t > 0.0:
		_sync()
		return
	_check_t = 0.3
	var w = _w()
	if w == null:
		return
	var p: Entity = w.nearest_player(global_position, dimension, float(ALARM.get(kind, 8.0)))
	if p != null:
		anim = 1
		anim_time = Time.get_ticks_msec() / 1000.0
		_flee = global_position - p.global_position
		_flee.y = 0.0
		_flee = _flee.normalized() if _flee.length() > 0.1 else Vector3.FORWARD
		yaw = atan2(-_flee.x, -_flee.z)
		rotation.y = yaw
		if is_bird():
			Audio.play("wing_flap", global_position, -2.0, 1.8)
		elif kind == "fish_school":
			Audio.play("splash_small", global_position, -8.0)
	_sync()


func _sync() -> void:
	if model != null:
		model.startled = anim == 1
		model.flee_dir = Vector3.FORWARD  # model space: the entity faces away from the threat


func _process(_delta: float) -> void:
	if model == null or is_server():
		return
	interpolate(Time.get_ticks_msec() / 1000.0)
	_sync()
