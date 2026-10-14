extends Node
## Autoload "Net" — temporary shell; replaced by the LAN party system.

signal lobby_changed
signal session_started(info: Dictionary)
signal join_failed(reason: String)
signal peer_left(id: int, player_name: String)

var players := {}
var runes := PackedInt32Array()


func host_party(_player_name: String) -> PackedInt32Array:
	return PackedInt32Array()


func join_party(_runes: PackedInt32Array, _player_name: String) -> void:
	join_failed.emit("Multiplayer is not available yet.")


func leave() -> void:
	pass


func start_campaign(info: Dictionary) -> void:
	session_started.emit(info)


func is_online() -> bool:
	return false


func is_server() -> bool:
	return true


func my_id() -> int:
	return 1


func send_chat(_text: String) -> void:
	pass
