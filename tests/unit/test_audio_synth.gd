extends TestCase
## Procedural audio: every contract sound exists and renders sane, non-silent,
## non-clipping data; ambience and music loops are seamless; timings.
##
## Set BURN_AUDIO_SAMPLES=/some/dir to also write WAV samples for inspection.

const CONTRACT_SOUNDS := ["ui_hover", "ui_click", "ui_back", "ui_open", "ui_close", "rune", "step_grass", "step_stone",
	"step_wood", "step_snow", "step_sand", "swing", "hit", "hit_heavy", "crit", "block_hit", "block_break", "block_place",
	"pickup", "coin", "potion", "hurt", "death", "levelup", "quest", "fireball_cast", "fireball_hit", "explosion", "arrow",
	"bow", "roar", "roar_big", "wing_flap", "stomp", "growl", "bone_rattle", "imp_screech", "door", "chest", "shrine",
	"portal", "thunder", "splash", "lava_bubble", "burn"]


func _sample_dir() -> String:
	return OS.get_environment("BURN_AUDIO_SAMPLES")


func _save(b: PackedFloat32Array, file_name: String, loop: bool) -> void:
	var dir := _sample_dir()
	if dir == "":
		return
	DirAccess.make_dir_recursive_absolute(dir)
	Synth.to_wav(Synth.to_bytes(b), loop).save_to_wav(dir.path_join(file_name + ".wav"))


func _check_buffer(b: PackedFloat32Array, label: String, min_sec: float, max_sec: float) -> void:
	var sec := Synth.seconds(b.size())
	check(sec >= min_sec and sec <= max_sec, "%s length %.2f s" % [label, sec])
	var p := Synth.peak(b)
	check(p <= 1.0 and p > 0.2, "%s peak %.3f" % [label, p])
	check(Synth.rms(b) > 0.005, "%s is not silent (rms %.4f)" % [label, Synth.rms(b)])
	for v in b:
		if is_nan(v) or is_inf(v):
			check(false, "%s contains NaN/Inf" % label)
			return


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


func test_sfx_render_sane() -> void:
	var t := Time.get_ticks_usec()
	var total := 0
	for sound: String in SfxLibrary.names():
		for v in SfxLibrary.variants(sound):
			var one := Time.get_ticks_usec()
			var b := SfxLibrary.build(sound, v)
			# Generous: real cost is 5-200 ms; the bound only catches regressions.
			check((Time.get_ticks_usec() - one) / 1000.0 < 4000.0, "%s#%d renders in reasonable time" % [sound, v])
			_check_buffer(b, "%s#%d" % [sound, v], 0.02, 6.0)
			total += 1
			if v == 0:
				_save(b, "sfx_" + sound, false)
	var ms := (Time.get_ticks_usec() - t) / 1000.0
	print("      %d sfx variants rendered single-threaded in %.0f ms" % [total, ms])


func test_variants_differ() -> void:
	for sound: String in ["step_grass", "hit", "swing", "block_hit"]:
		var a := SfxLibrary.build(sound, 0)
		var b := SfxLibrary.build(sound, 1)
		check(a != b, "%s variants differ" % sound)


func test_ambience_loops_seamless() -> void:
	var t := Time.get_ticks_usec()
	for bed: String in AmbienceLibrary.BEDS:
		var b := AmbienceLibrary.build(bed)
		_check_buffer(b, "ambience " + bed, AmbienceLibrary.LOOP - 0.01, AmbienceLibrary.LOOP + 0.01)
		_check_seamless(b, "ambience " + bed)
		_save(b, "amb_" + bed, true)
	print("      ambience beds rendered in %.0f ms" % ((Time.get_ticks_usec() - t) / 1000.0))


func test_music_loops_seamless() -> void:
	for state: String in MusicLibrary.STATES:
		var t := Time.get_ticks_usec()
		var b := MusicLibrary.build(state)
		var ms := (Time.get_ticks_usec() - t) / 1000.0
		var expected := MusicLibrary.length_of(state)
		_check_buffer(b, "music " + state, expected - 0.01, expected + 0.01)
		_check_seamless(b, "music " + state)
		_save(b, "music_" + state, true)
		print("      music %-8s %.0f ms" % [state, ms])


func test_audio_autoload_api() -> void:
	var script: GDScript = load("res://audio/audio.gd")
	var names := []
	for m in script.get_script_method_list():
		names.append(m["name"])
	for method: String in ["play", "play_ui", "set_music", "set_ambience", "set_muffle"]:
		check(method in names, "Audio.%s exists" % method)


func test_wav_encoding() -> void:
	var b := PackedFloat32Array([0.0, 1.0, -1.0, 0.5])
	var bytes := Synth.to_bytes(b)
	check_eq(bytes.size(), 8)
	check_eq(bytes.decode_s16(2), 32767)
	check_eq(bytes.decode_s16(4), -32767)
	var w := Synth.to_wav(bytes, true)
	check_eq(w.loop_end, 4)
	check_eq(w.mix_rate, Synth.SR)
