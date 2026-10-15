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
