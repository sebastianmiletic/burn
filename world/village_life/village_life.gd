class_name VillageLife
extends Node
## Village life on the network, at /root/GameWorld/VillageLife on every peer:
##   * pets: feeding requests, owner commands (checked against ownership on
##     the server), bringing a character's saved pets into the world when
##     they arrive, following their owner between realms, and the wild
##     foxes, dogs, cats and ravens that can be tamed (spawned near players
##     by biome; stray cats and dogs live in villages)
##   * fishing: each angler's line and bobber relayed to the other players
## Villager tempers and trading need nothing here: tempers ride on the
## villager's own replication, trades are the trading player's own.

const WILD_CHECK := 7.0
const WILD_PER_PLAYER := 2
const WILD_RADIUS := 80.0

## [kind, weight] by land biome; villages have their own strays.
const WILD := {
	WorldGen.Biome.PLAINS: [["wild_dog", 0.5], ["fox", 0.4], ["raven", 0.2]],
	WorldGen.Biome.FOREST: [["fox", 1.0], ["raven", 0.5], ["wild_dog", 0.3]],
	WorldGen.Biome.REDWOOD: [["fox", 0.8], ["raven", 0.6]],
	WorldGen.Biome.MARSH: [["raven", 1.0], ["cat", 0.15]],
	WorldGen.Biome.PEAKS: [["fox", 0.5], ["raven", 0.5]],
	WorldGen.Biome.ALPINE: [["fox", 0.7], ["raven", 0.4]],
	WorldGen.Biome.TUNDRA: [["fox", 0.8], ["raven", 0.3]],
	WorldGen.Biome.WASTES: [["wild_dog", 1.0], ["raven", 0.4]],
	WorldGen.Biome.CANYON: [["wild_dog", 0.8], ["raven", 0.5]],
	WorldGen.Biome.FJORD: [["raven", 0.8], ["fox", 0.5]],
}
const VILLAGE_STRAYS := [["cat", 1.0], ["wild_dog", 0.3]]

var _wild_t := 3.0
var _pets_sent := false
var _rng := RandomNumberGenerator.new()
var _lines := {}          ## peer -> FishingLine (other players' fishing)
var _line_state := {}     ## peer -> [state, pos, tight, time]

static var _water_cache := {}


static func of(w: Object) -> VillageLife:
	if w == null or not (w is Node):
		return null
	return (w as Node).get_node_or_null(^"VillageLife") as VillageLife


func _init() -> void:
	name = "VillageLife"


func _ready() -> void:
	_rng.randomize()


func gw() -> GameWorld:
	return get_parent() as GameWorld


## True if a village has fishable water within reach (sea or lake), the same on every machine.
static func near_water(w: Object, village: String, dim: int) -> bool:
	if w == null or not w.has_method("gen_for") or not w.has_method("location_by_id"):
		return false
	var loc: Location = w.call("location_by_id", StringName(village))
	var gen: WorldGen = w.call("gen_for", dim)
	var key := "%s:%d:%d" % [village, dim, gen.world_seed if gen != null else 0]
	if _water_cache.has(key):
		return bool(_water_cache[key])
	var wet := false
	if loc != null and gen != null:
		for i in 24:
			var a := TAU * i / 24.0
			for r: float in [45.0, 75.0, 105.0]:
				var x := loc.center.x + cos(a) * r
				var z := loc.center.z + sin(a) * r
				if not gen.in_bounds(int(x), int(z)):
					continue
				if gen.ground_level(x, z) < WorldGen.SEA_LEVEL - 0.5 or gen.lake_level(x, z).x > -INF:
					wet = true
					break
			if wet:
				break
	_water_cache[key] = wet
	return wet


func _process(delta: float) -> void:
	var w := gw()
	if w == null or w.local_player == null:
		return
	if not _pets_sent and Game.state != Game.State.LOADING and w.world_for(w.local_dimension) != null \
			and w.world_for(w.local_dimension).is_area_loaded(w.local_player.global_position):
		_pets_sent = true
		_bring_my_pets()
	if Net.is_server():
		_wild_t -= delta
		if _wild_t <= 0.0:
			_wild_t = WILD_CHECK
			_populate_wild(w)
	_draw_remote_lines()


# --- Pets: the owner's side ----------------------------------------------------------------

## Asks the server to bring the local character's saved pets to them.
func _bring_my_pets() -> void:
	var life := CharacterLife.of(gw().local_player)
	if life.pets.is_empty():
		return
	if Net.is_server():
		_spawn_pets(gw().local_player, life.pets)
	else:
		_request_pets.rpc_id(1, life.pets)


func request_feed(pet_id: int, item: String) -> void:
	if Net.is_server():
		_feed(gw().local_player, pet_id, item)
	else:
		_request_feed.rpc_id(1, pet_id, item)


func request_pet_command(pet_id: int, cmd: String, arg: Variant) -> void:
	if Net.is_server():
		_command(gw().local_player, pet_id, cmd, arg)
	else:
		_request_command.rpc_id(1, pet_id, cmd, arg)


@rpc("any_peer", "reliable")
func _request_pets(pets: Array) -> void:
	if multiplayer.is_server():
		_spawn_pets(_sender(), pets)


@rpc("any_peer", "reliable")
func _request_feed(pet_id: int, item: String) -> void:
	if multiplayer.is_server():
		_feed(_sender(), pet_id, item)


@rpc("any_peer", "reliable")
func _request_command(pet_id: int, cmd: String, arg: Variant) -> void:
	if multiplayer.is_server():
		_command(_sender(), pet_id, cmd, arg)


# --- Pets: the server's side --------------------------------------------------------------

## The player entity of the peer that sent the current RPC.
func _sender() -> Entity:
	return gw().entity(Replicator.player_net_id(multiplayer.get_remote_sender_id()))


func _spawn_pets(owner: Entity, pets: Array) -> void:
	var w := gw()
	if owner == null:
		return
	# Never twice: skip pets of this owner already in the world.
	var have := {}
	for e in w.all_entities():
		if e is Pet and (e as Pet).owner_id == owner.net_id:
			have[(e as Pet).uid] = true
	var i := 0
	for rec: Variant in pets.slice(0, 8):
		if not (rec is Dictionary) or have.has(int(rec.get("uid", 0))):
			continue
		var kind := String(rec.get("kind", ""))
		if not Pet.SPECIES.has(kind):
			continue
		var a := owner.yaw + PI + (i - 1) * 0.6
		var p := owner.global_position + Vector3(sin(a), 0, cos(a)) * 2.0
		p.y = _ground(w, owner.dimension, p, owner.global_position.y)
		w.spawn_entity(kind, p, owner.dimension, {"owner": owner.net_id, "name": String(rec.get("name", "")),
			"uid": int(rec.get("uid", 0)), "variant": int(rec.get("variant", 0)), "mode": String(rec.get("mode", "follow"))})
		i += 1


func _feed(p: Entity, pet_id: int, item: String) -> void:
	var w := gw()
	var pet := w.entity(pet_id) as Pet
	if pet == null or p == null or pet.dimension != p.dimension or pet.global_position.distance_to(p.global_position) > 5.0:
		return
	pet.server_feed(p, item)


func _command(owner: Entity, pet_id: int, cmd: String, arg: Variant) -> void:
	var w := gw()
	var pet := w.entity(pet_id) as Pet
	if pet == null or owner == null or pet.owner_id != owner.net_id:
		return
	if not cmd in ["follow", "sit", "stay", "name", "uid", "release"]:
		return
	pet.server_command(cmd, arg)


## The owner went to another realm: the pet goes too (respawned beside them).
func move_pet_to_owner(pet: Pet, owner: Entity) -> void:
	var w := gw()
	if w == null or not Net.is_server():
		return
	var data: Dictionary = pet.get_meta("spawn_data", {}).duplicate()
	data["owner"] = pet.owner_id
	data["name"] = pet.pet_name
	data["uid"] = pet.uid
	data["variant"] = pet.variant
	data["mode"] = "follow"
	w.despawn_entity(pet)
	var p := owner.global_position - Vector3(sin(owner.yaw), 0, cos(owner.yaw)) * 1.8
	p.y = _ground(w, owner.dimension, p, owner.global_position.y)
	w.spawn_entity(pet.kind, p, owner.dimension, data)


static func _ground(w: GameWorld, dim: int, p: Vector3, fallback: float) -> float:
	var vw := w.world_for(dim)
	if vw == null:
		return fallback
	var g := vw.ground_below(p.x, p.y + 3.0, p.z, 10.0)
	return g if absf(g) < 1e6 else fallback


## Wild tameable animals near each player (server).
func _populate_wild(w: GameWorld) -> void:
	for p in w.players_in(0):
		if p.dead:
			continue
		var vw := w.world_for(0)
		var gen := w.gen_for(0)
		if vw == null or gen == null or p.global_position.y < gen.ground_level(p.global_position.x, p.global_position.z) - 8.0:
			continue
		var n := 0
		for e in w.entities_near(p.global_position, WILD_RADIUS, 0):
			if e is Pet and not (e as Pet).tamed():
				n += 1
		if n >= WILD_PER_PLAYER or _rng.randf() > 0.4:
			continue
		var night := w.time_of_day() >= 21.0 or w.time_of_day() < 5.0
		if night and _rng.randf() < 0.6:
			continue
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(24.0, 45.0)
		var pos := p.global_position + Vector3(cos(a) * r, 0, sin(a) * r)
		if not vw.is_area_loaded(pos):
			continue
		var g := vw.ground_below(pos.x, pos.y + 30.0, pos.z, 60.0)
		if absf(g) >= 1e6:
			continue
		pos.y = g
		if vw.get_block(Vector3i(floori(pos.x), floori(pos.y + 0.2), floori(pos.z))) == Blocks.WATER:
			continue
		var here := w.location_at(pos, 0)
		var table: Array = []
		if here != null and here.kind == Location.Kind.VILLAGE:
			table = VILLAGE_STRAYS
		elif here == null:
			table = WILD.get(gen.biome_at(int(pos.x), int(pos.z)), [])
		if table.is_empty():
			continue
		var kind := FishingDB._pick(table, _rng)
		var e := w.spawn_entity(kind, pos, 0, {"variant": _rng.randi() % 100000})
		if e != null:
			e.set_meta("wild", true)
			e.set_meta("wild_role", "tame")


# --- Fishing lines ------------------------------------------------------------------------

## The local angler's line: 0 none, 1 cast / waiting, 2 fighting.
func send_fishing(state: int, bobber: Vector3, tight: float) -> void:
	if not Net.is_online():
		return
	if Net.is_server():
		_relay_fishing(multiplayer.get_unique_id(), state, bobber, tight)
	else:
		_fishing_up.rpc_id(1, state, bobber, tight)


@rpc("any_peer", "unreliable_ordered")
func _fishing_up(state: int, bobber: Vector3, tight: float) -> void:
	if multiplayer.is_server():
		_relay_fishing(multiplayer.get_remote_sender_id(), state, bobber, tight)


func _relay_fishing(peer: int, state: int, bobber: Vector3, tight: float) -> void:
	var rep := gw().replicator
	for target in rep.ready_peers():
		if target != peer:
			_fishing_down.rpc_id(target, peer, state, bobber, tight)
	if peer != multiplayer.get_unique_id():
		_fishing_down(peer, state, bobber, tight)


@rpc("authority", "unreliable_ordered")
func _fishing_down(peer: int, state: int, bobber: Vector3, tight: float) -> void:
	_line_state[peer] = [state, bobber, tight, Time.get_ticks_msec() / 1000.0]


func _draw_remote_lines() -> void:
	if _line_state.is_empty():
		return
	var w := gw()
	var now := Time.get_ticks_msec() / 1000.0
	for peer: int in _line_state.keys():
		var st: Array = _line_state[peer]
		var p := w.entity(Replicator.player_net_id(peer)) as Player
		var live := int(st[0]) != 0 and now - float(st[3]) < 2.0 and p != null and p.dimension == w.local_dimension \
				and ItemDB.info(p.held_item()).has("rod_tier")
		var line: FishingLine = _lines.get(peer)
		if not live:
			if line != null:
				line.queue_free()
				_lines.erase(peer)
			if int(st[0]) == 0 or p == null:
				_line_state.erase(peer)
			continue
		if line == null:
			line = FishingLine.new()
			add_child(line)
			_lines[peer] = line
		line.bobber.global_position = line.bobber.global_position.lerp(st[1], 0.3) if line.bobber.global_position != Vector3.ZERO else st[1]
		line.tight = float(st[2])
		line.tip = FishingLine.rod_tip(p)
		line.draw_line_now()
