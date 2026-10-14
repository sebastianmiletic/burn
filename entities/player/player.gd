class_name Player
extends Entity
## A player character. The local player reads input, moves itself with
## VoxelBody physics, mines, builds and fights; its state is replicated.
## Remote players are interpolated puppets of what their owners report.

const ACTIONS := ["", "attack", "attack2", "mine", "cast", "dodge", "hit", "die", "interact", "drink", "jump"]
const WALK_SPEED := 4.6
const SPRINT_SPEED := 7.4
const JUMP_VELOCITY := 9.2
const REACH := 5.5
const BASE_HEALTH := 100.0
const HEALTH_PER_RANK := 12.0

var is_local := false
var peer_id := 1
var inventory := Inventory.new()
var xp := 0
var rank := 0
var respawn_point := Vector3.ZERO
var respawn_dimension := 0
var offhand_light := false
var camera: PlayerCamera
var model: Node3D

var _input_enabled := true
var _move_speed := 0.0
var _visual_offset := 0.0
var _action := ""
var _action_time := 0.0
var _action_seq := 0
var _attack_hit_done := false
var _combo := 0
var _cooldowns := {}   # name -> [end_time, total]
var _last_damage_time := -100.0
var _dodge_dir := Vector3.ZERO
var _mine_target := Vector3i(1 << 30, 0, 0)
var _mine_progress := 0.0
var _mine_denied := Vector3i(1 << 30, 0, 0)
var _highlight: BlockHighlight
var _light: OmniLight3D
var _interact_target: Node = null
var _prev_remote_pos := Vector3.ZERO
var _remote_held := ""
var _remote_anim := -1
var _air_time := 0.0
var _fall_speed := 0.0
var _lava_tick := 0.0
var _footstep := 0.0


func _init() -> void:
	kind = "player"
	team = Team.PLAYERS
	hit_radius = 0.45
	hit_height = 1.8
	body.half_extents = Vector3(0.32, 0.9, 0.32)
	max_health = BASE_HEALTH
	health = max_health


func _ready() -> void:
	model = _make_model()
	add_child(model)
	_light = OmniLight3D.new()
	_light.position = Vector3(0.35, 1.5, 0.2)
	_light.light_color = Color(1.0, 0.68, 0.36)
	_light.omni_attenuation = 1.3
	_light.shadow_enabled = false
	_light.light_volumetric_fog_energy = 0.8
	add_child(_light)
	if is_local:
		camera = PlayerCamera.new()
		camera.target = self
		add_child(camera)
		_highlight = BlockHighlight.new()
		add_child(_highlight)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		inventory.changed.connect(_on_inventory_changed)
		_emit_stats()


func _make_model() -> Node3D:
	var colour := 0
	if Net.players.has(peer_id):
		colour = Net.players.keys().find(peer_id)
	return Models.player(colour, is_local)


func _model_call(method: String, args := []) -> void:
	if model != null and model.has_method(method):
		model.callv(method, args)


func set_input_enabled(on: bool) -> void:
	_input_enabled = on
	if is_local:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on and not dead else Input.MOUSE_MODE_VISIBLE


# --- Input -------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_local or not _input_enabled or dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera.look((event as InputEventMouseMotion).relative)
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			if Input.is_key_pressed(KEY_SHIFT):
				camera.zoom(-0.12)
			else:
				_select((inventory.selected + 2) % Inventory.HOTBAR)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if Input.is_key_pressed(KEY_SHIFT):
				camera.zoom(0.12)
			else:
				_select((inventory.selected + 1) % Inventory.HOTBAR)
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("slot_1"):
		_select(0)
	elif event.is_action_pressed("slot_2"):
		_select(1)
	elif event.is_action_pressed("slot_3"):
		_select(2)
	elif event.is_action_pressed("use"):
		_use()
	elif event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("ability_fire"):
		_cast_fireball()
	elif event.is_action_pressed("ability_burst"):
		_cast_burst()
	elif event.is_action_pressed("potion"):
		_drink_best_potion()
	elif event.is_action_pressed("dodge"):
		_dodge()


func _select(i: int) -> void:
	inventory.select(i)
	Events.hotbar_selected.emit(i)
	Audio.play_ui("ui_hover")


# --- Simulation ------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not is_local:
		_process_remote(delta)
		return
	var vw := voxels()
	_tick_cooldowns()
	if not dead:
		_move(delta, vw)
		_combat_update(delta)
		_mining_update(delta, vw)
		_find_interactable()
		_hazards(delta, vw)
		_regen(delta)
	else:
		body.velocity.x = 0.0
		body.velocity.z = 0.0
		body.step(self, vw, delta)
	_update_light(delta)
	_animate(delta)
	camera.follow(vw, global_position + Vector3(0, _visual_offset, 0), delta)


func _move(delta: float, vw: VoxelWorld) -> void:
	var input := Vector2.ZERO
	if _input_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_basis := Basis(Vector3.UP, camera.yaw)
	var wish := cam_basis * Vector3(input.x, 0, input.y)
	var sprint := _input_enabled and Input.is_action_pressed("sprint") and input.y < 0.0
	var speed := SPRINT_SPEED if sprint else WALK_SPEED
	if _action == "attack" or _action == "attack2" or _action == "cast":
		speed *= 0.45
	elif _action == "mine":
		speed *= 0.6
	elif _action == "drink":
		speed *= 0.5
	var target_vel := wish * speed
	if _action == "dodge":
		target_vel = _dodge_dir * 11.0 * (1.0 - _action_time / 0.5)
	var accel := 14.0 if body.on_floor else 4.0
	if body.in_liquid == Blocks.WATER:
		accel = 6.0
		target_vel *= 0.6
	var hv := Vector3(body.velocity.x, 0, body.velocity.z)
	hv = hv.lerp(target_vel, 1.0 - exp(-accel * delta))
	body.velocity.x = hv.x
	body.velocity.z = hv.z
	if _input_enabled and Input.is_action_pressed("jump"):
		if body.on_floor:
			body.velocity.y = JUMP_VELOCITY
			_start_action("jump", 0.4)
		elif body.in_liquid != 0:
			body.velocity.y = 4.0  # swim up
	var falling := body.velocity.y
	body.step(self, vw, delta)
	if body.stepped > 0.0:
		_visual_offset -= body.stepped
	_visual_offset = lerpf(_visual_offset, 0.0, 1.0 - exp(-delta * 14.0))
	# Fall damage.
	if not body.on_floor:
		_air_time += delta
		_fall_speed = minf(_fall_speed, falling)
	else:
		if _fall_speed < -17.0 and body.in_liquid == 0:
			receive_damage((-_fall_speed - 17.0) * 4.5, Vector3.INF, "fall", "the fall")
		_fall_speed = 0.0
		_air_time = 0.0
	_move_speed = hv.length()
	# Face where we're going; face the camera while fighting or mining.
	var face_dir := hv
	if _action in ["attack", "attack2", "cast", "mine"] or Input.is_action_pressed("attack"):
		face_dir = -cam_basis.z
	if face_dir.length() > 0.3:
		yaw = lerp_angle(yaw, atan2(face_dir.x, face_dir.z), 1.0 - exp(-delta * 12.0))
	rotation.y = yaw
	# Footsteps.
	if body.on_floor and _move_speed > 1.0:
		_footstep -= delta * _move_speed
		if _footstep <= 0.0:
			_footstep = 2.1
			Audio.play(_step_sound(vw), global_position, -8.0)


func _step_sound(vw: VoxelWorld) -> String:
	var b := vw.get_block(Vector3i((global_position - Vector3(0, 0.2, 0)).floor()))
	match b:
		Blocks.GRASS, Blocks.DIRT, Blocks.DRY_GRASS, Blocks.MUD, Blocks.LEAVES:
			return "step_grass"
		Blocks.PLANKS, Blocks.LOG, Blocks.THATCH:
			return "step_wood"
		Blocks.SNOW, Blocks.ICE:
			return "step_snow"
		Blocks.SAND, Blocks.ASH, Blocks.GRAVEL, Blocks.SOUL_SAND:
			return "step_sand"
	return "step_stone"


func _hazards(delta: float, vw: VoxelWorld) -> void:
	var feet := vw.get_block(Vector3i((global_position + Vector3(0, 0.2, 0)).floor()))
	if feet == Blocks.LAVA or body.in_liquid == Blocks.LAVA:
		_lava_tick -= delta
		if _lava_tick <= 0.0:
			_lava_tick = 0.5
			receive_damage(12.0, Vector3.INF, "fire", "lava")
	if global_position.y < -140.0:
		receive_damage(9999.0, Vector3.INF, "void", "the void")


func _regen(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_damage_time > 6.0 and health < max_health:
		heal_local(1.6 * delta)


# --- Actions -----------------------------------------------------------------------------

func _start_action(action: String, duration: float) -> void:
	_action = action
	_action_time = 0.0
	_action_seq = (_action_seq + 1) % 64
	anim = ACTIONS.find(action) + 16 * _action_seq
	anim_time = duration
	_attack_hit_done = false
	_model_call("play", [action, duration])


func _combat_update(delta: float) -> void:
	if _action != "":
		_action_time += delta
		if _action_time >= anim_time:
			_action = ""
	var holding := inventory.selected_item()
	var info := ItemDB.info(holding)
	var is_tool: bool = info.get("category", "") == "tool"
	if _input_enabled and Input.is_action_pressed("attack") and _action == "":
		var target := _block_target()
		if is_tool and not target.is_empty():
			pass  # mining handled in _mining_update
		else:
			_swing(info)
	if (_action == "attack" or _action == "attack2") and not _attack_hit_done and _action_time >= anim_time * 0.38:
		_attack_hit_done = true
		_resolve_swing(info)


func _swing(info: Dictionary) -> void:
	var speed := float(info.get("speed", 1.0))
	_combo = (_combo + 1) % 2
	_start_action("attack" if _combo == 0 else "attack2", 0.5 / speed)
	Audio.play("swing", global_position, -4.0, randf_range(0.9, 1.1))


func _resolve_swing(info: Dictionary) -> void:
	var reach := float(info.get("reach", 2.2))
	var base := float(info.get("damage", 3.0))
	var forward := Vector3(sin(yaw), 0, cos(yaw))
	var hits: Array = []
	for e in world().entities_near(center(), reach + 1.5, dimension):
		if e == self or e.team == Team.PLAYERS or e.team == Team.NEUTRAL:
			continue
		var to := e.center() - center()
		to.y = 0
		var dist := to.length() - e.hit_radius
		if dist > reach:
			continue
		if to.length() > 0.5 and forward.dot(to.normalized()) < 0.25:
			continue
		hits.append(e.net_id)
	if hits.is_empty():
		return
	var crit := randf() < 0.1
	var amount := base * (1.0 + rank * 0.06) * (1.75 if crit else 1.0)
	var kind := "crit" if crit else ("burn_hit" if info.has("burn") else "hit")
	world().request_attack(hits, amount, kind)
	Events.hit_stop.emit(0.05 if not crit else 0.09)
	camera.add_trauma(0.12 if not crit else 0.25)


func _block_target() -> Dictionary:
	var vw := voxels()
	var ray := camera.aim_ray()
	var origin: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	var hit := vw.raycast(origin, dir, camera.distance + REACH + 1.0)
	if hit.is_empty():
		return {}
	var eye := global_position + Vector3(0, 1.5, 0)
	if (Vector3(hit["pos"]) + Vector3(0.5, 0.5, 0.5)).distance_to(eye) > REACH:
		return {}
	return hit


func _mining_update(delta: float, vw: VoxelWorld) -> void:
	var info := inventory.selected_info()
	var target := _block_target()
	var holding_block := info.has("place_block")
	_highlight.show_target(target, info.get("category", "") == "tool" or holding_block)
	if target.is_empty() or info.get("category", "") != "tool" or not _input_enabled or not Input.is_action_pressed("attack"):
		if _mine_progress > 0.0:
			_mine_progress = 0.0
			_highlight.set_crack(0.0)
			Events.mining_progress.emit(-1.0)
		if _action == "mine":
			_action = ""
		return
	var pos: Vector3i = target["pos"]
	var block: int = target["block"]
	if pos != _mine_target:
		_mine_target = pos
		_mine_progress = 0.0
	if not Blocks.is_breakable(block):
		if _mine_denied != pos:
			_mine_denied = pos
			Events.notify.emit("%s cannot be broken." % Blocks.name_of(block), "warn")
		return
	if Blocks.tier(block) > int(info.get("mine_tier", 0)):
		if _mine_denied != pos:
			_mine_denied = pos
			Events.notify.emit("%s is too hard for your %s." % [Blocks.name_of(block), ItemDB.display_name(inventory.selected_item())], "warn")
			Audio.play("block_hit", Vector3(pos), -2.0, 0.7)
		return
	var break_time := maxf(0.08, Blocks.hardness(block) / float(info.get("mine_speed", 1.0)))
	if _action == "":
		_start_action("mine", 0.42)
		Audio.play("block_hit", Vector3(pos) + Vector3(0.5, 0.5, 0.5), -3.0, randf_range(0.85, 1.15))
	_mine_progress += delta / break_time
	_highlight.set_crack(_mine_progress)
	Events.mining_progress.emit(_mine_progress)
	if _mine_progress >= 1.0:
		_mine_progress = 0.0
		_highlight.set_crack(0.0)
		Events.mining_progress.emit(-1.0)
		world().request_set_block(pos, Blocks.AIR, dimension)
		Events.block_mined.emit(block, true)
		world().quests.on_event("mine", Blocks.name_of(block).to_lower())
		camera.add_trauma(0.05)


func _use() -> void:
	var id := inventory.selected_item()
	var info := ItemDB.info(id)
	if info.has("heal"):
		use_item_slot(inventory.selected)
		return
	if info.has("place_block"):
		var target := _block_target()
		if target.is_empty():
			return
		var pos: Vector3i = target["pos"] + target["normal"]
		if body.overlaps_block(global_position, pos):
			return
		world().request_set_block(pos, int(info["place_block"]), dimension)
		inventory.remove_from_slot(inventory.selected, 1)
		Audio.play("block_place", Vector3(pos) + Vector3(0.5, 0.5, 0.5))
		_start_action("interact", 0.25)


func _cast_fireball() -> void:
	if not _cooldown_ready("fireball") or _action == "dodge":
		return
	_trigger_cooldown("fireball", 4.0)
	_start_action("cast", 0.45)
	var ray := camera.aim_ray()
	var aim_point: Vector3 = ray[0] + ray[1] * 60.0
	var hit := voxels().raycast(ray[0], ray[1], 60.0)
	if not hit.is_empty():
		aim_point = hit["point"]
	var origin := global_position + Vector3(0, 1.45, 0) + Vector3(sin(yaw), 0, cos(yaw)) * 0.8
	var vel := (aim_point - origin).normalized() * 26.0
	world().replicator.request_projectile("player_fireball", origin, vel, 22.0 + rank * 3.0)


func _cast_burst() -> void:
	if not _cooldown_ready("burst"):
		return
	_trigger_cooldown("burst", 12.0)
	_start_action("cast", 0.5)
	world().view.flash = 0.6
	Audio.play("explosion", global_position, -3.0, 1.3)
	camera.add_trauma(0.35)
	var hits: Array = []
	for e in world().entities_near(global_position, 6.5, dimension, Team.MONSTERS):
		hits.append(e.net_id)
	if not hits.is_empty():
		world().replicator.request_attack(hits, 18.0 + rank * 2.5, "spell")


func _dodge() -> void:
	if not _cooldown_ready("dodge") or not body.on_floor:
		return
	_trigger_cooldown("dodge", 0.8)
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Basis(Vector3.UP, camera.yaw) * Vector3(input.x, 0, input.y)
	if dir.length() < 0.2:
		dir = -Vector3(sin(yaw), 0, cos(yaw))
	_dodge_dir = dir.normalized()
	yaw = atan2(_dodge_dir.x, _dodge_dir.z)
	invulnerable_until = Time.get_ticks_msec() / 1000.0 + 0.38
	_start_action("dodge", 0.5)
	Audio.play("swing", global_position, -6.0, 0.7)


func _drink_best_potion() -> void:
	if not _cooldown_ready("potion"):
		return
	for id: String in ["potion_greater", "potion_health", "bread"]:
		if inventory.has(id):
			if health >= max_health:
				Events.notify.emit("You are already at full health.", "info")
				return
			inventory.remove(id, 1)
			_drink(id)
			return
	Events.notify.emit("No potions.", "warn")


func _drink(id: String) -> void:
	_trigger_cooldown("potion", 2.0)
	_start_action("drink", 0.6)
	heal_local(float(ItemDB.info(id).get("heal", 0.0)))
	Events.damage_number.emit(center() + Vector3(0, 0.6, 0), int(ItemDB.info(id).get("heal", 0.0)), false, "heal")
	Audio.play("potion", global_position)


func _cooldown_ready(name_: String) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	return now >= float(_cooldowns.get(name_, [0.0, 0.0])[0])


func _trigger_cooldown(name_: String, seconds: float) -> void:
	_cooldowns[name_] = [Time.get_ticks_msec() / 1000.0 + seconds, seconds]


func _tick_cooldowns() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for n: String in _cooldowns:
		var c: Array = _cooldowns[n]
		Events.ability_cooldown.emit(n, maxf(0.0, float(c[0]) - now), float(c[1]))


# --- Interaction --------------------------------------------------------------------------------

func _find_interactable() -> void:
	var best: Node = null
	var best_score := 1e9
	var forward := Vector3(sin(camera.yaw), 0, cos(camera.yaw)) * -1.0
	for e in world().entities_near(global_position, 4.0, dimension):
		if e == self or not e.has_method("interact_prompt"):
			continue
		var prompt := String(e.call("interact_prompt", self))
		if prompt == "":
			continue
		var to := e.global_position - global_position
		var score := to.length() - forward.dot(to.normalized()) * 1.5
		if score < best_score:
			best_score = score
			best = e
	if best != _interact_target:
		_interact_target = best
		Events.interact_prompt.emit("" if best == null else "[E] " + String(best.call("interact_prompt", self)))


func _interact() -> void:
	if _interact_target != null and is_instance_valid(_interact_target):
		_interact_target.call("local_interact", self)
		_start_action("interact", 0.35)
		_interact_target = null
		Events.interact_prompt.emit("")


# --- Inventory API (used by the UI) -----------------------------------------------------------------

func held_item() -> String:
	return inventory.selected_item()


func give_item(id: String, count: int) -> void:
	var left := inventory.add(id, count)
	if count - left > 0:
		Events.item_picked_up.emit(id, count - left)
		Events.notify.emit("+%d %s" % [count - left, ItemDB.display_name(id)], "loot")
		Audio.play_ui("pickup")
	if left > 0:
		Events.notify.emit("Inventory full.", "warn")
		world().drop_item(global_position + Vector3(0, 1, 0), id, left, dimension)


func give_starting_kit() -> void:
	inventory.add("sword_rusty", 1)
	inventory.add("pickaxe_stone", 1)
	inventory.add("torch", 8)
	inventory.add("bread", 3)
	inventory.add("potion_health", 2)
	inventory.gold = 10
	inventory.select(0)


func use_item_slot(i: int) -> void:
	var s := inventory.get_slot(i)
	if s.is_empty():
		return
	var info := ItemDB.info(s["id"])
	if info.has("heal"):
		if not _cooldown_ready("potion"):
			return
		inventory.remove_from_slot(i, 1)
		_drink(s["id"])
	elif i >= Inventory.HOTBAR:
		# Move equipment into the selected hotbar slot.
		inventory.swap(i, inventory.selected)


func drop_slot(i: int) -> void:
	var s := inventory.get_slot(i)
	if s.is_empty():
		return
	inventory.slots[i] = {}
	inventory.changed.emit()
	world().drop_item(global_position + Vector3(sin(yaw), 1.2, cos(yaw)), s["id"], int(s["count"]), dimension)


func craft(recipe_id: String) -> bool:
	var r: Dictionary = ItemDB.RECIPES.get(recipe_id, {})
	if r.is_empty() or inventory.gold < int(r.get("gold", 0)):
		return false
	var inputs: Dictionary = r["inputs"]
	for item: String in inputs:
		if not inventory.has(item, int(inputs[item])):
			return false
	for item: String in inputs:
		inventory.remove(item, int(inputs[item]))
	inventory.gold -= int(r.get("gold", 0))
	give_item(recipe_id, int(r.get("count", 1)))
	Audio.play_ui("levelup")
	return true


func buy(item_id: String) -> bool:
	var price := int(ItemDB.SHOP.get(item_id, -1))
	if price < 0 or inventory.gold < price:
		return false
	inventory.gold -= price
	give_item(item_id, 1)
	Audio.play_ui("coin")
	return true


func sell_slot(i: int) -> bool:
	var s := inventory.get_slot(i)
	if s.is_empty():
		return false
	var value := int(ItemDB.info(s["id"]).get("value", 0))
	if value <= 0 or ItemDB.category(s["id"]) == "key":
		return false
	inventory.gold += value
	inventory.remove_from_slot(i, 1)
	Audio.play_ui("coin")
	return true


func _on_inventory_changed() -> void:
	Events.inventory_changed.emit()
	_model_call("set_held", [inventory.selected_item()])


# --- Health, XP, death ----------------------------------------------------------------------------

func receive_damage(amount: float, from: Vector3, kind: String, source_name: String) -> void:
	if dead:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < invulnerable_until:
		return
	health = maxf(0.0, health - amount)
	_last_damage_time = now
	Events.damage_number.emit(center() + Vector3(0, 0.7, 0), int(round(amount)), false, "player")
	Events.player_health_changed.emit(health, max_health)
	camera.add_trauma(clampf(amount / 40.0, 0.15, 0.6))
	world().view.tint = Color(1.0, 0.75, 0.7)
	get_tree().create_timer(0.15).timeout.connect(func() -> void: if world() != null: world().view.tint = Color.WHITE)
	_model_call("flash", [Color(1, 0.4, 0.3)])
	Audio.play("hurt", global_position)
	if from != Vector3.INF:
		var push := (global_position - from)
		push.y = 0
		body.velocity += push.normalized() * minf(8.0, amount * 0.25) + Vector3(0, 3, 0)
	if health <= 0.0:
		_die(source_name if source_name != "" else kind)
	elif _action == "":
		_start_action("hit", 0.3)


func heal_local(amount: float) -> void:
	health = minf(max_health, health + amount)
	Events.player_health_changed.emit(health, max_health)


func _die(cause: String) -> void:
	dead = true
	_start_action("die", 2.0)
	_model_call("set_dead", [true])
	Audio.play("death", global_position)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Events.player_died.emit(cause)


func request_respawn() -> void:
	if not dead:
		return
	dead = false
	health = max_health
	inventory.gold = int(inventory.gold * 0.9)
	if respawn_dimension != dimension:
		world().travel(respawn_dimension)
	global_position = respawn_point if respawn_point != Vector3.ZERO else world().default_spawn(dimension)
	body.velocity = Vector3.ZERO
	invulnerable_until = Time.get_ticks_msec() / 1000.0 + 3.0
	_model_call("set_dead", [false])
	_action = ""
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Events.player_health_changed.emit(health, max_health)
	Events.player_respawned.emit()


func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += amount
	var new_rank := ItemDB.rank_for_xp(xp)
	if new_rank > rank:
		rank = new_rank
		max_health = BASE_HEALTH + HEALTH_PER_RANK * rank
		health = max_health
		Events.rank_up.emit(rank, ItemDB.RANK_TITLES[rank])
		Events.notify.emit("Rank up: %s" % ItemDB.RANK_TITLES[rank], "rank")
		Audio.play_ui("levelup")
	_emit_stats()


func _emit_stats() -> void:
	Events.player_health_changed.emit(health, max_health)
	Events.xp_changed.emit(xp, rank, ItemDB.rank_progress(xp))


# --- Light and animation -----------------------------------------------------------------------------

func _update_light(delta: float) -> void:
	var held := inventory.selected_item() if is_local else _remote_held
	var holds_light := held == "torch" or held == "lantern"
	var dark := world() != null and (world().sky.darkness() > 0.4 or world().tracker.underground)
	if is_local:
		offhand_light = not holds_light and dark and (inventory.has("torch") or inventory.has("lantern"))
	var lit := holds_light or offhand_light
	var target_energy := 1.7 if lit else 0.25
	var target_range := 12.0 if lit else 4.5
	_light.light_energy = lerpf(_light.light_energy, target_energy * (0.92 + randf() * 0.16 if lit else 1.0), 1.0 - exp(-delta * 8.0))
	_light.omni_range = lerpf(_light.omni_range, target_range, 1.0 - exp(-delta * 4.0))
	_light.shadow_enabled = lit and is_local and int(Settings.get_value("graphics", "quality")) >= Settings.Quality.HIGH
	_model_call("set_offhand_light", [offhand_light])


func _animate(_delta: float) -> void:
	if model == null:
		return
	model.position.y = _visual_offset
	if "move_speed" in model:
		model.set("move_speed", _move_speed)
	if "grounded" in model:
		model.set("grounded", body.on_floor)


# --- Remote players -------------------------------------------------------------------------------------

func apply_remote_state(state: Array, time: float) -> void:
	dimension = int(state[0])
	_snapshots.append([time, state[1], state[2]])
	if _snapshots.size() > 12:
		_snapshots.pop_front()
	if int(state[3]) != _remote_anim:
		_remote_anim = int(state[3])
		var action: String = ACTIONS[clampi(_remote_anim % 16, 0, ACTIONS.size() - 1)]
		if action != "":
			_model_call("play", [action, float(state[4])])
	if String(state[5]) != _remote_held:
		_remote_held = String(state[5])
		_model_call("set_held", [_remote_held])
	health = float(state[6])
	max_health = float(state[7])
	var was_dead := dead
	dead = int(state[8]) == 1
	if dead != was_dead:
		_model_call("set_dead", [dead])
	display_name = String(state[9])
	offhand_light = bool(state[10])


func _process_remote(delta: float) -> void:
	var now: float = Net.server_time() if Net.has_method("server_time") else Time.get_ticks_msec() / 1000.0
	interpolate(now)
	_move_speed = lerpf(_move_speed, (global_position - _prev_remote_pos).length() / maxf(delta, 0.001), 1.0 - exp(-delta * 10.0))
	_prev_remote_pos = global_position
	_update_light(delta)
	_animate(delta)


# --- Save ---------------------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"name": display_name, "pos": global_position, "dim": dimension, "health": health, "xp": xp,
		"inventory": inventory.to_dict(), "respawn": respawn_point, "respawn_dim": respawn_dimension, "yaw": yaw}


func load_from(d: Dictionary) -> void:
	if d.is_empty():
		return
	dimension = int(d.get("dim", 0))
	global_position = d.get("pos", Vector3.ZERO)
	xp = int(d.get("xp", 0))
	rank = ItemDB.rank_for_xp(xp)
	max_health = BASE_HEALTH + HEALTH_PER_RANK * rank
	health = clampf(float(d.get("health", max_health)), 1.0, max_health)
	inventory.from_dict(d.get("inventory", {}))
	respawn_point = d.get("respawn", Vector3.ZERO)
	respawn_dimension = int(d.get("respawn_dim", 0))
	yaw = float(d.get("yaw", 0.0))
	if camera != null:
		camera.yaw = yaw + PI
	_emit_stats()
