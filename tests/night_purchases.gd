extends "res://tests/tutorial.gd"

func run_checks() -> void:
	root.show()
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	shop = game.shop
	cycle = game.cycle
	grid = game.grid
	cycle.skip_tutorial()
	cycle.day = 2
	cycle.barrier_broken = true
	cycle.start_night(true)
	game.zombie_manager.start_wave(2)
	game.camera_controller.stop_transition()
	var mover: Node = game.get_node("WorldInteractions")
	var construction: Node = game.get_node("Construction")
	game.economy.coins = 100000
	check(not shop.shop_button.disabled,"Night keeps the shop button enabled")
	check(not mover.select_item("iron"),"Night purchases still require progression unlocks")
	await purchase_route("VETAS","coal")
	var before: int = game.economy.coins
	await click_cell(Vector2i(14,0))
	check(game.mining.vein_at(Vector2i(14,0)) == "coal" and game.economy.coins == before - 100,"A real shop purchase places a coal vein and charges 100 at night")
	game.progression.unlocked["expansion"] = true
	await purchase_route("EXPANSION","expansion")
	check(grid.cave_width == 7 and game.economy.coins == before - 600,"Expansion can be purchased during the horde for 500")
	await purchase_route("DEFENSA","defense_platforms")
	check(grid.defense_tiles.has(grid.defense_cell("left")),"Defense platforms can be purchased during the horde")
	shop.close_shop()
	await wait_shop()
	await purchase_route("DEFENSA","launcher")
	await click_cell(grid.defense_cell("left"))
	check(game.launchers.launchers.has(grid.defense_cell("left")),"A night-purchased launcher can be placed on a defense platform")
	var cell := Vector2i(15,2)
	for item: String in ["copper","iron","gold","furnace","drill","compactor","saw","straight","corner_right","corner_left","junction"]:
		game.progression.unlocked[item] = true
		var category: String = "VETAS" if item in ["copper","iron","gold"] else ("AUTOMATIZACIÓN" if item in ["straight","corner_right","corner_left","junction"] else "HERRAMIENTAS")
		await purchase_route(category,item)
		await settle()
		check(mover.selected_item() == item,"Night placement persists across process frames for " + item)
		if item in ["furnace","saw"]:
			var direction: int = game.placement_direction
			await key(KEY_R)
			check(game.placement_direction == (direction + 1) % 4,"New " + item + " can be rotated before night placement")
		before = game.economy.coins
		await click_cell(cell)
		check(game.economy.coins == before - mover.item_price(item),"Night placement charges the normal price for " + item)
		if construction.has_recipe(item):
			check(construction.plans.has(cell) and construction.plans[cell]["delivered"].is_empty(),"Night tool purchase still requires construction resources for " + item)
			if item == "furnace":
				game.mining.items_for("coal_4")[Vector2i(16,2)] = 1
				await drag_cell(Vector2i(16,2),cell)
				game.mining.items_for("coal_4")[Vector2i(16,2)] = 1
				await drag_cell(Vector2i(16,2),cell)
				check(game.get_node("Furnaces").machines.has(cell),"A night-purchased furnace finishes when its recipe is delivered")
		else:
			check(game.mining.vein_at(cell) == item,"Night vein purchase finishes immediately for " + item)
		for map: Dictionary in mover.stores().values(): map.erase(cell)
		game.redraw_world()
	game.economy.coins = 0
	check(not mover.select_item("coal"),"Insufficient funds still block night purchases")
	game.economy.coins = 1000
	paused = true
	check(not mover.select_item("coal"),"Pausing still blocks night purchases")
	paused = false
	await click_control(shop.shop_button)
	await wait_shop()
	var elapsed: float = game.zombie_manager.wave_elapsed
	await create_timer(0.15).timeout
	check(game.zombie_manager.wave_elapsed > elapsed,"Opening the store does not pause the horde")
	shop.close_shop()
	await wait_shop()
	cycle.lose_night()
	check(not mover.select_item("coal") and shop.shop_button.disabled,"Defeat still blocks purchases")
	check(game.get_node("SaveGame").valid_snapshot(game.get_node("SaveGame").snapshot()),"Objects bought during combat remain valid for saving")
	print("RESULT: %d passed, %d failed; night purchases" % [passed,failed])
	game.queue_free()
	await settle()
	quit(1 if failed else 0)
