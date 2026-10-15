extends RefCounted
## SFX recipes for creatures and birds (see SfxLibrary). Voices are a jittery
## glottal pulse train (sawtooth with per-cycle pitch jitter, shimmer,
## optional period-doubling sub-harmonic, vocal-fry pulsing and breath noise)
## shaped by formant filters that move as the mouth opens.

const S := preload("res://audio/synth.gd")
const K := preload("res://audio/sfx_kit.gd")


# --- Voice building blocks ---------------------------------------------------------

## Irregular vocal source. `pitch` is a frequency envelope (Vector2 points).
static func voice(r: RandomNumberGenerator, dur: float, pitch: Array, jitter := 0.03, sub := 0.0,
		breath := 0.3, fry_hz := 0.0, fry_depth := 0.0) -> PackedFloat32Array:
	var pts := []
	var half := []
	var t := 0.0
	var seg := 1
	while t <= dur + 0.03:
		var fs := S._env_exp_seg(pitch, t, seg)
		seg = int(fs.y)
		var f := fs.x * r.randf_range(1.0 - jitter, 1.0 + jitter)
		pts.append(Vector2(t, f))
		half.append(Vector2(t, f * 0.5))
		t += 0.02
	var v := S.osc(dur, S.Wave.SAW, pts)
	if sub > 0.0:
		S.add(v, S.osc(dur, S.Wave.SAW, half), sub)
	# Shimmer: fast random amplitude roughness.
	var rough := S.lp(S.noise(dur, r), 90.0)
	S.normalize(rough, 1.0)
	S.modulate(v, rough, 0.45)
	if fry_hz > 0.0 and fry_depth > 0.0:
		S.mul(v, pulses(r, dur, fry_hz, fry_depth))
	if breath > 0.0:
		var n := S.pink(dur, r)
		S.normalize(n, 1.0)
		S.add(v, n, breath)
	return v


## Irregular pulse train (raised-cosine bumps) between 1 - depth and 1: vocal
## fry, growl rattle, chitter.
static func pulses(r: RandomNumberGenerator, dur: float, rate: float, depth: float) -> PackedFloat32Array:
	var b := S.make(dur)
	b.fill(1.0 - depth)
	var t := r.randf() / rate
	while t < dur:
		var period := r.randf_range(0.75, 1.25) / rate
		var w := int(period * S.SR * r.randf_range(0.45, 0.7))
		var i0 := int(t * S.SR)
		var a := depth * r.randf_range(0.6, 1.0)
		for i in w:
			if i0 + i >= b.size():
				break
			b[i0 + i] += a * (0.5 - 0.5 * cos(TAU * float(i) / w))
		t += period
	return b


## Parallel resonances whose centre frequencies follow tracks of points.
static func formant_tracks(src: PackedFloat32Array, tracks: Array, gains: Array, q := 4.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(src.size())
	for k in tracks.size():
		var band := S.filter(src.duplicate(), S.Filter.BANDPASS, tracks[k], q)
		S.add(out, band, float(gains[k]))
	return out


## Tonal call: a sum of harmonics following one pitch envelope.
static func harmonic(dur: float, pitch: Array, amps: Array) -> PackedFloat32Array:
	var b := S.make(dur)
	for h in amps.size():
		var pts := []
		for p: Vector2 in pitch:
			pts.append(Vector2(p.x, p.y * (h + 1)))
		if (pitch[0] as Vector2).y * (h + 1) > S.SR * 0.45:
			break
		S.add(b, S.osc(dur, S.Wave.SINE, pts), float(amps[h]))
	return b


## Pitch envelope with vibrato (rate Hz, depth fraction) fading in after `onset`.
static func vibrato(dur: float, base: Array, rate: float, depth: float, onset: float, r: RandomNumberGenerator) -> Array:
	var pts := []
	var t := 0.0
	var ph := r.randf() * TAU
	var seg := 1
	while t <= dur + 0.02:
		var d := depth * clampf((t - onset) / 0.4, 0.0, 1.0)
		var fs := S._env_exp_seg(base, t, seg)
		seg = int(fs.y)
		pts.append(Vector2(t, fs.x * (1.0 + d * sin(ph + TAU * rate * t))))
		t += 0.02
	return pts


# --- Beasts --------------------------------------------------------------------------

## Generic monster roar. size 1 = ghoul / troll, 2+ = boss.
static func roar(r: RandomNumberGenerator, f0: float, dur: float, size: float, room := true) -> PackedFloat32Array:
	var f := f0 * K.jit(r, 0.08)
	var pitch := [Vector2(0, f * 0.75), Vector2(dur * 0.18, f * 1.15), Vector2(dur * 0.6, f), Vector2(dur, f * 0.6)]
	var src := voice(r, dur, pitch, 0.05, 0.25 * size, 0.55, 40.0 / sqrt(size), 0.25)
	var k := 1.0 / sqrt(size)
	var b := formant_tracks(src, [
		[Vector2(0, 380 * k), Vector2(dur * 0.2, 700 * k), Vector2(dur, 450 * k)],
		[Vector2(0, 950 * k), Vector2(dur * 0.2, 1300 * k), Vector2(dur, 1000 * k)],
		[Vector2(0, 2300 * k), Vector2(dur, 2100 * k)],
	], [1.0, 0.6, 0.25], 3.5)
	S.env(b, [Vector2(0, 0), Vector2(dur * 0.12, 1.0), Vector2(dur * 0.65, 0.8), Vector2(dur, 0)])
	if size > 1.5:
		var sub := S.osc(dur, S.Wave.SINE, [Vector2(0, 48), Vector2(dur, 32)])
		S.env(sub, [Vector2(0, 0), Vector2(dur * 0.2, 1.0), Vector2(dur, 0)])
		S.add(b, sub, 0.5)
		S.low_shelf(b, 180.0, 5.0)
	S.normalize(b, 0.9)
	S.soft_clip(b, 1.4 + size * 0.35)
	return S.reverb(b, 0.82, 0.45, 0.2) if room else b


static func growl(r: RandomNumberGenerator, f0: float, dur: float) -> PackedFloat32Array:
	var f := f0 * K.jit(r, 0.1)
	var pitch := [Vector2(0, f * 0.9), Vector2(dur * 0.4, f * 1.1), Vector2(dur, f * 0.85)]
	var src := voice(r, dur, pitch, 0.06, 0.4, 0.35, r.randf_range(18.0, 28.0), 0.75)
	var b := formant_tracks(src, [
		[Vector2(0, 280), Vector2(dur * 0.5, 360), Vector2(dur, 300)],
		[Vector2(0, 750), Vector2(dur, 820)],
		[Vector2(0, 2000)],
	], [1.0, 0.5, 0.15], 4.0)
	S.env(b, [Vector2(0, 0), Vector2(0.15, 1.0), Vector2(dur * 0.75, 0.7), Vector2(dur, 0)])
	S.normalize(b, 0.9)
	return S.soft_clip(b, 1.6)


static func wolf_growl(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := r.randf_range(1.0, 1.3)
	var f := r.randf_range(105.0, 140.0)
	var src := voice(r, dur, [Vector2(0, f), Vector2(dur * 0.5, f * 1.15), Vector2(dur, f * 0.9)], 0.07, 0.3, 0.5,
			r.randf_range(24.0, 34.0), 0.7)
	var b := formant_tracks(src, [[Vector2(0, 480), Vector2(dur, 560)], [Vector2(0, 1350)], [Vector2(0, 2700)]],
			[1.0, 0.6, 0.3], 4.0)
	# Snarl: lips drawn back, air hissing over teeth.
	var snarl := S.filter(S.pink(dur, r), S.Filter.BANDPASS, [Vector2(0, 3000)], 1.5)
	S.mul(snarl, pulses(r, dur, 28.0, 0.7))
	S.add(b, snarl, 0.25)
	S.env(b, [Vector2(0, 0), Vector2(0.1, 1.0), Vector2(dur * 0.7, 0.85), Vector2(dur, 0)])
	S.normalize(b, 0.9)
	return S.soft_clip(b, 1.5)


static func wolf_howl(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := r.randf_range(2.6, 3.4)
	var lo := r.randf_range(300.0, 380.0)
	var hi := r.randf_range(470.0, 560.0)
	var base := [Vector2(0, lo), Vector2(0.45, hi), Vector2(dur * 0.65, hi * 0.95), Vector2(dur, lo * 0.75)]
	var pitch := vibrato(dur, base, r.randf_range(4.5, 6.0), 0.012, 0.6, r)
	var b := harmonic(dur, pitch, [1.0, 0.35, 0.14, 0.06, 0.03])
	var breath := S.bp(S.pink(dur, r), hi * 2.0, 2.0)
	S.normalize(breath, 1.0)
	S.add(b, breath, 0.04)
	S.lp(b, 2200.0)
	S.env(b, [Vector2(0, 0), Vector2(0.18, 0.8), Vector2(0.5, 1.0), Vector2(dur - 0.5, 0.85), Vector2(dur, 0)])
	# Heard across a valley.
	return S.reverb(b, 0.88, 0.45, 0.35)


static func bear_roar(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := r.randf_range(1.6, 2.0)
	var f := r.randf_range(95.0, 125.0)
	var src := voice(r, dur, [Vector2(0, f * 0.8), Vector2(0.25, f * 1.2), Vector2(dur, f * 0.7)], 0.07, 0.3, 1.1,
			r.randf_range(30.0, 45.0), 0.3)
	var b := formant_tracks(src, [
		[Vector2(0, 450), Vector2(0.3, 750), Vector2(dur, 550)],
		[Vector2(0, 1050), Vector2(0.3, 1250), Vector2(dur, 1100)],
		[Vector2(0, 2500)],
	], [1.0, 0.6, 0.3], 3.0)
	S.env(b, [Vector2(0, 0), Vector2(0.15, 1.0), Vector2(dur * 0.6, 0.85), Vector2(dur, 0)])
	S.low_shelf(b, 200.0, 4.0)
	S.normalize(b, 0.9)
	S.soft_clip(b, 1.8)
	return S.reverb(b, 0.8, 0.5, 0.15)


static func spider_hiss(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := r.randf_range(0.7, 1.0)
	var hiss := S.hp(S.noise(dur, r), 2500.0)
	hiss = S.formants(hiss, [3600.0 * K.jit(r, 0.1), 5800.0], [1.0, 0.6], 2.0)
	S.mul(hiss, pulses(r, dur, r.randf_range(25.0, 40.0), 0.5))
	S.env(hiss, [Vector2(0, 0), Vector2(0.06, 1.0), Vector2(dur * 0.6, 0.8), Vector2(dur, 0)])
	var clicks := S.make(dur)
	for i in r.randi_range(5, 10):
		var e := S.decay(S.noise(0.003, r), 0.0001, 0.0005)
		var ff := r.randf_range(3000.0, 6500.0)
		S.add(clicks, S.modal(e, [ff, ff * 1.5], [0.006, 0.004], [1.0, 0.5], 0.04), r.randf_range(0.4, 1.0),
				S.samples(r.randf_range(0.0, dur - 0.05)))
	var legs := S.grains(dur, r.randi_range(20, 40), r, 2000.0, 8000.0, 0.0003, 0.001, 1.0)
	S.normalize(hiss)
	S.normalize(clicks)
	S.normalize(legs)
	return K.mix([[hiss, 1.0, 0.0], [clicks, 0.5, 0.0], [legs, 0.25, 0.0]])


static func bat_screech(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 0.7
	var b := S.make(dur)
	var t := 0.0
	for i in r.randi_range(4, 8):
		var clen := r.randf_range(0.025, 0.05)
		var f_hi := r.randf_range(9000.0, 12000.0)
		var chirp := harmonic(clen, [Vector2(0, f_hi), Vector2(clen, f_hi * r.randf_range(0.4, 0.5))], [1.0, 0.15])
		S.env(chirp, [Vector2(0, 0), Vector2(0.004, 1.0), Vector2(clen, 0)])
		S.add(b, chirp, r.randf_range(0.4, 1.0), S.samples(t))
		t += r.randf_range(0.05, 0.09)
		if t > dur - 0.1:
			break
	# Audible social squeak.
	var sq_len := r.randf_range(0.12, 0.2)
	var f := r.randf_range(3000.0, 4500.0)
	var squeak := harmonic(sq_len, [Vector2(0, f), Vector2(sq_len * 0.4, f * 1.25), Vector2(sq_len, f * 0.85)], [1.0, 0.4, 0.15])
	S.mul(squeak, pulses(r, sq_len, 60.0, 0.6))
	S.env(squeak, [Vector2(0, 0), Vector2(0.01, 1.0), Vector2(sq_len, 0)])
	S.add(b, squeak, 0.8, S.samples(r.randf_range(0.05, 0.3)))
	return b


## A flock taking off: many birds, each flapping fast and fading as it climbs.
static func bird_flap(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 2.0
	var b := S.make(dur)
	var flap_src := []
	for k in 6:
		var f := S.filter(S.noise(0.06, r), S.Filter.BANDPASS, [Vector2(0, r.randf_range(700.0, 1600.0))], 0.8)
		flap_src.append(S.decay(f, 0.003, 0.018))
	for bird in r.randi_range(9, 15):
		var t := pow(r.randf(), 1.5) * 0.45
		var rate := r.randf_range(8.0, 12.0)
		var life := r.randf_range(0.7, 1.5)
		var amp := r.randf_range(0.4, 1.0)
		var t0 := t
		while t < t0 + life and t < dur - 0.07:
			var fade := 1.0 - (t - t0) / life
			S.add(b, flap_src[r.randi_range(0, 5)], amp * fade * r.randf_range(0.7, 1.0), S.samples(t))
			t += 1.0 / rate * r.randf_range(0.9, 1.1)
	for i in r.randi_range(1, 3):
		S.add(b, bird_call(r, 3, false), 0.2, S.samples(r.randf_range(0.1, 0.8)))
	var air := K.whoosh(r, dur, [Vector2(0, 600), Vector2(dur, 1200)], 0.7,
			[Vector2(0, 0), Vector2(0.15, 1.0), Vector2(dur, 0)])
	S.add(b, air, 0.15)
	return b


static func deer_call(r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.make(1.4)
	var calls := r.randi_range(1, 2)
	for c in calls:
		var dur := r.randf_range(0.25, 0.4)
		var f := r.randf_range(380.0, 520.0)
		# Alarm bark: harsh, noisy, quick fall.
		var src := voice(r, dur, [Vector2(0, f * 1.2), Vector2(0.05, f), Vector2(dur, f * 0.7)], 0.05, 0.2, 0.9)
		var call := S.formants(src, [900.0, 1900.0, 3100.0], [1.0, 0.6, 0.3], 4.0)
		S.env(call, [Vector2(0, 0), Vector2(0.015, 1.0), Vector2(0.08, 0.6), Vector2(dur, 0)])
		S.add(b, call, 1.0, S.samples(c * r.randf_range(0.5, 0.7)))
	return S.reverb(b, 0.82, 0.4, 0.25)


## The sea boss: a whale-like moan sweeping through moving formants, a monster
## roar rising out of it, sub rumble and churning water.
static func leviathan_roar(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 5.6
	var f := r.randf_range(50.0, 62.0)
	var pitch := [Vector2(0, f), Vector2(1.4, f * 1.7), Vector2(3.0, f * 1.35), Vector2(dur, f * 0.8)]
	var raw := S.osc(dur, S.Wave.SAW, vibrato(dur, pitch, 3.0, 0.015, 1.0, r))
	S.lp(raw, 1400.0)
	var moan := formant_tracks(raw, [
		[Vector2(0, 250), Vector2(1.5, 600), Vector2(dur, 320)],
		[Vector2(0, 800), Vector2(1.5, 1300), Vector2(dur, 900)],
	], [1.0, 0.5], 2.5)
	S.add(moan, S.lp(raw, 300.0), 0.6)
	S.env(moan, [Vector2(0, 0), Vector2(0.8, 1.0), Vector2(dur - 1.2, 0.8), Vector2(dur, 0)])
	var monster := roar(r, 40.0, 3.0, 3.0, false)
	var sub := S.lp(S.brown(dur, r), 70.0)
	S.env(sub, [Vector2(0, 0), Vector2(1.0, 1.0), Vector2(dur, 0)])
	var churn := S.lp(S.pink(dur, r), 500.0)
	S.mul(churn, S.wander(dur, 0.1, 0.3, 1.0, r))
	S.env(churn, [Vector2(0, 0.3), Vector2(1.5, 1.0), Vector2(dur, 0)])
	var b := K.mix([[moan, 1.0, 0.0], [monster, 0.8, 1.1], [sub, 1.2, 0.0], [churn, 0.4, 0.0]])
	for i in 60:
		S.bubble(b, r.randf_range(0.5, dur - 0.5), r.randf_range(90.0, 500.0), 0.1, r.randf_range(0.01, 0.04), 0.5)
	if b.size() > S.samples(dur):
		b = b.slice(0, S.samples(dur))
	S.soft_clip(b, 1.3)
	return S.reverb(b, 0.92, 0.5, 0.3)


static func wing_flap(r: RandomNumberGenerator) -> PackedFloat32Array:
	# Huge leathery wing: the downstroke shoves air, the membrane snaps taut.
	var dur := 0.7
	var push := S.filter(S.pink(dur, r), S.Filter.LOWPASS, [Vector2(0, 900), Vector2(dur, 150)], 1.2)
	S.env(push, [Vector2(0, 0), Vector2(0.06, 1.0), Vector2(0.25, 0.4), Vector2(dur, 0)])
	var whomp := K.thump(dur, 70.0, 38.0, 0.1, 0.15)
	var snap := S.grains(0.25, r.randi_range(15, 30), r, 300.0, 1500.0, 0.003, 0.008, 2.0)
	var crack := S.lp(K.click(r, 0.004, 200.0, 0.05), 2500.0)
	return K.mix([[push, 1.0, 0.0], [whomp, 0.9, 0.02], [snap, 0.5, 0.04], [crack, 0.4, 0.05]])


static func stomp(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 1.1
	var sub := K.thump(dur, 55.0, 25.0, 0.25, 0.25)
	var hit := K.ki("impactSoft_heavy", r.randi_range(0, 4), r.randf_range(0.5, 0.6), 0.0, 25.0)
	var debris := S.grains(dur, 80, r, 400.0, 3500.0, 0.002, 0.008, 1.8, 0.35)
	var rumble := S.lp(S.brown(dur, r), 150.0)
	S.env(rumble, [Vector2(0, 0), Vector2(0.02, 1.0), Vector2(dur, 0)])
	var b := K.mix([[sub, 1.2, 0.0], [hit, 0.8, 0.0], [debris, 0.4, 0.0], [rumble, 0.9, 0.0]])
	return S.soft_clip(b, 1.6)


static func bone_rattle(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 0.65
	var b := S.make(dur)
	var t := 0.0
	for i in r.randi_range(9, 15):
		var e := S.decay(S.noise(0.004, r), 0.0001, 0.0006)
		var f := r.randf_range(1100.0, 3400.0)
		var k := S.modal(e, [f, f * 1.8, f * 2.9], [0.016, 0.01, 0.007], [1.0, 0.5, 0.25], 0.08)
		S.add(b, k, r.randf_range(0.4, 1.0), S.samples(t))
		t += r.randf_range(0.01, 0.06)
		if t > dur - 0.08:
			t = r.randf_range(0.0, 0.2)
	return b


static func imp_screech(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := r.randf_range(0.55, 0.75)
	var f := r.randf_range(800.0, 1050.0)
	var src := voice(r, dur, [Vector2(0, f), Vector2(0.18, f * 1.5), Vector2(dur, f * 0.7)], 0.04, 0.0, 0.25,
			r.randf_range(20.0, 26.0), 0.4)
	var b := S.formants(src, [1800.0, 2900.0, 4200.0], [1.0, 0.6, 0.25], 5.0)
	S.env(b, [Vector2(0, 0), Vector2(0.03, 1.0), Vector2(0.4, 0.6), Vector2(dur, 0)])
	S.normalize(b, 0.9)
	return S.soft_clip(b, 1.5)


# --- Birds ---------------------------------------------------------------------------

static func _note(b: PackedFloat32Array, t: float, dur: float, pitch: Array, amp: float, harm := 0.12) -> void:
	var n := harmonic(dur, pitch, [1.0, harm])
	S.env(n, [Vector2(0, 0), Vector2(minf(0.008, dur * 0.2), 1.0), Vector2(dur * 0.7, 0.7), Vector2(dur, 0)])
	S.add(b, n, amp, S.samples(t))


## Songbird calls of a few different "species"; variant picks the pattern.
static func bird_call(r: RandomNumberGenerator, v: int, room := true) -> PackedFloat32Array:
	var b := S.make(2.2)
	var j := K.jit(r, 0.08)
	match v % 8:
		0:  # two-note whistle, "fee-bee"
			_note(b, 0.0, 0.22, [Vector2(0, 3300 * j), Vector2(0.22, 3250 * j)], 1.0, 0.05)
			_note(b, 0.28, 0.25, [Vector2(0, 2750 * j), Vector2(0.25, 2700 * j)], 0.9, 0.05)
		1:  # rapid descending trill
			var t := 0.0
			var f := 5200.0 * j
			for i in r.randi_range(10, 18):
				_note(b, t, 0.035, [Vector2(0, f), Vector2(0.035, f * 0.8)], 0.8)
				t += 1.0 / r.randf_range(16.0, 20.0)
				f *= 0.985
		2:  # warble: wandering melody
			var pts := []
			var t := 0.0
			while t < 1.2:
				pts.append(Vector2(t, r.randf_range(2200.0, 4800.0) * j))
				t += r.randf_range(0.03, 0.06)
			var w := harmonic(1.2, pts, [1.0, 0.1])
			S.mul(w, pulses(r, 1.2, 14.0, 0.85))
			S.env(w, [Vector2(0, 0), Vector2(0.05, 1.0), Vector2(1.0, 0.8), Vector2(1.2, 0)])
			S.add(b, w, 0.8)
		3:  # "tsip tsip" contact / alarm chips
			var t := 0.0
			for i in r.randi_range(2, 4):
				_note(b, t, 0.04, [Vector2(0, 7500 * j), Vector2(0.04, 4800 * j)], 1.0, 0.05)
				t += r.randf_range(0.12, 0.25)
		4:  # dove coo
			var t := 0.0
			for i in 3:
				var d := 0.32 if i != 1 else 0.5
				_note(b, t, d, [Vector2(0, 560 * j), Vector2(d * 0.3, 620 * j), Vector2(d, 520 * j)], 1.0, 0.3)
				t += d + 0.12
			S.lp(b, 1500.0)
		5:  # thrush: a motif repeated
			var motif := []
			for i in r.randi_range(2, 4):
				var f0 := r.randf_range(2000.0, 4500.0)
				motif.append([f0, f0 * r.randf_range(0.8, 1.3), r.randf_range(0.05, 0.1)])
			var t := 0.0
			for rep in 2:
				for m: Array in motif:
					_note(b, t, m[2], [Vector2(0, m[0] * j), Vector2(m[2], m[1] * j)], 0.9)
					t += float(m[2]) + 0.03
				t += 0.18
		6:  # robin-like: varied whistles with pauses
			var t := 0.0
			for i in r.randi_range(4, 6):
				var d := r.randf_range(0.08, 0.18)
				var f0 := r.randf_range(2400.0, 4200.0)
				_note(b, t, d, [Vector2(0, f0), Vector2(d * 0.5, f0 * r.randf_range(0.9, 1.25)), Vector2(d, f0 * 0.9)], 0.8)
				t += d + r.randf_range(0.06, 0.15)
		7:  # crow caw
			var t := 0.0
			for i in r.randi_range(2, 3):
				var d := r.randf_range(0.22, 0.3)
				var src := voice(r, d, [Vector2(0, 520 * j), Vector2(d, 430 * j)], 0.04, 0.0, 0.5)
				var caw := S.formants(src, [1100.0, 1700.0, 2600.0], [1.0, 0.7, 0.3], 5.0)
				S.env(caw, [Vector2(0, 0), Vector2(0.02, 1.0), Vector2(d * 0.6, 0.7), Vector2(d, 0)])
				S.add(b, caw, 0.8, S.samples(t))
				t += d + r.randf_range(0.15, 0.25)
	b = K.trim(b)
	S.highpass1(b, 300.0)
	return S.reverb(b, 0.75, 0.4, 0.2) if room else b


static func owl(r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.make(2.6)
	var j := K.jit(r, 0.06)
	var hoots := [[0.0, 0.35], [0.75, 0.18], [1.0, 0.75]]
	for h: Array in hoots:
		var d: float = h[1]
		_note(b, h[0], d, [Vector2(0, 410 * j), Vector2(d * 0.3, 430 * j), Vector2(d, 370 * j)], 1.0, 0.15)
		var breath := S.lp(S.pink(d, r), 900.0)
		S.env(breath, [Vector2(0, 0), Vector2(d * 0.3, 1.0), Vector2(d, 0)])
		S.add(b, breath, 0.06, S.samples(h[0]))
	S.lp(b, 1800.0)
	return S.reverb(b, 0.86, 0.45, 0.35)
