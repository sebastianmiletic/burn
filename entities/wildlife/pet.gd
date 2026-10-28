class_name Pet
extends Entity
## Animals that can be tamed and kept: foxes and ravens (fed fish), stray
## cats (fish) in villages, and wild dogs (meat). Wild ones keep their
## distance and bolt when crowded, but come closer, curious, to a player who
## stands still holding the right food. Each feeding (E with the food in hand)
## may win them over; it takes a few. A tamed pet belongs to that character:
## it follows (and is fetched to its owner when left far behind, or into
## another realm), sits, or stays put, answers to a name, and dogs fight
## whatever comes at their owner. Pets cannot be hurt.
##
## Server-run like all creatures; `anim` carries the mode (MODE_*), the owner,
## name and taming progress travel in spawn data and entity events. Owners
## keep their pets in their character (CharacterLife), VillageLife brings them
## back next session and relays commands.

const SPECIES := {
	"fox": {"name": "Fox", "food": "fish", "feeds": 3, "chance": 0.4, "speed": 1.4, "run": 7.5, "radius": 0.3, "height": 0.5, "shy": 11.0, "defends": false},
	"wild_dog": {"name": "Wild Dog", "food": "meat", "feeds": 3, "chance": 0.45, "speed": 1.5, "run": 7.8, "radius": 0.38, "height": 0.7, "shy": 8.0, "defends": true},
	"cat": {"name": "Stray Cat", "food": "fish", "feeds": 2, "chance": 0.5, "speed": 1.0, "run": 6.5, "radius": 0.2, "height": 0.33, "shy": 4.5, "defends": false},
	"raven": {"name": "Raven", "food": "fish", "feeds": 4, "chance": 0.35, "speed": 1.2, "run": 8.0, "radius": 0.22, "height": 0.35, "shy": 9.0, "defends": false, "bird": true},
	# Ultra-rare: never sold by anyone; seen only now and then over the peaks and canyons,
	# and it will take nothing but an Ember Eel (fished from the boiling vents).
	"phoenix": {"name": "Phoenix", "food": "fish_ember_eel", "feeds": 5, "chance": 0.25, "speed": 1.4, "run": 9.0, "radius": 0.3, "height": 0.45, "shy": 14.0,
		"defends": true, "bird": true, "rare": true},
}
const PET_NAMES := {"fox": "Fox", "wild_dog": "Dog", "cat": "Cat", "raven": "Raven", "phoenix": "Phoenix"}

const MODE_WILD := 0
const MODE_FLEE := 1
const MODE_CURIOUS := 2
const MODE_FOLLOW := 3
const MODE_SIT := 4
const MODE_STAY := 5
const MODE_FIGHT := 6
const MODE_MASK := 7
const MODES := {"follow": MODE_FOLLOW, "sit": MODE_SIT, "stay": MODE_STAY}

const TELEPORT_DISTANCE := 32.0
const FOLLOW_NEAR := 2.6
const DEFEND_RADIUS := 9.0
const BITE := 9.0

var spec := {}
var owner_id := 0
var pet_name := ""
var uid := 0
var variant := 0
var mode := MODE_WILD
var feeds := {}             ## player net id -> feedings (server)
var stay_at := Vector3.INF
var model: CreatureModel
var sim_world: Object = null

var _rng := RandomNumberGenerator.new()
var _think_t := 0.0
var _goal := Vector3.INF
var _foe: Entity
var _bite_cd := 0.0
var _owner_gone := 0.0
var _home := Vector3.ZERO
var _last_pos := Vector3.ZERO
var _vis_speed := 0.0
var _plate: Label3D
var _shown_anim_time := 0.0


static func create(pet_kind: String) -> Pet:
	var e := Pet.new()
	e.kind = pet_kind
	return e


func _w() -> Object:
	return sim_world if sim_world != null else world()


func is_bird() -> bool:
	return bool(spec.get("bird", false))


func tamed() -> bool:
	return owner_id != 0


func on_spawned(data: Dictionary) -> void:
	spec = SPECIES.get(kind, SPECIES["fox"])
	variant = int(data.get("variant", net_id))
	owner_id = int(data.get("owner", 0))
	pet_name = String(data.get("name", ""))
	uid = int(data.get("uid", 0))
	mode = MODES.get(String(data.get("mode", "follow")), MODE_FOLLOW) if tamed() else MODE_WILD
	anim = mode
	display_name = pet_name if pet_name != "" else String(spec["name"])
	team = Team.PLAYERS if tamed() else Team.NEUTRAL
	hit_radius = float(spec["radius"])
	hit_height = float(spec["height"])
	body.half_extents = Vector3(minf(0.3, hit_radius), maxf(0.15, hit_height * 0.5), minf(0.3, hit_radius))
	max_health = 100.0
	health = max_health
	_home = global_position
	_last_pos = global_position
	_rng.seed = hash(str(net_id) + kind)
	if DisplayServer.get_name() != "headless" or sim_world == null:
		model = Models.create_mob(kind, variant)
		add_child(model)
	_plate = Label3D.new()
	_plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_plate.pixel_size = 0.003
	_plate.font_size = 44
	_plate.outline_size = 10
	_plate.modulate = Color(0.75, 0.95, 0.7)
	_plate.outline_modulate = Color(0.05, 0.05, 0.03, 0.85)
	_plate.position = Vector3(0, hit_height + 0.35, 0)
	_plate.visible = false
	add_child(_plate)
	if not Events.dialog_choice.is_connected(_on_choice):
		Events.dialog_choice.connect(_on_choice)


## Pets never take harm (and wild ones are not game).
func take_damage(_amount: float, _source_id := 0, _damage_kind := "hit") -> float:
	return 0.0


## The food this animal takes from a hand ("" if `item` will not do).
func accepts(item: String) -> bool:
	match String(spec.get("food", "fish")):
		"meat":
			return VillageGoods.is_meat(item)
		"fish":
			return VillageGoods.is_fish(item) and ItemDB.category(item) == "consumable"
		var only:
			return item == String(only)


# --- Server -------------------------------------------------------------------------------

func server_tick(delta: float) -> void:
	var w := _w()
	if w == null:
		return
	_think_t -= delta
	_bite_cd -= delta
	if tamed():
		_tick_tamed(w, delta)
	else:
		_tick_wild(w, delta)
	anim = mode
	rotation.y = yaw
	if model != null:
		_present(Vector2(body.velocity.x, body.velocity.z).length())


func _vw() -> VoxelWorld:
	var w := _w()
	return w.call("world_for", dimension) if w != null else null


func _tick_wild(w: Object, delta: float) -> void:
	if _think_t <= 0.0:
		_think_t = 0.3 + _rng.randf() * 0.15
		var p: Variant = w.call("nearest_player", global_position, dimension, float(spec["shy"]) * 1.6)
		var pl := p as Entity
		if pl != null and not pl.dead:
			var food := pl.has_method("held_item") and accepts(String(pl.call("held_item")))
			var d := pl.global_position.distance_to(global_position)
			var calm := Vector2(pl.body.velocity.x, pl.body.velocity.z).length() < 2.5 if "body" in pl else true
			if food and calm:
				mode = MODE_CURIOUS
				var to := pl.global_position - global_position
				to.y = 0.0
				_goal = pl.global_position - to.normalized() * 1.5 if d > 1.8 else Vector3.INF
			elif d < float(spec["shy"]):
				mode = MODE_FLEE
				var away := global_position - pl.global_position
				away.y = 0.0
				_goal = global_position + away.normalized() * 10.0
			elif mode != MODE_WILD:
				mode = MODE_WILD
				_goal = Vector3.INF
		elif mode != MODE_WILD or (_goal == Vector3.INF and _rng.randf() < 0.08):
			mode = MODE_WILD
			var a := _rng.randf() * TAU
			_goal = _home + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(2.0, 7.0)
		elif mode == MODE_WILD and _goal != Vector3.INF and _flat(_goal - global_position) < 0.6:
			_goal = Vector3.INF
	var speed := float(spec["run"]) if mode == MODE_FLEE else float(spec["speed"]) * (1.6 if mode == MODE_CURIOUS else 1.0)
	if is_bird() and mode == MODE_FLEE:
		_fly_off(delta)
		return
	_walk_to(_goal, speed, delta)


## Fed by `feeder` (server): maybe tamed. Returns progress 0..1 (1 = tamed).
func server_feed(feeder: Entity, item: String) -> float:
	if tamed() or feeder == null or not accepts(item):
		return -1.0
	var n := int(feeds.get(feeder.net_id, 0)) + 1
	feeds[feeder.net_id] = n
	var need := int(spec["feeds"])
	var progress := minf(0.95, float(n) / float(need))
	if n >= need and _rng.randf() < float(spec["chance"]) + 0.18 * (n - need):
		_tame(feeder)
		return 1.0
	anim_time = _now()
	_event("fed", [feeder.net_id, progress])
	return progress


func _tame(feeder: Entity) -> void:
	owner_id = feeder.net_id
	pet_name = String(PET_NAMES.get(kind, "Pet"))
	display_name = pet_name
	mode = MODE_FOLLOW
	team = Team.PLAYERS
	feeds.clear()
	if has_meta("wild"):
		remove_meta("wild")
	_event("tamed", [owner_id, pet_name, variant])
	_sync_spawn_data()


## Players who come into range later spawn us from this: keep it current.
func _sync_spawn_data() -> void:
	var m := "follow"
	for k: String in MODES:
		if MODES[k] == mode:
			m = k
	set_meta("spawn_data", {"owner": owner_id, "name": pet_name, "uid": uid, "variant": variant, "mode": m})


## Owner commands (server; VillageLife checks the sender owns us).
func server_command(cmd: String, arg: Variant) -> void:
	match cmd:
		"follow", "sit", "stay":
			mode = MODES[cmd]
			stay_at = global_position if cmd == "stay" else Vector3.INF
			_foe = null
			_event("mode", cmd)
		"name":
			var n := String(arg).strip_edges().left(20)
			if n != "":
				pet_name = n
				display_name = n
				_event("named", n)
		"uid":
			uid = int(arg)
		"release":
			owner_id = 0
			team = Team.NEUTRAL
			mode = MODE_WILD
			_home = global_position
			set_meta("wild", true)
			set_meta("wild_role", "tame")
			_event("released", null)
	_sync_spawn_data()


func _tick_tamed(w: Object, delta: float) -> void:
	var o: Variant = w.call("entity", owner_id) if w.has_method("entity") else null
	var owner := o as Entity
	if owner == null or not is_instance_valid(owner):
		# Owner left the game: the pet goes with them (saved in their character).
		_owner_gone += delta
		if _owner_gone > 4.0 and w.has_method("despawn_entity") and sim_world == null:
			w.call("despawn_entity", self)
		return
	_owner_gone = 0.0
	if owner.dimension != dimension:
		var vl := VillageLife.of(w as Node) if sim_world == null else null
		if vl != null:
			vl.move_pet_to_owner(self, owner)
		return
	var od := _flat(owner.global_position - global_position)
	if mode in [MODE_FOLLOW, MODE_FIGHT] and (od > TELEPORT_DISTANCE or absf(owner.global_position.y - global_position.y) > 12.0):
		_teleport_near(owner)
		return
	# Dogs defend their owner.
	if bool(spec.get("defends", false)) and mode in [MODE_FOLLOW, MODE_STAY, MODE_FIGHT]:
		if _foe == null or not is_instance_valid(_foe) or _foe.dead or _flat(_foe.global_position - owner.global_position) > DEFEND_RADIUS * 1.8:
			_foe = _find_foe(w, owner)
		if _foe != null:
			mode = MODE_FIGHT
			var to := _foe.global_position - global_position
			if _flat(to) > _foe.hit_radius + 1.0:
				_walk_to(_foe.global_position, float(spec["run"]), delta)
			else:
				_walk_to(Vector3.INF, 0.0, delta)
				yaw = atan2(-to.x, -to.z)
				if _bite_cd <= 0.0:
					_bite_cd = 1.1
					anim_time = _now()
					if w.has_method("damage"):
						w.call("damage", _foe, BITE, net_id, "hit")
			return
		if mode == MODE_FIGHT:
			mode = MODE_FOLLOW if stay_at == Vector3.INF else MODE_STAY
	match mode:
		MODE_FOLLOW:
			if is_bird():
				_fly_with(owner, delta)
				return
			if od > FOLLOW_NEAR + 0.6:
				var back := owner.global_position - global_position
				back.y = 0.0
				var target := owner.global_position - back.normalized() * FOLLOW_NEAR
				_walk_to(target, float(spec["run"]) * (0.9 if od > 8.0 else 0.45), delta)
			else:
				_walk_to(Vector3.INF, 0.0, delta)
				_face(owner.global_position, delta * 0.5)
		MODE_SIT:
			_walk_to(Vector3.INF, 0.0, delta)
		MODE_STAY:
			if stay_at == Vector3.INF:
				stay_at = global_position
			if _think_t <= 0.0:
				_think_t = _rng.randf_range(3.0, 7.0)
				var a := _rng.randf() * TAU
				_goal = stay_at + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(0.5, 2.5)
			_walk_to(_goal, float(spec["speed"]) * 0.7, delta)


func _find_foe(w: Object, owner: Entity) -> Entity:
	if not w.has_method("entities_near"):
		return null
	var best: Entity = null
	var bd := DEFEND_RADIUS
	for e: Variant in w.call("entities_near", owner.global_position, DEFEND_RADIUS, dimension, Team.MONSTERS):
		var m := e as Entity
		if m == null or m.dead or m is Pet or m is Wildlife:
			continue
		var d := m.global_position.distance_to(owner.global_position)
		if d < bd:
			bd = d
			best = m
	return best


func _walk_to(target: Vector3, speed: float, delta: float) -> void:
	var desired := Vector3.ZERO
	if target != Vector3.INF and speed > 0.0:
		var to := target - global_position
		to.y = 0.0
		if to.length() > 0.4:
			desired = to.normalized() * speed
			_face(target, delta)
	if is_bird():
		# Birds hop about on the ground when they are not flying.
		body.velocity.x = lerpf(body.velocity.x, desired.x * 0.5, 1.0 - exp(-6.0 * delta))
		body.velocity.z = lerpf(body.velocity.z, desired.z * 0.5, 1.0 - exp(-6.0 * delta))
	else:
		body.velocity.x = lerpf(body.velocity.x, desired.x, 1.0 - exp(-7.0 * delta))
		body.velocity.z = lerpf(body.velocity.z, desired.z, 1.0 - exp(-7.0 * delta))
	if body.hit_wall and body.on_floor and desired.length() > 0.1:
		body.velocity.y = 6.5
	var vw := _vw()
	if vw != null:
		body.step(self, vw, delta)


func _face(target: Vector3, delta: float) -> void:
	var d := target - global_position
	if Vector2(d.x, d.z).length() < 0.05:
		return
	yaw = lerp_angle(yaw, atan2(-d.x, -d.z), 1.0 - exp(-8.0 * delta))


## A raven rides the air at its owner's shoulder.
func _fly_with(owner: Entity, delta: float) -> void:
	var side := Vector3(cos(owner.yaw), 0, -sin(owner.yaw))
	var t := _now()
	var target := owner.global_position + side * 0.9 + Vector3(sin(t * 0.7) * 0.4, 2.3 + sin(t * 1.3) * 0.25, cos(t * 0.5) * 0.4)
	var v := (target - global_position) * minf(1.0, delta * 2.5)
	global_position += v
	body.velocity = v / maxf(delta, 0.001)
	_face(global_position + Vector3(v.x, 0, v.z) * 10.0 if v.length() > 0.01 else owner.global_position, delta)


func _fly_off(delta: float) -> void:
	var dir := Vector3(sin(yaw), 0, cos(yaw)) * -1.0
	global_position += (dir * float(spec["run"]) + Vector3(0, 3.0, 0)) * delta
	body.velocity = dir * float(spec["run"])
	if global_position.y > _home.y + 30.0:
		var w := _w()
		if w != null and w.has_method("despawn_entity") and sim_world == null:
			w.call("despawn_entity", self)


func _teleport_near(owner: Entity) -> void:
	var back := -Vector3(sin(owner.yaw), 0, cos(owner.yaw))
	var p := owner.global_position + back * 1.8 + Vector3(_rng.randf_range(-0.6, 0.6), 0, _rng.randf_range(-0.6, 0.6))
	var vw := _vw()
	if vw != null:
		var g := vw.ground_below(p.x, p.y + 2.0, p.z, 6.0)
		p.y = g if absf(g) < 1e6 else owner.global_position.y
	global_position = p
	body.velocity = Vector3.ZERO
	_snapshots.clear()


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _now() -> float:
	var w := _w()
	if w != null and "now" in w:
		return float(w.get("now"))
	return Time.get_ticks_msec() / 1000.0


func _event(ev: String, arg: Variant) -> void:
	var w := world()
	if sim_world == null and w != null and w.replicator != null:
		w.replicator.broadcast_entity_event(net_id, ev, arg)
	else:
		on_event(ev, arg)


# --- Every machine ----------------------------------------------------------------------------

func on_event(ev: String, arg: Variant) -> void:
	var w := world()
	var me := w.local_player if w != null else null
	match ev:
		"fed":
			if model != null:
				model.play("bite", 0.6)
			Audio.play("pickup", center(), -14.0, 1.6)
			var a: Array = arg
			if me != null and int(a[0]) == me.net_id:
				var pct := int(float(a[1]) * 100.0)
				Events.notify.emit("The %s eats from your hand. (%d%% tame)" % [String(spec.get("name", kind)).to_lower(), pct], "info")
		"tamed":
			var a: Array = arg
			owner_id = int(a[0])
			pet_name = String(a[1])
			display_name = pet_name
			team = Team.PLAYERS
			mode = MODE_FOLLOW
			if has_meta("wild"):
				remove_meta("wild")
			if model != null:
				ModelKit.burst(self, Vector3(0, hit_height, 0), 18, 0.25, 2.0, 0.06, Color(1.0, 0.75, 0.8), Color(1.0, 0.4, 0.5), 0.7)
			if me != null and owner_id == me.net_id:
				var rec := CharacterLife.of(me).add_pet(kind, pet_name, variant)
				uid = int(rec["uid"])
				Events.notify.emit("The %s is yours now. Press E near it for commands." % String(spec.get("name", kind)).to_lower(), "quest")
				Audio.play_ui("levelup")
				var vl := VillageLife.of(w)
				if vl != null:
					vl.request_pet_command(net_id, "uid", uid)
		"named":
			pet_name = String(arg)
			display_name = pet_name
		"mode":
			mode = MODES.get(String(arg), MODE_FOLLOW)
		"released":
			owner_id = 0
			team = Team.NEUTRAL
			mode = MODE_WILD


func _process(delta: float) -> void:
	if is_server():
		_update_plate()
		return
	interpolate(Net.server_time() if Net.has_method("server_time") else Time.get_ticks_msec() / 1000.0)
	var moved := (global_position - _last_pos) / maxf(delta, 0.0001)
	_last_pos = global_position
	_vis_speed = lerpf(_vis_speed, Vector2(moved.x, moved.z).length(), 1.0 - exp(-10.0 * delta))
	mode = anim & MODE_MASK
	if model != null:
		_present(_vis_speed)
	_update_plate()


func _present(speed: float) -> void:
	model.move_speed = speed
	if model is QuadrupedModel:
		(model as QuadrupedModel).sitting = mode == MODE_SIT
	elif model is FlyerModel:
		(model as FlyerModel).perched = not (mode == MODE_FOLLOW and tamed()) and mode != MODE_FLEE
	if anim_time != _shown_anim_time:
		_shown_anim_time = anim_time
		if mode == MODE_FIGHT:
			model.play("bite", 0.5)
			Audio.play("wolf_growl" if kind == "wild_dog" else "growl", center(), -10.0, 1.4)


var _plate_t := 0.0


func _update_plate() -> void:
	_plate_t -= get_process_delta_time()
	if _plate_t > 0.0 or _plate == null:
		return
	_plate_t = 0.4
	var w := world()
	if w == null or w.local_player == null or not tamed():
		_plate.visible = false
		return
	var d := w.local_player.global_position.distance_to(global_position)
	_plate.text = pet_name
	_plate.visible = d < 14.0 and w.local_dimension == dimension


func interact_prompt(p: Player) -> String:
	if tamed():
		return "%s: commands" % pet_name if p.net_id == owner_id else ""
	if accepts(p.held_item()):
		return "Feed the %s (%s)" % [String(spec["name"]).to_lower(), ItemDB.display_name(p.held_item())]
	return ""


func local_interact(p: Player) -> void:
	var w := world()
	var vl := VillageLife.of(w)
	if tamed():
		if p.net_id == owner_id:
			_open_commands()
		return
	var item := p.held_item()
	if not accepts(item) or not p.inventory.has(item) or vl == null:
		return
	p.inventory.remove_from_slot(p.inventory.selected, 1)
	Audio.play("pickup", center(), -10.0, 1.3)
	vl.request_feed(net_id, item)


func _open_commands() -> void:
	var title := "%s (%s)" % [pet_name, String(spec["name"]).to_lower()]
	var lines := PackedStringArray([_mood_line()])
	var opts: Array = [
		{"text": "Follow me.", "id": "pet:follow"},
		{"text": "Sit.", "id": "pet:sit"},
		{"text": "Stay here.", "id": "pet:stay"},
		{"text": "Give it a name...", "id": "pet:name"},
		{"text": "Set it free.", "id": "pet:release"},
		{"text": "Good %s." % ("bird" if is_bird() else ("dog" if kind == "wild_dog" else kind)), "id": "bye"},
	]
	Events.dialog_open.emit(self, title, lines, opts)


func _mood_line() -> String:
	match kind:
		"wild_dog":
			return "Tail going, ears up, waiting for a word." if mode != MODE_SIT else "Sitting, eyes on you, quivering to be let off."
		"cat":
			return "It blinks at you slowly. That is love, in cat."
		"raven":
			return "It tilts its head and croaks something that sounds like your name."
		"phoenix":
			return "Its feathers smoulder gold. The air around it is warm as a hearth."
	return "It watches you with bright, clever eyes."


func _on_choice(npc: Node, option_id: String) -> void:
	if npc != self or not option_id.begins_with("pet:"):
		return
	var cmd := option_id.trim_prefix("pet:")
	var w := world()
	var vl := VillageLife.of(w)
	Events.dialog_close.emit()
	if vl == null:
		return
	var life := CharacterLife.of(w.local_player)
	match cmd:
		"name":
			PetNameDialog.ask(pet_name, func(n: String) -> void:
				if n.strip_edges() == "":
					return
				vl.request_pet_command(net_id, "name", n.strip_edges().left(20))
				var rec := life.pet(uid)
				if not rec.is_empty():
					rec["name"] = n.strip_edges().left(20))
		"release":
			life.remove_pet(uid)
			vl.request_pet_command(net_id, "release", null)
			Events.notify.emit("%s trots off into the wild." % pet_name, "info")
		_:
			vl.request_pet_command(net_id, cmd, null)
			var rec := life.pet(uid)
			if not rec.is_empty():
				rec["mode"] = cmd
			Events.notify.emit({"follow": "%s follows you.", "sit": "%s sits.", "stay": "%s stays here."}[cmd] % pet_name, "info")
