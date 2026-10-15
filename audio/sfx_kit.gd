extends RefCounted
## Shared building blocks for the SFX recipes (sfx_library / sfx_creatures /
## sfx_nature): cleaned-up recordings and common synthesised layers.

const S := preload("res://audio/synth.gd")
const SB := preload("res://audio/sample_bank.gd")
const KI := "kenney_impact/"
const KR := "kenney_rpg/"


## A recording, cleaned of rumble / DC, optionally cut to `max_sec`.
static func smp(file: String, rate := 1.0, max_sec := 0.0, hp_hz := 45.0) -> PackedFloat32Array:
	var b := SB.mono(file, rate)
	if b.is_empty():
		return S.make(0.05)
	# Start at the onset (recordings carry up to ~50 ms of lead-in), so layers
	# line up and footsteps land on the animation frame.
	var thr := S.peak(b) * 0.03
	var on := 0
	while on < b.size() and absf(b[on]) < thr:
		on += 1
	on = maxi(0, on - S.samples(0.002))
	if on > 0:
		b = b.slice(on)
		S.fade(b, 0.002, 0.0)
	if max_sec > 0.0 and b.size() > S.samples(max_sec):
		b = b.slice(0, S.samples(max_sec))
		S.fade(b, 0.0, minf(0.06, max_sec * 0.3))
	if hp_hz > 0.0:
		S.hp(b, hp_hz)
	S.normalize(b, 0.9)
	return b


## One of the five numbered takes of a Kenney impact recording.
static func ki(prefix: String, idx: int, rate := 1.0, max_sec := 0.0, hp_hz := 45.0) -> PackedFloat32Array:
	return smp(KI + "%s_%03d.ogg" % [prefix, posmod(idx, 5)], rate, max_sec, hp_hz)


## Decaying sine sweep: body thumps and sub-drops.
static func thump(dur: float, f0: float, f1: float, tau: float, sweep := 0.08) -> PackedFloat32Array:
	return S.decay(S.osc(dur, S.Wave.SINE, [Vector2(0, f0), Vector2(sweep, f1)]), 0.0015, tau)


## Very short broadband transient (the "tick" at the start of any hard contact).
static func click(r: RandomNumberGenerator, tau: float, hp_hz: float, dur := 0.04) -> PackedFloat32Array:
	return S.hp(S.decay(S.noise(dur, r), 0.0002, tau), hp_hz)


## Swept band of pink noise with an amplitude envelope.
static func whoosh(r: RandomNumberGenerator, dur: float, freq: Array, q: float, shape: Array) -> PackedFloat32Array:
	var b := S.filter(S.pink(dur, r), S.Filter.BANDPASS, freq, q)
	return S.env(b, shape)


## Mix layers [buffer, gain, offset_sec] into a new buffer long enough for all.
static func mix(layers: Array) -> PackedFloat32Array:
	var n := 1
	for l: Array in layers:
		n = maxi(n, (l[0] as PackedFloat32Array).size() + S.samples(float(l[2]) if l.size() > 2 else 0.0))
	var out := PackedFloat32Array()
	out.resize(n)
	for l: Array in layers:
		var off := S.samples(float(l[2])) if l.size() > 2 and float(l[2]) > 0.0 else 0
		S.add(out, l[0], float(l[1]), off)
	return out


static func jit(r: RandomNumberGenerator, amount := 0.06) -> float:
	return r.randf_range(1.0 - amount, 1.0 + amount)


## Fine grit under the sole: a whisper of tiny high cracks.
static func grit(r: RandomNumberGenerator, dur: float, count: int, lo := 2500.0, hi := 9000.0) -> PackedFloat32Array:
	return S.grains(dur, count, r, lo, hi, 0.0003, 0.0012, 1.8, dur * 0.4)


## Cut trailing silence (cheap; keeps everything above -70 dB of the peak).
static func trim(b: PackedFloat32Array) -> PackedFloat32Array:
	var thr := S.peak(b) * 0.0003
	var end := b.size() - 1
	while end > 0 and absf(b[end]) < thr:
		end -= 1
	return b.slice(0, mini(b.size(), end + 2))
