extends Node
## Autoload "Audio": procedural sound effects, ambience beds and adaptive
## music. Everything is synthesised at runtime (audio/synth.gd); nothing is
## loaded from disk.
##
## Startup: the menu sounds are rendered synchronously (a few ms); every other
## effect and the ambience beds render on worker threads and become playable
## as they finish. Music stems render lazily when a state is first requested.
## Requests for a sound that is not ready yet are skipped silently.

const MUSIC_FADE := 3.0
const AMBIENCE_FADE := 2.0
const POOL_2D := 24
const POOL_3D := 40
const MUFFLE_MIN_HZ := 650.0

var _streams := {}          # sound -> Array[AudioStreamWAV]
var _ambience_streams := {} # bed -> AudioStreamWAV
var _music_streams := {}    # state -> AudioStreamWAV
var _music_rendering := {}  # state -> task id
var _lock := Mutex.new()
var _finished: Array = []   # [kind, name, bytes] produced by workers

var _sfx_jobs: Array = []   # [name, variant]
var _sfx_group := -1
var _ambience_group := -1
var _stats := {}
var _sfx_started_usec := 0
var _sfx_done := 0

var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_3d_host: Node = null
var _voices := {}           # sound -> Array of players currently playing it

var _music_players: Array[AudioStreamPlayer] = []
var _music_gain := PackedFloat32Array([0.0, 0.0])
var _music_target := PackedFloat32Array([0.0, 0.0])
var _music_slot := 0
var _music_state := "silence"
var _music_slot_state := ["", ""]

var _ambience_players := {} # bed -> AudioStreamPlayer
var _ambience_gain := {}
var _ambience_target := {}

var _muffle := 0.0
var _muffle_target := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_apply_volumes()
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

	# Menu sounds right away.
	var t := Time.get_ticks_usec()
	for sound: String in SfxLibrary.UI_SOUNDS:
		var list: Array[AudioStreamWAV] = []
		for v in SfxLibrary.variants(sound):
			list.append(Synth.to_wav(Synth.to_bytes(SfxLibrary.build(sound, v)), false))
		_streams[sound] = list
	_stats["ui_ms"] = (Time.get_ticks_usec() - t) / 1000.0

	# Everything else in the background, one job per variant.
	for sound: String in SfxLibrary.names():
		if sound in SfxLibrary.UI_SOUNDS:
			continue
		for v in SfxLibrary.variants(sound):
			_sfx_jobs.append([sound, v])
	_sfx_started_usec = Time.get_ticks_usec()
	# High priority: low-priority pool tasks only get a fraction of the cores,
	# and these jobs are short.
	_sfx_group = WorkerThreadPool.add_group_task(_job_sfx, _sfx_jobs.size(), -1, true, "audio sfx")
	_ambience_group = WorkerThreadPool.add_group_task(_job_ambience, AmbienceLibrary.BEDS.size(), -1, true, "audio ambience")


func _exit_tree() -> void:
	# Worker tasks must be waited on before the engine shuts down.
	if _sfx_group >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_sfx_group)
	if _ambience_group >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_ambience_group)
	for state: String in _music_rendering:
		WorkerThreadPool.wait_for_task_completion(_music_rendering[state])
	stop_all()


## Silences everything immediately (quitting, returning to a black screen).
## Call a frame before quitting so the audio thread can release playbacks.
func stop_all() -> void:
	_music_target[0] = 0.0
	_music_target[1] = 0.0
	_music_state = "silence"
	for bed: String in _ambience_target:
		_ambience_target[bed] = 0.0
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
	var db := volume_db + float(SfxLibrary.TRIM.get(sound, 0.0)) + randf_range(-1.5, 1.0)
	var p := pitch * randf_range(0.94, 1.06)
	if at.is_finite():
		var host := _world_host()
		if host != null:
			var p3 := _take_3d(sound, host)
			if p3 != null:
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


## Keys: wind, rain, fire, cave, lava, village — each 0..1. Missing keys fade out.
func set_ambience(levels: Dictionary) -> void:
	for bed: String in _ambience_target:
		_ambience_target[bed] = clampf(float(levels.get(bed, 0.0)), 0.0, 1.0)


## 0 = open air, 1 = deep underground / indoors: low-passes SFX and ambience.
func set_muffle(amount: float) -> void:
	_muffle_target = clampf(amount, 0.0, 1.0)


func is_ready(sound: String) -> bool:
	return _streams.has(sound)


## Generation timings and readiness, for diagnostics and tests.
func stats() -> Dictionary:
	var s := _stats.duplicate()
	s["sfx_ready"] = _streams.size()
	s["sfx_total"] = SfxLibrary.SOUNDS.size()
	s["ambience_ready"] = _ambience_streams.size()
	s["music_ready"] = _music_streams.keys()
	return s


# --- Workers --------------------------------------------------------------------------

func _job_sfx(i: int) -> void:
	var job: Array = _sfx_jobs[i]
	var bytes := Synth.to_bytes(SfxLibrary.build(job[0], job[1]))
	_lock.lock()
	_finished.append(["sfx", job[0], bytes, job[1]])
	_lock.unlock()


func _job_ambience(i: int) -> void:
	var bed: String = AmbienceLibrary.BEDS[i]
	var t := Time.get_ticks_usec()
	var bytes := Synth.to_bytes(AmbienceLibrary.build(bed))
	_lock.lock()
	_finished.append(["ambience", bed, bytes, (Time.get_ticks_usec() - t) / 1000.0])
	_lock.unlock()


func _job_music(state: String) -> void:
	var t := Time.get_ticks_usec()
	var bytes := Synth.to_bytes(MusicLibrary.build(state))
	_lock.lock()
	_finished.append(["music", state, bytes, (Time.get_ticks_usec() - t) / 1000.0])
	_lock.unlock()


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
					_stats["sfx_ms"] = (Time.get_ticks_usec() - _sfx_started_usec) / 1000.0
			"ambience":
				_ambience_streams[item_name] = Synth.to_wav(bytes, true)
				_stats["ambience_%s_ms" % item_name] = item[3]
			"music":
				_music_streams[item_name] = Synth.to_wav(bytes, true)
				_stats["music_%s_ms" % item_name] = item[3]
				WorkerThreadPool.wait_for_task_completion(_music_rendering[item_name])
				_music_rendering.erase(item_name)
				_start_music_if_ready()
	if _sfx_group >= 0 and WorkerThreadPool.is_group_task_completed(_sfx_group):
		WorkerThreadPool.wait_for_group_task_completion(_sfx_group)
		_sfx_group = -1
	if _ambience_group >= 0 and WorkerThreadPool.is_group_task_completed(_ambience_group):
		WorkerThreadPool.wait_for_group_task_completion(_ambience_group)
		_ambience_group = -1


# --- Mixing ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _finished.is_empty():
		_collect_finished()

	# Music crossfade.
	for i in 2:
		var g := move_toward(_music_gain[i], _music_target[i], delta / MUSIC_FADE)
		_music_gain[i] = g
		var player := _music_players[i]
		player.volume_db = linear_to_db(maxf(g, 0.0001))
		if g <= 0.0 and player.playing and _music_target[i] <= 0.0:
			player.stop()

	# Ambience beds.
	for bed: String in _ambience_players:
		var player: AudioStreamPlayer = _ambience_players[bed]
		var target: float = _ambience_target[bed]
		if target > 0.0 and not player.playing:
			var stream: AudioStreamWAV = _ambience_streams.get(bed)
			if stream == null:
				continue
			player.stream = stream
			player.play(randf() * (stream.data.size() / 2.0) / stream.mix_rate)
		var g := move_toward(float(_ambience_gain[bed]), target, delta / AMBIENCE_FADE)
		_ambience_gain[bed] = g
		player.volume_db = linear_to_db(maxf(g, 0.0001))
		if g <= 0.0 and player.playing:
			player.stop()

	if not is_equal_approx(_muffle, _muffle_target):
		_muffle = move_toward(_muffle, _muffle_target, delta * 1.5)
		_apply_muffle()


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


func _pick(sound: String) -> AudioStreamWAV:
	var list: Variant = _streams.get(sound)
	if list == null or (list as Array).is_empty():
		return null
	var arr: Array = list
	return arr[randi() % arr.size()]


func _track(sound: String, player: Node) -> void:
	if not _voices.has(sound):
		_voices[sound] = []
	(_voices[sound] as Array).append(player)


## Voice limiting: if this sound already has its maximum voices playing, the
## oldest one is cut and reused.
func _steal_voice(sound: String) -> Node:
	var active: Array = _voices.get(sound, [])
	var still: Array = []
	for p: Node in active:
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
	p3.unit_size = 7.0
	p3.max_distance = 90.0
	p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p3.panning_strength = 0.8
	host.add_child(p3)
	_pool_3d.append(p3)
	return p3


func _world_host() -> Node:
	var host := get_tree().root.get_node_or_null("GameWorld")
	if host == null or not host.is_inside_tree() or not host is Node3D:
		return null
	return host


# --- Buses ---------------------------------------------------------------------------------

func _setup_buses() -> void:
	for bus_name: String in ["Music", "SFX", "Ambient", "UI"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, &"Master")
	for bus_name: String in ["SFX", "Ambient"]:
		var idx := AudioServer.get_bus_index(bus_name)
		if AudioServer.get_bus_effect_count(idx) == 0:
			var reverb := AudioEffectReverb.new()
			reverb.room_size = 0.45
			reverb.damping = 0.6
			reverb.wet = 0.1
			reverb.dry = 1.0
			AudioServer.add_bus_effect(idx, reverb)
			var lowpass := AudioEffectLowPassFilter.new()
			lowpass.cutoff_hz = 20000.0
			AudioServer.add_bus_effect(idx, lowpass)
			AudioServer.set_bus_effect_enabled(idx, 1, false)
	var master := AudioServer.get_bus_index(&"Master")
	if AudioServer.get_bus_effect_count(master) == 0:
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -0.5
		AudioServer.add_bus_effect(master, limiter)


func _apply_muffle() -> void:
	var cutoff := 20000.0 * pow(MUFFLE_MIN_HZ / 20000.0, _muffle)
	for bus_name: String in ["SFX", "Ambient"]:
		var idx := AudioServer.get_bus_index(bus_name)
		if AudioServer.get_bus_effect_count(idx) < 2:
			continue
		var lp := AudioServer.get_bus_effect(idx, 1) as AudioEffectLowPassFilter
		lp.cutoff_hz = cutoff
		AudioServer.set_bus_effect_enabled(idx, 1, _muffle > 0.01)


## Looked up by path so this script also compiles where autoloads are absent (tests).
func _settings() -> Node:
	return get_node_or_null("/root/Settings")


func _apply_volumes() -> void:
	var settings := _settings()
	if settings == null:
		return
	_set_bus_volume(&"Master", float(settings.call("get_value", "audio", "master")))
	_set_bus_volume(&"Music", float(settings.call("get_value", "audio", "music")))
	_set_bus_volume(&"SFX", float(settings.call("get_value", "audio", "sfx")))
	_set_bus_volume(&"UI", float(settings.call("get_value", "audio", "sfx")))
	_set_bus_volume(&"Ambient", float(settings.call("get_value", "audio", "ambient")))


func _set_bus_volume(bus: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))


func _on_setting(section: String, _key: String) -> void:
	if section == "audio":
		_apply_volumes()
