class_name ItemIcons
extends RefCounted
## Item icons rendered from the items' real 3D models (HeldItems.build) in a
## tiny off-screen photo studio: soft key/fill/rim lights, an HDR softbox
## environment for metal reflections, transparent background, 3/4 angle.
##
##   ItemIcons.icon(id) -> Texture2D or null (not rendered yet: draw the glyph)
##   ItemIcons.prewarm()             queue every item (low priority, a few per frame)
##   ItemIcons.version               bumps whenever new icons arrive (UI redraw hint)
##
## Rendering is asynchronous (a few icons per frame on a pool of SubViewports)
## so loading is never blocked. Headless / dummy renderers never render: icon()
## stays null and the UI keeps its glyphs.

const SIZE := 128
const POOL := 3

static var version := 0
static var _tex := {}
static var _renderer: Node = null


static func available() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return RenderingServer.get_rendering_device() != null or OS.get_name() == "Web"


static func has_icon(id: String) -> bool:
	return _tex.has(id)


## The icon for `id`, or null while it is being rendered (or when unavailable).
static func icon(id: String) -> Texture2D:
	var t: Variant = _tex.get(id)
	if t != null:
		return t
	if id == "" or not ItemDB.exists(id) or not available():
		return null
	_ensure_renderer()
	if _renderer != null:
		_renderer.call("request", id, true)
	return null


## Queues every item (or `ids`) behind on-demand requests.
static func prewarm(ids: Array = []) -> void:
	if not available():
		return
	_ensure_renderer()
	if _renderer == null:
		return
	var list := ids if not ids.is_empty() else ItemDB.ITEMS.keys()
	for id: String in list:
		if not _tex.has(id):
			_renderer.call("request", id, false)


static func _store(id: String, tex: Texture2D) -> void:
	_tex[id] = tex
	version += 1


static func _ensure_renderer() -> void:
	if _renderer != null and is_instance_valid(_renderer):
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	_renderer = _Renderer.new()
	_renderer.name = "ItemIconRenderer"
	tree.root.add_child.call_deferred(_renderer)


## Returns the pose used for an item: "diagonal" (long things), "upright" or "front".
static func pose(id: String) -> String:
	var inf := ItemDB.info(id)
	var cat := String(inf.get("category", ""))
	if inf.has("pose"):
		return String(inf["pose"])
	if cat in ["tool", "weapon"] or id in ["torch", "stick"]:
		return "diagonal"
	if cat == "armor" or cat == "key":
		return "front"
	return "upright"


class _Renderer:
	extends Node

	var _queue: Array[String] = []
	var _queued := {}
	var _tries := {}
	## Jobs staged this round, and the frame they were staged on.
	var _jobs: Array[String] = []
	var _models: Array[Node3D] = []
	var _staged_frame := -1
	var _views: Array[SubViewport] = []
	var _pivots: Array[Node3D] = []
	var _cams: Array[Camera3D] = []

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		var env := _environment()
		for i in ItemIcons.POOL:
			var vp := SubViewport.new()
			vp.size = Vector2i(ItemIcons.SIZE, ItemIcons.SIZE)
			vp.transparent_bg = true
			vp.own_world_3d = true
			vp.msaa_3d = Viewport.MSAA_4X
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
			add_child(vp)
			var we := WorldEnvironment.new()
			we.environment = env
			vp.add_child(we)
			_lights(vp)
			var cam := Camera3D.new()
			cam.fov = 20.0
			cam.near = 0.01
			cam.far = 50.0
			vp.add_child(cam)
			cam.current = true
			var pivot := Node3D.new()
			vp.add_child(pivot)
			_views.append(vp)
			_pivots.append(pivot)
			_cams.append(cam)

	func request(id: String, urgent: bool) -> void:
		if _queued.has(id) or ItemIcons.has_icon(id):
			if urgent and _queued.has(id):
				_queue.erase(id)
				_queue.push_front(id)
			return
		_queued[id] = true
		if urgent:
			_queue.push_front(id)
		else:
			_queue.append(id)

	## A small state machine polled every frame (no awaits that could stall):
	## stage up to POOL items, let two frames render them, then read back.
	func _process(_delta: float) -> void:
		if _views.is_empty():
			return
		var frame := Engine.get_frames_drawn()
		if not _jobs.is_empty():
			if frame - _staged_frame < 2:
				return
			_collect()
		if _queue.is_empty():
			return
		while _jobs.size() < _views.size() and not _queue.is_empty():
			var id: String = _queue.pop_front()
			var m := _stage(_jobs.size(), id)
			if m == null:
				_queued.erase(id)
				continue
			_views[_jobs.size()].render_target_update_mode = SubViewport.UPDATE_ONCE
			_jobs.append(id)
			_models.append(m)
		_staged_frame = frame

	func _collect() -> void:
		for k in _jobs.size():
			var id := _jobs[k]
			_queued.erase(id)
			var img := _views[k].get_texture().get_image()
			if img != null and not img.is_empty() and not _blank(img):
				img.convert(Image.FORMAT_RGBA8)
				img.generate_mipmaps()
				ItemIcons._store(id, ImageTexture.create_from_image(img))
			elif int(_tries.get(id, 0)) < 3:
				_tries[id] = int(_tries.get(id, 0)) + 1
				request(id, false)
			_models[k].queue_free()
		_jobs.clear()
		_models.clear()

	## True when nothing was drawn (the window was not drawing yet).
	func _blank(img: Image) -> bool:
		var s := img.get_width()
		for p: Vector2i in [Vector2i(s / 2, s / 2), Vector2i(s / 3, s / 2), Vector2i(s / 2, s / 3), Vector2i(2 * s / 3, s / 2), Vector2i(s / 2, 2 * s / 3)]:
			if img.get_pixelv(p).a > 0.05:
				return false
		var used := img.get_used_rect()
		return used.size.x <= 0

	## Builds the item into pivot k and frames the camera on it.
	func _stage(k: int, id: String) -> Node3D:
		var pivot := _pivots[k]
		var model := HeldItems.build(id, 1.0, false)
		if model == null:
			return null
		pivot.add_child(model)
		_stop_particles(model)
		var basis := Basis.IDENTITY
		match ItemIcons.pose(id):
			"diagonal":
				basis = Basis(Vector3(0, 0, 1), deg_to_rad(-45.0)) * Basis(Vector3(1, 0, 0), deg_to_rad(14.0)) * Basis(Vector3.UP, deg_to_rad(-24.0))
			"front":
				basis = Basis(Vector3(1, 0, 0), deg_to_rad(14.0)) * Basis(Vector3.UP, deg_to_rad(-22.0))
			_:
				basis = Basis(Vector3(1, 0, 0), deg_to_rad(26.0)) * Basis(Vector3.UP, deg_to_rad(-38.0))
		pivot.transform = Transform3D(basis, Vector3.ZERO)
		var box := _bounds(model, pivot.transform)
		var centre := box.get_center()
		pivot.position = -centre
		var extent := maxf(box.size.x, box.size.y)
		if ItemIcons.pose(id) == "diagonal" and extent > 0.55:
			# Long hafts: frame the head and let the shaft run off the corner.
			var zoom := clampf(0.55 / extent, 0.5, 1.0)
			centre += (basis * Vector3.UP).normalized() * extent * (1.0 - zoom) * 0.62
			extent *= zoom
			pivot.position = -centre
		var dist := (extent * 0.5) / tan(deg_to_rad(_cams[k].fov * 0.5)) * 1.12 + box.size.z * 0.5
		_cams[k].position = Vector3(0, 0, dist)
		_cams[k].look_at(Vector3.ZERO)
		_cams[k].far = dist + box.size.z * 2.0 + 1.0
		return model

	func _bounds(model: Node3D, pivot_xf: Transform3D) -> AABB:
		var box := AABB()
		var first := true
		var stack: Array[Node] = [model]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for c in n.get_children():
				stack.append(c)
			var mi := n as MeshInstance3D
			if mi == null or mi.mesh == null or not mi.visible:
				continue
			var xf := pivot_xf * _local_xf(mi, model)
			var b := xf * mi.mesh.get_aabb()
			if first:
				box = b
				first = false
			else:
				box = box.merge(b)
		if first:
			box = AABB(Vector3(-0.1, -0.1, -0.1), Vector3(0.2, 0.2, 0.2))
		return box

	func _local_xf(n: Node3D, root: Node3D) -> Transform3D:
		var xf := n.transform
		var p := n.get_parent() as Node3D
		while p != null and p != root:
			xf = p.transform * xf
			p = p.get_parent() as Node3D
		return root.transform * xf if p == root else xf

	func _stop_particles(n: Node) -> void:
		for c in n.get_children():
			if c is GPUParticles3D:
				(c as GPUParticles3D).visible = false
			elif c is OmniLight3D:
				(c as OmniLight3D).light_energy *= 0.35
			_stop_particles(c)

	func _lights(vp: SubViewport) -> void:
		var key := DirectionalLight3D.new()
		key.light_color = Color(1.0, 0.93, 0.84)
		key.light_energy = 2.3
		key.rotation_degrees = Vector3(-38, -42, 0)
		key.shadow_enabled = true
		key.shadow_blur = 2.0
		vp.add_child(key)
		var fill := DirectionalLight3D.new()
		fill.light_color = Color(0.62, 0.74, 1.0)
		fill.light_energy = 0.75
		fill.rotation_degrees = Vector3(-10, 70, 0)
		vp.add_child(fill)
		var rim := DirectionalLight3D.new()
		rim.light_color = Color(1.0, 0.78, 0.55)
		rim.light_energy = 2.6
		rim.rotation_degrees = Vector3(-25, 165, 0)
		vp.add_child(rim)

	func _environment() -> Environment:
		var env := Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		var sky := Sky.new()
		var mat := PanoramaSkyMaterial.new()
		mat.panorama = _studio_panorama()
		sky.sky_material = mat
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 0.55
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_exposure = 1.05
		env.glow_enabled = true
		env.glow_intensity = 0.55
		env.glow_bloom = 0.05
		env.glow_hdr_threshold = 1.2
		return env

	## A dark studio with two softboxes and a warm floor bounce, for reflections.
	func _studio_panorama() -> ImageTexture:
		var w := 256
		var h := 128
		var img := Image.create(w, h, false, Image.FORMAT_RGBH)
		for y in h:
			var v := float(y) / float(h - 1)  # 0 top .. 1 bottom
			for x in w:
				var u := float(x) / float(w - 1)
				var c := Color(0.06, 0.06, 0.07).lerp(Color(0.16, 0.12, 0.1), smoothstep(0.45, 1.0, v))
				# Key softbox: upper left-front.
				var d1 := Vector2((u - 0.62) * 2.2, (v - 0.28) * 3.0).length()
				c += Color(3.2, 2.9, 2.6) * (1.0 - smoothstep(0.18, 0.32, d1))
				# Cool strip on the right.
				var d2 := Vector2((u - 0.88) * 5.0, (v - 0.4) * 1.4).length()
				c += Color(0.8, 1.0, 1.4) * (1.0 - smoothstep(0.2, 0.4, d2))
				# Warm rim from behind.
				var d3 := Vector2((u - 0.12) * 3.0, (v - 0.3) * 2.5).length()
				c += Color(1.6, 1.0, 0.55) * (1.0 - smoothstep(0.15, 0.35, d3))
				img.set_pixel(x, y, c)
		return ImageTexture.create_from_image(img)
