class_name MenuBackdrop
extends Node3D
## The live world behind the title screens: a real piece of the game world
## (WorldGen + VoxelWorld with a fixed seed) drawn through WorldView in the
## player's render style, lit by SkyController, filmed by a slow cinematic
## camera that cuts between a few shots of notable places.
##
## Lifecycle (one instance at most, at /root/MenuBackdrop):
##   MenuBackdrop.ensure()   intro / main menu / lobby call this; it starts
##                           loading in the background and never blocks UI.
##   MenuBackdrop.release()  Game calls this before it builds a GameWorld, so
##                           there is never more than one world or WorldView.
## Headless runs (tests) never create it.
##
## Streaming uses two VoxelWorlds sharing one WorldGen: one is on screen, the
## other quietly streams the next shot, so cuts never wait for terrain.
## UI reads `reveal` (0..1) to fade its fallback ember field away and
## `caption` / `caption_sub` for the location card.

const SEED := 1717
const FIRST_RADIUS := 4          ## chunks; the first shot loads small and fast
const WORLD_DIM := 0.85           ## the world sits a little darker than in game, under the UI
const FADE_IN := 1.6
const FADE_OUT := 1.2
const FIRST_FADE_IN := 2.6
const LOAD_TIMEOUT_MS := 20000
## Under the glyphs a lower 3D resolution is invisible; the menu stays light.

## Shots, relative to the named location's centre (ground level). Kinds:
##   orbit: radius, height, a0..a1 (radians), look (offset of the target)
##   move:  from..to (camera offsets), look0..look1 (target offsets)
## hour: time of day (SkyController); clear: minimum height above terrain.
const SHOTS := [
	# The Dragon's Keep from the shore at sunset.
	{"loc": &"dragons_keep", "kind": "move", "from": Vector3(-62, 13, 108), "to": Vector3(-24, 12, 108),
		"look0": Vector3(-6, 10, 0), "look1": Vector3(6, 10, 0), "hour": 17.45, "seconds": 22.0, "clear": 8.0},
	# Mirewatch across the marsh lake, over the treetops.
	{"loc": &"mirewatch", "kind": "move", "from": Vector3(-96, 22, -30), "to": Vector3(-90, 19, 24),
		"look0": Vector3(0, 2, -6), "look1": Vector3(0, 2, 6), "hour": 17.2, "seconds": 22.0, "clear": 14.0},
	# Frosthold, high in the peaks: a slow arc over the snowbound roofs.
	{"loc": &"frosthold", "kind": "orbit", "radius": 66.0, "height": 40.0, "a0": 3.55, "a1": 4.1,
		"look": Vector3(0, 2, 0), "hour": 16.3, "seconds": 22.0, "clear": 14.0},
	# Emberfall from above, a slow arc over the roofs.
	{"loc": &"emberfall", "kind": "orbit", "radius": 72.0, "height": 34.0, "a0": 1.15, "a1": 1.75,
		"look": Vector3(0, 0, 0), "hour": 16.9, "seconds": 22.0, "clear": 10.0},
]

enum Phase { WAITING, PREPARING, LOADING, PLAYING }

## Screens that show the backdrop join this group (MenuStage, IntroScreen).
## With none left in the tree for a moment, the backdrop frees itself, so it
## can never outlive the title screens even if nobody calls release().
const USER_GROUP := &"menu_backdrop_user"
const ORPHAN_SECONDS := 1.5

static var _instance: MenuBackdrop

## 0 = nothing shown yet .. 1 = the world is fully up (UI fades its fallback).
var reveal := 0.0
var caption := ""
var caption_sub := ""
## Milliseconds from creation to the first visible frame of the world (-1 = not yet).
var first_frame_ms := -1
## Index of the shot on screen (for captures).
var shot_index := -1
## The current shot's own fade (0 black between cuts .. 1).
var visibility: float:
	get:
		return _fade

var _phase := Phase.WAITING
var _gen: WorldGen
var _worlds: Array[VoxelWorld] = []
var _sky: SkyController
var _view: WorldView
var _cam: Camera3D
var _shots: Array[Dictionary] = []
var _active := 0             # index in _worlds on screen
var _next_shot := 0          # shot index the off-screen world is streaming
var _shot: Dictionary = {}
var _t := 0.0                # seconds into the current shot
var _length := 0.0           # current shot length (may be extended while the next one streams)
var _min_y := PackedFloat32Array()
var _fade := 0.0             # 0 black .. 1 visible
var _prep_state := {"done": false}
var _prep_task := -1
var _created_ms := 0
var _load_started_ms := 0
var _radius := 5
var _shots_shown := 0
var _orphan_t := 0.0
var _forced := -1


# --- Lifecycle ----------------------------------------------------------------------

static func is_supported() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return not "--no-menu-world" in OS.get_cmdline_user_args()


static func instance() -> MenuBackdrop:
	return _instance if _instance != null and is_instance_valid(_instance) else null


## Starts the backdrop if it is not running yet. Cheap; safe to call often.
static func ensure() -> void:
	if not is_supported() or instance() != null:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_instance = MenuBackdrop.new()
	_instance.name = "MenuBackdrop"
	tree.root.add_child.call_deferred(_instance)


## Removes the backdrop immediately (before a GameWorld is built).
static func release() -> void:
	var b := instance()
	_instance = null
	if b != null:
		b._retire()


func _retire() -> void:
	if _instance == self:
		_instance = null
	if is_inside_tree():
		get_parent().remove_child(self)
	queue_free()


func _ready() -> void:
	_created_ms = Time.get_ticks_msec()
	process_priority = 10   # after the sky and the view, so our overrides stick
	_radius = [5, 5, 6, 6][clampi(int(Settings.get_value("graphics", "quality")), 0, 3)]


func _exit_tree() -> void:
	if _instance == self:
		_instance = null
	# The world generator may still be preparing on a worker thread.
	if _prep_task >= 0:
		var reaper := _TaskReaper.new()
		reaper.task = _prep_task
		_prep_task = -1
		var root := Engine.get_main_loop() as SceneTree
		if root != null:
			root.root.add_child.call_deferred(reaper)


func _start() -> void:
	_cam = Camera3D.new()
	_cam.name = "MenuCamera"
	_cam.fov = 52.0
	_cam.near = 0.1
	_cam.far = 700.0
	add_child(_cam)
	_sky = SkyController.new()
	_sky.name = "Sky"
	_sky.process_priority = -10   # runs before us, so our overrides win
	add_child(_sky)
	_sky.time_of_day = float(SHOTS[0]["hour"])
	_view = WorldView.new()
	_view.name = "View"
	_view.source_camera = _cam
	_view.tint = Color.BLACK
	add_child(_view)
	_light_profile()
	Settings.changed.connect(_on_setting)
	_warm_flora()

	_gen = WorldGen.new(WorldGen.Dimension.OVERWORLD, SEED)
	var gen := _gen
	var state := _prep_state
	_prep_task = WorkerThreadPool.add_task(func() -> void:
		gen.prepare()
		state["done"] = true, true, "menu backdrop prepare")
	_phase = Phase.PREPARING


## Flora (after the smooth-terrain merge) caches its meshes once; doing it now,
## behind the intro, keeps the first shot from hitching.
func _warm_flora() -> void:
	var path := "res://world/flora/flora.gd"
	if not ResourceLoader.exists(path):
		return
	var script: Script = load(path)
	if script == null:
		return
	for m: Dictionary in script.get_script_method_list():
		if m.get("name", "") == "warmup":
			script.call("warmup")
			return


func time_of_day() -> float:
	return _sky.time_of_day if _sky != null else 12.0


# --- Main loop ----------------------------------------------------------------------

func _process(delta: float) -> void:
	if get_tree().get_first_node_in_group(USER_GROUP) == null:
		_orphan_t += delta
		if _orphan_t > ORPHAN_SECONDS:
			_retire()
			return
	else:
		_orphan_t = 0.0
	match _phase:
		Phase.WAITING:
			# Coming back from a game: let the old GameWorld (and its WorldView) go first.
			if get_tree().root.get_node_or_null("GameWorld") == null:
				_start()
		Phase.PREPARING:
			if _prep_state["done"]:
				WorkerThreadPool.wait_for_task_completion(_prep_task)
				_prep_task = -1
				_build()
		Phase.LOADING:
			var w := _worlds[_active]
			var loaded := w.loading_progress() >= 0.9 and w.is_area_loaded(w.focus)
			if loaded or Time.get_ticks_msec() - _load_started_ms > LOAD_TIMEOUT_MS:
				var i := _forced if _forced >= 0 else _next_shot_index(-1)
				_forced = -1
				_begin_shot(i, first_frame_ms < 0)
		Phase.PLAYING:
			_play(delta)
	if _view != null:
		var k := _fade * WORLD_DIM
		_view.tint = Color(k, k, k)
	if _sky != null and _phase == Phase.PLAYING:
		_grade()


func _build() -> void:
	for s: Dictionary in SHOTS:
		var loc := _location(s["loc"])
		if loc == null:
			continue
		var shot := s.duplicate()
		var c := loc.center
		c.y = float(_gen.surface_height(int(c.x), int(c.z)))
		shot["center"] = c
		shot["title"] = loc.name
		shot["sub"] = str(WorldGen.BIOME_NAMES[clampi(_gen.biome_at(int(c.x), int(c.z)), 0, WorldGen.BIOME_NAMES.size() - 1)])
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--menu-shot-seconds="):
				shot["seconds"] = float(a.get_slice("=", 1))
		_shots.append(shot)
	if _shots.is_empty():
		var c := Vector3(_gen.size * 0.5, 0, _gen.size * 0.5)
		c.y = float(_gen.surface_height(int(c.x), int(c.z)))
		_shots.append({"kind": "orbit", "radius": 60.0, "height": 25.0, "a0": 0.0, "a1": 0.6, "look": Vector3.ZERO,
			"hour": 17.0, "seconds": 30.0, "clear": 8.0, "center": c, "title": "", "sub": ""})
	# The first world loads alone and small, so the first image comes quickly.
	_worlds.append(_make_world("MenuWorldA", FIRST_RADIUS))
	_worlds[0].focus = _focus_of(_shots[0])
	_active = 0
	_load_started_ms = Time.get_ticks_msec()
	_phase = Phase.LOADING
	# Film the first shot (still black) while it streams in, so materials and
	# shadow pipelines compile now rather than as the world fades up.
	_shot = _shots[0]
	_min_y = _clearance(_shot)
	_place_camera(0.0)


func _make_world(world_name: String, radius: int) -> VoxelWorld:
	var vw := VoxelWorld.new()
	vw.name = world_name
	vw.setup(_gen, 0)
	vw.view_radius = radius
	vw.max_point_lights = 6
	add_child(vw)
	return vw


func _location(id: StringName) -> Location:
	for l in _gen.locations:
		if l.id == id:
			return l
	return null


func _next_shot_index(i: int) -> int:
	return (i + 1) % _shots.size()


## Where a shot's world streams around: between the camera and its target, so
## the loaded disc covers what the lens sees.
func _focus_of(shot: Dictionary) -> Vector3:
	var a: Array = _pose(shot, 0.0)
	var b: Array = _pose(shot, 1.0)
	var cam: Vector3 = ((a[0] as Vector3) + (b[0] as Vector3)) * 0.5
	var target: Vector3 = ((a[1] as Vector3) + (b[1] as Vector3)) * 0.5
	var f := cam.lerp(target, 0.55)
	f.y = (shot["center"] as Vector3).y
	return f


func _begin_shot(index: int, first: bool) -> void:
	shot_index = index
	_shots_shown += 1
	_shot = _shots[index]
	_t = 0.0
	_length = float(_shot["seconds"])
	caption = str(_shot["title"])
	caption_sub = str(_shot["sub"])
	_min_y = _clearance(_shot)
	for i in _worlds.size():
		_worlds[i].visible = i == _active
	_sky.time_of_day = float(_shot["hour"])
	_phase = Phase.PLAYING
	_place_camera(0.0)
	if first:
		first_frame_ms = Time.get_ticks_msec() - _created_ms
		if OS.is_debug_build() and "--load-timing" in OS.get_cmdline_user_args():
			print("[menu] first shot after %d ms" % first_frame_ms)
	# Prepare the following shot off screen.
	_next_shot = _next_shot_index(index)
	if _shots.size() > 1:
		if _worlds.size() < 2:
			_worlds.append(_make_world("MenuWorldB", _radius))
		var other := _worlds[1 - _active]
		other.view_radius = _radius
		other.focus = _focus_of(_shots[_next_shot])
		other.visible = false
	# The world on screen may grow now that the first image is up.
	_worlds[_active].view_radius = _radius


## Development (captures): jump to shot `index` once its area has loaded.
func debug_jump(index: int) -> void:
	if _shots.is_empty() or _worlds.is_empty():
		return
	_forced = index % _shots.size()
	_worlds[_active].focus = _focus_of(_shots[_forced])
	_load_started_ms = Time.get_ticks_msec()
	_fade = 0.0
	_phase = Phase.LOADING


## Development (captures): move the current shot to parameter u.
func debug_seek(u: float) -> void:
	if _phase == Phase.PLAYING:
		_t = u * float(_shot["seconds"])
		_length = float(_shot["seconds"])


## Development: one line about the shot and streaming state.
func debug_state() -> String:
	var parts := PackedStringArray(["t %.1f/%.1f fade %.2f" % [_t, _length, _fade]])
	for w in _worlds:
		parts.append("%s%s: %s" % [w.name, "*" if w.visible else "", w.debug_stats()])
	return "  |  ".join(parts)


func is_playing() -> bool:
	return _phase == Phase.PLAYING


func _play(delta: float) -> void:
	_t += delta
	reveal = minf(1.0, reveal + delta / FIRST_FADE_IN)
	var fade_in := FIRST_FADE_IN if _shots_shown == 1 else FADE_IN
	var next_ready := _shots.size() > 1 and _next_ready()
	# Hold the shot (the camera keeps drifting) until the next one has streamed in.
	if _t > _length - FADE_OUT and not next_ready and _t < _length * 1.35:
		_length = _t + FADE_OUT
	_fade = smoothstep(0.0, fade_in, _t) * (1.0 - smoothstep(_length - FADE_OUT, _length, _t)) if _shots.size() > 1 \
			else smoothstep(0.0, fade_in, _t)
	_place_camera(_t / float(_shot["seconds"]))
	_sky.time_of_day = float(_shot["hour"]) + _t / 120.0
	if _shots.size() > 1 and _t >= _length:
		_active = 1 - _active
		_begin_shot(_next_shot, false)


func _next_ready() -> bool:
	if _worlds.size() < 2:
		return false
	var w := _worlds[1 - _active]
	return w.loading_progress() >= 0.85 and w.is_area_loaded(w.focus)


## Atmosphere tuned for a postcard: haze hides the edge of the loaded area.
func _grade() -> void:
	var env := _sky.environment
	var fog_scale := float(Settings.get_value("graphics", "fog"))
	env.fog_density = 0.0042 * maxf(0.35, fog_scale)
	env.fog_sky_affect = 0.5
	# Golden haze instead of the game's neutral daytime fog.
	env.fog_light_color = env.fog_light_color.lerp(Color(0.66, 0.46, 0.3), 0.6)


func _on_setting(section: String, _key: String) -> void:
	if section == "graphics":
		_light_profile.call_deferred()


## The backdrop is scenery, not gameplay: it skips the most expensive effects
## of the High/Ultra presets (GI, screen-space reflections and indirect light,
## volumetric fog) and renders the 3D view at a modest resolution when glyphs
## cover it anyway. Re-applied after every graphics setting change, because
## SkyController re-applies the preset then.
func _light_profile() -> void:
	if _sky == null or _view == null:
		return
	var env := _sky.environment
	env.sdfgi_enabled = false
	env.ssil_enabled = false
	env.ssr_enabled = false
	env.volumetric_fog_enabled = false
	_sky.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sky.sun.directional_shadow_max_distance = 120.0
	_apply_render_scale()


func _apply_render_scale() -> void:
	pass  # WorldView applies the quality's render resolution and upscaler itself.


# --- Camera ---------------------------------------------------------------------------

## [camera position, look target] at shot parameter u (0..1, may run past 1).
func _pose(shot: Dictionary, u: float) -> Array:
	var c: Vector3 = shot["center"]
	if shot["kind"] == "orbit":
		var a := lerpf(float(shot["a0"]), float(shot["a1"]), u)
		var r := float(shot["radius"])
		return [c + Vector3(cos(a) * r, float(shot["height"]), sin(a) * r), c + (shot["look"] as Vector3)]
	var from: Vector3 = shot["from"]
	var to: Vector3 = shot["to"]
	var l0: Vector3 = shot["look0"]
	var l1: Vector3 = shot["look1"]
	return [c + from + (to - from) * u, c + l0 + (l1 - l0) * u]


const CLEAR_SAMPLES := 48
const CLEAR_SPAN := 1.5


## Minimum camera height along the shot path, smoothed so the camera glides
## over hills instead of following every bump.
func _clearance(shot: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(CLEAR_SAMPLES + 1)
	var clear := float(shot.get("clear", 8.0))
	for i in CLEAR_SAMPLES + 1:
		var p: Vector3 = _pose(shot, CLEAR_SPAN * i / CLEAR_SAMPLES)[0]
		var top := float(WorldGen.SEA_LEVEL)
		for o: Vector2 in [Vector2.ZERO, Vector2(6, 0), Vector2(-6, 0), Vector2(0, 6), Vector2(0, -6)]:
			top = maxf(top, float(_gen.surface_height(int(p.x + o.x), int(p.z + o.y))))
		out[i] = top + clear
	# Spread peaks to their neighbours (look-ahead), then soften.
	for pass_i in 3:
		var copy := out.duplicate()
		for i in out.size():
			var m := copy[i]
			for d in [-2, -1, 1, 2]:
				var j := clampi(i + d, 0, out.size() - 1)
				m = maxf(m, copy[j] - 1.5 * absf(float(d)))
			out[i] = m
	return out


func _min_height(u: float) -> float:
	if _min_y.is_empty():
		return -INF
	var f := clampf(u / CLEAR_SPAN, 0.0, 1.0) * CLEAR_SAMPLES
	var i := mini(int(f), CLEAR_SAMPLES - 1)
	return lerpf(_min_y[i], _min_y[i + 1], f - i)


func _place_camera(u: float) -> void:
	var pose := _pose(_shot, u)
	var pos: Vector3 = pose[0]
	var target: Vector3 = pose[1]
	pos.y = maxf(pos.y, _min_height(u))
	# A breath of hand-held drift.
	var tt := _t
	pos += Vector3(sin(tt * 0.31) * 0.25, sin(tt * 0.23 + 1.0) * 0.18, cos(tt * 0.27) * 0.25)
	_cam.global_position = pos
	if pos.distance_to(target) > 0.5:
		_cam.look_at(target, Vector3.UP)


## Waits for a worker task the backdrop no longer needs, then frees itself.
class _TaskReaper extends Node:
	var task := -1

	func _process(_delta: float) -> void:
		if task < 0 or WorkerThreadPool.is_task_completed(task):
			if task >= 0:
				WorkerThreadPool.wait_for_task_completion(task)
			task = -1
			queue_free()
