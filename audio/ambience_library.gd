class_name AmbienceLibrary
extends RefCounted
## Seamless looping ambience beds. Each is rendered `length_of(bed) + XFADE`
## seconds long and folded into an equal-power crossfaded loop. Most beds are
## stereo: either two independently rendered channels, or (for diffuse,
## stationary textures) the loop and a copy rotated by half its length, which
## is fully decorrelated and still seamless. Stream / waterfall / crickets use
## CC0 field recordings (see CREDITS.md); everything else is synthesised.
##
## Audio derives the internal beds ("wind_strong", "rain_heavy") from the
## public "wind" / "rain" levels and modulates wind and leaves with gusts at
## run time, so the loops never sound static.

const S := preload("res://audio/synth.gd")
const K := preload("res://audio/sfx_kit.gd")
const C := preload("res://audio/sfx_creatures.gd")
const N := preload("res://audio/sfx_nature.gd")

const LOOP := 12.0
const XFADE := 1.0

## Every bed Audio keeps a player for (public keys first).
const BEDS := ["wind", "rain", "fire", "cave", "lava", "village", "birds", "insects", "crickets", "leaves",
	"ocean", "waterfall", "stream", "underwater", "furnace", "wind_strong", "rain_heavy"]

## Keys accepted by Audio.set_ambience.
const PUBLIC := ["wind", "rain", "fire", "cave", "lava", "village", "birds", "insects", "crickets", "leaves",
	"ocean", "waterfall", "stream", "underwater", "furnace"]

## Loop length overrides (default LOOP).
const LENGTH := {"ocean": 14.0, "fire": 10.0, "furnace": 10.0, "lava": 10.0, "underwater": 10.0}

## "mono", "shift" (rotated copy) or "dual" (two renders).
const STEREO := {"fire": "mono", "furnace": "mono", "village": "mono", "birds": "dual",
	"stream": "rec", "waterfall": "rec", "crickets": "rec"}

## RMS each bed is normalised to (dBFS); Audio applies per-bed mix gains.
const RMS_DB := -20.0

## Render order: what a fresh overworld start needs first.
const ORDER := ["wind", "leaves", "birds", "crickets", "insects", "rain", "rain_heavy", "wind_strong", "cave",
	"stream", "fire", "village", "ocean", "waterfall", "underwater", "lava", "furnace"]


static func length_of(bed: String) -> float:
	return float(LENGTH.get(bed, LOOP))


static func channels_of(bed: String) -> int:
	return 1 if STEREO.get(bed, "shift") == "mono" else 2


## Compatibility: the first (left / mono) channel.
static func build(bed: String) -> PackedFloat32Array:
	return build_channels(bed)[0]


## One (mono) or two (left, right) loop buffers, each exactly length_of(bed).
static func build_channels(bed: String) -> Array:
	var loop := length_of(bed)
	var mode: String = STEREO.get(bed, "shift")
	var out := []
	match mode:
		"rec":
			for ch: PackedFloat32Array in _recorded(bed, loop + XFADE):
				out.append(S.make_loop(S.dc_block(ch), loop, XFADE))
		"dual":
			for c in 2:
				var b := _render(bed, loop + XFADE, S.rng(hash(bed) + 99 + c * 7777))
				out.append(S.make_loop(S.dc_block(b), loop, XFADE))
		_:
			var b := _render(bed, loop + XFADE, S.rng(hash(bed) + 99))
			var l := S.make_loop(S.dc_block(b), loop, XFADE)
			out.append(l)
			if mode == "shift":
				var half := l.size() / 2
				var rr := l.slice(half)
				rr.append_array(l.slice(0, half))
				out.append(rr)
	_level(out)
	return out


## Common RMS for all channels, peak kept under 0.9.
static func _level(chans: Array) -> void:
	var acc := 0.0
	var n := 0
	var p := 0.0
	for ch: PackedFloat32Array in chans:
		for v in ch:
			acc += v * v
		n += ch.size()
		p = maxf(p, S.peak(ch))
	var rms := sqrt(acc / maxf(1.0, n))
	if rms < 1e-7:
		return
	var g := minf(db_to_linear(RMS_DB) / rms, 0.9 / maxf(p, 1e-6))
	for ch: PackedFloat32Array in chans:
		S.gain(ch, g)


static func _render(bed: String, dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	match bed:
		"wind": return _wind(dur, r)
		"wind_strong": return _wind_strong(dur, r)
		"rain": return _rain(dur, r)
		"rain_heavy": return _rain_heavy(dur, r)
		"fire": return _fire(dur, r)
		"cave": return _cave(dur, r)
		"lava": return _lava(dur, r)
		"village": return _village(dur, r)
		"birds": return _birds(dur, r)
		"insects": return _insects(dur, r)
		"leaves": return _leaves(dur, r)
		"ocean": return _ocean(dur, r)
		"underwater": return _underwater(dur, r)
		"furnace": return _furnace(dur, r)
	push_error("Unknown ambience %s" % bed)
	return S.make(dur)


static func _recorded(bed: String, dur: float) -> Array:
	var r := S.rng(hash(bed) + 5)
	match bed:
		"stream":
			var st := K.SB.stereo("field/river_thimras.ogg")
			var out := []
			for ch: PackedFloat32Array in st:
				var b := _fit(ch, dur, 0.0)
				S.hp(b, 80.0)
				# A little more close-up babble.
				N.bubbles(b, r, int(dur * 6.0), 0.0, dur, 500.0, 2200.0, 0.05, 1.0)
				out.append(b)
			return out
		"waterfall":
			var st := K.SB.stereo("field/river_thimras.ogg", 0.8)
			# One synthesised roar under both channels: heavy, dense falling water.
			var roar := S.lowpass1(S.lowpass1(S.pink(dur, r), 2500.0), 3500.0)
			S.normalize(roar, 0.5)
			var low := S.lp(S.brown(dur, r), 150.0)
			S.normalize(low, 0.5)
			S.add(roar, low, 0.7)
			var out := []
			for ch: PackedFloat32Array in st:
				var b := _fit(ch, dur, 2.0)
				S.normalize(b, 0.5)
				S.add(b, roar, 0.8, S.samples(0.37) * out.size(), true)
				out.append(b)
			return out
		"crickets":
			var st := K.SB.stereo("field/crickets_wolfgang.ogg")
			var out := []
			for ch: PackedFloat32Array in st:
				out.append(_fit(ch, dur, 0.0))
			return out
	return [S.make(dur), S.make(dur)]


## Cut `dur` seconds from `start` (wrapping if the recording is short).
static func _fit(b: PackedFloat32Array, dur: float, start: float) -> PackedFloat32Array:
	var n := S.samples(dur)
	if b.is_empty():
		return S.make(dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var i0 := S.samples(start) % b.size()
	for i in n:
		out[i] = b[(i0 + i) % b.size()]
	return out


static func _random_points(dur: float, step: float, lo: float, hi: float, r: RandomNumberGenerator) -> Array:
	var pts := []
	var t := 0.0
	while t <= dur + step:
		pts.append(Vector2(t, r.randf_range(lo, hi)))
		t += step * r.randf_range(0.7, 1.3)
	return pts


# --- Weather -------------------------------------------------------------------------

static func _wind(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.pink(dur, r)
	S.add(b, S.brown(dur, r), 1.5)
	S.filter(b, S.Filter.BANDPASS, _random_points(dur, 1.6, 240.0, 700.0, r), 0.7)
	var gust := S.wander(dur, 1.2, 0.25, 1.0, r)
	S.mul(b, gust)
	# Whistling over edges and branches, strongest in the gusts.
	var whistle := S.filter(S.noise(dur, r), S.Filter.BANDPASS, _random_points(dur, 2.2, 650.0, 1500.0, r), 16.0)
	S.mul(whistle, gust)
	S.mul(whistle, gust)
	S.add(b, whistle, 0.6)
	var air := S.hp(S.pink(dur, r), 2500.0)
	S.mul(air, gust)
	return S.add(b, air, 0.12)


static func _wind_strong(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.pink(dur, r)
	S.filter(b, S.Filter.BANDPASS, _random_points(dur, 1.0, 350.0, 1200.0, r), 0.6)
	S.mul(b, S.wander(dur, 0.6, 0.35, 1.0, r))
	# Buffeting: low, fast, irregular pressure.
	var buffet := S.lp(S.brown(dur, r), 110.0)
	S.normalize(buffet, 1.0)
	S.mul(buffet, S.wander(dur, 0.15, 0.1, 1.0, r))
	S.add(b, buffet, 0.8)
	for k in 2:
		var howl := S.filter(S.noise(dur, r), S.Filter.BANDPASS,
				_random_points(dur, 1.8, 420.0 * (1 + k * 1.6), 900.0 * (1 + k * 1.4), r), 22.0)
		S.mul(howl, S.wander(dur, 0.9, 0.0, 1.0, r))
		S.add(b, howl, 0.9 - k * 0.4)
	return b


## Light rain: ticks on leaves and ground, a few drops in puddles, soft hiss.
static func _rain(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.grains(dur, int(dur * 380), r, 2000.0, 9500.0, 0.0002, 0.0008, 1.0)
	var leaf := S.grains(dur, int(dur * 30), r, 700.0, 2500.0, 0.002, 0.005, 1.0)
	S.add(b, leaf, 0.5)
	N.bubbles(b, r, int(dur * 10), 0.0, dur, 1200.0, 3500.0, 0.06, 1.0)
	var hiss := S.lp(S.hp(S.pink(dur, r), 1200.0), 10000.0)
	S.normalize(hiss, 0.25)
	S.add(b, hiss, 0.6)
	var low := S.lp(S.brown(dur, r), 300.0)
	S.normalize(low, 0.1)
	return S.add(b, low, 1.0)


## Downpour: a dense roar of countless impacts with gusting intensity.
static func _rain_heavy(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.filter(S.pink(dur, r), S.Filter.BANDPASS, [Vector2(0, 2800)], 0.45)
	S.mul(b, S.wander(dur, 0.8, 0.65, 1.0, r))
	S.normalize(b, 0.5)
	var roar := S.lp(S.pink(dur, r), 700.0)
	S.normalize(roar, 0.35)
	S.add(b, roar, 1.0)
	var ticks := S.grains(dur, int(dur * 700), r, 1500.0, 9000.0, 0.0002, 0.0008, 1.0)
	S.normalize(ticks, 0.5)
	S.add(b, ticks, 0.8)
	var splat := S.grains(dur, int(dur * 60), r, 500.0, 2000.0, 0.002, 0.006, 1.0)
	S.normalize(splat, 0.4)
	return S.add(b, splat, 0.6)


# --- Fire and heat ----------------------------------------------------------------------

static func _fire(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := N.flame(r, dur, 500.0)
	S.normalize(b, 0.4)
	var cr := N.crackle(r, dur, 22.0)
	S.normalize(cr, 0.5)
	S.add(b, cr, 1.0)
	var hiss := S.hp(S.pink(dur, r), 3000.0)
	S.normalize(hiss, 0.05)
	S.add(b, hiss, 1.0)
	for i in 2:
		var shift := K.ki("impactWood_light", r.randi_range(0, 4), r.randf_range(0.6, 0.8), 0.3)
		S.lp(shift, 1500.0)
		S.add(b, shift, 0.25, S.samples(r.randf_range(0.5, dur - 1.5)))
	return b


static func _furnace(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := N.flame(r, dur, 700.0)
	S.normalize(b, 0.5)
	var roar := S.lp(S.brown(dur, r), 150.0)
	S.normalize(roar, 0.5)
	S.add(b, roar, 1.0)
	# Draught "breathing" through the chimney.
	S.modulate(b, S.tone(dur, S.Wave.SINE, 0.25 if dur > 4.0 else 1.0), 0.25)
	var cr := N.crackle(r, dur, 18.0)
	S.normalize(cr, 0.5)
	return S.add(b, cr, 0.6)


static func _lava(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.lp(S.brown(dur, r), 120.0)
	S.normalize(b, 0.6)
	var t := 0.05
	while t < dur - 0.4:
		var f := r.randf_range(45.0, 110.0)
		S.bubble(b, t, f, r.randf_range(0.2, 0.5), r.randf_range(0.03, 0.07), 1.2)
		t += r.randf_range(0.2, 0.8)
	var hiss := S.grains(dur, int(dur * 40), r, 2000.0, 7000.0, 0.0003, 0.001, 1.0)
	S.normalize(hiss, 0.3)
	return S.add(b, hiss, 1.0)


# --- Places ----------------------------------------------------------------------------

## Cave room tone: still, low air; drips into pools; a long reverberant tail.
static func _cave(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.lp(S.brown(dur, r), 110.0)
	S.normalize(b, 0.25)
	var air := S.lp(S.pink(dur, r), 400.0)
	S.normalize(air, 0.05)
	S.add(b, air, 1.0)
	var t := r.randf_range(0.2, 0.8)
	while t < dur - 0.4:
		S.bubble(b, t, r.randf_range(800.0, 2600.0), r.randf_range(0.08, 0.3), r.randf_range(0.008, 0.02), r.randf_range(0.3, 1.0))
		t += r.randf_range(0.6, 2.2)
	return S.reverb(b, 0.9, 0.4, 0.6)


## Village: distant smithy, the odd bird, a wind chime, quiet room tone.
static func _village(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.lp(S.pink(dur, r), 700.0)
	S.normalize(b, 0.08)
	var t := r.randf_range(0.5, 2.0)
	while t < dur - 3.0:
		for k in r.randi_range(3, 5):
			var e := S.decay(S.noise(0.004, r), 0.0001, 0.0006)
			var ring := S.modal(e, [1050.0, 1660.0, 2430.0, 3120.0], [0.5, 0.35, 0.25, 0.15], [1.0, 0.6, 0.4, 0.2], 1.0)
			S.lp(ring, 3000.0)
			S.normalize(ring, 0.25)
			S.add(b, ring, 1.0, S.samples(t + k * r.randf_range(0.9, 1.2)))
		t += r.randf_range(5.0, 8.0)
	for i in 3:
		S.add(b, C.bird_call(r, r.randi_range(0, 6), false), r.randf_range(0.05, 0.12), S.samples(r.randf_range(0.0, dur - 2.2)))
	var chime := S.bell(2.0, 1174.7, [1.0, 2.76, 5.4], [0.3, 0.1, 0.05], [0.8, 0.3, 0.1])
	S.add(b, chime, 0.05, S.samples(dur * 0.4))
	return S.reverb(b, 0.8, 0.5, 0.3)


# --- Wildlife -----------------------------------------------------------------------

## Distant dawn-chorus wash (closer individual birds are one-shots).
static func _birds(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.hp(S.pink(dur, r), 1500.0)
	S.normalize(b, 0.01)
	var calls := S.make(dur)
	for i in r.randi_range(9, 13):
		var call := C.bird_call(r, r.randi_range(0, 6), false)
		S.add(calls, call, r.randf_range(0.04, 0.16), S.samples(r.randf_range(0.0, dur - 1.0)), true)
	# Distance: dulled and diffuse.
	S.lowpass1(calls, 5000.0)
	S.reverb(calls, 0.8, 0.45, 0.4, true)
	return S.add(b, calls, 1.0)


## Daytime insects: cicada drone phrases, grasshopper stridulation, a passing fly.
static func _insects(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.make(dur)
	for k in 2:
		var cic := S.filter(S.noise(dur, r), S.Filter.BANDPASS, [Vector2(0, 4300.0 + k * 1700.0)], 4.0 + k * 2.0)
		var rate := r.randf_range(40.0, 60.0)
		S.modulate(cic, S.tone(dur, S.Wave.SINE, rate), 0.8)
		S.mul(cic, S.wander(dur, 1.5, 0.1, 1.0, r))
		S.add(b, cic, 0.5 - k * 0.2)
	var t := r.randf_range(0.5, 2.0)
	while t < dur - 1.0:
		var len_s := r.randf_range(0.3, 0.7)
		var g := S.filter(S.noise(len_s, r), S.Filter.BANDPASS, [Vector2(0, 7000)], 2.0)
		S.mul(g, pulses_simple(len_s, r.randf_range(14.0, 20.0)))
		S.env(g, [Vector2(0, 0), Vector2(0.05, 1.0), Vector2(len_s - 0.05, 1.0), Vector2(len_s, 0)])
		S.add(b, g, r.randf_range(0.1, 0.25), S.samples(t))
		t += r.randf_range(1.5, 4.0)
	var fly_t := r.randf_range(1.0, dur - 3.0)
	var fly_len := 1.6
	var f := r.randf_range(180.0, 230.0)
	var fly := S.osc(fly_len, S.Wave.SAW, [Vector2(0, f * 1.04), Vector2(fly_len, f * 0.96)])
	S.lp(fly, 2500.0)
	S.modulate(fly, S.lp(S.noise(fly_len, r), 15.0), 3.0)
	S.env(fly, [Vector2(0, 0), Vector2(fly_len * 0.5, 1.0), Vector2(fly_len, 0)])
	S.hp(fly, 150.0)
	S.add(b, fly, 0.006, S.samples(fly_t))
	return b


static func pulses_simple(dur: float, rate: float) -> PackedFloat32Array:
	var b := S.tone(dur, S.Wave.SINE, rate)
	for i in b.size():
		b[i] = maxf(0.0, b[i])
	return b


## Foliage rustling in the breeze; density and brightness swell with gusts.
static func _leaves(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var gust := S.wander(dur, 0.8, 0.15, 1.0, r)
	var b := S.grains(dur, int(dur * 900), r, 1500.0, 9500.0, 0.0002, 0.0008, 1.0)
	S.mul(b, gust)
	S.normalize(b, 0.6)
	var body := S.filter(S.pink(dur, r), S.Filter.BANDPASS, [Vector2(0, 3200)], 0.6)
	S.mul(body, gust)
	S.normalize(body, 0.3)
	return S.add(b, body, 1.0)


# --- Water -------------------------------------------------------------------------

## Surf on a shore: swells break, foam fizzes, backwash drags pebbles.
static func _ocean(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.lp(S.pink(dur, r), 500.0)
	S.mul(b, S.wander(dur, 2.0, 0.5, 1.0, r))
	S.normalize(b, 0.2)
	var waves := 2
	for w in waves:
		var t0 := (w + r.randf_range(0.0, 0.4)) * dur / waves
		var len_s := 5.0
		var swell := S.filter(S.pink(len_s, r), S.Filter.LOWPASS, [Vector2(0, 250), Vector2(1.6, 1800), Vector2(len_s, 400)], 0.7)
		S.env(swell, [Vector2(0, 0), Vector2(1.5, 0.7), Vector2(1.7, 1.0), Vector2(2.6, 0.5), Vector2(len_s, 0)])
		S.normalize(swell, 0.6)
		var foam := S.grains(len_s, 2200, r, 2500.0, 10000.0, 0.0002, 0.0008, 1.0)
		S.env(foam, [Vector2(0, 0), Vector2(1.6, 0.0), Vector2(2.0, 1.0), Vector2(len_s, 0)])
		S.normalize(foam, 0.35)
		var pebbles := S.grains(len_s, 300, r, 1000.0, 4000.0, 0.0008, 0.002, 1.0)
		S.env(pebbles, [Vector2(0, 0), Vector2(3.0, 0.0), Vector2(3.6, 1.0), Vector2(len_s, 0)])
		S.normalize(pebbles, 0.2)
		S.add(swell, foam, 1.0)
		S.add(swell, pebbles, 1.0)
		S.add(b, swell, r.randf_range(0.7, 1.0), S.samples(t0), true)
	return b


static func _underwater(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.lp(S.brown(dur, r), 120.0)
	S.normalize(b, 0.6)
	var swell := S.lp(S.pink(dur, r), 450.0)
	S.mul(swell, S.wander(dur, 1.5, 0.2, 1.0, r))
	S.normalize(swell, 0.2)
	S.add(b, swell, 1.0)
	var t := r.randf_range(0.5, 2.0)
	while t < dur - 1.5:
		var f := r.randf_range(300.0, 700.0)
		for k in r.randi_range(5, 12):
			S.bubble(b, t + k * r.randf_range(0.05, 0.12), f * r.randf_range(0.8, 1.5), 0.08, r.randf_range(0.006, 0.015), 0.6)
		t += r.randf_range(2.0, 4.0)
	return S.lowpass1(b, 1500.0)
