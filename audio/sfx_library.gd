class_name SfxLibrary
extends RefCounted
## Recipes for every sound effect. Each sound is synthesised from noise,
## oscillators, filters and envelopes (see Synth); frequently repeated sounds
## get several variants so footsteps and hits never machine-gun.

const S := preload("res://audio/synth.gd")

## name -> number of variants
const SOUNDS := {
	"ui_hover": 1, "ui_click": 1, "ui_back": 1, "ui_open": 1, "ui_close": 1, "rune": 4,
	"step_grass": 4, "step_stone": 4, "step_wood": 3, "step_snow": 3, "step_sand": 3,
	"swing": 3, "hit": 3, "hit_heavy": 2, "crit": 2, "block_hit": 3, "block_break": 3, "block_place": 2,
	"pickup": 2, "coin": 2, "potion": 1, "hurt": 3, "death": 1, "levelup": 1, "quest": 1,
	"fireball_cast": 2, "fireball_hit": 2, "explosion": 2, "arrow": 2, "bow": 2,
	"roar": 2, "roar_big": 1, "wing_flap": 3, "stomp": 2, "growl": 2, "bone_rattle": 3, "imp_screech": 2,
	"door": 1, "chest": 1, "shrine": 1, "portal": 1, "thunder": 2, "splash": 2, "lava_bubble": 3, "burn": 2,
}

## Sounds the menus need immediately; rendered synchronously at startup.
const UI_SOUNDS := ["ui_hover", "ui_click", "ui_back", "ui_open", "ui_close"]

## Default per-sound gain trim (dB) so the library is balanced.
const TRIM := {
	"ui_hover": -14.0, "ui_click": -8.0, "ui_back": -8.0, "ui_open": -8.0, "ui_close": -9.0, "rune": -6.0,
	"step_grass": -12.0, "step_stone": -12.0, "step_wood": -11.0, "step_snow": -12.0, "step_sand": -13.0,
	"swing": -6.0, "block_hit": -5.0, "block_place": -6.0, "pickup": -6.0, "coin": -6.0,
	"bone_rattle": -5.0, "lava_bubble": -6.0, "burn": -6.0, "splash": -4.0,
}

const MAX_VOICES := {"step_grass": 3, "step_stone": 3, "step_wood": 3, "step_snow": 3, "step_sand": 3,
	"ui_hover": 2, "block_hit": 3, "lava_bubble": 4, "burn": 3, "swing": 4, "hit": 6}


static func names() -> Array:
	return SOUNDS.keys()


static func variants(sound: String) -> int:
	return int(SOUNDS.get(sound, 0))


static func build(sound: String, variant: int) -> PackedFloat32Array:
	var r := S.rng(hash(sound) * 31 + variant * 7919 + 1)
	var b: PackedFloat32Array
	match sound:
		"ui_hover": b = _ui_hover(r)
		"ui_click": b = _ui_click(r)
		"ui_back": b = _ui_blips(r, [1320.0, 880.0])
		"ui_open": b = _ui_open(r, false)
		"ui_close": b = _ui_open(r, true)
		"rune": b = _rune(r, variant)
		"step_grass": b = _step(r, 2600.0, 0.11, 0.6, 900.0)
		"step_stone": b = _step_stone(r)
		"step_wood": b = _step_wood(r)
		"step_snow": b = _step(r, 4200.0, 0.15, 1.6, 1600.0)
		"step_sand": b = _step(r, 1800.0, 0.14, 0.3, 500.0)
		"swing": b = _swing(r)
		"hit": b = _hit(r, 1.0)
		"hit_heavy": b = _hit(r, 2.0)
		"crit": b = _crit(r)
		"block_hit": b = _block_hit(r)
		"block_break": b = _block_break(r)
		"block_place": b = _block_place(r)
		"pickup": b = _chime(r, [1318.5, 1760.0], 0.07, 0.5)
		"coin": b = _coin(r)
		"potion": b = _potion(r)
		"hurt": b = _hurt(r)
		"death": b = _death(r)
		"levelup": b = _chime(r, [587.3, 740.0, 880.0, 1174.7, 1480.0], 0.09, 1.6)
		"quest": b = _quest(r)
		"fireball_cast": b = _fireball_cast(r)
		"fireball_hit": b = _fire_burst(r, 0.7)
		"explosion": b = _explosion(r)
		"arrow": b = _arrow(r)
		"bow": b = _bow(r)
		"roar": b = _roar(r, 180.0, 1.4, 1.0)
		"roar_big": b = _roar(r, 78.0, 2.6, 2.2)
		"wing_flap": b = _wing_flap(r)
		"stomp": b = _stomp(r)
		"growl": b = _growl(r)
		"bone_rattle": b = _bone_rattle(r)
		"imp_screech": b = _imp_screech(r)
		"door": b = _door(r)
		"chest": b = _chest(r)
		"shrine": b = _shrine(r)
		"portal": b = _portal(r)
		"thunder": b = _thunder(r)
		"splash": b = _splash(r)
		"lava_bubble": b = _lava_bubble(r)
		"burn": b = _burn(r)
		_:
			push_error("Unknown sound %s" % sound)
			return S.make(0.05)
	S.dc_block(b)
	S.normalize(b, 0.89)
	S.fade(b, 0.0015, 0.01)
	return b


# --- UI -------------------------------------------------------------------------

static func _ui_hover(_r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.tone(0.045, S.Wave.SINE, 2350.0)
	S.add(b, S.tone(0.045, S.Wave.SINE, 3520.0), 0.3)
	return S.decay(b, 0.002, 0.012)


static func _ui_click(r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.hp(S.decay(S.noise(0.06, r), 0.0005, 0.004), 2500.0)
	var body := S.decay(S.osc(0.06, S.Wave.SINE, [Vector2(0, 1500), Vector2(0.05, 900)]), 0.001, 0.018)
	return S.add(b, body, 0.8)


static func _ui_blips(_r: RandomNumberGenerator, freqs: Array) -> PackedFloat32Array:
	var b := S.make(0.2)
	for i in freqs.size():
		var t := S.decay(S.tone(0.1, S.Wave.TRIANGLE, freqs[i]), 0.002, 0.03)
		S.add(b, t, 0.7, S.samples(i * 0.07))
	return S.lp(b, 5000.0)


static func _ui_open(r: RandomNumberGenerator, closing: bool) -> PackedFloat32Array:
	var sweep := [Vector2(0, 500), Vector2(0.25, 2400)] if not closing else [Vector2(0, 2400), Vector2(0.25, 500)]
	var w := S.filter(S.noise(0.3, r), S.Filter.BANDPASS, sweep, 2.0)
	S.env(w, [Vector2(0, 0), Vector2(0.12, 0.5), Vector2(0.3, 0)])
	var note := 1174.7 if not closing else 880.0
	var bl := S.bell(0.5, note, [1.0, 2.01, 3.0], [0.5, 0.15, 0.08], [0.25, 0.12, 0.08])
	var b := S.make(0.5)
	S.add(b, w, 0.6)
	S.add(b, bl, 0.7, S.samples(0.06 if not closing else 0.0))
	return b


static func _rune(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	# Each rune rings a different degree of a dark pentatonic scale.
	var scale := [587.3, 698.5, 784.0, 880.0, 1046.5, 1174.7]
	var f: float = scale[(v * 2 + 1) % scale.size()]
	var b := S.bell(1.1, f, [1.0, 2.76, 5.4, 8.93], [0.6, 0.25, 0.12, 0.05], [0.5, 0.25, 0.12, 0.06])
	var shimmer := S.filter(S.noise(1.1, r), S.Filter.BANDPASS, [Vector2(0, f * 4.0)], 8.0)
	S.env(shimmer, [Vector2(0, 0), Vector2(0.15, 0.25), Vector2(1.1, 0)])
	S.add(b, shimmer, 0.5)
	return S.reverb(b, 0.82, 0.3, 0.35)


# --- Footsteps -------------------------------------------------------------------

static func _step(r: RandomNumberGenerator, centre: float, length: float, grit: float, body: float) -> PackedFloat32Array:
	var c := centre * r.randf_range(0.85, 1.15)
	var b := S.filter(S.noise(length, r), S.Filter.BANDPASS, [Vector2(0, c), Vector2(length, c * 0.6)], 0.9)
	S.env(b, [Vector2(0, 0), Vector2(0.008, 1.0), Vector2(length * 0.35, 0.45), Vector2(length, 0)])
	var crackle := S.hp(S.dust(length, 900.0 * grit, r), 1200.0)
	S.env(crackle, [Vector2(0, 1), Vector2(length, 0)])
	S.add(b, crackle, 0.5 * grit)
	var thump := S.decay(S.osc(length, S.Wave.SINE, [Vector2(0, body * 0.12), Vector2(0.05, body * 0.06)]), 0.003, 0.02)
	S.add(b, thump, 0.35)
	return b


static func _step_stone(r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.hp(S.decay(S.noise(0.09, r), 0.001, 0.012), 1300.0)
	var ring := S.bp(S.decay(S.noise(0.12, r), 0.001, 0.03), 2300.0 * r.randf_range(0.9, 1.2), 4.0)
	S.add(b, ring, 0.6)
	var thump := S.decay(S.osc(0.1, S.Wave.SINE, [Vector2(0, 140), Vector2(0.05, 70)]), 0.002, 0.025)
	return S.add(b, thump, 0.3)


static func _step_wood(r: RandomNumberGenerator) -> PackedFloat32Array:
	var src := S.decay(S.noise(0.18, r), 0.001, 0.01)
	var b := S.formants(src, [320.0 * r.randf_range(0.9, 1.1), 760.0, 1500.0], [1.0, 0.6, 0.3], 9.0)
	var knock := S.decay(S.osc(0.18, S.Wave.SINE, [Vector2(0, 220), Vector2(0.1, 150)]), 0.002, 0.05)
	return S.add(b, knock, 0.6)


# --- Combat -------------------------------------------------------------------------

static func _swing(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := r.randf_range(0.24, 0.32)
	var b := S.filter(S.noise(dur, r), S.Filter.BANDPASS,
			[Vector2(0, 450), Vector2(dur * 0.45, 2600 * r.randf_range(0.85, 1.15)), Vector2(dur, 700)], 1.6)
	S.env(b, [Vector2(0, 0), Vector2(dur * 0.45, 1.0), Vector2(dur, 0)])
	return b


static func _hit(r: RandomNumberGenerator, weight: float) -> PackedFloat32Array:
	var dur := 0.25 * weight
	var b := S.make(dur)
	var thump := S.decay(S.osc(dur, S.Wave.SINE, [Vector2(0, 150 / weight), Vector2(0.12 * weight, 48 / weight)]), 0.002, 0.07 * weight)
	S.add(b, thump, 0.5)
	var crack := S.hp(S.decay(S.noise(0.08, r), 0.0005, 0.012 * weight), 1600.0)
	S.add(b, crack, 1.0)
	var body := S.bp(S.decay(S.noise(dur, r), 0.001, 0.04 * weight), 620.0 * r.randf_range(0.85, 1.15), 1.4)
	S.add(b, body, 2.2)
	if weight > 1.5:
		S.soft_clip(b, 2.5)
	return b


static func _crit(r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _hit(r, 1.3)
	var ring := S.bell(0.6, 1240.0 * r.randf_range(0.95, 1.05), [1.0, 2.35, 3.31, 4.7], [0.5, 0.35, 0.25, 0.12], [0.3, 0.2, 0.12, 0.08])
	var out := S.make(0.6)
	S.add(out, b, 0.9)
	return S.add(out, ring, 0.5)


static func _block_hit(r: RandomNumberGenerator) -> PackedFloat32Array:
	# Pickaxe on stone: a metallic ping over a gritty chip.
	var f := 2050.0 * r.randf_range(0.9, 1.12)
	var b := S.bell(0.32, f, [1.0, 1.63, 2.53, 3.41], [0.45, 0.3, 0.2, 0.1], [0.09, 0.07, 0.05, 0.04])
	var chip := S.hp(S.decay(S.noise(0.12, r), 0.0005, 0.018), 900.0)
	S.add(b, chip, 0.9)
	var grit := S.lp(S.dust(0.25, 350.0, r), 4000.0)
	S.env(grit, [Vector2(0, 1), Vector2(0.25, 0)])
	S.add(b, grit, 0.4, S.samples(0.01))
	var thud := S.decay(S.osc(0.15, S.Wave.SINE, [Vector2(0, 180), Vector2(0.08, 90)]), 0.001, 0.03)
	return S.add(b, thud, 0.5)


static func _block_break(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 0.55
	var b := S.make(dur)
	var grains := r.randi_range(10, 16)
	for i in grains:
		var t := pow(r.randf(), 1.6) * 0.38
		var g := S.bp(S.decay(S.noise(0.08, r), 0.001, r.randf_range(0.008, 0.02)), r.randf_range(500.0, 2600.0), 1.2)
		S.add(b, g, r.randf_range(0.4, 1.0) * (1.0 - t), S.samples(t))
	var thud := S.decay(S.osc(0.3, S.Wave.SINE, [Vector2(0, 110), Vector2(0.2, 45)]), 0.002, 0.08)
	S.add(b, thud, 0.8)
	var dust := S.lp(S.noise(dur, r), 1500.0)
	S.env(dust, [Vector2(0, 0), Vector2(0.03, 0.4), Vector2(dur, 0)])
	return S.add(b, dust, 0.5)


static func _block_place(r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.decay(S.osc(0.18, S.Wave.SINE, [Vector2(0, 200), Vector2(0.1, 90)]), 0.002, 0.04)
	var tap := S.lp(S.decay(S.noise(0.1, r), 0.001, 0.015), 2400.0)
	return S.add(b, tap, 0.7)


static func _chime(_r: RandomNumberGenerator, notes: Array, spacing: float, tail: float) -> PackedFloat32Array:
	var dur := spacing * notes.size() + tail
	var b := S.make(dur)
	for i in notes.size():
		var n := S.bell(tail, notes[i], [1.0, 2.0, 3.01, 4.2], [0.6, 0.2, 0.1, 0.06], [tail * 0.5, tail * 0.3, tail * 0.15, 0.08])
		S.add(b, n, 0.8, S.samples(i * spacing))
	return S.reverb(b, 0.75, 0.3, 0.3)


static func _coin(r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.make(0.45)
	for i in 2:
		var f := (2650.0 if i == 0 else 3150.0) * r.randf_range(0.98, 1.02)
		var p := S.bell(0.35, f, [1.0, 1.52, 2.33], [0.6, 0.3, 0.15], [0.12, 0.08, 0.05])
		S.add(b, p, 0.8, S.samples(i * 0.075))
	return b


static func _potion(r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.make(0.9)
	var pop := S.bp(S.decay(S.noise(0.05, r), 0.0005, 0.008), 1800.0, 2.0)
	S.add(b, pop, 1.0)
	for i in 7:
		var t := 0.12 + i * 0.09 + r.randf_range(-0.02, 0.02)
		var f := r.randf_range(380.0, 760.0)
		var bub := S.decay(S.osc(0.08, S.Wave.SINE, [Vector2(0, f), Vector2(0.06, f * 1.8)]), 0.004, 0.025)
		S.add(b, bub, 0.6, S.samples(t))
	return S.lp(b, 3500.0)


static func _hurt(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 0.35
	var f0 := r.randf_range(150.0, 190.0)
	var voice := S.osc(dur, S.Wave.SAW, [Vector2(0, f0), Vector2(0.08, f0 * 1.2), Vector2(dur, f0 * 0.75)])
	var b := S.formants(voice, [650.0, 1100.0, 2400.0], [1.0, 0.6, 0.2], 7.0)
	S.env(b, [Vector2(0, 0), Vector2(0.02, 1.0), Vector2(0.12, 0.6), Vector2(dur, 0)])
	var thump := S.decay(S.osc(0.2, S.Wave.SINE, [Vector2(0, 110), Vector2(0.1, 50)]), 0.002, 0.05)
	return S.add(b, thump, 0.8)


static func _death(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 1.6
	var tone := S.osc(dur, S.Wave.SAW, [Vector2(0, 220), Vector2(dur, 55)])
	S.lp(tone, 900.0)
	S.env(tone, [Vector2(0, 0), Vector2(0.05, 0.7), Vector2(dur, 0)])
	var rumble := S.lp(S.brown(dur, r), 220.0)
	S.env(rumble, [Vector2(0, 0), Vector2(0.1, 1.0), Vector2(dur, 0)])
	var b := S.make(dur)
	S.add(b, tone, 0.6)
	S.add(b, rumble, 1.0)
	return S.reverb(b, 0.85, 0.4, 0.4)


static func _quest(_r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.make(1.8)
	var chords := [[587.3, 740.0, 880.0], [784.0, 987.8, 1174.7]]
	for c in chords.size():
		for f: float in chords[c]:
			var n := S.bell(1.3, f, [1.0, 2.0, 3.0], [0.4, 0.12, 0.05], [0.7, 0.3, 0.15])
			S.add(b, n, 0.5, S.samples(c * 0.32))
	return S.reverb(b, 0.8, 0.3, 0.35)


# --- Fire and magic ------------------------------------------------------------------

static func _crackle(dur: float, density: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var d := S.dust(dur, density, r)
	S.bp(d, 3200.0, 0.8)
	return d


static func _fireball_cast(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 0.8
	var roar := S.filter(S.noise(dur, r), S.Filter.LOWPASS, [Vector2(0, 300), Vector2(0.25, 1800), Vector2(dur, 600)], 1.2)
	S.env(roar, [Vector2(0, 0), Vector2(0.18, 1.0), Vector2(dur, 0)])
	var whoosh := _swing(r)
	var b := S.make(dur)
	S.add(b, roar, 1.0)
	S.add(b, whoosh, 0.5)
	var cr := _crackle(dur, 260.0, r)
	S.env(cr, [Vector2(0, 0), Vector2(0.2, 1), Vector2(dur, 0)])
	return S.add(b, cr, 0.6)


static func _fire_burst(r: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var b := S.filter(S.noise(dur, r), S.Filter.LOWPASS, [Vector2(0, 4000), Vector2(dur, 300)], 0.9)
	S.decay(b, 0.003, dur * 0.25)
	var thump := S.decay(S.osc(dur, S.Wave.SINE, [Vector2(0, 120), Vector2(0.2, 40)]), 0.002, 0.08)
	S.add(b, thump, 0.9)
	var cr := _crackle(dur, 500.0, r)
	S.env(cr, [Vector2(0, 1), Vector2(dur, 0)])
	S.add(b, cr, 0.7)
	return S.soft_clip(b, 1.8)


static func _explosion(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 2.0
	var b := S.filter(S.noise(dur, r), S.Filter.LOWPASS, [Vector2(0, 2500), Vector2(0.4, 500), Vector2(dur, 120)], 0.8)
	S.decay(b, 0.002, 0.35)
	var sub := S.decay(S.osc(dur, S.Wave.SINE, [Vector2(0, 70), Vector2(0.6, 26)]), 0.002, 0.3)
	S.add(b, sub, 1.4)
	var rumble := S.lp(S.brown(dur, r), 160.0)
	S.env(rumble, [Vector2(0, 0), Vector2(0.05, 1.0), Vector2(dur, 0)])
	S.add(b, rumble, 1.2)
	var debris := _crackle(dur, 160.0, r)
	S.env(debris, [Vector2(0, 0), Vector2(0.2, 1.0), Vector2(1.4, 0)])
	S.add(b, debris, 0.5)
	S.soft_clip(b, 2.2)
	return S.reverb(b, 0.86, 0.5, 0.3)


static func _burn(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 0.9
	var b := S.lp(S.noise(dur, r), 1600.0)
	S.env(b, [Vector2(0, 0), Vector2(0.1, 0.5), Vector2(dur, 0)])
	var cr := _crackle(dur, 420.0, r)
	S.env(cr, [Vector2(0, 0), Vector2(0.05, 1), Vector2(dur, 0)])
	return S.add(b, cr, 1.0)


static func _portal(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 2.8
	var b := S.make(dur)
	for f: float in [110.0, 164.8, 220.5, 329.6]:
		var o := S.osc(dur, S.Wave.SAW, [Vector2(0, f * 0.98), Vector2(dur, f * 1.02)])
		S.add(b, o, 0.25)
	S.filter(b, S.Filter.LOWPASS, [Vector2(0, 200), Vector2(1.8, 3200), Vector2(dur, 900)], 2.5)
	var air := S.filter(S.noise(dur, r), S.Filter.BANDPASS, [Vector2(0, 600), Vector2(dur, 5200)], 3.0)
	S.add(b, air, 0.6)
	var sparkle := S.make(dur)
	for i in 18:
		var t := r.randf_range(0.6, dur - 0.6)
		var n := S.bell(0.5, r.randf_range(1800.0, 4200.0), [1.0, 2.7], [0.4, 0.15], [0.2, 0.1])
		S.add(sparkle, n, 0.3, S.samples(t))
	S.add(b, sparkle, 0.6)
	S.env(b, [Vector2(0, 0), Vector2(1.6, 1.0), Vector2(2.0, 0.8), Vector2(dur, 0)])
	return S.reverb(b, 0.88, 0.3, 0.45)


static func _shrine(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 2.6
	var b := S.make(dur)
	for f: float in [293.7, 440.0, 587.3, 740.0, 880.0]:
		var n := S.bell(dur, f, [1.0, 2.0, 3.01, 4.17], [0.5, 0.18, 0.08, 0.04], [1.1, 0.6, 0.3, 0.15])
		S.add(b, n, 0.35, S.samples(r.randf_range(0.0, 0.18)))
	var glow := S.filter(S.noise(dur, r), S.Filter.BANDPASS, [Vector2(0, 2000), Vector2(dur, 6000)], 6.0)
	S.env(glow, [Vector2(0, 0), Vector2(0.5, 0.35), Vector2(dur, 0)])
	S.add(b, glow, 0.4)
	return S.reverb(b, 0.88, 0.25, 0.45)


# --- Projectiles ----------------------------------------------------------------------

static func _arrow(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 0.32
	var b := S.filter(S.noise(dur, r), S.Filter.BANDPASS, [Vector2(0, 3800), Vector2(dur, 1300)], 6.0)
	S.env(b, [Vector2(0, 0), Vector2(0.03, 1.0), Vector2(0.25, 0.4), Vector2(dur, 0)])
	var thunk := S.decay(S.osc(0.12, S.Wave.SINE, [Vector2(0, 260), Vector2(0.05, 120)]), 0.001, 0.03)
	return S.add(b, thunk, 0.5, S.samples(0.2))


static func _bow(r: RandomNumberGenerator) -> PackedFloat32Array:
	var string := S.pluck(0.5, 98.0 * r.randf_range(0.95, 1.05), 0.992, 0.7, r)
	var creak := S.bp(S.dust(0.15, 2500.0, r), 1100.0, 3.0)
	var b := S.make(0.5)
	S.add(b, creak, 0.4)
	S.add(b, string, 1.0, S.samples(0.05))
	return S.decay(b, 0.001, 0.18)


# --- Creatures ---------------------------------------------------------------------------

static func _roar(r: RandomNumberGenerator, f0: float, dur: float, size: float) -> PackedFloat32Array:
	var f := f0 * r.randf_range(0.92, 1.08)
	var voice := S.osc(dur, S.Wave.SAW, [Vector2(0, f * 0.8), Vector2(dur * 0.2, f * 1.15), Vector2(dur, f * 0.55)])
	var rough := S.lp(S.noise(dur, r), 60.0)
	S.normalize(rough, 1.0)
	S.modulate(voice, rough, 0.6)
	var breath := S.noise(dur, r)
	S.add(voice, breath, 0.7)
	var b := S.formants(voice, [420.0 / sqrt(size), 900.0 / sqrt(size), 2200.0 / sqrt(size)], [1.0, 0.7, 0.25], 4.0)
	S.env(b, [Vector2(0, 0), Vector2(dur * 0.15, 1.0), Vector2(dur * 0.65, 0.8), Vector2(dur, 0)])
	if size > 1.5:
		var sub := S.osc(dur, S.Wave.SINE, [Vector2(0, 52), Vector2(dur, 34)])
		S.env(sub, [Vector2(0, 0), Vector2(dur * 0.2, 1.0), Vector2(dur, 0)])
		S.add(b, sub, 0.6)
	S.soft_clip(b, 1.6 + size * 0.4)
	return S.reverb(b, 0.84, 0.45, 0.3)


static func _growl(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 1.2
	var voice := S.osc(dur, S.Wave.SAW, [Vector2(0, 68), Vector2(dur * 0.5, 82), Vector2(dur, 60)])
	var rough := S.lp(S.noise(dur, r), 35.0)
	S.normalize(rough, 1.0)
	S.modulate(voice, rough, 0.9)
	var b := S.formants(voice, [380.0, 820.0, 1900.0], [1.0, 0.5, 0.15], 5.0)
	S.env(b, [Vector2(0, 0), Vector2(0.2, 1.0), Vector2(0.9, 0.7), Vector2(dur, 0)])
	return S.soft_clip(b, 1.5)


static func _wing_flap(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 0.45
	var b := S.filter(S.noise(dur, r), S.Filter.LOWPASS, [Vector2(0, 900), Vector2(dur, 160)], 1.5)
	S.env(b, [Vector2(0, 0), Vector2(0.04, 1.0), Vector2(0.18, 0.4), Vector2(dur, 0)])
	var whomp := S.decay(S.osc(dur, S.Wave.SINE, [Vector2(0, 75), Vector2(0.2, 40)]), 0.01, 0.1)
	return S.add(b, whomp, 0.9)


static func _stomp(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 0.9
	var b := S.decay(S.osc(dur, S.Wave.SINE, [Vector2(0, 62), Vector2(0.3, 28)]), 0.002, 0.2)
	var rumble := S.lp(S.brown(dur, r), 180.0)
	S.env(rumble, [Vector2(0, 1), Vector2(dur, 0)])
	S.add(b, rumble, 1.2)
	var crunch := S.lp(S.decay(S.noise(0.2, r), 0.001, 0.03), 1800.0)
	S.add(b, crunch, 0.5)
	return S.soft_clip(b, 2.0)


static func _bone_rattle(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 0.6
	var b := S.make(dur)
	var clicks := r.randi_range(9, 15)
	for i in clicks:
		var t := r.randf_range(0.0, dur - 0.06)
		var c := S.bp(S.decay(S.noise(0.05, r), 0.0005, 0.005), r.randf_range(1800.0, 4200.0), 5.0)
		S.add(b, c, r.randf_range(0.5, 1.0), S.samples(t))
	return b


static func _imp_screech(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 0.65
	var f := r.randf_range(850.0, 1050.0)
	var v := S.osc(dur, S.Wave.SAW, [Vector2(0, f), Vector2(0.2, f * 1.5), Vector2(dur, f * 0.7)])
	var vib := S.tone(dur, S.Wave.SINE, 23.0)
	S.modulate(v, vib, 0.35)
	var b := S.formants(v, [1800.0, 2900.0], [1.0, 0.6], 5.0)
	S.add(b, S.hp(S.noise(dur, r), 3000.0), 0.25)
	S.env(b, [Vector2(0, 0), Vector2(0.03, 1.0), Vector2(0.4, 0.6), Vector2(dur, 0)])
	return S.soft_clip(b, 1.4)


# --- World ---------------------------------------------------------------------------------

static func _creak(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	# A slow, jittery sawtooth through wood-like resonances.
	var pts := []
	var t := 0.0
	while t < dur:
		pts.append(Vector2(t, r.randf_range(55.0, 95.0)))
		t += 0.05
	var s := S.osc(dur, S.Wave.SAW, pts)
	var b := S.formants(s, [900.0, 1700.0, 2600.0], [1.0, 0.6, 0.3], 8.0)
	S.env(b, [Vector2(0, 0), Vector2(0.06, 1.0), Vector2(dur * 0.8, 0.7), Vector2(dur, 0)])
	return b


static func _door(r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.make(1.0)
	S.add(b, _creak(0.7, r), 0.7)
	var thud := S.decay(S.osc(0.3, S.Wave.SINE, [Vector2(0, 120), Vector2(0.1, 60)]), 0.002, 0.07)
	S.add(thud, S.lp(S.decay(S.noise(0.3, r), 0.001, 0.03), 1500.0), 0.6)
	return S.add(b, thud, 1.0, S.samples(0.68))


static func _chest(r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.make(0.8)
	S.add(b, _creak(0.45, r), 0.6)
	var clunk := S.formants(S.decay(S.noise(0.3, r), 0.001, 0.02), [280.0, 700.0], [1.0, 0.5], 8.0)
	S.add(b, clunk, 1.0, S.samples(0.4))
	var latch := S.bell(0.3, 1900.0, [1.0, 2.4], [0.4, 0.2], [0.05, 0.03])
	return S.add(b, latch, 0.4, S.samples(0.02))


static func _thunder(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 4.5
	var b := S.make(dur)
	var crack := S.hp(S.decay(S.noise(0.4, r), 0.001, 0.07), 600.0)
	S.add(b, crack, 1.0)
	var rumble := S.lp(S.brown(dur, r), 140.0)
	# Rolling: a few swells of the rumble.
	var pts := [Vector2(0, 0), Vector2(0.08, 1.0)]
	var t := 0.08
	while t < dur - 0.5:
		t += r.randf_range(0.3, 0.8)
		pts.append(Vector2(t, r.randf_range(0.3, 1.0) * (1.0 - t / dur)))
	pts.append(Vector2(dur, 0))
	S.env(rumble, pts)
	S.add(b, rumble, 1.6)
	S.soft_clip(b, 1.8)
	return S.reverb(b, 0.9, 0.5, 0.3)


static func _splash(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 0.7
	var b := S.filter(S.noise(dur, r), S.Filter.LOWPASS, [Vector2(0, 5000), Vector2(dur, 500)], 0.8)
	S.decay(b, 0.004, 0.12)
	for i in 6:
		var f := r.randf_range(500.0, 1200.0)
		var bub := S.decay(S.osc(0.06, S.Wave.SINE, [Vector2(0, f), Vector2(0.05, f * 1.6)]), 0.003, 0.02)
		S.add(b, bub, 0.35, S.samples(0.1 + r.randf() * 0.4))
	return b


static func _lava_bubble(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 0.6
	var f := r.randf_range(55.0, 85.0)
	var blub := S.osc(dur, S.Wave.SINE, [Vector2(0, f), Vector2(0.15, f * 2.6)])
	S.env(blub, [Vector2(0, 0), Vector2(0.02, 1.0), Vector2(0.16, 0.0)])
	var hiss := S.lp(S.noise(dur, r), 2200.0)
	S.env(hiss, [Vector2(0, 0), Vector2(0.15, 0.0), Vector2(0.2, 0.4), Vector2(dur, 0)])
	var b := S.make(dur)
	S.add(b, blub, 1.0)
	S.add(b, hiss, 0.4)
	return S.add(b, _crackle(dur, 80.0, r), 0.3)
