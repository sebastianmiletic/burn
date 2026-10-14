class_name GameWorld
extends Node3D
## TEMPORARY CONTRACT SHELL (creatures/combat worktree only) — discard on merge.
## Mirrors the documented API in docs/ARCHITECTURE.md so creature code compiles.
## Methods return neutral values; the integrator owns the real implementation.

static var instance: GameWorld

var local_player: Entity
var view: AsciiView
var local_dimension := 0


func world_for(_dim: int) -> VoxelWorld:
	return null


func locations(_dim: int) -> Array[Location]:
	return []


func location_at(_pos: Vector3, _dim: int) -> Location:
	return null


func entities_near(_pos: Vector3, _radius: float, _dim: int, _team := -1) -> Array[Entity]:
	return []


func players_in(_dim: int) -> Array[Entity]:
	return []


func nearest_player(_pos: Vector3, _dim: int, _max_dist: float) -> Entity:
	return null


func spawn_entity(_kind: String, _pos: Vector3, _dim: int, _data := {}) -> Entity:
	return null


func despawn_entity(_e: Entity) -> void:
	pass


func damage(_target: Entity, _amount: float, _source_id: int, _kind := "hit") -> void:
	pass


func spawn_projectile(_kind: String, _origin: Vector3, _velocity: Vector3, _owner_id: int, _team: int, _dim: int, _damage: float) -> void:
	pass


func telegraph(_shape: String, _pos: Vector3, _dir: Vector3, _size: Vector3, _duration: float, _dim: int) -> void:
	pass


func drop_item(_pos: Vector3, _item_id: String, _count: int, _dim: int) -> void:
	pass


func boss_started(_boss: Boss) -> void:
	pass


func boss_finished(_boss: Boss) -> void:
	pass


func shake(_strength: float) -> void:
	pass


func request_attack(_targets: Array[int], _amount: float, _kind: String) -> void:
	pass


func request_set_block(_pos: Vector3i, _block: int, _dim: int) -> void:
	pass
