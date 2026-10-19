extends SceneTree

var passed: int = 0
var failed: int = 0
var game: Node2D
var shop: Control
var cycle: RefCounted
var grid: RefCounted

func _initialize() -> void:
	Engine.max_fps = 0
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
	if not shop.shop_open:
		await click_control(shop.shop_button)
		await wait_shop()
	check(shop.shop_open,"The store remains accessible during every lesson")
	if shop.shop_title.text != category:
		if shop.shop_title.text != "TIENDA": await click_control(shop.fixed_back_button)
		await click_control(shop.category_buttons[category])
	await settle()
	check(shop.purchase_buttons.has(item) and not shop.purchase_buttons[item].disabled,"Normal unlock and money rules allow " + item)
	await click_control(shop.purchase_buttons[item])
	await wait_shop()

func research_route() -> void:
	await create_timer(3.2).timeout
	if not shop.shop_open:
		await click_control(shop.shop_button)
		await wait_shop()
	if shop.shop_title.text != "INVESTIGACIÓN":
		if shop.shop_title.text != "TIENDA": await click_control(shop.fixed_back_button)
		await click_control(shop.category_buttons["INVESTIGACIÓN"])
	await settle()
	var id: String = cycle.research_to_learn()
	var points: int = game.progression.research_points
	var price: int = game.progression.RESEARCHES[id]["cost"]
	check(shop.research_buttons.has(id) and not shop.research_buttons[id].disabled,"Milestone EXP makes the real research available: "+id)
	shop.shop_scroll.ensure_control_visible(shop.research_buttons[id])
	await settle()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/workspace/.onboarding/display-test/free-research-"+id+".png")
	await click_control(shop.research_buttons[id])
	check(game.progression.has_research(id) and game.progression.research_points == points - price,"The player spends normal research points to unlock "+id)
	shop.close_shop()
	await wait_shop()

func extract_one() -> void:
	for index in range(game.mining.hardness(game.mining.vein_at(cycle.tutorial_mining_cell()))): await click_cell(cycle.tutorial_mining_cell())

func earn_purchase_money() -> void:
	check(cycle.needs_tutorial_income() and cycle.allows_action("mine_coal") and cycle.allows_action("sell_coal") and not shop.shop_button.disabled, "Insufficient funds give advice while leaving the store accessible")
	var balance: int = game.economy.coins
	var earned: int = 0
	var count: int = 0
	var requested: int = cycle.income_level()

	while cycle.needs_tutorial_income() and count < 300:
		var targets: Array[Vector2i] = cycle.income_targets()
		if targets.size() == 1:
			for strike in range(5): await click_cell(targets[0])
		else:
			if targets[1] == grid.sale_cell:
				check(game.mining.nugget_type(targets[0]) == "coal_" + str(requested), "The guide requests the correct tier for sale")
				earned += game.economy.sale_value("coal_" + str(requested))
			await drag_cell(targets[0], targets[1])
		count += 1
	await settle()
	check(count < 300 and not cycle.needs_tutorial_income() and game.economy.coins == balance + earned and cycle.allows_action("mine_coal"), "Sales fund the next purchase without locking other actions")

func fund_current_vein() -> void:
	var count := 0
	while cycle.needs_tutorial_income() and count < 100:
		var targets: Array[Vector2i] = cycle.income_targets()
		if targets.size() == 1:
			for strike in range(5): await click_cell(targets[0])
		else:
			var selling: bool = targets[1] == grid.sale_cell
			var kind: String = game.mining.nugget_type(targets[0])
			var coins: int = game.economy.coins
			if cycle.tutorial_step == 4 and selling: check(game.mining.ore_level(kind) == cycle.income_level(),"Vein funding requires nugget sales matching the main vein level")
			await drag_cell(targets[0],targets[1])
			if selling: check(game.economy.coins == coins + game.economy.sale_value(kind),"Real guided sales fund the next vein without gifts")
		count += 1
	await settle()
	check(count < 100 and not cycle.needs_tutorial_income(),"The marked mining route can pay for the next vein")

func advance_workshop(step: int) -> void:
	var count := 0
	while cycle.tutorial_step == step and count < 200:
		var targets: Array[Vector2i] = game.get_node("TutorialGuide").targets()
		if targets.size() == 1:
			var material: String = game.mining.vein_at(targets[0])
			check(not material.is_empty(),"Workshop highlights an actual mine")
			for strike in range(game.mining.hardness(material)): await click_cell(targets[0])
		elif targets.size() == 2:
			await drag_cell(targets[0],targets[1])
		else:
			check(step == 7,"Only smelting may wait without a click target")
			if DisplayServer.get_name() != "headless":
				root.get_texture().get_image().save_png("/workspace/.onboarding/display-test/tutorial-smelting.png")
			game.get_node("Furnaces").process_smelting(4.0)
			await settle()
		count += 1
	await settle()
	check(count < 200 and cycle.tutorial_step != step,"The real workshop interactions complete step %d" % step)

func learn_advanced_veins() -> void:
	if DisplayServer.get_name() != "headless":
		await settle()
		root.get_texture().get_image().save_png("/workspace/.onboarding/display-test/vein-level-three-goal.png")
	var purchases := 0
	var merges := 0
	var reached_three := false
	while cycle.advanced_vein_lesson() and purchases < 8:
		check("nivel %d" % (4 if reached_three else 3) in cycle.tutorial_title(),"The lesson explicitly targets level three before level four")
		if cycle.needs_tutorial_income(): await fund_current_vein()
		var pair: Array[Vector2i] = cycle.vein_fusion_targets()
		if pair.size() == 2:
			var tier: int = game.mining.vein_level(pair[0])
			check(game.mining.vein_level(pair[1]) == tier,"The guide only pairs veins of the same tier")
			await drag_cell(pair[0],pair[1])
			check(game.mining.vein_level(pair[1]) == tier + 1,"A real drag creates the next vein tier")
			if pair[1] == cycle.TUTORIAL_COAL_CELL and tier == 2:
				reached_three = true
				check(cycle.tutorial_step == 4 and "nivel 4" in cycle.tutorial_title(),"Reaching vein level three keeps the lesson active and advances its objective to four")
			merges += 1
			if DisplayServer.get_name() != "headless" and pair[1] == cycle.TUTORIAL_COAL_CELL and tier == 2:
				await settle()
				root.get_texture().get_image().save_png("/workspace/.onboarding/display-test/advanced-vein-lesson.png")
		else:
			await purchase_route("VETAS","coal")
			var at: Vector2i = cycle.next_vein_cell()
			await click_cell(at)
			check(game.mining.vein_at(at) == "coal","A paid new vein occupies its marked staging cell")
			purchases += 1
	await settle()
	check(reached_three and purchases == 6 and merges == 6 and cycle.tutorial_step == 5 and game.mining.vein_level(cycle.TUTORIAL_COAL_CELL) == 4,"Six purchased veins and six real merges complete the lesson through levels three and four")
	check(grid.cave_width == 3 and grid.cave_height == 3 and grid.defense_tiles.is_empty(),"The level-four vein lesson needs neither expansion nor defense purchases")

func run_checks() -> void:
	root.show()
	root.size = Vector2i(1280,720)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene_name: String = args[0] if not args.is_empty() else "main.tscn"
	game = load("res://"+scene_name).instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	for child in game.get_children():
		if child.has_method("toggle_pause_menu"):
			child.resolution = Vector2i(1280,720)
			child.window_mode = 0
			child.apply_display(false)
	await settle()
	shop = game.shop
	cycle = game.cycle
	grid = game.grid
	var guide: Node = game.get_node("TutorialGuide")
	check(cycle.tutorial_step == 0 and "Nv. 4" in shop.cycle_goal.get_parsed_text(),"The first card introduces nugget fusion through level four")
	check(not shop.shop_button.disabled and not shop.view_button.disabled,"Shop and view controls remain available from the start")
	await click_control(shop.shop_button)
	await wait_shop()
	for category: String in shop.category_buttons: check(not shop.category_buttons[category].disabled,"Tutorial does not lock menu category "+category)
	await click_control(shop.category_buttons["VETAS"])
	check(not shop.purchase_buttons.has("brass") and not game.get_node("WorldInteractions").select_item("brass"),"Research-locked brass cannot be bought at the start")
	await click_control(shop.purchase_buttons["coal"])
	await wait_shop()
	await key(KEY_R)
	check(game.placement_direction == 2,"Rotation remains available during the tutorial")
	for i in range(3): await key(KEY_R)
	await click_cell(Vector2i(14,1))
	check(cycle.tutorial_step == 1 and cycle.coal_cell == Vector2i(14,1),"Any valid coal placement advances the guide and tracks its location")
	await drag_cell(Vector2i(14,1),cycle.TUTORIAL_COAL_CELL)
	check(cycle.coal_cell == cycle.TUTORIAL_COAL_CELL,"The guide follows a freely moved vein")
	await extract_one()
	await drag_cell(cycle.coal_output(),Vector2i(16,1))
	check(game.mining.nuggets_at(Vector2i(16,1)) == 1,"Loose ore can move away from the suggested tile")
	await drag_cell(Vector2i(16,1),grid.sale_cell)
	for i in range(4):
		await extract_one()
		await drag_cell(cycle.coal_output(),grid.sale_cell)
	check(cycle.tutorial_step == 2 and game.economy.coins == 15,"Five real sales advance the advisory lesson without free gold")
	await extract_one()
	await drag_cell(cycle.coal_output(),cycle.TUTORIAL_FUSION_CELL)
	await extract_one()
	await drag_cell(cycle.coal_output(),cycle.TUTORIAL_FUSION_CELL)
	check(cycle.fusion_taught and "Nv. 4" in cycle.tutorial_text(),"The first real fusion reinforces the full tier progression")
	await drag_cell(cycle.TUTORIAL_FUSION_CELL,grid.sale_cell)
	check(cycle.tutorial_step == 3,"Selling the first refined nugget advances the guide")
	await extract_one()
	var cash: int = game.economy.coins
	await drag_cell(cycle.coal_output(),grid.sale_cell)
	check(game.economy.coins == cash+3,"Lower-tier nuggets remain sellable even while higher-tier sales are suggested")
	await earn_purchase_money()
	await purchase_route("VETAS","coal")
	await click_cell(cycle.TUTORIAL_NEW_VEIN_CELL)
	await drag_cell(cycle.TUTORIAL_NEW_VEIN_CELL,cycle.coal_cell)
	check(cycle.tutorial_step == 4,"A real vein fusion advances the advisory guide")
	guide.focus_objective()
	await settle()
	await learn_advanced_veins()
	check(game.progression.level >= 2 and game.progression.research_points >= 1 and not game.progression.has_research("brass"),"The brass milestone grants missing EXP but does not unlock brass")
	var xp: int = game.progression.total_experience
	for i in range(5): cycle.refresh_tutorial()
	check(game.progression.total_experience == xp,"Milestone EXP is granted once, never on each refresh")
	check(not game.get_node("WorldInteractions").select_item("brass"),"Brass remains locked until the player researches it")
	await research_route()
	if cycle.needs_tutorial_income(): await earn_purchase_money()
	cash = game.economy.coins
	await purchase_route("VETAS","brass")
	await click_cell(cycle.TUTORIAL_BRASS_CELL)
	check(cycle.tutorial_step == 6 and game.economy.coins == cash-500,"Researched brass is bought normally for 500")
	check(not game.progression.has_research("furnace") and not game.get_node("WorldInteractions").select_item("furnace"),"The furnace milestone also preserves its research lock")
	check(game.progression.level >= 3 and game.progression.research_points >= 2,"Furnace EXP covers its prerequisite and its own normal research cost")
	xp = game.progression.total_experience
	for i in range(5): cycle.refresh_tutorial()
	check(game.progression.total_experience == xp,"Furnace XP cannot be farmed by refreshing the guide")
	for attempt in range(3):
		if cycle.research_to_learn().is_empty(): break
		await research_route()
	check(game.progression.has_research("drill") and game.progression.has_research("furnace"),"The player researches the drill prerequisite and then the furnace")
	if cycle.needs_tutorial_income(): await earn_purchase_money()
	cash = game.economy.coins
	await purchase_route("HERRAMIENTAS","furnace")
	await click_cell(cycle.TUTORIAL_FURNACE_CELL)
	check(cycle.furnace_blueprint_exists() and game.economy.coins == cash-350,"The unlocked furnace still costs gold and requires its blueprint materials")
	await advance_workshop(6)
	await advance_workshop(7)
	check(cycle.tutorial_step == 8 and cycle.brass_ingot_sold,"The player smelts and sells a real brass ingot")
	if cycle.needs_tutorial_income(): await earn_purchase_money()
	cash = game.economy.coins
	await purchase_route("DEFENSA","defense_platforms")
	check(cycle.tutorial_step == 9 and game.economy.coins == cash-1000,"Defense platforms still cost 1000")
	if cycle.needs_tutorial_income(): await earn_purchase_money()
	cash = game.economy.coins
	await purchase_route("DEFENSA","launcher")
	await click_cell(grid.defense_cell("left"))
	check(cycle.tutorial_step == 10 and game.economy.coins == cash-200,"The launcher keeps its price")
	await advance_workshop(10)
	check(cycle.tutorial_step == cycle.TUTORIAL_LAST_STEP and game.has_node("BarrierBreach"),"Following the guide still finishes with the fence-collapse cinematic")
	var breach: CanvasLayer = game.get_node("BarrierBreach")
	breach.finish()
	await settle()
	check(cycle.is_night and not cycle.is_tutorial_active(),"The full guided route starts night one")
	game.cycle.lose_night()
	game.queue_free()
	await settle()
	await full_board_regression(scene_name)
	print("RESULT: ",passed," passed; ",failed," failed; free tutorial=",scene_name)
	quit(0 if failed == 0 else 1)

func full_board_regression(scene_name: String) -> void:
	game = load("res://"+scene_name).instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	shop = game.shop
	cycle = game.cycle
	grid = game.grid
	cycle.research_boosts = {"brass":true,"furnace":true}
	game.mining.place_vein(cycle.TUTORIAL_COAL_CELL,1,"coal")
	game.mining.coal_veins[cycle.TUTORIAL_COAL_CELL]["level"] = 4
	game.mining.place_vein(cycle.TUTORIAL_BRASS_CELL,1,"brass")
	var furnace: Node = game.get_node("Furnaces")
	furnace.place(cycle.TUTORIAL_FURNACE_CELL,0)
	furnace.machines[cycle.TUTORIAL_FURNACE_CELL]["fuel"] = 20
	cycle.tutorial_step = 7
	var fixture := {"coal":Vector2i(15,1),"coal_2":Vector2i(15,0),"coal_3":Vector2i(16,0),"brass":Vector2i(15,2),"brass_2":Vector2i(16,2),"brass_3":Vector2i(14,1)}
	for kind: String in fixture: game.mining.items_for(kind)[fixture[kind]] = 1
	cycle.refresh_tutorial()
	game.get_node("TutorialGuide").focus_objective()
	await settle()
	check(cycle.workshop_targets().size() == 2,"A full board produces a space-clearing suggestion instead of a dead end")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/workspace/.onboarding/display-test/free-full-board.png")
	await click_cell(cycle.furnace_cell)
	check(game.get_node("ToolInspector").is_open(),"Tool contents can be inspected during the tutorial")
	game.get_node("ToolInspector").close_inspector()
	var cash: int = game.economy.coins
	await drag_cell(Vector2i(15,0),grid.sale_cell)
	check(game.economy.coins == cash+8 and game.mining.nuggets_at(Vector2i(15,0)) == 0,"The screenshot's loose coal level two can be sold during brass smelting")
	await drag_cell(Vector2i(15,1),grid.sale_cell)
	game.mining.items_for("brass_2")[Vector2i(15,1)] = 1
	await drag_cell(Vector2i(15,1),Vector2i(16,2))
	check(game.mining.nugget_type(Vector2i(16,2)) == "brass_3","The player can also fuse loose nuggets outside the suggested pair")
	await drag_cell(cycle.furnace_cell,Vector2i(15,0))
	check(cycle.furnace_cell == Vector2i(15,0),"Moving a furnace updates the guide's delivery target")
	await drag_cell(cycle.furnace_cell,cycle.TUTORIAL_FURNACE_CELL)
	await advance_workshop(7)
	check(cycle.tutorial_step == 8,"Free selling and fusing recover a full board and finish the smelting lesson")
	cycle.tutorial_step = 4
	game.mining.coal_veins[cycle.coal_cell]["level"] = 3
	grid.purchase_defense_platforms()
	game.launchers.place(grid.defense_cell("left"))
	game.launchers.receive(grid.defense_cell("left"),"brass")
	game.launchers.receive(grid.defense_cell("left"),"brass")
	cycle.refresh_tutorial()
	await settle()
	check(cycle.tutorial_step == 4 and cycle.can_start_night() and shop.cycle_action.visible and not shop.cycle_action.disabled,"The player can start the night before finishing advisory objectives")
	game.queue_free()
	await settle()
