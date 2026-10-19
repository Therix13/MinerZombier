extends "res://tests/building_controls.gd"

func run_checks() -> void:
	root.show()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene: String = args[0] if not args.is_empty() else "main.tscn"
	game = load("res://" + scene).instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	game.cycle.skip_tutorial()
	game.grid.expand()
	game.economy.coins = 100000
	for research: String in game.progression.RESEARCHES: game.progression.unlocked[research] = true
	mover = game.get_node("WorldInteractions")
	shop = game.shop
	compactors = game.get_node("Compactors")
	compactors.set_process(false)
	var furnace: Node2D = game.get_node("Furnaces")
	furnace.set_process(false)
	var construction: Node2D = game.get_node("Construction")
	var inspector: CanvasLayer = game.get_node("ToolInspector")
	var a := Vector2i(14,1)
	var b := Vector2i(15,1)
	for item: String in construction.RECIPES:
		clear_items()
		var cash: int = game.economy.coins
		check(mover.select_item(item) and game.economy.coins == cash, item + " selection does not charge")
		check(not mover.place_selected(Vector2i(0,0)) and game.economy.coins == cash, "Invalid placement does not charge")
		check(mover.place_selected(b) and construction.plans.has(b), item + " becomes a blueprint")
		check(game.economy.coins == cash - mover.item_price(item), "Only the placed blueprint charges its gold price")
		check(not game.drills.drills.has(b) and not game.conveyors.belts.has(b) and not compactors.machines.has(b) and not furnace.machines.has(b), "Unfinished machinery is absent from all active simulations")
		check(not game.mining.can_move_nugget(b) and not game.mining.can_place_vein(b) and not game.conveyors.can_place(b) and not game.drills.can_place(b), "Blueprint reserves its tile against all other placement")
		game.mining.items_for("coal")[a] = 1
		check(not mover.drop("nugget",a,b) and game.mining.nugget_type(a) == "coal", "Wrong materials are not consumed")
		game.mining.remove_one_nugget(a,"coal")
		for material: String in construction.RECIPES[item]:
			for index in range(construction.RECIPES[item][material]):
				game.mining.items_for(material)[a] = 1
				check(mover.drop("nugget",a,b) and game.mining.nuggets_at(a) == 0, "A valid delivery is consumed exactly once")
		check(not construction.plans.has(b) and mover.pick_kind(b,Vector2.ZERO) != "", item + " activates only after its complete recipe")
		check(not construction.receive(b,"copper_ingot"), "Completed plans cannot consume another item")
	clear_items()
	check(mover.select_item("furnace") and mover.place_selected(b), "Furnace blueprint placed for inspector")
	game.redraw_world()
	await settle()
	await mouse_move(point(b))
	await mouse_button(point(b),true)
	await mouse_button(point(b),false)
	check(inspector.is_open() and inspector.kind == "blueprint" and inspector.contents.get_child_count() == 1, "Real click opens material requirements in the corner inspector")
	check(not inspector.withdraw("coal_4"), "Plan requirements cannot be withdrawn as free resources")
	game.mining.items_for("coal_4")[a] = 1
	check(mover.drop("nugget",a,b) and construction.plans.has(b), "Partial delivery leaves the furnace inactive")
	inspector.refresh()
	check(inspector.withdraw_buttons["coal_4"].disabled, "Delivered and pending requirements are read-only")
	var paid: int = construction.plans[b]["paid"]
	var cash: int = game.economy.coins
	check(construction.cancel(b) and game.economy.coins == cash + paid and game.mining.nugget_type(b) == "coal_4", "Cancelling returns actual gold and every delivered material")
	check(not construction.cancel(b) and game.economy.coins == cash + paid, "Repeated cancellation cannot duplicate resources or gold")
	inspector.close_inspector()
	clear_items()
	mover.select_item("drill")
	mover.place_selected(b)
	game.conveyors.place(a,1)
	for material: String in ["copper_ingot_3","copper_ingot_3","copper_ingot","copper_ingot"]:
		game.mining.items_for(material)[a] = 1
		game.conveyors.tick()
	check(game.drills.drills.has(b) and game.mining.nuggets_at(a) == 0, "Conveyors can supply a complete construction recipe")
	clear_items()
	game.progression.developer_mode = false
	game.progression.unlocked.erase("iron")
	check(not game.progression.is_item_unlocked("iron"), "Iron vein respects research gating")
	game.progression.level = 4
	game.progression.research_points = 10
	game.progression.unlocked["drill"] = true
	game.progression.unlocked["furnace"] = true
	check(game.progression.research("iron") and game.progression.is_item_unlocked("iron"), "Iron research is available at level four after furnace research")
	check(mover.select_item("iron") and mover.place_selected(a) and game.mining.vein_at(a) == "iron", "Iron vein can be purchased and placed")
	for index in range(9): game.mining.mine(a)
	check(game.mining.nugget_type(b) == "iron", "Nine mining hits produce a raw iron nugget")
	game.mining.remove_one_nugget(b,"iron")
	game.mining.place_vein(b,1,"iron")
	check(mover.drop("vein",a,b) and game.mining.vein_level(b) == 2, "Iron veins fuse like coal and copper")
	clear_items()
	game.mining.items_for("iron")[a] = 1
	game.mining.items_for("iron")[b] = 1
	check(game.mining.fuse(a,b) and game.mining.nugget_type(b) == "iron_2", "Iron nuggets fuse to higher tiers")
	clear_items()
	furnace.place(b,1)
	check(not furnace.receive(b,"iron_3") and furnace.receive(b,"coal_4") and furnace.receive(b,"iron_4"), "Furnace accepts level-four iron with level-four coal fuel")
	furnace.process_smelting(4)
	check(game.mining.nugget_type(Vector2i(16,1)) == "iron_ingot" and furnace.machines[b]["fuel"] == 19, "Smelting emits one iron ingot and spends one unit of fuel")
	game.mining.items_for("iron_ingot")[a] = 1
	check(game.mining.fuse(a,Vector2i(16,1)) and game.mining.nugget_type(Vector2i(16,1)) == "iron_ingot_2", "Iron ingots can fuse for construction")
	clear_items()
	game.economy.developer_mode = true
	game.progression.developer_mode = true
	mover.select_item("furnace")
	mover.place_selected(b)
	cash = game.economy.coins
	check(construction.cancel(b) and game.economy.coins == cash, "Free DEV plans cannot generate refund gold")
	clear_items()
	for index in range(4):
		var at := Vector2i(13+index,2)
		var item: String = ["furnace","drill","compactor","straight"][index]
		mover.select_item(item)
		mover.place_selected(at)
	inspector.open_tool("blueprint",Vector2i(15,2))
	game.mining.place_vein(Vector2i(13,0),1,"iron")
	for tier in range(1,5):
		game.mining.items_for("iron" + ("_"+str(tier) if tier>1 else ""))[Vector2i(13+tier,0)] = 1
		game.mining.items_for("iron_ingot" + ("_"+str(tier) if tier>1 else ""))[Vector2i(13+tier,1)] = 1
	game.redraw_world()
	await settle()
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("/workspace/.onboarding/display-test/construction.png")
	game.free()
	await settle()
	print("RESULT: ",passed," passed; ",failed," failed; blueprints and iron; ",scene)
	quit(1 if failed else 0)
