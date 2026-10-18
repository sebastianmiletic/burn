extends Node
## Autoload "Audio": sound effects, ambience beds and adaptive music.
##
## Sound is built at startup from CC0 recordings (audio/samples/) layered with
## procedural synthesis (audio/synth.gd); see SfxLibrary / AmbienceLibrary.
##
## Startup: the menu sounds are rendered synchronously (a few ms); every other
## effect and the ambience beds render on worker threads (most needed first)
## and become playable as they finish. Renders are cached as raw PCM under
## user://audio_cache/<source hash>/, so later launches only read files.
## Music stems render (or load from the cache) when a state is first requested.
## Requests for a sound that is not ready yet, or unknown, are skipped silently.
##
## Mixing: SFX and ambience go through their own buses. Positional sounds use
## inverse-distance falloff with a per-category range and the engine's
## distance low-pass (air absorption); other characters' footsteps are quieter.
## Underground (set_muffle) the SFX bus gets a large, wet cave reverb and the
## ambience is low-passed; the "underwater" bed also muffles everything.

const MUSIC_FADE := 3.0
const AMBIENCE_FADE := 2.0
const POOL_2D := 24
const POOL_3D := 40
const MUFFLE_MIN_HZ := 650.0
const UNDERWATER_HZ := 450.0
## Bump when recordings change (the source hash covers the scripts).
const CACHE_VERSION := "3"
var CACHE_ROOT := RuntimePaths.file("audio_cache")

## Mix gain of each ambience bed at level 1 (dB; beds are rendered at equal RMS).
## (Wind, rain, cave, lava, fire and village match the loudness of the beds
## they replaced at the same set_ambience levels.)
const BED_DB := {"wind": 1.0, "wind_strong": 0.0, "rain": 3.0, "rain_heavy": 0.0, "fire": 0.0, "cave": 0.0,
	"lava": 0.0, "village": -2.0, "birds": -6.0, "insects": -12.0, "crickets": -8.0, "leaves": -8.0,
	"ocean": 0.0, "waterfall": 0.0, "stream": -3.0, "underwater": 0.0, "furnace": -3.0}

var _streams := {}          # sound -> Array[AudioStreamWAV]
var _ambience_streams := {} # bed -> AudioStreamWAV
var _music_streams := {}    # state -> AudioStreamWAV
var _music_rendering := {}  # state -> task id
var _lock := Mutex.new()
var _finished: Array = []   # [kind, name, bytes, extra] produced by workers

var _sfx_jobs: Array = []   # [name, variant]
var _sfx_groups: Array[int] = []
var _ambience_group := -1
var _stats := {}
var _started_usec := 0
var _sfx_done := 0
var _cache_dir := ""
var _cache_hits := 0
var _cache_lock := Mutex.new()
var _launched := false
var _cancel := false        # set on exit: queued jobs return at once

var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_3d_host: Node = null
var _voices := {}           # sound -> Array of players currently playing it
var _last_variant := {}     # sound -> index of the variant played last

var _music_players: Array[AudioStreamPlayer] = []
var _music_gain := PackedFloat32Array([0.0, 0.0])
var _music_target := PackedFloat32Array([0.0, 0.0])
var _music_slot := 0
var _music_state := "silence"
var _music_slot_state := ["", ""]

var _ambience_players := {} # bed -> AudioStreamPlayer
var _ambience_gain := {}
var _ambience_target := {}
var _levels := {}           # public key -> effective level
var _base_levels := {}      # last set_ambience() call
var _sources := {}          # set_ambience_source() name -> levels

var _muffle := 0.0
var _muffle_target := 0.0
var _underwater := 0.0

# Gusts: a slow random walk that breathes life into wind and leaves.
var _gust := 0.85
var _gust_target := 0.85
var _gust_timer := 0.0

# Ambient one-shots (birds, owls, cave drips) placed around the listener.
var _event_timers := {"amb_bird": 2.0, "amb_owl": 20.0, "amb_drip": 3.0}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_started_usec = Time.get_ticks_usec()
	_setup_buses()
	_apply_volumes()
	_apply_device()
	var settings := _settings()
	if settings != null:
		settings.connect(&"changed", _on_setting)

	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_pool_2d.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = &"Music"
		m.volume_db = -80.0
		add_child(m)
		_music_players.append(m)
	for bed: String in AmbienceLibrary.BEDS:
		var a := AudioStreamPlayer.new()
		a.bus = &"Ambient"
		a.volume_db = -80.0
		add_child(a)
		_ambience_players[bed] = a
		_ambience_gain[bed] = 0.0
		_ambience_target[bed] = 0.0

	# Offline tools (tests/audio/render_sounds.gd) render on their own.
	if Engine.has_meta(&"audio_offline"):
		return
	_cache_dir = _make_cache_dir()

	# Menu sounds right away from the cache (a file read each); on a cold
	# start they are the first background jobs instead, so the main thread
	# never synthesises.
	var t := Time.get_ticks_usec()
	for sound: String in SfxLibrary.UI_SOUNDS:
		for v in SfxLibrary.variants(sound):
			var bytes := _cache_read("sfx_%s_%d" % [sound, v])
			if bytes.is_empty():
				_sfx_jobs.append([sound, v])
			else:
				if not _streams.has(sound):
					_streams[sound] = []
				(_streams[sound] as Array).append(Synth.to_wav(bytes, false))
	_stats["ui_ms"] = (Time.get_ticks_usec() - t) / 1000.0

	# Everything else in the background, one job per variant: every variant of
	# what the first seconds of play need, then one variant of every other
	# sound (so all become playable quickly), all at high priority (short
	# jobs); then the extra variants and the ambience beds at low priority so
	# world generation is not starved.
	for sound: String in SfxLibrary.PRIORITY:
		for v in SfxLibrary.variants(sound):
			_sfx_jobs.append([sound, v])
	var later: Array = []
	for sound: String in SfxLibrary.names():
		if sound in SfxLibrary.UI_SOUNDS or sound in SfxLibrary.PRIORITY:
			continue
		_sfx_jobs.append([sound, 0])
		for v in range(1, SfxLibrary.variants(sound)):
			later.append([sound, v])
	var urgent := _sfx_jobs.size()
	_sfx_jobs.append_array(later)
	_sfx_groups.append(WorkerThreadPool.add_group_task(_job_sfx.bind(0), urgent, -1, true, "audio sfx urgent"))
	if _sfx_jobs.size() > urgent:
		_sfx_groups.append(WorkerThreadPool.add_group_task(_job_sfx.bind(urgent), _sfx_jobs.size() - urgent, -1, false, "audio sfx"))
	_ambience_group = WorkerThreadPool.add_group_task(_job_ambience, AmbienceLibrary.ORDER.size(), -1, false, "audio ambience")
	_launched = true
	_stats["ready_ms"] = (Time.get_ticks_usec() - _started_usec) / 1000.0


func _exit_tree() -> void:
	# Worker tasks must be waited on before the engine shuts down; jobs that
	# have not started yet skip their work, so quitting during a first-run
	# render only waits for the few in flight.
	_cancel = true
	for g in _sfx_groups:
		if g >= 0:
			WorkerThreadPool.wait_for_group_task_completion(g)
	_sfx_groups.clear()
	if _ambience_group >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_ambience_group)
		_ambience_group = -1
	for state: String in _music_rendering:
		WorkerThreadPool.wait_for_task_completion(_music_rendering[state])
	_music_rendering.clear()
	stop_all()


## Silences everything immediately (quitting, returning to a black screen).
## Call a frame before quitting so the audio thread can release playbacks.
func stop_all() -> void:
	_music_target[0] = 0.0
	_music_target[1] = 0.0
	_music_state = "silence"
	for bed: String in _ambience_target:
		_ambience_target[bed] = 0.0
	_levels.clear()
	_base_levels.clear()
	_sources.clear()
	var players: Array[Node] = []
	players.append_array(_pool_2d)
	players.append_array(_music_players)
	players.append_array(_ambience_players.values())
	for p in _pool_3d:
		if is_instance_valid(p):
			players.append(p)
	for p in players:
		p.call("stop")
		p.set("stream", null)


# --- Public API (see docs/ARCHITECTURE.md) -------------------------------------------

func play(sound: String, at := Vector3.INF, volume_db := 0.0, pitch := 1.0) -> void:
	var stream := _pick(sound)
	if stream == null:
		return
	var cat := SfxLibrary.category(sound)
	var jit: Vector2 = SfxLibrary.JITTER.get(cat, Vector2(0.05, 1.5))
	var db := volume_db + float(SfxLibrary.TRIM.get(sound, 0.0)) + randf_range(-jit.y, jit.y * 0.5)
	var p := pitch * (1.0 + randf_range(-jit.x, jit.x))
	if at.is_finite():
		var host := _world_host()
		if host != null:
			var p3 := _take_3d(sound, host)
			if p3 != null:
				var range_v: Vector2 = SfxLibrary.RANGE.get(cat, Vector2(6.0, 80.0))
				if cat == "step":
					# Someone else's feet: quieter and shorter-reaching than our own.
					var lp := _listener_pos()
					if lp.is_finite() and lp.distance_to(at) > 7.0:
						db -= 4.0
						range_v.x *= 0.8
				_setup_3d(p3, range_v, &"SFX")
				p3.stream = stream
				p3.volume_db = db
				p3.pitch_scale = p
				p3.global_position = at
				p3.play()
				_track(sound, p3)
				return
	var p2 := _take_2d(sound, &"SFX")
	p2.stream = stream
	p2.volume_db = db
	p2.pitch_scale = p
	p2.play()
	_track(sound, p2)


func play_ui(sound: String) -> void:
	var stream := _pick(sound)
	if stream == null:
		return
	var p2 := _take_2d(sound, &"UI")
	p2.stream = stream
	p2.volume_db = float(SfxLibrary.TRIM.get(sound, 0.0)) + randf_range(-0.8, 0.4)
	p2.pitch_scale = randf_range(0.98, 1.02)
	p2.play()
	_track(sound, p2)


## "menu", "explore", "night", "cave", "boss", "hell", "victory", "silence".
func set_music(state: String) -> void:
	if state == _music_state:
		return
	_music_state = state
	if state == "silence" or not state in MusicLibrary.STATES:
		_music_target[0] = 0.0
		_music_target[1] = 0.0
		return
	_ensure_music(state)
	if state == "menu":
		_ensure_music("explore")  # the likely next request
	_start_music_if_ready()


func current_music() -> String:
	return _music_state


## Keys (each 0..1): wind, rain, fire, cave, lava, village, birds, insects,
## crickets, leaves, ocean, waterfall, stream, underwater, furnace.
## Missing keys fade out; unknown keys are ignored.
func set_ambience(levels: Dictionary) -> void:
	_base_levels = levels.duplicate()
	_update_levels()


## Additional ambience from another system (a lit furnace, nearby water, being
## underwater...), keyed by `source` so callers do not overwrite each other or
## the main set_ambience call. Each key ends up at the max over all sources.
## Pass an empty dictionary to remove the source.
func set_ambience_source(source: String, levels: Dictionary) -> void:
	if levels.is_empty():
		_sources.erase(source)
	else:
		_sources[source] = levels.duplicate()
	_update_levels()


func _update_levels() -> void:
	_levels.clear()
	for key: String in AmbienceLibrary.PUBLIC:
		var v := float(_base_levels.get(key, 0.0))
		for src: Dictionary in _sources.values():
			v = maxf(v, float(src.get(key, 0.0)))
		_levels[key] = clampf(v, 0.0, 1.0)
	var wind: float = _levels["wind"]
	var rain: float = _levels["rain"]
	var heavy := smoothstep(0.3, 1.0, rain)
	for bed: String in _ambience_target:
		_ambience_target[bed] = float(_levels.get(bed, 0.0))
	_ambience_target["rain"] = minf(1.0, rain * 2.5) * (1.0 - 0.6 * heavy)
	_ambience_target["rain_heavy"] = heavy
	_ambience_target["wind_strong"] = smoothstep(0.45, 1.0, wind)


## 0 = open air, 1 = deep underground / indoors: cave reverb on effects,
## low-passed ambience.
func set_muffle(amount: float) -> void:
	_muffle_target = clampf(amount, 0.0, 1.0)


func is_ready(sound: String) -> bool:
	return _streams.has(sound)


## Generation timings and readiness, for diagnostics and tests.
func stats() -> Dictionary:
	var s := _stats.duplicate()
	s["sfx_ready"] = _streams.size()
	s["sfx_total"] = SfxLibrary.SOUNDS.size()
	var variants := 0
	for list: Array in _streams.values():
		variants += list.size()
	s["sfx_variants_done"] = variants
	s["ambience_ready"] = _ambience_streams.size()
	s["ambience_total"] = AmbienceLibrary.BEDS.size()
	s["music_ready"] = _music_streams.keys()
	s["cache_hits"] = _cache_hits
	s["cache_dir"] = _cache_dir
	return s


# --- Cache ------------------------------------------------------------------------------

## user://audio_cache/<hash of the generator sources + version>/. Stale
## siblings are removed in the background.
func _make_cache_dir() -> String:
	var h := CACHE_VERSION + ":" + str(Synth.SR)
	for f: String in ["synth.gd", "sample_bank.gd", "sfx_kit.gd", "sfx_library.gd", "sfx_nature.gd",
			"sfx_creatures.gd", "ambience_library.gd", "music_library.gd"]:
		var path := "res://audio/" + f
		if FileAccess.file_exists(path):
			h += ":" + str(FileAccess.get_file_as_string(path).hash())
	var key := "%08x" % (h.hash() & 0xffffffff)
	var dir := CACHE_ROOT.path_join(key)
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return ""
	var stale: Array[String] = []
	var root := DirAccess.open(CACHE_ROOT)
	if root != null:
		for d in root.get_directories():
			if d != key:
				stale.append(CACHE_ROOT.path_join(d))
	if not stale.is_empty():
		WorkerThreadPool.add_task(_remove_dirs.bind(stale), false, "audio cache cleanup")
	return dir


static func _remove_dirs(dirs: Array[String]) -> void:
	for d in dirs:
		var da := DirAccess.open(d)
		if da == null:
			continue
		for f in da.get_files():
			da.remove(f)
		DirAccess.remove_absolute(d)


func _cache_read(key: String) -> PackedByteArray:
	if _cache_dir == "":
		return PackedByteArray()
	var path := _cache_dir.path_join(key + ".pcm")
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var bytes := FileAccess.get_file_as_bytes(path)
	if not bytes.is_empty():
		_cache_lock.lock()
		_cache_hits += 1
		_cache_lock.unlock()
	return bytes


func _cache_write(key: String, bytes: PackedByteArray) -> void:
	if _cache_dir == "" or bytes.is_empty():
		return
	# Write then rename, so a reader never sees a half-written file.
	var path := _cache_dir.path_join(key + ".pcm")
	var tmp := path + ".%d.tmp" % (randi() % 1000000)
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(bytes)
	f.close()
	DirAccess.rename_absolute(tmp, path)


# --- Workers --------------------------------------------------------------------------

func _job_sfx(i: int, base: int) -> void:
	if _cancel:
		return
	var job: Array = _sfx_jobs[base + i]
	var key := "sfx_%s_%d" % [job[0], job[1]]
	var bytes := _cache_read(key)
	if bytes.is_empty():
		bytes = Synth.to_bytes(SfxLibrary.build(job[0], job[1]))
		_cache_write(key, bytes)
	_lock.lock()
	_finished.append(["sfx", job[0], bytes, job[1]])
	_lock.unlock()


func _job_ambience(i: int) -> void:
	if _cancel:
		return
	var bed: String = AmbienceLibrary.ORDER[i]
	var t := Time.get_ticks_usec()
	var key := "amb_" + bed
	var bytes := _cache_read(key)
	if bytes.is_empty():
		bytes = _interleave(AmbienceLibrary.build_channels(bed))
		_cache_write(key, bytes)
	_lock.lock()
	_finished.append(["ambience", bed, bytes, (Time.get_ticks_usec() - t) / 1000.0])
	_lock.unlock()


func _job_music(state: String) -> void:
	if _cancel:
		return
	var t := Time.get_ticks_usec()
	var key := "music_" + state
	var bytes := _cache_read(key)
	if bytes.is_empty():
		bytes = Synth.to_bytes(MusicLibrary.build(state))
		_cache_write(key, bytes)
	_lock.lock()
	_finished.append(["music", state, bytes, (Time.get_ticks_usec() - t) / 1000.0])
	_lock.unlock()


## 16-bit PCM, interleaved when there are two channels.
static func _interleave(chans: Array) -> PackedByteArray:
	if chans.size() == 1:
		return Synth.to_bytes(chans[0])
	var l: PackedFloat32Array = chans[0]
	var r: PackedFloat32Array = chans[1]
	var bytes := PackedByteArray()
	bytes.resize(l.size() * 4)
	for i in l.size():
		bytes.encode_s16(i * 4, int(clampf(l[i], -1.0, 1.0) * 32767.0))
		bytes.encode_s16(i * 4 + 2, int(clampf(r[i], -1.0, 1.0) * 32767.0))
	return bytes


func _ensure_music(state: String) -> void:
	if _music_streams.has(state) or _music_rendering.has(state):
		return
	# The requested state renders at high priority; prefetches at low priority.
	var urgent := state == _music_state
	_music_rendering[state] = WorkerThreadPool.add_task(_job_music.bind(state), urgent, "audio music %s" % state)


func _collect_finished() -> void:
	_lock.lock()
	var done := _finished
	_finished = []
	_lock.unlock()
	for item: Array in done:
		var kind: String = item[0]
		var item_name: String = item[1]
		var bytes: PackedByteArray = item[2]
		match kind:
			"sfx":
				if not _streams.has(item_name):
					_streams[item_name] = []
				(_streams[item_name] as Array).append(Synth.to_wav(bytes, false))
				_sfx_done += 1
				if _sfx_done == _sfx_jobs.size():
					_stats["sfx_ms"] = (Time.get_ticks_usec() - _started_usec) / 1000.0
			"ambience":
				var w := Synth.to_wav(bytes, true)
				if AmbienceLibrary.channels_of(item_name) == 2:
					w.stereo = true
					w.loop_end = bytes.size() / 4
				_ambience_streams[item_name] = w
				_stats["ambience_%s_ms" % item_name] = item[3]
				if _ambience_streams.size() == AmbienceLibrary.BEDS.size():
					_stats["ambience_ms"] = (Time.get_ticks_usec() - _started_usec) / 1000.0
			"music":
				_music_streams[item_name] = Synth.to_wav(bytes, true)
				_stats["music_%s_ms" % item_name] = item[3]
				WorkerThreadPool.wait_for_task_completion(_music_rendering[item_name])
				_music_rendering.erase(item_name)
				_start_music_if_ready()
	for k in _sfx_groups.size():
		var g := _sfx_groups[k]
		if g >= 0 and WorkerThreadPool.is_group_task_completed(g):
			WorkerThreadPool.wait_for_group_task_completion(g)
			_sfx_groups[k] = -1
	if _ambience_group >= 0 and WorkerThreadPool.is_group_task_completed(_ambience_group):
		WorkerThreadPool.wait_for_group_task_completion(_ambience_group)
		_ambience_group = -1
	if _ambience_group < 0 and _sfx_groups.all(func(g: int) -> bool: return g < 0) and not _stats.has("done_ms") \
			and _finished.is_empty():
		_stats["done_ms"] = (Time.get_ticks_usec() - _started_usec) / 1000.0
		SampleBank.clear()  # decoded recordings are no longer needed


# --- Mixing ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _finished.is_empty() or (_launched and not _stats.has("done_ms")):
		_collect_finished()

	# Music crossfade.
	for i in 2:
		var g := move_toward(_music_gain[i], _music_target[i], delta / MUSIC_FADE)
		_music_gain[i] = g
		var player := _music_players[i]
		player.volume_db = linear_to_db(maxf(g, 0.0001))
		if g <= 0.0 and player.playing and _music_target[i] <= 0.0:
			player.stop()

	_update_gust(delta)

	# Ambience beds.
	for bed: String in _ambience_players:
		var player: AudioStreamPlayer = _ambience_players[bed]
		var target: float = _ambience_target[bed]
		if target > 0.0 and not player.playing:
			var stream: AudioStreamWAV = _ambience_streams.get(bed)
			if stream == null:
				continue
			player.stream = stream
			player.play(randf() * stream.get_length())
		var g := move_toward(float(_ambience_gain[bed]), target, delta / AMBIENCE_FADE)
		_ambience_gain[bed] = g
		var lin := g * db_to_linear(float(BED_DB.get(bed, -8.0)))
		if bed in ["wind", "wind_strong"]:
			lin *= _gust
			player.pitch_scale = 0.94 + 0.12 * clampf((_gust - 0.5) / 0.7, 0.0, 1.0)
		elif bed == "leaves":
			# Leaves answer the wind: louder in gusts and when it blows harder.
			lin *= (0.3 + 0.7 * _gust) * (0.5 + float(_levels.get("wind", 0.4)))
		player.volume_db = linear_to_db(maxf(lin, 0.00001))
		if g <= 0.0 and player.playing:
			player.stop()

	_ambient_events(delta)

	var uw_target := float(_ambience_target.get("underwater", 0.0))
	if not is_equal_approx(_muffle, _muffle_target) or not is_equal_approx(_underwater, uw_target):
		_muffle = move_toward(_muffle, _muffle_target, delta * 1.5)
		_underwater = move_toward(_underwater, uw_target, delta * 4.0)
		_apply_muffle()


func _update_gust(delta: float) -> void:
	_gust_timer -= delta
	if _gust_timer <= 0.0:
		var w := float(_levels.get("wind", 0.35))
		# Stronger wind gusts harder.
		var spread := 0.25 + 0.35 * w
		_gust_target = clampf(randf_range(1.0 - spread, 1.0 + spread * 0.6), 0.4, 1.35)
		_gust_timer = randf_range(1.5, 5.0)
	_gust = move_toward(_gust, _gust_target, delta * 0.25)


## Birds by day, an owl at night, drips in caves: individual calls placed
## around the listener so the beds never sound like a loop.
func _ambient_events(delta: float) -> void:
	var birds := float(_ambience_gain.get("birds", 0.0))
	var crickets := float(_ambience_gain.get("crickets", 0.0))
	var cave := float(_ambience_gain.get("cave", 0.0))
	var rates := {"amb_bird": birds * (1.0 - 0.7 * float(_ambience_gain.get("rain_heavy", 0.0))),
		"amb_owl": crickets, "amb_drip": cave}
	for sound: String in rates:
		var rate: float = rates[sound]
		if rate < 0.05:
			continue
		_event_timers[sound] = float(_event_timers[sound]) - delta * rate
		if _event_timers[sound] > 0.0:
			continue
		match sound:
			"amb_bird":
				_event_timers[sound] = randf_range(1.2, 6.0)
				_play_around(sound, 10.0, 40.0, 3.0, 12.0, -4.0 + linear_to_db(rate))
			"amb_owl":
				_event_timers[sound] = randf_range(25.0, 70.0)
				_play_around(sound, 25.0, 60.0, 5.0, 14.0, -6.0)
			"amb_drip":
				_event_timers[sound] = randf_range(1.0, 4.5)
				_play_around(sound, 3.0, 16.0, 1.5, 6.0, -6.0 + linear_to_db(rate))


func _play_around(sound: String, d_min: float, d_max: float, h_min: float, h_max: float, db: float) -> void:
	var stream := _pick(sound)
	if stream == null:
		return
	var lp := _listener_pos()
	var host := _world_host()
	db += float(SfxLibrary.TRIM.get(sound, 0.0)) + randf_range(-3.0, 1.0)
	if lp.is_finite() and host != null:
		var p3 := _take_3d(sound, host)
		if p3 == null:
			return
		var a := randf() * TAU
		var d := randf_range(d_min, d_max)
		_setup_3d(p3, SfxLibrary.RANGE["amb"], &"Ambient")
		p3.stream = stream
		p3.volume_db = db
		p3.pitch_scale = randf_range(0.93, 1.07)
		p3.global_position = lp + Vector3(cos(a) * d, randf_range(h_min, h_max), sin(a) * d)
		p3.play()
		_track(sound, p3)
		return
	var p2 := _take_2d(sound, &"Ambient")
	p2.stream = stream
	p2.volume_db = db - 8.0
	p2.pitch_scale = randf_range(0.93, 1.07)
	p2.play()
	_track(sound, p2)


func _start_music_if_ready() -> void:
	var state := _music_state
	if state == "silence" or not _music_streams.has(state):
		return
	if _music_slot_state[_music_slot] == state and _music_target[_music_slot] > 0.0:
		return
	var next := 1 - _music_slot
	var player := _music_players[next]
	player.stream = _music_streams[state]
	player.play()
	_music_slot_state[next] = state
	_music_target[next] = 1.0
	_music_target[_music_slot] = 0.0
	_music_slot = next


## A random variant, never the one played last time (no machine-gun repeats).
func _pick(sound: String) -> AudioStreamWAV:
	var list: Variant = _streams.get(sound)
	if list == null or (list as Array).is_empty():
		return null
	var arr: Array = list
	var i := randi() % arr.size()
	if arr.size() > 1 and i == int(_last_variant.get(sound, -1)):
		i = (i + 1 + randi() % (arr.size() - 1)) % arr.size()
	_last_variant[sound] = i
	return arr[i]


func _track(sound: String, player: Node) -> void:
	if not _voices.has(sound):
		_voices[sound] = []
	(_voices[sound] as Array).append(player)


## Voice limiting: if this sound already has its maximum voices playing, the
## oldest one is cut and reused.
func _steal_voice(sound: String) -> Node:
	var active: Array = _voices.get(sound, [])
	var still: Array = []
	# A previous world may have freed its positional players. Do not cast a
	# stale object to Node before checking validity (new-game/continue flow).
	for p in active:
		if is_instance_valid(p) and p.get("playing"):
			still.append(p)
	_voices[sound] = still
	var limit := int(SfxLibrary.MAX_VOICES.get(sound, 5))
	if still.size() >= limit:
		var oldest: Node = still.pop_front()
		oldest.call("stop")
		return oldest
	return null


func _take_2d(sound: String, bus: StringName) -> AudioStreamPlayer:
	var stolen := _steal_voice(sound)
	if stolen is AudioStreamPlayer:
		(stolen as AudioStreamPlayer).bus = bus
		return stolen
	for p in _pool_2d:
		if not p.playing:
			p.bus = bus
			return p
	# Pool exhausted: grow a little rather than drop the sound.
	var extra := AudioStreamPlayer.new()
	extra.bus = bus
	add_child(extra)
	_pool_2d.append(extra)
	return extra


func _take_3d(sound: String, host: Node) -> AudioStreamPlayer3D:
	if host != _pool_3d_host:
		_pool_3d.clear()
		_pool_3d_host = host
	var stolen := _steal_voice(sound)
	if stolen is AudioStreamPlayer3D and is_instance_valid(stolen) and stolen.get_parent() == host:
		return stolen
	for p in _pool_3d:
		if is_instance_valid(p) and not p.playing:
			return p
	if _pool_3d.size() >= POOL_3D * 2:
		return null
	var p3 := AudioStreamPlayer3D.new()
	p3.bus = &"SFX"
	p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p3.panning_strength = 0.9
	# Air absorption: high frequencies fade with distance.
	p3.attenuation_filter_cutoff_hz = 4500.0
	p3.attenuation_filter_db = -18.0
	host.add_child(p3)
	_pool_3d.append(p3)
	return p3


static func _setup_3d(p3: AudioStreamPlayer3D, range_v: Vector2, bus: StringName) -> void:
	p3.unit_size = range_v.x
	p3.max_distance = range_v.y
	p3.bus = bus


func _world_host() -> Node:
	var host := get_tree().root.get_node_or_null("GameWorld")
	if host == null or not host.is_inside_tree() or not host is Node3D:
		return null
	return host


func _listener_pos() -> Vector3:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null or not cam.is_inside_tree():
		return Vector3.INF
	return cam.global_position


# --- Buses ---------------------------------------------------------------------------------

func _setup_buses() -> void:
	for bus_name: String in ["Music", "SFX", "Ambient", "UI"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, &"Master")
	# SFX: [0] room reverb (open air: a short, faint slap; underground: a big
	# wet cave), [1] low-pass (muffle / underwater), [2] glue compressor.
	var sfx := AudioServer.get_bus_index(&"SFX")
	if AudioServer.get_bus_effect_count(sfx) == 0:
		var reverb := AudioEffectReverb.new()
		reverb.predelay_msec = 12.0
		reverb.predelay_feedback = 0.2
		reverb.room_size = 0.3
		reverb.damping = 0.55
		reverb.spread = 0.8
		reverb.hipass = 0.15
		reverb.wet = 0.05
		reverb.dry = 1.0
		AudioServer.add_bus_effect(sfx, reverb)
		var lowpass := AudioEffectLowPassFilter.new()
		lowpass.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(sfx, lowpass)
		AudioServer.set_bus_effect_enabled(sfx, 1, false)
		var comp := AudioEffectCompressor.new()
		comp.threshold = -14.0
		comp.ratio = 2.5
		comp.attack_us = 2000.0
		comp.release_ms = 180.0
		comp.gain = 1.0
		AudioServer.add_bus_effect(sfx, comp)
	# Ambient: [0] low-pass.
	var amb := AudioServer.get_bus_index(&"Ambient")
	if AudioServer.get_bus_effect_count(amb) == 0:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(amb, lp)
		AudioServer.set_bus_effect_enabled(amb, 0, false)
	var master := AudioServer.get_bus_index(&"Master")
	if AudioServer.get_bus_effect_count(master) == 0:
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -0.5
		AudioServer.add_bus_effect(master, limiter)


func _apply_muffle() -> void:
	var m := _muffle
	var uw := _underwater
	var sfx := AudioServer.get_bus_index(&"SFX")
	if sfx >= 0 and AudioServer.get_bus_effect_count(sfx) >= 2:
		var rv := AudioServer.get_bus_effect(sfx, 0) as AudioEffectReverb
		if rv != null:
			rv.room_size = lerpf(0.3, 0.86, m)
			rv.damping = lerpf(0.55, 0.3, m)
			rv.wet = lerpf(0.05, 0.3, m)
			rv.predelay_msec = lerpf(12.0, 45.0, m)
			rv.predelay_feedback = lerpf(0.2, 0.4, m)
		# Effects are barely dulled by rock (a little absorption), heavily by water.
		var cut := minf(20000.0 * pow(9000.0 / 20000.0, m), 20000.0 * pow(UNDERWATER_HZ / 20000.0, uw))
		var lp := AudioServer.get_bus_effect(sfx, 1) as AudioEffectLowPassFilter
		if lp != null:
			lp.cutoff_hz = cut
			AudioServer.set_bus_effect_enabled(sfx, 1, cut < 19000.0)
	var amb := AudioServer.get_bus_index(&"Ambient")
	if amb >= 0 and AudioServer.get_bus_effect_count(amb) >= 1:
		var cut_a := minf(20000.0 * pow(MUFFLE_MIN_HZ / 20000.0, m), 20000.0 * pow(UNDERWATER_HZ / 20000.0, uw))
		var lpa := AudioServer.get_bus_effect(amb, 0) as AudioEffectLowPassFilter
		if lpa != null:
			lpa.cutoff_hz = cut_a
			AudioServer.set_bus_effect_enabled(amb, 0, cut_a < 19000.0)


## Looked up by path so this script also compiles where autoloads are absent (tests).
func _settings() -> Node:
	return get_node_or_null("/root/Settings")


func _apply_volumes() -> void:
	var settings := _settings()
	if settings == null:
		return
	var muted := _unfocused and bool(settings.call("get_value", "audio", "mute_unfocused"))
	_set_bus_volume(&"Master", 0.0 if muted else float(settings.call("get_value", "audio", "master")))
	_set_bus_volume(&"Music", float(settings.call("get_value", "audio", "music")))
	_set_bus_volume(&"SFX", float(settings.call("get_value", "audio", "sfx")))
	_set_bus_volume(&"UI", float(settings.call("get_value", "audio", "ui")))
	_set_bus_volume(&"Ambient", float(settings.call("get_value", "audio", "ambient")))


func _set_bus_volume(bus: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))


func _on_setting(section: String, key: String) -> void:
	if section == "audio":
		_apply_volumes()
		if key == "output_device":
			_apply_device()


var _unfocused := false


## Settings > Audio > Mute when unfocused.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_unfocused = what == NOTIFICATION_APPLICATION_FOCUS_OUT
		_apply_volumes()


## Settings > Audio > Output device ("Default" follows the system).
func _apply_device() -> void:
	var settings := _settings()
	if settings == null:
		return
	var want := String(settings.call("get_value", "audio", "output_device"))
	if not want in AudioServer.get_output_device_list():
		want = "Default"
	if AudioServer.output_device != want:
		AudioServer.output_device = want
