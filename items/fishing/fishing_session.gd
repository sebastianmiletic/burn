class_name FishingSession
extends Node3D
## The local player's fishing, driven by right-click with a rod in hand:
##   cast   the bobber flies from the rod tip to where you look (range by rod
##          tier) and settles on the water (on land it is just reeled back)
##   wait   it bobs; nibbles tug it; then a bite plunges it under: right-click
##          within the strike window to set the hook
##   fight  hold right-click to reel (FishingDB.ReelFight): watch the line
##          tension, ease off while the fish surges, or the line snaps
##   catch  the fish (or junk, or treasure) goes into the pack; one bait is
##          used from the pack per catch (best first)
## Walking away, swimming or putting the rod away ends it. Other players see
## the line and bobber (VillageLife relays the state).

enum State { IDLE, CASTING, WAITING, BITE, FIGHT }

const STRIKE_WINDOW := 1.1
const MAX_WALK := 4.0

var player: Player
var state := State.IDLE
var rod := ""
var tier := 1
var line: FishingLine
var hud: FishingHud
var fight: FishingDB.ReelFight
var catch_id := ""
var ctx := {}

var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _bite_at := 0.0
var _nibbles: Array[float] = []
var _start := Vector3.ZERO
var _target := Vector3.ZERO
var _surface := 0.0
var _cast_time := 0.6
var _cast_from := Vector3.ZERO
var _in_water := false
var _net_t := 0.0
var _sent_state := -1
var _dip := 0.0


static func for_player(p: Player) -> FishingSession:
	var w := p.world()
	var existing := w.get_node_or_null(^"FishingSession") as FishingSession if w != null else null
	if existing != null:
		return existing
	var s := FishingSession.new()
	s.name = "FishingSession"
	s.player = p
	if w != null:
		w.add_child(s)
	return s


func _ready() -> void:
	_rng.randomize()
	line = FishingLine.new()
	add_child(line)
	line.visible = false
	hud = FishingHud.new()
	add_child(hud)


func busy() -> bool:
	return state != State.IDLE


## Right-click with a rod.
func on_use(rod_id: String) -> void:
	match state:
		State.IDLE:
			_cast(rod_id)
		State.CASTING:
			pass
		State.WAITING:
			_reel_in_empty("You reel in.")
		State.BITE:
			_strike()
		State.FIGHT:
			pass  # holding the button reels (polled in _process)


# --- Casting ----------------------------------------------------------------------------------

func _cast(rod_id: String) -> void:
	if player.swimming:
		Events.notify.emit("You can't cast while swimming.", "warn")
		return
	var vw := player.voxels()
	if vw == null:
		return
	rod = rod_id
	tier = int(ItemDB.info(rod_id).get("rod_tier", 1))
	var reach := float(FishingDB.rod_stats(tier)["cast"])
	var ray := player.camera.aim_ray()
	var origin: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	# Aim a little above the horizon and the cast still lands at full range.
	if dir.y > -0.05:
		dir = Vector3(dir.x, -0.05, dir.z).normalized()
	var hit := vw.raycast(origin, dir, reach + 4.0, true)
	if hit.is_empty():
		var fwd := Vector3(dir.x, 0, dir.z).normalized()
		var land := origin + fwd * reach
		var g := vw.ground_below(land.x, origin.y + 2.0, land.z, 40.0)
		_target = Vector3(land.x, g if absf(g) < 1e6 else origin.y - 2.0, land.z)
		_in_water = false
	else:
		var cell: Vector3i = hit["pos"]
		_in_water = int(hit.get("block", -1)) == Blocks.WATER
		if _in_water:
			_surface = _water_top(vw, cell)
			_target = Vector3(float(hit.get("point", Vector3(cell) + Vector3(0.5, 0.5, 0.5)).x), _surface, float(hit.get("point", Vector3(cell) + Vector3(0.5, 0.5, 0.5)).z))
		else:
			_target = hit.get("point", Vector3(cell) + Vector3(0.5, 1.0, 0.5))
	_cast_from = FishingLine.rod_tip(player)
	_start = player.global_position
	_cast_time = 0.45 + _cast_from.distance_to(_target) / 26.0
	_t = 0.0
	state = State.CASTING
	line.visible = true
	line.tight = 0.0
	line.bobber.global_position = _cast_from
	player._start_action("interact", 0.45)
	Audio.play("swing_light", player.global_position, -6.0, 0.8)


static func _water_top(vw: VoxelWorld, cell: Vector3i) -> float:
	var top := cell.y
	while top < cell.y + 30 and vw.get_block(Vector3i(cell.x, top + 1, cell.z)) == Blocks.WATER:
		top += 1
	var above := vw.get_block(Vector3i(cell.x, top + 1, cell.z))
	return float(top) + (0.88 if above == Blocks.AIR or above < 0 else 1.0)


static func _depth(vw: VoxelWorld, p: Vector3) -> float:
	var c := Vector3i(floori(p.x), floori(p.y - 0.2), floori(p.z))
	var d := 0
	while d < 40 and vw.get_block(c - Vector3i(0, d, 0)) == Blocks.WATER:
		d += 1
	return float(d)


## Where the bobber sits: sea or fresh water, biome, hour, depth, rod, bait.
func context() -> Dictionary:
	var w := player.world()
	var vw := player.voxels()
	var p := line.bobber.global_position
	var gen := w.gen_for(player.dimension) if w != null else null
	var c := {"water": "fresh", "biome": WorldGen.Biome.PLAINS, "sea": WorldGen.Sea.NONE, "hour": 12.0,
		"depth": _depth(vw, p) if vw != null else 2.0, "tier": tier, "bait": best_bait()[1], "rain": false}
	if w != null:
		c["hour"] = w.time_of_day()
		if w.weather != null:
			c["rain"] = String(w.weather.get("state")).contains("rain") or String(w.weather.get("state")).contains("storm")
	if gen != null:
		var biome := gen.biome_at(int(p.x), int(p.z))
		c["biome"] = biome
		c["sea"] = gen.sea_at(p.x, p.z)
		if player.dimension == 0 and p.y < gen.ground_level(p.x, p.z) - 6.0:
			c["water"] = "cave"
		elif biome == WorldGen.Biome.OCEAN or int(c["sea"]) != WorldGen.Sea.NONE:
			c["water"] = "sea"
	return c


## [item id, strength] of the best bait carried, or ["", 0].
func best_bait() -> Array:
	var best := ["", 0]
	for id: String in ["bait_lure", "bait_glowgrub", "bait_worms"]:
		if player.inventory.has(id):
			var s := int(ItemDB.info(id).get("bait", 0))
			if s > int(best[1]):
				best = [id, s]
	return best


func _land_bobber() -> void:
	if not _in_water:
		Audio.play("pick_dirt", _target, -10.0, 1.3)
		Events.notify.emit("Cast into water to fish.", "info")
		_end()
		return
	Audio.play("splash_small", _target, -6.0, 1.2)
	ModelKit.burst(get_parent(), _target + Vector3(0, 0.05, 0), 10, 0.15, 1.6, 0.05, Color(0.85, 0.92, 1.0), Color(0.6, 0.75, 0.85), 0.5)
	state = State.WAITING
	ctx = context()
	_t = 0.0
	_bite_at = FishingDB.bite_delay(ctx, _rng)
	_nibbles.clear()
	for i in _rng.randi_range(1, 3):
		_nibbles.append(_bite_at * _rng.randf_range(0.35, 0.9))


# --- Bite, strike, fight -----------------------------------------------------------------------

func _strike() -> void:
	catch_id = FishingDB.roll(ctx, _rng)
	fight = FishingDB.ReelFight.new(catch_id, tier, _rng.randi())
	state = State.FIGHT
	_t = 0.0
	player._start_action("interact", 0.3)
	Audio.play("splash", line.bobber.global_position, -4.0, 1.1)
	hud.show_fight(FishingDB.is_fish(catch_id))


func _reel_in_empty(msg: String) -> void:
	if msg != "":
		Events.notify.emit(msg, "info")
	_end()


func _end() -> void:
	state = State.IDLE
	line.visible = false
	fight = null
	hud.hide_fight()
	_send(0)


func _finish(result: String) -> void:
	var bait: Array = best_bait()
	match result:
		"caught":
			if bait[0] != "":
				player.inventory.remove(String(bait[0]), 1)
			player.give_item(catch_id, 1)
			var life := CharacterLife.of(player)
			if FishingDB.is_fish(catch_id):
				var first := life.log_catch(catch_id)
				var xp := 2 + ItemDB.rarity(catch_id) * 6
				player.add_xp(xp)
				if first:
					Events.notify.emit("First %s caught!" % ItemDB.display_name(catch_id), "quest")
			Audio.play("splash", line.bobber.global_position, -6.0, 0.9)
			Audio.play_ui("pickup")
		"snapped":
			if bait[0] != "":
				player.inventory.remove(String(bait[0]), 1)
			Events.notify.emit("The line snaps!" if FishingDB.is_fish(catch_id) else "The line snaps on something heavy.", "warn")
			Audio.play("swing_light", player.global_position, -2.0, 1.8)
		"slipped":
			Events.notify.emit("It slipped the hook.", "warn")
	_end()


# --- Frame -------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		queue_free()
		return
	if state == State.IDLE:
		return
	var held := player.held_item()
	if not ItemDB.info(held).has("rod_tier") or player.dead or player.swimming \
			or player.global_position.distance_to(_start) > MAX_WALK + (30.0 if state == State.FIGHT else 0.0) \
			or Vector2(player.global_position.x - line.bobber.global_position.x, player.global_position.z - line.bobber.global_position.z).length() > 45.0:
		_reel_in_empty("")
		return
	_t += delta
	line.tip = FishingLine.rod_tip(player)
	var b := line.bobber
	match state:
		State.CASTING:
			var f := clampf(_t / _cast_time, 0.0, 1.0)
			var p := _cast_from.lerp(_target, f)
			p.y += sin(f * PI) * (1.2 + _cast_from.distance_to(_target) * 0.12)
			b.global_position = p
			line.tight = 0.4
			if f >= 1.0:
				_land_bobber()
		State.WAITING:
			var bob := sin(_t * 2.1) * 0.015
			for n in _nibbles:
				if _t >= n and _t < n + 0.35:
					bob -= sin((_t - n) / 0.35 * PI) * 0.05
					if _t - delta < n:
						Audio.play("splash_small", b.global_position, -18.0, 1.6)
			b.global_position = Vector3(_target.x, _surface - 0.02 + bob, _target.z)
			line.tight = 0.1
			if _t >= _bite_at:
				state = State.BITE
				_t = 0.0
				Audio.play("splash", b.global_position, -8.0, 1.4)
				ModelKit.burst(get_parent(), b.global_position, 14, 0.2, 2.2, 0.05, Color(0.85, 0.92, 1.0), Color(0.6, 0.75, 0.85), 0.5)
				hud.flash("Bite! Strike now", 0.9)
		State.BITE:
			_dip = lerpf(_dip, 0.22, 1.0 - exp(-delta * 18.0))
			b.global_position = Vector3(_target.x + sin(_t * 23.0) * 0.03, _surface - _dip, _target.z)
			line.tight = 0.6
			if _t > STRIKE_WINDOW:
				_dip = 0.0
				_reel_in_empty("Too slow. It took the bait and left." if best_bait()[0] == "" else "Too slow. The fish got away.")
		State.FIGHT:
			var reeling := Settings.action_held("use") and not _ui_open()
			var res := fight.step(delta, reeling)
			var near := Vector3(player.global_position.x, _surface, player.global_position.z)
			var away := Vector3(_target.x, _surface, _target.z)
			var p := near.lerp(away, 0.12 + 0.88 * fight.distance)
			var wiggle := 0.25 if fight.surging > 0.0 else 0.06
			p += Vector3(sin(_t * 7.3) * wiggle, 0, cos(_t * 5.1) * wiggle)
			b.global_position = p - Vector3(0, 0.12 + 0.1 * sin(_t * 9.0), 0)
			line.tight = clampf(fight.tension / fight.strength, 0.2, 1.0)
			hud.update_fight(fight, reeling)
			if reeling and fmod(_t, 0.2) < delta:
				Audio.play("rustle", player.global_position, -16.0, 2.2)
			if res != "":
				_finish(res)
				return
	line.draw_line_now()
	_net_t -= delta
	if _net_t <= 0.0:
		_net_t = 0.2
		_send(2 if state == State.FIGHT else 1)


func _ui_open() -> bool:
	var w := player.world()
	return w != null and w.hud != null and w.hud.has_method("any_screen_open") and bool(w.hud.call("any_screen_open"))


func _send(s: int) -> void:
	var vl := VillageLife.of(player.world())
	if vl == null:
		return
	if s == 0 and _sent_state == 0:
		return
	_sent_state = s
	vl.send_fishing(s, line.bobber.global_position if s != 0 else Vector3.ZERO, line.tight)
