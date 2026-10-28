extends RefCounted
## Instruments and a small sequencer for MusicLibrary's scores.
##
## Every instrument writes one note into a loop buffer with wrap-around (tails
## flow over the loop point). Sustained voices are built with Synth.periodic:
## a few cycles are rendered and filtered once (timbre: low-pass, formants)
## and then tiled, so a note costs little more than its envelope. Detuned
## pairs give the slow beating that keeps a held note alive.
##
## Notation (parse): "D4:1.5 E4:.5 r:1 | C4+E4+G4:2" = note:beats, r = rest,
## + = several notes at once, | is ignored (bar lines for the reader).

const S := preload("res://audio/synth.gd")

const _IDX := {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


static func hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


## "C#4" -> 61. Accidentals: # and b (after the letter).
static func midi_of(name: String) -> int:
	var idx: int = _IDX[name[0].to_upper()]
	var i := 1
	while i < name.length() and name[i] in ["#", "b"]:
		idx += 1 if name[i] == "#" else -1
		i += 1
	return 12 * (int(name.substr(i)) + 1) + idx


## A chord from note names: ch("D3 A3 F4") -> [50, 57, 65].
static func ch(names: String) -> Array:
	var out := []
	for n in names.split(" ", false):
		out.append(midi_of(n))
	return out


## [[midis, beats], ...]; a rest has no midis.
static func parse(score: String) -> Array:
	var out := []
	for tok in score.split(" ", false):
		if tok == "|":
			continue
		var parts := tok.split(":")
		var beats := float(parts[1]) if parts.size() > 1 else 1.0
		var midis := []
		if parts[0] != "r":
			for n in parts[0].split("+"):
				midis.append(midi_of(n))
		out.append([midis, beats])
	return out


## Total beats of a score.
static func beats_of(score: String) -> float:
	var t := 0.0
	for e: Array in parse(score):
		t += float(e[1])
	return t


## Plays a score on `inst` from `start` beats. `legato` scales note lengths;
## `swell` gives each note a slight random gain (humanised).
static func seq(out: PackedFloat32Array, r: RandomNumberGenerator, inst: String, score: String, start: float,
		beat: float, gain: float, transpose := 0, legato := 1.0) -> float:
	var t := start
	for e: Array in parse(score):
		var beats := float(e[1])
		for m: int in e[0]:
			note(out, r, inst, m + transpose, t * beat, beats * beat * legato, gain * r.randf_range(0.88, 1.0))
		t += beats
	return t


## Arpeggio over a chord list: `pattern` indexes the chord (>= chord size wraps
## up an octave), one note every `step` beats.
static func arp(out: PackedFloat32Array, r: RandomNumberGenerator, inst: String, chords: Array, chord_beats: float,
		beat: float, pattern: Array, step: float, gain: float, transpose := 0, note_beats := 2.0, skip := 0.0) -> void:
	for ci in chords.size():
		var c: Array = chords[ci]
		var steps := int(round(chord_beats / step))
		for s in steps:
			if skip > 0.0 and r.randf() < skip:
				continue
			var k: int = pattern[s % pattern.size()]
			var m: int = c[k % c.size()] + 12 * (k / c.size())
			var accent := 1.0 if s % 4 == 0 else 0.75
			note(out, r, inst, m + transpose, (ci * chord_beats + s * step) * beat, note_beats * beat, gain * accent)


## Pattern drums: one character per step; X = accent, x = normal, o = ghost.
static func drums(out: PackedFloat32Array, r: RandomNumberGenerator, inst: String, pattern: String, bars: int,
		bar_sec: float, gain: float, midi := 40, start_bar := 0) -> void:
	var steps := pattern.length()
	for bar in range(start_bar, start_bar + bars):
		for s in steps:
			var c := pattern[s]
			var g := 1.0 if c == "X" else (0.62 if c == "x" else (0.3 if c == "o" else 0.0))
			if g <= 0.0:
				continue
			note(out, r, inst, midi, bar * bar_sec + s * bar_sec / steps, 0.5, gain * g * r.randf_range(0.9, 1.0))


## Sustained chords (pads): `inst` is "strings", "choir", "organ", "warm" or "glass_pad".
static func chords(out: PackedFloat32Array, r: RandomNumberGenerator, inst: String, list: Array, chord_sec: float,
		gain: float, transpose := 0) -> void:
	for ci in list.size():
		for m: int in list[ci]:
			note(out, r, inst, m + transpose, ci * chord_sec, chord_sec, gain / sqrt(float((list[ci] as Array).size())))


# --- Voices ---------------------------------------------------------------------------

static func _layer(sec: float, wave: S.Wave, f: float, detunes: Array, process: Callable) -> PackedFloat32Array:
	var b := S.make(sec)
	for d: float in detunes:
		S.add(b, S.periodic(sec, wave, f * (1.0 + d), process), 1.0 / sqrt(float(detunes.size())))
	return b


static func _adsr(b: PackedFloat32Array, attack: float, dur: float, release: float, sustain := 0.85, decay_t := 0.3) -> void:
	S.env(b, [Vector2(0, 0), Vector2(attack, 1.0), Vector2(attack + decay_t, sustain), Vector2(maxf(dur, attack + decay_t), sustain * 0.92),
		Vector2(maxf(dur, attack + decay_t) + release, 0.0)])


static func _formant(fs: Array, gs: Array, q: float, top: float) -> Callable:
	return func(x: PackedFloat32Array) -> PackedFloat32Array:
		return S.lp(S.formants(x, fs, gs, q), top)


static func note(out: PackedFloat32Array, r: RandomNumberGenerator, inst: String, midi: int, at: float, dur: float, gain: float) -> void:
	var f := hz(midi)
	var b := PackedFloat32Array()
	match inst:
		"brass":  # bright section brass: a brassy "blat" settling into a rounder tone
			var rel := 0.3
			var cut := minf(f * 6.0, 3000.0)
			b = _layer(dur + rel, S.Wave.SAW, f, [-0.003, 0.0035], func(x: PackedFloat32Array) -> PackedFloat32Array:
				return S.lp(S.lp(x, cut), cut * 1.5))
			var blat := S.periodic(dur + rel, S.Wave.SAW, f, func(x: PackedFloat32Array) -> PackedFloat32Array:
				return S.lp(x, minf(f * 14.0, 7000.0)))
			S.env(blat, [Vector2(0, 0), Vector2(0.04, 1.0), Vector2(0.28, 0.0)])
			S.add(b, blat, 0.45)
			_adsr(b, 0.05, dur, rel, 0.8)
		"horn":  # french horn: dark, round, slower attack
			var rel := 0.4
			var cut := minf(f * 3.2, 1500.0)
			b = _layer(dur + rel, S.Wave.SAW, f, [-0.0025, 0.003], func(x: PackedFloat32Array) -> PackedFloat32Array:
				return S.lp(S.lp(x, cut), cut * 1.3))
			S.add(b, S.periodic(dur + rel, S.Wave.SINE, f, Callable()), 0.4)
			_adsr(b, 0.1, dur, rel, 0.85)
		"low_brass":  # trombones / tubas: weighty, growl on the attack
			var rel := 0.35
			var cut := minf(f * 5.0, 1200.0)
			b = _layer(dur + rel, S.Wave.SAW, f, [-0.004, 0.004], func(x: PackedFloat32Array) -> PackedFloat32Array:
				return S.lp(S.lp(x, cut), cut * 1.2))
			var growl := S.periodic(dur + rel, S.Wave.SQUARE, f, func(x: PackedFloat32Array) -> PackedFloat32Array:
				return S.lp(x, 1800.0))
			S.env(growl, [Vector2(0, 0), Vector2(0.03, 1.0), Vector2(0.35, 0.15), Vector2(dur + rel, 0.0)])
			S.add(b, growl, 0.35)
			S.add(b, S.periodic(dur + rel, S.Wave.SINE, f * 0.5, Callable()), 0.35)
			_adsr(b, 0.06, dur, rel, 0.8)
		"flute":
			var rel := 0.25
			b = S.periodic(dur + rel, S.Wave.SINE, f, Callable())
			S.add(b, S.periodic(dur + rel, S.Wave.TRIANGLE, f * 1.002, Callable()), 0.25)
			S.add(b, S.periodic(dur + rel, S.Wave.SINE, f * 2.0, Callable()), 0.08)
			var breath := S.bp(S.noise(dur + rel, r), f * 2.0, 3.0)
			S.env(breath, [Vector2(0, 0), Vector2(0.05, 1.0), Vector2(0.25, 0.25), Vector2(dur + rel, 0.0)])
			S.add(b, breath, 0.25)
			_adsr(b, 0.08, dur, rel, 0.85)
		"fiddle":  # bowed solo string: body resonances, a little rosin noise
			var rel := 0.25
			b = _layer(dur + rel, S.Wave.SAW, f, [-0.004, 0.0045], _formant([480.0, 1150.0, 2800.0], [1.0, 0.7, 0.35], 2.5, 6000.0))
			var rosin := S.hp(S.noise(dur + rel, r), 2500.0)
			S.env(rosin, [Vector2(0, 0), Vector2(0.04, 1.0), Vector2(0.2, 0.15), Vector2(dur + rel, 0.0)])
			S.add(b, rosin, 0.05)
			_adsr(b, 0.12, dur, rel, 0.85)
		"reed":  # oboe / duduk: nasal double reed
			var rel := 0.2
			b = _layer(dur + rel, S.Wave.SQUARE, f, [-0.003, 0.003], _formant([700.0, 1150.0, 2900.0], [1.0, 0.6, 0.25], 3.5, 5000.0))
			_adsr(b, 0.07, dur, rel, 0.85)
		"clarinet":  # low woodwind: hollow square, dark
			var rel := 0.2
			b = _layer(dur + rel, S.Wave.SQUARE, f, [-0.002, 0.002], func(x: PackedFloat32Array) -> PackedFloat32Array:
				return S.lp(S.lp(x, minf(f * 4.0, 1600.0)), 2400.0))
			_adsr(b, 0.09, dur, rel, 0.8)
		"voice":  # solo voice / boys' choir on "oo"
			var rel := 0.5
			b = _layer(dur + rel, S.Wave.SAW, f, [-0.006, 0.0, 0.006], _formant([330.0, 850.0, 2500.0], [1.0, 0.45, 0.15], 5.0, 3500.0))
			_adsr(b, 0.3, dur, rel, 0.9)
		"choir_ah":  # choir note on "ah"
			var rel := 0.8
			b = _layer(dur + rel, S.Wave.SAW, f, [-0.008, -0.002, 0.004, 0.009], _formant([700.0, 1220.0, 2600.0], [1.0, 0.5, 0.25], 5.0, 3000.0))
			_adsr(b, 0.5, dur, rel, 0.9, 0.5)
		"choir_oh":  # low men's chant on "oh"
			var rel := 0.6
			b = _layer(dur + rel, S.Wave.SAW, f, [-0.007, 0.0, 0.007], _formant([450.0, 800.0, 2830.0], [1.0, 0.55, 0.12], 5.0, 2600.0))
			_adsr(b, 0.25, dur, rel, 0.9, 0.4)
		"choir":  # pad version of choir_ah (chords)
			note(out, r, "choir_ah", midi, at, dur, gain)
			return
		"organ":  # pipe organ: drawbar sines, chiff on the attack
			var rel := 0.25
			b = S.make(dur + rel)
			var h := [[0.5, 0.45], [1.0, 1.0], [2.0, 0.55], [3.0, 0.3], [4.0, 0.28], [6.0, 0.12], [8.0, 0.08]]
			for p: Array in h:
				if f * float(p[0]) < S.SR * 0.42:
					S.add(b, S.periodic(dur + rel, S.Wave.SINE, f * float(p[0]) * (1.0 + 0.0008 * float(p[0])), Callable()), float(p[1]) * 0.45)
			var chiff := S.bp(S.noise(0.12, r), f * 3.0, 2.0)
			S.decay(chiff, 0.005, 0.03)
			S.add(b, chiff, 0.12)
			_adsr(b, 0.04, dur, rel, 0.95, 0.1)
		"strings":  # string section pad
			var rel := 1.2
			var cut := minf(f * 4.0, 2400.0)
			b = _layer(dur + rel, S.Wave.SAW, f, [-0.006, -0.002, 0.003, 0.007], func(x: PackedFloat32Array) -> PackedFloat32Array:
				return S.lp(S.lp(x, cut), cut * 1.5))
			_adsr(b, minf(0.6, dur * 0.4), dur, rel, 0.9, 0.4)
		"warm":  # soft synth/strings pad for calm music
			var rel := 1.6
			var cut := minf(f * 2.5, 1200.0)
			b = _layer(dur + rel, S.Wave.TRIANGLE, f, [-0.005, 0.005], func(x: PackedFloat32Array) -> PackedFloat32Array:
				return S.lp(x, cut))
			S.add(b, _layer(dur + rel, S.Wave.SAW, f, [-0.003, 0.004], func(x: PackedFloat32Array) -> PackedFloat32Array:
				return S.lp(S.lp(x, cut * 0.8), cut)), 0.4)
			_adsr(b, minf(1.4, dur * 0.4), dur, rel, 0.9, 0.6)
		"glass_pad":  # shimmering sine pad with an octave above
			var rel := 2.0
			b = _layer(dur + rel, S.Wave.SINE, f, [-0.003, 0.003], Callable())
			S.add(b, _layer(dur + rel, S.Wave.SINE, f * 2.0, [-0.002, 0.004], Callable()), 0.3)
			S.add(b, S.periodic(dur + rel, S.Wave.TRIANGLE, f * 3.0, Callable()), 0.06)
			_adsr(b, minf(1.5, dur * 0.4), dur, rel, 0.9, 0.6)
		"cello":  # bowed low strings
			var rel := 0.3
			var cut := minf(f * 6.0, 1800.0)
			b = _layer(dur + rel, S.Wave.SAW, f, [-0.003, 0.003], func(x: PackedFloat32Array) -> PackedFloat32Array:
				return S.lp(S.lp(x, cut), cut * 1.4))
			_adsr(b, minf(0.12, dur * 0.3), dur, rel, 0.85, 0.15)
		"spicc":  # short bowed strings (ostinati): bite then decay
			var sec := maxf(dur, 0.12) + 0.12
			var cut := minf(f * 7.0, 2600.0)
			b = _layer(sec, S.Wave.SAW, f, [-0.003, 0.004], func(x: PackedFloat32Array) -> PackedFloat32Array:
				return S.lp(S.lp(x, cut), cut * 1.4))
			S.env(b, [Vector2(0, 0), Vector2(0.008, 1.0), Vector2(0.06, 0.6), Vector2(sec - 0.04, 0.3), Vector2(sec, 0.0)])
		"pizz":  # pizzicato
			b = S.periodic(0.6, S.Wave.TRIANGLE, f, Callable())
			S.add(b, S.periodic(0.6, S.Wave.SAW, f, func(x: PackedFloat32Array) -> PackedFloat32Array: return S.lp(x, f * 4.0)), 0.5)
			S.decay(b, 0.002, 0.12)
		"bass":  # plucked/picked low bass
			var sec := maxf(dur, 0.2) + 0.15
			b = S.periodic(sec, S.Wave.SAW, f, func(x: PackedFloat32Array) -> PackedFloat32Array: return S.lp(S.lp(x, 520.0), 700.0))
			S.add(b, S.periodic(sec, S.Wave.SINE, f, Callable()), 0.8)
			S.env(b, [Vector2(0, 0), Vector2(0.006, 1.0), Vector2(0.15, 0.7), Vector2(sec - 0.08, 0.5), Vector2(sec, 0.0)])
		"sub":  # deep sine bass
			var rel := 0.5
			b = S.periodic(dur + rel, S.Wave.SINE, f, Callable())
			S.add(b, S.periodic(dur + rel, S.Wave.SINE, f * 2.0, Callable()), 0.15)
			_adsr(b, 0.08, dur, rel, 0.9)
		"harp":
			var sec := clampf(dur * 1.5 + 0.5, 0.8, 2.6)
			b = S.periodic(sec, S.Wave.TRIANGLE, f, Callable())
			S.add(b, S.periodic(sec, S.Wave.SINE, f * 2.0, Callable()), 0.2)
			var pl := S.periodic(0.25, S.Wave.SAW, f, func(x: PackedFloat32Array) -> PackedFloat32Array: return S.lp(x, minf(f * 8.0, 6000.0)))
			S.decay(pl, 0.001, 0.04)
			S.add(b, pl, 0.4)
			S.decay(b, 0.002, sec * 0.27)
		"lute":  # oud / lute: brighter, quicker decay
			var sec := 1.4
			b = S.periodic(sec, S.Wave.SAW, f, func(x: PackedFloat32Array) -> PackedFloat32Array:
				return S.lp(S.peq(x, 1200.0, 6.0, 1.5), minf(f * 10.0, 5000.0)))
			S.add(b, S.periodic(sec, S.Wave.TRIANGLE, f, Callable()), 0.6)
			S.env(b, [Vector2(0, 0), Vector2(0.003, 1.0), Vector2(0.08, 0.55), Vector2(sec, 0.0)])
			S.decay(b, 0.0, 0.35)
		"celesta":  # music box / celesta
			b = S.bell(1.2, f, [1.0, 3.0, 4.07, 6.1], [0.7, 0.15, 0.1, 0.03], [0.4, 0.2, 0.1, 0.05])
		"glass":  # crystal glass / glockenspiel
			b = S.bell(3.0, f, [1.0, 2.0, 2.99, 4.2, 5.43], [0.6, 0.25, 0.12, 0.06, 0.03], [1.2, 0.6, 0.4, 0.2, 0.1])
		"bell":  # church / tolling bell (minor-third hum)
			b = S.bell(5.0, f, [0.5, 1.0, 1.19, 1.5, 2.0, 2.52, 3.0], [0.35, 0.6, 0.3, 0.2, 0.3, 0.12, 0.08],
				[2.5, 1.8, 1.2, 1.0, 0.8, 0.5, 0.3])
		"ship_bell":
			b = S.bell(2.5, f, [1.0, 2.0, 2.4, 3.02, 4.1], [0.6, 0.3, 0.2, 0.12, 0.06], [1.0, 0.6, 0.4, 0.25, 0.15])
		"clang":  # anvil / forge hammer
			b = S.bell(0.9, f, [1.0, 2.32, 4.25, 6.63, 9.38], [0.5, 0.4, 0.3, 0.2, 0.1], [0.25, 0.18, 0.12, 0.08, 0.05])
			var hit := S.hp(S.noise(0.03, r), 3000.0)
			S.decay(hit, 0.0005, 0.006)
			S.add(b, hit, 0.6)
		"gong":
			b = S.bell(5.0, f, [1.0, 1.48, 2.03, 2.71, 3.6, 4.4], [0.6, 0.35, 0.3, 0.2, 0.12, 0.06], [3.0, 2.2, 1.6, 1.0, 0.7, 0.4])
			S.env(b, [Vector2(0, 0), Vector2(0.15, 1.0), Vector2(5.0, 1.0)])
		"taiko":  # big war drum: pitch drop plus skin
			var l := 0.9
			b = S.osc(l, S.Wave.SINE, [Vector2(0, f * 1.8), Vector2(0.06, f), Vector2(l, f * 0.8)])
			S.decay(b, 0.002, 0.26)
			var skin := S.lp(S.decay(S.noise(0.15, r), 0.001, 0.025), 1100.0)
			S.add(b, skin, 0.55)
		"tom":
			var l := 0.5
			b = S.osc(l, S.Wave.SINE, [Vector2(0, f * 1.5), Vector2(0.04, f), Vector2(l, f * 0.9)])
			S.decay(b, 0.002, 0.13)
			S.add(b, S.lp(S.decay(S.noise(0.08, r), 0.0005, 0.015), 1800.0), 0.4)
		"timp":  # timpani: tuned, long ring
			var l := 1.8
			b = S.osc(l, S.Wave.SINE, [Vector2(0, f * 1.04), Vector2(0.1, f), Vector2(l, f * 0.995)])
			S.add(b, S.osc(l, S.Wave.SINE, [Vector2(0, f * 1.51), Vector2(l, f * 1.5)]), 0.3)
			S.decay(b, 0.003, 0.55)
			S.add(b, S.lp(S.decay(S.noise(0.1, r), 0.001, 0.02), 600.0), 0.5)
		"kick":
			var l := 0.4
			b = S.osc(l, S.Wave.SINE, [Vector2(0, 150.0), Vector2(0.05, 55.0), Vector2(l, 45.0)])
			S.decay(b, 0.001, 0.12)
		"snare":
			var l := 0.25
			b = S.bp(S.noise(l, r), 2200.0, 0.8)
			S.decay(b, 0.001, 0.06)
			var body := S.osc(l, S.Wave.TRIANGLE, [Vector2(0, 240.0), Vector2(l, 170.0)])
			S.decay(body, 0.001, 0.04)
			S.add(b, body, 0.6)
		"hat":
			b = S.hp(S.noise(0.08, r), 7000.0)
			S.decay(b, 0.0005, 0.015)
		"shaker":
			b = S.bp(S.noise(0.12, r), 5000.0, 1.0)
			S.env(b, [Vector2(0, 0), Vector2(0.03, 1.0), Vector2(0.12, 0.0)])
		"frame":  # frame drum / bodhran: low thump and a slap
			var l := 0.5
			b = S.osc(l, S.Wave.SINE, [Vector2(0, 150.0), Vector2(0.03, 92.0), Vector2(l, 80.0)])
			S.decay(b, 0.001, 0.14)
			var slap := S.bp(S.noise(0.06, r), 900.0, 1.2)
			S.decay(slap, 0.0005, 0.018)
			S.add(b, slap, 0.5)
		"tick":  # clock tick / bone click
			b = S.hp(S.noise(0.03, r), 3500.0)
			S.decay(b, 0.0003, 0.004)
		"swell":  # cymbal / wave swell rising into the next downbeat
			b = S.hp(S.noise(dur, r), 1500.0)
			S.lp(b, 7000.0)
			S.env(b, [Vector2(0, 0), Vector2(dur * 0.6, 0.25), Vector2(dur * 0.95, 1.0), Vector2(dur, 0.0)])
		"wave":  # ocean wash: low-passed noise rising and falling
			b = S.lp(S.lp(S.noise(dur, r), 700.0), 900.0)
			S.env(b, [Vector2(0, 0), Vector2(dur * 0.4, 1.0), Vector2(dur, 0.0)])
		_:
			push_error("Unknown instrument %s" % inst)
			return
	S.add(out, b, gain, int(at * S.SR), true)


## A pitch glide (whale call, void moan): saw through a vowel, from one note to another.
static func glide(out: PackedFloat32Array, from_midi: float, to_midi: float, at: float, dur: float, gain: float, vowel := true) -> void:
	var b := S.osc(dur, S.Wave.SAW, [Vector2(0, hz(from_midi)), Vector2(dur * 0.3, hz(from_midi)), Vector2(dur, hz(to_midi))])
	if vowel:
		b = S.lp(S.formants(b, [400.0, 900.0, 2400.0], [1.0, 0.4, 0.1], 4.0), 2500.0)
	else:
		S.lp(S.lp(b, 900.0), 1200.0)
	S.env(b, [Vector2(0, 0), Vector2(dur * 0.35, 1.0), Vector2(dur * 0.7, 0.8), Vector2(dur, 0.0)])
	S.add(out, b, gain, int(at * S.SR), true)


## Drone that loops without a seam: block lengths divide the loop.
static func drone(out: PackedFloat32Array, midi: int, gain: float, wave := S.Wave.SAW, cutoff := 500.0, fifth := 0.4) -> void:
	var dur := S.seconds(out.size())
	var shape := func(x: PackedFloat32Array) -> PackedFloat32Array: return S.lp(S.lp(x, cutoff), cutoff * 1.4)
	var d := S.periodic(dur, wave, hz(midi), shape, out.size())
	S.add(d, S.periodic(dur, wave, hz(midi + 7), shape, out.size()), fifth)
	S.add(d, S.periodic(dur, S.Wave.SINE, hz(midi - 12), Callable(), out.size()), 0.6)
	S.add(out, d, gain)


## Hall reverb over the loop (seamless). `wet` 0..1.
static func hall(b: PackedFloat32Array, room := 0.82, damp := 0.4, wet := 0.3) -> void:
	var processed := S.process_loop(b, func(x: PackedFloat32Array) -> PackedFloat32Array:
		return S.reverb(x, room, damp, wet))
	for i in b.size():
		b[i] = processed[i]


static func echo(b: PackedFloat32Array, delay: float, feedback: float, wet: float) -> void:
	var processed := S.process_loop(b, func(x: PackedFloat32Array) -> PackedFloat32Array:
		return S.echo(x, delay, feedback, wet, 0.45))
	for i in b.size():
		b[i] = processed[i]
