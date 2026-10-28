class_name GlyphRecognizer
extends RefCounted
## Single-stroke gesture recognition in the spirit of the $1 Unistroke
## recogniser (Wobbrock et al. 2007): resample the stroke to N points, scale
## it uniformly into a unit box, centre it and compare point-by-point against
## templates. Orientation matters here (a "vee" is not a "caret"), so there is
## no rotation step; instead closed shapes get templates for every starting
## point and both drawing directions, and open shapes for both directions.
## Screen coordinates: +y is down.

const N := 48
## Below this the stroke is a scribble, not a glyph.
const MIN_EXTENT := 24.0

## Glyph id -> display name and how to draw it (for the spellbook).
const GLYPHS := {
	"circle": {"name": "Circle", "how": "One loop, back to where you started."},
	"triangle": {"name": "Triangle", "how": "Three straight sides, point at the top."},
	"square": {"name": "Square", "how": "Four sides, corners sharp."},
	"zigzag": {"name": "Zigzag", "how": "Lightning: down-up-down-up, left to right."},
	"spiral": {"name": "Spiral", "how": "Start in the middle and wind outwards two turns."},
	"vee": {"name": "Vee", "how": "Down to a point and back up (a V)."},
	"caret": {"name": "Peak", "how": "Up to a point and back down (a ^)."},
	"wave": {"name": "Serpent", "how": "An S from top to bottom."},
	"rise": {"name": "Rising Line", "how": "One straight vertical stroke (either way)."},
	"veil": {"name": "Veil Line", "how": "One straight horizontal stroke (either way)."},
}

const CLOSED := ["circle", "triangle", "square"]

static var _templates: Array = []   # [glyph, PackedVector2Array]


## Canonical drawing of each glyph (unit-ish coordinates, y down).
static func canonical(glyph: String) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match glyph:
		"circle":
			for i in 33:
				var a := -PI * 0.5 + TAU * float(i) / 32.0
				pts.append(Vector2(cos(a), sin(a)))
		"triangle":
			pts = PackedVector2Array([Vector2(0, -1), Vector2(0.9, 0.6), Vector2(-0.9, 0.6), Vector2(0, -1)])
		"square":
			pts = PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)])
		"zigzag":
			pts = PackedVector2Array([Vector2(-1, -0.5), Vector2(-0.5, 0.5), Vector2(0, -0.5), Vector2(0.5, 0.5), Vector2(1, -0.5)])
		"spiral":
			for i in 61:
				var t := float(i) / 60.0
				var a := t * TAU * 2.25
				pts.append(Vector2(cos(a), sin(a)) * (0.08 + 0.92 * t))
		"vee":
			pts = PackedVector2Array([Vector2(-0.8, -1), Vector2(0, 1), Vector2(0.8, -1)])
		"caret":
			pts = PackedVector2Array([Vector2(-0.8, 1), Vector2(0, -1), Vector2(0.8, 1)])
		"rise":
			for i in 9:
				pts.append(Vector2(0, 1.0 - 2.0 * float(i) / 8.0))
		"veil":
			for i in 9:
				pts.append(Vector2(-1.0 + 2.0 * float(i) / 8.0, 0))
		"wave":
			for i in 41:
				var t := float(i) / 40.0
				pts.append(Vector2(-0.6 * sin(t * TAU), -1.0 + 2.0 * t))
	return pts


static func _ensure_templates() -> void:
	if not _templates.is_empty():
		return
	for g: String in GLYPHS:
		var base := resample(canonical(g), N)
		var variants: Array = []
		if g in CLOSED:
			# Every starting point, both directions. Every point, not a coarse
			# subset: a start a point or two off costs as much distance as the
			# difference between a square and a circle.
			var ring := base.slice(0, N - 1)
			for dir in 2:
				var r := ring.duplicate()
				if dir == 1:
					r.reverse()
				for off in r.size():
					var v := PackedVector2Array()
					for i in r.size():
						v.append(r[(i + off) % r.size()])
					v.append(v[0])
					variants.append(v)
		else:
			variants.append(base)
			var rev := base.duplicate()
			rev.reverse()
			variants.append(rev)
		for v: PackedVector2Array in variants:
			_templates.append([g, normalize(v)])


## Resample a polyline to `n` evenly spaced points.
static func resample(points: PackedVector2Array, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if points.size() == 0:
		return out
	var total := path_length(points)
	if total <= 0.0001:
		for i in n:
			out.append(points[0])
		return out
	var step := total / float(n - 1)
	var pts := points.duplicate()
	out.append(pts[0])
	var acc := 0.0
	var i := 1
	while i < pts.size():
		var d := pts[i - 1].distance_to(pts[i])
		if acc + d >= step and d > 0.0:
			var q := pts[i - 1] + (step - acc) / d * (pts[i] - pts[i - 1])
			out.append(q)
			pts.insert(i, q)
			acc = 0.0
		else:
			acc += d
		i += 1
	while out.size() < n:
		out.append(pts[pts.size() - 1])
	if out.size() > n:
		out.resize(n)
	return out


static func path_length(points: PackedVector2Array) -> float:
	var d := 0.0
	for i in range(1, points.size()):
		d += points[i - 1].distance_to(points[i])
	return d


## Uniform scale into a unit box, centred on the centroid.
static func normalize(points: PackedVector2Array) -> PackedVector2Array:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var c := Vector2.ZERO
	for p in points:
		lo = lo.min(p)
		hi = hi.max(p)
		c += p
	c /= maxf(1.0, float(points.size()))
	var s := maxf(hi.x - lo.x, hi.y - lo.y)
	if s <= 0.0001:
		s = 1.0
	var out := PackedVector2Array()
	for p in points:
		out.append((p - c) / s)
	return out


static func extent(points: PackedVector2Array) -> float:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		lo = lo.min(p)
		hi = hi.max(p)
	return maxf(hi.x - lo.x, hi.y - lo.y) if points.size() > 0 else 0.0


static func _distance(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var d := 0.0
	for i in N:
		d += a[i].distance_to(b[i])
	return d / N


## Recognise a stroke (screen pixels). Returns
##   {glyph, score 0..1, second, second_score, valid}
## `allowed` (optional) restricts the candidates (e.g. glyphs a role knows).
static func recognize(stroke: PackedVector2Array, allowed: Array = []) -> Dictionary:
	_ensure_templates()
	var out := {"glyph": "", "score": 0.0, "second": "", "second_score": 0.0, "valid": false}
	if stroke.size() < 4 or extent(stroke) < MIN_EXTENT:
		return out
	var cand := normalize(resample(stroke, N))
	var best := {}
	for t: Array in _templates:
		var g: String = t[0]
		if not allowed.is_empty() and not g in allowed:
			continue
		var d := _distance(cand, t[1])
		if d < float(best.get(g, INF)):
			best[g] = d
	var names := best.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return float(best[a]) < float(best[b]))
	if names.is_empty():
		return out
	out["valid"] = true
	out["glyph"] = names[0]
	out["score"] = score_of(float(best[names[0]]))
	if names.size() > 1:
		out["second"] = names[1]
		out["second_score"] = score_of(float(best[names[1]]))
	return out


## Mean point distance (unit box) -> 0..1 similarity.
static func score_of(d: float) -> float:
	return clampf(1.0 - d / 0.32, 0.0, 1.0)


## A glyph as screen points (for the spellbook icons and tests), fitted to `rect`.
static func sample_points(glyph: String, rect: Rect2, jitter := 0.0, rng: RandomNumberGenerator = null) -> PackedVector2Array:
	var pts := resample(canonical(glyph), 64)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var s := minf(rect.size.x, rect.size.y) / maxf(0.001, maxf(hi.x - lo.x, hi.y - lo.y))
	var mid := (lo + hi) * 0.5
	var out := PackedVector2Array()
	for p in pts:
		var q := rect.get_center() + (p - mid) * s
		if jitter > 0.0 and rng != null:
			q += Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))
		out.append(q)
	return out
