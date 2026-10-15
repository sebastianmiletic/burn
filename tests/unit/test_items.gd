extends TestCase
## Items, recipes, progression ladder, equipment and crafting.


func test_every_recipe_references_real_items() -> void:
	for rid: String in ItemDB.RECIPES:
		var r: Dictionary = ItemDB.RECIPES[rid]
		check(ItemDB.exists(ItemDB.recipe_result(rid)), "recipe %s makes a real item" % rid)
		check(ItemDB.STATIONS.has(String(r.get("station", ""))), "recipe %s station '%s' is known" % [rid, r.get("station", "")])
		var inputs: Dictionary = r.get("inputs", {})
		check(not inputs.is_empty(), "recipe %s has inputs" % rid)
		for item: String in inputs:
			check(ItemDB.exists(item), "recipe %s input %s exists" % [rid, item])
			check(int(inputs[item]) > 0, "recipe %s input %s count > 0" % [rid, item])
			check(item != ItemDB.recipe_result(rid), "recipe %s does not consume its own result" % rid)


func test_every_block_drop_is_an_item() -> void:
	for b in Blocks.COUNT:
		var d := Blocks.drop(b)
		if d != "":
			check(ItemDB.exists(d), "block %s drops real item %s" % [Blocks.name_of(b), d])


func test_every_station_kind_has_recipes_and_an_item() -> void:
	for kind: String in ItemDB.STATIONS:
		check(ItemDB.recipes_for_station(kind).size() > 0, "station '%s' has recipes" % kind)
	var placed := {}
	for id: String in ItemDB.ITEMS:
		var inf: Dictionary = ItemDB.ITEMS[id]
		if inf.has("place_station"):
			placed[String(inf["place_station"])] = id
			check(ItemDB.STATIONS.has(String(inf["place_station"])), "%s places a known station" % id)
			check(ItemDB.RECIPES.has(id), "station item %s is craftable" % id)
	for kind: String in ItemDB.STATIONS:
		if kind != "":
			check(placed.has(kind), "an item places a %s" % kind)


func test_ladder_damage_increases_monotonically() -> void:
	for kind: String in ItemDB.KINDS:
		var last := -1.0
		for tier: String in ItemDB.TIER_ORDER:
			var id := kind + "_" + tier
			if not ItemDB.exists(id):
				continue
			var dmg := float(ItemDB.info(id)["damage"])
			check(dmg > last, "%s damage %.1f > previous %.1f" % [id, dmg, last])
			last = dmg
	# Every metal tier has the full weapon set.
	for tier: String in ItemDB.METALS:
		for kind: String in ItemDB.KINDS:
			check(ItemDB.exists(kind + "_" + tier), "%s_%s exists" % [kind, tier])
	# Heavy weapons hit harder than swords of the same tier.
	check(float(ItemDB.info("warhammer_steel")["damage"]) > float(ItemDB.info("sword_steel")["damage"]), "hammer > sword")
	check(float(ItemDB.info("sword_infernal")["damage"]) > 2.0 * float(ItemDB.info("sword_copper")["damage"]), "infernal far above copper")


func test_pickaxe_ladder_and_block_tiers() -> void:
	var last_tier := 0
	var last_speed := 0.0
	for tier: String in ItemDB.TIER_ORDER:
		var inf := ItemDB.info("pickaxe_" + tier)
		check(int(inf["mine_tier"]) >= last_tier, "pickaxe_%s tier never drops" % tier)
		check(float(inf["mine_speed"]) > last_speed, "pickaxe_%s faster" % tier)
		last_tier = int(inf["mine_tier"])
		last_speed = float(inf["mine_speed"])
	# Each tier's ore is reachable with the previous tier's pickaxe.
	var gates := [["pickaxe_wood", Blocks.COPPER_ORE], ["pickaxe_wood", Blocks.TIN_ORE], ["pickaxe_wood", Blocks.COAL_ORE],
		["pickaxe_stone", Blocks.IRON_ORE], ["pickaxe_bronze", Blocks.SILVER_ORE], ["pickaxe_iron", Blocks.GOLD_ORE],
		["pickaxe_steel", Blocks.MITHRIL_ORE], ["pickaxe_mithril", Blocks.ADAMANTITE_ORE], ["pickaxe_adamantite", Blocks.HELLSTONE],
		["pickaxe_iron", Blocks.RUBY_ORE], ["pickaxe_steel", Blocks.EMBER_ORE], ["pickaxe_mithril", Blocks.OBSIDIAN]]
	for g: Array in gates:
		check(ItemDB.can_mine(g[0], g[1]), "%s mines %s" % [g[0], Blocks.name_of(g[1])])
	var denied := [["pickaxe_wood", Blocks.IRON_ORE], ["pickaxe_stone", Blocks.GOLD_ORE], ["pickaxe_iron", Blocks.MITHRIL_ORE],
		["pickaxe_steel", Blocks.ADAMANTITE_ORE], ["pickaxe_mithril", Blocks.HELLSTONE], ["axe_steel", Blocks.STONE]]
	for g: Array in denied:
		check(not ItemDB.can_mine(g[0], g[1]), "%s cannot mine %s" % [g[0], Blocks.name_of(g[1])])
	check(ItemDB.mine_time("axe_iron", Blocks.OAK_TRUNK) < ItemDB.mine_time("pickaxe_iron", Blocks.OAK_TRUNK), "axes chop faster")
	check(ItemDB.mine_time("pickaxe_infernal", Blocks.STONE) < ItemDB.mine_time("pickaxe_copper", Blocks.STONE), "better picks dig faster")
	check(ItemDB.mine_time("pickaxe_infernal", Blocks.BEDROCK) < 0.0, "bedrock never breaks")
	# Every ore-ish block can be mined by the best pickaxe.
	for b in Blocks.COUNT:
		if Blocks.is_breakable(b) and Blocks.drop(b) != "":
			check(ItemDB.can_mine("pickaxe_infernal", b), "infernal pick mines %s" % Blocks.name_of(b))


func test_armor_reduces_damage_and_ladders() -> void:
	var inv := Inventory.new()
	check_eq(inv.damage_taken_multiplier("hit"), 1.0, "no armour")
	var last := 1.0
	for tier: String in ItemDB.METALS:
		var t := Inventory.new()
		for piece: String in ItemDB.ARMOR_PIECES:
			t.add(piece + "_" + tier)
		for i in range(Inventory.HOTBAR + 3, -1, -1):
			t.equip_from(i)
		var m := t.damage_taken_multiplier("hit")
		check(m < last, "%s set reduces more (%.2f < %.2f)" % [tier, m, last])
		last = m
	check(last < 0.5, "full infernal blocks over half (%.2f)" % last)
	var full := Inventory.new()
	full.add("chestplate_infernal")
	full.equip_from(0)
	check(full.get_slot(Inventory.equip_index("chest")).get("id", "") == "chestplate_infernal", "cuirass worn")
	check(full.damage_taken_multiplier("void") == 1.0, "void ignores armour")
	var set := Inventory.new()
	for piece: String in ItemDB.ARMOR_PIECES:
		set.add(piece + "_infernal")
	for i in range(Inventory.HOTBAR + 3, -1, -1):
		set.equip_from(i)
	check(set.damage_taken_multiplier("fire") < set.damage_taken_multiplier("hit"), "a full infernal set resists fire")
	var plain := Inventory.new()
	plain.add("chestplate_iron")
	plain.add("ruby")
	plain.equip_from(0)
	var before := plain.damage_taken_multiplier("fire")
	check(plain.socket(1, Inventory.equip_index("chest")), "ruby set into armour")
	check(plain.damage_taken_multiplier("fire") < before, "ruby resists fire")


func test_equipment_slots_reject_wrong_items() -> void:
	var inv := Inventory.new()
	inv.add("sword_iron")
	inv.add("helmet_iron")
	check(not inv.swap(0, Inventory.equip_index("head")), "a sword is no helmet")
	check(not inv.swap(1, Inventory.equip_index("feet")), "a helm is no boot")
	check(inv.swap(1, Inventory.equip_index("head")), "a helm goes on the head")
	check(inv.defense() > 0.0, "defence counts")
	check(inv.unequip("head"), "unequip to the bag")
	check(inv.defense() == 0.0, "defence gone")


func test_crafting_consumes_and_needs_station_and_fuel() -> void:
	var inv := Inventory.new()
	inv.add("iron_ore", 3)
	var r := inv.craft("iron_ingot", [])
	check(not r["ok"], "no furnace, no smelting")
	r = inv.craft("iron_ingot", ["furnace"])
	check(not r["ok"] and String(r["reason"]).contains("fuel"), "furnace needs fuel")
	inv.add("coal", 1)
	check(ItemDB.can_craft("iron_ingot", inv, ["furnace"]), "can smelt with coal")
	r = inv.craft("iron_ingot", ["furnace"])
	check(r["ok"], "smelted")
	check_eq(inv.count_of("iron_ingot"), 1)
	check_eq(inv.count_of("iron_ore"), 2)
	check_eq(inv.count_of("coal"), 0, "coal burned (4 units, 2 used, rest lost)")
	# Steel needs coal as an ingredient AND fuel: wood can be the fuel.
	inv.add("coal", 2)
	inv.add("wood", 1)
	check(ItemDB.can_craft("steel_ingot", inv, ["smithy"]), "village smithy counts as a furnace")
	r = inv.craft("steel_ingot", ["furnace"])
	check(r["ok"], "steel made")
	check_eq(inv.count_of("steel_ingot"), 1)
	check_eq(inv.count_of("coal"), 0)
	check_eq(inv.count_of("wood"), 0)
	# By-hand recipes work anywhere.
	inv.add("wood", 1)
	check(inv.craft("planks", [])["ok"], "planks by hand")
	check_eq(inv.count_of("planks"), 4)
	check(not ItemDB.can_craft("sword_iron", inv, ["anvil"]), "missing ingots")
	check_eq(inv.craftable_times("stick"), 4)


func test_attack_stats_include_gems_and_buffs() -> void:
	var inv := Inventory.new()
	inv.add("sword_steel")
	inv.add("sapphire")
	var base := float(inv.attack_stats()["damage"])
	check(inv.socket(1, 0), "socketed")
	check(float(inv.attack_stats()["damage"]) > base, "sapphire sharpens")
	check(not inv.has("sapphire"), "gem consumed")
	inv.apply_consumable("potion_might")
	check(inv.buff_active("might"), "buff active")
	check(float(inv.attack_stats()["damage"]) > base * 1.3, "might buff stacks")
	check_eq(inv.best_heal_item(), "")
	inv.add("bread")
	inv.add("potion_health")
	check_eq(inv.best_heal_item(), "potion_health", "potions before food")


func test_old_saves_still_load() -> void:
	var old := {"slots": [{"id": "sword_rusty", "count": 1}, {"id": "pickaxe_stone", "count": 1}, {}, {"id": "no_such_item", "count": 3}, {"id": "iron_ore", "count": 5}],
		"selected": 1, "gold": 12}
	var inv := Inventory.new()
	inv.from_dict(old)
	check(inv.has("sword_rusty") and inv.has("pickaxe_stone") and inv.has("iron_ore", 5), "old items kept")
	check_eq(inv.count_of("no_such_item"), 0)
	check_eq(inv.selected, 1)
	check_eq(inv.gold, 12)
	check(inv.equipment["head"].is_empty(), "no equipment in old saves")
	var round_trip := Inventory.new()
	inv.add("helmet_steel")
	inv.equip_from(inv.slots.find(inv.slots.filter(func(s: Dictionary) -> bool: return s.get("id", "") == "helmet_steel")[0]))
	round_trip.from_dict(inv.to_dict())
	check_eq(String(round_trip.equipment["head"].get("id", "")), "helmet_steel", "equipment saved")
	# Legacy ids the rest of the game uses still exist.
	for id: String in ["sword_rusty", "sword_iron", "sword_ember", "sword_dragonbone", "pickaxe_stone", "pickaxe_iron",
			"pickaxe_obsidian", "potion_health", "potion_greater", "bread", "torch", "lantern", "iron_ore", "gold_ore", "coal",
			"ember_crystal", "frost_shard", "hellstone", "obsidian", "bone", "warden_sigil", "frost_crown", "dragonheart"]:
		check(ItemDB.exists(id), "legacy id %s" % id)


func test_every_item_has_a_model() -> void:
	for id: String in ItemDB.ITEMS:
		var n := HeldItems.build(id, 1.0, false)
		check(n != null, "model for %s" % id)
		if n != null:
			check(n.get_child_count() > 0, "model for %s has parts" % id)
			n.free()
