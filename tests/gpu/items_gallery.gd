extends Node
## Items gallery: every item icon, the crafting stations in 3D, and the
## inventory / crafting / shop screens with a well-stocked mock player.
##   godot --path . --fullscreen res://tests/gpu/items_gallery.tscn -- --capture=/abs/dir [--only=icons,stations,inventory,crafting,shop,hud]

const MockWorld := preload("res://tests/gpu/ui_mock_world.gd")

var _out := ""
var _only := PackedStringArray()


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_out = arg.trim_prefix("--capture=")
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",")
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _wants(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _run() -> void:
	await _frames(5)
	ItemIcons.prewarm()
	var t0 := Time.get_ticks_msec()
	while true:
		var missing := 0
		for id: String in ItemDB.ITEMS:
			if not ItemIcons.has_icon(id):
				missing += 1
		if missing == 0 or Time.get_ticks_msec() - t0 > 40000:
			printerr("[items] icons ready in %d ms (missing %d)" % [Time.get_ticks_msec() - t0, missing])
			break
		await _frames(1)

	if _wants("icons"):
		await _icon_sheet()
	if _wants("stations"):
		await _stations()
	var need_world := false
	for n in ["inventory", "crafting", "shop", "hud", "anvil", "furnace", "alchemy", "workbench", "tooltip"]:
		need_world = need_world or _wants(n)
	if need_world:
		await _screens()
	get_tree().quit()


func _icon_sheet() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.045, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var ids: Array = ItemDB.ITEMS.keys()
	var per_page := 96
	var page := 0
	while page * per_page < ids.size():
		var grid := GridContainer.new()
		grid.columns = 12
		grid.position = Vector2(20, 20)
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 4)
		layer.add_child(grid)
		for i in range(page * per_page, mini(ids.size(), (page + 1) * per_page)):
			var id: String = ids[i]
			var cell := VBoxContainer.new()
			cell.custom_minimum_size = Vector2(150, 0)
			var slot := ItemSlot.new()
			slot.custom_minimum_size = Vector2(84, 84)
			slot.item = {"id": id, "count": 1}
			slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			cell.add_child(slot)
			var l := UiTheme.label(ItemDB.display_name(id), 11, ItemDB.rarity_color(id), HORIZONTAL_ALIGNMENT_CENTER)
			l.clip_text = true
			l.custom_minimum_size = Vector2(150, 0)
			cell.add_child(l)
			grid.add_child(cell)
		await _frames(4)
		await _shot("icons_%d" % page)
		grid.queue_free()
		page += 1
	layer.queue_free()


func _stations() -> void:
	var vp_root := Node3D.new()
	add_child(vp_root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.075, 0.07)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.42, 0.4)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	env.environment = e
	vp_root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	vp_root.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor_mi.mesh = pm
	floor_mi.material_override = ItemMats.stone(Color(0.3, 0.27, 0.24), Color(0.2, 0.18, 0.16))
	vp_root.add_child(floor_mi)
	var kinds := ["workbench", "furnace", "anvil", "alchemy"]
	for i in kinds.size():
		var st := StationModels.build(kinds[i], true)
		st.position = Vector3(-3.3 + i * 2.2, 0, 0)
		vp_root.add_child(st)
	var cam := Camera3D.new()
	cam.fov = 40
	vp_root.add_child(cam)
	cam.position = Vector3(0, 2.4, 5.2)
	cam.look_at(Vector3(0, 0.6, 0))
	cam.current = true
	await _wait(1.5)
	await _shot("stations")
	for i in kinds.size():
		cam.position = Vector3(-3.3 + i * 2.2 + 1.0, 1.6, 2.0)
		cam.look_at(Vector3(-3.3 + i * 2.2, 0.7, 0))
		await _wait(0.4)
		await _shot("station_" + kinds[i])
	vp_root.queue_free()
	await _frames(2)


func _screens() -> void:
	var world := MockWorld.new()
	add_child(world)
	world.call("setup")
	var p: Object = world.get("local_player")
	var inv: Inventory = p.get("inventory")
	_stock(inv)
	var backdrop := EmberBackground.new()
	backdrop.intensity = 0.7
	var layer := CanvasLayer.new()
	layer.layer = -5
	layer.add_child(backdrop)
	add_child(layer)
	var hud := Hud.new()
	add_child(hud)
	await _frames(5)
	var ev := get_node("/root/Events")
	ev.emit_signal("inventory_changed")
	ev.emit_signal("hotbar_selected", 0)
	ev.emit_signal("player_health_changed", 120.0, 140.0)
	if _wants("hud"):
		await _wait(2.0)
		await _shot("items_hud")
	if _wants("inventory") or _wants("tooltip"):
		hud.inventory_screen.open()
		await _wait(0.8)
		await _shot("inventory")
		if hud.inventory_screen.has_method("debug_hover"):
			hud.inventory_screen.call("debug_hover", 0)
			await _wait(0.4)
			await _shot("inventory_tooltip_weapon")
			hud.inventory_screen.call("debug_hover", 4)
			await _wait(0.4)
			await _shot("inventory_tooltip_armor")
		hud.inventory_screen.close()
		await _frames(2)
	for kind: String in ["workbench", "furnace", "anvil", "alchemy"]:
		if not (_wants("crafting") or _wants(kind)):
			continue
		ev.emit_signal("station_open", kind, null)
		await _wait(0.8)
		await _shot("craft_" + kind)
		var cs: Node = get_tree().get_first_node_in_group(&"crafting_screen")
		if cs != null and kind == "furnace" and cs.has_method("debug_start"):
			cs.call("debug_start")
			await _wait(1.0)
			await _shot("craft_furnace_smelting")
		if cs != null and cs.has_method("close"):
			cs.call("close")
		await _frames(2)
	if _wants("shop"):
		ev.emit_signal("shop_open", "merchant")
		await _wait(0.8)
		await _shot("shop_merchant")
		hud.shop_screen.close()
		await _frames(2)
	hud.queue_free()
	world.queue_free()


func _stock(inv: Inventory) -> void:
	for i in inv.slots.size():
		inv.slots[i] = {}
	var items := [["sword_steel", 1], ["pickaxe_mithril", 1], ["torch", 23], ["warhammer_adamantite", 1], ["helmet_mithril", 1],
		["greaves_steel", 1], ["iron_ore", 17], ["copper_ore", 24], ["tin_ore", 9], ["coal", 31], ["iron_ingot", 6], ["steel_ingot", 4],
		["mithril_ingot", 3], ["gold_ingot", 2], ["ruby", 2], ["sapphire", 1], ["potion_health", 4], ["potion_greater", 2], ["bread", 5],
		["planks", 40], ["stick", 12], ["wood", 9], ["stone", 64], ["granite", 22], ["glass_vial", 3], ["emberleaf", 7], ["amethyst", 1],
		["frost_crown", 1], ["dagger_infernal", 1], ["mithril_ore", 5]]
	for it: Array in items:
		inv.add(it[0], it[1])
	inv.equipment["chest"] = {"id": "chestplate_steel", "count": 1}
	inv.equipment["feet"] = {"id": "boots_iron", "count": 1, "gem": "sapphire"}
	inv.slots[0]["gem"] = "ruby"
	inv.gold = 1284
	inv.changed.emit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _shot(shot_name: String) -> void:
	if _out == "":
		await _wait(1.5)
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(shot_name + ".png"))
	printerr("[items] ", shot_name)
