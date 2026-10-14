class_name MusicLibrary
extends RefCounted
## The adaptive score: one loopable stem per game state, all in D (dorian /
## aeolian / phrygian colours), rendered offline. Every event writes with
## wrap-around so note tails flow over the loop point, and global effects run
## through Synth.process_loop, so the loops are seamless by construction.

const S := preload("res://audio/synth.gd")

const STATES := ["menu", "explore", "night", "cave", "boss", "hell", "victory"]

# Chords as MIDI notes.
const DM := [50, 57, 62, 65]
const BB := [46, 53, 62, 65]
const F := [41, 53, 60, 65]
const C := [48, 55, 60, 64]
const GM := [43, 50, 58, 62]
const A := [45, 52, 61, 64]
const EB := [51, 58, 63, 67]
const D_MAJ := [50, 57, 62, 66]
const G_MAJ := [43, 55, 59, 62]
const BM := [47, 54, 59, 62]
const A_MAJ := [45, 57, 61, 64]


static func hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


static func length_of(state: String) -> float:
	return 16.0 if state in ["boss", "victory"] else 24.0


static func build(state: String) -> PackedFloat32Array:
	var r := S.rng(hash(state) + 2026)
	var b := S.make(length_of(state))
	match state:
		"menu": _menu(b, r)
		"explore": _explore(b, r)
		"night": _night(b, r)
		"cave": _cave(b, r)
		"boss": _boss(b, r)
		"hell": _hell(b, r)
		"victory": _victory(b, r)
		_:
			push_error("Unknown music state %s" % state)
	b = S.process_loop(b, func(x: PackedFloat32Array) -> PackedFloat32Array: return S.dc_block(x))
	S.normalize(b, 0.8)
	return S.soft_clip(b, 1.2)


# --- Instruments -------------------------------------------------------------------

## Detuned saw stack per chord, each voice low-passed (two poles) and tiled
## from a steady-state block (Synth.periodic), with slow attack and a release
## that overlaps the next chord. `process` replaces the low-pass (choir).
static func _pad(out: PackedFloat32Array, chords: Array, chord_sec: float, cutoff: float, gain: float,
		attack := 1.2, release := 1.8, detune := 0.006, octave := 0, process := Callable()) -> void:
	var shape := process
	if not shape.is_valid():
		shape = func(x: PackedFloat32Array) -> PackedFloat32Array:
			return S.lp(S.lp(x, cutoff), cutoff * 1.5)
	var seg_sec := chord_sec + release
	for ci in chords.size():
		var notes: Array = chords[ci]
		var chord := S.make(seg_sec)
		var voices := 0
		for m: int in notes:
			var f := hz(m + 12 * octave)
			for d: float in [-detune, detune]:
				var v := S.periodic(seg_sec, S.Wave.SAW, f * (1.0 + d), shape)
				S.add(chord, v, 1.0)
				voices += 1
		S.env(chord, [Vector2(0, 0), Vector2(attack, 1.0), Vector2(chord_sec, 1.0), Vector2(seg_sec, 0.0)])
		S.add(out, chord, gain / sqrt(float(voices)), int(ci * chord_sec * S.SR), true)


## Plucked string (harp / lute) at a beat position.
static func _pluck(out: PackedFloat32Array, r: RandomNumberGenerator, midi: int, at: float, gain: float, dur := 2.0, bright := 0.6) -> void:
	var p := S.pluck(dur, hz(midi), 0.996, bright, r)
	S.decay(p, 0.002, dur * 0.4)
	S.add(out, p, gain, int(at * S.SR), true)


static func _bell(out: PackedFloat32Array, midi: int, at: float, gain: float, dur := 3.0) -> void:
	var b := S.bell(dur, hz(midi), [1.0, 2.76, 5.4, 8.93], [0.6, 0.25, 0.1, 0.04], [dur * 0.4, dur * 0.2, dur * 0.08, 0.05])
	S.add(out, b, gain, int(at * S.SR), true)


## War drum: pitched sine drop + skin noise.
static func _drum(out: PackedFloat32Array, r: RandomNumberGenerator, at: float, gain: float, pitch := 70.0, length := 0.7) -> void:
	var d := S.osc(length, S.Wave.SINE, [Vector2(0, pitch * 1.6), Vector2(0.08, pitch), Vector2(length, pitch * 0.8)])
	S.decay(d, 0.002, length * 0.3)
	var skin := S.lp(S.decay(S.noise(0.15, r), 0.001, 0.03), 900.0)
	S.add(d, skin, 0.5)
	S.add(out, d, gain, int(at * S.SR), true)


## Low brass-like stab: saw chord with a filter swell.
static func _stab(out: PackedFloat32Array, chord: Array, at: float, gain: float, length := 0.9) -> void:
	var b := S.make(length)
	for m: int in chord:
		S.add(b, S.tone(length, S.Wave.SAW, hz(m - 12)), 0.3)
		S.add(b, S.tone(length, S.Wave.SAW, hz(m - 12) * 1.004), 0.3)
	S.filter(b, S.Filter.LOWPASS, [Vector2(0, 250), Vector2(0.08, 1800), Vector2(length, 400)], 1.2)
	S.env(b, [Vector2(0, 0), Vector2(0.04, 1.0), Vector2(0.3, 0.6), Vector2(length, 0)])
	S.add(out, b, gain, int(at * S.SR), true)


## Choir: saw pad shaped into an "ah" vowel by a formant bank.
static func _choir(out: PackedFloat32Array, chords: Array, chord_sec: float, gain: float) -> void:
	var vowel := func(x: PackedFloat32Array) -> PackedFloat32Array:
		return S.lp(S.formants(x, [700.0, 1220.0, 2600.0], [1.0, 0.5, 0.25], 5.0), 3000.0)
	_pad(out, chords, chord_sec, 0.0, gain * 2.5, 1.6, 2.0, 0.01, 0, vowel)


static func _drone(out: PackedFloat32Array, midi: int, gain: float) -> void:
	var dur := S.seconds(out.size())
	var f := hz(midi)
	# Block lengths that divide the loop, so the drone loops without a seam.
	var d := S.periodic(dur, S.Wave.SINE, f, Callable(), out.size())
	S.add(d, S.periodic(dur, S.Wave.SINE, f * 1.5, Callable(), out.size()), 0.35)
	S.add(out, d, gain)


static func _space(b: PackedFloat32Array, delay: float, feedback: float, wet: float) -> void:
	var processed := S.process_loop(b, func(x: PackedFloat32Array) -> PackedFloat32Array:
		return S.echo(x, delay, feedback, wet, 0.45))
	for i in b.size():
		b[i] = processed[i]


static func _scale_melody(out: PackedFloat32Array, r: RandomNumberGenerator, scale: Array, beats: int, beat_sec: float,
		density: float, gain: float, octave: int, bright := 0.55) -> void:
	var idx := r.randi_range(0, scale.size() - 1)
	for beat in beats:
		if r.randf() > density:
			continue
		idx = clampi(idx + r.randi_range(-2, 2), 0, scale.size() - 1)
		_pluck(out, r, int(scale[idx]) + 12 * octave, beat * beat_sec, gain * r.randf_range(0.7, 1.0), 2.4, bright)


# --- States ----------------------------------------------------------------------------

static func _menu(b: PackedFloat32Array, r: RandomNumberGenerator) -> void:
	_pad(b, [DM, BB, GM, A], 6.0, 900.0, 0.5, 2.0, 2.5)
	_drone(b, 38, 0.18)
	var pent := [62, 65, 67, 69, 72, 74]
	_scale_melody(b, r, pent, 48, 0.5, 0.32, 0.35, 1, 0.5)
	for i in 4:
		_bell(b, [62, 58, 55, 57][i], i * 6.0 + 0.05, 0.12, 4.0)
	_space(b, 0.375, 0.45, 0.4)


static func _explore(b: PackedFloat32Array, r: RandomNumberGenerator) -> void:
	var chords := [DM, BB, F, C]
	_pad(b, chords, 6.0, 1100.0, 0.42, 1.5, 2.0)
	_drone(b, 38, 0.12)
	# Lute arpeggio in eighth notes at 80 bpm (0.375 s).
	var eighth := 0.375
	for ci in chords.size():
		var ch: Array = chords[ci]
		var pattern := [0, 1, 2, 3, 2, 1, 2, 3]
		for step in 16:
			if r.randf() < 0.12:
				continue
			var note: int = ch[pattern[step % pattern.size()]] + (12 if step % 8 >= 4 else 0)
			_pluck(b, r, note, ci * 6.0 + step * eighth, 0.22 if step % 4 == 0 else 0.14, 1.6, 0.75)
	_scale_melody(b, r, [69, 72, 74, 77, 79, 81], 48, 0.5, 0.18, 0.2, 0, 0.45)
	_space(b, 0.375, 0.3, 0.25)


static func _night(b: PackedFloat32Array, r: RandomNumberGenerator) -> void:
	_pad(b, [DM, GM, BB, A], 6.0, 600.0, 0.5, 2.5, 3.0)
	_drone(b, 26, 0.15)
	_scale_melody(b, r, [62, 64, 65, 69, 70, 72], 24, 1.0, 0.35, 0.28, 0, 0.35)
	_space(b, 0.6, 0.5, 0.45)


static func _cave(b: PackedFloat32Array, r: RandomNumberGenerator) -> void:
	_pad(b, [DM, EB], 12.0, 420.0, 0.45, 3.0, 3.0, 0.004, -1)
	_drone(b, 26, 0.3)
	var t := 0.5
	while t < 23.0:
		_bell(b, [74, 75, 81, 86][r.randi_range(0, 3)], t, 0.08, 2.5)
		t += r.randf_range(2.0, 5.0)
	_space(b, 0.8, 0.55, 0.5)


static func _boss(b: PackedFloat32Array, r: RandomNumberGenerator) -> void:
	# 120 bpm, 8 bars. Ostinato low strings, war drums, brass stabs, choir.
	var beat := 0.5
	var bars := [DM, DM, BB, C, DM, DM, BB, A]
	var ost := [38, 38, 50, 38, 41, 38, 48, 38]
	var low := S.make(S.seconds(b.size()))
	for bar in 8:
		var root: int = (bars[bar] as Array)[0]
		for e in 8:
			var note: int = ost[e] + (root - 50 if bar % 4 >= 2 else 0)
			var t := bar * 4 * beat + e * beat * 0.5
			var s := S.tone(0.24, S.Wave.SAW, hz(note))
			S.lp(s, 700.0)
			S.decay(s, 0.003, 0.08)
			S.add(low, s, 0.35, int(t * S.SR), true)
	S.add(b, low, 1.0)
	for bar in 8:
		var t0 := bar * 4 * beat
		_drum(b, r, t0, 0.9, 62.0, 0.8)
		_drum(b, r, t0 + 1.5 * beat, 0.5, 92.0, 0.4)
		_drum(b, r, t0 + 2.0 * beat, 0.75, 70.0, 0.7)
		_drum(b, r, t0 + 3.0 * beat, 0.45, 110.0, 0.3)
		_drum(b, r, t0 + 3.5 * beat, 0.45, 110.0, 0.3)
		if bar % 2 == 0:
			_stab(b, bars[bar], t0, 0.5, 1.2)
	_choir(b, [DM, BB, DM, A], 4.0, 0.25)
	_space(b, 0.25, 0.25, 0.18)


static func _hell(b: PackedFloat32Array, r: RandomNumberGenerator) -> void:
	_choir(b, [DM, EB, DM, [49, 56, 61, 64]], 6.0, 0.55)
	_drone(b, 26, 0.35)
	for i in 12:
		_drum(b, r, i * 2.0, 0.6 if i % 2 == 0 else 0.35, 52.0, 1.2)
	var t := 1.0
	while t < 23.0:
		_bell(b, [62, 63, 69, 70][r.randi_range(0, 3)] - 12, t, 0.15, 3.5)
		t += r.randf_range(3.0, 6.0)
	_space(b, 0.9, 0.5, 0.4)


static func _victory(b: PackedFloat32Array, r: RandomNumberGenerator) -> void:
	var chords := [D_MAJ, G_MAJ, BM, A_MAJ]
	_pad(b, chords, 4.0, 1600.0, 0.4, 0.8, 1.6)
	var sixteenth := 0.25
	for ci in chords.size():
		var ch: Array = chords[ci]
		for step in 16:
			var note: int = ch[[0, 1, 2, 3, 2, 3, 1, 2][step % 8]] + 12
			_pluck(b, r, note, ci * 4.0 + step * sixteenth, 0.18, 1.4, 0.8)
	for i in 4:
		_bell(b, [74, 79, 78, 76][i] + 12, i * 4.0, 0.15, 3.0)
	_space(b, 0.5, 0.35, 0.3)
