class_name ArenaDirector
extends Node3D
## Streams the modelled boss arenas on every machine. Locations carry one or
## more `{"type": "arena", "arena": <kind>, "center", "radius", ...}` props
## (written by Battlegrounds / Lairs together with the arena's STRUCTURE
## collision). Within BUILD_DISTANCE of the local player an arena's geometry is
## generated on a worker thread (ArenaBuilders), then instantiated a few
## pieces per frame; beyond FREE_DISTANCE (or in another dimension) it is freed.

const BUILD_DISTANCE := 320.0
const FREE_DISTANCE := 430.0
const POLL := 0.25
const FRAME_BUDGET_USEC := 2500

var _built := {}      # key -> ArenaInstance
var _pending := {}    # key -> [task id, ArenaBuild, Location, dim]
var _queue: Array[ArenaInstance] = []
var _poll := 0.0
var _dim := -1


func _init() -> void:
	name = "ArenaDirector"


static func arena_props(loc: Location) -> Array:
	var out := []
	for p: Dictionary in loc.props:
		if String(p.get("type", "")) == "arena":
			out.append(p)
	return out


func _exit_tree() -> void:
	for key: String in _pending:
		WorkerThreadPool.wait_for_task_completion(int(_pending[key][0]))
	_pending.clear()


func _process(delta: float) -> void:
	_finish_tasks()
	_instantiate()
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = POLL
	var w := GameWorld.instance
	if w == null or w.local_player == null:
		return
	# One build at a time, and never while the world is still loading.
	if Game.state != Game.State.PLAYING:
		return
	var dim := w.local_dimension
	var eye := w.local_player.global_position
	var wanted := {}
	for loc in w.locations(dim):
		var props := arena_props(loc)
		for i in props.size():
			var p: Dictionary = props[i]
			var key := "%d:%s:%d" % [dim, loc.id, i]
			var d := eye.distance_to(p["center"]) - float(p.get("radius", 40.0))
			if d < FREE_DISTANCE and (d < BUILD_DISTANCE or _built.has(key) or _pending.has(key)):
				wanted[key] = true
			if d < BUILD_DISTANCE and not _built.has(key) and _pending.is_empty():
				_start(key, p, loc, dim)
	for key: String in _built.keys():
		if not wanted.has(key):
			var inst: ArenaInstance = _built[key]
			_queue.erase(inst)
			inst.queue_free()
			_built.erase(key)


func _start(key: String, p: Dictionary, loc: Location, dim: int) -> void:
	var b := ArenaBuild.new(p)
	# Low priority: terrain streaming always comes first.
	var task := WorkerThreadPool.add_task(ArenaBuilders.run.bind(b), false, "arena " + b.kind)
	_pending[key] = [task, b, loc, dim]


func _finish_tasks() -> void:
	if _pending.is_empty():
		return
	var w := GameWorld.instance
	for key: String in _pending.keys():
		var entry: Array = _pending[key]
		if not WorkerThreadPool.is_task_completed(int(entry[0])):
			continue
		WorkerThreadPool.wait_for_task_completion(int(entry[0]))
		_pending.erase(key)
		if w == null or int(entry[3]) != w.local_dimension:
			continue
		var inst := ArenaInstance.new()
		inst.setup(entry[1], entry[2], int(entry[3]))
		add_child(inst)
		_built[key] = inst
		_queue.append(inst)


func _instantiate() -> void:
	var t0 := Time.get_ticks_usec()
	while not _queue.is_empty() and Time.get_ticks_usec() - t0 < FRAME_BUDGET_USEC:
		var inst: ArenaInstance = _queue[0]
		if not is_instance_valid(inst) or inst.step():
			_queue.pop_front()
