class_name Npc
extends Entity
## Villagers. Wander near home (server), turn to face people, and talk:
## quest offers and turn-ins, shops, rumours. Dialogue is local to each
## player because quests are per player.

const CHIEFS := {"emberfall": "Elder Maren", "ashford": "Reeve Halden", "thornwick": "Warden Ysolde",
		"frosthold": "Jarl Hrothgar", "mirewatch": "Old Nessa", "cinderreach": "Ashlord Kael"}
const SMITHS := {"emberfall": "Brannoc", "ashford": "Tamsin", "thornwick": "Odric", "frosthold": "Grima", "mirewatch": "Wendel", "cinderreach": "Sable"}
const FIRST := ["Alda", "Bram", "Cora", "Dunstan", "Edda", "Fenn", "Gisla", "Hob", "Ivo", "Jory", "Kestrel", "Lio", "Mabyn", "Nim", "Osric", "Pell", "Rowan", "Sigrun", "Tobin", "Wren"]

const RUMOURS := {
	"emberfall": ["The sun hasn't been warm since the crater woke.", "Elder Maren says the shrines remember everyone who lit them.", "Dig deep enough and the stone gets warm. Then it gets hot."],
	"ashford": ["Skeleton archers on the north road. Keep your head down.", "The old watchtowers were built to watch the crater, not the roads."],
	"thornwick": ["The Emberwood never loses its leaves. They just burn slower.", "Ghouls come out of the ground at night. Bring a torch."],
	"frosthold": ["There's a door in the mountain. The trolls go in and don't come out.", "The Mountain King wears a crown of ice that never melts."],
	"mirewatch": ["Something knocks from inside the Silent Crypt.", "The marsh water burns if you light it. Don't."],
	"cinderreach": ["Ashvane circles the Keep at dusk. You can hear the wings from here.", "Under the crater, they say, there is a gate. Under the gate, there is no bottom."],
}

var role := "villager"
var village := ""
var home := Vector3.ZERO
var _wander_target := Vector3.ZERO
var _wait := 0.0
var _model: Node3D
var _speed := 0.0
var _talking_to: Player = null


func _init() -> void:
	kind = "npc"
	team = Team.NEUTRAL
	hit_radius = 0.4
	body.half_extents = Vector3(0.3, 0.9, 0.3)
	max_health = 9999.0
	health = max_health


func on_spawned(data: Dictionary) -> void:
	role = String(data.get("role", "villager"))
	village = String(data.get("village", ""))
	home = global_position
	_wander_target = home
	display_name = _make_name(int(data.get("seed", net_id)))
	_model = _make_model(int(data.get("seed", net_id)))
	add_child(_model)
	Events.dialog_choice.connect(_on_choice)


func _make_name(s: int) -> String:
	match role:
		"elder", "chief":
			return CHIEFS.get(village, "Village Chief")
		"blacksmith":
			return SMITHS.get(village, "Smith")
		"merchant":
			return FIRST[absi(s * 7) % FIRST.size()] + " the Trader"
		"guard":
			return "Guard " + FIRST[absi(s * 3) % FIRST.size()]
	return FIRST[absi(s) % FIRST.size()]


func _make_model(s: int) -> Node3D:
	# Seeded per NPC: stable faces, builds, hair and role garments.
	return HumanoidModel.new(CharStyles.villager(role, s))


# --- Server behaviour ----------------------------------------------------------------

func server_tick(delta: float) -> void:
	var vw := voxels()
	var nearest := world().nearest_player(global_position, dimension, 4.0)
	var want := Vector3.ZERO
	if nearest != null:
		var to := nearest.global_position - global_position
		yaw = lerp_angle(yaw, atan2(to.x, to.z), 1.0 - exp(-delta * 6.0))
	elif role != "blacksmith" and role != "merchant":
		_wait -= delta
		var to := _wander_target - global_position
		to.y = 0
		if to.length() < 0.6 or _wait > 8.0:
			if _wait <= 0.0:
				var a := randf() * TAU
				_wander_target = home + Vector3(cos(a), 0, sin(a)) * randf_range(1.0, 7.0)
				_wait = randf_range(2.0, 6.0)
		else:
			want = to.normalized() * 1.4
			yaw = lerp_angle(yaw, atan2(to.x, to.z), 1.0 - exp(-delta * 5.0))
	body.velocity.x = want.x
	body.velocity.z = want.z
	body.step(self, vw, delta)
	if body.hit_wall and body.on_floor:
		body.velocity.y = 7.5
	if global_position.distance_to(home) > 20.0:
		global_position = home
	rotation.y = yaw
	_speed = Vector2(body.velocity.x, body.velocity.z).length()


func _process(delta: float) -> void:
	if _model == null:
		return
	if not is_server():
		var prev := global_position
		interpolate(Net.server_time() if Net.has_method("server_time") else Time.get_ticks_msec() / 1000.0)
		_speed = lerpf(_speed, (global_position - prev).length() / maxf(delta, 0.001), 0.2)
	if "move_speed" in _model:
		_model.set("move_speed", _speed)
	HumanoidModel.drive(_model, self, body.velocity if is_server() else _model.global_transform.basis * Vector3(0, 0, -_speed), body.on_floor or not is_server())


# --- Dialogue (local) --------------------------------------------------------------------

func interact_prompt(_p: Player) -> String:
	return "Talk to " + display_name


func local_interact(p: Player) -> void:
	_talking_to = p
	_open_dialog()
	Audio.play_ui("ui_open")


func _giver_key() -> String:
	if role == "elder":
		return "elder"
	if role == "blacksmith" and village == "emberfall":
		return "blacksmith"
	return "villager@" + village


func _open_dialog() -> void:
	var w := world()
	var q := w.quests
	var lines := PackedStringArray()
	var options: Array = []
	var giver := _giver_key()

	var givers := [giver]
	if role in ["elder", "chief", "villager"] and not givers.has("villager@" + village):
		givers.append("villager@" + village)
	for g: String in givers:
		for id in q.ready_to_turn_in(g):
			var quest := QuestDB.any(id)
			lines.append(_turn_in_line(id))
			options.append({"text": "Hand in: " + String(quest["title"]), "id": "turnin:" + id})

	var offer := _next_main_for(giver)
	if offer != "" and lines.is_empty():
		var quest := QuestDB.main_quest(offer)
		lines.append(String(quest["description"]))
		options.append({"text": "Accept: " + String(quest["title"]), "id": "accept:" + offer})
	if role == "chief" or role == "villager" or role == "elder":
		for side in QuestDB.side_quests_for(village):
			if not q.is_active(side["id"]) and not q.is_completed(side["id"]):
				options.append({"text": "Any work? (" + String(side["title"]) + ")", "id": "side:" + String(side["id"])})
				break
	if role == "blacksmith":
		options.append({"text": "Show me your forge.", "id": "shop:blacksmith"})
	if role == "merchant":
		options.append({"text": "Let's trade.", "id": "shop:merchant"})
	if lines.is_empty():
		lines.append(_idle_line())
	options.append({"text": "Farewell.", "id": "bye"})
	Events.dialog_open.emit(self, display_name, lines, options)


func _next_main_for(giver: String) -> String:
	var q := world().quests
	var prev_done := true
	for quest: Dictionary in QuestDB.MAIN:
		var id: String = quest["id"]
		if q.is_completed(id):
			prev_done = true
			continue
		if q.is_active(id):
			return ""
		if prev_done and String(quest["giver"]) == giver:
			return id
		return ""
	return ""


func _turn_in_line(id: String) -> String:
	match id:
		"kindling":
			return "The shrine burns again. I felt it in my bones. Brannoc at the forge will want to see you — he needs iron."
		"iron_in_the_deep":
			return "Good ore, and plenty of it. Take this blade; it's the best I've made since the sky went grey."
		"silent_crypt":
			return "The Warden's Sigil... cold as a grave. One seal of three. The next lies in the north, in the Mountain King's hall."
		"mountain_king":
			return "The Frost Crown! The king is dead, then. Only the dragon remains."
		"ashvane":
			return "Ashvane's heart, still burning. You hold all three seals. Now comes the worst of it."
	return "You've done well. Here, as promised."


func _idle_line() -> String:
	var w := world()
	match role:
		"elder":
			var active := w.quests.tracked()
			if not active.is_empty():
				return "Remember: " + String(active[0]["objectives"][0]["text"]) + ". The ash is patient. We are not."
			return "Emberfall endures, as long as there is someone to keep the fire."
		"blacksmith":
			return "Iron, coal, gold, ember crystal — bring me what the earth gives and I'll give it an edge."
		"merchant":
			return "Potions, torches, bread. Gold for anything shiny you dig up."
		"guard":
			return "Keep your blade close after dark. The dead don't sleep out here."
	var pool: Array = RUMOURS.get(village, RUMOURS["emberfall"])
	return pool[absi(net_id + int(Time.get_ticks_msec() / 60000)) % pool.size()]


func _on_choice(npc: Node, option_id: String) -> void:
	if npc != self:
		return
	var w := world()
	if option_id == "bye" or option_id == "leave":
		Events.dialog_close.emit()
		return
	if option_id.begins_with("turnin:"):
		var qid := option_id.trim_prefix("turnin:")
		if w.quests.ready_to_turn_in(_giver_key()).has(qid) or w.quests.ready_to_turn_in("villager@" + village).has(qid):
			w.quests.complete(qid)
		_open_dialog()
		return
	if option_id.begins_with("accept:") or option_id.begins_with("side:"):
		var id := option_id.get_slice(":", 1)
		w.quests.accept(id)
		Events.dialog_close.emit()
		return
	if option_id.begins_with("shop:"):
		Events.dialog_close.emit()
		Events.shop_open.emit(option_id.trim_prefix("shop:"))
