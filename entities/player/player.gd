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
## Role (Roles), outfit (Skins), XP per role (xp is the current role's pool),
## books read (knowledge ids) and role kits already handed out. See PlayerArcana.
var role := Roles.DEFAULT
var skin := Skins.DEFAULT
var role_xp := {}
var knowledge := {}
var kits_given := {}
var arcana: PlayerArcana

var _input_enabled := true
## Session-only inspection mode. Never inherited by a saved character.
var creative := false
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
var _remote_velocity := Vector3.ZERO
var _remote_held := ""
var _remote_anim := -1
var _air_time := 0.0
var _fall_speed := 0.0
var _lava_tick := 0.0
var _footstep := 0.0
var _sprinting := false
var _coyote := 0.0
## Multiplayer without shrine respawns: down but not out, waiting for a teammate.
var downed := false
var bleed_left := 0.0
const BLEED_TIME := 90.0
const REVIVE_TIME := 3.0
var _revive_target: Player
var _revive_t := 0.0
var _jump_buffer := 1.0
var _was_on_floor := true
var _rustle := 0.0
var _model_steps := false   # the model reports foot plants (footstep signal)

# --- Swimming and (hidden) breath ----------------------------------------------------
const SWIM_SPEED := 3.0
const SWIM_SPRINT := 4.4
const SWIM_VERTICAL := 2.6
## Feet this far below the water surface float (chest-deep); treading keeps the eyes just above it.
const SWIM_DEPTH := 1.2
const TREAD_DEPTH := 1.42
## Seconds the head can stay under before blacking out (never shown to the player).
const BREATH_TIME := 36.0
## The last seconds of air: vision closes in from the edges, blurs, sound muffles, the heart pounds.
const BREATH_FADE := 12.0
var swimming := false
var head_under := false
## Water surface height above the feet column (-INF when not in water).
var water_surface := -INF
var air := BREATH_TIME
## 0..1: how close to blacking out (drives UnderwaterFx).
var suffocation := 0.0
## Audio muffling requested by the player (LocationTracker combines it with caves).
var audio_muffle := 0.0
var _drown_pending := false
var _heartbeat := 0.0
var _vault_cd := 0.0
var _remote_swim := false
var _water_fx: UnderwaterFx


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
	if model.has_signal("footstep"):
		_model_steps = true
		model.connect("footstep", _on_model_footstep)
	if "terrain_probe" in model:
		model.set("terrain_probe", func(p: Vector3) -> float: return HumanoidModel.ground_probe(self, p))
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
		_apply_view.call_deferred()
		var vm := Viewmodel.new()
		vm.player = self
		camera.add_child(vm)
		_water_fx = UnderwaterFx.new()
		_water_fx.player = self
		add_child(_water_fx)
		var look := LookInspector.new()
		look.player = self
		add_child(look)
		_highlight = BlockHighlight.new()
		add_child(_highlight)
		arcana = PlayerArcana.new()
		arcana.player = self
		add_child(arcana)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		inventory.changed.connect(_on_inventory_changed)
		_emit_stats()


func _make_model() -> Node3D:
	var colour := 0
	if Net.players.has(peer_id):
		colour = Net.players.keys().find(peer_id)
	if not is_local:
		var look := SpellNet.look_of(peer_id)
		if not look.is_empty():
			role = String(look[0])
			skin = String(look[1])
	if skin != Skins.DEFAULT and Skins.SKINS.has(skin):
		return HumanoidModel.new(Skins.style(skin, colour, is_local))
	return Models.player(colour, is_local)


## Role and outfit changed (lobby choice, or a remote player's announcement).
func set_look(new_role: String, new_skin: String) -> void:
	if Roles.is_role(new_role):
		role = new_role
	if new_skin == skin or not Skins.SKINS.has(new_skin) or model == null:
		skin = new_skin if Skins.SKINS.has(new_skin) else skin
		return
	skin = new_skin
	var old := model
	model = _make_model()
	add_child(model)
	if model.has_signal("footstep"):
		_model_steps = true
		model.connect("footstep", _on_model_footstep)
	if "terrain_probe" in model:
		model.set("terrain_probe", func(p: Vector3) -> float: return HumanoidModel.ground_probe(self, p))
	old.queue_free()
	_model_call("set_held", [held_item()])
	_apply_view()
	if dead:
		_model_call("set_dead", [true])


## First person hides the head and hood from the inside (you still see your
## body, arms and weapon); third person shows the whole character.
func _apply_view() -> void:
	if camera == null:
		return
	_model_call("set_first_person", [camera.first_person])


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
	if arcana != null and arcana.handle_input(event):
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
	if event.is_action_pressed("toggle_view"):
		camera.first_person = not camera.first_person
		Settings.set_value("gameplay", "first_person", camera.first_person)
		_apply_view()
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
	# Streaming/setup may relocate an embedded spawn. Accumulating fall speed
	# before play starts can turn that correction into a lethal landing.
	if is_local and Game.state == Game.State.LOADING:
		return
	if not is_local:
		_process_remote(delta)
		return
	var vw := voxels()
	_tick_cooldowns()
	_revive_update(delta)
	if dead and downed:
		bleed_left -= delta
		if bleed_left <= 0.0:
			Events.notify.emit("You bled out and rise at your shrine.", "warn")
			request_respawn(true)
	_water_update(vw)
	_breath_update(delta)
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
	camera.move_speed = _move_speed
	camera.grounded = body.on_floor
	camera.follow(vw, global_position + Vector3(0, _visual_offset, 0), delta)


func _move(delta: float, vw: VoxelWorld) -> void:
	var boots: Dictionary = inventory.equipment.get("feet", {})
	body.climb_step = 1.15 if boots.get("id", "") == "hiking_boots" or creative else VoxelBody.MAX_STEP
	var input := Vector2.ZERO
	if _input_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_basis := Basis(Vector3.UP, camera.yaw)
	var wish := cam_basis * Vector3(input.x, 0, input.y)
	var sprint := _input_enabled and Settings.action_held("sprint") and input.y < 0.0
	_sprinting = sprint and body.on_floor
	var speed := (SPRINT_SPEED if sprint else WALK_SPEED) * (arcana.speed_mult() if arcana != null else 1.0)
	if _action == "attack" or _action == "attack2" or _action == "cast":
		speed *= 0.45
	elif _action == "mine":
		speed *= 0.6
	elif _action == "drink":
		speed *= 0.5
	var target_vel := wish * speed
	if _action == "dodge":
		target_vel = _dodge_dir * 11.0 * (1.0 - _action_time / 0.5) * (arcana.dash_mult() if arcana != null else 1.0)
	# Snappy on the ground (quicker to stop than to start), some steering in the air.
	var accel := (18.0 if target_vel.length() < 0.1 else 13.0) if body.on_floor else 5.0
	if body.in_liquid == Blocks.WATER:
		accel = 6.0
		target_vel *= 0.6
	var hv := Vector3(body.velocity.x, 0, body.velocity.z)
	body.swimming = swimming
	if swimming:
		_swim(delta, input, sprint)
		hv = Vector3(body.velocity.x, 0, body.velocity.z)
	else:
		hv = hv.lerp(target_vel, 1.0 - exp(-accel * delta))
		body.velocity.x = hv.x
		body.velocity.z = hv.z
	# Jump buffering (a press just before landing still counts) and coyote time
	# (a jump just after running off an edge still works); holding the key
	# doesn't bunny-hop.
	_coyote = 0.0 if body.on_floor else _coyote + delta
	_jump_buffer += delta
	if _input_enabled and Input.is_action_just_pressed("jump"):
		_jump_buffer = 0.0
	if swimming:
		pass  # swim() handles up/down
	elif _input_enabled and _jump_buffer < 0.14 and (body.on_floor or _coyote < 0.12) and body.velocity.y <= 0.5 and body.in_liquid == 0:
		_jump_buffer = 1.0
		_coyote = 1.0
		body.velocity.y = JUMP_VELOCITY
		_signal_anim("jump", 0.4)
		_model_call("on_jump")
		Audio.play("jump", global_position, -6.0, randf_range(0.92, 1.08))
	elif _input_enabled and body.in_liquid != 0 and Input.is_action_pressed("jump"):
		body.velocity.y = 4.0  # swim up
	elif arcana != null and _input_enabled and _jump_buffer == 0.0 and not body.on_floor and arcana.try_air_jump():
		_jump_buffer = 1.0
	if arcana != null:
		arcana.movement(delta)
	var falling := body.velocity.y
	body.step(self, vw, delta)
	if body.stepped > 0.0:
		_visual_offset -= body.stepped
	_visual_offset = lerpf(_visual_offset, 0.0, 1.0 - exp(-delta * 14.0))
	# Fall damage (not while waiting for the world to stream in, and deep water breaks any fall).
	if not vw.is_area_loaded(global_position) or swimming:
		_fall_speed = 0.0
		_air_time = 0.0
	elif not body.on_floor:
		_air_time += delta
		_fall_speed = minf(_fall_speed, falling)
	else:
		if not _was_on_floor and _air_time > 0.12:
			_land(-_fall_speed, vw)
		if _fall_speed < -17.0 and body.in_liquid == 0 and not (arcana != null and arcana.no_fall_damage()):
			receive_damage((-_fall_speed - 17.0) * 4.5, Vector3.INF, "fall", "the fall")
		_fall_speed = 0.0
		_air_time = 0.0
	_was_on_floor = body.on_floor
	_move_speed = hv.length()
	# Face where we're going; face the camera while fighting or mining.
	var face_dir := hv
	if _action in ["attack", "attack2", "cast", "mine"] or Settings.action_held("attack"):
		face_dir = -cam_basis.z
	if camera.first_person and _action != "dodge":
		# First person: the body always faces where you look.
		yaw = camera.yaw + PI
	elif face_dir.length() > 0.3:
		yaw = lerp_angle(yaw, atan2(face_dir.x, face_dir.z), 1.0 - exp(-delta * 12.0))
	rotation.y = yaw
	# Footsteps (timed by the model's feet when it reports them).
	if body.on_floor and _move_speed > 1.0:
		if not _model_steps:
			_footstep -= delta * _move_speed
			if _footstep <= 0.0:
				_footstep = 2.1
				_on_model_footstep(0.9 if _sprinting else 0.5)
		# Brushing through tall grass.
		_rustle -= delta * _move_speed
		if _rustle <= 0.0:
			_rustle = 3.5
			var under := ground_block(vw)
			if under == Blocks.GRASS or under == Blocks.DRY_GRASS:
				Audio.play("rustle", global_position, -16.0 + minf(_move_speed, 7.0), randf_range(0.85, 1.15))


# --- Swimming ------------------------------------------------------------------------

## Height of the water surface over the body's column (top of the highest
## connected water block, as the liquid mesher draws it), or -INF.
static func water_surface_at(vw: VoxelWorld, feet: Vector3) -> float:
	var y := floori(feet.y + 0.05)
	var found := false
	for i in 2:
		if vw.get_block(Vector3i(floori(feet.x), y - i, floori(feet.z))) == Blocks.WATER:
			found = true
			y -= i
			break
	if not found:
		var mid := vw.get_block(Vector3i(floori(feet.x), floori(feet.y + 1.0), floori(feet.z)))
		if mid != Blocks.WATER:
			return -INF
		y = floori(feet.y + 1.0)
	var top := y
	while top < y + 24 and vw.get_block(Vector3i(floori(feet.x), top + 1, floori(feet.z))) == Blocks.WATER:
		top += 1
	# Covered water (a flooded tunnel) is full to its ceiling; open water's
	# drawn surface sits a little below the block top.
	var above := vw.get_block(Vector3i(floori(feet.x), top + 1, floori(feet.z)))
	return float(top) + (0.88 if above == Blocks.AIR or above < 0 else 1.0)


func _water_update(vw: VoxelWorld) -> void:
	if vw == null:
		return
	water_surface = water_surface_at(vw, global_position)
	var depth := water_surface - global_position.y if water_surface > -INF else 0.0
	var was := swimming
	if dead:
		swimming = false
	elif swimming:
		swimming = depth > SWIM_DEPTH - 0.35  # hysteresis: wade out on the shallows
	else:
		swimming = depth > SWIM_DEPTH and not (body.on_floor and depth < SWIM_DEPTH + 0.25)
	head_under = water_surface > -INF and global_position.y + 1.56 < water_surface
	if swimming and not was:
		var impact := -minf(body.velocity.y, _fall_speed)
		Audio.play("splash_big" if impact > 9.0 else ("splash" if impact > 3.0 else "splash_small"), global_position + Vector3(0, 1.0, 0), -4.0 + minf(impact, 14.0) * 0.3)
		body.velocity.y *= 0.35
		if impact > 9.0 and camera != null:
			camera.add_trauma(0.12)


## Breaststroke where you look: forward follows the view (pitch included),
## jump rises, dodge (Ctrl) dives; with no input the body floats up to tread
## water with the eyes just above the surface.
func _swim(delta: float, input: Vector2, sprint: bool) -> void:
	var look := Basis(Vector3.UP, camera.yaw) * Basis(Vector3.RIGHT, camera.pitch)
	var wish := look * Vector3(input.x, 0, input.y)
	var speed := (SWIM_SPRINT if sprint else SWIM_SPEED) * armour_swim_factor() \
			* (1.0 + float(ItemDB.info(held_item()).get("swim_speed", 0.0)) + (arcana.swim_bonus() if arcana != null else 0.0))
	var target := wish * speed
	var up := 0.0
	if _input_enabled and Input.is_action_pressed("jump"):
		up += 1.0
	if _input_enabled and Input.is_action_pressed("dodge"):
		up -= 1.0
	var tread_y := water_surface - TREAD_DEPTH
	if up != 0.0:
		target.y = clampf(target.y + up * SWIM_VERTICAL, -speed, speed)
		if up > 0.0 and global_position.y > tread_y - 0.05:
			target.y = minf(target.y, (tread_y + 0.15 - global_position.y) * 4.0 + 0.3)
	elif absf(wish.y) < 0.25:
		# Buoyancy: drift up, then hold at treading depth (bobbing gently).
		var bob := sin(Time.get_ticks_msec() / 1000.0 * 1.7) * 0.04
		target.y += clampf((tread_y + bob - global_position.y) * 2.2, -1.4, 0.9)
	body.velocity = body.velocity.lerp(target, 1.0 - exp(-3.2 * delta))
	# Out onto a ledge or shore: swimming into a bank at the surface hauls you up.
	_vault_cd -= delta
	if body.hit_wall and input.y < -0.3 and _vault_cd <= 0.0 and global_position.y > water_surface - 1.75:
		_vault_cd = 0.6
		body.velocity.y = 6.4
		Audio.play("splash_small", global_position + Vector3(0, 1.2, 0), -6.0)


## Heavy armour drags in the water (up to 30 % slower).
func armour_swim_factor() -> float:
	var total := 0.0
	for slot: String in inventory.equipment:
		var it: Dictionary = inventory.equipment[slot]
		if not it.is_empty():
			total += float(ItemDB.info(String(it.get("id", ""))).get("armor", 0.0))
	return 1.0 - clampf(total / 150.0, 0.0, 0.3)


## Seconds of air the body holds (water-breathing gear adds to it, if any exists).
func breath_capacity() -> float:
	var bonus := 0.0
	for slot: String in inventory.equipment:
		var it: Dictionary = inventory.equipment[slot]
		if not it.is_empty():
			bonus += float(ItemDB.info(String(it.get("id", ""))).get("water_breathing", 0.0))
	return BREATH_TIME * (1.0 + bonus)


## The Tideborn helm or a Tidebreath draught: the sea's air is yours.
func breathes_water() -> bool:
	if inventory.buff_active("water_breathing"):
		return true
	for slot: String in inventory.equipment:
		var it: Dictionary = inventory.equipment[slot]
		if not it.is_empty() and ItemDB.info(String(it.get("id", ""))).get("water_breathing", 0.0) is bool \
				and bool(ItemDB.info(String(it.get("id", ""))).get("water_breathing")):
			return true
	return false


## Hidden breath: nothing on the HUD. Running low only shows as the screen
## closing in; surfacing recovers gradually.
func _breath_update(delta: float) -> void:
	var cap := breath_capacity()
	if head_under and not dead and not creative and not breathes_water():
		air = maxf(0.0, air - delta)
	else:
		air = minf(cap, air + delta * 5.0)
	var want := clampf(1.0 - air / BREATH_FADE, 0.0, 1.0)
	if dead and not head_under:
		want = 0.0
	# Slow both ways: it creeps in, and lifts over a few breaths.
	suffocation = move_toward(suffocation, want, delta * (0.25 if want > suffocation else 0.3))
	audio_muffle = maxf(1.0 if head_under else 0.0, suffocation)
	if suffocation > 0.25 and not dead:
		_heartbeat -= delta
		if _heartbeat <= 0.0:
			_heartbeat = lerpf(1.1, 0.55, suffocation)
			var vol := lerpf(-20.0, -6.0, suffocation)
			Audio.play("land", global_position, vol, 0.42)
			get_tree().create_timer(0.17).timeout.connect(func() -> void:
				if is_instance_valid(self):
					Audio.play("land", global_position, vol - 4.0, 0.38))
	if air <= 0.0 and suffocation >= 0.999 and not dead and not _drown_pending:
		_drown_pending = true
		var w := world()
		if w != null and w.replicator != null:
			w.replicator.request_drown_outcome()
		else:
			on_drown_outcome(false)


## The host decided: the sea keeps you (death, with the usual multiplayer
## downed rules) or, rarely, gives you back on Ogygia.
func on_drown_outcome(rescued: bool) -> void:
	_drown_pending = false
	if dead:
		return
	if rescued:
		air = breath_capacity()
		suffocation = 1.0  # wake from the dark
		Ogygia.arrive(world())
	else:
		_die("Drowned in the dark water.")


func reset_breath() -> void:
	air = breath_capacity()
	suffocation = 0.0
	_drown_pending = false


func _on_model_footstep(strength: float) -> void:
	var vw := voxels()
	if vw == null or not body.on_floor:
		return
	var vol := lerpf(-12.0, -4.0, clampf(strength, 0.0, 1.0))
	Audio.play(_step_sound(vw), global_position, vol, randf_range(0.92, 1.08))
	if _sprinting and strength > 0.7:
		Audio.play("step_run", global_position, vol - 6.0, randf_range(0.9, 1.1))


## Block under the feet (the smooth surface can sit up to half a block above its voxel).
func ground_block(vw: VoxelWorld) -> int:
	var b := vw.get_block(Vector3i((global_position - Vector3(0, 0.2, 0)).floor()))
	if b <= 0 or not Blocks.is_solid(b):
		b = vw.get_block(Vector3i((global_position - Vector3(0, 0.75, 0)).floor()))
	return b


func _land(impact: float, vw: VoxelWorld) -> void:
	_model_call("on_land", [impact])
	if impact > 12.0:
		Audio.play("land_heavy", global_position, -2.0)
		camera.add_trauma(clampf((impact - 12.0) * 0.03, 0.05, 0.4))
	elif impact > 4.0:
		Audio.play("land", global_position, -9.0 + minf(impact, 12.0) * 0.4, randf_range(0.92, 1.08))
		Audio.play(_step_sound(vw), global_position, -8.0)
	if camera.has_method("land"):
		camera.call("land", impact)


func _step_sound(vw: VoxelWorld) -> String:
	var b := ground_block(vw)
	if body.in_liquid == Blocks.WATER:
		return "water_wade"
	match Blocks.sound_family(b):
		"dirt":
			return "step_grass" if b == Blocks.GRASS or b == Blocks.DRY_GRASS else "step_dirt"
		"wood":
			return "step_wood"
		"snow":
			return "step_snow"
		"sand":
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

## Play an animation everywhere (model + replicated id) without occupying the
## action slot, so e.g. jumping never blocks attacking.
func _signal_anim(action: String, duration: float) -> void:
	_action_seq = (_action_seq + 1) % 64
	anim = ACTIONS.find(action) + 16 * _action_seq
	_model_call("play", [action, duration])


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
	if arcana != null and arcana.weapon_update(delta, info):
		return
	if _input_enabled and Settings.action_held("attack") and _action == "":
		var target := _block_target()
		if is_tool and not target.is_empty():
			pass  # mining handled in _mining_update
		else:
			_swing(info)
	if (_action == "attack" or _action == "attack2") and not _attack_hit_done and _action_time >= anim_time * 0.38:
		_attack_hit_done = true
		_resolve_swing(info)


func _swing(info: Dictionary) -> void:
	var speed := float(inventory.attack_stats()["speed"])
	_combo = (_combo + 1) % 2
	_start_action("attack" if _combo == 0 else "attack2", 0.5 / speed)
	var heavy := speed < 0.9 or float(info.get("damage", 3.0)) >= 14.0
	var blunt := String(info.get("weapon", "")) in ["hammer", "mace", "club"]
	Audio.play("swing_blunt" if blunt else ("swing_heavy" if heavy else "swing_light"), global_position, -4.0, randf_range(0.9, 1.1))


func _resolve_swing(info: Dictionary) -> void:
	var a := inventory.attack_stats()
	var reach := float(a["reach"])
	var base := float(a["damage"])
	var forward := Vector3(sin(yaw), 0, cos(yaw))
	var hits: Array = []
	var pvp_hits: Array = []
	for e in world().entities_near(center(), reach + 1.5, dimension):
		if e == self or e.team == Team.NEUTRAL or (e.team == Team.PLAYERS and not PvpArena.active()):
			continue
		var to := e.center() - center()
		to.y = 0
		var dist := to.length() - e.hit_radius
		if dist > reach:
			continue
		if to.length() > 0.5 and forward.dot(to.normalized()) < 0.25:
			continue
		if e.team == Team.PLAYERS:
			pvp_hits.append(e.net_id)
		else:
			hits.append(e.net_id)
	if hits.is_empty() and pvp_hits.is_empty():
		return
	inventory.buffs.erase("invisible")   # striking breaks the Veil
	var crit := randf() < float(a["crit"])
	var mult := arcana.power_mult(String(info.get("kind", ""))) if arcana != null else 1.0 + rank * 0.06
	var amount := base * mult * (1.75 if crit else 1.0)
	var kind := "crit" if crit else ("burn_hit" if float(a["burn"]) > 0.0 else "hit")
	if not hits.is_empty():
		world().request_attack(hits, amount, kind)
	if not pvp_hits.is_empty():
		SpellNet.request_pvp_hits(self, pvp_hits, amount)
	Events.hit_stop.emit(0.05 if not crit else 0.09)
	camera.add_trauma(0.12 if not crit else 0.25)


func _block_target() -> Dictionary:
	var vw := voxels()
	var ray := camera.aim_ray()
	var origin: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	var hit := vw.raycast(origin, dir, (0.2 if camera.first_person else camera.distance) + REACH + 1.0)
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
	if target.is_empty() or info.get("category", "") != "tool" or not _input_enabled or not Settings.action_held("attack"):
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
	var break_time := ItemDB.mine_time(inventory.selected_item(), block)
	if break_time < 0.0:
		if _mine_denied != pos:
			_mine_denied = pos
			Events.notify.emit("%s is too hard for your %s." % [Blocks.name_of(block), ItemDB.display_name(inventory.selected_item())], "warn")
			Audio.play("pick_stone", Vector3(pos), -2.0, 0.7)
		return
	break_time = maxf(0.08, break_time)
	if Blocks.is_smooth(block):
		_sculpt_strike(target, block)
		return
	if _action == "":
		_start_action("mine", 0.42)
		var fam := Blocks.sound_family(block)
		var snd := "pick_wood" if fam == "wood" else ("pick_dirt" if fam in ["dirt", "sand", "snow"] else "pick_stone")
		var point: Vector3 = target.get("point", Vector3(pos) + Vector3(0.5, 0.5, 0.5))
		Audio.play(snd, point, -3.0, randf_range(0.85, 1.15))
		var w := world()
		if w.fx != null:
			w.fx.debris(point, target.get("surface_normal", Vector3.UP), Blocks.color(block), false)
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
	elif Blocks.is_trunk(block) and _action == "mine" and _action_time < delta * 1.5:
		# Each axe bite shakes leaves out of the crown.
		var vw2 := voxels()
		if vw2.flora != null and vw2.flora.has_method("shake"):
			var bottom := pos
			while vw2.get_block(bottom - Vector3i(0, 1, 0)) == block:
				bottom.y -= 1
			var info2 := WorldGen.tree_info(block, bottom)
			vw2.flora.call("shake", world(), Vector3(bottom) + Vector3(0.5, 0, 0.5), int(info2[0]), int(info2[2]))


const STRIKE_TIME := 0.42


## Natural ground is carved, not broken: every pickaxe swing takes a rounded
## bite out of the surface where it lands (the server decides what comes off).
func _sculpt_strike(target: Dictionary, block: int) -> void:
	if _mine_progress > 0.0:
		_mine_progress = 0.0
		_highlight.set_crack(0.0)
		Events.mining_progress.emit(-1.0)
	if _action != "":
		return
	_start_action("mine", STRIKE_TIME)
	var item := inventory.selected_item()
	var tier := int(ItemDB.info(item).get("mine_tier", 1))
	var point: Vector3 = target.get("point", Vector3(target["pos"]) + Vector3(0.5, 0.5, 0.5))
	var n: Vector3 = target.get("surface_normal", Vector3.UP)
	var fam := Blocks.sound_family(block)
	var snd := "pick_dirt" if fam in ["dirt", "sand", "snow"] else "pick_stone"
	Audio.play(snd, point, -3.0, randf_range(0.85, 1.15))
	var w := world()
	if w.fx != null:
		w.fx.debris(point, n, Blocks.color(block), false)
	_highlight.flash_crack(point, n)
	# Bite centre sits just inside the surface so each strike digs in.
	w.replicator.request_dig(point - n * 0.25, 0.8 + tier * 0.06, STRIKE_TIME, item, dimension)
	camera.add_trauma(0.035)


func _use() -> void:
	var id := inventory.selected_item()
	var info := ItemDB.info(id)
	if arcana != null and arcana.use_item(id):
		return
	if info.has("heal") or info.has("buff") or info.has("mana"):
		use_item_slot(inventory.selected)
		return
	if info.has("place_station"):
		var target := _block_target()
		if target.is_empty():
			return
		var p := Vector3(target["pos"] + target["normal"]) + Vector3(0.5, 0.0, 0.5)
		var vw := voxels()
		var g := vw.ground_below(p.x, p.y + 1.0, p.z, 2.5)
		if absf(g) < 1e6:
			p.y = g
		world().request_place_station(String(info["place_station"]), p, yaw + PI, dimension)
		world().quests.on_event("place", id)
		inventory.remove_from_slot(inventory.selected, 1)
		Audio.play("block_place", p)
		_start_action("interact", 0.25)
		return
	if info.has("place_block"):
		var target := _block_target()
		if target.is_empty():
			return
		var block := int(info["place_block"])
		if Blocks.is_smooth(block):
			# Ground materials are packed onto the surface, not stacked as cubes.
			var n: Vector3 = target.get("surface_normal", Vector3(target["normal"]))
			var point: Vector3 = target.get("point", Vector3(target["pos"]) + Vector3(0.5, 0.5, 0.5)) + n * 0.45
			if point.distance_to(center()) < 1.4:
				return
			world().replicator.request_fill(point, 0.75, block, dimension)
			inventory.remove_from_slot(inventory.selected, 1)
			Audio.play("pick_dirt", point, -4.0, 0.8)
			_start_action("interact", 0.3)
			return
		if Blocks.family(block) != Blocks.Family.SMALL:
			return  # crisp building blocks are no longer placed by hand
		var pos: Vector3i = target["pos"] + target["normal"]
		if body.overlaps_block(global_position, pos):
			return
		world().request_set_block(pos, block, dimension)
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
	var air := not body.on_floor
	if not _cooldown_ready("dodge") or (air and not (arcana != null and arcana.can_air_dash())):
		return
	if air:
		arcana.used_air_dash()
		body.velocity.y = maxf(body.velocity.y, 1.5)
	_trigger_cooldown("dodge", 0.6 if arcana != null and arcana.dash_mult() > 1.0 else 0.8)
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Basis(Vector3.UP, camera.yaw) * Vector3(input.x, 0, input.y)
	if dir.length() < 0.2:
		dir = -Vector3(sin(yaw), 0, cos(yaw))
	_dodge_dir = dir.normalized()
	yaw = atan2(_dodge_dir.x, _dodge_dir.z)
	invulnerable_until = Time.get_ticks_msec() / 1000.0 + 0.38
	_start_action("dodge", 0.5)
	Audio.play("roll", global_position, -5.0, randf_range(0.92, 1.08))


func _drink_best_potion() -> void:
	if not _cooldown_ready("potion"):
		return
	var id := inventory.best_heal_item()
	if id != "":
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
	var h := inventory.apply_consumable(id)
	if h > 0.0:
		heal_local(h)
		Events.damage_number.emit(center() + Vector3(0, 0.6, 0), int(h), false, "heal")
	if arcana != null:
		arcana.on_drink(id)
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
	return inventory.selected_item() if is_local else _remote_held


func give_item(id: String, count: int) -> void:
	var left := inventory.add(id, count)
	if count - left > 0:
		if is_local and world() != null:
			world().quests.on_event("gather", id, count - left)
		Events.item_picked_up.emit(id, count - left)
		Events.notify.emit("+%d %s" % [count - left, ItemDB.display_name(id)], "loot")
		Audio.play_ui("pickup")
	if left > 0:
		Events.notify.emit("Inventory full.", "warn")
		world().drop_item(global_position + Vector3(0, 1, 0), id, left, dimension)


func give_starting_kit() -> void:
	var r: Dictionary = Roles.ROLES.get(role, Roles.ROLES[Roles.DEFAULT])
	for entry: Array in r["kit"]:
		inventory.add(String(entry[0]), int(entry[1]))
	inventory.gold = int(r.get("gold", 10))
	kits_given[role] = true
	inventory.select(0)


## A character entering as a role it never played gets that role's weapon and
## ammunition once (not the whole starting kit again).
func give_role_kit_once() -> void:
	if kits_given.has(role):
		return
	kits_given[role] = true
	for entry: Array in Roles.ROLES.get(role, Roles.ROLES[Roles.DEFAULT])["kit"]:
		var id := String(entry[0])
		if id in ["pickaxe_stone", "torch", "bread", "potion_health"] or (int(ItemDB.info(id).get("stack", 1)) == 1 and inventory.has(id)):
			continue
		give_item(id, int(entry[1]))


## Rank per role (the current role from xp, the others from role_xp).
func role_ranks() -> Dictionary:
	var out := {}
	for r: String in Roles.ORDER:
		out[r] = ItemDB.rank_for_xp(xp if r == role else int(role_xp.get(r, 0)))
	return out


func _max_health_for(r: int) -> float:
	return BASE_HEALTH + HEALTH_PER_RANK * r + float(Roles.perks(role, r)["health"])


## Switch the played role (lobby choice): XP pools swap, rank and stats follow.
func set_role(new_role: String) -> void:
	if not Roles.is_role(new_role):
		return
	role_xp[role] = xp
	role = new_role
	xp = int(role_xp.get(role, 0))
	rank = ItemDB.rank_for_xp(xp)
	max_health = _max_health_for(rank)
	health = clampf(health, 1.0, max_health)
	if arcana != null:
		arcana.on_rank_changed()
	_emit_stats()


func use_item_slot(i: int) -> void:
	var s := inventory.get_slot(i)
	if s.is_empty():
		return
	var info := ItemDB.info(s["id"])
	if arcana != null and arcana.use_item(String(s["id"])):
		return
	if info.has("heal") or info.has("buff") or info.has("mana"):
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


## Station kinds within reach; the village blacksmith counts as a smithy.
func nearby_station_kinds() -> Array:
	var out: Array = []
	for e in world().entities_near(global_position, 4.0, dimension):
		if e is Station:
			out.append((e as Station).station_kind)
		elif e is Npc and String(e.get("role")) == "blacksmith":
			out.append("smithy")
	return out


func craft(recipe_id: String) -> bool:
	var res := inventory.craft(recipe_id, nearby_station_kinds())
	if not bool(res.get("ok", false)):
		Events.notify.emit(String(res.get("reason", "")), "warn")
		return false
	Events.item_picked_up.emit(String(res["item"]), int(res["count"]))
	Audio.play_ui("levelup")
	Achievements.progress("crafted")
	if is_local and world() != null:
		world().quests.on_event("craft", String(res["item"]), int(res["count"]))
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
	inventory.gold += maxi(1, value / 2)
	inventory.remove_from_slot(i, 1)
	Audio.play_ui("coin")
	return true


func _on_inventory_changed() -> void:
	Events.inventory_changed.emit()
	_model_call("set_held", [inventory.selected_item()])


# --- Health, XP, death ----------------------------------------------------------------------------

func receive_damage(amount: float, from: Vector3, kind: String, source_name: String) -> void:
	if creative or dead:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < invulnerable_until:
		return
	amount *= inventory.damage_taken_multiplier(kind) * Game.damage_taken_scale()
	if health - amount <= 0.0 and arcana != null and arcana.try_undying():
		amount = maxf(0.0, health - 1.0)
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
	if dead:
		return
	if arcana != null:
		arcana.cancel_draw()
	if PvpArena.active():
		pass  # the arena brings you back itself (PvpArena)
	elif Net.is_online():
		if bool(Net.option("shrine_respawn", false)):
			# Shrine respawns on: rise at your shrine on your own after a moment.
			get_tree().create_timer(4.0).timeout.connect(func() -> void:
				if dead:
					request_respawn(true))
		else:
			downed = true
			bleed_left = BLEED_TIME
			Events.notify.emit("You are down! A teammate can revive you: they stand beside you and press E.", "warn")
	dead = true
	_start_action("die", 2.0)
	_model_call("set_dead", [true])
	Audio.play("death", global_position)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Events.player_died.emit(cause)


func request_respawn(force := false) -> void:
	if not dead:
		return
	if downed and not force:
		Events.notify.emit("Hold on - a teammate can still revive you (%d s)." % int(ceilf(bleed_left)), "warn")
		return
	downed = false
	dead = false
	health = max_health
	inventory.gold = int(inventory.gold * 0.9)
	if respawn_dimension != dimension:
		world().travel(respawn_dimension)
	global_position = respawn_point if respawn_point != Vector3.ZERO else world().default_spawn(dimension)
	body.velocity = Vector3.ZERO
	reset_breath()
	invulnerable_until = Time.get_ticks_msec() / 1000.0 + 3.0
	_model_call("set_dead", [false])
	_action = ""
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Events.player_health_changed.emit(health, max_health)
	Events.player_respawned.emit()


## A teammate got you back on your feet where you fell.
func revive(helper_name: String) -> void:
	if not dead:
		return
	downed = false
	dead = false
	health = max_health * 0.35
	reset_breath()
	invulnerable_until = Time.get_ticks_msec() / 1000.0 + 2.0
	_model_call("set_dead", [false])
	_action = ""
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Events.notify.emit("%s revived you." % helper_name, "info")
	Events.player_health_changed.emit(health, max_health)
	Events.player_respawned.emit()


## Downed teammates show a prompt to whoever stands beside them.
func interact_prompt(other: Node) -> String:
	if dead and downed and other != self and other is Player and not (other as Player).dead:
		return "Revive %s" % display_name
	return ""


func local_interact(other: Node) -> void:
	if other is Player and dead and downed:
		(other as Player)._begin_revive(self)


func _begin_revive(target: Player) -> void:
	_revive_target = target
	_revive_t = 0.0
	Events.notify.emit("Reviving %s... stay close." % target.display_name, "info")


func _revive_update(delta: float) -> void:
	if _revive_target == null:
		return
	var t := _revive_target
	if not is_instance_valid(t) or not t.dead or not t.downed or t.global_position.distance_to(global_position) > 3.0 or dead:
		_revive_target = null
		Events.mining_progress.emit(-1.0)
		return
	_revive_t += delta
	Events.mining_progress.emit(_revive_t / REVIVE_TIME)
	if _revive_t >= REVIVE_TIME:
		world().replicator.request_revive(t.net_id)
		_revive_target = null
		Events.mining_progress.emit(-1.0)


func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += amount
	var new_rank := ItemDB.rank_for_xp(xp)
	if new_rank > rank:
		rank = new_rank
		max_health = _max_health_for(rank)
		health = max_health
		Events.rank_up.emit(rank, ItemDB.RANK_TITLES[rank])
		Events.notify.emit("Rank up: %s %s. %s" % [Roles.role_name(role), ItemDB.RANK_TITLES[rank],
			String((Roles.PATH[role][rank] as Dictionary).get("note", ""))], "rank")
		Audio.play_ui("levelup")
		if arcana != null:
			arcana.on_rank_changed()
		if is_local:
			SpellNet.on_local_rank(self)
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
	# The offhand torch is on the left. Lighting from the right placed its
	# source against the weapon hand and bleached that hand in first person.
	_light.position.x = -0.35 if offhand_light else 0.35
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
		model.set("grounded", body.on_floor if is_local else not _remote_swim)
	if "swimming" in model:
		model.set("swimming", swimming if is_local else _remote_swim)
	if "velocity" in model:
		model.set("velocity", body.velocity if is_local else _remote_velocity)
	if "sprinting" in model:
		model.set("sprinting", _sprinting if is_local else _move_speed > 6.0)
	if "ground_block" in model and is_local:
		var vw := voxels()
		model.set("ground_block", ground_block(vw) if vw != null else -1)


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
	dead = int(state[8]) >= 1
	downed = int(state[8]) == 2
	if dead != was_dead:
		_model_call("set_dead", [dead])
	display_name = String(state[9])
	offhand_light = bool(state[10])
	_remote_swim = state.size() > 11 and bool(state[11])


func _process_remote(delta: float) -> void:
	var now: float = Net.server_time() if Net.has_method("server_time") else Time.get_ticks_msec() / 1000.0
	interpolate(now)
	_remote_velocity = _remote_velocity.lerp((global_position - _prev_remote_pos) / maxf(delta, 0.001), 1.0 - exp(-delta * 10.0))
	_move_speed = Vector2(_remote_velocity.x, _remote_velocity.z).length()
	_prev_remote_pos = global_position
	_update_light(delta)
	_animate(delta)


# --- Save ---------------------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	role_xp[role] = xp
	return {"name": display_name, "pos": global_position, "dim": dimension, "health": health, "xp": xp,
		"inventory": inventory.to_dict(), "respawn": respawn_point, "respawn_dim": respawn_dimension, "yaw": yaw,
		"role": role, "role_xp": role_xp.duplicate(), "knowledge": knowledge.duplicate(), "kits_given": kits_given.duplicate()}


func load_from(d: Dictionary) -> void:
	if d.is_empty():
		return
	dimension = int(d.get("dim", 0))
	global_position = d.get("pos", Vector3.ZERO)
	# Older saves have one XP pool: it becomes the pool of the role they were played as.
	var saved_role := String(d.get("role", Roles.DEFAULT))
	role_xp = (d.get("role_xp") as Dictionary).duplicate() if d.get("role_xp") is Dictionary else {}
	if not role_xp.has(saved_role):
		role_xp[saved_role] = int(d.get("xp", 0))
	knowledge = (d.get("knowledge") as Dictionary).duplicate() if d.get("knowledge") is Dictionary else {}
	kits_given = (d.get("kits_given") as Dictionary).duplicate() if d.get("kits_given") is Dictionary else {saved_role: true}
	xp = int(role_xp.get(role, 0))
	rank = ItemDB.rank_for_xp(xp)
	max_health = _max_health_for(rank)
	health = clampf(float(d.get("health", max_health)), 1.0, max_health)
	inventory.from_dict(d.get("inventory", {}))
	respawn_point = d.get("respawn", Vector3.ZERO)
	respawn_dimension = int(d.get("respawn_dim", 0))
	yaw = float(d.get("yaw", 0.0))
	if camera != null:
		camera.yaw = yaw + PI
	_emit_stats()
