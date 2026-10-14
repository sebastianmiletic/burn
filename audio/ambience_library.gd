class_name AmbienceLibrary
extends RefCounted
## Seamless looping ambience beds. Each is rendered LOOP + XFADE seconds long
## and folded into an equal-power crossfaded loop.

const S := preload("res://audio/synth.gd")
const LOOP := 8.0
const XFADE := 1.0

const BEDS := ["wind", "rain", "fire", "cave", "lava", "village"]


static func build(bed: String) -> PackedFloat32Array:
	var r := S.rng(hash(bed) + 99)
	var dur := LOOP + XFADE
	var b: PackedFloat32Array
	match bed:
		"wind": b = _wind(dur, r)
		"rain": b = _rain(dur, r)
		"fire": b = _fire(dur, r)
		"cave": b = _cave(dur, r)
		"lava": b = _lava(dur, r)
		"village": b = _village(dur, r)
		_:
			push_error("Unknown ambience %s" % bed)
			return S.make(LOOP)
	S.dc_block(b)
	var loop := S.make_loop(b, LOOP, XFADE)
	S.normalize(loop, 0.7)
	return loop


static func _random_points(dur: float, step: float, lo: float, hi: float, r: RandomNumberGenerator) -> Array:
	var pts := []
	var t := 0.0
	while t <= dur + step:
		pts.append(Vector2(t, r.randf_range(lo, hi)))
		t += step * r.randf_range(0.7, 1.3)
	return pts


static func _wind(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.noise(dur, r)
	S.add(b, S.brown(dur, r), 2.0)
	S.filter(b, S.Filter.BANDPASS, _random_points(dur, 1.3, 280.0, 900.0, r), 0.9)
	S.env(b, _random_points(dur, 0.9, 0.35, 1.0, r))
	var whistle := S.filter(S.noise(dur, r), S.Filter.BANDPASS, _random_points(dur, 2.0, 1400.0, 2600.0, r), 14.0)
	S.env(whistle, _random_points(dur, 1.5, 0.0, 0.6, r))
	return S.add(b, whistle, 0.25)


static func _rain(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.lp(S.noise(dur, r), 5500.0)
	S.gain(b, 0.35)
	var ticks := S.hp(S.dust(dur, 2600.0, r), 2200.0)
	S.add(b, ticks, 0.9)
	var drops := S.bp(S.dust(dur, 70.0, r), 900.0, 3.0)
	S.add(b, drops, 2.0)
	var rumble := S.lp(S.brown(dur, r), 300.0)
	return S.add(b, rumble, 0.4)


static func _fire(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.lp(S.noise(dur, r), 700.0)
	S.env(b, _random_points(dur, 0.25, 0.4, 1.0, r))
	var crackle := S.bp(S.dust(dur, 140.0, r), 3000.0, 0.8)
	S.add(b, crackle, 2.2)
	var pops := S.bp(S.dust(dur, 12.0, r), 1500.0, 2.0)
	return S.add(b, pops, 3.5)


static func _cave(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.make(dur)
	var drone := S.tone(dur, S.Wave.SINE, 55.0)
	S.add(drone, S.tone(dur, S.Wave.SINE, 55.6), 1.0)  # slow beating
	S.add(drone, S.tone(dur, S.Wave.SINE, 82.4), 0.4)
	S.add(b, drone, 0.18)
	var air := S.lp(S.brown(dur, r), 260.0)
	S.add(b, air, 0.5)
	var t := r.randf_range(0.1, 0.6)
	while t < dur - 0.6:
		var f := r.randf_range(1100.0, 2600.0)
		var drip := S.bell(0.5, f, [1.0, 2.3], [0.5, 0.15], [0.06, 0.03])
		S.add(b, drip, r.randf_range(0.15, 0.4), S.samples(t))
		t += r.randf_range(0.5, 1.6)
	return S.reverb(b, 0.9, 0.45, 0.6)


static func _lava(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.lp(S.brown(dur, r), 120.0)
	S.gain(b, 1.5)
	var t := 0.05
	while t < dur - 0.6:
		var f := r.randf_range(45.0, 90.0)
		var blub := S.osc(0.3, S.Wave.SINE, [Vector2(0, f), Vector2(0.15, f * 2.4)])
		S.env(blub, [Vector2(0, 0), Vector2(0.02, 1.0), Vector2(0.18, 0)])
		S.add(b, blub, r.randf_range(0.2, 0.5), S.samples(t))
		t += r.randf_range(0.15, 0.7)
	var hiss := S.hp(S.dust(dur, 60.0, r), 2000.0)
	return S.add(b, hiss, 0.6)


static func _village(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.lp(S.noise(dur, r), 600.0)
	S.gain(b, 0.25)
	var t := r.randf_range(0.2, 1.0)
	while t < dur - 0.8:
		# A bird: two to four quick chirps.
		var base := r.randf_range(2400.0, 3600.0)
		for c in r.randi_range(2, 4):
			var chirp := S.osc(0.09, S.Wave.SINE, [Vector2(0, base), Vector2(0.07, base * r.randf_range(1.15, 1.4))])
			S.env(chirp, [Vector2(0, 0), Vector2(0.01, 1.0), Vector2(0.09, 0)])
			S.add(b, chirp, 0.12, S.samples(t + c * 0.12))
		t += r.randf_range(1.0, 2.6)
	var chime := S.bell(2.0, 1174.7, [1.0, 2.76, 5.4], [0.3, 0.1, 0.05], [0.8, 0.3, 0.1])
	S.add(b, chime, 0.08, S.samples(dur * 0.4))
	return S.reverb(b, 0.8, 0.5, 0.35)
