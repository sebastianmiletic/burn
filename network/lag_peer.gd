class_name LagPeer
extends MultiplayerPeerExtension
## Wraps a real MultiplayerPeer (ENet) and adds simulated network conditions
## for testing the netcode: every packet is held for `latency_ms` on the way
## out and again on the way in (so a client running at 150 ms sees a ~300 ms
## round trip to the host), and a fraction `loss` of UNRELIABLE packets is
## dropped in each direction. Reliable packets are never dropped and order
## is preserved (the delay is constant, queues are FIFO).
##
## Run it on clients only; enabling it on the host as well doubles the delay.

var inner: MultiplayerPeer
var latency_ms := 0.0
var loss := 0.0

var _in: Array = []   # [deliver_usec, peer, channel, mode, data]
var _out: Array = []  # [send_usec, target, channel, mode, data]
var _target := 0
var _mode := TRANSFER_MODE_RELIABLE
var _channel := 0
var _rng := RandomNumberGenerator.new()
var dropped_in := 0
var dropped_out := 0


func _init(wrapped: MultiplayerPeer, latency := 0.0, packet_loss := 0.0) -> void:
	inner = wrapped
	latency_ms = latency
	loss = packet_loss
	_rng.randomize()
	inner.peer_connected.connect(func(id: int) -> void: peer_connected.emit(id))
	inner.peer_disconnected.connect(func(id: int) -> void: peer_disconnected.emit(id))


func _delay_usec() -> int:
	return int(maxf(0.0, latency_ms) * 1000.0)


func _drop(mode: int) -> bool:
	return mode != TRANSFER_MODE_RELIABLE and loss > 0.0 and _rng.randf() < loss


func _poll() -> void:
	inner.poll()
	var now := Time.get_ticks_usec()
	while inner.get_available_packet_count() > 0:
		var peer := inner.get_packet_peer()
		var channel := inner.get_packet_channel()
		var mode := inner.get_packet_mode()
		var data := inner.get_packet()
		if _drop(mode):
			dropped_in += 1
			continue
		_in.append([now + _delay_usec(), peer, channel, mode, data])
	_flush_out(now)


func _flush_out(now: int) -> void:
	while not _out.is_empty() and int(_out[0][0]) <= now:
		var p: Array = _out.pop_front()
		inner.set_target_peer(p[1])
		inner.transfer_channel = p[2]
		inner.transfer_mode = p[3]
		inner.put_packet(p[4])


func _ready_count() -> int:
	var now := Time.get_ticks_usec()
	var n := 0
	for p: Array in _in:
		if int(p[0]) > now:
			break
		n += 1
	return n


func _get_available_packet_count() -> int:
	return _ready_count()


func _get_packet_script() -> PackedByteArray:
	if _ready_count() == 0:
		return PackedByteArray()
	var p: Array = _in.pop_front()
	return p[4]


func _get_packet_peer() -> int:
	return int(_in[0][1]) if not _in.is_empty() else 0


func _get_packet_channel() -> int:
	return int(_in[0][2]) if not _in.is_empty() else 0


func _get_packet_mode() -> TransferMode:
	return (int(_in[0][3]) if not _in.is_empty() else TRANSFER_MODE_RELIABLE) as TransferMode


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _drop(_mode):
		dropped_out += 1
		return OK
	_out.append([Time.get_ticks_usec() + _delay_usec(), _target, _channel, _mode, buffer])
	if latency_ms <= 0.0:
		_flush_out(Time.get_ticks_usec())
	return OK


func _get_max_packet_size() -> int:
	return 1 << 24


func _set_target_peer(peer: int) -> void:
	_target = peer


func _get_transfer_mode() -> TransferMode:
	return _mode


func _set_transfer_mode(mode: TransferMode) -> void:
	_mode = mode


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_connection_status() -> ConnectionStatus:
	return inner.get_connection_status()


func _get_unique_id() -> int:
	return inner.get_unique_id()


func _is_server() -> bool:
	return inner.get_unique_id() == 1


func _is_server_relay_supported() -> bool:
	return true


func _disconnect_peer(peer: int, force: bool) -> void:
	inner.disconnect_peer(peer, force)


func _close() -> void:
	_in.clear()
	_out.clear()
	inner.close()


func _is_refusing_new_connections() -> bool:
	return inner.refuse_new_connections


func _set_refuse_new_connections(enable: bool) -> void:
	inner.refuse_new_connections = enable
