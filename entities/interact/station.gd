class_name Station
extends Entity
## A crafting station in the world: workbench, furnace, anvil, alchemy table or campfire
## table. Spawned server-side (GameWorld.spawn_entity("station", pos, dim,
## {"station": kind, "yaw": radians})) and mirrored on every client like any
## entity. Using it is purely local: it opens the crafting book for this
## station (Events.station_open), and crafting itself is client-local.
## The furnace burns: firelight, flame, sparks, chimney smoke and a crackle.

const KINDS := ["workbench", "furnace", "anvil", "alchemy", "campfire", "cauldron"]
const CRACKLE_RANGE := 14.0

var station_kind := "workbench"
var _model: Node3D
var _crackle := 0.0


func _init() -> void:
	kind = "station"
	team = Team.NEUTRAL
	hit_radius = 0.8
	hit_height = 1.2
	max_health = 1.0
	health = 1.0
	body.collides = false
	body.gravity = 0.0


func on_spawned(data: Dictionary) -> void:
	var k := String(data.get("station", "workbench"))
	station_kind = k if k in KINDS else "workbench"
	display_name = ItemDB.station_name(station_kind)
	yaw = float(data.get("yaw", 0.0))
	rotation.y = yaw
	if station_kind == "cauldron":
		_model = Node3D.new()
		ArcanaModels.cauldron(_model, true)
	else:
		_model = StationModels.build(station_kind, true)
	add_child(_model)


func interact_prompt(_p: Node) -> String:
	return "Use " + display_name


func local_interact(_p: Node) -> void:
	if station_kind == "cauldron":
		Audio.play("potion", global_position, -6.0)
		BrewingScreen.open_for(self)
		return
	Audio.play("chest" if station_kind == "workbench" else ("hit_metal" if station_kind == "anvil" else ("fire" if station_kind == "campfire" else "potion")), global_position, -6.0)
	Events.station_open.emit(station_kind, self)


## Stations are not damaged by stray swings.
func take_damage(_amount: float, _source_id := 0, _damage_kind := "hit") -> float:
	return 0.0


func snapshot() -> Array:
	return [global_position, yaw, health, 0, 0.0, 0, false]


func apply_snapshot(s: Array, _at_time: float) -> void:
	global_position = s[0]
	yaw = s[1]
	rotation.y = yaw


func _process(delta: float) -> void:
	if not (station_kind in ["furnace", "campfire"]) or not visible:
		return
	_crackle -= delta
	if _crackle > 0.0:
		return
	_crackle = randf_range(0.6, 1.8)
	var w := world()
	if w == null or w.local_player == null:
		return
	if w.local_player.global_position.distance_to(global_position) < CRACKLE_RANGE:
		Audio.play("fire", global_position + Vector3(0, 0.4, 0.5), -8.0, randf_range(0.85, 1.15))
