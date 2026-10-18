class_name GameWorld
extends Node3D
## The in-game root (always at /root/GameWorld so RPC paths match on every
## peer). Owns both dimensions, the entity registry, the local player, HUD,
## sky and weather, and is the API surface other systems talk to (see
## docs/ARCHITECTURE.md).
##
## Authority: the server (host, or this machine in solo) simulates monsters,
## bosses, projectiles, loot and block edits. Each client simulates its own
## player and reports it; the Replicator child carries all RPCs.

signal ready_to_play
signal loading(progress: float, text: String)

static var instance: GameWorld

const ENTITY_CULL_DISTANCE := 140.0

var session := {}
var gens := {}               # dim -> WorldGen
var worlds := {}             # dim -> VoxelWorld
var map_images := {}         # dim -> Image
var local_player: Player
var local_dimension := 0
var view: WorldView
var quests := QuestLog.new()
var discovered := {}         # location id -> true
var bosses_defeated := {}    # boss kind -> true
var opened_chests := {}      # chest key -> true
var lit_shrines := {}        # location id -> true
var play_time := 0.0
## Wounded bosses remembered across despawns and reloads (entities/bosses/boss_ledger.gd).
var boss_ledger := BossLedger.new()
var replicator: Replicator
var director: LocationDirector
var spawner: WildSpawner
var tracker: LocationTracker
var sky: SkyController
var weather: Weather
var fx: MiningFx
## Set when Hades falls: the portal to the Ryft Island opens (saved).
var ryft_unlocked := false
var _last_break_frame := -1
var hud: CanvasLayer
var ui_open := false

var _entities := {}          # net_id -> Entity
var _entity_root: Node3D
var _next_id := 1
var _active_boss: Node = null
var _prepare_task := -1
var _arena_gate_blocks: Array = []   # [dim, Vector3i] set during a boss fight


func _enter_tree() -> void:
	instance = self
	name = "GameWorld"
	add_to_group("game_world")


func _exit_tree() -> void:
	# Closing the game while a loading worker owns generator data must not
	# free the scene/resources out from under that worker.
	if _prepare_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_prepare_task)
		_prepare_task = -1
	if instance == self:
		instance = null


# --- Setup ---------------------------------------------------------------------

## info: {seed, mode, slot, save: Dictionary}
func setup(info: Dictionary) -> void:
	session = info
	var seed_value := int(info.get("seed", 1))
	_entity_root = Node3D.new()
	_entity_root.name = "Entities"
	add_child(_entity_root)
	replicator = Replicator.new()
	replicator.name = "Replicator"
	add_child(replicator)

	var t0 := Time.get_ticks_msec()
	loading.emit(0.02, "Reading the ashes")
	await _prepare_dimension(0, seed_value, 0.02, 0.45)
	_log_time("overworld prepared", t0)
	await _prepare_dimension(1, seed_value ^ 0x5eed, 0.45, 0.6)
	_log_time("underworld prepared", t0)
	await _prepare_dimension(2, seed_value ^ 0x7f17, 0.60, 0.62)
	add_child(Architecture.new())
	add_child(EnvironmentDetails.new())
	if DisplayServer.get_name() != "headless":
		CharBody.warmup([Models.player_style(0), Models.player_style(1)])
		await Models.warmup_mobs(self)
		_log_time("creatures warmed up", t0)
	if ResourceLoader.exists(VoxelWorld.FLORA_PATH):
		(load(VoxelWorld.FLORA_PATH) as Script).call("warmup")
		_log_time("flora warmed up", t0)

	sky = SkyController.new()
	add_child(sky)
	weather = Weather.new()
	add_child(weather)
	fx = MiningFx.new()
	add_child(fx)
	# Flora's interaction / ambient-life nodes (bending grass, insects), when present.
	for path in ["res://world/flora/foliage_interaction.gd", "res://world/flora/ambient_life.gd"]:
		if ResourceLoader.exists(path):
			var node: Node = (load(path) as Script).new()
			add_child(node)
	director = LocationDirector.new()
	add_child(director)
	spawner = WildSpawner.new()
	add_child(spawner)
	tracker = LocationTracker.new()
	add_child(tracker)
	# Activities (treasure, bounties, world events, the Proving Ring): same node path on every peer.
	add_child(ActivityDirector.new())

	var save: Dictionary = info.get("save", {})
	_load_world_state(save)

	# The local player and the camera the WorldView renders through.
	local_player = EntityFactory.create("player") as Player
	local_player.is_local = true
	local_player.net_id = Replicator.player_net_id(Net.my_id())
	local_player.peer_id = Net.my_id()
	local_player.display_name = String(Settings.get_value("gameplay", "player_name"))
	quests.inventory = local_player.inventory
	local_player.inventory.changed.connect(quests.inventory_changed)
	quests.completed_quest.connect(_on_quest_completed)
	_add_entity(local_player)
	local_player.load_from(save.get("player", {}))
	if not worlds.has(local_player.dimension) or (local_player.dimension == 2 and not ryft_unlocked):
		local_player.dimension = 0
		local_player.global_position = default_spawn(0)
	local_dimension = local_player.dimension
	var pdata: Dictionary = save.get("player", {})
	var lp := local_player.global_position
	var gsize := gen_for(local_player.dimension).size if gen_for(local_player.dimension) != null else 2048
	var lost := lp.x < 8.0 or lp.z < 8.0 or lp.x > gsize - 8.0 or lp.z > gsize - 8.0 or lp.y < WorldGen.Y_MIN + 4.0
	if pdata.has("pos") and lost:
		# A save from outside the world (an old bug put guests at the origin): bring them home.
		pdata = pdata.duplicate()
		pdata.erase("pos")
	if not pdata.has("pos"):
		# New characters, and guests bringing their character into a host's world.
		local_player.dimension = 0
		local_player.global_position = default_spawn(0)
		if not pdata.has("respawn") or (pdata["respawn"] as Vector3) == Vector3.ZERO:
			local_player.respawn_point = local_player.global_position
	if pdata.is_empty():
		local_player.give_starting_kit()
		quests.accept("kindling")
	if quests.is_completed("throne") and not quests.is_completed("ryft"):
		quests.accept("ryft")
	local_dimension = local_player.dimension

	view = WorldView.new()
	view.source_camera = local_player.camera
	add_child(view)
	_activate_dimension(local_dimension)

	loading.emit(0.62, "Raising the land")
	var world := world_for(local_dimension)
	world.focus = local_player.global_position
	var last_log := 0
	while not world.is_area_loaded(local_player.global_position) or world.loading_progress() < 0.98:
		loading.emit(0.62 + 0.35 * world.loading_progress(), "Raising the land")
		if "--load-timing" in OS.get_cmdline_user_args() and Time.get_ticks_msec() - last_log > 1000:
			last_log = Time.get_ticks_msec()
			print("[load]   ", world.debug_stats())
		await get_tree().process_frame
	_log_time("spawn area streamed", t0)
	# Make sure we stand on solid ground (saves can predate edits).
	var p := local_player.global_position
	# Saved inside a cave or mine: look for open space right here first, so a
	# slightly embedded save never lifts the player up to the surface.
	var near := Vector3.INF
	if local_player.body._overlaps(world, p) or world.field(p + Vector3(0, 0.3, 0)) >= 0.5:
		near = local_player.body.find_open_spot(world, p, 2.5)
	if near != Vector3.INF:
		local_player.global_position = near
	elif local_player.body._overlaps(world, p):
		# Smooth ground queries exclude masonry; they cannot resolve a body
		# embedded in a shrine platform or overlapping village architecture.
		local_player.global_position.y = world.surface_y(int(p.x), int(p.z)) + 1.05
	elif world.field(p + Vector3(0, 0.3, 0)) >= 0.5:
		var g := world.ground_below(p.x, p.y + 40.0, p.z, 80.0)
		if absf(g) < 1e6:
			local_player.global_position = Vector3(p.x, g + 0.02, p.z)
		else:
			local_player.global_position = Vector3(p.x, world.surface_y(int(p.x), int(p.z)) + 1.05, p.z)

	_apply_gfx_flags()
	hud = _make_ui()
	if hud != null:
		add_child(hud)
	loading.emit(1.0, "")
	Audio.set_music("explore")
	ready_to_play.emit()


## Profiling aid: --gfx=noshadow,nofog,nossao,noglow,nosun,dist4
func _apply_gfx_flags() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--gfx="):
			continue
		for f in a.trim_prefix("--gfx=").split(","):
			match f:
				"noshadow":
					sky.sun.shadow_enabled = false
					sky.moon.shadow_enabled = false
					sky.set_meta("no_shadow", true)
				"nofog":
					sky.environment.volumetric_fog_enabled = false
				"nossao":
					sky.environment.ssao_enabled = false
				"noglow":
					sky.environment.glow_enabled = false
				"nosun":
					sky.sun.visible = false
				"dist4":
					for d: int in worlds:
						(worlds[d] as VoxelWorld).view_radius = 4


func _log_time(what: String, t0: int) -> void:
	if OS.is_debug_build() and "--load-timing" in OS.get_cmdline_user_args():
		print("[load] %-22s %6d ms" % [what, Time.get_ticks_msec() - t0])


func _prepare_dimension(dim: int, seed_value: int, p0: float, p1: float) -> void:
	var saved: Dictionary = session.get("save", {})
	var revision := int(saved.get("world_revision", WorldGen.LATEST_REVISION if saved.is_empty() else 1))
	var gen := WorldGen.new(dim, seed_value, revision)
	gens[dim] = gen
	var done := [false]
	var horizon: Array = [[]]
	var progress := [0.0, ""]
	var task := WorkerThreadPool.add_task(func() -> void:
		gen.prepare(func(f: float, text: String) -> void:
			progress[0] = f
			progress[1] = text)
		map_images[dim] = MapImage.build(gen)
		if dim == 0:
			horizon[0] = DistantLand.arrays_for(gen)
		done[0] = true, true, "prepare dimension")
	_prepare_task = task
	while not done[0]:
		loading.emit(lerpf(p0, p1, progress[0]), progress[1] if progress[1] != "" else "Shaping the land")
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	_prepare_task = -1
	if dim == 0:
		var distant := DistantLand.new()
		distant.setup(gen, horizon[0])
		add_child(distant)
	var vw := VoxelWorld.new()
	vw.name = ["Overworld", "Underworld", "Ryft"][dim]
	vw.setup(gen, dim)
	vw.view_radius = view_radius()
	vw.max_point_lights = [6, 10, 14, 20][int(Settings.get_value("graphics", "quality"))]
	vw.block_changed.connect(_on_block_changed.bind(dim))
	worlds[dim] = vw
	add_child(vw)
	vw.visible = false
	vw.meshing_enabled = false


func view_radius() -> int:
	return [6, 8, 10, 12][int(Settings.get_value("graphics", "quality"))]


func _make_ui() -> CanvasLayer:
	var script: Script = load("res://ui/hud.gd") if ResourceLoader.exists("res://ui/hud.gd") else null
	if script == null:
		return null
	return script.new()


func _activate_dimension(dim: int) -> void:
	local_dimension = dim
	for d: int in worlds:
		var w: VoxelWorld = worlds[d]
		w.visible = d == dim
		w.meshing_enabled = d == dim
		w.set_process(true)
	sky.set_dimension(dim)
	weather.set_dimension(dim)
	for e: Entity in _entities.values():
		e.visible = e.dimension == dim
	Events.dimension_changed.emit(dim)


# --- Main loop -------------------------------------------------------------------

func _process(delta: float) -> void:
	if replicator != null:
		replicator.check_party_wipe(delta)
	if local_player == null:
		return
	play_time += delta
	var lw := world_for(local_dimension)
	lw.focus = local_player.global_position
	if Net.is_server():
		# Other players' surroundings need data for physics and AI.
		for d: int in worlds:
			var w: VoxelWorld = worlds[d]
			var foci: Array[Vector3] = []
			for p in players_in(d):
				if p != local_player:
					foci.append(p.global_position)
			w.data_focus = foci
			# A dimension with nobody in it does nothing.
			w.set_process(d == local_dimension or not foci.is_empty())
	_update_entities(delta)


func _physics_process(_delta: float) -> void:
	pass


func _update_entities(delta: float) -> void:
	var server := Net.is_server()
	var now: float = Net.server_time() if Net.has_method("server_time") else Time.get_ticks_msec() / 1000.0
	var player_positions := {}
	for p in players_in(-1):
		if not player_positions.has(p.dimension):
			player_positions[p.dimension] = []
		player_positions[p.dimension].append(p.global_position)
	for e: Entity in _entities.values():
		if not is_instance_valid(e):
			continue
		if e is Player:
			continue
		if server:
			# Freeze anything no player is near (bosses keep fighting while engaged).
			var near := false
			for pp: Vector3 in player_positions.get(e.dimension, []):
				if pp.distance_squared_to(e.global_position) < ENTITY_CULL_DISTANCE * ENTITY_CULL_DISTANCE:
					near = true
					break
			if near or (e.has_method("is_engaged") and e.call("is_engaged")):
				e.server_tick(delta)
		else:
			e.interpolate(now)


# --- Queries -----------------------------------------------------------------------

func world_for(dim: int) -> VoxelWorld:
	return worlds.get(dim)


func gen_for(dim: int) -> WorldGen:
	return gens.get(dim)


func map_image(dim: int) -> Image:
	return map_images.get(dim)


func locations(dim: int) -> Array[Location]:
	var g: WorldGen = gens.get(dim)
	return g.locations if g != null else ([] as Array[Location])


func location_by_id(id: StringName) -> Location:
	for d: int in gens:
		for l in locations(d):
			if l.id == id:
				return l
	return null


func location_at(pos: Vector3, dim: int) -> Location:
	var best: Location = null
	for l in locations(dim):
		if l.contains(pos):
			if best == null or l.radius < best.radius:
				best = l
	return best


func entity(net_id: int) -> Entity:
	return _entities.get(net_id)


func all_entities() -> Array:
	return _entities.values()


func entities_near(pos: Vector3, radius: float, dim: int, team := -1) -> Array[Entity]:
	var out: Array[Entity] = []
	var r2 := radius * radius
	for e: Entity in _entities.values():
		if e.dimension != dim or e.dead:
			continue
		if team >= 0 and e.team != team:
			continue
		if e.global_position.distance_squared_to(pos) <= r2:
			out.append(e)
	return out


func players_in(dim: int) -> Array[Player]:
	var out: Array[Player] = []
	for e: Entity in _entities.values():
		if e is Player and (dim < 0 or e.dimension == dim):
			out.append(e)
	return out


func nearest_player(pos: Vector3, dim: int, max_dist: float) -> Player:
	var best: Player = null
	var best_d := max_dist * max_dist
	for p in players_in(dim):
		if p.dead:
			continue
		var d := p.global_position.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = p
	return best


func default_spawn(dim: int) -> Vector3:
	var id := &"emberfall_shrine" if dim == 0 else (&"asphodel" if dim == 1 else &"ryft_landing")
	var loc := location_by_id(id)
	var g := gen_for(dim)
	var p := Vector3(g.size * 0.5, 40, g.size * 0.5)
	if loc != null:
		p = loc.center + Vector3(0, 0, 4)
		for s in loc.spawns_of("shrine"):
			p = s["pos"] + Vector3(0, 0, 3)
	# Preserve the shrine's masonry clearance instead of spawning in its floor.
	return Vector3(p.x, maxf(p.y, g.surface_height(int(p.x), int(p.z)) + 1.05), p.z)


func map_metres_per_pixel(_dim: int) -> float:
	return float(WorldGen.COARSE)


func surface_height_at(x: float, z: float) -> float:
	var g := gen_for(local_dimension)
	return float(g.surface_height(int(x), int(z))) if g != null else 0.0


func camera_yaw() -> float:
	return local_player.camera.yaw if local_player != null and local_player.camera != null else 0.0


func time_of_day() -> float:
	return sky.time_of_day if sky != null else 12.0


func day() -> int:
	return sky.day if sky != null else 1


func set_ui_open(open: bool) -> void:
	ui_open = open
	if local_player != null:
		local_player.set_input_enabled(not open)


# --- Entities (server) ------------------------------------------------------------------

func spawn_entity(kind: String, pos: Vector3, dim: int, data := {}) -> Entity:
	if not Net.is_server():
		return null
	var id := _next_id
	_next_id += 1
	var e := _create_entity(id, kind, pos, dim, data)
	if e != null:
		replicator.broadcast_spawn(e, data)
	return e


func _create_entity(id: int, kind: String, pos: Vector3, dim: int, data: Dictionary) -> Entity:
	var e := EntityFactory.create(kind, data)
	if e == null:
		push_error("Unknown entity kind " + kind)
		return null
	e.net_id = id
	e.dimension = dim
	# Position before entering the tree: entities record their spawn point in _ready.
	e.position = pos
	_add_entity(e)
	if e.has_method("on_spawned"):
		e.call("on_spawned", data)
	e.visible = dim == local_dimension
	return e


func _add_entity(e: Entity) -> void:
	_entities[e.net_id] = e
	_entity_root.add_child(e)
	e.died.connect(_on_entity_died)


## Client side: mirror a server spawn.
func client_spawn(id: int, kind: String, pos: Vector3, dim: int, data: Dictionary) -> void:
	if _entities.has(id):
		return
	_create_entity(id, kind, pos, dim, data)


func despawn_entity(e: Entity) -> void:
	if e == null or not _entities.has(e.net_id):
		return
	if Net.is_server():
		replicator.broadcast_despawn(e.net_id)
	remove_entity(e.net_id)


func remove_entity(id: int) -> void:
	var e: Entity = _entities.get(id)
	_entities.erase(id)
	if e != null and is_instance_valid(e):
		e.queue_free()


func _on_entity_died(e: Entity) -> void:
	if not Net.is_server():
		return
	if e is Player:
		return
	var xp := int(e.get("xp_value")) if e.get("xp_value") != null else 0
	var credit := players_near_credit(e)
	for p in credit:
		replicator.give_xp_to(p.peer_id, xp, e.kind)
	# Loot (bosses drop theirs in boss_finished, with the relic).
	var loot: Variant = e.get("loot") if not e is Boss else null
	if loot is Array:
		for entry: Array in loot:
			if randf() < float(entry[1]):
				drop_item(e.center(), entry[0], randi_range(int(entry[2]), int(entry[3])), e.dimension)
	if e.get("gold_value") != null and int(e.get("gold_value")) > 0:
		for p in credit:
			replicator.give_gold_to(p.peer_id, int(e.get("gold_value")))
	# Enemies and bosses despawn themselves once their death animation is done.
	if not (e is Enemy or e is Boss):
		# IDs survive early despawns without a lambda retaining a freed Node.
		get_tree().create_timer(4.0).timeout.connect(_despawn_dead_entity.bind(e.net_id))


func _despawn_dead_entity(id: int) -> void:
	var e := entity(id)
	if e != null and e.dead:
		despawn_entity(e)


## Players who share a kill: everyone in the dimension within 60 m.
func players_near_credit(e: Entity) -> Array[Player]:
	var out: Array[Player] = []
	for p in players_in(e.dimension):
		if p.global_position.distance_to(e.global_position) < 60.0:
			out.append(p)
	return out


# --- Combat (server) --------------------------------------------------------------

func damage(target: Entity, amount: float, source_id: int, kind := "hit") -> void:
	if not Net.is_server() or target == null or target.dead:
		return
	if target is Player:
		replicator.hurt_player((target as Player).peer_id, amount, source_id, kind)
		return
	# Enemies and bosses show their own damage numbers and hit flashes on every
	# machine when their health changes, so nothing else to broadcast here.
	target.take_damage(amount, source_id, kind)


func request_attack(targets: Array, amount: float, kind: String) -> void:
	replicator.request_attack(targets, amount, kind)


func spawn_projectile(kind: String, origin: Vector3, velocity: Vector3, owner_id: int, team: int, dim: int, dmg: float) -> void:
	if not Net.is_server():
		return
	replicator.broadcast_projectile(kind, origin, velocity, owner_id, team, dim, dmg)


func telegraph(shape: String, pos: Vector3, dir: Vector3, size: Vector3, duration: float, dim: int) -> void:
	if Net.is_server():
		replicator.broadcast_telegraph(shape, pos, dir, size, duration, dim)


func show_telegraph(shape: String, pos: Vector3, dir: Vector3, size: Vector3, duration: float, dim: int) -> void:
	if dim != local_dimension:
		return
	var fx: Script = load("res://combat/telegraph_fx.gd") if ResourceLoader.exists("res://combat/telegraph_fx.gd") else null
	if fx != null:
		fx.call("spawn", self, shape, pos, dir, size, duration)


func shake(strength: float, at := Vector3.INF, dim := -1) -> void:
	if Net.is_server():
		replicator.broadcast_shake(strength, at, dim)


func drop_item(pos: Vector3, item_id: String, count: int, dim: int) -> void:
	if not Net.is_server() or count <= 0 or not ItemDB.exists(item_id):
		return
	var vel := Vector3(randf_range(-2, 2), 4.0, randf_range(-2, 2))
	spawn_entity("drop", pos, dim, {"item": item_id, "count": count, "vel": vel})


# --- Bosses ----------------------------------------------------------------------------

func boss_started(boss: Node) -> void:
	if not Net.is_server():
		return
	_active_boss = boss
	replicator.broadcast_boss_state(boss.get("net_id"), true, String(boss.get("kind")))
	_set_arena_gates(boss, true)


func boss_finished(boss: Node) -> void:
	if not Net.is_server():
		return
	var kind := String(boss.get("kind"))
	var dim := int(boss.get("dimension"))
	_set_arena_gates(boss, false)
	_active_boss = null
	var defeated := bool(boss.get("dead"))
	replicator.broadcast_boss_state(boss.get("net_id"), false, kind, defeated)
	if defeated:
		bosses_defeated[kind] = true
		replicator.sync_bosses_defeated(bosses_defeated)
		# Relic for every participant, loot on the ground.
		var relic: Variant = boss.get("relic")
		for p in players_near_credit(boss as Entity):
			if relic != null and String(relic) != "":
				replicator.give_item_to(p.peer_id, String(relic), 1)
		var loot: Variant = boss.get("loot")
		if loot is Array:
			for entry: Array in loot:
				if randf() < float(entry[1]):
					drop_item((boss as Entity).center(), entry[0], randi_range(int(entry[2]), int(entry[3])), dim)
		if kind == "hades":
			ryft_unlocked = true
			replicator.broadcast_victory()


func _set_arena_gates(boss: Node, closed: bool) -> void:
	var dim := int(boss.get("dimension"))
	var home: Variant = boss.get("home_location")
	var loc: Location = location_by_id(StringName(String(home))) if home != null else location_at((boss as Node3D).global_position, dim)
	if loc == null:
		return
	if not closed:
		for entry: Array in _arena_gate_blocks:
			request_set_block_server(entry[1], Blocks.AIR, entry[0])
		_arena_gate_blocks.clear()
		return
	for g in loc.spawns_of("arena_gate"):
		var base := Vector3i((g["pos"] as Vector3).floor())
		var across: Vector3i = g["across"]
		for w in range(-int(g["width"]), int(g["width"]) + 1):
			for h in int(g["height"]):
				var p := base + across * w + Vector3i(0, h, 0)
				var vw := world_for(dim)
				if vw.get_block(p) == Blocks.AIR:
					request_set_block_server(p, Blocks.STRUCTURE, dim)  # invisible: ArenaGate draws the gate
					_arena_gate_blocks.append([dim, p])


## A boss whose fight was abandoned (everyone died or fled): reopen the arena.
func boss_reset(boss: Node) -> void:
	if not Net.is_server():
		return
	_set_arena_gates(boss, false)
	if _active_boss == boss:
		_active_boss = null
	replicator.broadcast_boss_state(boss.get("net_id"), false, String(boss.get("kind")), false)


func knockback(target: Entity, impulse: Vector3) -> void:
	if not Net.is_server() or target == null:
		return
	if target is Player:
		replicator.knockback_player((target as Player).peer_id, impulse)
	else:
		target.body.velocity += impulse


func active_boss() -> Node:
	return _active_boss


# --- Blocks -----------------------------------------------------------------------------

## Crafting stations players have placed: [{kind, pos, yaw, dim}] (saved).
var placed_stations: Array = []


func request_place_station(kind: String, pos: Vector3, yaw: float, dim: int) -> void:
	replicator.request_station(kind, pos, yaw, dim)


## Server: spawn a station and remember it for the save.
func place_station(kind: String, pos: Vector3, yaw: float, dim: int, remember := true) -> Entity:
	var e := spawn_entity("station", pos, dim, {"station": kind, "yaw": yaw})
	if e != null:
		e.yaw = yaw
		e.rotation.y = yaw
		if remember:
			placed_stations.append({"kind": kind, "pos": pos, "yaw": yaw, "dim": dim})
	return e


func request_set_block(pos: Vector3i, block: int, dim: int) -> void:
	replicator.request_block(pos, block, dim)


func request_set_block_server(pos: Vector3i, block: int, dim: int) -> void:
	if Net.is_server():
		replicator.broadcast_block(pos, block, dim)


func _on_block_changed(pos: Vector3i, old_block: int, new_block: int, dim: int) -> void:
	if dim != local_dimension or Blocks.is_trunk(old_block):
		return
	var c := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	# Sculpting changes many voxels at once: one sound and one burst per frame.
	var frame := Engine.get_process_frames()
	if frame == _last_break_frame:
		return
	_last_break_frame = frame
	if old_block != Blocks.AIR and new_block == Blocks.AIR:
		var fam := Blocks.sound_family(old_block)
		var snd := "break_" + ("dirt" if fam in ["dirt", "sand", "snow"] else ("wood" if fam == "wood" else ("crystal" if fam == "crystal" else "stone")))
		Audio.play(snd, c)
		if fx != null:
			fx.debris(c, Vector3.UP, Blocks.color(old_block), true)
	elif new_block != Blocks.AIR and old_block == Blocks.AIR and fx != null:
		fx.debris(c, Vector3.UP, Blocks.color(new_block), false)


## A tree toppling (visual only; the trunk blocks are removed separately).
func fell_tree_fx(root: Vector3i, trunk: int, dim: int, dir: Vector3) -> void:
	if dim != local_dimension:
		return
	var vw := world_for(dim)
	var info := WorldGen.tree_info(trunk, root)
	var ground := vw.ground_below(root.x + 0.5, root.y + 1.0, root.z + 0.5, 3.0)
	var base := Vector3(root.x + 0.5, ground if absf(ground) < 1e6 else float(root.y), root.z + 0.5)
	if vw.flora != null:
		vw.flora.call("fell", self, base, int(info[0]), float(info[1]), int(info[2]), dir)
	Audio.play("tree_creak", base + Vector3(0, 2, 0))
	get_tree().create_timer(1.1).timeout.connect(func() -> void: Audio.play("tree_fall", base + dir * 4.0))
	if fx != null:
		fx.debris(base + Vector3(0, 0.8, 0), -dir, Blocks.color(trunk), true)


# --- Dimensions --------------------------------------------------------------------------

## Local player moves to another dimension (portal).
## Solo inspection only: no progression unlocks or quest travel events.
func creative_teleport(location_id: StringName) -> bool:
	if Net.is_online() or local_player == null or not local_player.creative:
		return false
	var loc := location_by_id(location_id)
	if loc == null:
		return false
	var target := loc.center + Vector3(0, 3, 0)
	for s in loc.spawns_of("boss"):
		target = (s["pos"] as Vector3) + Vector3(0, 2, 8)
		break
	local_player.dimension = loc.dimension
	_activate_dimension(loc.dimension)
	local_player.global_position = target
	local_player.body.velocity = Vector3.ZERO
	world_for(loc.dimension).focus = target
	replicator.notify_dimension(loc.dimension)
	return true


func travel(to_dim: int) -> void:
	if not worlds.has(to_dim) or (to_dim == 2 and not ryft_unlocked):
		return
	var target := default_spawn(to_dim)
	if to_dim == 0 and local_dimension == 1:
		var gate := location_by_id(&"gates_of_hades")
		if gate != null:
			for s in gate.spawns_of("portal"):
				target = (s["pos"] as Vector3) + Vector3(0, 0.1, 9)
	var from := local_dimension
	local_player.dimension = to_dim
	_activate_dimension(to_dim)
	local_player.global_position = target
	local_player.body.velocity = Vector3.ZERO
	var w := world_for(to_dim)
	w.focus = target
	view.flash = 1.0
	Audio.play_ui("portal")
	Audio.set_music("hell" if to_dim == 1 else "explore")
	quests.on_event("dimension", str(to_dim))
	replicator.notify_dimension(to_dim)
	if from != to_dim:
		Events.notify.emit("Ryft Island: follow the stone arches between the floating isles." if to_dim == 2 else ("You pass through the Gates of Hades." if to_dim == 1 else "You return to the world above."), "warn")


# --- Quests / rewards ----------------------------------------------------------------------

func _on_quest_completed(q: Dictionary) -> void:
	var r: Dictionary = q.get("rewards", {})
	if r.has("take"):
		for item: String in r["take"]:
			local_player.inventory.remove(item, int(r["take"][item]))
	local_player.add_xp(int(r.get("xp", 0)))
	local_player.inventory.gold += int(r.get("gold", 0))
	for item: String in r.get("items", {}):
		local_player.give_item(item, int(r["items"][item]))
	local_player.inventory.changed.emit()


func discover(loc: Location) -> void:
	if discovered.has(loc.id):
		return
	discovered[loc.id] = true
	Events.location_discovered.emit(loc.id)
	quests.on_event("reach", String(loc.id))
	quests.on_event("discover", Location.KIND_LABELS[loc.kind].to_lower())
	local_player.add_xp(15 if not loc.major else 40)


# --- Save / load -----------------------------------------------------------------------------

func save_data() -> Dictionary:
	var here := location_at(local_player.global_position, local_dimension)
	return {
		"seed": int(session.get("seed", 1)),
		"world_revision": gen_for(0).revision,
		"play_time": play_time,
		"player": local_player.to_dict(),
		"quests": quests.to_dict(),
		"discovered": discovered.keys(),
		"map_fog": MapFog.save_dict(self),
		"bosses_defeated": bosses_defeated.keys(),
		"boss_wounds": boss_ledger.to_save(play_time),
		"opened_chests": opened_chests.keys(),
		"lit_shrines": lit_shrines.keys(),
		"edits": {0: world_for(0).get_edits(), 1: world_for(1).get_edits(), 2: world_for(2).get_edits()},
		"stations": placed_stations,
		"activities": ActivityDirector.of(self).save_state() if ActivityDirector.of(self) != null else {},
		"ryft_unlocked": ryft_unlocked,
		"time_of_day": sky.time_of_day,
		"day": sky.day,
		"location_name": here.name if here != null else GameWorld.biome_name(self, local_player.global_position, local_dimension),
	}


func _load_world_state(save: Dictionary) -> void:
	play_time = float(save.get("play_time", 0.0))
	quests.from_dict(save.get("quests", {}))
	for id in save.get("discovered", []):
		discovered[StringName(id)] = true
	for k in save.get("bosses_defeated", []):
		bosses_defeated[String(k)] = true
	var wounds: Variant = save.get("boss_wounds", {})
	if wounds is Dictionary:
		boss_ledger.from_save(wounds)
	for k in save.get("opened_chests", []):
		opened_chests[String(k)] = true
	for k in save.get("lit_shrines", []):
		lit_shrines[StringName(k)] = true
	var edits: Dictionary = save.get("edits", {})
	for d: int in edits:
		if worlds.has(d):
			(worlds[d] as VoxelWorld).apply_edits(edits[d])
	ryft_unlocked = bool(save.get("ryft_unlocked", false)) or bosses_defeated.has("hades")
	if save.has("time_of_day"):
		sky.time_of_day = float(save["time_of_day"])
		sky.day = int(save.get("day", 1))
	if Net.is_server() and ResourceLoader.exists("res://entities/interact/station.gd"):
		for st: Dictionary in save.get("stations", []):
			place_station(String(st["kind"]), st["pos"], float(st.get("yaw", 0.0)), int(st.get("dim", 0)))


func is_ready_for_join() -> bool:
	return worlds.has(0) and worlds.has(1) and worlds.has(2) and sky != null


## State a joining client needs: edits, bosses, clock.
func join_state() -> Dictionary:
	return {
		"edits": {0: world_for(0).get_edits(), 1: world_for(1).get_edits(), 2: world_for(2).get_edits()},
		"world_revision": gen_for(0).revision,
		"ryft_unlocked": ryft_unlocked,
		"bosses_defeated": bosses_defeated.keys(),
		"time_of_day": sky.time_of_day,
		"day": sky.day,
	}


static func biome_name(gw: GameWorld, pos: Vector3, dim: int) -> String:
	var g := gw.gen_for(dim)
	if g == null:
		return ""
	return WorldGen.BIOME_NAMES[g.biome_at(int(pos.x), int(pos.z))]
