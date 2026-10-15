class_name SfxLibrary
extends RefCounted
## Recipes for every sound effect. Sounds are built from CC0 recordings
## (audio/samples/, decoded by SampleBank) layered with synthesised material
## (Synth): modal resonators for struck wood / metal / stone / bone, granular
## crack clouds for crunch, crumble and rustle, Minnaert bubbles for water,
## swept noise for whooshes, pulse-train voices through moving formants for
## creatures. Every sound has several variants (random recording, re-pitch and
## layer choices) and Audio adds per-play pitch / volume jitter on top.
##
## Recipes for creatures and nature live in sfx_creatures.gd / sfx_nature.gd.

const S := preload("res://audio/synth.gd")
const K := preload("res://audio/sfx_kit.gd")
const C := preload("res://audio/sfx_creatures.gd")
const N := preload("res://audio/sfx_nature.gd")

## name -> number of variants
const SOUNDS := {
	# UI and feedback
	"ui_hover": 1, "ui_click": 1, "ui_back": 1, "ui_open": 1, "ui_close": 1, "rune": 4,
	"pickup": 3, "coin": 3, "potion": 2, "levelup": 1, "quest": 1, "gem": 3,
	# Movement
	"step_grass": 6, "step_dirt": 6, "step_stone": 6, "step_wood": 6, "step_snow": 6, "step_sand": 6,
	"step_run": 6, "jump": 4, "land": 4, "land_heavy": 3, "roll": 3, "water_wade": 5,
	# Foley
	"equip": 4, "equip_metal": 4, "equip_cloth": 4, "cloth": 5, "rustle": 5,
	# Combat
	"swing": 4, "swing_light": 4, "swing_heavy": 3, "swing_blunt": 3,
	"hit": 5, "hit_heavy": 4, "crit": 3, "hit_flesh": 5, "hit_bone": 5, "hit_metal": 5, "hit_wood": 5,
	"hurt": 4, "death": 1, "arrow": 3, "bow": 3,
	# Mining and building
	"block_hit": 5, "block_break": 4, "block_place": 4,
	"pick_stone": 5, "pick_dirt": 5, "pick_wood": 5,
	"break_stone": 4, "break_dirt": 4, "break_wood": 4, "break_crystal": 3,
	"tree_creak": 3, "tree_fall": 2,
	# Crafting
	"craft": 4, "saw": 3, "hammer_anvil": 4, "furnace_roar": 2, "quench": 3, "smelt_done": 2,
	# Magic and fire
	"fireball_cast": 3, "fireball_hit": 3, "explosion": 3, "burn": 3, "lava_bubble": 4,
	"shrine": 1, "portal": 1,
	# Creatures
	"roar": 3, "roar_big": 2, "growl": 3, "wing_flap": 4, "stomp": 3, "bone_rattle": 4, "imp_screech": 3,
	"wolf_howl": 3, "wolf_growl": 3, "bear_roar": 2, "spider_hiss": 3, "bat_screech": 3, "bird_flap": 2,
	"deer_call": 2, "leviathan_roar": 2,
	# World and water
	"door": 2, "chest": 2, "thunder": 3, "splash": 4, "splash_small": 5, "splash_big": 2,
	"wave_crash": 2, "water_spout": 2, "dive": 2,
	# Ambient one-shots scheduled by Audio around the listener
	"amb_bird": 8, "amb_owl": 2, "amb_drip": 4,
}

## Sounds the menus need immediately; rendered synchronously at startup.
const UI_SOUNDS := ["ui_hover", "ui_click", "ui_back", "ui_open", "ui_close"]

## Rendered first in the background: what the first seconds of play need.
const PRIORITY := ["step_grass", "step_dirt", "step_stone", "step_run", "jump", "land", "swing", "swing_light", "hit",
	"hit_flesh", "block_hit", "pick_stone", "pick_dirt", "block_break", "break_stone", "break_dirt", "block_place",
	"step_wood", "step_sand", "step_snow", "land_heavy", "roll", "hurt", "pickup", "coin", "rustle", "amb_bird"]

## Loudness class of each sound (default "world"); see TARGET_DB.
const CATEGORY := {
	"ui_hover": "ui", "ui_click": "ui", "ui_back": "ui", "ui_open": "ui", "ui_close": "ui", "rune": "ui",
	"pickup": "ui", "coin": "ui", "levelup": "ui", "quest": "ui", "gem": "ui", "potion": "foley",
	"step_grass": "step", "step_dirt": "step", "step_stone": "step", "step_wood": "step", "step_snow": "step",
	"step_sand": "step", "step_run": "step", "water_wade": "step",
	"jump": "foley", "land": "foley", "land_heavy": "impact", "roll": "foley", "equip": "foley",
	"equip_metal": "foley", "equip_cloth": "foley", "cloth": "foley", "rustle": "foley",
	"swing": "swing", "swing_light": "swing", "swing_heavy": "swing", "swing_blunt": "swing", "arrow": "swing",
	"bow": "foley",
	"hit": "impact", "hit_heavy": "impact", "crit": "impact", "hit_flesh": "impact", "hit_bone": "impact",
	"hit_metal": "impact", "hit_wood": "impact", "hurt": "impact", "death": "big",
	"block_hit": "impact", "block_break": "impact", "block_place": "foley", "pick_stone": "impact",
	"pick_dirt": "impact", "pick_wood": "impact", "break_stone": "impact", "break_dirt": "impact",
	"break_wood": "impact", "break_crystal": "impact", "tree_creak": "world", "tree_fall": "big",
	"craft": "foley", "saw": "world", "hammer_anvil": "impact", "furnace_roar": "world", "quench": "world",
	"smelt_done": "world",
	"fireball_cast": "magic", "fireball_hit": "magic", "explosion": "big", "burn": "world",
	"lava_bubble": "world", "shrine": "magic", "portal": "magic",
	"roar": "creature", "roar_big": "big", "growl": "creature", "wing_flap": "creature", "stomp": "big",
	"bone_rattle": "creature", "imp_screech": "creature", "wolf_howl": "creature", "wolf_growl": "creature",
	"bear_roar": "creature", "spider_hiss": "creature", "bat_screech": "creature", "bird_flap": "creature",
	"deer_call": "creature", "leviathan_roar": "big",
	"door": "world", "chest": "world", "thunder": "big", "splash": "water", "splash_small": "water",
	"splash_big": "big", "wave_crash": "big", "water_spout": "big", "dive": "water",
	"amb_bird": "amb", "amb_owl": "amb", "amb_drip": "amb",
}

## Short-term (loudest 50 ms) loudness each category is normalised to, dBFS.
const TARGET_DB := {"ui": -15.0, "step": -19.0, "foley": -17.0, "swing": -15.0, "impact": -10.0,
	"creature": -11.0, "big": -9.0, "world": -13.0, "water": -12.0, "magic": -11.0, "amb": -14.0}

## Per-sound gain trim (dB) on top of the category loudness, tuned so call
## sites keep the balance they were written against (they pass their own
## volume_db, e.g. the player's footsteps -8, an enemy's hurt rattle -4).
const TRIM := {
	"ui_hover": -10.0, "ui_click": -7.0, "ui_back": -3.0, "ui_close": -1.0, "levelup": 3.0, "quest": 3.0,
	"pickup": -3.0, "coin": -2.0, "step_sand": -1.0, "step_run": 1.0, "water_wade": 1.0,
	"swing": -2.0, "swing_light": -3.0, "hit": -2.0, "crit": -2.0, "block_hit": -7.0, "pick_stone": -6.0,
	"pick_dirt": -6.0, "pick_wood": -6.0, "block_place": -2.0, "bone_rattle": -7.0, "lava_bubble": -4.0,
	"burn": -4.0, "splash": -2.0, "rustle": -3.0, "cloth": -2.0, "fireball_hit": 3.0, "explosion": 2.0,
	"amb_drip": -4.0, "amb_owl": -2.0,
}

const MAX_VOICES := {"step_grass": 4, "step_stone": 4, "step_wood": 4, "step_snow": 4, "step_sand": 4,
	"step_dirt": 4, "step_run": 4, "water_wade": 4, "ui_hover": 2, "block_hit": 3, "pick_stone": 3,
	"pick_dirt": 3, "pick_wood": 3, "lava_bubble": 4, "burn": 3, "swing": 4, "swing_light": 4, "hit": 6,
	"hit_flesh": 6, "rustle": 4, "amb_bird": 4, "amb_drip": 3, "thunder": 2, "tree_fall": 2, "cloth": 3,
	"bone_rattle": 4, "wing_flap": 4}

## Per-category play() jitter: x = pitch spread (+-), y = volume spread (dB, +-).
const JITTER := {"ui": Vector2(0.015, 0.6), "step": Vector2(0.06, 2.5), "foley": Vector2(0.06, 2.0),
	"swing": Vector2(0.07, 1.5), "impact": Vector2(0.06, 1.5), "creature": Vector2(0.05, 1.5),
	"big": Vector2(0.04, 1.0), "world": Vector2(0.05, 1.5), "water": Vector2(0.07, 2.0),
	"magic": Vector2(0.04, 1.0), "amb": Vector2(0.08, 3.0)}

## Per-category 3D falloff: x = unit size (m, distance of 0 dB), y = max distance (m).
const RANGE := {"ui": Vector2(4.0, 40.0), "step": Vector2(2.2, 32.0), "foley": Vector2(2.5, 30.0),
	"swing": Vector2(3.0, 40.0), "impact": Vector2(5.0, 70.0), "creature": Vector2(9.0, 110.0),
	"big": Vector2(22.0, 300.0), "world": Vector2(6.0, 80.0), "water": Vector2(5.0, 70.0),
	"magic": Vector2(8.0, 100.0), "amb": Vector2(10.0, 120.0)}

const KI := "kenney_impact/"
const KR := "kenney_rpg/"


static func names() -> Array:
	return SOUNDS.keys()


static func variants(sound: String) -> int:
	return int(SOUNDS.get(sound, 0))


static func category(sound: String) -> String:
	return String(CATEGORY.get(sound, "world"))


static func build(sound: String, variant: int) -> PackedFloat32Array:
	if not SOUNDS.has(sound):
		push_error("Unknown sound %s" % sound)
		return S.make(0.05)
	var r := S.rng(hash(sound) * 31 + variant * 7919 + 1)
	var b := _recipe(sound, variant, r)
	if b.size() < S.samples(0.02):
		b = S.make(0.05)
	S.dc_block(b)
	b = S.trim_tail(b, -62.0, 0.015)
	S.level(b, float(TARGET_DB.get(category(sound), -13.0)))
	S.fade(b, 0.0006, 0.012)
	return b


static func _recipe(sound: String, v: int, r: RandomNumberGenerator) -> PackedFloat32Array:
	match sound:
		"ui_hover": return _ui_hover(r)
		"ui_click": return _ui_click(r)
		"ui_back": return _ui_blips(r, [1320.0, 880.0])
		"ui_open": return _ui_open(r, false)
		"ui_close": return _ui_open(r, true)
		"rune": return _rune(r, v)
		"pickup": return _pickup(r, v)
		"coin": return _coin(r, v)
		"potion": return _potion(r)
		"levelup": return _chime(r, [587.3, 740.0, 880.0, 1174.7, 1480.0], 0.09, 1.6)
		"quest": return _quest(r)
		"gem": return _gem(r, v)
		"step_grass": return _step_grass(r, v)
		"step_dirt": return _step_dirt(r, v)
		"step_stone": return _step_stone(r, v)
		"step_wood": return _step_wood(r, v)
		"step_snow": return _step_snow(r, v)
		"step_sand": return _step_sand(r, v)
		"step_run": return _step_run(r, v)
		"jump": return _jump(r, v)
		"land": return _land(r, v)
		"land_heavy": return _land_heavy(r, v)
		"roll": return _roll(r, v)
		"water_wade": return N.wade(r)
		"equip": return _equip(r, v)
		"equip_metal": return _equip_metal(r, v)
		"equip_cloth": return _equip_cloth(r, v)
		"cloth": return _cloth(r, v)
		"rustle": return N.rustle(r)
		"swing": return _swing(r, 0.30, 1.0, 0.55)
		"swing_light": return _swing(r, 0.22, 1.35, 0.7)
		"swing_heavy": return _swing_heavy(r)
		"swing_blunt": return _swing_blunt(r)
		"hit": return _hit(r, v)
		"hit_heavy": return _hit_heavy(r, v)
		"crit": return _crit(r, v)
		"hit_flesh": return _hit_flesh(r, v)
		"hit_bone": return _hit_bone(r, v)
		"hit_metal": return _hit_metal(r, v)
		"hit_wood": return _hit_wood(r, v)
		"hurt": return _hurt(r, v)
		"death": return _death(r)
		"arrow": return _arrow(r)
		"bow": return _bow(r)
		"block_hit": return _pick_stone(r, v + 2)
		"pick_stone": return _pick_stone(r, v)
		"pick_dirt": return _pick_dirt(r, v)
		"pick_wood": return _pick_wood(r, v)
		"block_break": return _break_stone(r, 0.8)
		"break_stone": return _break_stone(r, 1.0)
		"break_dirt": return _break_dirt(r)
		"break_wood": return _break_wood(r, v)
		"break_crystal": return _break_crystal(r, v)
		"block_place": return _block_place(r, v)
		"tree_creak": return N.tree_creak(r, v)
		"tree_fall": return N.tree_fall(r)
		"craft": return _craft(r, v)
		"saw": return _saw(r)
		"hammer_anvil": return _anvil(r, v)
		"furnace_roar": return N.furnace_roar(r)
		"quench": return N.quench(r)
		"smelt_done": return _smelt_done(r, v)
		"fireball_cast": return N.fireball_cast(r)
		"fireball_hit": return N.fire_burst(r, 0.9)
		"explosion": return N.explosion(r)
		"burn": return N.burn(r)
		"lava_bubble": return N.lava_bubble(r)
		"shrine": return _shrine(r)
		"portal": return _portal(r)
		"roar": return C.roar(r, 165.0, 1.5, 1.0)
		"roar_big": return C.roar(r, 70.0, 2.8, 2.2)
		"growl": return C.growl(r, 72.0, 1.3)
		"wing_flap": return C.wing_flap(r)
		"stomp": return C.stomp(r)
		"bone_rattle": return C.bone_rattle(r)
		"imp_screech": return C.imp_screech(r)
		"wolf_howl": return C.wolf_howl(r)
		"wolf_growl": return C.wolf_growl(r)
		"bear_roar": return C.bear_roar(r)
		"spider_hiss": return C.spider_hiss(r)
		"bat_screech": return C.bat_screech(r)
		"bird_flap": return C.bird_flap(r)
		"deer_call": return C.deer_call(r)
		"leviathan_roar": return C.leviathan_roar(r)
		"door": return _door(r, v)
		"chest": return _chest(r, v)
		"thunder": return N.thunder(r)
		"splash": return N.splash(r, 1.0)
		"splash_small": return N.splash(r, 0.45)
		"splash_big": return N.splash_big(r)
		"wave_crash": return N.wave_crash(r)
		"water_spout": return N.water_spout(r)
		"dive": return N.dive(r)
		"amb_bird": return C.bird_call(r, v)
		"amb_owl": return C.owl(r)
		"amb_drip": return N.drip(r)
	return S.make(0.05)


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


static func _chime(_r: RandomNumberGenerator, notes: Array, spacing: float, tail: float) -> PackedFloat32Array:
	var dur := spacing * notes.size() + tail
	var b := S.make(dur)
	for i in notes.size():
		var n := S.bell(tail, notes[i], [1.0, 2.0, 3.01, 4.2], [0.6, 0.2, 0.1, 0.06], [tail * 0.5, tail * 0.3, tail * 0.15, 0.08])
		S.add(b, n, 0.8, S.samples(i * spacing))
	return S.reverb(b, 0.75, 0.3, 0.3)


static func _quest(_r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := S.make(1.8)
	var chords := [[587.3, 740.0, 880.0], [784.0, 987.8, 1174.7]]
	for c in chords.size():
		for f: float in chords[c]:
			var n := S.bell(1.3, f, [1.0, 2.0, 3.0], [0.4, 0.12, 0.05], [0.7, 0.3, 0.15])
			S.add(b, n, 0.5, S.samples(c * 0.32))
	return S.reverb(b, 0.8, 0.3, 0.35)


## Item into the pack: a leather / cloth handling sound with a soft glint.
static func _pickup(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var files := ["handleSmallLeather.ogg", "handleSmallLeather2.ogg", "dropLeather.ogg"]
	var leather := K.smp(KR + files[v % files.size()], K.jit(r, 0.05), 0.35)
	var glint := S.bell(0.5, 1975.5 * K.jit(r, 0.01), [1.0, 2.0, 3.01], [0.5, 0.12, 0.05], [0.18, 0.1, 0.05])
	S.add(glint, S.bell(0.5, 2637.0, [1.0, 2.0], [0.4, 0.1], [0.16, 0.08]), 0.6, S.samples(0.06))
	return K.mix([[leather, 0.8, 0.0], [glint, 0.22, 0.03]])


static func _coin(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var purse := K.smp(KR + ("handleCoins.ogg" if v != 1 else "handleCoins2.ogg"), K.jit(r, 0.05), 0.45, 300.0)
	var b := K.mix([[purse, 0.55, 0.0]])
	# Two or three bright coin "tings" (thin-disc modes).
	for i in r.randi_range(2, 3):
		var f := r.randf_range(2900.0, 4200.0)
		var ting := S.bell(0.4, f, [1.0, 1.52, 2.33, 3.17], [0.5, 0.3, 0.18, 0.08], [0.16, 0.1, 0.06, 0.04])
		b = K.mix([[b, 1.0, 0.0], [ting, 0.35, 0.02 + i * r.randf_range(0.05, 0.09)]])
	return b


static func _potion(r: RandomNumberGenerator) -> PackedFloat32Array:
	# Cork pop, glass clink, then three or four glugs (big slow bubbles).
	var b := S.make(1.1)
	var pop := S.bp(S.decay(S.noise(0.05, r), 0.0003, 0.006), 1500.0, 1.5)
	S.add(b, pop, 1.0)
	S.add(b, K.thump(0.06, 900.0, 500.0, 0.01, 0.02), 0.4)
	var clink := S.bell(0.4, 2300.0 * K.jit(r, 0.03), [1.0, 2.32, 4.25], [0.4, 0.2, 0.08], [0.12, 0.07, 0.04])
	S.add(b, clink, 0.25, S.samples(0.1))
	var t := 0.28
	for i in r.randi_range(3, 4):
		S.bubble(b, t, r.randf_range(180.0, 320.0), 0.5, 0.03, 0.6)
		S.bubble(b, t + 0.03, r.randf_range(400.0, 700.0), 0.25, 0.015, 0.4)
		var gl := S.lp(S.decay(S.noise(0.12, r), 0.01, 0.03), 900.0)
		S.add(b, gl, 0.5, S.samples(t))
		t += r.randf_range(0.16, 0.22)
	return S.lp(b, 6000.0)


static func _gem(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var glass := K.ki("impactGlass_light", v, K.jit(r, 0.08), 0.25)
	var f := r.randf_range(1900.0, 2500.0)
	var ring := S.bell(1.4, f, [1.0, 2.32, 4.25, 6.63, 9.38], [0.5, 0.3, 0.18, 0.1, 0.05], [0.7, 0.45, 0.3, 0.18, 0.1])
	var sparkle := S.make(1.0)
	for i in 6:
		var s := S.bell(0.4, r.randf_range(4500.0, 9000.0), [1.0, 2.7], [0.4, 0.1], [0.12, 0.06])
		S.add(sparkle, s, r.randf_range(0.1, 0.25), S.samples(r.randf_range(0.05, 0.6)))
	var b := K.mix([[glass, 0.6, 0.0], [ring, 0.35, 0.005], [sparkle, 0.4, 0.0]])
	return S.reverb(b, 0.7, 0.4, 0.2)


# --- Footsteps -------------------------------------------------------------------

static func _step_grass(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var s := K.ki("footstep_grass", v, K.jit(r, 0.07), 0.3, 70.0)
	# Blades brushing the boot: soft high swish plus a few stalk snaps.
	var swish := K.whoosh(r, 0.22, [Vector2(0, 3000), Vector2(0.2, 5500)], 0.9,
			[Vector2(0, 0), Vector2(0.03, 1.0), Vector2(0.22, 0)])
	var stalks := S.grains(0.2, r.randi_range(6, 14), r, 1800.0, 6000.0, 0.0006, 0.002, 1.5)
	return K.mix([[s, 1.0, 0.0], [swish, 0.12, 0.0], [stalks, 0.18, 0.01]])


static func _step_dirt(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var s := K.smp(KR + "footstep%02d.ogg" % (v * 3 % 10), K.jit(r, 0.06), 0.3, 60.0)
	var grit := K.grit(r, 0.2, r.randi_range(15, 30), 1500.0, 7000.0)
	return K.mix([[s, 1.0, 0.0], [grit, 0.25, 0.012]])


static func _step_stone(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var s := K.ki("footstep_concrete", v, K.jit(r, 0.06), 0.25, 110.0)
	S.hp(s, 110.0)
	# Hard surface: a crisp heel tick and loose grit, a faint low knock.
	var tick := K.click(r, 0.0015, 3000.0)
	var grit := K.grit(r, 0.16, r.randi_range(10, 22))
	var knock := K.thump(0.08, 170.0, 110.0, 0.012, 0.03)
	return K.mix([[s, 1.0, 0.0], [tick, 0.35, 0.0], [grit, 0.35, 0.008], [knock, 0.12, 0.0]])


static func _step_wood(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var s := K.ki("footstep_wood", v, K.jit(r, 0.06), 0.25, 80.0)
	S.hp(s, 80.0)
	# Hollow boards: the impact excites a few plank modes over the void below.
	var ex := S.decay(S.noise(0.02, r), 0.0003, 0.003)
	var f0 := r.randf_range(140.0, 190.0)
	var hollow := S.normalize(S.modal(ex, [f0, f0 * 2.31, f0 * 4.1, f0 * 6.3], [0.035, 0.026, 0.018, 0.012], [1.0, 0.7, 0.45, 0.25], 0.2))
	var scuff := K.grit(r, 0.12, r.randi_range(6, 14), 1500.0, 6000.0)
	var creak := S.grains(0.12, r.randi_range(0, 3), r, 900.0, 2200.0, 0.004, 0.012, 1.0)
	return K.mix([[s, 1.0, 0.0], [hollow, 0.4, 0.0], [scuff, 0.2, 0.004], [creak, 0.15, 0.05]])


static func _step_snow(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var s := K.ki("footstep_snow", v, K.jit(r, 0.06), 0.3, 80.0)
	# Compacting snow: dense micro-fractures that crowd the first 120 ms.
	var crunch := S.grains(0.2, r.randi_range(90, 140), r, 1500.0, 7000.0, 0.0004, 0.0018, 1.4, 0.1)
	var squeak := S.bp(S.decay(S.noise(0.15, r), 0.02, 0.04), 1100.0 * K.jit(r, 0.15), 6.0)
	return K.mix([[s, 1.0, 0.0], [crunch, 0.35, 0.005], [squeak, 0.06, 0.02]])


static func _step_sand(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	# Dull padded footfall, then sand grains sliding and hissing off the sole.
	var s := K.smp(KR + "footstep%02d.ogg" % ((v * 7 + 1) % 10), K.jit(r, 0.05) * 0.92, 0.3, 60.0)
	S.lp(s, 1400.0)
	var grains := S.grains(0.3, r.randi_range(160, 240), r, 2500.0, 11000.0, 0.0002, 0.0008, 1.6, 0.12)
	var slide := K.whoosh(r, 0.28, [Vector2(0, 5000), Vector2(0.28, 3000)], 0.8,
			[Vector2(0, 0), Vector2(0.025, 1.0), Vector2(0.1, 0.4), Vector2(0.28, 0)])
	return K.mix([[s, 0.9, 0.0], [grains, 0.35, 0.004], [slide, 0.12, 0.0]])


## Sprinting: a harder heel strike with a sole scuff dragged forward.
static func _step_run(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var s := K.smp(KR + "footstep%02d.ogg" % ((v * 3 + 5) % 10), K.jit(r, 0.06) * 1.04, 0.3, 60.0)
	var scuff := K.whoosh(r, 0.14, [Vector2(0, 1400), Vector2(0.12, 3200)], 1.1,
			[Vector2(0, 0), Vector2(0.015, 1.0), Vector2(0.14, 0)])
	var grit := K.grit(r, 0.18, r.randi_range(15, 30), 1500.0, 7000.0)
	var cloth := K.smp(KR + "cloth%d.ogg" % (1 + v % 4), K.jit(r, 0.1) * 1.2, 0.18, 300.0)
	return K.mix([[s, 1.0, 0.0], [scuff, 0.18, 0.03], [grit, 0.25, 0.03], [cloth, 0.15, 0.0]])


# --- Body movement ------------------------------------------------------------------

static func _cloth(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var files := ["cloth1.ogg", "cloth2.ogg", "cloth3.ogg", "cloth4.ogg", "clothBelt.ogg"]
	return K.smp(KR + files[v % files.size()], K.jit(r, 0.08), 0.6, 150.0)


static func _jump(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	# Push-off: the sole scuffs and grips, clothes and gear lift.
	var push := K.smp(KR + "footstep%02d.ogg" % ((v * 3 + 2) % 10), K.jit(r, 0.05) * 1.05, 0.12, 80.0)
	var cloth := K.smp(KR + "cloth%d.ogg" % (1 + (v + 1) % 4), K.jit(r, 0.08), 0.35, 200.0)
	var air := K.whoosh(r, 0.3, [Vector2(0, 500), Vector2(0.25, 1300)], 0.8,
			[Vector2(0, 0), Vector2(0.08, 1.0), Vector2(0.3, 0)])
	var gear := K.smp(KR + "beltHandle%d.ogg" % (1 + v % 2), K.jit(r, 0.06), 0.25, 400.0)
	return K.mix([[push, 0.75, 0.0], [cloth, 0.55, 0.02], [air, 0.25, 0.02], [gear, 0.2, 0.05]])


static func _land(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	# Both feet a few ms apart, weight thud, knees and clothes settling.
	var thud := K.ki("impactSoft_medium", v, K.jit(r, 0.06), 0.2, 50.0)
	S.lp(thud, 1500.0)
	var f1 := K.smp(KR + "footstep%02d.ogg" % ((v * 3 + 4) % 10), K.jit(r, 0.05), 0.25, 60.0)
	var f2 := K.smp(KR + "footstep%02d.ogg" % ((v * 3 + 7) % 10), K.jit(r, 0.05), 0.25, 60.0)
	var cloth := K.smp(KR + "cloth%d.ogg" % (1 + v % 4), K.jit(r, 0.08), 0.3, 200.0)
	var grit := K.grit(r, 0.3, r.randi_range(20, 40), 1200.0, 6000.0)
	return K.mix([[thud, 0.55, 0.0], [f1, 0.8, 0.0], [f2, 0.65, r.randf_range(0.012, 0.03)],
			[cloth, 0.35, 0.03], [grit, 0.3, 0.01]])


static func _land_heavy(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var thud := K.ki("impactSoft_heavy", v, K.jit(r, 0.05) * 0.85, 0.5, 30.0)
	var body := K.ki("impactPunch_heavy", v + 2, K.jit(r, 0.05) * 0.8, 0.4)
	S.lp(body, 900.0)
	var feet := _land(r, v)
	var sub := K.thump(0.5, 70.0, 34.0, 0.12, 0.15)
	var debris := S.grains(0.6, r.randi_range(50, 80), r, 600.0, 5000.0, 0.001, 0.005, 1.8, 0.25, 0.02)
	return K.mix([[thud, 0.8, 0.0], [body, 0.45, 0.0], [feet, 0.6, 0.0], [sub, 0.5, 0.0], [debris, 0.35, 0.0]])


static func _roll(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var dur := 0.75
	var cloth := K.smp(KR + "cloth%d.ogg" % (1 + v % 4), K.jit(r, 0.06), 0.6, 150.0)
	var cloth2 := K.smp(KR + "clothBelt%s.ogg" % ("" if v % 2 == 0 else "2"), K.jit(r, 0.06), 0.6, 200.0)
	var t1 := K.ki("impactSoft_medium", v, K.jit(r, 0.06), 0.2)
	var t2 := K.ki("impactSoft_medium", v + 2, K.jit(r, 0.06) * 1.1, 0.2)
	S.lp(t1, 1200.0)
	S.lp(t2, 1200.0)
	# Shoulder and back scraping the ground.
	var scrape := K.whoosh(r, dur, [Vector2(0, 900), Vector2(0.4, 1800), Vector2(dur, 700)], 0.8,
			[Vector2(0, 0), Vector2(0.08, 0.8), Vector2(0.35, 1.0), Vector2(dur, 0)])
	var grit := S.grains(dur, r.randi_range(60, 100), r, 1200.0, 7000.0, 0.0005, 0.002, 1.0)
	S.env(grit, [Vector2(0, 0), Vector2(0.1, 1.0), Vector2(dur, 0)])
	var foot := K.smp(KR + "footstep%02d.ogg" % ((v * 3 + 1) % 10), K.jit(r, 0.05), 0.25, 60.0)
	return K.mix([[cloth, 0.6, 0.0], [cloth2, 0.3, 0.1], [t1, 0.55, 0.06], [t2, 0.4, 0.28],
			[scrape, 0.22, 0.04], [grit, 0.3, 0.04], [foot, 0.6, 0.55]])


static func _equip(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	# Blade drawn: the hiss of steel leaving the scabbard, leather creak, a click.
	var draw := K.smp(KR + "drawKnife%d.ogg" % (1 + v % 3), K.jit(r, 0.06) * 0.9, 0.0, 200.0)
	var leather := K.smp(KR + "handleSmallLeather%s.ogg" % ("" if v % 2 == 0 else "2"), K.jit(r, 0.06), 0.3, 150.0)
	var ring := S.bell(0.8, r.randf_range(2600.0, 3400.0), [1.0, 2.76, 5.4], [0.4, 0.2, 0.08], [0.35, 0.2, 0.1])
	var hiss := K.whoosh(r, 0.35, [Vector2(0, 3500), Vector2(0.3, 6500)], 3.0,
			[Vector2(0, 0), Vector2(0.25, 0.8), Vector2(0.35, 0)])
	return K.mix([[leather, 0.5, 0.0], [draw, 1.0, 0.05], [hiss, 0.12, 0.05], [ring, 0.07, 0.36]])


static func _equip_metal(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var files := ["beltHandle1.ogg", "beltHandle2.ogg", "metalClick.ogg", "metalLatch.ogg"]
	var base := K.smp(KR + files[v % files.size()], K.jit(r, 0.06), 0.5, 150.0)
	# Mail / plates settling: a scatter of small, bright, ringing contacts.
	var ex := S.make(0.5)
	for i in r.randi_range(6, 11):
		S.add(ex, S.decay(S.noise(0.004, r), 0.0001, 0.0008), r.randf_range(0.3, 1.0), S.samples(r.randf_range(0.0, 0.3)))
	var f := r.randf_range(2200.0, 3200.0)
	var jingle := S.normalize(S.modal(ex, [f, f * 1.47, f * 2.09, f * 2.81], [0.05, 0.04, 0.03, 0.02], [1.0, 0.7, 0.5, 0.3], 0.6))
	var cloth := K.smp(KR + "cloth%d.ogg" % (1 + v % 4), K.jit(r, 0.06), 0.4, 200.0)
	return K.mix([[base, 0.8, 0.0], [jingle, 0.45, 0.02], [cloth, 0.35, 0.0]])


static func _equip_cloth(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var a := K.smp(KR + ("clothBelt.ogg" if v % 2 == 0 else "clothBelt2.ogg"), K.jit(r, 0.06), 0.7, 150.0)
	var b := K.smp(KR + "cloth%d.ogg" % (1 + v % 4), K.jit(r, 0.06), 0.5, 150.0)
	var leather := K.smp(KR + "handleSmallLeather%s.ogg" % ("" if v < 2 else "2"), K.jit(r, 0.06), 0.3, 150.0)
	return K.mix([[a, 0.8, 0.0], [b, 0.6, 0.12], [leather, 0.35, 0.3]])


# --- Weapons ----------------------------------------------------------------------

## A blade cutting the air past the ear: broadband rush whose band climbs and
## falls (doppler-ish) plus a narrow edge tone; the envelope swells then snaps
## off as the blade passes.
static func _swing(r: RandomNumberGenerator, dur_base: float, bright: float, edge: float) -> PackedFloat32Array:
	var dur := dur_base * r.randf_range(0.88, 1.15)
	var peak := dur * r.randf_range(0.5, 0.62)
	var f_lo := 380.0 * bright * K.jit(r, 0.12)
	var f_hi := 2000.0 * bright * K.jit(r, 0.15)
	var shape := [Vector2(0, 0), Vector2(peak * 0.5, 0.25), Vector2(peak, 1.0), Vector2(peak + dur * 0.12, 0.35), Vector2(dur, 0)]
	var rush := K.whoosh(r, dur, [Vector2(0, f_lo), Vector2(peak, f_hi), Vector2(dur, f_lo * 1.3)], 1.3, shape)
	var e_lo := 1500.0 * bright * K.jit(r, 0.1)
	var tone := S.filter(S.noise(dur, r), S.Filter.BANDPASS, [Vector2(0, e_lo), Vector2(peak, e_lo * 2.1), Vector2(dur, e_lo * 1.1)], 9.0)
	S.env(tone, shape)
	var body := S.lp(S.pink(dur, r), 350.0)
	S.env(body, shape)
	return K.mix([[rush, 1.0, 0.0], [tone, edge * 0.8, 0.0], [body, 0.5, 0.0]])


static func _swing_heavy(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := r.randf_range(0.42, 0.52)
	var b := _swing(r, dur, 0.62, 0.35)
	var whomp := S.lp(S.pink(dur, r), 260.0)
	S.env(whomp, [Vector2(0, 0), Vector2(dur * 0.55, 1.0), Vector2(dur * 0.75, 0.3), Vector2(dur, 0)])
	var cloth := K.smp(KR + "cloth%d.ogg" % r.randi_range(1, 4), K.jit(r, 0.06), 0.4, 200.0)
	return K.mix([[b, 1.0, 0.0], [whomp, 0.9, 0.0], [cloth, 0.25, 0.0]])


## Club / hammer: no edge tone; a deeper rush that flutters as the head tumbles air.
static func _swing_blunt(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := r.randf_range(0.36, 0.44)
	var peak := dur * 0.55
	var shape := [Vector2(0, 0), Vector2(peak, 1.0), Vector2(peak + 0.05, 0.4), Vector2(dur, 0)]
	var rush := K.whoosh(r, dur, [Vector2(0, 220), Vector2(peak, 900), Vector2(dur, 300)], 1.0, shape)
	var flutter := S.tone(dur, S.Wave.SINE, r.randf_range(26.0, 38.0))
	S.modulate(rush, flutter, 0.45)
	var low := S.lp(S.pink(dur, r), 200.0)
	S.env(low, shape)
	return K.mix([[rush, 1.0, 0.0], [low, 1.1, 0.0]])


static func _arrow(r: RandomNumberGenerator) -> PackedFloat32Array:
	# Fletching whirr dopplering away from the bow.
	var dur := 0.45
	var b := S.filter(S.noise(dur, r), S.Filter.BANDPASS, [Vector2(0, 4200 * K.jit(r, 0.1)), Vector2(dur, 1600)], 5.0)
	S.env(b, [Vector2(0, 0), Vector2(0.02, 1.0), Vector2(0.15, 0.5), Vector2(dur, 0)])
	var flutter := S.tone(dur, S.Wave.SINE, r.randf_range(60.0, 90.0))
	S.modulate(b, flutter, 0.3)
	var air := K.whoosh(r, dur, [Vector2(0, 2500), Vector2(dur, 900)], 1.0,
			[Vector2(0, 0), Vector2(0.015, 1.0), Vector2(dur, 0)])
	return K.mix([[b, 1.0, 0.0], [air, 0.5, 0.0]])


static func _bow(r: RandomNumberGenerator) -> PackedFloat32Array:
	# Limb creak on the draw, then the string's release: a low twang and a slap.
	var creak := K.smp(KR + "creak%d.ogg" % r.randi_range(1, 3), K.jit(r, 0.08) * 1.6, 0.18, 300.0)
	var string := S.pluck(0.5, 92.0 * K.jit(r, 0.05), 0.993, 0.75, r)
	S.decay(string, 0.001, 0.12)
	var slap := S.bp(S.decay(S.noise(0.05, r), 0.0003, 0.008), 1800.0, 1.2)
	var thwip := K.whoosh(r, 0.12, [Vector2(0, 1500), Vector2(0.1, 4000)], 2.0,
			[Vector2(0, 0), Vector2(0.01, 1.0), Vector2(0.12, 0)])
	return K.mix([[creak, 0.35, 0.0], [string, 1.0, 0.12], [slap, 0.8, 0.12], [thwip, 0.4, 0.13]])


# --- Hits -------------------------------------------------------------------------

## Blade into a body: a meaty punch, a wet tear and a short slice.
static func _hit(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var flesh := _hit_flesh(r, v)
	var slice := K.whoosh(r, 0.09, [Vector2(0, 2500), Vector2(0.08, 6000)], 1.5,
			[Vector2(0, 0), Vector2(0.005, 1.0), Vector2(0.09, 0)])
	return K.mix([[flesh, 1.0, 0.0], [slice, 0.25, 0.0]])


static func _hit_flesh(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var punch := K.ki("impactPunch_medium", v, K.jit(r, 0.07), 0.4, 50.0)
	var smack := K.click(r, 0.002, 1200.0)
	# Wet, squelchy micro-texture in the low mids.
	var wet := S.grains(0.12, r.randi_range(8, 16), r, 300.0, 1600.0, 0.002, 0.006, 1.6)
	var sub := K.thump(0.25, 110.0, 50.0, 0.05, 0.06)
	return K.mix([[punch, 1.0, 0.0], [smack, 0.35, 0.0], [wet, 0.35, 0.004], [sub, 0.45, 0.0]])


static func _hit_heavy(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var punch := K.ki("impactPunch_heavy", v, K.jit(r, 0.06), 0.6, 35.0)
	var crunch := S.grains(0.2, r.randi_range(15, 25), r, 500.0, 3500.0, 0.001, 0.005, 1.8)
	var sub := K.thump(0.6, 80.0, 30.0, 0.14, 0.12)
	var b := K.mix([[punch, 1.0, 0.0], [crunch, 0.4, 0.002], [sub, 0.7, 0.0]])
	return S.soft_clip(b, 1.3)


static func _crit(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var b := _hit_heavy(r, v)
	var f := r.randf_range(1100.0, 1400.0)
	var ring := S.bell(0.9, f, [1.0, 2.35, 3.31, 4.7, 6.1], [0.5, 0.35, 0.25, 0.12, 0.06], [0.45, 0.3, 0.18, 0.1, 0.06])
	var slice := K.whoosh(r, 0.15, [Vector2(0, 3000), Vector2(0.12, 8000)], 1.5,
			[Vector2(0, 0), Vector2(0.005, 1.0), Vector2(0.15, 0)])
	return K.mix([[b, 0.9, 0.0], [ring, 0.35, 0.0], [slice, 0.3, 0.0]])


## Dry bone: a sharp crack, hollow knock modes and a little skeletal rattle.
static func _hit_bone(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var wood := K.ki("impactWood_light", v, K.jit(r, 0.08) * 1.35, 0.25, 120.0)
	var crack := K.click(r, 0.0012, 2000.0)
	var ex := S.decay(S.noise(0.01, r), 0.0002, 0.0015)
	var f := r.randf_range(850.0, 1150.0)
	var knock := S.normalize(S.modal(ex, [f, f * 1.83, f * 2.9, f * 4.2], [0.03, 0.022, 0.015, 0.01], [1.0, 0.7, 0.45, 0.25], 0.25))
	var rattle := S.make(0.3)
	for i in r.randi_range(4, 8):
		var e := S.decay(S.noise(0.004, r), 0.0001, 0.0006)
		var ff := r.randf_range(1400.0, 3800.0)
		var tk := S.modal(e, [ff, ff * 1.7], [0.012, 0.008], [1.0, 0.5], 0.08)
		S.add(rattle, tk, r.randf_range(0.2, 0.6), S.samples(0.03 + pow(r.randf(), 1.5) * 0.2))
	S.normalize(rattle)
	return K.mix([[wood, 0.8, 0.0], [crack, 0.5, 0.0], [knock, 0.6, 0.0], [rattle, 0.4, 0.0]])


## Steel on armour: recorded metal impact plus a long inharmonic ring.
static func _hit_metal(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var hit := K.ki("impactMetal_medium" if v % 2 == 0 else "impactMetal_heavy", v, K.jit(r, 0.06), 0.35)
	var ex := S.decay(S.noise(0.006, r), 0.0001, 0.001)
	var f := r.randf_range(850.0, 1300.0)
	var ring := S.modal(ex, [f, f * 1.41, f * 2.23, f * 2.76, f * 3.9, f * 5.4], [0.35, 0.3, 0.22, 0.18, 0.12, 0.08],
			[0.7, 0.5, 0.6, 0.45, 0.3, 0.2], 0.9)
	S.normalize(ring)
	var scrape := K.whoosh(r, 0.18, [Vector2(0, 5000), Vector2(0.15, 3000)], 3.0,
			[Vector2(0, 0), Vector2(0.004, 1.0), Vector2(0.18, 0)])
	return K.mix([[hit, 1.0, 0.0], [ring, 0.5, 0.0], [scrape, 0.15, 0.0]])


static func _hit_wood(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var hit := K.ki("impactWood_medium" if v % 2 == 0 else "impactWood_heavy", v, K.jit(r, 0.07), 0.35, 60.0)
	var plank := K.ki("impactPlank_medium", v + 1, K.jit(r, 0.07), 0.3)
	var splinter := S.grains(0.15, r.randi_range(5, 12), r, 2000.0, 7000.0, 0.0005, 0.002, 1.5)
	return K.mix([[hit, 1.0, 0.0], [plank, 0.35, 0.0], [splinter, 0.25, 0.003]])


## The hero takes a blow: a body impact and a short, breathy grunt.
static func _hurt(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var body := K.ki("impactPunch_medium", v + 3, K.jit(r, 0.05), 0.3)
	var dur := 0.26
	var f0 := r.randf_range(105.0, 135.0)
	var glottal := S.osc(dur, S.Wave.SAW, [Vector2(0, f0 * 1.15), Vector2(0.05, f0), Vector2(dur, f0 * 0.8)])
	S.lp(glottal, 1800.0)
	var breath := S.pink(dur, r)
	S.add(breath, glottal, 0.35)
	var vowel := S.formants(breath, [620.0 * K.jit(r, 0.05), 1150.0, 2450.0], [1.0, 0.55, 0.2], 5.0)
	S.env(vowel, [Vector2(0, 0), Vector2(0.015, 1.0), Vector2(0.08, 0.55), Vector2(dur, 0)])
	return K.mix([[body, 1.0, 0.0], [vowel, 0.55, 0.01]])


static func _death(r: RandomNumberGenerator) -> PackedFloat32Array:
	var fall := K.ki("impactSoft_heavy", 2, 0.85, 0.6, 30.0)
	var knees := K.ki("impactSoft_medium", 1, 0.9, 0.2)
	var gear := K.smp(KR + "beltHandle2.ogg", 0.85, 0.4, 200.0)
	var cloth := K.smp(KR + "cloth1.ogg", 0.9, 0.5, 150.0)
	var dur := 1.8
	var exhale := S.formants(S.pink(1.0, r), [500.0, 1000.0, 2300.0], [1.0, 0.5, 0.15], 4.0)
	S.env(exhale, [Vector2(0, 0), Vector2(0.1, 0.8), Vector2(1.0, 0)])
	var rumble := S.lp(S.brown(dur, r), 160.0)
	S.env(rumble, [Vector2(0, 0), Vector2(0.4, 0.0), Vector2(0.5, 1.0), Vector2(dur, 0)])
	var b := K.mix([[exhale, 0.25, 0.0], [knees, 0.6, 0.2], [cloth, 0.5, 0.2], [fall, 1.0, 0.5], [gear, 0.4, 0.52],
			[rumble, 0.6, 0.0]])
	return S.reverb(b, 0.8, 0.5, 0.25)


# --- Mining and building ---------------------------------------------------------------

## Pickaxe on rock: the recorded clink plus chips and crumbs falling away.
static func _pick_stone(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var clink := K.ki("impactMining", v, K.jit(r, 0.07), 0.55)
	var chips := S.grains(0.3, r.randi_range(15, 30), r, 900.0, 5000.0, 0.001, 0.004, 1.8, 0.1)
	var crumbs := S.grains(0.5, r.randi_range(8, 16), r, 1500.0, 6000.0, 0.0008, 0.003, 1.0, 0.0, 0.12)
	return K.mix([[clink, 1.0, 0.0], [chips, 0.35, 0.004], [crumbs, 0.18, 0.0]])


## Digging: blade thuds into soil; clods crunch and trickle.
static func _pick_dirt(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var thud := K.ki("impactSoft_medium", v, K.jit(r, 0.08), 0.25, 50.0)
	S.lp(thud, 1500.0)
	var tip := S.bell(0.08, r.randf_range(1800.0, 2400.0), [1.0, 2.6], [0.5, 0.2], [0.02, 0.01])
	var crunch := S.grains(0.18, r.randi_range(30, 50), r, 250.0, 2500.0, 0.002, 0.007, 1.6, 0.06)
	var shh := S.lp(S.pink(0.3, r), 1800.0)
	S.env(shh, [Vector2(0, 0), Vector2(0.015, 1.0), Vector2(0.3, 0)])
	var trickle := S.grains(0.6, r.randi_range(15, 30), r, 600.0, 3500.0, 0.001, 0.004, 1.0, 0.0, 0.12)
	S.env(trickle, [Vector2(0, 1), Vector2(0.6, 0)])
	return K.mix([[thud, 0.9, 0.0], [tip, 0.15, 0.0], [crunch, 0.6, 0.003], [shh, 0.3, 0.0], [trickle, 0.25, 0.0]])


## Axe / pick biting into wood.
static func _pick_wood(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var chop := K.smp(KR + "chop.ogg", K.jit(r, 0.1), 0.3)
	var body := K.ki("impactWood_medium", v, K.jit(r, 0.07), 0.3, 60.0)
	var splinter := S.grains(0.15, r.randi_range(8, 16), r, 2000.0, 7000.0, 0.0005, 0.002, 1.5)
	var ex := S.decay(S.noise(0.01, r), 0.0002, 0.002)
	var f := r.randf_range(240.0, 320.0)
	var trunk := S.normalize(S.modal(ex, [f, f * 2.4, f * 4.4], [0.06, 0.04, 0.025], [1.0, 0.5, 0.25], 0.3))
	return K.mix([[chop, 0.7 if v % 2 == 0 else 0.35, 0.0], [body, 0.8, 0.0], [splinter, 0.3, 0.002], [trunk, 0.4, 0.0]])


## Rock fracturing: a sharp crack and a thud, then rubble cascading and
## settling, the odd stone knocking on stone, and dust.
static func _break_stone(r: RandomNumberGenerator, scale: float) -> PackedFloat32Array:
	var dur := 1.1
	var crack := K.click(r, 0.006, 900.0, 0.08)
	var hit := K.ki("impactMining", r.randi_range(0, 4), K.jit(r, 0.06) * 0.8, 0.12)
	var thud := K.thump(0.4, 95.0 * scale, 42.0, 0.09, 0.1)
	var rubble := S.grains(dur, int(r.randi_range(90, 130) * scale), r, 350.0, 3800.0, 0.002, 0.012, 1.9, 0.35)
	var knocks := S.make(dur)
	for i in r.randi_range(5, 9):
		var e := S.decay(S.noise(0.005, r), 0.0001, 0.001)
		var f := r.randf_range(900.0, 2600.0)
		var k := S.modal(e, [f, f * 1.6, f * 2.3], [0.02, 0.014, 0.01], [1.0, 0.5, 0.3], 0.1)
		S.add(knocks, k, r.randf_range(0.2, 0.7) * (1.0 - float(i) / 10.0), S.samples(0.05 + pow(r.randf(), 1.3) * 0.75))
	S.normalize(knocks)
	var dust := S.lp(S.pink(dur, r), 2200.0)
	S.env(dust, [Vector2(0, 0), Vector2(0.03, 0.6), Vector2(dur, 0)])
	return K.mix([[crack, 0.6, 0.0], [hit, 0.35, 0.0], [thud, 0.8, 0.0], [rubble, 0.9, 0.005], [knocks, 0.45, 0.0],
			[dust, 0.2, 0.0]])


static func _break_dirt(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 0.9
	var thud := K.ki("impactSoft_heavy", r.randi_range(0, 4), K.jit(r, 0.06), 0.4, 40.0)
	S.lp(thud, 1000.0)
	var crumble := S.grains(dur, r.randi_range(80, 120), r, 150.0, 2000.0, 0.003, 0.012, 1.7, 0.3)
	var shh := S.filter(S.pink(dur, r), S.Filter.LOWPASS, [Vector2(0, 2500), Vector2(dur, 700)], 0.7)
	S.env(shh, [Vector2(0, 0), Vector2(0.02, 1.0), Vector2(0.25, 0.4), Vector2(dur, 0)])
	var trickle := S.grains(dur, r.randi_range(25, 40), r, 800.0, 4000.0, 0.001, 0.003, 1.0, 0.0, 0.15)
	S.env(trickle, [Vector2(0, 1), Vector2(dur, 0)])
	return K.mix([[thud, 0.9, 0.0], [crumble, 0.8, 0.0], [shh, 0.3, 0.0], [trickle, 0.25, 0.0]])


static func _break_wood(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var dur := 0.9
	var plank := K.ki("impactPlank_medium", v, K.jit(r, 0.06), 0.7)
	var snap := S.grains(0.2, r.randi_range(40, 70), r, 1500.0, 7000.0, 0.0006, 0.003, 2.0)
	# Fibres tearing: rasping crackle that thins out.
	var tear := S.grains(0.4, r.randi_range(30, 60), r, 700.0, 3500.0, 0.002, 0.006, 1.2, 0.0, 0.03)
	S.env(tear, [Vector2(0, 0), Vector2(0.05, 1.0), Vector2(0.4, 0)])
	var pieces := S.make(dur)
	for i in r.randi_range(3, 5):
		var e := S.decay(S.noise(0.008, r), 0.0002, 0.0015)
		var f := r.randf_range(300.0, 700.0)
		var k := S.modal(e, [f, f * 2.6, f * 4.9], [0.04, 0.025, 0.015], [1.0, 0.5, 0.25], 0.15)
		S.add(pieces, k, r.randf_range(0.3, 0.7), S.samples(0.15 + r.randf() * 0.6))
	S.normalize(pieces)
	return K.mix([[plank, 0.9, 0.0], [snap, 0.5, 0.0], [tear, 0.4, 0.01], [pieces, 0.35, 0.0]])


static func _break_crystal(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var dur := 1.4
	var glass := K.ki("impactGlass_heavy" if v != 1 else "impactGlass_medium", v, K.jit(r, 0.06), 0.6)
	var f := r.randf_range(1300.0, 1800.0)
	var ring := S.bell(dur, f, [1.0, 2.32, 4.25, 6.63, 9.38], [0.5, 0.35, 0.2, 0.12, 0.06], [0.8, 0.5, 0.3, 0.2, 0.1])
	var tinkle := S.make(dur)
	for i in r.randi_range(14, 22):
		var ff := r.randf_range(2500.0, 8000.0)
		var tk := S.bell(0.4, ff, [1.0, 2.41, 3.9], [0.5, 0.25, 0.1], [0.12, 0.07, 0.04])
		S.add(tinkle, tk, r.randf_range(0.1, 0.4) * (1.0 - float(i) / 25.0), S.samples(0.03 + pow(r.randf(), 1.6) * 0.9))
	var b := K.mix([[glass, 1.0, 0.0], [ring, 0.3, 0.0], [tinkle, 0.5, 0.0]])
	return S.reverb(b, 0.75, 0.3, 0.2)


static func _block_place(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var tap := K.ki("impactGeneric_light", v, K.jit(r, 0.08), 0.2)
	var thud := K.ki("impactSoft_medium", v + 1, K.jit(r, 0.06) * 1.1, 0.15)
	S.lp(thud, 1200.0)
	var grit := K.grit(r, 0.15, r.randi_range(6, 12), 1500.0, 6000.0)
	return K.mix([[tap, 0.8, 0.0], [thud, 0.6, 0.0], [grit, 0.2, 0.005]])


# --- Crafting ---------------------------------------------------------------------

static func _craft(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	# Handling materials at a bench: two or three taps and some rustle.
	var b := S.make(0.9)
	var t := 0.0
	for i in r.randi_range(2, 3):
		var tap := K.ki("impactWood_light", v + i, K.jit(r, 0.1), 0.2)
		S.add(b, tap, r.randf_range(0.5, 0.9), S.samples(t))
		t += r.randf_range(0.14, 0.26)
	var cloth := K.smp(KR + "cloth%d.ogg" % (1 + (v + 2) % 4), K.jit(r, 0.06), 0.5, 200.0)
	var gear := K.smp(KR + "beltHandle%d.ogg" % (1 + v % 2), K.jit(r, 0.06), 0.3, 300.0)
	return K.mix([[b, 1.0, 0.0], [cloth, 0.4, 0.05], [gear, 0.25, t]])


## Hand saw: push / pull strokes; each tooth plucks the wood (a buzzy band
## gated at the tooth rate) and the board resonates; sawdust hiss.
static func _saw(r: RandomNumberGenerator) -> PackedFloat32Array:
	var strokes := 2 + r.randi_range(0, 1)
	var stroke_len := r.randf_range(0.3, 0.38)
	var dur := strokes * stroke_len + 0.1
	var b := S.make(dur)
	for s in strokes:
		var push := s % 2 == 0
		var rate := r.randf_range(70.0, 110.0) * (1.15 if push else 0.9)
		var teeth := S.osc(stroke_len, S.Wave.SAW, [Vector2(0, rate * 0.8), Vector2(stroke_len * 0.5, rate * 1.1), Vector2(stroke_len, rate * 0.7)])
		for i in teeth.size():
			teeth[i] = maxf(0.0, teeth[i])
		var rasp := S.filter(S.noise(stroke_len, r), S.Filter.BANDPASS, [Vector2(0, 2600 if push else 2100)], 1.2)
		S.mul(rasp, teeth)
		var board := S.normalize(S.modal(rasp.duplicate(), [420.0, 980.0, 1700.0], [0.03, 0.02, 0.015], [0.4, 0.3, 0.2]), S.peak(rasp))
		S.add(rasp, board, 0.6)
		S.env(rasp, [Vector2(0, 0), Vector2(0.05, 1.0), Vector2(stroke_len - 0.06, 0.9), Vector2(stroke_len, 0)])
		S.add(b, rasp, 1.0 if push else 0.75, S.samples(s * stroke_len))
	var dust := S.hp(S.pink(dur, r), 4000.0)
	S.env(dust, [Vector2(0, 0), Vector2(0.1, 1.0), Vector2(dur, 0.2)])
	return S.add(b, dust, 0.08)


## Hammer on anvil: a bright, long-ringing strike and the hammer's bounce.
static func _anvil(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var dur := 1.8
	var hit := K.ki("impactMetal_heavy", v, K.jit(r, 0.05), 0.3)
	var f := r.randf_range(980.0, 1250.0)
	var ratios := [1.0, 1.58, 2.31, 2.97, 3.71, 4.66]
	var freqs := []
	for k in ratios:
		freqs.append(f * float(k) * K.jit(r, 0.004))
	var taus := [0.9, 0.7, 0.5, 0.36, 0.25, 0.18]
	var amps := [1.0, 0.7, 0.55, 0.35, 0.25, 0.15]
	# Strike and bounce excite the same modes: one resonator pass.
	var bounce_t := r.randf_range(0.11, 0.17)
	var ex := S.make(bounce_t + 0.01)
	S.add(ex, S.decay(S.noise(0.004, r), 0.0001, 0.0006), 1.0)
	S.add(ex, S.decay(S.noise(0.004, r), 0.0001, 0.0005), 0.35, S.samples(bounce_t))
	var ring := S.normalize(S.modal(ex, freqs, taus, amps, dur))
	var b := K.mix([[hit, 0.7, 0.0], [ring, 0.7, 0.0],
			[K.ki("impactMetal_light", v + 1, K.jit(r, 0.05), 0.2), 0.25, bounce_t]])
	return S.reverb(b, 0.6, 0.5, 0.12)


static func _smelt_done(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var clink := K.ki("impactMetal_light", v + 2, K.jit(r, 0.05), 0.4)
	var f := r.randf_range(1400.0, 1700.0)
	var ring := S.bell(1.0, f, [1.0, 2.76, 5.4], [0.5, 0.25, 0.1], [0.4, 0.2, 0.1])
	var puff := K.whoosh(r, 0.6, [Vector2(0, 300), Vector2(0.2, 900), Vector2(0.6, 300)], 0.8,
			[Vector2(0, 0), Vector2(0.1, 1.0), Vector2(0.6, 0)])
	var sizzle := S.grains(0.5, r.randi_range(20, 40), r, 3000.0, 9000.0, 0.0003, 0.001, 1.5)
	return K.mix([[puff, 0.35, 0.0], [clink, 0.9, 0.12], [ring, 0.25, 0.12], [sizzle, 0.15, 0.12]])


# --- Interactables -------------------------------------------------------------------------

static func _door(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var open := K.smp(KR + "doorOpen_%d.ogg" % (1 + v % 2), K.jit(r, 0.04), 0.0, 60.0)
	var creak := K.smp(KR + "creak%d.ogg" % (1 + v % 3), K.jit(r, 0.05) * 0.8, 0.0, 120.0)
	return K.mix([[open, 1.0, 0.0], [creak, 0.3, 0.1]])


static func _chest(r: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var latch := K.smp(KR + "metalLatch.ogg", K.jit(r, 0.05), 0.0, 150.0)
	var creak := K.smp(KR + "creak%d.ogg" % (1 + (v + 1) % 3), K.jit(r, 0.05) * 0.75, 0.0, 120.0)
	var lid := K.ki("impactWood_light", v, K.jit(r, 0.05) * 0.8, 0.3, 60.0)
	return K.mix([[latch, 0.6, 0.0], [creak, 0.7, 0.12], [lid, 0.7, 0.6]])


# --- Magic --------------------------------------------------------------------------

static func _portal(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 2.8
	var b := S.make(dur)
	for f: float in [110.0, 164.8, 220.5, 329.6]:
		var o := S.osc(dur, S.Wave.SAW, [Vector2(0, f * 0.98), Vector2(dur, f * 1.02)])
		S.add(b, o, 0.25)
	S.filter(b, S.Filter.LOWPASS, [Vector2(0, 200), Vector2(1.8, 3200), Vector2(dur, 900)], 2.5)
	var air := S.filter(S.pink(dur, r), S.Filter.BANDPASS, [Vector2(0, 600), Vector2(dur, 5200)], 3.0)
	S.add(b, air, 0.8)
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
