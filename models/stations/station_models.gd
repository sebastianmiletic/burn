class_name StationModels
extends RefCounted
## Crafting stations, life size (1 unit = 1 m), front facing +Z, resting on
## y = 0. `live` adds fire, light, smoke and sparks (the in-world entity);
## icons build them without.
##   workbench  - pegged oak top, trestle legs, vise, saw, mallet, offcuts
##   furnace    - fieldstone bloomery with a brick arch, glowing coals, chimney, bellows
##   anvil      - forged horn anvil on an iron-banded stump, hammer, tongs, quench tub
##   alchemy    - dark table with alembic over a burner, flasks, mortar, books
##   campfire   - stone ring, leaned logs, embers; cooks food and lights the night


static func _p(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	return ModelKit.part(parent, mesh, mat, pos, rot, scl)


static func build(kind: String, live := false) -> Node3D:
	var root := Node3D.new()
	root.name = "Station_" + kind
	match kind:
		"workbench":
			workbench(root)
		"furnace":
			furnace(root, live)
		"anvil":
			anvil(root, live)
		"alchemy":
			alchemy(root, live)
		"campfire":
			campfire(root, live)
		_:
			workbench(root)
	return root


static func _oak(grain := Vector3.RIGHT) -> Material:
	return ItemMats.wood(Color(0.44, 0.35, 0.26), Color(0.24, 0.17, 0.1), grain)


static func _dark_oak(grain := Vector3.UP) -> Material:
	return ItemMats.wood(Color(0.3, 0.23, 0.17), Color(0.15, 0.1, 0.07), grain)


# --- Workbench ------------------------------------------------------------------------------

static func workbench(root: Node3D) -> void:
	var top_y := 0.86
	var oak := _oak()
	var dark := _dark_oak()
	# Top: five planks with small gaps and a thick front apron.
	for i in 5:
		var z := -0.3 + i * 0.152
		var shade := ItemMats.wood(Color(0.44, 0.35, 0.26).darkened(0.05 * (i % 3)), Color(0.24, 0.17, 0.1), Vector3.RIGHT)
		_p(root, ItemMesh.bevel_box(Vector3(1.4, 0.07, 0.146), 0.01), shade, Vector3(0, top_y, z))
	_p(root, ItemMesh.bevel_box(Vector3(1.42, 0.12, 0.06), 0.01), _dark_oak(Vector3.RIGHT), Vector3(0, top_y - 0.07, 0.36))
	# Trestle legs with stretchers and pegs.
	for sx: float in [-0.58, 0.58]:
		for sz: float in [-0.28, 0.28]:
			_p(root, ItemMesh.bevel_box(Vector3(0.09, top_y - 0.04, 0.09), 0.012), dark, Vector3(sx, (top_y - 0.04) * 0.5, sz), Vector3(0, 0, sx * 3.0))
		_p(root, ItemMesh.bevel_box(Vector3(0.07, 0.07, 0.62), 0.01), dark, Vector3(sx, 0.2, 0))
	_p(root, ItemMesh.bevel_box(Vector3(1.2, 0.07, 0.07), 0.01), dark, Vector3(0, 0.2, 0))
	# Lower shelf with offcuts.
	_p(root, ItemMesh.bevel_box(Vector3(1.12, 0.035, 0.5), 0.006), oak, Vector3(0, 0.25, 0))
	for i in 4:
		_p(root, ItemMesh.bevel_box(Vector3(0.4 - i * 0.05, 0.045, 0.1), 0.006), ItemMats.wood(Color(0.62, 0.45, 0.27).darkened(i * 0.06)), Vector3(-0.3 + i * 0.05, 0.29 + i * 0.046, -0.05 + i * 0.03), Vector3(0, i * 9.0, 0))
	_p(root, ItemMesh.lathe(PackedVector2Array([Vector2(0.07, -0.13), Vector2(0.075, 0.0), Vector2(0.07, 0.13)]), 12, true), ItemMats.bark(), Vector3(0.32, 0.345, 0.05), Vector3(0, 20, 90))
	# Front vise: jaw block, screw and tommy bar.
	_p(root, ItemMesh.bevel_box(Vector3(0.22, 0.2, 0.06), 0.01), dark, Vector3(-0.5, top_y - 0.07, 0.42))
	_p(root, ModelKit.cylinder(0.018, 0.018, 0.16, 10), ItemMats.metal("dark_iron"), Vector3(-0.5, top_y - 0.08, 0.48), Vector3(90, 0, 0))
	_p(root, ModelKit.cylinder(0.01, 0.01, 0.26, 8), ItemMats.wood(Color(0.62, 0.46, 0.28)), Vector3(-0.5, top_y - 0.08, 0.56), Vector3(0, 0, 90))
	# Tools on top: saw, mallet, chisel, a half-planed board with shavings.
	var steel := ItemMats.metal("steel")
	var saw := PackedVector2Array([Vector2(0, 0), Vector2(0.42, 0.0), Vector2(0.42, 0.04), Vector2(0, 0.1)])
	_p(root, ItemMesh.plate_even(saw, 0.0012, 0.0005), steel, Vector3(0.05, top_y + 0.037, 0.12), Vector3(-90, 15, 0))
	_p(root, ItemMesh.bevel_box(Vector3(0.12, 0.022, 0.1), 0.008), oak, Vector3(0.0, top_y + 0.047, 0.09), Vector3(0, 15, 0))
	_p(root, ModelKit.cylinder(0.04, 0.04, 0.13, 12), dark, Vector3(0.5, top_y + 0.075, -0.14), Vector3(0, 0, 90))
	_p(root, ModelKit.cylinder(0.014, 0.016, 0.22, 8), oak, Vector3(0.5, top_y + 0.05, -0.0), Vector3(90, 0, 0))
	_p(root, ItemMesh.bevel_box(Vector3(0.6, 0.03, 0.14), 0.005), ItemMats.wood(Color(0.7, 0.52, 0.32)), Vector3(-0.25, top_y + 0.05, -0.18), Vector3(0, -6, 0))
	_p(root, ItemMesh.bevel_box(Vector3(0.012, 0.006, 0.12), 0.002), steel, Vector3(0.22, top_y + 0.038, -0.02), Vector3(0, 70, 0))
	_p(root, ModelKit.cylinder(0.011, 0.012, 0.09, 8), oak, Vector3(0.28, top_y + 0.045, -0.04), Vector3(90, 70, 0))
	var shaving := ItemMats.wood(Color(0.82, 0.66, 0.44))
	for i in 5:
		var path := PackedVector3Array()
		var rr := PackedFloat32Array()
		for k in 7:
			var a := TAU * float(k) / 7.0
			path.append(Vector3(-0.05 + i * 0.045 + cos(a) * 0.015, top_y + 0.05 + sin(a) * 0.015, -0.05 + float(k) * 0.006))
			rr.append(0.004)
		_p(root, ItemMesh.tube(path, rr, 4), shaving)
	# Wall-hung tool rack at the back.
	_p(root, ItemMesh.bevel_box(Vector3(1.2, 0.08, 0.04), 0.008), dark, Vector3(0, top_y + 0.36, -0.36))
	for sx: float in [-0.56, 0.56]:
		_p(root, ItemMesh.bevel_box(Vector3(0.06, 0.42, 0.05), 0.008), dark, Vector3(sx, top_y + 0.2, -0.36))
	var tools := Node3D.new()
	root.add_child(tools)
	tools.position = Vector3(-0.3, top_y + 0.42, -0.32)
	tools.rotation_degrees = Vector3(0, 0, 180)
	tools.scale = Vector3.ONE * 0.62
	GearModels.axe(tools, "copper")
	var hammer := Node3D.new()
	root.add_child(hammer)
	hammer.position = Vector3(0.25, top_y + 0.42, -0.32)
	hammer.rotation_degrees = Vector3(0, 0, 180)
	hammer.scale = Vector3.ONE * 0.5
	GearModels.pickaxe(hammer, "stone")


# --- Furnace -------------------------------------------------------------------------------------

static func furnace(root: Node3D, live: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1931
	var stones := [Color(0.45, 0.43, 0.4), Color(0.38, 0.36, 0.34), Color(0.5, 0.47, 0.42), Color(0.42, 0.38, 0.35)]
	var soot := ItemMats.stone(Color(0.12, 0.11, 0.1), Color(0.05, 0.05, 0.05), 0.95)
	# Core mass (rendered behind the fieldstones so gaps look like mortar).
	_p(root, ItemMesh.lathe(PackedVector2Array([Vector2(0.6, 0.0), Vector2(0.58, 0.5), Vector2(0.5, 0.9), Vector2(0.34, 1.15), Vector2(0.22, 1.25), Vector2(0.0, 1.27)]), 18, true, Vector2(1.0, 0.9)),
		ItemMats.stone(Color(0.3, 0.28, 0.26), Color(0.2, 0.19, 0.18), 0.95))
	# Fieldstone courses laid around the dome, leaving the mouth open at the front.
	for course in 7:
		var y := 0.08 + course * 0.16
		var r := _dome_radius(y) + 0.03
		var n := int(15 - course * 1.2)
		for i in n:
			var a := TAU * (float(i) + 0.5 * (course % 2)) / float(n)
			var front := absf(wrapf(a - PI * 0.5, -PI, PI)) < 0.42 and course < 3
			if front:
				continue
			var pos := Vector3(cos(a) * r, y, sin(a) * r * 0.9)
			var sz := Vector3(0.3 + rng.randf() * 0.06, 0.17, 0.16) * lerpf(1.0, 0.7, course / 6.0)
			_p(root, ItemMesh.rock(0.5, course * 31 + i, 0.14, 1, sz), ItemMats.stone(stones[rng.randi() % stones.size()], Color(0.3, 0.28, 0.26)),
				pos, Vector3(0, 90.0 - rad_to_deg(a), rng.randf_range(-6, 6)))
	# Brick arch around the mouth.
	var brick := ItemMats.stone(Color(0.6, 0.3, 0.22), Color(0.35, 0.17, 0.12), 0.9)
	for i in 9:
		var a := PI * float(i) / 8.0
		var pos := Vector3(cos(a) * 0.27, 0.04 + sin(a) * 0.3, 0.58)
		_p(root, ItemMesh.bevel_box(Vector3(0.07, 0.12, 0.1), 0.006), brick, pos, Vector3(0, 0, rad_to_deg(a) - 90.0))
	# Firebox: sooty inner chamber, coals and embers.
	_p(root, ItemMesh.lathe(PackedVector2Array([Vector2(0.23, 0.0), Vector2(0.23, 0.2), Vector2(0.15, 0.3), Vector2(0.0, 0.32)]), 14, true, Vector2(1.0, 1.4)), soot, Vector3(0, 0.04, 0.36))
	var coal_glow := ItemMats.molten(Color(0.12, 0.06, 0.04), Color(1.0, 0.36, 0.08), 9.0)
	for i in 9:
		var p := Vector3(rng.randf_range(-0.16, 0.16), 0.07 + rng.randf() * 0.04, 0.36 + rng.randf_range(-0.12, 0.2))
		_p(root, ItemMesh.rock(0.045, 200 + i, 0.3, 1), coal_glow, p)
	_p(root, ModelKit.sphere(0.12, 10), ItemMats.glow(Color(1.0, 0.5, 0.15), 4.0), Vector3(0, 0.12, 0.38), Vector3.ZERO, Vector3(1.3, 0.35, 1.2))
	# Chimney stack.
	_p(root, ItemMesh.lathe(PackedVector2Array([Vector2(0.2, 1.1), Vector2(0.17, 1.35), Vector2(0.16, 1.62), Vector2(0.19, 1.66), Vector2(0.19, 1.72), Vector2(0.13, 1.72), Vector2(0.13, 1.4)]), 12, true), brick)
	_p(root, ModelKit.cylinder(0.125, 0.125, 0.02, 12), soot, Vector3(0, 1.71, 0))
	# Bellows on the side, iron ring tools and a coal pile.
	var leather := ItemMats.leather(Color(0.36, 0.22, 0.13))
	_p(root, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, -0.2), Vector2(0.12, -0.16), Vector2(0.16, 0.0), Vector2(0.12, 0.14), Vector2(0.0, 0.18)]), 12, true, Vector2(1.0, 0.3)), leather, Vector3(0.78, 0.35, 0.15), Vector3(0, 0, 90))
	for side: float in [-1.0, 1.0]:
		_p(root, ItemMesh.bevel_box(Vector3(0.36, 0.03, 0.3), 0.008), _dark_oak(), Vector3(0.78, 0.35 + side * 0.06, 0.15), Vector3(0, 0, side * 8.0))
	_p(root, ModelKit.cylinder(0.02, 0.03, 0.3, 8), ItemMats.metal("dark_iron"), Vector3(0.6, 0.3, 0.15), Vector3(0, 0, 90))
	var coal := ItemMats.make({"albedo": Color(0.07, 0.07, 0.075), "accent": Color(0.3, 0.3, 0.35), "roughness": 0.35, "finish": ItemMats.Finish.ORE})
	for i in 8:
		_p(root, ItemMesh.rock(0.06, 300 + i, 0.3, 1), coal, Vector3(-0.72 + rng.randf_range(-0.12, 0.12), 0.04 + (0.05 if i < 3 else 0.0), 0.35 + rng.randf_range(-0.12, 0.12)))
	if live:
		_furnace_fx(root)


## Radius of the furnace's core dome at height y (matches its lathe profile).
static func _dome_radius(y: float) -> float:
	var prof := [Vector2(0.6, 0.0), Vector2(0.58, 0.5), Vector2(0.5, 0.9), Vector2(0.34, 1.15), Vector2(0.22, 1.25)]
	for i in prof.size() - 1:
		var a: Vector2 = prof[i]
		var b: Vector2 = prof[i + 1]
		if y <= b.y:
			return lerpf(a.x, b.x, clampf((y - a.y) / (b.y - a.y), 0.0, 1.0))
	return 0.2


static func _furnace_fx(root: Node3D) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.52, 0.22)
	light.light_energy = 2.4
	light.omni_range = 7.0
	light.omni_attenuation = 1.4
	light.light_volumetric_fog_energy = 1.4
	light.position = Vector3(0, 0.35, 0.75)
	root.add_child(light)
	var flicker := FireFlicker.new()
	flicker.light = light
	flicker.base = 2.4
	root.add_child(flicker)
	var flames := ModelKit.embers(root, 26, Vector3(0.14, 0.04, 0.1), 0.6, 0.16, 0.9)
	flames.position = Vector3(0, 0.14, 0.4)
	flames.emitting = true
	var sparks := ModelKit.embers(root, 10, Vector3(0.06, 0.02, 0.06), 1.6, 0.03, 2.2)
	sparks.position = Vector3(0, 1.7, 0)
	sparks.emitting = true
	root.add_child(smoke(Vector3(0, 1.75, 0)))


## Soft grey smoke rising from a chimney (alpha-blended, drawn over the glyphs).
static func smoke(pos: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 18
	p.lifetime = 4.0
	p.local_coords = false
	p.position = pos
	p.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 9, 8))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.08
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 0.35
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0.25, 0.12, 0.05)
	pm.damping_min = 0.1
	pm.damping_max = 0.3
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	var c := Curve.new()
	c.add_point(Vector2(0, 0.35))
	c.add_point(Vector2(1, 1.6))
	var ct := CurveTexture.new()
	ct.curve = c
	pm.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(0.3, 0.29, 0.28, 0.0))
	g.add_point(0.12, Color(0.26, 0.25, 0.24, 0.22))
	g.set_color(g.get_point_count() - 1, Color(0.4, 0.4, 0.4, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.55)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var tg := Gradient.new()
	tg.set_color(0, Color(1, 1, 1, 1))
	tg.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = tg
	tex.width = 64
	tex.height = 64
	mat.albedo_texture = tex
	quad.material = mat
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = true
	return p


# --- Anvil --------------------------------------------------------------------------------------

static func anvil(root: Node3D, live: bool) -> void:
	var iron := ItemMats.metal("dark_iron")
	var face := ItemMats.metal("steel")
	# Stump with iron bands.
	_p(root, ItemMesh.lathe(PackedVector2Array([Vector2(0.3, 0.0), Vector2(0.27, 0.06), Vector2(0.25, 0.3), Vector2(0.25, 0.5), Vector2(0.0, 0.5)]), 16, true), ItemMats.bark(Color(0.3, 0.22, 0.15)))
	_p(root, ModelKit.cylinder(0.245, 0.245, 0.012, 20), ItemMats.wood(Color(0.62, 0.46, 0.3), Color(0.35, 0.22, 0.12)), Vector3(0, 0.5, 0))
	for y: float in [0.12, 0.4]:
		_p(root, ItemMesh.lathe(PackedVector2Array([Vector2(0.262, y - 0.025), Vector2(0.27, y - 0.02), Vector2(0.27, y + 0.02), Vector2(0.262, y + 0.025)]), 18, true), iron)
	# Anvil body: feet, waist, body, face, horn and heel.
	var base_y := 0.5
	var feet := PackedVector2Array([Vector2(-0.24, 0.0), Vector2(0.24, 0.0), Vector2(0.2, 0.05), Vector2(0.09, 0.1), Vector2(0.1, 0.18), Vector2(0.2, 0.2),
		Vector2(0.21, 0.28), Vector2(-0.21, 0.28), Vector2(-0.2, 0.2), Vector2(-0.1, 0.18), Vector2(-0.09, 0.1), Vector2(-0.2, 0.05)])
	_p(root, ItemMesh.plate_even(feet, 0.11, 0.012), iron, Vector3(0, base_y, 0), Vector3(0, 90, 0))
	_p(root, ItemMesh.bevel_box(Vector3(0.44, 0.08, 0.16), 0.014), iron, Vector3(0, base_y + 0.3, 0))
	_p(root, ItemMesh.bevel_box(Vector3(0.45, 0.012, 0.15), 0.004), face, Vector3(0, base_y + 0.346, 0))
	var horn := PackedVector3Array([Vector3(0.22, base_y + 0.3, 0), Vector3(0.3, base_y + 0.3, 0), Vector3(0.38, base_y + 0.31, 0), Vector3(0.45, base_y + 0.325, 0)])
	_p(root, ItemMesh.tube(horn, PackedFloat32Array([0.05, 0.04, 0.022, 0.004]), 12), iron)
	_p(root, ItemMesh.bevel_box(Vector3(0.1, 0.06, 0.12), 0.01), iron, Vector3(-0.26, base_y + 0.31, 0))
	_p(root, ItemMesh.bevel_box(Vector3(0.022, 0.014, 0.022), 0.002), ItemMats.make({"albedo": Color(0.02, 0.02, 0.02), "roughness": 1.0}), Vector3(-0.24, base_y + 0.347, 0))
	# Hammer resting on the face, tongs leaning on the stump.
	var hammer := Node3D.new()
	root.add_child(hammer)
	hammer.position = Vector3(-0.05, base_y + 0.37, 0.02)
	hammer.rotation_degrees = Vector3(90, 0, -70)
	hammer.scale = Vector3.ONE * 0.48
	GearModels.warhammer(hammer, "iron")
	for side: float in [-1.0, 1.0]:
		_p(root, ItemMesh.tube(PackedVector3Array([Vector3(0.25, 0.02, 0.2), Vector3(0.24 + side * 0.01, 0.35, 0.24), Vector3(0.22 + side * 0.03, 0.55, 0.26)]),
			PackedFloat32Array([0.008, 0.008, 0.009]), 6), iron)
	# Quench tub.
	_p(root, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.2, 0.0), Vector2(0.22, 0.32), Vector2(0.2, 0.32), Vector2(0.18, 0.04), Vector2(0.0, 0.04)]), 18, true), _dark_oak(), Vector3(-0.55, 0, 0.2))
	for y: float in [0.06, 0.26]:
		_p(root, ItemMesh.lathe(PackedVector2Array([Vector2(0.205 + y * 0.06, y - 0.015), Vector2(0.215 + y * 0.06, y), Vector2(0.205 + y * 0.06, y + 0.015)]), 18, true), iron, Vector3(-0.55, 0, 0.2))
	var water := ItemMats.make({"albedo": Color(0.05, 0.08, 0.1), "roughness": 0.05, "specular_amount": 0.8, "ascii_id": AsciiMaterialId.LIQUID, "bump_amount": 0.0})
	_p(root, ModelKit.cylinder(0.19, 0.19, 0.01, 18), water, Vector3(-0.55, 0.28, 0.2))
	# A glowing billet on the face, cooling.
	_p(root, ItemMesh.bevel_box(Vector3(0.16, 0.022, 0.03), 0.004), ItemMats.glow(Color(1.0, 0.45, 0.12), 3.5), Vector3(0.08, base_y + 0.363, -0.03), Vector3(0, 12, 0))
	if live:
		var sparks := ModelKit.embers(root, 6, Vector3(0.08, 0.01, 0.03), 0.7, 0.025, 1.4)
		sparks.position = Vector3(0.08, base_y + 0.38, -0.03)
		sparks.emitting = true
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.55, 0.25)
		l.light_energy = 0.7
		l.omni_range = 2.5
		l.position = Vector3(0.08, base_y + 0.5, 0.0)
		root.add_child(l)


# --- Alchemy table ----------------------------------------------------------------------------------

static func alchemy(root: Node3D, live: bool) -> void:
	var dark := ItemMats.wood(Color(0.28, 0.18, 0.12), Color(0.12, 0.08, 0.05))
	var top_y := 0.84
	_p(root, ItemMesh.bevel_box(Vector3(1.3, 0.06, 0.66), 0.012), dark, Vector3(0, top_y, 0))
	for sx: float in [-0.56, 0.56]:
		for sz: float in [-0.26, 0.26]:
			_p(root, ItemMesh.lathe(PackedVector2Array([Vector2(0.035, 0.0), Vector2(0.045, 0.06), Vector2(0.03, 0.2), Vector2(0.045, 0.4), Vector2(0.03, 0.62), Vector2(0.045, top_y - 0.03)]), 10, true), dark, Vector3(sx, 0, sz))
	_p(root, ItemMesh.bevel_box(Vector3(1.1, 0.03, 0.5), 0.006), dark, Vector3(0, 0.2, 0))
	# Embroidered runner cloth.
	_p(root, ItemMesh.bevel_box(Vector3(1.32, 0.008, 0.22), 0.002), ItemMats.cloth(Color(0.35, 0.12, 0.32)), Vector3(0, top_y + 0.034, 0.05))
	# Brass burner, glass alembic with tubing to a receiver flask.
	var brass := ItemMats.metal("brass")
	_p(root, ItemMesh.lathe(PackedVector2Array([Vector2(0.07, 0.0), Vector2(0.07, 0.02), Vector2(0.03, 0.04), Vector2(0.03, 0.08), Vector2(0.0, 0.08)]), 14, true), brass, Vector3(-0.3, top_y + 0.03, -0.05))
	_p(root, ModelKit.sphere(0.03, 8), ItemMats.glow(Color(0.4, 0.6, 1.0), 4.0), Vector3(-0.3, top_y + 0.13, -0.05), Vector3.ZERO, Vector3(0.7, 1.2, 0.7))
	for i in 3:
		var a := TAU * float(i) / 3.0
		_p(root, ModelKit.cylinder(0.005, 0.005, 0.2, 5), ItemMats.metal("dark_iron"), Vector3(-0.3 + cos(a) * 0.09, top_y + 0.13, -0.05 + sin(a) * 0.09), Vector3(sin(a) * 10.0, 0, cos(a) * -10.0))
	var glass := ItemMats.glass(Color(0.75, 0.9, 0.85))
	var flask := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.05, 0.01), Vector2(0.08, 0.06), Vector2(0.075, 0.12), Vector2(0.04, 0.16), Vector2(0.02, 0.2), Vector2(0.02, 0.24), Vector2(0.0, 0.24)])
	_p(root, ItemMesh.lathe(flask, 16, true), glass, Vector3(-0.3, top_y + 0.22, -0.05))
	_p(root, ItemMesh.lathe(PackedVector2Array([Vector2(0.0, 0.01), Vector2(0.06, 0.03), Vector2(0.07, 0.07), Vector2(0.0, 0.07)]), 16, true), ItemMats.liquid(Color(0.2, 0.9, 0.5)), Vector3(-0.3, top_y + 0.22, -0.05))
	_p(root, ItemMesh.tube(PackedVector3Array([Vector3(-0.29, top_y + 0.46, -0.05), Vector3(-0.2, top_y + 0.48, -0.05), Vector3(-0.05, top_y + 0.36, -0.05), Vector3(0.05, top_y + 0.2, -0.05)]),
		PackedFloat32Array([0.012, 0.01, 0.008, 0.008]), 8), glass)
	potion_set(root, top_y + 0.035)
	# Mortar and pestle, open book, candle.
	var stone := ItemMats.stone(Color(0.6, 0.58, 0.54), Color(0.4, 0.4, 0.38), 0.7)
	_p(root, ItemMesh.lathe(PackedVector2Array([Vector2(0.06, 0.0), Vector2(0.075, 0.05), Vector2(0.07, 0.08), Vector2(0.055, 0.08), Vector2(0.05, 0.03), Vector2(0.0, 0.025)]), 16, true), stone, Vector3(0.45, top_y + 0.035, -0.15))
	_p(root, ModelKit.cylinder(0.012, 0.018, 0.16, 8), stone, Vector3(0.48, top_y + 0.13, -0.15), Vector3(0, 0, -25))
	var page := ItemMats.cloth(Color(0.86, 0.8, 0.66))
	for side: float in [-1.0, 1.0]:
		_p(root, ItemMesh.bevel_box(Vector3(0.16, 0.02, 0.22), 0.004), page, Vector3(0.18 + side * 0.085, top_y + 0.05, 0.16), Vector3(0, 0, side * -6.0))
	_p(root, ItemMesh.bevel_box(Vector3(0.36, 0.012, 0.24), 0.003), ItemMats.leather(Color(0.4, 0.12, 0.1)), Vector3(0.18, top_y + 0.038, 0.16))
	_p(root, ModelKit.cylinder(0.016, 0.018, 0.1, 10), ItemMats.food(Color(0.92, 0.88, 0.75), 0.5), Vector3(0.55, top_y + 0.085, 0.2))
	_p(root, ModelKit.sphere(0.012, 6), ItemMats.glow(Color(1.0, 0.75, 0.35), 5.0), Vector3(0.55, top_y + 0.15, 0.2), Vector3.ZERO, Vector3(0.7, 1.4, 0.7))
	# Hanging herbs on a back rail.
	_p(root, ItemMesh.bevel_box(Vector3(1.2, 0.04, 0.04), 0.006), dark, Vector3(0, top_y + 0.62, -0.3))
	for sx: float in [-0.58, 0.58]:
		_p(root, ItemMesh.bevel_box(Vector3(0.04, 0.62, 0.04), 0.006), dark, Vector3(sx, top_y + 0.31, -0.3))
	var herb := ItemMats.make({"albedo": Color(0.35, 0.45, 0.2), "accent": Color(0.6, 0.3, 0.15), "roughness": 0.8, "finish": ItemMats.Finish.WOOD, "ascii_id": AsciiMaterialId.FOLIAGE})
	for i in 5:
		_p(root, ModelKit.cone(0.04, 0.18, 6), herb, Vector3(-0.45 + i * 0.22, top_y + 0.5, -0.3), Vector3(180, i * 30.0, 0))
	if live:
		var l := OmniLight3D.new()
		l.light_color = Color(0.55, 0.75, 1.0)
		l.light_energy = 0.9
		l.omni_range = 3.5
		l.position = Vector3(-0.3, top_y + 0.3, 0.1)
		root.add_child(l)
		var f := FireFlicker.new()
		f.light = l
		f.base = 0.9
		root.add_child(f)


static func potion_set(root: Node3D, y: float) -> void:
	var specs := [["potion_health", Vector3(0.0, 0, -0.15)], ["potion_greater", Vector3(0.1, 0, -0.2)], ["potion_might", Vector3(0.22, 0, -0.18)],
		["potion_ironskin", Vector3(-0.08, 0, 0.18)], ["potion_phoenix", Vector3(-0.5, 0, 0.15)]]
	for s: Array in specs:
		var n := Node3D.new()
		root.add_child(n)
		n.position = Vector3(0, y, 0) + s[1]
		n.scale = Vector3.ONE * 1.4
		GoodsModels.potion(n, s[0])


# --- Campfire -----------------------------------------------------------------------------------

## A ring of fieldstones round an ash bed, split logs leaned into a cone,
## glowing embers and (live) flames, sparks, smoke and warm flickering light.
static func campfire(root: Node3D, live: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	var stones := [Color(0.46, 0.44, 0.41), Color(0.38, 0.36, 0.33), Color(0.52, 0.49, 0.44)]
	for i in 11:
		var a := TAU * float(i) / 11.0 + rng.randf_range(-0.08, 0.08)
		var r := 0.5 + rng.randf_range(-0.03, 0.03)
		var sz := Vector3(0.2, 0.13, 0.15) * rng.randf_range(0.85, 1.15)
		_p(root, ItemMesh.rock(0.5, 400 + i, 0.22, 1, sz), ItemMats.stone(stones[rng.randi() % stones.size()], Color(0.25, 0.24, 0.22)),
			Vector3(cos(a) * r, 0.05, sin(a) * r), Vector3(rng.randf_range(-8, 8), 90.0 - rad_to_deg(a), rng.randf_range(-8, 8)))
	# Ash bed with charred stubs.
	_p(root, ModelKit.cylinder(0.4, 0.42, 0.03, 16), ItemMats.stone(Color(0.17, 0.16, 0.15), Color(0.08, 0.08, 0.08), 0.98), Vector3(0, 0.015, 0))
	var char_mat := ItemMats.stone(Color(0.09, 0.07, 0.06), Color(0.03, 0.03, 0.03), 0.9)
	var bark := ItemMats.bark()
	# Five split logs leaned together into a cone.
	for i in 5:
		var a := TAU * float(i) / 5.0 + 0.3
		var lean := 52.0 + rng.randf_range(-5, 5)
		var log_node := Node3D.new()
		root.add_child(log_node)
		log_node.position = Vector3(cos(a) * 0.2, 0.0, sin(a) * 0.2)
		log_node.rotation_degrees = Vector3(0, 90.0 - rad_to_deg(a), 0)
		var pivot := Node3D.new()
		log_node.add_child(pivot)
		pivot.rotation_degrees = Vector3(0, 0, lean)
		_p(pivot, ModelKit.cylinder(0.045, 0.055, 0.5, 9), bark, Vector3(0, 0.25, 0))
		_p(pivot, ModelKit.cylinder(0.04, 0.047, 0.12, 9), char_mat, Vector3(0, 0.47, 0))
	# Embers under the cone.
	var ember := ItemMats.molten(Color(0.1, 0.05, 0.03), Color(1.0, 0.38, 0.08), 7.0)
	for i in 10:
		var p := Vector3(rng.randf_range(-0.18, 0.18), 0.04, rng.randf_range(-0.18, 0.18))
		_p(root, ItemMesh.rock(0.04, 500 + i, 0.3, 1), ember, p)
	if not live:
		return
	_p(root, ModelKit.sphere(0.14, 10), ItemMats.glow(Color(1.0, 0.5, 0.15), 4.5), Vector3(0, 0.12, 0), Vector3.ZERO, Vector3(1.2, 0.6, 1.2))
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.56, 0.24)
	light.light_energy = 2.8
	light.omni_range = 9.0
	light.omni_attenuation = 1.3
	light.shadow_enabled = true
	light.light_volumetric_fog_energy = 1.2
	light.position = Vector3(0, 0.55, 0)
	root.add_child(light)
	var flicker := FireFlicker.new()
	flicker.light = light
	flicker.base = 2.8
	root.add_child(flicker)
	var flames := ModelKit.embers(root, 34, Vector3(0.14, 0.05, 0.14), 0.7, 0.2, 1.0)
	flames.position = Vector3(0, 0.12, 0)
	flames.emitting = true
	var sparks := ModelKit.embers(root, 12, Vector3(0.08, 0.04, 0.08), 1.8, 0.03, 2.4)
	sparks.position = Vector3(0, 0.45, 0)
	sparks.emitting = true
	root.add_child(smoke(Vector3(0, 0.8, 0)))


## Flickering firelight.
class FireFlicker:
	extends Node
	var light: OmniLight3D
	var base := 2.0
	var _t := randf() * 10.0

	func _process(delta: float) -> void:
		_t += delta
		if light != null:
			light.light_energy = base * (1.0 + sin(_t * 13.0) * 0.07 + sin(_t * 5.3) * 0.1 + sin(_t * 29.0) * 0.04)
