class_name NpcDialogue
extends RefCounted
## What villagers say: a pure function of who they are, the time of day and
## the local player's quests, so it is easy to test. Npc turns the result into
## Events.dialog_open; activity options come from the ActivityDirector.

const ROLE_TITLES := {"elder": "Elder", "chief": "Chief", "blacksmith": "Blacksmith", "merchant": "Trader",
		"guard": "Guard", "villager": "Villager"}

const RUMOURS := {
	"emberfall": ["The crater woke and the sun went cold. We keep the fires lit anyway.",
		"Maren says the shrines remember everyone who lights them.",
		"Dig deep enough and the stone gets warm. Then it gets hot."],
	"ashford": ["Skeleton archers on the north road. Keep your head down.",
		"The old watchtowers were built to watch the crater, not the roads."],
	"thornwick": ["The Emberwood never loses its leaves. They just burn slower.",
		"Ghouls come out of the ground at night. Bring a torch."],
	"frosthold": ["There's a door in the mountain. Trolls go in and don't come out.",
		"The Mountain King wears a crown of ice that never melts."],
	"mirewatch": ["Something knocks from inside the Silent Crypt.",
		"The marsh water burns if you light it. Don't."],
	"cinderreach": ["Ashvane circles the Keep at dusk. You can hear the wings from here.",
		"Under the crater there's a gate. Under the gate there's no bottom."],
}

const TURN_IN := {
	"kindling": "The shrine burns again. I felt it in my bones. Brannoc at the forge needs iron — go to him.",
	"iron_in_the_deep": "Good ore, and plenty. Take this blade; the best I've made since the sky went grey.",
	"silent_crypt": "The Warden's Sigil. Cold as a grave. One seal of three — the next is the Mountain King's crown.",
	"mountain_king": "The Frost Crown! The king is dead. Only the dragon remains.",
	"ashvane": "Ashvane's heart, still burning. You hold all three seals. Now comes the worst of it.",
}


## The quest-giver key an NPC answers to (QuestDB "giver").
static func giver_key(role: String, village: String) -> String:
	if role == "elder":
		return "elder"
	if role == "blacksmith" and village == "emberfall":
		return "blacksmith"
	return "villager@" + village


## Main quest this giver can offer right now ("" if none): the next quest in
## the chain, once everything before it is done and nothing is in progress.
static func next_main_for(q: QuestLog, giver: String) -> String:
	for quest: Dictionary in QuestDB.MAIN:
		var id: String = quest["id"]
		if q.is_completed(id):
			continue
		if q.is_active(id):
			return ""
		return id if String(quest["giver"]) == giver else ""
	return ""


## Quests this NPC can take back right now.
static func turn_ins(q: QuestLog, role: String, village: String) -> Array[String]:
	var out: Array[String] = []
	var givers := [giver_key(role, village)]
	if role in ["elder", "chief", "villager"] and not givers.has("villager@" + village):
		givers.append("villager@" + village)
	for g: String in givers:
		for id in q.ready_to_turn_in(g):
			if not out.has(id):
				out.append(id)
	return out


## "!" (something to offer), "?" (a quest to hand in) or "".
static func marker(q: QuestLog, role: String, village: String) -> String:
	if q == null:
		return ""
	if not turn_ins(q, role, village).is_empty():
		return "?"
	if next_main_for(q, giver_key(role, village)) != "":
		return "!"
	return ""


## {"lines": PackedStringArray, "options": Array[{text, id}]}.
## info: {role, village, name, net_id, night: bool, indoors: bool, hour: float}
## extra: activity options [{text, id}] and an optional "rumour" line.
static func build(info: Dictionary, q: QuestLog, extra: Dictionary = {}) -> Dictionary:
	var role := String(info.get("role", "villager"))
	var village := String(info.get("village", ""))
	var lines := PackedStringArray()
	var options: Array = []
	if bool(info.get("indoors", false)):
		lines.append(_knock_line(role))
	for id in turn_ins(q, role, village):
		var quest := QuestDB.any(id)
		lines.append(String(TURN_IN.get(id, "You've done well. Here, as promised.")))
		options.append({"text": "Hand in: " + String(quest["title"]), "id": "turnin:" + id})
	var offer := next_main_for(q, giver_key(role, village))
	if offer != "" and options.is_empty():
		var quest := QuestDB.main_quest(offer)
		lines.append(String(quest["description"]))
		options.append({"text": "Accept: " + String(quest["title"]), "id": "accept:" + offer})
	for o: Dictionary in extra.get("options", []):
		options.append(o)
	match role:
		"blacksmith":
			options.append({"text": "Let me use your forge.", "id": "shop:blacksmith"})
		"merchant":
			options.append({"text": "Show me your wares.", "id": "shop:merchant"})
	if lines.is_empty() or (lines.size() == 1 and bool(info.get("indoors", false)) and options.size() <= 1):
		lines.append(idle_line(info, q, String(extra.get("rumour", ""))))
	options.append({"text": "What's the news?", "id": "rumour"})
	options.append({"text": "Farewell.", "id": "bye"})
	return {"lines": lines, "options": options}


static func _knock_line(role: String) -> String:
	match role:
		"merchant":
			return "(The shutter creaks open.) Shop's shut... but gold is gold. Quickly."
		"blacksmith":
			return "(A bleary face at the door.) The forge is banked. What is it?"
		"elder", "chief":
			return "(The door opens a crack.) Late visitors bring bad news or good. Which?"
	return "(Someone mutters behind the door.) Come back in daylight."


static func idle_line(info: Dictionary, q: QuestLog, rumour := "") -> String:
	var role := String(info.get("role", "villager"))
	var village := String(info.get("village", ""))
	var night := bool(info.get("night", false))
	match role:
		"elder", "chief":
			var tracked := q.tracked() if q != null else []
			for t: Dictionary in tracked:
				if bool(t.get("main", false)):
					for o: Dictionary in t["objectives"]:
						if not o["done"]:
							return "%s. The ash is patient. We are not." % String(o["text"])
			if rumour != "":
				return rumour
			return "We endure as long as someone keeps the fire. The bounty board by the well pays for brave work."
		"blacksmith":
			return "Bring me iron, gold, ember crystal — or starmetal, if a star ever falls near you. I'll give it an edge."
		"merchant":
			return "Potions, torches, bread. And maps — old ones, with crosses on them. Gold for anything shiny you dig up."
		"guard":
			if rumour != "":
				return rumour
			return "Quiet night, so far. Raiders come at dusk when they come." if night else "Eyes open. The dead don't keep office hours."
	if rumour != "":
		return rumour
	var pool: Array = RUMOURS.get(village, RUMOURS["emberfall"])
	return pool[absi(int(info.get("net_id", 0)) + int(Time.get_ticks_msec() / 60000)) % pool.size()]
