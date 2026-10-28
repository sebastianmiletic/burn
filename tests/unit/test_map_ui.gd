extends TestCase
## Map/quest UI logic that does not need a GPU: fog of war persistence,
## boss symbols, quest categories and compass text.


class FakeWorld:
	extends Node
	var session := {}
	var discovered := {}

	func map_image(_dim: int) -> Image:
		var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
		img.set_meta("metres_per_pixel", 16.0)
		img.set_meta("world_size", 1024.0)
		return img

	func locations(_dim: int) -> Array:
		return []


func test_fog_reveals_feathered_disc() -> void:
	var w := FakeWorld.new()
	var fog := MapFog.of(w)
	check(fog != null, "fog created")
	check(MapFog.of(w) == fog, "one fog per world")
	check_eq(fog.seen(0, Vector3(500, 0, 500)), 0.0, "unexplored at start")
	fog.reveal(0, Vector3(500, 0, 500))
	check(fog.seen(0, Vector3(500, 0, 500)) > 0.95, "centre fully seen")
	check(fog.seen(0, Vector3(500 + MapFog.REVEAL_RADIUS * 0.9, 0, 500)) < 0.6, "edge feathered")
	check_eq(fog.seen(0, Vector3(900, 0, 900)), 0.0, "far away stays unexplored")
	check(fog.has_unsaved(), "changes marked unsaved")
	w.free()


func test_fog_round_trip() -> void:
	var w := FakeWorld.new()
	var fog := MapFog.of(w)
	fog.reveal(0, Vector3(300, 0, 200))
	var d := fog.to_dict()
	var w2 := FakeWorld.new()
	w2.session = {"slot": -1, "seed": 1, "save": {"map_fog": d}}
	var fog2 := MapFog.of(w2)
	check(fog2.seen(0, Vector3(300, 0, 200)) > 0.95, "loaded from the save hook")
	check_eq(fog2.seen(0, Vector3(800, 0, 800)), 0.0)
	w.free()
	w2.free()


func test_boss_symbols() -> void:
	check_eq(MapIcons.boss_icon("leviathan"), &"serpent")
	check_eq(MapIcons.boss_icon("warden"), &"skull")
	check_eq(MapIcons.boss_icon("dragon"), &"dragon")
	check_eq(MapIcons.boss_icon("broodmother"), &"spider")
	check_eq(MapIcons.boss_icon("mountain_king"), &"crown")
	check_eq(MapIcons.boss_icon("hades"), &"flame")
	check_eq(MapIcons.boss_icon("bog_hag"), &"witch")
	check_eq(MapIcons.boss_icon("prism_sentinel"), &"crystal")
	check_eq(MapIcons.boss_icon("some_void_thing"), &"crystal", "unknown Ryft bosses still get a crystal")


func test_quest_categories() -> void:
	check_eq(QuestLogScreen.category_of({"main": true}), QuestLogScreen.Tab.MAIN)
	check_eq(QuestLogScreen.category_of({"main": false}), QuestLogScreen.Tab.SIDE)
	check_eq(QuestLogScreen.category_of({"category": "activity"}), QuestLogScreen.Tab.ACTIVITY)
	check_eq(QuestLogScreen.category_of({"main": true, "completed": true}), QuestLogScreen.Tab.DONE)


func test_compass_and_distance() -> void:
	check_eq(QuestMarkers.compass(Vector3(0, 0, -100)), "north")
	check_eq(QuestMarkers.compass(Vector3(100, 0, 0)), "east")
	check_eq(QuestMarkers.compass(Vector3(-70, 0, 70)), "south-west")
	check_eq(QuestMarkers.distance_text(312.0), "310 m")
	check_eq(QuestMarkers.distance_text(1440.0), "1.4 km")


func test_every_boss_has_its_own_symbol() -> void:
	var seen := {}
	for kind in ["warden", "leviathan", "dragon", "broodmother", "mountain_king", "hades", "cerberus", "bog_hag",
			"ryft_sentinel", "void_sovereign", "kraken", "charybdis"]:
		var icon := MapIcons.boss_icon(kind)
		check(not seen.has(icon), "%s has a symbol of its own (%s shared with %s)" % [kind, icon, seen.get(icon, "")])
		seen[icon] = kind
	check_eq(MapIcons.boss_icon("kraken"), &"kraken")
	check_eq(MapIcons.boss_icon("charybdis"), &"whirlpool")


func test_place_kinds_and_registration() -> void:
	var wreck := Location.new(&"wreck_2", "Saltbound Wreck", Location.Kind.RUIN, Vector3.ZERO)
	check_eq(MapIcons.place_of(null, wreck)["icon"], &"wreck", "wrecks by id prefix")
	var adit := Location.new(&"frost_adit", "Frosthold Adit", Location.Kind.CRYPT, Vector3.ZERO)
	check_eq(MapIcons.place_of(null, adit)["icon"], &"mine")
	var cave := Location.new(&"some_hole", "A Hole", Location.Kind.CRYPT, Vector3.ZERO)
	check_eq(MapIcons.place_of(null, cave)["icon"], &"cave")
	var oasis := Location.new(&"x_oasis", "Palm Spring", Location.Kind.RUIN, Vector3.ZERO)
	oasis.set_meta(&"map_kind", "oasis")
	check_eq(MapIcons.place_of(null, oasis)["icon"], &"oasis", "tag via meta")
	MapIcons.register_kind("test_beacon", &"lighthouse", "Beacon", MapIcons.QUEST)
	var beacon := Location.new(&"b", "Beacon", Location.Kind.RUIN, Vector3.ZERO)
	beacon.set_meta(&"map_kind", "test_beacon")
	var place := MapIcons.place_of(null, beacon)
	check_eq(place["icon"], &"lighthouse")
	check_eq(place["sub"], "Beacon")
	MapIcons.register_kind("isle_", &"palm", "Isle", MapIcons.GREEN, true)
	check_eq(MapIcons.place_of(null, Location.new(&"isle_far", "Far Isle", Location.Kind.RUIN, Vector3.ZERO))["icon"], &"palm", "id prefix")
	var unknown := Location.new(&"zzz", "?", Location.Kind.RUIN, Vector3.ZERO)
	unknown.set_meta(&"map_kind", "never_registered")
	check_eq(MapIcons.place_of(null, unknown)["icon"], &"ruin", "unknown tag falls back to the location kind")
	var drew := []
	MapIcons.register_glyph(&"test_glyph", func(_ci: CanvasItem, _at: Vector2, _r: float, _f: Color, _o: Color) -> void: drew.append(1))
	var canvas := Control.new()
	MapIcons.draw_glyph(canvas, &"test_glyph", Vector2.ZERO, 8.0, Color.WHITE, Color.BLACK)
	check_eq(drew.size(), 1, "registered glyph drawer is used")
	canvas.free()
	check(&"test_glyph" in MapIcons.glyphs())
	# A static registry must not outlive the test's lambda (freed scripts abort at exit).
	MapIcons._glyphs.erase(&"test_glyph")


func test_markers_save_with_the_fog() -> void:
	var w := FakeWorld.new()
	var marks := MapMarkers.of(w)
	var m := marks.add(Vector3(100, 5, 200), 0, "  Home  ", &"home", MapIcons.MARKER_COLOURS[2])
	check_eq(m["name"], "Home", "name trimmed")
	marks.add(Vector3(10, 0, 10), 1, "", &"not_an_icon")
	check_eq(marks.own[1]["icon"], "pin", "unknown icons become pins")
	check_eq(marks.own[1]["name"], "Marker 2", "unnamed markers get a number")
	check_eq(marks.visible(0).size(), 1, "markers are per dimension")
	marks.edit(m["id"], {"name": "Base", "icon": &"flag", "color": MapIcons.MARKER_COLOURS[3], "shared": true})
	check_eq(marks.find(m["id"])["name"], "Base")
	check(MapFog.of(w).has_unsaved(), "marker changes mark the fog file unsaved")
	var d := MapFog.of(w).to_dict()
	var w2 := FakeWorld.new()
	w2.session = {"slot": -1, "seed": 1, "save": {"map_fog": d}}
	var marks2 := MapMarkers.of(w2)
	check_eq(marks2.own.size(), 2, "markers load back with the fog")
	var back := marks2.find(m["id"])
	check_eq(back["name"], "Base")
	check_eq(MapMarkers.icon(back), &"flag")
	check(MapMarkers.colour(back).is_equal_approx(Color(MapIcons.MARKER_COLOURS[3].to_html(false))))
	check(back["shared"], "sharing flag kept")
	check_eq(marks2.shared_list().size(), 1)
	marks2.set_party({1: [{"id": "x", "name": "Their camp", "icon": "tent", "color": "ff0000", "pos": Vector3(1, 2, 3), "dim": 0, "owner": "Ash"}],
		2: [{"bad": true}], 5: [{"id": "mine", "pos": Vector3.ZERO}]}, 5)
	var vis := marks2.visible(0)
	check_eq(vis.size(), 2, "own + one valid party marker; own peer and junk ignored")
	marks2.remove(m["id"])
	check_eq(marks2.own.size(), 1)
	w.free()
	w2.free()


func test_party_reveal_is_tracked_per_explorer() -> void:
	var w := FakeWorld.new()
	var fog := MapFog.of(w)
	fog.reveal(0, Vector3(200, 0, 200))
	fog.reveal(0, Vector3(700, 0, 700), MapFog.REVEAL_RADIUS, false, 7)
	fog.reveal(0, Vector3(203, 0, 200))
	fog.reveal(0, Vector3(800, 0, 300), MapFog.REVEAL_RADIUS, false, 7)
	check(fog.seen(0, Vector3(700, 0, 700)) > 0.95, "a companion's path is uncovered")
	check(fog.seen(0, Vector3(800, 0, 300)) > 0.95, "each explorer is throttled on its own")
	w.free()


## The Gates of Hades show as a portal on the map, and creative inspection can
## teleport there, landing in front of the portal rather than inside the rock.
func test_hades_portal_on_map_and_creative_teleport() -> void:
	var gate := Location.new(&"gates_of_hades", "Gates of Hades", Location.Kind.GATE, Vector3(100, -80, 200))
	gate.add_spawn("portal", Vector3(100, -90, 180), {"to": 1})
	var place := MapIcons.place_of(null, gate)
	check_eq(place["icon"], &"portal", "the Gates of Hades draw as a portal")
	check_eq(place["color"], MapIcons.PORTAL)
	check_eq(place["sub"], "Portal to Hades")
	check(GameWorld.creative_destination(gate), "the Gates of Hades are a creative teleport destination")
	check(GameWorld.creative_target(gate).is_equal_approx(Vector3(100, -89.9, 189)), "creative teleport lands before the portal")
	var village := Location.new(&"emberfall", "Emberfall", Location.Kind.VILLAGE, Vector3(5, 10, 5))
	village.add_spawn("portal", Vector3(40, 10, 40), {"to": 2})
	check_eq(GameWorld.creative_target(village), Vector3(5, 13, 5), "villages still land at their centre")
	var ruin := Location.new(&"ruin_3", "Old Ruin", Location.Kind.RUIN, Vector3.ZERO)
	check(not GameWorld.creative_destination(ruin), "plain ruins are not listed")
