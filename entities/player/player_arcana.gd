class_name PlayerArcana
extends Node
## The local player's role powers: mana, glyph drawing and casting, the bow
## and staff, movement upgrades from rank (double jump, dash/air dash,
## wall-kick, glide, faster swimming), books and the role's XP/rank bookkeeping.
## A child of the local Player (Player.arcana); the Player calls the hooks.
##
## Casting: hold the cast key (Q, or R), draw a glyph with the mouse (the view
## stops turning while you draw and a glowing trail follows the stroke),
## release. GlyphRecognizer reads the shape, Spells.resolve() decides, and the
## host applies the effect (SpellNet).

signal stroke_changed
signal mana_changed(mana: float, max_mana: float)

const CAST_ACTIONS := ["ability_fire", "ability_burst"]
const STROKE_MAX := 600
const UNDYING_COOLDOWN := 300.0
const BOLT_COOLDOWN := 0.45

var player: Player
## Glyph drawing state (virtual cursor in screen pixels).
var drawing := false
var stroke := PackedVector2Array()
var cursor := Vector2.ZERO
var last_verdict := {}   # for the overlay: {result, spell, text, glyph, score, t}
var mana := 60.0
var max_mana := 60.0
var draw_t := 0.0        # bow draw time held
var _draw_action := ""
var _cooldowns := {}     # spell -> [end, total]
var _air_jumps := 0
var _air_dashes := 0
var _gliding := false
var _undying_ready_at := 0.0
var _warned_item := ""
var _bolt_cd := 0.0
var _no_arrow_warned := false


func _ready() -> void:
	_recompute(false)
	mana = max_mana


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func perks() -> Dictionary:
	return Roles.perks(player.role, player.rank)


## Max mana and health after a role/rank change.
func _recompute(fill := true) -> void:
	max_mana = Roles.max_mana(player.role, player.rank)
	if fill:
		mana = max_mana
	mana = minf(mana, max_mana)
	mana_changed.emit(mana, max_mana)


func on_rank_changed() -> void:
	_recompute(true)


# --- Input --------------------------------------------------------------------------

## Returns true when the event was used (the Player then ignores it).
func handle_input(event: InputEvent) -> bool:
	for a: String in CAST_ACTIONS:
		if event.is_action_pressed(a) and not event.is_echo():
			_begin_draw(a)
			return true
		if event.is_action_released(a) and drawing and a == _draw_action:
			_finish_draw()
			return true
	if drawing and event is InputEventMouseMotion:
		var vp := player.get_viewport().get_visible_rect().size
		cursor = (cursor + (event as InputEventMouseMotion).relative).clamp(Vector2.ZERO, vp)
		if stroke.is_empty() or stroke[stroke.size() - 1].distance_to(cursor) >= 3.0:
			if stroke.size() < STROKE_MAX:
				stroke.append(cursor)
			stroke_changed.emit()
		return true
	if drawing and event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
		cancel_draw()
		return true
	if event.is_action_pressed("dodge") and not player.body.on_floor and not player.swimming and can_air_dash():
		player._dodge()
		return true
	return false


func _begin_draw(action: String) -> void:
	if player.dead or player.swimming:
		return
	drawing = true
	_draw_action = action
	stroke = PackedVector2Array()
	cursor = player.get_viewport().get_visible_rect().size * 0.5
	stroke.append(cursor)
	stroke_changed.emit()
	Audio.play("rustle", player.global_position, -14.0, 1.6)


func cancel_draw() -> void:
	drawing = false
	stroke = PackedVector2Array()
	stroke_changed.emit()


func _finish_draw() -> void:
	drawing = false
	var rec := GlyphRecognizer.recognize(stroke)
	var known := known_spells()
	var res := Spells.resolve(player.role, rec, known)
	res["glyph"] = rec.get("glyph", "")
	res["score"] = rec.get("score", 0.0)
	res["t"] = _now()
	last_verdict = res
	stroke_changed.emit()
	var tracker := _tracker()
	match String(res["result"]):
		"fizzle", "unknown":
			if String(res["result"]) == "fizzle" and bool(rec.get("valid", false)):
				# A botched glyph still drains a little.
				mana = maxf(0.0, mana - 8.0)
			SpellNet.request_fizzle(player)
			Events.notify.emit(String(res["text"]), "warn")
		_:
			if not cast(String(res["spell"]), float(res["power"])):
				return
			if String(res["text"]) != "":
				Events.notify.emit(String(res["text"]), "warn")
	if tracker != null:
		tracker.on_glyph(String(res["result"]))


func _tracker() -> Achievements:
	var w := player.world()
	return w.get_node_or_null("SpellNet/Achievements") as Achievements if w != null else null


func known_spells() -> Array:
	return Spells.known(player.role, player.rank, player.knowledge)


func cooldown_left(spell: String) -> float:
	return maxf(0.0, float(_cooldowns.get(spell, [0.0, 0.0])[0]) - _now())


## Cast a known spell at `power` (0..1). Returns false (with a message) when it can't go.
func cast(spell: String, power: float) -> bool:
	var s: Dictionary = Spells.SPELLS.get(spell, {})
	if s.is_empty() or player.dead:
		return false
	if cooldown_left(spell) > 0.0:
		Events.notify.emit("%s is not ready (%d s)." % [String(s["name"]), ceili(cooldown_left(spell))], "warn")
		return false
	var cost := float(s["mana"])
	if mana < cost:
		Events.notify.emit("Not enough %s for %s." % [String(Roles.ROLES[player.role]["resource"]).to_lower(), String(s["name"])], "warn")
		return false
	mana -= cost
	mana_changed.emit(mana, max_mana)
	_cooldowns[spell] = [_now() + float(s["cooldown"]), float(s["cooldown"])]
	Events.ability_cooldown.emit("glyph", float(s["cooldown"]), float(s["cooldown"]))
	player._start_action("cast", 0.45)
	var ray := player.camera.aim_ray()
	var origin: Vector3 = player.global_position + Vector3(0, 1.45, 0) + Vector3(sin(player.yaw), 0, cos(player.yaw)) * 0.8
	var dir: Vector3 = ray[1]
	var aim: Vector3 = ray[0] + dir * 60.0
	var hit := player.voxels().raycast(ray[0], dir, 60.0)
	if not hit.is_empty():
		aim = hit["point"]
	match String(s["kind"]):
		"blink":
			_blink(float(s.get("range", 14.0)) * lerpf(0.6, 1.0, power), aim)
		"buff_self":
			player.inventory.buffs[String(s["buff"])] = _now() + float(s["seconds"]) * lerpf(0.5, 1.0, power)
			player.inventory.changed.emit()
	SpellNet.request_cast(player, spell, power, origin, (aim - origin).normalized(), aim)
	return true


func _blink(dist: float, aim: Vector3) -> void:
	var vw := player.voxels()
	var from := player.global_position
	var dir := Vector3(aim.x - from.x, 0, aim.z - from.z)
	if dir.length() < 0.5:
		dir = -Vector3(sin(player.camera.yaw), 0, cos(player.camera.yaw))
	dir = dir.normalized()
	var best := from
	var step := 0.5
	var t := step
	while t <= dist:
		var p := from + dir * t + Vector3(0, 0.1, 0)
		if player.body._overlaps(vw, p):
			# Try stepping up a little (a slope or a ledge).
			var up := p + Vector3(0, 1.0, 0)
			if player.body._overlaps(vw, up):
				break
			p = up
		best = p
		t += step
	player.global_position = best
	player.body.velocity = Vector3(player.body.velocity.x, maxf(0.0, player.body.velocity.y), player.body.velocity.z)
	player._fall_speed = 0.0


# --- Per-frame ------------------------------------------------------------------------

func _process(delta: float) -> void:
	if player == null:
		return
	var regen := Roles.mana_regen(player.role, player.rank) * (2.0 if player.inventory.buff_active("clarity") else 1.0)
	if not player.dead and mana < max_mana:
		mana = minf(max_mana, mana + regen * delta)
		mana_changed.emit(mana, max_mana)
	_bolt_cd = maxf(0.0, _bolt_cd - delta)
	if drawing and (player.dead or not player._input_enabled):
		cancel_draw()


## Bows and staffs (from Player._combat_update). True when the held weapon is
## one of ours (the Player then does not swing).
func weapon_update(delta: float, info: Dictionary) -> bool:
	var kind := String(info.get("kind", ""))
	if kind != "bow" and kind != "staff":
		if draw_t > 0.0:
			draw_t = 0.0
			Events.mining_progress.emit(-1.0)
		return false
	var held := player.inventory.selected_item()
	var attack := player._input_enabled and Settings.action_held("attack") and not drawing
	if not Roles.rank_ok(held, player.role_ranks()):
		if attack and _warned_item != held:
			_warned_item = held
			Events.notify.emit("The %s will not answer you: it asks for %s rank %d." % [ItemDB.display_name(held),
				Roles.role_name(Roles.role_for_item(held)), int(info.get("rank_req", 0))], "warn")
		return true
	if kind == "bow":
		var full := float(info.get("draw", 1.0)) / (1.0 + float(perks()["draw"]))
		if attack:
			if draw_t == 0.0 and _best_arrow() == "":
				if not _no_arrow_warned:
					_no_arrow_warned = true
					Events.notify.emit("No arrows.", "warn")
				return true
			_no_arrow_warned = false
			draw_t += delta
			Events.mining_progress.emit(clampf(draw_t / full, 0.0, 1.0))
		elif draw_t > 0.0:
			var frac := clampf(draw_t / full, 0.0, 1.0)
			draw_t = 0.0
			Events.mining_progress.emit(-1.0)
			if frac >= 0.25:
				_loose(info, frac)
		return true
	# Staff: an arcane bolt per press-and-hold tick.
	if attack and _bolt_cd <= 0.0 and player._action == "":
		var cost := float(info.get("mana_cost", 6.0))
		if mana < cost:
			if _bolt_cd <= 0.0:
				Events.notify.emit("Not enough mana.", "warn")
			_bolt_cd = 1.0
			return true
		mana -= cost
		mana_changed.emit(mana, max_mana)
		_bolt_cd = BOLT_COOLDOWN
		player._start_action("cast", 0.35)
		var ray := player.camera.aim_ray()
		var origin := player.global_position + Vector3(0, 1.5, 0) + Vector3(sin(player.yaw), 0, cos(player.yaw)) * 0.7
		var aim: Vector3 = ray[0] + ray[1] * 50.0
		var hit := player.voxels().raycast(ray[0], ray[1], 50.0)
		if not hit.is_empty():
			aim = hit["point"]
		var dmg := float(info.get("bolt_damage", 12.0)) * power_mult("staff")
		SpellNet.request_shot(player, "arcane_bolt", origin, (aim - origin).normalized() * 32.0, dmg, float(info.get("burn", 0.0)), false)
	return true


func _best_arrow() -> String:
	for a: String in ArcanaItems.ARROWS:
		if player.inventory.has(a):
			return a
	return ""


func _loose(info: Dictionary, frac: float) -> void:
	var arrow := _best_arrow()
	if arrow == "":
		return
	player.inventory.remove(arrow, 1)
	var ainf := ItemDB.info(arrow)
	var ray := player.camera.aim_ray()
	var origin := player.global_position + Vector3(0, 1.5, 0) + Vector3(sin(player.yaw), 0, cos(player.yaw)) * 0.6
	var aim: Vector3 = ray[0] + ray[1] * 80.0
	var hit := player.voxels().raycast(ray[0], ray[1], 80.0)
	if not hit.is_empty():
		aim = hit["point"]
	var speed := float(info.get("arrow_speed", 40.0)) * lerpf(0.45, 1.0, frac)
	var dir := (aim - origin).normalized()
	# Arrows drop: aim a touch high for the distance (gravity 9).
	var dist := origin.distance_to(aim)
	var flight := dist / maxf(speed, 1.0)
	var vel := dir * speed + Vector3(0, 4.5 * flight, 0)
	var dmg := (float(info.get("damage", 10.0)) * lerpf(0.3, 1.0, frac * frac) + float(ainf.get("arrow_damage", 0.0))) * power_mult("bow")
	var burn := float(info.get("burn", 0.0)) + float(ainf.get("arrow_burn", 0.0))
	SpellNet.request_shot(player, "arrow", origin, vel, dmg, burn, frac >= 0.99 and bool(perks()["pierce"]))
	player._signal_anim("attack", 0.3)
	Audio.play("swing_light", player.global_position, -8.0, 1.4)


## Damage multiplier for the role's own weapon kind (rank growth + path power).
func power_mult(kind: String) -> float:
	var m := 1.0 + player.rank * 0.06
	if kind in Roles.weapon_kinds(player.role):
		m += float(perks()["power"])
	return m


# --- Movement upgrades (called from Player._move) ---------------------------------------

func speed_mult() -> float:
	return 1.25 if player.inventory.buff_active("swift") else 1.0


func swim_bonus() -> float:
	return float(perks()["swim"])


func dash_mult() -> float:
	return 1.6 if Roles.has_move(player.role, player.rank, "dash") else 1.0


func can_air_dash() -> bool:
	return Roles.has_move(player.role, player.rank, "air_dash") and _air_dashes > 0


func used_air_dash() -> void:
	_air_dashes -= 1


func no_fall_damage() -> bool:
	return _gliding or player.inventory.buff_active("featherfall")


## A jump pressed in the air: wall-kick off a wall you are touching, else a double jump.
func try_air_jump() -> bool:
	var body := player.body
	if Roles.has_move(player.role, player.rank, "wall_kick") and body.hit_wall:
		var back := Vector3(sin(player.camera.yaw), 0, cos(player.camera.yaw))  # camera looks along -Z
		body.velocity = back * 6.5 + Vector3(0, Player.JUMP_VELOCITY * 0.95, 0)
		player._fall_speed = 0.0
		player._signal_anim("jump", 0.4)
		Audio.play("jump", player.global_position, -5.0, 1.15)
		return true
	if Roles.has_move(player.role, player.rank, "double_jump") and _air_jumps > 0:
		_air_jumps -= 1
		body.velocity.y = Player.JUMP_VELOCITY * 0.92
		player._fall_speed = 0.0
		player._signal_anim("jump", 0.4)
		Audio.play("jump", player.global_position, -6.0, 1.25)
		if player.world() != null and player.world().fx != null:
			ModelKit.burst(player.world(), player.global_position, 14, 0.3, 2.0, 0.25, Color(1, 0.9, 0.7), Color(0.9, 0.6, 0.3), 0.4)
		return true
	return false


## Glide and the per-airtime counters (before VoxelBody.step).
func movement(delta: float) -> void:
	var body := player.body
	if body.on_floor or player.swimming:
		_air_jumps = 1
		_air_dashes = 1
		_gliding = false
		return
	var can_glide := Roles.has_move(player.role, player.rank, "glide") or player.inventory.buff_active("featherfall")
	_gliding = can_glide and player._input_enabled and Input.is_action_pressed("jump") and body.velocity.y < -1.5
	if _gliding:
		body.velocity.y = maxf(body.velocity.y, -2.4)
		var fwd := -Vector3(sin(player.camera.yaw), 0, cos(player.camera.yaw))
		var hv := Vector3(body.velocity.x, 0, body.velocity.z)
		hv = hv.lerp(fwd * maxf(hv.length(), 6.5), 1.0 - exp(-1.5 * delta))
		body.velocity.x = hv.x
		body.velocity.z = hv.z
		player._fall_speed = 0.0


## Called before a lethal blow lands. True: it leaves you at 1 health instead.
func try_undying() -> bool:
	if not bool(perks()["undying"]) or _now() < _undying_ready_at:
		return false
	_undying_ready_at = _now() + UNDYING_COOLDOWN
	Events.notify.emit("Undying: you refuse to fall.", "rank")
	return true


# --- Items --------------------------------------------------------------------------------

## Use/drink an item of ours. True when handled.
func use_item(id: String) -> bool:
	var inf := ItemDB.info(id)
	if inf.has("book"):
		read_book(id)
		return true
	return false


func read_book(id: String) -> void:
	var k := ArcanaItems.book_knowledge(id)
	if k == "":
		return
	if player.knowledge.has(k):
		Events.notify.emit("You already know what %s teaches. (Codex: K)" % ItemDB.display_name(id), "info")
		return
	player.knowledge[k] = true
	Audio.play_ui("levelup")
	var teaches: Dictionary = ArcanaItems.BOOKS.get(k, {})
	var parts := PackedStringArray()
	for s: String in teaches.get("spells", []):
		parts.append(String(Spells.SPELLS[s]["name"]))
	for b: String in teaches.get("brews", []):
		parts.append(ItemDB.display_name(b))
	for c: String in teaches.get("crafts", []):
		parts.append(ItemDB.display_name(ItemDB.recipe_result(c)))
	Events.notify.emit("You read %s. Learned: %s. (Codex: K)" % [ItemDB.display_name(id), ", ".join(parts)], "quest")
	Achievements.on_books(player.knowledge)


## After drinking: mana potions.
func on_drink(id: String) -> void:
	var m := float(ItemDB.info(id).get("mana", 0.0))
	if m > 0.0:
		mana = minf(max_mana, mana + m)
		mana_changed.emit(mana, max_mana)
