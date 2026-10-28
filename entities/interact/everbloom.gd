class_name Everbloom
extends Entity
## The great glowing tree of the Everbloom Cavern (world revision 5, UndergroundSites).
## Harvest it (interact) for leaves; fruit and sap regrow slowly and go into potions.
## Any damage kills it: the tree withers for good and the cavern roof falls in (CaveCollapse).

## Seconds before fruit and sap can be taken again.
const FRUIT_REGROW := 180.0
const SAP_REGROW := 420.0
const LEAF_REGROW := 20.0
## Saved with the opened chests once the tree has died.
const WITHERED_KEY := "everbloom_cavern:withered"

signal collapse_started(tree: Everbloom)

var floor_y := 0.0
var top := 0.0
var _leaf_at := 0.0
var _fruit_at := 0.0
var _sap_at := 0.0
var _canopy: Array[MeshInstance3D] = []
var _glow: OmniLight3D


func _init() -> void:
	kind = "ug_everbloom"
	team = Team.NEUTRAL
	display_name = "The Everbloom"
	max_health = 1.0
	health = 1.0
	hit_radius = 3.2
	hit_height = 14.0
	body.collides = false
	body.gravity = 0.0


func on_spawned(data: Dictionary) -> void:
	floor_y = float(data.get("floor", global_position.y))
	top = float(data.get("top", global_position.y + 40.0))
	var bark := MaterialLibrary.stone(&"iron")
	_part(CylinderMesh.new(), Vector3(2.4, 16.0, 2.4), Vector3(0, 8.0, 0), bark)
	for k in 6:
		var a := TAU * k / 6.0
		_part(CylinderMesh.new(), Vector3(0.9, 7.0, 0.9), Vector3(cos(a) * 3.0, 1.2, sin(a) * 3.0), bark).rotation = Vector3(sin(a) * 1.1, 0, -cos(a) * 1.1)
	var leaf := MaterialLibrary.emissive(Color(0.45, 1.0, 0.7), 1.6)
	for k in 7:
		var a := TAU * k / 7.0
		var r := 4.0 if k > 0 else 0.0
		_canopy.append(_part(SphereMesh.new(), Vector3(8, 5, 8), Vector3(cos(a) * r, 17.0 + (k % 2) * 2.0, sin(a) * r), leaf))
	_glow = OmniLight3D.new()
	_glow.light_color = Color(0.55, 1.0, 0.8)
	_glow.light_energy = 2.5
	_glow.omni_range = 45.0
	_glow.position.y = 15.0
	add_child(_glow)
	var w := world()
	if w != null and w.opened_chests.has(WITHERED_KEY):
		dead = true
		health = 0.0
		on_event("withered", null)


func _part(mesh: PrimitiveMesh, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.scale = size
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi


## What a harvest at `now` yields ({item: count}), given when each part regrows.
static func harvest_yield(now: float, leaf_at: float, fruit_at: float, sap_at: float) -> Dictionary:
	var out := {}
	if now >= leaf_at:
		out["everbloom_leaf"] = 3
	if now >= fruit_at:
		out["everbloom_fruit"] = 1
	if now >= sap_at:
		out["everbloom_sap"] = 1
	return out


func interact_prompt(_p: Player) -> String:
	return "" if dead else "Harvest the Everbloom"


func local_interact(_p: Player) -> void:
	world().replicator.request_interact(net_id)


func server_interact(_p: Player) -> void:
	if dead:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var got := harvest_yield(now, _leaf_at, _fruit_at, _sap_at)
	if got.has("everbloom_leaf"):
		_leaf_at = now + LEAF_REGROW
	if got.has("everbloom_fruit"):
		_fruit_at = now + FRUIT_REGROW
	if got.has("everbloom_sap"):
		_sap_at = now + SAP_REGROW
	for item: String in got:
		world().drop_item(global_position + Vector3(0, 1.2, 1.5), item, int(got[item]), dimension)


## Any wound, however light (a pickaxe, an arrow, fire), is fatal.
func _on_damaged(_amount: float, _source_id: int, _kind: String) -> void:
	health = 0.0


## The tree withers (saved, so it never regrows) and the cavern starts to fall in (CaveCollapse).
func _on_died() -> void:
	collapse_started.emit(self)
	var w := world()
	if w == null:
		return
	w.opened_chests[WITHERED_KEY] = true
	if w.replicator != null:
		w.replicator.broadcast_entity_event(net_id, "withered")
	w.add_child(CaveCollapse.new().setup(global_position, UndergroundSites.EVERBLOOM_RADII.x * 0.75, floor_y, dimension, net_id))


func on_event(event: String, _arg: Variant) -> void:
	if event == "withered":
		dead = true
		for c in _canopy:
			c.material_override = MaterialLibrary.emissive(Color(0.25, 0.2, 0.12), 0.1)
		if _glow != null:
			_glow.light_energy = 0.2
