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
	for attempt in range(30):
		for index in range(5): await click_cell(cycle.TUTORIAL_COAL_CELL)
		if cycle.tutorial_step != 6 or game.mining.nugget_type(cycle.TUTORIAL_ORE_CELL) == "coal": return
		var parking: Array[Vector2i] = game.get_node("TutorialGuide").targets()
		await drag_cell(parking[0],parking[1])

func earn_purchase_money() -> void:
	check(cycle.needs_tutorial_income() and cycle.allows_action("mine_coal") and cycle.allows_action("sell_coal") and shop.shop_button.disabled, "Insufficient funds unlock mining and selling without skipping the purchase")
	var balance: int = game.economy.coins
	var earned: int = 0
	var count: int = 0
	var requested: int = cycle.income_level()
	var mover: Node = game.get_node("WorldInteractions")
	if requested > 2:
		game.economy.coins = 1000
		check(cycle.needs_tutorial_income(), "Even excess coins cannot skip the required level-%d sale" % requested)
		game.economy.coins = balance
		check(not cycle.allows_action("unlock_defense" if requested == 3 else "buy_launcher"), "The requested tier must be sold before its purchase")
		game.mining.coal_nuggets[cycle.TUTORIAL_ORE_CELL] = 1
		check(not mover.drop("nugget", cycle.TUTORIAL_ORE_CELL, grid.sale_cell), "A lower-tier sale cannot bypass the level-%d lesson" % requested)
		game.mining.coal_nuggets.erase(cycle.TUTORIAL_ORE_CELL)
	while cycle.needs_tutorial_income() and count < 300:
		if requested == 2:
			for click in range(5): game.mining.mine(cycle.TUTORIAL_COAL_CELL)
			check(mover.drop("nugget", cycle.TUTORIAL_ORE_CELL, grid.sale_cell), "A mined nugget funds the expansion")
			earned += game.economy.sale_value("coal")
		else:
			var targets: Array[Vector2i] = cycle.income_targets()
			if targets.size() == 1:
				for click in range(5): game.mining.mine(targets[0])
			else:
				if targets[1] == grid.sale_cell:
					check(game.mining.nugget_type(targets[0]) == "coal_" + str(requested), "The guide requests the correct tier for sale")
					earned += game.economy.sale_value("coal_" + str(requested))
				check(mover.drop("nugget", targets[0], targets[1]), "The highlighted level-%d fusion route is playable" % requested)
		count += 1
	await settle()
	check(count < 300 and not cycle.needs_tutorial_income() and game.economy.coins == balance + earned and not cycle.allows_action("mine_coal"), "Only actual tier sales fund the next purchase; its menu then unlocks")

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
	check(not game.placing_coal and game.economy.coins == 100 and not shop.cycle_action.visible, "The tutorial card cannot purchase an item directly")
	await purchase_route("VETAS", "coal")
	check(game.get("placing_coal") and game.get("economy").coins == 100, "The real store selects a coal vein without charging")
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
	check(not game.get("placing_coal") and game.get("economy").coins == 0, "Shift cannot purchase extra objects during the tutorial")
	await drag_cell(cycle.TUTORIAL_COAL_CELL, Vector2i(16, 1))
	check(game.get("mining").coal_veins.has(cycle.TUTORIAL_COAL_CELL) and game.get("mining").coal_veins.size() == 1, "Dragging the vein cannot move it out of the guided route")
	await extract_one()
	check(game.get("mining").nuggets_at(cycle.TUTORIAL_ORE_CELL) == 1 and cycle.tutorial_step == 1, "Five real mining clicks produce the tutorial nugget")
	await drag_cell(cycle.TUTORIAL_ORE_CELL, Vector2i(16, 1))
	check(game.get("mining").nuggets_at(cycle.TUTORIAL_ORE_CELL) == 1, "Dropping ore on an unrelated tile preserves it at the source")
	await drag_cell(cycle.TUTORIAL_ORE_CELL, grid.sale_cell)
	check(cycle.tutorial_step == 1 and game.get("economy").coins == 5 and not cycle.expansion_bonus_granted, "One sale does not advance or grant the five-sale bonus")
	for index in range(4):
		await extract_one()
		await drag_cell(cycle.TUTORIAL_ORE_CELL, grid.sale_cell)
		if index < 3:
			check(cycle.tutorial_step == 1 and not cycle.expansion_bonus_granted, "Sale %d still waits for all five nuggets" % (index + 2))
	check(cycle.tutorial_step == 2 and game.economy.coins == 25 and not cycle.expansion_bonus_granted, "Five sales lead directly to fusion without free coins")
	await extract_one()
	await drag_cell(cycle.TUTORIAL_ORE_CELL, cycle.TUTORIAL_FUSION_CELL)
	check(cycle.tutorial_step == 2 and game.mining.nugget_type(cycle.TUTORIAL_FUSION_CELL) == "coal", "The first nugget waits on the marked fusion tile")
	await extract_one()
	await drag_cell(cycle.TUTORIAL_ORE_CELL, cycle.TUTORIAL_FUSION_CELL)
	check(cycle.fusion_taught and cycle.tutorial_step == 2 and game.mining.nugget_type(cycle.TUTORIAL_FUSION_CELL) == "coal_2", "Fusion stays in its lesson until the more valuable nugget is sold")
	check("15" in cycle.tutorial_text() and "5" in cycle.tutorial_text(), "The lesson compares refined and raw sale prices")
	await drag_cell(cycle.TUTORIAL_FUSION_CELL, grid.sale_cell)
	check(cycle.fusion_sold and cycle.tutorial_step == 3 and game.economy.coins == 40 and cycle.needs_tutorial_income(), "Selling the fused nugget pays only its sale price and opens the income task")
	await earn_purchase_money()
	check(cycle.tutorial_step == 3 and cycle.vein_lesson_active() and grid.cave_width == 3 and game.economy.coins == 100 and not cycle.allows_action("expand"), "The fourth lesson funds the second vein instead of buying an expansion")
	await purchase_route("VETAS","coal")
	await click_cell(cycle.TUTORIAL_NEW_VEIN_CELL)
	check(game.mining.coal_veins.size() == 2 and game.economy.coins == 0 and cycle.tutorial_display_step() == 4,"The second vein is paid for and marked as the fourth lesson")
	await drag_cell(cycle.TUTORIAL_NEW_VEIN_CELL,cycle.TUTORIAL_COAL_CELL)
	check(cycle.vein_fusion_taught and cycle.tutorial_step == 4 and game.mining.vein_level(cycle.TUTORIAL_COAL_CELL) == 2 and game.mining.coal_veins.size() == 1,"A real drag fuses the two veins before defense preparation")
	await earn_purchase_money()
	await purchase_route("DEFENSA", "defense_platforms")
	check(cycle.tutorial_step == 5 and grid.defense_tiles.size() == 2 and game.economy.coins == 35 and cycle.level3_sold, "Platforms are bought with mined sales")
	await earn_purchase_money()
	await purchase_route("DEFENSA", "launcher")
	check(game.placing_launcher and game.economy.coins == 305, "Selecting the launcher reserves no money")
	await click_cell(grid.defense_cell("right"))
	check(game.launchers.launchers.is_empty() and game.placing_launcher and game.economy.coins == 305, "Wrong launcher placement preserves the purchase funds")
	await click_cell(grid.defense_cell("left"))
	check(cycle.tutorial_step == 6 and game.economy.coins == 105 and cycle.level4_sold and not cycle.free_launcher_available, "The first launcher costs 200 at placement")
	await check_locked_actions()
	game.mining.items_for("coal_3")[cycle.TUTORIAL_ORE_CELL] = 1
	var parking: Array[Vector2i] = game.get_node("TutorialGuide").targets()
	var before_sale: int = game.economy.coins
	await drag_cell(parking[0], parking[1])
	check(parking[1] == grid.sale_cell and game.economy.coins == before_sale + game.economy.sale_value("coal_3") and game.mining.nuggets_at(cycle.TUTORIAL_ORE_CELL) == 0, "Surplus high-tier ore is sold during ammunition training to keep the unexpanded mine free")
	var sold: int = cycle.coal_sold
	for index in range(4):
		await extract_one()
		if index == 0:
			await drag_cell(cycle.TUTORIAL_ORE_CELL, grid.sale_cell)
			check(game.mining.nuggets_at(cycle.TUTORIAL_ORE_CELL) == 1 and cycle.coal_sold == sold, "Ammo loading cannot sell the required ammunition")
		await drag_cell(cycle.TUTORIAL_ORE_CELL, grid.defense_cell("left"))
	check(cycle.tutorial_step == cycle.TUTORIAL_LAST_STEP and is_equal_approx(cycle.ammo_damage(), 2.0), "Four raw nuggets complete preparation after the earlier fusion lesson")
	var total_exp: int = game.get("progression").total_experience
	await click_cell(cycle.TUTORIAL_COAL_CELL)
	check(game.get("progression").total_experience == total_exp and game.get("mining").coal_veins[cycle.TUTORIAL_COAL_CELL]["progress"] == 0, "Final tutorial step permits only starting the night")
	check(game.has_node("BarrierBreach") and paused and not cycle.is_night,"Completing the tutorial automatically starts the fence-collapse scene before combat")
	var breach: CanvasLayer = game.get_node("BarrierBreach")
	breach.set_process(false)
	check(not cycle.start_night(),"The first night cannot bypass the fence collapse")
	breach.elapsed = breach.runtime_duration()
	breach.present_frame()
	check(breach.film.barrier.destruction == 1.0,"The fence is visibly destroyed at the end of the second scene")
	breach.finish()
	await settle()
	check(cycle.is_night and cycle.barrier_broken and not paused and not cycle.is_tutorial_active() and grid.cave_width == 3 and grid.cave_height == 3,"The collapse ends directly in the first active wave")
	var night_cash: int = game.economy.coins
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
	check(game.progression.research_points >= 1 and game.economy.coins == night_cash, "Leveling grants research, with no nightly point or gold reward")
	var research_points: int = game.progression.research_points
	check(not game.get("night_victory_overlay").visible and not shop.cycle_action.visible and shop.view_button.disabled and not cycle.can_start_night(), "Victory can be dismissed while day-two actions wait for a research choice")
	game.call("buy_conveyor")
	await settle()
	check(not game.get("placing_belt"), "The straight conveyor still requires research after the tutorial")
	var guide: Node = game.get_node("TutorialGuide")
	check(guide.pointer.target == shop.shop_button and shop.research_texture != null and "PI" not in shop.cycle_goal.get_parsed_text(), "Day two shows available research points and marks the actual menu")
	await click_control(shop.shop_button)
	await wait_shop()
	check(guide.pointer.target == shop.category_buttons["INVESTIGACIÓN"] and not shop.category_buttons["INVESTIGACIÓN"].disabled, "The guide marks the research category")
	for category: String in shop.category_buttons:
		if category != "INVESTIGACIÓN": check(shop.category_buttons[category].disabled, "Day two locks unrelated category: " + category)
	shop.open_category("VETAS")
	check(shop.shop_title.text == "TIENDA", "Direct category calls cannot skip the research lesson")
	await click_control(shop.category_buttons["INVESTIGACIÓN"])
	check(shop.research_buttons.keys() == ["brass"] and not shop.research_buttons["brass"].disabled, "Only the level-two brass vein is available in the initial research lesson")
	check(not shop.research_buttons.has("junction_belt"), "Higher-level research is absent during the first research lesson")
	shop.technology_requested.emit("junction_belt")
	check(cycle.is_research_tutorial_active() and game.get("progression").research_points == research_points, "An invalid research attempt does not complete the lesson or spend points")
	await click_control(shop.research_buttons["brass"])
	check(not cycle.is_research_tutorial_active() and game.get("progression").research_points == research_points - 1 and not shop.view_button.disabled, "One chosen unlock completes the lesson and keeps the remaining point")
	shop.close_shop()
	await wait_shop()
	# Earn normal post-tutorial funds for purchase checks.
	for index in range(40):
		for click in range(5): game.mining.mine(cycle.TUTORIAL_COAL_CELL)
		game.mining.move_nugget(cycle.TUTORIAL_ORE_CELL, grid.sale_cell)
	game.progression.add_experience(80)
	game.research_technology("straight_belt")
	game.call("buy_conveyor")
	check(game.get("placing_belt"), "Buying the conveyor research unlocks its normal store purchase")
	game.call("cancel_placement")
	game.call("buy_coal_vein")
	check(game.get("placing_coal"), "Basic purchases unlock immediately after the tutorial")
	game.call("cancel_placement")
	game.call("buy_drill")
	await settle()
	check(not game.get("placing_drill"), "Advanced purchases still require their item research after the tutorial")
	game.get("progression").add_experience(225)
	game.call("research_technology", "drill")
	game.call("buy_drill")
	check(game.get("placing_drill"), "Research unlocks the advanced purchase after the tutorial")
	game.call("cancel_placement")
	shop.call("open_shop")
	check(shop.get("shop_open"), "Shop navigation unlocks after the tutorial")
	print("RESULT: ", passed, " passed; ", failed, " failed; tutorial=", scene_name)
	quit(1 if failed > 0 else 0)
