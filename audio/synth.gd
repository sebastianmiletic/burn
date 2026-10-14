class_name Synth
extends RefCounted
## A small offline DSP toolkit. Everything works on mono PackedFloat32Array
## buffers at SR Hz and is thread-safe (no shared state), so sounds can be
## rendered on worker threads.
##
## Frequency / gain envelopes are given as point lists: Array of Vector2
## (time in seconds, value), interpolated linearly for gains and
## exponentially for frequencies.

const SR := 22050

enum Filter { LOWPASS, HIGHPASS, BANDPASS }
enum Wave { SINE, SAW, SQUARE, TRIANGLE }


static func seconds(n: int) -> float:
	return float(n) / SR


static func samples(sec: float) -> int:
	return maxi(1, int(sec * SR))


static func make(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(samples(sec))
	return b


static func rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


# --- Sources -------------------------------------------------------------------

static func noise(sec: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := make(sec)
	for i in b.size():
		b[i] = r.randf_range(-1.0, 1.0)
	return b


## Brown-ish (integrated, leaky) noise: deep rumbles.
static func brown(sec: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := make(sec)
	var v := 0.0
	for i in b.size():
		v = v * 0.985 + r.randf_range(-1.0, 1.0) * 0.12
		b[i] = v
	return b


## Sparse random impulses with a given density (per second): crackle, grit.
static func dust(sec: float, density: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := make(sec)
	var p := density / SR
	for i in b.size():
		if r.randf() < p:
			b[i] = r.randf_range(-1.0, 1.0)
	return b


## Oscillator with a frequency envelope (exponential interpolation, evaluated
## every 64 samples), band-limited with an inline polyBLEP.
static func osc(sec: float, wave: Wave, freq_points: Array, phase := 0.0) -> PackedFloat32Array:
	var b := make(sec)
	var n := b.size()
	var ph := phase
	var i := 0
	while i < n:
		var dt := _env_exp(freq_points, float(i) / SR) / SR
		var end := mini(i + 64, n)
		match wave:
			Wave.SINE:
				for j in range(i, end):
					ph += dt
					if ph >= 1.0:
						ph -= 1.0
					b[j] = sin(ph * TAU)
			Wave.SAW:
				for j in range(i, end):
					ph += dt
					if ph >= 1.0:
						ph -= 1.0
					var v := 2.0 * ph - 1.0
					if ph < dt:
						var t := ph / dt
						v -= t + t - t * t - 1.0
					elif ph > 1.0 - dt:
						var t := (ph - 1.0) / dt
						v -= t * t + t + t + 1.0
					b[j] = v
			Wave.SQUARE:
				for j in range(i, end):
					ph += dt
					if ph >= 1.0:
						ph -= 1.0
					b[j] = 1.0 if ph < 0.5 else -1.0
			Wave.TRIANGLE:
				for j in range(i, end):
					ph += dt
					if ph >= 1.0:
						ph -= 1.0
					b[j] = 1.0 - 4.0 * absf(ph - 0.5)
		i = end
	return b


## Constant-pitch tone: a few exact cycles are rendered once and tiled.
static func tone(sec: float, wave: Wave, freq: float, _phase := 0.0) -> PackedFloat32Array:
	return periodic(sec, wave, freq, Callable())


## A periodic voice: `cycles` of the waveform are rendered (optionally run
## through `process`, e.g. filters, until they reach steady state) and the
## last whole block is tiled to `sec`. Filtering a periodic signal gives a
## periodic signal, so this is exact, and costs a fraction of a second of
## processing however long the note is. If `loop_samples` > 0 the block length
## is chosen to divide it, so the tiled voice also loops seamlessly.
static func periodic(sec: float, wave: Wave, freq: float, process: Callable, loop_samples := 0) -> PackedFloat32Array:
	var n := samples(sec)
	var period := float(SR) / freq
	var best_len := maxi(2, roundi(period))
	var best_err := 1e9
	for k in range(1, 33):
		for candidate in [floori(period * k), ceili(period * k)]:
			var l: int = candidate
			if l < 2 or l > 16384:
				continue
			if loop_samples > 0 and loop_samples % l != 0:
				continue
			var err := absf(log(float(l) / (period * k)))
			if err < best_err - 1e-9:
				best_err = err
				best_len = l
	if best_err > 0.004 and loop_samples > 0:
		return periodic(sec, wave, freq, process, 0)  # no good divisor: accept a seam
	var cycles := maxi(1, roundi(best_len / period))
	var dt := float(cycles) / best_len
	# Render enough blocks for filters to settle (~0.12 s), keep the last.
	var blocks := 1 if not process.is_valid() else maxi(2, ceili(0.12 * SR / best_len) + 1)
	var raw := PackedFloat32Array()
	raw.resize(best_len * blocks)
	var ph := 0.0
	for i in raw.size():
		var v := 0.0
		match wave:
			Wave.SINE:
				v = sin(ph * TAU)
			Wave.SAW:
				v = 2.0 * ph - 1.0 - _blep(ph, dt)
			Wave.SQUARE:
				v = (1.0 if ph < 0.5 else -1.0) + _blep(ph, dt) - _blep(fmod(ph + 0.5, 1.0), dt)
			Wave.TRIANGLE:
				v = 1.0 - 4.0 * absf(ph - 0.5)
		raw[i] = v
		ph += dt
		if ph >= 1.0:
			ph -= 1.0
	if process.is_valid():
		raw = process.call(raw)
	var block := raw.slice(raw.size() - best_len)
	return tile(block, n)


## Repeat `block` to exactly n samples using native array copies.
static func tile(block: PackedFloat32Array, n: int) -> PackedFloat32Array:
	var out := block.duplicate()
	while out.size() < n:
		out.append_array(out)
	out.resize(n)
	return out


static func _blep(t: float, dt: float) -> float:
	if t < dt:
		t /= dt
		return t + t - t * t - 1.0
	if t > 1.0 - dt:
		t = (t - 1.0) / dt
		return t * t + t + t + 1.0
	return 0.0


## Struck metal / bell: inharmonic partials, each with its own decay.
static func bell(sec: float, freq: float, ratios: Array, amps: Array, decays: Array) -> PackedFloat32Array:
	var b := make(sec)
	for p in ratios.size():
		var f: float = freq * float(ratios[p])
		if f >= SR * 0.45:
			continue
		var a: float = amps[p]
		var k := exp(-1.0 / (float(decays[p]) * SR))
		var g := a
		var w := TAU * f / SR
		# Recursive sine oscillator: cheap and exact.
		var s0 := 0.0
		var s1 := sin(-w)
		var c := 2.0 * cos(w)
		for i in b.size():
			var s2 := c * s0 - s1
			s1 = s0
			s0 = s2
			b[i] += s1 * g
			g *= k
			if g < 1e-5:
				break
	return b


## Karplus-Strong plucked string.
static func pluck(sec: float, freq: float, damping: float, brightness: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := make(sec)
	var period := maxi(2, int(SR / freq))
	var line := PackedFloat32Array()
	line.resize(period)
	var prev := 0.0
	for i in period:
		# Pre-filtered excitation: brightness sets how harsh the attack is.
		var x := r.randf_range(-1.0, 1.0)
		prev = prev + (x - prev) * brightness
		line[i] = prev
	var idx := 0
	for i in b.size():
		var cur := line[idx]
		var nxt := line[(idx + 1) % period]
		line[idx] = (cur + nxt) * 0.5 * damping
		b[i] = cur
		idx = (idx + 1) % period
	return b


# --- Processing -------------------------------------------------------------------

static func _env_lin(points: Array, t: float) -> float:
	var n := points.size()
	if n == 0:
		return 1.0
	var first: Vector2 = points[0]
	if t <= first.x:
		return first.y
	for i in range(1, n):
		var p: Vector2 = points[i]
		if t <= p.x:
			var q: Vector2 = points[i - 1]
			var span := p.x - q.x
			return lerpf(q.y, p.y, (t - q.x) / span) if span > 0.0 else p.y
	return (points[n - 1] as Vector2).y


static func _env_exp(points: Array, t: float) -> float:
	var n := points.size()
	var first: Vector2 = points[0]
	if n == 1 or t <= first.x:
		return first.y
	for i in range(1, n):
		var p: Vector2 = points[i]
		if t <= p.x:
			var q: Vector2 = points[i - 1]
			var span := p.x - q.x
			var f := (t - q.x) / span if span > 0.0 else 1.0
			return q.y * pow(p.y / q.y, f)
	return (points[n - 1] as Vector2).y


## Multiply by a piecewise-linear gain envelope.
static func env(b: PackedFloat32Array, points: Array) -> PackedFloat32Array:
	var n := b.size()
	var step := 16
	var g0 := _env_lin(points, 0.0)
	for i in range(0, n, step):
		var g1 := _env_lin(points, float(mini(i + step, n)) / SR)
		var m := mini(step, n - i)
		for j in m:
			b[i + j] *= lerpf(g0, g1, float(j) / step)
		g0 = g1
	return b


## Attack then exponential decay (time constant tau seconds).
static func decay(b: PackedFloat32Array, attack: float, tau: float) -> PackedFloat32Array:
	var a := samples(attack)
	var k := exp(-1.0 / (tau * SR))
	var g := 1.0
	for i in b.size():
		if i < a:
			b[i] *= float(i) / a
		else:
			b[i] *= g
			g *= k
	return b


static func lowpass1(b: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var a := 1.0 - exp(-TAU * cutoff / SR)
	var y := 0.0
	for i in b.size():
		y += (b[i] - y) * a
		b[i] = y
	return b


static func highpass1(b: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var a := 1.0 - exp(-TAU * cutoff / SR)
	var y := 0.0
	for i in b.size():
		y += (b[i] - y) * a
		b[i] = b[i] - y
	return b


## RBJ biquad with a frequency envelope (coefficients refreshed every 32 samples).
static func filter(b: PackedFloat32Array, type: Filter, freq_points: Array, q := 0.707) -> PackedFloat32Array:
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var n := b.size()
	var constant := freq_points.size() == 1
	for i in n:
		if i % 32 == 0 and (i == 0 or not constant):
			var f := clampf(_env_exp(freq_points, float(i) / SR), 20.0, SR * 0.45)
			var w := TAU * f / SR
			var cw := cos(w)
			var alpha := sin(w) / (2.0 * q)
			var a0 := 1.0 + alpha
			match type:
				Filter.LOWPASS:
					b0 = (1.0 - cw) * 0.5 / a0
					b1 = (1.0 - cw) / a0
					b2 = b0
				Filter.HIGHPASS:
					b0 = (1.0 + cw) * 0.5 / a0
					b1 = -(1.0 + cw) / a0
					b2 = b0
				Filter.BANDPASS:
					b0 = alpha / a0
					b1 = 0.0
					b2 = -alpha / a0
			a1 = -2.0 * cw / a0
			a2 = (1.0 - alpha) / a0
		var x := b[i]
		var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		b[i] = y
	return b


static func lp(b: PackedFloat32Array, f: float, q := 0.707) -> PackedFloat32Array:
	return filter(b, Filter.LOWPASS, [Vector2(0, f)], q)


static func hp(b: PackedFloat32Array, f: float, q := 0.707) -> PackedFloat32Array:
	return filter(b, Filter.HIGHPASS, [Vector2(0, f)], q)


static func bp(b: PackedFloat32Array, f: float, q := 1.0) -> PackedFloat32Array:
	return filter(b, Filter.BANDPASS, [Vector2(0, f)], q)


## Parallel formant bank (vowel-like resonances) of a source signal.
static func formants(src: PackedFloat32Array, freqs: Array, gains: Array, q := 6.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(src.size())
	for f in freqs.size():
		var band := filter(src.duplicate(), Filter.BANDPASS, [Vector2(0, float(freqs[f]))], q)
		add(out, band, float(gains[f]))
	return out


static func gain(b: PackedFloat32Array, g: float) -> PackedFloat32Array:
	for i in b.size():
		b[i] *= g
	return b


## dst += src * g, starting at `offset` samples; wraps around when `wrap`.
static func add(dst: PackedFloat32Array, src: PackedFloat32Array, g := 1.0, offset := 0, wrap := false) -> PackedFloat32Array:
	var n := dst.size()
	if wrap:
		for i in src.size():
			var j := (offset + i) % n
			dst[j] += src[i] * g
	else:
		var m := mini(src.size(), n - offset)
		for i in range(maxi(0, -offset), m):
			dst[offset + i] += src[i] * g
	return dst


## Ring / amplitude modulation by another buffer (1 + depth * m).
static func modulate(b: PackedFloat32Array, m: PackedFloat32Array, depth: float) -> PackedFloat32Array:
	for i in mini(b.size(), m.size()):
		b[i] *= 1.0 + depth * m[i]
	return b


static func soft_clip(b: PackedFloat32Array, drive := 1.5) -> PackedFloat32Array:
	var norm := 1.0 / tanh(drive)
	for i in b.size():
		b[i] = tanh(b[i] * drive) * norm
	return b


static func peak(b: PackedFloat32Array) -> float:
	var m := 0.0
	for v in b:
		m = maxf(m, absf(v))
	return m


static func rms(b: PackedFloat32Array) -> float:
	var s := 0.0
	for v in b:
		s += v * v
	return sqrt(s / maxf(1.0, b.size()))


static func normalize(b: PackedFloat32Array, target := 0.89) -> PackedFloat32Array:
	var p := peak(b)
	if p > 1e-6:
		gain(b, target / p)
	return b


static func fade(b: PackedFloat32Array, fade_in: float, fade_out: float) -> PackedFloat32Array:
	var n := b.size()
	var a := mini(samples(fade_in), n)
	var z := mini(samples(fade_out), n)
	for i in a:
		b[i] *= float(i) / a
	for i in z:
		b[n - 1 - i] *= float(i) / z
	return b


## Remove DC offset (very low high-pass).
static func dc_block(b: PackedFloat32Array) -> PackedFloat32Array:
	var x1 := 0.0
	var y1 := 0.0
	for i in b.size():
		var x := b[i]
		var y := x - x1 + 0.995 * y1
		x1 = x
		y1 = y
		b[i] = y
	return b


## Schroeder reverb (4 combs, 2 allpasses, unrolled for speed). With `wrap`
## the buffer is treated as a loop: it is processed twice and the second pass
## kept, so the tail flows into the start.
static func reverb(b: PackedFloat32Array, room := 0.78, damp := 0.35, wet := 0.25, wrap := false) -> PackedFloat32Array:
	var c0 := PackedFloat32Array()
	c0.resize(557)
	var c1 := PackedFloat32Array()
	c1.resize(593)
	var c2 := PackedFloat32Array()
	c2.resize(641)
	var c3 := PackedFloat32Array()
	c3.resize(677)
	var ap0 := PackedFloat32Array()
	ap0.resize(277)
	var ap1 := PackedFloat32Array()
	ap1.resize(223)
	var i0 := 0
	var i1 := 0
	var i2 := 0
	var i3 := 0
	var j0 := 0
	var j1 := 0
	var f0 := 0.0
	var f1 := 0.0
	var f2 := 0.0
	var f3 := 0.0
	var keep := 1.0 - damp
	var n := b.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for _pass in (2 if wrap else 1):
		for i in n:
			var x := b[i] * 0.2
			var y0 := c0[i0]
			f0 = y0 * keep + f0 * damp
			c0[i0] = x + f0 * room
			i0 += 1
			if i0 == 557:
				i0 = 0
			var y1 := c1[i1]
			f1 = y1 * keep + f1 * damp
			c1[i1] = x + f1 * room
			i1 += 1
			if i1 == 593:
				i1 = 0
			var y2 := c2[i2]
			f2 = y2 * keep + f2 * damp
			c2[i2] = x + f2 * room
			i2 += 1
			if i2 == 641:
				i2 = 0
			var y3 := c3[i3]
			f3 = y3 * keep + f3 * damp
			c3[i3] = x + f3 * room
			i3 += 1
			if i3 == 677:
				i3 = 0
			var acc := y0 + y1 + y2 + y3
			var a0 := ap0[j0]
			ap0[j0] = acc + a0 * 0.5
			acc = a0 - acc
			j0 += 1
			if j0 == 277:
				j0 = 0
			var a1 := ap1[j1]
			ap1[j1] = acc + a1 * 0.5
			acc = a1 - acc
			j1 += 1
			if j1 == 223:
				j1 = 0
			out[i] = acc
	var dry := 1.0 - wet * 0.5
	for i in n:
		b[i] = b[i] * dry + out[i] * wet
	return b


## Feedback echo. With `wrap` the buffer is a loop and repeats flow into its start.
static func echo(b: PackedFloat32Array, delay_sec: float, feedback: float, wet: float, damp := 0.3, wrap := false) -> PackedFloat32Array:
	var d := samples(delay_sec)
	var line := PackedFloat32Array()
	line.resize(d)
	var n := b.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var j := 0
	var lpv := 0.0
	var keep := 1.0 - damp
	for _pass in (2 if wrap else 1):
		for i in n:
			var delayed := line[j]
			lpv += (delayed - lpv) * keep
			line[j] = b[i] + lpv * feedback
			j += 1
			if j == d:
				j = 0
			out[i] = delayed
	for i in n:
		b[i] += out[i] * wet
	return b


## Run `process` (Callable taking and returning a buffer) on a loop without a
## seam: the loop is processed twice in a row and the second copy kept.
static func process_loop(b: PackedFloat32Array, process: Callable) -> PackedFloat32Array:
	var n := b.size()
	var twice := b.duplicate()
	twice.append_array(b)
	twice = process.call(twice)
	return twice.slice(n, n * 2)


## Seamless loop: the `xfade` seconds after the loop end are blended over its
## start with an equal-power curve. Input must be `loop + xfade` long.
static func make_loop(b: PackedFloat32Array, loop_sec: float, xfade: float) -> PackedFloat32Array:
	var n := samples(loop_sec)
	var x := mini(samples(xfade), b.size() - n)
	var out := b.slice(0, n)
	for i in x:
		var t := float(i) / x
		out[i] = b[i] * sin(t * PI * 0.5) + b[n + i] * cos(t * PI * 0.5)
	return out


# --- Output ----------------------------------------------------------------------

static func to_bytes(b: PackedFloat32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(b.size() * 2)
	for i in b.size():
		bytes.encode_s16(i * 2, int(clampf(b[i], -1.0, 1.0) * 32767.0))
	return bytes


static func to_wav(bytes: PackedByteArray, loop: bool) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = bytes.size() / 2
	return w
