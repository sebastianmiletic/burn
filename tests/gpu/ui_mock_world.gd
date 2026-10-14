extends Node3D
## Stand-in for GameWorld used only by the UI gallery. Implements the duck-
## typed API the UI calls, backed by a real WorldGen for the map.

var local_player: MockPlayer
var quests := MockQuests.new()
var view := MockView.new()
var discovered := {}
var gen: WorldGen
var _map: Image
var _others: Array = []
var _enemies: Array = []
var ui_open := false


func _init() -> void:
	name = "GameWorld"
	add_to_group(&"game_world")


func setup() -> void:
	gen = WorldGen.new(WorldGen.Dimension.OVERWORLD, 1234)
	gen.prepare()
	_map = _build_map()
	for loc in gen.locations:
		if loc.major or loc.kind == Location.Kind.SHRINE:
			discovered[loc.id] = true
	local_player = MockPlayer.new()
	add_child(local_player)
	local_player.global_position = Vector3(1030, 22, 1060)
	local_player.yaw = 0.5
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = local_player.global_position + Vector3(0, 3, 6)
	cam.look_at(local_player.global_position + Vector3(0, 1.5, 0))
	view.source_camera = cam
	var friend := MockPlayer.new()
	friend.display_name = "Cinderheart"
	add_child(friend)
	friend.global_position = local_player.global_position + Vector3(22, 0, -30)
	_others.append(friend)
	for i in 5:
		var e := Node3D.new()
		e.set_meta("boss", i == 0)
		add_child(e)
		e.global_position = local_player.global_position + Vector3(cos(i * 1.3) * 40.0, 0, sin(i * 1.3) * 40.0)
		_enemies.append(e)
	view.source_camera.current = true


func _build_map() -> Image:
	var n := 512
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var colors := {
		WorldGen.Biome.OCEAN: Color(0.08, 0.12, 0.16), WorldGen.Biome.PLAINS: Color(0.45, 0.42, 0.24),
		WorldGen.Biome.FOREST: Color(0.55, 0.3, 0.12), WorldGen.Biome.PEAKS: Color(0.7, 0.72, 0.75),
		WorldGen.Biome.MARSH: Color(0.22, 0.25, 0.16), WorldGen.Biome.WASTES: Color(0.32, 0.27, 0.25),
	}
	for z in n:
		for x in n:
			var wx := x * 4 + 2
			var wz := z * 4 + 2
			var h := gen.smooth_height(wx, wz)
			var c: Color = colors.get(gen.biome_at(wx, wz), Color.GRAY)
			if h < WorldGen.SEA_LEVEL:
				c = Color(0.05, 0.08, 0.11)
			c = c * (0.7 + clampf(h / 90.0, 0.0, 1.0) * 0.6)
			img.set_pixel(x, z, c)
	return img


func map_image(_dim: int) -> Image:
	return _map


func map_metres_per_pixel(_dim: int) -> float:
	return 4.0


func locations(_dim: int) -> Array:
	return gen.locations


func entities_near(_pos: Vector3, _r: float, _dim: int, _team := -1) -> Array:
	return _enemies


func players_in(_dim: int) -> Array:
	return [local_player] + _others


func time_of_day() -> float:
	return 19.4


func day() -> int:
	return 3


func surface_height_at(x: float, z: float) -> float:
	return gen.surface_height(int(x), int(z))


func camera_yaw() -> float:
	return local_player.yaw


func set_ui_open(open: bool) -> void:
	ui_open = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


class MockPlayer:
	extends Node3D

	var inventory := Inventory.new()
	var yaw := 0.0
	var dimension := 0
	var display_name := "Ashwalker"

	func _init() -> void:
		inventory.add("sword_iron")
		inventory.add("pickaxe_iron")
		inventory.add("torch", 23)
		inventory.add("potion_health", 4)
		inventory.add("iron_ore", 7)
		inventory.add("coal", 12)
		inventory.add("ember_crystal", 3)
		inventory.add("gold_ore", 2)
		inventory.add("stone", 64)
		inventory.add("planks", 18)
		inventory.add("frost_crown")
		inventory.gold = 137

	func use_item_slot(i: int) -> void:
		inventory.remove_from_slot(i)

	func drop_slot(i: int) -> void:
		inventory.remove_from_slot(i, 999)

	func craft(_rid: String) -> bool:
		return true

	func buy(id: String) -> bool:
		inventory.add(id)
		return true

	func sell_slot(i: int) -> bool:
		inventory.remove_from_slot(i)
		return true

	func request_respawn() -> void:
		pass


class MockQuests:
	extends RefCounted

	var _tracked := {"embers": true, "mountain_king": true}

	func _quests() -> Array:
		return [
			{"id": "embers", "title": "Embers in the Ash", "description": "Elder Maren says the old shrines went dark the night the crater woke. Light the shrine of Emberfall, then speak with the blacksmith.",
				"objectives": [{"text": "Rest at the Emberfall Shrine", "current": 1, "target": 1, "done": true}, {"text": "Mine iron ore", "current": 3, "target": 5, "done": false}, {"text": "Speak with Hale the blacksmith", "current": 0, "target": 1, "done": false}],
				"rewards": "120 xp · 25 gold · Iron Sword", "tracked": true},
			{"id": "mountain_king", "title": "Hall of the Mountain King", "description": "Something sits on a throne of gold beneath the Frost Peaks, and it does not like guests.",
				"objectives": [{"text": "Find the Hall beneath the Frost Peaks", "current": 0, "target": 1, "done": false}, {"text": "Defeat the Mountain King", "current": 0, "target": 1, "done": false}],
				"rewards": "600 xp · Frost Crown", "tracked": true},
			{"id": "wolves", "title": "Ash Hounds", "description": "Thornwick's hunters want the hounds gone.",
				"objectives": [{"text": "Slay ghouls in Emberwood", "current": 2, "target": 6, "done": false}], "rewards": "80 xp · 30 gold", "tracked": false},
		]

	func tracked() -> Array:
		return _quests().filter(func(q: Dictionary) -> bool: return _tracked.get(q["id"], false))

	func active() -> Array:
		return _quests()

	func completed() -> Array:
		return [{"id": "arrival", "title": "Arrival", "description": "You woke in the ash outside Emberfall.", "objectives": [{"text": "Reach Emberfall", "current": 1, "target": 1, "done": true}], "rewards": "20 xp", "completed": true}]

	func set_tracked(id: String, on: bool) -> void:
		_tracked[id] = on

	func is_tracked(id: String) -> bool:
		return _tracked.get(id, false)


class MockView:
	extends RefCounted

	var source_camera: Camera3D

	func unproject(p: Vector3) -> Vector2:
		return source_camera.unproject_position(p)
