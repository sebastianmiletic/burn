extends TestCase


func test_phase_thresholds() -> void:
	check_eq(BossLogic.phase_for(1.0), 1)
	check_eq(BossLogic.phase_for(0.67), 1)
	check_eq(BossLogic.phase_for(0.66), 2)
	check_eq(BossLogic.phase_for(0.34), 2)
	check_eq(BossLogic.phase_for(0.33), 3)
	check_eq(BossLogic.phase_for(0.0), 3)


func test_enrage() -> void:
	check(not BossLogic.is_enraged(100.0, 480.0), "not enraged early")
	check(BossLogic.is_enraged(480.0, 480.0), "enraged at the timer")
	check(not BossLogic.is_enraged(9999.0, 0.0), "no timer, no enrage")
	check(BossLogic.tempo(500.0, 480.0, 1) > BossLogic.tempo(100.0, 480.0, 1), "enrage speeds up")
	check(BossLogic.tempo(0.0, 480.0, 3) > BossLogic.tempo(0.0, 480.0, 1), "later phases are faster")


func test_target_highest_threat() -> void:
	var threat := {1: 100.0, 2: 400.0, 3: 50.0}
	var dist := {1: 5.0, 2: 20.0, 3: 2.0}
	check_eq(BossLogic.pick_target(threat, dist), 2)


func test_target_proximity_breaks_close_calls() -> void:
	var threat := {1: 100.0, 2: 110.0}
	var dist := {1: 2.0, 2: 35.0}
	check_eq(BossLogic.pick_target(threat, dist), 1, "a close player with nearly equal threat wins")


func test_target_nearest_without_threat_and_ignores_far() -> void:
	check_eq(BossLogic.pick_target({}, {1: 12.0, 2: 4.0}), 2)
	check_eq(BossLogic.pick_target({}, {1: 100.0}, 0.6, 40.0), -1, "out of range")
	check_eq(BossLogic.pick_target({7: 500.0}, {1: 3.0}), 1, "threat of a departed player is ignored")


func test_weighted_pick() -> void:
	var w := {"a": 1.0, "b": 3.0}
	check_eq(BossLogic.pick_weighted(w, 0.1), "a")
	check_eq(BossLogic.pick_weighted(w, 0.9), "b")
	check_eq(BossLogic.pick_weighted({}, 0.5), "")
	check_eq(BossLogic.pick_weighted({"x": 0.0}, 0.5), "")


func test_telegraph_shapes() -> void:
	var o := Vector3.ZERO
	var fwd := Vector3(0, 0, -1)
	check(TelegraphShape.contains("circle", o, fwd, Vector3(3, 0, 0), Vector3(2, 0, 0)), "inside circle")
	check(not TelegraphShape.contains("circle", o, fwd, Vector3(3, 0, 0), Vector3(4, 0, 0)), "outside circle")
	check(not TelegraphShape.contains("circle", o, fwd, Vector3(3, 0, 0), Vector3(1, 9, 0)), "too high above")
	check(TelegraphShape.contains("ring", o, fwd, Vector3(3, 6, 0), Vector3(0, 0, 4)), "in ring band")
	check(not TelegraphShape.contains("ring", o, fwd, Vector3(3, 6, 0), Vector3(0, 0, 2)), "safe inside ring")
	check(TelegraphShape.contains("cone", o, fwd, Vector3(8, 30, 0), Vector3(1, 0, -5)), "in cone")
	check(not TelegraphShape.contains("cone", o, fwd, Vector3(8, 30, 0), Vector3(0, 0, 5)), "behind cone")
	check(not TelegraphShape.contains("cone", o, fwd, Vector3(8, 30, 0), Vector3(5, 0, -2)), "outside cone angle")
	check(TelegraphShape.contains("line", o, fwd, Vector3(10, 2, 0), Vector3(0.5, 0, -9)), "in line")
	check(not TelegraphShape.contains("line", o, fwd, Vector3(10, 2, 0), Vector3(1.5, 0, -5)), "beside line")
	check(not TelegraphShape.contains("line", o, fwd, Vector3(10, 2, 0), Vector3(0, 0, 1)), "behind line start")


func test_hades_rings_leave_safe_gaps() -> void:
	# The phase-3 ring attack must leave bands a player can stand in.
	var bands := [Vector2(2, 6), Vector2(8, 13), Vector2(15, 22)]
	for r: float in [7.0, 14.0]:
		var hit := false
		for b: Vector2 in bands:
			if TelegraphShape.contains("ring", Vector3.ZERO, Vector3.FORWARD, Vector3(b.x, b.y, 0), Vector3(r, 0, 0)):
				hit = true
		check(not hit, "radius %.0f is safe" % r)
