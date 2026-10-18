extends TestCase
## The progression ladder: new objective types, chain continuity, the Path
## tab data, optional boss contracts and old-save migration.


func _all_quests() -> Array:
	var out: Array = []
	out.append_array(QuestDB.FIRST_STEPS)
	out.append_array(QuestDB.MAIN)
	out.append_array(QuestDB.OPTIONAL)
	return out


func test_craft_place_gather_objectives() -> void:
	var q := QuestLog.new()
	q.accept("fs_timber")
	q.on_event("gather", "stone", 9)
	check(q.is_active("fs_timber"), "other items don't count as wood")
	q.on_event("gather", "wood", 3)
	check(q.is_active("fs_timber"), "3 of 4 logs")
	q.on_event("gather", "wood", 2)
	check(q.is_completed("fs_timber") and q.is_active("fs_workbench"), "wood gathered: the workbench step follows by itself")
	q.on_event("place", "workbench")
	check(q.is_active("fs_workbench"), "objectives count only once reached in any order, but all are needed")
	q.on_event("craft", "planks", 4)
	q.on_event("craft", "workbench", 1)
	check(q.is_completed("fs_workbench") and q.is_active("fs_stone_tools"), "planks, bench, placed")
	q.on_event("gather", "stone", 6)
	q.on_event("craft", "stick", 4)
	q.on_event("craft", "sword_wood", 1)
	check(q.is_active("fs_stone_tools"), "a wooden sword is not a stone tool")
	q.on_event("craft", "spear_stone", 1)
	check(q.is_completed("fs_stone_tools"), "alternative keys: a stone spear counts")
	q.on_event("craft", "campfire", 1)
	q.on_event("place", "campfire", 1)
	check(q.is_completed("fs_campfire") and q.is_active("fs_village"), "campfire built and placed")
	q.on_event("reach", "emberfall")
	q.on_event("talk", "elder")
	check(q.is_completed("fs_village"), "the guide ends at Elder Maren")
	check(QuestLog.key_matches("axe_stone|spear_stone", "craft", "axe_stone"), "key alternatives")
	check(not QuestLog.key_matches("axe_stone", "craft", "axe_stone_x"), "exact match otherwise")


func test_world_facts_prevent_stranded_boss_quests() -> void:
	var q := QuestLog.new()
	q.known_bosses = {"warden": true}
	q.known_places = {&"silent_crypt": true}
	q.accept("silent_crypt")
	check(q.ready_to_turn_in("elder").has("silent_crypt"), "a boss slain before the quest still counts")
	var later := QuestLog.new()
	later.accept("mountain_king")
	later.known_bosses = {"mountain_king": true}
	later.known_places = {&"mountain_hall": true}
	later.sync_world_facts()
	check(later.ready_to_turn_in("elder").has("mountain_king"), "loaded saves catch up with slain bosses")


func test_chain_continuity() -> void:
	var ids := {}
	for qd: Dictionary in _all_quests():
		check(not ids.has(qd["id"]), "unique quest id " + String(qd["id"]))
		ids[qd["id"]] = true
		check(not QuestDB.any(qd["id"]).is_empty(), "QuestDB.any finds " + String(qd["id"]))
		var nxt := String(qd.get("next", ""))
		check(nxt == "" or ids.has(nxt) or not QuestDB.any(nxt).is_empty(), "%s leads to a real quest" % qd["id"])
		for o: Dictionary in qd["objectives"]:
			check(int(o["count"]) > 0 and String(o["text"]) != "", "%s objectives are complete" % qd["id"])
			if o["type"] in ["craft", "gather", "collect", "have", "place"]:
				for k in String(o["key"]).split("|"):
					check(ItemDB.exists(k), "%s objective item %s exists" % [qd["id"], k])
			if o["type"] == "craft":
				for k in String(o["key"]).split("|"):
					var craftable := false
					for rid: String in ItemDB.RECIPES:
						if ItemDB.recipe_result(rid) == k:
							craftable = true
					check(craftable, "%s: %s has a recipe" % [qd["id"], k])
		for item: String in qd["rewards"].get("items", {}):
			check(ItemDB.exists(item), "%s reward %s exists" % [qd["id"], item])
	# Every main quest but the last names its successor, and the chain visits them all.
	var seen := {}
	var cur: String = QuestDB.MAIN[0]["id"]
	while cur != "":
		check(not seen.has(cur), "no loop at " + cur)
		if seen.has(cur):
			break
		seen[cur] = true
		cur = String(QuestDB.main_quest(cur).get("next", ""))
	check_eq(seen.size(), QuestDB.MAIN.size(), "every main quest is reachable from Kindling")
	cur = QuestDB.FIRST_STEPS[0]["id"]
	var n := 0
	while cur != "":
		n += 1
		cur = String(QuestDB.first_step(cur).get("next", ""))
	check_eq(n, QuestDB.FIRST_STEPS.size(), "the guide is one chain")
	for step: Dictionary in QuestDB.PATH:
		check(not QuestDB.any(String(step["quest"])).is_empty(), "path step %s has a quest" % step["title"])
	for qd: Dictionary in QuestDB.OPTIONAL:
		check(not QuestDB.any(String(qd["requires"])).is_empty(), "%s requirement exists" % qd["id"])
		check(String(qd["giver"]) != "", "%s is handed out by someone" % qd["id"])


func test_no_breathing_hints() -> void:
	for qd: Dictionary in _all_quests():
		var text := (String(qd["description"]) + " " + str(qd["objectives"])).to_lower()
		for w in ["breath", "oxygen", "drowning", "suffocat"]:
			check(not text.contains(w), "%s keeps breathing a secret" % qd["id"])


func test_new_game_path_and_optional_offers() -> void:
	var q := QuestLog.new()
	q.accept("kindling")
	q.start_guide()
	check(q.is_active("fs_timber"), "a new character starts the guide")
	var path := q.path()
	check_eq(String(path[0]["state"]), "current", "first step is current")
	check_eq(String(path[1]["state"]), "next", "second step is next")
	check_eq(String(path[5]["state"]), "locked", "later steps are locked")
	check(not str(path[5]).contains("hint") or String(path[5]["state"]) == "locked", "path rows carry state")
	check(NpcDialogue.optional_offers(q, "villager@thornwick").is_empty(), "optional hunts wait for the Warden")
	q._completed["silent_crypt"] = true
	check(NpcDialogue.optional_offers(q, "villager@thornwick").has("opt_broodmother"), "Thornwick asks for the Broodmother")
	check_eq(NpcDialogue.marker(q, "chief", "thornwick"), "!", "the chief shows a marker")
	q._completed["ashvane"] = true
	var kraken := NpcDialogue.optional_offers(q, "villager@kaldvik").has("opt_kraken")
	check_eq(kraken, "kraken" in EntityFactory.BOSS_KINDS, "the Kraken is offered only once the boss exists in this build")
	for e: Dictionary in q.optional_path():
		check(QuestDB.boss_available(QuestDB.optional_quest(e["id"])), "missing bosses stay off the Path tab")


func test_old_saves_skip_the_guide_and_inserted_steps() -> void:
	var q := QuestLog.new()
	q.from_dict({"active": {"silent_crypt": {"progress": [1, 0], "tracked": true}}, "completed": ["kindling", "iron_in_the_deep"]})
	check(q.is_completed("tempered"), "a quest inserted before the current one counts as done")
	check(q.is_completed("fs_timber") and q.is_completed("fs_village"), "advanced saves skip the guide")
	q.start_guide()
	check(not q.is_active("fs_timber"), "and it does not restart")
	check(not q.is_completed("steel_and_frost"), "later quests are untouched")
	check(NpcDialogue.next_main(q) == "", "silent crypt still in progress")
	var fresh := QuestLog.new()
	fresh.from_dict({"active": {"kindling": {"progress": [0], "tracked": true}}, "completed": []})
	fresh.start_guide()
	check(fresh.is_active("fs_timber"), "an old save that only just began gets the guide")
	var short := QuestLog.new()
	short.from_dict({"active": {"ryft": {"progress": [1], "tracked": true}}, "completed": []})
	check_eq(short.active()[0]["objectives"].size(), 4, "saved progress is padded to the quest's objectives")


func test_campfire_station() -> void:
	check(ItemDB.STATIONS.has("campfire") and "campfire" in Station.KINDS, "campfire is a station")
	var inv := Inventory.new()
	inv.add("stone", 5)
	inv.add("wood", 2)
	inv.add("stick", 2)
	check(inv.craft("campfire", [])["ok"], "a campfire is made by hand")
	inv.add("raw_meat", 1)
	check(not inv.craft("cooked_meat_campfire", [])["ok"], "cooking needs the fire")
	check(inv.craft("cooked_meat_campfire", ["campfire"])["ok"] and inv.has("cooked_meat"), "meat roasts on the campfire")
	for id in ["leather", "wolf_pelt", "spider_silk", "pearl", "hag_eye", "brood_heart", "leviathan_heart", "swamp_herb"]:
		check(ItemDB.exists(id), "loot item %s is defined" % id)
