extends TestCase
## Audio: every contract sound exists and renders sane, non-silent,
## non-clipping, click-free data; ambience and music loops are seamless;
## recordings are present; the Audio API tolerates unknown names.
##
## Set BURN_AUDIO_SAMPLES=/some/dir to also write WAV samples for inspection
## (or use tests/audio/render_sounds.gd for every variant).

## docs/ARCHITECTURE.md "Audio contract" + docs/REALISM_CONTRACTS.md "Audio additions".
const CONTRACT_SOUNDS := ["ui_hover", "ui_click", "ui_back", "ui_open", "ui_close", "rune", "step_grass", "step_stone",
	"step_wood", "step_snow", "step_sand", "swing", "hit", "hit_heavy", "crit", "block_hit", "block_break", "block_place",
	"pickup", "coin", "potion", "hurt", "death", "levelup", "quest", "fireball_cast", "fireball_hit", "explosion", "arrow",
	"bow", "roar", "roar_big", "wing_flap", "stomp", "growl", "bone_rattle", "imp_screech", "door", "chest", "shrine",
	"portal", "thunder", "splash", "lava_bubble", "burn",
	# Realism additions
	"jump", "land", "land_heavy", "roll", "step_run", "swing_light", "swing_heavy", "swing_blunt",
	"hit_flesh", "hit_bone", "hit_metal", "hit_wood", "pick_stone", "pick_dirt", "pick_wood", "break_stone", "break_dirt",
	"break_wood", "break_crystal", "tree_creak", "tree_fall", "rustle", "splash_small", "water_wade", "equip", "cloth",
	# Crafting, items, wildlife, sea boss
	"craft", "saw", "hammer_anvil", "furnace_roar", "quench", "smelt_done", "equip_metal", "equip_cloth", "gem",
	"wolf_howl", "wolf_growl", "bear_roar", "spider_hiss", "bat_screech", "bird_flap", "deer_call", "splash_big",
	"leviathan_roar", "wave_crash", "water_spout", "dive",
	# Extra surface
	"step_dirt"]

const MusicKit := preload("res://audio/music_kit.gd")

const CONTRACT_AMBIENCE := ["wind", "rain", "fire", "cave", "lava", "village", "birds", "insects", "crickets", "leaves",
	"ocean", "waterfall", "stream", "underwater", "furnace"]


func _sample_dir() -> String:
	return OS.get_environment("BURN_AUDIO_SAMPLES")


func _save(chans: Array, file_name: String) -> void:
	var dir := _sample_dir()
	if dir == "":
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var w := Synth.to_wav(Synth.to_bytes(chans[0]), false)
	w.save_to_wav(dir.path_join(file_name + ".wav"))


func _check_buffer(b: PackedFloat32Array, label: String, min_sec: float, max_sec: float) -> void:
	var sec := Synth.seconds(b.size())
	check(sec >= min_sec and sec <= max_sec, "%s length %.2f s" % [label, sec])
	var p := Synth.peak(b)
	check(p <= 1.0 and p > 0.1, "%s peak %.3f" % [label, p])
	check(Synth.rms(b) > 0.003, "%s is not silent (rms %.4f)" % [label, Synth.rms(b)])
	var sum := 0.0
	for v in b:
		if is_nan(v) or is_inf(v):
			check(false, "%s contains NaN/Inf" % label)
			return
		sum += v
	check(absf(sum / b.size()) < 0.01, "%s DC offset %.4f" % [label, sum / b.size()])


## One-shots must start and end at (near) zero: no clicks.
func _check_edges(b: PackedFloat32Array, label: String) -> void:
	var p := maxf(Synth.peak(b), 1e-6)
	check(absf(b[0]) < 0.02 * p + 0.002, "%s starts with a click (%.4f)" % [label, b[0]])
	check(absf(b[b.size() - 1]) < 0.01 * p + 0.001, "%s ends with a click (%.4f)" % [label, b[b.size() - 1]])


## The step across the loop point must look like any other step in the signal.
func _check_seamless(b: PackedFloat32Array, label: String) -> void:
	var steps := PackedFloat32Array()
	for i in range(0, b.size() - 1, 7):
		steps.append(absf(b[i + 1] - b[i]))
	steps.sort()
	var p999 := steps[int(steps.size() * 0.999)]
	var seam := absf(b[0] - b[b.size() - 1])
	check(seam <= p999 * 1.5 + 0.002, "%s loop seam %.4f vs typical step %.4f" % [label, seam, p999])


func test_every_contract_sound_exists() -> void:
	for sound: String in CONTRACT_SOUNDS:
		check(SfxLibrary.SOUNDS.has(sound), "sound %s defined" % sound)
		check(SfxLibrary.variants(sound) >= 1, "sound %s has variants" % sound)
	# Frequently repeated sounds need several takes so repeats are not mechanical.
	for sound: String in SfxLibrary.names():
		if not sound.begins_with("ui_") and not sound in ["death", "levelup", "quest", "shrine", "portal"]:
			check(SfxLibrary.variants(sound) >= 2, "sound %s has >= 2 variants" % sound)
		check(SfxLibrary.TARGET_DB.has(SfxLibrary.category(sound)), "sound %s has a known category" % sound)


## Every sound (variant 0) renders a sane, audible, click-free buffer.
func test_sfx_render_sane() -> void:
	var t := Time.get_ticks_usec()
	for sound: String in SfxLibrary.names():
		var one := Time.get_ticks_usec()
		var b := SfxLibrary.build(sound, 0)
		# Very generous: only catches runaway recipes (real cost 5-1500 ms).
		check((Time.get_ticks_usec() - one) / 1000.0 < 30000.0, "%s renders in reasonable time" % sound)
		_check_buffer(b, sound, 0.02, 6.0)
		_check_edges(b, sound)
		_save([b], "sfx_" + sound)
	check(SampleBank.missing.is_empty(), "recordings missing: %s" % ", ".join(SampleBank.missing))
	print("      %d sounds (variant 0) rendered single-threaded in %.0f ms" % [SfxLibrary.names().size(),
			(Time.get_ticks_usec() - t) / 1000.0])


func test_variants_differ() -> void:
	for sound: String in ["step_grass", "hit", "swing", "pick_stone"]:
		var a := SfxLibrary.build(sound, 0)
		var b := SfxLibrary.build(sound, 1)
		check(a != b, "%s variants differ" % sound)


func test_recordings_load() -> void:
	for file: String in ["kenney_impact/footstep_grass_000.ogg", "kenney_rpg/cloth1.ogg", "field/river_thimras.ogg",
			"field/crickets_wolfgang.ogg"]:
		var b := SampleBank.mono(file)
		check(b.size() > Synth.SR * 0.05, "%s decodes (%d samples)" % [file, b.size()])
		check(Synth.peak(b) > 0.05, "%s is audible" % file)


func test_ambience_loops_seamless() -> void:
	for bed: String in CONTRACT_AMBIENCE:
		check(bed in AmbienceLibrary.PUBLIC, "ambience key %s accepted" % bed)
	var t := Time.get_ticks_usec()
	for bed: String in AmbienceLibrary.BEDS:
		var chans := AmbienceLibrary.build_channels(bed)
		var expected := AmbienceLibrary.length_of(bed)
		check_eq(chans.size(), AmbienceLibrary.channels_of(bed), "%s channel count" % bed)
		for c in chans.size():
			var b: PackedFloat32Array = chans[c]
			_check_buffer(b, "ambience %s[%d]" % [bed, c], expected - 0.01, expected + 0.01)
			_check_seamless(b, "ambience %s[%d]" % [bed, c])
		_save(chans, "amb_" + bed)
	print("      ambience beds rendered in %.0f ms" % ((Time.get_ticks_usec() - t) / 1000.0))


## Every state (incl. one per boss and per biome) builds a sane, seamless loop
## in bounded time; the tracks are all different, and the fights are more
## driving (louder onsets, more rhythm) than the calm biome music.
func test_music_loops_seamless() -> void:
	var feats := {}
	var worst := 0.0
	for state: String in MusicLibrary.STATES:
		var t := Time.get_ticks_usec()
		var b := MusicLibrary.build(state)
		var ms := (Time.get_ticks_usec() - t) / 1000.0
		worst = maxf(worst, ms)
		var expected := MusicLibrary.length_of(state)
		_check_buffer(b, "music " + state, expected - 0.01, expected + 0.01)
		_check_seamless(b, "music " + state)
		_save([b], "music_" + state)
		feats[state] = _music_features(b)
		var f: Array = feats[state]
		print("      music %-20s %5.0f ms  %4.1f s  zcr %.3f  low %.2f  pulse %.3f" % [state, ms, expected, f[0], f[1], f[2]])
	check(worst < 15000.0, "music renders in bounded time (worst %.0f ms)" % worst)
	var names: Array = feats.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: Array = feats[names[i]]
			var c: Array = feats[names[j]]
			var d := absf(a[0] - c[0]) * 20.0 + absf(a[1] - c[1]) + absf(a[2] - c[2]) * 4.0 + absf(a[3] - c[3]) * 50.0
			check(d > 0.002, "music %s and %s differ (%.4f)" % [names[i], names[j], d])
	var fight := 0.0
	var calm := 0.0
	for s: String in MusicLibrary.BOSS_STATES:
		fight += float(feats[s][2]) / MusicLibrary.BOSS_STATES.size()
	for s: String in MusicLibrary.BIOME_STATES:
		calm += float(feats[s][2]) / MusicLibrary.BIOME_STATES.size()
	check(fight > calm * 1.3, "boss music drives harder than biome music (pulse %.3f vs %.3f)" % [fight, calm])


## [zero-crossing rate (brightness), low-band share, pulse (mean positive
## change of a 20 ms loudness envelope relative to its mean), first-second mean].
func _music_features(b: PackedFloat32Array) -> Array:
	var zc := 0
	for i in range(1, b.size()):
		if (b[i] >= 0.0) != (b[i - 1] >= 0.0):
			zc += 1
	var low := Synth.lp(Synth.lp(b.duplicate(), 180.0), 180.0)
	var low_share := Synth.rms(low) / maxf(Synth.rms(b), 1e-6)
	var win := Synth.samples(0.02)
	var envs := PackedFloat32Array()
	var i := 0
	while i + win <= b.size():
		var acc := 0.0
		for k in range(i, i + win, 4):
			acc += absf(b[k])
		envs.append(acc / (win / 4.0))
		i += win
	var mean := 0.0
	for e in envs:
		mean += e / envs.size()
	var rise := 0.0
	for k in range(1, envs.size()):
		rise += maxf(0.0, envs[k] - envs[k - 1])
	var first := 0.0
	for k in mini(50, envs.size()):
		first += envs[k] / 50.0
	return [float(zc) / b.size(), low_share, rise / envs.size() / maxf(mean, 1e-6), first]


## Every boss has its own fight music; unknown names fall back, never silence.
func test_music_states_and_fallbacks() -> void:
	for kind: String in ["warden", "mountain_king", "dragon", "cerberus", "hades", "broodmother", "bog_hag",
			"leviathan", "kraken", "charybdis", "ryft_sentinel", "void_sovereign"]:
		check("boss_" + kind in MusicLibrary.STATES, "boss %s has fight music" % kind)
	for s: String in MusicLibrary.BASE_STATES:
		check_eq(MusicLibrary.resolve(s), s, "old state %s still plays" % s)
	check_eq(MusicLibrary.resolve("boss_no_such_boss"), "boss", "unknown boss -> generic fight")
	check_eq(MusicLibrary.resolve("biome_no_such_biome"), "explore", "unknown biome -> plains")
	check_eq(MusicLibrary.resolve("nonsense"), "", "unknown state -> silence")
	check(MusicLibrary.is_fight("boss_dragon") and not MusicLibrary.is_fight("biome_sea"), "fights are told apart")
	var audio: Node = load("res://audio/audio.gd").new()
	audio.call("set_music", "nonsense")
	check_eq(audio.call("current_music"), "silence", "unknown music request is silence, not an error")
	audio.free()
	check_eq(MusicKit.midi_of("C4"), 60, "note names: C4")
	check_eq(MusicKit.midi_of("Bb2"), 46, "note names: Bb2")
	check_eq(MusicKit.midi_of("F#5"), 78, "note names: F#5")


func test_audio_autoload_api() -> void:
	var script: GDScript = load("res://audio/audio.gd")
	var names := []
	for m in script.get_script_method_list():
		names.append(m["name"])
	for method: String in ["play", "play_ui", "set_music", "set_ambience", "set_ambience_source", "set_muffle"]:
		check(method in names, "Audio.%s exists" % method)


## Unknown sound names and ambience keys are ignored, not errors.
func test_unknown_names_are_harmless() -> void:
	var audio: Node = load("res://audio/audio.gd").new()
	audio.call("play", "no_such_sound", Vector3(1, 2, 3))
	audio.call("play", "no_such_sound")
	audio.call("play_ui", "no_such_sound")
	audio.call("set_ambience", {"no_such_bed": 1.0, "wind": 0.5, "rain": 2.0})
	audio.call("set_ambience_source", "forge", {"furnace": 0.8, "bogus": 1.0})
	audio.call("set_ambience_source", "forge", {})
	check(SfxLibrary.variants("no_such_sound") == 0, "unknown sound has no variants")
	audio.free()


func test_level_and_limit() -> void:
	var r := Synth.rng(3)
	var b := Synth.decay(Synth.noise(0.5, r), 0.0005, 0.05)
	Synth.gain(b, 3.0)
	Synth.level(b, -10.0)
	check(Synth.peak(b) <= 0.95, "level() keeps the peak under the ceiling (%.3f)" % Synth.peak(b))
	var quiet := Synth.gain(Synth.lp(Synth.noise(0.5, r), 500.0), 0.01)
	Synth.level(quiet, -12.0)
	check_near(linear_to_db(Synth.loudness(quiet)), -12.0, 0.5, "level() reaches its loudness target")


func test_wav_encoding() -> void:
	var b := PackedFloat32Array([0.0, 1.0, -1.0, 0.5])
	var bytes := Synth.to_bytes(b)
	check_eq(bytes.size(), 8)
	check_eq(bytes.decode_s16(2), 32767)
	check_eq(bytes.decode_s16(4), -32767)
	var w := Synth.to_wav(bytes, true)
	check_eq(w.loop_end, 4)
	check_eq(w.mix_rate, Synth.SR)
