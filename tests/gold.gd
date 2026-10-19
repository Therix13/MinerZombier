extends "res://tests/compactor.gd"

func run_checks() -> void:
	root.show()
	root.size = Vector2i(1280,720)
	Engine.max_fps = 0
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	for child in game.get_children():
		if child.has_method("toggle_pause_menu"):
			child.resolution = Vector2i(1280,720)
			child.window_mode = 0
			child.apply_display(false)
	await settle()
	game.set_process(false)
	game.cycle.skip_tutorial()
	shop = game.shop
	mover = game.get_node("WorldInteractions")
	compactors = game.get_node("Compactors")
	var player: RefCounted = game.progression
	check(player.experience_to_next_level() == 500,"First level requires 500 EXP")
	for i in range(100):
		player.award_sale("coal")
		player.award_sale("gold_2")
	check(player.total_experience == 0,"One hundred raw and tier-two sales do not level the player")
	player.award_sale("gold_4")
	check(player.total_experience == 2,"A valuable tier-four sale grants only 2 EXP")
	for i in range(20): player.add_experience(player.ZOMBIE_EXPERIENCE)
	check(player.level == 2 and player.experience == 2 and player.experience_to_next_level() == 1000,"Zombie kills drive level gains and exponentially larger requirements")
	player.level = 4
	check(not player.visible_researches().has("gold"),"Gold research is hidden below level five")
	player.level = 5
	player.research_points = 2
	check(player.visible_researches().has("gold") and not player.can_research("gold"),"Gold appears at level five but needs iron research")
	player.unlocked["iron"] = true
	check(player.research("gold") and player.research_points == 0,"Iron research and two points unlock gold")
	game.economy.coins = 60000
	shop.open_shop()
	await wait_shop()
	shop.open_category("VETAS")
	check(shop.purchase_buttons.has("gold") and shop.purchase_buttons["gold"].get_meta("price_label").text == "◆ 50000","Gold has a priced purchase card")
	shop.purchase_buttons["gold"].pressed.emit()
	await wait_shop()
	check(mover.placing_gold and game.economy.coins == 60000,"Selecting gold reserves no money")
	var a := Vector2i(14,1)
	var b := Vector2i(15,1)
	check(not mover.place_selected(Vector2i(-999,-999)) and game.economy.coins == 60000,"Invalid gold placement costs nothing")
	check(mover.place_selected(a) and game.mining.vein_at(a) == "gold" and game.economy.coins == 10000,"Valid placement charges exactly 50000")
	for strike in range(10): game.mining.mine(a)
	check(game.mining.nuggets_at(b) == 0,"Gold hardness requires eleven strikes")
	game.mining.mine(a)
	check(game.mining.nugget_type(b) == "gold","Level-one gold veins always produce raw gold")
	for tier in range(1,5):
		check(game.mining.rolled_vein_level(tier,0.49) == tier and game.mining.rolled_vein_level(tier,0.5) == maxi(1,tier-1),"Gold drops obey the same fifty-fifty tier rule at level %d" % tier)
		if tier == 4: continue
		clear_items()
		game.mining.place_vein(a,1,"gold")
		game.mining.place_vein(b,1,"gold")
		game.mining.gold_veins[a]["level"] = tier
		game.mining.gold_veins[b]["level"] = tier
		check(mover.drop("vein",a,b) and game.mining.vein_level(b) == tier+1,"Gold veins fuse into level %d" % (tier+1))
		check(mover.resale_value("vein",b) == 25000 * (1 << tier),"Fused gold veins preserve their combined resale value")
	for form: String in ["gold","gold_ingot"]:
		for tier in range(1,5):
			clear_items()
			var kind: String = form + ("" if tier == 1 else "_" + str(tier))
			put(a,{kind:1})
			put(b,{kind:1})
			check(game.mining.fuse(a,b) == (tier < 4),"Gold form %s supports fusion through level four" % kind)
			check(preload("res://Scripts/saw_manager.gd").lower_tier(kind) == ("" if tier == 1 else form + ("" if tier == 2 else "_"+str(tier-1))),"Gold nuggets and ingots split into their previous tier")
	clear_items()
	var furnace: Node = game.get_node("Furnaces")
	furnace.set_process(false)
	check(furnace.place(b,0),"Gold smelting uses the normal furnace")
	put(a,{"coal_4":1})
	check(mover.drop("nugget",a,b),"A level-four coal nugget fuels the furnace")
	put(a,{"gold_3":1})
	check(not mover.drop("nugget",a,b) and game.mining.nugget_type(a) == "gold_3","Gold smelting rejects lower tiers without consuming them")
	game.mining.items_for("gold_3").clear()
	put(a,{"gold_4":1})
	check(mover.drop("nugget",a,b),"The furnace consumes a tier-four gold nugget")
	furnace.process_smelting(3.9)
	check(game.mining.nuggets_at(b+Vector2i.UP) == 0,"Gold smelting waits four seconds")
	furnace.process_smelting(0.1)
	check(game.mining.nugget_type(b+Vector2i.UP) == "gold_ingot" and furnace.machines[b]["fuel"] == 19,"Smelting emits a gold ingot and consumes one fuel")
	var saw: Node = game.get_node("Saws")
	clear_items()
	saw.set_process(false)
	saw.place(b,0)
	put(a,{"gold_ingot_2":1})
	check(mover.drop("nugget",a,b),"Sierra accepts gold ingots")
	saw.process_cutting(4.0)
	for at: Vector2i in saw.outlet_cells(b,0): check(game.mining.nugget_type(at) == "gold_ingot","Each saw outlet emits one lower-tier gold ingot")
	game.economy.toggle_developer_mode()
	shop.open_shop()
	await wait_shop()
	shop.open_category("RECURSOS")
	for kind: String in game.mining.gold_items: check(shop.resource_buttons.has(kind),"DEV resources expose "+kind)
	if DisplayServer.get_name() != "headless":
		await create_timer(3.2).timeout
		await settle()
		root.get_texture().get_image().save_png("/workspace/.onboarding/display-test/gold-resources.png")
	print("RESULT: ",passed," passed; ",failed," failed; gold and progression")
	game.queue_free()
	await settle()
	quit(0 if failed == 0 else 1)
