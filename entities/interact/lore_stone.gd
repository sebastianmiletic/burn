class_name LoreStone
extends Entity
## A runestone with an inscription.

const TEXTS := {
	"crater": ["Here the sky fell, and the fire went down into the earth.",
		"Three seals bind the Gate below: the Warden's, the King's, the Dragon's.",
		"Dig, and you will find it. Dig, and it will find you."],
	"leviathan": ["The fishers of the Grey Sea raised this spire to watch for storms.",
		"The storms were never storms. Something old circles beneath, and it does not sleep.",
		"It rises to feed. Strike only when its head is above the water."],
	"broodmother": ["Emberwood weeps here: the trees above drink from a hollow full of silk.",
		"Vexhira the Broodmother has fed on miners and hunters for a hundred winters.",
		"When she climbs into the dark, watch the ground beneath her."],
	"bog_hag": ["Leave a coin at the stones and Old Mother Mire may let you pass.",
		"Those who did not are in her pools now. Some of them still walk.",
		"She is frail, but she never stands where you left her."],
}

var text_key := ""


func _init() -> void:
	kind = "lore"
	team = Team.NEUTRAL
	body.collides = false
	body.gravity = 0.0


func on_spawned(data: Dictionary) -> void:
	text_key = String(data.get("text", ""))
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.5, 0.2)
	glow.light_energy = 1.0
	glow.omni_range = 5.0
	glow.position.y = 0.5
	add_child(glow)


func interact_prompt(_p: Player) -> String:
	return "Read the runes"


func local_interact(_p: Player) -> void:
	Events.dialog_open.emit(self, "Runestone", PackedStringArray(TEXTS.get(text_key, ["The runes are worn smooth."])), [{"text": "Step back.", "id": "bye"}])
	if not Events.dialog_choice.is_connected(_on_choice):
		Events.dialog_choice.connect(_on_choice)


func _on_choice(npc: Node, _id: String) -> void:  # "bye" or "leave"
	if npc == self:
		Events.dialog_close.emit()
