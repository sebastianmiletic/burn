class_name MusicLibrary
extends RefCounted
## The adaptive score: one loopable stem per game state, rendered offline.
## Every event writes with wrap-around so note tails flow over the loop point,
## and global effects run through Synth.process_loop, so the loops are
## seamless by construction.
##
## States: the original set (menu, explore = the plains, night, cave, boss =
## generic fight, hell = the Lake of Fire, victory), one calm track per biome
## ("biome_*") and one fight per boss ("boss_<kind>", see Boss.music_state()).
## Unknown names resolve to a sensible fallback (resolve()), never silence.
## The newer tracks are scored with MusicKit (instruments + note sequencer).

const S := preload("res://audio/synth.gd")
const K := preload("res://audio/music_kit.gd")

const BASE_STATES := ["menu", "explore", "night", "cave", "boss", "hell", "victory"]
const BOSS_STATES := ["boss_warden", "boss_mountain_king", "boss_dragon", "boss_cerberus", "boss_hades",
	"boss_broodmother", "boss_bog_hag", "boss_leviathan", "boss_kraken", "boss_charybdis", "boss_ryft_sentinel",
	"boss_void_sovereign"]
const BIOME_STATES := ["biome_forest", "biome_peaks", "biome_tundra", "biome_marsh", "biome_wastes", "biome_fjord",
	"biome_sea", "biome_deep", "biome_asphodel", "biome_tartarus", "biome_ryft", "biome_ogygia"]
const STATES := BASE_STATES + BOSS_STATES + BIOME_STATES

## Scored tracks: [beats per minute, beats in the loop].
const TEMPO := {
	"boss_warden": [100.0, 32], "boss_mountain_king": [90.0, 32], "boss_dragon": [112.0, 32],
	"boss_cerberus": [140.0, 64], "boss_hades": [76.0, 32], "boss_broodmother": [108.0, 32],
	"boss_bog_hag": [180.0, 72], "boss_leviathan": [70.0, 32], "boss_kraken": [104.0, 32],
	"boss_charybdis": [120.0, 32], "boss_ryft_sentinel": [128.0, 32], "boss_void_sovereign": [72.0, 32],
	"biome_forest": [84.0, 32], "biome_peaks": [66.0, 32], "biome_tundra": [60.0, 24], "biome_marsh": [64.0, 24],
	"biome_wastes": [76.0, 32], "biome_fjord": [80.0, 32], "biome_sea": [72.0, 32], "biome_deep": [50.0, 20],
	"biome_asphodel": [60.0, 24], "biome_tartarus": [56.0, 24], "biome_ryft": [80.0, 32], "biome_ogygia": [88.0, 32],
}

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


## The state actually played for a request: known states as they are, an
## unknown boss fight -> the generic fight, an unknown biome -> the plains.
## "" for anything else (silence).
static func resolve(state: String) -> String:
	if state in STATES:
		return state
	if state.begins_with("boss"):
		return "boss"
	if state.begins_with("biome"):
		return "explore"
	return ""


static func is_fight(state: String) -> bool:
	return state.begins_with("boss")


static func beat_of(state: String) -> float:
	return 60.0 / float(TEMPO[state][0])


static func length_of(state: String) -> float:
	if TEMPO.has(state):
		return beat_of(state) * float(TEMPO[state][1])
	return 16.0 if state in ["boss", "victory"] else 24.0


static func build(state: String) -> PackedFloat32Array:
	state = resolve(state)
	if state == "":
		state = "explore"
	var r := S.rng(hash(state) + 2026)
	var b := S.make(length_of(state))
	if TEMPO.has(state):
		var bt := beat_of(state)
		match state:
			"boss_warden": _boss_warden(b, r, bt)
			"boss_mountain_king": _boss_mountain_king(b, r, bt)
			"boss_dragon": _boss_dragon(b, r, bt)
			"boss_cerberus": _boss_cerberus(b, r, bt)
			"boss_hades": _boss_hades(b, r, bt)
			"boss_broodmother": _boss_broodmother(b, r, bt)
			"boss_bog_hag": _boss_bog_hag(b, r, bt)
			"boss_leviathan": _boss_leviathan(b, r, bt)
			"boss_kraken": _boss_kraken(b, r, bt)
			"boss_charybdis": _boss_charybdis(b, r, bt)
			"boss_ryft_sentinel": _boss_ryft_sentinel(b, r, bt)
			"boss_void_sovereign": _boss_void_sovereign(b, r, bt)
			"biome_forest": _biome_forest(b, r, bt)
			"biome_peaks": _biome_peaks(b, r, bt)
			"biome_tundra": _biome_tundra(b, r, bt)
			"biome_marsh": _biome_marsh(b, r, bt)
			"biome_wastes": _biome_wastes(b, r, bt)
			"biome_fjord": _biome_fjord(b, r, bt)
			"biome_sea": _biome_sea(b, r, bt)
			"biome_deep": _biome_deep(b, r, bt)
			"biome_asphodel": _biome_asphodel(b, r, bt)
			"biome_tartarus": _biome_tartarus(b, r, bt)
			"biome_ryft": _biome_ryft(b, r, bt)
			"biome_ogygia": _biome_ogygia(b, r, bt)
		b = S.process_loop(b, func(x: PackedFloat32Array) -> PackedFloat32Array: return S.dc_block(x))
		_seal_seam(b)
		S.normalize(b, 0.8)
		return S.soft_clip(b, 1.2)
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


## Bends the last few ms of a loop toward the sample before its start, so a
## hit or swell left ringing at the end never clicks at the wrap.
static func _seal_seam(b: PackedFloat32Array, sec := 0.008) -> void:
	var n := mini(S.samples(sec), b.size() - 2)
	if n <= 0:
		return
	var last := b.size() - 1
	var d := (2.0 * b[0] - b[1]) - b[last]
	for k in n:
		b[last - n + 1 + k] += d * float(k + 1) / n


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


# --- Scored tracks (MusicKit) ---------------------------------------------------------

static func _cs(list: Array) -> Array:
	var out := []
	for n: String in list:
		out.append(K.ch(n))
	return out


## Ostinato: one note per step at each bar's root plus the step's interval.
## `shapes` is either one interval list for every bar or one list per bar.
static func _ost(b: PackedFloat32Array, r: RandomNumberGenerator, inst: String, roots: Array, shapes: Array,
		bar_beats: float, bt: float, gain: float, legato := 0.85, start_bar := 0) -> void:
	for bar in roots.size():
		var shape: Array = shapes[bar] if shapes[0] is Array else shapes
		var step := bar_beats / shape.size()
		for s in shape.size():
			var accent := 1.0 if s == 0 else (0.8 if s % 2 == 0 else 0.62)
			K.note(b, r, inst, K.midi_of(roots[bar]) + int(shape[s]), ((start_bar + bar) * bar_beats + s * step) * bt,
				step * bt * legato, gain * accent)


## Pattern drums whose pitch follows each bar's root (timpani).
static func _tuned(b: PackedFloat32Array, r: RandomNumberGenerator, inst: String, pattern: String, roots: Array,
		bar_sec: float, gain: float) -> void:
	for bar in roots.size():
		K.drums(b, r, inst, pattern, 1, bar_sec, gain, K.midi_of(roots[bar]), bar)


# Bosses ----------------------------------------------------------------------------------

## The Warden: a funeral march in D minor for a dead knight. Tolling bell,
## marching snare, cello ostinato; the horn's grim theme passes to the brass.
static func _boss_warden(b: PackedFloat32Array, r: RandomNumberGenerator, bt: float) -> void:
	var bar := bt * 4.0
	var prog := _cs(["D3 A3 D4 F4", "G2 D3 G3 Bb3", "Bb2 F3 Bb3 D4", "A2 E3 A3 C#4",
		"D3 A3 D4 F4", "G2 D3 G3 Bb3", "F2 C3 F3 A3", "A2 E3 A3 C#4"])
	K.chords(b, r, "strings", prog, bar, 0.34)
	K.chords(b, r, "choir_oh", prog, bar, 0.16, -12)
	var roots := ["D2", "G1", "Bb1", "A1", "D2", "G1", "F1", "A1"]
	_ost(b, r, "spicc", roots, [12, 12, 24, 12, 19, 12, 24, 19], 4.0, bt, 0.2)
	_tuned(b, r, "timp", "X.......", roots, bar, 0.45)
	K.drums(b, r, "taiko", "X..x.Xx.", 8, bar, 0.62, 34)
	K.drums(b, r, "snare", "....x.......xoxo", 8, bar, 0.24)
	K.note(b, r, "bell", 50, 0.0, 4.0, 0.22)
	K.note(b, r, "bell", 50, bar * 4.0, 4.0, 0.18)
	K.seq(b, r, "horn", "D4:1.5 E4:.5 F4:1 A4:1 | G4:1.5 F4:.5 E4:2 | F4:1.5 G4:.5 A4:1 D5:1 | C#5:3 A4:1", 0.0, bt, 0.34)
	var climax := "D5:1.5 C5:.5 Bb4:1 A4:1 | G4:1.5 A4:.5 Bb4:2 | A4:1 G4:1 F4:1 E4:1 | E4:2 C#4:2"
	K.seq(b, r, "brass", climax, 16.0, bt, 0.3)
	K.seq(b, r, "horn", climax, 16.0, bt, 0.2, -12)
	K.hall(b, 0.8, 0.45, 0.28)


## The Mountain King: a stomping riff in E phrygian under a dwarven chant,
## forge anvils on the off-beats and a war drum on every step.
static func _boss_mountain_king(b: PackedFloat32Array, r: RandomNumberGenerator, bt: float) -> void:
	var bar := bt * 4.0
	var prog := _cs(["E2 B2 E3 G3", "E2 B2 E3 G3", "C2 G2 C3 E3", "B1 F#2 B2 D#3",
		"E2 B2 E3 G3", "A1 E2 A2 C3", "F2 C3 F3 A3", "B1 F#2 B2 D#3"])
	K.chords(b, r, "strings", prog, bar, 0.22, 12)
	var roots := ["E2", "E2", "C2", "B1", "E2", "A1", "F2", "B1"]
	var minor := [0, 0, 3, 0, 5, 3, 7, 5]
	var major := [0, 0, 4, 0, 5, 4, 7, 5]
	var shapes := [minor, minor, major, major, minor, minor, major, major]
	_ost(b, r, "low_brass", roots, shapes, 4.0, bt, 0.26, 0.8)
	_ost(b, r, "bass", roots, shapes, 4.0, bt, 0.2, 0.7)
	K.drums(b, r, "taiko", "X...X.x.", 8, bar, 0.62, 31)
	K.drums(b, r, "tom", "..x...x.", 8, bar, 0.25, 45)
	K.drums(b, r, "clang", "..x...x.", 8, bar, 0.1, 88)
	var chant := "E3:2 G3:2 | F#3:3 E3:1 | G3:2 E3:2 | D#3:4 | E3:2 B3:2 | A3:3 G3:1 | F3:2 A3:2 | B3:2 D#3:2"
	K.seq(b, r, "choir_oh", chant, 0.0, bt, 0.3)
	K.seq(b, r, "choir_oh", chant, 0.0, bt, 0.16, 12)
	K.seq(b, r, "horn", "E4:2 B4:2 | A4:3 G4:1 | F4:2 A4:2 | B4:2 D#4:2", 16.0, bt, 0.24)
	K.hall(b, 0.84, 0.5, 0.3)


## Ashvane: soaring brass over war drums and racing strings in C minor.
static func _boss_dragon(b: PackedFloat32Array, r: RandomNumberGenerator, bt: float) -> void:
	var bar := bt * 4.0
	var prog := _cs(["C3 G3 C4 Eb4", "Ab2 Eb3 Ab3 C4", "Eb3 Bb3 Eb4 G4", "Bb2 F3 Bb3 D4",
		"C3 G3 C4 Eb4", "Ab2 Eb3 Ab3 C4", "F2 C3 F3 Ab3", "G2 D3 G3 B3"])
	K.chords(b, r, "strings", prog, bar, 0.22)
	K.chords(b, r, "choir", prog, bar, 0.14)
	K.arp(b, r, "spicc", prog, 4.0, bt, [0, 2, 1, 2, 3, 2, 1, 2], 0.25, 0.16, -12, 0.25)
	var roots := ["C2", "Ab1", "Eb2", "Bb1", "C2", "Ab1", "F1", "G1"]
	_tuned(b, r, "timp", "X.....x.", roots, bar, 0.4)
	K.drums(b, r, "taiko", "X..x..X.X.x.x..o", 8, bar, 0.68, 33)
	K.drums(b, r, "tom", "......x.....x.xx", 8, bar, 0.22, 50)
	K.drums(b, r, "snare", "....X.......X...", 8, bar, 0.14)
	K.note(b, r, "swell", 60, bar * 4.0 - bt * 2.0, bt * 2.0, 0.12)
	K.note(b, r, "swell", 60, bar * 8.0 - bt * 2.0, bt * 2.0, 0.14)
	K.seq(b, r, "brass", "C5:1.5 G4:.5 C5:1 D5:1 | Eb5:3 D5:.5 C5:.5 | Bb4:1.5 G4:.5 Eb5:2 | D5:3 r:1 | "
		+ "C5:1.5 G4:.5 C5:1 Eb5:1 | Ab5:3 G5:.5 F5:.5 | F5:1.5 Eb5:.5 D5:1 C5:1 | B4:2 D5:2", 0.0, bt, 0.32)
	K.seq(b, r, "horn", "Eb4:4 | Eb4:2 C4:2 | Bb3:4 | F4:4 | G4:4 | Ab4:2 Eb4:2 | F4:2 Ab4:2 | G4:2 F4:2", 0.0, bt, 0.2)
	K.hall(b, 0.78, 0.4, 0.24)


## Cerberus: savage A phrygian, three-note snarls, drums at full gallop.
static func _boss_cerberus(b: PackedFloat32Array, r: RandomNumberGenerator, bt: float) -> void:
	var bar := bt * 4.0
	var half := ["A2 E3 A3 C4", "Bb2 F3 Bb3 D4", "A2 E3 A3 C4", "G2 D3 G3 B3",
		"F2 C3 F3 A3", "E2 B2 E3 G#3", "A2 E3 A3 C4", "E2 B2 E3 G#3"]
	var prog := _cs(half + half)
	K.chords(b, r, "strings", prog, bar, 0.2)
	K.chords(b, r, "choir", prog, bar, 0.12)
	var roots := ["A1", "Bb1", "A1", "G1", "F1", "E1", "A1", "E1"]
	_ost(b, r, "bass", roots + roots, [0, 0, 12, 0, 0, 12, 0, 10], 4.0, bt, 0.28, 0.8)
	_ost(b, r, "low_brass", roots + roots, [12, 0, 0, 0], 4.0, bt, 0.18, 0.5)
	K.drums(b, r, "taiko", "X.x.X.x.X.x.XxXx", 16, bar, 0.5, 35)
	K.drums(b, r, "snare", "....X.......X..X", 16, bar, 0.16)
	K.drums(b, r, "hat", "x.x.x.x.x.x.x.x.", 16, bar, 0.1)
	K.drums(b, r, "tom", "........x.x.xxxx", 1, bar, 0.3, 48, 7)
	K.drums(b, r, "tom", "........x.x.xxxx", 1, bar, 0.3, 48, 15)
	var lead := "A4:.5 Bb4:.5 A4:1 E4:1 r:1 | D5:.5 C5:.5 Bb4:1 F4:2 | A4:.5 Bb4:.5 A4:1 C5:.5 B4:.5 A4:1 | G4:1 B4:1 D5:2 | " \
		+ "C5:1 A4:1 F4:1 C5:1 | B4:1.5 G#4:.5 E4:2 | A4:.5 C5:.5 E5:1 D5:.5 C5:.5 B4:1 | G#4:2 E4:2"
	K.seq(b, r, "reed", lead, 0.0, bt, 0.28)
	K.seq(b, r, "brass", lead, 32.0, bt, 0.3)
	K.seq(b, r, "low_brass", lead, 32.0, bt, 0.16, -12)
	K.hall(b, 0.75, 0.4, 0.2)


## Hades: organ and a choir chanting the Dies irae in D minor; a funeral bell,
## timpani and low brass for the king of the dead.
static func _boss_hades(b: PackedFloat32Array, r: RandomNumberGenerator, bt: float) -> void:
	var bar := bt * 4.0
	var prog := _cs(["D3 A3 D4 F4", "G2 D3 G3 Bb3", "D3 A3 D4 F4", "A2 E3 A3 C#4",
		"Bb2 F3 Bb3 D4", "G2 D3 G3 Bb3", "Eb3 Bb3 Eb4 G4", "A2 E3 A3 C#4"])
	K.chords(b, r, "organ", prog, bar, 0.36)
	K.chords(b, r, "choir", prog, bar, 0.16)
	var roots := ["D2", "G1", "D2", "A1", "Bb1", "G1", "Eb2", "A1"]
	_ost(b, r, "organ", roots, [0, 12, 0, 12, 0, 12, 0, 12], 4.0, bt, 0.12, 0.9)
	_tuned(b, r, "timp", "X...x...", roots, bar, 0.42)
	K.drums(b, r, "taiko", "X.x.....", 8, bar, 0.36, 30)
	K.note(b, r, "bell", 50, 0.0, 4.0, 0.2)
	K.note(b, r, "bell", 45, bar * 4.0, 4.0, 0.16)
	var chant := "F4:1 E4:1 F4:1 D4:1 | E4:1 C4:1 D4:2 | F4:1 F4:1 G4:1 F4:1 | E4:1 D4:1 C#4:2 | " \
		+ "D4:1 F4:1 Bb4:2 | G4:1 Bb4:1 A4:2 | G4:1.5 F4:.5 Eb4:2 | E4:2 C#4:2"
	K.seq(b, r, "choir_ah", chant, 0.0, bt, 0.3, 0, 0.95)
	K.seq(b, r, "choir_oh", chant, 0.0, bt, 0.18, -12, 0.95)
	K.seq(b, r, "low_brass", "Bb2:4 | G2:4 | Eb2:4 | A2:4", 16.0, bt, 0.22)
	K.hall(b, 0.88, 0.45, 0.34)


## The Broodmother: a music box in C# minor over skittering chromatic
## pizzicato, clicking legs and a slow heartbeat.
static func _boss_broodmother(b: PackedFloat32Array, r: RandomNumberGenerator, bt: float) -> void:
	var bar := bt * 4.0
	var prog := _cs(["C#3 G#3 C#4 E4", "C#3 G#3 C#4 E4", "D3 A3 D4 F#4", "C#3 G#3 C#4 E4",
		"A2 E3 A3 C#4", "F#2 C#3 F#3 A3", "D3 A3 D4 F#4", "G#2 D#3 G#3 C4"])
	K.chords(b, r, "strings", prog, bar, 0.2)
	K.drone(b, 37, 0.06, S.Wave.SAW, 300.0, 0.0)
	var roots := ["C#3", "C#3", "D3", "C#3", "A2", "F#3", "D3", "G#2"]
	_ost(b, r, "pizz", roots, [0, 1, 0, 3, 0, 1, 4, 3, 0, 1, 0, 6, 7, 6, 4, 3], 4.0, bt, 0.15)
	K.drums(b, r, "kick", "X..x............", 8, bar, 0.62)
	K.drums(b, r, "tick", "..x..x.x..x.x..x", 8, bar, 0.22)
	K.seq(b, r, "celesta", "G#5:.5 A5:.5 G#5:.5 E5:.5 C#5:2 | E5:.5 D#5:.5 E5:.5 G#5:.5 C#6:2 | "
		+ "D5:.5 F#5:.5 A5:.5 F#5:.5 D5:2 | C#5:1 E5:1 G#4:2 | A4:.5 C#5:.5 E5:.5 A5:.5 G#5:2 | "
		+ "F#5:.5 E5:.5 C#5:.5 A4:.5 F#4:2 | D5:.5 F#5:.5 A5:.5 D6:.5 C#6:1 A5:1 | G#5:1 C5:1 D#5:1 G#4:1", 0.0, bt, 0.26)
	K.seq(b, r, "low_brass", "A2:2 r:2 | F#2:2 r:2 | D2:2 r:2 | G#2:2 G#2:2", 16.0, bt, 0.2)
	K.hall(b, 0.85, 0.5, 0.32)


## Old Mother Mire: an eerie fen jig in 6/8 (E aeolian); a detuned fiddle,
## lute, hurdy-gurdy drone, frame drum and a whispering choir.
static func _boss_bog_hag(b: PackedFloat32Array, r: RandomNumberGenerator, bt: float) -> void:
	var bar := bt * 6.0  # bt is an eighth note
	var prog := _cs(["E3 B3 E4 G4", "E3 B3 E4 G4", "D3 A3 D4 F#4", "E3 B3 E4 G4",
		"A2 E3 A3 C4", "E3 B3 E4 G4", "C3 G3 C4 E4", "D3 A3 D4 F#4",
		"E3 B3 E4 G4", "C3 G3 C4 E4", "B2 F#3 B3 D#4", "B2 F#3 B3 D#4"])
	K.chords(b, r, "voice", prog, bar, 0.12)
	K.drone(b, 40, 0.09, S.Wave.SAW, 700.0, 0.5)
	K.arp(b, r, "lute", prog, 6.0, bt, [0, 1, 2, 3, 2, 1], 1.0, 0.13, -12, 2.0, 0.08)
	K.drums(b, r, "frame", "X..x.x", 12, bar, 0.52)
	K.drums(b, r, "shaker", "..x..x", 12, bar, 0.06)
	var tune := "E5:3 G5:1 F#5:1 E5:1 | B4:3 D5:2 E5:1 | F#5:2 D5:1 A4:3 | E5:6 | A5:2 G5:1 E5:3 | B4:2 E5:1 G5:3 | " \
		+ "G5:2 E5:1 C5:3 | D5:2 F#5:1 A5:3 | B5:3 A5:1 G5:1 F#5:1 | E5:2 G5:1 C5:3 | B4:3 D#5:3 | F#5:3 B4:3"
	K.seq(b, r, "fiddle", tune, 0.0, bt, 0.24)
	K.seq(b, r, "reed", "A4:2 G4:1 E4:3 | B3:2 E4:1 G4:3 | G4:2 E4:1 C4:3 | D4:2 F#4:1 A4:3", 24.0, bt, 0.12)
	K.note(b, r, "glass", 88, bar * 3.0, 2.0, 0.08)
	K.note(b, r, "glass", 83, bar * 7.0 + bt * 3.0, 2.0, 0.07)
	K.hall(b, 0.86, 0.55, 0.32)


## The Leviathan: crushing F minor tides; contrabass brass, a gong and the
## deep drums under a choir, waves and whale calls.
static func _boss_leviathan(b: PackedFloat32Array, r: RandomNumberGenerator, bt: float) -> void:
	var bar := bt * 4.0
	var prog := _cs(["F2 C3 F3 Ab3", "Db2 Ab2 Db3 F3", "Bb1 F2 Bb2 Db3", "C2 G2 C3 E3",
		"F2 C3 F3 Ab3", "Db2 Ab2 Db3 F3", "Gb1 Db2 Gb2 Bb2", "C2 G2 C3 E3"])
	K.chords(b, r, "strings", prog, bar, 0.26, 12)
	K.chords(b, r, "choir_oh", prog, bar, 0.2, 12)
	var roots := ["F1", "Db1", "Bb0", "C1", "F1", "Db1", "Gb1", "C1"]
	_ost(b, r, "sub", roots, [12, 12], 4.0, bt, 0.3, 0.95)
	_tuned(b, r, "timp", "....x.x.", ["F2", "Db2", "Bb1", "C2", "F2", "Db2", "Gb1", "C2"], bar, 0.3)
	K.drums(b, r, "taiko", "X.....x.", 8, bar, 0.85, 28)
	K.note(b, r, "gong", 41, 0.0, 4.0, 0.22)
	K.note(b, r, "gong", 41, bar * 4.0, 4.0, 0.18)
	for i in 4:
		K.note(b, r, "wave", 40, bar * 2.0 * i + bt, bar * 1.8, 0.12)
	var theme := "F3:2 Ab3:1 C4:1 | Db4:3 C4:1 | Bb3:2 Db4:1 F4:1 | E4:4 | F4:2 G4:1 Ab4:1 | Ab4:2 F4:2 | Gb4:2 Bb3:1 Db4:1 | C4:4"
	K.seq(b, r, "low_brass", theme, 0.0, bt, 0.34)
	K.seq(b, r, "horn", "F4:2 G4:1 Ab4:1 | Ab4:2 F4:2 | Gb4:2 Bb3:1 Db4:1 | C4:4", 16.0, bt, 0.22, 12)
	K.glide(b, 50.0, 46.0, bar * 1.0 + bt * 2.0, 3.0, 0.06)
	K.glide(b, 53.0, 57.0, bar * 5.0 + bt * 2.0, 3.0, 0.05)
	K.hall(b, 0.88, 0.55, 0.34)


## The Kraken: a heaving minor shanty in G; swirling cellos (tentacles),
## a ship's bell and pounding toms.
static func _boss_kraken(b: PackedFloat32Array, r: RandomNumberGenerator, bt: float) -> void:
	var bar := bt * 4.0
	var prog := _cs(["G2 D3 G3 Bb3", "C3 G3 C4 Eb4", "Eb3 Bb3 Eb4 G4", "D3 A3 D4 F#4",
		"G2 D3 G3 Bb3", "Bb2 F3 Bb3 D4", "C3 G3 C4 Eb4", "D3 A3 D4 F#4"])
	K.chords(b, r, "strings", prog, bar, 0.2)
	K.chords(b, r, "choir", prog, bar, 0.12)
	K.arp(b, r, "spicc", prog, 4.0, bt, [0, 1, 2, 3, 2, 1], 1.0 / 3.0, 0.14, -12, 0.4)
	var roots := ["G1", "C2", "Eb2", "D2", "G1", "Bb1", "C2", "D2"]
	_ost(b, r, "bass", roots, [0, 0, 7, 0, 12, 0, 7, 0], 4.0, bt, 0.2, 0.7)
	K.drums(b, r, "taiko", "X..x..X.x..x.xx.", 8, bar, 0.68, 31)
	K.drums(b, r, "tom", "....x.......x..x", 8, bar, 0.22, 45)
	K.note(b, r, "ship_bell", 79, 0.0, 2.0, 0.12)
	K.note(b, r, "ship_bell", 79, bar * 4.0, 2.0, 0.1)
	K.seq(b, r, "brass", "G4:1 G4:.5 A4:.5 Bb4:1 D5:1 | C5:1 Bb4:.5 A4:.5 G4:2 | Eb5:1.5 D5:.5 C5:1 Bb4:1 | A4:3 r:1 | "
		+ "G4:1 Bb4:1 D5:1 G5:1 | F5:1.5 Eb5:.5 D5:2 | C5:1 Eb5:1 D5:1 C5:1 | D5:2 F#4:2", 0.0, bt, 0.3)
	K.seq(b, r, "low_brass", "G2:4 | Bb2:4 | C3:4 | D3:4", 16.0, bt, 0.22)
	K.note(b, r, "wave", 40, bar * 3.0, bar * 1.5, 0.1)
	K.note(b, r, "wave", 40, bar * 7.0, bar * 1.5, 0.1)
	K.hall(b, 0.82, 0.5, 0.28)


## Charybdis: a hypnotic whirlpool in A minor; harp swirls rising and falling,
## a 3+3+2 drum pulse, gong swells and a dark horn theme.
static func _boss_charybdis(b: PackedFloat32Array, r: RandomNumberGenerator, bt: float) -> void:
	var bar := bt * 4.0
	var prog := _cs(["A2 E3 A3 C4", "F2 C3 F3 A3", "D3 A3 D4 F4", "E2 B2 E3 G#3",
		"A2 E3 A3 C4", "F2 C3 F3 A3", "B2 F3 B3 D4", "E2 B2 E3 G#3"])
	K.chords(b, r, "choir", prog, bar, 0.2)
	K.chords(b, r, "strings", prog, bar, 0.16, -12)
	K.arp(b, r, "harp", prog, 4.0, bt, [0, 1, 2, 3, 4, 5, 6, 5], 0.5, 0.12, 0, 0.5)
	var roots := ["A1", "F1", "D2", "E1", "A1", "F1", "B1", "E1"]
	_ost(b, r, "sub", roots, [12, 12, 12, 12, 12, 12, 12, 12], 4.0, bt, 0.2, 0.6)
	K.drums(b, r, "taiko", "X..X..X.X..X..X.", 8, bar, 0.46, 33)
	K.drums(b, r, "shaker", "x.xx.xx.x.xx.xx.", 8, bar, 0.05)
	K.note(b, r, "gong", 45, 0.0, 4.0, 0.16)
	K.note(b, r, "swell", 60, bar * 4.0 - bt * 2.0, bt * 2.0, 0.12)
	K.note(b, r, "swell", 60, bar * 8.0 - bt * 2.0, bt * 2.0, 0.12)
	var theme := "A3:2 C4:1 E4:1 | F4:2 E4:1 C4:1 | D4:2 F4:1 A4:1 | G#4:4 | A4:2 B4:1 C5:1 | C5:2 A4:2 | B4:1 D5:1 F4:2 | E4:4"
	K.seq(b, r, "horn", theme, 0.0, bt, 0.32)
	K.seq(b, r, "low_brass", theme, 0.0, bt, 0.16, -12)
	K.hall(b, 0.85, 0.45, 0.3)


## The Prism Sentinel: a crystalline machine in E lydian; precise celesta
## arpeggios, a pulsing bass and a mechanical beat.
static func _boss_ryft_sentinel(b: PackedFloat32Array, r: RandomNumberGenerator, bt: float) -> void:
	var bar := bt * 4.0
	var prog := _cs(["E3 B3 E4 G#4", "E3 A#3 C#4 F#4", "C#3 G#3 C#4 E4", "B2 F#3 B3 D#4",
		"E3 B3 E4 G#4", "E3 A#3 C#4 F#4", "G#2 D#3 G#3 B3", "B2 F#3 B3 D#4"])
	K.chords(b, r, "glass_pad", prog, bar, 0.26)
	K.arp(b, r, "celesta", prog, 4.0, bt, [0, 1, 2, 3, 4, 3, 2, 1], 0.5, 0.1, 12, 0.5)
	var roots := ["E2", "E2", "C#2", "B1", "E2", "E2", "G#1", "B1"]
	_ost(b, r, "bass", roots, [0, 12, 0, 12, 0, 12, 7, 12], 4.0, bt, 0.24, 0.6)
	K.drums(b, r, "kick", "X.....X.X.......", 8, bar, 0.62)
	K.drums(b, r, "snare", "....X.......X...", 8, bar, 0.26)
	K.drums(b, r, "hat", "xxxxxxxxxxxxxxxx", 8, bar, 0.07)
	K.drums(b, r, "clang", "..x.......x.....", 8, bar, 0.05, 96)
	var lead := "B4:1.5 G#4:.5 E5:1 D#5:1 | C#5:1.5 A#4:.5 F#4:2 | G#4:1 C#5:1 E5:1 G#5:1 | F#5:3 D#5:1 | " \
		+ "E5:1.5 B4:.5 G#5:1 F#5:1 | A#5:1.5 G#5:.5 F#5:2 | D#5:1 G#5:1 B5:1 A#5:.5 G#5:.5 | F#5:4"
	K.seq(b, r, "horn", lead, 0.0, bt, 0.26, -12)
	K.seq(b, r, "glass", lead, 0.0, bt, 0.12)
	K.echo(b, bt * 0.75, 0.3, 0.2)
	K.hall(b, 0.8, 0.35, 0.22)


## The Void Sovereign: cosmic dread; tritone-related chords under a vast
## choir, a heartbeat, a distant clock and a lone voice.
static func _boss_void_sovereign(b: PackedFloat32Array, r: RandomNumberGenerator, bt: float) -> void:
	var bar := bt * 4.0
	var prog := _cs(["C3 G3 C4 Eb4", "F#2 C#3 F#3 A3", "C3 G3 C4 Eb4", "Ab2 C3 E3 Ab3",
		"C3 G3 C4 Eb4", "Db3 Ab3 Db4 F4", "B2 D3 F3 Ab3", "G2 B2 F3 Ab3"])
	K.chords(b, r, "choir", prog, bar, 0.34)
	K.chords(b, r, "strings", prog, bar, 0.18, -12)
	K.drone(b, 24, 0.12, S.Wave.SAW, 180.0, 0.0)
	_tuned(b, r, "timp", "X.......", ["C2", "F#1", "C2", "Ab1", "C2", "Db2", "B1", "G1"], bar, 0.38)
	K.drums(b, r, "kick", "X..x............", 8, bar, 0.5)
	K.drums(b, r, "tick", "x...x...x...x...", 8, bar, 0.1)
	K.note(b, r, "gong", 36, 0.0, 4.0, 0.24)
	K.note(b, r, "gong", 37, bar * 4.0, 4.0, 0.2)
	K.note(b, r, "swell", 60, bar * 4.0 - bt * 3.0, bt * 3.0, 0.1)
	K.seq(b, r, "voice", "C5:3 Db5:1 | C#5:2 A4:2 | C5:2 Eb5:1 D5:1 | E5:4 | G5:3 F5:1 | F5:2 Ab5:2 | F5:2 D5:2 | B4:4",
		0.0, bt, 0.26)
	K.seq(b, r, "low_brass", "C3:4 | C#3:4 | C3:4 | C3:4 | C3:4 | Db3:4 | B2:4 | G2:4", 0.0, bt, 0.16)
	K.glide(b, 60.0, 54.0, bar * 2.0, 4.0, 0.06)
	K.glide(b, 55.0, 61.0, bar * 6.0, 4.0, 0.05)
	K.echo(b, bt * 1.5, 0.35, 0.2)
	K.hall(b, 0.9, 0.5, 0.38)


# Biomes (calm) -------------------------------------------------------------------------

## Forests: a warm G mixolydian air for flute over a lute.
static func _biome_forest(b: PackedFloat32Array, r: RandomNumberGenerator, bt: float) -> void:
	var bar := bt * 4.0
	var prog := _cs(["G2 D3 G3 B3", "F2 C3 F3 A3", "C3 G3 C4 E4", "G2 D3 G3 B3",
		"E2 B2 E3 G3", "C3 G3 C4 E4", "D3 A3 D4 F#4", "G2 D3 G3 B3"])
	K.chords(b, r, "warm", prog, bar, 0.26)
	K.arp(b, r, "lute", prog, 4.0, bt, [0, 1, 2, 3, 2, 1, 2, 3], 0.5, 0.11, 0, 1.5, 0.1)
	K.seq(b, r, "flute", "D5:1.5 B4:.5 G4:1 A4:1 | C5:2 A4:1 F4:1 | E4:1.5 G4:.5 C5:2 | B4:3 r:1 | "
		+ "G4:1 B4:1 E5:1.5 D5:.5 | C5:1.5 B4:.5 A4:1 G4:1 | A4:1.5 F#4:.5 D4:1 A4:1 | G4:4", 0.0, bt, 0.2)
	K.drums(b, r, "frame", "X.......", 8, bar, 0.06)
	K.echo(b, bt * 0.75, 0.3, 0.2)
	K.hall(b, 0.75, 0.5, 0.2)


## Peaks and alps: open fifths and a horn call echoing off the mountains (D).
static func _biome_peaks(b: PackedFloat32Array, r: RandomNumberGenerator, bt: float) -> void:
	var bar := bt * 4.0
	var prog := _cs(["D2 A2 E3 F#3 A3", "D2 B2 E3 G#3", "B1 F#2 D3 F#3", "G1 D2 B2 D3",
		"D2 A2 E3 F#3 A3", "A1 E2 C#3 E3", "G1 D2 B2 D3", "A1 E2 C#3 E3"])
	K.chords(b, r, "strings", prog, bar, 0.26, 12)
	K.chords(b, r, "glass_pad", prog, bar, 0.07, 24)
	K.seq(b, r, "horn", "A4:1 D5:1 E5:2 | F#5:2 G#5:1 E5:1 | D5:3 B4:1 | B4:4 | A4:1 D5:1 F#5:2 | E5:3 C#5:1 | "
		+ "B4:1.5 D5:.5 G5:2 | A5:4", 0.0, bt, 0.22, -12)
	K.note(b, r, "timp", 38, 0.0, 1.0, 0.12)
	K.note(b, r, "timp", 33, bar * 4.0, 1.0, 0.1)
	K.echo(b, bt * 0.75, 0.42, 0.3)
	K.hall(b, 0.86, 0.4, 0.3)


## Tundra and the Rime Sea: cold, sparse glass over a still A minor.
static func _biome_tundra(b: PackedFloat32Array, r: RandomNumberGenerator, bt: float) -> void:
	var chord := bt * 6.0
	var prog := _cs(["A2 E3 B3 C4", "F2 C3 E3 A3", "C3 G3 D4 E4", "G2 D3 A3 B3"])
	K.chords(b, r, "glass_pad", prog, chord, 0.3)
	K.drone(b, 33, 0.06, S.Wave.TRIANGLE, 300.0, 0.3)
	K.seq(b, r, "glass", "E5:2 r:1 A5:1 G5:2 | r:2 C5:3 D5:1 | E5:3 r:1 G5:1 E5:1 | D5:4 r:2", 0.0, bt, 0.18)
	K.seq(b, r, "flute", "r:6 A4:6 | r:6 B4:6", 0.0, bt, 0.06)
	K.echo(b, bt * 1.5, 0.45, 0.3)
	K.hall(b, 0.9, 0.3, 0.36)


## Marshes: murky F# dorian; a low clarinet, drips of pizzicato and a still pad.
static func _biome_marsh(b: PackedFloat32Array, r: RandomNumberGenerator, bt: float) -> void:
	var bar := bt * 4.0
	var prog := _cs(["F#2 C#3 F#3 A3", "E2 B2 E3 G#3", "B1 F#2 B2 D#3", "F#2 C#3 F#3 A3", "D2 A2 C#3 F#3", "C#2 G#2 C#3 E3"])
	K.chords(b, r, "warm", prog, bar, 0.26)
	K.drone(b, 30, 0.06, S.Wave.SINE, 300.0, 0.0)
	K.seq(b, r, "clarinet", "C#4:2 A3:1 B3:1 | G#3:3 B3:1 | D#4:2 B3:2 | C#4:4 | A3:1.5 F#3:.5 C#4:2 | G#3:4", 0.0, bt, 0.22)
	var pent := [66, 68, 69, 71, 73, 76, 78]
	for i in 12:
		if r.randf() < 0.55:
			K.note(b, r, "pizz", pent[r.randi() % pent.size()], (i * 2.0 + float(r.randi_range(0, 1))) * bt, 0.3, 0.06)
	K.echo(b, bt * 0.75, 0.4, 0.25)
	K.hall(b, 0.85, 0.6, 0.3)


## Wastes, mesas and badlands: E phrygian dominant; an oud and a duduk over
## a soft frame drum and a drone.
static func _biome_wastes(b: PackedFloat32Array, r: RandomNumberGenerator, bt: float) -> void:
	var bar := bt * 4.0
	var prog := _cs(["E2 B2 E3 G#3", "F2 C3 F3 A3", "E2 B2 E3 G#3", "D2 A2 D3 F3",
		"A2 E3 A3 C4", "F2 C3 F3 A3", "E2 B2 E3 G#3", "E2 B2 E3 G#3"])
	K.chords(b, r, "warm", prog, bar, 0.16)
	K.drone(b, 40, 0.07, S.Wave.SAW, 400.0, 0.5)
	var tune := "E4:.5 F4:.5 G#4:1 A4:1 G#4:1 | F4:1.5 E4:.5 F4:2 | G#4:.5 A4:.5 B4:1 C5:1 B4:1 | A4:2 F4:2 | " \
		+ "E4:1 A4:1 C5:1.5 B4:.5 | A4:1 C5:1 F4:2 | G#4:1 F4:.5 E4:.5 F4:1 G#4:1 | E4:4"
	K.seq(b, r, "lute", tune, 0.0, bt, 0.2)
	K.seq(b, r, "reed", "E4:1 A4:1 C5:1.5 B4:.5 | A4:1 C5:1 F4:2 | G#4:1 F4:.5 E4:.5 F4:1 G#4:1 | E4:4", 16.0, bt, 0.14, -12)
	K.drums(b, r, "frame", "X..x.x..", 8, bar, 0.14)
	K.drums(b, r, "shaker", "..x...x.", 8, bar, 0.04)
	K.hall(b, 0.8, 0.5, 0.26)


## Kaldfjord: a slow northern air for fiddle in D aeolian, a lur-like horn.
static func _biome_fjord(b: PackedFloat32Array, r: RandomNumberGenerator, bt: float) -> void:
	var bar := bt * 4.0
	var prog := _cs(["D3 A3 D4 F4", "Bb2 F3 Bb3 D4", "F2 C3 F3 A3", "C3 G3 C4 E4",
		"D3 A3 D4 F4", "Bb2 F3 Bb3 D4", "G2 D3 G3 Bb3", "A2 E3 A3 C#4"])
	K.chords(b, r, "strings", prog, bar, 0.22)
	K.drone(b, 38, 0.07, S.Wave.SAW, 500.0, 0.5)
	K.seq(b, r, "fiddle", "A4:2 D5:1 E5:1 | F5:3 D5:1 | C5:2 A4:1 F4:1 | G4:4 | A4:2 F5:1 E5:1 | D5:2 Bb4:2 | "
		+ "G4:2 Bb4:1 D5:1 | C#5:4", 0.0, bt, 0.2)
	K.seq(b, r, "horn", "D3:4 r:12 D3:4 r:12", 0.0, bt, 0.14)
	K.echo(b, bt, 0.35, 0.22)
	K.hall(b, 0.88, 0.45, 0.32)


## Shallow seas: rolling harp, a flute and waves in C lydian.
static func _biome_sea(b: PackedFloat32Array, r: RandomNumberGenerator, bt: float) -> void:
	var bar := bt * 4.0
	var prog := _cs(["C3 G3 B3 E4", "C3 F#3 A3 D4", "A2 E3 G3 C4", "F2 C3 E3 A3",
		"C3 G3 B3 E4", "E2 B2 D3 G3", "F2 C3 E3 A3", "G2 D3 E3 B3"])
	K.chords(b, r, "warm", prog, bar, 0.22)
	K.arp(b, r, "harp", prog, 4.0, bt, [0, 1, 2, 3, 2, 1], 2.0 / 3.0, 0.11, 0, 2.0)
	for i in 4:
		K.note(b, r, "wave", 40, bar * 2.0 * i, bar * 2.0, 0.12)
	K.seq(b, r, "flute", "E5:2 D5:1 C5:1 | F#5:3 E5:1 | E5:2 C5:1 A4:1 | A4:4 | G5:2 E5:1 C5:1 | B4:3 G4:1 | "
		+ "A4:1.5 C5:.5 E5:2 | D5:4", 0.0, bt, 0.17)
	K.echo(b, bt * 0.75, 0.35, 0.22)
	K.hall(b, 0.85, 0.45, 0.3)


## The deep sea (abyss, vents, maelstrom): low and dark, sonar pings and whales.
static func _biome_deep(b: PackedFloat32Array, r: RandomNumberGenerator, bt: float) -> void:
	var chord := bt * 4.0
	var prog := _cs(["D2 A2 D3", "Bb1 F2 D3", "G1 D2 Bb2", "Eb2 Bb2 G3", "A1 E2 C#3"])
	K.chords(b, r, "strings", prog, chord, 0.3)
	K.drone(b, 26, 0.1, S.Wave.SINE, 200.0, 0.0)
	for t: float in [1.0, 7.5, 13.0, 17.0]:
		K.note(b, r, "glass", 86, t * bt, 1.0, 0.07)
	K.glide(b, 45.0, 41.0, bt * 4.0, 5.0, 0.05)
	K.glide(b, 52.0, 55.0, bt * 12.0, 5.0, 0.04)
	K.echo(b, bt * 0.75, 0.5, 0.3)
	K.hall(b, 0.9, 0.6, 0.4)


## Asphodel Fields: a soft choir and a lone voice, B minor, melancholy.
static func _biome_asphodel(b: PackedFloat32Array, r: RandomNumberGenerator, bt: float) -> void:
	var chord := bt * 4.0
	var prog := _cs(["B2 F#3 B3 D4", "G2 D3 G3 B3", "D3 A3 D4 F#4", "A2 E3 A3 C#4", "E2 B2 E3 G3", "F#2 C#3 F#3 A#3"])
	K.chords(b, r, "choir", prog, chord, 0.28)
	K.arp(b, r, "harp", prog, 4.0, bt, [0, 1, 2, 3, 2, 1, 2, 1], 0.5, 0.08, 0, 1.5, 0.25)
	K.seq(b, r, "voice", "F#4:3 E4:1 | D4:2 B3:2 | A4:3 F#4:1 | E4:4 | G4:2 F#4:1 E4:1 | C#4:2 A#3:2", 0.0, bt, 0.2)
	K.hall(b, 0.9, 0.45, 0.38)


## Tartarus: dark C# phrygian; low chant, chains and a distant drum.
static func _biome_tartarus(b: PackedFloat32Array, r: RandomNumberGenerator, bt: float) -> void:
	var chord := bt * 4.0
	var prog := _cs(["C#2 G#2 C#3 E3", "D2 A2 D3 F#3", "C#2 G#2 C#3 E3", "B1 F#2 B2 D3", "A1 E2 A2 C#3", "G#1 D#2 G#2 C3"])
	K.chords(b, r, "choir_oh", prog, chord, 0.3)
	K.drone(b, 25, 0.1, S.Wave.SAW, 220.0, 0.0)
	K.drums(b, r, "taiko", "X.......", 6, chord, 0.3, 28)
	for i in 6:
		K.note(b, r, "clang", 70 + r.randi_range(-3, 3), (i * 4.0 + 2.5) * bt, 0.5, 0.05)
	K.seq(b, r, "low_brass", "C#3:4 D3:4 E3:2 C#3:2 B2:4 A2:4 G#2:4", 0.0, bt, 0.14)
	K.hall(b, 0.88, 0.55, 0.34)


## Ryft Island: ethereal E lydian glass and shimmer.
static func _biome_ryft(b: PackedFloat32Array, r: RandomNumberGenerator, bt: float) -> void:
	var bar := bt * 4.0
	var prog := _cs(["E3 B3 D#4 G#4", "E3 A#3 C#4 F#4", "C#3 G#3 B3 E4", "A2 E3 G#3 C#4",
		"E3 B3 D#4 G#4", "E3 A#3 C#4 F#4", "G#2 D#3 F#3 B3", "B2 F#3 A#3 D#4"])
	K.chords(b, r, "glass_pad", prog, bar, 0.3)
	K.arp(b, r, "celesta", prog, 4.0, bt, [0, 2, 1, 3, 2, 4, 3, 1], 0.5, 0.07, 12, 0.5, 0.3)
	K.seq(b, r, "glass", "G#5:2 F#5:1 D#5:1 | E5:3 A#4:1 | B4:2 C#5:1 E5:1 | C#5:4 | B5:2 A#5:1 G#5:1 | F#5:3 C#5:1 | "
		+ "D#5:2 B4:1 F#5:1 | F#5:4", 0.0, bt, 0.16)
	K.seq(b, r, "flute", "r:16 B4:2 A#4:1 G#4:1 | F#4:4 | D#4:2 B3:1 F#4:1 | F#4:4", 0.0, bt, 0.08)
	K.echo(b, bt * 0.75, 0.45, 0.3)
	K.hall(b, 0.88, 0.35, 0.34)


## Ogygia: Calypso's idyll; harp and flute in F with a lydian lift.
static func _biome_ogygia(b: PackedFloat32Array, r: RandomNumberGenerator, bt: float) -> void:
	var bar := bt * 4.0
	var prog := _cs(["F2 C3 F3 A3", "F2 B2 D3 G3", "A2 E3 A3 C4", "D3 A3 D4 F4",
		"Bb2 F3 Bb3 D4", "C3 G3 C4 E4", "D3 A3 C4 F4", "C3 G3 C4 E4"])
	K.chords(b, r, "warm", prog, bar, 0.22)
	K.arp(b, r, "harp", prog, 4.0, bt, [0, 1, 2, 3, 4, 3, 2, 1], 0.5, 0.11, 0, 1.5)
	K.seq(b, r, "flute", "C5:1.5 A4:.5 F4:1 A4:1 | B4:2 D5:1 G4:1 | A4:1.5 C5:.5 E5:2 | D5:3 r:1 | "
		+ "D5:1 F5:1 Bb5:1.5 A5:.5 | G5:1.5 E5:.5 C5:2 | D5:1 F5:1 A4:1 C5:1 | C5:4", 0.0, bt, 0.18)
	K.echo(b, bt * 0.75, 0.3, 0.2)
	K.hall(b, 0.8, 0.45, 0.24)
