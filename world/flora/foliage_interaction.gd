class_name FoliageInteraction
extends Node
## Feeds the `foliage_pushers` / `foliage_pusher_count` shader globals so grass, flowers and
## ferns bend away from bodies walking through them.
##
## GameWorld adds one. Each frame it gathers the local player, other players and creatures near
## the camera (GameWorld.instance.entities_near) plus any nodes registered with track(), and
## writes up to 16 pushers (xyz = feet, w = radius). Moving bodies also leave a short trail of
## shrinking pushers behind them, so trampled grass stays flattened for a moment and springs
## back over ~1.5 s from the edges in.

const MAX_PUSHERS := 16
const TRAIL_LIFE := 1.5       ## seconds a flattened spot takes to recover
const TRAIL_STEP := 0.35      ## metres between trail samples
const TRAIL_KEEP := 5         ## samples per body
const NEAR := 40.0            ## only bodies this close to the camera matter

## Extra bodies (tests, props): [{node: Node3D, radius: float}]
var _tracked: Array = []
var _trails := {}             # instance id -> Array of [Vector3 pos, float time, float radius]
var _last := {}               # instance id -> Vector3 last trail sample
var _img: Image
var _tex: ImageTexture
var _time := 0.0
var _data := PackedFloat32Array()


func _ready() -> void:
	_data.resize(MAX_PUSHERS * 4)
	_img = Image.create_empty(MAX_PUSHERS, 1, false, Image.FORMAT_RGBAF)
	_tex = ImageTexture.create_from_image(_img)
	RenderingServer.global_shader_parameter_set(&"foliage_pushers", _tex)
	RenderingServer.global_shader_parameter_set(&"foliage_pusher_count", 0)


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set(&"foliage_pusher_count", 0)


## Registers a body that is not a GameWorld entity (radius in metres).
func track(node: Node3D, radius := 0.6) -> void:
	_tracked.append({"node": node, "radius": radius})


func untrack(node: Node3D) -> void:
	_tracked = _tracked.filter(func(e: Dictionary) -> bool: return e.node != node)


func _process(delta: float) -> void:
	_time += delta
	var cam := _camera_pos()
	var bodies: Array = []   # [id, pos, radius, priority]
	var w: GameWorld = GameWorld.instance
	if w != null and is_instance_valid(w):
		var lp: Player = w.local_player
		if lp != null and is_instance_valid(lp) and not lp.dead:
			bodies.append([lp.get_instance_id(), lp.global_position, 0.75, 0])
		for e: Entity in w.entities_near(cam, NEAR, w.local_dimension):
			if e == lp:
				continue
			var r := clampf(e.hit_radius * 1.15, 0.4, 3.5)
			bodies.append([e.get_instance_id(), e.global_position, r, 1])
	for t: Dictionary in _tracked:
		var n: Node3D = t.node
		if is_instance_valid(n) and n.is_inside_tree():
			bodies.append([n.get_instance_id(), n.global_position, t.radius, 0])
	bodies.sort_custom(func(a: Array, b: Array) -> bool:
		if a[3] != b[3]:
			return a[3] < b[3]
		return a[1].distance_squared_to(cam) < b[1].distance_squared_to(cam))

	# Trail samples.
	var alive := {}
	for b: Array in bodies:
		var id: int = b[0]
		alive[id] = true
		var p: Vector3 = b[1]
		if not _last.has(id) or (_last[id] as Vector3).distance_to(p) > TRAIL_STEP:
			_last[id] = p
			var tr: Array = _trails.get(id, [])
			tr.push_front([p, _time, b[2]])
			if tr.size() > TRAIL_KEEP:
				tr.resize(TRAIL_KEEP)
			_trails[id] = tr
	for id: int in _trails.keys():
		if not alive.has(id):
			var tr: Array = _trails[id]
			if tr.is_empty() or _time - float(tr[0][1]) > TRAIL_LIFE:
				_trails.erase(id)
				_last.erase(id)

	# Write: current positions first, then trails (youngest first, priority bodies first).
	var n := 0
	for b: Array in bodies:
		if n >= MAX_PUSHERS:
			break
		_write(n, b[1], b[2])
		n += 1
	var age_rank: Array = []
	for b: Array in bodies:
		var tr: Array = _trails.get(b[0], [])
		for s: Array in tr:
			var age := _time - float(s[1])
			if age < TRAIL_LIFE and (s[0] as Vector3).distance_to(b[1]) > 0.25:
				age_rank.append([age + float(b[3]) * 0.5, s[0], s[2] * pow(1.0 - age / TRAIL_LIFE, 0.6)])
	for id: int in _trails:
		if alive.has(id):
			continue
		for s: Array in _trails[id]:
			var age := _time - float(s[1])
			if age < TRAIL_LIFE:
				age_rank.append([age + 1.0, s[0], s[2] * pow(1.0 - age / TRAIL_LIFE, 0.6)])
	age_rank.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for s: Array in age_rank:
		if n >= MAX_PUSHERS:
			break
		if s[2] < 0.12:
			continue
		_write(n, s[1], s[2])
		n += 1
	for i in range(n, MAX_PUSHERS):
		_write(i, Vector3.ZERO, 0.0)
	_img.set_data(MAX_PUSHERS, 1, false, Image.FORMAT_RGBAF, _data.to_byte_array())
	_tex.update(_img)
	RenderingServer.global_shader_parameter_set(&"foliage_pusher_count", n)


func _write(i: int, p: Vector3, r: float) -> void:
	_data[i * 4] = p.x
	_data[i * 4 + 1] = p.y
	_data[i * 4 + 2] = p.z
	_data[i * 4 + 3] = r


func _camera_pos() -> Vector3:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam != null:
		return cam.global_position
	var w: GameWorld = GameWorld.instance
	if w != null and is_instance_valid(w) and w.local_player != null:
		return w.local_player.global_position
	return Vector3.ZERO
