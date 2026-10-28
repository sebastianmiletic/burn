class_name MapIcons
extends RefCounted
## Crisp vector map symbols for the minimap and world map, drawn with
## CanvasItem primitives (anti-aliased outlines over filled shapes) so they
## stay sharp at every size and UI scale.
##
##   MapIcons.draw_place(canvas, place, at, radius, faded)  one marker
##   MapIcons.place_of(world, loc)                         -> place Dictionary
##   MapIcons.boss_icon("leviathan")                       -> &"serpent"
##
## Bosses sit on a dark badge with a crimson ring; once defeated the badge
## turns grey and is crossed out. Places draw as outlined silhouettes.
##
## Extending (other systems add places, bosses and biomes; call these once,
## e.g. where your planner or boss script loads; they are cheap and idempotent):
##   MapIcons.register_kind("oasis", &"oasis", "Oasis", Color(...))
##       How locations of that kind show. A location picks its kind, first match wins:
##       1. loc.set_meta(&"map_kind", "oasis") on the Location (any registered key);
##       2. a key registered with `id_prefix = true` that its id starts with ("wreck_");
##       3. its Location.Kind name in lower case ("village", "mine", or a new enum value).
##       Unknown kinds fall back to the generic &"poi" lozenge.
##       Built-in keys: village shrine tower ruin mine cave dungeon crypt wreck sunken_ruin
##       well fishing_shack oasis volcano labyrinth portal camp lighthouse lair island
##       castle hall gate throne tartarus hell_spawn.
##   MapIcons.register_glyph(&"my_icon", func(ci, at, r, fill, outline): ...)
##       A new drawn symbol (about radius r around `at`); built-ins are in draw_glyph.
##   MapIcons.register_boss("kraken", &"kraken", "The Abyssal Kraken")
##   MapIcons.register_biome(WorldGen.Biome.TUNDRA, &"b_snow", tint)
## Player markers use the glyphs in MARKER_ICONS (MapMarkers, draw_marker).

enum State { NORMAL, DEFEATED, FADED }

const BOSS_ICONS := {
	"warden": &"skull", "leviathan": &"serpent", "sea_serpent": &"serpent", "dragon": &"dragon",
	"ashvane": &"dragon", "broodmother": &"spider", "mountain_king": &"crown", "hades": &"flame",
	"cerberus": &"hound", "bog_hag": &"witch", "prism_sentinel": &"crystal", "ryft_sentinel": &"crystal",
	"void_sovereign": &"void_eye", "kraken": &"kraken", "charybdis": &"whirlpool",
}
const BOSS_NAMES := {
	"warden": "The Warden", "leviathan": "The Leviathan", "dragon": "Ashvane", "broodmother": "Vexhira the Broodmother",
	"mountain_king": "The Mountain King", "hades": "Hades", "cerberus": "Cerberus", "bog_hag": "Old Mother Mire",
	"prism_sentinel": "The Prism Sentinel", "ryft_sentinel": "The Prism Sentinel", "void_sovereign": "The Void Sovereign",
	"kraken": "The Abyssal Kraken", "charybdis": "Charybdis",
}
## Symbols a player can pick for their own map markers.
const MARKER_ICONS: Array[StringName] = [&"pin", &"flag", &"home", &"tent", &"chest", &"mine", &"skull", &"star",
	&"eye", &"anchor", &"b_pine", &"portal"]
## Marker colours (MapMarkers); index 0 is the default.
const MARKER_COLOURS: Array[Color] = [Color(1.0, 0.8, 0.36), Color(0.95, 0.36, 0.26), Color(0.5, 0.86, 0.45),
	Color(0.45, 0.75, 1.0), Color(0.76, 0.55, 1.0), Color(1.0, 0.55, 0.78), Color(0.92, 0.9, 0.85), Color(0.35, 0.92, 0.85)]

const BONE := Color(0.95, 0.9, 0.8)
const INK := Color(0.05, 0.04, 0.035)
const BOSS_RING := Color(0.86, 0.22, 0.16)
const DEFEATED := Color(0.5, 0.48, 0.46)
const QUEST := Color(1.0, 0.8, 0.32)
const VILLAGE := Color(0.96, 0.86, 0.66)
const SHRINE := Color(1.0, 0.66, 0.26)
const STONE := Color(0.8, 0.74, 0.64)
const PORTAL := Color(0.74, 0.55, 1.0)
const SEA := Color(0.62, 0.84, 0.92)
const EARTH := Color(0.8, 0.64, 0.48)
const FIRE := Color(1.0, 0.52, 0.3)
const GREEN := Color(0.64, 0.86, 0.5)

static var _shapes := {}
static var _kinds := {}            # key -> {"icon", "label", "color", "prefix"}
static var _prefixes: Array = []   # id-prefix keys, longest first
static var _glyphs := {}           # icon -> Callable(ci, at, r, fill, outline)
static var _bosses := {}           # kind -> [icon, name]
static var _biomes := {}           # biome id -> [icon, tint]
static var _registry_ready := false


# --- Registry ------------------------------------------------------------------------

## How locations of `key` show on the map (see the header for how a location
## picks its key). Re-registering a key replaces it.
static func register_kind(key: String, icon: StringName, label: String, color := STONE, id_prefix := false) -> void:
	_ensure()
	_add_kind(key, icon, label, color, id_prefix)


## A custom symbol: `drawer.call(ci, at, r, fill, outline)` draws it about `r` in radius.
static func register_glyph(icon: StringName, drawer: Callable) -> void:
	_glyphs[icon] = drawer


static func register_boss(kind: String, icon: StringName, display_name := "") -> void:
	_ensure()
	_bosses[kind] = [icon, display_name if display_name != "" else kind.capitalize()]


## A biome's map symbol and legend tint.
static func register_biome(biome: int, icon: StringName, tint: Color) -> void:
	_ensure()
	_biomes[biome] = [icon, tint]


static func _add_kind(key: String, icon: StringName, label: String, color: Color, id_prefix: bool) -> void:
	_kinds[key] = {"icon": icon, "label": label, "color": color, "prefix": id_prefix}
	_prefixes.erase(key)
	if id_prefix:
		_prefixes.append(key)
		_prefixes.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())


static func _ensure() -> void:
	if _registry_ready:
		return
	_registry_ready = true
	# Location.Kind names.
	for spec: Array in [["village", &"village", "Village", VILLAGE], ["castle", &"keep", "Castle", STONE],
			["hall", &"hall", "Hall", STONE], ["gate", &"gate", "Gate", Color(1.0, 0.5, 0.3)],
			["crypt", &"dungeon", "Crypt", STONE], ["shrine", &"shrine", "Shrine", SHRINE],
			["tower", &"tower", "Watchtower", STONE], ["ruin", &"ruin", "Ruins", STONE],
			["hell_spawn", &"portal", "Portal", PORTAL], ["tartarus", &"keep", "Fortress", Color(0.92, 0.58, 0.48)],
			["throne", &"throne", "Palace", Color(1.0, 0.68, 0.42)], ["mine", &"mine", "Mine", EARTH],
			# Place types: set loc meta "map_kind" to one of these.
			["cave", &"cave", "Cave mouth", EARTH], ["dungeon", &"dungeon", "Dungeon", STONE],
			["wreck", &"wreck", "Wreck", SEA], ["sunken_ruin", &"sunken", "Sunken ruins", SEA],
			["well", &"well", "Well", SEA], ["fishing_shack", &"fishing", "Fishing shack", SEA],
			["oasis", &"oasis", "Oasis", GREEN], ["volcano", &"volcano", "Volcano", FIRE],
			["labyrinth", &"labyrinth", "Labyrinth", STONE], ["portal", &"portal", "Portal", PORTAL],
			["camp", &"tent", "Camp", EARTH], ["lighthouse", &"lighthouse", "Lighthouse", QUEST],
			["lair", &"cave", "Lair", Color(0.95, 0.45, 0.35)], ["island", &"palm", "Isle", GREEN]]:
		_add_kind(spec[0], spec[1], spec[2], spec[3], false)
	# Known location ids.
	for spec: Array in [["wreck_", &"wreck", "Wreck", SEA], ["sunken_", &"sunken", "Sunken ruins", SEA],
			["drowned_", &"sunken", "Sunken ruins", SEA], ["drowned_spire", &"lighthouse", "Sea tower", SEA],
			["tower_", &"tower", "Watchtower", STONE], ["ruin_", &"ruin", "Ruins", STONE],
			["silent_crypt", &"dungeon", "Crypt", STONE], ["crypt_", &"dungeon", "Crypt", STONE],
			["cinder_crater", &"volcano", "Crater", FIRE], ["gates_of_hades", &"portal", "Portal to Hades", PORTAL]]:
		_add_kind(spec[0], spec[1], spec[2], spec[3], true)
	for kind: String in BOSS_ICONS:
		_bosses[kind] = [BOSS_ICONS[kind], BOSS_NAMES.get(kind, kind.capitalize())]
	var b := WorldGen.Biome
	_biomes = {b.OCEAN: [&"b_waves", Color(0.3, 0.5, 0.58)], b.PLAINS: [&"b_grass", Color(0.62, 0.6, 0.36)],
		b.FOREST: [&"b_tree", Color(0.36, 0.5, 0.26)], b.PEAKS: [&"b_peak", Color(0.68, 0.68, 0.7)],
		b.MARSH: [&"b_reeds", Color(0.38, 0.45, 0.3)], b.WASTES: [&"b_dunes", Color(0.6, 0.45, 0.34)],
		b.ASPHODEL: [&"b_flower", Color(0.62, 0.52, 0.5)], b.LAKE_OF_FIRE: [&"flame", Color(0.9, 0.38, 0.14)],
		b.TARTARUS: [&"b_spikes", Color(0.46, 0.36, 0.36)], b.RYFT: [&"crystal", Color(0.6, 0.52, 0.85)],
		b.REDWOOD: [&"b_pine", Color(0.4, 0.36, 0.22)], b.CANYON: [&"b_mesa", Color(0.78, 0.45, 0.3)],
		b.ALPINE: [&"b_peak", Color(0.55, 0.66, 0.5)], b.TUNDRA: [&"b_snow", Color(0.8, 0.84, 0.86)],
		b.VOLCANIC: [&"volcano", Color(0.42, 0.3, 0.28)], b.FJORD: [&"b_fjord", Color(0.45, 0.6, 0.58)]}


## Every symbol name the built-in drawer knows plus registered ones (galleries).
static func glyphs() -> Array[StringName]:
	var out: Array[StringName] = [&"skull", &"serpent", &"kraken", &"whirlpool", &"dragon", &"spider", &"crown", &"flame",
		&"hound", &"witch", &"crystal", &"void_eye", &"village", &"shrine", &"cave", &"mine", &"dungeon", &"portal",
		&"tower", &"keep", &"hall", &"throne", &"gate", &"ruin", &"wreck", &"sunken", &"anchor", &"well", &"fishing",
		&"oasis", &"palm", &"volcano", &"labyrinth", &"tent", &"lighthouse", &"pin", &"flag", &"home", &"chest", &"eye",
		&"star", &"quest", &"b_waves", &"b_grass", &"b_tree", &"b_pine", &"b_peak", &"b_reeds", &"b_dunes", &"b_flower",
		&"b_spikes", &"b_mesa", &"b_snow", &"b_fjord"]
	for g: StringName in _glyphs:
		if not g in out:
			out.append(g)
	return out


## The symbol for a boss kind (unknown future bosses get the closest match).
static func boss_icon(kind: String) -> StringName:
	_ensure()
	if _bosses.has(kind):
		return _bosses[kind][0]
	for key in ["crystal", "prism", "void", "ryft"]:
		if key in kind:
			return &"crystal"
	if "kraken" in kind or "squid" in kind or "octo" in kind:
		return &"kraken"
	if "whirl" in kind or "maelstrom" in kind:
		return &"whirlpool"
	for key in ["serpent", "fish", "sea", "eel"]:
		if key in kind:
			return &"serpent"
	if "dragon" in kind or "wyrm" in kind or "drake" in kind:
		return &"dragon"
	if "spider" in kind or "brood" in kind:
		return &"spider"
	if "hag" in kind or "witch" in kind:
		return &"witch"
	if "king" in kind or "queen" in kind:
		return &"crown"
	if "fire" in kind or "flame" in kind or "volcan" in kind:
		return &"flame"
	if "hound" in kind or "wolf" in kind or "dog" in kind:
		return &"hound"
	return &"skull"


static func boss_name(kind: String) -> String:
	_ensure()
	return String(_bosses[kind][1]) if _bosses.has(kind) else kind.capitalize()


## [icon, tint] for a biome id (unknown biomes: a plain dot in a muted colour).
static func biome_symbol(biome: int) -> Array:
	_ensure()
	if _biomes.has(biome):
		return _biomes[biome]
	return [&"b_dot", Color.from_hsv(fposmod(float(biome) * 0.618034, 1.0), 0.3, 0.6)]


## The boss that lives at a location ("" if none).
static func boss_of(loc: Object) -> String:
	if loc == null:
		return ""
	var spawns: Variant = loc.get("spawns")
	if spawns is Array:
		for s: Dictionary in spawns:
			if s.get("type", "") == "boss":
				return String(s.get("kind", ""))
	return ""


## The registered kind key a location shows as ("" = none: the generic symbol).
static func kind_of(loc: Object) -> String:
	_ensure()
	if loc == null:
		return ""
	if loc.has_meta(&"map_kind"):
		var tag := String(loc.get_meta(&"map_kind"))
		if _kinds.has(tag):
			return tag
	var id := String(loc.get("id"))
	for key: String in _prefixes:
		if id.begins_with(key):
			return key
	var kind := int(loc.get("kind"))
	if kind == Location.Kind.CRYPT and ("mine" in id or "adit" in id):
		return "mine"
	if kind == Location.Kind.CRYPT and not ("crypt" in id):
		return "cave"
	var names := Location.Kind.keys()
	if kind >= 0 and kind < names.size():
		var key := String(names[kind]).to_lower()
		if _kinds.has(key):
			return key
	return ""


## Describes how a location shows on the map:
## {"icon", "boss", "name", "sub", "state", "major", "color", "kind"}.
static func place_of(world: Object, loc: Object) -> Dictionary:
	var boss := boss_of(loc)
	var key := kind_of(loc)
	var out := {"icon": &"poi", "boss": boss, "name": str(loc.get("name")), "sub": "", "state": State.NORMAL,
		"major": loc.get("major") == true, "color": STONE, "kind": key}
	if boss != "":
		out["icon"] = boss_icon(boss)
		out["major"] = true
		var defeated: Variant = world.get("bosses_defeated") if world != null else null
		var dead := defeated is Dictionary and (defeated as Dictionary).has(boss)
		out["state"] = State.DEFEATED if dead else State.NORMAL
		out["sub"] = boss_name(boss) + (" · defeated" if dead else "")
		return out
	if key != "":
		var spec: Dictionary = _kinds[key]
		out["icon"] = spec["icon"]
		out["color"] = spec["color"]
		out["sub"] = spec["label"]
	if key == "shrine":
		var lit: Variant = world.get("lit_shrines") if world != null else null
		var on := lit is Dictionary and (lit as Dictionary).has(loc.get("id"))
		out["color"] = SHRINE if on else STONE.darkened(0.15)
		out["sub"] = "Shrine · kindled" if on else "Shrine"
	var spawns: Variant = loc.get("spawns")
	if spawns is Array and out["icon"] in [&"ruin", &"poi"]:
		for s: Dictionary in spawns:
			if s.get("type", "") == "portal":
				out["icon"] = &"portal"
				out["color"] = PORTAL
				out["sub"] = "Portal"
	return out


# --- Drawing -------------------------------------------------------------------------

## One map marker. Bosses draw as a ringed badge; everything else as an
## outlined silhouette in `place.color`.
static func draw_place(ci: CanvasItem, place: Dictionary, at: Vector2, r: float, faded := false) -> void:
	var icon: StringName = place.get("icon", &"poi")
	var alpha := 0.55 if faded else 1.0
	if String(place.get("boss", "")) != "":
		draw_badge(ci, icon, at, r, place.get("state", State.NORMAL) == State.DEFEATED, alpha)
	else:
		var c: Color = place.get("color", STONE)
		c.a *= alpha
		draw_glyph(ci, icon, at, r * 0.92, c, Color(0, 0, 0, 0.85 * alpha))


static func draw_badge(ci: CanvasItem, icon: StringName, at: Vector2, r: float, defeated: bool, alpha := 1.0) -> void:
	var ring := DEFEATED if defeated else BOSS_RING
	ring.a *= alpha
	ci.draw_circle(at, r + 1.6, Color(0, 0, 0, 0.55 * alpha), true, -1.0, true)
	ci.draw_circle(at, r, Color(0.07, 0.05, 0.045, 0.94 * alpha), true, -1.0, true)
	ci.draw_arc(at, r - 0.6, 0.0, TAU, 40, ring, maxf(1.4, r * 0.14), true)
	var g := DEFEATED.darkened(0.1) if defeated else BONE
	g.a *= alpha
	draw_glyph(ci, icon, at, r * 0.62, g, Color(0, 0, 0, 0))
	if defeated:
		var k := r * 0.62
		var x := Color(0.7, 0.2, 0.16, 0.95 * alpha)
		ci.draw_line(at + Vector2(-k, -k), at + Vector2(k, k), x, maxf(1.5, r * 0.15), true)
		ci.draw_line(at + Vector2(k, -k), at + Vector2(-k, k), x, maxf(1.5, r * 0.15), true)


## Colour of a quest / activity marker (QuestMarkers.points entry).
static func point_colour(pt: Dictionary) -> Color:
	match String(pt.get("kind", "")):
		"main":
			return QUEST
		"turn_in":
			return Color(0.62, 1.0, 0.5)
		"side":
			return Color(0.95, 0.72, 0.42)
	match String(pt.get("icon", "")):
		"raid":
			return Color(0.95, 0.3, 0.25)
		"star":
			return Color(0.65, 0.78, 1.0)
		"treasure":
			return Color(1.0, 0.85, 0.4)
		"bounty":
			return Color(1.0, 0.55, 0.3)
		"ring":
			return Color(1.0, 0.65, 0.35)
		"hart", "charm":
			return Color(1.0, 0.88, 0.45)
	return UiTheme.FROST


## A quest objective, hand-in or activity point. Quests draw as the gold
## lozenge ("?" lozenge in green to hand in); activities as a dark badge with
## their own symbol (X marks the spot, dagger, falling star, crossed swords,
## ring, antlers). Untracked quest markers draw smaller and dimmer.
static func draw_point(ci: CanvasItem, pt: Dictionary, at: Vector2, r: float, t: float, faded := false) -> void:
	var col := point_colour(pt)
	var kind := String(pt.get("kind", ""))
	var tracked: bool = pt.get("tracked", true)
	if faded:
		col.a *= 0.8
	if kind in ["main", "side", "turn_in"]:
		if not tracked:
			col = col.lerp(Color(0.6, 0.58, 0.55), 0.4)
			col.a *= 0.75
			draw_glyph(ci, &"turn_in" if kind == "turn_in" else &"quest", at, r * 0.8, col, Color(0, 0, 0, 0.8 * col.a))
		elif kind == "turn_in":
			_pulse(ci, at, r, t, col)
			draw_glyph(ci, &"turn_in", at, r, col, Color(0, 0, 0, 0.9))
		else:
			draw_quest(ci, at, r, t, col)
		return
	var icon := StringName(String(pt.get("icon", "")))
	if float(pt.get("priority", 1.0)) >= 4.0:
		_pulse(ci, at, r, t, col)
	ci.draw_circle(at, r + 1.4, Color(0, 0, 0, 0.6 * col.a), true, -1.0, true)
	ci.draw_circle(at, r, Color(0.07, 0.055, 0.045, 0.94 * col.a), true, -1.0, true)
	ci.draw_arc(at, r - 0.5, 0.0, TAU, 32, col, maxf(1.2, r * 0.13), true)
	var glyph := icon if icon in [&"treasure", &"bounty", &"star", &"raid", &"ring", &"hart"] else &"charm"
	draw_glyph(ci, glyph, at, r * 0.62, col, Color(0, 0, 0, 0))


## The search area of a marker with a radius (treasure, last-seen quarry,
## the Proving Ring): a soft fill and a dashed rim, `px` pixels in radius.
static func draw_area(ci: CanvasItem, pt: Dictionary, at: Vector2, px: float) -> void:
	if px < 3.0:
		return
	var col := point_colour(pt)
	ci.draw_circle(at, px, Color(col.r, col.g, col.b, 0.1), true, -1.0, true)
	var dashes := clampi(int(px * 0.5), 12, 64)
	for i in dashes:
		var a0 := TAU * i / dashes
		ci.draw_arc(at, px, a0, a0 + TAU / dashes * 0.55, 4, Color(col.r, col.g, col.b, 0.75), 1.4, true)


static func _pulse(ci: CanvasItem, at: Vector2, r: float, t: float, col: Color) -> void:
	var pulse := fposmod(t * 0.8, 1.0)
	var ring := col
	ring.a = (1.0 - pulse) * 0.7 * col.a
	ci.draw_arc(at, r * (1.0 + pulse * 0.9), 0.0, TAU, 32, ring, 1.5, true)


## The objective marker: a gold lozenge with an exclamation mark, pulsing.
static func draw_quest(ci: CanvasItem, at: Vector2, r: float, t: float, color := QUEST) -> void:
	var pulse := fposmod(t * 0.8, 1.0)
	var ring := color
	ring.a = (1.0 - pulse) * 0.7
	ci.draw_arc(at, r * (1.0 + pulse * 0.9), 0.0, TAU, 32, ring, 1.5, true)
	draw_glyph(ci, &"quest", at, r, color, Color(0, 0, 0, 0.9))


## A silhouette from the symbol set, centred on `at`, about `r` in radius.
static func draw_glyph(ci: CanvasItem, icon: StringName, at: Vector2, r: float, fill: Color, outline: Color) -> void:
	var ink := Color(INK.r, INK.g, INK.b, fill.a)
	var w := maxf(1.0, r * 0.14)
	if _glyphs.has(icon):
		(_glyphs[icon] as Callable).call(ci, at, r, fill, outline)
		return
	match icon:
		&"skull":
			_circle(ci, at + Vector2(0, -0.2) * r, 0.7 * r, fill, outline)
			_poly(ci, _pts(&"skull_jaw"), at, r, fill, outline)
			ci.draw_circle(at + Vector2(-0.28, -0.14) * r, 0.2 * r, ink, true, -1.0, true)
			ci.draw_circle(at + Vector2(0.28, -0.14) * r, 0.2 * r, ink, true, -1.0, true)
			_poly(ci, _pts(&"skull_nose"), at, r, ink, Color(0, 0, 0, 0))
			for x in [-0.14, 0.14]:
				ci.draw_line(at + Vector2(x, 0.48) * r, at + Vector2(x, 0.76) * r, ink, maxf(1.0, r * 0.09), true)
		&"serpent":
			# Coils rising out of the sea, the head reared on the left.
			var body := PackedVector2Array()
			for i in 7:
				var t := i / 6.0
				body.append(at + Vector2(-0.52 + t * 0.12, 0.34 - t * 0.74) * r)
			var coil := PackedVector2Array()
			for i in 21:
				var t := i / 20.0
				coil.append(at + Vector2(-0.4 + t * 1.3, 0.36 - absf(sin(t * TAU)) * 0.52 * (1.0 - t * 0.3)) * r)
			_stroke(ci, body, fill, outline, w * 1.8)
			_stroke(ci, coil, fill, outline, w * 1.8)
			_poly(ci, _pts(&"serpent_head"), at, r, fill, outline)
			ci.draw_circle(at + Vector2(-0.56, -0.5) * r, 0.07 * r, ink, true, -1.0, true)
			_stroke(ci, _wave(at, r, 0.62, 0.95), fill, outline, w * 0.9)
		&"kraken":
			# A mantle over curling arms.
			for k in 5:
				var x := -0.6 + k * 0.3
				var arm := PackedVector2Array()
				for j in 6:
					var t := float(j) / 5.0
					arm.append(at + Vector2(x * (1.0 + t * 0.5) + sin(t * 4.0 + k) * 0.12, 0.05 + t * 0.85) * r)
				if outline.a > 0.0:
					ci.draw_polyline(arm, outline, w * 1.1 + 2.0, true)
				ci.draw_polyline(arm, fill, w * 1.1, true)
			_ellipse(ci, at + Vector2(0, -0.32) * r, Vector2(0.5, 0.62) * r, fill, outline)
			for x in [-0.2, 0.2]:
				ci.draw_circle(at + Vector2(x, -0.06) * r, 0.09 * r, ink, true, -1.0, true)
		&"whirlpool":
			_circle(ci, at, 0.9 * r, fill, outline)
			for k in 3:
				var rr := (0.72 - k * 0.22) * r
				ci.draw_arc(at, rr, k * 1.4, k * 1.4 + 4.6, 16, ink, maxf(1.0, r * 0.09), true)
			ci.draw_circle(at, 0.12 * r, ink, true, -1.0, true)
		&"dragon":
			_poly(ci, _pts(&"dragon"), at, r, fill, outline)
			ci.draw_circle(at + Vector2(-0.2, -0.08) * r, 0.09 * r, ink, true, -1.0, true)
		&"spider":
			for side in [-1.0, 1.0]:
				for k in 4:
					var y0 := -0.22 + k * 0.14
					var knee := Vector2(side * (0.58 + k * 0.04), y0 - 0.42 + k * 0.2)
					var foot := Vector2(side * (0.98 - k * 0.04), y0 + 0.12 + k * 0.22)
					var leg := PackedVector2Array([at + Vector2(side * 0.14, y0) * r, at + knee * r, at + foot * r])
					if outline.a > 0.0:
						ci.draw_polyline(leg, outline, w * 0.8 + 2.0, true)
					ci.draw_polyline(leg, fill, w * 0.8, true)
			_circle(ci, at + Vector2(0, 0.3) * r, 0.32 * r, fill, outline)
			_circle(ci, at + Vector2(0, -0.16) * r, 0.2 * r, fill, outline)
			ci.draw_line(at + Vector2(0, 0.14) * r, at + Vector2(0, 0.48) * r, ink, maxf(1.0, r * 0.08), true)
		&"crown":
			_poly(ci, _pts(&"crown"), at, r, fill, outline)
			ci.draw_line(at + Vector2(-0.8, 0.32) * r, at + Vector2(0.8, 0.32) * r, ink, maxf(1.0, r * 0.1), true)
			for p: Vector2 in [Vector2(-0.82, -0.5), Vector2(0, -0.8), Vector2(0.82, -0.5)]:
				_circle(ci, at + p * r, 0.12 * r, fill, outline)
		&"flame":
			_poly(ci, _pts(&"flame"), at, r, fill, outline)
			_poly(ci, _pts(&"flame_core"), at, r, Color(ink.r, ink.g, ink.b, fill.a * 0.75), Color(0, 0, 0, 0))
		&"hound":
			_ellipse(ci, at + Vector2(0, 0.34) * r, Vector2(0.48, 0.4) * r, fill, outline)
			for p: Vector2 in [Vector2(-0.64, -0.12), Vector2(-0.24, -0.52), Vector2(0.24, -0.52), Vector2(0.64, -0.12)]:
				_ellipse(ci, at + p * r, Vector2(0.18, 0.22) * r, fill, outline)
		&"witch":
			_poly(ci, _pts(&"hat"), at, r, fill, outline)
			_poly(ci, _pts(&"brim"), at, r, fill, outline)
			ci.draw_line(at + Vector2(-0.38, 0.3) * r, at + Vector2(0.38, 0.3) * r, ink, maxf(1.0, r * 0.13), true)
		&"crystal":
			_poly(ci, _pts(&"crystal"), at, r, fill, outline)
			var facet := PackedVector2Array([at + Vector2(-0.5, -0.3) * r, at + Vector2(0, 0.0) * r, at + Vector2(0.5, -0.3) * r])
			ci.draw_polyline(facet, ink, maxf(1.0, r * 0.07), true)
			ci.draw_line(at + Vector2(0, 0.0) * r, at + Vector2(0, 0.95) * r, ink, maxf(1.0, r * 0.07), true)
		&"village":
			_poly(ci, _pts(&"house"), at + Vector2(0.4, -0.26) * r, r * 0.6, fill.darkened(0.18), outline)
			_poly(ci, _pts(&"spire"), at + Vector2(-0.52, -0.2) * r, r * 0.7, fill.darkened(0.1), outline)
			_poly(ci, _pts(&"house"), at + Vector2(-0.06, 0.16) * r, r * 0.8, fill, outline)
			_poly(ci, _pts(&"door"), at + Vector2(-0.06, 0.16) * r, r * 0.8, ink, Color(0, 0, 0, 0))
		&"shrine":
			_poly(ci, _pts(&"plinth"), at, r, STONE if fill.a > 0 else fill, outline)
			var fl := fill
			_poly(ci, _pts(&"small_flame"), at, r, fl, outline)
		&"cave":
			_poly(ci, _pts(&"hill"), at, r, fill, outline)
			_poly(ci, _pts(&"arch"), at, r, ink, Color(0, 0, 0, 0))
		&"mine":
			var head := PackedVector2Array()
			for i in 11:
				var f := i / 10.0
				head.append(at + Vector2(lerpf(-0.85, 0.85, f), -0.3 - sin(f * PI) * 0.42) * r)
			var handle := PackedVector2Array([at + Vector2(0, -0.66) * r, at + Vector2(0.1, 0.92) * r])
			if outline.a > 0.0:
				ci.draw_polyline(head, outline, w * 1.6 + 2.0, true)
				ci.draw_polyline(handle, outline, w * 1.2 + 2.0, true)
			ci.draw_polyline(handle, fill.darkened(0.25), w * 1.2, true)
			ci.draw_polyline(head, fill, w * 1.6, true)
		&"portal":
			if outline.a > 0.0:
				ci.draw_arc(at, 0.72 * r, 0.0, TAU, 32, outline, w * 1.7 + 2.0, true)
			ci.draw_arc(at, 0.72 * r, 0.0, TAU, 32, fill, w * 1.7, true)
			ci.draw_arc(at, 0.36 * r, 0.6, 4.4, 20, fill, w, true)
			ci.draw_circle(at, 0.12 * r, fill, true, -1.0, true)
		&"tower":
			_poly(ci, _pts(&"tower"), at, r, fill, outline)
		&"keep":
			_poly(ci, _pts(&"keep"), at, r, fill, outline)
			_poly(ci, _pts(&"keep_door"), at, r, ink, Color(0, 0, 0, 0))
		&"gate":
			_poly(ci, _pts(&"gate"), at, r, fill, outline)
			_poly(ci, _pts(&"arch"), at, r, ink, Color(0, 0, 0, 0))
		&"ruin":
			_poly(ci, _pts(&"column_a"), at, r, fill, outline)
			_poly(ci, _pts(&"column_b"), at, r, fill, outline)
			_poly(ci, _pts(&"ruin_base"), at, r, fill, outline)
		&"anchor":
			var arms := PackedVector2Array()
			for i in 13:
				var a := lerpf(PI * 0.12, PI * 0.88, i / 12.0)
				arms.append(at + Vector2(cos(a) * 0.68, 0.12 + sin(a) * 0.62) * r)
			var lines: Array[PackedVector2Array] = [arms, PackedVector2Array([at + Vector2(0, -0.55) * r, at + Vector2(0, 0.74) * r]),
				PackedVector2Array([at + Vector2(-0.36, -0.32) * r, at + Vector2(0.36, -0.32) * r])]
			for l in lines:
				if outline.a > 0.0:
					ci.draw_polyline(l, outline, w * 1.3 + 2.0, true)
			for l in lines:
				ci.draw_polyline(l, fill, w * 1.3, true)
			if outline.a > 0.0:
				ci.draw_arc(at + Vector2(0, -0.72) * r, 0.17 * r, 0.0, TAU, 16, outline, w + 2.0, true)
			ci.draw_arc(at + Vector2(0, -0.72) * r, 0.17 * r, 0.0, TAU, 16, fill, w, true)
		&"turn_in":
			_poly(ci, _pts(&"lozenge"), at, r, fill, outline)
			ci.draw_arc(at + Vector2(0, -0.22) * r, 0.22 * r, PI * 1.05, PI * 2.35, 10, ink, maxf(1.2, r * 0.12), true)
			ci.draw_line(at + Vector2(0.06, 0.0) * r, at + Vector2(0, 0.18) * r, ink, maxf(1.2, r * 0.12), true)
			ci.draw_circle(at + Vector2(0, 0.42) * r, 0.1 * r, ink, true, -1.0, true)
		&"treasure":
			for d: Vector2 in [Vector2(1, 1), Vector2(1, -1)]:
				var a: Vector2 = at - d * 0.72 * r
				var b: Vector2 = at + d * 0.72 * r
				if outline.a > 0.0:
					ci.draw_line(a, b, outline, w * 2.0 + 2.0, true)
				ci.draw_line(a, b, fill, w * 2.0, true)
		&"bounty":
			_poly(ci, _pts(&"blade"), at, r, fill, outline)
			ci.draw_line(at + Vector2(-0.48, 0.28) * r, at + Vector2(0.48, 0.28) * r, fill, w * 1.4, true)
			ci.draw_line(at + Vector2(0, 0.32) * r, at + Vector2(0, 0.86) * r, fill.darkened(0.2), w * 1.5, true)
		&"star":
			_poly(ci, _pts(&"star4"), at, r, fill, outline)
		&"raid":
			for sgn: float in [-1.0, 1.0]:
				var a := at + Vector2(-0.72 * sgn, -0.72) * r
				var b := at + Vector2(0.55 * sgn, 0.55) * r
				ci.draw_line(a, b, fill, w * 1.4, true)
				var g := at + Vector2(0.38 * sgn, 0.38) * r
				var perp := Vector2(1, -1 * sgn).normalized() * 0.26 * r
				ci.draw_line(g - perp, g + perp, fill, w * 1.4, true)
		&"ring":
			ci.draw_arc(at, 0.78 * r, 0.0, TAU, 28, fill, w * 1.2, true)
			ci.draw_arc(at, 0.42 * r, 0.0, TAU, 20, fill, w * 1.2, true)
			ci.draw_circle(at, 0.12 * r, fill, true, -1.0, true)
		&"hart":
			for sgn: float in [-1.0, 1.0]:
				var beam := PackedVector2Array([at + Vector2(0.12 * sgn, 0.6) * r, at + Vector2(0.4 * sgn, 0.0) * r,
					at + Vector2(0.62 * sgn, -0.75) * r])
				ci.draw_polyline(beam, fill, w * 1.2, true)
				ci.draw_line(at + Vector2(0.4 * sgn, 0.0) * r, at + Vector2(0.85 * sgn, -0.2) * r, fill, w, true)
				ci.draw_line(at + Vector2(0.52 * sgn, -0.4) * r, at + Vector2(0.2 * sgn, -0.72) * r, fill, w, true)
			ci.draw_circle(at + Vector2(0, 0.62) * r, 0.18 * r, fill, true, -1.0, true)
		&"charm":
			_poly(ci, _pts(&"lozenge"), at, r * 0.75, fill, outline)
		&"void_eye":
			for k in 8:
				var a := TAU * k / 8.0
				var l0 := 0.66 if k % 2 == 0 else 0.6
				var l1 := 1.0 if k % 2 == 0 else 0.78
				var d := Vector2(cos(a), sin(a))
				_stroke(ci, PackedVector2Array([at + d * l0 * r, at + d * l1 * r]), fill, outline, w * 0.9)
			_poly(ci, _pts(&"almond"), at, r * 0.8, fill, outline)
			_poly(ci, _pts(&"slit"), at, r * 0.8, ink, Color(0, 0, 0, 0))
		&"dungeon":
			# A trilithon over a stair going down into the dark.
			_poly(ci, _rect(-0.92, -0.86, 0.92, -0.52), at, r, fill, outline)
			_poly(ci, _rect(-0.78, -0.52, -0.44, 0.84), at, r, fill, outline)
			_poly(ci, _rect(0.44, -0.52, 0.78, 0.84), at, r, fill, outline)
			_poly(ci, _rect(-0.44, -0.52, 0.44, 0.84), at, r, ink, Color(0, 0, 0, 0))
			for k in 3:
				var y := 0.2 + k * 0.24
				var half := 0.42 - k * 0.1
				ci.draw_line(at + Vector2(-half, y) * r, at + Vector2(half, y) * r, fill.darkened(0.2), maxf(1.0, r * 0.1), true)
		&"wreck":
			_stroke(ci, PackedVector2Array([at + Vector2(-0.04, 0.2) * r, at + Vector2(-0.3, -0.92) * r]), fill.darkened(0.2), outline, w * 1.1)
			_stroke(ci, PackedVector2Array([at + Vector2(-0.62, -0.62) * r, at + Vector2(0.12, -0.7) * r]), fill.darkened(0.2), outline, w * 0.9)
			_poly(ci, PackedVector2Array([Vector2(-0.24, -0.66), Vector2(0.36, -0.42), Vector2(0.08, -0.36), Vector2(0.2, -0.12), Vector2(-0.1, -0.2)]), at, r, fill, outline)
			_poly(ci, _pts(&"hull"), at, r, fill, outline)
			ci.draw_line(at + Vector2(-0.62, 0.3) * r, at + Vector2(0.62, 0.42) * r, ink, maxf(1.0, r * 0.08), true)
			_stroke(ci, _wave(at, r, 0.8, 0.95), fill, outline, w * 0.9)
		&"sunken":
			_poly(ci, PackedVector2Array([Vector2(-0.3, 0.42), Vector2(-0.3, -0.62), Vector2(-0.05, -0.5), Vector2(0.12, -0.74),
				Vector2(0.3, -0.6), Vector2(0.3, 0.42)]), at, r, fill, outline)
			_poly(ci, _rect(-0.44, -0.9, 0.0, -0.74), at, r, fill, outline)
			for x in [-0.12, 0.1]:
				ci.draw_line(at + Vector2(x, -0.4) * r, at + Vector2(x, 0.3) * r, ink, maxf(1.0, r * 0.06), true)
			_stroke(ci, _wave(at, r, 0.46, 0.95), fill, outline, w)
			_stroke(ci, _wave(at, r, 0.8, 0.8), fill, outline, w)
		&"well":
			_poly(ci, PackedVector2Array([Vector2(-0.86, -0.3), Vector2(0, -0.94), Vector2(0.86, -0.3)]), at, r, fill, outline)
			for x in [-0.56, 0.56]:
				_stroke(ci, PackedVector2Array([at + Vector2(x, -0.3) * r, at + Vector2(x, 0.4) * r]), fill, outline, w)
			ci.draw_line(at + Vector2(0, -0.3) * r, at + Vector2(0, 0.08) * r, fill, maxf(1.0, r * 0.07), true)
			_poly(ci, _rect(-0.76, 0.3, 0.76, 0.86), at, r, fill, outline)
			ci.draw_line(at + Vector2(-0.76, 0.52) * r, at + Vector2(0.76, 0.52) * r, ink, maxf(1.0, r * 0.08), true)
		&"fishing":
			_stroke(ci, PackedVector2Array([at + Vector2(0.18, -0.98) * r, at + Vector2(0.18, -0.3) * r]), fill, outline, w * 0.8)
			var hook := PackedVector2Array()
			for i in 9:
				var a := lerpf(0.0, PI * 1.2, i / 8.0)
				hook.append(at + Vector2(0.02 + cos(a) * 0.16, -0.3 + sin(a) * 0.16) * r)
			_stroke(ci, hook, fill, outline, w * 0.8)
			_poly(ci, _pts(&"fish"), at + Vector2(0.0, 0.42) * r, r * 0.8, fill, outline)
			ci.draw_circle(at + Vector2(-0.38, 0.38) * r, 0.07 * r, ink, true, -1.0, true)
		&"oasis", &"palm":
			if icon == &"oasis":
				_ellipse(ci, at + Vector2(0, 0.7) * r, Vector2(0.86, 0.22) * r, SEA if fill.a > 0.9 else fill, outline)
			else:
				_poly(ci, PackedVector2Array([Vector2(-0.9, 0.86), Vector2(-0.5, 0.6), Vector2(0.5, 0.6), Vector2(0.9, 0.86)]), at, r, fill.darkened(0.15), outline)
			_palm(ci, at, r, fill, outline, w)
		&"volcano":
			for c: Vector3 in [Vector3(0.0, -0.5, 0.15), Vector3(0.16, -0.72, 0.18), Vector3(0.42, -0.86, 0.14)]:
				_circle(ci, at + Vector2(c.x, c.y) * r, c.z * r, Color(0.62, 0.6, 0.58, fill.a), outline)
			_poly(ci, PackedVector2Array([Vector2(-0.96, 0.82), Vector2(-0.34, -0.3), Vector2(-0.16, -0.18), Vector2(0.14, -0.2),
				Vector2(0.34, -0.32), Vector2(0.96, 0.82)]), at, r, fill, outline)
			_poly(ci, PackedVector2Array([Vector2(-0.14, -0.2), Vector2(0.12, -0.2), Vector2(0.04, 0.34), Vector2(-0.06, 0.12),
				Vector2(-0.2, 0.42)]), at, r, Color(1.0, 0.42, 0.12, fill.a), Color(0, 0, 0, 0))
		&"labyrinth":
			_poly(ci, _rect(-0.86, -0.86, 0.86, 0.86), at, r, fill, outline)
			var lw := maxf(1.0, r * 0.11)
			ci.draw_polyline(_scaled(PackedVector2Array([Vector2(-0.12, -0.62), Vector2(-0.62, -0.62), Vector2(-0.62, 0.62),
				Vector2(0.62, 0.62), Vector2(0.62, -0.62), Vector2(0.12, -0.62)]), at, r), ink, lw, true)
			ci.draw_polyline(_scaled(PackedVector2Array([Vector2(0.12, 0.36), Vector2(0.36, 0.36), Vector2(0.36, -0.36),
				Vector2(-0.36, -0.36), Vector2(-0.36, 0.36), Vector2(-0.12, 0.36)]), at, r), ink, lw, true)
			ci.draw_line(at + Vector2(0, -0.36) * r, at + Vector2(0, -0.08) * r, ink, lw, true)
			ci.draw_circle(at + Vector2(0, 0.12) * r, 0.1 * r, ink, true, -1.0, true)
		&"hall":
			_poly(ci, PackedVector2Array([Vector2(-0.96, 0.82), Vector2(-0.4, -0.42), Vector2(-0.14, -0.18), Vector2(0.22, -0.88),
				Vector2(0.96, 0.82)]), at, r, fill, outline)
			_poly(ci, _rect(-0.3, 0.2, 0.3, 0.82), at, r, ink, Color(0, 0, 0, 0))
			ci.draw_line(at + Vector2(-0.44, 0.14) * r, at + Vector2(0.44, 0.14) * r, fill.lightened(0.2), maxf(1.0, r * 0.1), true)
			ci.draw_line(at + Vector2(0.38, -0.5) * r, at + Vector2(0.22, -0.88) * r, Color(1, 1, 1, 0.6 * fill.a), maxf(1.0, r * 0.08), true)
		&"throne":
			_poly(ci, PackedVector2Array([Vector2(-0.56, 0.86), Vector2(-0.56, -0.58), Vector2(-0.3, -0.92), Vector2(0, -0.66),
				Vector2(0.3, -0.92), Vector2(0.56, -0.58), Vector2(0.56, 0.86), Vector2(0.34, 0.86), Vector2(0.34, 0.4),
				Vector2(-0.34, 0.4), Vector2(-0.34, 0.86)]), at, r, fill, outline)
			ci.draw_line(at + Vector2(-0.56, 0.14) * r, at + Vector2(0.56, 0.14) * r, ink, maxf(1.0, r * 0.1), true)
			ci.draw_circle(at + Vector2(0, -0.32) * r, 0.11 * r, ink, true, -1.0, true)
		&"tent":
			_stroke(ci, PackedVector2Array([at + Vector2(0, -0.6) * r, at + Vector2(0, -1.0) * r]), fill, outline, w * 0.8)
			_poly(ci, PackedVector2Array([Vector2(0, -1.0), Vector2(0.42, -0.9), Vector2(0, -0.78)]), at, r, fill, outline)
			_poly(ci, PackedVector2Array([Vector2(-0.94, 0.8), Vector2(0, -0.66), Vector2(0.94, 0.8)]), at, r, fill, outline)
			_poly(ci, PackedVector2Array([Vector2(-0.28, 0.8), Vector2(0, 0.06), Vector2(0.28, 0.8)]), at, r, ink, Color(0, 0, 0, 0))
		&"lighthouse":
			for sgn: float in [-1.0, 1.0]:
				ci.draw_line(at + Vector2(0.34 * sgn, -0.56) * r, at + Vector2(0.95 * sgn, -0.78) * r, Color(fill, fill.a * 0.8), maxf(1.0, r * 0.08), true)
				ci.draw_line(at + Vector2(0.34 * sgn, -0.44) * r, at + Vector2(0.95 * sgn, -0.3) * r, Color(fill, fill.a * 0.8), maxf(1.0, r * 0.08), true)
			_poly(ci, PackedVector2Array([Vector2(-0.36, 0.88), Vector2(-0.22, -0.32), Vector2(0.22, -0.32), Vector2(0.36, 0.88)]), at, r, fill, outline)
			_poly(ci, _rect(-0.26, -0.64, 0.26, -0.32), at, r, fill.lightened(0.25), outline)
			_poly(ci, PackedVector2Array([Vector2(-0.32, -0.64), Vector2(0, -0.92), Vector2(0.32, -0.64)]), at, r, fill, outline)
			for y in [0.1, 0.5]:
				ci.draw_line(at + Vector2(-0.3, y) * r, at + Vector2(0.3, y) * r, ink, maxf(1.0, r * 0.12), true)
		&"pin":
			_circle(ci, at + Vector2(0, -0.3) * r, 0.56 * r, fill, outline)
			_poly(ci, PackedVector2Array([Vector2(-0.44, -0.04), Vector2(0, 0.96), Vector2(0.44, -0.04)]), at, r, fill, outline)
			ci.draw_circle(at + Vector2(0, -0.3) * r, 0.56 * r, fill, true, -1.0, true)
			ci.draw_circle(at + Vector2(0, -0.3) * r, 0.22 * r, ink, true, -1.0, true)
		&"flag":
			_stroke(ci, PackedVector2Array([at + Vector2(-0.5, -0.94) * r, at + Vector2(-0.5, 0.94) * r]), fill.darkened(0.25), outline, w * 1.1)
			_poly(ci, PackedVector2Array([Vector2(-0.46, -0.9), Vector2(0.88, -0.84), Vector2(0.5, -0.52), Vector2(0.88, -0.2),
				Vector2(-0.46, -0.16)]), at, r, fill, outline)
		&"home":
			_poly(ci, _rect(0.32, -0.78, 0.56, -0.24), at, r, fill.darkened(0.2), outline)
			_poly(ci, _pts(&"house"), at, r, fill, outline)
			_poly(ci, _pts(&"door"), at, r, ink, Color(0, 0, 0, 0))
			_poly(ci, _rect(-0.56, 0.06, -0.3, 0.3), at, r, ink, Color(0, 0, 0, 0))
		&"chest":
			_poly(ci, _pts(&"chest_lid"), at, r, fill.darkened(0.12), outline)
			_poly(ci, _rect(-0.86, -0.08, 0.86, 0.74), at, r, fill, outline)
			ci.draw_line(at + Vector2(-0.86, 0.22) * r, at + Vector2(0.86, 0.22) * r, ink, maxf(1.0, r * 0.08), true)
			_poly(ci, _rect(-0.14, -0.04, 0.14, 0.34), at, r, ink, Color(0, 0, 0, 0))
		&"eye":
			_poly(ci, _pts(&"almond"), at, r, fill, outline)
			ci.draw_circle(at, 0.34 * r, ink, true, -1.0, true)
			ci.draw_circle(at + Vector2(-0.1, -0.1) * r, 0.1 * r, fill, true, -1.0, true)
		&"b_waves":
			for y in [-0.3, 0.25]:
				_stroke(ci, _wave(at, r, y, 0.9), fill, outline, w * 1.1)
		&"b_grass":
			for x in [-0.5, 0.0, 0.5]:
				var base := at + Vector2(x, 0.6) * r
				for a in [-0.5, 0.0, 0.5]:
					_stroke(ci, PackedVector2Array([base, base + Vector2(sin(a) * 0.32, -0.8 + absf(a) * 0.25) * r]), fill, outline, w * 0.8)
		&"b_tree":
			_stroke(ci, PackedVector2Array([at + Vector2(0, 0.0) * r, at + Vector2(0, 0.9) * r]), fill.darkened(0.3), outline, w * 1.4)
			_circle(ci, at + Vector2(0, -0.3) * r, 0.6 * r, fill, outline)
		&"b_pine":
			_stroke(ci, PackedVector2Array([at + Vector2(0, 0.5) * r, at + Vector2(0, 0.95) * r]), fill.darkened(0.3), outline, w * 1.4)
			_poly(ci, PackedVector2Array([Vector2(0, -0.96), Vector2(0.34, -0.4), Vector2(0.18, -0.4), Vector2(0.56, 0.1),
				Vector2(0.3, 0.1), Vector2(0.7, 0.6), Vector2(-0.7, 0.6), Vector2(-0.3, 0.1), Vector2(-0.56, 0.1),
				Vector2(-0.18, -0.4), Vector2(-0.34, -0.4)]), at, r, fill, outline)
		&"b_peak":
			_poly(ci, PackedVector2Array([Vector2(-0.96, 0.72), Vector2(-0.2, -0.82), Vector2(0.18, -0.12), Vector2(0.4, -0.44),
				Vector2(0.96, 0.72)]), at, r, fill, outline)
			_poly(ci, PackedVector2Array([Vector2(-0.2, -0.82), Vector2(0.0, -0.42), Vector2(-0.14, -0.5), Vector2(-0.3, -0.36),
				Vector2(-0.4, -0.42)]), at, r, Color(0.96, 0.96, 0.98, fill.a), Color(0, 0, 0, 0))
		&"b_reeds":
			for x in [-0.45, 0.0, 0.42]:
				var top := -0.7 + absf(x) * 0.4
				_stroke(ci, PackedVector2Array([at + Vector2(x, 0.85) * r, at + Vector2(x * 1.1, top) * r]), fill, outline, w * 0.8)
				_ellipse(ci, at + Vector2(x * 1.05, top + 0.25) * r, Vector2(0.1, 0.22) * r, fill.darkened(0.3), outline)
		&"b_dunes":
			for d: Vector3 in [Vector3(-0.3, 0.1, 0.6), Vector3(0.35, 0.55, 0.55)]:
				var arc := PackedVector2Array()
				for i in 11:
					var a := lerpf(PI, TAU, i / 10.0)
					arc.append(at + Vector2(d.x + cos(a) * d.z, d.y + sin(a) * d.z * 0.55) * r)
				_stroke(ci, arc, fill, outline, w * 1.1)
		&"b_flower":
			for k in 5:
				var a := -PI * 0.5 + TAU * k / 5.0
				_circle(ci, at + Vector2(cos(a), sin(a)) * 0.45 * r, 0.3 * r, fill, outline)
			ci.draw_circle(at, 0.24 * r, ink, true, -1.0, true)
		&"b_spikes":
			_poly(ci, PackedVector2Array([Vector2(-0.9, 0.8), Vector2(-0.56, -0.4), Vector2(-0.32, 0.3), Vector2(0.0, -0.94),
				Vector2(0.3, 0.3), Vector2(0.56, -0.5), Vector2(0.9, 0.8)]), at, r, fill, outline)
		&"b_mesa":
			_poly(ci, PackedVector2Array([Vector2(-0.96, 0.78), Vector2(-0.6, -0.4), Vector2(0.62, -0.4), Vector2(0.96, 0.78)]), at, r, fill, outline)
			for y in [0.0, 0.38]:
				ci.draw_line(at + Vector2(-0.6 - (y + 0.4) * 0.3, y) * r, at + Vector2(0.62 + (y + 0.4) * 0.3, y) * r, ink, maxf(1.0, r * 0.07), true)
		&"b_snow":
			for k in 3:
				var a := PI * k / 3.0 + PI * 0.5
				var d := Vector2(cos(a), sin(a))
				_stroke(ci, PackedVector2Array([at - d * 0.9 * r, at + d * 0.9 * r]), fill, outline, w)
				for sgn: float in [-1.0, 1.0]:
					var tip := at + d * 0.62 * sgn * r
					var side := d.orthogonal() * 0.22 * r
					ci.draw_line(tip, tip + d * 0.22 * sgn * r + side, fill, maxf(1.0, w * 0.7), true)
					ci.draw_line(tip, tip + d * 0.22 * sgn * r - side, fill, maxf(1.0, w * 0.7), true)
		&"b_fjord":
			_poly(ci, PackedVector2Array([Vector2(-0.96, 0.4), Vector2(-0.5, -0.8), Vector2(-0.1, 0.4)]), at, r, fill, outline)
			_poly(ci, PackedVector2Array([Vector2(0.1, 0.4), Vector2(0.5, -0.5), Vector2(0.96, 0.4)]), at, r, fill, outline)
			_stroke(ci, _wave(at, r, 0.7, 0.9), SEA if fill.a > 0.9 else fill, outline, w)
		&"b_dot":
			_circle(ci, at, 0.5 * r, fill, outline)
		&"quest":
			_poly(ci, _pts(&"lozenge"), at, r, fill, outline)
			_poly(ci, _pts(&"bang"), at, r, ink, Color(0, 0, 0, 0))
			ci.draw_circle(at + Vector2(0, 0.42) * r, 0.11 * r, ink, true, -1.0, true)
		_:
			_poly(ci, _pts(&"lozenge"), at, r * 0.7, fill, outline)


## A polyline with an outline under it (screen-space points).
static func _stroke(ci: CanvasItem, pts: PackedVector2Array, fill: Color, outline: Color, width: float) -> void:
	if outline.a > 0.0:
		ci.draw_polyline(pts, outline, width + 2.0, true)
	ci.draw_polyline(pts, fill, width, true)


## Unit-space rectangle as a polygon.
static func _rect(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


static func _scaled(unit: PackedVector2Array, at: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(unit.size())
	for i in unit.size():
		out[i] = at + unit[i] * r
	return out


## A wave line across the symbol at unit height `y`, `half` wide each side.
static func _wave(at: Vector2, r: float, y: float, half: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 13:
		var t := i / 12.0
		out.append(at + Vector2(lerpf(-half, half, t), y + sin(t * TAU * 1.5) * 0.08) * r)
	return out


static func _palm(ci: CanvasItem, at: Vector2, r: float, fill: Color, outline: Color, w: float) -> void:
	var trunk := PackedVector2Array()
	for i in 7:
		var t := i / 6.0
		trunk.append(at + Vector2(0.12 - t * 0.2 + sin(t * PI) * 0.12, 0.62 - t * 1.12) * r)
	_stroke(ci, trunk, fill.darkened(0.3), outline, w * 1.3)
	var crown := trunk[trunk.size() - 1]
	for a: float in [-2.9, -2.2, -1.25, -0.5, 0.15]:
		var d := Vector2(cos(a), sin(a))
		var tip := crown + (d * 0.62 + Vector2(0, 0.26)) * r
		var mid := crown + (d * 0.34 + Vector2(0, -0.02)) * r
		var side := d.orthogonal() * 0.1 * r
		var leaf := PackedVector2Array([crown, mid + side, tip, mid - side])
		var closed := leaf.duplicate()
		closed.append(leaf[0])
		if outline.a > 0.0:
			ci.draw_polyline(closed, outline, 2.0, true)
		ci.draw_colored_polygon(leaf, fill)


## A player marker: a coloured pin whose tip sits on `at` (its world spot),
## with the chosen symbol inside. `r` is the pin head's radius.
static func draw_marker(ci: CanvasItem, icon: StringName, col: Color, at: Vector2, r: float, alpha := 1.0, selected := false) -> void:
	var head := at + Vector2(0, -r * 1.55)
	var c := Color(col, col.a * alpha)
	var dark := Color(0.06, 0.05, 0.045, 0.95 * alpha)
	var tail := PackedVector2Array([head + Vector2(-r * 0.62, r * 0.7), at, head + Vector2(r * 0.62, r * 0.7)])
	ci.draw_colored_polygon(PackedVector2Array([tail[0] + Vector2(-1.2, 0), at + Vector2(0, 1.8), tail[2] + Vector2(1.2, 0)]), Color(0, 0, 0, 0.6 * alpha))
	ci.draw_colored_polygon(tail, c)
	ci.draw_circle(head, r + 1.6, Color(0, 0, 0, 0.6 * alpha), true, -1.0, true)
	ci.draw_circle(head, r, c, true, -1.0, true)
	ci.draw_circle(head, r * 0.8, dark, true, -1.0, true)
	draw_glyph(ci, icon, head, r * 0.56, c, Color(0, 0, 0, 0))
	if selected:
		ci.draw_arc(head, r + 4.0, 0.0, TAU, 32, Color(1, 1, 1, 0.85 * alpha), 1.5, true)


# --- Primitives ----------------------------------------------------------------------

static func _poly(ci: CanvasItem, unit: PackedVector2Array, at: Vector2, r: float, fill: Color, outline: Color) -> void:
	var pts := PackedVector2Array()
	pts.resize(unit.size())
	for i in unit.size():
		pts[i] = at + unit[i] * r
	var closed := pts.duplicate()
	closed.append(pts[0])
	if outline.a > 0.0:
		ci.draw_polyline(closed, outline, 2.4, true)
	ci.draw_colored_polygon(pts, fill)
	# Anti-aliased edge over the (aliased) fill.
	ci.draw_polyline(closed, fill, 1.0, true)


static func _circle(ci: CanvasItem, at: Vector2, r: float, fill: Color, outline: Color) -> void:
	if outline.a > 0.0:
		ci.draw_circle(at, r + 1.2, outline, true, -1.0, true)
	ci.draw_circle(at, r, fill, true, -1.0, true)


static func _ellipse(ci: CanvasItem, at: Vector2, radii: Vector2, fill: Color, outline: Color) -> void:
	var unit := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		unit.append(Vector2(cos(a) * radii.x, sin(a) * radii.y))
	_poly(ci, unit, at, 1.0, fill, outline)


## Unit-space outlines (y down), built once.
static func _pts(id: StringName) -> PackedVector2Array:
	if _shapes.is_empty():
		_init_shapes()
	return _shapes.get(id, _shapes[&"lozenge"])


static func _init_shapes() -> void:
	var s := _shapes
	s[&"lozenge"] = PackedVector2Array([Vector2(0, -1), Vector2(0.72, 0), Vector2(0, 1), Vector2(-0.72, 0)])
	s[&"blade"] = PackedVector2Array([Vector2(0, -0.95), Vector2(0.16, -0.6), Vector2(0.14, 0.26), Vector2(-0.14, 0.26), Vector2(-0.16, -0.6)])
	var star := PackedVector2Array()
	for i in 8:
		var a := -PI * 0.5 + TAU * i / 8.0
		var rr := 0.95 if i % 2 == 0 else 0.3
		star.append(Vector2(cos(a), sin(a)) * rr)
	s[&"star4"] = star
	s[&"bang"] = PackedVector2Array([Vector2(-0.11, -0.58), Vector2(0.11, -0.58), Vector2(0.07, 0.2), Vector2(-0.07, 0.2)])
	s[&"skull_jaw"] = PackedVector2Array([Vector2(-0.44, 0.22), Vector2(0.44, 0.22), Vector2(0.38, 0.8), Vector2(-0.38, 0.8)])
	s[&"skull_nose"] = PackedVector2Array([Vector2(0, 0.1), Vector2(0.1, 0.3), Vector2(-0.1, 0.3)])
	var fish := PackedVector2Array()
	for i in 17:
		var a := lerpf(PI * 0.2, PI * 1.8, i / 16.0)
		fish.append(Vector2(-0.05 + cos(a) * 0.62, sin(a) * 0.34 * (1.0 - 0.25 * absf(cos(a)))))
	fish.append(Vector2(0.95, -0.5))
	fish.append(Vector2(0.78, 0.0))
	fish.append(Vector2(0.95, 0.5))
	s[&"fish"] = fish
	s[&"fin"] = PackedVector2Array([Vector2(-0.25, -0.2), Vector2(0.05, -0.62), Vector2(0.28, -0.22)])
	s[&"dragon"] = PackedVector2Array([Vector2(-0.95, -0.04), Vector2(-0.56, -0.2), Vector2(-0.26, -0.34),
		Vector2(0.1, -0.96), Vector2(0.06, -0.4), Vector2(0.58, -0.86), Vector2(0.4, -0.3), Vector2(0.8, -0.1),
		Vector2(0.98, 0.16), Vector2(0.74, 0.26), Vector2(0.9, 0.5), Vector2(0.64, 0.58), Vector2(0.64, 0.96),
		Vector2(0.12, 0.96), Vector2(0.1, 0.5), Vector2(-0.3, 0.42), Vector2(-0.86, 0.34), Vector2(-0.42, 0.15),
		Vector2(-0.95, 0.1)])
	s[&"crown"] = PackedVector2Array([Vector2(-0.82, 0.58), Vector2(-0.82, -0.42), Vector2(-0.42, 0.04), Vector2(0, -0.72),
		Vector2(0.42, 0.04), Vector2(0.82, -0.42), Vector2(0.82, 0.58)])
	s[&"flame"] = PackedVector2Array([Vector2(0.02, -0.98), Vector2(0.28, -0.52), Vector2(0.58, -0.2), Vector2(0.64, 0.26),
		Vector2(0.42, 0.68), Vector2(0, 0.88), Vector2(-0.42, 0.68), Vector2(-0.64, 0.26), Vector2(-0.52, -0.18),
		Vector2(-0.32, 0.02), Vector2(-0.24, -0.46)])
	s[&"flame_core"] = PackedVector2Array([Vector2(0.02, -0.12), Vector2(0.26, 0.24), Vector2(0.22, 0.56), Vector2(0, 0.7),
		Vector2(-0.22, 0.56), Vector2(-0.26, 0.28)])
	s[&"hat"] = PackedVector2Array([Vector2(-0.46, 0.46), Vector2(-0.26, 0.0), Vector2(-0.1, -0.42), Vector2(0.12, -0.76),
		Vector2(0.42, -0.94), Vector2(0.74, -0.86), Vector2(0.88, -0.66), Vector2(0.66, -0.7), Vector2(0.4, -0.66),
		Vector2(0.24, -0.3), Vector2(0.3, 0.06), Vector2(0.46, 0.46)])
	var brim := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		brim.append(Vector2(cos(a) * 0.96, 0.52 + sin(a) * 0.17))
	s[&"brim"] = brim
	s[&"crystal"] = PackedVector2Array([Vector2(0, -0.98), Vector2(0.5, -0.3), Vector2(0.4, 0.6), Vector2(0, 0.96),
		Vector2(-0.4, 0.6), Vector2(-0.5, -0.3)])
	s[&"house"] = PackedVector2Array([Vector2(-0.74, 0.82), Vector2(-0.74, -0.06), Vector2(0, -0.8), Vector2(0.74, -0.06), Vector2(0.74, 0.82)])
	s[&"door"] = PackedVector2Array([Vector2(-0.2, 0.82), Vector2(-0.2, 0.26), Vector2(0.2, 0.26), Vector2(0.2, 0.82)])
	s[&"plinth"] = PackedVector2Array([Vector2(-0.62, 0.2), Vector2(0.62, 0.2), Vector2(0.4, 0.48), Vector2(0.4, 0.86),
		Vector2(-0.4, 0.86), Vector2(-0.4, 0.48)])
	s[&"small_flame"] = PackedVector2Array([Vector2(0.02, -0.96), Vector2(0.24, -0.56), Vector2(0.42, -0.26), Vector2(0.36, 0.04),
		Vector2(0, 0.16), Vector2(-0.36, 0.04), Vector2(-0.42, -0.26), Vector2(-0.18, -0.5)])
	s[&"hill"] = PackedVector2Array([Vector2(-0.96, 0.78), Vector2(-0.46, -0.42), Vector2(-0.1, -0.76), Vector2(0.32, -0.52), Vector2(0.96, 0.78)])
	var arch := PackedVector2Array()
	for i in 13:
		var a := lerpf(PI, TAU, i / 12.0)
		arch.append(Vector2(cos(a) * 0.4, 0.78 + sin(a) * 0.5))
	s[&"arch"] = arch
	s[&"tower"] = PackedVector2Array([Vector2(-0.36, 0.86), Vector2(-0.3, -0.42), Vector2(-0.5, -0.42), Vector2(-0.5, -0.88),
		Vector2(-0.28, -0.88), Vector2(-0.28, -0.7), Vector2(-0.1, -0.7), Vector2(-0.1, -0.88), Vector2(0.1, -0.88),
		Vector2(0.1, -0.7), Vector2(0.28, -0.7), Vector2(0.28, -0.88), Vector2(0.5, -0.88), Vector2(0.5, -0.42),
		Vector2(0.3, -0.42), Vector2(0.36, 0.86)])
	s[&"keep"] = PackedVector2Array([Vector2(-0.9, 0.82), Vector2(-0.9, -0.7), Vector2(-0.68, -0.7), Vector2(-0.68, -0.52),
		Vector2(-0.5, -0.52), Vector2(-0.5, -0.7), Vector2(-0.3, -0.7), Vector2(-0.3, -0.2), Vector2(0.3, -0.2),
		Vector2(0.3, -0.7), Vector2(0.5, -0.7), Vector2(0.5, -0.52), Vector2(0.68, -0.52), Vector2(0.68, -0.7),
		Vector2(0.9, -0.7), Vector2(0.9, 0.82)])
	var kd := PackedVector2Array([Vector2(-0.2, 0.82)])
	for i in 9:
		var a := lerpf(PI, TAU, i / 8.0)
		kd.append(Vector2(cos(a) * 0.2, 0.36 + sin(a) * 0.22))
	kd.append(Vector2(0.2, 0.82))
	s[&"keep_door"] = kd
	s[&"gate"] = PackedVector2Array([Vector2(-0.9, 0.8), Vector2(-0.9, -0.55), Vector2(-0.45, -0.85), Vector2(0.45, -0.85),
		Vector2(0.9, -0.55), Vector2(0.9, 0.8)])
	s[&"column_a"] = PackedVector2Array([Vector2(-0.62, 0.66), Vector2(-0.62, -0.58), Vector2(-0.44, -0.78), Vector2(-0.3, -0.5),
		Vector2(-0.26, 0.66)])
	s[&"column_b"] = PackedVector2Array([Vector2(0.16, 0.66), Vector2(0.16, -0.02), Vector2(0.36, 0.1), Vector2(0.54, -0.12),
		Vector2(0.54, 0.66)])
	var almond := PackedVector2Array()
	for i in 13:
		var t := i / 12.0
		almond.append(Vector2(lerpf(-0.92, 0.92, t), -sin(t * PI) * 0.5))
	for i in range(11, 0, -1):
		var t := i / 12.0
		almond.append(Vector2(lerpf(-0.92, 0.92, t), sin(t * PI) * 0.5))
	s[&"almond"] = almond
	var slit := PackedVector2Array()
	for i in 9:
		var t := i / 8.0
		slit.append(Vector2(sin(t * PI) * 0.14, lerpf(-0.46, 0.46, t)))
	for i in range(7, 0, -1):
		var t := i / 8.0
		slit.append(Vector2(-sin(t * PI) * 0.14, lerpf(-0.46, 0.46, t)))
	s[&"slit"] = slit
	s[&"hull"] = PackedVector2Array([Vector2(-0.94, 0.06), Vector2(-0.2, 0.2), Vector2(0.9, 0.3), Vector2(0.62, 0.66), Vector2(-0.56, 0.56)])
	s[&"serpent_head"] = PackedVector2Array([Vector2(-0.34, -0.42), Vector2(-0.5, -0.66), Vector2(-0.94, -0.56),
		Vector2(-0.96, -0.42), Vector2(-0.56, -0.32)])
	s[&"spire"] = PackedVector2Array([Vector2(-0.3, 0.84), Vector2(-0.3, -0.2), Vector2(0, -0.98), Vector2(0.3, -0.2), Vector2(0.3, 0.84)])
	var lid := PackedVector2Array([Vector2(-0.86, -0.08)])
	for i in 9:
		var a := lerpf(PI, TAU, i / 8.0)
		lid.append(Vector2(cos(a) * 0.86, -0.08 + sin(a) * 0.5))
	s[&"chest_lid"] = lid
	s[&"ruin_base"] = PackedVector2Array([Vector2(-0.84, 0.64), Vector2(0.84, 0.64), Vector2(0.84, 0.86), Vector2(-0.84, 0.86)])

