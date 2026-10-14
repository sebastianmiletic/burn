class_name Entity
extends Node3D
## Base for everything that lives, moves and can be hit: players, NPCs,
## monsters, bosses.
##
## Authority: the server (the host, or the local machine in solo) runs
## `server_tick`, applies damage and decides deaths. Clients only show what
## the server's snapshots say (`apply_snapshot`), interpolating between them.
## The local player is the exception: it moves itself and reports its state.

signal died(entity: Entity)
signal damaged(entity: Entity, amount: float, source_id: int)

enum Team { PLAYERS, MONSTERS, NEUTRAL }

var net_id := 0
var kind := ""
var team := Team.MONSTERS
var dimension := 0
var max_health := 100.0
var health := 100.0
var dead := false
var display_name := ""
var hit_radius := 0.6
var hit_height := 1.8
var body := VoxelBody.new()
var yaw := 0.0
## Animation state replicated to clients (meaning is per entity type).
var anim := 0
var anim_time := 0.0
var invulnerable_until := 0.0
var burning := 0.0  ## seconds left on fire
var last_hit_by := 0

# Client-side interpolation buffer: [time, position, yaw]
var _snapshots: Array = []
const INTERP_DELAY := 0.1


func world() -> GameWorld:
	return GameWorld.instance


func voxels() -> VoxelWorld:
	var w := world()
	return w.world_for(dimension) if w != null else null


func is_server() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


func center() -> Vector3:
	return global_position + Vector3(0, hit_height * 0.5, 0)


func alive() -> bool:
	return not dead


## Server: apply damage. Returns the damage actually dealt.
func take_damage(amount: float, source_id := 0, damage_kind := "hit") -> float:
	if dead or amount <= 0.0:
		return 0.0
	var now := Time.get_ticks_msec() / 1000.0
	if now < invulnerable_until:
		return 0.0
	health = maxf(0.0, health - amount)
	last_hit_by = source_id
	damaged.emit(self, amount, source_id)
	_on_damaged(amount, source_id, damage_kind)
	if health <= 0.0:
		dead = true
		_on_died()
		died.emit(self)
	return amount


func heal(amount: float) -> void:
	if dead:
		return
	health = minf(max_health, health + amount)


func _on_damaged(_amount: float, _source_id: int, _kind: String) -> void:
	pass


func _on_died() -> void:
	pass


## Server-side simulation step; override in subclasses.
func server_tick(_delta: float) -> void:
	pass


## Snapshot sent to clients ~15 times a second.
func snapshot() -> Array:
	return [global_position, yaw, health, anim, anim_time, 1 if dead else 0, burning > 0.0]


func apply_snapshot(s: Array, at_time: float) -> void:
	_snapshots.append([at_time, s[0], s[1]])
	if _snapshots.size() > 12:
		_snapshots.pop_front()
	health = s[2]
	anim = s[3]
	anim_time = s[4]
	var was_dead := dead
	dead = s[5] == 1
	burning = 1.0 if s[6] else 0.0
	if dead and not was_dead:
		_on_died()


## Clients: place the entity INTERP_DELAY seconds in the past, between snapshots.
func interpolate(now: float) -> void:
	if _snapshots.is_empty():
		return
	var t := now - INTERP_DELAY
	var a: Array = _snapshots[0]
	var b: Array = _snapshots[_snapshots.size() - 1]
	for i in range(_snapshots.size() - 1):
		if _snapshots[i][0] <= t and _snapshots[i + 1][0] >= t:
			a = _snapshots[i]
			b = _snapshots[i + 1]
			break
	var span: float = b[0] - a[0]
	var f := clampf((t - a[0]) / span, 0.0, 1.0) if span > 0.0001 else 1.0
	global_position = (a[1] as Vector3).lerp(b[1], f)
	yaw = lerp_angle(a[2], b[2], f)
	rotation.y = yaw
