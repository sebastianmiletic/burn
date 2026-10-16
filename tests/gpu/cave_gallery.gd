extends Node3D
## Visual check for cave decorations (CaveDecor) and mine props (MineDressing), drawn on
## real smooth terrain: a row of sculpted chambers, one per cave biome, a chamber whose walls
## are banded with every ore, and a timbered mine drift with track, carts and lanterns.
## The terrain and decor go through the same SmoothMesher -> CaveDecor.plan_chunk ->
## build_chunk path as the game.
##
##   godot --path . res://tests/gpu/cave_gallery.tscn -- --capture=/abs/dir [--quality=2] [--only=name]
##
## Prints planning cost per chunk and the GPU frame time with decor shown and hidden.

const ROOM_Y := -40.0
const SPACING := 34.0
const KIND_ROOMS := ["karst", "geyser", "fungal", "frost", "sanctuary", "magma", "flooded"]
const ORE_ROOM := 7
const MINE_ROOM := 8
const ORE_BANDS := [13, 14, 51, 52, 53, 15, 54, 55, 56, 57, 58, 16, 36, 17]

var camera: Camera3D
var _capture_dir := ""
var _only := ""
var _blocks := {}
var _dens := {}
var _decor_nodes: Array[Node3D] = []
var _quality := 2
var _plan_us := 0
var _plan_chunks := 0
var _instances := 0
var _lights := 0
var _view: WorldView


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_capture_dir = arg.trim_prefix("--capture=")
		elif arg.begins_with("--quality="):
			_quality = int(arg.trim_prefix("--quality="))
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=")
	_environment()
	CaveDecor.warmup()
	MineDressing.warmup()
	var tris := []
	for i in CaveDecor.M.COUNT:
		var m := CaveDecor.mesh(i)
		tris.append(m.surface_get_array_index_len(0) / 3 if m != null else 0)
	print("[cave_gallery] template triangles: ", tris)
	_build_terrain()
	_build_mine()
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = 400.0
	add_child(camera)
	var torch := OmniLight3D.new()
	torch.light_color = Color(1.0, 0.68, 0.36)
	torch.light_energy = 1.7
	torch.omni_range = 12.0
	torch.omni_attenuation = 1.3
	torch.position = Vector3(0.35, -0.1, 0.2)
	camera.add_child(torch)
	_view = WorldView.new()
	_view.source_camera = camera
	add_child(_view)
	print("[cave_gallery] plan %.2f ms/chunk over %d chunks, %d instances, %d lights, warmup %.0f ms" % [
		_plan_us / 1000.0 / maxf(1, _plan_chunks), _plan_chunks, _instances, _lights, CaveDecor.warmup_ms])
	if _capture_dir != "":
		DirAccess.make_dir_recursive_absolute(_capture_dir)
		_capture.call_deferred()


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.36, 0.44)
	env.ambient_light_energy = 0.03
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.5
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.0
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(0.6, 0.6, 0.6)
	GraphicsQuality.apply_environment(env)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


# --- Terrain ---------------------------------------------------------------------------

func _room_centre(i: int) -> Vector3:
	return Vector3(20.0 + SPACING * i, ROOM_Y, 20.0)


## Smooth field value (>= 0.5 solid) and block id at a world voxel centre.
func _sample(p: Vector3) -> Array:
	var i := clampi(int(floor((p.x - 3.0) / SPACING)), 0, MINE_ROOM)
	var c := _room_centre(i)
	var q := p - c
	var nz := CaveMeshes.n3(p * 0.11, 1.0) * 2.2 + CaveMeshes.n3(p * 0.35, 2.0) * 0.6
	var inside: float
	if i == MINE_ROOM:
		# A straight drift 4 m wide, 3.6 m high with an arched roof, plus a yard at the end.
		var wall := absf(q.x) - 2.0
		var floor_d := -1.8 - q.y
		var roof := q.y - 1.8 - 0.25 * (1.0 - clampf(absf(q.x) / 2.0, 0.0, 1.0))
		inside = maxf(maxf(wall, floor_d), maxf(roof, absf(q.z) - 14.0)) + nz * 0.05
		var yard := maxf(Vector2(q.x, q.z - 21.0).length() - 11.0, maxf(-1.8 - q.y, q.y - 13.0))
		inside = minf(inside, yard)
	else:
		var e := Vector3(q.x / 12.0, q.y / 5.5, q.z / 12.0).length() - 1.0
		inside = maxf(e * 5.5, -3.0 - q.y) + nz * 0.55
	var d := 0.5 + inside * 0.5
	var block := Blocks.LIMESTONE
	match i:
		1:
			block = Blocks.BASALT
		3:
			block = Blocks.ICE if q.y > -2.5 else Blocks.STONE
		4:
			block = Blocks.MARBLE
		5:
			block = Blocks.BASALT
		6:
			block = Blocks.LIMESTONE
		ORE_ROOM:
			var band := int(floor((q.x + 12.0) / 1.75))
			if q.y > -2.6 and band >= 0 and band < ORE_BANDS.size() and absf(q.z) > 5.0:
				block = ORE_BANDS[band]
			else:
				block = Blocks.STONE
		MINE_ROOM:
			block = Blocks.STONE
			if CaveMeshes.n3(p * 0.6, 9.0) > 0.35:
				block = Blocks.IRON_ORE
	if i < ORE_ROOM and i != 4 and CaveMeshes.n3(p * 0.5, 4.0) > 0.42:
		block = [Blocks.IRON_ORE, Blocks.COPPER_ORE, Blocks.COAL_ORE, Blocks.SILVER_ORE][i % 4]
	return [d, block]


func _chunk_data(k: Vector3i) -> void:
	if _blocks.has(k):
		return
	var blocks := Chunk.empty()
	var dens := Chunk.empty()
	var o := k * Chunk.SIZE
	for y in 16:
		for z in 16:
			for x in 16:
				var s := _sample(Vector3(o.x + x + 0.5, o.y + y + 0.5, o.z + z + 0.5))
				var d: float = s[0]
				var i := x + z * 16 + y * 256
				if d >= 0.5:
					blocks[i] = int(s[1])
					dens[i] = clampi(int(d * 255.0), 128, 255)
				else:
					dens[i] = clampi(int(d * 255.0), 0, 127)
	_blocks[k] = blocks
	_dens[k] = dens


func _build_terrain() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = VoxelWorld.TERRAIN_SHADER
	TerrainTextures.apply(mat)
	var surface := PackedInt32Array()
	surface.resize(256)
	surface.fill(200)
	var biomes := PackedByteArray()
	biomes.resize(256)
	var x_chunks := int((_room_centre(MINE_ROOM).x + 40.0) / 16.0) + 1
	for kz in range(-1, 5):
		for ky in range(-5, 1):
			for kx in range(-1, x_chunks + 1):
				_chunk_data(Vector3i(kx, ky, kz))
	for kz in range(0, 4):
		for ky in range(-4, 0):
			for kx in range(0, x_chunks):
				var k := Vector3i(kx, ky, kz)
				var nb := []
				var dn := []
				nb.resize(27)
				dn.resize(27)
				for dz in range(-1, 2):
					for dy in range(-1, 2):
						for dx in range(-1, 2):
							var kk := k + Vector3i(dx, dy, dz)
							_chunk_data(kk)
							nb[(dx + 1) + (dy + 1) * 3 + (dz + 1) * 9] = _blocks[kk]
							dn[(dx + 1) + (dy + 1) * 3 + (dz + 1) * 9] = _dens[kk]
				var o := k * Chunk.SIZE
				var smooth := SmoothMesher.build(nb, dn, surface, biomes, o, 0)
				if not smooth.has("terrain"):
					continue
				var room := clampi(int(floor((o.x + 8.0 - 3.0) / SPACING)), 0, MINE_ROOM)
				var draw: Array = smooth["terrain"]
				if room == ORE_ROOM:
					# Show the decor on plain rock: the terrain shader's own ore speckle is not ours.
					draw = draw.duplicate()
					var codes: PackedFloat32Array = (draw[Mesh.ARRAY_CUSTOM0] as PackedFloat32Array).duplicate()
					for ci in codes.size():
						if CaveDecor.ORES.has(int(codes[ci])):
							codes[ci] = Blocks.STONE
					draw[Mesh.ARRAY_CUSTOM0] = codes
				var mesh := ArrayMesh.new()
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, draw, [], {}, SmoothMesher.format_flags())
				mesh.surface_set_material(0, mat)
				var mi := MeshInstance3D.new()
				mi.mesh = mesh
				mi.position = Vector3(o)
				add_child(mi)
				var kind := room if room < ORE_ROOM else (0 if room == ORE_ROOM else CaveDecor.MINE)
				var t0 := Time.get_ticks_usec()
				var plan := CaveDecor.plan_chunk(o, smooth["terrain"], 0, 1234, _blocks[k], kind)
				_plan_us += Time.get_ticks_usec() - t0
				_plan_chunks += 1
				if plan.is_empty():
					continue
				for key: int in plan["batches"]:
					_instances += int(plan["batches"][key][1])
				var node := CaveDecor.build_chunk(plan, _quality)
				if node != null:
					mi.add_child(node)
					_decor_nodes.append(node)
				for l: Array in plan["lights"]:
					_lights += 1
					var ol := OmniLight3D.new()
					ol.position = l[0]
					ol.light_color = l[1]
					ol.light_energy = 0.55 * float(l[2])
					ol.omni_range = 5.0 + float(l[2]) * 2.2
					ol.omni_attenuation = 1.6
					add_child(ol)


# --- Mine ---------------------------------------------------------------------------------------

func _build_mine() -> void:
	var c := _room_centre(MINE_ROOM)
	var floor_y := c.y - 1.8
	var props: Array = []
	for k in 10:
		var z := c.z - 13.0 + k * 3.0
		var t := "broken_set" if k == 6 else "timber_set"
		props.append({"type": t, "at": Vector3(c.x, floor_y, z), "yaw": 0.0, "width": 3.8, "height": 3.3, "lagging": k % 3 != 1})
		if k % 3 == 0:
			props.append({"type": "lantern", "at": Vector3(c.x + 1.1, floor_y + 3.0, z + 0.2), "lit": k != 9})
	props.append({"type": "rail", "a": Vector3(c.x, floor_y, c.z - 14.0), "b": Vector3(c.x, floor_y, c.z + 4.0)})
	props.append({"type": "rail", "a": Vector3(c.x, floor_y, c.z + 4.0), "b": Vector3(c.x + 1.0, floor_y, c.z + 16.0)})
	props.append({"type": "cart", "at": Vector3(c.x, floor_y + 0.08, c.z - 6.0), "yaw": 0.05, "tipped": false, "ore": Blocks.IRON_ORE})
	props.append({"type": "cart", "at": Vector3(c.x - 0.4, floor_y, c.z + 7.0), "yaw": 0.4, "tipped": true, "ore": Blocks.COPPER_ORE})
	props.append({"type": "crate", "at": Vector3(c.x - 1.45, floor_y, c.z - 10.0), "yaw": 0.2, "size": 0.8})
	props.append({"type": "crate", "at": Vector3(c.x - 1.4, floor_y + 0.8, c.z - 10.1), "yaw": -0.3, "size": 0.6})
	props.append({"type": "barrel", "at": Vector3(c.x + 1.45, floor_y, c.z - 9.0), "yaw": 0.0})
	props.append({"type": "tools", "at": Vector3(c.x - 1.5, floor_y, c.z - 3.0), "yaw": PI * 0.5})
	props.append({"type": "rubble", "at": Vector3(c.x + 0.8, floor_y, c.z + 3.5), "radius": 1.6})
	props.append({"type": "ladder", "at": Vector3(c.x + 1.6, floor_y, c.z + 10.5), "yaw": -PI * 0.5, "height": 4.0})
	var yard := Vector3(c.x, floor_y, c.z + 20.0)
	props.append({"type": "entrance", "at": yard + Vector3(-3.5, 0, 2.0), "yaw": 0.0, "width": 4.0, "height": 3.6})
	props.append({"type": "headframe", "at": yard + Vector3(3.5, 0, 2.5), "yaw": 0.3})
	props.append({"type": "spoil", "at": yard + Vector3(4.0, -0.2, -2.5), "radius": 2.6})
	var t0 := Time.get_ticks_usec()
	var result := MineDressing.plan(props, c)
	var node := MineDressing.build_node(result, c)
	add_child(node)
	print("[cave_gallery] mine plan+build %.1f ms, %d batches" % [(Time.get_ticks_usec() - t0) / 1000.0, (result["batches"] as Dictionary).size()])
	for p: Vector3 in result["lanterns"]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.66, 0.34)
		l.light_energy = 1.5
		l.omni_range = 9.0
		l.omni_attenuation = 1.4
		l.position = c + p + Vector3(0, -0.3, 0)
		add_child(l)


# --- Shots -------------------------------------------------------------------------------------

func _shots() -> Array:
	var out: Array = []
	for i in KIND_ROOMS.size():
		var c := _room_centre(i)
		out.append([KIND_ROOMS[i], c + Vector3(-8.5, -1.0, -6.5), c + Vector3(3, -1.5, 3)])
		out.append([KIND_ROOMS[i] + "_up", c + Vector3(5.0, -1.4, 4.0), c + Vector3(-4.0, 1.5, -4.5)])
	var oc := _room_centre(ORE_ROOM)
	for k in 7:
		# Two bands per shot: coal|iron, copper|tin, silver|gold, mithril|adamantite, ruby|sapphire, amethyst|ember, frost|obsidian.
		var x := oc.x - 12.0 + float(2 * k + 1) * 1.75
		out.append(["ores_%d" % k, Vector3(x, oc.y - 0.8, oc.z - 7.5), Vector3(x, oc.y - 0.6, oc.z - 12.0)])
	var mc := _room_centre(MINE_ROOM)
	out.append(["mine_drift", mc + Vector3(0.3, -0.2, -13.0), mc + Vector3(0, -0.6, 0)])
	out.append(["mine_cart", mc + Vector3(1.2, -0.6, -9.5), mc + Vector3(-0.2, -1.4, -6.0)])
	out.append(["mine_collapse", mc + Vector3(-1.0, -0.3, -1.5), mc + Vector3(0.5, -1.2, 5.0)])
	out.append(["mine_yard", mc + Vector3(-2.5, 1.2, 13.5), mc + Vector3(1.0, 2.0, 23.0)])
	return out


func _capture() -> void:
	for i in 30:
		await get_tree().process_frame
	var vp := _view.viewport.get_viewport_rid() if _view.viewport != null else get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for shot: Array in _shots():
		if _only != "" and not String(shot[0]).begins_with(_only):
			continue
		camera.global_position = shot[1]
		camera.look_at(shot[2], Vector3.UP)
		for i in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(img.get_width() / 2, img.get_height() / 2)
		img.save_jpg(_capture_dir.path_join("%s.jpg" % shot[0]), 0.85)
		printerr("[cave_gallery] shot ", shot[0])
	# GPU cost of the decor: same view (fungal hollow) with and without it.
	var c := _room_centre(2)
	camera.global_position = c + Vector3(-8.5, -1.0, -6.5)
	camera.look_at(c + Vector3(3, -1.5, 3), Vector3.UP)
	var with_decor: Array = await _gpu_ms(vp)
	for n in _decor_nodes:
		n.visible = false
	var without: Array = await _gpu_ms(vp)
	for n in _decor_nodes:
		n.visible = true
	print("[cave_gallery] fungal view: with decor %.2f ms GPU / %.2f ms frame, %d draws, %d prims; without %.2f ms GPU / %.2f ms frame, %d draws, %d prims" % (with_decor + without))
	get_tree().quit()


func _gpu_ms(vp: RID) -> Array:
	for i in 10:
		await get_tree().process_frame
	var gpu := 0.0
	var frame := 0.0
	for i in 40:
		await get_tree().process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		frame += get_process_delta_time() * 1000.0
	var draws := RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	return [gpu / 40.0, frame / 40.0, draws, prims]
