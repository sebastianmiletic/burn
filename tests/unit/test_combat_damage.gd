extends TestCase


func test_weapon_base_and_fists() -> void:
	check_eq(Damage.weapon_base("sword_iron"), 16.0)
	check_eq(Damage.weapon_base(""), Damage.FIST_DAMAGE)
	check_eq(Damage.weapon_base("stone"), Damage.FIST_DAMAGE, "blocks hit like fists")


func test_rank_scaling_is_monotonic() -> void:
	var last := 0.0
	for r in 10:
		var m := Damage.rank_multiplier(r)
		check(m > last, "rank %d multiplier grows" % r)
		last = m
	check_near(Damage.rank_multiplier(0), 1.0, 1e-6)


func test_crit_roll() -> void:
	var normal := Damage.melee("sword_iron", 0, 0.5)
	var crit := Damage.melee("sword_iron", 0, 0.05)
	check(not normal["crit"], "roll 0.5 is not a crit")
	check(crit["crit"], "roll 0.05 is a crit")
	check_near(crit["amount"], normal["amount"] * Damage.CRIT_MULT, 1e-4)


func test_fire_weapons_burn() -> void:
	var ember := Damage.melee("sword_ember", 2, 0.9)
	check_eq(ember["kind"], "fire")
	check(ember["burn"] > 0.0, "ember sword burns")
	check_eq(Damage.melee("sword_iron", 2, 0.9)["kind"], "hit")


func test_resistances() -> void:
	check_near(Damage.apply(100.0, "imp", "fire"), 15.0, 1e-4, "imps shrug off fire")
	check(Damage.apply(100.0, "ghoul", "fire") > 100.0, "ghouls are weak to fire")
	check_near(Damage.apply(100.0, "unknown_kind", "hit"), 100.0, 1e-4)
	check(Damage.apply(-5.0, "player", "hit") == 0.0, "never negative")


func test_boss_health_scales_with_party() -> void:
	check_near(Damage.boss_health(1000.0, 1), 1000.0, 1e-4)
	check(Damage.boss_health(1000.0, 4) > Damage.boss_health(1000.0, 2), "more players, more health")


func test_burn_ticks_sum_to_total() -> void:
	var ticks := int(Damage.BURN_SECONDS / Damage.BURN_TICK)
	check_near(Damage.burn_tick(6.0) * ticks, Damage.burn_total(6.0), 1e-4)


func test_enrage_increases_monster_damage() -> void:
	check(Damage.monster(10.0, true) > Damage.monster(10.0, false), "enraged hits harder")
