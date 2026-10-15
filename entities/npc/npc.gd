class_name Npc
extends Entity
## Villagers with daily lives. The server runs each person's routine, plans
## walking routes around buildings (NpcNav) and replicates what they are doing
## through `anim` (an Act plus flags); every machine presents it: walking,
## hammering at the anvil, keeping a stall, patrolling with a torch, going home
## at night (indoors = hidden; important people can still be knocked up),
## sheltering from raids, and turning to face whoever talks to them.
## Dialogue is local to each player because quests are per player.
##
## Routines (hours, see `_routine`):
##   villager    day: strolls the plaza and their street      night: home
##   merchant    day: keeps the stall                         night: home (knock to trade)
##   blacksmith  day: works the anvil                         night: home (knock)
##   elder/chief day: near the hall                           night: in the hall (knock)
##   guard       day: watches the plaza                       night: patrols with a torch
##   raid on the village: everyone but the guards shelters indoors; guards fight.

const CHIEFS := {"emberfall": "Elder Maren", "ashford": "Reeve Halden", "thornwick": "Warden Ysolde",
		"frosthold": "Jarl Hrothgar", "mirewatch": "Old Nessa", "cinderreach": "Ashlord Kael"}
const SMITHS := {"emberfall": "Brannoc", "ashford": "Tamsin", "thornwick": "Odric", "frosthold": "Grima", "mirewatch": "Wendel", "cinderreach": "Sable"}
const FIRST := ["Alda", "Bram", "Cora", "Dunstan", "Edda", "Fenn", "Gisla", "Hob", "Ivo", "Jory", "Kestrel", "Lio",
		"Mabyn", "Nim", "Osric", "Pell", "Rowan", "Sigrun", "Tobin", "Wren", "Agna", "Bertil", "Cass", "Dagny",
		"Eamon", "Freya", "Gorm", "Hild", "Ilse", "Jarl", "Kit", "Leof", "Maud", "Nell", "Orla", "Piet", "Quill",
		"Runa", "Sten", "Tilda"]

enum Act { IDLE, WALK, WORK, TALK, INDOORS, COWER, PATROL, FIGHT }
const TORCH_FLAG := 16
const ACT_MASK := 15

const WALK_SPEED := 1.35
const HURRY_SPEED := 2.6
const TURN_RATE := 5.0
const FACE_RANGE := 3.0
const TALK_SECONDS := 14.0

var role := "villager"
var village := ""
var home := Vector3.ZERO          ## spawn point: where this person belongs during the day
var npc_seed := 0
var act := Act.IDLE
var torch := false
var layout: VillageLayout
var home_door: Dictionary = {}
## Headless simulation hook (tests): duck-typed stand-in for GameWorld.
var sim_world: Object = null

# --- Server state
var _goal := Vector3.INF
var _goal_kind := ""
var _arrive_act := Act.IDLE
var _face_yaw := NAN
var _query: NpcNav.Query = null
var _path := PackedVector3Array()
var _path_i := 0
var _replans := 0
var _progress_t := 0.0
var _progress_pos := Vector3.ZERO
var _think_t := 0.0
var _wait := 0.0
var _talk_id := 0
var _talk_until := -1.0
var _air_t := 0.0
var _gesture_t := 0.0
var _settled := false
var _patrol_i := 0
var _blocked_t := 0.0
var _stuck_total := 0.0
var _hurry := false
var _rng := RandomNumberGenerator.new()
## Diagnostics for tests: recoveries from being stuck or fallen.
var recoveries := 0
var replans_total := 0

# --- Presentation (every machine)
var _model: Node3D
var _label: Label3D
var _speed := 0.0
var _vis_vel := Vector3.ZERO
var _prev_pos := Vector3.ZERO
var _shown_act := -1
var _shown_gesture := -1.0
var _marker_t := 0.0
var _held := ""


func _init() -> void:
	kind = "npc"
	team = Team.NEUTRAL
	hit_radius = 0.4
	body.half_extents = Vector3(0.28, 0.9, 0.28)
	max_health = 9999.0
	health = max_health


func on_spawned(data: Dictionary) -> void:
	role = String(data.get("role", "villager"))
	village = String(data.get("village", ""))
	npc_seed = int(data.get("seed", net_id))
	home = global_position
	_goal = home
	_rng.seed = npc_seed * 31 + 7
	display_name = _make_name(npc_seed)
	_model = HumanoidModel.new(CharStyles.villager(role, npc_seed))
	add_child(_model)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = false
	_label.pixel_size = 0.0065
	_label.font_size = 64
	_label.outline_size = 14
	_label.modulate = Color(1.0, 0.78, 0.3)
	_label.outline_modulate = Color(0.1, 0.05, 0.0, 0.9)
	_label.no_depth_test = false
	_label.position = Vector3(0, 2.3, 0)
	_label.visible = false
	add_child(_label)
	_prev_pos = global_position
	_bind_layout()
	if not Events.dialog_choice.is_connected(_on_choice):
		Events.dialog_choice.connect(_on_choice)


func _make_name(s: int) -> String:
	match role:
		"elder", "chief":
			return CHIEFS.get(village, "Village Chief")
		"blacksmith":
			return SMITHS.get(village, "Smith")
	var pick: String = FIRST[absi(s * 2654435761 + 1013904223) % FIRST.size()]
	match role:
		"merchant":
			return pick + " the Trader"
		"guard":
			return "Guard " + pick
	return pick


func role_title() -> String:
	return String(NpcDialogue.ROLE_TITLES.get(role, "Villager"))


## The world this person lives in (tests substitute a stand-in).
func _w() -> Object:
	return sim_world if sim_world != null else world()


func _vw() -> VoxelWorld:
	var w := _w()
	return w.call("world_for", dimension) if w != null else null


func _bind_layout() -> void:
	var w := _w()
	if w == null or not w.has_method("location_by_id"):
		return
	var loc: Location = w.call("location_by_id", StringName(village))
	layout = VillageLayout.of(loc)
	if layout != null:
		home_door = layout.home_door(role, npc_seed, home)


func _hour() -> float:
	var w := _w()
	return float(w.call("time_of_day")) if w != null and w.has_method("time_of_day") else 12.0


func _now() -> float:
	var w := _w()
	if w != null and "now" in w:
		return float(w.get("now"))
	return Time.get_ticks_msec() / 1000.0


func is_indoors() -> bool:
	return act == Act.INDOORS


# --- Server: routine ---------------------------------------------------------------

## What this person should be doing now: [kind, target, act on arrival, facing yaw or NAN].
func _routine() -> Array:
	var h := _hour()
	var raid := _raid_here()
	var smith_spot := layout.forge_spot() if layout != null else Vector3.INF
	match role:
		"guard":
			if raid:
				return ["defend", _patrol_point(7.0), Act.FIGHT, NAN]
			var night := h >= 19.5 or h < 6.5
			return ["patrol", _patrol_point(13.0 if night else 6.0), Act.PATROL, NAN]
		"blacksmith":
			if not raid and h >= 6.5 and h < 20.5 and smith_spot != Vector3.INF:
				return ["work", smith_spot, Act.WORK, _yaw_to(smith_spot, layout.anvil())]
		"merchant":
			if not raid and h >= 6.5 and h < 21.0:
				return ["work", home, Act.WORK, _yaw_to(home, _plaza())]
		"elder", "chief":
			if not raid and h >= 7.0 and h < 21.0:
				return ["linger", home, Act.IDLE, _yaw_to(home, _plaza())]
		_:
			var bedtime := 20.0 + float(absi(npc_seed) % 4) * 0.4
			if not raid and h >= 6.5 + float(absi(npc_seed) % 3) * 0.3 and h < bedtime:
				return ["wander", Vector3.INF, Act.IDLE, NAN]
	if not home_door.is_empty():
		return ["home", home_door["outside"], Act.INDOORS, NAN]
	# No house to go to: wait it out by the plaza fire.
	return ["gather", _gather_point(), Act.COWER if raid else Act.IDLE, _yaw_to(_gather_point(), _plaza())]


func _raid_here() -> bool:
	var w := _w()
	if w == null:
		return false
	if sim_world != null:
		return sim_world.has_method("raid_at") and bool(sim_world.call("raid_at", village))
	var acts: Node = (w as Node).get_node_or_null(^"Activities")
	return acts != null and acts.has_method("raid_at") and bool(acts.call("raid_at", village))


func _plaza() -> Vector3:
	return layout.center if layout != null else home


func _gather_point() -> Vector3:
	var a := float(absi(npc_seed) % 12) / 12.0 * TAU
	var c := _plaza()
	return Vector3(c.x + cos(a) * 4.5, home.y, c.z + sin(a) * 4.5)


func _patrol_point(radius: float) -> Vector3:
	var c := _plaza() if layout != null else home
	var vw := _vw()
	for attempt in 6:
		var a := TAU * float((_patrol_i + attempt) % 6) / 6.0 + float(absi(npc_seed) % 7)
		var r := radius * (1.0 - 0.15 * attempt)
		var p := Vector3(c.x + cos(a) * r, home.y, c.z + sin(a) * r)
		var h := NpcNav.stand_height(vw, dimension, p.x, p.z, home.y) if vw != null else home.y
		if not is_nan(h) and absf(h - home.y) < 2.5:
			return Vector3(p.x, h, p.z)
	return home


func _yaw_to(from: Vector3, to: Vector3) -> float:
	if to == Vector3.INF or from == Vector3.INF:
		return NAN
	var d := to - from
	return atan2(-d.x, -d.z) if Vector2(d.x, d.z).length() > 0.05 else NAN


# --- Server: tick ------------------------------------------------------------------

func server_tick(delta: float) -> void:
	var vw := _vw()
	if vw == null:
		return
	if not _settled:
		if not vw.is_area_loaded(global_position):
			return
		_settle(vw)
	var now := _now()
	_think_t -= delta
	_wait = maxf(0.0, _wait - delta)
	_gesture_t -= delta
	var want := Vector3.ZERO
	var talker := _talker()
	if talker != null:
		# Stand still and look at whoever is talking to us.
		_clear_path()
		if act == Act.INDOORS:
			pass
		else:
			act = Act.TALK
			_turn_towards(_yaw_to(global_position, talker.global_position), delta)
	elif act == Act.INDOORS:
		if _think_t <= 0.0:
			_think_t = 1.0 + _rng.randf()
			var r := _routine()
			if r[0] != "home":
				_leave_home()
	else:
		if act == Act.TALK:
			act = Act.IDLE
		if _think_t <= 0.0:
			_think()
		want = _follow(vw, delta)
		_present_work(delta)
	body.velocity.x = want.x
	body.velocity.z = want.z
	if act == Act.INDOORS:
		body.velocity = Vector3.ZERO
	else:
		body.step(self, vw, delta)
		if body.hit_wall and want.length() > 0.1:
			_lip_step(vw, want.normalized())
	_watch_health(vw, delta, want)
	rotation.y = yaw
	_speed = Vector2(body.velocity.x, body.velocity.z).length()
	var hr := _hour()
	torch = (role == "guard" and (hr >= 19.0 or hr < 6.5)) or (_hurry and (hr >= 20.0 or hr < 6.0) and role != "villager")
	anim = (act & ACT_MASK) | (TORCH_FLAG if torch else 0)


## Re-evaluate the routine and pick a goal.
func _think() -> void:
	_think_t = 1.2 + _rng.randf() * 0.8
	var r := _routine()
	var kind_: String = r[0]
	var target: Vector3 = r[1]
	_arrive_act = r[2]
	_face_yaw = r[3]
	var h := _hour()
	_hurry = kind_ in ["home", "defend"] and (h >= 21.0 or h < 6.0 or _raid_here())
	if kind_ == "wander":
		if _path_i < _path.size() or _wait > 0.0 or _query != null:
			return
		if _goal_kind == "wander" and act == Act.IDLE and _rng.randf() < 0.35:
			_wait = _rng.randf_range(2.0, 5.0)
			_gesture_t = 0.0
			return
		target = _wander_target()
	elif kind_ == "patrol":
		if _goal_kind == "patrol" and (_path_i < _path.size() or _query != null or _wait > 0.0):
			return
		if _goal_kind == "patrol":
			_patrol_i += 1
			target = _patrol_point(13.0 if (h >= 19.5 or h < 6.5) else 6.0)
	elif kind_ == _goal_kind and target.distance_to(_goal) < 0.5:
		# Same errand: resume it after a chat, or keep at it.
		if _path_i >= _path.size() and _query == null and act in [Act.IDLE, Act.TALK]:
			if _flat_distance(global_position, _goal) < 0.9:
				act = _arrive_act
			elif _wait <= 0.0:
				_set_goal(_goal)  # the last route failed: try again
		return
	elif kind_ == "home" and _goal_kind == "enter":
		if _query == null and _path_i >= _path.size():
			_enter_home()
		return
	_goal_kind = kind_
	_set_goal(target)


func _wander_target() -> Vector3:
	var vw := _vw()
	var anchor := home if _rng.randf() < 0.6 else _plaza()
	for attempt in 6:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(2.0, 8.0)
		var t := anchor + Vector3(cos(a) * d, 0.0, sin(a) * d)
		var hgt := NpcNav.stand_height(vw, dimension, t.x, t.z, anchor.y)
		if not is_nan(hgt) and absf(hgt - home.y) < 2.5:
			return Vector3(t.x, hgt, t.z)
	return home


func _set_goal(target: Vector3) -> void:
	_goal = target
	_clear_path()
	if target == Vector3.INF:
		return
	if _flat_distance(global_position, target) < 0.6:
		_arrive()
		return
	var vw := _vw()
	if NpcNav.segment_clear(vw, dimension, global_position, target):
		_path = PackedVector3Array([target])
		_path_i = 0
	else:
		_query = NpcNav.plan(vw, dimension, global_position, target, 36.0)
	_progress_t = 0.0
	_progress_pos = global_position


func _clear_path() -> void:
	_path = PackedVector3Array()
	_path_i = 0
	_query = null


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Steering along the current route. Returns the wanted horizontal velocity.
func _follow(vw: VoxelWorld, delta: float) -> Vector3:
	if _query != null:
		if NpcNav.step(_query, 260):
			var q := _query
			_query = null
			replans_total += 1
			if q.ok and not q.path.is_empty():
				_path = q.path
				_path_i = 1 if q.path.size() > 1 else 0
			else:
				_give_up()
		return Vector3.ZERO
	if _path_i >= _path.size():
		if act == Act.WALK:
			act = Act.IDLE
		# Glance at people standing close by; otherwise face the work.
		var w := _w()
		var near: Variant = w.call("nearest_player", global_position, dimension, FACE_RANGE) if w != null else null
		if near != null and act in [Act.IDLE, Act.PATROL]:
			_turn_towards(_yaw_to(global_position, (near as Node3D).global_position), delta * 0.6)
		elif not is_nan(_face_yaw):
			_turn_towards(_face_yaw, delta)
		return Vector3.ZERO
	var target := _path[_path_i]
	var to := target - global_position
	to.y = 0.0
	var reach := 0.45 if _path_i == _path.size() - 1 else 0.7
	if to.length() < reach:
		_path_i += 1
		if _path_i >= _path.size():
			_arrive()
			return Vector3.ZERO
		target = _path[_path_i]
		to = target - global_position
		to.y = 0.0
	var speed := HURRY_SPEED if _hurry else (1.55 if role == "guard" else WALK_SPEED)
	var dir := to.normalized()
	# Courtesy: people step to their right to pass each other (and players).
	if _someone_ahead(to):
		_blocked_t += delta
		_progress_pos = global_position
		_progress_t = 0.0
		if _blocked_t > 4.0:
			_blocked_t = 0.0
			_set_goal(_goal)
			return Vector3.ZERO
		var right := Vector3(-dir.z, 0.0, dir.x)
		var side := global_position + right * 0.7
		var hs := NpcNav.stand_height(vw, dimension, side.x, side.z, global_position.y)
		if not is_nan(hs) and absf(hs - global_position.y) < NpcNav.STEP_UP:
			_turn_towards(atan2(-dir.x, -dir.z), delta)
			act = Act.WALK if role != "guard" else Act.PATROL
			return (right * 0.85 + dir * 0.2) * WALK_SPEED
		return Vector3.ZERO
	_blocked_t = 0.0
	act = Act.WALK if role != "guard" else Act.PATROL
	_turn_towards(atan2(-dir.x, -dir.z), delta)
	# Ease off while turning sharply so corners are walked, not skated.
	var facing := -Vector3(sin(yaw), 0, cos(yaw))
	var along := clampf(facing.dot(dir), 0.25, 1.0)
	_watch_progress(delta)
	return dir * speed * along


func _someone_ahead(to: Vector3) -> bool:
	var w := _w()
	if w == null or not w.has_method("entities_near"):
		return false
	var dir := to.normalized()
	for e: Variant in w.call("entities_near", global_position, 1.6, dimension, -1):
		if e == self or not (e is Entity) or (e as Entity).dead:
			continue
		var ent := e as Entity
		if not (ent is Npc or ent.team == Team.PLAYERS):
			continue
		if ent is Npc and (ent as Npc).act == Act.INDOORS:
			continue
		var d := ent.global_position - global_position
		d.y = 0.0
		if d.length() < 1.3 and d.normalized().dot(dir) > 0.55:
			return true
	return false


func _watch_progress(delta: float) -> void:
	_progress_t += delta
	if _progress_t < 1.6:
		return
	var moved := _flat_distance(global_position, _progress_pos)
	_progress_t = 0.0
	_progress_pos = global_position
	if moved > 0.3:
		_replans = 0
		_stuck_total = 0.0
		return
	_stuck_total += 1.6
	_replans += 1
	if _replans <= 2:
		NpcNav.forget_cache()
		_set_goal(_goal)
	else:
		_give_up()


func _give_up() -> void:
	_clear_path()
	_replans = 0
	_stuck_total += 3.0
	act = Act.IDLE
	_wait = _rng.randf_range(1.5, 3.5)
	_think_t = _wait
	if _goal_kind in ["enter", "home"] and not home_door.is_empty() \
			and _flat_distance(global_position, home_door["pos"]) < 3.0:
		# At our own door but the last steps are awkward: just go in.
		_enter_home()
		return
	if _stuck_total > 9.0 and not _observed():
		# Hopelessly wedged and nobody is watching: go where we meant to be.
		_stuck_total = 0.0
		_teleport_to(_goal if _goal != Vector3.INF else home)
	elif _goal_kind == "wander":
		_goal_kind = ""


func _arrive() -> void:
	_clear_path()
	_replans = 0
	_stuck_total = 0.0
	match _goal_kind:
		"home":
			# At the door: walk in.
			_goal_kind = "enter"
			_set_goal(_inside_point())
			return
		"enter":
			_enter_home()
			return
		"out":
			act = Act.IDLE
			_think_t = 0.0
			return
		"wander":
			act = Act.IDLE
			_wait = _rng.randf_range(2.5, 7.0)
			_think_t = _wait
			_face_yaw = NAN
			return
		"patrol", "defend":
			act = Act.PATROL if _goal_kind == "patrol" else Act.FIGHT
			_wait = _rng.randf_range(2.0, 5.0)
			_think_t = _wait
			return
	act = _arrive_act


func _enter_home() -> void:
	act = Act.INDOORS
	_goal_kind = "home"
	_clear_path()
	# Step through the doorway; hidden indoors, knockable at the threshold.
	global_position = _inside_point()
	body.velocity = Vector3.ZERO
	var out: Vector3 = home_door["out"]
	yaw = atan2(-out.x, -out.z)


func _leave_home() -> void:
	if home_door.is_empty():
		act = Act.IDLE
		return
	global_position = _inside_point()
	act = Act.IDLE
	_goal_kind = "out"
	_set_goal(home_door["outside"])


## A spot just inside our door where a person can stand (houses differ:
## furniture, narrow rooms). Shared by everyone using the door.
func _inside_point() -> Vector3:
	if home_door.has("inside_ok"):
		return home_door["inside_ok"]
	if not bool(home_door.get("enterable", true)):
		# A house without a modelled interior: they step in and shut the door.
		home_door["inside_ok"] = home_door["outside"]
		return home_door["outside"]
	var vw := _vw()
	var t: Vector3 = home_door["pos"]
	var out: Vector3 = home_door["out"]
	var side := Vector3(-out.z, 0.0, out.x)
	var best := t - out * 0.6
	for d: float in [1.6, 1.2, 2.0, 0.9, 2.5]:
		var found := false
		for l: float in [0.0, 0.5, -0.5]:
			var q := t - out * d + side * l
			var h := NpcNav.stand_height(vw, dimension, q.x, q.z, t.y)
			if not is_nan(h) and absf(h - t.y) < 0.7 and NpcNav.segment_clear(vw, dimension, t, Vector3(q.x, h, q.z)):
				best = Vector3(q.x, h, q.z)
				found = true
				break
		if found:
			break
	if vw != null and vw.is_area_loaded(t):
		home_door["inside_ok"] = best
	return best


## First tick with terrain: make sure we stand somewhere sensible.
func _settle(vw: VoxelWorld) -> void:
	_settled = true
	var p := global_position
	var h := NpcNav.stand_height(vw, dimension, p.x, p.z, p.y)
	if is_nan(h) or absf(h - p.y) > 1.2 or body._overlaps(vw, Vector3(p.x, h if not is_nan(h) else p.y, p.z)):
		# Spawned on a porch edge, a step or in a wall: find somewhere to stand.
		var spot := _nearest_standable(vw, p, 6)
		if spot != Vector3.INF:
			global_position = spot
			home = spot
	else:
		global_position.y = h
	_prev_pos = global_position
	# People spawned at night appear where the routine puts them, not on the plaza.
	var r := _routine()
	match String(r[0]):
		"home":
			_enter_home()
		"work":
			_teleport_to(r[1])
			act = r[2]
			if not is_nan(float(r[3])):
				yaw = r[3]
			_goal_kind = "work"
			_goal = r[1]


func _nearest_standable(vw: VoxelWorld, p: Vector3, radius: int) -> Vector3:
	for r in range(1, radius + 1):
		for i in 8 * r:
			var a := TAU * float(i) / float(8 * r)
			var x := p.x + cos(a) * r
			var z := p.z + sin(a) * r
			var h := NpcNav.stand_height(vw, dimension, x, z, p.y)
			if not is_nan(h) and absf(h - p.y) < 3.0 and not body._overlaps(vw, Vector3(x, h + 0.002, z)):
				return Vector3(x, h, z)
	return Vector3.INF


func _teleport_to(p: Vector3) -> void:
	var vw := _vw()
	var h := NpcNav.stand_height(vw, dimension, p.x, p.z, p.y)
	if is_nan(h) or absf(h - p.y) > 1.5:
		var spot := _nearest_standable(vw, p, 8)
		if spot == Vector3.INF:
			return
		p = spot
	else:
		p.y = h
	global_position = p
	body.velocity = Vector3.ZERO
	recoveries += 1
	_clear_path()


## Falls, getting buried by someone's digging, drifting off: recover quietly.
func _watch_health(vw: VoxelWorld, delta: float, _want: Vector3) -> void:
	if act == Act.INDOORS:
		_air_t = 0.0
		return
	_air_t = 0.0 if body.on_floor else _air_t + delta
	var lost := global_position.y < home.y - 8.0 or _air_t > 3.0 or _flat_distance(global_position, home) > 45.0
	if lost and not _observed():
		_air_t = 0.0
		_teleport_to(home)
		_goal_kind = ""
	elif vw.field(global_position + Vector3(0, 1.2, 0)) >= 0.5:
		# Someone filled earth onto us: climb out.
		global_position.y += 0.5


## Thresholds: where smooth ground meets a built floor the floor can stand a
## few centimetres proud; VoxelBody only steps whole blocks (which a low door
## lintel then blocks). Lift onto a low crisp edge directly ahead.
func _lip_step(vw: VoxelWorld, dir: Vector3) -> void:
	var p := global_position
	var ahead := p + dir * (body.half_extents.x + 0.15)
	var cell := Vector3i(floori(ahead.x), floori(p.y + 0.001), floori(ahead.z))
	var b := vw.get_block(cell)
	if b <= 0 or not Blocks.is_solid(b) or Blocks.is_smooth(b):
		return
	var top := float(cell.y + 1)
	if top - p.y > NpcNav.STEP_UP or top <= p.y:
		return
	var lifted := Vector3(p.x, top + 0.002, p.z) + dir * 0.2
	if body._overlaps(vw, lifted):
		return
	global_position = lifted


## Is any player close enough to see a person pop into place?
func _observed() -> bool:
	var w := _w()
	if w == null:
		return false
	return w.call("nearest_player", global_position, dimension, 28.0) != null


func _talker() -> Entity:
	if _talk_id == 0 or _now() > _talk_until:
		_talk_id = 0
		return null
	var w := _w()
	var e: Variant = null
	if w != null and w.has_method("entity"):
		e = w.call("entity", _talk_id)
	if e == null or not (e is Entity) or (e as Entity).dead or (e as Entity).global_position.distance_to(global_position) > 6.0:
		_talk_id = 0
		return null
	return e as Entity


func _turn_towards(target_yaw: float, delta: float) -> void:
	if is_nan(target_yaw):
		return
	var diff := angle_difference(yaw, target_yaw)
	yaw += clampf(diff, -TURN_RATE * delta, TURN_RATE * delta)


## Work gestures (server decides the beat, every machine shows it).
func _present_work(_delta: float) -> void:
	if _path_i < _path.size() or _query != null:
		return
	match act:
		Act.WORK:
			if _gesture_t <= 0.0:
				_gesture_t = 1.15 if role == "blacksmith" else _rng.randf_range(4.0, 8.0)
				anim_time = _now()
		Act.FIGHT:
			_guard_fight()
		Act.IDLE, Act.PATROL:
			if _gesture_t <= 0.0:
				_gesture_t = _rng.randf_range(6.0, 14.0)
				anim_time = _now()


## Guards strike monsters that come within reach during a raid.
func _guard_fight() -> void:
	if _gesture_t > 0.0:
		return
	var w := _w()
	if w == null or not w.has_method("entities_near"):
		return
	for e: Variant in w.call("entities_near", global_position, 2.8, dimension, Team.MONSTERS):
		var m := e as Entity
		if m == null or m.dead:
			continue
		var d := m.global_position - global_position
		yaw = atan2(-d.x, -d.z)
		_gesture_t = 1.3
		anim_time = _now()
		if w.has_method("damage"):
			w.call("damage", m, 7.0, net_id, "hit")
		return


# --- Interaction --------------------------------------------------------------------

func server_interact(p: Entity) -> void:
	_talk_id = p.net_id
	_talk_until = _now() + TALK_SECONDS
	_clear_path()
	if act != Act.INDOORS:
		act = Act.TALK
		anim_time = _now()


func interact_prompt(_p: Player) -> String:
	if act == Act.INDOORS:
		if role in ["elder", "chief", "blacksmith", "merchant"]:
			return "Knock — " + display_name
		return ""
	return "Talk to %s (%s)" % [display_name, role_title()]


func local_interact(p: Player) -> void:
	_open_dialog()
	Audio.play_ui("ui_open")
	if act == Act.INDOORS:
		Audio.play("door", global_position, -6.0, 0.9)
	var w := world()
	if w != null and w.replicator != null:
		w.replicator.request_interact(net_id)
	elif p != null:
		server_interact(p)


func _activities() -> Node:
	var w := world()
	return w.get_node_or_null(^"Activities") if w != null else null


func _dialog_info() -> Dictionary:
	var h := _hour()
	return {"role": role, "village": village, "name": display_name, "net_id": net_id,
		"night": h >= 20.0 or h < 6.0, "indoors": act == Act.INDOORS, "hour": h}


func _open_dialog() -> void:
	var w := world()
	var extra := {}
	var acts := _activities()
	if acts != null and acts.has_method("dialog_extra"):
		extra = acts.call("dialog_extra", self)
	var d := NpcDialogue.build(_dialog_info(), w.quests, extra)
	var title := display_name if act != Act.INDOORS else display_name + " (at the door)"
	Events.dialog_open.emit(self, title, d["lines"], d["options"])


func _on_choice(npc: Node, option_id: String) -> void:
	if npc != self:
		return
	var w := world()
	if option_id == "bye" or option_id == "leave":
		Events.dialog_close.emit()
		return
	if option_id == "rumour":
		var extra := {}
		var acts := _activities()
		if acts != null and acts.has_method("dialog_extra"):
			extra = acts.call("dialog_extra", self)
		var line := NpcDialogue.idle_line(_dialog_info(), w.quests, String(extra.get("rumour", "")))
		Events.dialog_open.emit(self, display_name, PackedStringArray([line]), [{"text": "Thanks.", "id": "back"}, {"text": "Farewell.", "id": "bye"}])
		return
	if option_id == "back":
		_open_dialog()
		return
	if option_id.begins_with("turnin:"):
		var qid := option_id.trim_prefix("turnin:")
		if NpcDialogue.turn_ins(w.quests, role, village).has(qid):
			w.quests.complete(qid)
		_open_dialog()
		return
	if option_id.begins_with("accept:") or option_id.begins_with("side:"):
		w.quests.accept(option_id.get_slice(":", 1))
		Events.dialog_close.emit()
		return
	if option_id.begins_with("shop:"):
		Events.dialog_close.emit()
		Events.shop_open.emit(option_id.trim_prefix("shop:"))
		return
	if option_id.begins_with("act:"):
		var acts := _activities()
		if acts != null and acts.has_method("on_dialog_choice"):
			acts.call("on_dialog_choice", self, option_id.trim_prefix("act:"))
		return


# --- Presentation (every machine) -----------------------------------------------------

func _process(delta: float) -> void:
	if _model == null:
		return
	if not is_server():
		interpolate(Net.server_time() if Net.has_method("server_time") else Time.get_ticks_msec() / 1000.0)
		act = anim & ACT_MASK
		torch = (anim & TORCH_FLAG) != 0
	var moved := (global_position - _prev_pos) / maxf(delta, 0.001)
	_prev_pos = global_position
	if moved.length() > 12.0:
		moved = Vector3.ZERO  # a teleport, not a sprint
	_vis_vel = _vis_vel.lerp(Vector3(moved.x, 0.0, moved.z), 1.0 - exp(-delta * 10.0))
	_present(delta)


func _near_local(radius: float) -> bool:
	var gw := world()
	return gw != null and gw.local_player != null and gw.local_player.dimension == dimension \
			and gw.local_player.global_position.distance_to(global_position) < radius


func _present(delta: float) -> void:
	var indoors := act == Act.INDOORS
	if indoors and _shown_act >= 0 and _shown_act != Act.INDOORS and _near_local(24.0):
		Audio.play("door", global_position + Vector3(0, 1, 0), -8.0, randf_range(0.9, 1.1))
	_model.visible = not indoors
	if indoors:
		_shown_act = act
		_label.visible = false
		return
	var vel := body.velocity if is_server() else _vis_vel
	var spd := Vector2(vel.x, vel.z).length()
	if "move_speed" in _model:
		_model.set("move_speed", spd)
	HumanoidModel.drive(_model, self, Vector3(vel.x, 0.0, vel.z), true, spd > 2.2)
	# Tools of the trade.
	var held := ""
	if role == "blacksmith" and act == Act.WORK:
		held = "warhammer_iron"
	elif role == "guard":
		held = "spear_iron"
	if held != _held and _model.has_method("set_held"):
		_held = held
		_model.call("set_held", held)
	if _model.has_method("set_offhand_light"):
		_model.call("set_offhand_light", torch)
	if act != _shown_act or anim_time != _shown_gesture:
		var gesture := anim_time != _shown_gesture and _shown_act >= 0
		if _shown_act == Act.INDOORS and _near_local(24.0):
			Audio.play("door", global_position + Vector3(0, 1, 0), -8.0, randf_range(0.9, 1.1))
		_shown_act = act
		_shown_gesture = anim_time
		if gesture:
			_gesture()
	_marker_t -= delta
	if _marker_t <= 0.0:
		_marker_t = 0.5
		_update_marker()


func _gesture() -> void:
	if not _model.has_method("play"):
		return
	match act:
		Act.WORK:
			if role == "blacksmith":
				_model.call("play", "mine", 0.9)
				_anvil_strike.call_deferred()
			else:
				_model.call("play", "interact", 0.8)
		Act.TALK:
			_model.call("play", "interact", 0.7)
		Act.FIGHT:
			_model.call("play", "attack", 0.6)
			Audio.play("swing", center(), -8.0)
		Act.IDLE, Act.PATROL:
			_model.call("play", "interact" if _rng.randf() < 0.5 else "drink", 1.0)


func _anvil_strike() -> void:
	await get_tree().create_timer(0.42).timeout
	if not is_inside_tree() or layout == null or layout.anvil() == Vector3.INF:
		return
	var a := layout.anvil() + Vector3(0, 0.9, 0)
	var gw := world()
	if gw != null and gw.local_player != null and gw.local_player.global_position.distance_to(a) < 30.0:
		Audio.play("hammer_anvil", a, -6.0, randf_range(0.92, 1.08))
		if gw.local_dimension == dimension:
			ModelKit.burst(gw, a, 14, 0.08, 3.5, 0.06, Color(1.0, 0.85, 0.5), Color(1.0, 0.4, 0.1), 0.45)


func _update_marker() -> void:
	var w := world()
	if w == null or w.local_player == null or w.local_player.dimension != dimension:
		_label.visible = false
		return
	var dist := w.local_player.global_position.distance_to(global_position)
	var m := NpcDialogue.marker(w.quests, role, village) if dist < 60.0 else ""
	var acts := _activities()
	if m == "" and dist < 60.0 and acts != null and acts.has_method("npc_marker"):
		m = String(acts.call("npc_marker", self))
	_label.text = m
	_label.visible = m != ""
	_label.modulate = Color(1.0, 0.78, 0.3) if m != "?" else Color(0.55, 1.0, 0.5)
