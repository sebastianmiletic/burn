extends TestCase
## Roles (kits, rank perks), drawn-glyph recognition and spell resolution.


func test_every_glyph_recognises_its_own_drawing() -> void:
	for g: String in GlyphRecognizer.GLYPHS:
		var pts := GlyphRecognizer.sample_points(g, Rect2(100, 100, 220, 220))
		var r := GlyphRecognizer.recognize(pts)
		check(bool(r["valid"]), "%s drawing is a valid stroke" % g)
		check_eq(r["glyph"], g, "clean %s is recognised as itself" % g)
		check(float(r["score"]) >= Spells.CLEAN, "clean %s scores as clean (%.2f)" % [g, float(r["score"])])


func test_shaky_hand_still_recognised() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for g: String in GlyphRecognizer.GLYPHS:
		var pts := GlyphRecognizer.sample_points(g, Rect2(0, 0, 260, 260), 6.0, rng)
		check_eq(GlyphRecognizer.recognize(pts)["glyph"], g, "jittered %s is still %s" % [g, g])


func test_glyph_size_and_position_do_not_matter() -> void:
	var small := GlyphRecognizer.recognize(GlyphRecognizer.sample_points("zigzag", Rect2(900, 40, 60, 60)))
	var big := GlyphRecognizer.recognize(GlyphRecognizer.sample_points("zigzag", Rect2(0, 0, 700, 700)))
	check_eq(small["glyph"], "zigzag", "small zigzag")
	check_eq(big["glyph"], "zigzag", "big zigzag")


func test_closed_glyph_any_start_and_direction() -> void:
	var pts := GlyphRecognizer.sample_points("square", Rect2(0, 0, 200, 200))
	var rev := pts.duplicate()
	rev.reverse()
	check_eq(GlyphRecognizer.recognize(rev)["glyph"], "square", "square drawn backwards")
	for g: String in GlyphRecognizer.CLOSED:
		var ring := GlyphRecognizer.sample_points(g, Rect2(0, 0, 200, 200))
		for start in [5, 17, 33, 50]:
			var moved := PackedVector2Array()
			for i in ring.size():
				moved.append(ring[(i + start) % (ring.size() - 1)])
			check_eq(GlyphRecognizer.recognize(moved)["glyph"], g, "%s started at point %d" % [g, start])
			moved.reverse()
			check_eq(GlyphRecognizer.recognize(moved)["glyph"], g, "%s backwards from point %d" % [g, start])


func test_scribble_is_not_a_glyph() -> void:
	var tiny := PackedVector2Array([Vector2(0, 0), Vector2(3, 2), Vector2(5, 1), Vector2(6, 4), Vector2(2, 5)])
	check(not bool(GlyphRecognizer.recognize(tiny)["valid"]), "a tiny scribble is rejected")
	check(not bool(GlyphRecognizer.recognize(PackedVector2Array())["valid"]), "an empty stroke is rejected")


func test_resolve_cast_unknown_fizzle() -> void:
	var known := Spells.known("mage", 0, {})
	check("fireball" in known, "a fresh mage knows Fireball")
	var circle := GlyphRecognizer.recognize(GlyphRecognizer.sample_points("circle", Rect2(0, 0, 200, 200)))
	var v := Spells.resolve("mage", circle, known)
	check_eq(v["result"], "cast", "a clean circle casts")
	check_eq(v["spell"], "fireball", "mage circle is Fireball")
	var spiral := GlyphRecognizer.recognize(GlyphRecognizer.sample_points("spiral", Rect2(0, 0, 200, 200)))
	check_eq(Spells.resolve("mage", spiral, known)["result"], "unknown", "Meteor is not known at rank 0")
	check_eq(Spells.resolve("mage", {"valid": false}, known)["result"], "fizzle", "a bad stroke fizzles")
	var shaky := circle.duplicate()
	shaky["score"] = (Spells.CLEAN + Spells.SHAKY) * 0.5
	shaky["second"] = ""
	var w := Spells.resolve("mage", shaky, known)
	check_eq(w["result"], "weak", "a shaky circle casts weak")
	check_near(float(w["power"]), Spells.SHAKY_POWER, 0.001, "weak power")


func test_spells_are_consistent() -> void:
	for id: String in Spells.SPELLS:
		var s: Dictionary = Spells.SPELLS[id]
		check(GlyphRecognizer.GLYPHS.has(String(s["glyph"])), "%s uses a real glyph" % id)
		var book := String(s.get("book", ""))
		check(book == "" or ItemDB.exists(book), "%s book %s is an item" % [id, book])
		for r: String in s["ranks"]:
			check(Roles.is_role(r), "%s role %s exists" % [id, r])
			check_eq(Spells.for_glyph(r, String(s["glyph"])), id, "%s is the only %s spell of %s" % [id, s["glyph"], r])
	for r: String in Roles.ORDER:
		check(not Spells.known(r, 0, {}).is_empty(), "%s starts with a glyph spell" % r)


func test_book_gated_spell_needs_the_book() -> void:
	check(not Spells.can_cast("meteor", "mage", 9, {}), "Meteor needs its book")
	check(Spells.can_cast("meteor", "mage", 9, {"book_spells_master": true}), "Meteor with the book at rank 9")
	check(not Spells.can_cast("meteor", "mage", 7, {"book_spells_master": true}), "Meteor not before rank 8")


func test_role_kits_are_real_and_distinct() -> void:
	var weapons := {}
	for r: String in Roles.ORDER:
		var kit: Array = Roles.ROLES[r]["kit"]
		check(not kit.is_empty(), "%s has a kit" % r)
		for entry: Array in kit:
			check(ItemDB.exists(String(entry[0])), "%s kit item %s exists" % [r, entry[0]])
		weapons[String(kit[0][0])] = r
		check(Roles.weapon_kinds(r).has(String(ItemDB.info(String(kit[0][0])).get("kind", ""))),
			"%s's first kit item is its own weapon" % r)
	check_eq(weapons.size(), 3, "each role starts with a different weapon")


func test_every_rank_grants_something() -> void:
	for r: String in Roles.ORDER:
		var path: Array = Roles.PATH[r]
		check_eq(path.size(), ItemDB.RANK_TITLES.size(), "%s has a step per rank" % r)
		for i in path.size():
			var p: Dictionary = path[i]
			check(String(p.get("note", "")) != "", "%s rank %d says what it grants" % [r, i])
			if i == 0:
				continue
			var grants := p.keys().filter(func(k: String) -> bool: return k != "note")
			var has_spell := false
			for sid: String in Spells.SPELLS:
				if int((Spells.SPELLS[sid]["ranks"] as Dictionary).get(r, -1)) == i:
					has_spell = true
			check(not grants.is_empty() or has_spell, "%s rank %d grants a perk or a spell" % [r, i])


func test_rank_perks_accumulate() -> void:
	check(not Roles.has_move("warrior", 1, "dash"), "warrior has no dash at rank 1")
	check(Roles.has_move("warrior", 2, "dash"), "warrior dashes at rank 2")
	check(not Roles.has_move("warrior", 3, "double_jump"), "warrior has no double jump at rank 3")
	check(Roles.has_move("warrior", 4, "double_jump"), "warrior double jumps at rank 4")
	check(Roles.has_move("warrior", 9, "dash"), "perks are kept at higher ranks")
	check(Roles.has_move("archer", 2, "double_jump"), "archer double jumps at rank 2")
	check(Roles.has_move("mage", 2, "glide"), "mage glides at rank 2")
	check(bool(Roles.perks("warrior", 9)["undying"]), "warrior undying at rank 9")
	check(not bool(Roles.perks("warrior", 8)["undying"]), "not before rank 9")
	check_near(float(Roles.perks("warrior", 9)["health"]), 90.0, 0.01, "warrior health bonus at max rank")
	check(Roles.max_mana("mage", 9) > Roles.max_mana("mage", 0), "mage mana grows")
	check(Roles.mana_regen("mage", 9) > Roles.mana_regen("mage", 0), "mage regen grows")
	check(Roles.perks("archer", 0)["move"].is_empty(), "no movement perks at rank 0")


func test_rank_thresholds_are_steep_and_increasing() -> void:
	for i in range(1, ItemDB.RANK_XP.size()):
		check(ItemDB.RANK_XP[i] > ItemDB.RANK_XP[i - 1], "rank %d needs more xp" % i)
	check_eq(ItemDB.rank_for_xp(0), 0, "xp 0 is rank 0")
	check_eq(ItemDB.rank_for_xp(ItemDB.RANK_XP[2]), 2, "exact threshold reaches the rank")


func test_invisibility_and_flight_are_drawn_spells() -> void:
	for sid: String in ["veil", "flight"]:
		check(Spells.SPELLS.has(sid), "%s exists" % sid)
		for r: String in Roles.ORDER:
			check(sid in Spells.for_role(r), "%s can learn %s" % [r, sid])
	check_eq(Spells.SPELLS["veil"]["buff"], "invisible", "Veil makes you invisible")
	check_eq(Spells.SPELLS["flight"]["buff"], "flight", "Flight buff")
	var line := GlyphRecognizer.recognize(GlyphRecognizer.sample_points("rise", Rect2(300, 100, 40, 300)))
	check_eq(line["glyph"], "rise", "a vertical upward stroke is the rising line")
	var known := Spells.known("mage", 5, {"book_spells_master": true, "book_spells_adept": true})
	check_eq(Spells.resolve("mage", line, known)["spell"], "flight", "mage draws Flight")
	var flat := GlyphRecognizer.recognize(GlyphRecognizer.sample_points("veil", Rect2(100, 300, 300, 30)))
	check_eq(Spells.resolve("mage", flat, known)["spell"], "veil", "mage draws Veil")
	var down := GlyphRecognizer.sample_points("rise", Rect2(300, 100, 40, 300))
	down.reverse()
	check_eq(GlyphRecognizer.recognize(down)["glyph"], "rise", "open glyphs read both ways: a downward stroke too")
	var side := GlyphRecognizer.recognize(GlyphRecognizer.sample_points("veil", Rect2(100, 300, 300, 30)))
	check(side["glyph"] != "rise", "a horizontal stroke is not the vertical one")


func test_flight_climbs_hovers_and_dives() -> void:
	check(PlayerArcana.flight_velocity_y(0.0, true, false, 1.0) > 5.0, "holding jump climbs")
	check_near(PlayerArcana.flight_velocity_y(-10.0, false, false, 1.0), 0.0, 0.1, "letting go hovers")
	check(PlayerArcana.flight_velocity_y(0.0, false, true, 1.0) < -5.0, "sprint dives")


func test_achievements_menu_lists_every_category() -> void:
	var text := Achievements.menu_bbcode()
	check(text.contains("/ %d unlocked" % Achievements.LIST.size()), "menu shows the unlocked count")
	for id: String in Achievements.LIST:
		var a: Dictionary = Achievements.LIST[id]
		check(String(a.get("cat", "")) in Achievements.CATEGORIES, "%s has a known category" % id)
		if not bool(a.get("secret", false)):
			check(text.contains(String(a["name"])), "menu lists %s" % id)


func test_books_teach_their_gated_spells_and_drop_from_chests() -> void:
	var dropped := {}
	for tier: int in ArcanaItems.CHEST_LOOT:
		for entry: Array in ArcanaItems.CHEST_LOOT[tier]:
			check(ItemDB.exists(String(entry[0])), "chest loot %s exists" % entry[0])
			dropped[String(entry[0])] = true
	for id: String in Spells.SPELLS:
		var book := String(Spells.SPELLS[id].get("book", ""))
		if book == "":
			continue
		check(dropped.has(book), "%s (for %s) can be found in chests" % [book, id])
	check(Spells.can_cast("veil", "warrior", 4, {"book_spells_adept": true}), "warrior Veil with the adept tome")


func test_rank_rows_cover_every_rank() -> void:
	for r: String in Roles.ORDER:
		var rows := Roles.rank_rows(r)
		check_eq(rows.size(), Roles.PATH[r].size(), "%s rank rows" % r)
