extends RefCounted
## SFX recipes for water, fire, weather, trees and foliage (see SfxLibrary).
## Water is a cloud of Minnaert bubbles over shaped noise; fire is turbulent
## low noise with flicker and crackle grains; thunder is a crack series over a
## rolling rumble.

const S := preload("res://audio/synth.gd")
const K := preload("res://audio/sfx_kit.gd")


# --- Water ---------------------------------------------------------------------

## Bubble cloud: `count` bubbles over [t0, t0 + span], radius spread via
## [f_lo, f_hi], earlier bubbles louder.
static func bubbles(b: PackedFloat32Array, r: RandomNumberGenerator, count: int, t0: float, span: float,
		f_lo: float, f_hi: float, amp: float, crowd := 1.5) -> void:
	for i in count:
		var u := pow(r.randf(), crowd)
		var f := exp(r.randf_range(log(f_lo), log(f_hi)))
		# Bigger (lower) bubbles ring longer.
		var tau := clampf(r.randf_range(2.5, 6.0) / f, 0.0015, 0.04)
		S.bubble(b, t0 + u * span, f, amp * r.randf_range(0.3, 1.0) * (1.0 - u * 0.6), tau, r.randf_range(0.05, 0.35))


## A body or object hitting water. size 0.45 = pebble / hand, 1 = body.
static func splash(r: RandomNumberGenerator, size: float) -> PackedFloat32Array:
	var dur := 0.45 + 0.6 * size
	var slap := S.lp(S.decay(S.noise(0.12, r), 0.0004, 0.01 + 0.02 * size), 6000.0)
	var body := S.filter(S.pink(dur, r), S.Filter.LOWPASS, [Vector2(0, 4000), Vector2(dur, 700)], 0.8)
	S.env(body, [Vector2(0, 0), Vector2(0.008, 1.0), Vector2(0.06 + 0.12 * size, 0.35), Vector2(dur, 0)])
	var spray := S.hp(S.pink(dur, r), 3000.0)
	S.env(spray, [Vector2(0, 0), Vector2(0.01, 1.0), Vector2(0.1 + 0.15 * size, 0.2), Vector2(dur, 0)])
	var b := K.mix([[slap, 0.8, 0.0], [body, 0.7, 0.0], [spray, 0.3, 0.0]])
	# The cavity closing ("plunk"), then the bubble cloud and droplets falling back.
	S.bubble(b, 0.01 + 0.02 * size, r.randf_range(280.0, 420.0) / sqrt(size), 0.7, 0.012 + 0.012 * size, 0.6)
	bubbles(b, r, int(18 + 40 * size), 0.02, dur * 0.6, 500.0 / sqrt(size), 2600.0, 0.22)
	bubbles(b, r, int(6 + 14 * size), 0.15 + 0.1 * size, dur * 0.6, 1400.0, 4200.0, 0.12, 1.0)
	return b


static func splash_big(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 2.4
	var boom := K.thump(0.8, 75.0, 38.0, 0.18, 0.2)
	var body := S.filter(S.pink(dur, r), S.Filter.LOWPASS, [Vector2(0, 6000), Vector2(0.4, 2000), Vector2(dur, 400)], 0.7)
	S.env(body, [Vector2(0, 0), Vector2(0.015, 1.0), Vector2(0.4, 0.5), Vector2(dur, 0)])
	var rainback := S.grains(dur, 260, r, 1500.0, 7000.0, 0.0006, 0.002, 1.0, 0.0, 0.3)
	S.env(rainback, [Vector2(0, 0), Vector2(0.3, 0.0), Vector2(0.6, 1.0), Vector2(dur, 0)])
	var b := K.mix([[boom, 0.8, 0.0], [body, 0.9, 0.0], [rainback, 0.4, 0.0], [splash(r, 1.0), 0.6, 0.02]])
	S.bubble(b, 0.03, r.randf_range(110.0, 160.0), 0.8, 0.05, 0.5)
	bubbles(b, r, 140, 0.03, 1.4, 160.0, 1600.0, 0.25)
	return S.reverb(b, 0.75, 0.5, 0.15)


## Wading: legs pushing through shallow water.
static func wade(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := r.randf_range(0.5, 0.65)
	var swish := K.whoosh(r, dur, [Vector2(0, 500), Vector2(dur * 0.4, 1300), Vector2(dur, 600)], 0.9,
			[Vector2(0, 0), Vector2(dur * 0.3, 1.0), Vector2(dur, 0)])
	var slosh := S.lp(S.pink(dur, r), 600.0)
	S.modulate(slosh, S.tone(dur, S.Wave.SINE, r.randf_range(5.0, 8.0)), 0.6)
	S.env(slosh, [Vector2(0, 0), Vector2(dur * 0.3, 1.0), Vector2(dur, 0)])
	var b := K.mix([[swish, 0.8, 0.0], [slosh, 0.6, 0.0]])
	bubbles(b, r, r.randi_range(12, 22), 0.05, dur * 0.7, 500.0, 2000.0, 0.2, 1.0)
	bubbles(b, r, r.randi_range(4, 9), dur * 0.4, dur * 0.5, 1500.0, 4000.0, 0.1, 1.0)
	return b


static func wave_crash(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 3.2
	var swell := S.filter(S.pink(dur, r), S.Filter.LOWPASS, [Vector2(0, 250), Vector2(0.7, 1800), Vector2(dur, 500)], 0.8)
	S.env(swell, [Vector2(0, 0), Vector2(0.65, 0.6), Vector2(0.75, 0.2), Vector2(dur, 0)])
	var crash := S.filter(S.pink(dur, r), S.Filter.LOWPASS, [Vector2(0, 9000), Vector2(dur, 1200)], 0.7)
	S.env(crash, [Vector2(0, 0), Vector2(0.7, 0.0), Vector2(0.74, 1.0), Vector2(1.4, 0.5), Vector2(dur, 0)])
	var foam := S.grains(dur, 900, r, 2500.0, 10000.0, 0.0003, 0.0012, 1.0)
	S.env(foam, [Vector2(0, 0), Vector2(0.72, 0.0), Vector2(0.9, 1.0), Vector2(dur, 0)])
	var boom := S.delayed(K.thump(0.9, 70.0, 35.0, 0.2, 0.2), 0.72)
	var b := K.mix([[swell, 0.6, 0.0], [crash, 1.0, 0.0], [foam, 0.35, 0.0], [boom, 0.7, 0.0]])
	bubbles(b, r, 60, 0.75, 1.6, 300.0, 2500.0, 0.12, 1.2)
	return S.reverb(b, 0.7, 0.5, 0.12)


## A geyser of water: a rising roar, sustained turbulent jet, then rain-back.
static func water_spout(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 3.4
	var jet := S.filter(S.pink(dur, r), S.Filter.BANDPASS, [Vector2(0, 300), Vector2(0.5, 1800), Vector2(2.0, 1400), Vector2(dur, 500)], 0.7)
	S.mul(jet, S.wander(dur, 0.05, 0.6, 1.0, r))
	S.env(jet, [Vector2(0, 0), Vector2(0.45, 1.0), Vector2(1.8, 0.85), Vector2(2.4, 0.2), Vector2(dur, 0)])
	var low := S.lp(S.brown(dur, r), 200.0)
	S.env(low, [Vector2(0, 0), Vector2(0.4, 1.0), Vector2(2.0, 0.7), Vector2(dur, 0)])
	var spray := S.hp(S.pink(dur, r), 3500.0)
	S.env(spray, [Vector2(0, 0), Vector2(0.5, 1.0), Vector2(2.0, 0.6), Vector2(dur, 0)])
	var rainback := S.grains(dur, 500, r, 1200.0, 7000.0, 0.0006, 0.002, 1.0, 0.0, 1.0)
	S.env(rainback, [Vector2(0, 0), Vector2(1.0, 0.0), Vector2(1.6, 1.0), Vector2(dur, 0)])
	var b := K.mix([[jet, 1.0, 0.0], [low, 0.8, 0.0], [spray, 0.25, 0.0], [rainback, 0.4, 0.0]])
	bubbles(b, r, 50, 1.4, 1.8, 900.0, 3500.0, 0.08, 1.0)
	return S.reverb(b, 0.7, 0.5, 0.12)


## Something big diving under: air rushing, a deep gulp, bubbles, slosh.
static func dive(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 2.2
	var rush := K.whoosh(r, 0.6, [Vector2(0, 1500), Vector2(0.5, 400)], 0.8,
			[Vector2(0, 0), Vector2(0.4, 1.0), Vector2(0.6, 0)])
	var b := K.mix([[rush, 0.5, 0.0], [splash(r, 1.0), 0.8, 0.45]])
	S.bubble(b, 0.55, r.randf_range(70.0, 110.0), 0.9, 0.09, 0.6)
	S.bubble(b, 0.62, r.randf_range(120.0, 180.0), 0.6, 0.06, 0.5)
	bubbles(b, r, 90, 0.6, 1.4, 150.0, 1200.0, 0.25, 1.3)
	var slosh := S.lp(S.pink(dur, r), 450.0)
	S.env(slosh, [Vector2(0, 0), Vector2(0.5, 0.0), Vector2(0.7, 1.0), Vector2(dur, 0)])
	S.add(b, slosh, 0.7)
	return S.reverb(b, 0.7, 0.5, 0.12)


## A drip into a cave pool.
static func drip(r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.make(1.2)
	S.add(b, K.click(r, 0.0006, 3000.0, 0.01), 0.15)
	S.bubble(b, 0.002, r.randf_range(700.0, 2300.0), 0.9, r.randf_range(0.01, 0.025), r.randf_range(0.3, 1.2))
	return S.reverb(b, 0.88, 0.35, 0.55)


# --- Foliage and trees ------------------------------------------------------------

## Pushing through a bush / tall grass: hundreds of leaf contacts whose density
## fluctuates with the movement, the odd twig.
static func rustle(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := r.randf_range(0.5, 0.8)
	var leaves := S.grains(dur, r.randi_range(260, 400), r, 1800.0, 9500.0, 0.0002, 0.0008, 1.0)
	var crinkle := S.grains(dur, r.randi_range(20, 40), r, 700.0, 3000.0, 0.001, 0.003, 1.0)
	var body := S.filter(S.pink(dur, r), S.Filter.BANDPASS, [Vector2(0, 2500)], 0.6)
	var shape := S.wander(dur, 0.06, 0.25, 1.0, r)
	S.mul(leaves, shape)
	S.mul(crinkle, shape)
	S.mul(body, shape)
	var b := K.mix([[leaves, 1.0, 0.0], [crinkle, 0.5, 0.0], [body, 0.25, 0.0]])
	S.env(b, [Vector2(0, 0), Vector2(0.06, 1.0), Vector2(dur * 0.6, 0.8), Vector2(dur, 0)])
	if r.randf() < 0.6:
		var twig := S.grains(0.05, 3, r, 1200.0, 3000.0, 0.003, 0.006, 1.0)
		S.add(b, twig, 0.5, S.samples(r.randf_range(0.05, dur * 0.6)))
	return b


## Wood under stress: stick-slip pulses (an irregular low pulse train) ringing
## the trunk's modes, over a recorded creak pitched far down.
static func stick_slip(r: RandomNumberGenerator, dur: float, f_lo: float, f_hi: float) -> PackedFloat32Array:
	var ex := S.make(dur)
	var rate := S.wander(dur, 0.12, f_lo, f_hi, r)
	var amp := S.wander(dur, 0.2, 0.2, 1.0, r)
	var t := 0.0
	while t < dur:
		var i := int(t * S.SR)
		if i >= ex.size():
			break
		ex[i] = amp[i] * r.randf_range(0.6, 1.0)
		t += 1.0 / maxf(rate[i], 5.0) * r.randf_range(0.85, 1.15)
	return S.normalize(S.modal(ex, [170.0, 410.0, 760.0, 1250.0, 2100.0], [0.03, 0.025, 0.02, 0.015, 0.01], [1.0, 0.8, 0.6, 0.4, 0.2]))


static func tree_creak(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var rec := K.smp(K.KR + "creak%d.ogg" % (1 + v % 3), r.randf_range(0.42, 0.55), 0.0, 60.0)
	var dur := maxf(1.2, S.seconds(rec.size()))
	var groan := stick_slip(r, dur, 25.0, 70.0)
	S.env(groan, [Vector2(0, 0), Vector2(0.2, 1.0), Vector2(dur * 0.7, 0.8), Vector2(dur, 0)])
	var b := K.mix([[rec, 0.8, 0.0], [groan, 0.6, 0.0]])
	return S.reverb(b, 0.6, 0.5, 0.12)


## A tree felled: fibres crack and the trunk groans, the canopy rushes down
## through the air, a heavy ground impact with branch snaps and a leaf crash,
## one bounce.
static func tree_fall(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 5.0
	var hit_t := r.randf_range(2.4, 2.8)
	var creak := K.smp(K.KR + "creak%d.ogg" % r.randi_range(1, 3), r.randf_range(0.4, 0.5), 0.0, 60.0)
	var groan := stick_slip(r, 1.8, 20.0, 60.0)
	S.env(groan, [Vector2(0, 0), Vector2(0.3, 1.0), Vector2(1.8, 0)])
	var snaps := S.grains(hit_t, 70, r, 700.0, 4500.0, 0.002, 0.008, 0.6, 0.0)
	S.env(snaps, [Vector2(0, 0.6), Vector2(hit_t * 0.5, 0.3), Vector2(hit_t, 0.1)])
	var rush := K.whoosh(r, hit_t, [Vector2(0, 300), Vector2(hit_t, 1400)], 0.7,
			[Vector2(0, 0), Vector2(hit_t * 0.4, 0.1), Vector2(hit_t, 1.0)])
	var canopy := S.grains(hit_t, 700, r, 1800.0, 9000.0, 0.0002, 0.0008, 0.5)
	S.env(canopy, [Vector2(0, 0), Vector2(hit_t * 0.5, 0.15), Vector2(hit_t, 1.0)])
	var impact := K.ki("impactWood_heavy", r.randi_range(0, 4), 0.55, 0.0, 30.0)
	var impact2 := K.ki("impactSoft_heavy", r.randi_range(0, 4), 0.7, 0.0, 25.0)
	var boom := K.thump(1.2, 60.0, 28.0, 0.35, 0.3)
	var branches := S.grains(1.2, 120, r, 600.0, 5000.0, 0.002, 0.01, 1.8, 0.4)
	var leaf_crash := S.grains(1.5, 900, r, 1500.0, 9500.0, 0.0002, 0.001, 1.6, 0.5)
	var bounce := K.ki("impactWood_heavy", r.randi_range(0, 4), 0.7, 0.0, 30.0)
	var settle := S.grains(1.6, 50, r, 800.0, 4000.0, 0.001, 0.004, 1.0, 0.8)
	var b := K.mix([[creak, 0.5, 0.0], [groan, 0.5, 0.0], [snaps, 0.35, 0.0], [rush, 0.35, 0.0], [canopy, 0.3, 0.0],
			[impact, 1.0, hit_t], [impact2, 0.9, hit_t], [boom, 1.0, hit_t], [branches, 0.5, hit_t],
			[leaf_crash, 0.4, hit_t], [bounce, 0.4, hit_t + r.randf_range(0.3, 0.45)], [settle, 0.25, hit_t + 0.3]])
	if b.size() > S.samples(dur):
		b = b.slice(0, S.samples(dur))
	return S.reverb(b, 0.75, 0.5, 0.15)


# --- Fire ----------------------------------------------------------------------------

## Flames: turbulent low noise with fast flicker.
static func flame(r: RandomNumberGenerator, dur: float, cutoff: float) -> PackedFloat32Array:
	var b := S.lp(S.pink(dur, r), cutoff)
	S.lp(b, cutoff * 1.4)
	S.mul(b, S.wander(dur, 0.035, 0.35, 1.0, r))
	return b


## Wood crackle: sparse sharp pops and smaller ticks.
static func crackle(r: RandomNumberGenerator, dur: float, per_sec: float) -> PackedFloat32Array:
	var b := S.grains(dur, int(dur * per_sec), r, 1200.0, 7000.0, 0.0003, 0.0015, 1.0)
	var pops := S.grains(dur, int(dur * per_sec * 0.12) + 1, r, 600.0, 2500.0, 0.001, 0.004, 1.0)
	return S.add(b, pops, 1.6)


static func furnace_roar(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 2.8
	var whoomp := S.filter(S.pink(dur, r), S.Filter.LOWPASS, [Vector2(0, 200), Vector2(0.25, 1500), Vector2(dur, 500)], 0.9)
	S.env(whoomp, [Vector2(0, 0), Vector2(0.2, 1.0), Vector2(0.5, 0.4), Vector2(dur, 0.2)])
	var roar := flame(r, dur, 600.0)
	S.env(roar, [Vector2(0, 0), Vector2(0.3, 1.0), Vector2(dur * 0.7, 0.8), Vector2(dur, 0)])
	var rumble := S.lp(S.brown(dur, r), 120.0)
	S.env(rumble, [Vector2(0, 0), Vector2(0.3, 1.0), Vector2(dur, 0)])
	var cr := crackle(r, dur, 25.0)
	S.env(cr, [Vector2(0, 0), Vector2(0.3, 1.0), Vector2(dur, 0)])
	return K.mix([[whoomp, 0.8, 0.0], [roar, 1.0, 0.0], [rumble, 0.8, 0.0], [cr, 0.25, 0.0]])


## Red-hot metal plunged into water.
static func quench(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 2.4
	var plunge := splash(r, 0.4)
	var sizzle := S.hp(S.noise(dur, r), 2500.0)
	S.mul(sizzle, S.wander(dur, 0.02, 0.3, 1.0, r))
	S.decay(sizzle, 0.01, 0.55)
	var crack := S.grains(dur, 500, r, 2500.0, 9000.0, 0.0002, 0.0008, 2.0, 0.6)
	var steam := S.hp(S.pink(dur, r), 4000.0)
	S.env(steam, [Vector2(0, 0), Vector2(0.1, 1.0), Vector2(dur, 0)])
	var b := K.mix([[plunge, 0.4, 0.0], [sizzle, 0.8, 0.02], [crack, 0.35, 0.02], [steam, 0.3, 0.05]])
	bubbles(b, r, 120, 0.05, 1.5, 600.0, 2400.0, 0.12, 1.8)
	return b


static func fireball_cast(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 0.95
	var roar := S.filter(S.pink(dur, r), S.Filter.LOWPASS, [Vector2(0, 300), Vector2(0.3, 2400), Vector2(dur, 700)], 1.0)
	S.mul(roar, S.wander(dur, 0.03, 0.5, 1.0, r))
	S.env(roar, [Vector2(0, 0), Vector2(0.2, 1.0), Vector2(dur, 0)])
	var whoosh := K.whoosh(r, dur, [Vector2(0, 400), Vector2(0.35, 2400), Vector2(dur, 800)], 1.2,
			[Vector2(0, 0), Vector2(0.3, 1.0), Vector2(dur, 0)])
	var fwoomp := K.thump(0.5, 90.0, 50.0, 0.12, 0.2)
	var cr := crackle(r, dur, 50.0)
	S.env(cr, [Vector2(0, 0), Vector2(0.2, 1), Vector2(dur, 0)])
	return K.mix([[roar, 1.0, 0.0], [whoosh, 0.5, 0.0], [fwoomp, 0.6, 0.05], [cr, 0.35, 0.0]])


static func fire_burst(r: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var b := S.filter(S.pink(dur, r), S.Filter.LOWPASS, [Vector2(0, 5000), Vector2(dur, 300)], 0.8)
	S.decay(b, 0.002, dur * 0.28)
	var thump := K.thump(dur, 120.0, 40.0, 0.09, 0.2)
	var cr := crackle(r, dur, 120.0)
	S.env(cr, [Vector2(0, 1), Vector2(dur, 0)])
	var flame_tail := flame(r, dur, 900.0)
	S.env(flame_tail, [Vector2(0, 0), Vector2(0.05, 1.0), Vector2(dur, 0)])
	var out := K.mix([[b, 1.0, 0.0], [thump, 0.9, 0.0], [cr, 0.35, 0.0], [flame_tail, 0.6, 0.0]])
	return S.soft_clip(out, 1.4)


static func explosion(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 2.8
	var crack := K.click(r, 0.004, 500.0, 0.06)
	var blast := S.filter(S.pink(dur, r), S.Filter.LOWPASS, [Vector2(0, 6000), Vector2(0.3, 900), Vector2(dur, 150)], 0.8)
	S.decay(blast, 0.001, 0.4)
	var sub := K.thump(dur, 58.0, 24.0, 0.55, 0.5)
	var rumble := S.lp(S.brown(dur, r), 140.0)
	S.env(rumble, [Vector2(0, 0), Vector2(0.06, 1.0), Vector2(1.0, 0.6), Vector2(dur, 0)])
	var debris := S.grains(dur, 160, r, 400.0, 4000.0, 0.001, 0.006, 1.5, 0.8, 0.15)
	var b := K.mix([[crack, 0.6, 0.0], [blast, 1.0, 0.0], [sub, 1.2, 0.0], [rumble, 1.0, 0.0], [debris, 0.35, 0.0]])
	S.soft_clip(b, 1.6)
	return S.reverb(b, 0.86, 0.5, 0.25)


static func burn(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 1.0
	var b := flame(r, dur, 1600.0)
	S.env(b, [Vector2(0, 0), Vector2(0.08, 1.0), Vector2(dur, 0)])
	var cr := crackle(r, dur, 60.0)
	S.env(cr, [Vector2(0, 0), Vector2(0.05, 1), Vector2(dur, 0)])
	var sizzle := S.hp(S.noise(dur, r), 4000.0)
	S.env(sizzle, [Vector2(0, 0), Vector2(0.05, 1.0), Vector2(dur, 0)])
	return K.mix([[b, 1.0, 0.0], [cr, 0.5, 0.0], [sizzle, 0.08, 0.0]])


## Molten rock: a slow, viscous blurp, the skin popping, a hiss.
static func lava_bubble(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 0.8
	var b := S.make(dur)
	var f := r.randf_range(55.0, 95.0)
	S.bubble(b, 0.0, f, 1.0, 0.06, 1.2)
	S.bubble(b, r.randf_range(0.05, 0.12), f * r.randf_range(1.4, 1.9), 0.5, 0.04, 1.0)
	var pop := S.lp(S.decay(S.noise(0.05, r), 0.0003, 0.006), 1800.0)
	var pop_t := r.randf_range(0.12, 0.2)
	S.add(b, pop, 0.5, S.samples(pop_t))
	var hiss := S.hp(S.pink(dur, r), 2500.0)
	S.env(hiss, [Vector2(0, 0), Vector2(pop_t, 0.0), Vector2(pop_t + 0.05, 1.0), Vector2(dur, 0)])
	S.add(b, hiss, 0.15)
	var cr := crackle(r, dur, 20.0)
	S.env(cr, [Vector2(0, 0), Vector2(pop_t, 0.0), Vector2(pop_t + 0.02, 1.0), Vector2(dur, 0)])
	return S.add(b, cr, 0.2)


# --- Weather ----------------------------------------------------------------------

## Thunder: a tearing crack series (close strikes), the main boom, and a long
## rumble that rolls in several swells as sound arrives from along the bolt.
static func thunder(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 5.6
	var b := S.make(dur)
	var near := r.randf() < 0.65
	if near:
		var t := 0.0
		for i in r.randi_range(6, 12):
			var c := S.hp(S.decay(S.noise(0.08, r), 0.0003, r.randf_range(0.003, 0.012)), 600.0)
			S.add(b, c, r.randf_range(0.4, 1.0) * (1.0 - t * 1.5), S.samples(t))
			t += r.randf_range(0.01, 0.05)
		var tear := S.hp(S.pink(0.6, r), 400.0)
		S.env(tear, [Vector2(0, 0), Vector2(0.01, 1.0), Vector2(0.6, 0)])
		S.add(b, tear, 0.6)
	var boom := S.lp(S.pink(dur, r), 260.0)
	S.decay(boom, 0.01 if near else 0.25, 0.7)
	S.add(b, boom, 1.4)
	S.add(b, K.thump(dur, 48.0, 26.0, 0.9, 0.6), 0.8)
	var rumble := S.lp(S.brown(dur, r), 170.0)
	S.add(rumble, S.lp(S.pink(dur, r), 220.0), 0.6)
	var pts := [Vector2(0, 0), Vector2(0.15, 0.6)]
	var tt := 0.15
	while tt < dur - 0.6:
		tt += r.randf_range(0.35, 0.9)
		pts.append(Vector2(tt, r.randf_range(0.35, 1.0) * pow(1.0 - tt / dur, 1.3)))
	pts.append(Vector2(dur, 0))
	S.env(rumble, pts)
	S.add(b, rumble, 2.0)
	S.soft_clip(b, 1.4)
	return S.reverb(b, 0.9, 0.55, 0.28)
