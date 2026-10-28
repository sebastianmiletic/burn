class_name MapShare
extends Node
## Co-op sharing for map markers (MapMarkers). Every peer sends the markers
## it chose to share to the host, which keeps one list per player and relays
## the whole set to everyone (late joiners ask for it). A player's markers
## leave the party with them. Lives under GameWorld at the same path on every
## peer (GameWorld adds it next to the ActivityDirector).

const NODE_NAME := &"MapShare"

var _by_peer := {}   # host only: peer id -> Array


func _init() -> void:
	name = NODE_NAME


func _ready() -> void:
	if multiplayer.has_multiplayer_peer():
		multiplayer.peer_disconnected.connect(_on_peer_left)
	if Net.is_online():
		_join.call_deferred()


func _join() -> void:
	if not is_inside_tree() or not Net.is_online():
		return
	if not Net.is_server():
		_hello.rpc_id(1)
	_send()


## Sends the local player's shared markers (after a change). Safe offline.
static func push(world: Object) -> void:
	var node := world.get_node_or_null(NodePath(NODE_NAME)) as MapShare if world is Node else null
	if node != null:
		node._send()


func _send() -> void:
	if not Net.is_online():
		return
	var markers := MapMarkers.of(get_parent())
	if markers == null:
		return
	var list := markers.shared_list()
	var me := UiContext.player()
	var who := str(me.get("display_name")) if me != null and me.get("display_name") != null else ""
	for m: Dictionary in list:
		m["owner"] = who
	if Net.is_server():
		_store(multiplayer.get_unique_id(), list)
	else:
		_submit.rpc_id(1, list)


@rpc("any_peer", "reliable")
func _hello() -> void:
	if multiplayer.is_server():
		_receive.rpc_id(multiplayer.get_remote_sender_id(), _by_peer)


@rpc("any_peer", "reliable")
func _submit(list: Array) -> void:
	if multiplayer.is_server():
		_store(multiplayer.get_remote_sender_id(), list.slice(0, MapMarkers.MAX))


@rpc("authority", "reliable")
func _receive(by_peer: Dictionary) -> void:
	var markers := MapMarkers.of(get_parent())
	if markers != null:
		markers.set_party(by_peer, multiplayer.get_unique_id())


func _store(peer: int, list: Array) -> void:
	if list.is_empty():
		_by_peer.erase(peer)
	else:
		_by_peer[peer] = list
	_relay()


func _relay() -> void:
	_receive(_by_peer)
	var w := get_parent()
	var rep: Variant = w.get("replicator") if w != null else null
	if rep == null:
		return
	for peer: int in (rep as Object).call("ready_peers"):
		_receive.rpc_id(peer, _by_peer)


func _on_peer_left(peer: int) -> void:
	if multiplayer.is_server() and _by_peer.has(peer):
		_by_peer.erase(peer)
		_relay()
