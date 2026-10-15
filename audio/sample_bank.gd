class_name SampleBank
extends RefCounted
## Recorded CC0 samples (audio/samples/, see CREDITS.md), decoded to float PCM
## at Synth.SR so recipes can trim, filter and layer them with synthesised
## material. Thread-safe: recipes call it from worker threads.
##
## Decoding uses the engine's own resampler (AudioStreamPlayback.mix_audio),
## and an optional `rate` re-pitches the recording (0.5 = an octave down and
## twice as long) at no extra cost.

const DIR := "res://audio/samples/"

static var _cache := {}
static var _mutex := Mutex.new()
## Files requested but not found (tests assert this stays empty).
static var missing: PackedStringArray = []


## Mono PCM of `file` (path relative to audio/samples/). Empty if missing.
## Decodes are cached at the original pitch; other rates are resampled from it.
static func mono(file: String, rate := 1.0) -> PackedFloat32Array:
	_mutex.lock()
	var hit: Variant = _cache.get(file)
	_mutex.unlock()
	var l: PackedFloat32Array
	if hit != null:
		l = hit
	else:
		var st := stereo(file)
		l = st[0]
		var r: PackedFloat32Array = st[1]
		for i in l.size():
			l[i] = (l[i] + r[i]) * 0.5
		_mutex.lock()
		_cache[file] = l
		_mutex.unlock()
	if is_equal_approx(rate, 1.0) or l.is_empty():
		return l.duplicate()
	return Synth.resample(l, rate)


## Drop cached decodes (Audio calls this once every sound is built).
static func clear() -> void:
	_mutex.lock()
	_cache.clear()
	_mutex.unlock()


## [left, right] PCM of `file`.
static func stereo(file: String, rate := 1.0) -> Array:
	var path := DIR + file
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = ResourceLoader.load(path) as AudioStream
	if stream == null:
		push_error("SampleBank: missing sample %s" % path)
		_mutex.lock()
		missing.append(file)
		_mutex.unlock()
		return [PackedFloat32Array(), PackedFloat32Array()]
	var mix_rate := AudioServer.get_mix_rate()
	if mix_rate <= 0.0:
		mix_rate = 44100.0
	var pb := stream.instantiate_playback()
	# Played at `scale` x speed into a mix_rate output, the result holds
	# Synth.SR frames per (re-pitched) second.
	var scale := rate * mix_rate / Synth.SR
	var frames := int(ceil(stream.get_length() * Synth.SR / rate)) + 64
	pb.start(0.0)
	var mixed: PackedVector2Array = pb.mix_audio(scale, frames)
	pb.stop()
	var l := PackedFloat32Array()
	var r := PackedFloat32Array()
	l.resize(mixed.size())
	r.resize(mixed.size())
	for i in mixed.size():
		var v := mixed[i]
		l[i] = v.x
		r[i] = v.y
	return [l, r]


static func has(file: String) -> bool:
	return ResourceLoader.exists(DIR + file)
