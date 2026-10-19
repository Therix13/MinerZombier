extends "res://tests/interactions.gd"

func run_checks() -> void:
	root.show()
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.cycle.skip_tutorial()
	mover = game.get_node("WorldInteractions")
	var shop: Control = game.shop
	var player: RefCounted = game.progression
	shop.show_categories()
	check(shop.category_buttons.keys() == ["VETAS","DEFENSA"],"Only categories containing initially unlocked objects are shown")
	game.economy.coins = 5000
	shop.open_category("EXPANSION")
	shop.request_item("expansion",shop.expansion_requested)
	game.buy_expansion()
	check(game.grid.cave_width == 3 and game.economy.coins == 5000 and shop.shop_title.text == "TIENDA","Locked expansion cannot be opened or bought through either entry point")
	game.economy.toggle_developer_mode()
	check(shop.visible_categories() == ["EXPANSION","VETAS","HERRAMIENTAS","AUTOMATIZACIÓN","DEFENSA","RECURSOS"],"DEV exposes all categories, including expansion and testing resources")
	game.economy.toggle_developer_mode()
	check(shop.category_buttons.keys() == ["VETAS","DEFENSA"],"Leaving DEV hides categories without genuine unlocks")
	var a := Vector2i(14,0)
	var b := Vector2i(15,0)
	game.mining.place_vein(a,1)
	game.mining.place_vein(b,1)
	game.mining.coal_veins[a]["level"] = 3
	game.mining.coal_veins[b]["level"] = 3
	game.mining.fuse_veins(a,b)
	check(player.is_item_unlocked("copper") and not player.is_item_unlocked("expansion"),"Unlocking copper alone does not unlock expansion before a copper vein exists")
	shop.accept_unlock_notice()
	var copper := Vector2i(14,1)
	check(game.mining.place_vein(copper,1,"copper") and player.is_item_unlocked("expansion"),"Placing the first copper vein permanently unlocks expansion")
	check(shop.category_buttons.has("EXPANSION") and shop.notice_item_ids.has("expansion"),"The expansion category and its unlock notice appear immediately")
	shop.accept_unlock_notice()
	var saves: Node = game.get_node("SaveGame")
	var legacy: Dictionary = saves.snapshot()
	legacy["progression"]["unlocked"].erase("expansion")
	check(saves.restore_snapshot(legacy) and player.is_item_unlocked("expansion"),"Older saves with an existing copper vein recover the expansion milestone")
	game.mining.copper_veins.erase(copper)
	check(player.is_item_unlocked("expansion"),"Removing the copper vein does not revoke the earned expansion")
	game.buy_expansion()
	check(game.grid.cave_width == 7 and game.economy.coins == 4500,"Unlocked expansion charges the normal 500 gold price")
	await create_timer(0.4).timeout
	shop.show_categories()
	check(not shop.category_buttons.has("HERRAMIENTAS") and not shop.category_buttons.has("AUTOMATIZACIÓN"),"Still-empty tool and automation categories remain hidden")
	game.mining.resource_created.emit("coal_4")
	check(shop.category_buttons.has("HERRAMIENTAS"),"The tool category appears as soon as its furnace material unlocks")
	shop.accept_unlock_notice()
	game.mining.resource_created.emit("copper_ingot_3")
	check(shop.category_buttons.has("AUTOMATIZACIÓN"),"The automation category appears as soon as the belt material unlocks")
	shop.accept_unlock_notice()
	shop.close_shop()
	await create_timer(0.4).timeout
	var furnace: Node = game.get_node("Furnaces")
	furnace.set_process(false)
	var cell := Vector2i(16,2)
	var source := Vector2i(15,2)
	check(furnace.place(cell),"Fuel test furnace fits an empty owned tile")
	for kind: String in furnace.FUEL_VALUES:
		furnace.machines[cell]["fuel"] = 0
		game.mining.items_for(kind)[source] = 1
		check(mover.drop("nugget",source,cell) and furnace.machines[cell]["fuel"] == furnace.FUEL_VALUES[kind] and game.mining.nuggets_at(source) == 0,"Dragging %s consumes one nugget and adds exactly %d fuel" % [kind,furnace.FUEL_VALUES[kind]])
		check(furnace.stored_items(cell).is_empty(),"Consumed %s is fuel rather than stored removable material" % kind)
	furnace.machines[cell]["fuel"] = 38
	var candidates: Array = [{"kind":"coal_3"},{"kind":"coal_2"},{"kind":"coal"},{"kind":"coal"},{"kind":"coal"}]
	var accepted: Array = furnace.plan_inputs(cell,candidates)
	check(accepted.size() == 1 and accepted[0]["kind"] == "coal_3" and furnace.machines[cell]["fuel"] == 38,"Conveyor reservations accept one overflowing coal nugget and reserve the full capacity without mutating real fuel")
	check(furnace.receive(cell,"coal") and furnace.receive(cell,"coal") and furnace.machines[cell]["fuel"] == 40,"Low-tier coal can fill the final two units of capacity")
	for kind: String in furnace.FUEL_VALUES: check(not furnace.receive(cell,kind) and furnace.machines[cell]["fuel"] == 40,"A full furnace rejects extra %s without losing fuel" % kind)
	for kind: String in furnace.FUEL_VALUES:
		furnace.machines[cell]["fuel"] = 39
		game.mining.items_for(kind)[source] = 1
		check(mover.drop("nugget",source,cell) and furnace.machines[cell]["fuel"] == 40 and game.mining.nuggets_at(source) == 0,"Overflowing %s is consumed once, fills the furnace and discards excess fuel" % kind)
	furnace.machines[cell]["fuel"] = 35
	check(furnace.receive(cell,"coal_4") and furnace.machines[cell]["fuel"] == 40,"Thirty-five plus twenty fuel caps at forty and loses fifteen")
	var other := cell + Vector2i.RIGHT
	game.conveyors.place(source,1)
	game.conveyors.place(other,3)
	game.mining.items_for("coal_4")[source] = 1
	game.mining.items_for("coal_4")[other] = 1
	furnace.machines[cell]["fuel"] = 39
	game.conveyors.tick()
	check(furnace.machines[cell]["fuel"] == 40 and game.mining.nuggets_at(source)+game.mining.nuggets_at(other) == 1,"Two incoming belts consume only one oversized coal nugget to finish filling the furnace")
	game.conveyors.tick()
	check(furnace.machines[cell]["fuel"] == 40 and game.mining.nuggets_at(source)+game.mining.nuggets_at(other) == 1,"A full furnace leaves the remaining belt's coal untouched")
	game.queue_free()
	await process_frame
	print("RESULT: %d passed, %d failed; fuel tiers and visible unlock categories" % [passed,failed])
	quit(1 if failed else 0)
