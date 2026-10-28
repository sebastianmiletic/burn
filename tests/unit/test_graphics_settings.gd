extends TestCase
## Graphics presets, per-option overrides ("Custom") and that every preset
## re-applies a complete environment with nothing left from the previous one.


func _snapshot() -> Dictionary:
	return (Settings._data["graphics"] as Dictionary).duplicate()


func _restore(snap: Dictionary) -> void:
	Settings._data["graphics"] = snap
	Settings.changed.emit("graphics", "quality")


func test_presets_cover_every_option() -> void:
	for key: String in Settings.GFX_PRESETS:
		check_eq((Settings.GFX_PRESETS[key] as Array).size(), 4, "%s has a value per preset" % key)
		check(Settings.DEFAULTS["graphics"].has(key), "%s is a stored option" % key)
		check_eq(int(Settings.DEFAULTS["graphics"][key]), -1, "%s follows the preset by default" % key)


func test_override_makes_custom_and_preset_clears_it() -> void:
	var snap := _snapshot()
	Settings.apply_quality_preset(Settings.Quality.HIGH)
	check(not Settings.graphics_is_custom(), "a fresh preset is not custom")
	check_eq(Settings.gfx("shadows"), Settings.GFX_PRESETS["shadows"][2])
	Settings.set_value("graphics", "shadows", 0)
	check(Settings.graphics_is_custom(), "an override differing from the preset is custom")
	check_eq(Settings.gfx("shadows"), 0, "the override is in effect")
	Settings.apply_quality_preset(Settings.Quality.LOW)
	check(not Settings.graphics_is_custom(), "choosing a preset clears overrides")
	check_eq(Settings.gfx("shadows"), Settings.GFX_PRESETS["shadows"][0])
	check_eq(GraphicsQuality.view_radius(), Settings.GFX_PRESETS["view_distance"][0])
	_restore(snap)


func test_switching_presets_leaves_no_leftovers() -> void:
	var snap := _snapshot()
	var env := Environment.new()
	Settings.apply_quality_preset(Settings.Quality.ULTRA)
	GraphicsQuality.apply_environment(env)
	var fp := GraphicsQuality.forward_plus()
	check_eq(env.ssil_enabled, fp, "Ultra: bounce light where supported")
	Settings.apply_quality_preset(Settings.Quality.LOW)
	GraphicsQuality.apply_environment(env)
	check(not env.ssil_enabled and not env.sdfgi_enabled and not env.ssr_enabled and not env.ssao_enabled, "Low: no screen-space effects or GI")
	check(not env.volumetric_fog_enabled, "Low: no volumetric fog")
	var sun := DirectionalLight3D.new()
	GraphicsQuality.apply_directional(sun, true)
	check_eq(sun.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
	check_near(sun.directional_shadow_max_distance, GraphicsQuality.SHADOW_DISTANCE[1], 0.01)
	sun.free()
	_restore(snap)


func test_flora_requalify_changes_built_chunks() -> void:
	var snap := _snapshot()
	Settings.apply_quality_preset(Settings.Quality.HIGH)
	Flora.warmup()
	var tiers := PackedInt32Array([4, 3, 2, 1])
	var buf := PackedFloat32Array()
	buf.resize(10 * 16)
	for i in 10:
		buf[i * 16] = 1.0
		buf[i * 16 + 5] = 1.0
		buf[i * 16 + 10] = 1.0
	var plan := {"groups": [{"layer": Flora.L.GRASS, "buf": buf, "count": 10, "aabb": AABB(Vector3.ZERO, Vector3.ONE), "tiers": tiers}]}
	var root := Flora.build_chunk(plan, 2)
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(root)
	var mmi := root.get_child(root.get_child_count() - 1) as MultiMeshInstance3D
	check_eq(mmi.multimesh.visible_instance_count, 9, "High draws three of four tiers")
	Flora.requalify(tree, 0)
	check_eq(mmi.multimesh.visible_instance_count, 4, "Low draws one tier after a live change")
	root.free()
	Flora.requalify(tree, 2)
	_restore(snap)


func test_settings_menu_builds_graphics_tab() -> void:
	var menu := SettingsMenu.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(menu)
	check(menu._gfx_preset != null, "preset selector exists")
	check(menu._gfx_page.get_child_count() > 30, "every graphics option has a row")
	menu.free()


func test_render_scale_is_native_fraction_and_sharp() -> void:
	# High renders a 1080p screen at native and a Retina MacBook near 0.75,
	# never the old half-resolution (0.5 of physical pixels) that looked blurry.
	check_near(GraphicsQuality.preset_scale(Settings.Quality.HIGH, Vector2i(1920, 1080)), 1.0, 0.001, "High: 1080p native")
	var retina := Vector2i(2940, 1846)
	var high := GraphicsQuality.preset_scale(Settings.Quality.HIGH, retina)
	check(high >= 0.6 and high <= 0.8, "High on Retina renders 60-80%% of native (got %.2f)" % high)
	check(high * GraphicsQuality.ADAPT_FLOOR[Settings.Quality.HIGH] >= 0.45, "adaptive resolution keeps High near half native at worst")
	for q in 3:
		check(GraphicsQuality.preset_scale(q + 1, retina) >= GraphicsQuality.preset_scale(q, retina), "each preset at least as sharp as the one below")
	check(GraphicsQuality.preset_scale(Settings.Quality.LOW, Vector2i(3840, 2160)) >= 0.4, "Low floor on 4K")
	check(GraphicsQuality.preset_scale(Settings.Quality.ULTRA, Vector2i(1280, 720)) <= 1.0, "never supersamples")


func test_presets_pick_sensible_antialiasing() -> void:
	var snap := _snapshot()
	var aa: Array = Settings.GFX_PRESETS["antialiasing"]
	check_eq(int(aa[Settings.Quality.LOW]), 1, "Low: FXAA")
	check_eq(int(aa[Settings.Quality.MEDIUM]), 5, "Medium: SMAA")
	check_eq(int(aa[Settings.Quality.HIGH]), 2, "High: TAA")
	check_eq(int(aa[Settings.Quality.ULTRA]), 2, "Ultra: TAA")
	check(not bool(Settings.DEFAULTS["graphics"]["altitude_blur"]), "mountain blur is off by default")
	check(float(Settings.DEFAULTS["graphics"]["sharpness"]) >= 0.7, "upscaler sharpening on by default")
	Settings.set_value("graphics", "render_scale", 0.85)
	check_near(Settings.render_scale(Vector2i(2940, 1846)), 0.85, 0.001, "a forced 3D resolution is a fraction of native")
	_restore(snap)
