class_name SpellNet
extends Node
## Spells, ranged shots, PvP hits and player looks between peers. Lives at
## /root/GameWorld/SpellNet (same path everywhere). Host authoritative: clients
## ask, the host validates and applies damage/heals/buffs, and every machine
## plays the effects (_fx). In solo the same paths run locally.
##
## Looks: each client announces {role, skin, rank}; the host keeps the table
## and shares it, so remote players wear the right outfit (Player.set_look).

const MAX_ORIGIN_DIST := 4.5
const MAX_SPELL_RANGE := 70.0

## peer -> [role, skin, rank]
var looks := {}
var _announced := false
var arena: PvpArena
var tracker: Achievements

static var _instance: SpellNet


static func of(w: Node) -> SpellNet:
	return w.get_node_or_null("SpellNet") as SpellNet if w != null else null


static func look_of(peer: int) -> Array:
	if _instance == null or not is_instance_valid(_instance):
		return []
	return _instance.looks.get(peer, [])


func gw() -> GameWorld:
	return get_parent() as GameWorld


func _enter_tree() -> void:
	_instance = self


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _ready() -> void:
	tracker = Achievements.new()
	tracker.name = "Achievements"
	tracker.world = gw()
	add_child(tracker)
	gw().ready_to_play.connect(_on_world_ready)
	multiplayer.peer_disconnected.connect(func(peer: int) -> void: looks.erase(peer))


func _on_world_ready() -> void:
	var p := gw().local_player
	if p == null:
		return
	Achievements.on_role_played(p.role)
	Achievements.check_ranks(p.role_ranks())
	if PvpArena.active():
		arena = PvpArena.new()
		arena.name = "Arena"
		add_child(arena)
	announce()


## Tell everyone what we look like (on load, after a lobby change, on rank-up).
func announce() -> void:
	var p := gw().local_player
	if p == null or (Net.dedicated and Net.is_server()):
		return
	_announced = true
	if Net.is_server():
		_set_look(multiplayer.get_unique_id(), p.role, p.skin, p.rank)
	else:
		_rpc_look_request.rpc_id(1, p.role, p.skin, p.rank)


static func on_local_rank(p: Player) -> void:
	var sn := of(p.world())
	if sn != null:
		sn.announce()
	var earned := Skins.earned_by_rank(p.role, p.rank)
	for s: String in earned:
		if PlayerProfile.unlock_skin(s):
			Events.notify.emit("New outfit unlocked: %s (choose it in the lobby)." % Skins.display_name(s), "rank")
	Achievements.check_ranks(p.role_ranks())


@rpc("any_peer", "reliable")
func _rpc_look_request(role: String, skin: String, rank: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	_set_look(peer, role, skin, rank)
	# The newcomer learns everyone else's look.
	_rpc_looks.rpc_id(peer, looks)


func _set_look(peer: int, role: String, skin: String, rank: int) -> void:
	if not Roles.is_role(role) or not Skins.SKINS.has(skin):
		return
	looks[peer] = [role, skin, clampi(rank, 0, ItemDB.RANK_TITLES.size() - 1)]
	_apply_look(peer)
	if Net.is_online():
		for other in multiplayer.get_peers():
			if other != peer:
				_rpc_look.rpc_id(other, peer, role, skin, rank)


@rpc("authority", "reliable")
func _rpc_look(peer: int, role: String, skin: String, rank: int) -> void:
	looks[peer] = [role, skin, rank]
	_apply_look(peer)


@rpc("authority", "reliable")
func _rpc_looks(table: Dictionary) -> void:
	for peer: int in table:
		looks[peer] = table[peer]
		_apply_look(peer)


func _apply_look(peer: int) -> void:
	if peer == multiplayer.get_unique_id():
		return
	var p := gw().entity(Replicator.player_net_id(peer)) as Player
	if p != null and looks.has(peer):
		var l: Array = looks[peer]
		p.set_look(String(l[0]), String(l[1]))


## The host's view of a peer's role rank (what clients told it).
func rank_of(peer: int) -> int:
	if peer == multiplayer.get_unique_id() and gw().local_player != null:
		return gw().local_player.rank
	return int(looks.get(peer, ["", "", 0])[2])


func role_of(peer: int) -> String:
	if peer == multiplayer.get_unique_id() and gw().local_player != null:
		return gw().local_player.role
	return String(looks.get(peer, [Roles.DEFAULT])[0])


# --- Requests (any machine) ------------------------------------------------------------

static func request_cast(p: Player, spell: String, power: float, origin: Vector3, dir: Vector3, aim: Vector3) -> void:
	var sn := of(p.world())
	if sn == null:
		return
	if Net.is_server():
		sn._cast(sn.multiplayer.get_unique_id(), spell, power, origin, dir, aim)
	else:
		sn._rpc_cast.rpc_id(1, spell, power, origin, dir, aim)


static func request_shot(p: Player, kind: String, origin: Vector3, vel: Vector3, dmg: float, burn: float, pierce: bool) -> void:
	var sn := of(p.world())
	if sn == null:
		return
	if Net.is_server():
		sn._shot(sn.multiplayer.get_unique_id(), kind, origin, vel, dmg, burn, pierce)
	else:
		sn._rpc_shot.rpc_id(1, kind, origin, vel, dmg, burn, pierce)


static func request_pvp_hits(p: Player, targets: Array, amount: float) -> void:
	var sn := of(p.world())
	if sn == null or not PvpArena.active():
		return
	if Net.is_server():
		sn._pvp_hits(sn.multiplayer.get_unique_id(), targets, amount)
	else:
		sn._rpc_pvp_hits.rpc_id(1, targets, amount)


static func request_fizzle(p: Player) -> void:
	var sn := of(p.world())
	if sn != null:
		var hand := p.global_position + Vector3(0, 1.4, 0) + Vector3(sin(p.yaw), 0, cos(p.yaw)) * 0.6
		sn.fx("fizzle", hand, Vector3.UP, 1.0, PackedVector3Array(), p.dimension)


@rpc("any_peer", "reliable")
func _rpc_cast(spell: String, power: float, origin: Vector3, dir: Vector3, aim: Vector3) -> void:
	if multiplayer.is_server():
		_cast(multiplayer.get_remote_sender_id(), spell, power, origin, dir, aim)


@rpc("any_peer", "reliable")
func _rpc_shot(kind: String, origin: Vector3, vel: Vector3, dmg: float, burn: float, pierce: bool) -> void:
	if multiplayer.is_server():
		_shot(multiplayer.get_remote_sender_id(), kind, origin, vel, dmg, burn, pierce)


@rpc("any_peer", "reliable")
func _rpc_pvp_hits(targets: Array, amount: float) -> void:
	if multiplayer.is_server():
		_pvp_hits(multiplayer.get_remote_sender_id(), targets, amount)


# --- Host -------------------------------------------------------------------------------

func _caster(peer: int) -> Player:
	var p := gw().entity(Replicator.player_net_id(peer)) as Player
	return p if p != null and not p.dead else null


## Things a caster's spell may hurt: monsters, and other players in PvP.
func victims(center: Vector3, radius: float, caster: Player) -> Array[Entity]:
	var out: Array[Entity] = []
	for e: Entity in gw().entities_near(center, radius, caster.dimension):
		if e == caster or e.dead:
			continue
		if e.team == Entity.Team.MONSTERS or (e.team == Entity.Team.PLAYERS and PvpArena.active()):
			out.append(e)
	return out


func hurt(target: Entity, amount: float, caster: Player, kind := "hit") -> void:
	if target == null or target.dead:
		return
	gw().damage(target, amount, caster.net_id, kind)
	if target.has_method("add_threat"):
		target.call("add_threat", caster.net_id, amount)


func spell_mult(peer: int) -> float:
	var r := rank_of(peer)
	return 1.0 + r * 0.05 + float(Roles.perks(role_of(peer), r)["power"])


func _cast(peer: int, spell: String, power: float, origin: Vector3, dir: Vector3, aim: Vector3) -> void:
	var c := _caster(peer)
	var s: Dictionary = Spells.SPELLS.get(spell, {})
	if c == null or s.is_empty() or not origin.is_finite() or not dir.is_finite() or not aim.is_finite():
		return
	if origin.distance_to(c.global_position) > MAX_ORIGIN_DIST:
		return
	power = clampf(power, 0.0, 1.0)
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	if aim.distance_to(c.global_position) > MAX_SPELL_RANGE:
		aim = c.global_position + (aim - c.global_position).normalized() * MAX_SPELL_RANGE
	var m := spell_mult(peer) * power
	var base := float(s.get("power", 0.0))
	var dim := c.dimension
	var feet := c.global_position
	match String(s["kind"]):
		"projectile":
			gw().spawn_projectile(String(s["projectile"]), origin, dir * float(s.get("speed", 26.0)), c.net_id, Entity.Team.PLAYERS, dim, base * m)
		"melee_arc":
			var fwd := Vector3(dir.x, 0, dir.z).normalized()
			for e in victims(feet, float(s["radius"]) + 1.0, c):
				var to := e.global_position - feet
				to.y = 0
				if to.length() < 0.6 or fwd.dot(to.normalized()) > -0.1:
					hurt(e, base * m, c, "hit")
			fx(spell, feet + Vector3(0, 1.0, 0), fwd, power, PackedVector3Array(), dim)
		"nova":
			for e in victims(feet, float(s["radius"]), c):
				hurt(e, base * m, c, "hit")
				if e is Player:
					gw().replicator.knockback_player((e as Player).peer_id, (e.global_position - feet).normalized() * 9.0 + Vector3(0, 5, 0))
			fx(spell, feet + Vector3(0, 0.3, 0), Vector3.UP, power, PackedVector3Array(), dim)
		"buff_allies":
			for p in gw().players_in(dim):
				if p.global_position.distance_to(feet) <= float(s["radius"]) and not p.dead:
					_send_buff(p.peer_id, String(s["buff"]), float(s["seconds"]) * lerpf(0.5, 1.0, power))
			fx(spell, feet + Vector3(0, 1.0, 0), Vector3.UP, power, PackedVector3Array(), dim)
		"buff_self":
			fx(spell, feet + Vector3(0, 1.0, 0), Vector3.UP, power, PackedVector3Array([feet]), dim)
		"heal":
			var frac := float(s["power"]) * lerpf(0.5, 1.0, power)
			var radius := float(s.get("radius", 0.0))
			var pts := PackedVector3Array()
			for p in gw().players_in(dim):
				if p.dead or (p != c and (radius <= 0.0 or p.global_position.distance_to(feet) > radius)):
					continue
				_send_heal(p.peer_id, frac)
				pts.append(p.global_position)
			fx(spell, feet + Vector3(0, 1.0, 0), Vector3.UP, power, pts, dim)
		"blink":
			fx(spell, origin, dir, power, PackedVector3Array([aim]), dim)
		"volley":
			var n := int(s.get("count", 5))
			for i in n:
				var a := (float(i) / maxf(1.0, n - 1.0) - 0.5) * 0.45
				var d := dir.rotated(Vector3.UP, a)
				gw().spawn_projectile("arrow", origin, d * 38.0 + Vector3(0, 1.5, 0), c.net_id, Entity.Team.PLAYERS, dim, base * m)
		"rain":
			var n := int(s.get("count", 12))
			var r := float(s.get("radius", 5.0))
			for i in n:
				var off := Vector3(randf_range(-r, r), 0, randf_range(-r, r))
				var start := aim + off + Vector3(randf_range(-2, 2), 26.0 + randf() * 6.0, randf_range(-2, 2))
				var delay := randf() * 1.2
				get_tree().create_timer(delay).timeout.connect(func() -> void:
					if is_inside_tree():
						gw().spawn_projectile("arrow", start, (aim + off - start).normalized() * 34.0, c.net_id, Entity.Team.PLAYERS, dim, base * m))
			fx(spell, aim, Vector3.UP, power, PackedVector3Array(), dim)
		"chain":
			var pts := PackedVector3Array([origin])
			var hit := {}
			var from := origin
			var first: Entity = null
			var best := 1e9
			for e in victims(feet, float(s.get("range", 20.0)), c):
				var to := e.center() - origin
				var along := to.dot(dir)
				if along <= 0.0:
					continue
				var off := (to - dir * along).length()
				if off < 3.0 + along * 0.12 and along + off * 3.0 < best:
					best = along + off * 3.0
					first = e
			var target := first
			var dmg := base * m
			for j in int(s.get("jumps", 4)) + 1:
				if target == null:
					break
				hit[target] = true
				hurt(target, dmg, c, "hit")
				pts.append(target.center())
				from = target.center()
				dmg *= 0.8
				var next: Entity = null
				var nd := 9.0
				for e in victims(from, 9.0, c):
					if hit.has(e):
						continue
					var d := e.center().distance_to(from)
					if d < nd:
						nd = d
						next = e
				target = next
			if pts.size() == 1:
				pts.append(origin + dir * 12.0)
			fx(spell, origin, dir, power, pts, dim)
		"meteor":
			var start := aim + Vector3(-dir.x * 8.0, 32.0, -dir.z * 8.0)
			gw().spawn_projectile("meteor", start, (aim - start).normalized() * 30.0, c.net_id, Entity.Team.PLAYERS, dim, base * m)
			fx(spell, aim, Vector3.UP, power, PackedVector3Array(), dim)


func _shot(peer: int, kind: String, origin: Vector3, vel: Vector3, dmg: float, burn: float, pierce: bool) -> void:
	var c := _caster(peer)
	if c == null or not kind in ["arrow", "arcane_bolt"] or not origin.is_finite() or not vel.is_finite():
		return
	if origin.distance_to(c.global_position) > MAX_ORIGIN_DIST:
		return
	var proj := kind
	if kind == "arrow" and pierce:
		proj = "arrow_pierce"
	if kind == "arrow" and burn > 0.0:
		proj = "arrow_fire"
	gw().spawn_projectile(proj, origin, vel.limit_length(70.0), c.net_id, Entity.Team.PLAYERS, c.dimension, clampf(dmg, 0.0, 250.0))


func _pvp_hits(peer: int, targets: Array, amount: float) -> void:
	var c := _caster(peer)
	if c == null or not PvpArena.active():
		return
	amount = clampf(amount, 0.0, 300.0)
	for id: int in targets:
		var t := gw().entity(id) as Player
		if t == null or t == c or t.dead or t.dimension != c.dimension:
			continue
		if t.global_position.distance_to(c.global_position) > Replicator.MAX_REACH + 1.0:
			continue
		gw().damage(t, amount, c.net_id, "hit")


func _send_heal(peer: int, frac: float) -> void:
	if peer == multiplayer.get_unique_id() or not Net.is_online():
		_rpc_heal(frac)
	else:
		_rpc_heal.rpc_id(peer, frac)


@rpc("authority", "reliable")
func _rpc_heal(frac: float) -> void:
	var p := gw().local_player
	if p == null or p.dead:
		return
	var h := p.max_health * clampf(frac, 0.0, 1.0)
	p.heal_local(h)
	Events.damage_number.emit(p.center() + Vector3(0, 0.6, 0), int(h), false, "heal")


func _send_buff(peer: int, buff: String, seconds: float) -> void:
	if peer == multiplayer.get_unique_id() or not Net.is_online():
		_rpc_buff(buff, seconds)
	else:
		_rpc_buff.rpc_id(peer, buff, seconds)


@rpc("authority", "reliable")
func _rpc_buff(buff: String, seconds: float) -> void:
	var p := gw().local_player
	if p == null or p.dead or seconds <= 0.0 or seconds > 600.0:
		return
	p.inventory.buffs[buff] = Time.get_ticks_msec() / 1000.0 + seconds
	p.inventory.changed.emit()


# --- Effects (every machine) ---------------------------------------------------------------

## Plays a spell effect everywhere. Any machine may call it for its own fizzles
## and blinks; the host relays.
func fx(spell: String, pos: Vector3, dir: Vector3, power: float, pts: PackedVector3Array, dim: int) -> void:
	if Net.is_server():
		_rpc_fx(spell, pos, dir, power, pts, dim)
		if Net.is_online():
			for peer in gw().replicator.ready_peers():
				_rpc_fx.rpc_id(peer, spell, pos, dir, power, pts, dim)
	else:
		_rpc_fx_request.rpc_id(1, spell, pos, dir, power, pts, dim)


@rpc("any_peer", "unreliable")
func _rpc_fx_request(spell: String, pos: Vector3, dir: Vector3, power: float, pts: PackedVector3Array, dim: int) -> void:
	if multiplayer.is_server() and spell in ["fizzle", "brew_explosion", "brew_poison"] and pts.size() <= 8:
		fx(spell, pos, dir, power, pts, dim)


@rpc("authority", "unreliable")
func _rpc_fx(spell: String, pos: Vector3, dir: Vector3, power: float, pts: PackedVector3Array, dim: int) -> void:
	if gw() == null or dim != gw().local_dimension:
		return
	SpellFx.play(gw(), spell, pos, dir, power, pts)
