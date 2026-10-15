class_name MineLayout
extends RefCounted
## Abandoned mine workings (world revision 3). A timbered portal on a hillside opens on an
## adit that declines to two or three levels of drifts. Each level has a main haulage drift
## with rails, lanterns and timber sets, crosscuts to stopes with live ore seams, a storeroom,
## a collapsed crosscut with something worth digging for behind it, and on the deeper levels a
## flooded sump and the deep gallery where something large has made its lair. The deepest
## level breaks through into the natural cave network.
##
## Output: carvers (smooth signed-distance tunnels, CaveNetwork) on the surface location's
## metadata &"carvers", the dressing (props for MineDressing) on the workings location's
## metadata &"mine", spawns (monsters, guardian, chests, lore) and STRUCTURE collision for carts.

const HW := 1.9          ## drift half width
const HEIGHT := 3.7      ## drift height
const GRADE := 0.26      ## declines

var surface: Location
var depths: Location
var gen: WorldGen
var rng: RandomNumberGenerator
var net := CaveNetwork.new()
var props: Array = []
var ore := Blocks.IRON_ORE
var rich_ore := Blocks.SILVER_ORE
var _lo := Vector3(INF, INF, INF)
var _hi := Vector3(-INF, -INF, -INF)
var _detail: FastNoiseLite
var _ridge: FastNoiseLite
var _floors: Array = []   # [Vector3 floor point, String role]


## surface: the entrance (centre = portal floor on the hillside); heading: horizontal direction
## into the hill. spec: {"ore": block, "rich": block, "levels": 2|3, "guardian": enemy kind}.
static func build(surface_loc: Location, depths_loc: Location, world_gen: WorldGen, heading: Vector2, random: RandomNumberGenerator, spec: Dictionary) -> void:
	var m := MineLayout.new()
	m.surface = surface_loc
	m.depths = depths_loc
	m.gen = world_gen
	m.rng = random
	m.ore = int(spec.get("ore", Blocks.IRON_ORE))
	m.rich_ore = int(spec.get("rich", Blocks.SILVER_ORE))
	m._detail = world_gen.make_detail_noise()
	m._ridge = world_gen.make_ridge_noise()
	m._layout(heading.normalized(), int(spec.get("levels", 2)), String(spec.get("guardian", "troll")))
	surface_loc.set_meta(&"carvers", m.net)
	depths_loc.set_meta(&"mine", {"props": m.props, "entrance": surface_loc.center, "heading": heading})
	# The workings location spans everything that was dug.
	var c := (m._lo + m._hi) * 0.5
	depths_loc.center = c
	depths_loc.ground_y = int(c.y)
	depths_loc.radius = maxf(m._hi.x - m._lo.x, m._hi.z - m._lo.z) * 0.5 + 8.0
	depths_loc.half_height = (m._hi.y - m._lo.y) * 0.5 + 2.0


func _ground(x: float, z: float) -> float:
	return gen.raw_height(int(x), int(z), _detail, _ridge) + 1.0


func _grow(p: Vector3) -> void:
	_lo = _lo.min(p - Vector3(HW, 0, HW))
	_hi = _hi.max(p + Vector3(HW, HEIGHT, HW))


static func _yaw(d: Vector3) -> float:
	return atan2(d.x, d.z)


## One drift from floor point a to b with its dressing.
func drift(a: Vector3, b: Vector3, rails := true, lamps := true, ore_block := 0, ore_chance := 0.0, broken := 0.08) -> void:
	net.add_drift(a, b, HW, HEIGHT, Blocks.GRAVEL, ore_block, ore_chance)
	_grow(a)
	_grow(b)
	var d := b - a
	var length := Vector2(d.x, d.z).length()
	var yaw := _yaw(d)
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	var sets := maxi(1, int(length / 3.3))
	for i in range(1, sets):
		var p := a.lerp(b, float(i) / sets)
		var kind := "broken_set" if rng.randf() < broken else "timber_set"
		props.append({"type": kind, "at": p, "yaw": yaw, "width": HW * 2.0 - 0.3, "height": HEIGHT - 0.35, "lagging": rng.randf() < 0.55})
	if rails:
		props.append({"type": "rail", "a": a, "b": b})
	if lamps:
		var lamp_count := maxi(1, int(length / 11.0))
		for i in lamp_count:
			var p := a.lerp(b, (i + 0.5) / lamp_count)
			var flip := 1.0 if i % 2 == 0 else -1.0
			props.append({"type": "lantern", "at": p + Vector3(0, HEIGHT - 0.55, 0) + side * flip * (HW - 0.55), "lit": rng.randf() < 0.75})


## A room (stope, store, gallery) with its floor centre at c.
func room(c: Vector3, half_x: float, half_z: float, height: float, yaw: float, ore_block := 0, ore_chance := 0.0, water := CaveNetwork.NO_WATER) -> void:
	net.add_room(c, half_x, half_z, height, yaw, Blocks.GRAVEL, ore_block, ore_chance, water)
	var r := maxf(half_x, half_z)
	_lo = _lo.min(c - Vector3(r, 0, r))
	_hi = _hi.max(c + Vector3(r, height, r))


## A decline from a (floor) heading `dir` that drops `drop` metres over turning segments.
## Returns [end floor point, final direction].
func decline(a: Vector3, dir: Vector2, drop: float, turn: float) -> Array:
	var run := drop / GRADE
	var segs := maxi(1, int(ceil(run / 24.0)))
	var cur := a
	var d := dir
	for i in segs:
		var seg_run := run / segs
		var next := cur + Vector3(d.x, 0, d.y) * seg_run - Vector3(0, drop / segs, 0)
		drift(cur, next, true, true, 0, 0.0, 0.04)
		cur = next
		d = d.rotated(turn)
	return [cur, d]


func _layout(f: Vector2, levels: int, guardian: String) -> void:
	var e := surface.center
	var f3 := Vector3(f.x, 0, f.y)
	var side := Vector3(-f.y, 0, f.x)
	# Portal: a cut into the slope, then a short level adit under cover.
	var portal := e - f3 * 3.5 + Vector3(0, -0.2, 0)
	var adit_end := e + f3 * 16.0 + Vector3(0, -0.8, 0)
	drift(portal, adit_end, true, true, 0, 0.0, 0.0)
	props.append({"type": "entrance", "at": e + Vector3(0, -0.2, 0), "yaw": _yaw(f3), "width": HW * 2.0 + 0.4, "height": HEIGHT + 0.3})
	props.append({"type": "headframe", "at": e - f3 * 7.0 + side * 6.5, "yaw": _yaw(f3)})
	props.append({"type": "spoil", "at": e - f3 * 9.0 - side * 7.0, "radius": 4.5})
	props.append({"type": "tools", "at": e - f3 * 4.5 + side * 2.6, "yaw": _yaw(f3) + 0.4})
	props.append({"type": "cart", "at": e - f3 * 5.0 - side * 2.4, "yaw": _yaw(f3) + 1.2, "tipped": true, "ore": 0})
	surface.add_spawn("lore", e - f3 * 6.0 + side * 3.0 + Vector3(0, 1, 0), {"text": _story()})
	# How deep the first level must sit to keep rock above it.
	var lowest := e.y
	for k in 12:
		var q := Vector2(e.x, e.z) + f * 50.0 + Vector2.from_angle(TAU * k / 12.0) * 55.0
		lowest = minf(lowest, _ground(q.x, q.y))
	var level_y := minf(e.y - 20.0, lowest - 14.0)
	var res := decline(adit_end, f, adit_end.y - level_y, rng.randf_range(0.5, 0.8) * (1.0 if rng.randf() < 0.5 else -1.0))
	var start: Vector3 = res[0]
	var dir: Vector2 = res[1]
	# The workings location spans the levels (the portal location names the adit).
	_lo = Vector3(INF, INF, INF)
	_hi = Vector3(-INF, -INF, -INF)
	for level in levels:
		var deepest := level == levels - 1
		var out := _level(start, dir, level, deepest, guardian)
		if deepest:
			break
		var dres := decline(out[0], out[1], rng.randf_range(17.0, 21.0), rng.randf_range(0.9, 1.25) * (1.0 if level % 2 == 0 else -1.0))
		start = dres[0]
		dir = dres[1]


## One level: main drift, crosscuts to rooms. Returns [end of the main drift, its direction].
func _level(start: Vector3, dir: Vector2, level: int, deepest: bool, guardian: String) -> Array:
	var d3 := Vector3(dir.x, 0, dir.y)
	var side := Vector3(-dir.y, 0, dir.x)
	var length := rng.randf_range(58.0, 72.0)
	var end := start + d3 * length - Vector3(0, length * 0.012, 0)
	drift(start, end, true, true, ore if level > 0 else 0, 0.05)
	# Carts and an ore chute along the haulage way.
	for i in 2:
		var t := rng.randf_range(0.2, 0.85)
		var p := start.lerp(end, t)
		props.append({"type": "cart", "at": p, "yaw": _yaw(d3) + (PI if rng.randf() < 0.5 else 0.0), "tipped": false, "ore": ore if rng.randf() < 0.7 else 0})
		_collide(p, d3)
	var roles: Array = ["stope", "store", "collapse", "stope"]
	if deepest:
		roles = ["stope", "sump", "collapse", "gallery"]
	elif level > 0:
		roles = ["stope", "sump", "store", "stope"]
	for i in roles.size():
		var t := (i + 0.6) / (roles.size() + 0.4)
		var at := start.lerp(end, t)
		var s := 1.0 if i % 2 == 0 else -1.0
		var cross := rng.randf_range(12.0, 18.0)
		var cdir := (side * s + d3 * rng.randf_range(-0.35, 0.35)).normalized()
		var cend := at + cdir * cross
		cend.y = at.y + rng.randf_range(-0.6, 0.4)
		match roles[i]:
			"collapse":
				# The crosscut caved in: rubble and broken sets block it; three metres of
				# fallen rock (dig through it) hide a small rich stope beyond.
				var mid := at.lerp(cend, 0.55)
				drift(at, mid, false, true, 0, 0.0, 0.5)
				props.append({"type": "rubble", "at": mid - cdir * 1.2, "radius": 2.4})
				props.append({"type": "broken_set", "at": mid - cdir * 2.6, "yaw": _yaw(cdir), "width": HW * 2.0 - 0.3, "height": HEIGHT - 0.35, "lagging": true})
				var beyond := mid + cdir * 3.2
				drift(beyond, cend, false, false, rich_ore, 0.3)
				var rc := cend + cdir * 4.0
				room(rc, 3.5, 3.5, 4.0, _yaw(cdir), rich_ore, 0.5)
				depths.add_spawn("chest", rc + Vector3(0, 0.6, 0), {"tier": 2 + int(deepest)})
				props.append({"type": "rubble", "at": beyond + cdir * 0.8, "radius": 1.6})
			"stope":
				drift(at, cend, true, true, ore, 0.12)
				var rc := cend + cdir * 5.0
				room(rc, rng.randf_range(4.0, 5.5), rng.randf_range(5.0, 7.0), rng.randf_range(4.8, 6.0), _yaw(cdir), ore if level == 0 else rich_ore, 0.55)
				props.append({"type": "cart", "at": rc - cdir * 2.0, "yaw": _yaw(cdir) + 0.3, "tipped": rng.randf() < 0.5, "ore": ore})
				_collide(rc - cdir * 2.0, cdir)
				props.append({"type": "tools", "at": rc + side * 2.5, "yaw": rng.randf() * TAU})
				_floors.append([rc, "stope"])
				depths.add_spawn("enemy", rc + Vector3(1.5, 0.4, 0), {"kind": ["skeleton", "giant_spider", "cave_crawler"][(level + i) % 3]})
			"store":
				drift(at, cend, false, true)
				var rc := cend + cdir * 4.0
				room(rc, 4.0, 4.5, 4.2, _yaw(cdir))
				for k in 4:
					var off := side * rng.randf_range(-2.6, 2.6) + cdir * rng.randf_range(-2.0, 2.6)
					props.append({"type": "crate" if k % 2 == 0 else "barrel", "at": rc + off, "yaw": rng.randf() * TAU, "size": rng.randf_range(0.8, 1.1)})
				props.append({"type": "ladder", "at": rc + cdir * 3.6, "yaw": _yaw(cdir) + PI, "height": 3.4})
				depths.add_spawn("chest", rc + cdir * 2.2 + Vector3(0, 0.6, 0), {"tier": 1})
				depths.add_spawn("lore", rc - side * 2.6 + Vector3(0, 1, 0), {"text": _journal(level)})
				depths.add_spawn("enemy", at + d3 * 2.0 + Vector3(0, 0.4, 0), {"kind": "skeleton"})
			"sump":
				# A flooded pit below the drift floor (the water can't reach the drift).
				drift(at, cend, false, true)
				var rc := cend + cdir * 4.5 - Vector3(0, 2.8, 0)
				room(rc, 4.5, 5.0, 6.2, _yaw(cdir), 0, 0.0, rc.y + 1.9)
				props.append({"type": "ladder", "at": cend + cdir * 0.6 - Vector3(0, 2.8, 0), "yaw": _yaw(cdir), "height": 3.2})
				depths.add_spawn("enemy", cend + Vector3(0, 0.4, 0), {"kind": "ghoul"})
			"gallery":
				# The deep gallery: a big chamber where the guardian waits over the best seam.
				drift(at, cend, true, true)
				var rc := cend + cdir * 9.0
				room(rc, 8.5, 10.0, 8.0, _yaw(cdir), rich_ore, 0.45)
				depths.add_spawn("enemy", rc + Vector3(0, 0.5, 0), {"kind": guardian, "guardian": true})
				depths.add_spawn("enemy", rc + side * 5.0 + Vector3(0, 0.4, 0), {"kind": "skeleton"})
				depths.add_spawn("chest", rc + cdir * 6.5 + Vector3(0, 0.6, 0), {"tier": 3})
				for k in 3:
					props.append({"type": "lantern", "at": rc + side * (k - 1) * 4.5 + Vector3(0, 7.2, 0), "lit": k != 1})
				props.append({"type": "cart", "at": rc - cdir * 5.0 + side * 3.0, "yaw": _yaw(side), "tipped": true, "ore": rich_ore})
				_collide(rc - cdir * 5.0 + side * 3.0, side)
				# The miners broke into a natural cave: the way on into the deep.
				var brk := rc + cdir * 9.0 - side * 4.0
				net.add_blob(brk + Vector3(0, 1.8, 0), Vector3(3.4, 2.8, 3.4), 1.0)
				props.append({"type": "rubble", "at": brk - cdir * 2.0, "radius": 1.8})
				CaveNetwork._passage(net, gen, brk, Vector2(cdir.x, cdir.z), rng, 2.4, 3.4, _detail, _ridge)
		_floors.append([cend, String(roles[i])])
	# Monsters patrol the haulage way.
	depths.add_spawn("enemy", start.lerp(end, 0.5) + Vector3(0, 0.4, 0), {"kind": "giant_spider" if level == 0 else "cave_crawler"})
	return [end, dir]


## Carts are solid: invisible STRUCTURE collision under the modelled cart.
func _collide(p: Vector3, along: Vector3) -> void:
	var bp := Blueprint.new(Vector3i(p.floor()) - Vector3i(1, 0, 1), Vector3i(3, 2, 3))
	var a := Vector2(along.x, along.z).normalized()
	for k in [-0.6, 0.0, 0.6]:
		var q := Vector3(p.x + a.x * k, p.y + 0.5, p.z + a.y * k)
		var lp := Vector3i(q.floor()) - bp.origin
		bp.set_local(lp.x, lp.y, lp.z, Blocks.STRUCTURE)
	depths.blueprints.append(bp)


func _story() -> String:
	return "%s. The company worked these galleries for %s until the deep levels broke into the old caves and the crews stopped coming back up. Bring a good pick, light and company." % [surface.name, ["thirty years", "two generations", "a single rich decade", "longer than anyone remembers"][rng.randi() % 4]]


func _journal(level: int) -> String:
	return ["Shift ledger, level %d: seam running rich to the east stopes. Timbering behind. Lamp oil short again." % (level + 1),
			"Foreman's note: the sump floods faster every week. Something moves in the dark water. Nobody works the deep gallery alone.",
			"Crosscut caved in Tuesday. Two men and the good tools behind it. Dig carefully; the roof is still settling.",
			"Last entry: we broke through into a cave older than the mountain. Sealed it. It will not stay sealed."][(level + rng.randi()) % 4]
