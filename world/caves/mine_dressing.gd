class_name MineDressing
extends Node3D
## Modelled props of abandoned mines: timber sets, track, ore carts, lanterns, ladders,
## crates, barrels, collapses, the portal and headframe outside. Reads the layout the
## world generator stores on mine locations (`loc.get_meta(&"mine")["props"]`, world
## coordinates) and builds one node per nearby mine: MultiMesh batches per mesh and
## material, planned on a worker thread. The nearest lit lanterns get one of a small pool
## of real lights. Collision is the generator's business (invisible STRUCTURE blocks).

const BUILD_DISTANCE := 220.0
const FREE_DISTANCE := 280.0
const MAX_LIGHTS := 6
const FADE := 0.45  # instance fade distance / 200 m

enum MM { BEAM, BEAM_BROKEN, ROD, RAIL, CART, HEAP, LANTERN_FRAME, LANTERN_GLASS, CRATE, BARREL, HOOPS, SHEAVE, PICK, SHOVEL, BUCKET, SPOIL, COUNT }
enum MT { WOOD, WOOD_DARK, IRON, RAIL, GLASS, ROCK, COUNT }

static var _meshes: Array[Mesh] = []
static var _mats: Array[ShaderMaterial] = []

var _built := {}       # location id -> Node3D
var _pending := {}     # location id -> [task id, result holder]
var _lanterns := {}    # location id -> Array[Vector3] lit lantern positions
var _lights: Array[OmniLight3D] = []
var _poll := 0.0
var _light_poll := 0.0


static func warmup() -> void:
	if not _meshes.is_empty():
		return
	var m: Array[Mesh] = []
	m.resize(MM.COUNT)
	m[MM.BEAM] = MineMeshes.beam(false)
	m[MM.BEAM_BROKEN] = MineMeshes.beam(true)
	m[MM.ROD] = MineMeshes.rod()
	m[MM.RAIL] = MineMeshes.rail()
	m[MM.CART] = MineMeshes.cart()
	m[MM.HEAP] = MineMeshes.heap()
	m[MM.LANTERN_FRAME] = MineMeshes.lantern_frame()
	m[MM.LANTERN_GLASS] = MineMeshes.lantern_glass()
	m[MM.CRATE] = MineMeshes.crate()
	m[MM.BARREL] = MineMeshes.barrel()
	m[MM.HOOPS] = MineMeshes.barrel_hoops()
	m[MM.SHEAVE] = MineMeshes.sheave()
	m[MM.PICK] = MineMeshes.pick_head()
	m[MM.SHOVEL] = MineMeshes.shovel_blade()
	m[MM.BUCKET] = MineMeshes.bucket()
	m[MM.SPOIL] = MineMeshes.spoil()
	var mats: Array[ShaderMaterial] = []
	mats.resize(MT.COUNT)
	mats[MT.WOOD] = _mat("res://world/caves/mine_wood.gdshader", {})
	mats[MT.WOOD_DARK] = _mat("res://world/caves/mine_wood.gdshader", {"wood_light": Color(0.3, 0.22, 0.15), "wood_dark": Color(0.1, 0.07, 0.05)})
	mats[MT.IRON] = _mat("res://world/caves/mine_metal.gdshader", {"mode": 0})
	mats[MT.RAIL] = _mat("res://world/caves/mine_metal.gdshader", {"mode": 1})
	mats[MT.GLASS] = _mat("res://world/caves/cave_glow.gdshader", {})
	mats[MT.ROCK] = _mat("res://world/caves/cave_rock.gdshader", {"albedo_tex": load("res://world/flora/textures/rock_diff.jpg"),
		"normal_tex": load("res://world/flora/textures/rock_nor.jpg"), "tint": Color(0.5, 0.47, 0.43), "tint2": Color(0.6, 0.55, 0.5), "band_amount": 0.1, "wet_tip": 0.0})
	_mats = mats
	_meshes = m


static func _mat(path: String, params: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(path)
	for k: String in params:
		mat.set_shader_parameter(StringName(k), params[k])
	return mat


func _ready() -> void:
	for i in MAX_LIGHTS:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.66, 0.34)
		l.omni_range = 9.0
		l.omni_attenuation = 1.4
		l.light_energy = 1.5
		l.shadow_enabled = false
		l.light_volumetric_fog_energy = 0.6
		l.visible = false
		add_child(l)
		_lights.append(l)


func _process(delta: float) -> void:
	_collect_finished()
	_poll -= delta
	_light_poll -= delta
	var w := GameWorld.instance
	if w == null or w.local_player == null:
		return
	var pos := w.local_player.global_position
	if _poll <= 0.0:
		_poll = 0.25
		_update_mines(w, pos)
	if _light_poll <= 0.0:
		_light_poll = 0.3
		_update_lights(pos)
	var t := Time.get_ticks_msec() * 0.001
	for i in _lights.size():
		if _lights[i].visible:
			_lights[i].light_energy = 1.5 * (0.9 + 0.06 * sin(t * 7.3 + i * 2.1) + 0.04 * sin(t * 17.0 + i))


func _update_mines(w: GameWorld, pos: Vector3) -> void:
	var near := {}
	var started := false
	if w.local_dimension == 0:
		for loc in w.locations(0):
			if not loc.has_meta(&"mine"):
				continue
			var d := Vector2(loc.center.x - pos.x, loc.center.z - pos.z).length()
			var layout: Dictionary = loc.get_meta(&"mine")
			var reach := float(layout.get("radius", 0.0))
			if d - reach < FREE_DISTANCE:
				near[loc.id] = true
			if d - reach < BUILD_DISTANCE and not _built.has(loc.id) and not _pending.has(loc.id) and not started and DisplayServer.get_name() != "headless":
				started = true
				_start(loc.id, loc.center, layout.get("props", []))
	for id: StringName in _built.keys():
		if not near.has(id):
			(_built[id] as Node).queue_free()
			_built.erase(id)
			_lanterns.erase(id)


func _start(id: StringName, centre: Vector3, props: Array) -> void:
	warmup()
	var holder := [null]
	var task := WorkerThreadPool.add_task(func() -> void: holder[0] = plan(props, centre), true, "mine dressing")
	_pending[id] = [task, holder, centre]


func _collect_finished() -> void:
	for id: StringName in _pending.keys():
		var p: Array = _pending[id]
		if not WorkerThreadPool.is_task_completed(p[0]):
			continue
		WorkerThreadPool.wait_for_task_completion(p[0])
		_pending.erase(id)
		var raw: Variant = p[1][0]
		if not raw is Dictionary or (raw as Dictionary).is_empty():
			continue
		var result: Dictionary = raw
		var node := build_node(result, p[2])
		add_child(node)
		_built[id] = node
		_lanterns[id] = result.get("lanterns", [])


## Main thread: MultiMesh nodes for a plan (relative to `centre`).
static func build_node(result: Dictionary, centre: Vector3) -> Node3D:
	warmup()
	var node := Node3D.new()
	node.name = "Mine"
	node.position = centre
	var batches: Dictionary = result.get("batches", {})
	for key: String in batches:
		var bt: Array = batches[key]
		var parts := key.split(":")
		var mesh: Mesh
		var mat: Material
		if parts[0] == "d":
			mesh = CaveDecor.mesh(int(parts[1]))
			mat = CaveDecor.material(int(parts[2]))
		else:
			mesh = _meshes[int(parts[1])]
			mat = _mats[int(parts[2])]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = int(bt[1])
		mm.buffer = bt[0]
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		var big := parts[0] == "m" and int(parts[1]) in [MM.BEAM, MM.CART, MM.SPOIL]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if big else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)
	return node


func _update_lights(pos: Vector3) -> void:
	var found: Array = []
	for id: StringName in _lanterns:
		var origin: Vector3 = (_built[id] as Node3D).position if _built.has(id) else Vector3.ZERO
		for p: Vector3 in _lanterns[id]:
			var wp := origin + p
			var d := wp.distance_squared_to(pos)
			if d < 40.0 * 40.0:
				found.append([d, wp])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in _lights.size():
		if i < found.size():
			_lights[i].visible = true
			_lights[i].global_position = (found[i][1] as Vector3) + Vector3(0, -0.3, 0)
		else:
			_lights[i].visible = false


# =========================================================================== planning (worker)

class Plan:
	var batches := {}
	var lanterns: Array[Vector3] = []
	var centre := Vector3.ZERO

	func add(key: String, xf: Transform3D, cu: Color) -> void:
		var bt: Array = batches.get(key, [])
		if bt.is_empty():
			bt = [PackedFloat32Array(), 0]
			batches[key] = bt
		var b := xf.basis
		var o := xf.origin - centre
		var buf: PackedFloat32Array = bt[0]
		buf.append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z, cu.r, cu.g, cu.b, cu.a])
		bt[1] = int(bt[1]) + 1

	func mine(mesh: int, mat: int, xf: Transform3D, cu: Color) -> void:
		add("m:%d:%d" % [mesh, mat], xf, cu)

	func decor(mesh: int, mat: int, xf: Transform3D, cu: Color) -> void:
		add("d:%d:%d" % [mesh, mat], xf, cu)


## A member (beam, rod) from a to b with a w x d cross-section; `side` hints the w axis.
static func member(a: Vector3, b: Vector3, w: float, d: float, side := Vector3.RIGHT) -> Transform3D:
	var axis := b - a
	var len := axis.length()
	var y := axis / maxf(len, 0.0001)
	var x := (side - y * side.dot(y))
	if x.length_squared() < 1e-4:
		x = (Vector3.FORWARD - y * Vector3.FORWARD.dot(y))
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Transform3D(Basis(x * w, y * len, z * d), a)


## WORKER THREAD: expand the prop list into instance buffers.
static func plan(props: Array, centre: Vector3) -> Dictionary:
	var pl := Plan.new()
	pl.centre = centre
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(centre)
	for prop: Dictionary in props:
		var at: Vector3 = prop.get("at", Vector3.ZERO)
		var yaw := float(prop.get("yaw", 0.0))
		var rot := Basis(Vector3.UP, yaw)
		var wood := Color(rng.randf_range(0.0, 0.4), rng.randf(), rng.randf_range(0.0, 0.5), FADE)
		match String(prop.get("type", "")):
			"timber_set":
				_timber_set(pl, at, rot, float(prop.get("width", 3.6)), float(prop.get("height", 3.4)), bool(prop.get("lagging", false)), rng)
			"broken_set":
				_broken_set(pl, at, rot, float(prop.get("width", 3.6)), float(prop.get("height", 3.4)), rng)
			"rail":
				_rail(pl, prop.get("a", at), prop.get("b", at), rng)
			"cart":
				_cart(pl, at, rot, bool(prop.get("tipped", false)), int(prop.get("ore", 0)), rng)
			"lantern":
				pl.mine(MM.LANTERN_FRAME, MT.IRON, Transform3D(rot, at), Color(0.3, rng.randf(), 0, FADE))
				var lit := bool(prop.get("lit", true))
				pl.mine(MM.LANTERN_GLASS, MT.GLASS, Transform3D(rot, at), Color(0, rng.randf(), 1.0 if lit else 0.0, FADE))
				pl.mine(MM.ROD, MT.IRON, member(at + Vector3(0, 0.5, 0), at + Vector3(0, 0.02, 0), 0.012, 0.012), Color(0.5, 0, 0, FADE))
				if lit:
					pl.lanterns.append(at - centre)
			"ladder":
				var h := float(prop.get("height", 4.0))
				for s: float in [-0.22, 0.22]:
					var p0 := at + rot * Vector3(s, 0, 0)
					pl.mine(MM.BEAM, MT.WOOD, member(p0, p0 + Vector3(0, h, 0), 0.08, 0.06, rot * Vector3.RIGHT), wood)
				var y := 0.3
				while y < h - 0.1:
					pl.mine(MM.ROD, MT.WOOD, member(at + Vector3(0, y, 0) + rot * Vector3(-0.24, 0, 0), at + Vector3(0, y, 0) + rot * Vector3(0.24, 0, 0), 0.04, 0.04), wood)
					y += 0.32
			"crate":
				var s := float(prop.get("size", 1.0))
				pl.mine(MM.CRATE, MT.WOOD, Transform3D(rot.scaled(Vector3.ONE * s), at), wood)
			"barrel":
				pl.mine(MM.BARREL, MT.WOOD_DARK, Transform3D(rot, at), wood)
				pl.mine(MM.HOOPS, MT.IRON, Transform3D(rot, at), Color(0.6, rng.randf(), 0, FADE))
			"rubble":
				_rubble(pl, at, float(prop.get("radius", 1.5)), rng)
			"entrance":
				_entrance(pl, at, rot, float(prop.get("width", 4.0)), float(prop.get("height", 3.8)), rng)
			"headframe":
				_headframe(pl, at, rot, rng)
			"spoil":
				var r := float(prop.get("radius", 4.0))
				pl.mine(MM.SPOIL, MT.ROCK, Transform3D(rot.scaled(Vector3(r, r * 0.8, r)), at), Color(rng.randf(), rng.randf(), 0.2, FADE))
			"tools":
				_tools(pl, at, rot, rng)
	return {"batches": pl.batches, "lanterns": pl.lanterns}


static func _timber_set(pl: Plan, at: Vector3, rot: Basis, w: float, h: float, lagging: bool, rng: RandomNumberGenerator) -> void:
	var x := rot * Vector3.RIGHT
	var z := rot * Vector3.BACK
	var c := Color(rng.randf_range(0.0, 0.35), rng.randf(), rng.randf_range(0.1, 0.6), FADE)
	for s: float in [-1.0, 1.0]:
		var foot := at + x * s * (w * 0.5 - 0.18) - Vector3(0, 0.15, 0)
		var head := at + x * s * (w * 0.5 - 0.3) + Vector3(0, h - 0.15, 0)
		pl.mine(MM.BEAM, MT.WOOD, member(foot, head, 0.27, 0.27, z), c)
	var cap_y := at.y + h
	pl.mine(MM.BEAM, MT.WOOD, member(at + x * (-w * 0.5 - 0.15) + Vector3(0, h, 0), at + x * (w * 0.5 + 0.15) + Vector3(0, h, 0), 0.3, 0.3, Vector3.UP), c)
	if lagging:
		for k in 6:
			var off := lerpf(-w * 0.45, w * 0.45, float(k) / 5.0)
			var p := at + x * off + Vector3(0, h + 0.19, 0)
			pl.mine(MM.BEAM, MT.WOOD_DARK, member(p - z * 0.85, p + z * 0.85 + z * rng.randf_range(-0.15, 0.15), 0.22, 0.05, x), Color(rng.randf_range(0.1, 0.5), rng.randf(), 0.5, FADE))
	# Wedges between the cap and the posts.
	for s: float in [-1.0, 1.0]:
		var p := at + x * s * (w * 0.5 - 0.3) + Vector3(0, h - 0.2, 0) + z * 0.15
		pl.mine(MM.BEAM, MT.WOOD_DARK, member(p, p + Vector3(0, 0.1, 0), 0.12, 0.06, x), c)
	var _unused := cap_y


static func _broken_set(pl: Plan, at: Vector3, rot: Basis, w: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := rot * Vector3.RIGHT
	var z := rot * Vector3.BACK
	var c := Color(rng.randf_range(0.2, 0.5), rng.randf(), 0.6, FADE)
	var stand := at - x * (w * 0.5 - 0.2)
	pl.mine(MM.BEAM, MT.WOOD, member(stand - Vector3(0, 0.15, 0), stand + Vector3(0, h - 0.15, 0), 0.27, 0.27, z), c)
	# The other post kicked out and leaning.
	var foot := at + x * (w * 0.5 - 0.1) + z * 0.6
	pl.mine(MM.BEAM_BROKEN, MT.WOOD, member(foot - Vector3(0, 0.1, 0), foot + Vector3(0, h * 0.7, 0) - x * 0.9 + z * 0.3, 0.26, 0.26, z), c)
	# The cap snapped: one half still on the post, one fallen to the floor.
	pl.mine(MM.BEAM_BROKEN, MT.WOOD, member(stand + Vector3(0, h, 0), stand + Vector3(0, h - 0.5, 0) + x * w * 0.55, 0.3, 0.3, Vector3.UP), c)
	pl.mine(MM.BEAM_BROKEN, MT.WOOD, member(at + x * (w * 0.5) + Vector3(0, 0.1, 0) - z * 0.4, at + x * 0.1 + Vector3(0, 0.9, 0) + z * 0.3, 0.3, 0.3, Vector3.UP), c)
	_rubble(pl, at + x * 0.6 + z * 0.3, 1.2, rng)


static func _rail(pl: Plan, a: Vector3, b: Vector3, rng: RandomNumberGenerator) -> void:
	var d := b - a
	var flat := Vector3(d.x, 0, d.z)
	if flat.length() < 0.05:
		return
	var side := flat.normalized().cross(Vector3.UP).normalized()
	for s: float in [-0.45, 0.45]:
		var p0 := a + side * s + Vector3(0, 0.1, 0)
		var p1 := b + side * s + Vector3(0, 0.1, 0)
		# The rail mesh runs along +Z: build a basis with z along the track.
		var zt := p1 - p0
		var y := zt.cross(side).normalized()
		if y.y < 0.0:
			y = -y
		var bx := side if side.cross(y).dot(zt) > 0.0 else -side
		pl.mine(MM.RAIL, MT.RAIL, Transform3D(Basis(bx, y, zt), p0), Color(rng.randf_range(0.0, 0.3), rng.randf(), 0, FADE))
	var n := maxi(1, int(d.length() / 0.65))
	for k in n:
		var t := (float(k) + 0.5) / n
		var p := a.lerp(b, t) + Vector3(0, 0.02, 0)
		var wob := flat.normalized() * rng.randf_range(-0.05, 0.05)
		pl.mine(MM.BEAM, MT.WOOD_DARK, member(p - side * 0.75 + wob, p + side * 0.75 - wob, 0.2, 0.12, flat.normalized()),
			Color(rng.randf_range(0.2, 0.6), rng.randf(), rng.randf_range(0.3, 0.8), FADE))


static func _cart(pl: Plan, at: Vector3, rot: Basis, tipped: bool, ore: int, rng: RandomNumberGenerator) -> void:
	var b := rot
	var o := at
	if tipped:
		b = rot * Basis(Vector3.BACK, 1.45)
		o = at + rot * Vector3(0.6, 0.48, 0)
	var c := Color(rng.randf_range(0.0, 0.5), rng.randf(), 0, FADE)
	pl.mine(MM.CART, MT.IRON, Transform3D(b, o), c)
	var ore_entry: Variant = CaveDecor.ORES.get(ore)
	if ore_entry != null:
		var mat: int = (ore_entry as Array)[2]
		if tipped:
			# The spilled load across the floor.
			for k in 4:
				var p := at + rot * Vector3(-0.4 - k * 0.35, 0.0, rng.randf_range(-0.5, 0.5))
				pl.decor(CaveDecor.M.NODULES + (k & 1), mat, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.2, 2.0)), p), Color(rng.randf(), rng.randf(), 0.8, FADE))
		else:
			pl.mine(MM.HEAP, MT.ROCK, Transform3D(b, o), Color(0.5, rng.randf(), 0.3, FADE))
			for k in 3:
				var p := o + rot * Vector3(rng.randf_range(-0.2, 0.2), 0.98, rng.randf_range(-0.35, 0.35))
				pl.decor(CaveDecor.M.NODULES + (k & 1), mat, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 1.3)), p), Color(rng.randf(), rng.randf(), 0.8, FADE))


static func _rubble(pl: Plan, at: Vector3, radius: float, rng: RandomNumberGenerator) -> void:
	var rock := CaveDecor.T.R_KARST
	for k in 3 + int(radius * 1.5):
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * radius * 0.8
		var s := rng.randf_range(0.6, 1.2) * maxf(1.0, radius * 0.7) * (1.6 if k == 0 else 1.0)
		var p := at + Vector3(cos(a) * d, -0.05, sin(a) * d)
		pl.decor(CaveDecor.M.RUBBLE + (k & 1), rock, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.6, 1.0), s)), p),
			Color(rng.randf(), rng.randf(), rng.randf_range(0.0, 0.3), FADE))
	for k in 2:
		var a := rng.randf() * TAU
		var p := at + Vector3(cos(a), 0, sin(a)) * radius * 0.4
		var q := p + Vector3(cos(a + 1.7), rng.randf_range(0.2, 0.9), sin(a + 1.7)) * rng.randf_range(1.0, 2.0)
		pl.mine(MM.BEAM_BROKEN, MT.WOOD, member(p, q, 0.24, 0.24, Vector3.UP), Color(rng.randf_range(0.3, 0.6), rng.randf(), 0.6, FADE))


static func _entrance(pl: Plan, at: Vector3, rot: Basis, w: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := rot * Vector3.RIGHT
	var z := rot * Vector3.BACK
	var c := Color(0.15, rng.randf(), 0.35, FADE)
	for s: float in [-1.0, 1.0]:
		var foot := at + x * s * (w * 0.5 + 0.1) - Vector3(0, 0.3, 0)
		pl.mine(MM.BEAM, MT.WOOD, member(foot, foot + Vector3(0, h + 0.6, 0), 0.42, 0.42, z), c)
		# Raking braces.
		pl.mine(MM.BEAM, MT.WOOD, member(foot + x * s * 0.9 - z * 0.3, foot + Vector3(0, h * 0.75, 0) + x * s * 0.1, 0.2, 0.2, z), c)
	var top := at + Vector3(0, h + 0.15, 0)
	pl.mine(MM.BEAM, MT.WOOD, member(top - x * (w * 0.5 + 0.9), top + x * (w * 0.5 + 0.9), 0.45, 0.45, Vector3.UP), c)
	pl.mine(MM.BEAM, MT.WOOD_DARK, member(top + Vector3(0, 0.35, 0) - x * (w * 0.5 + 0.5), top + Vector3(0, 0.35, 0) + x * (w * 0.5 + 0.5), 0.3, 0.3, Vector3.UP), c)
	# Weathered sign hanging from the lintel on two chains.
	var sign_c := top - z * 0.35 - Vector3(0, 0.75, 0)
	pl.mine(MM.BEAM, MT.WOOD_DARK, member(sign_c - x * 0.85, sign_c + x * 0.85, 0.48, 0.05, Vector3.UP), Color(0.3, rng.randf(), 0.2, FADE))
	for s: float in [-0.65, 0.65]:
		pl.mine(MM.ROD, MT.IRON, member(sign_c + x * s + Vector3(0, 0.22, 0), top - z * 0.35 + x * s - Vector3(0, 0.15, 0), 0.015, 0.015), Color(0.7, 0, 0, FADE))
	# A lantern on a bracket beside the portal.
	var lp := at + x * (w * 0.5 + 0.45) + Vector3(0, h - 0.4, 0) - z * 0.35
	pl.mine(MM.ROD, MT.IRON, member(lp + Vector3(0, 0.05, 0), lp + Vector3(0, 0.05, 0) - x * 0.4 + z * 0.1, 0.02, 0.02), Color(0.6, 0, 0, FADE))
	pl.mine(MM.LANTERN_FRAME, MT.IRON, Transform3D(rot, lp), Color(0.4, 0.3, 0, FADE))
	pl.mine(MM.LANTERN_GLASS, MT.GLASS, Transform3D(rot, lp), Color(0, 0.3, 1.0, FADE))
	pl.lanterns.append(lp - pl.centre)


static func _headframe(pl: Plan, at: Vector3, rot: Basis, rng: RandomNumberGenerator) -> void:
	var x := rot * Vector3.RIGHT
	var z := rot * Vector3.BACK
	var c := Color(0.2, rng.randf(), 0.25, FADE)
	var top := at + Vector3(0, 5.8, 0)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var foot := at + x * sx * 1.5 + z * sz * 1.3 - Vector3(0, 0.3, 0)
			pl.mine(MM.BEAM, MT.WOOD, member(foot, top + x * sx * 0.45, 0.28, 0.28, z), c)
	for hgt: float in [1.6, 3.4]:
		var f := hgt / 6.1
		for sx: float in [-1.0, 1.0]:
			var a := at.lerp(top, f) + x * sx * lerpf(1.5, 0.45, f) - z * lerpf(1.3, 0.0, f)
			var b := at.lerp(top, f) + x * sx * lerpf(1.5, 0.45, f) + z * lerpf(1.3, 0.0, f)
			pl.mine(MM.BEAM, MT.WOOD_DARK, member(a, b, 0.16, 0.16, Vector3.UP), c)
		var l := at.lerp(top, f) - x * lerpf(1.5, 0.45, f)
		var r := at.lerp(top, f) + x * lerpf(1.5, 0.45, f)
		pl.mine(MM.BEAM, MT.WOOD_DARK, member(l - z * lerpf(1.3, 0.0, f), r - z * lerpf(1.3, 0.0, f), 0.16, 0.16, Vector3.UP), c)
	pl.mine(MM.BEAM, MT.WOOD, member(top - x * 0.75, top + x * 0.75, 0.3, 0.3, Vector3.UP), c)
	var wheel := top + Vector3(0, 0.95, 0)
	pl.mine(MM.SHEAVE, MT.IRON, Transform3D(rot, wheel), Color(0.5, rng.randf(), 0, FADE))
	# Hoist rope down to the ground and off to the winding drum.
	pl.mine(MM.ROD, MT.WOOD_DARK, member(wheel + x * 0.9, wheel + x * 0.9 + Vector3(0, -5.4, 0), 0.025, 0.025), Color(0.6, 0.5, 0.2, FADE))
	pl.mine(MM.ROD, MT.WOOD_DARK, member(wheel - x * 0.9 + Vector3(0, 0.1, 0), at - x * 6.0 + Vector3(0, 0.6, 0), 0.025, 0.025), Color(0.6, 0.5, 0.2, FADE))
	pl.mine(MM.BARREL, MT.WOOD_DARK, Transform3D(Basis(rot * Vector3.BACK, PI * 0.5) * rot, at - x * 6.3 + Vector3(0, 0.6, 0) - z * 0.45), Color(0.3, rng.randf(), 0.3, FADE))


static func _tools(pl: Plan, at: Vector3, rot: Basis, rng: RandomNumberGenerator) -> void:
	var x := rot * Vector3.RIGHT
	var z := rot * Vector3.BACK
	var c := Color(0.2, rng.randf(), 0.4, FADE)
	# A pick leaning against the wall (behind = -z).
	var foot := at + x * 0.2
	var head := foot + Vector3(0, 0.85, 0) - z * 0.35
	pl.mine(MM.ROD, MT.WOOD, member(foot, head, 0.045, 0.045), c)
	pl.mine(MM.PICK, MT.IRON, Transform3D(Basis(x, (head - foot).normalized(), z).orthonormalized(), head), Color(0.5, rng.randf(), 0, FADE))
	# A shovel beside it, blade down.
	var sf := at - x * 0.35
	var st := sf + Vector3(0, 1.0, 0) - z * 0.3
	pl.mine(MM.ROD, MT.WOOD, member(sf + Vector3(0, 0.3, 0), st, 0.04, 0.04), c)
	pl.mine(MM.SHOVEL, MT.IRON, Transform3D(Basis(x, (st - sf).normalized(), z).orthonormalized(), sf + Vector3(0, 0.33, 0) - z * 0.0), Color(0.6, rng.randf(), 0, FADE))
	# And a bucket.
	pl.mine(MM.BUCKET, MT.WOOD_DARK, Transform3D(rot, at + x * 0.85 + z * 0.3), c)
