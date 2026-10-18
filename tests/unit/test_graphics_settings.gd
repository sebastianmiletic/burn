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
