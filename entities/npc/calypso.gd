class_name Calypso
extends Npc
## Calypso of Ogygia. She stays by her hearth, turns to whoever speaks to
## her, and offers the way home on the raft. One gift, once.

const GIFT_ID := "lore_calypso_gift"
const GIFT_ITEM := "potion_phoenix"


func _init() -> void:
	super()
	kind = "calypso"


func on_spawned(data: Dictionary) -> void:
	super(data)
	role = "calypso"
	display_name = "Calypso"
	if _model != null:
		_model.queue_free()
	_model = HumanoidModel.new(style())
	add_child(_model)


## Long dark hair, a pale sea-green robe with a gold sash, bare of armour.
static func style() -> Dictionary:
	return {
		"female": true, "age": 0.22, "skin": Color(0.86, 0.7, 0.58), "height": 1.74, "bulk": 0.92,
		"jaw": 0.86, "nose": 0.95, "brow": 0.1, "cheeks": 1.05,
		"hair": Color(0.12, 0.08, 0.06), "hair_style": "long",
		"robe": true, "cloth": Color(0.62, 0.74, 0.68), "cloth2": Color(0.78, 0.62, 0.26),
		"sash": true, "collar": false, "sleeves": "long", "tunic_length": 1.0, "footwear": "shoes",
		"leather": Color(0.45, 0.32, 0.2), "trousers": Color(0.55, 0.65, 0.6),
	}


func _make_name(_s: int) -> String:
	return "Calypso"


func role_title() -> String:
	return "Nymph of Ogygia"


func interact_prompt(_p: Player) -> String:
	return "Speak with Calypso"


## She keeps to her hearth: no village routine, only turning to listeners.
func server_tick(delta: float) -> void:
	var vw := _vw()
	if vw == null:
		return
	if not _settled:
		if not vw.is_area_loaded(global_position):
			return
		_settle(vw)
	var talker := _talker()
	if talker != null:
		act = Act.TALK
		_turn_towards(_yaw_to(global_position, talker.global_position), delta)
	else:
		act = Act.IDLE
	body.velocity.x = 0.0
	body.velocity.z = 0.0
	body.step(self, vw, delta)
	rotation.y = yaw
	_speed = 0.0


func _open_dialog() -> void:
	var w := world()
	var lines := PackedStringArray([
		"The sea brought you to my shore, half drowned and cold as the stones. I warmed you by the fire and you slept a day and a night.",
		"The gods do not often let the sea give back what it takes. Do not waste it.",
	])
	var options: Array = [{"text": "Why did you save me?", "id": "why"}, {"text": "I have to go home.", "id": "home"}]
	if w != null and w.quests != null and not w.quests.is_completed(GIFT_ID):
		options.append({"text": "You have been kind to me.", "id": "gift"})
	options.append({"text": "Farewell.", "id": "bye"})
	Events.dialog_open.emit(self, display_name, lines, options)


func _on_choice(npc: Node, option_id: String) -> void:
	if npc != self:
		return
	var w := world()
	match option_id:
		"why":
			Events.dialog_open.emit(self, display_name, PackedStringArray([
				"Another man once washed up here, and I kept him seven years. He wept every evening for his rocky island and his wife.",
				"I could make you forget your way home. Stay, and you would never grow old. But I see it in your face: you will go.",
			]), [{"text": "I will.", "id": "home"}, {"text": "Ask something else.", "id": "back"}])
		"home":
			Events.dialog_open.emit(self, display_name, PackedStringArray([
				"Then go with a fair wind. The raft we lashed together lies on the beach below the cypresses, its sail mended.",
				"Step aboard, and it will carry you to the last fire you kindled. All you carried, you carry still.",
			]), [{"text": "Thank you, Calypso.", "id": "bye"}])
		"gift":
			if w != null and w.quests.record_lore(GIFT_ID) and w.local_player != null:
				w.local_player.give_item(GIFT_ITEM, 1)
			Events.dialog_open.emit(self, display_name, PackedStringArray([
				"Take this. The phoenix wakes from its own ashes, as you woke on my sand. Drink it when the dark comes for you again.",
			]), [{"text": "Thank you.", "id": "back"}])
		"back":
			_open_dialog()
		_:
			Events.dialog_close.emit()
