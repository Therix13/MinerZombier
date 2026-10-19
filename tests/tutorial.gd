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
	check(cycle.TUTORIAL_DISPLAY_STEPS == 6 and game.economy.coins == 100,"Six lessons start with exactly 100 gold")
	check(not game.get_node("WorldInteractions").select_item("brass"),"Brass remains locked by normal research")
	await purchase_route("VETAS","coal")
	await click_cell(cycle.coal_cell)
	check(cycle.tutorial_step == 1 and game.economy.coins == 0,"First purchase advances to nugget fusion without extra gold")
	await fund_goal(100)
	check(cycle.tutorial_step == 2 and cycle.level4_sold,"Level-four nuggets are made and sold before lesson three")
	await purchase_route("VETAS","coal")
	await click_cell(cycle.next_vein_cell())
	await fuse_veins_to(2)
	check(cycle.tutorial_step == 3 and game.economy.coins == 0,"Second coal vein fuses to level two")
	await fund_goal(200)
	check("Shift" in cycle.tutorial_text(),"Lesson four teaches Shift placement after earning 200 gold")
	await batch_coal(2)
	await fuse_veins_to(3)
	check(cycle.tutorial_step == 4 and game.economy.coins == 0,"Two more veins combine into a level-three vein")
	await fund_goal(400)
	await batch_coal(4)
	await fuse_veins_to(4)
	check(cycle.tutorial_step == 5 and game.economy.coins == 0,"Four additional veins produce a level-four vein")
	check(game.progression.level == 1,"No early tutorial XP gift bypasses research")
	await fund_goal(500)
	check(cycle.tutorial_step == 6 and not cycle.is_tutorial_active(),"Tutorial ends at 500 gold")
	check(game.progression.level == 2 and game.progression.research_points == 1,"Final milestone awards only missing XP to research brass")
	check(not game.progression.has_research("brass") and game.progression.visible_researches().has("brass"),"Brass becomes available for normal research")
	check(not cycle.is_night and not cycle.barrier_broken and game.get_node_or_null("BarrierBreach") == null,"Completing this guide does not automatically start a night")
	check(shop.research_notice.visible and shop.notice_research_ids.has("brass"),"New research announcement appears at the final milestone")
	await create_timer(3.3).timeout
	check(shop.research_notice.visible,"Research announcement persists beyond three seconds")
	var old_progress: int = game.mining.coal_veins[cycle.coal_cell]["progress"]
	await click_cell(cycle.coal_cell)
	check(game.mining.coal_veins[cycle.coal_cell]["progress"] == old_progress,"Announcement blocks mining input behind it")
	check(shop.research_notice.visible and not game.get_node("WorldInteractions").phase_allows(),"Clicking outside the announcement cannot dismiss it or interact with the mine")
	await click_control(shop.research_notice_accept)
	check(not shop.research_notice.visible and shop.notice_research_ids.is_empty(),"Aceptar closes and acknowledges the research announcement")
	check(game.economy.coins == 500 and game.progression.experience == 0,"Final XP boost leaves 500 gold intact and stops at the required level")
	# Research notices remain queued throughout a horde, then still require acceptance.
	cycle.is_night = true
	var queued: Array[String] = ["drill"]
	shop.announce_researches(queued)
	check(not shop.research_notice.visible,"Research notices remain hidden during a horde")
	cycle.is_night = false
	shop.update_notice_visibility()
	check(shop.research_notice.visible,"Queued research appears once the horde ends")
	await click_control(shop.research_notice_accept)
	# Finishing early or skipping should not leave a pointer behind.
	cycle.skip_tutorial()
	await settle()
	check(shop.tutorial_purchase().is_empty(),"No additional tutorial or purchase prompt remains")
	print("RESULT: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)

func fund_goal(goal: int) -> void:
	var count := 0
	while game.economy.coins < goal and count < 1500:
		var targets: Array[Vector2i] = cycle.income_targets()
		if targets.size() == 1:
			for strike in range(5): await click_cell(targets[0])
		else:
			if targets[1] == grid.sale_cell:
				check(game.mining.nugget_type(targets[0]) == "coal_4","Guide sells level-four coal throughout progression")
			await drag_cell(targets[0],targets[1])
		count += 1
	check(count < 1500 and game.economy.coins >= goal,"Actual mining, fusion and sales earn %d gold" % goal)

func batch_coal(count: int) -> void:
	await purchase_route("VETAS","coal")
	await key(KEY_SHIFT,true)
	for i in range(count):
		var at: Vector2i = cycle.next_vein_cell()
		await click_cell(at)
		check(game.mining.coal_veins.has(at),"Shift places each purchased vein")
		if i == 0 and count > 1: check(not cycle.needs_tutorial_income(),"Earned batch budget stays ready after its first purchase")
	await key(KEY_SHIFT,false)
	await settle()
	check(not game.placing_coal,"Releasing Shift cancels the next placement")

func fuse_veins_to(level: int) -> void:
	var count := 0
	while game.mining.vein_level(cycle.coal_cell) < level and count < 12:
		var pair: Array[Vector2i] = cycle.vein_fusion_targets()
		if pair.is_empty(): break
		await drag_cell(pair[0],pair[1])
		count += 1
	check(game.mining.vein_level(cycle.coal_cell) == level,"Actual vein fusion reaches level %d" % level)
