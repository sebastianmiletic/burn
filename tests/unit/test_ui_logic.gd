extends TestCase
## UI pure logic plus a compile check of every ui/ script.


func test_every_ui_script_compiles() -> void:
	var dir := DirAccess.open("res://ui")
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var script: GDScript = load("res://ui/" + f)
		check(script != null and script.can_instantiate(), "ui/%s compiles" % f)


func test_rune_tables_are_complete_and_unique() -> void:
	check_eq(RuneGlyph.NAMES.size(), 16)
	check_eq(RuneGlyph.KEYS.size(), 16)
	check_eq(RuneGlyph.STROKES.size(), 16)
	var seen := {}
	for k in RuneGlyph.KEYS:
		check(not seen.has(k), "duplicate rune key %s" % OS.get_keycode_string(k))
		seen[k] = true
	for r in 16:
		check_eq(RuneGlyph.key_to_rune(RuneGlyph.KEYS[r]), r)
	check_eq(RuneGlyph.key_to_rune(KEY_Q), -1, "unmapped key")


func test_rune_strokes_stay_inside_the_box() -> void:
	for r in 16:
		for stroke: Array in RuneGlyph.STROKES[r]:
			check(stroke.size() >= 2, "rune %d stroke has points" % r)
			for p: Vector2 in stroke:
				check(p.x >= 0.0 and p.x <= 1.0 and p.y >= 0.0 and p.y <= 1.0, "rune %d point in box" % r)


func test_code_text() -> void:
	check_eq(RuneGlyph.code_text(PackedInt32Array([0, 1, 2, 3])), "Ash · Ur · Thorn · Ansu")


func test_damage_number_format() -> void:
	check_eq(DamageNumbers.format(12, false, "hit"), "12")
	check_eq(DamageNumbers.format(40, true, "hit"), "40!")
	check_eq(DamageNumbers.format(15, false, "heal"), "+15")
	check_eq(DamageNumbers.format(7, false, "player"), "-7")


func test_number_and_time_format() -> void:
	check_eq(UiTheme.format_int(0), "0")
	check_eq(UiTheme.format_int(999), "999")
	check_eq(UiTheme.format_int(12450), "12 450")
	check_eq(UiTheme.format_int(-1234567), "-1 234 567")
	check_eq(UiTheme.format_time(65.0), "1m 05s")
	check_eq(UiTheme.format_time(3725.0), "1h 02m")
	check_eq(UiTheme.clock(6.5), "06:30")
	check_eq(UiTheme.clock(23.99), "23:59")


func test_item_stats_cover_weapons_and_potions() -> void:
	check(InventoryScreen.item_stats("sword_iron").contains("damage"), "sword shows damage")
	check(InventoryScreen.item_stats("pickaxe_iron").contains("mining tier iron"), "pickaxe shows tier")
	check(InventoryScreen.item_stats("potion_health").contains("restores"), "potion shows heal")


func test_guest_rules_explain_both_respawn_modes() -> void:
	var on := LobbyScreen.party_rules_text(true)
	var off := LobbyScreen.party_rules_text(false)
	check(on.contains("ON") and on.contains("shrine"), "automatic shrine returns are explicit")
	check(off.contains("OFF") and off.contains("Hold E") and off.contains("3 seconds"), "revive controls are explained")


func test_map_symbols_cover_every_location_kind() -> void:
	for k in Location.Kind.size():
		var loc := Location.new(&"x", "X", k, Vector3.ZERO)
		var place := MapIcons.place_of(null, loc)
		check(place.get("icon", &"poi") != &"poi", "map symbol for location kind %d" % k)
