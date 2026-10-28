extends TestCase
## Village life: profession trades end to end (Trading + CharacterLife),
## fishing (rod tiers/recipes, bites, the reel fight) and taming rules.


func _who(profession: String) -> Dictionary:
	return {"key": "testville:%s" % profession, "village": "testville", "profession": profession, "name": "Tester"}


func test_professions_have_distinct_trades_with_real_items() -> void:
	var seen := {}
	for prof: String in Professions.TRADES:
		var t: Dictionary = Professions.TRADES[prof]
		var sells: Array = []
		for e: Array in t["sells"]:
			check(ItemDB.exists(String(e[0])), "%s sells a real item %s" % [prof, e[0]])
			sells.append(String(e[0]))
		for e: Array in t["buys"]:
			check(ItemDB.exists(String(e[0])), "%s buys a real item %s" % [prof, e[0]])
		sells.sort()
		var key := ",".join(sells)
		check(not seen.has(key), "%s has its own wares" % prof)
		seen[key] = true
	check_eq(Professions.of("blacksmith", 1), "smith")
	check_eq(Professions.of("merchant", 1), "trader")
	var coastal_fisher := false
	for i in 40:
		check(Professions.of("villager", i, false) != "fisher", "no fishers inland")
		coastal_fisher = coastal_fisher or Professions.of("villager", i, true) == "fisher"
	check(coastal_fisher, "coastal villages have fishers")


func test_trade_buy_and_sell_end_to_end() -> void:
	var inv := Inventory.new()
	var life := CharacterLife.new()
	var who := _who("fisher")
	inv.gold = 100
	var rod := {}
	for o: Dictionary in Trading.sell_offers(life, who, 3):
		if String(o["item"]) == "rod_wood":
			rod = o
	check(not rod.is_empty() and int(rod["locked"]) == 0, "the fisher sells a willow rod to strangers")
	check_eq(Trading.buy(inv, life, who, "rod_wood", 1, 3), "", "buying works")
	check(inv.has("rod_wood"), "rod in the pack")
	check_eq(inv.gold, 100 - int(rod.get("price", 0)), "paid the price")
	check(Trading.buy(inv, life, who, "rod_iron", 1, 3) != "", "iron rod is locked for strangers")
	inv.add("fish_trout", 3)
	var before := inv.gold
	check_eq(Trading.sell(inv, life, who, "fish_trout", 2, 3), "", "selling fish works")
	check_eq(inv.count_of("fish_trout"), 1, "two trout sold")
	check(inv.gold > before, "paid for the fish")
	check(Trading.sell(inv, life, _who("mason"), "fish_trout", 1, 3) != "", "the mason does not want fish")
	# Stock runs out for the day and comes back later.
	var stock := 0
	for o: Dictionary in Trading.sell_offers(life, who, 3):
		if String(o["item"]) == "fish_herring":
			stock = int(o["stock"])
	check(stock > 0, "herring in stock")
	inv.gold = 10000
	check_eq(Trading.buy(inv, life, who, "fish_herring", stock, 3), "", "buy out the herring")
	check(Trading.buy(inv, life, who, "fish_herring", 1, 3) != "", "sold out today")
	var later := 0
	for o: Dictionary in Trading.sell_offers(life, who, 9):
		if String(o["item"]) == "fish_herring":
			later = int(o["stock"])
	check(later > 0, "restocked days later")
	# A village you have wronged refuses to trade.
	life.add_rep("testville", -100)
	check(Trading.refuses(life, who), "distrusted customers are refused")
	check(Trading.buy(inv, life, who, "bait_worms", 1, 9) != "", "refused at the counter")


func test_rod_tiers_have_recipes_and_get_stronger() -> void:
	var prev := {}
	for id: String in ["rod_wood", "rod_reed", "rod_iron", "rod_mithril", "rod_tideborn"]:
		check(ItemDB.exists(id), id + " exists")
		check(ItemDB.RECIPES.has(id), id + " can be crafted")
		for input: String in ItemDB.recipe(id)["inputs"]:
			check(ItemDB.exists(input), "%s input %s exists" % [id, input])
		var st := FishingDB.rod_stats(int(ItemDB.info(id)["rod_tier"]))
		if not prev.is_empty():
			check(float(st["strength"]) > float(prev["strength"]) and float(st["reel"]) > float(prev["reel"]), id + " is stronger than the tier below")
		prev = st
		check(ItemDB.info(id).has("use_script"), id + " is used with right-click")
	check(ItemDB.RECIPES.has("fishing_line"), "fishing line can be made")


func test_bites_and_reel_fight() -> void:
	var ctx := {"hour": 8.0, "water": "fresh", "depth": 3.0, "tier": 1, "bait": 0}
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var got := 0
	for i in 60:
		var id := FishingDB.roll(ctx, rng)
		if id != "" and ItemDB.exists(id):
			got += 1
	check_eq(got, 60, "every cast's catch is a real item")
	check(not FishingDB.candidates(ctx).is_empty(), "fish bite in fresh water by day")
	var d := FishingDB.bite_delay(ctx, rng)
	check(d >= 2.0 and d < 30.0, "a bite comes after a wait (%.1fs)" % d)
	var baited := ctx.duplicate()
	baited["bait"] = 3
	rng.seed = 5
	var slow := FishingDB.bite_delay(ctx, rng)
	rng.seed = 5
	check(FishingDB.bite_delay(baited, rng) <= slow, "bait shortens the wait")
	# Careful pumping lands a perch on a willow rod.
	var f := FishingDB.ReelFight.new("fish_perch", 1, 7)
	var t := 0.0
	while f.result == "" and t < 90.0:
		f.step(0.05, f.tension < 0.55)
		t += 0.05
	check_eq(f.result, "caught", "a careful reel lands the perch")
	# Never reeling lets the hook slip.
	var g := FishingDB.ReelFight.new("fish_perch", 1, 7)
	t = 0.0
	while g.result == "" and t < 90.0:
		g.step(0.05, false)
		t += 0.05
	check_eq(g.result, "slipped", "a slack line lets the fish go")


func test_taming_foods() -> void:
	for kind: String in ["fox", "cat", "raven"]:
		var p := Pet.create(kind)
		p.spec = Pet.SPECIES[kind]
		check(p.accepts("fish_perch"), kind + " takes fish")
		check(not p.accepts("raw_meat"), kind + " refuses meat")
		p.free()
	var dog := Pet.create("wild_dog")
	dog.spec = Pet.SPECIES["wild_dog"]
	check(dog.accepts("raw_meat"), "dogs take meat")
	check(not dog.accepts("fish_perch"), "dogs refuse fish")
	dog.free()
