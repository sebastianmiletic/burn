extends Node
## Test-only RPC endpoint at /root/NetProbe (added by net_harness.gd on every
## process) for measuring unreliable loss and reliable ordering.

var unreliable := {}      # sender -> count
var reliable_next := {}   # sender -> next expected sequence number
var reliable_bad := {}    # sender -> out-of-order count


@rpc("any_peer", "call_remote", "unreliable")
func probe_unreliable(_seq: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	unreliable[id] = int(unreliable.get(id, 0)) + 1


@rpc("any_peer", "call_remote", "reliable")
func probe_reliable(seq: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	var expect := int(reliable_next.get(id, 0))
	if seq != expect:
		reliable_bad[id] = int(reliable_bad.get(id, 0)) + 1
	reliable_next[id] = seq + 1
