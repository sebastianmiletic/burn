class_name BountyBoard
extends Entity
## The bounty board by a village's plaza. Reading it lists the posted
## contracts (shared by every board, refreshed each morning) with Accept /
## Abandon. The notices on the board show how many are still open.

var village := ""
var _notes: Array = []
var _shown := -1


func _init() -> void:
	kind = "act_board"
	team = Team.NEUTRAL
	hit_radius = 1.0
	body.collides = false
	body.gravity = 0.0


func on_spawned(data: Dictionary) -> void:
	village = String(data.get("village", ""))
	yaw = float(data.get("yaw", 0.0))
	rotation.y = yaw
	var model := Node3D.new()
	add_child(model)
	_notes = ActivityModels.board(model)
	var lantern := HeldItems.build("lantern", 1.6)
	if lantern != null:
		lantern.position = Vector3(0.95, 1.95, 0.25)
		model.add_child(lantern)
	if not Events.dialog_choice.is_connected(_on_choice):
		Events.dialog_choice.connect(_on_choice)


func _process(_delta: float) -> void:
	var acts := _acts()
	if acts == null:
		return
	var n := 0
	for c: Dictionary in acts.bounties.contracts():
		if c["state"] != "done":
			n += 1
	if n != _shown:
		_shown = n
		for i in _notes.size():
			(_notes[i] as Node3D).visible = i < n


func _acts() -> ActivityDirector:
	return ActivityDirector.of(world()) if world() != null else null


func interact_prompt(_p: Player) -> String:
	return "Read the bounty board"


func local_interact(_p: Player) -> void:
	_open()
	Audio.play_ui("ui_open")


func _open() -> void:
	var acts := _acts()
	if acts == null:
		return
	var lines := PackedStringArray()
	var options: Array = []
	var list := acts.bounties.contracts()
	var any := false
	for c: Dictionary in list:
		if c["state"] == "done":
			continue
		any = true
		var kind_text := "HUNT" if c["type"] == "hunt" else "BOUNTY"
		var status := "  [accepted]" if c["state"] == "active" else ""
		lines.append("%s · %s, the %s — near %s. %d gold + trophy.%s" % [kind_text, c["name"], c["what"], c["where"], int(c["gold"]), status])
		if c["state"] == "open":
			options.append({"text": "Take the contract: %s" % c["name"], "id": "accept:%d" % int(c["id"])})
		else:
			options.append({"text": "Give up on %s" % c["name"], "id": "abandon:%d" % int(c["id"])})
	if not any:
		lines.append("Every notice is torn down: all claimed. New contracts are posted each morning.")
	else:
		lines.insert(0, "WANTED — dead, for coin. Hunts start where the beast was last seen: look for fresh tracks.")
	options.append({"text": "Step back.", "id": "bye"})
	# One page: the notices and the choices together.
	Events.dialog_open.emit(self, "Bounty Board", PackedStringArray(["\n".join(lines)]), options)


func _on_choice(npc: Node, id: String) -> void:
	if npc != self:
		return
	var acts := _acts()
	if id.begins_with("accept:") and acts != null:
		acts.request("contract_accept", {"id": int(id.get_slice(":", 1))})
	elif id.begins_with("abandon:") and acts != null:
		acts.request("contract_abandon", {"id": int(id.get_slice(":", 1))})
	Events.dialog_close.emit()
