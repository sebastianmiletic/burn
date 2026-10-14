extends TestCase


func test_fresh_abilities_are_ready() -> void:
	var c := Cooldowns.new()
	for a in ["fireball", "burst", "dodge", "potion"]:
		check(c.ready(a), "%s ready at start" % a)
		check_near(c.progress(a), 1.0, 1e-6)


func test_trigger_blocks_until_elapsed() -> void:
	var c := Cooldowns.new()
	check(c.trigger("fireball"), "first trigger works")
	check(not c.trigger("fireball"), "second trigger is refused")
	check_near(c.remaining("fireball"), 4.0, 1e-6)
	c.advance(3.9)
	check(not c.ready("fireball"), "not ready at 3.9 s")
	check_near(c.progress("fireball"), 0.975, 1e-4)
	c.advance(0.11)
	check(c.ready("fireball"), "ready after 4 s")


func test_default_durations() -> void:
	var c := Cooldowns.new()
	c.trigger("burst")
	c.trigger("dodge")
	c.trigger("potion")
	check_near(c.remaining("burst"), 12.0, 1e-6)
	check_near(c.remaining("dodge"), 0.8, 1e-6)
	check_near(c.remaining("potion"), 2.0, 1e-6)


func test_abilities_are_independent_and_resettable() -> void:
	var c := Cooldowns.new()
	c.trigger("burst")
	check(c.ready("fireball"), "fireball unaffected by burst")
	c.reset("burst")
	check(c.ready("burst"), "reset clears one")
	c.trigger("burst", 5.0)
	check_near(c.total("burst"), 5.0, 1e-6, "custom duration")
	c.reset()
	check(c.ready("burst"), "reset clears all")
