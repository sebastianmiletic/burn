class_name Enemy
extends Entity
## Regular monsters: skeleton, archer, ghoul, troll, imp, shade.
##
## Server: a state machine (idle → patrol → chase → attack → recover, with
## stagger, flee and a leash back to the spawn point). Clients: interpolate
## the server's snapshots and play the same animations.
##
## Replicated animation: `anim` = action code (ANIM_*), `anim_time` = the
## server time the action started; a change of either starts it on clients.
## Loot and XP are paid out by whoever listens to `died` (GameWorld) using
## `xp_value` and `loot` ([item_id, chance, min, max]).

enum State { IDLE, PATROL, CHASE, ATTACK, RECOVER, STAGGER, FLEE, RETURN, DEAD }

const ANIM_NONE := 0
const ANIM_ATTACK := 1
const ANIM_HIT := 2
const ANIM_LUNGE := 3
const ANIM_SHOOT := 4
const ANIM_SLAM := 5
const ANIM_THROW := 6
const ANIM_DRAIN := 7
const ANIM_NAMES := ["", "attack", "hit", "lunge", "shoot", "slam", "throw", "drain"]

const STATS := {
	"skeleton": {"name": "Skeleton", "health": 45.0, "damage": 9.0, "speed": 2.6, "chase": 4.4, "aggro": 16.0, "range": 2.1,
		"windup": 0.42, "cooldown": 1.3, "xp": 18, "radius": 0.45, "height": 1.85, "attack": ANIM_ATTACK,
		"loot": [["bone", 0.6, 1, 3], ["iron_ore", 0.15, 1, 1], ["torch", 0.2, 1, 2], ["potion_health", 0.08, 1, 1]]},
	"archer": {"name": "Skeleton Archer", "health": 34.0, "damage": 8.0, "speed": 2.6, "chase": 3.8, "aggro": 24.0, "range": 20.0,
		"prefer": 11.0, "windup": 0.8, "cooldown": 2.1, "xp": 22, "radius": 0.45, "height": 1.85, "attack": ANIM_SHOOT,
		"projectile": "arrow", "projectile_speed": 26.0,
		"loot": [["bone", 0.5, 1, 2], ["torch", 0.3, 1, 3], ["coal", 0.2, 1, 2]]},
	"ghoul": {"name": "Ghoul", "health": 55.0, "damage": 11.0, "speed": 3.2, "chase": 6.0, "aggro": 18.0, "range": 1.9,
		"lunge": 6.5, "windup": 0.32, "cooldown": 1.05, "xp": 25, "radius": 0.45, "height": 1.7, "attack": ANIM_ATTACK,
		"flee_at": 0.22, "loot": [["coal", 0.4, 1, 3], ["potion_health", 0.12, 1, 1], ["gold_ore", 0.05, 1, 1]]},
	"troll": {"name": "Troll", "health": 190.0, "damage": 26.0, "speed": 2.0, "chase": 3.3, "aggro": 16.0, "range": 3.4,
		"windup": 1.05, "cooldown": 2.6, "xp": 70, "radius": 1.0, "height": 3.2, "attack": ANIM_SLAM, "heavy": true,
		"slam_radius": 3.3, "stagger_fraction": 0.3,
		"loot": [["iron_ore", 0.6, 2, 4], ["gold_ore", 0.25, 1, 2], ["frost_shard", 0.3, 1, 2], ["potion_greater", 0.15, 1, 1]]},
	"imp": {"name": "Imp", "health": 40.0, "damage": 13.0, "speed": 3.6, "chase": 5.2, "aggro": 26.0, "range": 17.0,
		"prefer": 9.0, "windup": 0.6, "cooldown": 2.3, "xp": 30, "radius": 0.45, "height": 1.3, "attack": ANIM_THROW,
		"projectile": "fireball", "projectile_speed": 15.0, "fly": true, "hover": 3.2,
		"loot": [["hellstone", 0.2, 1, 1], ["ember_crystal", 0.25, 1, 2]]},
	"shade": {"name": "Shade", "health": 75.0, "damage": 9.0, "speed": 2.8, "chase": 4.2, "aggro": 20.0, "range": 2.4,
		"windup": 0.4, "cooldown": 1.0, "xp": 40, "radius": 0.5, "height": 2.1, "attack": ANIM_DRAIN, "fly": true,
		"hover": 0.4, "ghost": true, "drain": 0.5,
		"loot": [["potion_greater", 0.12, 1, 1], ["ember_crystal", 0.3, 1, 1]]},
}

var stats := {}
var model: CreatureModel
var spawn_point := Vector3.ZERO
var respawn_seconds := 90.0
var xp_value := 10
var loot: Array = []
var state := State.IDLE

var _target: Entity
var _state_t := 0.0
var _cooldown := 0.0
var _patrol_to := Vector3.ZERO
var _attack_landed := false
var _hits_recent := 0.0
var _burn_acc := 0.0
var _burn_dps := 6.0
var _dead_t := 0.0
var _despawned := false
var _rng := RandomNumberGenerator.new()
var _last_anim := [-1, -1.0]
var _last_pos := Vector3.ZERO
var _vis_speed := 0.0
var _last_health := -1.0
var _lunge_dir := Vector3.ZERO
var _hazard_t := 0.0
var _hazard := false
var _hover_ground := 0.0
## Headless simulation hook (tests): when set, used instead of GameWorld.instance.
var sim_world: Object = null


## The world this creature acts in (duck-typed so tests can stand in for GameWorld).
func _w() -> Variant:
	return sim_world if sim_world != null else world()


## Revision 5 overworld lands (SurfaceBiomes), or null (older worlds, simulations).
func _surface_lands() -> SurfaceBiomes:
	var w = _w()
	if w == null or not w.has_method("gen_for"):
		return null
	var g: WorldGen = w.gen_for(0)
	return g.land if g != null else null


static func create(enemy_kind: String) -> Enemy:
	var e := Enemy.new()
	e.kind = enemy_kind
	return e


## Stats for any monster kind: the originals here, newer creatures in MobDB.
static func stats_for(enemy_kind: String) -> Dictionary:
	if STATS.has(enemy_kind):
		return STATS[enemy_kind]
	return MobDB.STATS.get(enemy_kind, STATS["skeleton"])


func _ready() -> void:
	stats = stats_for(kind)
	display_name = stats["name"]
	max_health = stats["health"]
	if health <= 0.0 or health == 100.0:
		health = max_health
	team = Team.MONSTERS
	xp_value = stats["xp"]
	loot = stats["loot"]
	hit_radius = stats["radius"]
	hit_height = stats["height"]
	body.half_extents = Vector3(minf(0.45, hit_radius), hit_height * 0.5, minf(0.45, hit_radius))
	body.fly = stats.get("fly", false)
	body.collides = not stats.get("ghost", false)
	if spawn_point == Vector3.ZERO:
		spawn_point = global_position
	_rng.seed = hash(str(net_id) + kind)
	model = Models.create_mob(kind, net_id)
	add_child(model)
	_last_pos = global_position
	_last_health = health
	_state_t = _rng.randf_range(0.5, 3.0)


# --- Damage ------------------------------------------------------------------------

## Resistances and status effects are applied here so every damage source agrees.
func take_damage(amount: float, source_id := 0, damage_kind := "hit") -> float:
	var resist_kind := "fire" if damage_kind in ["fire", "burn"] else "hit"
	return super.take_damage(Damage.apply(amount, kind, resist_kind), source_id, damage_kind)


func _on_damaged(amount: float, source_id: int, damage_kind: String) -> void:
	if damage_kind == "fire":
		burning = Damage.BURN_SECONDS
	_hits_recent += amount
	Events.damage_number.emit(center() + Vector3(0, hit_height * 0.4, 0), int(round(amount)), damage_kind == "crit", "fire" if damage_kind in ["fire", "burn"] else "hit")
	if model != null:
		model.flash(Color(1.0, 0.6, 0.35) if damage_kind in ["fire", "burn"] else Color(1, 1, 1))
	# Getting hit wakes you up and points you at the attacker.
	if state in [State.IDLE, State.PATROL, State.RETURN] and source_id != 0:
		var w = _w()
		if w != null:
			for p in w.players_in(dimension):
				if p.net_id == source_id:
					_target = p
					_set_state(State.CHASE)
	var threshold := max_health * float(stats.get("stagger_fraction", 0.18))
	if _hits_recent >= threshold and state != State.STAGGER and not dead:
		_hits_recent = 0.0
		_set_state(State.STAGGER, 0.55)
		_start_anim(ANIM_HIT)
	if stats.has("flee_at") and health / max_health < float(stats["flee_at"]) and state != State.FLEE and not dead:
		_set_state(State.FLEE, 2.5)
	Audio.play("bone_rattle" if kind in ["skeleton", "archer", "warden"] else "hit", center(), -4.0, _rng.randf_range(0.9, 1.1))


func _on_died() -> void:
	state = State.DEAD
	body.velocity = Vector3.ZERO
	burning = 0.0
	if model != null:
		model.set_dead(true)
		model.set_burning(false)
	Audio.play("bone_rattle" if kind in ["skeleton", "archer"] else "death", center(), -2.0)


# --- Server AI ------------------------------------------------------------------

## AI level of detail: calm monsters with no player nearby think 5x a second.
var _lod_acc := 0.0
var _lod_check := 0.0
var _lod_step := 0.0


## Seconds of simulation to run now, or -1 to skip this frame.
func _lod_gate(delta: float) -> float:
	_lod_check -= delta
	if _lod_check <= 0.0:
		_lod_check = 0.5
		var w = _w()
		var near: Variant = w.nearest_player(global_position, dimension, 40.0) if w != null else null
		_lod_step = 0.0 if near != null or not state in [State.IDLE, State.PATROL, State.RETURN] else 0.2
	_lod_acc += delta
	if _lod_acc < _lod_step:
		return -1.0
	var d := _lod_acc
	_lod_acc = 0.0
	return d


func server_tick(frame_delta: float) -> void:
	var delta := frame_delta if dead else _lod_gate(frame_delta)
	if delta < 0.0:
		return
	if dead:
		_dead_t += delta
		if _dead_t > 3.6 and not _despawned:
			_despawned = true
			var w = _w()
			if w != null:
				w.despawn_entity(self)
		return
	_hits_recent = maxf(0.0, _hits_recent - delta * max_health * 0.1)
	_tick_burn(delta)
	_cooldown -= delta
	_state_t -= delta
	_think(delta)
	if not dead:
		body.step(self, voxels(), delta)
		rotation.y = yaw
	if model != null:
		model.move_speed = Vector2(body.velocity.x, body.velocity.z).length()
		model.grounded = body.on_floor or body.fly
		model.set_burning(burning > 0.0)
		HumanoidModel.drive(model, self, body.velocity, body.on_floor or body.fly, state == State.CHASE)


func _tick_burn(delta: float) -> void:
	if burning <= 0.0:
		return
	burning -= delta
	_burn_acc += delta
	if _burn_acc >= Damage.BURN_TICK:
		_burn_acc -= Damage.BURN_TICK
		var w = _w()
		if w != null:
			w.damage(self, Damage.burn_tick(_burn_dps), last_hit_by, "burn")


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _set_state(s: State, duration := 0.0) -> void:
	state = s
	_state_t = duration
	_attack_landed = false


func _start_anim(code: int) -> void:
	anim = code
	anim_time = _now()


func _think(delta: float) -> void:
	var w = _w()
	if w == null:
		return
	var aggro := float(stats["aggro"])
	if _target != null and (not is_instance_valid(_target) or _target.dead or _target.dimension != dimension):
		_target = null
	match state:
		State.IDLE:
			_steer(global_position, 0.0, delta)
			if _scan(w, aggro):
				return
			if _state_t <= 0.0:
				var a := _rng.randf() * TAU
				_patrol_to = spawn_point + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(3.0, 9.0)
				_set_state(State.PATROL, 8.0)
		State.PATROL:
			if _scan(w, aggro):
				return
			var flat := Vector2(_patrol_to.x - global_position.x, _patrol_to.z - global_position.z)
			_steer(_patrol_to, float(stats["speed"]), delta)
			if flat.length() < 1.0 or _state_t <= 0.0:
				_set_state(State.IDLE, _rng.randf_range(2.0, 5.0))
		State.CHASE:
			if _target == null:
				_set_state(State.RETURN, 10.0)
				return
			var to_spawn := Vector2(global_position.x - spawn_point.x, global_position.z - spawn_point.z).length()
			var dist := _flat_dist(_target)
			if to_spawn > 40.0 or dist > aggro * 1.9:
				_target = null
				_set_state(State.RETURN, 12.0)
				return
			_chase(dist, delta)
		State.ATTACK:
			_attack(delta)
		State.RECOVER:
			if _target != null:
				_face(_target.global_position, delta, 6.0)
			_steer(global_position, 0.0, delta)
			if _state_t <= 0.0:
				_set_state(State.CHASE)
		State.STAGGER:
			_steer(global_position, 0.0, delta)
			if _state_t <= 0.0:
				_set_state(State.CHASE if _target != null else State.IDLE, 1.0)
		State.FLEE:
			if _target != null:
				var away := global_position + (global_position - _target.global_position).normalized() * 6.0
				_steer(away, float(stats["chase"]) * 1.1, delta)
			if _state_t <= 0.0:
				_set_state(State.CHASE if _target != null else State.IDLE)
		State.RETURN:
			# Walk home and recover; ignore players until back.
			heal(max_health * 0.25 * delta)
			_steer(spawn_point, float(stats["chase"]), delta)
			var home := Vector2(global_position.x - spawn_point.x, global_position.z - spawn_point.z).length()
			if home < 1.5 or _state_t <= 0.0:
				if _state_t <= 0.0 and home > 3.0:
					global_position = spawn_point  # stuck on the way: snap home
				_set_state(State.IDLE, 2.0)


func _scan(w: Variant, aggro: float) -> bool:
	var p: Entity = w.nearest_player(global_position, dimension, aggro)
	if p != null and not p.dead:
		_target = p
		_set_state(State.CHASE)
		if kind in ["skeleton", "archer"]:
			Audio.play("bone_rattle", center(), -6.0)
		elif kind == "imp":
			Audio.play("imp_screech", center(), -4.0)
		else:
			Audio.play("growl", center(), -4.0)
		return true
	return false


func _flat_dist(e: Entity) -> float:
	return Vector2(e.global_position.x - global_position.x, e.global_position.z - global_position.z).length()


func _chase(dist: float, delta: float) -> void:
	var reach := float(stats["range"])
	var chase := float(stats["chase"])
	var prefer := float(stats.get("prefer", 0.0))
	if stats.has("lunge") and dist < float(stats["lunge"]) and dist > reach + 0.8 and _cooldown <= 0.0:
		_lunge_dir = (_target.global_position - global_position)
		_lunge_dir.y = 0.0
		_lunge_dir = _lunge_dir.normalized()
		_start_anim(ANIM_LUNGE)
		_set_state(State.ATTACK, 0.65)
		return
	if prefer > 0.0:
		# Ranged: keep a comfortable distance, shoot when in reach and in sight.
		if dist < prefer * 0.6:
			var away := global_position + (global_position - _target.global_position).normalized() * 4.0
			_steer(away, float(stats["speed"]), delta)
		elif dist > minf(reach, prefer * 1.4):
			_steer(_target.global_position, chase, delta)
		else:
			_steer(global_position, 0.0, delta)
		_face(_target.global_position, delta, 8.0)
		if dist <= reach and _cooldown <= 0.0 and _has_line_of_sight(_target):
			_start_anim(int(stats["attack"]))
			_set_state(State.ATTACK, float(stats["windup"]) + 0.35)
		return
	if dist > reach:
		_steer(_target.global_position, chase, delta)
	else:
		_steer(global_position, 0.0, delta)
		_face(_target.global_position, delta, 10.0)
		if _cooldown <= 0.0:
			_start_anim(int(stats["attack"]))
			_set_state(State.ATTACK, float(stats["windup"]) + 0.4)
			if stats.get("heavy", false):
				var w = _w()
				var center_pos := global_position + _forward() * 1.8
				w.telegraph("circle", center_pos, _forward(), Vector3(float(stats["slam_radius"]), 0, 0), float(stats["windup"]), dimension)


func _attack(delta: float) -> void:
	var windup := float(stats["windup"])
	var elapsed := (windup + 0.4) - _state_t if anim != ANIM_LUNGE else 0.65 - _state_t
	if anim == ANIM_LUNGE:
		# Dash at the target; hit on contact once.
		var speed := 11.0 if elapsed < 0.4 else 2.0
		body.velocity.x = _lunge_dir.x * speed
		body.velocity.z = _lunge_dir.z * speed
		_face(global_position + _lunge_dir, delta, 20.0)
		if not _attack_landed and _target != null and _flat_dist(_target) < float(stats["range"]) + 0.6:
			_attack_landed = true
			_hit_target(float(stats["damage"]) * 1.2)
	else:
		_steer(global_position, 0.0, delta)
		if _target != null and elapsed < windup * 0.7:
			_face(_target.global_position, delta, 8.0)
		if not _attack_landed and elapsed >= windup:
			_attack_landed = true
			_strike()
	if _state_t <= 0.0:
		_cooldown = float(stats["cooldown"]) * _rng.randf_range(0.85, 1.2)
		_set_state(State.RECOVER, 0.25)


func _strike() -> void:
	var w = _w()
	if w == null:
		return
	var dmg := Damage.monster(float(stats["damage"]), false, w.players_in(dimension).size())
	if stats.has("projectile"):
		if _target == null:
			return
		var origin := global_position + Vector3(0, hit_height * 0.75, 0) + _forward() * 0.6
		var speed := float(stats["projectile_speed"])
		var aim := _target.center()
		var t := origin.distance_to(aim) / speed
		if stats["projectile"] == "arrow":
			aim.y += 0.5 * 9.0 * t * t
		w.spawn_projectile(stats["projectile"], origin, (aim - origin).normalized() * speed, net_id, Team.MONSTERS, dimension, dmg)
		return
	if stats.get("heavy", false):
		var center_pos := global_position + _forward() * 1.8
		for p in w.players_in(dimension):
			if TelegraphShape.contains("circle", center_pos, _forward(), Vector3(float(stats["slam_radius"]), 0, 0), p.global_position, 3.0):
				w.damage(p, dmg, net_id, "hit")
		w.shake(0.5)
		Audio.play("stomp", global_position)
		var parent := get_parent() as Node3D
		if parent != null:
			ModelKit.burst(parent, center_pos + Vector3(0, 0.2, 0), 30, 1.5, 4.0, 0.7, Color(0.8, 0.75, 0.7), Color(0.4, 0.36, 0.32), 0.8)
		return
	_hit_target(dmg)


func _hit_target(dmg: float) -> void:
	var w = _w()
	if w == null or _target == null or _target.dead:
		return
	var to := _target.global_position - global_position
	to.y = 0.0
	var in_front := to.length() < 0.6 or to.normalized().dot(_forward()) > 0.2
	if to.length() <= float(stats["range"]) + 0.7 and in_front and absf(_target.global_position.y - global_position.y) < 2.5:
		w.damage(_target, dmg, net_id, "hit")
		if stats.has("drain"):
			heal(dmg * float(stats["drain"]))
		Audio.play("hit", _target.center(), -2.0)
	else:
		Audio.play("swing", center(), -6.0)


func _has_line_of_sight(e: Entity) -> bool:
	var v := voxels()
	if v == null:
		return true
	var from := global_position + Vector3(0, hit_height * 0.8, 0)
	var to := e.center()
	var hit := v.raycast(from, to - from, from.distance_to(to))
	return hit.is_empty()


func _forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func _face(target: Vector3, delta: float, rate: float) -> void:
	var d := target - global_position
	if Vector2(d.x, d.z).length() < 0.05:
		return
	yaw = lerp_angle(yaw, atan2(-d.x, -d.z), 1.0 - exp(-rate * delta))


func _steer(target: Vector3, speed: float, delta: float) -> void:
	if dimension == 0:
		var land := _surface_lands()
		if land != null:
			target = land.keep_out(global_position, target)  # revision 5: the oasis is a safe zone
	var to := target - global_position
	to.y = 0.0
	var desired := Vector3.ZERO
	if to.length() > 0.3 and speed > 0.0:
		desired = to.normalized() * speed
		if not body.fly and _hazard_ahead(to.normalized(), delta):
			desired = Vector3.ZERO
		_face(target, delta, 7.0)
	body.velocity.x = lerpf(body.velocity.x, desired.x, 1.0 - exp(-9.0 * delta))
	body.velocity.z = lerpf(body.velocity.z, desired.z, 1.0 - exp(-9.0 * delta))
	if body.fly:
		var hover := float(stats.get("hover", 2.5))
		var want_y := _ground_below() + hover
		if _target != null and kind == "imp":
			want_y = maxf(want_y, _target.global_position.y + hover)
		if stats.get("ghost", false) and _target != null:
			want_y = _target.global_position.y + hover
		body.velocity.y = lerpf(body.velocity.y, clampf((want_y - global_position.y) * 2.0, -4.0, 4.0), 1.0 - exp(-4.0 * delta))
	elif body.hit_wall and body.on_floor and desired.length() > 0.1:
		body.velocity.y = 8.6


## Looks one step ahead for cliffs and lava (re-checked a few times a second).
func _hazard_ahead(dir: Vector3, delta: float) -> bool:
	_hazard_t -= delta
	if _hazard_t > 0.0:
		return _hazard
	_hazard_t = 0.2
	_hazard = false
	var v := voxels()
	if v == null:
		return false
	var ahead := global_position + dir * (hit_radius + 0.8)
	var foot := Vector3i(ahead.floor())
	for dy in range(0, 5):
		var b := v.get_block(foot - Vector3i(0, dy, 0))
		if b < 0:
			return false
		if b == Blocks.LAVA:
			_hazard = true
			return true
		if b != Blocks.AIR and Blocks.is_solid(b):
			return false
		if dy == 0 and b != Blocks.AIR and Blocks.is_liquid(b):
			return false
	_hazard = true  # a drop of more than four blocks
	return true


func _ground_below() -> float:
	var v := voxels()
	if v == null:
		return global_position.y
	if absf(_hover_ground - global_position.y) > 30.0:
		_hover_ground = global_position.y
	var p := Vector3i(global_position.floor())
	for dy in range(0, 24):
		var b := v.get_block(p - Vector3i(0, dy, 0))
		if b > 0 and (Blocks.is_solid(b) or Blocks.is_liquid(b)):
			_hover_ground = float(p.y - dy + 1)
			return _hover_ground
	return _hover_ground


# --- Client presentation ----------------------------------------------------------

func _process(delta: float) -> void:
	if model == null:
		return
	if not is_server():
		interpolate(Time.get_ticks_msec() / 1000.0)
		var moved := (global_position - _last_pos) / maxf(delta, 0.0001)
		_vis_speed = lerpf(_vis_speed, Vector2(moved.x, moved.z).length(), 1.0 - exp(-10.0 * delta))
		model.move_speed = _vis_speed
		model.grounded = true
		model.set_burning(burning > 0.0)
		HumanoidModel.drive(model, self, Vector3(moved.x, 0.0, moved.z))
		if _last_health >= 0.0 and health < _last_health - 0.01:
			var drop := _last_health - health
			model.flash()
			Events.damage_number.emit(center() + Vector3(0, hit_height * 0.4, 0), int(round(drop)), false, "hit")
		_last_health = health
		if dead and not model._dead:
			model.set_dead(true)
	_last_pos = global_position
	if anim != _last_anim[0] or anim_time != _last_anim[1]:
		_last_anim = [anim, anim_time]
		if anim > 0 and anim < ANIM_NAMES.size() and not dead:
			var dur := -1.0
			if anim in [ANIM_ATTACK, ANIM_SHOOT, ANIM_SLAM, ANIM_THROW, ANIM_DRAIN]:
				dur = float(stats["windup"]) + 0.35
			model.play(ANIM_NAMES[anim], dur)
			if anim == ANIM_ATTACK or anim == ANIM_LUNGE:
				Audio.play("swing", center(), -6.0)
			elif anim == ANIM_SHOOT:
				Audio.play("bow", center(), -4.0)
