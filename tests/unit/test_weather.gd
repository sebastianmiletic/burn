extends TestCase
## Weather tables, the summoning API and the cave light palettes.


func test_every_state_has_levels_chain_and_duration() -> void:
	for s: String in Weather.STATES:
		check(Weather.LEVELS.has(s), "levels for %s" % s)
		check_eq((Weather.LEVELS[s] as Array).size(), Weather.CHANNELS, "channels of %s" % s)
		check(Weather.CHAIN.has(s), "successors for %s" % s)
		check(Weather.DURATION.has(s), "duration for %s" % s)
		for o: Array in Weather.CHAIN[s]:
			check(Weather.LEVELS.has(o[0]), "%s -> %s is a known state" % [s, o[0]])
	check_eq(Weather.RATE_UP.size(), Weather.CHANNELS)
	check_eq(Weather.RATE_DOWN.size(), Weather.CHANNELS)


func test_request_applies_and_holds() -> void:
	var w := Weather.new()
	check(not w.request("not_a_weather", 30.0), "unknown states are refused")
	check(w.request("blizzard", 120.0, 7), "known states are accepted on the host")
	check_eq(w.state_name(), "blizzard")
	check_near(w.hold_left(), 120.0, 0.001)
	w.request("aurora", 5000.0)
	check_near(w.hold_left(), 900.0, 0.001, "hold is capped")
	w.free()


func test_events_drive_their_channels() -> void:
	var w := Weather.new()
	check(w.request("snow", 60.0), "snow can be summoned (frost charm)")
	w.force("ember_storm")
	check(w.ember_amount() > 0.4, "ember storm shows embers")
	w.force("aurora")
	check_near(w.aurora_amount(), 1.0, 0.001)
	w.force("meteor_shower")
	check_near(w.meteor_amount(), 1.0, 0.001)
	w.force("heatwave")
	check(w.heat_amount() > 0.9 and w.overcast() < 0.01, "heatwave is hot and clear")
	w.force("dust_storm")
	check(w.dust_amount() > 0.5, "dust storm carries dust everywhere")
	w.force("clear")
	check_near(w.visibility(), 1.0, 0.001, "clear air sees far")
	w.free()


func test_underworld_smoke_preserves_material_colours() -> void:
	var sky := SkyController.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(sky)
	sky.set_dimension(1)
	sky._update_lights(0.0, true)
	var env := sky.environment
	check(env.fog_light_color.r < env.fog_light_color.g * 1.5, "smoke is warm grey, not saturated red")
	check(env.volumetric_fog_density <= 0.006, "open arenas have thin local haze")
	check(env.volumetric_fog_emission.r <= 0.01, "fog does not flood the arena with emitted red light")
	sky.free()


func test_cave_palettes_are_dark_and_tinted() -> void:
	for kind: int in CaveBiomes.PALETTES:
		var p: Dictionary = CaveBiomes.PALETTES[kind]
		var fog: Color = p["fog"]
		check(fog.get_luminance() < 0.08, "cave murk stays dark (kind %d)" % kind)
		check((p["bounce"] as Color).get_luminance() < 0.3, "bounce is a fill, not daylight (kind %d)" % kind)
	var mine := CaveBiomes.palette_at(Vector3(0, -20, 0), 1, 0, 2, "old_ember_mine")
	check_eq(mine, CaveBiomes.MINE_PALETTE)
	check_eq(CaveBiomes.palette_at(Vector3.ZERO, 1, 1, 2), CaveBiomes.HELL_PALETTE)
