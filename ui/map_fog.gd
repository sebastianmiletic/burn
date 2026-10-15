class_name MapFog
extends RefCounted
## Fog of war for the minimap and world map: what the local player has seen.
## One soft greyscale mask per dimension (CELL metres per texel, 0 unexplored
## .. 255 explored), painted with a feathered disc around the player.
##
## One instance per GameWorld (`MapFog.of(world)`, kept as world metadata).
## Persistence, either:
##   * in the GameWorld save, if GameWorld wires the two hooks:
##       save_data():          "map_fog": MapFog.save_dict(self),
##       _load_world_state():  (nothing needed; `of()` reads save["map_fog"])
##   * otherwise in its own file next to the saves, keyed by slot and seed
##     (`saves/map_fog_<slot>.burn`), written every few seconds while it
##     changes and when the HUD leaves the tree.

const CELL := 8.0
const REVEAL_RADIUS := 120.0       ## fully seen within ~80 %, feathered to here
const META := &"map_fog"
const VERSION := 1

var _layers := {}          # dim -> {"img": Image, "tex": ImageTexture, "n": int, "dirty": bool}
var _unsaved := false
var _world: WeakRef
var _slot := -1
var _seed := 0
var _last_reveal := {}     # dim -> Vector2


## The fog of `world`, created (and loaded) on first use.
static func of(world: Object) -> MapFog:
	if world == null or not is_instance_valid(world):
		return null
	if world.has_meta(META):
		return world.get_meta(META)
	var fog := MapFog.new()
	fog._world = weakref(world)
	world.set_meta(META, fog)
	fog._load()
	return fog


## GameWorld save hook: the fog as plain data.
static func save_dict(world: Object) -> Dictionary:
	var fog := of(world)
	return fog.to_dict() if fog != null else {}


func _world_size(dim: int) -> float:
	var w: Object = _world.get_ref() if _world != null else null
	var layers := MapLayers.of(w, dim)
	return layers.world_size if layers != null else 2048.0


func _layer(dim: int) -> Dictionary:
	if _layers.has(dim):
		return _layers[dim]
	var n := clampi(int(ceil(_world_size(dim) / CELL)), 16, 2048)
	var img := Image.create(n, n, false, Image.FORMAT_L8)
	var l := {"img": img, "tex": null, "n": n, "dirty": true}
	_layers[dim] = l
	return l


## Mark the area around `pos` as seen. Cheap when the player has not moved.
func reveal(dim: int, pos: Vector3, radius := REVEAL_RADIUS, force := false) -> void:
	var at := Vector2(pos.x, pos.z)
	if not force and _last_reveal.has(dim) and (_last_reveal[dim] as Vector2).distance_to(at) < 6.0:
		return
	_last_reveal[dim] = at
	var l := _layer(dim)
	var img: Image = l["img"]
	var n: int = l["n"]
	var c := at / CELL
	var rc := radius / CELL
	var changed := false
	for z in range(maxi(0, int(c.y - rc) - 1), mini(n, int(c.y + rc) + 2)):
		for x in range(maxi(0, int(c.x - rc) - 1), mini(n, int(c.x + rc) + 2)):
			var d := Vector2(x + 0.5, z + 0.5).distance_to(c) / rc
			if d >= 1.0:
				continue
			var v := 1.0 - smoothstep(0.62, 1.0, d)
			var old := img.get_pixel(x, z).r
			if v > old + 0.004:
				img.set_pixel(x, z, Color(v, v, v))
				changed = true
	if changed:
		l["dirty"] = true
		_unsaved = true


## 0 unexplored .. 1 explored at a world position.
func seen(dim: int, pos: Vector3) -> float:
	var l := _layer(dim)
	var n: int = l["n"]
	var x := int(pos.x / CELL)
	var z := int(pos.z / CELL)
	if x < 0 or z < 0 or x >= n or z >= n:
		return 0.0
	return (l["img"] as Image).get_pixel(x, z).r


func texture(dim: int) -> ImageTexture:
	var l := _layer(dim)
	if l["tex"] == null:
		l["tex"] = ImageTexture.create_from_image(l["img"])
		l["dirty"] = false
	elif l["dirty"]:
		(l["tex"] as ImageTexture).update(l["img"])
		l["dirty"] = false
	return l["tex"]


func has_unsaved() -> bool:
	return _unsaved


# --- Persistence ---------------------------------------------------------------------

func to_dict() -> Dictionary:
	var dims := {}
	for dim: int in _layers:
		var img: Image = _layers[dim]["img"]
		dims[dim] = {"n": int(_layers[dim]["n"]), "data": img.get_data().compress(FileAccess.COMPRESSION_ZSTD)}
	return {"version": VERSION, "cell": CELL, "dims": dims}


func from_dict(d: Dictionary) -> bool:
	if d.is_empty() or float(d.get("cell", 0.0)) != CELL:
		return false
	var dims: Dictionary = d.get("dims", {})
	for dim: int in dims:
		var e: Dictionary = dims[dim]
		var n := int(e.get("n", 0))
		var bytes: PackedByteArray = e.get("data", PackedByteArray())
		if n <= 0 or bytes.is_empty():
			continue
		var raw := bytes.decompress(n * n, FileAccess.COMPRESSION_ZSTD)
		if raw.size() != n * n:
			continue
		_layers[int(dim)] = {"img": Image.create_from_data(n, n, false, Image.FORMAT_L8, raw), "tex": null, "n": n, "dirty": true}
	return true


func _path() -> String:
	return RuntimePaths.file("saves/map_fog_%d.burn" % _slot)


func _load() -> void:
	var w: Object = _world.get_ref()
	var session: Variant = w.get("session") if w != null else null
	var loaded := false
	if session is Dictionary:
		_slot = int((session as Dictionary).get("slot", -1))
		_seed = int((session as Dictionary).get("seed", 0))
		var save: Dictionary = (session as Dictionary).get("save", {})
		if save.get("map_fog") is Dictionary:
			loaded = from_dict(save["map_fog"])
		elif not save.is_empty() and _slot >= 0 and FileAccess.file_exists(_path()):
			var f := FileAccess.open(_path(), FileAccess.READ)
			var v: Variant = f.get_var() if f != null else null
			if v is Dictionary and int((v as Dictionary).get("seed", -1)) == _seed:
				loaded = from_dict((v as Dictionary).get("fog", {}))
	if not loaded:
		_reveal_known_places(w)


## Saves from before the fog existed: the places already discovered are known.
func _reveal_known_places(w: Object) -> void:
	var discovered: Variant = w.get("discovered") if w != null else null
	if not (discovered is Dictionary) or (discovered as Dictionary).is_empty():
		return
	for dim in [0, 1, 2]:
		var locs: Variant = UiContext.call_on(w, "locations", [dim], [])
		if not (locs is Array):
			continue
		for loc: Object in locs:
			if loc != null and (discovered as Dictionary).has(loc.get("id")):
				reveal(dim, loc.get("center"), maxf(140.0, float(loc.get("radius")) * 2.0), true)


## Writes the fog file (no-op without a save slot or changes).
func save_file() -> void:
	if not _unsaved or _slot < 0:
		return
	DirAccess.make_dir_recursive_absolute(_path().get_base_dir())
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f == null:
		return
	f.store_var({"seed": _seed, "fog": to_dict()})
	_unsaved = false
