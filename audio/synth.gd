class_name Synth
extends RefCounted
## A small offline DSP toolkit. Everything works on mono PackedFloat32Array
## buffers at SR Hz and is thread-safe (no shared state), so sounds can be
## rendered on worker threads.
##
## Frequency / gain envelopes are given as point lists: Array of Vector2
## (time in seconds, value), interpolated linearly for gains and
## exponentially for frequencies.

## 32 kHz keeps the "air" of footsteps, swishes and rain (content up to 16 kHz)
## at two thirds of the cost of 48 kHz. Recorded samples are decoded at this
## rate too (SampleBank), so layers can be mixed sample-exactly.
const SR := 32000

enum Filter { LOWPASS, HIGHPASS, BANDPASS, PEAK, LOWSHELF, HIGHSHELF }
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

## Noise sources slice long pre-rendered tables at a random offset (a native
## copy, so a second of noise costs microseconds instead of a GDScript loop).
## Tables are 12 s: far longer than any repetition a listener could notice in
## noise, and filtered differently wherever they are used.
const TABLE_SEC := 12.0

static var _tables := {}
static var _table_lock := Mutex.new()


static func _table(kind: String) -> PackedFloat32Array:
	_table_lock.lock()
	if not _tables.has(kind):
		var r := RandomNumberGenerator.new()
		r.seed = hash(kind) + 4242
		var n := int(TABLE_SEC * SR)
		var b := PackedFloat32Array()
		b.resize(n)
		match kind:
			"white":
				for i in n:
					b[i] = r.randf_range(-1.0, 1.0)
			"brown":
				var v := 0.0
				for i in n:
					v = v * 0.985 + r.randf_range(-1.0, 1.0) * 0.12
					b[i] = v
			"pink":
				var b0 := 0.0
				var b1 := 0.0
				var b2 := 0.0
				var b3 := 0.0
				var b4 := 0.0
				var b5 := 0.0
				var b6 := 0.0
				for i in n:
					var w := r.randf_range(-1.0, 1.0)
					b0 = 0.99886 * b0 + w * 0.0555179
					b1 = 0.99332 * b1 + w * 0.0750759
					b2 = 0.96900 * b2 + w * 0.1538520
					b3 = 0.86650 * b3 + w * 0.3104856
					b4 = 0.55000 * b4 + w * 0.5329522
					b5 = -0.7616 * b5 - w * 0.0168980
					b[i] = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362) * 0.11
					b6 = w * 0.115926
		_tables[kind] = b
	var t: PackedFloat32Array = _tables[kind]
	_table_lock.unlock()
	return t


static func _from_table(kind: String, sec: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var t := _table(kind)
	var n := samples(sec)
	var out := PackedFloat32Array()
	var at := r.randi_range(0, t.size() - 1)
	while out.size() < n:
		var take := mini(n - out.size(), t.size() - at)
		out.append_array(t.slice(at, at + take))
		at = 0
	# Random polarity: twice the variety from the same table.
	if r.randf() < 0.5:
		gain(out, -1.0)
	return out


static func noise(sec: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	return _from_table("white", sec, r)


## Brown-ish (integrated, leaky) noise: deep rumbles.
static func brown(sec: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	return _from_table("brown", sec, r)


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
	var seg := 1
	while i < n:
		var fs := _env_exp_seg(freq_points, float(i) / SR, seg)
		seg = int(fs.y)
		var dt := fs.x / SR
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


## _env_exp for increasing t: `seg` is the segment index found by the previous
## call (start with 1). Returns (value, segment).
static func _env_exp_seg(points: Array, t: float, seg: int) -> Vector2:
	var n := points.size()
	var first: Vector2 = points[0]
	if n == 1 or t <= first.x:
		return Vector2(first.y, 1)
	var s := maxi(seg, 1)
	while s < n and t > (points[s] as Vector2).x:
		s += 1
	if s >= n:
		return Vector2((points[n - 1] as Vector2).y, n)
	var p: Vector2 = points[s]
	var q: Vector2 = points[s - 1]
	var span := p.x - q.x
	var f := (t - q.x) / span if span > 0.0 else 1.0
	return Vector2(q.y * pow(p.y / q.y, f), s)


## Multiply by a piecewise-linear gain envelope (one linear ramp per segment).
static func env(b: PackedFloat32Array, points: Array) -> PackedFloat32Array:
	var n := b.size()
	if points.is_empty():
		return b
	var i := 0
	var first: Vector2 = points[0]
	var end0 := mini(n, int(first.x * SR))
	while i < end0:
		b[i] *= first.y
		i += 1
	for k in range(1, points.size()):
		var p: Vector2 = points[k]
		var q: Vector2 = points[k - 1]
		var end := mini(n, int(p.x * SR))
		var span := (p.x - q.x) * SR
		if end <= i:
			continue
		var g := q.y + (p.y - q.y) * ((float(i) - q.x * SR) / span if span > 0.0 else 1.0)
		var dg := (p.y - q.y) / span if span > 0.0 else 0.0
		while i < end:
			b[i] *= g
			g += dg
			i += 1
	var last: Vector2 = points[points.size() - 1]
	while i < n:
		b[i] *= last.y
		i += 1
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
## `gain_db` is used by the PEAK / LOWSHELF / HIGHSHELF types.
static func filter(b: PackedFloat32Array, type: Filter, freq_points: Array, q := 0.707, gain_db := 0.0) -> PackedFloat32Array:
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
	var seg := 1
	for i in n:
		if i % 32 == 0 and (i == 0 or not constant):
			var fs := _env_exp_seg(freq_points, float(i) / SR, seg)
			seg = int(fs.y)
			var f := clampf(fs.x, 20.0, SR * 0.45)
			var w := TAU * f / SR
			var cw := cos(w)
			var alpha := sin(w) / (2.0 * q)
			var a0 := 1.0 + alpha
			a1 = -2.0 * cw
			a2 = 1.0 - alpha
			match type:
				Filter.LOWPASS:
					b0 = (1.0 - cw) * 0.5
					b1 = 1.0 - cw
					b2 = b0
				Filter.HIGHPASS:
					b0 = (1.0 + cw) * 0.5
					b1 = -(1.0 + cw)
					b2 = b0
				Filter.BANDPASS:
					b0 = alpha
					b1 = 0.0
					b2 = -alpha
				Filter.PEAK:
					var pa := pow(10.0, gain_db / 40.0)
					b0 = 1.0 + alpha * pa
					b1 = -2.0 * cw
					b2 = 1.0 - alpha * pa
					a0 = 1.0 + alpha / pa
					a2 = 1.0 - alpha / pa
				Filter.LOWSHELF, Filter.HIGHSHELF:
					var sa := pow(10.0, gain_db / 40.0)
					var sq := 2.0 * sqrt(sa) * alpha
					var sgn := 1.0 if type == Filter.LOWSHELF else -1.0
					b0 = sa * ((sa + 1.0) - sgn * (sa - 1.0) * cw + sq)
					b1 = sgn * 2.0 * sa * ((sa - 1.0) - sgn * (sa + 1.0) * cw)
					b2 = sa * ((sa + 1.0) - sgn * (sa - 1.0) * cw - sq)
					a0 = (sa + 1.0) + sgn * (sa - 1.0) * cw + sq
					a1 = -sgn * 2.0 * ((sa - 1.0) + sgn * (sa + 1.0) * cw)
					a2 = (sa + 1.0) + sgn * (sa - 1.0) * cw - sq
			b0 /= a0
			b1 /= a0
			b2 /= a0
			a1 /= a0
			a2 /= a0
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


## Parametric EQ band (dB). Shelves use q as their slope (0.707 = gentle).
static func peq(b: PackedFloat32Array, f: float, gain_db: float, q := 1.0) -> PackedFloat32Array:
	return filter(b, Filter.PEAK, [Vector2(0, f)], q, gain_db)


static func low_shelf(b: PackedFloat32Array, f: float, gain_db: float) -> PackedFloat32Array:
	return filter(b, Filter.LOWSHELF, [Vector2(0, f)], 0.707, gain_db)


static func high_shelf(b: PackedFloat32Array, f: float, gain_db: float) -> PackedFloat32Array:
	return filter(b, Filter.HIGHSHELF, [Vector2(0, f)], 0.707, gain_db)


# --- Physical-ish building blocks ------------------------------------------------

## Pink noise (Paul Kellet's refined filter): natural spectral tilt for wind,
## water and air.
static func pink(sec: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	return _from_table("pink", sec, r)


## Slowly wandering control signal in [lo, hi] (smoothed random walk), sampled
## every `step` seconds and linearly interpolated: gusts, swells, intensity.
static func wander(sec: float, step: float, lo: float, hi: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var pts := []
	var t := 0.0
	var v := r.randf_range(lo, hi)
	while t <= sec + step:
		pts.append(Vector2(t, v))
		v = clampf(v + r.randf_range(-0.5, 0.5) * (hi - lo), lo, hi)
		t += step * r.randf_range(0.6, 1.4)
	var b := make(sec)
	b.fill(1.0)
	env(b, pts)
	return b


## Multiply b by a control buffer (sample by sample).
static func mul(b: PackedFloat32Array, m: PackedFloat32Array) -> PackedFloat32Array:
	for i in mini(b.size(), m.size()):
		b[i] *= m[i]
	return b


## Modal synthesis: the excitation `src` rings a bank of two-pole resonators
## (frequency Hz, decay time constant s, amplitude). Struck wood, metal,
## stone and bone are each a handful of such modes.
static func modal(src: PackedFloat32Array, freqs: Array, taus: Array, amps: Array, length := 0.0) -> PackedFloat32Array:
	var n := maxi(src.size(), samples(length))
	var out := PackedFloat32Array()
	out.resize(n)
	var m := src.size()
	for k in freqs.size():
		var f: float = freqs[k]
		if f >= SR * 0.45 or f <= 10.0:
			continue
		var rad := exp(-1.0 / (float(taus[k]) * SR))
		var c1 := 2.0 * rad * cos(TAU * f / SR)
		var c2 := -rad * rad
		# Normalise so a unit impulse peaks near `amp` whatever the decay.
		var g: float = float(amps[k]) * (1.0 - rad) * 2.0
		var y1 := 0.0
		var y2 := 0.0
		var quiet := 0
		for i in n:
			var x := src[i] if i < m else 0.0
			var y := x * g + c1 * y1 + c2 * y2
			y2 = y1
			y1 = y
			out[i] += y
			if i >= m:
				if absf(y) < 1e-6:
					quiet += 1
					if quiet > 64:
						break
				else:
					quiet = 0
	return out


## A cloud of tiny resonant "cracks": each grain is a noise click ringing a
## random band. Grain times follow `shape` (exponent on a uniform variable: >1
## crowds them early). Snow crunch, gravel, crumbling rock, crackling fire,
## leaves, splinters, rain ticks.
static func grains(dur: float, count: int, r: RandomNumberGenerator, f_lo: float, f_hi: float,
		tau_lo := 0.002, tau_hi := 0.01, shape := 1.0, amp_decay := 0.0, start := 0.0) -> PackedFloat32Array:
	var b := make(dur)
	var n := b.size()
	for g in count:
		var u := pow(r.randf(), shape)
		var t0 := start + u * (dur - start)
		var i0 := int(t0 * SR)
		if i0 >= n - 2:
			continue
		var f := exp(r.randf_range(log(f_lo), log(f_hi)))
		var tau := r.randf_range(tau_lo, tau_hi)
		var amp := r.randf_range(0.3, 1.0)
		if amp_decay > 0.0:
			amp *= exp(-(t0 - start) / amp_decay)
		var rad := exp(-1.0 / (tau * SR))
		var c1 := 2.0 * rad * cos(TAU * f / SR)
		var c2 := -rad * rad
		var y1 := 0.0
		var y2 := 0.0
		var glen := mini(int(tau * SR * 6.0) + 8, n - i0)
		var kick := 3 + r.randi_range(0, 4)
		var gain_k := amp * (1.0 - rad) * 2.0
		for i in glen:
			var x := r.randf_range(-1.0, 1.0) * gain_k if i < kick else 0.0
			var y := x + c1 * y1 + c2 * y2
			y2 = y1
			y1 = y
			b[i0 + i] += y
	return b


## Air-bubble "plink" (Minnaert resonance): a decaying sine whose pitch rises
## as the bubble nears the surface. Written into dst at t0.
static func bubble(dst: PackedFloat32Array, t0: float, f0: float, amp: float, tau: float, rise := 0.1) -> void:
	var i0 := int(t0 * SR)
	var n := mini(int(tau * 7.0 * SR), dst.size() - i0)
	if n <= 0 or i0 < 0:
		return
	var g := amp
	var k := exp(-1.0 / (tau * SR))
	var att := maxi(1, int(0.0006 * SR))
	# Phasor rotation, the step re-tuned every 32 samples as the pitch rises.
	var sn := 0.0
	var cs := 1.0
	var i := 0
	while i < n:
		var w := TAU * f0 * (1.0 + rise * (float(i) / SR) / tau) / SR
		var cw := cos(w)
		var sw := sin(w)
		var end := mini(i + 32, n)
		while i < end:
			var ns := sn * cw + cs * sw
			cs = cs * cw - sn * sw
			sn = ns
			dst[i0 + i] += sn * (g if i >= att else g * float(i) / att)
			g *= k
			i += 1


## Resample by linear interpolation: ratio > 1 raises pitch and shortens.
static func resample(b: PackedFloat32Array, ratio: float) -> PackedFloat32Array:
	var n := maxi(1, int(b.size() / ratio))
	var out := PackedFloat32Array()
	out.resize(n)
	var last := b.size() - 1
	for i in n:
		var p := i * ratio
		var j := int(p)
		if j >= last:
			out[i] = b[last]
		else:
			var f := p - j
			out[i] = b[j] + (b[j + 1] - b[j]) * f
	return out


## Shift a buffer later by `sec` (pads with silence; keeps the length + shift).
static func delayed(b: PackedFloat32Array, sec: float) -> PackedFloat32Array:
	var out := make(seconds(b.size()) + sec)
	return add(out, b, 1.0, samples(sec) if sec > 0.0 else 0)


## Short-term loudness: the loudest 50 ms RMS window (linear).
static func loudness(b: PackedFloat32Array) -> float:
	var w := mini(samples(0.05), b.size())
	var acc := 0.0
	for i in w:
		acc += b[i] * b[i]
	var best := acc
	for i in range(w, b.size()):
		acc += b[i] * b[i] - b[i - w] * b[i - w]
		if acc > best:
			best = acc
	return sqrt(maxf(best, 0.0) / w)


## Bring a finished sound to a short-term loudness target (dBFS), never letting
## the peak exceed `ceiling`; very peaky material is gently soft-limited first
## so impacts are not left far quieter than their body suggests.
static func level(b: PackedFloat32Array, target_db: float, ceiling := 0.94) -> PackedFloat32Array:
	var l := loudness(b)
	if l < 1e-7:
		return b
	gain(b, db_to_linear(target_db) / l)
	var p := peak(b)
	if p <= ceiling:
		return b
	# At most ~3 dB of transient rounding by a soft knee; beyond that, gain.
	var allowed := ceiling * 1.4
	if p > allowed:
		gain(b, allowed / p)
	var t := ceiling * 0.7
	var span := ceiling - t
	for i in b.size():
		var a := absf(b[i])
		if a > t:
			b[i] = signf(b[i]) * (t + span * tanh((a - t) / span))
	return b


## Trim trailing near-silence (below `floor_db` relative to the peak) and fade
## the new end, so long sample tails and reverb dregs do not waste voices.
static func trim_tail(b: PackedFloat32Array, floor_db := -60.0, fade_sec := 0.02) -> PackedFloat32Array:
	var thr := peak(b) * db_to_linear(floor_db)
	var end := b.size() - 1
	while end > 0 and absf(b[end]) < thr:
		end -= 1
	var keep := mini(b.size(), end + samples(fade_sec))
	var out := b.slice(0, keep)
	return fade(out, 0.0, fade_sec)


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
	var a := mini(samples(fade_in), n) if fade_in > 0.0 else 0
	var z := mini(samples(fade_out), n) if fade_out > 0.0 else 0
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
## kept, so the tail flows into the start. The reverberator runs at SR / 2
## (it is low-passed by its damping anyway), halving its cost; delay lengths
## are scaled so rooms keep the size they were tuned at (22.05 kHz).
static func reverb(b: PackedFloat32Array, room := 0.78, damp := 0.35, wet := 0.25, wrap := false) -> PackedFloat32Array:
	var d := 2 if SR >= 30000 else 1
	var scale := float(SR) / d / 22050.0
	var l0 := int(557 * scale)
	var l1 := int(593 * scale)
	var l2 := int(641 * scale)
	var l3 := int(677 * scale)
	var la := int(277 * scale)
	var lb := int(223 * scale)
	var c0 := PackedFloat32Array()
	c0.resize(l0)
	var c1 := PackedFloat32Array()
	c1.resize(l1)
	var c2 := PackedFloat32Array()
	c2.resize(l2)
	var c3 := PackedFloat32Array()
	c3.resize(l3)
	var ap0 := PackedFloat32Array()
	ap0.resize(la)
	var ap1 := PackedFloat32Array()
	ap1.resize(lb)
	var n := b.size()
	var m := (n + d - 1) / d
	var x := PackedFloat32Array()
	x.resize(m)
	var k := 0.2 / d
	for i in m:
		var acc := 0.0
		for j in d:
			var idx := i * d + j
			if idx < n:
				acc += b[idx]
		x[i] = acc * k
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
	var y := PackedFloat32Array()
	y.resize(m)
	for _pass in (2 if wrap else 1):
		for i in m:
			var xi := x[i]
			var y0 := c0[i0]
			f0 = y0 * keep + f0 * damp
			c0[i0] = xi + f0 * room
			i0 += 1
			if i0 == l0:
				i0 = 0
			var y1 := c1[i1]
			f1 = y1 * keep + f1 * damp
			c1[i1] = xi + f1 * room
			i1 += 1
			if i1 == l1:
				i1 = 0
			var y2 := c2[i2]
			f2 = y2 * keep + f2 * damp
			c2[i2] = xi + f2 * room
			i2 += 1
			if i2 == l2:
				i2 = 0
			var y3 := c3[i3]
			f3 = y3 * keep + f3 * damp
			c3[i3] = xi + f3 * room
			i3 += 1
			if i3 == l3:
				i3 = 0
			var acc := y0 + y1 + y2 + y3
			var a0 := ap0[j0]
			ap0[j0] = acc + a0 * 0.5
			acc = a0 - acc
			j0 += 1
			if j0 == la:
				j0 = 0
			var a1 := ap1[j1]
			ap1[j1] = acc + a1 * 0.5
			acc = a1 - acc
			j1 += 1
			if j1 == lb:
				j1 = 0
			y[i] = acc
	var dry := 1.0 - wet * 0.5
	if d == 1:
		for i in n:
			b[i] = b[i] * dry + y[i] * wet
		return b
	var inv := 1.0 / d
	for i in n:
		var p := i * inv
		var j := int(p)
		var fr := p - j
		var v := y[j]
		if j + 1 < m:
			v += (y[j + 1] - v) * fr
		elif wrap:
			v += (y[0] - v) * fr
		b[i] = b[i] * dry + v * wet
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
