class_name Wildlife
extends Entity
## Passive animals: deer and stags, rabbits, mountain goats, boars. They
## graze and wander, bolt from players who come close (rabbits zig-zag), and
## can be hunted for meat and hides. Boars turn and charge whoever hurts them.
##
## Cheap by design: decisions a few times a second, physics every frame only
## while moving. Replicated with the base snapshot; `anim` is the mood
## (0 calm, 1 grazing, 2 fleeing, 3 charging) so clients pose the model.

const STATS := {
	"deer": {"name": "Deer", "health": 35.0, "speed": 1.4, "run": 8.5, "alarm": 15.0, "radius": 0.45, "height": 1.4, "xp": 6,
		"loot": [["raw_meat", 1.0, 1, 2], ["leather", 0.7, 1, 2], ["bone", 0.3, 1, 1]]},
	"stag": {"name": "Stag", "health": 50.0, "speed": 1.4, "run": 8.0, "alarm": 16.0, "radius": 0.55, "height": 1.7, "xp": 9,
		"loot": [["raw_meat", 1.0, 2, 3], ["leather", 0.8, 1, 2], ["antler", 0.6, 1, 2]]},
	"rabbit": {"name": "Rabbit", "health": 6.0, "speed": 1.0, "run": 6.5, "alarm": 8.0, "radius": 0.25, "height": 0.35, "xp": 1,
		"loot": [["raw_meat", 0.8, 1, 1], ["rabbit_hide", 0.5, 1, 1]]},
	"goat": {"name": "Mountain Goat", "health": 30.0, "speed": 1.2, "run": 6.5, "alarm": 11.0, "radius": 0.4, "height": 1.0, "xp": 5,
		"loot": [["raw_meat", 1.0, 1, 2], ["wool", 0.6, 1, 2], ["leather", 0.4, 1, 1]]},
	"boar": {"name": "Wild Boar", "health": 60.0, "speed": 1.3, "run": 6.0, "alarm": 7.0, "radius": 0.5, "height": 0.9, "xp": 12,
		"damage": 12.0, "loot": [["raw_meat", 1.0, 2, 3], ["leather", 0.6, 1, 2], ["tusk", 0.4, 1, 1]]},
}

const CALM := 0
const GRAZE := 1
const FLEE := 2
const CHARGE := 3

var stats := {}
var model: CreatureModel
var loot: Array = []
var xp_value := 3
var spawn_point := Vector3.ZERO

var _rng := RandomNumberGenerator.new()
var _think_t := 0.0
var _mood_t := 0.0
var _goal := Vector3.ZERO
var _threat: Entity
var _hit_cd := 0.0
var _dead_t := 0.0
var _gone := false
var _last_pos := Vector3.ZERO
var _vis_speed := 0.0
var _last_health := -1.0
var sim_world: Object = null


static func create(animal_kind: String) -> Wildlife:
	var e := Wildlife.new()
	e.kind = animal_kind
	return e


func _w() -> Variant:
	return sim_world if sim_world != null else world()


func _ready() -> void:
	stats = STATS.get(kind, STATS["deer"])
	display_name = stats["name"]
	max_health = stats["health"]
	health = max_health
	team = Team.MONSTERS  # huntable: player attacks and spells only hit the monster team
	hit_radius = stats["radius"]
	hit_height = stats["height"]
	xp_value = stats["xp"]
	loot = stats["loot"]
	body.half_extents = Vector3(minf(0.4, hit_radius), hit_height * 0.5, minf(0.4, hit_radius))
	if spawn_point == Vector3.ZERO:
		spawn_point = global_position
	_rng.seed = hash(str(net_id) + kind)
	model = Models.create_mob(kind, net_id)
	add_child(model)
	_goal = global_position
	_last_pos = global_position
	_last_health = health
	_mood_t = _rng.randf_range(1.0, 4.0)


func take_damage(amount: float, source_id := 0, damage_kind := "hit") -> float:
	var dealt := super.take_damage(amount, source_id, damage_kind)
	if dealt > 0.0:
		Events.damage_number.emit(center() + Vector3(0, hit_height * 0.4, 0), int(round(dealt)), damage_kind == "crit", "hit")
		if model != null:
			model.flash()
		var w = _w()
		if w != null and source_id != 0:
			for p in w.players_in(dimension):
				if p.net_id == source_id:
					_threat = p
		if kind == "boar" and _threat != null and not dead:
			anim = CHARGE
			_mood_t = 6.0
		elif not dead:
			anim = FLEE
			_mood_t = 5.0
		Audio.play("hurt" if kind != "boar" else "growl", center(), -6.0, 1.6 if kind == "rabbit" else 1.0)
	return dealt


func _on_died() -> void:
	body.velocity = Vector3.ZERO
	if model != null:
		model.set_dead(true)


func server_tick(delta: float) -> void:
	if dead:
		_dead_t += delta
		if _dead_t > 3.5 and not _gone:
			_gone = true
			var w = _w()
			if w != null:
				w.despawn_entity(self)
		return
	_hit_cd -= delta
	_mood_t -= delta
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = 0.25 + _rng.randf() * 0.1
		_think()
	_move(delta)
	if model != null:
		model.move_speed = Vector2(body.velocity.x, body.velocity.z).length()
		model.set("grazing", anim == GRAZE)


func _think() -> void:
	var w = _w()
	if w == null:
		return
	if anim == CHARGE:
		if _threat == null or _threat.dead or _mood_t <= 0.0:
			anim = CALM
			_mood_t = 2.0
		else:
			_goal = _threat.global_position
		return
	var p: Entity = w.nearest_player(global_position, dimension, float(stats["alarm"]))
	if p != null and not p.dead:
		if kind == "boar" and anim != FLEE:
			# Boars stand their ground and snort; they only charge when hurt.
			_face_to(p.global_position)
			anim = CALM
			return
		_threat = p
		if anim != FLEE:
			anim = FLEE
			Audio.play("rustle", center(), -8.0)
		_mood_t = 3.0 + _rng.randf() * 2.0
	if anim == FLEE:
		if _threat != null and is_instance_valid(_threat):
			var away := global_position - _threat.global_position
			away.y = 0.0
			if away.length() < 0.1:
				away = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
			away = away.normalized()
			if kind == "rabbit":
				away = away.rotated(Vector3.UP, _rng.randf_range(-0.8, 0.8))
			_goal = global_position + away * 12.0
		if _mood_t <= 0.0:
			anim = CALM
			_mood_t = 2.0
		return
	if _mood_t <= 0.0:
		# Alternate grazing and ambling about the home spot.
		if anim == GRAZE or _rng.randf() < 0.4:
			anim = CALM
			var a := _rng.randf() * TAU
			_goal = spawn_point + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(2.0, 10.0)
			_mood_t = _rng.randf_range(4.0, 8.0)
		else:
			anim = GRAZE
			_goal = global_position
			_mood_t = _rng.randf_range(4.0, 10.0)


func _move(delta: float) -> void:
	var speed := 0.0
	match anim:
		CALM:
			speed = float(stats["speed"])
		FLEE:
			speed = float(stats["run"])
		CHARGE:
			speed = float(stats["run"]) * 1.1
	var to := _goal - global_position
	to.y = 0.0
	var desired := Vector3.ZERO
	if to.length() > 0.6 and speed > 0.0:
		desired = to.normalized() * speed
		_face_to(_goal, delta)
	body.velocity.x = lerpf(body.velocity.x, desired.x, 1.0 - exp(-6.0 * delta))
	body.velocity.z = lerpf(body.velocity.z, desired.z, 1.0 - exp(-6.0 * delta))
	if body.hit_wall and body.on_floor and desired.length() > 0.1:
		body.velocity.y = 7.5
	if kind == "rabbit" and anim == FLEE and body.on_floor:
		body.velocity.y = 3.2  # hop
	body.step(self, voxels(), delta)
	rotation.y = yaw
	if anim == CHARGE and _threat != null and _hit_cd <= 0.0:
		var d := Vector2(_threat.global_position.x - global_position.x, _threat.global_position.z - global_position.z).length()
		if d < 1.6:
			_hit_cd = 1.4
			var w = _w()
			if w != null:
				w.damage(_threat, float(stats.get("damage", 8.0)), net_id, "hit")
				Audio.play("hit", _threat.center(), -2.0)
			anim = FLEE
			_mood_t = 2.5


func _face_to(target: Vector3, delta := 1.0) -> void:
	var d := target - global_position
	if Vector2(d.x, d.z).length() < 0.05:
		return
	yaw = lerp_angle(yaw, atan2(-d.x, -d.z), 1.0 - exp(-8.0 * delta))


func _process(delta: float) -> void:
	if model == null or is_server():
		return
	interpolate(Time.get_ticks_msec() / 1000.0)
	var moved := (global_position - _last_pos) / maxf(delta, 0.0001)
	_vis_speed = lerpf(_vis_speed, Vector2(moved.x, moved.z).length(), 1.0 - exp(-10.0 * delta))
	_last_pos = global_position
	model.move_speed = _vis_speed
	model.set("grazing", anim == GRAZE)
	if _last_health >= 0.0 and health < _last_health - 0.01:
		model.flash()
		Events.damage_number.emit(center() + Vector3(0, hit_height * 0.4, 0), int(round(_last_health - health)), false, "hit")
	_last_health = health
	if dead and not model._dead:
		model.set_dead(true)
