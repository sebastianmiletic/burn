class_name MapIcons
extends RefCounted
## Crisp vector map symbols for the minimap and world map, drawn with
## CanvasItem primitives (anti-aliased outlines over filled shapes) so they
## stay sharp at every size and UI scale.
##
##   MapIcons.draw_place(canvas, place, at, radius, state)  one marker
##   MapIcons.place_of(world, loc)                         -> place Dictionary
##   MapIcons.boss_icon("leviathan")                       -> &"serpent"
##
## Bosses sit on a dark badge with a crimson ring; once defeated the badge
## turns grey and is crossed out. Places draw as outlined silhouettes.

enum State { NORMAL, DEFEATED, FADED }

const BOSS_ICONS := {
	"warden": &"skull", "leviathan": &"serpent", "sea_serpent": &"serpent", "dragon": &"dragon",
	"ashvane": &"dragon", "broodmother": &"spider", "mountain_king": &"crown", "hades": &"flame",
	"cerberus": &"hound", "bog_hag": &"witch", "prism_sentinel": &"crystal", "void_sovereign": &"crystal",
	"kraken": &"kraken", "charybdis": &"whirlpool",
}
const BOSS_NAMES := {
	"warden": "The Warden", "leviathan": "The Leviathan", "dragon": "Ashvane", "broodmother": "Vexhira the Broodmother",
	"mountain_king": "The Mountain King", "hades": "Hades", "cerberus": "Cerberus", "bog_hag": "Old Mother Mire",
	"prism_sentinel": "The Prism Sentinel", "void_sovereign": "The Void Sovereign",
	"kraken": "The Abyssal Kraken", "charybdis": "Charybdis",
}

const BONE := Color(0.95, 0.9, 0.8)
const INK := Color(0.05, 0.04, 0.035)
const BOSS_RING := Color(0.86, 0.22, 0.16)
const DEFEATED := Color(0.5, 0.48, 0.46)
const QUEST := Color(1.0, 0.8, 0.32)
const VILLAGE := Color(0.96, 0.86, 0.66)
const SHRINE := Color(1.0, 0.66, 0.26)
const STONE := Color(0.8, 0.74, 0.64)
const PORTAL := Color(0.74, 0.55, 1.0)

static var _shapes := {}


## The symbol for a boss kind (unknown future bosses get the closest match).
static func boss_icon(kind: String) -> StringName:
	if BOSS_ICONS.has(kind):
		return BOSS_ICONS[kind]
	for key in ["crystal", "prism", "void", "ryft"]:
		if key in kind:
			return &"crystal"
	for key in ["serpent", "kraken", "fish", "sea"]:
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
	return &"skull"


static func boss_name(kind: String) -> String:
	return BOSS_NAMES.get(kind, kind.capitalize())


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


## Describes how a location shows on the map:
## {"icon", "boss", "name", "sub", "state", "major", "color"}.
static func place_of(world: Object, loc: Object) -> Dictionary:
	var boss := boss_of(loc)
	var id := String(loc.get("id"))
	var kind := int(loc.get("kind"))
	var name := str(loc.get("name"))
	var out := {"icon": &"poi", "boss": boss, "name": name, "sub": "", "state": State.NORMAL,
		"major": loc.get("major") == true, "color": STONE}
	if boss != "":
		out["icon"] = boss_icon(boss)
		out["major"] = true
		var defeated: Variant = world.get("bosses_defeated") if world != null else null
		var dead := defeated is Dictionary and (defeated as Dictionary).has(boss)
		out["state"] = State.DEFEATED if dead else State.NORMAL
		out["sub"] = boss_name(boss) + (" · defeated" if dead else "")
		return out
	var has_portal := false
	var spawns: Variant = loc.get("spawns")
	if spawns is Array:
		for s: Dictionary in spawns:
			if s.get("type", "") == "portal":
				has_portal = true
	match kind:
		Location.Kind.VILLAGE:
			out["icon"] = &"village"
			out["color"] = VILLAGE
			out["sub"] = "Village"
		Location.Kind.SHRINE:
			out["icon"] = &"shrine"
			var lit: Variant = world.get("lit_shrines") if world != null else null
			var on := lit is Dictionary and (lit as Dictionary).has(loc.get("id"))
			out["color"] = SHRINE if on else STONE.darkened(0.15)
			out["sub"] = "Shrine · kindled" if on else "Shrine"
		Location.Kind.TOWER:
			out["icon"] = &"tower"
			out["sub"] = "Watchtower"
		Location.Kind.MINE:
			out["icon"] = &"mine"
			out["sub"] = "Mine"
		Location.Kind.CRYPT:
			out["icon"] = &"mine" if ("mine" in id or "adit" in id) else &"cave"
			out["sub"] = "Mine" if out["icon"] == &"mine" else "Cave"
		Location.Kind.HELL_SPAWN:
			out["icon"] = &"portal"
			out["color"] = PORTAL
			out["sub"] = "Portal"
		Location.Kind.GATE:
			out["icon"] = &"gate"
			out["color"] = Color(1.0, 0.5, 0.3)
			out["sub"] = "Gate"
		Location.Kind.CASTLE, Location.Kind.HALL, Location.Kind.TARTARUS, Location.Kind.THRONE:
			out["icon"] = &"keep"
			out["sub"] = Location.KIND_LABELS[kind]
		_:
			out["icon"] = &"anchor" if id.begins_with("wreck") else &"ruin"
			out["sub"] = "Wreck" if id.begins_with("wreck") else "Ruins"
	if has_portal and out["icon"] in [&"ruin", &"poi"]:
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
			_poly(ci, _pts(&"fin"), at, r, fill, outline)
			_poly(ci, _pts(&"fish"), at, r, fill, outline)
			ci.draw_circle(at + Vector2(-0.5, -0.06) * r, 0.09 * r, ink, true, -1.0, true)
			ci.draw_arc(at + Vector2(-0.3, 0.0) * r, 0.2 * r, -1.2, 1.2, 8, ink, maxf(1.0, r * 0.07), true)
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
			_poly(ci, _pts(&"house"), at, r, fill, outline)
			_poly(ci, _pts(&"door"), at, r, ink, Color(0, 0, 0, 0))
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
		&"quest":
			_poly(ci, _pts(&"lozenge"), at, r, fill, outline)
			_poly(ci, _pts(&"bang"), at, r, ink, Color(0, 0, 0, 0))
			ci.draw_circle(at + Vector2(0, 0.42) * r, 0.11 * r, ink, true, -1.0, true)
		_:
			_poly(ci, _pts(&"lozenge"), at, r * 0.7, fill, outline)


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
	s[&"ruin_base"] = PackedVector2Array([Vector2(-0.84, 0.64), Vector2(0.84, 0.64), Vector2(0.84, 0.86), Vector2(-0.84, 0.86)])

