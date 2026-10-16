class_name CharBody
extends RefCounted
## Builds (and caches) the smooth skinned body mesh of a humanoid style:
## anatomy, garments, armour, headwear and the cloak's simulation bones.
## Colours are not baked in: every instance sets its palette through instance
## uniforms (see character.gdshader), so all villagers with the same shape share
## one mesh and one material.
##
##   var body := CharBody.get_body(style)   # cached by shape
##   body.mesh, body.skin, body.rest (global bind positions of every bone), body.parents ...

const R := preload("res://models/character/char_rig.gd")
const SHADER := preload("res://models/character/character.gdshader")

## Keys that change geometry (everything else - colours, held items - is per instance).
const SHAPE_KEYS := ["bulk", "female", "gaunt", "muscle", "belly", "arm_length", "head_scale", "jaw", "brow", "nose",
	"cheeks", "ears", "hair_style", "hair", "beard", "hood", "cloak", "cape", "cloak_length", "robe", "apron", "hat",
	"helmet", "horns", "horn_style", "tusks", "crown", "eyes", "skeleton", "decay", "tattered", "rags", "sleeves",
	"tunic_length", "footwear", "gloves", "bracers", "greaves", "chainmail", "plate", "pauldrons", "tabard", "shield",
	"plume", "belt", "sash", "cloth", "vest", "collar"]

static var _cache := {}
static var _material: ShaderMaterial
## Set true to print a per-section build time breakdown.
static var profile := false
## Generate meshes on worker threads when a model allows it (the game does).
static var async_build := true
static var _pending := {}
static var _pt := 0


static func _lap(label: String) -> void:
	if profile:
		var now := Time.get_ticks_usec()
		print("    %-10s %6.1f ms" % [label, (now - _pt) / 1000.0])
		_pt = now

# Torso profile: y, half width, front depth, back depth, superellipse power.
const TORSO := [
	[0.8, 0.075, 0.055, 0.06, 2.0],
	[0.85, 0.135, 0.085, 0.095, 2.0],
	[0.91, 0.163, 0.095, 0.113, 2.1],
	[0.97, 0.172, 0.098, 0.118, 2.1],
	[1.03, 0.166, 0.097, 0.108, 2.1],
	[1.09, 0.156, 0.098, 0.098, 2.1],
	[1.16, 0.162, 0.106, 0.097, 2.2],
	[1.24, 0.177, 0.118, 0.1, 2.3],
	[1.31, 0.189, 0.126, 0.105, 2.4],
	[1.37, 0.197, 0.122, 0.11, 2.4],
	[1.42, 0.199, 0.108, 0.106, 2.4],
	[1.46, 0.186, 0.092, 0.092, 2.3],
	[1.49, 0.13, 0.07, 0.075, 2.0],
	[1.515, 0.075, 0.058, 0.058, 2.0],
]


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	return _material


static func shape_key(st: Dictionary) -> String:
	var parts := PackedStringArray()
	for k: String in SHAPE_KEYS:
		if not st.has(k):
			continue
		var v: Variant = st[k]
		if v is Color:
			parts.append(k + "=c")
		elif v is float:
			parts.append(k + "=%.2f" % (snappedf(v, 0.04) if k == "bulk" else v))
		elif v == null or (v is bool and v == false):
			continue
		else:
			parts.append(k + "=" + str(v))
	return ";".join(parts)


## Body for a style, built synchronously if needed (tools, tests).
static func get_body(st: Dictionary) -> Dictionary:
	var b := body_for(st, false)
	poll(b)
	if b.get("mesh") == null and _pending.has(b["key"]):
		WorkerThreadPool.wait_for_task_completion(int(_pending[b["key"]]["task"]))
		poll(b)
	return b


## Body for a style. The rig (bones, skin binds) is available at once; with
## allow_async the mesh is generated on a worker thread - call poll() until it
## returns true, then use body["mesh"].
static func body_for(st: Dictionary, allow_async: bool) -> Dictionary:
	var key := shape_key(st)
	var b: Dictionary = _cache.get(key, {})
	if b.is_empty():
		b = _rig(st)
		b["key"] = key
		_cache[key] = b
		var cloak_first: int = b["cloak_first"]
		if allow_async and async_build:
			var out := {}
			var st_copy := st.duplicate()
			var task := WorkerThreadPool.add_task(func() -> void: out.merge(build_data(st_copy, cloak_first)), false, "character mesh")
			_pending[key] = {"task": task, "out": out}
		else:
			var t0 := Time.get_ticks_usec()
			_finish(b, build_data(st, cloak_first))
			b["build_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	return b


## True once the body's mesh exists (finishes a completed background build).
static func poll(b: Dictionary) -> bool:
	if b.get("mesh") != null:
		return true
	var key: String = b.get("key", "")
	var p: Variant = _pending.get(key)
	if p == null:
		return false
	var task: int = p["task"]
	if not WorkerThreadPool.is_task_completed(task):
		return false
	WorkerThreadPool.wait_for_task_completion(task)
	_pending.erase(key)
	_finish(b, p["out"])
	return true


static func cached_count() -> int:
	return _cache.size()


## Build (synchronously) shapes every session needs, e.g. on a loading screen.
static func warmup(styles: Array) -> void:
	for st: Dictionary in styles:
		get_body(st)


static func _rig(st: Dictionary) -> Dictionary:
	var pr := R.proportions(st)
	var rest := R.rest_positions(pr)
	var parents := PackedInt32Array(R.PARENTS)
	var names := PackedStringArray(R.NAMES)
	var all_rest := PackedVector3Array(rest)
	var cloak_first := -1
	var cloak_rest := PackedVector3Array()
	if st.get("cloak", false) or st.get("cape", false):
		cloak_first = all_rest.size()
		for r in R.CLOAK_ROWS:
			for c in R.CLOAK_COLS:
				cloak_rest.append(cloak_point(float(c) / (R.CLOAK_COLS - 1), float(r) / (R.CLOAK_ROWS - 1), st, pr))
		for i in cloak_rest.size():
			all_rest.append(cloak_rest[i])
			parents.append(-1)
			names.append("cloak_%d" % i)
	var skin := Skin.new()
	for i in all_rest.size():
		skin.add_bind(i, Transform3D(Basis.IDENTITY, -all_rest[i]))
	var local := PackedVector3Array()
	local.resize(all_rest.size())
	for i in all_rest.size():
		local[i] = all_rest[i] - (all_rest[parents[i]] if parents[i] >= 0 else Vector3.ZERO)
	var hp := CharHead.params(st, pr)
	var hc: Vector3 = hp["c"]
	var hr: Vector3 = hp["r"]
	return {
		"mesh": null, "skin": skin, "rest": all_rest, "local": local, "parents": parents, "names": names,
		"glow_roles": [], "cloak_first": cloak_first, "cloak_rest": cloak_rest, "pr": pr,
		"head_top": hc + Vector3(0, hr.y + 0.02, 0), "tris": 0, "verts": 0, "build_ms": 0.0,
	}


static func _finish(b: Dictionary, data: Dictionary) -> void:
	var mesh := ArrayMesh.new()
	var surfaces: Array = data["surfaces"]
	for i in surfaces.size():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces[i], [], {}, CharGeo.FORMAT_FLAGS)
	mesh.surface_set_material(0, material())
	b["glow_roles"] = data["roles"]
	b["tris"] = data["tris"]
	b["verts"] = data["verts"]
	b["info"] = data["info"]
	b["mesh"] = mesh


# --- Profiles ------------------------------------------------------------------------

static func _bump(y: float, c: float, w: float) -> float:
	var d := (y - c) / w
	return exp(-d * d)


## Torso cross-section at height y (body units) for these proportions.
static func torso_ring(y: float, pr: Dictionary) -> Vector4:
	var a: Array = TORSO[0]
	var b: Array = TORSO[TORSO.size() - 1]
	var r := Vector4(a[1], a[2], a[3], a[4])
	if y >= float(b[0]):
		r = Vector4(b[1], b[2], b[3], b[4])
	else:
		for i in range(TORSO.size() - 1):
			var p: Array = TORSO[i]
			var q: Array = TORSO[i + 1]
			if y >= float(p[0]) and y <= float(q[0]):
				var f := (y - float(p[0])) / (float(q[0]) - float(p[0]))
				f = f * f * (3.0 - 2.0 * f)
				r = Vector4(lerpf(p[1], q[1], f), lerpf(p[2], q[2], f), lerpf(p[3], q[3], f), lerpf(p[4], q[4], f))
				break
	var bulk: float = pr["bulk"]
	var fem: float = pr["fem"]
	var m: float = pr["muscle"]
	var belly: float = pr["belly"]
	r.x *= bulk
	r.y *= lerpf(1.0, bulk, 0.75)
	r.z *= lerpf(1.0, bulk, 0.75)
	if fem > 0.0:
		r.x *= 1.0 + 0.07 * _bump(y, 0.95, 0.06) - 0.1 * _bump(y, 1.1, 0.05) - 0.08 * smoothstep(1.34, 1.42, y)
		r.z *= 1.0 + 0.06 * _bump(y, 0.95, 0.06)
		r.y += 0.022 * _bump(y, 1.3, 0.045)
	if m > 0.0:
		var up := smoothstep(1.2, 1.3, y) * (1.0 - smoothstep(1.46, 1.5, y))
		r.x *= 1.0 + 0.1 * m * up
		r.y += 0.016 * m * up
		r.z += 0.014 * m * up
	if belly > 0.0:
		var bb := _bump(y, 1.12, 0.09)
		r.y += 0.08 * belly * bb
		r.x += 0.035 * belly * bb
	if pr["gaunt"]:
		var w := _bump(y, 1.12, 0.09)
		r.x *= 1.0 - 0.12 * w
		r.y *= 1.0 - 0.15 * w
	return r


static func _torso_w(y: float) -> Vector3:
	if y < 1.0:
		return Vector3(R.HIPS, R.SPINE, 0.0)
	if y < 1.14:
		return Vector3(R.HIPS, R.SPINE, smoothstep(1.0, 1.14, y))
	if y < 1.28:
		return Vector3(R.SPINE, R.CHEST, smoothstep(1.14, 1.28, y))
	if y < 1.47:
		return Vector3(R.CHEST, R.NECK, 0.0)
	return Vector3(R.CHEST, R.NECK, 0.3 * smoothstep(1.47, 1.515, y))


static func _shoulder_reweight(g: CharGeo, from: int, b: float) -> void:
	g.reweight(from, g.vertex_count(), func(p: Vector3) -> Variant:
		var ax := absf(p.x)
		if p.y < 1.3 or ax < 0.1:
			return null
		var f := smoothstep(0.1, 0.2 * b, ax) * smoothstep(1.3, 1.42, p.y)
		var side := 0 if p.x < 0.0 else 5
		var tw := _torso_w(p.y)
		return [[int(tw.x), int(tw.y), R.CLAV_L + side, R.UARM_L + side], [(1.0 - tw.z) * (1.0 - f), tw.z * (1.0 - f), f * 0.75, f * 0.25]])


# --- Build ---------------------------------------------------------------------------

## Thread-safe: all geometry for a style as surface arrays (no resources, no scene).
static func build_data(st: Dictionary, cloak_first: int) -> Dictionary:
	var pr := R.proportions(st)
	var rest := R.rest_positions(pr)
	var g := CharGeo.new()
	var glow := {}
	var info := {}
	var skeleton: bool = pr["skeleton"]
	_pt = Time.get_ticks_usec()
	if skeleton:
		CharBones.body(g, st, pr, rest)
		if st.get("cloth", null) != null or st.get("rags", false):
			_rags(g, st, pr)
		_lap("bones")
	else:
		_torso(g, st, pr, rest)
		_lap("torso")
		_arms(g, st, pr, rest)
		_lap("arms")
		_legs(g, st, pr, rest)
		_lap("legs")
		_garments(g, st, pr, rest)
		_lap("garments")
	info.merge(CharHead.build(g, glow, st, pr))
	_lap("head")
	_armour(g, st, pr, rest)
	_lap("armour")
	if cloak_first >= 0:
		_cloak(g, st, pr, cloak_first)
	_lap("cloak")
	var surfaces := [g.to_arrays()]
	_lap("normals")
	var roles: Array[String] = []
	var tris := g.tri_count()
	for key: String in glow:
		var gg: CharGeo = glow[key]
		if gg.tri_count() == 0:
			continue
		surfaces.append(gg.to_arrays())
		roles.append(key)
		tris += gg.tri_count()
	return {"surfaces": surfaces, "roles": roles, "tris": tris, "verts": g.vertex_count(), "info": info}


static func _shirt_mat(st: Dictionary) -> Array:
	if st.get("chainmail", false):
		return [CharGeo.METAL, CharGeo.M_MAIL]
	var shirt := str(st.get("shirt", ""))
	if shirt == "none":
		return [CharGeo.SKIN, CharGeo.M_DECAY if float(st.get("decay", 0.0)) > 0.0 else CharGeo.M_SKIN]
	return [CharGeo.CLOTH, CharGeo.M_CLOTH]


static func _torso(g: CharGeo, st: Dictionary, pr: Dictionary, rest: PackedVector3Array) -> void:
	var sm := _shirt_mat(st)
	var ys := [0.8, 0.85, 0.91, 0.97, 1.0, 1.03, 1.09, 1.16, 1.24, 1.31, 1.37, 1.42, 1.46, 1.49, 1.515]
	var pts := PackedVector3Array()
	var rings: Array = []
	var ws: Array = []
	var mats: Array = []
	g.mat(CharGeo.TROUSERS, CharGeo.M_CLOTH)
	var trousers_c := Color(CharGeo.TROUSERS / 255.0, CharGeo.M_CLOTH / 255.0, 0.5, 1.0)
	var shirt_c := Color(int(sm[0]) / 255.0, int(sm[1]) / 255.0, 0.5, 1.0)
	for y: float in ys:
		var zc := 0.008 * smoothstep(1.2, 1.4, y) - 0.006 * _bump(y, 0.95, 0.08)
		pts.append(Vector3(0, y, zc))
		rings.append(torso_ring(y, pr))
		ws.append(_torso_w(y))
		mats.append(trousers_c if y < 1.0 else shirt_c)
	var v0 := g.vertex_count()
	g.tube(pts, rings, 28, ws, 2, 1, Vector3.RIGHT, Vector3.FORWARD, 0.0, 1.0, mats)
	_shoulder_reweight(g, v0, pr["bulk"])
	# Folds: darken under the chest, at the waist and the small of the back.
	g.reshade(v0, g.vertex_count(), func(p: Vector3) -> Variant:
		var crease := _bump(p.y, 1.06, 0.03) * 0.25 + (_bump(p.y, 1.22, 0.025) * 0.15 if p.z < 0.0 else 0.0)
		return Vector2(1.0 - crease, 1.0 - crease))
	var _u := rest


static func _arms(g: CharGeo, st: Dictionary, pr: Dictionary, rest: PackedVector3Array, closeup := false) -> void:
	var b: float = pr["bulk"]
	var lm: float = pr["limb"]
	var m: float = pr["muscle"]
	var k := lm * pow(b, 0.8) * (1.0 + 0.22 * m)
	var sleeves := str(st.get("sleeves", "long"))
	var robe: bool = st.get("robe", false)
	var sm := _shirt_mat(st)
	var skin_t := CharGeo.M_DECAY if float(st.get("decay", 0.0)) > 0.0 else CharGeo.M_SKIN
	var sleeve_c := Color(int(sm[0]) / 255.0, int(sm[1]) / 255.0, 0.5, 1.0)
	var skin_c := Color(CharGeo.SKIN / 255.0, skin_t / 255.0, 0.5, 1.0)
	var glove_c := Color(CharGeo.LEATHER / 255.0, CharGeo.M_LEATHER / 255.0, 0.5, 1.0)
	var bracer_c := Color(CharGeo.METAL / 255.0, CharGeo.M_METAL / 255.0, 0.5, 1.0) if str(st.get("bracers", "")) == "metal" else glove_c
	if st.get("chainmail", false) and sleeves == "long":
		sleeves = "elbow"
	for side in 2:
		var sg := -1.0 if side == 0 else 1.0
		var o := 0 if side == 0 else 5
		var sh := rest[R.UARM_L + o]
		var el := rest[R.FARM_L + o]
		var wr := rest[R.HAND_L + o]
		var pts := PackedVector3Array([sh + Vector3(-sg * 0.035, 0.012, 0.0), sh + Vector3(sg * 0.002, -0.035, 0.0), sh.lerp(el, 0.45), el,
			el.lerp(wr, 0.35), el.lerp(wr, 0.85), wr + (wr - el).normalized() * 0.008])
		var rings: Array = [Vector4(0.04, 0.042, 0.042, 2.0) * k, Vector4(0.053, 0.052, 0.054, 2.0) * k, Vector4(0.049, 0.05, 0.051, 2.0) * k,
			Vector4(0.041, 0.04, 0.043, 2.0) * k, Vector4(0.044, 0.043, 0.042, 2.0) * k, Vector4(0.032, 0.03, 0.03, 2.0) * k, Vector4(0.029, 0.026, 0.026, 2.0) * k]
		var ws: Array = [Vector3(R.CLAV_L + o, R.UARM_L + o, 0.55), Vector3(R.UARM_L + o, R.CLAV_L + o, 0.15), Vector3(R.UARM_L + o, R.FARM_L + o, 0.0),
			Vector3(R.UARM_L + o, R.FARM_L + o, 0.5), Vector3(R.FARM_L + o, R.UARM_L + o, 0.0), Vector3(R.FARM_L + o, R.HAND_L + o, 0.0), Vector3(R.FARM_L + o, R.HAND_L + o, 0.35)]
		var mats: Array = []
		for i in pts.size():
			var c := sleeve_c
			match sleeves:
				"short":
					c = sleeve_c if i <= 2 else skin_c
				"elbow":
					c = sleeve_c if i <= 3 else skin_c
				"none":
					c = skin_c if i >= 1 else sleeve_c
			if st.get("gloves", false) and i >= 5:
				c = glove_c
			if st.get("bracers", false) and i >= 4 and i <= 5:
				c = bracer_c
			mats.append(c)
		# Cuffs: a slightly wider ring where a sleeve ends.
		if sleeves == "long" and not st.get("gloves", false):
			rings[5] = rings[5] * 1.18
			if robe:
				rings[5] = Vector4(0.06, 0.055, 0.065, 2.0) * k
				rings[6] = Vector4(0.072, 0.07, 0.075, 2.0) * k
		g.mat(CharGeo.SKIN, skin_t)
		g.tube(pts, rings, 20 if closeup else 14, ws, 1, 0, Vector3.FORWARD, Vector3.FORWARD, 0.0, 1.0, mats)
		_hand(g, st, pr, rest, side, skin_t, closeup)


static func _hand(g: CharGeo, st: Dictionary, pr: Dictionary, rest: PackedVector3Array, side: int, skin_t: int, closeup := false) -> void:
	var sg := -1.0 if side == 0 else 1.0
	var o := 0 if side == 0 else 5
	var w := rest[R.HAND_L + o]
	var hs := float(st.get("hands", 1.0)) * sqrt(float(pr["bulk"])) * lerpf(1.0, 0.9, float(pr["fem"]))
	if st.get("gloves", false):
		g.mat(CharGeo.LEATHER, CharGeo.M_LEATHER)
	else:
		g.mat(CharGeo.SKIN, skin_t)
	# Palm (faces the thigh), slightly cupped.
	var v0 := g.vertex_count()
	g.bone(R.HAND_L + o)
	g.ellipsoid(w + Vector3(-sg * 0.002, -0.048 * hs, -0.003), Vector3(0.017, 0.048, 0.04) * hs,
		14 if closeup else 10, 20 if closeup else 14, Basis.IDENTITY, 2.0 if closeup else 2.4)
	g.reweight(v0, g.vertex_count(), func(p: Vector3) -> Variant:
		var f := smoothstep(w.y - 0.06 * hs, w.y - 0.095 * hs, p.y)
		return [[R.HAND_L + o, R.FING_L + o], [1.0 - f * 0.5, f * 0.5]])
	# Fingers.
	var lens := [0.074, 0.084, 0.079, 0.063]
	for f in 4:
		var z := lerpf(-0.028, 0.027, f / 3.0) * hs
		var base := w + Vector3(-sg * 0.001, -0.086 * hs, z)
		var l: float = lens[f] * hs
		var rad := (0.0092 - f * 0.0006) * hs
		var pts := PackedVector3Array([base + Vector3(0, 0.012, 0), base, base + Vector3(-sg * 0.004, -l * 0.45, 0), base + Vector3(-sg * 0.011, -l * 0.8, 0), base + Vector3(-sg * 0.016, -l, 0)])
		g.tube(pts, [Vector4(rad, rad, rad, 2.0), Vector4(rad, rad * 0.9, rad, 2.0), Vector4(rad * 0.92, rad * 0.85, rad * 0.9, 2.0), Vector4(rad * 0.85, rad * 0.8, rad * 0.8, 2.0), Vector4(rad * 0.75, rad * 0.7, rad * 0.7, 2.0)],
			12 if closeup else 7, [Vector3(R.HAND_L + o, R.FING_L + o, 0.3), Vector3(R.FING_L + o, R.HAND_L + o, 0.25), Vector3(R.FING_L + o, R.HAND_L + o, 0.0),
				Vector3(R.FING_L + o, R.HAND_L + o, 0.0), Vector3(R.FING_L + o, R.HAND_L + o, 0.0)], 0, 2)
	# Thumb.
	g.bone(R.HAND_L + o)
	var tb := w + Vector3(-sg * 0.008, -0.03 * hs, -0.03 * hs)
	g.tube(PackedVector3Array([tb, tb + Vector3(-sg * 0.012, -0.028, -0.014) * hs, tb + Vector3(-sg * 0.022, -0.052, -0.02) * hs, tb + Vector3(-sg * 0.026, -0.07, -0.02) * hs]),
		[Vector4(0.014, 0.013, 0.013, 2.0) * hs, Vector4(0.011, 0.011, 0.011, 2.0) * hs, Vector4(0.0095, 0.009, 0.009, 2.0) * hs, Vector4(0.008, 0.0075, 0.0075, 2.0) * hs], 12 if closeup else 7, [], 1, 2)


static func _legs(g: CharGeo, st: Dictionary, pr: Dictionary, rest: PackedVector3Array) -> void:
	var b: float = pr["bulk"]
	var lm: float = pr["limb"]
	var m: float = pr["muscle"]
	var k := lm * pow(b, 0.85) * (1.0 + 0.15 * m)
	var boots := str(st.get("footwear", "boots"))
	var skin_t := CharGeo.M_DECAY if float(st.get("decay", 0.0)) > 0.0 else CharGeo.M_SKIN
	var trousers_c := Color(CharGeo.TROUSERS / 255.0, CharGeo.M_CLOTH / 255.0, 0.5, 1.0)
	var boot_c := Color(CharGeo.LEATHER / 255.0, CharGeo.M_LEATHER / 255.0, 0.5, 1.0)
	var skin_c := Color(CharGeo.SKIN / 255.0, skin_t / 255.0, 0.5, 1.0)
	var greave_c := Color(CharGeo.METAL / 255.0, CharGeo.M_METAL / 255.0, 0.5, 1.0)
	var boot_top := 0.4 if boots == "boots" else (0.13 if boots == "shoes" else (0.62 if boots == "tall" else -1.0))
	for side in 2:
		var o := 0 if side == 0 else 4
		var hp := rest[R.THIGH_L + o]
		var kn := rest[R.SHIN_L + o]
		var an := rest[R.FOOT_L + o]
		# t along the leg: 0 hip, 1 knee, 2 ankle.
		var spec := [
			[-0.17, 0.084, 0.084, 0.084], [0.08, 0.088, 0.09, 0.087], [0.35, 0.077, 0.08, 0.072], [0.7, 0.062, 0.064, 0.058],
			[1.0, 0.05, 0.053, 0.048], [1.18, 0.051, 0.045, 0.06], [1.42, 0.05, 0.043, 0.058], [1.68, 0.04, 0.036, 0.042],
			[1.88, 0.033, 0.032, 0.033], [2.0, 0.032, 0.032, 0.034]]
		var pts := PackedVector3Array()
		var rings: Array = []
		var ws: Array = []
		var mats: Array = []
		var cuff_done := false
		for e: Array in spec:
			var t: float = e[0]
			var p := hp.lerp(kn, t) if t <= 1.0 else kn.lerp(an, t - 1.0)
			if t < 0.0:
				p = hp + Vector3(0, -t * 0.4, 0)
			var rr := Vector4(e[1], e[2], e[3], 2.0) * Vector4(k, k, k, 1.0)
			var c := trousers_c
			if boot_top > 0.0 and p.y <= boot_top + 0.001:
				c = boot_c
				rr = rr * Vector4(1.08, 1.08, 1.08, 1.0) + Vector4(0.004, 0.004, 0.004, 0.0)
			elif boot_top < 0.0 and p.y < 0.36:
				c = skin_c
			if st.get("greaves", false) and t > 1.05 and t < 1.85:
				c = greave_c
				rr = rr * Vector4(1.12, 1.15, 1.05, 1.0)
			# Boot cuff ring.
			if boot_top > 0.0 and not cuff_done and p.y < boot_top:
				cuff_done = true
				var top := hp.lerp(kn, 0.0)
				var tc := kn.lerp(an, (kn.y - boot_top) / maxf(kn.y - an.y, 0.01))
				var _u := top
				pts.append(tc + Vector3(0, 0.012, 0))
				rings.append(Vector4(0.06, 0.056, 0.064, 2.0) * Vector4(k, k, k, 1.0))
				ws.append(Vector3(R.SHIN_L + o, R.THIGH_L + o, 0.0))
				mats.append(boot_c)
				pts.append(tc - Vector3(0, 0.01, 0))
				rings.append(Vector4(0.058, 0.054, 0.062, 2.0) * Vector4(k, k, k, 1.0))
				ws.append(Vector3(R.SHIN_L + o, R.THIGH_L + o, 0.0))
				mats.append(boot_c)
			pts.append(p)
			rings.append(rr)
			if t < 0.0:
				ws.append(Vector3(R.HIPS, R.THIGH_L + o, 0.5))
			elif t < 0.85:
				ws.append(Vector3(R.THIGH_L + o, R.SHIN_L + o, 0.0))
			elif t < 1.15:
				ws.append(Vector3(R.THIGH_L + o, R.SHIN_L + o, smoothstep(0.85, 1.15, t)))
			elif t < 1.95:
				ws.append(Vector3(R.SHIN_L + o, R.FOOT_L + o, 0.0))
			else:
				ws.append(Vector3(R.SHIN_L + o, R.FOOT_L + o, 0.35))
			mats.append(c)
		g.tube(pts, rings, 16, ws, 0, 0, Vector3.RIGHT, Vector3.FORWARD, 0.0, 1.0, mats)
		_foot(g, rest, side, boot_top > 0.0, skin_t, k)
	var _u2 := pr


static func _foot(g: CharGeo, rest: PackedVector3Array, side: int, booted: bool, skin_t: int, k: float) -> void:
	var o := 0 if side == 0 else 4
	var an := rest[R.FOOT_L + o]
	if booted:
		g.mat(CharGeo.LEATHER, CharGeo.M_LEATHER)
	else:
		g.mat(CharGeo.SKIN, skin_t)
	var c := Vector3(an.x, 0.05, an.z - 0.045)
	var v0 := g.vertex_count()
	g.ellipsoid(c, Vector3(0.047 * sqrt(k), 0.052, 0.13), 10, 16, Basis.IDENTITY, 2.3, func(d: Vector3, p: Vector3) -> Vector3:
		var q := p
		if d.y < 0.0:
			q.y *= 0.5 if booted else 0.42
		if q.z < -0.04 and d.y > 0.0:
			q.y -= (-q.z - 0.04) * 0.45
		if q.z > 0.06:
			q.y += 0.006
		return q)
	g.reweight(v0, g.vertex_count(), func(p: Vector3) -> Variant:
		var f := smoothstep(-0.08, -0.125, p.z - an.z)
		var up := smoothstep(0.07, 0.1, p.y)
		return [[R.FOOT_L + o, R.TOE_L + o, R.SHIN_L + o], [(1.0 - f) * (1.0 - up * 0.5), f, up * 0.5 * (1.0 - f)]])
	# Dark sole and welt.
	g.reshade(v0, g.vertex_count(), func(p: Vector3) -> Variant:
		if p.y < 0.016:
			return Vector2(0.45, 0.6)
		return null)


# --- Garments --------------------------------------------------------------------------

static func _skirt(g: CharGeo, pr: Dictionary, y_top: float, hem: float, flare: float, follow: float, slot: int, mtype: int, tatter := 0.0, shade := 1.0) -> void:
	var n := 7
	var pts := PackedVector3Array()
	var rings: Array = []
	for i in n:
		var f := float(i) / (n - 1)
		var y := lerpf(y_top, hem, f)
		var tr := torso_ring(minf(y, 1.0) if y > 0.8 else 0.97, pr)
		var top := torso_ring(y_top, pr)
		var base := top if y < 0.97 else tr
		var grow := (y_top - y) * flare
		pts.append(Vector3(0, y, 0.004 + grow * 0.15))
		rings.append(Vector4(base.x + 0.008 + grow, base.y + 0.008 + grow * 0.8, base.z + 0.01 + grow, 2.1))
	var v0 := g.vertex_count()
	g.mat(slot, mtype, shade)
	g.tube(pts, rings, 28, [], 0, 0)
	var span := maxf(y_top - hem, 0.01)
	g.reweight(v0, g.vertex_count(), func(p: Vector3) -> Variant:
		var fd := clampf((y_top - p.y) / span, 0.0, 1.0)
		var fl := follow * smoothstep(0.0, 0.6, fd)
		var hx := torso_ring(0.97, pr).x + (y_top - p.y) * flare
		var s := clampf(0.5 + p.x / (2.0 * hx), 0.0, 1.0)
		return [[R.HIPS, R.THIGH_L, R.THIGH_R], [1.0 - fl, fl * (1.0 - s), fl * s]])
	if tatter > 0.0:
		for i in range(v0, g.vertex_count()):
			g.cus[i * 4 + 3] = clampf((y_top - g.pos[i].y) / span, 0.0, 1.0) * tatter
	# Inner face so the hem looks like fabric from below.
	var t1 := g.tri_count()
	var v1 := g.vertex_count()
	g.mat(slot, mtype, shade * 0.5, 0.4)
	var inner_rings: Array = []
	for r: Vector4 in rings:
		inner_rings.append(r - Vector4(0.006, 0.006, 0.006, 0.0))
	g.tube(pts, inner_rings, 28, [], 0, 0)
	g.flip_tris(t1)
	for i in range(v1, g.vertex_count()):
		var j := v0 + (i - v1)
		for kk in 4:
			g.bon[i * 4 + kk] = g.bon[j * 4 + kk]
			g.wgt[i * 4 + kk] = g.wgt[j * 4 + kk]
		g.cus[i * 4 + 3] = g.cus[j * 4 + 3]


static func _garments(g: CharGeo, st: Dictionary, pr: Dictionary, rest: PackedVector3Array) -> void:
	var b: float = pr["bulk"]
	var robe: bool = st.get("robe", false)
	var sm := _shirt_mat(st)
	var tl := float(st.get("tunic_length", 0.42))
	var tatter := 1.0 if st.get("tattered", false) and st.get("rags", false) else 0.0
	if robe:
		_skirt(g, pr, 1.02, 0.04, 0.22, 0.5, sm[0], sm[1], 0.0)
	elif tl > 0.0 and str(st.get("shirt", "")) != "none":
		_skirt(g, pr, 1.02, lerpf(0.9, 0.5, tl), 0.12, 0.85, sm[0], sm[1], tatter)
	if st.get("tabard", false):
		_tabard(g, pr)
	# Belt or sash.
	if st.get("belt", true) and str(st.get("shirt", "")) != "none" or robe:
		var sash: bool = st.get("sash", robe)
		var slot := CharGeo.CLOTH2 if sash else CharGeo.LEATHER
		var mt := CharGeo.M_CLOTH if sash else CharGeo.M_LEATHER
		g.mat(slot, mt)
		var r0 := torso_ring(1.03, pr)
		var extra := 0.016 if robe else 0.011
		var v0 := g.vertex_count()
		g.tube(PackedVector3Array([Vector3(0, 1.0, 0.004), Vector3(0, 1.012, 0.004), Vector3(0, 1.048, 0.004), Vector3(0, 1.06, 0.004)]),
			[Vector4(r0.x + extra - 0.003, r0.y + extra - 0.003, r0.z + extra - 0.003, r0.w), Vector4(r0.x + extra, r0.y + extra, r0.z + extra, r0.w),
			Vector4(r0.x + extra, r0.y + extra, r0.z + extra, r0.w), Vector4(r0.x + extra - 0.003, r0.y + extra - 0.003, r0.z + extra - 0.003, r0.w)], 28,
			[Vector3(R.HIPS, R.SPINE, 0.15), Vector3(R.HIPS, R.SPINE, 0.15), Vector3(R.HIPS, R.SPINE, 0.2), Vector3(R.HIPS, R.SPINE, 0.2)], 0, 0)
		var _u := v0
		if not sash:
			g.mat(CharGeo.METAL, CharGeo.M_METAL, 1.1)
			g.bone(R.HIPS)
			g.ellipsoid(Vector3(0, 1.03, -(r0.y + extra + 0.004)), Vector3(0.022, 0.02, 0.006), 4, 10, Basis.IDENTITY, 4.0)
			# Pouch on the right hip.
			g.mat(CharGeo.LEATHER, CharGeo.M_LEATHER, 0.85)
			g.ellipsoid(Vector3(r0.x * 0.82, 0.97, -r0.y * 0.45), Vector3(0.022, 0.045, 0.04), 6, 10, Basis(Vector3.UP, 0.6))
		else:
			g.bone(R.HIPS)
			g.tube(PackedVector3Array([Vector3(-0.05, 1.03, -(r0.y + extra)), Vector3(-0.07, 0.9, -(r0.y + extra * 0.5)), Vector3(-0.065, 0.78, -(r0.y))]),
				[Vector4(0.025, 0.006, 0.006, 2.0), Vector4(0.03, 0.006, 0.006, 2.0), Vector4(0.032, 0.005, 0.005, 2.0)], 6,
				[Vector3(R.HIPS, R.THIGH_L, 0.0), Vector3(R.HIPS, R.THIGH_L, 0.3), Vector3(R.HIPS, R.THIGH_L, 0.6)], 0, 0)
	if st.get("apron", false):
		_apron(g, pr)
	if st.get("vest", false):
		# A fitted leather vest over the shirt.
		g.mat(CharGeo.LEATHER, CharGeo.M_LEATHER, 0.95)
		var ys := [1.06, 1.16, 1.26, 1.34, 1.41, 1.45]
		var pts := PackedVector3Array()
		var rings: Array = []
		var ws: Array = []
		for y: float in ys:
			var r := torso_ring(y, pr)
			pts.append(Vector3(0, y, 0.008 * smoothstep(1.2, 1.4, y)))
			rings.append(Vector4(r.x + 0.01, r.y + 0.012, r.z + 0.01, r.w))
			ws.append(_torso_w(y))
		var t0 := g.tri_count()
		var v1 := g.vertex_count()
		g.tube(pts, rings, 28, ws, 0, 0)
		g.clip_tris(t0, func(p: Vector3) -> bool: return not (p.z < -0.05 and absf(p.x) < 0.035 + (p.y - 1.06) * 0.1))
		_shoulder_reweight(g, v1, b)
	if st.get("collar", false):
		g.mat(CharGeo.CLOTH2, CharGeo.M_WOOL)
		g.tube(PackedVector3Array([Vector3(0, 1.47, 0.008), Vector3(0, 1.51, 0.01), Vector3(0, 1.545, 0.012)]),
			[Vector4(0.12 * b, 0.085, 0.09, 2.0), Vector4(0.09, 0.075, 0.08, 2.0), Vector4(0.07, 0.065, 0.068, 2.0)], 20,
			[Vector3(R.CHEST, R.NECK, 0.1), Vector3(R.CHEST, R.NECK, 0.3), Vector3(R.CHEST, R.NECK, 0.5)], 0, 0)
	var _u2 := rest


static func _tabard(g: CharGeo, pr: Dictionary) -> void:
	for face in 2:
		var front := face == 0
		var rows := 8
		var cols := 5
		var grid := PackedVector3Array()
		for i in rows:
			var f := float(i) / (rows - 1)
			var y := lerpf(1.46, 0.6, f)
			var tr := torso_ring(clampf(y, 0.97, 1.46), pr)
			for j in cols:
				var u := float(j) / (cols - 1) * 2.0 - 1.0
				var w := 0.14 * float(pr["bulk"])
				var depth := (tr.y if front else tr.z) + 0.016
				var z := -depth * cos(u * 0.7) if front else depth * cos(u * 0.7)
				if y < 0.97:
					z = (-1.0 if front else 1.0) * (depth + (0.97 - y) * 0.15)
				grid.append(Vector3(u * w, y, z))
		g.mat(CharGeo.CLOTH2, CharGeo.M_CLOTH)
		g.sheet(grid, rows, cols, 0.006, Vector3.FORWARD if front else Vector3.BACK, func(row: int, col: int) -> Array:
			var y := lerpf(1.46, 0.6, float(row) / (rows - 1))
			if y > 1.0:
				var tw := _torso_w(y)
				return [[int(tw.x), int(tw.y)], [1.0 - tw.z, tw.z]]
			var fd := clampf((1.0 - y) / 0.4, 0.0, 1.0) * 0.8
			var s := float(col) / (cols - 1)
			return [[R.HIPS, R.THIGH_L, R.THIGH_R], [1.0 - fd, fd * (1.0 - s), fd * s]], Callable(), 0.6)


static func _apron(g: CharGeo, pr: Dictionary) -> void:
	var rows := 9
	var cols := 6
	var grid := PackedVector3Array()
	for i in rows:
		var f := float(i) / (rows - 1)
		var y := lerpf(1.38, 0.5, f)
		var tr := torso_ring(clampf(y, 0.97, 1.38), pr)
		var w := lerpf(0.11, 0.2, smoothstep(0.0, 0.45, f)) * float(pr["bulk"])
		for j in cols:
			var u := float(j) / (cols - 1) * 2.0 - 1.0
			var z := -(tr.y + 0.014) * cos(u * 0.8)
			if y < 0.97:
				z = -(tr.y + 0.02 + (0.97 - y) * 0.12) * cos(u * 0.5)
			grid.append(Vector3(u * w, y, z))
	g.mat(CharGeo.LEATHER, CharGeo.M_LEATHER, 1.15)
	g.sheet(grid, rows, cols, 0.008, Vector3.FORWARD, func(row: int, col: int) -> Array:
		var y := lerpf(1.38, 0.5, float(row) / (rows - 1))
		if y > 1.0:
			var tw := _torso_w(y)
			return [[int(tw.x), int(tw.y)], [1.0 - tw.z, tw.z]]
		var fd := clampf((1.0 - y) / 0.45, 0.0, 1.0) * 0.75
		var s := float(col) / (cols - 1)
		return [[R.HIPS, R.THIGH_L, R.THIGH_R], [1.0 - fd, fd * (1.0 - s), fd * s]], Callable(), 0.6)
	# Neck strap.
	var top := torso_ring(1.38, pr)
	g.mat(CharGeo.LEATHER, CharGeo.M_LEATHER, 0.9)
	g.tube(PackedVector3Array([Vector3(-0.1, 1.38, -top.y - 0.012), Vector3(-0.075, 1.5, -0.05), Vector3(0, 1.545, 0.045), Vector3(0.075, 1.5, -0.05), Vector3(0.1, 1.38, -top.y - 0.012)]),
		[Vector4(0.012, 0.004, 0.004, 2.0), Vector4(0.012, 0.004, 0.004, 2.0), Vector4(0.012, 0.004, 0.004, 2.0), Vector4(0.012, 0.004, 0.004, 2.0), Vector4(0.012, 0.004, 0.004, 2.0)], 6,
		[Vector3(R.CHEST, R.NECK, 0.0), Vector3(R.CHEST, R.NECK, 0.3), Vector3(R.CHEST, R.NECK, 0.5), Vector3(R.CHEST, R.NECK, 0.3), Vector3(R.CHEST, R.NECK, 0.0)], 0, 0, Vector3.UP)


static func _rags(g: CharGeo, st: Dictionary, pr: Dictionary) -> void:
	# Torn loincloth and a ragged shoulder wrap for the restless dead.
	var slot := CharGeo.CLOTH
	_skirt(g, pr, 1.03, 0.62, 0.1, 0.85, slot, CharGeo.M_CLOTH, 1.0, 0.9)
	if st.get("shoulder_rags", false) and not st.get("hood", false) and not st.get("cloak", false):
		var v0 := g.vertex_count()
		g.mat(slot, CharGeo.M_CLOTH, 0.85)
		var b: float = pr["bulk"]
		g.tube(PackedVector3Array([Vector3(0, 1.53, 0.02), Vector3(0, 1.47, 0.01), Vector3(0, 1.38, 0.01), Vector3(0, 1.22, 0.02)]),
			[Vector4(0.08, 0.07, 0.07, 2.0), Vector4(0.17 * b, 0.1, 0.11, 2.0), Vector4(0.23 * b, 0.13, 0.13, 2.2), Vector4(0.24 * b, 0.14, 0.14, 2.2)], 22,
			[Vector3(R.NECK, R.CHEST, 0.6), Vector3(R.CHEST, R.CHEST, 0.0), Vector3(R.CHEST, R.CHEST, 0.0), Vector3(R.CHEST, R.SPINE, 0.3)], 0, 0)
		for i in range(v0, g.vertex_count()):
			g.cus[i * 4 + 3] = clampf((1.53 - g.pos[i].y) / 0.31, 0.0, 1.0)


# --- Armour ----------------------------------------------------------------------------

static func _armour(g: CharGeo, st: Dictionary, pr: Dictionary, rest: PackedVector3Array) -> void:
	var b: float = pr["bulk"]
	if st.get("plate", false):
		g.mat(CharGeo.METAL, CharGeo.M_METAL)
		var ys := [1.08, 1.14, 1.22, 1.3, 1.37, 1.43, 1.47]
		var pts := PackedVector3Array()
		var rings: Array = []
		var ws: Array = []
		for y: float in ys:
			var r := torso_ring(y, pr)
			var add := 0.024 if y < 1.46 else 0.018
			pts.append(Vector3(0, y, 0.008 * smoothstep(1.2, 1.4, y)))
			rings.append(Vector4(r.x + add, r.y + add + 0.008 * _bump(y, 1.3, 0.08), r.z + add, 2.3))
			ws.append(_torso_w(y))
		var v0 := g.vertex_count()
		g.tube(pts, rings, 28, ws, 0, 0)
		_shoulder_reweight(g, v0, b)
		# Fauld: overlapping lames below the breastplate.
		for i in 2:
			var y0 := 1.07 - i * 0.055
			var r0 := torso_ring(maxf(y0, 0.97), pr)
			g.tube(PackedVector3Array([Vector3(0, y0, 0.0), Vector3(0, y0 - 0.06, 0.0)]),
				[Vector4(r0.x + 0.026 + i * 0.01, r0.y + 0.026 + i * 0.01, r0.z + 0.024 + i * 0.01, 2.2), Vector4(r0.x + 0.04 + i * 0.012, r0.y + 0.04 + i * 0.012, r0.z + 0.035 + i * 0.012, 2.2)], 28,
				[Vector3(R.HIPS, R.SPINE, 0.1), Vector3(R.HIPS, R.SPINE, 0.0)], 0, 0)
	if st.get("pauldrons", false) or st.get("plate", false):
		for side in 2:
			var sg := -1.0 if side == 0 else 1.0
			var o := 0 if side == 0 else 5
			var c := rest[R.UARM_L + o] + Vector3(sg * 0.012, 0.02, 0.0)
			for layer in 3:
				var t0 := g.tri_count()
				var v0 := g.vertex_count()
				g.mat(CharGeo.METAL, CharGeo.M_METAL, 1.0 - layer * 0.08)
				var rr := Vector3(0.085, 0.07, 0.09) * b * (1.0 - layer * 0.12)
				g.ellipsoid(c + Vector3(sg * layer * 0.02, -layer * 0.045, 0), rr, 10, 16)
				g.clip_tris(t0, func(p: Vector3) -> bool: return p.y > c.y - layer * 0.045 - 0.015 and sg * (p.x - c.x) > -0.05)
				g.reweight(v0, g.vertex_count(), func(_p: Vector3) -> Variant: return [[R.CLAV_L + o, R.UARM_L + o], [0.6 - layer * 0.15, 0.4 + layer * 0.15]])
	var shield: Variant = st.get("shield", false)
	if shield is bool and shield:
		shield = "round"
	if shield is String and shield != "":
		var e := rest[R.FARM_L]
		var w := rest[R.HAND_L]
		var c := e.lerp(w, 0.45) + Vector3(-0.065, 0, -0.01)
		var basis := Basis(Vector3.BACK, PI * 0.5)  # disc faces -X (outward on the left arm)
		g.bone(R.FARM_L)
		g.mat(CharGeo.CLOTH2, CharGeo.M_LEATHER, 1.0)
		var kite: bool = shield == "kite"
		var rr := Vector3(0.012, 0.3, 0.3) if not kite else Vector3(0.012, 0.36, 0.22)
		g.ellipsoid(c, Vector3(rr.y, rr.x, rr.z), 6, 28, basis, 2.0, func(d: Vector3, p: Vector3) -> Vector3:
			var q := p
			q.y += 0.03 * (1.0 - (d.x * d.x + d.z * d.z))  # gently domed
			if kite and d.x > 0.0:
				q.x *= 1.0 + 0.4 * d.x
				q.z *= 1.0 - 0.6 * d.x * d.x
			return q)
		g.mat(CharGeo.METAL, CharGeo.M_METAL)
		g.ellipsoid(c + Vector3(-0.035, 0, 0), Vector3(0.06, 0.03, 0.06), 6, 14, basis)
		# Rim.
		var band := PackedVector3Array()
		var rings: Array = []
		for i in 29:
			var a := TAU * float(i) / 28.0
			var y := sin(a) * rr.y
			if kite and y < 0.0:
				y *= 1.4
			band.append(c + Vector3(-0.004, y, cos(a) * rr.z * (1.0 - (0.5 * maxf(0.0, -sin(a)) if kite else 0.0))))
			rings.append(Vector4(0.01, 0.01, 0.01, 2.0))
		g.tube(band, rings, 6, [], 0, 0, Vector3.RIGHT)


# --- Cloak -----------------------------------------------------------------------------

## Rest shape of the cloak: u across (0 left front .. 1 right front), v down.
static func cloak_point(u: float, v: float, st: Dictionary, pr: Dictionary) -> Vector3:
	var b: float = pr["bulk"]
	var hem := 0.3
	if st.get("cape", false):
		hem = 0.82
	if st.get("robe", false):
		hem = 0.1
	hem = float(st.get("cloak_hem", hem))
	var th_max := lerpf(1.95, 1.55, v)
	var th := lerpf(-th_max, th_max, u)
	var top := 1.5 - 0.05 * absf(sin(th))
	var y := lerpf(top, hem, v)
	var rx := lerpf(0.2 * b + 0.035, 0.34 * b, pow(v, 0.8))
	var rz := lerpf(0.125 * b + 0.01, 0.27 * b, pow(v, 0.7))
	# A hood's mantle sits on top; tuck the cloak under it.
	return Vector3(sin(th) * rx, y, cos(th) * rz + 0.02)


static func _cloak(g: CharGeo, st: Dictionary, pr: Dictionary, first: int) -> PackedVector3Array:
	var C := R.CLOAK_COLS
	var RW := R.CLOAK_ROWS
	var bones_rest := PackedVector3Array()
	for r in RW:
		for c in C:
			bones_rest.append(cloak_point(float(c) / (C - 1), float(r) / (RW - 1), st, pr))
	var rows := 13
	var cols := 13
	var grid := PackedVector3Array()
	for r in rows:
		for c in cols:
			grid.append(cloak_point(float(c) / (cols - 1), float(r) / (rows - 1), st, pr))
	var tatter := 1.0 if st.get("tattered", false) else 0.0
	g.mat(CharGeo.CLOAK, CharGeo.M_CLOTH)
	g.sheet(grid, rows, cols, 0.012, Vector3.BACK, func(row: int, col: int) -> Array:
		var pu := float(col) / (cols - 1) * (C - 1)
		var pv := float(row) / (rows - 1) * (RW - 1)
		var c0 := mini(int(pu), C - 2)
		var r0 := mini(int(pv), RW - 2)
		var fu := pu - c0
		var fv := pv - r0
		var b00 := first + r0 * C + c0
		return [[b00, b00 + 1, b00 + C, b00 + C + 1], [(1.0 - fu) * (1.0 - fv), fu * (1.0 - fv), (1.0 - fu) * fv, fu * fv]],
		func(row: int, _col: int) -> float: return float(row) / (rows - 1) * tatter, 0.55)
	return bones_rest
