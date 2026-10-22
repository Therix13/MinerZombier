extends "res://tests/interactions.gd"

func run_checks() -> void:
	root.show()
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	game.cycle.skip_tutorial()
	game.camera_controller.stop_transition()
	game.grid.expand()
	mover = game.get_node("WorldInteractions")
	var belts: RefCounted = game.conveyors
	var cell := Vector2i(15,2)
	check(belts.move_interval == 2.0,"All conveyors use a two-second transport interval")
	for direction in range(4):
		belts.belts.clear()
		check(belts.place(cell,direction,"filter"),"Filter can face direction %d" % direction)
		var front: Vector2i = cell + belts.DIRECTIONS[direction]
		var side: Vector2i = cell + belts.DIRECTIONS[(direction + 1) % 4]
		belts.place(front,direction)
		belts.place(side,(direction + 1) % 4)
		for inlet in range(4):
			check(belts.accepts_from(cell,cell + belts.DIRECTIONS[inlet]) == (inlet == (direction + 2) % 4),"Only the rear inlet accepts automated input for orientation %d/%d" % [direction,inlet])
		belts.set_filter(cell,"copper")
		for kind: String in game.mining.ORE_KINDS:
			game.mining.items_for(kind)[cell] = 1
			belts.tick()
			var expected: Vector2i = front if kind.get_slice("_",0) == "copper" else side
			check(game.mining.nugget_type(expected) == kind and game.mining.nuggets_at(cell) == 0,"Orientation %d routes %s to its correct output" % [direction,kind])
			game.mining.items_for(kind).erase(expected)
		game.mining.items_for("coal")[front] = 1
		game.mining.items_for("copper_4")[cell] = 1
		belts.tick()
		check(game.mining.nugget_type(cell) == "copper_4" and game.mining.nuggets_at(side) == 0,"Blocked filtered output waits without spilling into the rejection side")
		for items: Dictionary in game.mining.nugget_stores().values(): items.clear()
	belts.accumulator = 0
	game.mining.items_for("copper")[cell] = 1
	belts.advance(1.99)
	check(game.mining.nugget_type(cell) == "copper","No item moves before the full two seconds")
	belts.advance(0.01)
	check(game.mining.nuggets_at(cell) == 0,"The item moves when two seconds elapse")
	for items: Dictionary in game.mining.nugget_stores().values(): items.clear()
	check(belts.move(cell,cell,1) and belts.belt_data(cell)["filter"] == "copper","Rotating a filter preserves its selected material")
	belts.belts.clear()
	belts.place(cell,1,"filter")
	await mouse_move(point(cell))
	await mouse_button(point(cell),true)
	await mouse_button(point(cell),false)
	var inspector: Node = game.get_node("ToolInspector")
	check(inspector.is_open() and inspector.filter_selector.visible and not inspector.contents.visible,"Clicking a filter opens its material selector instead of an empty inventory")
	inspector.filter_selector.select(2)
	inspector.filter_selector.item_selected.emit(2)
	check(belts.belt_data(cell)["filter"] == "iron","The material selector changes the filter to iron")
	await settle()
	if DisplayServer.get_name() != "headless": root.get_texture().get_image().save_png("/tmp/filter-belt-inspector.png")
	inspector.close_inspector()
	var saves: Node = game.get_node("SaveGame")
	var state: Dictionary = saves.snapshot()
	check(saves.valid_snapshot(state) and saves.restore_snapshot(state) and belts.belt_data(cell)["filter"] == "iron","Filter configuration survives saving and restoring")
	state["belts"][cell]["filter"] = "invalid"
	check(not saves.valid_snapshot(state),"Unknown filter materials cannot enter a saved game")
	check(not game.progression.is_item_unlocked("filter"),"The filter begins locked before its construction ingredient is crafted")
	game.progression.record_resource("copper_ingot_3")
	game.shop.accept_unlock_notice()
	check(game.progression.is_item_unlocked("filter") and game.shop.visible_shop_items("AUTOMATIZACIÓN").has("filter"),"Crafting copper ingot tier three unlocks the filter in Automation")
	game.economy.coins = 100
	check(mover.select_item("filter") and mover.place_selected(Vector2i(14,1)),"A filter can be purchased and placed as a blueprint")
	var construction: Node = game.get_node("Construction")
	check(construction.plans[Vector2i(14,1)]["item"] == "filter" and construction.receive(Vector2i(14,1),"copper_ingot_3") and belts.belt_shape(Vector2i(14,1)) == "filter","One tier-three copper ingot completes the new filter belt")
	game.display_settings.open_menu()
	check(game.display_settings.quit_button.text == "Guardar y Salir" and game.display_settings.pause_page.get_child_count() == 5,"Pause has just Continue, Settings and the single Save and exit button")
	print("RESULT: %d passed, %d failed; filter conveyors" % [passed,failed])
	game.queue_free()
	await settle()
	quit(1 if failed else 0)
