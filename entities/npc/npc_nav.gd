class_name NpcNav
extends RefCounted
## Walking routes for villagers on smooth ground and around buildings.
##
## A query plans over a 1 m grid with A*: a cell is walkable when a person can
## stand on it (smooth ground or a built floor under the feet, head room, no
## wall or water) and neighbouring cells differ by no more than a comfortable
## step. Queries are stepped a few hundred cells per tick so planning never
## hitches; standability is cached per cell for a while (terrain can be dug).
## The resulting cells are string-pulled into a few straight legs.

const STEP_UP := 0.62          ## a stride up or down between cells (m)
const MAX_CELLS := 3200        ## give up beyond this many expanded cells
const CACHE_SECONDS := 45.0

static var _stand_cache := {}  # Vector3i(x, z, dim) -> [height or NAN, time]


class Query:
	extends RefCounted
	var vw: VoxelWorld
	var dim := 0
	var start := Vector2i.ZERO
	var goal := Vector2i.ZERO
	var start_y := 0.0
	var goal_y := 0.0
	var open: Array = []          # binary heap of [f, Vector2i]
	var g := {}                   # Vector2i -> cost
	var came := {}                # Vector2i -> Vector2i
	var height := {}              # Vector2i -> float
	var closed := {}
	var expanded := 0
	var done := false
	var ok := false
	var path := PackedVector3Array()
	var radius := 40.0
	var best := Vector2i.ZERO
	var best_h := INF
	var allow_partial := true


## Starts a plan from `from` to `to` (feet positions). Step it until `done`.
static func plan(vw: VoxelWorld, dim: int, from: Vector3, to: Vector3, radius := 40.0) -> Query:
	var q := Query.new()
	q.vw = vw
	q.dim = dim
	q.start = Vector2i(floori(from.x), floori(from.z))
	q.goal = Vector2i(floori(to.x), floori(to.z))
	q.start_y = from.y
	q.goal_y = to.y
	q.radius = radius
	q.g[q.start] = 0.0
	q.height[q.start] = from.y
	q.best = q.start
	q.best_h = Vector2(q.start - q.goal).length()
	_push(q.open, [q.best_h, q.start])
	return q


## Expands up to `budget` cells. Returns true once the query has finished.
static func step(q: Query, budget := 220) -> bool:
	if q.done:
		return true
	var n := 0
	while not q.open.is_empty() and n < budget:
		var top: Array = _pop(q.open)
		var c: Vector2i = top[1]
		if q.closed.has(c):
			continue
		q.closed[c] = true
		n += 1
		q.expanded += 1
		if c == q.goal or (absi(c.x - q.goal.x) <= 0 and absi(c.y - q.goal.y) <= 0):
			_finish(q, c, true)
			return true
		var h := Vector2(c - q.goal).length()
		if h < q.best_h:
			q.best_h = h
			q.best = c
		if q.expanded > MAX_CELLS:
			break
		var cy: float = q.height[c]
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var nb := c + d
			if q.closed.has(nb):
				continue
			if Vector2(nb - q.start).length() > q.radius and Vector2(nb - q.goal).length() > q.radius:
				continue
			var ny := stand_height(q.vw, q.dim, nb.x + 0.5, nb.y + 0.5, cy)
			if is_nan(ny) or not step_ok(cy, ny):
				continue
			if d.x != 0 and d.y != 0:
				# No cutting corners past walls.
				var ax := stand_height(q.vw, q.dim, c.x + d.x + 0.5, c.y + 0.5, cy)
				var az := stand_height(q.vw, q.dim, c.x + 0.5, c.y + d.y + 0.5, cy)
				if is_nan(ax) or is_nan(az):
					continue
			var cost: float = q.g[c] + (1.4142 if d.x != 0 and d.y != 0 else 1.0) + absf(ny - cy) * 0.8
			if cost < float(q.g.get(nb, INF)):
				q.g[nb] = cost
				q.came[nb] = c
				q.height[nb] = ny
				_push(q.open, [cost + Vector2(nb - q.goal).length(), nb])
	if q.open.is_empty() or q.expanded > MAX_CELLS:
		# Unreachable: walk as close as possible if that gets anywhere.
		var near_enough := q.allow_partial and q.best != q.start
		_finish(q, q.best, near_enough)
		return true
	return false


static func _finish(q: Query, end: Vector2i, ok: bool) -> void:
	q.done = true
	q.ok = ok
	if not ok:
		return
	var cells: Array[Vector2i] = [end]
	var c := end
	while q.came.has(c):
		c = q.came[c]
		cells.push_front(c)
	var pts := PackedVector3Array()
	for cell in cells:
		pts.append(Vector3(cell.x + 0.5, float(q.height[cell]), cell.y + 0.5))
	q.path = smooth(q.vw, q.dim, pts)


## String pulling: drop intermediate points while a straight walk stays clear.
static func smooth(vw: VoxelWorld, dim: int, pts: PackedVector3Array) -> PackedVector3Array:
	if pts.size() <= 2:
		return pts
	var out := PackedVector3Array([pts[0]])
	var i := 0
	while i < pts.size() - 1:
		var j := pts.size() - 1
		while j > i + 1 and not segment_clear(vw, dim, pts[i], pts[j]):
			j -= 1
		out.append(pts[j])
		i = j
	return out


## Can a person walk straight from a to b (both feet positions)?
static func segment_clear(vw: VoxelWorld, dim: int, a: Vector3, b: Vector3) -> bool:
	var flat := Vector2(b.x - a.x, b.z - a.z)
	var length := flat.length()
	if length < 0.05:
		return true
	var n := ceili(length / 0.35)
	var prev := a.y
	for k in range(1, n + 1):
		var t := float(k) / n
		var p := a.lerp(b, t)
		var h := stand_height(vw, dim, p.x, p.z, prev)
		if is_nan(h) or not step_ok(prev, h):
			return false
		prev = h
	return true


## A stride from height a to b: gentle slopes, or one built step (a whole
## block ledge onto a floor or porch, which VoxelBody climbs).
static func step_ok(a: float, b: float) -> bool:
	var dy := absf(b - a)
	if dy <= STEP_UP:
		return true
	var crisp := absf(a - roundf(a)) < 0.03 or absf(b - roundf(b)) < 0.03
	return crisp and dy <= 1.05


## Height a person stands at over (x, z) near `y_hint`, or NAN where nobody can
## stand (wall, water, cliff, no ground loaded). Cached per cell centre.
static func stand_height(vw: VoxelWorld, dim: int, x: float, z: float, y_hint: float) -> float:
	# Measured on a 25 cm lattice (nearest point), so cached answers are exact for it.
	var cell := Vector3i(roundi(x * 4.0), roundi(z * 4.0), dim)
	x = cell.x * 0.25
	z = cell.y * 0.25
	var now := Time.get_ticks_msec() / 1000.0
	var hit: Variant = _stand_cache.get(cell)
	if hit != null and now - float(hit[1]) < CACHE_SECONDS:
		var cached: float = hit[0]
		if is_nan(cached) or absf(cached - y_hint) < 3.0:
			return cached
	var h := _measure(vw, x, z, y_hint)
	_stand_cache[cell] = [h, now]
	if _stand_cache.size() > 120000:
		_stand_cache.clear()
	return h


static func forget_cache() -> void:
	_stand_cache.clear()


static func _measure(vw: VoxelWorld, x: float, z: float, y_hint: float) -> float:
	if vw == null or not vw.is_area_loaded(Vector3(x, y_hint, z)):
		return NAN
	var top := y_hint + 1.7
	var g := vw.ground_below(x, top, z, 3.8)
	var smooth_ok := absf(g) < 1e6
	# Built floors (crisp cells under the feet) count as ground too.
	var crisp := -INF
	var cx := floori(x)
	var cz := floori(z)
	for y in range(floori(top), floori(y_hint - 2.2), -1):
		var b := vw.get_block(Vector3i(cx, y, cz))
		if b < 0:
			return NAN
		if b > 0 and Blocks.is_solid(b) and not Blocks.is_smooth(b):
			if not Blocks.is_solid(vw.get_block(Vector3i(cx, y + 1, cz))) and not Blocks.is_solid(vw.get_block(Vector3i(cx, y + 2, cz))):
				crisp = float(y + 1)
			break
	var h := g if smooth_ok else -INF
	if crisp > h:
		h = crisp
	if h == -INF or h > top:
		return NAN
	# Head room and walls: smooth ground or a crisp block where the body would be.
	for dy: float in [0.7, 1.5]:
		var p := Vector3(x, h + dy, z)
		if vw.field(p) >= 0.5:
			return NAN
		var b := vw.get_block(Vector3i(p.floor()))
		if b < 0 or (b > 0 and Blocks.is_solid(b) and not Blocks.is_smooth(b)):
			return NAN
	# Narrow gaps: the corners of the body at hip height.
	for o: Vector2 in [Vector2(0.3, 0.3), Vector2(-0.3, 0.3), Vector2(0.3, -0.3), Vector2(-0.3, -0.3)]:
		for dy: float in [0.05, 0.9, 1.7]:
			var q := Vector3i(floori(x + o.x), floori(h + dy), floori(z + o.y))
			var bq := vw.get_block(q)
			if bq < 0 or (bq > 0 and Blocks.is_solid(bq) and not Blocks.is_smooth(bq)):
				return NAN
	# Water and lava are no place to stroll.
	var feet := vw.get_block(Vector3i(cx, floori(h + 0.3), cz))
	if feet > 0 and Blocks.is_liquid(feet):
		return NAN
	return h


# --- Binary heap -----------------------------------------------------------------

static func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if float(heap[parent][0]) <= float(item[0]):
			break
		heap[i] = heap[parent]
		i = parent
	heap[i] = item


static func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	var i := 0
	var n := heap.size()
	while true:
		var l := i * 2 + 1
		if l >= n:
			break
		var r := l + 1
		var c := r if r < n and float(heap[r][0]) < float(heap[l][0]) else l
		if float(heap[c][0]) >= float(last[0]):
			break
		heap[i] = heap[c]
		i = c
	heap[i] = last
	return top
