extends "res://tests/tutorial.gd"

func finish_wave() -> void:
	var manager: Node = game.get("zombie_manager")
	manager.set_process(false)
	while manager.spawn_count < manager.wave_total:
		manager.spawn_zombie()
	for enemy in get_nodes_in_group("zombies"):
		enemy.take_damage(100.0)
	manager._process(3.0)
	await settle()

func run_checks() -> void:
	root.show()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene: String = args[0] if not args.is_empty() else "main.tscn"
	game = load("res://" + scene).instantiate()
	if "--legacy" in args: game.set_script(load(OS.get_environment("GODOT_LEGACY_MAIN")))
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	var display: CanvasLayer
	for child in game.get_children():
		if child.has_method("toggle_pause_menu"): display = child
	display.resolution = Vector2i(1280, 720)
	display.window_mode = 0
	display.apply_display(false)
	await settle()
	cycle = game.get("cycle")
	grid = game.get("grid")
	shop = game.get("shop")
	var player: RefCounted = game.get("progression")
	grid.expand()
	grid.purchase_defense_platforms()
	game.get("mining").place_vein(cycle.TUTORIAL_COAL_CELL, 1)
	var platform: Vector2i = grid.defense_cell("left")
	game.get("launchers").place(platform)
	for count in range(5): game.get("launchers").receive(platform, "coal")
	cycle.tutorial_step = cycle.TUTORIAL_LAST_STEP
	game.start_night()
	await finish_wave()
	check(cycle.day == 2 and player.level == 2 and player.research_points == 2, "First victory combines the level-up point with the nightly point")
	check(game.get("night_victory_overlay").visible, "Victory stays visible before the research lesson")
	await click_control(game.get("night_victory_continue_button"))
	check(not game.get("night_victory_overlay").visible and cycle.is_research_tutorial_active(), "Real victory-button input reaches the day-two lesson")
	while game.get("camera_controller").transitioning: await process_frame
	await settle()
	var mine_progress: int = game.get("mining").coal_veins[cycle.TUTORIAL_COAL_CELL]["progress"]
	await click_cell(cycle.TUTORIAL_COAL_CELL)
	check(game.get("mining").coal_veins[cycle.TUTORIAL_COAL_CELL]["progress"] == mine_progress, "Mining clicks cannot skip the mandatory research lesson")
	await drag_cell(cycle.TUTORIAL_COAL_CELL, Vector2i(14, 2))
	check(game.get("mining").coal_veins.has(cycle.TUTORIAL_COAL_CELL) and not game.holding_object, "World dragging stays blocked during the research lesson")
	await key(KEY_P)
	await key(KEY_P, false)
	check(not game.get("camera_controller").defense_view and shop.view_button.disabled, "View shortcuts stay locked until the player researches")
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE, false)
	check(display.menu_open, "Pause remains accessible during the research lesson")
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE, false)
	check(not display.menu_open and cycle.is_research_tutorial_active(), "Resuming preserves the pending research choice")
	game.start_night()
	check(not cycle.is_night and not cycle.start_night(), "Both the controller and cycle refuse the next night before research")
	var coins: int = game.get("economy").coins
	game.buy_coal_vein()
	await settle()
	check(not game.placing_coal and game.get("economy").coins == coins, "Purchases cannot bypass the lesson, including older embedded controllers")
	await click_control(shop.shop_button)
	await wait_shop()
	await click_control(shop.category_buttons["INVESTIGACIÓN"])
	check(not shop.research_buttons["drill"].disabled and not shop.research_buttons["straight_belt"].disabled, "The player can choose either initial item research")
	shop.close_shop()
	await wait_shop()
	check(cycle.is_research_tutorial_active() and not cycle.can_start_night(), "Opening and closing research without spending a point does not finish the lesson")
	await click_control(shop.shop_button)
	await wait_shop()
	await click_control(shop.category_buttons["INVESTIGACIÓN"])
	if DisplayServer.get_name() != "headless" and "--capture" in args:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/workspace/.onboarding/display-test/research-day-two.png")
	await click_control(shop.research_buttons["drill"])
	check(player.has_research("drill") and not player.has_research("straight_belt") and player.research_points == 1, "Choosing the drill spends one point without forcing conveyor research")
	check(not cycle.is_research_tutorial_active() and cycle.can_start_night() and not shop.view_button.disabled, "Either valid choice unlocks normal play and the next night")
	shop.show_categories()
	for category: String in shop.category_buttons:
		check(not shop.category_buttons[category].disabled, "Completing research unlocks category " + category)
	shop.close_shop()
	await wait_shop()
	game.start_night()
	await finish_wave()
	check(cycle.day == 3 and player.level == 2 and player.research_points == 2, "The next victory grants another point even without a new level")
	check(not cycle.research_tutorial_pending, "The research lesson does not repeat on later days")
	cycle.complete_night()
	check(cycle.day == 3 and player.research_points == 2, "Repeated victory notifications cannot duplicate the nightly point")
	game.free()
	await settle()
	print("RESULT: ", passed, " passed; ", failed, " failed; research tutorial=", scene)
	quit(1 if failed else 0)
