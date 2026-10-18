extends SceneTree

var passed: int = 0
var failed: int = 0
var game: Node2D
var shop: Control
var cycle: RefCounted
var grid: RefCounted

func _initialize() -> void:
	Engine.set_meta(&"mine_defense_intro_seen", true)
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS: ", description)
	else:
		failed += 1
		print("FAIL: ", description)

func settle() -> void:
	await process_frame
	await process_frame

func mouse_event(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = pressed
	Input.parse_input_event(event)
	await settle()

func move_mouse(point: Vector2) -> void:
	if DisplayServer.get_name() != "headless":
		Input.warp_mouse(point)
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)
	await settle()

func cell_point(cell: Vector2i) -> Vector2:
	return root.get_screen_transform() * (game.get_global_transform_with_canvas() * grid.get_cell_rect(cell).get_center())

func click_cell(cell: Vector2i) -> void:
	var point: Vector2 = cell_point(cell)
	await move_mouse(point)
	await mouse_event(point, true)
	await mouse_event(point, false)

func drag_cell(source: Vector2i, destination: Vector2i) -> void:
	var point: Vector2 = cell_point(source)
	await move_mouse(point)
	await mouse_event(point, true)
	point = cell_point(destination)
	await move_mouse(point)
	await mouse_event(point, false)

func key(code: Key, pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await settle()

func action_button() -> void:
	var button: Button = shop.get("cycle_action")
	var point: Vector2 = root.get_screen_transform() * (button.get_global_transform_with_canvas() * (button.size * 0.5))
	await move_mouse(point)
	await mouse_event(point, true)
	await mouse_event(point, false)
	await settle()

func click_control(control: Control) -> void:
	var point: Vector2 = root.get_screen_transform() * (control.get_global_transform_with_canvas() * (control.size * 0.5))
	await move_mouse(point)
	await mouse_event(point, true)
	await mouse_event(point, false)
	await settle()

func wait_shop() -> void:
	var deadline: int = Time.get_ticks_msec() + 2000
	while shop.shop_animating and Time.get_ticks_msec() < deadline:
		await process_frame
	await settle()

func purchase_route(category: String, item: String) -> void:
	var guide: Node = game.get_node("TutorialGuide")
	if not shop.shop_open:
		check(guide.pointer.target == shop.shop_button and not shop.shop_button.disabled, "The guide marks the real menu before buying " + item)
		await click_control(shop.shop_button)
		await wait_shop()
		check(shop.shop_open, "The marked menu opens for " + item)
	if shop.shop_title.text != category:
		check(guide.pointer.target == shop.category_buttons[category], "The guide points to the matching category for " + item)
		for other: String in shop.category_buttons:
			if other != category: check(shop.category_buttons[other].disabled, "Unrelated category stays locked: " + other)
		shop.open_category("INVESTIGACIÓN")
		check(shop.shop_title.text == "TIENDA", "Calling an unrelated category cannot bypass the guide")
		await click_control(shop.category_buttons[category])
	await settle()
	check(shop.shop_title.text == category and guide.pointer.target == shop.purchase_buttons[item], "The guide marks the real purchase button for " + item)
	if item == "coal":
		await click_control(shop.fixed_back_button)
		check(shop.shop_title.text == "TIENDA" and guide.pointer.target == shop.category_buttons[category], "Returning to categories restores the matching guide marker")
		await click_control(shop.category_buttons[category])
	for other: String in shop.purchase_buttons:
		if other != item: check(shop.purchase_buttons[other].disabled, "Unrelated store purchase stays locked: " + other)
	if item == "defense_platforms":
		var coins: int = game.economy.coins
		shop.request_item("launcher", shop.launcher_requested)
		check(not game.placing_launcher and game.economy.coins == coins, "A synthetic weapon request cannot skip buying the platforms")
	await click_control(shop.purchase_buttons[item])
	await wait_shop()

func check_locked_actions() -> void:
	var coins: int = game.get("economy").coins
	game.call("buy_brass_vein")
	game.call("buy_drill")
	game.call("buy_junction_conveyor")
	game.call("buy_conveyor")
	game.call("research_technology", "drill")
	# Older built-in controllers have their research locks enforced by the shop.
	await settle()
	check(game.get("economy").coins == coins and not game.get("placing_brass") and not game.get("placing_drill") and not game.get("placing_belt"), "Unrelated purchases spend nothing and do not enter placement")
	check(shop.view_button.disabled and shop.shop_button.disabled == shop.tutorial_purchase().is_empty(), "Only the menu required by the current step is unlocked")
	if shop.tutorial_purchase().is_empty():
		shop.open_shop()
		check(not shop.shop_open, "The store stays locked while mining or loading ammunition")
	check(not game.get("progression").has_research("drill"), "Research cannot bypass the tutorial")

func extract_one() -> void:
	for index in range(7):
		await click_cell(cycle.TUTORIAL_COAL_CELL)

func run_checks() -> void:
	root.show()
	root.size = Vector2i(1280, 720)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene_name: String = args[0] if not args.is_empty() else "main.tscn"
	game = load("res://" + scene_name).instantiate()
	if "--legacy" in args: game.set_script(load(OS.get_environment("GODOT_LEGACY_MAIN")))
	root.add_child(game)
	current_scene = game
	await settle()
	await settle()
	var display: CanvasLayer
	for child in game.get_children():
		if child.has_method("toggle_pause_menu"): display = child
	display.resolution = Vector2i(1280, 720)
	display.window_mode = 0
	display.apply_display(false)
	await settle()
	await settle()
	shop = game.get("shop")
	cycle = game.get("cycle")
	grid = game.get("grid")
	check(cycle.tutorial_step == 0 and cycle.is_tutorial_active(), "Fresh game starts in guided mode")
	check(game.has_node("TutorialGuide"), "Tutorial input guard is installed")
	await check_locked_actions()
	await key(KEY_P)
	await key(KEY_P, false)
	check(not game.get("economy").developer_mode and not game.get("camera_controller").defense_view, "P stays blocked during normal tutorial play")
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE, false)
	check(paused and display.menu_open, "ESC remains available during the tutorial")
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE, false)
	check(not paused, "ESC resumes the guided game")
	shop._on_cycle_action()
	check(not game.placing_coal and game.economy.coins == 500 and not shop.cycle_action.visible, "The tutorial card cannot purchase an item directly")
	await purchase_route("VETAS", "coal")
	check(game.get("placing_coal") and game.get("economy").coins == 500, "The real store selects a coal vein without charging")
	if not game.get("placing_coal"):
		quit(1)
		return
	await click_cell(Vector2i(16, 1))
	check(game.get("placing_coal") and game.get("mining").coal_veins.is_empty(), "Wrong placement cell is blocked without losing the purchase")
	await key(KEY_R)
	await key(KEY_R, false)
	check(game.get("placement_direction") == 1, "Rotation cannot break the guided output direction")
	await key(KEY_SHIFT)
	await click_cell(cycle.TUTORIAL_COAL_CELL)
	await key(KEY_SHIFT, false)
	check(cycle.tutorial_step == 1 and game.get("mining").coal_veins.size() == 1, "Marked cell completes the coal placement step")
	check(not game.get("placing_coal") and game.get("economy").coins == 400, "Shift cannot purchase extra objects during the tutorial")
	await drag_cell(cycle.TUTORIAL_COAL_CELL, Vector2i(16, 1))
	check(game.get("mining").coal_veins.has(cycle.TUTORIAL_COAL_CELL) and game.get("mining").coal_veins.size() == 1, "Dragging the vein cannot move it out of the guided route")
	await extract_one()
	check(game.get("mining").nuggets_at(cycle.TUTORIAL_ORE_CELL) == 1 and cycle.tutorial_step == 1, "Seven real mining clicks produce the tutorial nugget")
	await drag_cell(cycle.TUTORIAL_ORE_CELL, Vector2i(16, 1))
	check(game.get("mining").nuggets_at(cycle.TUTORIAL_ORE_CELL) == 1, "Dropping ore on an unrelated tile preserves it at the source")
	await drag_cell(cycle.TUTORIAL_ORE_CELL, grid.sale_cell)
	check(cycle.tutorial_step == 1 and game.get("economy").coins == 405 and not cycle.expansion_bonus_granted, "One sale does not advance or grant the five-sale bonus")
	for index in range(4):
		await extract_one()
		await drag_cell(cycle.TUTORIAL_ORE_CELL, grid.sale_cell)
		if index < 3:
			check(cycle.tutorial_step == 1 and not cycle.expansion_bonus_granted, "Sale %d still waits for all five nuggets" % (index + 2))
	check(cycle.tutorial_step == 2 and game.get("economy").coins == 925 and cycle.coal_sold == 5, "The fifth sale grants the expansion bonus exactly once")
	await click_cell(cycle.TUTORIAL_COAL_CELL)
	check(game.get("mining").coal_veins[cycle.TUTORIAL_COAL_CELL]["progress"] == 0, "Mining is blocked during the expansion step")
	await purchase_route("EXPANSION", "expansion")
	check(cycle.tutorial_step == 3 and grid.cave_width == 7 and game.get("economy").coins == 425, "Expansion advances directly to defenses without a conveyor step")
	game.call("buy_conveyor")
	await settle()
	check(not game.get("placing_belt") and game.get("conveyors").belts.is_empty(), "Conveyors remain locked throughout the tutorial")
	await purchase_route("DEFENSA", "defense_platforms")
	check(cycle.tutorial_step == 4 and grid.defense_tiles.size() == 2 and game.get("economy").coins == 325, "The store unlocks both defense platforms once")
	await purchase_route("DEFENSA", "launcher")
	check(game.get("placing_launcher") and game.get("economy").coins == 325, "First launcher is free")
	await click_cell(grid.defense_cell("right"))
	check(game.get("launchers").launchers.is_empty() and game.get("placing_launcher"), "Unmarked launcher platform is blocked")
	await click_cell(grid.defense_cell("left"))
	check(cycle.tutorial_step == 5 and not cycle.free_launcher_available, "Marked launcher placement consumes the free launcher and advances")
	await check_locked_actions()
	for index in range(4):
		await extract_one()
		if index == 0:
			await drag_cell(cycle.TUTORIAL_ORE_CELL, grid.sale_cell)
			check(game.get("mining").nuggets_at(cycle.TUTORIAL_ORE_CELL) == 1 and cycle.coal_sold == 5, "Selling is blocked while loading tutorial ammunition")
		await drag_cell(cycle.TUTORIAL_ORE_CELL, grid.defense_cell("left"))
	check(cycle.tutorial_step == 6 and is_equal_approx(cycle.ammo_damage(), 2.0), "Four real mining-and-loading cycles prepare the first night")
	var total_exp: int = game.get("progression").total_experience
	await click_cell(cycle.TUTORIAL_COAL_CELL)
	check(game.get("progression").total_experience == total_exp and game.get("mining").coal_veins[cycle.TUTORIAL_COAL_CELL]["progress"] == 0, "Final tutorial step permits only starting the night")
	await action_button()
	check(cycle.is_night and not cycle.is_tutorial_active(), "Card starts the first wave only after every tutorial step")
	var manager: Node = game.get("zombie_manager")
	manager.set_process(false)
	manager.call("spawn_zombie")
	for enemy in get_nodes_in_group("zombies"):
		enemy.call("take_damage", 100.0)
	manager.call("_process", 3.0)
	await settle()
	await click_control(game.get("night_victory_continue_button"))
	await settle()
	check(cycle.day == 2 and not cycle.is_night and cycle.is_research_tutorial_active() and not shop.get("shop_button").disabled, "Completing the first night starts the mandatory research lesson")
	check(game.get("progression").level == 2 and game.get("progression").research_points == 2, "The first wave grants one level point and one victory point")
	check(not game.get("night_victory_overlay").visible and not shop.cycle_action.visible and shop.view_button.disabled and not cycle.can_start_night(), "Victory can be dismissed while day-two actions wait for a research choice")
	game.call("buy_conveyor")
	await settle()
	check(not game.get("placing_belt"), "The straight conveyor still requires research after the tutorial")
	var guide: Node = game.get_node("TutorialGuide")
	check(guide.pointer.target == shop.shop_button and "2 PI" in shop.cycle_goal.text, "Day two shows available research points and marks the actual menu")
	await click_control(shop.shop_button)
	await wait_shop()
	check(guide.pointer.target == shop.category_buttons["INVESTIGACIÓN"] and not shop.category_buttons["INVESTIGACIÓN"].disabled, "The guide marks the research category")
	for category: String in shop.category_buttons:
		if category != "INVESTIGACIÓN": check(shop.category_buttons[category].disabled, "Day two locks unrelated category: " + category)
	shop.open_category("VETAS")
	check(shop.shop_title.text == "TIENDA", "Direct category calls cannot skip the research lesson")
	await click_control(shop.category_buttons["INVESTIGACIÓN"])
	check(not shop.research_buttons["drill"].disabled and not shop.research_buttons["straight_belt"].disabled, "Both starting research choices are available without forcing a particular item")
	check(not shop.research_buttons.has("junction_belt"), "Higher-level research is absent during the first research lesson")
	shop.technology_requested.emit("junction_belt")
	check(cycle.is_research_tutorial_active() and game.get("progression").research_points == 2, "An invalid research attempt does not complete the lesson or spend points")
	await click_control(shop.research_buttons["straight_belt"])
	check(not cycle.is_research_tutorial_active() and game.get("progression").research_points == 1 and not shop.view_button.disabled, "One chosen unlock completes the lesson and keeps the remaining point")
	shop.close_shop()
	await wait_shop()
	game.call("buy_conveyor")
	check(game.get("placing_belt"), "Buying the conveyor research unlocks its normal store purchase")
	game.call("cancel_placement")
	game.call("buy_coal_vein")
	check(game.get("placing_coal"), "Basic purchases unlock immediately after the tutorial")
	game.call("cancel_placement")
	game.call("buy_brass_vein")
	await settle()
	check(not game.get("placing_brass"), "Advanced purchases still require their item research after the tutorial")
	game.get("progression").add_experience(225)
	game.call("research_technology", "drill")
	game.call("research_technology", "brass")
	game.call("buy_brass_vein")
	check(game.get("placing_brass"), "Research unlocks the advanced purchase after the tutorial")
	game.call("cancel_placement")
	shop.call("open_shop")
	check(shop.get("shop_open"), "Shop navigation unlocks after the tutorial")
	print("RESULT: ", passed, " passed; ", failed, " failed; tutorial=", scene_name)
	quit(1 if failed > 0 else 0)
