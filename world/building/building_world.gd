class_name BuildingWorld
extends Node3D
## Player-built pieces and every storage container, on every peer. Lives at
## /root/GameWorld/Building so its RPCs resolve everywhere.
##
## * Pieces (BuildPieces / PieceMesh): the server validates and places them,
##   then every peer adds the same record, draws it and writes its collision
##   (Blocks.STRUCTURE in the solid cells that were open air). Doors, gates and
##   trapdoors toggle server-side; strikes with a tool wear pieces down and a
##   destroyed piece drops its own item back (full salvage). Saved with the world.
## * Containers: chests and barrels the players build ("p<id>") and the loot
##   chests of mines, wrecks and ruins ("c:<chest key>") share one server-side
##   store and ContainerScreen. Any number of players may look into one at a
##   time; every change is pushed to everyone looking. Breaking a built chest
##   spills its contents onto the ground (the chest item itself is returned
##   empty), so nothing is ever lost inside an item.
## * The local player's placement ghost (green = fits, red = blocked).

signal container_changed

const REACH := 6.0
const STRIKE_TIME := 0.45
const MAX_PIECES := 6000

## id -> {kind, mat, anchor: Vector3i, rot, dim, hp, state, ground: Array[Vector3i]}
var pieces := {}
var _cells := {}           # dim -> {Vector3i: id}
var _nodes := {}           # id -> Node3D
var _next_id := 1
var _shown_dim := -1

## Server: container key -> Array of slot dictionaries; viewers per key.
var containers := {}
var _viewers := {}         # key -> {peer: true}

## Client: the container this player has open.
var open_key := ""
var open_slots: Array = []
var open_title := ""
var open_pos := Vector3.ZERO

var _ghost: Node3D
var _ghost_key := ""
var _ghost_ok := false
var _ghost_place := {}
var _user_rot := 0
var _strike_cd := 0.0
var _focus_id := 0
var _hint_shown := false
var _ghost_mat_ok: StandardMaterial3D
var _ghost_mat_bad: StandardMaterial3D


func gw() -> GameWorld:
	return get_parent() as GameWorld


func _ready() -> void:
	name = "Building"
	var w := gw()
	if w != null and w.has_signal("ready_to_play"):
		w.ready_to_play.connect(_on_ready_to_play)


func _on_ready_to_play() -> void:
	if Net.is_online() and not Net.is_server():
		_rq_sync.rpc_id(1)


# --- Queries -------------------------------------------------------------------------------

func piece_at(cell: Vector3i, dim: int) -> int:
	return int(_cells.get(dim, {}).get(cell, 0))


func piece_transform(id: int) -> Transform3D:
	var p: Dictionary = pieces[id]
	return BuildPieces.transform(p["kind"], p["anchor"], p["rot"])


func piece_aabb(id: int) -> AABB:
	var p: Dictionary = pieces[id]
	var model := PieceMesh.get_model(p["kind"], p["mat"])
	var local: AABB = model.get("aabb", AABB(Vector3.ZERO, Vector3(BuildPieces.size_of(p["kind"]))))
	if local.size == Vector3.ZERO:
		local = AABB(Vector3.ZERO, Vector3(BuildPieces.size_of(p["kind"])))
	return piece_transform(id) * local.grow(0.04)


func piece_center(id: int) -> Vector3:
	return piece_aabb(id).get_center()


## The nearest piece a ray hits within `max_dist`: {id, distance, point} or {}.
func pick(origin: Vector3, dir: Vector3, max_dist: float, dim: int) -> Dictionary:
	var index: Dictionary = _cells.get(dim, {})
	if index.is_empty():
		return {}
	var seen := {}
	var best := {}
	var t := 0.0
	while t <= max_dist + 1.0:
		var c := Vector3i((origin + dir * t).floor())
		for dz in range(-1, 2):
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var id := int(index.get(c + Vector3i(dx, dy, dz), 0))
					if id == 0 or seen.has(id):
						continue
					seen[id] = true
					var hit: Variant = piece_aabb(id).intersects_ray(origin, dir)
					if hit == null:
						continue
					var d := origin.distance_to(hit)
					if d <= max_dist and (best.is_empty() or d < float(best["distance"])):
						best = {"id": id, "distance": d, "point": hit}
		if not best.is_empty() and t > float(best["distance"]) + 1.5:
			break
		t += 0.5
	return best


## Reason a piece cannot go here ("" = it fits). `who` (server) is the placer.
func placement_problem(kind: String, anchor: Vector3i, rot: int, dim: int, who: Player = null) -> String:
	var w := gw()
	var vw := w.world_for(dim) if w != null else null
	if vw == null or not BuildPieces.PIECES.has(kind):
		return "Nothing to build on."
	if pieces.size() >= MAX_PIECES:
		return "This world holds as much building as it can."
	var p: Dictionary = BuildPieces.PIECES[kind]
	var ground_ok := bool(p.get("ground", false))
	var cells := BuildPieces.cells(kind, anchor, rot)
	var index: Dictionary = _cells.get(dim, {})
	var air := 0
	var supported := false
	var mine := {}
	for e: Array in cells:
		mine[e[0]] = true
	for e: Array in cells:
		var c: Vector3i = e[0]
		if index.has(c):
			return "Something is already built there."
		var b := vw.get_block(c)
		if b < 0:
			return "Too far away."
		if b == Blocks.AIR:
			air += 1
		elif ground_ok and Blocks.is_smooth(b):
			supported = true
		else:
			return "Blocked."
		if bool(e[1]):
			for pl in w.players_in(dim):
				if pl.body.overlaps_block(pl.global_position, c):
					return "Someone is standing there."
	if air == 0:
		return "Blocked."
	# Support: touching the ground, another piece or solid rock.
	if not supported:
		for e: Array in cells:
			var c: Vector3i = e[0]
			for o: Vector3i in [Vector3i.DOWN, Vector3i.UP, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
				var n := c + o
				if mine.has(n):
					continue
				if index.has(n):
					supported = true
					break
				var nb := vw.get_block(n)
				if nb > 0 and Blocks.is_solid(nb) and (o == Vector3i.DOWN or not ground_ok):
					supported = true
					break
			if supported:
				break
	if not supported:
		return "It needs something to stand on." if ground_ok else "It needs a wall, floor or ground to rest on."
	if who != null:
		var centre := Vector3(anchor) + Vector3(BuildPieces.footprint(kind, rot)) * 0.5
		if centre.distance_to(who.global_position + Vector3(0, 1.2, 0)) > REACH + 2.5:
			return "Too far away."
	return ""


# --- Placing (client) ---------------------------------------------------------------------

func _held_piece(p: Player) -> Array:
	if p == null or p.inventory == null:
		return []
	return BuildPieces.parse(p.inventory.selected_item())


## Where the held piece would go from the player's view: {kind, mat, anchor, rot} or {}.
func _aim_placement(p: Player, kind: String, mat: String) -> Dictionary:
	var ray := p.camera.aim_ray()
	var origin: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	var reach := REACH + (0.0 if p.camera.first_person else p.camera.distance)
	var vw := p.voxels()
	var hit := vw.raycast(origin, dir, reach)
	var ph := pick(origin, dir, reach, p.dimension)
	var cell := Vector3i.ZERO
	var n := Vector3i.UP
	var align := Vector3i.ZERO
	if not ph.is_empty() and (hit.is_empty() or float(ph["distance"]) <= float(hit["distance"]) + 0.3):
		var id := int(ph["id"])
		var box := piece_aabb(id)
		var pt: Vector3 = ph["point"]
		n = _face_normal(box, pt)
		cell = Vector3i((pt + Vector3(n) * 0.5).floor())
		align = pieces[id]["anchor"]
	elif not hit.is_empty():
		n = hit["normal"]
		if n == Vector3i.ZERO:
			n = Vector3i.UP
		cell = hit["pos"] + n
	else:
		return {}
	var spec: Dictionary = BuildPieces.PIECES[kind]
	var fwd := Vector3(sin(p.camera.yaw), 0, cos(p.camera.yaw))
	var rot := posmod(BuildPieces.rot_facing(fwd) + _user_rot, 4)
	if spec.get("mount", false) and n.y == 0:
		rot = BuildPieces.rot_facing(Vector3(n))
	var anchor := BuildPieces.anchor_for(kind, rot, cell, n, align)
	return {"kind": kind, "mat": mat, "anchor": anchor, "rot": rot}


static func _face_normal(box: AABB, pt: Vector3) -> Vector3i:
	var best := Vector3i.UP
	var best_d := INF
	for axis in 3:
		for s: int in [-1, 1]:
			var plane := box.position[axis] + (box.size[axis] if s > 0 else 0.0)
			var d := absf(pt[axis] - plane)
			if d < best_d:
				best_d = d
				best = Vector3i.ZERO
				best[axis] = s
	return best


## Player input hook: R turns the held piece. True when consumed.
func handle_input(p: Player, event: InputEvent) -> bool:
	if _held_piece(p).is_empty():
		return false
	if event.is_action_pressed("ability_burst"):
		_user_rot = posmod(_user_rot + 1, 4)
		Audio.play_ui("ui_hover")
		return true
	return false


## Player "use" hook: places the held piece. True when the held item is a piece.
func try_place(p: Player) -> bool:
	var held := _held_piece(p)
	if held.is_empty():
		return false
	var place := _aim_placement(p, held[0], held[1])
	if place.is_empty():
		return true
	var why := placement_problem(place["kind"], place["anchor"], place["rot"], p.dimension)
	if why != "":
		Events.notify.emit(why, "warn")
		return true
	var item := p.inventory.selected_item()
	p.inventory.remove_from_slot(p.inventory.selected, 1)
	request_place(place["kind"], place["mat"], place["anchor"], place["rot"], p.dimension, item)
	if gw().quests != null:
		gw().quests.on_event("place", item)
	Audio.play("block_place", Vector3(place["anchor"]) + Vector3(0.5, 0.5, 0.5))
	p._start_action("interact", 0.25)
	return true


## Player mining hook: a tool swung at a piece wears it down. True when aimed at one.
func try_strike(p: Player, delta: float) -> bool:
	_strike_cd = maxf(0.0, _strike_cd - delta)
	var info := p.inventory.selected_info()
	if info.get("category", "") != "tool" or not p._input_enabled or not Settings.action_held("attack"):
		return false
	var ray := p.camera.aim_ray()
	var reach := REACH - 1.5 + (0.0 if p.camera.first_person else p.camera.distance)
	var ph := pick(ray[0], ray[1], reach, p.dimension)
	if ph.is_empty():
		return false
	var hit := p.voxels().raycast(ray[0], ray[1], reach)
	if not hit.is_empty() and float(hit["distance"]) < float(ph["distance"]) - 0.4 and pieces[int(ph["id"])]["kind"] != "door":
		return false
	if _strike_cd > 0.0:
		return true
	_strike_cd = STRIKE_TIME
	p._start_action("mine", STRIKE_TIME)
	var id := int(ph["id"])
	var fam := String(BuildPieces.MATS.get(pieces[id]["mat"], {}).get("family", "wood"))
	Audio.play("pick_wood" if fam == "wood" else "pick_stone", ph["point"], -3.0, randf_range(0.85, 1.15))
	var w := gw()
	if w.fx != null:
		w.fx.debris(ph["point"], -Vector3(ray[1]), Color(0.55, 0.42, 0.3) if fam == "wood" else Color(0.6, 0.58, 0.55), false)
	p.camera.add_trauma(0.03)
	_focus_id = id
	request_strike(id, p.inventory.selected_item())
	return true


## Player interaction hook: the piece aimed at that can be used (door, bed,
## container), as a Node for the prompt (this node), else null.
func interact_target(p: Player) -> Node:
	var ray := p.camera.aim_ray()
	var ph := pick(ray[0], ray[1], 3.6 + (0.0 if p.camera.first_person else p.camera.distance), p.dimension)
	if ph.is_empty():
		return null
	var id := int(ph["id"])
	if BuildPieces.use_of(pieces[id]["kind"]) == "":
		return null
	if piece_center(id).distance_to(p.global_position + Vector3(0, 1.0, 0)) > 4.5:
		return null
	_focus_id = id
	return self


func interact_prompt(_p: Node) -> String:
	if not pieces.has(_focus_id):
		return ""
	var pc: Dictionary = pieces[_focus_id]
	var name_ := BuildPieces.display_name(pc["kind"], pc["mat"])
	match BuildPieces.use_of(pc["kind"]):
		"door":
			return ("Close " if int(pc["state"]) == 1 else "Open ") + name_
		"bed":
			return "Rest (set your spawn here)"
		"container":
			return "Open " + name_
	return ""


func local_interact(p: Node) -> void:
	if not pieces.has(_focus_id):
		return
	var pc: Dictionary = pieces[_focus_id]
	match BuildPieces.use_of(pc["kind"]):
		"door":
			request_toggle(_focus_id)
		"bed":
			var pl := p as Player
			if pl != null:
				pl.respawn_point = piece_center(_focus_id) + Vector3(0, 0.6, 0)
				pl.respawn_dimension = int(pc["dim"])
				Events.notify.emit("You will wake here when you fall.", "info")
				Audio.play("chest", piece_center(_focus_id), -12.0, 0.7)
		"container":
			request_open("p%d" % _focus_id, BuildPieces.display_name(pc["kind"], ""))


# --- Ghost ---------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	var w := gw()
	if w == null or w.local_player == null:
		return
	if _shown_dim != w.local_dimension:
		_shown_dim = w.local_dimension
		for id: int in _nodes:
			(_nodes[id] as Node3D).visible = int(pieces[id]["dim"]) == _shown_dim
	_update_ghost(w.local_player)
	if open_key != "" and w.local_player.global_position.distance_to(open_pos) > 6.0:
		close_container()


func _update_ghost(p: Player) -> void:
	var held := _held_piece(p) if not p.dead and p._input_enabled else []
	if held.is_empty():
		if _ghost != null:
			_ghost.visible = false
		return
	if not _hint_shown:
		_hint_shown = true
		Events.notify.emit("Building: right-click to place, R to turn it. Strike a piece with a pick-axe or axe to take it down.", "info")
	var place := _aim_placement(p, held[0], held[1])
	if place.is_empty():
		if _ghost != null:
			_ghost.visible = false
		return
	var key := "%s|%s" % [held[0], held[1]]
	if _ghost == null or _ghost_key != key:
		if _ghost != null:
			_ghost.queue_free()
		_ghost = _build_visual(held[0], held[1], true)
		_ghost_key = key
		add_child(_ghost)
	var ok := placement_problem(place["kind"], place["anchor"], place["rot"], p.dimension) == ""
	_ghost.visible = true
	_ghost.transform = BuildPieces.transform(place["kind"], place["anchor"], place["rot"])
	if ok != _ghost_ok or _ghost_place.is_empty():
		_ghost_ok = ok
		_tint_ghost(_ghost, ok)
	_ghost_place = place


func _ghost_material(ok: bool) -> StandardMaterial3D:
	if _ghost_mat_ok == null:
		for good: bool in [true, false]:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.35, 1.0, 0.45, 0.32) if good else Color(1.0, 0.25, 0.2, 0.34)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.no_depth_test = false
			if good:
				_ghost_mat_ok = m
			else:
				_ghost_mat_bad = m
	return _ghost_mat_ok if ok else _ghost_mat_bad


func _tint_ghost(n: Node, ok: bool) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).material_override = _ghost_material(ok)
			(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_tint_ghost(c, ok)


# --- Visuals -------------------------------------------------------------------------------

func _build_visual(kind: String, mat: String, ghost := false) -> Node3D:
	var root := Node3D.new()
	var model := PieceMesh.get_model(kind, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = model["mesh"]
	mi.visibility_range_end = 240.0
	root.add_child(mi)
	var leaves: Array = []
	for leaf: Dictionary in model["leaves"]:
		var pivot := Node3D.new()
		pivot.position = leaf["pivot"]
		pivot.set_meta("axis", leaf["axis"])
		pivot.set_meta("open", leaf["open"])
		var lm := MeshInstance3D.new()
		lm.mesh = leaf["mesh"]
		lm.visibility_range_end = 160.0
		pivot.add_child(lm)
		root.add_child(pivot)
		leaves.append(pivot)
	root.set_meta("leaves", leaves)
	if not ghost:
		for f: Vector3 in model["fires"]:
			ArchMaterials.fire(root, f, 0.45, 8.0, 1.3)
		for l: Vector3 in model["lights"]:
			var light := OmniLight3D.new()
			light.position = l
			light.light_color = Color(1.0, 0.66, 0.34)
			light.light_energy = 1.3
			light.omni_range = 10.0
			light.distance_fade_enabled = true
			light.distance_fade_begin = 50.0
			light.distance_fade_length = 15.0
			root.add_child(light)
	return root


func _set_leaves(id: int, open: bool, animate: bool) -> void:
	var n: Node3D = _nodes.get(id)
	if n == null:
		return
	for pivot: Node3D in n.get_meta("leaves", []):
		var axis: Vector3 = pivot.get_meta("axis")
		var target := Basis(axis, float(pivot.get_meta("open")) if open else 0.0)
		if not animate:
			pivot.basis = target
			continue
		var from := pivot.basis.get_rotation_quaternion()
		var to := target.get_rotation_quaternion()
		var tw := pivot.create_tween()
		tw.tween_method(func(t: float) -> void: pivot.basis = Basis(from.slerp(to, t)), 0.0, 1.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# --- Records (every peer) ---------------------------------------------------------------------

func _record_to_array(id: int) -> Array:
	var p: Dictionary = pieces[id]
	return [id, p["kind"], p["mat"], p["anchor"], p["rot"], p["dim"], p["hp"], p["state"], p["ground"]]


func _add_record(a: Array, animate := false) -> void:
	var id := int(a[0])
	if pieces.has(id):
		_remove_record(id, false)
	var kind := String(a[1])
	if not BuildPieces.PIECES.has(kind):
		return
	var ground: Array = a[8] if a.size() > 8 else []
	var rec := {"kind": kind, "mat": String(a[2]), "anchor": a[3] as Vector3i, "rot": int(a[4]), "dim": int(a[5]),
			"hp": float(a[6]), "state": int(a[7]), "ground": ground}
	pieces[id] = rec
	_next_id = maxi(_next_id, id + 1)
	if not _cells.has(rec["dim"]):
		_cells[rec["dim"]] = {}
	for e: Array in BuildPieces.cells(kind, rec["anchor"], rec["rot"]):
		_cells[rec["dim"]][e[0]] = id
	_write_collision(id)
	var node := _build_visual(kind, rec["mat"])
	node.transform = piece_transform(id)
	node.visible = gw() == null or int(rec["dim"]) == gw().local_dimension
	add_child(node)
	_nodes[id] = node
	_set_leaves(id, int(rec["state"]) == 1, false)
	if animate and node.is_inside_tree():
		var s := node.scale
		node.scale = s * 0.92
		node.create_tween().tween_property(node, "scale", s, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _remove_record(id: int, clear := true) -> void:
	if not pieces.has(id):
		return
	var rec: Dictionary = pieces[id]
	if clear:
		_write_collision(id, true)
	var index: Dictionary = _cells.get(rec["dim"], {})
	for e: Array in BuildPieces.cells(rec["kind"], rec["anchor"], rec["rot"]):
		if int(index.get(e[0], 0)) == id:
			index.erase(e[0])
	pieces.erase(id)
	var n: Node3D = _nodes.get(id)
	if n != null:
		n.queue_free()
	_nodes.erase(id)


## Writes the piece's collision for its state (or clears it).
func _write_collision(id: int, clear := false) -> void:
	var rec: Dictionary = pieces[id]
	var vw := gw().world_for(rec["dim"]) if gw() != null else null
	if vw == null:
		return
	var ground := {}
	for g: Variant in rec["ground"]:
		ground[g] = true
	var batch := PackedInt32Array()
	for e: Array in BuildPieces.cells(rec["kind"], rec["anchor"], rec["rot"], int(rec["state"])):
		var c: Vector3i = e[0]
		if ground.has(c):
			continue
		var block := Blocks.STRUCTURE if bool(e[1]) and not clear else Blocks.AIR
		var cur := vw.get_block(c)
		if cur == block or (cur > 0 and cur != Blocks.STRUCTURE and cur != Blocks.AIR):
			continue
		batch.append_array([c.x, c.y, c.z, block, 0 if block == Blocks.AIR else -1])
	if not batch.is_empty():
		vw.set_voxels(batch)


# --- Network: pieces ------------------------------------------------------------------------

func _targets() -> Array:
	var w := gw()
	return w.replicator.ready_peers() if w != null and w.replicator != null else []


func _broadcast(method: StringName, args: Array) -> void:
	callv(method, args)
	if not Net.is_online():
		return
	for peer: int in _targets():
		callv("rpc_id", [peer, method] + args)


func request_place(kind: String, mat: String, anchor: Vector3i, rot: int, dim: int, item := "") -> void:
	if Net.is_server():
		_place_on_server(Net.my_id(), kind, mat, anchor, rot, dim, item)
	else:
		_rq_place.rpc_id(1, kind, mat, anchor, rot, dim, item)


@rpc("any_peer", "reliable")
func _rq_place(kind: String, mat: String, anchor: Vector3i, rot: int, dim: int, item: String) -> void:
	if multiplayer.is_server():
		_place_on_server(multiplayer.get_remote_sender_id(), kind, mat, anchor, rot, dim, item)


func _place_on_server(peer: int, kind: String, mat: String, anchor: Vector3i, rot: int, dim: int, item: String) -> void:
	var w := gw()
	var p := w.entity(Replicator.player_net_id(peer)) as Player
	var refund := BuildPieces.item_id(kind, mat)
	if p == null or p.dead or p.dimension != dim or not BuildPieces.PIECES.has(kind) or BuildPieces.parse(refund).is_empty():
		return
	var why := placement_problem(kind, anchor, posmod(rot, 4), dim, p)
	if why != "":
		# Lost the race (or out of reach): give the piece back.
		w.replicator.give_item_to(peer, refund, 1)
		return
	var ground: Array = []
	var vw := w.world_for(dim)
	for e: Array in BuildPieces.cells(kind, anchor, posmod(rot, 4)):
		if vw.get_block(e[0]) != Blocks.AIR:
			ground.append(e[0])
	var id := _next_id
	_next_id += 1
	_broadcast(&"_added", [[id, kind, mat, anchor, posmod(rot, 4), dim, BuildPieces.max_hp(kind, mat), 0, ground]])
	if BuildPieces.use_of(kind) == "container":
		var slots := []
		slots.resize(BuildPieces.container_slots(kind))
		slots.fill({})
		containers["p%d" % id] = slots


@rpc("authority", "reliable")
func _added(a: Array) -> void:
	_add_record(a, true)


func request_strike(id: int, item: String) -> void:
	if Net.is_server():
		_strike_on_server(Net.my_id(), id, item)
	else:
		_rq_strike.rpc_id(1, id, item)


@rpc("any_peer", "reliable")
func _rq_strike(id: int, item: String) -> void:
	if multiplayer.is_server():
		_strike_on_server(multiplayer.get_remote_sender_id(), id, item)


## Damage a tool strike does to a piece of `mat` (pick-axes bite stone, axes wood).
static func strike_damage(item: String, mat: String) -> float:
	var info := ItemDB.info(item)
	var tier := int(info.get("mine_tier", 1))
	var fam := String(BuildPieces.MATS.get(mat, {}).get("family", "wood"))
	var kind := String(info.get("kind", ""))
	var bonus := 1.0
	if (fam == "stone" and kind == "pickaxe") or (fam == "wood" and kind == "axe"):
		bonus = 1.5
	return (22.0 + tier * 9.0) * bonus


func _strike_on_server(peer: int, id: int, item: String) -> void:
	var w := gw()
	var p := w.entity(Replicator.player_net_id(peer)) as Player
	if p == null or p.dead or not pieces.has(id) or ItemDB.category(item) != "tool":
		return
	var rec: Dictionary = pieces[id]
	if int(rec["dim"]) != p.dimension or piece_center(id).distance_to(p.global_position) > REACH + 3.0:
		return
	var hp := float(rec["hp"]) - strike_damage(item, rec["mat"])
	if hp > 0.0:
		_broadcast(&"_hp", [id, hp])
		return
	destroy_piece(id, true)


## Server: removes a piece; `salvage` drops its item (and spills a container).
func destroy_piece(id: int, salvage: bool) -> void:
	if not pieces.has(id):
		return
	var w := gw()
	var rec: Dictionary = pieces[id]
	var at := piece_center(id)
	var key := "p%d" % id
	if containers.has(key):
		for s: Dictionary in containers[key]:
			if not s.is_empty():
				w.drop_item(at + Vector3(0, 0.4, 0), String(s["id"]), int(s["count"]), rec["dim"])
		containers.erase(key)
		for peer: int in _viewers.get(key, {}):
			_closed_for(peer, key)
		_viewers.erase(key)
	if salvage:
		w.drop_item(at, BuildPieces.item_id(rec["kind"], rec["mat"]), 1, rec["dim"])
	_broadcast(&"_removed", [id])


@rpc("authority", "reliable")
func _hp(id: int, hp: float) -> void:
	if not pieces.has(id):
		return
	pieces[id]["hp"] = hp
	if id == _focus_id:
		var rec: Dictionary = pieces[id]
		Events.mining_progress.emit(1.0 - hp / maxf(1.0, BuildPieces.max_hp(rec["kind"], rec["mat"])))
		get_tree().create_timer(0.8).timeout.connect(func() -> void:
			if _strike_cd <= 0.0:
				Events.mining_progress.emit(-1.0))


@rpc("authority", "reliable")
func _removed(id: int) -> void:
	if not pieces.has(id):
		return
	var rec: Dictionary = pieces[id]
	var at := piece_center(id)
	var fam := String(BuildPieces.MATS.get(rec["mat"], {}).get("family", "wood"))
	if gw() != null and int(rec["dim"]) == gw().local_dimension:
		Audio.play("break_wood" if fam == "wood" else "break_stone", at)
		if gw().fx != null:
			gw().fx.debris(at, Vector3.UP, Color(0.55, 0.42, 0.3) if fam == "wood" else Color(0.6, 0.58, 0.55), true)
	_remove_record(id)
	if id == _focus_id:
		Events.mining_progress.emit(-1.0)
	if open_key == "p%d" % id:
		_close_local()


func request_toggle(id: int) -> void:
	if Net.is_server():
		_toggle_on_server(Net.my_id(), id)
	else:
		_rq_toggle.rpc_id(1, id)


@rpc("any_peer", "reliable")
func _rq_toggle(id: int) -> void:
	if multiplayer.is_server():
		_toggle_on_server(multiplayer.get_remote_sender_id(), id)


func _toggle_on_server(peer: int, id: int) -> void:
	var w := gw()
	var p := w.entity(Replicator.player_net_id(peer)) as Player
	if p == null or p.dead or not pieces.has(id) or BuildPieces.use_of(pieces[id]["kind"]) != "door":
		return
	var rec: Dictionary = pieces[id]
	if int(rec["dim"]) != p.dimension or piece_center(id).distance_to(p.global_position) > REACH:
		return
	var next := 1 - int(rec["state"])
	if next == 0:
		# Never shut a door on someone standing in it.
		for e: Array in BuildPieces.cells(rec["kind"], rec["anchor"], rec["rot"], 0):
			if bool(e[1]):
				for pl in w.players_in(int(rec["dim"])):
					if pl.body.overlaps_block(pl.global_position, e[0]):
						return
	_broadcast(&"_state", [id, next])


@rpc("authority", "reliable")
func _state(id: int, state: int) -> void:
	if not pieces.has(id):
		return
	pieces[id]["state"] = state
	_write_collision(id)
	_set_leaves(id, state == 1, true)
	var rec: Dictionary = pieces[id]
	if gw() != null and int(rec["dim"]) == gw().local_dimension:
		var c := piece_center(id)
		match rec["kind"]:
			"chest", "chest_iron", "barrel":
				Audio.play("chest", c, -6.0, 1.0 if state == 1 else 0.85)
			_:
				Audio.play("door", c, -4.0, 1.0 if state == 1 else 0.9)


@rpc("any_peer", "reliable")
func _rq_sync() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var all: Array = []
	for id: int in pieces:
		all.append(_record_to_array(id))
	# In slices so no single packet grows huge.
	var i := 0
	while i < all.size():
		_sync.rpc_id(peer, all.slice(i, i + 200))
		i += 200


@rpc("authority", "reliable")
func _sync(list: Array) -> void:
	for a: Array in list:
		_add_record(a)


# --- Containers ---------------------------------------------------------------------------------

## Opens container `key` for the local player (piece "p<id>" or loot chest "c:<key>").
func request_open(key: String, title: String) -> void:
	open_title = title
	if Net.is_server():
		_open_on_server(Net.my_id(), key, title)
	else:
		_rq_open.rpc_id(1, key, title)


@rpc("any_peer", "reliable")
func _rq_open(key: String, title: String) -> void:
	if multiplayer.is_server():
		_open_on_server(multiplayer.get_remote_sender_id(), key, title)


## Server: the world position of a container, or Vector3.INF when it does not exist.
func _container_pos(key: String) -> Vector3:
	if key.begins_with("p"):
		var id := int(key.substr(1))
		return piece_center(id) if pieces.has(id) else Vector3.INF
	var chest := _loot_chest(key)
	return chest.global_position if chest != null else Vector3.INF


func _loot_chest(key: String) -> Chest:
	if not key.begins_with("c:"):
		return null
	for e in gw().all_entities():
		if e is Chest and (e as Chest).chest_key == key.substr(2):
			return e
	return null


func _open_on_server(peer: int, key: String, title: String) -> void:
	var w := gw()
	var p := w.entity(Replicator.player_net_id(peer)) as Player
	if p == null or p.dead:
		return
	var at := _container_pos(key)
	if at == Vector3.INF or at.distance_to(p.global_position) > REACH:
		return
	if not containers.has(key):
		if not key.begins_with("c:"):
			return
		containers[key] = _loot_chest(key).fill_loot(peer)
	if not _viewers.has(key):
		_viewers[key] = {}
	var first: bool = (_viewers[key] as Dictionary).is_empty()
	_viewers[key][peer] = true
	_send_contents(peer, key, title, at)
	if first:
		_lid(key, true)


func _lid(key: String, open: bool) -> void:
	var w := gw()
	if key.begins_with("p"):
		var id := int(key.substr(1))
		if pieces.has(id):
			_broadcast(&"_state", [id, 1 if open else 0])
	else:
		var chest := _loot_chest(key)
		if chest != null:
			w.replicator.broadcast_entity_event(chest.net_id, "lid", open)


func _send_contents(peer: int, key: String, title: String, at: Vector3) -> void:
	if peer == Net.my_id() or not Net.is_online():
		_contents(key, containers[key], title, at)
	else:
		_contents.rpc_id(peer, key, containers[key], title, at)


func _push(key: String) -> void:
	for peer: int in _viewers.get(key, {}):
		_send_contents(peer, key, "", _container_pos(key))


@rpc("authority", "reliable")
func _contents(key: String, slots: Array, title: String, at: Vector3) -> void:
	var was_open := open_key == key
	open_key = key
	open_slots = slots.duplicate(true)
	open_pos = at
	if title != "":
		open_title = title
	container_changed.emit()
	if not was_open:
		var screen := get_tree().get_first_node_in_group(&"container_screen")
		if screen == null:
			var hud := gw().hud
			if hud != null:
				screen = ContainerScreen.new()
				hud.add_child(screen)
		if screen != null:
			screen.call("open_container")


func close_container() -> void:
	if open_key == "":
		return
	var key := open_key
	_close_local()
	if Net.is_server():
		_close_on_server(Net.my_id(), key)
	else:
		_rq_close.rpc_id(1, key)


func _close_local() -> void:
	open_key = ""
	open_slots = []
	container_changed.emit()
	var screen := get_tree().get_first_node_in_group(&"container_screen")
	if screen != null and bool(screen.get("is_open")):
		screen.call("close")


@rpc("any_peer", "reliable")
func _rq_close(key: String) -> void:
	if multiplayer.is_server():
		_close_on_server(multiplayer.get_remote_sender_id(), key)


func _close_on_server(peer: int, key: String) -> void:
	if not _viewers.has(key):
		return
	(_viewers[key] as Dictionary).erase(peer)
	if (_viewers[key] as Dictionary).is_empty():
		_viewers.erase(key)
		_lid(key, false)


func _closed_for(peer: int, _key: String) -> void:
	if peer == Net.my_id() or not Net.is_online():
		_close_local()


## Client: moves `count` from container slot `slot` into the player's pack
## (`to` = preferred pack slot, -1 = anywhere).
func take(slot: int, count := -1, to := -1) -> void:
	if open_key == "":
		return
	_op({"op": "take", "slot": slot, "count": count, "to": to})


## Client: puts the stack in pack slot `from` (all or `count`) into container slot `slot` (-1 = anywhere).
func put(from: int, slot := -1, count := -1) -> void:
	var p := gw().local_player
	if open_key == "" or p == null:
		return
	var s := p.inventory.get_slot(from)
	if s.is_empty():
		return
	var n := int(s["count"]) if count < 0 else mini(count, int(s["count"]))
	var stack := s.duplicate()
	stack["count"] = n
	if Inventory.is_equip_index(from):
		return
	p.inventory.remove_from_slot(from, n)
	_op({"op": "put", "slot": slot, "stack": stack})


func move(from: int, to: int) -> void:
	_op({"op": "move", "from": from, "to": to})


func take_all() -> void:
	_op({"op": "take_all"})


## Client: everything in the pack (not the three held slots) goes in.
func deposit_all() -> void:
	var p := gw().local_player
	if open_key == "" or p == null:
		return
	var stacks: Array = []
	for i in range(Inventory.HOTBAR, Inventory.HOTBAR + Inventory.BAG):
		var s := p.inventory.get_slot(i)
		if not s.is_empty():
			stacks.append(s.duplicate())
			p.inventory.slots[i] = {}
	if stacks.is_empty():
		return
	p.inventory.changed.emit()
	_op({"op": "put_many", "stacks": stacks})


func sort_container() -> void:
	_op({"op": "sort"})


func _op(op: Dictionary) -> void:
	if Net.is_server():
		_op_on_server(Net.my_id(), open_key, op)
	else:
		_rq_op.rpc_id(1, open_key, op)


@rpc("any_peer", "reliable")
func _rq_op(key: String, op: Dictionary) -> void:
	if multiplayer.is_server():
		_op_on_server(multiplayer.get_remote_sender_id(), key, op)


static func _valid_stack(s: Variant) -> bool:
	if not s is Dictionary:
		return false
	var d: Dictionary = s
	return d.has("id") and ItemDB.exists(String(d["id"])) and int(d.get("count", 0)) > 0 and int(d["count"]) <= ItemDB.max_stack(String(d["id"]))


func _op_on_server(peer: int, key: String, op: Dictionary) -> void:
	var w := gw()
	var back: Array = []   # stacks returned to the peer
	if not containers.has(key) or not _viewers.get(key, {}).has(peer):
		# Not open (any more): whatever was sent comes back.
		if String(op.get("op", "")) == "put" and _valid_stack(op.get("stack")):
			back.append(op["stack"])
		elif String(op.get("op", "")) == "put_many":
			for s: Variant in op.get("stacks", []):
				if _valid_stack(s):
					back.append(s)
		_return(peer, back)
		return
	var slots: Array = containers[key]
	match String(op.get("op", "")):
		"take":
			var i := int(op.get("slot", -1))
			if i >= 0 and i < slots.size() and not (slots[i] as Dictionary).is_empty():
				var s: Dictionary = slots[i]
				var n := int(s["count"]) if int(op.get("count", -1)) < 0 else clampi(int(op.get("count", 1)), 1, int(s["count"]))
				var out := s.duplicate()
				out["count"] = n
				s["count"] = int(s["count"]) - n
				if int(s["count"]) <= 0:
					slots[i] = {}
				out["to"] = int(op.get("to", -1))
				back.append(out)
		"put":
			if _valid_stack(op.get("stack")):
				var left := container_add(slots, op["stack"], int(op.get("slot", -1)))
				if not left.is_empty():
					back.append(left)
		"put_many":
			for s: Variant in op.get("stacks", []):
				if _valid_stack(s):
					var left := container_add(slots, s, -1)
					if not left.is_empty():
						back.append(left)
		"move":
			var a := int(op.get("from", -1))
			var b := int(op.get("to", -1))
			if a >= 0 and b >= 0 and a < slots.size() and b < slots.size() and a != b:
				var sa: Dictionary = slots[a]
				var sb: Dictionary = slots[b]
				if not sa.is_empty() and not sb.is_empty() and sa["id"] == sb["id"] and not sa.has("gem") and not sb.has("gem"):
					var room := ItemDB.max_stack(String(sb["id"])) - int(sb["count"])
					var n := mini(room, int(sa["count"]))
					sb["count"] = int(sb["count"]) + n
					sa["count"] = int(sa["count"]) - n
					if int(sa["count"]) <= 0:
						slots[a] = {}
				else:
					slots[a] = sb
					slots[b] = sa
		"take_all":
			for i in slots.size():
				if not (slots[i] as Dictionary).is_empty():
					back.append((slots[i] as Dictionary).duplicate())
					slots[i] = {}
		"sort":
			sort_slots(slots)
	_return(peer, back)
	_push(key)


## Adds a stack into container slots (preferring `at`); returns what did not fit ({} = all).
static func container_add(slots: Array, stack: Dictionary, at := -1) -> Dictionary:
	var s := stack.duplicate()
	s.erase("to")
	var id := String(s["id"])
	var max_stack := ItemDB.max_stack(id)
	var plain := not s.has("gem")
	if at >= 0 and at < slots.size():
		var t: Dictionary = slots[at]
		if t.is_empty():
			slots[at] = s
			return {}
		if plain and t.get("id", "") == id and not t.has("gem"):
			var n := mini(max_stack - int(t["count"]), int(s["count"]))
			t["count"] = int(t["count"]) + n
			s["count"] = int(s["count"]) - n
			if int(s["count"]) <= 0:
				return {}
	if plain:
		for t: Dictionary in slots:
			if int(s["count"]) <= 0:
				break
			if t.get("id", "") == id and not t.has("gem") and int(t["count"]) < max_stack:
				var n := mini(max_stack - int(t["count"]), int(s["count"]))
				t["count"] = int(t["count"]) + n
				s["count"] = int(s["count"]) - n
	if int(s["count"]) <= 0:
		return {}
	for i in slots.size():
		if (slots[i] as Dictionary).is_empty():
			slots[i] = s
			return {}
	return s


## Merges stacks and orders by category, rarity and name.
static func sort_slots(slots: Array) -> void:
	var items: Array = []
	for s: Dictionary in slots:
		if not s.is_empty():
			items.append(s.duplicate())
	var merged: Array = []
	for s: Dictionary in items:
		if not s.has("gem"):
			for t: Dictionary in merged:
				if t["id"] == s["id"] and not t.has("gem"):
					var n := mini(ItemDB.max_stack(String(t["id"])) - int(t["count"]), int(s["count"]))
					t["count"] = int(t["count"]) + n
					s["count"] = int(s["count"]) - n
		if int(s["count"]) > 0:
			merged.append(s)
	merged.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ka := "%s|%d|%s" % [ItemDB.category(a["id"]), 9 - ItemDB.rarity(a["id"]), ItemDB.display_name(a["id"])]
		var kb := "%s|%d|%s" % [ItemDB.category(b["id"]), 9 - ItemDB.rarity(b["id"]), ItemDB.display_name(b["id"])]
		return ka < kb)
	for i in slots.size():
		slots[i] = merged[i] if i < merged.size() else {}


func _return(peer: int, stacks: Array) -> void:
	if stacks.is_empty():
		return
	if peer == Net.my_id() or not Net.is_online():
		_receive(stacks)
	else:
		_receive.rpc_id(peer, stacks)


## Client: stacks handed over from a container. What does not fit goes back in.
@rpc("authority", "reliable")
func _receive(stacks: Array) -> void:
	var p := gw().local_player
	if p == null:
		return
	var inv := p.inventory
	var leftovers: Array = []
	for s: Dictionary in stacks:
		var id := String(s.get("id", ""))
		if not ItemDB.exists(id):
			continue
		var to := int(s.get("to", -1))
		var clean := s.duplicate()
		clean.erase("to")
		if to >= 0 and to < inv.size() and inv.get_slot(to).is_empty():
			inv.slots[to] = clean
			inv.changed.emit()
			continue
		if clean.has("gem"):
			var placed := false
			for i in range(Inventory.HOTBAR, inv.size()):
				if inv.get_slot(i).is_empty():
					inv.slots[i] = clean
					placed = true
					break
			if not placed:
				leftovers.append(clean)
			inv.changed.emit()
			continue
		var left := inv.add(id, int(clean["count"]))
		if left > 0:
			var l := clean.duplicate()
			l["count"] = left
			leftovers.append(l)
	if not leftovers.is_empty():
		Events.notify.emit("Your pack is full.", "warn")
		if open_key != "":
			_op({"op": "put_many", "stacks": leftovers})
	Audio.play_ui("pickup")


# --- Save ----------------------------------------------------------------------------------

func save_state() -> Dictionary:
	var list: Array = []
	for id: int in pieces:
		list.append(_record_to_array(id))
	return {"pieces": list, "containers": containers.duplicate(true), "next": _next_id}


func load_state(d: Dictionary) -> void:
	for a: Variant in d.get("pieces", []):
		if a is Array and (a as Array).size() >= 8:
			_add_record(a)
	var c: Variant = d.get("containers", {})
	if c is Dictionary:
		for key: String in c:
			var slots: Array = []
			for s: Variant in c[key]:
				slots.append(s if _valid_stack(s) else {})
			containers[key] = slots
	_next_id = maxi(_next_id, int(d.get("next", 1)))
