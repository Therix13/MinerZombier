extends "res://tests/timed_hordes.gd"
const Catalog = preload("res://Scripts/content_catalog.gd")
func run_checks() -> void:
	root.show()
	root.size = Vector2i(1440,900)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	game.campaign.set_process(false)
	game.cycle.skip_tutorial()
	game.camera_controller.stop_transition()
	manager = game.zombie_manager
	manager.set_process(false)
	mover = game.get_node("WorldInteractions")
	var saves: Node = game.get_node("SaveGame")
	var tiers: Node = game.get_node("ToolFusion")
	var director: Node = game.get_node("StoryDirector")
	var progression: RefCounted = game.progression
	game.shop.notice_item_ids.clear()
	game.shop.unlock_notice_backdrop.hide()
	for connection: Dictionary in progression.items_unlocked.get_connections(): progression.items_unlocked.disconnect(connection["callable"])
	# Fusion milestones gate recipes independently of the nitrate unlock.
	progression.record_resource("copper_ingot_3")
	check(progression.is_item_unlocked("nitrate") and not progression.is_item_unlocked("pistol") and not progression.is_item_unlocked("powder"),"Nitrate does not bypass weapon or ammunition milestones")
	for id: String in Catalog.UNLOCKS:
		for ingredient: String in Catalog.UNLOCKS[id]["requires"]: progression.record_resource(ingredient)
		check(progression.is_item_unlocked(id),"Documented fusion/production unlock: " + id)
	check(game.campaign.achievements().any(func(entry: Dictionary): return entry["name"].contains("Alto calibre")),"Achievements teach the high-caliber fusion requirement")
	game.shop.notice_item_ids.clear()
	game.shop.unlock_notice_backdrop.hide()
	game.economy.developer_mode = true
	game.progression.developer_mode = true
	game.grid.expand()
	clear_items()
	var a := Vector2i(14,1)
	var b := Vector2i(15,1)
	for kind: String in ["drill","furnace","compactor","saw","belt"]:
		clear_items()
		for tier in range(1,4):
			if kind == "drill": game.drills.drills[a] = 0; game.drills.drills[b] = 0
			elif kind == "belt": game.conveyors.place(a,0); game.conveyors.place(b,0)
			else:
				var machine: Node = game.get_node({"furnace":"Furnaces","compactor":"Compactors","saw":"Saws"}[kind])
				machine.place(a,0)
				if not machine.machines.has(b): machine.place(b,0)
			tiers.levels[a] = tier
			tiers.levels[b] = tier
			check(tiers.fuse(kind,a,b) and tiers.level_at(b) == tier+1 and not mover.stores()[kind].has(a),"Two matching tools produce the next tier: " + kind + str(tier+1))
		check(not tiers.can_fuse(kind,a,b),"Tool cannot exceed tier four: " + kind)
		check(tiers.speed(b) > 3,"Tier four increases real throughput: " + kind)
		var data: Dictionary = saves.snapshot()
		check(saves.valid_snapshot(data) and saves.restore_snapshot(data) and tiers.level_at(b) == 4,"Tool tier survives save/load: " + kind)
	clear_items()
	game.get_node("Furnaces").place(a,0)
	game.get_node("Furnaces").place(b,0)
	game.get_node("Furnaces").machines[a]["fuel"] = 20
	check(not tiers.can_fuse("furnace",a,b),"Fusion never discards stored fuel")
	clear_items()
	game.drills.place(a,0)
	tiers.levels[a] = 3
	check(mover.drop("drill",a,b) and tiers.level_at(b) == 3 and not tiers.levels.has(a),"Moving a tool carries its tier metadata")
	clear_items()
	progression.unlocked["expansion"] = true
	game.economy.developer_mode = false
	game.grid.cave_width = 3
	game.grid.cave_height = 3
	game.grid.apply_cave_size()
	game.economy.coins = 499
	check(not game.campaign.expand_gallery() and game.economy.coins == 499 and game.grid.cave_width == 3,"Unaffordable expansion never charges or changes ownership")
	game.economy.coins = 10000000
	var previous_area: int = game.grid.cave_width*game.grid.cave_height
	while not Catalog.next_expansion(game.grid.cave_width).is_empty():
		var stage: Dictionary = Catalog.next_expansion(game.grid.cave_width)
		var before: int = game.economy.coins
		check(game.campaign.expand_gallery() and before-game.economy.coins == stage["price"] and game.grid.cave_width*game.grid.cave_height > previous_area,"Excavation charges its exact increasing price: " + str(stage["size"]))
		previous_area = game.grid.cave_width*game.grid.cave_height
	check(game.grid.owned_tiles.has(Vector2i(0,39)) and game.grid.owned_tiles.has(Vector2i(29,39)) and not game.campaign.expand_gallery(),"Final expansion covers every map cell and stops charging")
	check(saves.valid_snapshot(saves.snapshot()) and saves.restore_snapshot(saves.snapshot()),"Full 30 × 40 map survives save/load")
	game.grid.expand()
	check(game.grid.cave_width == 30 and game.grid.cave_height == 40,"Expansion API cannot shrink a completed map")
	# Tier bonuses advance production, preserving the same material costs.
	clear_items()
	var oven: Node = game.get_node("Furnaces")
	oven.place(b,0)
	tiers.levels[b] = 4
	oven.receive(b,"coal_4")
	oven.receive(b,"copper_4")
	oven.process_smelting(1.2)
	check(game.mining.nugget_type(b+Vector2i.UP) == "copper_ingot" and oven.machines[b]["fuel"] == 0,"Tier-four furnace completes one ingot faster without reducing fuel cost")
	var invalid: Dictionary = saves.snapshot()
	invalid["tool_levels"][b] = 5
	check(not saves.valid_snapshot(invalid),"Corrupt out-of-range tool tiers are rejected")
	clear_items()
	game.conveyors.place(b,0)
	game.conveyors.place(b+Vector2i.UP,0)
	tiers.levels[b] = 4
	game.conveyors.accumulator = 0
	game.mining.items_for("coal")[b] = 1
	game.conveyors.advance(.8)
	check(game.mining.nuggets_at(b+Vector2i.UP) == 1 and game.mining.nuggets_at(b) == 0,"Fused belts actually transport before the base two-second interval")
	clear_items()
	game.mining.place_vein(b,1,"coal")
	game.drills.place(b+Vector2i.DOWN,0)
	tiers.levels[b+Vector2i.DOWN] = 4
	game.drills.tick()
	check(game.mining.coal_veins[b]["progress"] == 4,"Tier-four drill performs four extraction hits per cycle")
	# Real logistics: alternate only after a successful transfer; eject to unbelted floor.
	clear_items()
	game.conveyors.place(b,0,"splitter")
	var first_dir: int = game.conveyors.output_direction(b,"coal")
	game.conveyors.place(b+Vector2i.RIGHT,1)
	game.conveyors.place(b+Vector2i.LEFT,3)
	game.mining.items_for("coal")[b] = 1
	game.conveyors.tick()
	check(game.conveyors.output_direction(b,"coal") != first_dir and game.mining.nuggets_at(b+Vector2i.RIGHT) == 1,"Distributor alternates outlets after a successful transfer")
	clear_items()
	game.conveyors.place(b,0,"ejector")
	game.mining.items_for("coal")[b] = 1
	game.conveyors.tick()
	check(game.mining.nuggets_at(b+Vector2i.UP) == 1,"Ejector deposits onto a free floor tile")
	clear_items()
	for weapon: String in ["ak47","minigun"]:
		check(mover.select_item(weapon) and mover.place_selected(b),"New intermediate weapon has a purchasable blueprint: " + weapon)
		for ingredient: String in game.get_node("Construction").RECIPES[weapon]:
			for index in range(game.get_node("Construction").RECIPES[weapon][ingredient]): game.get_node("Construction").receive(b,ingredient)
		check(game.launchers.launchers[b]["weapon"] == weapon and game.launchers.receive(b,"highcaliber") and not game.launchers.receive(b,"bullet"),"New weapon accepts high-caliber ammunition only: " + weapon)
		game.launchers.launchers.erase(b)
	# A crafted high-caliber batch conserves ingredients and unlocks its weapon milestone.
	clear_items()
	game.mining.items_for("powder")[a] = 2
	game.mining.items_for("iron_ingot_2")[b] = 1
	check(game.campaign.craft("highcaliber"),"High-caliber ammunition uses the workshop's real manufacturing path")
	game.campaign.advance_workshop(4)
	check(game.campaign.total("highcaliber") == 16 and game.campaign.total("powder") == 0 and game.campaign.total("iron_ingot_2") == 0,"A high-caliber batch consumes exact ingredients and yields sixteen rounds")
	clear_items()
	# Story scenes pause combat, fade and persist; replay has no economic side effects.
	director.play("warden")
	check(paused and director.active == "warden" and director.seen().has("warden"),"Boss kill-scene pauses gameplay and records its archive")
	director._process(1.1)
	check(director.overlay.modulate.a == 1,"Cinematic fades in over one second")
	if DisplayServer.get_name() != "headless":
		await settle()
		root.get_texture().get_image().save_png("/tmp/renewed-killscene.png")
	director.finish()
	director._process(1.1)
	check(not paused and director.active.is_empty(),"Cinematic fades out and restores gameplay")
	for boss: String in ["plague","broodmother","executor"]:
		director.play(boss)
		director._process(3.5)
		await settle()
		check(director.active == boss and director.film.scene_data["boss"] == boss,"Distinct animated boss kill-scene: " + boss)
		if boss == "plague":
			var event := InputEventKey.new()
			event.keycode = KEY_ESCAPE
			event.pressed = true
			Input.parse_input_event(event)
			await settle()
			check(director.closing and not game.display_settings.menu_open,"Escape dismisses the cinematic without opening a second pause menu")
		director.finish()
		director._process(1.1)
	director.enqueue("warden")
	check("warden" not in director.pending,"Boss scenes do not automatically repeat")
	check(saves.valid_snapshot(saves.snapshot()) and saves.restore_snapshot(saves.snapshot()) and director.seen().has("warden"),"Lore archive survives save/load")
	saves.test_mode = false
	game.economy.developer_mode = true
	game.night_victory_overlay.show()
	director.enqueue("origin")
	director._process(.1)
	check(director.active == "origin","A queued cinematic takes priority over the night victory panel")
	director._process(1.1)
	director.finish()
	director._process(1.1)
	check(not paused and game.night_victory_overlay.visible,"Closing the kill-scene preserves the underlying victory panel")
	game.night_victory_overlay.hide()
	saves.test_mode = true
	game.economy.developer_mode = false
	game.grid.cave_width = 11
	game.grid.cave_height = 7
	game.grid.apply_cave_size()
	game.mining.place_vein(Vector2i(14,0),1,"coal")
	game.mining.place_vein(Vector2i(14,2),1,"copper")
	game.get_node("Furnaces").place(Vector2i(16,2),0)
	game.get_node("Saws").place(Vector2i(16,3),0)
	game.get_node("Compactors").place(Vector2i(16,4),0)
	game.conveyors.place(Vector2i(15,2),1,"filter")
	game.conveyors.place(Vector2i(15,3),0,"splitter")
	game.drills.place(Vector2i(13,2),1)
	game.mining.items_for("copper_ingot_3")[Vector2i(16,1)] = 1
	game.camera_controller.set_defense_view(false)
	game.camera_controller.stop_transition()
	game.redraw_world()
	await settle()
	if DisplayServer.get_name() != "headless": root.get_texture().get_image().save_png("/tmp/renewed-mine.png")
	game.economy.coins = 1250000
	game.economy.money_changed.emit(game.economy.coins)
	check(not game.shop.money_label.text.contains("\n") and game.shop.money_label.text.contains("M"),"Large money balances use a compact single-line display")
	game.campaign.open_panel()
	game.campaign.show_tab("Logros")
	await settle()
	if DisplayServer.get_name() != "headless": root.get_texture().get_image().save_png("/tmp/renewed-achievements.png")
	game.campaign.close_panel()
	print("RESULT: %d passed, %d failed; renewed progression" % [passed,failed])
	quit(1 if failed else 0)
