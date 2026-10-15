extends SceneTree
## Renders every sound effect variant and ambience bed to WAV files for
## listening and analysis (tests/audio/analyze_wavs.py, spectrogram.py).
##
##   godot --headless --path . -s res://tests/audio/render_sounds.gd -- out=/tmp/burn_audio [only=a,b] [first] [noamb] [nosfx]
##
## `first` renders only variant 0 of each sound; `only` limits to the listed
## sounds / beds. Prints the render time of each item.

var _done := false


func _init() -> void:
	# Keep the Audio autoload from rendering everything in the background too.
	Engine.set_meta(&"audio_offline", true)


func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		_run()
		quit()
	return false


func _run() -> void:
	var out := "/tmp/burn_audio"
	var only: Array = []
	var first := false
	var do_amb := true
	var do_sfx := true
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		elif a.begins_with("only="):
			only = Array(a.substr(5).split(","))
		elif a == "first":
			first = true
		elif a == "noamb":
			do_amb = false
		elif a == "nosfx":
			do_sfx = false
	DirAccess.make_dir_recursive_absolute(out)
	var total := Time.get_ticks_usec()
	if do_sfx:
		for sound: String in SfxLibrary.names():
			if not only.is_empty() and not sound in only:
				continue
			var t := Time.get_ticks_usec()
			var n := 1 if first else SfxLibrary.variants(sound)
			for v in n:
				var b := SfxLibrary.build(sound, v)
				write_wav(out.path_join("%s_%d.wav" % [sound, v]), [b], Synth.SR)
			print("sfx %-16s x%d  %6.0f ms" % [sound, n, (Time.get_ticks_usec() - t) / 1000.0])
	if do_amb:
		for bed: String in AmbienceLibrary.BEDS:
			if not only.is_empty() and not bed in only:
				continue
			var t := Time.get_ticks_usec()
			var ch := AmbienceLibrary.build_channels(bed)
			write_wav(out.path_join("amb_%s.wav" % bed), ch, Synth.SR)
			print("amb %-16s %6.0f ms" % [bed, (Time.get_ticks_usec() - t) / 1000.0])
	print("total %.0f ms" % ((Time.get_ticks_usec() - total) / 1000.0))


static func write_wav(path: String, channels: Array, rate: int) -> void:
	var nch := channels.size()
	var first: PackedFloat32Array = channels[0]
	var frames := first.size()
	var data := PackedByteArray()
	data.resize(frames * nch * 2)
	for i in frames:
		for c in nch:
			var ch: PackedFloat32Array = channels[c]
			data.encode_s16((i * nch + c) * 2, int(clampf(ch[i], -1.0, 1.0) * 32767.0))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + data.size())
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(nch)
	f.store_32(rate)
	f.store_32(rate * nch * 2)
	f.store_16(nch * 2)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data.size())
	f.store_buffer(data)
	f.close()
