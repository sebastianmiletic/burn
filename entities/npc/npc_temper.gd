class_name NpcTemper
extends RefCounted
## A villager's temper (server side). Strike a villager and that one person,
## and nobody else, turns on you: they shout, chase you at a run and hit
## back with whatever they hold (guards with the spear, the smith with the
## hammer, everyone else with their fists). They cool off when you have kept
## your distance for a while, leave (out of reach, another dimension, down),
## or after a beating they yield. Then they go back to their day.
##
## Replicated through the Npc's `anim` (ANGRY flag) and entity events
## ("angered" / "calmed" with the player's net id) so every machine shows it
## and the striker's own record loses standing with the village.

const CALM_AFTER := 22.0        ## seconds since the last blow
const GIVE_UP_DISTANCE := 26.0  ## the striker got away
const REACH := 1.7
const SWING_EVERY := 1.35
const YIELD_DAMAGE := 90.0      ## a thrashing makes them back down
const REP_LOSS := 12

var target_id := 0
var since_hit := 0.0
var taken := 0.0
var _swing_cd := 0.6
var _rng := RandomNumberGenerator.new()


func active() -> bool:
	return target_id != 0


## Struck by `source_id` for `amount`.
func on_hit(npc: Npc, source_id: int, amount: float) -> void:
	var w: Object = npc._w()
	var src: Variant = w.call("entity", source_id) if w != null and w.has_method("entity") else null
	if src == null or not (src is Entity) or (src as Entity).team != Entity.Team.PLAYERS:
		return
	var first := target_id != source_id
	target_id = source_id
	since_hit = 0.0
	taken += amount
	_rng.seed = npc.npc_seed + Time.get_ticks_msec()
	if first:
		_swing_cd = 0.5
		npc.on_temper("angered", source_id)
	if taken >= YIELD_DAMAGE:
		calm(npc, true)


func calm(npc: Npc, yielded := false) -> void:
	if target_id == 0:
		return
	var who := target_id
	target_id = 0
	taken = 0.0
	npc.health = npc.max_health
	npc.on_temper("yielded" if yielded else "calmed", who)


## One server tick of a fight. Returns the wanted horizontal velocity.
func tick(npc: Npc, delta: float) -> Vector3:
	since_hit += delta
	_swing_cd -= delta
	var w: Object = npc._w()
	var t: Variant = w.call("entity", target_id) if w != null else null
	var foe := t as Entity
	if foe == null or not is_instance_valid(foe) or foe.dead or foe.dimension != npc.dimension:
		calm(npc)
		return Vector3.ZERO
	var to := foe.global_position - npc.global_position
	to.y = 0.0
	var dist := to.length()
	if since_hit > CALM_AFTER or dist > GIVE_UP_DISTANCE:
		calm(npc)
		return Vector3.ZERO
	npc.act = Npc.Act.FIGHT
	npc._turn_towards(atan2(-to.x, -to.z), delta * 2.0)
	if dist > REACH:
		var dir := to / maxf(dist, 0.001)
		var facing := -Vector3(sin(npc.yaw), 0, cos(npc.yaw))
		return dir * Npc.HURRY_SPEED * clampf(facing.dot(dir), 0.3, 1.0)
	if _swing_cd <= 0.0:
		_swing_cd = SWING_EVERY + _rng.randf() * 0.4
		npc.anim_time = npc._now()
		if w.has_method("damage"):
			w.call("damage", foe, damage_for(npc.role), npc.net_id, "hit")
	return Vector3.ZERO


static func damage_for(role: String) -> float:
	match role:
		"guard":
			return 14.0
		"blacksmith":
			return 11.0
		"elder", "chief":
			return 4.0
	return 6.0
